"""Each person's timezone, and the zone of a book (spec: docs/superpowers/specs/2026-11-18-calendar-dates-design.md,
"Where a person's timezone comes from" and "Today on the server").

The app sends the phone's IANA zone name on every request (X-Timezone). get_current_user hands it to
remember_timezone, which saves a valid name to users.timezone when it differs (at most once per 24 hours) and ignores
anything else; nothing about the header can fail a request. Without a saved zone (NULL) a person is in the default zone (tz_utils.default_zone).

Whose zone a request uses:
- user_zone(person): anything shown or sent to that person (in a family book, the member asking).
- book_zone(book_id): work done once for the whole book (a budget's stored status, a recurrence pointer re-arm, a
  rollover): a personal book's person, a family book's current owner.
"""
import logging
from datetime import timedelta, tzinfo
from typing import Optional

from sql import books as books_db
from sql import families as families_db
from sql import users as users_db
from tz_utils import as_utc, default_zone, is_valid_zone_name, utc_now, zone_for

logger = logging.getLogger(__name__)

TIMEZONE_HEADER = "X-Timezone"
ZONE_CHANGE_INTERVAL = timedelta(hours=24)  # a saved zone changes at most this often


async def remember_timezone(user: dict, header_value: Optional[str]) -> dict:
    """The user dict with `timezone` set to the header's zone when the header names a valid zone that may be saved,
    else unchanged (the request then goes on in the saved zone).

    The saved zone changes at most once per ZONE_CHANGE_INTERVAL (users.timezone_changed_at), so a client that sends
    a new zone on every request can't move its day-based limits (quota weeks and months) around; the first zone (none
    saved yet) is always taken. A failing save is logged and the request goes on in the header's zone."""
    stored = user.get("timezone")
    if not is_valid_zone_name(header_value) or header_value == stored:
        return user
    now = utc_now()
    last_change_before = now - ZONE_CHANGE_INTERVAL
    changed_at = as_utc(user.get("timezone_changed_at"))
    if stored is not None and changed_at is not None and changed_at > last_change_before:
        return user  # changed less than 24 hours ago: keep the saved zone
    try:
        if not await users_db.set_timezone(user["_id"], header_value, now, last_change_before):
            return user  # another request changed it first
    except Exception:  # noqa: BLE001 - the header must never fail a request
        logger.exception("Could not save the timezone of user %s", user.get("_id"))
    return {**user, "timezone": header_value, "timezone_changed_at": now}


def user_zone(user: dict) -> tzinfo:
    """The person's zone (the default zone when none is saved)."""
    return zone_for(user.get("timezone"))


async def person_zone(user_id: str) -> tzinfo:
    """user_zone of the person with this id, read from the database (the default zone when none is saved)."""
    return zone_for(await users_db.timezone_of(user_id))


async def book_zone(book_id: str) -> tzinfo:
    """The zone of once-per-book work: a personal book's person's, a family book's current owner's. A missing book (or
    an owner without a saved zone): the default zone."""
    book = await books_db.get_book_row(book_id)
    if book is None:
        return default_zone()
    if book["kind"] == "personal":
        return await person_zone(book["person_id"])
    return zone_for(await families_db.owner_timezone(book["family_id"]))
