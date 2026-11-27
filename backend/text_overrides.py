"""Admin overrides of the server texts (notification_service.NOTIFICATION_TRANSLATIONS and the two emails).

The code defaults stay the source of truth; an override replaces one (key, language) text. Overrides live in the
text_overrides table, are cached in this process and reloaded every 60 s (like app_control). `get` reads the cache
only, so notification_service.translate stays synchronous and never touches the database.

This module must not import notification_service at import time (translate imports this module): it does so inside
the functions that need the defaults.
"""
import asyncio
import logging
import string
from typing import Any, Dict, Optional, Set, Tuple

from sql import text_overrides as overrides_db

logger = logging.getLogger(__name__)

LANGS = ("en", "my")
MAX_TEXT = 1000

_AREAS = (
    ("plans", ("plan_", "trial_", "subscription_", "upgrade_", "payment_")),
    ("family", ("family_",)),
    ("budgets", ("budget_", "large_", "unusual_")),
    ("goals", ("goal_",)),
    ("Ko Toe Pwar", ("chat_", "insight_", "custom_", "weekly_", "monthly_", "entry_")),
    ("App control", ("app_", "feature_", "maintenance_", "announcement_")),
    ("contact", ("contact_",)),
    ("emails", ("email_",)),
)

_cache: Dict[Tuple[str, str], dict] = {}
# Stored rows (for keys the code still has) that no longer validate. get() never serves them; the admin listing shows
# them with the reason so the editor can save over or reset them (their version is the stored one).
_invalid: Dict[Tuple[str, str], dict] = {}
_warned: Set[Tuple[str, str, str]] = set()  # (key, lang, text) already logged, so the 60 s reload does not repeat it

# Texts that sit on one line (a header or a button label): a line break would break the email.
_SINGLE_LINE = frozenset({"email_verify_subject", "email_reset_subject", "email_verify_button",
                          "email_verify_heading", "email_reset_heading",
                          "email_changed_subject", "email_changed_heading"})
# Bumped by every write (before the database call and after the cache changes): a load whose read overlapped a write
# drops its possibly stale result.
_write_gen = 0


class TextConflict(Exception):
    """The text was changed (or removed) by someone else since the editor loaded it."""


# ---- the defaults and their placeholders ----

def defaults() -> Dict[str, Dict[str, str]]:
    """{key: {"en": ..., "my": ...}} from the code defaults."""
    from notification_service import NOTIFICATION_TRANSLATIONS
    return {k: {lang: NOTIFICATION_TRANSLATIONS[lang].get(k) for lang in LANGS if k in NOTIFICATION_TRANSLATIONS[lang]}
            for k in NOTIFICATION_TRANSLATIONS["en"]}


def _fields(template: str) -> Set[str]:
    """The {name} fields of a template; ValueError (readable) for anything the server will not store: unbalanced
    braces, positional or dotted fields, a format spec or conversion."""
    names: Set[str] = set()
    try:
        parsed = list(string.Formatter().parse(template))
    except ValueError as e:
        raise ValueError(f"The braces are not balanced ({e}). Write each placeholder as {{name}}.") from None
    for _literal, name, spec, conversion in parsed:
        if name is None:
            continue
        if not name.isidentifier():
            shown = "{" + name + "}"
            raise ValueError(f"{shown} is not a valid placeholder. Use only names such as {{date}}.")
        if spec or conversion:
            raise ValueError(f"The placeholder {{{name}}} must be plain: no format or conversion after the name.")
        names.add(name)
    return names


def placeholders(key: str) -> Set[str]:
    """The placeholder names of the key's English default."""
    return _fields(defaults()[key]["en"])


def area(key: str) -> str:
    for name, prefixes in _AREAS:
        if key.startswith(prefixes):
            return name
    return "other"


def validate(key: str, lang: str, text: str) -> str:
    """The trimmed text; ValueError (one readable message) if it cannot be stored for (key, lang)."""
    known = defaults()
    if key not in known:
        raise ValueError(f"Unknown text: {key}")
    if lang not in LANGS:
        raise ValueError(f"Unknown text language: {lang}")
    if not isinstance(text, str):
        raise ValueError("The text must be text")
    text = text.strip()
    if not text:
        raise ValueError("The text cannot be empty")
    if len(text) > MAX_TEXT:
        raise ValueError(f"The text is longer than {MAX_TEXT} characters")
    if key in _SINGLE_LINE and ("\n" in text or "\r" in text):
        raise ValueError("This text must stay on one line. Remove the line break.")
    if "{{" in text or "}}" in text:
        raise ValueError("Doubled braces are not allowed. Write a placeholder as {name} and do not use other braces.")
    wanted = _fields(known[key]["en"])
    found = _fields(text)
    missing, extra = sorted(wanted - found), sorted(found - wanted)
    if missing:
        raise ValueError("The text must keep " + ", ".join("{" + n + "}" for n in missing)
                         + " exactly as written (it is filled in when the message is sent).")
    if extra:
        raise ValueError("The text has " + ", ".join("{" + n + "}" for n in extra)
                         + ", which this message does not use.")
    return text


# ---- the cache ----

def get(key: str, lang: str) -> Optional[str]:
    """The cached override for (key, lang), or None (the caller uses the default). Never touches the database."""
    row = _cache.get((key, lang))
    return row["text"] if row else None


def rows() -> Dict[Tuple[str, str], dict]:
    """Copies of the stored rows for the admin listing, each with default_changed. A row that no longer validates is
    included with "invalid": the reason (it is not served; the editor can save over it or reset it)."""
    known = defaults()
    out = {}
    for source in (_cache, _invalid):
        for k, row in source.items():
            current = known.get(k[0], {}).get(k[1])
            out[k] = {**row, "default_changed": row["replaced_default"] != current}
    return out


async def load() -> None:
    """Reload the cache from the database. A stored row that no longer validates is never served; it is kept apart
    (when its key still exists) so the admin panel can show it, and logged once per process."""
    gen = _write_gen
    stored = await overrides_db.read_all()
    fresh: Dict[Tuple[str, str], dict] = {}
    broken: Dict[Tuple[str, str], dict] = {}
    known = defaults()
    for row in stored:
        try:
            validate(row["key"], row["lang"], row["text"])
        except ValueError as e:
            token = (row["key"], row["lang"], row["text"])
            if token not in _warned:
                _warned.add(token)
                logger.warning("Ignoring the stored text override %s/%s: %s", row["key"], row["lang"], e)
            if row["lang"] in known.get(row["key"], {}):
                broken[(row["key"], row["lang"])] = {**row, "invalid": str(e)}
            continue
        fresh[(row["key"], row["lang"])] = row
    if _write_gen != gen:
        logger.debug("Discarding a stale text override snapshot: a write happened while it was being read")
        return
    global _cache, _invalid
    _cache = fresh
    _invalid = broken


async def save(key: str, lang: str, text: str, expected_version: Optional[int], admin_email: str) -> dict:
    """Validate, store and cache an override; returns the stored row. ValueError when invalid, TextConflict when
    `expected_version` is not the stored version (None: there must be no override yet)."""
    global _write_gen
    clean = validate(key, lang, text)
    replaced = defaults()[key][lang]
    _write_gen += 1
    try:
        row = await overrides_db.upsert(key, lang, clean, replaced, expected_version, admin_email)
        if row is None:
            raise TextConflict(f"{key}/{lang}")
        _cache[(key, lang)] = row
        _invalid.pop((key, lang), None)
    finally:
        _write_gen += 1
    logger.info("Text %s/%s saved by %s", key, lang, admin_email)
    return dict(row)


async def reset(key: str, lang: str, expected_version: int, admin_email: str) -> bool:
    """Remove an override (the default applies again). True when removed, False when there was none, TextConflict
    when it is at another version."""
    global _write_gen
    _write_gen += 1
    try:
        done = await overrides_db.delete(key, lang, expected_version)
        if done is None:
            raise TextConflict(f"{key}/{lang}")
        _cache.pop((key, lang), None)
        _invalid.pop((key, lang), None)
    finally:
        _write_gen += 1
    if done:
        logger.info("Text %s/%s reset by %s", key, lang, admin_email)
    return done


_refresh_task: Optional[asyncio.Task] = None


async def _refresh_forever(interval: float) -> None:
    while True:
        await asyncio.sleep(interval)
        try:
            await load()
        except Exception:  # noqa: BLE001 - keep the last good cache and try again next round
            logger.exception("Could not refresh the text overrides from the database")


def start_refresh_loop(interval: float = 60.0) -> asyncio.Task:
    """Reload the cache every `interval` seconds on the running event loop (call once from app startup)."""
    global _refresh_task
    loop = asyncio.get_running_loop()
    if _refresh_task is not None and not _refresh_task.done() and _refresh_task.get_loop() is loop:
        return _refresh_task
    _refresh_task = loop.create_task(_refresh_forever(interval), name="text-overrides-refresh")
    return _refresh_task
