"""In-app notifications."""
from datetime import date, datetime
from typing import Any, Dict, Iterable, List, Optional, Union

from sqlalchemy import and_, delete, exists as sql_exists, func, insert, or_, select, update

from sql.db import execute, fetch_all, fetch_value, transaction
from sql.docs import rows_to_docs
from sql.tables import notifications as n

_COLUMNS = {c.name for c in n.columns}


def _row(doc: Dict[str, Any]) -> Dict[str, Any]:
    row = {("id" if k == "_id" else k): v for k, v in doc.items() if ("id" if k == "_id" else k) in _COLUMNS}
    if isinstance(row.get("reminder_target_date"), str):  # stored as "YYYY-MM-DD" by the code
        row["reminder_target_date"] = date.fromisoformat(row["reminder_target_date"])
    return row


async def insert_notification(doc: Dict[str, Any]) -> None:
    await execute(insert(n).values(**_row(doc)))


async def insert_many(docs: Iterable[Dict[str, Any]]) -> int:
    rows = [_row(d) for d in docs]
    if not rows:
        return 0
    async with transaction() as conn:
        await conn.execute(insert(n), rows)
    return len(rows)


async def list_for_user(user_id: str, unread_only: bool, limit: int) -> List[Dict[str, Any]]:
    stmt = select(n).where(n.c.user_id == user_id)
    if unread_only:
        stmt = stmt.where(n.c.is_read.is_(False))
    return rows_to_docs(await fetch_all(stmt.order_by(n.c.created_at.desc(), n.c.id).limit(limit)))


async def mark_read(user_id: str, notification_id: str) -> int:
    """Matched rows (already-read still counts, so the call stays idempotent)."""
    return await execute(update(n).where(n.c.id == notification_id, n.c.user_id == user_id).values(is_read=True))


async def mark_all_read(user_id: str) -> int:
    return await execute(update(n).where(n.c.user_id == user_id, n.c.is_read.is_(False)).values(is_read=True))


async def delete_notification(user_id: str, notification_id: str) -> int:
    return await execute(delete(n).where(n.c.id == notification_id, n.c.user_id == user_id))


async def unread_count(user_id: str) -> int:
    return await fetch_value(select(func.count()).select_from(n).where(n.c.user_id == user_id, n.c.is_read.is_(False)))


async def count_all() -> int:
    return await fetch_value(select(func.count()).select_from(n))


async def exists(user_id: str, types: Union[str, Iterable[str]], *, goal_id: Optional[str] = None,
                 goal_name: Optional[str] = None, currency: Optional[str] = None,
                 since: Optional[datetime] = None) -> bool:
    """De-duplication check: a notification of these type(s) (optionally for this goal/budget id,
    name, currency) exists for the user (optionally created at or after `since`)."""
    type_list = [types] if isinstance(types, str) else list(types)
    conds = [n.c.user_id == user_id, n.c.type.in_(type_list)]
    if goal_id is not None:
        conds.append(n.c.goal_id == goal_id)
    if goal_name is not None:
        conds.append(n.c.goal_name == goal_name)
    if currency is not None:
        conds.append(n.c.currency == currency)
    if since is not None:
        conds.append(n.c.created_at >= since)
    return bool(await fetch_value(select(sql_exists().where(*conds))))


async def approaching_reminder_exists(user_id: str, goal_id: str, threshold: int, target_key: str,
                                      since: datetime) -> bool:
    """goal_approaching_date already sent for this threshold+target date, or any one since `since`."""
    target = date.fromisoformat(target_key) if isinstance(target_key, str) else target_key
    stmt = select(sql_exists().where(
        n.c.user_id == user_id, n.c.goal_id == goal_id, n.c.type == "goal_approaching_date",
        or_(and_(n.c.reminder_threshold == threshold, n.c.reminder_target_date == target), n.c.created_at >= since),
    ))
    return bool(await fetch_value(stmt))
