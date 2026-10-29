"""AI provider switching: fake provider SDKs, failure control, and (in later tasks) the runner and admin API.

Print-only suite: every check prints [PASS] or [BUG]; the exit code is non-zero if any check failed.
"""
import asyncio
import json
import os
import sys

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
                                            max_tokens=100, stream=stream, **kw)
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
        "openai": ["gpt-4o-mini", "gpt-4o", "whisper-1"],
        "gemini": ["gemini-2.5-flash", "gemini-2.5-pro"],
        "claude": ["claude-sonnet-5-5", "claude-haiku-5-5", "claude-opus-5-5"]}, "catalogue: known models")
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
    f = classify(genai_errors.ClientError(429, {"error": {"code": 429, "message": "prepayment credits depleted",
                                                          "status": "RESOURCE_EXHAUSTED"}}), "gemini", "m")
    check(f is not None and f.kind == "rate_limit", "classify: 429 without an explicit billing signal is rate_limit", f)
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
        check(health.is_available(T("gemini", "gemini-2.5-flash"), t0), "health: refusal, unusable and timeout never cool off")

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
          and k["output_config"] == {"format": {"type": "json_schema", "schema": {"type": "object"}}, "effort": "low"},
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
    import base64
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
    check(_field(gk["config"], "system_instruction") == "s", "gemini: system goes in system_instruction")

    # openai and gemini request shapes
    await get_client("openai").complete("gpt-4o-mini", Prompt("s", "hi", json_schema={"type": "object"}, max_tokens=77))
    k = stubenv.LAST_KWARGS["openai"]
    check(k["response_format"] == {"type": "json_object"} and k["max_tokens"] == 77 and k["model"] == "gpt-4o-mini",
          "openai: json_schema -> response_format json_object", k)
    await get_client("openai").complete("gpt-4o-mini", Prompt("s", "hi"))
    check("response_format" not in stubenv.LAST_KWARGS["openai"], "openai: no response_format without json_schema")
    async for _ in get_client("openai").stream("gpt-4o-mini", Prompt("s", "hi")):
        pass
    k = stubenv.LAST_KWARGS["openai"]
    check(k["stream"] is True and k["stream_options"] == {"include_usage": True}, "openai: stream asks for usage", k)
    await get_client("gemini").complete("gemini-2.5-flash", Prompt("s", "hi", json_schema={"type": "object"}, max_tokens=55))
    cfg = stubenv.LAST_KWARGS["gemini"]["config"]
    check(_field(cfg, "response_mime_type") == "application/json" and _field(cfg, "max_output_tokens") == 55
          and stubenv.LAST_KWARGS["gemini"]["contents"] == "hi", "gemini: json_schema -> response_mime_type", cfg)
    await get_client("gemini").complete("gemini-2.5-flash", Prompt("s", "hi"))
    check(_field(stubenv.LAST_KWARGS["gemini"]["config"], "response_mime_type") is None,
          "gemini: no mime type without json_schema")

    # transcription
    r = await get_client("gemini").transcribe("gemini-2.5-flash", b"RIFFxxxx", "note.m4a", "my")
    gk = stubenv.LAST_KWARGS["gemini"]
    check(r.text == "fake transcript" and r.finish == "stop", "gemini_transcribe: returns the transcript", r)
    check(gk["contents"][0].inline_data.mime_type == "audio/mp4" and gk["contents"][0].inline_data.data == b"RIFFxxxx"
          and "Transcribe this audio exactly. Reply with only the transcript." in gk["contents"][1]
          and "my" in gk["contents"][1], "gemini_transcribe: audio part, mime from extension, instruction and language", gk["contents"])
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
    from types import SimpleNamespace as NS
    msg = NS(content=[NS(type="thinking", thinking="hmm"), NS(type="fallback"), NS(type="text", text="a"),
                      NS(type="text", text="b")], stop_reason="end_turn", usage=NS(input_tokens=3, output_tokens=4))
    check(claude_client.text_of(msg) == "ab" and claude_client.text_of(NS(content=[])) == "",
          "claude: text is the concatenation of text blocks only")


def _field(obj, name):
    return stubenv._field(obj, name)


async def all_async_checks():
    resolution_checks()  # pure; kept inside the single event loop run per the suite's convention
    await fake_checks()
    await kind_checks()
    migration_checks()
    await panel_checks()
    error_checks()
    await health_checks()
    await client_checks()


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
