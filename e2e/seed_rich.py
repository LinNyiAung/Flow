"""Reset the E2E database to a rich, known state for UI testing. Writes seed_accounts.json next to this file.

Usage: python seed_rich.py            (server must be running on 127.0.0.1:8765)
"""
import json
import os
import random
import time
import uuid
from datetime import datetime, timedelta, UTC

import httpx

HERE = os.path.dirname(os.path.abspath(__file__))
db = __import__("pgcompat").get_db()
c = httpx.Client(base_url="http://127.0.0.1:8765", timeout=120)
random.seed(7)

# wipe user data, keep categories/admins
for col in ("users", "transactions", "budgets", "goals", "notifications", "insights", "chat_sessions", "feedback",
            "notification_preferences", "ai_usage", "app_versions"):
    db[col].delete_many({})

ACCOUNTS = {
    "premium": {"name": "Maya Premium", "email": "maya@example.com", "password": "MayaPass123", "premium": True, "language": "en"},
    "free": {"name": "Felix Free", "email": "felix@example.com", "password": "FelixPass123", "premium": False, "language": "en"},
    "myanmar": {"name": "Aung Myanmar", "email": "aung@example.com", "password": "AungPass123", "premium": True, "language": "my"},
    "empty": {"name": "Nina New", "email": "nina@example.com", "password": "NinaPass123", "premium": False, "language": "en"},
    "deleteme": {"name": "Dee Delete", "email": "dee@example.com", "password": "DeePass1234", "premium": False, "language": "en"},
}
tokens = {}
for key, a in ACCOUNTS.items():
    r = c.post("/api/auth/register", json={"name": a["name"], "email": a["email"], "password": a["password"]})
    assert r.status_code == 200, r.text
    upd = {"is_verified": True, "language": a["language"]}
    if a["premium"]:
        upd |= {"subscription_type": "premium", "subscription_expires_at": datetime.now(UTC) + timedelta(days=200), "has_claimed_free_trial": True}
    db.users.update_one({"email": a["email"]}, {"$set": upd})
    tokens[key] = c.post("/api/auth/login", json={"email": a["email"], "password": a["password"]}).json()["access_token"]
    a["id"] = db.users.find_one({"email": a["email"]})["_id"]

now = datetime.now(UTC)
today = now.replace(hour=0, minute=0, second=0, microsecond=0)
OUT = [("Food & Daily Living", ["Groceries", "Restaurants", "Coffee & Snacks"]), ("Transportation", ["Taxi", "Fuel", "Public Transport"]),
       ("Housing & Utilities", ["Rent", "Electricity", "Internet"]), ("Entertainment & Leisure", ["Movies & Streaming", "Subscriptions"]),
       ("Shopping & Lifestyle", ["Clothing", "Electronics"]), ("Health & Insurance", ["Pharmacy", "Fitness & Gym"])]
INC = [("Employment Income", ["Salary", "Bonus"]), ("Self-Employment & Business", ["Freelance Income"])]


def tx(tok, t, main, sub, amount, cur, days_ago, desc, recurrence=None):
    body = {"type": t, "main_category": main, "sub_category": sub, "amount": round(amount, 2), "currency": cur,
            "date": (today - timedelta(days=days_ago) + timedelta(hours=random.randint(8, 20))).isoformat(), "description": desc}
    if recurrence:
        body["recurrence"] = recurrence
    r = c.post("/api/transactions", headers={"Authorization": f"Bearer {tok}"}, json=body)
    assert r.status_code == 200, r.text
    return r.json()["id"]


for key in ("premium", "free", "myanmar"):
    tok = tokens[key]
    big = key != "free"
    for m in range(4):
        tx(tok, "inflow", "Employment Income", "Salary", 3200 if big else 1500, "usd", 30 * m + 1, "Monthly salary")
    tx(tok, "inflow", "Self-Employment & Business", "Freelance Income", 640, "usd", 9, "Logo design")
    tx(tok, "inflow", "Employment Income", "Salary", 1_800_000, "mmk", 3, "MMK salary")
    for i in range(70 if big else 25):
        main, subs = random.choice(OUT)
        tx(tok, "outflow", main, random.choice(subs), random.uniform(3, 120), "usd", random.randint(0, 100), f"{main.split()[0].lower()} #{i}")
    for i in range(10):
        main, subs = random.choice(OUT)
        tx(tok, "outflow", main, random.choice(subs), random.uniform(5_000, 90_000), "mmk", random.randint(0, 40), f"mmk spend {i}")
    tx(tok, "outflow", "Housing & Utilities", "Rent", 900, "usd", 12, "Apartment rent",
       recurrence={"enabled": True, "config": {"frequency": "monthly", "day_of_month": (today - timedelta(days=12)).day}})
    tx(tok, "inflow", "Employment Income", "Bonus", 300, "thb", 5, "THB bonus")
    H = {"Authorization": f"Bearer {tok}"}
    som = today.replace(day=1)
    c.post("/api/budgets", headers=H, json={"name": "Monthly essentials", "period": "monthly", "start_date": som.isoformat(), "currency": "usd",
                                            "total_budget": 1500, "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 600},
                                                                                       {"main_category": "Transportation", "allocated_amount": 200},
                                                                                       {"main_category": "Entertainment & Leisure", "allocated_amount": 60}]})
    c.post("/api/budgets", headers=H, json={"name": "Weekly fun", "period": "weekly", "start_date": (today - timedelta(days=today.weekday())).isoformat(),
                                            "currency": "usd", "total_budget": 80, "category_budgets": [{"main_category": "Entertainment & Leisure", "allocated_amount": 80}]})
    c.post("/api/budgets", headers=H, json={"name": "MMK groceries", "period": "monthly", "start_date": som.isoformat(), "currency": "mmk",
                                            "total_budget": 300_000, "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 300_000}]})
    c.post("/api/goals", headers=H, json={"name": "Emergency fund", "target_amount": 5000, "goal_type": "savings", "initial_contribution": 1200, "currency": "usd",
                                          "target_date": (today + timedelta(days=180)).isoformat()})
    c.post("/api/goals", headers=H, json={"name": "New laptop", "target_amount": 1500, "goal_type": "large_purchase", "initial_contribution": 1500, "currency": "usd"})
    c.post("/api/goals", headers=H, json={"name": "Trip to Bagan", "target_amount": 800, "goal_type": "savings", "initial_contribution": 100, "currency": "usd",
                                          "target_date": (today - timedelta(days=4)).isoformat()})
    c.post("/api/goals", headers=H, json={"name": "Pay off card", "target_amount": 2_000_000, "goal_type": "debt_reduction", "initial_contribution": 250_000, "currency": "mmk"})
    c.post("/api/feedback", headers=H, json={"category": "feature_request", "message": "Dark mode for charts please", "rating": 4})
    if big:  # premium users: stored insights so the screen has content without AI
        for prov in ("openai", "gemini"):
            for typ in ("weekly", "monthly"):
                db.insights.insert_one({"_id": str(uuid.uuid4()), "user_id": ACCOUNTS[key]["id"], "ai_provider": prov, "insight_type": typ,
                                        "content": f"## {typ.title()} summary\nYou spent **$1,240** on {typ} essentials.\n\n## Tips\n- Cook at home twice a week\n- Review subscriptions",
                                        "content_mm": f"## {typ} အကျဉ်းချုပ်\nသင် **$1,240** သုံးခဲ့သည်။",
                                        "generated_at": now - timedelta(hours=3), "is_placeholder": False})
    # a few notifications incl. recurring/large-tx types that route to the transactions screen
    for t_, title in (("large_transaction", "Large transaction"), ("recurring_transaction_created", "Recurring rent added"),
                      ("budget_threshold", "80% of Monthly essentials used"), ("goal_achieved", "Goal achieved: New laptop"),
                      ("system_broadcast", "Welcome to the new version")):
        db.notifications.insert_one({"_id": str(uuid.uuid4()), "user_id": ACCOUNTS[key]["id"], "type": t_, "title": title,
                                     "message": f"{title} — details here.", "created_at": now - timedelta(hours=random.randint(1, 72)),
                                     "is_read": False, "currency": "usd"})

json.dump({k: {kk: v[kk] for kk in ("name", "email", "password", "premium", "language")} for k, v in ACCOUNTS.items()},
          open(os.path.join(HERE, "seed_accounts.json"), "w"), indent=1)
print("seeded:", {k: db.transactions.count_documents({"user_id": v["id"]}) for k, v in ACCOUNTS.items()})
