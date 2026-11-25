"""App control: the owner's switches (pause a feature for everyone) and maintenance mode.

One settings document, stored as JSON text in app_settings under SETTINGS_KEY, cached in this process and reloaded
every 60 s (like plans.store). Routes call `require_on(key, lang)` before doing any work; the admin API never calls it.
"""
import asyncio
import json
import logging
import re
from datetime import datetime
from typing import Any, Dict, List, Mapping, Optional

from fastapi import HTTPException, status

from notification_service import translate
from sql import app_control as app_control_db

logger = logging.getLogger(__name__)

SWITCHES = ("chat", "voice", "receipts", "budget_ideas", "reports", "custom_reports", "translation",
            "signups", "free_trial", "family_new")
SETTINGS_KEY = app_control_db.SETTINGS_KEY
MAX_MESSAGE = 300
MAX_TESTERS = 50

_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _default() -> Dict[str, Any]:
    return {
        "switches": {k: {"paused": False, "message_en": "", "message_my": ""} for k in SWITCHES},
        "maintenance": {"on": False, "message_en": "", "message_my": "", "back_by": None, "testers": []},
    }


_doc: Dict[str, Any] = _default()
_testers: frozenset = frozenset()


# ---- validation ----

def _text(value: Any, label: str) -> str:
    if value is None:
        return ""
    if not isinstance(value, str):
        raise ValueError(f"{label} must be text")
    value = value.strip()
    if len(value) > MAX_MESSAGE:
        raise ValueError(f"{label} is longer than {MAX_MESSAGE} characters")
    return value


def validate(doc: Mapping) -> dict:
    """The document with every switch present and values cleaned; ValueError (one readable message) if invalid."""
    if not isinstance(doc, Mapping):
        raise ValueError("The settings must be an object")
    out = _default()
    switches = doc.get("switches") or {}
    if not isinstance(switches, Mapping):
        raise ValueError("switches must be an object")
    for key, sw in switches.items():
        if key not in SWITCHES:
            raise ValueError(f"Unknown switch: {key}")
        if not isinstance(sw, Mapping):
            raise ValueError(f"Switch {key} must be an object")
        paused = sw.get("paused", False)
        if not isinstance(paused, bool):
            raise ValueError(f"Switch {key}: paused must be true or false")
        out["switches"][key] = {"paused": paused,
                                "message_en": _text(sw.get("message_en"), f"Switch {key}: the English message"),
                                "message_my": _text(sw.get("message_my"), f"Switch {key}: the Myanmar message")}
    m = doc.get("maintenance") or {}
    if not isinstance(m, Mapping):
        raise ValueError("maintenance must be an object")
    on = m.get("on", False)
    if not isinstance(on, bool):
        raise ValueError("Maintenance: on must be true or false")
    back_by = m.get("back_by")
    if back_by is not None and back_by != "":
        if not isinstance(back_by, str):
            raise ValueError("Maintenance: back_by must be a date and time")
        try:
            when = datetime.fromisoformat(back_by.strip())
        except ValueError:
            raise ValueError("Maintenance: back_by is not a valid date and time")
        if when.tzinfo is None or when.utcoffset() is None:
            raise ValueError("Maintenance: back_by needs a time zone (for example +06:30 or Z)")
        back_by = when.isoformat()
    else:
        back_by = None
    testers = m.get("testers") or []
    if not isinstance(testers, (list, tuple)):
        raise ValueError("Maintenance: testers must be a list of emails")
    clean: List[str] = []
    for t in testers:
        if not isinstance(t, str):
            raise ValueError("Maintenance: each tester must be an email")
        e = t.strip().lower()
        if not _EMAIL.match(e):
            raise ValueError(f"Maintenance: {t.strip() or '(empty)'} is not an email address")
        if e not in clean:
            clean.append(e)
    if len(clean) > MAX_TESTERS:
        raise ValueError(f"Maintenance: at most {MAX_TESTERS} testers")
    out["maintenance"] = {"on": on, "message_en": _text(m.get("message_en"), "Maintenance: the English message"),
                          "message_my": _text(m.get("message_my"), "Maintenance: the Myanmar message"),
                          "back_by": back_by, "testers": clean}
    return out


# ---- the cache ----

def _set_cache(doc: Dict[str, Any]) -> None:
    global _doc, _testers
    _doc = doc
    _testers = frozenset(doc["maintenance"]["testers"])


def snapshot() -> dict:
    """A copy of the cached document."""
    return json.loads(json.dumps(_doc))


# Bumped by every save (before the write and after the cache changes): a load whose read overlapped a save drops its
# possibly stale result.
_write_gen = 0


def _parse_stored(text: Optional[str]) -> Dict[str, Any]:
    """The stored text as a document: unknown switch keys are dropped, missing ones default, anything unreadable
    leaves nothing paused (logged)."""
    if text is None:
        return _default()
    try:
        raw = json.loads(text)
        if not isinstance(raw, Mapping):
            raise ValueError("not an object")
        known = dict(raw)
        sw = known.get("switches")
        if isinstance(sw, Mapping):
            for k in [k for k in sw if k not in SWITCHES]:
                logger.warning("Ignoring the stored app switch %r: unknown", k)
            known["switches"] = {k: v for k, v in sw.items() if k in SWITCHES}
        return validate(known)
    except Exception as e:  # noqa: BLE001 - a bad stored document must never stop the app
        logger.warning("Ignoring the stored app control settings (%s: %s); nothing is paused", type(e).__name__, e)
        return _default()


async def load() -> None:
    gen = _write_gen
    text = await app_control_db.read_settings()
    doc = _parse_stored(text)
    if _write_gen != gen:
        logger.debug("Discarding a stale app control snapshot: a save happened while it was being read")
        return
    _set_cache(doc)


async def save(doc: Mapping, admin_id: str) -> dict:
    """Validate, store and cache the document; returns the saved document. ValueError when invalid (nothing written)."""
    global _write_gen
    clean = validate(doc)
    _write_gen += 1
    await app_control_db.write_settings(json.dumps(clean, ensure_ascii=False))
    _set_cache(clean)
    _write_gen += 1
    logger.info("App control saved by admin %s", admin_id)
    return snapshot()


_refresh_task: asyncio.Task | None = None


async def _refresh_forever(interval: float) -> None:
    while True:
        await asyncio.sleep(interval)
        try:
            await load()
        except Exception:  # noqa: BLE001 - keep the last good cache and try again next round
            logger.exception("Could not refresh the app control settings from the database")


def start_refresh_loop(interval: float = 60.0) -> asyncio.Task:
    """Reload the cache every `interval` seconds on the running event loop (call once from app startup)."""
    global _refresh_task
    loop = asyncio.get_running_loop()
    if _refresh_task is not None and not _refresh_task.done() and _refresh_task.get_loop() is loop:
        return _refresh_task
    _refresh_task = loop.create_task(_refresh_forever(interval), name="app-control-refresh")
    return _refresh_task


# ---- switches ----

def _lang(lang: str) -> str:
    return "my" if lang == "my" else "en"


def paused_message(key: str, lang: str) -> str:
    lang = _lang(lang)
    own = _doc["switches"].get(key, {}).get(f"message_{lang}", "")
    return own or translate("feature_paused_msg", lang, feature=translate(f"app_switch_{key}", lang))


def both_languages(key: str) -> str:
    """The paused text in both languages (a signed-out refusal doesn't know the language)."""
    return paused_message(key, "en") + "\n\n" + paused_message(key, "my")


def paused_detail(key: str, lang: str) -> dict:
    return {"code": "feature_paused", "feature": key, "resets_at": None, "upgrade_available": False,
            "message": paused_message(key, lang)}


class FeaturePaused(HTTPException):
    def __init__(self, key: str, lang: str):
        detail = {k: v for k, v in paused_detail(key, lang).items() if k not in ("resets_at", "upgrade_available")}
        super().__init__(status_code=status.HTTP_403_FORBIDDEN, detail=detail)


def is_paused(key: str) -> bool:
    return bool(_doc["switches"].get(key, {}).get("paused", False))


def require_on(key: str, lang: str = "en") -> None:
    if is_paused(key):
        raise FeaturePaused(key, lang)


# ---- maintenance ----

def maintenance_on() -> bool:
    return bool(_doc["maintenance"]["on"])


def maintenance_message(lang: str) -> str:
    lang = _lang(lang)
    return _doc["maintenance"].get(f"message_{lang}", "") or translate("maintenance_msg", lang)


def maintenance_back_by() -> Optional[datetime]:
    value = _doc["maintenance"].get("back_by")
    return datetime.fromisoformat(value) if value else None


def is_tester(email: Optional[str]) -> bool:
    return bool(email) and email.strip().lower() in _testers
