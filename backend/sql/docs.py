"""Convert between PostgreSQL rows and the document shapes the backend code uses.

The rest of the backend was written against MongoDB documents ("_id", a nested
"recurrence" dict, an embedded "category_budgets" list, ...). These helpers keep that
shape so business logic stays unchanged while storage moves to normalized tables.
Money comes back as float (what the code and API expect) and is written as exact
NUMERIC.
"""
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, Iterable, List, Optional

_CENT = Decimal("0.01")


def money(value: Any) -> Optional[Decimal]:
    """float/int/str -> Decimal rounded to cents (for NUMERIC(18,2) columns)."""
    if value is None:
        return None
    return Decimal(str(value)).quantize(_CENT, rounding=ROUND_HALF_UP)


def _plain(value: Any) -> Any:
    return float(value) if isinstance(value, Decimal) else value


def row_to_doc(row: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """Generic: id -> _id, Decimal -> float."""
    if row is None:
        return None
    doc = {("_id" if k == "id" else k): _plain(v) for k, v in row.items()}
    return doc


def rows_to_docs(rows: Iterable[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return [row_to_doc(r) for r in rows]


# ---------------------------------------------------------------- transactions
_RECURRENCE_COLUMNS = {
    "recurrence_enabled", "recurrence_frequency", "recurrence_day_of_week", "recurrence_day_of_month",
    "recurrence_month", "recurrence_day_of_year", "recurrence_end_date", "recurrence_last_created_date",
    "parent_transaction_id",
}


def transaction_doc(row: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    if row is None:
        return None
    doc = {("_id" if k == "id" else k): _plain(v) for k, v in row.items() if k not in _RECURRENCE_COLUMNS}
    frequency = row.get("recurrence_frequency")
    config = None
    if frequency:
        config = {
            "frequency": frequency,
            "day_of_week": row.get("recurrence_day_of_week"),
            "day_of_month": row.get("recurrence_day_of_month"),
            "month": row.get("recurrence_month"),
            "day_of_year": row.get("recurrence_day_of_year"),
            "end_date": row.get("recurrence_end_date"),
        }
    doc["recurrence"] = {
        "enabled": bool(row.get("recurrence_enabled")),
        "config": config,
        "last_created_date": row.get("recurrence_last_created_date"),
        "parent_transaction_id": row.get("parent_transaction_id"),
    }
    return doc


def recurrence_columns(recurrence: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """Flatten a recurrence dict into transaction columns (missing -> not recurring)."""
    recurrence = recurrence or {}
    config = recurrence.get("config") or {}
    return {
        "recurrence_enabled": bool(recurrence.get("enabled")) and bool(config.get("frequency")),
        "recurrence_frequency": config.get("frequency"),
        "recurrence_day_of_week": config.get("day_of_week"),
        "recurrence_day_of_month": config.get("day_of_month"),
        "recurrence_month": config.get("month"),
        "recurrence_day_of_year": config.get("day_of_year"),
        "recurrence_end_date": config.get("end_date"),
        "recurrence_last_created_date": recurrence.get("last_created_date"),
        "parent_transaction_id": recurrence.get("parent_transaction_id"),
    }


def transaction_row(doc: Dict[str, Any]) -> Dict[str, Any]:
    row = {("id" if k == "_id" else k): v for k, v in doc.items() if k != "recurrence"}
    row["amount"] = money(row.get("amount"))
    row.update(recurrence_columns(doc.get("recurrence")))
    return row


# ---------------------------------------------------------------- budgets
_BUDGET_MONEY = ("total_budget", "total_spent", "remaining_budget")


def budget_doc(row: Optional[Dict[str, Any]], allocations: Iterable[Dict[str, Any]] = ()) -> Optional[Dict[str, Any]]:
    if row is None:
        return None
    doc = row_to_doc(row)
    doc["category_budgets"] = [
        {
            "main_category": a["main_category"],
            "allocated_amount": _plain(a["allocated_amount"]),
            "spent_amount": _plain(a["spent_amount"]),
            "percentage_used": _plain(a["percentage_used"]),
            "is_exceeded": a["is_exceeded"],
        }
        for a in sorted(allocations, key=lambda a: a["position"])
    ]
    return doc


def budget_row(doc: Dict[str, Any]) -> Dict[str, Any]:
    row = {("id" if k == "_id" else k): v for k, v in doc.items() if k != "category_budgets"}
    for key in _BUDGET_MONEY:
        if key in row:
            row[key] = money(row[key])
    if row.get("percentage_used") is not None:
        row["percentage_used"] = Decimal(str(round(float(row["percentage_used"]), 2)))
    return row


def allocation_rows(budget_id: str, category_budgets: Iterable[Any]) -> List[Dict[str, Any]]:
    rows = []
    for position, cat in enumerate(category_budgets or []):
        cat = cat.model_dump() if hasattr(cat, "model_dump") else dict(cat)
        rows.append({
            "budget_id": budget_id,
            "position": position,
            "main_category": cat["main_category"],
            "allocated_amount": money(cat.get("allocated_amount") or 0),
            "spent_amount": money(cat.get("spent_amount") or 0),
            "percentage_used": Decimal(str(round(float(cat.get("percentage_used") or 0), 2))),
            "is_exceeded": bool(cat.get("is_exceeded")),
        })
    return rows


# ---------------------------------------------------------------- insights
_TOKEN_COLUMNS = ("input_tokens", "output_tokens", "total_tokens")


def insight_doc(row: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    if row is None:
        return None
    doc = {("_id" if k == "id" else k): _plain(v) for k, v in row.items() if k not in _TOKEN_COLUMNS}
    if any(row.get(k) is not None for k in _TOKEN_COLUMNS):
        doc["token_usage"] = {k: row.get(k) or 0 for k in _TOKEN_COLUMNS}
    return doc


def insight_row(doc: Dict[str, Any]) -> Dict[str, Any]:
    row = {("id" if k == "_id" else k): v for k, v in doc.items() if k not in ("token_usage", "is_reused")}
    usage = doc.get("token_usage") or {}
    for k in _TOKEN_COLUMNS:
        if k in usage:
            row[k] = usage[k]
    return row


# ---------------------------------------------------------------- notifications
# A notice's subject is one typed link (each a FK, SET NULL when the thing is deleted), chosen by its type. Types not
# listed link nothing (unusual_spending, payment_reminder, the subscription / plan types, broadcasts). The weekly /
# monthly insight notices link only their book (book_id). The books migration (d846defddc6e) holds a frozen copy.
NOTIFICATION_SUBJECT_LINKS = ("goal_id", "budget_id", "transaction_id", "custom_insight_id", "family_invite_id", "family_id")
NOTIFICATION_LINKS: Dict[str, str] = {
    **dict.fromkeys(("goal_progress", "goal_achieved", "goal_milestone", "goal_approaching_date"), "goal_id"),
    **dict.fromkeys(("budget_threshold", "budget_exceeded", "budget_ending_soon", "budget_now_active", "budget_started",
                     "budget_auto_created"), "budget_id"),
    **dict.fromkeys(("large_transaction", "recurring_transaction_created", "recurring_transaction_ended",
                     "recurring_transaction_disabled"), "transaction_id"),
    **dict.fromkeys(("custom_insight_ready", "custom_insight_failed"), "custom_insight_id"),
    "family_invite": "family_invite_id",
    **dict.fromkeys(("family_invite_accepted", "family_removed", "family_owner"), "family_id"),
    **dict.fromkeys(("weekly_insights_generated", "monthly_insights_generated"), "book_id"),
}


def notification_row(doc: Dict[str, Any], columns: Iterable[str]) -> Dict[str, Any]:
    """A notification doc -> a row of the given columns ("_id" -> "id"; unknown keys are dropped)."""
    columns = set(columns)
    row = {("id" if k == "_id" else k): v for k, v in doc.items() if ("id" if k == "_id" else k) in columns}
    # TEMPORARY until Task 5 (books plan): the notification writers still put every subject id (budget, transaction,
    # report, invite, family, family book) into the legacy `goal_id` key. Route it by type into its typed column so the
    # insert doesn't hit the goals FK. The legacy `book == 'family'` key is dropped above (no such column).
    legacy = row.pop("goal_id", None)
    if legacy is not None:
        link = NOTIFICATION_LINKS.get(doc.get("type"))
        if link and row.get(link) is None:
            row[link] = legacy
    return row


def notification_doc(row: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    doc = row_to_doc(row)
    if doc is not None and doc.get("goal_id") is None:
        # TEMPORARY until Task 5 (books plan): readers still expect the subject in `goal_id`, whatever its type.
        doc["goal_id"] = next((doc[c] for c in NOTIFICATION_SUBJECT_LINKS if doc.get(c) is not None), None)
    return doc


# ---------------------------------------------------------------- categories
def categories_docs(rows: Iterable[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    """Category rows -> {"inflow": {"_id": "inflow", "categories": [...]}, "outflow": {...}}."""
    grouped: Dict[str, Dict[str, Dict[str, Any]]] = {}
    for r in sorted(rows, key=lambda r: (r["type"], r["main_position"], r["sub_position"])):
        mains = grouped.setdefault(r["type"], {})
        entry = mains.setdefault(r["main_category"], {"main_category": r["main_category"], "sub_categories": []})
        entry["sub_categories"].append(r["sub_category"])
    return {t: {"_id": t, "categories": list(mains.values())} for t, mains in grouped.items()}


def category_rows(type_: str, categories: Iterable[Dict[str, Any]]) -> List[Dict[str, Any]]:
    rows = []
    for mi, cat in enumerate(categories):
        for si, sub in enumerate(cat["sub_categories"]):
            rows.append({"type": type_, "main_category": cat["main_category"], "sub_category": sub,
                         "main_position": mi, "sub_position": si})
    return rows
