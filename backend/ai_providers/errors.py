"""Failure classification for AI provider calls, plus key redaction.

classify() turns whatever an SDK raised into a ProviderFailure with one of KINDS, or None when the
error belongs to the request itself (a malformed prompt) so trying another provider would not help.
"""
import asyncio
import re
from dataclasses import dataclass
from typing import Callable, Optional

KINDS = ("auth", "billing", "rate_limit", "server", "timeout", "model_not_found", "not_configured", "refusal", "unusable")

# ---- patterns shared with insights_service (which keeps thin wrappers) ----

RATE_LIMIT_TEXT = re.compile(r"\b429\b|RESOURCE_EXHAUSTED|rate[ _-]?limit|too many requests|quota", re.IGNORECASE)

# Out of credit / billing problems. Providers report these with rate-limit-like codes
# (Gemini: 402 RESOURCE_EXHAUSTED "prepayment credits are depleted"; OpenAI: 429
# insufficient_quota; Anthropic: 400 "credit balance is too low"), but waiting a few
# minutes won't help: someone must top up.
BILLING_TEXT = re.compile(
    r"credits? (are |is )?depleted|insufficient[_ ]quota|billing|prepay|payment required|exceeded your current quota"
    r"|credit balance is too low",
    re.IGNORECASE,
)

_MODEL_NOT_FOUND_TEXT = re.compile(r"model\b.*\b(not found|does not exist)|\b(not found|does not exist)\b.*\bmodel", re.IGNORECASE | re.DOTALL)

# API keys a provider may echo back in an error message. Anything that looks like one is removed.
_KEY_PATTERNS = re.compile(
    r"sk-ant-[A-Za-z0-9_-]{6,}(?:\*+[A-Za-z0-9_-]*)?"
    r"|sk-[A-Za-z0-9_-]{6,}(?:\*+[A-Za-z0-9_-]*)?"
    r"|sk-[A-Za-z0-9_-]*\*{3,}[A-Za-z0-9_-]*"  # OpenAI's masked echo: sk-proj-****abcd
    r"|AIza[0-9A-Za-z_-]{10,}"
)
MAX_MESSAGE_LEN = 300


def redact(text: str) -> str:
    """Replace anything that looks like an API key with [redacted], then truncate to 300 characters."""
    return _KEY_PATTERNS.sub("[redacted]", text or "")[:MAX_MESSAGE_LEN]


@dataclass
class ProviderFailure:
    provider: str
    model: str
    kind: str
    message: str  # already redacted


class UnusableAnswer(Exception):
    """Raised by a parser: this provider's answer can't be used, try the next provider (no cool-off)."""


class AllProvidersFailed(Exception):
    def __init__(self, failures: Optional[list] = None):
        self.failures: list[ProviderFailure] = list(failures or [])
        super().__init__("; ".join(f"{f.provider}/{f.model}: {f.kind}" for f in self.failures) or "no provider available")

    @property
    def all_rate_limited(self) -> bool:
        return bool(self.failures) and all(f.kind == "rate_limit" for f in self.failures)


# ---- SDK exception classes, imported defensively ----

def _timeout_types() -> tuple:
    types: list = [TimeoutError, asyncio.TimeoutError]
    try:
        import openai
        types += [openai.APITimeoutError, openai.APIConnectionError]
    except Exception:  # pragma: no cover - SDK missing
        pass
    try:
        import anthropic
        types += [anthropic.APITimeoutError, anthropic.APIConnectionError]
    except Exception:  # pragma: no cover
        pass
    # google-genai raises plain httpx (or httpx2) timeouts / network errors
    for mod_name in ("httpx", "httpx2"):
        try:
            mod = __import__(mod_name)
            types += [mod.TimeoutException, mod.NetworkError]
        except Exception:  # pragma: no cover
            pass
    return tuple(types)


_TIMEOUT_TYPES = _timeout_types()


def _openai_rate_limit_type():
    try:
        from openai import RateLimitError
        return RateLimitError
    except Exception:  # pragma: no cover - openai always installed in prod
        return None


def _chain(exc: Optional[BaseException]):
    """exc, then its __cause__ / __context__ links, each once."""
    seen = set()
    while exc is not None and id(exc) not in seen:
        seen.add(id(exc))
        yield exc
        exc = exc.__cause__ or exc.__context__


def _statuses(exc: BaseException) -> set[int]:
    """Every HTTP-ish status number on the exception chain (status_code, status or code)."""
    found: set[int] = set()
    for e in _chain(exc):
        for attr in ("status_code", "status", "code"):
            value = getattr(e, attr, None)
            if isinstance(value, bool):
                continue
            if isinstance(value, int):
                found.add(value)
            elif isinstance(value, str) and value.strip().isdigit():
                found.add(int(value))
    return found


# ---- billing / rate limit helpers (used by classify and by insights_service) ----

def is_billing_error(exc: Optional[BaseException]) -> bool:
    """True when the AI provider refused for lack of credit/billing, following __cause__/__context__."""
    for e in _chain(exc):
        for attr in ("code", "status_code"):
            value = getattr(e, attr, None)
            if value == 402 or str(value) in ("402", "insufficient_quota"):
                return True
        if BILLING_TEXT.search(str(e) or ""):
            return True
    return False


def is_rate_limit_error(exc: Optional[BaseException], extra: Optional[Callable[[BaseException], bool]] = None) -> bool:
    """True for openai.RateLimitError, Gemini 429 / RESOURCE_EXHAUSTED and similar, following __cause__/__context__.

    Billing / out-of-credit refusals are excluded (see is_billing_error): they are not
    transient, so telling users to retry in a few minutes would be wrong. `extra` is an
    optional per-exception predicate (insights_service uses it for InsightAIError).
    """
    if is_billing_error(exc):
        return False
    openai_rate_limit = _openai_rate_limit_type()
    for e in _chain(exc):
        if extra is not None and extra(e):
            return True
        if openai_rate_limit is not None and isinstance(e, openai_rate_limit):
            return True
        for attr in ("code", "status_code"):
            value = getattr(e, attr, None)
            if value == 429 or str(value) == "429":
                return True
        status_value = str(getattr(e, "status", "") or "")
        if "RESOURCE_EXHAUSTED" in status_value.upper() or status_value == "429":
            return True
        if RATE_LIMIT_TEXT.search(str(e) or ""):
            return True
    return False


# ---- classification ----

def classify(exc: BaseException, provider: str, model: str) -> Optional[ProviderFailure]:
    """Map an exception from a provider call to a ProviderFailure, or None for a request-level error (no fallback)."""
    kind = _kind(exc)
    if kind is None:
        return None
    return ProviderFailure(provider, model, kind, redact(str(exc) or type(exc).__name__))


def _kind(exc: BaseException) -> Optional[str]:
    chain = list(_chain(exc))
    if any(isinstance(e, _TIMEOUT_TYPES) for e in chain):
        return "timeout"
    statuses = _statuses(exc)
    texts = [str(e) or "" for e in chain]
    status_names = " ".join(str(getattr(e, "status", "") or "") for e in chain)
    if statuses & {401, 403}:
        return "auth"
    if 402 in statuses or is_billing_error(exc):  # before the 400 rule: Anthropic reports billing as a 400
        return "billing"
    if 429 in statuses or "RESOURCE_EXHAUSTED" in status_names.upper() or any("RESOURCE_EXHAUSTED" in t for t in texts):
        return "rate_limit"
    if 404 in statuses or any(_MODEL_NOT_FOUND_TEXT.search(t) for t in texts):
        return "model_not_found"
    if any(s >= 500 for s in statuses) or any("overloaded" in t.lower() for t in texts) \
            or any("overloaded" in type(e).__name__.lower() for e in chain):
        return "server"
    return None  # other 400 / 422 / unknown: the request or our own code is at fault
