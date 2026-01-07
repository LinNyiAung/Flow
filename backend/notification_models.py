from pydantic import BaseModel
from typing import Optional
from datetime import datetime
from enum import Enum

class NotificationType(str, Enum):
    GOAL_PROGRESS = "goal_progress"
    GOAL_MILESTONE = "goal_milestone"
    GOAL_APPROACHING_DATE = "goal_approaching_date"
    GOAL_ACHIEVED = "goal_achieved"
    BUDGET_STARTED = "budget_started"
    BUDGET_ENDING_SOON = "budget_ending_soon"
    BUDGET_THRESHOLD = "budget_threshold"
    BUDGET_EXCEEDED = "budget_exceeded"
    BUDGET_AUTO_CREATED = "budget_auto_created"
    BUDGET_NOW_ACTIVE = "budget_now_active"
    LARGE_TRANSACTION = "large_transaction"
    UNUSUAL_SPENDING = "unusual_spending"
    PAYMENT_REMINDER = "payment_reminder"
    RECURRING_TRANSACTION_CREATED = "recurring_transaction_created"
    RECURRING_TRANSACTION_ENDED = "recurring_transaction_ended"
    RECURRING_TRANSACTION_DISABLED = "recurring_transaction_disabled"
    WEEKLY_INSIGHTS_GENERATED = "weekly_insights_generated"

class NotificationResponse(BaseModel):
    id: str
    user_id: str
    type: NotificationType
    title: str
    message: str
    goal_id: Optional[str] = None
    goal_name: Optional[str] = None
    currency: Optional[str] = None  # NEW - add currency field
    created_at: datetime
    is_read: bool