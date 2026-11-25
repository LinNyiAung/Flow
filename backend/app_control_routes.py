"""Admin API for App control: pause features for everyone, maintenance mode, announcements; and the public config
endpoint the app reads (GET /api/app/config).

Moderators can view; admins and super admins can change. A change applies in this process at once and in other
workers within a minute. Every change is written to the admin action log. These routes are never blocked.
"""
import logging
from datetime import UTC, datetime
from typing import Dict, List, Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Path, Query, status
from pydantic import BaseModel, ConfigDict

import app_control
import utils
from admin_utils import log_admin_action, require_admin_or_super, require_moderator_or_above
from notification_service import translate
from plans.access import effective_plan
from sql import app_control as app_control_db
from sql import users as users_db

logger = logging.getLogger(__name__)

admin_router = APIRouter(prefix="/api/admin/app-control", tags=["admin", "app-control"])
public_router = APIRouter(prefix="/api/app", tags=["app-control"])

MAX_LOG_DETAILS = 2000


class SwitchBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    paused: bool = False
    message_en: str = ""
    message_my: str = ""


class MaintenanceBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    on: bool = False
    message_en: str = ""
    message_my: str = ""
    back_by: Optional[str] = None
    testers: List[str] = []


class SettingsBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    switches: Dict[str, SwitchBody] = {}
    maintenance: MaintenanceBody = MaintenanceBody()


def _changes(before: dict, after: dict) -> str:
    out = []
    for key in app_control.SWITCHES:
        b, a = before["switches"][key], after["switches"][key]
        if b["paused"] != a["paused"]:
            out.append(f"{'paused' if a['paused'] else 'resumed'}: {key}")
        elif b != a:
            out.append(f"message changed: {key}")
    bm, am = before["maintenance"], after["maintenance"]
    if bm["on"] != am["on"]:
        out.append(f"maintenance: {'on' if am['on'] else 'off'}")
    elif bm != am:
        out.append("maintenance settings changed")
    text = "; ".join(out) if out else "no changes"
    return text if len(text) <= MAX_LOG_DETAILS else text[:MAX_LOG_DETAILS - 3] + "..."


@admin_router.get("")
async def get_app_control(current_admin: dict = Depends(require_moderator_or_above)):
    return {"settings": app_control.snapshot(),
            "switches": [{"key": k, "name_en": translate(f"app_switch_{k}", "en")} for k in app_control.SWITCHES]}


@admin_router.put("")
async def put_app_control(body: SettingsBody, current_admin: dict = Depends(require_admin_or_super)):
    before = app_control.snapshot()
    try:
        after = await app_control.save(body.model_dump(), current_admin["_id"])
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e))
    await log_admin_action(admin_id=current_admin["_id"], admin_email=current_admin["email"],
                           action="app_control_update", details=_changes(before, after))
    return after


# ==================== ANNOUNCEMENTS ====================

class AnnouncementBody(BaseModel):
    """Checked by app_control.validate_announcement (one readable 422), so the fields are loose here."""
    model_config = ConfigDict(extra="forbid")
    text_en: Optional[str] = None
    text_my: Optional[str] = None
    style: Optional[str] = None
    link_url: Optional[str] = None
    link_label_en: Optional[str] = None
    link_label_my: Optional[str] = None
    plans: List[str] = []
    starts_at: Optional[str] = None
    ends_at: Optional[str] = None


def _clean_announcement(body: AnnouncementBody) -> dict:
    try:
        return app_control.validate_announcement(body.model_dump())
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e))


def _log_text(row: dict) -> str:
    text = f"{row['id']}: {row['text_en']}"
    return text if len(text) <= MAX_LOG_DETAILS else text[:MAX_LOG_DETAILS - 3] + "..."


@admin_router.get("/announcements")
async def list_announcements(current_admin: dict = Depends(require_moderator_or_above)):
    return await app_control_db.list_announcements()


@admin_router.post("/announcements")
async def create_announcement(body: AnnouncementBody, current_admin: dict = Depends(require_admin_or_super)):
    row = await app_control_db.create_announcement({**_clean_announcement(body), "created_by": current_admin["email"]})
    await log_admin_action(admin_id=current_admin["_id"], admin_email=current_admin["email"],
                           action="announcement_create", details=_log_text(row))
    return row


@admin_router.put("/announcements/{announcement_id}")
async def update_announcement(body: AnnouncementBody, announcement_id: str = Path(...),
                              current_admin: dict = Depends(require_admin_or_super)):
    row = await app_control_db.update_announcement(announcement_id, _clean_announcement(body))
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Announcement not found")
    await log_admin_action(admin_id=current_admin["_id"], admin_email=current_admin["email"],
                           action="announcement_update", details=_log_text(row))
    return row


@admin_router.delete("/announcements/{announcement_id}")
async def delete_announcement(announcement_id: str = Path(...), current_admin: dict = Depends(require_admin_or_super)):
    if not await app_control_db.delete_announcement(announcement_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Announcement not found")
    await log_admin_action(admin_id=current_admin["_id"], admin_email=current_admin["email"],
                           action="announcement_delete", details=announcement_id)
    return {"message": "Announcement deleted"}


# ==================== CONFIG THE APP READS ====================

async def _signed_in_user(authorization: Optional[str]) -> Optional[dict]:
    """The user of a valid bearer token, or None: a missing, invalid or unknown token means signed out, never a 401."""
    try:
        scheme, _, token = (authorization or "").partition(" ")
        if scheme.lower() != "bearer" or not token.strip():
            return None
        email = utils._decode_user_token(token.strip())["sub"]
        return await users_db.get_user_by_email(email)
    except Exception:  # noqa: BLE001 - any failure is "signed out"
        return None


@public_router.get("/config")
async def app_config(lang: str = Query("en"), authorization: Optional[str] = Header(None)):
    """What the app reads at start and on resume: maintenance, the paused features and the live announcement.

    No token needed: a signed-out caller gets maintenance and the paused list but no announcement."""
    lang = "my" if lang == "my" else "en"
    user = await _signed_in_user(authorization)
    on = app_control.maintenance_on()
    back_by = app_control.maintenance_back_by()
    announcement = None
    if user is not None:
        row = await app_control_db.live_announcement(effective_plan(user), datetime.now(UTC))
        if row is not None:
            link = row["link_url"]
            announcement = {
                "id": row["id"], "updated_at": row["updated_at"], "style": row["style"],
                "text": row[f"text_{lang}"], "link_url": link,
                "link_label": (row[f"link_label_{lang}"] or translate("announcement_open", lang)) if link else None,
            }
    return {
        "maintenance": {"on": on, "message": app_control.maintenance_message(lang),
                        "back_by": back_by.isoformat() if back_by else None,
                        "can_enter": (not on) or app_control.is_tester(user["email"] if user else None)},
        "paused": {k: app_control.paused_message(k, lang) for k in app_control.SWITCHES if app_control.is_paused(k)},
        "announcement": announcement,
    }
