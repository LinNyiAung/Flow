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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402

os.chdir(stubenv.BACKEND)
warnings.simplefilter("always", RuntimeWarning)

import recurring_transaction_service as rts  # noqa: E402
import notification_service as ns  # noqa: E402
import insights_service as ins  # noqa: E402
from database import (transactions_collection as T,  # noqa: E402
                      budgets_collection as B)
I = __import__("pgcompat").async_collection("insights")  # insights live in PostgreSQL
G = __import__("pgcompat").async_collection("goals")  # goals live in PostgreSQL
N = __import__("pgcompat").async_collection("notifications")  # notifications live in PostgreSQL
U = __import__("pgcompat").async_collection("users")  # users live in PostgreSQL

stubenv.patch_loaded_modules()

HERE = os.path.dirname(os.path.abspath(__file__))
state = json.load(open(os.path.join(HERE, "api_results.json")))["state"]
A = state["A_id"]
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


def errlines(out, pats=("Error", "error", "Traceback", "Critical", "TypeError", "can't", "not iterable")):
    return [l for l in out.splitlines() if any(p in l for p in pats)][:6]


async def main():
    now = datetime.now(UTC)

    # ---------------- recurring transactions
    parent = await T.find_one({"_id": state["rec_parent"]})
    before_children = await T.count_documents({"recurrence.parent_transaction_id": state["rec_parent"]})
    cached_before = (await U.find_one({"_id": A})).get("balances")
    exc, out, na = await run_job("recurring", rts.check_and_create_recurring_transactions)
    after_children = await T.count_documents({"recurrence.parent_transaction_id": state["rec_parent"]})
    if after_children == before_children:
        after_children = await T.count_documents({"parent_transaction_id": state["rec_parent"]})
    rec("recurring job ran without exception", "PASS" if exc is None else "FAIL", repr(exc) if exc else "")
    rec("daily recurrence started 3 days ago: occurrences created in one run", "INFO",
        f"{after_children - before_children} created (3 are due: days -2, -1, today)")
    if after_children - before_children < 3:
        rec("daily recurrence catches up at most 1 occurrence per run (stays behind permanently)", "BUG",
            f"created {after_children - before_children} of 3 due")
    cached_after = (await U.find_one({"_id": A})).get("balances")
    if cached_before and cached_after == cached_before and after_children > before_children:
        rec("auto-created recurring tx not reflected in cached dashboard balance", "BUG",
            f"cached usd balance still {cached_after.get('usd', {}).get('balance')}")
    else:
        rec("balance cache invalidated after recurring creation", "PASS")

    exc, out, na = await run_job("recurring-2", rts.check_and_create_recurring_transactions)
    again = await T.count_documents({"$or": [{"recurrence.parent_transaction_id": state["rec_parent"]}, {"parent_transaction_id": state["rec_parent"]}]})
    rec("second run same day is idempotent-ish", "INFO", f"total children now {again}")

    # malformed recurrence row (last_created_date: null) placed before a healthy one
    bad_id, good_id = "bad-" + uuid.uuid4().hex[:6], "zzz-" + uuid.uuid4().hex[:6]
    base = {k: v for k, v in parent.items() if k != "_id"}
    await T.insert_one({**base, "_id": bad_id, "created_at": now - timedelta(days=30),
                        "recurrence": {"enabled": True, "config": {"frequency": "daily"}, "last_created_date": None}})
    await T.insert_one({**base, "_id": good_id, "date": now - timedelta(days=2), "created_at": now - timedelta(days=29),
                        "recurrence": {"enabled": True, "config": {"frequency": "daily"}, "last_created_date": now - timedelta(days=2)}})
    exc, out, na = await run_job("recurring-bad", rts.check_and_create_recurring_transactions)
    good_children = await T.count_documents({"$or": [{"recurrence.parent_transaction_id": good_id}, {"parent_transaction_id": good_id}]})
    if exc is not None or good_children == 0:
        rec("one recurrence with last_created_date=null aborts the whole job (other users' recurrences skipped)", "BUG",
            f"exception={exc!r}; healthy recurrence children={good_children}; {errlines(out)}")
    else:
        rec("job survives a malformed recurrence row", "PASS")
    await T.delete_many({"_id": {"$in": [bad_id, good_id]}})
    await T.delete_many({"$or": [{"recurrence.parent_transaction_id": {"$in": [bad_id, good_id]}}, {"parent_transaction_id": {"$in": [bad_id, good_id]}}]})

    # ---------------- goal target dates
    await G.update_one({"_id": state["goal_id"]}, {"$set": {"target_date": now + timedelta(days=7), "status": "active"}})
    n0 = await N.count_documents({"user_id": A})
    exc, out, na = await run_job("targets", ns.check_approaching_target_dates)
    n1 = await N.count_documents({"user_id": A})
    if exc is not None:
        rec("check_approaching_target_dates crashes (goal deadline reminders never sent)", "BUG", repr(exc))
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
    exc, out, na = await run_job("budgets", ns.check_budget_period_notifications)
    n1 = await N.count_documents({"user_id": A})
    if exc is not None:
        rec("check_budget_period_notifications crashes (ending-soon & now-active notifications never sent)", "BUG", repr(exc))
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
    exc, out, na = await run_job("payments", ns.detect_and_notify_recurring_payments)
    if exc is not None:
        rec("detect_and_notify_recurring_payments crashes", "BUG", f"{exc!r}")
    else:
        rec("recurring payment detection job", "INFO", f"ran; {errlines(out)}")
    await T.delete_many({"_id": {"$in": ["netflix-1", "netflix-2", "netflix-3", "nodesc"]}})

    # ---------------- unusual spending
    exc, out, na = await run_job("unusual", ns.analyze_unusual_spending, A)
    rec("analyze_unusual_spending", "PASS" if exc is None else "FAIL", repr(exc) if exc else "")

    # ---------------- weekly insights for all users (trial user A has expiry)
    exc, out, na = await run_job("weekly-all", ins.generate_weekly_insights_for_all_users)
    ai_calls = [l for l in open(stubenv.OUTBOX, encoding="utf-8") if '"ai_call"' in l] if os.path.exists(stubenv.OUTBOX) else []
    tz_err = [l for l in out.splitlines() if "offset-naive" in l or "can't compare" in l]
    if tz_err:
        rec("weekly insight job skips premium users with an expiry date (naive/aware compare)", "BUG", tz_err[:2])
    else:
        rec("weekly insight job reached premium users", "PASS", errlines(out))
    exc, out, na = await run_job("monthly-all", ins.generate_monthly_insights_for_all_users)
    tz_err = [l for l in out.splitlines() if "offset-naive" in l or "can't compare" in l]
    if tz_err:
        rec("monthly insight job skips premium users with an expiry date (naive/aware compare)", "BUG", tz_err[:2])

    # ---------------- from here on: fake OpenAI that answers, to exercise post-AI code paths
    import openai
    from types import SimpleNamespace as NS

    class FakeCompletions:
        async def create(self, *a, **k):
            return NS(choices=[NS(message=NS(content="## Fake insight\nYou spent money."), finish_reason="stop")],
                      usage=NS(prompt_tokens=10, completion_tokens=5, total_tokens=15))

    class FakeAsyncOpenAI:
        def __init__(self, *a, **k):
            self.chat = NS(completions=FakeCompletions())

    openai.AsyncOpenAI = FakeAsyncOpenAI

    # ---------------- monthly insight directly (missing await claim)
    exc, out, na = await run_job("monthly-one", ins.generate_monthly_insight, A, "openai")
    mi = await I.count_documents({"user_id": A, "insight_type": "monthly"})
    rec("monthly insight saved with a working AI", "PASS" if mi else "BUG", "" if mi else "no monthly insight document created even though AI answered")
    coroutine_err = [l for l in out.splitlines() if "coroutine" in l]
    if coroutine_err or any("get_user_goals" in x or "get_user_budgets" in x for x in na):
        rec("generate_monthly_insight uses un-awaited coroutines (goals/budgets) and fails", "BUG", (coroutine_err + na)[:3])
    else:
        rec("generate_monthly_insight", "INFO", f"exc={exc!r}; {errlines(out)}; never-awaited={na}")

    # ---------------- un-awaited notify in weekly insight path
    n0 = await N.count_documents({"user_id": A})
    exc, out, na = await run_job("weekly-one", ins.generate_weekly_insight, A, "openai")
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
