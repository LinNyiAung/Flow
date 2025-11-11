from datetime import datetime, UTC, timedelta
from typing import List, Optional
import uuid
from database import goals_collection, database

from database import (notifications_collection, budgets_collection)


def create_notification(
    user_id: str,
    notification_type: str,
    title: str,
    message: str,
    goal_id: Optional[str] = None,
    goal_name: Optional[str] = None
) -> dict:
    """Create a new notification"""
    notification_id = str(uuid.uuid4())
    notification = {
        "_id": notification_id,
        "user_id": user_id,
        "type": notification_type,
        "title": title,
        "message": message,
        "goal_id": goal_id,
        "goal_name": goal_name,
        "created_at": datetime.now(UTC),
        "is_read": False
    }
    notifications_collection.insert_one(notification)
    return notification

def check_goal_notifications(user_id: str, goal_id: str, old_progress: float, new_progress: float, goal_name: str):
    """Check and create notifications based on goal progress"""
    # Progress milestones: 25%, 50%, 75%, 100%
    milestones = [25, 50, 75, 100]
    
    for milestone in milestones:
        # Check if we just crossed this milestone
        if old_progress < milestone <= new_progress:
            if milestone == 100:
                # Goal achieved
                create_notification(
                    user_id=user_id,
                    notification_type="goal_achieved",
                    title="Goal Achieved! 🥳",
                    message=f"Congratulations! You've officially achieved your '{goal_name}' goal! Amazing work!",
                    goal_id=goal_id,
                    goal_name=goal_name
                )
            elif milestone in [25, 50, 75]:
                # Progress updates
                emoji = "💪" if milestone == 25 else "🎯" if milestone == 50 else "🎉"
                create_notification(
                    user_id=user_id,
                    notification_type="goal_progress",
                    title=f"Goal Progress: {milestone}% {emoji}",
                    message=f"You're {milestone}% of the way to your '{goal_name}'! Keep up the great momentum!",
                    goal_id=goal_id,
                    goal_name=goal_name
                )

def check_milestone_amount(user_id: str, goal_id: str, old_amount: float, new_amount: float, goal_name: str):
    """Check for milestone amounts (every $1000)"""
    milestone_interval = 1000
    old_milestone = int(old_amount / milestone_interval)
    new_milestone = int(new_amount / milestone_interval)
    
    if new_milestone > old_milestone:
        milestone_amount = new_milestone * milestone_interval
        create_notification(
            user_id=user_id,
            notification_type="goal_milestone",
            title="Milestone Reached! 🏆",
            message=f"Fantastic! You've just saved ${milestone_amount:,.0f} towards your '{goal_name}' goal. Celebrate this win!",
            goal_id=goal_id,
            goal_name=goal_name
        )

def check_approaching_target_dates():
    """Check all goals for approaching target dates (run daily)"""
    now = datetime.now(UTC)
    two_weeks_from_now = now + timedelta(days=14)
    one_week_from_now = now + timedelta(days=7)
    three_days_from_now = now + timedelta(days=3)
    
    # Find active goals with target dates approaching
    goals = goals_collection.find({
        "status": "active",
        "target_date": {
            "$gte": now,
            "$lte": two_weeks_from_now
        }
    })
    
    for goal in goals:
        target_date = goal["target_date"]
        user_id = goal["user_id"]
        goal_id = goal["_id"]
        goal_name = goal["name"]
        remaining = goal["target_amount"] - goal["current_amount"]
        
        # Check if notification already sent for this period
        days_until = (target_date - now).days
        
        # Send notification at 14 days, 7 days, and 3 days
        if days_until == 14 or days_until == 7 or days_until == 3:
            # Check if we already sent this notification
            existing = notifications_collection.find_one({
                "user_id": user_id,
                "goal_id": goal_id,
                "type": "goal_approaching_date",
                "created_at": {"$gte": now - timedelta(hours=24)}
            })
            
            if not existing:
                time_text = f"{days_until} days" if days_until > 1 else "1 day"
                if remaining > 0:
                    message = f"Your '{goal_name}' target date is just {time_text} away! You have ${remaining:.2f} remaining. You're doing great working towards it! 🗓️"
                else:
                    message = f"Your '{goal_name}' target date is just {time_text} away! You've already reached your target amount! 🎯"
                
                create_notification(
                    user_id=user_id,
                    notification_type="goal_approaching_date",
                    title=f"Goal Deadline Approaching 🗓️",
                    message=message,
                    goal_id=goal_id,
                    goal_name=goal_name
                )
                
                
def check_budget_notifications(user_id: str, budget_id: str, old_percentage: float, new_percentage: float, budget_name: str, category_name: str = None):
    """Check and create budget threshold/exceeded notifications"""
    
    # Category-specific or overall budget
    budget_label = f"'{category_name}'" if category_name else "overall"
    
    # Check for 80% threshold
    if old_percentage < 80 <= new_percentage < 100:
        create_notification(
            user_id=user_id,
            notification_type="budget_threshold",
            title=f"Budget Alert: 80% Spent 🔔",
            message=f"You've spent 80% of your {budget_label} budget in '{budget_name}'. Consider adjusting your spending.",
            goal_id=budget_id,
            goal_name=budget_name
        )
    
    # Check for exceeded (>100%)
    if old_percentage < 100 <= new_percentage:
        exceeded_amount = ((new_percentage - 100) / 100) * 100  # Rough calculation
        create_notification(
            user_id=user_id,
            notification_type="budget_exceeded",
            title=f"Budget Exceeded! ⚠️",
            message=f"You've exceeded your {budget_label} budget in '{budget_name}'. Review your recent expenses.",
            goal_id=budget_id,
            goal_name=budget_name
        )


def check_budget_period_notifications():
    """Check all budgets for period start/end notifications (run daily)"""
    from datetime import datetime, UTC, timedelta
    
    now = datetime.now(UTC)
    three_days_from_now = now + timedelta(days=3)
    
    # Check for budgets ending in 3 days
    budgets_ending = budgets_collection.find({
        "status": "active",
        "end_date": {
            "$gte": now,
            "$lte": three_days_from_now
        }
    })
    
    for budget in budgets_ending:
        user_id = budget["user_id"]
        budget_id = budget["_id"]
        budget_name = budget["name"]
        end_date = budget["end_date"]
        
        days_until_end = (end_date - now).days
        
        # Only send notification once per milestone
        if days_until_end == 3:
            # Check if we already sent this notification
            existing = notifications_collection.find_one({
                "user_id": user_id,
                "goal_id": budget_id,
                "type": "budget_ending_soon",
                "created_at": {"$gte": now - timedelta(hours=24)}
            })
            
            if not existing:
                create_notification(
                    user_id=user_id,
                    notification_type="budget_ending_soon",
                    title="Budget Ending Soon 📅",
                    message=f"Your '{budget_name}' budget period ends in 3 days. Review your spending to see how you did!",
                    goal_id=budget_id,
                    goal_name=budget_name
                )
    
    # Check for budgets that just became active (upcoming -> active)
    budgets_now_active = budgets_collection.find({
        "status": "upcoming",
        "start_date": {"$lte": now}
    })
    
    for budget in budgets_now_active:
        user_id = budget["user_id"]
        budget_id = budget["_id"]
        budget_name = budget["name"]
        total_budget = budget["total_budget"]
        
        # Check if we already sent this notification
        existing = notifications_collection.find_one({
            "user_id": user_id,
            "goal_id": budget_id,
            "type": "budget_now_active"
        })
        
        if not existing:
            create_notification(
                user_id=user_id,
                notification_type="budget_now_active",
                title="Budget Now Active! 🚀",
                message=f"Your '{budget_name}' budget is now active! Total budget: ${total_budget:.2f}",
                goal_id=budget_id,
                goal_name=budget_name
            )


def notify_budget_started(user_id: str, budget_id: str, budget_name: str, total_budget: float, period: str):
    """Notify when a new budget is created and started"""
    create_notification(
        user_id=user_id,
        notification_type="budget_started",
        title="New Budget Started 🚀",
        message=f"Your '{budget_name}' budget for {period} has started. Total budget: ${total_budget:.2f}",
        goal_id=budget_id,
        goal_name=budget_name
    )


def notify_budget_auto_created(user_id: str, budget_id: str, budget_name: str, was_ai: bool):
    """Notify when a budget is auto-created"""
    ai_text = "with AI optimization" if was_ai else "based on your previous budget"
    
    create_notification(
        user_id=user_id,
        notification_type="budget_auto_created",
        title="Budget Auto-Created 🔄",
        message=f"Your '{budget_name}' budget has ended. A new budget for the next period has been created {ai_text}.",
        goal_id=budget_id,
        goal_name=budget_name
    )