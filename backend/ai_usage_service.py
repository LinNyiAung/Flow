from datetime import datetime, UTC
import logging
import re
import uuid

from sql import ai_usage as ai_usage_db
from ai_usage_models import AIFeatureType, AIProviderType

logger = logging.getLogger(__name__)

# List prices in USD per 1M tokens, checked 2026-11-07 against the official pages:
#   Gemini: https://ai.google.dev/gemini-api/docs/pricing
#   OpenAI: https://openai.com/api/pricing
#   Claude: Anthropic's pricing page (https://www.anthropic.com/pricing)
#
# PRICING[provider][model] is a dict with:
#   "input" / "output"    USD per 1M input / output tokens (Gemini output includes thinking tokens);
#   "cached_input"        optional: per 1M input tokens served from the provider's prompt cache (Claude: cache reads);
#   "cache_write"         optional: per 1M Claude cache creation tokens (the 5-minute TTL rate);
#   "audio_input"         optional: per 1M audio input tokens (Gemini transcription);
#   "cached_audio_input"  optional: per 1M cached audio input tokens;
#   "per_minute"          optional: USD per minute of audio (OpenAI speech-to-text, billed by duration, not tokens);
#   "long_context"        optional: {"above": N, prices...}: these prices apply when the request's input tokens are
#                         more than N (decided per request, by the prompt size);
#   "schedule"            optional: [(effective_from_utc, {prices}), ...] in date order; the latest entry whose start
#                         is at or before the call time overrides the base prices.
# A missing optional price falls back to "input" ("cached_audio_input" to "cached_input"). Model names are lower case;
# see resolve_model() for how a reported name is matched. Edit the numbers here when prices change, then run
# `python -m scripts.recalculate_ai_costs` (see docs/postgres-migration-plan.md) to reprice stored rows.
PRICING = {
    "openai": {
        "gpt-4o-mini": {"input": 0.15, "output": 0.60, "cached_input": 0.075},
        "gpt-4o": {"input": 2.50, "output": 10.00, "cached_input": 1.25},
        # speech-to-text, per minute of audio
        "whisper-1": {"per_minute": 0.006},
        "gpt-4o-transcribe": {"per_minute": 0.006},
        "gpt-4o-mini-transcribe": {"per_minute": 0.003},
    },
    "gemini": {
        "gemini-2.5-flash": {"input": 0.30, "output": 2.50, "cached_input": 0.03,
                             "audio_input": 1.00, "cached_audio_input": 0.10},
        "gemini-2.5-flash-lite": {"input": 0.10, "output": 0.40, "cached_input": 0.01,
                                  "audio_input": 0.30, "cached_audio_input": 0.03},
        "gemini-2.5-pro": {"input": 1.25, "output": 10.00, "cached_input": 0.125,
                           "long_context": {"above": 200_000, "input": 2.50, "output": 15.00, "cached_input": 0.25}},
        "gemini-3.5-flash-lite": {"input": 0.30, "output": 2.50, "cached_input": 0.03, "audio_input": 0.30},
        # Audio input costs the same as text input (no "audio_input" key).
        "gemini-3.8-flash": {"input": 0.75, "output": 3.75, "cached_input": 0.075,
                             "schedule": [(datetime(2027, 1, 1, tzinfo=UTC),
                                           {"input": 1.50, "output": 7.50, "cached_input": 0.15})]},
    },
    "claude": {
        # cache reads 0.1x input (Opus 5.5: 0.05x), 5-minute cache writes 1.25x input
        "claude-sonnet-5-5": {"input": 2.00, "output": 10.00, "cached_input": 0.20, "cache_write": 2.50},
        "claude-haiku-5-5": {"input": 0.10, "output": 0.50, "cached_input": 0.01, "cache_write": 0.125,
                             "long_context": {"above": 100_000, "input": 0.50, "output": 2.50,
                                              "cached_input": 0.05, "cache_write": 0.625}},
        "claude-opus-5-5": {"input": 4.00, "output": 20.00, "cached_input": 0.20, "cache_write": 5.00},
    },
}

# Speech-to-text priced per minute when the audio length is unknown: estimate it from the transcript. The token
# count is the transcript's characters // 4 (see the OpenAI client), about 5.5 characters per word, spoken at
# about 150 words per minute (2.5 words per second).
CHARS_PER_TOKEN = 4
CHARS_PER_WORD = 5.5
WORDS_PER_SECOND = 2.5

# A trailing snapshot or version suffix that names the same priced model: -2024-07-18, -20261001, -latest, -001.
_SUFFIX = re.compile(r"(-\d{4}-\d{2}-\d{2}|-\d{8}|-latest|-\d{3})$")

_warned_unknown: set[tuple[str, str]] = set()  # (provider, model) pairs already warned about in this process


def _utc(at: datetime | None) -> datetime:
    if at is None:
        return datetime.now(UTC)
    return at.replace(tzinfo=UTC) if at.tzinfo is None else at


def resolve_model(provider: str, model: str | None) -> str | None:
    """The PRICING key for `model` of `provider`, or None. Exact (trimmed, lower-case) name first; then without a
    `models/` prefix; then without trailing snapshot suffixes. Only whole suffixes are stripped, so
    gemini-2.5-flash-lite never becomes gemini-2.5-flash."""
    models = PRICING.get((provider or "").strip().lower(), {})
    name = (model or "").strip().lower()
    if not name:
        return None
    if name in models:
        return name
    if name.startswith("models/"):
        name = name[len("models/"):]
        if name in models:
            return name
    while True:
        stripped = _SUFFIX.sub("", name)
        if stripped == name:
            return None
        name = stripped
        if name in models:
            return name


def _prices_at(entry: dict, at: datetime) -> dict:
    """The entry's prices in effect at `at` (its base prices overridden by the latest started schedule step)."""
    prices = {k: v for k, v in entry.items() if k != "schedule"}
    for start, step in entry.get("schedule", ()):
        if start <= at:
            prices.update(step)
    return prices


def estimated_audio_seconds(output_tokens: int) -> float:
    """Seconds of speech in a transcript of `output_tokens` estimated tokens (characters // 4)."""
    words = output_tokens * CHARS_PER_TOKEN / CHARS_PER_WORD
    return words / WORDS_PER_SECOND


def _fallback_prices(provider: str, model: str, served_model: str | None, at: datetime) -> dict | None:
    """Prices for a model missing from PRICING: the provider's highest current prices (never $0)."""
    entries = [_prices_at(e, at) for e in PRICING.get(provider, {}).values()]
    if not entries:
        return None
    from ai_providers.features import is_openai_audio_model  # lazy: ai_providers imports this module

    per_minute = [e["per_minute"] for e in entries if "per_minute" in e]
    audio_name = is_openai_audio_model(model) or is_openai_audio_model(served_model or "")
    if provider == "openai" and audio_name and per_minute:
        return {"per_minute": max(per_minute)}
    text = [e for e in entries if "input" in e and "output" in e]
    if not text:
        return {"per_minute": max(per_minute)} if per_minute else None

    def top(key, default="input"):
        return max(e.get(key, e[default]) for e in text)
    return {"input": top("input"), "output": top("output"), "cached_input": top("cached_input"),
            "cache_write": top("cache_write"), "audio_input": top("audio_input"),
            "cached_audio_input": max(e.get("cached_audio_input", e.get("cached_input", e["input"])) for e in text)}


def calculate_cost(provider: str, model: str, input_tokens: int, output_tokens: int, *,
                   audio_seconds: float | None = None, audio_input: bool = False, audio_input_tokens: int = 0,
                   cached_input_tokens: int = 0, cache_write_tokens: int = 0, served_model: str | None = None,
                   at: datetime | None = None) -> float:
    """Estimated cost in USD of one call, at the list prices in effect at `at` (default: now, UTC).

    input_tokens is the whole input; cached_input_tokens, cache_write_tokens and audio_input_tokens are parts of it,
    each priced at its own rate (audio_input=True: all input tokens are audio). Cached tokens are counted against
    the text input first, then the audio. The price is the served model's when PRICING knows it, else the requested
    model's; a model missing from PRICING is priced at its provider's highest prices (warned once per process); an
    unknown provider costs 0. Per-minute (speech-to-text) models are priced from `audio_seconds`, or, when that is
    unknown, from seconds estimated from `output_tokens` (estimated_audio_seconds).
    """
    try:
        provider_key = (provider or "").strip().lower()
        when = _utc(at)
        key = resolve_model(provider_key, served_model) or resolve_model(provider_key, model)
        if key is not None:
            prices = _prices_at(PRICING[provider_key][key], when)
        else:
            model_key = (model or "").strip().lower()
            prices = _fallback_prices(provider_key, model_key, served_model, when)
            if (provider_key, model_key) not in _warned_unknown:
                _warned_unknown.add((provider_key, model_key))
                if prices is None:
                    logger.warning(f"Pricing not found for provider {provider}/{model}, using $0")
                else:
                    logger.warning(f"Pricing not found for {provider}/{model}; using the provider's highest prices")
            if prices is None:
                return 0.0

        input_tokens = max(int(input_tokens or 0), 0)
        output_tokens = max(int(output_tokens or 0), 0)
        if "per_minute" in prices:
            seconds = audio_seconds if audio_seconds is not None else estimated_audio_seconds(output_tokens)
            return round(max(float(seconds), 0.0) / 60 * prices["per_minute"], 6)

        long_context = prices.pop("long_context", None)
        if long_context and input_tokens > long_context["above"]:
            prices.update({k: v for k, v in long_context.items() if k != "above"})
        price_in = prices["input"]
        price_cached = prices.get("cached_input", price_in)
        price_audio = prices.get("audio_input", price_in)
        price_cached_audio = prices.get("cached_audio_input", price_cached)
        price_write = prices.get("cache_write", price_in)

        audio = input_tokens if audio_input else min(max(int(audio_input_tokens or 0), 0), input_tokens)
        text = input_tokens - audio
        cached = max(int(cached_input_tokens or 0), 0)
        cached_text = min(cached, text)
        cached_audio = min(cached - cached_text, audio)
        write = min(max(int(cache_write_tokens or 0), 0), text - cached_text)
        fresh_text = text - cached_text - write
        fresh_audio = audio - cached_audio

        cost = (fresh_text * price_in + cached_text * price_cached + write * price_write
                + fresh_audio * price_audio + cached_audio * price_cached_audio
                + output_tokens * prices["output"]) / 1_000_000
        return round(cost, 6)  # 6 decimal places for precision

    except Exception as e:
        logger.error(f"Error calculating cost: {e}")
        return 0.0


OUTCOMES = ("used", "rejected", "cancelled")


async def track_ai_usage(
    user_id: str,
    feature_type: AIFeatureType,
    provider: AIProviderType,
    model_name: str,
    input_tokens: int,
    output_tokens: int,
    total_tokens: int,
    fallback_from: str | None = None,
    *,
    audio_seconds: float | None = None,
    audio_input: bool = False,
    audio_input_tokens: int = 0,
    cached_input_tokens: int = 0,
    cache_write_tokens: int = 0,
    served_model: str | None = None,
    cost_estimated: bool = False,
    outcome: str = "used",
):
    """Track AI API usage and cost. `fallback_from` names the provider that failed before this one answered.

    The keyword-only details (see calculate_cost) are stored with the row so a later price change can be re-applied
    exactly (scripts/recalculate_ai_costs.py). `outcome`: "used" (the answer the user got), "rejected" (billed, but
    refused/empty/unparseable, so the next provider was asked) or "cancelled" (a stream that ended early after text
    started). `cost_estimated`: the tokens or the duration were estimated rather than reported by the provider.
    """
    try:
        # SDK usage fields can be None; normalize so cost math/logging never fails
        input_tokens = int(input_tokens or 0)
        output_tokens = int(output_tokens or 0)
        total_tokens = int(total_tokens or 0) or (input_tokens + output_tokens)
        audio_input_tokens = input_tokens if audio_input else int(audio_input_tokens or 0)
        cached_input_tokens = int(cached_input_tokens or 0)
        cache_write_tokens = int(cache_write_tokens or 0)
        created_at = datetime.now(UTC)

        # Calculate cost
        estimated_cost = calculate_cost(
            provider.value,
            model_name,
            input_tokens,
            output_tokens,
            audio_seconds=audio_seconds,
            audio_input_tokens=audio_input_tokens,
            cached_input_tokens=cached_input_tokens,
            cache_write_tokens=cache_write_tokens,
            served_model=served_model,
            at=created_at,
        )

        # Create usage record
        usage_record = {
            "_id": str(uuid.uuid4()),
            "user_id": user_id,
            "feature_type": feature_type.value,
            "provider": provider.value,
            "model_name": model_name,
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "total_tokens": total_tokens,
            "estimated_cost_usd": estimated_cost,
            "created_at": created_at,
            "fallback_from": fallback_from,
            "served_model": served_model or None,
            "cached_input_tokens": cached_input_tokens,
            "cache_write_tokens": cache_write_tokens,
            "audio_input_tokens": audio_input_tokens,
            "audio_seconds": float(audio_seconds) if audio_seconds is not None else None,
            "cost_estimated": bool(cost_estimated),
            "outcome": outcome if outcome in OUTCOMES else "used",
        }

        await ai_usage_db.insert_usage(usage_record)

        logger.info(
            f"💰 [AI USAGE TRACKED] User: {user_id} | "
            f"Feature: {feature_type.value} | Provider: {provider.value} | "
            f"Tokens: {total_tokens:,} | Cost: ${estimated_cost:.6f} | Outcome: {usage_record['outcome']}"
        )

        return usage_record

    except Exception as e:
        logger.error(f"Error tracking AI usage: {e}")
        return None
