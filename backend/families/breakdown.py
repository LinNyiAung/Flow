"""The per-person breakdown of a family book's spending (spec: docs/superpowers/specs/2026-11-13-family-book-design.md,
"Who added it" and "Whole family has its own row").

Spending is counted by who it was for, never by who added it:
- only outflows, and never a transfer leg (transfer_id set);
- an entry for n members adds amount / n to each of them;
- an entry for nobody in particular counts on its own "Whole family" row (member_id None), never divided;
- members who left, and removed placeholders, keep their rows (status "former").

Shares are summed exactly and rounded once per row to the currency's display precision (MMK whole kyat, others cents).
The rounding remainder goes to the first member row (the largest), so the rows always add up to total_spent.
Rows are sorted by amount, largest first; ties keep the family's join order, with Whole family first.
"""
from datetime import datetime
from decimal import ROUND_HALF_UP, Decimal
from fractions import Fraction
from typing import Any, Dict, List, Mapping, Optional

from sql import families as fdb

WHOLE_FAMILY = "Whole family"
_DECIMAL_PLACES = {"mmk": 0}  # every other currency: cents


def _quantum(currency: str) -> Decimal:
    return Decimal(1).scaleb(-_DECIMAL_PLACES.get(currency, 2))


def _rounded(value: Fraction, quantum: Decimal) -> Decimal:
    return (Decimal(value.numerator) / Decimal(value.denominator)).quantize(quantum, rounding=ROUND_HALF_UP)


def compute(currency: str, shares: List[Mapping[str, Any]], members: List[Mapping[str, Any]]) -> Dict[str, Any]:
    """The breakdown from outflow_shares rows (id, amount, member_id) and the family's members (join order)."""
    entries: Dict[str, Dict[str, Any]] = {}
    for row in shares:
        entry = entries.setdefault(row["id"], {"amount": Fraction(Decimal(str(row["amount"]))), "for": []})
        if row["member_id"] is not None:
            entry["for"].append(row["member_id"])

    exact: Dict[Optional[str], Fraction] = {}
    for entry in entries.values():
        whom = entry["for"] or [None]
        share = entry["amount"] / len(whom)
        for key in whom:
            exact[key] = exact.get(key, Fraction(0)) + share

    by_id = {m["id"]: m for m in members}
    position = {m["id"]: i for i, m in enumerate(members)}
    keys = sorted((k for k in exact if k is None or k in by_id),
                  key=lambda k: (-exact[k], -1 if k is None else position[k]))
    quantum = _quantum(currency)
    total = _rounded(sum(exact.values(), Fraction(0)), quantum)
    amounts = {k: _rounded(exact[k], quantum) for k in keys}
    remainder = total - sum(amounts.values(), Decimal(0))
    if remainder and keys:
        amounts[next((k for k in keys if k is not None), keys[0])] += remainder
    keys.sort(key=lambda k: -amounts[k])  # stable: ties keep the order above

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
    shares = await fdb.outflow_shares(family["book_user_id"], currency, date_from, date_to)
    return compute(currency, shares, await fdb.list_members(family["id"]))
