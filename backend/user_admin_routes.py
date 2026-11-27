"""Admin actions on one person: suspend, unsuspend, sign out everywhere, edit the name or currency, send a message.

Admins and super admins act; every success is written to the admin action log. A suspension is the account switch
described in account_guard.py. Nothing here reveals or sets a password or a reset code.
"""
import logging
import uuid
from datetime import UTC, datetime
from typing import Literal, Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Path, status
from sqlalchemy.exc import IntegrityError
from pydantic import BaseModel, ConfigDict, field_validator, model_validator
from starlette.concurrency import run_in_threadpool

import auth_routes
from account_guard import is_suspended
from admin_models import UserDetailResponse
from admin_routes import build_user_detail
from admin_utils import log_admin_action, require_admin_or_super, require_super_admin
from firebase_service import send_push
from email_service import send_email_changed_email
from models import Currency, NormalizedEmail
from sql import devices as devices_db
from sql import notifications as notifications_db
from sql import users as users_db

logger = logging.getLogger(__name__)

admin_router = APIRouter(prefix="/api/admin/users", tags=["admin", "users"])

MAX_REASON = 500
MAX_TITLE = 100  # the Broadcast form's limits
MAX_MESSAGE = 500
MAX_NAME = 100  # the app's own limit (models.ProfileUpdate)


def _conflict(code: str, message: str) -> HTTPException:
    return HTTPException(status_code=status.HTTP_409_CONFLICT, detail={"code": code, "message": message})


class SuspendBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    reason: str

    @field_validator("reason")
    @classmethod
    def _reason(cls, v: str) -> str:
        v = v.strip()
        if not 1 <= len(v) <= MAX_REASON:
            raise ValueError(f"must be 1 to {MAX_REASON} characters")
        return v


class ProfileBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: Optional[str] = None
    default_currency: Optional[Currency] = None

    @field_validator("name")
    @classmethod
    def _name(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        v = v.strip()
        if not v:
            raise ValueError("Name is required")
        if len(v) > MAX_NAME:
            raise ValueError(f"Name must be at most {MAX_NAME} characters")
        return v

    @model_validator(mode="after")
    def _something(self):
        if self.name is None and self.default_currency is None:
            raise ValueError("send a name or a default_currency")
        return self


class EmailBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: NormalizedEmail


class MessageBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str
    message: str
    notification_type: Literal["system_broadcast", "admin_announcement"]

    @field_validator("title", "message")
    @classmethod
    def _not_blank(cls, v: str, info) -> str:
        v = v.strip()
        limit = MAX_TITLE if info.field_name == "title" else MAX_MESSAGE
        if not 1 <= len(v) <= limit:
            raise ValueError(f"must be 1 to {limit} characters")
        return v


async def _person(user_id: str) -> dict:
    user = await users_db.get_user(user_id)
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return user


async def _log(admin: dict, action: str, user: dict, details: Optional[str] = None) -> None:
    await log_admin_action(admin_id=admin["_id"], admin_email=admin["email"], action=action,
                           target_user_id=user["_id"], target_user_email=user["email"], details=details)


@admin_router.post("/{user_id}/suspend")
async def suspend_user(body: SuspendBody, user_id: str = Path(...), current_admin: dict = Depends(require_admin_or_super)):
    user = await _person(user_id)
    now = datetime.now(UTC)
    if not await users_db.suspend(user_id, body.reason, current_admin["_id"], now):
        raise _conflict("already_suspended", "This person is already suspended.")
    await users_db.sign_out_everywhere(user_id)
    await _log(current_admin, "user_suspended", user, body.reason)
    return {"suspended_at": now, "suspended_reason": body.reason}


@admin_router.post("/{user_id}/unsuspend")
async def unsuspend_user(user_id: str = Path(...), current_admin: dict = Depends(require_admin_or_super)):
    user = await _person(user_id)
    if not await users_db.unsuspend(user_id):
        raise _conflict("not_suspended", "This person is not suspended.")
    await _log(current_admin, "user_unsuspended", user)
    return {"message": "Suspension lifted"}


@admin_router.post("/{user_id}/sign-out")
async def sign_out_user(user_id: str = Path(...), current_admin: dict = Depends(require_admin_or_super)):
    user = await _person(user_id)
    devices = len(await devices_db.list_for(user_id))
    await users_db.sign_out_everywhere(user_id)
    await _log(current_admin, "user_signed_out", user, f"{devices} devices")
    return {"devices_removed": devices}


@admin_router.put("/{user_id}/profile", response_model=UserDetailResponse)
async def update_user_profile(body: ProfileBody, user_id: str = Path(...),
                              current_admin: dict = Depends(require_admin_or_super)):
    user = await _person(user_id)
    changes = []
    if body.name is not None:
        new_name = await auth_routes.apply_profile_name(user_id, body.name)  # the app's rule: 400 when too short
        if new_name != user["name"]:
            changes.append(f"name: {user['name']} -> {new_name}")
    if body.default_currency is not None:
        old = user.get("default_currency") or "usd"
        if body.default_currency.value != old:
            await users_db.update_user(user_id, default_currency=body.default_currency.value)
            changes.append(f"default_currency: {old} -> {body.default_currency.value}")
    if changes:
        await _log(current_admin, "user_profile_updated", user, "; ".join(changes))
    return await build_user_detail(await users_db.get_user(user_id))


@admin_router.post("/{user_id}/message")
async def message_user(body: MessageBody, user_id: str = Path(...),
                       current_admin: dict = Depends(require_admin_or_super)):
    user = await _person(user_id)
    if is_suspended(user):
        raise _conflict("user_suspended", "This person is suspended. Unsuspend them first.")
    now = datetime.now(UTC)
    await notifications_db.insert_many([{
        "_id": str(uuid.uuid4()), "user_id": user_id, "type": body.notification_type, "title": body.title,
        "message": body.message, "goal_name": None, "currency": None, "created_at": now, "is_read": False,
    }])
    # The notification is stored: a push that fails must not make this a 500 (the admin would send it twice).
    sent = 0
    try:
        tokens = await devices_db.active_tokens(user_id, now)
        if tokens:
            result = await run_in_threadpool(send_push, tokens, body.title, body.message,
                                             {"type": body.notification_type})
            sent = result.get("success", 0)
            await devices_db.delete_tokens(result.get("unregistered") or [])
    except Exception as e:
        logger.warning(f"Could not push the admin message: {e}")
    await _log(current_admin, "user_message_sent", user, body.title)
    return {"devices": sent}


_NOT_SENT = {
    "recent": "A code was sent less than a minute ago.",
    "hourly_limit": "Too many codes this hour.",
    "locked": "Too many wrong codes; the account is locked for now.",
    "suspended": "This person is suspended.",
}


@admin_router.post("/{user_id}/reset-code")
async def send_reset_code(background_tasks: BackgroundTasks, user_id: str = Path(...),
                          current_admin: dict = Depends(require_admin_or_super)):
    """E-mail the person a reset code (the same one "Forgot password" sends). The admin never sees it."""
    user = await _person(user_id)
    result = await auth_routes.issue_reset_code(user, background_tasks)
    if not result.sent:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail={
            "code": "reset_code_not_sent", "reason": result.reason, "message": _NOT_SENT[result.reason],
            "retry_at": result.retry_at.isoformat() if result.retry_at else None})
    await _log(current_admin, "user_reset_code_sent", user)
    return {"sent": True}


@admin_router.put("/{user_id}/email")
async def change_user_email(body: EmailBody, background_tasks: BackgroundTasks, user_id: str = Path(...),
                            current_admin: dict = Depends(require_super_admin)):
    """Correct the sign-in email (super admin). The person is signed out and the OLD address is told."""
    user = await _person(user_id)
    old, new = user["email"], body.email
    if new == (old or "").strip().lower():
        return {"email": old}
    taken = await users_db.get_user_by_email(new)
    if taken and taken["_id"] != user_id:
        raise _conflict("email_taken", "Another account uses this email.")
    try:
        # A reset code or token issued before the correction must not finish a reset for the new address
        # (the lockout time is kept so a lockout still holds).
        await users_db.update_user(
            user_id, email=new, password_reset_otp=None, password_reset_otp_expiry=None,
            password_reset_token=None, password_reset_token_expiry=None,
            password_reset_attempts=None, password_reset_attempts_since=None)
    except IntegrityError:
        raise _conflict("email_taken", "Another account uses this email.")
    await users_db.sign_out_everywhere(user_id)
    background_tasks.add_task(send_email_changed_email, old, auth_routes.user_language(user))
    await _log(current_admin, "user_email_changed", user, f"{old} -> {new}")
    return {"email": new}
