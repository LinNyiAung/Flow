# backend/chat_models.py

from pydantic import BaseModel
from typing import List, Optional, Dict, Any
from datetime import datetime
from enum import Enum

class MessageRole(str, Enum):
    USER = "user"
    ASSISTANT = "assistant"

class ResponseStyle(str, Enum):
    NORMAL = "normal"
    CONCISE = "concise"
    EXPLANATORY = "explanatory"

class ChatMessage(BaseModel):
    role: MessageRole
    content: str
    timestamp: Optional[datetime] = None

class ChatRequest(BaseModel):
    message: str
    chat_history: Optional[List[ChatMessage]] = None
    response_style: Optional[ResponseStyle] = ResponseStyle.NORMAL  # NEW

class ChatResponse(BaseModel):
    response: str
    timestamp: datetime

class ChatSession(BaseModel):
    id: str
    user_id: str
    messages: List[ChatMessage]
    created_at: datetime
    updated_at: datetime