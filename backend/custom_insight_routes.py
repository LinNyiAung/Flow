"""Custom insights (Pro): the HTTP API under /api/custom-insights.

POST ""                    create a report (or answer with a reusable one), 202 / 200
GET  ""                    the user's reports (summaries), any plan
GET  "/{id}"               one report with its content and figures
POST "/{id}/translate"     the Myanmar text of a ready report
DELETE "/{id}"             delete a ready report; failed / refused ones are hidden but still count as attempts

The writing itself runs in the background (custom_insights_service.start_report). A plan refusal (locked, limit reached,
cost cap) is a PlanError, rendered by the app-wide handler; the other refusals are {"detail": {"code", "message",
"resets_at"}} with the message in the user's language.
"""
import logging
import uuid
from datetime import date, datetime
from typing import Any, Dict, Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel, ConfigDict

import custom_insights_service as cis
from insights_service import InsightAIError, is_rate_limit_error, translate_insight_to_myanmar
from notification_service import translate as translate_text
from plans import quota
from plans.access import user_language
from sql import custom_insights as ci
from sql import transactions as transactions_db
from tz_utils import app_today, as_utc, day_bounds_utc, utc_now
from utils import get_current_user

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/custom-insights", tags=["custom insights"])


class CustomInsightCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    start_date: date
    end_date: date
    preset: Optional[Literal["where_to_save", "compare_previous", "biggest_changes", "budgets_goals"]] = None
    instruction: Optional[str] = None


def _iso(value: Optional[datetime]) -> Optional[str]:
    return as_utc(value).isoformat() if value else None


_MESSAGE_KEYS = {  # error code -> NOTIFICATION_TRANSLATIONS key
    "custom_insight_invalid_range": "custom_insight_range_msg",
    "custom_insight_invalid_instruction": "custom_insight_instruction_msg",
    "custom_insight_no_data": "custom_insight_no_data_msg",
    "custom_insight_pending": "custom_insight_pending_msg",
    "custom_insight_attempts": "custom_insight_attempts_msg",
    "custom_insight_not_ready": "custom_insight_not_ready_msg",
}


def _error(user: dict, http_status: int, code: str, resets_at: Optional[datetime] = None) -> HTTPException:
    """{"detail": {"code", "message" (the user's language), "resets_at"}}."""
    message = translate_text(_MESSAGE_KEYS[code], user_language(user))
    return HTTPException(status_code=http_status, detail={"code": code, "message": message, "resets_at": _iso(resets_at)})


def _summary(row: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": row["_id"],
        "start_date": row["start_date"].isoformat(),
        "end_date": row["end_date"].isoformat(),
        "preset": row.get("preset"),
        "instruction": row.get("instruction"),
        "status": row["status"],
        "created_at": _iso(row["created_at"]),
        "completed_at": _iso(row.get("completed_at")),
        "has_myanmar": bool(row.get("content_mm")),
    }


def _detail(row: Dict[str, Any]) -> Dict[str, Any]:
    """The summary plus the text (English and any stored Myanmar, whatever the current plan) and the figures."""
    return {**_summary(row), "content": row.get("content"), "content_mm": row.get("content_mm"),
            "figures": row.get("figures")}


def _not_found() -> HTTPException:
    return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Custom insight not found")


@router.post("")
async def create_custom_insight(data: CustomInsightCreate, response: Response,
                                current_user: dict = Depends(get_current_user)):
    """Create a custom insight, or answer 200 with the user's earlier report when nothing has changed since (no use is
    counted). Otherwise reserve one use, insert a pending report and start writing it: 202."""
    uid = current_user["_id"]
    instruction = (data.instruction or "").strip() or None
    if instruction and (data.preset or len(instruction) > cis.MAX_INSTRUCTION_LENGTH):  # a preset OR an instruction
        raise _error(current_user, status.HTTP_422_UNPROCESSABLE_ENTITY, "custom_insight_invalid_instruction")
    try:
        cis.validate_range(data.start_date, data.end_date, app_today())
    except cis.RangeError:
        raise _error(current_user, status.HTTP_422_UNPROCESSABLE_ENTITY, "custom_insight_invalid_range")

    quota.require_unlocked(current_user, cis.FEATURE)  # PlanError: 403 plan_feature_locked

    figures = await cis.compute_figures(uid, data.start_date, data.end_date)
    if not figures["currencies"]:
        raise _error(current_user, status.HTTP_422_UNPROCESSABLE_ENTITY, "custom_insight_no_data")

    key = cis.instruction_key(data.preset, instruction)
    match = await ci.find_ready_match(uid, data.start_date, data.end_date, key)
    if match is not None:
        # Reusable only when nothing in the range was created or edited since, and the figures (which also see a deleted
        # transaction, or one moved out of the range) are the ones the report was written from.
        start_utc, end_utc = day_bounds_utc(data.start_date, data.end_date)
        changed = await transactions_db.changed_since(uid, start_utc, end_utc, match["created_at"])
        if not changed and match.get("figures") == figures:
            return {"report": _detail(match), "reused": True}  # 200: nothing reserved, nothing started

    if await ci.has_pending(uid):
        raise _error(current_user, status.HTTP_409_CONFLICT, "custom_insight_pending")
    now = utc_now()
    if await ci.count_attempts_since(uid, cis.attempts_window_start(now)) >= cis.MAX_FAILED_ATTEMPTS_PER_DAY:
        raise _error(current_user, status.HTTP_429_TOO_MANY_REQUESTS, "custom_insight_attempts",
                     resets_at=cis.attempts_reset_at(now))

    reservation = await quota.reserve(current_user, cis.FEATURE)  # PlanError: limit reached, cost cap
    report_id = str(uuid.uuid4())
    try:
        inserted = await ci.insert_pending({
            "_id": report_id, "user_id": uid, "start_date": data.start_date, "end_date": data.end_date,
            "preset": data.preset, "instruction": instruction, "instruction_key": key,
            "counter_keys": [[f, p, d.isoformat()] for f, p, d in reservation.keys], "figures": figures})
    except BaseException:
        await quota.give_back(reservation)
        raise
    if not inserted:  # a second request got in first: one pending report per user
        await quota.give_back(reservation)
        raise _error(current_user, status.HTTP_409_CONFLICT, "custom_insight_pending")
    reservation.commit()
    cis.start_report(report_id)
    response.status_code = status.HTTP_202_ACCEPTED
    return {"report": _detail(await ci.get(report_id, uid)), "reused": False}


@router.get("")
async def list_custom_insights(current_user: dict = Depends(get_current_user)):
    """The user's reports, newest first (at most 100), without their text. Open to every plan."""
    rows = await ci.list_for_user(current_user["_id"], limit=100)
    return {"reports": [_summary(r) for r in rows]}


@router.get("/{report_id}")
async def get_custom_insight(report_id: str, current_user: dict = Depends(get_current_user)):
    row = await ci.get(report_id, current_user["_id"])
    if row is None:
        raise _not_found()
    return _detail(row)


@router.post("/{report_id}/translate")
async def translate_custom_insight(report_id: str, current_user: dict = Depends(get_current_user)):
    """The Myanmar text of a ready report. A stored translation is returned as it is (nothing reserved, any plan).
    Otherwise one use of insight_translation is reserved (PlanError when the plan locks it, at the cost cap or used up)
    and given back if the translation fails."""
    uid = current_user["_id"]
    row = await ci.get(report_id, uid)
    if row is None:
        raise _not_found()
    if row["status"] != "ready":
        raise _error(current_user, status.HTTP_409_CONFLICT, "custom_insight_not_ready")
    if row.get("content_mm"):
        return _detail(row)

    reservation = await quota.reserve(current_user, "insight_translation")
    try:
        content_mm = await translate_insight_to_myanmar(row["content"], user_id=uid, is_placeholder=False)
        await ci.set_translation(report_id, content_mm)
        row = await ci.get(report_id, uid)
    except InsightAIError as e:
        await quota.give_back(reservation)
        logger.error("Custom insight %s: translation failed: %s", report_id, e)
        if is_rate_limit_error(e):
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="The AI service is busy right now (rate limit reached). Please try again in a few minutes.",
                headers={"Retry-After": "60"})
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="The AI service is temporarily unavailable, so we couldn't translate your insight. Please try again later.")
    except BaseException:
        await quota.give_back(reservation)
        raise
    if row is None or not row.get("content_mm"):  # deleted while it was being translated
        await quota.give_back(reservation)
        raise _not_found()
    reservation.commit()
    return _detail(row)


@router.delete("/{report_id}")
async def delete_custom_insight(report_id: str, current_user: dict = Depends(get_current_user)):
    """Delete a ready report. A failed or refused one is only hidden (it still counts towards the daily attempt limit);
    one still being written cannot be deleted."""
    outcome = await ci.delete_for_user(report_id, current_user["_id"], utc_now())
    if outcome in ("deleted", "hidden"):
        return {"deleted": True}
    if outcome == "pending":
        raise _error(current_user, status.HTTP_409_CONFLICT, "custom_insight_not_ready")
    raise _not_found()
