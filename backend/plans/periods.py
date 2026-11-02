"""Quota periods in the app timezone: weeks start on Monday, months on the 1st, both at local midnight.

All functions take the instant `now` (a naive datetime is read as UTC) and look the timezone up on every call
(tz_utils.get_app_timezone), so SCHEDULER_TIMEZONE decides where a user's week and month roll over.
"""
from datetime import date, datetime, time, timedelta, timezone

from tz_utils import get_app_timezone


def _local(now: datetime) -> datetime:
    if now.tzinfo is None:
        now = now.replace(tzinfo=timezone.utc)
    return now.astimezone(get_app_timezone())


def _start_date(period: str, local_today: date) -> date:
    if period == "week":
        return local_today - timedelta(days=local_today.weekday())
    if period == "month":
        return local_today.replace(day=1)
    raise ValueError(f"Unknown period '{period}'")


def _midnight_utc(day: date) -> datetime:
    """Local midnight at the start of `day`, as an aware UTC datetime."""
    return datetime.combine(day, time.min, tzinfo=get_app_timezone()).astimezone(timezone.utc)


def period_start(period: str, now: datetime) -> date:
    """The first local date of the week / month that contains `now` (Monday for a week)."""
    return _start_date(period, _local(now).date())


def resets_at(period: str, now: datetime) -> datetime:
    """When the current week / month ends and the counters start again, in UTC."""
    start = _start_date(period, _local(now).date())
    if period == "week":
        nxt = start + timedelta(days=7)
    else:
        nxt = date(start.year + (start.month == 12), start.month % 12 + 1, 1)
    return _midnight_utc(nxt)


def month_start_utc(now: datetime) -> datetime:
    """When the current month began (local midnight on the 1st), in UTC: the start of the monthly spend window."""
    return _midnight_utc(_start_date("month", _local(now).date()))
