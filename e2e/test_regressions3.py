"""Does viewing the budgets list before the 09:00 job swallow the 'budget now active' notification?"""
import asyncio
import os
import sys
from datetime import datetime, timedelta, UTC

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402

os.chdir(stubenv.BACKEND)
import httpx  # noqa: E402
import notification_service as ns  # noqa: E402
from database import budgets_collection as B  # noqa: E402
N = __import__("pgcompat").async_collection("notifications")  # notifications live in PostgreSQL
U = __import__("pgcompat").async_collection("users")  # users live in PostgreSQL

stubenv.patch_loaded_modules()


async def main():
    c = httpx.AsyncClient(base_url="http://127.0.0.1:8765", timeout=60)
    # Own throwaway user (used to depend on a "carol" left over from older runs).
    import uuid
    email = f"r3n-{uuid.uuid4().hex[:6]}@example.com"
    await c.post("/api/auth/register", json={"name": "Carol", "email": email, "password": "secret123"})
    await U.update_one({"email": email}, {"$set": {"is_verified": True}})
    tok = (await c.post("/api/auth/login", json={"email": email, "password": "secret123"})).json()["access_token"]
    H = {"Authorization": f"Bearer {tok}"}
    carol = await U.find_one({"email": email})
    tomorrow = (datetime.now(UTC) + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
    r = await c.post("/api/budgets", headers=H, json={
        "name": "Starts soon", "period": "custom", "start_date": tomorrow.isoformat(), "end_date": (tomorrow + timedelta(days=10)).isoformat(),
        "currency": "usd", "total_budget": 50, "category_budgets": [{"main_category": "Transportation", "allocated_amount": 50}]})
    bid = r.json()["id"]
    print("created status:", r.json()["status"])
    # time passes: start date reached
    await B.update_one({"_id": bid}, {"$set": {"start_date": datetime.now(UTC) - timedelta(hours=1)}})
    # The notification is now "budget_now_active" (older code used "budget_started").
    STARTED = {"$in": ["budget_started", "budget_now_active"]}
    await N.delete_many({"user_id": carol["_id"], "type": STARTED})
    # user opens the Budgets screen before the scheduled job
    r = await c.get("/api/budgets", headers=H)
    print("status after list:", next(b["status"] for b in r.json() if b["id"] == bid))
    await ns.check_budget_period_notifications()
    n = await N.count_documents({"user_id": carol["_id"], "type": STARTED, "goal_id": bid})
    print(("[PASS]" if n == 1 else "[BUG]") + f" exactly one 'budget now active' notification after list view + job: {n}")
    await ns.check_budget_period_notifications()
    n2 = await N.count_documents({"user_id": carol["_id"], "type": STARTED, "goal_id": bid})
    print(("[PASS]" if n2 == 1 else "[BUG]") + f" a second job run doesn't send it again: {n2}")
    await c.delete(f"/api/budgets/{bid}", headers=H)


asyncio.run(main())
