"""PostgreSQL connection and query helpers (SQLAlchemy Core on asyncpg).

Usage:
    row = await fetch_one(select(users).where(users.c.id == uid))
    rows = await fetch_all(select(transactions).where(...))
    n = await execute(update(goals).where(...).values(...))   # returns rowcount
    async with transaction() as conn:                         # all-or-nothing
        await conn.execute(...)

Inside `transaction()` every helper call (in any sql module) without an explicit `conn`
joins that transaction, so a block of ordinary calls is all-or-nothing and sees its own
writes (used by the per-user money lock). Nested `transaction()` blocks become savepoints.
Don't run queries concurrently (asyncio.gather) inside a transaction: it is one connection.

Rows come back as plain dicts (column -> value); sql.docs converts them to the
document shapes the rest of the backend already uses.
"""
import os
from contextlib import asynccontextmanager
from contextvars import ContextVar
from typing import Any, AsyncIterator, Dict, List, Optional

from sqlalchemy.ext.asyncio import AsyncConnection, AsyncEngine, create_async_engine


def _async_url(url: str) -> str:
    """Accept Render/Heroku style postgres:// URLs and force the asyncpg driver."""
    if url.startswith("postgres://"):
        url = "postgresql://" + url[len("postgres://"):]
    if url.startswith("postgresql://"):
        url = "postgresql+asyncpg://" + url[len("postgresql://"):]
    return url


_engine: Optional[AsyncEngine] = None
# The connection of the transaction() block the current task is in, if any.
_current: ContextVar[Optional[AsyncConnection]] = ContextVar("sql_current_transaction", default=None)


def get_engine() -> AsyncEngine:
    global _engine
    if _engine is None:
        url = os.getenv("DATABASE_URL")
        if not url:
            raise RuntimeError("DATABASE_URL is not set")
        _engine = create_async_engine(
            _async_url(url),
            pool_size=int(os.getenv("DB_POOL_SIZE", "10")),
            max_overflow=int(os.getenv("DB_MAX_OVERFLOW", "10")),
            pool_pre_ping=True,   # survive Render restarts / idle disconnects
            pool_recycle=1800,
        )
    return _engine


async def dispose_engine() -> None:
    global _engine
    if _engine is not None:
        await _engine.dispose()
        _engine = None


def _as_dict(row) -> Dict[str, Any]:
    return dict(row._mapping)


async def fetch_one(stmt, conn: Optional[AsyncConnection] = None) -> Optional[Dict[str, Any]]:
    conn = conn or _current.get()
    if conn is not None:
        row = (await conn.execute(stmt)).first()
        return _as_dict(row) if row is not None else None
    async with get_engine().connect() as c:
        row = (await c.execute(stmt)).first()
        return _as_dict(row) if row is not None else None


async def fetch_all(stmt, conn: Optional[AsyncConnection] = None) -> List[Dict[str, Any]]:
    conn = conn or _current.get()
    if conn is not None:
        return [_as_dict(r) for r in (await conn.execute(stmt)).all()]
    async with get_engine().connect() as c:
        return [_as_dict(r) for r in (await c.execute(stmt)).all()]


async def fetch_value(stmt, conn: Optional[AsyncConnection] = None) -> Any:
    conn = conn or _current.get()
    if conn is not None:
        return (await conn.execute(stmt)).scalar()
    async with get_engine().connect() as c:
        return (await c.execute(stmt)).scalar()


async def execute(stmt, conn: Optional[AsyncConnection] = None) -> int:
    """Run a write in its own transaction (or the given one); returns the affected row count."""
    conn = conn or _current.get()
    if conn is not None:
        return (await conn.execute(stmt)).rowcount
    async with get_engine().begin() as c:
        return (await c.execute(stmt)).rowcount


async def write_returning(stmt, conn: Optional[AsyncConnection] = None) -> Optional[Dict[str, Any]]:
    """Run an INSERT/UPDATE/DELETE ... RETURNING and return the first row (or None)."""
    conn = conn or _current.get()
    if conn is not None:
        row = (await conn.execute(stmt)).first()
        return _as_dict(row) if row is not None else None
    async with get_engine().begin() as c:
        row = (await c.execute(stmt)).first()
        return _as_dict(row) if row is not None else None


@asynccontextmanager
async def transaction() -> AsyncIterator[AsyncConnection]:
    """All-or-nothing unit of work: commits on success, rolls back on any exception.
    Inside an outer transaction() it is a savepoint of that transaction."""
    outer = _current.get()
    if outer is not None:
        async with outer.begin_nested():
            yield outer
        return
    async with get_engine().begin() as conn:
        token = _current.set(conn)
        try:
            yield conn
        finally:
            _current.reset(token)
