"""The tunable numbers and times record, stored as JSON text in app_settings (one row, with a version)."""
from typing import Optional

from sqlalchemy import Integer, cast, func, select, update
from sqlalchemy.dialects.postgresql import JSONB, insert as pg_insert

from sql.db import execute, fetch_value
from sql.tables import app_settings

SETTINGS_KEY = "tunables"  # read at call time (module attribute), so tests can point it at a private key


async def read() -> Optional[str]:
    """The stored JSON text, or None when nothing was saved yet."""
    return await fetch_value(select(app_settings.c.value).where(app_settings.c.key == SETTINGS_KEY))


async def write_if_version(value: str, expected_version: int) -> bool:
    """Store `value` only if the stored record is still at `expected_version` (compare-and-swap in SQL).
    Version 0 means "nothing stored yet": insert, unless a row appeared meanwhile. True when a row was written."""
    if expected_version == 0:
        stmt = pg_insert(app_settings).values(key=SETTINGS_KEY, value=value).on_conflict_do_nothing(
            index_elements=[app_settings.c.key])
        return await execute(stmt) == 1
    stored_version = cast(cast(app_settings.c.value, JSONB)["version"].astext, Integer)
    return await execute(update(app_settings)
                         .where(app_settings.c.key == SETTINGS_KEY, stored_version == expected_version)
                         .values(value=value, updated_at=func.now())) == 1
