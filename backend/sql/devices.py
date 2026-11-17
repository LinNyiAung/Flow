"""The devices a person is signed in on: one row per push token (a token belongs to exactly one account).

A device gets the person's pushes while its sign-in has not expired (session_expires_at: the exp of the sign-in token
it last registered with).
"""
import uuid
from datetime import datetime, timedelta
from typing import Iterable, List, Optional

from sqlalchemy import case, delete, exists, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert

from sql.db import execute, fetch_all, fetch_value, transaction
from sql.tables import user_devices as d
from sql.tables import users

# "Push enabled": the person has at least one device row (whether or not its sign-in has expired).
HAS_DEVICE = exists().where(d.c.user_id == users.c.id)


async def register(user_id: str, token: str, previous_token: Optional[str], session_expires_at: datetime,
                   now: datetime) -> int:
    """Give this device token to user_id; returns how many other accounts lost it (0 or 1).

    - If the token is another account's, it moves to user_id (that account stops getting pushes on this device).
    - If previous_token names a row of user_id, that row takes the new token (one phone stays one row across token
      refreshes). A previous_token of another account is ignored.
    - Every registration sets last_seen_at = now and session_expires_at, and clears the sign-in reminder stamp.
    Safe when two requests race: the token is unique and the write is an upsert on it.
    """
    async with transaction():
        row_id, created_at = str(uuid.uuid4()), now
        if previous_token and previous_token != token:
            # The previous row hands its identity (id, created_at) to the new token.
            old = await fetch_all(delete(d).where(d.c.user_id == user_id, d.c.token == previous_token)
                                  .returning(d.c.id, d.c.created_at))
            if old:
                row_id, created_at = old[0]["id"], old[0]["created_at"]
        owner = await fetch_value(select(d.c.user_id).where(d.c.token == token).with_for_update())
        stmt = pg_insert(d).values(id=row_id, user_id=user_id, token=token, created_at=created_at, last_seen_at=now,
                                   session_expires_at=session_expires_at, sign_in_reminder_sent_at=None)
        stmt = stmt.on_conflict_do_update(index_elements=[d.c.token], set_={
            "user_id": stmt.excluded.user_id,
            # A token moved from another account is a new device of this one.
            "created_at": case((d.c.user_id != stmt.excluded.user_id, stmt.excluded.created_at), else_=d.c.created_at),
            "last_seen_at": stmt.excluded.last_seen_at,
            "session_expires_at": stmt.excluded.session_expires_at,
            "sign_in_reminder_sent_at": None,
        })
        await execute(stmt)
    return 1 if owner is not None and owner != user_id else 0


async def remove(user_id: str, token: str) -> bool:
    """Logout on one device: deletes the token's row only if it is user_id's. True when a row was deleted."""
    return await execute(delete(d).where(d.c.user_id == user_id, d.c.token == token)) > 0


async def remove_all(user_id: str, keep_token: Optional[str] = None) -> int:
    """Deletes every device row of user_id except the one holding keep_token (None: every row); returns the count."""
    stmt = delete(d).where(d.c.user_id == user_id)
    if keep_token:
        stmt = stmt.where(d.c.token != keep_token)
    return await execute(stmt)


async def active_tokens(user_id: str, now: datetime) -> List[str]:
    """The push tokens of user_id's devices whose sign-in has not expired at `now`."""
    return await active_tokens_for([user_id], now)


async def active_tokens_for(user_ids: Iterable[str], now: datetime) -> List[str]:
    """The push tokens of these people's devices whose sign-in has not expired at `now` (each token once)."""
    ids = list(dict.fromkeys(user_ids))
    tokens: List[str] = []
    for chunk in _chunks(ids):
        rows = await fetch_all(select(d.c.token).where(d.c.user_id.in_(chunk), d.c.session_expires_at > now)
                               .order_by(d.c.created_at, d.c.id))
        tokens += [r["token"] for r in rows]
    return tokens


async def delete_tokens(tokens: Iterable[str]) -> int:
    """Deletes the rows of these tokens (Firebase reported them unregistered); returns the count."""
    deleted = 0
    for chunk in _chunks(list(dict.fromkeys(t for t in tokens if t))):
        deleted += await execute(delete(d).where(d.c.token.in_(chunk)))
    return deleted


async def claim_sign_in_reminders(now: datetime) -> List[dict]:
    """Claims the sign-in reminders due at `now`: the devices whose sign-in has expired and that have not been
    reminded. Each is stamped in the same statement that returns it, so two runs never claim the same device (a crash
    after the claim loses that reminder rather than sending it twice). Returns {token, user_id, language} rows;
    language is the person's, "en" when they have none.
    """
    stmt = (update(d).values(sign_in_reminder_sent_at=now)
            .where(d.c.user_id == users.c.id, d.c.session_expires_at <= now, d.c.sign_in_reminder_sent_at.is_(None))
            .returning(d.c.token, d.c.user_id, users.c.language))
    async with transaction():
        rows = await fetch_all(stmt)
    return [{"token": r["token"], "user_id": r["user_id"], "language": r["language"] or "en"} for r in rows]


async def delete_stale(now: datetime, days: int = 60) -> int:
    """Deletes the devices not seen for more than `days` days; returns the count."""
    return await execute(delete(d).where(d.c.last_seen_at < now - timedelta(days=days)))


_CHUNK = 5000  # ids per IN list (a statement takes at most 32767 parameters)


def _chunks(values: List[str]):
    for start in range(0, len(values), _CHUNK):
        yield values[start:start + _CHUNK]
