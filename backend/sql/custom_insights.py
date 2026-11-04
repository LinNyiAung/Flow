"""Custom insights (Pro): AI reports on a date range the user picks.

A row is created `pending` (at most one per user: a partial unique index) and leaves `pending` exactly once, to `ready`,
`failed` or `refused`. Whoever moves the row out of pending (the job that wrote the report, or the sweeper that gave up
on it) owns the quota give-back and the notification, so finish() and fail_stuck() only touch pending rows.

Every function returns documents in the shape of sql.docs.row_to_doc: `_id` for `id`, `start_date` / `end_date` as `date`,
`figures` a dict (or None), `counter_keys` a list of [feature, period, "YYYY-MM-DD"] lists.
"""
from datetime import date, datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import delete, func, null, select, text, update
from sqlalchemy.dialects.postgresql import insert as pg_insert

from sql.db import execute, fetch_all, fetch_one, fetch_value, transaction, write_returning
from sql.docs import row_to_doc
from sql.tables import custom_insights

_c = custom_insights.c
_ATTEMPT_STATUSES = ("failed", "refused")


async def insert_pending(doc: Dict[str, Any]) -> bool:
    """Create a pending report. False when the user already has a pending one (nothing is written).

    `doc` follows the convention of sql.insights.insert_insight: the report id under `_id`, the other keys are column
    names. Keys: `_id`, `user_id`, `start_date`, `end_date` (date), `preset`, `instruction`, `instruction_key`,
    `counter_keys` (list of [feature, period, "YYYY-MM-DD"]), and optionally `figures`, `created_at` (an aware datetime;
    the database's now() when left out). `status` is always 'pending'.
    """
    row = {("id" if k == "_id" else k): v for k, v in doc.items() if k != "status"}
    row["status"] = "pending"
    if row.get("figures") is None:
        row.pop("figures", None)  # a plain None would be stored as the JSON value null, not SQL NULL
    stmt = pg_insert(custom_insights).values(**row).on_conflict_do_nothing(
        # The predicate must be a literal (not a bind parameter) for Postgres to match it to the partial index.
        index_elements=[_c.user_id], index_where=text("status = 'pending'"))
    return await execute(stmt) == 1


async def get(report_id: str, user_id: Optional[str] = None, include_deleted: bool = False) -> Optional[Dict[str, Any]]:
    stmt = select(custom_insights).where(_c.id == report_id)
    if user_id is not None:
        stmt = stmt.where(_c.user_id == user_id)
    if not include_deleted:
        stmt = stmt.where(_c.deleted_at.is_(None))
    return row_to_doc(await fetch_one(stmt))


async def list_for_user(user_id: str, limit: int = 100) -> List[Dict[str, Any]]:
    """The user's reports (any status), newest first, hidden ones left out."""
    stmt = (select(custom_insights).where(_c.user_id == user_id, _c.deleted_at.is_(None))
            .order_by(_c.created_at.desc(), _c.id.desc()).limit(limit))
    return [row_to_doc(r) for r in await fetch_all(stmt)]


async def list_summaries(user_id: str, limit: int = 100) -> List[Dict[str, Any]]:
    """list_for_user without the text and figures (they can be large): only the summary columns, plus `has_myanmar`
    (whether content_mm is stored)."""
    stmt = (select(_c.id, _c.start_date, _c.end_date, _c.preset, _c.instruction, _c.status, _c.created_at,
                   _c.completed_at, (_c.content_mm.is_not(None) & (_c.content_mm != "")).label("has_myanmar"))
            .where(_c.user_id == user_id, _c.deleted_at.is_(None))
            .order_by(_c.created_at.desc(), _c.id.desc()).limit(limit))
    return [row_to_doc(r) for r in await fetch_all(stmt)]


async def has_pending(user_id: str) -> bool:
    return bool(await fetch_value(select(func.count()).select_from(custom_insights)
                                  .where(_c.user_id == user_id, _c.status == "pending")))


async def find_ready_match(user_id: str, start_date: date, end_date: date, instruction_key: str) -> Optional[Dict[str, Any]]:
    """The newest ready, not-deleted report with exactly these dates and instruction_key."""
    stmt = (select(custom_insights)
            .where(_c.user_id == user_id, _c.status == "ready", _c.deleted_at.is_(None), _c.start_date == start_date,
                   _c.end_date == end_date, _c.instruction_key == instruction_key)
            .order_by(_c.created_at.desc(), _c.id.desc()).limit(1))
    return row_to_doc(await fetch_one(stmt))


async def count_attempts_since(user_id: str, since: datetime) -> int:
    """Failed and refused reports created at or after `since`. Hidden (deleted) ones count too."""
    return await fetch_value(select(func.count()).select_from(custom_insights).where(
        _c.user_id == user_id, _c.status.in_(_ATTEMPT_STATUSES), _c.created_at >= since)) or 0


async def finish(report_id: str, *, status: str, now: datetime, content: Optional[str] = None,
                 ai_provider: Optional[str] = None, ai_model: Optional[str] = None,
                 input_tokens: Optional[int] = None, output_tokens: Optional[int] = None) -> Optional[Dict[str, Any]]:
    """pending -> ready / failed / refused. None when the report is no longer pending (somebody else finished it).
    Raises ValueError for any other status."""
    if status not in ("ready", "failed", "refused"):
        raise ValueError(f"finish: status must be ready, failed or refused, not {status!r}")
    stmt = (update(custom_insights).where(_c.id == report_id, _c.status == "pending")
            .values(status=status, completed_at=now, content=content, ai_provider=ai_provider, ai_model=ai_model,
                    input_tokens=input_tokens, output_tokens=output_tokens)
            .returning(*custom_insights.c))
    return row_to_doc(await write_returning(stmt))


async def fail_stuck(before: datetime, now: datetime) -> List[Dict[str, Any]]:
    """Every report still pending that was created before `before` -> failed (completed_at = now), in one UPDATE.
    Returns the rows it moved, so each is given back / notified once."""
    stmt = (update(custom_insights).where(_c.status == "pending", _c.created_at < before)
            .values(status="failed", completed_at=now).returning(*custom_insights.c))
    async with transaction():
        rows = await fetch_all(stmt)
    return [row_to_doc(r) for r in rows]


async def set_translation(report_id: str, content_mm: str) -> bool:
    """Store the Myanmar text of a ready, not-deleted report that has none yet. True when this call wrote it; False when
    the report already had a translation (the first one stays), is not ready or is hidden."""
    stmt = (update(custom_insights)
            .where(_c.id == report_id, _c.status == "ready", _c.deleted_at.is_(None), _c.content_mm.is_(None))
            .values(content_mm=content_mm))
    return await execute(stmt) == 1


async def delete_for_user(report_id: str, user_id: str, now: datetime) -> str:
    """A user deletes one of their reports. Returns
      "deleted"  a ready report is removed;
      "hidden"   a failed / refused report is kept so it still counts as an attempt: deleted_at = now and its
                 instruction, preset, content, content_mm and figures are cleared;
      "pending"  the report is still being written: nothing changed;
      "missing"  no such report for this user (or it was hidden already).
    """
    async with transaction():
        row = await fetch_one(select(_c.status).where(_c.id == report_id, _c.user_id == user_id, _c.deleted_at.is_(None))
                              .with_for_update())
        if row is None:
            return "missing"
        if row["status"] == "ready":
            await execute(delete(custom_insights).where(_c.id == report_id))
            return "deleted"
        if row["status"] in _ATTEMPT_STATUSES:
            await execute(update(custom_insights).where(_c.id == report_id)
                          # null(): a plain None would be stored as the JSON value null, not SQL NULL
                          .values(deleted_at=now, instruction=None, preset=None, content=None, content_mm=None,
                                  instruction_key="", figures=null()))
            return "hidden"
        return "pending"
