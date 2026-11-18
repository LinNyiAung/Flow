"""The local-time jobs' day claims (local_job_runs) and their subjects (local_jobs).

A job runs for a subject (a person or a book) at most once per local date: the tick claims (job, subject_id,
local_date) before it runs the job and releases the claim when the run fails, so the next tick retries it.
"""
from datetime import date
from typing import List, Optional, Set, Tuple

from sqlalchemy import and_, delete, select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from sql.db import execute, fetch_all
from sql.tables import books, family_members as fm, local_job_runs as r, users


async def claim(job: str, subject_id: str, local_date: date) -> bool:
    """Claim the job's run for the subject on its local date; True if this call claimed it (it wasn't claimed yet)."""
    stmt = (pg_insert(r).values(job=job, subject_id=subject_id, local_date=local_date)
            .on_conflict_do_nothing(index_elements=[r.c.job, r.c.subject_id, r.c.local_date]))
    return await execute(stmt) > 0


async def release(job: str, subject_id: str, local_date: date) -> None:
    """Drop a claim (its run failed): the next tick claims and runs it again."""
    await execute(delete(r).where(r.c.job == job, r.c.subject_id == subject_id, r.c.local_date == local_date))


async def claimed_since(first: date) -> Set[Tuple[str, str, date]]:
    """Every claim (job, subject_id, local_date) on or after `first` (a tick skips these without trying to claim)."""
    rows = await fetch_all(select(r.c.job, r.c.subject_id, r.c.local_date).where(r.c.local_date >= first))
    return {(row["job"], row["subject_id"], row["local_date"]) for row in rows}


async def forget_before(first: date) -> int:
    """Delete the claims of local dates before `first` (long past: no subject's today can be that date again)."""
    return await execute(delete(r).where(r.c.local_date < first))


async def person_subjects() -> List[Tuple[str, Optional[str]]]:
    """(person id, saved zone name or None) of every person with a personal book."""
    rows = await fetch_all(select(users.c.id, users.c.timezone)
                           .select_from(users.join(books, books.c.person_id == users.c.id))
                           .order_by(users.c.created_at, users.c.id))
    return [(row["id"], row["timezone"]) for row in rows]


async def book_subjects() -> List[Tuple[str, Optional[str]]]:
    """(book id, zone name of the book or None) of every personal book (its person's zone) and every family book with
    an active owner (the owner's zone, user_zones.book_zone). A family book without an active owner is left out."""
    personal = (select(books.c.id, users.c.timezone).select_from(books.join(users, users.c.id == books.c.person_id))
                .where(books.c.kind == "personal"))
    family = (select(books.c.id, users.c.timezone)
              .select_from(books.join(fm, and_(fm.c.family_id == books.c.family_id, fm.c.role == "owner",
                                               fm.c.status == "active"))
                           .join(users, users.c.id == fm.c.user_id))
              .where(books.c.kind == "family"))
    rows = await fetch_all(personal.union_all(family).order_by("id"))
    return [(row["id"], row["timezone"]) for row in rows]
