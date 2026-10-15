"""Load/perf: a user with 30k transactions, timed endpoints, and a parallel request burst."""
import concurrent.futures
import json
import os
import random
import statistics
import time
import uuid
from datetime import datetime, timedelta, UTC

import httpx
from pymongo import MongoClient

BASE = "http://127.0.0.1:8765"
HERE = os.path.dirname(os.path.abspath(__file__))
db = __import__("pgcompat").get_db()
c = httpx.Client(base_url=BASE, timeout=300)
H = lambda t: {"Authorization": f"Bearer {t}"}
RESULTS = []


def rec(name, status, detail=""):
    RESULTS.append(("Load", name, status, str(detail)[:300]))
    print(f"[{status}] {name}" + (f" -- {detail}" if detail else ""))


email = f"heavy-{uuid.uuid4().hex[:6]}@example.com"
c.post("/api/auth/register", json={"name": "Heavy", "email": email, "password": "secret123"})
db.users.update_one({"email": email}, {"$set": {"is_verified": True, "subscription_type": "premium", "subscription_expires_at": None}})
tok = c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json()["access_token"]
uid = db.users.find_one({"email": email})["_id"]

N = 30000
now = datetime.now(UTC).replace(hour=0, minute=0, second=0, microsecond=0)
cats = {"outflow": [("Food & Daily Living", "Groceries"), ("Transportation", "Taxi"), ("Housing & Utilities", "Electricity"),
                    ("Entertainment & Leisure", "Subscriptions"), ("Shopping & Lifestyle", "Clothing")],
        "inflow": [("Employment Income", "Salary"), ("Self-Employment & Business", "Freelance Income")]}
docs = []
for i in range(N):
    t = "inflow" if i % 8 == 0 else "outflow"
    m, s = random.choice(cats[t])
    d = now - timedelta(days=random.randint(0, 730), hours=random.randint(0, 23))
    docs.append({"_id": str(uuid.uuid4()), "user_id": uid, "type": t, "main_category": m, "sub_category": s,
                 "amount": round(random.uniform(1, 500 if t == "outflow" else 3000), 2), "currency": random.choice(["usd", "usd", "mmk"]),
                 "date": d, "description": f"bulk {i}", "created_at": d, "updated_at": d})
t0 = time.time()
db.transactions.insert_many(docs, ordered=False)
print(f"inserted {N} transactions in {time.time() - t0:.1f}s")
c.post("/api/budgets", headers=H(tok), json={"name": "Month", "period": "monthly", "start_date": now.replace(day=1).isoformat(), "currency": "usd",
                                             "total_budget": 2000, "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 1000},
                                                                                        {"main_category": "Transportation", "allocated_amount": 1000}]})
c.post("/api/goals", headers=H(tok), json={"name": "Car", "target_amount": 10000, "goal_type": "large_purchase", "initial_contribution": 100, "currency": "usd"})


def timed(name, method, path, budget_s, **kw):
    t0 = time.time()
    r = c.request(method, path, headers=H(tok), **kw)
    dt = time.time() - t0
    status = "PASS" if r.status_code == 200 and dt <= budget_s else ("SLOW" if r.status_code == 200 else "FAIL")
    rec(f"{name} ({dt:.2f}s, budget {budget_s}s)", status, "" if status == "PASS" else f"{r.status_code} {r.text[:150]}")
    return r


db.users.update_one({"_id": uid}, {"$unset": {"balances": ""}})
timed("balance, cache miss over 30k rows", "GET", "/api/dashboard/balance", 2)
timed("balance, cached", "GET", "/api/dashboard/balance", 0.5)
timed("transaction list, first page", "GET", "/api/transactions", 1, params={"limit": 50})
timed("transaction list, deep page (skip 20000)", "GET", "/api/transactions", 2, params={"limit": 50, "skip": 20000})
timed("analytics fetch 10k outflows", "GET", "/api/transactions", 5, params={"limit": 10000, "transaction_type": "outflow", "currency": "usd"})
timed("report: month", "POST", "/api/reports/generate", 3, json={"period": "month", "currency": "usd", "timezone_offset": 390})
timed("report: year", "POST", "/api/reports/generate", 5, json={"period": "year", "currency": "usd", "timezone_offset": 390})
timed("report: multi-currency custom 2 years", "POST", "/api/reports/generate-multi-currency", 8,
      json={"period": "custom", "start_date": (now - timedelta(days=730)).isoformat(), "end_date": now.isoformat(), "timezone_offset": 390})
timed("PDF download (year)", "POST", "/api/reports/download", 10, json={"period": "year", "currency": "usd"})
timed("budgets list (recalculates spent)", "GET", "/api/budgets", 3)
timed("budget summary", "GET", "/api/budgets/summary/all-currencies", 3)
timed("goals summary", "GET", "/api/goals/summary/all-currencies", 1)
timed("weekly insight generation (fake AI)", "POST", "/api/insights/regenerate", 15, params={"insight_type": "weekly"})
timed("monthly insight generation (fake AI)", "POST", "/api/insights/regenerate", 20, params={"insight_type": "monthly"})
t0 = time.time()
r = c.post("/api/chat/stream", headers=H(tok), json={"message": "How much did I spend on food?"})
dt = time.time() - t0
rec(f"chat with vector store build over 30k rows ({dt:.1f}s, budget 60s)", "PASS" if r.status_code == 200 and '"done": true' in r.text and dt <= 60 else "SLOW",
    r.text[-150:] if r.status_code != 200 else "")

# parallel burst: 40 workers x 5 mixed requests while one write path runs
paths = [("GET", "/api/dashboard/balance", {}), ("GET", "/api/transactions", {"params": {"limit": 50}}),
         ("GET", "/api/budgets", {}), ("GET", "/api/goals", {}), ("GET", "/api/notifications", {}),
         ("POST", "/api/transactions", {"json": {"type": "outflow", "main_category": "Transportation", "sub_category": "Taxi",
                                                 "date": now.isoformat(), "amount": 2, "currency": "usd"}})]


def worker(i):
    out = []
    with httpx.Client(base_url=BASE, timeout=120) as cc:
        for j in range(5):
            m, p, kw = paths[(i + j) % len(paths)]
            t0 = time.time()
            try:
                code = cc.request(m, p, headers=H(tok), **kw).status_code
            except httpx.HTTPError:
                code = -1
            out.append((code, time.time() - t0))
    return out


t0 = time.time()
with concurrent.futures.ThreadPoolExecutor(40) as ex:
    res = [x for lst in ex.map(worker, range(40)) for x in lst]
wall = time.time() - t0
lat = sorted(d for _, d in res)
errors = [c_ for c_, _ in res if c_ != 200]
p50, p95 = statistics.median(lat), lat[int(len(lat) * 0.95) - 1]
rec(f"burst: {len(res)} requests from 40 clients in {wall:.1f}s (p50 {p50:.2f}s, p95 {p95:.2f}s)",
    "PASS" if not errors and p95 < 10 else ("FAIL" if errors else "SLOW"), f"non-200: {dict((e, errors.count(e)) for e in set(errors))}" if errors else "")
bal = c.get("/api/dashboard/balance", headers=H(tok), params={"currency": "usd"}).json()
agg = list(db.transactions.aggregate([{"$match": {"user_id": uid, "currency": "usd"}},
                                      {"$group": {"_id": None, "i": {"$sum": {"$cond": [{"$eq": ["$type", "inflow"]}, "$amount", 0]}},
                                                  "o": {"$sum": {"$cond": [{"$eq": ["$type", "outflow"]}, "$amount", 0]}}}}]))[0]
rec("balance consistent with DB after concurrent writes", "PASS" if abs(bal["balance"] - (agg["i"] - agg["o"])) < 0.01 else "FAIL",
    f"api={bal['balance']:.2f} db={agg['i'] - agg['o']:.2f}")

p = os.path.join(HERE, "api_results.json")
data = json.load(open(p)) if os.path.exists(p) else {"results": []}
data["results"] = [r for r in data["results"] if r[0] != "Load"] + RESULTS
json.dump(data, open(p, "w"), indent=1, default=str)
