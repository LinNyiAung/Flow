from enum import Enum
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime

class RecurrenceFrequency(str, Enum):
    DAILY = "daily"
    WEEKLY = "weekly"
    MONTHLY = "monthly"
    ANNUALLY = "annually"

class RecurrenceConfig(BaseModel):
    frequency: RecurrenceFrequency
    day_of_week: Optional[int] = Field(default=None, ge=0, le=6)  # 0-6 for Monday-Sunday (weekly)
    day_of_month: Optional[int] = Field(default=None, ge=1, le=31)  # 1-31 (monthly)
    month: Optional[int] = Field(default=None, ge=1, le=12)  # 1-12 (annually)
    day_of_year: Optional[int] = Field(default=None, ge=1, le=31)  # 1-31 (annually, day within `month`)
    end_date: Optional[datetime] = None  # Optional end date for recurrence

class TransactionRecurrence(BaseModel):
    enabled: bool = False
    config: Optional[RecurrenceConfig] = None
    # Server-managed fields: ignored when sent by clients on create/update.
    last_created_date: Optional[datetime] = None
    parent_transaction_id: Optional[str] = None  # For auto-created transactions


class RecurrencePreviewRequest(BaseModel):
    start_date: datetime
    frequency: RecurrenceFrequency
    day_of_week: Optional[int] = Field(default=None, ge=0, le=6)
    day_of_month: Optional[int] = Field(default=None, ge=1, le=31)
    month: Optional[int] = Field(default=None, ge=1, le=12)
    day_of_year: Optional[int] = Field(default=None, ge=1, le=31)
    end_date: Optional[datetime] = None
