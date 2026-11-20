"""The book a request works on (spec: docs/superpowers/specs/2026-11-13-family-book-design.md, "Privacy").

Every financial route takes `book: Book = Depends(get_book)` and reads and writes `book.id` instead of the person's id.
The book is resolved on the server from the X-Book header and the caller's own membership, never from a client-supplied
user id:

- no X-Book, "" or "personal": the caller's personal book (id = its books.id, loaded with the caller by
  get_current_user as `personal_book_id`; never the caller's user id);
- "family": the book of the family the caller is an active member of (books.family_id), else 409 no_family;
- anything else: 400 invalid_book.

`Book.id` is always a books.id. Quotas, plan checks and notifications settings stay on `book.person`; only the data id
changes.

Refusals are HTTPException(status, {"code", "message"}) with the message in the caller's language (the
family_<code>_msg keys of notification_service.NOTIFICATION_TRANSLATIONS), as in families.service.
"""
from dataclasses import dataclass
from typing import Any, Dict, Iterable, List, Literal, Mapping, Optional

from fastapi import Depends, Header, HTTPException

from families.service import family_currency, family_is_read_only
from notification_service import translate
from plans.access import user_language
from sql import books as books_db
from sql import families as fdb
from utils import get_current_user

PERSONAL_VALUES = (None, "", "personal")


@dataclass(frozen=True)
class Book:
    id: str
    kind: Literal["personal", "family"]
    person: dict
    family: Optional[dict]
    member: Optional[dict]
    read_only: bool

    @property
    def is_family(self) -> bool:
        return self.kind == "family"

    @classmethod
    def personal(cls, person: dict) -> "Book":
        """The person's own book (what get_book gives without X-Book); `person` is get_current_user's dict, which
        carries `personal_book_id`."""
        return cls(id=person["personal_book_id"], kind="personal", person=person, family=None, member=None,
                   read_only=False)


def _fail(user: Mapping[str, Any], status: int, code: str):
    raise HTTPException(status_code=status,
                        detail={"code": code, "message": translate(f"family_{code}_msg", user_language(user))})


def refuse(user: Mapping[str, Any], status: int, code: str):
    """Raise the family refusal `code` (HTTP `status`, message family_<code>_msg in the user's language)."""
    _fail(user, status, code)


async def get_book(current_user: dict = Depends(get_current_user),
                   x_book: Optional[str] = Header(None, alias="X-Book")) -> Book:
    """The book named by X-Book (see the module docstring)."""
    value = x_book.strip().lower() if x_book is not None else None
    if value in PERSONAL_VALUES:
        return Book.personal(current_user)
    if value != "family":
        _fail(current_user, 400, "invalid_book")
    member = await fdb.active_membership(current_user["_id"])
    family = await fdb.get_family(member["family_id"]) if member else None
    book_id = await books_db.family_book_id(family["id"]) if family else None
    if member is None or family is None or book_id is None:
        _fail(current_user, 409, "no_family")
    return Book(id=book_id, kind="family", person=current_user, family=family, member=member,
                read_only=await family_is_read_only(family))


async def book_currency(book: Book) -> str:
    """The currency the book's defaults use (a summary, a report or an AI-read entry with no currency given): the
    person's default currency for a personal book, the family's (its owner's, family_currency) for a family book."""
    if book.is_family:
        return await family_currency(book.family["id"])
    return book.person.get("default_currency") or "usd"


def require_writable(book: Book) -> None:
    """403 family_read_only for a family book whose owner's plan isn't Plus or Pro (a personal book is always writable)."""
    if book.read_only:
        _fail(book.person, 403, "family_read_only")


def require_admin(book: Book) -> None:
    """403 not_allowed unless the caller is the family's owner or an admin (a personal book: always allowed)."""
    if book.is_family and (book.member or {}).get("role") not in fdb.ADMIN_ROLES:
        _fail(book.person, 403, "not_allowed")


def can_change_entry(book: Book, entry: Mapping[str, Any]) -> bool:
    """Whether the caller may edit or delete `entry` in this book: always in a personal book; in a family book, the
    owner and admins may change any entry, a member only the entries they added."""
    if not book.is_family:
        return True
    member: Dict[str, Any] = book.member or {}
    return member.get("role") in fdb.ADMIN_ROLES or entry.get("added_by_member_id") == member.get("id")


def require_change_entry(book: Book, entry: Mapping[str, Any]) -> None:
    """403 not_allowed unless can_change_entry (an entry with no recorded adder: admins only)."""
    if not can_change_entry(book, entry):
        _fail(book.person, 403, "not_allowed")


async def clean_for_whom(book: Book, member_ids: Optional[Iterable[str]],
                         already_tagged: Iterable[str] = ()) -> Optional[List[str]]:
    """Who an entry is for, checked: None stays None (not given), duplicates go (first one kept), [] is Whole family.
    400 invalid_for_whom for any id in a personal book, or, in a family book, any id that isn't an active member
    (account or placeholder) of this family.

    `already_tagged` (an update: the entry's current tags) may stay even when they are former members now, so an edit
    never has to drop someone from history (R20); a former member not already on the entry is still refused."""
    if member_ids is None:
        return None
    ids = list(dict.fromkeys(member_ids))
    if not ids:
        return []
    if not book.is_family:
        _fail(book.person, 400, "invalid_for_whom")
    members = await fdb.list_members(book.family["id"])
    allowed = {m["id"] for m in members if m["status"] == "active"}
    # Only ids that are (former) members of this family; the tags of a family entry always are.
    family_ids = {m["id"] for m in members}
    allowed |= {i for i in already_tagged if i in family_ids}
    if any(i not in allowed for i in ids):
        _fail(book.person, 400, "invalid_for_whom")
    return ids
