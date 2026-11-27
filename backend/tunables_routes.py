"""Admin API for the tunable numbers and times (see tunables.py).

Moderators can view; admins and super admins can change. A save applies in this process at once and in other workers
within a minute. Every change is written to the admin action log. The record is guarded by a version: a save made from
an older view is a 409 (nothing written), a bad value is a 422 naming each field.
"""
import logging
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict

import tunables
from admin_utils import log_admin_action, require_admin_or_super, require_moderator_or_above

logger = logging.getLogger(__name__)

admin_router = APIRouter(prefix="/api/admin/tunables", tags=["admin", "tunables"])

MAX_LOG_DETAILS = 2000
CONFLICT_MESSAGE = "These settings were changed by someone else. Reload to see them."


class SettingsBody(BaseModel):
    """Loose here: tunables.validate gives one readable error per field, and the version is checked below so that a bad
    one comes out in the same settings_invalid shape."""
    model_config = ConfigDict(extra="forbid")
    values: Any = None
    version: Any = None


def _invalid(errors: dict) -> HTTPException:
    return HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                         detail={"code": "settings_invalid", "errors": errors})


def _show(value: Any) -> str:
    if isinstance(value, dict):
        return ", ".join(f"{k} {_show(v)}" for k, v in value.items())
    if isinstance(value, (list, tuple)):
        return ", ".join(_show(v) for v in value)
    return str(value)


def _details(changes: list) -> str:
    text = "; ".join(f"{key}: {_show(old)} -> {_show(new)}" for key, old, new in changes) or "no changes"
    return text if len(text) <= MAX_LOG_DETAILS else text[:MAX_LOG_DETAILS - 3] + "..."


def _state() -> dict:
    return {"settings": tunables.catalogue(), "version": tunables.version()}


@admin_router.get("")
async def get_tunables(current_admin: dict = Depends(require_moderator_or_above)):
    return _state()


@admin_router.put("")
async def put_tunables(body: SettingsBody, current_admin: dict = Depends(require_admin_or_super)):
    version = body.version
    if not isinstance(version, int) or isinstance(version, bool) or version < 0:
        raise _invalid({"version": "The version must be a whole number, 0 or more"})
    try:
        result = await tunables.save(body.values, version, current_admin["_id"])
    except tunables.SettingsInvalid as e:
        raise _invalid(e.errors)
    except tunables.SettingsConflict:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT,
                            detail={"code": "settings_conflict", "message": CONFLICT_MESSAGE})
    if result["changes"]:  # nothing changed at the current version: no new version, no log line
        await log_admin_action(admin_id=current_admin["_id"], admin_email=current_admin["email"],
                               action="tunables_update", details=_details(result["changes"]))
    return _state()
