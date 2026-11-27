"""Daily jobs that run at a local time: each person's or each book's own clock (spec:
docs/superpowers/specs/2026-11-18-calendar-dates-design.md, "Scheduled jobs").

Two scheduler jobs (scheduler.py) call run_due_local_jobs every 15 minutes: one for DAILY_JOBS, one for INSIGHT_JOBS
(the AI calls), so a long insight run never delays the others. For every job and every subject it reads
the subject's wall clock; once the job's local time has passed today (and the date matches a weekly or monthly job's
day), it claims (job, subject, local date) in local_job_runs and runs the job's handler for that subject. The claim
makes the job run exactly once per local date, also when ticks are missed or late, when a person's zone changes during
the day (the new zone's date was already claimed, or is a new date) or a family changes owner. A handler that raises
releases its claim, so the next tick retries it; a finished run is recorded as done, and a claim a process that died
left unfinished is taken over by a later tick that day once stale (sql.local_job_runs.STALE_AFTER). Each handler's
own duplicate guards (a notice already sent, a recurring occurrence id, a rollover child, an insight for the period)
keep a retry from doing anything twice.

Subjects:
- "person": every person with a personal book, on their own zone (user_zones.user_zone); what is sent to a person.
- "book": every personal book (its person's zone) and every family book with an active owner (the owner's zone,
  user_zones.book_zone); work done once for a whole book.
"""
import asyncio
import logging
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, tzinfo
from typing import Awaitable, Callable, Dict, List, Literal, Optional, Sequence

import budget_service as bs
import insights_service as ins
import insight_schedule
import notification_service as ns
import recurring_transaction_service as rts
import tunables
from sql import local_job_runs as runs_db
from tz_utils import as_utc, local_now, utc_now, zone_for

logger = logging.getLogger(__name__)

TICK_CONCURRENCY = 5  # handlers of one job running at once (the insight jobs call the AI)
KEEP_CLAIMS_DAYS = 7  # claims of local dates this many days before the tick's UTC date are deleted

_WEEKDAYS = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")


@dataclass
class LocalJob:
    """A daily job run for each subject at `at` on the subject's clock; weekday (0 = Monday) or day (of the month)
    limit it to that day. `time_key` names the admin setting (tunables) that holds the job's time, read on every use
    (never cached); `default_at` is the time without one, and the time of a job with no `time_key`."""
    id: str
    default_at: time
    subject: Literal["person", "book"]
    handler: Callable[[str, date, tzinfo], Awaitable[None]]
    weekday: Optional[int] = None
    day: Optional[int] = None
    time_key: Optional[str] = None

    @property
    def at(self) -> time:
        """The local time the job is due from: the admin setting `time_key` now, else `default_at`."""
        return tunables.time_of(self.time_key) if self.time_key else self.default_at

    def is_due(self, wall: datetime) -> bool:
        """True when the job is due on the subject's wall clock `wall` (naive local date and time)."""
        if self.weekday is not None and wall.weekday() != self.weekday:
            return False
        if self.day is not None and wall.day != self.day:
            return False
        return wall.time() >= self.at


def _cron_job(job_id: str, insight_type: str, time_key: str, handler) -> LocalJob:
    """A book job on the day of an insight cron (insight_schedule) at the time setting `time_key`: the "Next insight"
    line reads the same day and the same setting."""
    cron = insight_schedule.cron_for(insight_type)
    weekday = _WEEKDAYS.index(cron["day_of_week"]) if "day_of_week" in cron else None
    return LocalJob(job_id, time(cron["hour"], cron["minute"]), "book", handler, weekday=weekday, day=cron.get("day"),
                    time_key=time_key)


# Times: the reminders at reminders_time (default 09:00), unusual spending at unusual_spending_time (08:00), the weekly
# insight at weekly_report_time (Monday 05:00) and the monthly one at monthly_report_time (the 1st, 06:00) are admin
# settings (tunables); budget rollovers (00:30) and recurring transactions (06:00) are fixed.
LOCAL_JOBS: List[LocalJob] = [
    LocalJob("goal_deadline_reminders", time(9, 0), "person", ns.goal_deadline_reminders_for_person,
             time_key="reminders_time"),
    LocalJob("budget_ending_reminders", time(9, 0), "person", ns.budget_ending_reminders_for_person,
             time_key="reminders_time"),
    LocalJob("payment_reminders", time(9, 0), "person", ns.payment_reminders_for_person, time_key="reminders_time"),
    LocalJob("unusual_spending", time(8, 0), "person", ns.unusual_spending_for_person, time_key="unusual_spending_time"),
    LocalJob("budget_now_active", time(9, 0), "book", ns.budget_now_active_for_book, time_key="reminders_time"),
    LocalJob("budget_rollovers", time(0, 30), "book", bs.budget_rollovers_for_book),
    LocalJob("recurring_transactions", time(6, 0), "book", rts.recurring_for_book),
    _cron_job("weekly_insights", "weekly", "weekly_report_time", ins.weekly_insight_for_book),
    _cron_job("monthly_insights", "monthly", "monthly_report_time", ins.monthly_insight_for_book),
]

# The insight jobs call the AI and can run for minutes, so they have a tick of their own (scheduler.py): a slow insight
# run never holds back a reminder, a rollover or a recurring transaction.
INSIGHT_JOB_IDS = frozenset({"weekly_insights", "monthly_insights"})
INSIGHT_JOBS: List[LocalJob] = [job for job in LOCAL_JOBS if job.id in INSIGHT_JOB_IDS]
DAILY_JOBS: List[LocalJob] = [job for job in LOCAL_JOBS if job.id not in INSIGHT_JOB_IDS]


async def _run(job: LocalJob, subject_id: str, today: date, tz: tzinfo, slots: asyncio.Semaphore) -> int:
    """Claim the job's day for the subject and run it: 1 when it ran (the claim is then recorded as done), 0 when it
    was claimed already or failed (a failure is logged and its claim released, so the next tick runs it again). A
    claim that raises (a database error) is logged and runs nothing; nothing is released, and the next tick tries the
    claim again. A claim left unfinished by a process that died is taken over once stale (runs_db.STALE_AFTER)."""
    async with slots:
        try:
            claimed = await runs_db.claim(job.id, subject_id, today)
        except Exception:  # noqa: BLE001 - one subject's failure must not stop the others
            logger.exception(f"Could not claim local job {job.id} for {subject_id} on {today}; the next tick tries again")
            return 0
        if not claimed:
            return 0
        try:
            await job.handler(subject_id, today, tz)
        except Exception:  # noqa: BLE001 - one subject's failure must not stop the others
            logger.exception(f"Local job {job.id} failed for {subject_id} on {today}; the next tick retries it")
            try:
                await runs_db.release(job.id, subject_id, today)
            except Exception:  # noqa: BLE001
                logger.exception(f"Could not release the claim of {job.id} for {subject_id} on {today}")
            return 0
        try:
            await runs_db.finish(job.id, subject_id, today)
        except Exception:  # noqa: BLE001 - it ran: at worst a stale claim is taken over later (guards stop repeats)
            logger.exception(f"Could not record {job.id} for {subject_id} on {today} as done")
        return 1


async def run_due_local_jobs(now: Optional[datetime] = None, jobs: Optional[Sequence[LocalJob]] = None) -> Dict[str, int]:
    """The tick: run every job (of `jobs`, default all of LOCAL_JOBS) for every subject whose local time for it has
    passed today and whose local date it hasn't run for yet. `now`: the instant of the tick (default: now). Returns how
    many runs each job made (by job id). Earlier local times run first (a catch-up tick rolls budgets over before it
    announces them)."""
    now = as_utc(now) if now is not None else utc_now()
    jobs = LOCAL_JOBS if jobs is None else list(jobs)
    needed = {job.subject for job in jobs}
    subjects = {
        "person": await runs_db.person_subjects() if "person" in needed else [],
        "book": await runs_db.book_subjects() if "book" in needed else [],
    }
    # Every subject's local date is the UTC date, the day before or the day after.
    claimed = await runs_db.claimed_since(now.date() - timedelta(days=1))
    zones: Dict[Optional[str], tzinfo] = {}
    slots = asyncio.Semaphore(TICK_CONCURRENCY)
    counts = {job.id: 0 for job in jobs}
    for job in sorted(jobs, key=lambda j: j.at):
        due = []
        for subject_id, zone_name in subjects[job.subject]:
            if zone_name not in zones:
                zones[zone_name] = zone_for(zone_name)
            tz = zones[zone_name]
            wall = local_now(tz, now)
            if job.is_due(wall) and (job.id, subject_id, wall.date()) not in claimed:
                due.append(_run(job, subject_id, wall.date(), tz, slots))
        counts[job.id] = sum(await asyncio.gather(*due))
    try:
        await runs_db.forget_before(now.date() - timedelta(days=KEEP_CLAIMS_DAYS))
    except Exception:  # noqa: BLE001 - old claims are only clutter
        logger.exception("Could not delete old local job claims")
    return counts
