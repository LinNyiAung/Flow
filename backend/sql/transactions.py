"""Income / expense transactions, including the (flattened) recurrence settings.

Amounts are exact NUMERIC and always finite and positive (database CHECK), so the
NaN/infinity filters the MongoDB code needed are gone. Sums are exact and returned as float.
"""
from datetime import date, datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import case, delete, distinct, exists, func, insert, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert

from sql.db import execute, fetch_all, fetch_one, fetch_value, transaction, write_returning
from sql.docs import money, recurrence_columns, transaction_doc, transaction_row, wall_bound as _wall
from sql.tables import books, transactions as t
from tz_utils import as_calendar_date, as_wall_clock

# A transfer between a personal wallet and the family wallet is a pair of rows with a transfer_id. It only moves money
# between two balances, so it is never income or spending: every aggregate below leaves it out (the balance adds
# currency_totals' transfer_in / transfer_out back).
NOT_TRANSFER = t.c.transfer_id.is_(None)

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
            column = _RECURRENCE_FIELDS[key]
            values[column] = as_calendar_date(value) if column == "recurrence_last_created_date" else value
        elif key == "amount":
            values["amount"] = money(value)
        elif key == "date":
            values["date"] = as_wall_clock(value)
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


async def update_transaction(transaction_id: str, book_id: str, fields: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Apply fields; returns the updated transaction (None if it no longer exists)."""
    stmt = (update(t).where(t.c.id == transaction_id, t.c.book_id == book_id)
            .values(**_values(fields)).returning(*t.c))
    return transaction_doc(await write_returning(stmt))


async def set_recurrence_pointer(transaction_id: str, last_created: date) -> None:
    """Move a recurring parent's pointer to the date of the last occurrence handled."""
    await execute(update(t).where(t.c.id == transaction_id)
                  .values(recurrence_last_created_date=as_calendar_date(last_created)))


async def disable_recurrence(transaction_id: str, book_id: str) -> bool:
    """Turn recurrence off for the transaction in `book_id`; False if not found or it was already off."""
    stmt = update(t).where(t.c.id == transaction_id, t.c.book_id == book_id, t.c.recurrence_enabled.is_(True))
    return await execute(stmt.values(recurrence_enabled=False)) > 0


async def delete_transaction(transaction_id: str, book_id: str) -> int:
    return await execute(delete(t).where(t.c.id == transaction_id, t.c.book_id == book_id))


async def delete_transfer(transfer_id: str) -> int:
    """Delete every leg of a transfer; the number deleted."""
    return await execute(delete(t).where(t.c.transfer_id == transfer_id))


# ------------------------------------------------------------------ reads
async def get_transaction(transaction_id: str, book_id: str) -> Optional[Dict[str, Any]]:
    """The transaction, only if it is in `book_id` (always given: an entry is read through its book)."""
    stmt = select(t).where(t.c.id == transaction_id, t.c.book_id == book_id)
    return transaction_doc(await fetch_one(stmt))


async def transfer_legs(transfer_id: str) -> List[Dict[str, Any]]:
    """The legs of a transfer (two, or fewer if one is gone), in a stable order."""
    rows = await fetch_all(select(t).where(t.c.transfer_id == transfer_id).order_by(t.c.type, t.c.id))
    return [transaction_doc(r) for r in rows]


def _filtered(stmt, book_id: Optional[str], type_: Optional[str], currency: Optional[str],
              date_from: Optional[datetime], date_to: Optional[datetime], date_before: Optional[datetime]):
    if book_id is not None:
        stmt = stmt.where(t.c.book_id == book_id)
    if type_ is not None:
        stmt = stmt.where(t.c.type == type_)
    if currency is not None:
        stmt = stmt.where(t.c.currency == currency)
    if date_from is not None:
        stmt = stmt.where(t.c.date >= _wall(date_from))
    if date_to is not None:
        stmt = stmt.where(t.c.date <= _wall(date_to))
    if date_before is not None:
        stmt = stmt.where(t.c.date < _wall(date_before))
    return stmt


async def find_transactions(book_id: str, *, type_: Optional[str] = None, currency: Optional[str] = None,
                            date_from: Optional[datetime] = None, date_to: Optional[datetime] = None,
                            date_before: Optional[datetime] = None, skip: int = 0,
                            limit: Optional[int] = None, include_transfers: bool = True) -> List[Dict[str, Any]]:
    """Newest first (date, then created_at, then id: a stable order for skip/limit paging).
    date_from / date_to are inclusive, date_before is exclusive. include_transfers=False leaves the legs of transfers
    out: every income or spending figure (reports, insights, budgets, the chat context) must."""
    stmt = _filtered(select(t), book_id, type_, currency, date_from, date_to, date_before)
    if not include_transfers:
        stmt = stmt.where(NOT_TRANSFER)
    stmt = stmt.order_by(t.c.date.desc(), t.c.created_at.desc(), t.c.id.desc()).offset(skip)
    if limit is not None:
        stmt = stmt.limit(limit)
    return [transaction_doc(r) for r in await fetch_all(stmt)]


async def recurring_parents(book_id: str) -> List[Dict[str, Any]]:
    """The book's transactions with recurrence enabled (input of the book's recurring run)."""
    stmt = select(t).where(t.c.book_id == book_id, t.c.recurrence_enabled.is_(True)).order_by(t.c.id)
    return [transaction_doc(r) for r in await fetch_all(stmt)]


async def child_exists_between(book_id: str, parent_id: str, start: datetime, end: datetime) -> bool:
    """True if an auto-created child of parent_id is dated within [start, end]."""
    return bool(await fetch_value(select(exists().where(
        t.c.book_id == book_id, t.c.parent_transaction_id == parent_id,
        t.c.date >= _wall(start), t.c.date <= _wall(end)))))


async def has_transactions_between(book_id: str, start: datetime, end: datetime) -> bool:
    """True when an income or spending entry (not a transfer) is dated within [start, end]."""
    return bool(await fetch_value(select(exists().where(
        t.c.book_id == book_id, t.c.date >= _wall(start), t.c.date <= _wall(end), NOT_TRANSFER))))


async def changed_since(book_id: str, start: datetime, end: datetime, since: datetime) -> bool:
    """True when an income or spending entry (not a transfer) dated within [start, end] was created or edited after
    `since`."""
    return bool(await fetch_value(select(exists().where(
        t.c.book_id == book_id, t.c.date >= _wall(start), t.c.date <= _wall(end), NOT_TRANSFER,
        (t.c.created_at > since) | (t.c.updated_at > since)))))


async def currencies(book_id: str) -> List[str]:
    rows = await fetch_all(select(distinct(t.c.currency).label("c")).where(t.c.book_id == book_id).order_by("c"))
    return [r["c"] for r in rows]


async def count_transactions(book_id: Optional[str]) -> int:
    """Entries in `book_id`; None counts every book's (admin totals), and must be passed explicitly."""
    stmt = select(func.count()).select_from(t)
    if book_id is not None:
        stmt = stmt.where(t.c.book_id == book_id)
    return await fetch_value(stmt)


async def latest_created_at(book_id: str) -> Optional[datetime]:
    return await fetch_value(select(func.max(t.c.created_at)).where(t.c.book_id == book_id))


async def active_user_ids(since: datetime) -> List[str]:
    """People who added a transaction to their personal book since `since` (person ids; family books are left out)."""
    stmt = (select(distinct(books.c.person_id).label("user_id")).select_from(t.join(books, books.c.id == t.c.book_id))
            .where(t.c.created_at >= since, books.c.person_id.isnot(None)))
    return [r["user_id"] for r in await fetch_all(stmt)]


# ------------------------------------------------------------------ aggregates
def _f(value: Any) -> float:
    return float(value or 0)


async def currency_totals(book_id: str, *, currency: Optional[str] = None, date_from: Optional[datetime] = None,
                          date_to: Optional[datetime] = None) -> List[Dict[str, Any]]:
    """Per currency with any row: total_inflow, total_outflow, inflow_count, outflow_count, count, amount_sum, min_date
    and max_date over income and spending entries only, plus transfer_in / transfer_out, the sums of the transfer legs
    into and out of the book. A currency with only transfers has count 0 (and min_date / max_date None)."""
    is_in, is_out = (t.c.type == "inflow") & NOT_TRANSFER, (t.c.type == "outflow") & NOT_TRANSFER
    is_transfer = t.c.transfer_id.is_not(None)
    stmt = select(
        t.c.currency,
        func.sum(case((is_in, t.c.amount), else_=0)).label("total_inflow"),
        func.sum(case((is_out, t.c.amount), else_=0)).label("total_outflow"),
        func.sum(case(((t.c.type == "inflow") & is_transfer, t.c.amount), else_=0)).label("transfer_in"),
        func.sum(case(((t.c.type == "outflow") & is_transfer, t.c.amount), else_=0)).label("transfer_out"),
        func.count().filter(is_in).label("inflow_count"),
        func.count().filter(is_out).label("outflow_count"),
        func.count().filter(NOT_TRANSFER).label("count"),
        func.sum(t.c.amount).filter(NOT_TRANSFER).label("amount_sum"),
        func.min(t.c.date).filter(NOT_TRANSFER).label("min_date"),
        func.max(t.c.date).filter(NOT_TRANSFER).label("max_date"),
    )
    stmt = _filtered(stmt, book_id, None, currency, date_from, date_to, None).group_by(t.c.currency).order_by(t.c.currency)
    rows = await fetch_all(stmt)
    for r in rows:
        for k in ("total_inflow", "total_outflow", "transfer_in", "transfer_out", "amount_sum"):
            r[k] = _f(r[k])
    return rows


async def category_totals(book_id: str, *, type_: Optional[str] = None, currency: Optional[str] = None,
                          date_from: Optional[datetime] = None, date_to: Optional[datetime] = None) -> List[Dict[str, Any]]:
    """Per (currency, type, main_category, sub_category): total and count, largest total first. Transfers are left
    out (they are neither income nor spending)."""
    total = func.sum(t.c.amount).label("total")
    stmt = select(t.c.currency, t.c.type, t.c.main_category, t.c.sub_category, total, func.count().label("count"))
    stmt = _filtered(stmt, book_id, type_, currency, date_from, date_to, None).where(NOT_TRANSFER)
    stmt = stmt.group_by(t.c.currency, t.c.type, t.c.main_category, t.c.sub_category)
    stmt = stmt.order_by(total.desc(), t.c.main_category, t.c.sub_category)
    rows = await fetch_all(stmt)
    for r in rows:
        r["total"] = _f(r["total"])
    return rows
