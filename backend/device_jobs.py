"""Scheduled jobs for the devices a person is signed in on (see sql/devices.py).

- send_sign_in_reminders: one push to each device whose sign-in has expired, once.
- delete_stale_devices: forgets devices that have not been seen for 60 days.
"""
import asyncio
import logging
from datetime import UTC, datetime
from typing import Optional

from firebase_service import send_push
from notification_service import NOTIFICATION_TRANSLATIONS, translate
from sql import devices as devices_db

logger = logging.getLogger(__name__)


async def send_sign_in_reminders(now: Optional[datetime] = None) -> int:
    """Tells each device whose sign-in has expired that it was signed out; returns the pushes sent.

    The reminder is stamped in the database in the same statement that claims it, before anything is sent: a crash
    in between loses at most one reminder and never sends one twice. A failed push is not retried.
    The push carries no amounts, names or ids, and no in-app notification is created for it.
    """
    now = now or datetime.now(UTC)
    claimed = await devices_db.claim_sign_in_reminders(now)

    # Group by language: one push call per language, each to all of its devices.
    by_language: dict = {}
    for row in claimed:
        language = row["language"] if row["language"] in NOTIFICATION_TRANSLATIONS else "en"
        by_language.setdefault(language, []).append(row["token"])

    sent = 0
    for language, tokens in by_language.items():
        try:
            # The blocking Firebase call runs in a worker thread; the dead-token clean-up runs back on the loop.
            result = await asyncio.to_thread(
                send_push, tokens, translate("sign_in_reminder_title", language),
                translate("sign_in_reminder_msg", language), {"type": "sign_in_reminder"})
            await devices_db.delete_tokens(result.get("unregistered") or [])
            sent += result.get("success", 0)
        except Exception as e:
            logger.error("Sign-in reminder push failed for %d device(s): %s", len(tokens), e)
    return sent


async def delete_stale_devices(now: Optional[datetime] = None) -> int:
    """Deletes the devices not seen for 60 days; returns how many."""
    deleted = await devices_db.delete_stale(now or datetime.now(UTC))
    if deleted:
        logger.info("Deleted %d stale device(s)", deleted)
    return deleted
