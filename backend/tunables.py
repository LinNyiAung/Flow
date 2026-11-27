"""Tunable numbers and times: the owner's admin-editable settings (trial length, reminder days, unusual-spending bars,
job times). One record, stored as JSON text in app_settings under SETTINGS_KEY, cached in this process and reloaded every
60 s (like app_control). The record is flat: the settings that differ from their default, plus "version".
Readers (`get`, `amount_for`, `time_of`) never raise for stored data: a bad stored value is ignored (its default used)
and warned about once.
"""
import asyncio
import copy
import json
import logging
import math
from dataclasses import dataclass
from datetime import time
from typing import Any, Dict, List, Mapping, Optional, Set, Tuple

from sql import tunables as tunables_db

logger = logging.getLogger(__name__)

SETTINGS_KEY = tunables_db.SETTINGS_KEY

CURRENCIES = ("mmk", "usd", "thb")


@dataclass(frozen=True)
class Setting:
    key: str
    kind: str  # "days" | "day_list" | "number" | "amounts" | "time"
    default: Any
    group: str
    label: str
    note: str
    min: Any = None  # amounts: None (anything above 0); time: "HH:MM"
    max: Any = None  # amounts: {currency: largest}; time: "HH:MM"


_AMOUNT_CAP = {"mmk": 100_000_000, "usd": 100_000, "thb": 2_000_000}

CATALOGUE: Tuple[Setting, ...] = (
    Setting("trial_days", "days", 30, "Trial and plans", "Free trial length (days)",
            "Length of a free trial claimed after the change; trials already running keep their end date.", 7, 90),
    Setting("ends_soon_days", "days", 3, "Trial and plans", 'Trial / renewal "ends soon" reminder (days before)',
            'How many days before a trial or paid plan ends the "ends soon" reminder goes out; the "last day" reminder '
            "stays at 1 day. Applies from the next hourly run; a reminder already sent isn't sent again.", 2, 14),
    Setting("goal_reminder_days", "day_list", [14, 7, 3, 1], "Reminders", "Goal reminder days (days before the target date)",
            "Days before a goal's target date when a reminder is sent. Applies from the next reminder run.", 1, 60),
    Setting("budget_ending_soon_days", "days", 3, "Reminders", 'Budget "ending soon" (days before the end)',
            "Days before a budget period ends when the \"ending soon\" notice is sent. Applies from the next reminder run.",
            1, 14),
    Setting("large_expense_multiple", "number", 3, "Unusual spending", "Large expense: times the person's average",
            "One expense counts as large when it is this many times the person's average expense (and at least the "
            "minimum below). Applies to new expenses.", 1.5, 10),
    Setting("large_expense_min", "amounts", {"mmk": 100000, "usd": 100, "thb": 2000}, "Unusual spending",
            "Large expense: minimum amount, per currency",
            "The smallest amount that can count as a large expense, per currency. With no spending history yet, the bar "
            "is 1.5 times this. Applies to new expenses.", None, _AMOUNT_CAP),
    Setting("unusual_week_multiple", "number", 1.5, "Unusual spending", "Unusual week: times the usual weekly amount",
            "A category's week counts as unusual when its spending is this many times its usual weekly amount. Applies "
            "from the next daily check.", 1.1, 5),
    Setting("unusual_week_min_diff", "amounts", {"mmk": 50000, "usd": 50, "thb": 1000}, "Unusual spending",
            "Unusual week: minimum difference, per currency",
            "And the week must be at least this much above usual, per currency. Applies from the next daily check.",
            None, _AMOUNT_CAP),
    Setting("invite_days", "days", 14, "Family", "Family invite validity (days)",
            "How long a new family invitation stays open; invitations already sent keep their expiry.", 1, 60),
    Setting("reminders_time", "time", "09:00", "Job times", "Reminders time",
            "Local time of goal, budget and payment reminders, and of \"budget now active\". A change applies today if "
            "that time hasn't passed yet; nothing runs twice in a day.", "07:00", "21:00"),
    Setting("unusual_spending_time", "time", "08:00", "Job times", "Unusual spending check time",
            "Local time of the daily unusual-spending check. Same rule: nothing runs twice in a day.", "07:00", "21:00"),
    Setting("weekly_report_time", "time", "05:00", "Job times", "Weekly report time",
            "Monday's local time for the weekly report. The app's \"Next insight\" follows it.", "01:00", "23:00"),
    Setting("monthly_report_time", "time", "06:00", "Job times", "Monthly report time",
            "Local time on the 1st for the monthly report. The app's \"Next insight\" follows it.", "01:00", "23:00"),
)
_BY_KEY: Dict[str, Setting] = {s.key: s for s in CATALOGUE}


class SettingsInvalid(ValueError):
    def __init__(self, errors: Dict[str, str]):
        super().__init__("; ".join(f"{k}: {m}" for k, m in errors.items()))
        self.errors = errors


class SettingsConflict(Exception):
    """The stored record is no longer at the version the editor saw."""


# ---- validation of one value ----

def _whole(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _number(value: Any) -> bool:
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        return False
    try:
        return math.isfinite(value)
    except OverflowError:  # an int too large for a float
        return False


def _minutes(text: str) -> int:
    return int(text[:2]) * 60 + int(text[3:])


def _check(s: Setting, value: Any) -> Any:
    """The cleaned value; ValueError (one readable message) when it isn't allowed for this setting."""
    if s.kind == "days":
        if not _whole(value) or not s.min <= value <= s.max:
            raise ValueError(f"Must be a whole number of days from {s.min} to {s.max}")
        return value
    if s.kind == "day_list":
        if not isinstance(value, (list, tuple)) or not 1 <= len(value) <= 4:
            raise ValueError("Give 1 to 4 days")
        if not all(_whole(d) and s.min <= d <= s.max for d in value):
            raise ValueError(f"Each must be a whole number of days from {s.min} to {s.max}")
        if len(set(value)) != len(value):
            raise ValueError("The days must all be different")
        return sorted(value, reverse=True)
    if s.kind == "number":
        if not _number(value) or not s.min <= value <= s.max:
            raise ValueError(f"Must be a number from {s.min} to {s.max}")
        return value
    if s.kind == "amounts":
        if not isinstance(value, Mapping) or set(value) != set(CURRENCIES):
            raise ValueError("Give an amount for each of mmk, usd and thb")
        for cur in CURRENCIES:
            if not _number(value[cur]) or not 0 < value[cur] <= s.max[cur]:
                raise ValueError(f"The {cur} amount must be above 0 and at most {s.max[cur]:,}")
        return {cur: value[cur] for cur in CURRENCIES}
    if s.kind == "time":
        ok = (isinstance(value, str) and len(value) == 5 and value[2] == ":" and value[:2].isdigit()
              and value[3:].isdigit() and value.isascii())
        if ok:
            h, m = int(value[:2]), int(value[3:])
            ok = h < 24 and m % 15 == 0 and m < 60 and _minutes(s.min) <= h * 60 + m <= _minutes(s.max)
        if not ok:
            raise ValueError(f"Must be a time as HH:MM on 15-minute steps, from {s.min} to {s.max}")
        return value
    raise ValueError("Unknown kind")  # pragma: no cover


def _cross_error(values: Mapping[str, Any]) -> Optional[str]:
    if values["ends_soon_days"] >= values["trial_days"]:
        return "Must be less than the trial length"
    return None


# ---- the cache ----

_values: Dict[str, Any] = {}  # the valid stored values that differ from defaults (the cache: tests set and restore it)
_version = 0  # the stored record's version (0 when nothing is stored)
_warned: Set[Tuple[str, str]] = set()  # (key, repr(value)) already logged, so the 60 s reload does not repeat it

# Bumped by every save (before the write and after the cache changes): a load whose read overlapped a save drops its
# possibly stale result.
_write_gen = 0


def _effective() -> Dict[str, Any]:
    return {s.key: copy.deepcopy(_values.get(s.key, s.default)) for s in CATALOGUE}


def _warn_once(key: str, value: Any, why: str) -> None:
    token = (key, repr(value))
    if token not in _warned:
        _warned.add(token)
        logger.warning("Ignoring the stored setting %s=%r: %s", key, value, why)


def _parse_stored(text: Optional[str]) -> Tuple[Dict[str, Any], int]:
    """(the valid stored overrides, the version). Anything unreadable is ignored (warned once), never raised."""
    if text is None:
        return {}, 0
    try:
        raw = json.loads(text)
        if not isinstance(raw, dict):
            raise ValueError("not an object")
    except ValueError as e:
        _warn_once("(record)", text, f"not a JSON object ({e}); every default applies")
        return {}, 0
    version = raw.get("version")
    version = version if _whole(version) and version >= 0 else 0
    out: Dict[str, Any] = {}
    for key, value in raw.items():
        if key == "version":
            continue
        s = _BY_KEY.get(key)
        if s is None:
            _warn_once(key, value, "unknown setting")
            continue
        try:
            out[key] = _check(s, value)
        except ValueError as e:
            _warn_once(key, value, str(e))
    merged = {s.key: out.get(s.key, s.default) for s in CATALOGUE}
    if "ends_soon_days" in out and _cross_error(merged):
        _warn_once("ends_soon_days", out["ends_soon_days"], "not less than the trial length")
        del out["ends_soon_days"]
    return out, version


async def load() -> None:
    global _values, _version
    gen = _write_gen
    text = await tunables_db.read()
    values, version = _parse_stored(text)
    if _write_gen != gen:
        logger.debug("Discarding a stale tunables snapshot: a save happened while it was being read")
        return
    _values, _version = values, version


def validate(values: Mapping[str, Any], base: Optional[Mapping[str, Any]] = None) -> dict:
    """The full effective set after merging `values` over `base` (default: this process's current effective values).
    SettingsInvalid carries every field error at once (plus the cross-field one under ends_soon_days)."""
    if not isinstance(values, Mapping):
        raise SettingsInvalid({"settings": "The settings must be an object"})
    merged = copy.deepcopy(dict(base)) if base is not None else _effective()
    errors: Dict[str, str] = {}
    for key, value in values.items():
        s = _BY_KEY.get(key)
        if s is None:
            errors[str(key)] = "Unknown setting"
            continue
        try:
            merged[key] = _check(s, value)
        except ValueError as e:
            errors[key] = str(e)
    if "ends_soon_days" not in errors and "trial_days" not in errors:
        msg = _cross_error(merged)
        if msg:
            errors["ends_soon_days"] = msg
    if errors:
        raise SettingsInvalid(errors)
    return merged


async def save(values: Mapping[str, Any], expected_version: int, admin_id: str) -> dict:
    """Validate and store `values` (merged over the current ones) if the stored record is still at `expected_version`.
    Returns {"changes": [(key, old, new), ...], "version": int}. SettingsInvalid or SettingsConflict; nothing is written
    then. The base is the STORED row, never this process's cache (which may be up to 60 s old): a save made at the right
    version can't write back old values for other keys. When nothing differs, nothing is written and "changes" is []."""
    global _write_gen, _values, _version
    stored_values, stored_version = _parse_stored(await tunables_db.read())
    if stored_version != expected_version:
        await load()
        raise SettingsConflict()
    old = {s.key: copy.deepcopy(stored_values.get(s.key, s.default)) for s in CATALOGUE}
    full = validate(values, old)
    changes = [(s.key, old[s.key], full[s.key]) for s in CATALOGUE if old[s.key] != full[s.key]]
    if not changes:
        await load()
        return {"changes": [], "version": stored_version}
    record: Dict[str, Any] = {"version": expected_version + 1}
    new_values = {}
    for s in CATALOGUE:
        if full[s.key] != s.default:
            record[s.key] = full[s.key]
            new_values[s.key] = full[s.key]
    _write_gen += 1
    if not await tunables_db.write_if_version(json.dumps(record, ensure_ascii=False), expected_version):
        await load()
        raise SettingsConflict()
    _values, _version = new_values, expected_version + 1
    _write_gen += 1
    logger.info("Tunable settings saved by admin %s (version %s)", admin_id, _version)
    return {"changes": changes, "version": _version}


_refresh_task: asyncio.Task | None = None


async def _refresh_forever(interval: float) -> None:
    while True:
        await asyncio.sleep(interval)
        try:
            await load()
        except Exception:  # noqa: BLE001 - keep the last good cache and try again next round
            logger.exception("Could not refresh the tunable settings from the database")


def start_refresh_loop(interval: float = 60.0) -> asyncio.Task:
    """Reload the cache every `interval` seconds on the running event loop (call once from app startup)."""
    global _refresh_task
    loop = asyncio.get_running_loop()
    if _refresh_task is not None and not _refresh_task.done() and _refresh_task.get_loop() is loop:
        return _refresh_task
    _refresh_task = loop.create_task(_refresh_forever(interval), name="tunables-refresh")
    return _refresh_task


# ---- readers ----

def get(key: str) -> Any:
    """The effective value: the cached valid stored value, else the default. KeyError for an unknown key."""
    s = _BY_KEY[key]
    return copy.deepcopy(_values.get(key, s.default))


def amount_for(key: str, currency: str) -> float:
    """The currency's amount of a per-currency setting (the usd amount for any other currency)."""
    amounts = get(key)
    return amounts.get(currency.lower() if isinstance(currency, str) else "", amounts["usd"])


def time_of(key: str) -> time:
    value = get(key)
    return time(int(value[:2]), int(value[3:]))


def version() -> int:
    return _version


def catalogue() -> List[dict]:
    """Every setting with its current value, for the admin panel."""
    return [{"key": s.key, "kind": s.kind, "group": s.group, "label": s.label, "note": s.note,
             "default": copy.deepcopy(s.default), "min": copy.deepcopy(s.min), "max": copy.deepcopy(s.max),
             "value": get(s.key), "changed": s.key in _values and _values[s.key] != s.default} for s in CATALOGUE]
