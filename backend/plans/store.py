"""The plan limits the app enforces: per plan and feature (locked / included / counted), a monthly AI cost cap per
plan, and the upgrade contact texts and the owner's own email and Viber number. The owner edits them in the admin panel; they live in the database
(sql.plans) and are served from an in-memory cache that is loaded at startup and refreshed every minute, so
a change is visible in this process at once and in the others within a minute.

Until a load succeeds (e.g. the database was down at boot) the catalogue defaults apply.
"""
import asyncio
import logging
import math
from collections.abc import Mapping
from typing import Any, Dict, List

from sql import plans as plans_db

from .contact import normalize_email, normalize_viber
from .catalog import DEFAULT_COST_CAPS, DEFAULT_LIMITS, FEATURES, MODES, PERIODS, PLANS, Limit

logger = logging.getLogger(__name__)

MAX_CONTACT_LENGTH = 500
MAX_QUOTA = 2_147_483_647   # plan_limits.quota is a 32-bit integer
MAX_COST_CAP = 999_999.0    # plan_settings.cost_cap_usd is NUMERIC(12, 6)

_limits: Dict[str, Dict[str, Limit]] = {p: dict(f) for p, f in DEFAULT_LIMITS.items()}
_caps: Dict[str, float] = dict(DEFAULT_COST_CAPS)
_contact: Dict[str, str] = {"en": "", "my": ""}
_owner: Dict[str, str] = {"email": "", "viber": ""}


# ---- reading (the cache) ----

def limits(plan: str) -> Dict[str, Limit]:
    """Every feature's limit on the plan (a copy)."""
    return dict(_limits[plan])


def cost_cap(plan: str) -> float:
    """The plan's monthly AI spend cap in USD."""
    return _caps[plan]


def upgrade_contact() -> Dict[str, str]:
    """{"en": ..., "my": ...}: how to reach the owner to upgrade (empty string when not set)."""
    return dict(_contact)


def owner_contact() -> Dict[str, str]:
    """{"email": ..., "viber": ...}: the owner's own email and Viber number (`+` and digits); empty string when not set."""
    return dict(_owner)


# ---- validation ----

def _is_int(v: Any) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def _limit(where: str, value: Any, errors: List[str]) -> Limit | None:
    """A Limit from a Limit or a {mode, quota, period} mapping; problems are appended to `errors`."""
    if isinstance(value, Limit):
        mode, quota, period = value.mode, value.quota, value.period
    elif isinstance(value, Mapping):
        mode, quota, period = value.get("mode"), value.get("quota"), value.get("period")
    else:
        errors.append(f"{where}: expected a limit with a mode")
        return None
    if mode not in MODES:
        errors.append(f"{where}: unknown mode {mode!r} (use {', '.join(MODES)})")
        return None
    if mode != "counted":
        if quota is not None or period is not None:
            errors.append(f"{where}: a {mode} limit must not have a quota or a period")
            return None
        return Limit(mode)
    ok = True
    if quota is None:
        errors.append(f"{where}: a counted limit needs a quota (0 or more)")
        ok = False
    elif not _is_int(quota) or quota < 0 or quota > MAX_QUOTA:
        errors.append(f"{where}: the quota must be a whole number from 0 to {MAX_QUOTA}")
        ok = False
    if period is None:
        errors.append(f"{where}: a counted limit needs a period ({' or '.join(PERIODS)})")
        ok = False
    elif period not in PERIODS:
        errors.append(f"{where}: unknown period {period!r} (use {' or '.join(PERIODS)})")
        ok = False
    return Limit("counted", quota, period) if ok else None


def _owner_contact(value: Any, errors: List[str]) -> Dict[str, str]:
    """{"email", "viber"} normalised ("" when empty) from a mapping with those keys; problems are appended to `errors`."""
    if not isinstance(value, Mapping):
        errors.append("owner contact must be an object with email and viber")
        return {}
    for key in value:
        if key not in ("email", "viber"):
            errors.append(f"Unknown owner contact field '{key}'")
    out: Dict[str, str] = {}
    for key, normalise, label in (("email", normalize_email, "email"), ("viber", normalize_viber, "Viber number")):
        raw = value.get(key, "")
        if raw is not None and not isinstance(raw, str):
            errors.append(f"owner contact {label} must be text")
            continue
        try:
            out[key] = normalise(raw) or ""
        except ValueError as e:
            errors.append(f"owner contact {label}: {e}")
    return out


def _validate(plan_rows: Any, caps: Any, contact: Any, owner: Any = None):
    """-> (normalised limits {plan: {feature: Limit}}, caps {plan: float}, contact {"en", "my"}, owner contact
    {"email", "viber"} or None when `owner` is None); ValueError if invalid."""
    errors: List[str] = []
    rows: Dict[str, Dict[str, Limit]] = {}
    if not isinstance(plan_rows, Mapping):
        raise ValueError("plans must be an object keyed by plan")
    for plan in plan_rows:
        if plan not in PLANS:
            errors.append(f"Unknown plan '{plan}'")
    for plan in PLANS:
        feats = plan_rows.get(plan)
        if not isinstance(feats, Mapping):
            errors.append(f"Plan '{plan}' is missing its limits")
            continue
        for feature in feats:
            if feature not in FEATURES:
                errors.append(f"{plan}: unknown feature '{feature}'")
        rows[plan] = {}
        for feature in FEATURES:
            if feature not in feats:
                errors.append(f"{plan}.{feature}: missing (every plan needs every feature)")
                continue
            lim = _limit(f"{plan}.{feature}", feats[feature], errors)
            if lim is not None:
                rows[plan][feature] = lim
        trans = rows[plan].get("insight_translation")
        if plan == "free" and trans is not None and trans.mode != "locked":
            errors.append("free.insight_translation: Free never gets translated insights, so it must stay locked")
        chat, adv = rows[plan].get("chat"), rows[plan].get("chat_advanced")
        if chat is not None and adv is not None and chat.mode == "locked" and adv.mode != "locked":
            errors.append(f"{plan}.chat_advanced: can only be available when chat is not locked")

    out_caps: Dict[str, float] = {}
    if not isinstance(caps, Mapping):
        raise ValueError("cost caps must be an object keyed by plan")
    for plan in caps:
        if plan not in PLANS:
            errors.append(f"Unknown plan '{plan}' in the cost caps")
    for plan in PLANS:
        cap = caps.get(plan)
        if plan not in caps:
            errors.append(f"{plan}: cost cap is missing")
        elif isinstance(cap, bool) or not isinstance(cap, (int, float)) or not math.isfinite(cap) \
                or cap < 0 or cap > MAX_COST_CAP:
            errors.append(f"{plan}: the cost cap must be a number from 0 to {MAX_COST_CAP:g} (USD)")
        else:
            out_caps[plan] = round(float(cap), 6)

    out_contact: Dict[str, str] = {}
    if not isinstance(contact, Mapping):
        raise ValueError("upgrade contact must be an object with en and my")
    for lang in contact:
        if lang not in ("en", "my"):
            errors.append(f"Unknown upgrade contact language '{lang}'")
    for lang in ("en", "my"):
        text = contact.get(lang)
        if lang not in contact:
            errors.append(f"upgrade contact ({lang}) is missing")
        elif not isinstance(text, str):
            errors.append(f"upgrade contact ({lang}) must be text")
        elif len(text) > MAX_CONTACT_LENGTH:
            errors.append(f"upgrade contact ({lang}) is {len(text)} characters; the limit is {MAX_CONTACT_LENGTH}")
        else:
            out_contact[lang] = text

    out_owner = _owner_contact(owner, errors) if owner is not None else None

    if errors:
        raise ValueError("; ".join(errors))
    return rows, out_caps, out_contact, out_owner


# ---- the cache <-> the database ----

def _set_cache(new_limits: Dict[str, Dict[str, Limit]], new_caps: Dict[str, float], new_contact: Dict[str, str],
               new_owner: Dict[str, str]) -> None:
    global _limits, _caps, _contact, _owner
    _limits, _caps, _contact, _owner = new_limits, new_caps, new_contact, new_owner


# Bumped by every save, before the write and after the cache changes. A load whose read overlapped a save may hold
# a stale snapshot, so it compares the counter and drops its result if it moved.
_write_gen = 0


async def load() -> None:
    """Read the limits, caps and contact texts into the cache.

    A missing or malformed row keeps its catalogue default (logged). If a save happened while the rows were being
    read, the snapshot may predate it, so it is discarded (the next refresh reads a consistent state).
    """
    gen = _write_gen
    limit_rows, cap_rows, texts = await plans_db.read_all()

    new_limits = {p: dict(f) for p, f in DEFAULT_LIMITS.items()}
    for row in limit_rows:
        plan, feature = row.get("plan"), row.get("feature")
        if plan not in PLANS or feature not in FEATURES:
            logger.warning("Ignoring the stored plan limit for %r/%r: unknown plan or feature", plan, feature)
            continue
        errors: List[str] = []
        lim = _limit(f"{plan}.{feature}", row, errors)
        if lim is None:
            logger.warning("Ignoring the stored plan limit: %s", "; ".join(errors))
            continue
        new_limits[plan][feature] = lim
    seen = {(r.get("plan"), r.get("feature")) for r in limit_rows}
    for plan in PLANS:
        for feature in FEATURES:
            if (plan, feature) not in seen:
                logger.warning("No stored plan limit for %s.%s; using the default", plan, feature)

    new_caps = dict(DEFAULT_COST_CAPS)
    for row in cap_rows:
        plan = row.get("plan")
        if plan in PLANS and row.get("cost_cap_usd") is not None:
            new_caps[plan] = float(row["cost_cap_usd"])
    new_contact = {lang: texts.get(key, "") for lang, key in plans_db.CONTACT_KEYS.items()}
    # A stored owner contact that no longer passes validation (edited by hand) is not shown.
    new_owner = {}
    for name, key in plans_db.OWNER_CONTACT_KEYS.items():
        try:
            new_owner[name] = (normalize_email if name == "email" else normalize_viber)(texts.get(key)) or ""
        except ValueError:
            logger.warning("Ignoring the stored owner contact %s: not valid", name)
            new_owner[name] = ""

    if _write_gen != gen:
        logger.debug("Discarding a stale plans snapshot: a save happened while it was being read")
        return
    _set_cache(new_limits, new_caps, new_contact, new_owner)


async def save(plan_rows: Mapping, caps: Mapping, contact: Mapping, admin_id: str,
               owner_contact: Mapping | None = None) -> None:
    """Validate, store and cache the limits (plan -> feature -> Limit or {mode, quota, period}), the cost caps
    (plan -> USD), the upgrade contact texts ({"en", "my"}) and, when given, the owner's {"email", "viber"} (empty
    string clears one; None leaves both as they are). Raises ValueError with a readable message when
    anything is invalid; nothing is written then. `admin_id` is only recorded in the server log (the route writes
    the admin action log).
    """
    global _write_gen
    rows, out_caps, out_contact, out_owner = _validate(plan_rows, caps, contact, owner_contact)
    flat = [{"plan": p, "feature": f, "mode": lim.mode, "quota": lim.quota, "period": lim.period}
            for p in PLANS for f, lim in rows[p].items()]
    _write_gen += 1
    await plans_db.write_all(flat, out_caps, out_contact, out_owner)
    _set_cache(rows, out_caps, out_contact, out_owner if out_owner is not None else dict(_owner))
    _write_gen += 1
    logger.info("Plans saved by admin %s", admin_id)


_refresh_task: asyncio.Task | None = None


async def _refresh_forever(interval: float) -> None:
    while True:
        await asyncio.sleep(interval)
        try:
            await load()
        except Exception:  # noqa: BLE001 - keep the last good cache and try again next round
            logger.exception("Could not refresh the plan limits from the database")


def start_refresh_loop(interval: float = 60.0) -> asyncio.Task:
    """Reload the cache every `interval` seconds on the running event loop (call once from app startup).

    Never started at import. Calling it again while the task is alive returns the same task.
    """
    global _refresh_task
    loop = asyncio.get_running_loop()
    if _refresh_task is not None and not _refresh_task.done() and _refresh_task.get_loop() is loop:
        return _refresh_task
    _refresh_task = loop.create_task(_refresh_forever(interval), name="plans-refresh")
    return _refresh_task
