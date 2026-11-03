"""When the scheduled insights are generated, and so when the next one arrives.

The cron fields live here once: scheduler.py builds its CronTrigger jobs from them and next_scheduled_insight_at() asks a trigger
built from the same fields, so the "Next insight" line in the app can never drift from the real schedule. Times are in
the app timezone (tz_utils.get_app_timezone).
"""
from datetime import datetime, timedelta, timezone
from typing import Optional

from apscheduler.triggers.cron import CronTrigger

from plans import periods
from tz_utils import as_utc, get_app_timezone, utc_now

# Weekly insights: every Monday at 05:00. Monthly insights: the 1st of every month at 06:00.
WEEKLY_INSIGHT_CRON = {"day_of_week": "mon", "hour": 5, "minute": 0}
MONTHLY_INSIGHT_CRON = {"day": 1, "hour": 6, "minute": 0}


def cron_for(insight_type: str) -> dict:
    if insight_type == "weekly":
        return WEEKLY_INSIGHT_CRON
    if insight_type == "monthly":
        return MONTHLY_INSIGHT_CRON
    raise ValueError(f"Unknown insight type '{insight_type}'")


def next_scheduled_insight_at(insight_type: str, now: Optional[datetime] = None) -> datetime:
    """The next time the scheduler generates insights of this type after `now`, as an aware UTC datetime."""
    tz = get_app_timezone()
    trigger = CronTrigger(timezone=tz, **cron_for(insight_type))
    # Strictly after `now`: the trigger would answer `now` itself when it is exactly a fire time.
    local_now = (as_utc(now) if now is not None else utc_now()).astimezone(tz) + timedelta(microseconds=1)
    return trigger.get_next_fire_time(None, local_now).astimezone(timezone.utc)


def next_on_demand_insight_at(now: Optional[datetime] = None) -> datetime:
    """A Free user's monthly insight is made on demand once per calendar month: the next one can be made at the
    start of next month (local midnight on the 1st), as an aware UTC datetime."""
    return periods.resets_at("month", as_utc(now) if now is not None else utc_now())
