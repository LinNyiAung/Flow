import hashlib
import hmac
import re
import secrets
import threading
import time
import uuid
from collections import deque
from datetime import datetime, timedelta, UTC
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, HTTPException, status, Depends
from fastapi.concurrency import run_in_threadpool
from sqlalchemy.exc import IntegrityError

from email_service import send_otp_email, send_verification_email
from utils import (
    create_access_token,
    ensure_utc_datetime,
    get_current_user,
    get_password_hash,
    password_changed_now,
    verify_password,
)
from models import (
    Currency,
    CurrencyUpdate,
    DeleteAccountRequest,
    ForgotPasswordRequest,
    LanguageUpdate,
    PasswordChange,
    ProfileUpdate,
    ResendVerificationRequest,
    ResetPasswordRequest,
    SubscriptionType,
    UserCreate,
    UserLogin,
    UserResponse,
    Token,
    VerifyOTPRequest,
)
from config import settings
from sql import users as users_db

router = APIRouter(prefix="/api/auth", tags=["auth"])


# ==================== CONSTANTS ====================

VERIFICATION_TOKEN_TTL = timedelta(hours=48)
OTP_TTL = timedelta(minutes=10)
OTP_MAX_ATTEMPTS = 5
OTP_LOCKOUT = timedelta(minutes=30)
RESET_TOKEN_TTL = timedelta(minutes=10)

GENERIC_OTP_ERROR = "Invalid or expired OTP. Please request a new one."
GENERIC_RESET_ERROR = "Invalid or expired reset session. Please start over."
GENERIC_VERIFY_ERROR = "Invalid or expired verification link. Please request a new one."


# ==================== HELPERS ====================

class _SlidingWindowRateLimiter:
    """
    Tiny in-memory per-key rate limiter (single uvicorn worker assumed).
    rules: list of (max_hits, window_seconds).
    """

    def __init__(self, rules: list[tuple[int, int]]):
        self._rules = rules
        self._max_window = max(w for _, w in rules)
        self._hits: dict[str, deque] = {}
        self._lock = threading.Lock()

    def allow(self, key: str) -> bool:
        now = time.monotonic()
        with self._lock:
            if len(self._hits) > 10_000:
                self._purge(now)
            hits = self._hits.setdefault(key, deque())
            while hits and now - hits[0] >= self._max_window:
                hits.popleft()
            for max_hits, window in self._rules:
                if sum(1 for t in hits if now - t < window) >= max_hits:
                    return False
            hits.append(now)
            return True

    def _purge(self, now: float) -> None:
        stale = [k for k, v in self._hits.items() if not v or now - v[-1] >= self._max_window]
        for k in stale:
            del self._hits[k]


# 1 per minute, 5 per hour per e-mail address
_otp_request_limiter = _SlidingWindowRateLimiter([(1, 60), (5, 3600)])
_verification_email_limiter = _SlidingWindowRateLimiter([(1, 60), (5, 3600)])


def _normalize_email(email: Optional[str]) -> str:
    return (email or "").strip().lower()


async def find_user_by_email(email: Optional[str]) -> Optional[dict]:
    """
    Find a user by e-mail, case-insensitively. New accounts are stored lowercase, so
    the exact match hits first; legacy mixed-case accounts fall back to an anchored,
    escaped case-insensitive regex.
    """
    return await users_db.get_user_by_email(email)


def build_user_response(user: dict) -> UserResponse:
    """Single place that turns a users-collection document into a UserResponse."""
    return UserResponse(
        id=user["_id"],
        name=user["name"],
        email=user["email"],
        created_at=user["created_at"],
        subscription_type=SubscriptionType(user.get("subscription_type") or "free"),
        subscription_expires_at=ensure_utc_datetime(user.get("subscription_expires_at")),
        default_currency=Currency(user.get("default_currency") or "usd"),
        is_verified=bool(user.get("is_verified", False)),
        has_claimed_free_trial=bool(user.get("has_claimed_free_trial", False)),
        language=user.get("language"),
    )


def _issue_token(user: dict) -> str:
    return create_access_token(
        data={"sub": user["email"], "uid": user["_id"], "pwv": int(user.get("password_version", 0) or 0)},
        expires_delta=timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES),
    )


def _hash_otp(user_id: str, otp: str) -> str:
    key = (settings.SECRET_KEY or "").encode()
    return hmac.new(key, f"{user_id}:{otp}".encode(), hashlib.sha256).hexdigest()


def _safe_equals(a: Optional[str], b: Optional[str]) -> bool:
    if not a or not b:
        return False
    return secrets.compare_digest(a.encode("utf-8"), b.encode("utf-8"))


# ==================== AUTHENTICATION ====================

@router.post("/register", response_model=Token)
async def register(user_data: UserCreate, background_tasks: BackgroundTasks):
    """
    Register new user. The returned token is NOT usable for authenticated endpoints
    until the e-mail address is verified (they return 403 "Email not verified").
    """
    email = _normalize_email(user_data.email)
    if await find_user_by_email(email):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered")

    hashed_password = await run_in_threadpool(get_password_hash, user_data.password)

    now = datetime.now(UTC)
    user_id = str(uuid.uuid4())
    verification_token = secrets.token_urlsafe(32)

    new_user = {
        "_id": user_id,
        "name": user_data.name,
        "email": email,
        "password": hashed_password,
        "subscription_type": "free",
        "subscription_expires_at": None,
        "default_currency": "usd",
        "language": "en",
        "created_at": now,
        "is_verified": False,
        "has_claimed_free_trial": False,
        "verification_token": verification_token,
        "verification_token_expires_at": now + VERIFICATION_TOKEN_TTL,
    }

    try:
        await users_db.insert_user(new_user)
    except IntegrityError:
        # Lost a race with a concurrent registration of the same address (unique
        # case-insensitive index email_unique_ci).
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered")

    # The registration e-mail does NOT count against the resend limiter, so the user can
    # press "Resend" right away (explicit resends stay limited to 1/min and 5/hour).
    background_tasks.add_task(send_verification_email, email, verification_token)

    return Token(
        access_token=_issue_token(new_user),
        token_type="bearer",
        user=build_user_response(new_user),
    )


@router.get("/verify-email")
async def verify_email(email: str, token: str):
    """Verify user's email address using the token from the e-mail link"""
    user = await find_user_by_email(email)

    if not user:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=GENERIC_VERIFY_ERROR)

    if user.get("is_verified") is True:
        return {"message": "Email is already verified. You can log in."}

    stored_token = user.get("verification_token")
    if not _safe_equals(stored_token, token):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=GENERIC_VERIFY_ERROR)

    # Legacy tokens issued before expiry tracking have no expiry and remain valid.
    expires_at = ensure_utc_datetime(user.get("verification_token_expires_at"))
    if expires_at is not None and datetime.now(UTC) > expires_at:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=GENERIC_VERIFY_ERROR)

    await users_db.mark_verified(user["_id"], stored_token, datetime.now(UTC))

    return {"message": "Email verified successfully! Your account is now active."}


@router.post("/resend-verification")
async def resend_verification_email(request: ResendVerificationRequest, background_tasks: BackgroundTasks):
    """
    Re-send the verification e-mail with a fresh 48h token.
    Always returns 200 with the same message (no account enumeration); silently
    rate-limited to 1/minute and 5/hour per address.
    """
    email = _normalize_email(request.email)
    generic = {"message": "If that email is registered and not yet verified, a new verification link has been sent."}

    if not _verification_email_limiter.allow(email):
        return generic

    user = await find_user_by_email(email)
    if user and user.get("is_verified") is not True:
        verification_token = secrets.token_urlsafe(32)
        await users_db.update_user(
            user["_id"],
            verification_token=verification_token,
            verification_token_expires_at=datetime.now(UTC) + VERIFICATION_TOKEN_TTL,
        )
        background_tasks.add_task(send_verification_email, user["email"], verification_token)

    return generic


@router.put("/language", response_model=UserResponse)
async def update_language(
    language_data: LanguageUpdate,
    current_user: dict = Depends(get_current_user)
):
    """Update user's preferred language (validated by the model: 'en' or 'my')"""
    updated_user = await users_db.update_user_returning(current_user["_id"], language=language_data.language)
    return build_user_response(updated_user)


@router.post("/login", response_model=Token)
async def login(user_credentials: UserLogin):
    """Login user"""
    user = await find_user_by_email(user_credentials.email)

    if (
        not user
        or not user.get("password")
        or not await run_in_threadpool(verify_password, user_credentials.password, user["password"])
    ):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Incorrect email or password")

    if not user.get("is_verified", False):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Please verify your email address before logging in. Check your inbox."
        )

    return Token(
        access_token=_issue_token(user),
        token_type="bearer",
        user=build_user_response(user),
    )


# ── 1. Request OTP ────────────────────────────────────────────────────────────
@router.post("/forgot-password/request-otp")
async def request_password_reset_otp(request: ForgotPasswordRequest, background_tasks: BackgroundTasks):
    """
    Generate a secure 6-digit OTP (10-minute expiry) and e-mail it in the background.
    Always returns 200 with the same message to avoid enumeration. Silently
    rate-limited (1/minute, 5/hour per address) and suppressed while the account is
    locked out. Re-requesting does NOT reset the failed-attempt counter inside the
    30-minute window.
    """
    generic = {"message": "If that email is registered, you will receive an OTP shortly."}
    email = _normalize_email(request.email)

    if not _otp_request_limiter.allow(email):
        return generic

    user = await find_user_by_email(email)
    if not user:
        return generic

    now = datetime.now(UTC)
    locked_until = ensure_utc_datetime(user.get("password_reset_locked_until"))
    if locked_until is not None and locked_until > now:
        return generic  # locked out: silently do nothing

    otp = str(secrets.randbelow(900000) + 100000)
    set_fields = {
        "password_reset_otp": _hash_otp(user["_id"], otp),
        "password_reset_otp_expiry": now + OTP_TTL,
    }

    # Start a fresh attempt window only if the previous one has elapsed (or a lock expired)
    window_start = ensure_utc_datetime(user.get("password_reset_attempts_since"))
    if locked_until is not None or window_start is None or now - window_start > OTP_LOCKOUT:
        set_fields["password_reset_attempts"] = 0
        set_fields["password_reset_attempts_since"] = now
        set_fields["password_reset_locked_until"] = None

    await users_db.update_user(user["_id"], **set_fields)

    background_tasks.add_task(send_otp_email, user["email"], otp)
    return generic


# ── 2. Verify OTP ─────────────────────────────────────────────────────────────
@router.post("/forgot-password/verify-otp")
async def verify_password_reset_otp(request: VerifyOTPRequest):
    """
    Check the OTP. Every attempt is counted atomically; after 5 failed attempts the
    account is locked for 30 minutes (also across new OTP requests). All failure
    cases return the same 400 error text.
    Returns a short-lived reset_token for /reset-password.
    """
    user = await find_user_by_email(request.email)
    if not user:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=GENERIC_OTP_ERROR)

    now = datetime.now(UTC)

    # Atomically consume one attempt, only if an unexpired OTP exists, the attempt
    # budget isn't exhausted and the account isn't locked.
    updated = await users_db.consume_reset_attempt(user["_id"], now, OTP_MAX_ATTEMPTS)

    if not updated:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=GENERIC_OTP_ERROR)

    submitted = (request.otp or "").strip()
    if not _safe_equals(updated.get("password_reset_otp"), _hash_otp(updated["_id"], submitted)):
        if updated.get("password_reset_attempts", 0) >= OTP_MAX_ATTEMPTS:
            await users_db.update_user(
                updated["_id"],
                password_reset_locked_until=now + OTP_LOCKOUT,
                password_reset_otp=None,
                password_reset_otp_expiry=None,
            )
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=GENERIC_OTP_ERROR)

    # OTP is valid – issue a single-use reset token (10-min window)
    reset_token = secrets.token_urlsafe(32)
    hashed_reset_token = hashlib.sha256(reset_token.encode()).hexdigest()

    await users_db.update_user(
        updated["_id"],
        password_reset_token=hashed_reset_token,  # Store hashed version
        password_reset_token_expiry=now + RESET_TOKEN_TTL,
        password_reset_otp=None,
        password_reset_otp_expiry=None,
        password_reset_attempts=None,
        password_reset_attempts_since=None,
        password_reset_locked_until=None,
    )

    return {"message": "OTP verified successfully.", "reset_token": reset_token}


# ── 3. Reset Password ─────────────────────────────────────────────────────────
@router.post("/forgot-password/reset-password")
async def reset_password(request: ResetPasswordRequest):
    """Accept the reset_token from step 2 and set a new password."""
    user = await find_user_by_email(request.email)
    if not user:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=GENERIC_RESET_ERROR)

    stored_token_hash = user.get("password_reset_token")
    token_expiry = ensure_utc_datetime(user.get("password_reset_token_expiry"))

    if not stored_token_hash or not token_expiry or datetime.now(UTC) > token_expiry:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=GENERIC_RESET_ERROR)

    incoming_token_hash = hashlib.sha256(request.reset_token.encode()).hexdigest()
    if not _safe_equals(stored_token_hash, incoming_token_hash):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=GENERIC_RESET_ERROR)

    if len(request.new_password) < 6:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password must be at least 6 characters"
        )

    if request.new_password != request.confirm_password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Passwords do not match"
        )

    hashed_pw = await run_in_threadpool(get_password_hash, request.new_password)

    # Only consume the token if it is still the one we validated (single use)
    if not await users_db.reset_password_with_token(user["_id"], stored_token_hash, hashed_pw, password_changed_now()):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=GENERIC_RESET_ERROR)

    return {"message": "Password reset successfully. You can now log in."}


@router.get("/me", response_model=UserResponse)
async def get_current_user_info(current_user: dict = Depends(get_current_user)):
    """Get current user info"""
    return build_user_response(current_user)


@router.put("/profile", response_model=UserResponse)
async def update_profile(
    profile_data: ProfileUpdate,
    current_user: dict = Depends(get_current_user)
):
    """Update user profile (name only). Name is stripped and validated by the model."""
    name = profile_data.name.strip()
    if len(name) < 2:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Name must be at least 2 characters"
        )

    updated_user = await users_db.update_user_returning(current_user["_id"], name=name)
    return build_user_response(updated_user)


@router.put("/currency", response_model=UserResponse)
async def update_default_currency(
    currency_data: CurrencyUpdate,
    current_user: dict = Depends(get_current_user)
):
    """Update user's default currency"""
    updated_user = await users_db.update_user_returning(
        current_user["_id"], default_currency=currency_data.default_currency.value
    )
    return build_user_response(updated_user)


@router.put("/change-password")
async def change_password(
    password_data: PasswordChange,
    current_user: dict = Depends(get_current_user)
):
    """
    Change user password. All previously issued tokens are revoked; the response
    contains a fresh access_token the client must store.
    """
    is_correct = await run_in_threadpool(verify_password, password_data.current_password, current_user["password"])

    if not is_correct:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Current password is incorrect"
        )

    if len(password_data.new_password) < 6:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="New password must be at least 6 characters"
        )

    if password_data.new_password != password_data.confirm_password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="New passwords do not match"
        )

    hashed_password = await run_in_threadpool(get_password_hash, password_data.new_password)

    updated_user = await users_db.change_password(current_user["_id"], hashed_password, password_changed_now())

    return {
        "message": "Password changed successfully",
        "access_token": _issue_token(updated_user or current_user),
        "token_type": "bearer",
    }


@router.delete("/delete-account")
async def delete_account(
    body: DeleteAccountRequest,
    current_user: dict = Depends(get_current_user)
):
    """Delete user account and all associated data. Requires the current password."""
    if not body.password or not await run_in_threadpool(verify_password, body.password, current_user["password"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Password is incorrect"
        )

    try:
        user_id = current_user["_id"]

        # Every table cascades from users (ON DELETE CASCADE): one atomic delete.
        if await users_db.delete_user(user_id) == 0:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to delete account"
            )

        return {"message": "Account deleted successfully"}

    except HTTPException:
        raise
    except Exception as e:
        print(f"Error deleting account: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete account"
        )


@router.get("/subscription-status")
async def get_subscription_status(current_user: dict = Depends(get_current_user)):
    """Check if user has active premium subscription"""
    subscription_type = current_user.get("subscription_type") or "free"
    try:
        expires_at = ensure_utc_datetime(current_user.get("subscription_expires_at"))
    except (TypeError, ValueError, AttributeError):
        expires_at = None

    is_premium = subscription_type == "premium"
    is_expired = False

    if is_premium and expires_at:
        is_expired = expires_at < datetime.now(UTC)
        is_premium = not is_expired

    return {
        "subscription_type": subscription_type,
        "is_premium": is_premium,
        "expires_at": expires_at,
        "is_expired": is_expired
    }


@router.post("/claim-free-trial", response_model=UserResponse)
async def claim_free_trial(current_user: dict = Depends(get_current_user)):
    """
    Grants the authenticated user 1 month of free premium access.
    Can only be claimed once per account.
    """
    # Prevent double-claiming
    if current_user.get("has_claimed_free_trial", False):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You have already claimed your free trial."
        )

    # Prevent claiming if already premium (admin-granted, lifetime or still active)
    if current_user.get("subscription_type") == "premium":
        existing_expiry = ensure_utc_datetime(current_user.get("subscription_expires_at"))
        if existing_expiry is None or existing_expiry > datetime.now(UTC):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="You already have an active premium subscription."
            )

    trial_expiry = datetime.now(UTC) + timedelta(days=30)

    # Atomic guard against concurrent double-claims
    if not await users_db.claim_free_trial(current_user["_id"], trial_expiry):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You have already claimed your free trial."
        )

    updated_user = await users_db.get_user(current_user["_id"])
    return build_user_response(updated_user)
