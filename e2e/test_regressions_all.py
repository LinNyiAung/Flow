"""Self-contained live checks for the regressions found in the retest. Run after test_api.py (needs a running server)."""
import asyncio
import concurrent.futures
import json
import os
import sys
import time
import uuid
from datetime import datetime, timedelta, UTC

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402

os.chdir(stubenv.BACKEND)
import httpx  # noqa: E402
from pymongo import MongoClient  # noqa: E402

BASE = "http://127.0.0.1:8765"
HERE = os.path.dirname(os.path.abspath(__file__))
db = __import__("pgcompat").get_db()
c = httpx.Client(base_url=BASE, timeout=60)
H = lambda t: {"Authorization": f"Bearer {t}"}
RESULTS = []


def rec(name, status, detail=""):
    RESULTS.append(("Regressions (retest)", name, status, str(detail)[:500]))
    print(f"[{status}] {name}" + (f" -- {detail}" if detail else ""))


def bug(name, cond, detail=""):
    rec(name, "BUG" if cond else "PASS", detail if cond else "")


def new_user(prefix):
    email = f"{prefix}-{uuid.uuid4().hex[:6]}@example.com"
    c.post("/api/auth/register", json={"name": prefix, "email": email, "password": "secret123"})
    db.users.update_one({"email": email}, {"$set": {"is_verified": True}})
    tok = c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json()["access_token"]
    return email, tok, db.users.find_one({"email": email})["_id"]


# 1. recurring due date at the real 06:00 Yangon run
import dotenv  # noqa: E402,F401
from recurring_transaction_service import due_occurrences, plan_due_occurrences  # noqa: E402
from recurrence_models import RecurrenceConfig  # noqa: E402
run_at = datetime(2026, 10, 9, 23, 30, tzinfo=UTC)
d, _ = due_occurrences(datetime(2026, 10, 9, tzinfo=UTC), RecurrenceConfig(frequency="daily"), run_at)
bug("daily occurrence due today is created at the 06:00 Yangon run", [x.date().isoformat() for x in d] != ["2026-10-10"], [x.date().isoformat() for x in d])
d, _ = due_occurrences(datetime(2026, 9, 10, tzinfo=UTC), RecurrenceConfig(frequency="monthly", day_of_month=10), run_at)
bug("monthly occurrence on day 10 created at the Oct 10 06:00 Yangon run", [x.date().isoformat() for x in d] != ["2026-10-10"], [x.date().isoformat() for x in d])
d = plan_due_occurrences(datetime(2026, 1, 1, tzinfo=UTC), RecurrenceConfig(frequency="daily"), datetime(2026, 10, 10, 6, tzinfo=UTC)).dates
bug("long-lagging daily recurrence catches up at most ~31 days in one run", len(d) > 32, f"{len(d)} occurrences")

# 2. editing a legacy-category transaction
email, tok, uid = new_user("legacy")
tid = "legacy-" + uuid.uuid4().hex[:6]
now = datetime.now(UTC)
db.transactions.insert_one({"_id": tid, "user_id": uid, "type": "outflow", "main_category": "Food & Drinks", "sub_category": "Lunch",
                            "amount": 4.5, "currency": "usd", "date": now, "description": "old", "created_at": now, "updated_at": now})
r = c.put(f"/api/transactions/{tid}", headers=H(tok), json={"type": "outflow", "main_category": "Food & Drinks", "sub_category": "Lunch",
                                                             "description": "edited", "amount": 4.5})
bug("description edit of a legacy-category transaction rejected", r.status_code != 200, f"{r.status_code} {r.text[:140]}")
r = c.put(f"/api/transactions/{tid}", headers=H(tok), json={"main_category": "Nope", "sub_category": "Nope"})
rec("changing to an invalid category still rejected", "PASS" if r.status_code == 400 else "FAIL", f"{r.status_code} {r.text[:120]}")

# 3. registration race
race = f"race-{uuid.uuid4().hex[:6]}@example.com"


def reg(_):
    with httpx.Client(base_url=BASE, timeout=60) as cc:
        return cc.post("/api/auth/register", json={"name": "Race", "email": race, "password": "secret123"}).status_code


with concurrent.futures.ThreadPoolExecutor(6) as ex:
    codes = list(ex.map(reg, range(6)))
bug("parallel registrations for one email return 500", 500 in codes, f"codes={sorted(codes)}")
rec("parallel registrations create exactly one account", "PASS" if db.users.count_documents({"email": race}) == 1 else "FAIL",
    db.users.count_documents({"email": race}))

# 4. resend right after register
e2 = f"resend-{uuid.uuid4().hex[:6]}@example.com"
c.post("/api/auth/register", json={"name": "R", "email": e2, "password": "secret123"})
u = db.users.find_one({"email": e2})
vkey = next(k for k in u if "verif" in k and "token" in k and "expires" not in k)
before = u.get(vkey)
c.post("/api/auth/resend-verification", json={"email": e2})
after = db.users.find_one({"email": e2}).get(vkey)
bug("first resend right after register sends nothing", before == after, "")
c.post("/api/auth/resend-verification", json={"email": e2})
after2 = db.users.find_one({"email": e2}).get(vkey)
rec("second resend within a minute is rate-limited", "PASS" if after2 == after else "INFO", "")

# 5. budget 'now active' notification after the list view flipped status
import notification_service as ns  # noqa: E402
stubenv.patch_loaded_modules()
email3, tok3, uid3 = new_user("budget")
tomorrow = (now + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
r = c.post("/api/budgets", headers=H(tok3), json={"name": "Soon", "period": "custom", "start_date": tomorrow.isoformat(),
                                                   "end_date": (tomorrow + timedelta(days=10)).isoformat(), "currency": "usd", "total_budget": 50,
                                                   "category_budgets": [{"main_category": "Transportation", "allocated_amount": 50}]})
bid = r.json()["id"]
db.budgets.update_one({"_id": bid}, {"$set": {"start_date": now - timedelta(hours=1)}})
db.notifications.delete_many({"user_id": uid3, "type": {"$in": ["budget_started", "budget_now_active"]}})
c.get("/api/budgets", headers=H(tok3))


async def _twice():
    await ns.check_budget_period_notifications()
    a = db.notifications.count_documents({"user_id": uid3, "type": {"$in": ["budget_started", "budget_now_active"]}})
    await ns.check_budget_period_notifications()
    return a


n1 = asyncio.run(_twice())  # one event loop: Motor binds to the first loop it sees
c.get("/api/budgets", headers=H(tok3))
n2 = db.notifications.count_documents({"user_id": uid3, "type": {"$in": ["budget_started", "budget_now_active"]}})
bug("'budget now active' notification missing after list view + job", n1 == 0, f"{n1}")
bug("'budget now active' sent more than once", n2 > 1, f"{n2}")

# 6. Platform enum text in audit log
logs = list(db.admin_action_logs.find({"details": {"$regex": "Platform\\."}}).limit(3))
new_logs = [l for l in logs if l.get("timestamp", l.get("created_at", now)) and True]
bug("admin audit log shows enum repr like 'Platform.ALL'", any("Platform." in (l.get("details") or "") for l in
    db.admin_action_logs.find({"details": {"$regex": "Platform\\."}, "_id": {"$exists": True}})), "")

# 7. placeholder insight not re-inserted on every GET
email4, tok4, uid4 = new_user("placeholder")
db.users.update_one({"_id": uid4}, {"$set": {"subscription_type": "premium", "subscription_expires_at": None}})
db.budgets.insert_one({"_id": "stale-" + uuid.uuid4().hex[:6], "user_id": uid4, "name": "Old", "period": "custom", "currency": "usd",
                       "start_date": now - timedelta(days=60), "end_date": now - timedelta(days=30), "category_budgets": [],
                       "total_budget": 10, "total_spent": 0, "remaining_budget": 10, "percentage_used": 0, "status": "active",
                       "is_active": True, "created_at": now, "updated_at": now})
for _ in range(3):
    c.get("/api/insights", headers=H(tok4), params={"insight_type": "weekly", "ai_provider": "gemini"})
n = db.insights.count_documents({"user_id": uid4})
bug("a new placeholder insight is inserted on every GET", n > 1, f"{n} insight docs after 3 GETs")

# 8. AI extraction: near-miss categories are snapped to valid ones; zero-amount items dropped
cats = {t: {c_["main_category"]: c_["sub_categories"] for c_ in c.get(f"/api/categories/{t}").json()} for t in ("inflow", "outflow")}


def valid(item):
    return item["main_category"] in cats.get(item["type"], {}) and item["sub_category"] in cats[item["type"]][item["main_category"]]


r = c.post("/api/transactions/extract-from-text", headers=H(tok4), json={"text": "coffee 2.5 dollars"})
ok_single = r.status_code == 200 and valid(r.json())
rec("single extraction returns a valid (snapped) category", "PASS" if ok_single else "FAIL", f"{r.status_code} {r.text[:200]}")
r = c.post("/api/transactions/extract-multiple-from-text", headers=H(tok4), json={"text": "lunch 4.5, grab 3, something"})
items = r.json().get("transactions", []) if r.status_code == 200 else []
rec("multi extraction: all categories valid", "PASS" if items and all(valid(i) for i in items) else "FAIL", f"{r.status_code} {[(i['main_category'], i['sub_category']) for i in items]}")
rec("multi extraction: zero-amount item dropped", "PASS" if len(items) == 2 and all(i["amount"] > 0 for i in items) else "FAIL", f"{len(items)} items")
rec("snapped categories (for review)", "INFO", [(i["description"], i["main_category"], i["sub_category"]) for i in items])
if items:
    payload = [{k: i[k] for k in ("type", "main_category", "sub_category", "date", "description", "amount", "currency")} for i in items]
    r = c.post("/api/transactions/batch-create", headers=H(tok4), json=payload)
    rec("extracted items batch-create successfully", "PASS" if r.status_code == 200 and len(r.json()) == 2 else "FAIL", f"{r.status_code} {r.text[:150]}")

p = os.path.join(HERE, "api_results.json")
data = json.load(open(p))
data["results"] = [r for r in data["results"] if r[0] != "Regressions (retest)"] + RESULTS
json.dump(data, open(p, "w"), indent=1, default=str)
