"""Admin API for App control: pause features for everyone, maintenance mode (announcements come later).

Moderators can view; admins and super admins can change. A change applies in this process at once and in other
workers within a minute. Every change is written to the admin action log. These routes are never blocked.
"""
from typing import Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict

import app_control
from admin_utils import log_admin_action, require_admin_or_super, require_moderator_or_above
from notification_service import translate

admin_router = APIRouter(prefix="/api/admin/app-control", tags=["admin", "app-control"])

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
