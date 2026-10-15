"""Published app versions (force-update control)."""
from typing import Any, Dict, Iterable, List, Optional

from sqlalchemy import delete, insert, select, update

from sql.db import execute, fetch_all, fetch_one
from sql.docs import row_to_doc, rows_to_docs
from sql.tables import app_versions

_ORDER = (app_versions.c.created_at.desc(), app_versions.c.id)


async def get(version_id: str) -> Optional[Dict[str, Any]]:
    return row_to_doc(await fetch_one(select(app_versions).where(app_versions.c.id == version_id)))


async def find_by_version(version: str, platform: str) -> Optional[Dict[str, Any]]:
    stmt = select(app_versions).where(app_versions.c.version == version, app_versions.c.platform == platform)
    return row_to_doc(await fetch_one(stmt))


async def insert_version(doc: Dict[str, Any]) -> None:
    await execute(insert(app_versions).values(**{("id" if k == "_id" else k): v for k, v in doc.items()}))


async def list_versions(platform: Optional[str], active_only: bool, skip: int, limit: int) -> List[Dict[str, Any]]:
    stmt = select(app_versions)
    if platform:
        stmt = stmt.where(app_versions.c.platform == platform)
    if active_only:
        stmt = stmt.where(app_versions.c.is_active.is_(True))
    return rows_to_docs(await fetch_all(stmt.order_by(*_ORDER).offset(skip).limit(limit)))


async def active_for_platforms(platforms: Iterable[str], limit: int = 500) -> List[Dict[str, Any]]:
    stmt = (select(app_versions)
            .where(app_versions.c.platform.in_(list(platforms)), app_versions.c.is_active.is_(True))
            .order_by(*_ORDER).limit(limit))
    return rows_to_docs(await fetch_all(stmt))


async def update_version(version_id: str, fields: Dict[str, Any]) -> int:
    return await execute(update(app_versions).where(app_versions.c.id == version_id).values(**fields))


async def delete_version(version_id: str) -> int:
    return await execute(delete(app_versions).where(app_versions.c.id == version_id))
