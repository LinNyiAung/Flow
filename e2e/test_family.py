"""Family book e2e. One function per section, called from main().

Sections:
  schema -- the tables / columns / indexes the family book needs (Task 1).
  book users -- a family's book is a books row, never a person: no users row, so no login, and never in the admin
    user list, the user stats, the broadcast recipients or user_ids() (Task 2; rewritten for the books table).
  family rules -- creating, inviting, joining, roles, removal, ownership, read-only (Task 3).
  book scope and privacy -- X-Book picks the book; no record is reachable from another book (Task 4).
  entries and breakdown -- who added an entry, who it was for, who may change it, the per-person breakdown, and
    recurring children that keep both (Task 5).
  transfers -- moving money between a personal wallet and the family wallet: one linked pair that only changes the
    two balances, left out of every income and spending figure, undone only by its mover (Task 6).
  budgets and goals -- only admins create, change or delete them or take money out of a goal; any member adds (Task 7).
  family notifications -- budget and goal notices reach every active account member in their own language and by their
    own preferences, and nobody else; no per-entry notices; recurring notices only to the adder (Task 8).
  ai -- Ko Toe Pwar in Family mode answers from the family book and the asker's profile; chat history is private per
    person and book; chat uses and costs the asker's allowance; family insights jobs and the owner's cost cap; the admin
    AI report's family row (Task 9).
  limits -- the admin Plans page's family limits: read, saved, validated 0-50, kept when left out, audit-logged, and
    lowering them removes no one (Task 10).
  account deletion -- a deleted member becomes former with their entries, name and tags kept; a deleted owner hands
    the family to the longest-standing admin, else account member, who is told; an owner left alone takes the family
    with them; through the user's own and the super admin's deletion (Task 11).
"""
import asyncio
import os
import sys
import time
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
    # The family's book is a books row (kind 'family'), not a hidden users row: users.kind and families.book_user_id are gone.
    check("kind" not in _columns("users"), "schema: users.kind is gone (users holds people only)")
    check("book_user_id" not in _columns("families"), "schema: families.book_user_id is gone (books.family_id instead)")
    _expect_cols("families", {"id": "NO", "name": "NO", "created_at": "NO", "updated_at": "NO"})
    _expect_cols("books", {"id": "NO", "kind": "NO", "person_id": "YES", "family_id": "YES"})
    _expect_cols("family_members", {"id": "NO", "family_id": "NO", "user_id": "YES", "display_name": "NO", "kind": "NO",
                                    "role": "YES", "status": "NO", "joined_at": "NO", "left_at": "YES"})
    _expect_cols("family_invites", {"id": "NO", "family_id": "NO", "email": "NO", "invited_by_member_id": "YES",
                                    "link_member_id": "YES", "status": "NO", "created_at": "NO", "expires_at": "NO"})
    _expect_cols("transactions", {"added_by_member_id": "YES", "transfer_id": "YES"})
    _expect_cols("transaction_beneficiaries", {"transaction_id": "NO", "member_id": "NO"})
    _expect_cols("chat_sessions", {"book_id": "NO"})  # every chat is about a book (a personal chat: the personal book)
    _expect_cols("notifications", {"book_id": "YES", "family_id": "YES", "family_invite_id": "YES"})
    _expect_cols("plan_settings", {"family_max_members": "NO", "family_max_placeholders": "NO"})

    idx = {r["indexname"] for r in db.sql("SELECT indexname FROM pg_indexes WHERE schemaname = 'public'")}
    for name in ("uq_family_members_user_active", "uq_family_members_owner_active", "uq_family_invites_pending_email",
                 "ix_transactions_transfer_id", "uq_books_family_id",
                 "ix_transactions_added_by_member_id", "ix_chat_sessions_book_id"):  # R21 (I3): the two FKs' indexes
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
    ids = {k: f"t-{tag}-{k}" for k in ("u1", "f", "b1", "b2", "m1", "m2", "m3")}
    try:
        db.sql("INSERT INTO users (id, name, email, password) VALUES (%s, 'x', %s, 'x')", ids["u1"], f"{ids['u1']}@family.test")
        db.sql("INSERT INTO families (id, name) VALUES (%s, 'F')", ids["f"])
        db.sql("INSERT INTO books (id, kind, family_id) VALUES (%s, 'family', %s)", ids["b1"], ids["f"])
        db.sql("INSERT INTO family_members (id, family_id, display_name, kind, role) VALUES (%s, %s, 'A', 'placeholder', 'owner')",
               ids["m1"], ids["f"])
        err = _violates("INSERT INTO family_members (id, family_id, display_name, kind, role) VALUES (%s, %s, 'B', 'placeholder', 'owner')",
                        ids["m2"], ids["f"])
        check(err is not None, "schema: two active owners in one family are refused", "second owner was accepted")
        check(_violates("INSERT INTO books (id, kind, family_id) VALUES (%s, 'family', %s)", ids["b2"], ids["f"]) is not None,
              "schema: a family has at most one family book")
        check(_violates("INSERT INTO books (id, kind, person_id, family_id) VALUES (%s, 'personal', %s, %s)",
                        ids["b2"], ids["u1"], ids["f"]) is not None, "schema: books.kind is tied to exactly one owner")
        check(_violates("INSERT INTO family_members (id, family_id, display_name, kind, role) VALUES (%s, %s, 'C', 'bogus', NULL)",
                        ids["m3"], ids["f"]) is not None, "schema: family_members.kind is checked")
        db.sql("INSERT INTO family_invites (id, family_id, email, status, expires_at) VALUES (%s, %s, 'a@b.c', 'pending', now())",
               ids["m1"], ids["f"])
        check(_violates("INSERT INTO family_invites (id, family_id, email, status, expires_at) VALUES (%s, %s, 'a@b.c', 'pending', now())",
                        ids["m2"], ids["f"]) is not None, "schema: one pending invite per family and email")
        check(_violates("UPDATE plan_settings SET family_max_members = 51 WHERE plan = 'plus'") is not None,
              "schema: family_max_members capped at 50")
    finally:
        db.sql("DELETE FROM families WHERE id = %s", ids["f"])  # cascades to its book, members and invites
        db.sql("DELETE FROM users WHERE id = %s", ids["u1"])

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
    """A family's book is a books row, never a person: no users row exists for it, so it can't log in, and it never
    shows up in the admin user list, the user stats or the broadcast recipients."""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend"))
    os.chdir(stubenv.BACKEND)
    import test_plans  # noqa: E402  (admin helpers)

    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:6]
    made = []
    register = _registrar(c, tag, made)
    admins = test_plans.make_admins(db, ("super_admin",))
    h = test_plans.admin_login(c, admins["super_admin"])

    def counts():
        u = c.get("/api/admin/stats/users", headers=h).json()
        b = c.get("/api/admin/broadcast-stats", headers=h).json()
        return {k: u.get(k) for k in ("total_users", "free_users", "plus_users", "pro_users", "paid_users",
                                       "active_users_last_7_days")} | {"bc_total": b.get("total_users"),
                                                                       "bc_push": b.get("users_with_push_enabled")}

    try:
        O = register("Bookowner", "plus")
        db.sql("INSERT INTO user_devices (id, user_id, token, session_expires_at) "
               "VALUES (%s, %s, 'owner-fcm-token', now() + interval '30 days') "
               "ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id", str(uuid.uuid4()), O["id"])
        before = counts()
        r = c.post("/api/family", headers=O["h"], json={"name": f"Books {tag}"})
        fid = ((r.json() if r.status_code == 200 else {}).get("family") or {}).get("id")
        book_id = (db.sql("SELECT id FROM books WHERE family_id = %s", fid) or [{}])[0].get("id") if fid else None
        check(book_id is not None, "book users: creating a family creates its book", f"{r.status_code} {r.text[:200]}")
        if not book_id:
            return
        check(not db.sql("SELECT 1 FROM users WHERE id = %s OR email LIKE %s", book_id, f"%{fid}%"),
              "book users: the family book has no users row (nothing to log in as)")
        # Entries in the family book make it look as active as possible to the counters.
        c.post("/api/transactions", headers={**O["h"], **FAM}, json={
            "type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries",
            "date": datetime.now(UTC).isoformat(), "amount": 5, "currency": "usd"})
        after = counts()
        check(after == before, "book users: admin stats and broadcast counts don't change when a family (and its book) is made",
              {k: (before[k], after[k]) for k in before if before[k] != after[k]})

        r = c.get("/api/admin/users", headers=h, params={"search": fid, "limit": 100})
        check(r.status_code == 200 and r.json() == [], "book users: admin user search by the family id finds no one",
              f"{r.status_code} {r.text[:200]}")
        r = c.get("/api/admin/users", headers=h, params={"limit": 100})
        check(r.status_code == 200 and book_id not in {u.get("id") or u.get("_id") for u in r.json()},
              "book users: the admin user list never lists the book", r.status_code)
        for path in (f"/api/admin/users/{book_id}", f"/api/admin/users/{book_id}/usage"):
            r = c.get(path, headers=h)
            check(r.status_code == 404, f"book users: {path.split(book_id)[1] or 'detail'} admin read of the book id is a 404",
                  r.status_code)

        # The old book-user e-mail logs nothing in, and a token naming the book's id is refused.
        for email in (f"family-{fid}@book.invalid", f"family-{book_id}@book.invalid"):
            r = c.post("/api/auth/login", json={"email": email, "password": "anything"})
            check(r.status_code in (401, 422), "book users: login with the old book-user e-mail is refused",
                  f"{r.status_code} {r.text[:120]}")

        async def mint():
            import auth_routes
            return auth_routes._issue_token({"_id": book_id, "email": f"family-{fid}@book.invalid"})
        r = c.get("/api/auth/me", headers={"Authorization": f"Bearer {_backend_async(mint)}"})
        check(r.status_code == 401, "book users: a token naming the family book is refused (401)", f"{r.status_code} {r.text[:120]}")

        async def jobs():
            from sql import users as users_db
            return book_id in await users_db.user_ids()
        check(not _backend_async(jobs), "book users: user_ids() (scheduler, daily jobs, broadcasts) never holds the book")
    finally:
        _cleanup_people(made)
        db.admins.delete_many({"email": admins["super_admin"]})


BASE = "http://127.0.0.1:8765"


def _code(r, status, code):
    """The response is `status` with {"detail": {"code": code, "message": <non-empty>}}."""
    try:
        d = r.json().get("detail") if r.status_code == status else None
    except ValueError:
        return False
    return isinstance(d, dict) and d.get("code") == code and bool(d.get("message"))


def _registrar(c, tag, made):
    """register(name, plan) -> {"id", "email", "name", "h", "book"}: a verified account on `plan` with its personal
    book's id, its id added to `made`."""
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
        return {"id": uid, "email": email, "name": name, "h": {"Authorization": f"Bearer {token}"},
                "book": _personal_book(uid)}
    return register


def _personal_book(uid):
    """A person's personal book id (None if they have none)."""
    rows = db.sql("SELECT id FROM books WHERE person_id = %s", uid)
    return rows[0]["id"] if rows else None


def _family_book(fid):
    """A family's book id (None if there is no such family)."""
    rows = db.sql("SELECT id FROM books WHERE family_id = %s", fid) if fid else []
    return rows[0]["id"] if rows else None


def _book_flag(book_id):
    """A book's ai_data_stale flag."""
    return db.sql("SELECT ai_data_stale FROM books WHERE id = %s", book_id)[0]["ai_data_stale"]


async def _person_with_book(uid):
    """The person's user dict as get_current_user returns it (with personal_book_id), for calling routes in-process."""
    from sql import users as users_db
    user = await users_db.get_user(uid)
    return {**user, "personal_book_id": _personal_book(uid)}


def _cleanup_people(made):
    """Delete the people in `made` and the families they were in (cascading to their books and everything)."""
    if made:
        db.sql("DELETE FROM families WHERE id IN (SELECT family_id FROM family_members WHERE user_id = ANY(%s))", made)
        db.sql("DELETE FROM users WHERE id = ANY(%s)", made)


def section_family_rules():
    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:6]
    made = []
    register = _registrar(c, tag, made)

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

    def race(*calls):
        """Fire (method, path, headers, json) requests at the same moment, each on its own connection -> responses."""
        import threading
        from concurrent.futures import ThreadPoolExecutor
        gate = threading.Barrier(len(calls))

        def go(call):
            method, path, headers, body = call
            with httpx.Client(base_url=BASE, timeout=60) as cc:
                gate.wait()
                return cc.request(method, path, headers=headers, json=body)
        with ThreadPoolExecutor(len(calls)) as ex:
            return list(ex.map(go, calls))

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
        want_by_plan = {"free": {"max_members": 0, "max_placeholders": 0}, "plus": {"max_members": 6, "max_placeholders": 20},
                        "pro": {"max_members": 6, "max_placeholders": 20}}
        for who, label in ((A, "Plus"), (B, "Free")):
            p = c.get("/api/plan", headers=who["h"]).json().get("family_by_plan")
            check(p == want_by_plan, f"family rules: GET /api/plan gives a {label} user every plan's family limits", p)

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
        book = db.sql("SELECT kind FROM books WHERE family_id = %s", fid)
        check(book and book[0]["kind"] == "family", "family rules: the family has its own family book", book)
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
        r = c.delete(f"/api/family/members/{a_mid}", headers=A["h"])
        check(_code(r, 403, "not_allowed"), "family rules: the owner can't remove themselves", r.status_code)
        row = db.sql("SELECT role, status, left_at FROM family_members WHERE id = %s", a_mid)
        check(row and row[0]["role"] == "owner" and row[0]["status"] == "active" and row[0]["left_at"] is None,
              "family rules: after the refused leave/remove the owner is still the active owner", row)

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
        members = fam(A).json().get("members", [])
        rows = [x for x in members if x["id"] == (mama or {}).get("id")]
        check(r is not None and r.status_code == 200 and len(rows) == 1
              and rows[0]["kind"] == "account" and rows[0]["status"] == "active" and rows[0]["role"] == "member",
              "family rules: accepting a linked invite turns the placeholder into the account (same member id, one row)", rows)
        check(len(rows) == 1 and rows[0]["display_name"] == M["name"]
              and not [x for x in members if x["display_name"] == "Ma Ma"],
              "family rules: the claimed placeholder takes the person's own name at once (an account member's name is "
              "their own), not 'Ma Ma'", [(x["display_name"], x["kind"]) for x in members])
        check(mama is not None and (fam(M).json().get("me") or {}).get("member_id") == mama["id"],
              "family rules: the new member is that row")
        for who, label in ((B, "an admin"), (A, "the owner")):
            r = c.patch(f"/api/family/members/{(mama or {}).get('id')}", headers=who["h"], json={"display_name": "Auntie"})
            check(_code(r, 403, "not_allowed"), f"family rules: {label} can't rename an active account member (their name is their own)",
                  f"{r.status_code} {r.text[:200]}")

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
        p3 = member_of(fam(A).json(), name="P3") or {"id": "missing-p3"}
        r = c.patch(f"/api/family/members/{p3['id']}", headers=B["h"], json={"display_name": "Grandma"})
        check(r.status_code == 200 and (member_of(r.json(), name="Grandma") or {}).get("id") == p3["id"],
              "family rules: an admin renames a placeholder", f"{r.status_code} {r.text[:200]}")

        # ---- only the owner removes an admin ----
        d_mid = (fam(D).json().get("me") or {}).get("member_id")
        r = c.patch(f"/api/family/members/{d_mid}", headers=A["h"], json={"role": "admin"})
        check(r.status_code == 200, "family rules: the owner makes a second admin", r.status_code)
        r = c.delete(f"/api/family/members/{d_mid}", headers=B["h"])
        check(_code(r, 403, "not_allowed") and (member_of(fam(A).json(), name="Daw") or {}).get("status") == "active",
              "family rules: an admin can't remove another admin", f"{r.status_code} {r.text[:200]}")
        r = c.delete(f"/api/family/members/{d_mid}", headers=A["h"])
        drow = member_of(fam(A).json(), name="Daw") or {}
        check(r.status_code == 200 and drow.get("status") == "former" and drow.get("role") == "admin",
              "family rules: the owner removes an admin (former, role kept)", f"{r.status_code} {drow}")

        # ---- removing placeholders: untagged deleted, tagged kept as former ----
        view = fam(A).json()
        p1, p2 = member_of(view, name="P1") or {"id": "missing-p1"}, member_of(view, name="P2") or {"id": "missing-p2"}
        r = c.delete(f"/api/family/members/{p1['id']}", headers=A["h"])
        gone = db.sql("SELECT count(*) n FROM family_members WHERE id = %s", p1["id"])[0]["n"]
        check(r.status_code == 200 and gone == 0 and member_of(fam(A).json(), name="P1") is None,
              "family rules: removing a placeholder with no entries deletes it", f"{r.status_code} {gone}")
        book_id = _family_book(fid)
        tx = str(uuid.uuid4())
        db.sql("INSERT INTO transactions (id, book_id, type, main_category, sub_category, amount, currency, date) "
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
        r = c.patch(f"/api/family/members/{c_mid}", headers=B["h"], json={"display_name": "Chit (left)"})
        check(r.status_code == 200 and (member_of(r.json(), name="Chit (left)") or {}).get("id") == c_mid,
              "family rules: an admin renames a former member", f"{r.status_code} {r.text[:200]}")

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

        # ---- the owner's plan lapses: read-only, but the family can still be repaired ----
        H = register("Htun")
        inv_g = invite(X, G["email"]).json()
        inv_h = invite(X, H["email"]).json()
        r = c.post(f"/api/family/invites/{inv_g.get('id')}/accept", headers=G["h"])
        g_mid = (fam(G).json().get("me") or {}).get("member_id")
        check(r.status_code == 200 and g_mid, "family rules: a member joins the Pro family", f"{r.status_code} {r.text[:200]}")
        db.sql("UPDATE users SET subscription_expires_at = now() - interval '1 minute' WHERE id = %s", X["id"])
        vx = fam(X).json()
        check((vx.get("family") or {}).get("read_only") is True, "family rules: the owner's plan lapsed, so the family is read-only",
              vx.get("family"))
        r = invite(X, f"later-{tag}@example.com")
        check(_code(r, 403, "family_read_only"), "family rules: read-only family: invite is family_read_only", f"{r.status_code} {r.text[:200]}")
        r = c.post("/api/family/placeholders", headers=X["h"], json={"display_name": "Grandpa"})
        check(_code(r, 403, "family_read_only"), "family rules: read-only family: add placeholder is family_read_only",
              f"{r.status_code} {r.text[:200]}")
        r = c.post(f"/api/family/invites/{inv_h.get('id')}/accept", headers=H["h"])
        st = db.sql("SELECT status FROM family_invites WHERE id = %s", inv_h.get("id"))
        check(_code(r, 403, "family_read_only") and st and st[0]["status"] == "pending" and fam(H).json() == {"family": None},
              "family rules: read-only family: accepting an invite is family_read_only (the invite stays pending)",
              f"{r.status_code} {r.text[:200]} {st}")
        r = c.patch("/api/family", headers=X["h"], json={"name": XNAME})
        check(r.status_code == 200, "family rules: read-only family: renaming still works", r.status_code)
        r = c.post("/api/family/transfer-ownership", headers=X["h"], json={"member_id": g_mid})
        check(r.status_code == 200 and (fam(G).json().get("me") or {}).get("role") == "owner",
              "family rules: read-only family: handing over ownership still works", f"{r.status_code} {r.text[:200]}")
        r = c.delete(f"/api/family/invites/{inv_h.get('id')}", headers=X["h"])
        check(r.status_code == 200, "family rules: read-only family: an admin can still cancel an invite", f"{r.status_code} {r.text[:200]}")
        r = c.post("/api/family/leave", headers=X["h"])
        check(r.status_code == 200 and fam(X).json() == {"family": None}, "family rules: read-only family: leaving still works",
              r.status_code)

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

        row = db.sql("SELECT count(*) n FROM family_members WHERE family_id = %s AND role = 'owner' AND status = 'former'", fid)
        check(row[0]["n"] == 0, "family rules: no former member holds the owner role", row)

        # ---- a former account row can only be taken over by its own person ----
        r = invite(B, G["email"], link=a_mid)
        check(_code(r, 400, "invite_invalid"), "family rules: an invite linked to someone else's former row is invite_invalid",
              f"{r.status_code} {r.text[:200]}")
        r = invite(B, f"nobody2-{tag}@example.com", link=a_mid)
        check(_code(r, 400, "invite_invalid"), "family rules: ... also for an e-mail without an account", f"{r.status_code} {r.text[:200]}")

        # ---- a former member comes back as the same member ----
        r = invite(B, A["email"], link=a_mid)
        check(r.status_code == 200, "family rules: a former member can be invited again, linked to their own row",
              f"{r.status_code} {r.text[:200]}")
        _, r = accept_from(A, FNAME)
        va = fam(A).json()
        check(r is not None and r.status_code == 200 and (va.get("me") or {}).get("member_id") == a_mid
              and (member_of(va, user=A) or {}).get("status") == "active"
              and len([x for x in va.get("members", []) if x["display_name"] == "Aye"]) == 1,
              "family rules: re-accepting reactivates the same member id", va.get("me"))
        c.post("/api/family/leave", headers=A["h"])
        r = invite(B, A["email"])
        _, r = accept_from(A, FNAME)
        va = fam(A).json()
        check(r is not None and r.status_code == 200 and (va.get("me") or {}).get("member_id") == a_mid,
              "family rules: an unlinked invite also reactivates the person's former row", va.get("me"))

        # ---- concurrency: handovers and leaves never leave the family without exactly one active owner ----
        m_mid, e_mid = ((fam(u).json().get("me") or {}).get("member_id") for u in (M, E))
        by_user = {u["id"]: u for u in (A, B, M, E)}

        def owners():
            return db.sql("SELECT user_id, status FROM family_members WHERE family_id = %s AND role = 'owner'", fid)

        def one_owner():
            o = owners()
            return len(o) == 1 and o[0]["status"] == "active"

        def back_to_b():
            o = owners()
            if len(o) == 1 and o[0]["user_id"] != B["id"]:
                c.post("/api/family/transfer-ownership", headers=by_user[o[0]["user_id"]]["h"], json={"member_id": b_mid})
            return one_owner() and owners()[0]["user_id"] == B["id"]

        rs = race(("POST", "/api/family/transfer-ownership", B["h"], {"member_id": m_mid}),
                  ("POST", "/api/family/transfer-ownership", B["h"], {"member_id": e_mid}))
        check(sorted(r.status_code for r in rs) == [200, 403] and any(_code(r, 403, "not_allowed") for r in rs) and one_owner(),
              "family rules: two concurrent handovers: one succeeds, the other is not_allowed, one active owner",
              ([(r.status_code, r.text[:120]) for r in rs], owners()))
        check(back_to_b(), "family rules: ownership handed back to B", owners())
        rs = race(("POST", "/api/family/transfer-ownership", B["h"], {"member_id": e_mid}),
                  ("POST", "/api/family/leave", E["h"], None))
        t_r, l_r = rs
        coded = ((t_r.status_code == 200 and _code(l_r, 409, "owner_must_hand_over"))
                 or (l_r.status_code == 200 and _code(t_r, 403, "not_allowed")))
        check(coded and one_owner(), "family rules: a handover racing the target's leave: one wins, the other is coded, one active owner",
              ([(r.status_code, r.text[:120]) for r in rs], owners()))
        check(back_to_b(), "family rules: ownership handed back to B again", owners())

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
        _cleanup_people(made)


FAM = {"X-Book": "family"}


def section_book_scope():
    """Every financial route reads and writes the book the request names (X-Book), never another one."""
    backend = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend")
    if backend not in sys.path:
        sys.path.insert(0, backend)
    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:6]
    made = []
    register = _registrar(c, tag, made)
    now = datetime.now(UTC).replace(microsecond=0)
    som = now.replace(day=1, hour=0, minute=0, second=0)

    def H(u, family=False):
        return {**u["h"], **(FAM if family else {})}

    def tx(u, family=False, **kw):
        body = {"type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries",
                "date": now.isoformat(), "amount": 10, "currency": "usd", "description": "scope"} | kw
        return c.post("/api/transactions", headers=H(u, family), json=body)

    def budget(u, family=False, name="B"):
        return c.post("/api/budgets", headers=H(u, family), json={
            "name": name, "period": "monthly", "start_date": som.isoformat(), "currency": "usd", "total_budget": 100,
            "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 100}]})

    def goal(u, family=False, name="G"):
        return c.post("/api/goals", headers=H(u, family), json={
            "name": name, "target_amount": 500, "goal_type": "savings", "currency": "usd"})

    def ids(r):
        return sorted(x["id"] for x in r.json()) if r.status_code == 200 else (r.status_code, r.text[:200])

    def same_for_both(path, method="GET", body=None, strip=()):
        """(Mum's body, Dad's body) for a family-mode request, with volatile keys removed."""
        out = []
        for u in (M, D):
            r = c.request(method, path, headers=H(u, True), json=body)
            j = r.json() if r.status_code == 200 else (r.status_code, r.text[:200])
            if isinstance(j, dict):
                j = {k: v for k, v in j.items() if k not in strip}
            out.append(j)
        return out

    book_flag = _book_flag

    try:
        M = register("Mum", "plus")
        D = register("Dad", "free")
        O = register("Outsider", "free")
        r = c.post("/api/family", headers=M["h"], json={"name": f"Scope family {tag}"})
        fid = (r.json().get("family") or {}).get("id") if r.status_code == 200 else None
        m_mid = (r.json().get("me") or {}).get("member_id") if r.status_code == 200 else None
        book_id = _family_book(fid)
        c.post("/api/family/invites", headers=M["h"], json={"email": D["email"]})
        inv = next(iter(c.get("/api/family/invites/mine", headers=D["h"]).json().get("invites", [])), None)
        r = c.post(f"/api/family/invites/{inv['id']}/accept", headers=D["h"]) if inv else None
        check(r is not None and r.status_code == 200 and book_id, "book scope: Mum's family with Dad as a member",
              r is not None and f"{r.status_code} {r.text[:200]}")
        d_mid = (c.get("/api/family", headers=D["h"]).json().get("me") or {}).get("member_id")

        # ---- personal records for each, family records from both ----
        mum_tx = [tx(M, amount=a).json()["id"] for a in (11, 12)]
        dad_tx = [tx(D, amount=21).json()["id"]]
        mum_in = tx(M, type="inflow", main_category="Employment Income", sub_category="Salary", amount=900).json()["id"]
        mum_budget, dad_budget = budget(M, name="Mum B").json()["id"], budget(D, name="Dad B").json()["id"]
        mum_goal, dad_goal = goal(M, name="Mum G").json()["id"], goal(D, name="Dad G").json()["id"]
        rec = c.post("/api/transactions", headers=H(D), json={
            "type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries", "date": now.isoformat(),
            "amount": 5, "currency": "usd", "recurrence": {"enabled": True, "config": {"frequency": "monthly", "day_of_month": 1}}})
        dad_rec = rec.json().get("id") if rec.status_code == 200 else None
        dad_report = str(uuid.uuid4())
        db.sql("INSERT INTO custom_insights (id, book_id, start_date, end_date, status, content) "
               "VALUES (%s, %s, current_date - 7, current_date, 'ready', 'Dad''s private report')", dad_report, D["book"])

        db.sql("UPDATE books SET ai_data_stale = false WHERE id IN (%s, %s)", M["book"], book_id)
        r = tx(M, True, amount=40, currency="mmk")
        fam_tx = [r.json().get("id")] if r.status_code == 200 else []
        check(r.status_code == 200 and r.json().get("book_id") == book_id,
              "book scope: a family POST transaction is stored under the book", f"{r.status_code} {r.text[:200]}")
        check(book_flag(book_id) is True and book_flag(M["book"]) is False,
              "book scope: a family write marks the book's AI data stale, not the person's")
        row = db.sql("SELECT added_by_member_id FROM transactions WHERE id = %s", fam_tx[0])[0] if fam_tx else {}
        check(row.get("added_by_member_id") == m_mid, "book scope: a family entry records who added it", row)
        r = tx(D, True, type="inflow", main_category="Employment Income", sub_category="Salary", amount=1000)
        fam_tx.append(r.json().get("id"))
        r = c.post("/api/transactions/batch-create", headers=H(D, True), json=[
            {"type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries",
             "date": now.isoformat(), "amount": 7, "currency": "usd"}])
        check(r.status_code == 200 and all(t["book_id"] == book_id for t in r.json()),
              "book scope: a family batch-create is stored under the book", f"{r.status_code} {r.text[:200]}")
        fam_tx += [t["id"] for t in r.json()] if r.status_code == 200 else []
        fam_budget = budget(M, True, name="Family B").json().get("id")
        r = goal(M, True, name="Family G")
        fam_goal = r.json().get("id")
        check(r.status_code == 200 and r.json().get("book_id") == book_id, "book scope: a family goal is stored under the book",
              f"{r.status_code} {r.text[:200]}")
        r = c.post(f"/api/goals/{fam_goal}/contribute", headers=H(D, True), json={"amount": 10})
        check(r.status_code == 200, "book scope: Dad contributes to the family goal from the family balance",
              f"{r.status_code} {r.text[:200]}")

        # ---- Family mode: Mum and Dad see the same book, and only the family's records ----
        time.sleep(1.5)  # budget recompute runs in the background
        lists = same_for_both("/api/transactions")
        check(lists[0] == lists[1] and sorted(t["id"] for t in lists[0]) == sorted(fam_tx),
              "book scope: family transactions are identical for Mum and Dad and only the family's",
              (len(lists[0]) if isinstance(lists[0], list) else lists[0], len(fam_tx)))
        bal = same_for_both("/api/dashboard/balance")
        usd = (bal[0].get("balances") or {}).get("usd", {}) if isinstance(bal[0], dict) else {}
        check(bal[0] == bal[1] and abs(usd.get("balance", 0) - 993) < 1e-9 and abs(usd.get("allocated_to_goals", 0) - 10) < 1e-9
              and set(bal[0].get("balances", {})) == {"usd", "mmk"},
              "book scope: the family balance is identical for both and counts only family entries", bal[0])
        for path, want in (("/api/budgets", [fam_budget]), ("/api/goals", [fam_goal])):
            got = same_for_both(path)
            check(got[0] == got[1] and sorted(x["id"] for x in got[0]) == want,
                  f"book scope: GET {path} is identical for both and only the family's", got[0])
        for path in ("/api/budgets/summary/all-currencies", "/api/goals/summary", "/api/goals/summary/all-currencies",
                     "/api/budgets/summary"):
            got = same_for_both(path)
            check(isinstance(got[0], dict) and got[0] == got[1]
                  and got[0].get("total_goals", got[0].get("total_budgets")) == 1,
                  f"book scope: {path} is identical for both and counts only the family's", got)
        body = {"period": "month"}
        rep = same_for_both("/api/reports/generate-multi-currency", "POST", body, strip=("generated_at", "end_date"))
        check(rep[0] == rep[1] and rep[0].get("total_transactions") == len(fam_tx)
              and [g["goal_id"] for g in rep[0].get("goals", [])] == [fam_goal],
              "book scope: the multi-currency report is identical for both and only the family's", rep[0])
        rep = same_for_both("/api/reports/generate", "POST", body | {"currency": "usd"}, strip=("generated_at", "end_date"))
        check(rep[0] == rep[1] and abs(rep[0].get("total_outflow", -1) - 7) < 1e-9 and rep[0].get("total_inflow") == 1000,
              "book scope: the USD report is identical for both and only the family's", rep[0])

        # ---- Personal mode: each sees only their own records ----
        check(ids(c.get("/api/transactions", headers=H(M))) == sorted(mum_tx + [mum_in]),
              "book scope: Mum's personal list is only her own entries")
        r = c.get("/api/transactions", headers=H(D))
        dl = r.json() if r.status_code == 200 else []
        check(set(dad_tx + [dad_rec]) <= {t["id"] for t in dl} and all(t["book_id"] == D["book"] for t in dl),
              "book scope: Dad's personal list is only his own entries", [(t["id"], t.get("book_id")) for t in dl])
        check(ids(c.get("/api/budgets", headers=H(M))) == [mum_budget] and ids(c.get("/api/goals", headers=H(D))) == [dad_goal],
              "book scope: personal budgets and goals are each person's own")
        b = c.get("/api/dashboard/balance", headers=H(M), params={"currency": "usd"}).json()
        check(abs(b.get("balance", 0) - (900 - 23)) < 1e-9, "book scope: Mum's personal balance is only her own", b)

        # ---- Review Focus 1: no record is reachable by id from another book ----
        targets = {
            "Dad's personal transaction": (f"/api/transactions/{dad_tx[0]}", {"amount": 1}),
            "Dad's personal budget": (f"/api/budgets/{dad_budget}", {"name": "pwned"}),
            "Dad's personal goal": (f"/api/goals/{dad_goal}", {"name": "pwned"}),
        }
        for family in (False, True):
            mode = "family" if family else "personal"
            for label, (path, put) in targets.items():
                codes = [c.get(path, headers=H(M, family)).status_code, c.put(path, headers=H(M, family), json=put).status_code,
                         c.delete(path, headers=H(M, family)).status_code]
                check(codes == [404, 404, 404], f"book scope: Mum GET/PUT/DELETE of {label} in {mode} mode is 404", codes)
            codes = [c.post(f"/api/goals/{dad_goal}/contribute", headers=H(M, family), json={"amount": 1}).status_code,
                     c.post(f"/api/budgets/{dad_budget}/refresh", headers=H(M, family)).status_code,
                     c.post(f"/api/transactions/{dad_rec}/disable-recurrence", headers=H(M, family)).status_code,
                     c.post(f"/api/transactions/{dad_rec}/disable-parent-recurrence", headers=H(M, family)).status_code,
                     c.get(f"/api/custom-insights/{dad_report}", headers=H(M, family)).status_code,
                     c.delete(f"/api/custom-insights/{dad_report}", headers=H(M, family)).status_code]
            check(codes == [404] * 6, f"book scope: contribute / refresh / recurrence / custom insight by id of Dad's in {mode} mode is 404", codes)
        for label, path, put in ((("Mum's own personal transaction", f"/api/transactions/{mum_tx[0]}", {"amount": 1}),
                                  ("Mum's own personal budget", f"/api/budgets/{mum_budget}", {"name": "x"}),
                                  ("Mum's own personal goal", f"/api/goals/{mum_goal}", {"name": "x"}))):
            codes = [c.get(path, headers=H(M, True)).status_code, c.put(path, headers=H(M, True), json=put).status_code,
                     c.delete(path, headers=H(M, True)).status_code]
            check(codes == [404, 404, 404], f"book scope: {label} by id with X-Book: family is 404", codes)
        r = c.get(f"/api/custom-insights/{dad_report}", headers=H(D, True))
        check(r.status_code == 404, "book scope: Dad's own personal custom insight is 404 in family mode", r.status_code)
        r = c.get(f"/api/transactions/{fam_tx[0]}", headers=H(M))
        check(r.status_code == 404, "book scope: a family entry by id in personal mode is 404", r.status_code)
        survived = (db.sql("SELECT count(*) n FROM transactions WHERE id = ANY(%s)", dad_tx + [mum_tx[0]])[0]["n"],
                    db.sql("SELECT count(*) n FROM budgets WHERE id = ANY(%s)", [dad_budget, mum_budget])[0]["n"],
                    db.sql("SELECT count(*) n FROM goals WHERE id = ANY(%s) AND name NOT LIKE 'pwned'", [dad_goal, mum_goal])[0]["n"],
                    db.sql("SELECT recurrence_enabled e FROM transactions WHERE id = %s", dad_rec)[0]["e"])
        check(survived == (2, 2, 2, True), "book scope: none of those requests changed a record", survived)
        r = c.get(f"/api/custom-insights/{dad_report}", headers=H(D))
        check(r.status_code == 200, "book scope: Dad still reads his own personal custom insight", r.status_code)

        # ---- insights: the book's, gated by the owner's plan ----
        r = c.get("/api/insights", headers=H(M, True), params={"insight_type": "weekly"})
        mum_ins = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and mum_ins.get("book_id") == book_id,
              "book scope: a family weekly insight is the book's", f"{r.status_code} {r.text[:200]}")
        r = c.get("/api/insights", headers=H(D, True), params={"insight_type": "weekly"})
        check(r.status_code == 200 and r.json().get("id") == mum_ins.get("id"),
              "book scope: Dad (Free) sees the same family weekly insight (the owner's plan gates it)", f"{r.status_code} {r.text[:200]}")
        r = c.get("/api/insights", headers=H(D), params={"insight_type": "weekly"})
        check(_code(r, 403, "plan_feature_locked"), "book scope: Dad's personal weekly insight stays locked on his Free plan",
              r.status_code)
        r = c.get("/api/custom-insights", headers=H(M, True))
        check(r.status_code == 200 and r.json().get("reports") == [], "book scope: the family custom-insight list has no personal reports",
              r.text[:200])

        # A family custom insight is the book's row but the asker's use: a give-back must reach the asker's counters.
        async def give_back_target():
            import custom_insights_service as cis
            from plans import quota
            r = quota.Reservation(D["id"], [("custom_insight", "month", now.date())])
            fam_row = {"book_id": book_id, "counter_keys": cis.counter_keys(r, family=True)}
            own_row = {"book_id": D["book"], "counter_keys": cis.counter_keys(r, family=False)}
            return ((await cis._reservation(fam_row)).user_id, len(fam_row["counter_keys"][0]),
                    (await cis._reservation(own_row)).user_id, len(own_row["counter_keys"][0]))
        got = _backend_async(give_back_target)
        check(got == (D["id"], 4, D["id"], 3),
              "book scope: a family custom insight's counter_keys name the asker (personal ones are unchanged)", got)

        # ---- R10: family insights never count against anyone ----
        r = c.get("/api/insights", headers=H(M, True), params={"insight_type": "monthly"})
        fam_monthly = r.json().get("id") if r.status_code == 200 else None
        check(r.status_code == 200 and r.json().get("book_id") == book_id, "book scope: a family monthly insight is the book's",
              f"{r.status_code} {r.text[:200]}")

        def insight_uses(*uids):
            return db.sql("SELECT coalesce(sum(used), 0) n FROM usage_counters WHERE user_id = ANY(%s) "
                          "AND feature LIKE 'insight%%'", list(uids))[0]["n"]

        def book_insights(kind=None):
            return db.sql("SELECT count(*) n FROM insights WHERE book_id = %s AND (%s::text IS NULL OR insight_type = %s)",
                          book_id, kind, kind)[0]["n"]

        async def family_generation_uncounted():
            """In-process, with Plus's weekly and monthly insights made counted: a family regenerate (Mum) and a family
            GET that has to generate (Dad, Free) leave both people's insight counters alone."""
            import main as backend_main
            from chat_models import AIProvider
            from families.book import get_book
            from plans import store
            from plans.catalog import Limit
            calls = []

            async def fake_generate(data_id, insight_type):
                calls.append(data_id)
                return {"_id": str(uuid.uuid4()), "book_id": data_id, "content": "## Fake family insight",
                        "generated_at": datetime.now(UTC), "is_placeholder": False}

            orig_limits, orig_generate = store.limits, backend_main._generate_insight

            def counted_limits(plan):
                lim = orig_limits(plan)
                if plan in ("plus", "pro"):
                    lim["insight_weekly"] = Limit("counted", 50, "week")
                    lim["insight_monthly"] = Limit("counted", 50, "month")
                return lim
            store.limits, backend_main._generate_insight = counted_limits, fake_generate
            try:
                mum_book = await get_book(current_user=await _person_with_book(M["id"]), x_book="family")
                dad_book = await get_book(current_user=await _person_with_book(D["id"]), x_book="family")
                before = insight_uses(M["id"], D["id"])
                await backend_main.regenerate_insights(language="en", ai_provider=AIProvider.OPENAI,
                                                       insight_type="weekly", book=mum_book)
                db.sql("DELETE FROM insights WHERE book_id = %s AND insight_type = 'weekly'", book_id)
                await backend_main.get_insights(language="en", ai_provider=AIProvider.OPENAI, insight_type="weekly",
                                                book=dad_book)
                return before, insight_uses(M["id"], D["id"]), calls
            finally:
                store.limits, backend_main._generate_insight = orig_limits, orig_generate
        try:
            before, after, calls = _backend_async(family_generation_uncounted)
        except Exception as e:  # noqa: BLE001
            before, after, calls = None, repr(e)[:200], []
        check(before is not None and before == after and calls == [book_id, book_id],
              "book scope: a family regenerate (Mum) and a generating family GET (Dad) count against neither",
              (before, after, calls))

        # ---- R21 (M2): the family PDF is generated for the family, a personal one for the person ----
        async def pdf_names():
            from io import BytesIO
            import report_routes
            from families.book import get_book
            from report_models import ReportRequest
            names = []
            orig = report_routes.generate_financial_report_pdf

            def fake_pdf(report, user_name, offset=0, currency=None):
                names.append(user_name)
                return BytesIO(b"%PDF-fake")
            report_routes.generate_financial_report_pdf = fake_pdf
            try:
                req = ReportRequest(period="month", currency="usd")
                for x_book in ("family", "personal"):
                    book = await get_book(current_user=await _person_with_book(D["id"]), x_book=x_book)
                    await report_routes._download_report_pdf(req, book)
            finally:
                report_routes.generate_financial_report_pdf = orig
            return names
        try:
            names = _backend_async(pdf_names)
        except Exception as e:  # noqa: BLE001
            names = repr(e)[:300]
        check(names == [f"Scope family {tag}", "Dad"],
              "book scope: the family PDF says Generated For the family's name, a personal PDF the person's", names)

        # ---- R21 (M4): the shared weekly/monthly family insights are deleted and regenerated by admins only ----
        stored = book_insights()
        r = c.delete("/api/insights", headers=H(D, True), params={"insight_type": "weekly"})
        check(_code(r, 403, "not_allowed") and book_insights() == stored,
              "book scope: a member (Dad) can't delete the family's insights (403 not_allowed)", f"{r.status_code} {r.text[:200]}")
        db.sql("UPDATE users SET subscription_type = 'plus', subscription_expires_at = now() + interval '30 days' "
               "WHERE id = %s", D["id"])  # so only the admin rule can refuse him
        try:
            r = c.post("/api/insights/regenerate", headers=H(D, True), params={"insight_type": "weekly"})
            check(_code(r, 403, "not_allowed") and book_insights() == stored,
                  "book scope: a member (Dad, on Plus) can't regenerate the family's insights (403 not_allowed)",
                  f"{r.status_code} {r.text[:200]}")
        finally:
            db.sql("UPDATE users SET subscription_type = 'free', subscription_expires_at = NULL WHERE id = %s", D["id"])
        r = c.delete("/api/insights", headers=H(D), params={"insight_type": "weekly"})
        check(r.status_code == 200, "book scope: Dad still deletes his own personal insights", f"{r.status_code} {r.text[:200]}")
        r = c.post("/api/insights/regenerate", headers=H(M, True), params={"insight_type": "weekly"})
        check(r.status_code == 200 and r.json().get("book_id") == book_id,
              "book scope: an admin (Mum) regenerates the family's weekly insight", f"{r.status_code} {r.text[:200]}")
        r = c.delete("/api/insights", headers=H(M, True), params={"insight_type": "weekly"})
        check(r.status_code == 200 and book_insights("weekly") == 0,
              "book scope: an admin (Mum) deletes the family's weekly insights", f"{r.status_code} {r.text[:200]}")

        # ---- headers ----
        r = c.get("/api/transactions", headers=H(O, True))
        check(_code(r, 409, "no_family"), "book scope: X-Book: family outside a family is 409 no_family", f"{r.status_code} {r.text[:200]}")
        r = c.get("/api/transactions", headers={**O["h"], "X-Book": "personal"})
        check(r.status_code == 200, "book scope: X-Book: personal is the personal book", r.status_code)
        r = c.get("/api/transactions", headers={**O["h"], "X-Book": "someone-else"})
        check(_code(r, 400, "invalid_book"), "book scope: an unknown X-Book value is 400 invalid_book", f"{r.status_code} {r.text[:200]}")

        # ---- Review Focus 3: the owner's plan lapses ----
        db.sql("UPDATE users SET subscription_expires_at = now() - interval '1 day' WHERE id = %s", M["id"])
        for who in (M, D):
            r = tx(who, True)
            check(_code(r, 403, "family_read_only"), f"book scope: a lapsed family refuses {who['name']}'s family POST transaction",
                  f"{r.status_code} {r.text[:200]}")
        r = budget(M, True)
        check(_code(r, 403, "family_read_only"), "book scope: a lapsed family refuses a new budget", r.status_code)
        r = goal(M, True)
        check(_code(r, 403, "family_read_only"), "book scope: a lapsed family refuses a new goal", r.status_code)
        r = c.put(f"/api/transactions/{fam_tx[0]}", headers=H(M, True), json={"amount": 99})
        check(_code(r, 403, "family_read_only"), "book scope: a lapsed family refuses an edit", r.status_code)
        r = c.delete(f"/api/transactions/{fam_tx[0]}", headers=H(M, True))
        check(_code(r, 403, "family_read_only"), "book scope: a lapsed family refuses a delete", r.status_code)
        r = c.post(f"/api/goals/{fam_goal}/contribute", headers=H(D, True), json={"amount": 1})
        check(_code(r, 403, "family_read_only"), "book scope: a lapsed family refuses a goal contribution", r.status_code)
        check(ids(c.get("/api/transactions", headers=H(D, True))) == sorted(fam_tx),
              "book scope: family GETs still work while read-only")
        r = c.get("/api/dashboard/balance", headers=H(M, True))
        check(r.status_code == 200, "book scope: the family balance still reads while read-only", r.status_code)
        check(tx(M).status_code == 200 and tx(D).status_code == 200, "book scope: personal writes still work while the family is read-only")

        # R10: a read-only family shows what is stored and never generates or counts.
        uses, stored = insight_uses(D["id"]), book_insights()
        r = c.get("/api/insights", headers=H(D, True), params={"insight_type": "monthly"})
        check(r.status_code == 200 and r.json().get("id") == fam_monthly and insight_uses(D["id"]) == uses
              and book_insights() == stored,
              "book scope: read-only: Dad's family monthly GET shows the stored insight, generates and counts nothing",
              f"{r.status_code} {r.text[:200]}")
        db.sql("DELETE FROM insights WHERE book_id = %s AND insight_type = 'monthly'", book_id)
        stored = book_insights()
        r = c.get("/api/insights", headers=H(D, True), params={"insight_type": "monthly"})
        check(_code(r, 403, "family_read_only") and insight_uses(D["id"]) == uses and book_insights() == stored,
              "book scope: read-only with nothing stored: family monthly GET is family_read_only, nothing generated or counted",
              (f"{r.status_code} {r.text[:200]}", insight_uses(D["id"]), uses, book_insights(), stored))
        r = c.post("/api/insights/regenerate", headers=H(M, True), params={"insight_type": "monthly"})
        check(_code(r, 403, "family_read_only") and book_insights() == stored,
              "book scope: read-only: a family regenerate is family_read_only", f"{r.status_code} {r.text[:200]}")
        r = c.post("/api/custom-insights", headers=H(M, True),
                   json={"start_date": (now.date() - timedelta(days=7)).isoformat(), "end_date": now.date().isoformat()})
        check(_code(r, 403, "family_read_only"), "book scope: read-only: creating a family custom insight is family_read_only",
              f"{r.status_code} {r.text[:200]}")

        db.sql("UPDATE users SET subscription_expires_at = now() + interval '30 days' WHERE id = %s", M["id"])
        check(tx(M, True).status_code == 200, "book scope: renewing the owner's plan makes the family writable again")

        # R10: a family custom report is shared, so only an admin deletes it.
        fam_report = str(uuid.uuid4())
        db.sql("INSERT INTO custom_insights (id, book_id, start_date, end_date, status, content) "
               "VALUES (%s, %s, current_date - 7, current_date, 'ready', 'Family report')", fam_report, book_id)
        r = c.delete(f"/api/custom-insights/{fam_report}", headers=H(D, True))
        check(_code(r, 403, "not_allowed"), "book scope: a member can't delete a family custom report (not_allowed)",
              f"{r.status_code} {r.text[:200]}")
        r = c.delete(f"/api/custom-insights/{fam_report}", headers=H(M, True))
        check(r.status_code == 200, "book scope: an admin (the owner) deletes a family custom report", f"{r.status_code} {r.text[:200]}")
        r = c.delete(f"/api/custom-insights/{dad_report}", headers=H(D))
        check(r.status_code == 200, "book scope: Dad still deletes his own personal custom report", f"{r.status_code} {r.text[:200]}")

        # ---- Review Focus 4: Dad is removed while his app is open ----
        r = c.delete(f"/api/family/members/{d_mid}", headers=M["h"])
        check(r.status_code == 200, "book scope: Mum removes Dad", f"{r.status_code} {r.text[:200]}")
        r = c.get("/api/transactions", headers=H(D, True))
        check(_code(r, 409, "no_family"), "book scope: Dad's next family request is 409 no_family", f"{r.status_code} {r.text[:200]}")
        r = tx(D, True)
        check(_code(r, 409, "no_family"), "book scope: Dad can no longer write to the family book", r.status_code)
        r = c.get("/api/transactions", headers=H(D))
        check(r.status_code == 200 and dad_tx[0] in {t["id"] for t in r.json()},
              "book scope: Dad's personal book still works after removal", r.status_code)
    finally:
        _cleanup_people(made)


def section_entries_breakdown():
    """Who added each family entry, who it was for, who may change it, and the per-person breakdown (Task 5)."""
    backend = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend")
    if backend not in sys.path:
        sys.path.insert(0, backend)
    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:6]
    made = []
    register = _registrar(c, tag, made)
    today = datetime.now(UTC).date()
    d0 = today - timedelta(days=10)  # the breakdown window is d0 .. d0 + 1, away from today's recurring children

    def at(day, hour=12, minute=0, second=0):
        return datetime(day.year, day.month, day.day, hour, minute, second, tzinfo=UTC).isoformat()

    def H(u, family=False):
        return {**u["h"], **(FAM if family else {})}

    def tx(u, family=True, **kw):
        body = {"type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries",
                "date": at(d0), "amount": 10, "currency": "usd", "description": "entries"} | kw
        return c.post("/api/transactions", headers=H(u, family), json=body)

    def breakdown(u, currency, start=d0, end=None, family=False):
        end = end or d0 + timedelta(days=1)
        return c.get("/api/family/breakdown", headers=H(u, family),
                     params={"start_date": start.isoformat(), "end_date": end.isoformat(), "currency": currency})

    def rows(r):
        j = r.json() if r.status_code == 200 else {}
        return [(x.get("member_id"), x.get("display_name"), x.get("status"), x.get("amount")) for x in j.get("rows", [])]

    def tagged(tid):
        return sorted(r["member_id"] for r in db.sql(
            "SELECT member_id FROM transaction_beneficiaries WHERE transaction_id = %s", tid))

    def placeholder(owner, name):
        view = c.post("/api/family/placeholders", headers=owner["h"], json={"display_name": name}).json()
        return next((m["id"] for m in view.get("members", []) if m["display_name"] == name), None)

    try:
        M = register("Mum", "plus")
        D = register("Dad", "free")
        O = register("Other", "plus")
        L = register("Loner", "free")
        r = c.post("/api/family", headers=M["h"], json={"name": f"Entries family {tag}"})
        m_mid = (r.json().get("me") or {}).get("member_id") if r.status_code == 200 else None
        c.post("/api/family/invites", headers=M["h"], json={"email": D["email"]})
        inv = next(iter(c.get("/api/family/invites/mine", headers=D["h"]).json().get("invites", [])), None)
        if inv:
            c.post(f"/api/family/invites/{inv['id']}/accept", headers=D["h"])
        d_mid = (c.get("/api/family", headers=D["h"]).json().get("me") or {}).get("member_id")
        mama, koko, gone = placeholder(M, "Ma Ma"), placeholder(M, "Ko Ko"), placeholder(M, "Gone")
        c.post("/api/family", headers=O["h"], json={"name": f"Other family {tag}"})
        stranger = placeholder(O, "Stranger")
        check(all((m_mid, d_mid, mama, koko, gone, stranger)), "entries: Mum's family with Dad, Ma Ma, Ko Ko and Gone",
              (m_mid, d_mid, mama, koko, gone, stranger))

        # ---- who added it, who it was for ----
        r = tx(M, amount=60000, currency="mmk", for_whom=[mama, koko])
        e1 = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and e1.get("added_by") == {"member_id": m_mid, "display_name": "Mum"}
              and sorted(e1.get("for_whom") or []) == sorted([mama, koko]),
              "entries: Mum's family entry for [Ma Ma, Ko Ko] answers added_by Mum and for_whom", f"{r.status_code} {r.text[:300]}")
        check(tagged(e1.get("id")) == sorted([mama, koko]), "entries: the beneficiaries are stored", tagged(e1.get("id")))
        r = tx(M, amount=850000, currency="mmk", for_whom=[])
        e2 = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and e2.get("for_whom") == [], "entries: for_whom [] is Whole family",
              f"{r.status_code} {r.text[:200]}")
        r = tx(M, amount=850, currency="thb")
        check(r.status_code == 200 and r.json().get("for_whom") == [], "entries: no for_whom is Whole family",
              f"{r.status_code} {r.text[:200]}")
        r = tx(M, amount=10.00, currency="usd", for_whom=[mama, koko, d_mid])
        e3 = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200, "entries: $10.00 for three members", f"{r.status_code} {r.text[:200]}")
        r = tx(D, amount=4, currency="thb", for_whom=[d_mid, d_mid, gone])
        e4 = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and sorted(e4.get("for_whom") or []) == sorted([d_mid, gone])
              and e4.get("added_by") == {"member_id": d_mid, "display_name": "Dad"},
              "entries: Dad's entry records Dad, duplicates in for_whom are removed", f"{r.status_code} {r.text[:300]}")
        # Not counted: an inflow, a transfer leg, and entries outside the window.
        tx(M, type="inflow", main_category="Employment Income", sub_category="Salary", amount=1000000, currency="mmk",
           for_whom=[mama])
        r = tx(M, amount=5000, currency="mmk", for_whom=[koko])
        if r.status_code == 200:
            db.sql("UPDATE transactions SET transfer_id = %s WHERE id = %s", str(uuid.uuid4()), r.json()["id"])
        tx(M, amount=7000, currency="mmk", for_whom=[mama], date=at(d0 + timedelta(days=1), 23, 30))  # last day: in
        tx(M, amount=9, currency="mmk", for_whom=[mama], date=at(d0 + timedelta(days=2), 0, 0))  # day after: out
        tx(M, amount=11, currency="mmk", for_whom=[mama], date=at(d0 - timedelta(days=1), 23, 59, 59))  # day before: out

        r = c.get("/api/transactions", headers=H(M, True), params={"limit": 200})
        listed = {t["id"]: t for t in r.json()} if r.status_code == 200 else {}
        check(listed.get(e1.get("id"), {}).get("added_by") == {"member_id": m_mid, "display_name": "Mum"}
              and sorted(listed.get(e1.get("id"), {}).get("for_whom") or []) == sorted([mama, koko])
              and listed.get(e4.get("id"), {}).get("added_by", {}).get("display_name") == "Dad",
              "entries: the family list carries added_by and for_whom", f"{r.status_code} {r.text[:300]}")
        r = c.get(f"/api/transactions/{e3.get('id')}", headers=H(D, True))
        check(r.status_code == 200 and sorted(r.json().get("for_whom") or []) == sorted([mama, koko, d_mid])
              and r.json().get("added_by", {}).get("member_id") == m_mid,
              "entries: GET one family entry carries added_by and for_whom", f"{r.status_code} {r.text[:300]}")

        # ---- personal books have neither ----
        r = tx(M, family=False, amount=3)
        check(r.status_code == 200 and r.json().get("added_by") is None and r.json().get("for_whom") == [],
              "entries: a personal entry has added_by null and for_whom []", f"{r.status_code} {r.text[:200]}")
        r = tx(M, family=False, amount=3, for_whom=[])
        check(r.status_code == 200, "entries: a personal entry accepts for_whom []", f"{r.status_code} {r.text[:200]}")
        r = tx(M, family=False, amount=3, for_whom=[mama])
        check(_code(r, 400, "invalid_for_whom"), "entries: for_whom in a personal book is 400 invalid_for_whom",
              f"{r.status_code} {r.text[:200]}")
        r = c.get("/api/transactions", headers=H(M))
        check(r.status_code == 200 and r.json() and all(t.get("added_by") is None and t.get("for_whom") == [] for t in r.json()),
              "entries: the personal list has added_by null and for_whom []", r.text[:200])

        # ---- for_whom must be active members of this family ----
        for label, ids in (("another family's member", [stranger]), ("an unknown id", ["no-such-member"]),
                           ("a mix with one outsider", [mama, stranger])):
            r = tx(M, for_whom=ids)
            check(_code(r, 400, "invalid_for_whom"), f"entries: for_whom with {label} is 400 invalid_for_whom",
                  f"{r.status_code} {r.text[:200]}")
        r = c.post("/api/transactions/batch-create", headers=H(M, True), json=[
            {"type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries", "date": at(today),
             "amount": 1, "currency": "usd", "for_whom": [stranger]}])
        check(_code(r, 400, "invalid_for_whom"), "entries: batch-create refuses an outsider in for_whom", f"{r.status_code} {r.text[:200]}")
        r = c.post("/api/transactions/batch-create", headers=H(D, True), json=[
            {"type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries", "date": at(today),
             "amount": 1, "currency": "usd", "for_whom": [koko]},
            {"type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries", "date": at(today),
             "amount": 2, "currency": "usd"}])
        b = r.json() if r.status_code == 200 else []
        check(r.status_code == 200 and len(b) == 2 and b[0].get("for_whom") == [koko] and b[1].get("for_whom") == []
              and all(x.get("added_by", {}).get("member_id") == d_mid for x in b) and tagged(b[0]["id"]) == [koko],
              "entries: batch-create takes for_whom per item and records who added them", f"{r.status_code} {r.text[:300]}")

        # ---- editing for_whom ----
        r = c.put(f"/api/transactions/{e4.get('id')}", headers=H(D, True), json={"description": "edited"})
        check(r.status_code == 200 and sorted(r.json().get("for_whom") or []) == sorted([d_mid, gone]),
              "entries: an edit without for_whom keeps it", f"{r.status_code} {r.text[:200]}")
        r = c.put(f"/api/transactions/{b[0]['id'] if b else 'x'}", headers=H(D, True), json={"for_whom": []})
        check(r.status_code == 200 and r.json().get("for_whom") == [] and tagged(b[0]["id"] if b else "x") == [],
              "entries: an edit with for_whom [] makes it Whole family", f"{r.status_code} {r.text[:200]}")
        r = c.put(f"/api/transactions/{b[1]['id'] if b else 'x'}", headers=H(D, True), json={"for_whom": [mama, mama]})
        check(r.status_code == 200 and r.json().get("for_whom") == [mama], "entries: an edit sets for_whom",
              f"{r.status_code} {r.text[:200]}")
        r = c.put(f"/api/transactions/{b[1]['id'] if b else 'x'}", headers=H(D, True), json={"for_whom": [stranger]})
        check(_code(r, 400, "invalid_for_whom") and tagged(b[1]["id"] if b else "x") == [mama],
              "entries: an edit with an outsider in for_whom is 400 and changes nothing", f"{r.status_code} {r.text[:200]}")

        # ---- who may change an entry ----
        r = c.put(f"/api/transactions/{e1.get('id')}", headers=H(D, True), json={"description": "Dad was here"})
        check(_code(r, 403, "not_allowed"), "entries: Dad (member) editing Mum's entry is 403 not_allowed",
              f"{r.status_code} {r.text[:200]}")
        r = c.delete(f"/api/transactions/{e1.get('id')}", headers=H(D, True))
        check(_code(r, 403, "not_allowed"), "entries: Dad deleting Mum's entry is 403 not_allowed", f"{r.status_code} {r.text[:200]}")
        row = (db.sql("SELECT description FROM transactions WHERE id = %s", e1.get("id")) or [{}])[0]
        check(row.get("description") == "entries", "entries: Mum's entry is unchanged", row)
        r = c.put(f"/api/transactions/{e4.get('id')}", headers=H(D, True), json={"description": "mine"})
        check(r.status_code == 200, "entries: Dad editing his own entry is 200", f"{r.status_code} {r.text[:200]}")
        r = c.put(f"/api/transactions/{e4.get('id')}", headers=H(M, True), json={"description": "checked by Mum"})
        check(r.status_code == 200, "entries: an admin (Mum) editing Dad's entry is 200", f"{r.status_code} {r.text[:200]}")
        r = tx(D, amount=1, date=at(today))
        r = c.delete(f"/api/transactions/{r.json().get('id')}", headers=H(D, True))
        check(r.status_code == 200, "entries: Dad deleting his own entry is 200", f"{r.status_code} {r.text[:200]}")
        r = tx(D, amount=1, date=at(today))
        legacy = r.json().get("id")
        db.sql("UPDATE transactions SET added_by_member_id = NULL WHERE id = %s", legacy)
        r = c.get(f"/api/transactions/{legacy}", headers=H(D, True))
        check(r.status_code == 200 and r.json().get("added_by") is None, "entries: an entry with no recorded adder has added_by null",
              f"{r.status_code} {r.text[:200]}")
        r = c.put(f"/api/transactions/{legacy}", headers=H(D, True), json={"amount": 2})
        check(_code(r, 403, "not_allowed"), "entries: an entry with no recorded adder can't be edited by a member",
              f"{r.status_code} {r.text[:200]}")
        r = c.put(f"/api/transactions/{legacy}", headers=H(M, True), json={"amount": 2})
        check(r.status_code == 200, "entries: an entry with no recorded adder can be edited by an admin", f"{r.status_code} {r.text[:200]}")

        # ---- the breakdown ----
        r = breakdown(M, "mmk")
        j = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and j.get("currency") == "mmk" and j.get("total_spent") == 917000
              and rows(r) == [(None, "Whole family", "active", 850000), (mama, "Ma Ma", "active", 37000),
                              (koko, "Ko Ko", "active", 30000)],
              "breakdown: MMK -- Whole family 850,000 on its own row, Ma Ma 30,000 + 7,000, Ko Ko 30,000; inflows, "
              "transfers and days outside the window are left out", f"{r.status_code} {r.text[:400]}")
        r = breakdown(M, "usd")
        j = r.json() if r.status_code == 200 else {}
        amounts = [x[3] for x in rows(r)]
        check(r.status_code == 200 and j.get("total_spent") == 10.0 and amounts == [3.34, 3.33, 3.33]
              and abs(sum(amounts) - 10.0) < 1e-9 and {x[0] for x in rows(r)} == {mama, koko, d_mid},
              "breakdown: $10.00 for three members is 3.34 / 3.33 / 3.33 and sums to 10.00", f"{r.status_code} {r.text[:400]}")
        r = breakdown(D, "usd", family=True)
        check(r.status_code == 200 and r.json() == j, "breakdown: a member (Dad, with X-Book: family) gets the same breakdown",
              f"{r.status_code} {r.text[:200]}")
        # R11: each entry is split on its own; its leftover cent goes to its first member (join order: Dad, Ma Ma, Ko Ko).
        d7 = d0 - timedelta(days=7)
        for _ in range(2):
            tx(M, amount=10.00, currency="usd", for_whom=[koko, mama, d_mid], date=at(d7))
        r = breakdown(M, "usd", start=d7, end=d7)
        check(r.status_code == 200 and r.json().get("total_spent") == 20.0
              and [(x[0], x[3]) for x in rows(r)] == [(d_mid, 6.68), (mama, 6.66), (koko, 6.66)],
              "breakdown: two $10.00 entries for three members are 6.68 / 6.66 / 6.66 (the leftover cent per entry "
              "goes to its first member)", f"{r.status_code} {r.text[:400]}")
        r = breakdown(M, "usd", start=d0 - timedelta(days=5), end=d0 - timedelta(days=4))
        check(r.status_code == 200 and r.json().get("total_spent") == 0 and rows(r) == [],
              "breakdown: an empty window is total 0 with no rows", f"{r.status_code} {r.text[:200]}")
        r = breakdown(M, "usd", start=d0 + timedelta(days=1), end=d0)
        check(r.status_code == 400, "breakdown: an end before the start is 400", f"{r.status_code} {r.text[:200]}")
        r = breakdown(L, "usd")
        check(_code(r, 409, "no_family"), "breakdown: outside a family is 409 no_family", f"{r.status_code} {r.text[:200]}")
        for method, path, body in (("POST", "/api/family/leave", None), ("PATCH", "/api/family", {"name": "x"}),
                                   ("POST", "/api/family/placeholders", {"display_name": "x"})):
            r = c.request(method, path, headers=L["h"], json=body)
            check(_code(r, 409, "no_family"), f"no_family: {method} {path} outside a family is 409 no_family (as a "
                  "family-book request is)", f"{r.status_code} {r.text[:200]}")

        # ---- R21 (I1): an account member's family name follows their profile name ----
        def dad_names():
            v = c.get("/api/family", headers=M["h"]).json()
            in_family = next((m["display_name"] for m in v.get("members", []) if m["id"] == d_mid), None)
            e = c.get(f"/api/transactions/{e4.get('id')}", headers=H(M, True))
            return in_family, (e.json().get("added_by") or {}).get("display_name") if e.status_code == 200 else e.status_code
        r = c.put("/api/auth/profile", headers=D["h"], json={"name": "  Daddy  "})
        check(r.status_code == 200 and dad_names() == ("Daddy", "Daddy"),
              "entries: Dad renames his profile: GET /api/family and added_by on his entries show the new name",
              (r.status_code, dad_names()))
        r = c.put("/api/auth/profile", headers=D["h"], json={"name": "   "})
        check(r.status_code in (400, 422) and dad_names() == ("Daddy", "Daddy"),
              "entries: a blank profile name is refused and the family name is unchanged", (r.status_code, dad_names()))
        r = c.put("/api/auth/profile", headers=D["h"], json={"name": "Dad"})
        check(r.status_code == 200 and dad_names() == ("Dad", "Dad"), "entries: Dad renames his profile back",
              (r.status_code, dad_names()))
        m_name = (db.sql("SELECT display_name FROM family_members WHERE id = %s", m_mid) or [{}])[0].get("display_name")
        check(m_name == "Mum", "entries: another member's family name is untouched by Dad's renames", m_name)

        # ---- a removed placeholder and a member who left stay in the history as former ----
        r = c.delete(f"/api/family/members/{gone}", headers=M["h"])
        check(r.status_code == 200, "entries: Mum removes the tagged placeholder Gone", f"{r.status_code} {r.text[:200]}")
        r = tx(M, for_whom=[gone])
        check(_code(r, 400, "invalid_for_whom"), "entries: for_whom with a former placeholder is 400", f"{r.status_code} {r.text[:200]}")
        r = c.post("/api/family/leave", headers=D["h"])
        check(r.status_code == 200, "entries: Dad leaves the family", f"{r.status_code} {r.text[:200]}")
        # R21 (I1): a former member's row keeps the name it had (history); the checks below still expect "Dad".
        r = c.put("/api/auth/profile", headers=D["h"], json={"name": "Papa"})
        row = (db.sql("SELECT display_name FROM family_members WHERE id = %s", d_mid) or [{}])[0]
        check(r.status_code == 200 and row.get("display_name") == "Dad",
              "entries: a profile rename after leaving leaves the former member row's name as it was", (r.status_code, row))
        r = tx(M, for_whom=[d_mid])
        check(_code(r, 400, "invalid_for_whom"), "entries: for_whom with a former member (Dad) is 400", f"{r.status_code} {r.text[:200]}")
        r = breakdown(M, "thb")
        check(r.status_code == 200 and r.json().get("total_spent") == 854
              and rows(r) == [(None, "Whole family", "active", 850), (d_mid, "Dad", "former", 2), (gone, "Gone", "former", 2)],
              "breakdown: Dad's and Gone's tagged history still shows, with status former", f"{r.status_code} {r.text[:400]}")
        r = c.get(f"/api/transactions/{e4.get('id')}", headers=H(M, True))
        check(r.status_code == 200 and r.json().get("added_by") == {"member_id": d_mid, "display_name": "Dad"},
              "entries: a former member still shows as the one who added the entry", f"{r.status_code} {r.text[:200]}")
        # R20: an edit may keep the entry's own former tags (history isn't rewritten), but can't add another former.
        r = c.put(f"/api/transactions/{e3.get('id')}", headers=H(M, True), json={"for_whom": [d_mid, koko]})
        check(r.status_code == 200 and sorted(r.json().get("for_whom") or []) == sorted([d_mid, koko])
              and tagged(e3.get("id")) == sorted([d_mid, koko]),
              "entries: an edit keeps the entry's former member (Dad) and changes the rest: [former, active] is 200",
              f"{r.status_code} {r.text[:200]}")
        r = c.put(f"/api/transactions/{e1.get('id')}", headers=H(M, True), json={"for_whom": [mama, koko, gone]})
        check(_code(r, 400, "invalid_for_whom") and tagged(e1.get("id")) == sorted([mama, koko]),
              "entries: an edit adding a former member not already on the entry (Gone) is 400 and changes nothing",
              f"{r.status_code} {r.text[:200]}")
        r = breakdown(D, "thb")
        check(_code(r, 409, "no_family"), "breakdown: Dad, who left, gets 409 no_family", f"{r.status_code} {r.text[:200]}")
    finally:
        _cleanup_people(made)


def section_breakdown_rounding():
    """R11, in-process: families.breakdown.compute splits each entry on its own (floor to the currency's quantum, the
    leftover to the entry's first member), so no row is negative and the rows sum exactly to total_spent."""
    backend = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend")
    if backend not in sys.path:
        sys.path.insert(0, backend)
    from families.breakdown import compute
    members = [{"id": x, "display_name": x, "status": "active"} for x in "ABCD"]

    def run(currency, entries):
        """entries: [(amount, [member ids in saved order])] -> ({member_id: amount}, total_spent, rows sum)"""
        shares = [{"id": f"e{i}", "amount": amount, "member_id": m}
                  for i, (amount, whom) in enumerate(entries) for m in (whom or [None])]
        out = compute(currency, shares, members)
        got = {r["member_id"]: r["amount"] for r in out["rows"]}
        return got, out["total_spent"], round(sum(r["amount"] for r in out["rows"]), 2), out["rows"]

    cases = (
        ("two $10.00 entries for [A,B,C]", "usd", [(10, ["A", "B", "C"])] * 2,
         {"A": 6.68, "B": 6.66, "C": 6.66}, 20.0),
        ("K1 for [A,B] plus K1 for [C,D]", "mmk", [(1, ["A", "B"]), (1, ["C", "D"])],
         {"A": 1, "B": 0, "C": 1, "D": 0}, 2),
        ("$0.01 for [A,B] plus $0.01 for [C,D]", "usd", [(0.01, ["A", "B"]), (0.01, ["C", "D"])],
         {"A": 0.01, "B": 0, "C": 0.01, "D": 0}, 0.02),
        ("K25,001 for [A,B] plus K25,001 for [C,D]", "mmk", [(25001, ["A", "B"]), (25001, ["C", "D"])],
         {"A": 12501, "B": 12500, "C": 12501, "D": 12500}, 50002),
        ("a mix with a Whole family entry", "usd", [(10, ["A", "B", "C"]), (850, None), (0.05, ["D", "B"]), (7.77, ["C"])],
         {None: 850, "A": 3.34, "C": 3.33 + 7.77, "D": 0.03, "B": 3.33 + 0.02}, 867.82),
    )
    for label, currency, entries, want, total in cases:
        got, spent, rows_sum, rows = run(currency, entries)
        ok = (set(got) == set(want) and all(abs(got[k] - v) < 1e-9 for k, v in want.items())
              and abs(spent - total) < 1e-9 and abs(rows_sum - spent) < 1e-9 and all(r["amount"] >= 0 for r in rows)
              and [r["amount"] for r in rows] == sorted((r["amount"] for r in rows), reverse=True))
        check(ok, f"breakdown rounding: {label} -> per-entry split, no negatives, rows sum to the total",
              (got, spent, rows_sum))


def section_recurring_children():
    """R4: children of a family recurring entry keep who added it and who it was for."""
    backend = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend")
    if backend not in sys.path:
        sys.path.insert(0, backend)
    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:6]
    made = []
    register = _registrar(c, tag, made)
    try:
        M = register("Mum", "plus")
        D = register("Dad", "free")
        r = c.post("/api/family", headers=M["h"], json={"name": f"Recurring family {tag}"})
        c.post("/api/family/invites", headers=M["h"], json={"email": D["email"]})
        inv = next(iter(c.get("/api/family/invites/mine", headers=D["h"]).json().get("invites", [])), None)
        if inv:
            c.post(f"/api/family/invites/{inv['id']}/accept", headers=D["h"])
        d_mid = (c.get("/api/family", headers=D["h"]).json().get("me") or {}).get("member_id")
        view = c.post("/api/family/placeholders", headers=M["h"], json={"display_name": "Ma Ma"}).json()
        mama = next((m["id"] for m in view.get("members", []) if m["display_name"] == "Ma Ma"), None)
        from tz_utils import default_zone, local_now
        # Two days ago on the default zone's calendar (the job's "today"), sent as a local date-time like the app.
        start = (local_now(default_zone()) - timedelta(days=2)).replace(hour=12, minute=0, second=0, microsecond=0)
        r = c.post("/api/transactions", headers={**D["h"], **FAM}, json={
            "type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries",
            "date": start.isoformat(), "amount": 5, "currency": "usd", "for_whom": [mama],
            "recurrence": {"enabled": True, "config": {"frequency": "daily"}}})
        parent = r.json().get("id") if r.status_code == 200 else None
        check(parent is not None and d_mid and mama, "recurring: Dad adds a daily family entry for Ma Ma",
              f"{r.status_code} {r.text[:200]}")

        async def run_job():
            from collections import defaultdict
            import recurring_transaction_service as rts
            from sql import transactions as transactions_db
            from tz_utils import local_today
            from user_zones import book_zone
            parent_book = db.sql("SELECT book_id FROM transactions WHERE id = %s", parent)[0]["book_id"]
            doc = await transactions_db.get_transaction(parent, parent_book)
            affected = defaultdict(lambda: defaultdict(list))
            today = local_today(await book_zone(doc["book_id"]))  # the family book's (its owner's) today
            return await rts._process_recurring_transaction(doc, datetime.now(UTC), today, affected)
        try:
            made_n = _backend_async(run_job)
        except Exception as e:  # noqa: BLE001
            made_n = repr(e)[:200]
        kids = db.sql("SELECT id, added_by_member_id FROM transactions WHERE parent_transaction_id = %s ORDER BY date", parent)
        check(made_n == 2 and len(kids) == 2, "recurring: the job creates the due children", (made_n, kids))
        check(kids and all(k["added_by_member_id"] == d_mid for k in kids),
              "recurring: each child has the parent's added_by", kids)
        tags = [sorted(r["member_id"] for r in db.sql(
            "SELECT member_id FROM transaction_beneficiaries WHERE transaction_id = %s", k["id"])) for k in kids]
        check(kids and all(t == [mama] for t in tags), "recurring: each child has the parent's for_whom", tags)
        if kids:
            r = c.get(f"/api/transactions/{kids[0]['id']}", headers={**D["h"], **FAM})
            check(r.status_code == 200 and r.json().get("for_whom") == [mama]
                  and (r.json().get("added_by") or {}).get("member_id") == d_mid,
                  "recurring: a child answers the parent's added_by and for_whom", f"{r.status_code} {r.text[:200]}")
            r = c.put(f"/api/transactions/{kids[0]['id']}", headers={**D["h"], **FAM}, json={"description": "child"})
            check(r.status_code == 200, "recurring: Dad (member) can edit the children of his own recurring entry",
                  f"{r.status_code} {r.text[:200]}")

        # ---- R21 (I2): a read-only family can still stop its recurring entries (a repair action) ----
        def recurring(u, **kw):
            r = c.post("/api/transactions", headers={**u["h"], **FAM}, json={
                "type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries",
                "date": datetime.now(UTC).isoformat(), "amount": 3, "currency": "usd",
                "recurrence": {"enabled": True, "config": {"frequency": "monthly", "day_of_month": 1}}} | kw)
            return r.json().get("id") if r.status_code == 200 else None

        def enabled(tid):
            return (db.sql("SELECT recurrence_enabled e FROM transactions WHERE id = %s", tid) or [{}])[0].get("e")
        mum_rec, dad_rec = recurring(M), recurring(D)
        db.sql("UPDATE users SET subscription_expires_at = now() - interval '1 day' WHERE id = %s", M["id"])
        view = c.get("/api/family", headers=D["h"]).json()
        check(mum_rec and dad_rec and (view.get("family") or {}).get("read_only") is True,
              "recurring: Mum's and Dad's monthly family entries, then Mum's plan lapses (read-only)", (mum_rec, dad_rec))
        r = c.put(f"/api/transactions/{dad_rec}", headers={**D["h"], **FAM}, json={"description": "x"})
        check(_code(r, 403, "family_read_only"), "recurring: read-only: an ordinary edit is still family_read_only",
              f"{r.status_code} {r.text[:200]}")
        m_mid = (c.get("/api/family", headers=M["h"]).json().get("me") or {}).get("member_id")
        # A child Dad didn't add: its recorded adder is Mum (the check is on the child's added_by).
        other_kid = kids[1]["id"] if len(kids) > 1 else "x"
        db.sql("UPDATE transactions SET added_by_member_id = %s WHERE id = %s", m_mid, other_kid)
        for path, target in (("disable-recurrence", mum_rec), ("disable-parent-recurrence", other_kid)):
            r = c.post(f"/api/transactions/{target}/{path}", headers={**D["h"], **FAM})
            check(_code(r, 403, "not_allowed"), f"recurring: read-only: Dad (member) can't {path} on Mum's entry (403)",
                  f"{r.status_code} {r.text[:200]}")
        check(enabled(mum_rec) is True and enabled(parent) is True, "recurring: read-only: Dad's refused requests changed nothing",
              (enabled(mum_rec), enabled(parent)))
        r = c.post(f"/api/transactions/{dad_rec}/disable-recurrence", headers={**D["h"], **FAM})
        check(r.status_code == 200 and enabled(dad_rec) is False,
              "recurring: read-only: Dad (the creator) stops his own recurring entry (200)", f"{r.status_code} {r.text[:200]}")
        r = c.post(f"/api/transactions/{mum_rec}/disable-recurrence", headers={**M["h"], **FAM})
        check(r.status_code == 200 and enabled(mum_rec) is False,
              "recurring: read-only: an admin (Mum) stops her recurring entry (200)", f"{r.status_code} {r.text[:200]}")
        r = c.post(f"/api/transactions/{kids[0]['id'] if kids else 'x'}/disable-parent-recurrence", headers={**M["h"], **FAM})
        check(r.status_code == 200 and enabled(parent) is False,
              "recurring: read-only: an admin (Mum) stops Dad's recurring parent from its child (200)",
              f"{r.status_code} {r.text[:200]}")
    finally:
        _cleanup_people(made)


def section_transfers():
    """Task 6: moving money between a personal wallet and the family wallet. One linked pair per transfer that changes
    only the two balances: never income or spending, budgets, reports or the breakdown. Only the mover may undo it."""
    backend = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend")
    if backend not in sys.path:
        sys.path.insert(0, backend)
    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:6]
    made = []
    register = _registrar(c, tag, made)
    today = datetime.now(UTC).date()
    day = datetime(today.year, today.month, today.day, 12, tzinfo=UTC).isoformat()
    window = {"start_date": (today - timedelta(days=1)).isoformat(), "end_date": (today + timedelta(days=1)).isoformat()}

    def H(u, family=False):
        return {**u["h"], **(FAM if family else {})}

    def tx(u, family=False, **kw):
        body = {"type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries",
                "date": day, "amount": 10, "currency": "mmk"} | kw
        r = c.post("/api/transactions", headers=H(u, family), json=body)
        check(r.status_code == 200, f"transfers: setup entry {kw}", f"{r.status_code} {r.text[:200]}")
        return r.json() if r.status_code == 200 else {}

    def salary(u, amount, currency="mmk", family=False):
        return tx(u, family, type="inflow", main_category="Employment Income", sub_category="Salary",
                  amount=amount, currency=currency)

    def bal(u, currency, family=False):
        r = c.get("/api/dashboard/balance", headers=H(u, family), params={"currency": currency})
        return r.json() if r.status_code == 200 else {}

    def move(u, direction, amount, currency="mmk", headers=None, **kw):
        body = {"direction": direction, "amount": amount, "currency": currency, "date": day} | kw
        return c.post("/api/transfers", headers=headers or u["h"], json=body)

    def legs(transfer_id):
        return db.sql("SELECT id, book_id, type, main_category, sub_category, amount, currency, date, description, "
                      "transfer_id, added_by_member_id, recurrence_enabled FROM transactions WHERE transfer_id = %s "
                      "ORDER BY type", transfer_id)

    def listed(u, family=False):
        r = c.get("/api/transactions", headers=H(u, family), params={"limit": 500})
        return {t["id"]: t for t in r.json()} if r.status_code == 200 else {}

    def report(u, family=False):
        r = c.post("/api/reports/generate", headers=H(u, family),
                   json={"period": "custom", "currency": "mmk", **window})
        j = r.json() if r.status_code == 200 else {}
        keys = ("total_inflow", "total_outflow", "net_balance", "total_transactions", "inflow_count", "outflow_count")
        cats = sorted(x["category"] for x in j.get("inflow_by_category", []) + j.get("outflow_by_category", []))
        return r.status_code, {k: j.get(k) for k in keys}, cats

    def multi(u, family=False):
        r = c.post("/api/reports/generate-multi-currency", headers=H(u, family), json={"period": "custom", **window})

        def strip(v):  # everything but the generation time
            if isinstance(v, dict):
                return {k: strip(x) for k, x in v.items() if k != "generated_at"}
            return [strip(x) for x in v] if isinstance(v, list) else v
        return r.status_code, str(strip(r.json() if r.status_code == 200 else r.text))

    def budget(u, family=False):
        r = c.post("/api/budgets", headers=H(u, family), json={
            "name": f"Transfers {tag}", "period": "custom", "currency": "mmk", "total_budget": 2000000,
            "start_date": window["start_date"], "end_date": window["end_date"],
            "category_budgets": [{"main_category": "Transfer", "allocated_amount": 1000000},
                                 {"main_category": "Food & Daily Living", "allocated_amount": 1000000}]})
        check(r.status_code == 200, f"transfers: setup budget (family={family})", f"{r.status_code} {r.text[:200]}")
        return r.json().get("id") if r.status_code == 200 else None

    def spent(u, budget_id, family=False):
        c.post(f"/api/budgets/{budget_id}/refresh", headers=H(u, family))
        r = c.get(f"/api/budgets/{budget_id}", headers=H(u, family))
        j = r.json() if r.status_code == 200 else {}
        return j.get("total_spent"), {x["main_category"]: x.get("spent_amount") for x in j.get("category_budgets", [])}

    try:
        M = register("Mum", "plus")
        D = register("Dad", "free")
        L = register("Loner", "plus")
        r = c.post("/api/family", headers=M["h"], json={"name": f"Transfers family {tag}"})
        m_mid = (r.json().get("me") or {}).get("member_id") if r.status_code == 200 else None
        c.post("/api/family/invites", headers=M["h"], json={"email": D["email"]})
        inv = next(iter(c.get("/api/family/invites/mine", headers=D["h"]).json().get("invites", [])), None)
        if inv:
            c.post(f"/api/family/invites/{inv['id']}/accept", headers=D["h"])
        d_mid = (c.get("/api/family", headers=D["h"]).json().get("me") or {}).get("member_id")
        book_id = (db.sql("SELECT b.id FROM books b JOIN family_members m ON m.family_id = b.family_id "
                          "WHERE m.user_id = %s", M["id"]) or [{}])[0].get("id")
        check(all((m_mid, d_mid, book_id)), "transfers: Mum's family with Dad", (m_mid, d_mid, book_id))

        # Mum: K500,000 salary, K10,000 groceries, K200,000 set aside for a goal (available K290,000).
        salary(M, 500000)
        tx(M, amount=10000)
        r = c.post("/api/goals", headers=M["h"], json={"name": f"Bike {tag}", "target_amount": 1000000,
                                                        "goal_type": "savings", "initial_contribution": 200000,
                                                        "currency": "mmk"})
        check(r.status_code == 200, "transfers: Mum sets K200,000 aside for a goal", f"{r.status_code} {r.text[:200]}")
        # The family: K300,000 income, K50,000 spending.
        salary(M, 300000, family=True)
        tx(M, family=True, amount=50000)
        b_personal, b_family = budget(M), budget(M, True)
        m0, f0 = bal(M, "mmk"), bal(M, "mmk", True)
        rep_m0, rep_f0 = report(M), report(M, True)
        multi_m0, multi_f0 = multi(M), multi(M, True)
        check(m0.get("balance") == 490000 and m0.get("available_balance") == 290000 and f0.get("balance") == 250000,
              "transfers: before -- Mum 490,000 (290,000 available), the family 250,000", (m0, f0))

        # ---- Mum moves K100,000 into the family wallet ----
        r = move(M, "to_family", 100000, description="for the house")
        j = r.json() if r.status_code == 200 else {}
        tid = j.get("transfer_id")
        check(r.status_code == 200 and set(j) == {"transfer_id", "personal_transaction_id", "family_transaction_id"}
              and all(j.values()), "transfers: Mum moves K100,000 to the family (200, the pair's ids)",
              f"{r.status_code} {r.text[:300]}")
        m1, f1 = bal(M, "mmk"), bal(M, "mmk", True)
        check(m1.get("balance") == 390000 and f1.get("balance") == 350000,
              "transfers: Mum's balance -100,000 and the family's +100,000", (m1, f1))
        check(m1.get("available_balance") == 190000 and f1.get("available_balance") == 350000,
              "transfers: the available balances move the same way", (m1, f1))
        check(all(m1.get(k) == m0.get(k) and f1.get(k) == f0.get(k) for k in ("total_inflow", "total_outflow")),
              "transfers: neither book's total_inflow / total_outflow changes", (m0, m1, f0, f1))
        rows = legs(tid)
        p = next((x for x in rows if x["book_id"] == M["book"]), {})
        f = next((x for x in rows if x["book_id"] == book_id), {})
        check(len(rows) == 2 and p.get("type") == "outflow" and f.get("type") == "inflow"
              and p.get("id") == j.get("personal_transaction_id") and f.get("id") == j.get("family_transaction_id"),
              "transfers: one linked pair -- an outflow in Mum's book, an inflow in the family's", rows)
        check(all(x["main_category"] == "Transfer" and x["sub_category"] == "Family wallet" and float(x["amount"]) == 100000
                  and x["currency"] == "mmk" and x["description"] == "for the house" and not x["recurrence_enabled"]
                  for x in rows) and len({x["date"] for x in rows}) == 1,
              "transfers: both legs are Transfer / Family wallet, same amount, currency, date and description", rows)
        check(p.get("added_by_member_id") is None and f.get("added_by_member_id") == m_mid,
              "transfers: the family leg records Mum as who moved it, the personal leg nobody", rows)
        check(not db.sql("SELECT 1 FROM transaction_beneficiaries WHERE transaction_id = ANY(%s)", [x["id"] for x in rows]),
              "transfers: neither leg has beneficiaries")

        lm, lf = listed(M), listed(M, True)
        check(lm.get(p.get("id"), {}).get("transfer_id") == tid and lf.get(f.get("id"), {}).get("transfer_id") == tid,
              "transfers: both books list their leg with transfer_id", (lm.get(p.get("id")), lf.get(f.get("id"))))
        check(lf.get(f.get("id"), {}).get("added_by") == {"member_id": m_mid, "display_name": "Mum"}
              and lf.get(f.get("id"), {}).get("for_whom") == [],
              "transfers: the family list shows Mum as who moved it", lf.get(f.get("id")))
        check(all(t.get("transfer_id") is None for t in list(lm.values()) + list(lf.values()) if t["id"] not in (p.get("id"), f.get("id"))),
              "transfers: normal entries answer transfer_id null")

        # ---- left out of every income and spending figure ----
        check(report(M) == rep_m0 and report(M, True) == rep_f0, "transfers: reports of both books are unchanged",
              (rep_m0, report(M), rep_f0, report(M, True)))
        check(multi(M) == multi_m0 and multi(M, True) == multi_f0,
              "transfers: multi-currency reports of both books are unchanged", (multi_m0[1][:300], multi(M)[1][:300]))
        check(spent(M, b_personal) == (10000, {"Transfer": 0, "Food & Daily Living": 10000}),
              "transfers: Mum's budget spending leaves the transfer out", spent(M, b_personal))
        check(spent(M, b_family, True) == (50000, {"Transfer": 0, "Food & Daily Living": 50000}),
              "transfers: the family budget's spending leaves the transfer out", spent(M, b_family, True))

        # ---- $5 into a family that has no USD yet (Review Focus 5) ----
        salary(M, 50, currency="usd")
        check(bal(M, "usd", True).get("balance") == 0, "transfers: the family has no USD yet")
        r = move(M, "to_family", 5, currency="usd")
        check(r.status_code == 200, "transfers: moving $5 into a family with no USD works", f"{r.status_code} {r.text[:200]}")
        check(bal(M, "usd", True).get("balance") == 5 and bal(M, "usd").get("balance") == 45,
              "transfers: the family has $5 and Mum $45", (bal(M, "usd", True), bal(M, "usd")))

        # ---- more than the source's available balance ----
        before = db.sql("SELECT count(*) AS n FROM transactions WHERE transfer_id IS NOT NULL")[0]["n"]
        r = move(M, "to_family", 190000.01)
        check(_code(r, 400, "transfer_insufficient"),
              "transfers: more than Mum's available balance (390,000 but 190,000 available) is 400 transfer_insufficient",
              f"{r.status_code} {r.text[:200]}")
        r = move(D, "to_personal", 350000.01)
        check(_code(r, 400, "transfer_insufficient"), "transfers: more than the family's available balance is refused",
              f"{r.status_code} {r.text[:200]}")
        r = move(M, "to_family", 1, currency="thb")
        check(_code(r, 400, "transfer_insufficient"), "transfers: a currency the source doesn't hold is refused",
              f"{r.status_code} {r.text[:200]}")
        after = db.sql("SELECT count(*) AS n FROM transactions WHERE transfer_id IS NOT NULL")[0]["n"]
        check(before == after, "transfers: a refused transfer writes nothing", (before, after))
        r = move(M, "to_family", 190000)
        check(r.status_code == 200 and bal(M, "mmk").get("available_balance") == 0,
              "transfers: exactly the available balance is allowed", f"{r.status_code} {r.text[:200]}")
        c.delete(f"/api/transfers/{r.json().get('transfer_id') if r.status_code == 200 else 'x'}", headers=M["h"])

        # ---- Dad takes K20,000 out of the family wallet ----
        r = move(D, "to_personal", 20000)
        dj = r.json() if r.status_code == 200 else {}
        dtid = dj.get("transfer_id")
        check(r.status_code == 200, "transfers: Dad (member) takes K20,000 out (to_personal)", f"{r.status_code} {r.text[:200]}")
        lf = listed(D, True)
        fam_leg = lf.get(dj.get("family_transaction_id"), {})
        check(fam_leg.get("transfer_id") == dtid and fam_leg.get("type") == "outflow"
              and fam_leg.get("added_by") == {"member_id": d_mid, "display_name": "Dad"},
              "transfers: the family list shows the outflow with transfer_id and added_by Dad", fam_leg)
        check(listed(M, True).get(dj.get("family_transaction_id"), {}).get("added_by", {}).get("display_name") == "Dad",
              "transfers: Mum sees who took it")
        per_leg = listed(D).get(dj.get("personal_transaction_id"), {})
        check(per_leg.get("transfer_id") == dtid and per_leg.get("type") == "inflow" and per_leg.get("added_by") is None,
              "transfers: Dad's personal list shows the inflow", per_leg)
        check(bal(D, "mmk").get("balance") == 20000 and bal(D, "mmk", True).get("balance") == 330000,
              "transfers: Dad +20,000, the family -20,000", (bal(D, "mmk"), bal(D, "mmk", True)))
        r = c.get("/api/family/breakdown", headers=M["h"], params={**window, "currency": "mmk"})
        check(r.status_code == 200 and r.json().get("total_spent") == 50000,
              "transfers: the breakdown leaves the transfer out", f"{r.status_code} {r.text[:300]}")
        check(spent(M, b_family, True)[0] == 50000, "transfers: a family outflow transfer isn't budget spending",
              spent(M, b_family, True))

        # ---- the backend's figures, in-process ----
        async def figures():
            from sql import transactions as tdb
            from insights_service import get_financial_summary
            lo = datetime.now(UTC) - timedelta(days=2)
            hi = datetime.now(UTC) + timedelta(days=2)
            return {
                "cats": {(x["main_category"]) for x in await tdb.category_totals(book_id)}
                | {(x["main_category"]) for x in await tdb.category_totals(M["book"])},
                "find": [x.get("transfer_id") for x in await tdb.find_transactions(book_id, include_transfers=False)],
                "find_all": sum(1 for x in await tdb.find_transactions(book_id) if x.get("transfer_id")),
                "dad_has": await tdb.has_transactions_between(D["book"], lo, hi),
                "dad_changed": await tdb.changed_since(D["book"], lo, hi, lo),
                "dad_totals": [(x["total_inflow"], x["total_outflow"], x["count"], x["transfer_in"], x["transfer_out"])
                               for x in await tdb.currency_totals(D["book"])],
                "dad_summary": (await get_financial_summary(D["book"], lo, hi))["summary"],
            }
        try:
            fig = _backend_async(figures)
        except Exception as e:  # noqa: BLE001
            fig = {"error": repr(e)[:300]}
        check("Transfer" not in fig.get("cats", {"Transfer"}), "transfers: category_totals leaves transfers out", fig)
        check(fig.get("find") is not None and all(x is None for x in fig["find"]) and fig.get("find_all", 0) >= 2,
              "transfers: find_transactions(include_transfers=False) leaves them out; the default keeps them", fig)
        check(fig.get("dad_has") is False and fig.get("dad_changed") is False,
              "transfers: a book with only transfers has no transactions for insights (has_transactions_between, "
              "changed_since)", fig)
        check(fig.get("dad_totals") == [(0, 0, 0, 20000, 0)],
              "transfers: currency_totals gives transfer_in / transfer_out apart from inflow / outflow", fig)
        check(fig.get("dad_summary") == [], "transfers: the insights summary has no currency with only transfers", fig)

        # ---- transfers can't be edited or deleted as entries ----
        for who, leg in ((D, fam_leg), (M, fam_leg)):
            r = c.put(f"/api/transactions/{leg.get('id')}", headers=H(who, True), json={"amount": 1})
            check(_code(r, 400, "transfer_not_editable"), f"transfers: PUT on the family leg ({who['name']}) is 400 "
                  "transfer_not_editable", f"{r.status_code} {r.text[:200]}")
        r = c.put(f"/api/transactions/{per_leg.get('id')}", headers=D["h"], json={"description": "x"})
        check(_code(r, 400, "transfer_not_editable"), "transfers: PUT on the personal leg is 400 transfer_not_editable",
              f"{r.status_code} {r.text[:200]}")
        r = c.delete(f"/api/transactions/{per_leg.get('id')}", headers=D["h"])
        check(_code(r, 400, "use_transfer_undo"), "transfers: DELETE on a leg is 400 use_transfer_undo",
              f"{r.status_code} {r.text[:200]}")
        r = c.delete(f"/api/transactions/{fam_leg.get('id')}", headers=H(M, True))
        check(_code(r, 400, "use_transfer_undo"), "transfers: an admin deleting the family leg is 400 use_transfer_undo",
              f"{r.status_code} {r.text[:200]}")
        r = c.post(f"/api/transactions/{per_leg.get('id')}/disable-recurrence", headers=D["h"])
        check(_code(r, 400, "transfer_not_editable"), "transfers: disable-recurrence on a leg is 400",
              f"{r.status_code} {r.text[:200]}")
        check(len(legs(dtid)) == 2, "transfers: both legs are still there", legs(dtid))

        # ---- undo ----
        r = c.delete(f"/api/transfers/{dtid}", headers=M["h"])
        check(_code(r, 403, "not_allowed"), "transfers: Mum (owner) undoing Dad's transfer is 403 not_allowed",
              f"{r.status_code} {r.text[:200]}")
        r = c.delete(f"/api/transfers/{dtid}", headers=H(M, True))
        check(_code(r, 403, "not_allowed"), "transfers: ... in Family mode too", f"{r.status_code} {r.text[:200]}")
        check(len(legs(dtid)) == 2, "transfers: a refused undo changes nothing", legs(dtid))
        r = c.delete(f"/api/transfers/{dtid}", headers=D["h"])
        check(r.status_code == 200 and legs(dtid) == [], "transfers: Dad undoing his own transfer removes both legs",
              f"{r.status_code} {r.text[:200]} {legs(dtid)}")
        check(bal(D, "mmk").get("balance") == 0 and bal(D, "mmk", True).get("balance") == 350000,
              "transfers: after the undo both balances are back", (bal(D, "mmk"), bal(D, "mmk", True)))
        r = c.delete(f"/api/transfers/{dtid}", headers=D["h"])
        check(_code(r, 404, "transfer_not_found"), "transfers: undoing it again is 404 transfer_not_found",
              f"{r.status_code} {r.text[:200]}")
        r = c.delete(f"/api/transfers/{uuid.uuid4()}", headers=L["h"])
        check(_code(r, 404, "transfer_not_found"), "transfers: an unknown transfer is 404", f"{r.status_code} {r.text[:200]}")

        # Undo would overdraw where the money went: Dad took K20,000 and spent K15,000 of it.
        r = move(D, "to_personal", 20000)
        spent_tid = r.json().get("transfer_id") if r.status_code == 200 else None
        tx(D, amount=15000)
        r = c.delete(f"/api/transfers/{spent_tid}", headers=D["h"])
        check(_code(r, 400, "transfer_insufficient") and len(legs(spent_tid)) == 2,
              "transfers: an undo that would take back money already spent is 400 transfer_insufficient",
              f"{r.status_code} {r.text[:200]}")

        # R13: a half pair (one leg gone) can't be undone: removing the other leg would bring money back.
        r = move(M, "to_family", 1000)
        half = r.json().get("transfer_id") if r.status_code == 200 else None
        db.sql("DELETE FROM transactions WHERE transfer_id = %s AND book_id = %s", half, book_id)
        m_before = bal(M, "mmk")
        r = c.delete(f"/api/transfers/{half}", headers=M["h"])
        check(_code(r, 409, "transfer_gone") and len(legs(half)) == 1 and legs(half)[0]["book_id"] == M["book"]
              and bal(M, "mmk") == m_before,
              "transfers: undoing a half pair is 409 transfer_gone; the personal leg and the balance stay",
              f"{r.status_code} {r.text[:200]} {legs(half)}")
        r = c.delete(f"/api/transfers/{half}", headers=D["h"])
        check(_code(r, 403, "not_allowed"), "transfers: someone else undoing a half pair is 403 not_allowed",
              f"{r.status_code} {r.text[:200]}")

        # ---- MMK amounts are kept as given (the app shows whole kyat) ----
        r = move(M, "to_family", 1500.4)
        k = r.json() if r.status_code == 200 else {}
        rows = legs(k.get("transfer_id"))
        check(r.status_code == 200 and len(rows) == 2 and all(float(x["amount"]) == 1500.4 for x in rows)
              and listed(M).get(k.get("personal_transaction_id"), {}).get("amount") == 1500.4
              and listed(M, True).get(k.get("family_transaction_id"), {}).get("amount") == 1500.4,
              "transfers: K1500.4 is stored and answered as 1500.4 on both legs", f"{r.status_code} {rows}")

        # ---- R21 (M1): a transfer waits for the books' in-process locks before it takes a pooled connection ----
        async def waits_without_a_connection():
            from fastapi import BackgroundTasks
            import utils
            from families import transfers as tr
            from sql import db as sqldb
            person = await _person_with_book(M["id"])
            pool = sqldb.get_engine().sync_engine.pool
            held = []

            async def while_family_locked(make):
                entered, release = asyncio.Event(), asyncio.Event()

                async def other_request():  # another request moving the family's money (its own task and context)
                    async with utils.get_book_money_lock(book_id):
                        entered.set()
                        await release.wait()
                holder = asyncio.create_task(other_request())
                await entered.wait()
                base = pool.checkedout()
                task = asyncio.create_task(make())
                await asyncio.sleep(0.5)
                # The reads before the locks (resolving the book) may still be running on a slow first call; once
                # they end the call waits on the lock. A connection taken before the locks would never be given back
                # here, so the count would stay above 0 for the whole 5 s.
                for _ in range(100):
                    if pool.checkedout() - base == 0 or task.done():
                        break
                    await asyncio.sleep(0.05)
                held.append(pool.checkedout() - base)
                release.set()
                await holder
                return await task
            made = await while_family_locked(lambda: tr.create_transfer(person, "to_family", 2, "mmk", datetime.now(UTC),
                                                                         None, BackgroundTasks()))
            undone = await while_family_locked(lambda: tr.undo_transfer(person, made["transfer_id"], BackgroundTasks()))
            return held, made, undone, legs(made["transfer_id"])
        try:
            held, made_t, undone, left = _backend_async(waits_without_a_connection)
        except Exception as e:  # noqa: BLE001
            held, made_t, undone, left = repr(e)[:300], {}, {}, None
        check(held == [0, 0] and made_t.get("transfer_id") and undone.get("transfer_id") == made_t.get("transfer_id")
              and left == [],
              "transfers: create and undo wait on the books' in-process locks holding no pooled connection, then "
              "complete as usual", (held, made_t, undone, left))

        # ---- who may transfer ----
        r = move(L, "to_family", 1)
        check(_code(r, 409, "no_family"), "transfers: outside a family is 409 no_family", f"{r.status_code} {r.text[:200]}")
        for label, body in (("an unknown direction", {"direction": "sideways"}), ("a zero amount", {"amount": 0}),
                            ("a negative amount", {"amount": -5}), ("an unknown currency", {"currency": "eur"})):
            r = c.post("/api/transfers", headers=M["h"],
                       json={"direction": "to_family", "amount": 1, "currency": "mmk", "date": day} | body)
            check(r.status_code == 422, f"transfers: {label} is 422", f"{r.status_code} {r.text[:200]}")
        r = move(M, "to_family", 1, headers=H(M, True))
        check(r.status_code == 200, "transfers: X-Book doesn't matter (the family is always the caller's own)",
              f"{r.status_code} {r.text[:200]}")
        db.sql("UPDATE users SET subscription_type = 'free', subscription_expires_at = NULL WHERE id = %s", M["id"])
        r = move(D, "to_family", 1)
        check(_code(r, 403, "family_read_only"), "transfers: a read-only family refuses transfers (family_read_only)",
              f"{r.status_code} {r.text[:200]}")

        # R13: deleting the family removes its legs; the personal legs stay in Mum's history and can't be undone.
        kept = k.get("transfer_id")
        r = c.request("DELETE", "/api/family", headers=M["h"], json={"confirm_name": f"Transfers family {tag}"})
        check(r.status_code == 200, "transfers: Mum deletes the family", f"{r.status_code} {r.text[:200]}")
        rows = legs(kept)
        check(len(rows) == 1 and rows[0]["book_id"] == M["book"],
              "transfers: after the family is deleted Mum's personal leg stays", rows)
        m_before = bal(M, "mmk")
        r = c.delete(f"/api/transfers/{kept}", headers=M["h"])
        check(_code(r, 409, "transfer_gone") and len(legs(kept)) == 1 and bal(M, "mmk") == m_before,
              "transfers: undoing it then is 409 transfer_gone; the leg and Mum's balance are unchanged",
              f"{r.status_code} {r.text[:200]} {bal(M, 'mmk')} vs {m_before}")
    finally:
        _cleanup_people(made)


def section_budgets_goals():
    """Task 7: in a family book only the owner and admins create, change or delete budgets and goals (and refresh a
    budget, ask for AI suggestions, or take money out of a goal); any active member may add money to a goal. Reads stay
    open to all, and personal books are unchanged."""
    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:6]
    made = []
    register = _registrar(c, tag, made)
    today = datetime.now(UTC).date()
    day = datetime(today.year, today.month, today.day, 12, tzinfo=UTC).isoformat()
    window = {"start_date": (today - timedelta(days=1)).isoformat(), "end_date": (today + timedelta(days=1)).isoformat()}

    def H(u, family=False):
        return {**u["h"], **(FAM if family else {})}

    def bud(u, family=True, name="B"):
        return c.post("/api/budgets", headers=H(u, family), json={
            "name": f"{name} {tag}", "period": "custom", "currency": "mmk", "total_budget": 100000, **window,
            "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 100000}]})

    def goal(u, family=True, **kw):
        return c.post("/api/goals", headers=H(u, family), json={
            "name": f"G {tag}", "target_amount": 500000, "goal_type": "savings", "currency": "mmk"} | kw)

    def put(u, amount, goal_id, family=True):
        return c.post(f"/api/goals/{goal_id}/contribute", headers=H(u, family), json={"amount": amount})

    def avail(u, family=True):
        r = c.get("/api/dashboard/balance", headers=H(u, family), params={"currency": "mmk"})
        return r.json().get("available_balance") if r.status_code == 200 else None

    def salary(u, amount, family):
        return c.post("/api/transactions", headers=H(u, family), json={
            "type": "inflow", "main_category": "Employment Income", "sub_category": "Salary", "date": day,
            "amount": amount, "currency": "mmk"})

    suggest = {"period": "monthly", "start_date": datetime.now(UTC).isoformat(), "currency": "mmk", "analysis_months": 3}

    try:
        A = register("Ann", "plus")
        B = register("Bo", "free")
        S = register("Sam", "free")
        c.post("/api/family", headers=A["h"], json={"name": f"BG family {tag}"})
        for p in (B, S):
            c.post("/api/family/invites", headers=A["h"], json={"email": p["email"]})
            inv = next(iter(c.get("/api/family/invites/mine", headers=p["h"]).json().get("invites", [])), None)
            if inv:
                c.post(f"/api/family/invites/{inv['id']}/accept", headers=p["h"])
        b_mid = (c.get("/api/family", headers=B["h"]).json().get("me") or {}).get("member_id")
        r = c.patch(f"/api/family/members/{b_mid}", headers=A["h"], json={"role": "admin"})
        check(r.status_code == 200, "budgets and goals: Ann (owner), Bo (admin) and Sam (member)", r.status_code)
        check(salary(A, 100000, True).status_code == 200, "budgets and goals: the family has K100,000")

        # ---- budgets ----
        r = bud(S)
        check(_code(r, 403, "not_allowed"), "budgets and goals: a member can't create a family budget",
              f"{r.status_code} {r.text[:200]}")
        r = bud(B)
        bid = r.json().get("id") if r.status_code == 200 else None
        check(r.status_code == 200 and bid, "budgets and goals: an admin creates a family budget",
              f"{r.status_code} {r.text[:200]}")
        r = bud(A, name="Owner")
        oid = r.json().get("id") if r.status_code == 200 else None
        check(r.status_code == 200, "budgets and goals: the owner creates a family budget",
              f"{r.status_code} {r.text[:200]}")
        r = c.get("/api/budgets", headers=H(S, True), params={"limit": 50})
        ids = [x["id"] for x in r.json()] if r.status_code == 200 else []
        check(bid in ids and oid in ids, "budgets and goals: a member lists the family budgets", f"{r.status_code} {ids}")
        check(c.get(f"/api/budgets/{bid}", headers=H(S, True)).status_code == 200,
              "budgets and goals: a member reads one family budget")
        check(c.get("/api/budgets/summary", headers=H(S, True)).status_code == 200,
              "budgets and goals: a member reads the family budget summary")
        r = c.put(f"/api/budgets/{bid}", headers=H(S, True), json={"name": "Renamed"})
        check(_code(r, 403, "not_allowed"), "budgets and goals: a member can't edit a family budget",
              f"{r.status_code} {r.text[:200]}")
        r = c.put(f"/api/budgets/{bid}", headers=H(B, True), json={"name": f"Renamed {tag}"})
        check(r.status_code == 200 and r.json().get("name") == f"Renamed {tag}",
              "budgets and goals: an admin edits a family budget", f"{r.status_code} {r.text[:200]}")
        r = c.post(f"/api/budgets/{bid}/refresh", headers=H(S, True))
        check(_code(r, 403, "not_allowed"), "budgets and goals: a member can't refresh a family budget",
              f"{r.status_code} {r.text[:200]}")
        r = c.post(f"/api/budgets/{bid}/refresh", headers=H(B, True))
        check(r.status_code == 200, "budgets and goals: an admin refreshes a family budget",
              f"{r.status_code} {r.text[:200]}")
        r = c.post("/api/budgets/ai-suggest", headers=H(S, True), json=suggest)
        check(_code(r, 403, "not_allowed"), "budgets and goals: a member can't ask for family AI budget suggestions",
              f"{r.status_code} {r.text[:200]}")
        r = c.post("/api/budgets/ai-suggest", headers=H(B, True), json=suggest)
        check(r.status_code != 403, "budgets and goals: an admin may ask for family AI budget suggestions",
              f"{r.status_code} {r.text[:200]}")
        r = c.delete(f"/api/budgets/{bid}", headers=H(S, True))
        check(_code(r, 403, "not_allowed") and c.get(f"/api/budgets/{bid}", headers=H(A, True)).status_code == 200,
              "budgets and goals: a member can't delete a family budget (it stays)", f"{r.status_code} {r.text[:200]}")
        r = c.delete(f"/api/budgets/{bid}", headers=H(B, True))
        check(r.status_code == 200 and c.get(f"/api/budgets/{bid}", headers=H(A, True)).status_code == 404,
              "budgets and goals: an admin deletes a family budget", f"{r.status_code} {r.text[:200]}")

        # ---- goals ----
        r = goal(S)
        check(_code(r, 403, "not_allowed"), "budgets and goals: a member can't create a family goal",
              f"{r.status_code} {r.text[:200]}")
        r = goal(B)
        gid = r.json().get("id") if r.status_code == 200 else None
        check(r.status_code == 200 and gid, "budgets and goals: an admin creates a family goal",
              f"{r.status_code} {r.text[:200]}")
        r = c.get("/api/goals", headers=H(S, True))
        check(r.status_code == 200 and gid in [x["id"] for x in r.json()],
              "budgets and goals: a member lists the family goals", r.status_code)
        check(c.get(f"/api/goals/{gid}", headers=H(S, True)).status_code == 200,
              "budgets and goals: a member reads one family goal")
        check(c.get("/api/goals/summary", headers=H(S, True)).status_code == 200,
              "budgets and goals: a member reads the family goals summary")
        r = c.put(f"/api/goals/{gid}", headers=H(S, True), json={"name": "Renamed"})
        check(_code(r, 403, "not_allowed"), "budgets and goals: a member can't edit a family goal",
              f"{r.status_code} {r.text[:200]}")
        r = c.put(f"/api/goals/{gid}", headers=H(B, True), json={"name": f"Renamed {tag}"})
        check(r.status_code == 200, "budgets and goals: an admin edits a family goal", f"{r.status_code} {r.text[:200]}")

        a0 = avail(S)
        r = put(S, 20000, gid)
        check(a0 is not None and r.status_code == 200 and avail(S) == a0 - 20000,
              "budgets and goals: a member adds K20,000 to a family goal; the available balance drops by 20,000",
              f"{r.status_code} {r.text[:200]} {a0} -> {avail(S)}")
        r = put(S, -5000, gid)
        check(_code(r, 403, "not_allowed") and avail(S) == a0 - 20000,
              "budgets and goals: a member can't take money out of a family goal (nothing moves)",
              f"{r.status_code} {r.text[:200]} {avail(S)}")
        r = put(B, -5000, gid)
        check(r.status_code == 200 and avail(S) == a0 - 15000,
              "budgets and goals: an admin takes K5,000 out of a family goal", f"{r.status_code} {r.text[:200]} {avail(S)}")
        r = put(A, 1000, gid)
        check(r.status_code == 200, "budgets and goals: the owner adds money to a family goal", r.status_code)
        r = c.delete(f"/api/goals/{gid}", headers=H(S, True))
        check(_code(r, 403, "not_allowed") and c.get(f"/api/goals/{gid}", headers=H(A, True)).status_code == 200,
              "budgets and goals: a member can't delete a family goal (it stays)", f"{r.status_code} {r.text[:200]}")
        r = c.delete(f"/api/goals/{gid}", headers=H(B, True))
        check(r.status_code == 200 and c.get(f"/api/goals/{gid}", headers=H(A, True)).status_code == 404,
              "budgets and goals: an admin deletes a family goal", f"{r.status_code} {r.text[:200]}")

        # ---- read-only: a member's contribution is refused ----
        r = goal(A, name="RO")
        rid = r.json().get("id") if r.status_code == 200 else None
        db.sql("UPDATE users SET subscription_type = 'free', subscription_expires_at = NULL WHERE id = %s", A["id"])
        r = put(S, 100, rid)
        check(_code(r, 403, "family_read_only"), "budgets and goals: a read-only family refuses contributions",
              f"{r.status_code} {r.text[:200]}")
        db.sql("UPDATE users SET subscription_type = 'plus', subscription_expires_at = %s WHERE id = %s",
               datetime.now(UTC) + timedelta(days=30), A["id"])

        # ---- personal books are unchanged: a plain member does everything in their own book ----
        r = bud(S, family=False, name="Mine")
        sb = r.json().get("id") if r.status_code == 200 else None
        check(r.status_code == 200, "budgets and goals: a member creates a personal budget",
              f"{r.status_code} {r.text[:200]}")
        r = c.put(f"/api/budgets/{sb}", headers=S["h"], json={"name": "Mine2"})
        check(r.status_code == 200, "budgets and goals: a member edits a personal budget", f"{r.status_code} {r.text[:200]}")
        r = c.post(f"/api/budgets/{sb}/refresh", headers=S["h"])
        check(r.status_code == 200, "budgets and goals: a member refreshes a personal budget", r.status_code)
        r = c.delete(f"/api/budgets/{sb}", headers=S["h"])
        check(r.status_code == 200, "budgets and goals: a member deletes a personal budget",
              f"{r.status_code} {r.text[:200]}")
        salary(S, 50000, False)
        r = goal(S, family=False)
        sg = r.json().get("id") if r.status_code == 200 else None
        check(r.status_code == 200, "budgets and goals: a member creates a personal goal", f"{r.status_code} {r.text[:200]}")
        r = c.put(f"/api/goals/{sg}", headers=S["h"], json={"name": "Mine2"})
        check(r.status_code == 200, "budgets and goals: a member edits a personal goal", f"{r.status_code} {r.text[:200]}")
        r = put(S, 10000, sg, family=False)
        check(r.status_code == 200, "budgets and goals: a member adds to a personal goal", f"{r.status_code} {r.text[:200]}")
        r = put(S, -4000, sg, family=False)
        check(r.status_code == 200, "budgets and goals: a member takes money out of a personal goal",
              f"{r.status_code} {r.text[:200]}")
        r = c.delete(f"/api/goals/{sg}", headers=S["h"])
        check(r.status_code == 200, "budgets and goals: a member deletes a personal goal", f"{r.status_code} {r.text[:200]}")
    finally:
        _cleanup_people(made)


def section_notifications():
    """Task 8: a family book's budget and goal notices go to every active account member (and nobody else), each in
    their own language and by their own preferences, linked to the family book; per-entry notices are not sent for a
    family book; recurring notices go only to the member who added the recurring entry; custom insight notices go to
    the asker when known."""
    backend = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend")
    if backend not in sys.path:
        sys.path.insert(0, backend)
    import json
    import re
    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:6]
    made = []
    register = _registrar(c, tag, made)
    today = datetime.now(UTC).date()
    noon = datetime(today.year, today.month, today.day, 12, tzinfo=UTC)

    def H(u, family=True):
        return {**u["h"], **(FAM if family else {})}

    def notes(uid, type_=None):
        rows = db.sql("SELECT type, title, message, goal_id, budget_id, custom_insight_id, book_id, goal_name "
                      "FROM notifications WHERE user_id = %s ORDER BY created_at, id", uid)
        return [r for r in rows if type_ is None or r["type"] == type_]

    def book_notes():
        """Every notice about the family book (book_id), whoever it went to."""
        return db.sql("SELECT user_id, type, goal_name FROM notifications WHERE book_id = %s ORDER BY created_at, id", book)

    def api_notes(u, type_):
        """The person's notifications of this type as GET /api/notifications answers them."""
        r = c.get("/api/notifications", headers=u["h"], params={"limit": 100})
        return [n for n in (r.json() if r.status_code == 200 else []) if n.get("type") == type_]

    def is_family(n):
        return (n.get("extra") or {}).get("book") == "family"

    def wait_for(fn, timeout=8.0):
        end = time.time() + timeout
        while True:
            v = fn()
            if v or time.time() > end:
                return v
            time.sleep(0.25)

    def pushes(token):
        if not os.path.exists(stubenv.OUTBOX):
            return []
        with open(stubenv.OUTBOX, encoding="utf-8") as f:
            recs = [json.loads(line) for line in f if '"fcm_send"' in line]
        return [r for r in recs if r.get("fcm_token") == token or r.get("token") == token]

    def tx(u, amount, main, sub, *, date=noon, currency="mmk", type_="outflow", **kw):
        return c.post("/api/transactions", headers=H(u), json={
            "type": type_, "main_category": main, "sub_category": sub, "date": date.isoformat(), "amount": amount,
            "currency": currency} | kw)

    from notification_service import NOTIFICATION_TRANSLATIONS as T
    EN, MY = T["en"], T["my"]
    myanmar = re.compile("[က-႟]")

    try:
        M = register("Mum", "plus")
        D = register("Dad", "free")
        c.post("/api/family", headers=M["h"], json={"name": f"Notify family {tag}"})
        c.post("/api/family/invites", headers=M["h"], json={"email": D["email"]})
        inv = next(iter(c.get("/api/family/invites/mine", headers=D["h"]).json().get("invites", [])), None)
        if inv:
            c.post(f"/api/family/invites/{inv['id']}/accept", headers=D["h"])
        book = (db.sql("SELECT b.id b FROM books b JOIN family_members m ON m.family_id = b.family_id "
                       "WHERE m.user_id = %s AND m.status = 'active'", M["id"]) or [{}])[0].get("b")
        d_mid = (c.get("/api/family", headers=D["h"]).json().get("me") or {}).get("member_id")
        check(book and d_mid, "notifications: Mum (owner, en) and Dad (member, my) share a family", (book, d_mid))
        for u, lang, token in ((D, "my", f"fcm-dad-{tag}"), (M, "en", f"fcm-mum-{tag}")):
            db.sql("UPDATE users SET language = %s WHERE id = %s", lang, u["id"])
            db.sql("INSERT INTO user_devices (id, user_id, token, session_expires_at) "
                   "VALUES (%s, %s, %s, now() + interval '30 days')", str(uuid.uuid4()), u["id"], token)
        db.sql("DELETE FROM notifications WHERE user_id = ANY(%s)", [M["id"], D["id"]])  # the invite notices
        tx(M, 1000000, "Employment Income", "Salary", type_="inflow")

        # ---- per-entry notices are never sent for a family book ----
        def seed(days_ago, amount, main, sub, desc=None):
            db.sql("INSERT INTO transactions (id, book_id, type, main_category, sub_category, amount, currency, date, "
                   "description) VALUES (%s, %s, 'outflow', %s, %s, %s, 'mmk', %s, %s)", str(uuid.uuid4()), book, main,
                   sub, amount, noon - timedelta(days=days_ago), desc)
        for d in (9, 12, 15, 18, 22, 26):
            seed(d, 10000, "Transportation", "Taxi")
        for d in (27, 57, 87):
            seed(d, 1000, "Housing", "Rent", f"Rent {tag}")
        r = tx(D, 300000, "Transportation", "Taxi", date=noon - timedelta(days=5), description="Big taxi")
        check(r.status_code == 200, "notifications: Dad adds a large family entry", f"{r.status_code} {r.text[:200]}")
        r = c.post("/api/notifications/analyze-spending", headers=H(D))
        check(r.status_code == 200, "notifications: the spending analysis runs on the family book", r.status_code)

        async def payment_reminders():
            import notification_service as ns
            from tz_utils import default_zone, local_today
            await ns._detect_recurring_payments_for_book(book, datetime.now(UTC), local_today(default_zone()),
                                                         default_zone())
        _backend_async(payment_reminders)
        time.sleep(2)  # the large-entry check runs as a background task
        per_entry = [n["type"] for uid in (M["id"], D["id"]) for n in notes(uid)] + [n["type"] for n in book_notes()]
        check(per_entry == [], "notifications: a family entry by itself (large, unusual, a due payment) notifies nobody",
              per_entry)

        # ---- budgets: started, close to the cap, preferences ----
        r = c.post("/api/budgets", headers=H(M), json={
            "name": f"House {tag}", "period": "custom", "currency": "mmk", "total_budget": 100000,
            "start_date": (today - timedelta(days=1)).isoformat(), "end_date": (today + timedelta(days=2)).isoformat(),
            "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 50000},
                                 {"main_category": "Transportation", "allocated_amount": 50000}]})
        bid = r.json().get("id") if r.status_code == 200 else None
        check(bid, "notifications: Mum creates a running family budget", f"{r.status_code} {r.text[:200]}")
        ms, ds = notes(M["id"], "budget_started"), notes(D["id"], "budget_started")
        check(len(ms) == 1 and len(ds) == 1 and ms[0]["title"] == EN["budget_started_title"]
              and ds[0]["title"] == MY["budget_started_title"] and ms[0]["budget_id"] == ds[0]["budget_id"] == bid
              and ms[0]["book_id"] == ds[0]["book_id"] == book,
              "notifications: budget started reaches Mum (en) and Dad (my)", (ms, ds))

        r = tx(D, 42000, "Food & Daily Living", "Groceries")
        check(r.status_code == 200, "notifications: Dad spends K42,000 on food (84% of its K50,000)", r.status_code)
        mt = wait_for(lambda: notes(M["id"], "budget_threshold"))
        dt = wait_for(lambda: notes(D["id"], "budget_threshold"))
        check(len(mt) == 1 and len(dt) == 1, "notifications: one budget_threshold each for Mum and Dad", (mt, dt))
        check(mt and dt and mt[0]["title"] == EN["budget_threshold_title"] and dt[0]["title"] == MY["budget_threshold_title"]
              and not myanmar.search(mt[0]["message"]) and myanmar.search(dt[0]["message"])
              and mt[0]["budget_id"] == dt[0]["budget_id"] == bid,
              "notifications: each in their own language, for the family budget", (mt, dt))
        check({n["user_id"] for n in book_notes()} == {M["id"], D["id"]},
              "notifications: the family book's notices go to its members only", book_notes())
        at = api_notes(D, "budget_threshold")
        check(len(at) == 1 and is_family(at[0]),
              "notifications: GET /api/notifications marks Dad's family budget alert extra.book = 'family' (R15)", at)
        mp = wait_for(lambda: [p for p in pushes(f"fcm-mum-{tag}") if p.get("title") == EN["budget_threshold_title"]])
        dp = wait_for(lambda: [p for p in pushes(f"fcm-dad-{tag}") if p.get("title") == MY["budget_threshold_title"]])
        check(len(mp) == 1 and len(dp) == 1, "notifications: each member's device gets the push in their language",
              (len(mp), len(dp)))
        check(mp and dp and all((p.get("data") or {}).get("book") == "family" for p in mp + dp),
              "notifications: the family push data carries book = 'family'", [p.get("data") for p in mp + dp])

        r = c.put("/api/notifications/preferences", headers=D["h"], json={"preferences": {"budget_threshold": False}})
        check(r.status_code == 200, "notifications: Dad turns budget alerts off", f"{r.status_code} {r.text[:200]}")
        tx(M, 41000, "Transportation", "Fuel")
        mt2 = wait_for(lambda: [n for n in notes(M["id"], "budget_threshold") if "Transportation" in n["message"]])
        time.sleep(1)
        check(len(mt2) == 1 and len(notes(D["id"], "budget_threshold")) == 1,
              "notifications: with Dad's alerts off, only Mum gets the next one",
              (mt2, notes(D["id"], "budget_threshold")))

        # ---- budget ending soon (each member's daily job): once each, the days in each language ----
        async def period_job():
            for _ in range(2):
                for person in (M, D):
                    await stubenv.run_local_job("budget_ending_reminders", person["id"])
                await stubenv.run_local_job("budget_now_active", book)
        _backend_async(period_job)
        me = [n for n in notes(M["id"], "budget_ending_soon") if n["budget_id"] == bid]
        de = [n for n in notes(D["id"], "budget_ending_soon") if n["budget_id"] == bid]
        check(len(me) == 1 and len(de) == 1 and re.search(r"\d+ days?", me[0]["message"])
              and "day" not in de[0]["message"] and myanmar.search(de[0]["message"]),
              "notifications: budget ending soon reaches each member once, the days in their language", (me, de))

        # ---- goals: achieved; deadline approaching ----
        r = c.post("/api/goals", headers=H(M), json={"name": f"Trip {tag}", "target_amount": 100000,
                                                       "goal_type": "savings", "currency": "mmk"})
        gid = r.json().get("id") if r.status_code == 200 else None
        r = c.post(f"/api/goals/{gid}/contribute", headers=H(D), json={"amount": 100000})
        check(gid and r.status_code == 200, "notifications: Dad fills the family goal", f"{r.status_code} {r.text[:200]}")
        ma, da = notes(M["id"], "goal_achieved"), notes(D["id"], "goal_achieved")
        check(len(ma) == 1 and len(da) == 1 and ma[0]["title"] == EN["goal_achieved_title"]
              and da[0]["title"] == MY["goal_achieved_title"] and f"Trip {tag}" in da[0]["message"]
              and ma[0]["goal_id"] == da[0]["goal_id"] == gid,
              "notifications: goal achieved reaches Mum (en) and Dad (my)", (ma, da))

        r = c.post("/api/goals", headers=H(M), json={"name": f"Soon {tag}", "target_amount": 900000, "goal_type": "savings",
                                                       "currency": "mmk", "target_date": (noon + timedelta(days=3)).isoformat()})
        sid = r.json().get("id") if r.status_code == 200 else None

        async def target_job():
            for _ in range(2):
                for person in (M, D):  # each member's own daily job
                    await stubenv.run_local_job("goal_deadline_reminders", person["id"])
        _backend_async(target_job)
        mg = [n for n in notes(M["id"], "goal_approaching_date") if n["goal_id"] == sid]
        dg = [n for n in notes(D["id"], "goal_approaching_date") if n["goal_id"] == sid]
        check(sid and len(mg) == 1 and len(dg) == 1 and re.search(r"\d+ days?", mg[0]["message"])
              and "day" not in dg[0]["message"] and myanmar.search(dg[0]["message"]),
              "notifications: goal deadline reminder reaches each member once, the days in their language", (mg, dg))

        # ---- insights ready: the family's notice is apart from a member's personal one ----
        async def insights():
            import notification_service as ns
            await ns.notify_weekly_insights_generated(M["book"])  # Mum's personal weekly insight
            await ns.notify_weekly_insights_generated(book)
            await ns.notify_weekly_insights_generated(book)    # a repeat within the hour is dropped
        _backend_async(insights)
        mw, dw = notes(M["id"], "weekly_insights_generated"), notes(D["id"], "weekly_insights_generated")
        check(len(mw) == 2 and len(dw) == 1 and dw[0]["title"] == MY["weekly_insights_title"]
              and {n["book_id"] for n in mw} == {M["book"], book} and dw[0]["book_id"] == book,
              "notifications: family weekly insights reach both once, besides Mum's personal one", (mw, dw))
        aw = api_notes(M, "weekly_insights_generated")
        check(sorted(is_family(n) for n in aw) == [False, True]
              and all("book" not in (n.get("extra") or {}) for n in aw if not is_family(n)),
              "notifications: Mum's personal notice has no book marker; the family one has extra.book (R15)", aw)

        # ---- custom insight: the asker when recorded, else everyone ----
        for rid in (f"ci1-{tag}", f"ci2-{tag}"):
            db.sql("INSERT INTO custom_insights (id, book_id, start_date, end_date, status, content) "
                   "VALUES (%s, %s, current_date - 7, current_date, 'ready', 'Report')", rid, book)

        async def custom():
            import custom_insights_service as cis
            base = {"status": "ready", "book_id": book, "start_date": today - timedelta(days=7), "end_date": today}
            await cis._notify(base | {"_id": f"ci1-{tag}", "counter_keys": [["insight_custom", "month",
                                                                                today.isoformat(), D["id"]]]})
            await cis._notify(base | {"_id": f"ci2-{tag}", "counter_keys": []})
        _backend_async(custom)
        mc = [n["custom_insight_id"] for n in notes(M["id"], "custom_insight_ready")]
        dc = [n["custom_insight_id"] for n in notes(D["id"], "custom_insight_ready")]
        check(mc == [f"ci2-{tag}"] and sorted(dc) == [f"ci1-{tag}", f"ci2-{tag}"],
              "notifications: a family custom insight tells its asker, or everyone when the asker isn't recorded", (mc, dc))
        ac = api_notes(D, "custom_insight_ready")
        check(len(ac) == 2 and all(is_family(n) for n in ac),
              "notifications: the family custom insight notices (the asker's too) carry extra.book (R15)", ac)

        # ---- recurring: only the member who added it; nobody once they are former ----
        def recurring(desc, end=None):
            cfg = {"frequency": "daily"} | ({"end_date": end.isoformat()} if end else {})
            r = tx(D, 5, "Food & Daily Living", "Groceries", currency="usd", date=noon - timedelta(days=2),
                   description=desc, recurrence={"enabled": True, "config": cfg})
            return r.json().get("id") if r.status_code == 200 else None

        def run_recurring(parent):
            async def go():
                from collections import defaultdict
                import recurring_transaction_service as rts
                from sql import transactions as transactions_db
                from tz_utils import local_today
                from user_zones import book_zone
                doc = await transactions_db.get_transaction(parent, book)
                today = local_today(await book_zone(book))
                return await rts._process_recurring_transaction(doc, datetime.now(UTC), today,
                                                                defaultdict(lambda: defaultdict(list)))
            try:
                return _backend_async(go)
            except Exception as e:  # noqa: BLE001
                return repr(e)[:200]

        p1, p2 = recurring(f"Milk {tag}", end=noon), recurring(f"Bread {tag}")
        n1 = run_recurring(p1)
        kinds = {(n["type"], n["goal_name"]) for n in notes(D["id"]) if n["type"].startswith("recurring_")}
        check(n1 == 2 and kinds == {("recurring_transaction_created", f"Milk {tag}"),
                                    ("recurring_transaction_ended", f"Milk {tag}")},
              "notifications: Dad, who added the recurring entry, is told it was created and ended", (n1, kinds))
        ar = api_notes(D, "recurring_transaction_created") + api_notes(D, "recurring_transaction_ended")
        check(len(ar) == 2 and all(is_family(n) for n in ar),
              "notifications: the adder's recurring notices for a family entry carry extra.book (R15)", ar)
        others = [n["type"] for n in book_notes() if n["type"].startswith("recurring_") and n["user_id"] != D["id"]]
        check(others == [], "notifications: nobody but Dad (Mum included) gets the family's recurring notices", others)
        db.sql("UPDATE family_members SET status = 'former', left_at = now() WHERE id = %s", d_mid)
        n2 = run_recurring(p2)
        late = [n for n in book_notes() if n["goal_name"] == f"Bread {tag}"]
        check(isinstance(n2, int) and n2 >= 2 and late == [], "notifications: once its adder is former, a recurring entry's notices go to nobody",
              (n2, late))

        # ---- a personal push has no book marker ----
        r = c.post("/api/budgets", headers=D["h"], json={
            "name": f"Mine {tag}", "period": "custom", "currency": "mmk", "total_budget": 20000,
            "start_date": (today - timedelta(days=1)).isoformat(), "end_date": (today + timedelta(days=2)).isoformat(),
            "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 20000}]})
        pid = r.json().get("id") if r.status_code == 200 else None
        pp = wait_for(lambda: [p for p in pushes(f"fcm-dad-{tag}") if (p.get("data") or {}).get("subject_id") == pid])
        check(pid and len(pp) == 1 and "book" not in (pp[0].get("data") or {}),
              "notifications: Dad's personal budget push has no book in its data", (r.status_code, pp))
    finally:
        _cleanup_people(made)


def section_ai():
    """Task 9: Ko Toe Pwar and insights for the family book. Family mode answers from the family book only (with a
    FAMILY section: members, this month's breakdown, moves between wallets) and the asker's own profile; each person's
    chat history stays private per book; a family chat uses and costs the asker's own allowance; the weekly and
    monthly jobs also make family insights for a paid owner under the owner's cost cap, as do on-demand ones; the
    admin AI report names a family's row."""
    backend = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend")
    if backend not in sys.path:
        sys.path.insert(0, backend)
    import json
    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:6]
    made = []
    register = _registrar(c, tag, made)
    started = datetime.now(UTC) - timedelta(seconds=5)
    now = datetime.now(UTC).replace(microsecond=0)
    fam_name = f"AI family {tag}"
    grandma = f"Grandma {tag}"

    def H(u, family=False):
        return {**u["h"], **(FAM if family else {})}

    def tx(u, family=False, **kw):
        body = {"type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries",
                "date": now.isoformat(), "amount": 10, "currency": "usd"} | kw
        return c.post("/api/transactions", headers=H(u, family), json=body)

    def chat(u, family, message):
        r = c.post("/api/chat/stream", headers=H(u, family), json={"message": message})
        frames = [json.loads(line[6:]) for line in r.text.split("\n") if line.startswith("data: ")] \
            if r.status_code == 200 else []
        return r.status_code == 200 and bool(frames) and frames[-1].get("done") and "error" not in frames[-1]

    def history(u, family):
        r = c.get("/api/chat/history", headers=H(u, family), params={"limit": 50})
        return [m["content"] for m in r.json()] if r.status_code == 200 else (r.status_code, r.text[:200])

    def chat_uses(uid):
        return db.sql("SELECT coalesce(sum(used), 0) n FROM usage_counters WHERE user_id = %s AND feature = 'chat' "
                      "AND period = 'week'", uid)[0]["n"]

    def ai_rows(uid, feature):
        return db.sql("SELECT count(*) n FROM ai_usage WHERE user_id = %s AND feature_type = %s", uid, feature)[0]["n"]

    def book_ai_rows(feature):
        """The family book's own AI usage rows of `feature` (ai_usage.book_id, user_id NULL)."""
        return db.sql("SELECT count(*) n FROM ai_usage WHERE book_id = %s AND user_id IS NULL AND feature_type = %s",
                      book, feature)[0]["n"]

    def book_insights(kind):
        return db.sql("SELECT count(*) n FROM insights WHERE book_id = %s AND insight_type = %s AND is_placeholder = false",
                      book, kind)[0]["n"]

    def run_job(kind):
        async def go():
            await stubenv.run_local_job(f"{kind}_insights", book)
        _backend_async(go)

    book = None
    try:
        M = register("Mum", "plus")
        D = register("Dad", "free")
        r = c.post("/api/family", headers=M["h"], json={"name": fam_name})
        c.post("/api/family/invites", headers=M["h"], json={"email": D["email"]})
        inv = next(iter(c.get("/api/family/invites/mine", headers=D["h"]).json().get("invites", [])), None)
        if inv:
            c.post(f"/api/family/invites/{inv['id']}/accept", headers=D["h"])
        view = c.post("/api/family/placeholders", headers=M["h"], json={"display_name": grandma}).json()
        gm = next((m["id"] for m in view.get("members", []) if m["display_name"] == grandma), None)
        book = (db.sql("SELECT b.id b FROM families f JOIN books b ON b.family_id = f.id WHERE f.name = %s", fam_name)
                or [{}])[0].get("b")
        check(book and gm, "ai: Mum (Plus, owner), Dad (Free) and the placeholder Grandma share a family", (book, gm))
        db.sql("UPDATE users SET default_currency = 'thb', language = 'my' WHERE id = %s", D["id"])
        db.sql("UPDATE users SET default_currency = 'mmk' WHERE id = %s", M["id"])

        # Personal entries that must never reach the family answers; family entries; a transfer.
        tx(M, description=f"MUMSECRET{tag}", amount=77)
        tx(D, description=f"DADSECRET{tag}", amount=66)
        tx(D, type="inflow", main_category="Employment Income", sub_category="Salary", amount=1000,
           description=f"DADPAY{tag}")
        r = tx(M, True, description=f"FAMGROCER{tag}", amount=30, for_whom=[gm])
        check(r.status_code == 200, "ai: Mum adds a family entry for Grandma", f"{r.status_code} {r.text[:200]}")
        r = c.post("/api/transfers", headers=D["h"], json={"direction": "to_family", "amount": 250, "currency": "usd",
                                                           "date": now.isoformat()})
        check(r.status_code == 200, "ai: Dad moves $250 into the family wallet", f"{r.status_code} {r.text[:200]}")

        # ---- the context, in-process ----
        async def context():
            from ai_chatbot import FinancialDataProcessor
            from tz_utils import default_zone  # nobody here has a saved zone
            p = FinancialDataProcessor(book, default_zone())
            docs = "\n".join(d.page_content for d in await p.create_financial_documents())
            family = await p.get_family_context()
            personal = await FinancialDataProcessor(M["book"], default_zone()).get_family_context()
            return docs, family, personal
        try:
            docs, family, personal = _backend_async(context)
        except Exception as e:  # noqa: BLE001
            docs, family, personal = "", repr(e)[:300], None
        check(f"FAMGROCER{tag}" in docs and f"MUMSECRET{tag}" not in docs and f"DADSECRET{tag}" not in docs
              and f"DADPAY{tag}" not in docs,
              "ai: the family book's context has the family entries and none of Mum's or Dad's personal ones", docs[:300])
        lines = family.splitlines()
        gm_line = next((x for x in lines if grandma in x and "30" in x), None)
        move_line = next((x for x in lines if "Dad" in x and "250" in x), None)
        check("FAMILY" in family and all(n in family for n in ("Mum", "Dad", grandma)) and gm_line is not None,
              "ai: the FAMILY section names the members (placeholders too) and this month's spending for Grandma",
              family[:500])
        check(move_line is not None and "into the family wallet" in move_line
              and "not income or spending" in family.lower(),
              "ai: the FAMILY section lists Dad's move into the family wallet, labelled as not income or spending",
              family[:500])
        check(all(s not in family for s in (f"MUMSECRET{tag}", f"DADSECRET{tag}", f"DADPAY{tag}", "1,000", "1000"))
              and personal == "",
              "ai: the FAMILY section has no personal data; a personal book has no FAMILY section", (family[:300], personal))

        # ---- the prompt, in-process: the asker's profile, the family framing, usage on the asker ----
        async def prompt():
            import ai_chatbot
            from ai_providers import runner
            from ai_providers.types import Completion, Target
            seen = {}
            orig = runner.run_stream

            async def fake_run_stream(feature, *, user_id, prompt):
                seen.update(feature=feature, user_id=user_id, system=prompt.system, user=prompt.user)
                yield "ok"
                yield runner.RunResult("ok", Target("gemini", "gemini-2.5-flash"), None, Completion("ok", 1, 1, "stop"))
            runner.run_stream = fake_run_stream
            try:
                bot = ai_chatbot.FinancialChatbot()
                async for _ in bot.stream_chat(book, "How much did we spend on Grandma?", person_id=D["id"]):
                    pass
            finally:
                runner.run_stream = orig
            return seen
        try:
            seen = _backend_async(prompt)
        except Exception as e:  # noqa: BLE001
            seen = {"error": repr(e)[:300]}
        user_p, sys_p = seen.get("user", ""), seen.get("system", "")
        check(seen.get("user_id") == D["id"], "ai: a family chat's AI usage is recorded under the asker (Dad), not the book",
              {k: v for k, v in seen.items() if k in ("user_id", "error")})
        check("Name: Dad" in user_p and "Default Currency: THB" in user_p and "Language: Myanmar" in user_p,
              "ai: the family chat prompt carries the asker's name, language and default currency", user_p[:300])
        check("family book (shared household money), not their personal money" in sys_p + user_p
              and "FAMILY" in user_p and grandma in user_p,
              "ai: the family chat prompt says it is about the family book and carries the FAMILY section", sys_p[-400:])
        check(all(s not in user_p for s in (f"MUMSECRET{tag}", f"DADSECRET{tag}", f"DADPAY{tag}")),
              "ai: the family chat prompt has none of Mum's or Dad's personal entries", user_p[:300])

        # ---- over HTTP: allowance and cost on the asker ----
        d_uses, m_uses = chat_uses(D["id"]), chat_uses(M["id"])
        d_cost, b_cost = ai_rows(D["id"], "chat"), book_ai_rows("chat")
        ok = chat(D, True, f"family question {tag}")
        check(ok and chat_uses(D["id"]) == d_uses + 1 and chat_uses(M["id"]) == m_uses,
              "ai: Dad's family chat uses Dad's own chat allowance (not Mum's)",
              (ok, d_uses, chat_uses(D["id"]), m_uses, chat_uses(M["id"])))
        check(ai_rows(D["id"], "chat") == d_cost + 1 and book_ai_rows("chat") == b_cost,
              "ai: Dad's family chat AI cost is recorded under Dad (his cost cap applies), none under the book",
              (d_cost, ai_rows(D["id"], "chat"), b_cost, book_ai_rows("chat")))

        # ---- chat history: private to each person, per book ----
        chat(M, False, f"mum personal {tag}")
        chat(M, True, f"mum family {tag}")
        mf, mp, df = history(M, True), history(M, False), history(D, True)
        check(isinstance(mf, list) and f"mum family {tag}" in mf and f"mum personal {tag}" not in mf
              and f"family question {tag}" not in mf,
              "ai: Mum's family history has her family question only (not her personal one, not Dad's)", mf)
        check(isinstance(mp, list) and f"mum personal {tag}" in mp and f"mum family {tag}" not in mp,
              "ai: Mum's personal history has no family question", mp)
        check(isinstance(df, list) and f"family question {tag}" in df and f"mum family {tag}" not in df
              and f"mum personal {tag}" not in df, "ai: Dad's family history never shows Mum's questions", df)
        r = c.delete("/api/chat/history", headers=H(M, True))
        check(r.status_code == 200 and history(M, True) == [] and f"mum personal {tag}" in history(M, False)
              and f"family question {tag}" in history(D, True),
              "ai: Mum clearing her family history leaves her personal history and Dad's family history",
              (r.status_code, history(M, True), history(M, False), history(D, True)))

        # ---- the scheduled jobs: family insights for a paid owner ----
        db.sql("DELETE FROM notifications WHERE user_id = ANY(%s)", [M["id"], D["id"]])
        run_job("weekly")
        check(book_insights("weekly") == 1, "ai: the weekly job makes one family insight under the book for a Plus owner",
              book_insights("weekly"))
        check(book_ai_rows("weekly_insight") == 1,
              "ai: the weekly job's family insight spend is recorded on the book (ai_usage.book_id, user_id NULL)",
              book_ai_rows("weekly_insight"))
        dn = db.sql("SELECT type, book_id FROM notifications WHERE user_id = %s AND type = 'weekly_insights_generated'",
                    D["id"])
        check(len(dn) == 1 and dn[0]["book_id"] == book, "ai: Dad is told the family weekly insights are ready", dn)
        run_job("monthly")
        check(book_insights("monthly") == 1, "ai: the monthly job makes one family insight for a paid owner",
              book_insights("monthly"))
        check(db.sql("SELECT coalesce(sum(used), 0) n FROM usage_counters WHERE user_id = ANY(%s) "
                     "AND feature LIKE 'insight%%'", [M["id"], D["id"]])[0]["n"] == 0,
              "ai: the family insights jobs count against nobody")

        # ---- the admin AI report names the family's row ----
        sys.path.insert(0, backend)
        os.chdir(stubenv.BACKEND)
        import test_plans  # noqa: E402  (admin helpers)
        admins = test_plans.make_admins(db, ("super_admin",))
        try:
            ah = test_plans.admin_login(c, admins["super_admin"])
            r = c.get("/api/admin/ai-usage/users", headers=ah, params={"limit": 100, "start_date": started.isoformat()})
            row = next((u for u in (r.json() if r.status_code == 200 else []) if u.get("book_id") == book), None)
            check(row is not None and row.get("user_id") is None and row.get("user_name") == f"Family · {fam_name}"
                  and "book.invalid" not in (row.get("user_email") or "") and M["email"] in (row.get("user_email") or ""),
                  "ai: the admin AI usage report labels the book's row (book_id set, user_id null) 'Family · <name>' "
                  "with the owner's e-mail",
                  (r.status_code, row))
            r = c.get("/api/admin/ai-usage/stats", headers=ah, params={"start_date": started.isoformat()})
            people = db.sql("SELECT count(DISTINCT a.user_id) n FROM ai_usage a JOIN users u ON u.id = a.user_id "
                            "WHERE a.created_at >= %s", started)[0]["n"]
            book_rows = db.sql("SELECT count(*) n FROM ai_usage WHERE book_id = %s AND created_at >= %s",
                               book, started)[0]["n"]
            check(r.status_code == 200 and book_rows > 0 and r.json().get("total_users") == people,
                  "ai: the admin AI page's Active Users count is people only (the book's own spend has no user)",
                  (r.status_code, r.json().get("total_users") if r.status_code == 200 else r.text[:200], people, book_rows))
        finally:
            db.admins.delete_many({"email": admins["super_admin"]})

        db.sql("DELETE FROM insights WHERE book_id = %s", book)
        db.sql("UPDATE users SET subscription_type = 'free' WHERE id = %s", M["id"])
        run_job("weekly")
        run_job("monthly")
        check(book_insights("weekly") == 0 and book_insights("monthly") == 0,
              "ai: the jobs make no family insight when the owner is Free", (book_insights("weekly"), book_insights("monthly")))

        # ---- the owner's cost cap: the jobs skip, on-demand refuses ----
        db.sql("UPDATE users SET subscription_type = 'plus' WHERE id = %s", M["id"])
        cap_row = str(uuid.uuid4())
        db.sql("INSERT INTO ai_usage (id, user_id, feature_type, provider, model_name, estimated_cost_usd) "
               "VALUES (%s, %s, 'chat', 'openai', 'gpt-test', 500)", cap_row, M["id"])
        try:
            run_job("weekly")
            run_job("monthly")
            check(book_insights("weekly") == 0 and book_insights("monthly") == 0,
                  "ai: the jobs skip the family while the owner is over the cost cap",
                  (book_insights("weekly"), book_insights("monthly")))
            r = c.post("/api/insights/regenerate", headers=H(M, True), params={"insight_type": "weekly"})
            check(_code(r, 429, "plan_cost_cap") and book_insights("weekly") == 0,
                  "ai: a family regenerate is plan_cost_cap while the owner is over the cost cap", f"{r.status_code} {r.text[:200]}")
            r = c.get("/api/insights", headers=H(D, True), params={"insight_type": "monthly"})
            check(_code(r, 429, "plan_cost_cap") and book_insights("monthly") == 0,
                  "ai: a family GET that would generate is plan_cost_cap while the owner is over the cost cap",
                  f"{r.status_code} {r.text[:200]}")
        finally:
            db.sql("DELETE FROM ai_usage WHERE id = %s", cap_row)
        r = c.get("/api/insights", headers=H(D, True), params={"insight_type": "monthly"})
        check(r.status_code == 200 and r.json().get("book_id") == book,
              "ai: under the cap again, Dad's family GET makes the family's monthly insight", f"{r.status_code} {r.text[:200]}")
        b_monthly, b_mm, d_mm = book_ai_rows("monthly_insight"), book_ai_rows("translation"), ai_rows(D["id"], "translation")
        r = c.get("/api/insights", headers=H(D, True), params={"insight_type": "monthly", "language": "mm"})
        check(r.status_code == 200 and r.json().get("content_mm") and b_monthly >= 1
              and book_ai_rows("translation") == b_mm + 1 and ai_rows(D["id"], "translation") == d_mm,
              "ai: the on-demand family insight and its Myanmar translation are spend on the book, not on Dad",
              (r.status_code, b_monthly, b_mm, book_ai_rows("translation"), d_mm, ai_rows(D["id"], "translation")))

        # ---- R16: the book's own AI spend counts toward the owner's cap ----
        db.sql("DELETE FROM insights WHERE book_id = %s", book)
        mum_spend = db.sql("SELECT coalesce(sum(estimated_cost_usd), 0) n FROM ai_usage WHERE user_id = %s", M["id"])[0]["n"]
        book_row = str(uuid.uuid4())
        db.sql("INSERT INTO ai_usage (id, book_id, feature_type, provider, model_name, estimated_cost_usd) "
               "VALUES (%s, %s, 'weekly_insight', 'openai', 'gpt-test', 2)", book_row, book)
        try:
            run_job("weekly")
            check(float(mum_spend) < 0.5 and book_insights("weekly") == 0,
                  "ai: R16: the weekly job skips the family when the book's spend takes the owner over the cap",
                  (mum_spend, book_insights("weekly")))
            r = c.post("/api/insights/regenerate", headers=H(M, True), params={"insight_type": "weekly"})
            check(_code(r, 429, "plan_cost_cap") and book_insights("weekly") == 0,
                  "ai: R16: a family regenerate is plan_cost_cap when the book's spend takes the owner over the cap",
                  f"{r.status_code} {r.text[:200]}")
            r = c.post("/api/insights/regenerate", headers=H(M), params={"insight_type": "weekly"})
            ok = chat(M, False, f"mum personal again {tag}")
            check(r.status_code == 200 and r.json().get("book_id") == M["book"] and ok,
                  "ai: R16: Mum's own personal insight and chat are unaffected by the book's spend",
                  (f"{r.status_code} {r.text[:200]}", ok))
        finally:
            db.sql("DELETE FROM ai_usage WHERE id = %s", book_row)

        # ---- the family insight prompt: the family's name and the owner's currency ----
        async def insight_contexts():
            import insights_service as ins
            from tz_utils import default_zone  # the owner has no saved zone
            seen = []
            orig = ins._call_insight_model

            async def fake_call(feature, system_prompt, context, label, **kw):
                seen.append((feature, context))
                return "## Fake family insight", "gemini", 1, 1, 2
            ins._call_insight_model = fake_call
            try:
                await ins.generate_weekly_insight(book, tz=default_zone())
                await ins.generate_monthly_insight(book, tz=default_zone())
            finally:
                ins._call_insight_model = orig
            return seen
        try:
            contexts = _backend_async(insight_contexts)
        except Exception as e:  # noqa: BLE001
            contexts = [("error", repr(e)[:300])]
        check(len(contexts) == 2 and all(f"USER: {fam_name}" in ctx and "DEFAULT CURRENCY: MMK" in ctx
                                         and "Family book" not in ctx for _, ctx in contexts),
              "ai: the family weekly and monthly insight prompts name the family and use the owner's currency",
              [(f, ctx[:160]) for f, ctx in contexts])

        # ---- R21 (M3): a family custom insight: the family's profile in the prompt, the AI cost on the asker ----
        async def custom_family():
            import custom_insights_service as cis
            from ai_providers.runner import RunResult
            from ai_providers.types import Completion, Target
            from plans import quota
            from sql import custom_insights as ci
            seen = {}
            today = datetime.now(UTC).date()
            start = today - timedelta(days=7)
            rid = str(uuid.uuid4())
            res = quota.Reservation(D["id"], [("insight_custom", "month", today)])
            assert await ci.insert_pending({
                "_id": rid, "book_id": book, "start_date": start, "end_date": today, "preset": None,
                "instruction": None, "instruction_key": cis.instruction_key(None, None),
                "counter_keys": cis.counter_keys(res, family=True), "figures": await cis.compute_figures(book, start, today)})
            orig = cis.run_insight_model

            async def fake(feature, system_prompt, context, label, **kw):
                seen.update(context=context, user_id=kw.get("user_id"), book_id=kw.get("book_id"))
                text = "## Summary\nok"
                return RunResult(text, Target(provider="claude", model="claude-test"), None, Completion(text, 1, 1, "stop"))
            cis.run_insight_model = fake
            try:
                row = await cis.run_report(rid)
            finally:
                cis.run_insight_model = orig
            return seen, (row or {}).get("status")
        try:
            seen, status_ = _backend_async(custom_family)
        except Exception as e:  # noqa: BLE001
            seen, status_ = {"error": repr(e)[:300]}, None
        ctx = seen.get("context", "")
        check(status_ == "ready" and f"USER: {fam_name}" in ctx and "DEFAULT CURRENCY: MMK" in ctx
              and "Family book" not in ctx,
              "ai: a family custom insight's prompt names the family and uses the owner's currency",
              (status_, seen.get("error"), ctx[:160]))
        check(seen.get("user_id") == D["id"] and seen.get("book_id") is None,
              "ai: a family custom insight's AI cost is recorded under the person who asked (Dad), not the book",
              {k: v for k, v in seen.items() if k in ("user_id", "book_id", "error")})
    finally:
        _cleanup_people(made)


def section_limits():
    """The admin Plans page's family limits (Task 10): the two numbers per plan are read and saved through
    /api/admin/plans, applied at once to GET /api/plan and the family rules, validated 0-50, kept when left out,
    audit-logged; lowering them never removes anyone."""
    import admin_utils
    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:6]
    made = []
    register = _registrar(c, tag, made)
    admin_email = f"t10limits-{tag}@example.com"
    pw = "t10-admin-pass-1"
    db.admins.insert_one({"_id": str(uuid.uuid4()), "name": "t10 admin", "email": admin_email,
                          "password": admin_utils.get_password_hash(pw), "role": "admin",
                          "created_at": datetime.now(UTC), "last_login": None})
    sup_email = f"t10super-{tag}@example.com"
    db.admins.insert_one({"_id": str(uuid.uuid4()), "name": "t10 super", "email": sup_email,
                          "password": admin_utils.get_password_hash(pw), "role": "super_admin",
                          "created_at": datetime.now(UTC), "last_login": None})

    def login(email):
        return {"Authorization": "Bearer " + c.post("/api/admin/login", json={"email": email, "password": pw}).json()["access_token"]}
    AD, SUP = login(admin_email), login(sup_email)
    original = None

    def plans():
        return c.get("/api/admin/plans", headers=AD).json()

    def body_with(snapshot, **family):
        """A PUT body from a GET snapshot; family: {plan: (members, placeholders)} set on top (others as read)."""
        b = {"plans": {p: {k: v for k, v in d.items()} for p, d in snapshot["plans"].items()},
             "upgrade_contact": snapshot["upgrade_contact"]}
        for plan, (m, ph) in family.items():
            b["plans"][plan]["family_max_members"] = m
            b["plans"][plan]["family_max_placeholders"] = ph
        return b

    def put(b):
        return c.put("/api/admin/plans", headers=AD, json=b)

    def invite(by, email):
        return c.post("/api/family/invites", headers=by["h"], json={"email": email})

    try:
        original = plans()
        fl = {p: (d.get("family_max_members"), d.get("family_max_placeholders")) for p, d in original["plans"].items()}
        check(fl == {"free": (0, 0), "plus": (6, 20), "pro": (6, 20)},
              "limits: GET /api/admin/plans gives every plan its family limits (free 0/0, plus 6/20, pro 6/20)", fl)

        A = register("Lia", "plus")
        r = c.post("/api/family", headers=A["h"], json={"name": f"Lia family {tag}"})
        check(r.status_code == 200, "limits: a Plus user creates a family", f"{r.status_code} {r.text[:200]}")

        # ---- set plus to 4 members: it applies at once ----
        r = put(body_with(original, plus=(4, 20)))
        check(r.status_code == 200 and r.json()["plans"]["plus"]["family_max_members"] == 4
              and r.json()["plans"]["plus"]["family_max_placeholders"] == 20 and r.json()["plans"]["pro"]["family_max_members"] == 6,
              "limits: PUT sets plus family_max_members to 4 and the reply shows it", f"{r.status_code} {r.text[:300]}")
        check(plans()["plans"]["plus"]["family_max_members"] == 4, "limits: GET /api/admin/plans reports the saved 4")
        check(c.get("/api/plan", headers=A["h"]).json().get("family") == {"max_members": 4, "max_placeholders": 20},
              "limits: GET /api/plan gives a Plus user family limits 4/20")
        check((c.get("/api/plan", headers=A["h"]).json().get("family_by_plan") or {}).get("plus") == {"max_members": 4, "max_placeholders": 20},
              "limits: GET /api/plan family_by_plan shows Plus's saved 4/20")
        check((c.get("/api/family", headers=A["h"]).json().get("limits")) == {"max_members": 4, "max_placeholders": 20},
              "limits: GET /api/family shows the new limits")
        stored = db.sql("SELECT family_max_members m, family_max_placeholders p FROM plan_settings WHERE plan = 'plus'")
        check(stored and (stored[0]["m"], stored[0]["p"]) == (4, 20), "limits: the numbers are stored in plan_settings", stored)

        # the owner counts: 3 invites fill 4 seats, the 4th invite is refused
        people = [register(n) for n in ("Mya", "Nay", "Oo", "Pyae")]
        rs = [invite(A, p["email"]) for p in people[:3]]
        check(all(r.status_code == 200 for r in rs), "limits: three invites fit a family of 4 with its owner",
              [r.status_code for r in rs])
        r = invite(A, people[3]["email"])
        check(_code(r, 409, "family_full"), "limits: the invite past the plus limit of 4 is refused (family_full)",
              f"{r.status_code} {r.text[:200]}")

        # ---- lowering below the current count keeps everyone, refuses only new people ----
        inv = c.get("/api/family/invites/mine", headers=people[0]["h"]).json().get("invites", [])
        r = c.post(f"/api/family/invites/{inv[0]['id']}/accept", headers=people[0]["h"]) if inv else None
        check(r is not None and r.status_code == 200, "limits: a pending invite is accepted while seats are free",
              r is not None and r.text[:200])
        inv = c.get("/api/family/invites/mine", headers=people[1]["h"]).json().get("invites", [])
        r = c.post(f"/api/family/invites/{inv[0]['id']}/accept", headers=people[1]["h"]) if inv else None
        check(r is not None and r.status_code == 200, "limits: a second pending invite is accepted", r is not None and r.text[:200])
        ph = c.post("/api/family/placeholders", headers=A["h"], json={"display_name": "Gran"})
        check(ph.status_code == 200, "limits: a placeholder is added", f"{ph.status_code} {ph.text[:200]}")

        r = put(body_with(plans(), plus=(2, 0)))
        check(r.status_code == 200, "limits: plus is lowered to 2 members and 0 placeholders (below the current 3 and 1)",
              f"{r.status_code} {r.text[:200]}")
        v = c.get("/api/family", headers=A["h"]).json()
        active = [m for m in v.get("members", []) if m["status"] == "active"]
        check(len([m for m in active if m["kind"] == "account"]) == 3 and len([m for m in active if m["kind"] == "placeholder"]) == 1,
              "limits: lowering the limits removes no one (3 accounts and 1 placeholder stay)", [(m["kind"], m["status"]) for m in v.get("members", [])])
        check(v.get("limits") == {"max_members": 2, "max_placeholders": 0}, "limits: the family now shows 2/0", v.get("limits"))
        r = invite(A, people[3]["email"])
        check(_code(r, 409, "family_full"), "limits: a new invite over the lowered limit is refused (family_full)", f"{r.status_code} {r.text[:200]}")
        r = c.post("/api/family/placeholders", headers=A["h"], json={"display_name": "Uncle"})
        check(_code(r, 409, "placeholders_full"), "limits: a new placeholder over the lowered limit is refused (placeholders_full)",
              f"{r.status_code} {r.text[:200]}")
        inv = c.get("/api/family/invites/mine", headers=people[2]["h"]).json().get("invites", [])
        r = c.post(f"/api/family/invites/{inv[0]['id']}/accept", headers=people[2]["h"]) if inv else None
        check(r is not None and _code(r, 409, "family_full"), "limits: an invite sent earlier can't be accepted over the lowered limit",
              r is not None and f"{r.status_code} {r.text[:200]}")
        check(len(c.get("/api/family", headers=people[0]["h"]).json().get("members", [])) >= 4,
              "limits: an existing member still sees the whole family")

        # ---- validation ----
        before = plans()
        def bad(label, **kw):
            b = body_with(before)
            b["plans"]["plus"].update(kw)
            r = put(b)
            check(r.status_code == 422, f"limits: {label} is refused (422)", f"{r.status_code} {r.text[:200]}")
        bad("51 members", family_max_members=51)
        bad("51 placeholders", family_max_placeholders=51)
        bad("-1 members", family_max_members=-1)
        bad("-1 placeholders", family_max_placeholders=-1)
        bad("a fractional number", family_max_members=2.5)
        bad("a text number", family_max_members="3")
        bad("a boolean", family_max_placeholders=True)
        r = put(body_with(before, pro=(50, 50)))
        check(r.status_code == 200 and r.json()["plans"]["pro"]["family_max_members"] == 50,
              "limits: 50 and 50 are accepted", f"{r.status_code} {r.text[:200]}")
        r = put(body_with(plans(), pro=(0, 0)))
        check(r.status_code == 200 and r.json()["plans"]["pro"]["family_max_members"] == 0,
              "limits: 0 and 0 are accepted", f"{r.status_code} {r.text[:200]}")
        after = plans()
        check(after["plans"]["plus"]["family_max_members"] == 2 and after["plans"]["plus"]["family_max_placeholders"] == 0,
              "limits: a refused PUT changes nothing", after["plans"]["plus"])

        # ---- left out: kept ----
        b = body_with(plans())
        for p in b["plans"].values():
            p.pop("family_max_members", None)
            p.pop("family_max_placeholders", None)
        r = put(b)
        check(r.status_code == 200 and r.json()["plans"]["plus"]["family_max_members"] == 2
              and r.json()["plans"]["plus"]["family_max_placeholders"] == 0,
              "limits: a PUT without the family fields keeps the stored values", f"{r.status_code} {r.text[:300]}")
        b = body_with(plans())
        b["plans"]["plus"].pop("family_max_placeholders")
        b["plans"]["plus"]["family_max_members"] = 5
        r = put(b)
        check(r.status_code == 200 and r.json()["plans"]["plus"]["family_max_members"] == 5
              and r.json()["plans"]["plus"]["family_max_placeholders"] == 0,
              "limits: one field left out keeps just that one", f"{r.status_code} {r.text[:300]}")
        b = body_with(plans())
        b["plans"]["plus"]["family_max_members"] = None
        r = put(b)
        check(r.status_code == 200 and r.json()["plans"]["plus"]["family_max_members"] == 5,
              "limits: null is read as left out (kept)", f"{r.status_code} {r.text[:200]}")

        # ---- the audit log ----
        put(body_with(plans(), plus=(7, 9)))
        logs = c.get("/api/admin/logs", headers=SUP, params={"limit": 100}).json()
        mine = [x for x in logs if x["admin_email"] == admin_email and x["action"] == "plans_update"]
        details = (mine[0].get("details") or "") if mine else ""
        check("plus" in details and "7" in details and "9" in details and "famil" in details.lower(),
              "limits: the admin action log says the family limits changed", details[:300])

        # ---- Free's numbers never let Free create a family ----
        r = put(body_with(plans(), free=(3, 3)))
        check(r.status_code == 200 and r.json()["plans"]["free"]["family_max_members"] == 3,
              "limits: Free may be given numbers", f"{r.status_code} {r.text[:200]}")
        F = register("Fay", "free")
        r = c.post("/api/family", headers=F["h"], json={"name": "Fay family"})
        check(_code(r, 403, "plan_required"), "limits: a Free user still can't create a family whatever Free's numbers are",
              f"{r.status_code} {r.text[:200]}")
    finally:
        if original is not None:
            put(body_with(original))
        _cleanup_people(made)
        db.admins.delete_many({"email": {"$in": [admin_email, sup_email]}})


def section_account_deletion():
    """Task 11: deleting an account keeps the family's history. A member becomes former (like leaving; their entries,
    name and tags stay); a deleting owner hands the family to the longest-standing active admin, else the
    longest-standing active account member (placeholders and former members never), who is told; an owner left alone
    takes the family with them. Both deletion paths (the user's own and the super admin's) do this."""
    import admin_utils
    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:6]
    made = []
    books = []
    register = _registrar(c, tag, made)
    sup_email = f"t11super-{tag}@example.com"
    pw = "t11-admin-pass-1"
    db.admins.insert_one({"_id": str(uuid.uuid4()), "name": "t11 super", "email": sup_email,
                          "password": admin_utils.get_password_hash(pw), "role": "super_admin",
                          "created_at": datetime.now(UTC), "last_login": None})
    SUP = {"Authorization": "Bearer " + c.post("/api/admin/login", json={"email": sup_email, "password": pw}).json()["access_token"]}
    now = datetime.now(UTC).replace(microsecond=0)

    def H(u, family=False):
        return {**u["h"], **(FAM if family else {})}

    def tx(u, family=True, **kw):
        body = {"type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries",
                "date": now.isoformat(), "amount": 10, "currency": "usd", "description": "deletion"} | kw
        return c.post("/api/transactions", headers=H(u, family), json=body)

    def create(owner, name):
        r = c.post("/api/family", headers=owner["h"], json={"name": name})
        fid = (r.json().get("family") or {}).get("id") if r.status_code == 200 else None
        if fid:
            books.append(_family_book(fid))
        return fid, (r.json().get("me") or {}).get("member_id") if r.status_code == 200 else None

    def join(owner, person, joined_at=None):
        c.post("/api/family/invites", headers=owner["h"], json={"email": person["email"]})
        inv = next(iter(c.get("/api/family/invites/mine", headers=person["h"]).json().get("invites", [])), None)
        if inv:
            c.post(f"/api/family/invites/{inv['id']}/accept", headers=person["h"])
        mid = (c.get("/api/family", headers=person["h"]).json().get("me") or {}).get("member_id")
        if mid and joined_at is not None:
            db.sql("UPDATE family_members SET joined_at = %s WHERE id = %s", joined_at, mid)
        return mid

    def make_admin(owner, mid):
        return c.patch(f"/api/family/members/{mid}", headers=owner["h"], json={"role": "admin"})

    def self_delete(u):
        return c.request("DELETE", "/api/auth/delete-account", headers=u["h"], json={"password": "secret123"})

    def admin_delete(u):
        return c.delete(f"/api/admin/users/{u['id']}", headers=SUP)

    def rows(fid):
        return {m["id"]: m for m in db.sql("SELECT * FROM family_members WHERE family_id = %s", fid)}

    def owners(fid):
        return [m["id"] for m in rows(fid).values() if m["role"] == "owner" and m["status"] == "active"]

    def notified(uid, kind):
        return db.sql("SELECT count(*) n FROM notifications WHERE user_id = %s AND type = %s", uid, kind)[0]["n"]

    base = datetime.now(UTC) - timedelta(days=30)
    try:
        # ---- not in a family: deleting still works ----
        Z = register("Zaw", "free")
        r = self_delete(Z)
        check(r.status_code == 200 and not db.sql("SELECT 1 FROM users WHERE id = %s", Z["id"]),
              "account deletion: someone in no family deletes their account", f"{r.status_code} {r.text[:200]}")

        # ---- a member deletes their account: becomes former, their entries and name stay ----
        M = register("Mum", "plus")
        D = register("Dad", "free")
        fid, m_mid = create(M, f"Deletion family {tag}")
        d_mid = join(M, D)
        kid = c.post("/api/family/placeholders", headers=M["h"], json={"display_name": "Kid"}).json()
        kid = next((m["id"] for m in kid.get("members", []) if m["display_name"] == "Kid"), None)
        r = tx(D, amount=25, for_whom=[d_mid, kid])
        e_dad = r.json().get("id") if r.status_code == 200 else None
        e_mum = (tx(M, amount=40, for_whom=[d_mid]).json() or {}).get("id")
        tx(D, family=False, amount=5)
        check(all((fid, m_mid, d_mid, kid, e_dad, e_mum)), "account deletion: Mum's family with Dad and Kid, an entry each",
              (fid, m_mid, d_mid, kid, e_dad, e_mum))
        r = c.request("DELETE", "/api/auth/delete-account", headers=D["h"], json={"password": "wrong-password"})
        check(r.status_code == 401 and rows(fid).get(d_mid, {}).get("status") == "active",
              "account deletion: a wrong password changes nothing in the family", f"{r.status_code} {rows(fid).get(d_mid)}")
        r = self_delete(D)
        check(r.status_code == 200 and not db.sql("SELECT 1 FROM users WHERE id = %s", D["id"]),
              "account deletion: Dad deletes his account", f"{r.status_code} {r.text[:200]}")
        d_row = rows(fid).get(d_mid) or {}
        check(d_row.get("status") == "former" and d_row.get("left_at") is not None and d_row.get("display_name") == "Dad"
              and d_row.get("user_id") is None and d_row.get("role") == "member",
              "account deletion: Dad's member row stays, former, with his name and left_at", d_row)
        r = c.get("/api/transactions", headers=H(M, True), params={"limit": 200})
        listed = {t["id"]: t for t in r.json()} if r.status_code == 200 else {}
        check(e_dad in listed and listed[e_dad].get("added_by") == {"member_id": d_mid, "display_name": "Dad"}
              and sorted(listed[e_dad].get("for_whom") or []) == sorted([d_mid, kid]),
              "account deletion: the family entry Dad added remains, added_by Dad, its for_whom kept",
              listed.get(e_dad) or f"{r.status_code} {r.text[:200]}")
        check(e_mum in listed and listed[e_mum].get("for_whom") == [d_mid],
              "account deletion: an entry for Dad still says it was for Dad", listed.get(e_mum))
        v = c.get("/api/family", headers=M["h"]).json()
        dad = next((m for m in v.get("members", []) if m["id"] == d_mid), {})
        check(dad.get("status") == "former" and dad.get("display_name") == "Dad" and v.get("me", {}).get("role") == "owner",
              "account deletion: the family view shows Dad as a former member, Mum still the owner", dad)
        check(not db.sql("SELECT 1 FROM transactions WHERE book_id = %s", D["book"])
              and not db.sql("SELECT 1 FROM books WHERE id = %s", D["book"]),
              "account deletion: Dad's personal book and entries are gone")

        # ---- the owner deletes with admins: the longest-standing admin becomes owner ----
        P = register("Pa", "plus")
        mem_old = register("Old", "free")     # longest-standing, but only a member
        adm1 = register("Adm", "plus")        # the longest-standing admin
        adm2 = register("Adm2", "free")       # a newer admin
        X = register("Xin", "free")           # invited by Pa, not yet joined
        fid2, p_mid = create(P, f"Admins family {tag}")
        # Adm2 joins before Adm, but joined_at (not the order rows were written) decides: Adm is the older admin.
        old_mid = join(P, mem_old, base + timedelta(days=1))
        a2 = join(P, adm2, base + timedelta(days=4))
        a1 = join(P, adm1, base + timedelta(days=3))
        made_admins = [make_admin(P, a1).status_code, make_admin(P, a2).status_code]
        c.post("/api/family/placeholders", headers=P["h"], json={"display_name": "Baby"})
        db.sql("UPDATE family_members SET joined_at = %s WHERE family_id = %s AND kind = 'placeholder'", base, fid2)
        p_entry = (tx(P, amount=12).json() or {}).get("id")
        r = c.post("/api/family/invites", headers=P["h"], json={"email": X["email"]})
        x_inv = r.json().get("id") if r.status_code == 200 else None
        check(made_admins == [200, 200], "account deletion: Pa makes Adm and Adm2 admins", made_admins)
        check(all((fid2, p_mid, old_mid, a1, a2, p_entry, x_inv)), "account deletion: Pa's family with Old, two admins, Baby and an invite",
              (fid2, p_mid, old_mid, a1, a2, p_entry, x_inv))
        db.sql("UPDATE users SET language = 'my' WHERE id = %s", adm1["id"])
        r = self_delete(P)
        check(r.status_code == 200, "account deletion: the owner Pa deletes his account", f"{r.status_code} {r.text[:200]}")
        rr = rows(fid2)
        check(owners(fid2) == [a1], "account deletion: the longest-standing admin is the only owner",
              [(m["display_name"], m["role"], m["status"]) for m in rr.values()])
        check((rr.get(p_mid) or {}).get("status") == "former" and (rr.get(p_mid) or {}).get("role") != "owner"
              and (rr.get(p_mid) or {}).get("display_name") == "Pa",
              "account deletion: Pa's row is former (no longer owner), with his name", rr.get(p_mid))
        check((rr.get(old_mid) or {}).get("role") == "member" and (rr.get(a2) or {}).get("role") == "admin",
              "account deletion: the other members keep their roles", (rr.get(old_mid), rr.get(a2)))
        v = c.get("/api/family", headers=adm1["h"]).json()
        check(v.get("me", {}).get("role") == "owner" and v.get("family", {}).get("read_only") is False,
              "account deletion: GET /api/family for Adm says role owner, family writable (Adm is on Plus)", v.get("me"))
        r = tx(adm1, amount=3)
        check(r.status_code == 200, "account deletion: the family takes new entries under its Plus owner", f"{r.status_code} {r.text[:200]}")
        r = tx(mem_old, amount=4)
        check(r.status_code == 200, "account deletion: a member adds a family entry too", f"{r.status_code} {r.text[:200]}")
        listed = {t["id"]: t for t in c.get("/api/transactions", headers=H(adm1, True), params={"limit": 200}).json()}
        check(listed.get(p_entry, {}).get("added_by") == {"member_id": p_mid, "display_name": "Pa"},
              "account deletion: the old owner's entry remains, added_by Pa", listed.get(p_entry))
        check(notified(adm1["id"], "family_owner") == 1 and notified(adm2["id"], "family_owner") == 0,
              "account deletion: the new owner is told (family_owner), nobody else",
              (notified(adm1["id"], "family_owner"), notified(adm2["id"], "family_owner")))
        msg = db.sql("SELECT title, message FROM notifications WHERE user_id = %s AND type = 'family_owner'", adm1["id"])
        check(bool(msg) and f"Admins family {tag}" in msg[0]["message"] and msg[0]["title"] == "သင် မိသားစုပိုင်ရှင် ဖြစ်လာပါပြီ",
              "account deletion: the notice names the family, in the new owner's language (Myanmar)", msg)
        inv = db.sql("SELECT status, invited_by_member_id FROM family_invites WHERE id = %s", x_inv)
        check(bool(inv) and inv[0]["status"] == "pending" and inv[0]["invited_by_member_id"] == p_mid,
              "account deletion: Pa's pending invite stays valid", inv)
        mine = c.get("/api/family/invites/mine", headers=X["h"]).json().get("invites", [])
        r = c.post(f"/api/family/invites/{mine[0]['id']}/accept", headers=X["h"]) if mine else None
        check(r is not None and r.status_code == 200, "account deletion: Xin can still accept Pa's invite",
              r is not None and f"{r.status_code} {r.text[:200]}")

        # ---- the owner deletes with only members (admin path): the longest-standing account member owns it ----
        Q = register("Que", "plus")
        n1 = register("Nwe", "free")     # oldest active member
        n2 = register("Nan", "plus")
        gone = register("Gone", "free")  # older still, but left
        fid3, q_mid = create(Q, f"Members family {tag}")
        g_mid = join(Q, gone, base + timedelta(days=1))
        n1_mid = join(Q, n1, base + timedelta(days=2))
        n2_mid = join(Q, n2, base + timedelta(days=3))
        c.post("/api/family/leave", headers=gone["h"])
        c.post("/api/family/placeholders", headers=Q["h"], json={"display_name": "Grandpa"})
        db.sql("UPDATE family_members SET joined_at = %s WHERE family_id = %s AND kind = 'placeholder'", base, fid3)
        check(all((fid3, q_mid, g_mid, n1_mid, n2_mid)) and rows(fid3).get(g_mid, {}).get("status") == "former",
              "account deletion: Que's family with Nwe, Nan, a former member and an old placeholder",
              (fid3, q_mid, g_mid, n1_mid, n2_mid))
        r = admin_delete(Q)
        check(r.status_code == 200 and not db.sql("SELECT 1 FROM users WHERE id = %s", Q["id"]),
              "account deletion: a super admin deletes the owner Que", f"{r.status_code} {r.text[:200]}")
        check(owners(fid3) == [n1_mid], "account deletion: the longest-standing account member Nwe is the owner",
              [(m["display_name"], m["role"], m["status"]) for m in rows(fid3).values()])
        check((rows(fid3).get(q_mid) or {}).get("status") == "former",
              "account deletion: Que's row is former", rows(fid3).get(q_mid))
        v = c.get("/api/family", headers=n1["h"]).json()
        check(v.get("me", {}).get("role") == "owner" and v.get("family", {}).get("read_only") is True,
              "account deletion: GET /api/family for Nwe says role owner, read-only (Nwe is on Free)",
              (v.get("me"), v.get("family")))
        r = tx(n2, amount=3)
        check(_code(r, 403, "family_read_only"), "account deletion: a family under a Free owner refuses new entries",
              f"{r.status_code} {r.text[:200]}")
        r = c.post("/api/family/transfer-ownership", headers=n1["h"], json={"member_id": n2_mid})
        check(r.status_code == 200 and tx(n2, amount=3).status_code == 200,
              "account deletion: the new owner can hand over to a Plus member, and it is writable again",
              f"{r.status_code} {r.text[:200]}")

        # ---- the owner alone (placeholders don't count) deletes: the family is gone ----
        S = register("Solo", "plus")
        fid4, _ = create(S, f"Solo family {tag}")
        c.post("/api/family/placeholders", headers=S["h"], json={"display_name": "Cat"})
        tx(S, amount=9)
        book4 = _family_book(fid4)
        r = self_delete(S)
        check(r.status_code == 200, "account deletion: the owner alone deletes their account", f"{r.status_code} {r.text[:200]}")
        check(not db.sql("SELECT 1 FROM families WHERE id = %s", fid4)
              and not db.sql("SELECT 1 FROM family_members WHERE family_id = %s", fid4)
              and not db.sql("SELECT 1 FROM books WHERE id = %s", book4)
              and not db.sql("SELECT 1 FROM transactions WHERE book_id = %s", book4),
              "account deletion: the family, its members, book and entries are deleted")

        # ---- the owner with only former members left (admin path): the family is gone ----
        T = register("Tun", "plus")
        U = register("Ung", "free")
        fid5, _ = create(T, f"Left family {tag}")
        join(T, U)
        c.post("/api/family/leave", headers=U["h"])
        r = admin_delete(T)
        check(r.status_code == 200 and not db.sql("SELECT 1 FROM families WHERE id = %s", fid5),
              "account deletion: an owner whose only other member left takes the family with them",
              f"{r.status_code} {r.text[:200]}")
        check(c.get("/api/family", headers=U["h"]).json() == {"family": None},
              "account deletion: the member who left sees no family")
    finally:
        if books:
            db.sql("DELETE FROM books WHERE id = ANY(%s)", books)
        _cleanup_people(made)
        db.admins.delete_many({"email": sup_email})


def section_family_currency():
    """A family book's currency is its owner's default currency: GET /api/family says it, and the book's defaults (budget
    summary, report, breakdown, an AI-read entry with no currency) use it for every member; a personal book keeps the
    person's own. It follows the owner's currency setting and a change of owner."""
    import httpx

    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:8]
    made = []
    register = _registrar(c, tag, made)
    H = lambda u, family=True: {**u["h"], **FAM} if family else u["h"]  # noqa: E731
    try:
        O, M = register("Owner", "plus"), register("Member", "plus")
        r = c.put("/api/auth/currency", headers=O["h"], json={"default_currency": "mmk"})
        check(r.status_code == 200, "family currency: the owner's default currency is MMK", f"{r.status_code} {r.text[:200]}")
        c.post("/api/family", headers=O["h"], json={"name": f"Kyat family {tag}"})
        c.post("/api/family/invites", headers=O["h"], json={"email": M["email"]})
        inv = next(iter(c.get("/api/family/invites/mine", headers=M["h"]).json().get("invites", [])), None)
        if inv:
            c.post(f"/api/family/invites/{inv['id']}/accept", headers=M["h"])
        m_mid = (c.get("/api/family", headers=M["h"]).json().get("me") or {}).get("member_id")
        check(bool(m_mid), "family currency: the member (default USD) joins the owner's family", m_mid)

        def family_currency(u):
            return (c.get("/api/family", headers=u["h"]).json().get("family") or {}).get("currency")
        check(family_currency(O) == "mmk" and family_currency(M) == "mmk",
              "family currency: GET /api/family gives the owner's currency (MMK) to the owner and the member alike",
              (family_currency(O), family_currency(M)))

        def defaults(u, family=True):
            summary = c.get("/api/budgets/summary", headers=H(u, family))
            report = c.post("/api/reports/generate", headers=H(u, family), json={"period": "month"})
            today = datetime.now(UTC).date()
            breakdown = c.get("/api/family/breakdown", headers=H(u, family),
                              params={"start_date": (today - timedelta(days=30)).isoformat(), "end_date": today.isoformat()})
            return tuple(r.json().get("currency") if r.status_code == 200 else (r.status_code, r.text[:120])
                         for r in (summary, report, breakdown))
        check(defaults(M) == ("mmk", "mmk", "mmk"),
              "family currency: in the family book the member's budget summary, report and breakdown default to MMK",
              defaults(M))
        check(defaults(M, family=False)[:2] == ("usd", "usd"),
              "family currency: the member's personal book keeps the member's own USD", defaults(M, family=False))

        async def extracted():
            """The currency of an AI-read entry that names none, in the member's family and personal book (the AI's
            answer faked in-process; one entry use each)."""
            import transaction_routes as tr
            from families.book import get_book
            from models import TextExtractionRequest
            stubenv.patch_loaded_modules()
            real_run, real_log = tr._run_ai, tr._log_ai_usage

            async def no_currency(*_a, **_k):
                class R:
                    value = {"type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries",
                             "description": "rice", "amount": 5000, "confidence": 0.9}
                return R()
            tr._run_ai, tr._log_ai_usage = no_currency, lambda *_a, **_k: None
            try:
                user = await _person_with_book(M["id"])
                out = []
                for x_book in ("family", None):
                    book = await get_book(user, x_book)
                    e = await tr.extract_transaction_from_text(TextExtractionRequest(text="rice 5000"), user, book)
                    out.append(e.currency.value if hasattr(e.currency, "value") else e.currency)
                return out
            finally:
                tr._run_ai, tr._log_ai_usage = real_run, real_log
        try:
            got = _backend_async(extracted)
        except Exception as e:  # noqa: BLE001
            got = repr(e)[:300]
        check(got == ["mmk", "usd"],
              "family currency: an AI-read entry with no currency gets MMK in the family book, USD in the member's own",
              got)

        c.put("/api/auth/currency", headers=O["h"], json={"default_currency": "usd"})
        check(family_currency(M) == "usd", "family currency: it follows the owner's own currency setting", family_currency(M))
        c.put("/api/auth/currency", headers=M["h"], json={"default_currency": "mmk"})
        r = c.post("/api/family/transfer-ownership", headers=O["h"], json={"member_id": m_mid})
        check(r.status_code == 200 and family_currency(O) == "mmk",
              "family currency: after the owner hands the family over, it is the new owner's (MMK)",
              (r.status_code, family_currency(O)))
    finally:
        _cleanup_people(made)


SECTIONS = {
    "schema": section_schema,
    "book_users": section_book_users,
    "family_rules": section_family_rules,
    "book_scope": section_book_scope,
    "entries_breakdown": section_entries_breakdown,
    "breakdown_rounding": section_breakdown_rounding,
    "recurring_children": section_recurring_children,
    "transfers": section_transfers,
    "budgets_goals": section_budgets_goals,
    "notifications": section_notifications,
    "ai": section_ai,
    "limits": section_limits,
    "account_deletion": section_account_deletion,
    "family_currency": section_family_currency,
}


def main():
    """Runs every section, or only the ones named on the command line (e.g. `test_family.py schema transfers`)."""
    wanted = sys.argv[1:] or list(SECTIONS)
    unknown = [w for w in wanted if w not in SECTIONS]
    if unknown:
        print(f"unknown section(s) {unknown}; choose from {list(SECTIONS)}")
        sys.exit(2)
    for name in wanted:
        SECTIONS[name]()
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
