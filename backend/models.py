from pydantic import BaseModel, EmailStr
from typing import Optional, List
from datetime import datetime
from enum import Enum

from recurrence_models import TransactionRecurrence

class TransactionType(str, Enum):
    INFLOW = "inflow"
    OUTFLOW = "outflow"

# NEW: Add subscription type enum
class SubscriptionType(str, Enum):
    FREE = "free"
    PREMIUM = "premium"

class UserCreate(BaseModel):
    name: str
    email: EmailStr
    password: str

class UserLogin(BaseModel):
    email: EmailStr
    password: str

class UserResponse(BaseModel):
    id: str
    name: str
    email: str
    created_at: datetime
    subscription_type: SubscriptionType  # NEW
    subscription_expires_at: Optional[datetime] = None  # NEW
    
    

# NEW: Subscription update model
class SubscriptionUpdate(BaseModel):
    subscription_type: SubscriptionType
    subscription_expires_at: Optional[datetime] = None

# NEW: Profile update model
class ProfileUpdate(BaseModel):
    name: str
    
    
class PasswordChange(BaseModel):
    current_password: str
    new_password: str
    confirm_password: str

class Token(BaseModel):
    access_token: str
    token_type: str
    user: UserResponse

# NEW: Subscription update model
class SubscriptionUpdate(BaseModel):
    subscription_type: SubscriptionType
    subscription_expires_at: Optional[datetime] = None

class TransactionCreate(BaseModel):
    type: TransactionType
    main_category: str
    sub_category: str
    date: datetime
    description: Optional[str] = None
    recurrence: Optional[TransactionRecurrence] = None
    amount: float

class TransactionUpdate(BaseModel):
    type: Optional[TransactionType] = None
    main_category: Optional[str] = None
    sub_category: Optional[str] = None
    date: Optional[datetime] = None
    description: Optional[str] = None
    recurrence: Optional[TransactionRecurrence] = None
    amount: Optional[float] = None

class TransactionResponse(BaseModel):
    id: str
    user_id: str
    type: TransactionType
    main_category: str
    sub_category: str
    date: datetime
    description: Optional[str]
    recurrence: Optional[TransactionRecurrence] = None
    parent_transaction_id: Optional[str] = None
    amount: float
    created_at: datetime
    updated_at: datetime

class CategoryResponse(BaseModel):
    main_category: str
    sub_categories: List[str]

class TransactionExtraction(BaseModel):
    type: str
    main_category: str
    sub_category: str
    date: datetime
    description: Optional[str] = None
    amount: float
    confidence: float
    reasoning: Optional[str] = None

class TextExtractionRequest(BaseModel):
    text: str

class MultipleTransactionExtraction(BaseModel):
    transactions: List[TransactionExtraction]
    total_count: int
    overall_confidence: float
    analysis: Optional[str] = None