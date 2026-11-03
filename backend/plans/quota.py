"""The quota engine: reserve a use before an AI call, then commit it on a usable answer or release it on failure.

    async with quota.use(user, "chat", also=("chat_advanced",)) as r:
        answer = await run_ai(...)        # an exception here gives the use back
        r.commit()                        # optional: commit early (e.g. after the first streamed chunk)
    # leaving the block cleanly commits

Checks, in order (each raises plans.access.PlanError):
  1. every requested feature is unlocked on the user's effective plan          -> 403 plan_feature_locked
  2. the user's AI spend this month is under the plan's hidden cost cap         -> 429 plan_cost_cap
  3. every counted feature has allowance left, reserved atomically             -> 429 plan_limit_reached

Counting. A counted feature has one counter row per period type (week and month) per user. A reservation increments
both rows for each counted feature, in one transaction: the row of the plan's own period is the limit-checked one
(incremented only while below the quota); the other period's row is incremented unconditionally. Keeping both means a
plan change mid-period measures the new plan's period against what was really used so far: 5 Free chats this week
(Free chat is weekly) show as 5 of Plus's 100 this month, and a Plus user who drops to Free is measured on this
week's uses. Included features reserve nothing but are still subject to the cost cap.

A reservation remembers the exact rows (period_start included) it incremented, so a release after a period boundary
still gives the use back to the period it was taken from.
"""
import asyncio
import logging
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Any, AsyncIterator, Dict, Mapping, Optional, Sequence, Tuple

from sql import ai_usage as ai_usage_db
from sql import plans as plans_db
from tz_utils import as_utc

from . import periods, store
from .access import COST_CAP, LIMIT_REACHED, LOCKED, PlanError, effective_plan, is_trial, user_language
from .catalog import FEATURES, PERIODS, PLANS, Limit

logger = logging.getLogger(__name__)

WEEKS_PER_MONTH = 52 / 12


def _now(now: Optional[datetime]) -> datetime:
    return as_utc(now) if now is not None else datetime.now(timezone.utc)


def _user_id(user: Mapping[str, Any]) -> str:
    return user.get("_id") or user["id"]


def _iso(value: Any) -> Optional[str]:
    return as_utc(value).isoformat() if value is not None else None


# ---- upgrade hints ----

def _per_month(lim: Limit) -> float:
    """A counted limit as uses per month, so a weekly and a monthly quota can be compared."""
    return lim.quota * WEEKS_PER_MONTH if lim.period == "week" else float(lim.quota)


def _upgrade_available(plan: str, feature: str) -> bool:
    """True when a higher plan has the feature included, or counted with a larger allowance."""
    current = store.limits(plan)[feature]
    if current.mode == "included":
        return False
    have = _per_month(current) if current.mode == "counted" else 0.0
    for higher in PLANS[PLANS.index(plan) + 1:]:
        lim = store.limits(higher)[feature]
        if lim.mode == "included" or (lim.mode == "counted" and _per_month(lim) > have):
            return True
    return False


def _cost_upgrade_available(plan: str) -> bool:
    return any(store.cost_cap(higher) > store.cost_cap(plan) for higher in PLANS[PLANS.index(plan) + 1:])


# ---- the hidden cost cap ----

def _spend_window_start(user: Mapping[str, Any], now: datetime) -> datetime:
    """Spend counts from the later of this month's start (app timezone) and the admin's last usage reset."""
    start = periods.month_start_utc(now)
    reset = user.get("usage_reset_at")
    if reset is not None and as_utc(reset) > start:
        start = as_utc(reset)
    return start


async def month_spend(user: Mapping[str, Any], now: Optional[datetime] = None) -> float:
    """The user's AI spend in USD in the cost cap's window: since the later of this month's start and the last reset."""
    now = _now(now)
    return await ai_usage_db.user_cost_since(_user_id(user), _spend_window_start(user, now))


async def _at_cost_cap(user: Mapping[str, Any], plan: str, now: datetime) -> bool:
    return await month_spend(user, now) >= store.cost_cap(plan)


async def over_cost_cap(user: Mapping[str, Any], now: Optional[datetime] = None) -> bool:
    """True when the user's AI spend this month has reached their effective plan's cap (for the scheduled jobs).

    `user` needs _id, subscription_type, subscription_expires_at and usage_reset_at.
    """
    now = _now(now)
    return await _at_cost_cap(user, effective_plan(user, now), now)


# ---- reservations ----

class Reservation:
    """One reserved use (of one or more features). commit() keeps it; release() gives it back.

    Commit is final: a release after a commit does nothing. Release is idempotent.
    """

    def __init__(self, user_id: str, keys: Sequence[plans_db.CounterKey]):
        self.user_id = user_id
        self.keys: Tuple[plans_db.CounterKey, ...] = tuple(keys)  # the exact rows incremented
        self._committed = False
        self._released = False

    @property
    def committed(self) -> bool:
        return self._committed

    @property
    def released(self) -> bool:
        return self._released

    def commit(self) -> None:
        if self._released:
            logger.warning("Commit of an already released reservation for user %s ignored", self.user_id)
            return
        self._committed = True

    async def release(self) -> None:
        if self._committed or self._released:
            return
        self._released = True  # set before the await, so a concurrent second release is a no-op
        if not self.keys:
            return
        try:
            await plans_db.decrement_counters(self.user_id, self.keys)
        except BaseException:
            self._released = False  # nothing was given back; a later release may retry
            raise


async def reserve(user: Mapping[str, Any], feature: str, *, also: Sequence[str] = (),
                  now: Optional[datetime] = None) -> Reservation:
    """Reserve one use of `feature` (and of each feature in `also`, all or nothing). Raises PlanError.

    `user` is the user row (as get_current_user returns it). `now` is for tests and defaults to the current time.
    """
    now = _now(now)
    wanted = tuple(dict.fromkeys((feature, *also)))
    for f in wanted:
        if f not in FEATURES:
            raise ValueError(f"Unknown quota feature '{f}'")
    plan = effective_plan(user, now)
    limits = store.limits(plan)
    lang = user_language(user)
    uid = _user_id(user)

    for f in wanted:
        if limits[f].mode == "locked":
            raise PlanError(LOCKED, f, upgrade_available=_upgrade_available(plan, f), lang=lang)

    # The cost cap is a soft safety net, checked outside the counter transaction: requests that pass this check at
    # the same time can each add their cost, so spend may overshoot the cap slightly under concurrency. That is
    # acceptable; the counted allowances below are the exact limits.
    if await _at_cost_cap(user, plan, now):
        raise PlanError(COST_CAP, feature, resets_at=periods.resets_at("month", now),
                        upgrade_available=_cost_upgrade_available(plan), lang=lang)

    rows = []
    for f in wanted:
        lim = limits[f]
        if lim.mode != "counted":
            continue  # included: nothing to count
        for period in PERIODS:
            cap = lim.quota if period == lim.period else None
            rows.append((f, period, periods.period_start(period, now), cap))
    if rows:
        full = await plans_db.increment_counters(uid, rows)
        if full is not None:
            f, period, _ = full
            raise PlanError(LIMIT_REACHED, f, resets_at=periods.resets_at(period, now),
                            upgrade_available=_upgrade_available(plan, f), lang=lang)
    return Reservation(uid, [r[:3] for r in rows])


def is_locked(user: Mapping[str, Any], feature: str, *, now: Optional[datetime] = None) -> bool:
    """True when `feature` is locked on the user's effective plan (the check require_unlocked raises on)."""
    if feature not in FEATURES:
        raise ValueError(f"Unknown quota feature '{feature}'")
    return store.limits(effective_plan(user, _now(now)))[feature].mode == "locked"


def require_unlocked(user: Mapping[str, Any], feature: str, *, now: Optional[datetime] = None) -> None:
    """Raise PlanError (403 plan_feature_locked) when `feature` is locked on the user's effective plan; otherwise nothing.

    For a user action that is not an AI call (the Reports PDF): no allowance is reserved and the hidden cost cap, which
    only guards AI spend, is not consulted, even if the owner made the feature a counted limit.
    """
    if feature not in FEATURES:
        raise ValueError(f"Unknown quota feature '{feature}'")
    plan = effective_plan(user, _now(now))
    if store.limits(plan)[feature].mode == "locked":
        raise PlanError(LOCKED, feature, upgrade_available=_upgrade_available(plan, feature), lang=user_language(user))


async def give_back(r: Reservation) -> None:
    """Release `r` (a no-op once committed or released) so that a cancelled request still gives the use back, and a
    failed release is logged instead of hiding the error the caller is handling.

    For a route that decides itself whether an answer counts (`reserve`, then `commit` or `give_back`); a
    `use` block releases through this on an exception.
    """
    try:
        await asyncio.shield(r.release())
    except Exception:  # noqa: BLE001 - never hide the original error behind a failed release
        logger.exception("Could not release a reserved use for user %s", r.user_id)


@asynccontextmanager
async def use(user: Mapping[str, Any], feature: str, *, also: Sequence[str] = (),
              now: Optional[datetime] = None) -> AsyncIterator[Reservation]:
    """Reserve on entry; commit on a clean exit; release on an exception (including cancellation) unless the block
    already called r.commit()."""
    r = await reserve(user, feature, also=also, now=now)
    try:
        yield r
    except BaseException:
        if not r.committed:
            await give_back(r)
        raise
    r.commit()


# ---- what the app reads, and the admin reset ----

async def status(user: Mapping[str, Any], now: Optional[datetime] = None) -> Dict[str, Any]:
    """The body of GET /api/plan: the user's plan, dates, each feature's allowance this period, and the catalogue.

    `used` is this period's counter of the plan's own period type; locked and included features have null counts.
    """
    now = _now(now)
    plan = effective_plan(user, now)
    limits = store.limits(plan)
    counts = await plans_db.read_counters(_user_id(user), {p: periods.period_start(p, now) for p in PERIODS})
    features = {}
    for f in FEATURES:
        lim = limits[f]
        if lim.mode == "counted":
            used = counts.get((f, lim.period), 0)
            features[f] = {"mode": "counted", "limit": lim.quota, "period": lim.period, "used": used,
                           "remaining": max(0, lim.quota - used), "resets_at": periods.resets_at(lim.period, now).isoformat()}
        else:
            features[f] = {"mode": lim.mode, "limit": None, "period": None, "used": None, "remaining": None,
                           "resets_at": None}
    paid = plan != "free"
    trial = paid and is_trial(user, now)
    return {
        "plan": plan,
        "expires_at": _iso(user.get("subscription_expires_at")) if paid else None,
        "is_trial": trial,
        "trial_ends_at": _iso(user.get("trial_ends_at")) if trial else None,
        "features": features,
        "catalog": {p: {f: {"mode": lim.mode, "quota": lim.quota, "period": lim.period}
                        for f, lim in store.limits(p).items()} for p in PLANS},
        "upgrade_contact": store.upgrade_contact(),
    }


async def reset_usage(user_id: str, admin_id: str, now: Optional[datetime] = None) -> None:
    """Admin "reset usage": delete this week's and this month's counters and restart the cost-cap window from now.

    ai_usage rows are never deleted (cost reports depend on them). The route writes the admin action log.
    """
    now = _now(now)
    await plans_db.reset_counters(user_id, {p: periods.period_start(p, now) for p in PERIODS}, now)
    logger.info("Usage reset for user %s by admin %s", user_id, admin_id)
