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
# (Gemini: 429 RESOURCE_EXHAUSTED "Your prepayment credits are depleted"; OpenAI: 429
# insufficient_quota; Anthropic: 400 "credit balance is too low"), but waiting a few
# minutes won't help: someone must top up.
BILLING_TEXT = re.compile(
    r"credits? (are |is )?depleted|insufficient[_ ]quota|billing|prepay|payment required|exceeded your current quota"
    r"|credit balance is too low",
    re.IGNORECASE,
)

_MODEL_NOT_FOUND_TEXT = re.compile(r"model\b.*\b(not found|does not exist)|\b(not found|does not exist)\b.*\bmodel", re.IGNORECASE | re.DOTALL)

_CREDIT_BALANCE_TEXT = re.compile(r"credit balance is too low", re.IGNORECASE)
# Gemini's depleted prepaid credits (a 429). Not in its per-minute-limit text, so it is an explicit billing signal.
_DEPLETED_CREDITS_TEXT = re.compile(r"credits.*depleted|prepay", re.IGNORECASE | re.DOTALL)
# OpenAI structured-error codes that mean "this model can't serve this request" (see _model_level_400).
_MODEL_LEVEL_CODES = frozenset({"unsupported_parameter", "model_not_found"})
# ...and unsupported_value on one of these sampling parameters (reasoning models accept only the default temperature).
_SAMPLING_PARAMS = frozenset({"temperature", "top_p", "top_k", "frequency_penalty", "presence_penalty", "logit_bias",
                              "logprobs", "top_logprobs", "n"})
_BAD_KEY_TEXT = re.compile(r"API key not valid|API key expired|API_KEY_INVALID", re.IGNORECASE)


def _error_code(exc: BaseException) -> str:
    value = getattr(exc, "code", None)
    return value.lower() if isinstance(value, str) else ""


# API keys a provider may echo back in an error message. Anything that looks like one is removed. Each form must
# start a word, so ordinary words such as "risk-assessment" are left alone.
_KEY_PATTERNS = re.compile(
    r"(?<![A-Za-z0-9])sk-ant-[A-Za-z0-9_-]{6,}(?:\*+[A-Za-z0-9_-]*)?"
    r"|(?<![A-Za-z0-9])sk-[A-Za-z0-9_-]{6,}(?:\*+[A-Za-z0-9_-]*)?"
    r"|(?<![A-Za-z0-9])sk-[A-Za-z0-9_-]*\*{3,}[A-Za-z0-9_-]*"  # OpenAI's masked echo: sk-proj-****abcd
    r"|(?<![A-Za-z0-9])AIza[0-9A-Za-z_-]{10,}"
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
    """Raised by a parser: this provider's answer can't be used, try the next provider (no cool-off).

    A `call` that made billed requests before giving up can pass them as `completion` (a Completion whose `requests`
    lists them), so the runner records them as rejected usage rows; a parser need not (the runner already has the
    answer it parsed). Likewise a `call` that fails with any other error after billed requests can set
    `error.billed_usage = <Completion>` before re-raising; the runner records those as rejected too."""

    def __init__(self, *args, completion=None):
        super().__init__(*args)
        self.completion = completion


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


def exception_chain(exc: Optional[BaseException]):
    """exc, then its __cause__ / __context__ links, each once."""
    seen = set()
    while exc is not None and id(exc) not in seen:
        seen.add(id(exc))
        yield exc
        exc = exc.__cause__ or exc.__context__


_chain = exception_chain  # internal short name


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
    if 408 in statuses:
        return "timeout"
    if statuses & {401, 403}:
        return "auth"
    # Gemini reports a bad or expired key as HTTP 400 INVALID_ARGUMENT, so check the text before the 400 rule.
    if any(_BAD_KEY_TEXT.search(t) for t in texts):
        return "auth"
    # Billing needs an explicit signal. A plain 429 / RESOURCE_EXHAUSTED is a rate limit even when its text
    # mentions "quota" and "billing" (Gemini's per-minute limit does).
    if 402 in statuses or any(_error_code(e) == "insufficient_quota" for e in chain) \
            or any(_CREDIT_BALANCE_TEXT.search(t) for t in texts) \
            or any(_DEPLETED_CREDITS_TEXT.search(t) for t in texts):  # Anthropic: a 400; Gemini: a 429
        return "billing"
    if 429 in statuses or "RESOURCE_EXHAUSTED" in status_names.upper() or any("RESOURCE_EXHAUSTED" in t for t in texts):
        return "rate_limit"
    if any(BILLING_TEXT.search(t) for t in texts):  # not a rate limit: billing wording alone is enough
        return "billing"
    if 404 in statuses or any(_MODEL_NOT_FOUND_TEXT.search(t) for t in texts) or _model_level_400(chain, statuses):
        return "model_not_found"
    if any(s >= 500 for s in statuses) or any("overloaded" in t.lower() for t in texts) \
            or any("overloaded" in type(e).__name__.lower() for e in chain):
        return "server"
    return None  # other 400 / 422 / unknown: the request or our own code is at fault


def _model_level_400(chain: list, statuses: set[int]) -> bool:
    """A 400 whose structured error (OpenAI's `param` / `code`) blames the model: it names param "model" (e.g. a chat
    model sent to the transcription endpoint), has code unsupported_parameter / model_not_found (e.g. max_tokens
    on a reasoning model), or has code unsupported_value on a sampling parameter (e.g. temperature 0.3 on a
    reasoning model). It is specific to the provider+model pair, so it cools that pair and falls back.

    Anthropic and Gemini report an unknown model as a 404 (handled by the 404 rule) and have no such fields.
    """
    if 400 not in statuses:
        return False

    def blames_model(e) -> bool:
        param, code = getattr(e, "param", None), _error_code(e)
        return param == "model" or code in _MODEL_LEVEL_CODES \
            or (code == "unsupported_value" and param in _SAMPLING_PARAMS)
    return any(blames_model(e) for e in chain)
