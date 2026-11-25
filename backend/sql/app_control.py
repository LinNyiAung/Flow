"""The App control settings document (switches, maintenance), stored as JSON text in app_settings."""
import uuid
from datetime import datetime
from typing import List, Optional

from sqlalchemy import any_, delete, func, insert, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert

from sql.db import execute, fetch_all, fetch_one, fetch_value, write_returning
from sql.tables import announcements, app_settings

SETTINGS_KEY = "app_control"


async def read_settings() -> Optional[str]:
    """The stored JSON text, or None when nothing was saved yet."""
    return await fetch_value(select(app_settings.c.value).where(app_settings.c.key == SETTINGS_KEY))


async def write_settings(value: str) -> None:
    stmt = pg_insert(app_settings).values(key=SETTINGS_KEY, value=value)
    await execute(stmt.on_conflict_do_update(index_elements=[app_settings.c.key],
                                             set_={"value": stmt.excluded.value, "updated_at": func.now()}))


# ---- announcements ----

_FIELDS = ("text_en", "text_my", "style", "link_url", "link_label_en", "link_label_my", "plans", "starts_at", "ends_at")


def _values(row: dict) -> dict:
    return {k: row.get(k) for k in _FIELDS}


async def list_announcements() -> List[dict]:
    """Every announcement, newest start first."""
    return await fetch_all(select(announcements).order_by(announcements.c.starts_at.desc(), announcements.c.id))


async def create_announcement(row: dict) -> dict:
    return await write_returning(insert(announcements).values(
        id=uuid.uuid4().hex, created_by=row.get("created_by"), **_values(row)).returning(announcements))


async def update_announcement(announcement_id: str, row: dict) -> Optional[dict]:
    return await write_returning(update(announcements).where(announcements.c.id == announcement_id)
                                 .values(updated_at=func.now(), **_values(row)).returning(announcements))


async def delete_announcement(announcement_id: str) -> bool:
    return await execute(delete(announcements).where(announcements.c.id == announcement_id)) > 0


async def live_announcement(plan: str, now: datetime) -> Optional[dict]:
    """The announcement shown to a user on `plan` at `now`: started, not ended, for that plan; the newest start wins."""
    return await fetch_one(
        select(announcements)
        .where(announcements.c.starts_at <= now,
               (announcements.c.ends_at.is_(None)) | (announcements.c.ends_at > now),
               plan == any_(announcements.c.plans))
        .order_by(announcements.c.starts_at.desc(), announcements.c.created_at.desc()).limit(1))
