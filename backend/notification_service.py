from datetime import datetime, UTC, timedelta
from typing import Dict, List, Optional
import uuid
from database import goals_collection, notification_preferences_collection

from database import (notifications_collection, budgets_collection, transactions_collection, users_collection)


def format_currency_amount(amount: float, currency: str) -> str:
    """Format amount with appropriate currency symbol"""
    if currency == "mmk":
        return f"{amount:,.0f} K"
    else:  # usd
        return f"${amount:,.2f}"

def get_user_notification_preferences(user_id: str) -> Dict[str, bool]:
    """Get user's notification preferences, return defaults if not set"""
    prefs = notification_preferences_collection.find_one({"user_id": user_id})
    
    if not prefs:
        # Return default preferences (all enabled)
        default_prefs = {
            "goal_progress": True,
            "goal_milestone": True,
            "goal_approaching_date": True,
            "goal_achieved": True,
            "budget_started": True,
            "budget_ending_soon": True,
            "budget_threshold": True,
            "budget_exceeded": True,
            "budget_auto_created": True,
            "budget_now_active": True,
            "large_transaction": True,
            "unusual_spending": True,
            "payment_reminder": True,
            "recurring_transaction_created": True,
            "recurring_transaction_ended": True,
            "recurring_transaction_disabled": True,
            "weekly_insights_generated": True,  # ADD
            "monthly_insights_generated": True,  # NEW
        }
        return default_prefs
    
    return prefs.get("preferences", {})



def should_send_notification(user_id: str, notification_type: str) -> bool:
    """Check if user wants to receive this type of notification"""
    preferences = get_user_notification_preferences(user_id)
    return preferences.get(notification_type, True)  # Default to True if not set


def create_notification(
    user_id: str,
    notification_type: str,
    title: str,
    message: str,
    goal_id: Optional[str] = None,
    goal_name: Optional[str] = None,
    currency: Optional[str] = None  # NEW parameter
) -> Optional[dict]:
    """Create a new notification (only if user has it enabled)"""
    
    if not should_send_notification(user_id, notification_type):
        print(f"Skipping notification {notification_type} for user {user_id} (disabled in preferences)")
        return None
    
    notification_id = str(uuid.uuid4())
    notification = {
        "_id": notification_id,
        "user_id": user_id,
        "type": notification_type,
        "title": title,
        "message": message,
        "goal_id": goal_id,
        "goal_name": goal_name,
        "currency": currency,  # NEW
        "created_at": datetime.now(UTC),
        "is_read": False
    }
    notifications_collection.insert_one(notification)
    print(f"✅ Created notification {notification_type} for user {user_id}")
    return notification

def check_goal_notifications(user_id: str, goal_id: str, old_progress: float, new_progress: float, goal_name: str):
    """Check and create notifications based on goal progress"""
    # Get goal to retrieve currency
    goal = goals_collection.find_one({"_id": goal_id})
    currency = goal.get("currency", "usd") if goal else "usd"
    
    milestones = [25, 50, 75, 100]
    
    for milestone in milestones:
        if old_progress < milestone <= new_progress:
            if milestone == 100:
                create_notification(
                    user_id=user_id,
                    notification_type="goal_achieved",
                    title="Goal Achieved! 🥳",
                    message=f"Congratulations! You've officially achieved your '{goal_name}' goal! Amazing work!",
                    goal_id=goal_id,
                    goal_name=goal_name,
                    currency=currency  # NEW
                )
            elif milestone in [25, 50, 75]:
                emoji = "💪" if milestone == 25 else "🎯" if milestone == 50 else "🎉"
                create_notification(
                    user_id=user_id,
                    notification_type="goal_progress",
                    title=f"Goal Progress: {milestone}% {emoji}",
                    message=f"You're {milestone}% of the way to your '{goal_name}'! Keep up the great momentum!",
                    goal_id=goal_id,
                    goal_name=goal_name,
                    currency=currency  # NEW
                )

def check_milestone_amount(user_id: str, goal_id: str, old_amount: float, new_amount: float, goal_name: str):
    """Check for milestone amounts (every $1000 or 1M K)"""
    # Get goal to retrieve currency
    goal = goals_collection.find_one({"_id": goal_id})
    currency = goal.get("currency", "usd") if goal else "usd"
    
    # Different milestone intervals for different currencies
    milestone_interval = 1000000 if currency == "mmk" else 1000  # 1M K or $1000
    
    old_milestone = int(old_amount / milestone_interval)
    new_milestone = int(new_amount / milestone_interval)
    
    if new_milestone > old_milestone:
        milestone_amount = new_milestone * milestone_interval
        formatted_amount = format_currency_amount(milestone_amount, currency)
        
        create_notification(
            user_id=user_id,
            notification_type="goal_milestone",
            title="Milestone Reached! 🏆",
            message=f"Fantastic! You've just saved {formatted_amount} towards your '{goal_name}' goal. Celebrate this win!",
            goal_id=goal_id,
            goal_name=goal_name,
            currency=currency  # NEW
        )

def check_approaching_target_dates():
    """Check all goals for approaching target dates (run daily)"""
    now = datetime.now(UTC)
    two_weeks_from_now = now + timedelta(days=14)
    one_week_from_now = now + timedelta(days=7)
    three_days_from_now = now + timedelta(days=3)
    
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
        currency = goal.get("currency", "usd")  # NEW
        
        days_until = (target_date - now).days
        
        if days_until == 14 or days_until == 7 or days_until == 3:
            existing = notifications_collection.find_one({
                "user_id": user_id,
                "goal_id": goal_id,
                "type": "goal_approaching_date",
                "created_at": {"$gte": now - timedelta(hours=24)}
            })
            
            if not existing:
                time_text = f"{days_until} days" if days_until > 1 else "1 day"
                formatted_remaining = format_currency_amount(remaining, currency)  # NEW
                
                if remaining > 0:
                    message = f"Your '{goal_name}' target date is just {time_text} away! You have {formatted_remaining} remaining. You're doing great working towards it! 🗓️"
                else:
                    message = f"Your '{goal_name}' target date is just {time_text} away! You've already reached your target amount! 🎯"
                
                create_notification(
                    user_id=user_id,
                    notification_type="goal_approaching_date",
                    title=f"Goal Deadline Approaching 🗓️",
                    message=message,
                    goal_id=goal_id,
                    goal_name=goal_name,
                    currency=currency  # NEW
                )
                
                
def check_budget_notifications(user_id: str, budget_id: str, old_percentage: float, new_percentage: float, budget_name: str, category_name: str = None):
    """Check and create budget threshold/exceeded notifications"""
    # Get budget to retrieve currency
    budget = budgets_collection.find_one({"_id": budget_id})
    currency = budget.get("currency", "usd") if budget else "usd"
    
    budget_label = f"'{category_name}'" if category_name else "overall"
    
    if old_percentage < 80 <= new_percentage < 100:
        create_notification(
            user_id=user_id,
            notification_type="budget_threshold",
            title=f"Budget Alert: 80% Spent 📊",
            message=f"You've spent 80% of your {budget_label} budget in '{budget_name}'. Consider adjusting your spending.",
            goal_id=budget_id,
            goal_name=budget_name,
            currency=currency  # NEW
        )
    
    if old_percentage < 100 <= new_percentage:
        create_notification(
            user_id=user_id,
            notification_type="budget_exceeded",
            title=f"Budget Exceeded! ⚠️",
            message=f"You've exceeded your {budget_label} budget in '{budget_name}'. Review your recent expenses.",
            goal_id=budget_id,
            goal_name=budget_name,
            currency=currency  # NEW
        )


def check_budget_period_notifications():
    """Check all budgets for period start/end notifications (run daily)"""
    from datetime import datetime, UTC, timedelta
    
    now = datetime.now(UTC)
    three_days_from_now = now + timedelta(days=3)
    
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
        currency = budget.get("currency", "usd")  # NEW
        
        days_until_end = (end_date - now).days
        
        if days_until_end == 3:
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
                    goal_name=budget_name,
                    currency=currency  # NEW
                )
    
    budgets_now_active = budgets_collection.find({
        "status": "upcoming",
        "start_date": {"$lte": now}
    })
    
    for budget in budgets_now_active:
        user_id = budget["user_id"]
        budget_id = budget["_id"]
        budget_name = budget["name"]
        total_budget = budget["total_budget"]
        currency = budget.get("currency", "usd")  # NEW
        formatted_budget = format_currency_amount(total_budget, currency)  # NEW
        
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
                message=f"Your '{budget_name}' budget is now active! Total budget: {formatted_budget}",
                goal_id=budget_id,
                goal_name=budget_name,
                currency=currency  # NEW
            )


def notify_budget_started(user_id: str, budget_id: str, budget_name: str, total_budget: float, period: str):
    """Notify when a new budget is created and started"""
    # Get budget to retrieve currency
    budget = budgets_collection.find_one({"_id": budget_id})
    currency = budget.get("currency", "usd") if budget else "usd"
    formatted_budget = format_currency_amount(total_budget, currency)
    
    create_notification(
        user_id=user_id,
        notification_type="budget_started",
        title="New Budget Started 🚀",
        message=f"Your '{budget_name}' budget for {period} has started. Total budget: {formatted_budget}",
        goal_id=budget_id,
        goal_name=budget_name,
        currency=currency  # NEW
    )


def notify_budget_auto_created(user_id: str, budget_id: str, budget_name: str, was_ai: bool):
    """Notify when a budget is auto-created"""
    budget = budgets_collection.find_one({"_id": budget_id})
    currency = budget.get("currency", "usd") if budget else "usd"
    
    ai_text = "with AI optimization" if was_ai else "based on your previous budget"
    
    create_notification(
        user_id=user_id,
        notification_type="budget_auto_created",
        title="Budget Auto-Created 🔄",
        message=f"Your '{budget_name}' budget has ended. A new budget for the next period has been created {ai_text}.",
        goal_id=budget_id,
        goal_name=budget_name,
        currency=currency  # NEW
    )
    
    
def check_large_transaction(user_id: str, transaction: Dict, user_spending_profile: Dict = None):
    """Check if a transaction is unusually large and notify"""
    from datetime import datetime, UTC, timedelta
    
    amount = transaction["amount"]
    transaction_type = transaction["type"]
    category = transaction["main_category"]
    description = transaction.get("description", "")
    currency = transaction.get("currency", "usd")  # NEW
    
    if transaction_type != "outflow":
        return
    
    # Currency-aware threshold
    if user_spending_profile and "avg_transaction" in user_spending_profile:
        threshold = user_spending_profile["avg_transaction"] * 3
        threshold = max(threshold, 100000 if currency == "mmk" else 100)
    else:
        threshold = 150000 if currency == "mmk" else 150
    
    if amount >= threshold:
        existing = notifications_collection.find_one({
            "user_id": user_id,
            "type": "large_transaction",
            "created_at": {"$gte": datetime.now(UTC) - timedelta(minutes=5)}
        })
        
        if not existing:
            merchant_info = f" at {description}" if description else ""
            formatted_amount = format_currency_amount(amount, currency)  # NEW
            
            create_notification(
                user_id=user_id,
                notification_type="large_transaction",
                title="Large Transaction Alert 💰",
                message=f"You had a large expense of {formatted_amount}{merchant_info} for {category}.",
                goal_id=transaction["_id"],
                goal_name=f"Large {category} expense",
                currency=currency  # NEW
            )


def analyze_unusual_spending(user_id: str):
    """Analyze spending patterns and notify about unusual activity"""
    from datetime import datetime, UTC, timedelta
    from collections import defaultdict
    import statistics
    
    now = datetime.now(UTC)
    
    # Analyze per currency
    currencies = transactions_collection.distinct("currency", {"user_id": user_id})
    
    for currency in currencies:
        this_week_start = now - timedelta(days=7)
        this_week_transactions = list(transactions_collection.find({
            "user_id": user_id,
            "type": "outflow",
            "currency": currency,
            "date": {"$gte": this_week_start}
        }))
        
        last_month_start = now - timedelta(days=35)
        last_month_end = this_week_start
        last_month_transactions = list(transactions_collection.find({
            "user_id": user_id,
            "type": "outflow",
            "currency": currency,
            "date": {"$gte": last_month_start, "$lt": last_month_end}
        }))
        
        if len(last_month_transactions) < 5:
            continue
        
        this_week_by_category = defaultdict(float)
        last_month_by_category = defaultdict(float)
        
        for t in this_week_transactions:
            this_week_by_category[t["main_category"]] += t["amount"]
        
        for t in last_month_transactions:
            last_month_by_category[t["main_category"]] += t["amount"]
        
        weeks_in_last_month = 4
        
        for category, this_week_amount in this_week_by_category.items():
            if category not in last_month_by_category:
                continue
            
            weekly_avg = last_month_by_category[category] / weeks_in_last_month
            
            # Currency-aware threshold
            min_diff = 50000 if currency == "mmk" else 50
            
            if this_week_amount > weekly_avg * 1.5 and this_week_amount - weekly_avg > min_diff:
                existing = notifications_collection.find_one({
                    "user_id": user_id,
                    "type": "unusual_spending",
                    "goal_name": category,
                    "currency": currency,
                    "created_at": {"$gte": this_week_start}
                })
                
                if not existing:
                    formatted_this_week = format_currency_amount(this_week_amount, currency)
                    formatted_avg = format_currency_amount(weekly_avg, currency)
                    
                    create_notification(
                        user_id=user_id,
                        notification_type="unusual_spending",
                        title="Unusual Spending Detected 📊",
                        message=f"Your spending on '{category}' is higher than usual this week ({formatted_this_week} vs usual {formatted_avg}). Would you like to review these transactions?",
                        goal_id=None,
                        goal_name=category,
                        currency=currency  # NEW
                    )


def detect_and_notify_recurring_payments():
    """Detect recurring payments and send reminders"""
    from datetime import datetime, UTC, timedelta
    from collections import defaultdict
    
    now = datetime.now(UTC)
    three_days_from_now = now + timedelta(days=3)
    
    users = users_collection.find({})
    
    for user in users:
        user_id = user["_id"]
        
        # Analyze per currency
        currencies = transactions_collection.distinct("currency", {"user_id": user_id})
        
        for currency in currencies:
            ninety_days_ago = now - timedelta(days=90)
            transactions = list(transactions_collection.find({
                "user_id": user_id,
                "type": "outflow",
                "currency": currency,
                "date": {"$gte": ninety_days_ago}
            }))
            
            if len(transactions) < 10:
                continue
            
            recurring_patterns = defaultdict(list)
            
            for t in transactions:
                key = t.get("description", "").lower().strip()
                if not key:
                    key = t["sub_category"].lower()
                
                if len(key) < 3 or key in ["payment", "purchase", "expense"]:
                    continue
                
                recurring_patterns[key].append({
                    "date": t["date"],
                    "amount": t["amount"],
                    "category": t["main_category"],
                    "sub_category": t["sub_category"],
                    "description": t.get("description", t["sub_category"])
                })
            
            for key, occurrences in recurring_patterns.items():
                if len(occurrences) < 2:
                    continue
                
                occurrences.sort(key=lambda x: x["date"])
                
                intervals = []
                for i in range(1, len(occurrences)):
                    interval = (occurrences[i]["date"] - occurrences[i-1]["date"]).days
                    intervals.append(interval)
                
                if not intervals:
                    continue
                
                avg_interval = sum(intervals) / len(intervals)
                
                if 28 <= avg_interval <= 32:
                    last_occurrence = occurrences[-1]["date"]
                    next_expected = last_occurrence + timedelta(days=int(avg_interval))
                    
                    days_until = (next_expected - now).days
                    
                    if 2 <= days_until <= 4:
                        existing = notifications_collection.find_one({
                            "user_id": user_id,
                            "type": "payment_reminder",
                            "goal_name": key,
                            "currency": currency,
                            "created_at": {"$gte": now - timedelta(days=7)}
                        })
                        
                        if not existing:
                            last_amount = occurrences[-1]["amount"]
                            description = occurrences[-1]["description"]
                            formatted_amount = format_currency_amount(last_amount, currency)
                            
                            create_notification(
                                user_id=user_id,
                                notification_type="payment_reminder",
                                title="Upcoming Payment Reminder 📅",
                                message=f"Your '{description}' payment of {formatted_amount} is due in {days_until} days.",
                                goal_id=None,
                                goal_name=key,
                                currency=currency  # NEW
                            )
                            
                            
                            
def notify_monthly_insights_generated(user_id: str):
    """Notify when monthly insights are generated"""
    create_notification(
        user_id=user_id,
        notification_type="monthly_insights_generated",
        title="Monthly Insights Ready! 📊",
        message=f"Your monthly financial insights powered by Flow Finance AI are now available. Check them out to see your monthly financial progress!",
        goal_id=None,
        goal_name=f"Monthly Insights Tailored For You",
        currency=None
    )
    
    
    
def notify_weekly_insights_generated(user_id: str):
    """Notify when weekly insights are generated"""   
    create_notification(
        user_id=user_id,
        notification_type="weekly_insights_generated",
        title="Weekly Insights Ready! 📊",
        message=f"Your weekly financial insights powered by Flow Finance Ai are now available. Check them out to see your financial progress!",
        goal_id=None,
        goal_name=f"Weekly Insights Tailored For You",
        currency=None
    )