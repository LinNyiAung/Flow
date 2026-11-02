"""Task 6 checks for test_plans: transaction entry (receipt photo, text, voice), AI budget suggestions, the AI budget
auto-create (paid plans only) and the Reports PDF download, all on the quota engine; batch-create open to every plan.

Run from test_plans (inside its single asyncio.run): `await plans_entry_checks.run(test_plans_module)`.
Everything goes over HTTP to the stubbed server with the fake AI providers; plans change through the admin users API and
the cost cap through the admin Plans API. The database is used only to preset a counter or a cost row (as the task 3
checks do) and to read results. The auto-create checks call budget_service in this process (the fake AI clients are
installed here too). At the end the fakes are cleared, the default plans are put back and every user made is removed.
"""
import io
import re
import time
import uuid
from datetime import datetime, timedelta, UTC

import httpx
from PIL import Image

BASE = "http://127.0.0.1:8765"
PROVIDERS = ("openai", "gemini", "claude")
TOKEN_RE = re.compile(r"^\d+\.[A-Za-z0-9_-]{43}$")
SUGGEST = {"period": "monthly", "start_date": datetime.now(UTC).isoformat(), "currency": "usd", "analysis_months": 3}
_buf = io.BytesIO()
Image.new("RGB", (8, 8), (200, 30, 30)).save(_buf, "PNG")
PNG = _buf.getvalue()


def outbox_lines():
    import plans_chat_checks
    return plans_chat_checks.outbox_lines()


def ai_calls_since(n):
    return [x for x in outbox_lines()[n:] if x.get("kind") == "ai_call"]


def plan_error(r, status, code, feature):
    """The response is the refusal {"detail": {code, feature, resets_at, upgrade_available, message}}."""
    d = r.json().get("detail") if r.status_code == status else None
    return (isinstance(d, dict) and d.get("code") == code and d.get("feature") == feature
            and set(d) == {"code", "feature", "resets_at", "upgrade_available", "message"} and d.get("message"))


async def run(t):
    """t: the test_plans module (check, connect, make_admins, admin_login, default_body)."""
    import stubenv
    from plans import periods, store, voice_token

    check = t.check
    c = httpx.Client(base_url=BASE, timeout=120)
    db = __import__("pgcompat").get_db()
    made = t.make_admins(db, ("admin",))
    AD = t.admin_login(c, made["admin"])
    tag = uuid.uuid4().hex[:5]
    await store.load()

    def register(name):
        email = f"t6e-{name}-{tag}@example.com"
        c.post("/api/auth/register", json={"name": name, "email": email, "password": "secret123"})
        db.users.update_one({"email": email}, {"$set": {"is_verified": True}})
        token = c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json()["access_token"]
        return db.users.find_one({"email": email})["_id"], {"Authorization": f"Bearer {token}"}

    def set_plan(uid, plan, expires=None):
        body = {"subscription_type": plan}
        if expires is not None:
            body["subscription_expires_at"] = expires.isoformat()
        return c.put(f"/api/admin/users/{uid}/subscription", headers=AD, json=body).status_code == 200

    def used(uid, feature, period="month"):
        start = periods.period_start(period, datetime.now(UTC))
        with t.connect() as conn:
            row = conn.execute("SELECT used FROM usage_counters WHERE user_id = %s AND feature = %s AND period = %s "
                               "AND period_start = %s", (uid, feature, period, start)).fetchone()
        return row[0] if row else 0

    def set_used(uid, feature, n):
        now = datetime.now(UTC)
        with t.connect() as conn:
            for period in ("week", "month"):
                conn.execute("INSERT INTO usage_counters (user_id, feature, period, period_start, used) VALUES (%s, %s, %s, %s, %s) "
                             "ON CONFLICT (user_id, feature, period, period_start) DO UPDATE SET used = EXCLUDED.used",
                             (uid, feature, period, periods.period_start(period, now), n))

    def add_cost(uid, usd):
        with t.connect() as conn:
            conn.execute("INSERT INTO ai_usage (id, user_id, feature_type, provider, model_name, estimated_cost_usd, created_at) "
                         "VALUES (%s, %s, 'chat', 'openai', 'gpt-test', %s, %s)", (str(uuid.uuid4()), uid, usd, datetime.now(UTC)))

    def add_transactions(h, n):
        for i in range(n):
            c.post("/api/transactions", headers=h, json={
                "type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries", "amount": 10 + i,
                "currency": "usd", "date": (datetime.now(UTC) - timedelta(days=i)).isoformat(), "description": f"t6 groceries {i}"})

    def text(h, body="coffee 2.5 dollars", **extra):
        return c.post("/api/transactions/extract-from-text", headers=h, json={"text": body, **extra})

    def multi(h, body="lunch 4.5, grab 3, something", **extra):
        return c.post("/api/transactions/extract-multiple-from-text", headers=h, json={"text": body, **extra})

    def image(h, data=PNG):
        return c.post("/api/transactions/extract-from-image", headers=h, files={"image": ("r.png", data, "image/png")})

    def audio(h):
        return c.post("/api/transactions/transcribe-audio", headers=h, files={"audio": ("voice.m4a", b"\x00\x01\x02\x03", "audio/mp4")})

    def calls_of(post):
        """-> (response, the AI calls it made)."""
        before = len(outbox_lines())
        r = post()
        return r, ai_calls_since(before)

    def reset_ai():
        """Fakes cleared and every provider's cool-off cleared (a failing provider is skipped for a while)."""
        stubenv.clear_fake_ai()
        for p in PROVIDERS:
            c.post(f"/api/admin/ai/test/{p}", headers=AD, json={})

    def fake_all(kind):
        stubenv.set_fake_ai(**{p: kind for p in PROVIDERS})

    try:
        reset_ai()

        # ---- entry_shared_count: text, image and multiple-text draw from one count; the 11th Free use is refused
        fid, fh = register("free")
        rs = [text(fh), image(fh), multi(fh)]
        check(all(r.status_code == 200 for r in rs) and used(fid, "entry") == 3,
              "entry_shared_count: a text, an image and a multiple-text extraction each count once, in one shared count (3)",
              ([r.status_code for r in rs], used(fid, "entry")))
        rs = [post(fh) for post in (text, image, multi, text, image, multi, text)]
        check(all(r.status_code == 200 for r in rs) and used(fid, "entry") == 10 and used(fid, "entry", "week") == 10,
              "entry_shared_count: ten uses of the three kinds in all, counted on the month and the week", used(fid, "entry"))
        for label, post in (("text", text), ("image", image), ("multiple-text", multi), ("voice", audio)):
            r, calls = calls_of(lambda: post(fh))
            check(plan_error(r, 429, "plan_limit_reached", "entry") and r.json()["detail"]["resets_at"]
                  and r.json()["detail"]["upgrade_available"] is True and not calls,
                  f"entry_shared_count: the 11th Free use ({label}) gets 429 plan_limit_reached before any AI call",
                  f"{r.status_code} {r.text[:200]} {len(calls)} calls")
        p = c.get("/api/plan", headers=fh).json().get("features", {}).get("entry", {})
        check(used(fid, "entry") == 10 and p.get("used") == 10 and p.get("remaining") == 0,
              "entry_shared_count: the refused requests counted nothing; GET /api/plan shows entry 10 used, 0 left", p)

        # ---- entry_zero_found_counts: a valid answer that finds no transactions is a use
        zid, zh = register("zero")
        fake_all("no_transactions")
        try:
            r = multi(zh, "nothing to report today")
        finally:
            reset_ai()
        body = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and body.get("transactions") == [] and body.get("total_count") == 0 and used(zid, "entry") == 1,
              "entry_zero_found_counts: an answer with no transactions is a 200 and still uses one", f"{r.status_code} {r.text[:200]} {used(zid, 'entry')}")

        # ---- entry_fail_releases: an error, every provider failing, an unusable answer, a bad image: nothing is used
        xid, xh = register("fail")
        failing = [("every provider fails (503)", "server", 503), ("an unusable answer from every provider (503)", "bad_json", 503),
                   ("a request-level error (400)", "odd_error", 400)]
        for label, kind, status in failing:
            for name, post in (("text", text), ("multiple-text", multi), ("image", image)):
                fake_all(kind)
                try:
                    r, calls = calls_of(lambda: post(xh))
                finally:
                    reset_ai()
                check(r.status_code == status and calls and used(xid, "entry") == 0,
                      f"entry_fail_releases: {name}, {label}, uses nothing", f"{r.status_code} {len(calls)} calls, used {used(xid, 'entry')}")
        fake_all("server")
        try:
            r, calls = calls_of(lambda: audio(xh))
        finally:
            reset_ai()
        check(r.status_code == 503 and calls and used(xid, "entry") == 0,
              "entry_fail_releases: voice, every provider fails (503), uses nothing", f"{r.status_code} {len(calls)} calls, used {used(xid, 'entry')}")
        r, calls = calls_of(lambda: image(xh, b"this is not an image"))
        check(r.status_code == 400 and not calls and used(xid, "entry") == 0,
              "entry_fail_releases: an invalid image (400, no AI call) uses nothing", f"{r.status_code} {r.text[:120]}")
        r = c.post("/api/transactions/transcribe-audio", headers=xh, files={"audio": ("a.m4a", b"\x00\x01", "audio/mp4")}, data={"language": "fr"})
        check(r.status_code == 400 and used(xid, "entry") == 0, "entry_fail_releases: an unsupported voice language (400) uses nothing", r.status_code)
        r = text(xh)
        check(r.status_code == 200 and used(xid, "entry") == 1,
              "entry_fail_releases: the next extraction that answers counts once (week and month)",
              (r.status_code, used(xid, "entry"), used(xid, "entry", "week")))

        # ---- voice_counts_once: transcribe, then extract with the voice_token: +1 in total
        vid, vh = register("voice")
        r = audio(vh)
        j = r.json() if r.status_code == 200 else {}
        tok = j.get("voice_token") or ""
        exp = int(tok.split(".")[0]) if TOKEN_RE.match(tok) else 0
        check(r.status_code == 200 and j.get("transcription") == "fake transcript" and set(j) == {"transcription", "voice_token"}
              and TOKEN_RE.match(tok) and abs(exp - (time.time() + 15 * 60)) < 120 and used(vid, "entry") == 1,
              "voice_counts_once: transcribe-audio uses one and returns {transcription, voice_token} (expiry 15 minutes out)",
              f"{r.status_code} {r.text[:200]} used {used(vid, 'entry')}")
        r, calls = calls_of(lambda: multi(vh, "fake transcript", voice_token=tok))
        check(r.status_code == 200 and len(r.json().get("transactions") or []) == 2 and calls and used(vid, "entry") == 1,
              "voice_counts_once: extract-multiple with the token runs the AI but adds nothing (still 1 in total)",
              f"{r.status_code} {len(calls)} calls, used {used(vid, 'entry')}")
        r = text(vh, "fake transcript", voice_token=tok)
        check(r.status_code == 200 and r.json().get("amount") == 2.5 and used(vid, "entry") == 1,
              "voice_counts_once: extract-from-text accepts the token the same way (still 1)", f"{r.status_code} {used(vid, 'entry')}")
        r = multi(vh, "  fake transcript \n", voice_token=tok)
        check(r.status_code == 200 and used(vid, "entry") == 1,
              "voice_counts_once: surrounding whitespace in the text does not matter (the transcript is stripped on both sides)",
              f"{r.status_code} {used(vid, 'entry')}")

        # ---- voice_token_wrong_text_counts: any other token is ignored and the request counts normally
        n = used(vid, "entry")
        r = multi(vh, "something else entirely", voice_token=tok)
        n += 1
        check(r.status_code == 200 and used(vid, "entry") == n,
              "voice_token_wrong_text_counts: the same token with different text counts (+1)", f"{r.status_code} {used(vid, 'entry')}")
        other_id, other_h = register("voice-other")
        for label, bad in (("without a token", None), ("with a garbage token", "abc"), ("with an empty token", ""),
                           ("with a token whose signature was changed", tok[:-1] + ("A" if tok[-1] != "A" else "B")),
                           ("with a token whose expiry was changed", str(exp + 60) + tok[tok.index("."):]),
                           ("with an expired token", voice_token.issue(vid, "fake transcript", now=time.time() - 16 * 60)),
                           ("with a token issued to another user", voice_token.issue(other_id, "fake transcript")),
                           ("with a very long token", "9" * 600)):
            r = multi(vh, "fake transcript", **({} if bad is None else {"voice_token": bad}))
            n += 1
            check(r.status_code == 200 and used(vid, "entry") == n,
                  f"voice_token_wrong_text_counts: the right text {label} counts normally (+1)", f"{r.status_code} {used(vid, 'entry')} want {n}")
        check(voice_token.is_valid(tok, vid, "fake transcript") and not voice_token.is_valid(tok, other_id, "fake transcript")
              and not voice_token.is_valid(tok, vid, "fake transcript.")
              and voice_token.is_valid(voice_token.issue(vid, "x"), vid, "x") and not voice_token.is_valid(None, vid, "x"),
              "voice_token: valid only for the user and the text it was issued for")

        # the token is what lets the follow-up through at the very limit its own transcription filled
        lid, lh = register("voice-limit")
        set_used(lid, "entry", 9)
        r = audio(lh)
        tok2 = (r.json() if r.status_code == 200 else {}).get("voice_token")
        check(r.status_code == 200 and tok2 and used(lid, "entry") == 10, "voice_counts_once: the transcription is the 10th use", used(lid, "entry"))
        r = multi(lh, "fake transcript", voice_token=tok2)
        check(r.status_code == 200 and used(lid, "entry") == 10,
              "voice_counts_once: at 10 of 10 the follow-up extraction with the token still goes through", f"{r.status_code} {r.text[:160]}")
        r, calls = calls_of(lambda: multi(lh, "fake transcript"))
        check(plan_error(r, 429, "plan_limit_reached", "entry") and not calls,
              "voice_counts_once: the same extraction without the token is refused (429)", f"{r.status_code} {r.text[:160]}")

        # the token does not get past the cost cap
        cid, ch = register("voice-cap")
        r = audio(ch)
        tok3 = (r.json() if r.status_code == 200 else {}).get("voice_token")
        body = t.default_body()
        body["plans"]["free"]["cost_cap_usd"] = 0
        r = c.put("/api/admin/plans", headers=AD, json=body)
        try:
            r2, calls = calls_of(lambda: multi(ch, "fake transcript", voice_token=tok3))
        finally:
            c.put("/api/admin/plans", headers=AD, json=t.default_body())
        check(r.status_code == 200 and plan_error(r2, 429, "plan_cost_cap", "entry") and not calls and used(cid, "entry") == 1,
              "voice_token: a user at the cost cap is refused even with a valid token (429 plan_cost_cap, nothing counted)",
              f"{r.status_code} {r2.status_code} {r2.text[:160]}")
        r = multi(ch, "fake transcript", voice_token=tok3)
        check(r.status_code == 200 and used(cid, "entry") == 1, "voice_token: with the cap back, the token works again", r.status_code)

        # ---- voice_silent_no_count: silence is a 200 with an empty transcription, no token, nothing used
        sid, sh = register("silent")
        stubenv.set_fake_ai(openai="empty", gemini="empty")
        try:
            r, calls = calls_of(lambda: audio(sh))
        finally:
            reset_ai()
        check(r.status_code == 200 and r.json() == {"transcription": ""} and len(calls) == 1 and used(sid, "entry") == 0,
              "voice_silent_no_count: silence is a 200 with an empty transcription, no voice_token, and uses nothing",
              f"{r.status_code} {r.text[:160]} {len(calls)} calls, used {used(sid, 'entry')}")
        check(used(sid, "entry", "week") == 0, "voice_silent_no_count: the week's row is given back too")

        # ---- batch_create_open_to_free: it saves a Free user's result and is not an AI call
        before = (used(fid, "entry"), len(outbox_lines()))
        items = [{"type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Coffee & Snacks",
                  "date": datetime.now(UTC).isoformat(), "amount": 3, "currency": "usd"},
                 {"type": "outflow", "main_category": "Transportation", "sub_category": "Taxi",
                  "date": datetime.now(UTC).isoformat(), "amount": 7, "currency": "usd"}]
        r = c.post("/api/transactions/batch-create", headers=fh, json=items)
        check(r.status_code == 200 and len(r.json()) == 2,
              "batch_create_open_to_free: a Free user at 10 of 10 entry uses saves two transactions (200)", f"{r.status_code} {r.text[:200]}")
        check((used(fid, "entry"), len(ai_calls_since(before[1]))) == (before[0], 0),
              "batch_create_open_to_free: it uses no allowance and makes no AI call")
        r = c.post("/api/transactions/batch-create", json=items)
        check(r.status_code in (401, 403), "batch_create_open_to_free: it still needs a signed-in user", r.status_code)

        # ---- budget_suggest_limit: a Free user gets one AI suggestion a month
        bid, bh = register("budget")
        add_transactions(bh, 12)
        r, calls = calls_of(lambda: c.post("/api/budgets/ai-suggest", headers=bh, json=SUGGEST))
        cats = (r.json().get("category_budgets") if r.status_code == 200 else None) or []
        check(r.status_code == 200 and len(calls) == 1 and cats and cats[0]["allocated_amount"] == 450 and used(bid, "budget_suggestion") == 1,
              "budget_suggest_limit: a Free user's first suggestion is the AI's (200) and uses the one a month",
              f"{r.status_code} {r.text[:160]} {len(calls)} calls, used {used(bid, 'budget_suggestion')}")
        r, calls = calls_of(lambda: c.post("/api/budgets/ai-suggest", headers=bh, json=SUGGEST))
        check(plan_error(r, 429, "plan_limit_reached", "budget_suggestion") and r.json()["detail"]["upgrade_available"] is True
              and not calls and used(bid, "budget_suggestion") == 1,
              "budget_suggest_limit: the second gets 429 plan_limit_reached before any AI call",
              f"{r.status_code} {r.text[:200]} {len(calls)} calls")
        check(c.get("/api/plan", headers=bh).json()["features"]["budget_suggestion"]["remaining"] == 0,
              "budget_suggest_limit: GET /api/plan shows 0 left")

        # a suggestion the AI did not answer (every provider down, or too little data to ask) uses nothing
        gid, gh = register("budget-fail")
        add_transactions(gh, 12)
        fake_all("server")
        try:
            r, calls = calls_of(lambda: c.post("/api/budgets/ai-suggest", headers=gh, json=SUGGEST))
        finally:
            reset_ai()
        check(r.status_code == 200 and calls and "temporarily unavailable" in " ".join(r.json().get("warnings") or [])
              and used(gid, "budget_suggestion") == 0,
              "budget_suggest_limit: every provider down -> the basic suggestions with a warning, and nothing is used",
              f"{r.status_code} {r.text[:200]} used {used(gid, 'budget_suggestion')}")
        fake_all("odd_error")
        try:
            r = c.post("/api/budgets/ai-suggest", headers=gh, json=SUGGEST)
        finally:
            reset_ai()
        check(r.status_code == 400 and used(gid, "budget_suggestion") == 0,
              "budget_suggest_limit: a request-level error (400) uses nothing", f"{r.status_code} {used(gid, 'budget_suggestion')}")
        r = c.post("/api/budgets/ai-suggest", headers=gh, json=SUGGEST)
        check(r.status_code == 200 and used(gid, "budget_suggestion") == 1,
              "budget_suggest_limit: the next suggestion the AI answers uses the one", f"{r.status_code} {used(gid, 'budget_suggestion')}")
        eid, eh = register("budget-few")
        add_transactions(eh, 3)
        r, calls = calls_of(lambda: c.post("/api/budgets/ai-suggest", headers=eh, json=SUGGEST))
        check(r.status_code == 200 and not calls and used(eid, "budget_suggestion") == 0,
              "budget_suggest_limit: too little data -> basic suggestions with no AI call, and nothing is used",
              f"{r.status_code} {len(calls)} calls, used {used(eid, 'budget_suggestion')}")

        # ---- auto_create_ai_only_paid: the AI-optimised auto-create is for Plus and Pro owners under their cost cap
        import budget_service as bs
        stubenv.patch_loaded_modules()
        now = datetime.now(UTC)
        window_end = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0) - timedelta(seconds=1)
        window_start = window_end.replace(day=1, hour=0, minute=0, second=0)

        async def auto_create(label, plan=None, expires=None, cost=None):
            """A completed AI auto-create budget with spending in its window; run the auto-create.
            -> (AI calls made, the child's allocation for Food & Daily Living, the owner's budget_suggestion count)."""
            uid, h = register(f"auto-{label}")
            if plan:
                set_plan(uid, plan, expires)
            if cost:
                add_cost(uid, cost)
            c.post("/api/transactions", headers=h, json={
                "type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries", "amount": 20, "currency": "usd",
                "date": (window_start + timedelta(days=3, hours=12)).isoformat(), "description": "t6 auto-create spend"})
            parent_id = f"t6-parent-{label}-{tag}"
            db.budgets.insert_one({
                "_id": parent_id, "user_id": uid, "name": f"T6 {label}", "period": "monthly", "currency": "usd",
                "start_date": window_start, "end_date": window_end,
                "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 50, "spent_amount": 0,
                                     "percentage_used": 0, "is_exceeded": False}],
                "total_budget": 50, "total_spent": 0, "remaining_budget": 50, "percentage_used": 0, "status": "completed",
                "is_active": False, "auto_create_enabled": True, "auto_create_with_ai": True, "created_at": now, "updated_at": now})
            before = len(outbox_lines())
            child_id = await bs.auto_create_next_budget(db.budgets.find_one({"_id": parent_id}))
            calls = ai_calls_since(before)
            child = db.budgets.find_one({"_id": child_id}) if child_id else None
            alloc = next((x["allocated_amount"] for x in (child or {}).get("category_budgets", [])
                          if x["main_category"] == "Food & Daily Living"), None)
            return len(calls), alloc, used(uid, "budget_suggestion"), child is not None and child.get("parent_budget_id") == parent_id

        # an AI-optimised budget for the fake answer is 450; the non-AI adjusted budget of 50 spent 0 is 40
        got = await auto_create("free")
        check(got == (0, 40.0, 0, True),
              "auto_create_ai_only_paid: a Free owner's auto-create makes no AI call and uses the adjusted budget (40)", got)
        got = await auto_create("plus", "plus")
        check(got == (1, 450, 0, True),
              "auto_create_ai_only_paid: a Plus owner's auto-create makes one AI call and uses its answer (450); no allowance used", got)
        got = await auto_create("pro", "pro")
        check(got == (1, 450, 0, True), "auto_create_ai_only_paid: a Pro owner's auto-create makes one AI call", got)
        got = await auto_create("expired", "plus", datetime.now(UTC) - timedelta(days=1))
        check(got == (0, 40.0, 0, True),
              "auto_create_ai_only_paid: an owner whose Plus ended yesterday is Free at once: no AI call", got)
        got = await auto_create("overcap", "plus", cost=5.0)
        check(got == (0, 40.0, 0, True),
              "auto_create_ai_only_paid: a Plus owner over their cost cap gets the adjusted budget, no AI call", got)

        # ---- report_download_locked_free: the PDF needs Reports, which Free does not have
        r = c.post("/api/reports/download", headers=fh, json={"period": "month", "currency": "usd"})
        d = r.json().get("detail") if r.status_code == 403 else {}
        check(plan_error(r, 403, "plan_feature_locked", "reports") and d.get("upgrade_available") is True and not d.get("resets_at"),
              "report_download_locked_free: a Free user's download is 403 plan_feature_locked (feature reports, upgrade available)",
              f"{r.status_code} {r.text[:200]}")
        pid, ph = register("report-plus")
        set_plan(pid, "plus")
        r = c.post("/api/reports/download", headers=ph, json={"period": "month", "currency": "usd"})
        check(r.status_code == 200 and r.content[:4] == b"%PDF", "report_download: a Plus user gets the PDF", f"{r.status_code} {r.text[:120]}")
        set_plan(pid, "pro")
        r = c.post("/api/reports/download", headers=ph, json={"period": "month", "currency": "usd"})
        check(r.status_code == 200 and r.content[:4] == b"%PDF", "report_download: a Pro user gets the PDF", f"{r.status_code} {r.text[:120]}")
        set_plan(pid, "plus", datetime.now(UTC) - timedelta(days=1))
        r = c.post("/api/reports/download", headers=ph, json={"period": "month", "currency": "usd"})
        check(plan_error(r, 403, "plan_feature_locked", "reports"),
              "report_download_locked_free: a Plus plan that ended yesterday is locked at once", f"{r.status_code} {r.text[:120]}")
        r = c.post("/api/reports/generate", headers=fh, json={"period": "month", "currency": "usd"})
        check(r.status_code == 200, "report_download: the report data endpoint stays open to Free (only the PDF is gated)", r.status_code)
    finally:
        try:
            reset_ai()
            c.put("/api/admin/plans", headers=AD, json=t.default_body())
            await store.load()
        finally:
            db.users.delete_many({"email": {"$regex": f"^t6e-.*-{tag}@"}})  # cascades to budgets, transactions, counters, usage
            db.admins.delete_many({"email": {"$in": list(made.values())}})
            c.close()
