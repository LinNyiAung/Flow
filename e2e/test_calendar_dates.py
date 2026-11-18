"""Calendar dates e2e (schema project #4): transaction dates are local date-times with no timezone, calendar dates are
DATE, every person has a timezone. One function per section, called from main() (or only the sections named on the
command line).

Sections:
  schema -- every converted column has its new type and nullability (transactions.date timestamp without time zone;
    recurrence end / last-created, budget start / end, goal target and insight bounds DATE; users.timezone text NULL),
    local_job_runs has its columns and primary key, the date indexes are still there and the budget dates_ordered
    CHECK still refuses an end before the start (Task 1).
  migration -- the calendar dates migration on rows seeded in the old shape (fake-UTC timestamptz): upgrade keeps every
    date and time (a transaction at 23:40 stays 23:40 on the same day, a budget ending at 00:00 keeps its date and a
    budget ending at 23:59:59.999 keeps its date, a start time that isn't midnight widens to its day, goal targets,
    recurrence pointers and insight bounds keep their day, recurring child ids are untouched); downgrade puts the UTC
    labels back (a budget end as 23:59:59.999999 of its day, every other date as midnight UTC); up again works; the API
    returns the new shapes and an old-style "...Z" input keeps its clock fields (Task 1). Needs the stub server on
    127.0.0.1:8765.
"""
import os
import sys
import uuid
from datetime import UTC, date, datetime

os.environ.setdefault("E2E_FAKE_AI", "1")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402,F401

db = __import__("pgcompat").get_db()
db._pg.prepare_threshold = None  # the migration changes column types under prepared statements: never prepare
failures = 0

BEFORE_DATES = "c1f0a8e2d93b"  # the revision the calendar dates migration revises
BASE = "http://127.0.0.1:8765"

TS_NAIVE, TS_TZ, DATE, TEXT = "timestamp without time zone", "timestamp with time zone", "date", "text"
# (table, column) -> (is_nullable, data_type) at head
NEW_TYPES = {
    ("transactions", "date"): ("NO", TS_NAIVE),
    ("transactions", "recurrence_end_date"): ("YES", DATE),
    ("transactions", "recurrence_last_created_date"): ("YES", DATE),
    ("budgets", "start_date"): ("NO", DATE),
    ("budgets", "end_date"): ("NO", DATE),
    ("goals", "target_date"): ("YES", DATE),
    ("insights", "week_start"): ("YES", DATE),
    ("insights", "week_end"): ("YES", DATE),
    ("insights", "month_start"): ("YES", DATE),
    ("insights", "month_end"): ("YES", DATE),
    ("users", "timezone"): ("YES", TEXT),
}
# Indexes on the converted columns, kept (rebuilt) on the new types.
DATE_INDEXES = {
    "transactions": ("ix_transactions_book_date", "ix_transactions_book_type_date", "ix_transactions_parent_date"),
    "budgets": ("uq_budgets_rollover_child", "ix_budgets_rollover_candidates", "ix_budgets_book_window"),
    "goals": ("ix_goals_status_target_date",),
}


def check(ok, name, detail=""):
    global failures
    if not ok:
        failures += 1
    print(("[PASS] " if ok else "[BUG] ") + name + (f" -- {detail}" if detail and not ok else ""), flush=True)


def _columns(table):
    rows = db.sql("SELECT column_name, is_nullable, data_type, column_default "
                  "FROM information_schema.columns WHERE table_schema = 'public' AND table_name = %s", table)
    return {r["column_name"]: r for r in rows}


def _tables():
    return {r["table_name"] for r in db.sql("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'")}


def _indexes(table):
    return {r["indexname"] for r in db.sql("SELECT indexname FROM pg_indexes WHERE tablename = %s", table)}


def _violates(sql, *params):
    """The exception type's name when the database refuses the statement, else None."""
    try:
        db.sql(sql, *params)
    except Exception as e:  # psycopg IntegrityError subclasses
        return type(e).__name__
    return None


def _check_types(label, want):
    for (table, column), (nullable, data_type) in want.items():
        col = _columns(table).get(column)
        got = (col["is_nullable"], col["data_type"]) if col else None
        check(got == (nullable, data_type), f"{label}: {table}.{column} is {data_type} "
              f"{'NULL' if nullable == 'YES' else 'NOT NULL'}", got)


def _check_indexes(label):
    for table, names in DATE_INDEXES.items():
        have = _indexes(table)
        check(all(n in have for n in names), f"{label}: the {table} date indexes are there", sorted(have))


# ---------------------------------------------------------------------------------------------------------- schema
def section_schema():
    _check_types("schema", NEW_TYPES)
    _check_indexes("schema")

    if "local_job_runs" not in _tables():
        check(False, "schema: the local_job_runs table exists", "missing")
    else:
        cols = _columns("local_job_runs")
        got = {c: (r["is_nullable"], r["data_type"]) for c, r in cols.items()}
        want = {"job": ("NO", TEXT), "subject_id": ("NO", TEXT), "local_date": ("NO", DATE), "claimed_at": ("NO", TS_TZ)}
        check(got == want, "schema: local_job_runs has exactly job, subject_id, local_date, claimed_at", got)
        check("now()" in (cols.get("claimed_at", {}).get("column_default") or ""),
              "schema: local_job_runs.claimed_at defaults to now()", cols.get("claimed_at"))
        pk = db.sql("SELECT c.conname, array_agg(a.attname ORDER BY k.n) AS cols FROM pg_constraint c "
                    "CROSS JOIN LATERAL unnest(c.conkey) WITH ORDINALITY AS k(attnum, n) "
                    "JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum "
                    "WHERE c.conrelid = 'local_job_runs'::regclass AND c.contype = 'p' GROUP BY c.conname")
        check(len(pk) == 1 and pk[0]["conname"] == "pk_local_job_runs"
              and list(pk[0]["cols"]) == ["job", "subject_id", "local_date"],
              "schema: local_job_runs' primary key is (job, subject_id, local_date)", pk)
        key = ("goal_deadline_reminders", f"cd-{uuid.uuid4().hex[:8]}", date(2026, 11, 18))
        try:
            ins = "INSERT INTO local_job_runs (job, subject_id, local_date) VALUES (%s, %s, %s)"
            check(_violates(ins, *key) is None, "schema: a first local_job_runs claim is accepted")
            check(_violates(ins, *key) == "UniqueViolation", "schema: the same (job, subject, local date) twice is refused")
        finally:
            db.sql("DELETE FROM local_job_runs WHERE subject_id = %s", key[1])

    tag = uuid.uuid4().hex[:8]
    person, book = f"cd-{tag}-p", str(uuid.uuid4())
    try:
        db.sql("INSERT INTO users (id, name, email, password) VALUES (%s, 'x', %s, 'x')", person, f"{person}@example.com")
        check("timezone" in _columns("users")
              and db.sql("SELECT timezone FROM users WHERE id = %s", person) == [{"timezone": None}],
              "schema: a new person's timezone is NULL (the default zone)")
        db.sql("INSERT INTO books (id, kind, person_id) VALUES (%s, 'personal', %s)", book, person)
        ins = ("INSERT INTO budgets (id, book_id, name, period, start_date, end_date, total_budget, status) "
               "VALUES (%s, %s, 'B', 'custom', %s, %s, 10, 'active')")
        check(_violates(ins, str(uuid.uuid4()), book, date(2026, 11, 2), date(2026, 11, 1)) == "CheckViolation",
              "schema: a budget ending before it starts is refused (dates_ordered)")
        check(_violates(ins, str(uuid.uuid4()), book, date(2026, 11, 1), date(2026, 11, 1)) is None,
              "schema: a one-day budget (end = start) is accepted")
    finally:
        db.sql("DELETE FROM users WHERE id = %s", person)


# ------------------------------------------------------------------------------------------------------- migration
# The rows are seeded at BEFORE_DATES with SQL, in the old fake-UTC shape.
SEED_TX = "2026-11-18 23:40:00+00"
SEED_BUDGETS = {  # key -> (period, start, end) as stored before
    "custom": ("custom", "2026-11-01 00:00:00+00", "2026-12-01 00:00:00+00"),
    "monthly": ("monthly", "2026-11-01 00:00:00+00", "2026-11-30 23:59:59.999+00"),
    "late_start": ("custom", "2026-11-05 14:00:00+00", "2026-11-20 00:00:00+00"),
}
WANT_BUDGETS = {  # after the upgrade
    "custom": (date(2026, 11, 1), date(2026, 12, 1)),
    "monthly": (date(2026, 11, 1), date(2026, 11, 30)),
    "late_start": (date(2026, 11, 5), date(2026, 11, 20)),
}
WANT_BUDGETS_DOWN = {  # after the downgrade: the end is the last moment of its day, the start its midnight
    "custom": ("2026-11-01 00:00:00", "2026-12-01 23:59:59.999999"),
    "monthly": ("2026-11-01 00:00:00", "2026-11-30 23:59:59.999999"),
    "late_start": ("2026-11-05 00:00:00", "2026-11-20 23:59:59.999999"),
}


def _utc(text):
    return datetime.fromisoformat(text).replace(tzinfo=UTC)


def _seed_old_shape(ids):
    import bcrypt
    pw = bcrypt.hashpw(b"secret123", bcrypt.gensalt()).decode()
    q = db.sql
    q("INSERT INTO users (id, name, email, password, is_verified) VALUES (%s, 'A', %s, %s, true)", ids["A"], ids["email"], pw)
    q("INSERT INTO books (id, kind, person_id) VALUES (%s, 'personal', %s)", ids["book"], ids["A"])
    tx = ("INSERT INTO transactions (id, book_id, type, main_category, sub_category, amount, currency, date, "
          "recurrence_enabled, recurrence_frequency, recurrence_day_of_month, recurrence_end_date, "
          "recurrence_last_created_date, parent_transaction_id) VALUES (%s, %s, %s, 'Food & Daily Living', 'Groceries', "
          "%s, 'usd', %s::timestamptz, %s, %s, %s, %s::timestamptz, %s::timestamptz, %s)")
    q(tx, ids["income"], ids["book"], "inflow", 5000, "2026-11-01 08:00:00+00", False, None, None, None, None, None)
    q(tx, ids["tx"], ids["book"], "outflow", 12.5, SEED_TX, False, None, None, None, None, None)
    q(tx, ids["parent"], ids["book"], "outflow", 30, "2026-09-03 09:15:00+00", True, "monthly", 3,
      "2027-03-03 00:00:00+00", "2026-10-03 09:15:00+00", None)
    q(tx, ids["child"], ids["book"], "outflow", 30, "2026-10-03 09:15:00+00", False, None, None, None, None, ids["parent"])
    for key, (period, start, end) in SEED_BUDGETS.items():
        q("INSERT INTO budgets (id, book_id, name, period, start_date, end_date, total_budget, status) "
          "VALUES (%s, %s, %s, %s, %s::timestamptz, %s::timestamptz, 100, 'active')", ids["b_" + key], ids["book"], key,
          period, start, end)
    q("INSERT INTO goals (id, book_id, name, goal_type, target_amount, target_date) "
      "VALUES (%s, %s, 'Trip', 'savings', 900, '2026-12-25 00:00:00+00')", ids["goal"], ids["book"])
    q("INSERT INTO insights (id, book_id, insight_type, ai_provider, content, week_start, week_end) "
      "VALUES (%s, %s, 'weekly', 'openai', 'x', '2026-11-09 00:00:00+00', '2026-11-15 23:59:59.999999+00')",
      ids["insight"], ids["book"])
    q("INSERT INTO insights (id, book_id, insight_type, ai_provider, content, month_start, month_end) "
      "VALUES (%s, %s, 'monthly', 'openai', 'x', '2026-10-01 00:00:00+00', '2026-10-31 23:59:59.999999+00')",
      ids["insight_m"], ids["book"])


def _one(sql, *params):
    rows = db.sql(sql, *params)
    return rows[0] if rows else {}


def _check_upgraded(ids, label):
    _check_types(f"migration ({label})", NEW_TYPES)
    _check_indexes(f"migration ({label})")
    check("local_job_runs" in _tables(), f"migration ({label}): local_job_runs exists")
    tx = _one("SELECT date FROM transactions WHERE id = %s", ids["tx"]).get("date")
    check(tx == datetime(2026, 11, 18, 23, 40), f"migration ({label}): the transaction at 23:40 UTC-labelled reads "
          "2026-11-18 23:40:00 with no timezone", tx)
    for key, (start, end) in WANT_BUDGETS.items():
        got = _one("SELECT start_date, end_date FROM budgets WHERE id = %s", ids["b_" + key])
        check((got.get("start_date"), got.get("end_date")) == (start, end),
              f"migration ({label}): budget {key} {SEED_BUDGETS[key][1:]} becomes {start} to {end}", got)
    goal = _one("SELECT target_date FROM goals WHERE id = %s", ids["goal"]).get("target_date")
    check(goal == date(2026, 12, 25), f"migration ({label}): the goal target becomes 2026-12-25", goal)
    parent = _one("SELECT recurrence_end_date, recurrence_last_created_date, date FROM transactions WHERE id = %s",
                  ids["parent"])
    check((parent.get("recurrence_end_date"), parent.get("recurrence_last_created_date"), parent.get("date"))
          == (date(2027, 3, 3), date(2026, 10, 3), datetime(2026, 9, 3, 9, 15)),
          f"migration ({label}): the recurring parent's end and last-created pointer become dates, its date keeps "
          "09:15", parent)
    child = db.sql("SELECT id, date, parent_transaction_id FROM transactions WHERE parent_transaction_id = %s", ids["parent"])
    check(child == [{"id": ids["child"], "date": datetime(2026, 10, 3, 9, 15), "parent_transaction_id": ids["parent"]}],
          f"migration ({label}): the child keeps its id {{parent}}:20261003 and its 09:15", child)
    ins = _one("SELECT week_start, week_end FROM insights WHERE id = %s", ids["insight"])
    check((ins.get("week_start"), ins.get("week_end")) == (date(2026, 11, 9), date(2026, 11, 15)),
          f"migration ({label}): the weekly insight bounds become 2026-11-09 to 2026-11-15", ins)
    ins = _one("SELECT month_start, month_end FROM insights WHERE id = %s", ids["insight_m"])
    check((ins.get("month_start"), ins.get("month_end")) == (date(2026, 10, 1), date(2026, 10, 31)),
          f"migration ({label}): the monthly insight bounds become 2026-10-01 to 2026-10-31", ins)
    tz = _one("SELECT timezone FROM users WHERE id = %s", ids["A"]) if "timezone" in _columns("users") else "no column"
    check(tz == {"timezone": None}, f"migration ({label}): an existing person's timezone is NULL", tz)


def _check_downgraded(ids):
    old = {k: (v[0], TS_TZ) for k, v in NEW_TYPES.items() if k != ("users", "timezone")}
    _check_types("migration (downgrade)", old)
    _check_indexes("migration (downgrade)")
    check("timezone" not in _columns("users"), "migration (downgrade): users.timezone is dropped")
    check("local_job_runs" not in _tables(), "migration (downgrade): local_job_runs is dropped")
    tx = _one("SELECT date FROM transactions WHERE id = %s", ids["tx"]).get("date")
    check(tx == _utc("2026-11-18 23:40:00"), "migration (downgrade): the transaction is 2026-11-18 23:40:00+00 again", tx)
    for key, (start, end) in WANT_BUDGETS_DOWN.items():
        got = _one("SELECT start_date, end_date FROM budgets WHERE id = %s", ids["b_" + key])
        check((got.get("start_date"), got.get("end_date")) == (_utc(start), _utc(end)),
              f"migration (downgrade): budget {key} is {start} to {end} UTC", got)
    goal = _one("SELECT target_date FROM goals WHERE id = %s", ids["goal"]).get("target_date")
    check(goal == _utc("2026-12-25 00:00:00"), "migration (downgrade): the goal target is 2026-12-25 00:00+00 again", goal)
    parent = _one("SELECT recurrence_end_date, recurrence_last_created_date FROM transactions WHERE id = %s", ids["parent"])
    check((parent.get("recurrence_end_date"), parent.get("recurrence_last_created_date"))
          == (_utc("2027-03-03 00:00:00"), _utc("2026-10-03 00:00:00")),
          "migration (downgrade): the recurrence end and pointer are midnight UTC of their days", parent)
    ins = _one("SELECT week_start, week_end FROM insights WHERE id = %s", ids["insight"])
    check((ins.get("week_start"), ins.get("week_end")) == (_utc("2026-11-09 00:00:00"), _utc("2026-11-15 00:00:00")),
          "migration (downgrade): the insight bounds are midnight UTC of their days", ins)
    check(_violates("INSERT INTO budgets (id, book_id, name, period, start_date, end_date, total_budget, status) "
                    "VALUES (%s, %s, 'B', 'custom', '2026-11-02 00:00+00', '2026-11-01 00:00+00', 10, 'active')",
                    str(uuid.uuid4()), ids["book"]) == "CheckViolation",
          "migration (downgrade): dates_ordered still refuses an end before the start")


def _login(c, ids):
    r = c.post("/api/auth/login", json={"email": ids["email"], "password": "secret123"})
    if r.status_code != 200:
        check(False, "migration: A logs in", f"{r.status_code} {r.text[:200]}")
        return None
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def _check_api_shapes(ids):
    import httpx
    c = httpx.Client(base_url=BASE, timeout=60)
    h = _login(c, ids)
    if h is None:
        return
    r = c.get("/api/transactions", headers=h)
    got = {t["id"]: t["date"] for t in r.json()} if r.status_code == 200 else r.text[:200]
    check(isinstance(got, dict) and got.get(ids["tx"]) == "2026-11-18T23:40:00",
          'migration (API): GET /api/transactions returns "date": "2026-11-18T23:40:00"', got)
    r = c.get(f"/api/budgets/{ids['b_custom']}", headers=h)
    got = {k: r.json().get(k) for k in ("start_date", "end_date")} if r.status_code == 200 else r.text[:200]
    check(got == {"start_date": "2026-11-01", "end_date": "2026-12-01"},
          'migration (API): GET /api/budgets/{id} returns "start_date": "2026-11-01", "end_date": "2026-12-01"', got)
    r = c.get(f"/api/goals/{ids['goal']}", headers=h)
    got = r.json().get("target_date") if r.status_code == 200 else r.text[:200]
    check(got == "2026-12-25", 'migration (API): the goal returns "target_date": "2026-12-25"', got)
    r = c.get(f"/api/transactions/{ids['parent']}", headers=h)
    got = (r.json().get("recurrence") or {}) if r.status_code == 200 else r.text[:200]
    check(isinstance(got, dict) and got.get("last_created_date") == "2026-10-03"
          and (got.get("config") or {}).get("end_date") == "2027-03-03",
          'migration (API): the recurring parent returns "last_created_date": "2026-10-03" and end_date "2027-03-03"', got)


def _check_api_round_trip(ids):
    import httpx
    c = httpx.Client(base_url=BASE, timeout=60)
    h = _login(c, ids)
    if h is None:
        return
    r = c.post("/api/transactions", headers=h, json={
        "type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries", "amount": 3,
        "currency": "usd", "date": "2026-11-18T23:40:00Z"})
    got = r.json().get("date") if r.status_code == 200 else r.text[:200]
    check(got == "2026-11-18T23:40:00", 'migration (API): POST /api/transactions with "...T23:40:00Z" returns '
          '"2026-11-18T23:40:00"', got)
    if r.status_code == 200:
        stored = _one("SELECT date FROM transactions WHERE id = %s", r.json()["id"]).get("date")
        check(stored == datetime(2026, 11, 18, 23, 40), "migration (API): it is stored as 2026-11-18 23:40:00", stored)
    r = c.post("/api/transactions", headers=h, json={
        "type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries", "amount": 3,
        "currency": "usd", "date": "2026-11-18T23:50:00+06:30"})
    got = r.json().get("date") if r.status_code == 200 else r.text[:200]
    check(got == "2026-11-18T23:50:00", 'migration (API): a "+06:30" date keeps its clock fields (no conversion)', got)
    r = c.post("/api/budgets", headers=h, json={
        "name": "Nov", "period": "monthly", "start_date": "2026-11-01T00:00:00Z", "currency": "usd", "total_budget": 100,
        "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 100}]})
    got = {k: r.json().get(k) for k in ("start_date", "end_date")} if r.status_code == 200 else r.text[:200]
    check(got == {"start_date": "2026-11-01", "end_date": "2026-11-30"},
          'migration (API): a monthly budget created with "start_date": "2026-11-01T00:00:00Z" returns 2026-11-01 to '
          "2026-11-30", got)
    r = c.post("/api/goals", headers=h, json={"name": "Bike", "target_amount": 50, "goal_type": "savings",
                                              "currency": "usd", "target_date": "2026-12-31T00:00:00Z"})
    got = r.json().get("target_date") if r.status_code == 200 else r.text[:200]
    check(got == "2026-12-31", 'migration (API): a goal created with "2026-12-31T00:00:00Z" returns "2026-12-31"', got)


def section_migration():
    import test_plans as t  # noqa: E402  (alembic helper)
    from plans_subscription_checks import head_revision  # noqa: E402

    head = head_revision()
    tag = uuid.uuid4().hex[:8]
    ids = {k: str(uuid.uuid4()) for k in ("book", "income", "tx", "parent", "goal", "insight", "insight_m",
                                         *("b_" + b for b in SEED_BUDGETS))}
    ids["A"], ids["email"] = f"cd-{tag}-A", f"cd-a-{tag}@example.com"
    ids["child"] = f"{ids['parent']}:20261003"
    with t.connect() as conn:
        check(t.current_revision(conn) == head, "migration: the e2e database starts at head", t.current_revision(conn))
    check(head != BEFORE_DATES, f"migration: head is a revision after {BEFORE_DATES}", head)
    try:
        ok, out = t.alembic("downgrade", BEFORE_DATES)
        check(ok, f"migration: downgrade to {BEFORE_DATES} runs", out)
        if not ok:
            return
        check(_columns("transactions")["date"]["data_type"] == TS_TZ,
              "migration: before the migration transactions.date is timestamptz")
        _seed_old_shape(ids)

        # ---- up
        ok, out = t.alembic("upgrade", "head")
        check(ok, "migration: upgrade head runs on the seeded old shape", out)
        if not ok:
            return
        _check_upgraded(ids, "upgrade")
        _check_api_shapes(ids)

        # ---- down: the UTC labels are back
        ok, out = t.alembic("downgrade", BEFORE_DATES)
        check(ok, "migration: downgrade runs on the migrated data", out)
        if not ok:
            return
        _check_downgraded(ids)

        # ---- up again
        ok, out = t.alembic("upgrade", "head")
        check(ok, "migration: upgrade head runs again", out)
        if ok:
            _check_upgraded(ids, "upgrade again")
            _check_api_round_trip(ids)
    finally:
        ok, out = t.alembic("upgrade", "head")  # whatever happened above, leave the database at head
        with t.connect() as conn:
            check(ok and t.current_revision(conn) == head, "migration: the e2e database is left at head", out)
        db.sql("DELETE FROM users WHERE id = %s", ids["A"])


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
