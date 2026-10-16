"""Budgets and their per-category allocations (the old embedded "category_budgets" list).

Documents keep the shape the budget code was written for: a budget dict with a
"category_budgets" list. Writing "category_budgets" replaces the allocation rows in the
same transaction as the budget row.
"""
from datetime import datetime
from typing import Any, Dict, List, Optional, Sequence

from sqlalchemy import delete, exists, func, insert, or_, select, update

from sql.db import execute, fetch_all, fetch_one, fetch_value, transaction
from sql.docs import allocation_rows, budget_doc, budget_row
from sql.tables import budget_allocations as a, budgets as b

_ANY = object()
RUNNING_OR_UPCOMING = ("upcoming", "active", "exceeded")


def _values(fields: Dict[str, Any]) -> Dict[str, Any]:
    values = budget_row({k: getattr(v, "value", v) for k, v in fields.items()})
    values.pop("id", None)
    return values


async def _docs(rows: Sequence[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Attach allocations to budget rows (one query for all of them)."""
    if not rows:
        return []
    allocations: Dict[str, List[Dict[str, Any]]] = {r["id"]: [] for r in rows}
    for alloc in await fetch_all(select(a).where(a.c.budget_id.in_(list(allocations)))):
        allocations[alloc["budget_id"]].append(alloc)
    return [budget_doc(r, allocations[r["id"]]) for r in rows]


async def _list(stmt) -> List[Dict[str, Any]]:
    return await _docs(await fetch_all(stmt))


# ------------------------------------------------------------------ reads
async def get_budget(budget_id: str, user_id: Optional[str] = None) -> Optional[Dict[str, Any]]:
    stmt = select(b).where(b.c.id == budget_id)
    if user_id is not None:
        stmt = stmt.where(b.c.user_id == user_id)
    docs = await _list(stmt)
    return docs[0] if docs else None


async def budget_currency(budget_id: str) -> Optional[str]:
    return await fetch_value(select(b.c.currency).where(b.c.id == budget_id))


async def list_budgets(user_id: str, *, currency: Optional[str] = None,
                       period: Optional[str] = None) -> List[Dict[str, Any]]:
    """The user's budgets, newest first."""
    stmt = select(b).where(b.c.user_id == user_id)
    if currency is not None:
        stmt = stmt.where(b.c.currency == currency)
    if period is not None:
        stmt = stmt.where(b.c.period == period)
    return await _list(stmt.order_by(b.c.created_at.desc(), b.c.id))


async def budgets_overlapping(user_id: str, start: datetime, end: datetime,
                              currency: Optional[str] = None) -> List[Dict[str, Any]]:
    """Budgets whose window overlaps [start, end] (start == end: windows containing that moment), newest first."""
    stmt = select(b).where(b.c.user_id == user_id, b.c.start_date <= end, b.c.end_date >= start)
    if currency is not None:
        stmt = stmt.where(b.c.currency == currency)
    return await _list(stmt.order_by(b.c.created_at.desc(), b.c.id))


async def has_budget_containing(user_id: str, moment: datetime) -> bool:
    return bool(await fetch_value(select(exists().where(
        b.c.user_id == user_id, b.c.start_date <= moment, b.c.end_date >= moment))))


async def count_budgets(user_id: Optional[str] = None) -> int:
    stmt = select(func.count()).select_from(b)
    if user_id is not None:
        stmt = stmt.where(b.c.user_id == user_id)
    return await fetch_value(stmt)


async def find_child(user_id: str, parent_id: str) -> Optional[Dict[str, Any]]:
    """{"_id": ...} of a budget auto-created from parent_id, or None."""
    row = await fetch_one(select(b.c.id).where(b.c.user_id == user_id, b.c.parent_budget_id == parent_id).limit(1))
    return {"_id": row["id"]} if row else None


async def find_existing_next(user_id: str, parent_id: str, name: str, period: str, currency: str,
                             day_start: datetime, day_end: datetime) -> Optional[Dict[str, Any]]:
    """A child of parent_id, or a same name/period/currency budget starting in [day_start, day_end)."""
    row = await fetch_one(select(b.c.id, b.c.parent_budget_id).where(
        b.c.user_id == user_id,
        or_(b.c.parent_budget_id == parent_id,
            (b.c.name == name) & (b.c.period == period) & (b.c.currency == currency)
            & (b.c.start_date >= day_start) & (b.c.start_date < day_end)),
    ).limit(1))
    return {"_id": row["id"], "parent_budget_id": row["parent_budget_id"]} if row else None


async def rollover_candidates(wall_now: datetime) -> List[Dict[str, Any]]:
    """Auto-create budgets whose period ended and that have no next budget yet."""
    return await _list(select(b).where(b.c.auto_create_enabled.is_(True), b.c.end_date < wall_now,
                                       b.c.rolled_over_to.is_(None)).order_by(b.c.end_date, b.c.id))


async def ending_soon_candidates(wall_now: datetime, window_start: datetime, window_end: datetime) -> List[Dict[str, Any]]:
    return await _list(select(b).where(
        b.c.status.in_(RUNNING_OR_UPCOMING), b.c.start_date <= wall_now,
        b.c.end_date >= window_start, b.c.end_date <= window_end, b.c.ending_soon_notified.is_(False),
    ).order_by(b.c.end_date, b.c.id))


async def now_active_candidates(lookback_start: datetime, wall_now: datetime) -> List[Dict[str, Any]]:
    return await _list(select(b).where(
        b.c.status.in_(RUNNING_OR_UPCOMING), b.c.started_notified.is_(False),
        b.c.start_date >= lookback_start, b.c.start_date <= wall_now, b.c.end_date >= wall_now,
    ).order_by(b.c.start_date, b.c.id))


# ------------------------------------------------------------------ writes
async def insert_budget(doc: Dict[str, Any]) -> None:
    """Budget + allocations, all-or-nothing. A second child of the same parent for the same
    start date violates uq_budgets_rollover_child (sqlalchemy IntegrityError)."""
    row = budget_row({k: getattr(v, "value", v) for k, v in doc.items()})
    async with transaction() as conn:
        await conn.execute(insert(b).values(**row))
        allocations = allocation_rows(row["id"], doc.get("category_budgets") or [])
        if allocations:
            await conn.execute(insert(a), allocations)


async def update_budget(budget_id: str, fields: Dict[str, Any], *, user_id: Optional[str] = None,
                        expected_updated_at: Any = _ANY) -> int:
    """Apply fields (incl. "category_budgets", which replaces the allocations). With
    expected_updated_at, only writes if the budget was not modified since (optimistic lock).
    Returns the number of budgets updated (0 or 1)."""
    fields = dict(fields)
    categories = fields.pop("category_budgets", None)
    stmt = update(b).where(b.c.id == budget_id)
    if user_id is not None:
        stmt = stmt.where(b.c.user_id == user_id)
    if expected_updated_at is not _ANY:
        stmt = stmt.where(b.c.updated_at == expected_updated_at)
    values = _values(fields)
    if not values:
        raise ValueError("update_budget needs at least one budget field (e.g. updated_at)")
    async with transaction() as conn:
        updated = (await conn.execute(stmt.values(**values))).rowcount
        if updated and categories is not None:
            await conn.execute(delete(a).where(a.c.budget_id == budget_id))
            allocations = allocation_rows(budget_id, categories)
            if allocations:
                await conn.execute(insert(a), allocations)
    return updated


async def delete_budget(budget_id: str, user_id: str) -> int:
    """Delete a budget (its allocations cascade; a parent's rolled_over_to pointing at it is cleared)."""
    return await execute(delete(b).where(b.c.id == budget_id, b.c.user_id == user_id))


_FLAGS = {"started_notified", "ending_soon_notified"}


async def claim_flag(budget_id: str, flag: str, now: datetime) -> bool:
    """Atomically set a one-time notification flag; False if it was already set."""
    assert flag in _FLAGS
    stmt = update(b).where(b.c.id == budget_id, b.c[flag].is_(False)).values({flag: True, f"{flag}_at": now})
    return await execute(stmt) > 0


async def release_flag(budget_id: str, flag: str) -> None:
    assert flag in _FLAGS
    await execute(update(b).where(b.c.id == budget_id).values({flag: False, f"{flag}_at": None}))


async def claim_auto_create(budget_id: str, now: datetime, stale_before: datetime) -> bool:
    """Claim the right to create budget_id's next budget (stale claims expire)."""
    stmt = update(b).where(b.c.id == budget_id, or_(b.c.auto_create_claimed_at.is_(None),
                                                     b.c.auto_create_claimed_at < stale_before))
    return await execute(stmt.values(auto_create_claimed_at=now)) > 0


async def release_auto_create(budget_id: str) -> None:
    await execute(update(b).where(b.c.id == budget_id).values(auto_create_claimed_at=None))


async def set_rolled_over(budget_id: str, child_id: str) -> None:
    await execute(update(b).where(b.c.id == budget_id).values(rolled_over_to=child_id))
