"""The App control settings document (switches, maintenance), stored as JSON text in app_settings."""
from typing import Optional

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from sql.db import execute, fetch_value
from sql.tables import app_settings

SETTINGS_KEY = "app_control"


async def read_settings() -> Optional[str]:
    """The stored JSON text, or None when nothing was saved yet."""
    return await fetch_value(select(app_settings.c.value).where(app_settings.c.key == SETTINGS_KEY))


async def write_settings(value: str) -> None:
    stmt = pg_insert(app_settings).values(key=SETTINGS_KEY, value=value)
    await execute(stmt.on_conflict_do_update(index_elements=[app_settings.c.key],
                                             set_={"value": stmt.excluded.value, "updated_at": func.now()}))
