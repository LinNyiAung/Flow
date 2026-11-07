import logging
from apscheduler.schedulers.asyncio import AsyncIOScheduler  # [CHANGED]
from apscheduler.triggers.cron import CronTrigger
from recurring_transaction_service import check_and_create_recurring_transactions
from notification_service import (
    analyze_unusual_spending, 
    check_approaching_target_dates, 
    check_budget_period_notifications, 
    detect_and_notify_recurring_payments
)
from sql import users as users_db
from budget_service import process_due_budget_rollovers
from insights_service import generate_weekly_insights_for_all_users, generate_monthly_insights_for_all_users
from custom_insights_service import fail_stuck_reports
from insight_schedule import WEEKLY_INSIGHT_CRON, MONTHLY_INSIGHT_CRON
from subscription_service import expire_paid_plans, send_plan_renewal_reminders, send_trial_reminders
from tz_utils import get_app_timezone

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def start_scheduler():
    """Start the async scheduler for notifications"""
    # [CHANGED] Use AsyncIOScheduler instead of BackgroundScheduler
    # This allows jobs to run on the MAIN event loop, reusing the global DB client.
    # Explicit timezone (SCHEDULER_TIMEZONE, default Asia/Yangon) so cron times like
    # "Monday 05:00" mean local time regardless of the server's TZ. insights_service
    # computes the "previous week/month" with the same timezone (tz_utils).
    app_tz = get_app_timezone()
    scheduler = AsyncIOScheduler(timezone=app_tz)

    # --- NO WRAPPERS NEEDED ---
    # We can now pass the async functions directly to the scheduler.
    
    # Special handling for user iteration (Async Cursor)
    async def analyze_all_users_spending():
        # [FIX] This now works because it runs on the main loop
        for user_id in await users_db.user_ids():
            try:
                await analyze_unusual_spending(user_id)
            except Exception as e:
                print(f"Error analyzing spending for user {user_id}: {e}")

    # --- ADD JOBS ---

    # Check for approaching goal target dates daily at 9 AM
    scheduler.add_job(
        check_approaching_target_dates, # Pass the async function directly
        trigger=CronTrigger(timezone=app_tz, hour=9, minute=0),
        id="check_target_dates",
        name="Check approaching goal target dates",
        replace_existing=True
    )
    
    # Check for budget period notifications daily at 9 AM
    scheduler.add_job(
        check_budget_period_notifications,
        trigger=CronTrigger(timezone=app_tz, hour=9, minute=0),
        id="check_budget_periods",
        name="Check budget periods for notifications",
        replace_existing=True
    )
    
    # Check for unusual spending patterns daily at 8 AM
    scheduler.add_job(
        analyze_all_users_spending,
        trigger=CronTrigger(timezone=app_tz, hour=8, minute=0),
        id="analyze_unusual_spending",
        name="Analyze unusual spending patterns",
        replace_existing=True
    )
    
    # Check for recurring payment reminders daily at 9 AM
    scheduler.add_job(
        detect_and_notify_recurring_payments,
        trigger=CronTrigger(timezone=app_tz, hour=9, minute=0),
        id="payment_reminders",
        name="Check for upcoming recurring payments",
        replace_existing=True
    )
    
    # Roll over finished auto-create budgets daily at 00:30 (app timezone): budgets whose
    # end date has passed and that have no next-period child get it created here instead
    # of only when something happens to recompute them. Failures are retried next run.
    scheduler.add_job(
        process_due_budget_rollovers,
        trigger=CronTrigger(timezone=app_tz, hour=0, minute=30),
        id="budget_rollovers",
        name="Create next-period budgets for finished auto-create budgets",
        replace_existing=True,
        misfire_grace_time=6 * 3600,
        coalesce=True,
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

    # Remind Plus-trial users 3 days before the trial ends and on its last day, hourly. Each
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

    # Remind paying Plus / Pro users whose plan has an end date, 3 days before it ends and on its last day, on the
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

    # Check recurring transactions daily at 6 AM
    scheduler.add_job(
        check_and_create_recurring_transactions,
        trigger=CronTrigger(timezone=app_tz, hour=6, minute=0),
        id="check_recurring_transactions",
        name="Check and create recurring transactions",
        replace_existing=True
    )
    
    # Generate weekly insights every Monday at 5 AM
    scheduler.add_job(
        generate_weekly_insights_for_all_users,
        trigger=CronTrigger(timezone=app_tz, **WEEKLY_INSIGHT_CRON),
        id="weekly_insights_generation",
        name="Generate weekly insights for all users",
        replace_existing=True
    )
    
    # Generate monthly insights on 1st of every month at 6 AM
    scheduler.add_job(
        generate_monthly_insights_for_all_users,
        trigger=CronTrigger(timezone=app_tz, **MONTHLY_INSIGHT_CRON),
        id="monthly_insights_generation",
        name="Generate monthly insights for all users",
        replace_existing=True
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