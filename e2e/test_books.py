"""Books table e2e. One function per section, called from main() (or only the sections named on the command line).

Sections:
  schema -- the books table, book_id on the book data, the typed notification links and the constraints (Task 1).
  migration -- the books migration on a database seeded in the old shape (hidden book users): every row lands on the
    right book, balances and goal totals don't change, transfer legs still pair, notices map by type; then down and
    up again keeps every balance (Task 1).
"""
import os
import sys
import uuid
from decimal import Decimal

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402,F401

db = __import__("pgcompat").get_db()
failures = 0

BEFORE_BOOKS = "522ad619de76"  # the revision the books migration revises
BOOK_TABLES = ("transactions", "budgets", "goals", "insights", "custom_insights")
LINKS = ("goal_id", "budget_id", "transaction_id", "custom_insight_id", "family_invite_id", "family_id")


def check(ok, name, detail=""):
    global failures
    if not ok:
        failures += 1
    print(("[PASS] " if ok else "[BUG] ") + name + (f" -- {detail}" if detail and not ok else ""), flush=True)


def _columns(table):
    rows = db.sql("SELECT column_name, is_nullable FROM information_schema.columns "
                  "WHERE table_schema = 'public' AND table_name = %s", table)
    return {r["column_name"]: r["is_nullable"] for r in rows}


def _expect_cols(table, expected):
    """expected: {column: 'YES' (nullable) / 'NO' (NOT NULL) / None (absent)}"""
    cols = _columns(table)
    for col, nullable in expected.items():
        if nullable is None:
            check(col not in cols, f"schema: {table}.{col} is gone")
        else:
            check(cols.get(col) == nullable, f"schema: {table}.{col} ({'NULL' if nullable == 'YES' else 'NOT NULL'})",
                  "missing" if col not in cols else f"is_nullable={cols[col]}")


def _violates(sql, *params):
    """The exception type's name when the database refuses the statement, else None."""
    try:
        db.sql(sql, *params)
    except Exception as e:  # psycopg IntegrityError subclasses
        return type(e).__name__
    return None


def _indexes():
    return {r["indexname"]: r["indexdef"] for r in db.sql("SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'public'")}


def _tables():
    return {r["table_name"] for r in db.sql("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'")}


# ---------------------------------------------------------------------------------------------------------- schema
def section_schema():
    if "books" not in _tables():
        check(False, "schema: the books table exists", "missing")
        return
    _expect_cols("books", {"id": "NO", "kind": "NO", "person_id": "YES", "family_id": "YES", "ai_data_stale": "NO",
                           "created_at": "NO"})
    for table in BOOK_TABLES:
        _expect_cols(table, {"book_id": "NO", "user_id": None})
    _expect_cols("users", {"kind": None, "ai_data_stale": None})
    _expect_cols("families", {"book_user_id": None})
    _expect_cols("chat_sessions", {"user_id": "NO", "book_id": "NO"})
    _expect_cols("ai_usage", {"user_id": "YES", "book_id": "YES"})
    _expect_cols("notifications", {**{c: "YES" for c in LINKS}, "book_id": "YES", "book": None})

    idx = _indexes()
    for name in ("ix_transactions_book_date", "ix_transactions_book_type_date", "ix_transactions_book_currency",
                 "ix_transactions_book_id", "ix_budgets_book_id", "ix_budgets_book_window", "uq_budgets_rollover_child",
                 "ix_goals_book_id", "ix_goals_book_status_currency", "ix_insights_book_id", "ix_insights_latest",
                 "ix_custom_insights_book_created", "uq_custom_insights_pending_book", "ix_ai_usage_book_id",
                 "uq_books_person_id", "uq_books_family_id", "ix_chat_sessions_book_id",
                 *(f"ix_notifications_{c}" for c in LINKS + ("book_id",))):
        check(name in idx, f"schema: index {name}", "missing")
    for name in ("uq_budgets_rollover_child", "ix_insights_latest", "uq_custom_insights_pending_book"):
        check("book_id" in idx.get(name, "") and "user_id" not in idx.get(name, ""), f"schema: {name} is on book_id",
              idx.get(name))
    stale = [n for n in idx if n.startswith(("ix_transactions_user", "ix_budgets_user", "ix_goals_user", "ix_insights_user",
                                            "ix_custom_insights_user", "uq_custom_insights_pending_user"))]
    check(not stale, "schema: no user_id index is left on the book data", stale)

    # Behaviour: constraints.
    tag = uuid.uuid4().hex[:8]
    p1, p2, fam, fam2 = (f"bk-{tag}-{k}" for k in ("p1", "p2", "f", "f2"))
    book1, goal, budget = (str(uuid.uuid4()) for _ in range(3))
    try:
        for p in (p1, p2):
            db.sql("INSERT INTO users (id, name, email, password) VALUES (%s, 'x', %s, 'x')", p, f"{p}@books.test")
        for f in (fam, fam2):
            db.sql("INSERT INTO families (id, name) VALUES (%s, 'F')", f)
        db.sql("INSERT INTO books (id, kind, person_id) VALUES (%s, 'personal', %s)", book1, p1)
        check(_violates("INSERT INTO books (id, kind, person_id) VALUES (%s, 'personal', %s)", str(uuid.uuid4()), p1)
              == "UniqueViolation", "schema: a second personal book for the same person is refused")
        db.sql("INSERT INTO books (id, kind, family_id) VALUES (%s, 'family', %s)", str(uuid.uuid4()), fam)
        check(_violates("INSERT INTO books (id, kind, family_id) VALUES (%s, 'family', %s)", str(uuid.uuid4()), fam)
              == "UniqueViolation", "schema: a second family book for the same family is refused")
        for label, kind, person, family in (("a personal book with family_id set", "personal", p2, fam2),
                                            ("a personal book without a person", "personal", None, None),
                                            ("a family book with person_id set", "family", p2, fam2),
                                            ("a family book without a family", "family", None, None),
                                            ("an unknown kind", "shared", p2, None)):
            check(_violates("INSERT INTO books (id, kind, person_id, family_id) VALUES (%s, %s, %s, %s)",
                            str(uuid.uuid4()), kind, person, family) == "CheckViolation", f"schema: {label} is refused")
        stale_default = db.sql("SELECT ai_data_stale FROM books WHERE id = %s", book1)
        check(stale_default and stale_default[0]["ai_data_stale"] is False, "schema: books.ai_data_stale defaults to false")

        check(_violates("INSERT INTO transactions (id, book_id, type, main_category, sub_category, amount, currency, date) "
                        "VALUES (%s, %s, 'outflow', 'Food', 'Groceries', 5, 'usd', now())", str(uuid.uuid4()), p1)
              == "ForeignKeyViolation", "schema: a person id where a book id belongs is refused (transactions.book_id FK)")

        db.sql("INSERT INTO goals (id, book_id, name, goal_type, target_amount) VALUES (%s, %s, 'G', 'savings', 100)", goal, book1)
        db.sql("INSERT INTO budgets (id, book_id, name, period, start_date, end_date, total_budget, status) "
               "VALUES (%s, %s, 'B', 'monthly', now(), now(), 10, 'active')", budget, book1)
        check(_violates("INSERT INTO notifications (id, user_id, type, goal_id, budget_id) VALUES (%s, %s, 'goal_progress', %s, %s)",
                        str(uuid.uuid4()), p1, goal, budget) == "CheckViolation",
              "schema: a notification with both goal_id and budget_id is refused")
        check(_violates("INSERT INTO notifications (id, user_id, type, goal_id) VALUES (%s, %s, 'goal_progress', %s)",
                        str(uuid.uuid4()), p1, "no-such-goal") == "ForeignKeyViolation",
              "schema: a notification linking a missing goal is refused")
        nid = str(uuid.uuid4())
        db.sql("INSERT INTO notifications (id, user_id, type, title, goal_id, book_id) VALUES (%s, %s, 'goal_progress', 'kept', %s, %s)",
               nid, p1, goal, book1)
        db.sql("DELETE FROM goals WHERE id = %s", goal)
        row = db.sql("SELECT goal_id, book_id, title FROM notifications WHERE id = %s", nid)
        check(row and row[0]["goal_id"] is None and row[0]["book_id"] == book1 and row[0]["title"] == "kept",
              "schema: deleting a notice's goal keeps the notice with its link cleared", row)
        n_ai = str(uuid.uuid4())
        db.sql("INSERT INTO ai_usage (id, user_id, book_id, feature_type, provider, model_name, estimated_cost_usd) "
               "VALUES (%s, NULL, %s, 'insight_weekly', 'openai', 'm', 0.5)", n_ai, book1)
        db.sql("DELETE FROM users WHERE id = %s", p1)  # cascades to the personal book and its data
        left = db.sql("SELECT id FROM books WHERE id = %s", book1)
        usage = db.sql("SELECT user_id, book_id, estimated_cost_usd FROM ai_usage WHERE id = %s", n_ai)
        check(not left and not db.sql("SELECT 1 FROM budgets WHERE id = %s", budget),
              "schema: deleting a person deletes their personal book and its data")
        check(usage and usage[0]["book_id"] is None and usage[0]["estimated_cost_usd"] == Decimal("0.5"),
              "schema: a deleted book's AI spend stays, with book_id cleared", usage)
        db.sql("DELETE FROM ai_usage WHERE id = %s", n_ai)
    finally:
        db.sql("DELETE FROM users WHERE id IN (%s, %s)", p1, p2)
        db.sql("DELETE FROM families WHERE id IN (%s, %s)", fam, fam2)


# ------------------------------------------------------------------------------------------------------- migration
def _sums(owner_col, owners):
    """{(owner, currency): inflow - outflow} for these owners."""
    rows = db.sql(f"SELECT {owner_col} AS o, currency, SUM(CASE type WHEN 'inflow' THEN amount ELSE -amount END) AS s "
                  f"FROM transactions WHERE {owner_col} = ANY(%s) GROUP BY 1, 2", list(owners))
    return {(r["o"], r["currency"]): r["s"] for r in rows}


def _goal_totals(owner_col, owners):
    rows = db.sql(f"SELECT {owner_col} AS o, currency, SUM(current_amount) AS s FROM goals WHERE {owner_col} = ANY(%s) GROUP BY 1, 2",
                  list(owners))
    return {(r["o"], r["currency"]): r["s"] for r in rows}


def _remap(totals, mapping):
    return {(mapping.get(o, o), cur): s for (o, cur), s in totals.items()}


def _seed_old_shape(ids):
    """Raw SQL in the old (522ad619de76) shape: people A and B, a family whose data sits under a hidden book user."""
    A, B, BU, F = ids["A"], ids["B"], ids["BU"], ids["F"]
    q = db.sql
    for uid, kind, stale in ((A, "person", False), (B, "person", False), (BU, "family_book", True)):
        q("INSERT INTO users (id, name, email, password, kind, ai_data_stale) VALUES (%s, 'x', %s, '$2b$12$x', %s, %s)",
          uid, f"{uid}@books.test", kind, stale)
    q("INSERT INTO families (id, name, book_user_id) VALUES (%s, 'Fam', %s)", F, BU)
    q("INSERT INTO family_members (id, family_id, user_id, display_name, kind, role) VALUES (%s, %s, %s, 'A', 'account', 'owner')",
      ids["MA"], F, A)
    q("INSERT INTO family_invites (id, family_id, email, status, expires_at) VALUES (%s, %s, %s, 'pending', now() + interval '7 days')",
      ids["INV"], F, f"{B}@books.test")

    tx = "INSERT INTO transactions (id, user_id, type, main_category, sub_category, amount, currency, date, transfer_id, " \
         "added_by_member_id) VALUES (%s, %s, %s, 'Food', 'Groceries', %s, %s, now(), %s, %s)"
    for key, owner, type_, amount, cur, transfer, member in (
            ("txA1", A, "inflow", "1000.00", "mmk", None, None), ("txA2", A, "outflow", "300.50", "mmk", None, None),
            ("txA3", A, "inflow", "50.00", "usd", None, None), ("txA4", A, "outflow", "20.25", "usd", None, None),
            ("txB1", B, "inflow", "70.00", "usd", None, None), ("txB2", B, "outflow", "5.00", "mmk", None, None),
            ("txF1", BU, "inflow", "200.00", "mmk", None, ids["MA"]), ("txF2", BU, "outflow", "40.00", "mmk", None, ids["MA"]),
            ("trA", A, "outflow", "100.00", "mmk", ids["T"], None), ("trF", BU, "inflow", "100.00", "mmk", ids["T"], ids["MA"])):
        q(tx, ids[key], owner, type_, Decimal(amount), cur, transfer, member)

    bud = "INSERT INTO budgets (id, user_id, name, period, currency, start_date, end_date, total_budget, status, parent_budget_id) " \
          "VALUES (%s, %s, 'B', 'monthly', 'mmk', now() + %s * interval '31 days', now() + %s * interval '31 days' + interval '30 days', 500, 'active', %s)"
    q(bud, ids["budA"], A, 0, 0, None)
    q(bud, ids["budA2"], A, 1, 1, ids["budA"])  # a rollover child (uq_budgets_rollover_child)
    q(bud, ids["budF"], BU, 0, 0, None)
    for pos, cat, amt in ((0, "Food", 300), (1, "Transport", 200)):
        q("INSERT INTO budget_allocations (budget_id, position, main_category, allocated_amount) VALUES (%s, %s, %s, %s)",
          ids["budA"], pos, cat, amt)

    goal = "INSERT INTO goals (id, user_id, name, goal_type, target_amount, current_amount, currency) VALUES (%s, %s, 'G', 'savings', 1000, %s, %s)"
    q(goal, ids["goalA"], A, Decimal("150.00"), "usd")
    q(goal, ids["goalF"], BU, Decimal("30.00"), "mmk")

    q("INSERT INTO insights (id, user_id, insight_type, ai_provider, content) VALUES (%s, %s, 'weekly', 'openai', 'x')", ids["insA"], A)
    q("INSERT INTO insights (id, user_id, insight_type, ai_provider, content) VALUES (%s, %s, 'weekly', 'openai', 'x')", ids["insF"], BU)
    q("INSERT INTO custom_insights (id, user_id, start_date, end_date, status, content) VALUES (%s, %s, '2026-10-01', '2026-10-31', 'ready', 'r')",
      ids["ciA"], A)
    q("INSERT INTO custom_insights (id, user_id, start_date, end_date, status) VALUES (%s, %s, '2026-10-01', '2026-10-31', 'pending')",
      ids["ciF"], BU)

    q("INSERT INTO chat_sessions (id, user_id, book_id) VALUES (%s, %s, NULL)", ids["chatA"], A)
    q("INSERT INTO chat_sessions (id, user_id, book_id) VALUES (%s, %s, %s)", ids["chatF"], A, BU)
    q("INSERT INTO chat_messages (session_id, role, content) VALUES (%s, 'user', 'hi')", ids["chatA"])
    q("INSERT INTO chat_messages (session_id, role, content) VALUES (%s, 'user', 'hi family')", ids["chatF"])

    ai = "INSERT INTO ai_usage (id, user_id, feature_type, provider, model_name, estimated_cost_usd) VALUES (%s, %s, %s, 'openai', 'm', %s)"
    q(ai, ids["aiA"], A, "chat", Decimal("0.010000"))
    q(ai, ids["aiF"], BU, "insight_weekly", Decimal("0.020000"))

    # (key, recipient, type, old goal_id, book)
    notices = (
        ("nGoal", A, "goal_achieved", ids["goalA"], None),
        ("nGoalF", A, "goal_progress", ids["goalF"], "family"),
        ("nBudget", A, "budget_started", ids["budA"], None),
        ("nBudgetGone", A, "budget_threshold", "no-such-budget", None),
        ("nTx", A, "large_transaction", ids["txA2"], None),
        ("nCi", A, "custom_insight_ready", ids["ciA"], None),
        ("nInv", B, "family_invite", ids["INV"], None),
        ("nOwner", A, "family_owner", F, None),
        ("nWeekA", A, "weekly_insights_generated", None, None),
        ("nWeekF", A, "monthly_insights_generated", BU, "family"),
        ("nUnusual", A, "unusual_spending", None, None),
    )
    for key, rcpt, type_, gid, book in notices:
        q("INSERT INTO notifications (id, user_id, type, title, goal_id, book) VALUES (%s, %s, %s, %s, %s, %s)",
          ids[key], rcpt, type_, key, gid, book)
    return {key: (gid, book) for key, _, _, gid, book in notices}


def _old_shape_ok(ids, label):
    cols = _columns("users")
    check("books" not in _tables() and "kind" in cols and "ai_data_stale" in cols and "book_user_id" in _columns("families")
          and "user_id" in _columns("transactions") and "book" in _columns("notifications"),
          f"migration: {label}: the old shape is back (no books; users.kind, families.book_user_id, user_id, notifications.book)")


def section_migration():
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend"))
    import test_plans as t  # noqa: E402  (alembic helper)
    from plans_subscription_checks import head_revision  # noqa: E402

    head = head_revision()
    keys = ("A", "B", "BU", "F", "MA", "INV", "T", "txA1", "txA2", "txA3", "txA4", "txB1", "txB2", "txF1", "txF2", "trA", "trF",
            "budA", "budA2", "budF", "goalA", "goalF", "insA", "insF", "ciA", "ciF", "chatA", "chatF", "aiA", "aiF",
            "nGoal", "nGoalF", "nBudget", "nBudgetGone", "nTx", "nCi", "nInv", "nOwner", "nWeekA", "nWeekF", "nUnusual")
    tag = uuid.uuid4().hex[:8]
    ids = {k: (f"bk-{tag}-{k}" if k in ("A", "B") else str(uuid.uuid4())) for k in keys}
    A, B, BU, F = ids["A"], ids["B"], ids["BU"], ids["F"]
    owners = (A, B, BU)
    with t.connect() as conn:
        check(t.current_revision(conn) == head, "migration: the e2e database starts at head", t.current_revision(conn))
    try:
        ok, out = t.alembic("downgrade", BEFORE_BOOKS)
        check(ok, f"migration: downgrade to {BEFORE_BOOKS} runs", out)
        if not ok:
            return
        old_notices = _seed_old_shape(ids)
        sums = _sums("user_id", owners)
        goals = _goal_totals("user_id", owners)
        check(len(sums) == 5 and len(goals) == 2, "migration: the seed recorded balances for A, B and the family", (sums, goals))

        # ---- up
        ok, out = t.alembic("upgrade", "head")
        check(ok, "migration: upgrade head runs on the seeded old shape", out)
        if not ok:
            return
        _check_upgraded(ids, sums, goals, "upgrade")

        # ---- down then up keeps every balance
        ok, out = t.alembic("downgrade", BEFORE_BOOKS)
        check(ok, "down then up keeps every balance: downgrade runs on the migrated data", out)
        if not ok:
            return
        _old_shape_ok(ids, "after downgrade")
        check(_sums("user_id", owners) == sums, "down then up keeps every balance: per-owner balances after downgrade",
              (_sums("user_id", owners), sums))
        check(_goal_totals("user_id", owners) == goals, "down then up keeps every balance: goal totals after downgrade",
              (_goal_totals("user_id", owners), goals))
        bu = db.sql("SELECT kind, email, password, is_verified, subscription_type, language, ai_data_stale FROM users WHERE id = %s", BU)
        check(bu and bu[0]["kind"] == "family_book" and bu[0]["email"] == f"family-{F}@book.invalid"
              and str(bu[0]["password"]).startswith("$2") and bu[0]["is_verified"] is True
              and bu[0]["subscription_type"] == "free" and bu[0]["language"] == "en" and bu[0]["ai_data_stale"] is True,
              "down then up keeps every balance: the book user is back (family_book, reserved e-mail, bcrypt hash, verified, free, en, stale kept)",
              bu)
        fam = db.sql("SELECT book_user_id FROM families WHERE id = %s", F)
        check(fam and fam[0]["book_user_id"] == BU, "down then up keeps every balance: families.book_user_id is restored", fam)
        persons = db.sql("SELECT id, kind, ai_data_stale FROM users WHERE id = ANY(%s)", [A, B])
        check(len(persons) == 2 and all(p["kind"] == "person" and p["ai_data_stale"] is False for p in persons),
              "down then up keeps every balance: people are kind 'person' with their stale flag", persons)
        expect_owner = {"txA1": A, "txB1": B, "txF1": BU, "trA": A, "trF": BU}
        got = {k: (db.sql("SELECT user_id FROM transactions WHERE id = %s", ids[k]) or [{}])[0].get("user_id") for k in expect_owner}
        check(got == expect_owner, "down then up keeps every balance: transactions are back on user_id", got)
        for table, key, owner in (("budgets", "budA", A), ("budgets", "budF", BU), ("goals", "goalF", BU),
                                  ("insights", "insF", BU), ("custom_insights", "ciA", A), ("custom_insights", "ciF", BU)):
            r = db.sql(f"SELECT user_id FROM {table} WHERE id = %s", ids[key])
            check(r and r[0]["user_id"] == owner, f"down then up keeps every balance: {table} {key} is back on its owner", r)
        chats = {r["id"]: r["book_id"] for r in db.sql("SELECT id, book_id FROM chat_sessions WHERE id = ANY(%s)", [ids["chatA"], ids["chatF"]])}
        check(chats == {ids["chatA"]: None, ids["chatF"]: BU}, "down then up keeps every balance: chat book_id is NULL (personal) / the book user",
              chats)
        usage = {r["id"]: r["user_id"] for r in db.sql("SELECT id, user_id FROM ai_usage WHERE id = ANY(%s)", [ids["aiA"], ids["aiF"]])}
        check(usage == {ids["aiA"]: A, ids["aiF"]: BU}, "down then up keeps every balance: ai_usage is back under the person / book user", usage)
        rows = {r["id"]: (r["goal_id"], r["book"]) for r in db.sql("SELECT id, goal_id, book FROM notifications WHERE id = ANY(%s)",
                                                                   [ids[k] for k in old_notices])}
        want = {ids[k]: (None if k == "nBudgetGone" else gid, book) for k, (gid, book) in old_notices.items()}
        check(rows == want, "down then up keeps every balance: notices' goal_id and book are restored (a link to nothing stays NULL)",
              {k: (rows.get(ids[k]), want[ids[k]]) for k in old_notices if rows.get(ids[k]) != want[ids[k]]})

        ok, out = t.alembic("upgrade", "head")
        check(ok, "down then up keeps every balance: upgrade head runs again", out)
        if ok:
            _check_upgraded(ids, sums, goals, "upgrade again")
    finally:
        ok, out = t.alembic("upgrade", "head")  # whatever happened above, leave the database at head
        with t.connect() as conn:
            check(ok and t.current_revision(conn) == head, "migration: the e2e database is left at head", out)
            _cleanup(conn, ids)


def _cleanup(conn, ids):
    """Remove everything seeded (works in either shape)."""
    conn.execute("DELETE FROM ai_usage WHERE id = ANY(%s)", ([ids["aiA"], ids["aiF"]],))
    conn.execute("DELETE FROM families WHERE id = %s", (ids["F"],))  # its family book (and data) or nothing
    conn.execute("DELETE FROM users WHERE id = ANY(%s)", ([ids["A"], ids["B"], ids["BU"]],))  # personal books, notices


def _check_upgraded(ids, sums, goals, label):
    A, B, BU, F = ids["A"], ids["B"], ids["BU"], ids["F"]
    if "books" not in _tables():
        check(False, f"migration ({label}): the books table exists", "missing")
        return
    books = {r["person_id"] or r["family_id"]: r for r in db.sql(
        "SELECT id, kind, person_id, family_id, ai_data_stale FROM books WHERE person_id = ANY(%s) OR family_id = %s", [A, B], F)}
    bA, bB, bF = (books.get(k, {}).get("id") for k in (A, B, F))
    check(bA and bB and bF and books[A]["kind"] == "personal" and books[B]["kind"] == "personal" and books[F]["kind"] == "family",
          f"migration ({label}): A and B have a personal book and the family a family book", books)
    if not (bA and bB and bF):
        return
    check(bF == BU, f"migration ({label}): the family book's id is the old book user id", (bF, BU))
    check(len({bA, bB, A, B}) == 4, f"migration ({label}): personal book ids are new (never a user id)", (bA, bB))
    check(books[F]["ai_data_stale"] is True and books[A]["ai_data_stale"] is False,
          f"migration ({label}): ai_data_stale moved to the books (family true, A false)",
          (books[F]["ai_data_stale"], books[A]["ai_data_stale"]))
    clash = db.sql("SELECT count(*) AS n FROM users u JOIN books b ON b.id = u.id")[0]["n"]
    check(clash == 0, f"migration ({label}): no users row has a book id", clash)
    check(not db.sql("SELECT 1 FROM users WHERE id = %s", BU), f"migration ({label}): the book user row is gone")

    owner = {A: bA, B: bB, BU: bF}
    expect = {"transactions": {"txA1": bA, "txA2": bA, "txA3": bA, "txA4": bA, "txB1": bB, "txB2": bB, "txF1": bF,
                               "txF2": bF, "trA": bA, "trF": bF},
              "budgets": {"budA": bA, "budA2": bA, "budF": bF}, "goals": {"goalA": bA, "goalF": bF},
              "insights": {"insA": bA, "insF": bF}, "custom_insights": {"ciA": bA, "ciF": bF}}
    for table, want in expect.items():
        got = {k: (db.sql(f"SELECT book_id FROM {table} WHERE id = %s", ids[k]) or [{}])[0].get("book_id") for k in want}
        check(got == want, f"migration ({label}): every {table} row sits on the right book",
              {k: (got[k], want[k]) for k in want if got[k] != want[k]})
    check(_sums("book_id", owner.values()) == _remap(sums, owner), f"migration ({label}): per-book balances equal the recorded ones",
          (_sums("book_id", owner.values()), _remap(sums, owner)))
    check(_goal_totals("book_id", owner.values()) == _remap(goals, owner), f"migration ({label}): goal totals equal the recorded ones",
          (_goal_totals("book_id", owner.values()), _remap(goals, owner)))
    legs = {r["id"]: r for r in db.sql("SELECT id, book_id, transfer_id, added_by_member_id FROM transactions WHERE id = ANY(%s)",
                                       [ids["trA"], ids["trF"]])}
    check(len(legs) == 2 and legs[ids["trA"]]["transfer_id"] == legs[ids["trF"]]["transfer_id"] == ids["T"]
          and legs[ids["trA"]]["book_id"] == bA and legs[ids["trF"]]["book_id"] == bF
          and legs[ids["trF"]]["added_by_member_id"] == ids["MA"],
          f"migration ({label}): both transfer legs share transfer_id, on A's book and the family book", legs)
    alloc = db.sql("SELECT count(*) AS n FROM budget_allocations WHERE budget_id = %s", ids["budA"])[0]["n"]
    check(alloc == 2, f"migration ({label}): the budget keeps its allocations", alloc)

    chats = {r["id"]: (r["user_id"], r["book_id"]) for r in db.sql(
        "SELECT id, user_id, book_id FROM chat_sessions WHERE id = ANY(%s)", [ids["chatA"], ids["chatF"]])}
    check(chats == {ids["chatA"]: (A, bA), ids["chatF"]: (A, bF)},
          f"migration ({label}): chat sessions keep the person and point at the personal / family book", chats)
    msgs = db.sql("SELECT count(*) AS n FROM chat_messages WHERE session_id = ANY(%s)", [ids["chatA"], ids["chatF"]])[0]["n"]
    check(msgs == 2, f"migration ({label}): chat messages are kept", msgs)

    usage = {r["id"]: (r["user_id"], r["book_id"]) for r in db.sql(
        "SELECT id, user_id, book_id FROM ai_usage WHERE id = ANY(%s)", [ids["aiA"], ids["aiF"]])}
    check(usage == {ids["aiA"]: (A, None), ids["aiF"]: (None, bF)},
          f"migration ({label}): the person's AI spend stays under user_id; the book user's moves to book_id with user_id NULL", usage)

    link = {"nGoal": ("goal_id", ids["goalA"], bA), "nGoalF": ("goal_id", ids["goalF"], bF),
            "nBudget": ("budget_id", ids["budA"], bA), "nBudgetGone": (None, None, None),
            "nTx": ("transaction_id", ids["txA2"], bA), "nCi": ("custom_insight_id", ids["ciA"], bA),
            "nInv": ("family_invite_id", ids["INV"], None), "nOwner": ("family_id", F, None),
            "nWeekA": (None, None, bA), "nWeekF": (None, None, bF), "nUnusual": (None, None, None)}
    rows = {r["id"]: r for r in db.sql(f"SELECT id, {', '.join(LINKS)}, book_id FROM notifications WHERE id = ANY(%s)",
                                       [ids[k] for k in link])}
    for key, (col, value, book) in link.items():
        r = rows.get(ids[key])
        want = {c: (value if c == col else None) for c in LINKS} | {"book_id": book}
        got = {c: r[c] for c in want} if r else None
        check(got == want, f"migration ({label}): notice {key} has the right typed link and book_id",
              {"got": got, "want": want})


SECTIONS = {"schema": section_schema, "migration": section_migration}


def main():
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
