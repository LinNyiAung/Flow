"""Invoke each scheduler job directly against the E2E database and check its effects."""
import asyncio
import contextlib
import io
import json
import os
import sys
import uuid
import warnings
from datetime import datetime, timedelta, UTC

# The insight checks need an AI that answers: the stubenv fakes (as in the full suite, which sets this too).
os.environ.setdefault("E2E_FAKE_AI", "1")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402

os.chdir(stubenv.BACKEND)
warnings.simplefilter("always", RuntimeWarning)

import notification_service as ns  # noqa: E402
import insights_service as ins  # noqa: E402
B = __import__("pgcompat").async_collection("budgets")  # budgets live in PostgreSQL
from tz_utils import default_zone  # noqa: E402  (A has no saved zone)
from utils import get_book_balance  # noqa: E402
T = __import__("pgcompat").async_collection("transactions")  # transactions live in PostgreSQL
I = __import__("pgcompat").async_collection("insights")  # insights live in PostgreSQL
G = __import__("pgcompat").async_collection("goals")  # goals live in PostgreSQL
N = __import__("pgcompat").async_collection("notifications")  # notifications live in PostgreSQL
U = __import__("pgcompat").async_collection("users")  # users live in PostgreSQL

stubenv.patch_loaded_modules()

HERE = os.path.dirname(os.path.abspath(__file__))
state = json.load(open(os.path.join(HERE, "api_results.json")))["state"]
A = state["A_id"]
# A's personal book: the jobs and helpers that take a book are called with it (notifications stay keyed by A).
BOOK_A = __import__("pgcompat").get_db().sql("SELECT id FROM books WHERE person_id = %s", A)[0]["id"]
RESULTS = []


def rec(name, status, detail=""):
    RESULTS.append(("Scheduler jobs", name, status, str(detail)[:700]))
    print(f"[{status}] {name}" + (f" -- {str(detail)[:400]}" if detail else ""))


async def run_job(label, coro_fn, *args):
    buf = io.StringIO()
    exc = None
    with warnings.catch_warnings(record=True) as w, contextlib.redirect_stdout(buf):
        warnings.simplefilter("always")
        try:
            await coro_fn(*args)
        except Exception as e:  # noqa: BLE001
            exc = e
    out = buf.getvalue()
    never_awaited = [str(x.message) for x in w if "never awaited" in str(x.message)]
    return exc, out, never_awaited


async def budget_period_jobs():
    """The daily budget notices: A's "ending soon" reminders and the "now active" check of A's book."""
    await stubenv.run_local_job("budget_ending_reminders", A)
    await stubenv.run_local_job("budget_now_active", BOOK_A)


def errlines(out, pats=("Error", "error", "Traceback", "Critical", "TypeError", "can't", "not iterable")):
    return [l for l in out.splitlines() if any(p in l for p in pats)][:6]


async def main():
    now = datetime.now(UTC)

    # ---------------- recurring transactions
    parent = await T.find_one({"_id": state["rec_parent"]})
    before_children = await T.count_documents({"parent_transaction_id": state["rec_parent"]})
    currency = parent.get("currency", "usd")
    outflow_before = (await get_book_balance(BOOK_A, currency))["total_outflow"]
    exc, out, na = await run_job("recurring", stubenv.run_local_job, "recurring_transactions", BOOK_A)
    after_children = await T.count_documents({"parent_transaction_id": state["rec_parent"]})
    rec("recurring job ran without exception", "PASS" if exc is None else "FAIL", repr(exc) if exc else "")
    rec("daily recurrence started 3 days ago: occurrences created in one run", "INFO",
        f"{after_children - before_children} created (3 are due: days -2, -1, today)")
    if after_children - before_children < 3:
        rec("daily recurrence catches up at most 1 occurrence per run (stays behind permanently)", "BUG",
            f"created {after_children - before_children} of 3 due")
    outflow_after = (await get_book_balance(BOOK_A, currency))["total_outflow"]
    expected = (after_children - before_children) * parent["amount"] * (1 if parent["type"] == "outflow" else 0)
    if parent["type"] == "outflow" and abs(outflow_after - outflow_before - expected) > 0.005:
        rec("auto-created recurring tx not reflected in the dashboard balance", "BUG",
            f"outflow {outflow_before} -> {outflow_after}, expected +{expected}")
    else:
        rec("balance reflects the auto-created recurring transactions", "PASS")

    exc, out, na = await run_job("recurring-2", stubenv.run_local_job, "recurring_transactions", BOOK_A)
    again = await T.count_documents({"parent_transaction_id": state["rec_parent"]})
    rec("second run same day is idempotent-ish", "INFO", f"total children now {again}")

    # malformed recurrence row (last_created_date: null) placed before a healthy one
    bad_id, good_id = "bad-" + uuid.uuid4().hex[:6], "zzz-" + uuid.uuid4().hex[:6]
    base = {k: v for k, v in parent.items() if k != "_id"}
    await T.insert_one({**base, "_id": bad_id, "created_at": now - timedelta(days=30),
                        "recurrence": {"enabled": True, "config": {"frequency": "daily"}, "last_created_date": None}})
    await T.insert_one({**base, "_id": good_id, "date": now - timedelta(days=2), "created_at": now - timedelta(days=29),
                        "recurrence": {"enabled": True, "config": {"frequency": "daily"}, "last_created_date": now - timedelta(days=2)}})
    exc, out, na = await run_job("recurring-bad", stubenv.run_local_job, "recurring_transactions", BOOK_A)
    good_children = await T.count_documents({"parent_transaction_id": good_id})
    if exc is not None or good_children == 0:
        rec("one recurrence with last_created_date=null aborts the whole job (the book's other recurrences skipped)", "BUG",
            f"exception={exc!r}; healthy recurrence children={good_children}; {errlines(out)}")
    else:
        rec("job survives a malformed recurrence row", "PASS")
    # Children first: deleting a parent clears its children's link (ON DELETE SET NULL).
    await T.delete_many({"parent_transaction_id": {"$in": [bad_id, good_id]}})
    await T.delete_many({"_id": {"$in": [bad_id, good_id]}})

    # ---------------- goal target dates
    await G.update_one({"_id": state["goal_id"]}, {"$set": {"target_date": now + timedelta(days=7), "status": "active"}})
    n0 = await N.count_documents({"user_id": A})
    exc, out, na = await run_job("targets", stubenv.run_local_job, "goal_deadline_reminders", A)
    n1 = await N.count_documents({"user_id": A})
    if exc is not None:
        rec("the goal deadline reminders job crashes (goal deadline reminders never sent)", "BUG", repr(exc))
    else:
        rec("goal 7-days-left reminder created", "PASS" if n1 > n0 else "FAIL", "" if n1 > n0 else f"no notification; {errlines(out)}")

    # ---------------- budget periods
    bid = "e2e-ending-" + uuid.uuid4().hex[:6]
    await B.insert_one({"_id": bid, "user_id": A, "name": "Ending soon", "period": "custom", "currency": "usd",
                        "start_date": now - timedelta(days=10), "end_date": now + timedelta(days=2, hours=12),
                        "category_budgets": [{"main_category": "Transportation", "allocated_amount": 10, "spent_amount": 0,
                                              "percentage_used": 0, "is_exceeded": False}],
                        "total_budget": 10, "total_spent": 0, "remaining_budget": 10, "percentage_used": 0,
                        "status": "active", "is_active": True, "created_at": now, "updated_at": now})
    uid = "e2e-upcoming-" + uuid.uuid4().hex[:6]
    await B.insert_one({"_id": uid, "user_id": A, "name": "Starts today", "period": "custom", "currency": "usd",
                        "start_date": now - timedelta(hours=1), "end_date": now + timedelta(days=20),
                        "category_budgets": [], "total_budget": 10, "total_spent": 0, "remaining_budget": 10, "percentage_used": 0,
                        "status": "upcoming", "is_active": False, "created_at": now, "updated_at": now})
    n0 = await N.count_documents({"user_id": A})
    exc, out, na = await run_job("budgets", budget_period_jobs)
    n1 = await N.count_documents({"user_id": A})
    if exc is not None:
        rec("the budget ending / now active jobs crash (ending-soon & now-active notifications never sent)", "BUG", repr(exc))
    else:
        rec("budget period job produced notifications", "PASS" if n1 > n0 else "BUG", "" if n1 > n0 else f"0 notifications for budget ending in 2.5 days and one that just started; {errlines(out)}")
    await B.delete_many({"_id": {"$in": [bid, uid]}})

    # ---------------- recurring payment detection
    for m in (1, 2, 3):
        await T.insert_one({"_id": f"netflix-{m}", "user_id": A, "type": "outflow", "main_category": "Entertainment & Leisure",
                            "sub_category": "Subscriptions", "description": "Netflix", "amount": 15.99, "currency": "usd",
                            "date": now - timedelta(days=30 * m - 2), "created_at": now, "updated_at": now})
    await T.insert_one({"_id": "nodesc", "user_id": A, "type": "outflow", "main_category": "Entertainment & Leisure",
                        "sub_category": "Subscriptions", "description": None, "amount": 1, "currency": "usd",
                        "date": now - timedelta(days=5), "created_at": now, "updated_at": now})
    exc, out, na = await run_job("payments", stubenv.run_local_job, "payment_reminders", A)
    if exc is not None:
        rec("the payment reminders job crashes", "BUG", f"{exc!r}")
    else:
        rec("recurring payment detection job", "INFO", f"ran; {errlines(out)}")
    await T.delete_many({"_id": {"$in": ["netflix-1", "netflix-2", "netflix-3", "nodesc"]}})

    # ---------------- unusual spending
    exc, out, na = await run_job("unusual", ns.analyze_unusual_spending, BOOK_A)
    rec("analyze_unusual_spending", "PASS" if exc is None else "FAIL", repr(exc) if exc else "")

    # ---------------- weekly insights for all users (trial user A has expiry)
    # A's book may already have this period's insights (made on demand by test_api), and the scheduled job skips a
    # book that has its period's insight (insights_service._has_period_insight): start without them.
    __import__("pgcompat").get_db().sql("DELETE FROM insights WHERE book_id = %s", BOOK_A)
    exc, out, na = await run_job("weekly-all", stubenv.run_local_job, "weekly_insights", BOOK_A)
    ai_calls = [l for l in open(stubenv.OUTBOX, encoding="utf-8") if '"ai_call"' in l] if os.path.exists(stubenv.OUTBOX) else []
    tz_err = [l for l in out.splitlines() if "offset-naive" in l or "can't compare" in l]
    if tz_err:
        rec("weekly insight job skips premium users with an expiry date (naive/aware compare)", "BUG", tz_err[:2])
    else:
        rec("weekly insight job reached premium users", "PASS", errlines(out))
    exc, out, na = await run_job("monthly-all", stubenv.run_local_job, "monthly_insights", BOOK_A)
    tz_err = [l for l in out.splitlines() if "offset-naive" in l or "can't compare" in l]
    if tz_err:
        rec("monthly insight job skips premium users with an expiry date (naive/aware compare)", "BUG", tz_err[:2])

    # ---------------- from here on: an AI that answers, to exercise post-AI code paths. Insights run on the
    # provider runner, whose clients use the stubenv fakes (the suite runs with E2E_FAKE_AI=1).

    # ---------------- monthly insight directly (missing await claim)
    # One insight per user on the insight_monthly provider chain (no provider argument any more).
    exc, out, na = await run_job("monthly-one", lambda: ins.generate_monthly_insight(BOOK_A, tz=default_zone()))
    mi = await I.count_documents({"user_id": A, "insight_type": "monthly"})
    rec("monthly insight saved with a working AI", "PASS" if mi else "BUG", "" if mi else "no monthly insight document created even though AI answered")
    coroutine_err = [l for l in out.splitlines() if "coroutine" in l]
    if coroutine_err or any("get_user_goals" in x or "get_user_budgets" in x for x in na):
        rec("generate_monthly_insight uses un-awaited coroutines (goals/budgets) and fails", "BUG", (coroutine_err + na)[:3])
    else:
        rec("generate_monthly_insight", "INFO", f"exc={exc!r}; {errlines(out)}; never-awaited={na}")

    # ---------------- un-awaited notify in weekly insight path
    n0 = await N.count_documents({"user_id": A})
    exc, out, na = await run_job("weekly-one", lambda: ins.generate_weekly_insight(BOOK_A, tz=default_zone()))
    await asyncio.sleep(0.5)
    n1 = await N.count_documents({"user_id": A})
    wi = await I.count_documents({"user_id": A, "insight_type": "weekly", "is_placeholder": False})
    rec("weekly insight saved with a working AI", "PASS" if wi else "FAIL", f"exc={exc!r}; {errlines(out)[:3]}")
    has_insight_note = await N.count_documents({"user_id": A, "type": {"$regex": "insight"}})
    if wi and n1 == n0 and not has_insight_note:
        rec("'weekly insights ready' notification never created (async notify called without await)", "BUG",
            f"never-awaited warnings: {na[:2]}")
    elif wi:
        rec("'insights ready' notification created", "PASS")


asyncio.run(main())
res_path = os.path.join(HERE, "api_results.json")
data = json.load(open(res_path))
data["results"] += RESULTS
json.dump(data, open(res_path, "w"), indent=1, default=str)
