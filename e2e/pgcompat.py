"""Test-only adapter: pymongo-style calls on PostgreSQL tables.

The E2E suites poke the database directly (make a user premium, insert a legacy
transaction, read an OTP hash, ...). During the MongoDB -> PostgreSQL migration each
collection moves to PostgreSQL in turn; `get_db()` returns an object whose attributes
are real pymongo collections for collections still in MongoDB and `PgCollection`s for
migrated ones, so the suites themselves barely change.

Migrated collections are listed in the E2E_PG_COLLECTIONS env var (comma separated,
"all" for every table). Supports the subset of Mongo operators the suites use.
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
from pymongo import MongoClient

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend"))
from sql import docs as D  # noqa: E402
from sql import tables as T  # noqa: E402

PG_DSN = os.environ.get("E2E_PG_DSN", "postgresql://flow@127.0.0.1:54329/flow_e2e")
MONGO_URL = os.environ.get("E2E_MONGO", "mongodb://127.0.0.1:27999")
ALL = {"users", "transactions", "goals", "budgets", "notifications", "notification_preferences", "insights",
       "chat_sessions", "ai_usage", "admins", "admin_action_logs", "feedback", "categories", "app_versions"}


# Collections the backend code already stores in PostgreSQL. Updated with each migration
# step so the suites follow the code; E2E_PG_COLLECTIONS (comma list or "all") overrides.
MIGRATED = {"categories", "admins", "admin_action_logs", "app_versions"}


def migrated() -> set:
    raw = os.environ.get("E2E_PG_COLLECTIONS")
    if raw is None:
        return MIGRATED
    return ALL if raw.strip() == "all" else {c.strip() for c in raw.split(",") if c.strip()}


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
        if self.name == "transactions":
            row = D.transaction_row(doc)
        elif self.name == "insights":
            row = D.insight_row(doc)
        elif self.name == "budgets":
            row = D.budget_row(doc)
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
    def insert_one(self, doc):
        row = self._to_row(doc)
        q = sql.SQL("INSERT INTO {} ({}) VALUES ({})").format(
            sql.Identifier(self.name), sql.SQL(", ").join(map(sql.Identifier, row)), sql.SQL(", ").join(sql.Placeholder() * len(row)))
        with self.conn.cursor() as cur:
            cur.execute(q, list(row.values()))
            if self.name == "budgets":
                for a in D.allocation_rows(row["id"], doc.get("category_budgets") or []):
                    cur.execute("INSERT INTO budget_allocations (budget_id, position, main_category, allocated_amount, spent_amount,"
                                " percentage_used, is_exceeded) VALUES (%(budget_id)s, %(position)s, %(main_category)s, %(allocated_amount)s,"
                                " %(spent_amount)s, %(percentage_used)s, %(is_exceeded)s)", a)
        return Result(inserted_id=doc.get("_id"))

    def insert_many(self, docs, ordered=True):
        ids = [self.insert_one(d).inserted_id for d in docs]
        return Result(inserted_ids=ids)

    def _update(self, flt, update, many: bool) -> Result:
        assignments, params = [], []
        for field, value in (update.get("$set") or {}).items():
            if self.name == "transactions" and field == "recurrence":
                for col, v in D.recurrence_columns(value).items():
                    assignments.append(sql.Identifier(col) + sql.SQL(" = %s")); params.append(v)
                continue
            if self.name == "budgets" and field == "category_budgets":
                raise NotImplementedError("pgcompat: $set category_budgets")
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
        if not assignments:
            raise NotImplementedError(f"pgcompat: update {update}")
        where, wparams = self._where(flt)
        target = sql.SQL("SELECT ctid FROM {} WHERE ").format(sql.Identifier(self.name)) + where + (sql.SQL("") if many else sql.SQL(" LIMIT 1"))
        q = (sql.SQL("UPDATE {} SET ").format(sql.Identifier(self.name)) + sql.SQL(", ").join(assignments)
             + sql.SQL(" WHERE ctid IN (") + target + sql.SQL(")"))
        with self.conn.cursor() as cur:
            cur.execute(q, params + wparams)
            n = cur.rowcount
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
    """Attribute access like a pymongo Database; routes each collection to its store."""

    def __init__(self, mongo_db_name: str = "flow_e2e"):
        self._mongo = MongoClient(MONGO_URL)[mongo_db_name]
        self._pg = psycopg.connect(PG_DSN, autocommit=True)

    def __getattr__(self, name):
        if name.startswith("_"):
            raise AttributeError(name)
        return PgCollection(self._pg, name) if name in migrated() else self._mongo[name]

    def __getitem__(self, name):
        return getattr(self, name)

    def list_collection_names(self):
        return sorted(ALL)

    def sql(self, query: str, *params):
        """Escape hatch for suites: run raw SQL, return rows as dicts."""
        with self._pg.cursor(row_factory=dict_row) as cur:
            cur.execute(query, params)
            return cur.fetchall() if cur.description else cur.rowcount


def get_db(name: str = "flow_e2e") -> CompatDB:
    return CompatDB(name)


def reset_postgres() -> None:
    """Empty every application table (keeps the schema and alembic_version)."""
    with psycopg.connect(PG_DSN, autocommit=True) as conn:
        names = ", ".join(t.name for t in T.metadata.sorted_tables)
        conn.execute(f"TRUNCATE {names} CASCADE")
