"""The plan catalogue: which plans and quota features exist, and the default limits.

The defaults are what the migration seeds into plan_limits / plan_settings (the owner changes them later in the
admin panel, so the database rows, not these constants, are what the app enforces). The migration carries its own
copy of the numbers so it never changes when these do; e2e/test_plans.py checks the two agree.
"""
from dataclasses import dataclass
from typing import Dict, Optional

PLANS = ("free", "plus", "pro")
PAID_PLANS = ("plus", "pro")

# One entry per metered (or gated) thing a user can do with AI or a paid report.
FEATURES = ("chat", "chat_advanced", "insight_monthly", "insight_weekly", "insight_translation",
            "entry", "budget_suggestion", "reports")

# Limit modes: locked = not available, included = available without a count, counted = quota per period.
MODES = ("locked", "included", "counted")
PERIODS = ("week", "month")


@dataclass(frozen=True)
class Limit:
    mode: str
    quota: Optional[int] = None    # counted only: uses allowed per period (>= 0)
    period: Optional[str] = None   # counted only: "week" or "month"


_LOCKED = Limit("locked")
_INCLUDED = Limit("included")

DEFAULT_LIMITS: Dict[str, Dict[str, Limit]] = {
    "free": {
        "chat": Limit("counted", 5, "week"),
        "chat_advanced": _LOCKED,
        "insight_monthly": Limit("counted", 1, "month"),
        "insight_weekly": _LOCKED,
        "insight_translation": _LOCKED,
        "entry": Limit("counted", 10, "month"),
        "budget_suggestion": Limit("counted", 1, "month"),
        "reports": _LOCKED,
    },
    "plus": {
        "chat": Limit("counted", 100, "month"),
        "chat_advanced": _LOCKED,
        "insight_monthly": _INCLUDED,
        "insight_weekly": _INCLUDED,
        "insight_translation": _INCLUDED,
        "entry": Limit("counted", 150, "month"),
        "budget_suggestion": Limit("counted", 5, "month"),
        "reports": _INCLUDED,
    },
    "pro": {
        "chat": Limit("counted", 400, "month"),
        "chat_advanced": Limit("counted", 100, "month"),
        "insight_monthly": _INCLUDED,
        "insight_weekly": _INCLUDED,
        "insight_translation": _INCLUDED,
        "entry": Limit("counted", 500, "month"),
        "budget_suggestion": Limit("counted", 20, "month"),
        "reports": _INCLUDED,
    },
}

# Monthly AI spend (USD) a user on the plan may cost before further AI requests are refused.
DEFAULT_COST_CAPS: Dict[str, float] = {"free": 0.10, "plus": 1.00, "pro": 3.00}
