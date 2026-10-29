"""Resolve a feature's provider setting: admin panel, then environment, then built-in default."""
import asyncio
import logging
import os
from collections.abc import Callable, Mapping

from sql import ai_settings as store

from .features import FEATURES, MODEL_ENV_VARS, PROVIDERS, builtin_default, default_model
from .types import FeatureSetting, Target

logger = logging.getLogger(__name__)

# Snapshot of the settings-relevant environment (AI_* and the *_MODEL defaults only, never API keys).
# Taken lazily on first use, so a .env loaded after this module is imported is still seen; a restart
# (or reload_env) is what picks up later changes.
_env: dict[str, str] | None = None
# Parsed environment unit per feature (None = unset or invalid), so a bad unit warns once per snapshot.
_env_units: dict[str, FeatureSetting | None] = {}
# Admin-panel layer: feature -> FeatureSetting. Filled by the panel layer (set_panel_cache).
_panel: dict[str, FeatureSetting] = {}


def reload_env(environ: Mapping[str, str] | None = None) -> None:
    """Refresh the environment snapshot (from os.environ unless an explicit mapping is given)."""
    global _env
    source = os.environ if environ is None else environ
    _env = {k: v for k, v in source.items() if k.startswith("AI_") or k in MODEL_ENV_VARS}
    _env_units.clear()


def _snapshot() -> dict[str, str]:
    if _env is None:
        reload_env()
    return _env  # type: ignore[return-value]


def _env_unit(feature: str) -> FeatureSetting | None:
    env = _snapshot()
    if feature not in _env_units:
        _env_units[feature] = parse_env(feature, env)
    return _env_units[feature]


def set_panel_cache(rows: dict[str, FeatureSetting]) -> None:
    """Replace the admin-panel layer. `resolve` consults it first."""
    global _panel
    _panel = dict(rows)


def validate(feature: str, s: FeatureSetting) -> list[str]:
    """Error messages for a setting; an empty list means it is valid."""
    spec = FEATURES.get(feature)
    if spec is None:
        return [f"Unknown feature '{feature}'"]
    errors: list[str] = []

    def check_target(role: str, t: Target) -> None:
        if t.provider not in PROVIDERS:
            errors.append(f"{role}: unknown provider '{t.provider}'")
        elif t.provider not in spec.allowed:
            errors.append(f"{role}: provider '{t.provider}' is not allowed for {feature}")
        if not (t.model or "").strip():
            errors.append(f"{role}: model is empty")

    check_target("main", s.main)
    seen: list[Target] = [s.main]
    for i, b in enumerate(s.backups or (), start=1):
        check_target(f"backup {i}", b)
        if b == s.main:
            errors.append(f"backup {i}: same as the main provider and model ({b.provider}:{b.model})")
        elif b in seen:
            errors.append(f"backup {i}: duplicate of an earlier backup ({b.provider}:{b.model})")
        seen.append(b)
    return errors


def _entry(feature: str, text: str, environ: Mapping[str, str]) -> Target:
    """Parse 'provider[:model]'."""
    provider, _, model = text.strip().partition(":")
    provider = provider.strip().lower()
    model = model.strip()
    if provider not in PROVIDERS:
        raise ValueError(f"unknown provider '{provider}'")
    return Target(provider, model or default_model(feature, provider, environ))


def parse_env(feature: str, environ: Mapping[str, str]) -> FeatureSetting | None:
    """The environment unit for a feature, or None if unset or invalid (invalid ones are logged)."""
    prefix = f"AI_{feature.upper()}_"
    provider_var, model_var, backups_var = prefix + "PROVIDER", prefix + "MODEL", prefix + "BACKUPS"
    provider = (environ.get(provider_var) or "").strip().lower()
    model = (environ.get(model_var) or "").strip()
    backups_raw = (environ.get(backups_var) or "").strip()
    if not provider:
        if model or backups_raw:
            logger.warning("Ignoring %s / %s: they need %s to be set too", model_var, backups_var, provider_var)
        return None
    try:
        main = _entry(feature, f"{provider}:{model}" if model else provider, environ)
        backups: tuple[Target, ...] | None
        if not backups_raw:
            backups = None
        elif backups_raw.lower() == "none":
            backups = ()
        else:
            backups = tuple(_entry(feature, part, environ) for part in backups_raw.split(",") if part.strip())
        setting = FeatureSetting(main, backups, "server")
    except ValueError as e:
        logger.warning("Ignoring the %s* environment setting: %s", prefix, e)
        return None
    errors = validate(feature, setting)
    if errors:
        logger.warning("Ignoring the %s* environment setting: %s", prefix, "; ".join(errors))
        return None
    return setting


def resolve(feature: str) -> FeatureSetting:
    """Panel setting, else environment unit, else the built-in default."""
    panel = _panel.get(feature)
    if panel is not None:
        return panel
    env = _env_unit(feature)
    if env is not None:
        return env
    return FeatureSetting(builtin_default(feature, _snapshot()), None, "default")


def default_backups(feature: str, main: Target, configured: Callable[[str], bool]) -> list[Target]:
    """What `backups: None` expands to for `main`: every other allowed, configured provider on its default model."""
    spec = FEATURES[feature]
    env = _snapshot()
    return [Target(p, default_model(feature, p, env)) for p in PROVIDERS
            if p in spec.allowed and p != main.provider and configured(p)]


def chain(feature: str, configured: Callable[[str], bool]) -> list[Target]:
    """The targets to try, in order: main, then explicit backups or the default backups."""
    s = resolve(feature)
    if s.backups is not None:
        return [s.main, *s.backups]
    return [s.main, *default_backups(feature, s.main, configured)]


# ---- admin-panel layer: database rows <-> the in-memory cache that resolve() reads ----

def _row_to_setting(row: Mapping) -> FeatureSetting:
    """A stored row as a FeatureSetting (raises ValueError/KeyError/TypeError if it is malformed)."""
    raw = row["backups"]
    backups: tuple[Target, ...] | None
    if raw is None:
        backups = None
    elif isinstance(raw, list):
        backups = tuple(Target(str(b["provider"]), str(b["model"])) for b in raw)
    else:
        raise ValueError("backups is not a list")
    return FeatureSetting(Target(row["main_provider"], row["main_model"]), backups, "panel")


def panel_setting(feature: str) -> FeatureSetting | None:
    """The admin-panel setting for a feature, or None when it has none (resolution then falls to env / built-in)."""
    return _panel.get(feature)


# Bumped by every save_panel / clear_panel, before the write and after the cache changes. A load_panel whose read
# overlapped a write may hold a stale snapshot, so it compares the counter and drops its result if it moved.
_write_gen = 0


async def load_panel() -> None:
    """Read every stored setting into the cache. A row that is malformed or fails validation is logged and skipped.

    If a save_panel / clear_panel happened while the rows were being read, the snapshot may predate it, so it is
    discarded (the cache already holds the newer value; the next refresh reads a consistent state).
    """
    gen = _write_gen
    stored = await store.list_feature_settings()
    rows: dict[str, FeatureSetting] = {}
    for row in stored:
        feature = row.get("feature")
        try:
            setting = _row_to_setting(row)
        except (ValueError, KeyError, TypeError) as e:
            logger.warning("Ignoring the stored AI setting for %r: %s", feature, e)
            continue
        errors = validate(feature, setting)
        if errors:
            logger.warning("Ignoring the stored AI setting for %r: %s", feature, "; ".join(errors))
            continue
        rows[feature] = setting
    if _write_gen != gen:
        logger.debug("Discarding a stale AI settings snapshot: a setting was written while it was being read")
        return
    set_panel_cache(rows)


async def save_panel(feature: str, s: FeatureSetting, admin_email: str) -> None:
    """Validate, store and cache an admin-panel setting. Raises ValueError(list_of_errors) if it is invalid."""
    global _write_gen
    errors = validate(feature, s)
    if errors:
        raise ValueError(errors)
    backups = None if s.backups is None else [{"provider": b.provider, "model": b.model} for b in s.backups]
    _write_gen += 1
    await store.upsert_feature_setting(feature, s.main.provider, s.main.model, backups, admin_email)
    set_panel_cache({**_panel, feature: FeatureSetting(s.main, s.backups, "panel")})
    _write_gen += 1


async def clear_panel(feature: str) -> bool:
    """Remove a feature's panel setting; it then falls back to the environment, then the built-in default.

    Returns True if a stored row was removed.
    """
    global _write_gen
    _write_gen += 1
    removed = await store.delete_feature_setting(feature)
    set_panel_cache({k: v for k, v in _panel.items() if k != feature})
    _write_gen += 1
    return bool(removed)


_refresh_task: asyncio.Task | None = None


async def _refresh_forever(interval: float) -> None:
    while True:
        await asyncio.sleep(interval)
        try:
            await load_panel()
        except Exception:  # noqa: BLE001 - keep the last good cache and try again next round
            logger.exception("Could not refresh the AI settings from the database")


def start_refresh_loop(interval: float = 60.0) -> asyncio.Task:
    """Reload the panel cache every `interval` seconds on the running event loop (call once from app startup).

    Never started at import. Calling it again while the task is alive returns the same task.
    """
    global _refresh_task
    loop = asyncio.get_running_loop()
    if _refresh_task is not None and not _refresh_task.done() and _refresh_task.get_loop() is loop:
        return _refresh_task
    _refresh_task = loop.create_task(_refresh_forever(interval), name="ai-settings-refresh")
    return _refresh_task


def setting_warnings(s: FeatureSetting, configured: Callable[[str], bool]) -> list[str]:
    """Warnings for a setting: one if its main provider has no API key configured."""
    if configured(s.main.provider):
        return []
    return [f"The main provider '{s.main.provider}' is not configured (no API key); "
            "requests will skip it and use the backups."]
