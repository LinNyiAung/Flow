"""The AI feature catalogue: keys, allowed providers, built-in defaults and default models."""
import os
from collections.abc import Mapping
from dataclasses import dataclass

from ai_usage_models import AIFeatureType

from .types import Target

PROVIDERS = ("openai", "gemini", "claude")

# Environment variable that names each provider's default model, and the fallback when it is unset.
_MODEL_ENV = {"openai": "OPENAI_MODEL", "gemini": "GEMINI_MODEL", "claude": "CLAUDE_MODEL"}
_MODEL_FALLBACK = {"openai": "gpt-4o-mini", "gemini": "gemini-2.5-flash", "claude": "claude-sonnet-5-5"}


@dataclass(frozen=True)
class FeatureSpec:
    key: str
    label: str
    allowed: tuple[str, ...]
    default: Target
    usage_type: AIFeatureType


_ALL = PROVIDERS
_NO_CLAUDE = ("openai", "gemini")


def _spec(key, label, allowed, provider, model, usage_type):
    return FeatureSpec(key, label, allowed, Target(provider, model), usage_type)


FEATURES: dict[str, FeatureSpec] = {s.key: s for s in (
    _spec("chat", "AI chat", _ALL, "gemini", "gemini-2.5-flash", AIFeatureType.CHAT),
    # Pro's Advanced chat: the same chatbot (persona, prompt, max tokens) on its own chain. Its usage rows are chat rows.
    _spec("chat_advanced", "Advanced chat", _ALL, "claude", "claude-sonnet-5-5", AIFeatureType.CHAT),
    _spec("insight_weekly", "Weekly insight", _ALL, "gemini", "gemini-2.5-flash", AIFeatureType.WEEKLY_INSIGHT),
    _spec("insight_monthly", "Monthly insight", _ALL, "gemini", "gemini-2.5-flash", AIFeatureType.MONTHLY_INSIGHT),
    _spec("insight_translation", "Insight translation", _ALL, "gemini", "gemini-2.5-pro", AIFeatureType.TRANSLATION),
    # Pro's custom insight: a report the user asks for over a date range and an instruction. Claude by default.
    _spec("insight_custom", "Custom insight", _ALL, "claude", "claude-sonnet-5-5", AIFeatureType.CUSTOM_INSIGHT),
    _spec("budget_suggestion", "Budget suggestion", _ALL, "openai", "gpt-4o-mini", AIFeatureType.BUDGET_SUGGESTION),
    _spec("budget_auto_create", "Budget auto-create", _ALL, "openai", "gpt-4o-mini", AIFeatureType.BUDGET_AUTO_CREATE),
    _spec("transaction_text", "Transaction from text", _ALL, "openai", "gpt-4o-mini",
          AIFeatureType.TRANSACTION_TEXT_EXTRACTION),
    _spec("transaction_image", "Transaction from receipt photo", _ALL, "openai", "gpt-4o",
          AIFeatureType.TRANSACTION_IMAGE_EXTRACTION),
    _spec("transaction_audio", "Voice input (speech to text)", _NO_CLAUDE, "openai", "whisper-1",
          AIFeatureType.TRANSACTION_AUDIO_TRANSCRIPTION),
)}

# The models the admin page offers per provider (it also allows "Other..."). OpenAI's speech-to-text models are
# offered only for voice input: see known_models().
KNOWN_MODELS: dict[str, list[str]] = {
    "openai": ["gpt-4o-mini", "gpt-4o"],
    "gemini": ["gemini-2.5-flash", "gemini-2.5-pro"],
    "claude": ["claude-sonnet-5-5", "claude-haiku-5-5", "claude-opus-5-5"],
}
AUDIO_FEATURE = "transaction_audio"
OPENAI_AUDIO_MODELS: list[str] = ["whisper-1"]


def known_models(feature: str) -> dict[str, list[str]]:
    """The models offered for `feature`, per allowed provider (fresh lists). Voice input on OpenAI offers only the
    speech-to-text models; no other feature offers them."""
    def models(provider: str) -> list[str]:
        if feature == AUDIO_FEATURE and provider == "openai":
            return list(OPENAI_AUDIO_MODELS)
        return list(KNOWN_MODELS[provider])
    return {p: models(p) for p in FEATURES[feature].allowed}


def is_openai_audio_model(model: str) -> bool:
    """True for OpenAI speech-to-text models: whisper* or *transcribe* (case-insensitive)."""
    name = (model or "").strip().lower()
    return name.startswith("whisper") or "transcribe" in name

# Claude "effort" level sent per feature (Claude only).
CLAUDE_EFFORT: dict[str, str] = {
    "chat": "low",
    "chat_advanced": "low",
    "transaction_text": "low",
    "transaction_image": "low",
    "budget_suggestion": "low",
    "budget_auto_create": "low",
    "insight_weekly": "medium",
    "insight_monthly": "medium",
    "insight_translation": "medium",
    "insight_custom": "medium",
}


# Features whose built-in main model follows GEMINI_MODEL / OPENAI_MODEL, as the code did before
# provider switching. The other features have hard-coded built-in models.
_ENV_MODEL_FEATURES = frozenset({"chat", "insight_weekly", "insight_monthly"})

# The environment variables the settings layer reads besides AI_<FEATURE>_*.
MODEL_ENV_VARS = tuple(_MODEL_ENV.values())


def builtin_default(feature: str, environ: Mapping[str, str] | None = None) -> Target:
    """The built-in main target for `feature` (used when neither the panel nor the environment sets one)."""
    spec = FEATURES[feature]
    if feature in _ENV_MODEL_FEATURES:
        return Target(spec.default.provider, default_model(feature, spec.default.provider, environ))
    return spec.default


def default_model(feature: str, provider: str, environ: Mapping[str, str] | None = None) -> str:
    """The model used when `provider` is named for `feature` without a model.

    Per-provider defaults come from OPENAI_MODEL / GEMINI_MODEL / CLAUDE_MODEL (read from `environ`,
    default os.environ), with two fixed per-feature exceptions on OpenAI.
    """
    if provider == "openai":
        if feature == "transaction_image":
            return "gpt-4o"
        if feature == "transaction_audio":
            return "whisper-1"
    env = os.environ if environ is None else environ
    return (env.get(_MODEL_ENV[provider]) or "").strip() or _MODEL_FALLBACK[provider]
