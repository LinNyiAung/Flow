"""Calendar dates e2e (schema project #4): transaction dates are local date-times with no timezone, calendar dates are
DATE, every person has a timezone. One function per section, called from main() (or only the sections named on the
command line).

Sections:
  schema -- every converted column has its new type and nullability (transactions.date timestamp without time zone;
    recurrence end / last-created, budget start / end, goal target and insight bounds DATE; users.timezone text NULL),
    local_job_runs has its columns, primary key and local_date index, the date indexes are still there and the budget dates_ordered
    CHECK still refuses an end before the start (Task 1).
  migration -- the calendar dates migration on rows seeded in the old shape (fake-UTC timestamptz): upgrade keeps every
    date and time (a transaction at 23:40 stays 23:40 on the same day, a budget ending at 00:00 keeps its date and a
    budget ending at 23:59:59.999 keeps its date, a start time that isn't midnight widens to its day, goal targets,
    recurrence pointers and insight bounds keep their day, recurring child ids are untouched); downgrade puts the UTC
    labels back (a budget end as 23:59:59.999999 of its day, the recurrence pointer at the parent's time, every other
    date as midnight UTC); up again works; the API
    returns the new shapes and an old-style "...Z" input keeps its clock fields (Task 1). Needs the stub server on
    127.0.0.1:8765.
  header -- the X-Timezone header: a new person's zone is NULL until their first header; a valid IANA name is saved and
    kept by later requests without the header; "Mars/Base", "", "+07:00" and a 70-character value are ignored with a
    200; a failing save never fails the request (Task 2). Needs the stub server.
  today -- each person's "today" comes from their own zone: the custom-insight range may end on the person's today but
    not the day after, a "week" report covers the person's own week and the quota week resets at the person's local
    midnight; a NULL zone behaves as Asia/Yangon; the old report timezone_offset is ignored; pinned instants check the
    same rules where Tokyo and Yangon are on different days (Task 2). The stub has no clock override, so the HTTP checks
    compare with "today" computed from the real clock in each zone, and Pacific/Kiritimati (UTC+14) against
    Etc/GMT+12 (UTC-12), which are never on the same day, makes the difference visible on every run. Needs the stub.
  family -- owner in Asia/Yangon, member in Asia/Tokyo: the member's "2026-11-18T23:40:00" entry reads back the same
    for the owner; the family book's zone is the owner's, and the new owner's after ownership passes (Task 2). Needs
    the stub.
  ticks -- the 15-minute tick (local_jobs.run_due_local_jobs, driven in-process at chosen instants, its subjects
    narrowed to this section's people): a Yangon person's 7-days-left goal reminder is not sent at 08:50, sent once at
    09:05 and not again at 09:20; a zone change to Asia/Tokyo after the Yangon run brings no second run that day; a
    handler that raises releases its claim and the next tick sends the reminder; a claim that raises is logged, runs
    nothing for that subject and the rest of the tick goes on; a book that already has the period's real weekly /
    monthly insight gets no second one from the tick (deploy day); an America/New_York person gets
    exactly one 09:00 run on the 2027-03-14 spring-forward day; a NULL-zone person's budget rolls over at the 00:30
    Yangon tick, not before (Task 3). Needs the stub (people are made over HTTP).
  family_jobs -- owner in Asia/Yangon, member in Asia/Tokyo: the family budget rolls over at the owner's 00:30, not
    the member's; a family goal's reminder reaches the member alone in Tokyo's 09:00 tick (Tokyo's day count) and the
    owner in Yangon's; the weekly family insight is generated once, at the owner's Monday 05:00 (Task 3). A
    Pacific/Honolulu member, whose 09:00 is already the owner's next day, gets the reminder counted from the member's
    own today; when ownership passes west (Yangon -> Kolkata) the book's 00:30 rollover runs nothing again for a local
    date the old owner already ran and runs once at the new owner's next 00:30; a family budget's stored status is on
    the owner's day and moves when ownership passes (UTC-12 -> Kiritimati) (final fixes). Needs the stub.
  plan_dates -- a plan renewal reminder shows the plan's end date on the recipient's calendar (a Kiritimati person's
    date, not the default zone's) (Task 3). Needs the stub.
  split -- the insight jobs have their own 15-minute tick: the scheduler's two ticks split LOCAL_JOBS, and the daily
    tick sends a 09:05 reminder while an insight tick is still waiting on its AI call. Needs the stub.
"""
import asyncio
import os
import sys
import uuid
from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo

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
    ("users", "timezone_changed_at"): ("YES", TS_TZ),
}
NEW_USER_COLUMNS = (("users", "timezone"), ("users", "timezone_changed_at"))  # added by the migration
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
    gone = {"ending_soon_notified", "ending_soon_notified_at"} & set(_columns("budgets"))
    check(not gone, "schema: budgets no longer has the unused ending_soon_notified(_at) columns (e7c2f9a4b815)", gone)

    if "local_job_runs" not in _tables():
        check(False, "schema: the local_job_runs table exists", "missing")
    else:
        cols = _columns("local_job_runs")
        got = {c: (r["is_nullable"], r["data_type"]) for c, r in cols.items()}
        want = {"job": ("NO", TEXT), "subject_id": ("NO", TEXT), "local_date": ("NO", DATE), "claimed_at": ("NO", TS_TZ),
                "done_at": ("YES", TS_TZ)}
        check(got == want, "schema: local_job_runs has exactly job, subject_id, local_date, claimed_at, done_at", got)
        check("now()" in (cols.get("claimed_at", {}).get("column_default") or ""),
              "schema: local_job_runs.claimed_at defaults to now()", cols.get("claimed_at"))
        pk = db.sql("SELECT c.conname, array_agg(a.attname ORDER BY k.n) AS cols FROM pg_constraint c "
                    "CROSS JOIN LATERAL unnest(c.conkey) WITH ORDINALITY AS k(attnum, n) "
                    "JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum "
                    "WHERE c.conrelid = 'local_job_runs'::regclass AND c.contype = 'p' GROUP BY c.conname")
        check(len(pk) == 1 and pk[0]["conname"] == "pk_local_job_runs"
              and list(pk[0]["cols"]) == ["job", "subject_id", "local_date"],
              "schema: local_job_runs' primary key is (job, subject_id, local_date)", pk)
        idx = db.sql("SELECT indexdef FROM pg_indexes WHERE tablename = 'local_job_runs' "
                     "AND indexname = 'ix_local_job_runs_local_date'")
        check(len(idx) == 1 and idx[0]["indexdef"].endswith("(local_date)"),
              "schema: local_job_runs has ix_local_job_runs_local_date on (local_date) (the tick's claimed_since and "
              "forget_before filter on it)", idx)
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
    check("local_job_runs" in _tables() and "ix_local_job_runs_local_date" in _indexes("local_job_runs"),
          f"migration ({label}): local_job_runs exists, with its local_date index")
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
    tz = (_one("SELECT timezone, timezone_changed_at FROM users WHERE id = %s", ids["A"])
          if {"timezone", "timezone_changed_at"} <= set(_columns("users")) else "no column")
    check(tz == {"timezone": None, "timezone_changed_at": None},
          f"migration ({label}): an existing person's timezone and timezone_changed_at are NULL", tz)


def _check_downgraded(ids):
    old = {k: (v[0], TS_TZ) for k, v in NEW_TYPES.items() if k not in NEW_USER_COLUMNS}
    _check_types("migration (downgrade)", old)
    _check_indexes("migration (downgrade)")
    check(not {"timezone", "timezone_changed_at"} & set(_columns("users")),
          "migration (downgrade): users.timezone and users.timezone_changed_at are dropped")
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
          == (_utc("2027-03-03 00:00:00"), _utc("2026-10-03 09:15:00")),
          "migration (downgrade): the recurrence end is midnight UTC of its day; the last-created pointer is its day at "
          "the parent's time (09:15 UTC), so the old code keeps creating occurrences at 09:15", parent)
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
    r = c.post("/api/transactions", headers=h, json={
        "type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries", "amount": 3,
        "currency": "usd", "date": "2026-11-18T23:59:59.500"})
    last = r.json().get("id") if r.status_code == 200 else None
    found = {}
    for end in ("2026-11-18", "2026-11-17"):
        r = c.get("/api/transactions", headers=h, params={"start_date": "2026-11-17", "end_date": end, "limit": 200})
        found[end] = (last in {t["id"] for t in r.json()}) if r.status_code == 200 else f"{r.status_code} {r.text[:200]}"
    check(last is not None and found == {"2026-11-18": True, "2026-11-17": False},
          'migration (API): the list filter with end_date "2026-11-18" (a day, as the app sends it) includes an entry '
          "at 23:59:59.500 that day; one ending the 17th doesn't", (last, found))
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


# ---------------------------------------------------------------------------------------------- people over HTTP
TZ_HEADER = "X-Timezone"
FAMILY = {"X-Book": "family"}


def _backend_async(coro_fn):
    """Run backend async code in-process (its DB engine binds to the loop: one asyncio.run per call, a fresh engine)."""
    async def go():
        from sql import db as sqldb
        try:
            return await coro_fn()
        finally:
            await sqldb.dispose_engine()
    return asyncio.run(go())


def _client():
    import httpx
    return httpx.Client(base_url=BASE, timeout=60)


def _person(c, made, label, plan="free", zone=None):
    """A verified account (id, email, h: the auth header), on `plan`; `zone` is sent once as X-Timezone (None: never)."""
    tag = uuid.uuid4().hex[:8]
    email = f"cd-{label.lower()}-{tag}@example.com"
    c.post("/api/auth/register", json={"name": label, "email": email, "password": "secret123"})
    db.sql("UPDATE users SET is_verified = true WHERE lower(email) = %s", email)
    row = _one("SELECT id FROM users WHERE lower(email) = %s", email)
    made.append(row.get("id"))
    if plan != "free":
        db.sql("UPDATE users SET subscription_type = %s, subscription_expires_at = now() + interval '30 days', "
               "trial_ends_at = NULL WHERE id = %s", plan, row.get("id"))
    r = c.post("/api/auth/login", json={"email": email, "password": "secret123"})
    p = {"id": row.get("id"), "email": email, "h": {"Authorization": f"Bearer {r.json().get('access_token')}"}}
    if zone is not None:
        c.get("/api/auth/me", headers={**p["h"], TZ_HEADER: zone})
    return p


def _stored_zone(p):
    return _one("SELECT timezone FROM users WHERE id = %s", p["id"]).get("timezone", "no row")


def _changed_at(p):
    try:
        return _one("SELECT timezone_changed_at FROM users WHERE id = %s", p["id"]).get("timezone_changed_at", "no row")
    except Exception as e:  # noqa: BLE001  (no such column)
        db._pg.rollback()
        return type(e).__name__


def _age_zone_change(p, interval):
    """Move the person's last zone change `interval` (e.g. '25 hours') into the past."""
    try:
        db.sql("UPDATE users SET timezone_changed_at = now() - %s::interval WHERE id = %s", interval, p["id"])
    except Exception:  # noqa: BLE001  (no such column: the checks after this report it)
        pass


def _cleanup(made):
    made = [m for m in made if m]
    if made:
        db.sql("DELETE FROM families WHERE id IN (SELECT family_id FROM family_members WHERE user_id = ANY(%s))", made)
        db.sql("DELETE FROM users WHERE id = ANY(%s)", made)


# ---------------------------------------------------------------------------------------------------------- header
def section_header():
    c, made = _client(), []
    try:
        p = _person(c, made, "Header")
        r = c.get("/api/auth/me", headers=p["h"])
        check(r.status_code == 200 and _stored_zone(p) is None,
              "header: a new person's timezone is NULL until their first header", (r.status_code, _stored_zone(p)))
        r = c.get("/api/auth/me", headers={**p["h"], TZ_HEADER: "Asia/Tokyo"})
        check(r.status_code == 200 and _stored_zone(p) == "Asia/Tokyo",
              "header: GET /api/auth/me with X-Timezone: Asia/Tokyo saves Asia/Tokyo", (r.status_code, _stored_zone(p)))
        r = c.get("/api/auth/me", headers=p["h"])
        check(r.status_code == 200 and _stored_zone(p) == "Asia/Tokyo",
              "header: a later request without the header keeps Asia/Tokyo", (r.status_code, _stored_zone(p)))
        for label, value in (("Mars/Base", "Mars/Base"), ('""', ""), ("+07:00", "+07:00"),
                             ("a 70-character value", "Asia/" + "x" * 65), ("a path", "../../etc/passwd")):
            r = c.get("/api/auth/me", headers={**p["h"], TZ_HEADER: value})
            check(r.status_code == 200 and _stored_zone(p) == "Asia/Tokyo",
                  f"header: X-Timezone {label} gives 200 and leaves the stored zone unchanged",
                  (r.status_code, _stored_zone(p)))
        changed = _changed_at(p)
        check(isinstance(changed, datetime) and abs(datetime.now(UTC) - changed) < timedelta(minutes=5),
              "header: saving the first zone records timezone_changed_at", changed)

        # ---- the saved zone changes at most once per 24 hours (a zone-hopping client can't reset day limits early)
        q = _person(c, made, "Hopper", zone=KIRITIMATI)
        first = _changed_at(q)
        check(_stored_zone(q) == KIRITIMATI and first is not None,
              "header: a first zone (NULL before) is always accepted", (_stored_zone(q), first))
        _age_zone_change(q, "1 minute")
        before = _changed_at(q)
        kiri_today = _today_in(KIRITIMATI)
        got = _range_ok(c, q, kiri_today, {TZ_HEADER: MINUS_12})
        check(got is True and _stored_zone(q) == KIRITIMATI and _changed_at(q) == before,
              "header: a different zone 1 minute after the last change is not saved, and that request's today is the "
              "saved zone's (a range ending today in Kiritimati is accepted)", (got, _stored_zone(q), _changed_at(q)))
        r = c.get("/api/transactions", headers={**q["h"], TZ_HEADER: MINUS_12})
        check(r.status_code == 200 and _stored_zone(q) == KIRITIMATI,
              "header: on any other route too", (r.status_code, _stored_zone(q)))
        _age_zone_change(q, "25 hours")
        got = _range_ok(c, q, kiri_today, {TZ_HEADER: MINUS_12})
        after = _changed_at(q)
        check(got is False and _stored_zone(q) == MINUS_12 and isinstance(after, datetime)
              and abs(datetime.now(UTC) - after) < timedelta(minutes=5),
              "header: 25 hours after the last change a new zone is saved (timezone_changed_at = now) and that request "
              "already uses it (the Kiritimati range is refused in UTC-12)", (got, _stored_zone(q), after))

        async def failing_save():
            import logging
            import user_zones
            from sql import users as users_db
            orig, log = users_db.set_timezone, logging.getLogger("user_zones")
            records = []

            class Keep(logging.Handler):
                def emit(self, record):
                    records.append(record.getMessage())

            async def boom(*a, **k):
                raise RuntimeError("database down")
            users_db.set_timezone, keep, log.propagate = boom, Keep(), False
            log.addHandler(keep)
            try:
                user = {"_id": p["id"], "timezone": "Asia/Bangkok"}
                got = await user_zones.remember_timezone(user, "Asia/Tokyo")
            finally:
                users_db.set_timezone, log.propagate = orig, True
                log.removeHandler(keep)
            same = await user_zones.remember_timezone({"_id": p["id"], "timezone": "Asia/Bangkok"}, "Mars/Base")
            return got.get("timezone"), same.get("timezone"), str(user_zones.user_zone(got)), len(records)
        try:
            got = _backend_async(failing_save)
        except Exception as e:  # noqa: BLE001
            got = repr(e)[:300]
        check(got == ("Asia/Tokyo", "Asia/Bangkok", "Asia/Tokyo", 1),
              "header: a failing save is logged, never raised, and the request still uses the header's zone; an "
              "invalid name keeps the stored one", got)
        check(_stored_zone(p) == "Asia/Tokyo", "header: the failed save stored nothing", _stored_zone(p))
    finally:
        _cleanup(made)


# ----------------------------------------------------------------------------------------------------------- today
PINNED = datetime(2026, 11, 22, 15, 30, tzinfo=UTC)  # Sunday 22nd 22:00 in Yangon, Monday 23rd 00:30 in Tokyo
TOKYO, YANGON = ZoneInfo("Asia/Tokyo"), ZoneInfo("Asia/Yangon")
KIRITIMATI, MINUS_12 = "Pacific/Kiritimati", "Etc/GMT+12"  # UTC+14 and UTC-12: never on the same calendar day


def _today_in(zone):
    return datetime.now(UTC).astimezone(ZoneInfo(zone)).date()


def _range_ok(c, p, end, extra=None):
    """True when the custom-insight range ending `end` passes the range check (a Free person then gets 403
    plan_feature_locked), False when it is refused as custom_insight_invalid_range, else the response."""
    body = {"start_date": (end - timedelta(days=13)).isoformat(), "end_date": end.isoformat()}
    r = c.post("/api/custom-insights", headers={**p["h"], **(extra or {})}, json=body)
    detail = r.json().get("detail") if r.headers.get("content-type", "").startswith("application/json") else None
    code = detail.get("code") if isinstance(detail, dict) else None
    if r.status_code == 403 and code == "plan_feature_locked":
        return True
    if r.status_code == 422 and code == "custom_insight_invalid_range":
        return False
    return f"{r.status_code} {r.text[:200]}"


def _week_report(c, p, extra=None):
    r = c.post("/api/reports/generate", headers=p["h"], json={"period": "week", "currency": "usd", **(extra or {})})
    if r.status_code != 200:
        return f"{r.status_code} {r.text[:200]}"
    return r.json()["start_date"], r.json()["end_date"]


def _week_of(today):
    monday = today - timedelta(days=today.weekday())
    return f"{monday.isoformat()}T00:00:00", f"{(monday + timedelta(days=6)).isoformat()}T23:59:59.999999"


def _weekly_resets_at(c, p):
    """The resets_at of the person's weekly counted features in GET /api/plan (as aware datetimes, one per feature)."""
    r = c.get("/api/plan", headers=p["h"])
    if r.status_code != 200:
        return f"{r.status_code} {r.text[:200]}"
    return {f: datetime.fromisoformat(v["resets_at"]) for f, v in r.json()["features"].items()
            if v.get("mode") == "counted" and v.get("period") == "week"}


def _next_monday_midnight(zone):
    today = _today_in(zone)
    monday = today - timedelta(days=today.weekday()) + timedelta(days=7)
    return datetime.combine(monday, datetime.min.time(), tzinfo=ZoneInfo(zone)).astimezone(UTC)


def section_today():
    c, made = _client(), []
    try:
        people = {
            "tokyo": _person(c, made, "Tokyo", zone="Asia/Tokyo"),
            "yangon": _person(c, made, "Yangon", zone="Asia/Yangon"),
            "null": _person(c, made, "Nullzone"),
            "kiri": _person(c, made, "Kiri", zone=KIRITIMATI),
            "minus12": _person(c, made, "Minus", zone=MINUS_12),
        }
        zone_of = {"tokyo": "Asia/Tokyo", "yangon": "Asia/Yangon", "null": "Asia/Yangon", "kiri": KIRITIMATI,
                   "minus12": MINUS_12}
        check(_stored_zone(people["null"]) is None, "today: the NULL-zone person really has no saved zone",
              _stored_zone(people["null"]))

        # ---- the custom-insight range may end on the person's today, not the day after
        for key, p in people.items():
            today = _today_in(zone_of[key])
            got = (_range_ok(c, p, today), _range_ok(c, p, today + timedelta(days=1)))
            check(got == (True, False), f"today: a range ending today in {zone_of[key]} ({today}) is accepted for the "
                  f"{key} person and one ending the day after is refused", got)
        kiri_today = _today_in(KIRITIMATI)
        got = (_range_ok(c, people["kiri"], kiri_today), _range_ok(c, people["minus12"], kiri_today))
        check(got == (True, False), f"today: a range ending {kiri_today} (today in Kiritimati) is accepted for the "
              "Kiritimati person and refused for the UTC-12 person", got)
        tokyo_today = _today_in("Asia/Tokyo")
        yangon_accepts = tokyo_today <= _today_in("Asia/Yangon")
        got = (_range_ok(c, people["tokyo"], tokyo_today), _range_ok(c, people["yangon"], tokyo_today),
               _range_ok(c, people["null"], tokyo_today))
        check(got == (True, yangon_accepts, yangon_accepts),
              f"today: a range ending today in Tokyo ({tokyo_today}) is accepted for the Tokyo person and "
              f"{'accepted' if yangon_accepts else 'refused'} for the Yangon and NULL-zone people (Yangon is on "
              f"{_today_in('Asia/Yangon')})", got)
        # The header's zone is used by the very request that brings it (once the 24-hour change limit allows it).
        switch = _person(c, made, "Switch", zone=MINUS_12)
        before = _range_ok(c, switch, kiri_today)
        _age_zone_change(switch, "25 hours")
        got = (before, _range_ok(c, switch, kiri_today, {TZ_HEADER: KIRITIMATI}), _stored_zone(switch))
        check(got == (False, True, KIRITIMATI), "today: a request that brings a new zone already uses it", got)

        # ---- a "week" report covers the person's own week
        for key, p in people.items():
            got = _week_report(c, p)
            want = _week_of(_today_in(zone_of[key]))
            check(got == want, f"today: the week report of the {key} person covers the week of today in "
                  f"{zone_of[key]}", (got, want))
        got = _week_report(c, people["yangon"], {"timezone_offset": -840})
        check(got == _week_of(_today_in("Asia/Yangon")),
              "today: an old app's report timezone_offset is ignored (the person's zone decides)", got)

        # ---- the quota week resets at the person's local midnight
        for key, p in people.items():
            got = _weekly_resets_at(c, p)
            want = _next_monday_midnight(zone_of[key])
            check(isinstance(got, dict) and got and all(v == want for v in got.values()),
                  f"today: the {key} person's weekly quota resets at Monday 00:00 in {zone_of[key]} ({want})", got)

        # ---- the same rules at a pinned instant where Tokyo and Yangon are on different days
        async def pinned():
            from plans import periods
            from report_models import ReportPeriod
            from report_routes import calculate_report_dates
            from tz_utils import local_midnight_utc
            out = {
                "week_start": (periods.period_start("week", PINNED, TOKYO), periods.period_start("week", PINNED, YANGON)),
                "week_reset": (periods.resets_at("week", PINNED, TOKYO), periods.resets_at("week", PINNED, YANGON)),
                "report": (calculate_report_dates(ReportPeriod.WEEK, None, None, TOKYO, now=PINNED)[0],
                           calculate_report_dates(ReportPeriod.WEEK, None, None, YANGON, now=PINNED)[0]),
                "midnight": (local_midnight_utc(date(2026, 11, 30), TOKYO), local_midnight_utc(date(2026, 11, 23), YANGON)),
            }
            return out
        try:
            got = _backend_async(pinned)
        except Exception as e:  # noqa: BLE001
            got = {"error": repr(e)[:300]}
        check(got.get("week_start") == (date(2026, 11, 23), date(2026, 11, 16)),
              "today (pinned 2026-11-22 15:30 UTC): the quota week is the 23rd's in Tokyo and the 16th's in Yangon",
              got.get("week_start", got))
        check(got.get("week_reset") == got.get("midnight") and got.get("midnight") == (
            datetime(2026, 11, 29, 15, 0, tzinfo=UTC), datetime(2026, 11, 22, 17, 30, tzinfo=UTC)),
              "today (pinned): the quota week resets at Tokyo midnight (local_midnight_utc) for Tokyo, Yangon "
              "midnight for Yangon", got.get("week_reset", got))
        check(got.get("report") == (datetime(2026, 11, 23), datetime(2026, 11, 16)),
              "today (pinned): a week report starts Monday the 23rd in Tokyo and Monday the 16th in Yangon",
              got.get("report", got))

        # ---- the custom-insight failed-attempts window is a rolling 24 hours, the same in every zone
        hopper = people["kiri"]
        book = _one("SELECT id FROM books WHERE person_id = %s", hopper["id"]).get("id")
        start, end = date(2026, 11, 1), date(2026, 11, 14)
        for hours in (23, 25):
            db.sql("INSERT INTO custom_insights (id, book_id, start_date, end_date, status, created_at) "
                   "VALUES (%s, %s, %s, %s, 'failed', now() - %s::interval)",
                   str(uuid.uuid4()), book, start, end, f"{hours} hours")

        async def rolling():
            import custom_insights_service as cis
            from sql import custom_insights as ci
            now = datetime.now(UTC)
            t = [now - timedelta(hours=h) for h in (20, 10, 5, 3, 1)]
            try:
                reset = cis.attempts_reset_at(t)
                reset6 = cis.attempts_reset_at([now - timedelta(hours=22)] + t)
            except Exception as e:  # noqa: BLE001  (the old signature)
                reset = reset6 = repr(e)[:120]
            return {"start": (cis.attempts_window_start(now), now),
                    "count": await ci.count_attempts_since(book, cis.attempts_window_start(now)),
                    "reset": (reset, t[0] + timedelta(hours=24)), "reset6": (reset6, t[0] + timedelta(hours=24))}
        try:
            got = _backend_async(rolling)
        except Exception as e:  # noqa: BLE001
            got = {"error": repr(e)[:300]}
        start_now = got.get("start")
        check(bool(start_now) and start_now[0] == start_now[1] - timedelta(hours=24),
              "today: the custom-insight attempt window starts 24 hours ago (no zone involved)", got)
        check(got.get("count") == 1, "today: a failed attempt 23 hours ago counts and one 25 hours ago doesn't",
              got.get("count", got))
        check(got.get("reset", (0, 1))[0] == got.get("reset", (0, 1))[1]
              and got.get("reset6", (0, 1))[0] == got.get("reset6", (0, 1))[1],
              "today: the limit lifts 24 hours after the oldest attempt that keeps it reached (5 attempts: the oldest; "
              "6: the second oldest)", (got.get("reset"), got.get("reset6")))
    finally:
        _cleanup(made)


# ---------------------------------------------------------------------------------------------------------- family
def section_family():
    c, made = _client(), []
    try:
        owner = _person(c, made, "Owner", plan="plus", zone="Asia/Yangon")
        member = _person(c, made, "Member", zone="Asia/Tokyo")
        r = c.post("/api/family", headers=owner["h"], json={"name": f"Zones {uuid.uuid4().hex[:6]}"})
        fid = ((r.json() if r.status_code == 200 else {}).get("family") or {}).get("id")
        check(fid is not None, "family: the owner creates a family", f"{r.status_code} {r.text[:200]}")
        if not fid:
            return
        book_id = _one("SELECT id FROM books WHERE family_id = %s", fid).get("id")
        r = c.post("/api/family/invites", headers=owner["h"], json={"email": member["email"]})
        invites = c.get("/api/family/invites/mine", headers=member["h"]).json().get("invites", [])
        inv = next((i for i in invites if i.get("family_id", fid) == fid), None)
        r = c.post(f"/api/family/invites/{inv['id']}/accept", headers=member["h"]) if inv else r
        check(inv is not None and r.status_code == 200, "family: the member joins", f"{r.status_code} {r.text[:200]}")

        r = c.post("/api/transactions", headers={**member["h"], **FAMILY}, json={
            "type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries", "amount": 4,
            "currency": "usd", "date": "2026-11-18T23:40:00"})
        tx = r.json().get("id") if r.status_code == 200 else None
        check(tx is not None and r.json().get("date") == "2026-11-18T23:40:00",
              'family: the Tokyo member posts "2026-11-18T23:40:00" and gets it back', f"{r.status_code} {r.text[:200]}")
        r = c.get("/api/transactions", headers={**owner["h"], **FAMILY})
        got = {t["id"]: t["date"] for t in r.json()}.get(tx) if r.status_code == 200 else r.text[:200]
        check(got == "2026-11-18T23:40:00", 'family: the Yangon owner reads it as "2026-11-18T23:40:00"', got)
        got = _one("SELECT date FROM transactions WHERE id = %s", tx).get("date")
        check(got == datetime(2026, 11, 18, 23, 40), "family: it is stored as 2026-11-18 23:40:00", got)

        async def zone():
            import user_zones
            return str(await user_zones.book_zone(book_id))
        try:
            got = _backend_async(zone)
        except Exception as e:  # noqa: BLE001
            got = repr(e)[:300]
        check(got == "Asia/Yangon", "family: the family book's zone is the owner's (Asia/Yangon)", got)
        members = c.get("/api/family", headers=member["h"]).json().get("members", [])
        mid = next((m["id"] for m in members if m.get("is_me")), None)
        r = c.post("/api/family/transfer-ownership", headers=owner["h"], json={"member_id": mid})
        check(r.status_code == 200, "family: ownership passes to the Tokyo member", f"{r.status_code} {r.text[:200]}")
        try:
            got = _backend_async(zone)
        except Exception as e:  # noqa: BLE001
            got = repr(e)[:300]
        check(got == "Asia/Tokyo", "family: the family book's zone is now the new owner's (Asia/Tokyo)", got)

        # The chat's cached documents ("TODAY", "N days ago", days remaining) are per book AND per member zone.
        async def chat_cache():
            from ai_chatbot import BookVectorStoreCache, FinancialChatbot
            cache, built = BookVectorStoreCache(), []

            def builder(tag):
                async def build():
                    built.append(tag)
                    return object()
                return build
            got = []
            for tag, zone in (("yangon", YANGON), ("tokyo", TOKYO), ("yangon again", YANGON)):
                store, release = await cache.acquire(book_id, builder(tag), zone)
                got.append(store)
                release()
            dropped = cache.invalidate(book_id)
            store, release = await cache.acquire(book_id, builder("after invalidate"), TOKYO)
            release()
            bot, zones = FinancialChatbot.__new__(FinancialChatbot), []
            bot.book_vector_stores = BookVectorStoreCache()

            async def fake_build(bid, tz):
                zones.append(str(tz))
                return object()
            bot._build_vector_store = fake_build
            _, release = await bot._get_or_create_vector_store(book_id, TOKYO)
            release()
            return built, got[0] is got[2], got[0] is not got[1], dropped, zones
        try:
            got = _backend_async(chat_cache)
        except Exception as e:  # noqa: BLE001
            got = repr(e)[:300]
        check(got == (["yangon", "tokyo", "after invalidate"], True, True, True, ["Asia/Tokyo"]),
              "family: the chat's cached documents are built once per member zone (a Tokyo member gets Tokyo's "
              "TODAY on a Yangon-owned book), invalidating the book drops every zone's store, and the chatbot builds "
              "them in the zone it is given (the asker's)", got)

        async def edges():
            import user_zones
            personal = _one("SELECT id FROM books WHERE person_id = %s", member["id"]).get("id")
            return (str(await user_zones.book_zone(personal)), str(await user_zones.book_zone("no-such-book")),
                    str(user_zones.user_zone({"timezone": None})), str(user_zones.user_zone({"timezone": "Mars/Base"})))
        try:
            got = _backend_async(edges)
        except Exception as e:  # noqa: BLE001
            got = repr(e)[:300]
        check(got == ("Asia/Tokyo", "Asia/Yangon", "Asia/Yangon", "Asia/Yangon"),
              "family: a personal book's zone is its person's; a missing book, a NULL zone and an unknown name give "
              "the default zone", got)
    finally:
        _cleanup(made)


# ----------------------------------------------------------------------------------------------------------- ticks
NEW_YORK = ZoneInfo("America/New_York")


def _at(day, hh, mm, zone):
    """The instant `day` hh:mm on the wall clock of `zone`, as an aware UTC datetime."""
    return datetime(day.year, day.month, day.day, hh, mm, tzinfo=zone).astimezone(UTC)


def _ticks(nows, people=(), books=(), probe=None, flaky=None, logs=None, flaky_claim=None):
    """run_due_local_jobs at each instant of `nows` (one event loop), its subjects narrowed to these people and books:
    [(run counts, probe())] per tick (probe: a sync read after each tick). flaky: the id of a job whose handler raises
    on its first call. flaky_claim: a (job id, subject id) whose first claim raises (a database error while claiming).
    logs: a list that collects (instead of printing) what local_jobs logs. An error: its repr."""
    async def go():
        import logging
        import local_jobs
        from sql import local_job_runs as runs_db
        stubenv.patch_loaded_modules()
        orig_p, orig_b, orig_claim = runs_db.person_subjects, runs_db.book_subjects, runs_db.claim
        claims = []

        async def only_people():
            return [s for s in await orig_p() if s[0] in people]

        async def only_books():
            return [s for s in await orig_b() if s[0] in books]

        async def claim_fails_once(job_id, subject_id, local_date):
            if (job_id, subject_id) == flaky_claim and not claims:
                claims.append(subject_id)
                raise RuntimeError("database down while claiming")
            return await orig_claim(job_id, subject_id, local_date)
        if flaky_claim:
            runs_db.claim = claim_fails_once
        job = next((j for j in local_jobs.LOCAL_JOBS if j.id == flaky), None)
        orig_handler = job.handler if job else None
        calls = []

        async def raises_once(subject_id, today, tz):
            calls.append(subject_id)
            if len(calls) == 1:
                raise RuntimeError("handler fails once")
            return await orig_handler(subject_id, today, tz)
        class Keep(logging.Handler):
            def emit(self, record):
                logs.append(record.getMessage())
        log, keep = logging.getLogger("local_jobs"), Keep()
        if logs is not None:
            log.addHandler(keep)
            log.propagate = False
        runs_db.person_subjects, runs_db.book_subjects = only_people, only_books
        if job:
            job.handler = raises_once
        try:
            out = []
            for now in nows:
                counts = await local_jobs.run_due_local_jobs(now=now)
                out.append((counts, probe() if probe else None))
            return out
        finally:
            runs_db.person_subjects, runs_db.book_subjects, runs_db.claim = orig_p, orig_b, orig_claim
            log.removeHandler(keep)
            log.propagate = True
            if job:
                job.handler = orig_handler
    try:
        return _backend_async(go)
    except Exception as e:  # noqa: BLE001
        return repr(e)[:300]


def _runs(ticks, job_id):
    """How many times `job_id` ran in each tick of a _ticks result (None when the ticks failed)."""
    return [t[0].get(job_id) for t in ticks] if isinstance(ticks, list) else None


def _probes(ticks):
    return [t[1] for t in ticks] if isinstance(ticks, list) else ticks


def _reminders(p, goal_id):
    return db.sql("SELECT message, reminder_threshold, book_id FROM notifications WHERE user_id = %s "
                  "AND type = 'goal_approaching_date' AND goal_id = %s", p["id"], goal_id)


def _goal(c, p, target, family=False):
    r = c.post("/api/goals", headers={**p["h"], **(FAMILY if family else {})},
               json={"name": f"Goal {uuid.uuid4().hex[:6]}", "target_amount": 1000, "goal_type": "savings",
                     "currency": "usd", "target_date": target.isoformat()})
    return r.json().get("id") if r.status_code == 200 else f"{r.status_code} {r.text[:200]}"


def _claimed(job, subject, day):
    return bool(db.sql("SELECT 1 FROM local_job_runs WHERE job = %s AND subject_id = %s AND local_date = %s",
                       job, subject, day))


def _finished_budget(book_id, end, label):
    """An auto-create (no AI) monthly budget of the book whose last day is `end`; its id."""
    bid = f"cd-roll-{label}-{uuid.uuid4().hex[:6]}"
    now = datetime.now(UTC)
    db.budgets.insert_one({
        "_id": bid, "book_id": book_id, "name": f"Roll {label}", "period": "custom", "currency": "usd",
        "start_date": end - timedelta(days=6), "end_date": end,
        "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 50, "spent_amount": 0,
                              "percentage_used": 0, "is_exceeded": False}],
        "total_budget": 50, "total_spent": 0, "remaining_budget": 50, "percentage_used": 0,
        "status": "completed", "is_active": False, "auto_create_enabled": True, "auto_create_with_ai": False,
        "created_at": now, "updated_at": now})
    return bid


def _children(parent_id):
    return db.sql("SELECT count(*) n FROM budgets WHERE parent_budget_id = %s", parent_id)[0]["n"]


def _book_of(p):
    return _one("SELECT id FROM books WHERE person_id = %s", p["id"]).get("id")


def section_ticks():
    c, made = _client(), []
    try:
        day = _today_in("Asia/Yangon")  # the jobs' own reads (status, rollover period) use the real clock: stay on it
        target = day + timedelta(days=7)

        # ---- once per local day: not before 09:00, once after it, never again that day
        p = _person(c, made, "Tick", zone="Asia/Yangon")
        gid = _goal(c, p, target)
        ticks = _ticks([_at(day, 8, 50, YANGON), _at(day, 9, 5, YANGON), _at(day, 9, 20, YANGON)], people={p["id"]},
                       probe=lambda: len(_reminders(p, gid)))
        check(_probes(ticks) == [0, 1, 1] and _runs(ticks, "goal_deadline_reminders") == [0, 1, 0],
              "ticks: a Yangon person's 7-days-left goal reminder is not sent at 08:50, sent once at 09:05 and not "
              "again at 09:20 (the job runs once)", (_probes(ticks), _runs(ticks, "goal_deadline_reminders")))
        got = _reminders(p, gid)
        check(len(got) == 1 and got[0]["reminder_threshold"] == 7 and "7 days" in got[0]["message"],
              "ticks: it is the 7-day reminder, counted from the person's today", got)
        check(_claimed("goal_deadline_reminders", p["id"], day),
              "ticks: the run is claimed in local_job_runs for (job, person, local date)")

        # ---- a zone change after the day's run brings no second run that day
        db.sql("UPDATE users SET timezone = 'Asia/Tokyo' WHERE id = %s", p["id"])  # 09:30 Yangon = 11:00 Tokyo
        ticks = _ticks([_at(day, 9, 45, YANGON)], people={p["id"]}, probe=lambda: len(_reminders(p, gid)))
        check(_runs(ticks, "goal_deadline_reminders") == [0] and _probes(ticks) == [1],
              "ticks: after the zone changes from Asia/Yangon to Asia/Tokyo (11:00 there, same date) the next tick "
              "runs nothing again", ticks)

        # ---- a failed run releases its claim and the next tick retries it
        q = _person(c, made, "Flaky", zone="Asia/Yangon")
        qid, logs = _goal(c, q, target), []
        ticks = _ticks([_at(day, 9, 5, YANGON), _at(day, 9, 20, YANGON)], people={q["id"]},
                       probe=lambda: (len(_reminders(q, qid)), _claimed("goal_deadline_reminders", q["id"], day)),
                       flaky="goal_deadline_reminders", logs=logs)
        check(_probes(ticks) == [(0, False), (1, True)] and _runs(ticks, "goal_deadline_reminders") == [0, 1],
              "ticks: a handler that raises releases its claim (nothing sent) and the next tick sends the reminder",
              (_probes(ticks), _runs(ticks, "goal_deadline_reminders")))
        check(len(logs) == 1 and "goal_deadline_reminders failed" in logs[0], "ticks: the failure is logged", logs)

        # ---- a claim that fails (a database error) is logged; the rest of the tick goes on and the next tick retries
        a, b = _person(c, made, "Claimfail", zone="Asia/Yangon"), _person(c, made, "Claimok", zone="Asia/Yangon")
        aid, bid, logs = _goal(c, a, target), _goal(c, b, target), []
        ticks = _ticks([_at(day, 9, 5, YANGON), _at(day, 9, 20, YANGON)], people={a["id"], b["id"]},
                       probe=lambda: (len(_reminders(a, aid)), len(_reminders(b, bid)),
                                      _claimed("goal_deadline_reminders", a["id"], day)),
                       flaky_claim=("goal_deadline_reminders", a["id"]), logs=logs)
        check(_probes(ticks) == [(0, 1, False), (1, 1, True)] and _runs(ticks, "goal_deadline_reminders") == [1, 1]
              and _runs(ticks, "budget_ending_reminders") == [2, 0],
              "ticks: a claim that raises runs nothing for that subject (no claim kept), the other person's reminder "
              "and the later jobs of the same tick still run, and the next tick runs the failed one",
              (_probes(ticks), _runs(ticks, "goal_deadline_reminders"), _runs(ticks, "budget_ending_reminders")))
        check(len(logs) == 1 and "claim" in logs[0] and "goal_deadline_reminders" in logs[0],
              "ticks: the failed claim is logged", logs)

        # ---- deploy day: a book that already has this period's real insight (the old cron made it this morning) gets
        # no second one from the tick: no AI call, no new row, no second notice, and the day stays claimed
        ip = _person(c, made, "Insightdup", plan="plus", zone="Asia/Yangon")
        ibook = _book_of(ip)
        _goal(c, ip, target)  # activity: without the guard the tick would write a new insight
        this_monday = day - timedelta(days=day.weekday())
        last_week, last_month_end = this_monday - timedelta(days=7), day.replace(day=1) - timedelta(days=1)
        for kind, start, end in (("week", last_week, last_week + timedelta(days=6)),
                                 ("month", last_month_end.replace(day=1), last_month_end)):
            db.sql(f"INSERT INTO insights (id, book_id, insight_type, ai_provider, content, {kind}_start, {kind}_end) "
                   "VALUES (%s, %s, %s, 'openai', 'made by the old cron', %s, %s)",
                   str(uuid.uuid4()), ibook, f"{kind}ly", start, end)

        def insights_made():
            return (db.sql("SELECT count(*) n FROM insights WHERE book_id = %s", ibook)[0]["n"],
                    db.sql("SELECT count(*) n FROM notifications WHERE user_id = %s AND type IN "
                           "('weekly_insights_generated', 'monthly_insights_generated')", ip["id"])[0]["n"])
        next_monday = this_monday + timedelta(days=7)
        next_first = (day.replace(day=1) + timedelta(days=32)).replace(day=1)
        ticks = _ticks([_at(next_monday, 5, 5, YANGON), _at(next_first, 6, 5, YANGON)], books={ibook},
                       probe=insights_made)
        check(_probes(ticks) == [(2, 0), (2, 0)] and _runs(ticks, "weekly_insights")[0] == 1
              and _runs(ticks, "monthly_insights")[1] == 1
              and _claimed("weekly_insights", ibook, next_monday) and _claimed("monthly_insights", ibook, next_first),
              f"ticks: a book that already has the real weekly insight for {last_week} and the monthly one for "
              f"{last_month_end.replace(day=1)} gets no second one from the Monday 05:00 and 1st 06:00 ticks (no new "
              "row, no notice; the runs count as done and stay claimed)",
              (_probes(ticks), _runs(ticks, "weekly_insights"), _runs(ticks, "monthly_insights")))

        # ---- a NULL-zone person's rollover runs at the 00:30 Yangon tick, not before
        n = _person(c, made, "Rollnull")
        check(_stored_zone(n) is None, "ticks: the rollover person has no saved zone", _stored_zone(n))
        nbook = _book_of(n)
        parent = _finished_budget(nbook, day - timedelta(days=1), "null")
        ticks = _ticks([_at(day, 0, 15, YANGON), _at(day, 0, 35, YANGON)], books={nbook},
                       probe=lambda: _children(parent))
        check(_probes(ticks) == [0, 1] and _runs(ticks, "budget_rollovers") == [0, 1],
              "ticks: a NULL-zone person's finished budget rolls over at the 00:30 Yangon tick, not at 00:15",
              (_probes(ticks), _runs(ticks, "budget_rollovers")))

        # ---- DST: exactly one 09:00 run on the America/New_York spring-forward day (02:00 -> 03:00)
        ny = _person(c, made, "Newyork", zone="America/New_York")
        dst = date(2027, 3, 14)
        nid = _goal(c, ny, dst + timedelta(days=7))
        start = _at(dst, 0, 0, NEW_YORK)
        nows = [start + timedelta(minutes=15 * i) for i in range(int((_at(dst, 12, 0, NEW_YORK) - start)
                                                                     / timedelta(minutes=15)) + 1)]
        ticks = _ticks(nows, people={ny["id"]})
        runs = _runs(ticks, "goal_deadline_reminders")
        first = runs.index(1) if isinstance(runs, list) and 1 in runs else None
        check(isinstance(runs, list) and sum(runs) == 1 and len(nows) == 45
              and nows[first].astimezone(NEW_YORK).strftime("%H:%M") == "09:00",
              "ticks: on 2027-03-14 (spring forward) an America/New_York person's 09:00 job runs exactly once, at "
              "09:00 EDT, across the ticks from 00:00 to 12:00", (runs, len(nows), first))
        check(len(_reminders(ny, nid)) == 1 and _claimed("goal_deadline_reminders", ny["id"], dst),
              "ticks: that run sends the one reminder, claimed for the local date 2027-03-14", _reminders(ny, nid))
        done = db.sql("SELECT done_at FROM local_job_runs WHERE job = 'goal_deadline_reminders' AND subject_id = %s "
                      "AND local_date = %s", ny["id"], dst)
        check(len(done) == 1 and done[0]["done_at"] is not None,
              "ticks: a run that finished is recorded as done (done_at)", done)

        # ---- a crash mid-run: a claim left unfinished is run again by a later tick that day, once it is stale
        cr = _person(c, made, "Crash", zone="Asia/Yangon")
        cid = _goal(c, cr, day + timedelta(days=7))
        key = ("goal_deadline_reminders", cr["id"], day)
        # The process died during the 09:05 run: claimed 40 minutes ago, never finished, nothing sent.
        db.sql("INSERT INTO local_job_runs (job, subject_id, local_date, claimed_at) "
               "VALUES (%s, %s, %s, now() - interval '40 minutes')", *key)
        ticks = _ticks([_at(day, 9, 50, YANGON), _at(day, 10, 5, YANGON)], people={cr["id"]},
                       probe=lambda: len(_reminders(cr, cid)))
        row = db.sql("SELECT done_at FROM local_job_runs WHERE job = %s AND subject_id = %s AND local_date = %s", *key)
        check(_probes(ticks) == [1, 1] and _runs(ticks, "goal_deadline_reminders") == [1, 0]
              and len(row) == 1 and row[0]["done_at"] is not None,
              "ticks: a claim left unfinished by a crash (claimed 40 minutes ago) is run again at the next tick, once, "
              "and then recorded as done", (_probes(ticks), _runs(ticks, "goal_deadline_reminders"), row))

        # ---- but a run still going (claimed a moment ago, not finished) is left alone
        busy = _person(c, made, "Busy", zone="Asia/Yangon")
        bid = _goal(c, busy, day + timedelta(days=7))
        db.sql("INSERT INTO local_job_runs (job, subject_id, local_date) VALUES ('goal_deadline_reminders', %s, %s)",
               busy["id"], day)
        ticks = _ticks([_at(day, 9, 20, YANGON)], people={busy["id"]}, probe=lambda: len(_reminders(busy, bid)))
        check(_probes(ticks) == [0] and _runs(ticks, "goal_deadline_reminders") == [0],
              "ticks: an unfinished claim made a moment ago (a run still going) is not run a second time",
              (_probes(ticks), _runs(ticks, "goal_deadline_reminders")))
    finally:
        _cleanup(made)


# ------------------------------------------------------------------------------------------------------ family jobs
def section_family_jobs():
    c, made = _client(), []
    try:
        owner = _person(c, made, "Fjowner", plan="plus", zone="Asia/Yangon")
        member = _person(c, made, "Fjmember", zone="Asia/Tokyo")
        r = c.post("/api/family", headers=owner["h"], json={"name": f"Jobs {uuid.uuid4().hex[:6]}"})
        fid = ((r.json() if r.status_code == 200 else {}).get("family") or {}).get("id")
        c.post("/api/family/invites", headers=owner["h"], json={"email": member["email"]})
        invites = c.get("/api/family/invites/mine", headers=member["h"]).json().get("invites", [])
        inv = next((i for i in invites if i.get("family_id", fid) == fid), None)
        r = c.post(f"/api/family/invites/{inv['id']}/accept", headers=member["h"]) if inv else r
        book = _one("SELECT id FROM books WHERE family_id = %s", fid).get("id") if fid else None
        check(book is not None and r.status_code == 200, "family_jobs: owner (Yangon) and member (Tokyo) share a "
              "family", f"{r.status_code} {r.text[:200]}")
        if not book:
            return
        people, books = {owner["id"], member["id"]}, {book}
        day = _today_in("Asia/Yangon")

        # ---- the family budget rolls over at the owner's 00:30, not the member's
        parent = _finished_budget(book, day - timedelta(days=1), "family")
        ticks = _ticks([_at(day, 0, 35, TOKYO), _at(day, 0, 35, YANGON)], people=people, books=books,
                       probe=lambda: _children(parent))
        check(_probes(ticks) == [0, 1],
              "family_jobs: the family budget rolls over at the owner's 00:30 (Yangon), not at the member's (Tokyo)",
              (_probes(ticks), _runs(ticks, "budget_rollovers")))

        # ---- a family goal 7 days away for Tokyo at Tokyo 09:00: each member's reminder in their own 09:00 run
        target = day + timedelta(days=7)
        gid = _goal(c, owner, target, family=True)
        ticks = _ticks([_at(day, 9, 5, TOKYO), _at(day, 9, 5, YANGON)], people=people, books=books,
                       probe=lambda: (len(_reminders(member, gid)), len(_reminders(owner, gid))))
        check(_probes(ticks) == [(1, 0), (1, 1)],
              "family_jobs: the member's reminder arrives in the Tokyo 09:00 tick and only to the member; the owner's "
              "in the Yangon 09:00 tick", _probes(ticks) if isinstance(ticks, list) else ticks)
        got = _reminders(member, gid)
        check(len(got) == 1 and got[0]["reminder_threshold"] == 7 and "7 days" in got[0]["message"]
              and got[0]["book_id"] == book,
              "family_jobs: the member's reminder counts 7 days from Tokyo's today and links the family book", got)

        # ---- the weekly family insight: once, at the owner's Monday 05:00
        monday = day + timedelta(days=7 - day.weekday())

        def weekly():
            return db.sql("SELECT count(*) n FROM insights WHERE book_id = %s AND insight_type = 'weekly'", book)[0]["n"]
        before = weekly()
        ticks = _ticks([_at(monday, 5, 5, TOKYO), _at(monday, 5, 5, YANGON), _at(monday, 5, 20, YANGON)],
                       people=people, books=books, probe=lambda: weekly() - before)
        check(_probes(ticks) == [0, 1, 1] and _runs(ticks, "weekly_insights") == [0, 1, 0],
              "family_jobs: the weekly family insight is generated once, at the owner's Monday 05:00 (not at the "
              "member's)", (_probes(ticks), _runs(ticks, "weekly_insights")))

        # ---- a member whose 09:00 is already the owner's next day: the reminder counts from the member's today
        # (a member ahead of Yangon can't show this: Kiritimati's 09:00 is 01:30 the same day in Yangon)
        honolulu = ZoneInfo("Pacific/Honolulu")  # UTC-10: 09:05 there is 01:35 the next day in Yangon
        db.sql("UPDATE users SET timezone = 'Pacific/Honolulu' WHERE id = %s", member["id"])
        mday = day + timedelta(days=1)
        at = _at(mday, 9, 5, honolulu)
        gid2 = _goal(c, owner, mday + timedelta(days=7), family=True)
        ticks = _ticks([at], people=people, probe=lambda: (_reminders(member, gid2), len(_reminders(owner, gid2))))
        got = _probes(ticks)
        mine = got[0][0] if isinstance(got, list) else []
        check(at.astimezone(YANGON).date() == mday + timedelta(days=1) and len(mine) == 1
              and mine[0]["reminder_threshold"] == 7 and "7 days" in mine[0]["message"] and got[0][1] == 0,
              f"family_jobs: a Pacific/Honolulu member's 09:00 tick on {mday} (already the {mday + timedelta(days=1)} "
              "for the Yangon owner) sends the member the 7-day reminder of a goal due 7 days after the member's today "
              "(6 after the owner's), and nothing to the owner", got)

        # ---- the same member and a family budget whose last day was yesterday on the owner's (real) clock: at the
        # member's 09:05 on that day it is still their last day, so they get "ends today", though the budget's stored
        # status (refreshed on the owner's clock) is already "completed"
        last = day - timedelta(days=1)
        last_day = _finished_budget(book, last, "lastday")
        db.sql("UPDATE budgets SET status = 'active', is_active = true, auto_create_enabled = false WHERE id = %s",
               last_day)

        def ending(p):
            return db.sql("SELECT message FROM notifications WHERE user_id = %s AND type = 'budget_ending_soon' "
                          "AND budget_id = %s", p["id"], last_day)
        at2 = _at(last, 9, 5, honolulu)
        _ticks([at2], people={member["id"]})
        notes = ending(member)
        check(at2.astimezone(YANGON).date() == day and len(notes) == 1 and "ends today" in notes[0]["message"]
              and not ending(owner),
              f"family_jobs: the Honolulu member gets 'ends today' at their 09:05 on {last}, the budget's last day, "
              f"though on the Yangon owner's clock it is already {day} and the budget is over; the owner gets nothing",
              (notes, ending(owner)))

        # ---- ownership passes west (Yangon -> Kolkata): the book's 00:30 rollover still runs once per local date
        kolkata = ZoneInfo("Asia/Kolkata")  # UTC+5:30, an hour behind Yangon
        d = day + timedelta(days=10)  # clear of the dates the ticks above claimed for the book
        parent2 = _finished_budget(book, d - timedelta(days=1), "transfer")
        before = _ticks([_at(d - timedelta(days=1), 0, 35, YANGON), _at(d, 0, 35, YANGON)], books=books,
                        probe=lambda: _children(parent2))
        mid = next((m["id"] for m in c.get("/api/family", headers=member["h"]).json().get("members", [])
                    if m.get("is_me")), None)
        db.sql("UPDATE users SET timezone = 'Asia/Kolkata' WHERE id = %s", member["id"])
        r = c.post("/api/family/transfer-ownership", headers=owner["h"], json={"member_id": mid})
        check(r.status_code == 200, "family_jobs: ownership passes to the member (now in Asia/Kolkata)",
              f"{r.status_code} {r.text[:200]}")
        after = _ticks([_at(d - timedelta(days=1), 23, 50, kolkata), _at(d, 0, 35, kolkata),
                        _at(d + timedelta(days=1), 0, 35, YANGON), _at(d + timedelta(days=1), 0, 35, kolkata)],
                       books=books, probe=lambda: _children(parent2))
        check(_runs(before, "budget_rollovers") == [1, 1] and _probes(before) == [0, 1]
              and _runs(after, "budget_rollovers") == [0, 0, 0, 1] and _probes(after) == [1, 1, 1, 1],
              f"family_jobs: the rollover runs at the Yangon owner's 00:30 on {d - timedelta(days=1)} and {d}; after "
              f"ownership passes to Kolkata, Kolkata's 23:50 on {d - timedelta(days=1)} and 00:35 on {d} run nothing "
              f"again, Yangon's 00:35 on {d + timedelta(days=1)} runs nothing, Kolkata's 00:35 then runs once",
              (_runs(before, "budget_rollovers"), _probes(before), _runs(after, "budget_rollovers"), _probes(after)))

        # ---- the family budget's stored status is on the owner's day, and moves with the ownership
        db.sql("UPDATE users SET timezone = %s WHERE id = %s", MINUS_12, member["id"])  # the owner now
        db.sql("UPDATE users SET timezone = %s WHERE id = %s", KIRITIMATI, owner["id"])
        start = _today_in(KIRITIMATI)  # never yet today in UTC-12
        bid = f"cd-status-{uuid.uuid4().hex[:6]}"
        now = datetime.now(UTC)
        db.budgets.insert_one({
            "_id": bid, "book_id": book, "name": "Status", "period": "custom", "currency": "usd",
            "start_date": start, "end_date": start + timedelta(days=6),
            "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 50, "spent_amount": 0,
                                  "percentage_used": 0, "is_exceeded": False}],
            "total_budget": 50, "total_spent": 0, "remaining_budget": 50, "percentage_used": 0,
            "status": "active", "is_active": True, "auto_create_enabled": False, "created_at": now, "updated_at": now})

        async def stored_status():
            import budget_service as bs
            from sql import budgets as budgets_db
            stubenv.patch_loaded_modules()
            await bs.update_budget_spent_amounts(book, bid, trigger_auto_create=False)
            return (await budgets_db.get_budget(bid, book) or {}).get("status")
        try:
            under_minus12 = _backend_async(stored_status)
            oid = next((m["id"] for m in c.get("/api/family", headers=owner["h"]).json().get("members", [])
                        if m.get("is_me")), None)
            r = c.post("/api/family/transfer-ownership", headers=member["h"], json={"member_id": oid})
            under_kiri = _backend_async(stored_status) if r.status_code == 200 else f"{r.status_code} {r.text[:200]}"
        except Exception as e:  # noqa: BLE001
            under_minus12, under_kiri = repr(e)[:300], None
        check((under_minus12, under_kiri) == ("upcoming", "active"),
              f"family_jobs: a family budget starting {start} (today in Kiritimati) is stored upcoming while the owner "
              "is in UTC-12 and active once ownership passes to the Kiritimati member",
              (under_minus12, under_kiri))
    finally:
        _cleanup(made)


# ------------------------------------------------------------------------------------------------------ plan dates
def section_plan_dates():
    c, made = _client(), []
    try:
        p = _person(c, made, "Plandate", plan="plus", zone=KIRITIMATI)
        # 12:00 UTC is 18:30 in Yangon and 02:00 the next day in Kiritimati (UTC+14).
        utc_day = datetime.now(UTC).date() + timedelta(days=2)
        ends = datetime(utc_day.year, utc_day.month, utc_day.day, 12, 0, tzinfo=UTC)
        db.sql("UPDATE users SET subscription_expires_at = %s, plan_reminder_3d_for = NULL, "
               "plan_reminder_last_for = NULL WHERE id = %s", ends, p["id"])

        async def remind():
            import subscription_service as ss
            from plans.access import format_date
            stubenv.patch_loaded_modules()
            await ss.send_plan_renewal_reminders()
            return format_date(ends, "en", ZoneInfo(KIRITIMATI)), format_date(ends, "en", YANGON)
        try:
            kiri, yangon = _backend_async(remind)
        except Exception as e:  # noqa: BLE001
            kiri, yangon = repr(e)[:300], None
        got = db.sql("SELECT message FROM notifications WHERE user_id = %s AND type = 'plan_ending_soon'", p["id"])
        check(len(got) == 1 and kiri in got[0]["message"] and yangon not in got[0]["message"],
              f"plan_dates: a Kiritimati person's renewal reminder shows the end date on their calendar ({kiri}), not "
              f"the default zone's ({yangon})", got)
    finally:
        _cleanup(made)


# ----------------------------------------------------------------------------------------------------------- split
def section_split():
    """The insight jobs tick on their own: the scheduler has two 15-minute ticks whose job lists split LOCAL_JOBS, and
    a daily tick finishes (its reminder sent) while an insight tick is still waiting on its AI call."""
    import local_jobs
    import scheduler

    stubenv.patch_loaded_modules()

    async def scheduled():  # the AsyncIOScheduler starts on a running event loop
        sched = scheduler.start_scheduler()
        try:
            return {jid: sched.get_job(jid) for jid in ("local_jobs_tick", "local_insights_tick")}
        finally:
            sched.shutdown(wait=False)
    ticks = _backend_async(scheduled)
    at = datetime(2026, 11, 19, 3, 2, tzinfo=UTC)

    def shape(job):
        if job is None:
            return None
        first = job.trigger.get_next_fire_time(None, at)
        return (job.func is local_jobs.run_due_local_jobs, [j.id for j in job.kwargs.get("jobs", [])], job.max_instances,
                job.coalesce, job.misfire_grace_time, first, job.trigger.get_next_fire_time(first, first + timedelta(seconds=1)))
    q1, q2 = datetime(2026, 11, 19, 3, 15, tzinfo=UTC), datetime(2026, 11, 19, 3, 30, tzinfo=UTC)
    daily_ids = [j.id for j in local_jobs.DAILY_JOBS]
    insight_ids = [j.id for j in local_jobs.INSIGHT_JOBS]
    got = {jid: shape(job) for jid, job in ticks.items()}
    check(got == {"local_jobs_tick": (True, daily_ids, 1, True, 900, q1, q2),
                  "local_insights_tick": (True, insight_ids, 1, True, 900, q1, q2)}
          and sorted(insight_ids) == ["monthly_insights", "weekly_insights"]
          and sorted(daily_ids + insight_ids) == sorted(j.id for j in local_jobs.LOCAL_JOBS),
          "split: the scheduler runs the daily jobs and the insight jobs as two 15-minute UTC ticks (one at a time "
          "each, coalesced, 900 s grace) whose job lists split LOCAL_JOBS", got)

    c, made = _client(), []
    try:
        day = _today_in("Asia/Yangon")
        p = _person(c, made, "Split", zone="Asia/Yangon")
        gid = _goal(c, p, day + timedelta(days=7))
        book = _book_of(p)
        now = _at(day, 9, 5, YANGON)

        async def go():
            from sql import local_job_runs as runs_db
            orig_p, orig_b = runs_db.person_subjects, runs_db.book_subjects

            async def only_p():
                return [s for s in await orig_p() if s[0] == p["id"]]

            async def only_b():
                return [s for s in await orig_b() if s[0] == book]
            release, started = asyncio.Event(), asyncio.Event()

            async def slow_insight(subject_id, today, tz):
                started.set()
                await release.wait()
            slow = local_jobs.LocalJob("cd_slow_insight", local_jobs.time(0, 0), "book", slow_insight)
            runs_db.person_subjects, runs_db.book_subjects = only_p, only_b
            try:
                insight = asyncio.create_task(local_jobs.run_due_local_jobs(now=now, jobs=[slow]))
                await asyncio.wait_for(started.wait(), 30)
                daily = await asyncio.wait_for(local_jobs.run_due_local_jobs(now=now, jobs=local_jobs.DAILY_JOBS), 120)
                waiting = not insight.done()
                sent = len(_reminders(p, gid))
                release.set()
                return daily, waiting, sent, await insight
            finally:
                runs_db.person_subjects, runs_db.book_subjects = orig_p, orig_b
                release.set()
        try:
            daily, waiting, sent, insight_counts = _backend_async(go)
        except Exception as e:  # noqa: BLE001
            daily, waiting, sent, insight_counts = repr(e)[:300], None, None, None
        check(isinstance(daily, dict) and daily.get("goal_deadline_reminders") == 1 and waiting is True and sent == 1
              and "weekly_insights" not in daily and insight_counts == {"cd_slow_insight": 1},
              "split: while an insight tick waits on a slow AI call, the daily tick runs and sends the 09:05 goal "
              "reminder; the insight tick then finishes on its own", (daily, waiting, sent, insight_counts))
    finally:
        db.sql("DELETE FROM local_job_runs WHERE job = 'cd_slow_insight'")
        _cleanup(made)


SECTIONS = {"schema": section_schema, "migration": section_migration, "header": section_header,
            "today": section_today, "family": section_family, "ticks": section_ticks,
            "family_jobs": section_family_jobs, "plan_dates": section_plan_dates, "split": section_split}


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
