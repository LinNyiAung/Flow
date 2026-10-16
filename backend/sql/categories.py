"""Transaction categories (table `categories`), returned in the document shape callers use:
{"_id": "outflow", "categories": [{"main_category": ..., "sub_categories": [...]}, ...]}.
"""
from typing import Any, Dict, Iterable, Optional

from sqlalchemy import func, insert, select

from sql.db import fetch_all, fetch_value, transaction
from sql.docs import categories_docs, category_rows
from sql.tables import categories


async def get_categories_doc(tx_type: str) -> Optional[Dict[str, Any]]:
    rows = await fetch_all(select(categories).where(categories.c.type == tx_type))
    return categories_docs(rows).get(tx_type)


async def seed_default_categories(defaults: Iterable[Dict[str, Any]]) -> bool:
    """Insert the default category tree if the table is empty. Returns True if seeded."""
    if await fetch_value(select(func.count()).select_from(categories)):
        return False
    rows = [r for doc in defaults for r in category_rows(doc["_id"], doc["categories"])]
    async with transaction() as conn:
        await conn.execute(insert(categories), rows)
    return True
