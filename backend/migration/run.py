"""One-time copy of the Flow MongoDB data into PostgreSQL.

    cd backend
    pip install -r requirements.txt -r migration/requirements.txt
    python -m migration.run --dump <mongodump folder of the database>     # dry run from a mongodump
    python -m migration.run --mongo-url <url> --mongo-db <name>           # dry run from a live MongoDB
    python -m migration.run ... --write                                   # write into DATABASE_URL

Dry run by default: reads everything, converts it with migration/convert.py (the same
rules the E2E suites exercise) and prints the report; nothing is written without --write.

With --write, all rows are written in ONE PostgreSQL transaction, then verified inside
that transaction (row counts and per-user/currency money totals re-read from PostgreSQL
must equal what was planned); any mismatch rolls everything back. The target database
must be at the latest schema (alembic upgrade head) and empty, or pass --reset to empty
it first (inside the same transaction).

Nothing is silently dropped: documents that can't be stored as valid rows (NaN amounts,
rows whose owner account no longer exists, ...) are written to quarantined_records with
the reason. Problems that need a human decision (two accounts whose e-mails differ only
by letter case) stop the run before anything is written.

Exit codes: 0 ok, 1 error, 2 blocking data problems, 3 verification failed (rolled back).
"""
import argparse
import asyncio
import gzip
import json
import os
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import UTC, datetime
from decimal import ROUND_HALF_UP, Decimal
from typing import Any, Dict, Iterable, List, Optional, Tuple
from urllib.parse import urlsplit

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BACKEND not in sys.path:
    sys.path.insert(0, BACKEND)

from migration import convert as C  # noqa: E402

CENT = Decimal("0.01")
BATCH = 1000

# Collections read from MongoDB (anything else is reported as ignored).
COLLECTIONS = ("categories", "admins", "admin_action_logs", "app_versions", "users", "notification_preferences",
               "feedback", "ai_usage", "notifications", "insights", "chat_sessions", "goals", "transactions",
               "budgets", "quarantined_transactions")
# PostgreSQL tables in insert (foreign key) order.
TABLE_ORDER = ("categories", "admins", "admin_action_logs", "app_versions", "users", "notification_preferences",
               "feedback", "ai_usage", "notifications", "insights", "chat_sessions", "chat_messages", "goals",
               "transactions", "budgets", "budget_allocations", "quarantined_records")
USER_OWNED = ("notification_preferences", "feedback", "ai_usage", "notifications", "insights", "goals")


def cents(value: Any) -> Decimal:
    return Decimal(str(value)).quantize(CENT, rounding=ROUND_HALF_UP)


def old_app_amount(value: Any) -> Optional[Decimal]:
    """An amount as the old code summed it: finite numbers only (NaN/inf/strings were excluded)."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    if value != value or value in (float("inf"), float("-inf")):
        return None
    return cents(value)


# ====================================================================== source
def load_dump(folder: str) -> Dict[str, List[dict]]:
    """Documents from a mongodump folder (<collection>.bson or .bson.gz files of one database)."""
    import bson
    from bson.codec_options import CodecOptions

    options = CodecOptions(tz_aware=True, tzinfo=UTC)
    if not os.path.isdir(folder):
        sys.exit(f"--dump: not a folder: {folder}")
    data: Dict[str, List[dict]] = {}
    for name in sorted(os.listdir(folder)):
        if name.endswith(".bson") or name.endswith(".bson.gz"):
            collection = name.split(".bson")[0]
            opener = gzip.open if name.endswith(".gz") else open
            with opener(os.path.join(folder, name), "rb") as f:
                data[collection] = list(bson.decode_file_iter(f, codec_options=options))
    if not data:
        sys.exit(f"--dump: no .bson files in {folder} (point it at the folder of ONE database)")
    return data


def load_live(url: str, db_name: str) -> Dict[str, List[dict]]:
    from pymongo import MongoClient

    client = MongoClient(url, tz_aware=True, serverSelectionTimeoutMS=15000)
    try:
        db = client[db_name]
        return {name: list(db[name].find()) for name in db.list_collection_names()}
    finally:
        client.close()


# ====================================================================== plan
@dataclass
class Plan:
    rows: Dict[str, List[dict]] = field(default_factory=lambda: defaultdict(list))
    quarantined: List[dict] = field(default_factory=list)
    fixes: Counter = field(default_factory=Counter)
    blocking: List[str] = field(default_factory=list)
    read: Counter = field(default_factory=Counter)
    ignored_collections: List[str] = field(default_factory=list)
    # Deferred self/cross references, set after all rows exist.
    tx_parents: List[Tuple[str, str]] = field(default_factory=list)          # (id, parent id)
    budget_links: List[Tuple[str, Optional[str], Optional[str]]] = field(default_factory=list)  # (id, parent, rolled_over_to)
    balance_changes: List[dict] = field(default_factory=list)

    def quarantine(self, source: str, doc: dict, reason: str) -> None:
        self.quarantined.append(C.quarantine_row(source, doc, reason))


def _convert_all(plan: Plan, source: str, docs: Iterable[dict], converter) -> List[Tuple[dict, Any]]:
    """[(doc, converted)] for docs the converter accepts; the rest are quarantined."""
    out = []
    for doc in docs:
        try:
            out.append((doc, converter(doc)))
        except C.Quarantine as e:
            plan.quarantine(source, doc, str(e))
    return out


def _keep_newest(items: List[Tuple[dict, dict]], key, stamp) -> Tuple[List[Tuple[dict, dict]], List[Tuple[dict, dict]]]:
    """Split items into (kept, duplicates): per key the item with the newest stamp is kept."""
    groups: Dict[Any, List[Tuple[dict, dict]]] = defaultdict(list)
    for item in items:
        groups[key(item[1])].append(item)
    kept, dups = [], []
    for group in groups.values():
        group.sort(key=lambda it: stamp(it[1]) or datetime.min.replace(tzinfo=UTC), reverse=True)
        kept.append(group[0])
        dups.extend(group[1:])
    return kept, dups


def build_plan(source: Dict[str, List[dict]]) -> Plan:
    plan = Plan()
    for name, docs in source.items():
        plan.read[name] = len(docs)
        if name not in COLLECTIONS and not name.startswith("system."):
            plan.ignored_collections.append(name)
    get = lambda name: source.get(name, [])  # noqa: E731

    # ---- categories (one document per transaction type)
    for doc in get("categories"):
        try:
            plan.rows["categories"].extend(C.convert_categories(doc))
        except C.Quarantine as e:
            plan.quarantine("categories", doc, str(e))

    # ---- admins: e-mails are unique case-insensitively
    admins = _convert_all(plan, "admins", get("admins"), C.convert_admin)
    by_email = defaultdict(list)
    for doc, row in admins:
        by_email[row["email"]].append(row)
    for email, rows in by_email.items():
        if len(rows) > 1:
            plan.blocking.append(f"admins: {len(rows)} admin accounts share the e-mail {email!r} "
                                 f"(ids {', '.join(r['id'] for r in rows)}): delete or rename all but one")
    plan.rows["admins"] = [row for _, row in admins]

    plan.rows["admin_action_logs"] = [row for _, row in _convert_all(
        plan, "admin_action_logs", get("admin_action_logs"), C.convert_admin_action_log)]

    versions = _convert_all(plan, "app_versions", get("app_versions"), C.convert_app_version)
    kept, dups = _keep_newest(versions, lambda r: (r["version"], r["platform"]), lambda r: r["created_at"])
    for doc, row in dups:
        plan.quarantine("app_versions", doc, f"duplicate of version {row['version']} / {row['platform']} (newest kept)")
    plan.rows["app_versions"] = [row for _, row in kept]

    # ---- users: case-insensitive e-mail must be unique; one account per device token
    users = _convert_all(plan, "users", get("users"), C.convert_user)
    by_email = defaultdict(list)
    for doc, row in users:
        by_email[row["email"]].append((doc, row))
    for email, items in sorted(by_email.items()):
        if len(items) > 1:
            details = "; ".join(f"id {row['id']} ({doc.get('email')!r}, created {row['created_at']:%Y-%m-%d})"
                                for doc, row in items)
            plan.blocking.append(f"users: {len(items)} accounts share the e-mail {email!r} ignoring case: {details}. "
                                 f"Merge or delete all but one in MongoDB, then run again.")
    tokens = defaultdict(list)
    for doc, row in users:
        if row["fcm_token"]:
            tokens[row["fcm_token"]].append(row)
    for rows in tokens.values():
        rows.sort(key=lambda r: r["created_at"], reverse=True)
        for row in rows[1:]:  # the device re-registers its token on next app start
            row["fcm_token"] = None
            plan.fixes["users: device token shared by several accounts, kept on the newest account"] += 1
    plan.rows["users"] = [row for _, row in users]
    user_ids = {row["id"] for row in plan.rows["users"]}

    def owned(source_name: str, items: List[Tuple[dict, Any]], user_of) -> List[Tuple[dict, Any]]:
        kept_items = []
        for doc, conv in items:
            if user_of(conv) in user_ids:
                kept_items.append((doc, conv))
            else:
                plan.quarantine(source_name, doc, "owner account no longer exists")
        return kept_items

    # ---- simple user-owned tables
    for name in USER_OWNED:
        items = owned(name, _convert_all(plan, name, get(name), C.CONVERTERS[name]), lambda r: r["user_id"])
        if name == "notification_preferences":  # one row per user (the old code could race into two)
            items, dups = _keep_newest(items, lambda r: r["user_id"], lambda r: r["updated_at"])
            for doc, _ in dups:
                plan.quarantine(name, doc, "duplicate preferences of the same user (newest kept)")
        plan.rows[name] = [row for _, row in items]

    # ---- chat sessions + messages
    for doc, conv in owned("chat_sessions", _convert_all(plan, "chat_sessions", get("chat_sessions"),
                                                          C.convert_chat_session), lambda c: c["session"]["user_id"]):
        plan.rows["chat_sessions"].append(conv["session"])
        plan.rows["chat_messages"].extend(conv["messages"])

    # ---- transactions (parent links set after insert; dangling ones cleared)
    txs = owned("transactions", _convert_all(plan, "transactions", get("transactions"), C.convert_transaction),
                lambda r: r["user_id"])
    tx_ids = {row["id"] for _, row in txs}
    for _, row in txs:
        parent = row.pop("parent_transaction_id")
        row["parent_transaction_id"] = None
        if parent and parent in tx_ids:
            plan.tx_parents.append((row["id"], parent))
        elif parent:
            plan.fixes["transactions: link to a deleted recurring parent cleared"] += 1
    plan.rows["transactions"] = [row for _, row in txs]
    # Rows the old cleanup script had already set aside in MongoDB keep their reason.
    for doc in get("quarantined_transactions"):
        original = {k: v for k, v in doc.items() if not k.startswith("quarantine")}
        plan.quarantine("transactions", original, f"quarantined before the migration: {doc.get('quarantine_reason') or '?'}")

    # ---- budgets + allocations (parent / rolled-over links set after insert)
    budgets = owned("budgets", _convert_all(plan, "budgets", get("budgets"), C.convert_budget),
                    lambda c: c["budget"]["user_id"])
    budget_ids = {conv["budget"]["id"] for _, conv in budgets}
    children = defaultdict(list)
    for _, conv in budgets:
        b = conv["budget"]
        for link in ("parent_budget_id", "rolled_over_to"):
            if b[link] and b[link] not in budget_ids:
                b[link] = None
                plan.fixes[f"budgets: {link} pointing at a deleted budget cleared"] += 1
        if b["parent_budget_id"]:
            children[(b["user_id"], b["parent_budget_id"], b["start_date"])].append(b)
    for group in children.values():  # unique (user, parent, start): one rollover child per period
        group.sort(key=lambda b: b["created_at"])
        for b in group[1:]:
            b["parent_budget_id"] = None
            plan.fixes["budgets: second rollover child of the same period unlinked from its parent"] += 1
    for _, conv in budgets:
        b = conv["budget"]
        plan.budget_links.append((b["id"], b["parent_budget_id"], b["rolled_over_to"]))
        b["parent_budget_id"] = b["rolled_over_to"] = None
        plan.rows["budgets"].append(b)
        plan.rows["budget_allocations"].extend(conv["allocations"])

    plan.rows["quarantined_records"] = plan.quarantined
    _explain_balance_changes(plan, source, user_ids)
    return plan


def _explain_balance_changes(plan: Plan, source: Dict[str, List[dict]], user_ids: set) -> None:
    """Per user and currency: the balance the old app showed vs the migrated one, with the
    documents that make the difference and why (informational; the write is verified
    separately against the plan)."""
    migrated = {row["id"]: row for row in plan.rows["transactions"]}
    reasons = {(q["source"], q["id"]): q["reason"] for q in plan.quarantined}
    changes: Dict[Tuple[str, str], dict] = {}
    for doc in source.get("transactions", []):
        uid = str(doc.get("user_id"))
        if uid not in user_ids:
            continue
        old_amount = old_app_amount(doc.get("amount"))
        old_key = doc.get("currency") if isinstance(doc.get("currency"), str) and doc.get("currency") else None
        old = Decimal(0)
        if old_amount is not None and old_key and doc.get("type") in ("inflow", "outflow"):
            old = old_amount if doc["type"] == "inflow" else -old_amount
        row = migrated.get(str(doc.get("_id")))
        new = Decimal(0) if row is None else (cents(row["amount"]) * (1 if row["type"] == "inflow" else -1))
        new_key = row["currency"] if row else old_key
        for key, delta in (((uid, old_key), -old), ((uid, new_key), new)):
            if key[1] is None or delta == 0:
                continue
            entry = changes.setdefault(key, {"user_id": uid, "currency": key[1], "difference": Decimal(0), "documents": []})
            entry["difference"] += delta
        if old_key == new_key and old == new:
            continue
        if row is None:
            why = reasons.get(("transactions", str(doc.get("_id"))), "not migrated")
        elif old_key is None:
            why = "had no currency (the old app left it out of every balance); migrated as usd"
        else:
            why = "amount rounded to whole cents"
        entry_key = (uid, new_key or old_key)
        if entry_key[1] is not None:
            changes[entry_key]["documents"].append({"id": str(doc.get("_id")), "amount": repr(doc.get("amount")),
                                                    "reason": why})
    plan.balance_changes = sorted((c for c in changes.values() if c["difference"] != 0 or c["documents"]),
                                  key=lambda c: (c["user_id"], c["currency"]))


# ====================================================================== expected totals
def planned_totals(plan: Plan) -> dict:
    """What PostgreSQL must contain after the write (compared exactly)."""
    tx = defaultdict(Decimal)
    for row in plan.rows["transactions"]:
        tx[(row["user_id"], row["currency"], row["type"])] += cents(row["amount"])
    goals = defaultdict(Decimal)
    for row in plan.rows["goals"]:
        goals[(row["user_id"], row["currency"])] += cents(row["current_amount"])
    budgets = defaultdict(Decimal)
    for row in plan.rows["budgets"]:
        budgets[(row["user_id"], row["currency"])] += cents(row["total_budget"])
    return {"counts": {t: len(plan.rows[t]) for t in TABLE_ORDER},
            "transactions": dict(tx), "goals": dict(goals), "budgets": dict(budgets)}


# ====================================================================== write + verify
class VerificationFailed(Exception):
    pass


def _prepare(table, rows: List[dict]) -> List[dict]:
    from sqlalchemy import Numeric

    numeric = {c.name for c in table.columns if isinstance(c.type, Numeric)}
    out = []
    for row in rows:
        row = dict(row)
        for name in numeric & row.keys():
            if isinstance(row[name], float):
                row[name] = Decimal(str(row[name]))
        out.append(row)
    return out


async def write(plan: Plan, database_url: str, reset: bool) -> dict:
    from alembic.config import Config
    from alembic.script import ScriptDirectory
    from sqlalchemy import bindparam, func, select, text, update
    from sqlalchemy.ext.asyncio import create_async_engine

    from sql.db import _async_url
    from sql import tables as T

    head = ScriptDirectory.from_config(Config(os.path.join(BACKEND, "alembic.ini"))).get_current_head()
    engine = create_async_engine(_async_url(database_url))
    try:
        async with engine.begin() as conn:  # ONE transaction: any exception rolls everything back
            try:
                version = (await conn.execute(text("SELECT version_num FROM alembic_version"))).scalar()
            except Exception:
                raise SystemExit("Target database has no schema: run `alembic upgrade head` first.")
            if version != head:
                raise SystemExit(f"Target database schema is at {version}, expected {head}: run `alembic upgrade head`.")
            tables = [T.metadata.tables[name] for name in TABLE_ORDER]
            non_empty = [t.name for t in tables if (await conn.execute(select(func.count()).select_from(t))).scalar()]
            if non_empty and not reset:
                raise SystemExit(f"Target database is not empty ({', '.join(non_empty)}). "
                                 f"Use --reset to replace its contents.")
            if non_empty:
                await conn.execute(text("TRUNCATE " + ", ".join(t.name for t in tables) + " CASCADE"))

            for table in tables:
                rows = _prepare(table, plan.rows[table.name])
                for i in range(0, len(rows), BATCH):
                    await conn.execute(table.insert(), rows[i:i + BATCH])
                print(f"  wrote {len(rows):>7} {table.name}")

            t, b = T.transactions, T.budgets
            if plan.tx_parents:
                await conn.execute(update(t).where(t.c.id == bindparam("tid")).values(parent_transaction_id=bindparam("pid")),
                                   [{"tid": i, "pid": p} for i, p in plan.tx_parents])
            links = [{"bid": i, "p": p, "r": r} for i, p, r in plan.budget_links if p or r]
            if links:
                await conn.execute(update(b).where(b.c.id == bindparam("bid"))
                                   .values(parent_budget_id=bindparam("p"), rolled_over_to=bindparam("r")), links)

            # ---- verify inside the transaction
            expected = planned_totals(plan)
            actual = {"counts": {}, "transactions": {}, "goals": {}, "budgets": {}}
            for table in tables:
                actual["counts"][table.name] = (await conn.execute(select(func.count()).select_from(table))).scalar()
            for r in (await conn.execute(select(t.c.user_id, t.c.currency, t.c.type, func.sum(t.c.amount))
                                         .group_by(t.c.user_id, t.c.currency, t.c.type))).all():
                actual["transactions"][(r[0], r[1], r[2])] = r[3]
            g = T.goals
            for r in (await conn.execute(select(g.c.user_id, g.c.currency, func.sum(g.c.current_amount))
                                         .group_by(g.c.user_id, g.c.currency))).all():
                actual["goals"][(r[0], r[1])] = r[2]
            for r in (await conn.execute(select(b.c.user_id, b.c.currency, func.sum(b.c.total_budget))
                                         .group_by(b.c.user_id, b.c.currency))).all():
                actual["budgets"][(r[0], r[1])] = r[2]
            linked = (await conn.execute(select(func.count()).select_from(t).where(t.c.parent_transaction_id.isnot(None)))).scalar()
            actual["counts"]["transaction parent links"] = linked
            expected["counts"]["transaction parent links"] = len(plan.tx_parents)

            problems = []
            for section in ("counts", "transactions", "goals", "budgets"):
                exp = {k: v for k, v in expected[section].items() if v != 0 or section == "counts"}
                act = {k: v for k, v in actual[section].items() if v != 0 or section == "counts"}
                for key in sorted(set(exp) | set(act), key=str):
                    if exp.get(key) != act.get(key):
                        problems.append(f"{section} {key}: planned {exp.get(key)}, database has {act.get(key)}")
            if problems:
                raise VerificationFailed("\n  ".join(problems[:50]))
            return {"counts": actual["counts"], "schema": version}
    finally:
        await engine.dispose()


# ====================================================================== report
def _host(url: Optional[str]) -> str:
    """host[:port]/database of a URL, never the credentials."""
    if not url:
        return "?"
    parts = urlsplit(url)
    return f"{parts.hostname or '?'}{':' + str(parts.port) if parts.port else ''}{parts.path or ''}"


def report(plan: Plan) -> dict:
    by_reason = Counter((q["source"], q["reason"].split(":")[0]) for q in plan.quarantined)
    return {
        "read": dict(plan.read),
        "ignored_collections": plan.ignored_collections,
        "rows_planned": {t: len(plan.rows[t]) for t in TABLE_ORDER},
        "quarantined": [{"source": s, "reason": r, "count": n} for (s, r), n in sorted(by_reason.items())],
        "fixes": dict(plan.fixes),
        "blocking": plan.blocking,
        "balance_changes": [{**c, "difference": str(c["difference"])} for c in plan.balance_changes],
    }


def print_report(rep: dict) -> None:
    def section(title):
        print(f"\n{title}\n{'-' * len(title)}")

    section("Read from MongoDB")
    for name, n in sorted(rep["read"].items()):
        print(f"  {name:28} {n:>7}")
    if rep["ignored_collections"]:
        print(f"  (not migrated: {', '.join(rep['ignored_collections'])})")
    section("Rows for PostgreSQL")
    for name, n in rep["rows_planned"].items():
        print(f"  {name:28} {n:>7}")
    section("Set aside in quarantined_records (kept for audit, not used by the app)")
    for q in rep["quarantined"] or [{"source": "-", "reason": "none", "count": 0}]:
        print(f"  {q['count']:>5}  {q['source']}: {q['reason']}")
    section("Automatic repairs")
    for what, n in (rep["fixes"] or {"none": 0}).items():
        print(f"  {n:>5}  {what}")
    section("Balances that change compared with the old app")
    if not rep["balance_changes"]:
        print("  none: every user's balance per currency stays exactly the same")
    for c in rep["balance_changes"][:50]:
        print(f"  user {c['user_id']} {c['currency'].upper()}: {c['difference']:>12}")
        for d in c["documents"][:5]:
            print(f"      transaction {d['id']} (amount {d['amount']}): {d['reason']}")
    if len(rep["balance_changes"]) > 50:
        print(f"  ... {len(rep['balance_changes']) - 50} more in the JSON report")
    if rep["blocking"]:
        section("BLOCKING: fix these in MongoDB first (nothing was written)")
        for b in rep["blocking"]:
            print(f"  * {b}")


# ====================================================================== main
def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Copy the Flow MongoDB data into PostgreSQL (dry run by default).")
    src = parser.add_mutually_exclusive_group()
    src.add_argument("--dump", help="folder with the mongodump .bson files of the database")
    src.add_argument("--mongo-url", help="live MongoDB URL (default: MONGODB_URL)")
    parser.add_argument("--mongo-db", help="MongoDB database name (default: DATABASE_NAME)")
    parser.add_argument("--database-url", help="target PostgreSQL URL (default: DATABASE_URL)")
    parser.add_argument("--write", action="store_true", help="write into PostgreSQL (one transaction, verified)")
    parser.add_argument("--reset", action="store_true", help="with --write: empty the target tables first")
    parser.add_argument("--yes", action="store_true", help="with --write: don't ask for confirmation")
    parser.add_argument("--report", help="also save the report as JSON to this file")
    args = parser.parse_args(argv)

    from config import settings  # loads backend/.env like the app (never printed)

    if args.dump:
        print(f"Source: mongodump folder {args.dump}")
        source = load_dump(args.dump)
    else:
        url, name = args.mongo_url or settings.MONGODB_URL, args.mongo_db or settings.DATABASE_NAME
        if not url or not name:
            parser.error("give --dump, or --mongo-url/--mongo-db (or set MONGODB_URL / DATABASE_NAME)")
        print(f"Source: MongoDB {_host(url)} / database {name!r}")
        source = load_live(url, name)

    plan = build_plan(source)
    rep = report(plan)
    print_report(rep)
    if args.report:
        with open(args.report, "w", encoding="utf-8") as f:
            json.dump(rep, f, indent=1, default=str, ensure_ascii=False)
        print(f"\nReport saved to {args.report}")
    if plan.blocking:
        return 2
    if not args.write:
        print("\nDry run: nothing was written. Re-run with --write to copy the data.")
        return 0

    database_url = args.database_url or settings.DATABASE_URL
    if not database_url:
        parser.error("--write needs --database-url or DATABASE_URL")
    target = _host(database_url)
    print(f"\nTarget: PostgreSQL {target}{' (contents will be REPLACED)' if args.reset else ''}")
    if not args.yes and input("Type WRITE to copy the data: ").strip() != "WRITE":
        print("Aborted.")
        return 1
    try:
        result = asyncio.run(write(plan, database_url, args.reset))
    except VerificationFailed as e:
        print(f"\nVERIFICATION FAILED, everything was rolled back:\n  {e}")
        return 3
    print(f"\nDone: written and verified in one transaction (schema {result['schema']}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
