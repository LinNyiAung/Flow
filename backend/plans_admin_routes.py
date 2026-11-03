"""Admin API for plans: every plan's per-feature limits, monthly AI cost cap and the upgrade contact texts, and the
users' upgrade requests (at the end of this file).

Moderators can view; admins and super admins can change. A change applies in this process at once and in
other workers within a minute (plans.store refreshes every 60 s). Every change is written to the admin action log.
"""
from datetime import datetime, UTC
from typing import Dict, Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Path, Query, status
from pydantic import BaseModel, ConfigDict, StrictFloat, StrictInt

from admin_utils import log_admin_action, require_admin_or_super, require_moderator_or_above
from plans import store
from plans.access import effective_plan, is_trial
from plans.catalog import FEATURES, PLANS, Limit
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


class ContactBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    en: str
    my: str


class PlansBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    plans: Dict[str, PlanBody]
    upgrade_contact: ContactBody


# ==================== HELPERS ====================

def _snapshot() -> dict:
    """What the store holds now, in the API's JSON shape."""
    return {
        "plans": {
            plan: {
                "limits": {f: {"mode": lim.mode, "quota": lim.quota, "period": lim.period}
                           for f, lim in store.limits(plan).items()},
                "cost_cap_usd": store.cost_cap(plan),
            }
            for plan in PLANS
        },
        "upgrade_contact": store.upgrade_contact(),
    }


def _fmt(lim: dict) -> str:
    return f"counted {lim['quota']}/{lim['period']}" if lim["mode"] == "counted" else lim["mode"]


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
    for lang in ("en", "my"):
        if before["upgrade_contact"][lang] != after["upgrade_contact"][lang]:
            out.append(f"upgrade contact ({lang}) changed")
    text = "; ".join(out) if out else "no changes"
    return text if len(text) <= MAX_LOG_DETAILS else text[:MAX_LOG_DETAILS - 3] + "..."


# ==================== ROUTES ====================

@router.get("")
async def get_plans(current_admin: dict = Depends(require_moderator_or_above)):
    """Every plan's limits and cost cap, and the upgrade contact texts."""
    return _snapshot()


@router.put("")
async def put_plans(body: PlansBody, current_admin: dict = Depends(require_admin_or_super)):
    """Replace all plans' limits, cost caps and the upgrade contact. 422 carries the validation message."""
    before = _snapshot()
    plan_rows = {plan: {f: lim.model_dump() for f, lim in p.limits.items()} for plan, p in body.plans.items()}
    caps = {plan: p.cost_cap_usd for plan, p in body.plans.items()}
    try:
        await store.save(plan_rows, caps, body.upgrade_contact.model_dump(), current_admin["_id"])
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


def _request_row(row: dict) -> dict:
    plan = effective_plan({"subscription_type": row["subscription_type"],
                           "subscription_expires_at": row["subscription_expires_at"]})
    on_trial = plan != "free" and is_trial({"trial_ends_at": row["trial_ends_at"]})
    return {
        "id": row["_id"],
        "user_id": row["user_id"],
        "name": row["user_name"],
        "email": row["user_email"],
        "current_plan": plan,
        "is_trial": on_trial,
        # When the trial ends, for "On trial until {date}" in the admin panel; null when the user is not on a trial.
        "trial_ends_at": row["trial_ends_at"].isoformat() if on_trial else None,
        "requested_plan": row["plan"],
        "note": row["note"],
        "created_at": row["created_at"].isoformat(),
        "status": row["status"],
        "handled_at": row["handled_at"].isoformat() if row["handled_at"] else None,
    }


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
