"""
Helpers for keeping non-finite numbers (NaN / +-Infinity) out of responses.

JSON has no representation for NaN or +-Infinity: Starlette's JSONResponse uses
json.dumps(allow_nan=False), so a single non-finite float anywhere in a response body
turns the whole request into a 500. New input is validated (allow_inf_nan=False on money
fields), but legacy rows may still hold such amounts, so read paths use these helpers.
"""
import logging
import math
from datetime import date, datetime
from decimal import Decimal
from enum import Enum
from typing import Any

logger = logging.getLogger(__name__)


def is_finite_number(value: Any) -> bool:
    """True for real (non-bool) ints/floats/Decimals that are finite."""
    if isinstance(value, bool):
        return False
    if isinstance(value, int):
        return True
    if isinstance(value, float):
        return math.isfinite(value)
    if isinstance(value, Decimal):
        return value.is_finite()
    return False


def finite_or(value: Any, default: float = 0.0) -> Any:
    """value if it is a finite number, else default."""
    return value if is_finite_number(value) else default


def finite_amount_or_none(doc: dict, kind: str = "transaction") -> Any:
    """
    The document's "amount" if finite, else None (and a warning naming the document id) so
    callers can skip the row instead of crashing the whole request.
    """
    amount = (doc or {}).get("amount")
    if is_finite_number(amount):
        return amount
    logger.warning(f"Skipping {kind} {(doc or {}).get('_id')!r} with non-finite/invalid amount {amount!r}")
    print(f"⚠️ Skipping {kind} {(doc or {}).get('_id')!r} with non-finite/invalid amount {amount!r}")
    return None


def json_safe(value: Any, _depth: int = 0) -> Any:
    """
    Recursively convert a value into something json.dumps(allow_nan=False) accepts:
    non-finite floats become the strings "NaN" / "Infinity" / "-Infinity", bytes are
    decoded, datetimes become ISO strings and anything else unknown becomes str(value).
    """
    if _depth > 50:
        return "..."
    if value is None or isinstance(value, (bool, str, int)):
        return value
    if isinstance(value, float):
        if math.isnan(value):
            return "NaN"
        if math.isinf(value):
            return "Infinity" if value > 0 else "-Infinity"
        return value
    if isinstance(value, Decimal):
        return json_safe(float(value), _depth + 1) if value.is_finite() else str(value)
    if isinstance(value, Enum):
        return json_safe(value.value, _depth + 1)
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    if isinstance(value, dict):
        return {str(k): json_safe(v, _depth + 1) for k, v in value.items()}
    if isinstance(value, (list, tuple, set, frozenset)):
        return [json_safe(v, _depth + 1) for v in value]
    try:
        return str(value)
    except Exception:
        return repr(type(value))


try:
    from fastapi.responses import JSONResponse as _JSONResponse
except Exception:  # pragma: no cover - fastapi is always installed for the app
    _JSONResponse = None

if _JSONResponse is not None:
    class SafeJSONResponse(_JSONResponse):
        """
        JSONResponse that never fails on non-finite floats: if the strict encoding fails
        (NaN / +-inf somewhere in the content) the content is passed through json_safe
        and re-encoded, and a warning is logged, instead of the request becoming a 500.
        Used as the app's default_response_class (safety net; read paths also sanitise).
        """

        def render(self, content: Any) -> bytes:
            try:
                return super().render(content)
            except (ValueError, TypeError) as e:
                logger.warning(f"Response contained non-JSON-compliant values ({e}); sanitising")
                print(f"⚠️ Response contained non-JSON-compliant values ({e}); sanitising")
                return super().render(json_safe(content))
