"""Add realistic sample transactions to one account through the public API.

Run it yourself; it asks for the account's email and password in this
terminal (or reads MOCK_ACCESS_TOKEN) and shows a summary before it writes.

    python generate_mock_data.py --api-url https://your-backend.example.com
    python generate_mock_data.py --api-url ... --months 3 --dry-run
"""
import argparse
import getpass
import os
import random
import sys
import time
from datetime import datetime, timedelta, timezone

import requests

YANGON = timezone(timedelta(hours=6, minutes=30))

# Amounts are in kyat; other currencies are converted with these rough rates.
MMK_PER_UNIT = {"mmk": 1, "usd": 4200, "thb": 120}

# Things that happen once a month: (type, main, sub, description, day of month, (min, max) MMK, chance)
MONTHLY = [
    ("inflow", "Employment Income", "Salary", "Monthly salary", 1, None, 1.0),
    ("outflow", "Housing & Utilities", "Rent", "Apartment rent", 3, None, 1.0),
    ("outflow", "Housing & Utilities", "Internet", "Home internet bill", 5, (35000, 35000), 1.0),
    ("outflow", "Housing & Utilities", "Electricity", "Electricity bill", 8, (25000, 65000), 1.0),
    ("outflow", "Housing & Utilities", "Water", "Water bill", 8, (4000, 9000), 1.0),
    ("outflow", "Entertainment & Leisure", "Subscriptions", "Netflix subscription", 12, (15000, 15000), 1.0),
    ("outflow", "Health & Insurance", "Fitness & Gym", "Gym membership", 2, (50000, 50000), 1.0),
    ("inflow", "Self-Employment & Business", "Freelance Income", "Freelance design project", 18, (150000, 500000), 0.6),
    ("inflow", "Gifts & Support", "Family Support", "Money from family", 20, (50000, 150000), 0.25),
    ("outflow", "Financial Expenses", "Bank Fees", "Bank service charge", 28, (1000, 3000), 1.0),
]

# Everyday things: (type, main, sub, descriptions, times per month (min, max), (min, max) MMK)
EVERYDAY = [
    ("outflow", "Food & Daily Living", "Groceries", ["Groceries at City Mart", "Groceries at Ocean", "Market shopping", "Weekly groceries"], (4, 5), (35000, 90000)),
    ("outflow", "Food & Daily Living", "Restaurants", ["Dinner with friends", "Lunch at restaurant", "Hot pot dinner", "Family dinner"], (3, 6), (15000, 45000)),
    ("outflow", "Food & Daily Living", "Fast Food", ["KFC", "Lotteria", "Burger lunch", "Noodle shop lunch"], (3, 5), (6000, 18000)),
    ("outflow", "Food & Daily Living", "Coffee & Snacks", ["Coffee", "Bubble tea", "Tea shop", "Snacks"], (8, 14), (2500, 7000)),
    ("outflow", "Transportation", "Taxi", ["Grab ride", "Taxi home", "Taxi to office"], (5, 10), (4000, 15000)),
    ("outflow", "Transportation", "Public Transport", ["YBS bus fare", "Bus fare"], (6, 12), (300, 1000)),
    ("outflow", "Housing & Utilities", "Mobile Phone", ["Phone top-up", "Mobile data pack"], (2, 3), (5000, 15000)),
    ("outflow", "Shopping & Lifestyle", "Home Supplies", ["Household supplies", "Cleaning supplies", "Toiletries"], (1, 2), (8000, 35000)),
    ("outflow", "Shopping & Lifestyle", "Clothing", ["New shirt", "Clothes shopping", "Longyi"], (0, 2), (25000, 120000)),
    ("outflow", "Health & Insurance", "Pharmacy", ["Pharmacy", "Vitamins", "Cold medicine"], (0, 2), (4000, 25000)),
    ("outflow", "Entertainment & Leisure", "Movies & Streaming", ["Cinema tickets", "Movie night"], (0, 1), (8000, 20000)),
    ("outflow", "Education & Self-Improvement", "Books", ["Books", "E-book"], (0, 1), (8000, 25000)),
]

# Occasional bigger things: (type, main, sub, description, chance per month, (min, max) MMK)
OCCASIONAL = [
    ("outflow", "Shopping & Lifestyle", "Electronics", "New headphones", 0.15, (150000, 400000)),
    ("outflow", "Health & Insurance", "Doctor Visits", "Clinic visit", 0.3, (20000, 60000)),
    ("outflow", "Education & Self-Improvement", "Online Courses", "Online course", 0.25, (30000, 120000)),
    ("outflow", "Other & Adjustments", "Miscellaneous", "Donation at pagoda", 0.4, (5000, 30000)),
    ("outflow", "Travel & Vacation", "Accommodation", "Weekend trip hotel", 0.15, (80000, 250000)),
    ("outflow", "Entertainment & Leisure", "Events & Concerts", "Concert ticket", 0.1, (30000, 80000)),
    ("inflow", "Employment Income", "Bonus", "Performance bonus", 0.1, (300000, 800000)),
    ("inflow", "Refunds & Reimbursements", "Expense Reimbursement", "Office expense reimbursement", 0.25, (20000, 80000)),
]


def login(api_url):
    token = os.environ.get("MOCK_ACCESS_TOKEN", "").strip()
    if token:
        r = requests.get(f"{api_url}/api/auth/me", headers=_headers(token), timeout=60)
        if r.status_code != 200:
            sys.exit(f"MOCK_ACCESS_TOKEN was refused ({r.status_code}). Unset it to sign in with email and password.")
        return token, r.json()
    email = input("Email: ").strip()
    password = getpass.getpass("Password (not shown): ")
    r = requests.post(f"{api_url}/api/auth/login", json={"email": email, "password": password}, timeout=60)
    if r.status_code != 200:
        sys.exit(f"Sign-in failed ({r.status_code}): {r.text[:200]}")
    body = r.json()
    return body["access_token"], body["user"]


def _headers(token):
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


def known_categories(api_url, token):
    known = set()
    for kind in ("inflow", "outflow"):
        r = requests.get(f"{api_url}/api/categories/{kind}", headers=_headers(token), timeout=60)
        r.raise_for_status()
        for cat in r.json():
            for sub in cat["sub_categories"]:
                known.add((kind, cat["main_category"], sub))
    return known


def _when(year, month, day, now):
    """A realistic local time on that day, or None if it is in the future."""
    hour = random.randint(7, 21)
    minute = random.randint(0, 59)
    try:
        at = datetime(year, month, day, hour, minute, tzinfo=YANGON)
    except ValueError:
        return None
    return at if at <= now else None


def _amount(lo, hi, currency):
    mmk = random.uniform(lo, hi)
    if currency == "mmk":
        return float(max(100, round(mmk / 100) * 100))
    return round(mmk / MMK_PER_UNIT[currency], 2) or 0.01


def build_plan(months, currency, known, now):
    salary = random.randrange(1_200_000, 1_800_001, 50_000)
    rent = random.randrange(300_000, 450_001, 25_000)
    fixed = {"Salary": (salary, salary), "Rent": (rent, rent)}
    plan, skipped = [], set()

    def add(kind, main, sub, desc, at, lo, hi):
        if at is None:
            return
        if (kind, main, sub) not in known:
            skipped.add(f"{main} / {sub}")
            return
        plan.append({
            "type": kind, "main_category": main, "sub_category": sub,
            "date": at.isoformat(), "description": desc,
            "amount": _amount(lo, hi, currency), "currency": currency,
        })

    first = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    for back in range(months - 1, -1, -1):
        y, m = first.year, first.month - back
        while m < 1:
            y, m = y - 1, m + 12
        days = (datetime(y + (m == 12), m % 12 + 1, 1) - datetime(y, m, 1)).days

        for kind, main, sub, desc, day, rng, chance in MONTHLY:
            if random.random() <= chance:
                lo, hi = rng or fixed[sub]
                add(kind, main, sub, desc, _when(y, m, min(day, days), now), lo, hi)
        for kind, main, sub, descs, (nmin, nmax), (lo, hi) in EVERYDAY:
            for _ in range(random.randint(nmin, nmax)):
                add(kind, main, sub, random.choice(descs), _when(y, m, random.randint(1, days), now), lo, hi)
        for kind, main, sub, desc, chance, (lo, hi) in OCCASIONAL:
            if random.random() < chance:
                add(kind, main, sub, desc, _when(y, m, random.randint(1, days), now), lo, hi)

    plan.sort(key=lambda t: t["date"])
    return plan, skipped


def post_all(api_url, token, plan):
    created = failed = 0
    for i, tx in enumerate(plan, 1):
        error = _post_one(api_url, token, tx)
        if error:
            failed += 1
            print(f"  [{i}/{len(plan)}] failed: {tx['date'][:10]} {tx['sub_category']}: {error}")
        else:
            created += 1
            if i % 25 == 0 or i == len(plan):
                print(f"  [{i}/{len(plan)}] added")
    return created, failed


def _post_one(api_url, token, tx):
    """Post one transaction, retrying network errors, 429 and 5xx. Returns an error text or None."""
    error = None
    for attempt in range(3):
        try:
            r = requests.post(f"{api_url}/api/transactions", headers=_headers(token), json=tx, timeout=60)
        except requests.RequestException as e:
            error = str(e)
        else:
            if r.status_code == 200:
                return None
            error = f"{r.status_code} {r.text[:150]}"
            if r.status_code < 500 and r.status_code != 429:
                return error
        time.sleep(2 * (attempt + 1))
    return error


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--api-url", default=os.environ.get("MOCK_API_BASE_URL", "http://localhost:8000"),
                   help="backend base URL (default: MOCK_API_BASE_URL or http://localhost:8000)")
    p.add_argument("--months", type=int, default=3, help="months of history, including this month (default 3)")
    p.add_argument("--currency", choices=sorted(MMK_PER_UNIT), help="default: the account's default currency")
    p.add_argument("--dry-run", action="store_true", help="show what would be added, write nothing")
    p.add_argument("--yes", action="store_true", help="do not ask for confirmation")
    args = p.parse_args()
    api_url = args.api_url.rstrip("/")
    if not 1 <= args.months <= 24:
        sys.exit("--months must be between 1 and 24")

    print(f"Backend: {api_url}")
    token, user = login(api_url)
    currency = args.currency or (user.get("default_currency") or "mmk").lower()
    known = known_categories(api_url, token)
    plan, skipped = build_plan(args.months, currency, known, datetime.now(YANGON))

    inflow = sum(t["amount"] for t in plan if t["type"] == "inflow")
    outflow = sum(t["amount"] for t in plan if t["type"] == "outflow")
    print(f"\nAccount:  {user.get('email')}")
    print(f"Adds:     {len(plan)} transactions over {args.months} month(s), in {currency.upper()}")
    print(f"Income:   {inflow:,.2f}   Spending: {outflow:,.2f}")
    if skipped:
        print(f"Skipped (category not on this server): {', '.join(sorted(skipped))}")
    if args.dry_run:
        for t in plan:
            print(f"  {t['date'][:10]}  {t['type']:<7} {t['sub_category']:<22} {t['amount']:>14,.2f}  {t['description']}")
        print("\nDry run: nothing was written.")
        return
    if not args.yes and input("\nAdd these to the account? Type yes: ").strip().lower() != "yes":
        print("Nothing was written.")
        return

    created, failed = post_all(api_url, token, plan)
    print(f"\nAdded {created}, failed {failed}.")


if __name__ == "__main__":
    main()
