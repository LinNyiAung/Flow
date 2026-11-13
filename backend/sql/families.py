"""Families, their members and invitations, and who family entries were for (families, family_members,
family_invites, transaction_beneficiaries). Plain Core queries; the rules live in families.service.

Rows come back as plain dicts with `id` (not `_id`). Every helper joins the caller's transaction() when inside one.
"""
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import and_, delete, exists, func, insert, select, update

from sql.db import execute, fetch_all, fetch_one, fetch_value, write_returning
from sql.tables import families as f, family_invites as fi, family_members as fm, transaction_beneficiaries as tb, users

ADMIN_ROLES = ("owner", "admin")


# ---- families ----

async def insert_family(family_id: str, name: str, book_user_id: str) -> None:
    await execute(insert(f).values(id=family_id, name=name, book_user_id=book_user_id))


async def get_family(family_id: str) -> Optional[Dict[str, Any]]:
    return await fetch_one(select(f).where(f.c.id == family_id))


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


async def count_active(family_id: str, kind: str) -> int:
    return int(await fetch_value(select(func.count()).select_from(fm).where(
        fm.c.family_id == family_id, fm.c.kind == kind, fm.c.status == "active")))


async def update_member(member_id: str, **fields: Any) -> int:
    return await execute(update(fm).where(fm.c.id == member_id).values(**fields))


async def delete_member(member_id: str) -> int:
    return await execute(delete(fm).where(fm.c.id == member_id))


async def has_tags(member_id: str) -> bool:
    """True when some entry was tagged as being for this member."""
    return bool(await fetch_value(select(exists().where(tb.c.member_id == member_id))))


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
