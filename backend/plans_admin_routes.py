"""Admin API for plans: every plan's per-feature limits, monthly AI cost cap and the upgrade contact texts.

Moderators can view; admins and super admins can change. A change applies in this process at once and in
other workers within a minute (plans.store refreshes every 60 s). Every change is written to the admin action log.
"""
from typing import Dict, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, StrictFloat, StrictInt

from admin_utils import log_admin_action, require_admin_or_super, require_moderator_or_above
from plans import store
from plans.catalog import FEATURES, PLANS, Limit

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
