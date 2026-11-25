"""App control e2e (docs/superpowers/specs/2026-11-25-app-control-design.md).

Sections (named on the command line, all by default):
  store -- the settings document in-process: validation, save -> cache -> load, the paused messages in both
    languages, FeaturePaused, a bad or older stored document, tester matching.
  admin_api -- GET/PUT /api/admin/app-control over HTTP: a moderator reads and can't change, an admin changes, a bad
    document is a readable 422, the change is in the admin log.
Every section that changes the stored settings puts the original document back in `finally`.
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


def _stored():
    rows = db.sql("SELECT value FROM app_settings WHERE key = 'app_control'")
    return rows[0]["value"] if rows else None


def _restore(original):
    if original is None:
        db.sql("DELETE FROM app_settings WHERE key = 'app_control'")
    else:
        db.sql("INSERT INTO app_settings (key, value) VALUES ('app_control', %s) "
               "ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value", original)


def _set_raw(value):
    db.sql("INSERT INTO app_settings (key, value) VALUES ('app_control', %s) "
           "ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value", value)


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
        _set_raw("not json")
        await ac.load()
        res["bad_json"] = [k for k in ac.SWITCHES if ac.is_paused(k)]
        # an older / hand-edited document: unknown key dropped, voice paused, the rest default
        _set_raw(json.dumps({"switches": {"nope": {"paused": True}, "voice": {"paused": True}}}))
        await ac.load()
        res["unknown"] = ([k for k in ac.SWITCHES if ac.is_paused(k)], "nope" in ac.snapshot()["switches"])
        # nothing stored at all
        db.sql("DELETE FROM app_settings WHERE key = 'app_control'")
        await ac.load()
        res["none"] = [k for k in ac.SWITCHES if ac.is_paused(k)]
        return res

    try:
        res = _backend_async(run)
    finally:
        _restore(original)

    check(res["paused"] == (True, False), "store: save applies at once")
    check(res["en"] == "Back at 5", "store: the owner's English message")
    check(res["my"] == translate("feature_paused_msg", "my", feature=translate("app_switch_voice", "my")),
          "store: an empty Myanmar message uses the standard one")
    check(res["chat_en"] == "Chat with Ko Toe Pwar is paused for now. Please try again later.",
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
        start = body.get("settings")
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
            if start is not None and ah is not None:
                c.put("/api/admin/app-control", headers=ah, json=start)
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
        start = c.get("/api/admin/app-control", headers=ah).json()["settings"]

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
            check(set(d) == {"code", "feature", "message"} and "paused" in (d.get("message") or ""),
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

        # a paused voice entry uses no entry allowance and reads no upload
        pause("voice")
        before = _entry_used(plus["id"])
        r = c.post("/api/transactions/transcribe-audio", headers=plus["h"], files=audio)
        check(r.status_code == 403 and _entry_used(plus["id"]) == before,
              "switches: a paused voice entry uses no entry allowance", f"{r.status_code} {before} {_entry_used(plus['id'])}")

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

        # in-process: the scheduled report and the budget renewal
        from tz_utils import default_zone

        async def scheduled(paused):
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
            _restore(original)

        # everything back on: chat works again
        pause()
        r = c.post("/api/chat", headers=plus["h"], json={"message": "hi"})
        check(r.status_code == 410, "switches: POST /api/chat is its old 410 again once unpaused", r.status_code)
        r = c.post("/api/chat/stream", headers=plus["h"], json={"message": "hi"})
        check(r.status_code == 200, "switches: POST /api/chat/stream works again once unpaused", f"{r.status_code} {r.text[:200]}")
    finally:
        try:
            if start is not None and ah is not None:
                c.put("/api/admin/app-control", headers=ah, json=start)
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


SECTIONS = {"store": section_store, "admin_api": section_admin_api, "switches": section_switches}


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
