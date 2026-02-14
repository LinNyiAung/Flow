import base64
import io
import json
import os
import shutil
import tempfile
from PIL import Image
import uuid
from datetime import datetime, UTC, timezone
from typing import List, Optional
import logging

# Added BackgroundTasks to imports
from fastapi import APIRouter, File, HTTPException, UploadFile, status, Depends, Query, Path, BackgroundTasks
from fastapi.concurrency import run_in_threadpool
from pymongo.errors import BulkWriteError  # <--- PRO FIX IMPORT

from ai_usage_models import AIFeatureType, AIProviderType
from ai_usage_service import track_ai_usage
from utils import get_current_user, require_premium
from recurring_transaction_service import disable_recurrence_for_parent, disable_recurrence_for_transaction, get_recurring_transaction_preview
from recurrence_models import RecurrenceConfig, RecurrencePreviewRequest, TransactionRecurrence
from budget_service import update_all_user_budgets, update_relevant_budgets
from models import (
    Currency, MultipleTransactionExtraction,TextExtractionRequest, TransactionExtraction, 
    TransactionCreate, TransactionResponse, TransactionType,
    TransactionUpdate
)

from notification_service import check_large_transaction

from database import transactions_collection, categories_collection, users_collection
    
from config import settings


logger = logging.getLogger(__name__)


router = APIRouter(prefix="/api/transactions", tags=["transactions"])


# ==================== TRANSACTIONS ====================

@router.post("", response_model=TransactionResponse)
async def create_transaction(
    transaction_data: TransactionCreate,
    background_tasks: BackgroundTasks,
    current_user: dict = Depends(get_current_user)
):
    """Create new transaction"""
    transaction_id = str(uuid.uuid4())
    now = datetime.now(UTC)
    
    new_transaction = {
        "_id": transaction_id,
        "user_id": current_user["_id"],
        "type": transaction_data.type.value,
        "main_category": transaction_data.main_category,
        "sub_category": transaction_data.sub_category,
        "date": transaction_data.date.replace(tzinfo=timezone.utc) if transaction_data.date.tzinfo is None else transaction_data.date,
        "description": transaction_data.description,
        "amount": transaction_data.amount,
        "currency": transaction_data.currency.value,
        "created_at": now,
        "updated_at": now,
    }
    
    # Add recurrence if provided
    if transaction_data.recurrence:
        new_transaction["recurrence"] = transaction_data.recurrence.dict()
        if transaction_data.recurrence.enabled:
            new_transaction["recurrence"]["last_created_date"] = new_transaction["date"]
    else:
        new_transaction["recurrence"] = {
            "enabled": False,
            "config": None,
            "last_created_date": None,
            "parent_transaction_id": None
        }

    result = await transactions_collection.insert_one(new_transaction)

    # === FIX: Cache Invalidation Strategy ===
    # We simply wipe the cache. The next time get_balance() is called, 
    # it will automatically re-aggregate all transactions for 100% accuracy.
    await users_collection.update_one(
        {"_id": current_user["_id"]},
        {"$unset": {"balances": ""}}
    )

    if not result.inserted_id:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to create transaction")
    
    # Check for large transaction
    try:
        cursor = transactions_collection.find({
            "user_id": current_user["_id"],
            "type": "outflow",
            "currency": transaction_data.currency.value
        }).limit(50)
        user_transactions = await cursor.to_list(length=50)
        
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
        transaction_data.date,
        transaction_data.currency.value
    )

    # 2. Mark AI Data as Stale
    await users_collection.update_one(
        {"_id": current_user["_id"]},
        {"$set": {"ai_data_stale": True}}
    )

    recurrence_obj = None
    if new_transaction.get("recurrence"):
        recurrence_obj = TransactionRecurrence(**new_transaction["recurrence"])

    return TransactionResponse(
        id=transaction_id,
        user_id=current_user["_id"],
        type=transaction_data.type,
        main_category=transaction_data.main_category,
        sub_category=transaction_data.sub_category,
        date=transaction_data.date,
        description=transaction_data.description,
        amount=transaction_data.amount,
        currency=transaction_data.currency,
        created_at=now,
        updated_at=now,
        recurrence=recurrence_obj,
        parent_transaction_id=new_transaction["recurrence"].get("parent_transaction_id")
    )


@router.get("", response_model=List[TransactionResponse])
async def get_transactions(
    current_user: dict = Depends(get_current_user),
    limit: int = Query(default=50, le=10000),
    skip: int = Query(default=0, ge=0),
    transaction_type: Optional[TransactionType] = None,
    start_date: Optional[datetime] = None,
    end_date: Optional[datetime] = None,
    currency: Optional[Currency] = None
):
    """Get user transactions with filters"""
    query = {"user_id": current_user["_id"]}
    
    if transaction_type:
        query["type"] = transaction_type.value
    
    if currency:
        query["currency"] = currency.value
    
    if start_date or end_date:
        date_filter = {}
        if start_date:
            date_filter["$gte"] = start_date
        if end_date:
            date_filter["$lte"] = end_date.replace(hour=23, minute=59, second=59, microsecond=999999)
        query["date"] = date_filter

    cursor = transactions_collection.find(query)\
        .sort([("date", -1), ("created_at", -1)])\
        .skip(skip)\
        .limit(limit)
    
    transactions = await cursor.to_list(length=limit)

    result = []
    for t in transactions:
        recurrence_obj = None
        if t.get("recurrence"):
            recurrence_obj = TransactionRecurrence(**t["recurrence"])
        
        result.append(TransactionResponse(
            id=t["_id"],
            user_id=t["user_id"],
            type=TransactionType(t["type"]),
            main_category=t["main_category"],
            sub_category=t["sub_category"],
            date=t["date"],
            description=t.get("description"),
            amount=t["amount"],
            currency=Currency(t.get("currency", "usd")),
            created_at=t["created_at"],
            updated_at=t.get("updated_at", t["created_at"]),
            recurrence=recurrence_obj,
            parent_transaction_id=t.get("recurrence", {}).get("parent_transaction_id")
        ))
    
    return result


@router.post("/{transaction_id}/disable-recurrence")
async def disable_transaction_recurrence(
    background_tasks: BackgroundTasks,
    transaction_id: str = Path(...),
    current_user: dict = Depends(get_current_user)
):
    """Disable recurrence for a transaction"""
    transaction = await transactions_collection.find_one({
        "_id": transaction_id,
        "user_id": current_user["_id"]
    })
    
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

    await users_collection.update_one(
        {"_id": current_user["_id"]},
        {"$set": {"ai_data_stale": True}}
    )
    
    return {"message": "Recurrence disabled successfully"}


@router.post("/{transaction_id}/disable-parent-recurrence")
async def disable_parent_transaction_recurrence(
    background_tasks: BackgroundTasks,
    transaction_id: str = Path(...),
    current_user: dict = Depends(get_current_user)
):
    """Disable recurrence for the parent transaction (used when editing auto-created transactions)"""
    transaction = await transactions_collection.find_one({
        "_id": transaction_id,
        "user_id": current_user["_id"]
    })
    
    if not transaction:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transaction not found"
        )
    
    parent_id = transaction.get("recurrence", {}).get("parent_transaction_id")
    
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
    
    await users_collection.update_one(
        {"_id": current_user["_id"]},
        {"$set": {"ai_data_stale": True}}
    )
    
    return {"message": "Parent transaction recurrence disabled successfully"}


@router.post("/preview-recurrence")
async def preview_transaction_recurrence(
    request: RecurrencePreviewRequest,
    count: int = Query(default=5, le=10),
    current_user: dict = Depends(get_current_user)
):
    """Preview upcoming occurrences of a recurring transaction"""
    
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
    transaction = await transactions_collection.find_one({
        "_id": transaction_id,
        "user_id": current_user["_id"]
    })

    if not transaction:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transaction not found")

    recurrence_obj = None
    if transaction.get("recurrence"):
        recurrence_obj = TransactionRecurrence(**transaction["recurrence"])

    return TransactionResponse(
        id=transaction["_id"],
        user_id=transaction["user_id"],
        type=TransactionType(transaction["type"]),
        main_category=transaction["main_category"],
        sub_category=transaction["sub_category"],
        date=transaction["date"],
        description=transaction.get("description"),
        amount=transaction["amount"],
        currency=Currency(transaction.get("currency", "usd")),
        created_at=transaction["created_at"],
        updated_at=transaction.get("updated_at", transaction["created_at"]),
        recurrence=recurrence_obj,
        parent_transaction_id=transaction.get("recurrence", {}).get("parent_transaction_id")
    )


@router.put("/{transaction_id}", response_model=TransactionResponse)
async def update_transaction(
    background_tasks: BackgroundTasks,
    transaction_id: str = Path(...),
    transaction_data: TransactionUpdate = ...,
    current_user: dict = Depends(get_current_user)
):
    """Update transaction"""
    transaction = await transactions_collection.find_one({
        "_id": transaction_id,
        "user_id": current_user["_id"]
    })
    
    if not transaction:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transaction not found")

    update_data = {"updated_at": datetime.now(UTC)}
    
    for field in ["type", "main_category", "sub_category", "date", "description", "amount", "currency"]:
        value = getattr(transaction_data, field, None)
        if value is not None:
            update_data[field] = value.value if field in ["type", "currency"] else value

    if transaction_data.recurrence is not None:
        update_data["recurrence"] = transaction_data.recurrence.dict()
        if transaction_data.recurrence.enabled and not transaction.get("recurrence", {}).get("enabled"):
            update_data["recurrence"]["last_created_date"] = update_data.get("date", transaction["date"])

    await transactions_collection.update_one(
    {"_id": transaction_id, "user_id": current_user["_id"]}, 
    {"$set": update_data}
    )

    await users_collection.update_one(
        {"_id": current_user["_id"]},
        {"$unset": {"balances": ""}}
    )

    updated_transaction = await transactions_collection.find_one({"_id": transaction_id})
    
    background_tasks.add_task(
        update_relevant_budgets,
        current_user["_id"], 
        transaction["date"], 
        transaction["currency"]
    )

    await users_collection.update_one(
        {"_id": current_user["_id"]},
        {"$set": {"ai_data_stale": True}}
    )
    
    recurrence_obj = None
    if updated_transaction.get("recurrence"):
        recurrence_obj = TransactionRecurrence(**updated_transaction["recurrence"])

    return TransactionResponse(
        id=updated_transaction["_id"],
        user_id=updated_transaction["user_id"],
        type=TransactionType(updated_transaction["type"]),
        main_category=updated_transaction["main_category"],
        sub_category=updated_transaction["sub_category"],
        date=updated_transaction["date"],
        description=updated_transaction["description"],
        amount=updated_transaction["amount"],
        currency=Currency(updated_transaction.get("currency", "usd")),
        created_at=updated_transaction["created_at"],
        updated_at=updated_transaction["updated_at"],
        recurrence=recurrence_obj,
        parent_transaction_id=updated_transaction.get("recurrence", {}).get("parent_transaction_id")
    )


@router.delete("/{transaction_id}")
async def delete_transaction(
    background_tasks: BackgroundTasks,
    transaction_id: str = Path(...),
    current_user: dict = Depends(get_current_user)
):
    """Delete transaction"""
    transaction = await transactions_collection.find_one({
        "_id": transaction_id, 
        "user_id": current_user["_id"]
    })
    
    if not transaction:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, 
            detail="Transaction not found"
        )

    result = await transactions_collection.delete_one({
        "_id": transaction_id, 
        "user_id": current_user["_id"]
    })

    await users_collection.update_one(
        {"_id": current_user["_id"]},
        {"$unset": {"balances": ""}}
    )
    
    if result.deleted_count == 0:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, 
            detail="Failed to delete transaction"
        )

    background_tasks.add_task(
        update_relevant_budgets,
        current_user["_id"], 
        transaction["date"],
        transaction["currency"]
    )

    await users_collection.update_one(
        {"_id": current_user["_id"]},
        {"$set": {"ai_data_stale": True}}
    )
    
    return {"message": "Transaction deleted successfully"}


@router.post("/transcribe-audio")
async def transcribe_audio(
    audio: UploadFile = File(...),
    current_user: dict = Depends(require_premium)
):
    """Transcribe audio to text using OpenAI Whisper (Memory Optimized)"""
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
            
            with open(temp_path, 'rb') as audio_file:
                transcript = await client.audio.transcriptions.create(
                    model="whisper-1",
                    file=audio_file,
                    language="en" 
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
        
        inflow_cats = await categories_collection.find_one({"_id": "inflow"})
        outflow_cats = await categories_collection.find_one({"_id": "outflow"})
        
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
4. Determine the date (default to today if not specified: {datetime.now(UTC).strftime('%Y-%m-%d')})
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
        
        return TransactionExtraction(
            type=result["type"],
            main_category=result["main_category"],
            sub_category=result["sub_category"],
            date=datetime.fromisoformat(result["date"]).replace(tzinfo=UTC),
            description=result.get("description"),
            amount=float(result["amount"]),
            currency=Currency(result.get("currency", user_default_currency)),
            confidence=float(result["confidence"]),
            reasoning=result.get("reasoning")
        )
        
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
        
        inflow_cats = await categories_collection.find_one({"_id": "inflow"})
        outflow_cats = await categories_collection.find_one({"_id": "outflow"})
        
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
   - Determine the date (default to today if not specified: {datetime.now(UTC).strftime('%Y-%m-%d')})
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
        for tx_data in result.get("transactions", []):
            transactions.append(TransactionExtraction(
                type=tx_data["type"],
                main_category=tx_data["main_category"],
                sub_category=tx_data["sub_category"],
                date=datetime.fromisoformat(tx_data["date"]).replace(tzinfo=UTC),
                description=tx_data.get("description"),
                amount=float(tx_data["amount"]),
                currency=Currency(tx_data.get("currency", user_default_currency)),
                confidence=float(tx_data["confidence"]),
                reasoning=tx_data.get("reasoning")
            ))
        
        return MultipleTransactionExtraction(
            transactions=transactions,
            total_count=result.get("total_count", len(transactions)),
            overall_confidence=float(result.get("overall_confidence", 0.0)),
            analysis=result.get("analysis")
        )
        
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
    """Create multiple transactions at once (Optimized with BulkWriteError handling)"""
    new_transactions = []
    response_models = []
    
    now = datetime.now(UTC)

    # 1. Prepare all documents in memory (Fast)
    for transaction_data in transactions_data:
        transaction_id = str(uuid.uuid4())
        
        doc = {
            "_id": transaction_id,
            "user_id": current_user["_id"],
            "type": transaction_data.type.value,
            "main_category": transaction_data.main_category,
            "sub_category": transaction_data.sub_category,
            "date": transaction_data.date.replace(tzinfo=timezone.utc) if transaction_data.date.tzinfo is None else transaction_data.date,
            "description": transaction_data.description,
            "amount": transaction_data.amount,
            "currency": transaction_data.currency.value,
            "created_at": now,
            "updated_at": now
        }

        # Add recurrence logic
        if transaction_data.recurrence:
            doc["recurrence"] = transaction_data.recurrence.dict()
            if transaction_data.recurrence.enabled:
                doc["recurrence"]["last_created_date"] = doc["date"]
        else:
            doc["recurrence"] = {
                "enabled": False,
                "config": None,
                "last_created_date": None,
                "parent_transaction_id": None
            }
        
        new_transactions.append(doc)

        # Prepare response model immediately
        recurrence_obj = None
        if transaction_data.recurrence:
             recurrence_obj = transaction_data.recurrence # Re-use input model or construct from dict

        response_models.append(TransactionResponse(
            id=transaction_id,
            user_id=current_user["_id"],
            type=transaction_data.type,
            main_category=transaction_data.main_category,
            sub_category=transaction_data.sub_category,
            date=transaction_data.date,
            description=transaction_data.description,
            amount=transaction_data.amount,
            currency=transaction_data.currency,
            created_at=now,
            updated_at=now,
            recurrence=recurrence_obj,
            parent_transaction_id=None
        ))

    # 2. Bulk Insert with "Pro" Error Handling
    if new_transactions:
        try:
            # ordered=False continues inserting even if one fails
            await transactions_collection.insert_many(new_transactions, ordered=False)
            
        except BulkWriteError as bwe:
            # === PRO FIX: Handle partial failures ===
            # This catches cases where some inserts failed but others succeeded.
            # bwe.details['nInserted'] tells you how many worked.
            inserted_count = bwe.details['nInserted']
            logger.warning(f"Batch insert partial failure. {inserted_count}/{len(new_transactions)} inserted. Errors: {bwe.details['writeErrors']}")
            
            # If at least ONE succeeded, we proceed with post-processing.
            if inserted_count == 0:
                 raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="All batch transactions failed to insert."
                )
        
        except Exception as e:
            # Catch other unexpected errors
            logger.error(f"Batch insert critical failure: {str(e)}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Batch insert failed: {str(e)}"
            )

        # 3. Post-processing (Background tasks & Cache invalidation)
        # We run this if at least one transaction succeeded (either normal flow or partial BulkWriteError)
        background_tasks.add_task(update_all_user_budgets, current_user["_id"])

        await users_collection.update_one(
            {"_id": current_user["_id"]},
            {"$unset": {"balances": ""}, "$set": {"ai_data_stale": True}}
        )

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
        inflow_cats = await categories_collection.find_one({"_id": "inflow"})
        outflow_cats = await categories_collection.find_one({"_id": "outflow"})
        
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
4. Extract the date from receipt (default to today if not visible: {datetime.now(UTC).strftime('%Y-%m-%d')})
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
        
        return TransactionExtraction(
            type=result["type"],
            main_category=result["main_category"],
            sub_category=result["sub_category"],
            date=datetime.fromisoformat(result["date"]).replace(tzinfo=UTC),
            description=result.get("description"),
            amount=float(result["amount"]),
            currency=Currency(result.get("currency", user_default_currency)),
            confidence=float(result["confidence"]),
            reasoning=result.get("reasoning")
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Image extraction error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to extract from image: {str(e)}"
        )