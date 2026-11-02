"""Task 3 checks for test_plans: the quota engine (reserve / commit / release on usage counters), the hidden cost cap,
the plan error responses and GET /api/plan.

Run from test_plans (inside its single asyncio.run): `await plans_quota_checks.run(test_plans_module)`. The engine
is exercised in-process against the e2e database; /api/plan and plan changes go over HTTP to the stubbed server.
Limits change only through the admin API (the server keeps its own cache) and are put back to the defaults at the end.
"""
import asyncio
import logging
import re
import uuid
from datetime import datetime, timedelta, UTC

import httpx

BASE = "http://127.0.0.1:8765"
MYANMAR = re.compile("[က-႟]")
STATUS_KEYS = {"plan", "expires_at", "is_trial", "trial_ends_at", "features", "catalog", "upgrade_contact"}
FEATURE_KEYS = {"mode", "limit", "period", "used", "remaining", "resets_at"}
DETAIL_KEYS = {"code", "feature", "resets_at", "upgrade_available", "message"}


async def run(t):
    """t: the test_plans module (check, connect, make_admins, admin_login, default_body)."""
    from plans import access, catalog, periods, quota, store
    from sql import users as users_db

    check = t.check
    c = httpx.Client(base_url=BASE, timeout=60)
    db = __import__("pgcompat").get_db()
    made = t.make_admins(db, ("admin",))
    AD = t.admin_login(c, made["admin"])
    tag = uuid.uuid4().hex[:5]
    await store.load()

    def register(name, lang="en"):
        email = f"t3q-{name}-{tag}@example.com"
        c.post("/api/auth/register", json={"name": name, "email": email, "password": "secret123"})
        db.users.update_one({"email": email}, {"$set": {"is_verified": True, "language": lang}})
        token = c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json()["access_token"]
        return db.users.find_one({"email": email})["_id"], {"Authorization": f"Bearer {token}"}

    async def fresh(uid):
        return await users_db.get_user(uid)

    def set_plan(uid, plan, expires=None):
        body = {"subscription_type": plan}
        if expires is not None:
            body["subscription_expires_at"] = expires.isoformat()
        r = c.put(f"/api/admin/users/{uid}/subscription", headers=AD, json=body)
        return r.status_code == 200

    def used(uid, feature, period, start=None):
        start = start or periods.period_start(period, datetime.now(UTC))
        with t.connect() as conn:
            row = conn.execute("SELECT used FROM usage_counters WHERE user_id = %s AND feature = %s AND period = %s "
                               "AND period_start = %s", (uid, feature, period, start)).fetchone()
        return row[0] if row else 0

    def set_used(uid, feature, n):
        """Both this week's and this month's row for the feature hold n."""
        now = datetime.now(UTC)
        with t.connect() as conn:
            for period in ("week", "month"):
                conn.execute("INSERT INTO usage_counters (user_id, feature, period, period_start, used) VALUES (%s, %s, %s, %s, %s) "
                             "ON CONFLICT (user_id, feature, period, period_start) DO UPDATE SET used = EXCLUDED.used",
                             (uid, feature, period, periods.period_start(period, now), n))

    def add_cost(uid, usd, at=None):
        with t.connect() as conn:
            conn.execute("INSERT INTO ai_usage (id, user_id, feature_type, provider, model_name, estimated_cost_usd, created_at) "
                         "VALUES (%s, %s, 'chat', 'openai', 'gpt-test', %s, %s)", (str(uuid.uuid4()), uid, usd, at or datetime.now(UTC)))

    async def attempt(user, feature, **kw):
        """-> the Reservation, or the PlanError raised."""
        try:
            return await quota.reserve(user, feature, **kw)
        except access.PlanError as e:
            return e

    def is_err(x, status, code, feature=None):
        return (isinstance(x, access.PlanError) and x.status == status and x.code == code
                and (feature is None or x.feature == feature))

    def desc(x):
        return x.detail() if isinstance(x, access.PlanError) else repr(x)

    try:
        # ---- effective_plan / is_trial
        now = datetime.now(UTC)
        ep = access.effective_plan
        check(ep({"subscription_type": "plus", "subscription_expires_at": now - timedelta(seconds=1)}) == "free"
              and ep({"subscription_type": "pro", "subscription_expires_at": now - timedelta(days=3)}) == "free"
              and ep({"subscription_type": "plus", "subscription_expires_at": None}) == "plus"
              and ep({"subscription_type": "pro", "subscription_expires_at": now + timedelta(days=3)}) == "pro"
              and ep({"subscription_type": "free"}) == "free" and ep({"subscription_type": "premium"}) == "free"
              and ep({"subscription_type": "plus", "subscription_expires_at": (now - timedelta(days=1)).replace(tzinfo=None)}) == "free",
              "effective_plan: an expired plus / pro is free at once; lifetime and future expiry keep the plan; unknown is free")
        check(access.is_trial({"trial_ends_at": now + timedelta(days=2)}) and not access.is_trial({"trial_ends_at": now - timedelta(days=2)})
              and not access.is_trial({"trial_ends_at": None}) and not access.is_trial({}),
              "is_trial: true only while trial_ends_at is in the future")

        # ---- reserve_counts_until_limit
        uid, _ = register("count")
        user = await fresh(uid)
        ok = 0
        for _ in range(5):
            try:
                async with quota.use(user, "chat"):
                    ok += 1
            except access.PlanError:
                pass
        check(ok == 5 and used(uid, "chat", "week") == 5, "reserve_counts_until_limit: a Free user gets 5 chat uses this week",
              (ok, used(uid, "chat", "week")))
        check(used(uid, "chat", "month") == 5, "reserve_counts_until_limit: the month row is counted too (for a plan change)",
              used(uid, "chat", "month"))
        sixth = await attempt(user, "chat")
        want_reset = periods.resets_at("week", datetime.now(UTC))
        check(is_err(sixth, 429, "plan_limit_reached", "chat") and sixth.resets_at == want_reset,
              "reserve_counts_until_limit: the sixth gives 429 plan_limit_reached, resets next Monday 00:00 app time", desc(sixth))
        d = sixth.detail() if isinstance(sixth, access.PlanError) else {}
        check(set(d) == DETAIL_KEYS and d.get("resets_at") == want_reset.isoformat() and d.get("upgrade_available") is True
              and d.get("feature") == "chat" and isinstance(d.get("message"), str) and d["message"],
              "reserve_counts_until_limit: the body is {code, feature, resets_at (UTC ISO), upgrade_available, message}", d)
        check(used(uid, "chat", "week") == 5 and used(uid, "chat", "month") == 5,
              "reserve_counts_until_limit: a refused reserve changes no counter")

        # ---- release_returns_use
        uid, _ = register("release")
        user = await fresh(uid)
        r = await quota.reserve(user, "chat")
        mid = used(uid, "chat", "week")
        await r.release()
        check(mid == 1 and used(uid, "chat", "week") == 0 and used(uid, "chat", "month") == 0,
              "release_returns_use: reserve then release leaves used at 0 (week and month)", (mid, used(uid, "chat", "week")))
        a = await quota.reserve(user, "chat")
        await quota.reserve(user, "chat")
        await a.release()
        await a.release()
        check(used(uid, "chat", "week") == 1, "release_returns_use: releasing twice gives back only one use (idempotent)",
              used(uid, "chat", "week"))
        try:
            async with quota.use(user, "chat"):
                raise RuntimeError("AI failed")
        except RuntimeError:
            pass
        check(used(uid, "chat", "week") == 1, "release_returns_use: an exception inside quota.use releases the use",
              used(uid, "chat", "week"))
        try:
            async with quota.use(user, "chat") as r:
                r.commit()
                raise RuntimeError("client went away after the first chunk")
        except RuntimeError:
            pass
        check(used(uid, "chat", "week") == 2, "release_returns_use: after an early commit an exception keeps the use",
              used(uid, "chat", "week"))
        r = await quota.reserve(user, "chat")
        r.commit()
        await r.release()
        check(used(uid, "chat", "week") == 3, "release_returns_use: release after commit is a no-op", used(uid, "chat", "week"))
        # a release after the period boundary still decrements the rows the reservation counted
        last_week = datetime.now(UTC) - timedelta(days=7)
        r = await quota.reserve(user, "chat", now=last_week)
        old_start = periods.period_start("week", last_week)
        old_used = used(uid, "chat", "week", old_start)
        await r.release()
        check(old_used == 1 and used(uid, "chat", "week", old_start) == 0 and used(uid, "chat", "week") == 3,
              "release_returns_use: a release after the week rolled over decrements last week's row, not this week's",
              (old_used, used(uid, "chat", "week", old_start), used(uid, "chat", "week")))
        set_used(uid, "chat", 0)
        r = await quota.reserve(user, "chat")
        set_used(uid, "chat", 0)  # e.g. an admin reset between reserve and release
        await r.release()
        check(used(uid, "chat", "week") == 0, "release_returns_use: a release never takes a counter below 0")

        # ---- concurrent_last_use
        uid, _ = register("race")
        user = await fresh(uid)
        set_used(uid, "chat", 4)
        outs = await asyncio.gather(*(attempt(user, "chat") for _ in range(5)))
        wins = [o for o in outs if isinstance(o, quota.Reservation)]
        check(len(wins) == 1 and all(is_err(o, 429, "plan_limit_reached") for o in outs if o not in wins)
              and used(uid, "chat", "week") == 5,
              "concurrent_last_use: with 4 used, 5 concurrent reserves give exactly 1 success", ([desc(o) for o in outs], used(uid, "chat", "week")))
        # a monthly feature too (Free entry 10/month): there the limit-checked row is the first one written
        set_used(uid, "entry", 9)
        outs = await asyncio.gather(*(attempt(user, "entry") for _ in range(5)))
        wins = [o for o in outs if isinstance(o, quota.Reservation)]
        check(len(wins) == 1 and used(uid, "entry", "month") == 10,
              "concurrent_last_use: with 9 of 10 monthly entries used, 5 concurrent reserves give exactly 1 success",
              ([desc(o) for o in outs], used(uid, "entry", "month")))
        uid, _ = register("race0")
        user = await fresh(uid)
        outs = await asyncio.gather(*(attempt(user, "chat") for _ in range(12)))
        wins = [o for o in outs if isinstance(o, quota.Reservation)]
        check(len(wins) == 5 and used(uid, "chat", "week") == 5 and used(uid, "chat", "month") == 5,
              "concurrent_last_use: 12 concurrent first reserves on a new user give exactly 5", (len(wins), used(uid, "chat", "week")))
        await asyncio.gather(*(w.release() for w in wins))
        check(used(uid, "chat", "week") == 0 and used(uid, "chat", "month") == 0,
              "concurrent_last_use: concurrent releases give every use back", used(uid, "chat", "week"))

        # ---- also: chat + chat_advanced reserve together or not at all
        uid, _ = register("adv")
        check(set_plan(uid, "pro"), "also: the user is set to pro through the admin API")
        user = await fresh(uid)
        r = await attempt(user, "chat", also=("chat_advanced",))
        check(isinstance(r, quota.Reservation) and used(uid, "chat", "month") == 1 and used(uid, "chat_advanced", "month") == 1,
              "also: a Pro advanced message counts once on chat and once on chat_advanced", desc(r))
        if isinstance(r, quota.Reservation):
            await r.release()
        check(used(uid, "chat", "month") == 0 and used(uid, "chat_advanced", "month") == 0, "also: release gives both back")
        set_used(uid, "chat_advanced", 100)
        r = await attempt(user, "chat", also=("chat_advanced",))
        check(is_err(r, 429, "plan_limit_reached", "chat_advanced") and used(uid, "chat", "month") == 0,
              "also: Advanced used up -> 429 on chat_advanced and the chat count is rolled back", (desc(r), used(uid, "chat", "month")))
        set_used(uid, "chat", 400)
        r = await attempt(user, "chat")
        check(is_err(r, 429, "plan_limit_reached", "chat") and r.upgrade_available is False,
              "also: Pro at its chat limit -> upgrade_available false (no higher plan)", desc(r))

        # ---- locked_is_403
        uid, _ = register("locked")
        user = await fresh(uid)
        r = await attempt(user, "insight_weekly")
        check(is_err(r, 403, "plan_feature_locked", "insight_weekly") and r.upgrade_available is True and r.resets_at is None,
              "locked_is_403: Free insight_weekly gives 403 plan_feature_locked with upgrade_available true", desc(r))
        r = await attempt(user, "chat", also=("chat_advanced",))
        check(is_err(r, 403, "plan_feature_locked", "chat_advanced") and used(uid, "chat", "week") == 0,
              "locked_is_403: Free chat + chat_advanced is 403 on chat_advanced and counts nothing", desc(r))
        set_plan(uid, "plus")
        r = await attempt(await fresh(uid), "reports")
        check(isinstance(r, quota.Reservation), "locked_is_403: an included feature (Plus reports) passes and reserves nothing", desc(r))
        if isinstance(r, quota.Reservation):
            async with quota.use(await fresh(uid), "reports"):
                pass
        with t.connect() as conn:
            n = conn.execute("SELECT count(*) FROM usage_counters WHERE user_id = %s", (uid,)).fetchone()[0]
        check(n == 0, "locked_is_403: an included feature writes no counter rows", n)
        set_plan(uid, "plus", datetime.now(UTC) - timedelta(hours=1))
        r = await attempt(await fresh(uid), "insight_weekly")
        check(is_err(r, 403, "plan_feature_locked"), "expired_plus_is_free_now: an expired Plus user is treated as Free at once", desc(r))

        # ---- cost_cap_blocks
        uid, _ = register("cap")
        user = await fresh(uid)
        add_cost(uid, 0.11)
        r = await attempt(user, "chat")
        check(is_err(r, 429, "plan_cost_cap", "chat") and r.resets_at == periods.resets_at("month", datetime.now(UTC)),
              "cost_cap_blocks: Free spend 0.11 this month -> 429 plan_cost_cap, resets at the next month start", desc(r))
        check(used(uid, "chat", "week") == 0, "cost_cap_blocks: a refused reserve counts nothing")
        check(await quota.over_cost_cap(user) is True, "cost_cap_blocks: over_cost_cap is true")
        r = await attempt(user, "insight_weekly")
        check(is_err(r, 403, "plan_feature_locked"), "cost_cap_blocks: a locked feature is still 403 (locked is checked first)", desc(r))
        set_used(uid, "chat", 5)
        r = await attempt(user, "chat")
        check(is_err(r, 429, "plan_cost_cap"), "cost_cap_blocks: the cap is checked before the allowance", desc(r))
        d = r.detail() if isinstance(r, access.PlanError) else {}
        check("0.1" not in d.get("message", "") and "$" not in d.get("message", ""), "cost_cap_blocks: the message shows no cost or cap", d)
        uid2, _ = register("cap-old")
        add_cost(uid2, 5.0, periods.month_start_utc(datetime.now(UTC)) - timedelta(minutes=1))
        add_cost(uid2, 0.09)
        user2 = await fresh(uid2)
        r = await attempt(user2, "chat")
        check(isinstance(r, quota.Reservation) and await quota.over_cost_cap(user2) is False,
              "cost_cap_blocks: spend before this month's start does not count", desc(r))
        set_plan(uid2, "plus")
        add_cost(uid2, 1.0)
        r = await attempt(await fresh(uid2), "insight_weekly")
        check(is_err(r, 429, "plan_cost_cap", "insight_weekly"), "cost_cap_blocks: an included feature is refused over the cap too", desc(r))

        # ---- reset_restores_cap
        await quota.reset_usage(uid, "t3-admin")
        user = await fresh(uid)
        r = await attempt(user, "chat")
        with t.connect() as conn:
            rows = conn.execute("SELECT count(*) FROM ai_usage WHERE user_id = %s", (uid,)).fetchone()[0]
        check(isinstance(r, quota.Reservation) and rows == 1 and user.get("usage_reset_at") is not None,
              "reset_restores_cap: after reset_usage the reserve succeeds and the ai_usage rows are kept", (desc(r), rows))
        check(used(uid, "chat", "week") == 1 and used(uid, "chat", "month") == 1,
              "reset_restores_cap: reset_usage cleared this period's counters (5 -> 0, then 1 new use)", used(uid, "chat", "week"))
        check(await quota.over_cost_cap(user) is False, "reset_restores_cap: over_cost_cap is false after the reset")

        # ---- plan_change_mid_period
        uid, h = register("change")
        user = await fresh(uid)
        for _ in range(5):
            async with quota.use(user, "chat"):
                pass
        set_plan(uid, "plus")
        j = c.get("/api/plan", headers=h).json()
        chat = j.get("features", {}).get("chat", {})
        check(j.get("plan") == "plus" and chat.get("limit") == 100 and chat.get("period") == "month" and chat.get("used") == 5
              and chat.get("remaining") == 95, "plan_change_mid_period: 5 Free chats this week, now Plus -> 95 of 100 left", chat)
        r = await attempt(await fresh(uid), "chat")
        if isinstance(r, quota.Reservation):
            r.commit()
        set_plan(uid, "free")
        j = c.get("/api/plan", headers=h).json()
        chat = j.get("features", {}).get("chat", {})
        check(j.get("plan") == "free" and chat.get("limit") == 5 and chat.get("used") == 6 and chat.get("remaining") == 0,
              "plan_change_mid_period: back to Free in the same week -> measured on this week's 6 uses, 0 left", chat)
        r = await attempt(await fresh(uid), "chat")
        check(is_err(r, 429, "plan_limit_reached"), "plan_change_mid_period: and a reserve is refused", desc(r))

        # ---- limit_lowered_below_used
        uid, h = register("lowered")
        user = await fresh(uid)
        for _ in range(4):
            async with quota.use(user, "chat"):
                pass
        try:
            body = t.default_body()
            body["plans"]["free"]["limits"]["chat"]["quota"] = 3
            r = c.put("/api/admin/plans", headers=AD, json=body)
            await store.load()
            chat = c.get("/api/plan", headers=h).json().get("features", {}).get("chat", {})
            check(r.status_code == 200 and chat.get("limit") == 3 and chat.get("used") == 4 and chat.get("remaining") == 0,
                  "limit_lowered_below_used: quota 5 -> 3 after 4 uses -> remaining 0, never negative", chat)
            r = await attempt(user, "chat")
            check(is_err(r, 429, "plan_limit_reached"), "limit_lowered_below_used: reserve gives 429", desc(r))
            body["plans"]["free"]["limits"]["chat"]["quota"] = 0
            c.put("/api/admin/plans", headers=AD, json=body)
            await store.load()
            uid0, _ = register("zero")
            r = await attempt(await fresh(uid0), "chat")
            check(is_err(r, 429, "plan_limit_reached") and used(uid0, "chat", "week") == 0,
                  "limit_lowered_below_used: a quota of 0 refuses the first use and writes nothing", desc(r))
        finally:
            r = c.put("/api/admin/plans", headers=AD, json=t.default_body())
            await store.load()
            check(r.status_code == 200 and store.limits("free") == catalog.DEFAULT_LIMITS["free"],
                  "limit_lowered_below_used: the default limits are restored")

        # ---- plan_status_shape
        uid, h = register("shape")
        r = c.get("/api/plan", headers=h)
        j = r.json() if r.status_code == 200 else {}
        feats = j.get("features", {})
        check(r.status_code == 200 and set(j) == STATUS_KEYS and set(feats) == set(catalog.FEATURES)
              and all(set(v) == FEATURE_KEYS for v in feats.values()),
              "plan_status_shape: /api/plan has plan, dates, trial, all 8 features, catalog and contact", f"{r.status_code} {r.text[:300]}")
        check(j.get("plan") == "free" and j.get("is_trial") is False and j.get("expires_at") is None and j.get("trial_ends_at") is None,
              "plan_status_shape: a new user is on free, not on a trial", j)
        chat = feats.get("chat", {})
        check(chat == {"mode": "counted", "limit": 5, "period": "week", "used": 0, "remaining": 5,
                       "resets_at": periods.resets_at("week", datetime.now(UTC)).isoformat()},
              "plan_status_shape: Free chat is counted 5/week, 0 used, 5 left, resets next Monday", chat)
        check(all(v == {"mode": "locked", "limit": None, "period": None, "used": None, "remaining": None, "resets_at": None}
                  for f, v in feats.items() if f in ("chat_advanced", "insight_weekly", "insight_translation", "reports")),
              "plan_status_shape: locked features have null counts", {f: feats.get(f) for f in ("reports", "insight_weekly")})
        cat = j.get("catalog", {})
        check(set(cat) == set(catalog.PLANS) and all(set(v) == set(catalog.FEATURES) for v in cat.values())
              and cat.get("pro", {}).get("chat_advanced") == {"mode": "counted", "quota": 100, "period": "month"}
              and cat.get("plus", {}).get("reports") == {"mode": "included", "quota": None, "period": None},
              "plan_status_shape: the catalog has the 3 plans' limits", cat.get("pro"))
        check(set(j.get("upgrade_contact", {})) == {"en", "my"}, "plan_status_shape: the upgrade contact has en and my",
              j.get("upgrade_contact"))
        check("cost" not in r.text.lower(), "plan_status_shape: no cost or cap amount is shown to the user")
        expires = (datetime.now(UTC) + timedelta(days=20)).replace(microsecond=0)
        set_plan(uid, "pro", expires)
        db.users.update_one({"_id": uid}, {"$set": {"trial_ends_at": expires}})
        j = c.get("/api/plan", headers=h).json()
        check(j.get("plan") == "pro" and j.get("is_trial") is True and j.get("expires_at") == expires.isoformat()
              and j.get("trial_ends_at") == expires.isoformat()
              and j.get("features", {}).get("reports") == {"mode": "included", "limit": None, "period": None, "used": None,
                                                           "remaining": None, "resets_at": None},
              "plan_status_shape: a Pro trial shows its end dates, is_trial and included features with null counts", j)
        set_plan(uid, "plus", datetime.now(UTC) - timedelta(minutes=5))
        j = c.get("/api/plan", headers=h).json()
        check(j.get("plan") == "free" and j.get("features", {}).get("chat", {}).get("limit") == 5,
              "plan_status_shape: an expired Plus user is shown as free with Free limits", j.get("plan"))
        r = c.get("/api/plan")
        check(r.status_code in (401, 403), "plan_status_shape: /api/plan needs a signed-in user", r.status_code)

        # ---- limit_message_language
        uid_my, _ = register("lang-my", "my")
        uid_en, _ = register("lang-en", "en")
        msgs = {}
        for lang, u in (("my", uid_my), ("en", uid_en)):
            set_used(u, "chat", 5)
            e = await attempt(await fresh(u), "chat")
            msgs[lang] = e.detail()["message"] if isinstance(e, access.PlanError) else ""
        check(MYANMAR.search(msgs["my"]) and not MYANMAR.search(msgs["en"]) and msgs["en"],
              "limit_message_language: the message is Myanmar for a my user and English for an en user", msgs)
        e = await attempt(await fresh(uid_my), "insight_translation")
        add_cost(uid_my, 0.5)
        e2 = await attempt(await fresh(uid_my), "chat")
        check(all(isinstance(x, access.PlanError) and MYANMAR.search(x.detail()["message"]) for x in (e, e2)),
              "limit_message_language: the locked and cost-cap messages are Myanmar too", (desc(e), desc(e2)))

        # ---- the app-level handler renders PlanError as {"detail": {...}} with the PlanError's status
        import main as backend_main
        import plans_routes
        logging.getLogger("httpx").setLevel(logging.WARNING)  # importing main turns on INFO request logging
        check(backend_main.app.exception_handlers.get(access.PlanError) is plans_routes.plan_error_handler,
              "plan_error_handler: main registers the PlanError handler")
        raised = {"e": None}

        async def boom():
            raise raised["e"]

        backend_main.app.add_api_route("/__t3_plan_error", boom, methods=["GET"])
        try:
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=backend_main.app), base_url="http://t3") as ac:
                for e in (await attempt(await fresh(uid_my), "insight_weekly"), await attempt(await fresh(uid_en), "chat")):
                    raised["e"] = e
                    resp = await ac.get("/__t3_plan_error")
                    body = resp.json()
                    check(isinstance(e, access.PlanError) and resp.status_code == e.status and set(body) == {"detail"}
                          and body["detail"] == e.detail() and set(body["detail"]) == DETAIL_KEYS,
                          f"plan_error_handler: {getattr(e, 'code', e)} -> HTTP {getattr(e, 'status', '?')} with the detail body",
                          f"{resp.status_code} {resp.text[:300]}")
        finally:
            backend_main.app.router.routes[:] = [rt for rt in backend_main.app.router.routes
                                                  if getattr(rt, "path", None) != "/__t3_plan_error"]
    finally:
        try:
            c.put("/api/admin/plans", headers=AD, json=t.default_body())
            await store.load()
        finally:
            db.users.delete_many({"email": {"$regex": "^t3q-"}})
            db.admins.delete_many({"email": {"$in": list(made.values())}})
            c.close()
