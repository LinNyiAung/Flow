"""Premium expiry: downgrade job, notification, refresh push, admin counts/broadcast targeting."""
import asyncio
import json
import os
import sys
import uuid
from datetime import datetime, timedelta, UTC

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402

os.chdir(stubenv.BACKEND)
import httpx  # noqa: E402

import subscription_service as ss  # noqa: E402
stubenv.patch_loaded_modules()

db = __import__("pgcompat").get_db()

def ACTIVE(now=None):
    """Mongo-style filter equivalent of subscription_service.active_premium_filter (for pgcompat)."""
    now = now or datetime.now(UTC)
    return {"subscription_type": "premium", "$or": [{"subscription_expires_at": None}, {"subscription_expires_at": {"$gt": now}}]}


def FREE(now=None):
    now = now or datetime.now(UTC)
    return {"$or": [{"subscription_type": {"$ne": "premium"}}, {"subscription_expires_at": {"$lte": now}}]}
c = httpx.Client(base_url="http://127.0.0.1:8765", timeout=60)
H = lambda t: {"Authorization": f"Bearer {t}"}
now = datetime.now(UTC)
results = []


def check(ok, name, detail=""):
    results.append(ok)
    print(("[PASS] " if ok else "[BUG] ") + name + (f" -- {detail}" if detail and not ok else ""), flush=True)


def user(tag, sub="free", expires=None, lang="en", fcm=None):
    email = f"px-{tag}-{uuid.uuid4().hex[:5]}@example.com"
    c.post("/api/auth/register", json={"name": tag, "email": email, "password": "secret123"})
    db.users.update_one({"email": email}, {"$set": {"is_verified": True, "subscription_type": sub, "subscription_expires_at": expires,
                                                   "language": lang, "fcm_token": fcm}})
    u = db.users.find_one({"email": email})
    return u["_id"], c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json()["access_token"]


# fresh population for exact counts
db.users.delete_many({"email": {"$regex": "^px-"}})
expired_en, tok_expired = user("expired-en", "premium", now - timedelta(days=5), "en", fcm="fcm-token-expired-en")
expired_my, _ = user("expired-my", "premium", now - timedelta(hours=2), "my")
active, tok_active = user("active", "premium", now + timedelta(days=20))
lifetime, _ = user("lifetime", "premium", None)
free, _ = user("free", "free", None)
race, _ = user("race", "premium", now - timedelta(minutes=1))
lapsed, _ = user("lapsed", "premium", now - timedelta(days=90), fcm="fcm-token-lapsed")
ids = [expired_en, expired_my, active, lifetime, free, race, lapsed]
scope = {"_id": {"$in": ids}}

# --- admin counts BEFORE the job already treat expired as free
check(db.users.count_documents({**scope, **ACTIVE(now)}) == 2, "active-premium filter: only the active + lifetime users")
check(db.users.count_documents({**scope, **FREE(now)}) == 5, "effectively-free filter: free + the 4 expired users")

# --- premium features stop at expiry even before the job runs
r = c.get("/api/insights", headers=H(tok_expired))
check(r.status_code == 403, "expired user is already blocked from premium features before the job", f"{r.status_code}")
r = c.get("/api/insights", headers=H(tok_active))
check(r.status_code != 403, "active premium user still has access", f"{r.status_code}")

# --- race: an admin extends 'race' before the job's conditional update lands
real_downgrade = ss.users_db.downgrade_if_unchanged


async def downgrade_after_admin_extension(user_id, stored_expiry, ended_at):
    # An admin extends 'race' after the job read it but before its conditional update lands.
    if user_id == race:
        db.users.update_one({"_id": race}, {"$set": {"subscription_expires_at": now + timedelta(days=30)}})
    return await real_downgrade(user_id, stored_expiry, ended_at)

pushes = []
ss.send_fcm_data_message = lambda token, data=None: pushes.append((token, data)) or True
ss.users_db.downgrade_if_unchanged = downgrade_after_admin_extension


async def run_job_twice():
    first = await ss.expire_premium_subscriptions(now)
    ss.users_db.downgrade_if_unchanged = real_downgrade
    second = await ss.expire_premium_subscriptions(now)
    return first, second

n, n2 = asyncio.run(run_job_twice())

downgraded_here = db.users.count_documents({"_id": {"$in": ids}, "premium_ended_at": {"$ne": None}})
# n can include expired users left behind by other suites; count only this test's users.
check(downgraded_here == 3 and n >= 3, f"job downgraded exactly this test's 3 expired users (got {downgraded_here}; job total {n})")
docs_lapsed = db.users.find_one({"_id": lapsed})
check(docs_lapsed is not None, "lapsed user exists")
check(docs_lapsed["subscription_type"] == "free", "user whose premium lapsed 90 days ago is downgraded too")
docs = {d["_id"]: d for d in db.users.find(scope)}
check(docs[expired_en]["subscription_type"] == "free" and docs[expired_my]["subscription_type"] == "free", "expired users are now subscription_type=free")
check(docs[expired_en].get("subscription_expires_at") is not None and docs[expired_en].get("premium_ended_at") is not None,
      "old expiry kept and premium_ended_at recorded (history)")
check(docs[race]["subscription_type"] == "premium", "admin extension made just before the downgrade wins (race user stays premium)")
check(docs[active]["subscription_type"] == "premium" and docs[lifetime]["subscription_type"] == "premium" and docs[free]["subscription_type"] == "free",
      "active, lifetime and free users untouched")

notes = {d["user_id"]: d for d in db.notifications.find({"type": "subscription_expired", "user_id": {"$in": ids}})}
check(set(notes) == {expired_en, expired_my}, "'Premium ended' notification only for recently ended subscriptions (none for the 90-day-lapsed user)", f"{list(notes)}")
en, my = notes.get(expired_en, {}), notes.get(expired_my, {})
check(en.get("title") == "Your Premium Has Ended" and "ended on" in en.get("message", ""), "English notification text", json.dumps(en, default=str)[:200])
check("Premium" in my.get("title", "") and any("က" <= ch <= "႟" for ch in my.get("message", "")), "Myanmar notification for a Myanmar-language user",
      json.dumps(my, ensure_ascii=False, default=str)[:200])
print("   EN:", en.get("message"))
print("   MY:", my.get("message"))

check(pushes == [("fcm-token-expired-en", {"type": "subscription_updated", "subscription_type": "free"})],
      "silent refresh push sent once, only to the recently-ended user with a device token (not the lapsed one)", f"{pushes}")

check(n2 == 0 and db.notifications.count_documents({"type": "subscription_expired", "user_id": {"$in": ids}}) == 2,
      "second run changes nothing and sends no duplicate notification")

# --- the app can list the new notification type
r = c.get("/api/notifications", headers=H(tok_expired))
types = [x.get("type") for x in (r.json() if r.status_code == 200 else [])]
check("subscription_expired" in types, "GET /api/notifications returns the subscription_expired notification", f"{r.status_code} {types[:5]}")

# --- admin endpoints use the same rule
from passlib.context import CryptContext  # noqa: E402
ae = f"px-admin-{uuid.uuid4().hex[:5]}@example.com"
db.admins.insert_one({"_id": str(uuid.uuid4()), "name": "PX", "email": ae, "password": CryptContext(schemes=["bcrypt"]).hash("px-admin-pw"),
                      "role": "super_admin", "created_at": now, "last_login": None})
AD = H(c.post("/api/admin/login", json={"email": ae, "password": "px-admin-pw"}).json()["access_token"])
st = c.get("/api/admin/stats/users", headers=AD).json()
truth_p = db.users.count_documents(ACTIVE())
truth_f = db.users.count_documents(FREE())
check(st.get("premium_users") == truth_p and st.get("free_users") == truth_f and truth_p + truth_f == st.get("total_users"),
      f"admin stats: premium {st.get('premium_users')} + free {st.get('free_users')} = total {st.get('total_users')}")
bs = c.get("/api/admin/broadcast-stats", headers=AD).json()
check(bs.get("premium_users") == truth_p and bs.get("free_users") == truth_f, "broadcast reach counts use the same rule", json.dumps(bs))
db.users.update_one({"_id": active}, {"$set": {"subscription_expires_at": now - timedelta(minutes=5)}})  # expired, job not run yet
bs2 = c.get("/api/admin/broadcast-stats", headers=AD).json()
check(bs2.get("premium_users") == truth_p - 1 and bs2.get("free_users") == truth_f + 1, "a just-expired user moves from premium to free in admin counts before the job runs")

print("\nPREMIUM EXPIRY:", sum(results), "pass,", len(results) - sum(results), "fail")
