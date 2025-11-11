from pydantic import BaseModel
from typing import Optional
from datetime import datetime
from enum import Enum

class NotificationType(str, Enum):
    GOAL_PROGRESS = "goal_progress"
    GOAL_MILESTONE = "goal_milestone"
    GOAL_APPROACHING_DATE = "goal_approaching_date"
    GOAL_ACHIEVED = "goal_achieved"
    BUDGET_STARTED = "budget_started"  # ADD THIS
    BUDGET_ENDING_SOON = "budget_ending_soon"  # ADD THIS
    BUDGET_THRESHOLD = "budget_threshold"  # ADD THIS
    BUDGET_EXCEEDED = "budget_exceeded"  # ADD THIS
    BUDGET_AUTO_CREATED = "budget_auto_created"  # ADD THIS
    BUDGET_NOW_ACTIVE = "budget_now_active"  # ADD THIS

class NotificationResponse(BaseModel):
    id: str
    user_id: str
    type: NotificationType
    title: str
    message: str
    goal_id: Optional[str] = None
    goal_name: Optional[str] = None
    created_at: datetime
    is_read: bool