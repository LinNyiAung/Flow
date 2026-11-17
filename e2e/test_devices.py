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


SECTIONS = {"migration": section_migration, "register": section_register, "logout": section_logout,
            "dead_tokens": section_dead_tokens, "expired_session": section_expired_session}


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
