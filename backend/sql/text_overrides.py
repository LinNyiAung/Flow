"""Admin overrides of the server texts (text_overrides): one row per (key, lang), versioned for concurrent edits."""
from typing import List, Optional

from sqlalchemy import and_, func, select, update
from sqlalchemy import delete as sa_delete
from sqlalchemy.dialects.postgresql import insert as pg_insert

from sql.db import fetch_all, write_returning
from sql.tables import text_overrides as t


async def read_all() -> List[dict]:
    return await fetch_all(select(t))


async def upsert(key: str, lang: str, text: str, replaced_default: str, expected_version: Optional[int],
                 admin_email: Optional[str]) -> Optional[dict]:
    """Save an override. `expected_version` None creates it (None back when one already exists); a number replaces
    that version (None back when the row is gone or at another version). The row's version starts at 1."""
    if expected_version is None:
        stmt = (pg_insert(t).values(key=key, lang=lang, text=text, replaced_default=replaced_default, version=1,
                                    updated_by=admin_email)
                .on_conflict_do_nothing(index_elements=[t.c.key, t.c.lang]).returning(t))
        return await write_returning(stmt)
    return await write_returning(
        update(t).where(and_(t.c.key == key, t.c.lang == lang, t.c.version == expected_version))
        .values(text=text, replaced_default=replaced_default, version=t.c.version + 1, updated_by=admin_email,
                updated_at=func.now()).returning(t))


async def delete(key: str, lang: str, expected_version: int) -> Optional[bool]:
    """Remove an override: True when removed, None when it is at another version, False when there is none."""
    row = await write_returning(
        sa_delete(t).where(and_(t.c.key == key, t.c.lang == lang, t.c.version == expected_version))
        .returning(t.c.key))
    if row is not None:
        return True
    still = await fetch_all(select(t.c.version).where(and_(t.c.key == key, t.c.lang == lang)))
    return None if still else False
