"""Timezone / calendar-date helpers shared by the scheduler, insights and notifications.

Conventions used across the backend (Python values):
- Wall-clock values (transaction dates) are NAIVE datetimes: the local date and time the person picked, with no
  timezone. They are stored as `timestamp without time zone`.
- Calendar dates (budget start/end, goal target date, recurrence end and pointer, insight bounds) are `date`s, stored
  as DATE. A budget's end date is its inclusive last day.
- Instants (created_at, expiries, ...) are AWARE UTC datetimes, stored as timestamptz.
- Never compare an aware value with a naive one.
- "Today" depends on a zone: local_today(zone). A person's zone is users.timezone (an IANA name); without one the
  default zone applies (SCHEDULER_TIMEZONE, default Asia/Yangon).

All functions here are pure (no DB / network) so they can be unit-tested directly.
"""
import logging
import os
from datetime import date, datetime, time, timedelta, timezone, tzinfo
from typing import Annotated, Iterable, Optional
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import AfterValidator, BeforeValidator

logger = logging.getLogger(__name__)

DEFAULT_APP_TIMEZONE = "Asia/Yangon"
MAX_ZONE_NAME_LENGTH = 64

# Goal target-date reminders (days before the target date), largest first.
GOAL_REMINDER_THRESHOLDS = (14, 7, 3, 1)

# Budget "ending soon" window (days before end date, inclusive).
BUDGET_ENDING_SOON_DAYS = 3


def default_zone() -> tzinfo:
    """The zone of a person without a saved one, and of the scheduler: SCHEDULER_TIMEZONE, then Asia/Yangon, then UTC."""
    name = os.getenv("SCHEDULER_TIMEZONE", DEFAULT_APP_TIMEZONE) or DEFAULT_APP_TIMEZONE
    try:
        return ZoneInfo(name)
    except (ZoneInfoNotFoundError, ValueError):
        logger.warning(f"Unknown SCHEDULER_TIMEZONE '{name}', falling back to {DEFAULT_APP_TIMEZONE}")
        try:
            return ZoneInfo(DEFAULT_APP_TIMEZONE)
        except (ZoneInfoNotFoundError, ValueError):
            logger.warning("No tz database available (install 'tzdata'); falling back to UTC")
            return timezone.utc


def is_valid_zone_name(name: Optional[str]) -> bool:
    """True only for a non-empty IANA zone name of at most 64 characters that the tz database knows. Fixed offsets
    such as "+07:00" are not names and are refused."""
    if not isinstance(name, str) or not name or len(name) > MAX_ZONE_NAME_LENGTH or name != name.strip():
        return False
    try:
        ZoneInfo(name)
    except (ZoneInfoNotFoundError, ValueError, OSError):  # unknown name, or a path-like value ZoneInfo refuses
        return False
    return True


def zone_for(name: Optional[str]) -> tzinfo:
    """The zone `name` names when it is valid, else the default zone."""
    return ZoneInfo(name) if is_valid_zone_name(name) else default_zone()


def as_utc(dt) -> Optional[datetime]:
    """Normalize a datetime (or ISO string) to an aware UTC datetime. Naive values are treated as UTC."""
    if dt is None:
        return None
    if isinstance(dt, str):
        dt = datetime.fromisoformat(dt.replace("Z", "+00:00"))
    if isinstance(dt, datetime):
        if dt.tzinfo is None:
            return dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)
    if isinstance(dt, date):
        return datetime.combine(dt, time.min, tzinfo=timezone.utc)
    raise TypeError(f"Unsupported date value: {dt!r}")


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def is_expired(expires_at, now: Optional[datetime] = None) -> bool:
    """True if expires_at is set and in the past (tz-safe)."""
    if not expires_at:
        return False
    try:
        return as_utc(expires_at) < as_utc(now or utc_now())
    except (TypeError, ValueError):
        return False


def local_now(tz: tzinfo, now: Optional[datetime] = None) -> datetime:
    """The wall clock in `tz` at the instant `now` (default: now), as a NAIVE datetime."""
    return as_utc(now or utc_now()).astimezone(tz).replace(tzinfo=None)


def local_today(tz: tzinfo, now: Optional[datetime] = None) -> date:
    """The calendar date in `tz` at the instant `now` (default: now)."""
    return as_utc(now or utc_now()).astimezone(tz).date()


def local_midnight_utc(day: date, tz: tzinfo) -> datetime:
    """The instant local midnight starts `day` in `tz`, as an aware UTC datetime."""
    return datetime.combine(day, time.min, tzinfo=tz).astimezone(timezone.utc)


def _parse_iso(value: str):
    text = value.strip()
    if len(text) == 10:
        return date.fromisoformat(text)
    return datetime.fromisoformat(text.replace("Z", "+00:00").replace("z", "+00:00"))


def as_wall_clock(value) -> Optional[datetime]:
    """A wall-clock value as a NAIVE datetime. An aware input keeps its clock fields and drops its offset WITHOUT
    converting ("...T23:40:00Z" and "...T23:40:00+06:30" both give 23:40); a date (or "YYYY-MM-DD") becomes its 00:00.
    ValueError for a string that is not ISO 8601, TypeError for anything else."""
    if value is None:
        return None
    if isinstance(value, str):
        value = _parse_iso(value)
    if isinstance(value, datetime):
        return value.replace(tzinfo=None)
    if isinstance(value, date):
        return datetime.combine(value, time.min)
    raise TypeError(f"Unsupported date value: {value!r}")


def as_calendar_date(value) -> Optional[date]:
    """A calendar date: the date part of a datetime or ISO string, taken WITHOUT any timezone conversion. ValueError
    for a string that is not ISO 8601, TypeError for anything else."""
    if value is None:
        return None
    if isinstance(value, str):
        value = _parse_iso(value)
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    raise TypeError(f"Unsupported date value: {value!r}")


def _wall_clock_input(value):
    return as_wall_clock(value) if isinstance(value, (str, datetime, date)) else value


def _calendar_date_input(value):
    return as_calendar_date(value) if isinstance(value, (str, datetime, date)) else value


# Request / response field types. A WallClock field holds a naive datetime (an offset or "Z" in the input is dropped
# without converting); a CalendarDate field holds a date (a date-time input keeps its date part). Anything else is left
# to pydantic's own datetime / date validation (a bad string: 422).
WallClock = Annotated[datetime, BeforeValidator(_wall_clock_input), AfterValidator(lambda v: v.replace(tzinfo=None))]
CalendarDate = Annotated[date, BeforeValidator(_calendar_date_input)]


def days_until(d, today: date) -> int:
    """Whole calendar days from `today` until the calendar date `d` (0 = today, negative = past)."""
    return (as_calendar_date(d) - today).days


def goal_reminder_threshold(days_remaining: int, thresholds: Iterable[int] = GOAL_REMINDER_THRESHOLDS) -> Optional[int]:
    """Bucket a days-remaining value into a reminder threshold.

    Returns the smallest threshold t with days_remaining <= t (e.g. 10 days -> 14, 5 -> 7,
    2 -> 3, 1 -> 1), or None if out of range (<1 or > largest threshold). Because the
    caller dedupes per (goal, threshold), a once-a-day job fires each threshold exactly
    once even if a run is missed or the goal is created inside a window.
    """
    ordered = sorted(thresholds)
    if days_remaining < 1 or days_remaining > ordered[-1]:
        return None
    for t in ordered:
        if days_remaining <= t:
            return t
    return None


def is_budget_ending_soon(days_until_end: int, window: int = BUDGET_ENDING_SOON_DAYS) -> bool:
    return 0 <= days_until_end <= window


def day_bounds(start: date, end: date) -> tuple[datetime, datetime]:
    """NAIVE wall-clock [start 00:00:00, end 23:59:59.999999] of calendar dates (to filter transaction dates)."""
    return datetime.combine(start, time.min), datetime.combine(end, time.max)


def previous_week_range(tz: tzinfo, now: Optional[datetime] = None):
    """Most recent COMPLETE Monday-Sunday week, relative to today in `tz`."""
    today = local_today(tz, now)
    this_monday = today - timedelta(days=today.weekday())
    start = this_monday - timedelta(days=7)
    return day_bounds(start, start + timedelta(days=6))


def current_week_to_date_range(tz: tzinfo, now: Optional[datetime] = None):
    """The current (incomplete) Monday-based week from Monday 00:00 through the end of today in `tz`."""
    today = local_today(tz, now)
    return day_bounds(today - timedelta(days=today.weekday()), today)


def current_month_to_date_range(tz: tzinfo, now: Optional[datetime] = None):
    """The current (incomplete) calendar month from the 1st 00:00 through the end of today in `tz`."""
    today = local_today(tz, now)
    return day_bounds(today.replace(day=1), today)


def week_before_previous_range(tz: tzinfo, now: Optional[datetime] = None):
    start, _ = previous_week_range(tz, now)
    prev_start = start.date() - timedelta(days=7)
    return day_bounds(prev_start, prev_start + timedelta(days=6))


def _month_start_before(d: date) -> date:
    """First day of the month before the month containing d."""
    first = d.replace(day=1)
    return (first - timedelta(days=1)).replace(day=1)


def previous_month_range(tz: tzinfo, now: Optional[datetime] = None):
    """Most recent COMPLETE calendar month, relative to today in `tz`."""
    today = local_today(tz, now)
    start = _month_start_before(today)
    end = today.replace(day=1) - timedelta(days=1)
    return day_bounds(start, end)


def month_before_previous_range(tz: tzinfo, now: Optional[datetime] = None):
    start, _ = previous_month_range(tz, now)
    prev_start = _month_start_before(start.date())
    prev_end = start.date() - timedelta(days=1)
    return day_bounds(prev_start, prev_end)
