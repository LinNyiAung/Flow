"""MongoDB document -> PostgreSQL row conversion, one function per table.

Used by the one-time data migration (and by the E2E harness for direct test inserts), so
every rule here is applied to real production data. Each converter accepts any shape the
old code ever wrote (missing fields, legacy defaults, strings for dates, ...) and returns
a row that satisfies the PostgreSQL schema, applying the SAME defaults the application
code used when it read those documents. Rows that can't be made valid raise
`Quarantine(reason)` so the migration can set them aside instead of dropping them.
"""
from datetime import datetime, UTC
from typing import Any, Dict, Optional

MIGRATION_TIME = datetime.now(UTC)
CURRENCIES = {"usd", "mmk", "thb"}


class Quarantine(Exception):
    """The document can't be stored as a valid row; carries the reason."""


def as_datetime(value: Any) -> Optional[datetime]:
    """datetime / ISO string -> timezone-aware UTC datetime (naive values are UTC, as Motor returned them)."""
    if value is None or value == "":
        return None
    if isinstance(value, str):
        try:
            value = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    if not isinstance(value, datetime):
        return None
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def _str_or_none(value: Any) -> Optional[str]:
    return value if isinstance(value, str) and value != "" else None


def _choice(value: Any, allowed: set, default: str) -> str:
    return value if value in allowed else default


def _int_or(value: Any, default: Optional[int]) -> Optional[int]:
    try:
        return int(value) if value is not None and not isinstance(value, bool) else default
    except (TypeError, ValueError):
        return default


def convert_user(doc: Dict[str, Any]) -> Dict[str, Any]:
    if not doc.get("_id") or not isinstance(doc.get("email"), str) or not doc["email"].strip():
        raise Quarantine("user without id or e-mail")
    if not doc.get("password"):
        raise Quarantine("user without password hash")
    return {
        "id": str(doc["_id"]),
        "name": doc.get("name") or doc["email"].split("@")[0],
        "email": doc["email"].strip().lower(),
        "password": doc["password"],
        "password_version": _int_or(doc.get("password_version"), 0) or 0,
        "password_changed_at": as_datetime(doc.get("password_changed_at")),
        "subscription_type": _choice(doc.get("subscription_type"), {"free", "premium"}, "free"),
        "subscription_expires_at": as_datetime(doc.get("subscription_expires_at")),
        "premium_ended_at": as_datetime(doc.get("premium_ended_at")),
        "has_claimed_free_trial": bool(doc.get("has_claimed_free_trial", False)),
        "default_currency": _choice(doc.get("default_currency"), CURRENCIES, "usd"),
        "language": _choice(doc.get("language"), {"en", "my"}, "en"),
        # Legacy accounts predate verification: the code only blocked an explicit False.
        "is_verified": doc.get("is_verified") is not False,
        "verified_at": as_datetime(doc.get("verified_at")),
        "verified_via": _str_or_none(doc.get("verified_via")),
        "verification_token": _str_or_none(doc.get("verification_token")),
        "verification_token_expires_at": as_datetime(doc.get("verification_token_expires_at")),
        "password_reset_otp": _str_or_none(doc.get("password_reset_otp")),
        "password_reset_otp_expiry": as_datetime(doc.get("password_reset_otp_expiry")),
        "password_reset_attempts": _int_or(doc.get("password_reset_attempts"), None),
        "password_reset_attempts_since": as_datetime(doc.get("password_reset_attempts_since")),
        "password_reset_locked_until": as_datetime(doc.get("password_reset_locked_until")),
        "password_reset_token": _str_or_none(doc.get("password_reset_token")),
        "password_reset_token_expiry": as_datetime(doc.get("password_reset_token_expiry")),
        "fcm_token": _str_or_none(doc.get("fcm_token")),
        "ai_data_stale": bool(doc.get("ai_data_stale", False)),
        # Temporary cache columns: never carried over (recomputed on first read).
        "balances": None,
        "balances_version": None,
        "created_at": as_datetime(doc.get("created_at")) or MIGRATION_TIME,
    }


CONVERTERS = {"users": convert_user}
