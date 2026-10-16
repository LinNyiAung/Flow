"""Admin accounts and the admin audit log."""
import uuid
from datetime import datetime, UTC
from typing import Any, Dict, List, Optional

from sqlalchemy import delete, func, insert, select, update

from sql.db import execute, fetch_all, fetch_one, fetch_value, write_returning
from sql.docs import row_to_doc, rows_to_docs
from sql.tables import admin_action_logs, admins


def _row(doc: Dict[str, Any]) -> Dict[str, Any]:
    return {("id" if k == "_id" else k): v for k, v in doc.items()}


async def count_admins() -> int:
    return await fetch_value(select(func.count()).select_from(admins))


async def get_admin_by_id(admin_id: str) -> Optional[Dict[str, Any]]:
    return row_to_doc(await fetch_one(select(admins).where(admins.c.id == admin_id)))


async def get_admin_by_email(email: str) -> Optional[Dict[str, Any]]:
    """Case-insensitive lookup (e-mails are unique on lower(email))."""
    normalized = (email or "").strip().lower()
    if not normalized:
        return None
    return row_to_doc(await fetch_one(select(admins).where(func.lower(admins.c.email) == normalized)))


async def list_admins() -> List[Dict[str, Any]]:
    return rows_to_docs(await fetch_all(select(admins).order_by(admins.c.created_at)))


async def insert_admin(doc: Dict[str, Any]) -> None:
    await execute(insert(admins).values(**_row(doc)))


async def delete_admin(admin_id: str) -> int:
    return await execute(delete(admins).where(admins.c.id == admin_id))


async def set_last_login(admin_id: str, when: datetime) -> None:
    await execute(update(admins).where(admins.c.id == admin_id).values(last_login=when))


async def change_password(admin_id: str, password_hash: str) -> Optional[Dict[str, Any]]:
    """Store the new hash and bump password_version (revokes older tokens); returns the updated admin."""
    stmt = (
        update(admins).where(admins.c.id == admin_id)
        .values(password=password_hash, password_changed_at=datetime.now(UTC),
                password_version=admins.c.password_version + 1)
        .returning(*admins.c)
    )
    return row_to_doc(await write_returning(stmt))


async def update_profile(admin_id: str, fields: Dict[str, Any], bump_version: bool) -> None:
    values = dict(fields)
    if bump_version:
        values["password_version"] = admins.c.password_version + 1
    await execute(update(admins).where(admins.c.id == admin_id).values(**values))


async def log_action(admin_id: str, admin_email: str, action: str, target_user_id: Optional[str] = None,
                     target_user_email: Optional[str] = None, details: Optional[str] = None) -> None:
    await execute(insert(admin_action_logs).values(
        id=str(uuid.uuid4()), admin_id=admin_id, admin_email=admin_email, action=action,
        target_user_id=target_user_id, target_user_email=target_user_email, details=details,
        timestamp=datetime.now(UTC),
    ))


async def list_logs(skip: int, limit: int) -> List[Dict[str, Any]]:
    stmt = (select(admin_action_logs)
            .order_by(admin_action_logs.c.timestamp.desc(), admin_action_logs.c.id)
            .offset(skip).limit(limit))
    return rows_to_docs(await fetch_all(stmt))
