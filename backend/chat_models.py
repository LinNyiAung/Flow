from pydantic import BaseModel, Field, field_validator
from typing import List, Literal, Optional, Dict, Any
from datetime import datetime
from enum import Enum

class MessageRole(str, Enum):
    USER = "user"
    ASSISTANT = "assistant"

class ResponseStyle(str, Enum):
    NORMAL = "normal"
    CONCISE = "concise"
    EXPLANATORY = "explanatory"

# NEW: AI Provider enum
class AIProvider(str, Enum):
    OPENAI = "openai"
    GEMINI = "gemini"

# Size limits: every character is paid for in each answer's prompt. A new message longer than CHAT_MESSAGE_MAX is
# refused (422); earlier messages are trimmed instead (an old long answer must not break the chat).
CHAT_MESSAGE_MAX = 4000
CHAT_HISTORY_MAX_MESSAGES = 20


class ChatMessage(BaseModel):
    role: MessageRole
    content: str
    timestamp: Optional[datetime] = None

    @field_validator("content", mode="after")
    @classmethod
    def _trim(cls, v: str) -> str:
        return v[:CHAT_MESSAGE_MAX]


class ChatRequest(BaseModel):
    message: str = Field(..., max_length=CHAT_MESSAGE_MAX)
    chat_history: Optional[List[ChatMessage]] = None

    @field_validator("chat_history", mode="after")
    @classmethod
    def _recent(cls, v: Optional[List[ChatMessage]]) -> Optional[List[ChatMessage]]:
        return v[-CHAT_HISTORY_MAX_MESSAGES:] if v else v
    response_style: Optional[ResponseStyle] = ResponseStyle.NORMAL
    ai_provider: Optional[AIProvider] = AIProvider.OPENAI  # NEW
    # Pro's Standard / Advanced switch. The server answers Advanced only for a Pro user with Advanced left; otherwise
    # it answers as Standard and says so in the stream's first frame (mode_used, advanced_exhausted).
    mode: Literal["standard", "advanced"] = "standard"

class ChatResponse(BaseModel):
    response: str
    timestamp: datetime

class ChatSession(BaseModel):
    id: str
    user_id: str
    messages: List[ChatMessage]
    created_at: datetime
    updated_at: datetime