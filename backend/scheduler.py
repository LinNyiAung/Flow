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
from database import users_collection
from budget_service import process_due_budget_rollovers
from insights_service import generate_weekly_insights_for_all_users, generate_monthly_insights_for_all_users
from subscription_service import expire_premium_subscriptions
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
        cursor = users_collection.find({})
        async for user in cursor:
            try:
                await analyze_unusual_spending(user["_id"])
            except Exception as e:
                print(f"Error analyzing spending for user {user['_id']}: {e}")

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

    # Downgrade expired premium subscriptions to free and notify the user, hourly so
    # the "Premium has ended" notification arrives soon after the expiry time.
    # (Premium features already stop at the exact expiry: require_premium checks it.)
    scheduler.add_job(
        expire_premium_subscriptions,
        trigger=CronTrigger(timezone=app_tz, minute=5),
        id="expire_premium_subscriptions",
        name="Downgrade expired premium subscriptions",
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
        trigger=CronTrigger(timezone=app_tz, day_of_week="mon", hour=5, minute=0),
        id="weekly_insights_generation",
        name="Generate weekly insights for all users",
        replace_existing=True
    )
    
    # Generate monthly insights on 1st of every month at 6 AM
    scheduler.add_job(
        generate_monthly_insights_for_all_users,
        trigger=CronTrigger(timezone=app_tz, day=1, hour=6, minute=0),
        id="monthly_insights_generation",
        name="Generate monthly insights for all users",
        replace_existing=True
    )
    
    scheduler.start()
    logger.info(f"✅ Async Notification scheduler started (timezone: {app_tz})")
    
    return scheduler