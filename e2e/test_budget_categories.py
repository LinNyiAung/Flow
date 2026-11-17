"""Budget categories e2e: a budget line stores its main and sub category in separate columns. One function per
section, called from main() (or only the sections named on the command line).

Sections:
  migration -- the budget sub-category migration on a database seeded in the old shape ("Main - Sub" in
    main_category): upgrade splits on the first " - " (amounts unchanged), downgrade rejoins the original texts, and
    up again splits again (Task 1).
  api -- through the API: create keeps sub_category, the old "Main - Sub" main_category gets 422 on create and PUT,
    a blank sub is stored as NULL, a GET's category_budgets PUT back as-is is accepted, and a PUT keys each line's
    stored spend on (main, sub) so a main line and its own sub line keep their own spent values (Task 1). Needs the
    stub server on 127.0.0.1:8765.
"""
import os
import sys
import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal

os.environ.setdefault("E2E_FAKE_AI", "1")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402,F401

db = __import__("pgcompat").get_db()
failures = 0

BEFORE_SUB = "d846defddc6e"  # the revision the budget sub-category migration revises
REV_BUDGET_SUB = "b4c7576d96c6"  # the budget sub-category migration
BASE = "http://127.0.0.1:8765"

# Two real seeded outflow sub-categories of different mains (backend/database.py).
MAIN1, SUB1 = "Food & Daily Living", "Groceries"
MAIN2, SUB2 = "Transportation", "Fuel"


def check(ok, name, detail=""):
    global failures
    if not ok:
        failures += 1
    print(("[PASS] " if ok else "[BUG] ") + name + (f" -- {detail}" if detail and not ok else ""), flush=True)


def _columns(table):
    rows = db.sql("SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = %s",
                  table)
    return {r["column_name"] for r in rows}


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


# ------------------------------------------------------------------------------------------------------- migration
def _seed_person(tag):
    """A person and their personal book, inserted with raw SQL (the shape is the same before and after the budget
    migration) -> (user id, book id)."""
    uid, book = f"bc-{tag}", str(uuid.uuid4())
    db.sql("INSERT INTO users (id, name, email, password) VALUES (%s, 'BC', %s, 'x')", uid, f"bc-{tag}@example.com")
    db.sql("INSERT INTO books (id, kind, person_id) VALUES (%s, 'personal', %s)", book, uid)
    return uid, book


def _allocs(budget_id):
    cols = _columns("budget_allocations")
    sub = "sub_category" if "sub_category" in cols else "NULL AS sub_category"
    return [(r["main_category"], r["sub_category"], r["allocated_amount"])
            for r in db.sql(f"SELECT main_category, {sub}, allocated_amount FROM budget_allocations "
                            "WHERE budget_id = %s ORDER BY position", budget_id)]


def section_migration():
    import test_plans as t  # noqa: E402  (alembic helper)
    from plans_subscription_checks import head_revision  # noqa: E402

    head = head_revision()
    tag = uuid.uuid4().hex[:8]
    budget_id = str(uuid.uuid4())
    uid = None
    old_texts = [f"{MAIN1} - {SUB1}", MAIN2]
    amounts = [Decimal("120.50"), Decimal("80.00")]
    split = [(MAIN1, SUB1, amounts[0]), (MAIN2, None, amounts[1])]
    with t.connect() as conn:
        check(t.current_revision(conn) == head, "migration: the e2e database starts at head", t.current_revision(conn))
    try:
        ok, out = t.alembic("downgrade", BEFORE_SUB)
        check(ok, f"migration: downgrade to {BEFORE_SUB} runs", out)
        if not ok:
            return
        check("sub_category" not in _columns("budget_allocations"),
              "migration: after the downgrade budget_allocations has no sub_category column")
        uid, book = _seed_person(tag)
        db.sql("INSERT INTO budgets (id, book_id, name, period, currency, start_date, end_date, total_budget, status) "
               "VALUES (%s, %s, 'BC', 'monthly', 'usd', now(), now() + interval '30 days', 200, 'active')", budget_id, book)
        for pos, (text, amt) in enumerate(zip(old_texts, amounts)):
            db.sql("INSERT INTO budget_allocations (budget_id, position, main_category, allocated_amount) "
                   "VALUES (%s, %s, %s, %s)", budget_id, pos, text, amt)

        # ---- up
        ok, out = t.alembic("upgrade", "head")
        check(ok, "migration: upgrade head runs on the seeded old shape", out)
        if not ok:
            return
        got = _allocs(budget_id)
        check(got == split, "migration: upgrade splits 'Main - Sub' into (main, sub), a main-only line gets sub NULL, "
                            "amounts unchanged", (got, split))

        # ---- down: the original texts come back
        ok, out = t.alembic("downgrade", BEFORE_SUB)
        check(ok, "migration: downgrade runs on the migrated data", out)
        if not ok:
            return
        check("sub_category" not in _columns("budget_allocations"),
              "migration: downgrade drops budget_allocations.sub_category")
        got = [(m, a) for m, _, a in _allocs(budget_id)]
        check(got == list(zip(old_texts, amounts)), "migration: downgrade rejoins the original 'Main - Sub' texts",
              (got, list(zip(old_texts, amounts))))

        # ---- up again (to this migration's own revision id)
        ok, out = t.alembic("upgrade", REV_BUDGET_SUB)
        check(ok, f"migration: upgrade to {REV_BUDGET_SUB} runs again", out)
        if ok:
            got = _allocs(budget_id)
            check(got == split, "migration: upgrade again splits the lines again", (got, split))
    finally:
        ok, out = t.alembic("upgrade", "head")  # whatever happened above, leave the database at head
        with t.connect() as conn:
            check(ok and t.current_revision(conn) == head, "migration: the e2e database is left at head", out)
        if uid:
            db.sql("DELETE FROM users WHERE id = %s", uid)  # cascades to the book, the budget and its lines


# ------------------------------------------------------------------------------------------------------------- api
def _register(c, tag, made, name, plan="plus"):
    """A verified account on `plan` registered through the API -> {"id", "h", "book"}; its id is added to `made`."""
    email = f"bc-{name.lower()}-{tag}@example.com"
    r = c.post("/api/auth/register", json={"name": name, "email": email, "password": "secret123"})
    if r.status_code != 200:
        check(False, f"register {name}", f"{r.status_code} {r.text[:200]}")
        return None
    uid = db.sql("SELECT id FROM users WHERE email = %s", email)[0]["id"]
    made.append(uid)
    db.sql("UPDATE users SET is_verified = true, subscription_type = %s, subscription_expires_at = %s, "
           "trial_ends_at = NULL WHERE id = %s", plan, datetime.now(UTC) + timedelta(days=30), uid)
    token = c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json().get("access_token")
    book = (db.sql("SELECT id FROM books WHERE person_id = %s", uid) or [{}])[0].get("id")
    return {"id": uid, "h": {"Authorization": f"Bearer {token}"}, "book": book}


def _lines(body):
    return [(x.get("main_category"), x.get("sub_category"), x.get("allocated_amount"))
            for x in (body or {}).get("category_budgets") or []]


def section_api():
    import httpx

    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:8]
    made = []
    som = datetime.now(UTC).replace(day=1, hour=0, minute=0, second=0, microsecond=0)

    def create(lines, total=150, name="BC"):
        return c.post("/api/budgets", headers=P["h"], json={
            "name": name, "period": "monthly", "start_date": som.isoformat(), "currency": "usd",
            "total_budget": total, "category_budgets": lines})

    try:
        P = _register(c, tag, made, "Cats")
        if P is None:
            return

        # ---- create keeps sub
        r = create([{"main_category": MAIN1, "sub_category": SUB1, "allocated_amount": 100},
                    {"main_category": MAIN2, "sub_category": None, "allocated_amount": 50}])
        want = [(MAIN1, SUB1, 100), (MAIN2, None, 50)]
        body = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and _lines(body) == want,
              "create keeps sub: the POST response has main_category / sub_category per line", (r.status_code, r.text[:300]))
        bid = body.get("id")
        g = c.get(f"/api/budgets/{bid}", headers=P["h"]) if bid else None
        check(g is not None and g.status_code == 200 and _lines(g.json()) == want,
              "create keeps sub: a GET returns the same main_category / sub_category",
              g.text[:300] if g is not None else "no budget")
        stored = db.sql("SELECT main_category, sub_category FROM budget_allocations WHERE budget_id = %s ORDER BY position",
                        bid) if bid else []
        check([(s["main_category"], s["sub_category"]) for s in stored] == [(MAIN1, SUB1), (MAIN2, None)],
              "create keeps sub: the stored rows hold main and sub in their own columns", stored)

        # ---- old format refused
        r = create([{"main_category": f"{MAIN1} - {SUB1}", "allocated_amount": 100}])
        check(r.status_code == 422, "old format refused: POST with main_category 'Main - Sub' gets 422",
              (r.status_code, r.text[:200]))
        if bid:
            r = c.put(f"/api/budgets/{bid}", headers=P["h"],
                      json={"category_budgets": [{"main_category": f"{MAIN1} - {SUB1}", "allocated_amount": 100}]})
            check(r.status_code == 422, "old format refused: PUT with main_category 'Main - Sub' gets 422",
                  (r.status_code, r.text[:200]))

        # ---- blank sub is null
        r = create([{"main_category": MAIN1, "sub_category": "", "allocated_amount": 70},
                    {"main_category": MAIN2, "sub_category": "   ", "allocated_amount": 30}], total=100, name="BC blank")
        body = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and _lines(body) == [(MAIN1, None, 70), (MAIN2, None, 30)],
              "blank sub is null: a blank sub_category is returned as null", (r.status_code, r.text[:300]))
        blank_id = body.get("id")
        stored = db.sql("SELECT sub_category FROM budget_allocations WHERE budget_id = %s ORDER BY position",
                        blank_id) if blank_id else []
        check(len(stored) == 2 and all(s["sub_category"] is None for s in stored),
              "blank sub is null: a blank sub_category is stored as NULL", stored)

        # ---- GET round-trips
        if bid:
            got = c.get(f"/api/budgets/{bid}", headers=P["h"]).json()
            r = c.put(f"/api/budgets/{bid}", headers=P["h"], json={"category_budgets": got.get("category_budgets")})
            check(r.status_code == 200 and _lines(r.json()) == want,
                  "GET round-trips: PUT with a GET's category_budgets array gets 200 and keeps the lines",
                  (r.status_code, r.text[:300]))

        # ---- PUT keeps each line's spent
        _put_keeps_each_lines_spent(create, P)
    finally:
        if made:
            db.sql("DELETE FROM users WHERE id = ANY(%s)", made)


def _put_keeps_each_lines_spent(create, P):
    """A main line and its own sub line share main_category: the PUT must find each line's stored spend by
    (main, sub). The route's spend recompute (which rewrites spent from transactions) is switched off, in-process, so
    what the route carried over is what is stored."""
    r = create([{"main_category": MAIN1, "sub_category": None, "allocated_amount": 300},
                {"main_category": MAIN1, "sub_category": SUB1, "allocated_amount": 100}], total=300, name="BC spent")
    bid = (r.json() if r.status_code == 200 else {}).get("id")
    check(bool(bid), "PUT keeps each line's spent: the budget with a main line and its own sub line is created",
          (r.status_code, r.text[:200]))
    if not bid:
        return
    seeded = {None: (Decimal("30.00"), Decimal("10.00"), False), SUB1: (Decimal("120.00"), Decimal("120.00"), True)}
    for sub, (spent, pct, exceeded) in seeded.items():
        db.sql("UPDATE budget_allocations SET spent_amount = %s, percentage_used = %s, is_exceeded = %s "
               "WHERE budget_id = %s AND main_category = %s AND sub_category IS NOT DISTINCT FROM %s",
               spent, pct, exceeded, bid, MAIN1, sub)

    async def put():
        import budget_routes as br
        from budget_models import BudgetUpdate
        from families.book import Book
        stubenv.patch_loaded_modules()
        orig = br.update_budget_spent_amounts

        async def no_recompute(*a, **k):
            return None
        br.update_budget_spent_amounts = no_recompute
        try:
            # Changed allocations, and the sub line first: the order must not matter either.
            data = BudgetUpdate(category_budgets=[
                {"main_category": MAIN1, "sub_category": SUB1, "allocated_amount": 150},
                {"main_category": MAIN1, "sub_category": None, "allocated_amount": 400},
            ])
            book = Book(id=P["book"], kind="personal", person={"_id": P["id"], "personal_book_id": P["book"]},
                        family=None, member=None, read_only=False)
            await br.update_budget(budget_id=bid, budget_data=data, book=book)
        finally:
            br.update_budget_spent_amounts = orig
    try:
        _backend_async(put)
    except Exception as e:  # noqa: BLE001
        check(False, "PUT keeps each line's spent: the in-process PUT runs", repr(e)[:300])
        return
    rows = db.sql("SELECT sub_category, allocated_amount, spent_amount, percentage_used, is_exceeded "
                  "FROM budget_allocations WHERE budget_id = %s ORDER BY position", bid)
    got = {r["sub_category"]: (r["spent_amount"], r["percentage_used"], r["is_exceeded"]) for r in rows}
    allocated = {r["sub_category"]: r["allocated_amount"] for r in rows}
    check(allocated == {SUB1: Decimal("150.00"), None: Decimal("400.00")},
          "PUT keeps each line's spent: the PUT stored the changed allocations", allocated)
    check(got == seeded, "PUT keeps each line's spent: the main line and its sub line each keep their own stored "
                         "spent / percentage / exceeded (no collision on main_category)", (got, seeded))


SECTIONS = {"migration": section_migration, "api": section_api}


def main():
    wanted = sys.argv[1:] or list(SECTIONS)
    unknown = [w for w in wanted if w not in SECTIONS]
    if unknown:
        print(f"unknown section(s) {unknown}; choose from {list(SECTIONS)}")
        sys.exit(2)
    for name in wanted:
        SECTIONS[name]()
    print(f"\n{failures} failure(s)", flush=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
