"""The Family spending screen (spec: docs/superpowers/specs/2026-11-21-family-spending-design.md): a family book's
spending per person it was for, one calendar month at a time, and one person's month in depth.

The split is the breakdown's own (families.breakdown.entry_shares), so a person's month here always equals their row in
GET /api/family/breakdown for that month. A month is the calendar month of the entry's own (wall-clock) date. Only the
family book is read.
"""
import re
from datetime import date, timedelta
from decimal import Decimal
from typing import Any, Dict, List, Mapping, Optional, Tuple

from report_models import ReportPeriod
from report_routes import calculate_report_dates
from sql import books as books_db
from sql import families as fdb
from user_zones import user_zone

from .breakdown import entry_shares, rows_of, total_by_person

_MONTH = re.compile(r"(\d{4})-(\d{2})")
TREND_MONTHS = 6
TOP_ENTRIES = 5

Month = Tuple[int, int]


def parse_month(value: str) -> date:
    """The 1st of a `YYYY-MM` month; ValueError for anything else."""
    m = _MONTH.fullmatch(value or "")
    if not m or not 1 <= int(m.group(2)) <= 12:
        raise ValueError("month must be YYYY-MM")
    return date(int(m.group(1)), int(m.group(2)), 1)


def _shift(month: date, months: int) -> date:
    index = month.year * 12 + month.month - 1 + months
    return date(index // 12, index % 12 + 1, 1)


def _last_day(month: date) -> date:
    return _shift(month, 1) - timedelta(days=1)


def _label(month: date) -> str:
    return f"{month.year:04d}-{month.month:02d}"


def _key(value) -> Month:
    return value.year, value.month


async def _entries(family: Mapping[str, Any], person: Mapping[str, Any], currency: str, first: date,
                   last: date) -> Tuple[Dict[Month, Dict[str, Dict[str, Any]]], List[Mapping[str, Any]]]:
    """The family book's split entries in `currency` from the 1st of month `first` to the end of month `last`, grouped
    by the calendar month of their date, and the family's members (join order)."""
    members = await fdb.list_members(family["id"])
    book_id = await books_db.family_book_id(family["id"])
    if not book_id:
        return {}, members
    date_from, date_to = calculate_report_dates(ReportPeriod.CUSTOM, first, _last_day(last), user_zone(person))
    shares = await fdb.outflow_shares(book_id, currency, date_from, date_to)
    by_month: Dict[Month, Dict[str, Dict[str, Any]]] = {}
    for entry_id, entry in entry_shares(currency, shares, members).items():
        by_month.setdefault(_key(entry["row"]["date"]), {})[entry_id] = entry
    return by_month, members


async def month_overview(family: Mapping[str, Any], person: Mapping[str, Any], currency: str,
                         month: date) -> Dict[str, Any]:
    """GET /api/family/spending: the month's rows (as the breakdown gives them) with each person's previous-month
    amount, the totals, the currencies the family book has spending in and the first month with spending in
    `currency`."""
    previous = _shift(month, -1)
    by_month, members = await _entries(family, person, currency, previous, month)
    now = total_by_person(by_month.get(_key(month), {}))
    before = total_by_person(by_month.get(_key(previous), {}))
    rows = rows_of(now, members)
    for row in rows:
        row["previous_amount"] = float(before.get(row["member_id"], Decimal(0)))
    book_id = await books_db.family_book_id(family["id"])
    firsts = await fdb.spending_firsts(book_id) if book_id else {}
    first = firsts.get(currency)
    return {"currency": currency, "month": _label(month),
            "total": float(sum(now.values(), Decimal(0))), "previous_total": float(sum(before.values(), Decimal(0))),
            "rows": rows, "currencies": sorted(firsts), "first_month": _label(first) if first else None}
