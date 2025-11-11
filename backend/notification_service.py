from datetime import datetime, UTC, timedelta
from typing import List, Optional
import uuid
from database import goals_collection, database

from database import notifications_collection


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