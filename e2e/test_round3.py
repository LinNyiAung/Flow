"""Live checks for round-3 review findings."""
import asyncio
import os
import sys
import uuid
from datetime import datetime, timedelta, UTC

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402

os.chdir(stubenv.BACKEND)
import httpx  # noqa: E402
from pymongo import MongoClient  # noqa: E402

db = __import__("pgcompat").get_db()
c = httpx.Client(base_url="http://127.0.0.1:8765", timeout=60)
H = lambda t: {"Authorization": f"Bearer {t}"}


RESULTS = []


def rec(name, is_bug, detail=""):
    RESULTS.append(("Round 3 regressions", name, "BUG" if is_bug else "PASS", str(detail)[:400]))
    print(f"[{'BUG' if is_bug else 'PASS'}] {name}" + (f" -- {detail}" if detail else ""))


def new_user():
    email = f"r3-{uuid.uuid4().hex[:6]}@example.com"
    c.post("/api/auth/register", json={"name": "R3", "email": email, "password": "secret123"})
    db.users.update_one({"email": email}, {"$set": {"is_verified": True}})
    tok = c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json()["access_token"]
    return tok, db.users.find_one({"email": email})["_id"]


now = datetime.now(UTC)
tok, uid = new_user()
som = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

# 1. renaming a budget re-sends threshold/exceeded alerts
b = c.post("/api/budgets", headers=H(tok), json={"name": "Food", "period": "monthly", "start_date": som.isoformat(), "currency": "usd",
                                                 "total_budget": 100, "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 100}]}).json()
c.post("/api/transactions", headers=H(tok), json={"type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries",
                                                  "date": now.isoformat(), "amount": 120, "currency": "usd"})
import time; time.sleep(1.5)
q = {"user_id": uid, "type": {"$in": ["budget_threshold", "budget_exceeded"]}}
n0 = db.notifications.count_documents(q)
cur = c.get(f"/api/budgets/{b['id']}", headers=H(tok)).json()
r = c.put(f"/api/budgets/{b['id']}", headers=H(tok), json={"name": "Food renamed", "category_budgets": cur["category_budgets"]})
time.sleep(1)
n1 = db.notifications.count_documents(q)
rec("renaming an over-budget budget re-sends threshold/exceeded alerts", n1 > n0, f"PUT {r.status_code}; alerts {n0} -> {n1}")

# 2. exceeded budget ending soon gets no 'ending soon' alert
import notification_service as ns  # noqa: E402
stubenv.patch_loaded_modules()
db.budgets.update_one({"_id": b["id"]}, {"$set": {"end_date": now + timedelta(days=2)}})
db.notifications.delete_many({"user_id": uid, "type": {"$regex": "ending|end"}})
asyncio.run(ns.check_budget_period_notifications())
ending = list(db.notifications.find({"user_id": uid, "type": {"$regex": "ending|end"}}))
st = db.budgets.find_one({"_id": b["id"]})["status"]
rec("over-budget ('exceeded') budget ending in 2 days gets no 'ending soon' alert", not ending, f"status={st}, alerts={[n['type'] for n in ending]}")

# 3. re-enabling a paused recurrence back-fills the paused period
t = c.post("/api/transactions", headers=H(tok), json={"type": "outflow", "main_category": "Housing & Utilities", "sub_category": "Rent",
                                                      "date": (now - timedelta(days=20)).isoformat(), "amount": 1, "currency": "usd",
                                                      "recurrence": {"enabled": False}}).json()
r = c.put(f"/api/transactions/{t['id']}", headers=H(tok), json={"recurrence": {"enabled": True, "config": {"frequency": "daily"}}})
import recurring_transaction_service as rts  # noqa: E402
asyncio.run(rts.check_and_create_recurring_transactions()) if False else None
from recurring_transaction_service import plan_due_occurrences  # noqa: E402
from recurrence_models import RecurrenceConfig  # noqa: E402
stored = db.transactions.find_one({"_id": t["id"]})["recurrence"]
plan = plan_due_occurrences(stored["last_created_date"], RecurrenceConfig(frequency="daily"), now)
rec("turning recurrence on for a 20-day-old transaction would back-fill past occurrences", len(plan.dates) > 1,
    f"PUT {r.status_code}; pointer={stored['last_created_date']}; next run would create {len(plan.dates)}")

# 4. bad query input -> 500
r = c.get("/api/transactions", headers=H(tok), params={"limit": -5})
rec("GET /api/transactions?limit=-5 returns 500", r.status_code == 500, r.status_code)
r = c.get("/api/notifications", headers=H(tok), params={"limit": -5})
rec("GET /api/notifications?limit=-5 returns 500", r.status_code == 500, r.status_code)
r = c.get("/api/goals", headers=H(tok), params={"currency": "eur"})
rec("GET /api/goals?currency=eur returns 500", r.status_code == 500, r.status_code)

# 5. category snapping cases from the round-3 review
from category_matching import snap_category  # noqa: E402
cat_map = {t: {c_["main_category"]: c_["sub_categories"] for c_ in c.get(f"/api/categories/{t}").json()} for t in ("inflow", "outflow")}
CASES = [
    ("inflow", "Income", "Freelance", "Self-Employment & Business", "Freelance Income"),
    ("inflow", "Income", "Monthly Salary", "Employment Income", "Salary"),
    ("inflow", "Gift", "Gift from mom", "Gifts & Support", "Gifts Received"),
    ("inflow", "Refund", "Refund", "Refunds & Reimbursements", None),
    ("inflow", "Salary", None, "Employment Income", "Salary"),
    ("outflow", "Subscriptions", "Netflix", "Entertainment & Leisure", None),
    ("outflow", "Food & Daily Living", "Steak", "Food & Daily Living", "Restaurants"),
    ("outflow", "Food & Drinks", "Lunch", "Food & Daily Living", "Restaurants"),
    ("outflow", "Transport", "Taxi Ride", "Transportation", "Taxi"),
]
for t, main, sub, want_main, want_sub in CASES:
    got = snap_category(t, main, sub, cat_map[t])[:2]
    rec(f"snap {t} '{main} / {sub}'", got[0] != want_main or (want_sub is not None and got[1] != want_sub),
        f"got {got}, want {want_main} / {want_sub or '(any)'}")
got = snap_category("outflow", "Transportation", "Training", cat_map["outflow"])[:2]
rec("snap 'Transportation / Training' not forced to Public Transport by substring", got[1] == "Public Transport", f"got {got}")

import json  # noqa: E402
p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "api_results.json")
data = json.load(open(p))
data["results"] = [r for r in data["results"] if r[0] != "Round 3 regressions"] + RESULTS
json.dump(data, open(p, "w"), indent=1, default=str)
