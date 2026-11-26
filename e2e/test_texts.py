"""Editable texts e2e (docs/superpowers/specs/2026-11-26-editable-texts-design.md).

Sections (named on the command line, all by default):
  store -- overrides in-process: the nine email keys, placeholder validation, save -> translate, reset, stale versions,
    replaced_default / default_changed, an invalid stored row ignored, translate with an empty cache.
  admin_api -- HTTP against the stub: roles, listing, save/reset, 409/422/404, the real-key path (a Free user's 403
    message), the admin log. Overrides are removed through the API in `finally`.
  emails -- in-process: the reset email in the person's language, the two-language verification email, HTML escaping,
    an edit appearing in the next email (the lookup is patched in-process; nothing is written to the table).
  clean -- the text_overrides table is as it was when the run started.
Every section deletes the overrides it created in `finally`.
"""
import asyncio
import os
import sys

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


def _table():
    return sorted((r["key"], r["lang"], r["text"]) for r in db.sql("SELECT key, lang, text FROM text_overrides"))


RUN_START = _table()
# A throwaway key that exists only in THIS process's defaults. The stub server polls the same table every 60 s, but its
# load() drops rows for a key it doesn't know, so no test override can ever be cached or served there. (The real-key
# behaviour over HTTP is covered by the admin API sections.)
KEY = "zz_e2e_limit_reached_msg"


# ------------------------------------------------------------------------------------------------------------ store
def section_store():
    from notification_service import NOTIFICATION_TRANSLATIONS as T
    T["en"][KEY] = "You reached the {feature} limit. It resets on {date}."
    T["my"][KEY] = "{feature} ကန့်သတ်ချက်ပြည့်ပါပြီ။ {date} တွင် ပြန်စပါမည်။"
    try:
        _store_body()
    finally:
        T["en"].pop(KEY, None)
        T["my"].pop(KEY, None)
        db.sql("DELETE FROM text_overrides WHERE key = %s", KEY)


def _store_body():
    import text_overrides as to
    from notification_service import translate, NOTIFICATION_TRANSLATIONS as T

    check(set(T["en"]) == set(T["my"]) and all(k in T["en"] for k in (
        "email_verify_subject", "email_verify_heading", "email_verify_intro", "email_verify_button",
        "email_verify_footer", "email_reset_subject", "email_reset_heading", "email_reset_intro",
        "email_reset_footer")), "store: email keys in en and my")
    check(to.placeholders(KEY) == {"feature", "date"}, "store: placeholders from the English default")
    for bad in ("{feature} only", "{feature} {date} {plan}", "{feature} {date} {", "{} {feature} {date}",
                "{feature:>5} {date}", "   ", "x" * 1001, "{feature} {date} {0}", "{feature!r} {date}",
                "{feature.x} {date}"):
        try:
            to.validate(KEY, "my", bad)
            check(False, f"store: rejects {bad[:20]!r}")
        except ValueError:
            check(True, f"store: rejects {bad[:20]!r}")
    for key, lang in (("no_such_key", "en"), (KEY, "fr")):
        try:
            to.validate(key, lang, "x")
            check(False, f"store: unknown {key}/{lang}")
        except ValueError as e:
            check(str(e).startswith("Unknown text"), f"store: unknown {key}/{lang} is 'Unknown text...'", str(e))
    check(to.validate(KEY, "en", "  {date}: no more {feature}  ") == "{date}: no more {feature}",
          "store: accepts reordered placeholders, trimmed")
    check(to.area("plan_limit_reached_msg") == "plans" and to.area("email_reset_intro") == "emails"
          and to.area("family_invite_title") == "family" and to.area("zzz") == "other"
          and to.area("feature_paused_msg") == "App control" and to.area("large_transaction_title") == "budgets",
          "store: area by prefix")

    async def run():
        res = {}
        en_default = T["en"][KEY]
        my_default = T["my"][KEY]
        res["empty"] = (translate(KEY, "en", feature="F", date="D"), translate("no_such_key", "en"))
        try:
            await to.save(KEY, "en", "{date}: no more {feature}", None, "t@example.com")
            row = to.rows()[(KEY, "en")]
            res["en"] = translate(KEY, "en", feature="F", date="D")
            res["my"] = translate(KEY, "my", feature="F", date="D")
            res["version"] = row["version"]
            res["replaced"] = row["replaced_default"] == en_default
            res["unchanged"] = row["default_changed"]
            # stale versions
            try:
                await to.save(KEY, "en", "{feature} {date} again", None, "t@example.com")
                res["conflict_new"] = False
            except to.TextConflict:
                res["conflict_new"] = True
            try:
                await to.save(KEY, "en", "{feature} {date} again", 5, "t@example.com")
                res["conflict_save"] = False
            except to.TextConflict:
                res["conflict_save"] = True
            try:
                await to.reset(KEY, "en", 5, "t@example.com")
                res["conflict_reset"] = False
            except to.TextConflict:
                res["conflict_reset"] = True
            row2 = await to.save(KEY, "en", "{feature} / {date}", 1, "t@example.com")
            res["v2"] = row2["version"]
            # replaced_default changed behind the cache: default_changed after a reload
            db.sql("UPDATE text_overrides SET replaced_default = 'older default {feature} {date}' "
                   "WHERE key = %s AND lang = 'en'", KEY)
            await to.load()
            res["changed"] = to.rows()[(KEY, "en")]["default_changed"]
            res["after_load"] = translate(KEY, "en", feature="F", date="D")
            # a stored row with a placeholder the code does not pass is ignored
            db.sql("INSERT INTO text_overrides (key, lang, text, replaced_default, version) "
                   "VALUES (%s, 'my', '{nope}', 'x', 1)", KEY)
            await to.load()
            res["bad_row_ignored"] = (translate(KEY, "my", feature="F", date="D") == my_default.format(feature="F", date="D"),
                                      (KEY, "my") not in to.rows())
            # a reset gives the default back
            res["reset"] = await to.reset(KEY, "en", 2, "t@example.com")
            res["after_reset"] = translate(KEY, "en", feature="F", date="D")
            res["reset_again"] = await to.reset(KEY, "en", 1, "t@example.com")
            # the email keys through translate, unknown language falls back to English
            res["email"] = translate("email_reset_heading", "fr")
        finally:
            for lang in ("en", "my"):
                db.sql("DELETE FROM text_overrides WHERE key = %s AND lang = %s", KEY, lang)
            await to.load()
        res["end"] = translate(KEY, "en", feature="F", date="D")
        return res

    r = _backend_async(run)
    en_default = T["en"][KEY]
    check(r["empty"] == (en_default.format(feature="F", date="D"), "no_such_key"),
          "store: empty cache gives the default; an unknown key gives the key", r["empty"])
    check(r["en"] == "D: no more F", "store: a saved override is used by translate at once", r["en"])
    check(r["my"] == T["my"][KEY].format(feature="F", date="D"), "store: the other language is unchanged", r["my"])
    check(r["version"] == 1 and r["replaced"] and r["unchanged"] is False,
          "store: version 1, replaced_default is the default, default_changed false")
    check(r["conflict_new"] and r["conflict_save"] and r["conflict_reset"],
          "store: stale versions (create over an existing one, save, reset) are TextConflict", r)
    check(r["v2"] == 2, "store: version increments", r["v2"])
    check(r["changed"] is True, "store: default_changed when replaced_default differs from the default")
    check(r["after_load"] == "F / D", "store: the saved override survives a reload", r["after_load"])
    check(r["bad_row_ignored"] == (True, True), "store: a stored row with a placeholder the code lacks is ignored",
          r["bad_row_ignored"])
    check(r["reset"] is True and r["after_reset"] == en_default.format(feature="F", date="D"),
          "store: reset gives the default again", r["after_reset"])
    check(r["reset_again"] is False, "store: resetting a missing override is False")
    check(r["email"] == T["en"]["email_reset_heading"], "store: unknown language falls back to English", r["email"])
    check(r["end"] == en_default.format(feature="F", date="D"), "store: the cache is clean at the end")


# ---------------------------------------------------------------------------------------------------------- clean
def section_clean():
    check(_table() == RUN_START, "clean: the text_overrides table is as it was at the start of the run",
          f"{RUN_START!r} -> {_table()!r}")


# ------------------------------------------------------------------------------------------------------- admin_api
BASE = "http://127.0.0.1:8765"
PAID_KEY = "plan_paid_required_msg"


def _admin(c, role):
    import admin_utils
    import uuid
    from datetime import UTC, datetime
    email, pw = f"tx-{role}-{uuid.uuid4().hex[:8]}@example.com", "tx-admin-pass-1"
    aid = str(uuid.uuid4())
    db.admins.insert_one({"_id": aid, "name": f"tx {role}", "email": email,
                          "password": admin_utils.get_password_hash(pw), "role": role,
                          "created_at": datetime.now(UTC), "last_login": None})
    r = c.post("/api/admin/login", json={"email": email, "password": pw})
    return {"Authorization": "Bearer " + r.json().get("access_token", "")}, aid


def _free_user(c, made):
    import uuid
    email = f"tx-free-{uuid.uuid4().hex[:8]}@example.com"
    c.post("/api/auth/register", json={"name": "Free", "email": email, "password": "secret123"})
    db.sql("UPDATE users SET is_verified = true, subscription_type = 'free', subscription_expires_at = NULL, "
           "trial_ends_at = NULL WHERE lower(email) = %s", email)
    rows = db.sql("SELECT id FROM users WHERE lower(email) = %s", email)
    made.append(rows[0]["id"])
    r = c.post("/api/auth/login", json={"email": email, "password": "secret123"})
    return {"Authorization": f"Bearer {r.json().get('access_token')}"}


def _free_message(c, h):
    r = c.post("/api/insights/regenerate", headers=h)
    try:
        d = r.json().get("detail", {})
    except Exception:  # noqa: BLE001
        d = {}
    return r.status_code, (d.get("message") if isinstance(d, dict) else str(d))


def section_admin_api():
    import httpx
    from notification_service import NOTIFICATION_TRANSLATIONS as T
    import text_overrides as to
    c = httpx.Client(base_url=BASE, timeout=60)
    made_admins, made_users = [], []
    ah = None
    try:
        mh, mid = _admin(c, "moderator")
        ah, aid = _admin(c, "admin")
        made_admins += [mid, aid]
        free = _free_user(c, made_users)
        default_msg = T["en"][PAID_KEY]

        r = c.get("/api/admin/texts", headers=mh)
        body = r.json() if r.status_code == 200 else {}
        texts = body.get("texts", [])
        keys = [t["key"] for t in texts]
        check(r.status_code == 200 and sorted(keys) == sorted(T["en"]) and len(keys) == len(set(keys)),
              "admin_api: a moderator lists every key once", f"{r.status_code} {r.text[:200]}")
        check(keys == [t["key"] for t in sorted(texts, key=lambda t: (t["area"], t["key"]))],
              "admin_api: sorted by area then key")
        paid = next((t for t in texts if t["key"] == PAID_KEY), {})
        check(paid.get("area") == "plans" and paid.get("placeholders") == []
              and paid.get("default") == {"en": T["en"][PAID_KEY], "my": T["my"][PAID_KEY]}
              and paid.get("override") == {"en": None, "my": None}, "admin_api: area, placeholders, default, no override", paid)
        limit = next((t for t in texts if t["key"] == "plan_limit_reached_msg"), {})
        check(limit.get("placeholders") == sorted(to.placeholders("plan_limit_reached_msg"))
              and limit["placeholders"], "admin_api: placeholders listed, sorted", limit)
        r = c.get("/api/admin/texts")
        check(r.status_code in (401, 403), "admin_api: no token is refused", r.status_code)
        r = c.put(f"/api/admin/texts/{PAID_KEY}/en", headers=mh, json={"text": "Nope", "version": None})
        check(r.status_code == 403, "admin_api: a moderator cannot save", r.status_code)
        r = c.delete(f"/api/admin/texts/{PAID_KEY}/en?version=1", headers=mh)
        check(r.status_code == 403, "admin_api: a moderator cannot reset", r.status_code)

        st, msg = _free_message(c, free)
        check(st == 403 and default_msg in (msg or ""), "admin_api: a Free user gets the default message", (st, msg))

        new = "Paid plans only, sorry."
        r = c.put(f"/api/admin/texts/{PAID_KEY}/en", headers=ah, json={"text": f"  {new}  ", "version": None})
        row = r.json() if r.status_code == 200 else {}
        check(r.status_code == 200 and row.get("version") == 1 and row.get("text") == new
              and row.get("default_changed") is False and row.get("updated_by"),
              "admin_api: an admin saves a valid text (version 1)", f"{r.status_code} {r.text[:200]}")
        st, msg = _free_message(c, free)
        check(st == 403 and (msg or "").startswith(new), "admin_api: the Free user's 403 shows the new text", (st, msg))
        g = next((t for t in c.get("/api/admin/texts", headers=mh).json()["texts"] if t["key"] == PAID_KEY), {})
        check((g.get("override") or {}).get("en", {}) and g["override"]["en"]["version"] == 1
              and g["override"]["my"] is None, "admin_api: the listing shows the override", g)

        r = c.put(f"/api/admin/texts/{PAID_KEY}/en", headers=ah, json={"text": "Again", "version": None})
        check(r.status_code == 409 and r.json() == {"detail": {
            "code": "text_conflict", "message": "This text was changed by someone else. Reload to see it."}},
              "admin_api: a stale save is 409 text_conflict", f"{r.status_code} {r.text[:200]}")
        r = c.put(f"/api/admin/texts/{PAID_KEY}/en", headers=ah, json={"text": "Again", "version": 1, "extra": 1})
        check(r.status_code == 422, "admin_api: an unknown body field is refused", r.status_code)

        r = c.put("/api/admin/texts/plan_limit_reached_msg/en", headers=ah, json={"text": "No placeholders", "version": None})
        check(r.status_code == 422 and isinstance(r.json().get("detail"), str)
              and "{feature}" in r.json()["detail"], "admin_api: a missing placeholder is a readable 422",
              f"{r.status_code} {r.text[:200]}")
        r = c.put("/api/admin/texts/no_such_key/en", headers=ah, json={"text": "x", "version": None})
        check(r.status_code == 404, "admin_api: an unknown key is 404", r.status_code)
        r = c.put(f"/api/admin/texts/{PAID_KEY}/fr", headers=ah, json={"text": "x", "version": None})
        check(r.status_code == 404, "admin_api: an unknown language is 404", r.status_code)

        r = c.delete(f"/api/admin/texts/{PAID_KEY}/en?version=7", headers=ah)
        check(r.status_code == 409, "admin_api: a reset at a stale version is 409", r.status_code)
        r = c.delete(f"/api/admin/texts/{PAID_KEY}/en?version=1", headers=ah)
        check(r.status_code == 200 and r.json() == {"reset": True}, "admin_api: a reset is 200",
              f"{r.status_code} {r.text[:200]}")
        st, msg = _free_message(c, free)
        check(st == 403 and default_msg in (msg or "") and new not in (msg or ""),
              "admin_api: the Free user's message is the default again", (st, msg))
        r = c.delete(f"/api/admin/texts/{PAID_KEY}/en?version=1", headers=ah)
        check(r.status_code == 404, "admin_api: resetting again is 404", r.status_code)
        r = c.delete(f"/api/admin/texts/no_such_key/en?version=1", headers=ah)
        check(r.status_code == 404, "admin_api: resetting an unknown key is 404", r.status_code)

        logs = db.sql("SELECT action, details FROM admin_action_logs WHERE admin_id = %s", aid)
        upd = [x for x in logs if x["action"] == "text_update"]
        rst = [x for x in logs if x["action"] == "text_reset"]
        check(len(upd) == 1 and PAID_KEY in upd[0]["details"] and "en" in upd[0]["details"] and new in upd[0]["details"]
              and len(upd[0]["details"]) <= 2000, "admin_api: the log has text_update naming key and language", upd)
        check(len(rst) == 1 and PAID_KEY in rst[0]["details"] and "en" in rst[0]["details"],
              "admin_api: the log has text_reset naming key and language", rst)
    finally:
        # Remove through the API so the server's own cache is clean at once (not only the table).
        if ah is not None:
            for lang in ("en", "my"):
                try:
                    for ver in range(1, 4):
                        if c.delete(f"/api/admin/texts/{PAID_KEY}/{lang}?version={ver}", headers=ah).status_code != 409:
                            break
                except Exception:  # noqa: BLE001
                    pass
        db.sql("DELETE FROM text_overrides WHERE key = %s", PAID_KEY)
        if made_admins:
            db.sql("DELETE FROM admin_action_logs WHERE admin_id = ANY(%s)", made_admins)
            db.sql("DELETE FROM admins WHERE id = ANY(%s)", made_admins)
        if made_users:
            db.sql("DELETE FROM users WHERE id = ANY(%s)", made_users)


# ------------------------------------------------------------------------------------------------------------ emails
def _parts(msg):
    plain = msg.get_body(preferencelist=("plain",)).get_content()
    html = msg.get_body(preferencelist=("html",)).get_content()
    return plain, html


def section_emails():
    import re
    import html as htmllib
    import text_overrides as to
    from notification_service import NOTIFICATION_TRANSLATIONS as T
    import email_service as es

    # reset email, both languages (build only, never send)
    for lang in ("en", "my"):
        m = es.build_reset_email("a@example.com", "123456", lang)
        plain, html = _parts(m)
        check(m["Subject"] == T[lang]["email_reset_subject"], f"emails: reset subject in {lang}", m["Subject"])
        check("123456" in html and "123456" in plain, f"emails: reset code in html and plain ({lang})")
        for k in ("heading", "intro", "footer"):
            check(htmllib.escape(T[lang][f"email_reset_{k}"]) in html and T[lang][f"email_reset_{k}"] in plain,
                  f"emails: reset {k} in html and plain ({lang})")
        check(m["To"] == "a@example.com", f"emails: reset recipient ({lang})")
    my_html = _parts(es.build_reset_email("a@example.com", "123456", "my"))[1]
    check(T["my"]["email_reset_heading"] in my_html, "emails: Myanmar text survives in the html")
    check(T["en"]["email_reset_heading"] not in my_html, "emails: the Myanmar reset email has no English heading")
    unknown = es.build_reset_email("a@example.com", "123456", "fr")
    check(unknown["Subject"] == T["en"]["email_reset_subject"], "emails: unknown language falls back to English")

    # verification email: both languages
    m = es.build_verification_email("a+b@example.com", "tok en")
    plain, html = _parts(m)
    check(m["Subject"] == T["en"]["email_verify_subject"] + " / " + T["my"]["email_verify_subject"],
          "emails: verification subject is EN / MY", m["Subject"])
    links = re.findall(r'href="([^"]*)"', html)
    check(len(links) == 1 and "/api/auth/verify-email?" in links[0] and "token=tok%20en" in links[0]
          and "email=a%2Bb%40example.com" in links[0].replace("&amp;", "&"),
          "emails: html has one link, to verify-email with the token", links)
    check("<a " in html and "background" in html.split("<a ", 1)[1].split(">", 1)[0],
          "emails: the link is styled as a button")
    link = htmllib.unescape(links[0]) if links else "?"
    check(link in plain, "emails: plain text contains the link")
    check(html.count(htmllib.escape(link)) >= 2, "emails: the link is also printed as text in the html")
    check(T["en"]["email_verify_button"] + " / " + T["my"]["email_verify_button"] in htmllib.unescape(html),
          "emails: the button is labelled EN / MY")
    for lang in ("en", "my"):
        for k in ("heading", "intro", "footer"):
            t = T[lang][f"email_verify_{k}"]
            check(htmllib.escape(t) in html and t in plain, f"emails: verify {k} ({lang}) in html and plain")
    check(plain.index(T["en"]["email_verify_intro"]) < plain.index(T["my"]["email_verify_intro"]),
          "emails: English texts come before Myanmar")

    # an override shows up in the next email: patch the in-process lookup only, nothing is written to the table
    real_get = to.get
    to.get = lambda key, lang: "Reset <b>&</b> now" if (key, lang) == ("email_reset_heading", "en") else real_get(key, lang)
    try:
        plain, html = _parts(es.build_reset_email("a@example.com", "123456", "en"))
        other = _parts(es.build_reset_email("a@example.com", "123456", "my"))[1]
    finally:
        to.get = real_get
    check("Reset &lt;b&gt;&amp;&lt;/b&gt; now" in html and "<b>&</b>" not in html,
          "emails: an edited text appears in the next email, HTML-escaped")
    check("Reset <b>&</b> now" in plain, "emails: the edited text is raw in the plain version")
    check(T["my"]["email_reset_heading"] in other, "emails: the other language is unchanged")
    check(T["en"]["email_reset_heading"] in _parts(es.build_reset_email("a@example.com", "1", "en"))[1],
          "emails: the lookup is restored")


SECTIONS = {"store": section_store, "admin_api": section_admin_api, "emails": section_emails, "clean": section_clean}


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
