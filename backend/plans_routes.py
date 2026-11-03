"""The user's plan for the app (GET /api/plan), upgrade requests (POST /api/plan/upgrade-request) and the HTTP
rendering of plan errors.

GET /api/plan gives the app everything it shows about plans: the effective plan, its end date and trial state, each
feature's allowance this period, every plan's limits (for the Upgrade screen), the upgrade contact texts, the owner's
email and Viber number and the user's pending upgrade request (or null; it carries the Viber number they gave). Costs and cost caps are never included.
Upgrades are manual: a user asks for Plus or Pro here and the owner handles the request in the admin panel.
"""
from datetime import datetime, UTC
from typing import Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, field_validator

from notification_service import translate
from plans import quota
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
    return {"plan": row["plan"], "note": row["note"], "viber_number": row["viber_number"],
            "created_at": row["created_at"].isoformat()}


@router.get("/plan")
async def get_plan(current_user: dict = Depends(get_current_user)):
    body = await quota.status(current_user)
    pending = await requests_db.get_pending(current_user["_id"])
    body["upgrade_request"] = _request_json(pending) if pending else None
    return body


@router.post("/plan/upgrade-request")
async def request_upgrade(body: UpgradeRequestBody, current_user: dict = Depends(get_current_user)):
    """Ask the owner for Plus or Pro. A pending request is updated in place (plan, note, Viber number, date) rather than added to.

    400 when the user already has that plan or a higher one (Pro counts as Plus). A free trial of Plus does not count
    as having Plus here: a trial user may ask to keep it.
    """
    current = effective_plan(current_user)
    if is_trial(current_user):
        current = "free"
    if PLAN_RANK[current] >= PLAN_RANK[body.plan]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=translate("plan_upgrade_request_already", user_language(current_user), plan=body.plan.capitalize()))
    row = await requests_db.upsert_pending(current_user["_id"], body.plan, body.note, datetime.now(UTC),
                                           body.viber_number)
    return {**_request_json(row), "status": row["status"]}


async def plan_error_handler(request: Request, exc: PlanError) -> JSONResponse:
    """App-level handler: 403 / 429 with {"detail": {"code", "feature", "resets_at", "upgrade_available", "message"}}."""
    return JSONResponse(status_code=exc.status, content={"detail": exc.detail()})
