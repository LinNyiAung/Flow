"""Route-level sweeps against the running server: auth on every route, bad-input fuzzing, cross-user (IDOR) access."""
import json
import os
import re
import sys
import uuid
from collections import Counter
from datetime import datetime, timedelta, UTC

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402

os.chdir(stubenv.BACKEND)
import httpx  # noqa: E402
import main  # noqa: E402  (only to enumerate routes; the server under test is the separate process)

BASE = "http://127.0.0.1:8765"
HERE = os.path.dirname(os.path.abspath(__file__))
db = __import__("pgcompat").get_db()
c = httpx.Client(base_url=BASE, timeout=90)
H = lambda t: {"Authorization": f"Bearer {t}"}
RESULTS = []


def rec(section, name, status, detail=""):
    RESULTS.append((section, name, status, str(detail)[:400]))
    if status != "PASS":
        print(f"[{status}] {section}: {name}" + (f" -- {detail}" if detail else ""))


# Enumerate from the live server's OpenAPI schema (newer FastAPI no longer flattens
# included routers into app.routes, so walking app.routes undercounts).
ROUTES = []
for path, ops in c.get("/openapi.json").json()["paths"].items():
    if not path.startswith("/api"):
        continue
    for m in ops:
        if m.upper() in {"GET", "POST", "PUT", "PATCH", "DELETE"}:
            ROUTES.append((m.upper(), path))
print(f"{len(ROUTES)} API method/route pairs")

PUBLIC = {
    ("GET", "/api/categories/{transaction_type}"), ("POST", "/api/auth/register"), ("POST", "/api/auth/login"),
    ("GET", "/api/auth/verify-email"), ("POST", "/api/auth/forgot-password/request-otp"),
    ("POST", "/api/auth/forgot-password/verify-otp"), ("POST", "/api/auth/forgot-password/reset-password"),
    ("POST", "/api/auth/resend-verification"), ("POST", "/api/admin/login"),
    # Intentionally public: the website's "Get the Android app" link (see test_app_download.py).
    ("GET", "/api/app/latest-android"),
}


def fill(path, value="x"):
    return re.sub(r"\{[^}]+\}", value, path)


def call(method, path, token=None, **kw):
    headers = H(token) if token else {}
    try:
        return c.request(method, path, headers=headers, **kw)
    except httpx.HTTPError as e:
        return type("R", (), {"status_code": -1, "text": repr(e)})()


# ---------- fixtures
def make_user(prefix, premium=False):
    email = f"{prefix}-{uuid.uuid4().hex[:6]}@example.com".lower()  # server stores emails lowercased
    c.post("/api/auth/register", json={"name": prefix, "email": email, "password": "secret123"})
    upd = {"is_verified": True}
    if premium:
        upd |= {"subscription_type": "premium", "subscription_expires_at": None}
    db.users.update_one({"email": email}, {"$set": upd})
    tok = c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json()["access_token"]
    return tok, db.users.find_one({"email": email})["_id"]


A, A_id = make_user("sweepA", premium=True)
B, B_id = make_user("sweepB", premium=True)
from passlib.context import CryptContext  # noqa: E402
admin_email = f"sweep-admin-{uuid.uuid4().hex[:6]}@example.com"
db.admins.insert_one({"_id": str(uuid.uuid4()), "name": "Sweep", "email": admin_email, "password": CryptContext(schemes=["bcrypt"]).hash("sweep-admin-pw"),
                      "role": "super_admin", "created_at": datetime.now(UTC), "last_login": None})
AD = c.post("/api/admin/login", json={"email": admin_email, "password": "sweep-admin-pw"}).json()["access_token"]
now = datetime.now(UTC)
tx = c.post("/api/transactions", headers=H(A), json={"type": "inflow", "main_category": "Employment Income", "sub_category": "Salary",
                                                     "date": now.isoformat(), "amount": 500, "currency": "usd"}).json()
goal = c.post("/api/goals", headers=H(A), json={"name": "A goal", "target_amount": 100, "goal_type": "savings", "initial_contribution": 10, "currency": "usd"}).json()
budget = c.post("/api/budgets", headers=H(A), json={"name": "A budget", "period": "monthly", "start_date": now.replace(day=1).isoformat(),
                                                    "currency": "usd", "total_budget": 100,
                                                    "category_budgets": [{"main_category": "Transportation", "allocated_amount": 100}]}).json()
note = db.notifications.find_one({"user_id": A_id}) or {"_id": "none"}
fb = c.post("/api/feedback", headers=H(A), json={"category": "bug", "message": "sweep"}).json()
A_IDS = {"transaction_id": tx["id"], "goal_id": goal["id"], "budget_id": budget["id"], "notification_id": note["_id"]}
snapshot = lambda: (db.transactions.find_one({"_id": tx["id"]}), db.goals.find_one({"_id": goal["id"]}), db.budgets.find_one({"_id": budget["id"]}))
before = snapshot()

# ---------- 1. no token
for m, p in ROUTES:
    if (m, p) in PUBLIC:
        continue
    r = call(m, fill(p), json={})
    ok = r.status_code in (401, 403)
    rec("Auth: no token", f"{m} {p}", "PASS" if ok else "BUG", f"{r.status_code} {r.text[:120]}")

# ---------- 2. user token on admin routes, admin token on user routes
for m, p in ROUTES:
    if (m, p) in PUBLIC:
        continue
    is_admin = p.startswith("/api/admin")
    r = call(m, fill(p), token=(A if is_admin else AD), json={})
    ok = r.status_code in (401, 403)
    rec("Auth: wrong token type", f"{m} {p} with {'user' if is_admin else 'admin'} token", "PASS" if ok else "BUG", f"{r.status_code} {r.text[:120]}")

# ---------- 3. IDOR: B touching A's resources
for m, p in ROUTES:
    params = re.findall(r"\{([^}]+)\}", p)
    if not params or p.startswith("/api/admin") or not all(k in A_IDS for k in params):
        continue
    path = p
    for k in params:
        path = path.replace("{" + k + "}", A_IDS[k])
    body = {"amount": 1} if "contribute" in p else {"name": "hijack", "amount": 1, "description": "hijack"}
    r = call(m, path, token=B, json=body)
    ok = r.status_code in (403, 404)
    rec("IDOR: other user's id", f"{m} {p}", "PASS" if ok else "BUG", f"{r.status_code} {r.text[:120]}")
rec("IDOR: A's records unchanged after B's attempts", "transaction/goal/budget", "PASS" if snapshot() == before else "BUG", "")

# ---------- 4. bad-input fuzzing (looking for 5xx)
BODIES = [{}, [], "x", {"amount": "abc", "date": "notadate", "currency": "zzz", "type": "nope"},
          {"amount": -1e308, "name": "a" * 20000, "email": "not-an-email", "password": None},
          {"amount": 1e400}, {"start_date": "2026-13-45", "end_date": "yesterday", "period": "forever"}]
QUERIES = [{"limit": "abc"}, {"limit": 0}, {"skip": -1}, {"start_date": "nope", "end_date": "2026-99-99"}, {"currency": "zzz"},
           {"insight_type": "daily", "language": "fr", "ai_provider": "bard"}, {"search": "(((["}, {"status": "weird"}]
PATHVALS = [str(uuid.uuid4()), "..%2F..%2Fetc", "x" * 3000, "%00", "မြန်မာ"]
fivexx = Counter()
for m, p in ROUTES:
    if (m, p) in {("DELETE", "/api/auth/delete-account")}:
        continue
    token = AD if p.startswith("/api/admin") else A
    if (m, p) in PUBLIC:
        token = None
    variants = []
    for b in BODIES:
        variants.append({"content": json.dumps(b) if not isinstance(b, str) else b, "headers": {"Content-Type": "application/json"}})
    for q in QUERIES:
        variants.append({"params": q})
    paths = [fill(p, v) for v in PATHVALS] if "{" in p else [p]
    for path in paths:
        for v in variants:
            hdrs = dict(v.get("headers", {}))
            if token:
                hdrs["Authorization"] = f"Bearer {token}"
            try:
                r = c.request(m, path, headers=hdrs, params=v.get("params"), content=v.get("content"))
                code = r.status_code
            except httpx.HTTPError as e:
                code, r = -1, type("R", (), {"text": repr(e)})()
            if code >= 500 or code == -1:
                fivexx[(m, p)] += 1
                if fivexx[(m, p)] == 1:
                    rec("Fuzz: bad input", f"{m} {p}", "BUG", f"{code} for path={path[:60]} {str(v)[:140]} -> {r.text[:160]}")
for m, p in ROUTES:
    if (m, p) not in fivexx and (m, p) != ("DELETE", "/api/auth/delete-account"):
        rec("Fuzz: bad input", f"{m} {p}", "PASS")

# ---------- 5. CORS
r = c.options("/api/auth/login", headers={"Origin": "https://evil.example", "Access-Control-Request-Method": "POST"})
cred = (r.headers.get("access-control-allow-credentials") or "").lower() == "true"
reflected = r.headers.get("access-control-allow-origin") == "https://evil.example"
rec("CORS", "arbitrary origin is not granted credentialed access", "BUG" if cred and reflected else "PASS",
    f"{r.status_code} allow-origin={r.headers.get('access-control-allow-origin')} allow-credentials={r.headers.get('access-control-allow-credentials')}")

counts = Counter((s, st) for s, _, st, _ in RESULTS)
for k, v in sorted(counts.items()):
    print(f"{k[0]:32} {k[1]:5} {v}")
p = os.path.join(HERE, "api_results.json")
data = json.load(open(p)) if os.path.exists(p) else {"results": []}
data["results"] = [r for r in data["results"] if not str(r[0]).startswith(("Auth:", "IDOR:", "Fuzz:", "CORS"))] + RESULTS
json.dump(data, open(p, "w"), indent=1, default=str)
