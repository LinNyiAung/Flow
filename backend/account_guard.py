"""A suspended account: an admin has switched the person's sign-in off.

Refused with HTTP 423 and {"detail": {"code": "account_suspended", "message": <text in the person's language>}} at
sign-in and on every authenticated request (utils.get_current_user). Never 401 or 403, so the app can tell a
suspension from an expired session. users.suspended_at is the one source of truth (NULL: not suspended).
"""
from typing import Any, Mapping

from fastapi import HTTPException

from notification_service import translate
from plans.access import user_language

SUSPENDED_CODE = "account_suspended"


def is_suspended(user: Mapping[str, Any]) -> bool:
    return user.get("suspended_at") is not None


def suspended_error(user: Mapping[str, Any]) -> HTTPException:
    return HTTPException(423, {"code": SUSPENDED_CODE,
                               "message": translate("account_suspended_msg", user_language(user))})
