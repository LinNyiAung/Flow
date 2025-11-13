from enum import Enum
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class RecurrenceFrequency(str, Enum):
    DAILY = "daily"
    WEEKLY = "weekly"
    MONTHLY = "monthly"
    ANNUALLY = "annually"

class RecurrenceConfig(BaseModel):
    frequency: RecurrenceFrequency
    day_of_week: Optional[int] = None  # 0-6 for Monday-Sunday (weekly)
    day_of_month: Optional[int] = None  # 1-31 (monthly)
    month: Optional[int] = None  # 1-12 (annually)
    day_of_year: Optional[int] = None  # 1-31 (annually)
    end_date: Optional[datetime] = None  # Optional end date for recurrence

class TransactionRecurrence(BaseModel):
    enabled: bool = False
    config: Optional[RecurrenceConfig] = None
    last_created_date: Optional[datetime] = None
    parent_transaction_id: Optional[str] = None  # For auto-created transactions
    
    
class RecurrencePreviewRequest(BaseModel):
    start_date: datetime
    frequency: RecurrenceFrequency
    day_of_week: Optional[int] = None
    day_of_month: Optional[int] = None
    month: Optional[int] = None
    day_of_year: Optional[int] = None
    end_date: Optional[datetime] = None