from pydantic import BaseModel
from typing import Dict, Optional
from datetime import datetime
from enum import Enum


class AIFeatureType(str, Enum):
    WEEKLY_INSIGHT = "weekly_insight"
    MONTHLY_INSIGHT = "monthly_insight"
    CHAT = "chat"
    TRANSLATION = "translation"
    CUSTOM_INSIGHT = "custom_insight"
    BUDGET_SUGGESTION = "budget_suggestion"
    BUDGET_AUTO_CREATE = "budget_auto_create"
    TRANSACTION_TEXT_EXTRACTION = "transaction_text_extraction"  # NEW
    TRANSACTION_IMAGE_EXTRACTION = "transaction_image_extraction"  # NEW
    TRANSACTION_AUDIO_TRANSCRIPTION = "transaction_audio_transcription"  # NEW


class AIProviderType(str, Enum):
    OPENAI = "openai"
    GEMINI = "gemini"
    CLAUDE = "claude"


class AIUsageCreate(BaseModel):
    user_id: Optional[str] = None  # the person, or None for a family book's own spend (book_id)
    book_id: Optional[str] = None
    feature_type: AIFeatureType
    provider: AIProviderType
    model_name: str
    input_tokens: int
    output_tokens: int
    total_tokens: int
    estimated_cost_usd: float


class AIUsageResponse(BaseModel):
    id: str
    user_id: Optional[str] = None  # the person whose spend it is; None for a family book's own spend
    book_id: Optional[str] = None  # the family book whose own spend it is (user_id None)
    feature_type: AIFeatureType
    provider: AIProviderType
    model_name: str
    input_tokens: int
    output_tokens: int
    total_tokens: int
    estimated_cost_usd: float
    fallback_from: Optional[AIProviderType] = None  # set when this answer came from a backup after that provider failed
    served_model: Optional[str] = None  # the model the provider says answered, when reported (stored in full)
    served_differs: bool = False  # served_model is another model than model_name (not just a dated snapshot of it)
    outcome: Optional[str] = None  # used | rejected (billed, unusable) | cancelled (stream cut short); None = used
    cost_estimated: bool = False  # the tokens or the audio length were estimated, not reported
    created_at: datetime


class UserAIUsageStats(BaseModel):
    # One spender: a person (user_id), a family book's own spend (book_id; user_name "Family · <name>") or every
    # deleted family's spend (both None, user_name "Deleted family").
    user_id: Optional[str] = None
    book_id: Optional[str] = None
    user_name: str
    user_email: str
    total_requests: int
    total_input_tokens: int
    total_output_tokens: int
    total_tokens: int
    total_cost_usd: float
    weekly_insights_count: int
    monthly_insights_count: int
    chat_requests_count: int
    translation_count: int
    cost_by_provider: Dict[str, float]


class AIUsageStatsResponse(BaseModel):
    total_users: int
    total_requests: int
    total_tokens: int
    total_cost_usd: float
    cost_by_provider: Dict[str, float]
    weekly_insights_requests: int
    monthly_insights_requests: int
    chat_requests: int
    translation_requests: int