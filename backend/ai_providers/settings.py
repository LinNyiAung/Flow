"""Resolve a feature's provider setting: admin panel, then environment, then built-in default."""
import logging
import os
from collections.abc import Callable, Mapping

from .features import FEATURES, PROVIDERS, default_model
from .types import FeatureSetting, Target

logger = logging.getLogger(__name__)

# Snapshot of the process environment, so a restart (or reload_env) is what picks up changes.
_env: dict[str, str] = dict(os.environ)
# Admin-panel layer: feature -> FeatureSetting. Filled by the panel layer (set_panel_cache).
_panel: dict[str, FeatureSetting] = {}


def reload_env(environ: Mapping[str, str] | None = None) -> None:
    """Refresh the environment snapshot (from os.environ unless an explicit mapping is given)."""
    global _env
    _env = dict(os.environ if environ is None else environ)


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
    env = parse_env(feature, _env)
    if env is not None:
        return env
    return FeatureSetting(FEATURES[feature].default, None, "default")


def chain(feature: str, configured: Callable[[str], bool]) -> list[Target]:
    """The targets to try, in order: main, then explicit backups or the default backups."""
    s = resolve(feature)
    if s.backups is not None:
        return [s.main, *s.backups]
    spec = FEATURES[feature]
    defaults = [Target(p, default_model(feature, p, _env)) for p in PROVIDERS
                if p in spec.allowed and p != s.main.provider and configured(p)]
    return [s.main, *defaults]
