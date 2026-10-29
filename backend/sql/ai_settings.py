"""Admin-panel AI provider settings (one row per overridden feature) and per-provider health."""
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import delete, func, null, select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from sql.db import execute, fetch_all
from sql.tables import ai_feature_settings as fs
from sql.tables import ai_provider_status as ps


async def list_feature_settings() -> List[Dict[str, Any]]:
    """Every stored row: feature, main_provider, main_model, backups (None / list), updated_at, updated_by."""
    return await fetch_all(select(fs).order_by(fs.c.feature))


async def upsert_feature_setting(feature: str, main_provider: str, main_model: str,
                                 backups: Optional[List[Dict[str, str]]], updated_by: str) -> None:
    """backups: None = default backups (SQL NULL), [] = no backups, else a list of {"provider", "model"}."""
    values = {
        "main_provider": main_provider,
        "main_model": main_model,
        # A Python None would be stored as JSON 'null'; the column must hold SQL NULL for "default backups".
        "backups": null() if backups is None else backups,
        "updated_by": updated_by,
        "updated_at": func.now(),
    }
    stmt = pg_insert(fs).values(feature=feature, **values)
    await execute(stmt.on_conflict_do_update(index_elements=[fs.c.feature], set_=values))


async def delete_feature_setting(feature: str) -> bool:
    """True if a row was removed."""
    return bool(await execute(delete(fs).where(fs.c.feature == feature)))


async def get_provider_status() -> Dict[str, Dict[str, Any]]:
    """provider -> {last_error, last_error_at, last_success_at} for every provider that has a row."""
    rows = await fetch_all(select(ps))
    return {r["provider"]: {k: v for k, v in r.items() if k != "provider"} for r in rows}


async def record_provider_error(provider: str, message: str, at: datetime) -> None:
    values = {"last_error": message, "last_error_at": at}
    stmt = pg_insert(ps).values(provider=provider, **values)
    await execute(stmt.on_conflict_do_update(index_elements=[ps.c.provider], set_=values))


async def record_provider_success(provider: str, at: datetime) -> None:
    stmt = pg_insert(ps).values(provider=provider, last_success_at=at)
    await execute(stmt.on_conflict_do_update(index_elements=[ps.c.provider], set_={"last_success_at": at}))
