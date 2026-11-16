"""AI usage records (tokens and estimated cost per AI call) and the admin statistics.

Whose spend a row is: `user_id`, a person (their own AI work and work on their personal book), or `book_id` with
user_id NULL, a family book's own AI work (its insights, their translations, its AI-made budgets). A person's rows go
with their account (ON DELETE CASCADE); a deleted family's rows stay with both NULL (book_id ON DELETE SET NULL), so
the admin totals keep their cost and the per-user report shows it as one "Deleted family" row.
"""
from datetime import datetime
from typing import Any, Dict, Iterable, List, Optional, Sequence

from sqlalchemy import and_, case, distinct, func, insert, or_, select

from sql.db import execute, fetch_all, fetch_one, fetch_value
from sql.docs import rows_to_docs
from sql.tables import ai_usage, books, families, family_members, users

c = ai_usage.c

DELETED_FAMILY = "Deleted family"

# The book whose own spend a row is (NULL for a person's spend): the report's second grouping key beside user_id.
_BOOK_KEY = case((c.user_id.is_(None), c.book_id))


def _window(stmt, start: Optional[datetime], end: Optional[datetime]):
    if start:
        stmt = stmt.where(c.created_at >= start)
    if end:
        stmt = stmt.where(c.created_at <= end)
    return stmt


def _count_if(condition):
    return func.count(case((condition, 1)))


def _sum_if(condition, column):
    return func.coalesce(func.sum(case((condition, column), else_=0)), 0)


_ID_LISTS = ("user_ids", "book_ids")


def _f(row: Dict[str, Any]) -> Dict[str, Any]:
    """Decimal sums -> float; NULL sums -> 0; NULL id lists (no rows matched the aggregate's filter) -> []."""
    return {k: (list(v or []) if k in _ID_LISTS else
                float(v) if hasattr(v, "is_finite") else (0 if v is None and k not in ("user_id", "book_id") else v))
            for k, v in row.items()}


async def insert_usage(doc: Dict[str, Any]) -> None:
    """One usage row from ai_usage_service.track_ai_usage's record: its owner is `user_id` (a person) or `book_id` (a
    family book's own AI work, user_id NULL)."""
    await execute(insert(ai_usage).values(**{("id" if k == "_id" else k): v for k, v in doc.items()}))


async def user_cost_since(user_id: str, since: datetime) -> float:
    """The person's estimated AI spend (USD) on calls made at or after `since` (the hidden cost cap's window)."""
    total = await fetch_value(select(func.coalesce(func.sum(c.estimated_cost_usd), 0))
                              .where(c.user_id == user_id, c.created_at >= since))
    return float(total or 0)


async def book_cost_since(book_id: str, since: datetime) -> float:
    """A family book's own estimated AI spend (USD, the rows recorded on its book_id) at or after `since`; it counts
    toward the family owner's cost cap (ruling R16, plans.quota.family_over_cost_cap)."""
    total = await fetch_value(select(func.coalesce(func.sum(c.estimated_cost_usd), 0))
                              .where(c.book_id == book_id, c.user_id.is_(None), c.created_at >= since))
    return float(total or 0)


async def backup_answer_counts(since: datetime) -> Dict[str, int]:
    """fallback_from provider -> number of answers since `since` that a backup gave after that provider failed.
    A backup's billed answer that was rejected (outcome 'rejected') is not an answer given; a cut-short one counts."""
    rows = await fetch_all(
        select(c.fallback_from, func.count().label("n"))
        .where(c.fallback_from.is_not(None), c.created_at >= since,
               or_(c.outcome.is_(None), c.outcome != "rejected"))
        .group_by(c.fallback_from))
    return {r["fallback_from"]: int(r["n"]) for r in rows}


async def overall_stats(start: Optional[datetime], end: Optional[datetime]) -> Dict[str, Any]:
    """Totals over every row in the window: people's, family books' and deleted families' spend alike (so the total
    cost matches cost_by_provider and a family's deletion leaves it unchanged). unique_users counts people only."""
    stmt = _window(select(
        func.count().label("total_requests"),
        func.coalesce(func.sum(c.total_tokens), 0).label("total_tokens"),
        func.coalesce(func.sum(c.estimated_cost_usd), 0).label("total_cost"),
        _count_if(c.feature_type == "weekly_insight").label("weekly_insights"),
        _count_if(c.feature_type == "monthly_insight").label("monthly_insights"),
        _count_if(c.feature_type == "chat").label("chat_requests"),
        _count_if(c.feature_type == "translation").label("translations"),
        func.count(distinct(c.user_id)).label("unique_users"),  # NULL (a book's own or a deleted family's) not counted
    ), start, end)
    out = _f(await fetch_one(stmt))
    by_provider = await fetch_all(_window(
        select(c.provider, func.coalesce(func.sum(c.estimated_cost_usd), 0).label("cost")), start, end).group_by(c.provider))
    out["cost_by_provider"] = {r["provider"]: float(r["cost"]) for r in by_provider}
    return out


async def _labels(user_ids: Sequence[str], book_ids: Sequence[str]) -> Dict[tuple, tuple]:
    """(user_id, book_id) report key -> (user_name, user_email). A person: their name and e-mail. A family book:
    "Family · <family name>" and "Family book · owner <the active owner's e-mail>" (never a reserved address)."""
    out: Dict[tuple, tuple] = {}
    if user_ids:
        for r in await fetch_all(select(users.c.id, users.c.name, users.c.email).where(users.c.id.in_(list(user_ids)))):
            out[(r["id"], None)] = (r["name"], r["email"])
    if book_ids:
        owner = users.alias("owner_user")
        owner_email = (select(owner.c.email)
                       .select_from(family_members.join(owner, owner.c.id == family_members.c.user_id))
                       .where(family_members.c.family_id == books.c.family_id, family_members.c.role == "owner",
                              family_members.c.status == "active")
                       .limit(1).scalar_subquery())
        person = users.alias("book_person")
        rows = await fetch_all(
            select(books.c.id, books.c.kind, families.c.name.label("family_name"), owner_email.label("owner_email"),
                   person.c.name.label("person_name"), person.c.email.label("person_email"))
            .select_from(books.outerjoin(families, families.c.id == books.c.family_id)
                         .outerjoin(person, person.c.id == books.c.person_id))
            .where(books.c.id.in_(list(book_ids))))
        for r in rows:
            if r["kind"] == "family":
                out[(None, r["id"])] = (f"Family · {r['family_name']}" if r["family_name"] else "Family",
                                        f"Family book · owner {r['owner_email']}" if r["owner_email"]
                                        else "Family book · no owner")
            else:  # not written by the app (a personal book's spend is its person's), but labelled sensibly
                out[(None, r["id"])] = (r["person_name"] or "Personal book", r["person_email"] or "")
    return out


async def per_user_stats(start: Optional[datetime], end: Optional[datetime], sort_by: str,
                         skip: int, limit: int) -> List[Dict[str, Any]]:
    """One row per spender, ordered by sort_by desc: a person (user_id set, book_id None), a family book's own spend
    (book_id set, user_id None, labelled as its family) and, when there is any, one row for every deleted family's
    spend (both None, user_name "Deleted family"). Each row has user_name and user_email (see _labels)."""
    metrics = {
        "total_requests": func.count().label("total_requests"),
        "total_tokens": func.coalesce(func.sum(c.total_tokens), 0).label("total_tokens"),
        "total_cost": func.coalesce(func.sum(c.estimated_cost_usd), 0).label("total_cost"),
    }
    stmt = _window(select(
        c.user_id, _BOOK_KEY.label("book_id"),
        metrics["total_requests"],
        func.coalesce(func.sum(c.input_tokens), 0).label("total_input_tokens"),
        func.coalesce(func.sum(c.output_tokens), 0).label("total_output_tokens"),
        metrics["total_tokens"], metrics["total_cost"],
        _count_if(c.feature_type == "weekly_insight").label("weekly_insights"),
        _count_if(c.feature_type == "monthly_insight").label("monthly_insights"),
        _count_if(c.feature_type == "chat").label("chat_requests"),
        _count_if(c.feature_type == "translation").label("translations"),
    ), start, end)
    stmt = (stmt.group_by(c.user_id, _BOOK_KEY)
            .order_by(metrics[sort_by].desc(), c.user_id, _BOOK_KEY).offset(skip).limit(limit))
    rows = [_f(dict(r)) for r in await fetch_all(stmt)]
    if not rows:
        return rows
    page_users = [r["user_id"] for r in rows if r["user_id"]]
    page_books = [r["book_id"] for r in rows if r["book_id"]]
    labels = await _labels(page_users, page_books)
    for r in rows:
        key = (r["user_id"], r["book_id"])
        if key == (None, None):
            r["user_name"], r["user_email"] = DELETED_FAMILY, ""
        else:
            r["user_name"], r["user_email"] = labels.get(key, ("Unknown", ""))
        r["cost_by_provider"] = {}
    # cost per provider for just the spenders on this page
    on_page = []
    if page_users:
        on_page.append(c.user_id.in_(page_users))
    if page_books:
        on_page.append(and_(c.user_id.is_(None), c.book_id.in_(page_books)))
    if any(r["user_id"] is None and r["book_id"] is None for r in rows):
        on_page.append(and_(c.user_id.is_(None), c.book_id.is_(None)))
    by_provider = await fetch_all(_window(
        select(c.user_id, _BOOK_KEY.label("book_id"), c.provider,
               func.coalesce(func.sum(c.estimated_cost_usd), 0).label("cost"))
        .where(or_(*on_page)), start, end).group_by(c.user_id, _BOOK_KEY, c.provider))
    index = {(r["user_id"], r["book_id"]): r for r in rows}
    for p in by_provider:
        index[(p["user_id"], p["book_id"])]["cost_by_provider"][p["provider"]] = float(p["cost"])
    return rows


async def _detail(where, feature_type: Optional[str], limit: int) -> List[Dict[str, Any]]:
    stmt = select(ai_usage).where(where)
    if feature_type:
        stmt = stmt.where(c.feature_type == feature_type)
    return rows_to_docs(await fetch_all(stmt.order_by(c.created_at.desc(), c.id).limit(limit)))


async def user_detail(user_id: str, feature_type: Optional[str], limit: int) -> List[Dict[str, Any]]:
    """A person's usage rows, newest first."""
    return await _detail(c.user_id == user_id, feature_type, limit)


async def book_detail(book_id: str, feature_type: Optional[str] = None, limit: int = 100) -> List[Dict[str, Any]]:
    """A family book's own usage rows (book_id, user_id NULL), newest first."""
    return await _detail(and_(c.book_id == book_id, c.user_id.is_(None)), feature_type, limit)


async def feature_stats(features: Iterable[str], start: Optional[datetime], end: Optional[datetime]) -> List[Dict[str, Any]]:
    """Per feature type: requests, tokens, cost, the distinct people (user_ids) and the distinct family books whose own
    spend it was (book_ids). A deleted family's rows count in the totals but in neither list."""
    stmt = _window(select(
        c.feature_type,
        func.count().label("total_requests"),
        func.coalesce(func.sum(c.total_tokens), 0).label("total_tokens"),
        func.coalesce(func.sum(c.estimated_cost_usd), 0).label("total_cost"),
        func.array_agg(distinct(c.user_id)).filter(c.user_id.is_not(None)).label("user_ids"),
        func.array_agg(distinct(c.book_id)).filter(c.user_id.is_(None), c.book_id.is_not(None)).label("book_ids"),
    ).where(c.feature_type.in_(list(features))), start, end).group_by(c.feature_type)
    return [_f(r) for r in await fetch_all(stmt)]
