"""The user's plan for the app (GET /api/plan), upgrade requests (POST /api/plan/upgrade-request) and the HTTP
rendering of plan errors.

GET /api/plan gives the app everything it shows about plans: the effective plan, its end date and trial state, each
feature's allowance this period, every plan's limits and prices (for the Upgrade screen), the upgrade contact texts, the owner's
contact details (email, Viber, Telegram, Facebook page and Messenger links) and the user's pending upgrade request (or null; it carries the Viber number and billing period they gave). Costs and cost caps are never included.
Upgrades are manual: a user asks for Plus or Pro here and the owner handles the request in the admin panel.
"""
from datetime import datetime, UTC
from typing import Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, field_validator

from notification_service import translate
from plans import quota, store
from plans.access import PlanError, effective_plan, is_trial, user_language
from plans.catalog import PLAN_RANK
from plans.contact import normalize_viber
from sql import upgrade_requests as requests_db
from utils import get_current_user

router = APIRouter(prefix="/api", tags=["plans"])

MAX_NOTE_LENGTH = 500


class UpgradeRequestBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    plan: Literal["plus", "pro"]
    note: Optional[str] = None
    viber_number: Optional[str] = None
    # The price the user picked; only when the plan has that price (the app sends it only then).
    billing: Optional[Literal["month", "year"]] = None

    @field_validator("note")
    @classmethod
    def _clean_note(cls, value: Optional[str]) -> Optional[str]:
        """Stripped; empty becomes None."""
        value = (value or "").strip()
        if len(value) > MAX_NOTE_LENGTH:
            raise ValueError(f"Note must be at most {MAX_NOTE_LENGTH} characters")
        return value or None

    @field_validator("viber_number")
    @classmethod
    def _clean_viber_number(cls, value: Optional[str]) -> Optional[str]:
        """Normalised to `+` and digits (09… becomes +959…); empty becomes None; anything else is a 422."""
        return normalize_viber(value)


def _request_json(row: dict) -> dict:
    return {"plan": row["plan"], "note": row["note"], "viber_number": row["viber_number"], "billing": row["billing"],
            "created_at": row["created_at"].isoformat()}


@router.get("/plan")
async def get_plan(current_user: dict = Depends(get_current_user)):
    body = await quota.status(current_user)
    pending = await requests_db.get_pending(current_user["_id"])
    body["upgrade_request"] = _request_json(pending) if pending else None
    return body


@router.post("/plan/upgrade-request")
async def request_upgrade(body: UpgradeRequestBody, current_user: dict = Depends(get_current_user)):
    """Ask the owner for Plus or Pro. A pending request is updated in place (plan, note, Viber number, billing period,
    date) rather than added to.

    400 when the user already has that plan or a higher one (Pro counts as Plus). A free trial of Plus does not count
    as having Plus here: a trial user may ask to keep it. A paying user whose plan has an end date may ask for that
    same plan again: a renewal (the admin list marks it, see plans_admin_routes._request_row); a lifetime plan cannot
    be renewed (400). 422 when `billing` names a price the plan does not have (renewals included).
    """
    # The app offers only the prices it was shown, so this means the owner changed them since (it names the field,
    # like the other 422s, so the app can tell).
    if body.billing is not None:
        price = store.prices(body.plan)
        if price["monthly_mmk"] is None:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                                detail=f"billing: the {body.plan.capitalize()} plan has no price")
        if body.billing == "year" and price["yearly_mmk"] is None:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                                detail=f"billing: the {body.plan.capitalize()} plan has no yearly price")
    current = effective_plan(current_user)
    if is_trial(current_user):
        current = "free"
    renewal = current == body.plan and current != "free" and current_user.get("subscription_expires_at") is not None
    if PLAN_RANK[current] >= PLAN_RANK[body.plan] and not renewal:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=translate("plan_upgrade_request_already", user_language(current_user), plan=body.plan.capitalize()))
    row = await requests_db.upsert_pending(current_user["_id"], body.plan, body.note, datetime.now(UTC),
                                           body.viber_number, body.billing)
    return {**_request_json(row), "status": row["status"]}


async def plan_error_handler(request: Request, exc: PlanError) -> JSONResponse:
    """App-level handler: 403 / 429 with {"detail": {"code", "feature", "resets_at", "upgrade_available", "message"}}."""
    return JSONResponse(status_code=exc.status, content={"detail": exc.detail()})
