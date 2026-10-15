"""Live checks for the backend-only round's review findings."""
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
c = httpx.Client(base_url="http://127.0.0.1:8765", timeout=120)
H = lambda t: {"Authorization": f"Bearer {t}"}
now = datetime.now(UTC)


def user(premium=False):
    email = f"r4-{uuid.uuid4().hex[:6]}@example.com"
    c.post("/api/auth/register", json={"name": "R4", "email": email, "password": "secret123"})
    upd = {"is_verified": True} | ({"subscription_type": "premium", "subscription_expires_at": None} if premium else {})
    db.users.update_one({"email": email}, {"$set": upd})
    return c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json()["access_token"], db.users.find_one({"email": email})["_id"]


async def rollover():
    import budget_service as bs
    stubenv.patch_loaded_modules()
    tok, uid = user()
    db.budgets.insert_one({"_id": "r4-parent-" + uid[:6], "user_id": uid, "name": "Groceries", "period": "monthly", "currency": "usd",
                           "start_date": now.replace(day=1) - timedelta(days=31), "end_date": now.replace(day=1) - timedelta(seconds=1),
                           "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 50}], "total_budget": 50,
                           "total_spent": 0, "remaining_budget": 50, "percentage_used": 0, "status": "completed", "is_active": False,
                           "auto_create_enabled": True, "created_at": now, "updated_at": now})
    await bs.process_due_budget_rollovers()
    kids = list(db.budgets.find({"user_id": uid, "parent_budget_id": {"$exists": True, "$ne": None}}))
    print("children after first rollover:", len(kids))
    if kids:
        r = c.delete(f"/api/budgets/{kids[0]['_id']}", headers=H(tok))
        print("user deletes the auto-created budget:", r.status_code)
    await bs.process_due_budget_rollovers()
    again = db.budgets.count_documents({"user_id": uid, "parent_budget_id": {"$exists": True, "$ne": None}})
    print(("[BUG]" if again else "[PASS]") + f" deleted auto-created budget recreated by the nightly job: {again}")


asyncio.run(rollover())

# GET insights when AI is down and the stored latest is a placeholder but the user now has data
tok, uid = user(premium=True)
db.insights.insert_one({"_id": "r4-ph-" + uid[:6], "user_id": uid, "ai_provider": "gemini", "insight_type": "weekly", "content": "## Welcome to Toe Pwar!",
                        "is_placeholder": True, "generated_at": now - timedelta(days=1)})
c.post("/api/transactions", headers=H(tok), json={"type": "outflow", "main_category": "Transportation", "sub_category": "Taxi",
                                                  "date": now.isoformat(), "amount": 5, "currency": "usd"})
r = c.get("/api/insights", headers=H(tok), params={"insight_type": "weekly", "ai_provider": "gemini"})
print(("[BUG]" if r.status_code >= 500 or r.status_code == 429 else "[PASS]") +
      f" GET insights with AI down returns {r.status_code} instead of the stored insight -- {r.text[:120]}")

# GET goals summary with unknown currency
r = c.get("/api/goals/summary", headers=H(tok), params={"currency": "zzz"})
print(("[BUG]" if r.status_code >= 500 else "[PASS]") + f" GET /api/goals/summary?currency=zzz -> {r.status_code}")

# Infinity / NaN JSON literals in request bodies
for body in ('{"type":"outflow","amount":Infinity}', '{"amount":NaN}'):
    r = c.post("/api/transactions", headers={**H(tok), "Content-Type": "application/json"}, content=body)
    print(("[BUG]" if r.status_code >= 500 else "[PASS]") + f" POST /api/transactions with {body} -> {r.status_code}")

# create_budget ignores client-sent spend fields
r = c.post("/api/budgets", headers=H(tok), json={"name": "Spoof", "period": "monthly", "start_date": now.replace(day=1).isoformat(), "currency": "usd",
                                                 "total_budget": 100, "category_budgets": [{"main_category": "Transportation", "allocated_amount": 100,
                                                                                            "spent_amount": 999, "percentage_used": 100, "is_exceeded": True}]})
cb = (r.json().get("category_budgets") or [{}])[0] if r.status_code == 200 else {}
print(("[BUG]" if cb.get("spent_amount", 0) >= 999 or cb.get("is_exceeded") is True and cb.get("spent_amount", 0) < 100 else "[PASS]")
      + f" create budget ignores client spent/percentage -> {r.status_code} {cb}")
