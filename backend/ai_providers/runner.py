"""Run one AI feature call through its chain of providers: fall back, cool off, track usage, record status.

run() makes one request (with a feature-specific `call`) and returns a RunResult. run_stream() streams text
chunks and ends with one RunResult; it can move to the next provider only until the first non-empty chunk
has been yielded, after which any error propagates to the caller.
"""
import asyncio
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import aclosing
from dataclasses import dataclass
from typing import Generic, TypeVar

from ai_usage_models import AIProviderType
from ai_usage_service import track_ai_usage

from . import health
from .clients.base import ProviderClient, get_client
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


def _targets(feature: str) -> list[Target]:
    """The feature's chain without cooling targets; if every target is cooling, the whole chain in order."""
    targets = chain(feature, configured=_configured)
    return [t for t in targets if health.is_available(t)] or targets


def _effort(feature: str, t: Target) -> str | None:
    return CLAUDE_EFFORT.get(feature) if t.provider == "claude" else None


def default_call(prompt: Prompt, feature: str) -> Callable[[ProviderClient, Target], Awaitable[Completion]]:
    """A `call` for run() that sends `prompt` with client.complete (plus the feature's effort on Claude)."""
    async def call(client: ProviderClient, t: Target) -> Completion:
        return await client.complete(t.model, prompt, effort=_effort(feature, t))
    return call


def _not_configured(t: Target) -> ProviderFailure:
    return ProviderFailure(t.provider, t.model, "not_configured", "no API key")


def _unusable(t: Target, e: UnusableAnswer) -> ProviderFailure:
    reason = str(e)
    return ProviderFailure(t.provider, t.model, "refusal" if reason == "refusal" else "unusable",
                           redact(reason or "unusable answer"))


def _check_answer(c: Completion) -> None:
    """Raise UnusableAnswer for a refusal, a filtered answer or an empty one."""
    if c.finish == "refusal":
        raise UnusableAnswer("refusal")
    if c.finish == "filtered" or not (c.text or "").strip():
        raise UnusableAnswer("filtered" if c.finish == "filtered" else "empty")


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
              background: bool = False) -> RunResult[T]:
    """Try each target of the feature's chain until one gives a usable answer.

    Provider failures (see errors.classify) cool the target off and move on; an UnusableAnswer (refusal,
    empty, filtered, or raised by `parse`) moves on without a cool-off; any other error is about the request
    itself and propagates at once. With background=True a rate-limited target is retried twice (5 s, 10 s)
    before moving on. Raises AllProvidersFailed when every target failed.
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
                _check_answer(c)
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
            failures.append(_unusable(t, e))
            continue
        except Exception as e:
            if parts:
                raise  # something was already yielded: too late to switch providers
            f = classify(e, t.provider, t.model)
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
