"""Burst profiler: which request types are slow under concurrency."""
import concurrent.futures
import statistics
import time
from collections import defaultdict
from datetime import datetime, UTC

import httpx

BASE = "http://127.0.0.1:8765"
db = __import__("pgcompat").get_db()
u = db.users.find_one({"email": {"$regex": "^heavy-"}})
tok = httpx.post(BASE + "/api/auth/login", json={"email": u["email"], "password": "secret123"}).json()["access_token"]
H = {"Authorization": f"Bearer {tok}"}
SHARED = httpx.Client(base_url=BASE, timeout=180, limits=httpx.Limits(max_connections=60, max_keepalive_connections=60))
now = datetime.now(UTC)
paths = [("GET", "/api/dashboard/balance", {}), ("GET", "/api/transactions", {"params": {"limit": 50}}),
         ("GET", "/api/budgets", {}), ("GET", "/api/goals", {}), ("GET", "/api/notifications", {}),
         ("POST", "/api/transactions", {"json": {"type": "outflow", "main_category": "Transportation", "sub_category": "Taxi",
                                                 "date": now.isoformat(), "amount": 2, "currency": "usd"}})]


def one(i):
    m, p, kw = paths[i % len(paths)]
    t0 = time.time()
    code = SHARED.request(m, p, headers=H, **kw).status_code
    return f"{m} {p}", code, time.time() - t0, t0


t_start = time.time()
with concurrent.futures.ThreadPoolExecutor(40) as ex:
    res = list(ex.map(one, range(600)))
by = defaultdict(list)
for name, code, dt, t0 in res:
    by[name].append(dt)
print(f"wall {time.time() - t_start:.1f}s")
for name, lst in sorted(by.items(), key=lambda kv: -max(kv[1])):
    print(f"{name:32} n={len(lst):3} p50={statistics.median(lst):6.2f}s max={max(lst):6.2f}s")
print("non-200:", [r[:2] for r in res if r[1] != 200][:5])
