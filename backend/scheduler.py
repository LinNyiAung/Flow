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
from insights_service import generate_weekly_insights_for_all_users, generate_monthly_insights_for_all_users

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def start_scheduler():
    """Start the async scheduler for notifications"""
    # [CHANGED] Use AsyncIOScheduler instead of BackgroundScheduler
    # This allows jobs to run on the MAIN event loop, reusing the global DB client.
    scheduler = AsyncIOScheduler()

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
        trigger=CronTrigger(hour=9, minute=0),
        id="check_target_dates",
        name="Check approaching goal target dates",
        replace_existing=True
    )
    
    # Check for budget period notifications daily at 9 AM
    scheduler.add_job(
        check_budget_period_notifications,
        trigger=CronTrigger(hour=9, minute=0),
        id="check_budget_periods",
        name="Check budget periods for notifications",
        replace_existing=True
    )
    
    # Check for unusual spending patterns daily at 8 AM
    scheduler.add_job(
        analyze_all_users_spending,
        trigger=CronTrigger(hour=8, minute=0),
        id="analyze_unusual_spending",
        name="Analyze unusual spending patterns",
        replace_existing=True
    )
    
    # Check for recurring payment reminders daily at 9 AM
    scheduler.add_job(
        detect_and_notify_recurring_payments,
        trigger=CronTrigger(hour=9, minute=0),
        id="payment_reminders",
        name="Check for upcoming recurring payments",
        replace_existing=True
    )
    
    # Check recurring transactions daily at 6 AM
    scheduler.add_job(
        check_and_create_recurring_transactions,
        trigger=CronTrigger(hour=6, minute=0),
        id="check_recurring_transactions",
        name="Check and create recurring transactions",
        replace_existing=True
    )
    
    # Generate weekly insights every Monday at 5 AM
    scheduler.add_job(
        generate_weekly_insights_for_all_users,
        trigger=CronTrigger(day_of_week="mon", hour=5, minute=0),
        id="weekly_insights_generation",
        name="Generate weekly insights for all users",
        replace_existing=True
    )
    
    # Generate monthly insights on 1st of every month at 6 AM
    scheduler.add_job(
        generate_monthly_insights_for_all_users,
        trigger=CronTrigger(day=1, hour=6, minute=0),
        id="monthly_insights_generation",
        name="Generate monthly insights for all users",
        replace_existing=True
    )
    
    scheduler.start()
    logger.info("✅ Async Notification scheduler started")
    
    return scheduler