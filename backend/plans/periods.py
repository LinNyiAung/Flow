"""Quota periods in a person's zone: weeks start on Monday, months on the 1st, both at local midnight.

All functions take the instant `now` (a naive datetime is read as UTC) and the person's zone `tz`
(user_zones.user_zone; for a person without a saved zone that is tz_utils.default_zone).
"""
from datetime import date, datetime, timedelta, tzinfo

from tz_utils import as_utc, local_midnight_utc, local_today


def _today(now: datetime, tz: tzinfo) -> date:
    return local_today(tz, as_utc(now))


def _start_date(period: str, today: date) -> date:
    if period == "week":
        return today - timedelta(days=today.weekday())
    if period == "month":
        return today.replace(day=1)
    raise ValueError(f"Unknown period '{period}'")


def period_start(period: str, now: datetime, tz: tzinfo) -> date:
    """The first local date of the week / month that contains `now` in `tz` (Monday for a week)."""
    return _start_date(period, _today(now, tz))


def resets_at(period: str, now: datetime, tz: tzinfo) -> datetime:
    """When the current week / month in `tz` ends and the counters start again, in UTC."""
    start = _start_date(period, _today(now, tz))
    if period == "week":
        nxt = start + timedelta(days=7)
    else:
        nxt = date(start.year + (start.month == 12), start.month % 12 + 1, 1)
    return local_midnight_utc(nxt, tz)


def month_start_utc(now: datetime, tz: tzinfo) -> datetime:
    """When the current month in `tz` began (local midnight on the 1st), in UTC: the start of the monthly spend
    window."""
    return local_midnight_utc(_start_date("month", _today(now, tz)), tz)
