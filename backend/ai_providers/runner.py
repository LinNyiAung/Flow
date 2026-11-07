"""Run one AI feature call through its chain of providers: fall back, cool off, track usage, record status.

run() makes one request (with a feature-specific `call`) and returns a RunResult. run_stream() streams text
chunks and ends with one RunResult; it can move to the next provider only until the first non-empty chunk
has been yielded, after which any error propagates to the caller.

Usage rows: one per billed answer: "used" for the answer returned, "rejected" for a billed answer that was unusable
(the next target was then tried), "cancelled" for a stream cut short after text went out. Attempts that failed with
an error (HTTP error, timeout) were not billed and record nothing.
"""
import asyncio
import contextvars
import logging
from collections.abc import AsyncIterator, Awaitable, Callable, Iterator
from contextlib import aclosing
from dataclasses import dataclass, replace
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
logger = logging.getLogger(__name__)

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


def _fallback_from(failures: list[ProviderFailure]) -> str | None:
    return failures[0].provider if failures else None


def _billed(c: Completion | None) -> bool:
    return c is not None and (c.input_tokens > 0 or c.output_tokens > 0 or c.audio_seconds is not None
                              or any(_billed(r) for r in c.requests))


def _rows(c: Completion, outcome: str) -> list[tuple[Completion, str]]:
    """The usage rows of an answer: one per provider request. An answer made of several requests (c.requests, e.g.
    the translation's cut-off retry) gives one row per request: when the answer is used, each request keeps its own
    outcome (a request whose text was not used is "rejected"); otherwise every request gets `outcome`."""
    if not c.requests:
        return [(c, outcome)]
    return [(r, (r.outcome or outcome) if outcome == "used" else outcome) for r in c.requests if _billed(r)]


async def _track(feature: str, user_id: str | None, t: Target, c: Completion, fallback_from: str | None,
                 outcome: str) -> None:
    """The usage rows for this answer (nothing without a user)."""
    if not user_id:
        return
    for r, row_outcome in _rows(c, outcome):
        await track_ai_usage(user_id, FEATURES[feature].usage_type, AIProviderType(t.provider), t.model,
                             r.input_tokens, r.output_tokens, r.input_tokens + r.output_tokens,
                             fallback_from=fallback_from, audio_seconds=r.audio_seconds,
                             audio_input_tokens=r.audio_input_tokens, cached_input_tokens=r.cached_input_tokens,
                             cache_write_tokens=r.cache_write_tokens, served_model=r.served_model,
                             cost_estimated=r.estimated, outcome=row_outcome)


# Usage writes run as tasks so a cancelled request still completes them (the caller awaits them shielded, or, on the
# GeneratorExit / CancelledError path, not at all). The set keeps a strong reference until each task is done (the
# event loop keeps only weak ones).
_usage_writes: set[asyncio.Task] = set()


def pending_usage_writes() -> list[asyncio.Task]:
    """The usage writes still running (tests await them)."""
    return list(_usage_writes)


def _spawn_write(coro) -> asyncio.Task:
    """Run a usage write as its own task, in a fresh context: it uses its own connection, never the caller's
    transaction() (which may be gone by the time a cancelled caller's write runs)."""
    task = asyncio.get_running_loop().create_task(coro, context=contextvars.Context())
    _usage_writes.add(task)
    task.add_done_callback(_usage_writes.discard)
    return task


async def _record(feature: str, user_id: str | None, t: Target, c: Completion, fallback_from: str | None,
                  outcome: str) -> None:
    """Write the usage rows of this answer. If the caller is cancelled meanwhile the write still completes (shielded
    task), so a billed answer is recorded exactly once."""
    if user_id:
        await asyncio.shield(_spawn_write(_track(feature, user_id, t, c, fallback_from, outcome)))


async def _rejected(feature: str, user_id: str | None, t: Target, c: Completion | None,
                    failures: list[ProviderFailure]) -> None:
    """An answer that was billed but not used (refused, filtered, empty, unparseable): record what it cost, with
    the fallback_from of that attempt. No row when the answer carries no usage. Health is not touched."""
    if _billed(c):
        await _record(feature, user_id, t, c, _fallback_from(failures), "rejected")


def _billed_before_error(e: BaseException) -> Completion | None:
    """What a `call` was billed for before it failed with this error (it sets `billed_usage`; see errors.py)."""
    c = getattr(e, "billed_usage", None)
    return c if isinstance(c, Completion) else None


def _record_cut_short(feature: str, user_id: str | None, t: Target, prompt: Prompt, parts: list[str],
                      final: Completion | None, failures: list[ProviderFailure]) -> None:
    """A stream that yielded text and then ended early (closed by its consumer, cancelled, or a provider error):
    the provider billed it, so schedule one usage row (outcome "cancelled"). Tokens are the provider's when it
    already reported them, else estimated: the prompt's characters // 4 in, the characters yielded // 4 out.
    Never awaits: this runs on the GeneratorExit / CancelledError path."""
    if not user_id:
        return
    text = "".join(parts)
    if _billed(final) and not final.estimated:
        c = final
    else:
        c = Completion(text, (len(prompt.system) + len(prompt.user)) // 4, len(text) // 4, "stop",
                       served_model=final.served_model if final else None, estimated=True)
    try:
        _spawn_write(_track(feature, user_id, t, c, _fallback_from(failures), "cancelled"))
    except RuntimeError:  # no running loop (a generator finalised after the loop closed)
        logger.warning(f"Could not record the usage of a stream cut short ({t.provider}/{t.model})")


async def _succeeded(feature: str, user_id: str | None, t: Target, c: Completion,
                     failures: list[ProviderFailure]) -> str | None:
    """Clear the target's cool-off, record the usage and the success; returns fallback_from. The usage is written
    first and shielded: a request cancelled from here on (a client that leaves as the answer completes) still
    records it, once."""
    health.mark_success(t)
    fallback_from = _fallback_from(failures)
    await _record(feature, user_id, t, c, fallback_from, "used")
    await health.persist_success(t)
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
            c = None
            try:
                c = await call(client, t)
                _check_answer(c, allow_empty)
                value = parse(c)  # may raise UnusableAnswer
            except UnusableAnswer as e:
                # billed even though unusable: the answer itself, or what a `call` passed with its UnusableAnswer
                await _rejected(feature, user_id, t, c if c is not None else e.completion, failures)
                failures.append(_unusable(t, e))
                break
            except Exception as e:
                # requests a `call` was billed for before this error (e.g. translation chunks): record them
                await _rejected(feature, user_id, t, _billed_before_error(e), failures)
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
    the first chunk counts as unusable and moves on (its usage is recorded as "rejected").
    A stream that ends early after text went out (closed by the consumer, cancelled, or a provider error)
    still records one usage row ("cancelled"; see _record_cut_short).
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
                _record_cut_short(feature, user_id, t, prompt, parts, final, failures)
                raise  # never stitch text from two providers together
            await _rejected(feature, user_id, t, final, failures)
            failures.append(_unusable(t, e))
            continue
        except Exception as e:
            f = classify(e, t.provider, t.model)
            if parts:
                _record_cut_short(feature, user_id, t, prompt, parts, final, failures)
                # Too late to switch providers, but a provider failure still counts towards cool-off and status.
                if f is not None:
                    await _record_failure(f)
                raise
            if f is None:
                raise
            await _record_failure(f)
            failures.append(f)
            continue
        except BaseException:
            # The consumer closed the stream (GeneratorExit) or the request was cancelled (CancelledError) after
            # text went out: still record what the provider billed. Nothing yielded: nothing to record.
            if parts:
                _record_cut_short(feature, user_id, t, prompt, parts, final, failures)
            raise
        text = "".join(parts)
        final = final or Completion("", 0, 0, "stop")
        c = replace(final, text=text)
        fallback_from = await _succeeded(feature, user_id, t, c, failures)
        yield RunResult(text, t, fallback_from, c)
        return
    raise AllProvidersFailed(failures)
