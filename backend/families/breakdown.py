"""The per-person breakdown of a family book's spending (spec: docs/superpowers/specs/2026-11-13-family-book-design.md,
"Who added it" and "Whole family has its own row").

Spending is counted by who it was for, never by who added it:
- only outflows, and never a transfer leg (transfer_id set);
- an entry for n members adds amount / n to each of them;
- an entry for nobody in particular counts on its own "Whole family" row (member_id None), never divided;
- members who left, and removed placeholders, keep their rows (status "former").

Rounding (ruling R11) is per entry, at the currency's display precision (MMK whole kyat, others cents): the entry's
amount is taken at that precision, each of its n members gets floor(amount / n), and the entry's leftover
(amount - n * share) goes to its first listed member (the order outflow_shares gives: the family's join order). So no
row is ever negative, and the rows sum exactly to total_spent (the sum of the entries' amounts).
Rows are sorted by amount, largest first; ties keep the family's join order, with Whole family first.
"""
from datetime import datetime
from decimal import ROUND_FLOOR, ROUND_HALF_UP, Decimal
from typing import Any, Dict, List, Mapping, Optional

from sql import books as books_db
from sql import families as fdb

WHOLE_FAMILY = "Whole family"
_DECIMAL_PLACES = {"mmk": 0}  # every other currency: cents


def _quantum(currency: str) -> Decimal:
    return Decimal(1).scaleb(-_DECIMAL_PLACES.get(currency, 2))


def entry_shares(currency: str, shares: List[Mapping[str, Any]],
                 members: List[Mapping[str, Any]]) -> Dict[str, Dict[str, Any]]:
    """Each entry's split, by entry id, from outflow_shares rows (an entry's members in their listed order) and the
    family's members (join order): {"row": the entry's first row (its other columns), "amount": Decimal at the
    currency's precision, "for": [member ids], "split": {member id, or None for Whole family: Decimal}}. An entry
    tagged with someone outside the family (can't happen) is left out entirely."""
    quantum = _quantum(currency)
    by_id = {m["id"]: m for m in members}
    entries: Dict[str, Dict[str, Any]] = {}
    unknown = set()
    for row in shares:
        entry = entries.setdefault(row["id"], {
            "row": row, "amount": Decimal(str(row["amount"])).quantize(quantum, rounding=ROUND_HALF_UP), "for": []})
        if row["member_id"] is not None and row["member_id"] in by_id:
            entry["for"].append(row["member_id"])
        elif row["member_id"] is not None:
            unknown.add(row["id"])

    out: Dict[str, Dict[str, Any]] = {}
    for entry_id, entry in entries.items():
        if entry_id in unknown:
            continue
        whom = entry["for"]
        if not whom:
            entry["split"] = {None: entry["amount"]}
        else:
            share = (entry["amount"] / len(whom)).quantize(quantum, rounding=ROUND_FLOOR)
            entry["split"] = {key: share for key in whom}
            entry["split"][whom[0]] += entry["amount"] - share * len(whom)
        out[entry_id] = entry
    return out


def rows_of(amounts: Mapping[Optional[str], Decimal], members: List[Mapping[str, Any]]) -> List[Dict[str, Any]]:
    """Breakdown rows from per-person totals (None: Whole family): largest first; ties in the family's join order, with
    Whole family first."""
    by_id = {m["id"]: m for m in members}
    position = {m["id"]: i for i, m in enumerate(members)}
    keys = sorted(amounts, key=lambda k: (-amounts[k], -1 if k is None else position[k]))
    rows = []
    for k in keys:
        member = by_id.get(k) or {}
        rows.append({"member_id": k,
                     "display_name": WHOLE_FAMILY if k is None else member["display_name"],
                     "status": "active" if k is None else member["status"],
                     "amount": float(amounts[k])})
    return rows


def total_by_person(entries: Mapping[str, Mapping[str, Any]]) -> Dict[Optional[str], Decimal]:
    """Per-person totals (None: Whole family) of entry_shares entries."""
    amounts: Dict[Optional[str], Decimal] = {}
    for entry in entries.values():
        for key, share in entry["split"].items():
            amounts[key] = amounts.get(key, Decimal(0)) + share
    return amounts


def compute(currency: str, shares: List[Mapping[str, Any]], members: List[Mapping[str, Any]]) -> Dict[str, Any]:
    """The breakdown from outflow_shares rows (id, amount, member_id; an entry's members in their listed order) and the
    family's members (join order)."""
    amounts = total_by_person(entry_shares(currency, shares, members))
    total = sum(amounts.values(), Decimal(0))
    return {"currency": currency, "total_spent": float(total), "rows": rows_of(amounts, members)}


async def family_breakdown(family: Mapping[str, Any], currency: str, date_from: datetime,
                           date_to: datetime) -> Dict[str, Any]:
    """GET /api/family/breakdown for `family`, entries dated within [date_from, date_to]."""
    book_id = await books_db.family_book_id(family["id"])
    shares = await fdb.outflow_shares(book_id, currency, date_from, date_to) if book_id else []
    return compute(currency, shares, await fdb.list_members(family["id"]))
