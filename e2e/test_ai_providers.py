"""AI provider switching: fake provider SDKs, failure control, and (in later tasks) the runner and admin API.

Print-only suite: every check prints [PASS] or [BUG]; the exit code is non-zero if any check failed.
"""
import asyncio
import base64
import copy
import json
import os
import sys
from types import SimpleNamespace as NS

# The in-process fakes only answer in fake mode (the stubbed server runs with the same flag).
os.environ.setdefault("E2E_FAKE_AI", "1")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402

os.chdir(stubenv.BACKEND)

import anthropic  # noqa: E402
import openai  # noqa: E402
from google import genai  # noqa: E402

results = []


def check(ok, name, detail=""):
    results.append(bool(ok))
    print(("[PASS] " if ok else "[BUG] ") + name + (f" -- {detail}" if detail and not ok else ""), flush=True)


class LogCapture:
    """with LogCapture("budget_service") as cap: ... -> cap.records (every level, that logger and its children)."""

    def __init__(self, name=None):
        import logging

        records = self.records = []

        class _Handler(logging.Handler):
            def emit(self, record):
                records.append(record)

        self._logger = logging.getLogger(name)
        self._handler = _Handler()
        self._old_level = None

    def __enter__(self):
        import logging
        self._old_level = self._logger.level
        self._logger.setLevel(logging.DEBUG)
        self._logger.addHandler(self._handler)
        return self

    def __exit__(self, *exc):
        self._logger.removeHandler(self._handler)
        self._logger.setLevel(self._old_level)
        return False

    def at(self, level):
        return [r for r in self.records if r.levelno == level]


def outbox_lines():
    if not os.path.exists(stubenv.OUTBOX):
        return []
    with open(stubenv.OUTBOX, encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


async def claude_hi():
    return await anthropic.AsyncAnthropic().beta.messages.create(
        model="claude-sonnet-5-5", max_tokens=100, messages=[{"role": "user", "content": "hi"}])


async def fake_checks():
    # --- the fakes answer when no failure is configured
    stubenv.clear_fake_ai()
    try:
        r = await claude_hi()
        text = "".join(b.text for b in r.content if b.type == "text")
        check(r.stop_reason == "end_turn" and text.strip() and r.usage.input_tokens == 10,
              "fake_claude_succeeds", f"{r.stop_reason!r} {text!r} {r.usage}")
    except Exception as e:  # noqa: BLE001
        check(False, "fake_claude_succeeds", repr(e))

    try:
        r = await genai.Client().aio.models.generate_content(model="gemini-2.5-flash", contents="hi")
        check(bool(r.text and r.text.strip()), "fake_gemini_succeeds", repr(r.text))
    except Exception as e:  # noqa: BLE001
        check(False, "fake_gemini_succeeds", repr(e))

    # --- a failure configured through the control file is raised, then cleared
    stubenv.set_fake_ai(claude="billing")
    try:
        await claude_hi()
        check(False, "fake_control_billing", "call succeeded")
    except stubenv.FakeAPIError as e:
        check(e.status_code == 400 and "credit balance is too low" in e.message,
              "fake_control_billing", f"{e.status_code} {e.message}")
    except Exception as e:  # noqa: BLE001
        check(False, "fake_control_billing", repr(e))
    stubenv.clear_fake_ai()
    try:
        r = await claude_hi()
        check(r.stop_reason == "end_turn", "fake_control_cleared_restores_success", r.stop_reason)
    except Exception as e:  # noqa: BLE001
        check(False, "fake_control_cleared_restores_success", repr(e))

    # --- every fake call leaves an ai_call line in the outbox
    before = len(outbox_lines())
    await claude_hi()
    new = [x for x in outbox_lines()[before:] if x.get("kind") == "ai_call"]
    check(new and new[-1].get("provider") == "claude" and new[-1].get("model") == "claude-sonnet-5-5",
          "fake_records_calls", repr(new))


async def call(provider, stream=False, json_mode=False):
    """One call through the fake SDK of `provider`; returns (text, extra) where extra is the raw response."""
    if provider == "openai":
        kw = {"response_format": {"type": "json_object"}} if json_mode else {}
        c = openai.AsyncOpenAI()
        r = await c.chat.completions.create(model="gpt-4o-mini", messages=[{"role": "user", "content": "hi"}],
                                            max_completion_tokens=100, stream=stream, **kw)
        if not stream:
            return r.choices[0].message.content, r
        return "".join([ch.choices[0].delta.content async for ch in r if ch.choices]), r
    if provider == "gemini":
        cfg = {"response_mime_type": "application/json"} if json_mode else {}
        m = genai.Client().aio.models
        if not stream:
            r = await m.generate_content(model="gemini-2.5-flash", contents="hi", config=cfg)
            return r.text, r
        r = await m.generate_content_stream(model="gemini-2.5-flash", contents="hi", config=cfg)
        return "".join([ch.text async for ch in r]), r
    kw = {"output_config": {"format": {"type": "json_schema", "schema": {}}}} if json_mode else {}
    c = anthropic.AsyncAnthropic().beta.messages
    if not stream:
        r = await c.create(model="claude-sonnet-5-5", max_tokens=100, messages=[{"role": "user", "content": "hi"}], **kw)
        return "".join(b.text for b in r.content if b.type == "text"), r
    async with c.stream(model="claude-sonnet-5-5", max_tokens=100, messages=[{"role": "user", "content": "hi"}], **kw) as s:
        text = "".join([t async for t in s.text_stream])
        return text, await s.get_final_message()


async def outcome(*args, **kw):
    """('ok', text) for an answer, ('err', (status, code, message)) for a FakeAPIError, ('timeout', None)."""
    try:
        text, _ = await call(*args, **kw)
        return "ok", text
    except stubenv.FakeAPIError as e:
        return "err", (e.status_code, e.code, e.message)
    except TimeoutError:
        return "timeout", None


async def length_once_checks():
    """Task 9: control kind length_once maps through each fake SDK and each client to finish "length", once."""
    from ai_providers.clients.base import get_client
    from ai_providers.types import Prompt

    raw = {"openai": lambda r: r.choices[0].finish_reason, "gemini": lambda r: r.candidates[0].finish_reason,
           "claude": lambda r: r.stop_reason}
    want = {"openai": "length", "gemini": "MAX_TOKENS", "claude": "max_tokens"}
    models = {"openai": "gpt-4o-mini", "gemini": "gemini-2.5-flash", "claude": "claude-sonnet-5-5"}
    for p in ("openai", "gemini", "claude"):
        stubenv.set_fake_ai(**{p: "length_once"})
        text, r = await call(p)
        check(raw[p](r) == want[p] and text and text != stubenv.FAKE_REPLY and stubenv.FAKE_REPLY.startswith(text),
              f"length_once: {p} answers a cut-off reply with {want[p]}", (raw[p](r), text))
        text2, r2 = await call(p)
        check(raw[p](r2) != want[p] and text2 == stubenv.FAKE_REPLY,
              f"length_once: {p} second call is a normal reply (first matching call only)", (raw[p](r2), text2))
        stubenv.set_fake_ai(**{p: "length_once"})
        c = await get_client(p).complete(models[p], Prompt("sys", "hi", max_tokens=100))
        check(c.finish == "length" and c.text, f"length_once: the {p} client maps it to finish 'length'", c)
        stubenv.set_fake_ai(**{p: "length_once"})
        finals = [x async for x in get_client(p).stream(models[p], Prompt("sys", "hi", max_tokens=100))
                  if not isinstance(x, str)]
        check(finals and finals[-1].finish == "length", f"length_once: the {p} client stream ends with finish 'length'",
              finals)
    # the {"kind": ...} form is also consumed by its first call; "times" still counts when given
    stubenv.set_fake_ai(claude={"kind": "length_once"})
    got = [(await call("claude"))[1].stop_reason for _ in range(2)]
    check(got == ["max_tokens", "end_turn"], "length_once: {'kind': 'length_once'} applies once", got)
    stubenv.set_fake_ai(claude={"kind": "length_once", "times": 2})
    got = [(await call("claude"))[1].stop_reason for _ in range(3)]
    check(got == ["max_tokens", "max_tokens", "end_turn"], "length_once: times=2 applies twice", got)
    stubenv.clear_fake_ai()


async def kind_checks():
    stubenv.clear_fake_ai()
    for p in ("openai", "gemini", "claude"):
        kind, text = await outcome(p)
        check(kind == "ok" and text == stubenv.FAKE_REPLY, f"{p}: default reply", f"{kind} {text!r}")
        kind, text = await outcome(p, stream=True)
        check(kind == "ok" and text == stubenv.FAKE_REPLY, f"{p}: default stream joins to the reply", f"{kind} {text!r}")
        kind, text = await outcome(p, json_mode=True)
        check(kind == "ok" and json.loads(text).get("amount") == 2.5, f"{p}: json mode gives a transaction", f"{kind} {text!r}")

    # failure kinds -> status per provider (claude differs for billing and server)
    table = {
        "billing": {"openai": 402, "gemini": 402, "claude": 400},
        "auth": {"openai": 401, "gemini": 401, "claude": 401},
        "rate_limit": {"openai": 429, "gemini": 429, "claude": 429},
        "server": {"openai": 503, "gemini": 503, "claude": 529},
        "model_not_found": {"openai": 404, "gemini": 404, "claude": 404},
        "bad_request": {"openai": 400, "gemini": 400, "claude": 400},
        "echo_key": {"openai": 401, "gemini": 401, "claude": 401},
        "invalid_model": {"openai": 400, "gemini": 400, "claude": 400},
        "unsupported_param": {"openai": 400, "gemini": 400, "claude": 400},
        "unsupported_value": {"openai": 400, "gemini": 400, "claude": 400},
    }
    for kind_name, per in table.items():
        for p, status in per.items():
            stubenv.set_fake_ai(**{p: kind_name})
            for stream in (False, True):
                kind, info = await outcome(p, stream=stream)
                check(kind == "err" and info[0] == status, f"{p} {kind_name}{' (stream)' if stream else ''} -> {status}",
                      f"{kind} {info}")
    stubenv.set_fake_ai(openai="billing", claude="billing")
    kind, info = await outcome("openai")
    check(info == (402, "insufficient_quota", "You exceeded your current quota"), "openai billing is 402 insufficient_quota", info)
    kind, info = await outcome("claude")
    check(info == (400, None, "Your credit balance is too low to access the Anthropic API"), "claude billing message", info)
    stubenv.set_fake_ai(openai="bad_request")
    kind, info = await outcome("openai")
    check(info and info[2] == "invalid image", "bad_request message is 'invalid image'", info)
    # F1: the fake OpenAI chat endpoint refuses max_tokens like OpenAI's reasoning models do
    stubenv.clear_fake_ai()
    try:
        await openai.AsyncOpenAI().chat.completions.create(model="gpt-4o-mini", messages=[], max_tokens=5)
        check(False, "fake openai: max_tokens is refused (unsupported_parameter)", "no error")
    except stubenv.FakeAPIError as e:
        check(e.status_code == 400 and e.code == "unsupported_parameter" and e.param == "max_tokens",
              "fake openai: max_tokens is refused (unsupported_parameter)", (e.status_code, e.code, e.param))
    stubenv.set_fake_ai(openai="invalid_model")
    kind, info = await outcome("openai")
    check(kind == "err" and info[0] == 400 and info[1] is None and "Invalid model" in info[2],
          "invalid_model is a 400 with no code", info)
    stubenv.set_fake_ai(gemini="echo_key")
    kind, info = await outcome("gemini")
    check(info and info[2] == "Incorrect API key provided: sk-e2eSECRETabcdef123", "echo_key message carries the fake key", info)
    stubenv.set_fake_ai(gemini="timeout", openai="timeout", claude="timeout")
    for p in ("openai", "gemini", "claude"):
        kind, _ = await outcome(p)
        check(kind == "timeout", f"{p} timeout raises TimeoutError", kind)

    # one provider failing leaves the others alone
    stubenv.set_fake_ai(claude="server")
    kind, _ = await outcome("openai")
    check(kind == "ok", "a failing claude does not affect openai")

    # odd successful answers
    stubenv.set_fake_ai(claude="refusal")
    _, r = await call("claude")
    check(r.stop_reason == "refusal", "claude refusal has stop_reason 'refusal'", r.stop_reason)
    for p in ("openai", "gemini", "claude"):
        stubenv.set_fake_ai(**{p: "empty"})
        kind, text = await outcome(p)
        check(kind == "ok" and text == "", f"{p} empty answer", f"{kind} {text!r}")
        stubenv.set_fake_ai(**{p: "bad_json"})
        kind, text = await outcome(p, json_mode=True)
        check(kind == "ok" and text == "not json", f"{p} bad_json answer", f"{kind} {text!r}")

    # fail_mid_stream: one chunk, then a 503; a non-streaming call is unaffected
    for p in ("openai", "gemini", "claude"):
        stubenv.set_fake_ai(**{p: "fail_mid_stream"})
        got = []
        try:
            if p == "openai":
                r = await openai.AsyncOpenAI().chat.completions.create(model="m", messages=[], stream=True)
                async for ch in r:
                    got.append(ch.choices[0].delta.content)
            elif p == "gemini":
                r = await genai.Client().aio.models.generate_content_stream(model="m", contents="hi")
                async for ch in r:
                    got.append(ch.text)
            else:
                async with anthropic.AsyncAnthropic().beta.messages.stream(model="m", max_tokens=5, messages=[]) as s:
                    async for t in s.text_stream:
                        got.append(t)
            check(False, f"{p} fail_mid_stream raises after the first chunk", f"no error, chunks={got}")
        except stubenv.FakeAPIError as e:
            check(len(got) == 1 and e.status_code == 503, f"{p} fail_mid_stream: one chunk then 503", f"{got} {e.status_code}")
        kind, text = await outcome(p)
        check(kind == "ok" and text == stubenv.FAKE_REPLY, f"{p} fail_mid_stream leaves non-streaming calls alone")

    # length_once: a cut-off reply with each SDK's own length signal, on the first matching call only
    await length_once_checks()

    # usage and finish metadata
    stubenv.clear_fake_ai()
    _, r = await call("openai")
    check((r.usage.prompt_tokens, r.usage.completion_tokens, r.usage.total_tokens) == (10, 5, 15), "openai usage 10/5/15")
    _, r = await call("gemini")
    check((r.usage_metadata.prompt_token_count, r.usage_metadata.candidates_token_count) == (10, 5)
          and r.candidates[0].finish_reason == "STOP", "gemini usage 10/5 and finish_reason STOP")
    _, r = await call("claude", stream=True)
    check((r.usage.input_tokens, r.usage.output_tokens, r.stop_reason) == (10, 5, "end_turn"),
          "claude stream final message usage and stop_reason")

    # openai audio transcription
    r = await openai.AsyncOpenAI().audio.transcriptions.create(model="whisper-1", file=("a.m4a", b"x"))
    check(bool(r.text), "openai audio transcription answers")
    stubenv.set_fake_ai(openai="rate_limit")
    try:
        await openai.AsyncOpenAI().audio.transcriptions.create(model="whisper-1", file=("a.m4a", b"x"))
        check(False, "openai audio honours failure kinds", "no error")
    except stubenv.FakeAPIError as e:
        check(e.status_code == 429, "openai audio honours failure kinds", e.status_code)
    stubenv.clear_fake_ai()


def resolution_checks():
    """Task 2: feature catalogue and setting resolution (environment and built-in). Pure Python.

    Restores the settings module's env snapshot, parsed-unit cache and panel cache afterwards.
    """
    from ai_providers import settings

    saved = (settings._env, dict(settings._env_units), settings._panel)
    try:
        _resolution_checks()
    finally:
        settings._env, settings._panel = saved[0], saved[2]
        settings._env_units.clear()
        settings._env_units.update(saved[1])


def _resolution_checks():
    import logging

    from ai_providers import features, settings
    from ai_providers.types import FeatureSetting, Target
    from ai_usage_models import AIFeatureType

    settings.set_panel_cache({})
    T = Target

    # catalogue
    check(features.PROVIDERS == ("openai", "gemini", "claude"), "catalogue: provider ids")
    check(set(features.FEATURES) == {
        "chat", "insight_weekly", "insight_monthly", "insight_translation", "budget_suggestion",
        "budget_auto_create", "transaction_text", "transaction_image", "transaction_audio"},
        "catalogue: feature keys", sorted(features.FEATURES))
    check(features.KNOWN_MODELS == {
        "openai": ["gpt-4o-mini", "gpt-4o"],
        "gemini": ["gemini-2.5-flash", "gemini-2.5-pro"],
        "claude": ["claude-sonnet-5-5", "claude-haiku-5-5", "claude-opus-5-5"]}, "catalogue: known models",
        features.KNOWN_MODELS)
    # F1: known models per feature: voice input on OpenAI offers only whisper-1, nothing else offers it
    km = {k: features.known_models(k) for k in features.FEATURES}
    check(km["transaction_audio"] == {"openai": ["whisper-1"], "gemini": ["gemini-2.5-flash", "gemini-2.5-pro"]},
          "known_models_per_feature: audio offers whisper-1 on openai, the gemini models on gemini", km["transaction_audio"])
    check(all(m == {p: features.KNOWN_MODELS[p] for p in features.FEATURES[k].allowed}
              for k, m in km.items() if k != "transaction_audio")
          and not any("whisper-1" in ms for k, m in km.items() if k != "transaction_audio" for ms in m.values()),
          "known_models_per_feature: other features offer their allowed providers' models, never whisper-1", km)
    km["chat"]["openai"].append("x")
    check("x" not in features.known_models("chat")["openai"], "known_models_per_feature: returns a copy")
    check(all("claude" in s.allowed for k, s in features.FEATURES.items() if k != "transaction_audio")
          and "claude" not in features.FEATURES["transaction_audio"].allowed
          and all(s.key == k for k, s in features.FEATURES.items()), "catalogue: claude allowed except audio")
    usage = {k: s.usage_type for k, s in features.FEATURES.items()}
    check(usage == {
        "chat": AIFeatureType.CHAT, "insight_weekly": AIFeatureType.WEEKLY_INSIGHT,
        "insight_monthly": AIFeatureType.MONTHLY_INSIGHT, "insight_translation": AIFeatureType.TRANSLATION,
        "budget_suggestion": AIFeatureType.BUDGET_SUGGESTION, "budget_auto_create": AIFeatureType.BUDGET_AUTO_CREATE,
        "transaction_text": AIFeatureType.TRANSACTION_TEXT_EXTRACTION,
        "transaction_image": AIFeatureType.TRANSACTION_IMAGE_EXTRACTION,
        "transaction_audio": AIFeatureType.TRANSACTION_AUDIO_TRANSCRIPTION}, "catalogue: usage types", usage)
    check(features.CLAUDE_EFFORT == {
        "chat": "low", "transaction_text": "low", "transaction_image": "low", "budget_suggestion": "low",
        "budget_auto_create": "low", "insight_weekly": "medium", "insight_monthly": "medium",
        "insight_translation": "medium"}, "catalogue: claude effort", features.CLAUDE_EFFORT)
    dm = lambda f, p, env=None: features.default_model(f, p, {} if env is None else env)  # noqa: E731
    check(dm("transaction_image", "openai") == "gpt-4o"
          and dm("transaction_audio", "openai") == "whisper-1"
          and dm("transaction_audio", "gemini") == "gemini-2.5-flash"
          and dm("chat", "openai") == "gpt-4o-mini"
          and dm("chat", "gemini") == "gemini-2.5-flash"
          and dm("chat", "claude") == "claude-sonnet-5-5",
          "catalogue: default_model per provider and exceptions")
    env = {"OPENAI_MODEL": "gpt-4o", "GEMINI_MODEL": "gemini-2.5-pro", "CLAUDE_MODEL": "claude-haiku-5-5"}
    check(dm("chat", "openai", env) == "gpt-4o" and dm("chat", "gemini", env) == "gemini-2.5-pro"
          and dm("chat", "claude", env) == "claude-haiku-5-5"
          and dm("transaction_audio", "gemini", env) == "gemini-2.5-pro"
          and dm("transaction_audio", "openai", env) == "whisper-1"
          and dm("transaction_image", "openai", {"OPENAI_MODEL": "x"}) == "gpt-4o",
          "catalogue: default_model honours OPENAI/GEMINI/CLAUDE_MODEL except the fixed exceptions")

    # env parsing
    s = settings.parse_env("chat", {"AI_CHAT_PROVIDER": "claude"})
    check(s == FeatureSetting(T("claude", "claude-sonnet-5-5"), None, "server"), "env_unit", s)
    check(settings.parse_env("chat", {"AI_CHAT_MODEL": "claude-haiku-5-5"}) is None,
          "env_model_without_provider_ignored")
    s = settings.parse_env("chat", {"AI_CHAT_PROVIDER": "claude", "AI_CHAT_MODEL": "claude-haiku-5-5"})
    check(s is not None and s.main == T("claude", "claude-haiku-5-5"), "env: model override", s)
    s = settings.parse_env("chat", {"AI_CHAT_PROVIDER": "openai", "AI_CHAT_BACKUPS": "none"})
    check(s is not None and s.backups == (), "env_backups_none", s)
    s = settings.parse_env("chat", {"AI_CHAT_PROVIDER": "openai", "AI_CHAT_BACKUPS": "gemini:gemini-2.5-pro,claude"})
    check(s is not None and s.backups == (T("gemini", "gemini-2.5-pro"), T("claude", "claude-sonnet-5-5")),
          "env_backups_list", s)

    class Capture(logging.Handler):
        def __init__(self):
            super().__init__()
            self.records = []

        def emit(self, record):
            self.records.append(record)

    cap = Capture()
    logging.getLogger().addHandler(cap)
    try:
        s = settings.parse_env("transaction_audio", {"AI_TRANSACTION_AUDIO_PROVIDER": "claude"})
        warned = [r for r in cap.records if r.levelno == logging.WARNING]
        check(s is None and warned, "env_claude_audio_rejected", f"{s} {len(warned)} warnings")
    finally:
        logging.getLogger().removeHandler(cap)
    # F6: a backups list that parses to nothing is invalid (logged, the unit ignored), not "no backups"
    for raw in (",", " , ,", ",,"):
        cap = Capture()
        logging.getLogger().addHandler(cap)
        try:
            s = settings.parse_env("chat", {"AI_CHAT_PROVIDER": "openai", "AI_CHAT_BACKUPS": raw})
            warned = [r for r in cap.records if r.levelno == logging.WARNING and "AI_CHAT_" in r.getMessage()]
        finally:
            logging.getLogger().removeHandler(cap)
        check(s is None and warned, f"env_backups_empty_list_ignored: AI_CHAT_BACKUPS={raw!r} is invalid and logged",
              f"{s} {[r.getMessage() for r in warned]}")
    s = settings.parse_env("chat", {"AI_CHAT_PROVIDER": "openai", "AI_CHAT_BACKUPS": "gemini,"})
    check(s is not None and s.backups == (T("gemini", "gemini-2.5-flash"),),
          "env_backups: a trailing comma after a real entry is still fine", s)
    check(settings.parse_env("chat", {"AI_CHAT_PROVIDER": "bogus"}) is None, "env: unknown provider skipped")
    check(settings.parse_env("chat", {}) is None, "env: nothing set gives None")

    # built-in defaults through resolve (empty environment snapshot, no panel rows)
    settings.reload_env({})
    expected = {
        "chat": ("gemini", "gemini-2.5-flash"), "insight_weekly": ("gemini", "gemini-2.5-flash"),
        "insight_monthly": ("gemini", "gemini-2.5-flash"), "insight_translation": ("gemini", "gemini-2.5-pro"),
        "budget_suggestion": ("openai", "gpt-4o-mini"), "budget_auto_create": ("openai", "gpt-4o-mini"),
        "transaction_text": ("openai", "gpt-4o-mini"), "transaction_image": ("openai", "gpt-4o"),
        "transaction_audio": ("openai", "whisper-1")}
    got = {k: settings.resolve(k) for k in features.FEATURES}
    check(all(got[k] == FeatureSetting(T(*v), None, "default") for k, v in expected.items()),
          "builtin_defaults", got)
    # resolution order: env beats built-in, panel beats env
    settings.reload_env({"AI_CHAT_PROVIDER": "claude"})
    r = settings.resolve("chat")
    check(r.main == T("claude", "claude-sonnet-5-5") and r.source == "server", "resolve: env beats built-in", r)
    panel = FeatureSetting(T("openai", "gpt-4o"), (), "panel")
    settings.set_panel_cache({"chat": panel})
    check(settings.resolve("chat") == panel and settings.resolve("insight_weekly").source == "default",
          "resolve: panel beats env, other features untouched")
    settings.set_panel_cache({})
    settings.reload_env({})

    # R5: chat and the insights follow GEMINI_MODEL / OPENAI_MODEL; the other built-ins are literal
    settings.reload_env({"GEMINI_MODEL": "gemini-2.5-pro", "OPENAI_MODEL": "gpt-4o"})
    check(all(settings.resolve(k).main == T("gemini", "gemini-2.5-pro") and settings.resolve(k).source == "default"
              for k in ("chat", "insight_weekly", "insight_monthly")),
          "builtin: chat and insights honour GEMINI_MODEL", settings.resolve("chat"))
    check(settings.resolve("budget_suggestion").main == T("openai", "gpt-4o-mini")
          and settings.resolve("budget_auto_create").main == T("openai", "gpt-4o-mini")
          and settings.resolve("transaction_text").main == T("openai", "gpt-4o-mini")
          and settings.resolve("transaction_image").main == T("openai", "gpt-4o")
          and settings.resolve("transaction_audio").main == T("openai", "whisper-1")
          and settings.resolve("insight_translation").main == T("gemini", "gemini-2.5-pro"),
          "builtin: other features keep literal models even with OPENAI_MODEL set")
    settings.reload_env({"OPENAI_MODEL": "gpt-4o"})
    check(settings.resolve("budget_suggestion").main.model == "gpt-4o-mini"
          and settings.resolve("chat").main == T("gemini", "gemini-2.5-flash"),
          "builtin: OPENAI_MODEL does not change budget_suggestion; chat stays on the gemini default")
    c = settings.chain("chat", lambda p: p == "openai")
    check(c == [T("gemini", "gemini-2.5-flash"), T("openai", "gpt-4o")], "chain: default backup picks up OPENAI_MODEL", c)

    # the environment is read lazily, after import: no snapshot yet, then AI_CHAT_PROVIDER appears in os.environ
    old = {k: os.environ.get(k) for k in ("AI_CHAT_PROVIDER", "OPENAI_API_KEY")}
    settings._env = None
    settings._env_units.clear()
    os.environ["AI_CHAT_PROVIDER"] = "claude"
    os.environ["OPENAI_API_KEY"] = "sk-e2eLAZYsnapshot123456"
    try:
        r = settings.resolve("chat")
        check(r.main.provider == "claude" and r.source == "server", "env snapshot is taken lazily on first use", r)
        check(settings._env is not None and not any("KEY" in k for k in settings._env)
              and all(k.startswith("AI_") or k.endswith("_MODEL") for k in settings._env),
              "env snapshot keeps only AI_* and *_MODEL keys (no API keys)", sorted(settings._env or {}))
    finally:
        for k, v in old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    settings.reload_env({})

    # an invalid env unit warns once per snapshot, not on every resolve
    class Count(logging.Handler):
        def __init__(self):
            super().__init__()
            self.n = 0

        def emit(self, record):
            if record.levelno == logging.WARNING:
                self.n += 1

    cnt = Count()
    logging.getLogger().addHandler(cnt)
    try:
        settings.reload_env({"AI_CHAT_PROVIDER": "bogus"})
        for _ in range(3):
            r = settings.resolve("chat")
        check(cnt.n == 1 and r.source == "default", "invalid env unit warns once per snapshot", f"{cnt.n} {r}")
        settings.reload_env({"AI_CHAT_PROVIDER": "bogus"})
        settings.resolve("chat")
        check(cnt.n == 2, "reload_env re-parses (and warns again)", cnt.n)
    finally:
        logging.getLogger().removeHandler(cnt)
    settings.set_panel_cache({})
    settings.reload_env({})

    # chains
    d = settings.resolve("chat")
    c = settings.chain("chat", lambda p: p != "claude")
    check(c == [T("gemini", "gemini-2.5-flash"), T("openai", "gpt-4o-mini")], "chain_default_backups", c)
    c = settings.chain("chat", lambda p: True)
    check(c == [T("gemini", "gemini-2.5-flash"), T("openai", "gpt-4o-mini"), T("claude", "claude-sonnet-5-5")],
          "chain: every provider configured appends claude", c)
    c = settings.chain("transaction_audio", lambda p: True)
    check(c == [T("openai", "whisper-1"), T("gemini", "gemini-2.5-flash")], "chain: audio never gets claude", c)
    settings.set_panel_cache({"chat": FeatureSetting(d.main, (), "panel")})
    c = settings.chain("chat", lambda p: True)
    check(c == [T("gemini", "gemini-2.5-flash")], "chain_no_backups", c)
    settings.set_panel_cache({"chat": FeatureSetting(d.main, (T("claude", "claude-haiku-5-5"),), "panel")})
    c = settings.chain("chat", lambda p: False)
    check(c == [d.main, T("claude", "claude-haiku-5-5")], "chain: explicit backups kept even if unconfigured", c)
    settings.set_panel_cache({})

    # validation
    ok = FeatureSetting(T("openai", "gpt-4o-mini"), (T("gemini", "gemini-2.5-flash"),), "panel")
    check(settings.validate("chat", ok) == [], "validate: a good setting has no errors", settings.validate("chat", ok))
    dup_main = FeatureSetting(T("openai", "gpt-4o-mini"), (T("openai", "gpt-4o-mini"),), "panel")
    e = settings.validate("chat", dup_main)
    check(len(e) == 1, "validate_duplicates: backup equal to main", e)
    dup_backup = FeatureSetting(T("openai", "gpt-4o-mini"),
                                (T("gemini", "gemini-2.5-flash"), T("gemini", "gemini-2.5-flash")), "panel")
    e = settings.validate("chat", dup_backup)
    check(len(e) == 1, "validate_duplicates: repeated backup", e)
    e = settings.validate("chat", FeatureSetting(T("nope", "x"), None, "panel"))
    check(len(e) == 1, "validate: unknown provider", e)
    e = settings.validate("transaction_audio", FeatureSetting(T("claude", "claude-sonnet-5-5"), None, "panel"))
    check(len(e) == 1, "validate: provider not allowed for the feature", e)
    e = settings.validate("chat", FeatureSetting(T("openai", ""), None, "panel"))
    check(len(e) == 1, "validate: empty model", e)
    e = settings.validate("transaction_audio", FeatureSetting(T("openai", "whisper-1"), (T("claude", "claude-haiku-5-5"),), "panel"))
    check(len(e) == 1, "validate: backup provider not allowed", e)

    # F1: OpenAI speech-to-text models only for voice input, and voice input on OpenAI only with one of them
    V = lambda f, main, *backups: settings.validate(f, FeatureSetting(T(*main), tuple(T(*b) for b in backups), "panel"))  # noqa: E731
    for model in ("whisper-1", "Whisper-2", "gpt-4o-mini-transcribe", "gpt-4o-transcribe"):
        e = V("chat", ("openai", model))
        check(len(e) == 1 and "voice input" in e[0], f"validate_audio_model_elsewhere: chat main openai {model} rejected", e)
    e = V("budget_suggestion", ("gemini", "gemini-2.5-flash"), ("openai", "whisper-1"))
    check(len(e) == 1 and e[0].startswith("backup 1"), "validate_audio_model_elsewhere: a whisper backup is rejected too", e)
    for model in ("gpt-4o-mini", "gpt-4o", "o4-mini"):
        e = V("transaction_audio", ("openai", model))
        check(len(e) == 1 and "speech-to-text" in e[0], f"validate_audio_needs_stt: audio main openai {model} rejected", e)
    e = V("transaction_audio", ("gemini", "gemini-2.5-flash"), ("openai", "gpt-4o"))
    check(len(e) == 1 and e[0].startswith("backup 1"), "validate_audio_needs_stt: an openai chat model as audio backup is rejected", e)
    for main in (("openai", "whisper-1"), ("openai", "gpt-4o-transcribe"), ("openai", "gpt-4o-mini-transcribe"),
                 ("gemini", "gemini-2.5-flash"), ("gemini", "gemini-live-whatever")):
        e = V("transaction_audio", main)
        check(e == [], f"validate_audio_ok: audio main {main[0]} {main[1]} is accepted", e)
    check(V("chat", ("openai", "gpt-5-mini")) == [] and V("chat", ("gemini", "gemini-2.5-pro")) == [],
          "validate: ordinary chat models (typed under Other) are still accepted")

    # F7: a model name that looks like an API key is rejected, and the message does not repeat it
    for secret in ("sk-proj-abcdef1234567890", "sk-ant-api03-abcdefgh", "AIzaSyAbcdefghijk123"):
        e = V("chat", ("openai", secret))
        check(len(e) == 1 and "API key" in e[0] and secret not in " ".join(e),
              f"validate_key_like_model: {secret[:6]}... rejected without echoing it", e)
        e = V("chat", ("gemini", "gemini-2.5-flash"), ("openai", secret), ("openai", secret))
        check(e and all(secret not in m for m in e) and any("API key" in m for m in e),
              f"validate_key_like_model: {secret[:6]}... as a repeated backup never appears in a message", e)
    s = settings.parse_env("chat", {"AI_CHAT_PROVIDER": "openai", "AI_CHAT_MODEL": "sk-proj-abcdef1234567890"})
    check(s is None, "validate_key_like_model: an env model that looks like a key is ignored", s)


def migration_checks():
    """Task 3: the Alembic revision created the tables/columns and relaxed the insights CHECK."""
    import psycopg

    dsn = os.environ["DATABASE_URL"]
    try:
        with psycopg.connect(dsn) as conn:  # not autocommit: everything below is rolled back
            have = {r[0] for r in conn.execute(
                "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'")}
            cols = {r[0] for r in conn.execute(
                "SELECT column_name FROM information_schema.columns WHERE table_name = 'ai_usage'")}
            ok = {"ai_feature_settings", "ai_provider_status"} <= have and "fallback_from" in cols
            check(ok, "migration_applied: new tables and ai_usage.fallback_from exist", f"{sorted(have)} {sorted(cols)}")
            try:
                conn.execute("INSERT INTO users (id, name, email, password) VALUES ('t3-user','t','t3@x.test','x')")
                conn.execute("INSERT INTO insights (id, user_id, insight_type, ai_provider, content) "
                             "VALUES ('t3-ins','t3-user','weekly','claude','hello')")
                check(True, "migration_applied: insights accept ai_provider='claude'")
            except Exception as e:  # noqa: BLE001
                check(False, "migration_applied: insights accept ai_provider='claude'", repr(e))
            conn.rollback()
            for provider, expect_ok in (("claude", True), ("bogus", False)):
                try:
                    conn.execute("INSERT INTO users (id, name, email, password) VALUES ('t3-user','t','t3@x.test','x')")
                    conn.execute("INSERT INTO ai_usage (id, user_id, feature_type, provider, model_name, fallback_from) "
                                 "VALUES ('t3-use','t3-user','chat','openai','m', %s)", (provider,))
                    got = True
                except Exception:  # noqa: BLE001
                    got = False
                check(got == expect_ok, f"migration_applied: ai_usage.fallback_from {provider!r} {'accepted' if expect_ok else 'rejected'}")
                conn.rollback()
    except Exception as e:  # noqa: BLE001
        check(False, "migration_applied", repr(e))


async def panel_checks():
    """Task 3: the admin-panel layer (database rows -> cache -> resolve). Restores the panel cache and rows."""
    from ai_providers import settings
    from ai_providers.types import FeatureSetting, Target
    from sql import ai_settings

    T = Target
    saved_env = (settings._env, dict(settings._env_units), settings._panel)
    try:
        settings.set_panel_cache({})
        settings.reload_env({"AI_CHAT_PROVIDER": "claude"})
        await settings.clear_panel("chat")
        await settings.save_panel("chat", FeatureSetting(T("openai", "gpt-4o"), (), "panel"), "t@x")
        r = settings.resolve("chat")
        check(r.main == T("openai", "gpt-4o") and r.backups == () and r.source == "panel",
              "panel_wins_over_env", r)
        rows = await ai_settings.list_feature_settings()
        row = next((x for x in rows if x["feature"] == "chat"), None)
        check(row is not None and row["main_provider"] == "openai" and row["updated_by"] == "t@x"
              and row["backups"] == [], "panel: save_panel upserts the row", row)

        await settings.clear_panel("chat")
        r = settings.resolve("chat")
        check(r.source == "server" and r.main.provider == "claude", "clear_panel_falls_back_to_env", r)
        check(not any(x["feature"] == "chat" for x in await ai_settings.list_feature_settings()),
              "panel: clear_panel deletes the row")

        # None (default backups) and () (no backups) and a list stay distinct through save and reload
        for backups in (None, (), (T("gemini", "gemini-2.5-pro"),)):
            await settings.save_panel("chat", FeatureSetting(T("openai", "gpt-4o"), backups, "panel"), "t@x")
            settings.set_panel_cache({})
            await settings.load_panel()
            got = settings.resolve("chat")
            check(got.source == "panel" and got.backups == backups, f"backups_null_vs_empty_roundtrip: {backups!r}", got)

        # save_panel validates and leaves the previous setting alone
        try:
            await settings.save_panel("chat", FeatureSetting(T("openai", "gpt-4o"), (T("openai", "gpt-4o"),), "panel"), "t@x")
            check(False, "panel: invalid setting raises ValueError", "no error")
        except ValueError as e:
            check(isinstance(e.args[0], list) and len(e.args[0]) == 1, "panel: invalid setting raises ValueError(list)", e.args)
        check(settings.resolve("chat").backups == (T("gemini", "gemini-2.5-pro"),),
              "panel: a rejected save keeps the previous setting")

        # load_panel skips (and logs) invalid rows
        await ai_settings.upsert_feature_setting("transaction_audio", "claude", "claude-sonnet-5-5", None, "t@x")
        await ai_settings.upsert_feature_setting("chat", "openai", "gpt-4o", [{"provider": "bogus", "model": "x"}], "t@x")
        settings.set_panel_cache({})
        await settings.load_panel()
        check("transaction_audio" not in settings._panel and settings.resolve("transaction_audio").source != "panel",
              "panel: load_panel skips a row that fails validation")
        check(settings.resolve("chat").source != "panel", "panel: load_panel skips a row with a bad backup")
        await settings.clear_panel("transaction_audio")
        await settings.clear_panel("chat")

        # warnings
        s = FeatureSetting(T("claude", "claude-sonnet-5-5"), None, "panel")
        w = settings.setting_warnings(s, lambda p: p != "claude")
        check(len(w) == 1 and "claude" in w[0].lower(), "setting_warnings: unconfigured main warns", w)
        check(settings.setting_warnings(s, lambda p: True) == [], "setting_warnings: configured main is clean")

        # provider status rows
        from datetime import datetime, timezone
        now = datetime.now(timezone.utc)
        from sql.db import execute as _execute
        from sql.tables import ai_provider_status as _status_table
        await _execute(_status_table.delete())  # a clean slate: the stub server's own runs leave status rows behind
        await ai_settings.record_provider_error("claude", "boom", now)
        await ai_settings.record_provider_success("claude", now)
        await ai_settings.record_provider_success("gemini", now)
        st = await ai_settings.get_provider_status()
        check(st["claude"]["last_error"] == "boom" and st["claude"]["last_success_at"] is not None
              and st["gemini"]["last_error"] is None and st["gemini"]["last_success_at"] is not None,
              "status: error and success are stored independently per provider", st)
        await ai_settings.record_provider_success("openai", now)
        check(await ai_settings.delete_feature_setting("nope") is False, "delete_feature_setting: false when absent")

        # the refresh loop is an asyncio task that picks up changes made behind the cache's back
        settings.set_panel_cache({})
        await ai_settings.upsert_feature_setting("chat", "openai", "gpt-4o", None, "t@x")
        task = settings.start_refresh_loop(interval=0.2)
        try:
            await asyncio.sleep(0.8)
            check(settings.resolve("chat").source == "panel", "panel: refresh loop reloads the cache")
        finally:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass
    finally:
        async def cleanup():
            for f in ("chat", "transaction_audio"):
                await ai_settings.delete_feature_setting(f)
            from sql.db import execute
            from sql.tables import ai_provider_status
            await execute(ai_provider_status.delete())
        try:
            await cleanup()
        finally:
            settings._env, settings._panel = saved_env[0], saved_env[2]
            settings._env_units.clear()
            settings._env_units.update(saved_env[1])


def error_checks():
    """Task 4: error classification, redaction and the insights wrappers. Pure Python."""
    import httpx

    from ai_providers import errors
    from ai_providers.errors import AllProvidersFailed, ProviderFailure, classify, redact

    # each fake failure kind maps to its failure kind (claude differs for billing and server statuses)
    stubenv.clear_fake_ai()
    expected = {"billing": "billing", "auth": "auth", "rate_limit": "rate_limit", "server": "server",
                "model_not_found": "model_not_found", "echo_key": "auth", "bad_request": None}
    for kind_name, want in expected.items():
        for p in ("openai", "gemini", "claude"):
            try:
                stubenv._raise_for(p, kind_name)
                got = "no error raised"
            except stubenv.FakeAPIError as e:
                f = classify(e, p, "m")
                got = None if f is None else f.kind
                if f is not None and (f.provider, f.model) != (p, "m"):
                    got = f"wrong target {f.provider}/{f.model}"
            check(got == want, f"classify_table: {p} {kind_name} -> {want}", got)
    check(classify(TimeoutError(), "openai", "m").kind == "timeout", "classify_table: TimeoutError -> timeout")
    check(classify(asyncio.TimeoutError(), "openai", "m").kind == "timeout", "classify_table: asyncio.TimeoutError -> timeout")
    check(classify(ValueError("x"), "openai", "m") is None, "classify_table: ValueError -> None")
    check(classify(Exception("boom"), "openai", "m") is None, "classify_table: plain Exception -> None")
    check(classify(stubenv.FakeAPIError(422, None, "unprocessable"), "openai", "m") is None, "classify_table: 422 -> None")

    # SDK timeout / connection errors (all three SDKs) and httpx network errors are timeouts
    req = httpx.Request("POST", "http://x.test")
    sdk = [openai.APITimeoutError(request=req), openai.APIConnectionError(request=req),
           anthropic.APITimeoutError(request=req), anthropic.APIConnectionError(request=req),
           httpx.ReadTimeout("t"), httpx.ConnectError("c")]
    got = [getattr(classify(e, "x", "m"), "kind", None) for e in sdk]
    check(got == ["timeout"] * len(sdk), "classify_sdk_timeouts: openai/anthropic/httpx network errors -> timeout", got)

    # real SDK status errors
    resp = httpx.Response(429, request=req)
    check(classify(openai.RateLimitError("slow down", response=resp, body=None), "openai", "m").kind == "rate_limit",
          "classify_sdk_status: openai.RateLimitError -> rate_limit")
    resp = httpx.Response(401, request=req)
    check(classify(anthropic.AuthenticationError("bad key", response=resp, body=None), "claude", "m").kind == "auth",
          "classify_sdk_status: anthropic.AuthenticationError -> auth")
    resp = httpx.Response(529, request=req)
    check(classify(anthropic.APIStatusError("overloaded", response=resp, body=None), "claude", "m").kind == "server",
          "classify_sdk_status: anthropic 529 -> server")
    from google.genai import errors as genai_errors
    e = genai_errors.ClientError(429, {"error": {"code": 429, "message": "quota", "status": "RESOURCE_EXHAUSTED"}})
    check(classify(e, "gemini", "m").kind == "rate_limit", "classify_sdk_status: genai 429 RESOURCE_EXHAUSTED -> rate_limit")
    e = genai_errors.ServerError(503, {"error": {"code": 503, "message": "down", "status": "UNAVAILABLE"}})
    check(classify(e, "gemini", "m").kind == "server", "classify_sdk_status: genai 503 -> server")

    # billing is recognised before the generic 400 rule and before rate_limit
    f = classify(stubenv.FakeAPIError(400, None, "Your credit balance is too low to access the Anthropic API."), "claude", "m")
    check(f is not None and f.kind == "billing", "classify_claude_billing_400", f)
    f = classify(stubenv.FakeAPIError(429, "insufficient_quota", "You exceeded your current quota"), "openai", "m")
    check(f is not None and f.kind == "billing", "classify: openai 429 insufficient_quota is billing, not rate_limit", f)
    f = classify(stubenv.FakeAPIError(402, "RESOURCE_EXHAUSTED", "prepayment credits are depleted"), "gemini", "m")
    check(f is not None and f.kind == "billing", "classify: gemini 402 RESOURCE_EXHAUSTED is billing", f)
    f = classify(stubenv.FakeAPIError(400, None, "The model `gpt-5x` does not exist"), "openai", "gpt-5x")
    check(f is not None and f.kind == "model_not_found", "classify: 400 'model ... does not exist' -> model_not_found", f)

    # R7: billing needs an explicit signal; a plain 429 is a rate limit even when it mentions quota and billing
    gemini_429 = ("You exceeded your current quota, please check your plan and billing details. "
                  "For more information on this error, head to: https://ai.google.dev/gemini-api/docs/rate-limits.")
    e = genai_errors.ClientError(429, {"error": {"code": 429, "message": gemini_429, "status": "RESOURCE_EXHAUSTED"}})
    f = classify(e, "gemini", "gemini-2.5-flash")
    check(f is not None and f.kind == "rate_limit", "classify_gemini_429_quota_text_is_rate_limit", f)
    f = classify(stubenv.FakeAPIError(429, None, gemini_429), "gemini", "m")
    check(f is not None and f.kind == "rate_limit", "classify: 429 mentioning quota and billing without a code is rate_limit", f)
    f = classify(stubenv.FakeAPIError(429, "insufficient_quota", gemini_429), "openai", "m")
    check(f is not None and f.kind == "billing", "classify_openai_429_insufficient_quota_is_billing", f)
    f = classify(stubenv.FakeAPIError(402, None, "payment required"), "gemini", "m")
    check(f is not None and f.kind == "billing", "classify: 402 alone is billing", f)
    f = classify(genai_errors.ClientError(429, {"error": {"code": 429, "message": "Resource has been exhausted (e.g. check quota).",
                                                          "status": "RESOURCE_EXHAUSTED"}}), "gemini", "m")
    check(f is not None and f.kind == "rate_limit", "classify: 429 without an explicit billing signal is rate_limit", f)

    # F4: Gemini reports depleted prepaid credits as a 429; that is billing (someone must top up), not a rate limit
    for msg in ("Your prepayment credits are depleted. Please go to AI Studio to manage your project and billing.",
                "prepayment credits depleted", "Your project's credits have been depleted",
                "This project needs prepay credits to continue"):
        e = genai_errors.ClientError(429, {"error": {"code": 429, "message": msg, "status": "RESOURCE_EXHAUSTED"}})
        f = classify(e, "gemini", "gemini-2.5-flash")
        check(f is not None and f.kind == "billing", f"classify_gemini_depleted_credits_429_is_billing: {msg[:30]}", f)
        f = classify(stubenv.FakeAPIError(429, None, msg), "gemini", "m")
        check(f is not None and f.kind == "billing", f"classify: a plain 429 with depleted credits is billing: {msg[:30]}", f)
    import inspect
    check("402 RESOURCE_EXHAUSTED" not in inspect.getsource(errors), "errors.py: no stale '402' Gemini comment")

    # F1: a 400 that is about the model (OpenAI's structured error: param "model", or code
    # unsupported_parameter / model_not_found) is specific to the provider+model pair: model_not_found
    def oai_400(body):
        return openai.BadRequestError(f"Error code: 400 - {body}", response=httpx.Response(400, request=req), body=body)

    cases = {
        "openai Invalid model (param model)": ({"message": "Invalid model gpt-4o-mini. The model argument should be left "
                                                           "blank.", "type": "invalid_request_error", "param": "model",
                                                "code": None}, "model_not_found"),
        "openai unsupported_parameter max_tokens": ({"message": "Unsupported parameter: 'max_tokens' is not supported with "
                                                                "this model. Use 'max_completion_tokens' instead.",
                                                     "type": "invalid_request_error", "param": "max_tokens",
                                                     "code": "unsupported_parameter"}, "model_not_found"),
        "openai 400 code model_not_found": ({"message": "That model is not available here", "type": "invalid_request_error",
                                             "param": None, "code": "model_not_found"}, "model_not_found"),
        "openai unsupported_value temperature": ({"message": "Unsupported value: 'temperature' does not support 0.3 "
                                                             "with this model. Only the default (1) value is supported.",
                                                  "type": "invalid_request_error", "param": "temperature",
                                                  "code": "unsupported_value"}, "model_not_found"),
        "openai unsupported_value top_p": ({"message": "Unsupported value: 'top_p'", "type": "invalid_request_error",
                                            "param": "top_p", "code": "unsupported_value"}, "model_not_found"),
        "openai unsupported_value presence_penalty": ({"message": "Unsupported value: 'presence_penalty'",
                                                       "type": "invalid_request_error", "param": "presence_penalty",
                                                       "code": "unsupported_value"}, "model_not_found"),
        "openai unsupported_value on a non-sampling param stays request-level": (
            {"message": "Unsupported value: 'messages[0].role'", "type": "invalid_request_error",
             "param": "messages[0].role", "code": "unsupported_value"}, None),
        "openai 400 bad messages stays request-level": ({"message": "Invalid 'messages[0].content'", "type":
                                                         "invalid_request_error", "param": "messages[0].content",
                                                         "code": "invalid_value"}, None),
        "openai 400 bad image stays request-level": ({"message": "You uploaded an unsupported image.", "type":
                                                      "invalid_request_error", "param": None, "code": "invalid_image_format"},
                                                     None),
    }
    for label, (body, want) in cases.items():
        e = oai_400(body)
        f = classify(e, "openai", "gpt-4o-mini")
        check((f.kind if f else None) == want and (f is None or (f.provider, f.model) == ("openai", "gpt-4o-mini")),
              f"classify_model_level_400: {label} -> {want}", (e.code, e.param, f))
    f = classify(stubenv.FakeAPIError(400, None, "Invalid model.", param="model"), "openai", "whisper-x")
    check(f is not None and f.kind == "model_not_found", "classify_model_level_400: fake invalid_model -> model_not_found", f)
    f = classify(stubenv.FakeAPIError(422, "unsupported_parameter", "x", param="model"), "openai", "m")
    check(f is None, "classify_model_level_400: only a 400 qualifies (422 stays request-level)", f)
    # Anthropic and Gemini report an unknown model as a 404 (not_found_error / NOT_FOUND): already model_not_found
    e = anthropic.NotFoundError("model: claude-typo", response=httpx.Response(404, request=req),
                                body={"type": "error", "error": {"type": "not_found_error", "message": "model: claude-typo"}})
    check(classify(e, "claude", "claude-typo").kind == "model_not_found", "classify: anthropic 404 not_found_error (model) -> model_not_found")
    e = genai_errors.ClientError(404, {"error": {"code": 404, "message": "models/gemini-typo is not found for API version "
                                                                         "v1beta", "status": "NOT_FOUND"}})
    check(classify(e, "gemini", "gemini-typo").kind == "model_not_found", "classify: genai 404 NOT_FOUND (model) -> model_not_found")
    f = classify(stubenv.FakeAPIError(400, None, "Please check your billing details"), "x", "m")
    check(f is not None and f.kind == "billing", "classify: non-429 billing wording is still billing", f)

    # R7: Gemini reports bad/expired keys as 400 INVALID_ARGUMENT
    for msg in ("API key not valid. Please pass a valid API key.", "API key expired. Please renew the API key.",
                "reason: API_KEY_INVALID"):
        e = genai_errors.ClientError(400, {"error": {"code": 400, "message": msg, "status": "INVALID_ARGUMENT"}})
        f = classify(e, "gemini", "m")
        check(f is not None and f.kind == "auth", f"classify_gemini_bad_key_400: {msg[:24]}", f)
    check(classify(stubenv.FakeAPIError(400, None, "invalid image"), "gemini", "m") is None,
          "classify: an ordinary 400 is still None")

    # plain statuses
    for status, want in ((403, "auth"), (401, "auth"), (402, "billing"), (404, "model_not_found"), (408, "timeout"),
                         (500, "server"), (529, "server"), (400, None), (422, None)):
        f = classify(stubenv.FakeAPIError(status, None, "something"), "openai", "m")
        check((f.kind if f else None) == want, f"classify_status: bare {status} -> {want}", f)

    # the cause chain is walked
    try:
        try:
            raise stubenv.FakeAPIError(429, "rate_limit_exceeded", "Rate limit reached")
        except stubenv.FakeAPIError as inner:
            raise RuntimeError("wrapper") from inner
    except RuntimeError as outer:
        f = classify(outer, "openai", "m")
        check(f is not None and f.kind == "rate_limit", "classify: walks __cause__", f)

    # redaction
    for secret in ("sk-e2eSECRETabcdef123", "AIzaSyAbcdefghijk123", "sk-ant-api03-abcdef", "sk-proj-abcd1234"):
        out = redact(f"Incorrect API key provided: {secret}. You can find your key at https://x.test")
        check(secret not in out and "[redacted]" in out and "sk-e2e" not in out and "AIza" not in out
              and "sk-ant" not in out, f"redact_keys: {secret[:6]}...", out)
    check(redact("sk-proj-********************abcd rest").strip() == "[redacted] rest",
          "redact_keys: OpenAI masked key form leaves no tail", redact("sk-proj-********************abcd rest"))
    long = redact("x" * 1000)
    check(len(long) <= 300, "redact: truncated to 300 characters", len(long))
    check(redact("a" * 290 + " sk-e2eSECRETabcdef123").count("sk-") == 0,
          "redact: a key near the truncation point is redacted before truncating")
    check(redact("plain message") == "plain message", "redact: leaves ordinary text alone")
    # F8: words that merely contain "sk-" or "AIza" are left alone; keys after punctuation are still caught
    for text in ("risk-assessment failed for task-1234567890", "the disk-cleanup-service and desk-booking-tool",
                 "MAIzaBCDEFGHIJKLMNOP is not a key"):
        check(redact(text) == text, f"redact_word_boundary: {text[:24]!r} is unchanged", redact(text))
    for text in ("key=sk-proj-abcdef123456 end", "key:sk-ant-api03-abcdefgh end", "(AIzaSyAbcdefghijk123) end",
                 "_sk-proj-abcdef123456 end", "\"sk-proj-********abcd\" end"):
        out = redact(text)
        check("[redacted]" in out and "abcdef1" not in out and "AIzaSy" not in out and "abcdefgh" not in out,
              f"redact_word_boundary: a key after punctuation is still redacted: {text[:12]!r}", out)
    f = classify(stubenv.FakeAPIError(401, "invalid_api_key", "Incorrect API key provided: sk-e2eSECRETabcdef123"), "openai", "m")
    check("sk-e2e" not in f.message and "[redacted]" in f.message, "classify: failure message is redacted", f.message)

    # AllProvidersFailed
    fs = [ProviderFailure("openai", "a", "rate_limit", ""), ProviderFailure("gemini", "b", "rate_limit", "")]
    check(AllProvidersFailed(fs).all_rate_limited and AllProvidersFailed(fs).failures == fs,
          "AllProvidersFailed: all_rate_limited when every failure is rate_limit")
    check(not AllProvidersFailed(fs + [ProviderFailure("claude", "c", "auth", "")]).all_rate_limited
          and not AllProvidersFailed([]).all_rate_limited, "AllProvidersFailed: mixed or empty is not all_rate_limited")
    check(issubclass(errors.UnusableAnswer, Exception) and "unusable" in errors.KINDS and len(errors.KINDS) == 9,
          "errors: KINDS and UnusableAnswer")

    # insights_service keeps its public helpers, now backed by errors.py
    import insights_service as ins
    billing = RuntimeError("Your credit balance is too low")
    check(ins.is_billing_error(billing) and not ins.is_rate_limit_error(billing),
          "insights_wrappers: billing wins over rate limit")
    check(ins.is_rate_limit_error(stubenv.FakeAPIError(429, None, "x")), "insights_wrappers: 429 is a rate limit")
    wrapped = RuntimeError("outer")
    wrapped.__cause__ = ins.InsightAIError("inner", rate_limited=True)
    check(ins.is_rate_limit_error(wrapped), "insights_wrappers: InsightAIError(rate_limited) found through __cause__")
    check(not ins.is_rate_limit_error(ins.InsightAIError("inner", rate_limited=False)) and not ins.is_rate_limit_error(None),
          "insights_wrappers: unrelated errors and None are not rate limits")
    check(ins.is_rate_limit_error(Exception("Error 429 too many requests")) and ins.is_rate_limit_error(Exception("RESOURCE_EXHAUSTED")),
          "insights_wrappers: text patterns still match")
    check(ins._RATE_LIMIT_TEXT.search("rate limit") and ins._BILLING_TEXT.search("insufficient_quota"),
          "insights_wrappers: _RATE_LIMIT_TEXT and _BILLING_TEXT still exported")


async def health_checks():
    """Task 4: cool-off state. Resets health after itself so later checks start clean."""
    from ai_providers import health
    from ai_providers.errors import ProviderFailure
    from ai_providers.types import Target

    PF = ProviderFailure
    T = Target
    haiku, sonnet = T("claude", "claude-haiku-5-5"), T("claude", "claude-sonnet-5-5")
    typo = T("claude", "claude-typo")
    t0 = 1_000_000.0
    health.reset()
    try:
        check(health.is_available(typo, t0) and health.is_available(T("openai", "gpt-4o"), t0), "health: starts available")

        # model_not_found cools only that provider+model
        health.mark_failure(PF("claude", "claude-typo", "model_not_found", ""), t0)
        check(not health.is_available(typo, t0), "cooloff_model_scoped: the typo'd pair is unavailable")
        check(health.is_available(sonnet, t0) and health.is_available(T("openai", "gpt-4o"), t0),
              "cooloff_model_scoped: other claude models and providers stay available")
        check(not health.is_available(typo, t0 + 299) and health.is_available(typo, t0 + 301)
              and health.is_available(sonnet, t0 + 301), "cooloff_model_scoped: both available at +301 s")
        snap = health.snapshot(t0 + 10)
        check(snap["claude"]["cooling_until"] is None and list(snap["claude"]["cooling_models"]) == ["claude-typo"]
              and abs(snap["claude"]["cooling_models"]["claude-typo"] - (t0 + 300)) < 1e-6
              and snap["openai"] == {"cooling_until": None, "cooling_models": {}},
              "health_snapshot: lists the cooled model and no provider cooling", snap)
        snap = health.snapshot(t0 + 301)
        check(snap["claude"]["cooling_models"] == {}, "health_snapshot: expired model cooling is not listed", snap)

        # billing/auth/not_configured cool the whole provider for 300 s
        for kind in ("billing", "auth", "not_configured"):
            health.reset()
            health.mark_failure(PF("claude", "claude-sonnet-5-5", kind, ""), t0)
            check(not health.is_available(sonnet, t0) and not health.is_available(haiku, t0)
                  and not health.is_available(typo, t0 + 299)
                  and health.is_available(T("openai", "gpt-4o"), t0),
                  f"cooloff_provider_scoped: {kind} makes every claude model unavailable", kind)
            check(health.is_available(sonnet, t0 + 301) and health.is_available(haiku, t0 + 301),
                  f"cooloff_provider_scoped: {kind} clears after 300 s")
        health.reset()
        health.mark_failure(PF("claude", "claude-sonnet-5-5", "billing", ""), t0)
        snap = health.snapshot(t0 + 5)
        check(abs(snap["claude"]["cooling_until"] - (t0 + 300)) < 1e-6, "health_snapshot: provider cooling_until", snap)

        # R2: a success proves the provider works again
        health.mark_success(T("claude", "claude-sonnet-5-5"))
        check(all(health.is_available(m, t0 + 1) for m in (sonnet, haiku, typo)),
              "mark_success_clears_provider_cooling: every claude model is available again")
        health.mark_failure(PF("claude", "claude-typo", "model_not_found", ""), t0)
        health.mark_failure(PF("claude", "claude-haiku-5-5", "model_not_found", ""), t0)
        health.mark_success(typo)
        check(health.is_available(typo, t0 + 1) and not health.is_available(haiku, t0 + 1),
              "mark_success_clears_pair_cooling: only the succeeding pair is cleared")

        # rate_limit: 60 s on the pair
        health.reset()
        health.mark_failure(PF("openai", "gpt-4o", "rate_limit", ""), t0)
        check(not health.is_available(T("openai", "gpt-4o"), t0 + 59) and health.is_available(T("openai", "gpt-4o"), t0 + 61)
              and health.is_available(T("openai", "gpt-4o-mini"), t0), "rate_limit_60s: unavailable until +60 s, other models fine")

        # a shorter cool-off never shortens a longer one for the same key
        health.reset()
        health.mark_failure(PF("openai", "gpt-4o", "model_not_found", ""), t0)
        health.mark_failure(PF("openai", "gpt-4o", "rate_limit", ""), t0 + 10)
        check(not health.is_available(T("openai", "gpt-4o"), t0 + 200), "cooloff_max: rate_limit does not shorten model_not_found")
        health.reset()
        health.mark_failure(PF("openai", "gpt-4o", "rate_limit", ""), t0)
        health.mark_failure(PF("openai", "gpt-4o", "rate_limit", ""), t0 + 30)
        check(not health.is_available(T("openai", "gpt-4o"), t0 + 80) and health.is_available(T("openai", "gpt-4o"), t0 + 91),
              "cooloff_max: a later rate_limit extends the cool-off")
        health.reset()
        health.mark_failure(PF("openai", "gpt-4o", "billing", ""), t0 + 100)
        health.mark_failure(PF("openai", "gpt-4o", "auth", ""), t0)
        check(not health.is_available(T("openai", "gpt-4o"), t0 + 350), "cooloff_max: an earlier-timestamped provider cool-off does not shorten")

        # nothing for refusal / unusable / a single timeout
        health.reset()
        for kind in ("refusal", "unusable", "timeout"):
            health.mark_failure(PF("gemini", "gemini-2.5-flash", kind, ""), t0)
        check(health.is_available(T("gemini", "gemini-2.5-flash"), t0), "health: refusal, unusable and a single timeout never cool off")

        # server needs two in a row
        health.reset()
        g = T("gemini", "gemini-2.5-flash")
        health.mark_failure(PF("gemini", "gemini-2.5-flash", "server", ""), t0)
        check(health.is_available(g, t0), "server_needs_two: one server failure leaves the target available")
        health.mark_failure(PF("gemini", "gemini-2.5-flash", "server", ""), t0 + 1)
        check(not health.is_available(g, t0 + 2) and not health.is_available(T("gemini", "gemini-2.5-pro"), t0 + 2)
              and health.is_available(g, t0 + 302), "server_needs_two: two consecutive mark the provider unavailable for 300 s")
        health.reset()
        health.mark_failure(PF("gemini", "gemini-2.5-flash", "server", ""), t0)
        health.mark_success(g)
        health.mark_failure(PF("gemini", "gemini-2.5-flash", "server", ""), t0 + 1)
        check(health.is_available(g, t0 + 2), "server_needs_two: a success in between resets the counter")
        health.reset()
        for i in range(2):
            health.mark_failure(PF("gemini", "gemini-2.5-flash", "server", ""), t0)
        health.mark_failure(PF("gemini", "gemini-2.5-flash", "server", ""), t0 + 400)
        check(health.is_available(g, t0 + 401), "server_needs_two: the counter restarts after a provider cool-off")

        # F2: timeouts count in the same streak as server errors: two in a row cool the whole provider for 300 s
        health.reset()
        health.mark_failure(PF("gemini", "gemini-2.5-flash", "timeout", ""), t0)
        check(health.is_available(g, t0 + 1), "timeouts_cool_provider: one timeout leaves the target available")
        health.mark_failure(PF("gemini", "gemini-2.5-pro", "timeout", ""), t0 + 1)
        check(not health.is_available(g, t0 + 2) and not health.is_available(T("gemini", "gemini-2.5-pro"), t0 + 2)
              and health.is_available(T("openai", "gpt-4o"), t0 + 2)
              and not health.is_available(g, t0 + 300) and health.is_available(g, t0 + 302),
              "timeouts_cool_provider: two timeouts in a row cool every gemini model for 300 s")
        snap = health.snapshot(t0 + 2)
        check(snap["gemini"]["cooling_until"] is not None and abs(snap["gemini"]["cooling_until"] - (t0 + 301)) < 1e-6,
              "timeouts_cool_provider: the status snapshot shows the provider cooling", snap["gemini"])
        health.mark_success(g)
        check(health.is_available(g, t0 + 3) and health.is_available(T("gemini", "gemini-2.5-pro"), t0 + 3),
              "timeouts_cool_provider: a success clears the cool-off")
        health.mark_failure(PF("gemini", "gemini-2.5-flash", "timeout", ""), t0 + 4)
        check(health.is_available(g, t0 + 5), "timeouts_cool_provider: after a success the streak starts again from zero")
        health.reset()
        health.mark_failure(PF("gemini", "gemini-2.5-flash", "server", ""), t0)
        health.mark_failure(PF("gemini", "gemini-2.5-flash", "timeout", ""), t0 + 1)
        check(not health.is_available(g, t0 + 2), "timeouts_cool_provider: a server error then a timeout also cool it")
        health.reset()
        health.mark_failure(PF("gemini", "gemini-2.5-flash", "timeout", ""), t0)
        health.mark_success(g)
        health.mark_failure(PF("gemini", "gemini-2.5-flash", "timeout", ""), t0 + 1)
        check(health.is_available(g, t0 + 2), "timeouts_cool_provider: a success in between resets the streak")

        # default clock
        health.reset()
        health.mark_failure(PF("openai", "gpt-4o", "billing", ""))
        check(not health.is_available(T("openai", "gpt-4o")), "health: now defaults to the wall clock")

        # persistence writes to ai_provider_status and swallows database errors
        from sql import ai_settings
        health.reset()
        await health.persist_failure(PF("claude", "claude-sonnet-5-5", "auth", "Invalid key [redacted]"))
        await health.persist_success(T("gemini", "gemini-2.5-flash"))
        st = await ai_settings.get_provider_status()
        check(st["claude"]["last_error"] == "Invalid key [redacted]" and st["claude"]["last_error_at"] is not None
              and st["gemini"]["last_success_at"] is not None, "persist: failure and success reach ai_provider_status", st)
        await health.persist_failure(PF("claude", "m", "auth", "Incorrect API key provided: sk-e2eSECRETabcdef123"))
        st = await ai_settings.get_provider_status()
        check("sk-e2e" not in (st["claude"]["last_error"] or "") and "[redacted]" in (st["claude"]["last_error"] or ""),
              "persist: the message is redacted again before storing", st["claude"]["last_error"])
        orig = (ai_settings.record_provider_error, ai_settings.record_provider_success)

        async def boom(*a, **k):
            raise RuntimeError("db down")

        ai_settings.record_provider_error = ai_settings.record_provider_success = boom
        try:
            await health.persist_failure(PF("claude", "m", "auth", "x"))
            await health.persist_success(T("claude", "m"))
            check(True, "persist: database errors are swallowed")
        except Exception as e:  # noqa: BLE001
            check(False, "persist: database errors are swallowed", repr(e))
        finally:
            ai_settings.record_provider_error, ai_settings.record_provider_success = orig
    finally:
        health.reset()
        from sql.db import execute
        from sql.tables import ai_provider_status
        await execute(ai_provider_status.delete())


async def client_checks():
    """Task 5: the three provider clients behind one interface, in-process against the fakes."""
    from ai_providers.clients import claude_client, gemini_client, openai_client
    from ai_providers.clients.base import get_client
    from ai_providers.types import Completion, Prompt

    models = {"openai": "gpt-4o-mini", "gemini": "gemini-2.5-flash", "claude": "claude-sonnet-5-5"}
    stubenv.clear_fake_ai()

    check(all(get_client(p) is get_client(p) and get_client(p).name == p for p in models),
          "get_client: one instance per provider, named after it")
    try:
        get_client("bogus")
        check(False, "get_client: unknown provider raises", "no error")
    except (KeyError, ValueError):
        check(True, "get_client: unknown provider raises")

    # configured() reads the environment at call time
    keys = {"openai": "OPENAI_API_KEY", "gemini": "GOOGLE_API_KEY", "claude": "ANTHROPIC_API_KEY"}
    saved = {k: os.environ.get(k) for k in keys.values()}
    try:
        for p, k in keys.items():
            os.environ[k] = "x-test"
            on = get_client(p).configured()
            del os.environ[k]
            off = get_client(p).configured()
            check(on is True and off is False, f"configured_{p}: follows {k} at call time", f"{on} {off}")
    finally:
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    # complete / json / stream through each provider
    for p, m in models.items():
        c = get_client(p)
        r = await c.complete(m, Prompt("sys", "hi"))
        check(isinstance(r, Completion) and r.text.strip() and r.finish == "stop" and r.input_tokens > 0
              and r.output_tokens > 0, f"client_complete_each: {p}", r)
        r = await c.complete(m, Prompt("sys", "hi", json_schema={"type": "object"}))
        try:
            ok = isinstance(json.loads(r.text), dict)
        except ValueError:
            ok = False
        check(ok, f"client_json_each: {p}", r.text)
        items = [x async for x in c.stream(m, Prompt("sys", "hi"))]
        chunks, last = items[:-1], items[-1] if items else None
        check(len(chunks) >= 2 and all(isinstance(x, str) and x for x in chunks) and "".join(chunks) == stubenv.FAKE_REPLY
              and isinstance(last, Completion) and last.text == "" and last.finish == "stop"
              and last.input_tokens == 10 and last.output_tokens == 5, f"client_stream_each: {p}", items)

    # the SDK call shape: what each fake received
    prompt = Prompt("be brief", "hello", json_schema={"type": "object"}, max_tokens=321)
    await get_client("claude").complete("claude-sonnet-5-5", prompt, effort="low")
    k = stubenv.LAST_KWARGS["claude"]
    check(not ({"temperature", "top_p", "top_k", "thinking"} & set(k)) and k["fallbacks"] == "default"
          and k["betas"] == ["server-side-fallback-2026-07-01"], "claude_no_sampling_params: none sent, fallbacks default", sorted(k))
    check(k["system"] == "be brief" and k["max_tokens"] == 321 and k["model"] == "claude-sonnet-5-5"
          and k["messages"] == [{"role": "user", "content": [{"type": "text", "text": "hello"}]}]
          and k["output_config"] == {"format": {"type": "json_schema", "schema": {"type": "object", "additionalProperties": False}}, "effort": "low"},
          "claude: system, max_tokens, messages and output_config shape", k)
    for model in ("claude-opus-5-5", "claude-fable-5-1"):
        await get_client("claude").complete(model, Prompt("s", "hi"))
        k = stubenv.LAST_KWARGS["claude"]
        check(k.get("fallbacks") == "default" and "output_config" not in k and "temperature" not in k,
              f"claude: refusal fallback for {model}, no output_config without schema/effort", sorted(k))
    await get_client("claude").complete("claude-haiku-5-5", Prompt("s", "hi"))
    k = stubenv.LAST_KWARGS["claude"]
    check("fallbacks" not in k and "betas" not in k, "claude: no fallbacks for other models", sorted(k))
    await get_client("claude").complete("claude-sonnet-5-5", Prompt("", "hi"))
    check("system" not in stubenv.LAST_KWARGS["claude"], "claude: empty system is omitted")
    async for _ in get_client("claude").stream("claude-sonnet-5-5", Prompt("s", "hi"), effort="medium"):
        pass
    k = stubenv.LAST_KWARGS["claude"]
    check(k["fallbacks"] == "default" and k["output_config"] == {"effort": "medium"}
          and not ({"temperature", "top_p", "top_k"} & set(k)), "claude stream: same params", sorted(k))

    # a big max_tokens goes through stream() + get_final_message()
    before = len(outbox_lines())
    r = await get_client("claude").complete("claude-sonnet-5-5", Prompt("s", "hi", max_tokens=20000))
    new = [x for x in outbox_lines()[before:] if x.get("kind") == "ai_call"]
    check(r.text and [x["target"] for x in new] == ["beta.messages.stream"],
          "claude: max_tokens > 16000 uses stream()", [x.get("target") for x in new])
    before = len(outbox_lines())
    await get_client("claude").complete("claude-sonnet-5-5", Prompt("s", "hi", max_tokens=16000))
    new = [x for x in outbox_lines()[before:] if x.get("kind") == "ai_call"]
    check([x["target"] for x in new] == ["beta.messages.create"], "claude: max_tokens == 16000 uses create()")

    # images: claude image block before the text, openai data URI, gemini Part
    img = Prompt("s", "what is this", image=b"\x89PNGdata", image_mime="image/png")
    for p, m in models.items():
        r = await get_client(p).complete(m, img)
        check(r.text.strip(), f"client_image: {p} answers")
    b64 = base64.b64encode(b"\x89PNGdata").decode()
    content = stubenv.LAST_KWARGS["claude"]["messages"][0]["content"]
    check(content == [{"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": b64}},
                      {"type": "text", "text": "what is this"}], "claude: image block precedes the text", content)
    msgs = stubenv.LAST_KWARGS["openai"]["messages"]
    check(msgs[0] == {"role": "system", "content": "s"} and msgs[1]["role"] == "user"
          and msgs[1]["content"] == [{"type": "text", "text": "what is this"},
                                     {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64}"}}],
          "openai: image sent as a base64 image_url data URI", msgs)
    gk = stubenv.LAST_KWARGS["gemini"]
    parts = gk["contents"]
    check(isinstance(parts, list) and parts[0].inline_data.data == b"\x89PNGdata"
          and parts[0].inline_data.mime_type == "image/png" and parts[1] == "what is this",
          "gemini: image sent as Part.from_bytes", parts)
    check(stubenv._field(gk["config"], "system_instruction") == "s", "gemini: system goes in system_instruction")

    # openai and gemini request shapes
    await get_client("openai").complete("gpt-4o-mini", Prompt("s", "hi", json_schema={"type": "object"}, max_tokens=77))
    k = stubenv.LAST_KWARGS["openai"]
    check(k["response_format"] == {"type": "json_object"} and k.get("max_completion_tokens") == 77 and k["model"] == "gpt-4o-mini",
          "openai: json_schema -> response_format json_object", k)
    # F1: chat completions send max_completion_tokens (accepted by gpt-4o and the reasoning models), never max_tokens
    check("max_tokens" not in k, "openai_max_completion_tokens: complete() never sends max_tokens", sorted(k))
    async for _ in get_client("openai").stream("gpt-4o-mini", Prompt("s", "hi", max_tokens=88)):
        pass
    k = stubenv.LAST_KWARGS["openai"]
    check(k.get("max_completion_tokens") == 88 and "max_tokens" not in k,
          "openai_max_completion_tokens: stream() sends max_completion_tokens", sorted(k))
    await get_client("openai").ping("gpt-4o-mini")
    k = stubenv.LAST_KWARGS["openai"]
    check(k.get("max_completion_tokens") == 16 and "max_tokens" not in k,
          "openai_max_completion_tokens: ping sends max_completion_tokens 16", sorted(k))
    import inspect
    check("max_tokens=" not in inspect.getsource(openai_client) and '"max_tokens"' not in inspect.getsource(openai_client),
          "openai_max_completion_tokens: the openai client source has no max_tokens parameter left")

    # F2: SDK clients are built with an explicit timeout and fewer retries
    oai = get_client("openai")._client().init_kwargs
    check(oai.get("timeout") == 60 and oai.get("max_retries") == 1,
          "sdk_timeouts: openai client timeout 60 s, max_retries 1", {k: v for k, v in oai.items() if k != "api_key"})
    get_client("claude")._messages()
    ant = get_client("claude")._sdk[1].init_kwargs
    check(ant.get("timeout") == 60 and ant.get("max_retries") == 1,
          "sdk_timeouts: anthropic client timeout 60 s, max_retries 1", {k: v for k, v in ant.items() if k != "api_key"})
    get_client("gemini")._models()
    gem = get_client("gemini")._sdk[1].init_kwargs
    opts = gem.get("http_options")
    check(opts is None or (stubenv._field(opts, "timeout") is None and stubenv._field(opts, "retry_options") is None),
          "sdk_timeouts: the gemini client has no client-level timeout (each call passes its own) and no retries",
          {k: v for k, v in gem.items() if k != "api_key"})

    # Follow-up 2 (N2): the long timeout is keyed on the feature: only the insight jobs get 300 s
    from ai_providers import runner as _runner
    from ai_providers.clients import base as client_base
    from ai_providers.features import FEATURES
    from ai_providers.types import Target
    got = {f: client_base.request_timeout(f) for f in FEATURES}
    check(got == {f: (300 if f in ("insight_weekly", "insight_monthly", "insight_translation") else 60) for f in FEATURES}
          and client_base.request_timeout(None) == 60,
          "request_timeout_by_feature: 300 s for the insight jobs, 60 s for every other feature", got)

    def gemini_timeout():
        cfg = stubenv.LAST_KWARGS["gemini"]["config"]
        opts = stubenv._field(cfg, "http_options") if cfg is not None else None
        return stubenv._field(opts, "timeout") if opts is not None else None

    tmodels = {"openai": "gpt-4o-mini", "claude": "claude-sonnet-5-5", "gemini": "gemini-2.5-flash"}

    async def timeouts_via_default_call(feature, size):
        out = []
        for p, m in tmodels.items():
            await _runner.default_call(Prompt("s", "translate this", max_tokens=size), feature)(get_client(p), Target(p, m))
            out.append(gemini_timeout() if p == "gemini" else stubenv.LAST_KWARGS[p].get("timeout"))
        return tuple(out)

    for feature, size, want in (("insight_translation", 8000, 300), ("insight_translation", 2000, 300),
                                ("insight_weekly", 2500, 300), ("insight_monthly", 12000, 300),
                                ("transaction_text", 8000, 60), ("budget_suggestion", 8000, 60),
                                ("transaction_image", 1000, 60), ("chat", 4000, 60)):
        got = await timeouts_via_default_call(feature, size)
        check(got == (want, want, want * 1000),
              f"timeout_by_feature: {feature} with max_tokens {size} -> {want} s on openai, claude and gemini (ms)", got)
    await _runner.default_call(Prompt("s", "translate this", max_tokens=32000), "insight_translation")(
        get_client("claude"), Target("claude", "claude-sonnet-5-5"))
    check(stubenv.LAST_KWARGS["claude"].get("timeout") == 300,
          "timeout_by_feature: claude's streamed path for a 32000-token translation gets 300 s too",
          stubenv.LAST_KWARGS["claude"].get("timeout"))
    # complete() without a feature, and stream(): the 60 s default (OpenAI/Claude: the client's; Gemini: per request)
    big = Prompt("s", "hi", max_tokens=8000)
    await get_client("openai").complete("gpt-4o-mini", big)
    await get_client("claude").complete("claude-sonnet-5-5", big)
    await get_client("gemini").complete("gemini-2.5-flash", big)
    check("timeout" not in stubenv.LAST_KWARGS["openai"] and "timeout" not in stubenv.LAST_KWARGS["claude"]
          and gemini_timeout() == 60_000, "timeout_by_feature: complete() with no timeout keeps 60 s",
          (stubenv.LAST_KWARGS["openai"].get("timeout"), stubenv.LAST_KWARGS["claude"].get("timeout"), gemini_timeout()))
    async for _ in get_client("openai").stream("gpt-4o-mini", big):
        pass
    async for _ in get_client("claude").stream("claude-sonnet-5-5", big):
        pass
    async for _ in get_client("gemini").stream("gemini-2.5-flash", big):
        pass
    check("timeout" not in stubenv.LAST_KWARGS["openai"] and "timeout" not in stubenv.LAST_KWARGS["claude"]
          and gemini_timeout() == 60_000,
          "timeout_by_feature: stream() keeps 60 s even for a large prompt",
          (stubenv.LAST_KWARGS["openai"].get("timeout"), stubenv.LAST_KWARGS["claude"].get("timeout"), gemini_timeout()))
    await get_client("gemini").ping("gemini-2.5-flash")
    p_ping = gemini_timeout()
    await get_client("gemini").transcribe("gemini-2.5-flash", b"x", "a.mp3", None)
    check(p_ping == 60_000 and gemini_timeout() == 60_000,
          "timeout_by_feature: gemini ping and transcribe pass their own 60 s", (p_ping, gemini_timeout()))

    await _gemini_server_timeout_header_checks()
    await get_client("openai").complete("gpt-4o-mini", Prompt("s", "hi"))
    check("response_format" not in stubenv.LAST_KWARGS["openai"], "openai: no response_format without json_schema")
    async for _ in get_client("openai").stream("gpt-4o-mini", Prompt("s", "hi")):
        pass
    k = stubenv.LAST_KWARGS["openai"]
    check(k["stream"] is True and k["stream_options"] == {"include_usage": True}, "openai: stream asks for usage", k)
    await get_client("gemini").complete("gemini-2.5-flash", Prompt("s", "hi", json_schema={"type": "object"}, max_tokens=55))
    cfg = stubenv.LAST_KWARGS["gemini"]["config"]
    check(stubenv._field(cfg, "response_mime_type") == "application/json" and stubenv._field(cfg, "max_output_tokens") == 55
          and stubenv.LAST_KWARGS["gemini"]["contents"] == "hi", "gemini: json_schema -> response_mime_type", cfg)
    await get_client("gemini").complete("gemini-2.5-flash", Prompt("s", "hi"))
    check(stubenv._field(stubenv.LAST_KWARGS["gemini"]["config"], "response_mime_type") is None,
          "gemini: no mime type without json_schema")

    # temperature (R8): OpenAI and Gemini get it when set; Claude never does
    await get_client("openai").complete("gpt-4o-mini", Prompt("s", "hi", temperature=0.3))
    check(stubenv.LAST_KWARGS["openai"]["temperature"] == 0.3, "temperature: openai receives it", stubenv.LAST_KWARGS["openai"])
    await get_client("openai").complete("gpt-4o-mini", Prompt("s", "hi"))
    check("temperature" not in stubenv.LAST_KWARGS["openai"], "temperature: openai omits it when None")
    await get_client("openai").complete("gpt-4o-mini", Prompt("", "hi"))
    check(stubenv.LAST_KWARGS["openai"]["messages"] == [{"role": "user", "content": "hi"}],
          "openai: empty system is omitted", stubenv.LAST_KWARGS["openai"]["messages"])
    await get_client("gemini").complete("gemini-2.5-flash", Prompt("s", "hi", temperature=0.7))
    check(stubenv._field(stubenv.LAST_KWARGS["gemini"]["config"], "temperature") == 0.7, "temperature: gemini receives it")
    await get_client("gemini").complete("gemini-2.5-flash", Prompt("s", "hi"))
    check(stubenv._field(stubenv.LAST_KWARGS["gemini"]["config"], "temperature") is None, "temperature: gemini omits it when None")
    await get_client("claude").complete("claude-sonnet-5-5", Prompt("s", "hi", temperature=0.5), effort="low")
    async for _ in get_client("claude").stream("claude-sonnet-5-5", Prompt("s", "hi", temperature=0.5)):
        pass
    check("temperature" not in stubenv.LAST_KWARGS["claude"] and "temperature" not in str(stubenv.LAST_KWARGS["claude"]),
          "temperature: claude never sends it even when set (complete and stream)", stubenv.LAST_KWARGS["claude"])
    await get_client("claude").complete("claude-sonnet-5-5", Prompt("s", "hi", temperature=0.5))
    check("temperature" not in stubenv.LAST_KWARGS["claude"], "temperature: claude complete omits it")

    # R9: Claude gets a strict copy of the schema; the caller's dict is untouched
    schema = {"type": "object", "properties": {
        "a": {"type": "array", "items": {"type": "object", "properties": {"n": {"type": "number"}}}},
        "b": {"anyOf": [{"type": "object", "properties": {}}, {"type": "null"}]},
        "c": {"type": "object", "properties": {}, "additionalProperties": True},
        "d": {"$ref": "#/$defs/D"}, "e": {"enum": ["object"]}},
        "required": ["a"], "$defs": {"D": {"type": "object", "properties": {"x": {"type": "string"}}}}}
    original = copy.deepcopy(schema)
    await get_client("claude").complete("claude-sonnet-5-5", Prompt("s", "hi", json_schema=schema))
    sent = stubenv.LAST_KWARGS["claude"]["output_config"]["format"]["schema"]
    check(schema == original, "claude_schema_strict: the caller's schema is not mutated")
    check(sent["additionalProperties"] is False
          and sent["properties"]["a"]["items"]["additionalProperties"] is False
          and sent["properties"]["b"]["anyOf"][0]["additionalProperties"] is False
          and "additionalProperties" not in sent["properties"]["b"]["anyOf"][1]
          and sent["properties"]["c"]["additionalProperties"] is True
          and sent["$defs"]["D"]["additionalProperties"] is False
          and sent["properties"]["e"] == {"enum": ["object"]} and sent["required"] == ["a"],
          "claude_schema_strict: additionalProperties:false on every object node lacking it", sent)

    # transcription
    r = await get_client("gemini").transcribe("gemini-2.5-flash", b"RIFFxxxx", "note.m4a", "my")
    gk = stubenv.LAST_KWARGS["gemini"]
    check(r.text == "fake transcript" and r.finish == "stop", "gemini_transcribe: returns the transcript", r)
    check(gk["contents"][0].inline_data.mime_type == "audio/mp4" and gk["contents"][0].inline_data.data == b"RIFFxxxx"
          and "Transcribe this audio exactly. Reply with only the transcript." in gk["contents"][1]
          and "Burmese" in gk["contents"][1] and "The spoken language is my" not in gk["contents"][1],
          "gemini_transcribe: audio part, mime from extension, instruction and the language name", gk["contents"])
    await get_client("gemini").transcribe("gemini-2.5-flash", b"x", "a.mp3", "xx")
    check("ISO 639-1 code 'xx'" in stubenv.LAST_KWARGS["gemini"]["contents"][1],
          "gemini_transcribe: unknown language code is phrased as an ISO code", stubenv.LAST_KWARGS["gemini"]["contents"][1])
    await get_client("gemini").transcribe("gemini-2.5-flash", b"x", "a.mp3", "en")
    check("English" in stubenv.LAST_KWARGS["gemini"]["contents"][1], "gemini_transcribe: en -> English")
    await get_client("gemini").transcribe("gemini-2.5-flash", b"x", "a.unknownext", None)
    gk = stubenv.LAST_KWARGS["gemini"]
    check(gk["contents"][0].inline_data.mime_type.startswith("audio/") and len(gk["contents"]) == 2
          and "language" not in gk["contents"][1].lower(), "gemini_transcribe: unknown extension, no language hint")
    r = await get_client("openai").transcribe("whisper-1", b"RIFFxxxx", "a.wav", "en")
    k = stubenv.LAST_KWARGS["openai"]
    check(r.text == "fake transcript" and r.input_tokens == r.output_tokens == len("fake transcript") // 4
          and k["language"] == "en" and k["model"] == "whisper-1" and k["file"] == ("a.wav", b"RIFFxxxx"),
          "openai_transcribe: whisper-1 with language, tokens estimated len//4", (r, k))
    await get_client("openai").transcribe("whisper-1", b"x", "a.wav", None)
    check("language" not in stubenv.LAST_KWARGS["openai"], "openai_transcribe: no language -> omitted")
    try:
        await get_client("claude").transcribe("claude-sonnet-5-5", b"x", "a.wav", None)
        check(False, "claude_transcribe_not_supported", "no error")
    except NotImplementedError:
        check(True, "claude_transcribe_not_supported")

    # refusal and the other odd answers
    stubenv.set_fake_ai(claude="refusal")
    r = await get_client("claude").complete("claude-sonnet-5-5", Prompt("s", "hi"))
    check(r.finish == "refusal" and r.text == "", "claude_refusal_finish: empty content tolerated", r)
    items = [x async for x in get_client("claude").stream("claude-sonnet-5-5", Prompt("s", "hi"))]
    check(len(items) == 1 and items[0].finish == "refusal", "claude_refusal_finish: stream yields just the Completion", items)
    for p, m in models.items():
        stubenv.set_fake_ai(**{p: "empty"})
        r = await get_client(p).complete(m, Prompt("s", "hi"))
        check(r.text == "" and r.finish == "stop", f"client: {p} empty answer passes through", r)
        stubenv.set_fake_ai(**{p: "bad_json"})
        r = await get_client(p).complete(m, Prompt("s", "hi", json_schema={"type": "object"}))
        check(r.text == "not json", f"client: {p} bad_json passes through unparsed", r)

    # SDK errors are not caught or translated; mid-stream failures propagate after the first chunk
    for p, m in models.items():
        stubenv.set_fake_ai(**{p: "billing"})
        try:
            await get_client(p).complete(m, Prompt("s", "hi"))
            check(False, f"client_errors_propagate: {p} complete", "no error")
        except stubenv.FakeAPIError as e:
            check(e.status_code in (400, 402), f"client_errors_propagate: {p} complete raises the SDK error")
        try:
            [x async for x in get_client(p).stream(m, Prompt("s", "hi"))]
            check(False, f"client_errors_propagate: {p} stream", "no error")
        except stubenv.FakeAPIError:
            check(True, f"client_errors_propagate: {p} stream raises the SDK error")
        stubenv.set_fake_ai(**{p: "fail_mid_stream"})
        got = []
        try:
            async for x in get_client(p).stream(m, Prompt("s", "hi")):
                got.append(x)
            check(False, f"client_errors_propagate: {p} mid-stream", "no error")
        except stubenv.FakeAPIError as e:
            check(e.status_code == 503 and len(got) == 1 and isinstance(got[0], str),
                  f"client_errors_propagate: {p} mid-stream 503 after one chunk", got)
        stubenv.set_fake_ai(**{p: "timeout"})
        try:
            await get_client(p).complete(m, Prompt("s", "hi"))
            check(False, f"client_errors_propagate: {p} timeout", "no error")
        except TimeoutError:
            check(True, f"client_errors_propagate: {p} timeout raises TimeoutError")

    # ping: a tiny request; whisper pings through a short silent clip
    stubenv.clear_fake_ai()
    for p, m in {**models, "whisper": "whisper-1"}.items():
        c = get_client("openai" if p == "whisper" else p)
        before = len(outbox_lines())
        check(await c.ping(m) is None, f"ping: {p} returns None")
        new = [x for x in outbox_lines()[before:] if x.get("kind") == "ai_call"]
        check(len(new) == 1 and new[0]["model"] == m, f"ping: {p} makes exactly one call", new)
    check(stubenv.LAST_KWARGS["claude"]["max_tokens"] == 16 and "output_config" not in stubenv.LAST_KWARGS["claude"],
          "ping: claude max_tokens 16, no effort")
    stubenv.set_fake_ai(claude="auth", openai="auth")
    for p, m in (("claude", "claude-sonnet-5-5"), ("openai", "whisper-1"), ("openai", "gpt-4o-mini")):
        try:
            await get_client(p).ping(m)
            check(False, f"ping: {p}/{m} propagates SDK errors", "no error")
        except stubenv.FakeAPIError:
            check(True, f"ping: {p}/{m} propagates SDK errors")
    stubenv.clear_fake_ai()

    # finish mapping
    class R:  # stand-in for Gemini's FinishReason enum member
        def __init__(self, name):
            self.name = name

    om = {"length": "length", "content_filter": "filtered", "stop": "stop", "tool_calls": "stop", None: "stop"}
    check(all(openai_client.map_finish(raw) == want for raw, want in om.items()), "finish_map: openai")
    gm = {"MAX_TOKENS": "length", "SAFETY": "filtered", "PROHIBITED_CONTENT": "filtered", "BLOCKLIST": "filtered",
          "STOP": "stop", "OTHER": "stop", None: "stop"}
    check(all(gemini_client.map_finish(R(raw) if raw else None) == want for raw, want in gm.items())
          and gemini_client.map_finish("MAX_TOKENS") == "length", "finish_map: gemini (enum member or plain string)")
    cm = {"max_tokens": "length", "refusal": "refusal", "end_turn": "stop", "stop_sequence": "stop",
          "pause_turn": "stop", None: "stop"}
    check(all(claude_client.map_finish(raw) == want for raw, want in cm.items()), "finish_map: claude")

    # gemini usage falls back to len // 4 when usage_metadata is missing; text blocks only for claude
    check(gemini_client.usage_of(None, 40, "x" * 80) == (10, 20) and gemini_client.usage_of(None, 3, "") == (0, 0),
          "gemini: usage falls back to len // 4")
    msg = NS(content=[NS(type="thinking", thinking="hmm"), NS(type="fallback"), NS(type="text", text="a"),
                      NS(type="text", text="b")], stop_reason="end_turn", usage=NS(input_tokens=3, output_tokens=4))
    check(claude_client.text_of(msg) == "ab" and claude_client.text_of(NS(content=[])) == "",
          "claude: text is the concatenation of text blocks only")


async def _gemini_server_timeout_header_checks():
    """Follow-up 2 (N1), no network: the real google-genai client builds each request, and the request is captured
    just before it would be sent. A 300 s request must still say X-Server-Timeout: 300 after 60 s calls."""
    from google.genai import client as genai_client_mod
    from google.genai import types as gtypes

    from ai_providers import runner as _runner
    from ai_providers.clients.base import get_client
    from ai_providers.types import Prompt, Target

    class _Stop(Exception):
        pass

    def real_client(**kw):
        """A real genai client (stubenv only swaps the package-level name) whose send step records and stops."""
        rc = genai_client_mod.Client(api_key="e2e-not-a-key", **kw)
        sent = []

        async def capture(http_request, http_options=None, stream=False):
            sent.append((dict(http_request.headers).get("X-Server-Timeout"), http_request.timeout))
            raise _Stop()
        rc._api_client._async_request = capture
        return rc, sent

    async def attempt(coro_or_gen):
        try:
            if hasattr(coro_or_gen, "__aiter__"):
                async for _ in coro_or_gen:
                    pass
            else:
                await coro_or_gen
        except _Stop:
            pass

    # what the fix avoids: with a client-level timeout, a call that does not override it writes X-Server-Timeout
    # into the client's shared headers, and a later 300 s request inherits that 60
    rc, sent = real_client(http_options=gtypes.HttpOptions(timeout=60_000))
    await attempt(rc.aio.models.generate_content(model="gemini-2.5-flash", contents="hi"))
    await attempt(rc.aio.models.generate_content(model="gemini-2.5-flash", contents="hi", config=gtypes.GenerateContentConfig(
        http_options=gtypes.HttpOptions(timeout=300_000))))
    check(sent == [("60", 60.0), ("60", 300.0)],
          "gemini_server_timeout_header: (SDK behaviour) a client-level timeout leaks X-Server-Timeout 60 into later "
          "requests", sent)

    # our client: no client-level timeout, every call passes its own
    gc = get_client("gemini")
    gc._models()  # make sure _sdk is keyed on the current key
    saved = gc._sdk
    rc, sent = real_client()
    gc._sdk = (saved[0], rc)
    try:
        await attempt(gc.stream("gemini-2.5-flash", Prompt("s", "hi")))
        await attempt(gc.ping("gemini-2.5-flash"))
        await attempt(gc.transcribe("gemini-2.5-flash", b"x", "a.mp3", None))
        await attempt(_runner.default_call(Prompt("s", "translate", max_tokens=8000), "insight_translation")(
            gc, Target("gemini", "gemini-2.5-pro")))
        await attempt(_runner.default_call(Prompt("s", "x", max_tokens=8000), "transaction_text")(
            gc, Target("gemini", "gemini-2.5-flash")))
        shared = dict(rc._api_client._http_options.headers or {})
    finally:
        gc._sdk = saved
    check(sent == [("60", 60.0), ("60", 60.0), ("60", 60.0), ("300", 300.0), ("60", 60.0)],
          "gemini_server_timeout_header: stream, ping and transcribe send 60; a later insight request still sends "
          "X-Server-Timeout 300 (and a transaction 60)", sent)
    check("X-Server-Timeout" not in shared,
          "gemini_server_timeout_header: the client's shared header dict is never written", sorted(shared))


def control_format_checks():
    """Task 6: the control file accepts provider@model keys and {"kind", "times"} values, and rejects typos."""
    for bad in ({"claud": "billing"}, {"claude": "billng"}, {"claude@": "billing"}, {"@x": "billing"},
                {"claude": {"kind": "billing", "times": 0}}, {"claude": {"kind": "nope", "times": 1}},
                {"claude": {"times": 1}}, {"claude": {"kind": "billing", "times": "2"}}, {"claude": 3}):
        try:
            stubenv.set_fake_ai(**bad)
            check(False, f"set_fake_ai_validates: {bad!r} rejected", "no error")
        except ValueError:
            check(True, f"set_fake_ai_validates: {bad!r} rejected")
    try:
        stubenv.set_fake_ai(**{"claude@claude-typo": "model_not_found", "openai": {"kind": "rate_limit", "times": 1},
                               "gemini": {"kind": "server"}})
        check(True, "set_fake_ai_validates: model keys and kind/times values accepted")
    except ValueError as e:
        check(False, "set_fake_ai_validates: model keys and kind/times values accepted", repr(e))
    stubenv.clear_fake_ai()

    # provider@model applies to that model only; a model entry wins over the provider entry
    stubenv.set_fake_ai(**{"claude@claude-typo": "model_not_found", "claude": "server"})
    try:
        stubenv._begin("claude", "test", "claude-typo")
        got = "no error"
    except stubenv.FakeAPIError as e:
        got = e.status_code
    check(got == 404, "control_model_key: claude@claude-typo -> 404", got)
    try:
        stubenv._begin("claude", "test", "claude-sonnet-5-5")
        got = "no error"
    except stubenv.FakeAPIError as e:
        got = e.status_code
    check(got == 529, "control_model_key: other claude models use the provider entry", got)

    # {"kind", "times"}: fails `times` calls, then succeeds
    stubenv.set_fake_ai(claude={"kind": "rate_limit", "times": 2})
    got = []
    for _ in range(3):
        try:
            got.append(stubenv._begin("claude", "test", "claude-sonnet-5-5"))
        except stubenv.FakeAPIError as e:
            got.append(e.status_code)
    check(got == [429, 429, None], "control_times: two failures then success", got)
    stubenv.clear_fake_ai()


def _outbox_ai_calls(before):
    return [x for x in outbox_lines()[before:] if x.get("kind") == "ai_call"]


async def runner_checks():
    """Task 6: the runner (fallback, cool-off, usage tracking, status), in-process against the fakes."""
    from sqlalchemy import delete, insert, select

    from ai_providers import health, settings
    from sql import ai_settings
    from sql.db import execute, fetch_all
    from sql.tables import ai_provider_status, ai_usage, users

    saved = (settings._env, dict(settings._env_units), settings._panel)
    uid = "t6-runner-user"
    await execute(delete(users).where(users.c.id == uid))
    await execute(insert(users).values(id=uid, name="t6", email="t6-runner@x.test", password="x"))
    health.reset()
    try:
        settings.set_panel_cache({})
        settings.reload_env({})
        await _runner_checks(uid)
    finally:
        stubenv.clear_fake_ai()
        health.reset()
        try:
            for f in ("chat", "insight_weekly"):
                await ai_settings.delete_feature_setting(f)
            await execute(ai_provider_status.delete())
            await execute(delete(users).where(users.c.id == uid))  # cascades to its ai_usage rows
        finally:
            settings._env, settings._panel = saved[0], saved[2]
            settings._env_units.clear()
            settings._env_units.update(saved[1])

    rows = await fetch_all(select(ai_usage.c.id).where(ai_usage.c.user_id == uid))
    check(rows == [], "runner: test usage rows cleaned up", rows)


async def _runner_checks(uid):
    from sqlalchemy import select

    from ai_providers import health, runner, settings
    from ai_providers.errors import AllProvidersFailed, UnusableAnswer
    from ai_providers.types import FeatureSetting, Prompt, Target
    from ai_usage_models import AIProviderType
    from ai_usage_service import PRICING
    from sql import ai_settings
    from sql.db import fetch_all
    from sql.tables import ai_usage

    T = Target
    claude_main = FeatureSetting(T("claude", "claude-sonnet-5-5"), None, "panel")

    async def usage_rows():
        return await fetch_all(select(ai_usage).where(ai_usage.c.user_id == uid).order_by(ai_usage.c.created_at))

    async def go(setting=claude_main, feature="chat", prompt=None, parse=None, background=False, **fakes):
        """Save the panel setting, configure the fakes, run once. Returns (result or exception, providers called)."""
        await settings.save_panel(feature, setting, "t6@x")
        stubenv.set_fake_ai(**fakes) if fakes else stubenv.clear_fake_ai()
        before = len(outbox_lines())
        kw = {"parse": parse} if parse else {}
        try:
            out = await runner.run(feature, user_id=uid, call=runner.default_call(prompt or Prompt("s", "u"), feature),
                                   background=background, **kw)
        except Exception as e:  # noqa: BLE001
            out = e
        return out, [x.get("provider") for x in _outbox_ai_calls(before)]

    def parse_json(c):
        try:
            return json.loads(c.text)
        except ValueError as e:
            raise UnusableAnswer("bad json") from e

    # enum and pricing
    check(AIProviderType("claude") == AIProviderType.CLAUDE and AIProviderType.CLAUDE.value == "claude",
          "usage: AIProviderType.CLAUDE")
    check(PRICING.get("claude") == {"claude-sonnet-5-5": {"input": 2.00, "output": 10.00},
                                    "claude-haiku-5-5": {"input": 0.10, "output": 0.50},
                                    "claude-opus-5-5": {"input": 4.00, "output": 20.00}},
          "usage: PRICING['claude']", PRICING.get("claude"))

    # the happy path: the main provider answers, effort goes to claude, usage is tracked without fallback
    health.reset()
    n0 = len(await usage_rows())
    r, called = await go()
    ok = isinstance(r, runner.RunResult)
    check(ok and r.target == T("claude", "claude-sonnet-5-5") and r.fallback_from is None and called == ["claude"]
          and r.value.text == stubenv.FAKE_REPLY and r.completion.input_tokens == 10,
          "run: the main provider answers", (r, called))
    check(stubenv.LAST_KWARGS["claude"].get("output_config", {}).get("effort") == "low",
          "default_call: passes CLAUDE_EFFORT to claude", stubenv.LAST_KWARGS["claude"].get("output_config"))
    rows = await usage_rows()
    check(len(rows) == n0 + 1 and rows[-1]["provider"] == "claude" and rows[-1]["fallback_from"] is None
          and rows[-1]["feature_type"] == "chat" and rows[-1]["total_tokens"] == 15
          and float(rows[-1]["estimated_cost_usd"]) > 0, "run: usage row for claude, no fallback", rows[-1:])

    # fallback_on_billing
    health.reset()
    r, called = await go(claude="billing")
    check(isinstance(r, runner.RunResult) and r.target.provider == "openai" and r.fallback_from == "claude"
          and called == ["claude", "openai"], "fallback_on_billing: openai answers, fallback_from claude", (r, called))
    rows = await usage_rows()
    check(rows and rows[-1]["provider"] == "openai" and rows[-1]["fallback_from"] == "claude"
          and rows[-1]["model_name"] == "gpt-4o-mini", "fallback_on_billing: usage row openai, fallback_from claude", rows[-1:])
    check(not health.is_available(T("claude", "claude-haiku-5-5")), "fallback_on_billing: claude cools off provider-wide")

    # fallback_each_kind
    for kind in ("auth", "rate_limit", "server", "timeout", "model_not_found", "refusal", "empty", "bad_json"):
        health.reset()
        extra = {"parse": parse_json, "prompt": Prompt("s", "u", json_schema={"type": "object"})} if kind == "bad_json" else {}
        r, called = await go(claude=kind, **extra)
        check(isinstance(r, runner.RunResult) and r.target.provider == "openai" and r.fallback_from == "claude"
              and called == ["claude", "openai"], f"fallback_each_kind: {kind}", (r, called))
    rows = await usage_rows()
    check(rows[-1]["fallback_from"] == "claude" and rows[-1]["provider"] == "openai", "fallback_each_kind: usage rows")

    # a refusal is recorded as kind "refusal", an empty answer as "unusable"
    health.reset()
    r, _ = await go(setting=FeatureSetting(T("claude", "claude-sonnet-5-5"), (), "panel"), claude="refusal")
    check(isinstance(r, AllProvidersFailed) and [f.kind for f in r.failures] == ["refusal"],
          "run: refusal failure kind", r)
    check(health.is_available(T("claude", "claude-sonnet-5-5")), "health_unchanged: refusal does not cool the target")
    r, _ = await go(setting=FeatureSetting(T("claude", "claude-sonnet-5-5"), (), "panel"), claude="empty")
    check(isinstance(r, AllProvidersFailed) and [f.kind for f in r.failures] == ["unusable"],
          "run: empty answer failure kind unusable", r)
    check(health.is_available(T("claude", "claude-sonnet-5-5")), "health_unchanged: unusable does not cool the target")

    # R11: a provider-wide failure skips the provider's later targets in the same request
    health.reset()
    two_claudes = FeatureSetting(T("claude", "claude-sonnet-5-5"),
                                 (T("claude", "claude-haiku-5-5"), T("openai", "gpt-4o-mini")), "panel")
    r, called = await go(setting=two_claudes, claude="billing")
    check(isinstance(r, runner.RunResult) and r.target == T("openai", "gpt-4o-mini") and r.fallback_from == "claude"
          and called == ["claude", "openai"], "recheck_availability: billing skips claude-haiku in the same request",
          (r, called))
    health.reset()
    r, called = await go(setting=two_claudes, **{"claude@claude-sonnet-5-5": "model_not_found"})
    check(isinstance(r, runner.RunResult) and r.target == T("claude", "claude-haiku-5-5")
          and called == ["claude", "claude"], "recheck_availability: a model-scoped failure still tries the other model",
          (r, called))

    # no_fallback_on_bad_request: the request itself is wrong, so no other provider is tried and nothing cools
    health.reset()
    n0 = len(await usage_rows())
    r, called = await go(claude="bad_request")
    check(isinstance(r, stubenv.FakeAPIError) and r.status_code == 400 and called == ["claude"],
          "no_fallback_on_bad_request: the error propagates, no openai or gemini call", (r, called))
    check(health.is_available(T("claude", "claude-sonnet-5-5")) and len(await usage_rows()) == n0,
          "no_fallback_on_bad_request: no cool-off and no usage row")

    # a parse error that is not UnusableAnswer is a bug in our code: it propagates
    health.reset()

    def parse_crash(c):
        raise KeyError("oops")
    r, called = await go(parse=parse_crash)
    check(isinstance(r, KeyError) and called == ["claude"], "run: a parse crash propagates without fallback", (r, called))

    # no_backups_fails
    health.reset()
    n0 = len(await usage_rows())
    r, called = await go(setting=FeatureSetting(T("claude", "claude-sonnet-5-5"), (), "panel"), claude="billing")
    check(isinstance(r, AllProvidersFailed) and len(r.failures) == 1 and r.failures[0].kind == "billing"
          and r.failures[0].provider == "claude" and called == ["claude"], "no_backups_fails: one billing failure", (r, called))
    check(len(await usage_rows()) == n0, "no_backups_fails: no usage row")

    # every provider failing raises AllProvidersFailed with one failure each, in chain order
    health.reset()
    r, called = await go(claude="rate_limit", openai="rate_limit", gemini="rate_limit")
    check(isinstance(r, AllProvidersFailed) and [f.provider for f in r.failures] == ["claude", "openai", "gemini"]
          and r.all_rate_limited, "run: all providers failing -> AllProvidersFailed in chain order", r)

    # all targets cooling: still tried in order
    r, called = await go()
    check(isinstance(r, runner.RunResult) and r.target.provider == "claude" and called == ["claude"],
          "run: when every target is cooling, the chain is still tried in order", (r, called))

    # not_configured_main_skipped
    health.reset()
    old_key = os.environ.pop("ANTHROPIC_API_KEY", None)
    try:
        r, called = await go()
    finally:
        if old_key is not None:
            os.environ["ANTHROPIC_API_KEY"] = old_key
    check(isinstance(r, runner.RunResult) and r.target.provider == "openai" and r.fallback_from == "claude"
          and called == ["openai"], "not_configured_main_skipped: answers from openai, claude never called", (r, called))
    health.reset()
    old_key = os.environ.pop("ANTHROPIC_API_KEY", None)
    try:
        r, called = await go(setting=FeatureSetting(T("claude", "claude-sonnet-5-5"), (), "panel"))
    finally:
        if old_key is not None:
            os.environ["ANTHROPIC_API_KEY"] = old_key
    check(isinstance(r, AllProvidersFailed) and [f.kind for f in r.failures] == ["not_configured"] and called == [],
          "not_configured: with no backups the feature fails", r)
    check(health.is_available(T("claude", "claude-sonnet-5-5")),
          "health_unchanged: not_configured does not cool the target")

    # F5: an unconfigured main never counts as "available", so a cooling backup is still tried (all unhealthy -> in order)
    health.reset()
    one_backup = FeatureSetting(T("claude", "claude-sonnet-5-5"), (T("openai", "gpt-4o-mini"),), "panel")
    await settings.save_panel("chat", one_backup, "t6@x")
    health.mark_failure(runner.ProviderFailure("openai", "gpt-4o-mini", "rate_limit", "429"))
    old_key = os.environ.pop("ANTHROPIC_API_KEY", None)
    try:
        listed = list(runner._targets("chat"))
        r, called = await go(setting=one_backup)
    finally:
        if old_key is not None:
            os.environ["ANTHROPIC_API_KEY"] = old_key
    check(listed == [T("claude", "claude-sonnet-5-5"), T("openai", "gpt-4o-mini")],
          "unconfigured_main_cooling_backup: _targets falls back to the whole chain in order", listed)
    check(isinstance(r, runner.RunResult) and r.target == T("openai", "gpt-4o-mini") and r.fallback_from == "claude"
          and called == ["openai"], "unconfigured_main_cooling_backup: the cooling backup still answers", (r, called))
    health.reset()
    health.mark_failure(runner.ProviderFailure("openai", "gpt-4o-mini", "rate_limit", "429"))
    listed = list(runner._targets("chat"))
    check(listed == [T("claude", "claude-sonnet-5-5")],
          "unconfigured_main_cooling_backup: with a configured main the cooling backup is still skipped", listed)

    # F1: a model-level 400 (OpenAI "Invalid model" / unsupported max_tokens) falls back, cools only that pair and
    # shows in the provider status
    for kind in ("invalid_model", "unsupported_param", "unsupported_value"):
        health.reset()
        await execute_status_delete()
        oai_main = FeatureSetting(T("openai", "gpt-5-mini"), (T("gemini", "gemini-2.5-flash"),), "panel")
        r, called = await go(setting=oai_main, **{"openai@gpt-5-mini": kind})
        st = await ai_settings.get_provider_status()
        check(isinstance(r, runner.RunResult) and r.target == T("gemini", "gemini-2.5-flash") and r.fallback_from == "openai"
              and called == ["openai", "gemini"], f"model_level_400_falls_back: {kind} -> gemini answers", (r, called))
        check(not health.is_available(T("openai", "gpt-5-mini")) and health.is_available(T("openai", "gpt-4o-mini")),
              f"model_level_400_falls_back: {kind} cools only openai/gpt-5-mini")
        check((st.get("openai") or {}).get("last_error"), f"model_level_400_falls_back: {kind} is persisted to the status",
              st.get("openai"))

    # cooled_target_skipped_next_time (the fakes are cleared: claude would answer if it were called)
    health.reset()
    await go(claude="billing")
    r, called = await go()
    check(isinstance(r, runner.RunResult) and r.target.provider == "openai" and "claude" not in called,
          "cooled_target_skipped_next_time: claude is not called while cooling", (r, called))

    # model_typo_scoped
    health.reset()
    r, called = await go(setting=FeatureSetting(T("claude", "claude-typo"), None, "panel"),
                         **{"claude@claude-typo": "model_not_found"})
    check(isinstance(r, runner.RunResult) and r.target.provider == "openai" and r.fallback_from == "claude"
          and called == ["claude", "openai"], "model_typo_scoped: chat falls back from the typo'd model", (r, called))
    # the control file keeps the typo entry: it must not affect claude-sonnet-5-5
    r, called = await go(setting=FeatureSetting(T("claude", "claude-sonnet-5-5"), None, "panel"), feature="insight_weekly",
                         **{"claude@claude-typo": "model_not_found"})
    check(isinstance(r, runner.RunResult) and r.target == T("claude", "claude-sonnet-5-5") and r.fallback_from is None
          and called == ["claude"], "model_typo_scoped: insight_weekly on claude-sonnet-5-5 still answers from claude",
          (r, called))
    check(not health.is_available(T("claude", "claude-typo")) and health.is_available(T("claude", "claude-sonnet-5-5")),
          "model_typo_scoped: only the typo'd pair cools off")
    await settings.clear_panel("insight_weekly")

    # background_retries_rate_limit (asyncio.sleep is patched to a no-op that records the delays)
    health.reset()
    sleeps = []
    real_sleep = asyncio.sleep

    async def fake_sleep(delay, *a, **k):
        sleeps.append(delay)
        await real_sleep(0)
    asyncio.sleep = fake_sleep
    try:
        r, called = await go(background=True, claude={"kind": "rate_limit", "times": 2})
    finally:
        asyncio.sleep = real_sleep
    check(isinstance(r, runner.RunResult) and r.target.provider == "claude" and r.fallback_from is None
          and called == ["claude", "claude", "claude"] and sleeps == [5, 10],
          "background_retries_rate_limit: claude answers on the third try", (r, called, sleeps))
    check(health.is_available(T("claude", "claude-sonnet-5-5")), "background_retries_rate_limit: no cool-off after success")
    health.reset()
    r, called = await go(claude={"kind": "rate_limit", "times": 1})
    check(isinstance(r, runner.RunResult) and r.target.provider == "openai" and called == ["claude", "openai"],
          "run: without background a rate limit falls back at once", (r, called))
    health.reset()
    asyncio.sleep = fake_sleep
    sleeps.clear()
    try:
        r, called = await go(background=True, claude="rate_limit")
    finally:
        asyncio.sleep = real_sleep
    check(isinstance(r, runner.RunResult) and r.target.provider == "openai" and r.fallback_from == "claude"
          and called == ["claude", "claude", "claude", "openai"] and sleeps == [5, 10],
          "background: three rate limits, then the next target", (r, called, sleeps))

    # streams
    async def go_stream(**fakes):
        await settings.save_panel("chat", claude_main, "t6@x")
        stubenv.set_fake_ai(**fakes) if fakes else stubenv.clear_fake_ai()
        before = len(outbox_lines())
        items, err = [], None
        try:
            async for x in runner.run_stream("chat", user_id=uid, prompt=Prompt("s", "u")):
                items.append(x)
        except Exception as e:  # noqa: BLE001
            err = e
        return items, err, [x.get("provider") for x in _outbox_ai_calls(before)]

    health.reset()
    items, err, called = await go_stream()
    chunks, last = items[:-1], items[-1] if items else None
    check(err is None and len(chunks) >= 2 and all(isinstance(c, str) for c in chunks)
          and isinstance(last, runner.RunResult) and last.value == stubenv.FAKE_REPLY == "".join(chunks)
          and last.target.provider == "claude" and last.fallback_from is None and last.completion.input_tokens == 10,
          "run_stream: chunks then one RunResult", (items, err))

    health.reset()
    n0 = len(await usage_rows())
    items, err, called = await go_stream(claude="server")
    last = items[-1] if items else None
    check(err is None and isinstance(last, runner.RunResult) and last.target.provider == "openai"
          and last.fallback_from == "claude" and "".join(items[:-1]) == stubenv.FAKE_REPLY
          and called == ["claude", "openai"], "stream_fallback_before_first_chunk", (items, err, called))
    rows = await usage_rows()
    check(len(rows) == n0 + 1 and rows[-1]["provider"] == "openai" and rows[-1]["fallback_from"] == "claude",
          "run_stream: tracks usage with fallback_from", rows[-1:])

    for kind in ("refusal", "empty"):
        health.reset()
        items, err, called = await go_stream(claude=kind)
        last = items[-1] if items else None
        check(err is None and isinstance(last, runner.RunResult) and last.target.provider == "openai"
              and last.fallback_from == "claude" and called == ["claude", "openai"],
              f"run_stream: {kind} before any chunk falls back", (items, err, called))

    health.reset()
    n0 = len(await usage_rows())
    items, err, called = await go_stream(claude="fail_mid_stream")
    check(isinstance(err, stubenv.FakeAPIError) and len(items) == 1 and isinstance(items[0], str)
          and called == ["claude"], "stream_no_fallback_after_chunk: one chunk, then the error; no openai call",
          (items, err, called))
    check(len(await usage_rows()) == n0, "stream_no_fallback_after_chunk: no usage row")

    # a provider failure after the first chunk still counts: status records it, and two in a row cool claude
    health.reset()
    await execute_status_delete()
    items, err, called = await go_stream(claude="fail_mid_stream")
    st = await ai_settings.get_provider_status()
    check(isinstance(err, stubenv.FakeAPIError) and (st.get("claude") or {}).get("last_error"),
          "stream_mid_failure_recorded: claude last_error is persisted", st.get("claude"))
    check(health.is_available(T("claude", "claude-sonnet-5-5")),
          "stream_mid_failure_recorded: one server failure does not cool yet")
    items, err, called = await go_stream(claude="fail_mid_stream")
    check(isinstance(err, stubenv.FakeAPIError) and called == ["claude"]
          and not health.is_available(T("claude", "claude-sonnet-5-5")),
          "stream_mid_failure_recorded: a second mid-stream 503 cools claude (server streak)", (err, called))
    items, err, called = await go_stream()
    check(isinstance(items[-1] if items else None, runner.RunResult) and items[-1].target.provider == "openai"
          and "claude" not in called, "stream_mid_failure_recorded: the next stream skips the cooled claude", called)

    # an unusable answer after a chunk was yielded propagates instead of switching provider
    health.reset()
    from ai_providers.clients.base import get_client
    claude_client = get_client("claude")

    async def chunk_then_unusable(model, prompt, *, effort=None):
        yield "partial "
        raise UnusableAnswer("late")
    claude_client.stream = chunk_then_unusable
    try:
        items, err, called = await go_stream()
    finally:
        del claude_client.stream
    check(isinstance(err, UnusableAnswer) and items == ["partial "] and called == [],
          "stream_unusable_after_chunk: propagates, no other provider is called", (items, err, called))

    # R11 for streams too
    health.reset()
    await settings.save_panel("chat", two_claudes, "t6@x")
    stubenv.set_fake_ai(claude="billing")
    before = len(outbox_lines())
    items = [x async for x in runner.run_stream("chat", user_id=uid, prompt=Prompt("s", "u"))]
    called = [x.get("provider") for x in _outbox_ai_calls(before)]
    check(isinstance(items[-1], runner.RunResult) and items[-1].target.provider == "openai" and called == ["claude", "openai"],
          "recheck_availability: run_stream skips claude-haiku after a billing failure", called)

    health.reset()
    items, err, called = await go_stream(claude="bad_request")
    check(isinstance(err, stubenv.FakeAPIError) and items == [] and called == ["claude"],
          "run_stream: a request-level error propagates without fallback", (items, err, called))

    # status_persisted_redacted
    health.reset()
    await execute_status_delete()
    r, called = await go(claude="echo_key")
    st = await ai_settings.get_provider_status()
    err_text = (st.get("claude") or {}).get("last_error")
    check(isinstance(r, runner.RunResult) and err_text and "sk-e2e" not in err_text and "[redacted]" in err_text,
          "status_persisted_redacted: claude last_error has no key", err_text)
    check((st.get("openai") or {}).get("last_success_at") is not None, "status: openai last_success_at recorded", st)

    # no user: no usage row
    health.reset()
    stubenv.clear_fake_ai()
    n0 = len(await usage_rows())
    r = await runner.run("chat", user_id=None, call=runner.default_call(Prompt("s", "u"), "chat"))
    check(isinstance(r, runner.RunResult) and len(await usage_rows()) == n0, "run: user_id None tracks nothing")

    # the package exports the runner
    import ai_providers
    check(all(hasattr(ai_providers, n) for n in ("run", "run_stream", "Prompt", "Completion", "Target",
                                                  "AllProvidersFailed", "UnusableAnswer", "RunResult")),
          "ai_providers re-exports the runner API")


async def execute_status_delete():
    from sql.db import execute
    from sql.tables import ai_provider_status
    await execute(ai_provider_status.delete())


async def refresh_race_checks():
    """Task 7: load_panel must not overwrite a newer save_panel / clear_panel with a stale snapshot (in-memory store)."""
    from ai_providers import settings
    from ai_providers.types import FeatureSetting, Target

    T = Target
    store = settings.store
    orig = (store.list_feature_settings, store.upsert_feature_setting, store.delete_feature_setting)
    saved = (settings._env, dict(settings._env_units), settings._panel)
    rows: dict = {}
    ctl = {"hold": False, "reading": asyncio.Event(), "gate": asyncio.Event()}

    async def fake_list():
        snapshot = [dict(r) for r in rows.values()]   # what the database held when the read started
        if ctl["hold"]:
            ctl["reading"].set()
            await ctl["gate"].wait()                   # ... and the read finishes later
        return snapshot

    async def fake_upsert(feature, main_provider, main_model, backups, updated_by):
        rows[feature] = {"feature": feature, "main_provider": main_provider, "main_model": main_model,
                         "backups": backups}

    async def fake_delete(feature):
        return rows.pop(feature, None) is not None

    def arm():
        ctl.update(hold=True, reading=asyncio.Event(), gate=asyncio.Event())

    store.list_feature_settings, store.upsert_feature_setting, store.delete_feature_setting = (
        fake_list, fake_upsert, fake_delete)
    try:
        settings.set_panel_cache({})
        settings.reload_env({})
        x = FeatureSetting(T("openai", "gpt-4o"), (), "panel")
        y = FeatureSetting(T("claude", "claude-sonnet-5-5"), (), "panel")

        # a load that started before a newer save finishes after it: the save wins
        await settings.save_panel("chat", x, "t7@x")
        arm()
        task = asyncio.create_task(settings.load_panel())
        await ctl["reading"].wait()
        await settings.save_panel("chat", y, "t7@x")
        ctl["gate"].set()
        await task
        r = settings.resolve("chat")
        check(r.main == y.main and r.source == "panel", "refresh_race: a stale load does not overwrite a newer save", r)

        # ... and a newer clear
        arm()
        task = asyncio.create_task(settings.load_panel())
        await ctl["reading"].wait()
        await settings.clear_panel("chat")
        ctl["gate"].set()
        await task
        r = settings.resolve("chat")
        check(r.source == "default" and "chat" not in settings._panel,
              "refresh_race: a stale load does not bring back a cleared setting", r)

        # an undisturbed load still applies what is in the store
        ctl["hold"] = False
        rows["chat"] = {"feature": "chat", "main_provider": "openai", "main_model": "gpt-4o", "backups": None}
        await settings.load_panel()
        check(settings.resolve("chat").source == "panel" and settings.resolve("chat").main == T("openai", "gpt-4o"),
              "refresh_race: an undisturbed load applies the stored rows")
    finally:
        store.list_feature_settings, store.upsert_feature_setting, store.delete_feature_setting = orig
        settings._env, settings._panel = saved[0], saved[2]
        settings._env_units.clear()
        settings._env_units.update(saved[1])


ADMIN_FEATURES = ("chat", "insight_weekly", "insight_monthly", "insight_translation", "budget_suggestion",
                  "budget_auto_create", "transaction_text", "transaction_image", "transaction_audio")
ADMIN_PROVIDERS = ("openai", "gemini", "claude")
ADMIN_PW = "t7-admin-pass-1"


def make_admins(c, db, prefix, roles):
    """Insert our own admins (never the root admin: test_api trips its login lockout); returns {role: email}."""
    import uuid
    from datetime import UTC, datetime

    import admin_utils
    made = {}
    for role in roles:
        email = f"{prefix}-{role}-{uuid.uuid4().hex[:6]}@example.com"
        db.admins.insert_one({"_id": str(uuid.uuid4()), "name": f"{prefix} {role}", "email": email,
                              "password": admin_utils.get_password_hash(ADMIN_PW), "role": role,
                              "created_at": datetime.now(UTC), "last_login": None})
        made[role] = email
    return made


def admin_login(c, email):
    r = c.post("/api/admin/login", json={"email": email, "password": ADMIN_PW})
    return {"Authorization": "Bearer " + r.json()["access_token"]}


def admin_reset(c, headers):
    """Settings only through the admin API (the server has its own cache and health); fakes cleared."""
    stubenv.clear_fake_ai()
    for f in ADMIN_FEATURES:
        c.delete(f"/api/admin/ai/settings/{f}", headers=headers)
    for p in ADMIN_PROVIDERS:
        c.post(f"/api/admin/ai/test/{p}", headers=headers, json={})


async def admin_api_checks():
    """Task 7: /api/admin/ai settings, status and test, over HTTP against the stubbed server."""
    from datetime import UTC, datetime, timedelta

    import httpx
    from sqlalchemy import delete, insert

    from ai_providers import health, runner, settings
    from ai_providers.types import FeatureSetting, Prompt, Target
    from sql.db import execute
    from sql.tables import ai_provider_status, ai_usage, users

    T = Target
    c = httpx.Client(base_url="http://127.0.0.1:8765", timeout=60)
    db = __import__("pgcompat").get_db()
    made = make_admins(c, db, "t7", ("admin", "moderator", "super_admin"))

    def login(role):
        return admin_login(c, made[role])

    def reset():
        admin_reset(c, AD)

    uid = "t7-status-user"
    AD = MOD = SUP = {}
    try:
        AD, MOD, SUP = login("admin"), login("moderator"), login("super_admin")
        reset()

        # --- GET /settings
        r = c.get("/api/admin/ai/settings", headers=MOD)
        body = r.json() if r.status_code == 200 else {}
        feats = {f["key"]: f for f in body.get("features", [])}
        provs = {p["id"]: p for p in body.get("providers", [])}
        chat = feats.get("chat", {})
        check(r.status_code == 200 and set(feats) == set(ADMIN_FEATURES) and len(body["features"]) == 9
              and chat["effective"]["source"] == "default" and provs.get("claude", {}).get("configured") is True,
              "settings_get_moderator_ok", f"{r.status_code} {r.text[:300]}")
        check(set(provs) == set(ADMIN_PROVIDERS) and all(set(p) == {"id", "label", "configured"} for p in provs.values()),
              "settings_get: provider shape (known models are per feature)", provs)
        check(chat.get("effective") == {"main": {"provider": "gemini", "model": "gemini-2.5-flash"},
                                        "backups": None, "source": "default"}
              and chat.get("panel") is None and chat.get("allowed") == ["openai", "gemini", "claude"]
              and chat.get("label")
              and set(chat) == {"key", "label", "allowed", "effective", "default_chain", "panel", "known_models"},
              "settings_get: feature shape", chat)
        # F1: each feature row lists the models its picker offers, per allowed provider
        audio = feats["transaction_audio"]
        check(audio.get("known_models") == {"openai": ["whisper-1"], "gemini": ["gemini-2.5-flash", "gemini-2.5-pro"]},
              "settings_get_known_models_per_feature: audio offers only whisper-1 on openai", audio.get("known_models"))
        check(chat.get("known_models") == {"openai": ["gpt-4o-mini", "gpt-4o"], "gemini": ["gemini-2.5-flash", "gemini-2.5-pro"],
                                           "claude": ["claude-sonnet-5-5", "claude-haiku-5-5", "claude-opus-5-5"]}
              and all(set(f["known_models"]) == set(f["allowed"]) for f in feats.values())
              and not any("whisper-1" in ms for k, f in feats.items() if k != "transaction_audio"
                          for ms in f["known_models"].values()),
              "settings_get_known_models_per_feature: other features never offer whisper-1",
              {k: f.get("known_models") for k, f in feats.items()})
        check(chat.get("default_chain") == [{"provider": "openai", "model": "gpt-4o-mini"},
                                            {"provider": "claude", "model": "claude-sonnet-5-5"}],
              "settings_get: default_chain is what null backups expand to", chat.get("default_chain"))
        check(feats["transaction_audio"]["allowed"] == ["openai", "gemini"]
              and [t["provider"] for t in feats["transaction_audio"]["default_chain"]] == ["gemini"],
              "settings_get: audio never offers or chains claude", feats["transaction_audio"])
        check("sk-" not in r.text and "AIza" not in r.text, "settings_get: no key material in the response")
        r2 = c.get("/api/admin/ai/settings")
        check(r2.status_code in (401, 403), "settings_get: no token is refused", r2.status_code)

        # --- PUT /settings/{feature}
        put = lambda feature, body, h=None: c.put(f"/api/admin/ai/settings/{feature}", headers=h or AD, json=body)  # noqa: E731
        claude = {"provider": "claude", "model": "claude-sonnet-5-5"}
        r = put("chat", {"main": claude, "backups": []})
        j = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and j.get("effective") == {"main": claude, "backups": [], "source": "panel"}
              and j.get("warnings") == [] and j.get("panel") == {"main": claude, "backups": [], "source": "panel"},
              "settings_put_admin_ok_and_applied: PUT result", f"{r.status_code} {r.text[:300]}")
        r = c.get("/api/admin/ai/settings", headers=MOD)
        chat = {f["key"]: f for f in r.json()["features"]}["chat"]
        check(chat["effective"]["source"] == "panel" and chat["effective"]["main"] == claude
              and chat["effective"]["backups"] == [], "settings_put_admin_ok_and_applied: GET shows source panel", chat)
        check({f["key"]: f for f in r.json()["features"]}["insight_weekly"]["effective"]["source"] == "default",
              "settings_put: other features untouched")

        r = put("chat", {"main": claude, "backups": []}, MOD)
        check(r.status_code == 403, "settings_put_moderator_forbidden", r.status_code)
        r = c.put("/api/admin/ai/settings/chat", json={"main": claude, "backups": []})
        check(r.status_code in (401, 403), "settings_put: no token is refused", r.status_code)

        r = put("transaction_audio", {"main": claude, "backups": None})
        check(r.status_code == 422 and isinstance(r.json().get("detail"), list)
              and any("claude" in str(m).lower() for m in r.json()["detail"]),
              "settings_put_claude_audio_422", f"{r.status_code} {r.text[:200]}")
        r = put("chat", {"main": {"provider": "openai", "model": "gpt-4o"}, "backups": [
            {"provider": "openai", "model": "gpt-4o"}]})
        check(r.status_code == 422, "settings_put_duplicates_422: backup repeats the main", f"{r.status_code} {r.text[:200]}")
        r = put("chat", {"main": claude, "backups": [{"provider": "gemini", "model": "gemini-2.5-pro"},
                                                      {"provider": "gemini", "model": "gemini-2.5-pro"}]})
        check(r.status_code == 422, "settings_put_duplicates_422: a backup repeats an earlier backup", f"{r.status_code} {r.text[:200]}")
        chat = {f["key"]: f for f in c.get("/api/admin/ai/settings", headers=AD).json()["features"]}["chat"]
        check(chat["effective"]["main"] == claude and chat["effective"]["backups"] == [],
              "settings_put: a rejected PUT leaves the saved setting alone", chat["effective"])

        r = put("nope", {"main": claude, "backups": None})
        check(r.status_code == 404, "settings_put: unknown feature is 404", r.status_code)
        bad_bodies = {
            "unknown provider": {"main": {"provider": "bogus", "model": "x"}, "backups": None},
            "empty model": {"main": {"provider": "claude", "model": "   "}, "backups": None},
            "missing model": {"main": {"provider": "claude"}, "backups": None},
            "missing main": {"backups": None},
            "unknown field": {"main": claude, "backups": None, "extra": 1},
            "unknown nested field": {"main": {**claude, "key": "x"}, "backups": None},
            "backups not a list": {"main": claude, "backups": "none"},
            "model not a string": {"main": {"provider": "claude", "model": 5}, "backups": None},
            "bad backup": {"main": claude, "backups": [{"provider": "bogus", "model": "x"}]},
        }
        for label, b in bad_bodies.items():
            r = put("chat", b)
            check(r.status_code == 422, f"settings_put_422: {label}", f"{r.status_code} {r.text[:160]}")
        r = c.put("/api/admin/ai/settings/chat", headers=AD, content=b"not json")
        check(r.status_code == 422, "settings_put_422: not JSON", r.status_code)

        # F1: a model the feature cannot use is a 422 with a readable message (shown inline by the admin page)
        r = put("transaction_audio", {"main": {"provider": "openai", "model": "gpt-4o-mini"}, "backups": None})
        d = r.json().get("detail") if r.status_code == 422 else None
        check(r.status_code == 422 and isinstance(d, list) and len(d) == 1 and isinstance(d[0], str)
              and "speech-to-text" in d[0] and "gpt-4o-mini" in d[0],
              "settings_put_model_mismatch_422: audio on openai gpt-4o-mini", f"{r.status_code} {r.text[:300]}")
        r = put("chat", {"main": claude, "backups": [{"provider": "openai", "model": "whisper-1"}]})
        d = r.json().get("detail") if r.status_code == 422 else None
        check(r.status_code == 422 and isinstance(d, list) and len(d) == 1 and d[0].startswith("backup 1")
              and "voice input" in d[0], "settings_put_model_mismatch_422: whisper-1 as a chat backup", f"{r.status_code} {r.text[:300]}")
        r = put("transaction_audio", {"main": {"provider": "openai", "model": "gpt-4o-transcribe"},
                                      "backups": [{"provider": "gemini", "model": "gemini-2.5-pro"}]})
        check(r.status_code == 200, "settings_put: audio accepts an openai *transcribe* model and any gemini model",
              f"{r.status_code} {r.text[:300]}")
        c.delete("/api/admin/ai/settings/transaction_audio", headers=AD)

        # F7: a model name that looks like an API key is a 422 that never echoes it, and nothing is stored or logged
        secret = "sk-proj-t7PASTEDkey1234567890"
        r = put("chat", {"main": {"provider": "openai", "model": secret}, "backups": None})
        check(r.status_code == 422 and secret not in r.text and "API key" in r.text,
              "settings_put_key_like_model_422: rejected without echoing the key", f"{r.status_code} {r.text[:300]}")
        r = put("chat", {"main": claude, "backups": [{"provider": "gemini", "model": "AIzaSyT7pastedKEY12345"}]})
        check(r.status_code == 422 and "AIzaSy" not in r.text, "settings_put_key_like_model_422: a key-like backup too",
              f"{r.status_code} {r.text[:300]}")
        g = c.get("/api/admin/ai/settings", headers=AD)
        check(secret not in g.text and "AIzaSyT7" not in g.text
              and {f["key"]: f for f in g.json()["features"]}["chat"]["effective"]["main"] == claude,
              "settings_put_key_like_model_422: the saved setting is unchanged and no key is returned", g.text[:300])

        r = put("chat", {"main": {"provider": "openai", "model": " gpt-4o "}, "backups": None})
        j = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and j["effective"]["main"]["model"] == "gpt-4o" and j["effective"]["backups"] is None
              and [t["provider"] for t in j["default_chain"]] == ["gemini", "claude"],
              "settings_put: null backups means default; model is trimmed; default_chain follows the main", f"{r.status_code} {r.text[:300]}")
        r = put("chat", {"main": {"provider": "openai", "model": "gpt-4o"},
                         "backups": [{"provider": "claude", "model": "claude-haiku-5-5"}]})
        check(r.status_code == 200 and r.json()["effective"]["backups"] == [{"provider": "claude", "model": "claude-haiku-5-5"}],
              "settings_put: explicit backups are stored", r.text[:300])

        # --- unconfigured main: the handler's warnings come from setting_warnings (the server has every key)
        w = settings.setting_warnings(FeatureSetting(T("claude", "claude-sonnet-5-5"), (), "panel"),
                                      configured=lambda p: p != "claude")
        check(len(w) == 1 and "claude" in w[0].lower(), "unconfigured_warning", w)

        # --- DELETE
        r = c.delete("/api/admin/ai/settings/chat", headers=MOD)
        check(r.status_code == 403, "settings_delete: moderator forbidden", r.status_code)
        r = c.delete("/api/admin/ai/settings/nope", headers=AD)
        check(r.status_code == 404, "settings_delete: unknown feature is 404", r.status_code)
        r = c.delete("/api/admin/ai/settings/chat", headers=AD)
        j = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and j.get("effective", {}).get("source") in ("server", "default")
              and j.get("panel") is None, "settings_delete_resets", f"{r.status_code} {r.text[:300]}")
        chat = {f["key"]: f for f in c.get("/api/admin/ai/settings", headers=AD).json()["features"]}["chat"]
        check(chat["effective"]["source"] in ("server", "default") and chat["panel"] is None,
              "settings_delete_resets: GET agrees", chat)
        r = c.delete("/api/admin/ai/settings/chat", headers=AD)
        check(r.status_code == 200, "settings_delete: deleting again is harmless", r.status_code)

        # --- POST /test/{provider}
        r = c.post("/api/admin/ai/test/openai", headers=MOD, json={})
        check(r.status_code == 403, "test: moderator forbidden", r.status_code)
        r = c.post("/api/admin/ai/test/bogus", headers=AD, json={})
        check(r.status_code == 404, "test: unknown provider is 404", r.status_code)
        r = c.post("/api/admin/ai/test/openai", headers=AD, json={"model": "gpt-4o-mini", "x": 1})
        check(r.status_code == 422, "test: unknown field is 422", r.status_code)
        r = c.post("/api/admin/ai/test/openai", headers=AD, json={"model": "  "})
        check(r.status_code == 422, "test: empty model is 422", r.status_code)
        before = len(outbox_lines())
        r = c.post("/api/admin/ai/test/claude", headers=AD, json={"model": "claude-haiku-5-5"})
        calls = _outbox_ai_calls(before)
        check(r.status_code == 200 and r.json() == {"ok": True} and [x.get("model") for x in calls] == ["claude-haiku-5-5"],
              "test: success pings the given model", f"{r.status_code} {r.text} {calls}")
        before = len(outbox_lines())
        r = c.post("/api/admin/ai/test/openai", headers=AD)
        calls = _outbox_ai_calls(before)
        check(r.status_code == 200 and r.json() == {"ok": True} and [x.get("model") for x in calls] == ["gpt-4o-mini"],
              "test: no body pings the provider's default model", f"{r.status_code} {r.text} {calls}")

        def status_of(provider):
            body = c.get("/api/admin/ai/status", headers=MOD).json()
            return {p["id"]: p for p in body["providers"]}[provider]

        s = status_of("openai")
        check(s["state"] == "working" and s["configured"] is True and s["last_success_at"],
              "status: a successful test makes the provider working", s)

        # --- status after a failed test, and redaction
        stubenv.set_fake_ai(claude="echo_key")
        r = c.post("/api/admin/ai/test/claude", headers=AD, json={})
        j = r.json()
        check(r.status_code == 200 and j.get("ok") is False and "sk-e2e" not in r.text and j.get("error"),
              "status_shape_and_redaction: the test reports a redacted error", r.text)
        rs = c.get("/api/admin/ai/status", headers=MOD)
        sj = rs.json()
        s = {p["id"]: p for p in sj["providers"]}["claude"]
        check(rs.status_code == 200 and "sk-e2e" not in rs.text and "sk-ant" not in rs.text and "AIza" not in rs.text
              and s["state"] == "failing" and "[redacted]" in (s["last_error"] or ""),
              "status_shape_and_redaction: status is redacted and failing", f"{rs.status_code} {s}")
        check([p["id"] for p in sj["providers"]] == list(ADMIN_PROVIDERS)
              and all(set(p) == {"id", "label", "configured", "state", "cooling_until", "cooling_models", "last_error",
                                 "last_error_at", "last_success_at", "backup_answers_24h"} for p in sj["providers"])
              and all(p["state"] in ("working", "failing", "cooling", "unused") for p in sj["providers"])
              and s["cooling_until"] is None and s["cooling_models"] == [] and s["last_error_at"],
              "status_shape_and_redaction: status shape", sj)
        r = c.get("/api/admin/ai/status")
        check(r.status_code in (401, 403), "status: no token is refused", r.status_code)
        stubenv.clear_fake_ai()

        # a failed test does not take the provider out of rotation; a success afterwards puts it back to working
        r = c.post("/api/admin/ai/test/claude", headers=AD, json={})
        s = status_of("claude")
        check(r.json() == {"ok": True} and s["state"] == "working" and s["cooling_until"] is None,
              "test: a later success makes the provider working again", s)

        # not configured: no SDK call (R10)
        import ai_admin_routes
        from ai_providers.clients.base import get_client
        gc = get_client("claude")
        orig_cfg, orig_ping = gc.configured, gc.ping
        pings = []

        async def ping_spy(model):
            pings.append(model)

        gc.configured = lambda: False
        gc.ping = ping_spy
        try:
            out = await ai_admin_routes.test_provider("claude", ai_admin_routes.TestBody(), {"_id": "x", "email": "x"})
        finally:
            gc.configured, gc.ping = orig_cfg, orig_ping
        check(out == {"ok": False, "error": "not configured"} and pings == [],
              "test: an unconfigured provider answers 'not configured' without calling the SDK", (out, pings))

        # --- status_backup_count: one fallback from claude, then one old row and one other provider
        health.reset()
        await execute(delete(users).where(users.c.id == uid))
        await execute(insert(users).values(id=uid, name="t7", email="t7-status@x.test", password="x"))
        n0 = status_of("claude")["backup_answers_24h"]
        g0 = status_of("gemini")["backup_answers_24h"]
        saved = (settings._env, dict(settings._env_units), settings._panel)
        try:
            settings.reload_env({})
            settings.set_panel_cache({"chat": FeatureSetting(T("claude", "claude-sonnet-5-5"), None, "panel")})
            stubenv.set_fake_ai(claude="billing")
            res = await runner.run("chat", user_id=uid, call=runner.default_call(Prompt("s", "u"), "chat"))
        finally:
            stubenv.clear_fake_ai()
            settings._env, settings._panel = saved[0], saved[2]
            settings._env_units.clear()
            settings._env_units.update(saved[1])
            health.reset()
        check(res.fallback_from == "claude", "status_backup_count: the in-process run fell back from claude", res)
        await execute(insert(ai_usage).values(
            id="t7-old-row", user_id=uid, feature_type="chat", provider="openai", model_name="gpt-4o-mini",
            fallback_from="gemini", created_at=datetime.now(UTC) - timedelta(hours=30)))
        s = status_of("claude")
        check(s["backup_answers_24h"] == n0 + 1 and s["backup_answers_24h"] >= 1,
              "status_backup_count: claude counts the fallback", s)
        check(status_of("gemini")["backup_answers_24h"] == g0, "status_backup_count: rows older than 24 h are not counted",
              status_of("gemini"))
        check(s["state"] == "failing" and "credit balance" in (s["last_error"] or ""),
              "status: the runner's billing failure shows as the last error", s)

        # --- admin_logs_written
        r = c.get("/api/admin/logs", headers=SUP, params={"limit": 100})
        logs = r.json() if r.status_code == 200 else []
        mine = [x for x in logs if x["admin_email"] == made["admin"]]
        upd = [x for x in mine if x["action"] == "ai_setting_update"]
        rst = [x for x in mine if x["action"] == "ai_setting_reset"]
        check(any("chat: main=openai:gpt-4o" in (x.get("details") or "") for x in upd)
              and any((x.get("details") or "").startswith("chat:") for x in rst)
              and not any("sk-" in (x.get("details") or "") for x in mine),
              "admin_logs_written: ai_setting_update and ai_setting_reset are logged", [x["action"] for x in mine][:6])
        n_logs = len(mine)
        c.delete("/api/admin/ai/settings/chat", headers=AD)  # nothing stored now: nothing to log
        r = c.get("/api/admin/logs", headers=SUP, params={"limit": 100})
        check(len([x for x in r.json() if x["admin_email"] == made["admin"]]) == n_logs,
              "admin_logs_written: resetting a setting that has no panel row writes no log entry")
    finally:
        try:
            reset()
        finally:
            health.reset()
            try:
                await execute(delete(users).where(users.c.id == uid))  # cascades to its ai_usage rows
                await execute(ai_provider_status.delete())
            finally:
                db.admins.delete_many({"email": {"$in": list(made.values())}})
                c.close()


def sse_frames(r):
    return [json.loads(line[6:]) for line in r.text.split("\n") if line.startswith("data: ")]


async def chat_checks():
    """Task 8: /api/chat/stream runs on the provider runner (one chatbot; ai_provider is validated and ignored)."""
    import uuid
    from datetime import UTC, datetime, timedelta

    import httpx
    from sqlalchemy import delete, func, select

    from sql.db import execute, fetch_all, fetch_value
    from sql.tables import ai_usage, chat_messages, chat_sessions, users

    c = httpx.Client(base_url="http://127.0.0.1:8765", timeout=60)
    db = __import__("pgcompat").get_db()
    made = make_admins(c, db, "t8", ("admin",))
    email, pw = f"t8-chat-{uuid.uuid4().hex[:6]}@example.com", "T8ChatPass123"
    uid = None
    AD = {}
    try:
        AD = admin_login(c, made["admin"])
        admin_reset(c, AD)
        r = c.post("/api/auth/register", json={"name": "T8 Chat", "email": email, "password": pw})
        db.users.update_one({"email": email}, {"$set": {
            "is_verified": True, "subscription_type": "premium",
            "subscription_expires_at": datetime.now(UTC) + timedelta(days=30)}})
        uid = db.users.find_one({"email": email})["_id"]
        U = {"Authorization": "Bearer " + c.post("/api/auth/login", json={"email": email, "password": pw}).json()["access_token"]}
        r = c.post("/api/transactions", headers=U, json={
            "type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries", "amount": 12.5,
            "currency": "usd", "date": datetime.now(UTC).isoformat(), "description": "t8 groceries"})
        check(r.status_code == 200, "chat setup: a premium user with one transaction", f"{r.status_code} {r.text[:200]}")

        def chat(body):
            before = len(outbox_lines())
            resp = c.post("/api/chat/stream", headers=U, json=body)
            frames = sse_frames(resp) if resp.status_code == 200 else []
            return resp, frames, [x.get("provider") for x in _outbox_ai_calls(before)]

        def normal_reply(resp, frames):
            chunks = [f for f in frames[:-1] if f.get("done") is False and f.get("chunk")]
            last = frames[-1] if frames else {}
            return (resp.status_code == 200 and chunks and len(chunks) == len(frames) - 1
                    and not any("error" in f for f in frames) and last.get("done") is True
                    and last.get("full_response") == "".join(f["chunk"] for f in chunks)
                    and "Fake answer" in last["full_response"])

        async def n_messages():
            return await fetch_value(select(func.count()).select_from(
                chat_messages.join(chat_sessions, chat_messages.c.session_id == chat_sessions.c.id))
                .where(chat_sessions.c.user_id == uid))

        async def usage():
            return await fetch_all(select(ai_usage).where(ai_usage.c.user_id == uid).order_by(ai_usage.c.created_at))

        claude = {"provider": "claude", "model": "claude-sonnet-5-5"}
        put = lambda body: c.put("/api/admin/ai/settings/chat", headers=AD, json=body)  # noqa: E731

        # --- chat = claude from the panel
        r = put({"main": claude, "backups": None})
        check(r.status_code == 200, "chat: PUT chat = claude", f"{r.status_code} {r.text[:200]}")
        m0, u0 = await n_messages(), len(await usage())
        r, fr, called = chat({"message": "How much did I spend?"})
        check(normal_reply(r, fr) and called == ["claude"], "chat_uses_panel_provider",
              f"{r.status_code} {called} {fr[-2:]}")
        rows = await usage()
        check(len(rows) == u0 + 1 and rows[-1]["provider"] == "claude" and rows[-1]["feature_type"] == "chat"
              and rows[-1]["model_name"] == "claude-sonnet-5-5" and rows[-1]["fallback_from"] is None,
              "chat: exactly one usage row per exchange, from the runner (no duplicate tracking)",
              [(x["provider"], x["model_name"], x["fallback_from"]) for x in rows[u0:]])
        check(await n_messages() == m0 + 2, "chat: a successful exchange is saved to history", (m0, await n_messages()))

        for old in ("gemini", "openai"):
            r, fr, called = chat({"message": "hi", "ai_provider": old})
            check(normal_reply(r, fr) and called == ["claude"], f"chat_ignores_ai_provider_field: {old}",
                  f"{r.status_code} {called} {fr[-1:]}")

        r = c.post("/api/chat/stream", headers=U, json={"message": "hi", "ai_provider": "bard"})
        check(r.status_code == 422, "chat_invalid_ai_provider_422", f"{r.status_code} {r.text[:200]}")

        # --- claude has no credit: the default backups answer and the app sees a normal reply
        stubenv.set_fake_ai(claude="billing")
        u0 = len(await usage())
        r, fr, called = chat({"message": "hi"})
        check(normal_reply(r, fr) and called == ["claude", "openai"], "chat_fallback_invisible",
              f"{r.status_code} {called} {fr[-2:]}")
        rows = await usage()
        check(len(rows) == u0 + 1 and rows[-1]["provider"] == "openai" and rows[-1]["fallback_from"] == "claude",
              "chat_fallback_invisible: the usage row names the answering provider and fallback_from",
              [(x["provider"], x["fallback_from"]) for x in rows[u0:]])
        admin_reset(c, AD)

        # --- every provider fails: today's error frame, nothing saved, no usage row
        r = put({"main": claude, "backups": []})
        stubenv.set_fake_ai(claude="billing")
        m0, u0 = await n_messages(), len(await usage())
        r, fr, called = chat({"message": "hi"})
        last = fr[-1] if fr else {}
        check(r.status_code == 200 and len(fr) == 1 and last.get("done") is True and last.get("error")
              and "credit" not in r.text and called == ["claude"],
              "chat_all_fail_error_frame_no_history: one error frame", f"{r.status_code} {called} {fr}")
        check(await n_messages() == m0 and len(await usage()) == u0,
              "chat_all_fail_error_frame_no_history: no history, no usage row", (m0, u0))
        admin_reset(c, AD)

        # --- the provider fails after the first chunk: chunks, then the error frame; nothing saved
        put({"main": claude, "backups": None})
        stubenv.set_fake_ai(claude="fail_mid_stream")
        m0 = await n_messages()
        r, fr, called = chat({"message": "hi"})
        check(r.status_code == 200 and len(fr) >= 2 and fr[0].get("chunk") and fr[-1].get("error")
              and fr[-1].get("done") is True and called == ["claude"],
              "chat: a mid-stream failure ends with the error frame (no second provider)", f"{called} {fr}")
        check(await n_messages() == m0, "chat: a mid-stream failure is not saved to history")
        admin_reset(c, AD)

        # --- refresh-data accepts and ignores ai_provider
        for q, want in (({}, 200), ({"ai_provider": "gemini"}, 200), ({"ai_provider": "openai"}, 200),
                        ({"ai_provider": "bard"}, 422)):
            r = c.post("/api/chat/refresh-data", headers=U, params=q)
            check(r.status_code == want, f"chat refresh-data {q or 'no ai_provider'} -> {want}", f"{r.status_code} {r.text[:200]}")

        await _chat_inprocess_checks(uid)
    finally:
        try:
            if AD:
                admin_reset(c, AD)
        finally:
            try:
                if uid:
                    await execute(delete(users).where(users.c.id == uid))  # cascades to chat and ai_usage rows
            finally:
                db.admins.delete_many({"email": {"$in": list(made.values())}})
                c.close()


async def _chat_inprocess_checks(uid):
    """FinancialChatbot.stream_chat in-process: prompt, temperatures, final usage, closing and runner outcomes."""
    from ai_chatbot import ChatServiceError, financial_chatbot
    from ai_providers import health, runner, settings
    from ai_providers.errors import AllProvidersFailed
    from ai_providers.types import Completion, Target

    saved = (settings._env, dict(settings._env_units), settings._panel)
    health.reset()
    stubenv.clear_fake_ai()
    try:
        settings.set_panel_cache({})
        settings.reload_env({})

        async def collect(**kw):
            items = []
            async for item in financial_chatbot.stream_chat(uid, "How much did I spend?", **kw):
                items.append(item)
            return items

        for style, temp in (("normal", 0.3), ("concise", 0.2), ("explanatory", 0.4), ("odd", 0.3)):
            items = await collect(response_style=style)
            cfg = stubenv.LAST_KWARGS["gemini"]["config"]
            check(cfg.temperature == temp and cfg.max_output_tokens == 4000,
                  f"chat prompt: {style} style sends temperature {temp} and max tokens 4000",
                  (cfg.temperature, cfg.max_output_tokens))
        sysmsg = cfg.system_instruction or ""
        user_msg = stubenv.LAST_KWARGS["gemini"]["contents"]
        check(sysmsg.startswith("You are Toe Pwar AI") and "Flow Finance AI" not in sysmsg
              and "How much did I spend?" in user_msg and "Name: T8 Chat" in user_msg,
              "chat prompt: persona Toe Pwar AI; the user prompt carries the profile and the question", sysmsg[:80])
        text = "".join(t for t, u in items if t)
        final = items[-1]
        check(final[0] == "" and final[1] == {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15,
                                               "model_name": "gemini-2.5-flash", "provider": "gemini",
                                               "fallback_from": None}
              and all(u is None for _, u in items[:-1]) and "Fake answer" in text,
              "chat stream_chat: chunks with None, then one final usage dict", items[-2:])

        await collect(chat_history=[{"role": "user", "content": "earlier question"},
                                    {"role": "assistant", "content": "earlier answer"}])
        user_msg = stubenv.LAST_KWARGS["gemini"]["contents"]
        check("You: earlier question" in user_msg and "Assistant: earlier answer" in user_msg,
              "chat prompt: the recent history is in the user prompt")

        # The runner is replaced to drive the outcomes the fakes can't reach directly.
        orig = runner.run_stream
        t = Target("claude", "claude-sonnet-5-5")
        closed = []

        def fake(*outcomes):
            async def run_stream(feature, *, user_id, prompt):
                try:
                    for o in outcomes:
                        if isinstance(o, BaseException):
                            raise o
                        yield o
                finally:
                    closed.append(feature)
            return run_stream

        try:
            runner.run_stream = fake("one", "two", runner.RunResult("onetwo", t, None, Completion("onetwo", 1, 1, "stop")))
            gen = financial_chatbot.stream_chat(uid, "hi")
            first = await gen.__anext__()
            await gen.aclose()
            check(first == ("one", None) and closed == ["chat"],
                  "chat: closing the chat stream early closes the runner stream at once", (first, closed))

            runner.run_stream = fake("partial", runner.RunResult("partial", t, "gemini", Completion("partial", 3, 2, "filtered")))
            try:
                items = await collect()
                err = None
            except Exception as e:  # noqa: BLE001
                items, err = [], e
            check(err is None and items[0] == ("partial", None) and items[-1][1]["provider"] == "claude"
                  and items[-1][1]["fallback_from"] == "gemini" and len(items) == 2,
                  "chat: a filtered ending after chunks ends the stream normally (text already sent stands)",
                  (items, err))

            runner.run_stream = fake(AllProvidersFailed([]))
            try:
                await collect()
                err = None
            except Exception as e:  # noqa: BLE001
                err = e
            check(isinstance(err, ChatServiceError) and err.user_message == ChatServiceError.DEFAULT_MESSAGE,
                  "chat: AllProvidersFailed becomes ChatServiceError with the default message", repr(err))
        finally:
            runner.run_stream = orig
    finally:
        stubenv.clear_fake_ai()
        health.reset()
        settings._env, settings._panel = saved[0], saved[2]
        settings._env_units.clear()
        settings._env_units.update(saved[1])


LONG_INSIGHT = "".join(
    f"## Section {n}\n" + "".join(f"- Point {n}.{i}: you spent $1{i}.00 on groceries this week.\n" for i in range(30))
    for n in range(4))  # about 6000 characters in 4 markdown sections: the chunked retry needs several chunks


async def insight_checks():
    """Task 9: insights run on the provider runner (one row per user, read across providers, translation)."""
    import uuid
    from datetime import UTC, datetime, timedelta

    import httpx
    from sqlalchemy import delete

    from sql.db import execute
    from sql.tables import users

    c = httpx.Client(base_url="http://127.0.0.1:8765", timeout=120)
    db = __import__("pgcompat").get_db()
    made = make_admins(c, db, "t9", ("admin",))
    AD = {}
    uids = []

    def premium_user(label, with_tx=True):
        email, pw = f"t9-{label}-{uuid.uuid4().hex[:6]}@example.com", "T9InsightPass123"
        c.post("/api/auth/register", json={"name": f"T9 {label}", "email": email, "password": pw})
        db.users.update_one({"email": email}, {"$set": {
            "is_verified": True, "subscription_type": "premium",
            "subscription_expires_at": datetime.now(UTC) + timedelta(days=30)}})
        uid = db.users.find_one({"email": email})["_id"]
        uids.append(uid)
        hdr = {"Authorization": "Bearer " + c.post("/api/auth/login", json={"email": email, "password": pw}).json()["access_token"]}
        if with_tx:
            c.post("/api/transactions", headers=hdr, json={
                "type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries", "amount": 12.5,
                "currency": "usd", "date": datetime.now(UTC).isoformat(), "description": "t9 groceries"})
        return uid, hdr

    def newest(uid, insight_type="weekly"):
        return db.insights.find_one({"user_id": uid, "insight_type": insight_type}, sort=[("generated_at", -1)])

    def n_rows(uid):
        return db.insights.count_documents({"user_id": uid})

    def put(feature, provider, model, backups=None):
        return c.put(f"/api/admin/ai/settings/{feature}", headers=AD,
                     json={"main": {"provider": provider, "model": model}, "backups": backups})

    def calls(before):
        return [x.get("provider") for x in _outbox_ai_calls(before)]

    try:
        AD = admin_login(c, made["admin"])
        admin_reset(c, AD)
        uid, U = premium_user("main")

        # --- regenerate ignores ai_provider: the insight_weekly setting decides, and the row names the answerer
        r = put("insight_weekly", "claude", "claude-sonnet-5-5")
        check(r.status_code == 200, "insights setup: PUT insight_weekly = claude", f"{r.status_code} {r.text[:200]}")
        before, rows0 = len(outbox_lines()), n_rows(uid)
        r = c.post("/api/insights/regenerate", headers=U, params={"ai_provider": "openai", "insight_type": "weekly"})
        row = newest(uid)
        check(r.status_code == 200 and row and row["ai_provider"] == "claude" and r.json().get("id") == row["_id"]
              and calls(before) == ["claude"] and n_rows(uid) == rows0 + 1,
              "insight_regenerate_uses_setting", f"{r.status_code} {r.text[:200]} {row and row['ai_provider']} {calls(before)}")
        claude_row = row

        # --- reads take the newest row across providers
        for p in ("gemini", "openai"):
            before = len(outbox_lines())
            r = c.get("/api/insights", headers=U, params={"ai_provider": p, "insight_type": "weekly"})
            check(r.status_code == 200 and claude_row and r.json().get("id") == claude_row["_id"] and calls(before) == [],
                  f"insight_get_ignores_provider: ai_provider={p}", f"{r.status_code} {r.text[:200]} {calls(before)}")
        r = c.get("/api/insights", headers=U, params={"ai_provider": "bard"})
        check(r.status_code == 422, "insights: an unknown ai_provider is still rejected (422)", r.status_code)

        # --- fallback: the stored provider is the one that answered
        stubenv.set_fake_ai(claude="billing")
        before = len(outbox_lines())
        r = c.post("/api/insights/regenerate", headers=U, params={"insight_type": "weekly"})
        row = newest(uid)
        check(r.status_code == 200 and row["ai_provider"] == "openai" and calls(before) == ["claude", "openai"],
              "insights: after a fallback the row names the answering provider", f"{r.status_code} {row['ai_provider']} {calls(before)}")
        admin_reset(c, AD)

        # --- translation on claude
        r = put("insight_translation", "claude", "claude-sonnet-5-5")
        check(r.status_code == 200, "insights setup: PUT insight_translation = claude", f"{r.status_code} {r.text[:200]}")
        before = len(outbox_lines())
        r = c.post("/api/insights/translate-myanmar", headers=U, params={"ai_provider": "openai", "insight_type": "weekly"})
        row = newest(uid)
        check(r.status_code == 200 and row.get("content_mm") and calls(before) == ["claude"],
              "translation_on_claude", f"{r.status_code} {r.text[:200]} {calls(before)} mm={bool(row.get('content_mm'))}")

        # --- translation cut off at the output limit: re-translated section by section
        long_id = "t9-long-" + uuid.uuid4().hex[:8]
        db.insights.insert_one({"_id": long_id, "user_id": uid, "ai_provider": "gemini", "insight_type": "weekly",
                                "content": LONG_INSIGHT, "content_mm": None, "is_placeholder": False,
                                "generated_at": datetime.now(UTC)})
        stubenv.set_fake_ai(claude="length_once")
        before = len(outbox_lines())
        r = c.post("/api/insights/translate-myanmar", headers=U, params={"insight_type": "weekly"})
        row = db.insights.find_one({"_id": long_id})
        n_calls = calls(before)
        check(r.status_code == 200 and row.get("content_mm") and len(n_calls) >= 3 and set(n_calls) == {"claude"},
              "translation_length_retry: the cut-off reply is retried in section chunks and content_mm is stored",
              f"{r.status_code} {r.text[:200]} calls={n_calls} mm={(row.get('content_mm') or '')[:60]!r}")
        check(row.get("content_mm") and row["content_mm"].count("Fake answer") == len(n_calls) - 1,
              "translation_length_retry: content_mm joins one translation per chunk (not the cut-off reply)",
              (row.get("content_mm") or "")[:200])
        stubenv.clear_fake_ai()

        # --- every provider fails: a stored placeholder is still shown (200), mirrors test_backend_r4
        uid2, U2 = premium_user("down")
        db.insights.insert_one({"_id": "t9-ph-" + uid2[:8], "user_id": uid2, "ai_provider": "gemini",
                                "insight_type": "weekly", "content": "## Welcome to Toe Pwar!", "is_placeholder": True,
                                "generated_at": datetime.now(UTC) - timedelta(days=1)})
        stubenv.set_fake_ai(openai="server", gemini="server", claude="server")
        r = c.get("/api/insights", headers=U2, params={"insight_type": "weekly", "ai_provider": "gemini"})
        check(r.status_code == 200 and "Welcome to Toe Pwar" in (r.json().get("content") or ""),
              "all_fail_returns_placeholder", f"{r.status_code} {r.text[:200]}")
        r = c.get("/api/insights", headers=U, params={"insight_type": "weekly"})
        check(r.status_code == 200 and r.json().get("id") == long_id, "all_fail: a stored real insight is shown (200)",
              f"{r.status_code} {r.text[:200]}")

        # --- nothing stored and every provider fails: today's mapping (503 / 429 / 503 for billing), never a 500
        uid3, U3 = premium_user("none")
        for kinds, want, label in (({"openai": "server", "gemini": "server", "claude": "server"}, 503, "server"),
                                   ({"openai": "rate_limit", "gemini": "rate_limit", "claude": "rate_limit"}, 429, "rate limit"),
                                   ({"openai": "billing", "gemini": "rate_limit", "claude": "server"}, 503, "billing")):
            admin_reset(c, AD)
            stubenv.set_fake_ai(**kinds)
            r = c.get("/api/insights", headers=U3, params={"insight_type": "weekly"})
            check(r.status_code == want and "credit" not in r.text and "quota" not in r.text,
                  f"insights: every provider failing ({label}) with nothing stored -> {want}", f"{r.status_code} {r.text[:200]}")
            if want == 429:
                check(r.headers.get("retry-after") == "60", "insights: the 429 carries Retry-After: 60", dict(r.headers))
        check(n_rows(uid3) == 0, "insights: nothing is stored when every provider failed", n_rows(uid3))
        admin_reset(c, AD)

        # --- a user without data gets a placeholder stored under the feature's current main provider
        uid4, U4 = premium_user("empty", with_tx=False)
        put("insight_monthly", "claude", "claude-sonnet-5-5")
        before = len(outbox_lines())
        r = c.get("/api/insights", headers=U4, params={"insight_type": "monthly", "ai_provider": "openai"})
        row = newest(uid4, "monthly")
        check(r.status_code == 200 and row and row["is_placeholder"] and row["ai_provider"] == "claude"
              and calls(before) == [], "insights: a placeholder is stored with the feature's main provider (no AI call)",
              f"{r.status_code} {row and (row['is_placeholder'], row['ai_provider'])} {calls(before)}")
        admin_reset(c, AD)

        # --- the manual weekly route generates once
        rows0 = n_rows(uid)
        before = len(outbox_lines())
        r = c.post("/api/insights/generate-weekly", headers=U)
        check(r.status_code == 200 and n_rows(uid) == rows0 + 1 and len(calls(before)) == 1,
              "insights: POST generate-weekly generates one insight (no loop over providers)",
              f"{r.status_code} {r.text[:200]} rows {rows0}->{n_rows(uid)} calls={calls(before)}")
        check(r.status_code == 200 and r.json().get("results") == {newest(uid)["ai_provider"]: "success"},
              "insights: generate-weekly results stay keyed by provider (the one that answered)", r.text[:200])
        stubenv.set_fake_ai(openai="rate_limit", gemini="rate_limit", claude="rate_limit")
        r = c.post("/api/insights/generate-weekly", headers=U)
        check(r.status_code == 200 and r.json().get("results") == {"gemini": "rate_limited"},
              "insights: generate-weekly, every provider rate limited -> {main provider: rate_limited}", r.text[:200])
        admin_reset(c, AD)

        await _insight_inprocess_checks(uid)
    finally:
        try:
            stubenv.clear_fake_ai()
            if AD:
                admin_reset(c, AD)
        finally:
            try:
                for u in uids:
                    await execute(delete(users).where(users.c.id == u))  # cascades to insights and ai_usage rows
            finally:
                db.admins.delete_many({"email": {"$in": list(made.values())}})
                c.close()


async def _insight_inprocess_checks(uid):
    """insights_service in-process: the jobs generate once per user in the background, prompts and token limits."""
    import insights_service as ins
    from ai_providers import health, runner, settings
    from ai_providers.types import FeatureSetting, Target
    from sql.db import fetch_all, fetch_value
    from sql.tables import insights as insights_t
    from sqlalchemy import func, select

    stubenv.patch_loaded_modules()
    saved = (settings._env, dict(settings._env_units), settings._panel)
    health.reset()
    stubenv.clear_fake_ai()
    orig_run, orig_list = runner.run, ins.users_db.list_fields
    runs = []

    async def spy(feature, **kw):
        runs.append((feature, kw.get("background"), kw.get("user_id")))
        return await orig_run(feature, **kw)

    async def only_our_user(fields, *where):
        return [u for u in await orig_list(fields, *where) if u["_id"] == uid]

    async def count(insight_type):
        return await fetch_value(select(func.count()).select_from(insights_t).where(
            insights_t.c.user_id == uid, insights_t.c.insight_type == insight_type))

    def use(feature, provider, model):
        settings.set_panel_cache({feature: FeatureSetting(Target(provider, model), None, "panel")})

    try:
        settings.set_panel_cache({})
        settings.reload_env({})
        runner.run, ins.users_db.list_fields = spy, only_our_user
        for label, job, itype, feature in (("weekly", ins.generate_weekly_insights_for_all_users, "weekly", "insight_weekly"),
                                           ("monthly", ins.generate_monthly_insights_for_all_users, "monthly", "insight_monthly")):
            n0 = await count(itype)
            runs.clear()
            await job()
            n1 = await count(itype)
            check(n1 == n0 + 1, f"job_generates_once_per_user: the {label} job inserts exactly 1 row", (n0, n1))
            check(runs == [(feature, True, uid)], f"job_generates_once_per_user: the {label} job runs {feature} once in the background",
                  runs)
        runner.run, ins.users_db.list_fields = orig_run, orig_list

        # prompts and token limits per answering provider (temperature 0.7 as before; never sent to Claude)
        for feature, gen, limits in (("insight_weekly", ins.generate_weekly_insight, {"openai": 2500, "gemini": 8192, "claude": 12000}),
                                     ("insight_monthly", ins.generate_monthly_insight, {"openai": 3000, "gemini": 8192, "claude": 12000})):
            for provider, model in (("openai", "gpt-4o-mini"), ("gemini", "gemini-2.5-flash"), ("claude", "claude-sonnet-5-5")):
                use(feature, provider, model)
                row = await gen(uid)
                kw = stubenv.LAST_KWARGS[provider]
                if provider == "openai":
                    got = (kw.get("max_completion_tokens"), kw.get("temperature"), kw["messages"][0]["content"][:40])
                elif provider == "gemini":
                    got = (kw["config"].max_output_tokens, kw["config"].temperature, (kw["config"].system_instruction or "")[:40])
                else:
                    got = (kw.get("max_tokens"), kw.get("temperature", "absent"), (kw.get("system") or "")[:40])
                want_temp = "absent" if provider == "claude" else 0.7
                persona = "You are Toe Pwar AI"  # F9: weekly too (was "Flow Finance AI")
                check(row and row["ai_provider"] == provider and got[0] == limits[provider] and got[1] == want_temp
                      and got[2].startswith(persona) and kw.get("model") == model,
                      f"insights prompt: {feature} on {provider} sends max tokens {limits[provider]}, temperature {want_temp}",
                      (row and row.get("ai_provider"), got, kw.get("model")))

        check("Flow Finance AI" not in open(ins.__file__, encoding="utf-8").read(),
              "insights persona: no 'Flow Finance AI' left in insights_service (F9)")

        # translation: per-provider limits, temperature 0.3 as before, the default model is gemini-2.5-pro
        settings.set_panel_cache({})
        await ins.translate_insight_to_myanmar("## Hi\nYou spent $5.", user_id=uid, is_placeholder=False)
        cfg = stubenv.LAST_KWARGS["gemini"]["config"]
        check(stubenv.LAST_KWARGS["gemini"]["model"] == "gemini-2.5-pro" and cfg.max_output_tokens == 32768
              and cfg.temperature == 0.3, "translation: built-in gemini-2.5-pro, 32768 tokens, temperature 0.3",
              (stubenv.LAST_KWARGS["gemini"]["model"], cfg.max_output_tokens, cfg.temperature))
        use("insight_translation", "openai", "gpt-4o-mini")
        await ins.translate_insight_to_myanmar("## Hi\nYou spent $5.", user_id=uid, is_placeholder=False)
        kw = stubenv.LAST_KWARGS["openai"]
        check(kw.get("max_completion_tokens") == 8000 and kw.get("temperature") == 0.3, "translation: openai 8000 tokens, temperature 0.3",
              (kw.get("max_completion_tokens"), kw.get("temperature")))
        use("insight_translation", "claude", "claude-sonnet-5-5")
        await ins.translate_insight_to_myanmar("## Hi\nYou spent $5.", user_id=uid, is_placeholder=False)
        kw = stubenv.LAST_KWARGS["claude"]
        check(kw.get("max_tokens") == 32000 and "temperature" not in kw, "translation: claude 32000 tokens, no temperature",
              (kw.get("max_tokens"), kw.get("temperature")))
        check(not hasattr(ins, "TRANSLATION_GEMINI_MODEL"), "translation: the hard-coded TRANSLATION_GEMINI_MODEL is gone")

        # cut off once on claude: the chunked retry runs on claude too; usage is tracked once, tokens summed
        from sql.tables import ai_usage

        async def translation_usage():
            return await fetch_all(select(ai_usage).where(ai_usage.c.user_id == uid,
                                                          ai_usage.c.feature_type == "translation"))

        async def new_usage(seen):
            return [r for r in await translation_usage() if r["id"] not in seen]

        health.reset()
        seen = {r["id"] for r in await translation_usage()}
        stubenv.set_fake_ai(claude="length_once")
        before = len(outbox_lines())
        mm = await ins.translate_insight_to_myanmar(LONG_INSIGHT, user_id=uid, is_placeholder=False)
        called = [x.get("provider") for x in _outbox_ai_calls(before)]
        new = await new_usage(seen)
        check(called == ["claude"] * 5 and mm.count("Fake answer") == 4,
              "translation: the cut-off retry runs on the same provider (one attempt + 4 chunks)", (called, mm[:80]))
        check(len(new) == 1 and new[0]["provider"] == "claude" and new[0]["input_tokens"] == 50
              and new[0]["output_tokens"] == 25,
              "translation: one usage row for the whole retry, tokens summed over the 5 requests",
              [(r["provider"], r["input_tokens"], r["output_tokens"]) for r in new])

        # a chunk still cut off: the next provider translates the whole text (never mixing providers)
        seen = {r["id"] for r in await translation_usage()}
        stubenv.set_fake_ai(claude={"kind": "length_once", "times": 10})
        before = len(outbox_lines())
        try:
            mm = await ins.translate_insight_to_myanmar(LONG_INSIGHT, user_id=uid, is_placeholder=False)
            err = None
        except Exception as e:  # noqa: BLE001
            mm, err = "", e
        called = [x.get("provider") for x in _outbox_ai_calls(before)]
        check(err is None and called == ["claude", "claude", "openai"] and mm == stubenv.FAKE_REPLY,
              "translation: a chunk still cut off moves to the backup, which answers the whole text alone",
              (called, repr(err), mm[:80]))
        rows = await new_usage(seen)
        check([(r["provider"], r["fallback_from"]) for r in rows] == [("openai", "claude")],
              "translation: the backup's usage row names fallback_from=claude",
              [(r["provider"], r["fallback_from"]) for r in rows])

        # ... and with no backups it still fails as InsightAIError (nothing cached, as before)
        settings.set_panel_cache({"insight_translation": FeatureSetting(Target("claude", "claude-sonnet-5-5"), (), "panel")})
        health.reset()
        stubenv.set_fake_ai(claude={"kind": "length_once", "times": 10})
        try:
            await ins.translate_insight_to_myanmar(LONG_INSIGHT, user_id=uid, is_placeholder=False)
            err = None
        except Exception as e:  # noqa: BLE001
            err = e
        check(isinstance(err, ins.InsightAIError) and err.provider == "claude" and not ins.is_rate_limit_error(err)
              and not ins.is_billing_error(err),
              "translation: no backups and a chunk still cut off -> InsightAIError", repr(err))
        stubenv.clear_fake_ai()

        # AllProvidersFailed -> InsightAIError(rate_limited=all_rate_limited, provider=<main provider>)
        settings.set_panel_cache({"insight_weekly": FeatureSetting(Target("claude", "claude-sonnet-5-5"), (), "panel")})
        for kind, rate_limited, billing in (("rate_limit", True, False), ("server", False, False), ("billing", False, True)):
            health.reset()
            stubenv.set_fake_ai(claude=kind)
            try:
                await ins.generate_weekly_insight(uid)
                err = None
            except Exception as e:  # noqa: BLE001
                err = e
            check(isinstance(err, ins.InsightAIError) and err.provider == "claude"
                  and ins.is_rate_limit_error(err) == rate_limited and ins.is_billing_error(err) == billing,
                  f"insights: every provider failing ({kind}) -> InsightAIError(rate_limited={rate_limited}, provider=claude)"
                  f"{', billing' if billing else ''}", (repr(err), getattr(err, "provider", None)))
        stubenv.clear_fake_ai()
        import ai_chatbot
        check(not hasattr(ai_chatbot.financial_chatbot, "gpt_model"), "insights: FinancialChatbot.gpt_model is gone (R1)")

        # F10: the manual weekly-insight route logs the failure text redacted
        import contextlib
        import io

        import main as backend_main
        orig_weekly = ins.generate_weekly_insight

        async def weekly_fails(user_id):
            raise RuntimeError("upstream refused key sk-proj-t9MANUALkey1234567 for this request")
        ins.generate_weekly_insight = weekly_fails
        out = io.StringIO()
        try:
            with contextlib.redirect_stdout(out):
                res = await backend_main.manually_generate_weekly_insights(current_user={"_id": uid})
        finally:
            ins.generate_weekly_insight = orig_weekly
        printed = out.getvalue()
        check(res.get("results") and list(res["results"].values()) == ["error"] and "Manual weekly insight failed" in printed
              and "t9MANUAL" not in printed and "[redacted]" in printed,
              "manual_weekly_logs_redacted: the failure is printed with the key redacted", (res, printed[-300:]))
    finally:
        runner.run, ins.users_db.list_fields = orig_run, orig_list
        stubenv.clear_fake_ai()
        health.reset()
        settings._env, settings._panel = saved[0], saved[2]
        settings._env_units.clear()
        settings._env_units.update(saved[1])


async def budget_checks():
    """Task 10: budget suggestions and auto-created budgets run on the provider runner."""
    import uuid
    from datetime import UTC, datetime, timedelta

    import httpx
    from sqlalchemy import delete, select

    from sql.db import execute, fetch_all
    from sql.tables import ai_usage, users

    c = httpx.Client(base_url="http://127.0.0.1:8765", timeout=120)
    db = __import__("pgcompat").get_db()
    made = make_admins(c, db, "t10", ("admin",))
    AD = {}
    uids = []

    def premium_user(label, n_tx=12):
        email, pw = f"t10-{label}-{uuid.uuid4().hex[:6]}@example.com", "T10BudgetPass123"
        c.post("/api/auth/register", json={"name": f"T10 {label}", "email": email, "password": pw})
        db.users.update_one({"email": email}, {"$set": {
            "is_verified": True, "subscription_type": "premium",
            "subscription_expires_at": datetime.now(UTC) + timedelta(days=30)}})
        uid = db.users.find_one({"email": email})["_id"]
        uids.append(uid)
        hdr = {"Authorization": "Bearer " + c.post("/api/auth/login", json={"email": email, "password": pw}).json()["access_token"]}
        for i in range(n_tx):
            c.post("/api/transactions", headers=hdr, json={
                "type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries",
                "amount": 10 + i, "currency": "usd", "date": (datetime.now(UTC) - timedelta(days=i)).isoformat(),
                "description": f"t10 groceries {i}"})
        return uid, hdr

    def put(feature, provider, model, backups=None):
        return c.put(f"/api/admin/ai/settings/{feature}", headers=AD,
                     json={"main": {"provider": provider, "model": model}, "backups": backups})

    def calls(before):
        return [x.get("provider") for x in _outbox_ai_calls(before)]

    async def usage(uid, feature):
        return await fetch_all(select(ai_usage).where(ai_usage.c.user_id == uid, ai_usage.c.feature_type == feature)
                               .order_by(ai_usage.c.created_at))

    suggest_body = {"period": "monthly", "start_date": datetime.now(UTC).isoformat(), "currency": "usd", "analysis_months": 3}

    try:
        AD = admin_login(c, made["admin"])
        admin_reset(c, AD)
        uid, U = premium_user("main")

        # --- budget_suggest_on_claude
        r = put("budget_suggestion", "claude", "claude-sonnet-5-5")
        check(r.status_code == 200, "budget setup: PUT budget_suggestion = claude", f"{r.status_code} {r.text[:200]}")
        before = len(outbox_lines())
        r = c.post("/api/budgets/ai-suggest", headers=U, json=suggest_body)
        body = r.json() if r.status_code == 200 else {}
        cats = body.get("category_budgets") or []
        rows = await usage(uid, "budget_suggestion")
        check(r.status_code == 200 and calls(before) == ["claude"] and cats and cats[0]["main_category"] == "Food & Daily Living"
              and cats[0]["allocated_amount"] == 450 and "temporarily unavailable" not in " ".join(body.get("warnings") or []),
              "budget_suggest_on_claude: 200, one claude call, the AI's categories are used",
              f"{r.status_code} {r.text[:300]} {calls(before)}")
        check(len(rows) == 1 and rows[0]["provider"] == "claude" and rows[0]["model_name"] == "claude-sonnet-5-5"
              and rows[0]["fallback_from"] is None, "budget_suggest_on_claude: exactly one usage row, provider claude",
              [(x["provider"], x["model_name"], x["fallback_from"]) for x in rows])
        admin_reset(c, AD)

        # --- a bad answer falls back to the next provider; the usage row names the provider that failed
        put("budget_suggestion", "claude", "claude-sonnet-5-5")
        stubenv.set_fake_ai(claude="bad_json")
        before = len(outbox_lines())
        n0 = len(await usage(uid, "budget_suggestion"))
        r = c.post("/api/budgets/ai-suggest", headers=U, json=suggest_body)
        rows = (await usage(uid, "budget_suggestion"))[n0:]
        cats = (r.json().get("category_budgets") if r.status_code == 200 else None) or []
        check(r.status_code == 200 and calls(before) == ["claude", "openai"] and cats and cats[0]["allocated_amount"] == 450,
              "budget_bad_json_falls_back: 200 from openai after claude's bad JSON", f"{r.status_code} {r.text[:200]} {calls(before)}")
        check(len(rows) == 1 and rows[0]["provider"] == "openai" and rows[0]["fallback_from"] == "claude",
              "budget_bad_json_falls_back: the usage row has fallback_from claude",
              [(x["provider"], x["fallback_from"]) for x in rows])
        admin_reset(c, AD)

        # --- every provider fails: never a 500, no provider text; today's non-AI suggestions with a warning
        put("budget_suggestion", "claude", "claude-sonnet-5-5", backups=[])
        stubenv.set_fake_ai(claude="server")
        before = len(outbox_lines())
        n0 = len(await usage(uid, "budget_suggestion"))
        r = c.post("/api/budgets/ai-suggest", headers=U, json=suggest_body)
        body = r.json() if r.status_code == 200 else {}
        check(r.status_code in (200, 503) and "The service" not in r.text and calls(before) == ["claude"],
              "budget_all_fail_503: every provider failing is never a 500 and leaks no provider text",
              f"{r.status_code} {r.text[:200]} {calls(before)}")
        check(r.status_code == 200 and body.get("category_budgets") and "temporarily unavailable" in " ".join(body.get("warnings") or [])
              and len(await usage(uid, "budget_suggestion")) == n0,
              "budget_all_fail: the basic (non-AI) suggestions come back with a warning, no usage row",
              f"{r.status_code} {r.text[:300]}")
        admin_reset(c, AD)

        # --- F3: a request-level provider error is a 400 with a fixed message: no provider text, no fallback
        import transaction_routes as _tr
        for provider, model in (("claude", "claude-sonnet-5-5"), ("openai", "gpt-4o-mini")):
            put("budget_suggestion", provider, model)
            stubenv.set_fake_ai(**{provider: "bad_request"})
            before = len(outbox_lines())
            n0 = len(await usage(uid, "budget_suggestion"))
            r = c.post("/api/budgets/ai-suggest", headers=U, json=suggest_body)
            check(r.status_code == 400 and r.json().get("detail") == _tr._AI_BAD_REQUEST
                  and "invalid image" not in r.text and "Error code" not in r.text and calls(before) == [provider]
                  and len(await usage(uid, "budget_suggestion")) == n0,
                  f"budget_bad_request_400: {provider} bad_request -> fixed 400, no provider text, no fallback",
                  f"{r.status_code} {r.text[:300]} {calls(before)}")
            admin_reset(c, AD)
        put("budget_suggestion", "claude", "claude-sonnet-5-5")
        stubenv.set_fake_ai(claude="odd_error")
        r = c.post("/api/budgets/ai-suggest", headers=U, json=suggest_body)
        check(r.status_code == 400 and r.json().get("detail") == _tr._AI_BAD_REQUEST and "odd provider" not in r.text,
              "budget_bad_request_400: an exception without a status is the same fixed 400", f"{r.status_code} {r.text[:300]}")
        admin_reset(c, AD)

        # --- not enough data: basic suggestions, no AI call at all
        uid2, U2 = premium_user("few", n_tx=3)
        before = len(outbox_lines())
        r = c.post("/api/budgets/ai-suggest", headers=U2, json=suggest_body)
        check(r.status_code == 200 and calls(before) == [], "budget_suggest: too little data uses basic suggestions, no AI call",
              f"{r.status_code} {r.text[:200]} {calls(before)}")

        await _budget_inprocess_checks(uid)
    finally:
        try:
            stubenv.clear_fake_ai()
            if AD:
                admin_reset(c, AD)
        finally:
            try:
                for u in uids:
                    await execute(delete(users).where(users.c.id == u))  # cascades to transactions and ai_usage rows
            finally:
                db.admins.delete_many({"email": {"$in": list(made.values())}})
                c.close()


async def _budget_inprocess_checks(uid):
    """budget_service in-process: schema and limits per provider, the parser, the auto-create fallback, the route's 503."""
    from datetime import UTC, datetime, timedelta

    from fastapi import HTTPException
    from sqlalchemy import select

    import budget_routes
    import budget_service as bs
    from ai_providers import health, settings
    from ai_providers.errors import AllProvidersFailed, UnusableAnswer
    from ai_providers.types import Completion, FeatureSetting, Target
    from budget_models import AIBudgetRequest
    from sql.db import fetch_all
    from sql.tables import ai_usage

    stubenv.patch_loaded_modules()
    saved = (settings._env, dict(settings._env_units), settings._panel)
    health.reset()
    stubenv.clear_fake_ai()
    now = datetime.now(UTC)
    parent = {"start_date": now - timedelta(days=30), "end_date": now + timedelta(days=1), "currency": "usd",
              "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 100.0, "spent_amount": 60.0,
                                    "percentage_used": 60.0, "is_exceeded": False}],
              "total_budget": 100.0, "total_spent": 60.0, "percentage_used": 60.0}

    def use(feature, provider, model, backups=()):
        settings.set_panel_cache({feature: FeatureSetting(Target(provider, model), backups, "panel")})

    async def auto(feature="budget_auto_create"):
        return await bs._generate_ai_category_budgets(uid, bs.BudgetPeriod.MONTHLY, now, now + timedelta(days=30), parent)

    async def usage(feature):
        return await fetch_all(select(ai_usage).where(ai_usage.c.user_id == uid, ai_usage.c.feature_type == feature))

    try:
        settings.set_panel_cache({})
        settings.reload_env({})

        # --- the request each provider gets: temperature 0.3 (never to Claude), a json schema, explicit limits
        schema = bs._BUDGET_JSON_SCHEMA
        item = schema["properties"]["categories"]["items"]
        check(schema.get("additionalProperties") is False and item.get("additionalProperties") is False
              and set(schema["required"]) == {"categories", "reasoning"}
              and set(item["required"]) == {"main_category", "allocated_amount", "spent_amount", "percentage_used", "is_exceeded"},
              "budget schema: explicit required lists and additionalProperties false", schema)
        for feature in ("budget_suggestion", "budget_auto_create"):
            for provider, model in (("openai", "gpt-4o-mini"), ("gemini", "gemini-2.5-flash"), ("claude", "claude-sonnet-5-5")):
                use(feature, provider, model)
                if feature == "budget_auto_create":
                    out = await auto()
                else:
                    out = (await bs.BudgetAnalyzer(uid).generate_ai_suggestions(
                        bs.BudgetPeriod.MONTHLY, now, None, 3, None, None, "usd")).category_budgets
                kw = stubenv.LAST_KWARGS[provider]
                if provider == "openai":
                    got = (kw.get("max_completion_tokens"), kw.get("temperature"), (kw.get("response_format") or {}).get("type"))
                elif provider == "gemini":
                    got = (kw["config"].max_output_tokens, kw["config"].temperature, kw["config"].response_mime_type)
                else:
                    fmt = (kw.get("output_config") or {}).get("format") or {}
                    got = (kw.get("max_tokens"), kw.get("temperature", "absent"), fmt.get("type"))
                want = {"openai": (4096, 0.3, "json_object"), "gemini": (8192, 0.3, "application/json"),
                        "claude": (8000, "absent", "json_schema")}[provider]
                check(got == want and kw.get("model", model) == model and out and out[0].allocated_amount == 450,
                      f"budget request: {feature} on {provider} sends {want}", (got, out[:1]))

        # --- the parser: today's field checks, anything unusable moves on to the next provider
        structure = [{"main_category": "Food & Daily Living", "sub_categories": ["Groceries"]}]
        parse = bs._parse_budget_answer(structure)

        def refuses(text):
            try:
                parse(Completion(text, 1, 1, "stop"))
                return False
            except UnusableAnswer:
                return True

        good = '{"categories": [{"main_category": "food & daily living", "allocated_amount": 5, "spent_amount": 0, ' \
               '"percentage_used": 0, "is_exceeded": false}, {"main_category": "Nope", "allocated_amount": 1}], "reasoning": "r"}'
        res = parse(Completion(good, 1, 1, "stop"))
        check([x.main_category for x in res["categories"]] == ["Food & Daily Living"] and res["reasoning"].startswith("r")
              and "excluded" in res["reasoning"], "budget parse: keeps valid categories (case-insensitive), drops unknown ones", res)
        check(all(refuses(t) for t in ("not json", "[]", '{"reasoning": "x"}', '{"categories": "x"}', '{"categories": []}',
                                       '{"categories": [{"main_category": "Nope", "allocated_amount": 1}]}')),
              "budget parse: bad JSON, wrong shape or no valid category is unusable")

        # --- AllProvidersFailed / unusable answers: the non-AI fallbacks, as before
        want_adjusted = [x.allocated_amount for x in bs._generate_adjusted_budgets(parent, 31)]
        for label, fakes in (("every provider fails", {"claude": "server"}), ("bad json", {"claude": "bad_json"})):
            health.reset()
            use("budget_auto_create", "claude", "claude-sonnet-5-5")
            n0 = len(await usage("budget_auto_create"))
            stubenv.set_fake_ai(**fakes)
            out = await auto()
            check([x.allocated_amount for x in out] == want_adjusted and want_adjusted == [90.0]
                  and len(await usage("budget_auto_create")) == n0,
                  f"budget auto-create: {label} -> the adjusted (non-AI) budgets, no usage row", [x.allocated_amount for x in out])
        stubenv.clear_fake_ai()
        health.reset()

        use("budget_suggestion", "claude", "claude-sonnet-5-5")
        stubenv.set_fake_ai(claude="server")
        s = await bs.BudgetAnalyzer(uid).generate_ai_suggestions(bs.BudgetPeriod.MONTHLY, now, None, 3, None, None, "usd")
        check(s.category_budgets and s.category_budgets[0].allocated_amount != 450
              and any("temporarily unavailable" in w for w in s.warnings),
              "budget suggest: every provider failing -> basic suggestions plus a warning",
              ([x.allocated_amount for x in s.category_budgets], s.warnings))
        stubenv.clear_fake_ai()

        # --- F3: any other exception escaping the runner is logged redacted at error level and becomes a fixed 400
        import logging
        orig_run = bs._runner.run

        async def rejects(*a, **k):
            raise RuntimeError("Error code: 413 - request_too_large for key sk-proj-t10BUDGETkey1234567")
        bs._runner.run = rejects
        use("budget_suggestion", "claude", "claude-sonnet-5-5")
        try:
            with LogCapture("budget_service") as cap:
                req = AIBudgetRequest(period="monthly", start_date=now, currency="usd", analysis_months=3)
                try:
                    await budget_routes.get_ai_budget_suggestions(req, current_user={"_id": uid})
                    err = None
                except HTTPException as e:
                    err = e
        finally:
            bs._runner.run = orig_run
        errs = [r.getMessage() for r in cap.at(logging.ERROR)]
        check(err is not None and err.status_code == 400
              and err.detail == "The AI service could not process this request. Please check it and try again."
              and "413" not in str(err.detail),
              "budget_rejected_400: the route answers the fixed 400", err and (err.status_code, err.detail))
        check(len(errs) == 1 and "[redacted]" in errs[0] and not any("t10BUDGET" in r.getMessage() for r in cap.records),
              "budget_rejected_400: one redacted error-level log line", [(r.levelname, r.getMessage()) for r in cap.records])

        # --- the route: AllProvidersFailed that reaches it is a 503 with a fixed message, never a 500 with provider text
        orig = bs.BudgetAnalyzer.generate_ai_suggestions

        async def boom(self, *a, **k):
            raise AllProvidersFailed([])
        bs.BudgetAnalyzer.generate_ai_suggestions = boom
        try:
            req = AIBudgetRequest(period="monthly", start_date=now, currency="usd", analysis_months=3)
            try:
                await budget_routes.get_ai_budget_suggestions(req, current_user={"_id": uid})
                err = None
            except HTTPException as e:
                err = e
            check(err is not None and err.status_code == 503 and err.detail == "AI is temporarily unavailable",
                  "route: AllProvidersFailed -> 503 'AI is temporarily unavailable'", (err and (err.status_code, err.detail)))
        finally:
            bs.BudgetAnalyzer.generate_ai_suggestions = orig
        check(not hasattr(bs, "AsyncOpenAI") and "gpt-4o-mini" not in open(bs.__file__, encoding="utf-8").read()
              and "track_ai_usage" not in open(bs.__file__, encoding="utf-8").read(),
              "budget_service: no direct OpenAI call, hard-coded model or own usage tracking is left")
    finally:
        stubenv.clear_fake_ai()
        health.reset()
        settings._env, settings._panel = saved[0], saved[2]
        settings._env_units.clear()
        settings._env_units.update(saved[1])


async def transaction_checks():
    """Task 11: transaction text, receipt image and voice run on the provider runner."""
    import io
    import uuid
    from datetime import UTC, datetime, timedelta

    import httpx
    from PIL import Image
    from sqlalchemy import delete, select

    from sql.db import execute, fetch_all
    from sql.tables import ai_usage, users

    c = httpx.Client(base_url="http://127.0.0.1:8765", timeout=120)
    db = __import__("pgcompat").get_db()
    made = make_admins(c, db, "t11", ("admin",))
    AD = {}
    uids = []

    buf = io.BytesIO()
    Image.new("RGB", (8, 8), (200, 30, 30)).save(buf, "PNG")
    PNG = buf.getvalue()

    def premium_user(label):
        email, pw = f"t11-{label}-{uuid.uuid4().hex[:6]}@example.com", "T11TxPass123"
        c.post("/api/auth/register", json={"name": f"T11 {label}", "email": email, "password": pw})
        db.users.update_one({"email": email}, {"$set": {
            "is_verified": True, "subscription_type": "premium",
            "subscription_expires_at": datetime.now(UTC) + timedelta(days=30)}})
        uid = db.users.find_one({"email": email})["_id"]
        uids.append(uid)
        hdr = {"Authorization": "Bearer " + c.post("/api/auth/login", json={"email": email, "password": pw}).json()["access_token"]}
        return uid, hdr

    def put(feature, provider, model, backups=None):
        return c.put(f"/api/admin/ai/settings/{feature}", headers=AD,
                     json={"main": {"provider": provider, "model": model}, "backups": backups})

    def calls(before):
        return [x.get("provider") for x in _outbox_ai_calls(before)]

    async def usage(uid, feature):
        return await fetch_all(select(ai_usage).where(ai_usage.c.user_id == uid, ai_usage.c.feature_type == feature)
                               .order_by(ai_usage.c.created_at))

    def image_post(H):
        return c.post("/api/transactions/extract-from-image", headers=H, files={"image": ("r.png", PNG, "image/png")})

    def audio_post(H, **data):
        return c.post("/api/transactions/transcribe-audio", headers=H,
                      files={"audio": ("voice.m4a", b"\x00\x01\x02\x03", "audio/mp4")}, data=data)

    try:
        AD = admin_login(c, made["admin"])
        admin_reset(c, AD)
        uid, U = premium_user("main")

        # --- text_extract_on_gemini
        r = put("transaction_text", "gemini", "gemini-2.5-flash")
        check(r.status_code == 200, "tx setup: PUT transaction_text = gemini", f"{r.status_code} {r.text[:200]}")
        before = len(outbox_lines())
        r = c.post("/api/transactions/extract-from-text", headers=U, json={"text": "coffee 2.5 dollars"})
        body = r.json() if r.status_code == 200 else {}
        rows = await usage(uid, "transaction_text_extraction")
        check(r.status_code == 200 and calls(before) == ["gemini"] and body.get("amount") == 2.5
              and body.get("type") == "outflow" and body.get("description") == "coffee",
              "text_extract_on_gemini: 200 with the canned transaction, one gemini call", f"{r.status_code} {r.text[:300]} {calls(before)}")
        check(len(rows) == 1 and rows[0]["provider"] == "gemini" and rows[0]["model_name"] == "gemini-2.5-flash"
              and rows[0]["fallback_from"] is None, "text_extract_on_gemini: exactly one usage row, provider gemini",
              [(x["provider"], x["model_name"], x["fallback_from"]) for x in rows])

        # --- the multi-transaction route on the same provider keeps its post-processing (zero amount dropped)
        before = len(outbox_lines())
        r = c.post("/api/transactions/extract-multiple-from-text", headers=U, json={"text": "lunch 4.5, grab 3, something"})
        body = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and calls(before) == ["gemini"] and len(body.get("transactions") or []) == 2
              and "omitted" in (body.get("analysis") or ""),
              "multi_extract_on_gemini: 200, the zero-amount item is dropped as before", f"{r.status_code} {r.text[:300]}")
        admin_reset(c, AD)

        # --- a bad answer falls back; the usage row names the provider that failed
        put("transaction_text", "claude", "claude-sonnet-5-5")
        stubenv.set_fake_ai(claude="bad_json")
        before = len(outbox_lines())
        n0 = len(await usage(uid, "transaction_text_extraction"))
        r = c.post("/api/transactions/extract-from-text", headers=U, json={"text": "coffee 2.5 dollars"})
        rows = (await usage(uid, "transaction_text_extraction"))[n0:]
        check(r.status_code == 200 and calls(before) == ["claude", "openai"] and r.json().get("amount") == 2.5,
              "text_bad_json_falls_back: 200 from openai after claude's bad JSON", f"{r.status_code} {r.text[:200]} {calls(before)}")
        check(len(rows) == 1 and rows[0]["provider"] == "openai" and rows[0]["fallback_from"] == "claude",
              "text_bad_json_falls_back: the usage row has fallback_from claude", [(x["provider"], x["fallback_from"]) for x in rows])
        admin_reset(c, AD)

        # --- F1: a model-level 400 (a model typed under "Other..." that the endpoint can't use) falls back to the
        # backup and shows on the status card: the model cools and the provider's last error is set
        r = put("transaction_text", "openai", "gpt-5-mini", backups=[{"provider": "gemini", "model": "gemini-2.5-flash"}])
        check(r.status_code == 200, "tx setup: PUT transaction_text = openai gpt-5-mini, backup gemini", f"{r.status_code} {r.text[:200]}")
        for kind in ("invalid_model", "unsupported_param", "unsupported_value"):
            stubenv.clear_fake_ai()
            # a successful Test of the pair clears its cool-off from the previous round
            admin_reset_status = c.post("/api/admin/ai/test/openai", headers=AD, json={"model": "gpt-5-mini"})
            stubenv.set_fake_ai(**{"openai@gpt-5-mini": kind})
            before = len(outbox_lines())
            r = c.post("/api/transactions/extract-from-text", headers=U, json={"text": "coffee 2.5 dollars"})
            st = {p["id"]: p for p in c.get("/api/admin/ai/status", headers=AD).json()["providers"]}["openai"]
            check(r.status_code == 200 and r.json().get("amount") == 2.5 and calls(before) == ["openai", "gemini"]
                  and admin_reset_status.status_code == 200,
                  f"tx_model_level_400_falls_back: {kind} on openai gpt-5-mini -> 200 from gemini",
                  f"{r.status_code} {r.text[:200]} {calls(before)}")
            check(st["state"] == "failing" and [m["model"] for m in st["cooling_models"]] == ["gpt-5-mini"]
                  and st["cooling_until"] is None and st["last_error"],
                  f"tx_model_level_400_falls_back: {kind} shows on the status card (gpt-5-mini cooling, last error)", st)
        stubenv.clear_fake_ai()
        c.post("/api/admin/ai/test/openai", headers=AD, json={"model": "gpt-5-mini"})  # un-cool the pair for later checks
        admin_reset(c, AD)

        # --- image_extract_on_claude
        put("transaction_image", "claude", "claude-sonnet-5-5")
        before = len(outbox_lines())
        r = image_post(U)
        body = r.json() if r.status_code == 200 else {}
        ai = _outbox_ai_calls(before)
        rows = await usage(uid, "transaction_image_extraction")
        check(r.status_code == 200 and [x.get("provider") for x in ai] == ["claude"] and ai and ai[0].get("has_image") is True
              and body.get("amount") == 2.5,
              "image_extract_on_claude: 200, the claude call carries an image block", f"{r.status_code} {r.text[:300]} {ai}")
        check(len(rows) == 1 and rows[0]["provider"] == "claude" and rows[0]["model_name"] == "claude-sonnet-5-5",
              "image_extract_on_claude: one usage row, provider claude", [(x["provider"], x["model_name"]) for x in rows])
        admin_reset(c, AD)

        # --- image_bad_request_no_fallback: a request-level error is a 400 with a fixed message and no other provider is tried
        put("transaction_image", "claude", "claude-sonnet-5-5")
        stubenv.set_fake_ai(claude="bad_request")
        before = len(outbox_lines())
        n0 = len(await usage(uid, "transaction_image_extraction"))
        r = image_post(U)
        import transaction_routes as _tr
        check(r.status_code == 400 and r.json().get("detail") == _tr._AI_BAD_REQUEST and calls(before) == ["claude"]
              and len(await usage(uid, "transaction_image_extraction")) == n0,
              "image_bad_request_no_fallback: 400 with the fixed message, no openai call, no usage row",
              f"{r.status_code} {r.text[:200]} {calls(before)}")
        admin_reset(c, AD)

        # --- a request-level error with no numeric status at all: still the fixed 400, never provider text (R17)
        for feature, post in (("transaction_text", lambda: c.post("/api/transactions/extract-from-text", headers=U, json={"text": "x 1"})),
                              ("transaction_text", lambda: c.post("/api/transactions/extract-multiple-from-text", headers=U, json={"text": "x 1"})),
                              ("transaction_image", lambda: image_post(U)),
                              ("transaction_audio", lambda: audio_post(U))):
            main = "openai" if feature == "transaction_audio" else "claude"
            put(feature, main, "whisper-1" if main == "openai" else "claude-sonnet-5-5")
            stubenv.set_fake_ai(**{main: "odd_error"})
            before = len(outbox_lines())
            r = post()
            check(r.status_code == 400 and r.json().get("detail") == _tr._AI_BAD_REQUEST and "odd provider" not in r.text
                  and calls(before) == [main], f"tx_odd_error_400: {feature} -> fixed 400, no provider text, no fallback",
                  f"{r.status_code} {r.text[:200]} {calls(before)}")
            admin_reset(c, AD)

        # --- silent audio: ONE provider call, a 200 with an empty transcription, usage still tracked (R16)
        stubenv.set_fake_ai(openai="empty")
        before = len(outbox_lines())
        n0 = len(await usage(uid, "transaction_audio_transcription"))
        r = audio_post(U)
        check(r.status_code == 200 and r.json() == {"transcription": ""} and calls(before) == ["openai"]
              and len(await usage(uid, "transaction_audio_transcription")) == n0 + 1,
              "audio_silence: 200 with an empty transcription after exactly one provider call", f"{r.status_code} {r.text[:200]} {calls(before)}")
        admin_reset(c, AD)

        # --- every provider failing: 503 with the fixed message, never provider text, no usage row
        for feature, post in (("transaction_text", lambda: c.post("/api/transactions/extract-from-text", headers=U, json={"text": "x 1"})),
                              ("transaction_image", lambda: image_post(U)),
                              ("transaction_audio", lambda: audio_post(U))):
            main = ("openai", "whisper-1") if feature == "transaction_audio" else ("claude", "claude-sonnet-5-5")
            put(feature, main[0], main[1], backups=[])
            stubenv.set_fake_ai(**{main[0]: "server"})
            before = len(outbox_lines())
            r = post()
            check(r.status_code == 503 and r.json().get("detail") == "AI is temporarily unavailable"
                  and "The service" not in r.text and calls(before) == [main[0]],
                  f"tx_all_fail_503: {feature} -> 503 'AI is temporarily unavailable'", f"{r.status_code} {r.text[:200]} {calls(before)}")
            admin_reset(c, AD)

        # --- audio_falls_back_to_gemini
        put("transaction_audio", "openai", "whisper-1")
        stubenv.set_fake_ai(openai="billing")
        before = len(outbox_lines())
        n0 = len(await usage(uid, "transaction_audio_transcription"))
        r = audio_post(U, language="my")
        rows = (await usage(uid, "transaction_audio_transcription"))[n0:]
        check(r.status_code == 200 and r.json() == {"transcription": "fake transcript"} and calls(before) == ["openai", "gemini"],
              "audio_falls_back_to_gemini: 200 transcript from gemini", f"{r.status_code} {r.text[:200]} {calls(before)}")
        check(len(rows) == 1 and rows[0]["provider"] == "gemini" and rows[0]["fallback_from"] == "openai"
              and rows[0]["model_name"] == "gemini-2.5-flash",
              "audio_falls_back_to_gemini: one usage row from gemini with fallback_from openai",
              [(x["provider"], x["fallback_from"], x["model_name"]) for x in rows])
        admin_reset(c, AD)

        # --- audio on the built-in default (whisper-1), language handling as before
        before = len(outbox_lines())
        n0 = len(await usage(uid, "transaction_audio_transcription"))
        r = audio_post(U, language="en")
        rows = (await usage(uid, "transaction_audio_transcription"))[n0:]
        check(r.status_code == 200 and calls(before) == ["openai"] and len(rows) == 1 and rows[0]["model_name"] == "whisper-1",
              "audio default: whisper-1 on openai, one usage row", f"{r.status_code} {r.text[:200]} {[x['model_name'] for x in rows]}")
        r = audio_post(U, language="fr")
        check(r.status_code == 400 and "Unsupported language" in r.text, "audio: an unsupported language is still a 400", f"{r.status_code} {r.text[:150]}")
        r = put("transaction_audio", "claude", "claude-sonnet-5-5")
        check(r.status_code == 422, "audio: claude cannot be chosen for transaction_audio", f"{r.status_code} {r.text[:150]}")

        await _transaction_inprocess_checks(uid)
    finally:
        try:
            stubenv.clear_fake_ai()
            if AD:
                admin_reset(c, AD)
        finally:
            try:
                for u in uids:
                    await execute(delete(users).where(users.c.id == u))  # cascades to transactions and ai_usage rows
                from sql.tables import ai_provider_status
                await execute(ai_provider_status.delete())
            finally:
                db.admins.delete_many({"email": {"$in": list(made.values())}})
                c.close()


async def _transaction_inprocess_checks(uid):
    """transaction_routes in-process: schemas, the request each provider gets, and the parser's leniency."""
    import io

    from fastapi import UploadFile
    from PIL import Image

    import transaction_routes as tr
    from ai_providers import health, settings
    from ai_providers.errors import AllProvidersFailed, UnusableAnswer
    from ai_providers.types import Completion, FeatureSetting, Target
    from models import TextExtractionRequest

    stubenv.patch_loaded_modules()
    saved = (settings._env, dict(settings._env_units), settings._panel)
    health.reset()
    stubenv.clear_fake_ai()
    user = {"_id": uid, "default_currency": "usd"}
    buf = io.BytesIO()
    Image.new("RGB", (8, 8), (10, 120, 200)).save(buf, "PNG")
    png = buf.getvalue()

    def use(feature, provider, model, backups=()):
        settings.set_panel_cache({feature: FeatureSetting(Target(provider, model), backups, "panel")})

    def kw_of(provider):
        kw = stubenv.LAST_KWARGS[provider]
        if provider == "openai":
            return (kw.get("max_completion_tokens"), kw.get("temperature"), (kw.get("response_format") or {}).get("type"))
        if provider == "gemini":
            return (kw["config"].max_output_tokens, kw["config"].temperature, kw["config"].response_mime_type)
        fmt = (kw.get("output_config") or {}).get("format") or {}
        return (kw.get("max_tokens"), kw.get("temperature", "absent"), fmt.get("type"))

    try:
        settings.set_panel_cache({})
        settings.reload_env({})

        # --- explicit closed schemas
        item = tr._TX_ITEM_SCHEMA
        multi = tr._MULTI_JSON_SCHEMA
        fields = {"type", "main_category", "sub_category", "date", "description", "amount", "currency", "confidence", "reasoning"}
        check(item.get("additionalProperties") is False and set(item["required"]) == fields and set(item["properties"]) == fields
              and multi.get("additionalProperties") is False and multi["properties"]["transactions"]["items"] is not None
              and multi["properties"]["transactions"]["items"].get("additionalProperties") is False
              and set(multi["required"]) == {"transactions", "total_count", "overall_confidence", "analysis"},
              "tx schemas: explicit required lists and additionalProperties false", (item, multi))

        # --- the request each provider gets: today's temperature 0.3 (never to Claude), a json schema, explicit limits
        want = {
            "transaction_text": {"openai": (4000, 0.3, "json_object"), "gemini": (8192, 0.3, "application/json"),
                                 "claude": (8000, "absent", "json_schema")},
            "transaction_text_multi": {"openai": (8000, 0.3, "json_object"), "gemini": (8192, 0.3, "application/json"),
                                       "claude": (8000, "absent", "json_schema")},
            "transaction_image": {"openai": (1000, 0.3, "json_object"), "gemini": (8192, 0.3, "application/json"),
                                  "claude": (8000, "absent", "json_schema")},
        }
        for provider, model in (("openai", "gpt-4o-mini"), ("gemini", "gemini-2.5-flash"), ("claude", "claude-sonnet-5-5")):
            use("transaction_text", provider, model)
            out = await tr.extract_transaction_from_text(TextExtractionRequest(text="coffee 2.5"), current_user=user)
            check(kw_of(provider) == want["transaction_text"][provider] and out.amount == 2.5,
                  f"tx request: text on {provider} sends {want['transaction_text'][provider]}", (kw_of(provider), out.amount))
            out = await tr.extract_multiple_transactions_from_text(TextExtractionRequest(text="a 1, b 2"), current_user=user)
            check(kw_of(provider) == want["transaction_text_multi"][provider] and len(out.transactions) == 2,
                  f"tx request: multi text on {provider} sends {want['transaction_text_multi'][provider]}", (kw_of(provider), len(out.transactions)))
            use("transaction_image", provider, "gpt-4o" if provider == "openai" else model)
            up = UploadFile(file=io.BytesIO(png), filename="r.png")
            out = await tr.extract_transaction_from_image(image=up, current_user=user)
            check(kw_of(provider) == want["transaction_image"][provider] and out.amount == 2.5,
                  f"tx request: image on {provider} sends {want['transaction_image'][provider]}", (kw_of(provider), out.amount))

        # --- the request sends the receipt as one JPEG image whichever provider answers
        import base64
        use("transaction_image", "openai", "gpt-4o")
        await tr.extract_transaction_from_image(image=UploadFile(file=io.BytesIO(png), filename="r.png"), current_user=user)
        url = stubenv.LAST_KWARGS["openai"]["messages"][1]["content"][1]["image_url"]["url"]
        raw = base64.b64decode(url.split("base64,", 1)[1]) if url.startswith("data:image/jpeg;base64,") else b""
        check(raw[:2] == b"\xff\xd8", "tx image: openai gets the resized JPEG as image/jpeg", url[:40])

        # --- voice: language and filename reach the provider as before
        use("transaction_audio", "openai", "whisper-1")
        for lang, want_lang in (("my", "my"), ("mm", "my"), ("en", "en"), (None, None)):
            up = UploadFile(file=io.BytesIO(b"\x00\x01"), filename="note.m4a")
            res = await tr.transcribe_audio(audio=up, language=lang, current_user=user)
            kw = stubenv.LAST_KWARGS["openai"]
            check(res == {"transcription": "fake transcript"} and kw.get("language") == want_lang and kw["model"] == "whisper-1"
                  and kw["file"][0].endswith(".m4a"), f"tx audio: language {lang!r} reaches whisper as {want_lang!r}", kw)
        up = UploadFile(file=io.BytesIO(b"\x00\x01"), filename="noext")
        await tr.transcribe_audio(audio=up, language=None, current_user=user)
        check(stubenv.LAST_KWARGS["openai"]["file"][0].endswith(".wav"), "tx audio: a file name without extension is sent as .wav",
              stubenv.LAST_KWARGS["openai"]["file"][0])

        # --- silence transcribes to "": still a normal 200 with an empty transcription (as before the runner)
        stubenv.set_fake_ai(openai="empty", gemini="empty")
        use("transaction_audio", "openai", "whisper-1", backups=(Target("gemini", "gemini-2.5-flash"),))
        before = len(outbox_lines())
        res = await tr.transcribe_audio(audio=UploadFile(file=io.BytesIO(b"\x00\x01"), filename="s.wav"), language=None, current_user=user)
        n_calls = [x.get("provider") for x in _outbox_ai_calls(before)]
        check(res == {"transcription": ""} and n_calls == ["openai"],
              "tx audio: silence is a 200 with an empty transcription after exactly one provider call", (res, n_calls))
        key = os.environ.pop("GOOGLE_API_KEY", None)  # the next target is not configured: still the one call, still a 200
        try:
            before = len(outbox_lines())
            res = await tr.transcribe_audio(audio=UploadFile(file=io.BytesIO(b"\x00\x01"), filename="s.wav"), language=None, current_user=user)
            n_calls = [x.get("provider") for x in _outbox_ai_calls(before)]
        finally:
            if key is not None:
                os.environ["GOOGLE_API_KEY"] = key
        check(res == {"transcription": ""} and n_calls == ["openai"],
              "tx audio: silence with an unconfigured backup is still a 200 (one call)", (res, n_calls))
        stubenv.clear_fake_ai()
        health.reset()

        # --- runner allow_empty: an empty answer that finished normally is valid (and tracked); nothing else changes
        from ai_providers import runner as rn

        def answer(text, finish):
            async def call(client, t):
                return Completion(text, 3, 4, finish)
            return call

        use("transaction_audio", "openai", "whisper-1", backups=(Target("gemini", "gemini-2.5-flash"),))
        from sqlalchemy import select as _select

        from sql.db import fetch_all as _fetch_all
        from sql.tables import ai_usage as _ai_usage
        n0 = len(await _fetch_all(_select(_ai_usage).where(_ai_usage.c.user_id == uid,
                                                           _ai_usage.c.feature_type == "transaction_audio_transcription")))
        r1 = await rn.run("transaction_audio", user_id=uid, call=answer("", "stop"), allow_empty=True)
        n1 = len(await _fetch_all(_select(_ai_usage).where(_ai_usage.c.user_id == uid,
                                                           _ai_usage.c.feature_type == "transaction_audio_transcription")))
        check(r1.value.text == "" and r1.target.provider == "openai" and r1.fallback_from is None and n1 == n0 + 1,
              "runner allow_empty=True: an empty stop answer is valid and tracked as usage", (r1.target, n1 - n0))
        for label, text, finish in (("an empty answer", "", "stop"), ("a refusal", "x", "refusal"), ("a filtered answer", "x", "filtered"),
                                    ("an empty cut-off answer", "", "length")):
            allow = label != "an empty answer"  # the default (allow_empty False) must still reject empty
            try:
                await rn.run("transaction_audio", user_id=None, call=answer(text, finish), allow_empty=allow)
                bad = False
            except AllProvidersFailed as e:
                bad = len(e.failures) == 2
            check(bad, f"runner: {label} is still unusable ({'allow_empty=True' if allow else 'default'}); both targets tried", label)
            health.reset()
        try:
            big = UploadFile(file=io.BytesIO(b"\x00" * (25 * 1024 * 1024 + 1)), filename="big.wav")
            await tr.transcribe_audio(audio=big, language=None, current_user=user)
            err = None
        except tr.HTTPException as e:
            err = e
        check(err is not None and err.status_code == 413, "tx audio: more than 25MB is a 413", err and err.status_code)

        # --- the parser accepts everything today's code accepts and post-processes; only unusable JSON moves on
        def refuses(parse, text):
            try:
                parse(Completion(text, 1, 1, "stop"))
                return False
            except UnusableAnswer:
                return True

        check(all(refuses(tr._parse_extraction_json, t) for t in ("not json", "", "[]", '"x"', "7", "null")),
              "tx parse: unparseable JSON or a non-object is unusable (next provider)")
        lenient = ['{}', '{"amount": 0, "confidence": 0.01}', '{"type": "weird", "main_category": "Nope", "amount": "abc"}',
                   '{"transactions": "x"}', '{"transactions": []}', '{"amount": -5, "confidence": 7, "date": "garbage"}']
        check(not any(refuses(tr._parse_extraction_json, t) for t in lenient),
              "tx parse: low confidence, zero or odd amounts, unknown categories and empty lists are still accepted")
        built = await tr._build_extraction({"amount": 0, "confidence": 0.9, "main_category": "Nope"}, "usd", keep_invalid_amount=True)
        check(built is not None and built.amount == 0 and built.confidence == 0,
              "tx parse: a zero amount still reaches the route's own handling (amount 0, confidence 0)")

        src = open(tr.__file__, encoding="utf-8").read()
        check(not any(s in src for s in ("gpt-4o", "whisper-1", "AsyncOpenAI", "track_ai_usage", "OPENAI_API_KEY")),
              "transaction_routes: no direct OpenAI call, hard-coded model, key check or own usage tracking is left")

        # --- F11: the "request rejected -> 400" path is logged at error level, redacted
        import logging
        orig_run = tr._runner.run

        async def rejects(*a, **k):
            raise RuntimeError("provider said no for key sk-proj-t11LOGGEDkey123456")
        tr._runner.run = rejects
        try:
            with LogCapture("transaction_routes") as cap:
                try:
                    await tr._run_ai("transaction_text", uid, call=None)
                    err = None
                except tr.HTTPException as e:
                    err = e
        finally:
            tr._runner.run = orig_run
        errs = [r.getMessage() for r in cap.at(logging.ERROR)]
        check(err is not None and err.status_code == 400 and err.detail == tr._AI_BAD_REQUEST
              and len(errs) == 1 and "transaction_text" in errs[0] and "[redacted]" in errs[0]
              and not any("t11LOGGED" in r.getMessage() for r in cap.records),
              "tx_rejected_logged_at_error: one redacted error-level log line, the fixed 400",
              (err and (err.status_code, err.detail), [(r.levelname, r.getMessage()) for r in cap.records]))
    finally:
        stubenv.clear_fake_ai()
        health.reset()
        settings._env, settings._panel = saved[0], saved[2]
        settings._env_units.clear()
        settings._env_units.update(saved[1])


async def usage_stats_checks():
    """Task 12: the admin AI-usage endpoints report cost per provider (Claude included) and fallback_from."""
    import uuid
    from datetime import UTC, datetime, timedelta

    import httpx
    from sqlalchemy import delete

    from sql.db import execute
    from sql.tables import users

    c = httpx.Client(base_url="http://127.0.0.1:8765", timeout=60)
    db = __import__("pgcompat").get_db()
    made = make_admins(c, db, "t12", ("admin",))
    email, pw = f"t12-usage-{uuid.uuid4().hex[:6]}@example.com", "T12UsagePass123"
    uid = None
    AD = {}
    try:
        AD = admin_login(c, made["admin"])
        admin_reset(c, AD)
        c.post("/api/auth/register", json={"name": "T12 Usage", "email": email, "password": pw})
        db.users.update_one({"email": email}, {"$set": {
            "is_verified": True, "subscription_type": "premium",
            "subscription_expires_at": datetime.now(UTC) + timedelta(days=30)}})
        uid = db.users.find_one({"email": email})["_id"]
        U = {"Authorization": "Bearer " + c.post("/api/auth/login", json={"email": email, "password": pw}).json()["access_token"]}

        def stats():
            return c.get("/api/admin/ai-usage/stats", headers=AD)

        def mine():
            r = c.get("/api/admin/ai-usage/users", headers=AD, params={"limit": 100})
            return next((u for u in r.json() if u["user_id"] == uid), None) if r.status_code == 200 else None

        def chat():
            return c.post("/api/chat/stream", headers=U, json={"message": "hi"})

        before = stats()
        b = before.json().get("cost_by_provider", {}) if before.status_code == 200 else {}
        check(before.status_code == 200 and isinstance(b, dict) and "openai_total_cost" not in before.json()
              and "gemini_total_cost" not in before.json(),
              "usage_stats_include_claude: stats has cost_by_provider and no fixed openai/gemini fields",
              f"{before.status_code} {before.text[:200]}")

        # --- a claude-answered request
        put = c.put("/api/admin/ai/settings/chat", headers=AD,
                    json={"main": {"provider": "claude", "model": "claude-sonnet-5-5"}, "backups": None})
        check(put.status_code == 200, "usage_stats_include_claude: PUT chat = claude", f"{put.status_code} {put.text[:200]}")
        r = chat()
        check(r.status_code == 200 and "Fake answer" in r.text, "usage_stats_include_claude: the claude chat answered",
              f"{r.status_code} {r.text[:200]}")
        after = stats().json()
        a = after.get("cost_by_provider", {})
        check(a.get("claude", 0) > 0 and a.get("claude", 0) > b.get("claude", 0),
              "usage_stats_include_claude: cost_by_provider['claude'] > 0 and grew", (b, a))
        check(all(isinstance(v, (int, float)) for v in a.values()) and abs(sum(a.values()) - after["total_cost_usd"]) < 0.001,
              "usage_stats: the provider costs add up to the total", (a, after["total_cost_usd"]))

        u = mine() or {}
        uc = u.get("cost_by_provider", {})
        check(uc.get("claude", 0) > 0 and "openai_cost" not in u and "gemini_cost" not in u
              and abs(sum(uc.values()) - u.get("total_cost_usd", -1)) < 0.001,
              "usage_stats_include_claude: the per-user row has cost_by_provider with claude", u)

        # --- records carry fallback_from; a backup answer names the provider that failed
        recs = c.get(f"/api/admin/ai-usage/user/{uid}", headers=AD).json()
        check(isinstance(recs, list) and len(recs) == 1 and "fallback_from" in recs[0] and recs[0]["fallback_from"] is None
              and recs[0]["provider"] == "claude",
              "usage_records_include_fallback_from: a first-choice answer has fallback_from null", recs)
        admin_reset(c, AD)
        c.put("/api/admin/ai/settings/chat", headers=AD,
              json={"main": {"provider": "claude", "model": "claude-sonnet-5-5"}, "backups": None})
        stubenv.set_fake_ai(claude="billing")
        r = chat()
        check(r.status_code == 200 and "Fake answer" in r.text, "usage_records_include_fallback_from: the backup answered",
              f"{r.status_code} {r.text[:200]}")
        recs = c.get(f"/api/admin/ai-usage/user/{uid}", headers=AD).json()
        got = sorted((x["provider"], x["fallback_from"]) for x in recs)
        check(len(recs) == 2 and ("openai", "claude") in got and ("claude", None) in got,
              "usage_records_include_fallback_from: the backup's record names fallback_from claude", got)
        u = mine() or {}
        # (the fake's openai cost rounds to 0.0 at 4 places, so check the key is listed, not its size)
        check("openai" in u.get("cost_by_provider", {}) and u.get("cost_by_provider", {}).get("claude", 0) > 0,
              "usage_stats: the per-user row has both the claude and the backup's provider", u)
    finally:
        try:
            if AD:
                admin_reset(c, AD)
        finally:
            try:
                if uid:
                    await execute(delete(users).where(users.c.id == uid))  # cascades to its ai_usage rows
            finally:
                db.admins.delete_many({"email": {"$in": list(made.values())}})
                c.close()


async def all_async_checks():
    resolution_checks()  # pure; kept inside the single event loop run per the suite's convention
    await fake_checks()
    await kind_checks()
    migration_checks()
    await panel_checks()
    error_checks()
    await health_checks()
    await client_checks()
    control_format_checks()
    try:
        await runner_checks()
    except Exception as e:  # noqa: BLE001 - report instead of aborting the suite
        import traceback
        traceback.print_exc()
        check(False, "runner_checks ran to completion", repr(e))
    await refresh_race_checks()
    try:
        await admin_api_checks()
    except Exception as e:  # noqa: BLE001 - report instead of aborting the suite
        import traceback
        traceback.print_exc()
        check(False, "admin_api_checks ran to completion", repr(e))
    try:
        await chat_checks()
    except Exception as e:  # noqa: BLE001 - report instead of aborting the suite
        import traceback
        traceback.print_exc()
        check(False, "chat_checks ran to completion", repr(e))
    try:
        await insight_checks()
    except Exception as e:  # noqa: BLE001 - report instead of aborting the suite
        import traceback
        traceback.print_exc()
        check(False, "insight_checks ran to completion", repr(e))
    try:
        await budget_checks()
    except Exception as e:  # noqa: BLE001 - report instead of aborting the suite
        import traceback
        traceback.print_exc()
        check(False, "budget_checks ran to completion", repr(e))
    try:
        await transaction_checks()
    except Exception as e:  # noqa: BLE001 - report instead of aborting the suite
        import traceback
        traceback.print_exc()
        check(False, "transaction_checks ran to completion", repr(e))
    try:
        await usage_stats_checks()
    except Exception as e:  # noqa: BLE001 - report instead of aborting the suite
        import traceback
        traceback.print_exc()
        check(False, "usage_stats_checks ran to completion", repr(e))


def stub_mode_checks():
    """Outside fake mode (E2E_FAKE_AI unset) every client still raises AIStubError."""
    code = (
        "import asyncio, os, sys; sys.path.insert(0, os.path.dirname(%r)); import stubenv, openai, anthropic\n"
        "from google import genai\n"
        "async def go():\n"
        "    out = []\n"
        "    for f in (lambda: openai.AsyncOpenAI().chat.completions.create(model='m', messages=[]),\n"
        "              lambda: genai.Client().aio.models.generate_content(model='m', contents='x'),\n"
        "              lambda: anthropic.AsyncAnthropic().beta.messages.create(model='m', max_tokens=1, messages=[])):\n"
        "        try:\n"
        "            await f(); out.append('ok')\n"
        "        except stubenv.AIStubError:\n"
        "            out.append('stub')\n"
        "    print(','.join(out))\n"
        "asyncio.run(go())\n" % os.path.abspath(__file__)
    )
    import subprocess
    env = {k: v for k, v in os.environ.items() if k != "E2E_FAKE_AI"}
    p = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, env=env, timeout=120)
    check(p.stdout.strip() == "stub,stub,stub", "without E2E_FAKE_AI all three clients raise AIStubError",
          (p.stdout + p.stderr)[-300:])


def main():
    stubenv.clear_fake_ai()
    try:
        asyncio.run(all_async_checks())  # ONE event loop: the backend's async DB engine binds to the first loop
        stub_mode_checks()
    finally:
        stubenv.clear_fake_ai()
    failed = results.count(False)
    print(f"\n{len(results) - failed}/{len(results)} passed", flush=True)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
