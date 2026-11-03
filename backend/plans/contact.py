"""Contact details: Viber numbers (a user's on an upgrade request, the owner's in the plan settings) and the owner's
email. One normalisation rule for the Viber number, shared by the API and the admin settings."""
import re
from typing import Optional

# What a person may type between the digits: spaces, dashes, dots and parentheses.
_SEPARATORS = re.compile(r"[\s\-.()]")
_E164 = re.compile(r"\+[0-9]{8,15}")
_EMAIL = re.compile(r"[^@\s]+@[^@\s]+\.[^@\s]+")

MAX_EMAIL_LENGTH = 254

VIBER_HINT = "Enter a Viber number with its country code, like +959123456789 (or 09 123 456 789)"


def normalize_viber(value: Optional[str]) -> Optional[str]:
    """A Viber number as `+` and 8 to 15 digits, or None for an empty one. ValueError (readable) when it is not a number.

    Spaces, dashes, dots and parentheses are dropped; one leading `+` is allowed; a Myanmar local number
    (`09…`) becomes `+959…`.
    """
    raw = _SEPARATORS.sub("", value or "")
    if not raw:
        return None
    if raw.startswith("09"):
        raw = "+95" + raw[1:]
    if not _E164.fullmatch(raw):
        raise ValueError(VIBER_HINT)
    return raw


def normalize_email(value: Optional[str]) -> Optional[str]:
    """The owner's email, stripped; None for an empty one. ValueError (readable) when it does not look like an email."""
    text = (value or "").strip()
    if not text:
        return None
    if len(text) > MAX_EMAIL_LENGTH or not _EMAIL.fullmatch(text):
        raise ValueError("Enter a valid email address")
    return text
