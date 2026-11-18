"""Quota periods in the default zone: weeks start on Monday, months on the 1st, both at local midnight.

All functions take the instant `now` (a naive datetime is read as UTC) and look the zone up on every call
(tz_utils.default_zone), so SCHEDULER_TIMEZONE decides where a user's week and month roll over.
"""
from datetime import date, datetime, timedelta

from tz_utils import as_utc, default_zone, local_midnight_utc, local_today


def _today(now: datetime) -> date:
    return local_today(default_zone(), as_utc(now))


def _start_date(period: str, today: date) -> date:
    if period == "week":
        return today - timedelta(days=today.weekday())
    if period == "month":
        return today.replace(day=1)
    raise ValueError(f"Unknown period '{period}'")


def _midnight_utc(day: date) -> datetime:
    """Local midnight at the start of `day`, as an aware UTC datetime."""
    return local_midnight_utc(day, default_zone())


def period_start(period: str, now: datetime) -> date:
    """The first local date of the week / month that contains `now` (Monday for a week)."""
    return _start_date(period, _today(now))


def resets_at(period: str, now: datetime) -> datetime:
    """When the current week / month ends and the counters start again, in UTC."""
    start = _start_date(period, _today(now))
    if period == "week":
        nxt = start + timedelta(days=7)
    else:
        nxt = date(start.year + (start.month == 12), start.month % 12 + 1, 1)
    return _midnight_utc(nxt)


def month_start_utc(now: datetime) -> datetime:
    """When the current month began (local midnight on the 1st), in UTC: the start of the monthly spend window."""
    return _midnight_utc(_start_date("month", _today(now)))
