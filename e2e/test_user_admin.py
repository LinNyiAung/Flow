"""User management e2e (docs/superpowers/specs/2026-11-27-user-management-design.md).

Sections (named on the command line, all by default):
  guard -- a suspended account: sign-in, old and new tokens, forgot-password and resend-verification, suspend and
    unsuspend as conditional writes; and a completed password reset verifies an unverified e-mail.
  actions -- the admin API on one person: roles, suspend / unsuspend, sign out, name and currency, a message, and
    the suspension in the detail and the list.
  recovery -- an admin sends a reset code (and its limits), and a super admin corrects a sign-in email.
  effects -- a suspended person gets no notices, broadcasts or AI work; data jobs and family books go on.
  clean -- no throwaway users or admins are left; keep this section last.
"""
import asyncio
import json
import os
import sys
import uuid
from datetime import UTC, datetime, timedelta

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


# ----------------------------------------------------------------------------------------------------------- actions
def _add_device(uid, token):
    db.sql("INSERT INTO user_devices (id, user_id, token, session_expires_at) "
           "VALUES (%s, %s, %s, now() + interval '30 days')", str(uuid.uuid4()), uid, token)


def _pushes_to(token):
    if not os.path.exists(OUTBOX):
        return 0
    n = 0
    for line in open(OUTBOX, encoding="utf-8"):
        if '"fcm_send"' in line and json.loads(line).get("token") == token:
            n += 1
    return n


def _logs(uid, action):
    return db.sql("SELECT admin_email, details FROM admin_action_logs WHERE target_user_id = %s AND action = %s",
                  uid, action)


def section_actions():
    import httpx
    c = httpx.Client(base_url=BASE, timeout=60)
    made_users, made_admins = [], []
    try:
        ah, admin_id = _admin(c, "admin")
        mh, mod_id = _admin(c, "moderator")
        made_admins += [admin_id, mod_id]
        p = _person(c, made_users, "act")
        uid = p["id"]
        url = f"/api/admin/users/{uid}"
        ghost = f"/api/admin/users/{uuid.uuid4()}"

        # roles: a moderator reads, never acts
        calls = [("post", "/suspend", {"reason": "x"}), ("post", "/unsuspend", None), ("post", "/sign-out", None),
                 ("put", "/profile", {"name": "Zed Zed"}),
                 ("post", "/message", {"title": "t", "message": "m", "notification_type": "system_broadcast"})]
        for method, path, body in calls:
            r = getattr(c, method)(url + path, headers=mh, **({"json": body} if body is not None else {}))
            check(r.status_code == 403, f"actions: a moderator gets 403 on {method.upper()} {path}", r.status_code)
        r = c.get(url, headers=mh)
        check(r.status_code == 200 and r.json().get("suspension") is None,
              "actions: a moderator sees suspension (null) in the detail", f"{r.status_code} {r.text[:200]}")

        # unknown person
        for method, path, body in [("post", "/suspend", {"reason": "x"}), ("post", "/unsuspend", None),
                                   ("post", "/sign-out", None), ("put", "/profile", {"name": "Zed Zed"}),
                                   ("post", "/message", {"title": "t", "message": "m",
                                                         "notification_type": "system_broadcast"})]:
            r = getattr(c, method)(ghost + path, headers=ah, **({"json": body} if body is not None else {}))
            check(r.status_code == 404, f"actions: unknown id is 404 on {method.upper()} {path}", r.status_code)

        # profile
        r = c.put(url + "/profile", headers=ah, json={"name": "B"})
        check(r.status_code == 400, "actions: a one-character name is 400", f"{r.status_code} {r.text[:200]}")
        r = c.put(url + "/profile", headers=ah, json={})
        check(r.status_code == 422, "actions: an empty profile body is 422", r.status_code)
        r = c.put(url + "/profile", headers=ah, json={"name": "Bo Bo", "email": "x@y.com"})
        check(r.status_code == 422, "actions: extra fields are refused (422)", r.status_code)
        r = c.put(url + "/profile", headers=ah, json={"default_currency": "gbp"})
        check(r.status_code == 422, "actions: an unknown currency is 422", r.status_code)
        # a family the person owns: their member name must follow
        db.sql("UPDATE users SET subscription_type = 'plus', subscription_expires_at = now() + interval '30 days', "
               "trial_ends_at = NULL WHERE id = %s", uid)
        r = c.post("/api/family", headers=p["h"], json={"name": "ua family"})
        fid = ((r.json() if r.status_code == 200 else {}).get("family") or {}).get("id")
        check(fid is not None, "actions: the person made a family", f"{r.status_code} {r.text[:200]}")
        r = c.put(url + "/profile", headers=ah, json={"name": "  Bo Bo  "})
        check(r.status_code == 200 and r.json().get("name") == "Bo Bo" and r.json().get("id") == uid,
              "actions: a name change is 200 and returns the detail", f"{r.status_code} {r.text[:200]}")
        row = db.sql("SELECT name FROM users WHERE id = %s", uid)[0]
        mem = db.sql("SELECT display_name FROM family_members WHERE user_id = %s", uid)
        check(row["name"] == "Bo Bo" and mem and all(m["display_name"] == "Bo Bo" for m in mem),
              "actions: the name is stored and their family member name follows", f"{row} {mem}")
        logs = _logs(uid, "user_profile_updated")
        check(len(logs) == 1 and logs[0]["details"] == "name: act -> Bo Bo", "actions: the name change is logged",
              str(logs))
        r = c.put(url + "/profile", headers=ah, json={"name": "Bo Bo"})
        check(r.status_code == 200 and len(_logs(uid, "user_profile_updated")) == 1,
              "actions: no change is 200 and not logged", f"{r.status_code} {len(_logs(uid, 'user_profile_updated'))}")
        r = c.put(url + "/profile", headers=ah, json={"default_currency": "thb"})
        check(r.status_code == 200 and r.json().get("default_currency") == "thb",
              "actions: the currency changes", f"{r.status_code} {r.text[:200]}")
        logs = _logs(uid, "user_profile_updated")
        check(len(logs) == 2 and any(l["details"] == "default_currency: usd -> thb" for l in logs),
              "actions: the currency change is logged", str(logs))

        # message
        tok1 = f"ua-tok-{uuid.uuid4().hex[:8]}"
        _add_device(uid, tok1)
        r = c.post(url + "/message", headers=ah, json={"title": "  Hello  ", "message": "  Hi there ",
                                                       "notification_type": "admin_announcement"})
        check(r.status_code == 200 and r.json() == {"devices": 1}, "actions: a message reports one device pushed",
              f"{r.status_code} {r.text[:200]}")
        nrows = db.sql("SELECT title, message, type FROM notifications WHERE user_id = %s AND title = 'Hello'", uid)
        check(len(nrows) == 1 and nrows[0]["message"] == "Hi there" and nrows[0]["type"] == "admin_announcement",
              "actions: the message is one notification row for the person", str(nrows))
        check(_pushes_to(tok1) == 1, "actions: one push reached the device", _pushes_to(tok1))
        check([l["details"] for l in _logs(uid, "user_message_sent")] == ["Hello"], "actions: the message is logged")
        for bad in ({"title": " ", "message": "m", "notification_type": "system_broadcast"},
                    {"title": "t", "message": "", "notification_type": "system_broadcast"},
                    {"title": "t" * 101, "message": "m", "notification_type": "system_broadcast"},
                    {"title": "t", "message": "m" * 501, "notification_type": "system_broadcast"},
                    {"title": "t", "message": "m", "notification_type": "goal_progress"}):
            r = c.post(url + "/message", headers=ah, json=bad)
            check(r.status_code == 422, "actions: a bad message body is 422", f"{r.status_code} {str(bad)[:60]}")

        # sign out
        _add_device(uid, "ua-tok-2")
        r = c.post(url + "/sign-out", headers=ah)
        check(r.status_code == 200 and r.json() == {"devices_removed": 2},
              "actions: sign-out reports the devices removed", f"{r.status_code} {r.text[:200]}")
        check(c.get("/api/auth/me", headers=p["h"]).status_code == 401, "actions: sign-out ends the old token")
        check(not db.sql("SELECT 1 FROM user_devices WHERE user_id = %s", uid), "actions: the devices are gone")
        check(len(_logs(uid, "user_signed_out")) == 1, "actions: the sign-out is logged")
        r = c.post(url + "/sign-out", headers=ah)
        check(r.status_code == 200 and r.json() == {"devices_removed": 0}, "actions: a second sign-out removes none",
              r.text[:200])

        # suspend
        _add_device(uid, "ua-tok-3")
        for bad in ({"reason": ""}, {"reason": "   "}, {"reason": "r" * 501}, {}):
            r = c.post(url + "/suspend", headers=ah, json=bad)
            check(r.status_code == 422, "actions: a bad suspend reason is 422", f"{r.status_code} {str(bad)[:30]}")
        r = c.post(url + "/suspend", headers=ah, json={"reason": "  spam  "})
        j = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and j.get("suspended_reason") == "spam" and j.get("suspended_at"),
              "actions: suspend is 200 with the stripped reason", f"{r.status_code} {r.text[:200]}")
        row = db.sql("SELECT suspended_reason, suspended_by FROM users WHERE id = %s", uid)[0]
        check(row["suspended_reason"] == "spam" and row["suspended_by"] == admin_id,
              "actions: the reason and admin are stored", str(row))
        check(not db.sql("SELECT 1 FROM user_devices WHERE user_id = %s", uid), "actions: suspend removes the devices")
        check(c.get("/api/auth/me", headers=p["h"]).status_code == 401, "actions: the old token is 401 after suspend")
        logs = _logs(uid, "user_suspended")
        check(len(logs) == 1 and "spam" in (logs[0]["details"] or ""), "actions: the suspension is logged with the reason",
              str(logs))
        r = c.post(url + "/suspend", headers=ah, json={"reason": "again"})
        d = _detail(r) or {}
        check(r.status_code == 409 and d.get("code") == "already_suspended" and d.get("message"),
              "actions: suspending again is 409 already_suspended", f"{r.status_code} {r.text[:200]}")
        r = c.get(url, headers=mh)
        s = (r.json() if r.status_code == 200 else {}).get("suspension") or {}
        check(s.get("reason") == "spam" and s.get("by_email") and s.get("at"),
              "actions: the detail shows the suspension to a moderator", f"{r.status_code} {r.text[:300]}")
        r = c.post(url + "/message", headers=ah, json={"title": "t", "message": "m",
                                                       "notification_type": "system_broadcast"})
        d = _detail(r) or {}
        check(r.status_code == 409 and d.get("code") == "user_suspended",
              "actions: a message to a suspended person is 409 user_suspended", f"{r.status_code} {r.text[:200]}")
        db.sql("DELETE FROM admins WHERE id = %s", admin_id)
        r = c.get(url, headers=mh)
        s = (r.json() if r.status_code == 200 else {}).get("suspension") or {}
        check(r.status_code == 200 and s.get("by_email") is None and s.get("reason") == "spam",
              "actions: when the suspending admin is gone by_email is null", f"{r.status_code} {r.text[:300]}")
        ah, admin_id = _admin(c, "admin")
        made_admins.append(admin_id)
        r = c.get("/api/admin/users", headers=ah, params={"search": p["email"]})
        row = next((u for u in (r.json() if r.status_code == 200 else []) if u["id"] == uid), {})
        check(row.get("suspended") is True, "actions: the users list flags the suspended person", str(row)[:200])

        # unsuspend
        r = c.post(url + "/unsuspend", headers=ah)
        check(r.status_code == 200, "actions: unsuspend is 200", f"{r.status_code} {r.text[:200]}")
        check(len(_logs(uid, "user_unsuspended")) == 1, "actions: the unsuspend is logged")
        r = c.post(url + "/unsuspend", headers=ah)
        d = _detail(r) or {}
        check(r.status_code == 409 and d.get("code") == "not_suspended",
              "actions: unsuspending again is 409 not_suspended", f"{r.status_code} {r.text[:200]}")
        r = c.post("/api/auth/login", json={"email": p["email"], "password": PW})
        check(r.status_code == 200, "actions: the person signs in again", r.status_code)
    finally:
        _cleanup(made_users, made_admins)


# ----------------------------------------------------------------------------------------------------------- recovery
def _smtp_to(email):
    """The recorded SMTP messages sent to `email` (one string each)."""
    out = []
    if os.path.exists(OUTBOX):
        for line in open(OUTBOX, encoding="utf-8"):
            rec = json.loads(line)
            body = " ".join(rec.get("args", []))
            if rec.get("kind") == "smtp" and f"To: {email} " in body:
                out.append(body.replace("\\n", "\n"))
    return out


def _wait_mails(email, n, seconds=6):
    import time
    end = time.time() + seconds
    while time.time() < end and len(_smtp_to(email)) < n:
        time.sleep(0.2)
    return len(_smtp_to(email))


def section_recovery():
    import time
    import httpx
    c = httpx.Client(base_url=BASE, timeout=60)
    made_users, made_admins = [], []
    try:
        ah, admin_id = _admin(c, "admin")
        sh, super_id = _admin(c, "super_admin")
        mh, mod_id = _admin(c, "moderator")
        made_admins += [admin_id, super_id, mod_id]
        p = _person(c, made_users, "rec", verified=False)
        uid, email = p["id"], p["email"]
        url = f"/api/admin/users/{uid}"

        # reset code: roles and unknown id
        check(c.post(url + "/reset-code", headers=mh).status_code == 403, "recovery: a moderator gets 403 on reset-code")
        check(c.post(f"/api/admin/users/{uuid.uuid4()}/reset-code", headers=ah).status_code == 404,
              "recovery: reset-code for an unknown id is 404")

        # sent
        before = len(_smtp_to(email))
        r = c.post(url + "/reset-code", headers=ah)
        check(r.status_code == 200 and r.json() == {"sent": True}, "recovery: reset-code is 200 {sent: true}",
              f"{r.status_code} {r.text[:200]}")
        check(_wait_mails(email, before + 1) == before + 1, "recovery: one mail went to the person")
        logs = _logs(uid, "user_reset_code_sent")
        check(len(logs) == 1 and logs[0]["details"] is None, "recovery: the send is logged once, without the code", str(logs))
        otp = _latest_otp(email)
        check(otp is not None and otp not in str(logs) and otp not in r.text,
              "recovery: the mailed code exists and is in neither the answer nor the log")

        # at once again: recent
        r = c.post(url + "/reset-code", headers=ah)
        d = _detail(r) or {}
        ahead = None
        if d.get("retry_at"):
            ahead = (datetime.fromisoformat(d["retry_at"]) - datetime.now(UTC)).total_seconds()
        check(r.status_code == 409 and d.get("code") == "reset_code_not_sent" and d.get("reason") == "recent"
              and d.get("message") and ahead is not None and 40 <= ahead <= 61,
              "recovery: asking again at once is 409 recent with retry_at about 60 s ahead", f"{r.status_code} {r.text[:300]}")
        check(len(_logs(uid, "user_reset_code_sent")) == 1, "recovery: a refused send is not logged")

        # the person's own request right after the admin's: generic 200, nothing sent
        n = len(_smtp_to(email))
        r = c.post("/api/auth/forgot-password/request-otp", json={"email": email})
        time.sleep(1.5)
        check(r.status_code == 200 and "If that email is registered" in r.json().get("message", "")
              and len(_smtp_to(email)) == n,
              "recovery: the person's own request right after gets the generic 200 and no mail",
              f"{r.status_code} {n} -> {len(_smtp_to(email))}")

        # the code from the admin send completes a reset (and verifies the account)
        r = c.post("/api/auth/forgot-password/verify-otp", json={"email": email, "otp": otp})
        token = r.json().get("reset_token") if r.status_code == 200 else None
        check(token is not None, "recovery: the mailed code is accepted", f"{r.status_code} {r.text[:200]}")
        r = c.post("/api/auth/forgot-password/reset-password",
                   json={"email": email, "reset_token": token, "new_password": "newsecret2",
                         "confirm_password": "newsecret2"})
        check(r.status_code == 200, "recovery: the reset completes", f"{r.status_code} {r.text[:200]}")
        check(c.post("/api/auth/login", json={"email": email, "password": "newsecret2"}).status_code == 200,
              "recovery: the person signs in with the new password (unverified before, verified after)")

        # locked
        until = datetime.now(UTC).replace(microsecond=0) + timedelta(minutes=20)
        db.sql("UPDATE users SET password_reset_locked_until = %s WHERE id = %s", until, uid)
        r = c.post(url + "/reset-code", headers=ah)
        d = _detail(r) or {}
        got = datetime.fromisoformat(d["retry_at"]) if d.get("retry_at") else None
        check(r.status_code == 409 and d.get("reason") == "locked" and got is not None
              and abs((got - until).total_seconds()) < 1,
              "recovery: a locked account is 409 locked with the lock time", f"{r.status_code} {r.text[:300]}")
        db.sql("UPDATE users SET password_reset_locked_until = NULL WHERE id = %s", uid)

        # suspended: nothing sent, retry_at null
        s_user = _person(c, made_users, "recsusp")
        db.sql("UPDATE users SET suspended_at = now(), suspended_reason = 'x', suspended_by = %s WHERE id = %s",
               admin_id, s_user["id"])
        n = len(_smtp_to(s_user["email"]))
        r = c.post(f"/api/admin/users/{s_user['id']}/reset-code", headers=ah)
        d = _detail(r) or {}
        time.sleep(1)
        check(r.status_code == 409 and d.get("reason") == "suspended" and d.get("retry_at") is None
              and len(_smtp_to(s_user["email"])) == n, "recovery: a suspended person is 409 suspended, nothing sent",
              f"{r.status_code} {r.text[:300]}")

        # hourly limit (the limiter lives in the stub's process, so this runs in-process with a primed limiter)
        async def hourly():
            import collections
            import time as _t
            from fastapi import BackgroundTasks
            import auth_routes
            from sql import users as users_db
            user = await users_db.get_user(uid)
            now = _t.monotonic()
            auth_routes._otp_request_limiter._hits[auth_routes._normalize_email(user["email"])] = collections.deque(
                [now - 3000, now - 2000, now - 1000, now - 500, now - 100])
            tasks = BackgroundTasks()
            res = await auth_routes.issue_reset_code(user, tasks)
            solo = auth_routes._SlidingWindowRateLimiter([(1, 60), (5, 3600)])
            solo._hits["k"] = collections.deque([100.0])
            return res, len(tasks.tasks), solo.check("k", now=130.0), solo.check("k", now=161.0), solo.check("k", now=162.0)
        res, queued, w1, w2, w3 = _backend_async(hourly)
        wait = (res.retry_at - datetime.now(UTC)).total_seconds() if res.retry_at else None
        check(res.sent is False and res.reason == "hourly_limit" and queued == 0 and wait is not None
              and 590 <= wait <= 601,
              "recovery: five sends within the hour give hourly_limit (in-process), nothing queued", str((res, queued, wait)))
        check(w1 is not None and abs(w1 - 30) < 0.01 and w2 is None and w3 is not None,
              "recovery: limiter.check gives the seconds to wait, None (and records a hit) when allowed",
              str((w1, w2, w3)))

        # ---- email correction
        e = _person(c, made_users, "mail")
        other = _person(c, made_users, "other")
        eurl = f"/api/admin/users/{e['id']}/email"
        new_addr = f"{PREFIX}new-{uuid.uuid4().hex[:8]}@example.com"
        for hdrs, what in ((ah, "an admin"), (mh, "a moderator")):
            r = c.put(eurl, headers=hdrs, json={"email": new_addr})
            check(r.status_code == 403, f"recovery: {what} gets 403 on the email correction", r.status_code)
        check(db.sql("SELECT email FROM users WHERE id = %s", e["id"])[0]["email"] == e["email"],
              "recovery: a refused correction changes nothing")
        check(c.put(f"/api/admin/users/{uuid.uuid4()}/email", headers=sh, json={"email": new_addr}).status_code == 404,
              "recovery: the correction for an unknown id is 404")
        for bad in ({"email": "not-an-email"}, {"email": ""}, {}, {"email": new_addr, "name": "x"}):
            r = c.put(eurl, headers=sh, json=bad)
            check(r.status_code == 422, "recovery: a bad email body is 422", f"{r.status_code} {str(bad)[:40]}")
        # taken, in another case: the DB holds lower-case, so put an upper-case twin in to test the index too
        db.sql("UPDATE users SET email = %s WHERE id = %s", other["email"].replace("@example.com", "@Example.COM"),
               other["id"])
        mixed = other["email"]
        r = c.put(eurl, headers=sh, json={"email": mixed})
        d = _detail(r) or {}
        check(r.status_code == 409 and d.get("code") == "email_taken" and d.get("message"),
              "recovery: another account's address in other case is 409 email_taken", f"{r.status_code} {r.text[:200]}")
        # unchanged
        r = c.put(eurl, headers=sh, json={"email": e["email"].upper()})
        check(r.status_code == 200 and r.json() == {"email": e["email"]} and not _logs(e["id"], "user_email_changed"),
              "recovery: the same address (other case) is 200, no change, no log", f"{r.status_code} {r.text[:200]}")
        check(c.get("/api/auth/me", headers=e["h"]).status_code == 200, "recovery: and the person stays signed in")

        # the change
        n_old = len(_smtp_to(e["email"]))
        r = c.put(eurl, headers=sh, json={"email": "  " + new_addr.replace("example.com", "Example.COM").upper() + " "})
        check(r.status_code == 200 and r.json() == {"email": new_addr},
              "recovery: the correction is 200 with the stored address", f"{r.status_code} {r.text[:200]}")
        check(db.sql("SELECT email FROM users WHERE id = %s", e["id"])[0]["email"] == new_addr,
              "recovery: the address is stored lower-case and trimmed")
        check(c.get("/api/auth/me", headers=e["h"]).status_code == 401, "recovery: the old token is 401")
        check(_wait_mails(e["email"], n_old + 1) == n_old + 1, "recovery: one mail went to the OLD address")
        mail = _smtp_to(e["email"])[-1]
        check("Our support team changed the email you use to sign in to Toe Pwar" in mail and new_addr not in mail
              and "Your Toe Pwar sign-in email was changed" in mail,
              "recovery: the mail has the intro and never names the new address", mail[:300])
        check(len(_smtp_to(new_addr)) == 0, "recovery: nothing went to the new address")
        logs = _logs(e["id"], "user_email_changed")
        check(len(logs) == 1 and logs[0]["details"] == f"{e['email']} -> {new_addr}",
              "recovery: the change is logged old -> new", str(logs))
        # the person recovers through Forgot password with the new address (unverified before, verified after)
        db.sql("UPDATE users SET is_verified = false WHERE id = %s", e["id"])
        c.post("/api/auth/forgot-password/request-otp", json={"email": new_addr})
        _wait_mails(new_addr, 1)
        otp = _latest_otp(new_addr)
        r = c.post("/api/auth/forgot-password/verify-otp", json={"email": new_addr, "otp": otp or "000000"})
        token = r.json().get("reset_token") if r.status_code == 200 else None
        r = c.post("/api/auth/forgot-password/reset-password",
                   json={"email": new_addr, "reset_token": token, "new_password": "newsecret3",
                         "confirm_password": "newsecret3"})
        check(r.status_code == 200, "recovery: Forgot password works with the new address", f"{r.status_code} {r.text[:200]}")
        check(c.post("/api/auth/login", json={"email": new_addr, "password": "newsecret3"}).status_code == 200,
              "recovery: the person signs in with the new address")
        check(c.post("/api/auth/login", json={"email": e["email"], "password": "newsecret3"}).status_code == 401,
              "recovery: the old address no longer signs in")

        # a suspended person's email can be corrected, and the old address is still told
        sa = f"{PREFIX}sus-{uuid.uuid4().hex[:8]}@example.com"
        n_old = len(_smtp_to(s_user["email"]))
        r = c.put(f"/api/admin/users/{s_user['id']}/email", headers=sh, json={"email": sa})
        check(r.status_code == 200 and _wait_mails(s_user["email"], n_old + 1) == n_old + 1,
              "recovery: a suspended person's email is corrected and the old address told",
              f"{r.status_code} {r.text[:200]}")
    finally:
        _cleanup(made_users, made_admins)


# ----------------------------------------------------------------------------------------------------------- effects
def _suspend_in_db(uid, admin_id):
    db.sql("UPDATE users SET suspended_at = now(), suspended_reason = 'e2e', suspended_by = %s WHERE id = %s",
           admin_id, uid)


def _plus(uid):
    db.sql("UPDATE users SET subscription_type = 'plus', subscription_expires_at = now() + interval '30 days', "
           "trial_ends_at = NULL WHERE id = %s", uid)


def _notes(uid, ntype):
    return db.sql("SELECT id FROM notifications WHERE user_id = %s AND type = %s", uid, ntype)


def _book_of(uid):
    return db.sql("SELECT id FROM books WHERE person_id = %s", uid)[0]["id"]


def _roll_budget(book_id, label, ai=False):
    """An auto-create budget of the book whose last day was yesterday; its id."""
    bid = f"ua-roll-{label}-{uuid.uuid4().hex[:6]}"
    today = datetime.now(UTC).date()
    now = datetime.now(UTC)
    db.budgets.insert_one({
        "_id": bid, "book_id": book_id, "name": f"Roll {label}", "period": "custom", "currency": "usd",
        "start_date": today - timedelta(days=7), "end_date": today - timedelta(days=1),
        "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 50, "spent_amount": 0,
                              "percentage_used": 0, "is_exceeded": False}],
        "total_budget": 50, "total_spent": 0, "remaining_budget": 50, "percentage_used": 0,
        "status": "completed", "is_active": False, "auto_create_enabled": True, "auto_create_with_ai": ai,
        "created_at": now, "updated_at": now})
    return bid


def _children(parent_id):
    return db.sql("SELECT id FROM budgets WHERE parent_budget_id = %s", parent_id)


def _ai_rows(user_id=None, book_id=None):
    if book_id:
        return db.sql("SELECT id FROM ai_usage WHERE book_id = %s", book_id)
    return db.sql("SELECT id FROM ai_usage WHERE user_id = %s", user_id)


def section_effects():
    import httpx
    from zoneinfo import ZoneInfo
    import stubenv as se
    c = httpx.Client(base_url=BASE, timeout=60)
    made_users, made_admins = [], []
    title = f"ua-bc-{uuid.uuid4().hex[:8]}"
    try:
        ah, admin_id = _admin(c, "admin")
        made_admins.append(admin_id)
        utc = ZoneInfo("UTC")
        today = datetime.now(UTC).date()
        se.patch_loaded_modules()  # no real push; notices are still stored

        # ---- goal reminders and the trial notice: the suspended person gets none, the twin gets one
        sus, twin = _person(c, made_users, "esus"), _person(c, made_users, "etwin")
        goal_ids = {}
        for p in (sus, twin):
            r = c.post("/api/goals", headers=p["h"], json={
                "name": "Effects goal", "target_amount": 1000, "goal_type": "savings", "currency": "usd",
                "target_date": (today + timedelta(days=7)).isoformat()})
            goal_ids[p["id"]] = r.json().get("id") if r.status_code == 200 else None
            _plus(p["id"])
            db.sql("UPDATE users SET trial_ends_at = now() + interval '2 days', "
                   "subscription_expires_at = now() + interval '2 days' WHERE id = %s", p["id"])
        check(all(goal_ids.values()), "effects: both people made a goal", str(goal_ids))
        _suspend_in_db(sus["id"], admin_id)

        async def reminders():
            import notification_service as ns
            import subscription_service as ss
            await ns.goal_deadline_reminders_for_person(sus["id"], today, utc)
            await ns.goal_deadline_reminders_for_person(twin["id"], today, utc)
            await ss.send_trial_reminders(datetime.now(UTC))
        _backend_async(reminders)
        check(len(_notes(twin["id"], "goal_approaching_date")) == 1,
              "effects: the unsuspended twin gets the goal reminder", str(_notes(twin["id"], "goal_approaching_date")))
        check(not _notes(sus["id"], "goal_approaching_date"), "effects: a suspended person gets no goal reminder")
        check(len(_notes(twin["id"], "trial_ending_soon")) == 1, "effects: the twin gets the trial 'ends soon' notice")
        check(not _notes(sus["id"], "trial_ending_soon"), "effects: a suspended person on trial gets no 'ends soon' notice")

        # ---- broadcast and its stats
        def stats():
            return c.get("/api/admin/broadcast-stats", headers=ah).json()
        db.sql("UPDATE users SET suspended_at = NULL, suspended_reason = NULL, suspended_by = NULL WHERE id = %s",
               sus["id"])
        before = stats()
        _suspend_in_db(sus["id"], admin_id)
        after = stats()
        check(after["total_users"] == before["total_users"] - 1 and after["plus_users"] == before["plus_users"] - 1
              and after["paid_users"] == before["paid_users"] - 1,
              "effects: broadcast-stats leaves a suspended person out of every count", f"{before} -> {after}")
        n_active = db.sql("SELECT count(*) AS n FROM users WHERE suspended_at IS NULL")[0]["n"]
        check(after["total_users"] == n_active, "effects: broadcast-stats total is the unsuspended people",
              f"{after['total_users']} vs {n_active}")
        r = c.post("/api/admin/broadcast-notification", headers=ah, json={
            "title": title, "message": "hello", "notification_type": "system_broadcast", "target_users": "all"})
        check(r.status_code == 200, "effects: the broadcast is sent", f"{r.status_code} {r.text[:200]}")
        rows = db.sql("SELECT user_id FROM notifications WHERE title = %s", title)
        got = {x["user_id"] for x in rows}
        check(twin["id"] in got and sus["id"] not in got, "effects: the broadcast reaches the twin, not the suspended person",
              f"{len(got)} rows")
        check(r.json().get("total_users") == n_active if r.status_code == 200 else False,
              "effects: the broadcast total counts only unsuspended people", r.text[:200])

        # ---- a suspended person's personal book: the weekly insight and AI budgets are skipped, data still rolls
        db.sql("UPDATE users SET suspended_at = NULL, suspended_reason = NULL, suspended_by = NULL WHERE id = %s",
               sus["id"])
        s_book, t_book = _book_of(sus["id"]), _book_of(twin["id"])
        for uid, book in ((sus["id"], s_book), (twin["id"], t_book)):
            db.sql("DELETE FROM insights WHERE book_id = %s", book)
        s_parent = _roll_budget(s_book, "sus", ai=True)
        t_parent = _roll_budget(t_book, "twin", ai=True)
        _suspend_in_db(sus["id"], admin_id)
        db.sql("DELETE FROM ai_usage WHERE user_id = ANY(%s)", [sus["id"], twin["id"]])

        async def personal_jobs():
            import budget_service
            import insights_service
            for book in (s_book, t_book):
                await insights_service.weekly_insight_for_book(book, today, utc)
                await budget_service.budget_rollovers_for_book(book, today, utc)
        _backend_async(personal_jobs)

        def weekly(book):
            return db.sql("SELECT id FROM insights WHERE book_id = %s AND insight_type = 'weekly'", book)
        check(len(_children(s_parent)) == 1, "effects: the suspended person's budget still rolls over (data job)")
        check(len(_children(t_parent)) == 1, "effects: the twin's budget rolls over too")
        check(not weekly(s_book), "effects: no weekly insight is made for a suspended person's personal book")
        check(len(weekly(t_book)) >= 1, "effects: the twin's weekly insight is made (the AI ran for them)")
        check(not _ai_rows(user_id=sus["id"]), "effects: no AI usage is recorded for the suspended person",
              str(_ai_rows(user_id=sus["id"])))
        check(len(_ai_rows(user_id=twin["id"])) >= 1, "effects: the twin's AI work is recorded (the control)")
        check(not _notes(sus["id"], "budget_auto_created") and not _notes(sus["id"], "weekly_insights_generated"),
              "effects: the suspended person gets no budget or insight notice")
        check(len(_notes(twin["id"], "budget_auto_created")) == 1, "effects: the twin gets the 'budget created' notice")

        # ---- a family book owned by a suspended person: the work goes on, only the active member is told
        owner, member = _person(c, made_users, "fowner"), _person(c, made_users, "fmember")
        _plus(owner["id"])
        r = c.post("/api/family", headers=owner["h"], json={"name": f"ua fam {uuid.uuid4().hex[:6]}"})
        fid = ((r.json() if r.status_code == 200 else {}).get("family") or {}).get("id")
        c.post("/api/family/invites", headers=owner["h"], json={"email": member["email"]})
        inv = next((i for i in c.get("/api/family/invites/mine", headers=member["h"]).json().get("invites", [])), None)
        r = c.post(f"/api/family/invites/{inv['id']}/accept", headers=member["h"]) if inv else r
        f_book = (db.sql("SELECT id FROM books WHERE family_id = %s", fid) or [{}])[0].get("id") if fid else None
        check(f_book is not None and r.status_code == 200, "effects: an owner and a member share a family",
              f"{r.status_code} {r.text[:200]}")
        if f_book:
            f_parent = _roll_budget(f_book, "fam", ai=True)
            now_id = f"ua-now-{uuid.uuid4().hex[:6]}"
            ts = datetime.now(UTC)
            db.budgets.insert_one({
                "_id": now_id, "book_id": f_book, "name": "Starts today", "period": "custom", "currency": "usd",
                "start_date": today, "end_date": today + timedelta(days=6),
                "category_budgets": [{"main_category": "Food & Daily Living", "allocated_amount": 50,
                                      "spent_amount": 0, "percentage_used": 0, "is_exceeded": False}],
                "total_budget": 50, "total_spent": 0, "remaining_budget": 50, "percentage_used": 0,
                "status": "active", "is_active": True, "auto_create_enabled": False, "auto_create_with_ai": False,
                "started_notified": False, "created_at": ts, "updated_at": ts})
            db.sql("DELETE FROM insights WHERE book_id = %s", f_book)
            _suspend_in_db(owner["id"], admin_id)

            async def family_jobs():
                import budget_service
                import insights_service
                import notification_service as ns
                await budget_service.budget_rollovers_for_book(f_book, today, utc)
                await ns.budget_now_active_for_book(f_book, today, utc)
                await insights_service.weekly_insight_for_book(f_book, today, utc)
            _backend_async(family_jobs)
            check(len(_children(f_parent)) == 1, "effects: a family book owned by a suspended person still rolls over")
            check(len(_notes(member["id"], "budget_now_active")) == 1,
                  "effects: the active member gets 'budget now active'", str(_notes(member["id"], "budget_now_active")))
            check(len(_notes(member["id"], "budget_auto_created")) == 1,
                  "effects: the active member gets 'budget created' for the rollover")
            check(not _notes(owner["id"], "budget_now_active") and not _notes(owner["id"], "budget_auto_created"),
                  "effects: the suspended owner gets neither notice")
            check(len(weekly(f_book)) >= 1, "effects: the family's weekly insight is still made (never skipped)")
            check(len(_notes(member["id"], "weekly_insights_generated")) == 1
                  and not _notes(owner["id"], "weekly_insights_generated"),
                  "effects: the family insight notice reaches the member only")
    finally:
        try:
            db.sql("DELETE FROM notifications WHERE title = %s", title)
            db.sql("DELETE FROM families WHERE id IN (SELECT family_id FROM family_members WHERE user_id = ANY(%s))",
                   made_users)
        finally:
            _cleanup(made_users, made_admins)


# -------------------------------------------------------------------------------------------------------------- clean
def section_clean():
    n = db.sql("SELECT count(*) AS n FROM users WHERE email LIKE %s", PREFIX + "%")[0]["n"]
    m = db.sql("SELECT count(*) AS n FROM admins WHERE email LIKE %s", PREFIX + "%")[0]["n"]
    check(n == 0 and m == 0, "clean: no throwaway users or admins are left", f"users {n}, admins {m}")


SECTIONS = {"guard": section_guard, "actions": section_actions, "recovery": section_recovery,
            "effects": section_effects, "clean": section_clean}


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
