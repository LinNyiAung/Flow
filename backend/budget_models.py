from pydantic import BaseModel
from typing import Any, Optional, List, Dict
from datetime import datetime
from enum import Enum

from models import Currency

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
    main_category: str
    allocated_amount: float
    spent_amount: float = 0.0
    percentage_used: float = 0.0
    is_exceeded: bool = False

class BudgetCreate(BaseModel):
    name: str
    period: BudgetPeriod
    start_date: datetime
    end_date: Optional[datetime] = None
    category_budgets: List[CategoryBudget]
    total_budget: float
    description: Optional[str] = None
    auto_create_enabled: bool = False
    auto_create_with_ai: bool = False
    currency: Currency  # NEW

class BudgetUpdate(BaseModel):
    name: Optional[str] = None
    category_budgets: Optional[List[CategoryBudget]] = None
    total_budget: Optional[float] = None
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
    analysis_months: Optional[int] = 3
    user_context: Optional[str] = None
    currency: Currency  # NEW

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