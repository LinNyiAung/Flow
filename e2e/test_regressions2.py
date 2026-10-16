"""Live checks for regressions the code review reported in the fixes."""
import asyncio
import concurrent.futures
import os
import sys
import uuid
from datetime import datetime, timedelta, UTC

import httpx

BASE = "http://127.0.0.1:8765"
db = __import__("pgcompat").get_db()
c = httpx.Client(base_url=BASE, timeout=60)
H = lambda t: {"Authorization": f"Bearer {t}"}
out = []


def rec(name, status, detail=""):
    out.append((name, status, detail))
    print(f"[{status}] {name}" + (f" -- {detail}" if detail else ""))


tok = c.post("/api/auth/login", json={"email": "alice@example.com", "password": "secret789"}).json()["access_token"]
alice = db.users.find_one({"email": "alice@example.com"})

# 1. Editing an existing transaction whose category isn't in the list (old AI extraction / renamed category)
tid = "legacy-" + uuid.uuid4().hex[:6]
now = datetime.now(UTC)
db.transactions.insert_one({"_id": tid, "user_id": alice["_id"], "type": "outflow", "main_category": "Food & Drinks",
                            "sub_category": "Lunch", "amount": 4.5, "currency": "usd", "date": now, "description": "old",
                            "created_at": now, "updated_at": now})
r = c.put(f"/api/transactions/{tid}", headers=H(tok), json={"type": "outflow", "main_category": "Food & Drinks",
                                                             "sub_category": "Lunch", "description": "edited note", "amount": 4.5})
rec("edit description of a legacy-category transaction (app always sends type+categories)",
    "BUG" if r.status_code == 400 else "PASS", f"{r.status_code} {r.text[:140]}")
db.transactions.delete_one({"_id": tid})

# 2. Simultaneous registrations with the same email
email = f"race-{uuid.uuid4().hex[:6]}@example.com"


def reg(_):
    with httpx.Client(base_url=BASE, timeout=60) as cc:
        return cc.post("/api/auth/register", json={"name": "Race", "email": email, "password": "secret123"}).status_code


with concurrent.futures.ThreadPoolExecutor(6) as ex:
    codes = list(ex.map(reg, range(6)))
rec("6 simultaneous registrations for one email", "BUG" if 500 in codes else "PASS", f"status codes={sorted(codes)}; accounts={db.users.count_documents({'email': email})}")

# 3. Resend verification right after register
email2 = f"resend-{uuid.uuid4().hex[:6]}@example.com"
c.post("/api/auth/register", json={"name": "R", "email": email2, "password": "secret123"})
u = db.users.find_one({"email": email2})
vkey = next(k for k in u if "verif" in k and "token" in k and "expires" not in k)
before = u.get(vkey)
r = c.post("/api/auth/resend-verification", json={"email": email2})
after = db.users.find_one({"email": email2}).get(vkey)
assert before, "no verification token stored"
rec("resend within 60s of register says sent but sends nothing", "BUG" if r.status_code == 200 and before == after else "PASS",
    f"{r.status_code} {r.json().get('message', '')[:90]!r}; token changed={before != after}")

out_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "regressions2.txt")
open(out_file, "w").write("\n".join(f"{s}\t{n}\t{d}" for n, s, d in out))
