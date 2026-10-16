"""Per-user notification preferences (one row per user; preferences is a JSON map of type -> bool)."""
from datetime import datetime
from typing import Any, Dict, Optional

from sqlalchemy import cast, delete, select
from sqlalchemy.dialects.postgresql import JSONB, insert

from sql.db import execute, fetch_one, write_returning
from sql.tables import notification_preferences as np


async def get(user_id: str) -> Optional[Dict[str, Any]]:
    return await fetch_one(select(np).where(np.c.user_id == user_id))


async def get_or_create(user_id: str, defaults: Dict[str, bool], now: datetime) -> Dict[str, Any]:
    """The user's row, creating it with the defaults first if missing (race-free)."""
    await execute(insert(np).values(user_id=user_id, preferences=defaults, created_at=now, updated_at=now)
                  .on_conflict_do_nothing(index_elements=[np.c.user_id]))
    return await get(user_id)


async def merge(user_id: str, defaults: Dict[str, bool], changes: Dict[str, bool], now: datetime) -> Dict[str, Any]:
    """Apply `changes` atomically on top of the stored map (or of the defaults if no row yet)."""
    stmt = (insert(np).values(user_id=user_id, preferences={**defaults, **changes}, created_at=now, updated_at=now)
            .on_conflict_do_update(index_elements=[np.c.user_id],
                                   set_={"preferences": np.c.preferences.op("||")(cast(changes, JSONB)),
                                         "updated_at": now})
            .returning(*np.c))
    return await write_returning(stmt)


async def reset(user_id: str, defaults: Dict[str, bool], now: datetime) -> None:
    await execute(insert(np).values(user_id=user_id, preferences=defaults, created_at=now, updated_at=now)
                  .on_conflict_do_update(index_elements=[np.c.user_id],
                                         set_={"preferences": defaults, "updated_at": now}))


async def delete_for_user(user_id: str) -> None:
    await execute(delete(np).where(np.c.user_id == user_id))
