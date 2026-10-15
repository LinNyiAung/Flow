import calendar
import logging
from collections import defaultdict
from datetime import date, datetime, time, timedelta, UTC
from typing import Dict, List, NamedTuple, Optional, Set, Tuple

from pydantic import ValidationError
from pymongo.errors import DuplicateKeyError

from recurrence_models import RecurrenceConfig, RecurrenceFrequency
from database import transactions_collection
from sql import users as users_db
from finite_utils import finite_amount_filter
from notification_service import create_notification
from tz_utils import app_today

logger = logging.getLogger(__name__)

# Safety cap: max occurrences generated for a single recurring transaction per job run.
MAX_CATCHUP_OCCURRENCES = 366

# Catch-up window: missed occurrences older than this many days (relative to today in the
# app timezone) are skipped instead of being back-filled in one burst.
CATCHUP_WINDOW_DAYS = 31

# Hard bound on how many stale occurrences we will step over in one run (defensive; a
# daily recurrence 10 years behind is ~3650 steps).
MAX_SKIP_STEPS = 100_000


def _as_utc(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC)


def _clamped(base: datetime, year: int, month: int, day: int) -> datetime:
    """`base` moved to year/month/day, clamping day to the last valid day of that month."""
    last_day = calendar.monthrange(year, month)[1]
    return base.replace(year=year, month=month, day=min(day, last_day))


def is_config_complete(config: RecurrenceConfig) -> bool:
    """True if the config has the fields its frequency needs."""
    if config.frequency == RecurrenceFrequency.WEEKLY:
        return config.day_of_week is not None
    if config.frequency == RecurrenceFrequency.MONTHLY:
        return config.day_of_month is not None
    if config.frequency == RecurrenceFrequency.ANNUALLY:
        return config.month is not None and config.day_of_year is not None
    return True


def calculate_next_occurrence(
    last_date: datetime,
    config: RecurrenceConfig
) -> Optional[datetime]:
    """
    Calculate the first occurrence strictly AFTER last_date (compared by calendar date).

    Dates follow the app convention (local wall-clock time stored tagged as UTC); the
    time-of-day of last_date is preserved. Days that don't exist in a month are clamped to
    the month's last day (Jan 31 monthly -> Feb 28/29; Apr 31 annually -> Apr 30).
    Returns None when the recurrence has ended or the config is incomplete.
    """
    last_date = _as_utc(last_date)
    end_date = _as_utc(config.end_date) if config.end_date else None

    if end_date and last_date.date() >= end_date.date():
        return None  # Recurrence has ended

    next_date: Optional[datetime] = None

    if config.frequency == RecurrenceFrequency.DAILY:
        next_date = last_date + timedelta(days=1)

    elif config.frequency == RecurrenceFrequency.WEEKLY:
        if config.day_of_week is None:
            return None
        days_ahead = config.day_of_week - last_date.weekday()
        if days_ahead <= 0:  # Target day already happened this week
            days_ahead += 7
        next_date = last_date + timedelta(days=days_ahead)

    elif config.frequency == RecurrenceFrequency.MONTHLY:
        if config.day_of_month is None:
            return None
        # Same month first (e.g. start Jan 5, day_of_month 20 -> Jan 20).
        candidate = _clamped(last_date, last_date.year, last_date.month, config.day_of_month)
        if candidate.date() <= last_date.date():
            year, month = last_date.year, last_date.month + 1
            if month > 12:
                year, month = year + 1, 1
            candidate = _clamped(last_date, year, month, config.day_of_month)
        next_date = candidate

    elif config.frequency == RecurrenceFrequency.ANNUALLY:
        if config.month is None or config.day_of_year is None:
            return None
        candidate = _clamped(last_date, last_date.year, config.month, config.day_of_year)
        if candidate.date() <= last_date.date():
            candidate = _clamped(last_date, last_date.year + 1, config.month, config.day_of_year)
        next_date = candidate

    # Whole-day semantics for end_date: an occurrence ON the end date is still created.
    if next_date and end_date and next_date.date() > end_date.date():
        return None

    return next_date


def rearmed_recurrence_pointer(start: datetime, config: RecurrenceConfig, today: date) -> datetime:
    """
    Pure helper: last_created_date to store when a recurrence is (re-)enabled or its
    schedule changes, so the daily job does NOT back-fill the past.

    Walks the occurrences after `start` and returns the latest one whose calendar date is
    on/before `today` (app timezone), i.e. everything up to and including today counts as
    already handled. Returns `start` itself when no occurrence falls in (start, today].

    Decision: if today is itself an occurrence date, today's occurrence is NOT created
    either (the user re-enabled/rescheduled today; the first auto-created transaction is
    the next occurrence after today). The pointer never moves before `start`.
    """
    current = _as_utc(start)
    for _ in range(MAX_SKIP_STEPS):
        nxt = calculate_next_occurrence(current, config)
        if nxt is None or nxt.date() > today:
            break
        current = nxt
    return current


def recurrence_schedule_key(config) -> Optional[tuple]:
    """Comparable key of the schedule-defining fields (frequency + day fields; end_date excluded)."""
    if not config:
        return None
    try:
        cfg = config if isinstance(config, RecurrenceConfig) else RecurrenceConfig(**config)
    except (ValidationError, TypeError):
        return ("invalid", repr(config))
    return (cfg.frequency.value, cfg.day_of_week, cfg.day_of_month, cfg.month, cfg.day_of_year)


def occurrence_id(parent_id: str, occurrence_date: datetime) -> str:
    """Deterministic _id for an auto-created occurrence (makes creation idempotent)."""
    return f"{parent_id}:{occurrence_date:%Y%m%d}"


class OccurrencePlan(NamedTuple):
    dates: List[datetime]               # occurrences to create (oldest first)
    ended: bool                         # recurrence has no further occurrences
    skipped: int                        # stale occurrences skipped (older than the window)
    last_skipped: Optional[datetime]    # newest skipped occurrence (pointer target), if any


def plan_due_occurrences(
    last_created: datetime,
    config: RecurrenceConfig,
    now: datetime,
    limit: int = MAX_CATCHUP_OCCURRENCES,
    catchup_days: Optional[int] = CATCHUP_WINDOW_DAYS,
) -> OccurrencePlan:
    """
    Pure helper: occurrences after last_created whose calendar date is <= today in the app
    timezone (so today's occurrence is due today even when the job runs at 06:00 Yangon =
    23:30 UTC the previous day).

    Occurrences dated before (today - catchup_days) are skipped (counted, not returned;
    they don't count towards `limit`). At most `limit` occurrences are returned.
    """
    today: date = app_today(now)
    cutoff: Optional[date] = today - timedelta(days=catchup_days) if catchup_days is not None else None
    dates: List[datetime] = []
    skipped = 0
    last_skipped: Optional[datetime] = None
    current = _as_utc(last_created)
    while len(dates) < limit:
        nxt = calculate_next_occurrence(current, config)
        if nxt is None:
            return OccurrencePlan(dates, True, skipped, last_skipped)
        if nxt.date() > today:
            return OccurrencePlan(dates, False, skipped, last_skipped)
        if cutoff is not None and nxt.date() < cutoff:
            skipped += 1
            last_skipped = nxt
            if skipped >= MAX_SKIP_STEPS:
                return OccurrencePlan(dates, False, skipped, last_skipped)
        else:
            dates.append(nxt)
        current = nxt
    return OccurrencePlan(dates, False, skipped, last_skipped)


def due_occurrences(
    last_created: datetime,
    config: RecurrenceConfig,
    now: datetime,
    limit: int = MAX_CATCHUP_OCCURRENCES,
) -> Tuple[List[datetime], bool]:
    """
    Pure helper: all occurrences after last_created whose calendar date is <= today in the
    app timezone (no catch-up window), capped at `limit`.
    Returns (dates, ended) where ended=True means the recurrence has no further occurrences.
    """
    plan = plan_due_occurrences(last_created, config, now, limit=limit, catchup_days=None)
    return plan.dates, plan.ended


async def _child_exists_on_date(transaction: dict, occ_date: datetime) -> bool:
    """True if an auto-created child of this parent already exists on occ_date's calendar date
    (older children have uuid _ids, so the deterministic _id alone can't dedupe them)."""
    day = occ_date.date()
    existing = await transactions_collection.find_one(
        {
            "user_id": transaction["user_id"],
            "recurrence.parent_transaction_id": transaction["_id"],
            "date": {
                "$gte": datetime.combine(day, time.min, tzinfo=UTC),
                "$lte": datetime.combine(day, time.max, tzinfo=UTC),
            },
        },
        {"_id": 1},
    )
    return existing is not None


async def _process_recurring_transaction(
    transaction: dict,
    now: datetime,
    affected: Dict[str, Dict[str, List[datetime]]],
) -> int:
    """Create all due occurrences for one recurring transaction. Returns number created."""
    recurrence = transaction.get("recurrence") or {}
    config_data = recurrence.get("config")
    if not config_data:
        return 0

    try:
        config = RecurrenceConfig(**config_data)
    except ValidationError as e:
        logger.warning(f"Recurring tx {transaction['_id']}: invalid config, skipping: {e}")
        return 0

    if not is_config_complete(config):
        logger.warning(f"Recurring tx {transaction['_id']}: incomplete config, disabling recurrence")
        await transactions_collection.update_one(
            {"_id": transaction["_id"]}, {"$set": {"recurrence.enabled": False}}
        )
        return 0

    # A key that exists with value None must also fall back to the transaction date.
    last_created = recurrence.get("last_created_date") or transaction["date"]
    last_created = _as_utc(last_created)

    plan = plan_due_occurrences(last_created, config, now)
    dates, ended = plan.dates, plan.ended

    if plan.skipped and plan.last_skipped is not None:
        # Too-old missed occurrences are not back-filled; just move the pointer past them.
        logger.warning(
            f"Recurring tx {transaction['_id']}: skipped {plan.skipped} missed occurrence(s) older than "
            f"{CATCHUP_WINDOW_DAYS} days (through {plan.last_skipped:%Y-%m-%d})"
        )
        await transactions_collection.update_one(
            {"_id": transaction["_id"]},
            {"$set": {"recurrence.last_created_date": plan.last_skipped}}
        )

    created = 0
    last_new_id = None
    for occ_date in dates:
        new_id = occurrence_id(transaction["_id"], occ_date)
        if await _child_exists_on_date(transaction, occ_date):
            # Already created (possibly by an older run with a uuid _id) - just advance the pointer.
            # Still refresh caches/budgets: a crashed run may have skipped that.
            affected[transaction["user_id"]][transaction.get("currency", "usd")].append(occ_date)
            await transactions_collection.update_one(
                {"_id": transaction["_id"]},
                {"$set": {"recurrence.last_created_date": occ_date}}
            )
            continue
        new_transaction = {
            "_id": new_id,
            "user_id": transaction["user_id"],
            "type": transaction["type"],
            "main_category": transaction["main_category"],
            "sub_category": transaction["sub_category"],
            "date": occ_date,
            "description": transaction.get("description"),
            "amount": transaction["amount"],
            "currency": transaction.get("currency", "usd"),
            "created_at": now,
            "updated_at": now,
            "recurrence": {
                "enabled": False,  # Auto-created transactions don't recurse
                "config": None,
                "last_created_date": None,
                "parent_transaction_id": transaction["_id"]
            }
        }
        try:
            await transactions_collection.insert_one(new_transaction)
            created += 1
            last_new_id = new_id
        except DuplicateKeyError:
            # Already created by a previous (possibly crashed) run - just advance the pointer.
            pass
        # Track even duplicates: a crashed run may have skipped the cache/budget refresh.
        affected[transaction["user_id"]][new_transaction["currency"]].append(occ_date)

        # Advance the pointer after every occurrence so a crash never re-creates (and the
        # deterministic _id makes a retry harmless anyway).
        await transactions_collection.update_one(
            {"_id": transaction["_id"]},
            {"$set": {"recurrence.last_created_date": occ_date}}
        )

    label = transaction.get("description") or transaction["sub_category"]

    if created:
        currency_map = {"usd": "$", "mmk": "K", "thb": "฿"}
        currency_symbol = currency_map.get(transaction.get("currency", "usd"), "$")
        if created == 1:
            message = (
                f"Your recurring {transaction['type']} of {currency_symbol}{transaction['amount']:.2f} "
                f"for '{label}' has been automatically created."
            )
        else:
            message = (
                f"{created} occurrences of your recurring {transaction['type']} of "
                f"{currency_symbol}{transaction['amount']:.2f} for '{label}' have been automatically created."
            )
        try:
            await create_notification(
                user_id=transaction["user_id"],
                notification_type="recurring_transaction_created",
                title="Recurring Transaction Created 🔄",
                message=message,
                goal_id=last_new_id,
                goal_name=label
            )
        except Exception as e:
            logger.error(f"Failed to notify recurring creation for {transaction['_id']}: {e}")

    if ended:
        await transactions_collection.update_one(
            {"_id": transaction["_id"]},
            {"$set": {"recurrence.enabled": False}}
        )
        try:
            await create_notification(
                user_id=transaction["user_id"],
                notification_type="recurring_transaction_ended",
                title="Recurring Transaction Ended 🏁",
                message=f"Your recurring transaction '{label}' has reached its end date.",
                goal_id=transaction["_id"],
                goal_name=label
            )
        except Exception as e:
            logger.error(f"Failed to notify recurring end for {transaction['_id']}: {e}")

    return created


async def _refresh_user_after_recurring(user_id: str, per_currency: Dict[str, List[datetime]]) -> None:
    """Invalidate balance cache, mark AI data stale and recompute affected budgets."""
    from budget_service import update_budgets_in_range  # local import: avoid import cycles

    await users_db.invalidate_balance_cache(user_id, mark_ai_stale=True)
    for currency, dates in per_currency.items():
        if not dates:
            continue
        try:
            await update_budgets_in_range(user_id, min(dates), max(dates), currency)
        except Exception as e:
            logger.error(f"Budget refresh after recurring creation failed for user {user_id}: {e}")


async def check_and_create_recurring_transactions():
    """Check all recurring transactions and create every due occurrence (catch-up)."""
    now = datetime.now(UTC)

    # Parents with a legacy NaN/inf amount are skipped: copying them would only create
    # more unusable rows.
    cursor = transactions_collection.find({"recurrence.enabled": True, **finite_amount_filter()})

    created_count = 0
    # user_id -> currency -> [occurrence dates]
    affected: Dict[str, Dict[str, List[datetime]]] = defaultdict(lambda: defaultdict(list))

    async for transaction in cursor:
        try:
            created_count += await _process_recurring_transaction(transaction, now, affected)
        except Exception as e:
            # One bad row must never abort the whole job.
            logger.exception(f"Error processing recurring transaction {transaction.get('_id')}: {e}")

    for user_id, per_currency in affected.items():
        try:
            await _refresh_user_after_recurring(user_id, per_currency)
        except Exception as e:
            logger.exception(f"Error refreshing user {user_id} after recurring creation: {e}")

    if created_count > 0:
        logger.info(f"✅ Created {created_count} recurring transactions")

    return created_count


async def disable_recurrence_for_transaction(transaction_id: str, user_id: str) -> bool:
    """Disable recurrence for a specific transaction"""
    result = await transactions_collection.update_one(
        {"_id": transaction_id, "user_id": user_id},
        {"$set": {"recurrence.enabled": False}}
    )
    return result.modified_count > 0


async def disable_recurrence_for_parent(parent_transaction_id: str, user_id: str) -> bool:
    """Disable recurrence for a parent transaction (when editing an auto-created one)"""
    result = await transactions_collection.update_one(
        {"_id": parent_transaction_id, "user_id": user_id},
        {"$set": {"recurrence.enabled": False}}
    )

    if result.modified_count > 0:
        parent_tx = await transactions_collection.find_one({"_id": parent_transaction_id})
        if parent_tx:
            label = parent_tx.get("description") or parent_tx["sub_category"]
            await create_notification(
                user_id=user_id,
                notification_type="recurring_transaction_disabled",
                title="Recurring Transaction Stopped 🛑",
                message=f"Automatic creation has been stopped for '{label}'.",
                goal_id=parent_transaction_id,
                goal_name=label
            )

    return result.modified_count > 0


def get_recurring_transaction_preview(
    last_date: datetime,
    config: RecurrenceConfig,
    count: int = 5
) -> List[datetime]:
    """Preview the next N occurrences of a recurring transaction"""
    occurrences = []
    current_date = last_date

    for _ in range(count):
        next_date = calculate_next_occurrence(current_date, config)
        if not next_date:
            break
        occurrences.append(next_date)
        current_date = next_date

    return occurrences
