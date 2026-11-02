"""Plans and AI quotas, task 1: the Free/Plus/Pro schema, the plan catalogue and the premium -> plus migration.

Print-only suite: every check prints [PASS] or [BUG]; the exit code is non-zero if any check failed.

The migration checks run `alembic downgrade` / `alembic upgrade` on the throwaway e2e database (nothing else
runs at the same time: the backend suites run one after another) and always leave it at head again.
"""
import os
import subprocess
import sys
import uuid
from datetime import datetime, timedelta, UTC

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
            check(s.status_code == 200 and s.json().get("is_premium") == paid and s.json().get("subscription_type") == sub,
                  f"behaviour: subscription-status for {tag} says is_premium={paid}", s.text[:200])
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


def main():
    schema_checks()
    catalog_checks()
    with connect() as conn:
        defaults_seeded(conn, "")
    migration_checks()
    behaviour_checks()
    failed = results.count(False)
    print(f"\n{len(results) - failed}/{len(results)} passed", flush=True)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
