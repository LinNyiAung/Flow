from pydantic import BaseModel
from typing import Optional
from datetime import datetime
from enum import Enum

class GoalType(str, Enum):
    SAVINGS = "savings"
    DEBT_REDUCTION = "debt_reduction"
    LARGE_PURCHASE = "large_purchase"

class GoalStatus(str, Enum):
    ACTIVE = "active"
    ACHIEVED = "achieved"

class GoalCreate(BaseModel):
    name: str
    target_amount: float
    target_date: Optional[datetime] = None
    goal_type: GoalType
    initial_contribution: Optional[float] = 0.0

class GoalUpdate(BaseModel):
    name: Optional[str] = None
    target_amount: Optional[float] = None
    target_date: Optional[datetime] = None
    goal_type: Optional[GoalType] = None

class GoalContribution(BaseModel):
    amount: float  # Positive for adding, negative for reducing

class GoalResponse(BaseModel):
    id: str
    user_id: str
    name: str
    target_amount: float
    current_amount: float
    target_date: Optional[datetime]
    goal_type: GoalType
    status: GoalStatus
    progress_percentage: float
    created_at: datetime
    updated_at: datetime
    achieved_at: Optional[datetime] = None

class GoalsSummary(BaseModel):
    total_goals: int
    active_goals: int
    achieved_goals: int
    total_allocated: float
    total_target: float
    overall_progress: float