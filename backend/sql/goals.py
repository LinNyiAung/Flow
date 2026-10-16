"""Savings / debt / purchase goals. Amounts are exact NUMERIC (returned as float)."""
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import delete, exists, func, insert, select, update

from sql.db import execute, fetch_all, fetch_one, fetch_value, write_returning
from sql.docs import money, row_to_doc, rows_to_docs
from sql.tables import goals as g

_MONEY_FIELDS = ("target_amount", "current_amount")


def _values(fields: Dict[str, Any]) -> Dict[str, Any]:
    values = {("id" if k == "_id" else k): v for k, v in fields.items()}
    for k in _MONEY_FIELDS:
        if k in values and values[k] is not None:
            values[k] = money(values[k])
    return values


async def insert_goal(doc: Dict[str, Any]) -> None:
    await execute(insert(g).values(**_values(doc)))


async def get_goal(goal_id: str, user_id: Optional[str] = None) -> Optional[Dict[str, Any]]:
    stmt = select(g).where(g.c.id == goal_id)
    if user_id is not None:
        stmt = stmt.where(g.c.user_id == user_id)
    return row_to_doc(await fetch_one(stmt))


async def list_goals(user_id: Optional[str] = None, *, status: Optional[str] = None, currency: Optional[str] = None,
                     target_between: Optional[Tuple[datetime, datetime]] = None) -> List[Dict[str, Any]]:
    """Goals newest first, filtered by any of user / status / currency / target-date window."""
    stmt = select(g)
    if user_id is not None:
        stmt = stmt.where(g.c.user_id == user_id)
    if status is not None:
        stmt = stmt.where(g.c.status == status)
    if currency is not None:
        stmt = stmt.where(g.c.currency == currency)
    if target_between is not None:
        stmt = stmt.where(g.c.target_date >= target_between[0], g.c.target_date <= target_between[1])
    return rows_to_docs(await fetch_all(stmt.order_by(g.c.created_at.desc(), g.c.id)))


async def update_goal(goal_id: str, fields: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Apply fields; returns the updated goal (or None if it no longer exists)."""
    return row_to_doc(await write_returning(update(g).where(g.c.id == goal_id).values(**_values(fields)).returning(*g.c)))


async def update_amount_if_unchanged(goal_id: str, original_amount: float, fields: Dict[str, Any]) -> int:
    """Optimistic guard: write only if current_amount is still `original_amount` (exact decimal)."""
    stmt = update(g).where(g.c.id == goal_id, g.c.current_amount == money(original_amount)).values(**_values(fields))
    return await execute(stmt)


async def delete_goal(goal_id: str, user_id: str) -> int:
    return await execute(delete(g).where(g.c.id == goal_id, g.c.user_id == user_id))


async def count_goals(user_id: Optional[str] = None) -> int:
    stmt = select(func.count()).select_from(g)
    if user_id is not None:
        stmt = stmt.where(g.c.user_id == user_id)
    return await fetch_value(stmt)


async def user_has_goals(user_id: str) -> bool:
    return bool(await fetch_value(select(exists().where(g.c.user_id == user_id))))


async def allocated_by_currency(user_id: str) -> List[Dict[str, Any]]:
    """[{"_id": currency, "total_allocated": float}] (sum of current_amount per currency)."""
    rows = await fetch_all(select(g.c.currency.label("_id"), func.sum(g.c.current_amount).label("total_allocated"))
                           .where(g.c.user_id == user_id).group_by(g.c.currency))
    return [{"_id": r["_id"], "total_allocated": float(r["total_allocated"] or 0)} for r in rows]
