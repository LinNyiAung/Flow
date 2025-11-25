import uuid
from datetime import datetime, timedelta, UTC

from fastapi import APIRouter, HTTPException, status, Depends,  Path

from utils import create_access_token, get_current_user, get_password_hash, verify_password
from models import (
    PasswordChange, ProfileUpdate, SubscriptionType, SubscriptionUpdate, UserCreate, UserLogin, UserResponse, Token, CategoryResponse, TransactionType,
)
from database import users_collection
from config import settings


router = APIRouter(prefix="/api/auth", tags=["auth"])



# ==================== AUTHENTICATION ====================

@router.post("/register", response_model=Token)
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
        "subscription_type": "free",  # NEW
        "subscription_expires_at": None,  # NEW
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
            created_at=new_user["created_at"],
            subscription_type=SubscriptionType.FREE,  # NEW
            subscription_expires_at=None  # NEW
        )
    )


@router.post("/login", response_model=Token)
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
            created_at=user["created_at"],
            subscription_type=SubscriptionType(user.get("subscription_type", "free")),  # NEW
            subscription_expires_at=user.get("subscription_expires_at")  # NEW
        )
    )


@router.get("/me", response_model=UserResponse)
async def get_current_user_info(current_user: dict = Depends(get_current_user)):
    """Get current user info"""
    return UserResponse(
        id=current_user["_id"],
        name=current_user["name"],
        email=current_user["email"],
        created_at=current_user["created_at"],
        subscription_type=SubscriptionType(current_user.get("subscription_type", "free")),  # NEW
        subscription_expires_at=current_user.get("subscription_expires_at")  # NEW
    )
    
    
@router.put("/profile", response_model=UserResponse)
async def update_profile(
    profile_data: ProfileUpdate,
    current_user: dict = Depends(get_current_user)
):
    """Update user profile (name only)"""
    if not profile_data.name or profile_data.name.strip() == "":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Name is required"
        )
    
    if len(profile_data.name.strip()) < 2:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Name must be at least 2 characters"
        )
    
    # Update user in database
    users_collection.update_one(
        {"_id": current_user["_id"]},
        {"$set": {"name": profile_data.name.strip()}}
    )
    
    # Get updated user
    updated_user = users_collection.find_one({"_id": current_user["_id"]})
    
    return UserResponse(
        id=updated_user["_id"],
        name=updated_user["name"],
        email=updated_user["email"],
        created_at=updated_user["created_at"],
        subscription_type=SubscriptionType(updated_user.get("subscription_type", "free")),
        subscription_expires_at=updated_user.get("subscription_expires_at")
    )
    
    
@router.put("/change-password")
async def change_password(
    password_data: PasswordChange,
    current_user: dict = Depends(get_current_user)
):
    """Change user password"""
    # Verify current password
    if not verify_password(password_data.current_password, current_user["password"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Current password is incorrect"
        )
    
    # Validate new password
    if len(password_data.new_password) < 6:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="New password must be at least 6 characters"
        )
    
    if password_data.new_password != password_data.confirm_password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="New passwords do not match"
        )
    
    # Update password
    hashed_password = get_password_hash(password_data.new_password)
    users_collection.update_one(
        {"_id": current_user["_id"]},
        {"$set": {"password": hashed_password}}
    )
    
    return {"message": "Password changed successfully"}
    
    
@router.put("/subscription", response_model=UserResponse)
async def update_subscription(
    subscription_data: SubscriptionUpdate,
    current_user: dict = Depends(get_current_user)
):
    """Update user subscription (admin use or after payment)"""
    update_data = {
        "subscription_type": subscription_data.subscription_type.value,
        "subscription_expires_at": subscription_data.subscription_expires_at
    }
    
    users_collection.update_one(
        {"_id": current_user["_id"]},
        {"$set": update_data}
    )
    
    updated_user = users_collection.find_one({"_id": current_user["_id"]})
    
    return UserResponse(
        id=updated_user["_id"],
        name=updated_user["name"],
        email=updated_user["email"],
        created_at=updated_user["created_at"],
        subscription_type=SubscriptionType(updated_user["subscription_type"]),
        subscription_expires_at=updated_user.get("subscription_expires_at")
    )
    
    
    
@router.get("/subscription-status")
async def get_subscription_status(current_user: dict = Depends(get_current_user)):
    """Check if user has active premium subscription"""
    subscription_type = current_user.get("subscription_type", "free")
    expires_at = current_user.get("subscription_expires_at")
    
    is_premium = subscription_type == "premium"
    is_expired = False
    
    if is_premium and expires_at:
        is_expired = expires_at < datetime.now(UTC)
        is_premium = not is_expired
    
    return {
        "subscription_type": subscription_type,
        "is_premium": is_premium,
        "expires_at": expires_at,
        "is_expired": is_expired
    }