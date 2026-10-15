"""User feedback (submitted from the app, managed in the admin panel)."""
from typing import Any, Dict, List, Optional

from sqlalchemy import case, delete, func, insert, select, update

from sql.db import execute, fetch_all, fetch_one
from sql.docs import rows_to_docs
from sql.tables import feedback


async def insert_feedback(doc: Dict[str, Any]) -> None:
    await execute(insert(feedback).values(**{("id" if k == "_id" else k): v for k, v in doc.items()}))


async def list_feedback(category: Optional[str], status: Optional[str], skip: int, limit: int) -> List[Dict[str, Any]]:
    stmt = select(feedback)
    if category:
        stmt = stmt.where(feedback.c.category == category)
    if status:
        stmt = stmt.where(feedback.c.status == status)
    stmt = stmt.order_by(feedback.c.created_at.desc(), feedback.c.id).offset(skip).limit(limit)
    return rows_to_docs(await fetch_all(stmt))


async def stats() -> Dict[str, Any]:
    def count(value: str):
        return func.count(case((feedback.c.status == value, 1)))

    row = await fetch_one(select(
        func.count().label("total"),
        count("pending").label("pending"),
        count("reviewed").label("reviewed"),
        count("resolved").label("resolved"),
        func.avg(feedback.c.rating).label("average_rating"),  # NULL ratings are ignored
    ))
    return row or {"total": 0, "pending": 0, "reviewed": 0, "resolved": 0, "average_rating": None}


async def set_status(feedback_id: str, status: str) -> int:
    """Row count of matched feedback (setting the same status again still counts)."""
    return await execute(update(feedback).where(feedback.c.id == feedback_id).values(status=status))


async def delete_feedback(feedback_id: str) -> int:
    return await execute(delete(feedback).where(feedback.c.id == feedback_id))
