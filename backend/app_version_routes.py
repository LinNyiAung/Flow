import uuid
from datetime import datetime, UTC
from typing import List, Optional
from packaging.version import Version, InvalidVersion

from fastapi import APIRouter, HTTPException, status, Depends, Query, Path

from admin_utils import (
    log_admin_action,
    require_admin_or_super,
    require_moderator_or_above,
    require_super_admin,
)
from app_version_models import (
    AppVersionCreate,
    AppVersionUpdate,
    AppVersionResponse,
    Platform,
    VersionCheckRequest,
    VersionCheckResponse,
)
from sqlalchemy.exc import IntegrityError
from sql import app_versions as versions_db
from utils import get_current_user

router = APIRouter(tags=["app-versions"])


# ==================== HELPERS ====================

def _parse_version(v: str) -> Version:
    """Parse a version string; raises HTTP 400 on invalid format."""
    try:
        return Version(v)
    except InvalidVersion:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid version string: '{v}'. Use semantic versioning e.g. '2.1.0'."
        )


def _safe_version(v) -> Optional[Version]:
    """Parse a version stored in the DB; returns None (record ignored) if malformed."""
    if not v or not isinstance(v, str):
        return None
    try:
        return Version(v.strip())
    except InvalidVersion:
        return None


def _doc_to_response(doc: dict) -> AppVersionResponse:
    return AppVersionResponse(
        id=doc["_id"],
        version=doc["version"],
        platform=Platform(doc["platform"]),
        download_url=doc["download_url"],
        release_notes=doc.get("release_notes"),
        is_force_update=doc["is_force_update"],
        min_supported_version=doc.get("min_supported_version"),
        is_active=doc["is_active"],
        created_at=doc["created_at"],
        created_by_email=doc["created_by_email"],
        updated_at=doc.get("updated_at"),
    )


# ==================== ADMIN ROUTES (prefix: /api/admin) ====================

admin_router = APIRouter(prefix="/api/admin", tags=["admin", "app-versions"])


@admin_router.post("/app-versions", response_model=AppVersionResponse, status_code=status.HTTP_201_CREATED)
async def create_app_version(
    data: AppVersionCreate,
    current_admin: dict = Depends(require_admin_or_super),
):
    """
    Publish a new app version.
    Set `is_force_update=true` to block users from using the app until they update.
    Set `min_supported_version` to force-update all users on versions below that threshold.
    """
    # Validate version strings
    _parse_version(data.version)
    if data.min_supported_version:
        _parse_version(data.min_supported_version)

    # Check for duplicate version + platform
    existing = await versions_db.find_by_version(data.version, data.platform.value)
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Version {data.version} for platform '{data.platform.value}' already exists.",
        )

    now = datetime.now(UTC)
    doc = {
        "_id": str(uuid.uuid4()),
        "version": data.version,
        "platform": data.platform.value,
        "download_url": data.download_url,
        "release_notes": data.release_notes,
        "is_force_update": data.is_force_update,
        "min_supported_version": data.min_supported_version,
        "is_active": True,
        "created_at": now,
        "created_by_email": current_admin["email"],
        "updated_at": None,
    }

    try:
        await versions_db.insert_version(doc)
    except IntegrityError:
        # unique (version, platform): a concurrent request published it first
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Version {data.version} for platform '{data.platform.value}' already exists.",
        )

    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"],
        action="created_app_version",
        details=f"Version {data.version} ({data.platform.value}) — force_update={data.is_force_update}",
    )

    return _doc_to_response(doc)


@admin_router.get("/app-versions", response_model=List[AppVersionResponse])
async def list_app_versions(
    current_admin: dict = Depends(require_moderator_or_above),
    platform: Optional[Platform] = Query(None),
    active_only: bool = Query(False),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
):
    """List all app versions. Optionally filter by platform or active status."""
    docs = await versions_db.list_versions(platform.value if platform else None, active_only, skip, limit)
    return [_doc_to_response(d) for d in docs]


@admin_router.get("/app-versions/{version_id}", response_model=AppVersionResponse)
async def get_app_version(
    version_id: str = Path(...),
    current_admin: dict = Depends(require_moderator_or_above),
):
    """Get a specific app version by ID."""
    doc = await versions_db.get(version_id)
    if not doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="App version not found")
    return _doc_to_response(doc)


@admin_router.put("/app-versions/{version_id}", response_model=AppVersionResponse)
async def update_app_version(
    data: AppVersionUpdate,
    version_id: str = Path(...),
    current_admin: dict = Depends(require_admin_or_super),
):
    """Update an existing app version (download URL, release notes, force-update flag, etc.)."""
    doc = await versions_db.get(version_id)
    if not doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="App version not found")

    update_fields: dict = {"updated_at": datetime.now(UTC)}
    sent = data.model_fields_set  # fields the client explicitly included (even if null)

    # Non-nullable fields: an explicit null is ignored
    if data.download_url is not None:
        update_fields["download_url"] = data.download_url
    if data.is_force_update is not None:
        update_fields["is_force_update"] = data.is_force_update
    if data.is_active is not None:
        update_fields["is_active"] = data.is_active

    # Nullable fields: explicit null clears the value
    if "release_notes" in sent:
        update_fields["release_notes"] = data.release_notes
    if "min_supported_version" in sent:
        if data.min_supported_version is not None:
            _parse_version(data.min_supported_version)
        update_fields["min_supported_version"] = data.min_supported_version

    await versions_db.update_version(version_id, update_fields)

    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"],
        action="updated_app_version",
        details=f"Updated version ID {version_id}: {list(update_fields.keys())}",
    )

    updated = await versions_db.get(version_id)
    return _doc_to_response(updated)


@admin_router.delete("/app-versions/{version_id}", status_code=status.HTTP_200_OK)
async def delete_app_version(
    version_id: str = Path(...),
    current_admin: dict = Depends(require_super_admin),
):
    """Delete an app version record (Super Admin only)."""
    if await versions_db.delete_version(version_id) == 0:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="App version not found")

    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"],
        action="deleted_app_version",
        details=f"Deleted version ID {version_id}",
    )

    return {"message": "App version deleted successfully"}


# ==================== USER-FACING ROUTE (prefix: /api) ====================

user_router = APIRouter(prefix="/api", tags=["app-versions"])


@user_router.post("/app/check-version", response_model=VersionCheckResponse)
async def check_app_version(
    payload: VersionCheckRequest,
    current_user: dict = Depends(get_current_user),
):
    """
    Called by the mobile app on startup (or resume).
    Returns whether the user needs to update, and whether it is forced.

    Logic:
    1. Load all ACTIVE versions for the user's platform (or "all").
    2. If none exist → user is up to date (nothing to enforce).
    3. latest_version / download_url / release_notes come from the highest version.
    4. Force update if:
       - ANY active version newer than current_version has `is_force_update`, OR
       - current_version is below the HIGHEST `min_supported_version` among active versions.
    Versions are compared numerically (2.10.0 > 2.1.0). A malformed current_version
    is rejected with 422 by the request model.
    """
    current_v = _parse_version(payload.current_version)

    # Query: active versions matching the device platform OR "all"
    docs = await versions_db.active_for_platforms([payload.platform.value, Platform.ALL.value], limit=500)

    # Ignore any malformed records already in the DB instead of 500-ing
    parsed = [(v, d) for d in docs if (v := _safe_version(d.get("version"))) is not None]

    if not parsed:
        # No version info published yet — let the user through
        return VersionCheckResponse(
            is_up_to_date=True,
            force_update=False,
            latest_version=payload.current_version,
            message="Your app is up to date.",
        )

    # Highest version among active records
    latest_v, latest_doc = max(parsed, key=lambda pair: pair[0])
    latest_version = latest_doc["version"]

    # Any newer active version flagged as force update?
    force_update = any(v > current_v and d.get("is_force_update") for v, d in parsed)

    # Highest min_supported_version among all active records
    min_versions = [
        mv for _, d in parsed
        if (mv := _safe_version(d.get("min_supported_version"))) is not None
    ]
    if min_versions and current_v < max(min_versions):
        force_update = True

    is_up_to_date = current_v >= latest_v and not force_update

    if is_up_to_date:
        return VersionCheckResponse(
            is_up_to_date=True,
            force_update=False,
            latest_version=latest_version,
            message="Your app is up to date.",
        )

    return VersionCheckResponse(
        is_up_to_date=False,
        force_update=force_update,
        latest_version=latest_version,
        download_url=latest_doc["download_url"],
        release_notes=latest_doc.get("release_notes"),
        message=(
            f"A new version ({latest_version}) is available. Please update to continue."
            if force_update
            else f"A new version ({latest_version}) is available."
        ),
    )