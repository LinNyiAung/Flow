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
BEFORE_VIBER = "f2c9a47e5b18"  # the revision the viber_number migration revises
REQUEST_KEYS = {"plan", "note", "viber_number", "status", "created_at"}
PLAN_REQUEST_KEYS = {"plan", "note", "viber_number", "created_at"}
ADMIN_ROW_KEYS = {"id", "user_id", "name", "email", "current_plan", "is_trial", "trial_ends_at", "requested_plan", "note",
                  "viber_number", "created_at", "status", "handled_at"}
OWNER_EMAIL, OWNER_VIBER = "owner@example.com", "+959123456789"


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
    saved_contact = None
    saved_owner = None

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

    def ask(h, plan, note=None, **more):
        body = {"plan": plan, **more}
        if note is not None:
            body["note"] = note
        return c.post("/api/plan/upgrade-request", headers=h, json=body)

    def rows(uid):
        """(id, plan, note, status, created_at, handled_at, handled_by, viber_number) of the user's requests."""
        with t.connect() as conn:
            return conn.execute("SELECT id, plan, note, status, created_at, handled_at, handled_by, viber_number "
                                "FROM upgrade_requests "
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

            def viber_column():
                return conn.execute("SELECT data_type, is_nullable FROM information_schema.columns "
                                    "WHERE table_name = 'upgrade_requests' AND column_name = 'viber_number'").fetchone()

            check(viber_column() == ("text", "YES"), "upgrade_requests_viber_migration: head has a nullable text viber_number",
                  viber_column())
            ok, out = t.alembic("downgrade", BEFORE_VIBER)
            check(ok and t.current_revision(conn) == BEFORE_VIBER and viber_column() is None
                  and "upgrade_requests" in t.table_names(conn),
                  "upgrade_requests_viber_migration: downgrade drops only the column (the table stays)", out)
            ok, out = t.alembic("upgrade", "head")
            check(ok and viber_column() == ("text", "YES") and t.current_revision(conn) != BEFORE_VIBER,
                  "upgrade_requests_viber_migration: upgrade adds it again", out)

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
        # The limit is 500 Unicode code points (what the app counts too). A Burmese note has far fewer grapheme
        # clusters than code points: 62 x 8 = 496 and 62.5 x 8 = 500 are fine, 70 x 8 = 560 is not.
        burmese = "ကျွန်ုပ်"
        check(len(burmese) == 8 and ask(h, "plus", burmese * 62 + burmese[:4]).status_code == 200
              and len(rows(uid)[0][2]) == 500,
              "upgrade_request_create: a Burmese note of exactly 500 code points is accepted and stored")
        r = ask(h, "plus", burmese * 70)
        check(r.status_code == 422 and rows(uid)[0][2] == burmese * 62 + burmese[:4],
              "upgrade_request_create: a Burmese note of 560 code points is refused (422) and changes nothing",
              f"{r.status_code} {r.text[:150]}")
        check(ask(h, "plus", burmese * 62 + burmese[:5]).status_code == 422,
              "upgrade_request_create: and 501 Burmese code points is refused")
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

        # ---- the user's Viber number
        check(rows(uid)[0][7] is None and plan_request(h)["viber_number"] is None,
              "upgrade_request_viber: a request without a number stores null, and GET /api/plan shows null")
        for given, want in (("+959123456789", "+959123456789"), ("09 123 456 789", "+959123456789"),
                            ("09-123-456-789", "+959123456789"), ("(09) 123.456.789", "+959123456789"),
                            ("  09123456789  ", "+959123456789"), ("09\u00a0123\u00a0456\u00a0789", "+959123456789"),
                            ("+66 81 234 5678", "+66812345678"), ("+1 (555) 123-4567", "+15551234567"),
                            ("+12345678", "+12345678"), ("+123456789012345", "+123456789012345")):
            r = ask(h, "plus", viber_number=given)
            j = r.json() if r.status_code == 200 else {}
            check(r.status_code == 200 and set(j) == REQUEST_KEYS and j["viber_number"] == want
                  and rows(uid)[0][7] == want and len(rows(uid)) == 1,
                  f"upgrade_request_viber: {given!r} is stored as {want}", f"{r.status_code} {r.text[:150]} {rows(uid)}")
        check(plan_request(h)["viber_number"] == "+123456789012345",
              "upgrade_request_viber: GET /api/plan shows the number of the pending request")
        first_id = rows(uid)[0][0]
        ask(h, "plus", viber_number="09 123 456 789")
        r = ask(h, "pro", "other plan", viber_number="+66 81 234 5678")
        check(r.status_code == 200 and r.json()["viber_number"] == "+66812345678" and len(rows(uid)) == 1
              and rows(uid)[0][0] == first_id and rows(uid)[0][7] == "+66812345678" and rows(uid)[0][1] == "pro",
              "upgrade_request_viber: a new request replaces the number of the pending one in place (like the note)",
              f"{r.status_code} {r.text[:150]} {rows(uid)}")
        for label, body in (("an empty string", {"viber_number": ""}), ("blanks and dashes", {"viber_number": " - "}),
                            ("null", {"viber_number": None}), ("no viber_number field", {})):
            ask(h, "plus", viber_number="09 123 456 789")
            r = c.post("/api/plan/upgrade-request", headers=h, json={"plan": "plus", **body})
            check(r.status_code == 200 and r.json()["viber_number"] is None and rows(uid)[0][7] is None and len(rows(uid)) == 1,
                  f"upgrade_request_viber: {label} clears the number (null)", f"{r.status_code} {r.text[:150]} {rows(uid)}")
        ask(h, "plus", viber_number="09 123 456 789")
        for label, given in (("letters", "abc"), ("too short", "12345"), ("only a plus", "+"), ("7 digits", "+1234567"),
                             ("16 digits", "+1234567890123456"), ("a local number with 0 but short", "0912"),
                             ("no plus (959…)", "959123456789"), ("a local non-09 number", "01 234 5678"),
                             ("two plus signs", "++959123456789"), ("a trailing plus", "+959123456789+"),
                             ("a plus in the middle", "+95+9123456789"), ("text after the number", "09 123 456 789 ext 2"),
                             ("Burmese digits", "၀၉၁၂၃၄၅၆၇၈၉"), ("a number as a JSON number", 959123456789)):
            r = c.post("/api/plan/upgrade-request", headers=h, json={"plan": "plus", "viber_number": given})
            check(r.status_code == 422 and (not isinstance(given, str) or "Viber" in r.text)
                  and rows(uid)[0][7] == "+959123456789" and len(rows(uid)) == 1,
                  f"upgrade_request_viber: {label} is refused (422, readable) and changes nothing",
                  f"{r.status_code} {r.text[:200]}")
        ask(h, "plus")  # back to no number and no note for the checks below

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
        trial_uid, trial_h = register("trial")
        trial_ends = datetime.now(UTC) + timedelta(days=10)
        db.users.update_one({"_id": trial_uid}, {"$set": {"subscription_type": "plus", "subscription_expires_at": trial_ends,
                                                         "trial_ends_at": trial_ends, "has_claimed_free_trial": True}})
        r = ask(trial_h, "plus", "keep it")
        check(r.status_code == 200 and r.json().get("plan") == "plus",
              "upgrade_request_trial: a user on the Plus trial may ask for Plus (the trial is not 'already on Plus')",
              f"{r.status_code} {r.text[:200]}")
        row = listed(MOD, trial_uid)
        check(row is not None and row["current_plan"] == "plus" and row["is_trial"] is True and row["requested_plan"] == "plus",
              "upgrade_request_trial: the admin list marks the trial user (is_trial true, current plan plus)", row)
        check(row is not None and row["trial_ends_at"] is not None
              and abs((parse(row["trial_ends_at"]) - trial_ends).total_seconds()) < 1,
              "upgrade_request_trial: the row carries trial_ends_at, the end of the trial (the admin panel shows it)", row)
        check(ask(trial_h, "pro").status_code == 200, "upgrade_request_trial: a trial user may ask for Pro too")
        check((c.get("/api/plan", headers=trial_h).json().get("upgrade_request") or {}).get("plan") == "pro",
              "upgrade_request_trial: the request stays pending while the trial runs (a trial does not fulfil it)")
        check(listed(MOD, plus_uid)["is_trial"] is False and listed(MOD, exp_uid)["is_trial"] is False,
              "upgrade_request_trial: users who are not on a trial are not marked")
        check(listed(MOD, plus_uid)["trial_ends_at"] is None and listed(MOD, exp_uid)["trial_ends_at"] is None,
              "upgrade_request_trial: and have trial_ends_at null")
        db.users.update_one({"_id": exp_uid}, {"$set": {"trial_ends_at": datetime.now(UTC) - timedelta(days=3)}})
        check(listed(MOD, exp_uid)["trial_ends_at"] is None and listed(MOD, exp_uid)["is_trial"] is False,
              "upgrade_request_trial: a trial that has ended leaves trial_ends_at null (nothing to show)")
        trial_auto = set_plan(trial_uid, "plus", datetime.now(UTC) + timedelta(days=30))
        check(trial_auto and rows(trial_uid)[0][3] == "pending",
              "upgrade_request_trial: the admin setting Plus does not answer the user's request for Pro")

        # ---- admin list
        row = listed(MOD, uid)
        check(row is not None and set(row) == ADMIN_ROW_KEYS and row["name"] == "free" and row["email"] == f"t8r-free-{tag}@example.com"
              and row["current_plan"] == "free" and row["requested_plan"] == "plus" and row["status"] == "pending"
              and row["handled_at"] is None and row["note"] is None and row["viber_number"] is None,
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
        ask(h, "plus", viber_number="09 123 456 789")
        row = listed(MOD, uid)
        check(row is not None and row["viber_number"] == "+959123456789" and row["email"] == f"t8r-free-{tag}@example.com",
              "admin_requests_list: a row carries the user's Viber number (the owner contacts them there) next to the email", row)
        check(listed(AD, uid)["viber_number"] == "+959123456789" and listed(SUP, uid)["viber_number"] == "+959123456789",
              "admin_requests_list: admins see the number too")
        row = listed(MOD, plus_uid)
        check(row is not None and row["viber_number"] is None,
              "admin_requests_list: a request without a number has viber_number null (contact by the account email)", row)
        ask(h, "plus")
        check(listed(MOD, uid)["viber_number"] is None, "admin_requests_list: a later request without a number clears it")

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
        got = [x for x in logs(made["admin"]) if x["action"] == "upgrade_request_done" and x["target_user_id"] == a_uid]
        check(len(got) == 1, "auto_done: the automatic close is written to the admin log like a manual one", got)

        b_uid, b_h = pending_for("auto-pro")
        ask(b_h, "plus")
        set_plan(b_uid, "pro", datetime.now(UTC) + timedelta(days=30))
        check(rows(b_uid)[0][3] == "done", "auto_done: a higher plan than requested also answers it")

        d_uid, d_h = pending_for("auto-lower")
        ask(d_h, "pro")
        set_plan(d_uid, "plus", datetime.now(UTC) + timedelta(days=30))
        check(rows(d_uid)[0][3] == "pending" and isinstance(plan_request(d_h), dict),
              "auto_done: a lower plan than requested (Pro asked, Plus set) leaves the request pending")
        check(not [x for x in logs(made["admin"]) if x["action"] == "upgrade_request_done" and x["target_user_id"] == d_uid],
              "auto_done: and writes no 'request done' log row")
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

        # ---- tell the user what happened: plan_activated and upgrade_request_declined notifications
        from plans.access import MONTHS_MY, format_date

        def notes(user_id, *types):
            found = db.notifications.find({"user_id": user_id, "type": {"$in": list(types)}})
            return sorted(found, key=lambda n: n["created_at"])

        def request_for(label, plan="plus", lang="en"):
            u, hh = register(label, lang)
            ask(hh, plan)
            return u, hh

        def plan_of(user_id):
            with t.connect() as conn:
                return conn.execute("SELECT subscription_type FROM users WHERE id = %s", (user_id,)).fetchone()[0]

        def put_contact(en, my):
            snap = c.get("/api/admin/plans", headers=AD).json()
            snap["upgrade_contact"] = {"en": en, "my": my}
            return c.put("/api/admin/plans", headers=AD, json=snap).status_code == 200

        def dismiss(user_id):
            return c.post(f"/api/admin/upgrade-requests/{listed(MOD, user_id)['id']}/dismiss", headers=AD).status_code

        ends = datetime(2099, 3, 5, 12, 0, tzinfo=UTC)

        # plan_activated: Plus with an end date, with a pending request (which the change also closes)
        n_uid, n_h = request_for("act-plus")
        check(set_plan(n_uid, "plus", ends), "setup: set Plus with an end date")
        got = notes(n_uid, "plan_activated")
        check(len(got) == 1 and got[0]["message"] == f"Your Plus plan is now active. It runs until {format_date(ends, 'en')}."
              and "Plus" in got[0]["title"] and got[0]["is_read"] is False,
              "plan_activated: Plus with an end date tells the user it is active and until when (English)", got)
        check(rows(n_uid)[0][3] == "done" and not notes(n_uid, "upgrade_request_declined"),
              "plan_activated: the request is closed by the change and the user is not told it was declined")
        # without a request, Pro for life: no end-date sentence
        p_uid, _ = register("act-pro")
        check(set_plan(p_uid, "pro"), "setup: set Pro for life")
        got = notes(p_uid, "plan_activated")
        check(len(got) == 1 and got[0]["message"] == "Your Pro plan is now active." and "Pro" in got[0]["title"],
              "plan_activated: Pro without a request and without an end date has no 'runs until' sentence", got)
        # Pro for a period, without a request; Plus for life, with a pending request for Pro (stays pending)
        q_uid, _ = register("act-pro-dated")
        set_plan(q_uid, "pro", ends)
        got = notes(q_uid, "plan_activated")
        check(len(got) == 1 and got[0]["message"] == f"Your Pro plan is now active. It runs until {format_date(ends, 'en')}.",
              "plan_activated: Pro with an end date, without a request", got)
        r_uid, _ = request_for("act-plus-life", "pro")
        set_plan(r_uid, "plus")
        got = notes(r_uid, "plan_activated")
        check(len(got) == 1 and got[0]["message"] == "Your Plus plan is now active." and rows(r_uid)[0][3] == "pending",
              "plan_activated: Plus for life while Pro is requested: told about Plus, the Pro request stays pending", got)
        # a new end date is a change and sends one; saving the same plan and end date again sends nothing
        set_plan(r_uid, "plus", ends)
        check(len(notes(r_uid, "plan_activated")) == 2, "plan_activated: setting Plus again with a new end date sends one")
        set_plan(r_uid, "plus", ends)
        check(len(notes(r_uid, "plan_activated")) == 2, "plan_activated: re-saving the same plan and end date sends nothing")
        # Myanmar user: Myanmar text with the Burmese month name
        m_uid, _ = request_for("act-my", "plus", "my")
        set_plan(m_uid, "plus", ends)
        got = notes(m_uid, "plan_activated")
        check(len(got) == 1 and MYANMAR.search(got[0]["title"]) and MYANMAR.search(got[0]["message"])
              and format_date(ends, "my") in got[0]["message"] and MONTHS_MY[2] in got[0]["message"]
              and "Plus" in got[0]["message"] and "now active" not in got[0]["message"],
              "plan_activated: a Myanmar user gets Myanmar text with the Burmese month name", got)
        m2_uid, _ = register("act-my-life", "my")
        set_plan(m2_uid, "pro")
        got = notes(m2_uid, "plan_activated")
        check(len(got) == 1 and MYANMAR.search(got[0]["message"]) and "Pro" in got[0]["message"]
              and not any(month in got[0]["message"] for month in MONTHS_MY),
              "plan_activated: a Myanmar user on a plan without an end date gets no date", got)
        # nothing for Free, nothing for a plan that has already ended
        z_uid, _ = request_for("act-free")
        set_plan(z_uid, "free")
        check(not notes(z_uid, "plan_activated", "upgrade_request_declined"), "plan_activated: setting Free sends nothing")
        y_uid, _ = register("act-past")
        set_plan(y_uid, "plus", datetime.now(UTC) - timedelta(days=1))
        check(not notes(y_uid, "plan_activated"), "plan_activated: a plan that has already ended is not 'now active': nothing sent")
        # a trial user whose plan the admin sets
        tr_uid, _ = register("act-trial")
        db.users.update_one({"_id": tr_uid}, {"$set": {"subscription_type": "plus", "trial_ends_at": trial_ends,
                                                       "subscription_expires_at": trial_ends}})
        set_plan(tr_uid, "pro", ends)
        check(len(notes(tr_uid, "plan_activated")) == 1, "plan_activated: a trial user whose plan the admin sets is told too")
        # like the trial reminders, the notice goes through create_notification: an explicit preference of "off" is honoured
        pr_uid, pr_h = register("act-pref")
        r = c.put("/api/notifications/preferences", headers=pr_h, json={"preferences": {"plan_activated": False}})
        set_plan(pr_uid, "plus", ends)
        check(r.status_code == 200 and not notes(pr_uid, "plan_activated") and plan_of(pr_uid) == "plus",
              "plan_activated: a user whose stored preference for it is off is not notified (the plan still changes)",
              f"{r.status_code} {r.text[:150]}")

        # ---- the owner's own email and Viber number (plan settings)
        snap0 = c.get("/api/admin/plans", headers=AD).json()
        saved_contact, saved_owner = snap0["upgrade_contact"], snap0["owner_contact"]

        def put_owner(email, viber, h_=AD, **over):
            """PUT the whole settings with this owner contact (the rest as it is now)."""
            snap = c.get("/api/admin/plans", headers=AD).json()
            snap["owner_contact"] = {"email": email, "viber": viber}
            snap.update(over)
            return c.put("/api/admin/plans", headers=h_, json=snap)

        def stored_owner():
            with t.connect() as conn:
                return {r[0]: r[1] for r in conn.execute(
                    "SELECT key, value FROM app_settings WHERE key IN ('contact_email', 'contact_viber')")}

        check(put_owner("", "").status_code == 200, "setup: clear the owner's email and Viber number")
        check(c.get("/api/admin/plans", headers=MOD).json()["owner_contact"] == {"email": "", "viber": ""}
              and c.get("/api/plan", headers=h).json()["owner_contact"] == {"email": "", "viber": ""},
              "owner_contact: nothing is set by default: empty strings in the admin API and in GET /api/plan")
        r = put_owner(" " + OWNER_EMAIL + " ", "09 123 456 789")
        want = {"email": OWNER_EMAIL, "viber": OWNER_VIBER}
        check(r.status_code == 200 and r.json()["owner_contact"] == want,
              "owner_contact_save: an admin saves them; the answer shows the stripped email and the normalised number "
              "(09… -> +959…)", f"{r.status_code} {r.text[-200:]}")
        check(c.get("/api/admin/plans", headers=MOD).json()["owner_contact"] == want
              and stored_owner() == {"contact_email": OWNER_EMAIL, "contact_viber": OWNER_VIBER},
              "owner_contact_save: a moderator reads them; app_settings holds contact_email and contact_viber")
        check(c.get("/api/plan", headers=h).json()["owner_contact"] == want
              and c.get("/api/plan", headers=plus_h).json()["owner_contact"] == want
              and c.get("/api/plan", headers=pro_h).json()["owner_contact"] == want,
              "owner_contact_app: GET /api/plan shows them to every user whatever the language (not per language)")
        got = [x for x in logs(made["admin"]) if x["action"] == "plans_update" and "owner contact email" in (x["details"] or "")]
        check(got and OWNER_EMAIL in got[0]["details"] and "owner contact viber" in got[0]["details"],
              "owner_contact_save: the change is written to the admin log", got[:1])
        # a save that leaves owner_contact out keeps them
        snap = c.get("/api/admin/plans", headers=AD).json()
        snap.pop("owner_contact")
        snap["upgrade_contact"] = {"en": "Ping us", "my": ""}
        r = c.put("/api/admin/plans", headers=AD, json=snap)
        check(r.status_code == 200 and r.json()["owner_contact"] == want and r.json()["upgrade_contact"]["en"] == "Ping us"
              and stored_owner()["contact_email"] == OWNER_EMAIL,
              "owner_contact_save: a save without owner_contact leaves the owner's email and number alone", f"{r.status_code} {r.text[-200:]}")
        # one at a time
        r = put_owner("", OWNER_VIBER)
        check(r.status_code == 200 and r.json()["owner_contact"] == {"email": "", "viber": OWNER_VIBER}
              and c.get("/api/plan", headers=h).json()["owner_contact"] == {"email": "", "viber": OWNER_VIBER},
              "owner_contact_save: an empty email clears just the email")
        r = put_owner(OWNER_EMAIL, "  ")
        check(r.status_code == 200 and r.json()["owner_contact"] == {"email": OWNER_EMAIL, "viber": ""},
              "owner_contact_save: a blank number clears just the number")
        before_bad = c.get("/api/admin/plans", headers=AD).json()
        for label, email, viber, word in (
            ("an email without @", "owner.example.com", "", "email"), ("an email without a domain dot", "owner@example", "", "email"),
            ("an email with a space", "own er@example.com", "", "email"), ("an email over 254 characters", "a" * 250 + "@b.co", "", "email"),
            ("a Viber number with letters", "", "abc", "Viber"), ("a Viber number too short", "", "+1234567", "Viber"),
            ("a Viber number without a plus or 09", "", "959123456789", "Viber"),
        ):
            r = put_owner(email, viber)
            check(r.status_code == 422 and word in r.text and c.get("/api/admin/plans", headers=AD).json() == before_bad,
                  f"owner_contact_validation: {label} is a 422 with a readable message and saves nothing", f"{r.status_code} {r.text[:200]}")
        r = put_owner("owner.example.com", "abc")
        check(r.status_code == 422 and "email" in r.text and "Viber" in r.text,
              "owner_contact_validation: both problems are reported together", r.text[:200])
        snap = c.get("/api/admin/plans", headers=AD).json()
        for label, bad in (("an unknown field", {"email": "", "viber": "", "telegram": "x"}), ("a missing viber", {"email": ""}),
                           ("a non-text email", {"email": 5, "viber": ""}), ("a string instead of an object", "me@example.com")):
            snap["owner_contact"] = bad
            r = c.put("/api/admin/plans", headers=AD, json=snap)
            check(r.status_code == 422 and c.get("/api/admin/plans", headers=AD).json() == before_bad,
                  f"owner_contact_validation: {label} is a 422", f"{r.status_code} {r.text[:150]}")
        check(put_owner("owner@example.com", "x", h_=MOD).status_code == 403,
              "owner_contact_roles: a moderator cannot change them (403)")
        r = c.put("/api/admin/plans", json=snap)
        check(r.status_code in (401, 403) and c.put("/api/admin/plans", headers=plus_h, json=snap).status_code in (401, 403),
              "owner_contact_roles: no token and a user token are refused")
        check(put_owner("super@example.com", "", h_=SUP).status_code == 200
              and c.get("/api/plan", headers=h).json()["owner_contact"]["email"] == "super@example.com",
              "owner_contact_roles: a super admin can")
        check(put_owner("", "").status_code == 200 and stored_owner() == {"contact_email": "", "contact_viber": ""},
              "owner_contact_save: both can be cleared again (stored as empty)")
        check(put_contact(saved_contact["en"], saved_contact["my"]), "setup: put the upgrade contact back")

        # upgrade_request_declined: dismiss, contact message unset
        check(put_contact("", ""), "setup: clear the upgrade contact")
        d1_uid, _ = request_for("dec-plain", "pro")
        check(dismiss(d1_uid) == 200, "setup: dismiss a request for Pro")
        got = notes(d1_uid, "upgrade_request_declined")
        check(len(got) == 1 and got[0]["message"] == "Your request for Pro was closed. Contact us if you have questions."
              and not notes(d1_uid, "plan_activated"),
              "upgrade_request_declined: without a contact message it says 'Contact us if you have questions.'", got)
        # with a contact message, in the user's language
        check(put_contact("Message the owner on Telegram: @flowowner", "ပိုင်ရှင်ကို Telegram မှ ဆက်သွယ်ပါ"),
              "setup: set the upgrade contact")
        d2_uid, _ = request_for("dec-contact", "plus")
        dismiss(d2_uid)
        got = notes(d2_uid, "upgrade_request_declined")
        check(len(got) == 1 and got[0]["message"] == "Your request for Plus was closed. Message the owner on Telegram: @flowowner"
              and "Request" in got[0]["title"] and "Contact us" not in got[0]["message"],
              "upgrade_request_declined: with a contact message it follows 'was closed.' (English)", got)
        d3_uid, _ = request_for("dec-my", "plus", "my")
        dismiss(d3_uid)
        got = notes(d3_uid, "upgrade_request_declined")
        check(len(got) == 1 and MYANMAR.search(got[0]["title"]) and "ပိုင်ရှင်ကို Telegram မှ ဆက်သွယ်ပါ" in got[0]["message"]
              and "Plus" in got[0]["message"] and "Telegram: @flowowner" not in got[0]["message"],
              "upgrade_request_declined: a Myanmar user gets the Myanmar wording and the Myanmar contact message", got)
        # a contact message only in the other language is not used: the default sentence in the user's language
        check(put_contact("Message the owner on Telegram: @flowowner", "  "), "setup: contact in English only")
        d4_uid, _ = request_for("dec-my-default", "pro", "my")
        dismiss(d4_uid)
        got = notes(d4_uid, "upgrade_request_declined")
        check(len(got) == 1 and MYANMAR.search(got[0]["message"]) and "@flowowner" not in got[0]["message"]
              and "Contact us" not in got[0]["message"],
              "upgrade_request_declined: a contact message missing in Myanmar falls back to the default Myanmar sentence", got)
        # the owner's email and Viber number follow the contact message (or the default sentence), one per line
        check(put_contact("Message the owner on Telegram: @flowowner", "ပိုင်ရှင်ကို Telegram မှ ဆက်သွယ်ပါ")
              and put_owner(OWNER_EMAIL, "09 123 456 789").status_code == 200, "setup: contact message, email and Viber number")
        d7_uid, _ = request_for("dec-owner", "plus")
        dismiss(d7_uid)
        got = notes(d7_uid, "upgrade_request_declined")
        check(len(got) == 1 and got[0]["message"] == "Your request for Plus was closed. Message the owner on Telegram: @flowowner"
              f"\nEmail: {OWNER_EMAIL}\nViber: {OWNER_VIBER}",
              "upgrade_request_declined: the email and Viber number follow the contact message ('Email: …', 'Viber: …')", got)
        d8_uid, _ = request_for("dec-owner-my", "pro", "my")
        dismiss(d8_uid)
        got = notes(d8_uid, "upgrade_request_declined")
        check(len(got) == 1 and "ပိုင်ရှင်ကို Telegram မှ ဆက်သွယ်ပါ" in got[0]["message"]
              and f"\nအီးမေးလ်: {OWNER_EMAIL}\nဗိုင်ဘာ: {OWNER_VIBER}" in got[0]["message"]
              and "Email:" not in got[0]["message"] and "Viber:" not in got[0]["message"],
              "upgrade_request_declined: a Myanmar user gets the Myanmar labels", got)
        check(put_contact("", "") and put_owner(OWNER_EMAIL, "").status_code == 200, "setup: no contact message, only an email")
        d9_uid, _ = request_for("dec-owner-email", "plus")
        dismiss(d9_uid)
        got = notes(d9_uid, "upgrade_request_declined")
        check(len(got) == 1 and got[0]["message"] == f"Your request for Plus was closed. Contact us if you have questions.\nEmail: {OWNER_EMAIL}",
              "upgrade_request_declined: with only an email set, the default sentence is followed by just the email line", got)
        check(put_owner("", OWNER_VIBER).status_code == 200, "setup: only a Viber number")
        d10_uid, _ = request_for("dec-owner-viber", "plus", "my")
        dismiss(d10_uid)
        got = notes(d10_uid, "upgrade_request_declined")
        check(len(got) == 1 and got[0]["message"].endswith(f"\nဗိုင်ဘာ: {OWNER_VIBER}") and "အီးမေးလ်" not in got[0]["message"]
              and MYANMAR.search(got[0]["message"].split("\n")[0]),
              "upgrade_request_declined: with only a Viber number, just the Viber line follows (Myanmar default sentence)", got)
        check(put_owner("", "").status_code == 200, "setup: clear the owner's email and Viber number")
        put_contact(saved_contact["en"], saved_contact["my"])
        # a dismissal answered twice (409) notifies once
        d5_uid, _ = request_for("dec-twice")
        rid = listed(MOD, d5_uid)["id"]
        c.post(f"/api/admin/upgrade-requests/{rid}/dismiss", headers=AD)
        check(c.post(f"/api/admin/upgrade-requests/{rid}/dismiss", headers=AD).status_code == 409
              and len(notes(d5_uid, "upgrade_request_declined")) == 1,
              "upgrade_request_declined: a second dismissal is a 409 and sends no second notice")
        # manual 'done' is bookkeeping: nothing
        d6_uid, _ = request_for("done-manual")
        r = c.post(f"/api/admin/upgrade-requests/{listed(MOD, d6_uid)['id']}/done", headers=AD)
        check(r.status_code == 200 and not notes(d6_uid, "plan_activated", "upgrade_request_declined"),
              "upgrade_request_done: Mark done sends the user nothing", r.status_code)

        # A failure to notify never fails the admin action: a trigger makes the notification insert fail for one user.
        f_uid, _ = request_for("fail-notify", "plus")
        f2_uid, _ = request_for("fail-notify-2", "plus")
        trigger_user = (f_uid, f2_uid)
        try:
            with t.connect() as conn:
                conn.execute("CREATE OR REPLACE FUNCTION t8r_refuse_note() RETURNS trigger LANGUAGE plpgsql AS "
                             "$$ BEGIN RAISE EXCEPTION 't8r: notifications are refused for this user'; END $$")
                for i, who in enumerate(trigger_user):
                    conn.execute(f"CREATE TRIGGER t8r_refuse_note_{i} BEFORE INSERT ON notifications FOR EACH ROW "
                                 f"WHEN (NEW.user_id = '{who}') EXECUTE FUNCTION t8r_refuse_note()")
            ok = set_plan(f_uid, "plus", ends)
            check(ok and plan_of(f_uid) == "plus" and rows(f_uid)[0][3] == "done" and not notes(f_uid, "plan_activated"),
                  "notify_failure: setting the plan still succeeds (200, plan changed, request closed) when the notice cannot be stored",
                  (ok, plan_of(f_uid)))
            r = c.post(f"/api/admin/upgrade-requests/{listed(MOD, f2_uid)['id']}/dismiss", headers=AD)
            check(r.status_code == 200 and r.json().get("status") == "dismissed" and rows(f2_uid)[0][3] == "dismissed"
                  and not notes(f2_uid, "upgrade_request_declined"),
                  "notify_failure: dismissing still succeeds when the notice cannot be stored", f"{r.status_code} {r.text[:150]}")
        finally:
            with t.connect() as conn:
                for i in range(len(trigger_user)):
                    conn.execute(f"DROP TRIGGER IF EXISTS t8r_refuse_note_{i} ON notifications")
                conn.execute("DROP FUNCTION IF EXISTS t8r_refuse_note()")
    finally:
        if saved_contact is not None:  # the checks changed the upgrade contact: put the original back
            snap = c.get("/api/admin/plans", headers=AD).json()
            snap["upgrade_contact"] = saved_contact
            snap["owner_contact"] = saved_owner
            c.put("/api/admin/plans", headers=AD, json=snap)
        db.users.delete_many({"email": {"$regex": f"^t8r-.*-{tag}@"}})
        db.admins.delete_many({"email": {"$in": list(made.values())}})
        c.close()
