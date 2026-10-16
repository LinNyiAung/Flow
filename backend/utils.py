import asyncio
import weakref
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from typing import AsyncIterator, Optional
from fastapi import Depends, HTTPException , status
from fastapi import security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from ai_chatbot import financial_chatbot
from sql import goals as goals_db
from sql import transactions as transactions_db
from sql import users as users_db
import jwt  # PyJWT (replaces python-jose; same HS256 tokens)
from passlib.context import CryptContext


from config import settings


security = HTTPBearer()

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against its hash"""
    return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password: str) -> str:
    """Hash a password"""
    return pwd_context.hash(password)


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """
    Create a user JWT access token.

    Callers should pass {"sub": <email>, "uid": <user _id>}. "iat" (issued-at, whole
    seconds) is always added so tokens can be revoked by password_changed_at.
    """
    to_encode = data.copy()
    now = datetime.now(UTC)
    expire = now + (expires_delta or timedelta(minutes=15))
    to_encode.update({"exp": expire, "iat": int(now.timestamp())})
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def password_changed_now() -> datetime:
    """
    Timestamp to store as users.password_changed_at. Truncated to whole seconds so a
    token issued right after the change (iat is whole seconds) is not rejected.
    """
    return datetime.now(UTC).replace(microsecond=0)


def _decode_user_token(token: str) -> dict:
    """Decode and validate a *user* JWT; returns the payload."""
    try:
        # PyJWT verifies the signature (HS256 only), exp and iat (numeric) with leeway 0.
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    except jwt.PyJWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials: Token invalid or expired"
        )
    if payload.get("sub") is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials: Subject not found"
        )
    # Admin tokens are signed with the same key — never accept them as user tokens.
    if payload.get("type") == "admin":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token type"
        )
    return payload


def verify_token(token: str) -> str:
    """Verify JWT token and return email"""
    return _decode_user_token(token)["sub"]


async def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """Get current authenticated (and e-mail verified) user"""
    payload = _decode_user_token(credentials.credentials)
    email = payload["sub"]
    user = await users_db.get_user_by_email(email)
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")

    # Token must belong to this exact account (e.g. not a deleted + re-registered one).
    # Legacy tokens without "uid" are still accepted for backward compatibility.
    uid = payload.get("uid")
    if uid is not None and uid != user["_id"]:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Could not validate credentials")

    # Revoke tokens issued before the last password change. Tokens carry the account's
    # password_version ("pwv"), bumped on every change/reset — exact, unlike timestamps,
    # which can't separate a token issued in the same second as the change.
    pwv = payload.get("pwv")
    if pwv is not None:
        if pwv != int(user.get("password_version", 0) or 0):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Session expired, please log in again"
            )
    # Tokens issued before password versions existed: fall back to the timestamp check.
    elif (password_changed_at := user.get("password_changed_at")) is not None:
        if isinstance(password_changed_at, datetime) and password_changed_at.tzinfo is None:
            password_changed_at = password_changed_at.replace(tzinfo=UTC)
        iat = payload.get("iat")
        # Legacy tokens (no iat) can't prove they were issued after the change.
        if (
            not isinstance(iat, (int, float))
            or (isinstance(password_changed_at, datetime) and iat < int(password_changed_at.timestamp()))
        ):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Session expired, please log in again"
            )

    if user.get("is_verified") is False:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Email not verified")
    return user


def ensure_utc_datetime(dt) -> datetime:
    """Ensure datetime is timezone-aware UTC"""
    if dt is None:
        return None

    # If it's a string, parse it
    if isinstance(dt, str):
        dt = datetime.fromisoformat(dt.replace("Z", "+00:00"))

    # If naive (no timezone), make it UTC
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=UTC)
    # If has timezone but not UTC, convert to UTC
    elif dt.tzinfo != UTC:
        dt = dt.astimezone(UTC)

    return dt


async def get_user_balance(user_id: str, currency: Optional[str] = None) -> dict:
    """
    Per-currency balance, computed live (exact SQL sums over indexed rows; nothing cached,
    so it can never be stale): balance = inflow - outflow, available = balance - goals.
    """
    user = await users_db.get_user(user_id)
    if not user:
        return {"balances": {}}

    tx_map = {res["currency"]: res for res in await transactions_db.currency_totals(user_id)}
    allocated_map = {g["_id"]: g["total_allocated"] for g in await goals_db.allocated_by_currency(user_id)}

    all_currencies = set(tx_map) | set(allocated_map)
    if not all_currencies:
        all_currencies = {user.get("default_currency", "usd")}

    balances = {}
    for curr in all_currencies:
        tx_data = tx_map.get(curr, {"total_inflow": 0, "total_outflow": 0})
        allocated = allocated_map.get(curr, 0)
        total_inflow = tx_data["total_inflow"]
        total_outflow = tx_data["total_outflow"]
        balance = total_inflow - total_outflow
        balances[curr] = {
            "currency": curr,
            "balance": balance,
            "available_balance": balance - allocated,
            "allocated_to_goals": allocated,
            "total_inflow": total_inflow,
            "total_outflow": total_outflow
        }

    if currency:
        return balances.get(currency, {
            "currency": currency, "balance": 0, "available_balance": 0,
            "allocated_to_goals": 0, "total_inflow": 0, "total_outflow": 0
        })
    return {"balances": balances}


# Per-user lock serializing operations that move money between "available balance"
# and goals (goal contributions, goal creation with initial contribution, editing /
# deleting inflows). The database row lock works across all server processes; the
# in-process lock in front of it just queues same-user requests of one process in
# memory instead of each holding a pooled connection while it waits.
_user_money_locks: "weakref.WeakValueDictionary[str, asyncio.Lock]" = weakref.WeakValueDictionary()


@asynccontextmanager
async def get_user_money_lock(user_id: str) -> AsyncIterator[None]:
    """`async with get_user_money_lock(uid):` - the block is serialized per user and its
    database writes commit (or roll back) together."""
    lock = _user_money_locks.get(user_id)
    if lock is None:
        lock = asyncio.Lock()
        _user_money_locks[user_id] = lock
    async with lock:
        async with users_db.money_lock(user_id):
            yield


async def require_premium(current_user: dict = Depends(get_current_user)):
    """Middleware to check if user has premium subscription"""
    subscription_type = current_user.get("subscription_type", "free")

    if subscription_type == "premium":
        # Check if subscription hasn't expired
        expires_at = current_user.get("subscription_expires_at")
        if expires_at:
            # FIX: Ensure expires_at is timezone-aware before comparison
            expires_at_utc = ensure_utc_datetime(expires_at)
            if expires_at_utc > datetime.now(UTC):
                return current_user
        elif not expires_at:  # Lifetime premium (no expiration date)
            return current_user

    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="This feature requires a premium subscription"
    )


