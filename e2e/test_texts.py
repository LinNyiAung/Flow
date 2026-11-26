"""Editable texts e2e (docs/superpowers/specs/2026-11-26-editable-texts-design.md).

Sections (named on the command line, all by default):
  store -- overrides in-process: the nine email keys, placeholder validation, save -> translate, reset, stale versions,
    replaced_default / default_changed, an invalid stored row ignored, translate with an empty cache.
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


SECTIONS = {"store": section_store, "clean": section_clean}


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
