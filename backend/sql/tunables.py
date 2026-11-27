"""The tunable numbers and times record, stored as JSON text in app_settings (one row, with a version)."""
from typing import Optional

from sqlalchemy import Integer, func, literal_column, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert

from sql.db import execute, fetch_value
from sql.tables import app_settings

SETTINGS_KEY = "tunables"  # read at call time (module attribute), so tests can point it at a private key


# The stored record's version, never raising: 0 when the text is not a JSON object or its "version" is missing or not a
# whole number (CASE evaluates in order, so the ::jsonb cast only runs on valid JSON).
_STORED_VERSION = literal_column(
    "CASE WHEN app_settings.value IS JSON OBJECT THEN "
    "CASE WHEN jsonb_typeof(app_settings.value::jsonb -> 'version') = 'number' "
    "AND (app_settings.value::jsonb ->> 'version') ~ '^[0-9]{1,9}$' "
    "THEN (app_settings.value::jsonb ->> 'version')::int ELSE 0 END "
    "ELSE 0 END", Integer)


async def read() -> Optional[str]:
    """The stored JSON text, or None when nothing was saved yet."""
    return await fetch_value(select(app_settings.c.value).where(app_settings.c.key == SETTINGS_KEY))


async def write_if_version(value: str, expected_version: int) -> bool:
    """Store `value` only if the stored record is still at `expected_version` (compare-and-swap in SQL).
    Version 0 means "nothing stored yet": insert, unless a row appeared meanwhile. True when a row was written."""
    if expected_version == 0:
        # One statement: insert when no row exists, or replace a row that is still at version 0 (which includes an
        # unreadable one); two first saves at once: exactly one writes.
        stmt = pg_insert(app_settings).values(key=SETTINGS_KEY, value=value)
        stmt = stmt.on_conflict_do_update(index_elements=[app_settings.c.key],
                                          set_={"value": stmt.excluded.value, "updated_at": func.now()},
                                          where=_STORED_VERSION == 0)
        return await execute(stmt) == 1
    return await execute(update(app_settings)
                         .where(app_settings.c.key == SETTINGS_KEY, _STORED_VERSION == expected_version)
                         .values(value=value, updated_at=func.now())) == 1
