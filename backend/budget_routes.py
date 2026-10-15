import uuid
from datetime import datetime, UTC, timezone
from typing import List, Optional

from fastapi import APIRouter, HTTPException, status, Depends, Query, Path
from pydantic import ValidationError


from models import Currency
from finite_utils import finite_or
from utils import get_current_user, require_premium

from budget_models import AIBudgetRequest, AIBudgetSuggestion, BudgetCreate, BudgetPeriod, BudgetResponse, BudgetStatus, BudgetSummary, BudgetUpdate, CategoryBudget, CurrencyBudgetSummary, MultiCurrencyBudgetSummary
from budget_service import (
    BudgetAnalyzer,
    calculate_budget_status,
    calculate_total_budget_excluding_subcategories,
    derive_budget_state,
    is_budget_active,
    refresh_budget_state_if_stale,
    update_budget_spent_amounts,
)


from notification_service import notify_budget_started


from database import budgets_collection, users_collection


router = APIRouter(prefix="/api/budgets", tags=["budgets"])

# Statuses that count as the "current" budget set for summary totals.
_CURRENT_STATUSES = {BudgetStatus.ACTIVE.value, BudgetStatus.EXCEEDED.value}


_CATEGORY_NUMBER_FIELDS = ("allocated_amount", "spent_amount", "percentage_used")


def _category_budget(cat: dict) -> CategoryBudget:
    """Build a CategoryBudget from a stored dict without failing on legacy invalid values."""
    # Legacy NaN/inf numbers can't be JSON-encoded (the whole response would 500).
    cat = {**cat, **{k: finite_or(cat[k]) for k in _CATEGORY_NUMBER_FIELDS if k in cat}}
    try:
        return CategoryBudget(**cat)
    except ValidationError:
        return CategoryBudget.model_construct(**cat)


def _budget_response(b: dict) -> BudgetResponse:
    return BudgetResponse(
        id=b["_id"],
        user_id=b["user_id"],
        name=b["name"],
        period=BudgetPeriod(b["period"]),
        start_date=b["start_date"],
        end_date=b["end_date"],
        category_budgets=[_category_budget(cat) for cat in b["category_budgets"]],
        total_budget=finite_or(b["total_budget"]),
        total_spent=finite_or(b["total_spent"]),
        remaining_budget=finite_or(b["remaining_budget"]),
        percentage_used=finite_or(b["percentage_used"]),
        status=BudgetStatus(b["status"]),
        description=b.get("description"),
        is_active=b["is_active"],
        auto_create_enabled=b.get("auto_create_enabled", False),
        auto_create_with_ai=b.get("auto_create_with_ai", False),
        parent_budget_id=b.get("parent_budget_id"),
        currency=Currency(b.get("currency", "usd")),
        created_at=b["created_at"],
        updated_at=b["updated_at"]
    )


def _summarize(budgets: List[dict]) -> dict:
    """Counts + totals for a list of budgets, using date/spend-derived status."""
    now = datetime.now(UTC)
    states = [derive_budget_state(b, now)["status"] for b in budgets]
    # Exceeded budgets are still "current": they count in the totals.
    current = [b for b, s in zip(budgets, states) if s in _CURRENT_STATUSES]
    total_allocated = sum(finite_or(b.get("total_budget", 0) or 0) for b in current)
    total_spent = sum(finite_or(b.get("total_spent", 0) or 0) for b in current)
    return {
        "total_budgets": len(budgets),
        "active_budgets": states.count(BudgetStatus.ACTIVE.value),
        "upcoming_budgets": states.count(BudgetStatus.UPCOMING.value),
        "completed_budgets": states.count(BudgetStatus.COMPLETED.value),
        "exceeded_budgets": states.count(BudgetStatus.EXCEEDED.value),
        "total_allocated": total_allocated,
        "total_spent": total_spent,
        "overall_remaining": total_allocated - total_spent,
    }

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

    except HTTPException:
        raise
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
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

        # Calculate end date if not provided (custom budgets without end_date are
        # rejected by BudgetCreate validation with 422).
        if budget_data.end_date is None:
            analyzer = BudgetAnalyzer(current_user["_id"])
            try:
                start_date, end_date = analyzer.calculate_period_dates(
                    budget_data.period,
                    budget_data.start_date,
                    None
                )
            except ValueError as e:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
        else:
            start_date = budget_data.start_date
            end_date = budget_data.end_date

        # Ensure timezone-aware
        if start_date.tzinfo is None:
            start_date = start_date.replace(tzinfo=timezone.utc)
        if end_date.tzinfo is None:
            end_date = end_date.replace(tzinfo=timezone.utc)

        # Determine if currently active
        window = {"start_date": start_date, "end_date": end_date}
        is_active = is_budget_active(window, now)
        initial_status = calculate_budget_status(
            {**window, "category_budgets": []}, now, total_budget=budget_data.total_budget, total_spent=0.0
        )

        new_budget = {
            "_id": budget_id,
            "user_id": current_user["_id"],
            "name": budget_data.name,
            "period": budget_data.period.value,
            "start_date": start_date,
            "end_date": end_date,
            # Spend fields are server-computed: whatever the client sent for
            # spent_amount / percentage_used / is_exceeded is ignored and every category
            # starts at 0; update_budget_spent_amounts below fills in the real values.
            "category_budgets": [
                {**cat.model_dump(), "spent_amount": 0.0, "percentage_used": 0.0, "is_exceeded": False}
                for cat in budget_data.category_budgets
            ],
            # total_budget is the user's value (see BudgetUpdate rule); it is never
            # overwritten by the spent-amount recalculation.
            "total_budget": budget_data.total_budget,
            "total_spent": 0.0,
            "remaining_budget": budget_data.total_budget,
            "percentage_used": 0.0,
            "status": initial_status.value,
            "description": budget_data.description,
            "is_active": is_active,
            "auto_create_enabled": budget_data.auto_create_enabled,
            "auto_create_with_ai": budget_data.auto_create_with_ai,
            "parent_budget_id": None,
            "currency": budget_data.currency.value,
            # Already-running budgets get "budget_started" right below; upcoming ones get
            # the one-time "budget now active" when they start (see notify_budget_now_active_once).
            "started_notified": is_active,
            "created_at": now,
            "updated_at": now
        }

        await budgets_collection.insert_one(new_budget)

        await update_budget_spent_amounts(current_user["_id"], budget_id)

        if is_active:
            await notify_budget_started(
                user_id=current_user["_id"],
                budget_id=budget_id,
                budget_name=budget_data.name,
                total_budget=budget_data.total_budget,
                period=budget_data.period.value
            )

        # Mark AI data as stale
        await users_collection.update_one(
            {"_id": current_user["_id"]},
            {"$set": {"ai_data_stale": True}}
        )

        # Get updated budget
        updated_budget = await budgets_collection.find_one({"_id": budget_id})

        return _budget_response(updated_budget)

    except HTTPException:
        raise
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

        if period:
            query["period"] = period.value

        if currency:
            query["currency"] = currency.value

        cursor = budgets_collection.find(query).sort("created_at", -1)
        budgets = await cursor.to_list(length=None)

        # Status / is_active are derived from the dates (+ spend) and persisted if stale,
        # so expired budgets don't stay "active" forever.
        budgets = [await refresh_budget_state_if_stale(b) for b in budgets]

        if active_only:
            budgets = [b for b in budgets if b.get("is_active")]

        return [_budget_response(b) for b in budgets]

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

        cursor = budgets_collection.find(query)
        budgets = await cursor.to_list(length=None)

        return BudgetSummary(**_summarize(budgets), currency=currency)

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
        cursor = budgets_collection.find({"user_id": current_user["_id"]})
        all_budgets = await cursor.to_list(length=None)

        overall = _summarize(all_budgets)

        # Group budgets by currency
        currency_groups = {}
        for budget in all_budgets:
            currency_groups.setdefault(budget.get("currency", "usd"), []).append(budget)

        currency_summaries = [
            CurrencyBudgetSummary(currency=Currency(currency), **_summarize(budgets))
            for currency, budgets in currency_groups.items()
        ]

        return MultiCurrencyBudgetSummary(
            total_budgets=overall["total_budgets"],
            active_budgets=overall["active_budgets"],
            completed_budgets=overall["completed_budgets"],
            exceeded_budgets=overall["exceeded_budgets"],
            upcoming_budgets=overall["upcoming_budgets"],
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
        budget = await budgets_collection.find_one({
            "_id": budget_id,
            "user_id": current_user["_id"]
        })

        if not budget:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Budget not found"
            )

        budget = await refresh_budget_state_if_stale(budget)
        return _budget_response(budget)

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
    """
    Update a budget.

    total_budget rule: total_budget is the user's value. If the request sends
    total_budget it is stored as-is. If it sends category_budgets WITHOUT total_budget,
    the total is recomputed from the allocations (a "Main - Sub" allocation is not added
    when "Main" itself is budgeted). Spent-amount recalculation never changes it.
    """
    try:
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

        if budget_data.category_budgets is not None:
            # Spend is recomputed right below. Categories that already existed (matched by
            # main_category) keep their stored spent/percentage so the recompute compares
            # the new percentage with the REAL previous one: renaming/editing a budget must
            # not re-send 80%/exceeded alerts. Only categories new to the budget start at 0.
            previous = {
                c.get("main_category"): c
                for c in (budget.get("category_budgets") or [])
                if isinstance(c, dict) and c.get("main_category")
            }
            category_budgets = []
            for cat in budget_data.category_budgets:
                cat_dict = cat.model_dump()
                old = previous.get(cat_dict.get("main_category"))
                if old is not None:
                    cat_dict["spent_amount"] = old.get("spent_amount") or 0
                    cat_dict["percentage_used"] = old.get("percentage_used") or 0
                    cat_dict["is_exceeded"] = bool(old.get("is_exceeded", False))
                else:
                    cat_dict["spent_amount"] = 0
                    cat_dict["percentage_used"] = 0
                    cat_dict["is_exceeded"] = False
                category_budgets.append(cat_dict)

            update_data["category_budgets"] = category_budgets
            if budget_data.total_budget is None:
                update_data["total_budget"] = calculate_total_budget_excluding_subcategories(category_budgets)

        if budget_data.total_budget is not None:
            update_data["total_budget"] = budget_data.total_budget

        if "total_budget" in update_data:
            spent = budget.get("total_spent", 0) or 0
            new_total = update_data["total_budget"]
            update_data["remaining_budget"] = new_total - spent
            # percentage_used is deliberately NOT rewritten here: the recompute below
            # compares its fresh overall percentage against the stored (real previous)
            # one, so lowering the total under the spend still fires the overall alert
            # once, and raising/keeping it never re-fires it.

        if budget_data.auto_create_enabled is not None:
            update_data["auto_create_enabled"] = budget_data.auto_create_enabled

        if budget_data.auto_create_with_ai is not None:
            update_data["auto_create_with_ai"] = budget_data.auto_create_with_ai

        await budgets_collection.update_one(
            {"_id": budget_id},
            {"$set": update_data}
        )

        # Recalculate spent amounts / status (does not touch total_budget)
        await update_budget_spent_amounts(current_user["_id"], budget_id)

        # Mark AI data as stale
        await users_collection.update_one(
            {"_id": current_user["_id"]},
            {"$set": {"ai_data_stale": True}}
        )

        updated_budget = await budgets_collection.find_one({"_id": budget_id})

        return _budget_response(updated_budget)

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
        budget = await budgets_collection.find_one({
            "_id": budget_id,
            "user_id": current_user["_id"]
        })

        if not budget:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Budget not found"
            )

        result = await budgets_collection.delete_one({
            "_id": budget_id,
            "user_id": current_user["_id"]
        })

        if result.deleted_count == 0:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to delete budget"
            )

        # Deleting an auto-created child re-opens its parent for the nightly rollover job
        # (same behaviour as before the rolled_over_to marker existed).
        if budget.get("parent_budget_id"):
            try:
                await budgets_collection.update_one(
                    {"_id": budget["parent_budget_id"], "user_id": current_user["_id"], "rolled_over_to": budget_id},
                    {"$unset": {"rolled_over_to": ""}},
                )
            except Exception as e:
                print(f"⚠️ Failed to clear rollover marker of parent budget {budget['parent_budget_id']}: {e}")

        # Mark AI data as stale
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
        budget = await budgets_collection.find_one({
            "_id": budget_id,
            "user_id": current_user["_id"]
        })

        if not budget:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Budget not found"
            )

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
