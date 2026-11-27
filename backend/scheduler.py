import logging
from datetime import timezone

from apscheduler.schedulers.asyncio import AsyncIOScheduler  # [CHANGED]
from apscheduler.triggers.cron import CronTrigger
from custom_insights_service import fail_stuck_reports
from local_jobs import DAILY_JOBS, INSIGHT_JOBS, run_due_local_jobs
from subscription_service import expire_paid_plans, send_plan_renewal_reminders, send_trial_reminders
from device_jobs import delete_stale_devices, send_sign_in_reminders
from tz_utils import default_zone

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def start_scheduler():
    """Start the async scheduler for notifications"""
    # [CHANGED] Use AsyncIOScheduler instead of BackgroundScheduler
    # This allows jobs to run on the MAIN event loop, reusing the global DB client.
    # The daily jobs that follow a person's or a book's clock (reminders, rollovers, recurring transactions, insights)
    # run from two 15-minute ticks (local_jobs). The jobs below work on instants; the one that runs at a time of day
    # keeps the default zone (SCHEDULER_TIMEZONE, default Asia/Yangon).
    app_tz = default_zone()
    scheduler = AsyncIOScheduler(timezone=app_tz)

    # --- NO WRAPPERS NEEDED ---
    # We can now pass the async functions directly to the scheduler.

    # --- ADD JOBS ---

    # The local-time jobs (local_jobs.LOCAL_JOBS: goal, budget and payment reminders, unusual spending, weekly and monthly
    # insights at the admin-set job times (defaults 09:00, 08:00, Monday 05:00, the 1st 06:00; tunables, 15-minute
    # steps), budget rollovers at 00:30, recurring transactions at 06:00), every 15 minutes
    # in UTC (every zone's offset is a multiple of 15 minutes). Each run is claimed per subject and local date, so a
    # late, missed or overlapping tick never runs one twice; one tick at a time, a missed one runs once.
    # The insight jobs call the AI and can run for minutes, so they tick on their own: a long insight run never delays
    # the reminders, rollovers and recurring transactions.
    for job_id, name, jobs in (
        ("local_jobs_tick", "Run the reminders, rollovers and recurring transactions due on each clock", DAILY_JOBS),
        ("local_insights_tick", "Run the weekly and monthly insights due on each book's clock", INSIGHT_JOBS),
    ):
        scheduler.add_job(
            run_due_local_jobs,
            trigger=CronTrigger(minute="*/15", timezone=timezone.utc),
            kwargs={"jobs": jobs},
            id=job_id,
            name=name,
            replace_existing=True,
            coalesce=True,
            misfire_grace_time=15 * 60,
            max_instances=1,
        )

    # Downgrade expired Plus/Pro plans to free and notify the user, hourly so the "plan has ended"
    # notification arrives soon after the expiry time.
    # (Paid features already stop at the exact expiry: plans.access.effective_plan checks it.)
    scheduler.add_job(
        expire_paid_plans,
        trigger=CronTrigger(timezone=app_tz, minute=5),
        id="expire_paid_plans",
        name="Downgrade expired Plus and Pro plans",
        replace_existing=True,
        misfire_grace_time=3600,
        coalesce=True,
    )

    # Remind Plus-trial users the "ends soon" number of days (an admin setting, 3 by default) before the trial ends and on its last day, hourly. Each
    # reminder is claimed in the database first, so it goes out at most once however often this runs.
    scheduler.add_job(
        send_trial_reminders,
        trigger=CronTrigger(timezone=app_tz, minute=20),
        id="send_trial_reminders",
        name="Send Plus trial reminders",
        replace_existing=True,
        misfire_grace_time=3600,
        coalesce=True,
    )

    # Remind paying Plus / Pro users whose plan has an end date, the "ends soon" number of days (admin setting) before it ends and on its last day, on the
    # same hourly schedule. Each reminder is claimed in the database for that end date first, so it goes out at most
    # once per end date however often this runs (an admin extension to a new end date re-arms it).
    scheduler.add_job(
        send_plan_renewal_reminders,
        trigger=CronTrigger(timezone=app_tz, minute=20),
        id="send_plan_renewal_reminders",
        name="Send paid plan renewal reminders",
        replace_existing=True,
        misfire_grace_time=3600,
        coalesce=True,
    )

    # Tell each device whose sign-in has expired that it was signed out, hourly. The reminder is stamped in the database
    # as it is claimed, so each device gets at most one however often this runs (registering again re-arms it).
    scheduler.add_job(
        send_sign_in_reminders,
        trigger=CronTrigger(timezone=app_tz, minute=35),
        id="sign_in_reminders",
        name="Send sign-in reminders to signed-out devices",
        replace_existing=True,
        misfire_grace_time=3600,
        coalesce=True,
    )

    # Forget devices not seen for 60 days, daily at 03:15 (default zone).
    scheduler.add_job(
        delete_stale_devices,
        trigger=CronTrigger(timezone=app_tz, hour=3, minute=15),
        id="stale_devices",
        name="Delete stale devices",
        replace_existing=True,
        misfire_grace_time=6 * 3600,
        coalesce=True,
    )

    # Fail custom insights still pending 20 minutes after they were created (a job lost to a restart), every
    # 5 minutes: the use is given back and the user told it was not created.
    scheduler.add_job(
        fail_stuck_reports,
        trigger=CronTrigger(timezone=app_tz, minute="*/5"),
        id="custom_insight_sweeper",
        name="Fail stuck custom insights",
        replace_existing=True,
        coalesce=True,
        misfire_grace_time=300,
    )

    scheduler.start()
    logger.info(f"✅ Async Notification scheduler started (timezone: {app_tz})")

    return scheduler
