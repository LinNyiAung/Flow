"""The one-time MongoDB -> PostgreSQL data migration (backend/migration/run.py), end to end.

Builds a mongodump-style folder of legacy-shaped documents (NaN / negative / currency-less
amounts, deleted owners, dangling recurring and rollover links, duplicate rows, ...),
then runs the real script against a separate scratch database (flow_migration_test):
dry run, write, verification, refusal to overwrite, --reset, rollback on a failed check,
and the stop on case-duplicate e-mails.
"""
import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, UTC

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402  (blocks backend/.env)

os.chdir(stubenv.BACKEND)
import bson  # noqa: E402
import psycopg  # noqa: E402
from psycopg.rows import dict_row  # noqa: E402

from migration import run as M  # noqa: E402

ADMIN_DSN = os.environ.get("E2E_PG_ADMIN_DSN", "postgresql://flow@127.0.0.1:54329/postgres")
TEST_DB = "flow_migration_test"
TEST_URL = ADMIN_DSN.rsplit("/", 1)[0] + "/" + TEST_DB
results = []


def check(ok, name, detail=""):
    results.append(bool(ok))
    print(("[PASS] " if ok else "[BUG] ") + name + (f" -- {detail}" if detail and not ok else ""), flush=True)


def fresh_database():
    with psycopg.connect(ADMIN_DSN, autocommit=True) as conn:
        conn.execute(f"DROP DATABASE IF EXISTS {TEST_DB} WITH (FORCE)")
        conn.execute(f"CREATE DATABASE {TEST_DB}")
    subprocess.run([sys.executable, "-m", "alembic", "upgrade", "head"], cwd=stubenv.BACKEND, check=True,
                   env=dict(os.environ, DATABASE_URL=TEST_URL), capture_output=True)


def q(sql, *params):
    with psycopg.connect(TEST_URL, row_factory=dict_row) as conn:
        return conn.execute(sql, params).fetchall()


def dump(folder, collections):
    os.makedirs(folder, exist_ok=True)
    for name, docs in collections.items():
        with open(os.path.join(folder, f"{name}.bson"), "wb") as f:
            for d in docs:
                f.write(bson.encode(d))
    return folder


def run(*args):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = M.main(list(args))
    return code, out.getvalue()


now = datetime.now(UTC).replace(microsecond=0)
day = timedelta(days=1)
U1, U2, GONE = "u-alice", "u-legacy", "u-deleted"


def tx(_id, user, amount, type_="outflow", currency="usd", **extra):
    doc = {"_id": _id, "user_id": user, "type": type_, "main_category": "Food & Daily Living", "sub_category": "Groceries",
           "amount": amount, "date": now - day, "created_at": now - day, "updated_at": now - day, **extra}
    if currency is not None:
        doc["currency"] = currency
    return doc


SOURCE = {
    "categories": [{"_id": "outflow", "categories": [{"main_category": "Food & Daily Living", "sub_categories": ["Groceries", "Groceries", ""]},
                                                     {"main_category": "", "sub_categories": ["x"]}]}],
    "admins": [{"_id": "a1", "name": "Root", "email": "Root@Example.com", "password": "$2b$hash", "role": "super_admin"},
               {"_id": "a2", "email": "odd@example.com", "password": "$2b$hash", "role": "owner"}],
    "admin_action_logs": [{"_id": "l1", "admin_id": "a1", "admin_email": "root@example.com", "action": "deleted_user",
                           "details": {"why": "spam"}, "timestamp": now}],
    "app_versions": [{"_id": "v1", "version": "1.2.0", "platform": "android", "download_url": "https://x/1", "created_at": now - day},
                     {"_id": "v2", "version": "1.2.0", "platform": "android", "download_url": "https://x/2", "created_at": now}],
    "users": [
        {"_id": U1, "name": "Alice", "email": "Alice@Example.com", "password": "$2b$hash", "is_verified": True,
         "fcm_token": "device-1", "created_at": now - 30 * day, "balances": {"usd": {"balance": 1}}},
        {"_id": U2, "email": "legacy@example.com", "password": "$2b$hash", "fcm_token": "device-1", "created_at": now - 400 * day},
        {"_id": "u-nopass", "email": "nopass@example.com", "created_at": now},
    ],
    "notification_preferences": [
        {"_id": bson.ObjectId(), "user_id": U1, "preferences": {"goal_reminders": False, "junk": "x"}, "updated_at": now - day},
        {"_id": bson.ObjectId(), "user_id": U1, "preferences": {"goal_reminders": True}, "updated_at": now},
    ],
    "feedback": [{"_id": "f1", "user_id": U1, "message": "hi", "rating": 9}],
    "ai_usage": [{"_id": "ai1", "user_id": U1, "feature_type": "chat", "estimated_cost_usd": float("nan")}],
    "notifications": [{"_id": "n1", "user_id": U1, "type": "goal_reminder_old", "title": "t", "message": "m", "created_at": now},
                      {"_id": "n2", "user_id": GONE, "type": "x", "created_at": now}],
    "insights": [{"_id": "i1", "user_id": U1, "content": "  ", "generated_at": now},
                 {"_id": "i2", "user_id": U1, "content": "Real insight", "ai_provider": "openai", "insight_type": "weekly",
                  "generated_at": now}],
    "chat_sessions": [{"_id": "c1", "user_id": U1, "messages": [{"role": "user", "content": "hi", "timestamp": now},
                                                                 {"role": "tool", "content": "x"},
                                                                 {"role": "assistant", "content": "hello", "timestamp": now}],
                       "updated_at": now}],
    "goals": [{"_id": "g1", "user_id": U1, "name": "Car", "target_amount": 1000, "current_amount": 250.5, "currency": "usd"},
              {"_id": "g2", "user_id": U1, "name": "Broken", "target_amount": 100, "current_amount": float("nan")}],
    "transactions": [
        tx("t-salary", U1, 1000, "inflow"),
        tx("t-food", U1, 10.005),                      # rounds half-up to 10.01
        tx("t-nan", U1, float("nan")),                 # old app ignored it -> quarantined, balance unchanged
        tx("t-neg", U1, -5),                           # old app counted it -> quarantined, balance changes
        tx("t-nocur", U1, 7, currency=None),           # old app left it out -> migrated as usd, balance changes
        tx("t-orphan", GONE, 99),                      # owner deleted -> quarantined
        tx("t-parent", U1, 20, recurrence={"enabled": True, "config": {"frequency": "monthly", "day_of_month": 3},
                                           "last_created_date": now - day}),
        tx("t-child", U1, 20, recurrence={"enabled": False, "parent_transaction_id": "t-parent"}),
        tx("t-lost-child", U1, 20, recurrence={"enabled": False, "parent_transaction_id": "t-was-deleted"}),
        tx("t-mmk", U2, 50000, "inflow", "mmk"),
    ],
    "quarantined_transactions": [{**tx("t-old-q", U1, float("inf")), "quarantine_reason": "non_finite_amount",
                                  "quarantined_at": now}],
    "budgets": [
        {"_id": "b-parent", "user_id": U1, "name": "Food", "period": "monthly", "currency": "usd",
         "start_date": now - 40 * day, "end_date": now - 10 * day, "total_budget": 300, "auto_create_enabled": True,
         "rolled_over_to": "b-child", "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 300,
                                                            "spent_amount": float("nan")}]},
        {"_id": "b-child", "user_id": U1, "name": "Food", "period": "monthly", "currency": "usd", "parent_budget_id": "b-parent",
         "start_date": now - 9 * day, "end_date": now + 20 * day, "category_budgets": [
             {"main_category": "Food & Daily Living", "allocated_amount": 200}, {"main_category": "Food & Daily Living - Groceries",
                                                                                 "allocated_amount": 50}]},
        {"_id": "b-orphan-link", "user_id": U1, "name": "Old", "period": "custom", "currency": "usd",
         "parent_budget_id": "b-deleted", "start_date": now - 5 * day, "end_date": now, "total_budget": 10},
    ],
    "sessions_backup": [{"_id": "x"}],  # unknown collection: reported, not migrated
}

tmp = tempfile.mkdtemp(prefix="flow-dump-")
folder = dump(os.path.join(tmp, "flow"), SOURCE)
report_path = os.path.join(tmp, "report.json")
fresh_database()

# ---------------------------------------------------------------- 1. dry run
code, out = run("--dump", folder, "--report", report_path)
rep = json.load(open(report_path, encoding="utf-8"))
check(code == 0, "dry run succeeds", out[-400:])
check(q("SELECT count(*) AS n FROM users")[0]["n"] == 0, "dry run writes nothing")
quarantined = {(r["source"], r["reason"]) for r in rep["quarantined"]}
for source, reason in [("transactions", "amount not a positive finite number"), ("transactions", "owner account no longer exists"),
                       ("transactions", "quarantined before the migration"), ("goals", "goal saved amount not a non-negative number"),
                       ("insights", "insight without content"), ("users", "user without password hash"),
                       ("notifications", "owner account no longer exists"), ("admins", "unknown admin role 'owner'"),
                       ("app_versions", "duplicate of version 1.2.0 / android (newest kept)"),
                       ("notification_preferences", "duplicate preferences of the same user (newest kept)")]:
    check((source, reason) in quarantined, f"report: {source} set aside ({reason})", sorted(quarantined))
check(rep["fixes"].get("transactions: link to a deleted recurring parent cleared") == 1
      and rep["fixes"].get("budgets: parent_budget_id pointing at a deleted budget cleared") == 1
      and rep["fixes"].get("users: device token shared by several accounts, kept on the newest account") == 1,
      "report: dangling links and a shared device token repaired", rep["fixes"])
check(rep["ignored_collections"] == ["sessions_backup"], "report: unknown collections listed, not migrated", rep["ignored_collections"])
changes = {(c["user_id"], c["currency"]): c for c in rep["balance_changes"]}
alice = changes.get((U1, "usd"))
# old app: 1000 - 10.01 (shown) - (-5) - 20*3 ; new: 1000 - 10.01 - 7 - 60  -> difference -12 (the -5 row and the 7 row)
check(alice and alice["difference"] == "-12.00" and {d["id"] for d in alice["documents"]} == {"t-neg", "t-nocur"},
      "report: Alice's USD balance change (-12.00) explained by the negative and the currency-less row", alice)
check((U2, "mmk") not in changes, "report: balances without problem rows are unchanged")

# ---------------------------------------------------------------- 2. write + verify
code, out = run("--dump", folder, "--database-url", TEST_URL, "--write", "--yes")
check(code == 0 and "written and verified" in out, "write succeeds and is verified", out[-600:])
users = {r["id"]: r for r in q("SELECT * FROM users")}
check(set(users) == {U1, U2}, "users migrated (the account without a password set aside)", sorted(users))
check(users[U1]["email"] == "alice@example.com" and users[U2]["is_verified"] is True,
      "e-mails lowercased; legacy account without is_verified stays able to log in")
check(users[U1]["fcm_token"] == "device-1" and users[U2]["fcm_token"] is None,
      "shared device token kept on the newest account only")
bal = {(r["currency"], r["type"]): r["s"] for r in q(
    "SELECT currency, type, sum(amount) AS s FROM transactions WHERE user_id = %s GROUP BY 1, 2", U1)}
check(bal.get(("usd", "inflow")) == 1000 and str(bal.get(("usd", "outflow"))) == "77.01",
      "Alice's sums in PostgreSQL: inflow 1000.00, outflow 77.01 (10.01 + 7 + 3x20)", bal)
links = {r["id"]: r["parent_transaction_id"] for r in q("SELECT id, parent_transaction_id FROM transactions")}
check(links.get("t-child") == "t-parent" and links.get("t-lost-child") is None, "recurring parent link kept, dangling one cleared")
qr = {(r["source"], r["id"]) for r in q("SELECT source, id FROM quarantined_records")}
check({("transactions", "t-nan"), ("transactions", "t-neg"), ("transactions", "t-orphan"), ("transactions", "t-old-q"),
       ("goals", "g2"), ("insights", "i1")} <= qr, "quarantined_records holds the set-aside documents", sorted(qr))
nan_copy = q("SELECT original FROM quarantined_records WHERE source = 'transactions' AND id = 't-nan'")[0]["original"]
check(nan_copy.get("amount") == "nan" and nan_copy.get("user_id") == U1, "audit copy keeps the original document (NaN as text)", nan_copy)
b = {r["id"]: r for r in q("SELECT * FROM budgets")}
check(b["b-child"]["parent_budget_id"] == "b-parent" and b["b-parent"]["rolled_over_to"] == "b-child"
      and b["b-orphan-link"]["parent_budget_id"] is None, "budget rollover links kept, dangling parent cleared")
check(str(b["b-child"]["total_budget"]) == "200.00", "legacy budget without a total gets the code's rule (sub-category not double counted)",
      b["b-child"]["total_budget"])
alloc = q("SELECT main_category, spent_amount FROM budget_allocations WHERE budget_id = 'b-parent'")
check(len(alloc) == 1 and alloc[0]["spent_amount"] == 0, "NaN allocation numbers become 0", alloc)
msgs = q("SELECT role FROM chat_messages WHERE session_id = 'c1' ORDER BY id")
check([m["role"] for m in msgs] == ["user", "assistant"], "chat messages kept in order, invalid ones dropped", msgs)
prefs = q("SELECT preferences FROM notification_preferences WHERE user_id = %s", U1)
check(len(prefs) == 1 and prefs[0]["preferences"] == {"goal_reminders": True}, "newest preferences row kept", prefs)
cats = q("SELECT main_category, sub_category FROM categories")
check(cats == [{"main_category": "Food & Daily Living", "sub_category": "Groceries"}], "categories: duplicates and blanks dropped", cats)
log = q("SELECT details FROM admin_action_logs")[0]["details"]
check(json.loads(log) == {"why": "spam"}, "admin log details kept (as JSON text)", log)
check(q("SELECT download_url FROM app_versions")[0]["download_url"] == "https://x/2", "newest duplicate app version kept")

# ---------------------------------------------------------------- 3. rerun safety
try:
    run("--dump", folder, "--database-url", TEST_URL, "--write", "--yes")
    refused = False
except SystemExit as e:
    refused = "not empty" in str(e)
check(refused, "a second --write into a non-empty database is refused")
code, out = run("--dump", folder, "--database-url", TEST_URL, "--write", "--reset", "--yes")
check(code == 0 and q("SELECT count(*) AS n FROM transactions")[0]["n"] == 7, "--reset reruns cleanly (same 7 transactions)", out[-300:])

# ---------------------------------------------------------------- 4. a failed verification rolls back everything
with psycopg.connect(TEST_URL, autocommit=True) as conn:  # only survives if the --reset TRUNCATE is rolled back
    conn.execute("INSERT INTO users (id, name, email, password) VALUES ('marker', 'Marker', 'marker@example.com', 'h')")
real = M.planned_totals
M.planned_totals = lambda plan: {**real(plan), "transactions": {**real(plan)["transactions"], (U1, "usd", "inflow"): 1}}
try:
    code, out = run("--dump", folder, "--database-url", TEST_URL, "--write", "--reset", "--yes")
finally:
    M.planned_totals = real
check(code == 3 and "VERIFICATION FAILED" in out, "a verification mismatch fails the run (exit 3)", out[-300:])
check(q("SELECT count(*) AS n FROM users WHERE id = 'marker'")[0]["n"] == 1 and q("SELECT count(*) AS n FROM users")[0]["n"] == 3,
      "...and rolls back everything, including the --reset (previous data intact)")

# ---------------------------------------------------------------- 5. case-duplicate e-mails stop the run
dup_folder = dump(os.path.join(tmp, "dup"), {"users": [
    {"_id": "d1", "email": "Same@Example.com", "password": "h", "created_at": now},
    {"_id": "d2", "email": "same@example.com", "password": "h", "created_at": now}]})
code, out = run("--dump", dup_folder, "--database-url", TEST_URL, "--write", "--reset", "--yes")
check(code == 2 and "same@example.com" in out and "BLOCKING" in out, "case-duplicate e-mails stop the run (exit 2) and are listed", out[-300:])
check(q("SELECT count(*) AS n FROM users")[0]["n"] == 3, "...before anything is written")

with psycopg.connect(ADMIN_DSN, autocommit=True) as conn:
    conn.execute(f"DROP DATABASE IF EXISTS {TEST_DB} WITH (FORCE)")
print(f"{sum(results)}/{len(results)} passed")
sys.exit(0 if all(results) else 1)
