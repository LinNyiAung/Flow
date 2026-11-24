"""AI correctness e2e (docs/ai-audit-2026-11-24.md, group 1: our code gave the model wrong or missing figures). One
function per section, called from main() (or only the sections named on the command line). No real AI call: the
checks read what the backend hands the model, in-process against the test database (people are made over HTTP, so
the stub server on 127.0.0.1:8765 must run).

Sections:
  chat -- a book whose only rows in a currency are transfers still builds its chat data (the summary's period line
    was None[:10]); the chat prompt has this week / this month / last month income and spending computed by code,
    with the top spending categories, and the all-time and recent-window totals say which they are.
"""
import asyncio
import os
import sys
import uuid
from datetime import date, datetime, timedelta

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


def _one(sql, *params):
    rows = db.sql(sql, *params)
    return rows[0] if rows else {}


def _backend_async(coro_fn):
    """Run backend async code in-process (its DB engine binds to the loop: one asyncio.run per call, a fresh engine)."""
    async def go():
        from sql import db as sqldb
        try:
            return await coro_fn()
        finally:
            await sqldb.dispose_engine()
    return asyncio.run(go())


def _client():
    import httpx
    return httpx.Client(base_url=BASE, timeout=60)


def _person(c, made, label, plan="free"):
    """A verified account (id, email, book: their personal book, h: the auth header), on `plan`; no saved zone (the
    default zone, Asia/Yangon)."""
    tag = uuid.uuid4().hex[:8]
    email = f"aic-{label.lower()}-{tag}@example.com"
    c.post("/api/auth/register", json={"name": label, "email": email, "password": "secret123"})
    db.sql("UPDATE users SET is_verified = true WHERE lower(email) = %s", email)
    uid = _one("SELECT id FROM users WHERE lower(email) = %s", email).get("id")
    made.append(uid)
    if plan != "free":
        db.sql("UPDATE users SET subscription_type = %s, subscription_expires_at = now() + interval '30 days', "
               "trial_ends_at = NULL WHERE id = %s", plan, uid)
    r = c.post("/api/auth/login", json={"email": email, "password": "secret123"})
    return {"id": uid, "email": email, "book": _one("SELECT id FROM books WHERE person_id = %s", uid).get("id"),
            "h": {"Authorization": f"Bearer {r.json().get('access_token')}"}}


def _entry(c, p, when, amount, type_="outflow", currency="mmk", main="Food & Daily Living", sub="Groceries"):
    r = c.post("/api/transactions", headers=p["h"], json={
        "type": type_, "main_category": main, "sub_category": sub, "amount": amount, "currency": currency,
        "date": f"{when.isoformat()}T12:00:00", "description": f"{sub} {amount}"})
    check(r.status_code in (200, 201), f"setup: {type_} {amount} {currency} on {when}", f"{r.status_code} {r.text[:200]}")


def _cleanup(made):
    made = [m for m in made if m]
    if made:
        db.sql("DELETE FROM families WHERE id IN (SELECT family_id FROM family_members WHERE user_id = ANY(%s))", made)
        db.sql("DELETE FROM users WHERE id = ANY(%s)", made)


def _today():
    from tz_utils import default_zone, local_today
    return local_today(default_zone())


# ------------------------------------------------------------------------------------------------------------ chat
def section_chat():
    c, made = _client(), []
    try:
        p = _person(c, made, "Chat")
        today = _today()
        last_month_mid = (today.replace(day=1) - timedelta(days=1)).replace(day=15)
        _entry(c, p, today, 12000)
        _entry(c, p, today, 500000, type_="inflow", main="Employment Income", sub="Salary")
        _entry(c, p, last_month_mid, 30000, sub="Restaurants")
        _entry(c, p, today - timedelta(days=200), 99000)
        # THB: only the leg of a transfer (as a move between the personal and the family wallet leaves)
        db.sql("INSERT INTO transactions (id, book_id, type, main_category, sub_category, amount, currency, date, "
               "transfer_id) VALUES (%s, %s, 'inflow', 'Transfers', 'Transfer', 50, 'thb', %s, %s)",
               str(uuid.uuid4()), p["book"], datetime.combine(today, datetime.min.time()), str(uuid.uuid4()))

        async def build():
            from ai_chatbot import FinancialDataProcessor, financial_chatbot
            from tz_utils import default_zone
            proc = FinancialDataProcessor(p["book"], default_zone())
            try:
                docs = await proc.create_financial_documents()
            except Exception as e:  # noqa: BLE001
                return repr(e), "", ""
            summary, goals, periods = await proc.get_financial_summary(), await proc.get_user_goals(), None
            if hasattr(proc, "get_period_totals"):
                periods = await proc.get_period_totals()
            prompt = financial_chatbot._build_user_prompt(
                {"name": "Chat", "language": "en", "default_currency": "mmk"}, summary,
                {"goals_by_currency": {}} if not goals else None, None, "", "", "How much did I spend this month?",
                "today", period_totals=periods) if periods is not None else ""
            return None, "\n".join(d.page_content for d in docs), prompt
        err, docs, prompt = _backend_async(build)
        check(err is None, "chat: a book with only transfer rows in a currency (THB) still builds its chat data", err)
        thb = docs[docs.find("THB SUMMARY"):][:400] if "THB SUMMARY" in docs else ""
        check("No income or spending entries" in thb,
              "chat: the THB summary says it has no income or spending entries instead of a broken period", thb or docs[:900])

        def section(label):
            """The period block that starts at `label` (up to the next period's line)."""
            start = prompt.find(label)
            if start < 0:
                return ""
            ends = [i for i in (prompt.find(x, start + 1) for x in ("This week so far", "This month so far", "Last month"))
                    if i > start]
            return prompt[start:min(ends) if ends else start + 600]
        month = section("This month so far")
        check("income K500,000 (MMK)" in month and "spending K12,000 (MMK)" in month,
              "chat: the prompt gives this month's income K500,000 and spending K12,000, computed by code", prompt[:1500])
        check("Food & Daily Living > Groceries K12,000 (MMK)" in month,
              "chat: ... with this month's top spending category", month)
        last = section("Last month")
        check("spending K30,000 (MMK)" in last and "Restaurants K30,000 (MMK)" in last,
              "chat: the prompt gives last month's spending K30,000 (Restaurants)", last)
        week = section("This week so far")
        check("spending K12,000 (MMK)" in week, "chat: the prompt gives this week's spending K12,000", week)
        check("Income (all time)" in prompt and "Expenses (all time)" in prompt and "\n  📉 Expenses:" not in prompt,
              "chat: the overview's income and expenses say they are all-time totals", prompt[:1200])
        check("Total Income (all time)" in docs and "Total Expenses (all time)" in docs,
              "chat: the summary document's totals say they are all-time", docs[:1200])
        check("Category:" in docs and "\nTotal:" not in docs and "Total since " in docs,
              "chat: each category's total says from which date it counts", docs[-1500:])
    finally:
        _cleanup(made)


SECTIONS = {"chat": section_chat}


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
