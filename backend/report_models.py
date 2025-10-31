from pydantic import BaseModel
from typing import Optional, List, Dict
from datetime import datetime
from enum import Enum

class ReportPeriod(str, Enum):
    WEEK = "week"
    MONTH = "month"
    YEAR = "year"
    CUSTOM = "custom"

class ReportRequest(BaseModel):
    period: ReportPeriod
    start_date: Optional[datetime] = None
    end_date: Optional[datetime] = None
    timezone_offset: Optional[int] = 0

class CategoryBreakdown(BaseModel):
    category: str
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
    
    generated_at: datetime