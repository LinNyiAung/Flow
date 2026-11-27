"""Tunable numbers and times e2e (docs/superpowers/specs/2026-11-27-numbers-and-times-design.md).

Sections (named on the command line, all by default):
  store -- the settings store in-process: defaults, validation (types, ranges, the cross-field rule), save with the
    compare-and-swap on the version, a bad stored record.
  admin_api -- the admin routes over HTTP (roles, save, log, conflict, 422 shapes); every save is restored in `finally`.
  public_config -- GET /api/app/config carries the trial and invite lengths.
  clean -- the real `tunables` row holds the same settings as when the run started (its version may have moved);
    keep this section last.
In-process tests point sql.tunables.SETTINGS_KEY at a private key, so the stub server (which caches the real row) never
sees them; they put the key and the module's cache back in `finally`.
"""
import asyncio
import json
import logging
import os
import sys
from datetime import time

os.environ.setdefault("E2E_FAKE_AI", "1")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402,F401

db = __import__("pgcompat").get_db()
failures = 0


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


REAL_KEY = "tunables"
E2E_KEY = "tunables_e2e"  # the in-process tests save here, never into the row the stub server reads


def _stored(key=REAL_KEY):
    rows = db.sql("SELECT value FROM app_settings WHERE key = %s", key)
    return rows[0]["value"] if rows else None


def _set_raw(value, key=E2E_KEY):
    if value is None:
        db.sql("DELETE FROM app_settings WHERE key = %s", key)
    else:
        db.sql("INSERT INTO app_settings (key, value) VALUES (%s, %s) "
               "ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value", key, value)


def _use_key(key):
    """Point the in-process reads and writes at `key` (read at call time); returns the previous key."""
    from sql import tunables as tunables_db
    prev = tunables_db.SETTINGS_KEY
    tunables_db.SETTINGS_KEY = key
    return prev


def _errors(tn, values):
    """The field errors validate() raises for `values` (None when it accepts them)."""
    try:
        tn.validate(values)
        return None
    except tn.SettingsInvalid as e:
        return e.errors


KEYS = ["trial_days", "ends_soon_days", "goal_reminder_days", "budget_ending_soon_days",
        "large_expense_multiple", "large_expense_min", "unusual_week_multiple", "unusual_week_min_diff", "invite_days",
        "reminders_time", "unusual_spending_time", "weekly_report_time", "monthly_report_time"]


# ------------------------------------------------------------------------------------------------------------ store
def section_store():
    import tunables as tn
    from sql import tunables as tunables_db

    check(tn.SETTINGS_KEY == "tunables" == tunables_db.SETTINGS_KEY, "store: the settings key is tunables")
    original = _stored()
    prev_key = _use_key(E2E_KEY)
    _set_raw(None)
    warnings = []

    class Grab(logging.Handler):
        def emit(self, record):
            warnings.append(record.getMessage())

    grab = Grab(level=logging.WARNING)
    logging.getLogger("tunables").addHandler(grab)

    async def run():
        res = {}
        await tn.load()
        res["defaults"] = (tn.get("trial_days"), tn.get("goal_reminder_days"), tn.amount_for("large_expense_min", "thb"),
                           tn.amount_for("large_expense_min", "eur"), tn.amount_for("large_expense_min", "mmk"),
                           tn.time_of("reminders_time"), tn.version())
        res["catalogue"] = tn.catalogue()
        try:
            tn.get("nope")
            res["unknown"] = None
        except KeyError:
            res["unknown"] = "KeyError"
        # a copy: changing what get() returned must not change the setting
        tn.get("goal_reminder_days").append(99)
        res["copy"] = tn.get("goal_reminder_days")

        # save at version 0, then again at version 0
        r1 = await tn.save({"trial_days": 45}, 0, "test-admin")
        res["first"] = (r1["version"], r1["changes"], json.loads(_stored(E2E_KEY)), tn.get("trial_days"), tn.version())
        try:
            await tn.save({"trial_days": 50}, 0, "test-admin")
            res["again"] = None
        except tn.SettingsConflict:
            res["again"] = "conflict"
        res["after_conflict"] = (tn.get("trial_days"), json.loads(_stored(E2E_KEY)))

        # the cross-field rule, both ways, against a saved ends_soon_days
        await tn.save({"trial_days": 30, "ends_soon_days": 9}, 1, "test-admin")
        res["cross_saved"] = _errors(tn, {"trial_days": 7})
        res["cross_same"] = _errors(tn, {"trial_days": 7, "ends_soon_days": 9})
        res["cross_ok"] = _errors(tn, {"trial_days": 7, "ends_soon_days": 3})

        # a value equal to its default leaves the stored record
        r3 = await tn.save({"ends_soon_days": 3}, 2, "test-admin")
        res["default_removed"] = (json.loads(_stored(E2E_KEY)), r3["changes"], r3["version"])

        # the first save ever racing another first save
        _set_raw(None, E2E_KEY)
        await tn.load()
        outcomes = await asyncio.gather(tn.save({"invite_days": 20}, 0, "a"), tn.save({"invite_days": 25}, 0, "b"),
                                        return_exceptions=True)
        res["race"] = (sorted(type(o).__name__ for o in outcomes), json.loads(_stored(E2E_KEY)))

        # a bad stored record: warned, not raised, every other value kept
        _set_raw(json.dumps({"version": 2, "trial_days": "x", "invite_days": 20, "nope": 5}), E2E_KEY)
        await tn.load()
        await tn.load()
        res["bad_value"] = (tn.get("trial_days"), tn.get("invite_days"), tn.version())
        _set_raw("not json", E2E_KEY)
        await tn.load()
        res["bad_json"] = [tn.get(k) for k in KEYS] == [s.default for s in tn.CATALOGUE]
        # out-of-range and wrong-kind stored values fall back to defaults
        _set_raw(json.dumps({"version": 1, "trial_days": 6, "reminders_time": "09:10", "large_expense_min": {"usd": 5},
                             "goal_reminder_days": [3, 3], "invite_days": True}), E2E_KEY)
        await tn.load()
        res["bad_range"] = [tn.get(k) for k in KEYS] == [s.default for s in tn.CATALOGUE]
        # both stored values valid alone but breaking ends_soon_days < trial_days: readers never raise
        _set_raw(json.dumps({"version": 1, "trial_days": 7, "ends_soon_days": 9}), E2E_KEY)
        await tn.load()
        res["cross_stored"] = (tn.get("trial_days"), tn.get("ends_soon_days"))
        _set_raw(None, E2E_KEY)
        await tn.load()
        # an unreadable row counts as version 0: a save at 0 replaces it, a save at N > 0 is a conflict, never a 500
        for name, raw in (("text", "not json"), ("version_x", json.dumps({"version": "x"})),
                          ("no_version", json.dumps({"trial_days": 40})), ("array", "[1]"),
                          ("version_float", json.dumps({"version": 2.5, "trial_days": 40}))):
            _set_raw(raw, E2E_KEY)
            await tn.load()
            before = (tn.get("trial_days"), tn.version())
            try:
                await tn.save({"invite_days": 21}, 3, "t")
                at_n = None
            except tn.SettingsConflict:
                at_n = "conflict"
            untouched = _stored(E2E_KEY) == raw
            r = await tn.save({"invite_days": 21}, 0, "t")
            res["unreadable_" + name] = (before, at_n, untouched, r["version"], json.loads(_stored(E2E_KEY)))
        _set_raw(None, E2E_KEY)
        await tn.load()
        res["none"] = (tn.get("trial_days"), tn.version())
        return res

    try:
        res = _backend_async(run)
    finally:
        logging.getLogger("tunables").removeHandler(grab)
        _use_key(prev_key)
        _set_raw(None, E2E_KEY)
        tn._values = {}
        tn._version = 0

    check(res["defaults"] == (30, [14, 7, 3, 1], 2000, 100, 100000, time(9, 0), 0),
          "store: with nothing stored the defaults apply and the version is 0", res["defaults"])
    check([c["key"] for c in res["catalogue"]] == KEYS, "store: the catalogue lists the 13 keys in group order",
          [c["key"] for c in res["catalogue"]])
    check([c["group"] for c in res["catalogue"]] == ["Trial and plans"] * 2 + ["Reminders"] * 2 + ["Unusual spending"] * 4
          + ["Family"] + ["Job times"] * 4, "store: the groups are in the panel order")
    c0 = res["catalogue"][0]
    check(c0["default"] == 30 and c0["value"] == 30 and c0["changed"] is False and (c0["min"], c0["max"]) == (7, 90)
          and c0["kind"] == "days" and c0["label"] and c0["note"] is not None, "store: a catalogue entry's fields", c0)
    check(res["unknown"] == "KeyError", "store: get() of an unknown key is a KeyError")
    check(res["copy"] == [14, 7, 3, 1], "store: get() returns a copy", res["copy"])

    checks = [({"trial_days": True}, "trial_days"), ({"trial_days": 3.5}, "trial_days"),
              ({"trial_days": "30"}, "trial_days"), ({"trial_days": 6}, "trial_days"),
              ({"trial_days": 91}, "trial_days"), ({"trial_days": 30.0}, "trial_days"),
              ({"goal_reminder_days": []}, "goal_reminder_days"), ({"goal_reminder_days": [7, 7]}, "goal_reminder_days"),
              ({"goal_reminder_days": [1, 2, 3, 4, 5]}, "goal_reminder_days"),
              ({"goal_reminder_days": [61]}, "goal_reminder_days"), ({"goal_reminder_days": [True]}, "goal_reminder_days"),
              ({"large_expense_multiple": float("nan")}, "large_expense_multiple"),
              ({"large_expense_multiple": float("inf")}, "large_expense_multiple"),
              ({"large_expense_multiple": 1.4}, "large_expense_multiple"),
              ({"large_expense_multiple": True}, "large_expense_multiple"),
              ({"large_expense_min": {"mmk": 0, "usd": 100, "thb": 2000}}, "large_expense_min"),
              ({"large_expense_min": {"mmk": 100000}}, "large_expense_min"),
              ({"large_expense_min": {"usd": 100001, "mmk": 1, "thb": 1}}, "large_expense_min"),
              ({"unusual_week_min_diff": {"mmk": 1, "usd": 1, "thb": 2000001}}, "unusual_week_min_diff"),
              ({"reminders_time": "06:45"}, "reminders_time"), ({"reminders_time": "09:10"}, "reminders_time"),
              ({"reminders_time": "9:00"}, "reminders_time"), ({"reminders_time": "21:15"}, "reminders_time"),
              ({"weekly_report_time": "00:45"}, "weekly_report_time"),
              ({"monthly_report_time": "23:15"}, "monthly_report_time"),
              ({"nope": 1}, "nope"),
              ({"trial_days": 7, "ends_soon_days": 9}, "ends_soon_days")]
    for values, key in checks:
        errs = _errors(tn, values)
        check(errs is not None and key in errs and isinstance(errs[key], str) and errs[key],
              f"store: validate refuses {values!r} naming {key}", errs)
    both = _errors(tn, {"trial_days": 3.5, "invite_days": 0, "reminders_time": "x"})
    check(both is not None and set(both) == {"trial_days", "invite_days", "reminders_time"},
          "store: validate reports every field error at once", both)
    check(_errors(tn, {"trial_days": 7, "ends_soon_days": 6, "unusual_week_multiple": 1.1, "reminders_time": "21:00",
                       "weekly_report_time": "01:00", "large_expense_min": {"mmk": 1, "usd": 0.5, "thb": 2000000}}) is None,
          "store: validate accepts the edges of the ranges")
    check(tn.validate({"goal_reminder_days": [1, 14, 7]})["goal_reminder_days"] == [14, 7, 1],
          "store: goal reminder days are stored high to low")
    check(tn.validate({})["trial_days"] == 30 and len(tn.validate({})) == 13,
          "store: validate returns the full effective set")

    fv, fc, fj, fs, fvv = res["first"][0], res["first"][1], res["first"][2], res["first"][3], res["first"][4]
    check(fv == 1 and fc == [("trial_days", 30, 45)] and fj == {"version": 1, "trial_days": 45} and fs == 45 and fvv == 1,
          "store: the first save is version 1, stores only the changed key and updates the cache", res["first"])
    check(res["again"] == "conflict" and res["after_conflict"] == (45, {"version": 1, "trial_days": 45}),
          "store: a second save at version 0 is a conflict and changes nothing", res["after_conflict"])
    check(res["cross_saved"] is not None and "ends_soon_days" in res["cross_saved"],
          "store: lowering trial_days under a saved ends_soon_days is refused (error under ends_soon_days)",
          res["cross_saved"])
    check(res["cross_same"] is not None and "ends_soon_days" in res["cross_same"],
          "store: raising ends_soon_days past trial_days in one save is refused", res["cross_same"])
    check(res["cross_ok"] is None, "store: both changed together and consistent is accepted", res["cross_ok"])
    check(res["default_removed"] == ({"version": 3}, [("ends_soon_days", 9, 3)], 3),
          "store: a value equal to its default leaves the stored record", res["default_removed"])
    check(res["race"][0] == ["SettingsConflict", "dict"] and res["race"][1]["version"] == 1,
          "store: two first saves at once: one wins, the other is a conflict", res["race"])
    check(res["bad_value"] == (30, 20, 2),
          "store: a bad stored value is ignored, the rest and the version are kept", res["bad_value"])
    bad_warns = [w for w in warnings if "trial_days" in w and "'x'" in w]
    check(len(bad_warns) == 1, "store: a bad stored value is warned about once, however often it is loaded", warnings)
    check(any("nope" in w for w in warnings), "store: an unknown stored key is warned about", warnings)
    check(res["bad_json"], "store: a stored value that isn't JSON leaves every default")
    check(res["bad_range"], "store: wrong-kind and out-of-range stored values fall back to their defaults")
    check(res["cross_stored"] == (7, 3), "store: stored values that break the cross-field rule drop ends_soon_days",
          res["cross_stored"])
    for name, trial in (("text", 30), ("version_x", 30), ("no_version", 40), ("array", 30), ("version_float", 40)):
        got = res["unreadable_" + name]
        want_row = {"version": 1, "invite_days": 21, **({"trial_days": 40} if trial == 40 else {})}
        check(got[0] == (trial, 0) and got[1] == "conflict" and got[2] and got[3] == 1 and got[4] == want_row,
              f"store: a stored row that is {name} is version 0: save at 0 replaces it, at 3 conflicts", got)
    check(res["none"] == (30, 0), "store: nothing stored is version 0 and the defaults")
    check(_stored(E2E_KEY) is None, "store: the private key is cleaned up")
    check(_stored() == original, "store: the real tunables row is untouched")


# ------------------------------------------------------------------------------------------------------- admin_api
BASE = "http://127.0.0.1:8765"


def _admin(c, role):
    import admin_utils
    import uuid
    from datetime import UTC, datetime
    email, pw = f"tn-{role}-{uuid.uuid4().hex[:8]}@example.com", "tn-admin-pass-1"
    aid = str(uuid.uuid4())
    db.admins.insert_one({"_id": aid, "name": f"tn {role}", "email": email,
                          "password": admin_utils.get_password_hash(pw), "role": role,
                          "created_at": datetime.now(UTC), "last_login": None})
    r = c.post("/api/admin/login", json={"email": email, "password": pw})
    return {"Authorization": "Bearer " + r.json().get("access_token", "")}, aid


def _by_key(body):
    return {s["key"]: s for s in body.get("settings", [])}


def section_admin_api():
    import httpx
    c = httpx.Client(base_url=BASE, timeout=60)
    made_admins = []
    ah = None
    start_values = None
    try:
        mh, mid = _admin(c, "moderator")
        ah, aid = _admin(c, "admin")
        made_admins += [mid, aid]

        r = c.get("/api/admin/tunables", headers=mh)
        body = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and len(body.get("settings", [])) == 13 and isinstance(body.get("version"), int),
              "admin_api: a moderator reads 13 settings and the version", f"{r.status_code} {r.text[:200]}")
        start_values = {k: s["value"] for k, s in _by_key(body).items()}
        v = body.get("version", 0)
        r = c.put("/api/admin/tunables", headers=mh, json={"values": {"trial_days": 45}, "version": v})
        check(r.status_code == 403, "admin_api: a moderator cannot save", r.status_code)
        check(c.get("/api/admin/tunables").status_code == 401, "admin_api: no token on GET is 401")
        check(c.put("/api/admin/tunables", json={"values": {}, "version": v}).status_code == 401,
              "admin_api: no token on PUT is 401")

        r = c.put("/api/admin/tunables", headers=ah,
                  json={"values": {"trial_days": 45, "reminders_time": "10:00"}, "version": v})
        body = r.json() if r.status_code == 200 else {}
        td = _by_key(body).get("trial_days", {})
        check(r.status_code == 200 and td.get("value") == 45 and td.get("changed") is True and body.get("version") == v + 1
              and _by_key(body).get("reminders_time", {}).get("value") == "10:00",
              "admin_api: an admin saves and gets the new state back", f"{r.status_code} {r.text[:200]}")
        logs = db.sql("SELECT action, details FROM admin_action_logs WHERE admin_id = %s ORDER BY timestamp DESC", aid)
        check(logs and logs[0]["action"] == "tunables_update" and "trial_days: 30 -> 45" in logs[0]["details"]
              and "reminders_time: 09:00 -> 10:00" in logs[0]["details"] and len(logs[0]["details"]) <= 2000,
              "admin_api: the log has tunables_update naming each change", logs[:1])
        n_logs = len(logs)

        r = c.get("/api/app/config")
        check(r.status_code == 200 and r.json().get("numbers") == {"trial_days": 45, "invite_days": 14},
              "admin_api: the app config shows the saved numbers", r.text[:300])

        r = c.put("/api/admin/tunables", headers=ah, json={"values": {"trial_days": 50}, "version": v})
        d = r.json().get("detail", {}) if r.status_code == 409 else {}
        check(r.status_code == 409 and d.get("code") == "settings_conflict" and d.get("message"),
              "admin_api: an old version is 409 settings_conflict", f"{r.status_code} {r.text[:200]}")

        r = c.put("/api/admin/tunables", headers=ah, json={"values": {"trial_days": 45}, "version": v + 1})
        body = r.json() if r.status_code == 200 else {}
        n2 = db.sql("SELECT count(*) AS n FROM admin_action_logs WHERE admin_id = %s", aid)[0]["n"]
        check(r.status_code == 200 and body.get("version") == v + 1 and n2 == n_logs,
              "admin_api: a save that changes nothing is 200, keeps the version and logs nothing",
              f"{r.status_code} {r.text[:200]} {n2} {n_logs}")

        cur = v + 1
        r = c.put("/api/admin/tunables", headers=ah, json={"values": {"trial_days": 3, "invite_days": 0}, "version": cur})
        errs = r.json().get("detail", {}).get("errors", {}) if r.status_code == 422 else {}
        check(r.status_code == 422 and r.json()["detail"].get("code") == "settings_invalid"
              and {"trial_days", "invite_days"} <= set(errs), "admin_api: a bad save is 422 with every field error",
              f"{r.status_code} {r.text[:200]}")
        r = c.put("/api/admin/tunables", headers=ah, json={"values": {"trial_days": 7}, "version": cur})
        check(r.status_code == 200, "admin_api: trial_days 7 alone is fine at ends_soon_days 3", r.status_code)
        cur += 1
        r = c.put("/api/admin/tunables", headers=ah, json={"values": {"ends_soon_days": 7}, "version": cur})
        check(r.status_code == 422 and "ends_soon_days" in r.json().get("detail", {}).get("errors", {}),
              "admin_api: the cross-field rule is a 422 under ends_soon_days", f"{r.status_code} {r.text[:200]}")
        for bad in (True, 1.5, "1", -1, None):
            r = c.put("/api/admin/tunables", headers=ah, json={"values": {}, "version": bad})
            d = r.json().get("detail", {}) if r.status_code == 422 else {}
            check(r.status_code == 422 and d.get("code") == "settings_invalid" and d.get("errors", {}).get("version"),
                  f"admin_api: version {bad!r} is a 422 settings_invalid under 'version'", f"{r.status_code} {r.text[:200]}")
        r = c.put("/api/admin/tunables", headers=ah, json={"values": {}})
        check(r.status_code == 422 and r.json().get("detail", {}).get("errors", {}).get("version"),
              "admin_api: a missing version is a 422 under 'version'", f"{r.status_code} {r.text[:200]}")
        r = c.put("/api/admin/tunables", headers=ah, json={"values": {}, "version": cur, "extra": 1})
        check(r.status_code == 422, "admin_api: extra fields are refused", r.status_code)
    finally:
        try:
            if ah and start_values is not None:
                cur = c.get("/api/admin/tunables", headers=ah).json().get("version", 0)
                c.put("/api/admin/tunables", headers=ah, json={"values": start_values, "version": cur})
        finally:
            if made_admins:
                db.sql("DELETE FROM admin_action_logs WHERE admin_id = ANY(%s)", made_admins)
                db.sql("DELETE FROM admins WHERE id = ANY(%s)", made_admins)


# ---------------------------------------------------------------------------------------------------- public_config
def section_public_config():
    import httpx
    c = httpx.Client(base_url=BASE, timeout=60)
    made_admins = []
    ah = None
    start_values = None
    try:
        ah, aid = _admin(c, "admin")
        made_admins.append(aid)
        body = c.get("/api/admin/tunables", headers=ah).json()
        start_values = {k: s["value"] for k, s in _by_key(body).items()}
        r = c.get("/api/app/config")
        check(r.status_code == 200 and r.json().get("numbers") == {"trial_days": start_values["trial_days"],
                                                                    "invite_days": start_values["invite_days"]},
              "public_config: signed out, the config carries the trial and invite lengths", r.text[:300])
        r = c.put("/api/admin/tunables", headers=ah,
                  json={"values": {"trial_days": 45}, "version": body["version"]})
        r = c.get("/api/app/config")
        check(r.json().get("numbers") == {"trial_days": 45, "invite_days": start_values["invite_days"]},
              "public_config: a saved trial length shows at once", r.text[:300])
    finally:
        try:
            if ah and start_values is not None:
                cur = c.get("/api/admin/tunables", headers=ah).json().get("version", 0)
                c.put("/api/admin/tunables", headers=ah, json={"values": start_values, "version": cur})
                r = c.get("/api/app/config")
                check(r.json().get("numbers", {}).get("trial_days") == start_values["trial_days"],
                      "public_config: restored, the config shows the original length", r.text[:300])
        finally:
            if made_admins:
                db.sql("DELETE FROM admin_action_logs WHERE admin_id = ANY(%s)", made_admins)
                db.sql("DELETE FROM admins WHERE id = ANY(%s)", made_admins)


# ------------------------------------------------------------------------------------------------------------ clean
def section_clean():
    # Saving through the API always bumps the version, so a row that did not exist comes back as {"version": N}: the
    # settings in it (everything but the version) are what must be as they were.
    def settings(raw):
        try:
            rec = json.loads(raw) if raw else {}
        except ValueError:
            return raw
        return {k: v for k, v in rec.items() if k != "version"} if isinstance(rec, dict) else raw

    check(settings(_stored()) == settings(RUN_START), "clean: the stored settings are as they were when the run started",
          f"{RUN_START!r} -> {_stored()!r}")
    check(_stored(E2E_KEY) is None, "clean: no private tunables row is left")


SECTIONS = {"store": section_store, "admin_api": section_admin_api, "public_config": section_public_config,
            "clean": section_clean}
RUN_START = _stored()  # the row as it was before anything ran


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
