"""Books: the owners of book data (spec: docs/superpowers/specs/2026-11-15-books-table-design.md).

Every person has exactly one personal book and every family exactly one family book. A book's id is a uuid4 of its own,
never a user id, so a person's id passed where a book id belongs finds nothing (or is refused by a foreign key).

- Creation: registration creates the personal book with the user, family creation the family book with the family
  (both in the caller's transaction()); ensure_personal_book repairs a person row that has none.
- ai_data_stale: Ko Toe Pwar's cached view of the book is out of date (mark_ai_data_stale / claim_ai_data_fresh).
- money_lock: the cross-process lock of one book's money-moving operations (a FOR UPDATE row lock on the book).
"""
import uuid
from contextlib import asynccontextmanager
from typing import Any, AsyncIterator, Dict, Optional, Sequence

from sqlalchemy import insert, select, text, update
from sqlalchemy.dialects.postgresql import insert as pg_insert

from sql import families as families_db
from sql import users as users_db
from sql.db import execute, fetch_all, fetch_one, fetch_value, transaction
from sql.tables import books as b

_ROW = (b.c.id, b.c.kind, b.c.person_id, b.c.family_id, b.c.ai_data_stale)


# ------------------------------------------------------------------ creation
async def create_personal_book(person_id: str, *, conn=None) -> str:
    """Insert the person's personal book; returns its new id. A second one for the same person violates
    uq_books_person_id (IntegrityError)."""
    book_id = str(uuid.uuid4())
    await execute(insert(b).values(id=book_id, kind="personal", person_id=person_id), conn)
    return book_id


async def ensure_personal_book(person_id: str) -> str:
    """The person's personal book id, creating the book when they have none (idempotent: concurrent callers get the
    same id)."""
    await execute(pg_insert(b).values(id=str(uuid.uuid4()), kind="personal", person_id=person_id)
                  # The predicate must be a literal for Postgres to match it to the partial unique index.
                  .on_conflict_do_nothing(index_elements=[b.c.person_id], index_where=text("person_id IS NOT NULL")))
    return await personal_book_id(person_id)


async def create_family_book(family_id: str, *, conn=None) -> str:
    """Insert the family's book; returns its new id."""
    book_id = str(uuid.uuid4())
    await execute(insert(b).values(id=book_id, kind="family", family_id=family_id), conn)
    return book_id


# ------------------------------------------------------------------ reads
async def personal_book_id(person_id: str) -> Optional[str]:
    return await fetch_value(select(b.c.id).where(b.c.person_id == person_id))


async def personal_book_ids(person_ids: Sequence[str]) -> Dict[str, str]:
    """{person id: their personal book id} in one query; a person without a book is left out."""
    if not person_ids:
        return {}
    rows = await fetch_all(select(b.c.person_id, b.c.id).where(b.c.person_id.in_(list(person_ids))))
    return {r["person_id"]: r["id"] for r in rows}


async def family_book_id(family_id: str) -> Optional[str]:
    return await fetch_value(select(b.c.id).where(b.c.family_id == family_id))


async def get_book_row(book_id: str) -> Optional[Dict[str, Any]]:
    """{id, kind, person_id, family_id, ai_data_stale}, or None (no such book, e.g. a person's id)."""
    return await fetch_one(select(*_ROW).where(b.c.id == book_id))


async def is_family_book(book_id: str) -> bool:
    return await fetch_value(select(b.c.kind).where(b.c.id == book_id)) == "family"


async def book_profile(book_id: str) -> Optional[Dict[str, Any]]:
    """The person whose settings (default_currency, language, plan) the book uses: a personal book's person, a family
    book's active owner (sql.families.owner_user). None when there is no such book or nobody (an owner's account gone)."""
    row = await get_book_row(book_id)
    if row is None:
        return None
    if row["kind"] == "personal":
        return await users_db.get_user(row["person_id"])
    return await families_db.owner_user(row["family_id"])


def spend_owner(book: Dict[str, Any]) -> Dict[str, Optional[str]]:
    """Whose AI spend the book's own AI work (its weekly / monthly insights, their translations, its AI-made budgets)
    is, as ai_providers.runner.run's user_id / book_id keywords: a personal book's person (user_id), or a family book
    itself (book_id: ai_usage.book_id, user_id NULL). `book` is its row (get_book_row)."""
    if book["kind"] == "personal":
        return {"user_id": book["person_id"], "book_id": None}
    return {"user_id": None, "book_id": book["id"]}


# ------------------------------------------------------------------ Ko Toe Pwar's freshness flag
async def mark_ai_data_stale(book_id: str) -> None:
    await execute(update(b).where(b.c.id == book_id).values(ai_data_stale=True))


async def claim_ai_data_fresh(book_id: str) -> bool:
    """ai_data_stale True -> False; True if this call cleared it."""
    return await execute(update(b).where(b.c.id == book_id, b.c.ai_data_stale.is_(True))
                         .values(ai_data_stale=False)) > 0


# ------------------------------------------------------------------ money lock
@asynccontextmanager
async def money_lock(book_id: str) -> AsyncIterator[None]:
    """Serialize one book's money-moving operations across every server process: holds the book's row lock
    (SELECT ... FOR UPDATE) for the whole block. All database calls in the block run in that one transaction, so the
    block also commits or rolls back as a unit.

    Raises LookupError when `book_id` is no book (e.g. a person's id): locking no row would let the block run without
    any serialisation, so a wrong id is refused instead of silently unprotected."""
    async with transaction() as conn:
        locked = (await conn.execute(select(b.c.id).where(b.c.id == book_id).with_for_update())).first()
        if locked is None:
            raise LookupError(f"no book {book_id}")
        yield
