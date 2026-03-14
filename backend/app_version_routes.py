import uuid
from datetime import datetime, UTC
from typing import List, Optional
from packaging.version import Version, InvalidVersion

from fastapi import APIRouter, HTTPException, status, Depends, Query, Path

from admin_utils import (
    get_current_admin,
    log_admin_action,
    require_admin_or_super,
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
from database import app_versions_collection
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
    existing = await app_versions_collection.find_one({
        "version": data.version,
        "platform": data.platform.value,
    })
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Version {data.version} for platform '{data.platform}' already exists.",
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

    await app_versions_collection.insert_one(doc)

    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"],
        action="created_app_version",
        details=f"Version {data.version} ({data.platform}) — force_update={data.is_force_update}",
    )

    return _doc_to_response(doc)


@admin_router.get("/app-versions", response_model=List[AppVersionResponse])
async def list_app_versions(
    current_admin: dict = Depends(get_current_admin),
    platform: Optional[Platform] = Query(None),
    active_only: bool = Query(False),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
):
    """List all app versions. Optionally filter by platform or active status."""
    query: dict = {}
    if platform:
        query["platform"] = platform.value
    if active_only:
        query["is_active"] = True

    cursor = app_versions_collection.find(query).sort("created_at", -1).skip(skip).limit(limit)
    docs = await cursor.to_list(length=limit)
    return [_doc_to_response(d) for d in docs]


@admin_router.get("/app-versions/{version_id}", response_model=AppVersionResponse)
async def get_app_version(
    version_id: str = Path(...),
    current_admin: dict = Depends(get_current_admin),
):
    """Get a specific app version by ID."""
    doc = await app_versions_collection.find_one({"_id": version_id})
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
    doc = await app_versions_collection.find_one({"_id": version_id})
    if not doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="App version not found")

    update_fields: dict = {"updated_at": datetime.now(UTC)}

    if data.download_url is not None:
        update_fields["download_url"] = data.download_url
    if data.release_notes is not None:
        update_fields["release_notes"] = data.release_notes
    if data.is_force_update is not None:
        update_fields["is_force_update"] = data.is_force_update
    if data.min_supported_version is not None:
        _parse_version(data.min_supported_version)
        update_fields["min_supported_version"] = data.min_supported_version
    if data.is_active is not None:
        update_fields["is_active"] = data.is_active

    await app_versions_collection.update_one({"_id": version_id}, {"$set": update_fields})

    await log_admin_action(
        admin_id=current_admin["_id"],
        admin_email=current_admin["email"],
        action="updated_app_version",
        details=f"Updated version ID {version_id}: {list(update_fields.keys())}",
    )

    updated = await app_versions_collection.find_one({"_id": version_id})
    return _doc_to_response(updated)


@admin_router.delete("/app-versions/{version_id}", status_code=status.HTTP_200_OK)
async def delete_app_version(
    version_id: str = Path(...),
    current_admin: dict = Depends(require_super_admin),
):
    """Delete an app version record (Super Admin only)."""
    result = await app_versions_collection.delete_one({"_id": version_id})
    if result.deleted_count == 0:
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
    1. Find the latest ACTIVE version for the user's platform (or "all").
    2. If no version record exists → user is up to date (nothing to enforce).
    3. Compare current_version with latest_version.
    4. Force update if:
       - `is_force_update` is True on the latest record, OR
       - `min_supported_version` is set and current_version is below it.
    """
    _parse_version(payload.current_version)

    # Query: active versions matching the device platform OR "all"
    cursor = app_versions_collection.find({
        "platform": {"$in": [payload.platform.value, Platform.ALL.value]},
        "is_active": True,
    }).sort("created_at", -1)

    docs = await cursor.to_list(length=100)

    if not docs:
        # No version info published yet — let the user through
        return VersionCheckResponse(
            is_up_to_date=True,
            force_update=False,
            latest_version=payload.current_version,
            message="Your app is up to date.",
        )

    # Pick the highest version among active records
    latest_doc = max(docs, key=lambda d: Version(d["version"]))
    latest_version = latest_doc["version"]

    current_v = Version(payload.current_version)
    latest_v = Version(latest_version)

    is_up_to_date = current_v >= latest_v

    # Determine if this must be a forced update
    force_update = False
    if not is_up_to_date:
        if latest_doc.get("is_force_update"):
            force_update = True
        elif latest_doc.get("min_supported_version"):
            min_v = Version(latest_doc["min_supported_version"])
            if current_v < min_v:
                force_update = True

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