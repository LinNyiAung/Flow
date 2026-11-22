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

from .breakdown import WHOLE_FAMILY, entry_shares, rows_of, total_by_person

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


def _sum_for(entries: Mapping[str, Mapping[str, Any]], member_id: Optional[str]) -> Decimal:
    return sum((e["split"][member_id] for e in entries.values() if member_id in e["split"]), Decimal(0))


async def person_month(family: Mapping[str, Any], person: Mapping[str, Any], currency: str, month: date,
                       member_id: Optional[str]) -> Optional[Dict[str, Any]]:
    """GET /api/family/spending/person: one person's month (member_id None: Whole family): their amount and previous
    month's, their share by main and sub category, the TREND_MONTHS months ending at `month`, their TOP_ENTRIES biggest
    entries by their share, and how many of the month's entries for them each member added. None when member_id is
    not a member (current or former) of this family."""
    first = _shift(month, -(TREND_MONTHS - 1))
    by_month, members = await _entries(family, person, currency, first, month)
    by_id = {m["id"]: m for m in members}
    if member_id is not None and member_id not in by_id:
        return None
    mine = {eid: e for eid, e in by_month.get(_key(month), {}).items() if member_id in e["split"]}

    mains: Dict[str, Dict[str, Any]] = {}
    for e in mine.values():
        share, row = e["split"][member_id], e["row"]
        main = mains.setdefault(row["main_category"], {"amount": Decimal(0), "subs": {}})
        main["amount"] += share
        main["subs"][row["sub_category"]] = main["subs"].get(row["sub_category"], Decimal(0)) + share
    categories = [{"main_category": name, "amount": float(v["amount"]),
                   "sub_categories": [{"sub_category": s, "amount": float(a)}
                                      for s, a in sorted(v["subs"].items(), key=lambda kv: (-kv[1], kv[0]))]}
                  for name, v in sorted(mains.items(), key=lambda kv: (-kv[1]["amount"], kv[0]))]

    trend = [{"month": _label(m), "amount": float(_sum_for(by_month.get(_key(m), {}), member_id))}
             for m in (_shift(first, i) for i in range(TREND_MONTHS))]

    # Biggest share first, then the latest, then by id (stable sorts, last key first).
    ordered = sorted(mine.items(), key=lambda kv: kv[0])
    ordered.sort(key=lambda kv: kv[1]["row"]["date"], reverse=True)
    ordered.sort(key=lambda kv: kv[1]["split"][member_id], reverse=True)
    top = [{"id": eid, "date": e["row"]["date"].date().isoformat(), "main_category": e["row"]["main_category"],
            "sub_category": e["row"]["sub_category"], "description": e["row"]["description"],
            "amount": float(e["amount"]), "share": float(e["split"][member_id]), "split_between": len(e["for"])}
           for eid, e in ordered[:TOP_ENTRIES]]

    position = {m["id"]: i for i, m in enumerate(members)}
    counts: Dict[str, int] = {}
    for e in mine.values():
        adder = e["row"]["added_by_member_id"]
        if adder in by_id:
            counts[adder] = counts.get(adder, 0) + 1
    added_by = [{"member_id": mid, "display_name": by_id[mid]["display_name"], "count": n}
                for mid, n in sorted(counts.items(), key=lambda kv: (-kv[1], position[kv[0]]))]

    member = by_id.get(member_id) or {}
    return {"currency": currency, "month": _label(month), "member_id": member_id,
            "display_name": WHOLE_FAMILY if member_id is None else member["display_name"],
            "status": "active" if member_id is None else member["status"],
            "amount": float(_sum_for(mine, member_id)),
            "previous_amount": float(_sum_for(by_month.get(_key(_shift(month, -1)), {}), member_id)),
            "categories": categories, "trend": trend, "top_entries": top, "added_by": added_by}
