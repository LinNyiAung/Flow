import asyncio
import hashlib
import json
import uuid
from datetime import datetime, timedelta, UTC
from typing import List, Optional

from fastapi import FastAPI, HTTPException, status, Depends, Query, Path
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware

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


from notification_models import NotificationResponse, NotificationType
from notification_service import (
    analyze_unusual_spending,
    notify_budget_started
)


from database import (
    transactions_collection, categories_collection,
    chat_sessions_collection, goals_collection, insights_collection, budgets_collection, notifications_collection, notification_preferences_collection
)
from ai_chatbot import financial_chatbot
from ai_chatbot_gemini import gemini_financial_chatbot
from config import settings


from transaction_routes import router as transaction_router
from goal_routes import router as goal_router
from auth_routes import router as auth_router
from budget_routes import router as budget_router
from report_routes import router as report_router

app = FastAPI(title="Flow Finance API", version="1.0.0")
app.include_router(transaction_router)
app.include_router(auth_router)
app.include_router(goal_router)
app.include_router(budget_router)
app.include_router(report_router)

try:
    scheduler = start_scheduler()
    print("✅ Notification scheduler started successfully")
except Exception as e:
    print(f"⚠️ Failed to start notification scheduler: {e}")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ==================== CATEGORIES & DASHBOARD ====================

@app.get("/api/categories/{transaction_type}", response_model=List[CategoryResponse])
async def get_categories(transaction_type: TransactionType):
    """Get categories for transaction type"""
    categories_doc = categories_collection.find_one({"_id": transaction_type.value})
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
    Get user's financial balance including goal allocations
    If currency is specified, returns balance for that currency only
    Otherwise returns balances for all currencies
    """
    return await get_user_balance(current_user["_id"], currency.value if currency else None)


# ==================== AI CHATBOT ====================

async def save_chat_session(user_id: str, user_message: str, ai_response: str, chat_history):
    """Save chat session to database"""
    try:
        current_time = datetime.now(UTC)
        
        messages = []
        if chat_history:
            messages = [
                {
                    "role": msg["role"],
                    "content": msg["content"],
                    "timestamp": msg.get("timestamp", current_time)
                }
                for msg in chat_history
            ]
        
        messages.extend([
            {"role": "user", "content": user_message, "timestamp": current_time},
            {"role": "assistant", "content": ai_response, "timestamp": current_time}
        ])
        
        if len(messages) > settings.MAX_CHAT_HISTORY:
            messages = messages[-settings.MAX_CHAT_HISTORY:]
        
        existing_session = chat_sessions_collection.find_one(
            {"user_id": user_id},
            sort=[("updated_at", -1)]
        )
        
        if existing_session:
            chat_sessions_collection.update_one(
                {"_id": existing_session["_id"]},
                {"$set": {"messages": messages, "updated_at": current_time}}
            )
        else:
            chat_sessions_collection.insert_one({
                "_id": str(uuid.uuid4()),
                "user_id": user_id,
                "messages": messages,
                "created_at": current_time,
                "updated_at": current_time
            })
    except Exception as e:
        print(f"Error saving chat session: {e}")


@app.post("/api/chat/stream")
async def stream_chat_with_ai(
    chat_request: ChatRequest,
    current_user: dict = Depends(require_premium)
):
    """Stream chat response from AI with response style and provider support"""
    
    # NEW: Select chatbot based on provider
    if chat_request.ai_provider == AIProvider.GEMINI:
        chatbot = gemini_financial_chatbot
        if chatbot is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Gemini AI service is currently unavailable"
            )
    else:  # Default to OpenAI
        chatbot = financial_chatbot
        if chatbot is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="OpenAI AI service is currently unavailable"
            )
    
    chat_history = None
    if chat_request.chat_history:
        chat_history = [
            {
                "role": msg.role.value,
                "content": msg.content,
                "timestamp": msg.timestamp
            }
            for msg in chat_request.chat_history
        ]
    
    # Get response style from request (default to "normal")
    response_style = chat_request.response_style.value if chat_request.response_style else "normal"
    
    async def generate_stream():
        try:
            stream = chatbot.stream_chat(  # Use selected chatbot
                user_id=current_user["_id"],
                message=chat_request.message,
                chat_history=chat_history,
                response_style=response_style
            )
            
            full_response = ""
            async for chunk in stream:
                full_response += chunk
                data = {
                    "chunk": chunk,
                    "done": False,
                    "timestamp": datetime.now(UTC).isoformat()
                }
                yield f"data: {json.dumps(data)}\n\n"
                await asyncio.sleep(0.01)
            
            final_data = {
                "chunk": "",
                "done": True,
                "full_response": full_response,
                "timestamp": datetime.now(UTC).isoformat()
            }
            yield f"data: {json.dumps(final_data)}\n\n"
            
            await save_chat_session(current_user["_id"], chat_request.message, full_response, chat_history)
            
        except Exception as e:
            error_data = {
                "error": str(e).replace('Exception: ', ''),
                "done": True,
                "timestamp": datetime.now(UTC).isoformat()
            }
            yield f"data: {json.dumps(error_data)}\n\n"
    
    return StreamingResponse(
        generate_stream(),
        media_type="text/plain",
        headers={"Cache-Control": "no-cache", "Connection": "keep-alive"}
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
    limit: int = Query(default=20, le=50)
):
    """Get user's chat history"""
    try:
        session = chat_sessions_collection.find_one(
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
        result = chat_sessions_collection.delete_many({"user_id": current_user["_id"]})
        return {
            "message": f"Cleared {result.deleted_count} chat sessions",
            "deleted_count": result.deleted_count
        }
    except Exception as e:
        print(f"Clear chat history error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An error occurred while clearing chat history"
        )



@app.post("/api/chat/refresh-data")
async def refresh_ai_data(
    ai_provider: AIProvider = Query(default=AIProvider.OPENAI),  # NEW
    current_user: dict = Depends(get_current_user)
):
    """Manually refresh user's AI data"""
    try:
        # NEW: Refresh based on provider
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
    
def calculate_data_hash(user_id: str) -> str:
    """Calculate hash of user's financial data to detect changes"""
    # Get counts and totals to create a fingerprint
    transaction_count = transactions_collection.count_documents({"user_id": user_id})
    goal_count = goals_collection.count_documents({"user_id": user_id})
    
    # Get last transaction date
    last_transaction = transactions_collection.find_one(
        {"user_id": user_id},
        sort=[("date", -1)]
    )
    last_transaction_date = last_transaction["date"].isoformat() if last_transaction else "none"
    
    # Get last goal update
    last_goal = goals_collection.find_one(
        {"user_id": user_id},
        sort=[("updated_at", -1)]
    )
    last_goal_update = last_goal["updated_at"].isoformat() if last_goal else "none"
    
    # Create hash from all these elements
    data_string = f"{user_id}:{transaction_count}:{goal_count}:{last_transaction_date}:{last_goal_update}"
    return hashlib.sha256(data_string.encode()).hexdigest()


@app.get("/api/insights", response_model=InsightResponse)
async def get_insights(
    language: Optional[str] = Query(default="en", regex="^(en|mm)$"),
    ai_provider: AIProvider = Query(default=AIProvider.OPENAI),  # NEW
    current_user: dict = Depends(require_premium)
):
    """Get AI-generated financial insights (cached if data unchanged)"""
    try:
        # Calculate current data hash
        current_hash = calculate_data_hash(current_user["_id"])
        
        # NEW: Add provider to cache key
        cache_key = f"{current_user['_id']}_{ai_provider.value}"
        
        # Check if we have cached insights for this provider
        cached_insight = insights_collection.find_one({
            "user_id": current_user["_id"],
            "data_hash": current_hash,
            "ai_provider": ai_provider.value  # NEW
        })
        
        if cached_insight:
            print(f"✅ Returning cached {ai_provider.value} insights for user {current_user['_id']}")
            
            # If Myanmar requested but not cached, generate translation
            if language == "mm" and not cached_insight.get("content_mm"):
                print(f"🔄 Generating Myanmar translation using {ai_provider.value}...")
                
                # Select chatbot for translation
                chatbot = gemini_financial_chatbot if ai_provider == AIProvider.GEMINI else financial_chatbot
                
                if chatbot is None:
                    raise HTTPException(
                        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                        detail=f"{ai_provider.value} AI service is currently unavailable"
                    )
                
                myanmar_content = await chatbot.translate_insights_to_myanmar(
                    cached_insight["content"]
                )
                
                # Update cache with Myanmar translation
                insights_collection.update_one(
                    {"_id": cached_insight["_id"]},
                    {"$set": {"content_mm": myanmar_content}}
                )
                
                cached_insight["content_mm"] = myanmar_content
            
            return InsightResponse(
                id=cached_insight["_id"],
                user_id=cached_insight["user_id"],
                content=cached_insight["content"],
                content_mm=cached_insight.get("content_mm"),
                generated_at=cached_insight["generated_at"],
                data_hash=cached_insight["data_hash"],
                expires_at=cached_insight.get("expires_at")
            )
        
        # Generate new insights
        print(f"🔄 Generating new {ai_provider.value} insights for user {current_user['_id']}")
        
        # Select chatbot
        chatbot = gemini_financial_chatbot if ai_provider == AIProvider.GEMINI else financial_chatbot
        
        if chatbot is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f"{ai_provider.value} AI service is currently unavailable"
            )
        
        insights_content = await chatbot.generate_insights(current_user["_id"])
        
        # Generate Myanmar translation if requested
        myanmar_content = None
        if language == "mm":
            print(f"🔄 Generating Myanmar translation using {ai_provider.value}...")
            myanmar_content = await chatbot.translate_insights_to_myanmar(insights_content)
        
        # Save to database
        insight_id = str(uuid.uuid4())
        now = datetime.now(UTC)
        
        new_insight = {
            "_id": insight_id,
            "user_id": current_user["_id"],
            "content": insights_content,
            "content_mm": myanmar_content,
            "generated_at": now,
            "data_hash": current_hash,
            "ai_provider": ai_provider.value,  # NEW
            "expires_at": None
        }
        
        # Delete old insights for this user and provider
        insights_collection.delete_many({
            "user_id": current_user["_id"],
            "ai_provider": ai_provider.value
        })
        
        # Insert new insight
        insights_collection.insert_one(new_insight)
        
        print(f"✅ New {ai_provider.value} insights generated and cached")
        
        return InsightResponse(
            id=insight_id,
            user_id=current_user["_id"],
            content=insights_content,
            content_mm=myanmar_content,
            generated_at=now,
            data_hash=current_hash,
            expires_at=None
        )
        
    except Exception as e:
        print(f"❌ Error generating insights: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate insights: {str(e)}"
        )


@app.delete("/api/insights")
async def delete_insights(
    ai_provider: Optional[AIProvider] = Query(default=None),  # NEW: Optional to delete specific provider
    current_user: dict = Depends(get_current_user)
):
    """Force regeneration of insights by deleting cached ones"""
    try:
        query = {"user_id": current_user["_id"]}
        
        # NEW: If provider specified, only delete for that provider
        if ai_provider:
            query["ai_provider"] = ai_provider.value
        
        result = insights_collection.delete_many(query)
        
        provider_msg = f" for {ai_provider.value}" if ai_provider else ""
        return {
            "message": f"Deleted {result.deleted_count} cached insights{provider_msg}",
            "deleted_count": result.deleted_count
        }
    except Exception as e:
        print(f"Error deleting insights: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete insights"
        )


@app.post("/api/insights/regenerate", response_model=InsightResponse)
async def regenerate_insights(
    language: Optional[str] = Query(default="en", regex="^(en|mm)$"),
    ai_provider: AIProvider = Query(default=AIProvider.OPENAI),  # NEW
    current_user: dict = Depends(require_premium)
):
    """Force regenerate insights regardless of data changes"""
    try:
        # Delete cached insights for this provider
        insights_collection.delete_many({
            "user_id": current_user["_id"],
            "ai_provider": ai_provider.value
        })
        
        current_hash = calculate_data_hash(current_user["_id"])
        
        print(f"🔄 Force regenerating {ai_provider.value} insights for user {current_user['_id']}")
        
        # Select chatbot
        chatbot = gemini_financial_chatbot if ai_provider == AIProvider.GEMINI else financial_chatbot
        
        if chatbot is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f"{ai_provider.value} AI service is currently unavailable"
            )
        
        insights_content = await chatbot.generate_insights(current_user["_id"])
        
        # Generate Myanmar translation if requested
        myanmar_content = None
        if language == "mm":
            print(f"🔄 Generating Myanmar translation using {ai_provider.value}...")
            myanmar_content = await chatbot.translate_insights_to_myanmar(insights_content)
        
        insight_id = str(uuid.uuid4())
        now = datetime.now(UTC)
        
        new_insight = {
            "_id": insight_id,
            "user_id": current_user["_id"],
            "content": insights_content,
            "content_mm": myanmar_content,
            "generated_at": now,
            "data_hash": current_hash,
            "ai_provider": ai_provider.value,  # NEW
            "expires_at": None
        }
        
        insights_collection.insert_one(new_insight)
        
        print(f"✅ {ai_provider.value} insights regenerated successfully")
        
        return InsightResponse(
            id=insight_id,
            user_id=current_user["_id"],
            content=insights_content,
            content_mm=myanmar_content,
            generated_at=now,
            data_hash=current_hash,
            expires_at=None
        )
        
    except Exception as e:
        print(f"❌ Error regenerating insights: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to regenerate insights: {str(e)}"
        )


@app.post("/api/insights/translate-myanmar")
async def translate_insights_to_myanmar(
    ai_provider: AIProvider = Query(default=AIProvider.OPENAI),  # NEW
    current_user: dict = Depends(require_premium)
):
    """Translate existing English insights to Myanmar"""
    try:
        # Get existing insights for this provider
        insight = insights_collection.find_one({
            "user_id": current_user["_id"],
            "ai_provider": ai_provider.value
        })
        
        if not insight:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"No {ai_provider.value} insights found to translate"
            )
        
        # Check if already translated
        if insight.get("content_mm"):
            return {
                "message": "Myanmar translation already exists",
                "already_translated": True
            }
        
        # Select chatbot
        chatbot = gemini_financial_chatbot if ai_provider == AIProvider.GEMINI else financial_chatbot
        
        if chatbot is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f"{ai_provider.value} AI service is currently unavailable"
            )
        
        print(f"🔄 Translating insights to Myanmar using {ai_provider.value} for user {current_user['_id']}")
        
        myanmar_content = await chatbot.translate_insights_to_myanmar(
            insight["content"]
        )
        
        # Update with Myanmar translation
        insights_collection.update_one(
            {"_id": insight["_id"]},
            {"$set": {"content_mm": myanmar_content}}
        )
        
        print(f"✅ Myanmar translation completed using {ai_provider.value}")
        
        return {
            "message": "Translation completed successfully",
            "already_translated": False
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Translation error: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to translate insights: {str(e)}"
        )
    
        
        
# ==================== NOTIFICATIONS ====================


@app.get("/api/notifications/preferences", response_model=NotificationPreferencesResponse)
async def get_notification_preferences(current_user: dict = Depends(get_current_user)):
    """Get user's notification preferences"""
    try:
        prefs_doc = notification_preferences_collection.find_one({
            "user_id": current_user["_id"]
        })
        
        if not prefs_doc:
            # Create default preferences
            default_prefs = NotificationPreferences()
            now = datetime.now(UTC)
            
            prefs_doc = {
                "user_id": current_user["_id"],
                "preferences": default_prefs.dict(),
                "created_at": now,
                "updated_at": now
            }
            
            notification_preferences_collection.insert_one(prefs_doc)
        
        return NotificationPreferencesResponse(
            user_id=prefs_doc["user_id"],
            preferences=NotificationPreferences(**prefs_doc["preferences"]),
            updated_at=prefs_doc["updated_at"]
        )
        
    except Exception as e:
        print(f"Error getting notification preferences: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get notification preferences"
        )


@app.put("/api/notifications/preferences", response_model=NotificationPreferencesResponse)
async def update_notification_preferences(
    update_data: NotificationPreferencesUpdate,
    current_user: dict = Depends(get_current_user)
):
    """Update user's notification preferences"""
    try:
        now = datetime.now(UTC)
        
        # Get existing preferences or create new
        prefs_doc = notification_preferences_collection.find_one({
            "user_id": current_user["_id"]
        })
        
        if prefs_doc:
            # Update existing preferences
            current_prefs = prefs_doc.get("preferences", {})
            current_prefs.update(update_data.preferences)
            
            notification_preferences_collection.update_one(
                {"user_id": current_user["_id"]},
                {
                    "$set": {
                        "preferences": current_prefs,
                        "updated_at": now
                    }
                }
            )
        else:
            # Create new preferences
            default_prefs = NotificationPreferences().dict()
            default_prefs.update(update_data.preferences)
            
            prefs_doc = {
                "user_id": current_user["_id"],
                "preferences": default_prefs,
                "created_at": now,
                "updated_at": now
            }
            
            notification_preferences_collection.insert_one(prefs_doc)
        
        # Get updated document
        updated_doc = notification_preferences_collection.find_one({
            "user_id": current_user["_id"]
        })
        
        return NotificationPreferencesResponse(
            user_id=updated_doc["user_id"],
            preferences=NotificationPreferences(**updated_doc["preferences"]),
            updated_at=updated_doc["updated_at"]
        )
        
    except Exception as e:
        print(f"Error updating notification preferences: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update notification preferences"
        )


@app.post("/api/notifications/preferences/reset")
async def reset_notification_preferences(current_user: dict = Depends(get_current_user)):
    """Reset notification preferences to default (all enabled)"""
    try:
        now = datetime.now(UTC)
        default_prefs = NotificationPreferences()
        
        notification_preferences_collection.update_one(
            {"user_id": current_user["_id"]},
            {
                "$set": {
                    "preferences": default_prefs.dict(),
                    "updated_at": now
                }
            },
            upsert=True
        )
        
        return {
            "message": "Notification preferences reset to default",
            "preferences": default_prefs.dict()
        }
        
    except Exception as e:
        print(f"Error resetting notification preferences: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to reset notification preferences"
        )

@app.get("/api/notifications", response_model=List[NotificationResponse])
async def get_notifications(
    current_user: dict = Depends(get_current_user),
    limit: int = Query(default=50, le=100),
    unread_only: bool = Query(default=False)
):
    """Get user notifications"""
    try:
        query = {"user_id": current_user["_id"]}
        
        if unread_only:
            query["is_read"] = False
        
        notifications = list(
            notifications_collection
            .find(query)
            .sort("created_at", -1)
            .limit(limit)
        )
        
        return [
            NotificationResponse(
                id=n["_id"],
                user_id=n["user_id"],
                type=NotificationType(n["type"]),
                title=n["title"],
                message=n["message"],
                goal_id=n.get("goal_id"),
                goal_name=n.get("goal_name"),
                currency=n.get("currency"),  # NEW
                created_at=n["created_at"],
                is_read=n["is_read"]
            )
            for n in notifications
        ]
    except Exception as e:
        print(f"Error fetching notifications: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to fetch notifications"
        )


@app.post("/api/notifications/{notification_id}/mark-read")
async def mark_notification_read(
    notification_id: str = Path(...),
    current_user: dict = Depends(get_current_user)
):
    """Mark a notification as read"""
    try:
        result = notifications_collection.update_one(
            {"_id": notification_id, "user_id": current_user["_id"]},
            {"$set": {"is_read": True}}
        )
        
        if result.modified_count == 0:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Notification not found"
            )
        
        return {"message": "Notification marked as read"}
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error marking notification read: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to mark notification as read"
        )


@app.post("/api/notifications/mark-all-read")
async def mark_all_notifications_read(current_user: dict = Depends(get_current_user)):
    """Mark all notifications as read"""
    try:
        result = notifications_collection.update_many(
            {"user_id": current_user["_id"], "is_read": False},
            {"$set": {"is_read": True}}
        )
        
        return {
            "message": f"Marked {result.modified_count} notifications as read",
            "count": result.modified_count
        }
    except Exception as e:
        print(f"Error marking all notifications read: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to mark notifications as read"
        )


@app.delete("/api/notifications/{notification_id}")
async def delete_notification(
    notification_id: str = Path(...),
    current_user: dict = Depends(get_current_user)
):
    """Delete a notification"""
    try:
        result = notifications_collection.delete_one({
            "_id": notification_id,
            "user_id": current_user["_id"]
        })
        
        if result.deleted_count == 0:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Notification not found"
            )
        
        return {"message": "Notification deleted successfully"}
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error deleting notification: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete notification"
        )


@app.get("/api/notifications/unread-count")
async def get_unread_count(current_user: dict = Depends(get_current_user)):
    """Get count of unread notifications"""
    try:
        count = notifications_collection.count_documents({
            "user_id": current_user["_id"],
            "is_read": False
        })
        
        return {"unread_count": count}
    except Exception as e:
        print(f"Error getting unread count: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get unread count"
        )
        
        
        
@app.post("/api/notifications/analyze-spending")
async def analyze_spending_patterns(current_user: dict = Depends(get_current_user)):
    """Manually trigger unusual spending analysis"""
    try:
        analyze_unusual_spending(current_user["_id"])
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
    return {"message": "Flow Finance API with AI Assistant is running"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)