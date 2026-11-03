"""The user's plan for the app (GET /api/plan) and the HTTP rendering of plan errors.

GET /api/plan gives the app everything it shows about plans: the effective plan, its end date and trial state, each
feature's allowance this period, every plan's limits (for the Upgrade screen) and the upgrade contact texts.
Costs and cost caps are never included.
"""
from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse

from plans import quota
from plans.access import PlanError
from utils import get_current_user

router = APIRouter(prefix="/api", tags=["plans"])


@router.get("/plan")
async def get_plan(current_user: dict = Depends(get_current_user)):
    return await quota.status(current_user)


async def plan_error_handler(request: Request, exc: PlanError) -> JSONResponse:
    """App-level handler: 403 / 429 with {"detail": {"code", "feature", "resets_at", "upgrade_available", "message"}}."""
    return JSONResponse(status_code=exc.status, content={"detail": exc.detail()})
