import asyncio
import hashlib
import json
import uuid
from datetime import datetime, timedelta, UTC
from typing import List, Optional

from fastapi import FastAPI, HTTPException, Request, status, Depends, Query, Path
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware

from finite_utils import SafeJSONResponse, json_safe

from firebase_service import initialize_firebase
from utils import get_current_user, get_user_balance, require_premium
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

from database import (
    chat_sessions_collection, create_db_indexes, initialize_admin,
    initialize_categories, insights_collection, notifications_collection,
    notification_preferences_collection, users_collection
)
from sql.categories import get_categories_doc
from ai_chatbot import financial_chatbot, ChatServiceError
from ai_chatbot_gemini import gemini_financial_chatbot
from ai_usage_service import track_ai_usage
from ai_usage_models import AIFeatureType, AIProviderType
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


@app.on_event("startup")
async def startup_db_client():
    await initialize_categories()
    await initialize_admin()
    await create_db_indexes()
    
    try:
        from scheduler import start_scheduler
        app.state.scheduler = start_scheduler()
        print("✅ Notification scheduler started successfully (Async Mode)")
    except Exception as e:
        print(f"⚠️ Failed to start notification scheduler: {e}")


@app.on_event("shutdown")
async def shutdown_db_client():
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
)


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

        existing_session = await chat_sessions_collection.find_one(
            {"user_id": user_id},
            {"_id": 1},
            sort=[("updated_at", -1)]
        )

        if existing_session:
            await chat_sessions_collection.update_one(
                {"_id": existing_session["_id"]},
                {
                    "$push": {"messages": {"$each": new_messages, "$slice": -settings.MAX_CHAT_HISTORY}},
                    "$set": {"updated_at": current_time},
                }
            )
        else:
            await chat_sessions_collection.insert_one({
                "_id": str(uuid.uuid4()),
                "user_id": user_id,
                "messages": new_messages[-settings.MAX_CHAT_HISTORY:],
                "created_at": current_time,
                "updated_at": current_time
            })
    except Exception as e:
        print(f"Error saving chat session: {e}")


def _invalidate_ai_caches(user_id: str) -> None:
    """Drop BOTH providers' cached vector stores for the user (they rebuild lazily)."""
    for bot in (financial_chatbot, gemini_financial_chatbot):
        if bot is None:
            continue
        try:
            bot.refresh_user_data(user_id)
        except Exception as e:
            print(f"⚠️ Failed to invalidate AI cache for user {user_id}: {e}")


def _sse(payload: dict) -> str:
    return f"data: {json.dumps(payload)}\n\n"


@app.post("/api/chat/stream")
async def stream_chat_with_ai(
    chat_request: ChatRequest,
    current_user: dict = Depends(require_premium)
):
    """
    Stream chat response from AI (Server-Sent Events, media type text/event-stream).

    Frames (each `data: <json>\\n\\n`):
      - chunk: {"chunk": "...", "done": false, "timestamp": ...}
      - final: {"chunk": "", "done": true, "full_response": "...", "timestamp": ...}
      - error: {"error": "<user-friendly message>", "done": true, "timestamp": ...}
    On error the exchange is NOT saved to chat history.
    """
    user_id = current_user["_id"]
    model_name = "unknown-model"  # Fallback

    # The ai_data_stale flag is shared by both providers, so when it is set invalidate
    # BOTH providers' caches. Clearing it with a conditional update first means a data
    # change that lands after this point re-sets the flag and is picked up next time.
    try:
        cleared = await users_collection.update_one(
            {"_id": user_id, "ai_data_stale": True},
            {"$set": {"ai_data_stale": False}}
        )
        if cleared.modified_count:
            _invalidate_ai_caches(user_id)
            print(f"🔄 AI data was stale for user {user_id}; invalidated cached vector stores")
    except Exception as e:
        print(f"⚠️ Failed to refresh stale AI data: {e}")

    if chat_request.ai_provider == AIProvider.GEMINI:
        chatbot = gemini_financial_chatbot
        if chatbot is None:
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Gemini AI service is currently unavailable")
        model_name = getattr(chatbot, 'gemini_model', 'gemini-2.5-flash')
        provider = AIProviderType.GEMINI
    else:
        chatbot = financial_chatbot
        if chatbot is None:
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="OpenAI AI service is currently unavailable")
        model_name = getattr(chatbot, 'gpt_model', 'gpt-4o-mini')
        provider = AIProviderType.OPENAI

    chat_history = None
    if chat_request.chat_history:
        # Used only as prompt context; never persisted.
        chat_history = [{"role": msg.role.value, "content": msg.content, "timestamp": msg.timestamp} for msg in chat_request.chat_history]

    response_style = chat_request.response_style.value if chat_request.response_style else "normal"

    async def generate_stream():
        nonlocal model_name
        input_tokens = output_tokens = total_tokens = 0
        full_response = ""
        error_message = None

        try:
            stream = chatbot.stream_chat(
                user_id=user_id,
                message=chat_request.message,
                chat_history=chat_history,
                response_style=response_style
            )

            async for chunk_text, usage_data in stream:
                if chunk_text:
                    full_response += chunk_text
                    yield _sse({"chunk": chunk_text, "done": False, "timestamp": datetime.now(UTC).isoformat()})
                    await asyncio.sleep(0.01)

                if usage_data:
                    input_tokens = usage_data.get('input_tokens') or 0
                    output_tokens = usage_data.get('output_tokens') or 0
                    total_tokens = usage_data.get('total_tokens') or (input_tokens + output_tokens)
                    if usage_data.get('model_name'):
                        model_name = usage_data['model_name']
        except ChatServiceError as e:
            error_message = e.user_message
        except Exception as e:
            print(f"❌ Chat stream error for user {user_id}: {type(e).__name__}: {e}")
            error_message = ChatServiceError.DEFAULT_MESSAGE

        if error_message:
            # Do not persist failed exchanges.
            yield _sse({"error": error_message, "done": True, "timestamp": datetime.now(UTC).isoformat()})
            return

        # Track usage BEFORE the final frame: the client may disconnect as soon as it
        # sees done:true, which would cancel anything after the yield.
        if input_tokens > 0 or output_tokens > 0:
            try:
                await track_ai_usage(
                    user_id=user_id,
                    feature_type=AIFeatureType.CHAT,
                    provider=provider,
                    model_name=model_name,
                    input_tokens=input_tokens,
                    output_tokens=output_tokens,
                    total_tokens=total_tokens
                )
            except Exception as e:
                print(f"⚠️ Failed to track chat AI usage: {e}")

        if full_response:
            # Saved before the "done" frame for the same reason.
            await save_chat_session(user_id, chat_request.message, full_response)

        yield _sse({"chunk": "", "done": True, "full_response": full_response, "timestamp": datetime.now(UTC).isoformat()})

    return StreamingResponse(
        generate_stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "Connection": "keep-alive", "X-Accel-Buffering": "no"}
    )


@app.post("/api/chat", response_model=ChatResponse)
async def chat_with_ai(
    chat_request: ChatRequest,
    current_user: dict = Depends(require_premium)
):
    """Chat with AI about financial data (deprecated - use /stream)"""
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
        # [FIX] Added await
        session = await chat_sessions_collection.find_one(
            {"user_id": current_user["_id"]},
            sort=[("updated_at", -1)]
        )
        
        if not session or "messages" not in session:
            return []
        
        messages = session["messages"][-limit:]
        
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
        # [FIX] Added await
        result = await chat_sessions_collection.delete_many({"user_id": current_user["_id"]})
        return {
            "message": f"Cleared {result.deleted_count} chat sessions",
            "deleted_count": result.deleted_count
        }
    except Exception as e:
        print(f"Clear chat history error: {str(e)}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="An error occurred while clearing chat history")


@app.post("/api/chat/refresh-data")
async def refresh_ai_data(
    ai_provider: AIProvider = Query(default=AIProvider.OPENAI),
    current_user: dict = Depends(get_current_user)
):
    """Manually refresh user's AI data"""
    try:
        # Refresh based on provider
        if ai_provider == AIProvider.GEMINI:
            if gemini_financial_chatbot:
                gemini_financial_chatbot.refresh_user_data(current_user["_id"])
            else:
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="Gemini AI service is currently unavailable"
                )
        else:
            if financial_chatbot:
                financial_chatbot.refresh_user_data(current_user["_id"])
            else:
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="OpenAI AI service is currently unavailable"
                )
        
        return {"message": f"AI data refreshed successfully for {ai_provider.value}"}
    except HTTPException:
        raise
    except Exception as e:
        print(f"Refresh AI data error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An error occurred while refreshing AI data"
        )
    

# ==================== AI INSIGHTS ====================


async def _generate_insight(user_id: str, insight_type: str, ai_provider: str):
    from insights_service import generate_weekly_insight, generate_monthly_insight

    if insight_type == "monthly":
        return await generate_monthly_insight(user_id, ai_provider)
    return await generate_weekly_insight(user_id, ai_provider)


async def _ensure_myanmar_translation(insight: dict, ai_provider: str, user_id: str) -> dict:
    """Translate (and cache) content_mm if missing. Placeholders never hit the paid API."""
    if insight.get("content_mm"):
        return insight

    from insights_service import translate_insight_to_myanmar

    myanmar_content = await translate_insight_to_myanmar(
        insight["content"],
        ai_provider,
        user_id=user_id,
        # None (legacy docs without the flag) falls back to text detection
        is_placeholder=insight.get("is_placeholder"),
    )
    await insights_collection.update_one(
        {"_id": insight["_id"]},
        {"$set": {"content_mm": myanmar_content}}
    )
    insight["content_mm"] = myanmar_content
    return insight


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


def _insight_response(insight: dict) -> InsightResponse:
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
        content_mm=insight.get("content_mm"),
        generated_at=insight["generated_at"],
        expires_at=insight.get("expires_at")
    )


@app.get("/api/insights", response_model=InsightResponse)
async def get_insights(
    language: Optional[str] = Query(default="en", pattern="^(en|mm)$"),
    ai_provider: AIProvider = Query(default=AIProvider.OPENAI),
    insight_type: Optional[str] = Query(default="weekly", pattern="^(weekly|monthly)$"),
    current_user: dict = Depends(require_premium)
):
    """Get latest AI-generated financial insights"""
    user_id = current_user["_id"]
    try:
        from insights_service import latest_valid_insight, user_has_insight_data, _latest_real_insight

        # Legacy insights with content None / "" are treated as missing (skipped here).
        latest_insight = await latest_valid_insight(user_id, ai_provider.value, insight_type)

        # A stored "welcome" placeholder is replaced once the user has real data (incl.
        # transactions in the current, incomplete period). If they don't, but they have
        # older REAL insights (e.g. a legacy placeholder stored over them after a quiet
        # week), the latest real insight is shown instead of the welcome text.
        if latest_insight and latest_insight.get("is_placeholder"):
            try:
                if await user_has_insight_data(user_id, insight_type):
                    print(f"🔄 Replacing placeholder {insight_type} {ai_provider.value} insight for user {user_id} (user now has data)")
                    regenerated = None
                    try:
                        regenerated = await _generate_insight(user_id, insight_type, ai_provider.value)
                    except Exception as gen_error:
                        # AI down / rate limited: something stored is still worth showing.
                        print(f"⚠️ Regenerating {insight_type} insight for user {user_id} failed "
                              f"({type(gen_error).__name__}: {gen_error}); falling back to the stored insight")
                    if _insight_has_content(regenerated):
                        latest_insight = regenerated
                    else:
                        latest_real = await _latest_real_insight(user_id, ai_provider.value, insight_type)
                        if latest_real:
                            latest_insight = latest_real
                        # else: keep showing the stored placeholder
                else:
                    latest_real = await _latest_real_insight(user_id, ai_provider.value, insight_type)
                    if latest_real:
                        latest_insight = latest_real
            except Exception as refresh_error:
                print(f"⚠️ Placeholder refresh failed for user {user_id} "
                      f"({type(refresh_error).__name__}: {refresh_error}); showing the stored placeholder")

        if not latest_insight:
            # Nothing stored at all: generation errors are surfaced (429/503/500).
            print(f"🔄 No {insight_type} insight found, generating first {ai_provider.value} insight for user {user_id}")
            latest_insight = await _generate_insight(user_id, insight_type, ai_provider.value)
            if not _insight_has_content(latest_insight):
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail=f"Couldn't generate your {insight_type} insight right now. Please try again later.",
                )

        if language == "mm":
            latest_insight = await _ensure_myanmar_translation(latest_insight, ai_provider.value, user_id)

        return _insight_response(latest_insight)

    except HTTPException:
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
    """Delete cached insights"""
    try:
        query = {"user_id": current_user["_id"]}
        if ai_provider:
            query["ai_provider"] = ai_provider.value
        if insight_type:
            query["insight_type"] = insight_type

        # [FIX] Added await
        result = await insights_collection.delete_many(query)

        provider_msg = f" for {ai_provider.value}" if ai_provider else ""
        type_msg = f" {insight_type}" if insight_type else ""
        return {"message": f"Deleted {result.deleted_count}{type_msg} insights{provider_msg}", "deleted_count": result.deleted_count}
    except Exception as e:
        print(f"Error deleting insights: {str(e)}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to delete insights")


@app.post("/api/insights/regenerate", response_model=InsightResponse)
async def regenerate_insights(
    language: Optional[str] = Query(default="en", pattern="^(en|mm)$"),
    ai_provider: AIProvider = Query(default=AIProvider.OPENAI),
    insight_type: Optional[str] = Query(default="weekly", pattern="^(weekly|monthly)$"),
    current_user: dict = Depends(require_premium)
):
    """Force regenerate insights (admin/testing purpose)"""
    try:
        print(f"🔄 Force regenerating {insight_type} {ai_provider.value} insights for user {current_user['_id']}")

        new_insight = await _generate_insight(current_user["_id"], insight_type, ai_provider.value)

        if not _insight_has_content(new_insight):
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f"Couldn't regenerate your {insight_type} insight right now. Please try again later.",
            )

        if language == "mm":
            new_insight = await _ensure_myanmar_translation(new_insight, ai_provider.value, current_user["_id"])

        print(f"✅ {insight_type.title()} {ai_provider.value} insights regenerated successfully")
        return _insight_response(new_insight)
    except HTTPException:
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
    current_user: dict = Depends(require_premium)
):
    """Translate the latest weekly or monthly insight to Myanmar"""
    try:
        from insights_service import latest_valid_insight

        # Legacy insights without content can't be translated: skipped.
        insight = await latest_valid_insight(current_user["_id"], ai_provider.value, insight_type)

        if not insight:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"No {insight_type} {ai_provider.value} insights found to translate")

        if insight.get("content_mm"):
            return {"message": "Myanmar translation already exists", "already_translated": True}

        print(f"🔄 Translating {insight_type} insights to Myanmar using {ai_provider.value} for user {current_user['_id']}")
        await _ensure_myanmar_translation(insight, ai_provider.value, current_user["_id"])

        return {"message": "Translation completed successfully", "already_translated": False}

    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Translation error: {type(e).__name__}: {e}")
        raise _insight_http_error(e, "translate your insights")




@app.post("/api/insights/generate-weekly")
async def manually_generate_weekly_insights(
    current_user: dict = Depends(require_premium)
):
    """Manually trigger weekly insights generation for current user"""
    try:
        from insights_service import generate_weekly_insight
        
        results = {}
        
        for provider in ["openai", "gemini"]:
            try:
                insight = await generate_weekly_insight(
                    current_user["_id"],
                    provider
                )
                results[provider] = "success" if insight else "failed"
            except Exception as e:
                from insights_service import is_rate_limit_error

                print(f"❌ Manual weekly insight ({provider}) failed: {type(e).__name__}: {e}")
                # No raw exception text in the response.
                results[provider] = "rate_limited" if is_rate_limit_error(e) else "error"
        
        return {
            "message": "Weekly insights generation completed",
            "results": results
        }
        
    except Exception as e:
        print(f"Error in manual weekly generation: {str(e)}")
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
        released = await users_collection.update_many(
            {"fcm_token": token, "_id": {"$ne": user_id}},
            {"$unset": {"fcm_token": ""}}
        )
        if released.modified_count:
            print(f"🔁 FCM token detached from {released.modified_count} other user(s)")

        await users_collection.update_one(
            {"_id": user_id},
            {"$set": {"fcm_token": token}}
        )
        return {"message": "FCM token updated successfully"}
    except Exception as e:
        print(f"Error updating FCM token: {str(e)}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to update FCM token")


@app.delete("/api/auth/fcm-token")
async def delete_fcm_token(current_user: dict = Depends(get_current_user)):
    """Unregister the current user's FCM token (call on logout)"""
    try:
        await users_collection.update_one(
            {"_id": current_user["_id"]},
            {"$unset": {"fcm_token": ""}}
        )
        return {"message": "FCM token removed successfully"}
    except Exception as e:
        print(f"Error removing FCM token: {str(e)}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to remove FCM token")


@app.get("/api/notifications/preferences", response_model=NotificationPreferencesResponse)
async def get_notification_preferences(current_user: dict = Depends(get_current_user)):
    """Get user's notification preferences"""
    try:
        # [FIX] Added await
        prefs_doc = await notification_preferences_collection.find_one({
            "user_id": current_user["_id"]
        })
        
        if not prefs_doc:
            default_prefs = NotificationPreferences()
            now = datetime.now(UTC)
            prefs_doc = {
                "user_id": current_user["_id"],
                "preferences": default_prefs.dict(),
                "created_at": now,
                "updated_at": now
            }
            # [FIX] Added await
            await notification_preferences_collection.insert_one(prefs_doc)
        
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
        now = datetime.now(UTC)
        # [FIX] Added await
        prefs_doc = await notification_preferences_collection.find_one({
            "user_id": current_user["_id"]
        })
        
        if prefs_doc:
            current_prefs = prefs_doc.get("preferences", {})
            current_prefs.update(update_data.preferences)
            # [FIX] Added await
            await notification_preferences_collection.update_one(
                {"user_id": current_user["_id"]},
                {
                    "$set": {
                        "preferences": current_prefs,
                        "updated_at": now
                    }
                }
            )
        else:
            default_prefs = NotificationPreferences().dict()
            default_prefs.update(update_data.preferences)
            prefs_doc = {
                "user_id": current_user["_id"],
                "preferences": default_prefs,
                "created_at": now,
                "updated_at": now
            }
            # [FIX] Added await
            await notification_preferences_collection.insert_one(prefs_doc)
        
        # [FIX] Added await
        updated_doc = await notification_preferences_collection.find_one({
            "user_id": current_user["_id"]
        })
        
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
        
        # [FIX] Added await
        await notification_preferences_collection.update_one(
            {"user_id": current_user["_id"]},
            {
                "$set": {
                    "preferences": default_prefs.dict(),
                    "updated_at": now
                }
            },
            upsert=True
        )
        
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
        query = {"user_id": current_user["_id"]}
        if unread_only:
            query["is_read"] = False

        # [FIX] Async query execution
        cursor = notifications_collection.find(query).sort("created_at", -1).limit(limit)
        notifications = await cursor.to_list(length=limit)

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
        # [FIX] Added await
        result = await notifications_collection.update_one(
            {"_id": notification_id, "user_id": current_user["_id"]},
            {"$set": {"is_read": True}}
        )

        if result.matched_count == 0:
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
        # [FIX] Added await
        result = await notifications_collection.update_many(
            {"user_id": current_user["_id"], "is_read": False},
            {"$set": {"is_read": True}}
        )
        
        return {"message": f"Marked {result.modified_count} notifications as read", "count": result.modified_count}
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
        # [FIX] Added await
        result = await notifications_collection.delete_one({
            "_id": notification_id,
            "user_id": current_user["_id"]
        })
        
        if result.deleted_count == 0:
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
        # [FIX] Added await
        count = await notifications_collection.count_documents({
            "user_id": current_user["_id"],
            "is_read": False
        })
        
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