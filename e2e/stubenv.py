"""Isolates the Flow backend for E2E testing.

Import this BEFORE any backend module. It:
  * blocks .env loading (so production database URLs/API keys/Firebase creds are never read)
  * points the app at a local throwaway PostgreSQL
  * replaces OpenAI / Gemini / Claude clients, SMTP and Firebase messaging with recorders that never touch the network

With E2E_FAKE_AI=1 the three AI clients answer with canned replies and can be made to fail on demand:
set_fake_ai(claude="billing") writes FAKE_CONTROL, which every fake call re-reads (so it also steers a
separately running server). Without E2E_FAKE_AI every AI call raises AIStubError.
"""
import asyncio
import json
import os
import sys

BACKEND = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend")
OUTBOX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "outbox.jsonl")

# ---- 1. never read the real .env ----
import dotenv
dotenv.load_dotenv = lambda *a, **k: False
dotenv.dotenv_values = lambda *a, **k: {}

os.environ.update({
    "ADMIN_BOOTSTRAP_EMAIL": "root-admin@example.com",
    "ADMIN_BOOTSTRAP_PASSWORD": "e2e-root-admin-pass",
    # Local throwaway PostgreSQL.
    "DATABASE_URL": os.environ.get("E2E_PG_URL", "postgresql://flow@127.0.0.1:54329/flow_e2e"),
    "SECRET_KEY": "e2e-local-secret-not-production",
    "OPENAI_API_KEY": "sk-e2e-stub",
    "GOOGLE_API_KEY": "e2e-stub",
    "ANTHROPIC_API_KEY": "sk-ant-e2e-stub",
    "EMAIL_SENDER": "e2e@localhost",
    "EMAIL_PASSWORD": "stub",
    "FIREBASE_CREDENTIALS_PATH": os.path.join(os.path.dirname(OUTBOX), "no-such-firebase.json"),
    "FIREBASE_CREDENTIALS_JSON_STR": "{}",
    "OPENAI_BASE_URL": "http://127.0.0.1:9/v1",  # belt and braces: dead local port
})


def record(kind, **payload):
    with open(OUTBOX, "a", encoding="utf-8") as f:
        f.write(json.dumps({"kind": kind, **payload}, default=str) + "\n")


class AIStubError(Exception):
    pass


# ---- 2. AI clients ----
import openai


class _Raiser:
    def __init__(self, label):
        self._label = label

    def __getattr__(self, name):
        return _Raiser(f"{self._label}.{name}")

    def __call__(self, *a, **k):
        record("ai_call", target=self._label)
        raise AIStubError(f"AI stubbed for E2E ({self._label})")


class StubAsyncOpenAI:
    def __init__(self, *a, **k):
        self.chat = _Raiser("openai.chat")
        self.audio = _Raiser("openai.audio")
        self.embeddings = _Raiser("openai.embeddings")
        self.responses = _Raiser("openai.responses")


FAKE_AI = os.environ.get("E2E_FAKE_AI") == "1"
FAKE_REPLY = "## Fake answer\nYou spent money on groceries."
FAKE_STREAM_PARTS = ("## Fake answer\n", "You spent ", "money on groceries.")
FAKE_USAGE = (10, 5, 15)  # prompt, completion, total tokens


def _ns(**k):
    from types import SimpleNamespace
    return SimpleNamespace(**k)


# ---- failure control (shared by the in-process fakes and a separately running server) ----
FAKE_CONTROL = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".data", "fake_ai.json")

# Control file: {key: value}. A key is a provider id ("claude") or "provider@model" ("claude@claude-typo"); a model
# key wins over the provider key for that model. A value is a kind ("billing") or {"kind": "billing", "times": N}
# (the next N calls fail that way, then the entry is removed). See _raise_for / _begin for what each kind does.
FAKE_PROVIDERS = ("openai", "gemini", "claude")
_RAISING_KINDS = ("billing", "auth", "rate_limit", "server", "timeout", "model_not_found", "bad_request", "echo_key")
# An odd successful answer, not an error. length_once: a reply cut off at the output limit (OpenAI finish_reason
# "length", Gemini MAX_TOKENS, Claude stop_reason "max_tokens"), on the first matching call only.
_ANSWER_KINDS = ("refusal", "empty", "bad_json", "fail_mid_stream", "length_once")
_ONCE_KINDS = ("length_once",)  # consumed by the first matching call, even without "times"
FAKE_KINDS = _RAISING_KINDS + _ANSWER_KINDS  # later tasks add kinds here


class FakeAPIError(Exception):
    """What a fake provider SDK raises: an HTTP-style error with a status, a provider code and a message."""

    def __init__(self, status_code, code, message):
        super().__init__(f"Error code: {status_code} - {message}")
        self.status_code = status_code
        self.code = code
        self.message = message


def _check_control(kinds):
    """Raise ValueError for an unknown provider, an empty model, an unknown kind or a bad `times`."""
    for key, value in kinds.items():
        provider, at, model = str(key).partition("@")
        if provider not in FAKE_PROVIDERS or (at and not model.strip()):
            raise ValueError(f"fake AI control key {key!r}: expected one of {FAKE_PROVIDERS}, optionally @model")
        if isinstance(value, dict):
            times = value.get("times")
            if set(value) - {"kind", "times"} or value.get("kind") not in FAKE_KINDS or (
                    "times" in value and (type(times) is not int or times < 1)):
                raise ValueError(f"fake AI control value {value!r} for {key!r}: expected "
                                 f'{{"kind": one of {FAKE_KINDS}, "times": a positive int}}')
        elif value not in FAKE_KINDS:
            raise ValueError(f"fake AI control kind {value!r} for {key!r}: expected one of {FAKE_KINDS}")


def _write_control(data):
    os.makedirs(os.path.dirname(FAKE_CONTROL), exist_ok=True)
    tmp = f"{FAKE_CONTROL}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f)
    for attempt in range(20):  # atomic replace; on Windows a concurrent reader can briefly lock the target
        try:
            os.replace(tmp, FAKE_CONTROL)
            return
        except PermissionError:
            if attempt == 19:
                raise
            __import__("time").sleep(0.01)


def set_fake_ai(**kinds):
    """Make fake providers fail on demand, e.g. set_fake_ai(claude="billing", openai="timeout").

    Replaces the whole control file, so providers not named succeed. Kinds: billing, auth, rate_limit, server,
    timeout, model_not_found, bad_request, echo_key (raise); refusal (claude), empty, bad_json (odd successful
    answer); fail_mid_stream (streaming calls only); length_once (a reply cut off at the output limit, on the
    first matching call only). Model-scoped keys need dict unpacking:
    set_fake_ai(**{"claude@claude-typo": "model_not_found"}); a count limits a failure:
    set_fake_ai(claude={"kind": "rate_limit", "times": 2}). Typos raise ValueError.
    """
    _check_control(kinds)
    _write_control(kinds)


def clear_fake_ai():
    try:
        os.remove(FAKE_CONTROL)
    except FileNotFoundError:
        pass


def _control():
    try:
        with open(FAKE_CONTROL, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _raise_for(provider, kind):
    claude = provider == "claude"
    if kind == "timeout":
        raise TimeoutError("fake request timed out")
    if kind == "billing":
        if claude:
            raise FakeAPIError(400, None, "Your credit balance is too low to access the Anthropic API")
        raise FakeAPIError(402, "insufficient_quota", "You exceeded your current quota")
    if kind == "auth":
        raise FakeAPIError(401, "invalid_api_key", "Invalid API key")
    if kind == "rate_limit":
        raise FakeAPIError(429, "rate_limit_exceeded", "Rate limit reached")
    if kind == "server":
        raise FakeAPIError(529 if claude else 503, None, "The service is overloaded" if claude else "The service is unavailable")
    if kind == "model_not_found":
        raise FakeAPIError(404, "model_not_found", "The model does not exist")
    if kind == "bad_request":
        raise FakeAPIError(400, None, "invalid image")
    if kind == "echo_key":
        raise FakeAPIError(401, "invalid_api_key", "Incorrect API key provided: sk-e2eSECRETabcdef123")


LAST_KWARGS = {}  # provider id -> the keyword arguments of its latest fake SDK call (in-process checks read this)


def _take_kind(provider, model):
    """The kind configured for this call ("provider@model" first, then "provider"), consuming one of its `times`."""
    data = _control()
    key = next((k for k in (f"{provider}@{model}", provider) if k in data), None)
    if key is None:
        return None
    value = data[key]
    if not isinstance(value, dict):
        if value in _ONCE_KINDS:
            del data[key]
            _write_control(data)
        return value
    times = value.get("times", 1 if value.get("kind") in _ONCE_KINDS else None)
    if isinstance(times, int):
        if times <= 1:
            del data[key]
        else:
            data[key] = {**value, "times": times - 1}
        _write_control(data)
    return value.get("kind")


def _begin(provider, target, model, streaming=False, **extra):
    """Record the call, raise the configured failure, else return the configured odd-answer kind (or None)."""
    record("ai_call", provider=provider, target=target, model=model, **extra)
    kind = _take_kind(provider, model)
    if kind in _RAISING_KINDS:
        _raise_for(provider, kind)
    if kind == "fail_mid_stream" and not streaming:
        return None
    return kind


def _stream_delay():
    # E2E_FAKE_AI_DELAY (seconds, default 0) slows the stream so a client
    # can be checked mid-stream (e.g. the web chat's Cancel button).
    return float(os.environ.get("E2E_FAKE_AI_DELAY") or 0)


def _canned_json(prompt):
    """The JSON the fakes answer a transaction-extraction prompt with: one transaction, or several."""
    today = __import__("datetime").date.today().isoformat()
    if '\\"transactions\\"' in prompt or "multiple" in prompt.lower():
        body = {"transactions": [
            {"type": "expense", "main_category": "Food & Drinks", "sub_category": "Lunch", "date": today,
             "description": "lunch", "amount": 4.5, "currency": "usd", "confidence": 0.9},
            {"type": "outflow", "main_category": "Transport", "sub_category": "Taxi Ride", "date": today,
             "description": "grab ride", "amount": 3, "currency": "usd", "confidence": 0.8},
            {"type": "outflow", "main_category": "Shopping", "sub_category": "Clothes", "date": today,
             "description": "unreadable", "amount": 0, "currency": "usd", "confidence": 0.3}],
            "total_count": 3, "overall_confidence": 0.7, "analysis": "3 items"}
    else:
        body = {"type": "expense", "main_category": "Food & Drinks", "sub_category": "Coffee", "date": today,
                "description": "coffee", "amount": 2.5, "currency": "usd", "confidence": 0.9, "reasoning": "fake"}
    return json.dumps(body)


def _answer_text(kind, prompt, wants_json):
    if kind == "empty":
        return ""
    if kind == "bad_json":
        return "not json"
    text = _canned_json(prompt) if wants_json else FAKE_REPLY
    if kind == "length_once":  # cut off at the output limit
        return text[:max(1, len(text) // 2)]
    return text


def _stream_parts(text):
    return FAKE_STREAM_PARTS if text == FAKE_REPLY else (text,)


def _field(obj, name):
    """obj[name] for a dict, obj.name for an SDK config object."""
    return obj.get(name) if isinstance(obj, dict) else getattr(obj, name, None)


# ---- OpenAI ----
class _FakeCompletions:
    async def create(self, *a, stream=False, **k):
        LAST_KWARGS["openai"] = dict(k, stream=stream)
        kind = _begin("openai", "chat.completions.create", k.get("model"), streaming=stream, stream=stream)
        usage = _ns(prompt_tokens=FAKE_USAGE[0], completion_tokens=FAKE_USAGE[1], total_tokens=FAKE_USAGE[2])
        wants_json = (k.get("response_format") or {}).get("type") == "json_object"
        text = _answer_text(kind, json.dumps(k.get("messages", [])), wants_json)
        finish = "length" if kind == "length_once" else "stop"
        if not stream:
            return _ns(choices=[_ns(message=_ns(content=text), finish_reason=finish)], usage=usage, model="fake")

        async def gen():
            delay = _stream_delay()
            parts = _stream_parts(text)
            for i, part in enumerate(parts):
                if delay:
                    await asyncio.sleep(delay)
                last_finish = "length" if kind == "length_once" and i == len(parts) - 1 else None
                yield _ns(choices=[_ns(delta=_ns(content=part), finish_reason=last_finish)], usage=None, model="fake")
                if kind == "fail_mid_stream":
                    raise FakeAPIError(503, None, "The service is unavailable")
            yield _ns(choices=[], usage=usage, model="fake")
        return gen()


class _FakeTranscriptions:
    async def create(self, *a, **k):
        LAST_KWARGS["openai"] = dict(k)
        kind = _begin("openai", "audio.transcriptions.create", k.get("model"))
        return _ns(text={"empty": "", "bad_json": "not json"}.get(kind, "fake transcript"))


class FakeAsyncOpenAI:
    def __init__(self, *a, **k):
        self.chat = _ns(completions=_FakeCompletions())
        self.audio = _ns(transcriptions=_FakeTranscriptions())
        self.embeddings = _Raiser("openai.embeddings")
        self.responses = _Raiser("openai.responses")


openai.AsyncOpenAI = FakeAsyncOpenAI if FAKE_AI else StubAsyncOpenAI
openai.OpenAI = StubAsyncOpenAI


# ---- Gemini (google.genai) ----
def _gemini_response(text, finish_reason="STOP"):
    return _ns(text=text, candidates=[_ns(finish_reason=finish_reason)],
               usage_metadata=_ns(prompt_token_count=FAKE_USAGE[0], candidates_token_count=FAKE_USAGE[1]))


def _gemini_wants_json(config):
    return config is not None and _field(config, "response_mime_type") == "application/json"


def _gemini_has_audio(contents):
    return isinstance(contents, list) and any(
        str(getattr(getattr(p, "inline_data", None), "mime_type", "") or "").startswith("audio/") for p in contents)


class _FakeGeminiModels:
    async def generate_content(self, *, model=None, contents=None, config=None, **k):
        LAST_KWARGS["gemini"] = dict(k, model=model, contents=contents, config=config)
        kind = _begin("gemini", "aio.models.generate_content", model)
        wants_json = _gemini_wants_json(config)
        if _gemini_has_audio(contents):  # a transcription request answers like OpenAI's audio.transcriptions
            return _gemini_response({"empty": "", "bad_json": "not json"}.get(kind, "fake transcript"))
        text = _answer_text(kind, json.dumps([contents, str(config)], default=str), wants_json)
        return _gemini_response(text, "MAX_TOKENS" if kind == "length_once" else "STOP")

    async def generate_content_stream(self, *, model=None, contents=None, config=None, **k):
        LAST_KWARGS["gemini"] = dict(k, model=model, contents=contents, config=config)
        kind = _begin("gemini", "aio.models.generate_content_stream", model, streaming=True)
        wants_json = _gemini_wants_json(config)
        text = _answer_text(kind, json.dumps([contents, str(config)], default=str), wants_json)
        parts = _stream_parts(text)

        async def gen():
            delay = _stream_delay()
            for i, part in enumerate(parts):
                if delay:
                    await asyncio.sleep(delay)
                last = i == len(parts) - 1
                end = "MAX_TOKENS" if kind == "length_once" else "STOP"
                chunk = _gemini_response(part, finish_reason=end if last else None)
                if not last:
                    chunk.usage_metadata = None
                yield chunk
                if kind == "fail_mid_stream":
                    raise FakeAPIError(503, None, "The service is unavailable")
        return gen()


class FakeGenaiClient:
    def __init__(self, *a, **k):
        self.aio = _ns(models=_FakeGeminiModels())
        self.models = _Raiser("gemini.models")
        self.files = _Raiser("gemini.files")


try:
    from google import genai

    class StubGenaiClient:
        def __init__(self, *a, **k):
            self.models = _Raiser("gemini.models")
            self.aio = _Raiser("gemini.aio")
            self.files = _Raiser("gemini.files")

    genai.Client = FakeGenaiClient if FAKE_AI else StubGenaiClient
except Exception:
    pass


# ---- Claude (anthropic) ----
import anthropic  # noqa: E402


def _claude_message(text, stop_reason, model):
    content = [_ns(type="text", text=text)] if text else []
    return _ns(id="msg_fake", type="message", role="assistant", model=model, content=content, stop_reason=stop_reason,
               usage=_ns(input_tokens=FAKE_USAGE[0], output_tokens=FAKE_USAGE[1]))


def _claude_answer(kind, k):
    """(text, stop_reason) a Claude call answers with."""
    # Structured output is requested through output_format or output_config={"format": ...}.
    wants_json = bool(k.get("output_format")) or "format" in (k.get("output_config") or {})
    prompt = json.dumps([k.get("system"), k.get("messages", [])], default=str)
    if kind == "refusal":
        return "", "refusal"
    return _answer_text(kind, prompt, wants_json), "max_tokens" if kind == "length_once" else "end_turn"


class _FakeClaudeStream:
    """Async context manager like anthropic's message stream: async text_stream plus get_final_message()."""

    def __init__(self, kind, k, error=None):
        self._kind = kind
        self._error = error
        self._model = k.get("model")
        self._text, self._stop = _claude_answer(kind, k)
        self._parts = _stream_parts(self._text) if self._text else ()

    async def __aenter__(self):
        if self._error:  # like the real SDK, the request (and so its failure) happens on entering
            raise self._error
        return self

    async def __aexit__(self, *exc):
        return False

    @property
    def text_stream(self):
        async def gen():
            delay = _stream_delay()
            for part in self._parts:
                if delay:
                    await asyncio.sleep(delay)
                yield part
                if self._kind == "fail_mid_stream":
                    raise FakeAPIError(503, None, "The service is unavailable")
        return gen()

    async def get_final_message(self):
        return _claude_message(self._text, self._stop, self._model)


class _FakeClaudeMessages:
    async def create(self, **k):
        LAST_KWARGS["claude"] = dict(k)
        kind = _begin("claude", "beta.messages.create", k.get("model"))
        text, stop = _claude_answer(kind, k)
        return _claude_message(text, stop, k.get("model"))

    def stream(self, **k):
        LAST_KWARGS["claude"] = dict(k)
        try:
            kind = _begin("claude", "beta.messages.stream", k.get("model"), streaming=True)
        except Exception as e:  # noqa: BLE001
            return _FakeClaudeStream(None, k, error=e)
        return _FakeClaudeStream(kind, k)


class FakeAsyncAnthropic:
    def __init__(self, *a, **k):
        self.beta = _ns(messages=_FakeClaudeMessages())
        self.messages = _Raiser("claude.messages")


class StubAsyncAnthropic:
    def __init__(self, *a, **k):
        self.beta = _Raiser("claude.beta")
        self.messages = _Raiser("claude.messages")


anthropic.AsyncAnthropic = FakeAsyncAnthropic if FAKE_AI else StubAsyncAnthropic
anthropic.Anthropic = StubAsyncAnthropic

try:
    import langchain_openai

    class _StubEmb:
        def __init__(self, *a, **k):
            pass

        @staticmethod
        def _vec(text):
            import hashlib
            h = hashlib.sha256(str(text).encode()).digest()
            return [b / 255.0 for b in h]

        def embed_documents(self, texts, *a, **k):
            if not FAKE_AI:
                record("ai_call", target="langchain.embed_documents")
                raise AIStubError("embeddings stubbed")
            return [self._vec(t) for t in texts]

        def embed_query(self, text, *a, **k):
            if not FAKE_AI:
                raise AIStubError("embeddings stubbed")
            return self._vec(text)

        async def aembed_documents(self, texts, *a, **k):
            return self.embed_documents(texts)

        async def aembed_query(self, text, *a, **k):
            return self.embed_query(text)

    langchain_openai.OpenAIEmbeddings = _StubEmb
    langchain_openai.ChatOpenAI = StubAsyncOpenAI
except Exception:
    pass

# ---- 3. SMTP ----
import smtplib


class StubSMTP:
    def __init__(self, *a, **k):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def __getattr__(self, name):
        def f(*a, **k):
            if name in ("send_message", "sendmail"):
                parts = []
                for x in a:
                    if hasattr(x, "get_body"):
                        body = x.get_body(preferencelist=("plain", "html"))
                        parts.append(f"To: {x['To']} Subject: {x['Subject']} " + (body.get_content() if body else ""))
                    else:
                        parts.append(str(x)[:20000])
                record("smtp", method=name, args=parts)
            return (250, b"ok")
        return f


smtplib.SMTP = StubSMTP
smtplib.SMTP_SSL = StubSMTP

# ---- 4. Firebase messaging ----
try:
    from firebase_admin import messaging

    def _send(msg, *a, **k):
        record("fcm_send", token=getattr(msg, "token", None),
               title=getattr(getattr(msg, "notification", None), "title", None))
        return "stub-message-id"

    class _BatchResp:
        def __init__(self, n):
            self.success_count = n
            self.failure_count = 0
            self.responses = []

    def _send_multi(msg, *a, **k):
        toks = getattr(msg, "tokens", []) or []
        record("fcm_multicast", n=len(toks))
        return _BatchResp(len(toks))

    messaging.send = _send
    messaging.send_each_for_multicast = _send_multi
    messaging.send_multicast = _send_multi
except Exception:
    pass

if BACKEND not in sys.path:
    sys.path.insert(0, BACKEND)


def patch_loaded_modules():
    """Patch names that backend modules imported by value (from x import y)."""
    import firebase_service

    def fake_init():
        record("firebase_init")

    def fake_send(*a, **k):
        names = ("fcm_token", "title", "body", "data")
        args = dict(zip(names, a)) | k
        record("fcm_send", **{n: args.get(n) for n in names})
        return True

    def fake_send_multi(*a, **k):
        tokens = k.get("fcm_tokens", a[0] if a else [])
        record("fcm_multicast", n=len(tokens or []), title=k.get("title", a[1] if len(a) > 1 else None))
        return {"success": len(tokens or []), "failure": 0}

    for mod in list(sys.modules.values()):
        f = getattr(mod, "__file__", "") or ""
        if not f.startswith(BACKEND):
            continue
        for name, fn in (("initialize_firebase", fake_init), ("send_fcm_notification", fake_send),
                         ("send_fcm_to_multiple", fake_send_multi)):
            if hasattr(mod, name):
                setattr(mod, name, fn)
