"""Run one AI feature call through its chain of providers: fall back, cool off, track usage, record status.

run() makes one request (with a feature-specific `call`) and returns a RunResult. run_stream() streams text
chunks and ends with one RunResult; it can move to the next provider only until the first non-empty chunk
has been yielded, after which any error propagates to the caller.
"""
import asyncio
from collections.abc import AsyncIterator, Awaitable, Callable, Iterator
from contextlib import aclosing
from dataclasses import dataclass
from typing import Generic, TypeVar

from ai_usage_models import AIProviderType
from ai_usage_service import track_ai_usage

from . import health
from .clients.base import ProviderClient, get_client, request_timeout
from .errors import AllProvidersFailed, ProviderFailure, UnusableAnswer, classify, redact
from .features import CLAUDE_EFFORT, FEATURES
from .settings import chain
from .types import Completion, Prompt, Target

T = TypeVar("T")

BACKGROUND_ATTEMPTS = 3       # background jobs retry a rate-limited target before moving on
BACKGROUND_BACKOFF = 5        # seconds; doubled each retry (5, 10)


@dataclass
class RunResult(Generic[T]):
    value: T
    target: Target
    fallback_from: str | None   # the first provider that failed before this one answered
    completion: Completion


def _configured(provider: str) -> bool:
    return get_client(provider).configured()


def _targets(feature: str) -> Iterator[Target]:
    """The feature's chain without cooling targets; if every target is cooling, the whole chain in order.

    A target whose provider has no API key never counts as available: otherwise an unconfigured main would be
    the only "available" target and a cooling backup would be skipped instead of tried. Unconfigured targets are
    still yielded in their place, so the caller records them as not_configured (and as fallback_from).
    Availability is checked again as each target comes up (R11): a provider-wide failure earlier in this
    request (billing, auth...) skips the later targets of that provider. Not when everything was cooling.
    """
    targets = chain(feature, configured=_configured)
    available = [t for t in targets if _configured(t.provider) and health.is_available(t)]
    if not available:
        yield from targets
        return
    for t in targets:
        if not _configured(t.provider) or health.is_available(t):
            yield t


def _effort(feature: str, t: Target) -> str | None:
    return CLAUDE_EFFORT.get(feature) if t.provider == "claude" else None


def default_call(prompt: Prompt, feature: str) -> Callable[[ProviderClient, Target], Awaitable[Completion]]:
    """A `call` for run() that sends `prompt` with client.complete (plus the feature's effort on Claude, and the
    feature's per-request timeout: 300 s for the insight jobs, 60 s otherwise)."""
    async def call(client: ProviderClient, t: Target) -> Completion:
        return await client.complete(t.model, prompt, effort=_effort(feature, t), timeout=request_timeout(feature))
    return call


def _not_configured(t: Target) -> ProviderFailure:
    return ProviderFailure(t.provider, t.model, "not_configured", "no API key")


def _unusable(t: Target, e: UnusableAnswer) -> ProviderFailure:
    reason = str(e)
    return ProviderFailure(t.provider, t.model, "refusal" if reason == "refusal" else "unusable",
                           redact(reason or "unusable answer"))


def _check_answer(c: Completion, allow_empty: bool = False) -> None:
    """Raise UnusableAnswer for a refusal, a filtered answer or an empty one (an empty "stop" answer is fine with allow_empty)."""
    if c.finish == "refusal":
        raise UnusableAnswer("refusal")
    if c.finish == "filtered":
        raise UnusableAnswer("filtered")
    if not (c.text or "").strip() and not (allow_empty and c.finish == "stop"):
        raise UnusableAnswer("empty")


async def _record_failure(f: ProviderFailure) -> None:
    health.mark_failure(f)
    await health.persist_failure(f)


async def _succeeded(feature: str, user_id: str | None, t: Target, c: Completion,
                     failures: list[ProviderFailure]) -> str | None:
    """Clear the target's cool-off, record the success and the usage; returns fallback_from."""
    health.mark_success(t)
    await health.persist_success(t)
    fallback_from = failures[0].provider if failures else None
    if user_id:
        await track_ai_usage(user_id, FEATURES[feature].usage_type, AIProviderType(t.provider), t.model,
                             c.input_tokens, c.output_tokens, c.input_tokens + c.output_tokens,
                             fallback_from=fallback_from)
    return fallback_from


async def run(feature: str, *, user_id: str | None,
              call: Callable[[ProviderClient, Target], Awaitable[Completion]],
              parse: Callable[[Completion], T] = lambda c: c,
              background: bool = False, allow_empty: bool = False) -> RunResult[T]:
    """Try each target of the feature's chain until one gives a usable answer.

    Provider failures (see errors.classify) cool the target off and move on; an UnusableAnswer (refusal,
    empty, filtered, or raised by `parse`) moves on without a cool-off; any other error is about the request
    itself and propagates at once. With background=True a rate-limited target is retried twice (5 s, 10 s)
    before moving on. With allow_empty=True an empty answer that finished normally is a valid answer (silence
    transcribes to ""); it is still tracked as usage. Raises AllProvidersFailed when every target failed.
    """
    failures: list[ProviderFailure] = []
    for t in _targets(feature):
        client = get_client(t.provider)
        if not client.configured():
            failures.append(_not_configured(t))
            continue
        attempts = BACKGROUND_ATTEMPTS if background else 1
        for attempt in range(attempts):
            try:
                c = await call(client, t)
                _check_answer(c, allow_empty)
                value = parse(c)  # may raise UnusableAnswer
            except UnusableAnswer as e:
                failures.append(_unusable(t, e))
                break
            except Exception as e:
                f = classify(e, t.provider, t.model)
                if f is None:
                    raise  # request-level: no fallback, no health change
                if background and f.kind == "rate_limit" and attempt < attempts - 1:
                    await asyncio.sleep(2 ** attempt * BACKGROUND_BACKOFF)
                    continue
                await _record_failure(f)
                failures.append(f)
                break
            else:
                fallback_from = await _succeeded(feature, user_id, t, c, failures)
                return RunResult(value, t, fallback_from, c)
    raise AllProvidersFailed(failures)


async def run_stream(feature: str, *, user_id: str | None, prompt: Prompt) -> AsyncIterator[str | RunResult[str]]:
    """Yield text chunks, then one RunResult whose value is the full text.

    Same chain and rules as run(), but the next target is tried only while nothing has been yielded:
    once the first non-empty chunk is out, any error propagates. A refusal or an empty answer before
    the first chunk counts as unusable and moves on.
    """
    failures: list[ProviderFailure] = []
    for t in _targets(feature):
        client = get_client(t.provider)
        if not client.configured():
            failures.append(_not_configured(t))
            continue
        parts: list[str] = []
        final: Completion | None = None
        try:
            async with aclosing(client.stream(t.model, prompt, effort=_effort(feature, t))) as items:
                async for item in items:
                    if isinstance(item, Completion):
                        final = item
                    elif item:
                        parts.append(item)
                        yield item
            if not parts:
                _check_answer(final or Completion("", 0, 0, "stop"))
        except UnusableAnswer as e:
            if parts:
                raise  # never stitch text from two providers together
            failures.append(_unusable(t, e))
            continue
        except Exception as e:
            f = classify(e, t.provider, t.model)
            if parts:
                # Too late to switch providers, but a provider failure still counts towards cool-off and status.
                if f is not None:
                    await _record_failure(f)
                raise
            if f is None:
                raise
            await _record_failure(f)
            failures.append(f)
            continue
        text = "".join(parts)
        final = final or Completion("", 0, 0, "stop")
        c = Completion(text, final.input_tokens, final.output_tokens, final.finish)
        fallback_from = await _succeeded(feature, user_id, t, c, failures)
        yield RunResult(text, t, fallback_from, c)
        return
    raise AllProvidersFailed(failures)
