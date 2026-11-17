"""Devices e2e: push tokens live in user_devices, one row per signed-in device, and every active device of a person
gets their pushes. One function per section, called from main() (or only the sections named on the command line).

Sections:
  migration -- the devices migration on a database seeded in the old shape (users.fcm_token): upgrade gives one
    device row per token (session_expires_at = now + 30 days, no reminder stamp) and drops the column, downgrade puts
    each person's most recently seen token back, and up again works (Task 4).
  register -- POST /api/auth/update-fcm-token: two devices of one person both get a notice's push; a token
    registered by another account moves to it (the first account gets nothing on that phone); previous_token makes the
    old row take the new token (still one row, the old token gets nothing); the row's session_expires_at is the
    bearer token's exp and the reminder stamp is cleared; two simultaneous registrations of one token give one row
    (Task 4). Needs the stub server on 127.0.0.1:8765.
  logout -- DELETE /api/auth/fcm-token {"fcm_token"}: removes only that device of the caller (the other keeps getting
    pushes), leaves another account's token alone (200 either way), and a missing or blank token is 422 (Task 4).
    Needs the stub server.
  dead_tokens -- a token Firebase reports as unregistered (the stub: any "dead-*" token) has its row deleted after a
    notice's push and after a broadcast; a live token's row stays (Task 4). Needs the stub server.
  expired_session -- a device whose session_expires_at has passed gets no notice push; the active one still does
    (Task 4). Needs the stub server.
  reminder -- device_jobs.send_sign_in_reminders (in-process, send_push faked): a device whose sign-in expired gets one
    push with the English (or Myanmar) text and data {"type": "sign_in_reminder"} and no notification row; a second run
    sends nothing; re-registering re-arms it; an active device gets none (Task 5).
  stale -- device_jobs.delete_stale_devices: a device last seen 61 days ago is deleted, one seen 59 days ago stays
    (Task 5).
  password -- a password reset removes every device of the person; a password change keeps only the device whose token
    is sent as fcm_token (no token, or a blank one: removes all) (Task 5). Needs the stub server.
  renewal -- POST /api/auth/renew-session: a fresh token with the full lifetime from now and the same uid and pwv, 
    that works; an expired token and one issued before a password change get 401 (Task 7). Needs the stub server.
  admin -- the admin panel API: the user list and detail show device_count, the detail lists each device's created_at
    and last_seen_at, no token appears in either response, and "push enabled" counts a person with 2 devices once
    (Task 6). Needs the stub server.
"""
import json
import os
import sys
import threading
import time
import uuid
from datetime import UTC, datetime, timedelta

os.environ.setdefault("E2E_FAKE_AI", "1")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402

db = __import__("pgcompat").get_db()
failures = 0

REV_BUDGET_SUB = "b4c7576d96c6"  # the revision the devices migration revises
BASE = "http://127.0.0.1:8765"


def check(ok, name, detail=""):
    global failures
    if not ok:
        failures += 1
    print(("[PASS] " if ok else "[BUG] ") + name + (f" -- {detail}" if detail and not ok else ""), flush=True)


def _columns(table):
    rows = db.sql("SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = %s",
                  table)
    return {r["column_name"] for r in rows}


def wait_for(fn, timeout=8.0):
    end = time.time() + timeout
    while True:
        v = fn()
        if v or time.time() > end:
            return v
        time.sleep(0.25)


def pushes(token):
    """Every push the stub recorded for this device token (one fcm_send line per token)."""
    if not os.path.exists(stubenv.OUTBOX):
        return []
    with open(stubenv.OUTBOX, encoding="utf-8") as f:
        recs = [json.loads(line) for line in f if '"fcm_send"' in line]
    return [r for r in recs if token in (r.get("fcm_token"), r.get("token"))]


def got(token, subject_id):
    """The pushes this token got for the notice about `subject_id`."""
    return [p for p in pushes(token) if (p.get("data") or {}).get("subject_id") == subject_id]


def devices(uid):
    return {r["token"] for r in db.sql("SELECT token FROM user_devices WHERE user_id = %s", uid)}


def device(token):
    return (db.sql("SELECT * FROM user_devices WHERE token = %s", token) or [None])[0]


# ------------------------------------------------------------------------------------------------------- migration
def section_migration():
    import test_plans as t  # noqa: E402  (alembic helper)
    from plans_subscription_checks import head_revision  # noqa: E402

    head = head_revision()
    tag = uuid.uuid4().hex[:8]
    one, two = f"dv-mig1-{tag}", f"dv-mig2-{tag}"
    made = []
    with t.connect() as conn:
        check(t.current_revision(conn) == head, "migration: the e2e database starts at head", t.current_revision(conn))
    try:
        ok, out = t.alembic("downgrade", REV_BUDGET_SUB)
        check(ok, f"migration: downgrade to {REV_BUDGET_SUB} runs", out)
        if not ok:
            return
        check("fcm_token" in _columns("users") and "user_devices" not in {
              r["table_name"] for r in db.sql("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'")},
              "migration: after the downgrade users.fcm_token is back and user_devices is gone")
        for uid in (one, two):
            db.sql("INSERT INTO users (id, name, email, password) VALUES (%s, 'DV', %s, 'x')", uid, f"{uid}@example.com")
            made.append(uid)
        db.sql("UPDATE users SET fcm_token = %s WHERE id = %s", f"mig-{tag}", one)

        # ---- up
        ok, out = t.alembic("upgrade", "head")
        check(ok, "migration: upgrade head runs on the seeded old shape", out)
        if not ok:
            return
        rows = db.sql("SELECT token, session_expires_at, sign_in_reminder_sent_at, last_seen_at FROM user_devices "
                      "WHERE user_id = %s", one)
        want = datetime.now(UTC) + timedelta(days=30)
        check(len(rows) == 1 and rows[0]["token"] == f"mig-{tag}"
              and abs((rows[0]["session_expires_at"] - want).total_seconds()) < 60
              and rows[0]["sign_in_reminder_sent_at"] is None
              and abs((rows[0]["last_seen_at"] - datetime.now(UTC)).total_seconds()) < 60,
              "migration: upgrade gives exactly one device row for the token (session now + 30 days, last seen now, "
              "no reminder stamp)", rows)
        check(not devices(two), "migration: a person without a token gets no device row", devices(two))
        check("fcm_token" not in _columns("users"), "migration: upgrade drops users.fcm_token")

        # The person with two devices gets the most recently seen one back on downgrade.
        db.sql("INSERT INTO user_devices (id, user_id, token, last_seen_at, session_expires_at) VALUES "
               "(%s, %s, %s, now() - interval '2 days', now() + interval '1 day'), "
               "(%s, %s, %s, now(), now() + interval '1 day')",
               str(uuid.uuid4()), two, f"mig-old-{tag}", str(uuid.uuid4()), two, f"mig-new-{tag}")

        # ---- down
        ok, out = t.alembic("downgrade", REV_BUDGET_SUB)
        check(ok, "migration: downgrade runs on the migrated data", out)
        if not ok:
            return
        back = {r["id"]: r["fcm_token"] for r in db.sql("SELECT id, fcm_token FROM users WHERE id = ANY(%s)", made)}
        check(back == {one: f"mig-{tag}", two: f"mig-new-{tag}"},
              "migration: downgrade puts each person's most recently seen token back in users.fcm_token", back)

        # ---- up again
        ok, out = t.alembic("upgrade", "head")
        check(ok, "migration: upgrade head runs again", out)
        if ok:
            check(devices(one) == {f"mig-{tag}"} and devices(two) == {f"mig-new-{tag}"},
                  "migration: upgrade again gives each token its device row", (devices(one), devices(two)))
    finally:
        ok, out = t.alembic("upgrade", "head")  # whatever happened above, leave the database at head
        with t.connect() as conn:
            check(ok and t.current_revision(conn) == head, "migration: the e2e database is left at head", out)
        if made:
            db.sql("DELETE FROM users WHERE id = ANY(%s)", made)


# ------------------------------------------------------------------------------------------------- API helpers
def _people(c, tag, made):
    """register(name, plan) -> {"id", "h", "token"}: a verified account on `plan` registered through the API; its id
    is added to `made`."""
    def register(name, plan="plus"):
        email = f"dv-{name.lower()}-{tag}@example.com"
        r = c.post("/api/auth/register", json={"name": name, "email": email, "password": "secret123"})
        if r.status_code != 200:
            check(False, f"register {name}", f"{r.status_code} {r.text[:200]}")
            return None
        uid = db.sql("SELECT id FROM users WHERE email = %s", email)[0]["id"]
        made.append(uid)
        db.sql("UPDATE users SET is_verified = true, subscription_type = %s, subscription_expires_at = %s, "
               "trial_ends_at = NULL WHERE id = %s", plan, datetime.now(UTC) + timedelta(days=30), uid)
        token = c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json().get("access_token")
        return {"id": uid, "h": {"Authorization": f"Bearer {token}"}, "token": token}
    return register


def _drop_people(made):
    if made:
        db.sql("DELETE FROM users WHERE id = ANY(%s)", made)


def _reg(c, u, token, previous=None):
    body = {"fcm_token": token} | ({"previous_token": previous} if previous else {})
    return c.post("/api/auth/update-fcm-token", headers=u["h"], json=body)


def _unreg(c, u, body):
    return c.request("DELETE", "/api/auth/fcm-token", headers=u["h"], json=body)


def _notice(c, u, tag):
    """A notice for `u` (a running budget's "budget started") -> the budget id, the push data's subject_id."""
    som = datetime.now(UTC).replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    r = c.post("/api/budgets", headers=u["h"], json={
        "name": f"DV {tag}", "period": "monthly", "start_date": som.isoformat(), "currency": "usd",
        "total_budget": 100, "category_budgets": [{"main_category": "Transportation", "allocated_amount": 100}]})
    bid = r.json().get("id") if r.status_code == 200 else None
    if not bid:
        check(False, "a running budget is created (the notice that pushes)", f"{r.status_code} {r.text[:200]}")
    return bid


def _admin_headers(c):
    """A super admin of our own -> (headers, email to delete)."""
    import admin_utils
    email, pw = f"dv-admin-{uuid.uuid4().hex[:8]}@example.com", "dv-admin-pass-1"
    db.admins.insert_one({"_id": str(uuid.uuid4()), "name": "devices admin", "email": email,
                          "password": admin_utils.get_password_hash(pw), "role": "super_admin",
                          "created_at": datetime.now(UTC), "last_login": None})
    r = c.post("/api/admin/login", json={"email": email, "password": pw})
    return {"Authorization": "Bearer " + r.json().get("access_token", "")}, email


# -------------------------------------------------------------------------------------------------------- register
def section_register():
    import httpx
    import jwt

    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:8]
    made = []
    register = _people(c, tag, made)
    a1, a2, a3 = f"a1-{tag}", f"a2-{tag}", f"a3-{tag}"
    try:
        A, B = register("Ann"), register("Ben")
        if not (A and B):
            return

        # ---- two devices both get pushes
        r1, r2 = _reg(c, A, a1), _reg(c, A, a2)
        check(r1.status_code == 200 and r2.status_code == 200 and devices(A["id"]) == {a1, a2},
              "two devices both get pushes: A registers two tokens, A has two device rows",
              (r1.status_code, r2.status_code, devices(A["id"])))
        bid = _notice(c, A, tag)
        p1, p2 = wait_for(lambda: got(a1, bid)), wait_for(lambda: got(a2, bid))
        check(bid and len(p1) == 1 and len(p2) == 1, "two devices both get pushes: a notice for A reaches both devices",
              (len(p1), len(p2)))

        # ---- a token moves to the new account
        r = _reg(c, B, a1)
        check(r.status_code == 200 and devices(A["id"]) == {a2} and devices(B["id"]) == {a1},
              "a token moves to the new account: B registers A's token, the row is B's now",
              (r.status_code, devices(A["id"]), devices(B["id"])))
        bid = _notice(c, A, tag)
        p2 = wait_for(lambda: got(a2, bid))
        time.sleep(0.5)
        check(bid and len(p2) == 1 and got(a1, bid) == [],
              "a token moves to the new account: a notice for A reaches only A's other device", (len(p2), got(a1, bid)))
        bid_b = _notice(c, B, tag)
        pb = wait_for(lambda: got(a1, bid_b))
        check(bid_b and len(pb) == 1, "a token moves to the new account: a notice for B reaches the moved token", pb)

        # ---- previous token replaces the row
        old_row = device(a2)
        r = _reg(c, A, a3, previous=a2)
        new_row = device(a3)
        check(r.status_code == 200 and devices(A["id"]) == {a3} and old_row and new_row
              and new_row["id"] == old_row["id"] and new_row["created_at"] == old_row["created_at"],
              "previous token replaces the row: A's one row now holds the new token (same row)",
              (r.status_code, devices(A["id"]), old_row, new_row))
        bid = _notice(c, A, tag)
        p3 = wait_for(lambda: got(a3, bid))
        time.sleep(0.5)
        check(bid and len(p3) == 1 and got(a2, bid) == [],
              "previous token replaces the row: the new token gets the push and the old one nothing",
              (len(p3), got(a2, bid)))
        r = _reg(c, A, a3, previous=a1)  # B's token named as previous: not the caller's row, B keeps it
        check(r.status_code == 200 and devices(A["id"]) == {a3} and devices(B["id"]) == {a1},
              "previous token replaces the row: another account's token named as previous_token is left alone",
              (r.status_code, devices(A["id"]), devices(B["id"])))

        # ---- expiry follows the request token
        db.sql("UPDATE user_devices SET session_expires_at = now() - interval '1 day', "
               "sign_in_reminder_sent_at = now(), last_seen_at = now() - interval '3 days' WHERE token = %s", a3)
        exp = jwt.decode(A["token"], options={"verify_signature": False})["exp"]
        r = _reg(c, A, a3)
        row = device(a3) or {}
        check(r.status_code == 200 and row.get("session_expires_at") == datetime.fromtimestamp(exp, UTC)
              and row.get("sign_in_reminder_sent_at") is None
              and abs((row.get("last_seen_at") - datetime.now(UTC)).total_seconds()) < 60,
              "expiry follows the request token: session_expires_at is the bearer token's exp, the reminder stamp is "
              "cleared and last_seen_at is now", (r.status_code, row, datetime.fromtimestamp(exp, UTC)))

        # ---- concurrent same token
        for i in range(3):
            tok = f"cc{i}-{tag}"
            start = threading.Barrier(2)
            codes = []

            def post():
                with httpx.Client(base_url=BASE, timeout=60) as cc:
                    start.wait()
                    codes.append(_reg(cc, A, tok).status_code)
            threads = [threading.Thread(target=post) for _ in range(2)]
            for th in threads:
                th.start()
            for th in threads:
                th.join()
            n = db.sql("SELECT count(*) AS n FROM user_devices WHERE token = %s", tok)[0]["n"]
            check(codes == [200, 200] and n == 1,
                  f"concurrent same token: two simultaneous registrations give one row (try {i + 1})", (codes, n))
    finally:
        _drop_people(made)


# ---------------------------------------------------------------------------------------------------------- logout
def section_logout():
    import httpx

    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:8]
    made = []
    register = _people(c, tag, made)
    x1, x2, y1 = f"x1-{tag}", f"x2-{tag}", f"y1-{tag}"
    try:
        A, B = register("Lia"), register("Leo")
        if not (A and B):
            return
        for u, tok in ((A, x1), (A, x2), (B, y1)):
            _reg(c, u, tok)
        check(devices(A["id"]) == {x1, x2} and devices(B["id"]) == {y1}, "logout: A has two devices and B one",
              (devices(A["id"]), devices(B["id"])))

        # ---- DELETE removes only that device
        r = _unreg(c, A, {"fcm_token": x1})
        check(r.status_code == 200 and devices(A["id"]) == {x2},
              "DELETE removes only that device: A logs out on one device, the other row stays",
              (r.status_code, r.text[:200], devices(A["id"])))
        bid = _notice(c, A, tag)
        p2 = wait_for(lambda: got(x2, bid))
        time.sleep(0.5)
        check(bid and len(p2) == 1 and got(x1, bid) == [],
              "DELETE removes only that device: the other device keeps getting pushes, the logged-out one none",
              (len(p2), got(x1, bid)))
        r = _unreg(c, A, {"fcm_token": x1})
        check(r.status_code == 200, "DELETE removes only that device: a retry of the same logout is 200", r.status_code)

        # ---- another account's token is untouched
        r = _unreg(c, A, {"fcm_token": y1})
        row = device(y1) or {}
        check(r.status_code == 200 and row.get("user_id") == B["id"],
              "another account's token is untouched: A deleting B's token gets 200 and the row is still B's",
              (r.status_code, row))

        # ---- missing token is 422
        for body in ({}, {"fcm_token": " "}, {"fcm_token": ""}):
            r = _unreg(c, A, body)
            check(r.status_code == 422, f"missing token is 422: {json.dumps(body)}", (r.status_code, r.text[:200]))
        r = c.request("DELETE", "/api/auth/fcm-token", headers=A["h"])
        check(r.status_code == 422, "missing token is 422: no body at all", (r.status_code, r.text[:200]))
        check(devices(A["id"]) == {x2} and devices(B["id"]) == {y1}, "missing token is 422: nothing was removed",
              (devices(A["id"]), devices(B["id"])))
    finally:
        _drop_people(made)


# ----------------------------------------------------------------------------------------------------- dead tokens
def section_dead_tokens():
    import httpx

    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:8]
    made = []
    register = _people(c, tag, made)
    dead, live, dead_bc = f"dead-{tag}", f"live-{tag}", f"dead-bc-{tag}"
    admin_email = None
    try:
        A = register("Dee", "pro")
        if not A:
            return
        _reg(c, A, dead)
        _reg(c, A, live)
        check(devices(A["id"]) == {dead, live}, "dead tokens: A has a dead and a live device", devices(A["id"]))

        bid = _notice(c, A, tag)
        gone = wait_for(lambda: dead not in devices(A["id"]))
        check(bid and gone and devices(A["id"]) == {live},
              "dead tokens: after a notice's push the unregistered token's row is deleted and the live one stays",
              devices(A["id"]))
        check(len(wait_for(lambda: got(live, bid))) == 1, "dead tokens: the live device got the notice's push",
              got(live, bid))

        # ---- a broadcast does the same
        _reg(c, A, dead_bc)
        check(devices(A["id"]) == {live, dead_bc}, "dead tokens: A registers another dead token", devices(A["id"]))
        AD, admin_email = _admin_headers(c)
        r = c.post("/api/admin/broadcast-notification", headers=AD,
                   json={"title": f"DV {tag}", "message": "Devices broadcast", "target_users": "pro"})
        check(r.status_code == 200 and devices(A["id"]) == {live},
              "dead tokens: after a broadcast the unregistered token's row is deleted and the live one stays",
              (r.status_code, r.text[:200], devices(A["id"])))
    finally:
        _drop_people(made)
        if admin_email:
            db.admins.delete_many({"email": admin_email})


# ------------------------------------------------------------------------------------------------- expired session
def section_expired_session():
    import httpx

    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:8]
    made = []
    register = _people(c, tag, made)
    e1, e2 = f"e1-{tag}", f"e2-{tag}"
    try:
        A = register("Eve")
        if not A:
            return
        _reg(c, A, e1)
        _reg(c, A, e2)
        db.sql("UPDATE user_devices SET session_expires_at = now() - interval '1 minute' WHERE token = %s", e1)
        bid = _notice(c, A, tag)
        p2 = wait_for(lambda: got(e2, bid))
        time.sleep(0.5)
        check(bid and len(p2) == 1 and got(e1, bid) == [],
              "expired session: a notice for A skips the device whose sign-in expired and reaches the active one",
              (len(p2), got(e1, bid)))
        check(devices(A["id"]) == {e1, e2}, "expired session: the expired device's row is kept (for its reminder)",
              devices(A["id"]))
    finally:
        _drop_people(made)


# ----------------------------------------------------------------------------------------------- in-process helpers
_loop = None


def run(coro):
    """Runs a backend coroutine in-process on one loop (the backend's DB engine belongs to the loop it first ran on)."""
    global _loop
    if _loop is None:
        _loop = __import__("asyncio").new_event_loop()
    return _loop.run_until_complete(coro)


def _expire(token, ago="1 hour"):
    db.sql(f"UPDATE user_devices SET session_expires_at = now() - interval '{ago}', sign_in_reminder_sent_at = NULL "
           "WHERE token = %s", token)


# ------------------------------------------------------------------------------------------------------- reminder
def section_reminder():
    import httpx

    import device_jobs
    from notification_service import translate

    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:8]
    made = []
    register = _people(c, tag, made)
    sent = []  # (tokens, title, body, data) of every push the job made

    def fake_send_push(tokens, title, body, data=None):
        sent.append((list(tokens), title, body, data))
        return {"success": len(tokens), "failure": 0, "unregistered": []}

    real = device_jobs.send_push
    device_jobs.send_push = fake_send_push
    try:
        A, B = register("Rem", "free"), register("Ria", "free")
        if not (A and B):
            return
        db.sql("UPDATE users SET language = 'my' WHERE id = %s", B["id"])
        ra, rb, rc = f"ra-{tag}", f"rb-{tag}", f"rc-{tag}"
        _reg(c, A, ra)
        _reg(c, B, rb)
        _reg(c, A, rc)
        _expire(ra)
        _expire(rb)  # rc stays active

        def pushes_to(token):
            return [s for s in sent if token in s[0]]

        before = db.sql("SELECT count(*) AS n FROM notifications WHERE user_id = ANY(%s)", made)[0]["n"]
        n = run(device_jobs.send_sign_in_reminders())
        check(n >= 2, "expired device gets one reminder: the job reports the pushes it sent", n)
        pa = pushes_to(ra)
        check(len(pa) == 1 and pa[0][1] == "Sign in to Toe Pwar"
              and pa[0][2] == "You've been signed out. Sign in to keep getting your budget and goal alerts."
              and pa[0][3] == {"type": "sign_in_reminder"},
              "expired device gets one reminder: English title, body and data exactly {type: sign_in_reminder}", pa)
        after = db.sql("SELECT count(*) AS n FROM notifications WHERE user_id = ANY(%s)", made)[0]["n"]
        check(after == before, "expired device gets one reminder: no notification row is created", (before, after))
        check((device(ra) or {}).get("sign_in_reminder_sent_at") is not None,
              "expired device gets one reminder: the device is stamped")

        pb = pushes_to(rb)
        check(len(pb) == 1 and pb[0][1] == translate("sign_in_reminder_title", "my")
              and pb[0][2] == translate("sign_in_reminder_msg", "my") and pb[0][1] != "Sign in to Toe Pwar",
              "Myanmar user gets the Myanmar text", pb)

        check(pushes_to(rc) == [], "active device gets none", pushes_to(rc))

        # ---- sent once
        sent.clear()
        run(device_jobs.send_sign_in_reminders())
        check(pushes_to(ra) == [] and pushes_to(rb) == [], "sent once: a second run sends nothing to those devices",
              sent)

        # ---- re-register resets
        r = _reg(c, A, ra)
        check(r.status_code == 200 and (device(ra) or {}).get("sign_in_reminder_sent_at") is None,
              "re-register resets: registering clears the stamp", r.status_code)
        sent.clear()
        run(device_jobs.send_sign_in_reminders())
        check(pushes_to(ra) == [], "re-register resets: the re-registered (active) device gets none yet", sent)
        _expire(ra)
        run(device_jobs.send_sign_in_reminders())
        check(len(pushes_to(ra)) == 1, "re-register resets: expiring it again sends the next reminder",
              pushes_to(ra))
    finally:
        device_jobs.send_push = real
        _drop_people(made)


# ---------------------------------------------------------------------------------------------------------- stale
def section_stale():
    import httpx

    import device_jobs

    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:8]
    made = []
    register = _people(c, tag, made)
    old, fresh = f"old-{tag}", f"fresh-{tag}"
    try:
        A = register("Sta", "free")
        if not A:
            return
        _reg(c, A, old)
        _reg(c, A, fresh)
        db.sql("UPDATE user_devices SET last_seen_at = now() - interval '61 days' WHERE token = %s", old)
        db.sql("UPDATE user_devices SET last_seen_at = now() - interval '59 days' WHERE token = %s", fresh)
        n = run(device_jobs.delete_stale_devices())
        check(n >= 1 and devices(A["id"]) == {fresh},
              "stale: the device last seen 61 days ago is deleted and the one seen 59 days ago is kept",
              (n, devices(A["id"])))
    finally:
        _drop_people(made)


# -------------------------------------------------------------------------------------------------------- password
def _latest_otp(email):
    code = None
    with open(stubenv.OUTBOX, encoding="utf-8") as f:
        for line in f:
            rec = json.loads(line)
            if rec.get("kind") != "smtp":
                continue
            body = " ".join(rec.get("args", []))
            if email in body and "Password Reset" in body:
                m = __import__("re").search(r"verification code is:\s+(\d{6})", body.replace("\\n", "\n"))
                if m:
                    code = m.group(1)
    return code


def section_password():
    import httpx

    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:8]
    made = []
    register = _people(c, tag, made)
    d1, d2, d3 = f"pw1-{tag}", f"pw2-{tag}", f"pw3-{tag}"
    try:
        A = register("Pat", "free")
        if not A:
            return
        email = f"dv-pat-{tag}@example.com"
        _reg(c, A, d1)
        _reg(c, A, d2)
        check(devices(A["id"]) == {d1, d2}, "password: the person has two devices", devices(A["id"]))

        # ---- reset removes every device
        c.post("/api/auth/forgot-password/request-otp", json={"email": email})
        otp = wait_for(lambda: _latest_otp(email))
        r = c.post("/api/auth/forgot-password/verify-otp", json={"email": email, "otp": otp})
        rt = r.json().get("reset_token") if r.status_code == 200 else None
        r = c.post("/api/auth/forgot-password/reset-password",
                   json={"email": email, "reset_token": rt, "new_password": "secret456", "confirm_password": "secret456"})
        check(r.status_code == 200 and devices(A["id"]) == set(),
              "reset removes every device: after the reset flow the person has 0 rows", (r.status_code, devices(A["id"])))

        def signed_in(password):
            tok = c.post("/api/auth/login", json={"email": email, "password": password}).json().get("access_token")
            return {"id": A["id"], "h": {"Authorization": f"Bearer {tok}"}}

        # ---- change keeps the sender's device
        U = signed_in("secret456")
        for t in (d1, d2, d3):
            _reg(c, U, t)
        r = c.put("/api/auth/change-password", headers=U["h"], json={
            "current_password": "secret456", "new_password": "secret789", "confirm_password": "secret789",
            "fcm_token": d1})
        check(r.status_code == 200 and devices(A["id"]) == {d1},
              "change keeps the sender's device: change-password with fcm_token d1 leaves rows {d1}",
              (r.status_code, r.text[:200], devices(A["id"])))

        # ---- change without a token removes all (absent, then blank)
        for label, extra, pw_from, pw_to in (("without token", {}, "secret789", "secret000"),
                                             ("with a blank token", {"fcm_token": "  "}, "secret000", "secret111")):
            U = signed_in(pw_from)
            _reg(c, U, d1)
            _reg(c, U, d2)
            r = c.put("/api/auth/change-password", headers=U["h"], json={
                "current_password": pw_from, "new_password": pw_to, "confirm_password": pw_to} | extra)
            check(r.status_code == 200 and devices(A["id"]) == set(),
                  f"change {label} removes all", (r.status_code, r.text[:200], devices(A["id"])))
    finally:
        _drop_people(made)


def section_admin():
    import httpx

    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:8]
    made = []
    register = _people(c, tag, made)
    t1, t2 = f"ad1-{tag}", f"ad2-{tag}"
    AD, admin_email = _admin_headers(c)
    try:
        P = register("Pia", "free")
        if not P:
            return
        email = f"dv-pia-{tag}@example.com"

        def push_enabled():
            r = c.get("/api/admin/broadcast-stats", headers=AD)
            return r.json().get("users_with_push_enabled") if r.status_code == 200 else None

        before = push_enabled()
        _reg(c, P, t1)
        _reg(c, P, t2)

        # ---- list shows device count
        r = c.get("/api/admin/users", headers=AD, params={"search": email})
        rows = r.json() if r.status_code == 200 else []
        row = next((u for u in rows if u.get("id") == P["id"]), {})
        check(r.status_code == 200 and row.get("device_count") == 2,
              "list shows device count: a user with 2 devices has device_count 2 in the user list",
              (r.status_code, row.get("device_count")))

        # ---- detail lists devices without tokens
        r = c.get(f"/api/admin/users/{P['id']}", headers=AD)
        body = r.json() if r.status_code == 200 else {}
        devs = body.get("devices") or []
        check(r.status_code == 200 and body.get("device_count") == 2 and len(devs) == 2
              and all(d.get("created_at") and d.get("last_seen_at") for d in devs),
              "detail lists devices without tokens: 2 devices, each with created_at and last_seen_at",
              (r.status_code, body.get("device_count"), devs))
        check(t1 not in r.text and t2 not in r.text and all(set(d) == {"created_at", "last_seen_at"} for d in devs),
              "detail lists devices without tokens: the response text holds neither token")
        r = c.get("/api/admin/users", headers=AD, params={"search": email})
        check(t1 not in r.text and t2 not in r.text, "detail lists devices without tokens: nor does the user list")

        # ---- a person with no device
        Q = register("Quin", "free")
        if Q:
            r = c.get(f"/api/admin/users/{Q['id']}", headers=AD)
            body = r.json() if r.status_code == 200 else {}
            check(body.get("device_count") == 0 and body.get("devices") == [],
                  "detail of a person with no device: device_count 0 and an empty list", (r.status_code, body))

        # ---- push enabled counts people
        after = push_enabled()
        check(before is not None and after == before + 1,
              "push enabled counts people: a person with 2 devices adds exactly 1", (before, after))
    finally:
        _drop_people(made)
        db.admins.delete_many({"email": admin_email})


def section_renewal():
    import httpx
    import jwt
    from config import settings
    from utils import create_access_token

    c = httpx.Client(base_url=BASE, timeout=60)
    tag = uuid.uuid4().hex[:8]
    made = []
    register = _people(c, tag, made)

    def decode(tok):
        return jwt.decode(tok, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])

    try:
        A = register("Rena", "free")
        if not A:
            return
        email = f"dv-rena-{tag}@example.com"
        old = decode(A["token"])

        # ---- the renewed token lasts the full lifetime from now
        time.sleep(1.1)  # so the new exp is visibly later than the old one
        r = c.post("/api/auth/renew-session", headers=A["h"])
        body = r.json() if r.status_code == 200 else {}
        new_tok = body.get("access_token")
        check(r.status_code == 200 and body.get("token_type") == "bearer" and bool(new_tok),
              "renewed token lasts 30 days from now: 200 with a bearer access_token", (r.status_code, r.text[:200]))
        new = decode(new_tok) if new_tok else {}
        want = datetime.now(UTC) + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
        exp = datetime.fromtimestamp(new.get("exp", 0), UTC)
        check(abs(exp - want) < timedelta(minutes=1) and new.get("exp", 0) > old["exp"]
              and new.get("uid") == old["uid"] and new.get("pwv") == old["pwv"],
              "renewed token lasts 30 days from now: new exp is now + lifetime and later than the old one; uid and pwv equal",
              (new, old))

        # ---- the renewed token works
        r = c.get("/api/auth/me", headers={"Authorization": f"Bearer {new_tok}"})
        check(r.status_code == 200, "renewed token works: GET /api/auth/me is 200", r.status_code)

        # ---- an expired token is refused
        expired = create_access_token(data={"sub": email, "uid": A["id"], "pwv": old["pwv"]},
                                      expires_delta=timedelta(seconds=-1))
        r = c.post("/api/auth/renew-session", headers={"Authorization": f"Bearer {expired}"})
        check(r.status_code == 401, "expired token refused: 401", r.status_code)

        # ---- a token issued before a password change is refused
        r = c.put("/api/auth/change-password", headers=A["h"], json={
            "current_password": "secret123", "new_password": "secret456", "confirm_password": "secret456"})
        check(r.status_code == 200, "revoked token refused: the password change worked", (r.status_code, r.text[:200]))
        r = c.post("/api/auth/renew-session", headers=A["h"])
        check(r.status_code == 401, "revoked token refused: the pre-change token gets 401", r.status_code)
        r = c.post("/api/auth/renew-session")
        check(r.status_code in (401, 403), "no token refused", r.status_code)
    finally:
        _drop_people(made)

SECTIONS = {"migration": section_migration, "register": section_register, "logout": section_logout,
            "dead_tokens": section_dead_tokens, "expired_session": section_expired_session,
            "reminder": section_reminder, "stale": section_stale, "password": section_password,
            "admin": section_admin, "renewal": section_renewal}


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
