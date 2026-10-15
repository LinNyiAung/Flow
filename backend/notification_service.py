import asyncio
from datetime import datetime, UTC, timedelta
import threading
from typing import Dict, List, Optional
import uuid
from firebase_service import send_fcm_notification
from finite_utils import finite_amount_filter
from database import goals_collection, notification_preferences_collection, notifications_collection, budgets_collection, transactions_collection, users_collection
from tz_utils import (
    app_today, app_wall_clock_now, as_utc, days_until, goal_reminder_threshold, is_budget_ending_soon,
    GOAL_REMINDER_THRESHOLDS, BUDGET_ENDING_SOON_DAYS,
)

# The daily job only announces budgets whose start date is at most this many days ago
# (covers a missed run without spamming long-running legacy budgets on rollout).
BUDGET_NOW_ACTIVE_LOOKBACK_DAYS = 2

# Strong references to fire-and-forget tasks (FCM sends). The event loop only keeps weak
# references, so un-referenced tasks can be garbage-collected before they finish.
_background_tasks: set = set()


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
        "budget_ending_soon_msg": "Your '{budget_name}' budget period ends in {days}. Review your spending to see how you did!",
        "budget_ending_today_msg": "Your '{budget_name}' budget period ends today. Review your spending to see how you did!",
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
        "subscription_expired_title": "Your Premium Has Ended",
        "subscription_expired_msg": "Your Toe Pwar Premium ended on {date}. Upgrade any time to keep using AI insights, the AI assistant and other premium features.",
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
        "budget_ending_soon_msg": "'{budget_name}' ဘတ်ဂျက်ကာလကုန်ဆုံးရန် {days} ရက်သာ လိုပါတော့တယ်။ သင်၏အသုံးစရိတ်များကို ပြန်လည်သုံးသပ်ကြည့်လိုက်ပါ။",
        "budget_ending_today_msg": "'{budget_name}' ဘတ်ဂျက်ကာလ ယနေ့ ကုန်ဆုံးပါမည်။ သင်၏အသုံးစရိတ်များကို ပြန်လည်သုံးသပ်ကြည့်လိုက်ပါ။",
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
        "monthly_insights_msg": "Toe Pwar AI မှ ထုတ်ပြန်ပေးသော သင်၏ လစဉ် ဘဏ္ဍာရေးသုံးသပ်ချက်များ ရရှိနိုင်ပါပြီ။ တစ်လတာ တိုးတက်မှုများကို စစ်ဆေးကြည့်လိုက်ပါ။",
        "subscription_expired_title": "Premium အသုံးပြုခွင့် ကုန်ဆုံးသွားပါပြီ",
        "subscription_expired_msg": "သင်၏ Toe Pwar Premium သည် {date} တွင် ကုန်ဆုံးသွားပါပြီ။ AI သုံးသပ်ချက်များ၊ AI လက်ထောက်နှင့် အခြား Premium လုပ်ဆောင်ချက်များကို ဆက်လက်အသုံးပြုရန် အချိန်မရွေး အဆင့်မြှင့်တင်နိုင်ပါသည်။"
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
    currency: Optional[str] = None,
    extra: Optional[dict] = None
) -> Optional[dict]:
    """Create a new notification (only if user has it enabled).

    extra: additional fields stored on the notification document (e.g. dedupe keys);
    they are not sent in the push payload.
    """
    
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
    if extra:
        for key, value in extra.items():
            notification.setdefault(key, value)

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
        # Schedule the blocking sync function in a separate thread, managed by the loop.
        # Keep a strong reference until it completes so it can't be garbage-collected.
        task = loop.create_task(asyncio.to_thread(send_background_fcm))
        _background_tasks.add(task)
        task.add_done_callback(_background_tasks.discard)
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


def _days_text(days: int, lang: str) -> str:
    """Days phrase for templates. Myanmar templates already contain 'ရက်' after {days}."""
    if lang == "my":
        return str(days)
    return "1 day" if days == 1 else f"{days} days"


async def check_approaching_target_dates():
    """
    Check active goals for approaching target dates (run once daily).

    Days remaining are counted in calendar days: the goal's stored target date vs. today
    in the app timezone. Each goal gets at most one reminder per threshold (14/7/3/1 days)
    for a given target date; thresholds are matched as ranges (e.g. 8-14 days -> the
    14-day reminder) so a missed run or a goal created inside a window still gets it.
    """
    today = app_today()
    max_days = max(GOAL_REMINDER_THRESHOLDS)
    window_start = datetime.combine(today - timedelta(days=1), datetime.min.time(), tzinfo=UTC)
    window_end = datetime.combine(today + timedelta(days=max_days + 1), datetime.max.time(), tzinfo=UTC)

    cursor = goals_collection.find({
        "status": "active",
        "target_date": {"$gte": window_start, "$lte": window_end}
    })
    goals = await cursor.to_list(length=None)

    for goal in goals:
        try:
            target_date = goal.get("target_date")
            if not target_date:
                continue

            days_remaining = days_until(target_date, today)
            threshold = goal_reminder_threshold(days_remaining)
            if threshold is None:
                continue

            user_id = goal["user_id"]
            goal_id = goal["_id"]
            target_key = as_utc(target_date).date().isoformat()

            # Dedupe per goal + threshold + target date (a changed target date re-arms
            # the reminders). The 20h check also covers notifications created before
            # these keys existed, so nobody gets a duplicate on rollout.
            existing = await notifications_collection.find_one({
                "user_id": user_id,
                "goal_id": goal_id,
                "type": "goal_approaching_date",
                "$or": [
                    {"reminder_threshold": threshold, "reminder_target_date": target_key},
                    {"created_at": {"$gte": datetime.now(UTC) - timedelta(hours=20)}},
                ],
            })
            if existing:
                continue

            goal_name = goal["name"]
            remaining = (goal.get("target_amount") or 0) - (goal.get("current_amount") or 0)
            currency = goal.get("currency", "usd")
            lang = await get_user_language(user_id)
            time_text = _days_text(days_remaining, lang)

            title = translate("goal_approaching_title", lang)
            if remaining > 0:
                message = translate("goal_approaching_msg_with_remaining", lang,
                                    goal_name=goal_name, days=time_text,
                                    remaining=format_currency_amount(remaining, currency))
            else:
                message = translate("goal_approaching_msg_achieved", lang,
                                    goal_name=goal_name, days=time_text)

            await create_notification(
                user_id=user_id,
                notification_type="goal_approaching_date",
                title=title,
                message=message,
                goal_id=goal_id,
                goal_name=goal_name,
                currency=currency,
                extra={"reminder_threshold": threshold, "reminder_target_date": target_key},
            )
        except Exception as e:
            print(f"❌ Error checking target date for goal {goal.get('_id')}: {e}")

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
    today = app_today(now)

    from budget_service import is_budget_running, refresh_budget_state_if_stale  # local: avoid import cycle

    wall_now = app_wall_clock_now(now)

    # --- Part 1: running budgets ending within BUDGET_ENDING_SOON_DAYS (by calendar date) ---
    # "Running" = window contains now (app wall clock) and status active OR exceeded (an
    # exceeded budget is still running and must get the alert). Stored statuses can be
    # stale (still "upcoming" after the start date), so candidates are refreshed first.
    try:
        window_start = datetime.combine(today - timedelta(days=1), datetime.min.time(), tzinfo=UTC)
        window_end = datetime.combine(today + timedelta(days=BUDGET_ENDING_SOON_DAYS + 1), datetime.max.time(), tzinfo=UTC)
        cursor_ending = budgets_collection.find({
            "status": {"$in": ["upcoming", "active", "exceeded"]},
            "start_date": {"$lte": wall_now},
            "end_date": {"$gte": window_start, "$lte": window_end},
            "ending_soon_notified": {"$ne": True},
        })
        budgets_ending = await cursor_ending.to_list(length=None)
    except Exception as e:
        print(f"❌ Error loading budgets ending soon: {e}")
        budgets_ending = []

    for budget in budgets_ending:
        try:
            budget = await refresh_budget_state_if_stale(budget)
            if not is_budget_running(budget, now):
                continue
            end_date = budget.get("end_date")
            if not end_date:
                continue
            days_until_end = days_until(end_date, today)
            if not is_budget_ending_soon(days_until_end):
                continue

            user_id = budget["user_id"]
            budget_id = budget["_id"]

            # Budget ids are per period, so one "ending soon" per budget ever. The flag is
            # claimed atomically (overlapping runs can't both send); budgets notified
            # before the flag existed are detected by their notification and just flagged.
            claim = await budgets_collection.update_one(
                {"_id": budget_id, "ending_soon_notified": {"$ne": True}},
                {"$set": {"ending_soon_notified": True, "ending_soon_notified_at": now}},
            )
            if claim.modified_count == 0:
                continue
            existing = await notifications_collection.find_one({
                "user_id": user_id,
                "goal_id": budget_id,
                "type": "budget_ending_soon",
            })
            if existing:
                continue

            budget_name = budget["name"]
            currency = budget.get("currency", "usd")
            lang = await get_user_language(user_id)

            title = translate("budget_ending_soon_title", lang)
            if days_until_end == 0:
                message = translate("budget_ending_today_msg", lang, budget_name=budget_name)
            else:
                message = translate("budget_ending_soon_msg", lang, budget_name=budget_name,
                                    days=_days_text(days_until_end, lang))

            try:
                await create_notification(
                    user_id=user_id,
                    notification_type="budget_ending_soon",
                    title=title,
                    message=message,
                    goal_id=budget_id,
                    goal_name=budget_name,
                    currency=currency
                )
            except Exception:
                # Release the claim so the next run can retry.
                await budgets_collection.update_one(
                    {"_id": budget_id}, {"$unset": {"ending_soon_notified": "", "ending_soon_notified_at": ""}}
                )
                raise
        except Exception as e:
            print(f"❌ Error checking budget end for {budget.get('_id')}: {e}")

    # --- Part 2: budgets whose start date has arrived and that were never announced ---
    # Status may already have been flipped upcoming -> active by a list/get refresh, so
    # select by dates + the started_notified flag instead of status == "upcoming".
    try:
        lookback_start = datetime.combine(
            today - timedelta(days=BUDGET_NOW_ACTIVE_LOOKBACK_DAYS), datetime.min.time(), tzinfo=UTC
        )
        cursor_active = budgets_collection.find({
            "status": {"$in": ["upcoming", "active", "exceeded"]},
            "started_notified": {"$ne": True},
            "start_date": {"$gte": lookback_start, "$lte": wall_now},
            "end_date": {"$gte": wall_now},
        })
        budgets_now_active = await cursor_active.to_list(length=None)
    except Exception as e:
        print(f"❌ Error loading started budgets: {e}")
        budgets_now_active = []

    for budget in budgets_now_active:
        try:
            if budget.get("status") == "upcoming":
                # Persist the real status; the recompute itself sends the notification.
                budget = await refresh_budget_state_if_stale(budget)
            if budget.get("status") in ("active", "exceeded"):
                await notify_budget_now_active_once(budget)
        except Exception as e:
            print(f"❌ Error sending budget-now-active for {budget.get('_id')}: {e}")


async def notify_budget_now_active_once(budget: Dict) -> bool:
    """Send the "budget now active" notification exactly once per budget.

    The started_notified flag is claimed atomically, so the daily job and the
    upcoming -> active recompute path can't both send it. Budgets that already have a
    budget_now_active / budget_started notification (pre-flag data) are only flagged.
    Returns True if a notification was sent.
    """
    budget_id = budget["_id"]
    user_id = budget["user_id"]
    claim = await budgets_collection.update_one(
        {"_id": budget_id, "started_notified": {"$ne": True}},
        {"$set": {"started_notified": True, "started_notified_at": datetime.now(UTC)}},
    )
    if claim.modified_count == 0:
        return False

    existing = await notifications_collection.find_one({
        "user_id": user_id,
        "goal_id": budget_id,
        "type": {"$in": ["budget_now_active", "budget_started"]},
    })
    if existing:
        return False

    budget_name = budget["name"]
    currency = budget.get("currency", "usd")
    lang = await get_user_language(user_id)
    formatted_budget = format_currency_amount(budget.get("total_budget") or 0, currency)

    title = translate("budget_now_active_title", lang)
    message = translate("budget_now_active_msg", lang, budget_name=budget_name, amount=formatted_budget)
    await create_notification(
        user_id=user_id,
        notification_type="budget_now_active",
        title=title,
        message=message,
        goal_id=budget_id,
        goal_name=budget_name,
        currency=currency
    )
    return True

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
    # Transaction dates are local wall-clock values stored tagged as UTC, so the "this
    # week" window is measured on the app-timezone wall clock (created_at stays real UTC).
    wall_now = app_wall_clock_now(now)
    # [FIX] Async distinct
    currencies = await transactions_collection.distinct("currency", {"user_id": user_id})
    # [FIX] Added await
    lang = await get_user_language(user_id)

    # Upper bound of the "this week" window: end of today on the app wall clock, so
    # future-dated (planned) transactions don't count as this week's spending.
    end_of_today = wall_now.replace(hour=23, minute=59, second=59, microsecond=999999)

    for currency in currencies:
        this_week_start = wall_now - timedelta(days=7)
        recent_notification_cutoff = now - timedelta(days=7)
        # [FIX] Async cursor
        cursor = transactions_collection.find({
            "user_id": user_id,
            "type": "outflow",
            "currency": currency,
            "date": {"$gte": this_week_start, "$lte": end_of_today},
            **finite_amount_filter(),
        })
        this_week_transactions = await cursor.to_list(length=None)
        
        last_month_start = wall_now - timedelta(days=35)
        last_month_end = this_week_start
        # [FIX] Async cursor
        cursor = transactions_collection.find({
            "user_id": user_id,
            "type": "outflow",
            "currency": currency,
            "date": {"$gte": last_month_start, "$lt": last_month_end},
            **finite_amount_filter(),
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
                    "created_at": {"$gte": recent_notification_cutoff}
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


async def _detect_recurring_payments_for_user(user_id: str, now: datetime, today):
    """Detect monthly recurring outflows for one user and send due-soon reminders."""
    from collections import defaultdict

    lang = await get_user_language(user_id)
    currencies = await transactions_collection.distinct("currency", {"user_id": user_id})

    for currency in currencies:
        ninety_days_ago = now - timedelta(days=90)
        cursor = transactions_collection.find({
            "user_id": user_id,
            "type": "outflow",
            "currency": currency,
            "date": {"$gte": ninety_days_ago},
            **finite_amount_filter(),
        })
        transactions = await cursor.to_list(length=None)

        if len(transactions) < 10:
            continue

        recurring_patterns = defaultdict(list)

        for t in transactions:
            if not t.get("date"):
                continue
            sub_category = t.get("sub_category") or ""
            key = (t.get("description") or "").lower().strip()
            if not key:
                key = sub_category.lower().strip()

            if len(key) < 3 or key in ["payment", "purchase", "expense"]:
                continue

            recurring_patterns[key].append({
                "date": as_utc(t["date"]),
                "amount": t.get("amount") or 0,
                "category": t.get("main_category"),
                "sub_category": sub_category,
                "description": t.get("description") or sub_category or key
            })

        for key, occurrences in recurring_patterns.items():
            if len(occurrences) < 2:
                continue

            occurrences.sort(key=lambda x: x["date"])

            intervals = [
                (occurrences[i]["date"] - occurrences[i - 1]["date"]).days
                for i in range(1, len(occurrences))
            ]
            if not intervals:
                continue

            avg_interval = sum(intervals) / len(intervals)
            if not (28 <= avg_interval <= 32):
                continue

            next_expected = occurrences[-1]["date"] + timedelta(days=int(avg_interval))
            days_until_due = days_until(next_expected, today)

            if not (2 <= days_until_due <= 4):
                continue

            existing = await notifications_collection.find_one({
                "user_id": user_id,
                "type": "payment_reminder",
                "goal_name": key,
                "currency": currency,
                "created_at": {"$gte": now - timedelta(days=7)}
            })
            if existing:
                continue

            formatted_amount = format_currency_amount(occurrences[-1]["amount"], currency)
            title = translate("payment_reminder_title", lang)
            message = translate("payment_reminder_msg", lang,
                                description=occurrences[-1]["description"],
                                amount=formatted_amount, days=days_until_due)

            await create_notification(
                user_id=user_id,
                notification_type="payment_reminder",
                title=title,
                message=message,
                goal_id=None,
                goal_name=key,
                currency=currency
            )


async def detect_and_notify_recurring_payments():
    """Detect recurring payments and send reminders"""
    now = datetime.now(UTC)
    today = app_today(now)

    cursor_users = users_collection.find({}, {"_id": 1})
    users = await cursor_users.to_list(length=None)

    for user in users:
        try:
            await _detect_recurring_payments_for_user(user["_id"], now, today)
        except Exception as e:
            print(f"❌ Error detecting recurring payments for user {user.get('_id')}: {e}")

async def _recent_notification_exists(user_id: str, notification_type: str, within: timedelta) -> bool:
    existing = await notifications_collection.find_one({
        "user_id": user_id,
        "type": notification_type,
        "created_at": {"$gte": datetime.now(UTC) - within},
    })
    return existing is not None


async def notify_monthly_insights_generated(user_id: str):
    """Notify when monthly insights are generated (at most once per hour per user)"""
    if await _recent_notification_exists(user_id, "monthly_insights_generated", timedelta(hours=1)):
        print(f"Skipping duplicate monthly_insights_generated notification for user {user_id}")
        return None

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
    """Notify when weekly insights are generated (at most once per hour per user)"""
    if await _recent_notification_exists(user_id, "weekly_insights_generated", timedelta(hours=1)):
        print(f"Skipping duplicate weekly_insights_generated notification for user {user_id}")
        return None

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