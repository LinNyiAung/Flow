import asyncio
import json
import uuid
from datetime import datetime, timedelta, UTC, timezone
from typing import List, Optional

from fastapi import FastAPI, HTTPException, status, Depends, Query, Path
from fastapi.responses import StreamingResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware

from models import (
    UserCreate, UserLogin, UserResponse, Token,
    TransactionCreate, TransactionResponse, CategoryResponse, TransactionType,
    TransactionUpdate
)
from chat_models import (
    ChatRequest, ChatResponse, ChatMessage, MessageRole,
)
from database import (
    users_collection, transactions_collection, categories_collection,
    chat_sessions_collection
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
    limit: int = Query(default=50, le=100),
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
    """Get user's financial balance"""
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

    return {
        "balance": total_inflow - total_outflow,
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



# ==================== ROOT ====================

@app.get("/")
async def root():
    return {"message": "Flow Finance API with AI Assistant is running"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)