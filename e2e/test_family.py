"""Family book e2e. One function per section, called from main().

Sections:
  schema -- the tables / columns / indexes the family book needs (Task 1).
  book users -- hidden, can't log in, left out of admin lists, stats, broadcasts, plan expiry and jobs (Task 2).
"""
import asyncio
import os
import sys
import uuid
from datetime import UTC, datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402,F401

import httpx  # noqa: E402

db = __import__("pgcompat").get_db()
failures = 0


def check(ok, name, detail=""):
    global failures
    if not ok:
        failures += 1
    print(("[PASS] " if ok else "[BUG] ") + name + (f" -- {detail}" if detail and not ok else ""))


def _columns(table):
    rows = db.sql("SELECT column_name, is_nullable, data_type, column_default FROM information_schema.columns "
                  "WHERE table_schema = 'public' AND table_name = %s", table)
    return {r["column_name"]: r for r in rows}


def _expect_cols(table, expected):
    """expected: {column: is_nullable 'YES'/'NO'}"""
    cols = _columns(table)
    for col, nullable in expected.items():
        c = cols.get(col)
        check(c is not None and c["is_nullable"] == nullable, f"schema: {table}.{col} ({'NULL' if nullable == 'YES' else 'NOT NULL'})",
              "missing" if c is None else f"is_nullable={c['is_nullable']}")


def _violates(sql, *params):
    """True when the statement is refused by the database (constraint violation)."""
    try:
        db.sql(sql, *params)
    except Exception as e:  # psycopg raises IntegrityError / CheckViolation
        try:
            db._pg.rollback()
        except Exception:
            pass
        return type(e).__name__
    return None


def section_schema():
    _expect_cols("users", {"kind": "NO"})
    _expect_cols("families", {"id": "NO", "name": "NO", "book_user_id": "NO", "created_at": "NO", "updated_at": "NO"})
    _expect_cols("family_members", {"id": "NO", "family_id": "NO", "user_id": "YES", "display_name": "NO", "kind": "NO",
                                    "role": "YES", "status": "NO", "joined_at": "NO", "left_at": "YES"})
    _expect_cols("family_invites", {"id": "NO", "family_id": "NO", "email": "NO", "invited_by_member_id": "YES",
                                    "link_member_id": "YES", "status": "NO", "created_at": "NO", "expires_at": "NO"})
    _expect_cols("transactions", {"added_by_member_id": "YES", "transfer_id": "YES"})
    _expect_cols("transaction_beneficiaries", {"transaction_id": "NO", "member_id": "NO"})
    _expect_cols("chat_sessions", {"book_id": "YES"})
    _expect_cols("plan_settings", {"family_max_members": "NO", "family_max_placeholders": "NO"})

    kind = _columns("users").get("kind")
    check(kind is not None and "person" in (kind["column_default"] or ""), "schema: users.kind defaults to 'person'",
          kind and kind["column_default"])

    idx = {r["indexname"] for r in db.sql("SELECT indexname FROM pg_indexes WHERE schemaname = 'public'")}
    for name in ("uq_family_members_user_active", "uq_family_members_owner_active", "uq_family_invites_pending_email",
                 "ix_transactions_transfer_id", "uq_families_book_user_id"):
        check(name in idx, f"schema: index {name}", "missing")

    rows = {r["plan"]: r for r in db.sql("SELECT plan, family_max_members m, family_max_placeholders p FROM plan_settings")} \
        if "family_max_members" in _columns("plan_settings") else {}
    for plan, m, p in (("free", 0, 0), ("plus", 6, 20), ("pro", 6, 20)):
        check(plan in rows and (rows[plan]["m"], rows[plan]["p"]) == (m, p), f"schema: plan_settings {plan} seeded {m}/{p}",
              rows.get(plan))

    # Behaviour: constraints.
    if not _columns("families"):
        check(False, "schema: constraint behaviour", "families table missing")
        return
    tag = uuid.uuid4().hex[:8]
    ids = {k: f"t-{tag}-{k}" for k in ("u1", "u2", "f", "m1", "m2", "m3")}
    try:
        for k in ("u1", "u2"):
            db.sql("INSERT INTO users (id, name, email, password, kind) VALUES (%s, 'x', %s, 'x', 'family_book')",
                   ids[k], f"{ids[k]}@book.invalid")
        db.sql("INSERT INTO families (id, name, book_user_id) VALUES (%s, 'F', %s)", ids["f"], ids["u1"])
        db.sql("INSERT INTO family_members (id, family_id, display_name, kind, role) VALUES (%s, %s, 'A', 'placeholder', 'owner')",
               ids["m1"], ids["f"])
        err = _violates("INSERT INTO family_members (id, family_id, display_name, kind, role) VALUES (%s, %s, 'B', 'placeholder', 'owner')",
                        ids["m2"], ids["f"])
        check(err is not None, "schema: two active owners in one family are refused", "second owner was accepted")
        check(_violates("INSERT INTO families (id, name, book_user_id) VALUES (%s, 'G', %s)", ids["m3"], ids["u1"]) is not None,
              "schema: book_user_id is unique")
        check(_violates("INSERT INTO family_members (id, family_id, display_name, kind, role) VALUES (%s, %s, 'C', 'bogus', NULL)",
                        ids["m3"], ids["f"]) is not None, "schema: family_members.kind is checked")
        check(_violates("UPDATE users SET kind = 'robot' WHERE id = %s", ids["u2"]) is not None, "schema: users.kind is checked")
        db.sql("INSERT INTO family_invites (id, family_id, email, status, expires_at) VALUES (%s, %s, 'a@b.c', 'pending', now())",
               ids["m1"], ids["f"])
        check(_violates("INSERT INTO family_invites (id, family_id, email, status, expires_at) VALUES (%s, %s, 'a@b.c', 'pending', now())",
                        ids["m2"], ids["f"]) is not None, "schema: one pending invite per family and email")
        check(_violates("UPDATE plan_settings SET family_max_members = 51 WHERE plan = 'plus'") is not None,
              "schema: family_max_members capped at 50")
    finally:
        db.sql("DELETE FROM users WHERE id IN (%s, %s)", ids["u1"], ids["u2"])  # cascades to the family and its rows

def _backend_async(coro_fn):
    """Run backend async code (its DB engine binds to the loop, so one asyncio.run per call and a fresh engine)."""
    async def go():
        from sql import db as sqldb
        try:
            return await coro_fn()
        finally:
            await sqldb.dispose_engine()
    return asyncio.run(go())


def section_book_users():
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend"))
    os.chdir(stubenv.BACKEND)
    import test_plans  # noqa: E402  (admin helpers)

    c = httpx.Client(base_url="http://127.0.0.1:8765", timeout=60)
    made = test_plans.make_admins(db, ("super_admin",))
    h = test_plans.admin_login(c, made["super_admin"])

    def counts():
        u = c.get("/api/admin/stats/users", headers=h).json()
        b = c.get("/api/admin/broadcast-stats", headers=h).json()
        return {k: u.get(k) for k in ("total_users", "free_users", "plus_users", "pro_users", "paid_users",
                                       "active_users_last_7_days")} | {"bc_total": b.get("total_users"),
                                                                       "bc_push": b.get("users_with_push_enabled")}

    family_id = str(uuid.uuid4())
    email = f"family-{family_id}@book.invalid"
    book_id = None
    try:
        before = counts()

        async def make():
            from sql import users as users_db
            return await users_db.create_book_user(family_id)
        book_id = _backend_async(make)

        row = db.users.find_one({"_id": book_id}) or {}
        check(row.get("kind") == "family_book" and row.get("email") == email and row.get("is_verified") is True
              and row.get("subscription_type") == "free" and row.get("language") == "en",
              "book users: create_book_user stores the agreed row", {k: row.get(k) for k in ("kind", "email", "is_verified", "subscription_type", "language")})
        check(str(row.get("password", "")).startswith("$2"), "book users: the password is a bcrypt hash of a discarded secret")

        # Make it look as attractive as possible to every listing, job and counter.
        db.users.update_one({"_id": book_id}, {"$set": {"subscription_type": "plus", "fcm_token": "book-fcm-token",
                                                         "subscription_expires_at": datetime.now(UTC) - timedelta(days=2)}})
        db.sql("INSERT INTO transactions (id, user_id, type, main_category, sub_category, amount, currency, date) "
               "VALUES (%s, %s, 'outflow', 'Food', 'Groceries', 5, 'usd', now())", str(uuid.uuid4()), book_id)
        db.sql("INSERT INTO chat_sessions (id, user_id) VALUES (%s, %s)", str(uuid.uuid4()), book_id)

        # Login: any password, and the e-mail in other cases, is the same 401 as an unknown account.
        for pw in ("anything", "secret123", ""):
            r = c.post("/api/auth/login", json={"email": email, "password": pw})
            check(r.status_code in (401, 422), "book users: login as the book user is refused (401; 422 where the e-mail validator rejects .invalid)", f"{pw!r}: {r.status_code} {r.text[:120]}")
        r = c.post("/api/auth/login", json={"email": email.upper(), "password": "anything"})
        check(r.status_code in (401, 422), "book users: login is refused whatever the e-mail's case", r.status_code)

        # Forgot password: the same generic answer as for an unknown e-mail, and no OTP is stored.
        r = c.post("/api/auth/forgot-password/request-otp", json={"email": email})
        stored = db.users.find_one({"_id": book_id}) or {}
        check(r.status_code in (200, 422) and not stored.get("password_reset_otp"), "book users: forgot-password sets no OTP",
              f"{r.status_code} otp={'set' if stored.get('password_reset_otp') else 'none'}")

        # Past the request validators, the lookups themselves treat it as not found (login, reset and verify all use this).
        async def lookup():
            import auth_routes
            return await auth_routes.find_user_by_email(email)
        check(_backend_async(lookup) is None, "book users: auth_routes.find_user_by_email treats it as not found")

        # A token minted for the book user (e.g. by a bug elsewhere) must not authenticate.
        async def mint():
            import auth_routes
            user = await __import__("sql.users", fromlist=["x"]).get_user(book_id)
            return auth_routes._issue_token(user)
        token = _backend_async(mint)
        r = c.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})
        check(r.status_code == 401, "book users: a token issued for the book user is refused (401)", f"{r.status_code} {r.text[:120]}")

        # Admin: list, search, detail, usage and the counters.
        r = c.get("/api/admin/users", headers=h, params={"search": family_id, "limit": 100})
        check(r.status_code == 200 and not any(u.get("email") == email for u in r.json()),
              "book users: admin user search doesn't find it", r.status_code)
        r = c.get("/api/admin/users", headers=h, params={"limit": 100, "subscription_type": "free"})
        check(r.status_code == 200 and not any(u.get("email") == email for u in r.json()),
              "book users: admin user list (free filter, where an expired Plus lands) doesn't include it", r.status_code)
        for path in (f"/api/admin/users/{book_id}", f"/api/admin/users/{book_id}/usage"):
            r = c.get(path, headers=h)
            check(r.status_code == 404, f"book users: {path.split(book_id)[1] or 'detail'} admin read is a 404", r.status_code)
        after = counts()
        check(after == before, "book users: admin stats and broadcast counts are unchanged", {k: (before[k], after[k]) for k in before if before[k] != after[k]})

        # The weekly/monthly all-user job selection and plan expiry.
        async def jobs():
            from plans.catalog import PAID_PLANS
            import subscription_service
            from sql import users as users_db
            picked = await users_db.list_fields(["subscription_type"], users_db.users.c.subscription_type.in_(PAID_PLANS))
            ids = await users_db.user_ids()
            n = await subscription_service.expire_paid_plans()
            return book_id in {u["_id"] for u in picked}, book_id in ids, n
        in_picked, in_ids, _ = _backend_async(jobs)
        check(not in_picked, "book users: the all-user insights selection (paid plans) skips it")
        check(not in_ids, "book users: user_ids() (scheduler, daily jobs) skips it")
        row = db.users.find_one({"_id": book_id}) or {}
        check(row.get("subscription_type") == "plus", "book users: expire_paid_plans leaves an expired book user alone",
              row.get("subscription_type"))

        r = c.delete(f"/api/admin/users/{book_id}", headers=h)  # last: the old behaviour deletes the row
        check(r.status_code == 404 and db.users.find_one({"_id": book_id}), "book users: admin can't delete it", r.status_code)
    finally:
        if book_id:
            db.sql("DELETE FROM users WHERE id = %s", book_id)
        db.admins.delete_many({"email": made["super_admin"]})


BASE = "http://127.0.0.1:8765"


def _code(r, status, code):
    """The response is `status` with {"detail": {"code": code, "message": <non-empty>}}."""
    try:
        d = r.json().get("detail") if r.status_code == status else None
    except ValueError:
        return False
    return isinstance(d, dict) and d.get("code") == code and bool(d.get("message"))


def section_family_rules():
    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:6]
    made = []

    def register(name, plan="free"):
        email = f"fam-{name.lower()}-{tag}@example.com"
        c.post("/api/auth/register", json={"name": name, "email": email, "password": "secret123"})
        db.users.update_one({"email": email}, {"$set": {"is_verified": True}})
        token = c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json()["access_token"]
        uid = db.users.find_one({"email": email})["_id"]
        made.append(uid)
        expires = datetime.now(UTC) + timedelta(days=30) if plan != "free" else None
        db.sql("UPDATE users SET subscription_type = %s, subscription_expires_at = %s, trial_ends_at = NULL WHERE id = %s",
               plan, expires, uid)
        return {"id": uid, "email": email, "name": name, "h": {"Authorization": f"Bearer {token}"}}

    def fam(u):
        return c.get("/api/family", headers=u["h"])

    def member_of(view, *, user=None, name=None):
        for m in view.get("members", []):
            if (name is not None and m["display_name"] == name) or (user is not None and m.get("is_me")):
                return m
        return None

    def invite(by, email, link=None):
        body = {"email": email} | ({"link_member_id": link} if link else {})
        return c.post("/api/family/invites", headers=by["h"], json=body)

    def accept_from(who, family_name):
        mine = c.get("/api/family/invites/mine", headers=who["h"]).json().get("invites", [])
        inv = next((i for i in mine if i.get("family_name") == family_name), None)
        if inv is None:
            return None, None
        return inv, c.post(f"/api/family/invites/{inv['id']}/accept", headers=who["h"])

    def notified(uid, kind):
        return db.sql("SELECT count(*) n FROM notifications WHERE user_id = %s AND type = %s", uid, kind)[0]["n"]

    try:
        A = register("Aye", "plus")
        B = register("Bo", "free")
        db.sql("UPDATE users SET language = 'my' WHERE id = %s", B["id"])

        # ---- creating ----
        r = c.post("/api/family", headers=B["h"], json={"name": "Bo's family"})
        check(_code(r, 403, "plan_required"), "family rules: a Free user can't create a family (403 plan_required)", f"{r.status_code} {r.text[:200]}")
        check(r.status_code == 403 and "Plus" in r.json()["detail"]["message"] and "Creating" not in r.json()["detail"]["message"],
              "family rules: the refusal is in the user's language (Myanmar)", r.text[:200])
        r = c.get("/api/family", headers=B["h"])
        check(r.status_code == 200 and r.json() == {"family": None}, "family rules: GET /api/family is {family: null} outside a family",
              f"{r.status_code} {r.text[:200]}")
        p = c.get("/api/plan", headers=A["h"]).json().get("family")
        check(p == {"max_members": 6, "max_placeholders": 20}, "family rules: GET /api/plan gives a Plus user family limits 6/20", p)
        p = c.get("/api/plan", headers=B["h"]).json().get("family")
        check(p == {"max_members": 0, "max_placeholders": 0}, "family rules: GET /api/plan gives a Free user family limits 0/0", p)

        FNAME = f"Aye family {tag}"
        r = c.post("/api/family", headers=A["h"], json={"name": FNAME})
        view = r.json() if r.status_code == 200 else {}
        me = view.get("me") or {}
        check(r.status_code == 200 and (view.get("family") or {}).get("name") == FNAME and me.get("role") == "owner"
              and view.get("family", {}).get("read_only") is False
              and view.get("limits") == {"max_members": 6, "max_placeholders": 20},
              "family rules: a Plus user creates a family and is its owner", f"{r.status_code} {r.text[:300]}")
        fid = (view.get("family") or {}).get("id")
        a_mid = me.get("member_id")
        m = member_of(view, user=A) or {}
        check(m.get("id") == a_mid and m.get("display_name") == "Aye" and m.get("kind") == "account" and m.get("status") == "active",
              "family rules: the owner member carries the user's name", m)
        book = db.sql("SELECT u.kind FROM families f JOIN users u ON u.id = f.book_user_id WHERE f.id = %s", fid)
        check(book and book[0]["kind"] == "family_book", "family rules: the family has its own book user", book)
        r = c.post("/api/family", headers=A["h"], json={"name": "Second"})
        check(_code(r, 409, "already_in_family"), "family rules: creating a second family is refused (already_in_family)", r.status_code)

        # ---- inviting a Free user; joining is free ----
        r = invite(A, B["email"].upper())
        check(r.status_code == 200, "family rules: the owner invites a Free user", f"{r.status_code} {r.text[:200]}")
        check(notified(B["id"], "family_invite") == 1, "family rules: the invitee is notified (family_invite)")
        inv, r = accept_from(B, FNAME)
        check(inv is not None, "family rules: the invite shows in invites/mine (matched case-insensitively)")
        check(r is not None and r.status_code == 200, "family rules: a Free user accepts the invite (joining is free)",
              r is not None and f"{r.status_code} {r.text[:200]}")
        vb = fam(B).json()
        b_mid = (vb.get("me") or {}).get("member_id")
        check((vb.get("me") or {}).get("role") == "member" and (vb.get("family") or {}).get("id") == fid,
              "family rules: the invitee is now a member", vb.get("me"))
        check("invites" in vb and vb["invites"] == [], "family rules: a member gets no invite list", vb.get("invites"))
        check(notified(A["id"], "family_invite_accepted") == 1, "family rules: admins are told the invite was accepted")

        # ---- a member has no admin powers ----
        r = invite(B, f"nobody-{tag}@example.com")
        check(_code(r, 403, "not_allowed"), "family rules: a member can't invite (not_allowed)", f"{r.status_code} {r.text[:200]}")
        r = c.post("/api/family/placeholders", headers=B["h"], json={"display_name": "Grandma"})
        check(_code(r, 403, "not_allowed"), "family rules: a member can't add a placeholder", r.status_code)
        r = c.patch(f"/api/family/members/{a_mid}", headers=B["h"], json={"display_name": "Boss"})
        check(_code(r, 403, "not_allowed"), "family rules: a member can't rename", r.status_code)
        r = c.patch("/api/family", headers=B["h"], json={"name": "Mine now"})
        check(_code(r, 403, "not_allowed"), "family rules: a member can't rename the family", r.status_code)
        r = c.delete(f"/api/family/members/{a_mid}", headers=B["h"])
        check(_code(r, 403, "not_allowed"), "family rules: a member can't remove anyone", r.status_code)

        # ---- the owner makes an admin; admins can't change roles ----
        r = c.patch(f"/api/family/members/{b_mid}", headers=A["h"], json={"role": "admin"})
        check(r.status_code == 200 and (member_of(fam(B).json(), user=B) or {}).get("role") == "admin",
              "family rules: the owner makes a member an admin", f"{r.status_code} {r.text[:200]}")
        r = c.patch(f"/api/family/members/{a_mid}", headers=A["h"], json={"role": "member"})
        check(_code(r, 403, "not_allowed"), "family rules: the owner's own role can't be set this way", r.status_code)
        C = register("Chit")
        r = invite(B, C["email"])
        check(r.status_code == 200, "family rules: an admin can invite", f"{r.status_code} {r.text[:200]}")
        _, r = accept_from(C, FNAME)
        c_mid = (fam(C).json().get("me") or {}).get("member_id")
        r = c.patch(f"/api/family/members/{c_mid}", headers=B["h"], json={"role": "admin"})
        check(_code(r, 403, "not_allowed"), "family rules: an admin can't change roles", r.status_code)
        r = c.delete(f"/api/family/members/{a_mid}", headers=B["h"])
        check(_code(r, 403, "not_allowed"), "family rules: the owner can't be removed", r.status_code)

        # ---- a placeholder becomes a real member ----
        r = c.post("/api/family/placeholders", headers=B["h"], json={"display_name": "Ma Ma"})
        mama = member_of(r.json(), name="Ma Ma") if r.status_code == 200 else None
        check(mama is not None and mama["kind"] == "placeholder" and mama["role"] is None,
              "family rules: an admin adds placeholder Ma Ma", f"{r.status_code} {r.text[:200]}")
        M = register("MaMa")
        r = invite(B, M["email"], link=mama and mama["id"])
        check(r.status_code == 200, "family rules: an invite can be linked to a placeholder", f"{r.status_code} {r.text[:200]}")
        pend = fam(A).json().get("invites", [])
        check(any(i.get("email") == M["email"].lower() and i.get("link_member_id") == (mama or {}).get("id")
                  and i.get("status") == "pending" for i in pend), "family rules: admins see the pending invites", pend)
        _, r = accept_from(M, FNAME)
        rows = [x for x in fam(A).json().get("members", []) if x["display_name"] == "Ma Ma"]
        check(r is not None and r.status_code == 200 and len(rows) == 1 and rows[0]["id"] == (mama or {}).get("id")
              and rows[0]["kind"] == "account" and rows[0]["status"] == "active" and rows[0]["role"] == "member",
              "family rules: accepting a linked invite turns the placeholder into the account (same member id, one row)", rows)
        check(mama is not None and (fam(M).json().get("me") or {}).get("member_id") == mama["id"],
              "family rules: the new member is that row")

        # ---- the member cap: active accounts + pending invites <= 6 ----
        D, E, G = register("Daw"), register("Ei"), register("Gyi")
        check(invite(A, D["email"]).status_code == 200 and invite(A, E["email"]).status_code == 200,
              "family rules: invites up to the cap are accepted (4 active + 2 pending)")
        r = invite(A, G["email"])
        check(_code(r, 409, "family_full"), "family rules: 4 active + 2 pending invites, one more invite is family_full",
              f"{r.status_code} {r.text[:200]}")
        accept_from(D, FNAME)
        accept_from(E, FNAME)
        actives = [x for x in fam(A).json().get("members", []) if x["kind"] == "account" and x["status"] == "active"]
        r = invite(A, G["email"])
        check(len(actives) == 6 and _code(r, 409, "family_full"), "family rules: a 7th account member is family_full",
              f"{len(actives)} {r.status_code}")

        # ---- placeholders cap ----
        codes = [c.post("/api/family/placeholders", headers=A["h"], json={"display_name": f"P{i}"}).status_code for i in range(1, 21)]
        check(codes == [200] * 20, "family rules: 20 placeholders are allowed", codes)
        r = c.post("/api/family/placeholders", headers=A["h"], json={"display_name": "P21"})
        check(_code(r, 409, "placeholders_full"), "family rules: a 21st placeholder is placeholders_full", f"{r.status_code} {r.text[:200]}")

        # ---- removing placeholders: untagged deleted, tagged kept as former ----
        view = fam(A).json()
        p1, p2 = member_of(view, name="P1") or {"id": "missing-p1"}, member_of(view, name="P2") or {"id": "missing-p2"}
        r = c.delete(f"/api/family/members/{p1['id']}", headers=A["h"])
        gone = db.sql("SELECT count(*) n FROM family_members WHERE id = %s", p1["id"])[0]["n"]
        check(r.status_code == 200 and gone == 0 and member_of(fam(A).json(), name="P1") is None,
              "family rules: removing a placeholder with no entries deletes it", f"{r.status_code} {gone}")
        book_id = db.sql("SELECT book_user_id FROM families WHERE id = %s", fid)[0]["book_user_id"]
        tx = str(uuid.uuid4())
        db.sql("INSERT INTO transactions (id, user_id, type, main_category, sub_category, amount, currency, date) "
               "VALUES (%s, %s, 'outflow', 'Food', 'Groceries', 5, 'usd', now())", tx, book_id)
        db.sql("INSERT INTO transaction_beneficiaries (transaction_id, member_id) VALUES (%s, %s)", tx, p2["id"])
        r = c.delete(f"/api/family/members/{p2['id']}", headers=A["h"])
        row = member_of(fam(A).json(), name="P2") or {}
        check(r.status_code == 200 and row.get("status") == "former"
              and db.sql("SELECT count(*) n FROM transaction_beneficiaries WHERE member_id = %s", p2["id"])[0]["n"] == 1,
              "family rules: removing a tagged placeholder keeps it as former, with its tags", f"{r.status_code} {row}")

        # ---- removing an account member ----
        r = c.delete(f"/api/family/members/{c_mid}", headers=B["h"])
        crow = member_of(fam(A).json(), name="Chit") or {}
        check(r.status_code == 200 and crow.get("status") == "former" and crow.get("role") == "member"
              and fam(C).json() == {"family": None}, "family rules: an admin removes a member; they become former",
              f"{r.status_code} {crow}")
        left = db.sql("SELECT left_at FROM family_members WHERE id = %s", c_mid)
        check(left and left[0]["left_at"] is not None, "family rules: a removed member has left_at set")
        check(notified(C["id"], "family_removed") == 1, "family rules: the removed member is notified (family_removed)")

        # ---- expired and cancelled invites (a second family) ----
        X = register("Xan", "pro")
        XNAME = f"Xan family {tag}"
        r = c.post("/api/family", headers=X["h"], json={"name": XNAME})
        check(r.status_code == 200, "family rules: a Pro user creates a family", f"{r.status_code} {r.text[:200]}")
        inv = invite(X, G["email"]).json()
        db.sql("UPDATE family_invites SET expires_at = now() - interval '1 minute' WHERE id = %s", inv.get("id"))
        check(not any(i["id"] == inv.get("id") for i in c.get("/api/family/invites/mine", headers=G["h"]).json().get("invites", [])),
              "family rules: an expired invite isn't in invites/mine")
        r = c.post(f"/api/family/invites/{inv.get('id')}/accept", headers=G["h"])
        st = db.sql("SELECT status FROM family_invites WHERE id = %s", inv.get("id"))
        check(_code(r, 400, "invite_invalid") and st and st[0]["status"] == "expired",
              "family rules: an expired invite can't be accepted and reads expired", f"{r.status_code} {st}")
        inv = invite(X, G["email"]).json()
        r = c.delete(f"/api/family/invites/{inv.get('id')}", headers=X["h"])
        check(r.status_code == 200, "family rules: an admin cancels an invite", f"{r.status_code} {r.text[:200]}")
        r = c.post(f"/api/family/invites/{inv.get('id')}/accept", headers=G["h"])
        check(_code(r, 400, "invite_invalid"), "family rules: a cancelled invite can't be accepted", r.status_code)
        inv = invite(X, G["email"]).json()
        r = c.post(f"/api/family/invites/{inv.get('id')}/decline", headers=G["h"])
        st = db.sql("SELECT status FROM family_invites WHERE id = %s", inv.get("id"))
        check(r.status_code == 200 and st and st[0]["status"] == "declined", "family rules: an invite can be declined", st)

        # ---- one family per person ----
        inv = invite(X, B["email"]).json()
        r = c.post(f"/api/family/invites/{inv.get('id')}/accept", headers=B["h"])
        check(_code(r, 409, "already_in_family"), "family rules: someone in a family can't accept another family's invite",
              f"{r.status_code} {r.text[:200]}")

        # ---- leaving and handing over ----
        r = c.post("/api/family/leave", headers=A["h"])
        check(_code(r, 409, "owner_must_hand_over"), "family rules: the owner can't leave (owner_must_hand_over)", r.status_code)
        r = c.post("/api/family/transfer-ownership", headers=B["h"], json={"member_id": b_mid})
        check(_code(r, 403, "not_allowed"), "family rules: only the owner hands over ownership", r.status_code)
        r = c.post("/api/family/transfer-ownership", headers=A["h"], json={"member_id": b_mid})
        vb = fam(B).json()
        check(r.status_code == 200 and (vb.get("me") or {}).get("role") == "owner"
              and (member_of(vb, name="Aye") or {}).get("role") == "admin",
              "family rules: ownership is handed over; the old owner becomes admin", f"{r.status_code} {vb.get('me')}")
        check((vb.get("family") or {}).get("read_only") is True and vb.get("limits") == {"max_members": 0, "max_placeholders": 0},
              "family rules: with a Free owner the family is read-only and has the Free limits", (vb.get("family"), vb.get("limits")))
        db.sql("UPDATE users SET subscription_type = 'plus', subscription_expires_at = now() + interval '30 days' WHERE id = %s", B["id"])
        vb = fam(B).json()
        check((vb.get("family") or {}).get("read_only") is False and vb.get("limits") == {"max_members": 6, "max_placeholders": 20},
              "family rules: once the owner is on Plus the family is writable again", (vb.get("family"), vb.get("limits")))
        r = c.post("/api/family/leave", headers=A["h"])
        arow = member_of(fam(B).json(), name="Aye") or {}
        check(r.status_code == 200 and fam(A).json() == {"family": None} and arow.get("status") == "former",
              "family rules: the old owner leaves and is now former", f"{r.status_code} {arow}")

        # ---- a former member comes back as the same member ----
        r = invite(B, A["email"])
        check(r.status_code == 200, "family rules: a former member can be invited again", f"{r.status_code} {r.text[:200]}")
        _, r = accept_from(A, FNAME)
        va = fam(A).json()
        check(r is not None and r.status_code == 200 and (va.get("me") or {}).get("member_id") == a_mid
              and (member_of(va, user=A) or {}).get("status") == "active"
              and len([x for x in va.get("members", []) if x["display_name"] == "Aye"]) == 1,
              "family rules: re-accepting reactivates the same member id", va.get("me"))

        # ---- deleting the family ----
        r = c.request("DELETE", "/api/family", headers=A["h"], json={"confirm_name": FNAME})
        check(_code(r, 403, "not_allowed"), "family rules: only the owner deletes the family", r.status_code)
        r = c.request("DELETE", "/api/family", headers=B["h"], json={"confirm_name": FNAME + "x"})
        check(_code(r, 400, "confirm_mismatch"), "family rules: a wrong confirm_name is confirm_mismatch", f"{r.status_code} {r.text[:200]}")
        r = c.request("DELETE", "/api/family", headers=B["h"], json={"confirm_name": FNAME})
        check(r.status_code == 200 and not db.sql("SELECT 1 FROM users WHERE id = %s", book_id)
              and not db.sql("SELECT 1 FROM families WHERE id = %s", fid) and fam(A).json() == {"family": None},
              "family rules: the owner deletes the family; its book user is gone", f"{r.status_code} {r.text[:200]}")
        check(not db.sql("SELECT 1 FROM transactions WHERE id = %s", tx), "family rules: the family's entries went with it")
    finally:
        if made:
            db.sql("DELETE FROM users WHERE id IN (SELECT f.book_user_id FROM families f JOIN family_members m "
                   "ON m.family_id = f.id WHERE m.user_id = ANY(%s))", made)
            db.sql("DELETE FROM users WHERE id = ANY(%s)", made)


def main():
    section_schema()
    section_book_users()
    section_family_rules()
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
