from fastapi import FastAPI, HTTPException, status, Depends, Query, Path
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime, timedelta
from typing import List, Optional
from models import (
    UserCreate, UserLogin, UserResponse, Token, 
    TransactionCreate, TransactionResponse, CategoryResponse, TransactionType,
    TransactionUpdate
)
from database import users_collection, transactions_collection, categories_collection
from auth import get_password_hash, verify_password, create_access_token, verify_token
from config import settings
import uuid

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
        "created_at": datetime.utcnow()
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

# Transaction CRUD endpoints
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
        "description": transaction_data.description,
        "amount": transaction_data.amount,
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow()
    }
    
    transactions_collection.insert_one(new_transaction)
    
    return TransactionResponse(
        id=transaction_id,
        user_id=current_user["_id"],
        type=transaction_data.type,
        main_category=transaction_data.main_category,
        sub_category=transaction_data.sub_category,
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
    transaction_type: Optional[TransactionType] = None
):
    query = {"user_id": current_user["_id"]}
    if transaction_type:
        query["type"] = transaction_type.value
    
    transactions = list(
        transactions_collection
        .find(query)
        .sort("created_at", -1)
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
    # Check if transaction exists and belongs to user
    existing_transaction = transactions_collection.find_one({
        "_id": transaction_id,
        "user_id": current_user["_id"]
    })
    
    if not existing_transaction:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transaction not found"
        )
    
    # Prepare update data (only include fields that are provided)
    update_data = {"updated_at": datetime.utcnow()}
    
    if transaction_data.type is not None:
        update_data["type"] = transaction_data.type.value
    if transaction_data.main_category is not None:
        update_data["main_category"] = transaction_data.main_category
    if transaction_data.sub_category is not None:
        update_data["sub_category"] = transaction_data.sub_category
    if transaction_data.description is not None:
        update_data["description"] = transaction_data.description
    if transaction_data.amount is not None:
        update_data["amount"] = transaction_data.amount
    
    # Update the transaction
    transactions_collection.update_one(
        {"_id": transaction_id},
        {"$set": update_data}
    )
    
    # Get updated transaction
    updated_transaction = transactions_collection.find_one({"_id": transaction_id})
    
    return TransactionResponse(
        id=updated_transaction["_id"],
        user_id=updated_transaction["user_id"],
        type=TransactionType(updated_transaction["type"]),
        main_category=updated_transaction["main_category"],
        sub_category=updated_transaction["sub_category"],
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
    # Check if transaction exists and belongs to user
    existing_transaction = transactions_collection.find_one({
        "_id": transaction_id,
        "user_id": current_user["_id"]
    })
    
    if not existing_transaction:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transaction not found"
        )
    
    # Delete the transaction
    result = transactions_collection.delete_one({
        "_id": transaction_id,
        "user_id": current_user["_id"]
    })
    
    if result.deleted_count == 0:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete transaction"
        )
    
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
    # Calculate total inflow and outflow
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

@app.get("/")
async def root():
    return {"message": "Flow Finance API is running"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)