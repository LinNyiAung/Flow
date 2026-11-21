"""The local-time jobs' day claims (local_job_runs) and their subjects (local_jobs).

A job runs for a subject (a person or a book) at most once per local date: the tick claims (job, subject_id,
local_date) before it runs the job, records done_at when the run finishes, and releases the claim when the run fails,
so the next tick retries it. A claim never finished and older than STALE_AFTER was left by a process that died
mid-run: a later tick that day claims it again (each job's own duplicate guards make a re-run safe).
"""
from datetime import date, timedelta
from typing import List, Optional, Set, Tuple

from sqlalchemy import and_, delete, func, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert

from sql.db import execute, fetch_all
from sql.tables import books, family_members as fm, local_job_runs as r, users

# An unfinished claim this old is taken as left by a dead process. Longer than any run (an insight's AI call takes
# minutes); a tick group runs one tick at a time, so a live run is never older than its own tick.
STALE_AFTER = timedelta(minutes=30)


def _key(job: str, subject_id: str, local_date: date):
    return and_(r.c.job == job, r.c.subject_id == subject_id, r.c.local_date == local_date)


def _stale():
    return and_(r.c.done_at.is_(None), r.c.claimed_at < func.now() - STALE_AFTER)


async def claim(job: str, subject_id: str, local_date: date) -> bool:
    """Claim the job's run for the subject on its local date; True if this call claimed it: it wasn't claimed yet, or
    its claim was left unfinished for longer than STALE_AFTER (taken over, claimed_at reset)."""
    stmt = (pg_insert(r).values(job=job, subject_id=subject_id, local_date=local_date)
            .on_conflict_do_nothing(index_elements=[r.c.job, r.c.subject_id, r.c.local_date]))
    if await execute(stmt) > 0:
        return True
    retake = update(r).where(_key(job, subject_id, local_date), _stale()).values(claimed_at=func.now())
    return await execute(retake) > 0


async def finish(job: str, subject_id: str, local_date: date) -> None:
    """The claimed run finished: record done_at, so it is never taken for a dead one."""
    await execute(update(r).where(_key(job, subject_id, local_date)).values(done_at=func.now()))


async def release(job: str, subject_id: str, local_date: date) -> None:
    """Drop a claim (its run failed): the next tick claims and runs it again."""
    await execute(delete(r).where(_key(job, subject_id, local_date)))


async def claimed_since(first: date) -> Set[Tuple[str, str, date]]:
    """Every live claim (job, subject_id, local_date) on or after `first`, done or still running (a tick skips these
    without trying to claim). A stale unfinished claim is left out, so the tick tries to take it over."""
    rows = await fetch_all(select(r.c.job, r.c.subject_id, r.c.local_date)
                           .where(r.c.local_date >= first, ~_stale()))
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
