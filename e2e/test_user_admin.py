"""User management e2e (docs/superpowers/specs/2026-11-27-user-management-design.md).

Sections (named on the command line, all by default):
  guard -- a suspended account: sign-in, old and new tokens, forgot-password and resend-verification, suspend and
    unsuspend as conditional writes; and a completed password reset verifies an unverified e-mail.
  clean -- no throwaway users or admins are left; keep this section last.
"""
import asyncio
import json
import os
import sys
import uuid
from datetime import UTC, datetime

os.environ.setdefault("E2E_FAKE_AI", "1")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402,F401

db = __import__("pgcompat").get_db()
failures = 0
BASE = "http://127.0.0.1:8765"
OUTBOX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "outbox.jsonl")
PREFIX = "ua-"
EN_MSG = "This account is suspended. Please contact us."
MY_MSG = "ဤအကောင့်ကို ရပ်ဆိုင်းထားပါသည်။ ကျွန်ုပ်တို့ထံ ဆက်သွယ်ပေးပါ။"
PW = "secret123"


def check(ok, name, detail=""):
    global failures
    if not ok:
        failures += 1
    print(("[PASS] " if ok else "[BUG] ") + name + (f" -- {detail}" if detail and not ok else ""), flush=True)


def _backend_async(coro_fn):
    """Run backend async code in-process (its DB engine binds to the loop: one asyncio.run per call, a fresh engine)."""
    async def go():
        from sql import db as sqldb
        try:
            return await coro_fn()
        finally:
            await sqldb.dispose_engine()
    return asyncio.run(go())


def _admin(c, role):
    import admin_utils
    email, pw = f"{PREFIX}{role}-{uuid.uuid4().hex[:8]}@example.com", "ua-admin-pass-1"
    aid = str(uuid.uuid4())
    db.admins.insert_one({"_id": aid, "name": f"ua {role}", "email": email,
                          "password": admin_utils.get_password_hash(pw), "role": role,
                          "created_at": datetime.now(UTC), "last_login": None})
    r = c.post("/api/admin/login", json={"email": email, "password": pw})
    return {"Authorization": "Bearer " + r.json().get("access_token", "")}, aid


def _person(c, made, label, verified=True):
    """A person with a password (id, email, h: the auth header when verified), its id added to `made`."""
    email = f"{PREFIX}{label}-{uuid.uuid4().hex[:8]}@example.com"
    c.post("/api/auth/register", json={"name": label, "email": email, "password": PW})
    uid = db.users.find_one({"email": email})["_id"]
    made.append(uid)
    token = None
    if verified:
        db.users.update_one({"email": email}, {"$set": {"is_verified": True}})
        token = c.post("/api/auth/login", json={"email": email, "password": PW}).json().get("access_token")
    return {"id": uid, "email": email, "h": {"Authorization": f"Bearer {token}"}}


def _cleanup(made_users, made_admins):
    if made_users:
        db.sql("DELETE FROM users WHERE id = ANY(%s)", made_users)
    if made_admins:
        db.sql("DELETE FROM admins WHERE id = ANY(%s)", made_admins)


def _mails_to(email):
    """How many mails the stubbed SMTP has sent to `email`."""
    if not os.path.exists(OUTBOX):
        return 0
    n = 0
    for line in open(OUTBOX, encoding="utf-8"):
        rec = json.loads(line)
        if rec.get("kind") == "smtp" and f"To: {email} " in " ".join(rec.get("args", [])):
            n += 1
    return n


def _latest_otp(email):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import re
    code = None
    for line in open(OUTBOX, encoding="utf-8"):
        rec = json.loads(line)
        if rec.get("kind") != "smtp":
            continue
        body = " ".join(rec.get("args", []))
        if f"To: {email} " in body:
            m = re.search(r"\n[ \t]+(\d{6})[ \t]*(?:\n|$)", body.replace("\\n", "\n"))
            if m:
                code = m.group(1)
    return code


def _detail(r):
    try:
        d = r.json().get("detail")
    except Exception:
        return None
    return d if isinstance(d, dict) else {"raw": d}


# -------------------------------------------------------------------------------------------------------------- guard
def section_guard():
    import httpx
    c = httpx.Client(base_url=BASE, timeout=60)
    made_users, made_admins = [], []
    try:
        _, admin_id = _admin(c, "admin")
        made_admins.append(admin_id)
        p = _person(c, made_users, "susp")
        old_h = p["h"]
        check(c.get("/api/auth/me", headers=old_h).status_code == 200, "guard: before the suspension the token works")

        async def suspend():
            from sql import users as users_db
            ok1 = await users_db.suspend(p["id"], "e2e reason", admin_id, datetime.now(UTC))
            ok2 = await users_db.suspend(p["id"], "again", admin_id, datetime.now(UTC))
            await users_db.sign_out_everywhere(p["id"])
            return ok1, ok2
        first, second = _backend_async(suspend)
        check(first is True and second is False, "guard: suspend is True once, False when already suspended",
              f"{first} {second}")
        row = db.sql("SELECT suspended_at, suspended_reason, suspended_by FROM users WHERE id = %s", p["id"])[0]
        check(row["suspended_at"] is not None and row["suspended_reason"] == "e2e reason"
              and row["suspended_by"] == admin_id, "guard: the suspension record keeps the first reason and admin",
              str(row))

        r = c.post("/api/auth/login", json={"email": p["email"], "password": PW})
        d = _detail(r) or {}
        check(r.status_code == 423 and d.get("code") == "account_suspended" and d.get("message") == EN_MSG,
              "guard: sign-in of a suspended person is 423 with the English message", f"{r.status_code} {r.text[:200]}")
        db.sql("UPDATE users SET language = 'my' WHERE id = %s", p["id"])
        r = c.post("/api/auth/login", json={"email": p["email"], "password": PW})
        d = _detail(r) or {}
        check(r.status_code == 423 and d.get("code") == "account_suspended" and d.get("message") == MY_MSG,
              "guard: with language my the message is Myanmar", f"{r.status_code} {r.text[:200]}")
        r = c.post("/api/auth/login", json={"email": p["email"], "password": "wrong-password"})
        check(r.status_code == 401 and r.json().get("detail") == "Incorrect email or password",
              "guard: a wrong password on a suspended account is still 401", f"{r.status_code} {r.text[:200]}")

        r = c.get("/api/auth/me", headers=old_h)
        check(r.status_code == 401, "guard: the old token is signed out (401, not 423)", f"{r.status_code}")

        async def issue():
            from auth_routes import _issue_token
            from sql import users as users_db
            return _issue_token(await users_db.get_user(p["id"]))
        new_h = {"Authorization": "Bearer " + _backend_async(issue)}
        r1 = c.get("/api/auth/me", headers=new_h)
        r2 = c.post("/api/auth/renew-session", headers=new_h)
        for r, what in ((r1, "/me"), (r2, "renew-session")):
            d = _detail(r) or {}
            check(r.status_code == 423 and d.get("code") == "account_suspended" and d.get("message") == MY_MSG,
                  f"guard: a token issued after the suspension is refused with 423 on {what}",
                  f"{r.status_code} {r.text[:200]}")

        before = _mails_to(p["email"])
        r = c.post("/api/auth/forgot-password/request-otp", json={"email": p["email"]})
        check(r.status_code == 200 and "If that email is registered" in r.json().get("message", ""),
              "guard: forgot-password for a suspended person gets the generic 200", f"{r.status_code} {r.text[:200]}")
        db.sql("UPDATE users SET is_verified = false WHERE id = %s", p["id"])
        r = c.post("/api/auth/resend-verification", json={"email": p["email"]})
        check(r.status_code == 200 and "If that email is registered" in r.json().get("message", ""),
              "guard: resend-verification for a suspended person gets the generic 200", f"{r.status_code} {r.text[:200]}")
        import time
        time.sleep(1)  # the mails are sent in a background task
        check(_mails_to(p["email"]) == before, "guard: no mail is sent to a suspended person",
              f"{before} -> {_mails_to(p['email'])}")
        otp_row = db.sql("SELECT password_reset_otp, verification_token FROM users WHERE id = %s", p["id"])[0]
        check(otp_row["password_reset_otp"] is None, "guard: no reset code was stored for a suspended person")
        db.sql("UPDATE users SET is_verified = true WHERE id = %s", p["id"])

        async def lift():
            from sql import users as users_db
            return await users_db.unsuspend(p["id"]), await users_db.unsuspend(p["id"])
        up, again = _backend_async(lift)
        check(up is True and again is False, "guard: unsuspend is True once, False when not suspended",
              f"{up} {again}")
        r = c.post("/api/auth/login", json={"email": p["email"], "password": PW})
        check(r.status_code == 200, "guard: after unsuspend the person signs in", f"{r.status_code} {r.text[:200]}")
        row = db.sql("SELECT suspended_at, suspended_reason, suspended_by FROM users WHERE id = %s", p["id"])[0]
        check(row["suspended_at"] is None and row["suspended_reason"] is None and row["suspended_by"] is None,
              "guard: unsuspend clears the record", str(row))

        # a completed reset verifies an unverified e-mail
        u = _person(c, made_users, "unver", verified=False)
        check(c.post("/api/auth/login", json={"email": u["email"], "password": PW}).status_code == 403,
              "guard: an unverified person cannot sign in")
        c.post("/api/auth/forgot-password/request-otp", json={"email": u["email"]})
        time.sleep(1)
        otp = _latest_otp(u["email"])
        check(otp is not None, "guard: the reset code was mailed to the unverified person")
        r = c.post("/api/auth/forgot-password/verify-otp", json={"email": u["email"], "otp": otp})
        token = r.json().get("reset_token") if r.status_code == 200 else None
        check(token is not None, "guard: the code is accepted", f"{r.status_code} {r.text[:200]}")
        r = c.post("/api/auth/forgot-password/reset-password",
                   json={"email": u["email"], "reset_token": token, "new_password": "newsecret1",
                         "confirm_password": "newsecret1"})
        check(r.status_code == 200, "guard: the reset completes", f"{r.status_code} {r.text[:200]}")
        r = c.post("/api/auth/login", json={"email": u["email"], "password": "newsecret1"})
        row = db.sql("SELECT is_verified, verified_at FROM users WHERE id = %s", u["id"])[0]
        check(r.status_code == 200 and row["is_verified"] is True and row["verified_at"] is not None,
              "guard: after the reset the person is verified and signs in", f"{r.status_code} {row}")
    finally:
        _cleanup(made_users, made_admins)


# -------------------------------------------------------------------------------------------------------------- clean
def section_clean():
    n = db.sql("SELECT count(*) AS n FROM users WHERE email LIKE %s", PREFIX + "%")[0]["n"]
    m = db.sql("SELECT count(*) AS n FROM admins WHERE email LIKE %s", PREFIX + "%")[0]["n"]
    check(n == 0 and m == 0, "clean: no throwaway users or admins are left", f"users {n}, admins {m}")


SECTIONS = {"guard": section_guard, "clean": section_clean}


def main():
    wanted = sys.argv[1:] or list(SECTIONS)
    unknown = [w for w in wanted if w not in SECTIONS]
    if unknown:
        print(f"unknown section(s) {unknown}; choose from {list(SECTIONS)}")
        sys.exit(2)
    for name in wanted:
        SECTIONS[name]()
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
