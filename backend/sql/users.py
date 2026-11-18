"""User accounts: lookups, updates and the atomic (conditional) updates the auth flows need."""
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List, Optional

from sqlalchemy import and_, delete, func, insert, or_, select, update
from sqlalchemy.sql import ColumnElement

from plans.catalog import PAID_PLANS
from sql import devices as devices_db
from sql.db import execute, fetch_all, fetch_one, fetch_value, write_returning
from sql.docs import row_to_doc, rows_to_docs
from sql.tables import books, users

_COLUMNS = {c.name for c in users.columns}


def _values(fields: Dict[str, Any]) -> Dict[str, Any]:
    values = {("id" if k == "_id" else k): v for k, v in fields.items()}
    unknown = set(values) - _COLUMNS
    if unknown:
        raise KeyError(f"users has no column(s) {sorted(unknown)}")
    return values


# ------------------------------------------------------------------ subscription rule
def _not_expired(now: datetime) -> ColumnElement:
    return or_(users.c.subscription_expires_at.is_(None), users.c.subscription_expires_at > now)


def active_plan(plan: str, now: datetime) -> ColumnElement:
    """On this plan ("plus" or "pro") and not expired (no expiry date = lifetime)."""
    return and_(users.c.subscription_type == plan, _not_expired(now))


def active_paid(now: datetime) -> ColumnElement:
    """On a paid plan (plus or pro) and not expired (no expiry date = lifetime)."""
    return and_(users.c.subscription_type.in_(PAID_PLANS), _not_expired(now))


def effectively_free(now: datetime) -> ColumnElement:
    """Free, or on a paid plan whose expiry has passed."""
    return or_(users.c.subscription_type.not_in(PAID_PLANS), users.c.subscription_expires_at <= now)


def not_on_trial(now: datetime) -> ColumnElement:
    """No running free trial: the trial marker is unset or in the past (the SQL side of plans.access.is_trial)."""
    return or_(users.c.trial_ends_at.is_(None), users.c.trial_ends_at <= now)


HAS_DEVICE = devices_db.HAS_DEVICE  # at least one device row (sql.devices)


# ------------------------------------------------------------------ reads
async def get_user(user_id: str) -> Optional[Dict[str, Any]]:
    return row_to_doc(await fetch_one(select(users).where(users.c.id == user_id)))


async def get_user_by_email(email: Optional[str]) -> Optional[Dict[str, Any]]:
    """Case-insensitive (e-mails are unique on lower(email))."""
    normalized = (email or "").strip().lower()
    if not normalized:
        return None
    return row_to_doc(await fetch_one(select(users).where(func.lower(users.c.email) == normalized)))


async def get_user_with_book_by_email(email: Optional[str]) -> Optional[Dict[str, Any]]:
    """get_user_by_email plus `personal_book_id`, the person's personal book (None when they have none yet), in one
    query (the per-request lookup of get_current_user)."""
    normalized = (email or "").strip().lower()
    if not normalized:
        return None
    stmt = (select(users, books.c.id.label("personal_book_id"))
            .select_from(users.outerjoin(books, books.c.person_id == users.c.id))
            .where(func.lower(users.c.email) == normalized))
    return row_to_doc(await fetch_one(stmt))


async def count_users(*conditions: ColumnElement) -> int:
    stmt = select(func.count()).select_from(users)
    if conditions:
        stmt = stmt.where(*conditions)
    return await fetch_value(stmt)


async def user_ids(*conditions: ColumnElement) -> List[str]:
    stmt = select(users.c.id).order_by(users.c.created_at)
    if conditions:
        stmt = stmt.where(*conditions)
    return [r["id"] for r in await fetch_all(stmt)]


async def list_fields(columns: Iterable[str], *conditions: ColumnElement) -> List[Dict[str, Any]]:
    """Selected columns of the users matching the conditions, as documents ("_id" + fields)."""
    cols = [users.c.id] + [users.c[c] for c in columns if c != "id"]
    stmt = select(*cols).order_by(users.c.created_at)
    if conditions:
        stmt = stmt.where(*conditions)
    return rows_to_docs(await fetch_all(stmt))


async def admin_list(search: Optional[str], subscription_type: Optional[str], skip: int, limit: int,
                     now: Optional[datetime] = None) -> List[Dict[str, Any]]:
    """Users for the admin list. `subscription_type` filters by the plan a user has at `now` (an expired Plus is free)."""
    now = now or datetime.now(timezone.utc)
    stmt = select(users)
    if search and search.strip():
        # Literal (not pattern) substring match, case-insensitive.
        needle = search.strip().lower()
        stmt = stmt.where(or_(func.strpos(func.lower(users.c.name), needle) > 0,
                              func.strpos(func.lower(users.c.email), needle) > 0))
    if subscription_type:
        stmt = stmt.where(effectively_free(now) if subscription_type == "free" else active_plan(subscription_type, now))
    stmt = stmt.order_by(users.c.created_at.desc(), users.c.id).offset(skip).limit(limit)
    return rows_to_docs(await fetch_all(stmt))


# ------------------------------------------------------------------ writes
async def insert_user(doc: Dict[str, Any]) -> None:
    """Raises sqlalchemy.exc.IntegrityError if the e-mail is taken (case-insensitively)."""
    await execute(insert(users).values(**_values(doc)))


async def update_user(user_id: str, *conditions: ColumnElement, **fields: Any) -> int:
    """UPDATE users SET fields WHERE id = user_id AND conditions; returns the row count.

    Values may be SQL expressions (e.g. users.c.password_version + 1); None clears a field.
    """
    stmt = update(users).where(users.c.id == user_id, *conditions).values(**_values(fields))
    return await execute(stmt)


async def update_user_returning(user_id: str, *conditions: ColumnElement, **fields: Any) -> Optional[Dict[str, Any]]:
    stmt = (update(users).where(users.c.id == user_id, *conditions).values(**_values(fields))
            .returning(*users.c))
    return row_to_doc(await write_returning(stmt))


async def set_timezone(user_id: str, name: str, now: datetime, last_change_before: datetime) -> bool:
    """Save the person's IANA zone name (validated by the caller, user_zones.remember_timezone) and when it changed
    (timezone_changed_at = now), only while it may change: no zone saved yet, or the last change was at or before
    `last_change_before`. In one statement, so two requests racing with different zones save at most one. True when
    saved."""
    return await update_user(user_id, or_(users.c.timezone.is_(None), users.c.timezone_changed_at.is_(None),
                                          users.c.timezone_changed_at <= last_change_before),
                             timezone=name, timezone_changed_at=now) > 0


async def timezone_of(user_id: str) -> Optional[str]:
    """The person's saved zone name (None: none saved, or no such person)."""
    return await fetch_value(select(users.c.timezone).where(users.c.id == user_id))


async def lock_user(user_id: str) -> bool:
    """SELECT ... FOR UPDATE on the user row (inside transaction()); False when there is none. Until the transaction
    ends, nothing can point a new row at this user (a foreign-key check waits for the lock)."""
    return await fetch_value(select(users.c.id).where(users.c.id == user_id).with_for_update()) is not None


async def delete_user(user_id: str) -> int:
    """Deletes the user; every PostgreSQL table holding their data cascades."""
    return await execute(delete(users).where(users.c.id == user_id))


# ------------------------------------------------------------------ atomic flows
async def mark_verified(user_id: str, token: str, now: datetime) -> bool:
    """Verify only if the stored token is still the one that was checked."""
    return await update_user(user_id, users.c.verification_token == token, is_verified=True, verified_at=now,
                             verification_token=None, verification_token_expires_at=None) > 0


async def consume_reset_attempt(user_id: str, now: datetime, max_attempts: int) -> Optional[Dict[str, Any]]:
    """Count one OTP attempt, only while an unexpired OTP exists, attempts remain and the
    account isn't locked. Returns the updated user, or None if no attempt was allowed."""
    return await update_user_returning(
        user_id,
        users.c.password_reset_otp.isnot(None),
        users.c.password_reset_otp_expiry > now,
        or_(users.c.password_reset_attempts.is_(None), users.c.password_reset_attempts < max_attempts),
        or_(users.c.password_reset_locked_until.is_(None), users.c.password_reset_locked_until <= now),
        password_reset_attempts=func.coalesce(users.c.password_reset_attempts, 0) + 1,
    )


async def reset_password_with_token(user_id: str, token_hash: str, password_hash: str, changed_at: datetime) -> bool:
    """Single use: succeeds only if the reset token is still the validated one."""
    return await update_user(user_id, users.c.password_reset_token == token_hash,
                             password=password_hash, password_changed_at=changed_at,
                             password_version=users.c.password_version + 1,
                             password_reset_token=None, password_reset_token_expiry=None) > 0


async def change_password(user_id: str, password_hash: str, changed_at: datetime) -> Optional[Dict[str, Any]]:
    """Store the new hash and bump password_version (revokes older tokens)."""
    return await update_user_returning(user_id, password=password_hash, password_changed_at=changed_at,
                                       password_version=users.c.password_version + 1)


async def claim_free_trial(user_id: str, expires_at: datetime) -> bool:
    """One-time Plus trial: the plan end and the trial marker (trial_ends_at) are the same instant."""
    return await update_user(user_id, users.c.has_claimed_free_trial.is_(False),
                             subscription_type="plus", subscription_expires_at=expires_at,
                             trial_ends_at=expires_at, has_claimed_free_trial=True) > 0


async def set_plan(user_id: str, plan: str, expires_at: Optional[datetime]) -> int:
    """Admin plan change. Always clears the trial marker (and so any pending trial reminder)."""
    return await update_user(user_id, subscription_type=plan, subscription_expires_at=expires_at, trial_ends_at=None)


# Which column records that a trial reminder went out ("3d": ends within 3 days, "last": within the last day).
_REMINDER_COLUMNS = {"3d": "trial_reminder_3d_at", "last": "trial_reminder_last_at"}


async def claim_trial_reminder(user_id: str, kind: str, trial_ends_at: datetime, now: datetime) -> bool:
    """Record that the `kind` reminder is being sent; True for exactly one caller.

    Only while the user is still on the same trial (same trial_ends_at, on a paid plan) and the reminder has not
    been recorded yet, so overlapping runs, a re-run, or an admin plan change in between never send it twice.
    """
    column = users.c[_REMINDER_COLUMNS[kind]]
    return await update_user(user_id, users.c.trial_ends_at == trial_ends_at, users.c.subscription_type.in_(PAID_PLANS),
                             column.is_(None), **{column.name: now}) > 0


# Which column records the plan end date a paid-plan reminder went out for ("3d": ends within 3 days, "last": within
# the last day).
_PLAN_REMINDER_COLUMNS = {"3d": "plan_reminder_3d_for", "last": "plan_reminder_last_for"}


async def claim_plan_reminder(user_id: str, kind: str, expires_at: datetime, now: datetime) -> bool:
    """Record that the `kind` paid-plan reminder is being sent for the plan ending at `expires_at`; True for exactly
    one caller.

    Only while the user is still on a paid plan ending at exactly `expires_at` (not yet passed), is not on a free trial,
    and the reminder has not been sent for that end date yet (the column is NULL or holds another date). So overlapping
    runs or a re-run never send it twice, and an admin extension to a new end date re-arms it.
    """
    column = users.c[_PLAN_REMINDER_COLUMNS[kind]]
    return await update_user(user_id, users.c.subscription_type.in_(PAID_PLANS),
                             users.c.subscription_expires_at == expires_at, users.c.subscription_expires_at > now,
                             not_on_trial(now), column.is_distinct_from(expires_at),
                             **{column.name: expires_at}) > 0


async def downgrade_if_unchanged(user_id: str, stored_expiry: datetime, ended_at: datetime) -> bool:
    """Plus/pro -> free only if the expiry is still the one the job read (an admin extension wins)."""
    return await update_user(user_id, users.c.subscription_type.in_(PAID_PLANS),
                             users.c.subscription_expires_at == stored_expiry,
                             subscription_type="free", premium_ended_at=ended_at) > 0
