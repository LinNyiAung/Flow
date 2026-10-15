from pydantic import BaseModel, Field, field_validator, model_validator
from typing import Any, Optional, List, Dict
from datetime import datetime, timezone
from enum import Enum

from models import Currency, NonNegativeAmount


def _as_utc(dt: datetime) -> datetime:
    return dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt.astimezone(timezone.utc)


def _validate_period_dates(period, start_date: datetime, end_date: Optional[datetime]):
    """Shared validation for budget create / AI-suggest requests."""
    if period == BudgetPeriod.CUSTOM and end_date is None:
        raise ValueError("end_date is required for custom budgets")
    if end_date is not None and _as_utc(end_date) < _as_utc(start_date):
        raise ValueError("end_date must be on or after start_date")

class BudgetPeriod(str, Enum):
    WEEKLY = "weekly"
    MONTHLY = "monthly"
    YEARLY = "yearly"
    CUSTOM = "custom"

class BudgetStatus(str, Enum):
    UPCOMING = "upcoming"
    ACTIVE = "active"
    COMPLETED = "completed"
    EXCEEDED = "exceeded"

class CategoryBudget(BaseModel):
    """Stored / response shape (lenient so legacy documents never break reads)."""
    main_category: str
    allocated_amount: float
    spent_amount: float = 0.0
    percentage_used: float = 0.0
    is_exceeded: bool = False

class CategoryBudgetIn(CategoryBudget):
    """Client / AI input: allocated_amount must be finite and >= 0."""
    allocated_amount: NonNegativeAmount

class BudgetCreate(BaseModel):
    name: str
    period: BudgetPeriod
    start_date: datetime
    end_date: Optional[datetime] = None
    category_budgets: List[CategoryBudgetIn]
    total_budget: NonNegativeAmount
    description: Optional[str] = None
    auto_create_enabled: bool = False
    auto_create_with_ai: bool = False
    currency: Currency  # NEW

    @model_validator(mode="after")
    def _check_dates(self):
        _validate_period_dates(self.period, self.start_date, self.end_date)
        return self

class BudgetUpdate(BaseModel):
    name: Optional[str] = None
    category_budgets: Optional[List[CategoryBudgetIn]] = None
    # Rule: total_budget is the user's value. If omitted while category_budgets
    # is sent, it is recomputed from the category allocations (sub-categories
    # under a budgeted main category are not double counted).
    total_budget: Optional[NonNegativeAmount] = None
    description: Optional[str] = None
    auto_create_enabled: Optional[bool] = None
    auto_create_with_ai: Optional[bool] = None
    # Note: currency cannot be changed after creation

class BudgetResponse(BaseModel):
    id: str
    user_id: str
    name: str
    period: BudgetPeriod
    start_date: datetime
    end_date: datetime
    category_budgets: List[CategoryBudget]
    total_budget: float
    total_spent: float
    remaining_budget: float
    percentage_used: float
    status: BudgetStatus
    description: Optional[str]
    is_active: bool
    created_at: datetime
    updated_at: datetime
    auto_create_enabled: bool = False
    auto_create_with_ai: bool = False
    parent_budget_id: Optional[str] = None
    currency: Currency  # NEW

class BudgetSummary(BaseModel):
    total_budgets: int
    active_budgets: int
    completed_budgets: int
    exceeded_budgets: int
    upcoming_budgets: int
    total_allocated: float
    total_spent: float
    overall_remaining: float
    currency: Currency  # NEW - for filtered summary

class AIBudgetRequest(BaseModel):
    period: BudgetPeriod
    start_date: datetime
    end_date: Optional[datetime] = None
    name: Optional[str] = None
    description: Optional[str] = None
    include_categories: Optional[List[str]] = None
    analysis_months: Optional[int] = Field(default=3, ge=1, le=24)
    user_context: Optional[str] = None
    currency: Currency  # NEW

    @field_validator("analysis_months", mode="after")
    @classmethod
    def _default_months(cls, v):
        return 3 if v is None else v

    @model_validator(mode="after")
    def _check_dates(self):
        _validate_period_dates(self.period, self.start_date, self.end_date)
        return self

class AIBudgetSuggestion(BaseModel):
    suggested_name: str
    period: BudgetPeriod
    start_date: datetime
    end_date: datetime
    category_budgets: List[CategoryBudget]
    total_budget: float
    reasoning: str
    data_confidence: float
    warnings: List[str]
    analysis_summary: Dict[str, Any]
    currency: Currency  # NEW
    
    
class CurrencyBudgetSummary(BaseModel):
    currency: Currency
    total_budgets: int
    active_budgets: int
    completed_budgets: int
    exceeded_budgets: int
    upcoming_budgets: int
    total_allocated: float
    total_spent: float
    overall_remaining: float

class MultiCurrencyBudgetSummary(BaseModel):
    total_budgets: int
    active_budgets: int
    completed_budgets: int
    exceeded_budgets: int
    upcoming_budgets: int
    currency_summaries: List[CurrencyBudgetSummary]