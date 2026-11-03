"""Plan-polish checks for test_plans: upgrade requests (the table and its migration, POST /api/plan/upgrade-request,
the `upgrade_request` field of GET /api/plan, the admin list / done / dismiss API, the automatic "done" when an admin sets
the plan, the dashboard count) and the admin users list showing the effective plan (an expired Plus reads Free).

Run from test_plans (inside its single asyncio.run): `await plans_upgrade_request_checks.run(test_plans_module)`.
Users are registered through the API; plans change only through the admin API (the DB is used to read results and to
back-date a plan's end). Everything the checks create is removed at the end.
"""
import re
import uuid
from datetime import datetime, timedelta, UTC

import httpx

BASE = "http://127.0.0.1:8765"
MYANMAR = re.compile("[က-႟]")
BEFORE_REQUESTS = "e1b6d3a8f245"  # the revision the upgrade_requests migration revises
REQUEST_KEYS = {"plan", "note", "status", "created_at"}
PLAN_REQUEST_KEYS = {"plan", "note", "created_at"}
ADMIN_ROW_KEYS = {"id", "user_id", "name", "email", "current_plan", "requested_plan", "note", "created_at", "status",
                  "handled_at"}


def parse(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00")) if isinstance(value, str) else value


async def run(t):
    """t: the test_plans module (check, connect, alembic, make_admins, admin_login, current_revision, table_names)."""
    check = t.check
    c = httpx.Client(base_url=BASE, timeout=60)
    db = __import__("pgcompat").get_db()
    made = t.make_admins(db, ("admin", "moderator", "super_admin"))
    AD = t.admin_login(c, made["admin"])
    MOD = t.admin_login(c, made["moderator"])
    SUP = t.admin_login(c, made["super_admin"])
    admin_id = db.admins.find_one({"email": made["admin"]})["_id"]
    super_id = db.admins.find_one({"email": made["super_admin"]})["_id"]
    tag = uuid.uuid4().hex[:5]

    def register(name, lang="en"):
        email = f"t8r-{name}-{tag}@example.com"
        c.post("/api/auth/register", json={"name": name, "email": email, "password": "secret123"})
        db.users.update_one({"email": email}, {"$set": {"is_verified": True, "language": lang}})
        token = c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json()["access_token"]
        return db.users.find_one({"email": email})["_id"], {"Authorization": f"Bearer {token}"}

    def set_plan(uid, plan, expires=None):
        body = {"subscription_type": plan}
        if expires is not None:
            body["subscription_expires_at"] = expires.isoformat()
        return c.put(f"/api/admin/users/{uid}/subscription", headers=AD, json=body).status_code == 200

    def ask(h, plan, note=None):
        body = {"plan": plan}
        if note is not None:
            body["note"] = note
        return c.post("/api/plan/upgrade-request", headers=h, json=body)

    def rows(uid):
        with t.connect() as conn:
            return conn.execute("SELECT id, plan, note, status, created_at, handled_at, handled_by FROM upgrade_requests "
                                "WHERE user_id = %s ORDER BY created_at", (uid,)).fetchall()

    def pending_count():
        with t.connect() as conn:
            return conn.execute("SELECT count(*) FROM upgrade_requests WHERE status = 'pending'").fetchone()[0]

    def admin_list(h, **params):
        return c.get("/api/admin/upgrade-requests", headers=h, params=params)

    def listed(h, uid, **params):
        """The admin list row for this user (or None)."""
        r = admin_list(h, **params)
        return next((x for x in (r.json() if r.status_code == 200 else []) if x["user_id"] == uid), None)

    def logs(email):
        r = c.get("/api/admin/logs", headers=SUP, params={"limit": 100})
        return [x for x in (r.json() if r.status_code == 200 else []) if x["admin_email"] == email]

    def plan_request(h):
        return c.get("/api/plan", headers=h).json().get("upgrade_request", "missing")

    try:
        # ---- migration up / down (leaves the database at head)
        with t.connect() as conn:
            check("upgrade_requests" in t.table_names(conn), "upgrade_requests_schema: the table exists at head")
            ok, out = t.alembic("downgrade", BEFORE_REQUESTS)
            check(ok and t.current_revision(conn) == BEFORE_REQUESTS and "upgrade_requests" not in t.table_names(conn),
                  "upgrade_requests_migration: downgrade drops the table", out)
            ok, out = t.alembic("upgrade", "head")
            check(ok and "upgrade_requests" in t.table_names(conn) and t.current_revision(conn) != BEFORE_REQUESTS,
                  "upgrade_requests_migration: upgrade creates it again", out)
            idx = {r[0] for r in conn.execute("SELECT indexname FROM pg_indexes WHERE tablename = 'upgrade_requests'")}
            check({"uq_upgrade_requests_pending_user", "ix_upgrade_requests_status_created",
                   "ix_upgrade_requests_user_id"} <= idx, "upgrade_requests_migration: the indexes are back", sorted(idx))

            # ---- constraints
            uid = "t8r-" + tag
            user = t.new_user(uid)
            ins = ("INSERT INTO upgrade_requests (id, user_id, plan, note, status) VALUES (%s, %s, %s, %s, %s)")
            check(t.accepted(conn, user, (ins, ("r1", uid, "plus", "hi", "pending"))),
                  "upgrade_requests_schema: accepts a pending Plus request with a note")
            check(not t.accepted(conn, user, (ins, ("r1", uid, "free", None, "pending"))),
                  "upgrade_requests_schema: rejects plan 'free'")
            check(not t.accepted(conn, user, (ins, ("r1", uid, "gold", None, "pending"))),
                  "upgrade_requests_schema: rejects an unknown plan")
            check(not t.accepted(conn, user, (ins, ("r1", uid, "plus", None, "approved"))),
                  "upgrade_requests_schema: rejects status 'approved'")
            check(t.accepted(conn, user, (ins, ("r1", uid, "pro", "x" * 500, "done"))),
                  "upgrade_requests_schema: accepts a note of 500 characters")
            check(not t.accepted(conn, user, (ins, ("r1", uid, "pro", "x" * 501, "done"))),
                  "upgrade_requests_schema: rejects a note of 501 characters")
            check(not t.accepted(conn, user, (ins, ("r1", uid, "plus", None, "pending")),
                                 (ins, ("r2", uid, "pro", None, "pending"))),
                  "upgrade_requests_schema: at most one pending request per user")
            check(t.accepted(conn, user, (ins, ("r1", uid, "plus", None, "done")), (ins, ("r2", uid, "plus", None, "done")),
                             (ins, ("r3", uid, "pro", None, "dismissed")), (ins, ("r4", uid, "pro", None, "pending"))),
                  "upgrade_requests_schema: handled requests pile up beside one pending")
            check(not t.accepted(conn, (ins, ("r1", "no-such-user", "plus", None, "pending"))),
                  "upgrade_requests_schema: rejects an unknown user (foreign key)")
            left = None
            try:
                with conn.transaction():
                    conn.execute(*user)
                    conn.execute(ins, ("r1", uid, "plus", None, "pending"))
                    conn.execute("DELETE FROM users WHERE id = %s", (uid,))
                    left = conn.execute("SELECT count(*) FROM upgrade_requests WHERE user_id = %s", (uid,)).fetchone()[0]
                    raise t.psycopg.Rollback()
            except t.psycopg.Error as e:
                left = repr(e)
            check(left == 0, "upgrade_requests_schema: deleting a user deletes its requests", left)

        # ---- create
        uid, h = register("free")
        check(plan_request(h) is None, "upgrade_request_field: GET /api/plan has upgrade_request null before any request",
              plan_request(h))
        before = datetime.now(UTC)
        r = ask(h, "plus", "  Please upgrade me  ")
        j = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and set(j) == REQUEST_KEYS and j["plan"] == "plus" and j["status"] == "pending"
              and j["note"] == "Please upgrade me" and parse(j["created_at"]) >= before - timedelta(seconds=2),
              "upgrade_request_create: 200 {plan, note, status, created_at}; the note is stripped", f"{r.status_code} {r.text[:200]}")
        got = plan_request(h)
        check(isinstance(got, dict) and set(got) == PLAN_REQUEST_KEYS and got["plan"] == "plus"
              and got["note"] == "Please upgrade me" and got["created_at"] == j.get("created_at"),
              "upgrade_request_field: GET /api/plan shows {plan, note, created_at} of the pending request", got)
        other_uid, other_h = register("other")
        check(plan_request(other_h) is None, "upgrade_request_field: another user's GET /api/plan stays null")
        check(len(rows(uid)) == 1 and rows(uid)[0][3] == "pending", "upgrade_request_create: one pending row")

        # ---- update in place
        first_id, first_at = rows(uid)[0][0], rows(uid)[0][4]
        r = ask(h, "pro", "Actually Pro")
        j = r.json() if r.status_code == 200 else {}
        now_rows = rows(uid)
        check(r.status_code == 200 and j.get("plan") == "pro" and j.get("note") == "Actually Pro" and len(now_rows) == 1
              and now_rows[0][0] == first_id and now_rows[0][1] == "pro" and now_rows[0][4] > first_at,
              "upgrade_request_update: a second request replaces plan, note and date of the pending row (no new row)",
              f"{r.status_code} {r.text[:200]} {now_rows}")
        r = ask(h, "plus", "   ")
        check(r.status_code == 200 and r.json().get("note") is None and rows(uid)[0][2] is None and len(rows(uid)) == 1,
              "upgrade_request_update: a blank note becomes null (and clears the old one)", f"{r.status_code} {r.text[:200]}")
        r = ask(h, "plus")
        check(r.status_code == 200 and r.json().get("note") is None, "upgrade_request_update: no note field is fine")
        check(ask(h, "plus", "x" * 500).status_code == 200, "upgrade_request_create: a note of 500 characters is accepted")
        check(ask(h, "plus", "  " + "x" * 500 + "  ").status_code == 200,
              "upgrade_request_create: the 500-character limit counts the stripped note")
        ask(h, "plus")  # back to no note for the checks below

        # ---- validation
        for label, body, want in (
            ("plan free", {"plan": "free"}, 422), ("plan gold", {"plan": "gold"}, 422), ("no plan", {"note": "x"}, 422),
            ("a note over 500 characters", {"plan": "plus", "note": "x" * 501}, 422),
            ("a non-text note", {"plan": "plus", "note": 5}, 422), ("an unknown field", {"plan": "plus", "x": 1}, 422),
        ):
            r = c.post("/api/plan/upgrade-request", headers=h, json=body)
            check(r.status_code == want, f"upgrade_request_validation: {label} -> {want}", f"{r.status_code} {r.text[:150]}")
        check(len(rows(uid)) == 1, "upgrade_request_validation: refused requests added no rows")
        r = c.post("/api/plan/upgrade-request", json={"plan": "plus"})
        check(r.status_code in (401, 403), "upgrade_request_validation: no token is refused", r.status_code)

        # ---- already on that plan or higher
        plus_uid, plus_h = register("plus")
        pro_uid, pro_h = register("pro", "my")
        set_plan(plus_uid, "plus", datetime.now(UTC) + timedelta(days=10))
        set_plan(pro_uid, "pro")
        r = ask(plus_h, "plus")
        check(r.status_code == 400 and isinstance(r.json().get("detail"), str) and "Plus" in r.json()["detail"],
              "upgrade_request_refused: a Plus user asking for Plus gets 400 with a readable message", f"{r.status_code} {r.text[:200]}")
        check(ask(plus_h, "pro").status_code == 200, "upgrade_request_refused: a Plus user may ask for Pro")
        r = ask(pro_h, "plus")
        check(r.status_code == 400 and MYANMAR.search(r.json().get("detail", "")),
              "upgrade_request_refused: a Pro user asking for Plus gets 400, in their language (Myanmar)", f"{r.status_code} {r.text[:200]}")
        check(ask(pro_h, "pro").status_code == 400, "upgrade_request_refused: a Pro user asking for Pro gets 400")
        check(not rows(pro_uid), "upgrade_request_refused: refused requests added no rows (Pro user)")
        exp_uid, exp_h = register("expired")
        db.users.update_one({"_id": exp_uid}, {"$set": {"subscription_type": "plus",
                                                        "subscription_expires_at": datetime.now(UTC) - timedelta(days=1)}})
        check(ask(exp_h, "plus").status_code == 200,
              "upgrade_request_refused: an expired Plus counts as Free, so asking for Plus is fine")

        # ---- admin list
        row = listed(MOD, uid)
        check(row is not None and set(row) == ADMIN_ROW_KEYS and row["name"] == "free" and row["email"] == f"t8r-free-{tag}@example.com"
              and row["current_plan"] == "free" and row["requested_plan"] == "plus" and row["status"] == "pending"
              and row["handled_at"] is None and row["note"] is None,
              "admin_requests_list: the moderator sees the pending request with user, current plan, requested plan, note", row)
        row = listed(MOD, plus_uid)
        check(row is not None and row["current_plan"] == "plus" and row["requested_plan"] == "pro",
              "admin_requests_list: current_plan is the user's plan now (Plus asking for Pro)", row)
        row = listed(MOD, exp_uid)
        check(row is not None and row["current_plan"] == "free",
              "admin_requests_list: an expired Plus shows as Free", row)
        check(listed(AD, uid) is not None and listed(SUP, uid) is not None, "admin_requests_list: admins see it too")
        check(listed(MOD, uid, status="done") is None and listed(MOD, uid, status="dismissed") is None,
              "admin_requests_list: a pending request is not in the done / dismissed lists")
        check(listed(MOD, uid, status="pending") is not None, "admin_requests_list: status=pending is the default list")
        check(admin_list(MOD, status="bogus").status_code == 422, "admin_requests_list: an unknown status is a 422")
        check(c.get("/api/admin/upgrade-requests").status_code in (401, 403), "admin_requests_list: no token is refused")
        check(c.get("/api/admin/upgrade-requests", headers=plus_h).status_code in (401, 403),
              "admin_requests_list: a user token is refused")
        check(admin_list(MOD, limit=0).status_code == 422 and admin_list(MOD, skip=-1).status_code == 422,
              "admin_requests_list: skip / limit are validated")
        page = admin_list(MOD, limit=1).json()
        check(len(page) == 1, "admin_requests_list: limit pages the list", page)

        # ---- dismiss / done: roles, 404, 409, log
        request_id = listed(MOD, uid)["id"]
        for action in ("done", "dismiss"):
            r = c.post(f"/api/admin/upgrade-requests/{request_id}/{action}", headers=MOD)
            check(r.status_code == 403, f"admin_requests_{action}: a moderator gets 403", r.status_code)
            check(c.post(f"/api/admin/upgrade-requests/{request_id}/{action}").status_code in (401, 403),
                  f"admin_requests_{action}: no token is refused")
            check(c.post(f"/api/admin/upgrade-requests/{request_id}/{action}", headers=plus_h).status_code in (401, 403),
                  f"admin_requests_{action}: a user token is refused")
        check(rows(uid)[0][3] == "pending", "admin_requests: refused calls changed nothing")
        r = c.post(f"/api/admin/upgrade-requests/{uuid.uuid4()}/dismiss", headers=AD)
        check(r.status_code == 404, "admin_requests_dismiss: an unknown id is 404", r.status_code)
        r = c.post(f"/api/admin/upgrade-requests/{uuid.uuid4()}/done", headers=AD)
        check(r.status_code == 404, "admin_requests_done: an unknown id is 404", r.status_code)

        r = c.post(f"/api/admin/upgrade-requests/{request_id}/dismiss", headers=AD)
        j = r.json() if r.status_code == 200 else {}
        got = rows(uid)[0]
        check(r.status_code == 200 and j.get("status") == "dismissed" and got[3] == "dismissed" and got[5] is not None
              and got[6] == admin_id, "admin_requests_dismiss: an admin dismisses it (status, handled_at, handled_by)",
              f"{r.status_code} {r.text[:200]} {got}")
        for action in ("done", "dismiss"):
            r = c.post(f"/api/admin/upgrade-requests/{request_id}/{action}", headers=SUP)
            check(r.status_code == 409, f"admin_requests_{action}: a request that is not pending is 409", r.status_code)
        check(rows(uid)[0][3] == "dismissed" and rows(uid)[0][6] == admin_id,
              "admin_requests: a 409 leaves the first decision alone")
        row = listed(MOD, uid, status="dismissed")
        check(row is not None and row["status"] == "dismissed" and row["handled_at"] is not None,
              "admin_requests_list: it now shows under status=dismissed", row)
        check(listed(MOD, uid) is None, "admin_requests_list: and is gone from the pending list")
        check(plan_request(h) is None, "upgrade_request_field: GET /api/plan is null again after a dismissal")
        got = [x for x in logs(made["admin"]) if x["action"] == "upgrade_request_dismissed" and x["target_user_id"] == uid]
        check(len(got) == 1 and got[0]["target_user_email"] == f"t8r-free-{tag}@example.com",
              "admin_requests_dismiss: written to the admin log", got)

        r = ask(h, "pro", "again")
        check(r.status_code == 200 and len(rows(uid)) == 2 and rows(uid)[1][3] == "pending" and rows(uid)[0][3] == "dismissed",
              "upgrade_request_create: after a dismissal a new request is a new pending row (history kept)")
        request_id = listed(MOD, uid)["id"]
        r = c.post(f"/api/admin/upgrade-requests/{request_id}/done", headers=SUP)
        got = rows(uid)[1]
        check(r.status_code == 200 and r.json().get("status") == "done" and got[3] == "done" and got[6] == super_id,
              "admin_requests_done: a super admin marks it done", f"{r.status_code} {r.text[:200]} {got}")
        check(listed(MOD, uid, status="done") is not None, "admin_requests_list: it shows under status=done")
        got = [x for x in logs(made["super_admin"]) if x["action"] == "upgrade_request_done" and x["target_user_id"] == uid]
        check(len(got) == 1, "admin_requests_done: written to the admin log", got)

        # ---- the admin changing the plan answers the request
        def pending_for(label):
            u, hh = register(label)
            return u, hh

        a_uid, a_h = pending_for("auto-plus")
        ask(a_h, "plus", "n")
        check(set_plan(a_uid, "plus", datetime.now(UTC) + timedelta(days=30)), "setup: set Plus")
        got = rows(a_uid)[0]
        check(got[3] == "done" and got[6] == admin_id and got[5] is not None and plan_request(a_h) is None,
              "auto_done: setting the requested plan marks the pending request done (handled_by the admin)", got)

        b_uid, b_h = pending_for("auto-pro")
        ask(b_h, "plus")
        set_plan(b_uid, "pro", datetime.now(UTC) + timedelta(days=30))
        check(rows(b_uid)[0][3] == "done", "auto_done: a higher plan than requested also answers it")

        d_uid, d_h = pending_for("auto-lower")
        ask(d_h, "pro")
        set_plan(d_uid, "plus", datetime.now(UTC) + timedelta(days=30))
        check(rows(d_uid)[0][3] == "pending" and isinstance(plan_request(d_h), dict),
              "auto_done: a lower plan than requested leaves the request pending")
        set_plan(d_uid, "pro", datetime.now(UTC) + timedelta(days=30))
        check(rows(d_uid)[0][3] == "done", "auto_done: and the requested plan later answers it")

        e_uid, e_h = pending_for("auto-free")
        ask(e_h, "plus")
        set_plan(e_uid, "free")
        check(rows(e_uid)[0][3] == "pending", "auto_done: setting Free does not answer a request")

        f_uid, f_h = pending_for("auto-past")
        ask(f_h, "plus")
        set_plan(f_uid, "plus", datetime.now(UTC) - timedelta(days=1))
        check(rows(f_uid)[0][3] == "pending", "auto_done: a plan that has already ended does not answer a request")

        g_uid, g_h = pending_for("auto-none")
        check(set_plan(g_uid, "plus", datetime.now(UTC) + timedelta(days=5)) and not rows(g_uid),
              "auto_done: setting a plan for a user without a request is fine")

        # ---- dashboard count
        stats = c.get("/api/admin/stats/system", headers=MOD).json()
        check(stats.get("pending_upgrade_requests") == pending_count() and pending_count() >= 3,
              "admin_requests_stats: /api/admin/stats/system has pending_upgrade_requests (the pending rows)",
              f"{stats.get('pending_upgrade_requests')} vs {pending_count()}")
        before_count = stats["pending_upgrade_requests"]
        c.post(f"/api/admin/upgrade-requests/{listed(MOD, e_uid)['id']}/dismiss", headers=AD)
        check(c.get("/api/admin/stats/system", headers=MOD).json().get("pending_upgrade_requests") == before_count - 1,
              "admin_requests_stats: the count drops when a request is handled")

        # ---- deleting a user removes its requests
        check(rows(d_uid) and c.delete(f"/api/admin/users/{d_uid}", headers=SUP).status_code == 200 and not rows(d_uid),
              "admin_requests_cascade: deleting a user through the admin API deletes its requests")

        # ---- admin users list shows the effective plan (item 7)
        def user_row(h, uid_, **params):
            r = c.get("/api/admin/users", headers=h, params={"search": f"-{tag}@", "limit": 100, **params})
            return next((x for x in (r.json() if r.status_code == 200 else []) if x["id"] == uid_), None)

        expired = user_row(MOD, exp_uid)
        check(expired is not None and expired["subscription_type"] == "plus" and expired["effective_plan"] == "free",
              "admin_users_effective_plan: an expired Plus lists effective_plan 'free' and keeps the stored 'plus'", expired)
        live = user_row(MOD, plus_uid)
        check(live is not None and live["subscription_type"] == "plus" and live["effective_plan"] == "plus",
              "admin_users_effective_plan: a live Plus lists 'plus' for both", live)
        lifetime = user_row(MOD, pro_uid)
        check(lifetime is not None and lifetime["effective_plan"] == "pro" and lifetime["subscription_expires_at"] is None,
              "admin_users_effective_plan: a lifetime Pro lists 'pro'", lifetime)
        fresh = user_row(MOD, other_uid)
        check(fresh is not None and fresh["effective_plan"] == "free" and fresh["subscription_type"] == "free",
              "admin_users_effective_plan: a Free user lists 'free'", fresh)
        check(user_row(MOD, exp_uid, subscription_type="free") is not None
              and user_row(MOD, exp_uid, subscription_type="plus") is None,
              "admin_users_effective_plan: the plan filter uses the plan now (expired Plus is under Free, not Plus)")
        check(user_row(MOD, plus_uid, subscription_type="plus") is not None and user_row(MOD, plus_uid, subscription_type="free") is None
              and user_row(MOD, pro_uid, subscription_type="pro") is not None and user_row(MOD, pro_uid, subscription_type="plus") is None,
              "admin_users_effective_plan: the plan filter finds live Plus and Pro")
        detail = c.get(f"/api/admin/users/{exp_uid}", headers=MOD).json()
        check(detail.get("effective_plan") == "free" and detail.get("subscription_type") == "plus",
              "admin_users_effective_plan: the user detail has effective_plan too", detail)
    finally:
        db.users.delete_many({"email": {"$regex": f"^t8r-.*-{tag}@"}})
        db.admins.delete_many({"email": {"$in": list(made.values())}})
        c.close()
