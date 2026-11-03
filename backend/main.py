import asyncio
import hashlib
import json
from contextlib import aclosing
from datetime import datetime, timedelta, UTC
from typing import List, Optional

from fastapi import FastAPI, HTTPException, Request, status, Depends, Query, Path
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.exc import DBAPIError
from starlette.background import BackgroundTask

from finite_utils import SafeJSONResponse, json_safe

from firebase_service import initialize_firebase
from utils import ensure_paid, get_current_user, get_user_balance
from notification_preferences_models import NotificationPreferences, NotificationPreferencesResponse, NotificationPreferencesUpdate
from scheduler import start_scheduler
from pdf_generator import generate_financial_report_pdf
from report_models import CategoryBreakdown, FinancialReport, GoalProgress, ReportPeriod, ReportRequest
from insight_models import InsightResponse
from models import (
    CategoryResponse, Currency, TransactionType,
)
from chat_models import (
    AIProvider, ChatRequest, ChatResponse, ChatMessage, MessageRole,
)

from notification_models import FcmTokenUpdate, NotificationResponse, NotificationType, parse_notification_type
from notification_service import (
    analyze_unusual_spending,
    notify_budget_started
)

from database import initialize_admin, initialize_categories
from sql.categories import get_categories_doc
from sql import users as users_db
from sql import notification_prefs as prefs_db
from sql import notifications as notifications_db
from sql import chat as chat_db
from sql import insights as insights_db
from ai_chatbot import financial_chatbot, ChatServiceError
from config import settings

from transaction_routes import router as transaction_router
from goal_routes import router as goal_router
from auth_routes import router as auth_router
from budget_routes import router as budget_router
from report_routes import router as report_router
from admin_routes import router as admin_router
from feedback_routes import router as feedback_router

# NEW: App version routers
from app_version_routes import admin_router as app_version_admin_router
from app_version_routes import user_router as app_version_user_router

# AI provider switching: admin API and the settings cache it feeds
from ai_admin_routes import router as ai_admin_router
from ai_providers import settings as ai_provider_settings
from ai_providers.errors import redact

# Plans and AI quotas: admin API and the limits cache it feeds
from plans_admin_routes import router as plans_admin_router
from plans_routes import plan_error_handler, router as plans_router
from plans import periods, quota
from plans import store as plan_store
from plans.access import COST_CAP, LIMIT_REACHED, PlanError, effective_plan
from tz_utils import as_utc

# SafeJSONResponse: a stray NaN/inf in a response body is sanitised instead of a 500.
app = FastAPI(title="Toe Pwar API", version="1.0.0", default_response_class=SafeJSONResponse)

app.include_router(transaction_router)
app.include_router(auth_router)
app.include_router(goal_router)
app.include_router(budget_router)
app.include_router(report_router)
app.include_router(admin_router)
app.include_router(feedback_router)

# NEW: Register app version routes
app.include_router(app_version_admin_router)
app.include_router(app_version_user_router)
app.include_router(ai_admin_router)
app.include_router(plans_admin_router)
app.include_router(plans_router)


@app.on_event("startup")
async def startup_db_client():
    await initialize_categories()
    await initialize_admin()

    # Admin-panel AI settings: load once, then refresh every minute. A database blip must not stop the API
    # from booting; until a load succeeds the server's environment / built-in settings apply (the refresh retries).
    try:
        await ai_provider_settings.load_panel()
    except Exception as e:
        print(f"⚠️ Could not load the AI provider settings at startup ({type(e).__name__}); will retry")
    app.state.ai_settings_refresh = ai_provider_settings.start_refresh_loop()

    # Plan limits, cost caps and upgrade contact: same pattern. Until a load succeeds the catalogue defaults apply.
    try:
        await plan_store.load()
    except Exception as e:
        print(f"⚠️ Could not load the plan limits at startup ({type(e).__name__}); will retry")
    app.state.plans_refresh = plan_store.start_refresh_loop()

    try:
        from scheduler import start_scheduler
        app.state.scheduler = start_scheduler()
        print("✅ Notification scheduler started successfully (Async Mode)")
    except Exception as e:
        print(f"⚠️ Failed to start notification scheduler: {e}")


@app.on_event("shutdown")
async def shutdown_db_client():
    if hasattr(app.state, "ai_settings_refresh"):
        app.state.ai_settings_refresh.cancel()
    if hasattr(app.state, "plans_refresh"):
        app.state.plans_refresh.cancel()
    if hasattr(app.state, "scheduler"):
        app.state.scheduler.shutdown()
        print("🛑 Scheduler shut down successfully")
    from sql.db import dispose_engine
    await dispose_engine()


try:
    initialize_firebase()
except Exception as e:
    print(f"⚠️  Failed to initialize Firebase: {e}")

app.add_middleware(
    CORSMiddleware,
    # See CORS_ALLOWED_ORIGINS in config.py (default "*"). Auth uses the Authorization
    # header, not cookies, so credentials are never needed cross-origin; with
    # allow_credentials=False a wildcard is sent as a literal "*" instead of reflecting
    # the caller's origin with Access-Control-Allow-Credentials: true.
    allow_origins=settings.CORS_ALLOWED_ORIGINS,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
    # Lets the web app read the PDF filename from a cross-origin download response.
    expose_headers=["Content-Disposition"],
)


class RejectNulCharacters:
    """
    400 for a request whose path or query contains a NUL character (%00). PostgreSQL text
    can't hold NUL, and many routes turn any exception into a 500, so this is rejected up
    front instead of reaching the database (see database_input_error_handler for bodies).
    """

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] == "http" and ("\x00" in scope.get("path", "") or b"%00" in scope.get("query_string", b"")):
            response = JSONResponse(status_code=status.HTTP_400_BAD_REQUEST,
                                    content={"detail": "The request contains a value that isn't allowed."})
            await response(scope, receive, send)
            return
        await self.app(scope, receive, send)


app.add_middleware(RejectNulCharacters)


# ==================== ERROR HANDLERS ====================

@app.exception_handler(RequestValidationError)
async def request_validation_exception_handler(request: Request, exc: RequestValidationError):
    """
    Same 422 body as FastAPI's default handler ({"detail": [errors...]}), but JSON-safe.

    The default handler echoes each error's "input": a body containing the JSON literals
    NaN / Infinity (which Python's json parser accepts) made that echo unencodable
    (JSONResponse uses allow_nan=False), turning the 422 into a 500. Non-finite floats
    are rendered as the strings "NaN" / "Infinity" / "-Infinity" and any other
    non-serialisable value is stringified.
    """
    errors = exc.errors()
    try:
        detail = json_safe(jsonable_encoder(errors))
    except Exception:
        detail = json_safe(errors)
    return JSONResponse(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, content={"detail": detail})


def _pg_sqlstate(exc: BaseException) -> Optional[str]:
    """SQLSTATE of a PostgreSQL error, looking through SQLAlchemy's wrapper and causes."""
    seen = set()
    while exc is not None and id(exc) not in seen:
        seen.add(id(exc))
        for attr in ("sqlstate", "pgcode"):
            code = getattr(exc, attr, None)
            if isinstance(code, str) and len(code) == 5:
                return code
        exc = getattr(exc, "orig", None) or exc.__cause__ or exc.__context__
    return None


# A plan check refused the request (feature locked, allowance used up, cost cap): 403 / 429 with a stable code.
app.add_exception_handler(PlanError, plan_error_handler)


@app.exception_handler(DBAPIError)
async def database_input_error_handler(request: Request, exc: DBAPIError):
    """
    A value the database refuses to store is a bad request, not a server error:
    SQLSTATE class 22 (data exception, e.g. a NUL character in a path or text field, a
    number too large for its column) and 23514 (a CHECK constraint, e.g. a non-positive
    amount that slipped past validation) -> 400. Everything else stays a 500.
    """
    code = _pg_sqlstate(exc)
    if code and (code.startswith("22") or code == "23514"):
        return JSONResponse(status_code=status.HTTP_400_BAD_REQUEST,
                            content={"detail": "The request contains a value that isn't allowed."})
    print(f"❌ Database error on {request.method} {request.url.path}: {type(exc).__name__} (SQLSTATE {code})")
    return JSONResponse(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, content={"detail": "Internal Server Error"})


# ==================== CATEGORIES & DASHBOARD ====================

@app.get("/api/categories/{transaction_type}", response_model=List[CategoryResponse])
async def get_categories(transaction_type: TransactionType):
    """Get categories for transaction type"""
    categories_doc = await get_categories_doc(transaction_type.value)
    if not categories_doc:
        return []

    return [
        CategoryResponse(
            main_category=cat["main_category"],
            sub_categories=cat["sub_categories"]
        )
        for cat in categories_doc["categories"]
    ]


@app.get("/api/dashboard/balance")
async def get_balance(
    currency: Optional[Currency] = None,
    current_user: dict = Depends(get_current_user)
):
    """
    Get user's financial balance including goal allocations.
    If currency is specified, returns balance for that currency only.
    Otherwise returns balances for all currencies.
    """
    return await get_user_balance(current_user["_id"], currency.value if currency else None)


# ==================== AI CHATBOT ====================

async def save_chat_session(user_id: str, user_message: str, ai_response: str):
    """
    Append one user/assistant exchange to the server-stored chat history.

    The server copy is the source of truth: client-supplied history is never written
    back (it may be stale, truncated or edited), only the new exchange is appended and
    the stored list is trimmed to MAX_CHAT_HISTORY.
    """
    try:
        current_time = datetime.now(UTC)
        new_messages = [
            {"role": "user", "content": user_message, "timestamp": current_time},
            {"role": "assistant", "content": ai_response, "timestamp": current_time},
        ]

        await chat_db.append_exchange(user_id, new_messages, settings.MAX_CHAT_HISTORY, current_time)
    except Exception as e:
        print(f"Error saving chat session: {e}")


def _invalidate_ai_caches(user_id: str) -> None:
    """Drop the chatbot's cached vector store for the user (it rebuilds lazily)."""
    if financial_chatbot is None:
        return
    try:
        financial_chatbot.refresh_user_data(user_id)
    except Exception as e:
        print(f"⚠️ Failed to invalidate AI cache for user {user_id}: {e}")


def _sse(payload: dict) -> str:
    return f"data: {json.dumps(payload)}\n\n"


async def _reserve_chat(user: dict, mode: str):
    """Reserve one chat use -> (reservation, mode_used, advanced_exhausted). Raises PlanError (chat locked, used up,
    or the cost cap reached), which the app-level handler turns into a 403 / 429.

    Advanced is answered only for a Pro user with Advanced allowance left; it reserves chat and chat_advanced together.
    When Advanced is used up the message is answered as Standard and flagged advanced_exhausted. Anyone else asking
    for Advanced (Free, Plus, or a Pro plan whose Advanced the owner locked) is simply answered as Standard.
    """
    advanced_exhausted = False
    if mode == "advanced" and effective_plan(user) == "pro":
        try:
            return await quota.reserve(user, "chat", also=("chat_advanced",)), "advanced", False
        except PlanError as e:
            if e.feature != "chat_advanced":
                raise  # chat itself is locked or used up, or the cost cap: Standard would be refused too
            advanced_exhausted = e.code == LIMIT_REACHED
    return await quota.reserve(user, "chat"), "standard", advanced_exhausted


async def _give_back(reservation: "quota.Reservation") -> None:
    """Release a chat use that was not kept (a no-op once committed or released). Never raises: a failed release is
    logged, so it can't break the stream or hide the original error."""
    try:
        await reservation.release()
    except Exception as e:  # noqa: BLE001
        print(f"❌ Could not give back a chat use for user {reservation.user_id}: {type(e).__name__}: {redact(str(e))}")


@app.post("/api/chat/stream")
async def stream_chat_with_ai(
    chat_request: ChatRequest,
    current_user: dict = Depends(get_current_user)
):
    """
    Stream chat response from AI (Server-Sent Events, media type text/event-stream).

    Frames (each `data: <json>\\n\\n`):
      - meta (always first, once): {"chunk": "", "done": false, "mode_used": "standard"|"advanced",
                                    "advanced_exhausted": bool, "timestamp": ...}
      - chunk: {"chunk": "...", "done": false, "timestamp": ...}
      - final: {"chunk": "", "done": true, "full_response": "...", "timestamp": ...}
      - error: {"error": "<user-friendly message>", "done": true, "timestamp": ...}
    On error the exchange is NOT saved to chat history.

    Each message uses one chat (and, answered as Advanced, one chat_advanced) allowance. It is reserved before the
    stream starts, so a refusal is a normal 403 / 429 with the plan-error body. The use is kept when the answer
    completes, or when the client disconnects after the first chunk of the answer was sent. It is given back when the
    AI fails (before or after the first chunk: the error frame) or the client leaves before the first chunk.

    The answer comes from the "chat" feature's provider chain, or "chat_advanced" for an Advanced answer (admin
    panel / server settings); the runner records the usage. `ai_provider` in the body (sent by old apps) is
    validated and ignored.
    """
    user_id = current_user["_id"]

    # Clearing the ai_data_stale flag with a conditional update first means a data
    # change that lands after this point re-sets the flag and is picked up next time.
    try:
        if await users_db.claim_ai_data_fresh(user_id):
            _invalidate_ai_caches(user_id)
            print(f"🔄 AI data was stale for user {user_id}; invalidated cached vector stores")
    except Exception as e:
        print(f"⚠️ Failed to refresh stale AI data: {e}")

    chat_history = None
    if chat_request.chat_history:
        # Used only as prompt context; never persisted.
        chat_history = [{"role": msg.role.value, "content": msg.content, "timestamp": msg.timestamp} for msg in chat_request.chat_history]

    response_style = chat_request.response_style.value if chat_request.response_style else "normal"

    # Last step before the response: nothing may raise between the reservation and handing it to the stream.
    reservation, mode_used, advanced_exhausted = await _reserve_chat(current_user, chat_request.mode)
    feature = "chat_advanced" if mode_used == "advanced" else "chat"

    # What the stream got to: whether a chunk of the answer reached the client, and whether the AI failed.
    progress = {"first_sent": False, "failed": False}

    async def settle():
        """Keep or give back the use, once (later calls do nothing): a failed AI request never counts; an answer that
        reached the client counts, even if the client then left; a stream that ended before any answer gives it back."""
        if reservation.committed or reservation.released:
            return
        if progress["first_sent"] and not progress["failed"]:
            reservation.commit()
        else:
            await _give_back(reservation)

    async def generate_stream():
        full_response = ""
        error_message = None

        try:
            yield _sse({"chunk": "", "done": False, "mode_used": mode_used, "advanced_exhausted": advanced_exhausted,
                        "timestamp": datetime.now(UTC).isoformat()})
            try:
                # aclosing: a client disconnect closes the chatbot's stream, and through it the provider's.
                async with aclosing(financial_chatbot.stream_chat(
                    user_id=user_id,
                    message=chat_request.message,
                    chat_history=chat_history,
                    response_style=response_style,
                    feature=feature,
                )) as stream:
                    async for chunk_text, _usage in stream:  # usage is already tracked by the provider runner
                        if chunk_text:
                            full_response += chunk_text
                            yield _sse({"chunk": chunk_text, "done": False, "timestamp": datetime.now(UTC).isoformat()})
                            progress["first_sent"] = True  # resumed only once that chunk was sent
                            await asyncio.sleep(0.01)
            except ChatServiceError as e:
                error_message = e.user_message
            except Exception as e:
                print(f"❌ Chat stream error for user {user_id}: {type(e).__name__}: {redact(str(e))}")
                error_message = ChatServiceError.DEFAULT_MESSAGE

            if error_message:
                # A failed AI request, before or after the first chunk: nothing saved, the use given back.
                progress["failed"] = True
                await settle()
                yield _sse({"error": error_message, "done": True, "timestamp": datetime.now(UTC).isoformat()})
                return

            if full_response:
                # Saved BEFORE the "done" frame: the client may disconnect as soon as it
                # sees done:true, which would cancel anything after the yield.
                await save_chat_session(user_id, chat_request.message, full_response)

            await settle()  # the answer completed: the use is kept
            yield _sse({"chunk": "", "done": True, "full_response": full_response, "timestamp": datetime.now(UTC).isoformat()})
        finally:
            # Closed or cancelled early (the client left): kept if an answer chunk had reached the client, otherwise
            # given back. Shielded so a cancelled request still completes a release.
            if not (reservation.committed or reservation.released):
                await asyncio.shield(settle())

    async def settle_unstarted():
        # Also run after the response ends: a client gone before the stream started never runs generate_stream's
        # finally. A no-op once the stream settled the use itself.
        # Relies on ASGI spec 2.3 disconnect handling (uvicorn 0.54 reports 2.3): Starlette then listens for the
        # disconnect, cancels the stream and still runs this background task. On a server reporting spec >= 2.4
        # Starlette neither listens for disconnects nor runs `background` after a ClientDisconnect, so a stream whose
        # client left before any chunk would run to completion and commit its use. Revisit this when the server or
        # Starlette changes (re-run the e2e disconnect-before-first-chunk check).
        await settle()

    return StreamingResponse(
        generate_stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "Connection": "keep-alive", "X-Accel-Buffering": "no"},
        background=BackgroundTask(settle_unstarted),
    )


@app.post("/api/chat", response_model=ChatResponse)
async def chat_with_ai(
    chat_request: ChatRequest,
    current_user: dict = Depends(get_current_user)
):
    """Chat with AI about financial data (deprecated - use /stream). Makes no AI call, so it uses no allowance."""
    raise HTTPException(
        status_code=status.HTTP_410_GONE,
        detail="This endpoint is deprecated. Please use /api/chat/stream instead."
    )


@app.get("/api/chat/history", response_model=List[ChatMessage])
async def get_chat_history(
    current_user: dict = Depends(get_current_user),
    limit: int = Query(default=20, ge=1, le=50)
):
    """Get user's chat history"""
    try:
        messages = await chat_db.history(current_user["_id"], limit)

        return [
            ChatMessage(
                role=MessageRole(msg["role"]),
                content=msg["content"],
                timestamp=msg.get("timestamp")
            )
            for msg in messages
        ]
    except Exception as e:
        print(f"Chat history error: {str(e)}")
        return []


@app.delete("/api/chat/history")
async def clear_chat_history(current_user: dict = Depends(get_current_user)):
    """Clear user's chat history"""
    try:
        deleted = await chat_db.clear(current_user["_id"])
        return {
            "message": f"Cleared {deleted} chat sessions",
            "deleted_count": deleted
        }
    except Exception as e:
        print(f"Clear chat history error: {str(e)}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="An error occurred while clearing chat history")


@app.post("/api/chat/refresh-data")
async def refresh_ai_data(
    ai_provider: AIProvider = Query(default=AIProvider.OPENAI),
    current_user: dict = Depends(get_current_user)
):
    """Manually refresh user's AI data. `ai_provider` (sent by old apps) is validated and ignored: one chatbot."""
    try:
        if financial_chatbot:
            financial_chatbot.refresh_user_data(current_user["_id"])
        return {"message": "AI data refreshed successfully"}
    except Exception as e:
        print(f"Refresh AI data error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An error occurred while refreshing AI data"
        )


# ==================== AI INSIGHTS ====================


async def _generate_insight(user_id: str, insight_type: str):
    """One insight on the insight_weekly / insight_monthly provider chain (the admin AI settings decide)."""
    from insights_service import generate_weekly_insight, generate_monthly_insight

    if insight_type == "monthly":
        return await generate_monthly_insight(user_id)
    return await generate_weekly_insight(user_id)


def _is_new_real_insight(insight: Optional[dict]) -> bool:
    """A freshly generated, non-placeholder insight: the only result that uses an allowance. A welcome
    placeholder, an older insight returned for a quiet period (is_reused) and an empty result do not."""
    return (_insight_has_content(insight) and not insight.get("is_placeholder")
            and not insight.get("is_reused"))


async def _generate_counted(user: dict, insight_type: str):
    """One on-demand insight, reserved on the plan first (a locked insight type, the hidden cost cap or a used-up
    allowance raise PlanError, which no handler may swallow) and counted only when the result is a new real insight.

    An included insight reserves nothing but is still refused at the cost cap. A placeholder, an older insight
    reused for a quiet period, an empty result or any failure gives the reservation back.
    """
    reservation = await quota.reserve(user, f"insight_{insight_type}")
    try:
        insight = await _generate_insight(user["_id"], insight_type)
    except BaseException:
        await quota.give_back(reservation)
        raise
    if _is_new_real_insight(insight):
        reservation.commit()
    else:
        await quota.give_back(reservation)
    return insight


def _translation_locked(user: dict) -> bool:
    """True when the user's plan does not include insight translation: Free never gets one (whatever the owner sets for
    it), and any plan whose insight_translation limit the owner locked."""
    plan = effective_plan(user)
    return plan == "free" or plan_store.limits(plan)["insight_translation"].mode == "locked"


def _needs_translation_call(insight: dict) -> bool:
    """True when showing the insight in Myanmar needs an AI call: no stored translation and not a welcome placeholder."""
    from insights_service import _is_placeholder_text

    if insight.get("content_mm"):
        return False
    flag = insight.get("is_placeholder")
    return not (flag or (flag is None and _is_placeholder_text(insight["content"])))


async def _ensure_myanmar_translation(insight: dict, user: dict) -> dict:
    """Translate (and cache) content_mm if missing. Placeholders never hit the paid API and a stored translation costs
    nothing; only a real translation call is reserved on the user's plan (the cost cap applies) and counted."""
    if not _needs_translation_call(insight):
        if insight.get("content_mm"):
            return insight
        # A welcome placeholder: the canned translation, no AI call and nothing to reserve.
        reservation = None
    else:
        reservation = await quota.reserve(user, "insight_translation")  # PlanError: locked, cost cap, used up

    from insights_service import translate_insight_to_myanmar

    try:
        myanmar_content = await translate_insight_to_myanmar(
            insight["content"],
            user_id=user["_id"],
            # None (legacy docs without the flag) falls back to text detection
            is_placeholder=insight.get("is_placeholder"),
        )
        await insights_db.set_translation(insight["_id"], myanmar_content)
    except BaseException:
        if reservation:
            await quota.give_back(reservation)
        raise
    if reservation:
        reservation.commit()
    insight["content_mm"] = myanmar_content
    return insight


async def _translate_if_possible(insight: dict, user: dict):
    """Myanmar for a Plus/Pro user: (insight, None) when translated or already stored. A plan refusal of the translation
    itself (the hidden cost cap, a used-up counted allowance) must not hide the English insight, which exists and costs
    nothing to show: it returns (insight, the limit error's detail) and the insight keeps its content_mm empty."""
    try:
        return await _ensure_myanmar_translation(insight, user), None
    except PlanError as e:
        return insight, e.detail()


def _insight_http_error(e: Exception, action: str) -> HTTPException:
    """
    Map an insight generation/translation failure to a client-safe HTTP error (never the
    raw exception text): provider rate limit / quota (openai.RateLimitError, Gemini 429
    RESOURCE_EXHAUSTED) -> 429 with Retry-After; other AI provider failures (including
    out-of-credit / billing refusals) -> 503; anything else -> 500.
    """
    from insights_service import InsightAIError, is_billing_error, is_rate_limit_error

    if is_billing_error(e):
        # Not transient and not the user's fault: make it obvious in the server logs.
        print(f"❌ AI provider refused for billing / out of credit while trying to {action}: {type(e).__name__}")
        return HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"The AI service is temporarily unavailable, so we couldn't {action}. Please try again later.",
        )
    if is_rate_limit_error(e):
        return HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="The AI service is busy right now (rate limit reached). Please try again in a few minutes.",
            headers={"Retry-After": "60"},
        )
    if isinstance(e, InsightAIError):
        return HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"The AI service is temporarily unavailable, so we couldn't {action}. Please try again later.",
        )
    return HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail=f"Failed to {action}. Please try again later.",
    )


def _insight_has_content(insight: Optional[dict]) -> bool:
    content = (insight or {}).get("content")
    return isinstance(content, str) and bool(content.strip())


def _insight_response(insight: dict, translation_locked: bool = False, plan_translates: bool = True,
                      translation_unavailable: Optional[dict] = None) -> InsightResponse:
    """translation_locked: Myanmar was requested but the plan has no translation (reported to the app).
    translation_unavailable: Myanmar was requested, the plan has translation, but the translation was refused (cost cap,
    used-up allowance): the limit error's detail, else None. The English insight is still returned.
    plan_translates False: the plan has no translation at all, so a Myanmar text stored earlier (for example while the
    user was on Plus) is not handed out."""
    if not _insight_has_content(insight):
        # Never build a response from a legacy/empty document (content=None -> 500).
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Couldn't load your insight right now. Please try again later.",
        )
    return InsightResponse(
        id=insight["_id"],
        user_id=insight["user_id"],
        content=insight["content"],
        content_mm=insight.get("content_mm") if plan_translates else None,
        generated_at=insight["generated_at"],
        expires_at=insight.get("expires_at"),
        translation_locked=translation_locked,
        translation_unavailable=translation_unavailable,
    )


async def _free_monthly_insight(user: dict, latest: Optional[dict]) -> dict:
    """The monthly insight a Free user sees: generated on demand, once per calendar month (app timezone).

    - A real (non-placeholder) monthly insight generated this month, by this on-demand call or by the scheduler while
      the user was on a paid plan, is shown and nothing is counted.
    - Otherwise one insight is generated, covering the same period the scheduled monthly job would cover if it ran now
      (generate_monthly_insight is the job's own function). A real insight counts as the month's use; a welcome
      placeholder (no data yet) and an older insight reused for a quiet month do not.
    - A stored placeholder with still no data is not regenerated: the latest older real insight is shown if there is one.
    - If generation fails, the latest older insight is shown and nothing is counted; with nothing stored the error
      is surfaced, as for Plus and Pro.
    - If the month's use is gone or the hidden cost cap is reached, the latest older real insight is shown (200, nothing
      counted); with none stored the 429 PlanError is raised. An owner-locked insight is still a 403.
    `latest` is the newest stored insight.
    """
    from insights_service import _latest_real_insight, user_has_insight_data

    user_id = user["_id"]
    real = await _latest_real_insight(user_id, "monthly")
    this_month = periods.period_start("month", datetime.now(UTC))
    if real and real.get("generated_at") and periods.period_start("month", as_utc(real["generated_at"])) == this_month:
        return real
    if latest and latest.get("is_placeholder") and not await user_has_insight_data(user_id, "monthly"):
        return real or latest

    error: Optional[Exception] = None
    generated = None
    try:
        generated = await _generate_counted(user, "monthly")
    except PlanError as e:
        # Blocked from generating this month's insight (the month's use is gone, the hidden cost cap): an older real
        # insight costs nothing to show, so it is returned instead of the 429. With none stored the refusal stands.
        # A locked insight (the owner locked it for Free) stays a 403.
        if e.code in (LIMIT_REACHED, COST_CAP) and real:
            return real
        raise
    except Exception as e:  # AI down, rate limited, unusable answer: fall back to what is stored
        error = e
        print(f"⚠️ Generating the monthly insight for user {user_id} failed "
              f"({type(e).__name__}: {redact(str(e))}); falling back to the stored insight")
    if _insight_has_content(generated):
        return generated
    fallback = real or latest
    if _insight_has_content(fallback):
        return fallback
    # Nothing stored to show: surface the failure (429 / 503 / 500) as for any first generation.
    if error is not None:
        raise error
    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail="Couldn't generate your monthly insight right now. Please try again later.",
    )


@app.get("/api/insights", response_model=InsightResponse)
async def get_insights(
    language: Optional[str] = Query(default="en", pattern="^(en|mm)$"),
    ai_provider: AIProvider = Query(default=AIProvider.OPENAI),
    insight_type: Optional[str] = Query(default="weekly", pattern="^(weekly|monthly)$"),
    current_user: dict = Depends(get_current_user)
):
    """Get latest AI-generated financial insights.

    `ai_provider` (sent by old apps) is validated and ignored: the newest insight of any provider is shown.

    By plan: weekly insights are locked for Free (403). A Free user's monthly insight is generated on demand, once a
    month (see _free_monthly_insight). `language` is the display language asked for by this request (not the profile's):
    Myanmar is translated once and stored for Plus and Pro; Free is never translated and gets English with
    translation_locked true.
    """
    user_id = current_user["_id"]
    if insight_type == "weekly":
        quota.require_unlocked(current_user, "insight_weekly")  # outside the handlers below: a PlanError passes through
    plan_translates = not _translation_locked(current_user)
    translation_locked = language == "mm" and not plan_translates
    try:
        from insights_service import latest_valid_insight, user_has_insight_data, _latest_real_insight

        # Legacy insights with content None / "" are treated as missing (skipped here).
        latest_insight = await latest_valid_insight(user_id, insight_type)

        if effective_plan(current_user) == "free" and insight_type == "monthly":
            # Free is never translated: English only, whatever language was asked for (no translation call).
            latest_insight = await _free_monthly_insight(current_user, latest_insight)
            return _insight_response(latest_insight, translation_locked, plan_translates=False)

        # A stored "welcome" placeholder is replaced once the user has real data (incl.
        # transactions in the current, incomplete period). If they don't, but they have
        # older REAL insights (e.g. a legacy placeholder stored over them after a quiet
        # week), the latest real insight is shown instead of the welcome text.
        if latest_insight and latest_insight.get("is_placeholder"):
            try:
                if await user_has_insight_data(user_id, insight_type):
                    print(f"🔄 Replacing placeholder {insight_type} insight for user {user_id} (user now has data)")
                    regenerated = None
                    try:
                        regenerated = await _generate_counted(current_user, insight_type)
                    except Exception as gen_error:
                        # AI down / rate limited / the cost cap reached (a PlanError): something stored is still
                        # worth showing, and nothing was generated.
                        print(f"⚠️ Regenerating {insight_type} insight for user {user_id} failed "
                              f"({type(gen_error).__name__}: {gen_error}); falling back to the stored insight")
                    if _insight_has_content(regenerated):
                        latest_insight = regenerated
                    else:
                        latest_real = await _latest_real_insight(user_id, insight_type)
                        if latest_real:
                            latest_insight = latest_real
                        # else: keep showing the stored placeholder
                else:
                    latest_real = await _latest_real_insight(user_id, insight_type)
                    if latest_real:
                        latest_insight = latest_real
            except Exception as refresh_error:
                print(f"⚠️ Placeholder refresh failed for user {user_id} "
                      f"({type(refresh_error).__name__}: {refresh_error}); showing the stored placeholder")

        if not latest_insight:
            # Nothing stored at all: generation errors are surfaced (429/503/500).
            print(f"🔄 No {insight_type} insight found, generating the first one for user {user_id}")
            latest_insight = await _generate_counted(current_user, insight_type)
            if not _insight_has_content(latest_insight):
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail=f"Couldn't generate your {insight_type} insight right now. Please try again later.",
                )

        translation_unavailable = None
        if language == "mm" and plan_translates:
            latest_insight, translation_unavailable = await _translate_if_possible(latest_insight, current_user)

        return _insight_response(latest_insight, translation_locked, plan_translates, translation_unavailable)

    except (HTTPException, PlanError):
        raise
    except Exception as e:
        print(f"❌ Error getting insights: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        raise _insight_http_error(e, "get your insights")

@app.delete("/api/insights")
async def delete_insights(
    ai_provider: Optional[AIProvider] = Query(default=None),
    insight_type: Optional[str] = Query(default=None, pattern="^(weekly|monthly)$"),
    current_user: dict = Depends(get_current_user)
):
    """Delete cached insights.

    `ai_provider` (sent by old apps) is validated and ignored: reads show the newest insight of any
    provider, so clearing only one provider's rows would leave another provider's insight on screen.
    """
    try:
        deleted = await insights_db.delete_for_user(current_user["_id"], None, insight_type)

        type_msg = f" {insight_type}" if insight_type else ""
        return {"message": f"Deleted {deleted}{type_msg} insights", "deleted_count": deleted}
    except Exception as e:
        print(f"Error deleting insights: {str(e)}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to delete insights")


@app.post("/api/insights/regenerate", response_model=InsightResponse)
async def regenerate_insights(
    language: Optional[str] = Query(default="en", pattern="^(en|mm)$"),
    ai_provider: AIProvider = Query(default=AIProvider.OPENAI),
    insight_type: Optional[str] = Query(default="weekly", pattern="^(weekly|monthly)$"),
    current_user: dict = Depends(get_current_user)
):
    """Force regenerate insights (admin/testing purpose). `ai_provider` (sent by old apps) is validated and ignored.

    Locked for Free (403, whatever the type): regenerating is a paid-plan action. Plus and Pro are refused at the hidden
    cost cap. `language` is the display language of this request (see GET /api/insights).
    """
    # Outside the handlers below: a PlanError passes through
    ensure_paid(current_user)  # feature None: the refusal reads "only on Plus and Pro" (Free does include a monthly insight)
    plan_translates = not _translation_locked(current_user)
    translation_locked = language == "mm" and not plan_translates
    try:
        print(f"🔄 Force regenerating {insight_type} insights for user {current_user['_id']}")

        new_insight = await _generate_counted(current_user, insight_type)

        if not _insight_has_content(new_insight):
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f"Couldn't regenerate your {insight_type} insight right now. Please try again later.",
            )

        translation_unavailable = None
        if language == "mm" and plan_translates:
            new_insight, translation_unavailable = await _translate_if_possible(new_insight, current_user)

        print(f"✅ {insight_type.title()} insights regenerated successfully ({new_insight.get('ai_provider')})")
        return _insight_response(new_insight, translation_locked, plan_translates, translation_unavailable)
    except (HTTPException, PlanError):
        raise
    except Exception as e:
        print(f"❌ Error regenerating insights: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        raise _insight_http_error(e, "regenerate your insights")


@app.post("/api/insights/translate-myanmar")
async def translate_insights_to_myanmar(
    ai_provider: AIProvider = Query(default=AIProvider.OPENAI),
    insight_type: Optional[str] = Query(default="weekly", pattern="^(weekly|monthly)$"),
    current_user: dict = Depends(get_current_user)
):
    """Translate the latest weekly or monthly insight to Myanmar.

    `ai_provider` (sent by old apps) is validated and ignored: the newest insight of any provider is
    translated on the insight_translation provider chain. Locked for Free (403); Plus and Pro are refused at
    the hidden cost cap when a translation call is needed.
    """
    # Outside the handlers below: a PlanError passes through
    ensure_paid(current_user, "insight_translation")
    quota.require_unlocked(current_user, "insight_translation")
    try:
        from insights_service import latest_valid_insight

        # Legacy insights without content can't be translated: skipped.
        insight = await latest_valid_insight(current_user["_id"], insight_type)

        if not insight:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"No {insight_type} insights found to translate")

        if insight.get("content_mm"):
            return {"message": "Myanmar translation already exists", "already_translated": True}

        print(f"🔄 Translating {insight_type} insights to Myanmar for user {current_user['_id']}")
        await _ensure_myanmar_translation(insight, current_user)

        return {"message": "Translation completed successfully", "already_translated": False}

    except (HTTPException, PlanError):
        raise
    except Exception as e:
        print(f"❌ Translation error: {type(e).__name__}: {e}")
        raise _insight_http_error(e, "translate your insights")




@app.post("/api/insights/generate-weekly")
async def manually_generate_weekly_insights(
    current_user: dict = Depends(get_current_user)
):
    """Manually trigger weekly insights generation for current user (once, on the insight_weekly chain).

    Locked for Free (403); Plus and Pro are refused at the hidden cost cap."""
    # Outside the handlers below: a PlanError passes through
    ensure_paid(current_user, "insight_weekly")
    try:
        from insights_service import is_rate_limit_error

        # Same shape as before ({provider: outcome}), keyed by the provider that answered, or by the
        # feature's main provider when nothing was generated.
        provider = ai_provider_settings.resolve("insight_weekly").main.provider
        try:
            insight = await _generate_counted(current_user, "weekly")
            outcome = "success" if insight else "failed"
            provider = (insight or {}).get("ai_provider") or provider
        except PlanError:
            raise
        except Exception as e:
            print(f"❌ Manual weekly insight failed: {type(e).__name__}: {redact(str(e))}")
            # No raw exception text in the response.
            outcome = "rate_limited" if is_rate_limit_error(e) else "error"
        results = {provider: outcome}

        return {
            "message": "Weekly insights generation completed",
            "results": results
        }

    except PlanError:
        raise
    except Exception as e:
        print(f"Error in manual weekly generation: {redact(str(e))}")
        raise _insight_http_error(e, "generate weekly insights")



# ==================== NOTIFICATIONS ====================


@app.post("/api/auth/update-fcm-token")
async def update_fcm_token(
    payload: FcmTokenUpdate,
    current_user: dict = Depends(get_current_user)
):
    """Register the device's FCM token for the current user (body: {"fcm_token": "..."})"""
    try:
        token = payload.fcm_token
        user_id = current_user["_id"]

        # A device token belongs to exactly one account: detach it from any other user
        # first so a shared device never receives another account's pushes.
        released = await users_db.set_device_token(user_id, token)
        if released:
            print(f"🔁 FCM token detached from {released} other user(s)")
        return {"message": "FCM token updated successfully"}
    except Exception as e:
        print(f"Error updating FCM token: {str(e)}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to update FCM token")


@app.delete("/api/auth/fcm-token")
async def delete_fcm_token(current_user: dict = Depends(get_current_user)):
    """Unregister the current user's FCM token (call on logout)"""
    try:
        await users_db.clear_device_token(current_user["_id"])
        return {"message": "FCM token removed successfully"}
    except Exception as e:
        print(f"Error removing FCM token: {str(e)}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to remove FCM token")


@app.get("/api/notifications/preferences", response_model=NotificationPreferencesResponse)
async def get_notification_preferences(current_user: dict = Depends(get_current_user)):
    """Get user's notification preferences"""
    try:
        prefs_doc = await prefs_db.get_or_create(
            current_user["_id"], NotificationPreferences().dict(), datetime.now(UTC)
        )

        return NotificationPreferencesResponse(
            user_id=prefs_doc["user_id"],
            preferences=NotificationPreferences(**prefs_doc["preferences"]),
            updated_at=prefs_doc["updated_at"]
        )
    except Exception as e:
        print(f"Error getting notification preferences: {str(e)}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to get notification preferences")


@app.put("/api/notifications/preferences", response_model=NotificationPreferencesResponse)
async def update_notification_preferences(
    update_data: NotificationPreferencesUpdate,
    current_user: dict = Depends(get_current_user)
):
    """Update user's notification preferences"""
    try:
        # One atomic upsert: the changes are merged into the stored map in the database,
        # so two quick toggles can't overwrite each other.
        updated_doc = await prefs_db.merge(
            current_user["_id"], NotificationPreferences().dict(), dict(update_data.preferences), datetime.now(UTC)
        )

        return NotificationPreferencesResponse(
            user_id=updated_doc["user_id"],
            preferences=NotificationPreferences(**updated_doc["preferences"]),
            updated_at=updated_doc["updated_at"]
        )
    except Exception as e:
        print(f"Error updating notification preferences: {str(e)}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to update notification preferences")


@app.post("/api/notifications/preferences/reset")
async def reset_notification_preferences(current_user: dict = Depends(get_current_user)):
    """Reset notification preferences to default (all enabled)"""
    try:
        now = datetime.now(UTC)
        default_prefs = NotificationPreferences()

        await prefs_db.reset(current_user["_id"], default_prefs.dict(), now)

        return {"message": "Notification preferences reset to default", "preferences": default_prefs.dict()}
    except Exception as e:
        print(f"Error resetting notification preferences: {str(e)}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to reset notification preferences")

@app.get("/api/notifications", response_model=List[NotificationResponse])
async def get_notifications(
    current_user: dict = Depends(get_current_user),
    limit: int = Query(default=50, ge=1, le=100),
    unread_only: bool = Query(default=False)
):
    """Get user notifications"""
    try:
        notifications = await notifications_db.list_for_user(current_user["_id"], unread_only, limit)

        results = []
        for n in notifications:
            try:
                results.append(NotificationResponse(
                    id=n["_id"],
                    user_id=n["user_id"],
                    # Unknown/legacy types are mapped to a generic system type instead of 500ing
                    type=parse_notification_type(n.get("type")),
                    title=n.get("title") or "",
                    message=n.get("message") or "",
                    goal_id=n.get("goal_id"),
                    goal_name=n.get("goal_name"),
                    currency=n.get("currency"),
                    created_at=n["created_at"],
                    is_read=bool(n.get("is_read", False))
                ))
            except Exception as item_error:
                # One malformed document must not break the whole list
                print(f"⚠️ Skipping malformed notification {n.get('_id')}: {item_error}")
        return results
    except Exception as e:
        print(f"Error fetching notifications: {str(e)}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to fetch notifications")


@app.post("/api/notifications/{notification_id}/mark-read")
async def mark_notification_read(
    notification_id: str = Path(...),
    current_user: dict = Depends(get_current_user)
):
    """Mark a notification as read (idempotent: already-read returns 200)"""
    try:
        if await notifications_db.mark_read(current_user["_id"], notification_id) == 0:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Notification not found")

        return {"message": "Notification marked as read"}
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error marking notification read: {str(e)}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to mark notification as read")


@app.post("/api/notifications/mark-all-read")
async def mark_all_notifications_read(current_user: dict = Depends(get_current_user)):
    """Mark all notifications as read"""
    try:
        count = await notifications_db.mark_all_read(current_user["_id"])

        return {"message": f"Marked {count} notifications as read", "count": count}
    except Exception as e:
        print(f"Error marking all notifications read: {str(e)}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to mark notifications as read")


@app.delete("/api/notifications/{notification_id}")
async def delete_notification(
    notification_id: str = Path(...),
    current_user: dict = Depends(get_current_user)
):
    """Delete a notification"""
    try:
        if await notifications_db.delete_notification(current_user["_id"], notification_id) == 0:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Notification not found")

        return {"message": "Notification deleted successfully"}
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error deleting notification: {str(e)}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to delete notification")


@app.get("/api/notifications/unread-count")
async def get_unread_count(current_user: dict = Depends(get_current_user)):
    """Get count of unread notifications"""
    try:
        count = await notifications_db.unread_count(current_user["_id"])

        return {"unread_count": count}
    except Exception as e:
        print(f"Error getting unread count: {str(e)}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to get unread count")


@app.post("/api/notifications/analyze-spending")
async def analyze_spending_patterns(current_user: dict = Depends(get_current_user)):
    """Manually trigger unusual spending analysis"""
    try:
        await analyze_unusual_spending(current_user["_id"])
        return {"message": "Spending analysis completed"}
    except Exception as e:
        print(f"Error analyzing spending: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to analyze spending"
        )



# ==================== ROOT ====================

@app.get("/")
async def root():
    return {"message": "Toe Pwar API with AI Assistant is running"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)