"""Plans and AI quotas: the Free/Plus/Pro schema, the plan catalogue and the premium -> plus migration (task 1),
then the period maths, the limits store and the admin Plans API (task 2), then the quota engine, the cost cap and
GET /api/plan (task 3, in plans_quota_checks.py), then plan expiry, the Plus trial and its reminders, and the admin
usage controls (task 4, in plans_subscription_checks.py), then chat quotas and Pro's Advanced chat (task 5, in
plans_chat_checks.py), then the entry, budget and report gates and the voice token (task 6, in plans_entry_checks.py),
then the insight routes and scheduled jobs by plan and the per-request insight language (task 7, in plans_insight_checks.py),
then upgrade requests and the admin users list's effective plan (plan polish, in plans_upgrade_request_checks.py).

Print-only suite: every check prints [PASS] or [BUG]; the exit code is non-zero if any check failed.
Keep this suite LAST in run_backend_suite.SUITES (it runs alembic downgrade/upgrade on the e2e database).

The migration checks run `alembic downgrade` / `alembic upgrade` on the throwaway e2e database (nothing else
runs at the same time: the backend suites run one after another) and always leave it at head again.
"""
import asyncio
import os
import subprocess
import sys
import uuid
from datetime import date, datetime, timedelta, UTC

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402

os.chdir(stubenv.BACKEND)
import httpx  # noqa: E402
import psycopg  # noqa: E402

BEFORE_PLANS = "a3f1c7d92b64"  # the revision this task's migration revises
DSN = os.environ["DATABASE_URL"]
TABLES = ("plan_limits", "plan_settings", "app_settings", "usage_counters")
results = []


def check(ok, name, detail=""):
    results.append(bool(ok))
    print(("[PASS] " if ok else "[BUG] ") + name + (f" -- {detail}" if detail and not ok else ""), flush=True)


def connect():
    return psycopg.connect(DSN, autocommit=True)


def alembic(*args):
    """Run an Alembic command against the e2e database -> (ok, tail of its output)."""
    p = subprocess.run([sys.executable, "-m", "alembic", "-c", "alembic.ini", *args], capture_output=True, text=True,
                       cwd=stubenv.BACKEND, env=dict(os.environ, PYTHONIOENCODING="utf-8"), timeout=300)
    return p.returncode == 0, (p.stdout + p.stderr)[-500:]


def current_revision(conn):
    row = conn.execute("SELECT version_num FROM alembic_version").fetchone()
    return row[0] if row else None


def table_names(conn):
    return {r[0] for r in conn.execute("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'")}


def column_names(conn, table):
    return {r[0] for r in conn.execute(
        "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = %s", (table,))}


def accepted(conn, *statements):
    """True when every (sql, params) statement succeeds in one transaction; always rolled back."""
    try:
        with conn.transaction():
            for sql, params in statements:
                conn.execute(sql, params)
            raise psycopg.Rollback()
    except psycopg.Error:
        return False
    return True


def new_user(uid, sub="free", expires=None):
    return ("INSERT INTO users (id, name, email, password, subscription_type, subscription_expires_at) "
            "VALUES (%s, 't', %s, 'x', %s, %s)", (uid, f"{uid}@plans.test", sub, expires))


def schema_checks():
    with connect() as conn:
        have = table_names(conn)
        check(set(TABLES) <= have, "schema_has_plan_tables: plan_limits, plan_settings, app_settings, usage_counters exist",
              sorted(set(TABLES) - have))
        cols = column_names(conn, "users")
        check({"trial_ends_at", "usage_reset_at"} <= cols, "schema_has_plan_tables: users.trial_ends_at and users.usage_reset_at exist",
              sorted(cols))
        for plan, ok in (("free", True), ("plus", True), ("pro", True), ("premium", False), ("gold", False)):
            check(accepted(conn, new_user("pl-chk", plan)) == ok,
                  f"schema: users.subscription_type {plan!r} {'accepted' if ok else 'rejected'}")
        check(accepted(conn, new_user("pl-null", "plus", None)), "schema: a plus user may have no expiry (lifetime)")

        ins = "INSERT INTO plan_limits (plan, feature, mode, quota, period) VALUES (%s, %s, %s, %s, %s)"
        probes = [
            ("a counted limit of 5 per week", ("free", "chat_test", "counted", 5, "week"), True),
            ("a locked limit", ("plus", "chat_test", "locked", None, None), True),
            ("an included limit", ("pro", "chat_test", "included", None, None), True),
            ("a counted limit of 0", ("free", "chat_test", "counted", 0, "month"), True),
            ("an unknown plan", ("zz", "chat_test", "locked", None, None), False),
            ("mode 'bogus'", ("free", "chat_test", "bogus", None, None), False),
            ("period 'day'", ("free", "chat_test", "counted", 5, "day"), False),
            ("a counted limit without a quota", ("free", "chat_test", "counted", None, "week"), False),
            ("a counted limit without a period", ("free", "chat_test", "counted", 5, None), False),
            ("a counted limit with a negative quota", ("free", "chat_test", "counted", -1, "week"), False),
            ("a duplicate (plan, feature)", ("free", "chat", "locked", None, None), False),
        ]
        for label, params, ok in probes:
            check(accepted(conn, (ins, params)) == ok, f"schema: plan_limits {'accepts' if ok else 'rejects'} {label}")
        check(not accepted(conn, ("INSERT INTO plan_settings (plan, cost_cap_usd) VALUES ('gold', 1)", ())),
              "schema: plan_settings rejects an unknown plan")
        check(not accepted(conn, ("UPDATE plan_settings SET cost_cap_usd = -1 WHERE plan = 'free'", ())),
              "schema: plan_settings rejects a negative cost cap")
        check(accepted(conn, ("INSERT INTO app_settings (key, value) VALUES ('plans-test', 'x')", ())),
              "schema: app_settings (key, value) accepts a row; updated_at defaults")

        usage = "INSERT INTO usage_counters (user_id, feature, period, period_start) VALUES (%s, 'chat', %s, '2026-11-02')"
        check(accepted(conn, new_user("pl-use"), (usage, ("pl-use", "week"))), "schema: usage_counters accepts a row (used defaults to 0)")
        check(not accepted(conn, (usage, ("no-such-user", "week"))), "schema: usage_counters rejects an unknown user (foreign key)")
        check(not accepted(conn, new_user("pl-use"), (usage, ("pl-use", "day"))), "schema: usage_counters rejects period 'day'")
        check(not accepted(conn, new_user("pl-use"), (usage, ("pl-use", "week")), (usage, ("pl-use", "week"))),
              "schema: usage_counters primary key rejects a duplicate")
        check(not accepted(conn, new_user("pl-use"), (usage, ("pl-use", "week")),
                           ("UPDATE usage_counters SET used = -1 WHERE user_id = 'pl-use'", ())),
              "schema: usage_counters rejects a negative count")
        left = None
        try:
            with conn.transaction():
                conn.execute(*new_user("pl-cascade"))
                conn.execute(usage, ("pl-cascade", "month"))
                conn.execute("DELETE FROM users WHERE id = 'pl-cascade'")
                left = conn.execute("SELECT count(*) FROM usage_counters WHERE user_id = 'pl-cascade'").fetchone()[0]
                raise psycopg.Rollback()
        except psycopg.Error as e:
            left = repr(e)
        check(left == 0, "schema: deleting a user deletes its usage counters", left)


def catalog_checks():
    try:
        from plans import catalog
    except Exception as e:  # noqa: BLE001
        check(False, "catalog: plans.catalog imports", repr(e))
        return
    check(catalog.PLANS == ("free", "plus", "pro"), "catalog: PLANS", catalog.PLANS)
    check(catalog.PAID_PLANS == ("plus", "pro"), "catalog: PAID_PLANS", catalog.PAID_PLANS)
    check(catalog.FEATURES == ("chat", "chat_advanced", "insight_monthly", "insight_weekly", "insight_translation",
                               "entry", "budget_suggestion", "reports"), "catalog: FEATURES", catalog.FEATURES)
    check(set(catalog.DEFAULT_LIMITS) == set(catalog.PLANS)
          and all(set(v) == set(catalog.FEATURES) for v in catalog.DEFAULT_LIMITS.values()),
          "catalog: DEFAULT_LIMITS has all 24 (plan, feature) pairs")
    check(set(catalog.DEFAULT_COST_CAPS) == set(catalog.PLANS), "catalog: DEFAULT_COST_CAPS has every plan")
    lim = catalog.Limit("counted", 5, "week")
    try:
        lim.quota = 6
        frozen = False
    except Exception:  # noqa: BLE001
        frozen = True
    check(frozen and catalog.Limit("locked") == catalog.Limit("locked", None, None), "catalog: Limit is frozen, quota/period default to None")
    L = catalog.Limit
    spec = {
        "free": {"chat": L("counted", 5, "week"), "chat_advanced": L("locked"), "insight_monthly": L("counted", 1, "month"),
                 "insight_weekly": L("locked"), "insight_translation": L("locked"), "entry": L("counted", 10, "month"),
                 "budget_suggestion": L("counted", 1, "month"), "reports": L("locked")},
        "plus": {"chat": L("counted", 100, "month"), "chat_advanced": L("locked"), "insight_monthly": L("included"),
                 "insight_weekly": L("included"), "insight_translation": L("included"), "entry": L("counted", 150, "month"),
                 "budget_suggestion": L("counted", 5, "month"), "reports": L("included")},
        "pro": {"chat": L("counted", 400, "month"), "chat_advanced": L("counted", 100, "month"), "insight_monthly": L("included"),
                "insight_weekly": L("included"), "insight_translation": L("included"), "entry": L("counted", 500, "month"),
                "budget_suggestion": L("counted", 20, "month"), "reports": L("included")},
    }
    check(catalog.DEFAULT_LIMITS == spec, "catalog: DEFAULT_LIMITS match the agreed defaults")
    check(catalog.DEFAULT_COST_CAPS == {"free": 0.10, "plus": 1.00, "pro": 3.00}, "catalog: DEFAULT_COST_CAPS 0.10 / 1.00 / 3.00",
          catalog.DEFAULT_COST_CAPS)


def seeded_limits(conn):
    return {(r[0], r[1]): (r[2], r[3], r[4]) for r in conn.execute("SELECT plan, feature, mode, quota, period FROM plan_limits")}


def defaults_seeded(conn, label):
    """plan_limits and plan_settings hold exactly the catalogue defaults."""
    try:
        from plans import catalog
    except Exception as e:  # noqa: BLE001
        check(False, f"defaults_seeded{label}: needs plans.catalog", repr(e))
        return
    want ={(p, f): (lim.mode, lim.quota, lim.period) for p, feats in catalog.DEFAULT_LIMITS.items() for f, lim in feats.items()}
    got = seeded_limits(conn)
    check(len(got) == 24 and got == want, f"defaults_seeded{label}: plan_limits rows equal DEFAULT_LIMITS (24 pairs)",
          f"{len(got)} rows; differ: {sorted(set(got.items()) ^ set(want.items()))[:4]}")
    caps = {r[0]: float(r[1]) for r in conn.execute("SELECT plan, cost_cap_usd FROM plan_settings")}
    check(caps == {"free": 0.10, "plus": 1.00, "pro": 3.00}, f"defaults_seeded{label}: plan_settings caps are 0.10, 1.00, 3.00", caps)


def migration_checks():
    expires = datetime.now(UTC).replace(microsecond=0) + timedelta(days=45)
    ids = ("pl-mig-prem", "pl-mig-life", "pl-mig-free")
    with connect() as conn:
        at_head = current_revision(conn)
        check(at_head not in (None, BEFORE_PLANS), "migration: the e2e database is already past the AI-provider revision", at_head)
        try:
            ok, out = alembic("downgrade", BEFORE_PLANS)
            check(ok and current_revision(conn) == BEFORE_PLANS, "downgrade_maps_back: downgrade to the AI-provider revision runs", out)
            have = table_names(conn)
            check(not (set(TABLES) & have) and not ({"trial_ends_at", "usage_reset_at"} & column_names(conn, "users")),
                  "downgrade_maps_back: the new tables and users columns are dropped", sorted(set(TABLES) & have))

            for uid, sub, exp in (("pl-mig-prem", "premium", expires), ("pl-mig-life", "premium", None), ("pl-mig-free", "free", None)):
                conn.execute(*new_user(uid, sub, exp))
            ok, out = alembic("upgrade", "head")
            check(ok, "premium_migrated_to_plus: upgrade runs on a database holding premium users", out)
            rows = {r[0]: r[1:] for r in conn.execute(
                "SELECT id, subscription_type, subscription_expires_at, trial_ends_at, usage_reset_at FROM users WHERE id = ANY(%s)", (list(ids),))}
            check(rows.get("pl-mig-prem", (None,))[0] == "plus" and rows["pl-mig-prem"][1] == expires,
                  "premium_migrated_to_plus: a premium user with an expiry is now plus with the same expiry", rows.get("pl-mig-prem"))
            check(rows.get("pl-mig-life", (None,))[0] == "plus" and rows["pl-mig-life"][1] is None,
                  "premium_migrated_to_plus: a lifetime premium user is now plus with no expiry", rows.get("pl-mig-life"))
            check(rows.get("pl-mig-free", (None,))[0] == "free", "premium_migrated_to_plus: a free user stays free", rows.get("pl-mig-free"))
            check(all(r[2] is None and r[3] is None for r in rows.values()), "premium_migrated_to_plus: trial_ends_at and usage_reset_at start empty", rows)
            check(not conn.execute("SELECT 1 FROM users WHERE subscription_type = 'premium'").fetchone(),
                  "premium_migrated_to_plus: no premium user is left")
            defaults_seeded(conn, " (after upgrade)")

            # plus and pro map back to premium, free stays free; the expiry is kept.
            conn.execute("UPDATE users SET subscription_type = 'pro' WHERE id = 'pl-mig-life'")
            ok, out = alembic("downgrade", BEFORE_PLANS)
            back = {r[0]: r[1:] for r in conn.execute(
                "SELECT id, subscription_type, subscription_expires_at FROM users WHERE id = ANY(%s)", (list(ids),))}
            check(ok and back.get("pl-mig-prem") == ("premium", expires) and back.get("pl-mig-life") == ("premium", None)
                  and back.get("pl-mig-free", (None,))[0] == "free",
                  "downgrade_maps_back: plus and pro come back as premium (expiry kept), free stays free", f"{out} {back}")
            check(not accepted(conn, new_user("pl-mig-x", "plus")) and accepted(conn, new_user("pl-mig-x", "premium")),
                  "downgrade_maps_back: the old CHECK (free, premium) is back")
            ok, out = alembic("upgrade", "head")
            check(ok and TABLES[0] in table_names(conn), "downgrade_maps_back: upgrade is clean again after a downgrade", out)
            defaults_seeded(conn, " (after re-upgrade)")
        finally:
            ok, out = alembic("upgrade", "head")  # whatever happened above, leave the database at head
            conn.execute("DELETE FROM users WHERE id = ANY(%s)", (list(ids),))
            check(ok and current_revision(conn) == at_head, "migration: the e2e database is left at head", out)


def behaviour_checks():
    """The renamed plan checks keep behaviour: plus and pro are the paid plans, free is not, an expired paid user is free."""
    c = httpx.Client(base_url="http://127.0.0.1:8765", timeout=60)
    db = __import__("pgcompat").get_db()
    now = datetime.now(UTC)

    def user(tag, sub, expires=None):
        email = f"pl-{tag}-{uuid.uuid4().hex[:5]}@example.com"
        c.post("/api/auth/register", json={"name": tag, "email": email, "password": "secret123"})
        db.users.update_one({"email": email}, {"$set": {"is_verified": True, "subscription_type": sub, "subscription_expires_at": expires}})
        token = c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json()["access_token"]
        return email, {"Authorization": f"Bearer {token}"}

    try:
        cases = [("free", "free", None, False), ("plus", "plus", None, True), ("pro", "pro", None, True),
                 ("plus-exp", "plus", now - timedelta(days=1), False), ("pro-exp", "pro", now - timedelta(days=1), False),
                 ("pro-live", "pro", now + timedelta(days=9), True)]
        for tag, sub, expires, paid in cases:
            _, h = user(tag, sub, expires)
            r = c.get("/api/insights", headers=h)
            check((r.status_code != 403) == paid, f"behaviour: {tag} user {'reaches' if paid else 'is blocked from'} a premium endpoint", r.status_code)
            s = c.get("/api/auth/subscription-status", headers=h)
            check(s.status_code == 200 and s.json().get("is_paid") == paid and s.json().get("subscription_type") == sub
                  and s.json().get("plan") == (sub if paid else "free"),
                  f"behaviour: subscription-status for {tag} says is_paid={paid}", s.text[:200])
        email, h = user("trial", "free")
        r = c.post("/api/auth/claim-free-trial", headers=h)
        check(r.status_code == 200 and r.json().get("subscription_type") == "plus", "behaviour: claim-free-trial grants plus", r.text[:200])
        r = c.post("/api/auth/claim-free-trial", headers=h)
        check(r.status_code == 400, "behaviour: a second claim-free-trial is refused", r.status_code)
        email, h = user("pro-trial", "pro")
        r = c.post("/api/auth/claim-free-trial", headers=h)
        check(r.status_code == 400, "behaviour: a pro user cannot claim the free trial", r.status_code)
    finally:
        db.users.delete_many({"email": {"$regex": "^pl-"}})


# ---- task 2: periods, the limits store and the admin Plans API ----

ADMIN_PW = "t2-admin-pass-1"


def utc(*args):
    return datetime(*args, tzinfo=UTC)


def body_of(limits, caps, contact):
    """The admin API body ({plans: {plan: {limits, cost_cap_usd}}, upgrade_contact}) for catalogue-shaped inputs."""
    return {"plans": {p: {"limits": {f: {"mode": l.mode, "quota": l.quota, "period": l.period} for f, l in limits[p].items()},
                          "cost_cap_usd": caps[p]} for p in limits},
            "upgrade_contact": dict(contact)}


def default_body():
    from plans import catalog
    return body_of(catalog.DEFAULT_LIMITS, catalog.DEFAULT_COST_CAPS, {"en": "", "my": ""})


def stored_plans(conn):
    """What the database holds: ({(plan, feature): (mode, quota, period)}, {plan: cap}, {key: value})."""
    return (seeded_limits(conn),
            {r[0]: float(r[1]) for r in conn.execute("SELECT plan, cost_cap_usd FROM plan_settings")},
            {r[0]: r[1] for r in conn.execute("SELECT key, value FROM app_settings WHERE key LIKE 'upgrade_contact_%'")})


def period_checks():
    from plans import periods
    check(periods.period_start("week", utc(2026, 11, 2, 23, 30)) == date(2026, 11, 2),
          "period_week_starts_monday_yangon: the week of 2026-11-03 06:00 Yangon starts on Monday 2026-11-02",
          periods.period_start("week", utc(2026, 11, 2, 23, 30)))
    check(periods.resets_at("week", utc(2026, 11, 2, 23, 30)) == utc(2026, 11, 8, 17, 30)
          and periods.resets_at("week", utc(2026, 11, 2, 23, 30)).utcoffset() == timedelta(0),
          "period_week_starts_monday_yangon: that week resets at 2026-11-08T17:30:00Z (Monday 00:00 Yangon)",
          periods.resets_at("week", utc(2026, 11, 2, 23, 30)))
    # Sunday 23:59 Yangon is still the old week; Monday 00:00 Yangon starts the new one.
    check(periods.period_start("week", utc(2026, 11, 8, 17, 29)) == date(2026, 11, 2)
          and periods.period_start("week", utc(2026, 11, 8, 17, 30)) == date(2026, 11, 9),
          "period_week_boundary: Sunday 23:59 Yangon is the old week, Monday 00:00 Yangon the new one")
    # Yangon is ahead of UTC, so late Sunday UTC is already Monday there.
    check(periods.period_start("week", utc(2026, 11, 1, 20, 0)) == date(2026, 11, 2),
          "period_week_boundary: Sunday 20:00 UTC (Monday 02:30 Yangon) is already the Monday week")
    check(periods.period_start("month", utc(2026, 11, 30, 18, 0)) == date(2026, 12, 1),
          "period_month_boundary: 2026-11-30 18:00 UTC (Yangon 00:30 on Dec 1) starts December",
          periods.period_start("month", utc(2026, 11, 30, 18, 0)))
    check(periods.period_start("month", utc(2026, 11, 30, 17, 29)) == date(2026, 11, 1),
          "period_month_boundary: 2026-11-30 17:29 UTC is still November")
    check(periods.resets_at("month", utc(2026, 11, 2, 23, 30)) == utc(2026, 11, 30, 17, 30)
          and periods.resets_at("month", utc(2026, 12, 20, 0, 0)) == utc(2026, 12, 31, 17, 30),
          "period_month_boundary: a month resets at the next month's midnight in Yangon (December -> January rolls the year)",
          (periods.resets_at("month", utc(2026, 11, 2, 23, 30)), periods.resets_at("month", utc(2026, 12, 20, 0, 0))))
    check(periods.month_start_utc(utc(2026, 11, 2, 23, 30)) == utc(2026, 10, 31, 17, 30)
          and periods.month_start_utc(utc(2026, 11, 30, 18, 0)) == utc(2026, 11, 30, 17, 30),
          "period_month_start_utc: the month starts at Yangon midnight, expressed in UTC",
          (periods.month_start_utc(utc(2026, 11, 2, 23, 30)), periods.month_start_utc(utc(2026, 11, 30, 18, 0))))
    check(periods.period_start("week", datetime(2026, 11, 2, 23, 30)) == date(2026, 11, 2)
          and periods.resets_at("week", datetime(2026, 11, 2, 23, 30)) == utc(2026, 11, 8, 17, 30),
          "period_naive_is_utc: a naive datetime is read as UTC")
    old = os.environ.get("SCHEDULER_TIMEZONE")
    try:
        os.environ["SCHEDULER_TIMEZONE"] = "UTC"
        check(periods.period_start("month", utc(2026, 11, 30, 18, 0)) == date(2026, 11, 1)
              and periods.resets_at("week", utc(2026, 11, 2, 23, 30)) == utc(2026, 11, 9, 0, 0),
              "period_uses_app_timezone: SCHEDULER_TIMEZONE changes the boundaries")
    finally:
        if old is None:
            os.environ.pop("SCHEDULER_TIMEZONE", None)
        else:
            os.environ["SCHEDULER_TIMEZONE"] = old
    for fn in (periods.period_start, periods.resets_at):
        try:
            fn("day", utc(2026, 11, 2))
            ok = False
        except ValueError:
            ok = True
        check(ok, f"period_unknown: {fn.__name__}('day') raises ValueError")


def mutated(limits=None, caps=None, contact=None):
    """save() arguments: the defaults, with the given (plan, feature) -> Limit / plan -> cap / contact replaced."""
    from plans import catalog
    rows = {p: dict(feats) for p, feats in catalog.DEFAULT_LIMITS.items()}
    for (p, f), v in (limits or {}).items():
        if v is None:
            del rows[p][f]
        else:
            rows[p][f] = v
    return rows, {**catalog.DEFAULT_COST_CAPS, **(caps or {})}, {"en": "", "my": "", **(contact or {})}


async def store_checks():
    """store.save validation (nothing is written), then save / load / refresh against the database."""
    from plans import catalog, store
    L = catalog.Limit
    with connect() as conn:
        before = stored_plans(conn)

        async def rejects(label, expect, **kw):
            rows, caps, contact = mutated(**kw)
            try:
                await store.save(rows, caps, contact, "t2-admin")
                msg = None
            except ValueError as e:
                msg = str(e)
            check(msg is not None and expect.lower() in msg.lower(), f"store_validation: {label} is rejected with a clear message",
                  msg)
            check(stored_plans(conn) == before, f"store_validation: {label} writes nothing")

        await rejects("a counted entry with no period", "chat", limits={("free", "chat"): L("counted", 5, None)})
        await rejects("a counted entry with no quota", "chat", limits={("free", "chat"): L("counted", None, "week")})
        await rejects("a negative quota", "quota", limits={("free", "chat"): L("counted", -1, "week")})
        await rejects("a fractional quota", "quota", limits={("free", "chat"): {"mode": "counted", "quota": 2.5, "period": "week"}})
        await rejects("a boolean quota", "quota", limits={("free", "chat"): {"mode": "counted", "quota": True, "period": "week"}})
        await rejects("an unknown period", "period", limits={("free", "chat"): L("counted", 5, "day")})
        await rejects("an unknown mode", "mode", limits={("free", "chat"): {"mode": "bogus"}})
        await rejects("a locked entry that carries a quota", "chat_advanced", limits={("free", "chat_advanced"): L("locked", 5, None)})
        await rejects("an included entry that carries a period", "reports", limits={("plus", "reports"): L("included", None, "week")})
        await rejects("a missing feature", "insight_weekly", limits={("pro", "insight_weekly"): None})
        await rejects("an unknown feature", "bogus", limits={("pro", "bogus"): L("locked")})
        await rejects("chat_advanced on while chat is locked", "chat_advanced",
                      limits={("plus", "chat"): L("locked"), ("plus", "chat_advanced"): L("included")})
        await rejects("a negative cost cap", "cost", caps={"plus": -0.01})
        await rejects("a NaN cost cap", "cost", caps={"plus": float("nan")})
        await rejects("a non-numeric cost cap", "cost", caps={"plus": "lots"})
        await rejects("a cost cap too large for the column", "cost", caps={"pro": 1e12})
        await rejects("an upgrade contact over 500 characters", "500", contact={"my": "x" * 501})
        await rejects("a non-text upgrade contact", "contact", contact={"en": 5})
        rows, caps, contact = mutated()
        del rows["pro"]
        try:
            await store.save(rows, caps, contact, "t2-admin")
            msg = None
        except ValueError as e:
            msg = str(e)
        check(msg is not None and "pro" in msg, "store_validation: a missing plan is rejected", msg)
        rows, caps, contact = mutated()
        del caps["free"]
        try:
            await store.save(rows, caps, contact, "t2-admin")
            msg = None
        except ValueError as e:
            msg = str(e)
        check(msg is not None and "free" in msg, "store_validation: a missing cost cap is rejected", msg)
        # the boundary values are valid: a quota of 0, a 500-character contact, a cap of 0
        rows, caps, contact = mutated(limits={("free", "chat"): L("counted", 0, "month"), ("pro", "chat"): L("locked"),
                                              ("pro", "chat_advanced"): L("locked")},
                                      caps={"free": 0}, contact={"en": "e" * 500, "my": "မြန်မာ" * 80})
        try:
            await store.save(rows, caps, contact, "t2-admin")
            msg = None
        except ValueError as e:
            msg = str(e)
        check(msg is None, "store_validation: quota 0, cap 0, chat_advanced locked with chat locked, 500-character texts are valid", msg)

        # load / cache: the defaults come back after the limits are put back
        await store.save(*mutated(), "t2-admin")
        await store.load()
        check(all(store.limits(p) == catalog.DEFAULT_LIMITS[p] for p in catalog.PLANS)
              and all(store.cost_cap(p) == catalog.DEFAULT_COST_CAPS[p] for p in catalog.PLANS)
              and store.upgrade_contact() == {"en": "", "my": ""},
              "store_load: after saving the defaults, load() holds the catalogue limits, caps and an empty contact")

        # save -> cache and database
        rows, caps, contact = mutated(limits={("free", "chat"): L("counted", 20, "month")}, caps={"plus": 1.5},
                                      contact={"en": "Message us", "my": "ဆက်သွယ်ပါ"})
        await store.save(rows, caps, contact, "t2-admin")
        got_limits, got_caps, got_contact = stored_plans(conn)
        check(store.limits("free")["chat"] == L("counted", 20, "month") and store.cost_cap("plus") == 1.5
              and store.upgrade_contact() == {"en": "Message us", "my": "ဆက်သွယ်ပါ"},
              "store_save: the cache changes at once")
        check(got_limits[("free", "chat")] == ("counted", 20, "month") and got_caps["plus"] == 1.5
              and got_contact == {"upgrade_contact_en": "Message us", "upgrade_contact_my": "ဆက်သွယ်ပါ"} and len(got_limits) == 24,
              "store_save: the database holds the new rows, caps and the app_settings keys upgrade_contact_en / upgrade_contact_my",
              (got_limits[("free", "chat")], got_caps, got_contact))
        # a locked mode clears the quota and period
        rows, caps, contact = mutated(limits={("free", "chat"): L("locked"), ("free", "chat_advanced"): L("locked")})
        await store.save(rows, caps, contact, "t2-admin")
        check(stored_plans(conn)[0][("free", "chat")] == ("locked", None, None) and store.limits("free")["chat"] == L("locked"),
              "store_save: switching an entry to locked stores a null quota and period")
        # dict-shaped entries (what the API passes) are accepted too
        await store.save({p: {f: {"mode": l.mode, "quota": l.quota, "period": l.period} for f, l in fs.items()}
                          for p, fs in catalog.DEFAULT_LIMITS.items()}, dict(catalog.DEFAULT_COST_CAPS), {"en": "", "my": ""}, "t2-admin")
        check(store.limits("free") == catalog.DEFAULT_LIMITS["free"], "store_save: entries may be dicts or Limit objects")

        # a copy is returned, so a caller cannot change the cache
        lim = store.limits("free")
        lim["chat"] = L("locked")
        con = store.upgrade_contact()
        con["en"] = "changed"
        check(store.limits("free") == catalog.DEFAULT_LIMITS["free"] and store.upgrade_contact()["en"] == "",
              "store_copies: limits() and upgrade_contact() hand out copies")

        # a stale refresh never overwrites a newer save
        real = store.plans_db.read_all
        gate, started = asyncio.Event(), asyncio.Event()

        async def slow_read():
            snapshot = await real()
            started.set()
            await gate.wait()
            return snapshot

        store.plans_db.read_all = slow_read
        try:
            task = asyncio.ensure_future(store.load())
            await started.wait()
            rows, caps, contact = mutated(limits={("free", "chat"): L("counted", 33, "week")})
            store.plans_db.read_all = real
            await store.save(rows, caps, contact, "t2-admin")
            gate.set()
            await task
        finally:
            store.plans_db.read_all = real
        check(store.limits("free")["chat"] == L("counted", 33, "week"),
              "store_write_generation: a load that overlapped a save does not overwrite the newer value", store.limits("free")["chat"])

        # a failing load keeps the last good cache and raises (startup treats that as non-fatal)
        async def boom():
            raise ConnectionError("db down")

        store.plans_db.read_all = boom
        try:
            try:
                await store.load()
                raised = False
            except ConnectionError:
                raised = True
        finally:
            store.plans_db.read_all = real
        check(raised and store.limits("free")["chat"] == L("counted", 33, "week"), "store_load_failure: the error propagates, the cache is kept")

        # the refresh loop picks up a change made by another process
        conn.execute("UPDATE plan_limits SET quota = 44, period = 'month' WHERE plan = 'free' AND feature = 'chat'")
        conn.execute("UPDATE plan_settings SET cost_cap_usd = 0.75 WHERE plan = 'free'")
        conn.execute("INSERT INTO app_settings (key, value) VALUES ('upgrade_contact_en', 'from elsewhere') "
                     "ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value")
        task = store.start_refresh_loop(0.05)
        check(store.start_refresh_loop(0.05) is task, "store_refresh_loop: starting it again returns the same task")
        for _ in range(60):
            await asyncio.sleep(0.05)
            if store.limits("free")["chat"] == L("counted", 44, "month"):
                break
        task.cancel()
        check(store.limits("free")["chat"] == L("counted", 44, "month") and store.cost_cap("free") == 0.75
              and store.upgrade_contact()["en"] == "from elsewhere",
              "store_refresh_loop: a change made in the database shows up on the next refresh")

        # a row missing from the database falls back to the catalogue default; a missing contact key is ''
        conn.execute("DELETE FROM plan_limits WHERE plan = 'plus' AND feature = 'entry'")
        conn.execute("DELETE FROM app_settings WHERE key = 'upgrade_contact_my'")
        await store.load()
        check(store.limits("plus")["entry"] == catalog.DEFAULT_LIMITS["plus"]["entry"] and store.upgrade_contact()["my"] == "",
              "store_load: a missing plan_limits row falls back to the default; a missing contact text is an empty string")
        # put the database and the cache back to the defaults
        await store.save(*mutated(), "t2-admin")
        await store.load()
        check(stored_plans(conn)[0] == before[0] and stored_plans(conn)[1] == before[1] and store.limits("free") == catalog.DEFAULT_LIMITS["free"],
              "store_checks: defaults restored")


def make_admins(db, roles):
    """Our own admins (never the root admin: test_api trips its login lockout) -> {role: email}."""
    import admin_utils
    made = {}
    for role in roles:
        email = f"t2plans-{role}-{uuid.uuid4().hex[:6]}@example.com"
        db.admins.insert_one({"_id": str(uuid.uuid4()), "name": f"t2 {role}", "email": email,
                              "password": admin_utils.get_password_hash(ADMIN_PW), "role": role,
                              "created_at": datetime.now(UTC), "last_login": None})
        made[role] = email
    return made


def admin_login(c, email):
    r = c.post("/api/admin/login", json={"email": email, "password": ADMIN_PW})
    return {"Authorization": "Bearer " + r.json()["access_token"]}


def api_checks():
    """/api/admin/plans over HTTP. The server keeps its own cache, so settings change only through this API."""
    from plans import catalog
    L = catalog.Limit
    c = httpx.Client(base_url="http://127.0.0.1:8765", timeout=60)
    db = __import__("pgcompat").get_db()
    made = make_admins(db, ("admin", "moderator", "super_admin"))
    AD = MOD = SUP = {}

    def restore():
        r = c.put("/api/admin/plans", headers=AD, json=default_body())
        return r.status_code == 200

    def put(body, h=None):
        return c.put("/api/admin/plans", headers=h or AD, json=body)

    def get(h=None):
        return c.get("/api/admin/plans", headers=h or MOD)

    try:
        AD, MOD, SUP = (admin_login(c, made[r]) for r in ("admin", "moderator", "super_admin"))
        check(restore(), "admin_plans: the defaults are restored through the admin API at the start")

        # --- admin_plans_get_defaults
        r = get()
        j = r.json() if r.status_code == 200 else {}
        want = default_body()
        shaped = (set(j) == {"plans", "upgrade_contact"} and set(j.get("plans", {})) == set(catalog.PLANS)
                  and all(set(v) == {"limits", "cost_cap_usd"} and set(v["limits"]) == set(catalog.FEATURES)
                          and all(set(x) == {"mode", "quota", "period"} for x in v["limits"].values())
                          for v in j.get("plans", {}).values()))
        check(r.status_code == 200 and shaped, "admin_plans_get_defaults: the moderator gets plans (3 x 8 limits + cost cap) and the upgrade contact",
              f"{r.status_code} {r.text[:300]}")
        check(j == want, "admin_plans_get_defaults: the values are the catalogue defaults and an empty contact",
              [(p, f) for p in catalog.PLANS for f in catalog.FEATURES
               if j.get("plans", {}).get(p, {}).get("limits", {}).get(f) != want["plans"][p]["limits"][f]][:4])
        check(isinstance(j["plans"]["free"]["cost_cap_usd"], float) and j["plans"]["plus"]["cost_cap_usd"] == 1.0
              and j["plans"]["free"]["cost_cap_usd"] == 0.1, "admin_plans_get_defaults: cost caps are numbers (0.1, 1.0, 3.0)",
              j["plans"]["free"]["cost_cap_usd"])
        r = c.get("/api/admin/plans")
        check(r.status_code in (401, 403), "admin_plans_auth: GET without a token is refused", r.status_code)
        r = c.put("/api/admin/plans", json=want)
        check(r.status_code in (401, 403), "admin_plans_auth: PUT without a token is refused", r.status_code)

        # --- admin_plans_put_applies
        body = default_body()
        body["plans"]["free"]["limits"]["chat"] = {"mode": "counted", "quota": 20, "period": "month"}
        body["plans"]["plus"]["cost_cap_usd"] = 1.25
        body["upgrade_contact"] = {"en": "Contact us on Viber", "my": "ဗိုင်ဘာမှာ ဆက်သွယ်ပါ"}
        r = put(body)
        check(r.status_code == 200 and r.json() == body, "admin_plans_put_applies: PUT returns the saved plans", f"{r.status_code} {r.text[:300]}")
        r = get()
        check(r.status_code == 200 and r.json() == body, "admin_plans_put_applies: GET now shows free chat 20/month, the new cap and the contact",
              r.json()["plans"]["free"]["limits"]["chat"])
        with connect() as conn:
            lim, caps, contact = stored_plans(conn)
        check(lim[("free", "chat")] == ("counted", 20, "month") and caps["plus"] == 1.25 and contact["upgrade_contact_en"] == "Contact us on Viber",
              "admin_plans_put_applies: the database holds the new values")
        r = put(body, SUP)
        check(r.status_code == 200, "admin_plans_put_applies: a super admin may change plans too", r.status_code)
        body["plans"]["pro"]["limits"]["chat_advanced"] = {"mode": "included", "quota": None, "period": None}
        body["plans"]["free"]["limits"]["insight_weekly"] = {"mode": "counted", "quota": 0, "period": "week"}
        r = put(body)
        check(r.status_code == 200 and get().json() == body, "admin_plans_put_applies: included and a counted quota of 0 are accepted")
        r = put({**body, "plans": {**body["plans"], "plus": {**body["plans"]["plus"], "cost_cap_usd": 2}}})
        check(r.status_code == 200 and get().json()["plans"]["plus"]["cost_cap_usd"] == 2.0,
              "admin_plans_put_applies: an integer cost cap is accepted")
        check(restore() and get().json() == default_body(), "admin_plans_put_applies: restoring the defaults puts everything back")

        # --- admin_plans_put_invalid_422
        import copy
        pre = get().json()

        def bad(label, mutate, expect=None):
            b = copy.deepcopy(default_body())
            mutate(b)
            r = put(b)
            detail = r.json().get("detail") if r.headers.get("content-type", "").startswith("application/json") else None
            text = detail if isinstance(detail, str) else str(detail)
            check(r.status_code == 422 and (expect is None or expect.lower() in text.lower()),
                  f"admin_plans_put_invalid_422: {label} gives 422" + (f" mentioning {expect!r}" if expect else ""),
                  f"{r.status_code} {r.text[:300]}")

        bad("a counted entry with no period", lambda b: b["plans"]["free"]["limits"]["chat"].update(period=None), "period")
        bad("a counted entry with no quota", lambda b: b["plans"]["free"]["limits"]["chat"].update(quota=None), "quota")
        bad("a negative quota", lambda b: b["plans"]["free"]["limits"]["chat"].update(quota=-3), "quota")
        bad("a locked entry with a quota", lambda b: b["plans"]["free"]["limits"]["reports"].update(quota=3), "reports")
        bad("an unknown period", lambda b: b["plans"]["free"]["limits"]["chat"].update(period="day"), "period")
        bad("an unknown mode", lambda b: b["plans"]["free"]["limits"]["chat"].update(mode="unlimited"), "mode")
        bad("a missing feature", lambda b: b["plans"]["plus"]["limits"].pop("entry"), "entry")
        bad("an unknown feature", lambda b: b["plans"]["plus"]["limits"].update(bogus={"mode": "locked", "quota": None, "period": None}), "bogus")
        bad("a missing plan", lambda b: b["plans"].pop("pro"), "pro")
        bad("an unknown plan", lambda b: b["plans"].update(gold=b["plans"]["pro"]), "gold")
        bad("chat_advanced on while chat is locked",
            lambda b: (b["plans"]["plus"]["limits"].update(chat={"mode": "locked", "quota": None, "period": None},
                                                           chat_advanced={"mode": "counted", "quota": 5, "period": "month"})), "chat_advanced")
        bad("a negative cost cap", lambda b: b["plans"]["pro"].update(cost_cap_usd=-1), "cost")
        bad("a text cost cap", lambda b: b["plans"]["pro"].update(cost_cap_usd="lots"))
        bad("an upgrade contact over 500 characters", lambda b: b["upgrade_contact"].update(en="x" * 501), "500")
        bad("a missing upgrade contact", lambda b: b.pop("upgrade_contact"))
        bad("an extra top-level field", lambda b: b.update(extra=1))
        r = c.put("/api/admin/plans", headers=AD, content=b"not json")
        check(r.status_code == 422, "admin_plans_put_invalid_422: a body that is not JSON gives 422", r.status_code)
        r = c.put("/api/admin/plans", headers=AD, content=b'{"plans": {"free": {"limits": {}, "cost_cap_usd": NaN}}, "upgrade_contact": {"en": "", "my": ""}}',
                  )
        check(r.status_code == 422, "admin_plans_put_invalid_422: a NaN cost cap gives 422, not a 500", r.status_code)
        check(get().json() == pre, "admin_plans_put_invalid_422: nothing was changed by the rejected requests")

        # --- admin_plans_moderator_read_only
        r = get(MOD)
        check(r.status_code == 200, "admin_plans_moderator_read_only: the moderator can GET", r.status_code)
        mb = default_body()
        mb["plans"]["free"]["limits"]["chat"]["quota"] = 77
        r = put(mb, MOD)
        check(r.status_code == 403, "admin_plans_moderator_read_only: the moderator cannot PUT", r.status_code)
        check(get().json()["plans"]["free"]["limits"]["chat"]["quota"] == 5, "admin_plans_moderator_read_only: the refused PUT changed nothing")

        # --- admin_plans_logged
        b = default_body()
        b["plans"]["free"]["limits"]["chat"] = {"mode": "counted", "quota": 21, "period": "week"}
        b["plans"]["pro"]["cost_cap_usd"] = 3.5
        b["upgrade_contact"]["en"] = "Ping us"
        r = put(b)
        r2 = c.get("/api/admin/logs", headers=SUP, params={"limit": 100})
        mine = [x for x in (r2.json() if r2.status_code == 200 else []) if x["admin_email"] == made["admin"]]
        upd = [x for x in mine if x["action"] == "plans_update"]
        details = upd[0].get("details") or "" if upd else ""
        check(r.status_code == 200 and len(upd) >= 1 and "free.chat" in details and "pro" in details and "contact" in details.lower(),
              "admin_plans_logged: the PUT is in the admin action logs, saying what changed", [x["action"] for x in mine][:6] or details)
        n = len(upd)
        mod_logs = [x for x in (c.get("/api/admin/logs", headers=SUP, params={"limit": 100}).json()) if x["admin_email"] == made["moderator"]]
        check(not any(x["action"] == "plans_update" for x in mod_logs), "admin_plans_logged: the moderator's refused PUT is not logged as an update")
        put(b)  # unchanged values: still a save, still logged
        r2 = c.get("/api/admin/logs", headers=SUP, params={"limit": 100})
        check(len([x for x in r2.json() if x["admin_email"] == made["admin"] and x["action"] == "plans_update"]) == n + 1,
              "admin_plans_logged: every accepted PUT writes one log entry")
        r = put({**b, "plans": {**b["plans"], "free": {**b["plans"]["free"], "cost_cap_usd": -1}}})
        r2 = c.get("/api/admin/logs", headers=SUP, params={"limit": 100})
        check(r.status_code == 422 and len([x for x in r2.json() if x["admin_email"] == made["admin"] and x["action"] == "plans_update"]) == n + 1,
              "admin_plans_logged: a rejected PUT is not logged")
    finally:
        try:
            ok = restore()
            check(ok and get(MOD).json() == default_body(), "admin_plans: the defaults are restored through the admin API at the end")
        finally:
            db.admins.delete_many({"email": {"$in": list(made.values())}})
            c.close()


async def plans_checks():
    """Task 2 and 3 checks under ONE event loop: the backend's async DB engine binds to the first loop it is used on."""
    from sql.db import dispose_engine
    import plans_chat_checks
    import plans_entry_checks
    import plans_insight_checks
    import plans_quota_checks
    import plans_subscription_checks
    import plans_upgrade_request_checks
    try:
        period_checks()
        await store_checks()
        api_checks()
        await plans_quota_checks.run(sys.modules[__name__])  # task 3: quota engine, cost cap, /api/plan
        await plans_subscription_checks.run(sys.modules[__name__])  # task 4: expiry, trial, reminders, admin usage controls
        await plans_chat_checks.run(sys.modules[__name__])  # task 5: chat quotas and Pro's Advanced chat
        await plans_entry_checks.run(sys.modules[__name__])  # task 6: entry, budget and report gates; voice counts once
        await plans_insight_checks.run(sys.modules[__name__])  # task 7: insights by plan; language chosen per request
        await plans_upgrade_request_checks.run(sys.modules[__name__])  # plan polish: upgrade requests; admin list shows the effective plan
    finally:
        await dispose_engine()


def main():
    schema_checks()
    catalog_checks()
    with connect() as conn:
        defaults_seeded(conn, "")
    migration_checks()
    behaviour_checks()
    asyncio.run(plans_checks())
    failed = results.count(False)
    print(f"\n{len(results) - failed}/{len(results)} passed", flush=True)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
