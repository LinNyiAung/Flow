from apscheduler.schedulers.background import BackgroundScheduler
from notification_service import check_approaching_target_dates, check_budget_period_notifications
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def start_scheduler():
    """Start the background scheduler for notifications"""
    scheduler = BackgroundScheduler()
    
    # Check for approaching target dates daily at 9 AM
    scheduler.add_job(
        func=check_approaching_target_dates,
        trigger="cron",
        hour=9,
        minute=0,
        id="check_target_dates",
        name="Check approaching goal target dates",
        replace_existing=True
    )
    
    
    # NEW: Check for budget period notifications daily at 9 AM
    scheduler.add_job(
        func=check_budget_period_notifications,
        trigger="cron",
        hour=9,
        minute=0,
        id="check_budget_periods",
        name="Check budget periods for notifications",
        replace_existing=True
    )
    
    scheduler.start()
    logger.info("Notification scheduler started")
    
    return scheduler