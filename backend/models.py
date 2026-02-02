from pydantic import BaseModel, EmailStr
from typing import Optional, List
from datetime import datetime
from enum import Enum

from recurrence_models import TransactionRecurrence

class TransactionType(str, Enum):
    INFLOW = "inflow"
    OUTFLOW = "outflow"
    
    
class Currency(str, Enum):
    USD = "usd"
    MMK = "mmk"
    THB = "thb"  
    
class LanguageUpdate(BaseModel):
    language: str
    
class CurrencyUpdate(BaseModel):
    default_currency: Currency

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
    subscription_type: SubscriptionType
    subscription_expires_at: Optional[datetime] = None
    default_currency: Currency = Currency.USD  # NEW
    
    

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
    currency: Currency = Currency.USD  # NEW

class TransactionUpdate(BaseModel):
    type: Optional[TransactionType] = None
    main_category: Optional[str] = None
    sub_category: Optional[str] = None
    date: Optional[datetime] = None
    description: Optional[str] = None
    recurrence: Optional[TransactionRecurrence] = None
    amount: Optional[float] = None
    currency: Optional[Currency] = None  # NEW

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
    currency: Currency  # NEW
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
    currency: Currency = Currency.USD  # NEW
    confidence: float
    reasoning: Optional[str] = None

class TextExtractionRequest(BaseModel):
    text: str

class MultipleTransactionExtraction(BaseModel):
    transactions: List[TransactionExtraction]
    total_count: int
    overall_confidence: float
    analysis: Optional[str] = None
    
    
class FeedbackCategory(str, Enum):
    BUG = "bug"
    FEATURE = "feature_request"
    GENERAL = "general"
    USABILITY = "usability"

class FeedbackCreate(BaseModel):
    category: FeedbackCategory
    message: str
    rating: Optional[int] = None  # 1 to 5 stars
    screenshot_url: Optional[str] = None # Optional: if you plan to upload images later

class FeedbackResponse(BaseModel):
    id: str
    user_id: str
    category: FeedbackCategory
    message: str
    rating: Optional[int]
    created_at: datetime
    status: str = "pending" # pending, reviewed, resolved