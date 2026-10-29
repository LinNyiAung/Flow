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


async def all_async_checks():
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
