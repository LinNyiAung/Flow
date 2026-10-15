"""Stored AI insights (weekly / monthly, per provider). Content is guaranteed non-blank by the schema."""
from typing import Any, Dict, Optional

from sqlalchemy import delete, insert, select, update

from sql.db import execute, fetch_one
from sql.docs import insight_doc, insight_row
from sql.tables import insights as i


async def insert_insight(doc: Dict[str, Any]) -> None:
    await execute(insert(i).values(**insight_row(doc)))


async def latest(user_id: str, ai_provider: str, insight_type: str, real_only: bool = False) -> Optional[Dict[str, Any]]:
    """Latest stored insight for provider/type; real_only skips placeholders."""
    stmt = select(i).where(i.c.user_id == user_id, i.c.ai_provider == ai_provider, i.c.insight_type == insight_type)
    if real_only:
        stmt = stmt.where(i.c.is_placeholder.is_(False))
    return insight_doc(await fetch_one(stmt.order_by(i.c.generated_at.desc(), i.c.id).limit(1)))


async def set_translation(insight_id: str, content_mm: str) -> None:
    await execute(update(i).where(i.c.id == insight_id).values(content_mm=content_mm))


async def delete_for_user(user_id: str, ai_provider: Optional[str] = None, insight_type: Optional[str] = None) -> int:
    stmt = delete(i).where(i.c.user_id == user_id)
    if ai_provider:
        stmt = stmt.where(i.c.ai_provider == ai_provider)
    if insight_type:
        stmt = stmt.where(i.c.insight_type == insight_type)
    return await execute(stmt)
