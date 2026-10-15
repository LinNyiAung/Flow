import secrets
from datetime import UTC, datetime, timedelta
from typing import Optional
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
import jwt  # PyJWT (replaces python-jose; same HS256 tokens)
from passlib.context import CryptContext

from config import settings
from database import admins_collection

security_admin = HTTPBearer()
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against its hash"""
    return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password: str) -> str:
    """Hash a password"""
    return pwd_context.hash(password)


ADMIN_TOKEN_TTL = timedelta(hours=8)


def admin_password_version(admin: dict) -> int:
    """Admin's current password version (bumped on every password change; missing = 0)."""
    try:
        return int((admin or {}).get("password_version") or 0)
    except (TypeError, ValueError):
        return 0


def initial_admin_password_version() -> int:
    """
    password_version for a NEWLY created admin: a random positive nonce instead of 0, so
    a stale token of a deleted admin (pwv 0 / missing) can never match a new admin that
    reuses the e-mail address (tokens are additionally bound to the admin _id via "aid").
    """
    return secrets.randbelow(2**31 - 2) + 1


def admin_token_claims(admin: dict) -> dict:
    """Identity claims for an admin token: e-mail (sub), admin _id (aid), password version (pwv)."""
    return {"sub": admin["email"], "aid": admin["_id"], "pwv": admin_password_version(admin)}


def create_admin_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """Create JWT access token for admin.

    Callers should pass admin_token_claims(admin): "aid" binds the token to the admin
    document and "pwv" revokes it when the admin's password (or e-mail) changes.
    """
    to_encode = data.copy()
    expire = datetime.now(UTC) + (expires_delta or timedelta(minutes=60))
    to_encode.update({"exp": expire, "type": "admin"})
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def verify_admin_token_payload(token: str) -> dict:
    """Verify an admin JWT and return its payload (raises 401 if invalid)."""
    try:
        # PyJWT verifies the signature (HS256 only) and exp with leeway 0.
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

    if payload.get("type") != "admin":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token type"
        )

    return payload


def verify_admin_token(token: str) -> str:
    """Verify admin JWT token and return email"""
    return verify_admin_token_payload(token)["sub"]


async def get_current_admin(credentials: HTTPAuthorizationCredentials = Depends(security_admin)):
    """Get current authenticated admin"""
    payload = verify_admin_token_payload(credentials.credentials)
    email = payload["sub"]

    admin = await admins_collection.find_one({"email": email})

    if not admin:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Admin not found"
        )

    # The token must belong to this exact admin document (not a deleted + re-created
    # admin, or another admin that later took over the e-mail address). Legacy tokens
    # without "aid" are rejected: admins sign in again once after this deploy (admin
    # sessions last at most 8 hours anyway).
    aid = payload.get("aid")
    if not isinstance(aid, str) or aid != admin.get("_id"):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session expired. Please sign in again."
        )

    # Tokens issued before the last password (or e-mail) change are revoked. Tokens
    # without "pwv" count as version 0.
    try:
        token_version = int(payload.get("pwv") or 0)
    except (TypeError, ValueError):
        token_version = -1
    if token_version != admin_password_version(admin):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session expired: password or e-mail was changed. Please sign in again."
        )

    # NOTE: last_login is only updated on successful login (see admin_routes.admin_login),
    # not on every authenticated request.
    return admin


def require_super_admin(admin: dict = Depends(get_current_admin)):
    """Middleware to check if admin has super_admin role"""
    if admin.get("role") != "super_admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This action requires super admin privileges"
        )
    return admin


def require_admin_or_super(admin: dict = Depends(get_current_admin)):
    """Middleware to check if admin has admin or super_admin role (write access)"""
    if admin.get("role") not in ["admin", "super_admin"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This action requires admin privileges"
        )
    return admin


def require_moderator_or_above(admin: dict = Depends(get_current_admin)):
    """Read-only access: moderator, admin or super_admin"""
    if admin.get("role") not in ["moderator", "admin", "super_admin"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This action requires moderator privileges"
        )
    return admin


async def log_admin_action(
    admin_id: str,
    admin_email: str,
    action: str,
    target_user_id: Optional[str] = None,
    target_user_email: Optional[str] = None,
    details: Optional[str] = None
):
    """Log admin actions for audit trail"""
    from database import admin_action_logs_collection
    import uuid
    
    log_entry = {
        "_id": str(uuid.uuid4()),
        "admin_id": admin_id,
        "admin_email": admin_email,
        "action": action,
        "target_user_id": target_user_id,
        "target_user_email": target_user_email,
        "details": details,
        "timestamp": datetime.now(UTC)
    }
    
    try:
        # [FIX] Added await for async database insertion
        await admin_action_logs_collection.insert_one(log_entry)
    except Exception as e:
        print(f"Error logging admin action: {e}")