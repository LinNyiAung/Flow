import sys
from pymongo import MongoClient

d = __import__("pgcompat").get_db()
cmd = sys.argv[1]
if cmd == "versions-off":
    print(d.app_versions.update_many({}, {"$set": {"is_active": False}}).modified_count)
elif cmd == "seed-insight":
    import uuid
    from datetime import datetime, UTC
    u = d.users.find_one({"email": sys.argv[2]})
    for prov in ("openai", "gemini"):
        for typ in ("weekly", "monthly"):
            d.insights.insert_one({"_id": str(uuid.uuid4()), "user_id": u["_id"], "ai_provider": prov, "insight_type": typ,
                                   "content": f"## ALICE PRIVATE INSIGHT ({prov}/{typ})\nAlice spent $125.50 on groceries and rent.",
                                   "content_mm": f"## ALICE PRIVATE INSIGHT MM ({prov}/{typ})\nAlice ...",
                                   "generated_at": datetime.now(UTC), "expires_at": None, "is_placeholder": False})
    print("seeded")
elif cmd == "add-admin":
    import uuid
    from datetime import datetime, UTC
    from passlib.context import CryptContext
    email, pw, role = sys.argv[2], sys.argv[3], sys.argv[4]
    d.admins.delete_many({"email": email})
    d.admins.insert_one({"_id": str(uuid.uuid4()), "name": f"E2E {role}", "email": email,
                         "password": CryptContext(schemes=["bcrypt"]).hash(pw), "role": role,
                         "created_at": datetime.now(UTC), "last_login": None})
    print("admin added", email, role)
elif cmd == "user":
    u = d.users.find_one({"email": sys.argv[2]})
    print({k: u.get(k) for k in ("subscription_type", "subscription_expires_at", "language", "fcm_token", "balances")})
