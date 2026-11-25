import io
import json
import os
import re
from PIL import Image, ImageOps
import uuid
import time
from collections import defaultdict
from contextlib import asynccontextmanager
from datetime import date, datetime, timedelta, UTC
from decimal import Decimal
from typing import Dict, List, Optional, Set, Tuple
import logging

# Added BackgroundTasks to imports
from fastapi import APIRouter, File, Form, HTTPException, UploadFile, status, Depends, Query, Path, BackgroundTasks
from fastapi.concurrency import run_in_threadpool
from pydantic import ValidationError

from ai_providers import runner as _runner
from ai_providers.errors import AllProvidersFailed, UnusableAnswer, redact
from ai_providers.types import Completion, Prompt
from utils import get_current_user, get_book_balance, get_book_money_lock
from families.book import Book, book_currency, clean_for_whom, get_book, refuse, require_change_entry, require_writable
import app_control
from plans import quota, voice_token
from plans.access import user_language
from goal_routes import to_cents
from recurring_transaction_service import (
    disable_recurrence_for_parent, disable_recurrence_for_transaction, get_recurring_transaction_preview,
    rearmed_recurrence_pointer, recurrence_schedule_key,
)
from recurrence_models import RecurrenceConfig, RecurrencePreviewRequest, TransactionRecurrence
from budget_service import update_all_book_budgets, update_relevant_budgets
from models import (
    AddedBy, Currency, MultipleTransactionExtraction,TextExtractionRequest, TransactionExtraction,
    TransactionCreate, TransactionResponse, TransactionType,
    TransactionUpdate
)

from notification_service import check_large_transaction

from sql import families as families_db
from sql import transactions as transactions_db
from sql import books as books_db
from sql.categories import get_categories_doc
from sql.db import transaction as db_transaction

from category_matching import is_known_type, normalize_type, parse_positive_amount, snap_category
from tz_utils import WallClock, as_calendar_date, as_wall_clock, local_today
from user_zones import book_zone, user_zone
from finite_utils import finite_amount_or_none, is_finite_number


logger = logging.getLogger(__name__)


router = APIRouter(prefix="/api/transactions", tags=["transactions"])


# ==================== HELPERS ====================

# --- Category validation (categories cached in memory per transaction type) ---
_CATEGORY_CACHE_TTL_SECONDS = 300
_category_cache: Dict[str, tuple] = {}


async def _get_category_map(tx_type: str) -> Optional[Dict[str, List[str]]]:
    """{main_category: [sub_categories]} (configured order) for a transaction type, or None if not configured."""
    now = time.monotonic()
    cached = _category_cache.get(tx_type)
    if cached and now - cached[0] < _CATEGORY_CACHE_TTL_SECONDS:
        return cached[1]
    doc = await get_categories_doc(tx_type)
    cmap = None
    if doc:
        cmap = {
            c["main_category"]: list(c.get("sub_categories") or [])
            for c in doc.get("categories", [])
            if c.get("main_category")
        }
    _category_cache[tx_type] = (now, cmap)
    return cmap


async def _validate_categories(tx_type: str, main_category: str, sub_category: str, prefix: str = "") -> None:
    """Reject (400) categories that don't exist for the transaction type."""
    cmap = await _get_category_map(tx_type)
    if cmap is None:
        logger.warning(f"No categories configured for type '{tx_type}'; skipping category validation")
        return
    if main_category not in cmap:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"{prefix}Invalid main_category '{main_category}' for {tx_type} transactions"
        )
    subs = cmap[main_category]
    if subs and sub_category not in subs:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"{prefix}Invalid sub_category '{sub_category}' for main_category '{main_category}'"
        )


# --- AI extraction post-processing ---
def _safe_confidence(value) -> float:
    try:
        c = float(value)
    except (TypeError, ValueError):
        return 0.0
    if c != c:  # NaN
        return 0.0
    return min(max(c, 0.0), 1.0)


def _extraction_date(value, today: date) -> datetime:
    """Model-produced date (YYYY-MM-DD) as a wall-clock datetime at 00:00; `today` (the person's) if unusable."""
    try:
        return as_wall_clock(as_calendar_date(str(value).strip()[:10]))
    except (TypeError, ValueError):
        return as_wall_clock(today)


# Ways the model may name a supported currency besides its code.
_CURRENCY_ALIASES = {"k": "mmk", "ks": "mmk", "kyat": "mmk", "kyats": "mmk", "ကျပ်": "mmk",
                     "$": "usd", "us$": "usd", "dollar": "usd", "dollars": "usd",
                     "฿": "thb", "baht": "thb", "บาท": "thb"}


def _named_currency(value) -> Optional[str]:
    """The supported currency code `value` names ("MMK", "Ks", "$"...), "" when it names none (missing or blank),
    None when it names a currency the app doesn't record (e.g. "SGD")."""
    text = str(value).strip().lower() if value is not None else ""
    if not text:
        return ""
    text = _CURRENCY_ALIASES.get(text, text)
    return text if text in {c.value for c in Currency} else None


def _extraction_currency(value, default: str) -> Currency:
    for candidate in (_named_currency(value) or None, default, Currency.USD.value):
        try:
            return Currency(str(candidate).strip().lower())
        except (ValueError, AttributeError):
            continue
    return Currency.USD


async def _build_extraction(
    data: dict, default_currency: str, keep_invalid_amount: bool, *, today: date
) -> Optional[TransactionExtraction]:
    """
    Turn one model-produced transaction dict into a TransactionExtraction whose type and
    categories are valid (snapped to the closest configured category, else the type's
    "Other" category), so the result can be sent to create/batch-create as-is.

    Amount <= 0 / missing: returns None (caller drops it) unless keep_invalid_amount, in
    which case amount=0 and confidence=0 are returned with a note in `reasoning`.
    today: the person's today, the date when the model gave none.
    """
    if not isinstance(data, dict):
        return None
    notes = []
    tx_type = normalize_type(data.get("type"))
    raw_main, raw_sub = data.get("main_category"), data.get("sub_category")
    cats = await _get_category_map(tx_type)
    main, sub, adjusted = snap_category(tx_type, raw_main, raw_sub, cats)
    if adjusted:
        logger.info(f"AI extraction: category '{raw_main} / {raw_sub}' snapped to '{main} / {sub}' ({tx_type})")
        notes.append(f"Category '{raw_main} / {raw_sub}' was mapped to '{main} / {sub}'.")

    confidence = _safe_confidence(data.get("confidence"))
    amount, flipped = parse_positive_amount(data.get("amount"))
    if amount is None:
        if not keep_invalid_amount:
            logger.info(f"AI extraction: dropping item without a valid amount: {data.get('amount')!r}")
            return None
        amount, confidence = 0.0, 0.0
        notes.append("Amount could not be determined; please enter it.")
    elif flipped:
        notes.append("Amount was negative; using its absolute value.")

    # No usable type: it was recorded as spending by default. Say so, and don't let it pass as a sure item.
    if not is_known_type(data.get("type")):
        notes.append("It wasn't clear whether this is money in or out; recorded as spending.")
        confidence = min(confidence, 0.5)

    # A currency the app doesn't record (e.g. a 25 SGD receipt): its number must not be saved as the book's currency
    # (25 SGD as K25). Like a missing amount: dropped from a list, or left for the person to enter.
    if amount and _named_currency(data.get("currency")) is None:
        if not keep_invalid_amount:
            logger.info(f"AI extraction: dropping item in an unsupported currency: {data.get('currency')!r}")
            return None
        notes.append(f"This is in {str(data.get('currency')).strip().upper()}, which the app doesn't record; "
                     f"please enter the amount in {(default_currency or 'your currency').upper()}.")
        amount, confidence = 0.0, 0.0

    reasoning = data.get("reasoning")
    if notes:
        reasoning = " ".join([str(reasoning)] + notes) if reasoning else " ".join(notes)

    return TransactionExtraction(
        type=tx_type,
        main_category=main,
        sub_category=sub,
        date=_extraction_date(data.get("date"), today),
        description=data.get("description"),
        amount=amount,
        currency=_extraction_currency(data.get("currency"), default_currency),
        confidence=confidence,
        reasoning=reasoning,
    )


# What speech-to-text models are known to "hear" in silence or noise (whisper's training on subtitled video): a
# transcript that is only one of these is treated as no speech, so it never becomes an entry (and the use is given
# back, as for silence).
_FILLER_TRANSCRIPTS = frozenset({
    "thank you", "thank you very much", "thanks", "thanks for watching", "thank you for watching",
    "please subscribe", "subscribe", "bye", "you", "okay", "ok", "music", "applause", "silence",
})


def _without_filler(transcript: str) -> str:
    """`transcript`, or "" when it is only a known silence filler ("Thank you.", "[Music]", "Thanks for watching!")."""
    words = re.sub(r"[\W_]+", " ", (transcript or "").lower()).strip()
    return "" if not words or words in _FILLER_TRANSCRIPTS else transcript


def _entry_failed(user: dict) -> str:
    """The message an AI entry read (text, voice, receipt) fails with, in the user's language: never the exception's
    own text, which can carry provider or internal details (those go to the server log)."""
    from notification_service import translate
    from plans.access import user_language
    return translate("entry_ai_failed_msg", user_language(user))


# --- The extraction prompts (one source for the rules all three share) ---
def _categories_text(inflow_cats, outflow_cats) -> str:
    text = "AVAILABLE CATEGORIES:\n\nINFLOW:\n"
    for cat in (inflow_cats or {}).get("categories", []):
        text += f"- {cat['main_category']}: {', '.join(cat['sub_categories'])}\n"
    text += "\nOUTFLOW:\n"
    for cat in (outflow_cats or {}).get("categories", []):
        text += f"- {cat['main_category']}: {', '.join(cat['sub_categories'])}\n"
    return text


def _type_rule() -> str:
    return ("TYPE: \"outflow\" for money spent or paid out; \"inflow\" for money received (salary, a sale, a refund, a "
            "gift received). If it is unclear, use \"outflow\" and lower the confidence.")


def _date_rules(today: date) -> str:
    yesterday = today - timedelta(days=1)
    # The past week spelled out: models miscount weekdays ("last Friday" read as a Tuesday in the 2026-11-25 live test).
    past_week = "; ".join(f"{d:%A} {d.isoformat()}" for d in (today - timedelta(days=n) for n in range(1, 8)))
    return f"""DATES:
   - Today is {today:%A}, {today.isoformat()}. Yesterday was {yesterday:%A}, {yesterday.isoformat()}.
   - The past 7 days: {past_week}. For "last <weekday>" (or "on <weekday>"), use the date listed for that weekday.
   - Work out words like "yesterday", "last Friday" or "on the 3rd" from today; never count weekdays yourself.
   - When no date is said or shown, use today ({today.isoformat()}). Never make up a date, and never use a date after
     today unless the text says so."""


def _amount_rules() -> str:
    return """AMOUNTS (never guess one):
   - Use the amount exactly as said or shown, as a plain number with no thousands separators. If no amount is stated,
     or it can't be read, set "amount": 0 and "confidence": 0. Never invent an amount.
   - Myanmar digits ၀ ၁ ၂ ၃ ၄ ၅ ၆ ၇ ၈ ၉ are 0 to 9: "၄,၅၀၀" is 4500.
   - Myanmar number words: ထောင် = 1,000; သောင်း = 10,000; သိန်း = 100,000; သန်း = 1,000,000; ခွဲ adds a half:
     "၅ ထောင်" = 5000, "နှစ်သောင်း" = 20000, "၁ သိန်းခွဲ" or "တစ်သိန်းခွဲ" = 150000.
   - "lakh" is 100,000: "1.5 lakh" = 150000.
   - A short number followed by the letter k means thousands: "5k" = 5000, "2.5k" = 2500, "12K" = 12000. K or Ks
     written before a full amount, or after one with thousands ("K 4,500", "4,500 Ks"), is the kyat sign, not
     thousands."""


def _currency_rules(default_currency: str) -> str:
    return f"""CURRENCY:
   - The app records only "usd", "mmk" and "thb". Use "mmk" for K, Ks, Kyat, ကျပ် or MMK; "usd" for $, USD or
     dollars; "thb" for ฿, THB, baht or บาท.
   - If an amount is in any other currency, return that currency's code as written (for example "SGD"). Never
     convert it, and never relabel it as one of the three.
   - If no currency is mentioned, use the user's default currency: "{default_currency}"."""


def _ground_rule(source: str) -> str:
    return (f"Use only what the {source} says. Never make up an amount, a date, a merchant or an item; when something "
            "is missing, use the defaults above and lower the confidence.")


def _text_prompt(categories_text: str, today: date, default_currency: str) -> str:
    return f"""You are a financial transaction extraction assistant. Extract one transaction from the user's text.

{categories_text}

RULES:
1. {_type_rule()}
2. Select the most appropriate main_category and sub_category from the list above.
3. {_amount_rules()}
4. {_date_rules(today)}
5. Put any description or notes in "description".
6. {_currency_rules(default_currency)}
7. Give a confidence score (0.0-1.0) for how clearly the text states the amount, date and category.
8. In "reasoning", say briefly what you read and why you chose the category.
9. {_ground_rule("text")}

Respond in JSON format:
{{
    "type": "inflow" or "outflow",
    "main_category": "selected main category",
    "sub_category": "selected sub category",
    "date": "YYYY-MM-DD",
    "description": "optional description",
    "amount": 4500,
    "currency": "mmk",
    "confidence": 0.95,
    "reasoning": "why you chose these categories"
}}"""


def _multi_prompt(categories_text: str, today: date, default_currency: str) -> str:
    return f"""You are a financial transaction extraction assistant. Extract EVERY transaction in the user's text (often a
voice note): there may be one or many.

{categories_text}

RULES:
1. Each separate purchase, payment or income is its own item: "lunch 3000 and taxi 5000" is two items. Don't split
   one purchase into its parts, and don't add an item that wasn't said.
2. For each item:
   - {_type_rule()}
   - Select the most appropriate main_category and sub_category from the list above.
   - {_amount_rules()}
   - {_date_rules(today)}
   - Put any description or notes in "description".
   - {_currency_rules(default_currency)} Each item can have its own currency.
   - Give a confidence score (0.0-1.0) for how clearly the item's amount, date and category were said.
   - In "reasoning", say briefly what you heard for this item.
3. {_ground_rule("text")}
4. Give an overall confidence and a brief analysis of what you found.

Respond in JSON format:
{{
    "transactions": [
        {{
            "type": "inflow" or "outflow",
            "main_category": "selected main category",
            "sub_category": "selected sub category",
            "date": "YYYY-MM-DD",
            "description": "optional description",
            "amount": 3000,
            "currency": "mmk",
            "confidence": 0.95,
            "reasoning": "what you heard"
        }}
    ],
    "total_count": 1,
    "overall_confidence": 0.90,
    "analysis": "Found 1 transaction: lunch"
}}"""


def _receipt_prompt(categories_text: str, today: date, default_currency: str) -> str:
    return f"""You are a financial receipt analyzer. Extract the transaction from a photo of a receipt.

{categories_text}

RULES:
1. {_type_rule()} A receipt is almost always "outflow".
2. Select the most appropriate category from the list above, from the merchant and the items.
3. TOTAL: use the final amount payable, the grand total after tax, service charge and discounts. Never use the cash
   handed over ("Cash", "Paid", "Tendered"), the change given back, a subtotal, or a single line item. If the photo
   isn't a receipt, or the total can't be read, set "amount": 0 and "confidence": 0.
4. {_amount_rules()}
5. {_date_rules(today)} Use the date printed on the receipt when there is one.
6. Put the merchant name and a brief description in "description".
7. {_currency_rules(default_currency)} Clues: Myanmar text or Ks prices suggest "mmk", Thai text suggests "thb".
8. Give a confidence score (0.0-1.0) for how clearly you could read the total, the date and the merchant.
9. In "reasoning", say what you saw on the receipt.
10. {_ground_rule("receipt")}

Respond in JSON format:
{{
    "type": "inflow" or "outflow",
    "main_category": "selected main category",
    "sub_category": "selected sub category",
    "date": "YYYY-MM-DD",
    "description": "merchant name and brief description",
    "amount": 12500,
    "currency": "mmk",
    "confidence": 0.95,
    "reasoning": "what you saw on the receipt"
}}"""


# --- AI calls (the transaction_text / transaction_image / transaction_audio provider chains) ---
_AI_UNAVAILABLE = "AI is temporarily unavailable"
_AI_BAD_REQUEST = "The AI service could not process this request. Please check it and try again."

# One extracted transaction, as the prompts ask for it. Explicit and closed (additionalProperties false) so
# the structured-output modes of every provider accept it.
_TX_ITEM_SCHEMA = {
    "type": "object",
    "properties": {
        "type": {"type": "string"},
        "main_category": {"type": "string"},
        "sub_category": {"type": "string"},
        "date": {"type": "string"},
        "description": {"type": "string"},
        "amount": {"type": "number"},
        "currency": {"type": "string"},
        "confidence": {"type": "number"},
        "reasoning": {"type": "string"},
    },
    "required": ["type", "main_category", "sub_category", "date", "description", "amount", "currency",
                 "confidence", "reasoning"],
    "additionalProperties": False,
}
_MULTI_JSON_SCHEMA = {
    "type": "object",
    "properties": {
        "transactions": {"type": "array", "items": _TX_ITEM_SCHEMA},
        "total_count": {"type": "integer"},
        "overall_confidence": {"type": "number"},
        "analysis": {"type": "string"},
    },
    "required": ["transactions", "total_count", "overall_confidence", "analysis"],
    "additionalProperties": False,
}

# Output limits per answering provider. OpenAI keeps what the routes sent before (the receipt route 1000; the text
# routes had no limit, so these are far above any answer). Gemini's thinking tokens and Claude's thinking both
# count toward the limit, so they get more room.
_TEXT_MAX_TOKENS = {"openai": 4000, "gemini": 8192, "claude": 8000}
_MULTI_MAX_TOKENS = {"openai": 8000, "gemini": 8192, "claude": 8000}
_IMAGE_MAX_TOKENS = {"openai": 1000, "gemini": 8192, "claude": 8000}
_TX_TEMPERATURE = 0.3  # as before; sent to OpenAI and Gemini, never to Claude


def _tx_call(feature: str, system: str, user: str, schema: dict, max_tokens: Dict[str, int],
             image: Optional[bytes] = None, image_mime: Optional[str] = None):
    """A runner `call` that builds the JSON prompt for the answering target (its token limit depends on the provider)."""
    async def call(client, t):
        prompt = Prompt(system=system, user=user, image=image, image_mime=image_mime, json_schema=schema,
                        max_tokens=max_tokens[t.provider], temperature=_TX_TEMPERATURE)
        return await _runner.default_call(prompt, feature)(client, t)
    return call


def _parse_extraction_json(c: Completion) -> dict:
    """A runner `parse`: the answer's JSON object.

    Raises UnusableAnswer (the runner then tries the next provider) only when the text is not a JSON object,
    which the routes could not use at all. Everything else (a zero or odd amount, low confidence, an unknown
    category, missing fields, an empty transaction list) is accepted and handled by _build_extraction and the
    routes, exactly as before the provider runner.
    """
    try:
        data = json.loads(c.text)
    except ValueError as e:
        raise UnusableAnswer("answer is not JSON") from e
    if not isinstance(data, dict):
        raise UnusableAnswer("answer is not a JSON object")
    return data


async def _run_ai(feature: str, user_id: str, call, parse=lambda c: c, allow_empty: bool = False):
    """_runner.run for the transaction routes, with their error mapping.

    AllProvidersFailed -> 503 with a fixed message. The runner re-raises only request-level errors (the request
    itself was refused, e.g. an invalid image: no fallback), so any other exception escaping it -> 400 with a fixed
    message. Either way provider text is only logged (redacted) and never reaches the response or the routes'
    generic handlers.
    """
    try:
        return await _runner.run(feature, user_id=user_id, call=call, parse=parse, allow_empty=allow_empty)
    except AllProvidersFailed as e:
        logger.warning(f"{feature} unavailable for user {user_id}: {e}")
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=_AI_UNAVAILABLE) from e
    except Exception as e:
        # error, not warning: this path also catches our own bugs, which must be visible in the logs
        logger.error(f"{feature} request rejected for user {user_id}: {redact(f'{type(e).__name__}: {e}')}")
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=_AI_BAD_REQUEST) from e


@asynccontextmanager
async def _entry_use(user: dict, text: Optional[str] = None, token: Optional[str] = None):
    """One use of the shared "entry" allowance around an extraction: reserved before the AI call (a locked feature,
    the cost cap or a used-up allowance raise PlanError, which no handler below may swallow), committed when the
    block ends cleanly, released when it raises (a 503, a 400, an unusable answer).

    A voice entry is one use: a valid `token` for this user and exactly this `text` (see plans.voice_token) means
    transcribe-audio already counted it, so nothing more is reserved. Any other token is ignored, the request counts
    normally, and a user at the cost cap gets the normal refusal.
    """
    if token and text is not None and voice_token.is_valid(token, user["_id"], text) \
            and not await quota.over_cost_cap(user):
        yield
        return
    async with quota.use(user, "entry"):
        yield


def _log_ai_usage(label: str, user_id: str, result) -> None:
    c, t = result.completion, result.target
    logger.info(
        f"📝 [{t.provider.upper()} TOKEN USAGE - {label}] User: {user_id} | "
        f"in={c.input_tokens:,} out={c.output_tokens:,} total={c.input_tokens + c.output_tokens:,} | model={t.model}"
        + (f" | fallback from {result.fallback_from}" if result.fallback_from else "")
    )


# --- Recurrence helpers ---
def _new_recurrence_doc(rec: Optional[TransactionRecurrence], tx_date: datetime) -> dict:
    """Recurrence sub-document for a NEW transaction. Server-managed fields are never taken from the client."""
    if not rec:
        return {"enabled": False, "config": None, "last_created_date": None, "parent_transaction_id": None}
    return {
        "enabled": rec.enabled,
        "config": rec.config.model_dump() if rec.config else None,
        "last_created_date": tx_date.date() if rec.enabled else None,
        "parent_transaction_id": None,
    }


def _recurrence_obj(doc: dict) -> Optional[TransactionRecurrence]:
    """Parse a stored recurrence without failing on legacy/invalid configs."""
    rec = doc.get("recurrence")
    if not rec:
        return None
    try:
        return TransactionRecurrence(**rec)
    except ValidationError:
        return TransactionRecurrence(
            enabled=bool(rec.get("enabled")),
            config=None,
            last_created_date=rec.get("last_created_date"),
            parent_transaction_id=rec.get("parent_transaction_id"),
        )


# (member id -> display name, transaction id -> [member ids it was for]) of a book's entries; empty for a personal book.
EntryPeople = Tuple[Dict[str, str], Dict[str, List[str]]]
_NO_PEOPLE: EntryPeople = ({}, {})


async def _entry_people(book: Book, docs: List[dict]) -> EntryPeople:
    """Who added and who each entry was for, in two queries whatever the number of entries (former members keep
    their names)."""
    if not book.is_family or not docs:
        return _NO_PEOPLE
    names = {m["id"]: m["display_name"] for m in await families_db.list_members(book.family["id"])}
    return names, await families_db.beneficiaries_for([d["_id"] for d in docs])


async def _respond(book: Book, t: dict) -> TransactionResponse:
    return _transaction_response(t, await _entry_people(book, [t]))


def _transaction_response(t: dict, people: EntryPeople = _NO_PEOPLE) -> TransactionResponse:
    names, for_whom = people
    added = t.get("added_by_member_id")
    amount = t.get("amount")
    if not is_finite_number(amount):
        # Legacy NaN/inf amount (can't be JSON-encoded): shown as 0 so the user can still
        # open, fix or delete the row. Lists skip such rows (see _transaction_responses).
        logger.warning(f"Transaction {t.get('_id')!r} has a non-finite/invalid amount {amount!r}; returning 0")
        amount = 0.0
    return TransactionResponse(
        id=t["_id"],
        book_id=t["book_id"],
        type=TransactionType(t["type"]),
        main_category=t["main_category"],
        sub_category=t["sub_category"],
        date=t["date"],
        description=t.get("description"),
        amount=amount,
        currency=Currency(t.get("currency", "usd")),
        created_at=t["created_at"],
        updated_at=t.get("updated_at", t["created_at"]),
        recurrence=_recurrence_obj(t),
        parent_transaction_id=(t.get("recurrence") or {}).get("parent_transaction_id"),
        added_by=AddedBy(member_id=added, display_name=names[added]) if added in names else None,
        for_whom=list(for_whom.get(t["_id"], [])),
        transfer_id=t.get("transfer_id"),
    )


def _transaction_responses(docs: List[dict], people: EntryPeople = _NO_PEOPLE) -> List[TransactionResponse]:
    """Serialize a list; rows with a non-finite amount or otherwise malformed are skipped (logged)."""
    results = []
    for t in docs:
        if finite_amount_or_none(t) is None:
            continue
        try:
            results.append(_transaction_response(t, people))
        except Exception as e:
            logger.warning(f"Skipping malformed transaction {t.get('_id')!r}: {e}")
    return results


def _not_a_transfer(book: Book, transaction: dict, code: str = "transfer_not_editable") -> None:
    """400 `code` for a leg of a transfer: transfers can't be edited, and are removed only together (DELETE
    /api/transfers/{transfer_id})."""
    if transaction.get("transfer_id"):
        refuse(book.person, 400, code)


def _new_entry_fields(book: Book) -> dict:
    """Book-owned fields of a new entry: who added it, in a family book (personal entries have none)."""
    return {"added_by_member_id": book.member["id"]} if book.is_family else {}


def _cents_or_zero(value) -> Decimal:
    """to_cents for a stored amount; legacy NaN/inf/invalid amounts count as 0."""
    return to_cents(value) if is_finite_number(value) else Decimal("0.00")


# --- Goal allocation guard ---
async def _ensure_goal_allocations_covered(book_id: str, old_tx: dict, new_values: Optional[dict]) -> None:
    """
    Reject (400) deleting/editing an inflow when that would make a currency's
    available_balance (balance - allocated_to_goals) negative while money is allocated
    to goals. new_values = {"type", "amount", "currency"} after the edit, None for delete.
    Must be called while holding get_book_money_lock(book_id).
    """
    if old_tx.get("type") != TransactionType.INFLOW.value:
        return

    deltas: Dict[str, Decimal] = defaultdict(Decimal)
    # A legacy NaN/inf amount was never part of the balance (it is excluded there): 0.
    deltas[old_tx.get("currency", "usd")] -= _cents_or_zero(old_tx.get("amount"))
    if new_values is not None:
        signed = _cents_or_zero(new_values["amount"])
        if new_values["type"] != TransactionType.INFLOW.value:
            signed = -signed
        deltas[new_values["currency"]] += signed

    for currency, delta in deltas.items():
        if delta >= 0:
            continue
        balance = await get_book_balance(book_id, currency)
        allocated = to_cents(balance.get("allocated_to_goals", 0))
        if allocated <= 0:
            continue
        new_available = to_cents(balance.get("available_balance", 0)) + delta
        if new_available < 0:
            cur = currency.upper()
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    f"This change would make your available {cur} balance negative "
                    f"({cur} {new_available:.2f}) because {cur} {allocated:.2f} is allocated to goals. "
                    f"Please withdraw at least {cur} {-new_available:.2f} from your goals first."
                )
            )


# ==================== TRANSACTIONS ====================

@router.post("", response_model=TransactionResponse)
async def create_transaction(
    transaction_data: TransactionCreate,
    background_tasks: BackgroundTasks,
    book: Book = Depends(get_book)
):
    """Create new transaction in the request's book"""
    require_writable(book)
    await _validate_categories(
        transaction_data.type.value, transaction_data.main_category, transaction_data.sub_category
    )
    for_whom = await clean_for_whom(book, transaction_data.for_whom) or []

    transaction_id = str(uuid.uuid4())
    now = datetime.now(UTC)
    tx_date = transaction_data.date  # the local date and time, no timezone

    new_transaction = {
        "_id": transaction_id,
        "book_id": book.id,
        "type": transaction_data.type.value,
        "main_category": transaction_data.main_category,
        "sub_category": transaction_data.sub_category,
        "date": tx_date,
        "description": transaction_data.description,
        "amount": transaction_data.amount,
        "currency": transaction_data.currency.value,
        "created_at": now,
        "updated_at": now,
        # Server-managed recurrence fields are never taken from the client.
        "recurrence": _new_recurrence_doc(transaction_data.recurrence, tx_date),
        **_new_entry_fields(book),
    }

    async with db_transaction():
        await transactions_db.insert_transaction(new_transaction)
        if for_whom:
            await families_db.set_beneficiaries(transaction_id, for_whom)
    await books_db.mark_ai_data_stale(book.id)

    # Check for large transaction
    try:
        user_transactions = await transactions_db.find_transactions(
            book.id, type_="outflow", currency=transaction_data.currency.value, limit=50, include_transfers=False
        )

        if user_transactions:
            avg_amount = sum(t["amount"] for t in user_transactions) / len(user_transactions)
            user_profile = {"avg_transaction": avg_amount}
        else:
            user_profile = None

        background_tasks.add_task(
            check_large_transaction,
            book_id=book.id,
            transaction=new_transaction,
            user_spending_profile=user_profile
        )
    except Exception as e:
        print(f"Error checking large transaction: {e}")

    background_tasks.add_task(
        update_relevant_budgets,
        book.id,
        tx_date,
        transaction_data.currency.value
    )

    return await _respond(book, new_transaction)


@router.get("", response_model=List[TransactionResponse])
async def get_transactions(
    book: Book = Depends(get_book),
    limit: int = Query(default=50, ge=1, le=10000),
    skip: int = Query(default=0, ge=0),
    transaction_type: Optional[TransactionType] = None,
    start_date: Optional[WallClock] = None,
    end_date: Optional[WallClock] = None,
    currency: Optional[Currency] = None
):
    """Get user transactions with filters. start_date / end_date are local date-times or dates, compared directly with
    the transactions' dates (an offset sent with them is dropped, not applied)."""
    if end_date:
        # Date-only semantics when the client sent a date or exactly midnight (e.g. "2025-01-31"): that whole day is
        # included. Precise timestamps are respected as-is.
        if (end_date.hour, end_date.minute, end_date.second, end_date.microsecond) == (0, 0, 0, 0):
            end_date = end_date.replace(hour=23, minute=59, second=59, microsecond=999999)

    # Newest first; the id tiebreaker gives a stable order for skip/limit pagination.
    transactions = await transactions_db.find_transactions(
        book.id,
        type_=transaction_type.value if transaction_type else None,
        currency=currency.value if currency else None,
        date_from=start_date,
        date_to=end_date,
        skip=skip,
        limit=limit,
    )

    return _transaction_responses(transactions, await _entry_people(book, transactions))


@router.post("/{transaction_id}/disable-recurrence")
async def disable_transaction_recurrence(
    background_tasks: BackgroundTasks,
    transaction_id: str = Path(...),
    book: Book = Depends(get_book)
):
    """Disable recurrence for a transaction. Allowed in a read-only family too (R21): stopping recurrence is a repair
    action (the job would otherwise keep adding entries nobody can stop); who may change the entry still applies."""
    transaction =await transactions_db.get_transaction(transaction_id, book.id)

    if not transaction:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transaction not found"
        )
    _not_a_transfer(book, transaction)  # transfers never recur
    require_change_entry(book, transaction)

    success = await disable_recurrence_for_transaction(transaction_id, book.id)

    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transaction not found or recurrence not enabled"
        )

    await books_db.mark_ai_data_stale(book.id)

    return {"message": "Recurrence disabled successfully"}


@router.post("/{transaction_id}/disable-parent-recurrence")
async def disable_parent_transaction_recurrence(
    background_tasks: BackgroundTasks,
    transaction_id: str = Path(...),
    book: Book = Depends(get_book)
):
    """Disable recurrence for the parent transaction (used when editing auto-created transactions). Allowed in a
    read-only family too, like disable-recurrence (R21: a repair action)."""
    transaction =await transactions_db.get_transaction(transaction_id, book.id)

    if not transaction:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transaction not found"
        )
    # The child carries its parent's added_by (recurring_transaction_service), so this is the parent's check too.
    require_change_entry(book, transaction)

    parent_id = (transaction.get("recurrence") or {}).get("parent_transaction_id")

    if not parent_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This transaction is not auto-created from a recurring transaction"
        )

    success = await disable_recurrence_for_parent(parent_id, book.id)

    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Parent transaction not found"
        )

    await books_db.mark_ai_data_stale(book.id)

    return {"message": "Parent transaction recurrence disabled successfully"}


@router.post("/preview-recurrence")
async def preview_transaction_recurrence(
    request: RecurrencePreviewRequest,
    count: int = Query(default=5, ge=1, le=10),
    current_user: dict = Depends(get_current_user)
):
    """Preview upcoming occurrences of a recurring transaction"""

    # Bounds (day_of_week 0-6, day_of_month 1-31, month 1-12, day_of_year 1-31) are
    # enforced by RecurrencePreviewRequest -> 422 on bad input.
    try:
        config = RecurrenceConfig(
            frequency=request.frequency,
            day_of_week=request.day_of_week,
            day_of_month=request.day_of_month,
            month=request.month,
            day_of_year=request.day_of_year,
            end_date=request.end_date
        )
        occurrences = get_recurring_transaction_preview(
            last_date=request.start_date,
            config=config,
            count=count
        )
    except (ValidationError, ValueError) as e:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=f"Invalid recurrence: {e}")

    return {
        "occurrences": [date.isoformat() for date in occurrences],
        "count": len(occurrences)
    }


@router.get("/{transaction_id}", response_model=TransactionResponse)
async def get_transaction(
    transaction_id: str = Path(...),
    book: Book = Depends(get_book)
):
    """Get single transaction (404 for any id outside the request's book)"""
    transaction = await transactions_db.get_transaction(transaction_id, book.id)

    if not transaction:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transaction not found")

    return await _respond(book, transaction)


@router.put("/{transaction_id}", response_model=TransactionResponse)
async def update_transaction(
    background_tasks: BackgroundTasks,
    transaction_id: str = Path(...),
    transaction_data: TransactionUpdate = ...,
    book: Book = Depends(get_book)
):
    """Update transaction"""
    require_writable(book)
    transaction = await transactions_db.get_transaction(transaction_id, book.id)

    if not transaction:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transaction not found")
    _not_a_transfer(book, transaction)
    require_change_entry(book, transaction)
    # None: unchanged. The entry's current tags may stay, former members included (R20).
    current_tags: List[str] = []
    if transaction_data.for_whom is not None and book.is_family:
        current_tags = (await families_db.beneficiaries_for([transaction_id])).get(transaction_id, [])
    for_whom = await clean_for_whom(book, transaction_data.for_whom, already_tagged=current_tags)

    update_data = {"updated_at": datetime.now(UTC)}

    for field in ["type", "main_category", "sub_category", "date", "description", "amount", "currency"]:
        value = getattr(transaction_data, field, None)
        if value is not None:
            update_data[field] = value.value if field in ["type", "currency"] else value

    # An empty description is how the app clears a note; store it as "no note".
    if isinstance(update_data.get("description"), str) and not update_data["description"].strip():
        update_data["description"] = None

    new_type = update_data.get("type", transaction["type"])
    new_main = update_data.get("main_category", transaction["main_category"])
    new_sub = update_data.get("sub_category", transaction["sub_category"])
    new_amount = update_data.get("amount", transaction["amount"])
    new_currency = update_data.get("currency", transaction.get("currency", "usd"))
    new_date = update_data.get("date", transaction["date"])

    # Validate the effective categories only when they actually differ from the stored
    # document (the app always resends type/main/sub, so editing e.g. only the description
    # of a transaction with a legacy/renamed category must not be rejected).
    if (
        new_type != transaction["type"]
        or new_main != transaction["main_category"]
        or new_sub != transaction["sub_category"]
    ):
        await _validate_categories(new_type, new_main, new_sub)

    # Recurrence: only `enabled` and `config` are client-editable. last_created_date and
    # parent_transaction_id are server-managed and preserved from the stored document
    # (auto-created children keep their parent link even if the client sends enabled=false).
    existing_rec = transaction.get("recurrence") or {}
    if transaction_data.recurrence is not None:
        incoming = transaction_data.recurrence
        new_rec = {
            "enabled": incoming.enabled,
            "config": incoming.config.model_dump() if incoming.config else None,
            "last_created_date": existing_rec.get("last_created_date"),
            "parent_transaction_id": existing_rec.get("parent_transaction_id"),
        }
        if new_rec["enabled"]:
            # Never schedule occurrences before the transaction's own date.
            candidates = [as_calendar_date(d) for d in (new_rec["last_created_date"], new_date) if d]
            pointer = max(candidates)
            was_enabled = bool(existing_rec.get("enabled"))
            schedule_changed = (
                recurrence_schedule_key(existing_rec.get("config"))
                != recurrence_schedule_key(new_rec["config"])
            )
            if (not was_enabled or schedule_changed) and incoming.config:
                # Re-enabled (disabled -> enabled) or rescheduled (frequency/day changed):
                # don't back-fill the past. Every occurrence up to and including today
                # (the book's zone: the job runs once per book) counts as handled, so the job only creates from
                # the next occurrence after today. An unchanged enabled recurrence keeps its pointer.
                try:
                    pointer = rearmed_recurrence_pointer(pointer, incoming.config,
                                                         local_today(await book_zone(book.id)))
                except Exception as e:
                    logger.warning(f"Could not fast-forward recurrence pointer for {transaction_id}: {e}")
            new_rec["last_created_date"] = pointer
        update_data["recurrence"] = new_rec
    elif "date" in update_data and existing_rec.get("enabled"):
        last = existing_rec.get("last_created_date")
        if not last or as_calendar_date(last) < new_date.date():
            update_data["recurrence.last_created_date"] = new_date.date()

    money_changed = (
        new_type != transaction["type"]
        or new_currency != transaction.get("currency", "usd")
        or _cents_or_zero(new_amount) != _cents_or_zero(transaction.get("amount"))
    )

    async with get_book_money_lock(book.id):
        if money_changed:
            await _ensure_goal_allocations_covered(
                book.id,
                transaction,
                {"type": new_type, "amount": new_amount, "currency": new_currency},
            )

        async with db_transaction():
            updated_transaction = await transactions_db.update_transaction(transaction_id, book.id, update_data)
            if updated_transaction and for_whom is not None:
                await families_db.set_beneficiaries(transaction_id, for_whom)
        await books_db.mark_ai_data_stale(book.id)

    if not updated_transaction:  # deleted meanwhile
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transaction not found")

    # Recalculate budgets for BOTH the old and the new (date, currency).
    old_key = (transaction["date"], transaction.get("currency", "usd"))
    new_key = (new_date, new_currency)
    for budget_date, budget_currency in {old_key, new_key}:
        background_tasks.add_task(
            update_relevant_budgets,
            book.id,
            budget_date,
            budget_currency
        )

    return await _respond(book, updated_transaction)


@router.delete("/{transaction_id}")
async def delete_transaction(
    background_tasks: BackgroundTasks,
    transaction_id: str = Path(...),
    book: Book = Depends(get_book)
):
    """Delete transaction"""
    require_writable(book)
    transaction = await transactions_db.get_transaction(transaction_id, book.id)

    if not transaction:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transaction not found"
        )
    _not_a_transfer(book, transaction, "use_transfer_undo")
    require_change_entry(book, transaction)

    async with get_book_money_lock(book.id):
        # Deleting an inflow must not leave money "allocated to goals" that no longer exists.
        await _ensure_goal_allocations_covered(book.id, transaction, None)

        deleted = await transactions_db.delete_transaction(transaction_id, book.id)
        await books_db.mark_ai_data_stale(book.id)

    if deleted == 0:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete transaction"
        )

    background_tasks.add_task(
        update_relevant_budgets,
        book.id,
        transaction["date"],
        transaction.get("currency", "usd")
    )

    return {"message": "Transaction deleted successfully"}


# App language code -> Whisper (ISO-639-1) language code
_WHISPER_LANGUAGES = {"en": "en", "my": "my", "mm": "my"}


@router.post("/transcribe-audio")
async def transcribe_audio(
    audio: UploadFile = File(...),
    language: Optional[str] = Form(default=None),
    current_user: dict = Depends(get_current_user)
):
    """
    Transcribe audio to text with the transaction_audio provider chain (OpenAI Whisper by default).

    Optional multipart form field `language`: "en" or "my" (Burmese; "mm" accepted as an
    alias). When omitted, the language is auto-detected.

    Uses one "entry" allowance, kept only for a non-empty transcript (silence, an error or a refusal gives it back).
    A kept use returns a `voice_token` beside the transcription: send it as `voice_token` with the text extraction
    of that transcript and the voice entry stays one use (plans.voice_token).
    """
    app_control.require_on("voice", user_language(current_user))  # before any allowance is reserved
    reservation = await quota.reserve(current_user, "entry")  # outside the handlers below: a PlanError passes through
    try:
        out = await _transcribe_audio(audio, language, current_user)
        empty = not out["transcription"].strip()  # inside the try: a malformed result still gives the use back
    except BaseException:
        await quota.give_back(reservation)
        raise
    if empty:
        await quota.give_back(reservation)
        return out
    reservation.commit()
    token = voice_token.issue(current_user["_id"], out["transcription"])
    return {**out, "voice_token": token} if token else out


async def _transcribe_audio(audio: UploadFile, language: Optional[str], current_user: dict) -> dict:
    whisper_language = None
    if language is not None and language.strip():
        whisper_language = _WHISPER_LANGUAGES.get(language.strip().lower())
        if whisper_language is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Unsupported language. Use 'en' or 'my', or omit it for auto-detection."
            )

    try:
        MAX_AUDIO_SIZE = 25 * 1024 * 1024
        too_large = HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Audio file exceeds the 25MB limit."
        )
        content_length = audio.headers.get('content-length')
        if content_length and int(content_length) > MAX_AUDIO_SIZE:
            raise too_large

        audio_bytes = await audio.read(MAX_AUDIO_SIZE + 1)
        if len(audio_bytes) > MAX_AUDIO_SIZE:
            raise too_large

        # Providers pick the audio format from the file extension (.wav when there is none).
        file_ext = os.path.splitext(audio.filename)[1] if audio.filename else ""
        filename = f"audio{file_ext or '.wav'}"

        async def call(client, t):
            return await client.transcribe(t.model, audio_bytes, filename, whisper_language)

        # Silence or noise transcribes to "": that is a valid answer, not a reason to ask a backup provider.
        result = await _run_ai("transaction_audio", current_user["_id"], call, allow_empty=True)
        _log_ai_usage("Audio Transcription", current_user["_id"], result)
        return {"transcription": _without_filler(result.value.text)}

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Transcription internal error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=_entry_failed(current_user)
        )


@router.post("/extract-from-text", response_model=TransactionExtraction)
async def extract_transaction_from_text(
    request: TextExtractionRequest,
    current_user: dict = Depends(get_current_user),
    book: Book = Depends(get_book)
):
    """Extract transaction details from text with the transaction_text provider chain (one "entry" use). An entry
    that names no currency gets the book's (a family book's is its owner's)."""
    if not voice_token.is_valid(request.voice_token, current_user["_id"], request.text):
        app_control.require_on("voice", user_language(current_user))  # a voice entry already paid for finishes
    async with _entry_use(current_user, request.text, request.voice_token):
        return await _extract_transaction_from_text(request, current_user, await book_currency(book))


async def _extract_transaction_from_text(request: TextExtractionRequest, current_user: dict, default_currency: str):
    try:
        inflow_cats = await get_categories_doc("inflow")
        outflow_cats = await get_categories_doc("outflow")

        user_default_currency = default_currency
        today = local_today(user_zone(current_user))
        system_prompt = _text_prompt(_categories_text(inflow_cats, outflow_cats), today, user_default_currency)

        result = await _run_ai(
            "transaction_text", current_user["_id"],
            call=_tx_call("transaction_text", system_prompt, f"Extract transaction from: {request.text}",
                          _TX_ITEM_SCHEMA, _TEXT_MAX_TOKENS),
            parse=_parse_extraction_json,
        )
        _log_ai_usage("Text Extraction", current_user["_id"], result)
        result = result.value

        extraction = await _build_extraction(result, user_default_currency, keep_invalid_amount=True, today=today)
        if extraction is None:
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="AI returned an unexpected response")
        return extraction

    except HTTPException:
        raise
    except Exception as e:
        print(f"Extraction error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=_entry_failed(current_user)
        )


@router.post("/extract-multiple-from-text", response_model=MultipleTransactionExtraction)
async def extract_multiple_transactions_from_text(
    request: TextExtractionRequest,
    current_user: dict = Depends(get_current_user),
    book: Book = Depends(get_book)
):
    """Extract multiple transaction details from text with the transaction_text provider chain (one "entry" use;
    an answer that finds no transactions still counts). Entries naming no currency get the book's."""
    if not voice_token.is_valid(request.voice_token, current_user["_id"], request.text):
        app_control.require_on("voice", user_language(current_user))  # a voice entry already paid for finishes
    async with _entry_use(current_user, request.text, request.voice_token):
        return await _extract_multiple_transactions_from_text(request, current_user, await book_currency(book))


async def _extract_multiple_transactions_from_text(request: TextExtractionRequest, current_user: dict,
                                                  default_currency: str):
    try:
        inflow_cats = await get_categories_doc("inflow")
        outflow_cats = await get_categories_doc("outflow")

        user_default_currency = default_currency
        today = local_today(user_zone(current_user))
        system_prompt = _multi_prompt(_categories_text(inflow_cats, outflow_cats), today, user_default_currency)

        result = await _run_ai(
            "transaction_text", current_user["_id"],
            call=_tx_call("transaction_text", system_prompt, f"Extract all transactions from: {request.text}",
                          _MULTI_JSON_SCHEMA, _MULTI_MAX_TOKENS),
            parse=_parse_extraction_json,
        )
        _log_ai_usage("Multiple Text Extraction", current_user["_id"], result)
        result = result.value

        transactions = []
        raw_items = result.get("transactions") or []
        if not isinstance(raw_items, list):
            raw_items = []
        for tx_data in raw_items:
            extraction = await _build_extraction(tx_data, user_default_currency, keep_invalid_amount=False,
                                                 today=today)
            if extraction is not None:
                transactions.append(extraction)

        analysis = result.get("analysis")
        dropped = len(raw_items) - len(transactions)
        if dropped:
            note = f"{dropped} item(s) without a valid amount were omitted."
            analysis = f"{analysis} {note}" if analysis else note

        return MultipleTransactionExtraction(
            transactions=transactions,
            total_count=len(transactions),
            overall_confidence=_safe_confidence(result.get("overall_confidence")),
            analysis=analysis
        )

    except HTTPException:
        raise
    except Exception as e:
        print(f"Extraction error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=_entry_failed(current_user)
        )


@router.post("/batch-create", response_model=List[TransactionResponse])
async def batch_create_transactions(
    transactions_data: List[TransactionCreate],
    background_tasks: BackgroundTasks,
    book: Book = Depends(get_book)
):
    """Create multiple transactions at once (one all-or-nothing insert) in the request's book. Not an AI call: every
    plan may use it."""
    require_writable(book)
    new_transactions = []

    now = datetime.now(UTC)

    # 0. Validate categories for every item before inserting anything
    for index, transaction_data in enumerate(transactions_data, start=1):
        label = (transaction_data.description or "").strip()
        label = f" ('{label[:40]}')" if label else ""
        await _validate_categories(
            transaction_data.type.value,
            transaction_data.main_category,
            transaction_data.sub_category,
            prefix=f"Transaction #{index}{label}: ",
        )
    # ... and who each one is for (voice and receipt entries may say per item)
    for_whom = [await clean_for_whom(book, d.for_whom) or [] for d in transactions_data]
    tags = []

    # 1. Prepare all documents in memory (Fast)
    for transaction_data, item_for_whom in zip(transactions_data, for_whom):
        transaction_id = str(uuid.uuid4())
        if item_for_whom:
            tags.append((transaction_id, item_for_whom))
        tx_date = transaction_data.date  # the local date and time, no timezone

        doc = {
            "_id": transaction_id,
            "book_id": book.id,
            "type": transaction_data.type.value,
            "main_category": transaction_data.main_category,
            "sub_category": transaction_data.sub_category,
            "date": tx_date,
            "description": transaction_data.description,
            "amount": transaction_data.amount,
            "currency": transaction_data.currency.value,
            "created_at": now,
            "updated_at": now,
            # Server-managed recurrence fields are never taken from the client.
            "recurrence": _new_recurrence_doc(transaction_data.recurrence, tx_date),
            **_new_entry_fields(book),
        }

        new_transactions.append(doc)
        _transaction_response(doc)  # fail before inserting anything if a document can't be answered

    # 2. One all-or-nothing insert (entries and who they are for)
    if new_transactions:
        async with db_transaction():
            await transactions_db.insert_many(new_transactions)
            for transaction_id, item_for_whom in tags:
                await families_db.set_beneficiaries(transaction_id, item_for_whom)

        # 3. Post-processing (budgets in the background, AI data stale)
        background_tasks.add_task(update_all_book_budgets, book.id)
        await books_db.mark_ai_data_stale(book.id)

    people = await _entry_people(book, new_transactions)
    return [_transaction_response(doc, people) for doc in new_transactions]


# Constants
MAX_IMAGE_SIZE_BYTES = 10 * 1024 * 1024  # 10 MB Hard Limit
# The largest receipt image sent to the model: its long and short sides. A receipt is long and narrow, so fitting it
# in a square (1024 x 1024, before) made a 1000 x 4000 photo 256 px wide and its figures hard to read.
MAX_IMAGE_LONG_SIDE, MAX_IMAGE_SHORT_SIDE = 3200, 1600


def process_and_resize_image(image_data: bytes) -> bytes:
    """
    CPU-bound task: opens the image, turns it upright (the camera's EXIF orientation), shrinks it to fit
    MAX_IMAGE_LONG_SIDE x MAX_IMAGE_SHORT_SIDE (never enlarges it, keeps the aspect ratio) and re-encodes it as an
    optimized JPEG (returns the JPEG bytes). This runs in a threadpool to avoid blocking the async event loop.
    """
    try:
        with Image.open(io.BytesIO(image_data)) as img:
            # 1. Upright: a phone photo is often stored sideways with an EXIF "rotate me" tag the model doesn't read.
            img = ImageOps.exif_transpose(img)

            # 2. JPEG takes RGB or greyscale (PNGs with transparency, palettes, CMYK... become RGB)
            if img.mode not in ("RGB", "L"):
                img = img.convert("RGB")

            # 3. Shrink a large image to the long / short side limits
            w, h = img.size
            scale = min(1.0, MAX_IMAGE_LONG_SIDE / max(w, h), MAX_IMAGE_SHORT_SIDE / min(w, h))
            if scale < 1.0:
                img = img.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)

            # 3. Save to optimized JPEG buffer
            buffer = io.BytesIO()
            img.save(buffer, format="JPEG", quality=85, optimize=True)

            return buffer.getvalue()
    except Exception as e:
        logger.error(f"Image processing failed: {e}")
        raise ValueError("Invalid image format")

@router.post("/extract-from-image", response_model=TransactionExtraction)
async def extract_transaction_from_image(
    image: UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
    book: Book = Depends(get_book)
):
    """
    Extract transaction details from a receipt image with the transaction_image provider chain (one "entry" use).
    (Memory Optimized: Resizes images before processing)
    """
    app_control.require_on("receipts", user_language(current_user))
    async with _entry_use(current_user):
        return await _extract_transaction_from_image(image, current_user, await book_currency(book))


async def _extract_transaction_from_image(image: UploadFile, current_user: dict, default_currency: str):
    try:
        # 1. Validate File Size (Content-Length Header)
        # Fail fast if the client reports a file larger than our limit
        content_length = image.headers.get('content-length')
        if content_length and int(content_length) > MAX_IMAGE_SIZE_BYTES:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail="Image file too large. Please upload an image smaller than 10MB."
            )

        # 3. Read File Safely (Chunked Read)
        # Prevent reading massive files into RAM if Content-Length was missing/faked
        image_data = bytearray()
        chunk_size = 1024 * 1024  # 1MB chunks

        while True:
            chunk = await image.read(chunk_size)
            if not chunk:
                break
            image_data.extend(chunk)
            if len(image_data) > MAX_IMAGE_SIZE_BYTES:
                raise HTTPException(
                    status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                    detail="Image file exceeds the 10MB limit."
                )

        # 4. Process Image (Resize & Encode)
        # Run CPU-intensive PIL operations in a separate thread
        try:
            jpeg_bytes = await run_in_threadpool(process_and_resize_image, bytes(image_data))
        except ValueError:
             raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid image file. Please upload a valid JPG or PNG."
            )

        # 5. Prepare Categories for Prompt
        inflow_cats = await get_categories_doc("inflow")
        outflow_cats = await get_categories_doc("outflow")

        user_default_currency = default_currency
        today = local_today(user_zone(current_user))

        # 6. Construct System Prompt
        system_prompt = _receipt_prompt(_categories_text(inflow_cats, outflow_cats), today, user_default_currency)

        # 7. Ask the transaction_image provider chain (the resized receipt goes as one JPEG image)
        result = await _run_ai(
            "transaction_image", current_user["_id"],
            call=_tx_call("transaction_image", system_prompt, "Analyze this receipt and extract transaction details:",
                          _TX_ITEM_SCHEMA, _IMAGE_MAX_TOKENS, image=jpeg_bytes, image_mime="image/jpeg"),
            parse=_parse_extraction_json,
        )
        _log_ai_usage("Image Extraction", current_user["_id"], result)
        result = result.value

        extraction = await _build_extraction(result, user_default_currency, keep_invalid_amount=True, today=today)
        if extraction is None:
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="AI returned an unexpected response")
        return extraction

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Image extraction error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=_entry_failed(current_user)
        )