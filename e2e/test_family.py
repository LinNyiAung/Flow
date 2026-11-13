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


def main():
    section_schema()
    section_book_users()
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
