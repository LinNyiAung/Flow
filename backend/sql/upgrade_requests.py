"""Upgrade requests: users ask for Plus or Pro from the app, the owner handles them in the admin panel."""
import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional, Sequence

from sqlalchemy import func, select, text, update
from sqlalchemy.dialects.postgresql import insert as pg_insert

from sql.db import fetch_all, fetch_one, fetch_value, write_returning
from sql.docs import row_to_doc, rows_to_docs
from sql.tables import upgrade_requests, users

_ur = upgrade_requests.c
STATUSES = ("pending", "done", "dismissed")


async def upsert_pending(user_id: str, plan: str, note: Optional[str], now: datetime) -> Dict[str, Any]:
    """The user's pending request: created, or (when one is pending already) its plan, note and date replaced.

    One conditional upsert on the partial unique index (one pending row per user), so two taps at once never
    make two rows. Returns the row.
    """
    stmt = pg_insert(upgrade_requests).values(id=str(uuid.uuid4()), user_id=user_id, plan=plan, note=note,
                                              status="pending", created_at=now)
    stmt = stmt.on_conflict_do_update(
        # The predicate must be a literal (not a bind parameter) for Postgres to match it to the partial index.
        index_elements=[_ur.user_id], index_where=text("status = 'pending'"),
        set_={"plan": stmt.excluded.plan, "note": stmt.excluded.note, "created_at": stmt.excluded.created_at}
    ).returning(*upgrade_requests.c)
    return row_to_doc(await write_returning(stmt))


async def get_pending(user_id: str) -> Optional[Dict[str, Any]]:
    return row_to_doc(await fetch_one(
        select(upgrade_requests).where(_ur.user_id == user_id, _ur.status == "pending")))


async def get(request_id: str) -> Optional[Dict[str, Any]]:
    return row_to_doc(await fetch_one(select(upgrade_requests).where(_ur.id == request_id)))


async def list_with_users(status: str, skip: int, limit: int) -> List[Dict[str, Any]]:
    """Requests in `status`, newest first (pending: oldest first, the order to work through them), each with the
    requesting user's name, email and stored plan fields."""
    order = _ur.created_at.asc() if status == "pending" else func.coalesce(_ur.handled_at, _ur.created_at).desc()
    stmt = (select(upgrade_requests, users.c.name.label("user_name"), users.c.email.label("user_email"),
                   users.c.subscription_type, users.c.subscription_expires_at, users.c.trial_ends_at)
            .join(users, users.c.id == _ur.user_id)
            .where(_ur.status == status)
            .order_by(order, _ur.id).offset(skip).limit(limit))
    return rows_to_docs(await fetch_all(stmt))


async def count_pending() -> int:
    return await fetch_value(select(func.count()).select_from(upgrade_requests).where(_ur.status == "pending")) or 0


async def mark(request_id: str, status: str, admin_id: str, now: datetime) -> Optional[Dict[str, Any]]:
    """pending -> done / dismissed; None when the request is not pending (any more)."""
    stmt = (update(upgrade_requests).where(_ur.id == request_id, _ur.status == "pending")
            .values(status=status, handled_at=now, handled_by=admin_id).returning(*upgrade_requests.c))
    return row_to_doc(await write_returning(stmt))


async def mark_user_done_if_covered(user_id: str, covered_plans: Sequence[str], admin_id: str,
                                    now: datetime) -> Optional[Dict[str, Any]]:
    """The user's pending request -> done, but only when it asks for one of `covered_plans` (the plans the user's new
    plan includes). One conditional UPDATE, so a request that changed to a higher plan in the meantime stays pending.
    Returns the row, or None when nothing changed."""
    stmt = (update(upgrade_requests)
            .where(_ur.user_id == user_id, _ur.status == "pending", _ur.plan.in_(list(covered_plans)))
            .values(status="done", handled_at=now, handled_by=admin_id).returning(*upgrade_requests.c))
    return row_to_doc(await write_returning(stmt))
