from datetime import datetime, UTC
import uuid
from database import ai_usage_collection
from ai_usage_models import AIFeatureType, AIProviderType
import logging

logger = logging.getLogger(__name__)

# Pricing per 1M tokens (as of latest rates)
PRICING = {
    "openai": {
        "gpt-4o-mini": {"input": 0.150, "output": 0.600},
        "gpt-4o": {"input": 2.50, "output": 10.00},
        "whisper-1": {"input": 0.006, "output": 0.006},  # NEW: $0.006/minute, estimated as tokens
    },
    "gemini": {
        "gemini-2.0-flash-exp": {"input": 0.00, "output": 0.00},
        "gemini-2.5-flash": {"input": 0.075, "output": 0.30},
        "gemini-2.5-pro": {"input": 1.25, "output": 5.00},
    }
}


def calculate_cost(provider: str, model: str, input_tokens: int, output_tokens: int) -> float:
    """Calculate estimated cost in USD"""
    try:
        if provider not in PRICING or model not in PRICING[provider]:
            logger.warning(f"Pricing not found for {provider}/{model}, using $0")
            return 0.0
        
        pricing = PRICING[provider][model]
        
        # Calculate cost (pricing is per 1M tokens)
        input_cost = (input_tokens / 1_000_000) * pricing["input"]
        output_cost = (output_tokens / 1_000_000) * pricing["output"]
        
        return round(input_cost + output_cost, 6)  # 6 decimal places for precision
    
    except Exception as e:
        logger.error(f"Error calculating cost: {e}")
        return 0.0


async def track_ai_usage(
    user_id: str,
    feature_type: AIFeatureType,
    provider: AIProviderType,
    model_name: str,
    input_tokens: int,
    output_tokens: int,
    total_tokens: int
):
    """Track AI API usage and cost"""
    try:
        # Calculate cost
        estimated_cost = calculate_cost(
            provider.value,
            model_name,
            input_tokens,
            output_tokens
        )
        
        # Create usage record
        usage_record = {
            "_id": str(uuid.uuid4()),
            "user_id": user_id,
            "feature_type": feature_type.value,
            "provider": provider.value,
            "model_name": model_name,
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "total_tokens": total_tokens,
            "estimated_cost_usd": estimated_cost,
            "created_at": datetime.now(UTC)
        }
        
        # [FIX] Added await for async database insertion
        await ai_usage_collection.insert_one(usage_record)
        
        logger.info(
            f"💰 [AI USAGE TRACKED] User: {user_id} | "
            f"Feature: {feature_type.value} | Provider: {provider.value} | "
            f"Tokens: {total_tokens:,} | Cost: ${estimated_cost:.6f}"
        )
        
        return usage_record
        
    except Exception as e:
        logger.error(f"Error tracking AI usage: {e}")
        return None