"""Families, their members and invitations, and who family entries were for (families, family_members,
family_invites, transaction_beneficiaries). Plain Core queries; the rules live in families.service.

Rows come back as plain dicts with `id` (not `_id`). Every helper joins the caller's transaction() when inside one.
"""
from datetime import datetime
from typing import Any, Dict, List, Optional, Sequence

from sqlalchemy import and_, delete, exists, func, insert, or_, select, update

from sql.db import execute, fetch_all, fetch_one, fetch_value, write_returning
from sql.tables import (families as f, family_invites as fi, family_members as fm, transaction_beneficiaries as tb,
                        transactions as t, users)

ADMIN_ROLES = ("owner", "admin")


# ---- families ----

async def insert_family(family_id: str, name: str, book_user_id: str) -> None:
    await execute(insert(f).values(id=family_id, name=name, book_user_id=book_user_id))


async def get_family(family_id: str) -> Optional[Dict[str, Any]]:
    return await fetch_one(select(f).where(f.c.id == family_id))


async def family_for_book(book_user_id: str) -> Optional[Dict[str, Any]]:
    """The family whose hidden book user this is, or None (a person's id)."""
    return await fetch_one(select(f).where(f.c.book_user_id == book_user_id))


async def books_with_paid_owner(plans: Sequence[str]) -> List[Dict[str, Any]]:
    """Every family whose active owner's stored plan is one of `plans` (the scheduled insight jobs), oldest first:
    `book_user_id`, `family_id`, `family_name` and `owner`, the owner's user fields that effective_plan and
    quota.over_cost_cap read (`_id`, subscription_type, subscription_expires_at, usage_reset_at). The caller still
    checks the owner's effective plan (an expired paid plan is stored as paid until the expiry job runs)."""
    stmt = (select(f.c.book_user_id, f.c.id.label("family_id"), f.c.name.label("family_name"),
                   users.c.id.label("owner_id"), users.c.subscription_type, users.c.subscription_expires_at,
                   users.c.usage_reset_at)
            .select_from(f.join(fm, and_(fm.c.family_id == f.c.id, fm.c.role == "owner", fm.c.status == "active"))
                         .join(users, users.c.id == fm.c.user_id))
            .where(users.c.subscription_type.in_(list(plans)), users.c.kind == "person")
            .order_by(f.c.created_at, f.c.id))
    return [{"book_user_id": r["book_user_id"], "family_id": r["family_id"], "family_name": r["family_name"],
             "owner": {"_id": r["owner_id"], "subscription_type": r["subscription_type"],
                       "subscription_expires_at": r["subscription_expires_at"],
                       "usage_reset_at": r["usage_reset_at"]}}
            for r in await fetch_all(stmt)]


async def owner_user(family_id: str) -> Optional[Dict[str, Any]]:
    """The active owner's user fields that effective_plan and quota.over_cost_cap read (`_id`, subscription_type,
    subscription_expires_at, usage_reset_at), plus language and default_currency; None when the owner's account is
    gone."""
    fields = ("subscription_type", "subscription_expires_at", "usage_reset_at", "language", "default_currency")
    row = await fetch_one(select(users.c.id, *(users.c[k] for k in fields))
                          .select_from(fm.join(users, users.c.id == fm.c.user_id))
                          .where(fm.c.family_id == family_id, fm.c.role == "owner", fm.c.status == "active"))
    if row is None:
        return None
    return {"_id": row["id"], **{k: row[k] for k in fields}}


async def lock_family(family_id: str) -> Optional[Dict[str, Any]]:
    """SELECT ... FOR UPDATE on the family row (inside transaction()): serialises the membership changes whose limits
    are counted (invites, joins, placeholders, ownership)."""
    return await fetch_one(select(f).where(f.c.id == family_id).with_for_update())


async def rename_family(family_id: str, name: str) -> None:
    await execute(update(f).where(f.c.id == family_id).values(name=name, updated_at=func.now()))


# ---- members ----

async def insert_member(member_id: str, family_id: str, display_name: str, kind: str, role: Optional[str],
                        user_id: Optional[str] = None) -> None:
    await execute(insert(fm).values(id=member_id, family_id=family_id, user_id=user_id, display_name=display_name,
                                    kind=kind, role=role, status="active"))


async def active_membership(user_id: str) -> Optional[Dict[str, Any]]:
    """The person's active member row (at most one: uq_family_members_user_active), or None."""
    return await fetch_one(select(fm).where(fm.c.user_id == user_id, fm.c.status == "active"))


async def get_member(member_id: str, family_id: str) -> Optional[Dict[str, Any]]:
    return await fetch_one(select(fm).where(fm.c.id == member_id, fm.c.family_id == family_id))


async def list_members(family_id: str) -> List[Dict[str, Any]]:
    """Every member, active and former, oldest first."""
    return await fetch_all(select(fm).where(fm.c.family_id == family_id).order_by(fm.c.joined_at, fm.c.id))


async def owner(family_id: str) -> Optional[Dict[str, Any]]:
    """The active owner member joined with the owner's user row (user columns prefixed `user_`; None if the
    account is gone)."""
    stmt = (select(fm, users.c.subscription_type.label("user_subscription_type"),
                   users.c.subscription_expires_at.label("user_subscription_expires_at"))
            .select_from(fm.outerjoin(users, users.c.id == fm.c.user_id))
            .where(fm.c.family_id == family_id, fm.c.role == "owner", fm.c.status == "active"))
    return await fetch_one(stmt)


async def former_account_member(family_id: str, user_id: str) -> Optional[Dict[str, Any]]:
    """The person's most recent former member row in this family, or None."""
    return await fetch_one(select(fm).where(fm.c.family_id == family_id, fm.c.user_id == user_id,
                                            fm.c.kind == "account", fm.c.status == "former")
                           .order_by(fm.c.left_at.desc().nulls_last()).limit(1))


async def admin_user_ids(family_id: str) -> List[str]:
    """User ids of the active owner and admins."""
    rows = await fetch_all(select(fm.c.user_id).where(fm.c.family_id == family_id, fm.c.status == "active",
                                                      fm.c.role.in_(ADMIN_ROLES), fm.c.user_id.isnot(None)))
    return [r["user_id"] for r in rows]


async def account_user_ids_for_book(book_user_id: str) -> List[str]:
    """User ids of the active account members of the family whose book user this is, in join order (who a family
    book's notifications go to); [] when it isn't a book user."""
    rows = await fetch_all(select(fm.c.user_id).select_from(fm.join(f, f.c.id == fm.c.family_id))
                           .where(f.c.book_user_id == book_user_id, fm.c.status == "active", fm.c.kind == "account",
                                  fm.c.user_id.isnot(None))
                           .order_by(fm.c.joined_at, fm.c.id))
    return [r["user_id"] for r in rows]


async def active_member_user_id(book_user_id: str, member_id: str) -> Optional[str]:
    """The user id of this member of the book's family while it is an active account member, else None."""
    return await fetch_value(select(fm.c.user_id).select_from(fm.join(f, f.c.id == fm.c.family_id))
                             .where(f.c.book_user_id == book_user_id, fm.c.id == member_id, fm.c.status == "active",
                                    fm.c.kind == "account", fm.c.user_id.isnot(None)))


async def count_active(family_id: str, kind: str) -> int:
    return int(await fetch_value(select(func.count()).select_from(fm).where(
        fm.c.family_id == family_id, fm.c.kind == kind, fm.c.status == "active")))


async def update_member(member_id: str, **fields: Any) -> int:
    return await execute(update(fm).where(fm.c.id == member_id).values(**fields))


async def set_former(member_id: str, now: datetime) -> bool:
    """Active, non-owner member -> former (left_at = now, role kept). False when the row is not active or is the owner
    (e.g. it was made owner meanwhile): the owner can never become former this way."""
    return await execute(update(fm).where(
        fm.c.id == member_id, fm.c.status == "active", or_(fm.c.role.is_(None), fm.c.role != "owner"))
        .values(status="former", left_at=now)) == 1


async def demote_owner(member_id: str) -> bool:
    """The active owner -> admin; False when the row isn't the active owner any more."""
    return await execute(update(fm).where(fm.c.id == member_id, fm.c.role == "owner", fm.c.status == "active")
                         .values(role="admin")) == 1


async def make_owner(member_id: str) -> bool:
    """An active account member -> owner; False when it isn't one any more."""
    return await execute(update(fm).where(fm.c.id == member_id, fm.c.kind == "account", fm.c.status == "active")
                         .values(role="owner")) == 1


async def claim_member(member_id: str, user_id: str, now: datetime) -> bool:
    """A placeholder or former member row becomes the person's active account member (role member; id, name and tags
    kept). False when the row is gone or is an active account member now."""
    return await execute(update(fm).where(
        fm.c.id == member_id, or_(fm.c.kind == "placeholder", fm.c.status == "former"))
        .values(kind="account", user_id=user_id, role="member", status="active", joined_at=now, left_at=None)) == 1


async def delete_member(member_id: str) -> int:
    return await execute(delete(fm).where(fm.c.id == member_id))


async def has_tags(member_id: str) -> bool:
    """True when some entry was tagged as being for this member."""
    return bool(await fetch_value(select(exists().where(tb.c.member_id == member_id))))


# ---- who entries were for (transaction_beneficiaries) ----

async def set_beneficiaries(transaction_id: str, member_ids: List[str]) -> None:
    """Replace who the entry was for (no rows = Whole family). Call inside transaction() with the entry's own write."""
    await execute(delete(tb).where(tb.c.transaction_id == transaction_id))
    if member_ids:
        await execute(insert(tb).values([{"transaction_id": transaction_id, "member_id": m} for m in member_ids]))


async def beneficiaries_for(transaction_ids: List[str]) -> Dict[str, List[str]]:
    """{transaction_id: [member_id, ...]} in one query, members in join order; entries with none are left out
    (Whole family)."""
    if not transaction_ids:
        return {}
    rows = await fetch_all(select(tb.c.transaction_id, tb.c.member_id)
                           .select_from(tb.join(fm, fm.c.id == tb.c.member_id))
                           .where(tb.c.transaction_id.in_(list(transaction_ids)))
                           .order_by(tb.c.transaction_id, fm.c.joined_at, fm.c.id))
    out: Dict[str, List[str]] = {}
    for r in rows:
        out.setdefault(r["transaction_id"], []).append(r["member_id"])
    return out


async def outflow_shares(book_user_id: str, currency: str, date_from: datetime, date_to: datetime) -> List[Dict[str, Any]]:
    """The book's outflows in `currency` dated within [date_from, date_to], transfers left out: one row per
    (entry, member it was for) with `id`, `amount` and `member_id` (None for a Whole-family entry). An entry's members
    come in the family's join order (stable: the breakdown gives an entry's leftover to its first member)."""
    stmt = (select(t.c.id, t.c.amount, tb.c.member_id)
            .select_from(t.outerjoin(tb, tb.c.transaction_id == t.c.id).outerjoin(fm, fm.c.id == tb.c.member_id))
            .where(t.c.user_id == book_user_id, t.c.type == "outflow", t.c.currency == currency,
                   t.c.transfer_id.is_(None), t.c.date >= date_from, t.c.date <= date_to)
            .order_by(t.c.id, fm.c.joined_at, fm.c.id))
    return await fetch_all(stmt)


async def transfer_totals(book_user_id: str, date_from: datetime, date_to: datetime) -> List[Dict[str, Any]]:
    """The family book's transfer legs dated within [date_from, date_to], summed per mover, direction and currency:
    `member_id` (the leg's added_by_member_id, the member who moved it), `type` (inflow: into the family wallet;
    outflow: out of it), `currency` and `total`. Only the family's own legs: nobody's personal book is read."""
    stmt = (select(t.c.added_by_member_id.label("member_id"), t.c.type, t.c.currency,
                   func.sum(t.c.amount).label("total"))
            .select_from(t.outerjoin(fm, fm.c.id == t.c.added_by_member_id))
            .where(t.c.user_id == book_user_id, t.c.transfer_id.isnot(None), t.c.date >= date_from,
                   t.c.date <= date_to)
            .group_by(t.c.added_by_member_id, fm.c.joined_at, t.c.type, t.c.currency)
            .order_by(fm.c.joined_at.nulls_last(), t.c.added_by_member_id, t.c.type, t.c.currency))
    return [{**r, "total": float(r["total"])} for r in await fetch_all(stmt)]


# ---- invites ----

async def expire_due(now: datetime, *, family_id: Optional[str] = None, email: Optional[str] = None,
                     invite_id: Optional[str] = None) -> None:
    """Mark pending invites whose expires_at has passed as expired (lazily, on read), limited to a family, an
    e-mail (lowercased) or one invite."""
    where = [fi.c.status == "pending", fi.c.expires_at < now]
    if family_id is not None:
        where.append(fi.c.family_id == family_id)
    if email is not None:
        where.append(fi.c.email == email)
    if invite_id is not None:
        where.append(fi.c.id == invite_id)
    await execute(update(fi).where(and_(*where)).values(status="expired"))


async def insert_invite(invite_id: str, family_id: str, email: str, invited_by_member_id: str,
                        link_member_id: Optional[str], expires_at: datetime) -> Dict[str, Any]:
    return await write_returning(insert(fi).values(
        id=invite_id, family_id=family_id, email=email, invited_by_member_id=invited_by_member_id,
        link_member_id=link_member_id, status="pending", expires_at=expires_at).returning(*fi.c))


async def get_invite(invite_id: str) -> Optional[Dict[str, Any]]:
    return await fetch_one(select(fi).where(fi.c.id == invite_id))


async def pending_invite_for(family_id: str, email: str) -> Optional[Dict[str, Any]]:
    return await fetch_one(select(fi).where(fi.c.family_id == family_id, fi.c.email == email, fi.c.status == "pending"))


async def list_pending_invites(family_id: str, now: datetime) -> List[Dict[str, Any]]:
    return await fetch_all(select(fi).where(fi.c.family_id == family_id, fi.c.status == "pending", fi.c.expires_at > now)
                           .order_by(fi.c.created_at, fi.c.id))


async def count_pending_invites(family_id: str, now: datetime) -> int:
    return int(await fetch_value(select(func.count()).select_from(fi).where(
        fi.c.family_id == family_id, fi.c.status == "pending", fi.c.expires_at > now)))


async def invites_for_email(email: str, now: datetime) -> List[Dict[str, Any]]:
    """Pending, unexpired invites to this (lowercased) e-mail, newest first, with the family name and the inviter's
    display name."""
    inviter = fm.alias("inviter")
    stmt = (select(fi, f.c.name.label("family_name"), inviter.c.display_name.label("invited_by"))
            .select_from(fi.join(f, f.c.id == fi.c.family_id)
                         .outerjoin(inviter, inviter.c.id == fi.c.invited_by_member_id))
            .where(fi.c.email == email, fi.c.status == "pending", fi.c.expires_at > now)
            .order_by(fi.c.created_at.desc(), fi.c.id))
    return await fetch_all(stmt)


async def set_invite_status(invite_id: str, status: str, *, now: Optional[datetime] = None) -> bool:
    """Move a pending invite (unexpired, when `now` is given) to `status`; False when it wasn't pending."""
    where = [fi.c.id == invite_id, fi.c.status == "pending"]
    if now is not None:
        where.append(fi.c.expires_at > now)
    return await execute(update(fi).where(and_(*where)).values(status=status)) == 1
