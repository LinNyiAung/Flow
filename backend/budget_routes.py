import uuid
from datetime import datetime, UTC, timezone
from typing import List, Optional

from fastapi import APIRouter, HTTPException, status, Depends, Query, Path


from models import Currency
from utils import get_current_user, require_premium

from budget_models import AIBudgetRequest, AIBudgetSuggestion, BudgetCreate, BudgetPeriod, BudgetResponse, BudgetStatus, BudgetSummary, BudgetUpdate, CategoryBudget, CurrencyBudgetSummary, MultiCurrencyBudgetSummary
from budget_service import BudgetAnalyzer, is_budget_active, update_budget_spent_amounts


from notification_service import notify_budget_started


from database import budgets_collection, users_collection


router = APIRouter(prefix="/api/budgets", tags=["budgets"])

# ==================== BUDGETS ====================

@router.post("/ai-suggest", response_model=AIBudgetSuggestion)
async def get_ai_budget_suggestions(
    request: AIBudgetRequest,
    current_user: dict = Depends(require_premium)
):
    """Get AI-generated budget suggestions (Premium Feature)"""
    try:
        analyzer = BudgetAnalyzer(current_user["_id"])
        
        suggestions = await analyzer.generate_ai_suggestions(
            period=request.period,
            start_date=request.start_date,
            end_date=request.end_date,
            analysis_months=request.analysis_months,
            include_categories=request.include_categories,
            user_context=request.user_context,
            currency=request.currency  # NEW
        )
        
        return suggestions
        
    except Exception as e:
        print(f"Error generating AI budget suggestions: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate budget suggestions: {str(e)}"
        )


@router.post("", response_model=BudgetResponse)
async def create_budget(
    budget_data: BudgetCreate,
    current_user: dict = Depends(get_current_user)
):
    """Create a new budget (manual or from AI suggestions)"""
    try:
        budget_id = str(uuid.uuid4())
        now = datetime.now(UTC)
        
        # Calculate end date if not provided
        if budget_data.end_date is None:
            analyzer = BudgetAnalyzer(current_user["_id"])
            # Assuming calculate_period_dates is pure logic (sync)
            start_date, end_date = analyzer.calculate_period_dates(
                budget_data.period,
                budget_data.start_date,
                None
            )
        else:
            start_date = budget_data.start_date
            end_date = budget_data.end_date
        
        # Ensure timezone-aware
        if start_date.tzinfo is None:
            start_date = start_date.replace(tzinfo=timezone.utc)
        if end_date.tzinfo is None:
            end_date = end_date.replace(tzinfo=timezone.utc)
        
        # Determine if currently active
        is_active = is_budget_active(
            {"start_date": start_date, "end_date": end_date},
            now
        )
        
        new_budget = {
            "_id": budget_id,
            "user_id": current_user["_id"],
            "name": budget_data.name,
            "period": budget_data.period.value,
            "start_date": start_date,
            "end_date": end_date,
            "category_budgets": [cat.dict() for cat in budget_data.category_budgets],
            "total_budget": budget_data.total_budget,
            "total_spent": 0.0,
            "remaining_budget": budget_data.total_budget,
            "percentage_used": 0.0,
            "status": BudgetStatus.ACTIVE.value,
            "description": budget_data.description,
            "is_active": is_active,
            "auto_create_enabled": budget_data.auto_create_enabled,
            "auto_create_with_ai": budget_data.auto_create_with_ai,
            "parent_budget_id": None,
            "currency": budget_data.currency.value,
            "created_at": now,
            "updated_at": now
        }
        
        # [FIX] Added await
        await budgets_collection.insert_one(new_budget)
        
        # [FIX] Added await (Assuming service is updated to async)
        await update_budget_spent_amounts(current_user["_id"], budget_id)
        
        if is_active:
            # [FIX] Add await here
            await notify_budget_started(
                user_id=current_user["_id"],
                budget_id=budget_id,
                budget_name=budget_data.name,
                total_budget=budget_data.total_budget,
                period=budget_data.period.value
            )
        
        # Mark AI data as stale
        # [FIX] Added await
        await users_collection.update_one(
            {"_id": current_user["_id"]},
            {"$set": {"ai_data_stale": True}}
        )
        
        # Get updated budget
        # [FIX] Added await
        updated_budget = await budgets_collection.find_one({"_id": budget_id})
        
        return BudgetResponse(
            id=updated_budget["_id"],
            user_id=updated_budget["user_id"],
            name=updated_budget["name"],
            period=BudgetPeriod(updated_budget["period"]),
            start_date=updated_budget["start_date"],
            end_date=updated_budget["end_date"],
            category_budgets=[CategoryBudget(**cat) for cat in updated_budget["category_budgets"]],
            total_budget=updated_budget["total_budget"],
            total_spent=updated_budget["total_spent"],
            remaining_budget=updated_budget["remaining_budget"],
            percentage_used=updated_budget["percentage_used"],
            status=BudgetStatus(updated_budget["status"]),
            description=updated_budget.get("description"),
            is_active=updated_budget["is_active"],
            auto_create_enabled=updated_budget.get("auto_create_enabled", False),
            auto_create_with_ai=updated_budget.get("auto_create_with_ai", False),
            parent_budget_id=updated_budget.get("parent_budget_id"),
            currency=Currency(updated_budget.get("currency", "usd")),
            created_at=updated_budget["created_at"],
            updated_at=updated_budget["updated_at"]
        )
        
    except Exception as e:
        print(f"Error creating budget: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create budget: {str(e)}"
        )


@router.get("", response_model=List[BudgetResponse])
async def get_budgets(
    current_user: dict = Depends(get_current_user),
    active_only: bool = Query(default=False),
    period: Optional[BudgetPeriod] = None,
    currency: Optional[Currency] = None
):
    """Get all user budgets"""
    try:
        query = {"user_id": current_user["_id"]}
        
        if active_only:
            query["is_active"] = True
        
        if period:
            query["period"] = period.value
        
        if currency:
            query["currency"] = currency.value
        
        # [FIX] Async find with sort
        cursor = budgets_collection.find(query).sort("created_at", -1)
        budgets = await cursor.to_list(length=None)
        
        return [
            BudgetResponse(
                id=b["_id"],
                user_id=b["user_id"],
                name=b["name"],
                period=BudgetPeriod(b["period"]),
                start_date=b["start_date"],
                end_date=b["end_date"],
                category_budgets=[CategoryBudget(**cat) for cat in b["category_budgets"]],
                total_budget=b["total_budget"],
                total_spent=b["total_spent"],
                remaining_budget=b["remaining_budget"],
                percentage_used=b["percentage_used"],
                status=BudgetStatus(b["status"]),
                description=b.get("description"),
                is_active=b["is_active"],
                currency=Currency(b.get("currency", "usd")),
                created_at=b["created_at"],
                updated_at=b["updated_at"]
            )
            for b in budgets
        ]
        
    except Exception as e:
        print(f"Error fetching budgets: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to fetch budgets"
        )


@router.get("/summary", response_model=BudgetSummary)
async def get_budgets_summary(
    current_user: dict = Depends(get_current_user),
    currency: Optional[Currency] = Query(default=None)
):
    """Get summary of budgets for specific currency"""
    try:
        query = {"user_id": current_user["_id"]}
        
        # If currency not specified, use user's default currency
        if currency is None:
            currency = Currency(current_user.get("default_currency", "usd"))
        
        query["currency"] = currency.value
        
        # [FIX] Async find
        cursor = budgets_collection.find(query)
        budgets = await cursor.to_list(length=None)
        
        total_budgets = len(budgets)
        active_budgets = len([b for b in budgets if b["is_active"] and b["status"] == "active"])
        upcoming_budgets = len([b for b in budgets if b["status"] == "upcoming"])
        completed_budgets = len([b for b in budgets if b["status"] == "completed"])
        exceeded_budgets = len([b for b in budgets if b["status"] == "exceeded"])
        
        # Only sum active budgets (not upcoming)
        active_budget_list = [b for b in budgets if b["is_active"] and b["status"] == "active"]
        total_allocated = sum(b["total_budget"] for b in active_budget_list)
        total_spent = sum(b["total_spent"] for b in active_budget_list)
        overall_remaining = total_allocated - total_spent
        
        return BudgetSummary(
            total_budgets=total_budgets,
            active_budgets=active_budgets,
            completed_budgets=completed_budgets,
            exceeded_budgets=exceeded_budgets,
            upcoming_budgets=upcoming_budgets,
            total_allocated=total_allocated,
            total_spent=total_spent,
            overall_remaining=overall_remaining,
            currency=currency
        )
        
    except Exception as e:
        print(f"Error calculating budget summary: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to calculate budget summary"
        )
        
        
@router.get("/summary/all-currencies", response_model=MultiCurrencyBudgetSummary)
async def get_multi_currency_budgets_summary(
    current_user: dict = Depends(get_current_user)
):
    """Get summary of all budgets with per-currency breakdown"""
    try:
        # [FIX] Async find
        cursor = budgets_collection.find({"user_id": current_user["_id"]})
        all_budgets = await cursor.to_list(length=None)
        
        total_budgets = len(all_budgets)
        active_budgets = len([b for b in all_budgets if b["is_active"] and b["status"] == "active"])
        upcoming_budgets = len([b for b in all_budgets if b["status"] == "upcoming"])
        completed_budgets = len([b for b in all_budgets if b["status"] == "completed"])
        exceeded_budgets = len([b for b in all_budgets if b["status"] == "exceeded"])
        
        # Group budgets by currency
        currency_groups = {}
        for budget in all_budgets:
            currency = budget.get("currency", "usd")
            if currency not in currency_groups:
                currency_groups[currency] = []
            currency_groups[currency].append(budget)
        
        # Calculate summary for each currency
        currency_summaries = []
        for currency, budgets in currency_groups.items():
            active = [b for b in budgets if b["is_active"] and b["status"] == "active"]
            
            total_allocated = sum(b["total_budget"] for b in active)
            total_spent = sum(b["total_spent"] for b in active)
            overall_remaining = total_allocated - total_spent
            
            currency_summaries.append(CurrencyBudgetSummary(
                currency=Currency(currency),
                total_budgets=len(budgets),
                active_budgets=len([b for b in budgets if b["is_active"] and b["status"] == "active"]),
                completed_budgets=len([b for b in budgets if b["status"] == "completed"]),
                exceeded_budgets=len([b for b in budgets if b["status"] == "exceeded"]),
                upcoming_budgets=len([b for b in budgets if b["status"] == "upcoming"]),
                total_allocated=total_allocated,
                total_spent=total_spent,
                overall_remaining=overall_remaining
            ))
        
        return MultiCurrencyBudgetSummary(
            total_budgets=total_budgets,
            active_budgets=active_budgets,
            completed_budgets=completed_budgets,
            exceeded_budgets=exceeded_budgets,
            upcoming_budgets=upcoming_budgets,
            currency_summaries=currency_summaries
        )
        
    except Exception as e:
        print(f"Error calculating multi-currency budget summary: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to calculate budget summary"
        )


@router.get("/{budget_id}", response_model=BudgetResponse)
async def get_budget(
    budget_id: str = Path(...),
    current_user: dict = Depends(get_current_user)
):
    """Get a specific budget"""
    try:
        # [FIX] Added await
        budget = await budgets_collection.find_one({
            "_id": budget_id,
            "user_id": current_user["_id"]
        })
        
        if not budget:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Budget not found"
            )
        
        return BudgetResponse(
            id=budget["_id"],
            user_id=budget["user_id"],
            name=budget["name"],
            period=BudgetPeriod(budget["period"]),
            start_date=budget["start_date"],
            end_date=budget["end_date"],
            category_budgets=[CategoryBudget(**cat) for cat in budget["category_budgets"]],
            total_budget=budget["total_budget"],
            total_spent=budget["total_spent"],
            remaining_budget=budget["remaining_budget"],
            percentage_used=budget["percentage_used"],
            status=BudgetStatus(budget["status"]),
            description=budget.get("description"),
            is_active=budget["is_active"],
            currency=Currency(budget.get("currency", "usd")),
            created_at=budget["created_at"],
            updated_at=budget["updated_at"]
        )
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error fetching budget: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to fetch budget"
        )


@router.put("/{budget_id}", response_model=BudgetResponse)
async def update_budget(
    budget_id: str = Path(...),
    budget_data: BudgetUpdate = ...,
    current_user: dict = Depends(get_current_user)
):
    """Update a budget"""
    try:
        # [FIX] Added await
        budget = await budgets_collection.find_one({
            "_id": budget_id,
            "user_id": current_user["_id"]
        })
        
        if not budget:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Budget not found"
            )
        
        update_data = {"updated_at": datetime.now(UTC)}
        
        if budget_data.name is not None:
            update_data["name"] = budget_data.name
        
        if budget_data.description is not None:
            update_data["description"] = budget_data.description
        
        if budget_data.total_budget is not None:
            update_data["total_budget"] = budget_data.total_budget
            update_data["remaining_budget"] = budget_data.total_budget - budget["total_spent"]
            update_data["percentage_used"] = (budget["total_spent"] / budget_data.total_budget * 100) if budget_data.total_budget > 0 else 0
        
        if budget_data.category_budgets is not None:
            # Reset spent amounts to 0 for new categories
            category_budgets = []
            for cat in budget_data.category_budgets:
                cat_dict = cat.dict()
                cat_dict["spent_amount"] = 0
                cat_dict["percentage_used"] = 0
                cat_dict["is_exceeded"] = False
                category_budgets.append(cat_dict)
            
            update_data["category_budgets"] = category_budgets
            update_data["total_budget"] = sum(cat.allocated_amount for cat in budget_data.category_budgets)
        
        # [FIX] Added await
        await budgets_collection.update_one(
            {"_id": budget_id},
            {"$set": update_data}
        )
        
        # Recalculate spent amounts
        # [FIX] Added await
        await update_budget_spent_amounts(current_user["_id"], budget_id)
        
        # Mark AI data as stale
        # [FIX] Added await
        await users_collection.update_one(
            {"_id": current_user["_id"]},
            {"$set": {"ai_data_stale": True}}
        )
        
        # Fetch updated budget
        # [FIX] Added await
        updated_budget = await budgets_collection.find_one({"_id": budget_id})
        
        return BudgetResponse(
            id=updated_budget["_id"],
            user_id=updated_budget["user_id"],
            name=updated_budget["name"],
            period=BudgetPeriod(updated_budget["period"]),
            start_date=updated_budget["start_date"],
            end_date=updated_budget["end_date"],
            category_budgets=[CategoryBudget(**cat) for cat in updated_budget["category_budgets"]],
            total_budget=updated_budget["total_budget"],
            total_spent=updated_budget["total_spent"],
            remaining_budget=updated_budget["remaining_budget"],
            percentage_used=updated_budget["percentage_used"],
            status=BudgetStatus(updated_budget["status"]),
            description=updated_budget.get("description"),
            is_active=updated_budget["is_active"],
            currency=Currency(updated_budget.get("currency", "usd")),
            created_at=updated_budget["created_at"],
            updated_at=updated_budget["updated_at"]
        )
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error updating budget: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update budget"
        )


@router.delete("/{budget_id}")
async def delete_budget(
    budget_id: str = Path(...),
    current_user: dict = Depends(get_current_user)
):
    """Delete a budget"""
    try:
        # [FIX] Added await
        budget = await budgets_collection.find_one({
            "_id": budget_id,
            "user_id": current_user["_id"]
        })
        
        if not budget:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Budget not found"
            )
        
        # [FIX] Added await
        result = await budgets_collection.delete_one({
            "_id": budget_id,
            "user_id": current_user["_id"]
        })
        
        if result.deleted_count == 0:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to delete budget"
            )
        
        # Mark AI data as stale
        # [FIX] Added await
        await users_collection.update_one(
            {"_id": current_user["_id"]},
            {"$set": {"ai_data_stale": True}}
        )
        
        return {"message": "Budget deleted successfully"}
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error deleting budget: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete budget"
        )


@router.post("/{budget_id}/refresh")
async def refresh_budget(
    budget_id: str = Path(...),
    current_user: dict = Depends(get_current_user)
):
    """Manually refresh a budget's spent amounts"""
    try:
        # [FIX] Added await
        budget = await budgets_collection.find_one({
            "_id": budget_id,
            "user_id": current_user["_id"]
        })
        
        if not budget:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Budget not found"
            )
        
        # [FIX] Added await
        await update_budget_spent_amounts(current_user["_id"], budget_id)
        
        return {"message": "Budget refreshed successfully"}
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error refreshing budget: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to refresh budget"
        )