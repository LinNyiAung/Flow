"""Contact details: Viber numbers (a user's on an upgrade request, the owner's in the plan settings) and the owner's
email, Telegram number or username, Facebook page link and Messenger link. One normalisation rule for each, shared by
the API and the admin settings (the admin panel and the app mirror them: admin/src/PlansSettings.jsx,
frontend/lib/utils/contact_details.dart)."""
import re
from typing import Optional, Tuple

# What a person may type between the digits: spaces, dashes, dots and parentheses.
_SEPARATORS = re.compile(r"[\s\-.()]")
_E164 = re.compile(r"\+[0-9]{8,15}")
_EMAIL = re.compile(r"[^@\s]+@[^@\s]+\.[^@\s]+")
# A Telegram input that is a phone number: digits (after the separators are dropped) with an optional leading `+`.
_PHONE_LIKE = re.compile(r"\+?[0-9]+")
# A Telegram username (5 to 32 of a-z A-Z 0-9 _, starting with a letter), alone, after `@`, or in a t.me /
# telegram.me link (http or https, or no scheme). Case-insensitive on the scheme and host; ASCII only.
_TELEGRAM = re.compile(r"(?:(?:https?://)?(?:t|telegram)\.me/|@)?([a-z][a-z0-9_]{4,31})", re.IGNORECASE | re.ASCII)
_SCHEME = re.compile(r"([A-Za-z][A-Za-z0-9+.\-]*)://")

MAX_EMAIL_LENGTH = 254
MAX_LINK_LENGTH = 300

VIBER_HINT = "Enter a Viber number with its country code, like +959123456789 (or 09 123 456 789)"
TELEGRAM_HINT = "Enter a phone number with the country code (like +959123456789) or a username (like @yourname)"
FACEBOOK_HINT = "Enter your Facebook page link, like facebook.com/yourpage (a facebook.com, fb.com or fb.me link)"
MESSENGER_HINT = "Enter your Messenger link, like m.me/yourpage (an m.me or messenger.com link)"

FACEBOOK_HOSTS = ("facebook.com", "www.facebook.com", "m.facebook.com", "web.facebook.com",
                  "fb.com", "www.fb.com", "fb.me")
MESSENGER_HOSTS = ("m.me", "messenger.com", "www.messenger.com")


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


def normalize_telegram(value: Optional[str]) -> Optional[str]:
    """The owner's Telegram as a phone number (`+` and 8 to 15 digits, the normalize_viber rule, so `09…` becomes
    `+959…`) or a username (`@name`, in the case it was typed); None for an empty one. ValueError (readable) otherwise.

    An input that is only digits (after spaces, dashes, dots and parentheses are dropped) with an optional leading `+`
    is a number. Anything else is a username: `@name`, `name`, or a `t.me/name` / `telegram.me/name` link with or
    without `http(s)://`; the name is 5 to 32 of a-z A-Z 0-9 _ and starts with a letter.
    """
    text = (value or "").strip()
    if not _SEPARATORS.sub("", text):
        return None
    if _PHONE_LIKE.fullmatch(_SEPARATORS.sub("", text)):
        try:
            return normalize_viber(text)
        except ValueError:
            raise ValueError(TELEGRAM_HINT) from None
    m = _TELEGRAM.fullmatch(text)
    if not m:
        raise ValueError(TELEGRAM_HINT)
    return "@" + m.group(1)


def _split_link(text: str) -> Tuple[Optional[str], str, str]:
    """(scheme or None, authority, the rest from the first `/`, `?` or `#` on) of a link typed with or without
    `scheme://`."""
    m = _SCHEME.match(text)
    scheme, rest = (m.group(1), text[m.end():]) if m else (None, text)
    cut = next((i for i, ch in enumerate(rest) if ch in "/?#"), len(rest))
    return scheme, rest[:cut], rest[cut:]


def _normalize_link(value: Optional[str], hosts: Tuple[str, ...], hint: str) -> Optional[str]:
    """An http(s) link on one of `hosts` with a page path, as `https://` + host (lower case) + the path, query and
    fragment as typed; None for an empty one. ValueError (readable, `hint`) for any other host, no path, a user name
    or a port, spaces, a scheme other than http/https, or more than MAX_LINK_LENGTH characters."""
    text = (value or "").strip()
    if not text:
        return None
    if len(text) > MAX_LINK_LENGTH:
        raise ValueError(f"The link is too long (the limit is {MAX_LINK_LENGTH} characters)")
    if re.search(r"\s", text):
        raise ValueError("A link cannot contain spaces")
    scheme, authority, rest = _split_link(text)
    if scheme is not None and scheme.lower() not in ("http", "https"):
        raise ValueError("Use an http or https link")
    host = authority.lower()
    # A user name (user@host) or a port (host:443) makes the authority differ from every allowed host.
    if host not in hosts:
        raise ValueError(hint)
    path = re.split(r"[?#]", rest, maxsplit=1)[0]
    if path in ("", "/"):
        raise ValueError(hint)
    url = f"https://{host}{rest}"
    if len(url) > MAX_LINK_LENGTH:
        raise ValueError(f"The link is too long (the limit is {MAX_LINK_LENGTH} characters)")
    return url


def normalize_facebook_url(value: Optional[str]) -> Optional[str]:
    """The owner's Facebook page link (facebook.com, www./m./web.facebook.com, fb.com, www.fb.com or fb.me, with a
    page path) as an `https://` URL; None for an empty one. ValueError (readable) otherwise. See _normalize_link."""
    return _normalize_link(value, FACEBOOK_HOSTS, FACEBOOK_HINT)


def normalize_messenger_url(value: Optional[str]) -> Optional[str]:
    """The owner's Messenger link (m.me, messenger.com or www.messenger.com, with a page path) as an `https://` URL;
    None for an empty one. ValueError (readable) otherwise. See _normalize_link."""
    return _normalize_link(value, MESSENGER_HOSTS, MESSENGER_HINT)


def link_display(url: str) -> str:
    """A stored link as people read it: without the leading `https://` (facebook.com/yourpage)."""
    return url[len("https://"):] if url.startswith("https://") else url
