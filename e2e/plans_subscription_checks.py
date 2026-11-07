"""Task 4 checks for test_plans: plan expiry for Plus and Pro, the Plus trial and its reminders, the subscription-status
shape, and the admin controls (set plan, dashboard counts, broadcast targets, per-user usage view and reset).

Run from test_plans (inside its single asyncio.run): `await plans_subscription_checks.run(test_plans_module)`.
Plans change only through the admin API. The Plus trial is claimed through the app API; the DB is used only to move a
trial's dates (the claim always gives 30 days) and to read results. Everything the checks create is removed at the end.
"""
import asyncio
import re
import uuid
from datetime import datetime, timedelta, UTC

import httpx

BASE = "http://127.0.0.1:8765"
MYANMAR = re.compile("[က-႟]")
STATUS_KEYS = {"subscription_type", "plan", "is_paid", "is_trial", "expires_at", "is_expired"}
USAGE_KEYS = {"plan", "features", "month_spend_usd", "cost_cap_usd", "cost_cap_reached"}
USAGE_FEATURE_KEYS = {"mode", "used", "limit", "period"}
DETAIL_KEYS = {"code", "feature", "resets_at", "upgrade_available", "message"}
BEFORE_PLAN_REMINDERS = "d6b2e8f4a1c7"  # the revision the plan renewal reminders migration (a9c4f1e7b352) revises


def parse(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00")) if isinstance(value, str) else value


def aware(value):
    return value if value is None or value.tzinfo else value.replace(tzinfo=UTC)


async def run(t):
    """t: the test_plans module (check, connect, make_admins, admin_login)."""
    import stubenv
    import subscription_service as ss
    from plans import catalog, periods, quota
    from sql import users as users_db
    stubenv.patch_loaded_modules()  # no real push; notifications are still stored

    check = t.check
    c = httpx.Client(base_url=BASE, timeout=60)
    db = __import__("pgcompat").get_db()
    made = t.make_admins(db, ("admin", "moderator", "super_admin"))
    AD = t.admin_login(c, made["admin"])
    MOD = t.admin_login(c, made["moderator"])
    SUP = t.admin_login(c, made["super_admin"])  # only super admins read the action logs
    tag = uuid.uuid4().hex[:5]
    broadcast_title = f"t4s-broadcast-{tag}"

    def register(name, lang="en"):
        email = f"t4s-{name}-{tag}@example.com"
        c.post("/api/auth/register", json={"name": name, "email": email, "password": "secret123"})
        db.users.update_one({"email": email}, {"$set": {"is_verified": True, "language": lang}})
        token = c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json()["access_token"]
        return db.users.find_one({"email": email})["_id"], {"Authorization": f"Bearer {token}"}

    def set_plan(uid, plan, expires=None):
        body = {"subscription_type": plan}
        if expires is not None:
            body["subscription_expires_at"] = expires.isoformat()
        return c.put(f"/api/admin/users/{uid}/subscription", headers=AD, json=body).status_code == 200

    def row(uid, *columns):
        with t.connect() as conn:
            return conn.execute(f"SELECT {', '.join(columns)} FROM users WHERE id = %s", (uid,)).fetchone()

    def trial_user(name, ends_in, lang="en"):
        """A user on the Plus trial (claimed through the API) whose trial is moved to end `ends_in` from now."""
        uid, h = register(name, lang)
        r = c.post("/api/auth/claim-free-trial", headers=h)
        ends = datetime.now(UTC) + ends_in
        db.users.update_one({"_id": uid}, {"$set": {"trial_ends_at": ends, "subscription_expires_at": ends}})
        return uid, h, r.status_code

    def notes(uid, *types):
        return list(db.notifications.find({"user_id": uid, "type": {"$in": list(types)}}))

    def add_cost(uid, usd, at=None):
        with t.connect() as conn:
            conn.execute("INSERT INTO ai_usage (id, user_id, feature_type, provider, model_name, estimated_cost_usd, created_at) "
                         "VALUES (%s, %s, 'chat', 'openai', 'gpt-test', %s, %s)", (str(uuid.uuid4()), uid, usd, at or datetime.now(UTC)))

    def counter_rows(uid):
        with t.connect() as conn:
            return conn.execute("SELECT count(*) FROM usage_counters WHERE user_id = %s", (uid,)).fetchone()[0]

    def logs(email):
        r = c.get("/api/admin/logs", headers=SUP, params={"limit": 100})
        return [x for x in (r.json() if r.status_code == 200 else []) if x["admin_email"] == email]

    try:
        with t.connect() as conn:
            cols = t.column_names(conn, "users")
        check({"trial_reminder_3d_at", "trial_reminder_last_at"} <= cols,
              "trial_reminder_columns: users has trial_reminder_3d_at and trial_reminder_last_at", sorted(cols))

        # ---- plan_reminder_migration (leaves the database at head)
        plan_cols = {"plan_reminder_3d_for", "plan_reminder_last_for"}
        with t.connect() as conn:
            types = {r[0]: (r[1], r[2]) for r in conn.execute(
                "SELECT column_name, data_type, is_nullable FROM information_schema.columns "
                "WHERE table_name = 'users' AND column_name = ANY(%s)", (sorted(plan_cols),))}
            check(types == {c_: ("timestamp with time zone", "YES") for c_ in plan_cols},
                  "plan_reminder_migration: head has the nullable timestamptz columns plan_reminder_3d_for and "
                  "plan_reminder_last_for", types)
            ok, out = t.alembic("downgrade", BEFORE_PLAN_REMINDERS)  # -1 while this migration is head
            check(ok and t.current_revision(conn) == BEFORE_PLAN_REMINDERS and not (plan_cols & t.column_names(conn, "users"))
                  and {"trial_reminder_3d_at", "trial_reminder_last_at"} <= t.column_names(conn, "users"),
                  "plan_reminder_migration: downgrade -1 drops only the two columns", out)
            ok, out = t.alembic("upgrade", "head")
            check(ok and plan_cols <= t.column_names(conn, "users") and t.current_revision(conn) != BEFORE_PLAN_REMINDERS,
                  "plan_reminder_migration: upgrade head adds them again", out)

        # ---- trial_sets_plus_and_marker
        uid, h = register("trial")
        before = datetime.now(UTC)
        r = c.post("/api/auth/claim-free-trial", headers=h)
        sub, trial_end, plan_end = row(uid, "subscription_type", "trial_ends_at", "subscription_expires_at")
        check(r.status_code == 200 and r.json().get("subscription_type") == "plus" and sub == "plus",
              "trial_sets_plus_and_marker: claim-free-trial gives the Plus plan", f"{r.status_code} {r.text[:200]}")
        check(trial_end is not None and trial_end == plan_end
              and timedelta(days=29, hours=23) < aware(trial_end) - before < timedelta(days=30, minutes=5),
              "trial_sets_plus_and_marker: trial_ends_at equals the plan end, 30 days from now", (trial_end, plan_end))
        s = c.get("/api/auth/subscription-status", headers=h).json()
        check(set(s) == STATUS_KEYS and s["subscription_type"] == "plus" and s["plan"] == "plus" and s["is_paid"] is True
              and s["is_trial"] is True and s["is_expired"] is False and parse(s["expires_at"]) == aware(plan_end),
              "trial_sets_plus_and_marker: subscription-status is {subscription_type, plan, is_paid, is_trial, expires_at, is_expired}", s)
        p = c.get("/api/plan", headers=h).json()
        check(p.get("plan") == "plus" and p.get("is_trial") is True and parse(p.get("trial_ends_at")) == aware(trial_end),
              "trial_sets_plus_and_marker: GET /api/plan shows the Plus trial", p.get("plan"))
        check(c.post("/api/auth/claim-free-trial", headers=h).status_code == 400,
              "trial_sets_plus_and_marker: a second claim is refused")

        # ---- subscription-status for the other states
        fid, fh = register("free-status")
        s = c.get("/api/auth/subscription-status", headers=fh).json()
        check(set(s) == STATUS_KEYS and s["subscription_type"] == "free" and s["plan"] == "free" and s["is_paid"] is False
              and s["is_trial"] is False and s["expires_at"] is None and s["is_expired"] is False,
              "subscription_status_shape: a free user is plan free, not paid, not a trial, not expired", s)
        pid, ph = register("pro-status")
        set_plan(pid, "pro", datetime.now(UTC) + timedelta(days=9))
        s = c.get("/api/auth/subscription-status", headers=ph).json()
        check(s.get("plan") == "pro" and s.get("subscription_type") == "pro" and s.get("is_paid") is True
              and s.get("is_trial") is False and s.get("is_expired") is False and s.get("expires_at"),
              "subscription_status_shape: an admin-granted Pro is paid and not a trial", s)
        set_plan(pid, "plus", datetime.now(UTC) - timedelta(minutes=1))
        s = c.get("/api/auth/subscription-status", headers=ph).json()
        check(s.get("subscription_type") == "plus" and s.get("plan") == "free" and s.get("is_paid") is False
              and s.get("is_expired") is True and s.get("is_trial") is False,
              "subscription_status_shape: an expired Plus (job not run) is plan free, is_expired true", s)
        db.users.update_one({"_id": pid}, {"$set": {"trial_ends_at": datetime.now(UTC) + timedelta(days=3)}})
        s = c.get("/api/auth/subscription-status", headers=ph).json()
        check(s.get("is_trial") is False, "subscription_status_shape: a trial marker never makes an expired plan a trial", s)

        # ---- admin_set_plan_clears_trial
        for plan, expires in (("plus", datetime.now(UTC) + timedelta(days=40)), ("pro", None), ("free", None)):
            uid2, h2, code = trial_user(f"clear-{plan}", timedelta(days=10))
            marked = row(uid2, "trial_ends_at")[0] is not None
            ok = set_plan(uid2, plan, expires)
            after = row(uid2, "subscription_type", "trial_ends_at")
            s = c.get("/api/auth/subscription-status", headers=h2).json()
            check(code == 200 and marked and ok and after == (plan, None) and s.get("is_trial") is False,
                  f"admin_set_plan_clears_trial: the admin setting {plan} clears the trial marker", (code, marked, ok, after, s))
        uid2, h2, _ = trial_user("clear-fcm", timedelta(days=10))
        db.users.update_one({"_id": uid2}, {"$set": {"fcm_token": f"t4s-token-{tag}"}})
        r = c.put(f"/api/admin/users/{uid2}/subscription", headers=AD, json={"subscription_type": "pro"})
        check(r.status_code == 200 and "fcm_refresh_sent" in r.json(),
              "admin_set_plan_clears_trial: the subscription update still reports the push refresh", r.text[:200])
        r = c.put(f"/api/admin/users/{uid2}/subscription", headers=AD, json={"subscription_type": "premium"})
        check(r.status_code == 422, "admin_set_plan_clears_trial: premium is not an accepted plan any more", r.status_code)

        # ---- expired_plus_is_free_now (before any expiry job)
        uid, h = register("expired-now")
        check(set_plan(uid, "plus", datetime.now(UTC) - timedelta(minutes=1)), "expired_plus_is_free_now: Plus that ended a minute ago is set")
        r = c.get("/api/insights", headers=h)
        d = r.json().get("detail") if r.status_code == 403 else None
        check(r.status_code == 403 and isinstance(d, dict) and d.get("code") == "plan_feature_locked",
              "expired_plus_is_free_now: weekly insights give 403 plan_feature_locked", f"{r.status_code} {r.text[:200]}")
        check(isinstance(d, dict) and set(d) == DETAIL_KEYS and d["feature"] == "insight_weekly" and d["resets_at"] is None
              and d["upgrade_available"] is True and d["message"] and not MYANMAR.search(d["message"]),
              "expired_plus_is_free_now: the body has the plan-error shape (feature insight_weekly, upgrade available, English message)", d)
        check(row(uid, "subscription_type")[0] == "plus", "expired_plus_is_free_now: the stored plan is still plus (no job has run)")
        uid_ok, h_ok = register("live-plus")
        set_plan(uid_ok, "plus", datetime.now(UTC) + timedelta(days=2))
        check(c.get("/api/insights", headers=h_ok).status_code != 403, "expired_plus_is_free_now: a live Plus user still has access")
        uid_pro, h_pro = register("lifetime-pro")
        set_plan(uid_pro, "pro")
        check(c.get("/api/insights", headers=h_pro).status_code != 403, "expired_plus_is_free_now: a lifetime Pro user has access")
        uid_my, h_my = register("free-my", "my")
        r = c.get("/api/insights", headers=h_my)
        d = r.json().get("detail") if r.status_code == 403 else {}
        check(isinstance(d, dict) and MYANMAR.search(d.get("message", "")),
              "expired_plus_is_free_now: the 403 message is Myanmar for a Myanmar-language user", d)
        r = c.get("/api/insights", headers=fh)
        check(r.status_code == 403 and r.json().get("detail", {}).get("code") == "plan_feature_locked",
              "expired_plus_is_free_now: a Free user gets the same 403", r.status_code)

        # ---- expiry_job_downgrades_plus_and_pro
        now = datetime.now(UTC)
        e_plus, _ = register("exp-plus")
        e_pro, _ = register("exp-pro", "my")
        e_live, _ = register("exp-live")
        e_old, _ = register("exp-old")
        set_plan(e_plus, "plus", now - timedelta(hours=2))
        set_plan(e_pro, "pro", now - timedelta(hours=3))
        set_plan(e_live, "pro", now + timedelta(days=5))
        set_plan(e_old, "plus", now - timedelta(days=60))
        n = await ss.expire_paid_plans(now)
        got = {u: row(u, "subscription_type", "premium_ended_at")[0] for u in (e_plus, e_pro, e_live, e_old)}
        check(n >= 3 and got == {e_plus: "free", e_pro: "free", e_live: "pro", e_old: "free"},
              "expiry_job_downgrades_plus_and_pro: expired Plus and Pro go to free, a live Pro stays", (n, got))
        en = notes(e_plus, "subscription_expired")
        my = notes(e_pro, "subscription_expired")
        check(len(en) == 1 and en[0]["title"] == "Your Plus Plan Has Ended" and "Plus plan ended on" in en[0]["message"]
              and "Premium" not in en[0]["message"] + en[0]["title"],
              "expiry_job_downgrades_plus_and_pro: the Plus user is told their Plus plan has ended", en)
        check(len(my) == 1 and "Pro" in my[0]["title"] and MYANMAR.search(my[0]["message"]),
              "expiry_job_downgrades_plus_and_pro: the Pro user gets a Myanmar notice naming Pro", my)
        check(not notes(e_old, "subscription_expired") and not notes(e_live, "subscription_expired"),
              "expiry_job_downgrades_plus_and_pro: no notice for a long-lapsed or a live plan")
        n2 = await ss.expire_paid_plans(now)
        check(n2 == 0 and len(notes(e_plus, "subscription_expired")) == 1 and len(notes(e_pro, "subscription_expired")) == 1,
              "expiry_job_downgrades_plus_and_pro: a second run downgrades nobody and sends no second notice", n2)

        # ---- trial_reminder_3_days
        uid, _, code = trial_user("rem3", timedelta(days=2, hours=12))
        sent = await ss.send_trial_reminders()
        soon = notes(uid, "trial_ending_soon")
        check(code == 200 and sent >= 1 and len(soon) == 1 and not notes(uid, "trial_ends_today"),
              "trial_reminder_3_days: a trial ending in 2.5 days gets one 'ends soon' reminder", (code, sent, soon))
        check(soon and soon[0]["title"] == "Your Plus Trial Ends Soon" and "Plus trial ends on" in soon[0]["message"],
              "trial_reminder_3_days: the reminder is in English and names Plus and the end date", soon)
        await ss.send_trial_reminders()
        await ss.send_trial_reminders(datetime.now(UTC) + timedelta(hours=2))
        check(len(notes(uid, "trial_ending_soon")) == 1 and not notes(uid, "trial_ends_today"),
              "trial_reminder_3_days: a second run (and a later one the same day) sends no second reminder")
        none_5d, _, _ = trial_user("rem5", timedelta(days=5))
        ended, _, _ = trial_user("remend", timedelta(hours=-1))
        await ss.send_trial_reminders()
        check(not notes(none_5d, "trial_ending_soon", "trial_ends_today") and not notes(ended, "trial_ending_soon", "trial_ends_today"),
              "trial_reminder_3_days: no reminder for a trial with more than 3 days left, or one that has already ended")

        # ---- trial_reminder_last_day
        uid, _, _ = trial_user("remlast", timedelta(hours=20))
        await ss.send_trial_reminders()
        last = notes(uid, "trial_ends_today")
        check(len(last) == 1 and not notes(uid, "trial_ending_soon"),
              "trial_reminder_last_day: a trial first seen in its last 24 hours gets only the last-day reminder", last)
        check(last and last[0]["title"] == "Last Day of Your Plus Trial", "trial_reminder_last_day: the last-day reminder text", last)
        await ss.send_trial_reminders()
        check(len(notes(uid, "trial_ends_today")) == 1, "trial_reminder_last_day: a second run sends no second last-day reminder")
        # a trial that already got the 3-day reminder gets the last-day one when the day comes, once
        uid, _, _ = trial_user("rem3then1", timedelta(days=2, hours=12), "my")
        await ss.send_trial_reminders()
        later = datetime.now(UTC) + timedelta(days=2)
        await ss.send_trial_reminders(later)
        await ss.send_trial_reminders(later + timedelta(hours=1))
        soon, last = notes(uid, "trial_ending_soon"), notes(uid, "trial_ends_today")
        check(len(soon) == 1 and len(last) == 1 and all(MYANMAR.search(x["message"]) and MYANMAR.search(x["title"]) for x in soon + last),
              "trial_reminder_last_day: a Myanmar user gets one 'ends soon' then one 'last day', both in Myanmar", (len(soon), len(last)))

        # ---- no_reminder_for_admin_granted
        a_plus, _ = register("grant-plus")
        a_pro, _ = register("grant-pro")
        a_cleared, _, _ = trial_user("grant-cleared", timedelta(days=2))
        set_plan(a_plus, "plus", datetime.now(UTC) + timedelta(days=2))
        set_plan(a_pro, "pro", datetime.now(UTC) + timedelta(hours=10))
        set_plan(a_cleared, "plus", datetime.now(UTC) + timedelta(days=2))
        await ss.send_trial_reminders()
        check(all(not notes(u, "trial_ending_soon", "trial_ends_today") for u in (a_plus, a_pro, a_cleared)),
              "no_reminder_for_admin_granted: admin-granted plans, even a changed trial, get no trial reminder")
        t_changed, _, _ = trial_user("grant-after", timedelta(days=2))
        set_plan(t_changed, "free")
        await ss.send_trial_reminders()
        check(not notes(t_changed, "trial_ending_soon", "trial_ends_today"),
              "no_reminder_for_admin_granted: a trial the admin moved to free gets no reminder")
        # a concurrent pair of runs still sends one reminder
        uid, _, _ = trial_user("remrace", timedelta(days=2))
        await asyncio.gather(*(ss.send_trial_reminders() for _ in range(4)))
        check(len(notes(uid, "trial_ending_soon")) == 1, "trial_reminder_3_days: four overlapping runs send exactly one reminder",
              len(notes(uid, "trial_ending_soon")))

        # ---- plan renewal reminders (paying Plus / Pro users whose plan has an end date)
        from plans.access import format_date
        PLAN_TYPES = ("plan_ending_soon", "plan_ends_today")

        def paid_user(name, plan, ends_in, lang="en"):
            """A user the admin put on `plan` ending `ends_in` from now (None: lifetime) -> (id, headers, stored end)."""
            uid_, h_ = register(name, lang)
            set_plan(uid_, plan, None if ends_in is None else datetime.now(UTC) + ends_in)
            return uid_, h_, row(uid_, "subscription_expires_at")[0]

        # ---- plan_reminder_3_days
        uid, _, ends = paid_user("pr3", "plus", timedelta(days=2, hours=12))
        sent = await ss.send_plan_renewal_reminders()
        soon = notes(uid, "plan_ending_soon")
        # (`sent` is not asserted: the server's own hourly job may have sent this one first, which is just as good.)
        check(len(soon) == 1 and not notes(uid, "plan_ends_today"),
              "plan_reminder_3_days: a Plus plan ending in 2.5 days gets one 'plan ends soon' reminder", (sent, soon))
        check(soon and soon[0]["title"] == "Your Plus Plan Ends Soon"
              and soon[0]["message"] == f"Your Toe Pwar Plus plan ends on {format_date(aware(ends), 'en')}. Renew before "
                                        "then to keep your AI allowances and Plus features.",
              "plan_reminder_3_days: the reminder is in English and names Plus and the end date", soon)
        check(row(uid, "plan_reminder_3d_for", "plan_reminder_last_for") == (ends, None),
              "plan_reminder_3_days: plan_reminder_3d_for holds the end date it was sent for",
              row(uid, "plan_reminder_3d_for", "plan_reminder_last_for"))
        await ss.send_plan_renewal_reminders()
        await ss.send_plan_renewal_reminders(datetime.now(UTC) + timedelta(hours=2))
        check(len(notes(uid, "plan_ending_soon")) == 1 and not notes(uid, "plan_ends_today"),
              "plan_reminder_3_days: a second run (and a later one the same day) sends nothing more")

        # ---- plan_reminder_last_day
        uid, _, ends = paid_user("prlast", "pro", timedelta(hours=20))
        await ss.send_plan_renewal_reminders()
        last = notes(uid, "plan_ends_today")
        check(len(last) == 1 and not notes(uid, "plan_ending_soon"),
              "plan_reminder_last_day: a Pro plan first seen in its last 24 hours gets only the 'ends today' reminder", last)
        check(last and last[0]["title"] == "Your Pro Plan Ends Today"
              and last[0]["message"] == f"Your Toe Pwar Pro plan ends within 24 hours, on {format_date(aware(ends), 'en')}. "
                                        "Renew now to keep your AI allowances and Pro features.",
              "plan_reminder_last_day: the 'ends today' text names Pro and the end date", last)
        await ss.send_plan_renewal_reminders()
        check(len(notes(uid, "plan_ends_today")) == 1 and row(uid, "plan_reminder_last_for")[0] == ends,
              "plan_reminder_last_day: a second run sends nothing more")
        # a plan that already got the 3-day reminder gets the last-day one when the day comes, once; Myanmar text
        uid, _, ends = paid_user("pr3then1", "plus", timedelta(days=2, hours=12), "my")
        await ss.send_plan_renewal_reminders()
        later = datetime.now(UTC) + timedelta(days=2)
        await ss.send_plan_renewal_reminders(later)
        await ss.send_plan_renewal_reminders(later + timedelta(hours=1))
        soon, last = notes(uid, "plan_ending_soon"), notes(uid, "plan_ends_today")
        check(len(soon) == 1 and len(last) == 1
              and all(MYANMAR.search(x["message"]) and MYANMAR.search(x["title"]) and "Plus" in x["message"]
                      and format_date(aware(ends), "my") in x["message"] for x in soon + last),
              "plan_reminder_last_day: a Myanmar user gets one 'ends soon' then one 'ends today', both in Myanmar with "
              "the Burmese date", (len(soon), len(last)))

        # ---- no_plan_reminder: more than 3 days left, lifetime, ended, trial, free
        p5, _, _ = paid_user("pr5", "plus", timedelta(days=5))
        plife, _, _ = paid_user("prlife", "pro", None)
        pended, _, _ = paid_user("prended", "plus", timedelta(hours=-1))
        ptrial, _, _ = trial_user("prtrial", timedelta(days=2))
        ptrial_last, _, _ = trial_user("prtrial-last", timedelta(hours=10))
        pfree, _ = register("prfree")
        await ss.send_plan_renewal_reminders()
        check(all(not notes(u, *PLAN_TYPES) for u in (p5, plife, pended, ptrial, ptrial_last, pfree)),
              "no_plan_reminder: none for 5 days left, a lifetime plan, a plan that has ended, a trial, or a Free user")
        check(row(plife, "plan_reminder_3d_for", "plan_reminder_last_for") == (None, None)
              and row(ptrial, "plan_reminder_3d_for", "plan_reminder_last_for") == (None, None),
              "no_plan_reminder: nothing is claimed for them either")
        await ss.send_trial_reminders()
        check(len(notes(ptrial, "trial_ending_soon")) == 1 and len(notes(ptrial_last, "trial_ends_today")) == 1,
              "no_plan_reminder: trial users still get their trial reminders")

        # ---- plan_reminder_extension: a new end date re-arms the reminders; a far one sends nothing
        uid, _, first_end = paid_user("prext", "plus", timedelta(days=2))
        await ss.send_plan_renewal_reminders()
        check(len(notes(uid, "plan_ending_soon")) == 1, "plan_reminder_extension: setup: one reminder for the first end date")
        new_end = datetime.now(UTC) + timedelta(days=2, hours=20)
        set_plan(uid, "plus", new_end)
        await ss.send_plan_renewal_reminders()
        await ss.send_plan_renewal_reminders()
        soon = sorted(notes(uid, "plan_ending_soon"), key=lambda n: n["created_at"])
        stored_end = row(uid, "subscription_expires_at")[0]
        check(len(soon) == 2 and format_date(aware(stored_end), "en") in soon[1]["message"]
              and row(uid, "plan_reminder_3d_for")[0] == stored_end and stored_end != first_end,
              "plan_reminder_extension: extended to a new end date within 3 days, one new reminder for the new date",
              (len(soon), [n["message"] for n in soon]))
        set_plan(uid, "plus", datetime.now(UTC) + timedelta(days=30))
        await ss.send_plan_renewal_reminders()
        check(len(notes(uid, "plan_ending_soon")) == 2 and not notes(uid, "plan_ends_today"),
              "plan_reminder_extension: extended far away (30 days), nothing more is sent")
        # the same end date saved again by the admin does not re-arm it
        uid, _, ends = paid_user("prsame", "pro", timedelta(days=2))
        await ss.send_plan_renewal_reminders()
        set_plan(uid, "pro", aware(ends))
        await ss.send_plan_renewal_reminders()
        check(len(notes(uid, "plan_ending_soon")) == 1,
              "plan_reminder_extension: re-saving the same plan and end date sends no second reminder")

        # ---- plan_reminder_race: overlapping runs send exactly one
        uid, _, _ = paid_user("prrace", "pro", timedelta(days=2))
        await asyncio.gather(*(ss.send_plan_renewal_reminders() for _ in range(4)))
        check(len(notes(uid, "plan_ending_soon")) == 1, "plan_reminder_race: four overlapping runs send exactly one reminder",
              len(notes(uid, "plan_ending_soon")))

        # ---- plan_reminder_preference: a stored preference of "off" is honoured
        uid, h = register("prpref")
        r = c.put("/api/notifications/preferences", headers=h, json={"preferences": {"plan_ending_soon": False}})
        set_plan(uid, "plus", datetime.now(UTC) + timedelta(days=2))
        await ss.send_plan_renewal_reminders()
        check(r.status_code == 200 and not notes(uid, *PLAN_TYPES),
              "plan_reminder_preference: a user whose stored preference for it is off is not reminded",
              f"{r.status_code} {r.text[:150]}")

        # ---- admin_usage_view
        uid, h = register("usage")
        user = await users_db.get_user(uid)
        for _ in range(2):
            await quota.reserve(user, "chat")
        await quota.reserve(user, "entry")
        add_cost(uid, 0.04)
        r = c.get(f"/api/admin/users/{uid}/usage", headers=MOD)
        j = r.json() if r.status_code == 200 else {}
        feats = j.get("features", {})
        check(r.status_code == 200 and set(j) == USAGE_KEYS and set(feats) == set(catalog.FEATURES)
              and all(set(v) == USAGE_FEATURE_KEYS for v in feats.values()),
              "admin_usage_view: a moderator gets {plan, features, month_spend_usd, cost_cap_usd, cost_cap_reached}", f"{r.status_code} {r.text[:300]}")
        check(j.get("plan") == "free" and feats.get("chat") == {"mode": "counted", "used": 2, "limit": 5, "period": "week"}
              and feats.get("entry") == {"mode": "counted", "used": 1, "limit": 10, "period": "month"}
              and feats.get("budget_suggestion") == {"mode": "counted", "used": 0, "limit": 1, "period": "month"},
              "admin_usage_view: a Free user's counts are this period's used and the plan's limit (chat 2/5 week, entry 1/10 month)", feats.get("chat"))
        check(feats.get("insight_weekly") == {"mode": "locked", "used": None, "limit": None, "period": None},
              "admin_usage_view: a locked feature shows mode locked and no counts", feats.get("insight_weekly"))
        check(abs(j.get("month_spend_usd", -1) - 0.04) < 1e-9 and j.get("cost_cap_usd") == 0.1 and j.get("cost_cap_reached") is False,
              "admin_usage_view: month spend 0.04 of the 0.10 Free cap, not reached", (j.get("month_spend_usd"), j.get("cost_cap_usd")))
        add_cost(uid, 0.07)
        add_cost(uid, 9.0, periods.month_start_utc(datetime.now(UTC)) - timedelta(minutes=1))  # last month: not counted
        j = c.get(f"/api/admin/users/{uid}/usage", headers=MOD).json()
        check(abs(j.get("month_spend_usd", -1) - 0.11) < 1e-9 and j.get("cost_cap_reached") is True,
              "admin_usage_view: spend 0.11 reaches the cap; last month's spend is not counted", (j.get("month_spend_usd"), j.get("cost_cap_reached")))
        set_plan(uid, "plus")
        j = c.get(f"/api/admin/users/{uid}/usage", headers=AD).json()
        check(j.get("plan") == "plus" and j["features"]["chat"]["limit"] == 100 and j["features"]["chat"]["period"] == "month"
              and j["features"]["chat"]["used"] == 2 and j["features"]["reports"]["mode"] == "included"
              and j["cost_cap_usd"] == 1.0 and j["cost_cap_reached"] is False,
              "admin_usage_view: after a change to Plus, the view uses Plus limits (chat 2/100 month) and the Plus cap", j.get("features", {}).get("chat"))
        set_plan(uid, "plus", datetime.now(UTC) - timedelta(minutes=1))
        check(c.get(f"/api/admin/users/{uid}/usage", headers=MOD).json().get("plan") == "free",
              "admin_usage_view: an expired Plus shows as free")
        check(c.get("/api/admin/users/no-such-user/usage", headers=MOD).status_code == 404, "admin_usage_view: an unknown user is 404")
        check(c.get(f"/api/admin/users/{uid}/usage").status_code in (401, 403), "admin_usage_view: it needs an admin token")
        check(c.get(f"/api/admin/users/{uid}/usage", headers=h).status_code in (401, 403), "admin_usage_view: a user token is refused")

        # ---- moderator_cannot_reset
        uid, _ = register("reset")
        user = await users_db.get_user(uid)
        for _ in range(3):
            await quota.reserve(user, "chat")
        add_cost(uid, 0.2)
        r = c.post(f"/api/admin/users/{uid}/reset-usage", headers=MOD)
        j = c.get(f"/api/admin/users/{uid}/usage", headers=MOD).json()
        check(r.status_code == 403 and j["features"]["chat"]["used"] == 3 and j["cost_cap_reached"] is True
              and row(uid, "usage_reset_at")[0] is None,
              "moderator_cannot_reset: a moderator's reset is 403 and changes nothing", (r.status_code, j["features"]["chat"]))
        check(not [x for x in logs(made["moderator"]) if x["action"] == "reset_user_usage"],
              "moderator_cannot_reset: the refused reset is not logged")
        check(c.post(f"/api/admin/users/{uid}/reset-usage").status_code in (401, 403), "moderator_cannot_reset: no token is refused")

        # ---- admin_reset_usage_logged
        spend_rows = lambda: len(list(db.ai_usage.find({"user_id": uid})))  # noqa: E731
        rows_before = spend_rows()
        r = c.post(f"/api/admin/users/{uid}/reset-usage", headers=AD)
        j = c.get(f"/api/admin/users/{uid}/usage", headers=MOD).json()
        check(r.status_code == 200 and counter_rows(uid) == 0 and row(uid, "usage_reset_at")[0] is not None,
              "admin_reset_usage_logged: the admin's reset clears the counters and sets usage_reset_at", f"{r.status_code} {r.text[:200]}")
        check(j["features"]["chat"]["used"] == 0 and j["month_spend_usd"] == 0 and j["cost_cap_reached"] is False
              and spend_rows() == rows_before == 1,
              "admin_reset_usage_logged: usage 0 and spend 0 after the reset, the ai_usage rows are kept", (j["features"]["chat"], j["month_spend_usd"]))
        add_cost(uid, 0.03)
        check(abs(c.get(f"/api/admin/users/{uid}/usage", headers=MOD).json()["month_spend_usd"] - 0.03) < 1e-9,
              "admin_reset_usage_logged: spend after the reset counts from zero")
        entries = [x for x in logs(made["admin"]) if x["action"] == "reset_user_usage"]
        check(len(entries) == 1 and entries[0].get("target_user_email") == f"t4s-reset-{tag}@example.com",
              "admin_reset_usage_logged: the reset is in the admin action logs with the target user", entries)
        check(c.post("/api/admin/users/no-such-user/reset-usage", headers=AD).status_code == 404, "admin_reset_usage_logged: an unknown user is 404")

        # ---- broadcast_targets_paid
        b_free, _ = register("bc-free")
        b_plus, _ = register("bc-plus")
        b_pro, _ = register("bc-pro")
        b_exp, _ = register("bc-exp")
        set_plan(b_plus, "plus", datetime.now(UTC) + timedelta(days=3))
        set_plan(b_pro, "pro")
        set_plan(b_exp, "pro", datetime.now(UTC) - timedelta(minutes=2))
        group = {"free": b_free, "plus": b_plus, "pro": b_pro, "expired": b_exp}

        def broadcast(target, title):
            return c.post("/api/admin/broadcast-notification", headers=AD, json={"title": title, "message": "hello", "target_users": target})

        def received(title):
            return {name for name, u in group.items() if any(n.get("title") == title for n in db.notifications.find({"user_id": u}))}

        for target, want in (("paid", {"plus", "pro"}), ("plus", {"plus"}), ("pro", {"pro"}), ("free", {"free", "expired"}),
                             ("all", {"free", "plus", "pro", "expired"})):
            title = f"{broadcast_title}-{target}"
            r = broadcast(target, title)
            got = received(title)
            check(r.status_code == 200 and got == want, f"broadcast_targets_paid: target '{target}' reaches {sorted(want)}",
                  (r.status_code, sorted(got), r.text[:150]))
        check(broadcast("premium", f"{broadcast_title}-premium").status_code == 422, "broadcast_targets_paid: 'premium' is no longer a target")
        check(c.post("/api/admin/broadcast-notification", headers=MOD, json={"title": "x", "message": "y", "target_users": "paid"}).status_code == 403,
              "broadcast_targets_paid: a moderator cannot broadcast")

        # ---- dashboard_counts_per_plan
        def counts():
            u = c.get("/api/admin/stats/users", headers=MOD).json()
            s = c.get("/api/admin/stats/system", headers=MOD).json()
            b = c.get("/api/admin/broadcast-stats", headers=MOD).json()
            return u, s, b

        u0, s0, b0 = counts()
        base = datetime.now(UTC)
        d_free, _ = register("dc-free")
        d_plus, _ = register("dc-plus")
        d_pro, _ = register("dc-pro")
        d_exp, _ = register("dc-exp")
        d_life, _ = register("dc-life")
        set_plan(d_plus, "plus", base + timedelta(days=5))
        set_plan(d_pro, "pro", base + timedelta(days=5))
        set_plan(d_exp, "plus", base - timedelta(minutes=3))
        set_plan(d_life, "pro")
        for d in (d_plus, d_pro):
            db.users.update_one({"_id": d}, {"$set": {"fcm_token": f"t4s-push-{d}"}})
        u1, s1, b1 = counts()
        delta = lambda a, b, k: b[k] - a[k]  # noqa: E731
        check(delta(u0, u1, "total_users") == 5 and delta(u0, u1, "free_users") == 2 and delta(u0, u1, "plus_users") == 1
              and delta(u0, u1, "pro_users") == 2 and delta(u0, u1, "paid_users") == 3,
              "dashboard_counts_per_plan: user stats move by free +2 (incl. the expired Plus), plus +1, pro +2, paid +3",
              {k: delta(u0, u1, k) for k in ("total_users", "free_users", "plus_users", "pro_users", "paid_users")})
        check(delta(s0, s1, "free_users") == 2 and delta(s0, s1, "plus_users") == 1 and delta(s0, s1, "pro_users") == 2
              and delta(s0, s1, "paid_users") == 3, "dashboard_counts_per_plan: system stats agree",
              {k: delta(s0, s1, k) for k in ("free_users", "plus_users", "pro_users", "paid_users")})
        check(delta(b0, b1, "free_users") == 2 and delta(b0, b1, "plus_users") == 1 and delta(b0, b1, "pro_users") == 2
              and delta(b0, b1, "paid_users") == 3 and delta(b0, b1, "plus_with_push") == 1 and delta(b0, b1, "pro_with_push") == 1
              and delta(b0, b1, "paid_with_push") == 2 and delta(b0, b1, "free_with_push") == 0,
              "dashboard_counts_per_plan: broadcast reach counts users and users with push per plan",
              {k: delta(b0, b1, k) for k in b0 if isinstance(b0[k], int)})
        check(u1["free_users"] + u1["paid_users"] == u1["total_users"] and u1["paid_users"] == u1["plus_users"] + u1["pro_users"]
              and not ({"premium_users", "premium_with_push"} & (set(u1) | set(s1) | set(b1))),
              "dashboard_counts_per_plan: free + paid = total, paid = plus + pro, and no premium_* fields remain", sorted(u1))
        with t.connect() as conn:
            truth = {p: conn.execute("SELECT count(*) FROM users WHERE subscription_type = %s AND (subscription_expires_at IS NULL "
                                     "OR subscription_expires_at > now())", (p,)).fetchone()[0] for p in ("plus", "pro")}
        check(u1["plus_users"] == truth["plus"] and u1["pro_users"] == truth["pro"],
              "dashboard_counts_per_plan: the counts equal the database", (u1["plus_users"], u1["pro_users"], truth))
    finally:
        try:
            db.notifications.delete_many({"title": {"$regex": f"^{broadcast_title}"}})
        finally:
            db.users.delete_many({"email": {"$regex": f"^t4s-.*-{tag}@"}})
            db.admins.delete_many({"email": {"$in": list(made.values())}})
            c.close()
