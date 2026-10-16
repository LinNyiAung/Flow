"""Income / expense transactions, including the (flattened) recurrence settings.

Amounts are exact NUMERIC and always finite and positive (database CHECK), so the
NaN/infinity filters the MongoDB code needed are gone. Sums are exact and returned as float.
"""
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import case, delete, distinct, exists, func, insert, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert

from sql.db import execute, fetch_all, fetch_one, fetch_value, transaction, write_returning
from sql.docs import money, recurrence_columns, transaction_doc, transaction_row
from sql.tables import transactions as t

# Dotted document paths the code updates directly -> columns.
_RECURRENCE_FIELDS = {
    "recurrence.enabled": "recurrence_enabled",
    "recurrence.last_created_date": "recurrence_last_created_date",
}


def _plain(value: Any) -> Any:
    return getattr(value, "value", value)  # str enums (type, currency, frequency) -> str


def _row(doc: Dict[str, Any]) -> Dict[str, Any]:
    return {k: _plain(v) for k, v in transaction_row(doc).items()}


def _values(fields: Dict[str, Any]) -> Dict[str, Any]:
    """Update fields in document shape -> column values."""
    values: Dict[str, Any] = {}
    for key, value in fields.items():
        if key == "recurrence":
            values.update({k: _plain(v) for k, v in recurrence_columns(value).items()})
        elif key in _RECURRENCE_FIELDS:
            values[_RECURRENCE_FIELDS[key]] = value
        elif key == "amount":
            values["amount"] = money(value)
        else:
            values["id" if key == "_id" else key] = _plain(value)
    return values


# ------------------------------------------------------------------ writes
async def insert_transaction(doc: Dict[str, Any]) -> bool:
    """Insert; False if a transaction with this id already exists (idempotent recurring inserts)."""
    stmt = pg_insert(t).values(**_row(doc)).on_conflict_do_nothing(index_elements=[t.c.id])
    return await execute(stmt) == 1


async def insert_many(docs: List[Dict[str, Any]]) -> None:
    """All-or-nothing batch insert."""
    if docs:
        async with transaction() as conn:
            await conn.execute(insert(t), [_row(d) for d in docs])


async def update_transaction(transaction_id: str, user_id: str, fields: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Apply fields; returns the updated transaction (None if it no longer exists)."""
    stmt = (update(t).where(t.c.id == transaction_id, t.c.user_id == user_id)
            .values(**_values(fields)).returning(*t.c))
    return transaction_doc(await write_returning(stmt))


async def set_recurrence_pointer(transaction_id: str, last_created: datetime) -> None:
    await execute(update(t).where(t.c.id == transaction_id).values(recurrence_last_created_date=last_created))


async def disable_recurrence(transaction_id: str, user_id: Optional[str] = None) -> bool:
    """Turn recurrence off; False if not found or it was already off."""
    stmt = update(t).where(t.c.id == transaction_id, t.c.recurrence_enabled.is_(True))
    if user_id is not None:
        stmt = stmt.where(t.c.user_id == user_id)
    return await execute(stmt.values(recurrence_enabled=False)) > 0


async def delete_transaction(transaction_id: str, user_id: str) -> int:
    return await execute(delete(t).where(t.c.id == transaction_id, t.c.user_id == user_id))


# ------------------------------------------------------------------ reads
async def get_transaction(transaction_id: str, user_id: Optional[str] = None) -> Optional[Dict[str, Any]]:
    stmt = select(t).where(t.c.id == transaction_id)
    if user_id is not None:
        stmt = stmt.where(t.c.user_id == user_id)
    return transaction_doc(await fetch_one(stmt))


def _filtered(stmt, user_id: Optional[str], type_: Optional[str], currency: Optional[str],
              date_from: Optional[datetime], date_to: Optional[datetime], date_before: Optional[datetime]):
    if user_id is not None:
        stmt = stmt.where(t.c.user_id == user_id)
    if type_ is not None:
        stmt = stmt.where(t.c.type == type_)
    if currency is not None:
        stmt = stmt.where(t.c.currency == currency)
    if date_from is not None:
        stmt = stmt.where(t.c.date >= date_from)
    if date_to is not None:
        stmt = stmt.where(t.c.date <= date_to)
    if date_before is not None:
        stmt = stmt.where(t.c.date < date_before)
    return stmt


async def find_transactions(user_id: str, *, type_: Optional[str] = None, currency: Optional[str] = None,
                            date_from: Optional[datetime] = None, date_to: Optional[datetime] = None,
                            date_before: Optional[datetime] = None, skip: int = 0,
                            limit: Optional[int] = None) -> List[Dict[str, Any]]:
    """Newest first (date, then created_at, then id: a stable order for skip/limit paging).
    date_from / date_to are inclusive, date_before is exclusive."""
    stmt = _filtered(select(t), user_id, type_, currency, date_from, date_to, date_before)
    stmt = stmt.order_by(t.c.date.desc(), t.c.created_at.desc(), t.c.id.desc()).offset(skip)
    if limit is not None:
        stmt = stmt.limit(limit)
    return [transaction_doc(r) for r in await fetch_all(stmt)]


async def recurring_parents() -> List[Dict[str, Any]]:
    """Every transaction with recurrence enabled (input of the recurring job)."""
    return [transaction_doc(r) for r in await fetch_all(select(t).where(t.c.recurrence_enabled.is_(True)).order_by(t.c.id))]


async def child_exists_between(user_id: str, parent_id: str, start: datetime, end: datetime) -> bool:
    """True if an auto-created child of parent_id is dated within [start, end]."""
    return bool(await fetch_value(select(exists().where(
        t.c.user_id == user_id, t.c.parent_transaction_id == parent_id, t.c.date >= start, t.c.date <= end))))


async def has_transactions_between(user_id: str, start: datetime, end: datetime) -> bool:
    return bool(await fetch_value(select(exists().where(t.c.user_id == user_id, t.c.date >= start, t.c.date <= end))))


async def currencies(user_id: str) -> List[str]:
    rows = await fetch_all(select(distinct(t.c.currency).label("c")).where(t.c.user_id == user_id).order_by("c"))
    return [r["c"] for r in rows]


async def count_transactions(user_id: Optional[str] = None) -> int:
    stmt = select(func.count()).select_from(t)
    if user_id is not None:
        stmt = stmt.where(t.c.user_id == user_id)
    return await fetch_value(stmt)


async def latest_created_at(user_id: str) -> Optional[datetime]:
    return await fetch_value(select(func.max(t.c.created_at)).where(t.c.user_id == user_id))


async def active_user_ids(since: datetime) -> List[str]:
    """Users who added a transaction since `since`."""
    return [r["user_id"] for r in await fetch_all(select(distinct(t.c.user_id).label("user_id")).where(t.c.created_at >= since))]


# ------------------------------------------------------------------ aggregates
def _f(value: Any) -> float:
    return float(value or 0)


async def currency_totals(user_id: str, *, currency: Optional[str] = None, date_from: Optional[datetime] = None,
                          date_to: Optional[datetime] = None) -> List[Dict[str, Any]]:
    """Per currency: total_inflow, total_outflow, inflow_count, outflow_count, count, amount_sum, min_date, max_date."""
    is_in, is_out = t.c.type == "inflow", t.c.type == "outflow"
    stmt = select(
        t.c.currency,
        func.sum(case((is_in, t.c.amount), else_=0)).label("total_inflow"),
        func.sum(case((is_out, t.c.amount), else_=0)).label("total_outflow"),
        func.count().filter(is_in).label("inflow_count"),
        func.count().filter(is_out).label("outflow_count"),
        func.count().label("count"),
        func.sum(t.c.amount).label("amount_sum"),
        func.min(t.c.date).label("min_date"),
        func.max(t.c.date).label("max_date"),
    )
    stmt = _filtered(stmt, user_id, None, currency, date_from, date_to, None).group_by(t.c.currency).order_by(t.c.currency)
    rows = await fetch_all(stmt)
    for r in rows:
        for k in ("total_inflow", "total_outflow", "amount_sum"):
            r[k] = _f(r[k])
    return rows


async def category_totals(user_id: str, *, type_: Optional[str] = None, currency: Optional[str] = None,
                          date_from: Optional[datetime] = None, date_to: Optional[datetime] = None) -> List[Dict[str, Any]]:
    """Per (currency, type, main_category, sub_category): total and count, largest total first."""
    total = func.sum(t.c.amount).label("total")
    stmt = select(t.c.currency, t.c.type, t.c.main_category, t.c.sub_category, total, func.count().label("count"))
    stmt = _filtered(stmt, user_id, type_, currency, date_from, date_to, None)
    stmt = stmt.group_by(t.c.currency, t.c.type, t.c.main_category, t.c.sub_category)
    stmt = stmt.order_by(total.desc(), t.c.main_category, t.c.sub_category)
    rows = await fetch_all(stmt)
    for r in rows:
        r["total"] = _f(r["total"])
    return rows
