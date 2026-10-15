"""Isolates the Flow backend for E2E testing.

Import this BEFORE any backend module. It:
  * blocks .env loading (so production Mongo/API keys/Firebase creds are never read)
  * points the app at a local throwaway mongod
  * replaces OpenAI / Gemini clients, SMTP and Firebase messaging with recorders that never touch the network
"""
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
    "MONGODB_URL": os.environ.get("E2E_MONGO", "mongodb://127.0.0.1:27999"),
    "DATABASE_NAME": "flow_e2e",
    # Local throwaway PostgreSQL (migration in progress: tables move from Mongo one by one).
    "DATABASE_URL": os.environ.get("E2E_PG_URL", "postgresql://flow@127.0.0.1:54329/flow_e2e"),
    "SECRET_KEY": "e2e-local-secret-not-production",
    "OPENAI_API_KEY": "sk-e2e-stub",
    "GOOGLE_API_KEY": "e2e-stub",
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


def _ns(**k):
    from types import SimpleNamespace
    return SimpleNamespace(**k)


class _FakeCompletions:
    async def create(self, *a, stream=False, **k):
        record("ai_call", target="openai.chat.completions.create(fake)", stream=stream)
        usage = _ns(prompt_tokens=10, completion_tokens=5, total_tokens=15)
        if (k.get("response_format") or {}).get("type") == "json_object":
            prompt = json.dumps(k.get("messages", []))
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
            return _ns(choices=[_ns(message=_ns(content=json.dumps(body)), finish_reason="stop")], usage=usage, model="fake")
        if not stream:
            return _ns(choices=[_ns(message=_ns(content=FAKE_REPLY), finish_reason="stop")], usage=usage, model="fake")

        async def gen():
            for part in ("## Fake answer\n", "You spent ", "money on groceries."):
                yield _ns(choices=[_ns(delta=_ns(content=part), finish_reason=None)], usage=None, model="fake")
            yield _ns(choices=[], usage=usage, model="fake")
        return gen()


class FakeAsyncOpenAI:
    def __init__(self, *a, **k):
        self.chat = _ns(completions=_FakeCompletions())
        self.audio = _Raiser("openai.audio")
        self.embeddings = _Raiser("openai.embeddings")
        self.responses = _Raiser("openai.responses")


openai.AsyncOpenAI = FakeAsyncOpenAI if FAKE_AI else StubAsyncOpenAI
openai.OpenAI = StubAsyncOpenAI

try:
    from google import genai

    class StubGenaiClient:
        def __init__(self, *a, **k):
            self.models = _Raiser("gemini.models")
            self.aio = _Raiser("gemini.aio")
            self.files = _Raiser("gemini.files")

    genai.Client = StubGenaiClient
except Exception:
    pass

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
