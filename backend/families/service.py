"""The family rules: who may do what to a family, its members and its invitations (spec: docs/superpowers/specs/
2026-11-13-family-book-design.md, "People and roles", "Invitations", "Leaving and removal", "Plans").

- One active family per person. Creating one needs Plus or Pro (effective_plan); joining is free.
- Roles: owner (exactly one; makes and removes admins, hands over ownership, deletes the family), admin (invites;
  removes members and placeholders but not other admins; adds placeholders; renames placeholders and former members,
  never an active account member; renames the family), member.
- Member-changing writes lock the family row and re-read the rows they act on, with guarded UPDATEs, so concurrent
  handovers, leaves and removals can never leave a family with no active owner (or a former owner).
- An invite may take over a placeholder, or a former account row whose account is gone or is the invitee's own.
- Read-only: when the owner's effective plan isn't Plus or Pro (family_is_read_only), inviting, joining and adding
  placeholders answer family_read_only; leaving, removing, renaming, roles, handing over ownership, cancelling invites
  and deleting still work, so the family can be repaired.
- Limits are the owner's paid plan's (plans.store.family_limits): active account members plus pending, unexpired
  invites stay <= max_members; active placeholders <= max_placeholders. Counted changes lock the family row first.
- Nobody's history is rewritten: a removed or leaving account member becomes `former` (role kept), a placeholder with
  tagged entries becomes former, one without is deleted. Accepting an invite linked to a placeholder or former member,
  or re-joining after leaving, reuses that member row (same id), so its tags carry over.
- Invites expire after INVITE_DAYS; expiry is applied lazily whenever invites are read.
- Deleting an account (before_account_delete, in the deletion's own transaction): a member becomes former; an owner
  hands the family to the longest-standing admin, else account member; an owner left alone takes the family along.

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
from sql import books as books_db
from sql import goal_entries as goal_entries_db
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


def _own_name(user: Mapping[str, Any]) -> str:
    """An account member's display name: the person's profile name, else their e-mail (never blank)."""
    return (user.get("name") or "").strip() or _email(user)


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


async def family_of(user: Mapping[str, Any]) -> Dict[str, Any]:
    """The family the caller is an active member of; 404 no_family when none."""
    return (await _context(user))[1]


async def _lock_and_reread(user: Mapping[str, Any], family_id: str) -> Dict[str, Any]:
    """Inside transaction(): lock the family row, then re-read the caller's member row (rows read before the lock
    may be stale: a concurrent handover, leave or removal). no_family when they are no longer in this family."""
    await fdb.lock_family(family_id)
    me = await fdb.active_membership(user["_id"])
    if me is None or me["family_id"] != family_id:
        _fail(user, "no_family")
    return me


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
    """The family, its family book and the caller as owner, in one transaction."""
    if effective_plan(user) not in PAID_PLANS:
        _fail(user, "plan_required")
    if await fdb.active_membership(user["_id"]):
        _fail(user, "already_in_family")
    family_id = str(uuid.uuid4())
    try:
        async with transaction():
            await fdb.insert_family(family_id, name)
            await books_db.create_family_book(family_id)
            await fdb.insert_member(str(uuid.uuid4()), family_id, _own_name(user), "account", "owner", user["_id"])
    except IntegrityError:  # a concurrent create or join won the one-family-per-person index
        _fail(user, "already_in_family")
    return await overview(user)


async def rename_family(user: Mapping[str, Any], name: str) -> Dict[str, Any]:
    me, family = await _context(user)
    _require_admin(user, me)
    await fdb.rename_family(family["id"], name)
    return await overview(user)


async def delete_family(user: Mapping[str, Any], confirm_name: str) -> Dict[str, Any]:
    """Owner only, with the family name typed exactly. Deleting the family cascades to its book and all its data;
    personal books are untouched."""
    me, family = await _context(user)
    _require_owner(user, me)
    if (confirm_name or "").strip() != family["name"].strip():
        _fail(user, "confirm_mismatch")
    await fdb.delete_family(family["id"])
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


async def follow_profile_name(user_id: str, name: str) -> None:
    """The person changed their profile name: their name in their family follows (their active account member row;
    former rows keep the name they had, as history). A blank name is never stored."""
    name = (name or "").strip()
    if name:
        await fdb.rename_account_member(user_id, name)


async def update_member(user: Mapping[str, Any], member_id: str, display_name: Optional[str] = None,
                        role: Optional[str] = None) -> Dict[str, Any]:
    """Admins rename placeholders and former members only (an active account member's name is their own); only the
    owner moves an active account member between admin and member, and never their own role."""
    _, family = await _context(user)
    async with transaction():
        me = await _lock_and_reread(user, family["id"])
        target = await fdb.get_member(member_id, family["id"])
        if target is None:
            _fail(user, "not_found")
        fields: Dict[str, Any] = {}
        if display_name is not None:
            _require_admin(user, me)
            if target["kind"] == "account" and target["status"] == "active":
                _fail(user, "not_allowed")
            fields["display_name"] = display_name
        if role is not None:
            _require_owner(user, me)
            if target["role"] == "owner" or target["kind"] != "account" or target["status"] != "active":
                _fail(user, "not_allowed")
            fields["role"] = role
        if fields:
            await fdb.update_member(target["id"], **fields)
    return await overview(user)


async def _notify(user_id: Optional[str], kind: str, key: str, subject: Dict[str, str], ref_name: str,
                  **values: Any) -> None:
    """One notification in the recipient's language, linked to `subject` (the invite or the family, e.g.
    {"family_id": ...}); a failure is logged, never raised (the change is done)."""
    if not user_id:
        return
    try:
        person = await users_db.get_user(user_id)
        if not person:
            return
        lang = user_language(person)
        await notification_service.create_notification(
            user_id, kind, translate(f"{key}_title", lang), translate(f"{key}_msg", lang, **values),
            goal_name=ref_name, links=subject)
    except Exception:  # noqa: BLE001
        logger.exception("Could not send the %s notification", kind)


async def remove_member(user: Mapping[str, Any], member_id: str) -> Dict[str, Any]:
    """Admins remove members and placeholders; only the owner removes an admin; the owner (and the caller themselves:
    use leave) can't be removed. An account member becomes former (role kept) and is notified; a placeholder becomes
    former when entries or goal entries are tagged with it, else it is deleted. Runs under the family lock with fresh rows, so it
    can't race a handover into a former owner, or delete a placeholder an accept is claiming."""
    _, family = await _context(user)
    now = _now()
    notify_user = None
    async with transaction():
        me = await _lock_and_reread(user, family["id"])
        _require_admin(user, me)
        target = await fdb.get_member(member_id, family["id"])
        if target is None:
            _fail(user, "not_found")
        if target["role"] == "owner" or target["id"] == me["id"]:
            _fail(user, "not_allowed")
        if target["role"] == "admin" and target["status"] == "active" and me["role"] != "owner":
            _fail(user, "not_allowed")
        if target["kind"] == "placeholder":
            if not await fdb.has_tags(target["id"]) and not await goal_entries_db.member_has_entries(target["id"]):
                await fdb.delete_member(target["id"])
            elif target["status"] == "active":
                await fdb.set_former(target["id"], now)
        elif target["status"] == "active":
            if not await fdb.set_former(target["id"], now):
                _fail(user, "not_allowed")
            notify_user = target["user_id"]
    if notify_user:
        await _notify(notify_user, "family_removed", "family_removed", {"family_id": family["id"]}, family["name"],
                      family_name=family["name"])
    return await overview(user)


async def leave(user: Mapping[str, Any]) -> Dict[str, Any]:
    """Any member but the owner becomes former (role kept). Under the family lock, re-reading the caller's row."""
    _, family = await _context(user)
    async with transaction():
        me = await _lock_and_reread(user, family["id"])
        if me["role"] == "owner" or not await fdb.set_former(me["id"], _now()):
            _fail(user, "owner_must_hand_over")
    return {"family": None}


async def transfer_ownership(user: Mapping[str, Any], member_id: str) -> Dict[str, Any]:
    """Owner only, to another active account member; the old owner becomes an admin. Under the family lock with
    fresh rows and guarded updates, so concurrent handovers, leaves and removals give a coded refusal, never two
    owners or none."""
    _, family = await _context(user)
    try:
        async with transaction():
            me = await _lock_and_reread(user, family["id"])
            _require_owner(user, me)
            target = await fdb.get_member(member_id, family["id"])
            if target is None:
                _fail(user, "not_found")
            if target["id"] == me["id"] or target["kind"] != "account" or target["status"] != "active":
                _fail(user, "not_allowed")
            # Demote first: one active owner per family (unique index).
            if not await fdb.demote_owner(me["id"]) or not await fdb.make_owner(target["id"]):
                _fail(user, "not_allowed")
    except IntegrityError:
        _fail(user, "not_allowed")
    return await overview(user)


# ---- deleted accounts ----

async def before_account_delete(user_id: str) -> Optional[Dict[str, Any]]:
    """Call inside the transaction() that then deletes the account (users_db.delete_user), so both commit or neither
    (spec "Deleted accounts": nobody's history goes with them).

    - Not in a family: nothing.
    - A member or admin becomes former (left_at now; name, role and tags kept), as if they had left; deleting the user
      row then nulls the member's user_id (FK ON DELETE SET NULL), so entries keep showing their name.
    - The owner: the longest-standing active admin (joined_at, then id), else the longest-standing active account
      member, becomes the owner. The old owner is demoted, made former, then the heir promoted, in that order (one
      active owner per family). The heir's plan doesn't matter: on Free the family is simply read-only. With no other
      active account member (placeholders and former members don't count), the family is deleted with its book.

    Locks the user row first (no create or join can point a new member row at it until the account is gone), then
    the family row, and re-reads the member rows under the lock. Returns the handover to announce once committed
    (announce_new_owner), or None."""
    if not await users_db.lock_user(user_id):
        return None
    me = await fdb.active_membership(user_id)
    while me is not None:
        family = await fdb.lock_family(me["family_id"])
        fresh = await fdb.active_membership(user_id)  # a concurrent leave or removal may have won the lock
        if fresh is not None and fresh["id"] == me["id"] and family is not None:
            me = fresh
            break
        me = fresh
    if me is None:
        return None
    now = _now()
    if me["role"] != "owner":
        if not await fdb.set_former(me["id"], now):
            raise RuntimeError(f"member {me['id']} could not be made former")
        return None
    others = [m for m in await fdb.list_members(family["id"])  # oldest first
              if m["id"] != me["id"] and m["kind"] == "account" and m["status"] == "active" and m["user_id"]]
    if not others:
        await fdb.delete_family(family["id"])  # cascades to its book and all its data
        logger.info("Family %s deleted with its last account member's account", family["id"])
        return None
    heir = next((m for m in others if m["role"] == "admin"), others[0])
    if not (await fdb.demote_owner(me["id"]) and await fdb.set_former(me["id"], now)
            and await fdb.make_owner(heir["id"])):
        raise RuntimeError(f"family {family['id']}: ownership could not pass to member {heir['id']}")
    logger.info("Family %s: owner's account deleted, member %s is the owner", family["id"], heir["id"])
    return {"user_id": heir["user_id"], "family_id": family["id"], "family_name": family["name"]}


async def announce_new_owner(handover: Optional[Mapping[str, Any]]) -> None:
    """After before_account_delete's transaction committed: tell the new owner (family_owner). Never raises."""
    if handover:
        await _notify(handover["user_id"], "family_owner", "family_owner", {"family_id": handover["family_id"]},
                      handover["family_name"], family_name=handover["family_name"])


# ---- invitations ----

def _linkable(link: Mapping[str, Any], invitee_id: Optional[str]) -> bool:
    """Whether an invite to `invitee_id` (None: no account yet) may take over member row `link`: any placeholder; a
    former account row only when its account is gone (user_id NULL) or is the invitee's own. Never an active
    account member."""
    if link["kind"] == "placeholder":
        return True
    return link["status"] == "former" and (link["user_id"] is None or link["user_id"] == invitee_id)


async def create_invite(user: Mapping[str, Any], email: str, link_member_id: Optional[str] = None) -> Dict[str, Any]:
    """Admins invite by e-mail (stored lowercased), optionally linked to a placeholder or former member of this family.
    A pending invite to the same e-mail is replaced. Active account members plus pending invites, this one
    included, must stay <= the owner's max_members (family_full). The invitee, if they have an account, is notified."""
    me, family = await _context(user)
    _require_admin(user, me)
    email = email.strip().lower()
    now = _now()
    invitee = await users_db.get_user_by_email(email)
    async with transaction():
        await fdb.lock_family(family["id"])
        max_members, _ = await _writable_limits(user, family["id"])
        await fdb.expire_due(now, family_id=family["id"])
        if link_member_id is not None:
            link = await fdb.get_member(link_member_id, family["id"])
            if link is None:
                _fail(user, "not_found")
            if not _linkable(link, invitee["_id"] if invitee else None):
                _fail(user, "invite_invalid")
        if invitee:
            theirs = await fdb.active_membership(invitee["_id"])
            if theirs and theirs["family_id"] == family["id"]:
                _fail(user, "already_in_family")
        existing = await fdb.pending_invite_for(family["id"], email)
        if existing:
            await fdb.set_invite_status(existing["id"], "cancelled")
        taken = await fdb.count_active(family["id"], "account") + await fdb.count_pending_invites(family["id"], now)
        if taken + 1 > max_members:
            _fail(user, "family_full")
        invite = await fdb.insert_invite(str(uuid.uuid4()), family["id"], email, me["id"], link_member_id,
                                         now + timedelta(days=INVITE_DAYS))
    if invitee:
        await _notify(invitee["_id"], "family_invite", "family_invite", {"family_invite_id": invite["id"]},
                      family["name"], inviter=me["display_name"], family_name=family["name"])
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
                if link and link["kind"] == "account" and link["status"] == "former" and not _linkable(link, uid):
                    _fail(user, "invite_invalid")  # someone else's former row: the invite stays pending
                if link and _linkable(link, uid):
                    reuse = link
            if reuse is None:
                reuse = await fdb.former_account_member(family_id, uid)
            # The family lock keeps the row as read (remove takes it too); a failed claim falls back to a new member.
            if reuse is None or not await fdb.claim_member(reuse["id"], uid, now):
                await fdb.insert_member(str(uuid.uuid4()), family_id, _own_name(user), "account", "member", uid)
    except IntegrityError:  # joined another family concurrently (one active family per person)
        _fail(user, "already_in_family")
    name = _own_name(user)
    for admin_id in await fdb.admin_user_ids(family_id):
        if admin_id != uid:
            await _notify(admin_id, "family_invite_accepted", "family_invite_accepted", {"family_id": family_id},
                          family["name"], name=name, family_name=family["name"])
    return await overview(user)


async def decline_invite(user: Mapping[str, Any], invite_id: str) -> Dict[str, Any]:
    now = _now()
    await _usable_invite(user, invite_id, now)
    if not await fdb.set_invite_status(invite_id, "declined", now=now):
        _fail(user, "invite_invalid")
    return {"status": "declined"}
