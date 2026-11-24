from pydantic import BaseModel
from typing import Any, Dict, Optional
from datetime import date, datetime

class InsightResponse(BaseModel):
    id: str
    book_id: str
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
    # When the next insight of this type arrives (UTC): the next scheduled run for Plus and Pro, the start of next month
    # for a Free user's on-demand monthly insight. Null when the type is not available to the user.
    next_insight_at: Optional[datetime] = None
    # The days the report covers (inclusive; a weekly report's week, a monthly one's month), so the app can say which
    # period it is about: an old report (a failed run, a quiet period) mustn't read as the latest. Null for a placeholder
    # or an old row without them. is_period_to_date: the period was still running (a "so far" report).
    period_start: Optional[date] = None
    period_end: Optional[date] = None
    is_period_to_date: bool = False
