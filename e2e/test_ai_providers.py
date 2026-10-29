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
    """Task 2: feature catalogue and setting resolution (environment and built-in). Pure Python."""
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


async def all_async_checks():
    resolution_checks()  # pure; kept inside the single event loop run per the suite's convention
    await fake_checks()
    await kind_checks()


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
