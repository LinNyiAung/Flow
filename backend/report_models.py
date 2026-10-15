from pydantic import BaseModel, Field, field_validator
from typing import Optional, List, Dict
from datetime import datetime
from enum import Enum

from models import Currency  # ADD THIS IMPORT

class ReportPeriod(str, Enum):
    WEEK = "week"
    MONTH = "month"
    YEAR = "year"
    CUSTOM = "custom"

class ReportRequest(BaseModel):
    period: ReportPeriod
    start_date: Optional[datetime] = None
    end_date: Optional[datetime] = None
    # Minutes EAST of UTC (Dart's DateTime.timeZoneOffset.inMinutes), e.g. +390 for Myanmar.
    timezone_offset: Optional[int] = Field(default=0, ge=-840, le=840)
    currency: Optional[Currency] = None  # NEW - optional currency filter

    @field_validator("timezone_offset", mode="after")
    @classmethod
    def _none_to_zero(cls, v):
        return 0 if v is None else v

class CategoryBreakdown(BaseModel):
    category: str
    main_category: str  # NEW - Add this field
    amount: float
    percentage: float
    transaction_count: int

class GoalProgress(BaseModel):
    goal_id: str
    name: str
    target_amount: float
    current_amount: float
    progress_percentage: float
    status: str
    currency: Currency  # NEW

class FinancialReport(BaseModel):
    period: ReportPeriod
    start_date: datetime
    end_date: datetime

    # Overall metrics
    total_inflow: float
    total_outflow: float
    net_balance: float

    # Category breakdowns
    inflow_by_category: List[CategoryBreakdown]
    outflow_by_category: List[CategoryBreakdown]

    # Goals
    goals: List[GoalProgress]
    total_allocated_to_goals: float

    # Transaction counts
    total_transactions: int
    inflow_count: int
    outflow_count: int

    # Top categories
    top_income_category: Optional[str] = None
    top_expense_category: Optional[str] = None

    # Daily averages
    average_daily_inflow: float
    average_daily_outflow: float

    currency: Currency  # NEW - which currency this report is for
    generated_at: datetime


# NEW - Multi-currency report models
class CurrencyReport(BaseModel):
    currency: Currency
    total_inflow: float
    total_outflow: float
    net_balance: float
    inflow_by_category: List[CategoryBreakdown]
    outflow_by_category: List[CategoryBreakdown]
    total_transactions: int
    inflow_count: int
    outflow_count: int
    average_daily_inflow: float
    average_daily_outflow: float

class MultiCurrencyFinancialReport(BaseModel):
    period: ReportPeriod
    start_date: datetime
    end_date: datetime
    currency_reports: List[CurrencyReport]
    goals: List[GoalProgress]  # All goals across currencies
    total_transactions: int
    generated_at: datetime
