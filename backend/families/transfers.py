"""Transfers between a person's wallet and their family's wallet (spec: "The family wallet and transfers", "Transfers
aren't income or spending", "Undoing a transfer").

A transfer is one linked pair of transactions sharing a transfer_id: an outflow in the source book and an inflow in the
destination book, with the same date, currency, amount and description, main_category "Transfer" and sub_category
"Family wallet". It only moves money between the two balances: every income and spending figure leaves rows with a
transfer_id out (sql.transactions), the balance counts them (utils.get_book_balance).

Money never appears or disappears: both legs are written, and removed, together in one database transaction while
holding both books' money locks (utils.get_books_money_locks: the in-process locks first, then the transaction, then
the row locks, each in sorted id order so two transfers between the same books can't deadlock).

Refusals are HTTPException(status, {"code", "message"}) in the caller's language, as in families.book.
"""
import uuid
from datetime import UTC, datetime
from typing import Any, Dict, Iterable, List, Literal, Optional

from fastapi import BackgroundTasks, HTTPException

from budget_service import update_relevant_budgets
from families.book import Book, get_book, refuse, require_writable
from goal_routes import to_cents
from sql import transactions as transactions_db
from sql import families as fdb
from sql import books as books_db
from utils import get_book_balance, get_books_money_locks

MAIN_CATEGORY = "Transfer"
SUB_CATEGORY = "Family wallet"
Direction = Literal["to_family", "to_personal"]


async def _family_book(person: dict) -> Optional[Book]:
    """The caller's own family book (whatever X-Book says), or None outside a family."""
    try:
        return await get_book(person, "family")
    except HTTPException:
        return None


async def _still_in(book: Book) -> None:
    """Under the locks: the caller is still an active member of this family (409 no_family if they left or were
    removed since the book was resolved)."""
    me = await fdb.active_membership(book.person["_id"])
    if me is None or me["family_id"] != book.family["id"]:
        refuse(book.person, 409, "no_family")


def _refresh(background_tasks: BackgroundTasks, legs: Iterable[Dict[str, Any]]) -> None:
    """Budgets of both books in the background, as for a normal entry (a transfer is never budget spending, but the
    budgets are recomputed the same way)."""
    for leg in legs:
        date = leg["date"] if leg["date"].tzinfo else leg["date"].replace(tzinfo=UTC)
        background_tasks.add_task(update_relevant_budgets, leg["book_id"], date, leg["currency"])


async def create_transfer(person: dict, direction: Direction, amount: float, currency: str, date: datetime,
                          description: Optional[str], background_tasks: BackgroundTasks) -> Dict[str, str]:
    """Move `amount` between the caller's wallet and their family's: `to_family` out of theirs into the family's,
    `to_personal` out of the family's into theirs. Any active member of a family that isn't read-only.

    400 transfer_insufficient when the amount is more than the source book's available balance (balance minus money
    held for goals) in that currency; nothing is written then."""
    book = await _family_book(person)
    if book is None:
        refuse(person, 409, "no_family")
    require_writable(book)

    to_family = direction == "to_family"
    personal_book = book.person["personal_book_id"]
    source = personal_book if to_family else book.id
    transfer_id = str(uuid.uuid4())
    now = datetime.now(UTC)
    when = date if date.tzinfo else date.replace(tzinfo=UTC)
    note = (description or "").strip() or None

    def leg(book_id: str, type_: str, added_by: Optional[str]) -> Dict[str, Any]:
        return {"_id": str(uuid.uuid4()), "book_id": book_id, "type": type_, "main_category": MAIN_CATEGORY,
                "sub_category": SUB_CATEGORY, "date": when, "description": note, "amount": amount,
                "currency": currency, "created_at": now, "updated_at": now, "recurrence": None,
                "transfer_id": transfer_id, "added_by_member_id": added_by}

    personal = leg(personal_book, "outflow" if to_family else "inflow", None)
    family = leg(book.id, "inflow" if to_family else "outflow", book.member["id"])

    async with get_books_money_locks((personal_book, book.id)):  # one transaction: both legs or neither
        await _still_in(book)
        available = (await get_book_balance(source, currency))["available_balance"]
        if to_cents(amount) > to_cents(available):
            refuse(person, 400, "transfer_insufficient")
        await transactions_db.insert_transaction(personal)
        await transactions_db.insert_transaction(family)

    for book_id in (personal_book, book.id):
        await books_db.mark_ai_data_stale(book_id)
    _refresh(background_tasks, (personal, family))
    return {"transfer_id": transfer_id, "personal_transaction_id": personal["_id"],
            "family_transaction_id": family["_id"]}


async def undo_transfer(person: dict, transfer_id: str, background_tasks: BackgroundTasks) -> Dict[str, str]:
    """Remove both legs of a transfer, in one database transaction under both books' money locks.

    Only the person who made it (the personal leg is in their book) may undo it; anyone else, admins included, gets
    403 not_allowed, as does the mover once they are no longer in the family whose leg it is, and a read-only family
    refuses (family_read_only).

    Both legs must exist (R13): if one is gone (e.g. the family was deleted, which removes the family leg while the
    personal leg stays in the mover's history), 409 transfer_gone and nothing is deleted. Removing the remaining leg
    would bring back money that left with the other book. 400 transfer_insufficient when taking the money back would
    leave the book it went to with less than nothing available (it was spent or set aside since)."""
    legs = await transactions_db.transfer_legs(transfer_id)
    if not legs:
        refuse(person, 404, "transfer_not_found")
    personal_book = person["personal_book_id"]
    if not any(x["book_id"] == personal_book for x in legs):
        refuse(person, 403, "not_allowed")  # someone else's transfer (its personal leg is in their book)
    if len(legs) != 2:
        refuse(person, 409, "transfer_gone")
    family_leg = next(x for x in legs if x["book_id"] != personal_book)
    book = await _family_book(person)
    if book is None or family_leg["book_id"] != book.id:
        refuse(person, 403, "not_allowed")  # a family the caller is no longer in
    require_writable(book)

    async with get_books_money_locks(x["book_id"] for x in legs):  # one transaction: both legs or neither
        legs = await transactions_db.transfer_legs(transfer_id)
        if not legs:
            refuse(person, 404, "transfer_not_found")  # undone meanwhile
        if len(legs) != 2:
            refuse(person, 409, "transfer_gone")
        await _check_destination(person, legs)
        await transactions_db.delete_transfer(transfer_id)

    for book_id in {x["book_id"] for x in legs}:
        await books_db.mark_ai_data_stale(book_id)
    _refresh(background_tasks, legs)
    return {"message": "Transfer undone", "transfer_id": transfer_id}


async def _check_destination(person: dict, legs: List[Dict[str, Any]]) -> None:
    """The book the money went to (the inflow leg) must still have it available."""
    inflow = next(x for x in legs if x["type"] == "inflow")
    available = (await get_book_balance(inflow["book_id"], inflow["currency"]))["available_balance"]
    if to_cents(available) < to_cents(inflow["amount"]):
        refuse(person, 400, "transfer_insufficient")
