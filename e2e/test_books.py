"""Books table e2e. One function per section, called from main() (or only the sections named on the command line).

Sections:
  schema -- the books table, book_id on the book data, the typed notification links and the constraints (Task 1).
  migration -- the books migration on a database seeded in the old shape (hidden book users): every row lands on the
    right book, balances and goal totals don't change, transfer legs still pair, notices map by type; then down and
    up again keeps every balance (Task 1).
  books_in_requests -- registration and family creation create the books, a person row without a book gets one on
    its first request, a person id finds no book data, the freshness flag and book_profile work on books, and deleting
    a family (or its lone owner's account) deletes its book (Task 2). Needs the stub server on 127.0.0.1:8765.
  api_shape -- transactions, budgets, goals and insights (created, generated and listed) carry book_id, the personal
    or the family book, and no user_id (Task 3). Needs the stub server.
  books_api -- through the API: a family's book answers 200 [] right after the family is created, a POST marks the
    right book stale, and a person seeded in the old shape and migrated sees the same transactions, balance, budgets
    and goals (Task 3). Needs the stub server.
  jobs -- the scheduled jobs on books, in-process with the AI faked: the weekly insight job makes one insight per book
    (paid persons' personal books, a paid owner's family book, nothing for Free) and records a family insight's spend
    on the book; the recurring job writes a child in its parent's book and tells only the adder; a family's AI
    auto-create budget follows the owner's plan; unusual spending skips family books (Task 4). Needs the stub server.
  notification_links -- each notice stores its subject in its typed link (and its book in book_id); the API and push
    data carry subject_id and book, never goal_id; deleting the subject or the family keeps the notice unlinked; a
    notice about a subject already gone is stored unlinked; insight notices dedupe per book (Task 5). Needs the stub
    server.
"""
import os
import sys
import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal

# The jobs section runs the insight and budget jobs in-process: the stubenv fake AI must answer (as in the full suite).
os.environ.setdefault("E2E_FAKE_AI", "1")
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
    """{(owner, currency): held for goals}. Pre-books (user_id, the old revision) goals still hold current_amount; at
    head a goal's money is the sum of its goal_entries."""
    if owner_col == "user_id":
        rows = db.sql("SELECT user_id AS o, currency, SUM(current_amount) AS s FROM goals WHERE user_id = ANY(%s) GROUP BY 1, 2",
                      list(owners))
    else:
        rows = db.sql("SELECT g.book_id AS o, g.currency, COALESCE(SUM(e.amount), 0) AS s FROM goals g "
                      "LEFT JOIN goal_entries e ON e.goal_id = g.id WHERE g.book_id = ANY(%s) GROUP BY 1, 2", list(owners))
    return {(r["o"], r["currency"]): r["s"] for r in rows}


def _remap(totals, mapping):
    return {(mapping.get(o, o), cur): s for (o, cur), s in totals.items()}


def _seed_old_shape(ids):
    """Raw SQL in the old (522ad619de76) shape: people A and B, a family whose data sits under a hidden book user."""
    A, B, BU, F = ids["A"], ids["B"], ids["BU"], ids["F"]
    q = db.sql
    # BU2: the book user of a family already deleted (no families row points at it any more).
    for uid, kind, stale in ((A, "person", False), (B, "person", False), (BU, "family_book", True),
                             (ids["BU2"], "family_book", False)):
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
        ("nWeekGone", A, "weekly_insights_generated", ids["BU2"], "family"),  # a deleted family's insight notice
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
    keys = ("A", "B", "BU", "BU2", "F", "MA", "INV", "T", "txA1", "txA2", "txA3", "txA4", "txB1", "txB2", "txF1", "txF2", "trA", "trF",
            "budA", "budA2", "budF", "goalA", "goalF", "insA", "insF", "ciA", "ciF", "chatA", "chatF", "aiA", "aiF",
            "nGoal", "nGoalF", "nBudget", "nBudgetGone", "nTx", "nCi", "nInv", "nOwner", "nWeekA", "nWeekF", "nWeekGone",
            "nUnusual")
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
        # A link to nothing stays NULL; the deleted family's insight notice had no book after the upgrade, so it comes
        # back with neither goal_id nor book.
        want = {ids[k]: ((None, None) if k == "nWeekGone" else (None if k == "nBudgetGone" else gid, book))
                for k, (gid, book) in old_notices.items()}
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
    conn.execute("DELETE FROM users WHERE id = ANY(%s)", ([ids["A"], ids["B"], ids["BU"], ids["BU2"]],))  # personal books, notices


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
            "nWeekA": (None, None, bA), "nWeekF": (None, None, bF), "nUnusual": (None, None, None),
            # A deleted family's insight notice gets no book (not the recipient's personal one). After a downgrade it
            # has neither goal_id nor book, so the second upgrade reads it as a personal insight notice.
            "nWeekGone": (None, None, None if label == "upgrade" else bA)}
    rows = {r["id"]: r for r in db.sql(f"SELECT id, {', '.join(LINKS)}, book_id FROM notifications WHERE id = ANY(%s)",
                                       [ids[k] for k in link])}
    for key, (col, value, book) in link.items():
        r = rows.get(ids[key])
        want = {c: (value if c == col else None) for c in LINKS} | {"book_id": book}
        got = {c: r[c] for c in want} if r else None
        check(got == want, f"migration ({label}): notice {key} has the right typed link and book_id",
              {"got": got, "want": want})


# ----------------------------------------------------------------------------------------------- books in requests
BASE = "http://127.0.0.1:8765"


def _backend_async(coro_fn):
    """Run backend async code (its DB engine binds to the loop, so one asyncio.run per call and a fresh engine)."""
    import asyncio

    async def go():
        from sql import db as sqldb
        try:
            return await coro_fn()
        finally:
            await sqldb.dispose_engine()
    return asyncio.run(go())


class _captured_logs:
    """`with _captured_logs("logger.name") as logs:` -> logs gets (level name, message) of every record logged there."""

    def __init__(self, name):
        import logging
        self.logger, self.records = logging.getLogger(name), []
        records = self.records

        class _Keep(logging.Handler):
            def emit(self, record):
                records.append((record.levelname, record.getMessage()))
        self.handler = _Keep(level=logging.DEBUG)

    def __enter__(self):
        self.logger.addHandler(self.handler)
        return self.records

    def __exit__(self, *exc):
        self.logger.removeHandler(self.handler)
        return False


def _books_of(person_id=None, family_id=None):
    if person_id is not None:
        return db.sql("SELECT id, kind FROM books WHERE person_id = %s", person_id)
    return db.sql("SELECT id, kind FROM books WHERE family_id = %s", family_id)


def _seed_tx(book_id, amount="10.00", type_="inflow"):
    tx_id = str(uuid.uuid4())
    db.sql("INSERT INTO transactions (id, book_id, type, main_category, sub_category, amount, currency, date) "
           "VALUES (%s, %s, %s, 'Food', 'Groceries', %s, 'usd', now())", tx_id, book_id, type_, Decimal(amount))
    return tx_id


def section_books_in_requests():
    import bcrypt
    import httpx

    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:8]
    made = []  # user ids to delete at the end (their personal books and families go with them)

    def register(name, plan="free"):
        """A verified account on `plan` registered through the API: {"id", "email", "h"}."""
        email = f"bk-{name.lower()}-{tag}@example.com"
        r = c.post("/api/auth/register", json={"name": name, "email": email, "password": "secret123"})
        if r.status_code != 200:
            check(False, f"books in requests: register {name}", f"{r.status_code} {r.text[:200]}")
            return None
        uid = db.sql("SELECT id FROM users WHERE email = %s", email)[0]["id"]
        made.append(uid)
        expires = None if plan == "free" else datetime.now(UTC) + timedelta(days=30)
        db.sql("UPDATE users SET is_verified = true, subscription_type = %s, subscription_expires_at = %s, "
               "trial_ends_at = NULL WHERE id = %s", plan, expires, uid)
        token = c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json().get("access_token")
        return {"id": uid, "email": email, "h": {"Authorization": f"Bearer {token}"}}

    try:
        # ---- register creates one personal book
        A = register("Ann")
        if A is None:
            return
        books = _books_of(person_id=A["id"])
        check(len(books) == 1 and books[0]["kind"] == "personal",
              "register creates one personal book: exactly one personal book for the new user", books)
        bookA = books[0]["id"] if books else None
        check(bookA is not None and bookA != A["id"], "register creates one personal book: its id is not the user id",
              (bookA, A["id"]))

        # ---- creating a family creates one family book
        O = register("Owner", "plus")
        r = c.post("/api/family", json={"name": f"Fam {tag}"}, headers=O["h"])
        check(r.status_code == 200 and (r.json().get("family") or {}).get("id"),
              "creating a family creates one family book: POST /api/family answers 200", f"{r.status_code} {r.text[:200]}")
        family_id = ((r.json() if r.status_code == 200 else {}).get("family") or {}).get("id")
        fbooks = _books_of(family_id=family_id) if family_id else []
        check(len(fbooks) == 1 and fbooks[0]["kind"] == "family",
              "creating a family creates one family book: exactly one family book for the family", fbooks)
        bookF = fbooks[0]["id"] if fbooks else None
        check(bookF is not None and not db.sql("SELECT 1 FROM users WHERE id = %s", bookF),
              "creating a family creates one family book: the family book is not a users row")

        # ---- user without a book gets one (a person row written by older code or by a test, P2)
        N = f"bk-{tag}-nobook"
        email_n = f"{N}@example.com"  # the login validator refuses reserved domains such as .test
        pw_hash = bcrypt.hashpw(b"secret123", bcrypt.gensalt()).decode()
        db.sql("INSERT INTO users (id, name, email, password, is_verified) VALUES (%s, 'No Book', %s, %s, true)",
               N, email_n, pw_hash)
        made.append(N)
        check(not _books_of(person_id=N), "user without a book gets one: the seeded person has no book yet")
        r = c.post("/api/auth/login", json={"email": email_n, "password": "secret123"})
        check(r.status_code == 200, "user without a book gets one: login works", f"{r.status_code} {r.text[:200]}")
        hn = {"Authorization": f"Bearer {(r.json().get('access_token') if r.status_code == 200 else None) or 'none'}"}
        r = c.get("/api/auth/me", headers=hn)
        check(r.status_code == 200, "user without a book gets one: an authenticated request answers 200",
              f"{r.status_code} {r.text[:200]}")
        c.get("/api/auth/me", headers=hn)  # a second request must not create another one
        nb = _books_of(person_id=N)
        check(len(nb) == 1 and nb[0]["kind"] == "personal" and nb[0]["id"] != N,
              "user without a book gets one: now exactly one personal book exists", nb)

        # ---- a person id is not a book id
        if bookA:
            _seed_tx(bookA, "12.00")

            async def by_ids():
                from sql import transactions as transactions_db
                return (await transactions_db.find_transactions(A["id"]),
                        await transactions_db.find_transactions(bookA))
            try:
                by_person, by_book = _backend_async(by_ids)
                check(by_person == [] and len(by_book) == 1,
                      "a person id is not a book id: find_transactions(<A's user id>) finds nothing, A's book finds the entry",
                      (len(by_person), len(by_book)))
            except Exception as e:  # noqa: BLE001
                check(False, "a person id is not a book id: find_transactions by id runs", repr(e))

        # ---- the freshness flag lives on the book (personal and family)
        def stale(book_id):
            row = db.sql("SELECT ai_data_stale FROM books WHERE id = %s", book_id)
            return row[0]["ai_data_stale"] if row else None

        for label, book_id in (("personal", bookA), ("family", bookF)):
            if not book_id:
                continue

            async def flag(book_id=book_id):
                from sql import books as books_db
                await books_db.mark_ai_data_stale(book_id)
                marked = stale(book_id)
                return marked, await books_db.claim_ai_data_fresh(book_id), await books_db.claim_ai_data_fresh(book_id)
            try:
                marked, first, second = _backend_async(flag)
                check(marked is True, f"book freshness flag ({label}): mark_ai_data_stale sets the book's ai_data_stale", marked)
                check(first is True and second is False,
                      f"book freshness flag ({label}): claim_ai_data_fresh is True once, then False", (first, second))
                check(stale(book_id) is False, f"book freshness flag ({label}): the flag is cleared")
            except Exception as e:  # noqa: BLE001
                check(False, f"book freshness flag ({label}): the books helpers run", repr(e))

        # ---- the money lock is the book's row lock; book_profile is the book's settings person
        if bookA and bookF:
            async def profiles():
                from sql import books as books_db
                return (await books_db.book_profile(bookA), await books_db.book_profile(bookF),
                        await books_db.book_profile(A["id"]), await books_db.get_book_row(bookF))
            try:
                pa, pf, pnone, rowf = _backend_async(profiles)
                check((pa or {}).get("_id") == A["id"] and (pf or {}).get("_id") == O["id"] and pnone is None,
                      "book_profile: a personal book's person, a family book's owner, None for a person id",
                      ((pa or {}).get("_id"), (pf or {}).get("_id"), pnone))
                check(rowf and rowf["kind"] == "family" and rowf["family_id"] == family_id and rowf["person_id"] is None,
                      "get_book_row: the family book's row", rowf)
            except Exception as e:  # noqa: BLE001
                check(False, "book_profile / get_book_row run", repr(e))

        # ---- deleting a family deletes its book
        if family_id and bookF:
            tx_f = _seed_tx(bookF, "7.00")
            r = c.request("DELETE", "/api/family", json={"confirm_name": f"Fam {tag}"}, headers=O["h"])
            check(r.status_code == 200, "deleting a family deletes its book: DELETE /api/family answers 200",
                  f"{r.status_code} {r.text[:200]}")
            check(not db.sql("SELECT 1 FROM books WHERE id = %s", bookF) and not _books_of(family_id=family_id),
                  "deleting a family deletes its book: no family book row is left")
            check(not db.sql("SELECT 1 FROM transactions WHERE id = %s", tx_f),
                  "deleting a family deletes its book: its transactions are gone")
            check(len(_books_of(person_id=O["id"])) == 1, "deleting a family deletes its book: the owner's personal book stays")

        # ---- an owner alone deleting their account takes the family and its book along
        S = register("Solo", "plus")
        r = c.post("/api/family", json={"name": f"Solo {tag}"}, headers=S["h"])
        solo_family = ((r.json() if r.status_code == 200 else {}).get("family") or {}).get("id")
        solo_book = (_books_of(family_id=solo_family) or [{}])[0].get("id") if solo_family else None
        check(solo_book is not None, "owner's account deletion: the solo owner's family has a book", r.text[:200])
        if solo_book:
            r = c.request("DELETE", "/api/auth/delete-account", json={"password": "secret123"}, headers=S["h"])
            check(r.status_code == 200, "owner's account deletion: DELETE /api/auth/delete-account answers 200",
                  f"{r.status_code} {r.text[:200]}")
            check(not db.sql("SELECT 1 FROM families WHERE id = %s", solo_family)
                  and not db.sql("SELECT 1 FROM books WHERE id = %s", solo_book)
                  and not _books_of(person_id=S["id"]),
                  "owner's account deletion: the family, its book and the personal book are gone")
    finally:
        if made:
            db.sql("DELETE FROM families WHERE id IN (SELECT family_id FROM family_members WHERE user_id = ANY(%s))", made)
            db.sql("DELETE FROM users WHERE id = ANY(%s)", made)


# ------------------------------------------------------------------------------------------------ api shape, books api
def _api_people(c, tag, made):
    """register(name, plan) -> {"id", "email", "h", "book"}: a verified account on `plan` registered through the API,
    with its personal book id; its id is added to `made`."""
    def register(name, plan="free"):
        email = f"bk-{name.lower()}-{tag}@example.com"
        r = c.post("/api/auth/register", json={"name": name, "email": email, "password": "secret123"})
        if r.status_code != 200:
            check(False, f"register {name}", f"{r.status_code} {r.text[:200]}")
            return None
        uid = db.sql("SELECT id FROM users WHERE email = %s", email)[0]["id"]
        made.append(uid)
        expires = None if plan == "free" else datetime.now(UTC) + timedelta(days=30)
        db.sql("UPDATE users SET is_verified = true, subscription_type = %s, subscription_expires_at = %s, "
               "trial_ends_at = NULL WHERE id = %s", plan, expires, uid)
        token = c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json().get("access_token")
        book = (_books_of(person_id=uid) or [{}])[0].get("id")
        return {"id": uid, "email": email, "h": {"Authorization": f"Bearer {token}"}, "book": book}
    return register


def _drop_people(made):
    if made:
        db.sql("DELETE FROM families WHERE id IN (SELECT family_id FROM family_members WHERE user_id = ANY(%s))", made)
        db.sql("DELETE FROM users WHERE id = ANY(%s)", made)


FAMILY = {"X-Book": "family"}


def section_api_shape():
    """A created transaction, budget, goal and generated insight carry book_id (the personal book, or in Family mode
    the family book) and no user_id key."""
    import httpx

    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:8]
    made = []
    register = _api_people(c, tag, made)
    now = datetime.now(UTC).replace(microsecond=0)
    som = now.replace(day=1, hour=0, minute=0, second=0)
    try:
        P = register("Shape", "plus")
        if P is None:
            return
        r = c.post("/api/family", json={"name": f"Shape {tag}"}, headers=P["h"])
        fid = ((r.json() if r.status_code == 200 else {}).get("family") or {}).get("id")
        fbook = (_books_of(family_id=fid) or [{}])[0].get("id") if fid else None
        check(bool(P["book"]) and bool(fbook), "api shape: the person has a personal book and a family book",
              (P["book"], fbook, r.status_code))

        def creates(headers):
            """{"transaction"|"budget"|"goal"|"insight"|"transaction list": (status, body)}."""
            out = {}
            r = c.post("/api/transactions", headers=headers, json={
                "type": "inflow", "main_category": "Employment Income", "sub_category": "Salary",
                "date": now.isoformat(), "amount": 100, "currency": "usd", "description": "shape"})
            out["transaction"] = r
            r = c.post("/api/budgets", headers=headers, json={
                "name": "Shape B", "period": "monthly", "start_date": som.isoformat(), "currency": "usd",
                "total_budget": 100, "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 100}]})
            out["budget"] = r
            out["goal"] = c.post("/api/goals", headers=headers, json={
                "name": "Shape G", "target_amount": 500, "goal_type": "savings", "currency": "usd"})
            out["insight"] = c.get("/api/insights", headers=headers, params={"insight_type": "weekly"})
            out["transaction list"] = c.get("/api/transactions", headers=headers)
            out["budget list"] = c.get("/api/budgets", headers=headers)
            out["goal list"] = c.get("/api/goals", headers=headers)
            return out

        for mode, headers, want in (("personal", P["h"], P["book"]), ("family", {**P["h"], **FAMILY}, fbook)):
            for what, r in creates(headers).items():
                body = r.json() if r.status_code == 200 else None
                items = body if isinstance(body, list) else [body]
                check(r.status_code == 200 and items and all(isinstance(x, dict) and x.get("book_id") == want
                                                             and "user_id" not in x for x in items),
                      f"api shape ({mode}): the {what} carries book_id = the {mode} book and no user_id",
                      f"{r.status_code} {r.text[:240]}")
    finally:
        _drop_people(made)


def section_books_api():
    """Through the API: a person migrated from the old shape sees the same data; a write marks the right book's
    freshness flag; a new family's book answers an empty list."""
    import bcrypt
    import httpx

    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:8]
    made = []
    register = _api_people(c, tag, made)
    now = datetime.now(UTC).replace(microsecond=0)

    def stale(book_id):
        row = db.sql("SELECT ai_data_stale FROM books WHERE id = %s", book_id)
        return row[0]["ai_data_stale"] if row else None

    try:
        # ---- X-Book: family right after creating a family: an empty list
        O = register("Fowner", "plus")
        if O is None:
            return
        r = c.post("/api/family", json={"name": f"Api {tag}"}, headers=O["h"])
        fid = ((r.json() if r.status_code == 200 else {}).get("family") or {}).get("id")
        fbook = (_books_of(family_id=fid) or [{}])[0].get("id") if fid else None
        r = c.get("/api/transactions", headers={**O["h"], **FAMILY})
        check(r.status_code == 200 and r.json() == [],
              "books api: GET /api/transactions with X-Book: family right after creating a family is 200 []",
              f"{r.status_code} {r.text[:200]}")

        # ---- book freshness flag, through POST /api/transactions
        def post_tx(headers):
            return c.post("/api/transactions", headers=headers, json={
                "type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries",
                "date": now.isoformat(), "amount": 3, "currency": "usd"})

        if O["book"] and fbook:
            db.sql("UPDATE books SET ai_data_stale = false WHERE id IN (%s, %s)", O["book"], fbook)
            r = post_tx(O["h"])
            check(r.status_code == 200 and stale(O["book"]) is True and stale(fbook) is False,
                  "book freshness flag: a personal POST transaction marks the personal book stale (not the family's)",
                  (r.status_code, stale(O["book"]), stale(fbook)))
            db.sql("UPDATE books SET ai_data_stale = false WHERE id IN (%s, %s)", O["book"], fbook)
            r = post_tx({**O["h"], **FAMILY})
            check(r.status_code == 200 and stale(fbook) is True and stale(O["book"]) is False,
                  "book freshness flag: a Family-mode POST transaction marks the family book stale (not the personal one)",
                  (r.status_code, stale(fbook), stale(O["book"])))
        else:
            check(False, "book freshness flag: the owner has a personal and a family book", (O["book"], fbook))

        # ---- a person id is not a book id (route level): another person's id in X-Book is refused
        r = c.get("/api/transactions", headers={**O["h"], "X-Book": O["id"]})
        check(r.status_code == 400, "a person id is not a book id: a user id as X-Book is refused (400)",
              f"{r.status_code} {r.text[:200]}")

        _migrated_person_sees_the_same_data(c, tag, made, bcrypt)
    finally:
        _drop_people(made)


def _migrated_person_sees_the_same_data(c, tag, made, bcrypt):
    """Seed a person's data in the old (522ad619de76) shape, upgrade, log in through the API: the transactions, balance,
    budgets and goals are the seeded ones."""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend"))
    import test_plans as t  # noqa: E402  (alembic helper)
    from plans_subscription_checks import head_revision  # noqa: E402

    head = head_revision()
    pid = f"bk-{tag}-migrated"
    email = f"bk-migrated-{tag}@example.com"
    made.append(pid)
    pw_hash = bcrypt.hashpw(b"secret123", bcrypt.gensalt()).decode()
    seeded = (("inflow", "1000.00", "mmk"), ("outflow", "300.50", "mmk"), ("inflow", "50.00", "usd"),
              ("outflow", "20.25", "usd"), ("inflow", "5.00", "usd"))
    want = {}
    for type_, amount, cur in seeded:
        b = want.setdefault(cur, {"total_inflow": Decimal(0), "total_outflow": Decimal(0)})
        b["total_inflow" if type_ == "inflow" else "total_outflow"] += Decimal(amount)
    goal_amount = Decimal("12.75")
    try:
        ok, out = t.alembic("downgrade", BEFORE_BOOKS)
        check(ok, f"migrated person sees the same data: downgrade to {BEFORE_BOOKS} runs", out)
        if not ok:
            return
        q = db.sql
        q("INSERT INTO users (id, name, email, password, kind, is_verified) VALUES (%s, 'Migrated', %s, %s, 'person', true)",
          pid, email, pw_hash)
        for type_, amount, cur in seeded:
            q("INSERT INTO transactions (id, user_id, type, main_category, sub_category, amount, currency, date) "
              "VALUES (%s, %s, %s, 'Food & Daily Living', 'Groceries', %s, %s, now() - interval '1 day')",
              str(uuid.uuid4()), pid, type_, Decimal(amount), cur)
        q("INSERT INTO goals (id, user_id, name, goal_type, target_amount, current_amount, currency, status) "
          "VALUES (%s, %s, 'Old goal', 'savings', 100, %s, 'usd', 'active')", str(uuid.uuid4()), pid, goal_amount)
        q("INSERT INTO budgets (id, user_id, name, period, currency, start_date, end_date, total_budget, status) "
          "VALUES (%s, %s, 'Old budget', 'monthly', 'usd', now() - interval '5 days', now() + interval '25 days', 80, 'active')",
          str(uuid.uuid4()), pid)
    finally:
        ok, out = t.alembic("upgrade", "head")
        with t.connect() as conn:
            at_head = t.current_revision(conn) == head
        check(ok and at_head, "migrated person sees the same data: upgrade head runs", out)
    if not (ok and at_head):
        return

    r = c.post("/api/auth/login", json={"email": email, "password": "secret123"})
    check(r.status_code == 200, "migrated person sees the same data: login works", f"{r.status_code} {r.text[:200]}")
    if r.status_code != 200:
        return
    h = {"Authorization": f"Bearer {r.json().get('access_token')}"}
    r = c.get("/api/transactions", headers=h, params={"limit": 100})
    check(r.status_code == 200 and len(r.json()) == len(seeded),
          "migrated person sees the same data: GET /api/transactions returns every seeded entry",
          f"{r.status_code} {len(r.json()) if r.status_code == 200 else r.text[:200]}")
    r = c.get("/api/dashboard/balance", headers=h)
    got = (r.json().get("balances") or {}) if r.status_code == 200 else {}
    ok_bal = set(got) == set(want)
    for cur, w in want.items():
        g = got.get(cur) or {}
        alloc = goal_amount if cur == "usd" else Decimal(0)
        bal = w["total_inflow"] - w["total_outflow"]
        ok_bal = ok_bal and all(abs(Decimal(str(g.get(k, "nan"))) - v) < Decimal("0.001") for k, v in (
            ("total_inflow", w["total_inflow"]), ("total_outflow", w["total_outflow"]), ("balance", bal),
            ("allocated_to_goals", alloc), ("available_balance", bal - alloc)))
    check(r.status_code == 200 and ok_bal, "migrated person sees the same data: the dashboard balance totals are the seeded ones",
          (got, want))
    r = c.get("/api/goals", headers=h)
    check(r.status_code == 200 and [g.get("name") for g in r.json()] == ["Old goal"],
          "migrated person sees the same data: GET /api/goals shows the seeded goal", f"{r.status_code} {r.text[:200]}")
    r = c.get("/api/budgets", headers=h)
    check(r.status_code == 200 and [b.get("name") for b in r.json()] == ["Old budget"],
          "migrated person sees the same data: GET /api/budgets shows the seeded budget", f"{r.status_code} {r.text[:200]}")


# ------------------------------------------------------------------------------------------------------------ jobs
def _join_family(c, owner, member):
    """`member` accepts `owner`'s invitation to the owner's family (through the API)."""
    c.post("/api/family/invites", headers=owner["h"], json={"email": member["email"]})
    inv = next(iter(c.get("/api/family/invites/mine", headers=member["h"]).json().get("invites", [])), None)
    if inv:
        c.post(f"/api/family/invites/{inv['id']}/accept", headers=member["h"])


def _seed_outflow(book_id, amount, days_ago, category="Food & Daily Living"):
    db.sql("INSERT INTO transactions (id, book_id, type, main_category, sub_category, amount, currency, date) "
           "VALUES (%s, %s, 'outflow', %s, 'Groceries', %s, 'usd', now() - %s * interval '1 day')",
           str(uuid.uuid4()), book_id, category, Decimal(str(amount)), days_ago)


def section_jobs():
    """The scheduled jobs work on books (Task 4), in-process with the stubenv fake AI answering."""
    import httpx

    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:8]
    made = []
    register = _api_people(c, tag, made)
    started = datetime.now(UTC) - timedelta(seconds=5)
    try:
        P1, P2, F = register("Jone", "plus"), register("Jtwo", "pro"), register("Jfree", "free")
        if not (P1 and P2 and F):
            return
        r = c.post("/api/family", json={"name": f"Jobs {tag}"}, headers=P1["h"])
        fid = ((r.json() if r.status_code == 200 else {}).get("family") or {}).get("id")
        fbook = (_books_of(family_id=fid) or [{}])[0].get("id") if fid else None
        _join_family(c, P1, P2)
        joined = db.sql("SELECT 1 FROM family_members WHERE family_id = %s AND user_id = %s AND status = 'active'",
                        fid, P2["id"])
        check(bool(fbook) and bool(joined), "jobs: P1 (Plus) owns a family book and P2 (Pro) is a member", (fbook, joined))
        if not (fbook and joined):
            return
        books = {"P1": P1["book"], "P2": P2["book"], "F": F["book"], "family": fbook}
        for b in books.values():
            _seed_tx(b, "40.00", "outflow")

        # ---- weekly job covers each book once (and family insight spend is on the book)
        ours = {P1["id"], P2["id"], F["id"]}

        async def weekly():
            import insights_service as ins
            stubenv.patch_loaded_modules()
            orig_list, orig_books = ins.users_db.list_fields, ins.families_db.books_with_paid_owner

            async def only_people(fields, *where):  # the job runs on this test's people and family only
                return [u for u in await orig_list(fields, *where) if u["_id"] in ours]

            async def only_family(plans):
                return [b for b in await orig_books(plans) if b["book_id"] == fbook]
            ins.users_db.list_fields, ins.families_db.books_with_paid_owner = only_people, only_family
            try:
                targets = await ins._job_targets("insight_weekly")
                await ins.generate_weekly_insights_for_all_users()
            finally:
                ins.users_db.list_fields, ins.families_db.books_with_paid_owner = orig_list, orig_books
            return sorted((t[0], t[1]["_id"], t[2]) for t in targets)
        try:
            targets = _backend_async(weekly)
        except Exception as e:  # noqa: BLE001
            targets = repr(e)[:300]
        want = sorted([(P1["book"], P1["id"], False), (P2["book"], P2["id"], False), (fbook, P1["id"], True)])
        check(targets == want, "weekly job covers each book once: _job_targets is (book, plan user, is_family) for P1's "
                               "and P2's personal books and P1's family book, nothing for Free", (targets, want))
        counts = {name: db.sql("SELECT count(*) n FROM insights WHERE book_id = %s AND insight_type = 'weekly'", b)[0]["n"]
                  for name, b in books.items()}
        check(counts == {"P1": 1, "P2": 1, "F": 0, "family": 1},
              "weekly job covers each book once: one weekly insight each for P1's, P2's and the family book, none for F",
              counts)
        spend = db.sql("SELECT user_id, book_id FROM ai_usage WHERE feature_type = 'weekly_insight' AND created_at >= %s "
                       "AND (book_id = %s OR user_id = ANY(%s))", started, fbook, [P1["id"], P2["id"], F["id"]])
        fam_rows = [s for s in spend if s["book_id"] == fbook]
        p1_rows = [s for s in spend if s["user_id"] == P1["id"]]
        check(fam_rows and all(s["user_id"] is None for s in fam_rows),
              "family insight spend is on the book: the family weekly insight's ai_usage row has book_id = the family "
              "book and user_id NULL", spend)
        check(p1_rows and all(s["book_id"] is None for s in p1_rows),
              "family insight spend is on the book: a personal weekly insight's row has user_id = the person and "
              "book_id NULL", spend)

        # ---- family AI budgets follow the owner
        now = datetime.now(UTC)
        window_end = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0) - timedelta(seconds=1)
        window_start = window_end.replace(day=1, hour=0, minute=0, second=0)
        db.sql("INSERT INTO transactions (id, book_id, type, main_category, sub_category, amount, currency, date) "
               "VALUES (%s, %s, 'outflow', 'Food & Daily Living', 'Groceries', 20, 'usd', %s)",
               str(uuid.uuid4()), fbook, window_start + timedelta(days=3, hours=12))

        def rollover(label):
            """A finished family budget (auto-create with AI) and the nightly rollover job -> (budget_auto_create calls
            for the family book, the child's Food & Daily Living allocation, the job's AI usage rows of the book)."""
            parent_id = f"bk-jobs-{label}-{tag}"
            db.budgets.insert_one({
                "_id": parent_id, "book_id": fbook, "name": f"Family {label}", "period": "monthly", "currency": "usd",
                "start_date": window_start, "end_date": window_end,
                "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 50, "spent_amount": 0,
                                      "percentage_used": 0, "is_exceeded": False}],
                "total_budget": 50, "total_spent": 0, "remaining_budget": 50, "percentage_used": 0,
                "status": "completed", "is_active": False, "auto_create_enabled": True, "auto_create_with_ai": True,
                "created_at": now, "updated_at": now})

            async def go():
                import budget_service as bs
                stubenv.patch_loaded_modules()
                seen = []
                orig = bs._runner.run

                async def spy(feature, **kw):
                    seen.append((feature, kw.get("user_id"), kw.get("book_id")))
                    return await orig(feature, **kw)
                bs._runner.run = spy
                try:
                    await bs.process_due_budget_rollovers()
                finally:
                    bs._runner.run = orig
                return seen
            seen = _backend_async(go)
            calls = [s for s in seen if s[0] == "budget_auto_create" and fbook in (s[1], s[2])]
            child = db.budgets.find_one({"parent_budget_id": parent_id})
            alloc = next((x["allocated_amount"] for x in (child or {}).get("category_budgets", [])
                          if x["main_category"] == "Food & Daily Living"), None)
            usage = db.sql("SELECT user_id, book_id FROM ai_usage WHERE feature_type = 'budget_auto_create' "
                           "AND created_at >= %s AND book_id = %s", started, fbook)
            return calls, alloc, usage

        try:
            calls, alloc, usage = rollover("plus")
        except Exception as e:  # noqa: BLE001
            calls, alloc, usage = repr(e)[:300], None, []
        check(isinstance(calls, list) and len(calls) == 1 and calls[0][1:] == (None, fbook) and alloc == 450,
              "family AI budgets follow the owner: owner on Plus: the rollover makes one budget_auto_create call (spend "
              "on the family book) and the next budget has the AI's allocations (450)", (calls, alloc))
        check(len(usage) == 1 and usage[0]["user_id"] is None,
              "family AI budgets follow the owner: the AI budget's ai_usage row has book_id = the family book and "
              "user_id NULL", usage)
        db.sql("UPDATE users SET subscription_type = 'free', subscription_expires_at = NULL WHERE id = %s", P1["id"])
        try:
            calls, alloc, _ = rollover("free")
        except Exception as e:  # noqa: BLE001
            calls, alloc = repr(e)[:300], None
        finally:
            db.sql("UPDATE users SET subscription_type = 'plus', subscription_expires_at = %s WHERE id = %s",
                   datetime.now(UTC) + timedelta(days=30), P1["id"])
        check(calls == [] and alloc == 40.0,
              "family AI budgets follow the owner: owner on Free: no AI call, the non-AI amounts (40)", (calls, alloc))

        # ---- unusual spending skips family books
        for b in (fbook, P1["book"]):
            for days in (10, 15, 20, 25, 30):
                _seed_outflow(b, 10, days)
            _seed_outflow(b, 300, 1)
        db.sql("DELETE FROM notifications WHERE user_id = ANY(%s)", [P1["id"], P2["id"]])

        async def unusual():
            import notification_service as ns
            stubenv.patch_loaded_modules()
            await ns.analyze_unusual_spending(fbook)
            await ns.analyze_all_unusual_spending()
        try:
            _backend_async(unusual)
            err = None
        except Exception as e:  # noqa: BLE001
            err = repr(e)[:300]
        # The family book's members are P1 and P2: a family notice would reach both, so P2 has none and P1 only the
        # personal one.
        notes = db.sql("SELECT user_id FROM notifications WHERE type = 'unusual_spending' AND user_id = ANY(%s)",
                       [P1["id"], P2["id"]])
        check(err is None and not [n for n in notes if n["user_id"] == P2["id"]],
              "unusual spending skips family books: the family book's spike makes no unusual_spending notice", (err, notes))
        check(len([n for n in notes if n["user_id"] == P1["id"]]) == 1,
              "unusual spending skips family books: P1's personal book's spike makes P1's one notice (the job runs on "
              "persons' personal books)", notes)

        # ---- recurring job uses the entry's book (the notice goes to the adder only, R14)
        from tz_utils import default_zone, local_now
        # Two days ago on the default zone's calendar (the job's "today"), sent as a local date-time like the app.
        start = (local_now(default_zone()) - timedelta(days=2)).replace(hour=12, minute=0, second=0, microsecond=0)
        r = c.post("/api/transactions", headers={**P2["h"], **FAMILY}, json={
            "type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries",
            "date": start.isoformat(), "amount": 5, "currency": "usd",
            "recurrence": {"enabled": True, "config": {"frequency": "daily"}}})
        parent = r.json().get("id") if r.status_code == 200 else None
        check(parent is not None, "recurring job uses the entry's book: P2 adds a daily family entry",
              f"{r.status_code} {r.text[:200]}")
        if parent:
            db.sql("DELETE FROM notifications WHERE user_id = ANY(%s)", [P1["id"], P2["id"]])
            db.sql("UPDATE books SET ai_data_stale = false WHERE id = %s", fbook)

            async def recurring():
                import recurring_transaction_service as rts
                stubenv.patch_loaded_modules()
                await rts.check_and_create_recurring_transactions()
            try:
                _backend_async(recurring)
                err = None
            except Exception as e:  # noqa: BLE001
                err = repr(e)[:300]
            kids = db.sql("SELECT book_id FROM transactions WHERE parent_transaction_id = %s", parent)
            check(err is None and len(kids) == 2 and all(k["book_id"] == fbook for k in kids),
                  "recurring job uses the entry's book: the job creates the due children in the family book", (err, kids))
            notes = db.sql("SELECT user_id FROM notifications WHERE type = 'recurring_transaction_created' "
                           "AND user_id = ANY(%s)", [P1["id"], P2["id"]])
            check(len(notes) == 1 and notes[0]["user_id"] == P2["id"],
                  "recurring job uses the entry's book: only the adder (P2) is told (R14)", notes)
            stale = db.sql("SELECT ai_data_stale s FROM books WHERE id = %s", fbook)[0]["s"]
            check(stale is True, "recurring job uses the entry's book: the family book is marked stale", stale)
    finally:
        _drop_people(made)


# ---------------------------------------------------------------------------------------------- notification links
def section_notification_links():
    """Each notice stores its subject in the typed link its type names (and its book in book_id); the API and the push
    data carry subject_id and the family marker `book`, never goal_id; deleting the subject (or the family) keeps the
    notice with its link cleared; a notice about a subject already gone is stored unlinked; insight notices dedupe per
    book (Task 5). Needs the stub server."""
    import json
    import time
    import httpx

    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:8]
    made = []
    register = _api_people(c, tag, made)
    now = datetime.now(UTC).replace(microsecond=0)
    today = now.date()

    def rows(uid, type_):
        return db.sql("SELECT * FROM notifications WHERE user_id = %s AND type = %s ORDER BY created_at, id", uid, type_)

    def wait_for(fn, timeout=8.0):
        end = time.time() + timeout
        while True:
            v = fn()
            if v or time.time() > end:
                return v
            time.sleep(0.25)

    def api(u, type_):
        r = c.get("/api/notifications", headers=u["h"], params={"limit": 100})
        return [n for n in (r.json() if r.status_code == 200 else []) if n.get("type") == type_]

    def pushes(token):
        if not os.path.exists(stubenv.OUTBOX):
            return []
        with open(stubenv.OUTBOX, encoding="utf-8") as f:
            recs = [json.loads(line) for line in f if '"fcm_send"' in line]
        return [(r.get("data") or {}) for r in recs if token in (r.get("fcm_token"), r.get("token"))]

    def linked(uid, type_, link, subject, book):
        """The person's one notice of this type holds `subject` in `link`, NULL in the other subject links, and
        `book` in book_id."""
        got = rows(uid, type_)
        ok = (len(got) == 1 and got[0][link] == subject and got[0]["book_id"] == book
              and all(got[0][x] is None for x in LINKS if x != link))
        check(ok, f"each notice stores its typed link: {type_} -> {link} (other links NULL, book_id "
                  f"{'the book' if book else 'NULL'})", [{k: g[k] for k in (*LINKS, 'book_id')} for g in got])

    try:
        P, Q = register("Linkp", "plus"), register("Linkq", "free")
        if not (P and Q):
            return
        for u, name in ((P, "p"), (Q, "q")):
            db.sql("INSERT INTO user_devices (id, user_id, token, session_expires_at) "
                   "VALUES (%s, %s, %s, now() + interval '30 days')", str(uuid.uuid4()), u["id"], f"fcm-links-{name}-{tag}")
        r = c.post("/api/family", json={"name": f"Links {tag}"}, headers=P["h"])
        fid = ((r.json() if r.status_code == 200 else {}).get("family") or {}).get("id")
        fbook = (_books_of(family_id=fid) or [{}])[0].get("id") if fid else None
        c.post("/api/family/invites", headers=P["h"], json={"email": Q["email"]})
        inv = next(iter(c.get("/api/family/invites/mine", headers=Q["h"]).json().get("invites", [])), {})
        if inv:
            c.post(f"/api/family/invites/{inv['id']}/accept", headers=Q["h"])
        check(bool(fbook) and bool(inv), "notification links: P owns a family and Q joined it by invite", (fbook, inv))
        if not (fbook and inv):
            return

        # ---- each notice stores its typed link
        r = c.post("/api/transactions", headers=P["h"], json={
            "type": "inflow", "main_category": "Employment Income", "sub_category": "Salary", "date": now.isoformat(),
            "amount": 1000, "currency": "usd"})
        for _ in range(5):
            _seed_tx(P["book"], "10.00", "outflow")
        r = c.post("/api/goals", headers=P["h"], json={"name": f"Links goal {tag}", "target_amount": 100,
                                                        "goal_type": "savings", "currency": "usd"})
        gid = r.json().get("id") if r.status_code == 200 else None
        r = c.post(f"/api/goals/{gid}/contribute", headers=P["h"], json={"amount": 100})
        check(gid and r.status_code == 200, "notification links: P fills a personal goal", f"{r.status_code} {r.text[:200]}")
        budget = {"name": f"Links budget {tag}", "period": "custom", "currency": "usd", "total_budget": 1000,
                  "start_date": (today - timedelta(days=1)).isoformat(), "end_date": (today + timedelta(days=5)).isoformat(),
                  "category_budgets": [{"main_category": "Transportation", "allocated_amount": 1000}]}
        r = c.post("/api/budgets", headers=P["h"], json=budget)
        bid = r.json().get("id") if r.status_code == 200 else None
        r = c.post("/api/transactions", headers=P["h"], json={
            "type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries",
            "date": now.isoformat(), "amount": 300, "currency": "usd", "description": "Big shop"})
        txid = r.json().get("id") if r.status_code == 200 else None
        wait_for(lambda: rows(P["id"], "large_transaction"))
        ci_own, ci_fam = f"ci-own-{tag}", f"ci-fam-{tag}"
        for rid, book in ((ci_own, P["book"]), (ci_fam, fbook)):
            db.sql("INSERT INTO custom_insights (id, book_id, start_date, end_date, status, content) "
                   "VALUES (%s, %s, current_date - 7, current_date, 'ready', 'Report')", rid, book)

        async def custom_ready():
            import custom_insights_service as cis
            stubenv.patch_loaded_modules()
            base = {"status": "ready", "start_date": today - timedelta(days=7), "end_date": today}
            await cis._notify(base | {"_id": ci_own, "book_id": P["book"], "counter_keys": []})
            await cis._notify(base | {"_id": ci_fam, "book_id": fbook,
                                      "counter_keys": [["insight_custom", "month", today.isoformat(), P["id"]]]})
        _backend_async(custom_ready)

        linked(P["id"], "goal_achieved", "goal_id", gid, P["book"])
        linked(P["id"], "budget_started", "budget_id", bid, P["book"])
        linked(P["id"], "large_transaction", "transaction_id", txid, P["book"])
        own = [x for x in rows(P["id"], "custom_insight_ready") if x["custom_insight_id"] == ci_own]
        fam = [x for x in rows(P["id"], "custom_insight_ready") if x["custom_insight_id"] == ci_fam]
        check(len(own) == 1 and own[0]["book_id"] == P["book"] and len(fam) == 1 and fam[0]["book_id"] == fbook
              and all(x[k] is None for x in own + fam for k in LINKS if k != "custom_insight_id"),
              "each notice stores its typed link: custom_insight_ready -> custom_insight_id (book_id the report's book)",
              (own, fam))
        linked(Q["id"], "family_invite", "family_invite_id", inv["id"], None)
        linked(P["id"], "family_invite_accepted", "family_id", fid, None)

        # ---- API and push carry subject_id and book
        r = c.post("/api/budgets", headers={**P["h"], **FAMILY}, json=budget | {"name": f"Links family {tag}"})
        fbid = r.json().get("id") if r.status_code == 200 else None
        check(fbid is not None, "API and push carry subject_id and book: P creates a family budget",
              f"{r.status_code} {r.text[:200]}")
        ag = api(P, "goal_achieved")
        check(len(ag) == 1 and ag[0].get("subject_id") == gid and "goal_id" not in ag[0] and not ag[0].get("extra"),
              "API and push carry subject_id and book: GET /api/notifications gives a personal notice subject_id and no "
              "goal_id, no book marker", ag)
        aq = api(Q, "budget_started")
        check(len(aq) == 1 and aq[0].get("subject_id") == fbid and "goal_id" not in aq[0]
              and (aq[0].get("extra") or {}).get("book") == "family",
              "API and push carry subject_id and book: a family budget's notice has subject_id and extra.book = 'family'",
              aq)
        ai = api(Q, "family_invite")
        check(len(ai) == 1 and ai[0].get("subject_id") == inv["id"] and not ai[0].get("extra"),
              "API and push carry subject_id and book: the invite notice's subject_id is the invite id", ai)
        qp = wait_for(lambda: [d for d in pushes(f"fcm-links-q-{tag}") if d.get("subject_id") == fbid])
        check(len(qp) == 1 and qp[0].get("book") == "family" and "goal_id" not in qp[0],
              "API and push carry subject_id and book: the family push data has subject_id and book = 'family', no "
              "goal_id", pushes(f"fcm-links-q-{tag}"))
        pp = wait_for(lambda: [d for d in pushes(f"fcm-links-p-{tag}") if d.get("subject_id") == bid])
        check(len(pp) == 1 and "book" not in pp[0] and "goal_id" not in pp[0],
              "API and push carry subject_id and book: a personal push has subject_id and no book, no goal_id",
              pushes(f"fcm-links-p-{tag}"))
        np_ = [d for d in pushes(f"fcm-links-p-{tag}") if d.get("type") == "large_transaction"]
        check(len(np_) == 1 and np_[0].get("subject_id") == txid,
              "API and push carry subject_id and book: the large-entry push's subject_id is the entry", np_)

        # ---- a notice about a subject already gone is stored unlinked (never fails its caller)
        gone = f"no-such-budget-{tag}"

        async def about_gone():
            import notification_service as ns
            stubenv.patch_loaded_modules()
            with _captured_logs("sql.notifications") as logs:
                await ns.notify_budget_auto_created(P["book"], gone, f"Gone {tag}", False)
            return logs
        try:
            logs = _backend_async(about_gone)
            err = None
        except Exception as e:  # noqa: BLE001
            err, logs = repr(e)[:300], []
        ga = rows(P["id"], "budget_auto_created")
        check(err is None and len(ga) == 1 and ga[0]["budget_id"] is None and ga[0]["book_id"] == P["book"]
              and f"Gone {tag}" in ga[0]["message"],
              "a notice about a subject already gone is stored with the link NULL, its caller unharmed", (err, ga))
        warned = [m for lvl, m in logs if lvl == "WARNING" and "budget_auto_created" in m and "budget_id" in m
                  and gone in m]
        check(len(warned) == 1 and not any("book_id" in m for lvl, m in logs if lvl == "WARNING"),
              "a link stored NULL is logged: one warning names the type (budget_auto_created) and the link (budget_id); "
              "the book link, which was stored, is not", logs)

        # ---- a subject deleted between the link's sub-select and the insert: retried unlinked, never a 500
        raced = f"raced-budget-{tag}"

        async def race():
            import notification_service as ns
            from sqlalchemy import select as sa_select
            from sql import notifications as notifications_db
            from sql.db import fetch_value, transaction
            stubenv.patch_loaded_modules()
            real = notifications_db._if_exists
            # The sub-select saw the row; the delete committed before the FK check: the insert gets the bare id.
            notifications_db._if_exists = lambda link, value: value
            out = {}
            try:
                with _captured_logs("sql.notifications") as logs:
                    try:
                        async with transaction():  # a caller's transaction: it must survive the failed insert
                            sent = await ns.create_notification_from_key(
                                P["book"], "budget_auto_created", "budget_auto_created_title",
                                "budget_auto_created_msg", subject={"budget_id": raced}, goal_name=f"Raced {tag}",
                                currency="usd", budget_name=f"Raced {tag}")
                            out["sent"] = len(sent)
                            out["after"] = await fetch_value(sa_select(1))  # the transaction still works
                    except Exception as e:  # noqa: BLE001
                        out["error"] = repr(e)[:300]
                    try:
                        out["skipped"] = await ns.create_notification(
                            f"no-such-person-{tag}", "budget_auto_created", "t", "m", links={"budget_id": raced})
                    except Exception as e:  # noqa: BLE001
                        out["skip_error"] = repr(e)[:300]
            finally:
                notifications_db._if_exists = real
            out["logs"] = logs
            return out
        out = _backend_async(race)
        raced_rows = [x for x in rows(P["id"], "budget_auto_created") if f"Raced {tag}" in x["message"]]
        check("error" not in out and out.get("sent") == 1 and out.get("after") == 1 and len(raced_rows) == 1
              and all(raced_rows[0][k] is None for k in (*LINKS, "book_id")),
              "a delete racing a notice insert: the FK violation is retried with every link NULL inside a savepoint; "
              "no exception escapes, the caller's transaction commits, the notice is stored unlinked", (out, raced_rows))
        skipped = not db.sql("SELECT 1 FROM notifications WHERE user_id = %s", f"no-such-person-{tag}")
        check("skip_error" not in out and out.get("skipped") is None and skipped
              and any(lvl in ("WARNING", "ERROR") and "skipped" in m for lvl, m in out.get("logs", [])),
              "a delete racing a notice insert: when the unlinked retry fails too, the notice is skipped and logged",
              out)

        # ---- every notice type has an entry in the type -> link table
        import notification_service as ns_mod
        from notification_models import NotificationType
        missing = [t.value for t in NotificationType if t.value not in ns_mod.NOTIFICATION_LINKS]
        check(not missing, "every NotificationType has an entry in notification_service.NOTIFICATION_LINKS", missing)

        # ---- insight notices dedupe per book
        _seed_tx(fbook, "40.00", "outflow")
        ours = {P["id"], Q["id"]}

        async def weekly_twice():
            import insights_service as ins
            import notification_service as ns
            stubenv.patch_loaded_modules()
            orig_list, orig_books = ins.users_db.list_fields, ins.families_db.books_with_paid_owner

            async def only_people(fields, *where):
                return [u for u in await orig_list(fields, *where) if u["_id"] in ours]

            async def only_family(plans):
                return [b for b in await orig_books(plans) if b["book_id"] == fbook]
            ins.users_db.list_fields, ins.families_db.books_with_paid_owner = only_people, only_family
            try:
                await ins.generate_weekly_insights_for_all_users()
                await ins.generate_weekly_insights_for_all_users()
            finally:
                ins.users_db.list_fields, ins.families_db.books_with_paid_owner = orig_list, orig_books
            for b in (P["book"], fbook):  # a direct repeat within the hour is dropped as well
                await ns.notify_weekly_insights_generated(b)
        try:
            _backend_async(weekly_twice)
            err = None
        except Exception as e:  # noqa: BLE001
            err = repr(e)[:300]
        got = sorted(((x["user_id"], x["book_id"]) for u in (P, Q) for x in rows(u["id"], "weekly_insights_generated")),
                     key=repr)
        want = sorted([(P["id"], P["book"]), (P["id"], fbook), (Q["id"], fbook)], key=repr)
        check(err is None and got == want,
              "insight notices dedupe per book: the weekly job twice gives each recipient one notice per book (P: "
              "personal and family; Q: family)", (err, got, want))

        # ---- the dedupe reader on typed links, and the writer's type -> link table
        async def readers():
            import notification_service as ns
            from sql import notifications as notifications_db
            stubenv.patch_loaded_modules()
            found = (await notifications_db.exists(P["id"], "goal_achieved", goal_id=gid),
                     await notifications_db.exists(P["id"], "goal_achieved", budget_id=gid),
                     await notifications_db.exists(P["id"], "weekly_insights_generated", no_subject=True),
                     await notifications_db.exists(P["id"], "goal_achieved", no_subject=True))
            try:
                await ns.create_notification(P["id"], "goal_achieved", "t", "m", links={"budget_id": bid})
                refused = None
            except ValueError as e:
                refused = str(e)
            return found, refused
        found, refused = _backend_async(readers)
        check(found == (True, False, True, False),
              "exists() matches the typed link given (goal_id, not budget_id) and no_subject means no subject link",
              found)
        check(refused is not None and not rows(P["id"], "goal_achieved")[1:],
              "a writer can't store a subject under a link its type doesn't name (goal_achieved with budget_id)",
              refused)

        # ---- deleting the subject keeps the notice
        before = api(P, "goal_achieved")
        r = c.delete(f"/api/goals/{gid}", headers=P["h"])
        after = api(P, "goal_achieved")
        check(r.status_code == 200 and len(after) == 1 and before and after[0]["id"] == before[0]["id"]
              and after[0]["message"] == before[0]["message"] and after[0]["title"] == before[0]["title"]
              and after[0].get("subject_id") is None,
              "deleting the subject keeps the notice: the goal's goal_achieved notice stays with its text, subject_id "
              "null", (r.status_code, before, after))

        # ---- deleting the family keeps its notices, links cleared
        r = c.request("DELETE", "/api/family", headers=P["h"], json={"confirm_name": f"Links {tag}"})
        fam_notes = [x for x in rows(Q["id"], "budget_started")]
        check(r.status_code == 200 and len(fam_notes) == 1 and fam_notes[0]["budget_id"] is None
              and fam_notes[0]["book_id"] is None,
              "deleting the family keeps its notices: Q's family budget notice stays, budget_id and book_id NULL",
              (r.status_code, r.text[:200], fam_notes))
        aq = api(Q, "budget_started")
        check(len(aq) == 1 and aq[0].get("subject_id") is None and not aq[0].get("extra"),
              "deleting the family keeps its notices: the API lists it with subject_id null and no book marker", aq)
        acc, invn = rows(P["id"], "family_invite_accepted"), rows(Q["id"], "family_invite")
        check(len(acc) == 1 and acc[0]["family_id"] is None and len(invn) == 1 and invn[0]["family_invite_id"] is None,
              "deleting the family keeps its notices: the joined and invite notices stay, family_id and "
              "family_invite_id NULL", (acc, invn))
    finally:
        _drop_people(made)


# ------------------------------------------------------------------------------------------------------- AI spend
def _admin_headers(c):
    """A super admin of our own -> (headers, email to delete)."""
    import admin_utils
    email, pw = f"bk-admin-{uuid.uuid4().hex[:8]}@example.com", "bk-admin-pass-1"
    db.admins.insert_one({"_id": str(uuid.uuid4()), "name": "books admin", "email": email,
                          "password": admin_utils.get_password_hash(pw), "role": "super_admin",
                          "created_at": datetime.now(UTC), "last_login": None})
    r = c.post("/api/admin/login", json={"email": email, "password": pw})
    return {"Authorization": "Bearer " + r.json().get("access_token", "")}, email


def _book_spend(book_id, *costs, feature="weekly_insight"):
    """ai_usage rows of a family book's own AI work (book_id, user_id NULL) -> their ids."""
    ids = []
    for cost in costs:
        ids.append(str(uuid.uuid4()))
        db.sql("INSERT INTO ai_usage (id, book_id, feature_type, provider, model_name, estimated_cost_usd) "
               "VALUES (%s, %s, %s, 'openai', 'gpt-test', %s)", ids[-1], book_id, feature, Decimal(str(cost)))
    return ids


def section_ai_spend():
    """AI spend per book (Task 6). A family book's own AI work is recorded on ai_usage.book_id with user_id NULL (that
    write is checked in the jobs section: 'family insight spend is on the book'); the owner's cost cap counts the
    book's spend; deleting a family (or its last owner's account) keeps its spend in the admin totals as one
    "Deleted family" row; the admin report labels a family book's row and lists its records. Needs the stub server."""
    import httpx

    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:8]
    made = []
    register = _api_people(c, tag, made)
    started = (datetime.now(UTC) - timedelta(seconds=5)).isoformat()
    window = {"start_date": started}
    ah, admin_email = _admin_headers(c)

    def users_report():
        r = c.get("/api/admin/ai-usage/users", headers=ah, params={**window, "limit": 100})
        check(r.status_code == 200, "ai spend: GET /api/admin/ai-usage/users answers 200", f"{r.status_code} {r.text[:200]}")
        return r.json() if r.status_code == 200 else []

    def deleted_cost():
        rows = [u for u in users_report() if u.get("user_name") == "Deleted family"]
        check(len(rows) <= 1 and all(u.get("user_id") is None and u.get("book_id") is None for u in rows),
              "ai spend: at most one 'Deleted family' row, with no user_id and no book_id", rows)
        return rows[0]["total_cost_usd"] if rows else 0.0

    def total_cost():
        r = c.get("/api/admin/ai-usage/stats", headers=ah, params=window)
        check(r.status_code == 200, "ai spend: GET /api/admin/ai-usage/stats answers 200", f"{r.status_code} {r.text[:200]}")
        return r.json().get("total_cost_usd") if r.status_code == 200 else None

    def family(owner, name):
        r = c.post("/api/family", json={"name": name}, headers=owner["h"])
        fid = ((r.json() if r.status_code == 200 else {}).get("family") or {}).get("id")
        return fid, ((_books_of(family_id=fid) or [{}])[0].get("id") if fid else None)

    def spend_of(ids):
        return float(db.sql("SELECT coalesce(sum(estimated_cost_usd), 0) n FROM ai_usage WHERE id = ANY(%s)", ids)[0]["n"])

    def still_unowned(ids):
        rows = db.sql("SELECT user_id, book_id FROM ai_usage WHERE id = ANY(%s)", ids)
        return len(rows) == len(ids) and all(r["user_id"] is None and r["book_id"] is None for r in rows)

    try:
        O, R = register("Spendo", "plus"), register("Spendr", "plus")
        if not (O and R):
            return
        fid, fbook = family(O, f"Spend {tag}")
        check(bool(fbook), "ai spend: O (Plus) owns a family book", (fid, fbook))
        if not fbook:
            return

        # ---- a family custom insight's spend: on the asker when one is recorded, else on the book
        t0 = datetime.now(UTC) - timedelta(seconds=1)

        async def custom_reports():
            import json
            import custom_insights_service as cis
            stubenv.patch_loaded_modules()
            today = datetime.now(UTC).date()
            out = []
            # No recorded asker: insight_custom is included in the plan, so the reservation had no counter keys.
            for keys in ([], [["insight_custom", "month", today.isoformat(), O["id"]]]):
                rid = str(uuid.uuid4())
                db.sql("INSERT INTO custom_insights (id, book_id, start_date, end_date, status, counter_keys) "
                       "VALUES (%s, %s, current_date - 7, current_date, 'pending', %s::jsonb)",
                       rid, fbook, json.dumps(keys))
                row = await cis.run_report(rid)
                out.append((row or {}).get("status"))
            return out
        try:
            statuses = _backend_async(custom_reports)
        except Exception as e:  # noqa: BLE001
            statuses = repr(e)[:300]
        spend = db.sql("SELECT id, user_id, book_id, estimated_cost_usd FROM ai_usage WHERE created_at >= %s "
                       "AND (book_id = %s OR user_id = %s) ORDER BY created_at", t0, fbook, O["id"])
        on_book = [s for s in spend if s["book_id"] == fbook]
        on_asker = [s for s in spend if s["user_id"] == O["id"]]
        check(statuses == ["ready", "ready"] and len(on_book) == 1 and on_book[0]["user_id"] is None
              and len(on_asker) == 1 and on_asker[0]["book_id"] is None,
              "family custom insight spend: with no recorded asker (counter_keys []) the report's AI spend is on the "
              "family book (user_id NULL); with an asker it is on the asker", (statuses, spend))
        db.sql("DELETE FROM ai_usage WHERE id = ANY(%s)", [s["id"] for s in spend])

        # ---- spend on a book deleted while the AI was answering keeps its cost, unowned
        gone_id = str(uuid.uuid4())

        async def usage_on_gone_book():
            from sql import ai_usage as ai_usage_db
            stubenv.patch_loaded_modules()
            await ai_usage_db.insert_usage({"_id": gone_id, "user_id": None, "book_id": f"no-such-book-{tag}",
                                            "feature_type": "weekly_insight", "provider": "openai",
                                            "model_name": "gpt-test", "estimated_cost_usd": 0.0425})
        try:
            _backend_async(usage_on_gone_book)
            err = None
        except Exception as e:  # noqa: BLE001
            err = repr(e)[:300]
        kept = db.sql("SELECT user_id, book_id, estimated_cost_usd FROM ai_usage WHERE id = %s", gone_id)
        check(err is None and len(kept) == 1 and kept[0]["user_id"] is None and kept[0]["book_id"] is None
              and float(kept[0]["estimated_cost_usd"]) == 0.0425,
              "spend on a book already gone is stored with book_id NULL and its cost kept", (err, kept))
        db.sql("DELETE FROM ai_usage WHERE id = %s", gone_id)

        # ---- owner cap counts the book
        async def caps():
            from plans import quota, store
            from sql import users as users_db
            stubenv.patch_loaded_modules()
            await store.load()
            owner = await users_db.get_user(O["id"])
            return (await quota.over_cost_cap(owner), await quota.family_over_cost_cap(owner, fbook),
                    store.cost_cap("plus"))
        cap = _backend_async(caps)[2]
        own_id = str(uuid.uuid4())
        db.sql("INSERT INTO ai_usage (id, user_id, feature_type, provider, model_name, estimated_cost_usd) "
               "VALUES (%s, %s, 'chat', 'openai', 'gpt-test', %s)", own_id, O["id"], Decimal(str(round(cap * 0.6, 6))))
        before = _backend_async(caps)[:2]
        cap_ids = _book_spend(fbook, round(cap * 0.6, 6))
        after = _backend_async(caps)[:2]
        check(before == (False, False) and after == (False, True),
              "owner cap counts the book: the owner's spend (60% of the cap) plus the book's (60%) puts the family over "
              "the cap; the owner alone stays under it", (cap, before, after))
        db.sql("DELETE FROM ai_usage WHERE id = ANY(%s)", [own_id, *cap_ids])

        # ---- admin book detail
        detail_ids = _book_spend(fbook, 0.01, 0.02)
        r = c.get(f"/api/admin/ai-usage/book/{fbook}", headers=ah)
        got = r.json() if r.status_code == 200 else []
        check(r.status_code == 200 and sorted(x.get("id") for x in got) == sorted(detail_ids)
              and all(x.get("book_id") == fbook and x.get("user_id") is None for x in got),
              "admin book detail: GET /api/admin/ai-usage/book/{id} lists that book's rows (book_id set, user_id null)",
              (r.status_code, r.text[:300]))
        r = c.get(f"/api/admin/ai-usage/book/{fbook}", headers=ah, params={"feature_type": "chat"})
        check(r.status_code == 200 and r.json() == [], "admin book detail: a feature filter applies",
              (r.status_code, r.text[:200]))
        r = c.get(f"/api/admin/ai-usage/book/no-such-book-{tag}", headers=ah)
        check(r.status_code == 200 and r.json() == [], "admin book detail: an unknown book lists nothing",
              (r.status_code, r.text[:200]))
        report = users_report()
        row = next((u for u in report if u.get("book_id") == fbook), None)
        check(row is not None and row.get("user_id") is None and row.get("user_name") == f"Family · Spend {tag}"
              and O["email"] in (row.get("user_email") or "") and abs(row.get("total_cost_usd", 0) - 0.03) < 1e-6,
              "admin book detail: the users list shows the book as 'Family · <name>' with book_id set and the owner's "
              "e-mail", row)
        prow = next((u for u in report if u.get("user_id") == O["id"]), None)
        check(prow is None or prow.get("book_id") is None, "admin book detail: a person's row has book_id null", prow)
        auto_ids = _book_spend(fbook, 0.01, feature="budget_auto_create")
        r = c.get("/api/admin/ai-usage/stats/budgets", headers=ah, params=window)
        auto = (r.json() if r.status_code == 200 else {}).get("budget_auto_create", {})
        check(r.status_code == 200 and auto.get("requests") == 1 and auto.get("unique_users") == 0
              and auto.get("unique_books") == 1,
              "admin book detail: the budget feature stats count a family book's AI budget under books, not users",
              (r.status_code, auto))

        # ---- deleting a family keeps its spend
        spent = detail_ids + auto_ids + _book_spend(fbook, 0.25, 0.5)
        cost = spend_of(spent)
        total0, gone0 = total_cost(), deleted_cost()
        r = c.request("DELETE", "/api/family", headers=O["h"], json={"confirm_name": f"Spend {tag}"})
        check(r.status_code == 200, "deleting a family keeps its spend: the owner deletes the family (200)",
              f"{r.status_code} {r.text[:200]}")
        check(still_unowned(spent), "deleting a family keeps its spend: the family's ai_usage rows remain, user_id and "
                                    "book_id NULL", db.sql("SELECT user_id, book_id FROM ai_usage WHERE id = ANY(%s)", spent))
        total1, gone1 = total_cost(), deleted_cost()
        check(abs((gone1 - gone0) - cost) < 1e-3,
              "deleting a family keeps its spend: GET /api/admin/ai-usage/users has one 'Deleted family' row carrying "
              "its cost", (gone0, gone1, cost))
        check(total0 is not None and total1 is not None and abs(total1 - total0) < 1e-3,
              "deleting a family keeps its spend: the /api/admin/ai-usage/stats total cost is unchanged by the delete",
              (total0, total1))
        everything = float(db.sql("SELECT coalesce(sum(estimated_cost_usd), 0) n FROM ai_usage WHERE created_at >= %s",
                                  started)[0]["n"])
        check(total1 is not None and abs(total1 - everything) < 1e-3,
              "deleting a family keeps its spend: the stats total counts every row (people's, books' and deleted "
              "families' spend)", (total1, everything))

        # ---- the owner's own account deletion, last member of a family with spend, notices and chats
        S, Q = register("Spends", "plus"), register("Spendq", "plus")
        fid3, fbook3 = family(S, f"Solo spend {tag}")
        _join_family(c, S, Q)
        budget = {"name": f"Spend family {tag}", "period": "custom", "currency": "usd", "total_budget": 100,
                  "start_date": (datetime.now(UTC).date() - timedelta(days=1)).isoformat(),
                  "end_date": (datetime.now(UTC).date() + timedelta(days=5)).isoformat(),
                  "category_budgets": [{"main_category": "Transportation", "allocated_amount": 100}]}
        rb = c.post("/api/budgets", headers={**S["h"], **FAMILY}, json=budget)
        chats = [c.post("/api/chat/stream", headers={**u["h"], **FAMILY}, json={"message": f"family {tag}"}).status_code
                 for u in (S, Q)]
        sessions = db.sql("SELECT count(*) n FROM chat_sessions WHERE book_id = %s", fbook3)[0]["n"] if fbook3 else 0
        q_notes = [n for n in c.get("/api/notifications", headers=Q["h"], params={"limit": 100}).json()
                   if n.get("type") in ("family_invite", "budget_started")]
        rl = c.post("/api/family/leave", headers=Q["h"])
        check(bool(fbook3) and rb.status_code == 200 and chats == [200, 200] and sessions == 2 and len(q_notes) == 2
              and all(n.get("subject_id") for n in q_notes) and rl.status_code == 200,
              "owner account deletion: S's family has a budget, S's and Q's family chats and Q's family notices; Q left",
              (fbook3, rb.status_code, chats, sessions, q_notes, rl.status_code))
        spent3 = _book_spend(fbook3, 0.125, 0.375)
        own3 = float(db.sql("SELECT coalesce(sum(estimated_cost_usd), 0) n FROM ai_usage WHERE user_id = %s",
                            S["id"])[0]["n"])
        total2, gone2 = total_cost(), deleted_cost()
        r = c.request("DELETE", "/api/auth/delete-account", headers=S["h"], json={"password": "secret123"})
        check(r.status_code == 200 and not db.sql("SELECT 1 FROM families WHERE id = %s", fid3),
              "owner account deletion: the last member deletes their account (200) and the family goes with it",
              f"{r.status_code} {r.text[:200]}")
        if r.status_code == 200:
            made.remove(S["id"])
        total3, gone3 = total_cost(), deleted_cost()
        check(still_unowned(spent3) and abs((gone3 - gone2) - spend_of(spent3)) < 1e-3,
              "owner account deletion: the family's spend stays, in the 'Deleted family' row", (gone2, gone3))
        check(total2 is not None and total3 is not None and abs((total2 - total3) - own3) < 1e-3,
              "owner account deletion: the admin total keeps the family's spend (it drops by the owner's own spend only)",
              (total2, total3, own3))
        r = c.get("/api/notifications", headers=Q["h"], params={"limit": 100})
        after_notes = [n for n in (r.json() if r.status_code == 200 else []) if n.get("id") in {x["id"] for x in q_notes}]
        check(r.status_code == 200 and len(after_notes) == 2 and all(n.get("subject_id") is None for n in after_notes),
              "owner account deletion: Q's notices about the family stay listed, subject_id null",
              (r.status_code, after_notes))
        check(not db.sql("SELECT 1 FROM chat_sessions WHERE book_id = %s", fbook3)
              and c.get("/api/chat/history", headers=Q["h"]).status_code == 200,
              "owner account deletion: the family's chats go with its book; Q's own chat still answers")

        # ---- the owner's account deletion with an active member: the family is handed over, its spend stays on it
        fid4, fbook4 = family(Q, f"Handed {tag}")
        _join_family(c, Q, R)
        spent4 = _book_spend(fbook4, 0.0625)
        r = c.request("DELETE", "/api/auth/delete-account", headers=Q["h"], json={"password": "secret123"})
        if r.status_code == 200:
            made.remove(Q["id"])
        owner4 = db.sql("SELECT user_id FROM family_members WHERE family_id = %s AND role = 'owner' AND status = 'active'",
                        fid4)
        kept = db.sql("SELECT book_id FROM ai_usage WHERE id = ANY(%s)", spent4)
        row4 = next((u for u in users_report() if u.get("book_id") == fbook4), None)
        check(r.status_code == 200 and owner4 == [{"user_id": R["id"]}] and kept == [{"book_id": fbook4}]
              and row4 is not None and R["email"] in (row4.get("user_email") or ""),
              "owner account deletion: with an active member the family is handed over (R owns it) and its spend stays "
              "on the book, shown with the new owner's e-mail", (r.status_code, owner4, kept, row4))
    finally:
        _drop_people(made)
        db.admins.delete_many({"email": admin_email})


SECTIONS = {"schema": section_schema, "migration": section_migration, "books_in_requests": section_books_in_requests,
            "api_shape": section_api_shape, "books_api": section_books_api, "jobs": section_jobs,
            "notification_links": section_notification_links, "ai_spend": section_ai_spend}


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
