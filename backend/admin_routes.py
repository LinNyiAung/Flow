import uuid
from datetime import datetime, timedelta, UTC
from typing import List, Optional

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
    notifications_collection
)
from config import settings

router = APIRouter(prefix="/api/admin", tags=["admin"])


# ==================== ADMIN AUTHENTICATION ====================

@router.post("/login", response_model=AdminToken)
async def admin_login(credentials: AdminLogin):
    """Admin login"""
    admin = admins_collection.find_one({"email": credentials.email})
    
    if not admin or not verify_password(credentials.password, admin["password"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password"
        )
    
    # Update last login
    admins_collection.update_one(
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
    admins_collection.update_one(
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
        if admins_collection.find_one({"email": update_data.email}):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already in use"
            )
        update_fields["email"] = update_data.email
        
    if not update_fields:
        # No changes needed, return current info
        return AdminResponse(
            id=current_admin["_id"],
            name=current_admin["name"],
            email=current_admin["email"],
            role=AdminRole(current_admin["role"]),
            created_at=current_admin["created_at"],
            last_login=current_admin.get("last_login")
        )

    admins_collection.update_one(
        {"_id": current_admin["_id"]},
        {"$set": update_fields}
    )
    
    # Log action
    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"], # Log using the old email for continuity
        action="updated_profile",
        details=f"Updated profile fields: {', '.join(update_fields.keys())}"
    )
    
    # Fetch updated document
    updated_admin = admins_collection.find_one({"_id": current_admin["_id"]})
    
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
    if admins_collection.find_one({"email": admin_data.email}):
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
    
    admins_collection.insert_one(new_admin)
    
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
    admins = list(admins_collection.find())
    
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
    
    admin_to_delete = admins_collection.find_one({"_id": admin_id})
    if not admin_to_delete:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Admin not found"
        )
    
    result = admins_collection.delete_one({"_id": admin_id})
    
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
    
    users = list(users_collection.find(query).skip(skip).limit(limit).sort("created_at", -1))
    
    user_list = []
    for user in users:
        # Get transaction count
        transaction_count = transactions_collection.count_documents({"user_id": user["_id"]})
        
        # Get goals count
        goals_count = goals_collection.count_documents({"user_id": user["_id"]})
        
        # Get last active (from last transaction or chat)
        last_transaction = transactions_collection.find_one(
            {"user_id": user["_id"]},
            sort=[("created_at", -1)]
        )
        last_chat = chat_sessions_collection.find_one(
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
    user = users_collection.find_one({"_id": user_id})
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    # Get counts
    transaction_count = transactions_collection.count_documents({"user_id": user_id})
    goals_count = goals_collection.count_documents({"user_id": user_id})
    budgets_count = budgets_collection.count_documents({"user_id": user_id})
    chat_sessions_count = chat_sessions_collection.count_documents({"user_id": user_id})
    
    # Get last active
    last_transaction = transactions_collection.find_one(
        {"user_id": user_id},
        sort=[("created_at", -1)]
    )
    last_chat = chat_sessions_collection.find_one(
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
    user = users_collection.find_one({"_id": user_id})
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    update_data = {
        "subscription_type": subscription_data.subscription_type.value,
        "subscription_expires_at": subscription_data.subscription_expires_at
    }
    
    users_collection.update_one(
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
    user = users_collection.find_one({"_id": user_id})
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    # Delete all user data
    transactions_collection.delete_many({"user_id": user_id})
    goals_collection.delete_many({"user_id": user_id})
    budgets_collection.delete_many({"user_id": user_id})
    chat_sessions_collection.delete_many({"user_id": user_id})
    notifications_collection.delete_many({"user_id": user_id})
    
    # Delete user
    result = users_collection.delete_one({"_id": user_id})
    
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
    total_users = users_collection.count_documents({})
    free_users = users_collection.count_documents({"subscription_type": "free"})
    premium_users = users_collection.count_documents({"subscription_type": "premium"})
    
    # Users created in last 30 days
    thirty_days_ago = datetime.now(UTC) - timedelta(days=30)
    new_users_last_30_days = users_collection.count_documents({
        "created_at": {"$gte": thirty_days_ago}
    })
    
    # Active users in last 7 days
    seven_days_ago = datetime.now(UTC) - timedelta(days=7)
    active_user_ids = set()
    
    # Get users with recent transactions
    recent_transactions = transactions_collection.find({
        "created_at": {"$gte": seven_days_ago}
    }, {"user_id": 1})
    for t in recent_transactions:
        active_user_ids.add(t["user_id"])
    
    # Get users with recent chat activity
    recent_chats = chat_sessions_collection.find({
        "updated_at": {"$gte": seven_days_ago}
    }, {"user_id": 1})
    for c in recent_chats:
        active_user_ids.add(c["user_id"])
    
    active_users_last_7_days = len(active_user_ids)
    
    total_transactions = transactions_collection.count_documents({})
    total_goals = goals_collection.count_documents({})
    
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
    
    # User stats
    total_users = users_collection.count_documents({})
    free_users = users_collection.count_documents({"subscription_type": "free"})
    premium_users = users_collection.count_documents({"subscription_type": "premium"})
    
    new_users_today = users_collection.count_documents({"created_at": {"$gte": today_start}})
    new_users_this_week = users_collection.count_documents({"created_at": {"$gte": week_start}})
    new_users_this_month = users_collection.count_documents({"created_at": {"$gte": month_start}})
    
    # Activity stats
    active_today = set()
    active_week = set()
    
    # Recent transactions
    for t in transactions_collection.find({"created_at": {"$gte": today_start}}, {"user_id": 1}):
        active_today.add(t["user_id"])
    
    for t in transactions_collection.find({"created_at": {"$gte": week_start}}, {"user_id": 1}):
        active_week.add(t["user_id"])
    
    # Recent chats
    for c in chat_sessions_collection.find({"updated_at": {"$gte": today_start}}, {"user_id": 1}):
        active_today.add(c["user_id"])
    
    for c in chat_sessions_collection.find({"updated_at": {"$gte": week_start}}, {"user_id": 1}):
        active_week.add(c["user_id"])
    
    # Total counts
    total_transactions = transactions_collection.count_documents({})
    total_goals = goals_collection.count_documents({})
    total_budgets = budgets_collection.count_documents({})
    total_chat_sessions = chat_sessions_collection.count_documents({})
    total_notifications = notifications_collection.count_documents({})
    
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
        # else "all" - no filter
        
        # Get target users
        users = list(users_collection.find(query))
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
            
            # Check if user has this notification type enabled
            if not should_send_notification(user_id, broadcast_data.notification_type):
                continue
            
            # Create in-app notification
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
            
            notifications_collection.insert_one(notification)
            notifications_sent += 1
            
            # Collect FCM token if available
            if user.get("fcm_token"):
                fcm_tokens.append(user["fcm_token"])
        
        # Send FCM push notifications in batch
        fcm_result = {"success": 0, "failure": 0}
        if fcm_tokens:
            fcm_data = {
                "type": broadcast_data.notification_type,
                "is_broadcast": "true"
            }
            fcm_result = send_fcm_to_multiple(
                fcm_tokens=fcm_tokens,
                title=broadcast_data.title,
                body=broadcast_data.message,
                data=fcm_data
            )
        
        # Log admin action
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
        total_users = users_collection.count_documents({})
        free_users = users_collection.count_documents({"subscription_type": "free"})
        premium_users = users_collection.count_documents({"subscription_type": "premium"})
        
        # Count users with FCM tokens
        users_with_fcm = users_collection.count_documents({"fcm_token": {"$exists": True, "$ne": None}})
        free_with_fcm = users_collection.count_documents({
            "subscription_type": "free",
            "fcm_token": {"$exists": True, "$ne": None}
        })
        premium_with_fcm = users_collection.count_documents({
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


# ==================== ADMIN ACTION LOGS ====================

@router.get("/logs", response_model=List[AdminActionLog])
async def get_admin_logs(
    current_admin: dict = Depends(require_super_admin),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100)
):
    """Get admin action logs (super admin only)"""
    logs = list(
        admin_action_logs_collection
        .find()
        .sort("timestamp", -1)
        .skip(skip)
        .limit(limit)
    )
    
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