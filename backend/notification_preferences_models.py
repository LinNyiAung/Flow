from pydantic import BaseModel
from typing import Dict, Optional
from datetime import datetime

class NotificationPreferences(BaseModel):
    # Goal notifications
    goal_progress: bool = True
    goal_milestone: bool = True
    goal_approaching_date: bool = True
    goal_achieved: bool = True
    
    # Budget notifications
    budget_started: bool = True
    budget_ending_soon: bool = True
    budget_threshold: bool = True
    budget_exceeded: bool = True
    budget_auto_created: bool = True
    budget_now_active: bool = True
    
    # Transaction notifications
    large_transaction: bool = True
    unusual_spending: bool = True
    payment_reminder: bool = True
    recurring_transaction_created: bool = True
    recurring_transaction_ended: bool = True
    recurring_transaction_disabled: bool = True

class NotificationPreferencesResponse(BaseModel):
    user_id: str
    preferences: NotificationPreferences
    updated_at: datetime

class NotificationPreferencesUpdate(BaseModel):
    preferences: Dict[str, bool]