"""The voice token: what makes a voice entry one use of "entry" although it makes two requests.

transcribe-audio reserves and commits one use for a non-empty transcript and returns a `voice_token` with it. The app
sends that token back as the optional `voice_token` field of extract-from-text / extract-multiple-from-text; when it
is valid for the same user and the same text, the extraction does not reserve a second use.

Token format: "<expiry>.<signature>"
  expiry     unix time in whole seconds (decimal digits) at which the token stops being valid, 15 minutes after issue
  signature  URL-safe base64 (no padding) of HMAC-SHA256(SECRET_KEY, "<user_id>|<sha256 hex of the text>|<expiry>")
The text is the transcript with surrounding whitespace stripped (UTF-8), on both the issuing and the checking side.
The signing key is the app's existing JWT secret (config.settings.SECRET_KEY); without one no token is issued and
none is valid. The token is opaque to the app: it stores it next to the transcript and sends it back unchanged.
"""
import base64
import hashlib
import hmac
import time
from typing import Optional

from config import settings

TTL_SECONDS = 15 * 60
MAX_TOKEN_LENGTH = 512


def _key() -> bytes:
    return (settings.SECRET_KEY or "").encode()


def _signature(user_id: str, text: str, expiry: int) -> str:
    digest = hashlib.sha256(text.strip().encode("utf-8")).hexdigest()
    mac = hmac.new(_key(), f"{user_id}|{digest}|{expiry}".encode("utf-8"), hashlib.sha256).digest()
    return base64.urlsafe_b64encode(mac).rstrip(b"=").decode("ascii")


def issue(user_id: str, transcript: str, now: Optional[float] = None) -> Optional[str]:
    """A token for this user and transcript, valid for 15 minutes; None when the app has no signing key."""
    if not _key():
        return None
    expiry = int((time.time() if now is None else now)) + TTL_SECONDS
    return f"{expiry}.{_signature(user_id, transcript, expiry)}"


def is_valid(token: Optional[str], user_id: str, text: str, now: Optional[float] = None) -> bool:
    """True only for an unexpired token that was issued to this user for exactly this text."""
    if not token or not _key() or len(token) > MAX_TOKEN_LENGTH:
        return False
    expiry_part, dot, signature = token.partition(".")
    if not dot or not expiry_part.isascii() or not expiry_part.isdigit():
        return False
    expiry = int(expiry_part)
    if (time.time() if now is None else now) > expiry:
        return False
    expected = _signature(user_id, text, expiry)
    # compare_digest on bytes: a non-ASCII token must be a mismatch, not a TypeError
    return hmac.compare_digest(expected.encode("ascii"), signature.encode("utf-8"))
