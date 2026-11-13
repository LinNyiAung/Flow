"""Family book e2e. One function per section, called from main().

Sections:
  schema -- the tables / columns / indexes the family book needs (Task 1).
"""
import os
import sys
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402,F401

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


def main():
    section_schema()
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
