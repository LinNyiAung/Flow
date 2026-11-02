"""Admin API for AI provider switching: per-feature settings, provider status and a "Test" ping.

Everything here that returns provider text (last error, test error) is redacted: no API key, or part of
one, may leave the server. `configured` comes only from client.configured() (key presence).
"""
import asyncio
from datetime import datetime, timedelta, timezone
from typing import Annotated, Optional

from fastapi import APIRouter, Depends, HTTPException, Path, status
from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from admin_utils import log_admin_action, require_admin_or_super, require_moderator_or_above
from ai_providers import health, settings
from ai_providers.clients.base import get_client
from ai_providers.errors import ProviderFailure, classify, redact
from ai_providers.features import FEATURES, PROVIDERS, default_model, known_models
from ai_providers.types import FeatureSetting, Target
from sql import ai_settings as ai_settings_db
from sql import ai_usage as ai_usage_db

router = APIRouter(prefix="/api/admin/ai", tags=["admin", "ai-providers"])

PROVIDER_LABELS = {"openai": "OpenAI", "gemini": "Gemini", "claude": "Claude"}
PING_TIMEOUT = 30.0  # seconds


# ==================== MODELS ====================

_Name = Annotated[str, StringConstraints(strip_whitespace=True, max_length=100)]


class TargetBody(BaseModel):
    """One provider and model. Whether they are allowed is decided by settings.validate (one 422 message list)."""
    model_config = ConfigDict(extra="forbid")
    provider: Annotated[str, StringConstraints(strip_whitespace=True, max_length=32)]
    model: _Name


class SettingBody(BaseModel):
    """`backups`: null = default backups, [] = no backups."""
    model_config = ConfigDict(extra="forbid")
    main: TargetBody
    backups: Optional[list[TargetBody]] = Field(default=None, max_length=10)


class TestBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    model: Optional[Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]] = None


# ==================== HELPERS ====================

def _target_json(t: Target) -> dict:
    return {"provider": t.provider, "model": t.model}


def _setting_json(s: FeatureSetting) -> dict:
    return {"main": _target_json(s.main),
            "backups": None if s.backups is None else [_target_json(b) for b in s.backups],
            "source": s.source}


def _configured(provider: str) -> bool:
    return get_client(provider).configured()


def _feature_json(key: str) -> dict:
    """One feature row: what is in force, what `backups: null` expands to right now, and the panel's own setting."""
    spec = FEATURES[key]
    effective = settings.resolve(key)
    default_backups = settings.default_backups(key, effective.main, _configured)
    panel = settings.panel_setting(key)
    return {
        "key": key,
        "label": spec.label,
        "allowed": list(spec.allowed),
        "effective": _setting_json(effective),
        "default_chain": [_target_json(t) for t in default_backups],
        "panel": None if panel is None else _setting_json(panel),
        "known_models": known_models(key),  # the models this feature's pickers offer, per allowed provider
    }


def _iso(value: Optional[datetime]) -> Optional[str]:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat()


def _epoch_iso(seconds: float) -> str:
    return datetime.fromtimestamp(seconds, tz=timezone.utc).isoformat()


def _require_feature(feature: str) -> None:
    if feature not in FEATURES:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Unknown feature '{feature}'")


def _describe(s: FeatureSetting) -> str:
    backups = "default" if s.backups is None else ("none" if not s.backups else
                                                   ", ".join(f"{b.provider}:{b.model}" for b in s.backups))
    return f"main={s.main.provider}:{s.main.model} backups={backups}"


# ==================== SETTINGS ====================

@router.get("/settings")
async def get_ai_settings(current_admin: dict = Depends(require_moderator_or_above)):
    """Providers (with whether their API key is configured) and every feature's effective setting and known models."""
    return {
        "providers": [
            {"id": p, "label": PROVIDER_LABELS[p], "configured": _configured(p)}
            for p in PROVIDERS
        ],
        "features": [_feature_json(key) for key in FEATURES],
    }


@router.put("/settings/{feature}")
async def put_ai_setting(
    body: SettingBody,
    feature: str = Path(...),
    current_admin: dict = Depends(require_admin_or_super),
):
    """Save the admin-panel setting for a feature. 422 carries the validation messages."""
    _require_feature(feature)
    setting = FeatureSetting(
        Target(body.main.provider, body.main.model),
        None if body.backups is None else tuple(Target(b.provider, b.model) for b in body.backups),
        "panel",
    )
    try:
        await settings.save_panel(feature, setting, current_admin["email"])
    except ValueError as e:
        errors = e.args[0] if e.args and isinstance(e.args[0], list) else [str(e)]
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=errors)

    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"],
        action="ai_setting_update",
        details=f"{feature}: {_describe(setting)}",
    )
    return {**_feature_json(feature), "warnings": settings.setting_warnings(setting, _configured)}


@router.delete("/settings/{feature}")
async def delete_ai_setting(
    feature: str = Path(...),
    current_admin: dict = Depends(require_admin_or_super),
):
    """Remove the admin-panel setting ("use server setting"). Harmless (and not logged) when there is none."""
    _require_feature(feature)
    if await settings.clear_panel(feature):
        await log_admin_action(
            admin_id=current_admin["_id"],
            admin_email=current_admin["email"],
            action="ai_setting_reset",
            details=f"{feature}: use server setting",
        )
    return _feature_json(feature)


# ==================== STATUS ====================

def _state(cooling: bool, last_error_at: Optional[datetime], last_success_at: Optional[datetime]) -> str:
    if cooling:
        return "cooling"
    if last_error_at is not None and (last_success_at is None or last_error_at > last_success_at):
        return "failing"
    if last_success_at is not None:
        return "working"
    return "unused"


@router.get("/status")
async def get_ai_status(current_admin: dict = Depends(require_moderator_or_above)):
    """Per provider: configured, state, cooling, last error / success and answers given by a backup in 24 h.

    `async def` on purpose: health.snapshot() reads unlocked module state, which is only safe on the event loop.
    """
    cooling = health.snapshot()
    stored = await ai_settings_db.get_provider_status()
    since = datetime.now(timezone.utc) - timedelta(hours=24)
    backup_counts = await ai_usage_db.backup_answer_counts(since)

    providers = []
    for p in PROVIDERS:
        row = stored.get(p) or {}
        snap = cooling.get(p) or {}
        until = snap.get("cooling_until")
        models = snap.get("cooling_models") or {}
        last_error = row.get("last_error")
        providers.append({
            "id": p,
            "label": PROVIDER_LABELS[p],
            "configured": _configured(p),
            "state": _state(until is not None, row.get("last_error_at"), row.get("last_success_at")),
            "cooling_until": None if until is None else _epoch_iso(until),
            "cooling_models": [{"model": m, "until": _epoch_iso(u)} for m, u in sorted(models.items())],
            "last_error": None if last_error is None else redact(last_error),
            "last_error_at": _iso(row.get("last_error_at")),
            "last_success_at": _iso(row.get("last_success_at")),
            "backup_answers_24h": backup_counts.get(p, 0),
        })
    return {"providers": providers}


# ==================== TEST ====================

@router.post("/test/{provider}")
async def test_provider(
    provider: str = Path(...),
    body: Optional[TestBody] = None,
    current_admin: dict = Depends(require_admin_or_super),
):
    """Send one tiny request to the provider (a fraction of a cent) to check its key and model.

    A success clears the target's cool-off (it proves the target works) and is recorded in the status;
    a failure is recorded in the status only: a diagnostic ping does not change how requests are routed.
    """
    if provider not in PROVIDERS:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Unknown provider '{provider}'")
    client = get_client(provider)
    if not client.configured():
        return {"ok": False, "error": "not configured"}  # never call an SDK without a key

    model = (body.model if body else None) or default_model("chat", provider)
    target = Target(provider, model)
    try:
        await asyncio.wait_for(client.ping(model), timeout=PING_TIMEOUT)
    except Exception as e:  # noqa: BLE001 - any SDK error is the answer to "does it work?"
        failure = classify(e, provider, model) \
            or ProviderFailure(provider, model, "unusable", redact(str(e) or type(e).__name__))
        await health.persist_failure(failure)
        return {"ok": False, "error": redact(failure.message)}
    health.mark_success(target)
    await health.persist_success(target)
    return {"ok": True}
