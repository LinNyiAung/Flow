"""The family rules: who may do what to a family, its members and its invitations (spec: docs/superpowers/specs/
2026-11-13-family-book-design.md, "People and roles", "Invitations", "Leaving and removal", "Plans").

- One active family per person. Creating one needs Plus or Pro (effective_plan); joining is free.
- Roles: owner (exactly one; makes admins, hands over ownership, deletes the family), admin (invites, removes, adds and
  renames placeholders, renames the family), member.
- Read-only: when the owner's effective plan isn't Plus or Pro (family_is_read_only), inviting, joining and adding
  placeholders answer family_read_only; leaving, removing, renaming, roles, handing over ownership, cancelling invites
  and deleting still work, so the family can be repaired.
- Limits are the owner's paid plan's (plans.store.family_limits): active account members plus pending, unexpired
  invites stay <= max_members; active placeholders <= max_placeholders. Counted changes lock the family row first.
- Nobody's history is rewritten: a removed or leaving account member becomes `former` (role kept), a placeholder with
  tagged entries becomes former, one without is deleted. Accepting an invite linked to a placeholder or former member,
  or re-joining after leaving, reuses that member row (same id), so its tags carry over.
- Invites expire after INVITE_DAYS; expiry is applied lazily whenever invites are read.

Refusals are HTTPException(status, {"code", "message"}); the message is in the caller's language (the texts are the
family_<code>_msg keys of notification_service.NOTIFICATION_TRANSLATIONS).
"""
import logging
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any, Dict, Mapping, Optional, Tuple

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError

import notification_service
from notification_service import translate
from plans import store
from plans.access import effective_plan, user_language
from plans.catalog import PAID_PLANS
from sql import families as fdb
from sql import users as users_db
from sql.db import transaction

logger = logging.getLogger(__name__)

INVITE_DAYS = 14
STATUS = {
    "no_family": 404,
    "not_found": 404,
    "already_in_family": 409,
    "family_full": 409,
    "placeholders_full": 409,
    "owner_must_hand_over": 409,
    "not_allowed": 403,
    "plan_required": 403,
    "family_read_only": 403,
    "invite_invalid": 400,
    "confirm_mismatch": 400,
}


def _fail(user: Mapping[str, Any], code: str):
    raise HTTPException(status_code=STATUS[code],
                        detail={"code": code, "message": translate(f"family_{code}_msg", user_language(user))})


def _now() -> datetime:
    return datetime.now(UTC)


def _iso(value: Optional[datetime]) -> Optional[str]:
    return value.isoformat() if value is not None else None


def _email(user: Mapping[str, Any]) -> str:
    return (user.get("email") or "").strip().lower()


# ---- reading ----

async def owner_plan(family_id: str) -> str:
    """The effective plan of the family's owner ("free" when the owner's account is gone)."""
    row = await fdb.owner(family_id)
    if not row or row.get("user_subscription_type") is None:
        return "free"
    return effective_plan({"subscription_type": row["user_subscription_type"],
                           "subscription_expires_at": row["user_subscription_expires_at"]})


async def family_is_read_only(family: Mapping[str, Any]) -> bool:
    """True when the owner's effective plan isn't Plus or Pro (lapsed, or the owner's account is gone).

    A read-only family can be read and repaired (leave, remove, rename, roles, hand over ownership, cancel invites,
    delete) but nothing can be added to it (invites, joining, placeholders; Task 4: money writes)."""
    return _read_only_plan(await owner_plan(family["id"]))


def _read_only_plan(plan: str) -> bool:
    return plan not in PAID_PLANS


async def _writable_limits(user: Mapping[str, Any], family_id: str) -> Tuple[int, int]:
    """The owner's (max_members, max_placeholders); family_read_only when the owner's plan isn't paid (the limits
    are only used on a paid plan)."""
    plan = await owner_plan(family_id)
    if _read_only_plan(plan):
        _fail(user, "family_read_only")
    return store.family_limits(plan)


async def _context(user: Mapping[str, Any]) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    """(the caller's active member row, their family); no_family when they have none."""
    me = await fdb.active_membership(user["_id"])
    family = await fdb.get_family(me["family_id"]) if me else None
    if me is None or family is None:
        _fail(user, "no_family")
    return me, family


def _is_admin(me: Mapping[str, Any]) -> bool:
    return me.get("role") in fdb.ADMIN_ROLES


def _require_admin(user, me) -> None:
    if not _is_admin(me):
        _fail(user, "not_allowed")


def _require_owner(user, me) -> None:
    if me.get("role") != "owner":
        _fail(user, "not_allowed")


def _member_json(m: Mapping[str, Any], me: Mapping[str, Any]) -> Dict[str, Any]:
    return {"id": m["id"], "display_name": m["display_name"], "kind": m["kind"], "role": m["role"],
            "status": m["status"], "is_me": m["id"] == me["id"]}


def _invite_json(i: Mapping[str, Any]) -> Dict[str, Any]:
    return {"id": i["id"], "email": i["email"], "link_member_id": i["link_member_id"], "status": i["status"],
            "created_at": _iso(i["created_at"]), "expires_at": _iso(i["expires_at"])}


async def overview(user: Mapping[str, Any]) -> Dict[str, Any]:
    """GET /api/family: {"family": null} outside a family; otherwise the family, the caller's member id and role,
    every member (active and former), the pending invites (admins only; [] for members) and the owner's limits."""
    me = await fdb.active_membership(user["_id"])
    family = await fdb.get_family(me["family_id"]) if me else None
    if me is None or family is None:
        return {"family": None}
    now = _now()
    await fdb.expire_due(now, family_id=family["id"])
    plan = await owner_plan(family["id"])
    max_members, max_placeholders = store.family_limits(plan)
    members = await fdb.list_members(family["id"])
    invites = await fdb.list_pending_invites(family["id"], now) if _is_admin(me) else []
    return {
        "family": {"id": family["id"], "name": family["name"], "read_only": _read_only_plan(plan)},
        "me": {"member_id": me["id"], "role": me["role"]},
        "members": [_member_json(m, me) for m in members],
        "invites": [_invite_json(i) for i in invites],
        "limits": {"max_members": max_members, "max_placeholders": max_placeholders},
    }


# ---- the family ----

async def create_family(user: Mapping[str, Any], name: str) -> Dict[str, Any]:
    """The family, its hidden book user and the caller as owner, in one transaction."""
    if effective_plan(user) not in PAID_PLANS:
        _fail(user, "plan_required")
    if await fdb.active_membership(user["_id"]):
        _fail(user, "already_in_family")
    family_id = str(uuid.uuid4())
    try:
        async with transaction():
            book_id = await users_db.create_book_user(family_id)
            await fdb.insert_family(family_id, name, book_id)
            await fdb.insert_member(str(uuid.uuid4()), family_id, user.get("name") or _email(user), "account", "owner",
                                    user["_id"])
    except IntegrityError:  # a concurrent create or join won the one-family-per-person index
        _fail(user, "already_in_family")
    return await overview(user)


async def rename_family(user: Mapping[str, Any], name: str) -> Dict[str, Any]:
    me, family = await _context(user)
    _require_admin(user, me)
    await fdb.rename_family(family["id"], name)
    return await overview(user)


async def delete_family(user: Mapping[str, Any], confirm_name: str) -> Dict[str, Any]:
    """Owner only, with the family name typed exactly. Deleting the book user cascades to the family and all its data;
    personal books are untouched."""
    me, family = await _context(user)
    _require_owner(user, me)
    if (confirm_name or "").strip() != family["name"].strip():
        _fail(user, "confirm_mismatch")
    await users_db.delete_user(family["book_user_id"])
    return {"family": None}


# ---- members ----

async def add_placeholder(user: Mapping[str, Any], display_name: str) -> Dict[str, Any]:
    me, family = await _context(user)
    _require_admin(user, me)
    async with transaction():
        await fdb.lock_family(family["id"])
        _, max_placeholders = await _writable_limits(user, family["id"])
        if await fdb.count_active(family["id"], "placeholder") >= max_placeholders:
            _fail(user, "placeholders_full")
        await fdb.insert_member(str(uuid.uuid4()), family["id"], display_name, "placeholder", None)
    return await overview(user)


async def update_member(user: Mapping[str, Any], member_id: str, display_name: Optional[str] = None,
                        role: Optional[str] = None) -> Dict[str, Any]:
    """Admins rename anyone (former members and placeholders included); only the owner moves an active account
    member between admin and member, and never their own role."""
    me, family = await _context(user)
    target = await fdb.get_member(member_id, family["id"])
    if target is None:
        _fail(user, "not_found")
    fields: Dict[str, Any] = {}
    if display_name is not None:
        _require_admin(user, me)
        fields["display_name"] = display_name
    if role is not None:
        _require_owner(user, me)
        if target["role"] == "owner" or target["kind"] != "account" or target["status"] != "active":
            _fail(user, "not_allowed")
        fields["role"] = role
    if fields:
        await fdb.update_member(target["id"], **fields)
    return await overview(user)


async def _notify(user_id: Optional[str], kind: str, key: str, ref_id: str, ref_name: str, **values: Any) -> None:
    """One notification in the recipient's language; a failure is logged, never raised (the change is done)."""
    if not user_id:
        return
    try:
        person = await users_db.get_user(user_id)
        if not person or person.get("kind", "person") != "person":
            return
        lang = user_language(person)
        await notification_service.create_notification(
            user_id, kind, translate(f"{key}_title", lang), translate(f"{key}_msg", lang, **values),
            goal_id=ref_id, goal_name=ref_name)
    except Exception:  # noqa: BLE001
        logger.exception("Could not send the %s notification", kind)


async def remove_member(user: Mapping[str, Any], member_id: str) -> Dict[str, Any]:
    """Admins. The owner (and the caller themselves: use leave) can't be removed. An account member becomes former
    (role kept) and is notified; a placeholder becomes former when entries are tagged with it, else it is deleted."""
    me, family = await _context(user)
    _require_admin(user, me)
    target = await fdb.get_member(member_id, family["id"])
    if target is None:
        _fail(user, "not_found")
    if target["role"] == "owner" or target["id"] == me["id"]:
        _fail(user, "not_allowed")
    now = _now()
    if target["kind"] == "placeholder":
        async with transaction():
            if await fdb.has_tags(target["id"]):
                if target["status"] == "active":
                    await fdb.update_member(target["id"], status="former", left_at=now)
            else:
                await fdb.delete_member(target["id"])
    elif target["status"] == "active":
        await fdb.update_member(target["id"], status="former", left_at=now)
        await _notify(target["user_id"], "family_removed", "family_removed", family["id"], family["name"],
                      family_name=family["name"])
    return await overview(user)


async def leave(user: Mapping[str, Any]) -> Dict[str, Any]:
    me, _ = await _context(user)
    if me["role"] == "owner":
        _fail(user, "owner_must_hand_over")
    await fdb.update_member(me["id"], status="former", left_at=_now())
    return {"family": None}


async def transfer_ownership(user: Mapping[str, Any], member_id: str) -> Dict[str, Any]:
    """Owner only, to another active account member; the old owner becomes an admin."""
    me, family = await _context(user)
    _require_owner(user, me)
    async with transaction():
        await fdb.lock_family(family["id"])
        target = await fdb.get_member(member_id, family["id"])
        if target is None:
            _fail(user, "not_found")
        if target["id"] == me["id"] or target["kind"] != "account" or target["status"] != "active":
            _fail(user, "not_allowed")
        await fdb.update_member(me["id"], role="admin")  # first: one active owner per family (unique index)
        await fdb.update_member(target["id"], role="owner")
    return await overview(user)


# ---- invitations ----

async def create_invite(user: Mapping[str, Any], email: str, link_member_id: Optional[str] = None) -> Dict[str, Any]:
    """Admins invite by e-mail (stored lowercased), optionally linked to a placeholder or former member of this family.
    A pending invite to the same e-mail is replaced. Active account members plus pending invites, this one
    included, must stay <= the owner's max_members (family_full). The invitee, if they have an account, is notified."""
    me, family = await _context(user)
    _require_admin(user, me)
    email = email.strip().lower()
    now = _now()
    invitee = await users_db.get_user_by_email(email)
    if invitee and invitee.get("kind", "person") != "person":
        invitee = None
    async with transaction():
        await fdb.lock_family(family["id"])
        max_members, _ = await _writable_limits(user, family["id"])
        await fdb.expire_due(now, family_id=family["id"])
        if link_member_id is not None:
            link = await fdb.get_member(link_member_id, family["id"])
            if link is None:
                _fail(user, "not_found")
            if link["kind"] != "placeholder" and link["status"] != "former":
                _fail(user, "invite_invalid")
        if invitee:
            theirs = await fdb.active_membership(invitee["_id"])
            if theirs and theirs["family_id"] == family["id"]:
                _fail(user, "already_in_family")
        existing = await fdb.pending_invite_for(family["id"], email)
        if existing:
            await fdb.set_invite_status(existing["id"], "cancelled")
        taken =await fdb.count_active(family["id"], "account") + await fdb.count_pending_invites(family["id"], now)
        if taken + 1 > max_members:
            _fail(user, "family_full")
        invite = await fdb.insert_invite(str(uuid.uuid4()), family["id"], email, me["id"], link_member_id,
                                         now + timedelta(days=INVITE_DAYS))
    if invitee:
        await _notify(invitee["_id"], "family_invite", "family_invite", invite["id"], family["name"],
                      inviter=me["display_name"], family_name=family["name"])
    return _invite_json(invite)


async def cancel_invite(user: Mapping[str, Any], invite_id: str) -> Dict[str, Any]:
    me, family = await _context(user)
    _require_admin(user, me)
    invite = await fdb.get_invite(invite_id)
    if invite is None or invite["family_id"] != family["id"]:
        _fail(user, "not_found")
    if not await fdb.set_invite_status(invite_id, "cancelled"):
        _fail(user, "invite_invalid")
    return await overview(user)


async def my_invites(user: Mapping[str, Any]) -> Dict[str, Any]:
    """The caller's pending, unexpired invites (by e-mail, case-insensitively), newest first."""
    email, now = _email(user), _now()
    await fdb.expire_due(now, email=email)
    rows = await fdb.invites_for_email(email, now)
    return {"invites": [{"id": r["id"], "family_id": r["family_id"], "family_name": r["family_name"],
                         "invited_by": r["invited_by"], "created_at": _iso(r["created_at"]),
                         "expires_at": _iso(r["expires_at"])} for r in rows]}


async def _usable_invite(user: Mapping[str, Any], invite_id: str, now: datetime) -> Dict[str, Any]:
    """The invite, if it is the caller's, pending and unexpired (expiring it first if due); else invite_invalid."""
    await fdb.expire_due(now, invite_id=invite_id)
    invite = await fdb.get_invite(invite_id)
    if (invite is None or invite["email"] != _email(user) or invite["status"] != "pending"
            or invite["expires_at"] <= now):
        _fail(user, "invite_invalid")
    return invite


async def accept_invite(user: Mapping[str, Any], invite_id: str) -> Dict[str, Any]:
    """Join the family. The member row reused, in order: the invite's linked placeholder or former member, the
    caller's own former member row in this family; otherwise a new member. Admins are notified."""
    now, uid = _now(), user["_id"]
    invite = await _usable_invite(user, invite_id, now)
    if await fdb.active_membership(uid):
        _fail(user, "already_in_family")
    family_id = invite["family_id"]
    try:
        async with transaction():
            family = await fdb.lock_family(family_id)
            if family is None:
                _fail(user, "invite_invalid")
            max_members, _ = await _writable_limits(user, family_id)  # read-only: the invite stays pending
            if not await fdb.set_invite_status(invite_id, "accepted", now=now):
                _fail(user, "invite_invalid")
            if await fdb.count_active(family_id, "account") >= max_members:
                _fail(user, "family_full")
            reuse = None
            if invite["link_member_id"]:
                link = await fdb.get_member(invite["link_member_id"], family_id)
                if link and (link["kind"] == "placeholder" or link["status"] == "former"):
                    reuse = link
            if reuse is None:
                reuse = await fdb.former_account_member(family_id, uid)
            if reuse is not None:
                await fdb.update_member(reuse["id"], kind="account", user_id=uid, role="member", status="active",
                                        joined_at=now, left_at=None)
            else:
                await fdb.insert_member(str(uuid.uuid4()), family_id, user.get("name") or _email(user), "account",
                                        "member", uid)
    except IntegrityError:  # joined another family concurrently (one active family per person)
        _fail(user, "already_in_family")
    name = user.get("name") or _email(user)
    for admin_id in await fdb.admin_user_ids(family_id):
        if admin_id != uid:
            await _notify(admin_id, "family_invite_accepted", "family_invite_accepted", family_id, family["name"],
                          name=name, family_name=family["name"])
    return await overview(user)


async def decline_invite(user: Mapping[str, Any], invite_id: str) -> Dict[str, Any]:
    now = _now()
    await _usable_invite(user, invite_id, now)
    if not await fdb.set_invite_status(invite_id, "declined", now=now):
        _fail(user, "invite_invalid")
    return {"status": "declined"}
