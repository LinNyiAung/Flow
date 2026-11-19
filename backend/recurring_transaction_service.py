import calendar
import logging
from collections import defaultdict
from datetime import date, datetime, timedelta, tzinfo, UTC
from typing import Dict, List, NamedTuple, Optional, Set, Tuple

from pydantic import ValidationError

from recurrence_models import RecurrenceConfig, RecurrenceFrequency
from sql import families as families_db
from sql import transactions as transactions_db
from sql import books as books_db
from sql.db import transaction as db_transaction
from notification_service import create_notification
from tz_utils import as_calendar_date, as_wall_clock, day_bounds

logger = logging.getLogger(__name__)

# Safety cap: max occurrences generated for a single recurring transaction per job run.
MAX_CATCHUP_OCCURRENCES = 366

# Catch-up window: missed occurrences older than this many days (relative to the book's
# today) are skipped instead of being back-filled in one burst.
CATCHUP_WINDOW_DAYS = 31

# Hard bound on how many stale occurrences we will step over in one run (defensive; a
# daily recurrence 10 years behind is ~3650 steps).
MAX_SKIP_STEPS = 100_000


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

    Dates are local wall-clock values (naive datetimes; a date counts as its 00:00); the
    time-of-day of last_date is preserved. Days that don't exist in a month are clamped to
    the month's last day (Jan 31 monthly -> Feb 28/29; Apr 31 annually -> Apr 30).
    Returns None when the recurrence has ended or the config is incomplete.
    """
    last_date = as_wall_clock(last_date)
    end_date = as_calendar_date(config.end_date)

    if end_date and last_date.date() >= end_date:
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
    if next_date and end_date and next_date.date() > end_date:
        return None

    return next_date


def rearmed_recurrence_pointer(start: date, config: RecurrenceConfig, today: date) -> date:
    """
    Pure helper: last_created_date (a date) to store when a recurrence is (re-)enabled or its
    schedule changes, so the daily job does NOT back-fill the past.

    Walks the occurrences after `start` and returns the date of the latest one on/before
    `today`, i.e. everything up to and including today counts as already handled. Returns
    `start`'s date itself when no occurrence falls in (start, today].

    Decision: if today is itself an occurrence date, today's occurrence is NOT created
    either (the user re-enabled/rescheduled today; the first auto-created transaction is
    the next occurrence after today). The pointer never moves before `start`.
    """
    current = as_wall_clock(start)
    for _ in range(MAX_SKIP_STEPS):
        nxt = calculate_next_occurrence(current, config)
        if nxt is None or nxt.date() > today:
            break
        current = nxt
    return current.date()


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
    today: date,
    limit: int = MAX_CATCHUP_OCCURRENCES,
    catchup_days: Optional[int] = CATCHUP_WINDOW_DAYS,
) -> OccurrencePlan:
    """
    Pure helper: occurrences after last_created (a local wall-clock datetime; the occurrences
    keep its time of day) whose calendar date is <= `today` (the book's today, so today's
    occurrence is due at the book's 06:00 run whatever the UTC date).

    Occurrences dated before (today - catchup_days) are skipped (counted, not returned;
    they don't count towards `limit`). At most `limit` occurrences are returned.
    """
    cutoff: Optional[date] = today - timedelta(days=catchup_days) if catchup_days is not None else None
    dates: List[datetime] = []
    skipped = 0
    last_skipped: Optional[datetime] = None
    current = as_wall_clock(last_created)
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
    today: date,
    limit: int = MAX_CATCHUP_OCCURRENCES,
) -> Tuple[List[datetime], bool]:
    """
    Pure helper: all occurrences after last_created whose calendar date is <= `today` (the book's today, in its
    zone user_zones.book_zone; no catch-up window), capped at `limit`.
    Returns (dates, ended) where ended=True means the recurrence has no further occurrences.
    """
    plan = plan_due_occurrences(last_created, config, today, limit=limit, catchup_days=None)
    return plan.dates, plan.ended


async def _notice_recipient(transaction: dict) -> Optional[str]:
    """Who is told about a recurring entry: a personal book's person, or for a family book's entry only the member
    who added it, while that member is an active account member (else nobody). Never every member. (The notice links
    the entry's book, which marks a family entry's notice as the family's.)"""
    book = await books_db.get_book_row(transaction["book_id"])
    if book is None:
        return None
    if book["kind"] == "personal":
        return book["person_id"]
    member_id = transaction.get("added_by_member_id")
    return await families_db.active_member_user_id(book["id"], member_id) if member_id else None


async def _child_exists_on_date(transaction: dict, occ_date: datetime) -> bool:
    """True if an auto-created child of this parent already exists on occ_date's calendar date
    (older children have uuid _ids, so the deterministic _id alone can't dedupe them)."""
    day = as_calendar_date(occ_date)
    return await transactions_db.child_exists_between(transaction["book_id"], transaction["_id"],
                                                      *day_bounds(day, day))


async def _process_recurring_transaction(
    transaction: dict,
    now: datetime,
    today: date,
    affected: Dict[str, Dict[str, List[datetime]]],
) -> int:
    """Create all due occurrences (dated up to its book's `today`) for one recurring transaction. Returns number
    created. `now`: the instant stamped on the children."""
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
        await transactions_db.disable_recurrence(transaction["_id"])
        return 0

    # The pointer is the date of the last occurrence handled; occurrences keep the parent's time of day. A key that
    # exists with value None must also fall back to the transaction date.
    parent_date = as_wall_clock(transaction["date"])
    pointer = recurrence.get("last_created_date")
    last_created = datetime.combine(as_calendar_date(pointer), parent_date.time()) if pointer else parent_date

    plan = plan_due_occurrences(last_created, config, today)
    dates, ended = plan.dates, plan.ended

    if plan.skipped and plan.last_skipped is not None:
        # Too-old missed occurrences are not back-filled; just move the pointer past them.
        logger.warning(
            f"Recurring tx {transaction['_id']}: skipped {plan.skipped} missed occurrence(s) older than "
            f"{CATCHUP_WINDOW_DAYS} days (through {plan.last_skipped:%Y-%m-%d})"
        )
        await transactions_db.set_recurrence_pointer(transaction["_id"], plan.last_skipped.date())

    created = 0
    last_new_id = None
    # A family entry's children keep who added it and who it was for (so the adder may change them and the
    # per-person breakdown counts them).
    for_whom = (await families_db.beneficiaries_for([transaction["_id"]])).get(transaction["_id"], []) if dates else []
    for occ_date in dates:
        new_id = occurrence_id(transaction["_id"], occ_date)
        if await _child_exists_on_date(transaction, occ_date):
            # Already created (possibly by an older run with a uuid _id) - just advance the pointer.
            # Still refresh caches/budgets: a crashed run may have skipped that.
            affected[transaction["book_id"]][transaction.get("currency", "usd")].append(occ_date)
            await transactions_db.set_recurrence_pointer(transaction["_id"], occ_date.date())
            continue
        new_transaction = {
            "_id": new_id,
            "book_id": transaction["book_id"],
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
            },
            "added_by_member_id": transaction.get("added_by_member_id"),
        }
        # False = already created by a previous (possibly crashed) run: just advance the pointer.
        async with db_transaction():
            inserted = await transactions_db.insert_transaction(new_transaction)
            if inserted and for_whom:
                await families_db.set_beneficiaries(new_id, for_whom)
        if inserted:
            created += 1
            last_new_id = new_id
        # Track even duplicates: a crashed run may have skipped the cache/budget refresh.
        affected[transaction["book_id"]][new_transaction["currency"]].append(occ_date)

        # Advance the pointer after every occurrence so a crash never re-creates (and the
        # deterministic _id makes a retry harmless anyway).
        await transactions_db.set_recurrence_pointer(transaction["_id"], occ_date.date())

    label = transaction.get("description") or transaction["sub_category"]
    recipient = None
    if created or ended:
        try:
            recipient = await _notice_recipient(transaction)
        except Exception as e:
            logger.error(f"Could not find who to notify for recurring {transaction['_id']}: {e}")

    if created and recipient:
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
                user_id=recipient,
                notification_type="recurring_transaction_created",
                title="Recurring Transaction Created 🔄",
                message=message,
                goal_name=label,
                links={"transaction_id": last_new_id, "book_id": transaction["book_id"]},
            )
        except Exception as e:
            logger.error(f"Failed to notify recurring creation for {transaction['_id']}: {e}")

    if ended:
        await transactions_db.disable_recurrence(transaction["_id"])
        if recipient:
            try:
                await create_notification(
                    user_id=recipient,
                    notification_type="recurring_transaction_ended",
                    title="Recurring Transaction Ended 🏁",
                    message=f"Your recurring transaction '{label}' has reached its end date.",
                    goal_name=label,
                    links={"transaction_id": transaction["_id"], "book_id": transaction["book_id"]},
                )
            except Exception as e:
                logger.error(f"Failed to notify recurring end for {transaction['_id']}: {e}")

    return created


async def _refresh_book_after_recurring(book_id: str, per_currency: Dict[str, List[datetime]]) -> None:
    """Mark AI data stale and recompute affected budgets."""
    from budget_service import update_budgets_in_range  # local import: avoid import cycles

    await books_db.mark_ai_data_stale(book_id)
    for currency, dates in per_currency.items():
        if not dates:
            continue
        try:
            await update_budgets_in_range(book_id, min(dates), max(dates), currency)
        except Exception as e:
            logger.error(f"Budget refresh after recurring creation failed for book {book_id}: {e}")


async def recurring_for_book(book_id: str, today: date, tz: tzinfo) -> int:
    """The book's daily recurring run (local_jobs, 06:00 on the book's clock: a personal book's person's, a family
    book's owner's): create every due occurrence of its recurring transactions (catch-up), dated up to the book's
    `today`. Returns how many were created. Each occurrence has a deterministic id and the pointer moves after each one,
    so a retried run never creates one twice."""
    now = datetime.now(UTC)
    created_count = 0
    # book_id -> currency -> [occurrence dates]
    affected: Dict[str, Dict[str, List[datetime]]] = defaultdict(lambda: defaultdict(list))

    for transaction in await transactions_db.recurring_parents(book_id):
        try:
            created_count += await _process_recurring_transaction(transaction, now, today, affected)
        except Exception as e:
            # One bad row must never abort the whole run.
            logger.exception(f"Error processing recurring transaction {transaction.get('_id')}: {e}")

    for affected_book, per_currency in affected.items():
        try:
            await _refresh_book_after_recurring(affected_book, per_currency)
        except Exception as e:
            logger.exception(f"Error refreshing book {affected_book} after recurring creation: {e}")

    if created_count > 0:
        logger.info(f"✅ Created {created_count} recurring transactions in book {book_id}")

    return created_count


async def disable_recurrence_for_transaction(transaction_id: str, book_id: str) -> bool:
    """Disable recurrence for a specific transaction"""
    return await transactions_db.disable_recurrence(transaction_id, book_id)


async def disable_recurrence_for_parent(parent_transaction_id: str, book_id: str) -> bool:
    """Disable recurrence for a parent transaction (when editing an auto-created one)"""
    disabled = await transactions_db.disable_recurrence(parent_transaction_id, book_id)

    if disabled:
        parent_tx = await transactions_db.get_transaction(parent_transaction_id)
        # A family book's entry: only the member who added it is told (see _notice_recipient).
        recipient = await _notice_recipient(parent_tx) if parent_tx else None
        if parent_tx and recipient:
            label = parent_tx.get("description") or parent_tx["sub_category"]
            await create_notification(
                user_id=recipient,
                notification_type="recurring_transaction_disabled",
                title="Recurring Transaction Stopped 🛑",
                message=f"Automatic creation has been stopped for '{label}'.",
                goal_name=label,
                links={"transaction_id": parent_transaction_id, "book_id": parent_tx["book_id"]},
            )

    return disabled


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
