import asyncio
from datetime import datetime, UTC, timedelta
import threading
from typing import Dict, List, Optional
import uuid
from firebase_service import send_fcm_notification
from database import goals_collection, notification_preferences_collection, notifications_collection, budgets_collection, transactions_collection, users_collection


# NEW: Translation dictionaries
NOTIFICATION_TRANSLATIONS = {
    "en": {
        "goal_achieved_title": "Goal Achieved! 🥳",
        "goal_achieved_msg": "Congratulations! You've officially achieved your '{goal_name}' goal! Amazing work!",
        "goal_progress_title": "Goal Progress: {milestone}% {emoji}",
        "goal_progress_msg": "You're {milestone}% of the way to your '{goal_name}'! Keep up the great momentum!",
        "goal_milestone_title": "Milestone Reached! 🏆",
        "goal_milestone_msg": "Fantastic! You've just saved {amount} towards your '{goal_name}' goal. Celebrate this win!",
        "goal_approaching_title": "Goal Deadline Approaching 🗓️",
        "goal_approaching_msg_with_remaining": "Your '{goal_name}' target date is just {days} away! You have {remaining} remaining. You're doing great working towards it! 🗓️",
        "goal_approaching_msg_achieved": "Your '{goal_name}' target date is just {days} away! You've already reached your target amount! 🎯",
        "budget_threshold_title": "Budget Alert: 80% Spent 📊",
        "budget_threshold_msg": "You've spent 80% of your {label} budget in '{budget_name}'. Consider adjusting your spending.",
        "budget_exceeded_title": "Budget Exceeded! ⚠️",
        "budget_exceeded_msg": "You've exceeded your {label} budget in '{budget_name}'. Review your recent expenses.",
        "budget_ending_soon_title": "Budget Ending Soon 📅",
        "budget_ending_soon_msg": "Your '{budget_name}' budget period ends in 3 days. Review your spending to see how you did!",
        "budget_now_active_title": "Budget Now Active! 🚀",
        "budget_now_active_msg": "Your '{budget_name}' budget is now active! Total budget: {amount}",
        "budget_started_title": "New Budget Started 🚀",
        "budget_started_msg": "Your '{budget_name}' budget for {period} has started. Total budget: {amount}",
        "budget_auto_created_title": "Budget Auto-Created 🔄",
        "budget_auto_created_msg_ai": "Your '{budget_name}' budget has ended. A new budget for the next period has been created with AI optimization.",
        "budget_auto_created_msg": "Your '{budget_name}' budget has ended. A new budget for the next period has been created based on your previous budget.",
        "large_transaction_title": "Large Transaction Alert 💰",
        "large_transaction_msg": "You had a large expense of {amount}{merchant} for {category}.",
        "unusual_spending_title": "Unusual Spending Detected 📊",
        "unusual_spending_msg": "Your spending on '{category}' is higher than usual this week ({this_week} vs usual {avg}). Would you like to review these transactions?",
        "payment_reminder_title": "Upcoming Payment Reminder 📅",
        "payment_reminder_msg": "Your '{description}' payment of {amount} is due in {days} days.",
        "weekly_insights_title": "Weekly Insights Ready! 📊",
        "weekly_insights_msg": "Your weekly financial insights powered by Toe Pwar AI are now available. Check them out to see your financial progress!",
        "monthly_insights_title": "Monthly Insights Ready! 📊",
        "monthly_insights_msg": "Your monthly financial insights powered by Toe Pwar AI are now available. Check them out to see your monthly financial progress!",
    },
    "my": {
        "goal_achieved_title": "ရည်မှန်းချက် အောင်မြင်သွားပါပြီ! 🥳",
        "goal_achieved_msg": "ဂုဏ်ယူပါတယ်! သင်၏ '{goal_name}' ရည်မှန်းချက်ကို အောင်မြင်စွာ အကောင်အထည်ဖော်နိုင်ခဲ့ပါပြီ။ တကယ်ကို ချီးကျူးစရာပါပဲ!",
        "goal_progress_title": "ရည်မှန်းချက် တိုးတက်မှု: {milestone}% {emoji}",
        "goal_progress_msg": "သင်၏ '{goal_name}' ရည်မှန်းချက်ရောက်ဖို့ {milestone}% ခရီးရောက်နေပါပြီ။ ဒီအတိုင်းပဲ ဆက်လက်ကြိုးစားပေးပါဦး!",
        "goal_milestone_title": "မှတ်တိုင်သစ်တစ်ခုသို့ ရောက်ရှိ! 🏆",
        "goal_milestone_msg": "ထူးချွန်ပါတယ်! သင်၏ '{goal_name}' ရည်မှန်းချက်အတွက် {amount} စုဆောင်းနိုင်ခဲ့ပါပြီ။ ဒီအောင်မြင်မှုကို အတူတူအောင်ပွဲခံကြစို့!",
        "goal_approaching_title": "ရည်မှန်းချက် သတ်မှတ်ရက် နီးကပ်လာပြီ 🗓️",
        "goal_approaching_msg_with_remaining": "'{goal_name}' ရည်မှန်းချက်အတွက် သတ်မှတ်ရက်ရောက်ဖို့ {days} ရက်ပဲ လိုပါတော့တယ်။ ကျန်ရှိငွေ {remaining} လိုအပ်ပါသေးတယ်။ အကောင်းဆုံး ဆက်လက်ကြိုးစားပေးပါ!",
        "goal_approaching_msg_achieved": "'{goal_name}' ရည်မှန်းချက်အတွက် သတ်မှတ်ရက်ရောက်ဖို့ {days} ရက်ပဲ လိုပါတော့တယ်။ သင် သတ်မှတ်ထားတဲ့ ပမာဏကို ရောက်ရှိပြီးဖြစ်ပါတယ်! 🎯",
        "budget_threshold_title": "ဘတ်ဂျက်သတိပေးချက်: ၈၀% သုံးစွဲပြီး 📊",
        "budget_threshold_msg": "'{budget_name}' ထဲမှ {label} ဘတ်ဂျက်၏ ၈၀% ကို သင်သုံးစွဲပြီးပါပြီ။ အသုံးစရိတ်ကို ပြန်လည်စိစစ်ရန် အကြံပြုလိုပါတယ်။",
        "budget_exceeded_title": "ဘတ်ဂျက် ကျော်လွန်သွားပါပြီ! ⚠️",
        "budget_exceeded_msg": "'{budget_name}' ထဲမှ {label} ဘတ်ဂျက် ပမာဏထက် ကျော်လွန်သွားပါပြီ။ သင်၏ နောက်ဆုံးအသုံးစရိတ်များကို ပြန်လည်စစ်ဆေးကြည့်ပါ။",
        "budget_ending_soon_title": "ဘတ်ဂျက်ကာလ ကုန်ဆုံးတော့မည် 📅",
        "budget_ending_soon_msg": "'{budget_name}' ဘတ်ဂျက်ကာလကုန်ဆုံးရန် ၃ ရက်သာ လိုပါတော့တယ်။ သင်၏အသုံးစရိတ်များကို ပြန်လည်သုံးသပ်ကြည့်လိုက်ပါ။",
        "budget_now_active_title": "ဘတ်ဂျက် စတင်အသက်ဝင်ပါပြီ! 🚀",
        "budget_now_active_msg": "'{budget_name}' ဘတ်ဂျက်ကို ယခုစတင်အသုံးပြုနိုင်ပါပြီ။ စုစုပေါင်းဘတ်ဂျက်- {amount}",
        "budget_started_title": "ဘတ်ဂျက်အသစ် စတင်ပါပြီ 🚀",
        "budget_started_msg": "{period} အတွက် '{budget_name}' ဘတ်ဂျက် စတင်ပါပြီ။ စုစုပေါင်းဘတ်ဂျက်- {amount}",
        "budget_auto_created_title": "ဘတ်ဂျက်အသစ် အလိုအလျောက်ဖန်တီးပြီး 🔄",
        "budget_auto_created_msg_ai": "'{budget_name}' ဘတ်ဂျက်ကာလ ကုန်ဆုံးသွားပါပြီ။ AI အကူအညီဖြင့် နောက်ကာလအတွက် ဘတ်ဂျက်အသစ်တစ်ခုကို အလိုအလျောက် ဖန်တီးပေးထားပါသည်။",
        "budget_auto_created_msg": "'{budget_name}' ဘတ်ဂျက်ကာလ ကုန်ဆုံးသွားပါပြီ။ ယခင်အသုံးစရိတ်များအပေါ် အခြေခံ၍ နောက်ကာလအတွက် ဘတ်ဂျက်အသစ်တစ်ခုကို အလိုအလျောက် ဖန်တီးပေးထားပါသည်။",
        "large_transaction_title": "အသုံးစရိတ်ပမာဏ များပြားမှု သတိပေးချက် 💰",
        "large_transaction_msg": "{category} အတွက် {merchant} တွင် {amount} ပမာဏရှိသော အသုံးစရိတ်တစ်ခု ရှိခဲ့ပါသည်။",
        "unusual_spending_title": "ပုံမှန်မဟုတ်သော အသုံးစရိတ် တွေ့ရှိရသည် 📊",
        "unusual_spending_msg": "ယခုအပတ်တွင် '{category}' အတွက် အသုံးစရိတ်သည် ပုံမှန်ထက် ပိုများနေပါသည် (ပုံမှန် {avg} ဖြစ်သော်လည်း ယခုအပတ်တွင် {this_week} ဖြစ်နေသည်)။ ဤအသုံးစရိတ်များကို ပြန်လည်စစ်ဆေးလိုပါသလား?",
        "payment_reminder_title": "ပေးချေရန်ရှိသည်များကို သတိပေးခြင်း 📅",
        "payment_reminder_msg": "'{description}' အတွက် ပေးချေရန် {amount} ရှိပြီး နောက်ထပ် {days} ရက်အတွင်း ပေးချေရပါမည်။",
        "weekly_insights_title": "အပတ်စဉ်သုံးသပ်ချက် အဆင်သင့်ဖြစ်ပါပြီ! 📊",
        "weekly_insights_msg": "Toe Pwar AI မှ ထုတ်ပြန်ပေးသော သင်၏ အပတ်စဉ် ဘဏ္ဍာရေးသုံးသပ်ချက်များ ရရှိနိုင်ပါပြီ။ သင်၏ တိုးတက်မှုများကို စစ်ဆေးကြည့်လိုက်ပါ။",
        "monthly_insights_title": "လစဉ်သုံးသပ်ချက် အဆင်သင့်ဖြစ်ပါပြီ! 📊",
        "monthly_insights_msg": "Toe Pwar AI မှ ထုတ်ပြန်ပေးသော သင်၏ လစဉ် ဘဏ္ဍာရေးသုံးသပ်ချက်များ ရရှိနိုင်ပါပြီ။ တစ်လတာ တိုးတက်မှုများကို စစ်ဆေးကြည့်လိုက်ပါ။"
    }
}


def format_currency_amount(amount: float, currency: str) -> str:
    """Format amount with appropriate currency symbol"""
    if currency == "mmk":
        return f"{amount:,.0f} K"
    elif currency == "usd":  # usd
        return f"${amount:,.2f}"
    else:  
        return f"฿{amount:,.2f}"


async def get_user_language(user_id: str) -> str:
    """Get user's preferred language from user preferences or default to 'en'"""
    # [FIX] Added await
    user = await users_collection.find_one({"_id": user_id})
    return user.get("language", "en") if user else "en"


def translate(key: str, language: str, **kwargs) -> str:
    """Get translated text with variable substitution"""
    template = NOTIFICATION_TRANSLATIONS.get(language, NOTIFICATION_TRANSLATIONS["en"]).get(key, key)
    return template.format(**kwargs)


async def get_user_notification_preferences(user_id: str) -> Dict[str, bool]:
    """Get user's notification preferences, return defaults if not set"""
    # [FIX] Added await
    prefs = await notification_preferences_collection.find_one({"user_id": user_id})
    
    if not prefs:
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
            "weekly_insights_generated": True,
            "monthly_insights_generated": True,
        }
        return default_prefs
    
    return prefs.get("preferences", {})


async def should_send_notification(user_id: str, notification_type: str) -> bool:
    """Check if user wants to receive this type of notification"""
    # [FIX] Added await
    preferences = await get_user_notification_preferences(user_id)
    return preferences.get(notification_type, True)


async def create_notification(
    user_id: str,
    notification_type: str,
    title: str,
    message: str,
    goal_id: Optional[str] = None,
    goal_name: Optional[str] = None,
    currency: Optional[str] = None
) -> Optional[dict]:
    """Create a new notification (only if user has it enabled)"""
    
    # [FIX] Added await
    if not await should_send_notification(user_id, notification_type):
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
        "currency": currency,
        "created_at": datetime.now(UTC),
        "is_read": False
    }
    
    # [FIX] Added await
    await notifications_collection.insert_one(notification)
    print(f"✅ Created notification {notification_type} for user {user_id}")
    
    # [FIX] Fetch user data ASYNC before starting the thread
    # This prevents running async DB calls inside the sync thread
    user = await users_collection.find_one({"_id": user_id})
    fcm_token = user.get("fcm_token") if user else None

    # Send FCM push notification in a separate thread
    def send_background_fcm():
        try:
            if fcm_token:
                fcm_data = {
                    "notification_id": notification_id,
                    "type": notification_type,
                    "goal_id": goal_id or "",
                    "goal_name": goal_name or "",
                    "currency": currency or "",
                }
                
                send_fcm_notification(
                    fcm_token=fcm_token,
                    title=title,
                    body=message,
                    data=fcm_data
                )
            else:
                print(f"⚠️  User {user_id} has no FCM token")
        except Exception as e:
            print(f"❌ Error sending background FCM: {e}")

    # [FIX] Fire and forget using the event loop's thread pool
    # This prevents blocking the async loop while keeping execution managed
    try:
        loop = asyncio.get_running_loop()
        # Schedule the blocking sync function in a separate thread, managed by the loop
        loop.create_task(asyncio.to_thread(send_background_fcm))
    except RuntimeError:
        # Fallback if no loop is running (e.g., synchronous testing context)
        threading.Thread(target=send_background_fcm, daemon=True).start()
    
    return notification


async def check_goal_notifications(user_id: str, goal_id: str, old_progress: float, new_progress: float, goal_name: str):
    """Check and create notifications based on goal progress"""
    # [FIX] Added await
    goal = await goals_collection.find_one({"_id": goal_id})
    currency = goal.get("currency", "usd") if goal else "usd"
    # [FIX] Added await
    lang = await get_user_language(user_id)
    
    milestones = [25, 50, 75, 100]
    
    for milestone in milestones:
        if old_progress < milestone <= new_progress:
            if milestone == 100:
                title = translate("goal_achieved_title", lang)
                message = translate("goal_achieved_msg", lang, goal_name=goal_name)
                # [FIX] Added await
                await create_notification(
                    user_id=user_id,
                    notification_type="goal_achieved",
                    title=title,
                    message=message,
                    goal_id=goal_id,
                    goal_name=goal_name,
                    currency=currency
                )
            elif milestone in [25, 50, 75]:
                emoji = "💪" if milestone == 25 else "🎯" if milestone == 50 else "🎉"
                title = translate("goal_progress_title", lang, milestone=milestone, emoji=emoji)
                message = translate("goal_progress_msg", lang, milestone=milestone, goal_name=goal_name)
                # [FIX] Added await
                await create_notification(
                    user_id=user_id,
                    notification_type="goal_progress",
                    title=title,
                    message=message,
                    goal_id=goal_id,
                    goal_name=goal_name,
                    currency=currency
                )

async def check_milestone_amount(user_id: str, goal_id: str, old_amount: float, new_amount: float, goal_name: str):
    """Check for milestone amounts (every $1000 or 1M K)"""
    # [FIX] Added await
    goal = await goals_collection.find_one({"_id": goal_id})
    currency = goal.get("currency", "usd") if goal else "usd"
    # [FIX] Added await
    lang = await get_user_language(user_id)
    
    milestone_interval = 1000000 if currency == "mmk" else 1000
    
    old_milestone = int(old_amount / milestone_interval)
    new_milestone = int(new_amount / milestone_interval)
    
    if new_milestone > old_milestone:
        milestone_amount = new_milestone * milestone_interval
        formatted_amount = format_currency_amount(milestone_amount, currency)
        
        title = translate("goal_milestone_title", lang)
        message = translate("goal_milestone_msg", lang, amount=formatted_amount, goal_name=goal_name)
        
        # [FIX] Added await
        await create_notification(
            user_id=user_id,
            notification_type="goal_milestone",
            title=title,
            message=message,
            goal_id=goal_id,
            goal_name=goal_name,
            currency=currency
        )


async def check_approaching_target_dates():
    """Check all goals for approaching target dates (run daily)"""
    now = datetime.now(UTC)
    two_weeks_from_now = now + timedelta(days=14)
    one_week_from_now = now + timedelta(days=7)
    three_days_from_now = now + timedelta(days=3)
    
    # [FIX] Async cursor
    cursor = goals_collection.find({
        "status": "active",
        "target_date": {
            "$gte": now,
            "$lte": two_weeks_from_now
        }
    })
    
    goals = await cursor.to_list(length=None)
    
    for goal in goals:
        target_date = goal["target_date"]
        user_id = goal["user_id"]
        goal_id = goal["_id"]
        goal_name = goal["name"]
        remaining = goal["target_amount"] - goal["current_amount"]
        currency = goal.get("currency", "usd")
        # [FIX] Added await
        lang = await get_user_language(user_id)
        
        days_until = (target_date - now).days
        
        if days_until == 14 or days_until == 7 or days_until == 3:
            # [FIX] Added await
            existing = await notifications_collection.find_one({
                "user_id": user_id,
                "goal_id": goal_id,
                "type": "goal_approaching_date",
                "created_at": {"$gte": now - timedelta(hours=24)}
            })
            
            if not existing:
                time_text = f"{days_until} days" if days_until > 1 else "1 day"
                formatted_remaining = format_currency_amount(remaining, currency)
                
                title = translate("goal_approaching_title", lang)
                
                if remaining > 0:
                    message = translate("goal_approaching_msg_with_remaining", lang, 
                                      goal_name=goal_name, days=time_text, remaining=formatted_remaining)
                else:
                    message = translate("goal_approaching_msg_achieved", lang, 
                                      goal_name=goal_name, days=time_text)
                
                # [FIX] Added await
                await create_notification(
                    user_id=user_id,
                    notification_type="goal_approaching_date",
                    title=title,
                    message=message,
                    goal_id=goal_id,
                    goal_name=goal_name,
                    currency=currency
                )


async def check_budget_notifications(user_id: str, budget_id: str, old_percentage: float, new_percentage: float, budget_name: str, category_name: str = None):
    """Check and create budget threshold/exceeded notifications"""
    # [FIX] Added await
    budget = await budgets_collection.find_one({"_id": budget_id})
    currency = budget.get("currency", "usd") if budget else "usd"
    # [FIX] Added await
    lang = await get_user_language(user_id)
    
    budget_label = f"'{category_name}'" if category_name else ("overall" if lang == "en" else "စုစုပေါင်း")
    
    if old_percentage < 80 <= new_percentage < 100:
        title = translate("budget_threshold_title", lang)
        message = translate("budget_threshold_msg", lang, label=budget_label, budget_name=budget_name)
        # [FIX] Added await
        await create_notification(
            user_id=user_id,
            notification_type="budget_threshold",
            title=title,
            message=message,
            goal_id=budget_id,
            goal_name=budget_name,
            currency=currency
        )
    
    if old_percentage < 100 <= new_percentage:
        title = translate("budget_exceeded_title", lang)
        message = translate("budget_exceeded_msg", lang, label=budget_label, budget_name=budget_name)
        # [FIX] Added await
        await create_notification(
            user_id=user_id,
            notification_type="budget_exceeded",
            title=title,
            message=message,
            goal_id=budget_id,
            goal_name=budget_name,
            currency=currency
        )


async def check_budget_period_notifications():
    """Check all budgets for period start/end notifications (run daily)"""
    now = datetime.now(UTC)
    three_days_from_now = now + timedelta(days=3)
    
    # [FIX] Async cursor
    cursor_ending = budgets_collection.find({
        "status": "active",
        "end_date": {
            "$gte": now,
            "$lte": three_days_from_now
        }
    })
    budgets_ending = await cursor_ending.to_list(length=None)
    
    for budget in budgets_ending:
        user_id = budget["user_id"]
        budget_id = budget["_id"]
        budget_name = budget["name"]
        end_date = budget["end_date"]
        currency = budget.get("currency", "usd")
        # [FIX] Added await
        lang = await get_user_language(user_id)
        
        days_until_end = (end_date - now).days
        
        if days_until_end == 3:
            # [FIX] Added await
            existing = await notifications_collection.find_one({
                "user_id": user_id,
                "goal_id": budget_id,
                "type": "budget_ending_soon",
                "created_at": {"$gte": now - timedelta(hours=24)}
            })
            
            if not existing:
                title = translate("budget_ending_soon_title", lang)
                message = translate("budget_ending_soon_msg", lang, budget_name=budget_name)
                # [FIX] Added await
                await create_notification(
                    user_id=user_id,
                    notification_type="budget_ending_soon",
                    title=title,
                    message=message,
                    goal_id=budget_id,
                    goal_name=budget_name,
                    currency=currency
                )
    
    # [FIX] Async cursor
    cursor_active = budgets_collection.find({
        "status": "upcoming",
        "start_date": {"$lte": now}
    })
    budgets_now_active = await cursor_active.to_list(length=None)
    
    for budget in budgets_now_active:
        user_id = budget["user_id"]
        budget_id = budget["_id"]
        budget_name = budget["name"]
        total_budget = budget["total_budget"]
        currency = budget.get("currency", "usd")
        # [FIX] Added await
        lang = await get_user_language(user_id)
        formatted_budget = format_currency_amount(total_budget, currency)
        
        # [FIX] Added await
        existing = await notifications_collection.find_one({
            "user_id": user_id,
            "goal_id": budget_id,
            "type": "budget_now_active"
        })
        
        if not existing:
            title = translate("budget_now_active_title", lang)
            message = translate("budget_now_active_msg", lang, budget_name=budget_name, amount=formatted_budget)
            # [FIX] Added await
            await create_notification(
                user_id=user_id,
                notification_type="budget_now_active",
                title=title,
                message=message,
                goal_id=budget_id,
                goal_name=budget_name,
                currency=currency
            )


async def notify_budget_started(user_id: str, budget_id: str, budget_name: str, total_budget: float, period: str):
    """Notify when a new budget is created and started"""
    # [FIX] Added await
    budget = await budgets_collection.find_one({"_id": budget_id})
    currency = budget.get("currency", "usd") if budget else "usd"
    # [FIX] Added await
    lang = await get_user_language(user_id)
    formatted_budget = format_currency_amount(total_budget, currency)
    
    title = translate("budget_started_title", lang)
    message = translate("budget_started_msg", lang, budget_name=budget_name, period=period, amount=formatted_budget)
    
    # [FIX] Added await
    await create_notification(
        user_id=user_id,
        notification_type="budget_started",
        title=title,
        message=message,
        goal_id=budget_id,
        goal_name=budget_name,
        currency=currency
    )


async def notify_budget_auto_created(user_id: str, budget_id: str, budget_name: str, was_ai: bool):
    """Notify when a budget is auto-created"""
    # [FIX] Added await
    budget = await budgets_collection.find_one({"_id": budget_id})
    currency = budget.get("currency", "usd") if budget else "usd"
    # [FIX] Added await
    lang = await get_user_language(user_id)
    
    title = translate("budget_auto_created_title", lang)
    
    if was_ai:
        message = translate("budget_auto_created_msg_ai", lang, budget_name=budget_name)
    else:
        message = translate("budget_auto_created_msg", lang, budget_name=budget_name)
    
    # [FIX] Added await
    await create_notification(
        user_id=user_id,
        notification_type="budget_auto_created",
        title=title,
        message=message,
        goal_id=budget_id,
        goal_name=budget_name,
        currency=currency
    )


async def check_large_transaction(user_id: str, transaction: Dict, user_spending_profile: Dict = None):
    """Check if a transaction is unusually large and notify"""
    amount = transaction["amount"]
    transaction_type = transaction["type"]
    category = transaction["main_category"]
    description = transaction.get("description", "")
    currency = transaction.get("currency", "usd")
    # [FIX] Added await
    lang = await get_user_language(user_id)
    
    if transaction_type != "outflow":
        return
    
    if user_spending_profile and "avg_transaction" in user_spending_profile:
        threshold = user_spending_profile["avg_transaction"] * 3
        threshold = max(threshold, 100000 if currency == "mmk" else 100)
    else:
        threshold = 150000 if currency == "mmk" else 150
    
    if amount >= threshold:
        # [FIX] Added await
        existing = await notifications_collection.find_one({
            "user_id": user_id,
            "type": "large_transaction",
            "created_at": {"$gte": datetime.now(UTC) - timedelta(minutes=5)}
        })
        
        if not existing:
            merchant_info = f" at {description}" if description else ""
            if lang == "my" and description:
                merchant_info = f" {description} တွင်"
            
            formatted_amount = format_currency_amount(amount, currency)
            
            title = translate("large_transaction_title", lang)
            message = translate("large_transaction_msg", lang, 
                              amount=formatted_amount, merchant=merchant_info, category=category)
            
            # [FIX] Added await
            await create_notification(
                user_id=user_id,
                notification_type="large_transaction",
                title=title,
                message=message,
                goal_id=transaction["_id"],
                goal_name=f"Large {category} expense",
                currency=currency
            )


async def analyze_unusual_spending(user_id: str):
    """Analyze spending patterns and notify about unusual activity"""
    from collections import defaultdict
    
    now = datetime.now(UTC)
    # [FIX] Async distinct
    currencies = await transactions_collection.distinct("currency", {"user_id": user_id})
    # [FIX] Added await
    lang = await get_user_language(user_id)
    
    for currency in currencies:
        this_week_start = now - timedelta(days=7)
        # [FIX] Async cursor
        cursor = transactions_collection.find({
            "user_id": user_id,
            "type": "outflow",
            "currency": currency,
            "date": {"$gte": this_week_start}
        })
        this_week_transactions = await cursor.to_list(length=None)
        
        last_month_start = now - timedelta(days=35)
        last_month_end = this_week_start
        # [FIX] Async cursor
        cursor = transactions_collection.find({
            "user_id": user_id,
            "type": "outflow",
            "currency": currency,
            "date": {"$gte": last_month_start, "$lt": last_month_end}
        })
        last_month_transactions = await cursor.to_list(length=None)
        
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
            min_diff = 50000 if currency == "mmk" else 50
            
            if this_week_amount > weekly_avg * 1.5 and this_week_amount - weekly_avg > min_diff:
                # [FIX] Added await
                existing = await notifications_collection.find_one({
                    "user_id": user_id,
                    "type": "unusual_spending",
                    "goal_name": category,
                    "currency": currency,
                    "created_at": {"$gte": this_week_start}
                })
                
                if not existing:
                    formatted_this_week = format_currency_amount(this_week_amount, currency)
                    formatted_avg = format_currency_amount(weekly_avg, currency)
                    
                    title = translate("unusual_spending_title", lang)
                    message = translate("unusual_spending_msg", lang, 
                                      category=category, this_week=formatted_this_week, avg=formatted_avg)
                    
                    # [FIX] Added await
                    await create_notification(
                        user_id=user_id,
                        notification_type="unusual_spending",
                        title=title,
                        message=message,
                        goal_id=None,
                        goal_name=category,
                        currency=currency
                    )


async def detect_and_notify_recurring_payments():
    """Detect recurring payments and send reminders"""
    from collections import defaultdict
    
    now = datetime.now(UTC)
    # [FIX] Async cursor for users
    cursor_users = users_collection.find({})
    users = await cursor_users.to_list(length=None)
    
    for user in users:
        user_id = user["_id"]
        # [FIX] Added await
        lang = await get_user_language(user_id)
        # [FIX] Async distinct
        currencies = await transactions_collection.distinct("currency", {"user_id": user_id})
        
        for currency in currencies:
            ninety_days_ago = now - timedelta(days=90)
            # [FIX] Async cursor
            cursor = transactions_collection.find({
                "user_id": user_id,
                "type": "outflow",
                "currency": currency,
                "date": {"$gte": ninety_days_ago}
            })
            transactions = await cursor.to_list(length=None)
            
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
                        # [FIX] Added await
                        existing = await notifications_collection.find_one({
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
                            
                            title = translate("payment_reminder_title", lang)
                            message = translate("payment_reminder_msg", lang, 
                                              description=description, amount=formatted_amount, days=days_until)
                            
                            # [FIX] Added await
                            await create_notification(
                                user_id=user_id,
                                notification_type="payment_reminder",
                                title=title,
                                message=message,
                                goal_id=None,
                                goal_name=key,
                                currency=currency
                            )


async def notify_monthly_insights_generated(user_id: str):
    """Notify when monthly insights are generated"""
    # [FIX] Added await
    lang = await get_user_language(user_id)
    
    title = translate("monthly_insights_title", lang)
    message = translate("monthly_insights_msg", lang)
    
    # [FIX] Added await
    await create_notification(
        user_id=user_id,
        notification_type="monthly_insights_generated",
        title=title,
        message=message,
        goal_id=None,
        goal_name="Monthly Insights Tailored For You" if lang == "en" else "သင့်အတွက် ပြင်ဆင်ထားသော လစဉ်ထိုးထွင်းသိမြင်မှုများ",
        currency=None
    )


async def notify_weekly_insights_generated(user_id: str):
    """Notify when weekly insights are generated"""
    # [FIX] Added await
    lang = await get_user_language(user_id)
    
    title = translate("weekly_insights_title", lang)
    message = translate("weekly_insights_msg", lang)
    
    # [FIX] Added await
    await create_notification(
        user_id=user_id,
        notification_type="weekly_insights_generated",
        title=title,
        message=message,
        goal_id=None,
        goal_name="Weekly Insights Tailored For You" if lang == "en" else "သင့်အတွက် ပြင်ဆင်ထားသော အပတ်စဉ်ထိုးထွင်းသိမြင်မှုများ",
        currency=None
    )