"""In-memory provider health: which provider (or provider+model) is cooling off after a failure.

One backend process, so plain dicts are enough. The last error / last success are also written
to ai_provider_status (persist_failure / persist_success) so the admin panel can show them.
"""
import logging
import time
from datetime import datetime, timezone
from typing import Optional

from .errors import ProviderFailure
from .features import PROVIDERS
from .types import Target

logger = logging.getLogger(__name__)

PROVIDER_COOLOFF = 300.0     # auth, billing, not_configured, repeated server errors
MODEL_COOLOFF = 300.0        # model_not_found
RATE_LIMIT_COOLOFF = 60.0    # rate_limit (provider+model)
SERVER_STREAK_LIMIT = 2

_provider_until: dict[str, float] = {}
_pair_until: dict[tuple[str, str], float] = {}
_server_streak: dict[str, int] = {}


def _now(now: Optional[float]) -> float:
    return time.time() if now is None else now


def reset() -> None:
    """Forget all cool-off state (tests, and the admin panel's reset)."""
    _provider_until.clear()
    _pair_until.clear()
    _server_streak.clear()


def is_available(t: Target, now: Optional[float] = None) -> bool:
    now = _now(now)
    if _provider_until.get(t.provider, 0.0) > now:
        return False
    return _pair_until.get((t.provider, t.model), 0.0) <= now


def mark_failure(f: ProviderFailure, now: Optional[float] = None) -> None:
    now = _now(now)
    if f.kind in ("auth", "billing", "not_configured"):
        _cool_provider(f.provider, now)
    elif f.kind == "server":
        _server_streak[f.provider] = _server_streak.get(f.provider, 0) + 1
        if _server_streak[f.provider] >= SERVER_STREAK_LIMIT:
            _cool_provider(f.provider, now)
    elif f.kind == "model_not_found":
        _pair_until[(f.provider, f.model)] = now + MODEL_COOLOFF
    elif f.kind == "rate_limit":
        _pair_until[(f.provider, f.model)] = now + RATE_LIMIT_COOLOFF
    # refusal, unusable and a single timeout never cool anything off


def _cool_provider(provider: str, now: float) -> None:
    _provider_until[provider] = now + PROVIDER_COOLOFF
    _server_streak[provider] = 0


def mark_success(t: Target) -> None:
    """A success proves the target works: clear its cool-offs and the consecutive-server-failure count."""
    _server_streak[t.provider] = 0
    _provider_until.pop(t.provider, None)
    _pair_until.pop((t.provider, t.model), None)


def snapshot(now: Optional[float] = None) -> dict[str, dict]:
    """Per provider: cooling_until (epoch seconds or None) and cooling_models {model: until}. Expired entries are left out."""
    now = _now(now)
    out: dict[str, dict] = {p: {"cooling_until": None, "cooling_models": {}} for p in PROVIDERS}
    for provider, until in _provider_until.items():
        if until > now:
            out.setdefault(provider, {"cooling_until": None, "cooling_models": {}})["cooling_until"] = until
    for (provider, model), until in _pair_until.items():
        if until > now:
            out.setdefault(provider, {"cooling_until": None, "cooling_models": {}})["cooling_models"][model] = until
    return out


async def persist_failure(f: ProviderFailure) -> None:
    """Store the (already redacted) last error for the provider. Database errors are swallowed."""
    try:
        from sql import ai_settings
        await ai_settings.record_provider_error(f.provider, f.message, datetime.now(timezone.utc))
    except Exception as e:  # noqa: BLE001
        logger.warning("could not record %s provider error: %s", f.provider, type(e).__name__)


async def persist_success(t: Target) -> None:
    """Store the time of the provider's last success. Database errors are swallowed."""
    try:
        from sql import ai_settings
        await ai_settings.record_provider_success(t.provider, datetime.now(timezone.utc))
    except Exception as e:  # noqa: BLE001
        logger.warning("could not record %s provider success: %s", t.provider, type(e).__name__)
