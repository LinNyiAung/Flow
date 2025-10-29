from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class InsightResponse(BaseModel):
    id: str
    user_id: str
    content: str
    generated_at: datetime
    data_hash: str  # Hash of user's financial data to detect changes
    expires_at: Optional[datetime] = None