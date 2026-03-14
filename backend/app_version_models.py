from pydantic import BaseModel, HttpUrl
from typing import Optional
from datetime import datetime
from enum import Enum


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


class AppVersionUpdate(BaseModel):
    download_url: Optional[str] = None
    release_notes: Optional[str] = None
    is_force_update: Optional[bool] = None
    min_supported_version: Optional[str] = None
    is_active: Optional[bool] = None


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


class VersionCheckResponse(BaseModel):
    is_up_to_date: bool
    force_update: bool          # If True, the app must block the user until updated
    latest_version: str
    download_url: Optional[str] = None
    release_notes: Optional[str] = None
    message: str