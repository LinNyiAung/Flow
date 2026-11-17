from pydantic import BaseModel, Field, field_validator
from typing import Any, Dict, Optional
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
    MONTHLY_INSIGHTS_GENERATED = "monthly_insights_generated"
    SYSTEM_BROADCAST = "system_broadcast"  # NEW
    ADMIN_ANNOUNCEMENT = "admin_announcement"  # NEW
    SUBSCRIPTION_EXPIRED = "subscription_expired"
    TRIAL_ENDING_SOON = "trial_ending_soon"
    TRIAL_ENDS_TODAY = "trial_ends_today"
    PLAN_ENDING_SOON = "plan_ending_soon"
    PLAN_ENDS_TODAY = "plan_ends_today"
    PLAN_ACTIVATED = "plan_activated"
    UPGRADE_REQUEST_DECLINED = "upgrade_request_declined"
    CUSTOM_INSIGHT_READY = "custom_insight_ready"
    CUSTOM_INSIGHT_FAILED = "custom_insight_failed"
    FAMILY_INVITE = "family_invite"  # subject_id: the invite id, goal_name: the family name
    FAMILY_INVITE_ACCEPTED = "family_invite_accepted"  # subject_id: the family id
    FAMILY_REMOVED = "family_removed"  # subject_id: the family id
    FAMILY_OWNER = "family_owner"  # subject_id: the family id (the owner's account was deleted; you own it now)

def parse_notification_type(value) -> NotificationType:
    """
    Map a stored notification type to the enum. Unknown/legacy values (e.g. a custom
    admin broadcast type) fall back to SYSTEM_BROADCAST so listing never fails.
    """
    try:
        return NotificationType(value)
    except ValueError:
        return NotificationType.SYSTEM_BROADCAST


class FcmTokenUpdate(BaseModel):
    """Body for POST /api/auth/update-fcm-token. previous_token: the token this device registered before (after a
    Firebase token refresh), so its row takes the new token."""
    fcm_token: str = Field(..., min_length=1, max_length=4096)
    previous_token: Optional[str] = Field(None, max_length=4096)

    @field_validator("fcm_token")
    @classmethod
    def _strip_non_empty(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("fcm_token must not be empty")
        return v

    @field_validator("previous_token")
    @classmethod
    def _blank_is_none(cls, v: Optional[str]) -> Optional[str]:
        return (v or "").strip() or None


class FcmTokenRemove(BaseModel):
    """Body for DELETE /api/auth/fcm-token (logout): the token of the device signing out."""
    fcm_token: str = Field(..., min_length=1, max_length=4096)

    @field_validator("fcm_token")
    @classmethod
    def _strip_non_empty(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("fcm_token must not be empty")
        return v


class NotificationResponse(BaseModel):
    id: str
    user_id: str
    type: NotificationType
    title: str
    message: str
    # The notice's subject (the goal, budget, entry, custom insight, invite or family it is about: the one typed link
    # set); None when it has none or the thing was deleted.
    subject_id: Optional[str] = None
    goal_name: Optional[str] = None
    currency: Optional[str] = None  # NEW - add currency field
    created_at: datetime
    is_read: bool
    # {"book": "family"} on a notice that belongs to a family book (open it in Family mode); None for personal ones.
    extra: Optional[Dict[str, Any]] = None