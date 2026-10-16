"""Test-only adapter: pymongo-style calls on the PostgreSQL tables.

The E2E suites poke the database directly (make a user premium, insert a legacy
transaction, read an OTP hash, ...). They were written against MongoDB; `get_db()`
returns an object whose attributes are `PgCollection`s accepting the subset of Mongo
calls and operators the suites use, so the suites barely changed in the move. Direct
inserts go through the production migration converters (migration/convert.py).
"""
import json
import os
import re
import sys
from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

import psycopg
from psycopg import sql
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend"))
from sql import docs as D  # noqa: E402
from sql import tables as T  # noqa: E402
from migration.convert import CONVERTERS, MULTI_CONVERTERS, Quarantine, quarantine_row  # noqa: E402  (same rules as the production data migration)

PG_DSN = os.environ.get("E2E_PG_DSN", "postgresql://flow@127.0.0.1:54329/flow_e2e")
TABLES = {"users", "transactions", "goals", "budgets", "notifications", "notification_preferences", "insights",
          "chat_sessions", "ai_usage", "admins", "admin_action_logs", "feedback", "categories", "app_versions",
          "quarantined_transactions"}


# Mongo field path -> column, per table (only the non-obvious ones).
_FIELD_MAP = {
    "transactions": {
        "recurrence.enabled": "recurrence_enabled",
        "recurrence.parent_transaction_id": "parent_transaction_id",
        "recurrence.last_created_date": "recurrence_last_created_date",
        "recurrence.config.frequency": "recurrence_frequency",
        "recurrence.config.end_date": "recurrence_end_date",
    },
    "insights": {f"token_usage.{k}": k for k in ("input_tokens", "output_tokens", "total_tokens")},
}


class Result:
    def __init__(self, matched=0, modified=0, deleted=0, inserted_id=None, inserted_ids=None):
        self.matched_count, self.modified_count, self.deleted_count = matched, modified, deleted
        self.inserted_id, self.inserted_ids = inserted_id, inserted_ids or []
        self.acknowledged = True


class Cursor(list):
    def sort(self, key, direction=1):
        keys = key if isinstance(key, list) else [(key, direction)]
        for k, d in reversed(keys):
            self[:] = sorted(self, key=lambda doc: (doc.get(k) is None, doc.get(k)), reverse=d == -1)
        return self

    def limit(self, n):
        if n:
            del self[n:]
        return self

    def skip(self, n):
        del self[:n]
        return self

    def to_list(self, *_a, **_k):
        return list(self)


class PgCollection:
    def __init__(self, conn, name: str):
        self.conn, self.name = conn, name
        self.table = T.metadata.tables[name]
        self.cols = {c.name: c for c in self.table.columns}
        self.pk = "user_id" if name == "notification_preferences" else ("type" if name == "categories" else "id")

    # ----------------------------------------------------------- translation
    def _col(self, field: str) -> str:
        if field == "_id":
            return self.pk
        mapped = _FIELD_MAP.get(self.name, {}).get(field, field)
        if mapped not in self.cols:
            raise KeyError(f"{self.name}: no column for field {field!r}")
        return mapped

    def _value(self, col: str, value: Any) -> Any:
        coltype = self.cols[col].type
        if isinstance(value, (dict, list)) and coltype.__class__.__name__ == "JSONB":
            return Jsonb(value)
        if isinstance(value, float) and coltype.__class__.__name__ == "Numeric":
            return Decimal(str(value))
        return value

    def _where(self, flt: Optional[Dict[str, Any]]) -> Tuple[sql.Composable, List[Any]]:
        if not flt:
            return sql.SQL("TRUE"), []
        parts, params = [], []
        for field, cond in flt.items():
            if field in ("$or", "$and"):
                subs = [self._where(f) for f in cond]
                joiner = sql.SQL(" OR " if field == "$or" else " AND ")
                parts.append(sql.SQL("(") + joiner.join(s for s, _ in subs) + sql.SQL(")"))
                for _, p in subs:
                    params += p
                continue
            col = sql.Identifier(self._col(field))
            cname = self._col(field)
            if isinstance(cond, dict) and any(k.startswith("$") for k in cond):
                for op, v in cond.items():
                    if op == "$in":
                        parts.append(col + sql.SQL(" = ANY(%s)")); params.append([self._value(cname, x) for x in v])
                    elif op == "$nin":
                        parts.append(sql.SQL("NOT (") + col + sql.SQL(" = ANY(%s))")); params.append(list(v))
                    elif op in ("$gt", "$gte", "$lt", "$lte"):
                        sym = {"$gt": ">", "$gte": ">=", "$lt": "<", "$lte": "<="}[op]
                        parts.append(col + sql.SQL(f" {sym} %s")); params.append(self._value(cname, v))
                    elif op == "$ne":
                        parts.append(col + sql.SQL(" IS DISTINCT FROM %s")); params.append(self._value(cname, v))
                    elif op == "$exists":
                        parts.append(col + sql.SQL(" IS NOT NULL" if v else " IS NULL"))
                    elif op == "$regex":
                        flags = cond.get("$options", "")
                        parts.append(col + sql.SQL(" ~* %s" if "i" in flags else " ~ %s")); params.append(v)
                    elif op in ("$options", "$type"):
                        continue
                    else:
                        raise NotImplementedError(f"{self.name}: operator {op}")
            elif cond is None:
                parts.append(col + sql.SQL(" IS NULL"))
            else:
                parts.append(col + sql.SQL(" = %s")); params.append(self._value(cname, cond))
        return sql.SQL(" AND ").join(parts), params

    def _to_doc(self, row: Dict[str, Any]) -> Dict[str, Any]:
        if self.name == "transactions":
            return D.transaction_doc(row)
        if self.name == "insights":
            return D.insight_doc(row)
        if self.name == "budgets":
            with self.conn.cursor(row_factory=dict_row) as cur:
                cur.execute("SELECT * FROM budget_allocations WHERE budget_id = %s", (row["id"],))
                return D.budget_doc(row, cur.fetchall())
        if self.name == "notification_preferences":
            return {"_id": row["user_id"], **row}
        return D.row_to_doc(row)

    def _to_row(self, doc: Dict[str, Any]) -> Dict[str, Any]:
        if self.name in CONVERTERS:
            # Test inserts go through the migration converter, so legacy-shaped test
            # documents are stored exactly as the production migration would store them.
            row = CONVERTERS[self.name](doc)
            return {k: self._value(k, v) for k, v in row.items()}
        if self.name == "transactions":
            row = D.transaction_row(doc)
        elif self.name == "insights":
            row = D.insight_row(doc)
        else:
            row = {(self.pk if k == "_id" else k): v for k, v in doc.items()}
        unknown = [k for k in row if k not in self.cols]
        for k in unknown:
            row.pop(k)
        if unknown:
            print(f"[pgcompat] {self.name}: ignored fields {unknown}", file=sys.stderr)
        return {k: self._value(k, v) for k, v in row.items()}

    # ----------------------------------------------------------- reads
    def find(self, flt=None, projection=None, sort=None, limit=0) -> Cursor:
        where, params = self._where(flt)
        q = sql.SQL("SELECT * FROM {} WHERE ").format(sql.Identifier(self.name)) + where
        with self.conn.cursor(row_factory=dict_row) as cur:
            cur.execute(q, params)
            rows = cur.fetchall()
        result = Cursor(self._to_doc(r) for r in rows)
        if sort:
            result.sort(sort)
        return result.limit(limit)

    def find_one(self, flt=None, projection=None, sort=None):
        rows = self.find(flt, sort=sort)
        return rows[0] if rows else None

    def count_documents(self, flt=None, limit=0):
        where, params = self._where(flt)
        q = sql.SQL("SELECT count(*) FROM {} WHERE ").format(sql.Identifier(self.name)) + where
        with self.conn.cursor() as cur:
            cur.execute(q, params)
            n = cur.fetchone()[0]
        return min(n, limit) if limit else n

    def distinct(self, field, flt=None):
        return sorted({d.get(field) for d in self.find(flt)})

    # ----------------------------------------------------------- writes
    def _quarantine(self, doc, reason):
        """What the production migration does with a row it can't store: set it aside
        (transactions into quarantined_transactions, other rows only in the report)."""
        if self.name != "transactions":
            print(f"[pgcompat] {self.name}: not stored, as in the migration: {reason}", file=sys.stderr)
            return
        row = quarantine_row(doc, reason)
        with self.conn.cursor() as cur:
            cur.execute("INSERT INTO quarantined_transactions (id, user_id, reason, original) VALUES (%s, %s, %s, %s)"
                        " ON CONFLICT (id) DO NOTHING", (row["id"], row["user_id"], row["reason"], Jsonb(row["original"])))

    def _insert_sql(self, row):
        return sql.SQL("INSERT INTO {} ({}) VALUES ({})").format(
            sql.Identifier(self.name), sql.SQL(", ").join(map(sql.Identifier, row)), sql.SQL(", ").join(sql.Placeholder() * len(row)))

    def _insert_allocations(self, cur, allocations):
        for a in allocations:
            a = {k: (Decimal(str(v)) if isinstance(v, float) else v) for k, v in a.items()}
            cur.execute("INSERT INTO budget_allocations (budget_id, position, main_category, allocated_amount, spent_amount,"
                        " percentage_used, is_exceeded) VALUES (%(budget_id)s, %(position)s, %(main_category)s, %(allocated_amount)s,"
                        " %(spent_amount)s, %(percentage_used)s, %(is_exceeded)s)", a)

    def _insert_budget(self, doc):
        """Budgets go through the migration converter too (budget row + allocation rows)."""
        try:
            converted = MULTI_CONVERTERS["budgets"](doc)
        except Quarantine as e:
            self._quarantine(doc, str(e))
            return Result(inserted_id=doc.get("_id"))
        row = {k: self._value(k, v) for k, v in converted["budget"].items()}
        with self.conn.transaction(), self.conn.cursor() as cur:
            cur.execute(self._insert_sql(row), list(row.values()))
            self._insert_allocations(cur, converted["allocations"])
        return Result(inserted_id=doc.get("_id"))

    def insert_one(self, doc):
        if self.name == "budgets":
            return self._insert_budget(doc)
        try:
            row = self._to_row(doc)
        except Quarantine as e:
            self._quarantine(doc, str(e))
            return Result(inserted_id=doc.get("_id"))
        with self.conn.cursor() as cur:
            cur.execute(self._insert_sql(row), list(row.values()))
        return Result(inserted_id=doc.get("_id"))

    def insert_many(self, docs, ordered=True):
        if self.name == "budgets":
            return Result(inserted_ids=[self.insert_one(d).inserted_id for d in docs])
        rows = []
        for d in docs:
            try:
                rows.append(self._to_row(d))
            except Quarantine as e:
                self._quarantine(d, str(e))
        by_shape = {}
        for row in rows:
            by_shape.setdefault(tuple(row), []).append(list(row.values()))
        with self.conn.transaction(), self.conn.cursor() as cur:
            for shape, values in by_shape.items():
                cur.executemany(self._insert_sql(dict.fromkeys(shape)), values)
        return Result(inserted_ids=[d.get("_id") for d in docs])

    def _update(self, flt, update, many: bool) -> Result:
        assignments, params = [], []
        categories = None
        for field, value in (update.get("$set") or {}).items():
            if self.name == "transactions" and field == "recurrence":
                for col, v in D.recurrence_columns(value).items():
                    assignments.append(sql.Identifier(col) + sql.SQL(" = %s")); params.append(v)
                continue
            if self.name == "budgets" and field == "category_budgets":
                categories = value
                continue
            col = self._col(field)
            assignments.append(sql.Identifier(col) + sql.SQL(" = %s")); params.append(self._value(col, value))
        for field in (update.get("$unset") or {}):
            col = self._col(field)
            c = self.cols[col]
            if c.nullable:
                assignments.append(sql.Identifier(col) + sql.SQL(" = NULL"))
            else:
                assignments.append(sql.Identifier(col) + sql.SQL(" = DEFAULT"))
        for field, inc in (update.get("$inc") or {}).items():
            col = self._col(field)
            assignments.append(sql.Identifier(col) + sql.SQL(" = COALESCE({}, 0) + %s").format(sql.Identifier(col)))
            params.append(inc)
        if not assignments and categories is not None:
            assignments.append(sql.SQL("updated_at = updated_at"))  # only the allocations change
        if not assignments:
            raise NotImplementedError(f"pgcompat: update {update}")
        where, wparams = self._where(flt)
        target = sql.SQL("SELECT ctid FROM {} WHERE ").format(sql.Identifier(self.name)) + where + (sql.SQL("") if many else sql.SQL(" LIMIT 1"))
        q = (sql.SQL("UPDATE {} SET ").format(sql.Identifier(self.name)) + sql.SQL(", ").join(assignments)
             + sql.SQL(" WHERE ctid IN (") + target + sql.SQL(")") + sql.SQL(" RETURNING id" if categories is not None else ""))
        with self.conn.cursor() as cur:
            cur.execute(q, params + wparams)
            n = cur.rowcount
            if categories is not None:
                for (budget_id,) in cur.fetchall():
                    cur.execute("DELETE FROM budget_allocations WHERE budget_id = %s", (budget_id,))
                    self._insert_allocations(cur, D.allocation_rows(budget_id, categories))
        return Result(matched=n, modified=n)

    def update_one(self, flt, update, upsert=False):
        return self._update(flt, update, many=False)

    def update_many(self, flt, update, upsert=False):
        return self._update(flt, update, many=True)

    def _delete(self, flt, many: bool) -> Result:
        where, params = self._where(flt)
        target = sql.SQL("SELECT ctid FROM {} WHERE ").format(sql.Identifier(self.name)) + where + (sql.SQL("") if many else sql.SQL(" LIMIT 1"))
        q = sql.SQL("DELETE FROM {} WHERE ctid IN (").format(sql.Identifier(self.name)) + target + sql.SQL(")")
        with self.conn.cursor() as cur:
            cur.execute(q, params)
            return Result(deleted=cur.rowcount)

    def delete_one(self, flt):
        return self._delete(flt, many=False)

    def delete_many(self, flt=None):
        return self._delete(flt or {}, many=True)

    def aggregate(self, *_a, **_k):
        raise NotImplementedError(f"pgcompat: aggregate on {self.name} - rewrite this test step in SQL")


class CompatDB:
    """Attribute access like a pymongo Database: db.users, db["goals"], ..."""

    def __init__(self):
        self._pg = psycopg.connect(PG_DSN, autocommit=True)

    def __getattr__(self, name):
        if name.startswith("_"):
            raise AttributeError(name)
        if name not in TABLES:
            raise AttributeError(f"no table {name!r}")
        return PgCollection(self._pg, name)

    def __getitem__(self, name):
        return getattr(self, name)

    def list_collection_names(self):
        return sorted(TABLES)

    def sql(self, query: str, *params):
        """Escape hatch for suites: run raw SQL, return rows as dicts."""
        with self._pg.cursor(row_factory=dict_row) as cur:
            cur.execute(query, params)
            return cur.fetchall() if cur.description else cur.rowcount


class AsyncCollection:
    """Awaitable facade (motor-like) over a collection, for suites that used backend motor collections."""

    def __init__(self, coll):
        self._c = coll

    def __getattr__(self, op):
        target = getattr(self._c, op)

        async def call(*a, **k):
            return target(*a, **k)
        return call


def async_collection(name: str) -> AsyncCollection:
    return AsyncCollection(getattr(get_db(), name))


def get_db() -> CompatDB:
    return CompatDB()


def reset_postgres() -> None:
    """Empty every application table (keeps the schema and alembic_version)."""
    with psycopg.connect(PG_DSN, autocommit=True) as conn:
        names = ", ".join(t.name for t in T.metadata.sorted_tables)
        conn.execute(f"TRUNCATE {names} CASCADE")
