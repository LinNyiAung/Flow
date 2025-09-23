import asyncio
import json
from fastapi import FastAPI, HTTPException, status, Depends, Query, Path
from fastapi.responses import StreamingResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime, timedelta, UTC
from typing import List, Optional
import uuid

# Import existing models
from models import (
    UserCreate, UserLogin, UserResponse, Token,
    TransactionCreate, TransactionResponse, CategoryResponse, TransactionType,
    TransactionUpdate
)

# Import new chat models
from chat_models import (
    ChatRequest, ChatResponse, ChatMessage, MessageRole,
    InsightsResponse, ChatSession
)

# Import database collections
from database import (
    users_collection, transactions_collection, categories_collection,
    chat_sessions_collection  # New collection
)

# Import auth functions
from auth import get_password_hash, verify_password, create_access_token, verify_token

# Import AI chatbot
from ai_chatbot import financial_chatbot

from config import settings

app = FastAPI(title="Flow Finance API", version="1.0.0")

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure this properly in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

security = HTTPBearer()

def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    token = credentials.credentials
    email = verify_token(token)
    user = users_collection.find_one({"email": email})
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found"
        )
    return user

# Authentication endpoints (keeping existing ones)
@app.post("/api/auth/register", response_model=Token)
async def register(user_data: UserCreate):
    existing_user = users_collection.find_one({"email": user_data.email})
    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered"
        )

    hashed_password = get_password_hash(user_data.password)
    user_id = str(uuid.uuid4())
    new_user = {
        "_id": user_id,
        "name": user_data.name,
        "email": user_data.email,
        "password": hashed_password,
        "created_at": datetime.now(UTC)
    }

    users_collection.insert_one(new_user)

    access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user_data.email}, expires_delta=access_token_expires
    )

    user_response = UserResponse(
        id=user_id,
        name=user_data.name,
        email=user_data.email,
        created_at=new_user["created_at"]
    )

    return Token(access_token=access_token, token_type="bearer", user=user_response)

@app.post("/api/auth/login", response_model=Token)
async def login(user_credentials: UserLogin):
    user = users_collection.find_one({"email": user_credentials.email})
    if not user or not verify_password(user_credentials.password, user["password"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password"
        )

    access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user["email"]}, expires_delta=access_token_expires
    )

    user_response = UserResponse(
        id=user["_id"],
        name=user["name"],
        email=user["email"],
        created_at=user["created_at"]
    )

    return Token(access_token=access_token, token_type="bearer", user=user_response)

@app.get("/api/auth/me", response_model=UserResponse)
async def get_current_user_info(current_user: dict = Depends(get_current_user)):
    return UserResponse(
        id=current_user["_id"],
        name=current_user["name"],
        email=current_user["email"],
        created_at=current_user["created_at"]
    )

# Transaction CRUD endpoints (keeping all existing ones)
@app.post("/api/transactions", response_model=TransactionResponse)
async def create_transaction(
    transaction_data: TransactionCreate,
    current_user: dict = Depends(get_current_user)
):
    transaction_id = str(uuid.uuid4())
    new_transaction = {
        "_id": transaction_id,
        "user_id": current_user["_id"],
        "type": transaction_data.type.value,
        "main_category": transaction_data.main_category,
        "sub_category": transaction_data.sub_category,
        "date": transaction_data.date,
        "description": transaction_data.description,
        "amount": transaction_data.amount,
        "created_at": datetime.now(UTC),
        "updated_at": datetime.now(UTC)
    }

    transactions_collection.insert_one(new_transaction)
    
    # Refresh user's AI data after adding transaction
    try:
        financial_chatbot.refresh_user_data(current_user["_id"])
    except Exception as e:
        print(f"Error refreshing AI data: {e}")  # Log error but don't fail the transaction

    return TransactionResponse(
        id=transaction_id,
        user_id=current_user["_id"],
        type=transaction_data.type,
        main_category=transaction_data.main_category,
        sub_category=transaction_data.sub_category,
        date=transaction_data.date,
        description=transaction_data.description,
        amount=transaction_data.amount,
        created_at=new_transaction["created_at"],
        updated_at=new_transaction["updated_at"]
    )

@app.get("/api/transactions", response_model=List[TransactionResponse])
async def get_transactions(
    current_user: dict = Depends(get_current_user),
    limit: int = Query(default=50, le=100),
    skip: int = Query(default=0, ge=0),
    transaction_type: Optional[TransactionType] = None,
    start_date: Optional[datetime] = Query(default=None, description="Start date for filtering (YYYY-MM-DD)"),
    end_date: Optional[datetime] = Query(default=None, description="End date for filtering (YYYY-MM-DD)")
):
    query = {"user_id": current_user["_id"]}
    
    # Add transaction type filter if provided
    if transaction_type:
        query["type"] = transaction_type.value
    
    # Add date range filters if provided
    if start_date or end_date:
        date_filter = {}
        if start_date:
            date_filter["$gte"] = start_date
        if end_date:
            # Add one day to end_date to include transactions on that day
            end_date_inclusive = end_date.replace(hour=23, minute=59, second=59, microsecond=999999)
            date_filter["$lte"] = end_date_inclusive
        
        if date_filter:
            query["date"] = date_filter

    # Sort by transaction date, descending (latest first)
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
    transaction = transactions_collection.find_one({
        "_id": transaction_id,
        "user_id": current_user["_id"]
    })

    if not transaction:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transaction not found"
        )

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
    existing_transaction = transactions_collection.find_one({
        "_id": transaction_id,
        "user_id": current_user["_id"]
    })

    if not existing_transaction:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transaction not found"
        )

    update_data = {"updated_at": datetime.now(UTC)}

    if transaction_data.type is not None:
        update_data["type"] = transaction_data.type.value
    if transaction_data.main_category is not None:
        update_data["main_category"] = transaction_data.main_category
    if transaction_data.sub_category is not None:
        update_data["sub_category"] = transaction_data.sub_category
    if transaction_data.date is not None:
        update_data["date"] = transaction_data.date
    if transaction_data.description is not None:
        update_data["description"] = transaction_data.description
    if transaction_data.amount is not None:
        update_data["amount"] = transaction_data.amount

    transactions_collection.update_one(
        {"_id": transaction_id},
        {"$set": update_data}
    )

    updated_transaction = transactions_collection.find_one({"_id": transaction_id})
    
    # Refresh user's AI data after updating transaction
    try:
        financial_chatbot.refresh_user_data(current_user["_id"])
    except Exception as e:
        print(f"Error refreshing AI data: {e}")

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
    existing_transaction = transactions_collection.find_one({
        "_id": transaction_id,
        "user_id": current_user["_id"]
    })

    if not existing_transaction:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transaction not found"
        )

    result = transactions_collection.delete_one({
        "_id": transaction_id,
        "user_id": current_user["_id"]
    })

    if result.deleted_count == 0:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete transaction"
        )

    # Refresh user's AI data after deleting transaction
    try:
        financial_chatbot.refresh_user_data(current_user["_id"])
    except Exception as e:
        print(f"Error refreshing AI data: {e}")

    return {"message": "Transaction deleted successfully"}

@app.get("/api/categories/{transaction_type}", response_model=List[CategoryResponse])
async def get_categories(transaction_type: TransactionType):
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
    balance = total_inflow - total_outflow

    return {
        "balance": balance,
        "total_inflow": total_inflow,
        "total_outflow": total_outflow
    }

# NEW AI CHATBOT ENDPOINTS

@app.post("/api/chat/stream")
async def stream_chat_with_ai(
    chat_request: ChatRequest,
    current_user: dict = Depends(get_current_user)
):
    """Stream chat response from AI"""
    try:
        # Check if chatbot is initialized
        if financial_chatbot is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="AI service is currently unavailable. Please try again later."
            )
        
        # Convert chat history to dict format for the chatbot
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
                # Get streaming response from AI
                stream = financial_chatbot.stream_chat(
                    user_id=current_user["_id"],
                    message=chat_request.message,
                    chat_history=chat_history
                )
                
                # Stream each chunk
                full_response = ""
                async for chunk in stream:
                    full_response += chunk
                    data = {
                        "chunk": chunk,
                        "done": False,
                        "timestamp": datetime.now(UTC).isoformat()
                    }
                    yield f"data: {json.dumps(data)}\n\n"
                    await asyncio.sleep(0.01)  # Small delay for better UX
                
                # Send final message
                final_data = {
                    "chunk": "",
                    "done": True,
                    "full_response": full_response,
                    "timestamp": datetime.now(UTC).isoformat()
                }
                yield f"data: {json.dumps(final_data)}\n\n"
                
                # Save chat session to database (same logic as before)
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
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
            }
        )
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Stream chat endpoint error: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An error occurred while processing your message. Please try again."
        )

async def save_chat_session(user_id: str, user_message: str, ai_response: str, chat_history):
    """Helper function to save chat session"""
    try:
        session_id = str(uuid.uuid4())
        current_time = datetime.now(UTC)
        
        # Create messages list
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
        
        # Add current conversation
        messages.extend([
            {
                "role": "user",
                "content": user_message,
                "timestamp": current_time
            },
            {
                "role": "assistant",
                "content": ai_response,
                "timestamp": current_time
            }
        ])
        
        # Keep only the last N messages
        if len(messages) > settings.MAX_CHAT_HISTORY:
            messages = messages[-settings.MAX_CHAT_HISTORY:]
        
        # Save or update chat session
        existing_session = chat_sessions_collection.find_one({
            "user_id": user_id
        }, sort=[("updated_at", -1)])
        
        if existing_session:
            chat_sessions_collection.update_one(
                {"_id": existing_session["_id"]},
                {
                    "$set": {
                        "messages": messages,
                        "updated_at": current_time
                    }
                }
            )
        else:
            chat_session = {
                "_id": session_id,
                "user_id": user_id,
                "messages": messages,
                "created_at": current_time,
                "updated_at": current_time
            }
            chat_sessions_collection.insert_one(chat_session)
            
    except Exception as e:
        print(f"Error saving chat session: {e}")
        

@app.post("/api/chat", response_model=ChatResponse)
async def chat_with_ai(
    chat_request: ChatRequest,
    current_user: dict = Depends(get_current_user)
):
    """Chat with AI about financial data"""
    try:
        # Check if chatbot is initialized
        if financial_chatbot is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="AI service is currently unavailable. Please try again later."
            )
        
        # Convert chat history to dict format for the chatbot
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
        
        # Get AI response
        response = financial_chatbot.chat(
            user_id=current_user["_id"],
            message=chat_request.message,
            chat_history=chat_history
        )
        
        # Save chat session to database
        session_id = str(uuid.uuid4())
        current_time = datetime.now(UTC)
        
        # Create messages list with user message and AI response
        messages = []
        if chat_request.chat_history:
            messages = [
                {
                    "role": msg.role.value,
                    "content": msg.content,
                    "timestamp": msg.timestamp or current_time
                }
                for msg in chat_request.chat_history
            ]
        
        # Add current user message and AI response
        messages.extend([
            {
                "role": "user",
                "content": chat_request.message,
                "timestamp": current_time
            },
            {
                "role": "assistant",
                "content": response,
                "timestamp": current_time
            }
        ])
        
        # Keep only the last N messages to prevent database bloat
        if len(messages) > settings.MAX_CHAT_HISTORY:
            messages = messages[-settings.MAX_CHAT_HISTORY:]
        
        # Save or update chat session
        try:
            # Try to update existing session or create new one
            existing_session = chat_sessions_collection.find_one({
                "user_id": current_user["_id"]
            }, sort=[("updated_at", -1)])
            
            if existing_session:
                chat_sessions_collection.update_one(
                    {"_id": existing_session["_id"]},
                    {
                        "$set": {
                            "messages": messages,
                            "updated_at": current_time
                        }
                    }
                )
            else:
                chat_session = {
                    "_id": session_id,
                    "user_id": current_user["_id"],
                    "messages": messages,
                    "created_at": current_time,
                    "updated_at": current_time
                }
                chat_sessions_collection.insert_one(chat_session)
        except Exception as db_error:
            print(f"Error saving chat session: {db_error}")
            # Don't fail the request if we can't save to DB
        
        return ChatResponse(
            response=response,
            timestamp=current_time
        )
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Chat endpoint error: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An error occurred while processing your message. Please try again."
        )

@app.get("/api/chat/history", response_model=List[ChatMessage])
async def get_chat_history(
    current_user: dict = Depends(get_current_user),
    limit: int = Query(default=20, le=50)
):
    """Get user's chat history"""
    try:
        # Get the most recent chat session
        session = chat_sessions_collection.find_one(
            {"user_id": current_user["_id"]},
            sort=[("updated_at", -1)]
        )
        
        if not session or "messages" not in session:
            return []
        
        # Return the last N messages
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
        result = chat_sessions_collection.delete_many({
            "user_id": current_user["_id"]
        })
        
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

@app.get("/api/insights", response_model=InsightsResponse)
async def get_financial_insights(current_user: dict = Depends(get_current_user)):
    """Get AI-generated financial insights for the user"""
    try:
        if financial_chatbot is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="AI service is currently unavailable. Please try again later."
            )
            
        insights = financial_chatbot.get_financial_insights(current_user["_id"])
        
        return InsightsResponse(
            insights=insights,
            generated_at=datetime.now(UTC)
        )
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Insights endpoint error: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An error occurred while generating insights. Please try again."
        )

# UPDATED TRANSACTION ENDPOINTS TO PROPERLY REFRESH AI DATA

@app.post("/api/transactions", response_model=TransactionResponse)
async def create_transaction(
    transaction_data: TransactionCreate,
    current_user: dict = Depends(get_current_user)
):
    transaction_id = str(uuid.uuid4())
    new_transaction = {
        "_id": transaction_id,
        "user_id": current_user["_id"],
        "type": transaction_data.type.value,
        "main_category": transaction_data.main_category,
        "sub_category": transaction_data.sub_category,
        "date": transaction_data.date,
        "description": transaction_data.description,
        "amount": transaction_data.amount,
        "created_at": datetime.now(UTC),
        "updated_at": datetime.now(UTC)
    }

    result = transactions_collection.insert_one(new_transaction)
    if not result.inserted_id:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create transaction"
        )
    
    # Refresh user's AI data after adding transaction
    try:
        if financial_chatbot:
            financial_chatbot.refresh_user_data(current_user["_id"])
            print(f"Refreshed AI data for user {current_user['_id']} after transaction creation")
    except Exception as e:
        print(f"Error refreshing AI data: {e}")
        # Don't fail the transaction creation if AI refresh fails

    return TransactionResponse(
        id=transaction_id,
        user_id=current_user["_id"],
        type=transaction_data.type,
        main_category=transaction_data.main_category,
        sub_category=transaction_data.sub_category,
        date=transaction_data.date,
        description=transaction_data.description,
        amount=transaction_data.amount,
        created_at=new_transaction["created_at"],
        updated_at=new_transaction["updated_at"]
    )

@app.post("/api/chat/refresh-data")
async def refresh_ai_data(current_user: dict = Depends(get_current_user)):
    """Manually refresh user's AI data (useful after bulk operations)"""
    try:
        financial_chatbot.refresh_user_data(current_user["_id"])
        return {"message": "AI data refreshed successfully"}
        
    except Exception as e:
        print(f"Refresh AI data error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An error occurred while refreshing AI data"
        )

@app.get("/")
async def root():
    return {"message": "Flow Finance API with AI Assistant is running"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)