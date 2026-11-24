import asyncio
from datetime import date, datetime, UTC, timedelta, tzinfo
from typing import Any, Dict, List, Optional, Tuple
import uuid
from firebase_service import send_push
from sql import budgets as budgets_db
from sql import devices as devices_db
from sql import families as families_db
from sql import transactions as transactions_db
from sql import goals as goals_db
from sql import notifications as notifications_db
from sql import notification_prefs as prefs_db
from sql import books as books_db
from sql import users as users_db
from plans.access import format_day
from tz_utils import (
    as_calendar_date, as_wall_clock, days_until, goal_reminder_threshold, is_budget_ending_soon, local_now,
    GOAL_REMINDER_THRESHOLDS, BUDGET_ENDING_SOON_DAYS,
)
from user_zones import person_zone

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
        "budget_auto_created_msg_ai": "Your '{budget_name}' budget has ended. Ko Toe Pwar created a new budget for the next period, tuned to your spending.",
        "budget_auto_created_msg": "Your '{budget_name}' budget has ended. A new budget for the next period has been created based on your previous budget.",
        "large_transaction_title": "Large Transaction Alert 💰",
        "large_transaction_msg": "You had a large expense of {amount}{merchant} for {category}.",
        "unusual_spending_title": "Unusual Spending Detected 📊",
        "unusual_spending_msg": "Your spending on '{category}' is higher than usual this week ({this_week} vs usual {avg}). Would you like to review these transactions?",
        "payment_reminder_title": "Upcoming Payment Reminder 📅",
        "payment_reminder_msg": "Your '{description}' payment of {amount} is due in {days} days.",
        "weekly_insights_title": "Weekly Insights Ready! 📊",
        "weekly_insights_msg": "Your weekly financial insights from Ko Toe Pwar are now available. Check them out to see your financial progress!",
        "monthly_insights_title": "Monthly Insights Ready! 📊",
        "monthly_insights_msg": "Your monthly financial insights from Ko Toe Pwar are now available. Check them out to see your monthly financial progress!",
        "custom_insight_ready_title": "Your custom insight is ready 📊",
        "custom_insight_ready_msg": "Your insight for {range} is ready. Tap to read it.",
        "custom_insight_failed_title": "Custom insight not created",
        "custom_insight_failed_msg": "We couldn't create your insight for {range}. It wasn't counted, so you can try again.",
        "custom_insight_refused_msg": "That isn't something I can answer from your finances, so no insight was created for {range}. It wasn't counted.",
        "custom_insight_range_msg": "Choose from 7 days to 12 months, ending today or earlier.",
        "custom_insight_instruction_msg": "Use one ready-made instruction or your own, of at most 300 characters.",
        "custom_insight_instruction_chars_msg": "Your instruction contains characters that can't be used. Please remove them and try again.",
        "custom_insight_no_data_msg": "There are no transactions in these dates, so there is nothing to report on.",
        "custom_insight_pending_msg": "Your previous custom insight is still being created. Please wait until it's ready.",
        "custom_insight_attempts_msg": "The limit of 5 custom insights that couldn't be created in 24 hours has been reached. Please try again later.",
        "custom_insight_not_ready_msg": "This custom insight isn't ready yet.",
        "subscription_expired_title": "Your {plan} Plan Has Ended",
        "subscription_expired_msg": "Your Toe Pwar {plan} plan ended on {date}, so you're back on the Free plan. Upgrade any time to get your AI allowances and {plan} features back.",
        "trial_ending_soon_title": "Your {plan} Trial Ends Soon",
        "trial_ending_soon_msg": "Your free Toe Pwar {plan} trial ends on {date}. Upgrade before then to keep your AI allowances and {plan} features.",
        "trial_ends_today_title": "Last Day of Your {plan} Trial",
        "trial_ends_today_msg": "Your free Toe Pwar {plan} trial ends within 24 hours, on {date}. Upgrade now to keep your AI allowances and {plan} features.",
        "plan_ending_soon_title": "Your {plan} Plan Ends Soon",
        "plan_ending_soon_msg": "Your Toe Pwar {plan} plan ends on {date}. Renew before then to keep your AI allowances and {plan} features.",
        "plan_ends_today_title": "Your {plan} Plan Ends Within 24 Hours",
        "plan_ends_today_msg": "Your Toe Pwar {plan} plan ends within 24 hours, on {date}. Renew now to keep your AI allowances and {plan} features.",
        "plan_activated_title": "Your {plan} Plan Is Active",
        "plan_activated_msg": "Your {plan} plan is now active.",
        "plan_activated_msg_until": "Your {plan} plan is now active. It runs until {date}.",
        "upgrade_request_declined_title": "Upgrade Request Closed",
        "upgrade_request_declined_msg": "Your request for {plan} was closed. {contact}",
        "upgrade_request_contact_default": "Contact us if you have questions.",
        "contact_email_label": "Email",
        "contact_viber_label": "Viber",
        "contact_telegram_label": "Telegram",
        "contact_facebook_label": "Facebook",
        "contact_messenger_label": "Messenger",
        "plan_paid_required_msg": "This feature is only available on the Plus and Pro plans.",
        # Plan limit responses (plans.access.PlanError). Feature names are used inside the messages.
        "plan_feature_chat": "AI chat",
        "plan_feature_chat_advanced": "Advanced chat",
        "plan_feature_insight_monthly": "monthly insights",
        "plan_feature_insight_weekly": "weekly insights",
        "plan_feature_insight_translation": "insight translation",
        "plan_feature_insight_custom": "custom insights",
        "plan_feature_entry": "AI entries (receipt, text and voice)",
        "plan_feature_budget_suggestion": "AI budget suggestions",
        "plan_feature_reports": "reports",
        "plan_feature_locked_msg": "Your plan doesn't include {feature}.",
        "plan_limit_reached_msg": "You've reached your limit for {feature}. It resets on {date}.",
        "plan_cost_cap_msg": "You've reached this month's AI limit; it resets on {date}.",
        "plan_upgrade_to_unlock": "Upgrade your plan to use it.",
        "plan_upgrade_for_more": "Upgrade your plan to get more.",
        "plan_upgrade_request_already": "You're already on the {plan} plan or a higher one.",
        # Ko Toe Pwar (the AI helper) couldn't answer: the chat's error frame and the budget ideas.
        "chat_unavailable_msg": "Ko Toe Pwar can't answer right now. Please try again in a moment.",
        "budget_ai_unavailable_msg": "Ko Toe Pwar can't suggest a budget right now. Please try again in a moment.",
        "budget_ai_rules_fallback_msg": "Ko Toe Pwar can't answer right now, so these suggestions use simple rules instead.",
        "insight_translation_failed_msg": "The Myanmar translation isn't available right now, so this report is in English. Try again later.",
        "chat_no_data_msg": "I don't have any of your financial data yet. Add some transactions, goals or budgets first, and I can help!",
        # Family book: notifications, and the refusals of /api/family (families.service; keys family_<code>_msg).
        "family_invite_title": "Family invitation",
        "family_invite_msg": "{inviter} invited you to join the family '{family_name}'. Open Family to join or decline.",
        "family_invite_accepted_title": "New family member",
        "family_invite_accepted_msg": "{name} joined the family '{family_name}'.",
        "family_removed_title": "Removed from family",
        "family_removed_msg": "You were removed from the family '{family_name}'. Your personal book isn't affected.",
        "family_owner_title": "You're the family owner now",
        "family_owner_msg": "The owner of the family '{family_name}' deleted their account, so you're its owner now.",
        "family_no_family_msg": "You're not in a family.",
        "family_already_in_family_msg": "You're already in a family. Leave it before joining another.",
        "family_not_allowed_msg": "You don't have permission to do this in the family.",
        "family_not_found_msg": "That member or invitation isn't in your family.",
        "family_family_full_msg": "The family already has as many members as it can have.",
        "family_placeholders_full_msg": "The family already has as many name-only members as it can have.",
        "family_plan_required_msg": "Creating a family needs the Plus or Pro plan.",
        "family_invite_invalid_msg": "This invitation can't be used. It may have expired or been cancelled.",
        "family_owner_must_hand_over_msg": "You're the owner. Hand ownership to another member before you leave.",
        "family_confirm_mismatch_msg": "The name you typed doesn't match the family name.",
        "family_family_read_only_msg": "The family is read-only because the owner's plan has ended. The owner can renew, or hand ownership to a member on Plus or Pro.",
        "family_invalid_book_msg": "Unknown book. Choose Personal or Family.",
        "family_invalid_month_msg": "That month can't be shown. Choose a month between 1900 and 2999.",
        "family_invalid_for_whom_msg": "Choose who it's for from the family's current members.",
        "family_transfer_insufficient_msg": "There isn't enough money available in that wallet for this.",
        "family_transfer_not_editable_msg": "A transfer can't be changed. Undo it and make a new one.",
        "family_use_transfer_undo_msg": "This is a transfer. Undo the transfer to remove both sides together.",
        "family_transfer_not_found_msg": "That transfer wasn't found.",
        "family_transfer_gone_msg": "This transfer can't be undone because one side of it no longer exists.",
        # Push-only (no in-app notification, so not in NOTIFICATION_LINKS): sent once to a device whose sign-in expired.
        "sign_in_reminder_title": "Sign in to Toe Pwar",
        "sign_in_reminder_msg": "You've been signed out. Sign in to keep getting your budget and goal alerts.",
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
        "budget_auto_created_msg_ai": "'{budget_name}' ဘတ်ဂျက်ကာလ ကုန်ဆုံးသွားပါပြီ။ ကိုတိုးပွားက သင့်သုံးစွဲမှုနှင့် ကိုက်ညီအောင် ချိန်ညှိ၍ နောက်ကာလအတွက် ဘတ်ဂျက်အသစ်တစ်ခုကို ဖန်တီးပေးထားပါသည်။",
        "budget_auto_created_msg": "'{budget_name}' ဘတ်ဂျက်ကာလ ကုန်ဆုံးသွားပါပြီ။ ယခင်အသုံးစရိတ်များအပေါ် အခြေခံ၍ နောက်ကာလအတွက် ဘတ်ဂျက်အသစ်တစ်ခုကို အလိုအလျောက် ဖန်တီးပေးထားပါသည်။",
        "large_transaction_title": "အသုံးစရိတ်ပမာဏ များပြားမှု သတိပေးချက် 💰",
        "large_transaction_msg": "{category} အတွက် {merchant} တွင် {amount} ပမာဏရှိသော အသုံးစရိတ်တစ်ခု ရှိခဲ့ပါသည်။",
        "unusual_spending_title": "ပုံမှန်မဟုတ်သော အသုံးစရိတ် တွေ့ရှိရသည် 📊",
        "unusual_spending_msg": "ယခုအပတ်တွင် '{category}' အတွက် အသုံးစရိတ်သည် ပုံမှန်ထက် ပိုများနေပါသည် (ပုံမှန် {avg} ဖြစ်သော်လည်း ယခုအပတ်တွင် {this_week} ဖြစ်နေသည်)။ ဤအသုံးစရိတ်များကို ပြန်လည်စစ်ဆေးလိုပါသလား?",
        "payment_reminder_title": "ပေးချေရန်ရှိသည်များကို သတိပေးခြင်း 📅",
        "payment_reminder_msg": "'{description}' အတွက် ပေးချေရန် {amount} ရှိပြီး နောက်ထပ် {days} ရက်အတွင်း ပေးချေရပါမည်။",
        "weekly_insights_title": "အပတ်စဉ်သုံးသပ်ချက် အဆင်သင့်ဖြစ်ပါပြီ! 📊",
        "weekly_insights_msg": "ကိုတိုးပွားမှ ထုတ်ပြန်ပေးသော သင်၏ အပတ်စဉ် ဘဏ္ဍာရေးသုံးသပ်ချက်များ ရရှိနိုင်ပါပြီ။ သင်၏ တိုးတက်မှုများကို စစ်ဆေးကြည့်လိုက်ပါ။",
        "monthly_insights_title": "လစဉ်သုံးသပ်ချက် အဆင်သင့်ဖြစ်ပါပြီ! 📊",
        "monthly_insights_msg": "ကိုတိုးပွားမှ ထုတ်ပြန်ပေးသော သင်၏ လစဉ် ဘဏ္ဍာရေးသုံးသပ်ချက်များ ရရှိနိုင်ပါပြီ။ တစ်လတာ တိုးတက်မှုများကို စစ်ဆေးကြည့်လိုက်ပါ။",
        "custom_insight_ready_title": "သင်၏ စိတ်ကြိုက်သုံးသပ်ချက် အဆင်သင့်ဖြစ်ပါပြီ 📊",
        "custom_insight_ready_msg": "{range} အတွက် သင်၏ သုံးသပ်ချက် အဆင်သင့်ဖြစ်ပါပြီ။ ဖတ်ရန် နှိပ်ပါ။",
        "custom_insight_failed_title": "စိတ်ကြိုက်သုံးသပ်ချက် မဖန်တီးနိုင်ပါ",
        "custom_insight_failed_msg": "{range} အတွက် သင်၏ သုံးသပ်ချက်ကို မဖန်တီးနိုင်ခဲ့ပါ။ အသုံးပြုခွင့်မှ မနှုတ်ထားသဖြင့် ထပ်မံကြိုးစားနိုင်ပါသည်။",
        "custom_insight_refused_msg": "၎င်းမေးခွန်းကို သင်၏ ငွေကြေးအချက်အလက်များမှ ဖြေကြားပေး၍ မရသဖြင့် {range} အတွက် သုံးသပ်ချက် မဖန်တီးခဲ့ပါ။ အသုံးပြုခွင့်မှ မနှုတ်ထားပါ။",
        "custom_insight_range_msg": "7 ရက်မှ 12 လအတွင်း ရွေးချယ်ပါ။ ယနေ့ သို့မဟုတ် ယနေ့မတိုင်မီ ရက်တွင် ပြီးဆုံးရပါမည်။",
        "custom_insight_instruction_msg": "အသင့်ပြင်ဆင်ထားသော ညွှန်ကြားချက်တစ်ခု သို့မဟုတ် ကိုယ်တိုင်ရေးသော ညွှန်ကြားချက်ကို အက္ခရာ 300 ထက် မပိုစေဘဲ အသုံးပြုပါ။",
        "custom_insight_instruction_chars_msg": "သင်၏ ညွှန်ကြားချက်တွင် အသုံးပြု၍မရသော စာလုံးများ ပါဝင်နေပါသည်။ ၎င်းတို့ကို ဖယ်ရှားပြီး ထပ်မံကြိုးစားပါ။",
        "custom_insight_no_data_msg": "ဤရက်များတွင် ငွေစာရင်းမရှိသဖြင့် သုံးသပ်ရန် မရှိပါ။",
        "custom_insight_pending_msg": "သင်၏ ယခင်စိတ်ကြိုက်သုံးသပ်ချက်ကို ဖန်တီးနေဆဲဖြစ်ပါသည်။ အဆင်သင့်ဖြစ်သည်အထိ ခဏစောင့်ပါ။",
        "custom_insight_attempts_msg": "၂၄ နာရီအတွင်း ဖန်တီး၍မရခဲ့သော စိတ်ကြိုက်သုံးသပ်ချက် 5 ခု၏ ကန့်သတ်ချက်သို့ ရောက်ရှိပါပြီ။ နောက်မှ ထပ်မံကြိုးစားပါ။",
        "custom_insight_not_ready_msg": "ဤစိတ်ကြိုက်သုံးသပ်ချက်သည် မအဆင်သင့်သေးပါ။",
        "subscription_expired_title": "{plan} အစီအစဉ် ကုန်ဆုံးသွားပါပြီ",
        "subscription_expired_msg": "သင်၏ Toe Pwar {plan} အစီအစဉ်သည် {date} တွင် ကုန်ဆုံးသွားပြီး Free အစီအစဉ်သို့ ပြန်ရောက်ပါပြီ။ AI အသုံးပြုခွင့်များနှင့် {plan} လုပ်ဆောင်ချက်များကို ပြန်လည်ရရှိရန် အချိန်မရွေး အဆင့်မြှင့်တင်နိုင်ပါသည်။",
        "trial_ending_soon_title": "{plan} အစမ်းသုံးကာလ မကြာမီ ကုန်ဆုံးပါမည်",
        "trial_ending_soon_msg": "သင်၏ Toe Pwar {plan} အစမ်းသုံးကာလသည် {date} တွင် ကုန်ဆုံးပါမည်။ AI အသုံးပြုခွင့်များနှင့် {plan} လုပ်ဆောင်ချက်များကို ဆက်လက်ရရှိရန် ထိုနေ့မတိုင်မီ အဆင့်မြှင့်တင်ပါ။",
        "trial_ends_today_title": "{plan} အစမ်းသုံးကာလ နောက်ဆုံးနေ့",
        "trial_ends_today_msg": "သင်၏ Toe Pwar {plan} အစမ်းသုံးကာလသည် {date} တွင် (၂၄ နာရီအတွင်း) ကုန်ဆုံးပါမည်။ AI အသုံးပြုခွင့်များနှင့် {plan} လုပ်ဆောင်ချက်များကို ဆက်လက်ရရှိရန် ယခုပင် အဆင့်မြှင့်တင်ပါ။",
        "plan_ending_soon_title": "{plan} အစီအစဉ် မကြာမီ ကုန်ဆုံးပါမည်",
        "plan_ending_soon_msg": "သင်၏ Toe Pwar {plan} အစီအစဉ်သည် {date} တွင် ကုန်ဆုံးပါမည်။ AI အသုံးပြုခွင့်များနှင့် {plan} လုပ်ဆောင်ချက်များကို ဆက်လက်ရရှိရန် ထိုနေ့မတိုင်မီ သက်တမ်းတိုးပါ။",
        "plan_ends_today_title": "{plan} အစီအစဉ် ၂၄ နာရီအတွင်း ကုန်ဆုံးပါမည်",
        "plan_ends_today_msg": "သင်၏ Toe Pwar {plan} အစီအစဉ်သည် {date} တွင် (၂၄ နာရီအတွင်း) ကုန်ဆုံးပါမည်။ AI အသုံးပြုခွင့်များနှင့် {plan} လုပ်ဆောင်ချက်များကို ဆက်လက်ရရှိရန် ယခုပင် သက်တမ်းတိုးပါ။",
        "plan_activated_title": "{plan} အစီအစဉ် စတင်အသုံးပြုနိုင်ပါပြီ",
        "plan_activated_msg": "သင်၏ {plan} အစီအစဉ်ကို ယခု အသုံးပြုနိုင်ပါပြီ။",
        "plan_activated_msg_until": "သင်၏ {plan} အစီအစဉ်ကို ယခု အသုံးပြုနိုင်ပါပြီ။ {date} အထိ အသုံးပြုနိုင်ပါမည်။",
        "upgrade_request_declined_title": "အဆင့်မြှင့်တင်ရန် တောင်းဆိုမှု ပိတ်လိုက်ပါပြီ",
        "upgrade_request_declined_msg": "{plan} အတွက် သင်၏ တောင်းဆိုမှုကို ပိတ်လိုက်ပါပြီ။ {contact}",
        "upgrade_request_contact_default": "မေးမြန်းလိုသည်များရှိပါက ကျွန်ုပ်တို့ထံ ဆက်သွယ်ပါ။",
        "contact_email_label": "အီးမေးလ်",
        "contact_viber_label": "ဗိုင်ဘာ",
        # The brand names stay in Latin script: that is how they are commonly written in Myanmar.
        "contact_telegram_label": "Telegram",
        "contact_facebook_label": "Facebook",
        "contact_messenger_label": "Messenger",
        "plan_paid_required_msg": "ဤလုပ်ဆောင်ချက်ကို Plus နှင့် Pro အစီအစဉ်များတွင်သာ အသုံးပြုနိုင်ပါသည်။",
        "plan_feature_chat": "AI စကားပြောခြင်း",
        "plan_feature_chat_advanced": "Advanced စကားပြောခြင်း",
        "plan_feature_insight_monthly": "လစဉ်သုံးသပ်ချက်",
        "plan_feature_insight_weekly": "အပတ်စဉ်သုံးသပ်ချက်",
        "plan_feature_insight_translation": "သုံးသပ်ချက် ဘာသာပြန်ခြင်း",
        "plan_feature_insight_custom": "စိတ်ကြိုက် သုံးသပ်ချက်",
        "plan_feature_entry": "AI ဖြင့် စာရင်းသွင်းခြင်း (ပြေစာ၊ စာသားနှင့် အသံ)",
        "plan_feature_budget_suggestion": "AI ဘတ်ဂျက် အကြံပြုချက်",
        "plan_feature_reports": "အစီရင်ခံစာများ",
        "plan_feature_locked_msg": "{feature} သည် သင်၏ အစီအစဉ်တွင် မပါဝင်ပါ။",
        "plan_limit_reached_msg": "{feature} အတွက် အသုံးပြုခွင့် ကုန်သွားပါပြီ။ {date} တွင် ပြန်လည်ရရှိပါမည်။",
        "plan_cost_cap_msg": "ဤလအတွက် AI အသုံးပြုမှု ကန့်သတ်ချက်သို့ ရောက်ရှိသွားပါပြီ။ {date} တွင် ပြန်လည်စတင်ပါမည်။",
        "plan_upgrade_to_unlock": "အသုံးပြုရန် သင်၏ အစီအစဉ်ကို အဆင့်မြှင့်တင်ပါ။",
        "plan_upgrade_for_more": "ပိုမိုအသုံးပြုရန် သင်၏ အစီအစဉ်ကို အဆင့်မြှင့်တင်ပါ။",
        "plan_upgrade_request_already": "သင်သည် {plan} အစီအစဉ် သို့မဟုတ် ၎င်းထက်မြင့်သော အစီအစဉ်ကို အသုံးပြုနေပြီးဖြစ်ပါသည်။",
        "chat_unavailable_msg": "ကိုတိုးပွား ယခု မဖြေနိုင်သေးပါ။ ခဏအကြာတွင် ထပ်ကြိုးစားပါ။",
        "budget_ai_unavailable_msg": "ကိုတိုးပွား ယခု ဘတ်ဂျက် အကြံပြု၍ မရသေးပါ။ ခဏအကြာတွင် ထပ်ကြိုးစားပါ။",
        "budget_ai_rules_fallback_msg": "ကိုတိုးပွား ယခု မဖြေနိုင်သေးသဖြင့် ဤအကြံပြုချက်များကို ရိုးရှင်းသော စည်းမျဉ်းများဖြင့် တွက်ထားပါသည်။",
        "insight_translation_failed_msg": "မြန်မာဘာသာပြန်ကို ယခု မရနိုင်သေးသဖြင့် ဤအစီရင်ခံစာကို အင်္ဂလိပ်ဘာသာဖြင့် ပြထားပါသည်။ နောက်မှ ထပ်ကြိုးစားပါ။",
        "chat_no_data_msg": "သင့်ငွေကြေးအချက်အလက် မရှိသေးပါ။ ငွေဝင်ငွေထွက်၊ ရည်မှန်းချက် သို့မဟုတ် ဘတ်ဂျက် အရင်ထည့်ပါ၊ ပြီးရင် ကူညီပေးနိုင်ပါတယ်။",
        "family_invite_title": "မိသားစုသို့ ဖိတ်ကြားချက်",
        "family_invite_msg": "{inviter} က '{family_name}' မိသားစုသို့ ဝင်ရန် ဖိတ်ကြားထားပါသည်။ ဝင်ရန် သို့မဟုတ် ငြင်းရန် မိသားစု စာမျက်နှာကို ဖွင့်ပါ။",
        "family_invite_accepted_title": "မိသားစုဝင် အသစ်",
        "family_invite_accepted_msg": "{name} သည် '{family_name}' မိသားစုသို့ ဝင်ရောက်လာပါပြီ။",
        "family_removed_title": "မိသားစုမှ ဖယ်ရှားခံရပါသည်",
        "family_removed_msg": "သင့်ကို '{family_name}' မိသားစုမှ ဖယ်ရှားလိုက်ပါပြီ။ သင်၏ ကိုယ်ပိုင်စာရင်းကို မထိခိုက်ပါ။",
        "family_owner_title": "သင် မိသားစုပိုင်ရှင် ဖြစ်လာပါပြီ",
        "family_owner_msg": "'{family_name}' မိသားစု၏ ပိုင်ရှင်က ၎င်း၏အကောင့်ကို ဖျက်လိုက်သဖြင့် ယခု သင်သည် ပိုင်ရှင် ဖြစ်လာပါပြီ။",
        "family_no_family_msg": "သင် မိသားစုတစ်ခုတွင် မပါဝင်ပါ။",
        "family_already_in_family_msg": "သင် မိသားစုတစ်ခုတွင် ပါဝင်ပြီးဖြစ်ပါသည်။ အခြားမိသားစုသို့ မဝင်မီ ယခုမိသားစုမှ ထွက်ပါ။",
        "family_not_allowed_msg": "မိသားစုတွင် ဤလုပ်ဆောင်ချက်ကို ပြုလုပ်ခွင့် မရှိပါ။",
        "family_not_found_msg": "ထိုအဖွဲ့ဝင် သို့မဟုတ် ဖိတ်ကြားချက်သည် သင့်မိသားစုတွင် မရှိပါ။",
        "family_family_full_msg": "မိသားစုတွင် အဖွဲ့ဝင် အရေအတွက် ပြည့်နေပါပြီ။",
        "family_placeholders_full_msg": "မိသားစုတွင် အမည်သာထည့်ထားသော အဖွဲ့ဝင် အရေအတွက် ပြည့်နေပါပြီ။",
        "family_plan_required_msg": "မိသားစုဖွဲ့ရန် Plus သို့မဟုတ် Pro အစီအစဉ် လိုအပ်ပါသည်။",
        "family_invite_invalid_msg": "ဤဖိတ်ကြားချက်ကို အသုံးပြု၍ မရတော့ပါ။ သက်တမ်းကုန်သွားခြင်း သို့မဟုတ် ပယ်ဖျက်ထားခြင်း ဖြစ်နိုင်ပါသည်။",
        "family_owner_must_hand_over_msg": "သင်သည် ပိုင်ရှင်ဖြစ်ပါသည်။ မထွက်မီ အခြားအဖွဲ့ဝင်တစ်ဦးထံ ပိုင်ရှင်အဖြစ် လွှဲပေးပါ။",
        "family_confirm_mismatch_msg": "ရိုက်ထည့်သော အမည်သည် မိသားစုအမည်နှင့် မကိုက်ညီပါ။",
        "family_family_read_only_msg": "ပိုင်ရှင်၏ အစီအစဉ် ကုန်ဆုံးသွားသဖြင့် ဤမိသားစုကို ကြည့်ရုံသာ ကြည့်နိုင်ပါသည်။ ပိုင်ရှင်က သက်တမ်းတိုးနိုင်သည် သို့မဟုတ် Plus သို့မဟုတ် Pro အစီအစဉ်ရှိသော အဖွဲ့ဝင်တစ်ဦးထံ ပိုင်ရှင်အဖြစ် လွှဲပေးနိုင်ပါသည်။",
        "family_invalid_book_msg": "မသိသော စာရင်းဖြစ်ပါသည်။ ကိုယ်ပိုင်စာရင်း သို့မဟုတ် မိသားစုစာရင်းကို ရွေးပါ။",
        "family_invalid_month_msg": "ထိုလကို ပြသ၍ မရပါ။ ၁၉၀၀ မှ ၂၉၉၉ အတွင်းရှိ လတစ်လကို ရွေးပါ။",
        "family_invalid_for_whom_msg": "မည်သူ့အတွက်လဲဆိုတာကို မိသားစု၏ လက်ရှိအဖွဲ့ဝင်များထဲမှ ရွေးပါ။",
        "family_transfer_insufficient_msg": "ထိုပိုက်ဆံအိတ်တွင် ဤငွေပမာဏအတွက် သုံးနိုင်သောငွေ မလုံလောက်ပါ။",
        "family_transfer_not_editable_msg": "ငွေလွှဲမှုကို ပြင်၍မရပါ။ ပြန်ရုပ်သိမ်းပြီး အသစ်ပြုလုပ်ပါ။",
        "family_use_transfer_undo_msg": "ဤစာရင်းသည် ငွေလွှဲမှုဖြစ်ပါသည်။ နှစ်ဘက်လုံးကို အတူဖယ်ရှားရန် ငွေလွှဲမှုကို ပြန်ရုပ်သိမ်းပါ။",
        "family_transfer_not_found_msg": "ထိုငွေလွှဲမှုကို မတွေ့ပါ။",
        "family_transfer_gone_msg": "ဤငွေလွှဲမှု၏ တစ်ဘက်မှာ မရှိတော့သဖြင့် ပြန်ရုပ်သိမ်း၍ မရပါ။",
        # needs native review
        "sign_in_reminder_title": "Toe Pwar သို့ ဝင်ရောက်ပါ",
        "sign_in_reminder_msg": "သင် ထွက်သွားပါပြီ။ ဘတ်ဂျက်နှင့် ရည်မှန်းချက် သတိပေးချက်များ ဆက်လက်ရရှိရန် ပြန်လည်ဝင်ရောက်ပါ။",
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
    user = await users_db.get_user(user_id)
    return user.get("language", "en") if user else "en"


def translate(key: str, language: str, **kwargs) -> str:
    """Get translated text with variable substitution"""
    template = NOTIFICATION_TRANSLATIONS.get(language, NOTIFICATION_TRANSLATIONS["en"]).get(key, key)
    return template.format(**kwargs)


async def get_user_notification_preferences(user_id: str) -> Dict[str, bool]:
    """Get user's notification preferences, return defaults if not set"""
    prefs = await prefs_db.get(user_id)

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
            "custom_insight_ready": True,
            "custom_insight_failed": True,
        }
        return default_prefs

    return prefs.get("preferences", {})


async def should_send_notification(user_id: str, notification_type: str) -> bool:
    """Check if user wants to receive this type of notification"""
    # [FIX] Added await
    preferences = await get_user_notification_preferences(user_id)
    return preferences.get(notification_type, True)


# The type -> subject link table: the typed link (sql.notifications.SUBJECT_LINKS) that holds a notice's subject, by
# its type; None: the type links no subject (it may still link its book). Every type appears. The books migration
# (d846defddc6e) holds a frozen copy.
NOTIFICATION_LINKS: Dict[str, Optional[str]] = {
    **dict.fromkeys(("goal_progress", "goal_achieved", "goal_milestone", "goal_approaching_date"), "goal_id"),
    **dict.fromkeys(("budget_threshold", "budget_exceeded", "budget_ending_soon", "budget_now_active", "budget_started",
                     "budget_auto_created"), "budget_id"),
    **dict.fromkeys(("large_transaction", "recurring_transaction_created", "recurring_transaction_ended",
                     "recurring_transaction_disabled"), "transaction_id"),
    **dict.fromkeys(("custom_insight_ready", "custom_insight_failed"), "custom_insight_id"),
    "family_invite": "family_invite_id",
    **dict.fromkeys(("family_invite_accepted", "family_removed", "family_owner"), "family_id"),
    **dict.fromkeys(("unusual_spending", "payment_reminder", "weekly_insights_generated", "monthly_insights_generated",
                     "subscription_expired", "trial_ending_soon", "trial_ends_today", "plan_ending_soon",
                     "plan_ends_today", "plan_activated", "upgrade_request_declined", "system_broadcast",
                     "admin_announcement"), None),
}


async def create_notification(
    user_id: str,
    notification_type: str,
    title: str,
    message: str,
    goal_name: Optional[str] = None,
    currency: Optional[str] = None,
    extra: Optional[dict] = None,
    links: Optional[Dict[str, Optional[str]]] = None,
) -> Optional[dict]:
    """Create a new notification (only if user has it enabled).

    links: the notice's typed links (sql.notifications.LINKS): its subject under the link its type names
    (NOTIFICATION_LINKS, e.g. {"budget_id": ...}) and the book it is about ({"book_id": ...}). A link whose row is
    already gone is stored NULL, so a notice never fails the action that sent it.
    extra: additional fields stored on the notification document (e.g. dedupe keys); not sent in the push payload.
    The push data carries subject_id (the subject link stored, "" if none) and book = 'family' when the notice's book
    is a family book (the app opens it in Family mode).
    """
    links = {k: v for k, v in (links or {}).items() if v is not None}
    subject = [k for k in links if k != "book_id"]
    if set(links) - set(notifications_db.LINKS) or subject not in ([], [NOTIFICATION_LINKS.get(notification_type)]):
        raise ValueError(f"A {notification_type} notice can't link {sorted(links)}")

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
        **links,
        "goal_name": goal_name,
        "currency": currency,
        "created_at": datetime.now(UTC),
        "is_read": False
    }
    if extra:
        for key, value in extra.items():
            notification.setdefault(key, value)

    notification = await notifications_db.insert_notification(notification)
    if notification is None:  # it could not be stored (logged by insert_notification): no push either
        return None
    print(f"✅ Created notification {notification_type} for user {user_id}")
    subject_id = next((notification[k] for k in notifications_db.SUBJECT_LINKS if notification.get(k)), None)
    family = bool(notification.get("book_id")) and await books_db.is_family_book(notification["book_id"])

    # The push goes to every device of the user whose sign-in has not expired. The tokens are read here, on the event
    # loop: the worker thread that sends never touches the database.
    tokens = await devices_db.active_tokens(user_id, datetime.now(UTC))
    if not tokens:
        print(f"⚠️  User {user_id} has no signed-in device")
        return notification

    fcm_data = {
        "notification_id": notification_id,
        "type": notification_type,
        "subject_id": subject_id or "",
        "goal_name": goal_name or "",
        "currency": currency or "",
    }
    if family:
        # A family book's notice: the app's push-tap handler switches to Family mode first.
        fcm_data["book"] = "family"

    async def push():
        try:
            # The blocking Firebase call runs in a worker thread; the dead-token clean-up runs back on the loop.
            result = await asyncio.to_thread(send_push, tokens, title, message, fcm_data)
            await devices_db.delete_tokens(result.get("unregistered") or [])
        except Exception as e:
            print(f"❌ Error sending background FCM: {e}")

    # Fire and forget, keeping a strong reference until it completes so it can't be garbage-collected.
    task = asyncio.get_running_loop().create_task(push())
    _background_tasks.add(task)
    task.add_done_callback(_background_tasks.discard)

    return notification


async def notification_recipients(book_id: str) -> Tuple[bool, List[str]]:
    """(is_family, recipients) of a book's notices: a personal book's go to its person; a family book's go to the
    family's active account members (who may be none). No such book (e.g. a person's id): (False, []), logged."""
    book = await books_db.get_book_row(book_id)
    if book is None:
        print(f"⚠️ No book {book_id}: its notice goes to nobody")
        return False, []
    if book["kind"] == "family":
        return True, await families_db.account_user_ids_for_book(book_id)
    return False, [book["person_id"]]


def _for_language(value: Any, lang: str) -> Any:
    """A value that depends on the reader's language is passed as a callable taking the language."""
    return value(lang) if callable(value) else value


async def create_person_notification_from_key(
    person_id: str,
    notification_type: str,
    title_key: str,
    msg_key: str,
    *,
    links: Optional[Dict[str, Optional[str]]] = None,
    goal_name: Any = None,
    currency: Optional[str] = None,
    extra: Optional[dict] = None,
    **fmt: Any,
) -> Optional[dict]:
    """create_notification for one person, with the title and message rendered from NOTIFICATION_TRANSLATIONS in that
    person's language. `goal_name` and the `fmt` values may be callables taking the language (e.g. a days phrase); the
    templates' {goal_name} is the notification's goal_name. `links` as in create_notification. To tell everyone a
    book's notice is for, use create_notification_from_key."""
    lang = await get_user_language(person_id)
    name = _for_language(goal_name, lang)
    values = {"goal_name": name, **{k: _for_language(v, lang) for k, v in fmt.items()}}
    return await create_notification(
        user_id=person_id,
        notification_type=notification_type,
        title=translate(title_key, lang, **values),
        message=translate(msg_key, lang, **values),
        goal_name=name,
        currency=currency,
        extra=extra,
        links=links,
    )


async def create_notification_from_key(
    book_id: str,
    notification_type: str,
    title_key: str,
    msg_key: str,
    *,
    subject: Optional[Dict[str, str]] = None,
    goal_name: Any = None,
    currency: Optional[str] = None,
    extra: Optional[dict] = None,
    **fmt: Any,
) -> List[dict]:
    """A book's notice, fanned out by the book's kind (notification_recipients), each one rendered in its reader's
    language (create_person_notification_from_key) and linked to the book (book_id) and to `subject` (its typed link,
    e.g. {"budget_id": ...}; see create_notification).

    A personal book: exactly one notification, for its person. A family book: one notification per active account
    member, each subject to that member's preferences and device (its book_id is what marks it as the family's).
    Returns the notifications stored (a member's failure is logged and skipped).
    """
    is_family, recipients = await notification_recipients(book_id)
    links = {**(subject or {}), "book_id": book_id}
    sent: List[dict] = []
    for recipient in recipients:
        try:
            notification = await create_person_notification_from_key(
                recipient, notification_type, title_key, msg_key,
                links=links, goal_name=goal_name, currency=currency, extra=extra, **fmt,
            )
        except Exception as e:
            if not is_family:
                raise
            print(f"❌ Could not send {notification_type} for family book {book_id} to member {recipient}: {e}")
            continue
        if notification:
            sent.append(notification)
    return sent


async def check_goal_notifications(book_id: str, goal_id: str, old_progress: float, new_progress: float, goal_name: str):
    """Check and create notifications based on goal progress"""
    # [FIX] Added await
    goal = await goals_db.get_goal(goal_id, book_id)
    currency = goal.get("currency", "usd") if goal else "usd"

    milestones = [25, 50, 75, 100]

    for milestone in milestones:
        if old_progress < milestone <= new_progress:
            if milestone == 100:
                await create_notification_from_key(
                    book_id, "goal_achieved", "goal_achieved_title", "goal_achieved_msg",
                    subject={"goal_id": goal_id}, goal_name=goal_name, currency=currency,
                )
            elif milestone in [25, 50, 75]:
                emoji = "💪" if milestone == 25 else "🎯" if milestone == 50 else "🎉"
                await create_notification_from_key(
                    book_id, "goal_progress", "goal_progress_title", "goal_progress_msg",
                    subject={"goal_id": goal_id}, goal_name=goal_name, currency=currency, milestone=milestone,
                    emoji=emoji,
                )

async def check_milestone_amount(book_id: str, goal_id: str, old_amount: float, new_amount: float, goal_name: str):
    """Check for milestone amounts (every $1000 or 1M K)"""
    # [FIX] Added await
    goal = await goals_db.get_goal(goal_id, book_id)
    currency = goal.get("currency", "usd") if goal else "usd"

    milestone_interval = 1000000 if currency == "mmk" else 1000

    old_milestone = int(old_amount / milestone_interval)
    new_milestone = int(new_amount / milestone_interval)

    if new_milestone > old_milestone:
        milestone_amount = new_milestone * milestone_interval
        await create_notification_from_key(
            book_id, "goal_milestone", "goal_milestone_title", "goal_milestone_msg",
            subject={"goal_id": goal_id}, goal_name=goal_name, currency=currency,
            amount=format_currency_amount(milestone_amount, currency),
        )


def _days_text(days: int, lang: str) -> str:
    """Days phrase for templates. Myanmar templates already contain 'ရက်' after {days}."""
    if lang == "my":
        return str(days)
    return "1 day" if days == 1 else f"{days} days"


async def _books_of_person(person_id: str) -> List[str]:
    """The books whose reminders a person gets: their personal book, and their family's book while they are an active
    account member of a family."""
    book_ids = []
    personal = await books_db.personal_book_id(person_id)
    if personal:
        book_ids.append(personal)
    membership = await families_db.active_membership(person_id)
    family_book = await books_db.family_book_id(membership["family_id"]) if membership else None
    if family_book:
        book_ids.append(family_book)
    return book_ids


async def goal_deadline_reminders_for_person(person_id: str, today: date, tz: tzinfo) -> None:
    """The person's daily goal-deadline reminders (local_jobs, 09:00 on their clock): the active goals of their
    books (personal, and their family's) whose target date is near, counted in calendar days from the person's `today`.

    Each goal gets at most one reminder per threshold (14/7/3/1 days) for a given target date for each person;
    thresholds are matched as ranges (e.g. 8-14 days -> the 14-day reminder) so a missed run or a goal created inside a
    window still gets it. A family goal's reminder goes to this member only (each member gets theirs in their own
    run, counted from their own today)."""
    window = (today - timedelta(days=1), today + timedelta(days=max(GOAL_REMINDER_THRESHOLDS) + 1))
    since = datetime.now(UTC) - timedelta(hours=20)
    for book_id in await _books_of_person(person_id):
        for goal in await goals_db.list_goals(book_id, status="active", target_between=window):
            try:
                target_date = goal.get("target_date")
                if not target_date:
                    continue
                days_remaining = days_until(target_date, today)
                threshold = goal_reminder_threshold(days_remaining)
                if threshold is None:
                    continue
                goal_id = goal["_id"]
                target_key = as_calendar_date(target_date).isoformat()

                # Dedupe per person + goal + threshold + target date (a changed target date re-arms the reminders).
                # The 20h check also covers notifications created before these keys existed.
                if await notifications_db.approaching_reminder_exists([person_id], goal_id, threshold, target_key,
                                                                      since=since):
                    continue

                remaining = (goal.get("target_amount") or 0) - (goal.get("current_amount") or 0)
                currency = goal.get("currency", "usd")
                await create_person_notification_from_key(
                    person_id, "goal_approaching_date", "goal_approaching_title",
                    "goal_approaching_msg_with_remaining" if remaining > 0 else "goal_approaching_msg_achieved",
                    links={"goal_id": goal_id, "book_id": book_id},
                    goal_name=goal["name"],
                    currency=currency,
                    extra={"reminder_threshold": threshold, "reminder_target_date": target_key},
                    days=lambda lang, d=days_remaining: _days_text(d, lang),
                    remaining=format_currency_amount(remaining, currency),
                )
            except Exception as e:
                print(f"❌ Error checking target date for goal {goal.get('_id')} for {person_id}: {e}")

async def check_budget_notifications(book_id: str, budget_id: str, old_percentage: float, new_percentage: float, budget_name: str, category_name: str = None):
    """Check and create budget threshold/exceeded notifications"""
    # [FIX] Added await
    currency = await budgets_db.budget_currency(budget_id) or "usd"

    def budget_label(lang: str) -> str:
        return f"'{category_name}'" if category_name else ("overall" if lang == "en" else "စုစုပေါင်း")

    if old_percentage < 80 <= new_percentage < 100:
        await create_notification_from_key(
            book_id, "budget_threshold", "budget_threshold_title", "budget_threshold_msg",
            subject={"budget_id": budget_id}, goal_name=budget_name, currency=currency, label=budget_label,
            budget_name=budget_name,
        )

    if old_percentage < 100 <= new_percentage:
        await create_notification_from_key(
            book_id, "budget_exceeded", "budget_exceeded_title", "budget_exceeded_msg",
            subject={"budget_id": budget_id}, goal_name=budget_name, currency=currency, label=budget_label,
            budget_name=budget_name,
        )


async def budget_ending_reminders_for_person(person_id: str, today: date, tz: tzinfo) -> None:
    """The person's daily "budget ending soon" reminders (local_jobs, 09:00 on their clock): the running budgets of
    their books (personal, and their family's) whose last day is at most BUDGET_ENDING_SOON_DAYS calendar days after
    the person's `today` (0: it ends today).

    "Running" = its days include the person's own today (an exceeded budget is still running and must get the alert).
    That is decided from the dates on the person's calendar, not from the stored status: a budget's status is once per
    book (the book's zone, a family's owner), so for a member behind the owner it already reads "completed" on the
    member's last day, which would never get its "ends today". Budget ids are per period, so each person gets one
    "ending soon" per budget ever; a family budget's goes to this member only."""
    window = (today - timedelta(days=1), today + timedelta(days=BUDGET_ENDING_SOON_DAYS + 1))
    for budget in await budgets_db.ending_soon_candidates(await _books_of_person(person_id), today, *window):
        try:
            book_id = budget["book_id"]
            start, end = budget.get("start_date"), budget.get("end_date")
            if not start or not end or not as_calendar_date(start) <= today <= as_calendar_date(end):
                continue
            days_until_end = days_until(budget["end_date"], today)
            if not is_budget_ending_soon(days_until_end):
                continue
            budget_id = budget["_id"]
            if await notifications_db.exists([person_id], "budget_ending_soon", budget_id=budget_id):
                continue
            budget_name = budget["name"]
            await create_person_notification_from_key(
                person_id, "budget_ending_soon", "budget_ending_soon_title",
                "budget_ending_today_msg" if days_until_end == 0 else "budget_ending_soon_msg",
                links={"budget_id": budget_id, "book_id": book_id},
                goal_name=budget_name,
                currency=budget.get("currency", "usd"),
                budget_name=budget_name,
                days=lambda lang, d=days_until_end: _days_text(d, lang),
            )
        except Exception as e:
            print(f"❌ Error checking budget end for {budget.get('_id')} for {person_id}: {e}")


async def budget_now_active_for_book(book_id: str, today: date, tz: tzinfo) -> None:
    """The book's daily "budget now active" check (local_jobs, 09:00 on the book's clock): budgets whose start date
    (at most BUDGET_NOW_ACTIVE_LOOKBACK_DAYS before the book's `today`) has arrived and that were never announced.

    Status may already have been flipped upcoming -> active by a list/get refresh, so they are selected by dates and
    the started_notified flag instead of status == "upcoming". The upcoming -> active recompute sends the notice too;
    notify_budget_now_active_once sends it once whichever path gets there first."""
    from budget_service import refresh_budget_state_if_stale  # local: avoid import cycle

    lookback_start = today - timedelta(days=BUDGET_NOW_ACTIVE_LOOKBACK_DAYS)
    for budget in await budgets_db.now_active_candidates(book_id, lookback_start, today):
        try:
            if budget.get("status") == "upcoming":
                # Persist the real status; the recompute itself sends the notification.
                budget = await refresh_budget_state_if_stale(budget, tz)
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
    book_id = budget["book_id"]
    if not await budgets_db.claim_flag(budget_id, "started_notified", datetime.now(UTC)):
        return False

    _, recipients = await notification_recipients(book_id)
    existing = await notifications_db.exists(recipients, ["budget_now_active", "budget_started"], budget_id=budget_id)
    if existing:
        return False

    budget_name = budget["name"]
    currency = budget.get("currency", "usd")
    await create_notification_from_key(
        book_id, "budget_now_active", "budget_now_active_title", "budget_now_active_msg",
        subject={"budget_id": budget_id}, goal_name=budget_name, currency=currency, budget_name=budget_name,
        amount=format_currency_amount(budget.get("total_budget") or 0, currency),
    )
    return True

async def notify_budget_started(book_id: str, budget_id: str, budget_name: str, total_budget: float, period: str):
    """Notify when a new budget is created and started"""
    currency = await budgets_db.budget_currency(budget_id) or "usd"
    await create_notification_from_key(
        book_id, "budget_started", "budget_started_title", "budget_started_msg",
        subject={"budget_id": budget_id}, goal_name=budget_name, currency=currency, budget_name=budget_name, period=period,
        amount=format_currency_amount(total_budget, currency),
    )


async def notify_budget_auto_created(book_id: str, budget_id: str, budget_name: str, was_ai: bool):
    """Notify when a budget is auto-created"""
    currency = await budgets_db.budget_currency(budget_id) or "usd"
    await create_notification_from_key(
        book_id, "budget_auto_created", "budget_auto_created_title",
        "budget_auto_created_msg_ai" if was_ai else "budget_auto_created_msg",
        subject={"budget_id": budget_id}, goal_name=budget_name, currency=currency, budget_name=budget_name,
    )


async def _personal_book_person(book_id: str) -> Optional[str]:
    """The person of a personal book; None for a family book (it gets no per-entry or spending-pattern notices, R14)
    or no such book."""
    book = await books_db.get_book_row(book_id)
    return book["person_id"] if book is not None and book["kind"] == "personal" else None


async def check_large_transaction(book_id: str, transaction: Dict, user_spending_profile: Dict = None):
    """Check if a transaction of the book is unusually large and notify its person (never for a family book: no
    per-entry notices)"""
    person_id = await _personal_book_person(book_id)
    if person_id is None:
        return
    amount = transaction["amount"]
    transaction_type = transaction["type"]
    category = transaction["main_category"]
    description = transaction.get("description", "")
    currency = transaction.get("currency", "usd")
    # [FIX] Added await
    lang = await get_user_language(person_id)

    if transaction_type != "outflow":
        return

    if user_spending_profile and "avg_transaction" in user_spending_profile:
        threshold = user_spending_profile["avg_transaction"] * 3
        threshold = max(threshold, 100000 if currency == "mmk" else 100)
    else:
        threshold = 150000 if currency == "mmk" else 150

    if amount >= threshold:
        # [FIX] Added await
        existing = await notifications_db.exists(person_id, "large_transaction", since=datetime.now(UTC) - timedelta(minutes=5))

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
                user_id=person_id,
                notification_type="large_transaction",
                title=title,
                message=message,
                goal_name=f"Large {category} expense",
                currency=currency,
                links={"transaction_id": transaction["_id"], "book_id": book_id},
            )


async def analyze_unusual_spending(book_id: str, tz: Optional[tzinfo] = None):
    """Analyze the book's spending patterns and notify its person about unusual activity (never for a family book: no
    per-entry notices, R14). tz: the person's zone when the caller has it (else it is read)."""
    from collections import defaultdict

    person_id = await _personal_book_person(book_id)
    if person_id is None:
        return

    now = datetime.now(UTC)
    # Transaction dates are local wall-clock values (no timezone), so the "this week" window is measured on the
    # person's wall clock (created_at stays real UTC).
    wall_now = local_now(tz if tz is not None else await person_zone(person_id), now)
    currencies = await transactions_db.currencies(book_id)
    # [FIX] Added await
    lang = await get_user_language(person_id)

    # Upper bound of the "this week" window: end of today on that wall clock, so
    # future-dated (planned) transactions don't count as this week's spending.
    end_of_today = wall_now.replace(hour=23, minute=59, second=59, microsecond=999999)

    for currency in currencies:
        this_week_start = wall_now - timedelta(days=7)
        recent_notification_cutoff = now - timedelta(days=7)
        this_week_transactions = await transactions_db.find_transactions(
            book_id, type_="outflow", currency=currency, date_from=this_week_start, date_to=end_of_today,
            include_transfers=False,
        )

        last_month_start = wall_now - timedelta(days=35)
        last_month_end = this_week_start
        last_month_transactions = await transactions_db.find_transactions(
            book_id, type_="outflow", currency=currency, date_from=last_month_start, date_before=last_month_end,
            include_transfers=False,
        )

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
                existing = await notifications_db.exists(
                    person_id, "unusual_spending", goal_name=category, currency=currency, since=recent_notification_cutoff
                )

                if not existing:
                    formatted_this_week = format_currency_amount(this_week_amount, currency)
                    formatted_avg = format_currency_amount(weekly_avg, currency)

                    title = translate("unusual_spending_title", lang)
                    message = translate("unusual_spending_msg", lang, 
                                      category=category, this_week=formatted_this_week, avg=formatted_avg)

                    # [FIX] Added await
                    await create_notification(
                        user_id=person_id,
                        notification_type="unusual_spending",
                        title=title,
                        message=message,
                        goal_name=category,
                        currency=currency,
                        links={"book_id": book_id},
                    )


async def _detect_recurring_payments_for_book(book_id: str, now: datetime, today: date, tz: tzinfo):
    """Detect monthly recurring outflows in one book and send its person due-soon reminders (never for a family book,
    R14). `today` and `tz`: the person's."""
    from collections import defaultdict

    person_id = await _personal_book_person(book_id)
    if person_id is None:
        return

    lang = await get_user_language(person_id)
    currencies = await transactions_db.currencies(book_id)

    for currency in currencies:
        ninety_days_ago = local_now(tz, now) - timedelta(days=90)
        transactions = await transactions_db.find_transactions(
            book_id, type_="outflow", currency=currency, date_from=ninety_days_ago, include_transfers=False
        )

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
                "date": as_wall_clock(t["date"]),
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

            existing = await notifications_db.exists(
                person_id, "payment_reminder", goal_name=key, currency=currency, since=now - timedelta(days=7)
            )
            if existing:
                continue

            formatted_amount = format_currency_amount(occurrences[-1]["amount"], currency)
            title = translate("payment_reminder_title", lang)
            message = translate("payment_reminder_msg", lang,
                                description=occurrences[-1]["description"],
                                amount=formatted_amount, days=days_until_due)

            await create_notification(
                user_id=person_id,
                notification_type="payment_reminder",
                title=title,
                message=message,
                goal_name=key,
                currency=currency,
                links={"book_id": book_id},
            )


async def payment_reminders_for_person(person_id: str, today: date, tz: tzinfo) -> None:
    """The person's daily recurring-payment reminders (local_jobs, 09:00 on their clock), from their personal book
    only (family books get no spending-pattern notices, R14)."""
    book_id = await books_db.personal_book_id(person_id)
    if book_id:
        await _detect_recurring_payments_for_book(book_id, datetime.now(UTC), today, tz)


async def unusual_spending_for_person(person_id: str, today: date, tz: tzinfo) -> None:
    """The person's daily unusual-spending check (local_jobs, 08:00 on their clock), on their personal book only
    (family books get no spending-pattern notices, R14)."""
    book_id = await books_db.personal_book_id(person_id)
    if book_id:
        await analyze_unusual_spending(book_id, tz)

async def _notify_insights_generated(book_id: str, notification_type: str, title_key: str, msg_key: str,
                                     goal_name_en: str, goal_name_my: str):
    """The "insights ready" notice of a book, at most once per hour per book.

    The notice links its book (book_id): a family book's notice goes to every active account member, and the hourly
    dedupe looks for this book's notice only, so a member's own personal notice doesn't hold the family's back.
    """
    _, recipients = await notification_recipients(book_id)
    since = datetime.now(UTC) - timedelta(hours=1)
    if await notifications_db.exists(recipients, notification_type, book_id=book_id, since=since):
        print(f"Skipping duplicate {notification_type} notification for book {book_id}")
        return None

    await create_notification_from_key(
        book_id, notification_type, title_key, msg_key,
        goal_name=lambda lang: goal_name_en if lang == "en" else goal_name_my,
        currency=None,
    )


async def notify_monthly_insights_generated(book_id: str):
    """Notify when the book's monthly insights are generated (at most once per hour per book)"""
    await _notify_insights_generated(book_id, "monthly_insights_generated", "monthly_insights_title",
                                     "monthly_insights_msg", "Monthly Insights Tailored For You",
                                     "သင့်အတွက် ပြင်ဆင်ထားသော လစဉ်ထိုးထွင်းသိမြင်မှုများ")


async def notify_weekly_insights_generated(book_id: str):
    """Notify when the book's weekly insights are generated (at most once per hour per book)"""
    await _notify_insights_generated(book_id, "weekly_insights_generated", "weekly_insights_title",
                                     "weekly_insights_msg", "Weekly Insights Tailored For You",
                                     "သင့်အတွက် ပြင်ဆင်ထားသော အပတ်စဉ်ထိုးထွင်းသိမြင်မှုများ")


async def _notify_custom_insight(book_id: str, report_id: str, start: date, end: date, asker: Optional[str],
                                 notification_type: str, title_key: str, message_key: str) -> None:
    """Store one custom-insight notice, linked to the report (custom_insight_id: the app opens it) and its book.

    asker: the person who asked for a family book's report, who alone is told; None: the book's notice goes to
    whoever the book's notices go to (a personal book's person; every active member of a family book).
    Never raises: the report is already ready or failed, so a notice that cannot be stored is only logged.
    """
    subject = {"custom_insight_id": report_id}

    def report_range(lang: str) -> str:
        return f"{format_day(start, lang)} – {format_day(end, lang)}"
    try:
        if asker:
            await create_person_notification_from_key(
                asker, notification_type, title_key, message_key,
                links={**subject, "book_id": book_id}, range=report_range,
            )
        else:
            await create_notification_from_key(
                book_id, notification_type, title_key, message_key, subject=subject, range=report_range,
            )
    except Exception as e:
        print(f"❌ Could not send {notification_type} notification for report {report_id}: {e}")


async def notify_custom_insight_ready(book_id: str, report_id: str, start: date, end: date,
                                      asker: Optional[str] = None) -> None:
    """Tell the asker (see _notify_custom_insight) that the book's custom insight for start..end is ready."""
    await _notify_custom_insight(book_id, report_id, start, end, asker, "custom_insight_ready",
                                 "custom_insight_ready_title", "custom_insight_ready_msg")


async def notify_custom_insight_failed(book_id: str, report_id: str, start: date, end: date, refused: bool,
                                       asker: Optional[str] = None) -> None:
    """Tell the asker (see _notify_custom_insight) that the book's custom insight could not be made, and that it was
    not counted.

    refused=True: the question was off-topic (own message); same type and title as a plain failure.
    """
    await _notify_custom_insight(book_id, report_id, start, end, asker, "custom_insight_failed",
                                 "custom_insight_failed_title",
                                 "custom_insight_refused_msg" if refused else "custom_insight_failed_msg")
