from pydantic import BaseModel, EmailStr, field_validator
from typing import Literal, Optional, List
from datetime import datetime
from enum import Enum

from models import SubscriptionType, Currency
from notification_models import NotificationType


class AdminRole(str, Enum):
    SUPER_ADMIN = "super_admin"
    ADMIN = "admin"
    MODERATOR = "moderator"


class AdminCreate(BaseModel):
    name: str
    email: EmailStr
    password: str
    role: AdminRole = AdminRole.ADMIN


class AdminLogin(BaseModel):
    email: EmailStr
    password: str


class AdminResponse(BaseModel):
    id: str
    name: str
    email: str
    role: AdminRole
    created_at: datetime
    last_login: Optional[datetime] = None


class AdminToken(BaseModel):
    access_token: str
    token_type: str
    admin: AdminResponse


class AdminPasswordChange(BaseModel):
    current_password: str
    new_password: str
    confirm_password: str
    
    
class AdminUpdate(BaseModel):
    name: Optional[str] = None
    email: Optional[EmailStr] = None


class UserListResponse(BaseModel):
    id: str
    name: str
    email: str
    subscription_type: SubscriptionType
    subscription_expires_at: Optional[datetime] = None
    default_currency: Currency
    created_at: datetime
    total_transactions: int = 0
    total_goals: int = 0
    last_active: Optional[datetime] = None


class UserStatsResponse(BaseModel):
    total_users: int
    free_users: int
    premium_users: int
    new_users_last_30_days: int
    active_users_last_7_days: int
    total_transactions: int
    total_goals: int


class UserDetailResponse(BaseModel):
    id: str
    name: str
    email: str
    subscription_type: SubscriptionType
    subscription_expires_at: Optional[datetime] = None
    default_currency: Currency
    language: str
    created_at: datetime
    total_transactions: int
    total_goals: int
    total_budgets: int
    total_chat_sessions: int
    last_active: Optional[datetime] = None


class UpdateUserSubscriptionRequest(BaseModel):
    subscription_type: SubscriptionType
    subscription_expires_at: Optional[datetime] = None


class AdminActionLog(BaseModel):
    id: str
    admin_id: str
    admin_email: str
    action: str
    target_user_id: Optional[str] = None
    target_user_email: Optional[str] = None
    details: Optional[str] = None
    timestamp: datetime


class SystemStatsResponse(BaseModel):
    total_users: int
    free_users: int
    premium_users: int
    total_transactions: int
    total_goals: int
    total_budgets: int
    total_chat_sessions: int
    total_notifications: int
    new_users_today: int
    new_users_this_week: int
    new_users_this_month: int
    active_users_today: int
    active_users_this_week: int
    
    
class BroadcastNotificationRequest(BaseModel):
    title: str
    message: str
    target_users: Literal["all", "free", "premium"] = "all"
    notification_type: NotificationType = NotificationType.SYSTEM_BROADCAST

    @field_validator("title", "message")
    @classmethod
    def _not_blank(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("must not be empty")
        return v


class BroadcastNotificationResponse(BaseModel):
    message: str
    total_users: int
    notifications_sent: int
    fcm_sent: int
    fcm_failed: int
    
    
class AdminFeedbackListResponse(BaseModel):
    id: str
    user_id: str
    user_name: str
    user_email: str
    category: str
    message: str
    rating: Optional[int] = None
    created_at: datetime
    status: str


class FeedbackStatsResponse(BaseModel):
    total: int
    pending: int
    reviewed: int
    resolved: int
    average_rating: Optional[float] = None