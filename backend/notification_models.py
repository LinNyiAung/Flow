from pydantic import BaseModel
from typing import Optional
from datetime import datetime
from enum import Enum

class NotificationType(str, Enum):
    GOAL_PROGRESS = "goal_progress"
    GOAL_MILESTONE = "goal_milestone"
    GOAL_APPROACHING_DATE = "goal_approaching_date"
    GOAL_ACHIEVED = "goal_achieved"

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