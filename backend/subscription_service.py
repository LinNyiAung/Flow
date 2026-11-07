"""Paid-plan state: one definition of "on a paid plan", the expiry job and the Plus-trial reminders.

A user is on a paid plan while subscription_type is "plus" or "pro" and subscription_expires_at is unset (lifetime)
or in the future. Feature access (plans.access.effective_plan, utils.ensure_paid) checks that live;
expire_paid_plans() additionally downgrades expired users to "free" so the stored data, admin counts and broadcast
targeting stay truthful.

A trial is a Plus plan with users.trial_ends_at set (see plans.access.is_trial). send_trial_reminders() tells trial
users, each at most once, when the trial is about to end. send_plan_renewal_reminders() does the same for paying users
whose plan has an end date (once per end date), so they can ask to renew before it ends.
"""
import asyncio
import logging
from datetime import datetime, timedelta, UTC
from typing import Optional

from plans import store
from plans.catalog import PAID_PLANS
from sql import users as users_db
from firebase_service import send_fcm_data_message
from notification_service import create_notification, translate
from plans.access import format_date, user_language
from utils import ensure_utc_datetime

logger = logging.getLogger(__name__)

# Only plans that ended this recently get a "plan has ended" notification.
# Older ones (e.g. everything already expired when this job first ships) are downgraded
# silently instead of flooding long-lapsed users with stale notices.
NOTIFY_IF_ENDED_WITHIN = timedelta(days=7)

# Trial reminders: "trial ends soon" once the trial has at most 3 days left, "last day" once it has at most 1 day.
# The paid-plan renewal reminders use the same two windows.
TRIAL_REMINDER_SOON = timedelta(days=3)
TRIAL_REMINDER_LAST = timedelta(days=1)
PLAN_REMINDER_SOON = TRIAL_REMINDER_SOON
PLAN_REMINDER_LAST = TRIAL_REMINDER_LAST


def active_paid_filter(now: Optional[datetime] = None):
    """SQL condition: users who are currently on a paid plan (lifetime or not yet expired)."""
    return users_db.active_paid(now or datetime.now(UTC))


def active_plan_filter(plan: str, now: Optional[datetime] = None):
    """SQL condition: users currently on this paid plan ("plus" or "pro")."""
    return users_db.active_plan(plan, now or datetime.now(UTC))


def effectively_free_filter(now: Optional[datetime] = None):
    """SQL condition: users without an active paid plan (free, or a paid plan that has expired)."""
    return users_db.effectively_free(now or datetime.now(UTC))


def _format_end_date(expired_at: datetime, lang: str) -> str:
    return format_date(expired_at, lang)


def _plan_name(plan: str) -> str:
    return plan.capitalize()


async def expire_paid_plans(now: Optional[datetime] = None) -> int:
    """Downgrade every expired Plus/Pro user to free, notify them and refresh their app.

    Each downgrade is conditional on the user still being on a paid plan with the same expiry
    date, so an admin extension that lands meanwhile wins and overlapping runs can't
    notify twice. The expiry date is kept (and copied to premium_ended_at) as history.
    Returns the number of users downgraded.
    """
    now = now or datetime.now(UTC)
    candidates = await users_db.list_fields(
        ["subscription_type", "subscription_expires_at", "fcm_token", "language"],
        users_db.users.c.subscription_type.in_(PAID_PLANS),
        users_db.users.c.subscription_expires_at.isnot(None),
    )

    downgraded = 0
    for user in candidates:
        stored_expiry = user.get("subscription_expires_at")
        try:
            expired_at = ensure_utc_datetime(stored_expiry)
        except (TypeError, ValueError, AttributeError):
            logger.warning(f"Unparseable subscription_expires_at for user {user['_id']}: {stored_expiry!r}")
            continue
        if expired_at is None or expired_at > now:
            continue

        if not await users_db.downgrade_if_unchanged(user["_id"], stored_expiry, expired_at):
            continue
        downgraded += 1
        plan = _plan_name(user["subscription_type"])
        logger.info(f"{plan} plan expired for user {user['_id']} (ended {expired_at.isoformat()}); downgraded to free")

        if now - expired_at > NOTIFY_IF_ENDED_WITHIN:
            continue  # long-lapsed: silent downgrade, no notice (and nothing paid to refresh)

        try:
            lang = user_language(user)
            await create_notification(
                user_id=user["_id"],
                notification_type="subscription_expired",
                title=translate("subscription_expired_title", lang, plan=plan),
                message=translate("subscription_expired_msg", lang, plan=plan, date=_format_end_date(expired_at, lang)),
            )
        except Exception as e:
            logger.error(f"Could not create plan-ended notification for user {user['_id']}: {e}")

        # Silent data message: the app reloads the profile and drops paid UI at once.
        if user.get("fcm_token"):
            try:
                await asyncio.to_thread(
                    send_fcm_data_message, user["fcm_token"],
                    {"type": "subscription_updated", "subscription_type": "free"},
                )
            except Exception as e:
                logger.warning(f"Could not send subscription refresh push to user {user['_id']}: {e}")

    if downgraded:
        logger.info(f"Plan expiry job: downgraded {downgraded} user(s)")
    return downgraded


async def send_trial_reminders(now: Optional[datetime] = None) -> int:
    """Remind trial users that their Plus trial is ending; returns the number of reminders sent.

    Two reminders, each sent at most once per trial and only to users whose trial marker (trial_ends_at) is still
    in the future and who are still on a paid plan: "ends soon" when 3 days or less are left (but more than 1 day),
    and "last day" when 1 day or less is left. A user first seen inside the last day gets only the last-day one.
    Plans an admin granted or changed carry no marker, so they are never reminded. Each reminder is claimed in the
    database before it is sent, so overlapping runs or a re-run cannot send it twice.
    """
    now = now or datetime.now(UTC)
    candidates = await users_db.list_fields(
        ["subscription_type", "trial_ends_at", "language"],
        users_db.active_paid(now),
        users_db.users.c.trial_ends_at.isnot(None),
        users_db.users.c.trial_ends_at > now,
        users_db.users.c.trial_ends_at <= now + TRIAL_REMINDER_SOON,
    )

    sent = 0
    for user in candidates:
        ends_at = ensure_utc_datetime(user["trial_ends_at"])
        kind = "last" if ends_at - now <= TRIAL_REMINDER_LAST else "3d"
        if not await users_db.claim_trial_reminder(user["_id"], kind, user["trial_ends_at"], now):
            continue
        sent += 1
        try:
            lang = user_language(user)
            plan = _plan_name(user["subscription_type"])
            key = "trial_ends_today" if kind == "last" else "trial_ending_soon"
            await create_notification(
                user_id=user["_id"],
                notification_type=key,
                title=translate(f"{key}_title", lang, plan=plan),
                message=translate(f"{key}_msg", lang, plan=plan, date=_format_end_date(ends_at, lang)),
            )
        except Exception as e:
            logger.error(f"Could not create trial reminder for user {user['_id']}: {e}")

    if sent:
        logger.info(f"Trial reminder job: sent {sent} reminder(s)")
    return sent


async def send_plan_renewal_reminders(now: Optional[datetime] = None) -> int:
    """Remind paying users that their Plus / Pro plan is ending; returns the number of reminders sent.

    Same windows as the trial reminders: "plan_ending_soon" when 3 days or less are left (but more than 1 day), and
    "plan_ends_today" when 1 day or less is left; a user first seen inside the last day gets only the last-day one.
    Only users on a paid plan with an end date still in the future who are not on a free trial (trial users get the
    trial reminders instead); lifetime plans (no end date) are never reminded. Each reminder is claimed in the database
    for that end date before it is sent, so overlapping runs or a re-run cannot send it twice, and an admin extension
    to a new end date re-arms both.
    """
    now = now or datetime.now(UTC)
    candidates = await users_db.list_fields(
        ["subscription_type", "subscription_expires_at", "language"],
        users_db.active_paid(now),
        users_db.users.c.subscription_expires_at.isnot(None),
        users_db.users.c.subscription_expires_at > now,
        users_db.users.c.subscription_expires_at <= now + PLAN_REMINDER_SOON,
        users_db.not_on_trial(now),
    )

    sent = 0
    for user in candidates:
        ends_at = ensure_utc_datetime(user["subscription_expires_at"])
        kind = "last" if ends_at - now <= PLAN_REMINDER_LAST else "3d"
        if not await users_db.claim_plan_reminder(user["_id"], kind, user["subscription_expires_at"], now):
            continue
        sent += 1
        try:
            lang = user_language(user)
            plan = _plan_name(user["subscription_type"])
            key = "plan_ends_today" if kind == "last" else "plan_ending_soon"
            await create_notification(
                user_id=user["_id"],
                notification_type=key,
                title=translate(f"{key}_title", lang, plan=plan),
                message=translate(f"{key}_msg", lang, plan=plan, date=_format_end_date(ends_at, lang)),
            )
        except Exception as e:
            logger.error(f"Could not create plan renewal reminder for user {user['_id']}: {e}")

    if sent:
        logger.info(f"Plan renewal reminder job: sent {sent} reminder(s)")
    return sent


async def notify_plan_activated(user: dict, plan: str, expires_at: Optional[datetime]) -> None:
    """Tell the user an admin has put them on Plus or Pro ("plan_activated"), with the end date when the plan has one.

    Goes through create_notification like the trial reminders (stored, pushed where the user has a token, and skipped
    when the user's stored preference for the type is off). A failure is logged and swallowed: the admin's plan change
    has already happened and must not fail because the notice could not be sent.
    """
    try:
        lang = user_language(user)
        name = _plan_name(plan)
        if expires_at is None:
            message = translate("plan_activated_msg", lang, plan=name)
        else:
            message = translate("plan_activated_msg_until", lang, plan=name, date=format_date(expires_at, lang))
        await create_notification(
            user_id=user["_id"],
            notification_type="plan_activated",
            title=translate("plan_activated_title", lang, plan=name),
            message=message,
        )
    except Exception as e:
        logger.error(f"Could not create plan-activated notification for user {user.get('_id')}: {e}")


async def notify_upgrade_request_declined(user: dict, plan: str) -> None:
    """Tell the user their upgrade request for `plan` was closed without a plan change ("upgrade_request_declined"):
    the owner's contact message (in the user's language) when one is set, otherwise a generic "contact us" sentence,
    then the owner's email and Viber number ("Email: …", "Viber: …", each on its own line) when they are set.
    A failure is logged and swallowed, like notify_plan_activated."""
    try:
        lang = user_language(user)
        contact = (store.upgrade_contact().get(lang) or "").strip() or translate("upgrade_request_contact_default", lang)
        owner = store.owner_contact()
        for key in ("email", "viber"):
            if owner.get(key):
                contact += f"\n{translate(f'contact_{key}_label', lang)}: {owner[key]}"
        await create_notification(
            user_id=user["_id"],
            notification_type="upgrade_request_declined",
            title=translate("upgrade_request_declined_title", lang),
            message=translate("upgrade_request_declined_msg", lang, plan=_plan_name(plan), contact=contact),
        )
    except Exception as e:
        logger.error(f"Could not create request-declined notification for user {user.get('_id')}: {e}")
