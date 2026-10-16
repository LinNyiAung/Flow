import base64
import io
import json
import os
import shutil
import tempfile
from PIL import Image
import uuid
import time
from collections import defaultdict
from datetime import datetime, UTC, timezone
from decimal import Decimal
from typing import Dict, List, Optional, Set
import logging

# Added BackgroundTasks to imports
from fastapi import APIRouter, File, Form, HTTPException, UploadFile, status, Depends, Query, Path, BackgroundTasks
from fastapi.concurrency import run_in_threadpool
from pydantic import ValidationError

from ai_usage_models import AIFeatureType, AIProviderType
from ai_usage_service import track_ai_usage
from utils import get_current_user, get_user_balance, get_user_money_lock, require_premium
from goal_routes import to_cents
from recurring_transaction_service import (
    disable_recurrence_for_parent, disable_recurrence_for_transaction, get_recurring_transaction_preview,
    rearmed_recurrence_pointer, recurrence_schedule_key,
)
from recurrence_models import RecurrenceConfig, RecurrencePreviewRequest, TransactionRecurrence
from budget_service import update_all_user_budgets, update_relevant_budgets
from models import (
    Currency, MultipleTransactionExtraction,TextExtractionRequest, TransactionExtraction,
    TransactionCreate, TransactionResponse, TransactionType,
    TransactionUpdate
)

from notification_service import check_large_transaction

from sql import transactions as transactions_db
from sql import users as users_db
from sql.categories import get_categories_doc

from config import settings
from category_matching import normalize_type, parse_positive_amount, snap_category
from tz_utils import app_today
from finite_utils import finite_amount_or_none, is_finite_number


logger = logging.getLogger(__name__)


router = APIRouter(prefix="/api/transactions", tags=["transactions"])


# ==================== HELPERS ====================

def _as_utc(dt: datetime) -> datetime:
    """Naive datetimes are treated as UTC (app convention: local wall-clock tagged as UTC)."""
    return dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt


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


def _extraction_date(value) -> datetime:
    """Model-produced date (YYYY-MM-DD) as a UTC-tagged wall-clock datetime; today if unusable."""
    try:
        parsed = datetime.fromisoformat(str(value).strip()[:10])
        return datetime(parsed.year, parsed.month, parsed.day, tzinfo=UTC)
    except (TypeError, ValueError):
        today = app_today()
        return datetime(today.year, today.month, today.day, tzinfo=UTC)


def _extraction_currency(value, default: str) -> Currency:
    for candidate in (value, default, Currency.USD.value):
        try:
            return Currency(str(candidate).strip().lower())
        except (ValueError, AttributeError):
            continue
    return Currency.USD


async def _build_extraction(
    data: dict, default_currency: str, keep_invalid_amount: bool
) -> Optional[TransactionExtraction]:
    """
    Turn one model-produced transaction dict into a TransactionExtraction whose type and
    categories are valid (snapped to the closest configured category, else the type's
    "Other" category), so the result can be sent to create/batch-create as-is.

    Amount <= 0 / missing: returns None (caller drops it) unless keep_invalid_amount, in
    which case amount=0 and confidence=0 are returned with a note in `reasoning`.
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

    reasoning = data.get("reasoning")
    if notes:
        reasoning = " ".join([str(reasoning)] + notes) if reasoning else " ".join(notes)

    return TransactionExtraction(
        type=tx_type,
        main_category=main,
        sub_category=sub,
        date=_extraction_date(data.get("date")),
        description=data.get("description"),
        amount=amount,
        currency=_extraction_currency(data.get("currency"), default_currency),
        confidence=confidence,
        reasoning=reasoning,
    )


# --- Recurrence helpers ---
def _new_recurrence_doc(rec: Optional[TransactionRecurrence], tx_date: datetime) -> dict:
    """Recurrence sub-document for a NEW transaction. Server-managed fields are never taken from the client."""
    if not rec:
        return {"enabled": False, "config": None, "last_created_date": None, "parent_transaction_id": None}
    return {
        "enabled": rec.enabled,
        "config": rec.config.model_dump() if rec.config else None,
        "last_created_date": tx_date if rec.enabled else None,
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


def _transaction_response(t: dict) -> TransactionResponse:
    amount = t.get("amount")
    if not is_finite_number(amount):
        # Legacy NaN/inf amount (can't be JSON-encoded): shown as 0 so the user can still
        # open, fix or delete the row. Lists skip such rows (see _transaction_responses).
        logger.warning(f"Transaction {t.get('_id')!r} has a non-finite/invalid amount {amount!r}; returning 0")
        amount = 0.0
    return TransactionResponse(
        id=t["_id"],
        user_id=t["user_id"],
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
        parent_transaction_id=(t.get("recurrence") or {}).get("parent_transaction_id")
    )


def _transaction_responses(docs: List[dict]) -> List[TransactionResponse]:
    """Serialize a list; rows with a non-finite amount or otherwise malformed are skipped (logged)."""
    results = []
    for t in docs:
        if finite_amount_or_none(t) is None:
            continue
        try:
            results.append(_transaction_response(t))
        except Exception as e:
            logger.warning(f"Skipping malformed transaction {t.get('_id')!r}: {e}")
    return results


def _cents_or_zero(value) -> Decimal:
    """to_cents for a stored amount; legacy NaN/inf/invalid amounts count as 0."""
    return to_cents(value) if is_finite_number(value) else Decimal("0.00")


# --- Goal allocation guard ---
async def _ensure_goal_allocations_covered(user_id: str, old_tx: dict, new_values: Optional[dict]) -> None:
    """
    Reject (400) deleting/editing an inflow when that would make a currency's
    available_balance (balance - allocated_to_goals) negative while money is allocated
    to goals. new_values = {"type", "amount", "currency"} after the edit, None for delete.
    Must be called while holding get_user_money_lock(user_id).
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
        balance = await get_user_balance(user_id, currency)
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
    current_user: dict = Depends(get_current_user)
):
    """Create new transaction"""
    await _validate_categories(
        transaction_data.type.value, transaction_data.main_category, transaction_data.sub_category
    )

    transaction_id = str(uuid.uuid4())
    now = datetime.now(UTC)
    tx_date = _as_utc(transaction_data.date)

    new_transaction = {
        "_id": transaction_id,
        "user_id": current_user["_id"],
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
    }

    await transactions_db.insert_transaction(new_transaction)
    await users_db.mark_ai_data_stale(current_user["_id"])

    # Check for large transaction
    try:
        user_transactions = await transactions_db.find_transactions(
            current_user["_id"], type_="outflow", currency=transaction_data.currency.value, limit=50
        )

        if user_transactions:
            avg_amount = sum(t["amount"] for t in user_transactions) / len(user_transactions)
            user_profile = {"avg_transaction": avg_amount}
        else:
            user_profile = None

        background_tasks.add_task(
            check_large_transaction,
            user_id=current_user["_id"],
            transaction=new_transaction,
            user_spending_profile=user_profile
        )
    except Exception as e:
        print(f"Error checking large transaction: {e}")

    background_tasks.add_task(
        update_relevant_budgets,
        current_user["_id"],
        tx_date,
        transaction_data.currency.value
    )

    return _transaction_response(new_transaction)


@router.get("", response_model=List[TransactionResponse])
async def get_transactions(
    current_user: dict = Depends(get_current_user),
    limit: int = Query(default=50, ge=1, le=10000),
    skip: int = Query(default=0, ge=0),
    transaction_type: Optional[TransactionType] = None,
    start_date: Optional[datetime] = None,
    end_date: Optional[datetime] = None,
    currency: Optional[Currency] = None
):
    """Get user transactions with filters"""
    if start_date:
        start_date = _as_utc(start_date)
    if end_date:
        end_date = _as_utc(end_date)
        # Date-only semantics only when the client sent exactly midnight (e.g. "2025-01-31");
        # precise timestamps are respected as-is.
        if (end_date.hour, end_date.minute, end_date.second, end_date.microsecond) == (0, 0, 0, 0):
            end_date = end_date.replace(hour=23, minute=59, second=59, microsecond=999999)

    # Newest first; the id tiebreaker gives a stable order for skip/limit pagination.
    transactions = await transactions_db.find_transactions(
        current_user["_id"],
        type_=transaction_type.value if transaction_type else None,
        currency=currency.value if currency else None,
        date_from=start_date,
        date_to=end_date,
        skip=skip,
        limit=limit,
    )

    return _transaction_responses(transactions)


@router.post("/{transaction_id}/disable-recurrence")
async def disable_transaction_recurrence(
    background_tasks: BackgroundTasks,
    transaction_id: str = Path(...),
    current_user: dict = Depends(get_current_user)
):
    """Disable recurrence for a transaction"""
    transaction = await transactions_db.get_transaction(transaction_id, current_user["_id"])

    if not transaction:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transaction not found"
        )

    success = await disable_recurrence_for_transaction(transaction_id, current_user["_id"])

    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transaction not found or recurrence not enabled"
        )

    await users_db.mark_ai_data_stale(current_user["_id"])

    return {"message": "Recurrence disabled successfully"}


@router.post("/{transaction_id}/disable-parent-recurrence")
async def disable_parent_transaction_recurrence(
    background_tasks: BackgroundTasks,
    transaction_id: str = Path(...),
    current_user: dict = Depends(get_current_user)
):
    """Disable recurrence for the parent transaction (used when editing auto-created transactions)"""
    transaction = await transactions_db.get_transaction(transaction_id, current_user["_id"])

    if not transaction:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transaction not found"
        )

    parent_id = (transaction.get("recurrence") or {}).get("parent_transaction_id")

    if not parent_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This transaction is not auto-created from a recurring transaction"
        )

    success = await disable_recurrence_for_parent(parent_id, current_user["_id"])

    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Parent transaction not found"
        )

    await users_db.mark_ai_data_stale(current_user["_id"])

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
    current_user: dict = Depends(get_current_user)
):
    """Get single transaction"""
    transaction = await transactions_db.get_transaction(transaction_id, current_user["_id"])

    if not transaction:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transaction not found")

    return _transaction_response(transaction)


@router.put("/{transaction_id}", response_model=TransactionResponse)
async def update_transaction(
    background_tasks: BackgroundTasks,
    transaction_id: str = Path(...),
    transaction_data: TransactionUpdate = ...,
    current_user: dict = Depends(get_current_user)
):
    """Update transaction"""
    transaction = await transactions_db.get_transaction(transaction_id, current_user["_id"])

    if not transaction:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transaction not found")

    update_data = {"updated_at": datetime.now(UTC)}

    for field in ["type", "main_category", "sub_category", "date", "description", "amount", "currency"]:
        value = getattr(transaction_data, field, None)
        if value is not None:
            update_data[field] = value.value if field in ["type", "currency"] else value

    # An empty description is how the app clears a note; store it as "no note".
    if isinstance(update_data.get("description"), str) and not update_data["description"].strip():
        update_data["description"] = None

    if "date" in update_data:
        update_data["date"] = _as_utc(update_data["date"])

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
            candidates = [_as_utc(d) for d in (new_rec["last_created_date"], new_date) if d]
            pointer = max(candidates)
            was_enabled = bool(existing_rec.get("enabled"))
            schedule_changed = (
                recurrence_schedule_key(existing_rec.get("config"))
                != recurrence_schedule_key(new_rec["config"])
            )
            if (not was_enabled or schedule_changed) and incoming.config:
                # Re-enabled (disabled -> enabled) or rescheduled (frequency/day changed):
                # don't back-fill the past. Every occurrence up to and including today
                # (app timezone) counts as handled, so the job only creates from the next
                # occurrence after today. An unchanged enabled recurrence keeps its pointer.
                try:
                    pointer = rearmed_recurrence_pointer(pointer, incoming.config, app_today())
                except Exception as e:
                    logger.warning(f"Could not fast-forward recurrence pointer for {transaction_id}: {e}")
            new_rec["last_created_date"] = pointer
        update_data["recurrence"] = new_rec
    elif "date" in update_data and existing_rec.get("enabled"):
        last = existing_rec.get("last_created_date")
        if not last or _as_utc(last) < new_date:
            update_data["recurrence.last_created_date"] = new_date

    money_changed = (
        new_type != transaction["type"]
        or new_currency != transaction.get("currency", "usd")
        or _cents_or_zero(new_amount) != _cents_or_zero(transaction.get("amount"))
    )

    async with get_user_money_lock(current_user["_id"]):
        if money_changed:
            await _ensure_goal_allocations_covered(
                current_user["_id"],
                transaction,
                {"type": new_type, "amount": new_amount, "currency": new_currency},
            )

        updated_transaction = await transactions_db.update_transaction(transaction_id, current_user["_id"], update_data)
        await users_db.mark_ai_data_stale(current_user["_id"])

    if not updated_transaction:  # deleted meanwhile
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transaction not found")

    # Recalculate budgets for BOTH the old and the new (date, currency).
    old_key = (_as_utc(transaction["date"]), transaction.get("currency", "usd"))
    new_key = (_as_utc(new_date), new_currency)
    for budget_date, budget_currency in {old_key, new_key}:
        background_tasks.add_task(
            update_relevant_budgets,
            current_user["_id"],
            budget_date,
            budget_currency
        )

    return _transaction_response(updated_transaction)


@router.delete("/{transaction_id}")
async def delete_transaction(
    background_tasks: BackgroundTasks,
    transaction_id: str = Path(...),
    current_user: dict = Depends(get_current_user)
):
    """Delete transaction"""
    transaction = await transactions_db.get_transaction(transaction_id, current_user["_id"])

    if not transaction:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, 
            detail="Transaction not found"
        )

    async with get_user_money_lock(current_user["_id"]):
        # Deleting an inflow must not leave money "allocated to goals" that no longer exists.
        await _ensure_goal_allocations_covered(current_user["_id"], transaction, None)

        deleted = await transactions_db.delete_transaction(transaction_id, current_user["_id"])
        await users_db.mark_ai_data_stale(current_user["_id"])

    if deleted == 0:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete transaction"
        )

    background_tasks.add_task(
        update_relevant_budgets,
        current_user["_id"],
        _as_utc(transaction["date"]),
        transaction.get("currency", "usd")
    )

    return {"message": "Transaction deleted successfully"}


# App language code -> Whisper (ISO-639-1) language code
_WHISPER_LANGUAGES = {"en": "en", "my": "my", "mm": "my"}


@router.post("/transcribe-audio")
async def transcribe_audio(
    audio: UploadFile = File(...),
    language: Optional[str] = Form(default=None),
    current_user: dict = Depends(require_premium)
):
    """
    Transcribe audio to text using OpenAI Whisper (Memory Optimized).

    Optional multipart form field `language`: "en" or "my" (Burmese; "mm" accepted as an
    alias). When omitted, Whisper auto-detects the language.
    """
    whisper_language = None
    if language is not None and language.strip():
        whisper_language = _WHISPER_LANGUAGES.get(language.strip().lower())
        if whisper_language is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Unsupported language. Use 'en' or 'my', or omit it for auto-detection."
            )

    temp_path = None
    try:
        if not settings.OPENAI_API_KEY:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="OpenAI API key not configured"
            )

        MAX_AUDIO_SIZE = 25 * 1024 * 1024 
        content_length = audio.headers.get('content-length')
        if content_length and int(content_length) > MAX_AUDIO_SIZE:
             raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail="Audio file exceeds the 25MB limit."
            )

        file_ext = os.path.splitext(audio.filename)[1] if audio.filename else ".wav"
        if not file_ext:
            file_ext = ".wav"

        with tempfile.NamedTemporaryFile(delete=False, suffix=file_ext) as temp_audio:
            shutil.copyfileobj(audio.file, temp_audio)
            temp_path = temp_audio.name

        try:
            from openai import AsyncOpenAI
            client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)

            whisper_kwargs = {"model": "whisper-1"}
            if whisper_language:
                whisper_kwargs["language"] = whisper_language  # omitted -> auto-detect
            with open(temp_path, 'rb') as audio_file:
                transcript = await client.audio.transcriptions.create(
                    file=audio_file,
                    **whisper_kwargs
                )

            transcription_length = len(transcript.text)
            estimated_input_tokens = int(transcription_length / 4) 
            estimated_output_tokens = int(transcription_length / 4)
            estimated_total_tokens = estimated_input_tokens + estimated_output_tokens

            logger.info(f"🎤 [OPENAI TOKEN USAGE - Audio Transcription] User: {current_user['_id']}")
            logger.info(f"   📥 Estimated input tokens: {estimated_input_tokens:,}")
            logger.info(f"   📤 Estimated output tokens: {estimated_output_tokens:,}")
            logger.info(f"   📊 Estimated total tokens: {estimated_total_tokens:,}")
            logger.info(f"   🤖 Model: whisper-1")
            logger.info(f"   📝 Transcription length: {transcription_length} characters")

            await track_ai_usage(
                user_id=current_user["_id"],
                feature_type=AIFeatureType.TRANSACTION_AUDIO_TRANSCRIPTION,
                provider=AIProviderType.OPENAI,
                model_name="whisper-1",
                input_tokens=estimated_input_tokens,
                output_tokens=estimated_output_tokens,
                total_tokens=estimated_total_tokens
            )

            return {"transcription": transcript.text}

        except Exception as e:
            logger.error(f"OpenAI API Error: {str(e)}")
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY, 
                detail=f"AI Service Provider Error: {str(e)}"
            )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Transcription internal error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to transcribe audio: {str(e)}"
        )
    finally:
        if temp_path and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except Exception as e:
                logger.warning(f"Failed to delete temp file {temp_path}: {e}")


@router.post("/extract-from-text", response_model=TransactionExtraction)
async def extract_transaction_from_text(
    request: TextExtractionRequest,
    current_user: dict = Depends(require_premium)
):
    """Extract transaction details from text using GPT-4"""
    try:
        if not settings.OPENAI_API_KEY:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="OpenAI API key not configured"
            )

        inflow_cats = await get_categories_doc("inflow")
        outflow_cats = await get_categories_doc("outflow")

        categories_text = "AVAILABLE CATEGORIES:\n\nINFLOW:\n"
        if inflow_cats:
            for cat in inflow_cats["categories"]:
                categories_text += f"- {cat['main_category']}: {', '.join(cat['sub_categories'])}\n"

        categories_text += "\nOUTFLOW:\n"
        if outflow_cats:
            for cat in outflow_cats["categories"]:
                categories_text += f"- {cat['main_category']}: {', '.join(cat['sub_categories'])}\n"

        user_default_currency = current_user.get("default_currency", "usd")

        system_prompt = f"""You are a financial transaction extraction assistant. Extract transaction details from user text.

{categories_text}

RULES:
1. Determine if it's 'inflow' (income) or 'outflow' (expense)
2. Select the most appropriate main_category and sub_category from the list above
3. Extract the amount as a positive number
4. Determine the date (default to today if not specified: {app_today().isoformat()})
5. Extract any description/notes
6. CURRENCY DETECTION (VERY IMPORTANT):
   - Carefully analyze the text for currency indicators
   - Look for currency symbols: $, USD, K, Ks, Kyat, ฿, THB, etc.
   - Look for currency codes: USD, MMK, THB, etc.
   - Look for currency names: dollars, kyat, myanmar Kyat, baht, thai baht, etc.
   - Common patterns:
     * "$" or "USD" or "dollar" → use "usd"
     * "K", "Ks", "Kyat", "kyat", "MMK" → use "mmk"
     * "฿", "THB", "baht", "Baht" → use "thb"  
   - If NO currency is mentioned anywhere in the text, use the user's default currency: "{user_default_currency}"
   - Be thorough - check the entire text, not just near the amount
7. Provide a confidence score (0.0-1.0) based on clarity
8. Provide brief reasoning for your categorization

Respond in JSON format:
{{
    "type": "inflow" or "outflow",
    "main_category": "selected main category",
    "sub_category": "selected sub category",
    "date": "YYYY-MM-DD",
    "description": "optional description",
    "amount": 123.45,
    "currency": "usd" or "mmk",
    "confidence": 0.95,
    "reasoning": "why you chose these categories"
}}"""

        from openai import AsyncOpenAI
        client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)

        response = await client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": f"Extract transaction from: {request.text}"}
            ],
            response_format={"type": "json_object"},
            temperature=0.3
        )

        if hasattr(response, 'usage'):
            from ai_usage_service import track_ai_usage
            from ai_usage_models import AIFeatureType, AIProviderType
            import logging



            input_tokens = response.usage.prompt_tokens
            output_tokens = response.usage.completion_tokens
            total_tokens = response.usage.total_tokens

            logger.info(f"📝 [OPENAI TOKEN USAGE - Text Extraction] User: {current_user['_id']}")
            logger.info(f"   📥 Input tokens: {input_tokens:,}")
            logger.info(f"   📤 Output tokens: {output_tokens:,}")
            logger.info(f"   📊 Total tokens: {total_tokens:,}")
            logger.info(f"   🤖 Model: gpt-4o-mini")

            await track_ai_usage(
                user_id=current_user["_id"],
                feature_type=AIFeatureType.TRANSACTION_TEXT_EXTRACTION,
                provider=AIProviderType.OPENAI,
                model_name="gpt-4o-mini",
                input_tokens=input_tokens,
                output_tokens=output_tokens,
                total_tokens=total_tokens
            )

        result = json.loads(response.choices[0].message.content)

        extraction = await _build_extraction(result, user_default_currency, keep_invalid_amount=True)
        if extraction is None:
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="AI returned an unexpected response")
        return extraction

    except HTTPException:
        raise
    except Exception as e:
        print(f"Extraction error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to extract transaction: {str(e)}"
        )


@router.post("/extract-multiple-from-text", response_model=MultipleTransactionExtraction)
async def extract_multiple_transactions_from_text(
    request: TextExtractionRequest,
    current_user: dict = Depends(require_premium)
):
    """Extract multiple transaction details from text using GPT-4"""
    try:
        if not settings.OPENAI_API_KEY:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="OpenAI API key not configured"
            )

        inflow_cats = await get_categories_doc("inflow")
        outflow_cats = await get_categories_doc("outflow")

        categories_text = "AVAILABLE CATEGORIES:\n\nINFLOW:\n"
        if inflow_cats:
            for cat in inflow_cats["categories"]:
                categories_text += f"- {cat['main_category']}: {', '.join(cat['sub_categories'])}\n"

        categories_text += "\nOUTFLOW:\n"
        if outflow_cats:
            for cat in outflow_cats["categories"]:
                categories_text += f"- {cat['main_category']}: {', '.join(cat['sub_categories'])}\n"

        user_default_currency = current_user.get("default_currency", "usd")

        system_prompt = f"""You are a financial transaction extraction assistant. Extract ALL transaction details from user text, even if there are multiple transactions mentioned.

{categories_text}

RULES:
1. Identify ALL transactions in the text (there may be one or many)
2. For each transaction:
   - Determine if it's 'inflow' (income) or 'outflow' (expense)
   - Select the most appropriate main_category and sub_category from the list above
   - Extract the amount as a positive number
   - Determine the date (default to today if not specified: {app_today().isoformat()})
   - Extract any description/notes
   - CURRENCY DETECTION (VERY IMPORTANT):
     * Carefully analyze the text for currency indicators for EACH transaction
     * Look for currency symbols: $, USD, K, Ks, Kyat, etc.
     * Look for currency codes: USD, MMK, etc.
     * Look for currency names: dollars, kyat, myanmar Kyat, etc.
     * Common patterns:
       - "$" or "USD" or "dollar" → use "usd"
       - "K", "Ks", "Kyat", "kyat", "MMK" → use "mmk"
       - "฿", "THB", "baht", "Baht" → use "thb"
     * If a transaction mentions no currency, use the user's default currency: "{user_default_currency}"
     * Each transaction can have a different currency
   - Provide a confidence score (0.0-1.0) based on clarity
   - Provide brief reasoning for your categorization

3. If multiple transactions are mentioned, extract each one separately
4. Calculate an overall confidence score based on all transactions
5. Provide a brief analysis of what you found

Respond in JSON format:
{{
    "transactions": [
        {{
            "type": "inflow" or "outflow",
            "main_category": "selected main category",
            "sub_category": "selected sub category",
            "date": "YYYY-MM-DD",
            "description": "optional description",
            "amount": 123.45,
            "currency": "usd" or "mmk",
            "confidence": 0.95,
            "reasoning": "why you chose these categories"
        }},
        // ... more transactions if found
    ],
    "total_count": 2,
    "overall_confidence": 0.90,
    "analysis": "Found 2 transactions: a grocery purchase and a salary payment"
}}"""

        from openai import AsyncOpenAI
        client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)

        response = await client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": f"Extract all transactions from: {request.text}"}
            ],
            response_format={"type": "json_object"},
            temperature=0.3
        )


        if hasattr(response, 'usage'):
            from ai_usage_service import track_ai_usage
            from ai_usage_models import AIFeatureType, AIProviderType
            import logging



            input_tokens = response.usage.prompt_tokens
            output_tokens = response.usage.completion_tokens
            total_tokens = response.usage.total_tokens

            logger.info(f"📝 [OPENAI TOKEN USAGE - Multiple Text Extraction] User: {current_user['_id']}")
            logger.info(f"   📥 Input tokens: {input_tokens:,}")
            logger.info(f"   📤 Output tokens: {output_tokens:,}")
            logger.info(f"   📊 Total tokens: {total_tokens:,}")
            logger.info(f"   🤖 Model: gpt-4o-mini")

            await track_ai_usage(
                user_id=current_user["_id"],
                feature_type=AIFeatureType.TRANSACTION_TEXT_EXTRACTION,
                provider=AIProviderType.OPENAI,
                model_name="gpt-4o-mini",
                input_tokens=input_tokens,
                output_tokens=output_tokens,
                total_tokens=total_tokens
            )

        result = json.loads(response.choices[0].message.content)

        transactions = []
        raw_items = result.get("transactions") or []
        if not isinstance(raw_items, list):
            raw_items = []
        for tx_data in raw_items:
            extraction = await _build_extraction(tx_data, user_default_currency, keep_invalid_amount=False)
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
            detail=f"Failed to extract transactions: {str(e)}"
        )


@router.post("/batch-create", response_model=List[TransactionResponse])
async def batch_create_transactions(
    transactions_data: List[TransactionCreate],
    background_tasks: BackgroundTasks,
    current_user: dict = Depends(require_premium)
):
    """Create multiple transactions at once (one all-or-nothing insert)"""
    new_transactions = []
    response_models = []

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

    # 1. Prepare all documents in memory (Fast)
    for transaction_data in transactions_data:
        transaction_id = str(uuid.uuid4())
        tx_date = _as_utc(transaction_data.date)

        doc = {
            "_id": transaction_id,
            "user_id": current_user["_id"],
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
        }

        new_transactions.append(doc)
        response_models.append(_transaction_response(doc))

    # 2. One all-or-nothing insert
    if new_transactions:
        await transactions_db.insert_many(new_transactions)

        # 3. Post-processing (budgets in the background, AI data stale)
        background_tasks.add_task(update_all_user_budgets, current_user["_id"])
        await users_db.mark_ai_data_stale(current_user["_id"])

    return response_models


# Constants
MAX_IMAGE_SIZE_BYTES = 10 * 1024 * 1024  # 10 MB Hard Limit
TARGET_IMAGE_SIZE = (1024, 1024)         # Resize target for Vision API

def process_and_resize_image(image_data: bytes) -> str:
    """
    CPU-bound task: Opens image, resizes it, and converts to optimized Base64.
    This runs in a threadpool to avoid blocking the async event loop.
    """
    try:
        with Image.open(io.BytesIO(image_data)) as img:
            # 1. Convert to RGB (Handy for PNGs with transparency)
            if img.mode in ("RGBA", "P"):
                img = img.convert("RGB")

            # 2. Resize if the image is too large (maintains aspect ratio)
            img.thumbnail(TARGET_IMAGE_SIZE)

            # 3. Save to optimized JPEG buffer
            buffer = io.BytesIO()
            img.save(buffer, format="JPEG", quality=85, optimize=True)

            # 4. Encode to Base64
            return base64.b64encode(buffer.getvalue()).decode('utf-8')
    except Exception as e:
        logger.error(f"Image processing failed: {e}")
        raise ValueError("Invalid image format")

@router.post("/extract-from-image", response_model=TransactionExtraction)
async def extract_transaction_from_image(
    image: UploadFile = File(...),
    current_user: dict = Depends(require_premium)
):
    """
    Extract transaction details from receipt image using OpenAI Vision.
    (Memory Optimized: Resizes images before processing)
    """
    try:
        # 1. Validate Service Availability
        if not settings.OPENAI_API_KEY:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="OpenAI API key not configured"
            )

        # 2. Validate File Size (Content-Length Header)
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
            base64_image = await run_in_threadpool(process_and_resize_image, bytes(image_data))
        except ValueError:
             raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid image file. Please upload a valid JPG or PNG."
            )

        # 5. Prepare Categories for Prompt
        inflow_cats = await get_categories_doc("inflow")
        outflow_cats = await get_categories_doc("outflow")

        categories_text = "AVAILABLE CATEGORIES:\n\nINFLOW:\n"
        if inflow_cats:
            for cat in inflow_cats.get("categories", []):
                categories_text += f"- {cat['main_category']}: {', '.join(cat['sub_categories'])}\n"

        categories_text += "\nOUTFLOW:\n"
        if outflow_cats:
            for cat in outflow_cats.get("categories", []):
                categories_text += f"- {cat['main_category']}: {', '.join(cat['sub_categories'])}\n"

        user_default_currency = current_user.get("default_currency", "usd")

        # 6. Construct System Prompt
        system_prompt = f"""You are a financial receipt analyzer. Extract transaction details from receipt images.

{categories_text}

RULES:
1. Identify if it's 'inflow' or 'outflow' (receipts are usually outflow)
2. Select the most appropriate category from the list above based on merchant/items
3. Extract the total amount
4. Extract the date from receipt (default to today if not visible: {app_today().isoformat()})
5. Create a brief description including merchant name
6. CURRENCY DETECTION (VERY IMPORTANT):
   - Look CAREFULLY at the receipt for currency indicators
   - Check for currency symbols: $, K, Ks, ฿, etc.
   - Check for currency codes: USD, MMK, THB, etc.
   - Check for country/language clues (Myanmar text → MMK, English with $ → USD, Thai text → THB)
   - Look at price format (e.g., "1,000 K" or "Ks 1,000" → MMK, "฿1,000" → THB)
   - Common patterns:
     * "$" or "USD" or "US Dollar" → use "usd"
     * "K", "Ks", "Kyat", "กျပ်", "MMK" → use "mmk"
     * "฿", "THB", "baht", "บาท" → use "thb"  
   - If NO currency indicators are visible on the receipt, use the user's default currency: "{user_default_currency}"
7. Provide confidence score (0.0-1.0)
8. Explain your reasoning

Respond in JSON format:
{{
    "type": "inflow" or "outflow",
    "main_category": "selected main category",
    "sub_category": "selected sub category",
    "date": "YYYY-MM-DD",
    "description": "merchant name and brief description",
    "amount": 123.45,
    "currency": "usd" or "mmk",
    "confidence": 0.95,
    "reasoning": "what you saw on the receipt"
}}"""

        # 7. Call OpenAI API
        from openai import AsyncOpenAI
        client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)

        response = await client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {
                    "role": "system", 
                    "content": system_prompt
                },
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": "Analyze this receipt and extract transaction details:"
                        },
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/jpeg;base64,{base64_image}"
                            }
                        }
                    ]
                }
            ],
            response_format={"type": "json_object"},
            max_tokens=1000,
            temperature=0.3
        )

        # 8. Track AI Usage
        if hasattr(response, 'usage'):
            input_tokens = response.usage.prompt_tokens
            output_tokens = response.usage.completion_tokens
            total_tokens = response.usage.total_tokens

            logger.info(f"📸 [OPENAI TOKEN USAGE - Image Extraction] User: {current_user['_id']}")
            logger.info(f"   📥 Input tokens: {input_tokens:,}")
            logger.info(f"   📤 Output tokens: {output_tokens:,}")
            logger.info(f"   📊 Total tokens: {total_tokens:,}")
            logger.info(f"   🤖 Model: gpt-4o")

            await track_ai_usage(
                user_id=current_user["_id"],
                feature_type=AIFeatureType.TRANSACTION_IMAGE_EXTRACTION,
                provider=AIProviderType.OPENAI,
                model_name="gpt-4o",
                input_tokens=input_tokens,
                output_tokens=output_tokens,
                total_tokens=total_tokens
            )

        # 9. Parse Response
        result = json.loads(response.choices[0].message.content)

        extraction = await _build_extraction(result, user_default_currency, keep_invalid_amount=True)
        if extraction is None:
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="AI returned an unexpected response")
        return extraction

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Image extraction error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to extract from image: {str(e)}"
        )