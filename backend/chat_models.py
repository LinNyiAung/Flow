from pydantic import BaseModel
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

class ChatMessage(BaseModel):
    role: MessageRole
    content: str
    timestamp: Optional[datetime] = None

class ChatRequest(BaseModel):
    message: str
    chat_history: Optional[List[ChatMessage]] = None
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