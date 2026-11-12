"""Goals summary counts achieved goals' money, so it agrees with the dashboard's
"set aside for goals" (allocated_to_goals sums every goal's current_amount).

Trip $100 of $800 (active), New laptop $1,500 of $1,500 (achieved), Emergency
$1,200 of $5,000 (active): the summary used to say $1,300 of $5,800 while
showing 3 goals; it must say $2,800 of $7,300.
"""
import os
import sys
import uuid
from datetime import datetime, UTC

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402,F401

import httpx  # noqa: E402

db = __import__("pgcompat").get_db()
c = httpx.Client(base_url="http://127.0.0.1:8765", timeout=60)
H = lambda t: {"Authorization": f"Bearer {t}"}
failures = 0


def check(ok, name, detail=""):
    global failures
    if not ok:
        failures += 1
    print(("[PASS] " if ok else "[BUG] ") + name + (f" -- {detail}" if detail and not ok else ""))


email = f"gs-{uuid.uuid4().hex[:6]}@example.com"
c.post("/api/auth/register", json={"name": "GS", "email": email, "password": "secret123"})
db.users.update_one({"email": email}, {"$set": {"is_verified": True}})
tok = c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json()["access_token"]

r = c.post("/api/transactions", headers=H(tok), json={
    "type": "inflow", "main_category": "Employment Income", "sub_category": "Salary", "amount": 5000,
    "currency": "usd", "date": datetime.now(UTC).isoformat(), "description": "salary"})
check(r.status_code == 200, "income recorded", f"{r.status_code} {r.text[:200]}")

goals = {}
for name, target, initial in [("Trip", 800, 100), ("New laptop", 1500, 1500), ("Emergency", 5000, 1200)]:
    r = c.post("/api/goals", headers=H(tok), json={
        "name": name, "target_amount": target, "initial_contribution": initial,
        "goal_type": "savings", "currency": "usd"})
    check(r.status_code == 200, f"goal {name} created", f"{r.status_code} {r.text[:200]}")
    goals[name] = r.json()
check(goals["New laptop"].get("status") == "achieved", "New laptop is achieved", goals["New laptop"])

balance = c.get("/api/dashboard/balance", headers=H(tok), params={"currency": "usd"}).json()
set_aside = balance.get("allocated_to_goals")
check(set_aside == 2800, "dashboard sets aside $2,800 for goals", balance)

s = c.get("/api/goals/summary", headers=H(tok), params={"currency": "usd"}).json()
check(s.get("total_allocated") == 2800 and s.get("total_target") == 7300,
      "/api/goals/summary: $2,800 of $7,300", s)
check(s.get("active_goals") == 2 and s.get("achieved_goals") == 1, "/api/goals/summary counts", s)
check(s.get("total_allocated") == set_aside, "/api/goals/summary agrees with the dashboard", s)

m = c.get("/api/goals/summary/all-currencies", headers=H(tok)).json()
usd = next((x for x in m.get("currency_summaries", []) if x.get("currency") == "usd"), {})
check(usd.get("total_allocated") == 2800 and usd.get("total_target") == 7300,
      "all-currencies USD: $2,800 of $7,300", usd)
check(usd.get("active_goals", 0) + usd.get("achieved_goals", 0) == 3, "all-currencies USD: 3 goals", usd)
check(abs((usd.get("overall_progress") or 0) - 2800 / 7300 * 100) < 0.01, "all-currencies USD progress", usd)
check(usd.get("total_allocated") == set_aside, "all-currencies agrees with the dashboard", usd)

# The AI assistant is told the same totals (in-process, against the same database).
import asyncio  # noqa: E402
import base64  # noqa: E402
import json  # noqa: E402


def _uid(token):
    payload = token.split(".")[1]
    return json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))["uid"]


async def _ai_context(uid):
    from ai_chatbot import FinancialDataProcessor, financial_chatbot
    proc = FinancialDataProcessor(uid)
    docs = await proc.create_financial_documents()
    texts = {d.metadata.get("type"): d.page_content for d in docs}
    goals_list = await proc.get_user_goals()
    summary = await proc.get_financial_summary()
    prompt = financial_chatbot._build_user_prompt(
        {"name": "GS"}, summary, {"goals_by_currency": {"usd": goals_list}}, None, "", "", "hi", "today")
    return texts, prompt


texts, prompt = asyncio.run(_ai_context(_uid(tok)))
overview = texts.get("goals_overview", "")
check("Total Allocated: $2,800.00" in overview and "Total Target: $7,300.00" in overview,
      "AI goals overview: $2,800 of $7,300", overview[:600])
summaries = "\n".join(t for k, t in texts.items() if k != "goals_overview")
check("Allocated to Goals: $2,800.00" in summaries, "AI financial summary sets aside $2,800", summaries[:800])
check("Allocated to Goals: $2,800.00" in prompt and "Available Balance: $2,200.00" in prompt,
      "AI prompt: $2,800 for goals, $2,200 available", prompt[:800])

print(f"\n{'ALL PASS' if failures == 0 else f'{failures} FAILED'}")
sys.exit(1 if failures else 0)
