import uuid
from datetime import datetime, UTC, timezone
from typing import List, Optional

from fastapi import APIRouter, HTTPException, status, Depends, Path

from models import Currency
from utils import get_current_user, get_user_balance
from goal_models import CurrencySummary, GoalContribution, GoalCreate, GoalResponse, GoalStatus, GoalType, GoalUpdate, GoalsSummary, MultiCurrencyGoalsSummary

from notification_service import (
    check_goal_notifications,
    check_milestone_amount,
)

from database import goals_collection, users_collection

router = APIRouter(prefix="/api/goals", tags=["goals"])

# ==================== FINANCIAL GOALS ====================

@router.post("", response_model=GoalResponse)
async def create_goal(
    goal_data: GoalCreate,
    current_user: dict = Depends(get_current_user)
):
    """Create a new financial goal"""
    # Check if user has sufficient balance for initial contribution
    balance_data = await get_user_balance(current_user["_id"], goal_data.currency.value)  # UPDATED - pass currency
    available_balance = balance_data["available_balance"]  # UPDATED - use available_balance
    
    if goal_data.initial_contribution > available_balance:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Insufficient balance. Available for goals: {goal_data.currency.value.upper()} {available_balance:.2f}"  # UPDATED
        )
    
    goal_id = str(uuid.uuid4())
    now = datetime.now(UTC)
    
    current_amount = goal_data.initial_contribution if goal_data.initial_contribution else 0.0
    progress = (current_amount / goal_data.target_amount * 100) if goal_data.target_amount > 0 else 0
    
    # Check if goal is already achieved
    status_value = GoalStatus.ACHIEVED if current_amount >= goal_data.target_amount else GoalStatus.ACTIVE
    achieved_at = now if status_value == GoalStatus.ACHIEVED else None
    
    new_goal = {
        "_id": goal_id,
        "user_id": current_user["_id"],
        "name": goal_data.name,
        "target_amount": goal_data.target_amount,
        "current_amount": current_amount,
        "target_date": goal_data.target_date.replace(tzinfo=timezone.utc) if goal_data.target_date and goal_data.target_date.tzinfo is None else goal_data.target_date,
        "goal_type": goal_data.goal_type.value,
        "status": status_value.value,
        "currency": goal_data.currency.value,  # NEW
        "created_at": now,
        "updated_at": now,
        "achieved_at": achieved_at
    }
    
    result = goals_collection.insert_one(new_goal)
    if not result.inserted_id:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create goal"
        )
    
    # Mark AI data as stale
    users_collection.update_one(
        {"_id": current_user["_id"]},
        {"$set": {"ai_data_stale": True}}
    )
    
    return GoalResponse(
        id=goal_id,
        user_id=current_user["_id"],
        name=goal_data.name,
        target_amount=goal_data.target_amount,
        current_amount=current_amount,
        target_date=goal_data.target_date,
        goal_type=goal_data.goal_type,
        status=status_value,
        progress_percentage=progress,
        currency=goal_data.currency,  # NEW
        created_at=now,
        updated_at=now,
        achieved_at=achieved_at
    )


@router.get("", response_model=List[GoalResponse])
async def get_goals(
    current_user: dict = Depends(get_current_user),
    status_filter: Optional[GoalStatus] = None,
    currency: Optional[str] = None  # NEW - add currency filter
):
    """Get all user goals"""
    query = {"user_id": current_user["_id"]}
    
    if status_filter:
        query["status"] = status_filter.value
    
    if currency:  # NEW
        query["currency"] = currency
    
    goals = list(goals_collection.find(query).sort("created_at", -1))
    
    return [
        GoalResponse(
            id=g["_id"],
            user_id=g["user_id"],
            name=g["name"],
            target_amount=g["target_amount"],
            current_amount=g["current_amount"],
            target_date=g.get("target_date"),
            goal_type=GoalType(g["goal_type"]),
            status=GoalStatus(g["status"]),
            progress_percentage=(g["current_amount"] / g["target_amount"] * 100) if g["target_amount"] > 0 else 0,
            currency=Currency(g.get("currency", "usd")),  # NEW - with fallback
            created_at=g["created_at"],
            updated_at=g.get("updated_at", g["created_at"]),
            achieved_at=g.get("achieved_at")
        )
        for g in goals
    ]


@router.get("/summary", response_model=GoalsSummary)
async def get_goals_summary(
    current_user: dict = Depends(get_current_user),
    currency: Optional[str] = None  # NEW - add currency parameter
):
    """Get summary of all goals"""
    query = {"user_id": current_user["_id"]}
    if currency:  # NEW - filter by currency
        query["currency"] = currency
    
    goals = list(goals_collection.find(query))
    
    total_goals = len(goals)
    active_goals = len([g for g in goals if g["status"] == "active"])
    achieved_goals = len([g for g in goals if g["status"] == "achieved"])
    total_allocated = sum(g["current_amount"] for g in goals if g["status"] == "active")
    total_target = sum(g["target_amount"] for g in goals if g["status"] == "active")
    overall_progress = (total_allocated / total_target * 100) if total_target > 0 else 0
    
    return GoalsSummary(
        total_goals=total_goals,
        active_goals=active_goals,
        achieved_goals=achieved_goals,
        total_allocated=total_allocated,
        total_target=total_target,
        overall_progress=overall_progress,
        currency=Currency(currency) if currency else None  # NEW
    )


@router.get("/{goal_id}", response_model=GoalResponse)
async def get_goal(
    goal_id: str = Path(...),
    current_user: dict = Depends(get_current_user)
):
    """Get a specific goal"""
    goal = goals_collection.find_one({
        "_id": goal_id,
        "user_id": current_user["_id"]
    })
    
    if not goal:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Goal not found"
        )
    
    return GoalResponse(
        id=goal["_id"],
        user_id=goal["user_id"],
        name=goal["name"],
        target_amount=goal["target_amount"],
        current_amount=goal["current_amount"],
        target_date=goal.get("target_date"),
        goal_type=GoalType(goal["goal_type"]),
        status=GoalStatus(goal["status"]),
        progress_percentage=(goal["current_amount"] / goal["target_amount"] * 100) if goal["target_amount"] > 0 else 0,
        currency=Currency(goal.get("currency", "usd")),  # NEW
        created_at=goal["created_at"],
        updated_at=goal.get("updated_at", goal["created_at"]),
        achieved_at=goal.get("achieved_at")
    )


@router.put("/{goal_id}", response_model=GoalResponse)
async def update_goal(
    goal_id: str = Path(...),
    goal_data: GoalUpdate = ...,
    current_user: dict = Depends(get_current_user)
):
    """Update a goal's details (name, target amount, target date, type)"""
    goal = goals_collection.find_one({
        "_id": goal_id,
        "user_id": current_user["_id"]
    })
    
    if not goal:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Goal not found"
        )
    
    update_data = {"updated_at": datetime.now(UTC)}
    
    if goal_data.name is not None:
        update_data["name"] = goal_data.name
    if goal_data.target_amount is not None:
        update_data["target_amount"] = goal_data.target_amount
        # Recalculate status if target amount changed
        current_amount = goal["current_amount"]
        if current_amount >= goal_data.target_amount:
            update_data["status"] = GoalStatus.ACHIEVED.value
            if not goal.get("achieved_at"):
                update_data["achieved_at"] = datetime.now(UTC)
        else:
            update_data["status"] = GoalStatus.ACTIVE.value
            update_data["achieved_at"] = None
    if goal_data.target_date is not None:
        update_data["target_date"] = goal_data.target_date
    if goal_data.goal_type is not None:
        update_data["goal_type"] = goal_data.goal_type.value
    
    goals_collection.update_one(
        {"_id": goal_id},
        {"$set": update_data}
    )
    
    updated_goal = goals_collection.find_one({"_id": goal_id})
    #  Mark AI data as stale
    users_collection.update_one(
        {"_id": current_user["_id"]},
        {"$set": {"ai_data_stale": True}}
    )
    
    return GoalResponse(
        id=updated_goal["_id"],
        user_id=updated_goal["user_id"],
        name=updated_goal["name"],
        target_amount=updated_goal["target_amount"],
        current_amount=updated_goal["current_amount"],
        target_date=updated_goal.get("target_date"),
        goal_type=GoalType(updated_goal["goal_type"]),
        status=GoalStatus(updated_goal["status"]),
        progress_percentage=(updated_goal["current_amount"] / updated_goal["target_amount"] * 100) if updated_goal["target_amount"] > 0 else 0,
        currency=Currency(updated_goal.get("currency", "usd")),  # NEW
        created_at=updated_goal["created_at"],
        updated_at=updated_goal["updated_at"],
        achieved_at=updated_goal.get("achieved_at")
    )


@router.post("/{goal_id}/contribute", response_model=GoalResponse)
async def contribute_to_goal(
    goal_id: str = Path(...),
    contribution: GoalContribution = ...,
    current_user: dict = Depends(get_current_user)
):
    """Add or reduce amount from a goal"""
    goal = goals_collection.find_one({
        "_id": goal_id,
        "user_id": current_user["_id"]
    })
    
    if not goal:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Goal not found"
        )
    
    if goal["status"] == GoalStatus.ACHIEVED.value and contribution.amount > 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot add funds to an achieved goal"
        )
    
    goal_currency = goal.get("currency", "usd")  # NEW - get goal currency
    
    # Store old values for notification checks
    old_amount = goal["current_amount"]
    old_progress = (old_amount / goal["target_amount"] * 100) if goal["target_amount"] > 0 else 0
    
    # Calculate what the new amount would be
    new_amount = goal["current_amount"] + contribution.amount
    
    # For adding money to goal
    if contribution.amount > 0:
        # Check if adding this amount would exceed the target
        if new_amount > goal["target_amount"]:
            max_can_add = goal["target_amount"] - goal["current_amount"]
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Cannot exceed target amount. Maximum you can add: {goal_currency.upper()} {max_can_add:.2f}"
            )
        
        # Check available balance for the GOAL'S CURRENCY - UPDATED
        balance_data = await get_user_balance(current_user["_id"], goal_currency)
        available_balance = balance_data["available_balance"]
        
        if contribution.amount > available_balance:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Insufficient balance. Available for goals: {goal_currency.upper()} {available_balance:.2f}"
            )
    
    # For reducing money from goal
    if contribution.amount < 0:
        if abs(contribution.amount) > goal["current_amount"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Cannot reduce more than current amount: {goal_currency.upper()} {goal['current_amount']:.2f}"
            )
    
    # Determine new status
    new_status = goal["status"]
    achieved_at = goal.get("achieved_at")
    
    if new_amount >= goal["target_amount"] and new_status == GoalStatus.ACTIVE.value:
        new_status = GoalStatus.ACHIEVED.value
        achieved_at = datetime.now(UTC)
    elif new_amount < goal["target_amount"] and new_status == GoalStatus.ACHIEVED.value:
        new_status = GoalStatus.ACTIVE.value
        achieved_at = None
    
    # Calculate new progress
    new_progress = (new_amount / goal["target_amount"] * 100) if goal["target_amount"] > 0 else 0
    
    goals_collection.update_one(
        {"_id": goal_id},
        {
            "$set": {
                "current_amount": new_amount,
                "status": new_status,
                "updated_at": datetime.now(UTC),
                "achieved_at": achieved_at
            }
        }
    )
    
    # Check and create notifications (only for additions)
    if contribution.amount > 0:
        check_goal_notifications(
            user_id=current_user["_id"],
            goal_id=goal_id,
            old_progress=old_progress,
            new_progress=new_progress,
            goal_name=goal["name"]
        )
        
        check_milestone_amount(
            user_id=current_user["_id"],
            goal_id=goal_id,
            old_amount=old_amount,
            new_amount=new_amount,
            goal_name=goal["name"]
        )
    
    updated_goal = goals_collection.find_one({"_id": goal_id})
    # Mark AI data as stale
    users_collection.update_one(
        {"_id": current_user["_id"]},
        {"$set": {"ai_data_stale": True}}
    )
    
    return GoalResponse(
        id=updated_goal["_id"],
        user_id=updated_goal["user_id"],
        name=updated_goal["name"],
        target_amount=updated_goal["target_amount"],
        current_amount=updated_goal["current_amount"],
        target_date=updated_goal.get("target_date"),
        goal_type=GoalType(updated_goal["goal_type"]),
        status=GoalStatus(updated_goal["status"]),
        progress_percentage=(updated_goal["current_amount"] / updated_goal["target_amount"] * 100) if updated_goal["target_amount"] > 0 else 0,
        currency=Currency(updated_goal.get("currency", "usd")),  # NEW
        created_at=updated_goal["created_at"],
        updated_at=updated_goal["updated_at"],
        achieved_at=updated_goal.get("achieved_at")
    )


@router.delete("/{goal_id}")
async def delete_goal(
    goal_id: str = Path(...),
    current_user: dict = Depends(get_current_user)
):
    """Delete a goal and return its amount to balance"""
    goal = goals_collection.find_one({
        "_id": goal_id,
        "user_id": current_user["_id"]
    })
    
    if not goal:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Goal not found"
        )
    
    returned_amount = goal["current_amount"]
    
    result = goals_collection.delete_one({
        "_id": goal_id,
        "user_id": current_user["_id"]
    })
    
    if result.deleted_count == 0:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete goal"
        )
    
    # Mark AI data as stale
    users_collection.update_one(
        {"_id": current_user["_id"]},
        {"$set": {"ai_data_stale": True}}
    )
    
    return {
        "message": "Goal deleted successfully",
        "returned_amount": returned_amount
    }
    
    
@router.get("/summary/all-currencies", response_model=MultiCurrencyGoalsSummary)
async def get_multi_currency_goals_summary(
    current_user: dict = Depends(get_current_user)
):
    """Get summary of all goals with per-currency breakdown"""
    all_goals = list(goals_collection.find({"user_id": current_user["_id"]}))
    
    total_goals = len(all_goals)
    active_goals = len([g for g in all_goals if g["status"] == "active"])
    achieved_goals = len([g for g in all_goals if g["status"] == "achieved"])
    
    # Group goals by currency
    currency_groups = {}
    for goal in all_goals:
        currency = goal.get("currency", "usd")
        if currency not in currency_groups:
            currency_groups[currency] = []
        currency_groups[currency].append(goal)
    
    # Calculate summary for each currency
    currency_summaries = []
    for currency, goals in currency_groups.items():
        active = [g for g in goals if g["status"] == "active"]
        achieved = [g for g in goals if g["status"] == "achieved"]
        
        total_allocated = sum(g["current_amount"] for g in active)
        total_target = sum(g["target_amount"] for g in active)
        overall_progress = (total_allocated / total_target * 100) if total_target > 0 else 0
        
        currency_summaries.append(CurrencySummary(
            currency=Currency(currency),
            active_goals=len(active),
            achieved_goals=len(achieved),
            total_allocated=total_allocated,
            total_target=total_target,
            overall_progress=overall_progress
        ))
    
    return MultiCurrencyGoalsSummary(
        total_goals=total_goals,
        active_goals=active_goals,
        achieved_goals=achieved_goals,
        currency_summaries=currency_summaries
    )