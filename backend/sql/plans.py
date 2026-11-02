"""Plan limits, per-plan cost caps and the upgrade contact texts (plan_limits, plan_settings, app_settings)."""
from typing import Any, Dict, List, Mapping, Tuple

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from sql.db import execute, fetch_all, transaction
from sql.tables import app_settings, plan_limits, plan_settings

CONTACT_KEYS = {"en": "upgrade_contact_en", "my": "upgrade_contact_my"}


async def read_all() -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]], Dict[str, str]]:
    """(plan_limits rows, plan_settings rows, {app_settings key: value} for the upgrade contact keys)."""
    limits = await fetch_all(select(plan_limits))
    caps = await fetch_all(select(plan_settings))
    texts = await fetch_all(select(app_settings.c.key, app_settings.c.value).where(app_settings.c.key.in_(list(CONTACT_KEYS.values()))))
    return limits, caps, {r["key"]: r["value"] for r in texts}


async def write_all(limit_rows: List[Mapping[str, Any]], caps: Mapping[str, float], contact: Mapping[str, str]) -> None:
    """Upsert every limit row, cost cap and contact text in one transaction.

    limit_rows: dicts with plan, feature, mode, quota, period. caps: plan -> USD. contact: {"en": ..., "my": ...}.
    """
    async with transaction():
        if limit_rows:
            stmt = pg_insert(plan_limits).values(list(limit_rows))
            await execute(stmt.on_conflict_do_update(
                index_elements=[plan_limits.c.plan, plan_limits.c.feature],
                set_={c: stmt.excluded[c] for c in ("mode", "quota", "period")}))
        for plan, cap in caps.items():
            stmt = pg_insert(plan_settings).values(plan=plan, cost_cap_usd=cap)
            await execute(stmt.on_conflict_do_update(index_elements=[plan_settings.c.plan],
                                                     set_={"cost_cap_usd": stmt.excluded.cost_cap_usd}))
        for lang, key in CONTACT_KEYS.items():
            stmt = pg_insert(app_settings).values(key=key, value=contact[lang])
            await execute(stmt.on_conflict_do_update(index_elements=[app_settings.c.key],
                                                     set_={"value": stmt.excluded.value, "updated_at": func.now()}))
