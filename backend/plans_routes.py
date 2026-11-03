"""The user's plan for the app (GET /api/plan), upgrade requests (POST /api/plan/upgrade-request) and the HTTP
rendering of plan errors.

GET /api/plan gives the app everything it shows about plans: the effective plan, its end date and trial state, each
feature's allowance this period, every plan's limits (for the Upgrade screen), the upgrade contact texts and the
user's pending upgrade request (or null). Costs and cost caps are never included.
Upgrades are manual: a user asks for Plus or Pro here and the owner handles the request in the admin panel.
"""
from datetime import datetime, UTC
from typing import Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, field_validator

from notification_service import translate
from plans import quota
from plans.access import PlanError, effective_plan, user_language
from plans.catalog import PLAN_RANK
from sql import upgrade_requests as requests_db
from utils import get_current_user

router = APIRouter(prefix="/api", tags=["plans"])

MAX_NOTE_LENGTH = 500


class UpgradeRequestBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    plan: Literal["plus", "pro"]
    note: Optional[str] = None

    @field_validator("note")
    @classmethod
    def _clean_note(cls, value: Optional[str]) -> Optional[str]:
        """Stripped; empty becomes None."""
        value = (value or "").strip()
        if len(value) > MAX_NOTE_LENGTH:
            raise ValueError(f"Note must be at most {MAX_NOTE_LENGTH} characters")
        return value or None


@router.get("/plan")
async def get_plan(current_user: dict = Depends(get_current_user)):
    body = await quota.status(current_user)
    pending = await requests_db.get_pending(current_user["_id"])
    body["upgrade_request"] = (
        {"plan": pending["plan"], "note": pending["note"], "created_at": pending["created_at"].isoformat()}
        if pending else None)
    return body


@router.post("/plan/upgrade-request")
async def request_upgrade(body: UpgradeRequestBody, current_user: dict = Depends(get_current_user)):
    """Ask the owner for Plus or Pro. A pending request is updated in place (plan, note, date) rather than added to.

    400 when the user already has that plan or a higher one (Pro counts as Plus).
    """
    current = effective_plan(current_user)
    if PLAN_RANK[current] >= PLAN_RANK[body.plan]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=translate("plan_upgrade_request_already", user_language(current_user), plan=body.plan.capitalize()))
    row = await requests_db.upsert_pending(current_user["_id"], body.plan, body.note, datetime.now(UTC))
    return {"plan": row["plan"], "note": row["note"], "status": row["status"],
            "created_at": row["created_at"].isoformat()}


async def plan_error_handler(request: Request, exc: PlanError) -> JSONResponse:
    """App-level handler: 403 / 429 with {"detail": {"code", "feature", "resets_at", "upgrade_available", "message"}}."""
    return JSONResponse(status_code=exc.status, content={"detail": exc.detail()})
