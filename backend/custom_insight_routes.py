"""Custom insights (Pro): the HTTP API under /api/custom-insights.

POST ""                    create a report (or answer with a reusable one), 202 / 200
GET  ""                    the user's reports (summaries), any plan; 30 a page, ?before=<next_before> for the next
GET  "/{id}"               one report with its content and figures
POST "/{id}/translate"     the Myanmar text of a ready report
DELETE "/{id}"             delete a ready report; failed / refused ones are hidden but still count as attempts

The writing itself runs in the background (custom_insights_service.start_report). A plan refusal (locked, limit reached,
cost cap) is a PlanError, rendered by the app-wide handler; the other refusals are {"detail": {"code", "message",
"resets_at"}} with the message in the user's language.
"""
import asyncio
import base64
import binascii
import logging
import re
import uuid
from datetime import datetime
from typing import Any, Dict, Literal, Optional, Tuple

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from pydantic import BaseModel, ConfigDict

import app_control
import custom_insights_service as cis
from insights_service import InsightAIError, is_rate_limit_error, translate_insight_to_myanmar
from notification_service import translate as translate_text
from plans import quota
from plans.access import user_language
from sql import budgets as budgets_db
from sql import custom_insights as ci
from sql import goals as goals_db
from sql import transactions as transactions_db
from tz_utils import CalendarDate, as_utc, day_bounds, local_today, utc_now
from families.book import Book, get_book, require_admin, require_writable
from user_zones import user_zone

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/custom-insights", tags=["custom insights"])


class CustomInsightCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    start_date: CalendarDate  # first and last day, inclusive
    end_date: CalendarDate
    preset: Optional[Literal[tuple(cis.PRESETS)]] = None  # the service's own preset keys
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


PAGE_SIZE = 30
GOALS_BUDGETS_PRESET = "budgets_goals"  # its reuse also checks goals and budgets
# C0 control characters other than tab, newline and carriage return, and DEL (Postgres text cannot even store NUL).
_BAD_INSTRUCTION_CHARS = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")


def _error(user: dict, http_status: int, code: str, resets_at: Optional[datetime] = None,
           message_key: Optional[str] = None) -> HTTPException:
    """{"detail": {"code", "message" (the user's language), "resets_at"}}. message_key: another text for the code."""
    message = translate_text(message_key or _MESSAGE_KEYS[code], user_language(user))
    return HTTPException(status_code=http_status, detail={"code": code, "message": message, "resets_at": _iso(resets_at)})


def _cursor(row: Dict[str, Any]) -> str:
    """The opaque `next_before` of a page ending at `row`: its created_at and id, base64url."""
    raw = f"{as_utc(row['created_at']).isoformat()}|{row['_id']}".encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def _parse_cursor(value: str) -> Tuple[datetime, str]:
    """(created_at, id) from a `next_before`; ValueError for anything else."""
    try:
        raw = base64.urlsafe_b64decode(value + "=" * (-len(value) % 4)).decode()
    except (binascii.Error, UnicodeDecodeError) as e:
        raise ValueError("not a cursor") from e
    stamp, sep, report_id = raw.partition("|")
    created_at = datetime.fromisoformat(stamp)  # ValueError for a bad stamp
    if not sep or not report_id or created_at.tzinfo is None:
        raise ValueError("not a cursor")
    return created_at, report_id


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
        "has_myanmar": bool(row["has_myanmar"]) if "has_myanmar" in row else bool(row.get("content_mm")),
    }


def _detail(row: Dict[str, Any]) -> Dict[str, Any]:
    """The summary plus the text (English and any stored Myanmar, whatever the current plan) and the figures."""
    return {**_summary(row), "content": row.get("content"), "content_mm": row.get("content_mm"),
            "figures": row.get("figures")}


def _not_found() -> HTTPException:
    return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Custom insight not found")


@router.post("")
async def create_custom_insight(data: CustomInsightCreate, response: Response,
                                book: Book = Depends(get_book)):
    """Create a custom insight, or answer 200 with the user's earlier report when nothing has changed since (no use is
    counted). Otherwise reserve one use, insert a pending report and start writing it: 202.

    The report is about, and stored under, the request's book (a family shares its list); the plan check and the use
    are the person's (counter_keys then name the person, see custom_insights_service._reservation). A family's new
    report needs a writable family (R10)."""
    app_control.require_on("custom_reports", user_language(book.person))
    require_writable(book)
    current_user = book.person
    book_id = book.id
    instruction = (data.instruction or "").strip() or None
    if instruction and (data.preset or len(instruction) > cis.MAX_INSTRUCTION_LENGTH):  # a preset OR an instruction
        raise _error(current_user, status.HTTP_422_UNPROCESSABLE_ENTITY, "custom_insight_invalid_instruction")
    if instruction and _BAD_INSTRUCTION_CHARS.search(instruction):
        raise _error(current_user, status.HTTP_422_UNPROCESSABLE_ENTITY, "custom_insight_invalid_instruction",
                     message_key="custom_insight_instruction_chars_msg")
    try:
        cis.validate_range(data.start_date, data.end_date, local_today(user_zone(current_user)))  # the asker's today
    except cis.RangeError:
        raise _error(current_user, status.HTTP_422_UNPROCESSABLE_ENTITY, "custom_insight_invalid_range")

    quota.require_unlocked(current_user, cis.FEATURE)  # PlanError: 403 plan_feature_locked

    figures = await cis.compute_figures(book_id, data.start_date, data.end_date)
    if not figures["currencies"]:
        raise _error(current_user, status.HTTP_422_UNPROCESSABLE_ENTITY, "custom_insight_no_data")

    key = cis.instruction_key(data.preset, instruction)
    match = await ci.find_ready_match(book_id, data.start_date, data.end_date, key)
    if match is not None:
        # Reusable only when nothing in the range was created or edited since, and the figures (which also see a deleted
        # transaction, or one moved out of the range) are the ones the report was written from. The "Check my budgets and
        # goals" report is about the goals and budgets themselves, so for it a goal created or edited since, or a budget
        # overlapping the range created since, makes it stale too. Budget edits are not seen (budgets.updated_at also
        # moves on every spend recompute), nor are deleted goals or budgets.
        since = match["created_at"]
        changed = await transactions_db.changed_since(book_id, *day_bounds(data.start_date, data.end_date), since)
        if not changed and data.preset == GOALS_BUDGETS_PRESET:
            changed = (await goals_db.changed_since(book_id, since)
                       or await budgets_db.created_since(book_id, data.start_date, data.end_date, since))
        if not changed and match.get("figures") == figures:
            return {"report": _detail(match), "reused": True}  # 200: nothing reserved, nothing started

    if await ci.has_pending(book_id):
        raise _error(current_user, status.HTTP_409_CONFLICT, "custom_insight_pending")
    now = utc_now()
    attempts = await ci.attempt_times_since(book_id, cis.attempts_window_start(now))
    if len(attempts) >= cis.MAX_FAILED_ATTEMPTS_PER_DAY:
        raise _error(current_user, status.HTTP_429_TOO_MANY_REQUESTS, "custom_insight_attempts",
                     resets_at=cis.attempts_reset_at(attempts))

    reservation = await quota.reserve(current_user, cis.FEATURE)  # PlanError: limit reached, cost cap
    report_id = str(uuid.uuid4())
    row = {"_id": report_id, "book_id": book_id, "start_date": data.start_date, "end_date": data.end_date,
           "preset": data.preset, "instruction": instruction, "instruction_key": key,
           "counter_keys": cis.counter_keys(reservation, book.is_family), "figures": figures,
           "created_at": utc_now()}
    try:
        inserted = await ci.insert_pending(row)
    except BaseException:
        # The insert may have committed before the error reached us (a cancellation after Postgres committed but before
        # execute returned). The row then owns the reservation through its counter_keys and the sweeper gives it back,
        # so giving it back here too would give it back twice. Give back only when the row is surely not there; if the
        # lookup fails as well, leave it: if the row exists the sweeper gives the use back, if not it stays counted.
        try:
            exists = await asyncio.shield(ci.get(report_id, book_id, include_deleted=True)) is not None
        except BaseException:  # noqa: BLE001 - unknown, see above
            exists = True
        if not exists:
            await quota.give_back(reservation)
        raise
    if not inserted:  # a second request got in first: one pending report per user
        await quota.give_back(reservation)
        raise _error(current_user, status.HTTP_409_CONFLICT, "custom_insight_pending")
    # The 202 body is the row just inserted (always pending), so nothing can fail between the insert and the start: once
    # the row exists it owns the reservation (its counter_keys), and the job or the sweeper gives it back.
    reservation.commit()
    cis.start_report(report_id)
    response.status_code = status.HTTP_202_ACCEPTED
    return {"report": _detail({**row, "status": "pending", "completed_at": None, "content": None, "content_mm": None}),
            "reused": False}


@router.get("")
async def list_custom_insights(before: Optional[str] = Query(None), book: Book = Depends(get_book)):
    """The user's reports, newest first, PAGE_SIZE at a time, without their text. Open to every plan.

    `next_before` is null on the last page; otherwise pass it back as `before` for the next (older) page."""
    cursor = None
    if before:
        try:
            cursor = _parse_cursor(before)
        except ValueError:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Invalid 'before' cursor")
    rows = await ci.list_summaries(book.id, limit=PAGE_SIZE + 1, before=cursor)
    more = len(rows) > PAGE_SIZE
    rows = rows[:PAGE_SIZE]
    return {"reports": [_summary(r) for r in rows], "next_before": _cursor(rows[-1]) if more else None}


@router.get("/{report_id}")
async def get_custom_insight(report_id: str, book: Book = Depends(get_book)):
    row = await ci.get(report_id, book.id)
    if row is None:
        raise _not_found()
    return _detail(row)


@router.post("/{report_id}/translate")
async def translate_custom_insight(report_id: str, book: Book = Depends(get_book)):
    """The Myanmar text of a ready report. A stored translation is returned as it is (nothing reserved, any plan).
    Otherwise one use of insight_translation is reserved (PlanError when the plan locks it, at the cost cap or used up)
    and given back if the translation fails. The report is the book's; the use (and the AI cost) the person's."""
    current_user = book.person
    book_id = book.id
    row = await ci.get(report_id, book_id)
    if row is None:
        raise _not_found()
    if row["status"] != "ready":
        raise _error(current_user, status.HTTP_409_CONFLICT, "custom_insight_not_ready")
    if row.get("content_mm"):
        return _detail(row)  # reading a stored translation works while translation is paused

    app_control.require_on("translation", user_language(current_user))  # only when a translation would be made
    reservation = await quota.reserve(current_user, "insight_translation")
    try:
        content_mm = await translate_insight_to_myanmar(row["content"], user_id=current_user["_id"],
                                                        is_placeholder=False)
        wrote = await ci.set_translation(report_id, content_mm)
        row = await ci.get(report_id, book_id)
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
    if wrote:
        reservation.commit()
    else:  # a simultaneous request stored its translation first: that text stands, and this one costs nothing
        await quota.give_back(reservation)
    return _detail(row)


@router.delete("/{report_id}")
async def delete_custom_insight(report_id: str, book: Book = Depends(get_book)):
    """Delete a ready report. A failed or refused one is only hidden (it still counts towards the daily attempt limit);
    one still being written cannot be deleted. A family's reports are shared: deleting one needs a writable family and
    the owner or an admin (R10)."""
    require_writable(book)
    require_admin(book)
    outcome = await ci.delete_for_user(report_id, book.id, utc_now())
    if outcome in ("deleted", "hidden"):
        return {"deleted": True}
    if outcome == "pending":
        raise _error(book.person, status.HTTP_409_CONFLICT, "custom_insight_not_ready")
    raise _not_found()
