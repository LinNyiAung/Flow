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


def compute(currency: str, shares: List[Mapping[str, Any]], members: List[Mapping[str, Any]]) -> Dict[str, Any]:
    """The breakdown from outflow_shares rows (id, amount, member_id; an entry's members in their listed order) and the
    family's members (join order)."""
    quantum = _quantum(currency)
    by_id = {m["id"]: m for m in members}
    entries: Dict[str, Dict[str, Any]] = {}
    for row in shares:
        entry = entries.setdefault(row["id"], {
            "amount": Decimal(str(row["amount"])).quantize(quantum, rounding=ROUND_HALF_UP), "for": []})
        if row["member_id"] is not None and row["member_id"] in by_id:
            entry["for"].append(row["member_id"])
        elif row["member_id"] is not None:
            entry.setdefault("unknown", True)  # not a member of this family (can't happen): left out entirely

    amounts: Dict[Optional[str], Decimal] = {}
    for entry in entries.values():
        if entry.get("unknown"):
            continue
        whom = entry["for"]
        if not whom:
            amounts[None] = amounts.get(None, Decimal(0)) + entry["amount"]
            continue
        share = (entry["amount"] / len(whom)).quantize(quantum, rounding=ROUND_FLOOR)
        for key in whom:
            amounts[key] = amounts.get(key, Decimal(0)) + share
        amounts[whom[0]] += entry["amount"] - share * len(whom)

    position = {m["id"]: i for i, m in enumerate(members)}
    keys = sorted(amounts, key=lambda k: (-amounts[k], -1 if k is None else position[k]))
    total = sum(amounts.values(), Decimal(0))

    rows = []
    for k in keys:
        member = by_id.get(k) or {}
        rows.append({"member_id": k,
                     "display_name": WHOLE_FAMILY if k is None else member["display_name"],
                     "status": "active" if k is None else member["status"],
                     "amount": float(amounts[k])})
    return {"currency": currency, "total_spent": float(total), "rows": rows}


async def family_breakdown(family: Mapping[str, Any], currency: str, date_from: datetime,
                           date_to: datetime) -> Dict[str, Any]:
    """GET /api/family/breakdown for `family`, entries dated within [date_from, date_to]."""
    book_id = await books_db.family_book_id(family["id"])
    shares = await fdb.outflow_shares(book_id, currency, date_from, date_to) if book_id else []
    return compute(currency, shares, await fdb.list_members(family["id"]))
