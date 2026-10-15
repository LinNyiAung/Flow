"""Timezone / calendar-date helpers shared by the scheduler, insights and notifications.

Conventions used across the backend:
- Datetimes are stored in Mongo as UTC. User-entered dates (transaction date, goal
  target_date, budget start/end) arrive from the app as naive wall-clock values and are
  stored labelled as UTC, so their *calendar date* is simply the UTC date component.
- "Today" for the user-facing schedule is the calendar date in the app timezone
  (SCHEDULER_TIMEZONE, default Asia/Yangon), which is also the scheduler's timezone.

All functions here are pure (no DB / network) so they can be unit-tested directly.
"""
import logging
import os
from datetime import date, datetime, time, timedelta, timezone
from typing import Iterable, Optional
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

logger = logging.getLogger(__name__)

DEFAULT_APP_TIMEZONE = "Asia/Yangon"

# Goal target-date reminders (days before the target date), largest first.
GOAL_REMINDER_THRESHOLDS = (14, 7, 3, 1)

# Budget "ending soon" window (days before end date, inclusive).
BUDGET_ENDING_SOON_DAYS = 3


def get_app_timezone():
    """Timezone used for the scheduler and for "today" in user-facing date math."""
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


def app_today(now: Optional[datetime] = None) -> date:
    """Current calendar date in the app timezone."""
    return as_utc(now or utc_now()).astimezone(get_app_timezone()).date()


def app_wall_clock_now(now: Optional[datetime] = None) -> datetime:
    """Current wall-clock time in the app timezone, labelled as UTC.

    Use this (not the real UTC instant) when comparing "now" against stored user-entered
    datetimes (transaction date, budget start/end), which are local wall-clock values
    stored tagged as UTC.
    """
    local = as_utc(now or utc_now()).astimezone(get_app_timezone())
    return local.replace(tzinfo=timezone.utc)


def stored_calendar_date(dt) -> Optional[date]:
    """Calendar date of a stored (UTC-labelled) date value."""
    value = as_utc(dt)
    return value.date() if value else None


def days_until(dt, today: date) -> int:
    """Whole calendar days from `today` until the stored date `dt` (0 = today, negative = past)."""
    return (stored_calendar_date(dt) - today).days


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


def _day_bounds_utc(start: date, end: date):
    """UTC-labelled [start 00:00:00, end 23:59:59.999999] for calendar dates (matches how dates are stored)."""
    return (
        datetime.combine(start, time.min, tzinfo=timezone.utc),
        datetime.combine(end, time.max, tzinfo=timezone.utc),
    )


def previous_week_range(now: Optional[datetime] = None):
    """Most recent COMPLETE Monday-Sunday week, relative to today in the app timezone."""
    today = app_today(now)
    this_monday = today - timedelta(days=today.weekday())
    start = this_monday - timedelta(days=7)
    return _day_bounds_utc(start, start + timedelta(days=6))


def current_week_to_date_range(now: Optional[datetime] = None):
    """The current (incomplete) Monday-based week from Monday 00:00 through the end of today (app timezone)."""
    today = app_today(now)
    return _day_bounds_utc(today - timedelta(days=today.weekday()), today)


def current_month_to_date_range(now: Optional[datetime] = None):
    """The current (incomplete) calendar month from the 1st 00:00 through the end of today (app timezone)."""
    today = app_today(now)
    return _day_bounds_utc(today.replace(day=1), today)


def week_before_previous_range(now: Optional[datetime] = None):
    start, _ = previous_week_range(now)
    prev_start = start.date() - timedelta(days=7)
    return _day_bounds_utc(prev_start, prev_start + timedelta(days=6))


def _month_start_before(d: date) -> date:
    """First day of the month before the month containing d."""
    first = d.replace(day=1)
    return (first - timedelta(days=1)).replace(day=1)


def previous_month_range(now: Optional[datetime] = None):
    """Most recent COMPLETE calendar month, relative to today in the app timezone."""
    today = app_today(now)
    start = _month_start_before(today)
    end = today.replace(day=1) - timedelta(days=1)
    return _day_bounds_utc(start, end)


def month_before_previous_range(now: Optional[datetime] = None):
    start, _ = previous_month_range(now)
    prev_start = _month_start_before(start.date())
    prev_end = start.date() - timedelta(days=1)
    return _day_bounds_utc(prev_start, prev_end)
