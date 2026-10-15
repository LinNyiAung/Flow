"""Premium subscription state: one definition of "active premium" and the expiry job.

A user is premium while subscription_type == "premium" and subscription_expires_at is
unset (lifetime) or in the future. Feature access (utils.require_premium) checks that
live; expire_premium_subscriptions() additionally downgrades expired users to "free"
so the stored data, admin counts and broadcast targeting stay truthful.
"""
import asyncio
import logging
from datetime import datetime, timedelta, UTC
from typing import Optional

from sql import users as users_db
from firebase_service import send_fcm_data_message
from notification_service import create_notification, get_user_language, translate
from tz_utils import get_app_timezone
from utils import ensure_utc_datetime

logger = logging.getLogger(__name__)

# Only subscriptions that ended this recently get a "Premium has ended" notification.
# Older ones (e.g. everything already expired when this job first ships) are downgraded
# silently instead of flooding long-lapsed users with stale notices.
NOTIFY_IF_ENDED_WITHIN = timedelta(days=7)


def active_premium_filter(now: Optional[datetime] = None):
    """SQL condition: users who currently have premium (lifetime or not yet expired)."""
    return users_db.active_premium(now or datetime.now(UTC))


def effectively_free_filter(now: Optional[datetime] = None):
    """SQL condition: users without active premium (free, or premium that has expired)."""
    return users_db.effectively_free(now or datetime.now(UTC))


def _format_end_date(expired_at: datetime, lang: str) -> str:
    local = expired_at.astimezone(get_app_timezone())
    return local.strftime("%Y-%m-%d") if lang == "my" else local.strftime("%b %d, %Y").replace(" 0", " ")


async def expire_premium_subscriptions(now: Optional[datetime] = None) -> int:
    """Downgrade every expired premium user to free, notify them and refresh their app.

    Each downgrade is conditional on the user still being premium with the same expiry
    date, so an admin extension that lands meanwhile wins and overlapping runs can't
    notify twice. The expiry date is kept (and copied to premium_ended_at) as history.
    Returns the number of users downgraded.
    """
    now = now or datetime.now(UTC)
    candidates = await users_db.list_fields(
        ["subscription_expires_at", "fcm_token"],
        users_db.users.c.subscription_type == "premium",
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
        logger.info(f"Premium expired for user {user['_id']} (ended {expired_at.isoformat()}); downgraded to free")

        if now - expired_at > NOTIFY_IF_ENDED_WITHIN:
            continue  # long-lapsed: silent downgrade, no notice (and nothing premium to refresh)

        try:
            lang = await get_user_language(user["_id"])
            await create_notification(
                user_id=user["_id"],
                notification_type="subscription_expired",
                title=translate("subscription_expired_title", lang),
                message=translate("subscription_expired_msg", lang, date=_format_end_date(expired_at, lang)),
            )
        except Exception as e:
            logger.error(f"Could not create premium-ended notification for user {user['_id']}: {e}")

        # Silent data message: the app reloads the profile and drops premium UI at once.
        if user.get("fcm_token"):
            try:
                await asyncio.to_thread(
                    send_fcm_data_message, user["fcm_token"],
                    {"type": "subscription_updated", "subscription_type": "free"},
                )
            except Exception as e:
                logger.warning(f"Could not send subscription refresh push to user {user['_id']}: {e}")

    if downgraded:
        logger.info(f"Premium expiry job: downgraded {downgraded} user(s)")
    return downgraded
