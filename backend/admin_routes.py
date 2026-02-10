import uuid
from datetime import datetime, timedelta, UTC
from typing import Dict, List, Optional

from fastapi import APIRouter, HTTPException, status, Depends, Query, Path

from admin_utils import (
    create_admin_access_token,
    get_current_admin,
    get_password_hash,
    log_admin_action,
    require_admin_or_super,
    require_super_admin,
    verify_password
)
from admin_models import (
    AdminActionLog,
    AdminCreate,
    AdminFeedbackListResponse,
    AdminLogin,
    AdminPasswordChange,
    AdminResponse,
    AdminRole,
    AdminToken,
    AdminUpdate,
    BroadcastNotificationRequest,
    BroadcastNotificationResponse,
    SystemStatsResponse,
    UpdateUserSubscriptionRequest,
    UserDetailResponse,
    UserListResponse,
    UserStatsResponse
)
from firebase_service import send_fcm_to_multiple
from notification_service import should_send_notification
from models import Currency, SubscriptionType
from database import (
    admins_collection,
    admin_action_logs_collection,
    users_collection,
    transactions_collection,
    goals_collection,
    budgets_collection,
    chat_sessions_collection,
    notifications_collection,
    ai_usage_collection,
    feedback_collection
)
from ai_usage_models import AIUsageResponse, UserAIUsageStats, AIUsageStatsResponse, AIFeatureType, AIProviderType
from config import settings

router = APIRouter(prefix="/api/admin", tags=["admin"])


# ==================== ADMIN AUTHENTICATION ====================

@router.post("/login", response_model=AdminToken)
async def admin_login(credentials: AdminLogin):
    """Admin login"""
    # [FIX] Added await
    admin = await admins_collection.find_one({"email": credentials.email})
    
    if not admin or not verify_password(credentials.password, admin["password"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password"
        )
    
    # Update last login
    # [FIX] Added await
    await admins_collection.update_one(
        {"_id": admin["_id"]},
        {"$set": {"last_login": datetime.now(UTC)}}
    )
    
    access_token = create_admin_access_token(
        data={"sub": admin["email"]},
        expires_delta=timedelta(hours=8)
    )
    
    return AdminToken(
        access_token=access_token,
        token_type="bearer",
        admin=AdminResponse(
            id=admin["_id"],
            name=admin["name"],
            email=admin["email"],
            role=AdminRole(admin["role"]),
            created_at=admin["created_at"],
            last_login=admin.get("last_login")
        )
    )


@router.get("/me", response_model=AdminResponse)
async def get_current_admin_info(current_admin: dict = Depends(get_current_admin)):
    """Get current admin info"""
    return AdminResponse(
        id=current_admin["_id"],
        name=current_admin["name"],
        email=current_admin["email"],
        role=AdminRole(current_admin["role"]),
        created_at=current_admin["created_at"],
        last_login=current_admin.get("last_login")
    )


@router.put("/change-password")
async def admin_change_password(
    password_data: AdminPasswordChange,
    current_admin: dict = Depends(get_current_admin)
):
    """Change admin password"""
    if not verify_password(password_data.current_password, current_admin["password"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Current password is incorrect"
        )
    
    if len(password_data.new_password) < 8:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="New password must be at least 8 characters"
        )
    
    if password_data.new_password != password_data.confirm_password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="New passwords do not match"
        )
    
    hashed_password = get_password_hash(password_data.new_password)
    # [FIX] Added await
    await admins_collection.update_one(
        {"_id": current_admin["_id"]},
        {"$set": {"password": hashed_password}}
    )
    
    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"],
        action="changed_password"
    )
    
    return {"message": "Password changed successfully"}


@router.put("/me", response_model=AdminResponse)
async def update_admin_profile(
    update_data: AdminUpdate,
    current_admin: dict = Depends(get_current_admin)
):
    """Update current admin profile"""
    update_fields = {}
    
    if update_data.name and update_data.name != current_admin["name"]:
        update_fields["name"] = update_data.name
        
    if update_data.email and update_data.email != current_admin["email"]:
        # Check if email already exists
        # [FIX] Added await
        if await admins_collection.find_one({"email": update_data.email}):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already in use"
            )
        update_fields["email"] = update_data.email
        
    if not update_fields:
        return AdminResponse(
            id=current_admin["_id"],
            name=current_admin["name"],
            email=current_admin["email"],
            role=AdminRole(current_admin["role"]),
            created_at=current_admin["created_at"],
            last_login=current_admin.get("last_login")
        )

    # [FIX] Added await
    await admins_collection.update_one(
        {"_id": current_admin["_id"]},
        {"$set": update_fields}
    )
    
    # Log action
    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"], 
        action="updated_profile",
        details=f"Updated profile fields: {', '.join(update_fields.keys())}"
    )
    
    # Fetch updated document
    # [FIX] Added await
    updated_admin = await admins_collection.find_one({"_id": current_admin["_id"]})
    
    return AdminResponse(
        id=updated_admin["_id"],
        name=updated_admin["name"],
        email=updated_admin["email"],
        role=AdminRole(updated_admin["role"]),
        created_at=updated_admin["created_at"],
        last_login=updated_admin.get("last_login")
    )


# ==================== ADMIN MANAGEMENT (Super Admin Only) ====================

@router.post("/admins", response_model=AdminResponse)
async def create_admin(
    admin_data: AdminCreate,
    current_admin: dict = Depends(require_super_admin)
):
    """Create new admin (super admin only)"""
    # [FIX] Added await
    if await admins_collection.find_one({"email": admin_data.email}):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered"
        )
    
    admin_id = str(uuid.uuid4())
    new_admin = {
        "_id": admin_id,
        "name": admin_data.name,
        "email": admin_data.email,
        "password": get_password_hash(admin_data.password),
        "role": admin_data.role.value,
        "created_at": datetime.now(UTC),
        "last_login": None
    }
    
    # [FIX] Added await
    await admins_collection.insert_one(new_admin)
    
    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"],
        action="created_admin",
        details=f"Created admin: {admin_data.email} with role {admin_data.role.value}"
    )
    
    return AdminResponse(
        id=admin_id,
        name=new_admin["name"],
        email=new_admin["email"],
        role=AdminRole(new_admin["role"]),
        created_at=new_admin["created_at"],
        last_login=None
    )


@router.get("/admins", response_model=List[AdminResponse])
async def get_all_admins(current_admin: dict = Depends(require_super_admin)):
    """Get all admins (super admin only)"""
    # [FIX] Async cursor to list
    cursor = admins_collection.find()
    admins = await cursor.to_list(length=None)
    
    return [
        AdminResponse(
            id=admin["_id"],
            name=admin["name"],
            email=admin["email"],
            role=AdminRole(admin["role"]),
            created_at=admin["created_at"],
            last_login=admin.get("last_login")
        )
        for admin in admins
    ]


@router.delete("/admins/{admin_id}")
async def delete_admin(
    admin_id: str = Path(...),
    current_admin: dict = Depends(require_super_admin)
):
    """Delete admin (super admin only)"""
    if admin_id == current_admin["_id"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot delete yourself"
        )
    
    # [FIX] Added await
    admin_to_delete = await admins_collection.find_one({"_id": admin_id})
    if not admin_to_delete:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Admin not found"
        )
    
    # [FIX] Added await
    result = await admins_collection.delete_one({"_id": admin_id})
    
    if result.deleted_count == 0:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Admin not found"
        )
    
    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"],
        action="deleted_admin",
        details=f"Deleted admin: {admin_to_delete['email']}"
    )
    
    return {"message": "Admin deleted successfully"}


# ==================== USER MANAGEMENT ====================

@router.get("/users", response_model=List[UserListResponse])
async def get_all_users(
    current_admin: dict = Depends(require_admin_or_super),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    search: Optional[str] = Query(None),
    subscription_type: Optional[SubscriptionType] = Query(None)
):
    """Get all users with pagination and filters"""
    query = {}
    
    if search:
        query["$or"] = [
            {"name": {"$regex": search, "$options": "i"}},
            {"email": {"$regex": search, "$options": "i"}}
        ]
    
    if subscription_type:
        query["subscription_type"] = subscription_type.value
    
    # [FIX] Async find with skip/limit
    cursor = users_collection.find(query).skip(skip).limit(limit).sort("created_at", -1)
    users = await cursor.to_list(length=limit)
    
    user_list = []
    for user in users:
        # [FIX] Added await for counts
        transaction_count = await transactions_collection.count_documents({"user_id": user["_id"]})
        goals_count = await goals_collection.count_documents({"user_id": user["_id"]})
        
        # [FIX] Async find_one
        last_transaction = await transactions_collection.find_one(
            {"user_id": user["_id"]},
            sort=[("created_at", -1)]
        )
        last_chat = await chat_sessions_collection.find_one(
            {"user_id": user["_id"]},
            sort=[("updated_at", -1)]
        )
        
        last_active = None
        if last_transaction and last_chat:
            last_active = max(
                last_transaction.get("created_at"),
                last_chat.get("updated_at")
            )
        elif last_transaction:
            last_active = last_transaction.get("created_at")
        elif last_chat:
            last_active = last_chat.get("updated_at")
        
        user_list.append(UserListResponse(
            id=user["_id"],
            name=user["name"],
            email=user["email"],
            subscription_type=SubscriptionType(user.get("subscription_type", "free")),
            subscription_expires_at=user.get("subscription_expires_at"),
            default_currency=Currency(user.get("default_currency", "usd")),
            created_at=user["created_at"],
            total_transactions=transaction_count,
            total_goals=goals_count,
            last_active=last_active
        ))
    
    return user_list


@router.get("/users/{user_id}", response_model=UserDetailResponse)
async def get_user_detail(
    user_id: str = Path(...),
    current_admin: dict = Depends(require_admin_or_super)
):
    """Get detailed user information"""
    # [FIX] Added await
    user = await users_collection.find_one({"_id": user_id})
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    # [FIX] Added await for counts
    transaction_count = await transactions_collection.count_documents({"user_id": user_id})
    goals_count = await goals_collection.count_documents({"user_id": user_id})
    budgets_count = await budgets_collection.count_documents({"user_id": user_id})
    chat_sessions_count = await chat_sessions_collection.count_documents({"user_id": user_id})
    
    # [FIX] Async find_one
    last_transaction = await transactions_collection.find_one(
        {"user_id": user_id},
        sort=[("created_at", -1)]
    )
    last_chat = await chat_sessions_collection.find_one(
        {"user_id": user_id},
        sort=[("updated_at", -1)]
    )
    
    last_active = None
    if last_transaction and last_chat:
        last_active = max(
            last_transaction.get("created_at"),
            last_chat.get("updated_at")
        )
    elif last_transaction:
        last_active = last_transaction.get("created_at")
    elif last_chat:
        last_active = last_chat.get("updated_at")
    
    return UserDetailResponse(
        id=user["_id"],
        name=user["name"],
        email=user["email"],
        subscription_type=SubscriptionType(user.get("subscription_type", "free")),
        subscription_expires_at=user.get("subscription_expires_at"),
        default_currency=Currency(user.get("default_currency", "usd")),
        language=user.get("language", "en"),
        created_at=user["created_at"],
        total_transactions=transaction_count,
        total_goals=goals_count,
        total_budgets=budgets_count,
        total_chat_sessions=chat_sessions_count,
        last_active=last_active
    )


@router.put("/users/{user_id}/subscription")
async def update_user_subscription(
    user_id: str = Path(...),
    subscription_data: UpdateUserSubscriptionRequest = ...,
    current_admin: dict = Depends(require_admin_or_super)
):
    """Update user subscription"""
    # [FIX] Added await
    user = await users_collection.find_one({"_id": user_id})
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    update_data = {
        "subscription_type": subscription_data.subscription_type.value,
        "subscription_expires_at": subscription_data.subscription_expires_at
    }
    
    # [FIX] Added await
    await users_collection.update_one(
        {"_id": user_id},
        {"$set": update_data}
    )
    
    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"],
        action="updated_user_subscription",
        target_user_id=user_id,
        target_user_email=user["email"],
        details=f"Updated subscription to {subscription_data.subscription_type.value}"
    )
    
    return {"message": "User subscription updated successfully"}


@router.delete("/users/{user_id}")
async def delete_user(
    user_id: str = Path(...),
    current_admin: dict = Depends(require_super_admin)
):
    """Delete user and all associated data (super admin only)"""
    # [FIX] Added await
    user = await users_collection.find_one({"_id": user_id})
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    # [FIX] Added await for all delete operations
    await transactions_collection.delete_many({"user_id": user_id})
    await goals_collection.delete_many({"user_id": user_id})
    await budgets_collection.delete_many({"user_id": user_id})
    await chat_sessions_collection.delete_many({"user_id": user_id})
    await notifications_collection.delete_many({"user_id": user_id})
    
    result = await users_collection.delete_one({"_id": user_id})
    
    if result.deleted_count == 0:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete user"
        )
    
    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"],
        action="deleted_user",
        target_user_id=user_id,
        target_user_email=user["email"],
        details="Deleted user and all associated data"
    )
    
    return {"message": "User deleted successfully"}


# ==================== STATISTICS ====================

@router.get("/stats/users", response_model=UserStatsResponse)
async def get_user_stats(current_admin: dict = Depends(require_admin_or_super)):
    """Get user statistics"""
    # [FIX] Added await to all DB calls
    total_users = await users_collection.count_documents({})
    free_users = await users_collection.count_documents({"subscription_type": "free"})
    premium_users = await users_collection.count_documents({"subscription_type": "premium"})
    
    # Users created in last 30 days
    thirty_days_ago = datetime.now(UTC) - timedelta(days=30)
    new_users_last_30_days = await users_collection.count_documents({
        "created_at": {"$gte": thirty_days_ago}
    })
    
    # Active users in last 7 days
    seven_days_ago = datetime.now(UTC) - timedelta(days=7)
    active_user_ids = set()
    
    # [FIX] Async cursor iteration
    cursor_tx = transactions_collection.find({
        "created_at": {"$gte": seven_days_ago}
    }, {"user_id": 1})
    async for t in cursor_tx:
        active_user_ids.add(t["user_id"])
    
    # [FIX] Async cursor iteration
    cursor_chat = chat_sessions_collection.find({
        "updated_at": {"$gte": seven_days_ago}
    }, {"user_id": 1})
    async for c in cursor_chat:
        active_user_ids.add(c["user_id"])
    
    active_users_last_7_days = len(active_user_ids)
    
    total_transactions = await transactions_collection.count_documents({})
    total_goals = await goals_collection.count_documents({})
    
    return UserStatsResponse(
        total_users=total_users,
        free_users=free_users,
        premium_users=premium_users,
        new_users_last_30_days=new_users_last_30_days,
        active_users_last_7_days=active_users_last_7_days,
        total_transactions=total_transactions,
        total_goals=total_goals
    )


@router.get("/stats/system", response_model=SystemStatsResponse)
async def get_system_stats(current_admin: dict = Depends(require_admin_or_super)):
    """Get comprehensive system statistics"""
    now = datetime.now(UTC)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    week_start = now - timedelta(days=7)
    month_start = now - timedelta(days=30)
    
    # [FIX] Added await to all DB calls
    total_users = await users_collection.count_documents({})
    free_users = await users_collection.count_documents({"subscription_type": "free"})
    premium_users = await users_collection.count_documents({"subscription_type": "premium"})
    
    new_users_today = await users_collection.count_documents({"created_at": {"$gte": today_start}})
    new_users_this_week = await users_collection.count_documents({"created_at": {"$gte": week_start}})
    new_users_this_month = await users_collection.count_documents({"created_at": {"$gte": month_start}})
    
    # Activity stats
    active_today = set()
    active_week = set()
    
    # [FIX] Async cursor iterations
    async for t in transactions_collection.find({"created_at": {"$gte": today_start}}, {"user_id": 1}):
        active_today.add(t["user_id"])
    
    async for t in transactions_collection.find({"created_at": {"$gte": week_start}}, {"user_id": 1}):
        active_week.add(t["user_id"])
    
    async for c in chat_sessions_collection.find({"updated_at": {"$gte": today_start}}, {"user_id": 1}):
        active_today.add(c["user_id"])
    
    async for c in chat_sessions_collection.find({"updated_at": {"$gte": week_start}}, {"user_id": 1}):
        active_week.add(c["user_id"])
    
    # Total counts with await
    total_transactions = await transactions_collection.count_documents({})
    total_goals = await goals_collection.count_documents({})
    total_budgets = await budgets_collection.count_documents({})
    total_chat_sessions = await chat_sessions_collection.count_documents({})
    total_notifications = await notifications_collection.count_documents({})
    
    return SystemStatsResponse(
        total_users=total_users,
        free_users=free_users,
        premium_users=premium_users,
        total_transactions=total_transactions,
        total_goals=total_goals,
        total_budgets=total_budgets,
        total_chat_sessions=total_chat_sessions,
        total_notifications=total_notifications,
        new_users_today=new_users_today,
        new_users_this_week=new_users_this_week,
        new_users_this_month=new_users_this_month,
        active_users_today=len(active_today),
        active_users_this_week=len(active_week)
    )
    
    
    
# ==================== NOTIFICATION BROADCAST ====================

@router.post("/broadcast-notification", response_model=BroadcastNotificationResponse)
async def broadcast_notification(
    broadcast_data: BroadcastNotificationRequest,
    current_admin: dict = Depends(require_admin_or_super)
):
    """Broadcast notification to users based on criteria"""
    try:
        # Build user query based on target
        query = {}
        if broadcast_data.target_users == "free":
            query["subscription_type"] = "free"
        elif broadcast_data.target_users == "premium":
            query["subscription_type"] = "premium"
        
        # [FIX] Async find and to_list
        cursor = users_collection.find(query)
        users = await cursor.to_list(length=None)
        total_users = len(users)
        
        if total_users == 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No users found matching the criteria"
            )
        
        # Create notifications and collect FCM tokens
        notifications_sent = 0
        fcm_tokens = []
        
        for user in users:
            user_id = user["_id"]
            
            # [FIX] Added await to this imported async function
            if not await should_send_notification(user_id, broadcast_data.notification_type):
                continue
            
            notification_id = str(uuid.uuid4())
            notification = {
                "_id": notification_id,
                "user_id": user_id,
                "type": broadcast_data.notification_type,
                "title": broadcast_data.title,
                "message": broadcast_data.message,
                "goal_id": None,
                "goal_name": None,
                "currency": None,
                "created_at": datetime.now(UTC),
                "is_read": False
            }
            
            # [FIX] Added await
            await notifications_collection.insert_one(notification)
            notifications_sent += 1
            
            if user.get("fcm_token"):
                fcm_tokens.append(user["fcm_token"])
        
        # Send FCM push notifications in batch
        fcm_result = {"success": 0, "failure": 0}
        if fcm_tokens:
            fcm_data = {
                "type": broadcast_data.notification_type,
                "is_broadcast": "true"
            }
            # send_fcm_to_multiple is sync (uses firebase sdk), so it's fine
            fcm_result = send_fcm_to_multiple(
                fcm_tokens=fcm_tokens,
                title=broadcast_data.title,
                body=broadcast_data.message,
                data=fcm_data
            )
        
        await log_admin_action(
            admin_id=current_admin["_id"],
            admin_email=current_admin["email"],
            action="broadcast_notification",
            details=f"Sent '{broadcast_data.title}' to {broadcast_data.target_users} users ({notifications_sent} notifications, {fcm_result['success']} FCM sent)"
        )
        
        return BroadcastNotificationResponse(
            message=f"Broadcast notification sent successfully",
            total_users=total_users,
            notifications_sent=notifications_sent,
            fcm_sent=fcm_result["success"],
            fcm_failed=fcm_result["failure"]
        )
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error broadcasting notification: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to broadcast notification: {str(e)}"
        )


@router.get("/broadcast-stats")
async def get_broadcast_stats(
    current_admin: dict = Depends(require_admin_or_super)
):
    """Get statistics for potential broadcast reach"""
    try:
        # [FIX] Added await for all counts
        total_users = await users_collection.count_documents({})
        free_users = await users_collection.count_documents({"subscription_type": "free"})
        premium_users = await users_collection.count_documents({"subscription_type": "premium"})
        
        users_with_fcm = await users_collection.count_documents({"fcm_token": {"$exists": True, "$ne": None}})
        free_with_fcm = await users_collection.count_documents({
            "subscription_type": "free",
            "fcm_token": {"$exists": True, "$ne": None}
        })
        premium_with_fcm = await users_collection.count_documents({
            "subscription_type": "premium",
            "fcm_token": {"$exists": True, "$ne": None}
        })
        
        return {
            "total_users": total_users,
            "free_users": free_users,
            "premium_users": premium_users,
            "users_with_push_enabled": users_with_fcm,
            "free_with_push": free_with_fcm,
            "premium_with_push": premium_with_fcm
        }
        
    except Exception as e:
        print(f"Error getting broadcast stats: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get broadcast statistics"
        )
    


# ==================== AI USAGE MONITORING ====================

@router.get("/ai-usage/stats", response_model=AIUsageStatsResponse)
async def get_ai_usage_stats(
    current_admin: dict = Depends(require_admin_or_super),
    start_date: Optional[datetime] = Query(None),
    end_date: Optional[datetime] = Query(None)
):
    """Get overall AI usage statistics"""
    try:
        query = {}
        if start_date or end_date:
            query["created_at"] = {}
            if start_date:
                query["created_at"]["$gte"] = start_date
            if end_date:
                query["created_at"]["$lte"] = end_date
        
        # Aggregate statistics
        pipeline = [
            {"$match": query} if query else {"$match": {}},
            {
                "$group": {
                    "_id": None,
                    "total_requests": {"$sum": 1},
                    "total_tokens": {"$sum": "$total_tokens"},
                    "total_cost": {"$sum": "$estimated_cost_usd"},
                    "openai_cost": {
                        "$sum": {
                            "$cond": [{"$eq": ["$provider", "openai"]}, "$estimated_cost_usd", 0]
                        }
                    },
                    "gemini_cost": {
                        "$sum": {
                            "$cond": [{"$eq": ["$provider", "gemini"]}, "$estimated_cost_usd", 0]
                        }
                    },
                    "weekly_insights": {
                        "$sum": {
                            "$cond": [{"$eq": ["$feature_type", "weekly_insight"]}, 1, 0]
                        }
                    },
                    "monthly_insights": {
                        "$sum": {
                            "$cond": [{"$eq": ["$feature_type", "monthly_insight"]}, 1, 0]
                        }
                    },
                    "chat_requests": {
                        "$sum": {
                            "$cond": [{"$eq": ["$feature_type", "chat"]}, 1, 0]
                        }
                    },
                    "translations": {
                        "$sum": {
                            "$cond": [{"$eq": ["$feature_type", "translation"]}, 1, 0]
                        }
                    }
                }
            }
        ]
        
        # [FIX] Async aggregation
        cursor = ai_usage_collection.aggregate(pipeline)
        result = await cursor.to_list(length=None)
        
        if not result:
            return AIUsageStatsResponse(
                total_users=0,
                total_requests=0,
                total_tokens=0,
                total_cost_usd=0.0,
                openai_total_cost=0.0,
                gemini_total_cost=0.0,
                weekly_insights_requests=0,
                monthly_insights_requests=0,
                chat_requests=0,
                translation_requests=0
            )
        
        stats = result[0]
        
        # [FIX] Async distinct
        unique_users = len(await ai_usage_collection.distinct("user_id", query))
        
        return AIUsageStatsResponse(
            total_users=unique_users,
            total_requests=stats["total_requests"],
            total_tokens=stats["total_tokens"],
            total_cost_usd=round(stats["total_cost"], 4),
            openai_total_cost=round(stats["openai_cost"], 4),
            gemini_total_cost=round(stats["gemini_cost"], 4),
            weekly_insights_requests=stats["weekly_insights"],
            monthly_insights_requests=stats["monthly_insights"],
            chat_requests=stats["chat_requests"],
            translation_requests=stats["translations"]
        )
        
    except Exception as e:
        print(f"Error getting AI usage stats: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get AI usage statistics"
        )


@router.get("/ai-usage/users", response_model=List[UserAIUsageStats])
async def get_users_ai_usage(
    current_admin: dict = Depends(require_admin_or_super),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    sort_by: str = Query("total_cost", regex="^(total_cost|total_tokens|total_requests)$")
):
    """Get AI usage statistics per user"""
    try:
        pipeline = [
            {
                "$group": {
                    "_id": "$user_id",
                    "total_requests": {"$sum": 1},
                    "total_input_tokens": {"$sum": "$input_tokens"},
                    "total_output_tokens": {"$sum": "$output_tokens"},
                    "total_tokens": {"$sum": "$total_tokens"},
                    "total_cost": {"$sum": "$estimated_cost_usd"},
                    "weekly_insights": {
                        "$sum": {"$cond": [{"$eq": ["$feature_type", "weekly_insight"]}, 1, 0]}
                    },
                    "monthly_insights": {
                        "$sum": {"$cond": [{"$eq": ["$feature_type", "monthly_insight"]}, 1, 0]}
                    },
                    "chat_requests": {
                        "$sum": {"$cond": [{"$eq": ["$feature_type", "chat"]}, 1, 0]}
                    },
                    "translations": {
                        "$sum": {"$cond": [{"$eq": ["$feature_type", "translation"]}, 1, 0]}
                    },
                    "openai_cost": {
                        "$sum": {"$cond": [{"$eq": ["$provider", "openai"]}, "$estimated_cost_usd", 0]}
                    },
                    "gemini_cost": {
                        "$sum": {"$cond": [{"$eq": ["$provider", "gemini"]}, "$estimated_cost_usd", 0]}
                    }
                }
            },
            {"$sort": {sort_by.replace("total_cost", "total_cost"): -1}},
            {"$skip": skip},
            {"$limit": limit}
        ]
        
        # [FIX] Async aggregation
        cursor = ai_usage_collection.aggregate(pipeline)
        results = await cursor.to_list(length=limit)
        
        # Get user details
        user_stats = []
        for result in results:
            # [FIX] Added await
            user = await users_collection.find_one({"_id": result["_id"]})
            if user:
                user_stats.append(UserAIUsageStats(
                    user_id=result["_id"],
                    user_name=user["name"],
                    user_email=user["email"],
                    total_requests=result["total_requests"],
                    total_input_tokens=result["total_input_tokens"],
                    total_output_tokens=result["total_output_tokens"],
                    total_tokens=result["total_tokens"],
                    total_cost_usd=round(result["total_cost"], 4),
                    weekly_insights_count=result["weekly_insights"],
                    monthly_insights_count=result["monthly_insights"],
                    chat_requests_count=result["chat_requests"],
                    translation_count=result["translations"],
                    openai_cost=round(result["openai_cost"], 4),
                    gemini_cost=round(result["gemini_cost"], 4)
                ))
        
        return user_stats
        
    except Exception as e:
        print(f"Error getting users AI usage: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get users AI usage"
        )


@router.get("/ai-usage/user/{user_id}", response_model=List[AIUsageResponse])
async def get_user_ai_usage_detail(
    user_id: str = Path(...),
    current_admin: dict = Depends(require_admin_or_super),
    limit: int = Query(100, ge=1, le=500),
    feature_type: Optional[AIFeatureType] = Query(None)
):
    """Get detailed AI usage for a specific user"""
    try:
        query = {"user_id": user_id}
        if feature_type:
            query["feature_type"] = feature_type.value
        
        # [FIX] Async find and sort
        cursor = ai_usage_collection.find(query).sort("created_at", -1).limit(limit)
        usage_records = await cursor.to_list(length=limit)
        
        return [
            AIUsageResponse(
                id=record["_id"],
                user_id=record["user_id"],
                feature_type=AIFeatureType(record["feature_type"]),
                provider=AIProviderType(record["provider"]),
                model_name=record["model_name"],
                input_tokens=record["input_tokens"],
                output_tokens=record["output_tokens"],
                total_tokens=record["total_tokens"],
                estimated_cost_usd=record["estimated_cost_usd"],
                created_at=record["created_at"]
            )
            for record in usage_records
        ]
        
    except Exception as e:
        print(f"Error getting user AI usage detail: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get user AI usage detail"
        )
    


@router.get("/ai-usage/stats/budgets", response_model=Dict)
async def get_budget_ai_usage_stats(
    current_admin: dict = Depends(require_admin_or_super),
    start_date: Optional[datetime] = Query(None),
    end_date: Optional[datetime] = Query(None)
):
    """Get AI usage statistics specifically for budget features"""
    try:
        query = {
            "feature_type": {"$in": ["budget_suggestion", "budget_auto_create"]}
        }
        
        if start_date or end_date:
            query["created_at"] = {}
            if start_date:
                query["created_at"]["$gte"] = start_date
            if end_date:
                query["created_at"]["$lte"] = end_date
        
        pipeline = [
            {"$match": query},
            {
                "$group": {
                    "_id": "$feature_type",
                    "total_requests": {"$sum": 1},
                    "total_tokens": {"$sum": "$total_tokens"},
                    "total_cost": {"$sum": "$estimated_cost_usd"},
                    "unique_users": {"$addToSet": "$user_id"}
                }
            }
        ]
        
        # [FIX] Async aggregation
        cursor = ai_usage_collection.aggregate(pipeline)
        results = await cursor.to_list(length=None)
        
        stats = {
            "budget_suggestion": {"requests": 0, "tokens": 0, "cost": 0.0, "unique_users": 0},
            "budget_auto_create": {"requests": 0, "tokens": 0, "cost": 0.0, "unique_users": 0},
            "total": {"requests": 0, "tokens": 0, "cost": 0.0, "unique_users": set()}
        }
        
        for result in results:
            feature = result["_id"]
            stats[feature]["requests"] = result["total_requests"]
            stats[feature]["tokens"] = result["total_tokens"]
            stats[feature]["cost"] = round(result["total_cost"], 4)
            stats[feature]["unique_users"] = len(result["unique_users"])
            
            stats["total"]["requests"] += result["total_requests"]
            stats["total"]["tokens"] += result["total_tokens"]
            stats["total"]["cost"] += result["total_cost"]
            stats["total"]["unique_users"].update(result["unique_users"])
        
        stats["total"]["unique_users"] = len(stats["total"]["unique_users"])
        stats["total"]["cost"] = round(stats["total"]["cost"], 4)
        
        return stats
        
    except Exception as e:
        print(f"Error getting budget AI usage stats: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get budget AI usage statistics"
        )
    


@router.get("/ai-usage/stats/transactions", response_model=Dict)
async def get_transaction_extraction_ai_usage_stats(
    current_admin: dict = Depends(require_admin_or_super),
    start_date: Optional[datetime] = Query(None),
    end_date: Optional[datetime] = Query(None)
):
    """Get AI usage statistics specifically for transaction extraction features"""
    try:
        query = {
            "feature_type": {
                "$in": [
                    "transaction_text_extraction",
                    "transaction_image_extraction",
                    "transaction_audio_transcription"
                ]
            }
        }
        
        if start_date or end_date:
            query["created_at"] = {}
            if start_date:
                query["created_at"]["$gte"] = start_date
            if end_date:
                query["created_at"]["$lte"] = end_date
        
        pipeline = [
            {"$match": query},
            {
                "$group": {
                    "_id": "$feature_type",
                    "total_requests": {"$sum": 1},
                    "total_tokens": {"$sum": "$total_tokens"},
                    "total_cost": {"$sum": "$estimated_cost_usd"},
                    "unique_users": {"$addToSet": "$user_id"}
                }
            }
        ]
        
        # [FIX] Async aggregation
        cursor = ai_usage_collection.aggregate(pipeline)
        results = await cursor.to_list(length=None)
        
        stats = {
            "transaction_text_extraction": {"requests": 0, "tokens": 0, "cost": 0.0, "unique_users": 0},
            "transaction_image_extraction": {"requests": 0, "tokens": 0, "cost": 0.0, "unique_users": 0},
            "transaction_audio_transcription": {"requests": 0, "tokens": 0, "cost": 0.0, "unique_users": 0},
            "total": {"requests": 0, "tokens": 0, "cost": 0.0, "unique_users": set()}
        }
        
        for result in results:
            feature = result["_id"]
            stats[feature]["requests"] = result["total_requests"]
            stats[feature]["tokens"] = result["total_tokens"]
            stats[feature]["cost"] = round(result["total_cost"], 4)
            stats[feature]["unique_users"] = len(result["unique_users"])
            
            stats["total"]["requests"] += result["total_requests"]
            stats["total"]["tokens"] += result["total_tokens"]
            stats["total"]["cost"] += result["total_cost"]
            stats["total"]["unique_users"].update(result["unique_users"])
        
        stats["total"]["unique_users"] = len(stats["total"]["unique_users"])
        stats["total"]["cost"] = round(stats["total"]["cost"], 4)
        
        return stats
        
    except Exception as e:
        print(f"Error getting transaction extraction AI usage stats: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get transaction extraction AI usage statistics"
        )


# ==================== ADMIN ACTION LOGS ====================

@router.get("/logs", response_model=List[AdminActionLog])
async def get_admin_logs(
    current_admin: dict = Depends(require_super_admin),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100)
):
    """Get admin action logs (super admin only)"""
    # [FIX] Async cursor sort/skip/limit
    cursor = admin_action_logs_collection.find().sort("timestamp", -1).skip(skip).limit(limit)
    logs = await cursor.to_list(length=limit)
    
    return [
        AdminActionLog(
            id=log["_id"],
            admin_id=log["admin_id"],
            admin_email=log["admin_email"],
            action=log["action"],
            target_user_id=log.get("target_user_id"),
            target_user_email=log.get("target_user_email"),
            details=log.get("details"),
            timestamp=log["timestamp"]
        )
        for log in logs
    ]
    
    
# ==================== FEEDBACK MANAGEMENT ====================

@router.get("/feedback", response_model=List[AdminFeedbackListResponse])
async def get_all_feedback(
    current_admin: dict = Depends(require_admin_or_super),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    category: Optional[str] = None
):
    """Get all user feedback"""
    query = {}
    if category:
        query["category"] = category
        
    # [FIX] Async find sort/skip/limit
    cursor = feedback_collection.find(query).sort("created_at", -1).skip(skip).limit(limit)
    feedbacks = await cursor.to_list(length=limit)
    
    return [
        AdminFeedbackListResponse(
            id=fb["_id"],
            user_id=fb["user_id"],
            user_name=fb.get("user_name", "Unknown"),
            user_email=fb.get("user_email", "Unknown"),
            category=fb["category"],
            message=fb["message"],
            rating=fb.get("rating"),
            created_at=fb["created_at"],
            status=fb.get("status", "pending")
        )
        for fb in feedbacks
    ]

@router.put("/feedback/{feedback_id}/status")
async def update_feedback_status(
    feedback_id: str = Path(...),
    status_update: str = Query(..., regex="^(pending|reviewed|resolved)$"),
    current_admin: dict = Depends(require_admin_or_super)
):
    """Update feedback status"""
    # [FIX] Added await
    result = await feedback_collection.update_one(
        {"_id": feedback_id},
        {"$set": {"status": status_update}}
    )
    
    if result.modified_count == 0:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Feedback not found"
        )
        
    return {"message": "Feedback status updated"}

@router.delete("/feedback/{feedback_id}")
async def delete_feedback(
    feedback_id: str = Path(...),
    current_admin: dict = Depends(require_super_admin)
):
    """Delete feedback (Super Admin only)"""
    # [FIX] Added await
    result = await feedback_collection.delete_one({"_id": feedback_id})
    
    if result.deleted_count == 0:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Feedback not found"
        )
        
    return {"message": "Feedback deleted successfully"}