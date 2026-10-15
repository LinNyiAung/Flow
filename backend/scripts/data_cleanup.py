#!/usr/bin/env python
"""
One-off data maintenance for the Flow / Toe Pwar database.

Dry-run by default: nothing is changed unless --apply (and/or --mark-legacy-verified)
is given. See scripts/README.md. ALWAYS back up the database first.

Checks
  a) transactions with a non-finite amount (NaN / +inf / -inf)
       --apply: moved to `quarantined_transactions` (with reason + timestamp) and the
                owners' cached balances invalidated (unset balances, $inc balances_version)
  b) user e-mails that differ only by letter case (report for manual merging)
       --apply: lowercases e-mails that have NO case-insensitive conflict
  c) users without an `is_verified` field (report count)
       --mark-legacy-verified: sets is_verified=True for them (NOT implied by --apply)
  d) insights whose content is null / empty / not a string
       --apply: deleted
  e) summary

Connection: MONGODB_URL / DATABASE_NAME from the backend settings (config.py, which
loads backend/.env like the app does; real environment variables take precedence).
"""
import argparse
import math
import os
import sys
from collections import defaultdict
from datetime import UTC, datetime

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

# Matches exactly NaN, +inf and -inf (MongoDB equality on NaN matches NaN).
NON_FINITE_AMOUNT_QUERY = {
    "$or": [{"amount": float("nan")}, {"amount": float("inf")}, {"amount": float("-inf")}]
}
# Amount present but not a number at all (string, null, object...): reported only.
NON_NUMERIC_AMOUNT_QUERY = {"amount": {"$not": {"$type": "number"}}}
# Insight content that can't be shown: missing, null, not a string, or whitespace only.
INVALID_INSIGHT_QUERY = {"$nor": [{"content": {"$type": "string", "$regex": r"\S"}}]}
BUDGET_NUMBER_FIELDS = ("total_budget", "total_spent", "remaining_budget", "percentage_used")
SAMPLE_LIMIT = 20


def _fmt_dt(value):
    if isinstance(value, datetime):
        return value.isoformat(timespec="seconds")
    return "-" if value is None else str(value)


def _amount_repr(value):
    if isinstance(value, float):
        if math.isnan(value):
            return "NaN"
        if math.isinf(value):
            return "Infinity" if value > 0 else "-Infinity"
    return repr(value)


def _section(title):
    print()
    print("=" * 78)
    print(title)
    print("=" * 78)


def connect():
    """(client, db, display_target) from the backend settings. Never prints credentials."""
    from pymongo import MongoClient
    from pymongo.uri_parser import parse_uri

    from config import settings  # loads backend/.env (python-dotenv) like the app

    url, name = settings.MONGODB_URL, settings.DATABASE_NAME
    if not url or not name:
        sys.exit("MONGODB_URL and DATABASE_NAME must be set (environment or backend/.env).")
    try:
        nodes = ",".join(f"{h}:{p}" for h, p in parse_uri(url)["nodelist"]) or "?"
    except Exception:
        nodes = "?"
    client = MongoClient(url, tz_aware=True, serverSelectionTimeoutMS=15000)
    client.admin.command("ping")
    return client, client[name], f"{nodes} / database '{name}'"


# ---------------------------------------------------------------- a) amounts

def check_non_finite_transactions(db, apply: bool, summary: dict):
    _section("a) Transactions with non-finite amounts (NaN / +-Infinity)")
    docs = list(db.transactions.find(NON_FINITE_AMOUNT_QUERY))
    by_user = defaultdict(list)
    for d in docs:
        by_user[d.get("user_id")].append(d)

    print(f"Found {len(docs)} transaction(s) across {len(by_user)} user(s).")
    for d in docs[:SAMPLE_LIMIT]:
        print(f"  - tx {d.get('_id')}  user {d.get('user_id')}  amount={_amount_repr(d.get('amount'))}  "
              f"type={d.get('type')}  currency={d.get('currency')}  date={_fmt_dt(d.get('date'))}")
    if len(docs) > SAMPLE_LIMIT:
        print(f"  ... and {len(docs) - SAMPLE_LIMIT} more")

    non_numeric = db.transactions.count_documents(NON_NUMERIC_AMOUNT_QUERY)
    if non_numeric:
        print(f"Note: {non_numeric} transaction(s) have a NON-NUMERIC amount (string/null/...). They are "
              f"ignored by the app's read paths but NOT changed by this script; inspect them manually.")

    bad_budgets = db.budgets.count_documents({
        "$or": [{f: v} for f in BUDGET_NUMBER_FIELDS for v in (float("nan"), float("inf"), float("-inf"))]
    })
    if bad_budgets:
        print(f"Note: {bad_budgets} budget(s) store NaN/inf totals; the app recomputes them automatically "
              f"the next time they are read (after the transactions above are quarantined).")

    summary["non_finite_transactions"] = len(docs)
    summary["non_finite_users"] = len(by_user)
    summary["non_numeric_transactions"] = non_numeric
    summary["budgets_with_non_finite_totals"] = bad_budgets

    if not apply or not docs:
        return
    now = datetime.now(UTC)
    moved = 0
    for d in docs:
        quarantined = {
            **d,
            "quarantine_reason": "non_finite_amount",
            "quarantine_amount_repr": _amount_repr(d.get("amount")),
            "quarantined_at": now,
            "quarantined_from": "transactions",
        }
        # Idempotent: a re-run after a partial failure just overwrites the copy.
        db.quarantined_transactions.replace_one({"_id": d["_id"]}, quarantined, upsert=True)
        db.transactions.delete_one({"_id": d["_id"]})
        moved += 1
    user_ids = [u for u in by_user if u is not None]
    invalidated = 0
    if user_ids:
        res = db.users.update_many(
            {"_id": {"$in": user_ids}},
            {"$unset": {"balances": ""}, "$inc": {"balances_version": 1}, "$set": {"ai_data_stale": True}},
        )
        invalidated = res.modified_count
    print(f"APPLIED: moved {moved} transaction(s) to 'quarantined_transactions'; "
          f"invalidated the balance cache of {invalidated} user(s).")
    summary["quarantined"] = moved
    summary["balance_caches_invalidated"] = invalidated


# ---------------------------------------------------------------- b) e-mails

def _last_activity(db, user):
    for field in ("last_login", "last_login_at", "last_active", "last_seen_at"):
        if user.get(field):
            return f"{field}={_fmt_dt(user[field])}"
    last_tx = db.transactions.find_one({"user_id": user["_id"]}, {"created_at": 1}, sort=[("created_at", -1)])
    if last_tx and last_tx.get("created_at"):
        return f"last_tx={_fmt_dt(last_tx['created_at'])}"
    return "no activity recorded"


def check_case_duplicate_emails(db, apply: bool, summary: dict):
    _section("b) User e-mails that differ only by letter case")
    groups = list(db.users.aggregate([
        {"$match": {"email": {"$type": "string"}}},
        {"$group": {"_id": {"$toLower": {"$trim": {"input": "$email"}}}, "ids": {"$push": "$_id"}, "n": {"$sum": 1}}},
        {"$match": {"n": {"$gt": 1}}},
        {"$sort": {"_id": 1}},
    ], allowDiskUse=True))

    print(f"Found {len(groups)} group(s) of conflicting e-mails (merge manually; not changed by this script).")
    for g in groups:
        print(f"  * {g['_id']}  ({g['n']} accounts)")
        for user in db.users.find({"_id": {"$in": g["ids"]}}).sort("created_at", 1):
            tx_count = db.transactions.count_documents({"user_id": user["_id"]})
            print(f"      - id={user['_id']}  email={user.get('email')!r}  created_at={_fmt_dt(user.get('created_at'))}  "
                  f"{_last_activity(db, user)}  is_verified={user.get('is_verified', '<missing>')}  "
                  f"transactions={tx_count}")
    summary["email_conflict_groups"] = len(groups)

    conflicted = {g["_id"] for g in groups}
    fixable = []
    for user in db.users.find({"email": {"$type": "string"}}, {"email": 1}):
        email = user["email"]
        normalized = email.strip().lower()
        if email != normalized and normalized not in conflicted:
            fixable.append((user["_id"], email, normalized))

    print(f"{len(fixable)} account(s) have a non-lowercase e-mail WITHOUT a conflict"
          f"{' (will be lowercased)' if apply else ' (use --apply to lowercase them)'}.")
    for uid, email, normalized in fixable[:SAMPLE_LIMIT]:
        print(f"  - id={uid}  {email!r} -> {normalized!r}")
    if len(fixable) > SAMPLE_LIMIT:
        print(f"  ... and {len(fixable) - SAMPLE_LIMIT} more")
    summary["emails_lowercasable"] = len(fixable)

    if not apply or not fixable:
        return
    changed = 0
    for uid, email, normalized in fixable:
        try:
            # Only if the e-mail is still what we inspected (no concurrent change).
            res = db.users.update_one({"_id": uid, "email": email}, {"$set": {"email": normalized}})
            changed += res.modified_count
        except Exception as e:  # e.g. duplicate key from the case-insensitive unique index
            print(f"  ! could not lowercase {uid}: {type(e).__name__}: {e}")
    print(f"APPLIED: lowercased {changed} e-mail(s). Those users must sign in again.")
    summary["emails_lowercased"] = changed


# ---------------------------------------------------------------- c) is_verified

def check_missing_is_verified(db, mark_legacy_verified: bool, summary: dict):
    _section("c) Users without an is_verified field")
    query = {"is_verified": {"$exists": False}}
    count = db.users.count_documents(query)
    print(f"Found {count} user(s) without is_verified (they cannot log in: login requires is_verified=True).")
    summary["users_missing_is_verified"] = count
    if not mark_legacy_verified:
        if count:
            print("Use --mark-legacy-verified to set is_verified=True for them.")
        return
    if not count:
        return
    res = db.users.update_many(
        query, {"$set": {"is_verified": True, "verified_via": "legacy_cleanup", "verified_at": datetime.now(UTC)}}
    )
    print(f"APPLIED: marked {res.modified_count} legacy user(s) as verified.")
    summary["users_marked_verified"] = res.modified_count


# ---------------------------------------------------------------- d) insights

def check_empty_insights(db, apply: bool, summary: dict):
    _section("d) Insights with null / empty content")
    docs = list(db.insights.find(INVALID_INSIGHT_QUERY, {"user_id": 1, "insight_type": 1, "ai_provider": 1,
                                                          "generated_at": 1, "content": 1}))
    print(f"Found {len(docs)} insight(s) without usable content.")
    for d in docs[:SAMPLE_LIMIT]:
        print(f"  - insight {d.get('_id')}  user {d.get('user_id')}  {d.get('insight_type')}/{d.get('ai_provider')}  "
              f"generated_at={_fmt_dt(d.get('generated_at'))}  content={d.get('content')!r}")
    if len(docs) > SAMPLE_LIMIT:
        print(f"  ... and {len(docs) - SAMPLE_LIMIT} more")
    summary["empty_insights"] = len(docs)
    if not apply or not docs:
        return
    res = db.insights.delete_many({"_id": {"$in": [d["_id"] for d in docs]}, **INVALID_INSIGHT_QUERY})
    print(f"APPLIED: deleted {res.deleted_count} empty insight(s).")
    summary["empty_insights_deleted"] = res.deleted_count


# ---------------------------------------------------------------- main

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="One-off data cleanup (dry-run by default). Back up first!")
    parser.add_argument("--apply", action="store_true",
                        help="apply fixes a) quarantine, b) lowercase conflict-free e-mails, d) delete empty insights")
    parser.add_argument("--mark-legacy-verified", action="store_true",
                        help="c) set is_verified=True for users missing the field (separate, explicit flag)")
    parser.add_argument("--yes", action="store_true", help="don't ask for confirmation before changing data")
    args = parser.parse_args(argv)

    client, db, target = connect()
    changing = args.apply or args.mark_legacy_verified
    mode = "APPLY" if changing else "DRY-RUN (no changes)"
    print(f"Target: {target}")
    print(f"Mode:   {mode}"
          f"{'  [--apply]' if args.apply else ''}{'  [--mark-legacy-verified]' if args.mark_legacy_verified else ''}")

    if changing and not args.yes:
        answer = input(f"This will MODIFY database '{db.name}'. Did you back it up? Type the database name to continue: ")
        if answer.strip() != db.name:
            print("Aborted.")
            return 1

    summary: dict = {}
    try:
        check_non_finite_transactions(db, args.apply, summary)
        check_case_duplicate_emails(db, args.apply, summary)
        check_missing_is_verified(db, args.mark_legacy_verified, summary)
        check_empty_insights(db, args.apply, summary)
    finally:
        client.close()

    _section(f"e) Summary ({mode})")
    for key, value in summary.items():
        print(f"  {key:34} {value}")
    if not changing:
        print("\nNothing was changed. Re-run with --apply (and/or --mark-legacy-verified) to fix.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
