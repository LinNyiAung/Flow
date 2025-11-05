import asyncio
import base64
import hashlib
import json
import uuid
from datetime import datetime, timedelta, UTC, timezone
from typing import List, Optional

from fastapi import FastAPI, File, HTTPException, UploadFile, status, Depends, Query, Path
from fastapi.responses import StreamingResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware

from pdf_generator import generate_financial_report_pdf
from report_models import CategoryBreakdown, FinancialReport, GoalProgress, ReportPeriod, ReportRequest
from insight_models import InsightResponse
from goal_models import GoalContribution, GoalCreate, GoalResponse, GoalStatus, GoalType, GoalUpdate, GoalsSummary
from models import (
    TextExtractionRequest, TransactionExtraction, UserCreate, UserLogin, UserResponse, Token,
    TransactionCreate, TransactionResponse, CategoryResponse, TransactionType,
    TransactionUpdate
)
from chat_models import (
    ChatRequest, ChatResponse, ChatMessage, MessageRole,
)
from database import (
    users_collection, transactions_collection, categories_collection,
    chat_sessions_collection, goals_collection, insights_collection
)
from auth import get_password_hash, verify_password, create_access_token, verify_token
from ai_chatbot import financial_chatbot
from config import settings

app = FastAPI(title="Flow Finance API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

security = HTTPBearer()


def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """Get current authenticated user"""
    email = verify_token(credentials.credentials)
    user = users_collection.find_one({"email": email})
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    return user


# ==================== AUTHENTICATION ====================

@app.post("/api/auth/register", response_model=Token)
async def register(user_data: UserCreate):
    """Register new user"""
    if users_collection.find_one({"email": user_data.email}):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered")

    user_id = str(uuid.uuid4())
    new_user = {
        "_id": user_id,
        "name": user_data.name,
        "email": user_data.email,
        "password": get_password_hash(user_data.password),
        "created_at": datetime.now(UTC)
    }
    users_collection.insert_one(new_user)

    access_token = create_access_token(
        data={"sub": user_data.email},
        expires_delta=timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    )

    return Token(
        access_token=access_token,
        token_type="bearer",
        user=UserResponse(
            id=user_id,
            name=user_data.name,
            email=user_data.email,
            created_at=new_user["created_at"]
        )
    )


@app.post("/api/auth/login", response_model=Token)
async def login(user_credentials: UserLogin):
    """Login user"""
    user = users_collection.find_one({"email": user_credentials.email})
    if not user or not verify_password(user_credentials.password, user["password"]):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Incorrect email or password")

    access_token = create_access_token(
        data={"sub": user["email"]},
        expires_delta=timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    )

    return Token(
        access_token=access_token,
        token_type="bearer",
        user=UserResponse(
            id=user["_id"],
            name=user["name"],
            email=user["email"],
            created_at=user["created_at"]
        )
    )


@app.get("/api/auth/me", response_model=UserResponse)
async def get_current_user_info(current_user: dict = Depends(get_current_user)):
    """Get current user info"""
    return UserResponse(
        id=current_user["_id"],
        name=current_user["name"],
        email=current_user["email"],
        created_at=current_user["created_at"]
    )


# ==================== TRANSACTIONS ====================

def refresh_ai_data_silent(user_id: str):
    """Silently refresh AI data without failing on error"""
    try:
        if financial_chatbot:
            financial_chatbot.refresh_user_data(user_id)
    except Exception as e:
        print(f"Error refreshing AI data: {e}")


@app.post("/api/transactions", response_model=TransactionResponse)
async def create_transaction(
    transaction_data: TransactionCreate,
    current_user: dict = Depends(get_current_user)
):
    """Create new transaction"""
    transaction_id = str(uuid.uuid4())
    now = datetime.now(UTC)
    
    new_transaction = {
        "_id": transaction_id,
        "user_id": current_user["_id"],
        "type": transaction_data.type.value,
        "main_category": transaction_data.main_category,
        "sub_category": transaction_data.sub_category,
        "date": transaction_data.date.replace(tzinfo=timezone.utc) if transaction_data.date.tzinfo is None else transaction_data.date,  # Ensure UTC
        "description": transaction_data.description,
        "amount": transaction_data.amount,
        "created_at": now,
        "updated_at": now
    }

    result = transactions_collection.insert_one(new_transaction)
    if not result.inserted_id:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to create transaction")
    
    refresh_ai_data_silent(current_user["_id"])

    return TransactionResponse(
        id=transaction_id,
        user_id=current_user["_id"],
        type=transaction_data.type,
        main_category=transaction_data.main_category,
        sub_category=transaction_data.sub_category,
        date=transaction_data.date,
        description=transaction_data.description,
        amount=transaction_data.amount,
        created_at=now,
        updated_at=now
    )


@app.get("/api/transactions", response_model=List[TransactionResponse])
async def get_transactions(
    current_user: dict = Depends(get_current_user),
    limit: int = Query(default=50, le=10000),
    skip: int = Query(default=0, ge=0),
    transaction_type: Optional[TransactionType] = None,
    start_date: Optional[datetime] = None,
    end_date: Optional[datetime] = None
):
    """Get user transactions with filters"""
    query = {"user_id": current_user["_id"]}
    
    if transaction_type:
        query["type"] = transaction_type.value
    
    if start_date or end_date:
        date_filter = {}
        if start_date:
            date_filter["$gte"] = start_date
        if end_date:
            date_filter["$lte"] = end_date.replace(hour=23, minute=59, second=59, microsecond=999999)
        query["date"] = date_filter

    transactions = list(
        transactions_collection
        .find(query)
        .sort("date", -1)
        .skip(skip)
        .limit(limit)
    )

    return [
        TransactionResponse(
            id=t["_id"],
            user_id=t["user_id"],
            type=TransactionType(t["type"]),
            main_category=t["main_category"],
            sub_category=t["sub_category"],
            date=t["date"],
            description=t["description"],
            amount=t["amount"],
            created_at=t["created_at"],
            updated_at=t.get("updated_at", t["created_at"])
        )
        for t in transactions
    ]


@app.get("/api/transactions/{transaction_id}", response_model=TransactionResponse)
async def get_transaction(
    transaction_id: str = Path(...),
    current_user: dict = Depends(get_current_user)
):
    """Get single transaction"""
    transaction = transactions_collection.find_one({
        "_id": transaction_id,
        "user_id": current_user["_id"]
    })

    if not transaction:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transaction not found")

    return TransactionResponse(
        id=transaction["_id"],
        user_id=transaction["user_id"],
        type=TransactionType(transaction["type"]),
        main_category=transaction["main_category"],
        sub_category=transaction["sub_category"],
        date=transaction["date"],
        description=transaction["description"],
        amount=transaction["amount"],
        created_at=transaction["created_at"],
        updated_at=transaction.get("updated_at", transaction["created_at"])
    )


@app.put("/api/transactions/{transaction_id}", response_model=TransactionResponse)
async def update_transaction(
    transaction_id: str = Path(...),
    transaction_data: TransactionUpdate = ...,
    current_user: dict = Depends(get_current_user)
):
    """Update transaction"""
    if not transactions_collection.find_one({"_id": transaction_id, "user_id": current_user["_id"]}):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transaction not found")

    update_data = {"updated_at": datetime.now(UTC)}
    
    for field in ["type", "main_category", "sub_category", "date", "description", "amount"]:
        value = getattr(transaction_data, field, None)
        if value is not None:
            update_data[field] = value.value if field == "type" else value

    transactions_collection.update_one(
        {"_id": transaction_id},
        {"$set": update_data}
    )

    updated_transaction = transactions_collection.find_one({"_id": transaction_id})
    refresh_ai_data_silent(current_user["_id"])

    return TransactionResponse(
        id=updated_transaction["_id"],
        user_id=updated_transaction["user_id"],
        type=TransactionType(updated_transaction["type"]),
        main_category=updated_transaction["main_category"],
        sub_category=updated_transaction["sub_category"],
        date=updated_transaction["date"],
        description=updated_transaction["description"],
        amount=updated_transaction["amount"],
        created_at=updated_transaction["created_at"],
        updated_at=updated_transaction["updated_at"]
    )


@app.delete("/api/transactions/{transaction_id}")
async def delete_transaction(
    transaction_id: str = Path(...),
    current_user: dict = Depends(get_current_user)
):
    """Delete transaction"""
    if not transactions_collection.find_one({"_id": transaction_id, "user_id": current_user["_id"]}):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transaction not found")

    result = transactions_collection.delete_one({"_id": transaction_id, "user_id": current_user["_id"]})
    
    if result.deleted_count == 0:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to delete transaction")

    refresh_ai_data_silent(current_user["_id"])
    return {"message": "Transaction deleted successfully"}


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
async def get_balance(current_user: dict = Depends(get_current_user)):
    """Get user's financial balance including goal allocations"""
    pipeline_inflow = [
        {"$match": {"user_id": current_user["_id"], "type": "inflow"}},
        {"$group": {"_id": None, "total": {"$sum": "$amount"}}}
    ]
    pipeline_outflow = [
        {"$match": {"user_id": current_user["_id"], "type": "outflow"}},
        {"$group": {"_id": None, "total": {"$sum": "$amount"}}}
    ]

    inflow_result = list(transactions_collection.aggregate(pipeline_inflow))
    outflow_result = list(transactions_collection.aggregate(pipeline_outflow))

    total_inflow = inflow_result[0]["total"] if inflow_result else 0
    total_outflow = outflow_result[0]["total"] if outflow_result else 0
    
    # Calculate total allocated to ALL goals (both active and achieved)
    # Achieved goals should still keep their allocated funds
    goals_pipeline = [
        {"$match": {"user_id": current_user["_id"]}},  # Remove status filter
        {"$group": {"_id": None, "total": {"$sum": "$current_amount"}}}
    ]
    goals_result = list(goals_collection.aggregate(goals_pipeline))
    total_allocated_to_goals = goals_result[0]["total"] if goals_result else 0

    total_balance = total_inflow - total_outflow
    available_balance = total_balance - total_allocated_to_goals

    return {
        "balance": total_balance,
        "available_balance": available_balance,
        "allocated_to_goals": total_allocated_to_goals,
        "total_inflow": total_inflow,
        "total_outflow": total_outflow
    }


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
    current_user: dict = Depends(get_current_user)
):
    """Stream chat response from AI"""
    if financial_chatbot is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="AI service is currently unavailable"
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
    
    async def generate_stream():
        try:
            stream = financial_chatbot.stream_chat(
                user_id=current_user["_id"],
                message=chat_request.message,
                chat_history=chat_history
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
    current_user: dict = Depends(get_current_user)
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
async def refresh_ai_data(current_user: dict = Depends(get_current_user)):
    """Manually refresh user's AI data"""
    try:
        financial_chatbot.refresh_user_data(current_user["_id"])
        return {"message": "AI data refreshed successfully"}
    except Exception as e:
        print(f"Refresh AI data error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An error occurred while refreshing AI data"
        )
        
        
@app.get("/api/debug/transactions")
async def debug_transactions(current_user: dict = Depends(get_current_user)):
    """Debug endpoint to check transaction dates and timezone info"""
    from datetime import timezone
    import platform
    
    # Get recent transactions
    transactions = list(
        transactions_collection
        .find({"user_id": current_user["_id"]})
        .sort("date", -1)
        .limit(5)
    )
    
    # Get server info
    server_time = datetime.now(timezone.utc)
    server_time_local = datetime.now()
    
    debug_info = {
        "server_timezone": str(server_time_local.astimezone().tzinfo),
        "server_time_utc": server_time.isoformat(),
        "server_time_local": server_time_local.isoformat(),
        "server_platform": platform.system(),
        "transactions": []
    }
    
    for t in transactions:
        transaction_date = t.get("date")
        debug_info["transactions"].append({
            "id": t["_id"],
            "description": t.get("description", "N/A"),
            "amount": t["amount"],
            "type": t["type"],
            "date_raw": str(transaction_date),
            "date_type": str(type(transaction_date)),
            "date_timezone": str(transaction_date.tzinfo) if hasattr(transaction_date, 'tzinfo') else "No tzinfo",
            "date_iso": transaction_date.isoformat() if hasattr(transaction_date, 'isoformat') else str(transaction_date),
            "created_at": t.get("created_at").isoformat() if t.get("created_at") else "N/A"
        })
    
    # Also check what "today" means in different contexts
    from ai_chatbot import FinancialDataProcessor
    processor = FinancialDataProcessor(current_user["_id"])
    today_query = {"user_id": current_user["_id"], "date": {"$gte": datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)}}
    today_transactions = list(transactions_collection.find(today_query))
    
    debug_info["today_query"] = {
        "query_date_start": datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0).isoformat(),
        "matching_transactions_count": len(today_transactions),
        "matching_transaction_ids": [t["_id"] for t in today_transactions]
    }
    
    return debug_info


# ==================== FINANCIAL GOALS ====================

@app.post("/api/goals", response_model=GoalResponse)
async def create_goal(
    goal_data: GoalCreate,
    current_user: dict = Depends(get_current_user)
):
    """Create a new financial goal"""
    # Check if user has sufficient balance for initial contribution
    balance_data = await get_balance(current_user)
    available_balance = balance_data["balance"]
    
    # Get total already allocated to goals
    allocated_pipeline = [
        {"$match": {"user_id": current_user["_id"], "status": "active"}},
        {"$group": {"_id": None, "total": {"$sum": "$current_amount"}}}
    ]
    allocated_result = list(goals_collection.aggregate(allocated_pipeline))
    total_allocated = allocated_result[0]["total"] if allocated_result else 0
    
    available_for_goals = available_balance - total_allocated
    
    if goal_data.initial_contribution > available_for_goals:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Insufficient balance. Available for goals: ${available_for_goals:.2f}"
        )
    
    goal_id = str(uuid.uuid4())
    now = datetime.now(UTC)
    
    current_amount = goal_data.initial_contribution if goal_data.initial_contribution else 0.0
    progress = (current_amount / goal_data.target_amount * 100) if goal_data.target_amount > 0 else 0
    
    # Check if goal is already achieved
    status_value = GoalStatus.ACHIEVED if current_amount >= goal_data.target_amount else GoalStatus.ACTIVE
    achieved_at = now if status_value == GoalStatus.ACHIEVED else None
    
    new_goal = {
        "_id": goal_id,
        "user_id": current_user["_id"],
        "name": goal_data.name,
        "target_amount": goal_data.target_amount,
        "current_amount": current_amount,
        "target_date": goal_data.target_date.replace(tzinfo=timezone.utc) if goal_data.target_date and goal_data.target_date.tzinfo is None else goal_data.target_date,
        "goal_type": goal_data.goal_type.value,
        "status": status_value.value,
        "created_at": now,
        "updated_at": now,
        "achieved_at": achieved_at
    }
    
    result = goals_collection.insert_one(new_goal)
    if not result.inserted_id:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create goal"
        )
    
    refresh_ai_data_silent(current_user["_id"])
    
    return GoalResponse(
        id=goal_id,
        user_id=current_user["_id"],
        name=goal_data.name,
        target_amount=goal_data.target_amount,
        current_amount=current_amount,
        target_date=goal_data.target_date,
        goal_type=goal_data.goal_type,
        status=status_value,
        progress_percentage=progress,
        created_at=now,
        updated_at=now,
        achieved_at=achieved_at
    )


@app.get("/api/goals", response_model=List[GoalResponse])
async def get_goals(
    current_user: dict = Depends(get_current_user),
    status_filter: Optional[GoalStatus] = None
):
    """Get all user goals"""
    query = {"user_id": current_user["_id"]}
    
    if status_filter:
        query["status"] = status_filter.value
    
    goals = list(goals_collection.find(query).sort("created_at", -1))
    
    return [
        GoalResponse(
            id=g["_id"],
            user_id=g["user_id"],
            name=g["name"],
            target_amount=g["target_amount"],
            current_amount=g["current_amount"],
            target_date=g.get("target_date"),
            goal_type=GoalType(g["goal_type"]),
            status=GoalStatus(g["status"]),
            progress_percentage=(g["current_amount"] / g["target_amount"] * 100) if g["target_amount"] > 0 else 0,
            created_at=g["created_at"],
            updated_at=g.get("updated_at", g["created_at"]),
            achieved_at=g.get("achieved_at")
        )
        for g in goals
    ]


@app.get("/api/goals/summary", response_model=GoalsSummary)
async def get_goals_summary(current_user: dict = Depends(get_current_user)):
    """Get summary of all goals"""
    goals = list(goals_collection.find({"user_id": current_user["_id"]}))
    
    total_goals = len(goals)
    active_goals = len([g for g in goals if g["status"] == "active"])
    achieved_goals = len([g for g in goals if g["status"] == "achieved"])
    total_allocated = sum(g["current_amount"] for g in goals if g["status"] == "active")
    total_target = sum(g["target_amount"] for g in goals if g["status"] == "active")
    overall_progress = (total_allocated / total_target * 100) if total_target > 0 else 0
    
    return GoalsSummary(
        total_goals=total_goals,
        active_goals=active_goals,
        achieved_goals=achieved_goals,
        total_allocated=total_allocated,
        total_target=total_target,
        overall_progress=overall_progress
    )


@app.get("/api/goals/{goal_id}", response_model=GoalResponse)
async def get_goal(
    goal_id: str = Path(...),
    current_user: dict = Depends(get_current_user)
):
    """Get a specific goal"""
    goal = goals_collection.find_one({
        "_id": goal_id,
        "user_id": current_user["_id"]
    })
    
    if not goal:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Goal not found"
        )
    
    return GoalResponse(
        id=goal["_id"],
        user_id=goal["user_id"],
        name=goal["name"],
        target_amount=goal["target_amount"],
        current_amount=goal["current_amount"],
        target_date=goal.get("target_date"),
        goal_type=GoalType(goal["goal_type"]),
        status=GoalStatus(goal["status"]),
        progress_percentage=(goal["current_amount"] / goal["target_amount"] * 100) if goal["target_amount"] > 0 else 0,
        created_at=goal["created_at"],
        updated_at=goal.get("updated_at", goal["created_at"]),
        achieved_at=goal.get("achieved_at")
    )


@app.put("/api/goals/{goal_id}", response_model=GoalResponse)
async def update_goal(
    goal_id: str = Path(...),
    goal_data: GoalUpdate = ...,
    current_user: dict = Depends(get_current_user)
):
    """Update a goal's details (name, target amount, target date, type)"""
    goal = goals_collection.find_one({
        "_id": goal_id,
        "user_id": current_user["_id"]
    })
    
    if not goal:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Goal not found"
        )
    
    update_data = {"updated_at": datetime.now(UTC)}
    
    if goal_data.name is not None:
        update_data["name"] = goal_data.name
    if goal_data.target_amount is not None:
        update_data["target_amount"] = goal_data.target_amount
        # Recalculate status if target amount changed
        current_amount = goal["current_amount"]
        if current_amount >= goal_data.target_amount:
            update_data["status"] = GoalStatus.ACHIEVED.value
            if not goal.get("achieved_at"):
                update_data["achieved_at"] = datetime.now(UTC)
        else:
            update_data["status"] = GoalStatus.ACTIVE.value
            update_data["achieved_at"] = None
    if goal_data.target_date is not None:
        update_data["target_date"] = goal_data.target_date
    if goal_data.goal_type is not None:
        update_data["goal_type"] = goal_data.goal_type.value
    
    goals_collection.update_one(
        {"_id": goal_id},
        {"$set": update_data}
    )
    
    updated_goal = goals_collection.find_one({"_id": goal_id})
    refresh_ai_data_silent(current_user["_id"])
    
    return GoalResponse(
        id=updated_goal["_id"],
        user_id=updated_goal["user_id"],
        name=updated_goal["name"],
        target_amount=updated_goal["target_amount"],
        current_amount=updated_goal["current_amount"],
        target_date=updated_goal.get("target_date"),
        goal_type=GoalType(updated_goal["goal_type"]),
        status=GoalStatus(updated_goal["status"]),
        progress_percentage=(updated_goal["current_amount"] / updated_goal["target_amount"] * 100) if updated_goal["target_amount"] > 0 else 0,
        created_at=updated_goal["created_at"],
        updated_at=updated_goal["updated_at"],
        achieved_at=updated_goal.get("achieved_at")
    )


@app.post("/api/goals/{goal_id}/contribute", response_model=GoalResponse)
async def contribute_to_goal(
    goal_id: str = Path(...),
    contribution: GoalContribution = ...,
    current_user: dict = Depends(get_current_user)
):
    """Add or reduce amount from a goal"""
    goal = goals_collection.find_one({
        "_id": goal_id,
        "user_id": current_user["_id"]
    })
    
    if not goal:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Goal not found"
        )
    
    if goal["status"] == GoalStatus.ACHIEVED.value and contribution.amount > 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot add funds to an achieved goal"
        )
    
    # Calculate what the new amount would be
    new_amount = goal["current_amount"] + contribution.amount
    
    # For adding money to goal
    if contribution.amount > 0:
        # Check if adding this amount would exceed the target
        if new_amount > goal["target_amount"]:
            max_can_add = goal["target_amount"] - goal["current_amount"]
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Cannot exceed target amount. Maximum you can add: ${max_can_add:.2f}"
            )
        
        # Check available balance
        balance_data = await get_balance(current_user)
        available_balance = balance_data["balance"]
        
        # Get total already allocated to other active goals
        allocated_pipeline = [
            {"$match": {"user_id": current_user["_id"], "status": "active", "_id": {"$ne": goal_id}}},
            {"$group": {"_id": None, "total": {"$sum": "$current_amount"}}}
        ]
        allocated_result = list(goals_collection.aggregate(allocated_pipeline))
        total_allocated = allocated_result[0]["total"] if allocated_result else 0
        
        available_for_goals = available_balance - total_allocated
        
        if contribution.amount > available_for_goals:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Insufficient balance. Available for goals: ${available_for_goals:.2f}"
            )
    
    # For reducing money from goal
    if contribution.amount < 0:
        if abs(contribution.amount) > goal["current_amount"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Cannot reduce more than current amount: ${goal['current_amount']:.2f}"
            )
    
    # Determine new status
    new_status = goal["status"]
    achieved_at = goal.get("achieved_at")
    
    if new_amount >= goal["target_amount"] and new_status == GoalStatus.ACTIVE.value:
        new_status = GoalStatus.ACHIEVED.value
        achieved_at = datetime.now(UTC)
    elif new_amount < goal["target_amount"] and new_status == GoalStatus.ACHIEVED.value:
        new_status = GoalStatus.ACTIVE.value
        achieved_at = None
    
    goals_collection.update_one(
        {"_id": goal_id},
        {
            "$set": {
                "current_amount": new_amount,
                "status": new_status,
                "updated_at": datetime.now(UTC),
                "achieved_at": achieved_at
            }
        }
    )
    
    updated_goal = goals_collection.find_one({"_id": goal_id})
    refresh_ai_data_silent(current_user["_id"])
    
    return GoalResponse(
        id=updated_goal["_id"],
        user_id=updated_goal["user_id"],
        name=updated_goal["name"],
        target_amount=updated_goal["target_amount"],
        current_amount=updated_goal["current_amount"],
        target_date=updated_goal.get("target_date"),
        goal_type=GoalType(updated_goal["goal_type"]),
        status=GoalStatus(updated_goal["status"]),
        progress_percentage=(updated_goal["current_amount"] / updated_goal["target_amount"] * 100) if updated_goal["target_amount"] > 0 else 0,
        created_at=updated_goal["created_at"],
        updated_at=updated_goal["updated_at"],
        achieved_at=updated_goal.get("achieved_at")
    )


@app.delete("/api/goals/{goal_id}")
async def delete_goal(
    goal_id: str = Path(...),
    current_user: dict = Depends(get_current_user)
):
    """Delete a goal and return its amount to balance"""
    goal = goals_collection.find_one({
        "_id": goal_id,
        "user_id": current_user["_id"]
    })
    
    if not goal:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Goal not found"
        )
    
    returned_amount = goal["current_amount"]
    
    result = goals_collection.delete_one({
        "_id": goal_id,
        "user_id": current_user["_id"]
    })
    
    if result.deleted_count == 0:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete goal"
        )
    
    refresh_ai_data_silent(current_user["_id"])
    
    return {
        "message": "Goal deleted successfully",
        "returned_amount": returned_amount
    }
    

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
async def get_insights(current_user: dict = Depends(get_current_user)):
    """Get AI-generated financial insights (cached if data unchanged)"""
    try:
        # Calculate current data hash
        current_hash = calculate_data_hash(current_user["_id"])
        
        # Check if we have cached insights
        cached_insight = insights_collection.find_one({
            "user_id": current_user["_id"],
            "data_hash": current_hash
        })
        
        if cached_insight:
            print(f"✅ Returning cached insights for user {current_user['_id']}")
            return InsightResponse(
                id=cached_insight["_id"],
                user_id=cached_insight["user_id"],
                content=cached_insight["content"],
                generated_at=cached_insight["generated_at"],
                data_hash=cached_insight["data_hash"],
                expires_at=cached_insight.get("expires_at")
            )
        
        # Generate new insights
        print(f"🔄 Generating new insights for user {current_user['_id']}")
        
        if financial_chatbot is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="AI service is currently unavailable"
            )
        
        insights_content = await financial_chatbot.generate_insights(current_user["_id"])
        
        # Save to database
        insight_id = str(uuid.uuid4())
        now = datetime.now(UTC)
        
        new_insight = {
            "_id": insight_id,
            "user_id": current_user["_id"],
            "content": insights_content,
            "generated_at": now,
            "data_hash": current_hash,
            "expires_at": None  # Never expires, only regenerates on data change
        }
        
        # Delete old insights for this user
        insights_collection.delete_many({"user_id": current_user["_id"]})
        
        # Insert new insight
        insights_collection.insert_one(new_insight)
        
        print(f"✅ New insights generated and cached")
        
        return InsightResponse(
            id=insight_id,
            user_id=current_user["_id"],
            content=insights_content,
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
async def delete_insights(current_user: dict = Depends(get_current_user)):
    """Force regeneration of insights by deleting cached ones"""
    try:
        result = insights_collection.delete_many({"user_id": current_user["_id"]})
        return {
            "message": f"Deleted {result.deleted_count} cached insights",
            "deleted_count": result.deleted_count
        }
    except Exception as e:
        print(f"Error deleting insights: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete insights"
        )
        
        
@app.post("/api/insights/regenerate", response_model=InsightResponse)
async def regenerate_insights(current_user: dict = Depends(get_current_user)):
    """Force regenerate insights regardless of data changes"""
    try:
        insights_collection.delete_many({"user_id": current_user["_id"]})
        
        current_hash = calculate_data_hash(current_user["_id"])
        
        print(f"🔄 Force regenerating insights for user {current_user['_id']}")
        
        if financial_chatbot is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="AI service is currently unavailable"
            )
        
        insights_content = await financial_chatbot.generate_insights(current_user["_id"])
        
        insight_id = str(uuid.uuid4())
        now = datetime.now(UTC)
        
        new_insight = {
            "_id": insight_id,
            "user_id": current_user["_id"],
            "content": insights_content,
            "generated_at": now,
            "data_hash": current_hash,
            "expires_at": None
        }
        
        insights_collection.insert_one(new_insight)
        
        print(f"✅ Insights regenerated successfully")
        
        return InsightResponse(
            id=insight_id,
            user_id=current_user["_id"],
            content=insights_content,
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
        
        
        
# ==================== FINANCIAL REPORTS ====================

def calculate_report_dates(period: ReportPeriod, start_date: Optional[datetime] = None, end_date: Optional[datetime] = None):
    """Calculate start and end dates based on period"""
    now = datetime.now(UTC)
    
    if period == ReportPeriod.WEEK:
        start = now - timedelta(days=now.weekday())
        start = start.replace(hour=0, minute=0, second=0, microsecond=0)
        end = start + timedelta(days=6, hours=23, minutes=59, seconds=59)
    elif period == ReportPeriod.MONTH:
        start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        if now.month == 12:
            end = now.replace(month=12, day=31, hour=23, minute=59, second=59)
        else:
            end = (now.replace(month=now.month + 1, day=1) - timedelta(days=1)).replace(hour=23, minute=59, second=59)
    elif period == ReportPeriod.YEAR:
        start = now.replace(month=1, day=1, hour=0, minute=0, second=0, microsecond=0)
        end = now.replace(month=12, day=31, hour=23, minute=59, second=59)
    else:  # CUSTOM
        if not start_date or not end_date:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Start date and end date are required for custom period"
            )
        # Ensure dates are in UTC
        if start_date.tzinfo is None:
            start = start_date.replace(tzinfo=UTC, hour=0, minute=0, second=0, microsecond=0)
        else:
            start = start_date.astimezone(UTC).replace(hour=0, minute=0, second=0, microsecond=0)
            
        if end_date.tzinfo is None:
            end = end_date.replace(tzinfo=UTC, hour=23, minute=59, second=59, microsecond=999999)
        else:
            end = end_date.astimezone(UTC).replace(hour=23, minute=59, second=59, microsecond=999999)
    
    return start, end


@app.post("/api/reports/generate", response_model=FinancialReport)
async def generate_report(
    report_request: ReportRequest,
    current_user: dict = Depends(get_current_user)
):
    """Generate a financial report for the specified period"""
    try:
        start_date, end_date = calculate_report_dates(
            report_request.period,
            report_request.start_date,
            report_request.end_date
        )
        
        # Fetch all transactions in the period
        transactions = list(transactions_collection.find({
            "user_id": current_user["_id"],
            "date": {"$gte": start_date, "$lte": end_date}
        }))
        
        # Calculate metrics
        inflows = [t for t in transactions if t["type"] == "inflow"]
        outflows = [t for t in transactions if t["type"] == "outflow"]
        
        total_inflow = sum(t["amount"] for t in inflows)
        total_outflow = sum(t["amount"] for t in outflows)
        net_balance = total_inflow - total_outflow
        
        # Calculate category breakdowns for inflows
        inflow_categories = {}
        for t in inflows:
            cat = t["main_category"]
            if cat not in inflow_categories:
                inflow_categories[cat] = {"amount": 0, "count": 0}
            inflow_categories[cat]["amount"] += t["amount"]
            inflow_categories[cat]["count"] += 1
        
        inflow_by_category = [
            CategoryBreakdown(
                category=cat,
                amount=data["amount"],
                percentage=(data["amount"] / total_inflow * 100) if total_inflow > 0 else 0,
                transaction_count=data["count"]
            )
            for cat, data in inflow_categories.items()
        ]
        inflow_by_category.sort(key=lambda x: x.amount, reverse=True)
        
        # Calculate category breakdowns for outflows
        outflow_categories = {}
        for t in outflows:
            cat = t["main_category"]
            if cat not in outflow_categories:
                outflow_categories[cat] = {"amount": 0, "count": 0}
            outflow_categories[cat]["amount"] += t["amount"]
            outflow_categories[cat]["count"] += 1
        
        outflow_by_category = [
            CategoryBreakdown(
                category=cat,
                amount=data["amount"],
                percentage=(data["amount"] / total_outflow * 100) if total_outflow > 0 else 0,
                transaction_count=data["count"]
            )
            for cat, data in outflow_categories.items()
        ]
        outflow_by_category.sort(key=lambda x: x.amount, reverse=True)
        
        # Get goals data
        goals = list(goals_collection.find({"user_id": current_user["_id"]}))
        goals_progress = [
            GoalProgress(
                goal_id=g["_id"],
                name=g["name"],
                target_amount=g["target_amount"],
                current_amount=g["current_amount"],
                progress_percentage=(g["current_amount"] / g["target_amount"] * 100) if g["target_amount"] > 0 else 0,
                status=g["status"]
            )
            for g in goals
        ]
        
        total_allocated = sum(g["current_amount"] for g in goals)
        
        # Calculate daily averages
        days_in_period = (end_date - start_date).days + 1
        avg_daily_inflow = total_inflow / days_in_period if days_in_period > 0 else 0
        avg_daily_outflow = total_outflow / days_in_period if days_in_period > 0 else 0
        
        # Top categories
        top_income = inflow_by_category[0].category if inflow_by_category else None
        top_expense = outflow_by_category[0].category if outflow_by_category else None
        
        report = FinancialReport(
            period=report_request.period,
            start_date=start_date,
            end_date=end_date,
            total_inflow=total_inflow,
            total_outflow=total_outflow,
            net_balance=net_balance,
            inflow_by_category=inflow_by_category,
            outflow_by_category=outflow_by_category,
            goals=goals_progress,
            total_allocated_to_goals=total_allocated,
            total_transactions=len(transactions),
            inflow_count=len(inflows),
            outflow_count=len(outflows),
            top_income_category=top_income,
            top_expense_category=top_expense,
            average_daily_inflow=avg_daily_inflow,
            average_daily_outflow=avg_daily_outflow,
            generated_at=datetime.now(UTC)
        )
        
        return report
        
    except Exception as e:
        print(f"Error generating report: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate report: {str(e)}"
        )


@app.post("/api/reports/download")
async def download_report_pdf(
    report_request: ReportRequest,
    current_user: dict = Depends(get_current_user)
):
    """Generate and download a financial report as PDF"""
    try:
        # Generate the report data
        start_date, end_date = calculate_report_dates(
            report_request.period,
            report_request.start_date,
            report_request.end_date
        )
        
        # Fetch all transactions in the period
        transactions = list(transactions_collection.find({
            "user_id": current_user["_id"],
            "date": {"$gte": start_date, "$lte": end_date}
        }))
        
        # Calculate metrics (same as generate_report)
        inflows = [t for t in transactions if t["type"] == "inflow"]
        outflows = [t for t in transactions if t["type"] == "outflow"]
        
        total_inflow = sum(t["amount"] for t in inflows)
        total_outflow = sum(t["amount"] for t in outflows)
        net_balance = total_inflow - total_outflow
        
        # Calculate category breakdowns for inflows
        inflow_categories = {}
        for t in inflows:
            cat = t["main_category"]
            if cat not in inflow_categories:
                inflow_categories[cat] = {"amount": 0, "count": 0}
            inflow_categories[cat]["amount"] += t["amount"]
            inflow_categories[cat]["count"] += 1
        
        inflow_by_category = [
            CategoryBreakdown(
                category=cat,
                amount=data["amount"],
                percentage=(data["amount"] / total_inflow * 100) if total_inflow > 0 else 0,
                transaction_count=data["count"]
            )
            for cat, data in inflow_categories.items()
        ]
        inflow_by_category.sort(key=lambda x: x.amount, reverse=True)
        
        # Calculate category breakdowns for outflows
        outflow_categories = {}
        for t in outflows:
            cat = t["main_category"]
            if cat not in outflow_categories:
                outflow_categories[cat] = {"amount": 0, "count": 0}
            outflow_categories[cat]["amount"] += t["amount"]
            outflow_categories[cat]["count"] += 1
        
        outflow_by_category = [
            CategoryBreakdown(
                category=cat,
                amount=data["amount"],
                percentage=(data["amount"] / total_outflow * 100) if total_outflow > 0 else 0,
                transaction_count=data["count"]
            )
            for cat, data in outflow_categories.items()
        ]
        outflow_by_category.sort(key=lambda x: x.amount, reverse=True)
        
        # Get goals data
        goals = list(goals_collection.find({"user_id": current_user["_id"]}))
        goals_progress = [
            GoalProgress(
                goal_id=g["_id"],
                name=g["name"],
                target_amount=g["target_amount"],
                current_amount=g["current_amount"],
                progress_percentage=(g["current_amount"] / g["target_amount"] * 100) if g["target_amount"] > 0 else 0,
                status=g["status"]
            )
            for g in goals
        ]
        
        total_allocated = sum(g["current_amount"] for g in goals)
        
        # Calculate daily averages
        days_in_period = (end_date - start_date).days + 1
        avg_daily_inflow = total_inflow / days_in_period if days_in_period > 0 else 0
        avg_daily_outflow = total_outflow / days_in_period if days_in_period > 0 else 0
        
        # Top categories
        top_income = inflow_by_category[0].category if inflow_by_category else None
        top_expense = outflow_by_category[0].category if outflow_by_category else None
        
        report = FinancialReport(
            period=report_request.period,
            start_date=start_date,
            end_date=end_date,
            total_inflow=total_inflow,
            total_outflow=total_outflow,
            net_balance=net_balance,
            inflow_by_category=inflow_by_category,
            outflow_by_category=outflow_by_category,
            goals=goals_progress,
            total_allocated_to_goals=total_allocated,
            total_transactions=len(transactions),
            inflow_count=len(inflows),
            outflow_count=len(outflows),
            top_income_category=top_income,
            top_expense_category=top_expense,
            average_daily_inflow=avg_daily_inflow,
            average_daily_outflow=avg_daily_outflow,
            generated_at=datetime.now(UTC)
        )
        
        # Generate PDF with user's timezone offset (if provided)
        user_timezone_offset = report_request.timezone_offset if hasattr(report_request, 'timezone_offset') and report_request.timezone_offset is not None else 0
        pdf_buffer = generate_financial_report_pdf(report, current_user["name"], user_timezone_offset)
        
        # Create filename
        period_name = report_request.period.value
        filename = f"financial_report_{period_name}_{start_date.strftime('%Y%m%d')}_{end_date.strftime('%Y%m%d')}.pdf"
        
        return StreamingResponse(
            pdf_buffer,
            media_type="application/pdf",
            headers={"Content-Disposition": f"attachment; filename={filename}"}
        )
        
    except Exception as e:
        print(f"Error generating PDF: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate PDF: {str(e)}"
        )
        
        
@app.post("/api/transactions/transcribe-audio")
async def transcribe_audio(
    audio: UploadFile = File(...),
    current_user: dict = Depends(get_current_user)
):
    """Transcribe audio to text using OpenAI Whisper"""
    try:
        if not settings.OPENAI_API_KEY:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="OpenAI API key not configured"
            )
        
        # Read audio file
        audio_data = await audio.read()
        
        # Save temporarily
        import tempfile
        with tempfile.NamedTemporaryFile(delete=False, suffix='.wav') as temp_audio:
            temp_audio.write(audio_data)
            temp_path = temp_audio.name
        
        try:
            from openai import AsyncOpenAI
            client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
            
            with open(temp_path, 'rb') as audio_file:
                transcript = await client.audio.transcriptions.create(
                    model="whisper-1",
                    file=audio_file,
                    language="en"
                )
            
            return {"transcription": transcript.text}
        finally:
            # Clean up temp file
            import os
            os.unlink(temp_path)
            
    except Exception as e:
        print(f"Transcription error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to transcribe audio: {str(e)}"
        )


@app.post("/api/transactions/extract-from-text", response_model=TransactionExtraction)
async def extract_transaction_from_text(
    request: TextExtractionRequest,
    current_user: dict = Depends(get_current_user)
):
    """Extract transaction details from text using GPT-4"""
    try:
        if not settings.OPENAI_API_KEY:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="OpenAI API key not configured"
            )
        
        # Get user's categories
        inflow_cats = categories_collection.find_one({"_id": "inflow"})
        outflow_cats = categories_collection.find_one({"_id": "outflow"})
        
        categories_text = "AVAILABLE CATEGORIES:\n\nINFLOW:\n"
        if inflow_cats:
            for cat in inflow_cats["categories"]:
                categories_text += f"- {cat['main_category']}: {', '.join(cat['sub_categories'])}\n"
        
        categories_text += "\nOUTFLOW:\n"
        if outflow_cats:
            for cat in outflow_cats["categories"]:
                categories_text += f"- {cat['main_category']}: {', '.join(cat['sub_categories'])}\n"
        
        system_prompt = f"""You are a financial transaction extraction assistant. Extract transaction details from user text.

{categories_text}

RULES:
1. Determine if it's 'inflow' (income) or 'outflow' (expense)
2. Select the most appropriate main_category and sub_category from the list above
3. Extract the amount as a positive number
4. Determine the date (default to today if not specified: {datetime.now(UTC).strftime('%Y-%m-%d')})
5. Extract any description/notes
6. Provide a confidence score (0.0-1.0) based on clarity
7. Provide brief reasoning for your categorization

Respond in JSON format:
{{
    "type": "inflow" or "outflow",
    "main_category": "selected main category",
    "sub_category": "selected sub category",
    "date": "YYYY-MM-DD",
    "description": "optional description",
    "amount": 123.45,
    "confidence": 0.95,
    "reasoning": "why you chose these categories"
}}"""

        from openai import AsyncOpenAI
        client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
        
        response = await client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": f"Extract transaction from: {request.text}"}
            ],
            response_format={"type": "json_object"},
            temperature=0.3
        )
        
        result = json.loads(response.choices[0].message.content)
        
        # Validate and parse
        return TransactionExtraction(
            type=result["type"],
            main_category=result["main_category"],
            sub_category=result["sub_category"],
            date=datetime.fromisoformat(result["date"]).replace(tzinfo=UTC),
            description=result.get("description"),
            amount=float(result["amount"]),
            confidence=float(result["confidence"]),
            reasoning=result.get("reasoning")
        )
        
    except Exception as e:
        print(f"Extraction error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to extract transaction: {str(e)}"
        )


@app.post("/api/transactions/extract-from-image", response_model=TransactionExtraction)
async def extract_transaction_from_image(
    image: UploadFile = File(...),
    current_user: dict = Depends(get_current_user)
):
    """Extract transaction details from receipt image using GPT-4 Vision"""
    try:
        if not settings.OPENAI_API_KEY:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="OpenAI API key not configured"
            )
        
        # Read and encode image
        image_data = await image.read()
        base64_image = base64.b64encode(image_data).decode('utf-8')
        
        # Get user's categories
        inflow_cats = categories_collection.find_one({"_id": "inflow"})
        outflow_cats = categories_collection.find_one({"_id": "outflow"})
        
        categories_text = "AVAILABLE CATEGORIES:\n\nINFLOW:\n"
        if inflow_cats:
            for cat in inflow_cats["categories"]:
                categories_text += f"- {cat['main_category']}: {', '.join(cat['sub_categories'])}\n"
        
        categories_text += "\nOUTFLOW:\n"
        if outflow_cats:
            for cat in outflow_cats["categories"]:
                categories_text += f"- {cat['main_category']}: {', '.join(cat['sub_categories'])}\n"
        
        system_prompt = f"""You are a financial receipt analyzer. Extract transaction details from receipt images.

{categories_text}

RULES:
1. Identify if it's 'inflow' or 'outflow' (receipts are usually outflow)
2. Select the most appropriate category from the list above based on merchant/items
3. Extract the total amount
4. Extract the date from receipt (default to today if not visible: {datetime.now(UTC).strftime('%Y-%m-%d')})
5. Create a brief description including merchant name
6. Provide confidence score (0.0-1.0)
7. Explain your reasoning

Respond in JSON format:
{{
    "type": "inflow" or "outflow",
    "main_category": "selected main category",
    "sub_category": "selected sub category",
    "date": "YYYY-MM-DD",
    "description": "merchant name and brief description",
    "amount": 123.45,
    "confidence": 0.95,
    "reasoning": "what you saw on the receipt"
}}"""

        from openai import AsyncOpenAI
        client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
        
        response = await client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {
                    "role": "system", 
                    "content": system_prompt
                },
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": "Analyze this receipt and extract transaction details:"
                        },
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/jpeg;base64,{base64_image}"
                            }
                        }
                    ]
                }
            ],
            response_format={"type": "json_object"},
            max_tokens=1000,
            temperature=0.3
        )
        
        result = json.loads(response.choices[0].message.content)
        
        return TransactionExtraction(
            type=result["type"],
            main_category=result["main_category"],
            sub_category=result["sub_category"],
            date=datetime.fromisoformat(result["date"]).replace(tzinfo=UTC),
            description=result.get("description"),
            amount=float(result["amount"]),
            confidence=float(result["confidence"]),
            reasoning=result.get("reasoning")
        )
        
    except Exception as e:
        print(f"Image extraction error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to extract from image: {str(e)}"
        )



# ==================== ROOT ====================

@app.get("/")
async def root():
    return {"message": "Flow Finance API with AI Assistant is running"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)