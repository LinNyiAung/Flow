"""Task 7 checks for test_plans: the insight routes and the scheduled insight jobs on the plans, and the insight
display language chosen per request.

Run from test_plans (inside its single asyncio.run): `await plans_insight_checks.run(test_plans_module)`.
Everything goes over HTTP to the stubbed server with the fake AI providers; plans change through the admin users API and
limits through the admin Plans API (restored in a finally). The database is used only to preset a counter, a cost row or a
stored insight and to read results. The scheduler checks run the jobs in this process (the fake AI clients are installed
here too). At the end the fakes are cleared, the default plans are put back and every user made is removed.
"""
import re
import uuid
from datetime import datetime, timedelta, UTC

import httpx

BASE = "http://127.0.0.1:8765"
PROVIDERS = ("openai", "gemini", "claude")
RESPONSE_KEYS = {"id", "user_id", "content", "content_mm", "generated_at", "expires_at", "translation_locked"}
MYANMAR = re.compile("[က-႟]")


def outbox_lines():
    import plans_chat_checks
    return plans_chat_checks.outbox_lines()


def ai_calls_since(n):
    return [x for x in outbox_lines()[n:] if x.get("kind") == "ai_call"]


def plan_error(r, status, code, feature):
    """The response is the refusal {"detail": {code, feature, resets_at, upgrade_available, message}}."""
    d = r.json().get("detail") if r.status_code == status else None
    return bool(isinstance(d, dict) and d.get("code") == code and d.get("feature") == feature
                and set(d) == {"code", "feature", "resets_at", "upgrade_available", "message"} and d.get("message"))


async def run(t):
    """t: the test_plans module (check, connect, make_admins, admin_login, default_body)."""
    import stubenv
    from plans import periods, store

    check = t.check
    c = httpx.Client(base_url=BASE, timeout=120)
    db = __import__("pgcompat").get_db()
    made = t.make_admins(db, ("admin",))
    AD = t.admin_login(c, made["admin"])
    tag = uuid.uuid4().hex[:5]
    await store.load()

    def register(name, lang="en", tx=True):
        email = f"t7i-{name}-{tag}@example.com"
        c.post("/api/auth/register", json={"name": name, "email": email, "password": "secret123"})
        db.users.update_one({"email": email}, {"$set": {"is_verified": True, "language": lang}})
        token = c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json()["access_token"]
        h = {"Authorization": f"Bearer {token}"}
        uid = db.users.find_one({"email": email})["_id"]
        if tx:  # a transaction today: an insight has data to cover (month to date / week to date)
            c.post("/api/transactions", headers=h, json={
                "type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries", "amount": 12.5,
                "currency": "usd", "date": datetime.now(UTC).isoformat(), "description": "t7 groceries"})
        return uid, h

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

    def counter_rows(uid, feature):
        with t.connect() as conn:
            return conn.execute("SELECT count(*) FROM usage_counters WHERE user_id = %s AND feature = %s", (uid, feature)).fetchone()[0]

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

    def store_insight(uid, insight_type="monthly", content="## Stored insight\nYou spent money.", mm=None, placeholder=False,
                      age=timedelta(0)):
        iid = f"t7i-{uuid.uuid4().hex[:10]}"
        db.insights.insert_one({"_id": iid, "user_id": uid, "ai_provider": "gemini", "insight_type": insight_type,
                                "content": content, "content_mm": mm, "is_placeholder": placeholder,
                                "generated_at": datetime.now(UTC) - age})
        return iid

    def rows(uid, insight_type="monthly"):
        return db.insights.count_documents({"user_id": uid, "insight_type": insight_type})

    def get(h, insight_type="monthly", **params):
        return c.get("/api/insights", headers=h, params={"insight_type": insight_type, **params})

    def calls_of(do):
        """-> (response, the AI calls it made)."""
        before = len(outbox_lines())
        r = do()
        return r, ai_calls_since(before)

    def reset_ai():
        """Fakes cleared and every provider's cool-off cleared (a failing provider is skipped for a while)."""
        stubenv.clear_fake_ai()
        for p in PROVIDERS:
            c.post(f"/api/admin/ai/test/{p}", headers=AD, json={})

    def fake_all(kind):
        stubenv.set_fake_ai(**{p: kind for p in PROVIDERS})

    def put_plans(mutate):
        body = t.default_body()
        mutate(body)
        return c.put("/api/admin/plans", headers=AD, json=body).status_code == 200

    try:
        reset_ai()

        # ---- free_monthly_on_demand_counts_once
        fid, fh = register("free")
        r, calls = calls_of(lambda: get(fh))
        j = r.json() if r.status_code == 200 else {}
        row = db.insights.find_one({"user_id": fid, "insight_type": "monthly"})
        check(r.status_code == 200 and len(calls) == 1 and row and not row["is_placeholder"] and j.get("id") == row["_id"]
              and used(fid, "insight_monthly") == 1,
              "free_monthly_on_demand_counts_once: the first GET generates the monthly insight (one AI call) and counts 1",
              f"{r.status_code} {r.text[:160]} calls={len(calls)} used={used(fid, 'insight_monthly')}")
        check(set(j) == RESPONSE_KEYS and j.get("translation_locked") is False and j.get("content_mm") is None,
              "insight_response_shape: {id, user_id, content, content_mm, generated_at, expires_at, translation_locked}; "
              "translation_locked is false unless Myanmar was requested", sorted(j))
        first_id = j.get("id")
        r, calls = calls_of(lambda: get(fh))
        check(r.status_code == 200 and r.json().get("id") == first_id and not calls and used(fid, "insight_monthly") == 1
              and rows(fid) == 1,
              "free_monthly_on_demand_counts_once: a second GET returns the same insight, with no AI call and no new count",
              f"{r.status_code} {len(calls)} calls used={used(fid, 'insight_monthly')} rows={rows(fid)}")
        p = c.get("/api/plan", headers=fh).json().get("features", {}).get("insight_monthly", {})
        check(p.get("used") == 1 and p.get("remaining") == 0, "free_monthly_on_demand_counts_once: GET /api/plan shows 1 used, 0 left", p)
        r, calls = calls_of(lambda: get(fh, "monthly", language="en"))
        check(r.status_code == 200 and r.json().get("id") == first_id and not calls and used(fid, "insight_monthly") == 1,
              "free_monthly_on_demand_counts_once: a third request (language=en) is still free", f"{r.status_code} {len(calls)}")

        # ---- free_monthly_placeholder_no_count: nothing to analyse yet
        nid, nh = register("nodata", tx=False)
        r, calls = calls_of(lambda: get(nh))
        row = db.insights.find_one({"user_id": nid, "insight_type": "monthly"})
        check(r.status_code == 200 and row and row["is_placeholder"] and "Welcome" in (r.json().get("content") or "") and not calls
              and used(nid, "insight_monthly") == 0,
              "free_monthly_placeholder_no_count: a user with no data gets the welcome placeholder, no AI call and used 0",
              f"{r.status_code} {r.text[:120]} calls={len(calls)} used={used(nid, 'insight_monthly')}")
        r = get(nh)
        check(r.status_code == 200 and rows(nid) == 1 and used(nid, "insight_monthly") == 0,
              "free_monthly_placeholder_no_count: asking again stores no second placeholder and still counts nothing",
              f"{r.status_code} rows={rows(nid)} used={used(nid, 'insight_monthly')}")
        # the user then adds data: the placeholder is replaced by a real insight, which counts
        c.post("/api/transactions", headers=nh, json={
            "type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries", "amount": 5,
            "currency": "usd", "date": datetime.now(UTC).isoformat(), "description": "t7 first spend"})
        r, calls = calls_of(lambda: get(nh))
        check(r.status_code == 200 and "Welcome" not in (r.json().get("content") or "") and len(calls) == 1
              and used(nid, "insight_monthly") == 1,
              "free_monthly_placeholder_no_count: once data exists the real insight replaces the placeholder and counts 1",
              f"{r.status_code} {r.text[:120]} calls={len(calls)} used={used(nid, 'insight_monthly')}")

        # ---- free_monthly_existing_shown_free: an insight stored this month (e.g. by the scheduler during Plus) is free to see
        pid, ph = register("was-plus")
        set_plan(pid, "plus")
        r, calls = calls_of(lambda: get(ph))
        plus_id = r.json().get("id") if r.status_code == 200 else None
        check(r.status_code == 200 and len(calls) == 1 and counter_rows(pid, "insight_monthly") == 0,
              "plus_insight_included: a Plus user's on-demand monthly insight is generated and counts nothing",
              f"{r.status_code} {len(calls)} calls rows={counter_rows(pid, 'insight_monthly')}")
        set_plan(pid, "free")
        r, calls = calls_of(lambda: get(ph))
        check(r.status_code == 200 and r.json().get("id") == plus_id and not calls and used(pid, "insight_monthly") == 0
              and counter_rows(pid, "insight_monthly") == 0,
              "free_monthly_existing_shown_free: an insight made during Plus is shown to the now-Free user with used 0 and no AI call",
              f"{r.status_code} {len(calls)} calls used={used(pid, 'insight_monthly')}")
        sid, sh = register("stored")
        stored = store_insight(sid)
        r, calls = calls_of(lambda: get(sh))
        check(r.status_code == 200 and r.json().get("id") == stored and not calls and used(sid, "insight_monthly") == 0,
              "free_monthly_existing_shown_free: a stored real insight from this month is returned with used 0",
              f"{r.status_code} {r.text[:120]} {len(calls)} calls")

        # ---- an older insight: a new month's insight is generated (and counted); a failure shows the older one
        oid, oh = register("older")
        older = store_insight(oid, age=timedelta(days=40))
        fake_all("server")
        try:
            r, calls = calls_of(lambda: get(oh))
        finally:
            reset_ai()
        check(r.status_code == 200 and r.json().get("id") == older and calls and used(oid, "insight_monthly") == 0
              and used(oid, "insight_monthly", "week") == 0,
              "free_monthly_failure_releases: when generation fails the latest older insight is shown and nothing is counted",
              f"{r.status_code} {r.text[:120]} {len(calls)} calls used={used(oid, 'insight_monthly')}")
        fake_all("empty")  # an empty answer is unusable: a failure too (every provider is tried)
        try:
            r = get(oh)
        finally:
            reset_ai()
        check(r.status_code == 200 and r.json().get("id") == older and used(oid, "insight_monthly") == 0,
              "free_monthly_failure_releases: an unusable (empty) answer from every provider shows the older insight and counts nothing",
              f"{r.status_code} {r.text[:100]} used={used(oid, 'insight_monthly')}")
        r, calls = calls_of(lambda: get(oh))
        check(r.status_code == 200 and r.json().get("id") != older and len(calls) == 1 and used(oid, "insight_monthly") == 1,
              "free_monthly_on_demand_counts_once: with only an older insight stored, the next GET generates this month's and counts 1",
              f"{r.status_code} {len(calls)} calls used={used(oid, 'insight_monthly')}")
        # nothing stored and every provider fails: the error is surfaced, nothing counted
        zid, zh = register("allfail")
        fake_all("server")
        try:
            r = get(zh)
        finally:
            reset_ai()
        check(r.status_code == 503 and used(zid, "insight_monthly") == 0 and rows(zid) == 0,
              "free_monthly_failure_releases: nothing stored and every provider failing -> 503, nothing counted or stored",
              f"{r.status_code} {r.text[:120]}")

        # ---- free_monthly_refused: used up, at the cost cap
        lid, lh = register("limit")
        set_used(lid, "insight_monthly", 1)  # the month's use is gone and no insight is stored (e.g. deleted)
        r, calls = calls_of(lambda: get(lh))
        d = r.json().get("detail") if r.status_code == 429 else {}
        check(plan_error(r, 429, "plan_limit_reached", "insight_monthly") and d.get("resets_at") and not calls,
              "free_monthly_refused: with the month's use gone and nothing stored, GET is 429 plan_limit_reached, no AI call",
              f"{r.status_code} {r.text[:160]} {len(calls)} calls")
        gid, gh = register("capped")
        add_cost(gid, 0.5)
        r, calls = calls_of(lambda: get(gh))
        check(plan_error(r, 429, "plan_cost_cap", "insight_monthly") and not calls and used(gid, "insight_monthly") == 0,
              "free_monthly_refused: a Free user at the cost cap gets 429 plan_cost_cap and no AI call",
              f"{r.status_code} {r.text[:160]} {len(calls)} calls")
        capped_stored = store_insight(gid)
        r, calls = calls_of(lambda: get(gh))
        check(r.status_code == 200 and r.json().get("id") == capped_stored and not calls,
              "free_monthly_refused: an insight already stored is still shown at the cost cap (no AI is needed)", f"{r.status_code} {len(calls)}")

        # ---- free_weekly_locked, and every other locked insight route
        wid, wh = register("locked")
        r, calls = calls_of(lambda: get(wh, "weekly"))
        check(plan_error(r, 403, "plan_feature_locked", "insight_weekly") and r.json()["detail"]["upgrade_available"] is True
              and not r.json()["detail"]["resets_at"] and not calls and rows(wid, "weekly") == 0,
              "free_weekly_locked: GET weekly is 403 plan_feature_locked (feature insight_weekly), no AI call, nothing stored",
              f"{r.status_code} {r.text[:160]} {len(calls)} calls")
        r = c.get("/api/insights", headers=wh)
        check(plan_error(r, 403, "plan_feature_locked", "insight_weekly"), "free_weekly_locked: weekly is the default type and is locked too",
              f"{r.status_code}")
        for label, do, feature in (
                ("regenerate weekly", lambda: c.post("/api/insights/regenerate", headers=wh, params={"insight_type": "weekly"}), "insight_weekly"),
                ("regenerate monthly", lambda: c.post("/api/insights/regenerate", headers=wh, params={"insight_type": "monthly"}), "insight_monthly"),
                ("generate-weekly", lambda: c.post("/api/insights/generate-weekly", headers=wh), "insight_weekly"),
                ("translate-myanmar", lambda: c.post("/api/insights/translate-myanmar", headers=wh, params={"insight_type": "monthly"}), "insight_translation")):
            r, calls = calls_of(do)
            check(plan_error(r, 403, "plan_feature_locked", feature) and r.json()["detail"]["upgrade_available"] is True and not calls
                  and rows(wid, "monthly") == 0 and counter_rows(wid, "insight_monthly") == 0,
                  f"free_locked_routes: {label} is 403 plan_feature_locked ({feature}) for Free, with no AI call and nothing counted",
                  f"{r.status_code} {r.text[:160]} {len(calls)} calls")
        mid, mh = register("locked-my", "my")
        r = get(mh, "weekly")
        d = r.json().get("detail") if r.status_code == 403 else {}
        check(isinstance(d, dict) and MYANMAR.search(d.get("message", "")),
              "free_weekly_locked: the 403 message is in Myanmar for a Myanmar-profile user", d)

        # ---- free_myanmar_returns_english_locked: never translated, no translation call
        xid, xh = register("mm-free")
        mm_stored = store_insight(xid, mm="## ဘာသာပြန်ပြီးသား\nမြန်မာစာ")  # a translation made while the user was on Plus
        r, calls = calls_of(lambda: get(xh, language="mm"))
        j = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and j.get("id") == mm_stored and j.get("translation_locked") is True and j.get("content_mm") is None
              and "Stored insight" in j.get("content", "") and not calls,
              "free_myanmar_returns_english_locked: ?language=mm returns the English insight, translation_locked true, content_mm null and "
              "no AI call at all (the fake outbox shows no translation call)", f"{r.status_code} {r.text[:200]} {len(calls)} calls")
        r = get(xh, language="en")
        j = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and j.get("translation_locked") is False and j.get("content_mm") is None,
              "free_myanmar_returns_english_locked: ?language=en says translation_locked false and carries no Myanmar text either",
              f"{r.status_code} {r.text[:200]}")
        yid, yh = register("mm-free-fresh")
        r, calls = calls_of(lambda: get(yh, language="mm"))
        j = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and j.get("translation_locked") is True and j.get("content_mm") is None and len(calls) == 1
              and used(yid, "insight_monthly") == 1 and not MYANMAR.search(j.get("content", "")),
              "free_myanmar_returns_english_locked: a Free ?language=mm request that has to generate makes exactly one AI call (the "
              "insight, not a translation) and counts it", f"{r.status_code} {r.text[:200]} {len(calls)} calls")
        myid, myh = register("mm-free-profile", "my")  # a Myanmar profile does not change what Free is shown
        stored_my = store_insight(myid)
        r, calls = calls_of(lambda: get(myh))
        j = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and j.get("id") == stored_my and j.get("translation_locked") is False and not calls,
              "free_myanmar_returns_english_locked: a Free user with a Myanmar profile who asks for English gets English", r.text[:160])

        # ---- plus_myanmar_translated_independent_of_profile
        eid, eh = register("plus-en", "en")
        set_plan(eid, "plus")
        r, calls = calls_of(lambda: get(eh, "weekly"))
        j = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and j.get("content_mm") is None and j.get("translation_locked") is False and len(calls) == 1,
              "plus_insight_included: a Plus weekly insight is generated (one AI call); without ?language=mm it is not translated",
              f"{r.status_code} {r.text[:160]} {len(calls)} calls")
        weekly_id = j.get("id")
        r, calls = calls_of(lambda: get(eh, "weekly", language="mm"))
        j = r.json() if r.status_code == 200 else {}
        row = db.insights.find_one({"_id": weekly_id}) or {}
        check(r.status_code == 200 and j.get("id") == weekly_id and j.get("content_mm") and j.get("translation_locked") is False
              and len(calls) == 1 and row.get("content_mm") == j.get("content_mm") and "Fake answer" in j.get("content_mm", ""),
              "plus_myanmar_translated_independent_of_profile: a profile language of en and ?language=mm still translates the insight "
              "(one translation call, stored)", f"{r.status_code} {r.text[:200]} {len(calls)} calls")
        r, calls = calls_of(lambda: get(eh, "weekly", language="mm"))
        check(r.status_code == 200 and r.json().get("content_mm") == row.get("content_mm") and not calls,
              "plus_myanmar_translated_independent_of_profile: asking for Myanmar again uses the stored translation (no AI call)",
              f"{r.status_code} {len(calls)} calls")
        r, calls = calls_of(lambda: get(eh, "weekly", language="en"))
        check(r.status_code == 200 and not calls and r.json().get("translation_locked") is False,
              "plus_myanmar_translated_independent_of_profile: flipping back to English costs nothing", f"{r.status_code} {len(calls)}")
        check(counter_rows(eid, "insight_translation") == 0 and counter_rows(eid, "insight_weekly") == 0,
              "plus_insight_included: Plus insights and translations count nothing")
        qid, qh = register("plus-my", "my")
        set_plan(qid, "plus")
        r, calls = calls_of(lambda: get(qh, "monthly", language="en"))
        j = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and j.get("content_mm") is None and len(calls) == 1,
              "plus_myanmar_translated_independent_of_profile: a Myanmar profile asking for English is not translated "
              "(the request decides, not the profile)", f"{r.status_code} {r.text[:160]} {len(calls)} calls")
        r = c.post("/api/insights/translate-myanmar", headers=qh, params={"insight_type": "monthly"})
        check(r.status_code == 200 and r.json().get("already_translated") is False and db.insights.find_one({"_id": j.get("id")}).get("content_mm"),
              "translate_myanmar_plus: POST translate-myanmar translates the latest insight for Plus", f"{r.status_code} {r.text[:120]}")
        r, calls = calls_of(lambda: c.post("/api/insights/translate-myanmar", headers=qh, params={"insight_type": "monthly"}))
        check(r.status_code == 200 and r.json().get("already_translated") is True and not calls,
              "translate_myanmar_plus: a second POST says already translated and makes no call", f"{r.status_code} {len(calls)}")
        r, calls = calls_of(lambda: c.post("/api/insights/regenerate", headers=qh, params={"insight_type": "monthly", "language": "mm"}))
        j = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and j.get("content_mm") and len(calls) == 2 and counter_rows(qid, "insight_monthly") == 0
              and set(j) == RESPONSE_KEYS,
              "plus_regenerate: regenerate (language=mm) for Plus makes the insight and its translation (two AI calls) and counts nothing",
              f"{r.status_code} {r.text[:160]} {len(calls)} calls")
        r, calls = calls_of(lambda: c.post("/api/insights/generate-weekly", headers=qh))
        check(r.status_code == 200 and "results" in r.json() and len(calls) == 1 and counter_rows(qid, "insight_weekly") == 0,
              "plus_regenerate: generate-weekly works for Plus (one AI call, nothing counted)", f"{r.status_code} {r.text[:120]} {len(calls)}")

        # ---- plus_cost_cap: user-initiated AI is refused at the cap, reading is not
        cid, ch = register("plus-cap")
        set_plan(cid, "plus")
        stored_cap = store_insight(cid, "weekly")
        add_cost(cid, 5.0)
        r, calls = calls_of(lambda: get(ch, "weekly"))
        check(r.status_code == 200 and r.json().get("id") == stored_cap and not calls,
              "plus_cost_cap: a Plus user over the cap can still read a stored insight", f"{r.status_code} {len(calls)}")
        r, calls = calls_of(lambda: get(ch, "weekly", language="mm"))
        check(plan_error(r, 429, "plan_cost_cap", "insight_translation") and not calls,
              "plus_cost_cap: a translation that needs an AI call is refused (429 plan_cost_cap, insight_translation)",
              f"{r.status_code} {r.text[:160]} {len(calls)} calls")
        for label, do, feature in (
                ("regenerate", lambda: c.post("/api/insights/regenerate", headers=ch, params={"insight_type": "weekly"}), "insight_weekly"),
                ("generate-weekly", lambda: c.post("/api/insights/generate-weekly", headers=ch), "insight_weekly"),
                ("translate-myanmar", lambda: c.post("/api/insights/translate-myanmar", headers=ch, params={"insight_type": "weekly"}), "insight_translation")):
            r, calls = calls_of(do)
            check(plan_error(r, 429, "plan_cost_cap", feature) and not calls,
                  f"plus_cost_cap: {label} is refused at the cost cap (429 plan_cost_cap, {feature}), no AI call", f"{r.status_code} {r.text[:160]} {len(calls)}")
        c2id, c2h = register("plus-cap-empty")
        set_plan(c2id, "plus")
        add_cost(c2id, 5.0)
        r, calls = calls_of(lambda: get(c2h, "monthly"))
        check(plan_error(r, 429, "plan_cost_cap", "insight_monthly") and not calls and rows(c2id) == 0,
              "plus_cost_cap: with nothing stored, a Plus user at the cap is refused (429, no AI call, nothing stored)",
              f"{r.status_code} {r.text[:160]} {len(calls)}")
        set_plan(cid, "pro")
        with t.connect() as conn:
            conn.execute("DELETE FROM ai_usage WHERE user_id = %s", (cid,))
        r, calls = calls_of(lambda: get(ch, "weekly", language="mm"))
        check(r.status_code == 200 and r.json().get("content_mm") and len(calls) == 1,
              "plus_cost_cap: Pro under its cap translates", f"{r.status_code} {r.text[:120]} {len(calls)}")

        # ---- translation counted by the owner: reserved, kept on success, given back on failure
        tid, th = register("plus-counted")
        set_plan(tid, "plus")
        store_insight(tid, "weekly", age=timedelta(days=2))
        try:
            ok = put_plans(lambda body: body["plans"]["plus"]["limits"].update(
                insight_translation={"mode": "counted", "quota": 1, "period": "month"}))
            await store.load()
            check(ok, "translation_counted: the owner makes Plus translation 1 per month (admin API)")
            fake_all("server")
            try:
                r, calls = calls_of(lambda: get(th, "weekly", language="mm"))
            finally:
                reset_ai()
            check(r.status_code == 503 and calls and used(tid, "insight_translation") == 0,
                  "translation_counted: a translation that fails gives its use back", f"{r.status_code} {r.text[:120]} used={used(tid, 'insight_translation')}")
            r, calls = calls_of(lambda: get(th, "weekly", language="mm"))
            check(r.status_code == 200 and r.json().get("content_mm") and len(calls) == 1 and used(tid, "insight_translation") == 1,
                  "translation_counted: a successful translation is counted", f"{r.status_code} {r.text[:120]} used={used(tid, 'insight_translation')}")
            r, calls = calls_of(lambda: get(th, "weekly", language="mm"))
            check(r.status_code == 200 and not calls and used(tid, "insight_translation") == 1,
                  "translation_counted: the stored translation is shown again for free", f"{r.status_code} {len(calls)}")
            store_insight(tid, "monthly")
            r, calls = calls_of(lambda: get(th, "monthly", language="mm"))
            check(plan_error(r, 429, "plan_limit_reached", "insight_translation") and not calls,
                  "translation_counted: the next insight's translation is refused when the allowance is used up",
                  f"{r.status_code} {r.text[:160]} {len(calls)}")
            # a welcome placeholder is translated from the canned text: no AI call, nothing used
            phid, phh = register("plus-placeholder", tx=False)
            set_plan(phid, "plus")
            r, calls = calls_of(lambda: get(phh, "weekly", language="mm"))
            check(r.status_code == 200 and MYANMAR.search(r.json().get("content_mm") or "") and not calls and used(phid, "insight_translation") == 0,
                  "translation_counted: a welcome placeholder is shown in Myanmar from the canned text (no AI call, nothing counted)",
                  f"{r.status_code} {r.text[:120]} {len(calls)}")
            # the owner locks translation for Plus: English with translation_locked, no call
            ok = put_plans(lambda body: body["plans"]["plus"]["limits"].update(insight_translation={"mode": "locked", "quota": None, "period": None}))
            await store.load()
            lid2, lh2 = register("plus-nomm")
            set_plan(lid2, "plus")
            store_insight(lid2, "weekly")
            r, calls = calls_of(lambda: get(lh2, "weekly", language="mm"))
            j = r.json() if r.status_code == 200 else {}
            check(ok and r.status_code == 200 and j.get("translation_locked") is True and j.get("content_mm") is None and not calls,
                  "translation_locked_by_owner: when the owner locks translation for Plus, ?language=mm returns English with translation_locked true",
                  f"{r.status_code} {r.text[:160]} {len(calls)}")
            r = c.post("/api/insights/translate-myanmar", headers=lh2, params={"insight_type": "weekly"})
            check(plan_error(r, 403, "plan_feature_locked", "insight_translation"),
                  "translation_locked_by_owner: translate-myanmar is 403 for Plus when the owner locks it", f"{r.status_code} {r.text[:120]}")
        finally:
            c.put("/api/admin/plans", headers=AD, json=t.default_body())
            await store.load()

        # ---- the owner locks the Free monthly insight: limits are read live
        try:
            ok = put_plans(lambda body: body["plans"]["free"]["limits"].update(insight_monthly={"mode": "locked", "quota": None, "period": None}))
            await store.load()
            kid, kh = register("free-locked-monthly")
            r, calls = calls_of(lambda: get(kh))
            check(ok and plan_error(r, 403, "plan_feature_locked", "insight_monthly") and not calls,
                  "free_monthly_locked_by_owner: when the owner locks the Free monthly insight, GET is 403 (insight_monthly)",
                  f"{r.status_code} {r.text[:120]} {len(calls)}")
        finally:
            c.put("/api/admin/plans", headers=AD, json=t.default_body())
            await store.load()

        # ---- scheduler_skips_free_and_capped: the jobs select Plus and Pro, skip ended plans and users at the cost cap
        import insights_service as ins
        from ai_providers import runner
        stubenv.patch_loaded_modules()
        now = datetime.now(UTC)
        sch = {}
        for name, plan, expires in (("free", "free", None), ("plus", "plus", None), ("pro", "pro", now + timedelta(days=9)),
                                    ("expired", "plus", now - timedelta(days=1)), ("capped", "plus", None),
                                    ("reset", "pro", None), ("procapped", "pro", None), ("freecapped", "free", None)):
            uid, h = register(f"sch-{name}")
            if plan != "free":
                set_plan(uid, plan, expires)
            sch[name] = uid
        add_cost(sch["capped"], 1.5)       # Plus cap is 1.00
        add_cost(sch["procapped"], 3.5)    # Pro cap is 3.00
        add_cost(sch["reset"], 4.0)        # over the Pro cap ...
        r = c.post(f"/api/admin/users/{sch['reset']}/reset-usage", headers=AD)  # ... until the admin resets usage
        check(r.status_code == 200, "scheduler_skips_free_and_capped: the admin reset gives one Pro user a fresh cap", r.status_code)
        ours = set(sch.values())
        orig_run, orig_list = runner.run, ins.users_db.list_fields
        seen, listed = [], []

        async def spy(feature, **kw):
            seen.append((feature, kw.get("user_id"), kw.get("background")))
            return await orig_run(feature, **kw)

        async def only_ours(fields, *where):
            got = [u for u in await orig_list(fields, *where) if u["_id"] in ours]
            listed.append({u["_id"] for u in got})
            return got

        try:
            runner.run, ins.users_db.list_fields = spy, only_ours
            for label, job, feature in (("weekly", ins.generate_weekly_insights_for_all_users, "insight_weekly"),
                                        ("monthly", ins.generate_monthly_insights_for_all_users, "insight_monthly")):
                seen.clear()
                await job()
                ran = {u for f, u, bg in seen if f == feature}
                want = {sch["plus"], sch["pro"], sch["reset"]}
                check(ran == want and all(bg for f, u, bg in seen if f == feature),
                      f"scheduler_skips_free_and_capped: the {label} job generates for Plus, Pro and a reset Pro user only (in the background)",
                      sorted(k for k, v in sch.items() if v in ran))
                names = {k for k, v in sch.items() if v in listed[-1]}
                check(names == {"plus", "pro", "expired", "capped", "reset", "procapped"},
                      f"scheduler_skips_free_and_capped: the {label} job's selection is the Plus and Pro plan rows (free users never listed)",
                      sorted(names))
        finally:
            runner.run, ins.users_db.list_fields = orig_run, orig_list
        check(all(rows(sch[k], "weekly") == 0 and rows(sch[k], "monthly") == 0 for k in ("free", "expired", "capped", "procapped", "freecapped")),
              "scheduler_skips_free_and_capped: no insight was stored for Free, an ended plan or a user at the cap")
        check(all(rows(sch[k], "weekly") == 1 and rows(sch[k], "monthly") == 1 for k in ("plus", "pro", "reset")),
              "scheduler_skips_free_and_capped: one weekly and one monthly insight stored for each Plus, Pro and reset user")
        check(all(counter_rows(sch[k], f) == 0 for k in sch for f in ("insight_weekly", "insight_monthly")),
              "scheduler_skips_free_and_capped: the scheduled jobs count nothing against any allowance")
        with t.connect() as conn:
            spend = {k: conn.execute("SELECT count(*) FROM ai_usage WHERE user_id = %s AND feature_type IN ('weekly_insight', 'monthly_insight')",
                                     (sch[k],)).fetchone()[0] for k in ("plus", "pro", "reset", "capped")}
        check(spend["plus"] == 2 and spend["pro"] == 2 and spend["reset"] == 2 and spend["capped"] == 0,
              "scheduled_spend_recorded: each scheduled insight's cost is recorded in ai_usage against the user (so it counts toward the cap)", spend)
        # the cap counts that spend: a user whose recorded job spend reaches the cap is skipped on the next run
        with t.connect() as conn:
            conn.execute("UPDATE ai_usage SET estimated_cost_usd = 0.6 WHERE user_id = %s", (sch["plus"],))
        seen.clear()
        try:
            runner.run, ins.users_db.list_fields = spy, only_ours
            await ins.generate_weekly_insights_for_all_users()
        finally:
            runner.run, ins.users_db.list_fields = orig_run, orig_list
        ran = {u for f, u, bg in seen if f == "insight_weekly"}
        check(sch["plus"] not in ran and sch["pro"] in ran,
              "scheduled_spend_recorded: once a user's recorded spend reaches the plan's cap the next job run skips them", sorted(ran))
    finally:
        try:
            reset_ai()
            c.put("/api/admin/plans", headers=AD, json=t.default_body())
            await store.load()
        finally:
            db.users.delete_many({"email": {"$regex": f"^t7i-.*-{tag}@"}})  # cascades to insights, counters, usage
            db.admins.delete_many({"email": {"$in": list(made.values())}})
            c.close()
