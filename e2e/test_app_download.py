"""Public GET /api/app/latest-android (no auth) and the CORS header the web app needs to read PDF filenames."""
import os
import sys
import uuid
from datetime import datetime, UTC

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402

os.chdir(stubenv.BACKEND)
import httpx  # noqa: E402

stubenv.patch_loaded_modules()

db = __import__("pgcompat").get_db()
c = httpx.Client(base_url="http://127.0.0.1:8765", timeout=60)
now = datetime.now(UTC)
results = []

URL_A, URL_B, URL_C, URL_D, URL_E = (f"https://example.com/flow-{n}.apk" for n in "ABCDE")


def check(ok, name, detail=""):
    results.append(ok)
    print(("[PASS] " if ok else "[BUG] ") + name + (f" -- {detail}" if detail and not ok else ""), flush=True)


def add_version(version, platform, url, active=True):
    vid = str(uuid.uuid4())
    db.app_versions.insert_one({
        "_id": vid, "version": version, "platform": platform, "download_url": url, "release_notes": None,
        "is_force_update": False, "min_supported_version": None, "is_active": active,
        "created_by_email": "test@example.com", "created_at": now, "updated_at": None,
    })
    return vid


db.app_versions.delete_many({})

# --- nothing published yet; the request carries no Authorization header
r = c.get("/api/app/latest-android")
check(r.status_code == 200 and r.json() == {"version": None, "download_url": None},
      "no versions: 200 with null version and download_url, no auth needed", f"{r.status_code} {r.text}")

# --- highest parseable ACTIVE android/all version wins
add_version("1.2.0", "android", URL_A)
latest_all = add_version("1.3.0", "all", URL_B)
add_version("9.0.0", "android", URL_C, active=False)
add_version("5.0.0", "ios", URL_D)
add_version("abc", "android", URL_E)
r = c.get("/api/app/latest-android")
check(r.status_code == 200 and r.json() == {"version": "1.3.0", "download_url": URL_B},
      "picks highest active android/all version; ignores inactive, ios and malformed ones", f"{r.status_code} {r.text}")
check(set(r.json()) == {"version", "download_url"}, "response exposes only version and download_url", f"{r.text}")

# --- deactivating the top version falls back to the next one
db.app_versions.update_one({"_id": latest_all}, {"$set": {"is_active": False}})
r = c.get("/api/app/latest-android")
check(r.status_code == 200 and r.json() == {"version": "1.2.0", "download_url": URL_A},
      "deactivated version is skipped", f"{r.status_code} {r.text}")

# --- CORS: browsers can read Content-Disposition on the PDF download
email = f"dl-{uuid.uuid4().hex[:5]}@example.com"
c.post("/api/auth/register", json={"name": "dl", "email": email, "password": "secret123"})
db.users.update_one({"email": email}, {"$set": {"is_verified": True, "subscription_type": "premium", "subscription_expires_at": None}})
token = c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json()["access_token"]
r = c.post("/api/reports/download", headers={"Authorization": f"Bearer {token}", "Origin": "http://example.com"},
           json={"period": "month", "currency": "usd"})
exposed = r.headers.get("access-control-expose-headers", "")
check(r.status_code == 200 and "content-disposition" in exposed.lower(),
      "PDF download exposes Content-Disposition to browsers via CORS", f"{r.status_code} expose={exposed!r}")

print("\nAPP DOWNLOAD:", sum(results), "pass,", len(results) - sum(results), "fail")
sys.exit(0 if all(results) else 1)
