from pydantic import BaseModel, field_validator
from typing import List, Optional
from datetime import datetime
from enum import Enum

from models import Currency, FiniteAmount, NonNegativeAmount, PositiveAmount

class GoalType(str, Enum):
    SAVINGS = "savings"
    DEBT_REDUCTION = "debt_reduction"
    LARGE_PURCHASE = "large_purchase"

class GoalStatus(str, Enum):
    ACTIVE = "active"
    ACHIEVED = "achieved"

class GoalCreate(BaseModel):
    name: str
    target_amount: PositiveAmount
    target_date: Optional[datetime] = None
    goal_type: GoalType
    initial_contribution: Optional[NonNegativeAmount] = 0.0
    currency: Currency = Currency.USD  # NEW

    @field_validator("initial_contribution", mode="after")
    @classmethod
    def _none_to_zero(cls, v):
        return 0.0 if v is None else v

class GoalUpdate(BaseModel):
    name: Optional[str] = None
    target_amount: Optional[PositiveAmount] = None
    target_date: Optional[datetime] = None
    goal_type: Optional[GoalType] = None

class GoalContribution(BaseModel):
    amount: FiniteAmount  # Positive for adding, negative for reducing

    @field_validator("amount", mode="after")
    @classmethod
    def _non_zero(cls, v: float) -> float:
        if round(v, 2) == 0:
            raise ValueError("Contribution amount must not be zero")
        return v

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
    currency: Currency  # NEW

class GoalsSummary(BaseModel):
    total_goals: int
    active_goals: int
    achieved_goals: int
    total_allocated: float
    total_target: float
    overall_progress: float
    currency: Optional[Currency] = None  # NEW - for currency-specific summary


class CurrencySummary(BaseModel):
    currency: Currency
    active_goals: int
    achieved_goals: int
    total_allocated: float
    total_target: float
    overall_progress: float

class MultiCurrencyGoalsSummary(BaseModel):
    total_goals: int
    active_goals: int
    achieved_goals: int
    currency_summaries: List[CurrencySummary]  # Per-currency breakdown
