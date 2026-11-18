"""Savings / debt / purchase goals. Amounts are exact NUMERIC (returned as float).

A goal's money is its rows in goal_entries: every read here returns current_amount, the sum of the goal's entries
(0.0 with none), so callers see the same goal shape as when it was a stored column."""
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import delete, exists, func, insert, select, update

from sql.db import execute, fetch_all, fetch_one, fetch_value, write_returning
from sql.docs import money, row_to_doc, rows_to_docs
from sql.tables import goal_entries as e
from sql.tables import goals as g

_MONEY_FIELDS = ("target_amount",)

# What the goal holds: the sum of its entries, correlated to the outer goals row (one query for a list of goals).
_CURRENT_AMOUNT = (select(func.coalesce(func.sum(e.c.amount), 0)).where(e.c.goal_id == g.c.id)
                   .correlate(g).scalar_subquery().label("current_amount"))
_GOAL = (*g.c, _CURRENT_AMOUNT)


def _values(fields: Dict[str, Any]) -> Dict[str, Any]:
    values = {("id" if k == "_id" else k): v for k, v in fields.items()}
    for k in _MONEY_FIELDS:
        if k in values and values[k] is not None:
            values[k] = money(values[k])
    return values


async def insert_goal(doc: Dict[str, Any]) -> None:
    await execute(insert(g).values(**_values(doc)))


async def get_goal(goal_id: str, book_id: Optional[str] = None) -> Optional[Dict[str, Any]]:
    stmt = select(*_GOAL).where(g.c.id == goal_id)
    if book_id is not None:
        stmt = stmt.where(g.c.book_id == book_id)
    return row_to_doc(await fetch_one(stmt))


async def list_goals(book_id: Optional[str] = None, *, status: Optional[str] = None, currency: Optional[str] = None,
                     target_between: Optional[Tuple[datetime, datetime]] = None) -> List[Dict[str, Any]]:
    """Goals newest first, filtered by any of book / status / currency / target-date window."""
    stmt = select(*_GOAL)
    if book_id is not None:
        stmt = stmt.where(g.c.book_id == book_id)
    if status is not None:
        stmt = stmt.where(g.c.status == status)
    if currency is not None:
        stmt = stmt.where(g.c.currency == currency)
    if target_between is not None:
        stmt = stmt.where(g.c.target_date >= target_between[0], g.c.target_date <= target_between[1])
    return rows_to_docs(await fetch_all(stmt.order_by(g.c.created_at.desc(), g.c.id)))


async def changed_since(book_id: str, since: datetime) -> bool:
    """True when one of the book's goals was created or edited after `since` (a deleted goal leaves no trace). Only the
    user's own actions move updated_at (editing the goal, adding to or taking from it); no job updates goals."""
    return bool(await fetch_value(select(exists().where(
        g.c.book_id == book_id, (g.c.created_at > since) | (g.c.updated_at > since)))))


async def update_goal(goal_id: str, fields: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Apply fields; returns the updated goal (or None if it no longer exists)."""
    return row_to_doc(await write_returning(update(g).where(g.c.id == goal_id).values(**_values(fields)).returning(*_GOAL)))


async def delete_goal(goal_id: str, book_id: str) -> int:
    return await execute(delete(g).where(g.c.id == goal_id, g.c.book_id == book_id))


async def count_goals(book_id: Optional[str] = None) -> int:
    stmt = select(func.count()).select_from(g)
    if book_id is not None:
        stmt = stmt.where(g.c.book_id == book_id)
    return await fetch_value(stmt)


async def user_has_goals(book_id: str) -> bool:
    return bool(await fetch_value(select(exists().where(g.c.book_id == book_id))))


async def allocated_by_currency(book_id: str) -> List[Dict[str, Any]]:
    """[{"_id": currency, "total_allocated": float}]: the sum of the book's goal entries per currency. Every currency
    the book has a goal in is listed, 0 when its goals hold nothing (the outer join keeps goals without entries)."""
    rows = await fetch_all(select(g.c.currency.label("_id"), func.sum(e.c.amount).label("total_allocated"))
                           .select_from(g.outerjoin(e, e.c.goal_id == g.c.id))
                           .where(g.c.book_id == book_id).group_by(g.c.currency))
    return [{"_id": r["_id"], "total_allocated": float(r["total_allocated"] or 0)} for r in rows]
