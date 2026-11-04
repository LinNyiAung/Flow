"""Checks for custom insights (Pro): the quota feature `insight_custom`, the custom_insights table and its data layer.

Run from test_plans: `migration_checks(test_plans_module)` (sync, right after the plans migration checks; it runs
alembic downgrade / upgrade on the throwaway e2e database and always leaves it at head) and
`await run(test_plans_module)` (inside test_plans' single asyncio.run, after the upgrade-request checks).

`run` builds a small helper object `h` and calls `notification_checks(t, h)` (the ready / not-created notifications,
in this process) and `generation_checks(t, h)` (custom_insights_service: figures, prompt, the background job and the
stuck-job sweeper, in this process with the fake AI providers) after `storage_checks(t, h)`: the data layer (sql.custom_insights and
transactions_db.changed_since) is used in this process, users and plans go over HTTP to the stubbed server and the
database is read / preset through psycopg. Users are tagged `t9c-<name>-<tag>@example.com` and are all removed in a
`finally` (deleting a user cascades to its custom insights and counters).
"""
import re
import uuid
from types import SimpleNamespace
from datetime import date, datetime, timedelta, UTC

import httpx

MYANMAR = re.compile("[က-႟]")
BASE = "http://127.0.0.1:8765"
BEFORE_CUSTOM = "a7d3e5c91f20"  # the revision this feature's migration revises
HEAD_WITH_CUSTOM = "b8f4d2c6e9a1"


# ---------------------------------------------------------------- migration
def migration_checks(t):
    check = t.check
    uid = "t9c-mig"
    with t.connect() as conn:
        try:
            conn.execute(*t.new_user(uid))
            counter = ("INSERT INTO usage_counters (user_id, feature, period, period_start, used) "
                       "VALUES (%s, %s, 'month', '2026-11-01', 3)")
            conn.execute(counter, (uid, "insight_custom"))
            conn.execute(counter, (uid, "chat"))
            ok_down, out_down = t.alembic("downgrade", BEFORE_CUSTOM)
            left = conn.execute("SELECT feature FROM usage_counters WHERE user_id = %s", (uid,)).fetchall()
            check(ok_down and t.current_revision(conn) == BEFORE_CUSTOM and "custom_insights" not in t.table_names(conn)
                  and not any(f == "insight_custom" for (_, f) in t.seeded_limits(conn)) and left == [("chat",)],
                  "custom_migration_down: downgrade to a7d3e5c91f20 drops custom_insights and the insight_custom limits "
                  "and counters (other counters stay)", f"{out_down} {left}")
            ok_up, out_up = t.alembic("upgrade", "head")
            limits = t.seeded_limits(conn)
            check(ok_up and "custom_insights" in t.table_names(conn)
                  and limits[("pro", "insight_custom")] == ("counted", 10, "month")
                  and limits[("plus", "insight_custom")] == ("locked", None, None)
                  and limits[("free", "insight_custom")] == ("locked", None, None) and len(limits) == 27,
                  "custom_migration_up: upgrade re-creates the table and seeds Free/Plus locked, Pro 10 a month", out_up)
            indexes = {r[0]: r[1] for r in conn.execute(
                "SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'custom_insights'")}
            pending = indexes.get("uq_custom_insights_pending_user", "")
            check("UNIQUE" in pending and "status = 'pending'" in pending
                  and "ix_custom_insights_user_created" in indexes and "created_at DESC" in indexes["ix_custom_insights_user_created"]
                  and "ix_custom_insights_user_id" in indexes,
                  "custom_migration_indexes: unique one-pending-per-user (partial), newest-first per user, user_id", indexes)
        finally:
            ok, out = t.alembic("upgrade", "head")  # whatever happened above, leave the database at head
            conn.execute("DELETE FROM users WHERE id = %s", (uid,))
            check(ok and t.current_revision(conn) == HEAD_WITH_CUSTOM, "custom_migration: the database is left at head", out)


# ---------------------------------------------------------------- the table's own rules (CHECKs, defaults)
def constraint_checks(t):
    check = t.check
    ins = ("INSERT INTO custom_insights (id, user_id, start_date, end_date, preset, instruction, status, content, deleted_at) "
           "VALUES (%s, 't9c-chk', %s, %s, %s, %s, %s, %s, %s)")

    def ok(label, expect, start="2026-09-01", end="2026-09-30", preset=None, instruction=None, status="pending",
           content=None, deleted_at=None):
        with t.connect() as conn:
            got = t.accepted(conn, t.new_user("t9c-chk"),
                             (ins, (str(uuid.uuid4()), start, end, preset, instruction, status, content, deleted_at)))
        check(got == expect, f"storage_constraint: {label} is {'accepted' if expect else 'rejected'}")

    now = datetime.now(UTC)
    ok("a plain pending row", True)
    ok("a ready row with content", True, status="ready", content="## Summary\nx")
    ok("a ready row without content", False, status="ready")
    ok("a ready row with blank content", False, status="ready", content="   ")
    ok("status 'done'", False, status="done")
    ok("an end date before the start date", False, start="2026-09-30", end="2026-09-01")
    ok("a one-day range (end = start)", True, start="2026-09-01", end="2026-09-01")
    ok("preset 'where_to_save'", True, preset="where_to_save")
    ok("preset 'bogus'", False, preset="bogus")
    ok("an instruction of 300 characters", True, instruction="x" * 300)
    ok("an instruction of 301 characters", False, instruction="x" * 301)
    ok("a preset together with an instruction", False, preset="biggest_changes", instruction="why?")
    ok("deleted_at on a failed row", True, status="failed", deleted_at=now)
    ok("deleted_at on a refused row", True, status="refused", deleted_at=now)
    ok("deleted_at on a ready row", False, status="ready", content="x", deleted_at=now)
    ok("deleted_at on a pending row", False, deleted_at=now)
    with t.connect() as conn:
        uid = "t9c-dflt"
        try:
            conn.execute(*t.new_user(uid))
            conn.execute("INSERT INTO custom_insights (id, user_id, start_date, end_date) VALUES ('t9c-dflt-1', %s, "
                         "'2026-09-01', '2026-09-30')", (uid,))
            row = conn.execute("SELECT status, instruction_key, counter_keys, created_at, preset, instruction, content, "
                               "figures, completed_at, deleted_at FROM custom_insights WHERE id = 't9c-dflt-1'").fetchone()
            check(row is not None and row[0] == "pending" and row[1] == "" and row[2] == [] and row[3] is not None
                  and all(v is None for v in row[4:]),
                  "storage_defaults: status 'pending', instruction_key '', counter_keys [], created_at now, the rest NULL", row)
        finally:
            conn.execute("DELETE FROM users WHERE id = %s", (uid,))


# ---------------------------------------------------------------- the data layer
async def storage_checks(t, h):
    from sql import custom_insights as ci
    from sql import transactions as transactions_db

    check = t.check
    constraint_checks(t)
    now = datetime.now(UTC).replace(microsecond=0)
    s, e = date(2026, 9, 1), date(2026, 9, 30)
    keys = [["insight_custom", "month", "2026-11-01"]]

    def doc(uid, **kw):
        d = {"_id": str(uuid.uuid4()), "user_id": uid, "start_date": s, "end_date": e, "preset": None, "instruction": None,
             "instruction_key": "", "counter_keys": keys, "created_at": now}
        d.update(kw)
        return d

    async def make(uid, status, created_at, content=None, **kw):
        """A finished row: inserted pending, then moved out of pending."""
        d = doc(uid, created_at=created_at, **kw)
        assert await ci.insert_pending(d) is True
        if status == "ready":
            content = content or "## Summary\nx"
        assert await ci.finish(d["_id"], status=status, now=created_at, content=content) is not None
        return d["_id"]

    def ids(rows):
        return [r["_id"] for r in rows]

    ua, _ = h.register("a")
    ub, _ = h.register("b")
    uc, _ = h.register("c")

    # ---- one pending per user
    figs = {"currencies": {"usd": {"outflow": 12.5, "inflow": 0}}, "count": 2}
    a, a2, b = doc(ua, instruction="where did it go?", instruction_key="where did it go?"), doc(ua), doc(ub, figures=figs)
    check(await ci.insert_pending(a) is True and await ci.insert_pending(a2) is False
          and await ci.insert_pending(b) is True, "storage_one_pending_per_user")
    check(await ci.get(a2["_id"]) is None and await ci.has_pending(ua) is True and await ci.has_pending(ub) is True
          and await ci.has_pending(uc) is False, "storage_has_pending: true for a user with a pending row, false without")

    got = await ci.get(a["_id"])
    check(got is not None and got["_id"] == a["_id"] and "id" not in got and got["user_id"] == ua
          and got["start_date"] == s and type(got["start_date"]) is date and got["end_date"] == e and type(got["end_date"]) is date
          and got["status"] == "pending" and got["instruction"] == "where did it go?"
          and got["instruction_key"] == "where did it go?" and got["preset"] is None and got["counter_keys"] == keys
          and got["created_at"] == now and got["content"] is None and got["figures"] is None and got["completed_at"] is None
          and got["deleted_at"] is None,
          "storage_doc_shape: _id, date columns as date, counter_keys as [feature, period, 'YYYY-MM-DD'] lists", got)

    with t.connect() as conn:
        null_figures = conn.execute("SELECT figures IS NULL FROM custom_insights WHERE id = %s", (a["_id"],)).fetchone()[0]
    check((await ci.get(b["_id"]))["figures"] == figs and null_figures is True,
          "storage_figures: a figures dict round-trips; left out it is SQL NULL (not the JSON value null)")

    # created_at is optional: the database default applies
    d = doc(uc)
    del d["created_at"]
    before = datetime.now(UTC) - timedelta(seconds=5)
    check(await ci.insert_pending(d) is True and before <= (await ci.get(d["_id"]))["created_at"] <= datetime.now(UTC) + timedelta(seconds=5),
          "storage_insert_defaults: created_at defaults to now when the caller leaves it out")
    await ci.finish(d["_id"], status="failed", now=now)  # uc has no pending row again

    # ---- get is scoped
    check((await ci.get(a["_id"], user_id=ua)) is not None and await ci.get(a["_id"], user_id=ub) is None
          and await ci.get("no-such-id") is None, "storage_get_scoped: user_id filters, an unknown id is None")

    # ---- finish only from pending
    done = await ci.finish(a["_id"], status="ready", content="## Summary\nx", now=now, ai_provider="claude",
                           ai_model="claude-sonnet-5-5", input_tokens=120, output_tokens=340)
    check(done is not None and await ci.finish(a["_id"], status="failed", now=now) is None,
          "storage_finish_only_from_pending")
    after = await ci.get(a["_id"])
    check(done is not None and done["_id"] == a["_id"] and done["status"] == "ready" and done["completed_at"] == now
          and done["content"] == "## Summary\nx" and done["ai_provider"] == "claude" and done["ai_model"] == "claude-sonnet-5-5"
          and done["input_tokens"] == 120 and done["output_tokens"] == 340 and after["status"] == "ready"
          and after["content"] == "## Summary\nx" and after["completed_at"] == now,
          "storage_finish_sets_fields: status, content, completed_at, provider, model and tokens; the failed attempt changed nothing",
          (done, after))
    check(await ci.has_pending(ua) is False and await ci.insert_pending(doc(ua)) is True,
          "storage_pending_slot_frees: after finish the user can start a new report")
    await ci.finish(await _pending_id(ua), status="refused", now=now)

    # ---- list_for_user: newest first, not deleted, limited
    ul, _ = h.register("list")
    r1 = await make(ul, "ready", now - timedelta(hours=3))
    r2 = await make(ul, "ready", now - timedelta(hours=1))
    r3 = await make(ul, "failed", now - timedelta(hours=2))
    check(ids(await ci.list_for_user(ul)) == [r2, r3, r1] and ids(await ci.list_for_user(ul, limit=2)) == [r2, r3],
          "storage_list_newest_first: newest first, limit applies")
    check(await ci.delete_for_user(r3, ul, now) == "hidden" and ids(await ci.list_for_user(ul)) == [r2, r1]
          and ids(await ci.list_for_user(ub)) == [b["_id"]],
          "storage_list_hides_deleted: a hidden row is not listed, other users' rows never are")

    # ---- find_ready_match: the newest ready row with exactly these values
    um, _ = h.register("match")
    await make(um, "ready", now - timedelta(hours=5), instruction_key="k")
    ready2 = await make(um, "ready", now - timedelta(hours=2), instruction_key="k")
    await make(um, "failed", now - timedelta(hours=1), instruction_key="k")
    await make(um, "ready", now - timedelta(hours=4), instruction_key="other")
    match = await ci.find_ready_match(um, s, e, "k")
    check(match is not None and match["_id"] == ready2 and await ci.find_ready_match(um, s, e, "other") is not None
          and await ci.find_ready_match(um, s, e, "missing") is None
          and await ci.find_ready_match(um, s, e + timedelta(days=1), "k") is None
          and await ci.find_ready_match(um, s + timedelta(days=1), e, "k") is None
          and await ci.find_ready_match(ub, s, e, "k") is None,
          "storage_find_ready_match: newest ready row with the same dates and instruction_key; none for other values or users")
    await ci.insert_pending(doc(um, instruction_key="pend"))
    check(await ci.find_ready_match(um, s, e, "pend") is None, "storage_find_ready_match: a pending row never matches")

    # ---- delete: ready removes, failed / refused hide and keep counting, pending is refused
    ud, _ = h.register("del")
    day_start = now - timedelta(hours=12)
    ready_id = await make(ud, "ready", now - timedelta(minutes=50), instruction="my words", instruction_key="my words")
    failed_id = await make(ud, "failed", now - timedelta(minutes=40), content="partial text", instruction="secret question",
                           instruction_key="secret question", figures=figs)
    with t.connect() as conn:  # set directly: set_translation only writes to ready rows
        conn.execute("UPDATE custom_insights SET content_mm = 'ဘာသာပြန်' WHERE id = %s", (failed_id,))
    refused_id = await make(ud, "refused", now - timedelta(minutes=30), preset="where_to_save")
    pending_id = doc(ud)["_id"]
    await ci.insert_pending(doc(ud, _id=pending_id))
    check(await ci.delete_for_user(ready_id, ud, now) == "deleted" and await ci.get(ready_id, include_deleted=True) is None,
          "storage_delete_ready_removes_row")
    check(await ci.delete_for_user(failed_id, ud, now) == "hidden" and failed_id not in ids(await ci.list_for_user(ud))
          and await ci.count_attempts_since(ud, day_start) == 2, "storage_delete_failed_hides_but_counts")
    check(await ci.get(failed_id) is None and (await ci.get(failed_id, user_id=ud)) is None, "storage_get_skips_hidden: get() hides a hidden row")
    with t.connect() as conn:
        null_figures = conn.execute("SELECT figures IS NULL FROM custom_insights WHERE id = %s", (failed_id,)).fetchone()[0]
    hidden = await ci.get(failed_id, include_deleted=True)
    check(hidden is not None and hidden["deleted_at"] == now and hidden["status"] == "failed" and hidden["instruction"] is None
          and hidden["preset"] is None and hidden["content"] is None and hidden["content_mm"] is None and null_figures is True
          and hidden["instruction_key"] == "",
          "storage_delete_hidden_clears_content: instruction, instruction_key, preset, content, content_mm and figures are "
          "cleared, deleted_at set", hidden)
    check(await ci.delete_for_user(refused_id, ud, now) == "hidden" and await ci.count_attempts_since(ud, day_start) == 2
          and await ci.count_attempts_since(ud, now - timedelta(minutes=35)) == 1
          and await ci.count_attempts_since(ud, now) == 0, "storage_count_attempts_since: failed and refused count, deleted too, "
          "created_at >= since; ready and pending do not")
    check(await ci.delete_for_user(pending_id, ud, now) == "pending" and (await ci.get(pending_id))["status"] == "pending",
          "storage_delete_pending_refused")
    check(await ci.delete_for_user(failed_id, ud, now) == "missing" and await ci.delete_for_user(ready_id, ud, now) == "missing"
          and await ci.delete_for_user("no-such-id", ud, now) == "missing"
          and await ci.delete_for_user(pending_id, ub, now) == "missing",
          "storage_delete_missing: an already deleted, unknown or someone else's report is missing")

    # ---- fail_stuck: one UPDATE, once
    us, _ = h.register("stuck")
    uf, _ = h.register("fresh")
    old = doc(us, created_at=now - timedelta(minutes=30), counter_keys=keys)
    fresh = doc(uf, created_at=now - timedelta(minutes=5))
    await ci.insert_pending(old)
    await ci.insert_pending(fresh)
    swept = await ci.fail_stuck(now - timedelta(minutes=20), now)
    swept_ours = [r for r in swept if r["_id"] in (old["_id"], fresh["_id"])]
    check(len(swept_ours) == 1 and swept_ours[0]["_id"] == old["_id"] and swept_ours[0]["status"] == "failed"
          and swept_ours[0]["completed_at"] == now and swept_ours[0]["counter_keys"] == keys
          and swept_ours[0]["user_id"] == us and (await ci.get(fresh["_id"]))["status"] == "pending"
          and await ci.fail_stuck(now - timedelta(minutes=20), now) == []
          and await ci.finish(old["_id"], status="ready", content="late", now=now) is None,
          "storage_fail_stuck_once: returns the stuck row as failed once, then nothing; a fresh pending row stays; "
          "a late finish gets None", swept)

    # ---- set_translation
    check(await ci.set_translation(r2, "## အနှစ်ချုပ်\nx") is None and (await ci.get(r2))["content_mm"] == "## အနှစ်ချုပ်\nx",
          "storage_set_translation: content_mm is stored")
    await ci.set_translation(failed_id, "x")   # hidden failed row
    await ci.set_translation(refused_id, "x")  # hidden refused row
    live_failed = await make(uc, "failed", now - timedelta(hours=1))  # a visible failed row
    await ci.set_translation(live_failed, "x")
    with t.connect() as conn:
        mm = conn.execute("SELECT id, content_mm FROM custom_insights WHERE id = ANY(%s)",
                          ([failed_id, refused_id, live_failed],)).fetchall()
    check(len(mm) == 3 and all(v is None for (_, v) in mm),
          "storage_set_translation_ready_only: does nothing on a failed, refused or hidden row", mm)

    # ---- finish refuses a status that is not a way out of pending
    up_, _ = h.register("fin")
    pid = doc(up_)
    await ci.insert_pending(pid)
    raised = []
    for bad in ("pending", "done", ""):
        try:
            await ci.finish(pid["_id"], status=bad, now=now)
            raised.append(False)
        except ValueError:
            raised.append(True)
    check(all(raised) and (await ci.get(pid["_id"]))["status"] == "pending",
          "storage_finish_status_guard: finish(status='pending'/'done'/'') raises ValueError and leaves the row pending", raised)

    # ---- changed_since (transaction created or edited after the report)
    ut, th = h.register("tx")
    tx_day = date(2026, 9, 15)
    s_bound = datetime(2026, 9, 1, tzinfo=UTC)
    e_bound = datetime(2026, 9, 30, 23, 59, 59, tzinfo=UTC)
    before_add = datetime.now(UTC) - timedelta(seconds=2)
    tx = h.add_tx(th, "outflow", 12.5, tx_day)
    after_add = datetime.now(UTC) + timedelta(seconds=2)
    out_of_range = h.add_tx(th, "outflow", 3.0, date(2026, 10, 15))
    check(tx and await transactions_db.changed_since(ut, s_bound, e_bound, before_add) is True
          and await transactions_db.changed_since(ut, s_bound, e_bound, after_add) is False,
          "storage_changed_since: a transaction created after `since` counts, an older one does not")
    check(await transactions_db.changed_since(ut, datetime(2026, 10, 1, tzinfo=UTC), datetime(2026, 10, 31, tzinfo=UTC), before_add) is True
          and await transactions_db.changed_since(ut, datetime(2026, 8, 1, tzinfo=UTC), datetime(2026, 8, 31, tzinfo=UTC), before_add) is False
          and await transactions_db.changed_since(ub, s_bound, e_bound, before_add) is False,
          "storage_changed_since: only transactions dated in [start, end] of that user count")
    edit_at = datetime.now(UTC)
    with t.connect() as conn:  # an edit moves updated_at (the app sets it on every edit), created_at stays
        conn.execute("UPDATE transactions SET created_at = %s, updated_at = %s WHERE id = %s",
                     (edit_at - timedelta(hours=1), edit_at - timedelta(hours=1), tx))
        conn.execute("DELETE FROM transactions WHERE id = %s", (out_of_range,))
    base = edit_at - timedelta(minutes=30)
    check(await transactions_db.changed_since(ut, s_bound, e_bound, base) is False, "storage_changed_since: untouched since -> False")
    with t.connect() as conn:
        conn.execute("UPDATE transactions SET updated_at = %s WHERE id = %s", (edit_at, tx))
    check(await transactions_db.changed_since(ut, s_bound, e_bound, base) is True
          and await transactions_db.changed_since(ut, s_bound, e_bound, edit_at) is False,
          "storage_changed_since: an edit (updated_at) after `since` counts, once `since` passes it it does not")

    # ---- the user's custom insights go with the user
    with t.connect() as conn:
        n_before = conn.execute("SELECT count(*) FROM custom_insights WHERE user_id = %s", (ud,)).fetchone()[0]
        conn.execute("DELETE FROM users WHERE id = %s", (ud,))
        n_after = conn.execute("SELECT count(*) FROM custom_insights WHERE user_id = %s", (ud,)).fetchone()[0]
    check(n_before >= 3 and n_after == 0, "storage_cascade: deleting the user deletes their custom insights", (n_before, n_after))

    # ---- GET /api/plan shows the new feature
    _, free_h = h.register("planfree")
    up, pro_h = h.register("planpro")
    upl, plus_h = h.register("planplus")
    check(h.set_plan(up, "pro") and h.set_plan(upl, "plus"), "plan_setup: made a Pro and a Plus user")
    feats = {n: h.c.get("/api/plan", headers=hd).json().get("features", {}).get("insight_custom", {})
             for n, hd in (("pro", pro_h), ("plus", plus_h), ("free", free_h))}
    p = feats["pro"]
    check(p.get("mode") == "counted" and p.get("limit") == 10 and p.get("period") == "month" and p.get("used") == 0,
          "plan_status_insight_custom: GET /api/plan shows Pro 10 a month", feats)
    check(feats["plus"].get("mode") == "locked" and feats["free"].get("mode") == "locked",
          "plan_status_insight_custom: Free and Plus are locked", feats)
    h.set_used(up, 4)
    check(h.used(up) == 4 and h.c.get("/api/plan", headers=pro_h).json()["features"]["insight_custom"].get("used") == 4
          and h.used(up, "week") == 4 and h.used(up, feature="chat") == 0,
          "plan_status_insight_custom: the counter helpers read and write the insight_custom counter")


async def _pending_id(uid):
    """The id of the user's pending row (the one the unique index allows)."""
    from sql.db import fetch_value
    from sqlalchemy import select
    from sql.tables import custom_insights as c
    return await fetch_value(select(c.c.id).where(c.c.user_id == uid, c.c.status == "pending"))


# ---------------------------------------------------------------- notifications
async def notification_checks(t, h):
    """notify_custom_insight_ready / notify_custom_insight_failed (what the generation service sends) and format_day."""
    import stubenv
    import notification_service as ns
    from plans.access import format_day
    stubenv.patch_loaded_modules()  # no real push; notifications are still stored

    check = t.check
    start, end = date(2026, 10, 6), date(2026, 11, 4)
    en_uid, _ = h.register("noten", "en")
    my_uid, _ = h.register("notmy", "my")

    def notes(uid, kind):
        return list(h.db.notifications.find({"user_id": uid, "type": kind}))

    rid = str(uuid.uuid4())
    await ns.notify_custom_insight_ready(en_uid, rid, start, end)
    got = notes(en_uid, "custom_insight_ready")
    row = got[0] if got else {}
    check(len(got) == 1 and row["goal_id"] == rid and "Oct 6, 2026 – Nov 4, 2026" in row["message"]
          and row["title"] == "Your custom insight is ready 📊" and row["message"].endswith("Tap to read it."),
          "notify_custom_ready: stored with the report id and the date range", row)

    fid = str(uuid.uuid4())
    await ns.notify_custom_insight_failed(en_uid, fid, start, end, refused=False)
    got = notes(en_uid, "custom_insight_failed")
    f = got[0] if got else {}
    check(len(got) == 1 and f["type"] == "custom_insight_failed" and "wasn't counted" in f["message"]
          and f["goal_id"] == fid and f["title"] == "Custom insight not created" and "Oct 6, 2026 – Nov 4, 2026" in f["message"],
          "notify_custom_failed: says it was not counted", f)

    xid = str(uuid.uuid4())
    await ns.notify_custom_insight_failed(en_uid, xid, start, end, refused=True)
    r = next((n for n in notes(en_uid, "custom_insight_failed") if n["goal_id"] == xid), {})
    check(r and r["title"] == f["title"] and r["message"] != f["message"] and "answer from your finances" in r["message"]
          and r["message"].endswith("It wasn't counted."),
          "notify_custom_refused: its own message, the failed type and title", r)

    mid = str(uuid.uuid4())
    await ns.notify_custom_insight_ready(my_uid, mid, start, end)
    await ns.notify_custom_insight_failed(my_uid, str(uuid.uuid4()), start, end, refused=True)
    mm = notes(my_uid, "custom_insight_ready")
    mm_row = mm[0] if mm else {"title": "", "message": ""}
    mm_fail = (notes(my_uid, "custom_insight_failed") or [{"title": "", "message": ""}])[0]
    check(MYANMAR.search(mm_row["title"]) and MYANMAR.search(mm_row["message"]) and "6 အောက်တိုဘာ 2026 – 4 နိုဝင်ဘာ 2026" in mm_row["message"]
          and MYANMAR.search(mm_fail["title"]) and MYANMAR.search(mm_fail["message"]) and "{" not in mm_row["message"] + mm_fail["message"],
          "notify_custom_myanmar: a Myanmar user gets Myanmar text and a Myanmar date range", (mm_row, mm_fail))

    check(format_day(date(2026, 12, 1), "en") == "Dec 1, 2026" and format_day(date(2026, 12, 1), "my") == "1 ဒီဇင်ဘာ 2026"
          and format_day(date(2026, 1, 31), "en") == "Jan 31, 2026" and format_day(date(2026, 3, 10), "en") == "Mar 10, 2026",
          "format_day: the calendar day as 'Dec 1, 2026' / '1 ဒီဇင်ဘာ 2026', no timezone shift")

    prefs = await ns.get_user_notification_preferences(en_uid)
    check(prefs.get("custom_insight_ready") is True and prefs.get("custom_insight_failed") is True,
          "notify_custom_prefs: both types are on by default", prefs)

    try:
        await ns.notify_custom_insight_ready("t9c-no-such-user", str(uuid.uuid4()), start, end)
        await ns.notify_custom_insight_failed("t9c-no-such-user", str(uuid.uuid4()), start, end, refused=False)
        swallowed = True
    except Exception as exc:  # noqa: BLE001
        swallowed = repr(exc)
    check(swallowed is True, "notify_custom_failure_swallowed: a failing send is logged, not raised", swallowed)


# ---------------------------------------------------------------- generation (figures, prompt, job, sweeper)
async def generation_checks(t, h):
    """custom_insights_service in this process: the figures, the range rules, the prompt and context, run_report with
    the fake AI providers (ready / refused / failed), cancellation, and the stuck-job sweeper racing a slow job.

    Pending rows are made the way the create route will make them: reserve a use, insert_pending with the reservation's
    counter keys and the computed figures, commit. The use counter is reset (h.set_used) before each scenario."""
    import asyncio
    import stubenv
    import plans_chat_checks
    from plans import quota, store
    from sql import custom_insights as ci
    from sql import users as users_db
    from ai_providers import health
    from ai_providers.runner import RunResult
    from ai_providers.types import Completion, Target
    from tz_utils import app_today, get_app_timezone

    check = t.check
    try:
        import custom_insights_service as cis
        import scheduler
    except ImportError as exc:
        check(False, "generation_import: custom_insights_service can be imported", repr(exc))
        return
    stubenv.patch_loaded_modules()  # no real push; notifications are still stored
    await store.load()

    def reset_ai():
        """Fakes cleared and every provider's cool-off cleared, here and in the server."""
        stubenv.clear_fake_ai()
        health.reset()
        for p in ("openai", "gemini", "claude"):
            h.c.post(f"/api/admin/ai/test/{p}", headers=h.AD, json={})

    def ai_calls():
        return sum(1 for x in plans_chat_checks.outbox_lines() if x.get("kind") == "ai_call")

    def notes(uid):
        return sorted(h.db.notifications.find({"user_id": uid}), key=lambda n: n["created_at"])

    def notes_for(uid, rid):
        return [n for n in notes(uid) if n.get("goal_id") == rid]

    def answering(text):
        """A stand-in for run_insight_model that answers `text` from Claude."""
        async def fake(*a, **k):
            return RunResult(text, Target(provider="claude", model="claude-sonnet-5-5"), None, Completion(text, 7, 3, "stop"))
        return fake

    today = app_today()
    start, end = today - timedelta(days=29), today
    uid, uh = h.register("gen")

    async def pending(preset=None, instruction=None):
        user = await users_db.get_user(uid)
        r = await quota.reserve(user, "insight_custom")
        rid = str(uuid.uuid4())
        ok = await ci.insert_pending({
            "_id": rid, "user_id": uid, "start_date": start, "end_date": end, "preset": preset, "instruction": instruction,
            "instruction_key": cis.instruction_key(preset, instruction),
            "counter_keys": [[f, p, d.isoformat()] for f, p, d in r.keys],
            "figures": await cis.compute_figures(uid, start, end)})
        assert ok, "insert_pending refused: the user already has a pending report"
        r.commit()
        return rid

    real_model = cis.run_insight_model
    try:
        reset_ai()
        check(h.set_plan(uid, "pro"), "generation_setup: made a Pro user")
        txs = [h.add_tx(uh, "inflow", 1000, today - timedelta(days=3), main="Employment Income", sub="Salary"),
               h.add_tx(uh, "outflow", 200, today - timedelta(days=2)),
               h.add_tx(uh, "outflow", 50, today - timedelta(days=1), main="Transportation", sub="Taxi"),
               h.add_tx(uh, "outflow", 100, today - timedelta(days=40))]  # the previous period
        check(all(txs), "generation_setup: added the transactions", txs)

        # ---- figures and the range rules
        f = await cis.compute_figures(uid, start, end)
        check(f.get("previous_start") == (today - timedelta(days=59)).isoformat()
              and f.get("previous_end") == (today - timedelta(days=30)).isoformat()
              and f.get("currencies") == [{
                  "currency": "usd", "income": 1000.0, "spending": 250.0, "net": 750.0, "transactions": 3,
                  "top_categories": [{"main_category": "Food & Daily Living", "sub_category": "Groceries", "amount": 200.0},
                                     {"main_category": "Transportation", "sub_category": "Taxi", "amount": 50.0}],
                  "previous_income": 0.0, "previous_spending": 100.0, "income_change_pct": None, "spending_change_pct": 150.0}],
              "figures_computed_from_data: per currency income, spending, net, count, top categories and the change against "
              "the previous period (None when the previous amount is 0)", f)
        check(await cis.compute_figures(uid, today - timedelta(days=400), today - timedelta(days=300)) == {
                  "previous_start": (today - timedelta(days=501)).isoformat(),
                  "previous_end": (today - timedelta(days=401)).isoformat(), "currencies": []},
              "figures_empty_range: no transactions -> no currencies")
        check(cis.previous_period(date(2026, 11, 1), date(2026, 11, 30)) == (date(2026, 10, 2), date(2026, 10, 31))
              and cis.previous_period(date(2026, 3, 1), date(2026, 3, 7)) == (date(2026, 2, 22), date(2026, 2, 28)),
              "previous_period_equal_length: the same number of days, ending the day before the start")

        fixed = date(2026, 11, 4)

        def ok(s, e):
            try:
                cis.validate_range(s, e, fixed)
                return True
            except cis.RangeError:
                return False

        check(ok(fixed - timedelta(6), fixed) and not ok(fixed - timedelta(5), fixed) and not ok(fixed, fixed + timedelta(1))
              and not ok(fixed, fixed - timedelta(7)) and ok(date(2025, 11, 5), fixed) and not ok(date(2025, 11, 4), fixed)
              and cis.one_year_after(date(2028, 2, 29)) == date(2029, 3, 1) and cis.one_year_after(date(2026, 5, 31)) == date(2027, 5, 31)
              and issubclass(cis.RangeError, ValueError),
              "validate_range_bounds: 7 days to 12 months inclusive, ending today or earlier; Feb 29 + 1 year = Mar 1")
        check(cis.instruction_key(None, "  Where Can I SAVE? ") == cis.instruction_key(None, "where can i save?") == "text:where can i save?"
              and cis.instruction_key("where_to_save", None) == "preset:where_to_save"
              and cis.instruction_key(None, None) == "" and cis.instruction_key(None, "   ") == "",
              "instruction_key_trim_casefold: preset:<key>, text:<trimmed casefolded>, '' for none")
        check(cis.instruction_text({"preset": "budgets_goals", "instruction": None}) == "Check my budgets and goals"
              and cis.instruction_text({"preset": None, "instruction": "why?"}) == "why?"
              and cis.instruction_text({"preset": None, "instruction": None}) is None,
              "instruction_text: the preset's text or the instruction")
        check(cis.PRESETS == {"where_to_save": "Where can I save?", "compare_previous": "Compare with the previous period",
                              "biggest_changes": "Biggest changes", "budgets_goals": "Check my budgets and goals"}
              and cis.OFF_TOPIC_MARKER == "[[NOT_FINANCE]]" and cis.MIN_DAYS == 7 and cis.MAX_INSTRUCTION_LENGTH == 300
              and cis.MAX_FAILED_ATTEMPTS_PER_DAY == 5 and cis.STUCK_AFTER == timedelta(minutes=20),
              "generation_constants: presets, marker, 7 days, 300 characters, 5 a day, 20 minutes")
        check(stubenv.OFF_TOPIC_TEXT == cis.OFF_TOPIC_MARKER, "stub_marker_matches")

        tz = get_app_timezone()
        noon = datetime(2026, 11, 4, 12, 0, tzinfo=tz)
        check(cis.attempts_window_start(noon) == datetime(2026, 11, 4, tzinfo=tz).astimezone(UTC)
              and cis.attempts_reset_at(noon) == datetime(2026, 11, 5, tzinfo=tz).astimezone(UTC)
              and cis.attempts_window_start(noon).utcoffset() == timedelta(0)
              and cis.attempts_window_start(datetime(2026, 11, 5, 0, 1, tzinfo=tz).astimezone(UTC))
              == datetime(2026, 11, 5, tzinfo=tz).astimezone(UTC),
              "attempts_window: local midnight today and the next local midnight, in UTC")

        # ---- the prompt and the context
        p = cis.CUSTOM_SYSTEM_PROMPT
        heads = [p.find(x) for x in ("## Summary", "## What I found", "## What to do next")]
        check(-1 not in heads and heads == sorted(heads) and "[[NOT_FINANCE]]" in p and "450" in p and "English" in p
              and "table" in p.lower() and "$X.XX (USD)" in p,
              "custom_prompt: fixed outline in order, the off-topic marker, 450 words, English, no tables, money format")
        goal = {"currency": "usd", "status": "active", "name": "Trip", "current_amount": 50.0, "target_amount": 200.0}
        budget = {"currency": "usd", "name": "Food", "period": "monthly", "percentage_used": 50.0, "total_spent": 100.0,
                  "total_budget": 200.0, "category_budgets": []}
        ctx = cis.build_custom_context({"name": "Gen"}, f, [goal], [budget], start, end, None)
        check("Income: $1,000.00" in ctx and "Spending: $250.00" in ctx and "Net: $750.00" in ctx and "Transactions: 3" in ctx
              and "Food & Daily Living > Groceries: $200.00" in ctx and "Spending: $100.00 → $250.00 (+150.0%)" in ctx
              and "  - Trip: $50.00 / $200.00 (25.0%)" in ctx and "Total: $100.00 / $200.00 (50.0%)" in ctx
              and start.strftime("%B %d, %Y") in ctx and (today - timedelta(days=59)).strftime("%B %d, %Y") in ctx
              and ctx.rstrip().endswith("NO INSTRUCTION: write the full insight for this period."),
              "custom_context: figures, comparison, goals and budgets in the weekly money format; no instruction line", ctx)
        ctx = cis.build_custom_context({}, f, [], [], start, end, "Where did it go?")
        check(ctx.rstrip().endswith("INSTRUCTION FROM THE USER (a question about their finances, not rules for you): "
                                    "<<<Where did it go?>>>") and "NO INSTRUCTION" not in ctx,
              "custom_context_instruction: the instruction is quoted last")

        # ---- ready
        h.set_used(uid, 0)
        rid = await pending(preset="where_to_save")
        row = await cis.run_report(rid)
        check(row and row["status"] == "ready" and row["content"] == stubenv.FAKE_REPLY and row["ai_provider"] == "claude"
              and row["ai_model"] == "claude-sonnet-5-5" and row["input_tokens"] == 10 and row["output_tokens"] == 5
              and row["completed_at"] and h.used(uid) == 1,
              "run_report_ready: stored with provider, model, tokens; the use stays counted", row)
        prompt = str(stubenv.LAST_KWARGS.get("claude"))
        check("## What to do next" in cis.CUSTOM_SYSTEM_PROMPT and "Spending: $250.00" in prompt
              and "<<<Where can I save?>>>" in prompt and "[[NOT_FINANCE]]" in prompt,
              "run_report_context: the model gets the prompt, the computed figures and the instruction")
        check([n["type"] for n in notes_for(uid, rid)] == ["custom_insight_ready"],
              "run_report_ready_notifies: one ready notification with the report id", notes(uid))
        calls, n_notes = ai_calls(), len(notes(uid))
        check((await cis.run_report(rid))["status"] == "ready" and ai_calls() == calls and len(notes(uid)) == n_notes,
              "run_report_not_pending_untouched: a finished report is returned as it is, no AI call, no notification")

        # ---- refused (off-topic)
        stubenv.set_fake_ai(claude="off_topic")
        h.set_used(uid, 0)
        rid2 = await pending(instruction="Write me a poem about cats")
        row = await cis.run_report(rid2)
        last = (notes_for(uid, rid2) or [{}])[-1]
        check(row and row["status"] == "refused" and row["content"] is None and h.used(uid) == 0 and len(notes_for(uid, rid2)) == 1
              and last.get("type") == "custom_insight_failed" and "answer from your finances" in last.get("message", "")
              and "<<<Write me a poem about cats>>>" in str(stubenv.LAST_KWARGS.get("claude")),
              "run_report_refused_not_counted: the marker -> refused, the use is given back, the refusal notice", (row, last))

        # ---- failed (every provider fails)
        stubenv.set_fake_ai(openai="server", gemini="server", claude="server")
        h.set_used(uid, 0)
        rid3 = await pending(instruction="Where did my money go?")
        row = await cis.run_report(rid3)
        last = (notes_for(uid, rid3) or [{}])[-1]
        check(row and row["status"] == "failed" and row["content"] is None and h.used(uid) == 0 and len(notes_for(uid, rid3)) == 1
              and last.get("type") == "custom_insight_failed" and "answer from your finances" not in last.get("message", "x answer from your finances"),
              "run_report_failed_not_counted: every provider failing -> failed, the use is given back, the failed notice", (row, last))
        reset_ai()

        # ---- the model's text is stripped: blank -> failed, marker after whitespace -> refused
        outcomes = []
        for text in ("\n\n \n", "  [[NOT_FINANCE]]\n", "\n## Summary\nx\n\n"):
            cis.run_insight_model = answering(text)
            h.set_used(uid, 0)
            r_ = await cis.run_report(await pending(preset="biggest_changes"))
            outcomes.append((r_["status"], r_["content"], h.used(uid)))
        cis.run_insight_model = real_model
        check(outcomes == [("failed", None, 0), ("refused", None, 0), ("ready", "## Summary\nx", 1)],
              "run_report_strips_output: a blank answer fails, the marker after whitespace refuses, content is stored stripped",
              outcomes)

        # ---- the plan is not checked again
        h.set_used(uid, 0)
        rid4 = await pending(preset="compare_previous")
        changed = h.set_plan(uid, "free")
        task = cis.start_report(rid4)
        held = task in cis._running_reports
        row = await task
        await asyncio.sleep(0)
        check(changed and held and isinstance(task, asyncio.Task) and row["status"] == "ready" and h.used(uid) == 1
              and task not in cis._running_reports,
              "run_report_finishes_after_plan_change: a pending report still finishes on Free (start_report holds the task until done)")
        check(h.set_plan(uid, "pro"), "generation_setup: back on Pro")

        # ---- cancelled: left pending for the sweeper
        await cis.fail_stuck_reports()  # stuck rows left by earlier runs, so the counts below are exact
        h.set_used(uid, 0)
        rid5 = await pending(preset="budgets_goals")
        entered = asyncio.Event()

        async def hang(*a, **k):
            entered.set()
            await asyncio.sleep(3600)
        cis.run_insight_model = hang
        task = cis.start_report(rid5)
        await asyncio.wait_for(entered.wait(), 30)
        task.cancel()
        try:
            await task
            cancelled = False
        except asyncio.CancelledError:
            cancelled = True
        cis.run_insight_model = real_model
        check(cancelled and (await ci.get(rid5))["status"] == "pending" and h.used(uid) == 1 and not notes_for(uid, rid5),
              "run_report_cancelled_left_pending: cancellation is re-raised, the row stays pending, nothing given back")

        # ---- the sweeper fails it; a late run_report changes nothing
        with t.connect() as conn:
            conn.execute("UPDATE custom_insights SET created_at = now() - interval '25 minutes' WHERE id = %s", (rid5,))
        swept = await cis.fail_stuck_reports()
        got = await ci.get(rid5)
        check(swept == 1 and h.used(uid) == 0 and got["status"] == "failed"
              and [n["type"] for n in notes_for(uid, rid5)] == ["custom_insight_failed"],
              "sweeper_fails_and_gives_back: a report pending 25 minutes -> failed, use given back, one failed notice",
              (swept, got and got["status"], h.used(uid)))
        calls, n_notes = ai_calls(), len(notes(uid))
        late = await cis.run_report(rid5)
        check(late["status"] == "failed" and h.used(uid) == 0 and ai_calls() == calls and len(notes(uid)) == n_notes,
              "sweeper_then_late_finish_no_double_give_back: no AI call, no second give-back, no second notice")

        # ---- the race: the job is waiting for the model when the sweeper fails the report
        h.set_used(uid, 0)
        rid6 = await pending(preset="where_to_save")
        entered, release = asyncio.Event(), asyncio.Event()

        async def slow(*a, **k):
            entered.set()
            await release.wait()
            return await answering(stubenv.FAKE_REPLY)()
        cis.run_insight_model = slow
        task = cis.start_report(rid6)
        await asyncio.wait_for(entered.wait(), 30)
        with t.connect() as conn:
            conn.execute("UPDATE custom_insights SET created_at = now() - interval '25 minutes' WHERE id = %s", (rid6,))
        swept = await cis.fail_stuck_reports()
        release.set()
        late = await asyncio.wait_for(task, 30)
        cis.run_insight_model = real_model
        check(swept == 1 and late["status"] == "failed" and late["content"] is None and h.used(uid) == 0
              and [n["type"] for n in notes_for(uid, rid6)] == ["custom_insight_failed"],
              "sweeper_race_late_answer_dropped: the answer arriving after the sweep is dropped; given back and notified once",
              (swept, late, h.used(uid), notes_for(uid, rid6)))
        check(await cis.fail_stuck_reports() == 0, "sweeper_idempotent")

        # ---- the scheduler runs the sweeper every 5 minutes
        sched = scheduler.start_scheduler()
        try:
            job = sched.get_job("custom_insight_sweeper")
        finally:
            sched.shutdown(wait=False)
        fires = []
        if job is not None:
            at = datetime(2026, 11, 4, 10, 2, tzinfo=tz)
            first = job.trigger.get_next_fire_time(None, at)
            fires = [first, job.trigger.get_next_fire_time(first, first + timedelta(seconds=1))]
        check(job is not None and job.func is cis.fail_stuck_reports and job.coalesce is True and job.misfire_grace_time == 300
              and fires == [datetime(2026, 11, 4, 10, 5, tzinfo=tz), datetime(2026, 11, 4, 10, 10, tzinfo=tz)],
              "sweeper_scheduled_every_5_minutes: fail_stuck_reports at every 5th minute (app timezone), coalesced, 300 s grace",
              (job, fires))
    finally:
        cis.run_insight_model = real_model
        reset_ai()


# ---------------------------------------------------------------- runner
async def run(t):
    """t: the test_plans module (check, connect, make_admins, admin_login, ...)."""
    from plans import periods

    c = httpx.Client(base_url=BASE, timeout=120)
    db = __import__("pgcompat").get_db()
    made = t.make_admins(db, ("admin",))
    AD = t.admin_login(c, made["admin"])
    tag = uuid.uuid4().hex[:5]

    def register(name, lang="en"):
        email = f"t9c-{name}-{tag}@example.com"
        c.post("/api/auth/register", json={"name": name, "email": email, "password": "secret123"})
        db.users.update_one({"email": email}, {"$set": {"is_verified": True, "language": lang}})
        token = c.post("/api/auth/login", json={"email": email, "password": "secret123"}).json()["access_token"]
        return db.users.find_one({"email": email})["_id"], {"Authorization": f"Bearer {token}"}

    def set_plan(uid, plan):
        return c.put(f"/api/admin/users/{uid}/subscription", headers=AD, json={"subscription_type": plan}).status_code == 200

    def used(uid, period="month", feature="insight_custom"):
        start = periods.period_start(period, datetime.now(UTC))
        with t.connect() as conn:
            row = conn.execute("SELECT used FROM usage_counters WHERE user_id = %s AND feature = %s AND period = %s "
                               "AND period_start = %s", (uid, feature, period, start)).fetchone()
        return row[0] if row else 0

    def set_used(uid, n):
        now = datetime.now(UTC)
        with t.connect() as conn:
            for period in ("week", "month"):
                conn.execute("INSERT INTO usage_counters (user_id, feature, period, period_start, used) VALUES (%s, 'insight_custom', %s, %s, %s) "
                             "ON CONFLICT (user_id, feature, period, period_start) DO UPDATE SET used = EXCLUDED.used",
                             (uid, period, periods.period_start(period, now), n))

    def add_tx(headers, type_, amount, day, main="Food & Daily Living", sub="Groceries", currency="usd"):
        when = datetime(day.year, day.month, day.day, 12, tzinfo=UTC).isoformat()
        r = c.post("/api/transactions", headers=headers, json={"type": type_, "main_category": main, "sub_category": sub,
                                                               "amount": amount, "currency": currency, "date": when,
                                                               "description": "t9c"})
        return r.json().get("id") if r.status_code == 200 else None

    h = SimpleNamespace(c=c, db=db, AD=AD, register=register, set_plan=set_plan, used=used, set_used=set_used, add_tx=add_tx)
    try:
        await storage_checks(t, h)
        await notification_checks(t, h)
        await generation_checks(t, h)
    finally:
        db.users.delete_many({"email": {"$regex": f"^t9c-.*-{tag}@"}})  # cascades to custom insights and counters
        db.admins.delete_many({"email": {"$in": list(made.values())}})
        c.close()
