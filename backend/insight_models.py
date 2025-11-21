from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class InsightResponse(BaseModel):
    id: str
    user_id: str
    content: str
    content_mm: Optional[str] = None  # NEW: Myanmar translation
    generated_at: datetime
    data_hash: str
    expires_at: Optional[datetime] = None