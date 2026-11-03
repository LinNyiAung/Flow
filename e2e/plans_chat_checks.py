"""Task 5 checks for test_plans: AI chat on the quota engine, and Pro's Advanced chat.

Run from test_plans (inside its single asyncio.run): `await plans_chat_checks.run(test_plans_module)`.
Everything goes over HTTP to the stubbed server with the fake AI providers: plans change through the admin users API,
the Advanced chain through the admin AI settings API, and provider failures through stubenv.set_fake_ai. The database
is used only to preset a counter (set_used, as the task 3 checks do) and to read results. At the end the fakes are
cleared, the AI settings and provider health are put back, and every user the checks made is removed.
"""
import asyncio
import json
import os
import uuid
from datetime import datetime, UTC

import httpx

BASE = "http://127.0.0.1:8765"
META_KEYS = {"chunk", "done", "mode_used", "advanced_exhausted", "timestamp"}
PROVIDERS = ("openai", "gemini", "claude")
AI_FEATURES = ("chat", "chat_advanced")


def frames_of(text):
    return [json.loads(line[6:]) for line in text.split("\n") if line.startswith("data: ")]


def outbox_lines():
    import stubenv
    if not os.path.exists(stubenv.OUTBOX):
        return []
    with open(stubenv.OUTBOX, encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def is_meta(frame, mode, exhausted):
    return (set(frame) == META_KEYS and frame["chunk"] == "" and frame["done"] is False
            and frame["mode_used"] == mode and frame["advanced_exhausted"] is exhausted)


def answered(frames):
    """A normal reply after the meta frame: text chunks, then done with the full response."""
    body = frames[1:]
    chunks = [f for f in body[:-1] if f.get("done") is False and f.get("chunk")]
    last = body[-1] if body else {}
    return (len(body) >= 2 and len(chunks) == len(body) - 1 and not any("error" in f for f in frames)
            and last.get("done") is True and last.get("full_response") == "".join(f["chunk"] for f in chunks)
            and "Fake answer" in last["full_response"])


async def run(t):
    """t: the test_plans module (check, connect, make_admins, admin_login)."""
    import stubenv
    from plans import periods

    check = t.check
    c = httpx.Client(base_url=BASE, timeout=60)
    db = __import__("pgcompat").get_db()
    made = t.make_admins(db, ("admin",))
    AD = t.admin_login(c, made["admin"])
    tag = uuid.uuid4().hex[:5]

    def register(name):
        email = f"t5c-{name}-{tag}@example.com"
        c.post("/api/auth/register", json={"name": name, "email": email, "password": "secret123"})
        db.users.update_one({"email": email}, {"$set": {"is_verified": True}})
        token = c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json()["access_token"]
        return db.users.find_one({"email": email})["_id"], {"Authorization": f"Bearer {token}"}

    def set_plan(uid, plan):
        return c.put(f"/api/admin/users/{uid}/subscription", headers=AD, json={"subscription_type": plan}).status_code == 200

    def used(uid, feature, period):
        start = periods.period_start(period, datetime.now(UTC))
        with t.connect() as conn:
            row = conn.execute("SELECT used FROM usage_counters WHERE user_id = %s AND feature = %s AND period = %s "
                               "AND period_start = %s", (uid, feature, period, start)).fetchone()
        return row[0] if row else 0

    def counts(uid):
        return {f"{f}/{p}": used(uid, f, p) for f in AI_FEATURES for p in ("week", "month")}

    def set_used(uid, feature, n):
        now = datetime.now(UTC)
        with t.connect() as conn:
            for period in ("week", "month"):
                conn.execute("INSERT INTO usage_counters (user_id, feature, period, period_start, used) VALUES (%s, %s, %s, %s, %s) "
                             "ON CONFLICT (user_id, feature, period, period_start) DO UPDATE SET used = EXCLUDED.used",
                             (uid, feature, period, periods.period_start(period, now), n))

    def history(uid):
        with t.connect() as conn:
            return conn.execute("SELECT count(*) FROM chat_messages m JOIN chat_sessions s ON m.session_id = s.id "
                                "WHERE s.user_id = %s", (uid,)).fetchone()[0]

    def chat(h, mode=None, message="How much did I spend?"):
        """-> (response, frames, [(provider, model) of each AI call it made])."""
        before = len(outbox_lines())
        body = {"message": message} if mode is None else {"message": message, "mode": mode}
        r = c.post("/api/chat/stream", headers=h, json=body)
        fr = frames_of(r.text) if r.status_code == 200 else []
        calls = [(x.get("provider"), x.get("model")) for x in outbox_lines()[before:] if x.get("kind") == "ai_call"]
        return r, fr, calls

    def reset_ai():
        """Fakes cleared, chat / Advanced settings back to their defaults, and every provider's cool-off cleared."""
        stubenv.clear_fake_ai()
        for f in AI_FEATURES:
            c.delete(f"/api/admin/ai/settings/{f}", headers=AD)
        for p in PROVIDERS:
            c.post(f"/api/admin/ai/test/{p}", headers=AD, json={})

    def plus_one(before, after, *keys):
        """Exactly the counters in `keys` went up by one; every other chat counter is unchanged."""
        return all(after[k] == before[k] + (1 if k in keys else 0) for k in before)

    try:
        reset_ai()
        r = c.get("/api/admin/ai/settings", headers=AD)
        row = {f["key"]: f for f in r.json().get("features", [])}.get("chat_advanced", {}) if r.status_code == 200 else {}
        check(row.get("label") == "Advanced chat" and row.get("allowed") == list(PROVIDERS)
              and row.get("effective") == {"main": {"provider": "claude", "model": "claude-sonnet-5-5"}, "backups": None,
                                           "source": "default"},
              "advanced_chat_feature: the AI settings list 'Advanced chat', all providers allowed, default claude-sonnet-5-5",
              row or f"{r.status_code} {r.text[:200]}")

        # ---- chat_counts_and_limits: a Free user gets 5 streamed chats a week, the sixth is refused
        fid, fh = register("free")
        results = [chat(fh) for _ in range(5)]
        check(all(r.status_code == 200 and answered(fr) for r, fr, _ in results),
              "chat_counts_and_limits: a Free user's five chats stream normal answers",
              [(r.status_code, fr[-1:]) for r, fr, _ in results if not answered(fr)][:2])
        check(all(fr and is_meta(fr[0], "standard", False) for _, fr, _ in results),
              "stream_meta: the first frame is {chunk '', done false, mode_used standard, advanced_exhausted false, timestamp}",
              results[0][1][:1])
        check(used(fid, "chat", "week") == 5 and used(fid, "chat_advanced", "week") == 0,
              "chat_counts_and_limits: five chats count 5 of the week's chat allowance", counts(fid))
        r, fr, calls = chat(fh)
        d = r.json().get("detail") if r.status_code == 429 else None
        check(r.status_code == 429 and isinstance(d, dict) and d.get("code") == "plan_limit_reached" and d.get("feature") == "chat"
              and d.get("resets_at") and d.get("upgrade_available") is True and not calls,
              "chat_counts_and_limits: the sixth gets 429 plan_limit_reached (feature chat), before any AI call",
              f"{r.status_code} {r.text[:200]} {calls}")
        check(used(fid, "chat", "week") == 5, "chat_counts_and_limits: the refused chat counted nothing", counts(fid))
        p = c.get("/api/plan", headers=fh).json().get("features", {}).get("chat", {})
        check(p.get("used") == 5 and p.get("remaining") == 0, "chat_counts_and_limits: GET /api/plan shows chat 5 used, 0 left", p)

        # ---- chat_fail_releases: every provider fails before the first chunk
        uid, h = register("fail")
        before, m0 = counts(uid), history(uid)
        stubenv.set_fake_ai(openai="server", gemini="server", claude="server")
        try:
            r, fr, calls = chat(h)
        finally:
            reset_ai()
        check(r.status_code == 200 and len(fr) == 2 and is_meta(fr[0], "standard", False) and fr[-1].get("error")
              and fr[-1].get("done") is True and calls,
              "chat_fail_releases: the stream is the meta frame, then the error frame", f"{r.status_code} {fr} {calls}")
        check(counts(uid) == before and history(uid) == m0,
              "chat_fail_releases: the failed chat used nothing and saved nothing", (before, counts(uid)))
        r, fr, _ = chat(h)
        check(answered(fr) and plus_one(before, counts(uid), "chat/week", "chat/month"),
              "chat_fail_releases: the next chat that answers counts once (week and month)", (before, counts(uid)))

        # ---- chat_midstream_failure_releases: partial text, then the provider fails: a failed request, not counted
        before, m0 = counts(uid), history(uid)
        stubenv.set_fake_ai(openai="fail_mid_stream", gemini="fail_mid_stream", claude="fail_mid_stream")
        try:
            r, fr, calls = chat(h)
        finally:
            reset_ai()
        check(r.status_code == 200 and len(fr) >= 3 and is_meta(fr[0], "standard", False) and fr[1].get("chunk")
              and fr[-1].get("error") and fr[-1].get("done") is True and len(calls) == 1,
              "chat_midstream_failure_releases: the meta frame, a chunk, then the error frame (no second provider)",
              f"{r.status_code} {fr} {calls}")
        check(counts(uid) == before and history(uid) == m0,
              "chat_midstream_failure_releases: the failed answer used nothing and saved nothing", (before, counts(uid)))
        r, fr, _ = chat(h)
        check(answered(fr) and plus_one(before, counts(uid), "chat/week", "chat/month"),
              "chat_completion_counts_once: a completed answer counts exactly once", (before, counts(uid)))

        # ---- chat_disconnect_counts: the client goes away after the first chunk, then before it
        uid, h = register("disconnect")
        before, m0 = counts(uid), history(uid)
        stubenv.set_fake_ai(openai="slow", gemini="slow", claude="slow")
        seen = []
        try:
            with c.stream("POST", "/api/chat/stream", headers=h, json={"message": "hi"}) as resp:
                for line in resp.iter_lines():
                    if line.startswith("data: "):
                        seen.append(json.loads(line[6:]))
                        if seen[-1].get("chunk"):
                            break  # leaving the block closes the connection mid-stream
            await asyncio.sleep(4)  # the rest of the slow answer would have streamed by now
            after_first = counts(uid)
            check(len(seen) == 2 and is_meta(seen[0], "standard", False) and seen[1].get("chunk")
                  and plus_one(before, after_first, "chat/week", "chat/month") and history(uid) == m0,
                  "chat_disconnect_counts: closing after the first chunk keeps the use (+1), and the cut answer is not saved",
                  (seen, before, after_first, history(uid)))
            seen = []
            with c.stream("POST", "/api/chat/stream", headers=h, json={"message": "hi"}) as resp:
                for line in resp.iter_lines():
                    if line.startswith("data: "):
                        seen.append(json.loads(line[6:]))
                        break  # the meta frame only: gone before any answer text
            await asyncio.sleep(4)
            check(len(seen) == 1 and is_meta(seen[0], "standard", False) and counts(uid) == after_first,
                  "chat_disconnect_counts: closing before the first chunk gives the use back", (seen, after_first, counts(uid)))
        finally:
            reset_ai()

        # ---- advanced_uses_advanced_chain: Pro + Advanced runs the chat_advanced chain (built-in claude-sonnet-5-5)
        pro, ph = register("pro")
        check(set_plan(pro, "pro"), "advanced: a Pro user is set through the admin API")
        before = counts(pro)
        r, fr, calls = chat(ph, "advanced")
        check(r.status_code == 200 and answered(fr) and is_meta(fr[0], "advanced", False),
              "advanced_uses_advanced_chain: the answer streams with mode_used advanced, advanced_exhausted false", fr[:1])
        check(calls == [("claude", "claude-sonnet-5-5")],
              "advanced_uses_advanced_chain: the chat_advanced main (claude-sonnet-5-5) answered, not the chat chain", calls)
        check(plus_one(before, counts(pro), "chat/week", "chat/month", "chat_advanced/week", "chat_advanced/month"),
              "advanced_uses_advanced_chain: chat and chat_advanced each +1", (before, counts(pro)))
        r = c.put("/api/admin/ai/settings/chat_advanced", headers=AD,
                  json={"main": {"provider": "openai", "model": "gpt-4o"}, "backups": []})
        before = counts(pro)
        r2, fr, calls = chat(ph, "advanced")
        check(r.status_code == 200 and answered(fr) and is_meta(fr[0], "advanced", False) and calls == [("openai", "gpt-4o")]
              and plus_one(before, counts(pro), "chat/week", "chat/month", "chat_advanced/week", "chat_advanced/month"),
              "advanced_uses_advanced_chain: the owner's Advanced setting (openai gpt-4o) is what answers", (r.status_code, calls))
        before = counts(pro)
        r, fr, calls = chat(ph, "standard")
        check(answered(fr) and is_meta(fr[0], "standard", False) and calls == [("gemini", "gemini-2.5-flash")]
              and plus_one(before, counts(pro), "chat/week", "chat/month"),
              "advanced: a Pro user's Standard message runs the chat chain and counts chat only", (calls, before, counts(pro)))
        reset_ai()

        # ---- advanced_exhausted_falls_back: chat_advanced 100/100 -> answered as Standard, flagged
        set_used(pro, "chat_advanced", 100)
        before = counts(pro)
        r, fr, calls = chat(ph, "advanced")
        check(r.status_code == 200 and answered(fr) and is_meta(fr[0], "standard", True),
              "advanced_exhausted_falls_back: answered with mode_used standard, advanced_exhausted true", fr[:1])
        check(calls == [("gemini", "gemini-2.5-flash")] and plus_one(before, counts(pro), "chat/week", "chat/month"),
              "advanced_exhausted_falls_back: the chat chain answered and only chat +1 (Advanced stays 100)", (calls, before, counts(pro)))
        p = c.get("/api/plan", headers=ph).json().get("features", {})
        check(p.get("chat_advanced", {}).get("remaining") == 0 and p.get("chat", {}).get("used") == before["chat/month"] + 1,
              "advanced_exhausted_falls_back: GET /api/plan shows Advanced 0 left", p.get("chat_advanced"))
        set_used(pro, "chat_advanced", 0)

        # ---- advanced_from_plus_is_standard (and from Free)
        plus, plh = register("plus")
        check(set_plan(plus, "plus"), "advanced: a Plus user is set through the admin API")
        for label, uid, h in (("Plus", plus, plh), ("Free", fid, None)):
            if h is None:
                set_used(fid, "chat", 0)
                h = fh
            before = counts(uid)
            r, fr, calls = chat(h, "advanced")
            check(r.status_code == 200 and answered(fr) and is_meta(fr[0], "standard", False)
                  and calls == [("gemini", "gemini-2.5-flash")] and plus_one(before, counts(uid), "chat/week", "chat/month"),
                  f"advanced_from_plus_is_standard: a {label} user's Advanced request is answered as Standard (chat +1 only)",
                  (r.status_code, fr[:1], calls, before, counts(uid)))
        r = c.post("/api/chat/stream", headers=plh, json={"message": "hi", "mode": "turbo"})
        check(r.status_code == 422, "chat_mode: an unknown mode is 422", r.status_code)

        # ---- advanced_backup_counts_advanced: the Advanced main is out of credit, its backup answers
        before = counts(pro)
        stubenv.set_fake_ai(claude="billing")
        try:
            r, fr, calls = chat(ph, "advanced")
        finally:
            reset_ai()
        check(r.status_code == 200 and answered(fr) and is_meta(fr[0], "advanced", False)
              and [p for p, _ in calls] == ["claude", "openai"],
              "advanced_backup_counts_advanced: claude fails on billing, the default backup (openai) answers as Advanced",
              (r.status_code, fr[:1], calls))
        check(plus_one(before, counts(pro), "chat/week", "chat/month", "chat_advanced/week", "chat_advanced/month"),
              "advanced_backup_counts_advanced: it counts as Advanced (chat and chat_advanced +1)", (before, counts(pro)))

        # ---- the deprecated non-streaming endpoint stays gone, for every plan
        check(c.post("/api/chat", headers=fh, json={"message": "x"}).status_code == 410
              and c.post("/api/chat", headers=ph, json={"message": "x", "mode": "advanced"}).status_code == 410,
              "chat_deprecated: /api/chat is 410 for Free and Pro (no AI call, nothing counted)")
    finally:
        try:
            reset_ai()
        finally:
            db.users.delete_many({"email": {"$regex": f"^t5c-.*-{tag}@"}})
            db.admins.delete_many({"email": {"$in": list(made.values())}})
            c.close()
