"""Admin API for the editable server texts (the notification texts and the two emails).

Moderators can view; admins and super admins can change. A change applies in this process at once and in other
workers within a minute. Every save and reset is written to the admin action log. Each save and reset names the
version the editor saw; a mismatch is a 409 so two admins never overwrite each other unseen.
"""
import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Path, Query, status
from pydantic import BaseModel, ConfigDict

import text_overrides
from admin_utils import log_admin_action, require_admin_or_super, require_moderator_or_above

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/admin/texts", tags=["admin", "texts"])

MAX_LOG_DETAILS = 2000
_CONFLICT = {"code": "text_conflict", "message": "This text was changed by someone else. Reload to see it."}


class TextBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    text: str
    version: Optional[int] = None


def _cut(text: str) -> str:
    return text if len(text) <= MAX_LOG_DETAILS else text[:MAX_LOG_DETAILS - 3] + "..."


def _check_target(key: str, lang: str) -> dict:
    known = text_overrides.defaults()
    if key not in known or lang not in text_overrides.LANGS or lang not in known[key]:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Text not found")
    return known[key]


def _override(row: Optional[dict]) -> Optional[dict]:
    if row is None:
        return None
    return {"text": row["text"], "version": row["version"], "default_changed": row["default_changed"],
            "updated_by": row.get("updated_by"), "updated_at": row.get("updated_at")}


@router.get("")
async def list_texts(current_admin: dict = Depends(require_moderator_or_above)):
    stored = text_overrides.rows()
    out = []
    for key, default in text_overrides.defaults().items():
        out.append({
            "key": key,
            "area": text_overrides.area(key),
            "placeholders": sorted(text_overrides.placeholders(key)),
            "default": {lang: default.get(lang) for lang in text_overrides.LANGS},
            "override": {lang: _override(stored.get((key, lang))) for lang in text_overrides.LANGS},
        })
    out.sort(key=lambda t: (t["area"], t["key"]))
    return {"texts": out}


@router.put("/{key}/{lang}")
async def put_text(body: TextBody, key: str = Path(...), lang: str = Path(...),
                   current_admin: dict = Depends(require_admin_or_super)):
    default = _check_target(key, lang)
    old = text_overrides.rows().get((key, lang))
    try:
        await text_overrides.save(key, lang, body.text, body.version, current_admin["email"])
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e))
    except text_overrides.TextConflict:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=_CONFLICT)
    row = text_overrides.rows()[(key, lang)]
    before = old["text"] if old else default[lang]
    await log_admin_action(admin_id=current_admin["_id"], admin_email=current_admin["email"], action="text_update",
                           details=_cut(f"{key}/{lang}: {before} -> {row['text']}"))
    return _override(row)


@router.delete("/{key}/{lang}")
async def delete_text(key: str = Path(...), lang: str = Path(...), version: int = Query(...),
                      current_admin: dict = Depends(require_admin_or_super)):
    _check_target(key, lang)
    old = text_overrides.rows().get((key, lang))
    try:
        done = await text_overrides.reset(key, lang, version, current_admin["email"])
    except text_overrides.TextConflict:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=_CONFLICT)
    if not done:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No override for this text")
    shown = old["text"] if old else "(override)"
    await log_admin_action(admin_id=current_admin["_id"], admin_email=current_admin["email"], action="text_reset",
                           details=_cut(f"{key}/{lang}: {shown} -> default"))
    return {"reset": True}
