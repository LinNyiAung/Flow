import ipaddress
import re
import threading
import time
import uuid
from datetime import datetime, timedelta, UTC
from typing import Dict, List, Optional, Tuple

from fastapi import APIRouter, HTTPException, Request, status, Depends, Query, Path
from starlette.concurrency import run_in_threadpool


from admin_utils import (
    ADMIN_TOKEN_TTL,
    admin_token_claims,
    create_admin_access_token,
    initial_admin_password_version,
    get_current_admin,
    get_password_hash,
    log_admin_action,
    require_admin_or_super,
    require_moderator_or_above,
    require_super_admin,
    verify_password
)
from admin_models import (
    AdminActionLog,
    AdminCreate,
    AdminFeedbackListResponse,
    FeedbackStatsResponse,
    AdminLogin,
    AdminPasswordChange,
    AdminResponse,
    AdminRole,
    AdminToken,
    AdminUpdate,
    BroadcastNotificationRequest,
    BroadcastNotificationResponse,
    SystemStatsResponse,
    UpdateUserSubscriptionRequest,
    UserDetailResponse,
    UserListResponse,
    UserStatsResponse
)
from firebase_service import send_fcm_data_message, send_fcm_to_multiple
from notification_service import should_send_notification
from subscription_service import active_premium_filter, effectively_free_filter
from models import Currency, SubscriptionType
from sqlalchemy.exc import IntegrityError
from sql import admins as admins_db
from sql import users as users_db
from sql import feedback as feedback_db
from sql import ai_usage as ai_usage_db
from sql import notifications as notifications_db
from sql import chat as chat_db
from sql import goals as goals_db
from sql import transactions as transactions_db
from sql import budgets as budgets_db
from ai_usage_models import AIUsageResponse, UserAIUsageStats, AIUsageStatsResponse, AIFeatureType, AIProviderType
from config import settings

router = APIRouter(prefix="/api/admin", tags=["admin"])


# ==================== HELPERS ====================

def _to_aware_utc(dt: Optional[datetime]) -> Optional[datetime]:
    """Normalise a datetime to timezone-aware UTC (naive values are assumed UTC)."""
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC)


async def _find_admin_by_email(email: str) -> Optional[dict]:
    """Case-insensitive admin lookup (e-mails are unique on lower(email))."""
    return await admins_db.get_admin_by_email(email)


# In-memory admin login lockout (single uvicorn worker assumed):
# 5 failed attempts within 15 minutes from one client IP for one email -> that
# (email, IP) pair is locked for 15 minutes. Keying by the pair means an attacker can't
# lock a real admin out from their own IP. Entries are purged opportunistically and the
# maps are capped so they can't grow without bound.
ADMIN_MAX_FAILED_LOGINS = 5
ADMIN_LOCKOUT_SECONDS = 15 * 60
ADMIN_LOCKOUT_MAX_ENTRIES = 10_000
_LockKey = Tuple[str, str]  # (normalized email, client ip)
_admin_failed_logins: Dict[_LockKey, List[float]] = {}
_admin_locked_until: Dict[_LockKey, float] = {}
_admin_lockout_lock = threading.Lock()


_IPV4_MAPPED_NET = ipaddress.ip_network("::ffff:0:0/96")


def _unmap_ip(ip):
    """IPv4-mapped IPv6 (::ffff:a.b.c.d) -> the IPv4 address; anything else unchanged."""
    if isinstance(ip, ipaddress.IPv6Address) and ip.ipv4_mapped is not None:
        return ip.ipv4_mapped
    return ip


def _parse_ip(value: Optional[str]):
    """
    Parse one address as found in X-Forwarded-For / request.client.host; None if unusable.

    Accepts surrounding whitespace/quotes, "1.2.3.4", "1.2.3.4:5678", "2001:db8::1",
    "[2001:db8::1]" and "[2001:db8::1]:443"; IPv4-mapped IPv6 is normalised to IPv4.
    """
    if not isinstance(value, str):
        return None
    s = value.strip().strip('"').strip()
    if not s or len(s) > 100:
        return None
    if s.startswith("["):
        end = s.find("]")
        if end == -1:
            return None
        host, rest = s[1:end], s[end + 1:]
        if rest and not (rest.startswith(":") and rest[1:].isdigit()):
            return None
    elif s.count(":") == 1:
        # IPv4 with a port (a bare IPv6 address always has 2+ colons)
        host, port = s.split(":")
        if not port.isdigit():
            return None
    else:
        host = s
    try:
        return _unmap_ip(ipaddress.ip_address(host))
    except ValueError:
        return None


def _parse_trusted_network(entry: str):
    """One TRUSTED_PROXY_IPS entry (IP or CIDR) as a network; IPv4-mapped ranges become IPv4."""
    net = ipaddress.ip_network(entry.strip(), strict=False)
    if (
        isinstance(net, ipaddress.IPv6Network)
        and net.prefixlen >= 96
        and net.network_address in _IPV4_MAPPED_NET
    ):
        net = ipaddress.ip_network(f"{net.network_address.ipv4_mapped}/{net.prefixlen - 96}", strict=False)
    return net


def _trusted_proxy_networks():
    networks = []
    for entry in settings.TRUSTED_PROXY_IPS:
        try:
            networks.append(_parse_trusted_network(entry))
        except ValueError:
            pass  # ignore malformed entries
    return networks


def _is_trusted_proxy(ip, networks) -> bool:
    return ip is not None and any(ip.version == net.version and ip in net for net in networks)


def client_ip_from_request(request: Optional[Request]) -> str:
    """
    Client IP for rate limiting / lockout (see TRUSTED_PROXY_IPS / TRUST_FORWARDED_FOR in config.py).

    - Default: the TCP peer; X-Forwarded-For is ignored (it is client-controlled).
    - TRUST_FORWARDED_FOR=true: the RIGHT-most X-Forwarded-For entry, i.e. the address
      appended by the immediate proxy (e.g. Render); the entries left of it are
      client-controlled. Falls back to the peer when that entry is unparseable.
    - Peer in TRUSTED_PROXY_IPS: X-Forwarded-For walked right-to-left, skipping trusted
      proxies; the first untrusted hop is the client.
    Addresses are normalised (IPv4-mapped IPv6 -> IPv4, ports stripped).
    """
    if request is None:
        return "unknown"
    raw_peer = request.client.host if request.client else None
    peer_ip = _parse_ip(raw_peer)
    peer = str(peer_ip) if peer_ip is not None else (raw_peer or "unknown")
    forwarded = ",".join(request.headers.getlist("x-forwarded-for")) if hasattr(request.headers, "getlist") \
        else (request.headers.get("x-forwarded-for") or "")
    hops = [h.strip() for h in forwarded.split(",") if h.strip()]
    if hops:
        if settings.TRUST_FORWARDED_FOR:
            last = _parse_ip(hops[-1])
            if last is not None:
                return str(last)
        else:
            networks = _trusted_proxy_networks()
            if networks and _is_trusted_proxy(peer_ip, networks):
                for hop in reversed(hops):
                    ip = _parse_ip(hop)
                    if ip is None:
                        return peer  # garbage in the chain: don't trust anything left of it
                    if not _is_trusted_proxy(ip, networks):
                        return str(ip)
                # every hop is a trusted proxy: the left-most one is the origin
                return str(_parse_ip(hops[0]))
    return peer


def _admin_lock_key(email: Optional[str], request: Optional[Request]) -> _LockKey:
    return ((email or "").strip().lower(), client_ip_from_request(request))


def _admin_purge_locked(now: float) -> None:
    """Drop expired entries and enforce the size cap. Caller holds _admin_lockout_lock."""
    for key in [k for k, until in _admin_locked_until.items() if until <= now]:
        del _admin_locked_until[key]
    for key in [k for k, ts in _admin_failed_logins.items() if not ts or now - ts[-1] >= ADMIN_LOCKOUT_SECONDS]:
        del _admin_failed_logins[key]
    # Still too big: evict the oldest (dicts keep insertion order; refreshed keys move last).
    for mapping in (_admin_failed_logins, _admin_locked_until):
        overflow = len(mapping) - ADMIN_LOCKOUT_MAX_ENTRIES
        if overflow > 0:
            for key in list(mapping)[:overflow]:
                del mapping[key]


def _admin_is_locked(key: _LockKey) -> bool:
    now = time.monotonic()
    with _admin_lockout_lock:
        until = _admin_locked_until.get(key)
        if until is None:
            return False
        if until > now:
            return True
        _admin_locked_until.pop(key, None)
        return False


def _admin_record_failure(key: _LockKey) -> None:
    now = time.monotonic()
    with _admin_lockout_lock:
        attempts = [t for t in _admin_failed_logins.pop(key, []) if now - t < ADMIN_LOCKOUT_SECONDS]
        attempts.append(now)
        if len(attempts) >= ADMIN_MAX_FAILED_LOGINS:
            _admin_locked_until.pop(key, None)
            _admin_locked_until[key] = now + ADMIN_LOCKOUT_SECONDS
        else:
            _admin_failed_logins[key] = attempts  # re-inserted -> newest
        if (
            len(_admin_failed_logins) > ADMIN_LOCKOUT_MAX_ENTRIES
            or len(_admin_locked_until) > ADMIN_LOCKOUT_MAX_ENTRIES
            or len(_admin_failed_logins) % 256 == 0
        ):
            _admin_purge_locked(now)


def _admin_clear_failures(key: _LockKey) -> None:
    with _admin_lockout_lock:
        _admin_failed_logins.pop(key, None)
        _admin_locked_until.pop(key, None)


# ==================== ADMIN AUTHENTICATION ====================

@router.post("/login", response_model=AdminToken)
async def admin_login(credentials: AdminLogin, request: Request):
    """Admin login (locked for 15 minutes after 5 failed attempts per email + client IP)"""
    lock_key = _admin_lock_key(credentials.email, request)

    if _admin_is_locked(lock_key):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many failed login attempts. Please try again in 15 minutes."
        )

    admin = await _find_admin_by_email(lock_key[0])

    if (
        not admin
        or not admin.get("password")
        or not await run_in_threadpool(verify_password, credentials.password, admin["password"])
    ):
        _admin_record_failure(lock_key)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password"
        )

    _admin_clear_failures(lock_key)

    login_time = datetime.now(UTC)
    await admins_db.set_last_login(admin["_id"], login_time)

    access_token = create_admin_access_token(
        data=admin_token_claims(admin),
        expires_delta=ADMIN_TOKEN_TTL
    )

    return AdminToken(
        access_token=access_token,
        token_type="bearer",
        admin=AdminResponse(
            id=admin["_id"],
            name=admin["name"],
            email=admin["email"],
            role=AdminRole(admin["role"]),
            created_at=admin["created_at"],
            last_login=login_time
        )
    )


@router.get("/me", response_model=AdminResponse)
async def get_current_admin_info(current_admin: dict = Depends(get_current_admin)):
    """Get current admin info"""
    return AdminResponse(
        id=current_admin["_id"],
        name=current_admin["name"],
        email=current_admin["email"],
        role=AdminRole(current_admin["role"]),
        created_at=current_admin["created_at"],
        last_login=current_admin.get("last_login")
    )


@router.put("/change-password")
async def admin_change_password(
    password_data: AdminPasswordChange,
    current_admin: dict = Depends(get_current_admin)
):
    """Change admin password"""
    if not await run_in_threadpool(verify_password, password_data.current_password, current_admin["password"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Current password is incorrect"
        )

    if len(password_data.new_password) < 8:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="New password must be at least 8 characters"
        )

    if password_data.new_password != password_data.confirm_password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="New passwords do not match"
        )

    hashed_password = await run_in_threadpool(get_password_hash, password_data.new_password)
    # Bumping password_version revokes every token issued before the change (tokens
    # carry it as "pwv"; get_current_admin rejects mismatches).
    updated_admin = await admins_db.change_password(current_admin["_id"], hashed_password)
    if not updated_admin:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Admin not found")

    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"],
        action="changed_password"
    )

    # Fresh token for the session that made the change (all older tokens are now invalid).
    access_token = create_admin_access_token(
        data=admin_token_claims(updated_admin),
        expires_delta=ADMIN_TOKEN_TTL,
    )
    return {
        "message": "Password changed successfully",
        "access_token": access_token,
        "token_type": "bearer",
    }


@router.put("/me", response_model=AdminResponse)
async def update_admin_profile(
    update_data: AdminUpdate,
    current_admin: dict = Depends(get_current_admin)
):
    """Update current admin profile"""
    update_fields = {}

    if update_data.name and update_data.name != current_admin["name"]:
        update_fields["name"] = update_data.name

    new_email = (update_data.email or "").strip().lower()
    if new_email and new_email != (current_admin.get("email") or "").strip().lower():
        # Same normalisation + case-insensitive duplicate check as create-admin.
        existing = await _find_admin_by_email(new_email)
        if existing and existing["_id"] != current_admin["_id"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already in use"
            )
        update_fields["email"] = new_email

    if not update_fields:
        return AdminResponse(
            id=current_admin["_id"],
            name=current_admin["name"],
            email=current_admin["email"],
            role=AdminRole(current_admin["role"]),
            created_at=current_admin["created_at"],
            last_login=current_admin.get("last_login")
        )

    # Changing the sign-in e-mail revokes every existing token of this admin
    # (including the current session: the admin signs in again with the new e-mail).
    await admins_db.update_profile(current_admin["_id"], update_fields, bump_version="email" in update_fields)

    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"],
        action="updated_profile",
        details=f"Updated profile fields: {', '.join(update_fields.keys())}"
    )

    updated_admin = await admins_db.get_admin_by_id(current_admin["_id"])

    return AdminResponse(
        id=updated_admin["_id"],
        name=updated_admin["name"],
        email=updated_admin["email"],
        role=AdminRole(updated_admin["role"]),
        created_at=updated_admin["created_at"],
        last_login=updated_admin.get("last_login")
    )


# ==================== ADMIN MANAGEMENT (Super Admin Only) ====================

@router.post("/admins", response_model=AdminResponse)
async def create_admin(
    admin_data: AdminCreate,
    current_admin: dict = Depends(require_super_admin)
):
    """Create new admin (super admin only)"""
    new_email = admin_data.email.strip().lower()
    if await _find_admin_by_email(new_email):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered"
        )

    admin_id = str(uuid.uuid4())
    new_admin = {
        "_id": admin_id,
        "name": admin_data.name,
        "email": new_email,
        "password": await run_in_threadpool(get_password_hash, admin_data.password),
        "role": admin_data.role.value,
        # Random starting version: stale tokens of a deleted admin with the same e-mail
        # (pwv 0 / missing) can never match (tokens are also bound to the _id via "aid").
        "password_version": initial_admin_password_version(),
        "created_at": datetime.now(UTC),
        "last_login": None
    }

    try:
        await admins_db.insert_admin(new_admin)
    except IntegrityError:
        # Unique lower(email): a concurrent request created the same admin first.
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered")

    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"],
        action="created_admin",
        details=f"Created admin: {admin_data.email} with role {admin_data.role.value}"
    )

    return AdminResponse(
        id=admin_id,
        name=new_admin["name"],
        email=new_admin["email"],
        role=AdminRole(new_admin["role"]),
        created_at=new_admin["created_at"],
        last_login=None
    )


@router.get("/admins", response_model=List[AdminResponse])
async def get_all_admins(current_admin: dict = Depends(require_super_admin)):
    """Get all admins (super admin only)"""
    admins = await admins_db.list_admins()

    return [
        AdminResponse(
            id=admin["_id"],
            name=admin["name"],
            email=admin["email"],
            role=AdminRole(admin["role"]),
            created_at=admin["created_at"],
            last_login=admin.get("last_login")
        )
        for admin in admins
    ]


@router.delete("/admins/{admin_id}")
async def delete_admin(
    admin_id: str = Path(...),
    current_admin: dict = Depends(require_super_admin)
):
    """Delete admin (super admin only)"""
    if admin_id == current_admin["_id"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot delete yourself"
        )

    admin_to_delete = await admins_db.get_admin_by_id(admin_id)
    if not admin_to_delete:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Admin not found"
        )

    if await admins_db.delete_admin(admin_id) == 0:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Admin not found"
        )

    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"],
        action="deleted_admin",
        details=f"Deleted admin: {admin_to_delete['email']}"
    )

    return {"message": "Admin deleted successfully"}


# ==================== USER MANAGEMENT ====================

@router.get("/users", response_model=List[UserListResponse])
async def get_all_users(
    current_admin: dict = Depends(require_moderator_or_above),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    search: Optional[str] = Query(None),
    subscription_type: Optional[SubscriptionType] = Query(None)
):
    """Get all users with pagination and filters"""
    users = await users_db.admin_list(search, subscription_type.value if subscription_type else None, skip, limit)

    user_list = []
    for user in users:
        transaction_count = await transactions_db.count_transactions(user["_id"])
        goals_count = await goals_db.count_goals(user["_id"])

        last_tx_at = await transactions_db.latest_created_at(user["_id"])
        last_transaction = {"created_at": last_tx_at} if last_tx_at else None
        last_chat_at = await chat_db.latest_activity(user["_id"])
        last_chat = {"updated_at": last_chat_at} if last_chat_at else None

        last_active = None
        if last_transaction and last_chat:
            last_active = max(
                last_transaction.get("created_at"),
                last_chat.get("updated_at")
            )
        elif last_transaction:
            last_active = last_transaction.get("created_at")
        elif last_chat:
            last_active = last_chat.get("updated_at")

        user_list.append(UserListResponse(
            id=user["_id"],
            name=user["name"],
            email=user["email"],
            subscription_type=SubscriptionType(user.get("subscription_type", "free")),
            subscription_expires_at=user.get("subscription_expires_at"),
            default_currency=Currency(user.get("default_currency", "usd")),
            created_at=user["created_at"],
            total_transactions=transaction_count,
            total_goals=goals_count,
            last_active=last_active
        ))

    return user_list


@router.get("/users/{user_id}", response_model=UserDetailResponse)
async def get_user_detail(
    user_id: str = Path(...),
    current_admin: dict = Depends(require_moderator_or_above)
):
    """Get detailed user information"""
    user = await users_db.get_user(user_id)

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    transaction_count = await transactions_db.count_transactions(user_id)
    goals_count = await goals_db.count_goals(user_id)
    budgets_count = await budgets_db.count_budgets(user_id)
    chat_sessions_count = await chat_db.count_sessions(user_id)

    last_tx_at = await transactions_db.latest_created_at(user_id)
    last_transaction = {"created_at": last_tx_at} if last_tx_at else None
    last_chat_at = await chat_db.latest_activity(user_id)
    last_chat = {"updated_at": last_chat_at} if last_chat_at else None

    last_active = None
    if last_transaction and last_chat:
        last_active = max(
            last_transaction.get("created_at"),
            last_chat.get("updated_at")
        )
    elif last_transaction:
        last_active = last_transaction.get("created_at")
    elif last_chat:
        last_active = last_chat.get("updated_at")

    return UserDetailResponse(
        id=user["_id"],
        name=user["name"],
        email=user["email"],
        subscription_type=SubscriptionType(user.get("subscription_type", "free")),
        subscription_expires_at=user.get("subscription_expires_at"),
        default_currency=Currency(user.get("default_currency", "usd")),
        language=user.get("language", "en"),
        created_at=user["created_at"],
        total_transactions=transaction_count,
        total_goals=goals_count,
        total_budgets=budgets_count,
        total_chat_sessions=chat_sessions_count,
        last_active=last_active
    )


@router.put("/users/{user_id}/subscription")
async def update_user_subscription(
    user_id: str = Path(...),
    subscription_data: UpdateUserSubscriptionRequest = ...,
    current_admin: dict = Depends(require_admin_or_super)
):
    """Update user subscription and instantly notify their device to refresh"""
    user = await users_db.get_user(user_id)

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    update_data = {
        "subscription_type": subscription_data.subscription_type.value,
        # Always store timezone-aware UTC
        "subscription_expires_at": _to_aware_utc(subscription_data.subscription_expires_at)
    }

    await users_db.update_user(user_id, **update_data)

    # Send a silent FCM data-only message so the app refreshes instantly.
    # Blocking firebase call runs in a threadpool so the event loop isn't blocked.
    fcm_token = user.get("fcm_token")
    fcm_sent = False
    if fcm_token:
        fcm_sent = await run_in_threadpool(
            send_fcm_data_message,
            fcm_token,
            {
                "type": "subscription_updated",
                "subscription_type": subscription_data.subscription_type.value,
            },
        )
        if fcm_sent:
            print(f"✅ Subscription refresh FCM sent to user {user_id}")
        else:
            print(f"⚠️  Could not send FCM refresh to user {user_id} (token may be stale)")
    # ────────────────────────────────────────────────────────────────────────────

    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"],
        action="updated_user_subscription",
        target_user_id=user_id,
        target_user_email=user["email"],
        details=f"Updated subscription to {subscription_data.subscription_type.value}"
    )

    return {
        "message": "User subscription updated successfully",
        "fcm_refresh_sent": fcm_sent
    }


@router.delete("/users/{user_id}")
async def delete_user(
    user_id: str = Path(...),
    current_admin: dict = Depends(require_super_admin)
):
    """Delete user and all associated data (super admin only)"""
    user = await users_db.get_user(user_id)

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    # Every table cascades from users (ON DELETE CASCADE): one atomic delete.
    if await users_db.delete_user(user_id) == 0:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete user"
        )

    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"],
        action="deleted_user",
        target_user_id=user_id,
        target_user_email=user["email"],
        details="Deleted user and all associated data"
    )

    return {"message": "User deleted successfully"}


# ==================== STATISTICS ====================

@router.get("/stats/users", response_model=UserStatsResponse)
async def get_user_stats(current_admin: dict = Depends(require_moderator_or_above)):
    """Get user statistics"""
    total_users = await users_db.count_users()
    # Expired premium counts as free (subscription_service has the one definition).
    free_users = await users_db.count_users(effectively_free_filter())
    premium_users = await users_db.count_users(active_premium_filter())

    thirty_days_ago = datetime.now(UTC) - timedelta(days=30)
    new_users_last_30_days = await users_db.count_users(users_db.users.c.created_at >= thirty_days_ago)

    seven_days_ago = datetime.now(UTC) - timedelta(days=7)
    active_user_ids = set()

    active_user_ids.update(await transactions_db.active_user_ids(seven_days_ago))

    active_user_ids.update(await chat_db.active_user_ids(seven_days_ago))

    active_users_last_7_days = len(active_user_ids)

    total_transactions = await transactions_db.count_transactions()
    total_goals = await goals_db.count_goals()

    return UserStatsResponse(
        total_users=total_users,
        free_users=free_users,
        premium_users=premium_users,
        new_users_last_30_days=new_users_last_30_days,
        active_users_last_7_days=active_users_last_7_days,
        total_transactions=total_transactions,
        total_goals=total_goals
    )


@router.get("/stats/system", response_model=SystemStatsResponse)
async def get_system_stats(current_admin: dict = Depends(require_moderator_or_above)):
    """Get comprehensive system statistics"""
    now = datetime.now(UTC)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    week_start = now - timedelta(days=7)
    month_start = now - timedelta(days=30)

    total_users = await users_db.count_users()
    free_users = await users_db.count_users(effectively_free_filter(now))
    premium_users = await users_db.count_users(active_premium_filter(now))

    created = users_db.users.c.created_at
    new_users_today = await users_db.count_users(created >= today_start)
    new_users_this_week = await users_db.count_users(created >= week_start)
    new_users_this_month = await users_db.count_users(created >= month_start)

    active_today = set()
    active_week = set()

    active_today.update(await transactions_db.active_user_ids(today_start))
    active_week.update(await transactions_db.active_user_ids(week_start))

    active_today.update(await chat_db.active_user_ids(today_start))
    active_week.update(await chat_db.active_user_ids(week_start))

    total_transactions = await transactions_db.count_transactions()
    total_goals = await goals_db.count_goals()
    total_budgets = await budgets_db.count_budgets()
    total_chat_sessions = await chat_db.count_sessions()
    total_notifications = await notifications_db.count_all()

    return SystemStatsResponse(
        total_users=total_users,
        free_users=free_users,
        premium_users=premium_users,
        total_transactions=total_transactions,
        total_goals=total_goals,
        total_budgets=total_budgets,
        total_chat_sessions=total_chat_sessions,
        total_notifications=total_notifications,
        new_users_today=new_users_today,
        new_users_this_week=new_users_this_week,
        new_users_this_month=new_users_this_month,
        active_users_today=len(active_today),
        active_users_this_week=len(active_week)
    )



# ==================== NOTIFICATION BROADCAST ====================

@router.post("/broadcast-notification", response_model=BroadcastNotificationResponse)
async def broadcast_notification(
    broadcast_data: BroadcastNotificationRequest,
    current_admin: dict = Depends(require_admin_or_super)
):
    """Broadcast notification to users based on criteria"""
    try:
        notification_type = broadcast_data.notification_type.value

        conditions = []
        # Expired premium users are effectively free: target them with the free group.
        if broadcast_data.target_users == "free":
            conditions.append(effectively_free_filter())
        elif broadcast_data.target_users == "premium":
            conditions.append(active_premium_filter())

        users = await users_db.list_fields(["fcm_token"], *conditions)
        total_users = len(users)

        if total_users == 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No users found matching the criteria"
            )

        notifications_sent = 0
        fcm_tokens = []
        pending_docs = []
        now = datetime.now(UTC)

        for user in users:
            user_id = user["_id"]

            if not await should_send_notification(user_id, notification_type):
                continue

            pending_docs.append({
                "_id": str(uuid.uuid4()),
                "user_id": user_id,
                "type": notification_type,
                "title": broadcast_data.title,
                "message": broadcast_data.message,
                "goal_id": None,
                "goal_name": None,
                "currency": None,
                "created_at": now,
                "is_read": False
            })

            if user.get("fcm_token"):
                fcm_tokens.append(user["fcm_token"])

            if len(pending_docs) >= 500:
                notifications_sent += await notifications_db.insert_many(pending_docs)
                pending_docs = []

        if pending_docs:
            notifications_sent += await notifications_db.insert_many(pending_docs)

        fcm_result = {"success": 0, "failure": 0}
        if fcm_tokens:
            fcm_data = {
                "type": notification_type,
                "is_broadcast": "true"
            }
            # Blocking firebase calls (chunked by 500 inside) run in a threadpool
            fcm_result = await run_in_threadpool(
                send_fcm_to_multiple,
                fcm_tokens=list(dict.fromkeys(fcm_tokens)),
                title=broadcast_data.title,
                body=broadcast_data.message,
                data=fcm_data
            )

        await log_admin_action(
            admin_id=current_admin["_id"],
            admin_email=current_admin["email"],
            action="broadcast_notification",
            details=f"Sent '{broadcast_data.title}' to {broadcast_data.target_users} users ({notifications_sent} notifications, {fcm_result['success']} FCM sent)"
        )

        return BroadcastNotificationResponse(
            message=f"Broadcast notification sent successfully",
            total_users=total_users,
            notifications_sent=notifications_sent,
            fcm_sent=fcm_result["success"],
            fcm_failed=fcm_result["failure"]
        )

    except HTTPException:
        raise
    except Exception as e:
        print(f"Error broadcasting notification: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to broadcast notification"
        )


@router.get("/broadcast-stats")
async def get_broadcast_stats(
    current_admin: dict = Depends(require_moderator_or_above)
):
    """Get statistics for potential broadcast reach"""
    try:
        now = datetime.now(UTC)
        has_fcm = users_db.HAS_DEVICE
        total_users = await users_db.count_users()
        free_users = await users_db.count_users(effectively_free_filter(now))
        premium_users = await users_db.count_users(active_premium_filter(now))

        users_with_fcm = await users_db.count_users(has_fcm)
        free_with_fcm = await users_db.count_users(effectively_free_filter(now), has_fcm)
        premium_with_fcm = await users_db.count_users(active_premium_filter(now), has_fcm)

        return {
            "total_users": total_users,
            "free_users": free_users,
            "premium_users": premium_users,
            "users_with_push_enabled": users_with_fcm,
            "free_with_push": free_with_fcm,
            "premium_with_push": premium_with_fcm
        }

    except Exception as e:
        print(f"Error getting broadcast stats: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get broadcast statistics"
        )



# ==================== AI USAGE MONITORING ====================

@router.get("/ai-usage/stats", response_model=AIUsageStatsResponse)
async def get_ai_usage_stats(
    current_admin: dict = Depends(require_moderator_or_above),
    start_date: Optional[datetime] = Query(None),
    end_date: Optional[datetime] = Query(None)
):
    """Get overall AI usage statistics"""
    try:
        stats = await ai_usage_db.overall_stats(start_date, end_date)
        unique_users = stats["unique_users"]

        return AIUsageStatsResponse(
            total_users=unique_users,
            total_requests=stats["total_requests"],
            total_tokens=stats["total_tokens"],
            total_cost_usd=round(stats["total_cost"], 4),
            openai_total_cost=round(stats["openai_cost"], 4),
            gemini_total_cost=round(stats["gemini_cost"], 4),
            weekly_insights_requests=stats["weekly_insights"],
            monthly_insights_requests=stats["monthly_insights"],
            chat_requests=stats["chat_requests"],
            translation_requests=stats["translations"]
        )

    except Exception as e:
        print(f"Error getting AI usage stats: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get AI usage statistics"
        )


@router.get("/ai-usage/users", response_model=List[UserAIUsageStats])
async def get_users_ai_usage(
    current_admin: dict = Depends(require_moderator_or_above),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    sort_by: str = Query("total_cost", pattern="^(total_cost|total_tokens|total_requests)$"),
    start_date: Optional[datetime] = Query(None),
    end_date: Optional[datetime] = Query(None)
):
    """Get AI usage statistics per user (optionally within [start_date, end_date])"""
    try:
        results = await ai_usage_db.per_user_stats(start_date, end_date, sort_by, skip, limit)

        user_stats = [
            UserAIUsageStats(
                user_id=result["user_id"],
                user_name=result["user_name"],
                user_email=result["user_email"],
                total_requests=result["total_requests"],
                total_input_tokens=result["total_input_tokens"],
                total_output_tokens=result["total_output_tokens"],
                total_tokens=result["total_tokens"],
                total_cost_usd=round(result["total_cost"], 4),
                weekly_insights_count=result["weekly_insights"],
                monthly_insights_count=result["monthly_insights"],
                chat_requests_count=result["chat_requests"],
                translation_count=result["translations"],
                openai_cost=round(result["openai_cost"], 4),
                gemini_cost=round(result["gemini_cost"], 4)
            )
            for result in results
        ]

        return user_stats

    except Exception as e:
        print(f"Error getting users AI usage: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get users AI usage"
        )


@router.get("/ai-usage/user/{user_id}", response_model=List[AIUsageResponse])
async def get_user_ai_usage_detail(
    user_id: str = Path(...),
    current_admin: dict = Depends(require_moderator_or_above),
    limit: int = Query(100, ge=1, le=500),
    feature_type: Optional[AIFeatureType] = Query(None)
):
    """Get detailed AI usage for a specific user"""
    try:
        usage_records = await ai_usage_db.user_detail(user_id, feature_type.value if feature_type else None, limit)

        return [
            AIUsageResponse(
                id=record["_id"],
                user_id=record["user_id"],
                feature_type=AIFeatureType(record["feature_type"]),
                provider=AIProviderType(record["provider"]),
                model_name=record["model_name"],
                input_tokens=record["input_tokens"],
                output_tokens=record["output_tokens"],
                total_tokens=record["total_tokens"],
                estimated_cost_usd=record["estimated_cost_usd"],
                created_at=record["created_at"]
            )
            for record in usage_records
        ]

    except Exception as e:
        print(f"Error getting user AI usage detail: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get user AI usage detail"
        )



@router.get("/ai-usage/stats/budgets", response_model=Dict)
async def get_budget_ai_usage_stats(
    current_admin: dict = Depends(require_moderator_or_above),
    start_date: Optional[datetime] = Query(None),
    end_date: Optional[datetime] = Query(None)
):
    """Get AI usage statistics specifically for budget features"""
    try:
        results = await ai_usage_db.feature_stats(["budget_suggestion", "budget_auto_create"], start_date, end_date)

        stats = {
            "budget_suggestion": {"requests": 0, "tokens": 0, "cost": 0.0, "unique_users": 0},
            "budget_auto_create": {"requests": 0, "tokens": 0, "cost": 0.0, "unique_users": 0},
            "total": {"requests": 0, "tokens": 0, "cost": 0.0, "unique_users": set()}
        }

        for result in results:
            feature = result["feature_type"]
            stats[feature]["requests"] = result["total_requests"]
            stats[feature]["tokens"] = result["total_tokens"]
            stats[feature]["cost"] = round(result["total_cost"], 4)
            stats[feature]["unique_users"] = len(result["user_ids"])

            stats["total"]["requests"] += result["total_requests"]
            stats["total"]["tokens"] += result["total_tokens"]
            stats["total"]["cost"] += result["total_cost"]
            stats["total"]["unique_users"].update(result["user_ids"])

        stats["total"]["unique_users"] = len(stats["total"]["unique_users"])
        stats["total"]["cost"] = round(stats["total"]["cost"], 4)

        return stats

    except Exception as e:
        print(f"Error getting budget AI usage stats: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get budget AI usage statistics"
        )



@router.get("/ai-usage/stats/transactions", response_model=Dict)
async def get_transaction_extraction_ai_usage_stats(
    current_admin: dict = Depends(require_moderator_or_above),
    start_date: Optional[datetime] = Query(None),
    end_date: Optional[datetime] = Query(None)
):
    """Get AI usage statistics specifically for transaction extraction features"""
    try:
        results = await ai_usage_db.feature_stats(
            ["transaction_text_extraction", "transaction_image_extraction", "transaction_audio_transcription"],
            start_date, end_date,
        )

        stats = {
            "transaction_text_extraction": {"requests": 0, "tokens": 0, "cost": 0.0, "unique_users": 0},
            "transaction_image_extraction": {"requests": 0, "tokens": 0, "cost": 0.0, "unique_users": 0},
            "transaction_audio_transcription": {"requests": 0, "tokens": 0, "cost": 0.0, "unique_users": 0},
            "total": {"requests": 0, "tokens": 0, "cost": 0.0, "unique_users": set()}
        }

        for result in results:
            feature = result["feature_type"]
            stats[feature]["requests"] = result["total_requests"]
            stats[feature]["tokens"] = result["total_tokens"]
            stats[feature]["cost"] = round(result["total_cost"], 4)
            stats[feature]["unique_users"] = len(result["user_ids"])

            stats["total"]["requests"] += result["total_requests"]
            stats["total"]["tokens"] += result["total_tokens"]
            stats["total"]["cost"] += result["total_cost"]
            stats["total"]["unique_users"].update(result["user_ids"])

        stats["total"]["unique_users"] = len(stats["total"]["unique_users"])
        stats["total"]["cost"] = round(stats["total"]["cost"], 4)

        return stats

    except Exception as e:
        print(f"Error getting transaction extraction AI usage stats: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get transaction extraction AI usage statistics"
        )


# ==================== ADMIN ACTION LOGS ====================

@router.get("/logs", response_model=List[AdminActionLog])
async def get_admin_logs(
    current_admin: dict = Depends(require_super_admin),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100)
):
    """Get admin action logs (super admin only)"""
    logs = await admins_db.list_logs(skip, limit)

    return [
        AdminActionLog(
            id=log["_id"],
            admin_id=log["admin_id"],
            admin_email=log["admin_email"],
            action=log["action"],
            target_user_id=log.get("target_user_id"),
            target_user_email=log.get("target_user_email"),
            details=log.get("details"),
            timestamp=log["timestamp"]
        )
        for log in logs
    ]


# ==================== FEEDBACK MANAGEMENT ====================

@router.get("/feedback/stats", response_model=FeedbackStatsResponse)
async def get_feedback_stats(
    current_admin: dict = Depends(require_moderator_or_above),
):
    """Aggregate statistics over ALL feedback (not just the current page)"""
    stats = await feedback_db.stats()
    avg = stats.get("average_rating")
    return FeedbackStatsResponse(
        total=stats["total"],
        pending=stats["pending"],
        reviewed=stats["reviewed"],
        resolved=stats["resolved"],
        average_rating=round(float(avg), 2) if avg is not None else None,
    )


@router.get("/feedback", response_model=List[AdminFeedbackListResponse])
async def get_all_feedback(
    current_admin: dict = Depends(require_moderator_or_above),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    category: Optional[str] = None,
    status: Optional[str] = Query(None, pattern="^(pending|reviewed|resolved)$"),
):
    """Get all user feedback"""
    feedbacks = await feedback_db.list_feedback(category, status, skip, limit)

    return [
        AdminFeedbackListResponse(
            id=fb["_id"],
            user_id=fb["user_id"],
            user_name=fb.get("user_name", "Unknown"),
            user_email=fb.get("user_email", "Unknown"),
            category=fb["category"],
            message=fb["message"],
            rating=fb.get("rating"),
            created_at=fb["created_at"],
            status=fb.get("status", "pending")
        )
        for fb in feedbacks
    ]

@router.put("/feedback/{feedback_id}/status")
async def update_feedback_status(
    feedback_id: str = Path(...),
    status_update: str = Query(..., pattern="^(pending|reviewed|resolved)$"),
    current_admin: dict = Depends(require_admin_or_super)
):
    """Update feedback status"""
    # Matched rows: setting the same status again is a no-op, not a 404
    if await feedback_db.set_status(feedback_id, status_update) == 0:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Feedback not found"
        )

    return {"message": "Feedback status updated"}

@router.delete("/feedback/{feedback_id}")
async def delete_feedback(
    feedback_id: str = Path(...),
    current_admin: dict = Depends(require_super_admin)
):
    """Delete feedback (Super Admin only)"""
    if await feedback_db.delete_feedback(feedback_id) == 0:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Feedback not found"
        )

    return {"message": "Feedback deleted successfully"}