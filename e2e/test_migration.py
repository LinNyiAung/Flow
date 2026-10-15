"""Migration dry run: legacy-shaped documents (as production likely has) against the new code."""
import asyncio
import json
import os
import sys
import uuid
from datetime import datetime, timedelta, UTC

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402

os.chdir(stubenv.BACKEND)
import httpx  # noqa: E402
try:
    import jwt  # PyJWT (replaces python-jose)
except ImportError:  # pragma: no cover
    from jose import jwt  # noqa: E402
from pymongo import MongoClient  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
mc = MongoClient("mongodb://127.0.0.1:27999")
db = __import__("pgcompat").get_db()
c = httpx.Client(base_url="http://127.0.0.1:8765", timeout=120)
H = lambda t: {"Authorization": f"Bearer {t}"}
RESULTS = []
now = datetime.now(UTC)


def rec(name, status, detail=""):
    RESULTS.append(("Migration dry run", name, status, str(detail)[:400]))
    print(f"[{status}] {name}" + (f" -- {detail}" if detail else ""))


def legacy_token(email, **extra):
    payload = {"sub": email, "exp": int((now + timedelta(days=10)).timestamp())} | extra
    return jwt.encode(payload, os.environ["SECRET_KEY"], algorithm="HS256")


# 1. a legacy user document: none of the new fields, created before verification existed
lid = str(uuid.uuid4())
lemail = f"legacy-{uuid.uuid4().hex[:6]}@example.com"
from passlib.context import CryptContext  # noqa: E402
db.users.insert_one({"_id": lid, "name": "Legacy", "email": lemail, "password": CryptContext(schemes=["bcrypt"]).hash("secret123"),
                     "created_at": now - timedelta(days=400)})
tok_legacy = legacy_token(lemail)  # no uid / iat / pwv
r = c.get("/api/auth/me", headers=H(tok_legacy))
rec("legacy token (no uid/iat/pwv) for legacy user still works", "PASS" if r.status_code == 200 else "FAIL", f"{r.status_code} {r.text[:150]}")
r = c.post("/api/auth/login", json={"email": lemail, "password": "secret123"})
rec("legacy user without is_verified field can log in", "PASS" if r.status_code == 200 else "INFO", f"{r.status_code} {r.text[:150]}")
tok = r.json().get("access_token") if r.status_code == 200 else tok_legacy

# 2. legacy data shapes
db.transactions.insert_many([
    {"_id": "leg-nocur", "user_id": lid, "type": "inflow", "main_category": "Employment Income", "sub_category": "Salary", "amount": 100,
     "date": now - timedelta(days=3), "created_at": now, "updated_at": now},  # no currency
    {"_id": "leg-oldcat", "user_id": lid, "type": "outflow", "main_category": "Food", "sub_category": "Lunch", "amount": 5, "currency": "usd",
     "date": now - timedelta(days=2), "description": None, "created_at": now, "updated_at": now},
])
r = c.get("/api/transactions", headers=H(tok))
rec("transaction list with a currency-less and an old-category row", "PASS" if r.status_code == 200 else "FAIL", f"{r.status_code} {r.text[:150]}")
r = c.get("/api/dashboard/balance", headers=H(tok))
rec("balance with a currency-less row", "PASS" if r.status_code == 200 else "FAIL", f"{r.status_code} {r.text[:150]}")
db.budgets.insert_one({"_id": "leg-budget", "user_id": lid, "name": "Old budget", "period": "monthly", "start_date": now.replace(day=1) - timedelta(days=40),
                       "end_date": now.replace(day=1) - timedelta(days=10), "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 50}],
                       "total_budget": 50, "total_spent": 0, "remaining_budget": 50, "percentage_used": 0, "status": "active", "is_active": True,
                       "auto_create_enabled": True, "created_at": now, "updated_at": now})  # no currency, no flags
r = c.get("/api/budgets", headers=H(tok))
rec("budget list with a currency-less, flag-less legacy budget", "PASS" if r.status_code == 200 else "FAIL", f"{r.status_code} {r.text[:150]}")
db.insights.insert_one({"_id": "leg-insight", "user_id": lid, "ai_provider": "openai", "insight_type": "weekly", "content": None,
                        "generated_at": now - timedelta(days=2)})
db.users.update_one({"_id": lid}, {"$set": {"subscription_type": "premium", "subscription_expires_at": None}})
r = c.get("/api/insights", headers=H(tok), params={"insight_type": "weekly"})
rec("GET insights when the latest stored insight has content=None", "PASS" if r.status_code < 500 else "FAIL", f"{r.status_code} {r.text[:150]}")
db.notifications.insert_one({"_id": "leg-note", "user_id": lid, "type": "goal_reminder_old", "title": "old", "message": "old",
                             "created_at": now - timedelta(days=30), "is_read": False})
r = c.get("/api/notifications", headers=H(tok))
rec("notifications list with an unknown legacy type", "PASS" if r.status_code == 200 else "FAIL", f"{r.status_code}")

# 3. a NaN amount already stored before validation existed
db.transactions.insert_one({"_id": "leg-nan", "user_id": lid, "type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries",
                            "amount": float("nan"), "currency": "usd", "date": now, "created_at": now, "updated_at": now})
db.users.update_one({"_id": lid}, {"$unset": {"balances": ""}})
codes = {p: c.get(p, headers=H(tok)).status_code for p in ("/api/dashboard/balance", "/api/transactions")}
codes["report"] = c.post("/api/reports/generate", headers=H(tok), json={"period": "month", "currency": "usd"}).status_code
rec("existing NaN row still breaks that user's balance/list/report (needs a one-off cleanup)", "BUG" if 500 in codes.values() else "PASS", codes)
db.transactions.delete_one({"_id": "leg-nan"})
db.users.update_one({"_id": lid}, {"$unset": {"balances": ""}})


async def jobs():
    import recurring_transaction_service as rts
    import notification_service as ns
    import budget_service as bs
    stubenv.patch_loaded_modules()
    # 4. recurring parent whose pointer lags 200 days (old one-per-run logic / old edit reset)
    db.transactions.insert_one({"_id": "leg-rec", "user_id": lid, "type": "outflow", "main_category": "Housing & Utilities", "sub_category": "Rent",
                                "amount": 1, "currency": "usd", "date": now - timedelta(days=200), "created_at": now, "updated_at": now,
                                "recurrence": {"enabled": True, "config": {"frequency": "daily"}, "last_created_date": now - timedelta(days=200)}})
    await rts.check_and_create_recurring_transactions()
    n = db.transactions.count_documents({"$or": [{"recurrence.parent_transaction_id": "leg-rec"}, {"parent_transaction_id": "leg-rec"}]})
    rec(f"200-day-behind daily recurrence: first run creates {n}", "PASS" if 0 < n <= 33 else "BUG", "expected ≤ ~31 (catch-up window)")
    await rts.check_and_create_recurring_transactions()
    n2 = db.transactions.count_documents({"$or": [{"recurrence.parent_transaction_id": "leg-rec"}, {"parent_transaction_id": "leg-rec"}]})
    rec("second run the same day creates no duplicates", "PASS" if n2 == n else "BUG", f"{n} -> {n2}")
    # 5. long-running active budgets without started_notified must not all get 'now active' on deploy
    db.budgets.insert_one({"_id": "leg-running", "user_id": lid, "name": "Running", "period": "custom", "currency": "usd",
                           "start_date": now - timedelta(days=10), "end_date": now + timedelta(days=20),
                           "category_budgets": [{"main_category": "Transportation", "allocated_amount": 50}], "total_budget": 50, "total_spent": 0,
                           "remaining_budget": 50, "percentage_used": 0, "status": "active", "is_active": True, "created_at": now, "updated_at": now})
    before = db.notifications.count_documents({"user_id": lid, "type": {"$in": ["budget_now_active", "budget_started"]}})
    await ns.check_budget_period_notifications()
    after = db.notifications.count_documents({"user_id": lid, "type": {"$in": ["budget_now_active", "budget_started"]}})
    rec("no 'budget now active' burst for budgets that started 10 days ago", "PASS" if after == before else "BUG", f"{before} -> {after}")
    # 6. rollover job for the legacy auto-create budget (ended 10 days ago); idempotent
    await bs.process_due_budget_rollovers()
    await bs.process_due_budget_rollovers()
    kids = list(db.budgets.find({"parent_budget_id": "leg-budget"}))
    rec(f"rollover job creates exactly one next budget for an ended auto-create budget ({len(kids)})", "PASS" if len(kids) == 1 else "BUG",
        [(k["name"], k.get("currency"), str(k["start_date"])[:10]) for k in kids])


asyncio.run(jobs())

# 7. unique email index vs existing duplicate-case emails (a copy of production might have them)
leg = mc["flow_e2e_legacy_copy"]
mc.drop_database("flow_e2e_legacy_copy")
leg.users.insert_many([{"_id": "u1", "email": "Same@Example.com"}, {"_id": "u2", "email": "same@example.com"}, {"_id": "u3", "email": "other@example.com"}])
import database  # noqa: E402
from motor.motor_asyncio import AsyncIOMotorClient  # noqa: E402


async def idx():
    cli = AsyncIOMotorClient(os.environ["MONGODB_URL"], tz_aware=True)
    ldb = cli["flow_e2e_legacy_copy"]
    for name in ("users_collection", "transactions_collection", "budgets_collection", "app_versions_collection"):
        setattr(database, name, ldb[name.replace("_collection", "")])
    import contextlib, io
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        await database.create_db_indexes()
    names = [i["name"] for i in await ldb.users.list_indexes().to_list(None)]
    return buf.getvalue(), names


out, names = asyncio.run(idx())
dups = list(leg.users.aggregate([{"$group": {"_id": {"$toLower": "$email"}, "n": {"$sum": 1}, "emails": {"$push": "$email"}}}, {"$match": {"n": {"$gt": 1}}}]))
rec("startup with duplicate-case emails: index creation fails gracefully (no crash), index missing",
    "PASS" if "email_unique_ci" not in names and ("Could not create unique email index" in out or "unique" in out.lower()) else "INFO",
    f"indexes={names}; duplicates to merge before deploy: {[d['emails'] for d in dups]}")
mc.drop_database("flow_e2e_legacy_copy")

p = os.path.join(HERE, "api_results.json")
data = json.load(open(p)) if os.path.exists(p) else {"results": []}
data["results"] = [r for r in data["results"] if r[0] != "Migration dry run"] + RESULTS
json.dump(data, open(p, "w"), indent=1, default=str)
