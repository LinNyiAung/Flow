import uuid
from datetime import datetime, UTC, timezone
from decimal import Decimal, ROUND_HALF_UP
from typing import List, Optional

from fastapi import APIRouter, HTTPException, status, Depends, Path

from models import Currency
from utils import get_current_user, get_user_balance, get_user_money_lock
from goal_models import CurrencySummary, GoalContribution, GoalCreate, GoalResponse, GoalStatus, GoalType, GoalUpdate, GoalsSummary, MultiCurrencyGoalsSummary

from notification_service import (
    check_goal_notifications,
    check_milestone_amount,
)

from sql import goals as goals_db
from sql import users as users_db

router = APIRouter(prefix="/api/goals", tags=["goals"])

_CENT = Decimal("0.01")


def to_cents(value) -> Decimal:
    """Money value as a Decimal rounded to cents (avoids float artefacts like 0.30000000000000004)."""
    return Decimal(repr(float(value or 0))).quantize(_CENT, rounding=ROUND_HALF_UP)


def _money(value: Decimal) -> float:
    return float(value.quantize(_CENT, rounding=ROUND_HALF_UP))

# ==================== FINANCIAL GOALS ====================

@router.post("", response_model=GoalResponse)
async def create_goal(
    goal_data: GoalCreate,
    current_user: dict = Depends(get_current_user)
):
    """Create a new financial goal"""
    initial = to_cents(goal_data.initial_contribution or 0)
    target = to_cents(goal_data.target_amount)
    if target <= 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Target amount must be at least 0.01")
    if initial > target:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Initial contribution cannot exceed the target amount"
        )

    goal_id = str(uuid.uuid4())

    # Serialize with other balance-moving operations of this user so two concurrent
    # requests can't both allocate the same available balance.
    async with get_user_money_lock(current_user["_id"]):
        if initial > 0:
            # Check (inside the lock) that the user has enough available balance
            balance_data = await get_user_balance(current_user["_id"], goal_data.currency.value)
            available_balance = to_cents(balance_data["available_balance"])
            if initial > available_balance:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Insufficient balance. Available for goals: {goal_data.currency.value.upper()} {available_balance:.2f}"
                )

        now = datetime.now(UTC)
        current_amount = _money(initial)

        # Check if goal is already achieved
        status_value = GoalStatus.ACHIEVED if initial >= target else GoalStatus.ACTIVE
        achieved_at = now if status_value == GoalStatus.ACHIEVED else None

        new_goal = {
            "_id": goal_id,
            "user_id": current_user["_id"],
            "name": goal_data.name,
            "target_amount": _money(target),
            "current_amount": current_amount,
            "target_date": goal_data.target_date.replace(tzinfo=timezone.utc) if goal_data.target_date and goal_data.target_date.tzinfo is None else goal_data.target_date,
            "goal_type": goal_data.goal_type.value,
            "status": status_value.value,
            "currency": goal_data.currency.value,
            "created_at": now,
            "updated_at": now,
            "achieved_at": achieved_at
        }

        await goals_db.insert_goal(new_goal)

        # AI data stale (same transaction as the goal)
        await users_db.mark_ai_data_stale(current_user["_id"])

    progress = (current_amount / new_goal["target_amount"] * 100) if new_goal["target_amount"] > 0 else 0

    return GoalResponse(
        id=goal_id,
        user_id=current_user["_id"],
        name=goal_data.name,
        target_amount=new_goal["target_amount"],
        current_amount=current_amount,
        target_date=goal_data.target_date,
        goal_type=goal_data.goal_type,
        status=status_value,
        progress_percentage=progress,
        currency=goal_data.currency,
        created_at=now,
        updated_at=now,
        achieved_at=achieved_at
    )


@router.get("", response_model=List[GoalResponse])
async def get_goals(
    current_user: dict = Depends(get_current_user),
    status_filter: Optional[GoalStatus] = None,
    currency: Optional[Currency] = None  # enum -> unknown values are a 422, not a 500
):
    """Get all user goals"""
    goals = await goals_db.list_goals(
        current_user["_id"],
        status=status_filter.value if status_filter else None,
        currency=currency.value if currency else None,
    )

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
            currency=Currency(g.get("currency", "usd")),
            created_at=g["created_at"],
            updated_at=g.get("updated_at", g["created_at"]),
            achieved_at=g.get("achieved_at")
        )
        for g in goals
    ]


@router.get("/summary", response_model=GoalsSummary)
async def get_goals_summary(
    current_user: dict = Depends(get_current_user),
    currency: Optional[Currency] = None  # enum -> unknown values are a 422, not a 500
):
    """Get summary of all goals"""
    goals = await goals_db.list_goals(current_user["_id"], currency=currency.value if currency else None)

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
        currency=currency
    )


@router.get("/{goal_id}", response_model=GoalResponse)
async def get_goal(
    goal_id: str = Path(...),
    current_user: dict = Depends(get_current_user)
):
    """Get a specific goal"""
    goal = await goals_db.get_goal(goal_id, current_user["_id"])

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
        currency=Currency(goal.get("currency", "usd")),
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
    """Update a goal's details"""
    goal = await goals_db.get_goal(goal_id, current_user["_id"])

    if not goal:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Goal not found"
        )

    update_data = {"updated_at": datetime.now(UTC)}

    if goal_data.name is not None:
        update_data["name"] = goal_data.name
    if goal_data.target_amount is not None:
        new_target = to_cents(goal_data.target_amount)
        if new_target <= 0:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Target amount must be at least 0.01")
        update_data["target_amount"] = _money(new_target)
        if to_cents(goal["current_amount"]) >= new_target:
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

    updated_goal = await goals_db.update_goal(goal_id, update_data)

    await users_db.mark_ai_data_stale(current_user["_id"])

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
        currency=Currency(updated_goal.get("currency", "usd")),
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
    """Add or reduce amount from a goal (serialized per user + optimistic guard)"""
    amount = to_cents(contribution.amount)
    if amount == 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Contribution amount must not be zero")

    # Serialize all balance-moving operations of this user (database row lock, so across
    # workers too): two concurrent contributions can't both spend the same available balance.
    async with get_user_money_lock(current_user["_id"]):
        # 1. READ (inside the lock): Fetch the goal state
        goal = await goals_db.get_goal(goal_id, current_user["_id"])

        if not goal:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Goal not found")

        # 2. CAPTURE STATE
        original_amount = goal["current_amount"]
        original = to_cents(original_amount)
        target = to_cents(goal["target_amount"])

        if goal["status"] == GoalStatus.ACHIEVED.value and amount > 0:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot add funds to an achieved goal")

        goal_currency = goal.get("currency", "usd")

        old_progress = (original_amount / goal["target_amount"] * 100) if goal["target_amount"] > 0 else 0
        new_total = original + amount

        # --- VALIDATION LOGIC (cent-exact) ---
        if amount > 0:
            if new_total > target:
                max_can_add = max(target - original, Decimal("0"))
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Cannot exceed target amount. Maximum you can add: {goal_currency.upper()} {max_can_add:.2f}"
                )

            # Re-read balance inside the lock
            balance_data = await get_user_balance(current_user["_id"], goal_currency)
            available_balance = to_cents(balance_data["available_balance"])

            if amount > available_balance:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Insufficient balance. Available for goals: {goal_currency.upper()} {available_balance:.2f}"
                )

        if amount < 0 and -amount > original:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Cannot reduce more than current amount: {goal_currency.upper()} {original:.2f}"
            )

        new_amount = _money(new_total)

        # --- STATUS CALCULATION ---
        new_status = goal["status"]
        achieved_at = goal.get("achieved_at")
        now = datetime.now(UTC)

        if new_total >= target and new_status == GoalStatus.ACTIVE.value:
            new_status = GoalStatus.ACHIEVED.value
            achieved_at = now
        elif new_total < target and new_status == GoalStatus.ACHIEVED.value:
            new_status = GoalStatus.ACTIVE.value
            achieved_at = None

        # --- ATOMIC WRITE (optimistic guard kept as a second line of defence) ---
        updated = await goals_db.update_amount_if_unchanged(goal_id, original_amount, {
            "current_amount": new_amount,
            "status": new_status,
            "updated_at": now,
            "achieved_at": achieved_at,
        })

        if updated == 0:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Transaction failed due to concurrent modification. Please try again."
            )

        # AI data stale (same transaction as the contribution)
        await users_db.mark_ai_data_stale(current_user["_id"])

    # --- POST-UPDATE ACTIONS ---
    new_progress = (new_amount / goal["target_amount"] * 100) if goal["target_amount"] > 0 else 0

    if amount > 0:
        await check_goal_notifications(
            user_id=current_user["_id"],
            goal_id=goal_id,
            old_progress=old_progress,
            new_progress=new_progress,
            goal_name=goal["name"]
        )
        await check_milestone_amount(
            user_id=current_user["_id"],
            goal_id=goal_id,
            old_amount=original_amount,
            new_amount=new_amount,
            goal_name=goal["name"]
        )

    updated_goal = await goals_db.get_goal(goal_id)

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
        currency=Currency(updated_goal.get("currency", "usd")),
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
    goal = await goals_db.get_goal(goal_id, current_user["_id"])

    if not goal:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Goal not found"
        )

    returned_amount = goal["current_amount"]

    if await goals_db.delete_goal(goal_id, current_user["_id"]) == 0:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete goal"
        )

    await users_db.mark_ai_data_stale(current_user["_id"])

    return {
        "message": "Goal deleted successfully",
        "returned_amount": returned_amount
    }


@router.get("/summary/all-currencies", response_model=MultiCurrencyGoalsSummary)
async def get_multi_currency_goals_summary(
    current_user: dict = Depends(get_current_user)
):
    """Get summary of all goals with per-currency breakdown"""
    all_goals = await goals_db.list_goals(current_user["_id"])

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
        try:
            currency_enum = Currency(currency)
        except ValueError:
            print(f"⚠️ Skipping goals with unknown stored currency {currency!r} for user {current_user['_id']}")
            continue
        active = [g for g in goals if g["status"] == "active"]
        achieved = [g for g in goals if g["status"] == "achieved"]

        total_allocated = sum(g["current_amount"] for g in active)
        total_target = sum(g["target_amount"] for g in active)
        overall_progress = (total_allocated / total_target * 100) if total_target > 0 else 0

        currency_summaries.append(CurrencySummary(
            currency=currency_enum,
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