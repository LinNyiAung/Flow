"""Admin API for plans: every plan's per-feature limits, monthly AI cost cap and price in kyat, the upgrade contact texts
and the owner's own contact details (email, Viber, Telegram, Facebook page, Messenger), and the users' upgrade
requests (at the end of this file).

Moderators can view; admins and super admins can change. A change applies in this process at once and in
other workers within a minute (plans.store refreshes every 60 s). Every change is written to the admin action log.
"""
from datetime import datetime, timedelta, UTC
from typing import Dict, Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Path, Query, status
from pydantic import BaseModel, ConfigDict, StrictFloat, StrictInt

from admin_routes import apply_plan
from admin_utils import log_admin_action, require_admin_or_super, require_moderator_or_above
from plans import store
from plans.access import effective_plan, is_trial
from plans.catalog import FEATURES, PLAN_RANK, PLANS, Limit
from tz_utils import as_utc
from subscription_service import notify_upgrade_request_declined
from sql import upgrade_requests as requests_db
from sql import users as users_db

router = APIRouter(prefix="/api/admin/plans", tags=["admin", "plans"])

MAX_LOG_DETAILS = 2000


# ==================== MODELS ====================
# Shape and basic types only; what values are allowed (modes, periods, ranges, completeness) is decided by
# plans.store.save, so a bad request gets one readable 422 message.

class LimitBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    mode: str
    quota: Optional[StrictInt] = None
    period: Optional[str] = None


class PlanBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    limits: Dict[str, LimitBody]
    cost_cap_usd: StrictFloat
    # Whole kyat; null: not set. Left out of every plan (an older admin panel): the prices stay as they are.
    price_monthly_mmk: Optional[StrictInt] = None
    price_yearly_mmk: Optional[StrictInt] = None
    # Family limits (whole numbers, 0 to 50; plans.store.save checks the range). Left out or null: that plan's stored
    # value stays as it is (an older admin panel).
    family_max_members: Optional[StrictInt] = None
    family_max_placeholders: Optional[StrictInt] = None


class ContactBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    en: str
    my: str


class OwnerContactBody(BaseModel):
    """The owner's own email, Viber number, Telegram number or username, Facebook page link and Messenger link;
    "" clears one. plans.store.save validates them. Telegram, Facebook and Messenger came later: one left out (an older
    admin panel still open) keeps its stored value (only the fields sent are passed on, model_fields_set)."""
    model_config = ConfigDict(extra="forbid")
    email: str
    viber: str
    telegram: str = ""
    facebook: str = ""
    messenger: str = ""


class PlansBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    plans: Dict[str, PlanBody]
    upgrade_contact: ContactBody
    # Left out: the owner's contact details all stay as they are.
    owner_contact: Optional[OwnerContactBody] = None


# ==================== HELPERS ====================

def _snapshot() -> dict:
    """What the store holds now, in the API's JSON shape."""
    return {
        "plans": {
            plan: {
                "limits": {f: {"mode": lim.mode, "quota": lim.quota, "period": lim.period}
                           for f, lim in store.limits(plan).items()},
                "cost_cap_usd": store.cost_cap(plan),
                "price_monthly_mmk": store.prices(plan)["monthly_mmk"],
                "price_yearly_mmk": store.prices(plan)["yearly_mmk"],
                "family_max_members": store.family_limits(plan)[0],
                "family_max_placeholders": store.family_limits(plan)[1],
            }
            for plan in PLANS
        },
        "upgrade_contact": store.upgrade_contact(),
        "owner_contact": store.owner_contact(),
    }


def _fmt(lim: dict) -> str:
    return f"counted {lim['quota']}/{lim['period']}" if lim["mode"] == "counted" else lim["mode"]


def _fmt_price(mmk: Optional[int]) -> str:
    return f"{mmk} MMK" if mmk is not None else "(none)"


def _changes(before: dict, after: dict) -> str:
    """A short readable list of what differs, for the admin action log."""
    out = []
    for plan in PLANS:
        for feature in FEATURES:
            old, new = before["plans"][plan]["limits"][feature], after["plans"][plan]["limits"][feature]
            if old != new:
                out.append(f"{plan}.{feature}: {_fmt(old)} -> {_fmt(new)}")
        old_cap, new_cap = before["plans"][plan]["cost_cap_usd"], after["plans"][plan]["cost_cap_usd"]
        if old_cap != new_cap:
            out.append(f"{plan} cost cap: {old_cap:g} -> {new_cap:g} USD")
        for label, key in (("monthly", "price_monthly_mmk"), ("yearly", "price_yearly_mmk")):
            old_price, new_price = before["plans"][plan][key], after["plans"][plan][key]
            if old_price != new_price:
                out.append(f"{plan} {label} price: {_fmt_price(old_price)} -> {_fmt_price(new_price)}")
        for label, key in (("members", "family_max_members"), ("placeholders", "family_max_placeholders")):
            old_n, new_n = before["plans"][plan][key], after["plans"][plan][key]
            if old_n != new_n:
                out.append(f"{plan} family {label} limit: {old_n} -> {new_n}")
    for lang in ("en", "my"):
        if before["upgrade_contact"][lang] != after["upgrade_contact"][lang]:
            out.append(f"upgrade contact ({lang}) changed")
    for key in store.OWNER_KEYS:
        old, new = before["owner_contact"][key], after["owner_contact"][key]
        if old != new:
            out.append(f"owner contact {key}: {old or '(none)'} -> {new or '(none)'}")
    text = "; ".join(out) if out else "no changes"
    return text if len(text) <= MAX_LOG_DETAILS else text[:MAX_LOG_DETAILS - 3] + "..."


# ==================== ROUTES ====================

@router.get("")
async def get_plans(current_admin: dict = Depends(require_moderator_or_above)):
    """Every plan's limits, cost cap and prices, the upgrade contact texts and the owner's contact details."""
    return _snapshot()


@router.put("")
async def put_plans(body: PlansBody, current_admin: dict = Depends(require_admin_or_super)):
    """Replace all plans' limits, cost caps and the upgrade contact (and the owner's contact details when
    `owner_contact` is sent, and every plan's prices when any plan sends a price field, and the family limits any plan sends). 422 carries the validation
    message."""
    before = _snapshot()
    plan_rows = {plan: {f: lim.model_dump() for f, lim in p.limits.items()} for plan, p in body.plans.items()}
    caps = {plan: p.cost_cap_usd for plan, p in body.plans.items()}
    # A body with no price field at all (an older admin panel) leaves the prices alone; otherwise a plan without
    # them has none.
    sends_prices = any({"price_monthly_mmk", "price_yearly_mmk"} & p.model_fields_set for p in body.plans.values())
    prices = ({plan: {"monthly_mmk": p.price_monthly_mmk, "yearly_mmk": p.price_yearly_mmk}
               for plan, p in body.plans.items()} if sends_prices else None)
    # A family limit left out (or null) keeps the plan's stored value; a body with none at all leaves them all alone.
    sends_family = any(p.family_max_members is not None or p.family_max_placeholders is not None
                       for p in body.plans.values())
    family = ({plan: {"max_members": before["plans"][plan]["family_max_members"] if p.family_max_members is None
                      else p.family_max_members,
                      "max_placeholders": before["plans"][plan]["family_max_placeholders"]
                      if p.family_max_placeholders is None else p.family_max_placeholders}
               for plan, p in body.plans.items()} if sends_family else None)
    try:
        await store.save(plan_rows, caps, body.upgrade_contact.model_dump(), current_admin["_id"],
                         (body.owner_contact.model_dump(include=body.owner_contact.model_fields_set)
                          if body.owner_contact is not None else None), prices, family)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e))

    after = _snapshot()
    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"],
        action="plans_update",
        details=_changes(before, after),
    )
    return after


# ==================== UPGRADE REQUESTS ====================
# Users ask for Plus or Pro from the app (POST /api/plan/upgrade-request); the owner sees the requests here, changes
# the user's plan by hand (which marks the request done by itself, see admin_routes.update_user_subscription) or
# dismisses it. Moderators can view; admins and super admins can handle.

requests_router = APIRouter(prefix="/api/admin/upgrade-requests", tags=["admin", "plans"])


def grant_until(user: dict, plan: str, billing: Optional[str], now: datetime) -> datetime:
    """When a granted request's plan should end: 30 days ("month" or no billing) or 365 days ("year") after the base.
    The base is the person's current end date when they hold a paid plan, not on a trial, of at least the requested
    rank, that is still running (a renewal adds to it); otherwise now."""
    base = now
    have = effective_plan(user, now)
    ends = user.get("subscription_expires_at")
    if (have != "free" and not is_trial(user, now) and PLAN_RANK[have] >= PLAN_RANK[plan]
            and ends is not None and as_utc(ends) > now):
        base = as_utc(ends)
    return base + timedelta(days=365 if billing == "year" else 30)


def _request_row(row: dict) -> dict:
    plan = effective_plan({"subscription_type": row["subscription_type"],
                           "subscription_expires_at": row["subscription_expires_at"]})
    on_trial = plan != "free" and is_trial({"trial_ends_at": row["trial_ends_at"]})
    # A renewal: a pending request for the paid plan the user has now (not a trial, which asks to buy the plan it is
    # trying). Worked out when the list is read; a handled request is never marked, since by then the user usually
    # has the plan they asked for whether it was a renewal or an upgrade.
    is_renewal = row["status"] == "pending" and not on_trial and plan == row["plan"]
    out = {
        "id": row["_id"],
        "user_id": row["user_id"],
        "name": row["user_name"],
        "email": row["user_email"],
        "current_plan": plan,
        "is_trial": on_trial,
        # When the trial ends, for "On trial until {date}" in the admin panel; null when the user is not on a trial.
        "trial_ends_at": row["trial_ends_at"].isoformat() if on_trial else None,
        "requested_plan": row["plan"],
        "is_renewal": is_renewal,
        "note": row["note"],
        # The number the user gave for the owner to contact them on Viber; null: contact them by their account email.
        "viber_number": row["viber_number"],
        # "month" / "year": the price the user picked; null when the plan had no price shown.
        "billing": row["billing"],
        "created_at": row["created_at"].isoformat(),
        "status": row["status"],
        "handled_at": row["handled_at"].isoformat() if row["handled_at"] else None,
    }
    if row["status"] == "pending":
        # What the one-click grant would set the plan's end to, for the panel's "Grant until" button.
        out["grant_until"] = grant_until(row, row["plan"], row["billing"], datetime.now(UTC)).isoformat()
    return out


def _already_handled() -> HTTPException:
    return HTTPException(status_code=status.HTTP_409_CONFLICT,
                         detail={"code": "request_already_handled", "message": "This request was already handled."})


@requests_router.get("")
async def list_upgrade_requests(
    status_filter: Literal["pending", "done", "dismissed"] = Query("pending", alias="status"),
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=200),
    current_admin: dict = Depends(require_moderator_or_above),
):
    """Requests in one status (default pending), each with the user's name, email and current effective plan."""
    rows = await requests_db.list_with_users(status_filter, skip, limit)
    return [_request_row(r) for r in rows]


async def _handle(request_id: str, new_status: str, action: str, current_admin: dict) -> dict:
    request = await requests_db.get(request_id)
    if not request:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Upgrade request not found")
    row = await requests_db.mark(request_id, new_status, current_admin["_id"], datetime.now(UTC))
    if row is None:  # handled in the meantime, or already handled
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="This request has already been handled")
    user = await users_db.get_user(request["user_id"])
    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"],
        action=action,
        target_user_id=request["user_id"],
        target_user_email=user["email"] if user else None,
        details=f"Upgrade request for {request['plan']}: {new_status}",
    )
    # A dismissal is the one answer the user is not otherwise shown (an admin plan change tells them itself; "done" is
    # bookkeeping), so tell them. Never fails the call.
    if new_status == "dismissed" and user:
        await notify_upgrade_request_declined(user, request["plan"])
    return {"id": row["_id"], "status": row["status"], "handled_at": row["handled_at"].isoformat()}


@requests_router.post("/{request_id}/done")
async def mark_upgrade_request_done(request_id: str = Path(...),
                                    current_admin: dict = Depends(require_admin_or_super)):
    """The owner has dealt with the request (for instance by changing the user's plan by hand)."""
    return await _handle(request_id, "done", "upgrade_request_done", current_admin)


@requests_router.post("/{request_id}/dismiss")
async def dismiss_upgrade_request(request_id: str = Path(...),
                                  current_admin: dict = Depends(require_admin_or_super)):
    """Turn the request down without changing the user's plan."""
    return await _handle(request_id, "dismissed", "upgrade_request_dismissed", current_admin)


class GrantBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    expires_at: Optional[datetime] = None


@requests_router.post("/{request_id}/grant")
async def grant_upgrade_request(request_id: str = Path(...), body: Optional[GrantBody] = None,
                                current_admin: dict = Depends(require_admin_or_super)):
    """Give the person the plan they asked for, until `expires_at` (default: grant_until), and close the request."""
    request = await requests_db.get(request_id)
    if not request:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Upgrade request not found")
    if request["status"] != "pending":
        raise _already_handled()
    user = await users_db.get_user(request["user_id"])
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    now = datetime.now(UTC)
    expires_at = body.expires_at if body and body.expires_at else None
    if expires_at is None:
        expires_at = grant_until(user, request["plan"], request["billing"], now)
    elif as_utc(expires_at) <= now:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                            detail="The end date must be in the future")
    # Closed first, by a conditional update: of two grants at once only one gets past here, so the plan is extended once.
    row = await requests_db.mark(request_id, "done", current_admin["_id"], now)
    if row is None:
        raise _already_handled()
    await apply_plan(current_admin, user, request["plan"], expires_at)
    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"],
        action="upgrade_request_granted",
        target_user_id=user["_id"],
        target_user_email=user["email"],
        details=f"{request['plan']} until {as_utc(expires_at).date().isoformat()}",
    )
    fresh = await users_db.get_user(user["_id"])
    return _request_row({**row, "user_name": fresh["name"], "user_email": fresh["email"],
                         "subscription_type": fresh["subscription_type"],
                         "subscription_expires_at": fresh.get("subscription_expires_at"),
                         "trial_ends_at": fresh.get("trial_ends_at")})
