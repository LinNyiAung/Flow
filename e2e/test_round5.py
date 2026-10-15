"""Live checks for round-5 backend changes: clearing a transaction note via update."""
import os
import sys
import uuid
from datetime import datetime, UTC

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402,F401

import httpx  # noqa: E402
from pymongo import MongoClient  # noqa: E402

db = __import__("pgcompat").get_db()
c = httpx.Client(base_url="http://127.0.0.1:8765", timeout=60)
H = lambda t: {"Authorization": f"Bearer {t}"}


def check(ok, name, detail=""):
    print(("[PASS] " if ok else "[BUG] ") + name + (f" -- {detail}" if detail and not ok else ""))


email = f"r5-{uuid.uuid4().hex[:6]}@example.com"
c.post("/api/auth/register", json={"name": "R5", "email": email, "password": "secret123"})
db.users.update_one({"email": email}, {"$set": {"is_verified": True}})
tok = c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json()["access_token"]

tx = c.post("/api/transactions", headers=H(tok), json={
    "type": "outflow", "main_category": "Transportation", "sub_category": "Taxi", "amount": 5,
    "currency": "usd", "date": datetime.now(UTC).isoformat(), "description": "note to clear"}).json()
tid = tx["id"]


def put(body):
    r = c.put(f"/api/transactions/{tid}", headers=H(tok), json=body)
    return r.status_code, (r.json() if r.status_code == 200 else r.text)


code, body = put({"description": ""})
check(code == 200 and body.get("description") is None, "empty description clears the note", f"{code} {body}")
check(db.transactions.find_one({"_id": tid}).get("description") is None, "cleared note stored as null in Mongo")

code, body = put({"description": "kept"})
check(code == 200 and body.get("description") == "kept", "setting a note after clearing works", f"{code} {body}")

code, body = put({"description": "   "})
check(code == 200 and body.get("description") is None, "whitespace-only description clears the note", f"{code} {body}")

put({"description": "stays"})
code, body = put({"amount": 9})
check(code == 200 and body.get("description") == "stays", "update without description leaves the note untouched", f"{code} {body}")

code, body = put({"description": None, "amount": 10})
check(code == 200 and body.get("description") == "stays", "explicit null description is ignored (not a clear)", f"{code} {body}")

listed = c.get("/api/transactions", headers=H(tok), params={"limit": 5}).json()
row = next((t for t in listed if t["id"] == tid), {})
check(row.get("description") == "stays" and row.get("amount") == 10, "list endpoint reflects the updates", row)

c.delete(f"/api/transactions/{tid}", headers=H(tok))
