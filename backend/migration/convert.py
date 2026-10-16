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
from decimal import ROUND_HALF_UP, Decimal
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


def quarantine_row(source: str, doc: Dict[str, Any], reason: str) -> Dict[str, Any]:
    """Row for quarantined_records: the untouched original plus why it was set aside."""
    return {
        "source": source,
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
    # Half-up on the decimal value, like the app's sql.docs.money (round(10.005, 2) gives 10.0).
    return float(Decimal(str(number)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


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


def _finite(value: Any, default: float = 0.0) -> float:
    number = finite_amount(value)
    return default if number is None else number


def _total_excluding_subcategories(allocations) -> float:
    """budget_service.calculate_total_budget_excluding_subcategories (legacy budgets without a
    total): "Main - Sub" allocations count only when "Main" itself is not budgeted."""
    mains = {a["main_category"] for a in allocations if " - " not in a["main_category"]}
    total = 0.0
    for a in allocations:
        name = a["main_category"]
        if " - " not in name or name.split(" - ", 1)[0] not in mains:
            total += a["allocated_amount"]
    return round(total, 2)


def convert_budget(doc: Dict[str, Any]) -> Dict[str, Any]:
    """-> {"budget": row, "allocations": [rows]}. Allocation numbers the old code could not
    show (NaN/inf/negative) become 0 (the API showed them as 0 and the next recompute
    rewrites spend anyway); entries without a category name are dropped."""
    if not doc.get("_id") or not doc.get("user_id"):
        raise Quarantine("budget without id or user")
    start, end = as_datetime(doc.get("start_date")), as_datetime(doc.get("end_date"))
    if start is None or end is None:
        raise Quarantine("budget without readable start/end dates")
    if end < start:
        raise Quarantine("budget ends before it starts")
    currency = doc.get("currency") or "usd"
    if currency not in CURRENCIES:
        raise Quarantine(f"unknown currency {doc.get('currency')!r}")
    budget_id = str(doc["_id"])
    allocations = []
    for cat in doc.get("category_budgets") or []:
        if not isinstance(cat, dict) or not isinstance(cat.get("main_category"), str) or not cat["main_category"]:
            continue
        pct = _finite(cat.get("percentage_used"))
        allocations.append({
            "budget_id": budget_id,
            "position": len(allocations),
            "main_category": cat["main_category"],
            "allocated_amount": max(_finite(cat.get("allocated_amount")), 0.0),
            "spent_amount": _finite(cat.get("spent_amount")),
            "percentage_used": pct if abs(pct) < 1e7 else 0.0,
            "is_exceeded": bool(cat.get("is_exceeded", False)),
        })
    total = finite_amount(doc.get("total_budget"))
    if total is None or total < 0:
        total = _total_excluding_subcategories(allocations)  # the code's fallback for a missing total
    spent = _finite(doc.get("total_spent"))
    remaining = finite_amount(doc.get("remaining_budget"))
    pct = _finite(doc.get("percentage_used"))
    created = as_datetime(doc.get("created_at")) or MIGRATION_TIME
    name = doc.get("name")
    return {
        "budget": {
            "id": budget_id,
            "user_id": str(doc["user_id"]),
            "name": name if isinstance(name, str) and name.strip() else "Budget",
            "description": doc.get("description") if isinstance(doc.get("description"), str) else None,
            "period": _choice(doc.get("period"), {"weekly", "monthly", "yearly", "custom"}, "custom"),
            "currency": currency,
            "start_date": start,
            "end_date": end,
            "total_budget": total,
            "total_spent": spent,
            "remaining_budget": round(total - spent, 2) if remaining is None else remaining,
            "percentage_used": pct if abs(pct) < 1e7 else 0.0,
            # Stored status is refreshed from the dates on first read when stale.
            "status": _choice(doc.get("status"), {"upcoming", "active", "completed", "exceeded"}, "active"),
            "is_active": bool(doc.get("is_active", False)),
            "auto_create_enabled": bool(doc.get("auto_create_enabled", False)),
            "auto_create_with_ai": bool(doc.get("auto_create_with_ai", False)),
            "parent_budget_id": str(doc["parent_budget_id"]) if doc.get("parent_budget_id") else None,
            "rolled_over_to": str(doc["rolled_over_to"]) if doc.get("rolled_over_to") else None,
            "auto_create_claimed_at": as_datetime(doc.get("auto_create_claimed_at")),
            # Missing flags meant "not yet" to the code ({"$ne": True}).
            "started_notified": doc.get("started_notified") is True,
            "started_notified_at": as_datetime(doc.get("started_notified_at")),
            "ending_soon_notified": doc.get("ending_soon_notified") is True,
            "ending_soon_notified_at": as_datetime(doc.get("ending_soon_notified_at")),
            "created_at": created,
            "updated_at": as_datetime(doc.get("updated_at")) or created,
        },
        "allocations": allocations,
    }


ADMIN_ROLES = {"super_admin", "admin", "moderator"}


def convert_admin(doc: Dict[str, Any]) -> Dict[str, Any]:
    email = doc.get("email")
    if not doc.get("_id") or not isinstance(email, str) or not email.strip():
        raise Quarantine("admin without id or e-mail")
    if not doc.get("password"):
        raise Quarantine("admin without password hash")
    if doc.get("role") not in ADMIN_ROLES:
        # Never grant more than the code would have: an unknown role passed no role check.
        raise Quarantine(f"unknown admin role {doc.get('role')!r}")
    return {
        "id": str(doc["_id"]),
        "name": doc.get("name") if isinstance(doc.get("name"), str) and doc["name"].strip() else email.split("@")[0],
        "email": email.strip().lower(),
        "password": doc["password"],
        "role": doc["role"],
        "password_version": _int_or(doc.get("password_version"), 0) or 0,
        "password_changed_at": as_datetime(doc.get("password_changed_at")),
        "last_login": as_datetime(doc.get("last_login")),
        "created_at": as_datetime(doc.get("created_at")) or MIGRATION_TIME,
    }


def convert_admin_action_log(doc: Dict[str, Any]) -> Dict[str, Any]:
    if not doc.get("_id"):
        raise Quarantine("admin log entry without id")
    details = doc.get("details")
    if details is not None and not isinstance(details, str):
        import json
        details = json.dumps(json_safe(details), ensure_ascii=False)
    return {
        "id": str(doc["_id"]),
        "admin_id": str(doc.get("admin_id") or "unknown"),
        "admin_email": str(doc.get("admin_email") or "unknown"),
        "action": str(doc.get("action") or "unknown"),
        "target_user_id": str(doc["target_user_id"]) if doc.get("target_user_id") else None,
        "target_user_email": _str_or_none(doc.get("target_user_email")),
        "details": details,
        "timestamp": as_datetime(doc.get("timestamp")) or as_datetime(doc.get("created_at")) or MIGRATION_TIME,
    }


def convert_app_version(doc: Dict[str, Any]) -> Dict[str, Any]:
    if not doc.get("_id") or not isinstance(doc.get("version"), str) or not doc["version"].strip():
        raise Quarantine("app version without id or version")
    if doc.get("platform") not in ("android", "ios", "all"):
        raise Quarantine(f"unknown platform {doc.get('platform')!r}")
    return {
        "id": str(doc["_id"]),
        "version": doc["version"].strip(),
        "platform": doc["platform"],
        "download_url": doc.get("download_url") if isinstance(doc.get("download_url"), str) else "",
        "release_notes": _str_or_none(doc.get("release_notes")),
        "is_force_update": bool(doc.get("is_force_update", False)),
        "min_supported_version": _str_or_none(doc.get("min_supported_version")),
        "is_active": bool(doc.get("is_active", True)),
        "created_by_email": _str_or_none(doc.get("created_by_email")),
        "created_at": as_datetime(doc.get("created_at")) or MIGRATION_TIME,
        "updated_at": as_datetime(doc.get("updated_at")),
    }


def convert_categories(doc: Dict[str, Any]) -> list:
    """{"_id": "inflow"|"outflow", "categories": [{"main_category", "sub_categories"}]} -> category rows
    (configured order kept; duplicates and blank names dropped)."""
    if doc.get("_id") not in ("inflow", "outflow"):
        raise Quarantine(f"unknown category type {doc.get('_id')!r}")
    rows, seen, mains = [], set(), 0
    for cat in doc.get("categories") or []:
        main = cat.get("main_category") if isinstance(cat, dict) else None
        if not isinstance(main, str) or not main.strip():
            continue
        subs = [s for s in (cat.get("sub_categories") or []) if isinstance(s, str) and s.strip()]
        added = 0
        for sub in subs:
            if (main, sub) not in seen:
                seen.add((main, sub))
                rows.append({"type": doc["_id"], "main_category": main, "sub_category": sub,
                             "main_position": mains, "sub_position": added})
                added += 1
        if added:
            mains += 1
    return rows


# Single-row converters (collection -> one table). Multi-table ones are listed separately.
CONVERTERS = {"users": convert_user, "feedback": convert_feedback, "ai_usage": convert_ai_usage,
              "notification_preferences": convert_notification_preferences, "notifications": convert_notification,
              "insights": convert_insight, "goals": convert_goal,
              "transactions": convert_transaction, "admins": convert_admin,
              "admin_action_logs": convert_admin_action_log, "app_versions": convert_app_version}
MULTI_CONVERTERS = {"chat_sessions": convert_chat_session, "budgets": convert_budget}
