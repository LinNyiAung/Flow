from apscheduler.schedulers.background import BackgroundScheduler
from recurring_transaction_service import check_and_create_recurring_transactions
from notification_service import analyze_unusual_spending, check_approaching_target_dates, check_budget_period_notifications, detect_and_notify_recurring_payments
import logging
from database import users_collection

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def start_scheduler():
    """Start the background scheduler for notifications"""
    scheduler = BackgroundScheduler()
    
    # Check for approaching goal target dates daily at 9 AM
    scheduler.add_job(
        func=check_approaching_target_dates,
        trigger="cron",
        hour=9,
        minute=0,
        id="check_target_dates",
        name="Check approaching goal target dates",
        replace_existing=True
    )
    
    # Check for budget period notifications daily at 9 AM
    scheduler.add_job(
        func=check_budget_period_notifications,
        trigger="cron",
        hour=9,
        minute=0,
        id="check_budget_periods",
        name="Check budget periods for notifications",
        replace_existing=True
    )
    
    # NEW: Check for unusual spending patterns daily at 8 AM
    def analyze_all_users_spending():
        """Analyze spending for all users"""
        users = users_collection.find({})
        for user in users:
            try:
                analyze_unusual_spending(user["_id"])
            except Exception as e:
                print(f"Error analyzing spending for user {user['_id']}: {e}")
    
    scheduler.add_job(
        func=analyze_all_users_spending,
        trigger="cron",
        hour=8,
        minute=0,
        id="analyze_unusual_spending",
        name="Analyze unusual spending patterns",
        replace_existing=True
    )
    
    # NEW: Check for recurring payment reminders daily at 9 AM
    scheduler.add_job(
        func=detect_and_notify_recurring_payments,
        trigger="cron",
        hour=9,
        minute=0,
        id="payment_reminders",
        name="Check for upcoming recurring payments",
        replace_existing=True
    )
    
    
    scheduler.add_job(
        func=check_and_create_recurring_transactions,
        trigger="cron",
        hour=6,
        minute=0,
        id="check_recurring_transactions",
        name="Check and create recurring transactions",
        replace_existing=True
    )
    
    
    
        # NEW: Generate weekly insights every Sunday at 6 AM
    def generate_all_users_weekly_insights():
        """Generate weekly insights for all premium users"""
        from insights_service import generate_weekly_insights_for_all_users
        generate_weekly_insights_for_all_users()
    
    scheduler.add_job(
        func=generate_all_users_weekly_insights,
        trigger="cron",
        day_of_week="mon",  # Monday
        hour=5,  # 6 AM Monday morning
        minute=0,
        id="weekly_insights_generation",
        name="Generate weekly insights for all users",
        replace_existing=True
    )
    
    scheduler.start()
    logger.info("Notification scheduler started")
    
    return scheduler