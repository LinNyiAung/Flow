"""Who is on which plan right now, and the error a plan check raises.

effective_plan() is the one live definition of a user's plan: a plus or pro plan whose end date has passed is free
at once, without waiting for the hourly expiry job to rewrite subscription_type.

PlanError is raised by the quota engine (plans.quota) and rendered by the app-level handler in plans_routes as
HTTP 403 (plan_feature_locked) or 429 (plan_limit_reached, plan_cost_cap) with the body
{"detail": {"code", "feature", "resets_at", "upgrade_available", "message"}}. The app decides what to do from
`code`; `message` is for people, in the user's language.
"""
from datetime import datetime, timezone
from typing import Any, Dict, Mapping, Optional

from tz_utils import as_utc, get_app_timezone

from .catalog import PAID_PLANS, PLANS

LOCKED = "plan_feature_locked"
LIMIT_REACHED = "plan_limit_reached"
COST_CAP = "plan_cost_cap"
_STATUS = {LOCKED: 403, LIMIT_REACHED: 429, COST_CAP: 429}
LANGUAGES = ("en", "my")


def _now(now: Optional[datetime]) -> datetime:
    return as_utc(now) if now is not None else datetime.now(timezone.utc)


def effective_plan(user: Mapping[str, Any], now: Optional[datetime] = None) -> str:
    """The plan the user has at `now`: "free", "plus" or "pro".

    A paid plan with an end date in the past counts as free; no end date on a paid plan means lifetime.
    An unknown stored value (e.g. a stray legacy "premium") is treated as free.
    """
    plan = user.get("subscription_type") or "free"
    if plan not in PLANS:
        return "free"
    if plan in PAID_PLANS:
        expires = user.get("subscription_expires_at")
        if expires is not None and as_utc(expires) <= _now(now):
            return "free"
    return plan


def is_trial(user: Mapping[str, Any], now: Optional[datetime] = None) -> bool:
    """True while the user's free-trial marker (trial_ends_at) is set and in the future."""
    ends = user.get("trial_ends_at")
    return ends is not None and as_utc(ends) > _now(now)


def user_language(user: Mapping[str, Any]) -> str:
    lang = user.get("language")
    return lang if lang in LANGUAGES else "en"


def _format_date(when: datetime, lang: str) -> str:
    """The local (app timezone) date a period resets on, as the user reads it."""
    local = when.astimezone(get_app_timezone())
    return local.strftime("%Y-%m-%d") if lang == "my" else local.strftime("%b %d, %Y").replace(" 0", " ")


class PlanError(Exception):
    """A plan check refused the request: the feature is locked, its allowance is used up, or the cost cap is reached.

    status: 403 for plan_feature_locked, 429 otherwise. resets_at: an aware UTC datetime (None for a locked feature).
    """

    def __init__(self, code: str, feature: str, *, resets_at: Optional[datetime] = None,
                 upgrade_available: bool = False, lang: str = "en"):
        if code not in _STATUS:
            raise ValueError(f"Unknown plan error code '{code}'")
        self.status = _STATUS[code]
        self.code = code
        self.feature = feature
        self.resets_at = resets_at
        self.upgrade_available = upgrade_available
        self.lang = lang if lang in LANGUAGES else "en"
        super().__init__(f"{code}: {feature}")

    def message(self) -> str:
        from notification_service import translate  # imported late: it pulls in the notification stack

        lang = self.lang
        name = translate(f"plan_feature_{self.feature}", lang)
        date = _format_date(self.resets_at, lang) if self.resets_at is not None else ""
        if self.code == LOCKED:
            text = translate("plan_feature_locked_msg", lang, feature=name)
            hint = "plan_upgrade_to_unlock"
        elif self.code == LIMIT_REACHED:
            text = translate("plan_limit_reached_msg", lang, feature=name, date=date)
            hint = "plan_upgrade_for_more"
        else:
            text = translate("plan_cost_cap_msg", lang, date=date)
            hint = "plan_upgrade_for_more"
        return f"{text} {translate(hint, lang)}" if self.upgrade_available else text

    def detail(self) -> Dict[str, Any]:
        """The body under "detail" in the HTTP response."""
        return {
            "code": self.code,
            "feature": self.feature,
            "resets_at": self.resets_at.isoformat() if self.resets_at is not None else None,
            "upgrade_available": self.upgrade_available,
            "message": self.message(),
        }
