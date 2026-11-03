from pydantic import BaseModel
from typing import Any, Dict, Optional
from datetime import datetime

class InsightResponse(BaseModel):
    id: str
    user_id: str
    content: str
    content_mm: Optional[str] = None  # NEW: Myanmar translation
    generated_at: datetime
    expires_at: Optional[datetime] = None
    # True when Myanmar was requested but the user's plan does not include translation: the English
    # insight is returned and content_mm is null.
    translation_locked: Optional[bool] = False
    # Myanmar was requested and the plan includes it, but the translation was refused (cost cap, used-up allowance):
    # the same object as a limit error's detail {code, feature, resets_at, upgrade_available, message}, else null.
    # The English insight is returned and content_mm is null.
    translation_unavailable: Optional[Dict[str, Any]] = None
