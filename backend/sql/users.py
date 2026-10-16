"""User accounts: lookups, updates and the atomic (conditional) updates the auth flows need."""
from datetime import datetime
from typing import Any, Dict, Iterable, List, Optional

from sqlalchemy import and_, delete, func, insert, or_, select, update
from sqlalchemy.sql import ColumnElement

from sql.db import execute, fetch_all, fetch_one, fetch_value, transaction, write_returning
from sql.docs import row_to_doc, rows_to_docs
from sql.tables import users

_COLUMNS = {c.name for c in users.columns}


def _values(fields: Dict[str, Any]) -> Dict[str, Any]:
    values = {("id" if k == "_id" else k): v for k, v in fields.items()}
    unknown = set(values) - _COLUMNS
    if unknown:
        raise KeyError(f"users has no column(s) {sorted(unknown)}")
    return values


# ------------------------------------------------------------------ subscription rule
def active_premium(now: datetime) -> ColumnElement:
    """Premium and not expired (no expiry date = lifetime)."""
    return and_(users.c.subscription_type == "premium",
                or_(users.c.subscription_expires_at.is_(None), users.c.subscription_expires_at > now))


def effectively_free(now: datetime) -> ColumnElement:
    """Free, or premium whose expiry has passed."""
    return or_(users.c.subscription_type != "premium", users.c.subscription_expires_at <= now)


HAS_DEVICE = users.c.fcm_token.isnot(None)


# ------------------------------------------------------------------ reads
async def get_user(user_id: str) -> Optional[Dict[str, Any]]:
    return row_to_doc(await fetch_one(select(users).where(users.c.id == user_id)))


async def get_user_by_email(email: Optional[str]) -> Optional[Dict[str, Any]]:
    """Case-insensitive (e-mails are unique on lower(email))."""
    normalized = (email or "").strip().lower()
    if not normalized:
        return None
    return row_to_doc(await fetch_one(select(users).where(func.lower(users.c.email) == normalized)))


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


async def admin_list(search: Optional[str], subscription_type: Optional[str], skip: int, limit: int) -> List[Dict[str, Any]]:
    stmt = select(users)
    if search and search.strip():
        # Literal (not pattern) substring match, case-insensitive.
        needle = search.strip().lower()
        stmt = stmt.where(or_(func.strpos(func.lower(users.c.name), needle) > 0,
                              func.strpos(func.lower(users.c.email), needle) > 0))
    if subscription_type:
        stmt = stmt.where(users.c.subscription_type == subscription_type)
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
    return await update_user(user_id, users.c.has_claimed_free_trial.is_(False),
                             subscription_type="premium", subscription_expires_at=expires_at,
                             has_claimed_free_trial=True) > 0


async def claim_ai_data_fresh(user_id: str) -> bool:
    """ai_data_stale True -> False; True if this call cleared it."""
    return await update_user(user_id, users.c.ai_data_stale.is_(True), ai_data_stale=False) > 0


async def mark_ai_data_stale(user_id: str) -> None:
    await update_user(user_id, ai_data_stale=True)


async def downgrade_if_unchanged(user_id: str, stored_expiry: datetime, ended_at: datetime) -> bool:
    """Premium -> free only if the expiry is still the one the job read (an admin extension wins)."""
    return await update_user(user_id, users.c.subscription_type == "premium",
                             users.c.subscription_expires_at == stored_expiry,
                             subscription_type="free", premium_ended_at=ended_at) > 0


async def set_device_token(user_id: str, token: str) -> int:
    """Give this device token to user_id only; returns how many other accounts lost it."""
    async with transaction() as conn:
        released = (await conn.execute(
            update(users).where(users.c.fcm_token == token, users.c.id != user_id).values(fcm_token=None)
        )).rowcount
        await conn.execute(update(users).where(users.c.id == user_id).values(fcm_token=token))
    return released


async def clear_device_token(user_id: str) -> None:
    await update_user(user_id, fcm_token=None)
