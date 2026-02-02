import uuid
from datetime import datetime, UTC
from typing import List

from fastapi import APIRouter, HTTPException, status, Depends
from models import FeedbackCreate, FeedbackResponse
from utils import get_current_user
from database import feedback_collection

router = APIRouter(prefix="/api/feedback", tags=["feedback"])

@router.post("", response_model=FeedbackResponse)
async def submit_feedback(
    feedback_data: FeedbackCreate,
    current_user: dict = Depends(get_current_user)
):
    """Submit user feedback"""
    try:
        feedback_id = str(uuid.uuid4())
        now = datetime.now(UTC)
        
        new_feedback = {
            "_id": feedback_id,
            "user_id": current_user["_id"],
            "user_email": current_user["email"], # Store email for easy contact
            "user_name": current_user["name"],
            "category": feedback_data.category.value,
            "message": feedback_data.message,
            "rating": feedback_data.rating,
            "screenshot_url": feedback_data.screenshot_url,
            "created_at": now,
            "status": "pending"
        }
        
        feedback_collection.insert_one(new_feedback)
        
        return FeedbackResponse(
            id=feedback_id,
            user_id=current_user["_id"],
            category=feedback_data.category,
            message=feedback_data.message,
            rating=feedback_data.rating,
            created_at=now,
            status="pending"
        )
        
    except Exception as e:
        print(f"Error submitting feedback: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to submit feedback"
        )