import random
import secrets
import uuid
from datetime import datetime, timedelta, UTC

from fastapi import APIRouter, BackgroundTasks, HTTPException, status, Depends,  Path
from fastapi.concurrency import run_in_threadpool

from email_service import send_otp_email, send_verification_email
from utils import create_access_token, get_current_user, get_password_hash, verify_password
from models import (
    Currency, CurrencyUpdate, ForgotPasswordRequest, LanguageUpdate, PasswordChange, ProfileUpdate, ResetPasswordRequest, SubscriptionType, SubscriptionUpdate, UserCreate, UserLogin, UserResponse, Token, CategoryResponse, TransactionType, VerifyOTPRequest,
)
from database import users_collection
from config import settings
from database import (
    transactions_collection, chat_sessions_collection, goals_collection, insights_collection, budgets_collection, notifications_collection, notification_preferences_collection
)

router = APIRouter(prefix="/api/auth", tags=["auth"])



# ==================== AUTHENTICATION ====================

@router.post("/register", response_model=Token)
async def register(user_data: UserCreate, background_tasks: BackgroundTasks): # <-- Inject BackgroundTasks
    """Register new user"""
    if await users_collection.find_one({"email": user_data.email}):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered")
    
    hashed_password = await run_in_threadpool(get_password_hash, user_data.password)
    
    user_id = str(uuid.uuid4())
    verification_token = secrets.token_urlsafe(32) # <-- Generate a secure random token
    
    new_user = {
        "_id": user_id,
        "name": user_data.name,
        "email": user_data.email,
        "password": hashed_password,
        "subscription_type": "free",
        "subscription_expires_at": None,
        "default_currency": "usd",
        "language": "en",
        "created_at": datetime.now(UTC),
        "is_verified": False, # <-- Default to False
        "verification_token": verification_token # <-- Save the token to the DB
    }
    
    await users_collection.insert_one(new_user)

    # Trigger the email to send in the background
    background_tasks.add_task(send_verification_email, user_data.email, verification_token)

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
            subscription_type=SubscriptionType.FREE,
            subscription_expires_at=None,
            default_currency=Currency.USD,
            is_verified=False # <-- Reflect in response
        )
    )


@router.get("/verify-email")
async def verify_email(email: str, token: str):
    """Verify user's email address using the token"""
    user = await users_collection.find_one({"email": email})
    
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
        
    if user.get("is_verified"):
        return {"message": "Email is already verified. You can log in."}
        
    if user.get("verification_token") != token:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid verification token")
        
    # Update user to verified and remove the token so it can't be reused
    await users_collection.update_one(
        {"_id": user["_id"]},
        {
            "$set": {"is_verified": True},
            "$unset": {"verification_token": ""} 
        }
    )
    
    return {"message": "Email verified successfully! Your account is now active."}
    
    
@router.put("/language", response_model=UserResponse)
async def update_language(
    language_data: LanguageUpdate,
    current_user: dict = Depends(get_current_user)
):
    """Update user's preferred language"""
    if language_data.language not in ["en", "my"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid language. Must be 'en' or 'my'"
        )
    
    # [FIX] Added await
    await users_collection.update_one(
        {"_id": current_user["_id"]},
        {"$set": {"language": language_data.language}}
    )
    
    # [FIX] Added await
    updated_user = await users_collection.find_one({"_id": current_user["_id"]})
    
    return UserResponse(
        id=updated_user["_id"],
        name=updated_user["name"],
        email=updated_user["email"],
        created_at=updated_user["created_at"],
        subscription_type=SubscriptionType(updated_user.get("subscription_type", "free")),
        subscription_expires_at=updated_user.get("subscription_expires_at"),
        default_currency=Currency(updated_user.get("default_currency", "usd"))
    )


@router.post("/login", response_model=Token)
async def login(user_credentials: UserLogin):
    """Login user"""
    user = await users_collection.find_one({"email": user_credentials.email})
    
    if not user or not await run_in_threadpool(verify_password, user_credentials.password, user["password"]):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Incorrect email or password")

    # <-- NEW: Block login if the user hasn't verified their email
    if not user.get("is_verified", False):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, 
            detail="Please verify your email address before logging in. Check your inbox."
        )

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
            subscription_type=SubscriptionType(user.get("subscription_type", "free")),
            subscription_expires_at=user.get("subscription_expires_at"),
            default_currency=Currency(user.get("default_currency", "usd")),
            is_verified=user.get("is_verified", True) # <-- Pass status to frontend
        )
    )
    
    
@router.post("/forgot-password/request-otp")
async def request_password_reset_otp(request: ForgotPasswordRequest):
    """
    Generate a 6-digit OTP, store it (hashed) with a 10-minute expiry,
    and e-mail it to the user.  Always returns 200 to avoid user enumeration.
    """
    user = await users_collection.find_one({"email": request.email})

    if user:
        otp = str(random.randint(100000, 999999))          # 6-digit code
        otp_expiry = datetime.now(UTC) + timedelta(minutes=10)

        await users_collection.update_one(
            {"_id": user["_id"]},
            {
                "$set": {
                    "password_reset_otp": otp,              # store plain for simplicity;
                    "password_reset_otp_expiry": otp_expiry # swap to hashed in production
                }
            }
        )

        # Fire-and-forget – errors are logged but don't break the response
        try:
            send_otp_email(request.email, otp)
        except Exception as e:
            print(f"❌ OTP email failed: {e}")

    # Always return the same response (prevents email enumeration)
    return {"message": "If that email is registered, you will receive an OTP shortly."}


# ── 2. Verify OTP ─────────────────────────────────────────────────────────────
@router.post("/forgot-password/verify-otp")
async def verify_password_reset_otp(request: VerifyOTPRequest):
    """
    Check that the supplied OTP matches and hasn't expired.
    Returns a short-lived reset_token the client must present when
    calling /reset-password.
    """
    user = await users_collection.find_one({"email": request.email})

    if not user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid OTP or email"
        )

    stored_otp = user.get("password_reset_otp")
    otp_expiry = user.get("password_reset_otp_expiry")

    if not stored_otp or not otp_expiry:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No OTP was requested for this account"
        )

    # Ensure expiry is timezone-aware
    if otp_expiry.tzinfo is None:
        otp_expiry = otp_expiry.replace(tzinfo=UTC)

    if datetime.now(UTC) > otp_expiry:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="OTP has expired. Please request a new one."
        )

    if stored_otp != request.otp:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid OTP. Please try again."
        )

    # OTP is valid – issue a single-use reset token (10-min window)
    import secrets
    reset_token = secrets.token_urlsafe(32)
    reset_token_expiry = datetime.now(UTC) + timedelta(minutes=10)

    await users_collection.update_one(
        {"_id": user["_id"]},
        {
            "$set": {
                "password_reset_token": reset_token,
                "password_reset_token_expiry": reset_token_expiry
            },
            "$unset": {
                "password_reset_otp": "",
                "password_reset_otp_expiry": ""
            }
        }
    )

    return {"message": "OTP verified successfully.", "reset_token": reset_token}


# ── 3. Reset Password ─────────────────────────────────────────────────────────
@router.post("/forgot-password/reset-password")
async def reset_password(request: ResetPasswordRequest):
    """
    Accept the reset_token from step 2 and set a new password.
    """
    user = await users_collection.find_one({"email": request.email})

    if not user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid request"
        )

    stored_token = user.get("password_reset_token")
    token_expiry = user.get("password_reset_token_expiry")

    if not stored_token or not token_expiry:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No password reset was initiated for this account"
        )

    if token_expiry.tzinfo is None:
        token_expiry = token_expiry.replace(tzinfo=UTC)

    if datetime.now(UTC) > token_expiry:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Reset session expired. Please start over."
        )

    if stored_token != request.reset_token:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid reset token"
        )

    if len(request.new_password) < 6:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password must be at least 6 characters"
        )

    if request.new_password != request.confirm_password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Passwords do not match"
        )

    hashed = await run_in_threadpool(get_password_hash, request.new_password)

    await users_collection.update_one(
        {"_id": user["_id"]},
        {
            "$set": {"password": hashed},
            "$unset": {
                "password_reset_token": "",
                "password_reset_token_expiry": ""
            }
        }
    )

    return {"message": "Password reset successfully. You can now log in."}


@router.get("/me", response_model=UserResponse)
async def get_current_user_info(current_user: dict = Depends(get_current_user)):
    """Get current user info"""
    return UserResponse(
        id=current_user["_id"],
        name=current_user["name"],
        email=current_user["email"],
        created_at=current_user["created_at"],
        subscription_type=SubscriptionType(current_user.get("subscription_type", "free")),
        subscription_expires_at=current_user.get("subscription_expires_at"),
        default_currency=Currency(current_user.get("default_currency", "usd"))  # NEW
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
    
    # [FIX] Added await
    await users_collection.update_one(
        {"_id": current_user["_id"]},
        {"$set": {"name": profile_data.name.strip()}}
    )
    
    # [FIX] Added await
    updated_user = await users_collection.find_one({"_id": current_user["_id"]})
    
    return UserResponse(
        id=updated_user["_id"],
        name=updated_user["name"],
        email=updated_user["email"],
        created_at=updated_user["created_at"],
        subscription_type=SubscriptionType(updated_user.get("subscription_type", "free")),
        subscription_expires_at=updated_user.get("subscription_expires_at"),
        default_currency=Currency(updated_user.get("default_currency", "usd"))
    )
    
    
@router.put("/currency", response_model=UserResponse)
async def update_default_currency(
    currency_data: CurrencyUpdate,
    current_user: dict = Depends(get_current_user)
):
    """Update user's default currency"""
    # [FIX] Added await
    await users_collection.update_one(
        {"_id": current_user["_id"]},
        {"$set": {"default_currency": currency_data.default_currency.value}}
    )
    
    # [FIX] Added await
    updated_user = await users_collection.find_one({"_id": current_user["_id"]})
    
    return UserResponse(
        id=updated_user["_id"],
        name=updated_user["name"],
        email=updated_user["email"],
        created_at=updated_user["created_at"],
        subscription_type=SubscriptionType(updated_user.get("subscription_type", "free")),
        subscription_expires_at=updated_user.get("subscription_expires_at"),
        default_currency=Currency(updated_user["default_currency"])
    )
    
    
@router.put("/change-password")
async def change_password(
    password_data: PasswordChange,
    current_user: dict = Depends(get_current_user)
):
    """Change user password"""
    # Verify current password
    # [FIX] Offload verification
    is_correct = await run_in_threadpool(verify_password, password_data.current_password, current_user["password"])
    
    if not is_correct:
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
    hashed_password = await run_in_threadpool(get_password_hash, password_data.new_password)
    
    # [FIX] Added await
    await users_collection.update_one(
        {"_id": current_user["_id"]},
        {"$set": {"password": hashed_password}}
    )
    
    return {"message": "Password changed successfully"}
    
    

@router.delete("/delete-account")
async def delete_account(
    current_user: dict = Depends(get_current_user)
):
    """Delete user account and all associated data"""
    try:
        user_id = current_user["_id"]
        
        # Delete all user data
        # [FIX] Added await to all calls
        await transactions_collection.delete_many({"user_id": user_id})
        await goals_collection.delete_many({"user_id": user_id})
        await budgets_collection.delete_many({"user_id": user_id})
        await chat_sessions_collection.delete_many({"user_id": user_id})
        await insights_collection.delete_many({"user_id": user_id})
        await notifications_collection.delete_many({"user_id": user_id})
        await notification_preferences_collection.delete_many({"user_id": user_id})
        
        # Finally, delete the user account
        # [FIX] Added await
        result = await users_collection.delete_one({"_id": user_id})
        
        if result.deleted_count == 0:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to delete account"
            )
        
        return {"message": "Account deleted successfully"}
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error deleting account: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete account"
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