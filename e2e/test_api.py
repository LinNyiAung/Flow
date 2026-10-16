"""End-to-end API suite for the Flow backend (runs against run_server.py on a throwaway local PostgreSQL)."""
import json
import math
import os
import time
import traceback
from datetime import datetime, timedelta, UTC

import httpx

BASE = os.environ.get("E2E_BASE", "http://127.0.0.1:8765")
HERE = os.path.dirname(os.path.abspath(__file__))
db = __import__("pgcompat").get_db()
c = httpx.Client(base_url=BASE, timeout=60)

RESULTS = []  # (section, name, status, detail)
SECTION = ["?"]


def section(name):
    SECTION[0] = name
    print(f"\n=== {name} ===")


def rec(name, status, detail=""):
    RESULTS.append((SECTION[0], name, status, str(detail)[:600]))
    print(f"[{status}] {name}" + (f" -- {str(detail)[:300]}" if detail else ""))


def ok(name, cond, detail=""):
    rec(name, "PASS" if cond else "FAIL", "" if cond else detail)
    return cond


def bug(name, cond_bug, detail=""):
    """cond_bug True => the suspected bug reproduced."""
    rec(name, "BUG" if cond_bug else "PASS", detail if cond_bug else "")
    return cond_bug


def H(tok):
    return {"Authorization": f"Bearer {tok}"}


def run(fn):
    try:
        fn()
    except Exception as e:
        rec(f"{fn.__name__} crashed", "ERROR", f"{type(e).__name__}: {e}\n{traceback.format_exc()[-800:]}")


now = datetime.now(UTC)
S = {}


def iso(d):
    return d.isoformat().replace("+00:00", "Z")


def verify_field(u):
    return next((k for k in u if "verif" in k and "token" in k), None)


def latest_otp(email):
    """Read the most recent OTP mailed to `email` from the stubbed SMTP outbox."""
    import re as _re
    path = os.path.join(HERE, "outbox.jsonl")
    code = None
    for line in open(path, encoding="utf-8"):
        rec_ = json.loads(line)
        if rec_.get("kind") != "smtp":
            continue
        body = " ".join(rec_.get("args", []))
        if email in body and "Password Reset" in body:
            m = _re.search(r"verification code is:\s+(\d{6})", body.replace("\\n", "\n"))
            if m:
                code = m.group(1)
    return code


def register_verified(name, email, pw):
    r = c.post("/api/auth/register", json={"name": name, "email": email, "password": pw})
    assert r.status_code == 200, r.text
    u = db.users.find_one({"email": email})
    r2 = c.get("/api/auth/verify-email", params={"email": email, "token": u[verify_field(u)]})
    r3 = c.post("/api/auth/login", json={"email": email, "password": pw})
    assert r3.status_code == 200, r3.text
    return r3.json()["access_token"], r3.json()["user"]["id"], r.json()["access_token"], r2


# ------------------------------------------------------------------ AUTH
def t_auth():
    section("Auth")
    r = c.get("/")
    ok("root responds", r.status_code == 200, r.text)

    r = c.post("/api/auth/register", json={"name": "Weak", "email": "weak@example.com", "password": "1"})
    bug("register accepts 1-char password (reset/change require >=6)", r.status_code == 200, r.status_code)

    email = "alice@example.com"
    r = c.post("/api/auth/register", json={"name": "Alice", "email": email, "password": "secret123"})
    ok("register", r.status_code == 200, r.text)
    reg_token = r.json().get("access_token")

    r = c.post("/api/auth/register", json={"name": "Alice", "email": email, "password": "secret123"})
    ok("duplicate register rejected", r.status_code == 400, r.status_code)
    r = c.post("/api/auth/register", json={"name": "Alice", "email": "ALICE@example.com", "password": "secret123"})
    bug("same email with different case registers a second account", r.status_code == 200, r.status_code)

    r = c.post("/api/auth/login", json={"email": email, "password": "secret123"})
    ok("unverified login blocked", r.status_code == 403, f"{r.status_code} {r.text}")

    r = c.get("/api/auth/me", headers=H(reg_token))
    bug("register token works before email verification (verification bypass)", r.status_code == 200, r.status_code)

    out_path = os.path.join(HERE, "outbox.jsonl")
    out = open(out_path, encoding="utf-8").read() if os.path.exists(out_path) else ""
    ok("verification email produced (stubbed SMTP)", "verify-email" in out, "no smtp record")

    u = db.users.find_one({"email": email})
    r = c.get("/api/auth/verify-email", params={"email": email, "token": "wrong"})
    ok("verify with wrong token rejected", r.status_code >= 400, r.status_code)
    r = c.get("/api/auth/verify-email", params={"email": email, "token": u[verify_field(u)]})
    ok("verify-email", r.status_code == 200, r.text[:200])

    plus = "bob+flow@example.com"
    c.post("/api/auth/register", json={"name": "Plus", "email": plus, "password": "secret123"})
    import re as _re
    link = None
    for _ in range(20):  # the email is sent from a background task after the response
        links = [m for line in open(out_path, encoding="utf-8") for m in _re.findall(r"https?://\S*verify-email\?\S+", line.replace("\\n", " "))]
        link = next((l for l in reversed(links) if "bob%2Bflow" in l or "bob+flow" in l), None)
        if link:
            break
        time.sleep(0.25)
    if link:
        path = "/api/auth/verify-email?" + link.split("?", 1)[1].rstrip('",')
        r = c.get(path)
        bug("verification link from the email fails for addresses containing '+'", r.status_code != 200, f"{r.status_code} {r.text[:120]} link={link[:120]}")
    else:
        rec("verification link for '+' address", "FAIL", "no link captured in outbox")
    r = c.post("/api/auth/resend-verification", json={"email": "nobody-here@example.com"})
    ok("resend-verification for unknown email gives generic 200", r.status_code == 200, f"{r.status_code} {r.text[:120]}")

    r = c.post("/api/auth/login", json={"email": email, "password": "secret123"})
    ok("login", r.status_code == 200, r.text)
    S["A"] = r.json()["access_token"]
    S["A_id"] = r.json()["user"]["id"]
    ok("login response is_verified=true", r.json()["user"].get("is_verified") is True, r.json()["user"])
    r = c.post("/api/auth/login", json={"email": email, "password": "nope"})
    ok("wrong password rejected", r.status_code == 401, r.status_code)

    r = c.get("/api/auth/me", headers=H(S["A"]))
    ok("/me", r.status_code == 200 and r.json()["email"] == email, r.text)
    bug("/me reports is_verified=false for a verified user", r.json().get("is_verified") is not True, r.json().get("is_verified"))

    r = c.get("/api/auth/me", headers={"Authorization": "Bearer garbage"})
    ok("bad token -> 401", r.status_code == 401, r.status_code)
    r = c.get("/api/auth/me")
    ok("no token -> 401/403", r.status_code in (401, 403), r.status_code)

    r = c.put("/api/auth/profile", headers=H(S["A"]), json={"name": "Alice <3"})
    ok("update profile", r.status_code == 200 and r.json()["name"] == "Alice <3", r.text)
    r = c.put("/api/auth/profile", headers=H(S["A"]), json={"name": ""})
    bug("empty profile name accepted", r.status_code == 200, r.status_code)
    c.put("/api/auth/profile", headers=H(S["A"]), json={"name": "Alice <3"})
    r = c.put("/api/auth/currency", headers=H(S["A"]), json={"default_currency": "mmk"})
    ok("update currency", r.status_code == 200 and r.json()["default_currency"] == "mmk", r.text)
    c.put("/api/auth/currency", headers=H(S["A"]), json={"default_currency": "usd"})
    r = c.put("/api/auth/language", headers=H(S["A"]), json={"language": "my"})
    ok("update language", r.status_code == 200, r.text)

    r = c.put("/api/auth/change-password", headers=H(S["A"]),
              json={"current_password": "wrong", "new_password": "secret456", "confirm_password": "secret456"})
    ok("change password with wrong current rejected", r.status_code in (400, 401), r.status_code)
    r = c.put("/api/auth/change-password", headers=H(S["A"]),
              json={"current_password": "secret123", "new_password": "secret456", "confirm_password": "secret456"})
    ok("change password", r.status_code == 200, r.text)
    r = c.get("/api/auth/me", headers=H(S["A"]))
    bug("old JWT still valid after password change (no revocation)", r.status_code == 200, "")
    r = c.post("/api/auth/login", json={"email": email, "password": "secret456"})
    ok("login with new password", r.status_code == 200, r.text)
    S["A"] = r.json()["access_token"]

    S["B"], S["B_id"], _, _ = register_verified("Bob", "bob@example.com", "secret123")


def t_forgot():
    section("Forgot password / OTP")
    email = "alice@example.com"
    r = c.post("/api/auth/forgot-password/request-otp", json={"email": email})
    ok("request otp", r.status_code == 200, r.text)
    r = c.post("/api/auth/forgot-password/request-otp", json={"email": "nobody@example.com"})
    ok("request otp for unknown email doesn't reveal existence", r.status_code == 200, r.status_code)
    r1 = c.post("/api/auth/forgot-password/verify-otp", json={"email": "nobody@example.com", "otp": "000000"})
    r2 = c.post("/api/auth/forgot-password/verify-otp", json={"email": "bob@example.com", "otp": "000000"})
    bug("verify-otp error text differs for registered vs unknown emails (enumeration)",
        r1.json().get("detail") != r2.json().get("detail"), f"unknown={r1.json()} registered={r2.json()}")

    # brute-force probe on a dedicated account
    bf = "otp-victim@example.com"
    register_verified("Victim", bf, "secret123")
    c.post("/api/auth/forgot-password/request-otp", json={"email": bf})
    votp = latest_otp(bf)
    vwrong = "000000" if votp != "000000" else "111111"
    codes = [c.post("/api/auth/forgot-password/verify-otp", json={"email": bf, "otp": vwrong}).status_code for _ in range(6)]
    r = c.post("/api/auth/forgot-password/verify-otp", json={"email": bf, "otp": votp})
    ok("OTP locked after repeated wrong guesses", r.status_code != 200, f"codes={codes}, correct-after={r.status_code}")
    c.post("/api/auth/forgot-password/request-otp", json={"email": bf})
    votp2 = latest_otp(bf)
    r = c.post("/api/auth/forgot-password/verify-otp", json={"email": bf, "otp": votp2})
    bug("re-requesting an OTP after lockout gives fresh guesses (unlimited brute force)", r.status_code == 200,
        f"correct OTP after lockout+re-request -> {r.status_code}")

    otp = latest_otp(email)
    r = c.post("/api/auth/forgot-password/verify-otp", json={"email": email, "otp": otp})
    ok("verify correct otp", r.status_code == 200, r.text)
    rt = r.json().get("reset_token")
    r = c.post("/api/auth/forgot-password/reset-password",
               json={"email": email, "reset_token": rt, "new_password": "secret789", "confirm_password": "secret789"})
    ok("reset password", r.status_code == 200, r.text)
    r = c.post("/api/auth/forgot-password/reset-password",
               json={"email": email, "reset_token": rt, "new_password": "secret000", "confirm_password": "secret000"})
    ok("reset token single-use", r.status_code >= 400, r.status_code)
    r = c.post("/api/auth/login", json={"email": email, "password": "secret789"})
    ok("login after reset", r.status_code == 200, r.text)
    S["A"] = r.json()["access_token"]


# ------------------------------------------------------------------ SUBSCRIPTION
def t_subscription():
    section("Subscription / free trial")
    r = c.get("/api/auth/subscription-status", headers=H(S["A"]))
    ok("subscription-status (free user)", r.status_code == 200, r.text)
    r = c.post("/api/chat/stream", headers=H(S["A"]), json={"message": "hi"})
    ok("premium endpoint blocked for free user", r.status_code == 403, r.status_code)

    r = c.post("/api/auth/claim-free-trial", headers=H(S["A"]))
    ok("claim free trial", r.status_code == 200, r.text)
    bug("claim-free-trial response says has_claimed_free_trial=false", r.json().get("has_claimed_free_trial") is not True, r.json().get("has_claimed_free_trial"))
    r = c.get("/api/auth/me", headers=H(S["A"]))
    bug("/me never reports has_claimed_free_trial=true (app keeps showing trial button)",
        r.json().get("has_claimed_free_trial") is not True, r.json().get("has_claimed_free_trial"))
    r = c.post("/api/auth/login", json={"email": "alice@example.com", "password": "secret789"})
    bug("/login response has_claimed_free_trial=false after claiming", r.json()["user"].get("has_claimed_free_trial") is not True, "")
    r = c.get("/api/auth/subscription-status", headers=H(S["A"]))
    bug("subscription-status 500s for trial users (naive vs aware datetime)", r.status_code == 500, f"{r.status_code} {r.text[:150]}")
    r = c.post("/api/auth/claim-free-trial", headers=H(S["A"]))
    ok("second trial claim rejected", r.status_code == 400, r.status_code)

    db.users.update_one({"_id": S["B_id"]}, {"$set": {"subscription_type": "premium", "subscription_expires_at": None}})
    r = c.post("/api/auth/claim-free-trial", headers=H(S["B"]))
    after = db.users.find_one({"_id": S["B_id"]})
    bug("lifetime premium user downgraded to 30-day expiry by claiming trial",
        r.status_code == 200 and after.get("subscription_expires_at") is not None, f"{r.status_code} expires={after.get('subscription_expires_at')}")
    db.users.update_one({"_id": S["B_id"]}, {"$set": {"subscription_type": "free", "subscription_expires_at": None}})

    # expired premium is blocked
    tok, uid, _, _ = register_verified("Exp", "expired@example.com", "secret123")
    db.users.update_one({"_id": uid}, {"$set": {"subscription_type": "premium", "subscription_expires_at": datetime.now(UTC) - timedelta(days=1)}})
    r = c.post("/api/chat/stream", headers=H(tok), json={"message": "hi"})
    ok("expired premium blocked from premium endpoints", r.status_code == 403, r.status_code)


# ------------------------------------------------------------------ CATEGORIES / TRANSACTIONS
def tx(tok, **kw):
    body = {"type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Groceries",
            "date": iso(now), "amount": 10, "currency": "usd", "description": "e2e"}
    body.update(kw)
    return c.post("/api/transactions", headers=H(tok), json=body)


def bal(tok, cur="usd"):
    r = c.get("/api/dashboard/balance", headers=H(tok), params={"currency": cur})
    assert r.status_code == 200, f"balance {r.status_code} {r.text[:100]}"
    return r.json()


def t_transactions():
    section("Categories & transactions")
    r = c.get("/api/categories/outflow")
    ok("outflow categories", r.status_code == 200 and len(r.json()) > 5, r.text[:100])
    r = c.get("/api/categories/inflow")
    ok("inflow categories", r.status_code == 200 and len(r.json()) > 3, r.text[:100])
    r = c.get("/api/categories/bogus")
    ok("bad category type -> 422", r.status_code == 422, r.status_code)

    A = S["A"]
    r = tx(A, type="inflow", main_category="Employment Income", sub_category="Salary", amount=1000)
    ok("create inflow", r.status_code == 200, r.text)
    S["inflow_id"] = r.json()["id"]
    r = tx(A, amount=50)
    ok("create outflow", r.status_code == 200, r.text)
    S["out_id"] = r.json()["id"]
    r = tx(A, type="inflow", main_category="Employment Income", sub_category="Salary", amount=500000, currency="mmk")
    ok("create MMK inflow", r.status_code == 200, r.text)

    b = bal(A)
    ok("USD balance = 950", abs(b.get("balance", -1) - 950) < 1e-9, b)
    b2 = bal(A, "mmk")
    ok("MMK balance separate = 500000", abs(b2.get("balance", -1) - 500000) < 1e-9, b2)
    r = c.get("/api/dashboard/balance", headers=H(A))
    ok("all-currency balance", r.status_code == 200 and set(r.json()["balances"]) >= {"usd", "mmk"}, r.text[:200])

    r = c.get("/api/transactions", headers=H(A))
    ok("list transactions", r.status_code == 200 and len(r.json()) == 3, len(r.json()) if r.status_code == 200 else r.text)
    r = c.get("/api/transactions", headers=H(A), params={"transaction_type": "inflow", "currency": "usd"})
    ok("filter by type+currency", r.status_code == 200 and len(r.json()) == 1, r.text[:200])

    r = c.put(f"/api/transactions/{S['out_id']}", headers=H(A), json={"amount": 70})
    ok("update amount", r.status_code == 200 and r.json()["amount"] == 70, r.text)
    ok("balance updated after edit", abs(bal(A)["balance"] - 930) < 1e-9, bal(A))
    r = c.put(f"/api/transactions/{S['out_id']}", headers=H(A), json={"description": "edited"})
    ok("partial update keeps amount", r.status_code == 200 and r.json()["amount"] == 70, r.text[:200])

    r = tx(A, amount=-100)
    bug("negative amount accepted", r.status_code == 200, r.status_code)
    if r.status_code == 200:
        c.delete(f"/api/transactions/{r.json()['id']}", headers=H(A))
    r = tx(A, amount=0)
    bug("zero amount accepted", r.status_code == 200, r.status_code)
    if r.status_code == 200:
        c.delete(f"/api/transactions/{r.json()['id']}", headers=H(A))

    r = c.post("/api/transactions", headers={**H(A), "Content-Type": "application/json"},
               content='{"type":"outflow","main_category":"x","sub_category":"y","date":"%s","amount":NaN}' % iso(now))
    nan_docs = [t for t in db.transactions.find({"user_id": S["A_id"]}) if isinstance(t.get("amount"), float) and math.isnan(t["amount"])]
    bal_r = c.get("/api/dashboard/balance", headers=H(A))
    bug("NaN amount persisted even though API returned an error; user's balance endpoint then 500s",
        bool(nan_docs) and bal_r.status_code == 500, f"create={r.status_code}, NaN docs={len(nan_docs)}, balance={bal_r.status_code}")
    rep = c.post("/api/reports/generate", headers=H(A), json={"period": "month", "currency": "usd"})
    bug("...and reports 500 too while the NaN row exists", rep.status_code == 500, rep.status_code)
    lst = c.get("/api/transactions", headers=H(A))
    bug("...and the transaction list 500s too", lst.status_code == 500, lst.status_code)
    for t in nan_docs:
        db.transactions.delete_one({"_id": t["_id"]})

    r = tx(A, main_category="Not A Category", sub_category="Nope")
    bug("arbitrary category names accepted", r.status_code == 200, r.status_code)
    if r.status_code == 200:
        c.delete(f"/api/transactions/{r.json()['id']}", headers=H(A))
    ok("balance unchanged after cleanups", abs(bal(A)["balance"] - 930) < 1e-9, bal(A))

    B = S["B"]
    ok("B cannot read A's tx", c.get(f"/api/transactions/{S['out_id']}", headers=H(B)).status_code == 404, "")
    ok("B cannot edit A's tx", c.put(f"/api/transactions/{S['out_id']}", headers=H(B), json={"amount": 1}).status_code == 404, "")
    ok("B cannot delete A's tx", c.delete(f"/api/transactions/{S['out_id']}", headers=H(B)).status_code == 404, "")
    ok("B sees none of A's tx", len(c.get("/api/transactions", headers=H(B)).json()) == 0, "")
    r = c.get("/api/transactions/does-not-exist", headers=H(A))
    ok("missing tx -> 404", r.status_code == 404, r.status_code)

    today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    r = c.get("/api/transactions", headers=H(A), params={"start_date": iso(today), "end_date": iso(today)})
    ok("start=end=today (UTC) returns today's tx", r.status_code == 200 and len(r.json()) >= 3, f"{r.status_code} n={len(r.json()) if r.status_code == 200 else r.text}")
    # fixed app sends wall-clock day bounds as UTC: 00:00:00Z .. 23:59:59Z
    r = c.get("/api/transactions", headers=H(A), params={"start_date": iso(today), "end_date": iso(today.replace(hour=23, minute=59, second=59))})
    ok("day filter with explicit 23:59:59 end returns today's tx", r.status_code == 200 and len(r.json()) >= 3, f"n={len(r.json()) if r.status_code == 200 else r.status_code}")

    batch = []
    for i in range(6):
        batch.append(tx(A, amount=1 + i, date=iso(now - timedelta(days=40)), description=f"page{i}").json()["id"])
    db.transactions.update_many({"_id": {"$in": batch}}, {"$set": {"created_at": now}})  # same created_at as batch-create
    seen = []
    for skip in (0, 3, 6, 9):
        seen += [t["id"] for t in c.get("/api/transactions", headers=H(A), params={"limit": 3, "skip": skip}).json()]
    bug("pagination returns duplicates/misses rows when date+created_at tie", len(seen) != len(set(seen)) or not set(batch) <= set(seen),
        f"{len(seen)} rows, {len(set(seen))} unique, missing={len(set(batch) - set(seen))}")
    for i in batch:
        c.delete(f"/api/transactions/{i}", headers=H(A))


# ------------------------------------------------------------------ BUDGETS
def t_budgets():
    section("Budgets")
    A = S["A"]
    som = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    r = c.post("/api/budgets", headers=H(A), json={
        "name": "Oct", "period": "monthly", "start_date": iso(som), "currency": "usd", "total_budget": 100,
        "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 100}]})
    ok("create monthly budget", r.status_code == 200, r.text)
    bid = r.json()["id"]
    S["budget_id"] = bid
    time.sleep(1.5)
    bgt = c.get(f"/api/budgets/{bid}", headers=H(A)).json()
    ok("existing 70 USD food spend counted", abs(bgt["total_spent"] - 70) < 1e-9, bgt["total_spent"])

    r = c.post("/api/budgets", headers=H(A), json={
        "name": "Bad", "period": "monthly", "start_date": iso(som), "currency": "usd", "total_budget": -5,
        "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": -5}]})
    bug("budget with negative allocation accepted", r.status_code == 200, r.status_code)
    if r.status_code == 200:
        c.delete(f"/api/budgets/{r.json()['id']}", headers=H(A))

    # next-month budget exists BEFORE a tx is moved into it
    nm_start = (som + timedelta(days=40)).replace(day=1)
    r = c.post("/api/budgets", headers=H(A), json={
        "name": "Next", "period": "monthly", "start_date": iso(nm_start), "currency": "usd", "total_budget": 100,
        "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 100}]})
    nb = r.json()["id"]
    t = tx(A, amount=20).json()
    time.sleep(1.5)
    ok("new 20 outflow counted in current budget (90)", abs(c.get(f"/api/budgets/{bid}", headers=H(A)).json()["total_spent"] - 90) < 1e-9, "")
    c.put(f"/api/transactions/{t['id']}", headers=H(A), json={"date": iso(nm_start.replace(day=2))})
    time.sleep(1.5)
    ok("moving tx out removes it from old budget (70)", abs(c.get(f"/api/budgets/{bid}", headers=H(A)).json()["total_spent"] - 70) < 1e-9, "")
    nb_spent = c.get(f"/api/budgets/{nb}", headers=H(A)).json()["total_spent"]
    bug("tx moved into next month NOT counted by next month's budget (only old period recalculated)", abs(nb_spent - 20) > 1e-9,
        f"next-month budget spent={nb_spent}, expected 20")
    c.post(f"/api/budgets/{nb}/refresh", headers=H(A))
    nb_spent2 = c.get(f"/api/budgets/{nb}", headers=H(A)).json()["total_spent"]
    rec("next-month budget after manual refresh", "INFO", nb_spent2)
    # currency change: tx now MMK, should leave USD next-month budget
    c.put(f"/api/transactions/{t['id']}", headers=H(A), json={"currency": "mmk"})
    time.sleep(1.5)
    nb_spent3 = c.get(f"/api/budgets/{nb}", headers=H(A)).json()["total_spent"]
    rec("USD next-month budget after tx switched to MMK", "INFO", f"spent={nb_spent3} (expected 0)")
    c.delete(f"/api/transactions/{t['id']}", headers=H(A))
    c.delete(f"/api/budgets/{nb}", headers=H(A))

    big = tx(A, amount=60).json()
    time.sleep(1.5)
    b = c.get(f"/api/budgets/{bid}", headers=H(A)).json()
    ok("budget status exceeded at 130/100", b["status"] == "exceeded", b["status"])
    summ = c.get("/api/budgets/summary", headers=H(A), params={"currency": "usd"}).json()
    bug("exceeded budget disappears from summary totals", summ.get("total_spent", 0) < 130 - 1e-9, summ)
    c.delete(f"/api/transactions/{big['id']}", headers=H(A))
    time.sleep(1.5)
    b = c.get(f"/api/budgets/{bid}", headers=H(A)).json()
    bug("status stays 'exceeded' after deleting the overspend", b["status"] == "exceeded",
        f"spent={b['total_spent']} status={b['status']}")
    c.post(f"/api/budgets/{bid}/refresh", headers=H(A))
    b = c.get(f"/api/budgets/{bid}", headers=H(A)).json()
    rec("status after manual refresh", "INFO", f"spent={b['total_spent']} status={b['status']}")

    r = c.put(f"/api/budgets/{bid}", headers=H(A), json={"total_budget": 500})
    b = c.get(f"/api/budgets/{bid}", headers=H(A)).json()
    bug("changing total_budget is silently reverted", r.status_code == 200 and abs(b["total_budget"] - 500) > 1e-9,
        f"PUT {r.status_code}, now total_budget={b['total_budget']}")

    ok("B cannot read A's budget", c.get(f"/api/budgets/{bid}", headers=H(S["B"])).status_code == 404, "")
    ok("B cannot delete A's budget", c.delete(f"/api/budgets/{bid}", headers=H(S["B"])).status_code == 404, "")
    ok("list budgets", c.get("/api/budgets", headers=H(A)).status_code == 200, "")
    ok("list active budgets", c.get("/api/budgets", headers=H(A), params={"active_only": True}).status_code == 200, "")
    r = c.get("/api/budgets/summary/all-currencies", headers=H(A))
    ok("multi-currency summary", r.status_code == 200, r.text[:200])
    r = c.post("/api/budgets/ai-suggest", headers=H(A), json={"period": "monthly", "start_date": iso(som), "currency": "usd", "analysis_months": 0})
    rec("ai-suggest analysis_months=0", "INFO", f"{r.status_code} {r.text[:150]}")
    r = c.post("/api/budgets", headers=H(A), json={
        "name": "Weekly", "period": "weekly", "start_date": iso(now), "currency": "usd", "total_budget": 50,
        "category_budgets": [{"main_category": "Transportation", "allocated_amount": 50}]})
    ok("create weekly budget", r.status_code == 200, r.text[:200])
    r = c.post("/api/budgets", headers=H(A), json={
        "name": "Custom", "period": "custom", "start_date": iso(now), "currency": "usd", "total_budget": 50,
        "category_budgets": [{"main_category": "Transportation", "allocated_amount": 50}]})
    ok("custom budget without end_date rejected", 400 <= r.status_code < 500, f"{r.status_code} {r.text[:150]}")
    r = c.post("/api/budgets", headers=H(A), json={
        "name": "Backwards", "period": "custom", "start_date": iso(now), "end_date": iso(now - timedelta(days=5)), "currency": "usd",
        "total_budget": 50, "category_budgets": [{"main_category": "Transportation", "allocated_amount": 50}]})
    ok("custom budget with end before start rejected", 400 <= r.status_code < 500, f"{r.status_code} {r.text[:150]}")


# ------------------------------------------------------------------ GOALS
def t_goals():
    section("Goals")
    A = S["A"]
    before = bal(A)
    r = c.post("/api/goals", headers=H(A), json={"name": "Bike", "target_amount": 300, "goal_type": "savings",
                                                  "initial_contribution": 100, "currency": "usd",
                                                  "target_date": iso(now + timedelta(days=7))})
    ok("create goal w/ initial contribution", r.status_code == 200, r.text)
    gid = r.json()["id"]
    S["goal_id"] = gid
    b = bal(A)
    ok("available balance reduced by allocation", abs(b["available_balance"] - (before["available_balance"] - 100)) < 1e-9, f"{before} -> {b}")

    r = c.post(f"/api/goals/{gid}/contribute", headers=H(A), json={"amount": 50})
    ok("contribute 50", r.status_code == 200 and abs(r.json()["current_amount"] - 150) < 1e-9, r.text)
    r = c.post(f"/api/goals/{gid}/contribute", headers=H(A), json={"amount": 10_000})
    ok("over-contribution rejected", r.status_code == 400, f"{r.status_code} {r.text[:120]}")
    r = c.post(f"/api/goals/{gid}/contribute", headers=H(A), json={"amount": -1000})
    ok("over-withdrawal rejected", r.status_code == 400, f"{r.status_code} {r.text[:120]}")
    r = c.post(f"/api/goals/{gid}/contribute", headers=H(A), json={"amount": -50})
    ok("withdraw 50", r.status_code == 200 and abs(r.json()["current_amount"] - 100) < 1e-9, r.text)

    pre = bal(A)["available_balance"]
    r = c.post("/api/goals", headers=H(A), json={"name": "Neg", "target_amount": 100, "goal_type": "savings",
                                                  "initial_contribution": -1000, "currency": "usd"})
    post = bal(A)["available_balance"]
    bug("negative initial_contribution accepted and inflates available balance", r.status_code == 200 and post > pre,
        f"{r.status_code} available {pre} -> {post}")
    if r.status_code == 200:
        c.delete(f"/api/goals/{r.json()['id']}", headers=H(A))
    r = c.post("/api/goals", headers=H(A), json={"name": "Null", "target_amount": 100, "goal_type": "savings",
                                                  "initial_contribution": None, "currency": "usd"})
    bug("initial_contribution=null -> 500", r.status_code == 500, f"{r.status_code} {r.text[:120]}")
    if r.status_code == 200:
        c.delete(f"/api/goals/{r.json()['id']}", headers=H(A))
    r = c.post("/api/goals", headers=H(A), json={"name": "Zero", "target_amount": 0, "goal_type": "savings", "currency": "usd"})
    bug("goal with target_amount=0 accepted", r.status_code == 200, f"{r.status_code} {r.text[:120]}")
    if r.status_code == 200:
        c.delete(f"/api/goals/{r.json()['id']}", headers=H(A))

    r = c.post("/api/goals", headers=H(A), json={"name": "Cents", "target_amount": 0.3, "goal_type": "savings",
                                                  "initial_contribution": 0.1, "currency": "usd"})
    g2 = r.json()["id"]
    r = c.post(f"/api/goals/{g2}/contribute", headers=H(A), json={"amount": 0.2})
    bug("cannot complete 0.3 goal with 0.1 + 0.2 (float compare)", r.status_code != 200, f"{r.status_code} {r.text[:150]}")
    c.delete(f"/api/goals/{g2}", headers=H(A))

    r = c.post(f"/api/goals/{gid}/contribute", headers=H(A), json={"amount": 200})
    ok("reaching target marks achieved", r.status_code == 200 and r.json()["status"] == "achieved", r.text[:200])
    c.post(f"/api/goals/{gid}/contribute", headers=H(A), json={"amount": -200})
    g = c.get(f"/api/goals/{gid}", headers=H(A)).json()
    ok("withdrawing from achieved goal reverts to active", g["status"] == "active", g["status"])

    r = c.put(f"/api/goals/{gid}", headers=H(A), json={"target_amount": 50})
    rec("lower target below current amount", "INFO", f"{r.status_code} {r.text[:200]}")
    c.put(f"/api/goals/{gid}", headers=H(A), json={"target_amount": 300})

    ok("goals list", c.get("/api/goals", headers=H(A)).status_code == 200, "")
    ok("goals summary", c.get("/api/goals/summary", headers=H(A)).status_code == 200, "")
    r = c.get("/api/goals/summary/all-currencies", headers=H(A))
    bug("/api/goals/summary/all-currencies shadowed by /{goal_id}", r.status_code == 404, f"{r.status_code} {r.text[:120]}")
    ok("B cannot contribute to A's goal", c.post(f"/api/goals/{gid}/contribute", headers=H(S["B"]), json={"amount": 1}).status_code == 404, "")
    ok("B cannot delete A's goal", c.delete(f"/api/goals/{gid}", headers=H(S["B"])).status_code == 404, "")

    t = tx(A, type="inflow", main_category="Employment Income", sub_category="Salary", amount=10, currency="thb").json()
    g = c.post("/api/goals", headers=H(A), json={"name": "THB", "target_amount": 100, "goal_type": "savings",
                                                 "initial_contribution": 10, "currency": "thb"}).json()
    r = c.delete(f"/api/transactions/{t['id']}", headers=H(A))
    rec("delete goal-funded inflow", "INFO", f"{r.status_code} {r.text[:150]}")
    bug("deleting funded inflow leaves negative available balance (no guard)", bal(A, "thb").get("available_balance", 0) < 0,
        bal(A, "thb"))
    r = c.put(f"/api/transactions/{t['id']}", headers=H(A), json={"amount": 5})
    bug("lowering a goal-funded inflow below allocations accepted", r.status_code == 200, f"{r.status_code} {r.text[:120]}")
    r = c.delete(f"/api/goals/{g['id']}", headers=H(A))
    ok("delete goal", r.status_code == 200, r.status_code)
    ok("deleting goal releases allocation", bal(A, "thb").get("available_balance", 0) >= 0, bal(A, "thb"))
    c.delete(f"/api/transactions/{t['id']}", headers=H(A))

    # concurrent contributions to different goals must not over-allocate
    import concurrent.futures
    cur = "mmk"
    avail = bal(A, cur)["available_balance"]
    g1 = c.post("/api/goals", headers=H(A), json={"name": "C1", "target_amount": avail * 2, "goal_type": "savings", "currency": cur}).json()["id"]
    g2 = c.post("/api/goals", headers=H(A), json={"name": "C2", "target_amount": avail * 2, "goal_type": "savings", "currency": cur}).json()["id"]
    amt = round(avail * 0.8, 2)

    def contrib(gid):
        with httpx.Client(base_url=BASE, timeout=60) as cc:
            return cc.post(f"/api/goals/{gid}/contribute", headers=H(A), json={"amount": amt}).status_code
    with concurrent.futures.ThreadPoolExecutor(4) as ex:
        codes = list(ex.map(contrib, [g1, g2, g1, g2]))
    after = bal(A, cur)["available_balance"]
    bug("parallel contributions over-allocate the balance", after < -1e-6, f"codes={codes} available={after}")
    c.delete(f"/api/goals/{g1}", headers=H(A))
    c.delete(f"/api/goals/{g2}", headers=H(A))


# ------------------------------------------------------------------ RECURRING (API part)
def t_recurring_setup():
    section("Recurring transactions (API)")
    A = S["A"]
    r = c.post("/api/transactions/preview-recurrence", headers=H(A),
               json={"start_date": iso(datetime(2027, 1, 31, tzinfo=UTC)), "frequency": "monthly", "day_of_month": 31})
    ok("preview monthly from Jan 31 clamps to month end", r.status_code == 200 and "2027-02-28" in r.text, r.text[:300])
    r = c.post("/api/transactions/preview-recurrence", headers=H(A),
               json={"start_date": iso(now), "frequency": "annually", "month": 13, "day_of_year": 1})
    bug("annual recurrence with month=13 -> 500 instead of 422", r.status_code == 500, f"{r.status_code} {r.text[:150]}")
    r = c.post("/api/transactions/preview-recurrence", headers=H(A),
               json={"start_date": iso(now), "frequency": "weekly", "day_of_week": 9})
    bug("weekly recurrence with day_of_week=9 -> 500 instead of 422", r.status_code == 500, f"{r.status_code} {r.text[:150]}")

    start = now - timedelta(days=3)
    r = tx(A, type="outflow", main_category="Housing & Utilities", sub_category="Rent", amount=5, date=iso(start),
           recurrence={"enabled": True, "config": {"frequency": "daily"}})
    ok("create daily recurring tx", r.status_code == 200, r.text)
    S["rec_parent"] = r.json()["id"]
    marker = datetime(2026, 1, 1, tzinfo=UTC)
    db.transactions.update_one({"_id": S["rec_parent"]}, {"$set": {"recurrence.last_created_date": now - timedelta(days=3)}})
    r = c.put(f"/api/transactions/{S['rec_parent']}", headers=H(A), json={
        "description": "rent edited",
        "recurrence": {"enabled": True, "config": {"frequency": "daily"}, "last_created_date": iso(marker)}})
    stored = db.transactions.find_one({"_id": S["rec_parent"]})["recurrence"].get("last_created_date")
    bug("client can overwrite server-managed last_created_date when editing a recurring tx (duplicates)",
        r.status_code == 200 and stored is not None and stored.year == 2026 and stored.month == 1 and stored.day == 1,
        f"PUT {r.status_code}, stored last_created_date={stored}")
    bal(A)  # warm the balance cache so the job test can detect staleness
    S["bal_before_job"] = bal(A)["balance"]


# ------------------------------------------------------------------ REPORTS
def t_reports():
    section("Reports")
    A = S["A"]
    for p in ("week", "month", "year"):
        r = c.post("/api/reports/generate", headers=H(A), json={"period": p, "currency": "usd"})
        ok(f"report {p}", r.status_code == 200, r.text[:200])
    r = c.post("/api/reports/generate", headers=H(A), json={"period": "custom", "start_date": iso(now - timedelta(days=5)),
                                                            "end_date": iso(now), "currency": "usd"})
    ok("custom report", r.status_code == 200, r.text[:200])
    if r.status_code == 200:
        j = r.json()
        rec("custom report totals", "INFO", f"in={j['total_inflow']} out={j['total_outflow']} net={j['net_balance']}")
    r = c.post("/api/reports/generate", headers=H(A), json={"period": "custom"})
    bug("custom report without dates -> 500 (wraps the intended 400)", r.status_code == 500, f"{r.status_code} {r.text[:120]}")
    r = c.post("/api/reports/generate-multi-currency", headers=H(A), json={"period": "month"})
    ok("multi-currency report", r.status_code == 200 and len(r.json()["currency_reports"]) >= 2, r.text[:200])
    r = c.post("/api/reports/download", headers=H(A), json={"period": "month", "currency": "usd"})
    bug("PDF download 500s when user name contains '<' (ReportLab markup)", r.status_code == 500, f"{r.status_code}")
    c.put("/api/auth/profile", headers=H(A), json={"name": "Alice"})
    r = c.post("/api/reports/download", headers=H(A), json={"period": "month", "currency": "usd"})
    ok("PDF download", r.status_code == 200 and r.content[:4] == b"%PDF", f"{r.status_code} {r.text[:150]}")
    r = c.post("/api/reports/download", headers=H(A), json={"period": "month"})
    ok("PDF download (all currencies)", r.status_code == 200 and r.content[:4] == b"%PDF", f"{r.status_code} {r.text[:150]}")
    r = c.post("/api/reports/download", headers=H(A), json={"period": "month", "currency": "usd", "timezone_offset": 2000})
    bug("timezone_offset=2000 -> 500", r.status_code == 500, r.status_code)
    r = c.post("/api/reports/download", headers=H(S["B"]), json={"period": "month"})
    ok("PDF requires premium", r.status_code == 403, r.status_code)
    r = c.post("/api/reports/generate", headers=H(S["B"]), json={"period": "month", "currency": "usd"})
    ok("empty-data report for new user", r.status_code == 200 and r.json()["total_transactions"] == 0, r.text[:200])


# ------------------------------------------------------------------ NOTIFICATIONS / AI
def t_notifications():
    section("Notifications")
    A = S["A"]
    r = c.get("/api/notifications/preferences", headers=H(A))
    ok("get prefs", r.status_code == 200, r.text[:200])
    prefs = r.json()["preferences"]
    key = next(iter(prefs))
    r = c.put("/api/notifications/preferences", headers=H(A), json={"preferences": {key: False}})
    ok("update prefs", r.status_code == 200 and r.json()["preferences"][key] is False, r.text[:200])
    r = c.put("/api/notifications/preferences", headers=H(A), json={"preferences": {"not_a_pref": "banana"}})
    bug("unknown/invalid preference keys accepted and stored", r.status_code == 200 and "not_a_pref" in str(db.notification_preferences.find_one({"user_id": S["A_id"]})), r.status_code)
    r = c.post("/api/notifications/preferences/reset", headers=H(A))
    ok("reset prefs", r.status_code == 200, r.text[:100])
    r = c.post("/api/auth/update-fcm-token", headers=H(A), json={"fcm_token": "tok-alice"})
    ok("update fcm token", r.status_code == 200, r.text)
    r = c.post("/api/auth/update-fcm-token", headers=H(A), json={})
    bug("update-fcm-token with missing field -> 500", r.status_code == 500, r.status_code)
    c.post("/api/auth/update-fcm-token", headers=H(S["B"]), json={"fcm_token": "tok-alice"})
    a_tok = db.users.find_one({"_id": S["A_id"]}).get("fcm_token")
    bug("same device token stays on two accounts (pushes leak across accounts)", a_tok == "tok-alice", f"alice token={a_tok}")
    r = c.delete("/api/auth/fcm-token", headers=H(S["B"]))
    b_tok = db.users.find_one({"_id": S["B_id"]}).get("fcm_token")
    ok("DELETE /api/auth/fcm-token clears the token on logout", r.status_code == 200 and not b_tok, f"{r.status_code} token={b_tok}")
    c.post("/api/auth/update-fcm-token", headers=H(A), json={"fcm_token": "tok-alice"})

    r = c.get("/api/notifications", headers=H(A))
    ok("list notifications", r.status_code == 200, r.text[:200])
    notes = r.json()
    rec("notifications so far", "INFO", [n["type"] for n in notes])
    r = c.get("/api/notifications/unread-count", headers=H(A))
    ok("unread count", r.status_code == 200, r.text)
    if notes:
        nid = notes[0]["id"]
        r1 = c.post(f"/api/notifications/{nid}/mark-read", headers=H(A))
        r2 = c.post(f"/api/notifications/{nid}/mark-read", headers=H(A))
        bug("marking an already-read notification returns 404", r1.status_code == 200 and r2.status_code == 404, f"{r1.status_code},{r2.status_code}")
        ok("B cannot delete A's notification", c.delete(f"/api/notifications/{nid}", headers=H(S["B"])).status_code == 404, "")
        ok("delete notification", c.delete(f"/api/notifications/{nid}", headers=H(A)).status_code == 200, "")
    r = c.post("/api/notifications/mark-all-read", headers=H(A))
    ok("mark all read", r.status_code == 200, r.text)
    r = c.post("/api/notifications/analyze-spending", headers=H(A))
    ok("analyze spending", r.status_code == 200, r.text[:200])


def t_ai():
    section("AI chat / insights (AI stubbed)")
    A = S["A"]
    def frames_of(resp):
        return [json.loads(l[6:]) for l in resp.text.split("\n") if l.startswith("data: ")]

    r = c.post("/api/chat/stream", headers=H(A), json={"message": "How much did I spend?"})
    fr = frames_of(r) if r.status_code == 200 else []
    ok("chat stream (fake OpenAI) streams chunks and a done frame",
       r.status_code == 200 and len(fr) >= 2 and fr[-1].get("done") and "Fake answer" in (fr[-1].get("full_response") or ""),
       f"{r.status_code} {str(fr[-1:])[:250]}")
    rec("chat stream content-type", "INFO", r.headers.get("content-type"))
    r = c.post("/api/chat/stream", headers=H(A), json={"message": "second", "chat_history": [
        {"role": "user", "content": "How much did I spend?"}, {"role": "assistant", "content": "INJECTED FAKE ASSISTANT"}]})
    r = c.post("/api/chat/stream", headers=H(A), json={"message": "third"})
    h = c.get("/api/chat/history", headers=H(A), params={"limit": 50}).json()
    bug("server chat history overwritten by client-sent history (sending none wipes it)", len(h) < 6,
        f"{len(h)} stored messages after 3 exchanges")
    bug("client-supplied assistant messages persisted into server history", any("INJECTED" in (m.get("content") or "") for m in h), "")

    r = c.post("/api/chat/stream", headers=H(A), json={"message": "hi", "ai_provider": "gemini"})
    if r.status_code == 200:
        fr = frames_of(r)
        last = fr[-1] if fr else {}
        bug("Gemini failure not surfaced as an error frame", "error" not in last, str(last)[:250])
        h2 = c.get("/api/chat/history", headers=H(A), params={"limit": 50}).json()
        bug("failed AI exchange persisted into chat history", len(h2) != len(h), f"{len(h)} -> {len(h2)}")
    else:
        rec("gemini stream", "INFO", f"{r.status_code} {r.text[:150]}")
    r = c.post("/api/chat", headers=H(A), json={"message": "x"})
    ok("deprecated /api/chat -> 410", r.status_code == 410, r.status_code)
    ok("chat history", c.get("/api/chat/history", headers=H(A)).status_code == 200, "")
    ok("clear chat history", c.delete("/api/chat/history", headers=H(A)).status_code == 200, "")

    r = c.get("/api/insights", headers=H(A), params={"insight_type": "weekly"})
    ok("GET weekly insight (fake OpenAI)", r.status_code == 200 and r.json().get("content"), f"{r.status_code} {r.text[:200]}")
    r = c.get("/api/insights", headers=H(A), params={"insight_type": "monthly"})
    ok("GET monthly insight (fake OpenAI)", r.status_code == 200 and r.json().get("content"), f"{r.status_code} {r.text[:300]}")
    r = c.post("/api/insights/translate-myanmar", headers=H(A), params={"insight_type": "monthly"})
    mm = db.insights.find_one({"user_id": S["A_id"], "insight_type": "monthly", "ai_provider": "openai"}, sort=[("generated_at", -1)])
    ok("translate-myanmar translates the requested (monthly) insight", r.status_code == 200 and mm and mm.get("content_mm"),
       f"{r.status_code} {r.text[:150]}")
    r = c.post("/api/transactions/extract-from-text", headers=H(A), json={"text": "coffee 3 dollars"})
    rec("extract-from-text (AI stubbed)", "INFO", f"{r.status_code} {r.text[:150]}")
    r = c.post("/api/transactions/extract-from-text", headers=H(S["B"]), json={"text": "coffee"})
    ok("extract-from-text requires premium", r.status_code == 403, r.status_code)

    r = c.post("/api/transactions/batch-create", headers=H(A), json=[
        {"type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Coffee & Snacks", "date": iso(now), "amount": 3, "currency": "usd"},
        {"type": "outflow", "main_category": "Transportation", "sub_category": "Taxi", "date": iso(now), "amount": 7, "currency": "usd"}])
    ok("batch create", r.status_code == 200 and len(r.json()) == 2, f"{r.status_code} {r.text[:200]}")
    r = c.post("/api/transactions/batch-create", headers=H(A), json=[])
    rec("batch create empty list", "INFO", f"{r.status_code} {r.text[:120]}")


def t_feedback_versions():
    section("Feedback & app version check")
    r = c.post("/api/feedback", headers=H(S["A"]), json={"category": "bug", "message": "e2e", "rating": 99})
    bug("feedback rating=99 accepted (should be 1-5)", r.status_code == 200, r.status_code)
    S["fb_id"] = r.json().get("id") if r.status_code == 200 else None
    r = c.post("/api/feedback", headers=H(S["A"]), json={"category": "bug", "message": ""})
    bug("empty feedback message accepted", r.status_code == 200, r.status_code)
    r = c.post("/api/app/check-version", json={"current_version": "1.0.0", "platform": "android"})
    rec("check-version without auth", "INFO", f"{r.status_code} {r.text[:100]}")
    r = c.post("/api/app/check-version", headers=H(S["A"]), json={"current_version": "1.0.0", "platform": "android"})
    ok("check-version with no versions published", r.status_code == 200, f"{r.status_code} {r.text[:200]}")


# ------------------------------------------------------------------ ADMIN
def t_admin():
    section("Admin")
    r = c.post("/api/admin/login", json={"email": "admin@toepwar.com", "password": "admin123"})
    bug("default super-admin admin@toepwar.com/admin123 auto-created and usable", r.status_code == 200, "")
    r = c.post("/api/admin/login", json={"email": "root-admin@example.com", "password": "e2e-root-admin-pass"})
    ok("bootstrap super-admin from env can log in", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
    if r.status_code != 200:
        return
    AD = r.json()["access_token"]
    S["AD_tok"] = AD
    bad = [c.post("/api/admin/login", json={"email": "root-admin@example.com", "password": f"x{i}"}).status_code for i in range(8)]
    r = c.post("/api/admin/login", json={"email": "root-admin@example.com", "password": "e2e-root-admin-pass"})
    bug("no lockout on admin login after repeated failures", r.status_code == 200, f"bad codes={bad}, correct-after={r.status_code}")

    ok("admin /me", c.get("/api/admin/me", headers=H(AD)).status_code == 200, "")
    r = c.get("/api/auth/me", headers=H(AD))
    ok("admin token rejected on user API", r.status_code == 401, r.status_code)
    r = c.get("/api/admin/users", headers=H(S["A"]))
    ok("user token rejected on admin API", r.status_code in (401, 403), r.status_code)

    r = c.get("/api/admin/users", headers=H(AD))
    ok("list users", r.status_code == 200 and len(r.json()) >= 2, r.text[:200])
    r = c.get("/api/admin/users", headers=H(AD), params={"search": "bob+flow"})
    bug("search for 'bob+flow' (literal +) finds nothing — regex not escaped", r.status_code == 200 and len(r.json()) == 0, r.text[:120])
    r = c.get("/api/admin/users", headers=H(AD), params={"search": "("})
    bug("search '(' -> 500 (raw $regex)", r.status_code == 500, f"{r.status_code}")
    r = c.get(f"/api/admin/users/{S['A_id']}", headers=H(AD))
    ok("user detail", r.status_code == 200, r.text[:200])
    r = c.get("/api/admin/users/nope", headers=H(AD))
    ok("user detail 404", r.status_code == 404, r.status_code)
    r = c.put(f"/api/admin/users/{S['B_id']}/subscription", headers=H(AD),
              json={"subscription_type": "premium", "subscription_expires_at": iso(now + timedelta(days=30))})
    ok("grant premium", r.status_code == 200, r.text[:200])
    r = c.get("/api/auth/subscription-status", headers=H(S["B"]))
    bug("subscription-status 500 after admin grants time-limited premium", r.status_code == 500, f"{r.status_code}")
    r = c.post("/api/reports/download", headers=H(S["B"]), json={"period": "month"})
    ok("admin-granted premium unlocks premium endpoint", r.status_code == 200, r.status_code)

    for path in ("/api/admin/stats/users", "/api/admin/stats/system", "/api/admin/broadcast-stats",
                 "/api/admin/ai-usage/stats", "/api/admin/ai-usage/users", "/api/admin/ai-usage/stats/budgets",
                 "/api/admin/ai-usage/stats/transactions", "/api/admin/logs", "/api/admin/feedback", "/api/admin/admins",
                 f"/api/admin/ai-usage/user/{S['A_id']}", "/api/admin/app-versions"):
        r = c.get(path, headers=H(AD))
        ok(f"GET {path}", r.status_code == 200, f"{r.status_code} {r.text[:200]}")

    r = c.post("/api/admin/admins", headers=H(AD), json={"name": "Mod", "email": "mod@example.com", "password": "modpass1", "role": "moderator"})
    ok("create moderator", r.status_code == 200, r.text[:200])
    MT = c.post("/api/admin/login", json={"email": "mod@example.com", "password": "modpass1"}).json().get("access_token")
    S["MT_tok"] = MT
    codes = {p: c.get(p, headers=H(MT)).status_code for p in ("/api/admin/stats/users", "/api/admin/users", "/api/admin/feedback", "/api/admin/app-versions")}
    bug("moderator role can't access any admin data (role is useless)", all(v == 403 for v in codes.values()), codes)
    r = c.get("/api/admin/admins", headers=H(MT))
    ok("moderator can't list admins", r.status_code == 403, r.status_code)

    r = c.post("/api/admin/broadcast-notification", headers=H(AD),
               json={"title": "Promo", "message": "hi", "target_users": "all", "notification_type": "promo"})
    ok("broadcast with unknown notification_type rejected (422)", r.status_code == 422, f"{r.status_code} {r.text[:150]}")
    db.notifications.insert_one({"_id": "legacy-promo", "user_id": S["A_id"], "type": "promo", "title": "old", "message": "old",
                                 "created_at": now, "is_read": False})
    r = c.get("/api/notifications", headers=H(S["A"]))
    bug("a stored notification with an unknown type makes GET /api/notifications 500", r.status_code == 500, f"{r.status_code}")
    db.notifications.delete_many({"type": "promo"})
    r = c.get("/api/admin/feedback/stats", headers=H(AD))
    ok("GET /api/admin/feedback/stats", r.status_code == 200 and "total" in r.json(), f"{r.status_code} {r.text[:150]}")
    r = c.get("/api/admin/ai-usage/users", headers=H(AD), params={"start_date": iso(now - timedelta(days=1)), "end_date": iso(now)})
    ok("ai-usage/users accepts a date range", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
    r = c.post("/api/admin/broadcast-notification", headers=H(AD),
               json={"title": "Hello", "message": "hi", "target_users": "premium"})
    ok("broadcast (default type)", r.status_code == 200, r.text[:200])
    rec("broadcast result", "INFO", r.text[:200])
    r = c.get("/api/notifications", headers=H(S["A"]))
    ok("user list after normal broadcast", r.status_code == 200 and any(n["title"] == "Hello" for n in r.json()), f"{r.status_code} {r.text[:150]}")
    r = c.post("/api/admin/broadcast-notification", headers=H(AD), json={"title": "x", "message": "y", "target_users": "martians"})
    ok("broadcast to invalid target rejected", 400 <= r.status_code < 500, f"{r.status_code} {r.text[:120]}")

    if S.get("fb_id"):
        r1 = c.put(f"/api/admin/feedback/{S['fb_id']}/status", headers=H(AD), params={"status_update": "reviewed"})
        r2 = c.put(f"/api/admin/feedback/{S['fb_id']}/status", headers=H(AD), params={"status_update": "reviewed"})
        bug("setting feedback to its current status -> 404", r1.status_code == 200 and r2.status_code == 404, f"{r1.status_code},{r2.status_code}")

    r = c.post("/api/admin/app-versions", headers=H(AD), json={"version": "2.0.0", "platform": "all", "download_url": "https://x/2.0",
                                                                "is_force_update": True, "min_supported_version": "1.5.0"})
    ok("publish 2.0.0 forced", r.status_code in (200, 201), r.text[:200])
    v2 = r.json().get("id")
    r = c.post("/api/admin/app-versions", headers=H(AD), json={"version": "2.0.0", "platform": "all", "download_url": "https://x/dup"})
    ok("duplicate version rejected", 400 <= r.status_code < 500, f"{r.status_code} {r.text[:120]}")
    r = c.post("/api/app/check-version", headers=H(S["A"]), json={"current_version": "1.0.0", "platform": "android"})
    ok("1.0.0 forced to update", r.status_code == 200 and r.json()["force_update"] is True, r.text[:200])
    r = c.put(f"/api/admin/app-versions/{v2}", headers=H(AD), json={"min_supported_version": None})
    v = c.get(f"/api/admin/app-versions/{v2}", headers=H(AD)).json()
    bug("clearing min_supported_version via PUT null has no effect", v.get("min_supported_version") == "1.5.0", v.get("min_supported_version"))
    r = c.post("/api/admin/app-versions", headers=H(AD), json={"version": "2.1.0", "platform": "all", "download_url": "https://x/2.1",
                                                                "is_force_update": False})
    r = c.post("/api/app/check-version", headers=H(S["A"]), json={"current_version": "1.0.0", "platform": "android"})
    rec("1.0.0 after optional 2.1.0 (2.0.0 forced, min_supported 1.5.0 still set)", "INFO", r.text[:200])
    db.app_versions.update_one({"_id": v2}, {"$set": {"min_supported_version": None}})
    r = c.post("/api/app/check-version", headers=H(S["A"]), json={"current_version": "1.0.0", "platform": "android"})
    bug("user below a forced version (2.0.0) no longer forced once optional 2.1.0 ships",
        r.status_code == 200 and r.json()["force_update"] is False, r.text[:200])
    r = c.post("/api/app/check-version", headers=H(S["A"]), json={"current_version": "garbage", "platform": "android"})
    ok("check-version with malformed version doesn't 500", r.status_code != 500, f"{r.status_code} {r.text[:120]}")
    r = c.post("/api/app/check-version", headers=H(S["A"]), json={"current_version": "2.1.0", "platform": "android"})
    ok("2.1.0 is up to date", r.status_code == 200 and r.json()["is_up_to_date"] is True, r.text[:200])
    r = c.post("/api/app/check-version", headers=H(S["A"]), json={"current_version": "2.10.0", "platform": "android"})
    ok("2.10.0 compared numerically (newer than 2.1.0)", r.status_code == 200 and r.json()["is_up_to_date"] is True, r.text[:200])


def t_delete_account():
    section("Account deletion")
    tok, uid, _, _ = register_verified("Del", "del@example.com", "secret123")
    tx(tok, amount=5)
    c.post("/api/feedback", headers=H(tok), json={"category": "general", "message": "bye"})
    r = c.request("DELETE", "/api/auth/delete-account", headers=H(tok))
    ok("delete account without password rejected", r.status_code in (400, 401, 422), r.status_code)
    r = c.request("DELETE", "/api/auth/delete-account", headers=H(tok), json={"password": "wrong"})
    ok("delete account with wrong password rejected", r.status_code in (400, 401, 403), r.status_code)
    r = c.request("DELETE", "/api/auth/delete-account", headers=H(tok), json={"password": "secret123"})
    ok("delete account", r.status_code == 200, f"{r.status_code} {r.text[:200]}")
    left = {col: db[col].count_documents({"user_id": uid}) for col in ("transactions", "goals", "budgets", "feedback", "ai_usage", "notifications", "insights", "chat_sessions", "notification_preferences")}
    bug("user data left behind after self-delete", any(left.values()), left)
    tok2, uid2, _, _ = register_verified("Del2", "del@example.com", "secret123")
    r = c.get("/api/auth/me", headers=H(tok))
    bug("deleted account's old JWT authenticates as the NEW account with same email", r.status_code == 200, r.json().get("id") if r.status_code == 200 else r.status_code)


def latest_verify_token(email):
    """Pull the token from the most recent verification email sent to `email`."""
    from urllib.parse import urlparse, parse_qs
    import re as _re
    tok = None
    for _ in range(20):
        for line in open(os.path.join(HERE, "outbox.jsonl"), encoding="utf-8"):
            for link in _re.findall(r"https?://\S*verify-email\?[^\s\"\\]+", line):
                q = parse_qs(urlparse(link).query)
                if q.get("email", [""])[0] == email:
                    tok = q.get("token", [None])[0]
        if tok:
            return tok
        time.sleep(0.25)
    return tok


def t_regression():
    section("Regression checks for the fixes")
    # --- change password rotates the session token
    tok, uid, _, _ = register_verified("Rot", "rotate@example.com", "secret123")
    r = c.put("/api/auth/change-password", headers=H(tok),
              json={"current_password": "secret123", "new_password": "secret999", "confirm_password": "secret999"})
    new_tok = r.json().get("access_token") if r.status_code == 200 else None
    ok("change-password returns a fresh access_token", bool(new_tok), f"{r.status_code} {r.text[:150]}")
    if new_tok:
        ok("fresh token from change-password works immediately", c.get("/api/auth/me", headers=H(new_tok)).status_code == 200, "")
    ok("old token rejected after change-password", c.get("/api/auth/me", headers=H(tok)).status_code == 401, "")
    r = c.post("/api/auth/login", json={"email": "rotate@example.com", "password": "secret999"})
    ok("login right after password change works", r.status_code == 200, f"{r.status_code} {r.text[:120]}")

    # --- unverified account: login blocked, resend delivers a working link
    em = "late-verify@example.com"
    r = c.post("/api/auth/register", json={"name": "Late", "email": em, "password": "secret123"})
    reg_tok = r.json().get("access_token")
    ok("unverified register token gets 403 on /me", c.get("/api/auth/me", headers=H(reg_tok)).status_code == 403, "")
    r = c.post("/api/auth/login", json={"email": em, "password": "secret123"})
    ok("unverified login returns 403 'Email not verified'-style error", r.status_code == 403, f"{r.status_code} {r.text[:120]}")
    first = latest_verify_token(em)
    time.sleep(61) if os.environ.get("E2E_SLOW") else None
    r = c.post("/api/auth/resend-verification", json={"email": em})
    ok("resend-verification returns 200", r.status_code == 200, f"{r.status_code} {r.text[:120]}")
    tok_now = latest_verify_token(em)
    for _ in range(20):  # resend mails from a background task; wait for the new token
        if tok_now != first:
            break
        time.sleep(0.25)
        tok_now = latest_verify_token(em)
    rec("resend within 1 minute of register", "INFO", "new token issued" if tok_now != first else "rate-limited (same token) — expected within 60s")
    r = c.get("/api/auth/verify-email", params={"email": em, "token": tok_now})
    ok("verification link (latest) verifies the account", r.status_code == 200, f"{r.status_code} {r.text[:120]}")
    r = c.post("/api/auth/login", json={"email": em.upper(), "password": "secret123"})
    ok("login works with different email casing", r.status_code == 200, f"{r.status_code} {r.text[:120]}")
    if r.status_code == 200:
        ok("/login user payload includes language field", "language" in r.json()["user"], r.json()["user"])

    # --- full password reset invalidates old sessions and works end to end
    r = c.post("/api/auth/login", json={"email": em, "password": "secret123"})
    t_old = r.json()["access_token"]
    c.post("/api/auth/forgot-password/request-otp", json={"email": em})
    otp = None
    for _ in range(20):
        otp = latest_otp(em)
        if otp:
            break
        time.sleep(0.25)
    r = c.post("/api/auth/forgot-password/verify-otp", json={"email": em, "otp": otp})
    ok("OTP from email verifies", r.status_code == 200, f"{r.status_code} {r.text[:120]}")
    rt = r.json().get("reset_token") if r.status_code == 200 else None
    r = c.post("/api/auth/forgot-password/reset-password",
               json={"email": em, "reset_token": rt, "new_password": "brandnew1", "confirm_password": "brandnew1"})
    ok("reset password", r.status_code == 200, f"{r.status_code} {r.text[:120]}")
    ok("session from before the reset is revoked", c.get("/api/auth/me", headers=H(t_old)).status_code == 401, "")
    ok("login with reset password", c.post("/api/auth/login", json={"email": em, "password": "brandnew1"}).status_code == 200, "")

    # --- moderator is read-only
    MT, AD = S.get("MT_tok"), S.get("AD_tok")
    if MT:
        r = c.post("/api/admin/broadcast-notification", headers=H(MT), json={"title": "m", "message": "m", "target_users": "all"})
        ok("moderator cannot broadcast", r.status_code == 403, r.status_code)
        r = c.put(f"/api/admin/users/{S['A_id']}/subscription", headers=H(MT), json={"subscription_type": "free"})
        ok("moderator cannot change subscriptions", r.status_code == 403, r.status_code)
    if AD:
        r = c.get("/api/admin/feedback", headers=H(AD), params={"status": "reviewed"})
        ok("feedback list filters by status", r.status_code == 200 and all(f["status"] == "reviewed" for f in r.json()), f"{r.status_code} {r.text[:150]}")
        r = c.get("/api/admin/ai-usage/stats", headers=H(AD))
        ok("AI usage recorded from fake chats/insights", r.status_code == 200 and (r.json().get("total_requests") or 0) > 0, f"{r.status_code} {r.text[:150]}")
        r = c.get("/api/admin/users", headers=H(AD), params={"search": "bob+flow"})
        ok("admin search finds literal 'bob+flow'", r.status_code == 200 and len(r.json()) == 1, r.text[:150])

    # --- reports honour timezone offset; audio language validation
    A = S["A"]
    r = c.post("/api/reports/generate", headers=H(A), json={"period": "month", "currency": "usd", "timezone_offset": 390})
    ok("month report with Myanmar offset (+390)", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
    r = c.post("/api/reports/generate", headers=H(A), json={"period": "week", "currency": "usd", "timezone_offset": -480})
    ok("week report with negative offset", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
    r = c.post("/api/transactions/transcribe-audio", headers=H(A), files={"audio": ("a.m4a", b"\x00\x01", "audio/mp4")}, data={"language": "fr"})
    ok("transcribe-audio rejects unsupported language", r.status_code == 400, f"{r.status_code} {r.text[:120]}")

    # --- budgets: weekly/yearly create + list works and summary consistent
    som = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    r = c.post("/api/budgets", headers=H(A), json={
        "name": "Year", "period": "yearly", "start_date": iso(som.replace(month=1)), "currency": "usd", "total_budget": 5000,
        "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 3000},
                             {"main_category": "Transportation", "allocated_amount": 2000}]})
    ok("yearly budget create", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
    if r.status_code == 200:
        b = r.json()
        ok("yearly budget end is Dec 31", b["end_date"][:10].endswith("12-31"), b["end_date"])
        ok("yearly budget counts this year's food+transport spend", b["total_spent"] > 0, b["total_spent"])
    r = c.get("/api/budgets/summary/all-currencies", headers=H(A))
    ok("multi-currency budget summary after changes", r.status_code == 200, r.text[:150])

    # --- batch-create from AI extraction with a category the extractor might output
    r = c.post("/api/transactions/batch-create", headers=H(A), json=[
        {"type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Restaurants", "date": iso(now), "amount": 9.99, "currency": "usd"}])
    ok("batch-create with valid category", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
    r = c.post("/api/transactions/batch-create", headers=H(A), json=[
        {"type": "outflow", "main_category": "Food & Daily Living", "sub_category": "Restaurants", "date": iso(now), "amount": 1, "currency": "usd"},
        {"type": "outflow", "main_category": "Food", "sub_category": "Lunch", "date": iso(now), "amount": 1, "currency": "usd"}])
    rec("batch-create with one invalid category", "INFO", f"{r.status_code} {r.text[:160]}")
    n_after = db.transactions.count_documents({"user_id": S["A_id"], "amount": 1})
    ok("invalid batch is all-or-nothing (no partial insert)", r.status_code == 200 or n_after == 0, f"status={r.status_code}, rows with amount 1: {n_after}")


if __name__ == "__main__":
    for fn in (t_auth, t_forgot, t_subscription, t_transactions, t_budgets, t_goals, t_recurring_setup, t_reports,
               t_notifications, t_ai, t_feedback_versions, t_admin, t_regression, t_delete_account):
        run(fn)
    json.dump({"results": RESULTS, "state": {k: v for k, v in S.items() if isinstance(v, (str, int, float, list))}},
              open(os.path.join(HERE, "api_results.json"), "w"), indent=1, default=str)
    from collections import Counter
    print("\nSUMMARY:", Counter(r[2] for r in RESULTS))
