from pydantic import BaseModel, EmailStr
from typing import Optional, List
from datetime import datetime
from enum import Enum

from models import SubscriptionType, Currency


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