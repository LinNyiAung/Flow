"""Plan limits, per-plan cost caps and the upgrade contact texts (plan_limits, plan_settings, app_settings), and the
per-user usage counters the quota engine reserves on (usage_counters)."""
from datetime import date, datetime
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Tuple

from sqlalchemy import and_, func, or_, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert

from sql.db import execute, fetch_all, transaction, write_returning
from sql.tables import app_settings, plan_limits, plan_settings, usage_counters, users

CONTACT_KEYS = {"en": "upgrade_contact_en", "my": "upgrade_contact_my"}

# One counter row of a user: (feature, period, period_start).
CounterKey = Tuple[str, str, date]
_uc = usage_counters.c


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


# ---- usage counters ----

class _CounterFull(Exception):
    def __init__(self, key: CounterKey):
        super().__init__(key)
        self.key = key


def _key_of(user_id: str, key: CounterKey):
    feature, period, start = key
    return and_(_uc.user_id == user_id, _uc.feature == feature, _uc.period == period, _uc.period_start == start)


async def increment_counters(user_id: str, rows: Sequence[Tuple[str, str, date, Optional[int]]]) -> Optional[CounterKey]:
    """Add one use to each (feature, period, period_start, cap) counter row of the user, all in ONE transaction.

    A row with an int `cap` is incremented only while its count is below the cap; a row whose cap is None always is.
    Each is a single conditional upsert (INSERT ... ON CONFLICT DO UPDATE SET used = used + 1 WHERE used < cap
    RETURNING used), so the check and the increment are atomic: concurrent callers queue on the row lock and each
    re-checks the count it finds. A new row starts at 1, so a cap below 1 is full without touching the table.

    Returns None when every row was incremented. Otherwise the transaction is rolled back (nothing changed) and the key
    of the capped row that was full is returned. Rows are written in sorted key order, so two reservations of the same
    user always lock rows in the same order and cannot deadlock.
    """
    try:
        async with transaction():
            for feature, period, start, cap in sorted(rows, key=lambda r: r[:3]):
                key = (feature, period, start)
                if cap is not None and cap < 1:
                    raise _CounterFull(key)
                stmt = pg_insert(usage_counters).values(user_id=user_id, feature=feature, period=period,
                                                        period_start=start, used=1)
                stmt = stmt.on_conflict_do_update(
                    index_elements=[_uc.user_id, _uc.feature, _uc.period, _uc.period_start],
                    set_={"used": _uc.used + 1},
                    where=(_uc.used < cap) if cap is not None else None,
                ).returning(_uc.used)
                if await write_returning(stmt) is None:
                    raise _CounterFull(key)  # rolls the whole transaction back
    except _CounterFull as full:
        return full.key
    return None


async def decrement_counters(user_id: str, keys: Iterable[CounterKey]) -> None:
    """Give one use back on each counter row (never below 0; a row that no longer exists is skipped), in one transaction."""
    async with transaction():
        for key in sorted(keys):
            await execute(update(usage_counters).where(_key_of(user_id, key), _uc.used > 0).values(used=_uc.used - 1))


def _in_periods(starts: Mapping[str, date]):
    return or_(*(and_(_uc.period == period, _uc.period_start == start) for period, start in starts.items()))


async def read_counters(user_id: str, starts: Mapping[str, date]) -> Dict[Tuple[str, str], int]:
    """{(feature, period): used} for the user's rows of the given periods ({"week": monday, "month": first})."""
    rows = await fetch_all(select(_uc.feature, _uc.period, _uc.used).where(_uc.user_id == user_id, _in_periods(starts)))
    return {(r["feature"], r["period"]): int(r["used"]) for r in rows}


async def reset_counters(user_id: str, starts: Mapping[str, date], reset_at: datetime) -> None:
    """Delete the user's counter rows of the given periods and set users.usage_reset_at, in one transaction."""
    which = and_(_uc.user_id == user_id, _in_periods(starts))
    async with transaction():
        # lock the rows in the same (sorted) order a reservation does, so a concurrent reserve can't deadlock with us
        await fetch_all(select(_uc.feature).where(which).order_by(_uc.feature, _uc.period, _uc.period_start).with_for_update())
        await execute(usage_counters.delete().where(which))
        await execute(update(users).where(users.c.id == user_id).values(usage_reset_at=reset_at))
