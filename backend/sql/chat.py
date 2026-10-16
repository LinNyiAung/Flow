"""AI chat history: one session per user (the latest is used), messages capped per session."""
import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import delete, distinct, func, insert, select, update

from sql.db import execute, fetch_all, fetch_value, transaction
from sql.tables import chat_messages as m, chat_sessions as s


async def append_exchange(user_id: str, messages: List[Dict[str, Any]], keep_last: int, now: datetime) -> None:
    """Append messages to the user's latest session (creating one if needed), keeping only
    the newest `keep_last`. One transaction; the session row is locked so concurrent
    appends from the same user can't interleave their trims."""
    async with transaction() as conn:
        row = (await conn.execute(
            select(s.c.id).where(s.c.user_id == user_id)
            .order_by(s.c.updated_at.desc(), s.c.id).limit(1).with_for_update()
        )).first()
        if row is None:
            session_id = str(uuid.uuid4())
            await conn.execute(insert(s).values(id=session_id, user_id=user_id, created_at=now, updated_at=now))
        else:
            session_id = row.id
            await conn.execute(update(s).where(s.c.id == session_id).values(updated_at=now))
        await conn.execute(insert(m), [{"session_id": session_id, "role": msg["role"], "content": msg["content"],
                                        "timestamp": msg.get("timestamp")} for msg in messages])
        newest = select(m.c.id).where(m.c.session_id == session_id).order_by(m.c.id.desc()).limit(keep_last)
        await conn.execute(delete(m).where(m.c.session_id == session_id, m.c.id.not_in(newest)))


async def history(user_id: str, limit: int) -> List[Dict[str, Any]]:
    """The newest `limit` messages of the user's latest session, oldest first."""
    session_id = await fetch_value(select(s.c.id).where(s.c.user_id == user_id)
                                   .order_by(s.c.updated_at.desc(), s.c.id).limit(1))
    if session_id is None:
        return []
    rows = await fetch_all(select(m.c.role, m.c.content, m.c.timestamp).where(m.c.session_id == session_id)
                           .order_by(m.c.id.desc()).limit(limit))
    return list(reversed(rows))


async def clear(user_id: str) -> int:
    """Delete all of the user's sessions (messages cascade); returns the number of sessions."""
    return await execute(delete(s).where(s.c.user_id == user_id))


async def latest_activity(user_id: str) -> Optional[datetime]:
    return await fetch_value(select(func.max(s.c.updated_at)).where(s.c.user_id == user_id))


async def count_sessions(user_id: Optional[str] = None) -> int:
    stmt = select(func.count()).select_from(s)
    if user_id is not None:
        stmt = stmt.where(s.c.user_id == user_id)
    return await fetch_value(stmt)


async def active_user_ids(since: datetime) -> List[str]:
    rows = await fetch_all(select(distinct(s.c.user_id).label("user_id")).where(s.c.updated_at >= since))
    return [r["user_id"] for r in rows]
