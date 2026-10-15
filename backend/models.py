from pydantic import BaseModel, EmailStr
from pydantic import BeforeValidator as _BeforeValidator, Field as _Field, field_validator as _field_validator
from typing import Optional, List
from typing import Annotated as _Annotated, Literal as _Literal
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
    
def _normalize_email_input(value):
    """Strip whitespace and lowercase e-mail input before EmailStr validation."""
    if isinstance(value, str):
        return value.strip().lower()
    return value


# E-mail address normalised to lowercase (used by all user auth request bodies)
NormalizedEmail = _Annotated[EmailStr, _BeforeValidator(_normalize_email_input)]

# Languages accepted by PUT /api/auth/language
SUPPORTED_LANGUAGES = ("en", "my")


class LanguageUpdate(BaseModel):
    language: _Literal["en", "my"]

class CurrencyUpdate(BaseModel):
    default_currency: Currency

# NEW: Add subscription type enum
class SubscriptionType(str, Enum):
    FREE = "free"
    PREMIUM = "premium"

class UserCreate(BaseModel):
    name: str
    email: NormalizedEmail
    password: str = _Field(..., min_length=6)

class UserLogin(BaseModel):
    email: NormalizedEmail
    password: str

class UserResponse(BaseModel):
    id: str
    name: str
    email: str
    created_at: datetime
    subscription_type: SubscriptionType
    subscription_expires_at: Optional[datetime] = None
    default_currency: Currency = Currency.USD
    is_verified: bool = False
    has_claimed_free_trial: bool = False  # <-- NEW FIELD
    language: Optional[str] = None
    
    
class ForgotPasswordRequest(BaseModel):
    email: NormalizedEmail


class ResendVerificationRequest(BaseModel):
    email: NormalizedEmail


class DeleteAccountRequest(BaseModel):
    password: str


class VerifyOTPRequest(BaseModel):
    email: NormalizedEmail
    otp: str  # 6-digit string e.g. "482910"


class ResetPasswordRequest(BaseModel):
    email: NormalizedEmail
    reset_token: str
    new_password: str
    confirm_password: str
    
    

# NEW: Subscription update model
class SubscriptionUpdate(BaseModel):
    subscription_type: SubscriptionType
    subscription_expires_at: Optional[datetime] = None

# NEW: Profile update model
class ProfileUpdate(BaseModel):
    name: str

    @_field_validator("name")
    @classmethod
    def _strip_name(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Name is required")
        if len(v) > 100:
            raise ValueError("Name must be at most 100 characters")
        return v

    
class PasswordChange(BaseModel):
    current_password: str
    new_password: str
    confirm_password: str

class Token(BaseModel):
    access_token: str
    token_type: str
    user: UserResponse


# ---- Money validation (transactions / goals / budgets) ----
from pydantic import Field as _MoneyField
from typing import Annotated as _MoneyAnnotated

# Upper bound for any single money value. Large enough for MMK amounts, small
# enough that sums can never overflow to +/-inf.
MAX_MONEY_AMOUNT = 1e13

# Strictly positive, finite amount (NaN / +-inf rejected with 422).
PositiveAmount = _MoneyAnnotated[float, _MoneyField(gt=0, le=MAX_MONEY_AMOUNT, allow_inf_nan=False)]
# Zero or positive, finite amount.
NonNegativeAmount = _MoneyAnnotated[float, _MoneyField(ge=0, le=MAX_MONEY_AMOUNT, allow_inf_nan=False)]
# Any finite amount (sign allowed).
FiniteAmount = _MoneyAnnotated[float, _MoneyField(ge=-MAX_MONEY_AMOUNT, le=MAX_MONEY_AMOUNT, allow_inf_nan=False)]


class TransactionCreate(BaseModel):
    type: TransactionType
    main_category: str
    sub_category: str
    date: datetime
    description: Optional[str] = None
    recurrence: Optional[TransactionRecurrence] = None
    amount: PositiveAmount
    currency: Currency = Currency.USD  # NEW

class TransactionUpdate(BaseModel):
    type: Optional[TransactionType] = None
    main_category: Optional[str] = None
    sub_category: Optional[str] = None
    date: Optional[datetime] = None
    description: Optional[str] = None
    recurrence: Optional[TransactionRecurrence] = None
    amount: Optional[PositiveAmount] = None
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
    rating: Optional[int] = _Field(None, ge=1, le=5)  # 1 to 5 stars
    screenshot_url: Optional[str] = None # Optional: if you plan to upload images later

    @_field_validator("message")
    @classmethod
    def _strip_message(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Message is required")
        if len(v) > 5000:
            raise ValueError("Message must be at most 5000 characters")
        return v

class FeedbackResponse(BaseModel):
    id: str
    user_id: str
    category: FeedbackCategory
    message: str
    rating: Optional[int]
    created_at: datetime
    status: str = "pending" # pending, reviewed, resolved