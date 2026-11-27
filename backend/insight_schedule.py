"""When the scheduled insights are generated, and so when the next one arrives.

The cron fields live here once: local_jobs takes its weekly and monthly insight jobs' weekday and day from them and
next_scheduled_insight_at() asks a trigger built from the same fields, so the "Next insight" line in the app can never
drift from the real schedule. Weekly insights run every Monday and monthly insights on the 1st, at the admin settings
weekly_report_time (default 05:00) and monthly_report_time (default 06:00), read on every call (tunables). The times are
on the book's clock (user_zones.book_zone: a personal book's person's, a family book's owner's); a Free user's on-demand
monthly insight follows their own month.
"""
from datetime import datetime, timedelta, timezone, tzinfo
from typing import Optional

from apscheduler.triggers.cron import CronTrigger

import tunables
from plans import periods
from tz_utils import as_utc, utc_now


def cron_for(insight_type: str) -> dict:
    """The cron fields of this insight type, a new dict on every call (the time is the admin setting right now)."""
    if insight_type == "weekly":
        at = tunables.time_of("weekly_report_time")
        return {"day_of_week": "mon", "hour": at.hour, "minute": at.minute}
    if insight_type == "monthly":
        at = tunables.time_of("monthly_report_time")
        return {"day": 1, "hour": at.hour, "minute": at.minute}
    raise ValueError(f"Unknown insight type '{insight_type}'")


def next_scheduled_insight_at(insight_type: str, tz: tzinfo, now: Optional[datetime] = None) -> datetime:
    """The next time a book whose zone is `tz` gets its insight of this type after `now`, as an aware UTC datetime."""
    trigger = CronTrigger(timezone=tz, **cron_for(insight_type))
    # Strictly after `now`: the trigger would answer `now` itself when it is exactly a fire time.
    local_now = (as_utc(now) if now is not None else utc_now()).astimezone(tz) + timedelta(microseconds=1)
    return trigger.get_next_fire_time(None, local_now).astimezone(timezone.utc)


def next_on_demand_insight_at(tz: tzinfo, now: Optional[datetime] = None) -> datetime:
    """A Free user's monthly insight is made on demand once per calendar month of their zone `tz`: the next one can be
    made at the start of next month (local midnight on the 1st), as an aware UTC datetime."""
    return periods.resets_at("month", as_utc(now) if now is not None else utc_now(), tz)
