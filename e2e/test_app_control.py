"""App control e2e (docs/superpowers/specs/2026-11-25-app-control-design.md).

Sections (named on the command line, all by default):
  store -- the settings document in-process: validation, save -> cache -> load, the paused messages in both
    languages, FeaturePaused, a bad or older stored document, tester matching.
  admin_api -- GET/PUT /api/admin/app-control over HTTP: a moderator reads and can't change, an admin changes, a bad
    document is a readable 422, the change is in the admin log.
  announcements -- /api/admin/app-control/announcements: create, validation (link, naive times, order, texts), update,
    delete, the admin log, moderator read-only.
  config -- GET /api/app/config: signed out, per plan, time windows, newest wins, invalid token, maintenance can_enter.
Every section that changes the stored settings puts the original document back in `finally`.
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


REAL_KEY = "app_control"
E2E_KEY = "app_control_e2e"  # the in-process tests save here, never into the row the stub server reads


def _stored(key=REAL_KEY):
    rows = db.sql("SELECT value FROM app_settings WHERE key = %s", key)
    return rows[0]["value"] if rows else None


def _restore(original, key=REAL_KEY):
    if original is None:
        db.sql("DELETE FROM app_settings WHERE key = %s", key)
    else:
        db.sql("INSERT INTO app_settings (key, value) VALUES (%s, %s) "
               "ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value", key, original)


def _set_raw(value, key=REAL_KEY):
    _restore(value, key)


def _clean_doc(original):
    """The document to put back through the API: the stored original, or the all-defaults document."""
    import app_control as ac
    return ac.validate(json.loads(original)) if original is not None else ac.validate({})


def _use_key(key):
    """Point the in-process settings reads and writes at `key` (read at call time); returns the previous key."""
    from sql import app_control as app_control_db
    prev = app_control_db.SETTINGS_KEY
    app_control_db.SETTINGS_KEY = key
    return prev


# ------------------------------------------------------------------------------------------------------------ store
def section_store():
    import app_control as ac
    from notification_service import translate

    check(ac.SWITCHES == ("chat", "voice", "receipts", "budget_ideas", "reports", "custom_reports", "translation",
                          "signups", "free_trial", "family_new"), "store: the ten switches")
    doc = ac.validate({"switches": {"voice": {"paused": True, "message_en": "Back at 5", "message_my": ""}},
                       "maintenance": {"on": False, "message_en": "", "message_my": "", "back_by": None,
                                       "testers": [" Tester@Example.com "]}})
    check(set(doc["switches"]) == set(ac.SWITCHES) and doc["switches"]["chat"]["paused"] is False,
          "store: missing switches default to not paused")
    check(doc["maintenance"]["testers"] == ["tester@example.com"], "store: testers trimmed and lowercased")
    for bad in ({"switches": {"nope": {"paused": True}}}, {"switches": {"voice": {"paused": "yes"}}},
                {"switches": {"voice": {"paused": True, "message_en": "x" * 301}}},
                {"maintenance": {"on": True, "testers": ["not-an-email"]}},
                {"maintenance": {"on": True, "testers": [f"t{i}@e.com" for i in range(51)]}},
                {"maintenance": {"on": True, "back_by": "2026-12-01T10:00:00"}}):  # naive time
        try:
            ac.validate(bad)
            check(False, f"store: rejects {list(bad)}")
        except ValueError:
            check(True, f"store: rejects {list(bad)}")
    ok = ac.validate({"maintenance": {"on": True, "back_by": "2026-12-01T10:00:00+06:30"}})
    check(ok["maintenance"]["back_by"] == "2026-12-01T10:00:00+06:30", "store: an aware back_by is kept")

    original = _stored()
    prev_key = _use_key(E2E_KEY)

    async def run():
        await ac.save({"switches": {"voice": {"paused": True, "message_en": "Back at 5", "message_my": ""}},
                       "maintenance": {"on": True, "message_en": "", "message_my": "",
                                       "back_by": "2026-12-01T10:00:00+06:30", "testers": ["Tester@Example.com"]}},
                      "test-admin")
        res = {}
        res["paused"] = (ac.is_paused("voice"), ac.is_paused("chat"))
        res["en"] = ac.paused_message("voice", "en")
        res["my"] = ac.paused_message("voice", "my")
        res["chat_en"] = ac.paused_message("chat", "en")
        res["both"] = ac.both_languages("voice")
        res["tester"] = (ac.is_tester("TESTER@example.com"), ac.is_tester(None), ac.is_tester("x@example.com"))
        res["maint"] = (ac.maintenance_on(), ac.maintenance_message("en"), ac.maintenance_message("my"),
                        ac.maintenance_back_by())
        try:
            ac.require_on("voice", "my")
            res["raised"] = None
        except ac.FeaturePaused as e:
            res["raised"] = (e.status_code, e.detail)
        ac.require_on("chat")  # not paused: no error
        # the stored text is what a fresh load reads back
        ac._set_cache(ac._default())
        await ac.load()
        res["reloaded"] = ac.is_paused("voice")
        # a stored value that isn't JSON: nothing paused
        _set_raw("not json", E2E_KEY)
        await ac.load()
        res["bad_json"] = [k for k in ac.SWITCHES if ac.is_paused(k)]
        # an older / hand-edited document: unknown key dropped, voice paused, the rest default
        _set_raw(json.dumps({"switches": {"nope": {"paused": True}, "voice": {"paused": True}}}), E2E_KEY)
        await ac.load()
        res["unknown"] = ([k for k in ac.SWITCHES if ac.is_paused(k)], "nope" in ac.snapshot()["switches"])
        # nothing stored at all
        db.sql("DELETE FROM app_settings WHERE key = %s", E2E_KEY)
        await ac.load()
        res["none"] = [k for k in ac.SWITCHES if ac.is_paused(k)]
        return res

    try:
        res = _backend_async(run)
    finally:
        _use_key(prev_key)
        _restore(None, E2E_KEY)

    check(res["paused"] == (True, False), "store: save applies at once")
    check(res["en"] == "Back at 5", "store: the owner's English message")
    check(res["my"] == translate("feature_paused_msg", "my", feature=translate("app_switch_voice", "my")),
          "store: an empty Myanmar message uses the standard one")
    check(res["chat_en"] == "Paused for now: Chat with Ko Toe Pwar. Please try again later.",
          "store: the standard English message names the feature")
    check(res["both"] == res["en"] + "\n\n" + res["my"], "store: both_languages joins English and Myanmar")
    check(res["raised"] is not None and res["raised"][0] == 403 and res["raised"][1]["code"] == "feature_paused"
          and res["raised"][1]["feature"] == "voice" and res["raised"][1]["message"] == res["my"],
          "store: FeaturePaused is 403 feature_paused with the message in the language asked", res["raised"])
    check(res["raised"] is not None and res["raised"][1] == {"code": "feature_paused", "feature": "voice",
                                                             "message": res["my"]},
          "store: FeaturePaused detail is exactly code, feature, message", res["raised"])
    check(res["tester"] == (True, False, False), "store: tester match ignores case")
    check(res["maint"][0] and res["maint"][1] == translate("maintenance_msg", "en")
          and res["maint"][2] == translate("maintenance_msg", "my")
          and res["maint"][3] == datetime(2026, 12, 1, 3, 30, tzinfo=UTC), "store: maintenance values", res["maint"])
    check(res["reloaded"], "store: save -> load round trip")
    check(res["bad_json"] == [], "store: a stored value that isn't JSON pauses nothing")
    check(res["unknown"] == (["voice"], False), "store: an unknown stored switch is dropped, the rest kept", res["unknown"])
    check(res["none"] == [], "store: nothing stored pauses nothing")
    check(_stored() == original, "store: the stored document is back as it was")

    def _reload():
        async def go():
            await ac.load()
        _backend_async(go)
    _reload()


# -------------------------------------------------------------------------------------------------------- admin_api
def _admin(c, role):
    import admin_utils
    email, pw = f"ac-{role}-{uuid.uuid4().hex[:8]}@example.com", "ac-admin-pass-1"
    aid = str(uuid.uuid4())
    db.admins.insert_one({"_id": aid, "name": f"ac {role}", "email": email,
                          "password": admin_utils.get_password_hash(pw), "role": role,
                          "created_at": datetime.now(UTC), "last_login": None})
    r = c.post("/api/admin/login", json={"email": email, "password": pw})
    return {"Authorization": "Bearer " + r.json().get("access_token", "")}, email, aid


def section_admin_api():
    import httpx
    c = httpx.Client(base_url=BASE, timeout=60)
    original = _stored()
    made = []
    start = ah = None
    try:
        mh, memail, mid = _admin(c, "moderator")
        ah, aemail, aid = _admin(c, "admin")
        made += [mid, aid]
        r = c.get("/api/admin/app-control", headers=mh)
        body = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and len(body.get("switches", [])) == 10
              and body["switches"][0] == {"key": "chat", "name_en": "Chat with Ko Toe Pwar"}
              and set(body["settings"]["switches"]) == {s["key"] for s in body["switches"]},
              "admin_api: a moderator reads the settings", f"{r.status_code} {r.text[:200]}")
        check(body["settings"]["maintenance"]["on"] is False, "admin_api: maintenance is off at the start of the section")
        start = _clean_doc(original)
        r = c.put("/api/admin/app-control", headers=mh, json=start)
        check(r.status_code == 403, "admin_api: a moderator can't change them", r.status_code)
        r = c.put("/api/admin/app-control", headers=ah,
                  json={"switches": {"voice": {"paused": True, "message_en": "x" * 301}}})
        check(r.status_code == 422 and isinstance(r.json().get("detail"), str) and "300" in r.json()["detail"],
              "admin_api: a bad document is a readable 422", f"{r.status_code} {r.text[:200]}")
        r = c.put("/api/admin/app-control", headers=ah, json={"switches": {"nope": {"paused": True}}})
        check(r.status_code == 422 and "nope" in str(r.json().get("detail")), "admin_api: an unknown switch is a 422",
              f"{r.status_code} {r.text[:200]}")
        r = c.put("/api/admin/app-control", headers=ah, json={"extra": 1})
        check(r.status_code == 422, "admin_api: an unknown field is refused", r.status_code)
        new = {**start, "switches": {**start["switches"], "voice": {"paused": True, "message_en": "Back at 5",
                                                                     "message_my": ""}}}
        r = c.put("/api/admin/app-control", headers=ah, json=new)
        check(r.status_code == 200 and r.json()["switches"]["voice"]["paused"] is True,
              "admin_api: an admin pauses voice", f"{r.status_code} {r.text[:200]}")
        g = c.get("/api/admin/app-control", headers=mh).json()
        check(g["settings"]["switches"]["voice"]["message_en"] == "Back at 5", "admin_api: a GET shows it")
        logs = db.sql("SELECT details FROM admin_action_logs WHERE admin_id = %s AND action = 'app_control_update'", aid)
        check(len(logs) == 1 and "voice" in (logs[0]["details"] or "") and len(logs[0]["details"]) <= 2000,
              "admin_api: the admin log has app_control_update naming voice", logs)
        r = c.get("/api/admin/app-control")
        check(r.status_code in (401, 403), "admin_api: no token is refused", r.status_code)
    finally:
        # The server caches the document: put it back through the API too (not only in the table), or the pause
        # stays on there until its next refresh.
        try:
            if ah is not None:
                c.put("/api/admin/app-control", headers=ah, json=_clean_doc(original))
        except Exception:  # noqa: BLE001
            pass
        _restore(original)
        if made:
            db.sql("DELETE FROM admin_action_logs WHERE admin_id = ANY(%s)", made)
            db.sql("DELETE FROM admins WHERE id = ANY(%s)", made)
    check(_stored() == original, "admin_api: the stored document is back as it was")


# ------------------------------------------------------------------------------------------------------- switches
def _person(c, made, label, plan="plus", language=None):
    """A verified account on `plan` (id, email, book, h: the auth header), optionally with the language set."""
    tag = uuid.uuid4().hex[:8]
    email = f"acs-{label.lower()}-{tag}@example.com"
    c.post("/api/auth/register", json={"name": label, "email": email, "password": "secret123"})
    db.sql("UPDATE users SET is_verified = true WHERE lower(email) = %s", email)
    rows = db.sql("SELECT id FROM users WHERE lower(email) = %s", email)
    uid = rows[0]["id"] if rows else None
    made.append(uid)
    if plan != "free":
        db.sql("UPDATE users SET subscription_type = %s, subscription_expires_at = now() + interval '30 days', "
               "trial_ends_at = NULL WHERE id = %s", plan, uid)
    if language:
        db.sql("UPDATE users SET language = %s WHERE id = %s", language, uid)
    r = c.post("/api/auth/login", json={"email": email, "password": "secret123"})
    book = db.sql("SELECT id FROM books WHERE person_id = %s", uid)
    return {"id": uid, "email": email, "book": book[0]["id"] if book else None,
            "h": {"Authorization": f"Bearer {r.json().get('access_token')}"}}


def _entry_used(uid):
    rows = db.sql("SELECT coalesce(sum(used), 0) AS n FROM usage_counters WHERE user_id = %s AND feature = 'entry'", uid)
    return int(rows[0]["n"]) if rows else 0


def _store_insight(book, kind, content_mm=None):
    """A stored real insight of the book, English (and optionally Myanmar)."""
    from datetime import date, timedelta

    async def go():
        from sql import insights as insights_db
        key = "week" if kind == "weekly" else "month"
        start = date.today() - timedelta(days=14)
        await insights_db.insert_insight({
            "_id": str(uuid.uuid4()), "book_id": book, "content": "## Summary\nA stored report.", "content_mm": content_mm,
            "generated_at": datetime.now(), f"{key}_start": start, f"{key}_end": start + timedelta(days=6),
            "insight_type": kind, "ai_provider": "gemini", "expires_at": None, "is_placeholder": False,
            "is_period_to_date": False})
    _backend_async(go)


def section_switches():
    import httpx
    from notification_service import translate
    c = httpx.Client(base_url=BASE, timeout=60)
    original = _stored()
    made, admins = [], []
    start = ah = None
    try:
        ah_, _, aid = _admin(c, "admin")
        ah = ah_
        admins.append(aid)
        seen = c.get("/api/admin/app-control", headers=ah).json()["settings"]
        check(seen["maintenance"]["on"] is False, "switches: maintenance is off at the start of the section")
        start = _clean_doc(original)

        def pause(*keys):
            sw = {k: {"paused": k in keys, "message_en": "", "message_my": ""} for k in start["switches"]}
            r = c.put("/api/admin/app-control", headers=ah, json={"switches": sw, "maintenance": start["maintenance"]})
            check(r.status_code == 200, f"switches: pause {list(keys)}", f"{r.status_code} {r.text[:200]}")

        plus = _person(c, made, "Plus")
        free = _person(c, made, "Free", plan="free")
        mm = _person(c, made, "Burmese", language="my")
        stored = _person(c, made, "Stored")  # made before the sign-ups pause below
        empty = _person(c, made, "Empty")
        free_monthly = _person(c, made, "FreeMonthly", plan="free")
        withmm = _person(c, made, "WithMm")
        today = datetime.now(UTC).date().isoformat()
        audio = {"audio": ("voice.m4a", b"\x00\x01\x02\x03", "audio/mp4")}
        image = {"image": ("r.jpg", b"\xff\xd8\xff\xe0", "image/jpeg")}
        routes = [
            ("chat", "/api/chat", {"json": {"message": "hi"}}),
            ("chat", "/api/chat/stream", {"json": {"message": "hi"}}),
            ("voice", "/api/transactions/transcribe-audio", {"files": audio}),
            ("voice", "/api/transactions/extract-from-text", {"json": {"text": "coffee 3000 kyat"}}),
            ("voice", "/api/transactions/extract-multiple-from-text", {"json": {"text": "coffee 3000 kyat"}}),
            ("receipts", "/api/transactions/extract-from-image", {"files": image}),
            ("budget_ideas", "/api/budgets/ai-suggest",
             {"json": {"period": "monthly", "start_date": today, "currency": "mmk"}}),
            ("reports", "/api/insights/regenerate", {}),
            ("reports", "/api/insights/generate-weekly", {}),
            ("custom_reports", "/api/custom-insights", {"json": {"start_date": today, "end_date": today}}),
            ("translation", "/api/insights/translate-myanmar", {}),
            ("free_trial", "/api/auth/claim-free-trial", {}),
            ("family_new", "/api/family", {"json": {"name": "Acme"}}),
            ("family_new", "/api/family/invites", {"json": {"email": "someone@example.com"}}),
            ("family_new", "/api/family/invites/none/accept", {}),
        ]
        for key, path, kw in routes:
            pause(key)
            who = free if key == "free_trial" else plus
            r = c.post(path, headers=who["h"], **kw)
            try:
                d = r.json().get("detail", {})
            except Exception:  # noqa: BLE001
                d = {}
            d = d if isinstance(d, dict) else {}
            check(r.status_code == 403 and d.get("code") == "feature_paused" and d.get("feature") == key
                  and (r.headers.get("content-type") or "").startswith("application/json"),
                  f"switches: {key} paused refuses {path}", f"{r.status_code} {r.text[:200]}")
            check(set(d) == {"code", "feature", "message"} and "paused" in (d.get("message") or "").lower(),
                  f"switches: {path} detail is code, feature and the English message", d)

        # the user's language
        pause("chat")
        r = c.post("/api/chat/stream", headers=mm["h"], json={"message": "hi"})
        want = translate("feature_paused_msg", "my", feature=translate("app_switch_chat", "my"))
        check(r.status_code == 403 and r.json()["detail"]["message"] == want,
              "switches: a Myanmar-language user gets the Myanmar message", r.text[:200])
        # reading what exists still works
        r = c.get("/api/chat/history", headers=plus["h"])
        check(r.status_code == 200, "switches: chat history is readable while chat is paused", r.status_code)
        pause("family_new")
        r = c.get("/api/family", headers=plus["h"])
        check(r.status_code == 200, "switches: GET /api/family works while family_new is paused", r.status_code)

        # a paused voice entry uses no entry allowance
        pause("voice")
        before = _entry_used(plus["id"])
        r = c.post("/api/transactions/transcribe-audio", headers=plus["h"], files=audio)
        check(r.status_code == 403 and _entry_used(plus["id"]) == before,
              "switches: a paused voice entry uses no entry allowance", f"{r.status_code} {before} {_entry_used(plus['id'])}")

        # a voice entry already paid for finishes while voice is paused; without a valid token it is refused
        pause()
        r = c.post("/api/transactions/transcribe-audio", headers=plus["h"], files=audio)
        tj = r.json() if r.status_code == 200 else {}
        token, text = tj.get("voice_token"), (tj.get("transcription") or "").strip()
        check(bool(token and text), "switches: transcribe-audio returns a transcript and a voice token while unpaused",
              f"{r.status_code} {r.text[:200]}")
        pause("voice")
        used_before = _entry_used(plus["id"])
        for path in ("/api/transactions/extract-from-text", "/api/transactions/extract-multiple-from-text"):
            r = c.post(path, headers=plus["h"], json={"text": text, "voice_token": token})
            check(r.status_code == 200, f"switches: {path} with its voice token works while voice is paused",
                  f"{r.status_code} {r.text[:200]}")
            r = c.post(path, headers=plus["h"], json={"text": text})
            d = r.json().get("detail", {}) if r.status_code == 403 else {}
            check(r.status_code == 403 and d.get("code") == "feature_paused" and d.get("feature") == "voice",
                  f"switches: {path} without a token is refused while voice is paused", f"{r.status_code} {r.text[:200]}")
        check(_entry_used(plus["id"]) == used_before, "switches: the token-paid text steps used no further allowance",
              f"{used_before} {_entry_used(plus['id'])}")

        # sign-ups: both languages, no user row
        pause("signups")
        email = f"acs-new-{uuid.uuid4().hex[:8]}@example.com"
        r = c.post("/api/auth/register", json={"name": "New", "email": email, "password": "secret123"})
        d = r.json().get("detail", {}) if r.status_code == 403 else {}
        both = (translate("feature_paused_msg", "en", feature=translate("app_switch_signups", "en")) + "\n\n"
                + translate("feature_paused_msg", "my", feature=translate("app_switch_signups", "my")))
        check(r.status_code == 403 and d.get("code") == "feature_paused" and d.get("feature") == "signups"
              and d.get("message") == both, "switches: register while signups paused: 403 with both languages",
              f"{r.status_code} {r.text[:300]}")
        check(not db.sql("SELECT id FROM users WHERE lower(email) = %s", email), "switches: no user row is created")

        # reports paused: the stored report is shown, nothing new is made; with none stored it is a 403
        _store_insight(stored["book"], "weekly")
        pause("reports")
        r = c.get("/api/insights", headers=stored["h"])
        check(r.status_code == 200 and "A stored report." in r.json().get("content", ""),
              "switches: GET /api/insights shows the stored report while reports are paused", f"{r.status_code} {r.text[:200]}")
        r = c.get("/api/insights", headers=empty["h"])
        d = r.json().get("detail", {}) if r.status_code == 403 else {}
        check(r.status_code == 403 and d.get("code") == "feature_paused" and d.get("feature") == "reports",
              "switches: GET /api/insights with nothing stored is a 403 while reports are paused", f"{r.status_code} {r.text[:200]}")
        r = c.get("/api/insights?insight_type=monthly", headers=free_monthly["h"])
        check(r.status_code == 403 and r.json().get("detail", {}).get("feature") == "reports",
              "switches: a Free user's monthly report with none stored is a 403 while reports are paused",
              f"{r.status_code} {r.text[:200]}")

        # translation paused: English with the note, a stored Myanmar text is still returned
        pause("translation")
        r = c.get("/api/insights?language=mm", headers=stored["h"])
        b = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and "A stored report." in b.get("content", "") and not b.get("content_mm")
              and (b.get("translation_unavailable") or {}).get("code") == "feature_paused",
              "switches: language=mm with translation paused is English with translation_unavailable", f"{r.status_code} {r.text[:300]}")
        _store_insight(withmm["book"], "weekly", content_mm="မြန်မာ အစီရင်ခံစာ")
        r = c.get("/api/insights?language=mm", headers=withmm["h"])
        b = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and b.get("content_mm") == "မြန်မာ အစီရင်ခံစာ"
              and not b.get("translation_unavailable"),
              "switches: a stored Myanmar text is still returned while translation is paused", f"{r.status_code} {r.text[:300]}")

        # custom report translate while translation is paused: a stored Myanmar text is read, a new one is refused
        ids = {}
        for tag, mm_text in (("with_mm", "မြန်မာ စိတ်ကြိုက်အစီရင်ခံစာ"), ("no_mm", None)):
            ids[tag] = str(uuid.uuid4())
            db.sql("INSERT INTO custom_insights (id, book_id, start_date, end_date, status, content, content_mm, "
                   "completed_at) VALUES (%s, %s, current_date - 3, current_date - 2, 'ready', 'A custom report.', %s, now())",
                   ids[tag], plus["book"], mm_text)
        used = lambda: db.sql("SELECT coalesce(sum(used), 0) AS n FROM usage_counters WHERE user_id = %s "
                              "AND feature = 'insight_translation'", plus["id"])[0]["n"]
        n0 = used()
        r = c.post(f"/api/custom-insights/{ids['with_mm']}/translate", headers=plus["h"])
        check(r.status_code == 200 and r.json().get("content_mm") == "မြန်မာ စိတ်ကြိုက်အစီရင်ခံစာ",
              "switches: a stored custom report translation is returned while translation is paused",
              f"{r.status_code} {r.text[:200]}")
        r = c.post(f"/api/custom-insights/{ids['no_mm']}/translate", headers=plus["h"])
        d = r.json().get("detail", {}) if r.status_code == 403 else {}
        check(r.status_code == 403 and d.get("code") == "feature_paused" and d.get("feature") == "translation"
              and used() == n0, "switches: a custom report with no translation is refused (403 translation), nothing counted",
              f"{r.status_code} {r.text[:200]} {n0} {used()}")

        # in-process: the scheduled report and the budget renewal
        from tz_utils import default_zone

        async def scheduled(paused):
            prev = _use_key(E2E_KEY)  # never the row the stub server reads
            try:
                return await scheduled_inner(paused)
            finally:
                _use_key(prev)

        async def scheduled_inner(paused):
            import app_control as ac
            import insights_service as ins
            doc = ac.snapshot()
            doc["switches"]["reports"]["paused"] = paused
            doc["switches"]["budget_ideas"]["paused"] = paused
            await ac.save(doc, "test-admin")
            calls = []

            async def generate(book_id, **kw):
                calls.append(book_id)
                return {"ai_provider": "stub", "is_placeholder": True}

            async def notify(book_id):
                calls.append("notify")

            err = None
            try:
                await ins._scheduled_insight(empty["book"], default_zone(), "insight_weekly", generate, notify)
            except Exception as e:  # noqa: BLE001
                err = repr(e)
            import budget_service
            return calls, err, await budget_service._owner_gets_ai_budgets(empty["book"])

        try:
            calls, err, gets_ai = _backend_async(lambda: scheduled(True))
            check(calls == [] and err is None, "switches: _scheduled_insight with reports paused makes nothing, no error",
                  (calls, err))
            check(gets_ai is False, "switches: _owner_gets_ai_budgets is False for a Plus owner while budget_ideas is paused")
            calls, err, gets_ai = _backend_async(lambda: scheduled(False))
            check(calls and err is None, "switches: _scheduled_insight makes the report again once unpaused", (calls, err))
            check(gets_ai is True, "switches: _owner_gets_ai_budgets is True for a Plus owner when not paused")
        finally:
            _restore(None, E2E_KEY)

        # everything back on: chat works again
        pause()
        r = c.post("/api/chat", headers=plus["h"], json={"message": "hi"})
        check(r.status_code == 410, "switches: POST /api/chat is its old 410 again once unpaused", r.status_code)
        r = c.post("/api/chat/stream", headers=plus["h"], json={"message": "hi"})
        check(r.status_code == 200, "switches: POST /api/chat/stream works again once unpaused", f"{r.status_code} {r.text[:200]}")
    finally:
        try:
            if ah is not None:
                c.put("/api/admin/app-control", headers=ah, json=_clean_doc(original))
        except Exception:  # noqa: BLE001
            pass
        _restore(original)
        made = [m for m in made if m]
        if made:
            db.sql("DELETE FROM families WHERE id IN (SELECT family_id FROM family_members WHERE user_id = ANY(%s))", made)
            db.sql("DELETE FROM users WHERE id = ANY(%s)", made)
        if admins:
            db.sql("DELETE FROM admin_action_logs WHERE admin_id = ANY(%s)", admins)
            db.sql("DELETE FROM admins WHERE id = ANY(%s)", admins)
    check(_stored() == original, "switches: the stored document is back as it was")


# ---------------------------------------------------------------------------------------------------- announcements
def _ann(plans=("plus",), start=-1, end=1, **over):
    """An announcement body: starts `start` hours from now, ends `end` hours from now (None: no end)."""
    now = datetime.now(UTC)
    body = {"text_en": "Hello", "text_my": "မင်္ဂလာပါ", "style": "info", "plans": list(plans),
            "starts_at": (now + timedelta(hours=start)).isoformat(),
            "ends_at": None if end is None else (now + timedelta(hours=end)).isoformat()}
    body.update(over)
    return body


def section_announcements():
    import httpx
    c = httpx.Client(base_url=BASE, timeout=60)
    original = _stored()
    admins, ann_ids = [], []
    try:
        mh, _, mid = _admin(c, "moderator")
        ah, aemail, aid = _admin(c, "admin")
        admins += [mid, aid]
        base = "/api/admin/app-control/announcements"
        r = c.post(base, headers=ah, json=_ann(link_url="https://example.com/x", link_label_en="Read"))
        made = r.json() if r.status_code == 200 else {}
        if made.get("id"):
            ann_ids.append(made["id"])
        check(r.status_code == 200 and made.get("plans") == ["plus"] and made.get("link_url") == "https://example.com/x"
              and made.get("created_by") == aemail and made.get("style") == "info",
              "announcements: an admin creates one", f"{r.status_code} {r.text[:200]}")
        aid1 = made.get("id")
        bads = [("an ftp link", _ann(link_url="ftp://x")),
                ("a link with no host", _ann(link_url="https://")),
                ("a label with no link", _ann(link_label_en="Read")),
                ("a label that is too long", _ann(link_url="https://e.com", link_label_my="x" * 41)),
                ("a link that is too long", _ann(link_url="https://e.com/" + "x" * 500)),
                ("a naive start", _ann(starts_at="2026-12-01T10:00:00")),
                ("a naive end", _ann(ends_at="2026-12-01T10:00:00")),
                ("an end before the start", _ann(start=1, end=-1)),
                ("an end equal to the start", _ann(starts_at="2026-12-01T10:00:00Z", ends_at="2026-12-01T10:00:00Z")),
                ("no start", _ann(starts_at=None)),
                ("a missing Myanmar text", _ann(text_my=None)),
                ("an empty English text", _ann(text_en="  ")),
                ("a text over 500", _ann(text_en="x" * 501)),
                ("a bad style", _ann(style="danger")),
                ("no plans", _ann(plans=())),
                ("an unknown plan", _ann(plans=("gold",))),
                ("an unknown field", {**_ann(), "extra": 1})]
        for name, body in bads:
            r = c.post(base, headers=ah, json=body)
            if r.status_code == 200 and r.json().get("id"):
                ann_ids.append(r.json()["id"])
            check(r.status_code == 422, f"announcements: {name} is a 422", f"{r.status_code} {r.text[:200]}")
        r = c.post(base, headers=ah, json=_ann(plans=("plus",), link_url="https://e.com/" + "x" * 480))
        if r.status_code == 200:
            ann_ids.append(r.json()["id"])
        check(r.status_code == 200, "announcements: a link under 500 characters is fine", r.status_code)
        r = c.post(base, headers=mh, json=_ann())
        check(r.status_code == 403, "announcements: a moderator can't create", r.status_code)
        r = c.get(base, headers=mh)
        check(r.status_code == 200 and any(a["id"] == aid1 for a in r.json()),
              "announcements: a moderator lists them", f"{r.status_code} {r.text[:200]}")
        r = c.get(base)
        check(r.status_code in (401, 403), "announcements: no token is refused", r.status_code)
        r = c.put(f"{base}/{aid1}", headers=ah, json=_ann(plans=("plus", "pro"), text_en="Changed", style="warning"))
        check(r.status_code == 200 and r.json()["text_en"] == "Changed" and r.json()["plans"] == ["plus", "pro"]
              and r.json()["style"] == "warning" and r.json()["link_url"] is None,
              "announcements: an admin updates one", f"{r.status_code} {r.text[:200]}")
        r = c.put(f"{base}/{aid1}", headers=ah, json=_ann(link_url="ftp://x"))
        check(r.status_code == 422, "announcements: an update is validated too", r.status_code)
        r = c.put(f"{base}/nope", headers=ah, json=_ann())
        check(r.status_code == 404, "announcements: updating an unknown one is a 404", r.status_code)
        r = c.put(f"{base}/{aid1}", headers=mh, json=_ann())
        check(r.status_code == 403, "announcements: a moderator can't update", r.status_code)
        r = c.delete(f"{base}/{aid1}", headers=mh)
        check(r.status_code == 403, "announcements: a moderator can't delete", r.status_code)
        r = c.delete(f"{base}/{aid1}", headers=ah)
        check(r.status_code == 200, "announcements: an admin deletes one", f"{r.status_code} {r.text[:200]}")
        r = c.delete(f"{base}/{aid1}", headers=ah)
        check(r.status_code == 404, "announcements: deleting it again is a 404", r.status_code)
        actions = {x["action"] for x in db.sql("SELECT action FROM admin_action_logs WHERE admin_id = %s", aid)}
        check({"announcement_create", "announcement_update", "announcement_delete"} <= actions,
              "announcements: create, update and delete are in the admin log", actions)
    finally:
        if ann_ids:
            db.sql("DELETE FROM announcements WHERE id = ANY(%s)", ann_ids)
        _restore(original)
        if admins:
            db.sql("DELETE FROM admin_action_logs WHERE admin_id = ANY(%s)", admins)
            db.sql("DELETE FROM admins WHERE id = ANY(%s)", admins)
    check(_stored() == original, "announcements: the stored document is back as it was")


# ------------------------------------------------------------------------------------------------------------ config
def section_config():
    import httpx
    from notification_service import translate
    c = httpx.Client(base_url=BASE, timeout=60)
    original = _stored()
    admins, made, ann_ids = [], [], []
    start = ah = None
    try:
        ah, _, aid = _admin(c, "admin")
        admins.append(aid)
        seen = c.get("/api/admin/app-control", headers=ah).json()["settings"]
        check(seen["maintenance"]["on"] is False, "config: maintenance is off at the start of the section")
        start = _clean_doc(original)
        plus = _person(c, made, "CfgPlus")
        free = _person(c, made, "CfgFree", plan="free")
        base = "/api/admin/app-control/announcements"

        def add(**kw):
            r = c.post(base, headers=ah, json=_ann(**kw))
            if r.status_code == 200:
                ann_ids.append(r.json()["id"])
            else:
                check(False, "config: could not create the announcement", f"{r.status_code} {r.text[:200]}")
            return r.json()

        def put_settings(paused=(), on=False, testers=()):
            sw = {k: {"paused": k in paused, "message_en": "", "message_my": ""} for k in start["switches"]}
            m = {"on": on, "message_en": "", "message_my": "", "back_by": None, "testers": list(testers)}
            r = c.put("/api/admin/app-control", headers=ah, json={"switches": sw, "maintenance": m})
            check(r.status_code == 200, "config: settings saved", f"{r.status_code} {r.text[:200]}")

        put_settings(paused=("voice",))
        live = add(plans=("plus",), text_en="Plus news", text_my="Plus သတင်း", start=-1, end=1)
        add(plans=("free",), text_en="Free news", text_my="Free သတင်း", start=-1, end=1)
        add(plans=("plus",), text_en="Soon", text_my="မကြာမီ", start=1, end=2)
        add(plans=("plus",), text_en="Over", text_my="ပြီးပြီ", start=-3, end=-2)
        # signed out
        r = c.get("/api/app/config?lang=my")
        b = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and b.get("announcement") is None, "config: signed out has no announcement",
              f"{r.status_code} {r.text[:300]}")
        want = translate("feature_paused_msg", "my", feature=translate("app_switch_voice", "my"))
        check(b.get("paused") == {"voice": want}, "config: only paused switches, messages in Myanmar", b.get("paused"))
        check(b.get("maintenance") == {"on": False, "message": translate("maintenance_msg", "my"), "back_by": None,
                                       "can_enter": True}, "config: maintenance off, anyone can enter", b.get("maintenance"))
        r = c.get("/api/app/config")
        check(r.json()["paused"] == {"voice": translate("feature_paused_msg", "en",
                                                         feature=translate("app_switch_voice", "en"))},
              "config: English is the default language")
        # a Plus user
        r = c.get("/api/app/config?lang=en", headers=plus["h"])
        a = (r.json() if r.status_code == 200 else {}).get("announcement") or {}
        check(a.get("id") == live["id"] and a.get("text") == "Plus news" and a.get("style") == "info"
              and a.get("link_url") is None and a.get("link_label") is None and a.get("updated_at"),
              "config: a Plus user gets the live Plus announcement (future and ended ones are not shown)",
              f"{r.status_code} {r.text[:300]}")
        r = c.get("/api/app/config?lang=my", headers=plus["h"])
        check((r.json().get("announcement") or {}).get("text") == "Plus သတင်း", "config: in the user's language (my)")
        r = c.get("/api/app/config", headers=free["h"])
        check((r.json().get("announcement") or {}).get("text") == "Free news",
              "config: a Free user gets the Free one, not the Plus one", r.text[:300])
        # link label fallbacks
        db.sql("UPDATE announcements SET link_url = 'https://example.com', link_label_en = NULL, link_label_my = '' "
               "WHERE id = %s", live["id"])
        a = c.get("/api/app/config?lang=en", headers=plus["h"]).json().get("announcement") or {}
        check(a.get("link_url") == "https://example.com" and a.get("link_label") == "Open",
              "config: an empty link label falls back to Open", a)
        a = c.get("/api/app/config?lang=my", headers=plus["h"]).json().get("announcement") or {}
        check(a.get("link_label") == translate("announcement_open", "my") and a["link_label"] != "Open",
              "config: an empty Myanmar link label falls back to the Myanmar text", a)
        db.sql("UPDATE announcements SET link_label_en = 'Read it' WHERE id = %s", live["id"])
        a = c.get("/api/app/config?lang=en", headers=plus["h"]).json().get("announcement") or {}
        check(a.get("link_label") == "Read it", "config: the link label is used when set", a)
        # two live ones: the newer start wins
        newer = add(plans=("plus",), text_en="Newer", text_my="အသစ်", start=-0.5, end=None)
        a = c.get("/api/app/config", headers=plus["h"]).json().get("announcement") or {}
        check(a.get("id") == newer["id"], "config: of two live announcements the newer start wins", a)
        # a plan that expired counts as Free
        db.sql("UPDATE users SET subscription_expires_at = now() - interval '1 day' WHERE id = %s", plus["id"])
        a = c.get("/api/app/config", headers=plus["h"]).json().get("announcement") or {}
        check(a.get("text") == "Free news", "config: an expired Plus plan is chosen as Free", a)
        # invalid tokens are signed out, never 401
        for name, h in (("a garbage token", {"Authorization": "Bearer not.a.token"}),
                        ("a wrong scheme", {"Authorization": "Basic abc"}),
                        ("an admin token", ah)):
            r = c.get("/api/app/config", headers=h)
            check(r.status_code == 200 and r.json()["announcement"] is None,
                  f"config: {name} is answered as signed out", f"{r.status_code} {r.text[:200]}")
        # maintenance: testers can enter
        put_settings(on=True, testers=(plus["email"].upper(),))
        b = c.get("/api/app/config", headers=plus["h"]).json()
        check(b["maintenance"]["on"] is True and b["maintenance"]["can_enter"] is True,
              "config: a tester can enter during maintenance", b["maintenance"])
        for name, h in (("a non-tester", free["h"]), ("a signed-out caller", {})):
            b = c.get("/api/app/config", headers=h).json()
            check(b["maintenance"]["on"] is True and b["maintenance"]["can_enter"] is False,
                  f"config: {name} cannot enter during maintenance", b["maintenance"])
        check(c.get("/api/app/latest-android").status_code == 200, "config: /api/app/latest-android is still served")
    finally:
        try:
            if ah is not None:
                c.put("/api/admin/app-control", headers=ah, json=_clean_doc(original))
        except Exception:  # noqa: BLE001
            pass
        _restore(original)
        if ann_ids:
            db.sql("DELETE FROM announcements WHERE id = ANY(%s)", ann_ids)
        made = [m for m in made if m]
        if made:
            db.sql("DELETE FROM users WHERE id = ANY(%s)", made)
        if admins:
            db.sql("DELETE FROM admin_action_logs WHERE admin_id = ANY(%s)", admins)
            db.sql("DELETE FROM admins WHERE id = ANY(%s)", admins)
    check(_stored() == original, "config: the stored document is back as it was")


# ------------------------------------------------------------------------------------------------------ maintenance
def section_maintenance():
    import httpx
    c = httpx.Client(base_url=BASE, timeout=60)
    original = _stored()
    admins, made = [], []
    start = ah = None
    try:
        ah, _, aid = _admin(c, "admin")
        admins.append(aid)
        seen = c.get("/api/admin/app-control", headers=ah).json()["settings"]
        check(seen["maintenance"]["on"] is False, "maintenance: maintenance is off at the start of the section")
        start = _clean_doc(original)
        tester = _person(c, made, "MtTester")
        user = _person(c, made, "MtUser")
        tester_h, user_h = tester["h"], user["h"]
        check(c.get("/api/transactions", headers=user_h).status_code == 200, "maintenance: open while it is off")
        m = {"on": True, "message_en": "", "message_my": "", "back_by": None,
             "testers": [f" {tester['email'].capitalize()} "]}
        r = c.put("/api/admin/app-control", headers=ah, json={**start, "maintenance": m})
        check(r.status_code == 200, "maintenance: turned on", f"{r.status_code} {r.text[:200]}")
        r = c.get("/api/transactions", headers=user_h)
        d = (r.json().get("detail") or {}) if r.status_code == 503 else {}
        check(r.status_code == 503 and d.get("code") == "maintenance", "maintenance: the app API is closed",
              f"{r.status_code} {r.text[:200]}")
        check("\n\n" in d.get("message", ""), "maintenance: the message carries both languages", d)
        check(d.get("back_by", "x") is None, "maintenance: back_by is null when not set", d)
        check(c.get("/api/transactions", headers=tester_h).status_code == 200, "maintenance: a tester gets in")
        check(c.get("/api/admin/app-control", headers=ah).status_code == 200, "maintenance: the admin API stays open")
        for path in ("/api/app/config", "/api/plan/public", "/api/app/latest-android"):
            check(c.get(path).status_code != 503, f"maintenance: {path} stays open")
        check(c.post("/api/auth/login", json={"email": user["email"], "password": "secret123"}).status_code == 200,
              "maintenance: sign-in stays open")
        check(c.get("/api/auth/me", headers=user_h).status_code == 200, "maintenance: GET /api/auth/me stays open")
        r = c.get("/api/transactions", headers={**user_h, "Origin": "https://app.example.com"})
        check(r.status_code == 503 and "access-control-allow-origin" in r.headers,
              "maintenance: the 503 carries CORS headers")
        r = c.options("/api/transactions", headers={"Origin": "https://app.example.com",
                                                     "Access-Control-Request-Method": "GET"})
        check(r.status_code == 200, "maintenance: a CORS preflight still passes", r.status_code)
        check(c.get("/").status_code != 503, "maintenance: the root health check stays open")
        for name, resp in (
                ("verify-email", c.get("/api/auth/verify-email", params={"email": user["email"], "token": "bad"})),
                ("resend-verification", c.post("/api/auth/resend-verification", json={"email": user["email"]})),
                ("forgot-password/request-otp",
                 c.post("/api/auth/forgot-password/request-otp", json={"email": user["email"]})),
                ("check-version", c.post("/api/app/check-version", json={"version": "1.0.0", "platform": "android"}))):
            check(resp.status_code != 503, f"maintenance: {name} stays open", resp.status_code)
        r = c.get("/api/transactions", headers={"Authorization": "Bearer not.a.token"})
        check(r.status_code == 503, "maintenance: a garbage token is not a tester", r.status_code)
        # a back_by time is in the 503
        m2 = {**m, "back_by": (datetime.now(UTC) + timedelta(hours=1)).isoformat()}
        c.put("/api/admin/app-control", headers=ah, json={**start, "maintenance": m2})
        r = c.get("/api/transactions", headers=user_h)
        check(r.status_code == 503 and (r.json()["detail"].get("back_by") or "").startswith(m2["back_by"][:16]),
              "maintenance: back_by is in the 503", r.text[:200])
    finally:
        try:
            if ah is not None:
                c.put("/api/admin/app-control", headers=ah, json=_clean_doc(original))
        except Exception:  # noqa: BLE001
            pass
        _restore(original)
        made = [m_ for m_ in made if m_]
        if made:
            db.sql("DELETE FROM users WHERE id = ANY(%s)", made)
        if admins:
            db.sql("DELETE FROM admin_action_logs WHERE admin_id = ANY(%s)", admins)
            db.sql("DELETE FROM admins WHERE id = ANY(%s)", admins)
    check(_stored() == original, "maintenance: the stored document is back as it was")
    try:
        r = httpx.Client(base_url=BASE, timeout=60).get("/api/plan/public")
        check(r.status_code != 503, "maintenance: the server is open again", r.status_code)
    except Exception as e:  # noqa: BLE001
        check(False, "maintenance: the server is open again", e)


# ---------------------------------------------------------------------------------------------------------- clean
def section_clean():
    check(_stored() == RUN_START, "clean: the stored document equals the one at the start of the run",
          f"{RUN_START!r} -> {_stored()!r}")
    now = db.sql("SELECT id FROM announcements")
    check(sorted(r["id"] for r in now) == RUN_ANNOUNCEMENTS, "clean: no test announcements are left",
          f"{len(RUN_ANNOUNCEMENTS)} -> {len(now)}")


SECTIONS = {"store": section_store, "admin_api": section_admin_api, "switches": section_switches,
            "announcements": section_announcements, "config": section_config,
            "maintenance": section_maintenance, "clean": section_clean}
RUN_START = _stored()  # the document and the announcements as they were before anything ran
RUN_ANNOUNCEMENTS = sorted(r["id"] for r in db.sql("SELECT id FROM announcements"))


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
