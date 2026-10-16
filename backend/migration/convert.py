"""MongoDB document -> PostgreSQL row conversion, one function per table.

Used by the one-time data migration (and by the E2E harness for direct test inserts), so
every rule here is applied to real production data. Each converter accepts any shape the
old code ever wrote (missing fields, legacy defaults, strings for dates, ...) and returns
a row that satisfies the PostgreSQL schema, applying the SAME defaults the application
code used when it read those documents. Rows that can't be made valid raise
`Quarantine(reason)` so the migration can set them aside instead of dropping them.
"""
import uuid
from datetime import datetime, UTC
from typing import Any, Dict, Optional

MIGRATION_TIME = datetime.now(UTC)
CURRENCIES = {"usd", "mmk", "thb"}


class Quarantine(Exception):
    """The document can't be stored as a valid row; carries the reason."""


def json_safe(value: Any) -> Any:
    """A Mongo document as JSON for the audit copy: dates as ISO text, NaN/inf as text."""
    if isinstance(value, dict):
        return {str(k): json_safe(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_safe(v) for v in value]
    if isinstance(value, float) and (value != value or value in (float("inf"), float("-inf"))):
        return repr(value)
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, datetime):
        return value.isoformat()
    return str(value)


def quarantine_row(doc: Dict[str, Any], reason: str) -> Dict[str, Any]:
    """Row for quarantined_transactions: the untouched original plus why it was set aside."""
    return {
        "id": str(doc.get("_id") or uuid.uuid4()),
        "user_id": str(doc["user_id"]) if doc.get("user_id") else None,
        "reason": reason,
        "original": json_safe(doc),
    }


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
        "created_at": as_datetime(doc.get("created_at")) or MIGRATION_TIME,
    }


def convert_feedback(doc: Dict[str, Any]) -> Dict[str, Any]:
    if not doc.get("_id") or not doc.get("user_id"):
        raise Quarantine("feedback without id or user")
    rating = _int_or(doc.get("rating"), None)
    return {
        "id": str(doc["_id"]),
        "user_id": str(doc["user_id"]),
        "user_email": _str_or_none(doc.get("user_email")),
        "user_name": _str_or_none(doc.get("user_name")),
        "category": _choice(doc.get("category"), {"bug", "feature_request", "general", "usability"}, "general"),
        "message": doc.get("message") if isinstance(doc.get("message"), str) else "",
        "rating": rating if rating is not None and 1 <= rating <= 5 else None,
        "screenshot_url": _str_or_none(doc.get("screenshot_url")),
        # Feedback without a status was always shown and counted as pending.
        "status": _choice(doc.get("status"), {"pending", "reviewed", "resolved"}, "pending"),
        "created_at": as_datetime(doc.get("created_at")) or MIGRATION_TIME,
    }


def convert_ai_usage(doc: Dict[str, Any]) -> Dict[str, Any]:
    if not doc.get("_id") or not doc.get("user_id"):
        raise Quarantine("ai usage without id or user")
    input_tokens = max(_int_or(doc.get("input_tokens"), 0) or 0, 0)
    output_tokens = max(_int_or(doc.get("output_tokens"), 0) or 0, 0)
    cost = doc.get("estimated_cost_usd")
    try:
        cost = float(cost) if cost is not None else 0.0
    except (TypeError, ValueError):
        cost = 0.0
    if not (0 <= cost < 1e6):  # NaN / negative / absurd -> 0 (it is an estimate)
        cost = 0.0
    return {
        "id": str(doc["_id"]),
        "user_id": str(doc["user_id"]),
        "feature_type": str(doc.get("feature_type") or "chat"),
        "provider": str(doc.get("provider") or "openai"),
        "model_name": str(doc.get("model_name") or "unknown"),
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "total_tokens": max(_int_or(doc.get("total_tokens"), 0) or 0, 0) or input_tokens + output_tokens,
        "estimated_cost_usd": round(cost, 6),
        "created_at": as_datetime(doc.get("created_at")) or MIGRATION_TIME,
    }


def convert_notification_preferences(doc: Dict[str, Any]) -> Dict[str, Any]:
    if not doc.get("user_id"):
        raise Quarantine("notification preferences without user")
    prefs = doc.get("preferences") if isinstance(doc.get("preferences"), dict) else {}
    created = as_datetime(doc.get("created_at"))
    updated = as_datetime(doc.get("updated_at")) or created or MIGRATION_TIME
    return {
        "user_id": str(doc["user_id"]),
        # Only boolean entries are meaningful (the code treats missing keys as enabled).
        "preferences": {str(k): bool(v) for k, v in prefs.items() if isinstance(v, bool)},
        "created_at": created or updated,
        "updated_at": updated,
    }


def convert_notification(doc: Dict[str, Any]) -> Dict[str, Any]:
    if not doc.get("_id") or not doc.get("user_id"):
        raise Quarantine("notification without id or user")
    target = doc.get("reminder_target_date")
    try:
        from datetime import date
        target = date.fromisoformat(target) if isinstance(target, str) else None
    except ValueError:
        target = None
    return {
        "id": str(doc["_id"]),
        "user_id": str(doc["user_id"]),
        # Unknown legacy types are kept as-is (the API maps them to system_broadcast).
        "type": str(doc.get("type") or "system_broadcast"),
        "title": doc.get("title") if isinstance(doc.get("title"), str) else "",
        "message": doc.get("message") if isinstance(doc.get("message"), str) else "",
        "goal_id": _str_or_none(doc.get("goal_id")),
        "goal_name": _str_or_none(doc.get("goal_name")),
        "currency": _str_or_none(doc.get("currency")),
        "is_read": bool(doc.get("is_read", False)),
        "reminder_threshold": _int_or(doc.get("reminder_threshold"), None),
        "reminder_target_date": target,
        "created_at": as_datetime(doc.get("created_at")) or MIGRATION_TIME,
    }


def _is_placeholder_text(text: str) -> bool:
    """Same rule as insights_service._is_placeholder_text (legacy insights had no flag)."""
    text = text or ""
    return "Get Started with Your Financial Journey" in text and (
        "Welcome to Toe Pwar!" in text or "Welcome to Tow Pwar!" in text)


def convert_insight(doc: Dict[str, Any]) -> Dict[str, Any]:
    if not doc.get("_id") or not doc.get("user_id"):
        raise Quarantine("insight without id or user")
    content = doc.get("content")
    if not isinstance(content, str) or not content.strip():
        # The code treated these as missing everywhere (never shown, never translated).
        raise Quarantine("insight without content")
    usage = doc.get("token_usage") if isinstance(doc.get("token_usage"), dict) else {}
    flag = doc.get("is_placeholder")
    return {
        "id": str(doc["_id"]),
        "user_id": str(doc["user_id"]),
        "insight_type": _choice(doc.get("insight_type"), {"weekly", "monthly"}, "weekly"),
        "ai_provider": _choice(doc.get("ai_provider"), {"openai", "gemini"}, "openai"),
        "content": content,
        "content_mm": doc.get("content_mm") if isinstance(doc.get("content_mm"), str) and doc["content_mm"].strip() else None,
        "is_placeholder": flag if isinstance(flag, bool) else _is_placeholder_text(content),
        "is_period_to_date": doc.get("is_period_to_date") if isinstance(doc.get("is_period_to_date"), bool) else None,
        "week_start": as_datetime(doc.get("week_start")),
        "week_end": as_datetime(doc.get("week_end")),
        "month_start": as_datetime(doc.get("month_start")),
        "month_end": as_datetime(doc.get("month_end")),
        "input_tokens": _int_or(usage.get("input_tokens"), None),
        "output_tokens": _int_or(usage.get("output_tokens"), None),
        "total_tokens": _int_or(usage.get("total_tokens"), None),
        "expires_at": as_datetime(doc.get("expires_at")),
        "generated_at": as_datetime(doc.get("generated_at")) or as_datetime(doc.get("created_at")) or MIGRATION_TIME,
    }


def convert_chat_session(doc: Dict[str, Any]) -> Dict[str, Any]:
    """-> {"session": row, "messages": [rows]} (messages keep their order; bad entries dropped)."""
    if not doc.get("_id") or not doc.get("user_id"):
        raise Quarantine("chat session without id or user")
    created = as_datetime(doc.get("created_at"))
    updated = as_datetime(doc.get("updated_at")) or created or MIGRATION_TIME
    messages = []
    for msg in doc.get("messages") or []:
        if isinstance(msg, dict) and msg.get("role") in ("user", "assistant") and isinstance(msg.get("content"), str):
            messages.append({"session_id": str(doc["_id"]), "role": msg["role"], "content": msg["content"],
                             "timestamp": as_datetime(msg.get("timestamp"))})
    return {"session": {"id": str(doc["_id"]), "user_id": str(doc["user_id"]),
                        "created_at": created or updated, "updated_at": updated},
            "messages": messages}


def finite_amount(value: Any) -> Optional[float]:
    """float of a finite number within NUMERIC(18,2) range, else None (NaN, inf, strings, ...)."""
    if isinstance(value, bool):
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if number != number or abs(number) >= 1e16:
        return None
    return round(number, 2)


def convert_goal(doc: Dict[str, Any]) -> Dict[str, Any]:
    if not doc.get("_id") or not doc.get("user_id"):
        raise Quarantine("goal without id or user")
    target = finite_amount(doc.get("target_amount"))
    if target is None or target <= 0:
        raise Quarantine(f"goal target amount not a positive number: {doc.get('target_amount')!r}")
    current = finite_amount(doc.get("current_amount", 0))
    if current is None or current < 0:
        raise Quarantine(f"goal saved amount not a non-negative number: {doc.get('current_amount')!r}")
    created = as_datetime(doc.get("created_at")) or MIGRATION_TIME
    status = _choice(doc.get("status"), {"active", "achieved"}, "achieved" if current >= target else "active")
    return {
        "id": str(doc["_id"]),
        "user_id": str(doc["user_id"]),
        "name": doc.get("name") if isinstance(doc.get("name"), str) and doc["name"].strip() else "Goal",
        "goal_type": _choice(doc.get("goal_type"), {"savings", "debt_reduction", "large_purchase"}, "savings"),
        "status": status,
        "target_amount": target,
        "current_amount": current,
        "currency": _choice(doc.get("currency"), CURRENCIES, "usd"),
        "target_date": as_datetime(doc.get("target_date")),
        "achieved_at": as_datetime(doc.get("achieved_at")),
        "created_at": created,
        "updated_at": as_datetime(doc.get("updated_at")) or created,  # the code fell back to created_at
    }


_FREQUENCIES = {"daily", "weekly", "monthly", "annually"}


def _recurrence(doc: Dict[str, Any]) -> Dict[str, Any]:
    """Nested recurrence -> columns. A config without a known frequency was never run by the
    job (it failed validation), so it is stored as "not recurring"; parent links are kept."""
    rec = doc.get("recurrence") if isinstance(doc.get("recurrence"), dict) else {}
    config = rec.get("config") if isinstance(rec.get("config"), dict) else {}
    frequency = config.get("frequency") if config.get("frequency") in _FREQUENCIES else None
    parent = rec.get("parent_transaction_id")
    return {
        "recurrence_enabled": bool(rec.get("enabled")) and frequency is not None,
        "recurrence_frequency": frequency,
        "recurrence_day_of_week": _int_or(config.get("day_of_week"), None) if frequency else None,
        "recurrence_day_of_month": _int_or(config.get("day_of_month"), None) if frequency else None,
        "recurrence_month": _int_or(config.get("month"), None) if frequency else None,
        "recurrence_day_of_year": _int_or(config.get("day_of_year"), None) if frequency else None,
        "recurrence_end_date": as_datetime(config.get("end_date")) if frequency else None,
        "recurrence_last_created_date": as_datetime(rec.get("last_created_date")),
        "parent_transaction_id": str(parent) if parent else None,
    }


def convert_transaction(doc: Dict[str, Any]) -> Dict[str, Any]:
    """Rows the old code could not show (no amount / NaN / unknown type ...) are quarantined.
    A dangling parent_transaction_id is cleared by the migration script (it needs the full id set)."""
    if not doc.get("_id") or not doc.get("user_id"):
        raise Quarantine("transaction without id or user")
    amount = finite_amount(doc.get("amount"))
    if amount is None or amount <= 0:
        raise Quarantine(f"amount not a positive finite number: {doc.get('amount')!r}")
    if doc.get("type") not in ("inflow", "outflow"):
        raise Quarantine(f"unknown type {doc.get('type')!r}")
    for field in ("main_category", "sub_category"):
        if not isinstance(doc.get(field), str):
            raise Quarantine(f"{field} missing")
    currency = doc.get("currency") or "usd"  # the code read a missing currency as usd
    if currency not in CURRENCIES:
        raise Quarantine(f"unknown currency {doc.get('currency')!r}")
    date = as_datetime(doc.get("date"))
    if date is None:
        raise Quarantine(f"date missing or unreadable: {doc.get('date')!r}")
    created = as_datetime(doc.get("created_at")) or MIGRATION_TIME
    return {
        "id": str(doc["_id"]),
        "user_id": str(doc["user_id"]),
        "type": doc["type"],
        "main_category": doc["main_category"],
        "sub_category": doc["sub_category"],
        "amount": amount,
        "currency": currency,
        "date": date,
        "description": doc.get("description") if isinstance(doc.get("description"), str) else None,
        **_recurrence(doc),
        "created_at": created,
        "updated_at": as_datetime(doc.get("updated_at")) or created,  # the code fell back to created_at
    }


# Single-row converters (collection -> one table). Multi-table ones are listed separately.
CONVERTERS = {"users": convert_user, "feedback": convert_feedback, "ai_usage": convert_ai_usage,
              "notification_preferences": convert_notification_preferences, "notifications": convert_notification,
              "insights": convert_insight, "goals": convert_goal,
              "transactions": convert_transaction}
MULTI_CONVERTERS = {"chat_sessions": convert_chat_session}
