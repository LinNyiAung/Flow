"""Goal history e2e: a goal's money is a list of rows in goal_entries, and what a goal holds is their sum. One function
per section, called from main() (or only the sections named on the command line).

Sections:
  schema -- goal_entries has exactly its columns, goals has no current_amount, each CHECK refuses its bad row, deleting
    a goal deletes its entries and deleting a family member clears the entry's member (Task 1).
  migration -- the goal entries migration on goals seeded in the old shape (goals.current_amount) in two people's
    personal books and a family book: upgrade gives each non-zero goal one carried_over entry with no member and none
    to a zero goal, held sums and the API's current_amount and available balance don't change; downgrade puts the
    column back with the same values, and up again works (Task 1); both directions first lock goals, and an upgrade
    started while a goal write is open waits for it and carries over the committed amount (final review F2). Needs the
    stub server on 127.0.0.1:8765.
  money -- create, contribute, refusals, cents, withdrawing everything, target edits, who a family entry records, two
    racing adds, delete, and the sql/goal_entries helpers (Task 1). Needs the stub server.
  history -- GET /api/goals/{id}/history: order, paging and past the end, limit and offset bounds, 404, who an entry
    names (personal book: nobody; family: the adder, still after they leave; carried_over: nobody, last), a read-only
    family can read it but not add, and removing a placeholder that has goal entries keeps it as former (Task 2).
    Needs the stub server.
"""
import os
import sys
import threading
import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal

os.environ.setdefault("E2E_FAKE_AI", "1")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402,F401

db = __import__("pgcompat").get_db()
failures = 0

BEFORE_ENTRIES = "7e3a91c4d5b8"  # the revision the goal entries migration revises
BASE = "http://127.0.0.1:8765"
FAMILY = {"X-Book": "family"}


def check(ok, name, detail=""):
    global failures
    if not ok:
        failures += 1
    print(("[PASS] " if ok else "[BUG] ") + name + (f" -- {detail}" if detail and not ok else ""), flush=True)


def _columns(table):
    rows = db.sql("SELECT column_name, is_nullable, data_type, numeric_precision, numeric_scale "
                  "FROM information_schema.columns WHERE table_schema = 'public' AND table_name = %s", table)
    return {r["column_name"]: r for r in rows}


def _tables():
    return {r["table_name"] for r in db.sql("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'")}


def _violates(sql, *params):
    """The exception type's name when the database refuses the statement, else None."""
    try:
        db.sql(sql, *params)
    except Exception as e:  # psycopg IntegrityError subclasses
        return type(e).__name__
    return None


def entries(goal_id):
    """The goal's entries oldest first as (kind, amount, member); None when they can't be read (no table)."""
    try:
        rows = db.sql("SELECT kind, amount, added_by_member_id FROM goal_entries WHERE goal_id = %s "
                      "ORDER BY created_at, id", goal_id)
    except Exception:  # noqa: BLE001  (before the migration there is no goal_entries table)
        return None
    return [(r["kind"], r["amount"], r["added_by_member_id"]) for r in rows]


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


# ---------------------------------------------------------------------------------------------------------- schema
def section_schema():
    if "goal_entries" not in _tables():
        check(False, "schema: the goal_entries table exists", "missing")
        return
    cols = _columns("goal_entries")
    want = {"id": ("NO", "text"), "goal_id": ("NO", "text"), "kind": ("NO", "text"), "amount": ("NO", "numeric"),
            "added_by_member_id": ("YES", "text"), "created_at": ("NO", "timestamp with time zone")}
    got = {c: (r["is_nullable"], r["data_type"]) for c, r in cols.items()}
    check(got == want, "schema: goal_entries has exactly id, goal_id, kind, amount, added_by_member_id, created_at", got)
    amount = cols.get("amount") or {}
    check((amount.get("numeric_precision"), amount.get("numeric_scale")) == (18, 2), "schema: goal_entries.amount is MONEY",
          amount)
    check("current_amount" not in _columns("goals"), "schema: goals.current_amount is gone")
    checks = {r["conname"] for r in db.sql("SELECT conname FROM pg_constraint WHERE conrelid = 'goals'::regclass")}
    check("ck_goals_current_non_negative_finite" not in checks, "schema: the goals current_amount CHECK is gone", checks)
    idx = {r["indexname"]: r["indexdef"] for r in db.sql("SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'goal_entries'")}
    check("(goal_id, created_at, id)" in idx.get("ix_goal_entries_goal_created", ""),
          "schema: index ix_goal_entries_goal_created on (goal_id, created_at, id)", idx)
    check("(added_by_member_id)" in idx.get("ix_goal_entries_added_by_member_id", ""),
          "schema: index ix_goal_entries_added_by_member_id", idx)

    tag = uuid.uuid4().hex[:8]
    person, fam = f"gh-{tag}-p", f"gh-{tag}-f"
    book, fbook, goal, member = (str(uuid.uuid4()) for _ in range(4))
    ins = "INSERT INTO goal_entries (id, goal_id, kind, amount, added_by_member_id) VALUES (%s, %s, %s, %s, %s)"
    try:
        db.sql("INSERT INTO users (id, name, email, password) VALUES (%s, 'x', %s, 'x')", person, f"{person}@example.com")
        db.sql("INSERT INTO books (id, kind, person_id) VALUES (%s, 'personal', %s)", book, person)
        db.sql("INSERT INTO families (id, name) VALUES (%s, 'F')", fam)
        db.sql("INSERT INTO books (id, kind, family_id) VALUES (%s, 'family', %s)", fbook, fam)
        db.sql("INSERT INTO family_members (id, family_id, user_id, display_name, kind, role) "
               "VALUES (%s, %s, %s, 'P', 'account', 'owner')", member, fam, person)
        db.sql("INSERT INTO goals (id, book_id, name, goal_type, target_amount) VALUES (%s, %s, 'G', 'savings', 100)", goal, fbook)
        for label, kind, amount in (("a withdraw with a positive amount", "withdraw", "5"),
                                    ("an add with a negative amount", "add", "-5"),
                                    ("an add of 0", "add", "0"),
                                    ("a start of 0", "start", "0"),
                                    ("a carried_over with a negative amount", "carried_over", "-1"),
                                    ("kind 'gift'", "gift", "5")):
            check(_violates(ins, str(uuid.uuid4()), goal, kind, Decimal(amount), None) == "CheckViolation",
                  f"schema: {label} is refused")
        # MONEY (numeric(18,2)) overflows before amount_finite can: either refusal keeps the row out.
        check(_violates(ins, str(uuid.uuid4()), goal, "add", Decimal("1e16"), None) in ("CheckViolation", "NumericValueOutOfRange"),
              "schema: an amount of 1e16 is refused")
        names = {r["conname"] for r in db.sql("SELECT conname FROM pg_constraint WHERE conrelid = 'goal_entries'::regclass "
                                              "AND contype = 'c'")}
        check(names == {"ck_goal_entries_kind", "ck_goal_entries_amount_sign", "ck_goal_entries_amount_finite"},
              "schema: the CHECKs are kind, amount_sign and amount_finite", names)
        good = str(uuid.uuid4())
        for kind, amount in (("start", "10.50"), ("add", "0.01"), ("withdraw", "-3.25"), ("carried_over", "7")):
            check(_violates(ins, good if kind == "start" else str(uuid.uuid4()), goal, kind, Decimal(amount), member) is None,
                  f"schema: a {kind} of {amount} is accepted")
        row = db.sql("SELECT created_at FROM goal_entries WHERE id = %s", good)
        check(row and abs((row[0]["created_at"] - datetime.now(UTC)).total_seconds()) < 120,
              "schema: created_at defaults to now()", row)

        db.sql("DELETE FROM family_members WHERE id = %s", member)
        left = db.sql("SELECT added_by_member_id FROM goal_entries WHERE goal_id = %s", goal)
        check(len(left) == 4 and all(r["added_by_member_id"] is None for r in left),
              "schema: deleting a family member keeps its entries with added_by_member_id NULL", left)
        db.sql("DELETE FROM goals WHERE id = %s", goal)
        check(not db.sql("SELECT 1 FROM goal_entries WHERE goal_id = %s", goal), "schema: deleting a goal deletes its entries")
    finally:
        db.sql("DELETE FROM families WHERE id = %s", fam)
        db.sql("DELETE FROM users WHERE id = %s", person)


# ------------------------------------------------------------------------------------------------------- migration
# (key, owner, currency, current_amount): two people's personal books (A, B) and a family book (F).
SEED_GOALS = (("a0", "A", "usd", "0"), ("a250", "A", "usd", "250"), ("a1234", "A", "mmk", "12.34"),
              ("b999", "B", "usd", "999.99"), ("b0", "B", "mmk", "0"),
              ("f250", "F", "mmk", "250"), ("f1234", "F", "usd", "12.34"), ("f999", "F", "usd", "999.99"))
# (owner, type, amount, currency)
SEED_TX = (("A", "inflow", "2000.00", "usd"), ("A", "outflow", "100.50", "usd"), ("A", "inflow", "500.00", "mmk"),
           ("B", "inflow", "1500.00", "usd"), ("F", "inflow", "3000.00", "mmk"), ("F", "outflow", "20.00", "mmk"),
           ("F", "inflow", "1500.00", "usd"))


def _held(books):
    """{(book, currency): held} from the goals' current_amount (old shape) or their entries (head)."""
    if "current_amount" in _columns("goals"):
        rows = db.sql("SELECT book_id AS b, currency, SUM(current_amount) AS s FROM goals WHERE book_id = ANY(%s) "
                      "GROUP BY 1, 2", list(books))
    else:
        rows = db.sql("SELECT g.book_id AS b, g.currency, COALESCE(SUM(e.amount), 0) AS s FROM goals g "
                      "LEFT JOIN goal_entries e ON e.goal_id = g.id WHERE g.book_id = ANY(%s) GROUP BY 1, 2", list(books))
    return {(r["b"], r["currency"]): Decimal(r["s"]) for r in rows}


def _seed_old_shape(ids):
    import bcrypt
    pw = bcrypt.hashpw(b"secret123", bcrypt.gensalt()).decode()
    q = db.sql
    for p in ("A", "B"):
        q("INSERT INTO users (id, name, email, password, is_verified) VALUES (%s, %s, %s, %s, true)",
          ids[p], p, ids[p + "_email"], pw)
        q("INSERT INTO books (id, kind, person_id) VALUES (%s, 'personal', %s)", ids[p + "_book"], ids[p])
    q("INSERT INTO families (id, name) VALUES (%s, 'Fam')", ids["fam"])
    q("INSERT INTO books (id, kind, family_id) VALUES (%s, 'family', %s)", ids["F_book"], ids["fam"])
    q("INSERT INTO family_members (id, family_id, user_id, display_name, kind, role) VALUES (%s, %s, %s, 'A', 'account', 'owner')",
      ids["MA"], ids["fam"], ids["A"])
    for owner, type_, amount, cur in SEED_TX:
        q("INSERT INTO transactions (id, book_id, type, main_category, sub_category, amount, currency, date) "
          "VALUES (%s, %s, %s, 'Food & Daily Living', 'Groceries', %s, %s, now() - interval '1 day')",
          str(uuid.uuid4()), ids[owner + "_book"], type_, Decimal(amount), cur)
    for key, owner, cur, amount in SEED_GOALS:
        q("INSERT INTO goals (id, book_id, name, goal_type, target_amount, current_amount, currency) "
          "VALUES (%s, %s, %s, 'savings', 5000, %s, %s)", ids[key], ids[owner + "_book"], key, Decimal(amount), cur)


def _check_upgraded(ids, held, label):
    if "goal_entries" not in _tables():
        check(False, f"migration ({label}): the goal_entries table exists", "missing")
        return
    check("current_amount" not in _columns("goals"), f"migration ({label}): goals.current_amount is dropped")
    for key, _, _, amount in SEED_GOALS:
        rows = db.sql("SELECT kind, amount, added_by_member_id, created_at FROM goal_entries WHERE goal_id = %s", ids[key])
        if Decimal(amount) == 0:
            check(rows == [], f"migration ({label}): zero goal {key} has no entry", rows)
        else:
            check(len(rows) == 1 and rows[0]["kind"] == "carried_over" and rows[0]["amount"] == Decimal(amount)
                  and rows[0]["added_by_member_id"] is None
                  and abs((rows[0]["created_at"] - datetime.now(UTC)).total_seconds()) < 300,
                  f"migration ({label}): goal {key} has one carried_over entry of {amount}, no member, created now", rows)
    books = [ids[p + "_book"] for p in ("A", "B", "F")]
    check(_held(books) == held, f"migration ({label}): per-book held sums are identical", (_held(books), held))

    import httpx
    c = httpx.Client(base_url=BASE, timeout=60)
    for person, headers, owner in (("A", {}, "A"), ("B", {}, "B"), ("A", FAMILY, "F")):
        r = c.post("/api/auth/login", json={"email": ids[person + "_email"], "password": "secret123"})
        if r.status_code != 200:
            check(False, f"migration ({label}): {person} logs in", f"{r.status_code} {r.text[:200]}")
            continue
        h = {"Authorization": f"Bearer {r.json()['access_token']}", **headers}
        book = ids[owner + "_book"]
        r = c.get("/api/goals", headers=h)
        got = {g["id"]: g["current_amount"] for g in r.json()} if r.status_code == 200 else r.text[:200]
        want = {ids[k]: float(Decimal(a)) for k, o, _, a in SEED_GOALS if o == owner}
        check(got == want, f"migration ({label}): GET /api/goals for book {owner} returns the same current_amount values",
              (got, want))
        for cur in ("usd", "mmk"):
            flows = {"inflow": Decimal(0), "outflow": Decimal(0)}
            for o, type_, amount, cc in SEED_TX:
                if o == owner and cc == cur:
                    flows[type_] += Decimal(amount)
            want_available = flows["inflow"] - flows["outflow"] - held.get((book, cur), Decimal(0))
            r = c.get("/api/dashboard/balance", headers=h, params={"currency": cur})
            got_available = r.json().get("available_balance") if r.status_code == 200 else r.text[:200]
            check(isinstance(got_available, (int, float)) and abs(Decimal(str(got_available)) - want_available) < Decimal("0.001"),
                  f"migration ({label}): book {owner} {cur} available_balance = inflow - outflow - held",
                  (got_available, want_available))


def _check_locks_goals_first():
    """Both directions start by locking goals ACCESS EXCLUSIVE, before anything reads or changes goals."""
    import ast
    path = os.path.join(stubenv.BACKEND, "alembic", "versions", "20261118_c1f0a8e2d93b_goal_entries.py")
    with open(path, encoding="utf-8") as f:
        tree = ast.parse(f.read())
    for fn in ("upgrade", "downgrade"):
        body = next((n.body for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == fn), [])
        first = ast.unparse(body[0]) if body else None
        check(first == "op.execute('LOCK TABLE goals IN ACCESS EXCLUSIVE MODE')",
              f"migration: {fn}() first locks goals in ACCESS EXCLUSIVE mode", first)


def _check_waits_for_open_write(t, ids):
    """At the old revision a request's transaction has locked a goal's row and not committed when the upgrade starts
    (the old backend keeps serving while the upgrade runs). The upgrade waits on goals for it, and the goal's
    carried_over entry is the amount that transaction committed, not the one before it."""
    import time
    goal, new = ids["a250"], Decimal("400.00")
    done = {}
    upgrade = threading.Thread(target=lambda: done.update(result=t.alembic("upgrade", "head")))
    with t.connect() as watch, t.psycopg.connect(t.DSN) as writer:  # writer is not autocommit: its UPDATEs stay open
        writer.execute("UPDATE goals SET current_amount = current_amount WHERE id = %s", (goal,))
        upgrade.start()
        waiting = False
        for _ in range(1200):  # up to 120 s for the alembic process to start (it is slow on a busy machine) and queue
            waiting = bool(watch.execute("SELECT 1 FROM pg_locks l JOIN pg_class c ON c.oid = l.relation "
                                         "WHERE c.relname = 'goals' AND NOT l.granted").fetchone())
            if waiting:
                break
            time.sleep(0.1)
        time.sleep(1)
        check(waiting and upgrade.is_alive(), "migration (open write): the upgrade waits on goals for an open goal write",
              (waiting, done))
        writer.execute("UPDATE goals SET current_amount = %s WHERE id = %s", (new, goal))
        writer.commit()
    upgrade.join(300)
    ok, out = done.get("result", (False, "the upgrade did not finish"))
    check(ok, "migration (open write): the upgrade finishes once the write commits", out)
    got = entries(goal)
    check(got == [("carried_over", new, None)],
          f"migration (open write): the carried_over entry is the committed amount {new}, not 250", got)


def section_migration():
    import test_plans as t  # noqa: E402  (alembic helper)
    from plans_subscription_checks import head_revision  # noqa: E402

    head = head_revision()
    tag = uuid.uuid4().hex[:8]
    ids = {k: str(uuid.uuid4()) for k in ("A_book", "B_book", "F_book", "fam", "MA", *(g[0] for g in SEED_GOALS))}
    for p in ("A", "B"):
        ids[p] = f"gh-{tag}-{p}"
        ids[p + "_email"] = f"gh-{p.lower()}-{tag}@example.com"
    with t.connect() as conn:
        check(t.current_revision(conn) == head, "migration: the e2e database starts at head", t.current_revision(conn))
    try:
        ok, out = t.alembic("downgrade", BEFORE_ENTRIES)
        check(ok, f"migration: downgrade to {BEFORE_ENTRIES} runs", out)
        if not ok:
            return
        check("current_amount" in _columns("goals") and "goal_entries" not in _tables(),
              "migration: after the downgrade goals.current_amount is back and goal_entries is gone")
        _seed_old_shape(ids)
        books = [ids[p + "_book"] for p in ("A", "B", "F")]
        held = _held(books)
        check(len(held) == 6, "migration: the seed recorded held sums for both currencies of A, B and the family", held)

        # ---- up
        ok, out = t.alembic("upgrade", "head")
        check(ok, "migration: upgrade head runs on the seeded old shape", out)
        if not ok:
            return
        _check_upgraded(ids, held, "upgrade")

        # ---- down: the column is back with the same values
        ok, out = t.alembic("downgrade", BEFORE_ENTRIES)
        check(ok, "migration: downgrade runs on the migrated data", out)
        if not ok:
            return
        check("goal_entries" not in _tables(), "migration (downgrade): goal_entries is dropped")
        got = {r["id"]: r["current_amount"] for r in db.sql("SELECT id, current_amount FROM goals WHERE id = ANY(%s)",
                                                           [ids[g[0]] for g in SEED_GOALS])}
        want = {ids[k]: Decimal(a) for k, _, _, a in SEED_GOALS}
        check(got == want, "migration (downgrade): goals.current_amount is back with the same values", (got, want))
        check(_held(books) == held, "migration (downgrade): per-book held sums are identical", (_held(books), held))
        checks = {r["conname"] for r in db.sql("SELECT conname FROM pg_constraint WHERE conrelid = 'goals'::regclass")}
        check("ck_goals_current_non_negative_finite" in checks, "migration (downgrade): the current_amount CHECK is back", checks)

        ok, out = t.alembic("upgrade", "head")
        check(ok, "migration: upgrade head runs again", out)
        if ok:
            _check_upgraded(ids, held, "upgrade again")

        # ---- a goal write still open when the upgrade starts is not lost
        _check_locks_goals_first()
        ok, out = t.alembic("downgrade", BEFORE_ENTRIES)
        check(ok, "migration (open write): downgrade runs", out)
        if ok:
            _check_waits_for_open_write(t, ids)
    finally:
        ok, out = t.alembic("upgrade", "head")  # whatever happened above, leave the database at head
        with t.connect() as conn:
            check(ok and t.current_revision(conn) == head, "migration: the e2e database is left at head", out)
        db.sql("DELETE FROM families WHERE id = %s", ids["fam"])
        db.sql("DELETE FROM users WHERE id = ANY(%s)", [ids["A"], ids["B"]])


# ----------------------------------------------------------------------------------------------------------- money
def _people(c, tag, made):
    """register(name, plan) -> {"id", "email", "h", "book"}: a verified account on `plan` registered through the API."""
    def register(name, plan="free"):
        email = f"gh-{name.lower()}-{tag}@example.com"
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
        book = (db.sql("SELECT id FROM books WHERE person_id = %s", uid) or [{}])[0].get("id")
        return {"id": uid, "email": email, "h": {"Authorization": f"Bearer {token}"}, "book": book}
    return register


def _inflow(c, headers, amount, currency="usd"):
    r = c.post("/api/transactions", headers=headers, json={
        "type": "inflow", "main_category": "Employment Income", "sub_category": "Salary", "amount": amount,
        "currency": currency, "date": datetime.now(UTC).isoformat(), "description": "salary"})
    check(r.status_code == 200, f"income of {amount} recorded", f"{r.status_code} {r.text[:200]}")


def _goal(c, headers, name, target, initial=None, currency="usd"):
    body = {"name": name, "target_amount": target, "goal_type": "savings", "currency": currency}
    if initial is not None:
        body["initial_contribution"] = initial
    r = c.post("/api/goals", headers=headers, json=body)
    check(r.status_code == 200, f"goal {name} created", f"{r.status_code} {r.text[:200]}")
    return r.json() if r.status_code == 200 else {}


def _available(c, headers, currency="usd"):
    r = c.get("/api/dashboard/balance", headers=headers, params={"currency": currency})
    return r.json().get("available_balance") if r.status_code == 200 else f"{r.status_code} {r.text[:120]}"


def _message(r):
    detail = r.json().get("detail") if r.headers.get("content-type", "").startswith("application/json") else None
    return detail.get("message") if isinstance(detail, dict) else detail


def section_money():
    import httpx

    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:8]
    made = []
    register = _people(c, tag, made)
    D = Decimal
    try:
        A = register("Ann")
        if A is None:
            return
        _inflow(c, A["h"], 1000)

        # ---- create
        g1 = _goal(c, A["h"], "Bike", 500, initial=30)
        check(entries(g1.get("id")) == [("start", D("30.00"), None)], "create: initial_contribution 30 writes one start entry of 30",
              entries(g1.get("id")))
        check(g1.get("current_amount") == 30.0, "create: the response holds 30", g1)
        g2 = _goal(c, A["h"], "Empty", 500)
        check(entries(g2.get("id")) == [], "create: no initial_contribution writes no entry", entries(g2.get("id")))
        g0 = _goal(c, A["h"], "Zero start", 500, initial=0)
        check(entries(g0.get("id")) == [], "create: initial_contribution 0 writes no entry", entries(g0.get("id")))

        # ---- contribute
        gid = g1.get("id")
        r = c.post(f"/api/goals/{gid}/contribute", headers=A["h"], json={"amount": 50})
        check(r.status_code == 200 and r.json().get("current_amount") == 80.0, "contribute: +50 answers 200 holding 80",
              f"{r.status_code} {r.text[:200]}")
        check(entries(gid) == [("start", D("30.00"), None), ("add", D("50.00"), None)], "contribute: +50 writes one add entry of 50",
              entries(gid))
        r = c.post(f"/api/goals/{gid}/contribute", headers=A["h"], json={"amount": -20})
        check(r.status_code == 200 and r.json().get("current_amount") == 60.0, "contribute: -20 answers 200 holding 60",
              f"{r.status_code} {r.text[:200]}")
        check((entries(gid) or [None])[-1] == ("withdraw", D("-20.00"), None) and len(entries(gid)) == 3,
              "contribute: -20 writes one withdraw entry of -20", entries(gid))
        r = c.get(f"/api/goals/{gid}", headers=A["h"])
        check(r.status_code == 200 and r.json().get("current_amount") == 60.0 and abs(r.json().get("progress_percentage") - 12) < 1e-9,
              "contribute: GET /api/goals/{id} holds 60 (12%)", r.text[:200])
        listed = {g["id"]: g["current_amount"] for g in c.get("/api/goals", headers=A["h"]).json()}
        check(listed == {gid: 60.0, g2.get("id"): 0.0, g0.get("id"): 0.0}, "contribute: GET /api/goals holds 60, 0 and 0", listed)

        # ---- refusals write no entry and keep their status and message
        g4 = _goal(c, A["h"], "Done", 10, initial=10)
        check(g4.get("status") == "achieved", "refusals: a goal created at its target is achieved", g4)
        available = _available(c, A["h"])
        check(available == 1000 - 60 - 10, "refusals: available is 930 before the refusals", available)
        g3 = _goal(c, A["h"], "Big", 100000)
        refusals = (
            ("over target", gid, 441, 400, "Cannot exceed target amount. Maximum you can add: USD 440.00"),
            ("insufficient balance", g3.get("id"), 5000, 400, "Insufficient balance. Available for goals: USD 930.00"),
            ("below zero", gid, -61, 400, "Cannot reduce more than current amount: USD 60.00"),
            ("zero amount", gid, 0, 422, "Contribution amount must not be zero"),
            ("achieved goal", g4.get("id"), 1, 400, "Cannot add funds to an achieved goal"),
        )
        for label, goal_id, amount, code, message in refusals:
            before = entries(goal_id)
            r = c.post(f"/api/goals/{goal_id}/contribute", headers=A["h"], json={"amount": amount})
            text = r.text
            check(r.status_code == code and (_message(r) == message if code != 422 else message in text),
                  f"refusals ({label}): {code} \"{message}\"", f"{r.status_code} {text[:240]}")
            check(before is not None and entries(goal_id) == before, f"refusals ({label}): no entry is written",
                  (before, entries(goal_id)))

        # ---- cents (Review Focus 1)
        g5 = _goal(c, A["h"], "Cents", 1)
        g5id = g5.get("id")
        c.post(f"/api/goals/{g5id}/contribute", headers=A["h"], json={"amount": 0.10})
        r = c.post(f"/api/goals/{g5id}/contribute", headers=A["h"], json={"amount": 0.20})
        check(r.status_code == 200 and r.json().get("current_amount") == 0.30, "cents: 0.10 then 0.20 holds exactly 0.30",
              f"{r.status_code} {r.text[:200]}")
        r = c.post(f"/api/goals/{g5id}/contribute", headers=A["h"], json={"amount": 0.40})
        check(r.status_code == 200 and r.json().get("current_amount") == 0.70 and r.json().get("status") == "active",
              "cents: + 0.40 holds 0.70, still active", f"{r.status_code} {r.text[:200]}")
        r = c.post(f"/api/goals/{g5id}/contribute", headers=A["h"], json={"amount": 0.30})
        body = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and body.get("current_amount") == 1.0 and body.get("status") == "achieved"
              and body.get("achieved_at"), "cents: a target-1.00 goal holding 0.70 plus 0.30 is achieved",
              f"{r.status_code} {r.text[:240]}")
        held = db.sql("SELECT SUM(amount) AS s FROM goal_entries WHERE goal_id = %s", g5id) if entries(g5id) is not None else None
        check(held and held[0]["s"] == D("1.00"), "cents: the entries sum to exactly 1.00", held)

        # ---- withdrawing everything (Review Focus 2): a person whose only goal is this one
        C = register("Cleo")
        if C:
            _inflow(c, C["h"], 100)
            g6 = _goal(c, C["h"], "All", 50, initial=50)
            check(g6.get("status") == "achieved", "withdraw everything: the goal starts achieved holding 50", g6)
            r = c.post(f"/api/goals/{g6.get('id')}/contribute", headers=C["h"], json={"amount": -50})
            body = r.json() if r.status_code == 200 else {}
            check(r.status_code == 200 and body.get("current_amount") == 0.0 and body.get("status") == "active"
                  and body.get("achieved_at") is None,
                  "withdraw everything: the goal holds 0.0, is active and achieved_at is null", f"{r.status_code} {r.text[:240]}")
            check(entries(g6.get("id")) == [("start", D("50.00"), None), ("withdraw", D("-50.00"), None)],
                  "withdraw everything: the goal keeps both entries", entries(g6.get("id")))
            s = c.get("/api/goals/summary", headers=C["h"], params={"currency": "usd"}).json()
            check(s.get("total_allocated") == 0, "withdraw everything: the summary's total_allocated is 0", s)
            bal = c.get("/api/dashboard/balance", headers=C["h"], params={"currency": "usd"}).json()
            check(bal.get("allocated_to_goals") == 0 and bal.get("available_balance") == 100,
                  "withdraw everything: the dashboard holds 0 for goals and 100 is available", bal)

        # ---- target edit (Review Focus 3)
        g7 = _goal(c, A["h"], "Edit", 200, initial=100)
        g7id = g7.get("id")
        r = c.put(f"/api/goals/{g7id}", headers=A["h"], json={"target_amount": 100})
        body = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and body.get("status") == "achieved" and body.get("achieved_at")
              and body.get("current_amount") == 100.0,
              "target edit: holding 100, target 100 -> achieved (current_amount 100)", f"{r.status_code} {r.text[:240]}")
        r = c.put(f"/api/goals/{g7id}", headers=A["h"], json={"target_amount": 150})
        body = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and body.get("status") == "active" and body.get("achieved_at") is None
              and body.get("current_amount") == 100.0 and abs(body.get("progress_percentage", 0) - 100 / 1.5) < 1e-6,
              "target edit: target 150 -> active again (current_amount 100)", f"{r.status_code} {r.text[:240]}")
        check(entries(g7id) == [("start", D("100.00"), None)], "target edit: no entry is written", entries(g7id))

        # ---- family: who an entry records
        O, M = register("Owen", "plus"), register("Mia")
        if O and M:
            r = c.post("/api/family", json={"name": f"GH {tag}"}, headers=O["h"])
            check(r.status_code == 200, "family: the owner creates a family", f"{r.status_code} {r.text[:200]}")
            c.post("/api/family/invites", headers=O["h"], json={"email": M["email"]})
            inv = next(iter(c.get("/api/family/invites/mine", headers=M["h"]).json().get("invites", [])), None)
            if inv:
                c.post(f"/api/family/invites/{inv['id']}/accept", headers=M["h"])
            mid = {p: (c.get("/api/family", headers=P["h"]).json().get("me") or {}).get("member_id")
                   for p, P in (("O", O), ("M", M))}
            check(all(mid.values()), "family: owner and member have member ids", mid)
            OF, MF = {**O["h"], **FAMILY}, {**M["h"], **FAMILY}
            _inflow(c, OF, 500)
            fg = _goal(c, OF, "Family trip", 300, initial=30)
            fgid = fg.get("id")
            check(entries(fgid) == [("start", D("30.00"), mid["O"])], "family: start records the creating owner",
                  entries(fgid))
            r = c.post(f"/api/goals/{fgid}/contribute", headers=MF, json={"amount": 20})
            check(r.status_code == 200 and (entries(fgid) or [None])[-1] == ("add", D("20.00"), mid["M"]),
                  "family: the member's add records the member", (r.status_code, entries(fgid)))
            r = c.post(f"/api/goals/{fgid}/contribute", headers=OF, json={"amount": -10})
            check(r.status_code == 200 and (entries(fgid) or [None])[-1] == ("withdraw", D("-10.00"), mid["O"]),
                  "family: the owner's withdraw records the owner", (r.status_code, entries(fgid)))
            before = entries(fgid)
            r = c.post(f"/api/goals/{fgid}/contribute", headers=MF, json={"amount": -5})
            detail = r.json().get("detail") if r.status_code == 403 else None
            check(r.status_code == 403 and isinstance(detail, dict) and detail.get("code") == "not_allowed",
                  "refusals (family member's withdraw): 403 not_allowed", f"{r.status_code} {r.text[:200]}")
            check(before is not None and entries(fgid) == before and len(before) == 3,
                  "refusals (family member's withdraw): no entry is written", (before, entries(fgid)))
        personal = db.sql("SELECT count(*) AS n, count(added_by_member_id) AS m FROM goal_entries e JOIN goals g "
                          "ON g.id = e.goal_id WHERE g.book_id = %s", A["book"]) if entries(gid) is not None else None
        check(personal and personal[0]["n"] > 0 and personal[0]["m"] == 0, "family: personal entries record NULL", personal)

        # ---- concurrency: two adds racing for the same 100
        R = register("Race")
        if R:
            _inflow(c, R["h"], 100)
            ga, gb = _goal(c, R["h"], "Race A", 1000).get("id"), _goal(c, R["h"], "Race B", 1000).get("id")
            barrier, results = threading.Barrier(2), {}

            def add(goal_id):
                with httpx.Client(base_url=BASE, timeout=60) as cc:
                    barrier.wait()
                    results[goal_id] = cc.post(f"/api/goals/{goal_id}/contribute", headers=R["h"], json={"amount": 100})
            threads = [threading.Thread(target=add, args=(g,)) for g in (ga, gb)]
            for th in threads:
                th.start()
            for th in threads:
                th.join()
            codes = sorted(r.status_code for r in results.values())
            refused = [r for r in results.values() if r.status_code == 400]
            check(codes == [200, 400] and _message(refused[0]) == "Insufficient balance. Available for goals: USD 0.00",
                  "concurrency: two parallel +100 adds -> exactly one 200 and one 400 \"Insufficient balance\"",
                  [(r.status_code, r.text[:160]) for r in results.values()])
            totals = {g["id"]: g["current_amount"] for g in c.get("/api/goals", headers=R["h"]).json()}
            sums = {g: float(sum((e[1] for e in (entries(g) or [])), D(0))) for g in (ga, gb)}
            check(totals == sums and sum(sums.values()) == 100.0, "concurrency: the entry sums equal the goals' totals (100 in all)",
                  (totals, sums))
            check(_available(c, R["h"]) == 0, "concurrency: nothing is left available", _available(c, R["h"]))

        # ---- delete
        E = register("Eve")
        if E:
            _inflow(c, E["h"], 200)
            g8 = _goal(c, E["h"], "Gone", 100, initial=30)
            c.post(f"/api/goals/{g8.get('id')}/contribute", headers=E["h"], json={"amount": 50})
            before = _available(c, E["h"])
            r = c.delete(f"/api/goals/{g8.get('id')}", headers=E["h"])
            check(r.status_code == 200 and r.json().get("returned_amount") == 80, "delete: a goal holding 80 returns 80",
                  f"{r.status_code} {r.text[:200]}")
            check(entries(g8.get("id")) == [], "delete: its entries are gone", entries(g8.get("id")))
            after = _available(c, E["h"])
            check(before == 120 and after == 200, "delete: the available balance rises by 80", (before, after))

        # ---- the sql/goal_entries helpers (what the history endpoint reads)
        async def helpers():
            from sql import goal_entries as ge
            return (await ge.list_entries(gid, 2, 0), await ge.list_entries(gid, 10, 2), await ge.list_entries(gid, 10, 3),
                    await ge.count_entries(gid), await ge.count_entries(g2.get("id")),
                    await ge.member_has_entries(mid["M"]) if O and M else None,
                    await ge.member_has_entries(str(uuid.uuid4())),
                    (ge.KIND_START, ge.KIND_ADD, ge.KIND_WITHDRAW, ge.KIND_CARRIED_OVER))
        try:
            first, rest, past, n, n_empty, m_has, nobody_has, kinds = _backend_async(helpers)
            check([(e["kind"], e["amount"]) for e in first + rest] == [("withdraw", -20.0), ("add", 50.0), ("start", 30.0)]
                  and all(isinstance(e["amount"], float) for e in first + rest)
                  and set(first[0]) >= {"_id", "goal_id", "kind", "amount", "added_by_member_id", "created_at"},
                  "helpers: list_entries pages newest first with float amounts", (first, rest))
            check(past == [], "helpers: list_entries past the end is []", past)
            check(n == 3 and n_empty == 0, "helpers: count_entries", (n, n_empty))
            check(m_has is True and nobody_has is False, "helpers: member_has_entries", (m_has, nobody_has))
            check(kinds == ("start", "add", "withdraw", "carried_over"), "helpers: the kind constants", kinds)
        except Exception as e:  # noqa: BLE001
            check(False, "helpers: sql.goal_entries runs", repr(e))

        # ---- add_entry stamps the clock time of the call, not its transaction's start (final review F3)
        async def two_in_one_transaction():
            import asyncio
            from sql import db as sqldb, goal_entries as ge
            async with sqldb.transaction():
                await ge.add_entry(gid, ge.KIND_ADD, 1, None)
                await asyncio.sleep(0.05)
                await ge.add_entry(gid, ge.KIND_ADD, 2, None)
        try:
            _backend_async(two_in_one_transaction)
            rows = db.sql("SELECT amount, created_at FROM goal_entries WHERE goal_id = %s AND kind = 'add' "
                          "AND amount IN (1, 2) ORDER BY amount", gid)
            check(len(rows) == 2 and (rows[1]["created_at"] - rows[0]["created_at"]).total_seconds() >= 0.04,
                  "helpers: two add_entry calls in one transaction get their own times, in call order", rows)
        except Exception as e:  # noqa: BLE001
            check(False, "helpers: add_entry in one transaction runs", repr(e))
    finally:
        if made:
            db.sql("DELETE FROM families WHERE id IN (SELECT family_id FROM family_members WHERE user_id = ANY(%s))", made)
            db.sql("DELETE FROM users WHERE id = ANY(%s)", made)


# --------------------------------------------------------------------------------------------------------- history
def section_history():
    import httpx

    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:8]
    made = []
    register = _people(c, tag, made)
    ins = "INSERT INTO goal_entries (id, goal_id, kind, amount, added_by_member_id, created_at) VALUES (%s, %s, %s, %s, %s, %s)"
    base = datetime.now(UTC) - timedelta(days=2)

    def history(headers, goal_id, **params):
        return c.get(f"/api/goals/{goal_id}/history", headers=headers, params=params)

    try:
        A = register("Ann")
        if A is None:
            return
        g = _goal(c, A["h"], "Hist", 100000).get("id")
        for i in range(12):  # 12 adds of 1..12, one minute apart, oldest first
            db.sql(ins, str(uuid.uuid4()), g, "add", Decimal(i + 1), None, base + timedelta(minutes=i))

        # ---- order and paging
        r = history(A["h"], g)
        body = r.json() if r.status_code == 200 else {}
        got = [e.get("amount") for e in body.get("entries", [])]
        check(r.status_code == 200 and got == [float(n) for n in range(12, 2, -1)] and body.get("total") == 12,
              "history: the default call returns the 10 newest first, total 12", f"{r.status_code} {r.text[:240]}")
        first = (body.get("entries") or [{}])[0]
        check(set(first) == {"id", "kind", "amount", "created_at", "added_by"} and first.get("kind") == "add"
              and first.get("added_by") is None and isinstance(first.get("created_at"), str),
              "history: an entry has id, kind, amount, created_at and added_by", first)
        r = history(A["h"], g, limit=5, offset=10)
        got = [e.get("amount") for e in r.json().get("entries", [])] if r.status_code == 200 else r.text[:200]
        check(got == [2.0, 1.0] and r.json().get("total") == 12, "history: limit 5 offset 10 returns the 2 oldest", got)
        r = history(A["h"], g, offset=12)
        check(r.status_code == 200 and r.json() == {"entries": [], "total": 12},
              "history: offset 12 (past the end) returns no entries and total 12", f"{r.status_code} {r.text[:200]}")
        r = history(A["h"], g, limit=50, offset=0)
        check(r.status_code == 200 and len(r.json().get("entries", [])) == 12, "history: limit 50 returns all 12",
              f"{r.status_code} {r.text[:120]}")
        # the same created_at: id descending
        tie = base + timedelta(hours=1)
        g_tie = _goal(c, A["h"], "Ties", 1000).get("id")
        tie_ids = sorted(str(uuid.uuid4()) for _ in range(3))
        for eid in tie_ids:
            db.sql(ins, eid, g_tie, "add", Decimal(1), None, tie)
        r = history(A["h"], g_tie)
        check(r.status_code == 200 and [e["id"] for e in r.json().get("entries", [])] == tie_ids[::-1],
              "history: entries with the same created_at come id descending", f"{r.status_code} {r.text[:240]}")

        # ---- limits
        for label, params in (("limit=0", {"limit": 0}), ("limit=51", {"limit": 51}), ("offset=-1", {"offset": -1})):
            r = history(A["h"], g, **params)
            check(r.status_code == 422, f"history: {label} is a 422", f"{r.status_code} {r.text[:120]}")

        # ---- another book's goal / unknown goal
        B = register("Bob")
        if B:
            r = history(B["h"], g)
            check(r.status_code == 404 and r.json().get("detail") == "Goal not found",
                  "history: another book's goal is 404 \"Goal not found\"", f"{r.status_code} {r.text[:200]}")
        r = history(A["h"], str(uuid.uuid4()))
        check(r.status_code == 404 and r.json().get("detail") == "Goal not found", "history: an unknown goal is 404", r.status_code)

        # ---- personal book: nobody is named
        _inflow(c, A["h"], 100)
        c.post(f"/api/goals/{g_tie}/contribute", headers=A["h"], json={"amount": 5})
        r = history(A["h"], g_tie)
        check(r.status_code == 200 and r.json().get("total") == 4 and all(e["added_by"] is None for e in r.json()["entries"]),
              "history: in a personal book every added_by is null", f"{r.status_code} {r.text[:240]}")

        # ---- family book
        O, M = register("Owen", "plus"), register("Mia")
        if not (O and M):
            return
        r = c.post("/api/family", json={"name": f"GH {tag}"}, headers=O["h"])
        check(r.status_code == 200, "history: the owner creates a family", f"{r.status_code} {r.text[:200]}")
        c.post("/api/family/invites", headers=O["h"], json={"email": M["email"]})
        inv = next(iter(c.get("/api/family/invites/mine", headers=M["h"]).json().get("invites", [])), None)
        if inv:
            c.post(f"/api/family/invites/{inv['id']}/accept", headers=M["h"])
        mid = {p: (c.get("/api/family", headers=P["h"]).json().get("me") or {}).get("member_id") for p, P in (("O", O), ("M", M))}
        fid = (db.sql("SELECT family_id FROM family_members WHERE user_id = %s", O["id"]) or [{}])[0].get("family_id")
        check(all(mid.values()) and fid, "history: owner and member have member ids", (mid, fid))
        OF, MF = {**O["h"], **FAMILY}, {**M["h"], **FAMILY}
        _inflow(c, OF, 500)
        fg = _goal(c, OF, "Family trip", 300, initial=30).get("id")
        r = c.post(f"/api/goals/{fg}/contribute", headers=MF, json={"amount": 20})
        check(r.status_code == 200, "history: the member adds 20", f"{r.status_code} {r.text[:200]}")
        db.sql(ins, str(uuid.uuid4()), fg, "carried_over", Decimal("7"), None, datetime.now(UTC) - timedelta(days=30))
        r = history(OF, fg)
        es = r.json().get("entries", []) if r.status_code == 200 else []
        check([(e["kind"], e["amount"], (e["added_by"] or {}).get("display_name")) for e in es]
              == [("add", 20.0, "Mia"), ("start", 30.0, "Owen"), ("carried_over", 7.0, None)] and r.json().get("total") == 3,
              "history: family entries name their adder; carried_over names nobody and sorts last", f"{r.status_code} {r.text[:400]}")
        check(es and es[0]["added_by"] == {"member_id": mid["M"], "display_name": "Mia"},
              "history: added_by is {member_id, display_name}", es[:1])

        # ---- read-only family (Review Focus 4): the owner's plan lapses
        n_before = db.sql("SELECT count(*) AS n FROM goal_entries WHERE goal_id = %s", fg)[0]["n"]
        db.sql("UPDATE users SET subscription_expires_at = now() - interval '1 day' WHERE id = %s", O["id"])
        try:
            r = history(MF, fg)
            check(r.status_code == 200 and r.json().get("total") == 3,
                  "history: a read-only family's member reads the history (200)", f"{r.status_code} {r.text[:200]}")
            r = c.post(f"/api/goals/{fg}/contribute", headers=MF, json={"amount": 1})
            detail = r.json().get("detail") if r.status_code == 403 else None
            n_after = db.sql("SELECT count(*) AS n FROM goal_entries WHERE goal_id = %s", fg)[0]["n"]
            check(r.status_code == 403 and isinstance(detail, dict) and detail.get("code") == "family_read_only"
                  and n_after == n_before,
                  "history: read-only: an Add is refused (family_read_only) and writes no entry",
                  f"{r.status_code} {r.text[:200]} {n_before}->{n_after}")
        finally:
            db.sql("UPDATE users SET subscription_expires_at = now() + interval '30 days' WHERE id = %s", O["id"])

        # ---- placeholders: one with a goal entry is kept as former, one with nothing is deleted
        for name in ("Grandma", "Grandpa"):
            r = c.post("/api/family/placeholders", headers=O["h"], json={"display_name": name})
            check(r.status_code == 200, f"history: the owner adds placeholder {name}", f"{r.status_code} {r.text[:200]}")
        ph = {n: (db.sql("SELECT id FROM family_members WHERE family_id = %s AND display_name = %s", fid, n) or [{}])[0].get("id")
              for n in ("Grandma", "Grandpa")}
        db.sql(ins, str(uuid.uuid4()), fg, "add", Decimal("3"), ph["Grandma"], datetime.now(UTC))
        r = c.delete(f"/api/family/members/{ph['Grandma']}", headers=O["h"])
        row = db.sql("SELECT kind, status FROM family_members WHERE id = %s", ph["Grandma"])
        check(r.status_code == 200 and row and row[0]["status"] == "former",
              "history: removing a placeholder with a goal entry keeps it as former", f"{r.status_code} {row}")
        r = history(OF, fg)
        names = [(e["added_by"] or {}).get("display_name") for e in r.json().get("entries", [])] if r.status_code == 200 else r.text[:200]
        check(names and names[0] == "Grandma", "history: that entry still names the former placeholder", names)
        r = c.delete(f"/api/family/members/{ph['Grandpa']}", headers=O["h"])
        gone = db.sql("SELECT count(*) AS n FROM family_members WHERE id = %s", ph["Grandpa"])[0]["n"]
        check(r.status_code == 200 and gone == 0, "history: a placeholder with no tags and no entries is still deleted",
              f"{r.status_code} {gone}")

        # ---- a member who leaves keeps their name on their entries
        r = c.post("/api/family/leave", headers=M["h"])
        check(r.status_code == 200, "history: Mia leaves the family", f"{r.status_code} {r.text[:200]}")
        r = history(OF, fg)
        es = r.json().get("entries", []) if r.status_code == 200 else []
        mia = [e for e in es if e["kind"] == "add" and e["amount"] == 20.0]
        check(mia and (mia[0]["added_by"] or {}).get("display_name") == "Mia",
              "history: after Mia leaves, her entry still returns her display_name", f"{r.status_code} {r.text[:300]}")
    finally:
        if made:
            db.sql("DELETE FROM families WHERE id IN (SELECT family_id FROM family_members WHERE user_id = ANY(%s))", made)
            db.sql("DELETE FROM users WHERE id = ANY(%s)", made)


SECTIONS = {"schema": section_schema, "migration": section_migration, "money": section_money,
            "history": section_history}


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
