"""In-app notifications."""
import logging
from datetime import date, datetime
from typing import Any, Dict, Iterable, List, Optional, Union

from sqlalchemy import and_, delete, exists as sql_exists, func, insert, or_, select, update
from sqlalchemy.exc import IntegrityError

from sql.db import execute, fetch_all, fetch_value, transaction, write_returning
from sql.docs import row_to_doc
from sql.tables import books
from sql.tables import notifications as n

logger = logging.getLogger(__name__)

_COLUMNS = {c.name for c in n.columns}
FOREIGN_KEY_VIOLATION = "23503"  # PostgreSQL SQLSTATE

# A notice's subject: at most one of these typed links (each a FK, SET NULL when the thing is deleted), the one its
# type names (notification_service.NOTIFICATION_LINKS). LINKS adds the book the notice is about.
SUBJECT_LINKS = ("goal_id", "budget_id", "transaction_id", "custom_insight_id", "family_invite_id", "family_id")
LINKS = (*SUBJECT_LINKS, "book_id")


def _row(doc: Dict[str, Any]) -> Dict[str, Any]:
    row = {("id" if k == "_id" else k): v for k, v in doc.items() if ("id" if k == "_id" else k) in _COLUMNS}
    if isinstance(row.get("reminder_target_date"), str):  # stored as "YYYY-MM-DD" by the code
        row["reminder_target_date"] = date.fromisoformat(row["reminder_target_date"])
    return row


def _if_exists(link: str, value: str):
    """The link's value as a sub-select of the row it points at, so a subject (or book) deleted before the notice is
    stored leaves the link NULL instead of failing the insert (and the action that sent the notice)."""
    target = next(iter(n.c[link].foreign_keys)).column
    return select(target).where(target == value).scalar_subquery()


def _is_fk_violation(e: IntegrityError) -> bool:
    return getattr(e.orig, "sqlstate", None) == FOREIGN_KEY_VIOLATION


async def _insert(row: Dict[str, Any]) -> Dict[str, Any]:
    """INSERT ... RETURNING in a savepoint of the caller's transaction (or its own transaction), so a failed insert
    leaves the caller's transaction usable."""
    async with transaction():
        return await write_returning(insert(n).values(**row).returning(*n.c))


async def insert_notification(doc: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Store one notice; returns it as stored (a link whose row was already gone is None, and logged).

    A subject deleted between a link's sub-select and the insert's FK check fails the insert: it is retried once with
    every link NULL. If that fails too (e.g. the recipient is gone), the notice is skipped and logged, and None is
    returned: a notice never turns the action that sent it into an error."""
    row = _row(doc)
    requested = {link: row[link] for link in LINKS if row.get(link) is not None}
    try:
        stored = await _insert({**row, **{link: _if_exists(link, v) for link, v in requested.items()}})
    except IntegrityError as e:
        if not _is_fk_violation(e):
            raise
        logger.warning("Notification %s for %s: a link's row was deleted while it was stored (%s); retrying with no "
                       "links", row.get("type"), row.get("user_id"), e.orig)
        try:
            stored = await _insert({**row, **dict.fromkeys(requested)})
        except IntegrityError as e2:
            if not _is_fk_violation(e2):
                raise
            logger.warning("Notification %s for %s skipped: it could not be stored even with no links (%s)",
                           row.get("type"), row.get("user_id"), e2.orig)
            return None
    for link, value in requested.items():
        if stored.get(link) is None:
            logger.warning("Notification %s for %s: %s %s no longer exists; the link is stored NULL",
                           row.get("type"), row.get("user_id"), link, value)
    return row_to_doc(stored)


async def insert_many(docs: Iterable[Dict[str, Any]]) -> int:
    """Store notices that link nothing (the admin broadcast), in one batch."""
    rows = [_row(d) for d in docs]
    if not rows:
        return 0
    async with transaction() as conn:
        await conn.execute(insert(n), rows)
    return len(rows)


async def list_for_user(user_id: str, unread_only: bool, limit: int) -> List[Dict[str, Any]]:
    """The person's notices, newest first, each with `subject_id` (the one subject link set, else None) and
    `book_kind` (the kind of the book it is about, else None)."""
    stmt = (select(n, func.coalesce(*(n.c[link] for link in SUBJECT_LINKS)).label("subject_id"),
                   books.c.kind.label("book_kind"))
            .select_from(n.outerjoin(books, books.c.id == n.c.book_id))
            .where(n.c.user_id == user_id))
    if unread_only:
        stmt = stmt.where(n.c.is_read.is_(False))
    return [row_to_doc(r) for r in await fetch_all(stmt.order_by(n.c.created_at.desc(), n.c.id).limit(limit))]


async def mark_read(user_id: str, notification_id: str) -> int:
    """Matched rows (already-read still counts, so the call stays idempotent)."""
    return await execute(update(n).where(n.c.id == notification_id, n.c.user_id == user_id).values(is_read=True))


async def mark_all_read(user_id: str) -> int:
    return await execute(update(n).where(n.c.user_id == user_id, n.c.is_read.is_(False)).values(is_read=True))


async def delete_notification(user_id: str, notification_id: str) -> int:
    return await execute(delete(n).where(n.c.id == notification_id, n.c.user_id == user_id))


async def unread_count(user_id: str) -> int:
    return await fetch_value(select(func.count()).select_from(n).where(n.c.user_id == user_id, n.c.is_read.is_(False)))


async def count_all() -> int:
    return await fetch_value(select(func.count()).select_from(n))


def _owner(user_id: Union[str, Iterable[str]]):
    """user_id is one user or several (a family book's members: any of them having it counts)."""
    return n.c.user_id == user_id if isinstance(user_id, str) else n.c.user_id.in_(list(user_id))


async def exists(user_id: Union[str, Iterable[str]], types: Union[str, Iterable[str]], *, goal_id: Optional[str] = None,
                 budget_id: Optional[str] = None, transaction_id: Optional[str] = None,
                 custom_insight_id: Optional[str] = None, family_invite_id: Optional[str] = None,
                 family_id: Optional[str] = None, book_id: Optional[str] = None, goal_name: Optional[str] = None,
                 currency: Optional[str] = None, since: Optional[datetime] = None, no_subject: bool = False) -> bool:
    """De-duplication check: a notification of these type(s) exists for the user, or for any of the users given,
    optionally linked to this goal / budget / transaction / custom insight / invite / family / book, or with no
    subject link at all (no_subject), with this name and currency, created at or after `since`."""
    type_list = [types] if isinstance(types, str) else list(types)
    conds = [_owner(user_id), n.c.type.in_(type_list)]
    links = {"goal_id": goal_id, "budget_id": budget_id, "transaction_id": transaction_id,
             "custom_insight_id": custom_insight_id, "family_invite_id": family_invite_id, "family_id": family_id,
             "book_id": book_id}
    conds.extend(n.c[link] == value for link, value in links.items() if value is not None)
    if no_subject:
        conds.extend(n.c[link].is_(None) for link in SUBJECT_LINKS)
    if goal_name is not None:
        conds.append(n.c.goal_name == goal_name)
    if currency is not None:
        conds.append(n.c.currency == currency)
    if since is not None:
        conds.append(n.c.created_at >= since)
    return bool(await fetch_value(select(sql_exists().where(*conds))))


async def approaching_reminder_exists(user_id: Union[str, Iterable[str]], goal_id: str, threshold: int, target_key: str,
                                      since: datetime) -> bool:
    """goal_approaching_date already sent for this goal (to the user, or any of the users given) for this
    threshold+target date, or any one since `since`."""
    target = date.fromisoformat(target_key) if isinstance(target_key, str) else target_key
    stmt = select(sql_exists().where(
        _owner(user_id), n.c.goal_id == goal_id, n.c.type == "goal_approaching_date",
        or_(and_(n.c.reminder_threshold == threshold, n.c.reminder_target_date == target), n.c.created_at >= since),
    ))
    return bool(await fetch_value(stmt))
