import re

from pydantic import BaseModel, field_validator
from typing import Optional
from datetime import datetime
from enum import Enum


# Numeric dotted versions only: "2", "2.1", "2.1.0", "2.1.0.4"
VERSION_PATTERN = re.compile(r"^\d+(\.\d+){0,3}$")


def _validate_version(value: Optional[str], field_name: str, allow_none: bool) -> Optional[str]:
    if value is None:
        if allow_none:
            return None
        raise ValueError(f"{field_name} is required")
    value = value.strip()
    if not VERSION_PATTERN.match(value):
        raise ValueError(
            f"Invalid {field_name} '{value}'. Use numeric dotted versions like '2.1.0'."
        )
    return value


class Platform(str, Enum):
    ANDROID = "android"
    IOS = "ios"
    ALL = "all"


# ==================== ADMIN-FACING MODELS ====================

class AppVersionCreate(BaseModel):
    version: str                        # e.g. "2.1.0"
    platform: Platform = Platform.ALL
    download_url: str                   # Direct APK link, Play Store, App Store URL, etc.
    release_notes: Optional[str] = None
    is_force_update: bool = False       # If True, user MUST update before continuing
    min_supported_version: Optional[str] = None  # Versions below this are force-updated

    @field_validator("version")
    @classmethod
    def _check_version(cls, v: str) -> str:
        return _validate_version(v, "version", allow_none=False)

    @field_validator("min_supported_version")
    @classmethod
    def _check_min_version(cls, v: Optional[str]) -> Optional[str]:
        return _validate_version(v, "min_supported_version", allow_none=True)


class AppVersionUpdate(BaseModel):
    """
    Partial update. Fields omitted are left unchanged.
    release_notes / min_supported_version sent explicitly as null are CLEARED.
    download_url / is_force_update / is_active sent as null are ignored.
    """
    download_url: Optional[str] = None
    release_notes: Optional[str] = None
    is_force_update: Optional[bool] = None
    min_supported_version: Optional[str] = None
    is_active: Optional[bool] = None

    @field_validator("min_supported_version")
    @classmethod
    def _check_min_version(cls, v: Optional[str]) -> Optional[str]:
        return _validate_version(v, "min_supported_version", allow_none=True)


class AppVersionResponse(BaseModel):
    id: str
    version: str
    platform: Platform
    download_url: str
    release_notes: Optional[str] = None
    is_force_update: bool
    min_supported_version: Optional[str] = None
    is_active: bool
    created_at: datetime
    created_by_email: str
    updated_at: Optional[datetime] = None


# ==================== USER-FACING MODELS ====================

class VersionCheckRequest(BaseModel):
    current_version: str        # e.g. "1.0.0" — the version installed on the user's device
    platform: Platform          # "android" or "ios"

    @field_validator("current_version")
    @classmethod
    def _check_current_version(cls, v: str) -> str:
        return _validate_version(v, "current_version", allow_none=False)


class VersionCheckResponse(BaseModel):
    is_up_to_date: bool
    force_update: bool          # If True, the app must block the user until updated
    latest_version: str
    download_url: Optional[str] = None
    release_notes: Optional[str] = None
    message: str
