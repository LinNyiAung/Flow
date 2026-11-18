"""A goal's money: one row per movement into or out of a goal. What a goal holds is the sum of its entries (sql.goals
computes it); entries are never edited or deleted on their own, only with their goal. Amounts are exact NUMERIC,
signed (a withdraw is negative), returned as float.
"""
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from sqlalchemy import exists, func, insert, select

from sql.db import execute, fetch_all, fetch_value
from sql.docs import money, rows_to_docs
from sql.tables import goal_entries as e

KIND_START = "start"  # the initial contribution when the goal was created
KIND_ADD = "add"
KIND_WITHDRAW = "withdraw"
KIND_CARRIED_OVER = "carried_over"  # the goal's balance when history began (the goal entries migration)


async def add_entry(goal_id: str, kind: str, amount, added_by_member_id: Optional[str]) -> None:
    """Record one movement; `amount` is signed (negative for a withdraw) and rounded to cents.

    created_at is the clock time of this call, not the server default now() (the transaction's start): callers hold the
    book's money lock here, so entry order follows the order the movements were made in, across workers.
    """
    await execute(insert(e).values(id=str(uuid.uuid4()), goal_id=goal_id, kind=kind, amount=money(amount),
                                   added_by_member_id=added_by_member_id, created_at=datetime.now(timezone.utc)))


async def list_entries(goal_id: str, limit: int, offset: int) -> List[Dict[str, Any]]:
    """A page of the goal's entries: created_at descending, then id descending (a stable order for paging)."""
    rows = await fetch_all(select(e).where(e.c.goal_id == goal_id)
                           .order_by(e.c.created_at.desc(), e.c.id.desc()).limit(limit).offset(offset))
    return rows_to_docs(rows)


async def count_entries(goal_id: str) -> int:
    return await fetch_value(select(func.count()).select_from(e).where(e.c.goal_id == goal_id))


async def member_has_entries(member_id: str) -> bool:
    """Whether any goal entry records this family member."""
    return bool(await fetch_value(select(exists().where(e.c.added_by_member_id == member_id))))
