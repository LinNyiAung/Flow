import asyncio
import json
from datetime import datetime, timedelta, timezone
from typing import List, Dict, Optional
from collections import defaultdict
import statistics
import uuid

from notification_service import check_budget_notifications, notify_budget_auto_created, notify_budget_now_active_once
from tz_utils import app_wall_clock_now
from database import transactions_collection, budgets_collection
from sql import goals as goals_db
from sql.categories import get_categories_doc
from budget_models import (
    BudgetPeriod, CategoryBudget, CategoryBudgetIn, AIBudgetSuggestion, BudgetStatus
)
from config import settings
from finite_utils import finite_amount_filter, is_finite_number
from pymongo.errors import DuplicateKeyError
import logging


logger = logging.getLogger(__name__)


# Strong references to fire-and-forget tasks (asyncio only keeps weak refs).
_background_tasks: set = set()

_CURRENCY_SYMBOLS = {"usd": "$", "mmk": "K", "thb": "฿"}

# Monthly fallback budgets for users with too little history for analysis. Keys are
# default outflow main categories (see database.py); amounts are set per currency as
# rough local starting points the user is expected to adjust.
_DEFAULT_MONTHLY_BUDGETS = {
    "Food & Daily Living": {"usd": 400, "mmk": 600_000, "thb": 9_000},
    "Housing & Utilities": {"usd": 300, "mmk": 300_000, "thb": 6_000},
    "Transportation": {"usd": 200, "mmk": 150_000, "thb": 3_000},
    "Shopping & Lifestyle": {"usd": 150, "mmk": 150_000, "thb": 3_000},
    "Entertainment & Leisure": {"usd": 100, "mmk": 80_000, "thb": 2_000},
    "Health & Insurance": {"usd": 100, "mmk": 100_000, "thb": 2_000},
}


def _append_valid_category(target: List[CategoryBudget], cat: Dict) -> None:
    """Append a CategoryBudget unless it fails input validation (e.g. negative/NaN amount from AI)."""
    try:
        target.append(CategoryBudget(**CategoryBudgetIn(**cat).model_dump()))
    except Exception as e:  # pydantic ValidationError / TypeError
        logger.warning(f"Skipping invalid category budget {cat!r}: {e}")


class BudgetAnalyzer:
    """Analyzes user's financial data for AI budget suggestions"""

    def __init__(self, user_id: str):
        self.user_id = user_id

    # [FIX] Changed to async def
    async def analyze_spending_patterns(self, months: int = 3, currency: str = "usd") -> Dict:
        """Analyze user's spending patterns over the last N months for specific currency"""
        cutoff_date = datetime.now(timezone.utc) - timedelta(days=months * 30)

        # [FIX] Async find
        cursor = transactions_collection.find({
            "user_id": self.user_id,
            "date": {"$gte": cutoff_date},
            "type": "outflow",
            "currency": currency,
            **finite_amount_filter(),  # legacy NaN/inf amounts would poison every statistic
        })
        transactions = await cursor.to_list(length=None)

        if len(transactions) < 10:
            return {
                "sufficient_data": False,
                "transaction_count": len(transactions),
                "message": f"Only {len(transactions)} transactions found. Need at least 10 for accurate analysis."
            }

        # Group by category
        category_data = defaultdict(lambda: {"amounts": [], "total": 0, "count": 0})

        for t in transactions:
            cat = t["main_category"]
            amount = t["amount"]
            category_data[cat]["amounts"].append(amount)
            category_data[cat]["total"] += amount
            category_data[cat]["count"] += 1

        # Calculate statistics per category
        category_stats = {}
        for cat, data in category_data.items():
            amounts = data["amounts"]
            category_stats[cat] = {
                "total_spent": data["total"],
                "transaction_count": data["count"],
                "average_per_transaction": data["total"] / data["count"],
                "monthly_average": data["total"] / months,
                "min_transaction": min(amounts),
                "max_transaction": max(amounts),
                "std_deviation": statistics.stdev(amounts) if len(amounts) > 1 else 0,
                "variability": "high" if len(amounts) > 1 and statistics.stdev(amounts) > data["total"] / data["count"] else "stable"
            }

        # [FIX] Async find for income
        income_cursor = transactions_collection.find({
            "user_id": self.user_id,
            "date": {"$gte": cutoff_date},
            "type": "inflow",
            "currency": currency,
            **finite_amount_filter(),
        })
        income_transactions = await income_cursor.to_list(length=None)

        total_income = sum(t["amount"] for t in income_transactions)
        monthly_income = total_income / months if income_transactions else 0

        # [FIX] Async find for goals
        goals = await goals_db.list_goals(self.user_id, status="active", currency=currency)

        total_goal_target = sum(g["target_amount"] for g in goals)
        total_goal_current = sum(g["current_amount"] for g in goals)

        return {
            "sufficient_data": True,
            "transaction_count": len(transactions),
            "analysis_period_months": months,
            "categories": category_stats,
            "income": {
                "total": total_income,
                "monthly_average": monthly_income,
                "transaction_count": len(income_transactions)
            },
            "goals": {
                "active_count": len(goals),
                "total_target": total_goal_target,
                "total_allocated": total_goal_current,
                "remaining_to_allocate": total_goal_target - total_goal_current
            },
            "total_expenses": sum(data["total_spent"] for data in category_stats.values())
        }

    def calculate_period_dates(self, period: BudgetPeriod, start_date: datetime, end_date: Optional[datetime] = None):
        """Calculate end date based on period type"""
        if period == BudgetPeriod.CUSTOM:
            if not end_date:
                raise ValueError("end_date is required for custom period")
            return start_date, end_date

        # Ensure start_date is timezone-aware
        if start_date.tzinfo is None:
            start_date = start_date.replace(tzinfo=timezone.utc)

        if period == BudgetPeriod.WEEKLY:
            # Calculate the start of the week (Monday)
            days_since_monday = start_date.weekday()  # Monday is 0, Sunday is 6
            week_start = start_date - timedelta(days=days_since_monday)
            week_start = week_start.replace(hour=0, minute=0, second=0, microsecond=0)

            # End is Sunday (6 days after Monday)
            week_end = week_start + timedelta(days=6, hours=23, minutes=59, seconds=59)
            return week_start, week_end

        elif period == BudgetPeriod.MONTHLY:
            # Use the selected start date as-is (don't force to 1st of month)
            month_start = start_date.replace(hour=0, minute=0, second=0, microsecond=0)

            # End of month calculation
            if start_date.month == 12:
                month_end = start_date.replace(month=12, day=31, hour=23, minute=59, second=59)
            else:
                next_month = start_date.replace(month=start_date.month + 1, day=1)
                month_end = (next_month - timedelta(days=1)).replace(hour=23, minute=59, second=59)

            return month_start, month_end

        elif period == BudgetPeriod.YEARLY:
            # Use the selected start date as-is (don't force to Jan 1)
            year_start = start_date.replace(hour=0, minute=0, second=0, microsecond=0)
            # End of year: December 31 at 23:59:59
            year_end = start_date.replace(month=12, day=31, hour=23, minute=59, second=59)
            return year_start, year_end

    async def generate_ai_suggestions(
        self,
        period: BudgetPeriod,
        start_date: datetime,
        end_date: Optional[datetime] = None,
        analysis_months: int = 3,
        include_categories: Optional[List[str]] = None,
        user_context: Optional[str] = None,
        currency: str = "usd"
    ) -> AIBudgetSuggestion:
        """Generate AI budget suggestions for specific currency"""

        # [FIX] Added await
        analysis = await self.analyze_spending_patterns(analysis_months, currency)

        warnings = []
        data_confidence = 1.0

        if not analysis["sufficient_data"]:
            warnings.append(analysis["message"])
            warnings.append("Budget suggestions will be based on limited data and may not be accurate.")
            data_confidence = 0.3
        elif analysis["transaction_count"] < 30:
            warnings.append(f"Only {analysis['transaction_count']} transactions available. More data will improve accuracy.")
            data_confidence = 0.6

        # Calculate budget period dates
        budget_start, budget_end = self.calculate_period_dates(period, start_date, end_date)

        # Calculate days in budget period
        days_in_period = (budget_end - budget_start).days + 1

        # Use OpenAI to generate smart suggestions
        if settings.OPENAI_API_KEY and analysis["sufficient_data"]:
            suggestions = await self._generate_with_ai(
                analysis, period, days_in_period, include_categories, user_context, currency  # NEW parameter
            )
        else:
            suggestions = self._generate_basic_suggestions(
                analysis, days_in_period, include_categories, currency
            )

        # Calculate totals. Same rule as stored budgets: a "Main - Sub" line is part of
        # its main category's budget when that main is also listed, so it isn't added twice.
        total_budget = calculate_total_budget_excluding_subcategories(
            [{"main_category": cat.main_category, "allocated_amount": cat.allocated_amount}
             for cat in suggestions["categories"]]
        )

        # Generate name if not provided
        period_names = {
            BudgetPeriod.WEEKLY: "Weekly Budget",
            BudgetPeriod.MONTHLY: "Monthly Budget",
            BudgetPeriod.YEARLY: "Yearly Budget",
            BudgetPeriod.CUSTOM: "Custom Budget"
        }

        suggested_name = f"{period_names[period]} - {budget_start.strftime('%b %Y')}"

        return AIBudgetSuggestion(
            suggested_name=suggested_name,
            period=period,
            start_date=budget_start,
            end_date=budget_end,
            category_budgets=suggestions["categories"],
            total_budget=total_budget,
            reasoning=suggestions["reasoning"],
            data_confidence=data_confidence,
            warnings=warnings,
            currency=currency,  # NEW
            analysis_summary={
                "transaction_count": analysis.get("transaction_count", 0),
                "analysis_months": analysis_months,
                "categories_analyzed": len(analysis.get("categories", {})),
                "average_monthly_income": analysis.get("income", {}).get("monthly_average", 0),
                "average_monthly_expenses": analysis.get("total_expenses", 0) / analysis_months if analysis.get("total_expenses") else 0,
                "active_goals": analysis.get("goals", {}).get("active_count", 0)
            }
        )

    async def _generate_with_ai(
        self,
        analysis: Dict,
        period: BudgetPeriod,
        days_in_period: int,
        include_categories: Optional[List[str]],
        user_context: Optional[str] = None,
        currency: str = "usd"
    ) -> Dict:
        """Use OpenAI to generate intelligent budget suggestions"""
        from openai import AsyncOpenAI
        client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)

        currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")

        # [FIX] Added await
        outflow_categories_doc = await get_categories_doc("outflow")
        categories_structure = []

        if outflow_categories_doc:
            for cat in outflow_categories_doc["categories"]:
                categories_structure.append({
                    "main_category": cat["main_category"],
                    "sub_categories": cat["sub_categories"]
                })

        # Create detailed categories structure for the prompt
        categories_info = []
        for cat_struct in categories_structure:
            sub_cats = ", ".join(cat_struct["sub_categories"])
            categories_info.append(f"- {cat_struct['main_category']}: [{sub_cats}]")

        categories_list = "\n".join(categories_info)

        # Prepare analysis context
        context = {
            "period_type": period.value,
            "days_in_period": days_in_period,
            "spending_analysis": analysis.get("categories", {}),
            "monthly_income": analysis.get("income", {}).get("monthly_average", 0),
            "monthly_expenses": analysis.get("total_expenses", 0) / analysis.get("analysis_period_months", 1),
            "active_goals": analysis.get("goals", {})
        }

        # Add user context if provided
        context_instruction = ""
        if user_context:
            context_instruction = f"\n\nUSER CONTEXT: {user_context}\nIMPORTANT: Adjust budget allocations based on this context."

        system_prompt = f"""You are a financial budgeting expert. Analyze the user's spending patterns and suggest realistic budgets.

    IMPORTANT: The budget period spans {days_in_period} days.

    AVAILABLE CATEGORIES WITH SUB-CATEGORIES:
    {categories_list}

    CRITICAL RULES:
    1. You MUST ONLY use categories and sub-categories from the "AVAILABLE CATEGORIES" list above
    2. DO NOT create or suggest any new category or sub-category names
    3. For each budget allocation, you can either:
    - Budget for a MAIN CATEGORY (covers all sub-categories under it)
    - Budget for a SPECIFIC SUB-CATEGORY (e.g., "Food & Dining - Restaurants")
    4. If you see spending patterns that suggest specific sub-category budgeting would be helpful, include those
    5. Budget for SPECIFIC SUB-CATEGORIES as much as possible rather than just a MAIN CATEGORY
    6. Format for main category: "Main Category Name"
    7. Format for sub-category: "Main Category Name - Sub Category Name"
    8. You can budget for both main category AND its sub-categories
    9. If you suggest budget for both main category AND its sub-categories, the budget for main category must be greater than its sub-categories combined
    10. Base suggestions on historical spending patterns, scaled to the {days_in_period}-day period
    11. Consider income vs expenses ratio
    12. Account for active financial goals
    13. Add 10-15% buffer for categories with high variability
    14. Prioritize essential spending categories
    15. Ensure total budget doesn't exceed 80% of income (leave room for savings and goals)
    {context_instruction}

    EXAMPLES OF VALID BUDGET ENTRIES:
    - {{"main_category": "Example Main", "allocated_amount": 500.00, ...}} (covers all Example Main)
    - {{"main_category": "Example Main - Example Sub", "allocated_amount": 100.00, ...}} (only Example Sub)
    - {{"main_category": "Example Main - Example Sub2", "allocated_amount": 300.00, ...}} (only Example Sub2)

    Return JSON format:
    {{
        "categories": [
            {{
                "main_category": "category name or category name - sub category name",
                "allocated_amount": 500.00,
                "spent_amount": 0,
                "percentage_used": 0,
                "is_exceeded": false
            }}
        ],
        "reasoning": "Detailed explanation of budget suggestions including why certain sub-categories were chosen"
    }}"""

        user_prompt = f"""Based on this financial data, suggest a {period.value} budget in {currency.upper()}:

SPENDING ANALYSIS:
{json.dumps(context, indent=2)}

All amounts should be in {currency.upper()} ({currency_symbol}).

{f"Focus on these categories: {', '.join(include_categories)}" if include_categories else "Suggest budgets for relevant spending categories. Include specific sub-category budgets where spending patterns suggest it would be helpful."}

Calculate budgets for {days_in_period} days period.

REMEMBER: 
- Only use categories/sub-categories from the AVAILABLE CATEGORIES list
- If you suggest budget for both main category AND its sub-categories, the budget for main category must be greater than its sub-categories combined
- Budget for SPECIFIC SUB-CATEGORIES as much as possible rather than just a MAIN CATEGORY
- Use sub-category budgets when spending patterns show clear distinctions
- All amounts must be in {currency.upper()}"""

        response = await client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            response_format={"type": "json_object"},
            temperature=0.3
        )

        # NEW: Track AI usage
        if hasattr(response, 'usage'):
            from ai_usage_service import track_ai_usage
            from ai_usage_models import AIFeatureType, AIProviderType

            input_tokens = response.usage.prompt_tokens
            output_tokens = response.usage.completion_tokens
            total_tokens = response.usage.total_tokens

            logger.info(f"📊 [OPENAI TOKEN USAGE - AI Budget Suggestion] User: {self.user_id}")
            logger.info(f"   📥 Input tokens: {input_tokens:,}")
            logger.info(f"   📤 Output tokens: {output_tokens:,}")
            logger.info(f"   📊 Total tokens: {total_tokens:,}")
            logger.info(f"   🤖 Model: gpt-4o-mini")

            await track_ai_usage(
                user_id=self.user_id,
                feature_type=AIFeatureType.BUDGET_SUGGESTION,
                provider=AIProviderType.OPENAI,
                model_name="gpt-4o-mini",
                input_tokens=input_tokens,
                output_tokens=output_tokens,
                total_tokens=total_tokens
            )

        result = json.loads(response.choices[0].message.content)

        # Validate that all categories exist in the system
        valid_categories = []
        available_main_categories = [cat["main_category"] for cat in categories_structure]
        raw_categories = result.get("categories") or []

        for cat in raw_categories:
            if not isinstance(cat, dict) or not isinstance(cat.get("main_category"), str):
                continue
            category_name = cat["main_category"]

            # Check if it's a sub-category budget (contains " - ")
            if " - " in category_name:
                parts = category_name.split(" - ", 1)
                main_cat = parts[0]
                sub_cat = parts[1]

                # Validate main category exists
                if main_cat not in available_main_categories:
                    print(f"Warning: AI suggested invalid main category '{main_cat}', skipping...")
                    continue

                # Validate sub-category exists
                category_struct = next(
                    (c for c in categories_structure if c["main_category"] == main_cat),
                    None
                )

                if category_struct and sub_cat in category_struct["sub_categories"]:
                    _append_valid_category(valid_categories, cat)
                else:
                    print(f"Warning: AI suggested invalid sub-category '{sub_cat}' for '{main_cat}', skipping...")
            else:
                # It's a main category budget
                if category_name in available_main_categories:
                    _append_valid_category(valid_categories, cat)
                else:
                    # Try case-insensitive match
                    matched = False
                    for available_cat in available_main_categories:
                        if available_cat.lower() == category_name.lower():
                            cat["main_category"] = available_cat
                            _append_valid_category(valid_categories, cat)
                            matched = True
                            break

                    if not matched:
                        print(f"Warning: AI suggested invalid category '{category_name}', skipping...")

        # Update result with validated categories
        result["categories"] = valid_categories
        result.setdefault("reasoning", "")

        # Add warning if some categories were skipped
        if len(valid_categories) < len(raw_categories):
            result["reasoning"] += "\n\nNote: Some suggested categories were not available in your system and were excluded."

        return result

    def _generate_basic_suggestions(
        self,
        analysis: Dict,
        days_in_period: int,
        include_categories: Optional[List[str]],
        currency: str = "usd"
    ) -> Dict:
        """Generate basic budget suggestions without AI"""
        categories = []
        reasoning_parts = []
        symbol = _CURRENCY_SYMBOLS.get(currency, "")

        if not analysis.get("sufficient_data"):
            # Very limited data - use conservative monthly defaults. Names must be real
            # main categories (budgets only track spending in exactly matching ones) and
            # amounts are per currency: there are no exchange rates to convert USD with.
            default_budgets = {
                cat: amounts.get(currency, amounts["usd"])
                for cat, amounts in _DEFAULT_MONTHLY_BUDGETS.items()
            }

            for cat, amount in default_budgets.items():
                if include_categories and cat not in include_categories:
                    continue

                # Scale to period
                if days_in_period <= 7:
                    scaled_amount = amount * 0.25
                elif days_in_period <= 31:
                    scaled_amount = amount
                else:
                    scaled_amount = amount * (days_in_period / 30)

                categories.append(CategoryBudget(
                    main_category=cat,
                    allocated_amount=round(scaled_amount, 2),
                    spent_amount=0,
                    percentage_used=0,
                    is_exceeded=False
                ))

            reasoning_parts.append("Budget based on conservative default values due to limited transaction history.")
        else:
            # Use historical data
            category_stats = analysis["categories"]
            months_analyzed = analysis["analysis_period_months"]

            for cat, stats in category_stats.items():
                if include_categories and cat not in include_categories:
                    continue

                # Calculate budget based on historical average + buffer
                monthly_avg = stats["monthly_average"]

                # Add buffer based on variability
                buffer = 1.15 if stats["variability"] == "high" else 1.10

                # Scale to period
                if days_in_period <= 7:
                    period_budget = (monthly_avg / 30) * days_in_period * buffer
                elif days_in_period <= 31:
                    period_budget = monthly_avg * buffer
                else:
                    period_budget = monthly_avg * (days_in_period / 30) * buffer

                categories.append(CategoryBudget(
                    main_category=cat,
                    allocated_amount=round(period_budget, 2),
                    spent_amount=0,
                    percentage_used=0,
                    is_exceeded=False
                ))

                reasoning_parts.append(
                    f"{cat}: {symbol}{period_budget:,.2f} (based on {symbol}{monthly_avg:,.2f}/month average, {stats['variability']} variability)"
                )

        reasoning = "Budget suggestions:\n" + "\n".join(reasoning_parts)

        return {
            "categories": categories,
            "reasoning": reasoning
        }


def _aware(dt: datetime) -> datetime:
    return dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt


def calculate_budget_status(
    budget: Dict,
    current_date: datetime,
    total_budget: Optional[float] = None,
    total_spent: Optional[float] = None,
) -> BudgetStatus:
    """
    Calculate the current status of a budget.

    current_date is a real instant (e.g. datetime.now(UTC)); it is converted to the app
    timezone's wall clock before comparing with the stored (wall-clock, UTC-tagged)
    start/end dates.

    total_budget / total_spent override the (possibly stale) values stored in `budget`;
    callers that just recomputed spending must pass the fresh totals. Category
    `is_exceeded` flags are read from budget["category_budgets"], so update them first.
    """
    current_date = app_wall_clock_now(_aware(current_date))
    start_date = _aware(budget["start_date"])
    end_date = _aware(budget["end_date"])

    # Check if budget hasn't started yet
    if current_date < start_date:
        return BudgetStatus.UPCOMING

    # Check if budget period has ended
    if current_date > end_date:
        return BudgetStatus.COMPLETED

    if total_budget is None:
        total_budget = budget.get("total_budget", 0) or 0
    if total_spent is None:
        total_spent = budget.get("total_spent", 0) or 0

    if round(total_spent, 2) > round(total_budget, 2):
        return BudgetStatus.EXCEEDED

    # Check individual categories
    for cat_budget in budget.get("category_budgets", []):
        if cat_budget.get("is_exceeded", False):
            return BudgetStatus.EXCEEDED

    return BudgetStatus.ACTIVE


def is_budget_active(budget: Dict, current_date: datetime) -> bool:
    """Check if a budget is currently active (within its date range, inclusive).

    current_date is a real instant; compared as app-timezone wall clock (see calculate_budget_status).
    """
    current_date = app_wall_clock_now(_aware(current_date))
    return _aware(budget["start_date"]) <= current_date <= _aware(budget["end_date"])


def derive_budget_state(budget: Dict, current_date: Optional[datetime] = None) -> Dict:
    """Date + spend derived {"status": str, "is_active": bool} for a stored budget document."""
    now = current_date or datetime.now(timezone.utc)
    return {
        "status": calculate_budget_status(budget, now).value,
        "is_active": is_budget_active(budget, now),
    }


async def refresh_budget_state_if_stale(budget: Dict) -> Dict:
    """
    Make sure a budget's status/is_active reflect the current date (expired budgets must
    not stay "active" forever). If the stored values are stale, the budget is recomputed
    and persisted (which also triggers auto-create of the next budget on completion).
    Returns the up-to-date budget document.
    """
    derived = derive_budget_state(budget)
    # Stored totals that are NaN/inf (computed before non-finite amounts were excluded)
    # also count as stale: the recompute below replaces them with real numbers.
    numbers_ok = all(
        is_finite_number(budget.get(k)) for k in ("total_spent", "remaining_budget", "percentage_used")
        if budget.get(k) is not None
    )
    if numbers_ok and budget.get("status") == derived["status"] and budget.get("is_active") == derived["is_active"]:
        return budget
    try:
        await update_budget_spent_amounts(budget["user_id"], budget["_id"], budget_doc=dict(budget))
        fresh = await budgets_collection.find_one({"_id": budget["_id"]})
        if fresh:
            return fresh
    except Exception as e:
        logger.error(f"Failed to refresh budget {budget.get('_id')}: {e}")
    # Fallback: at least return (and try to persist) the date-derived state.
    patched = {**budget, **derived}
    try:
        await budgets_collection.update_one({"_id": budget["_id"]}, {"$set": derived})
    except Exception:
        pass
    return patched


# A budget is "running" (counts as the user's current budget for chat, insights and
# "ending soon" alerts) when today's app wall clock is inside its date window AND its
# status is active or exceeded. Exceeded budgets are still running.
RUNNING_BUDGET_STATUSES = (BudgetStatus.ACTIVE.value, BudgetStatus.EXCEEDED.value)


def is_budget_running(budget: Dict, current_date: Optional[datetime] = None) -> bool:
    """True if the budget's window contains now (app wall clock) and status is active/exceeded."""
    now = current_date or datetime.now(timezone.utc)
    return budget.get("status") in RUNNING_BUDGET_STATUSES and is_budget_active(budget, now)


async def get_running_budgets(
    user_id: str,
    currency: Optional[str] = None,
    recompute: bool = False,
) -> List[Dict]:
    """
    The user's running budgets (newest first).

    Candidates are selected by date window only (stored status can be stale, e.g. still
    "upcoming" after the start date), then each one is refreshed before deciding:
    recompute=True recalculates spend for every candidate (chatbot: fresh numbers),
    otherwise only budgets whose stored status/is_active are stale are recomputed.
    """
    wall_now = app_wall_clock_now()
    query = {"user_id": user_id, "start_date": {"$lte": wall_now}, "end_date": {"$gte": wall_now}}
    if currency:
        query["currency"] = currency
    candidates = await budgets_collection.find(query).sort("created_at", -1).to_list(length=None)

    running: List[Dict] = []
    for budget in candidates:
        try:
            if recompute:
                await update_budget_spent_amounts(user_id, budget["_id"], budget_doc=dict(budget))
                budget = await budgets_collection.find_one({"_id": budget["_id"]}) or budget
            else:
                budget = await refresh_budget_state_if_stale(budget)
        except Exception as e:
            logger.error(f"Failed to refresh budget {budget.get('_id')}: {e}")
        if is_budget_running(budget):
            running.append(budget)
    return running


async def update_budget_spent_amounts(
    user_id: str,
    budget_id: str,
    budget_doc: Optional[Dict] = None,
    trigger_auto_create: bool = True,
):
    """
    Recalculate spent amounts for a budget using MongoDB Aggregation for O(1) memory usage.
    Uses Optimistic Locking to prevent race conditions.

    trigger_auto_create: when the recompute finds the budget COMPLETED and auto-create is
    enabled, schedule auto_create_next_budget in the background. The daily rollover job
    passes False and awaits auto_create_next_budget itself.
    """
    max_retries = 3
    attempt = 0

    while attempt < max_retries:
        try:
            # 1. Get the budget document and its version (updated_at)
            if attempt == 0 and budget_doc:
                budget = budget_doc
            else:
                budget = await budgets_collection.find_one({"_id": budget_id, "user_id": user_id})

            if not budget:
                return

            # CAPTURE VERSION for optimistic lock
            current_version_timestamp = budget.get("updated_at")

            # Store old values for notification checks. These are the REAL previously
            # stored percentages (the update route preserves them for categories that
            # already existed), so threshold alerts only fire on an actual crossing.
            # Categories that are new to the budget have no previous value -> 0.
            old_total_percentage = budget.get("percentage_used") or 0
            old_category_percentages = {
                cat["main_category"]: (cat.get("percentage_used") or 0)
                for cat in budget["category_budgets"]
            }

            budget_currency = budget.get("currency", "usd")

            # 2. AGGREGATION PIPELINE (The Fix)
            # Instead of fetching all transactions, we ask Mongo to sum them up by category
            pipeline = [
                {
                    "$match": {
                        "user_id": user_id,
                        "type": "outflow",
                        "currency": budget_currency,
                        "date": {
                            "$gte": budget["start_date"],
                            "$lte": budget["end_date"]
                        },
                        # Excludes legacy NaN/inf amounts (one would make every sum NaN).
                        **finite_amount_filter(),
                    }
                },
                {
                    "$group": {
                        "_id": {
                            "main": "$main_category",
                            "sub": "$sub_category"
                        },
                        "total_amount": {"$sum": "$amount"}
                    }
                }
            ]

            # Execute aggregation
            cursor = transactions_collection.aggregate(pipeline)
            agg_results = await cursor.to_list(length=None)

            # 3. Process Results in Memory
            # Create a lookup set for categories actually in the budget
            budget_category_keys = set(cat["main_category"] for cat in budget["category_budgets"])

            # Temporary storage for calculations
            category_spent_map = defaultdict(float)
            total_spent_accum = 0.0

            for res in agg_results:
                group_key = res["_id"] or {}
                amount = res.get("total_amount")
                if not is_finite_number(amount):
                    logger.warning(f"Budget {budget_id}: ignoring non-finite spend group {group_key!r}")
                    continue

                main_cat = group_key.get("main")
                sub_cat = group_key.get("sub")

                # Construct keys matching budget format
                main_key = main_cat
                sub_key = f"{main_cat} - {sub_cat}"

                # Determine if this transaction group matches ANY bucket in the budget
                is_relevant = False

                # 1. Match Main Category (e.g., "Food")
                if main_key in budget_category_keys:
                    category_spent_map[main_key] += amount
                    is_relevant = True

                # 2. Match Specific Sub-Category (e.g., "Food - Groceries")
                if sub_key in budget_category_keys:
                    category_spent_map[sub_key] += amount
                    is_relevant = True

                # Only add to total spent if it matched a tracked category
                if is_relevant:
                    total_spent_accum += amount

            # Update category objects in the budget dictionary
            for cat_budget in budget["category_budgets"]:
                budget_category = cat_budget["main_category"]

                spent = category_spent_map.get(budget_category, 0.0)
                allocated = cat_budget["allocated_amount"]

                # Calculate percentage
                new_cat_percentage = (spent / allocated * 100) if allocated > 0 else 0

                cat_budget["spent_amount"] = spent
                cat_budget["percentage_used"] = new_cat_percentage
                cat_budget["is_exceeded"] = spent > allocated

            # Update Totals.
            # Rule: total_budget is the user's value and is NOT recomputed here (it is only
            # derived from category allocations by the update route when categories change
            # without an explicit total). Legacy docs without a total fall back to the
            # category sum (sub-categories under a budgeted main category not double counted).
            total_budget = budget.get("total_budget")
            if total_budget is None:
                total_budget = calculate_total_budget_excluding_subcategories(budget["category_budgets"])
            remaining = total_budget - total_spent_accum
            new_total_percentage = (total_spent_accum / total_budget * 100) if total_budget > 0 else 0

            # Recalculate status from the FRESH totals (not the stale stored ones), so removing
            # an overspend flips the budget back to active immediately.
            now_utc = datetime.now(timezone.utc)
            status_enum = calculate_budget_status(
                budget, now_utc, total_budget=total_budget, total_spent=total_spent_accum
            )
            is_active = is_budget_active(budget, now_utc)

            # 4. Attempt Atomic Update with Optimistic Lock
            #
            result = await budgets_collection.update_one(
                {
                    "_id": budget_id,
                    "updated_at": current_version_timestamp
                },
                {
                    "$set": {
                        "category_budgets": budget["category_budgets"],
                        "total_budget": total_budget,
                        "total_spent": total_spent_accum,
                        "remaining_budget": remaining,
                        "percentage_used": new_total_percentage,
                        "status": status_enum.value,
                        "is_active": is_active,
                        "updated_at": datetime.now(timezone.utc)
                    }
                }
            )

            if result.modified_count == 1:
                # === SUCCESS ===

                # Check notifications (Async - fire and forget if needed, but here we await)
                for cat_budget in budget["category_budgets"]:
                    cat_name = cat_budget["main_category"]
                    new_pct = cat_budget["percentage_used"]
                    old_pct = old_category_percentages.get(cat_name, 0)

                    if new_pct != old_pct:
                        await check_budget_notifications(
                            user_id=user_id,
                            budget_id=budget_id,
                            old_percentage=old_pct,
                            new_percentage=new_pct,
                            budget_name=budget["name"],
                            category_name=cat_name
                        )

                # Check total budget notifications
                if new_total_percentage != old_total_percentage:
                    await check_budget_notifications(
                        user_id=user_id,
                        budget_id=budget_id,
                        old_percentage=old_total_percentage,
                        new_percentage=new_total_percentage,
                        budget_name=budget["name"],
                        category_name=None
                    )

                # Upcoming -> running transition (whichever path triggered the recompute:
                # list/get refresh, a new transaction, the daily job...): send the one-time
                # "budget now active" notification (deduped by the started_notified flag).
                if (
                    is_active
                    and budget.get("status") == BudgetStatus.UPCOMING.value
                    and not budget.get("started_notified")
                ):
                    try:
                        await notify_budget_now_active_once({**budget, "total_budget": total_budget})
                    except Exception as e:
                        logger.error(f"Failed to send budget-now-active for {budget_id}: {e}")

                # Check Auto-Create Logic
                if (
                    trigger_auto_create
                    and status_enum == BudgetStatus.COMPLETED
                    and budget.get("auto_create_enabled")
                ):
                    updated_budget = await budgets_collection.find_one({"_id": budget_id})
                    try:
                        if updated_budget:
                            task = asyncio.get_running_loop().create_task(auto_create_next_budget(updated_budget))
                            _background_tasks.add(task)
                            task.add_done_callback(_background_tasks.discard)
                    except Exception as e:
                        print(f"Error triggering auto-create: {e}")

                return # Exit successfully

            else:
                # === FAILURE (Race Condition) ===
                attempt += 1
                if attempt < max_retries:
                    budget_doc = None # Force re-fetch
                    await asyncio.sleep(0.05 * attempt)
                    continue

        except Exception as e:
            print(f"Error in update_budget_spent_amounts (attempt {attempt}): {str(e)}")
            import traceback
            traceback.print_exc()
            attempt += 1
            await asyncio.sleep(0.1)

    print(f"❌ Failed to update budget {budget_id} after {max_retries} attempts.")



async def _find_child_budget(budget: Dict) -> Optional[Dict]:
    """
    Any budget auto-created from `budget` ({_id} only, or None). Queries by (user_id,
    parent_budget_id) so it is served by the budgets indexes, not a collection scan.
    """
    return await budgets_collection.find_one(
        {"user_id": budget["user_id"], "parent_budget_id": budget["_id"]}, {"_id": 1}
    )


async def _mark_rolled_over(budget_id: str, child_id: str) -> None:
    """Remember that budget_id already has its next-period child (skipped by the nightly job)."""
    try:
        await budgets_collection.update_one({"_id": budget_id}, {"$set": {"rolled_over_to": child_id}})
    except Exception as e:
        logger.warning(f"Could not mark budget {budget_id} as rolled over: {e}")


async def process_due_budget_rollovers() -> Dict[str, int]:
    """
    Daily job: create the next-period budget for auto-create budgets whose period ended.

    Before this job, the next budget was only created when something happened to
    recompute the finished budget (opening the budgets screen, a new transaction in its
    range...). Selects auto_create_enabled budgets whose end_date has passed (app wall
    clock) and that have no child yet, completes them (recompute) and awaits
    auto_create_next_budget, which keeps its own duplicate check and atomic claim.

    A failed attempt (auto_create_next_budget releases its claim on error; a crashed claim
    expires after 10 minutes) is simply retried on the next run. A budget stops being
    selected once its child exists: the parent is then marked with rolled_over_to=<child
    id> (set by auto_create_next_budget, or backfilled here for budgets created before
    the marker existed), so each series only costs its latest budget per run. The child
    check is an indexed (user_id, parent_budget_id) lookup, never a collection scan.
    """
    wall_now = app_wall_clock_now()
    stats = {"candidates": 0, "created": 0, "skipped": 0, "not_created": 0, "failed": 0, "already_rolled_over": 0}

    try:
        unmarked = await budgets_collection.find({
            "auto_create_enabled": True,
            "end_date": {"$lt": wall_now},
            "rolled_over_to": {"$exists": False},
        }).to_list(length=None)
    except Exception as e:
        logger.error(f"Budget rollover job: failed to load candidates: {e}")
        return stats

    candidates = []
    for budget in unmarked:
        try:
            child = await _find_child_budget(budget)
        except Exception as e:
            stats["failed"] += 1
            logger.error(f"Budget rollover job: child lookup for budget {budget.get('_id')} failed: {e}")
            continue
        if child:
            # Legacy series member (or created concurrently): mark it so it is never
            # selected again.
            await _mark_rolled_over(budget["_id"], child["_id"])
            stats["already_rolled_over"] += 1
        else:
            candidates.append(budget)

    stats["candidates"] = len(candidates)
    for budget in candidates:
        budget_id = budget.get("_id")
        try:
            if budget.get("status") != BudgetStatus.COMPLETED.value or budget.get("is_active"):
                # Persist the final spend/status first (no background auto-create: we do it below).
                await update_budget_spent_amounts(
                    budget["user_id"], budget_id, budget_doc=dict(budget), trigger_auto_create=False
                )
                budget = await budgets_collection.find_one({"_id": budget_id}) or budget
            if budget.get("status") != BudgetStatus.COMPLETED.value or not budget.get("auto_create_enabled"):
                stats["skipped"] += 1
                continue
            new_id = await auto_create_next_budget(budget)
            if new_id:
                stats["created"] += 1
            elif child := await _find_child_budget(budget):
                await _mark_rolled_over(budget_id, child["_id"])
                stats["skipped"] += 1  # created concurrently / duplicate
            else:
                # Duplicate same-day budget, lost claim or an error inside auto-create
                # (which releases its claim): retried on the next run.
                stats["not_created"] += 1
        except Exception as e:
            stats["failed"] += 1
            logger.error(f"Budget rollover job: budget {budget_id} failed (will retry next run): {e}")

    logger.info(f"Budget rollover job finished: {stats}")
    return stats


async def update_relevant_budgets(user_id: str, transaction_date: datetime, transaction_currency: str):
    """Update only budgets that are affected by the transaction"""
    if transaction_date.tzinfo is None:
        transaction_date = transaction_date.replace(tzinfo=timezone.utc)

    query = {
        "user_id": user_id,
        "currency": transaction_currency,
        "start_date": {"$lte": transaction_date},
        "end_date": {"$gte": transaction_date}
    }

    # [FIX] Async find
    cursor = budgets_collection.find(query)
    relevant_budgets = await cursor.to_list(length=None)

    for budget in relevant_budgets:
        # [FIX] Added await
        await update_budget_spent_amounts(user_id, budget["_id"], budget_doc=budget)


async def update_budgets_in_range(user_id: str, start: datetime, end: datetime, currency: str):
    """Recompute every budget (of `currency`) whose period overlaps [start, end]."""
    start, end = _aware(start), _aware(end)
    if end < start:
        start, end = end, start
    cursor = budgets_collection.find({
        "user_id": user_id,
        "currency": currency,
        "start_date": {"$lte": end},
        "end_date": {"$gte": start},
    })
    for budget in await cursor.to_list(length=None):
        await update_budget_spent_amounts(user_id, budget["_id"], budget_doc=budget)


def calculate_total_budget_excluding_subcategories(category_budgets: List[Dict]) -> float:
    """
    Calculate total budget excluding sub-categories that fall under main categories.
    For example, if we have "Shopping" and "Shopping - Clothing", only count "Shopping".
    """
    main_categories = set()
    sub_category_pairs = []

    # First, identify all categories
    for cat_budget in category_budgets:
        category_name = cat_budget["main_category"]
        if " - " in category_name:
            parts = category_name.split(" - ", 1)
            main_cat = parts[0]
            sub_cat = parts[1]
            sub_category_pairs.append((main_cat, sub_cat, cat_budget["allocated_amount"]))
        else:
            main_categories.add(category_name)

    total = 0.0

    # Add all main category budgets
    for cat_budget in category_budgets:
        category_name = cat_budget["main_category"]
        if " - " not in category_name:
            total += cat_budget["allocated_amount"]

    # Add sub-category budgets only if their main category doesn't exist
    for main_cat, sub_cat, amount in sub_category_pairs:
        if main_cat not in main_categories:
            total += amount

    return total


async def auto_create_next_budget(budget: Dict) -> Optional[str]:
    """Automatically create next budget based on completed budget"""
    budget_id = budget["_id"]

    if not budget.get("auto_create_enabled", False):
        return None

    if budget["status"] != BudgetStatus.COMPLETED.value:
        return None

    user_id = budget["user_id"]
    currency = budget.get("currency", "usd")
    period = BudgetPeriod(budget["period"])
    old_start = _aware(budget["start_date"])
    old_end = _aware(budget["end_date"])

    # Next period starts at the beginning of the day after the parent's end date
    # (end_date is typically 23:59:59, so "+1 day" alone would land on 23:59:59).
    next_start_date = (old_end + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)

    # Compute the real next period BEFORE any expensive work.
    analyzer = BudgetAnalyzer(user_id)

    def _period_after(start: datetime):
        if period == BudgetPeriod.CUSTOM:
            return start, start + (old_end - old_start)
        return analyzer.calculate_period_dates(period, start, None)

    try:
        new_start, new_end = _period_after(next_start_date)
        # If the user was away for several periods, jump straight to the period containing
        # "now" instead of creating (and paying AI for) every missed period one by one.
        now_check = app_wall_clock_now()
        for _ in range(1000):
            if _aware(new_end) >= now_check:
                break
            following = (_aware(new_end) + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
            new_start, new_end = _period_after(following)
    except Exception as e:
        logger.error(f"Auto-create: cannot compute next period for budget {budget_id}: {e}")
        return None

    # Duplicate check BEFORE calling OpenAI: any child of this parent, or a budget of the
    # same name/period/currency starting on the same day, means it was already created.
    day_start = new_start.replace(hour=0, minute=0, second=0, microsecond=0)
    existing = await budgets_collection.find_one({
        "user_id": user_id,
        "$or": [
            {"parent_budget_id": budget_id},
            {
                "name": budget["name"],
                "period": budget["period"],
                "currency": currency,
                "start_date": {"$gte": day_start, "$lt": day_start + timedelta(days=1)},
            },
        ],
    })
    if existing:
        if existing.get("parent_budget_id") == budget_id:
            await _mark_rolled_over(budget_id, existing["_id"])
        return None

    # Claim the parent so concurrent triggers (every recompute of a completed budget calls
    # this) can't both generate (and both pay for an OpenAI call). Stale claims expire.
    now = datetime.now(timezone.utc)
    claim = await budgets_collection.update_one(
        {
            "_id": budget_id,
            "$or": [
                {"auto_create_claimed_at": {"$exists": False}},
                {"auto_create_claimed_at": None},
                {"auto_create_claimed_at": {"$lt": now - timedelta(minutes=10)}},
            ],
        },
        {"$set": {"auto_create_claimed_at": now}},
    )
    if claim.modified_count == 0:
        return None

    try:
        if budget.get("auto_create_with_ai", False):
            category_budgets = await _generate_ai_category_budgets(
                user_id, period, new_start, new_end, parent_budget=budget
            )
        else:
            category_budgets = []
            for cat in budget["category_budgets"]:
                _append_valid_category(category_budgets, cat)

        # Fresh period: reset spend fields copied from the parent.
        category_dicts = []
        for cat in category_budgets:
            d = cat.model_dump()
            d.update({"spent_amount": 0.0, "percentage_used": 0.0, "is_exceeded": False})
            category_dicts.append(d)

        if budget.get("auto_create_with_ai", False):
            # Don't double count "Main" + "Main - Sub" allocations.
            total_budget = calculate_total_budget_excluding_subcategories(category_dicts)
        else:
            # Plain copy keeps the user's own total.
            total_budget = budget.get("total_budget")
            if total_budget is None:
                total_budget = calculate_total_budget_excluding_subcategories(category_dicts)

        new_budget_id = str(uuid.uuid4())
        now = datetime.now(timezone.utc)
        window = {"start_date": new_start, "end_date": new_end}
        is_active = is_budget_active(window, now)
        status_value = (
            BudgetStatus.ACTIVE if is_active
            else (BudgetStatus.UPCOMING if app_wall_clock_now(now) < _aware(new_start) else BudgetStatus.COMPLETED)
        ).value

        new_budget = {
            "_id": new_budget_id,
            "user_id": user_id,
            "name": budget['name'],
            "period": budget["period"],
            "start_date": new_start,
            "end_date": new_end,
            "category_budgets": category_dicts,
            "total_budget": total_budget,
            "total_spent": 0.0,
            "remaining_budget": total_budget,
            "percentage_used": 0.0,
            "status": status_value,
            "description": budget.get("description"),
            "is_active": is_active,
            "auto_create_enabled": budget.get("auto_create_enabled", False),
            "auto_create_with_ai": budget.get("auto_create_with_ai", False),
            "parent_budget_id": budget["_id"],
            "currency": currency,
            # An auto-created budget that is already running is announced by the
            # "auto created" notification; an upcoming one gets "now active" later.
            "started_notified": is_active,
            "created_at": now,
            "updated_at": now
        }

        await budgets_collection.insert_one(new_budget)
        # The parent is done: the nightly rollover job skips it from now on.
        await _mark_rolled_over(budget_id, new_budget_id)

        # Compute spend for the new period (transactions may already exist in it).
        await update_budget_spent_amounts(user_id, new_budget_id)

        await notify_budget_auto_created(
            user_id=user_id,
            budget_id=new_budget_id,
            budget_name=budget["name"],
            was_ai=budget.get("auto_create_with_ai", False)
        )

        return new_budget_id

    except DuplicateKeyError:
        return None
    except Exception as e:
        print(f"❌ Error auto-creating budget: {str(e)}")
        # Release the claim so a later trigger can retry.
        try:
            await budgets_collection.update_one(
                {"_id": budget_id}, {"$unset": {"auto_create_claimed_at": ""}}
            )
        except Exception:
            pass
        return None



async def _generate_ai_category_budgets(
    user_id: str,
    period: BudgetPeriod,
    start_date: datetime,
    end_date: datetime,
    parent_budget: Dict
) -> List[CategoryBudget]:
    """Generate AI-based category budgets"""

    analyzer = BudgetAnalyzer(user_id)
    days_in_period = (end_date - start_date).days + 1

    # [FIX] Added await
    outflow_categories_doc = await get_categories_doc("outflow")
    categories_structure = []

    if outflow_categories_doc:
        for cat in outflow_categories_doc["categories"]:
            categories_structure.append({
                "main_category": cat["main_category"],
                "sub_categories": cat["sub_categories"]
            })

    # Create detailed categories structure
    categories_info = []
    for cat_struct in categories_structure:
        sub_cats = ", ".join(cat_struct["sub_categories"])
        categories_info.append(f"- {cat_struct['main_category']}: [{sub_cats}]")

    categories_list = "\n".join(categories_info)

    # Analyze spending from the completed budget period
    parent_start = parent_budget["start_date"]
    parent_end = parent_budget["end_date"]

    # [FIX] Async find
    cursor = transactions_collection.find({
        "user_id": user_id,
        "type": "outflow",
        "currency": parent_budget.get("currency", "usd"),
        "date": {"$gte": parent_start, "$lte": parent_end},
        **finite_amount_filter(),
    })
    transactions = await cursor.to_list(length=None)

    if not transactions:
        # No data, use parent budget allocations (no AI call)
        fallback: List[CategoryBudget] = []
        for cat in parent_budget["category_budgets"]:
            _append_valid_category(fallback, cat)
        return fallback

    # Calculate actual spending per category from parent budget
    category_spending = {}
    for cat_budget in parent_budget["category_budgets"]:
        category_spending[cat_budget["main_category"]] = cat_budget.get("spent_amount", 0)

    if settings.OPENAI_API_KEY:
        try:
            from openai import AsyncOpenAI
            client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)

            # [Context and Prompt building logic remains identical]
            context = {
                "period_type": period.value,
                "days_in_period": days_in_period,
                "parent_budget_categories": parent_budget["category_budgets"],
                "actual_spending": category_spending,
                "total_allocated": parent_budget["total_budget"],
                "total_spent": parent_budget["total_spent"],
                "utilization_rate": parent_budget["percentage_used"]
            }

            system_prompt = f"""You are a financial budgeting expert. Analyze the previous budget performance and suggest improved budgets for the next period.

PREVIOUS BUDGET PERFORMANCE:
- Period: {period.value} ({days_in_period} days)
- Total Allocated: ${parent_budget['total_budget']:.2f}
- Total Spent: ${parent_budget['total_spent']:.2f}
- Utilization: {parent_budget['percentage_used']:.1f}%

AVAILABLE CATEGORIES WITH SUB-CATEGORIES:
{categories_list}

CRITICAL RULES:
1. You MUST ONLY use categories and sub-categories from the "AVAILABLE CATEGORIES" list above
2. DO NOT create or suggest any new category or sub-category names
3. You can budget for both main categories and specific sub-categories
4. If you suggest budget for both main category AND its sub-categories, the budget for main category must be greater than its sub-categories combined
5. Format for main category: "Main Category Name"
6. Format for sub-category: "Main Category Name - Sub Category Name"
7. Adjust budgets based on actual spending patterns:
   - If under-utilized (<80%), consider reducing allocation
   - If over-utilized (>100%), increase allocation
   - If well-utilized (80-100%), keep similar allocation
8. Consider seasonal variations
9. If parent budget used sub-categories effectively, maintain that structure
10. Total budget should be reasonable based on past performance

Return JSON format:
{{
    "categories": [
        {{
            "main_category": "category name or category name - sub category name",
            "allocated_amount": 500.00,
            "spent_amount": 0,
            "percentage_used": 0,
            "is_exceeded": false
        }}
    ],
    "reasoning": "Brief explanation of adjustments made"
}}"""

            user_prompt = f"""Based on this budget performance data, suggest optimized budgets for the next {period.value} period:

{json.dumps(context, indent=2)}

Provide realistic budget suggestions that learn from past spending patterns.

REMEMBER: Only use categories/sub-categories from the AVAILABLE CATEGORIES list provided."""

            response = await client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt}
                ],
                response_format={"type": "json_object"},
                temperature=0.3
            )

            # NEW: Track AI usage for auto-create
            if hasattr(response, 'usage'):
                from ai_usage_service import track_ai_usage
                from ai_usage_models import AIFeatureType, AIProviderType
                import logging

                logger = logging.getLogger(__name__)

                input_tokens = response.usage.prompt_tokens
                output_tokens = response.usage.completion_tokens
                total_tokens = response.usage.total_tokens

                logger.info(f"💰 [OPENAI TOKEN USAGE - Auto Budget Creation] User: {user_id}")
                logger.info(f"   📥 Input tokens: {input_tokens:,}")
                logger.info(f"   📤 Output tokens: {output_tokens:,}")
                logger.info(f"   📊 Total tokens: {total_tokens:,}")
                logger.info(f"   🤖 Model: gpt-4o-mini")

                await track_ai_usage(
                    user_id=user_id,
                    feature_type=AIFeatureType.BUDGET_AUTO_CREATE,
                    provider=AIProviderType.OPENAI,
                    model_name="gpt-4o-mini",
                    input_tokens=input_tokens,
                    output_tokens=output_tokens,
                    total_tokens=total_tokens
                )

            result = json.loads(response.choices[0].message.content)

            # [Validation logic remains identical]
            valid_categories = []
            available_main_categories = [cat["main_category"] for cat in categories_structure]

            for cat in result.get("categories") or []:
                if not isinstance(cat, dict) or not isinstance(cat.get("main_category"), str):
                    continue
                category_name = cat["main_category"]
                if " - " in category_name:
                    parts = category_name.split(" - ", 1)
                    main_cat, sub_cat = parts[0], parts[1]
                    if main_cat not in available_main_categories: continue
                    category_struct = next((c for c in categories_structure if c["main_category"] == main_cat), None)
                    if category_struct and sub_cat in category_struct["sub_categories"]:
                        _append_valid_category(valid_categories, cat)
                else:
                    if category_name in available_main_categories:
                        _append_valid_category(valid_categories, cat)
                    else:
                        for available_cat in available_main_categories:
                            if available_cat.lower() == category_name.lower():
                                cat["main_category"] = available_cat
                                _append_valid_category(valid_categories, cat)
                                break

            return valid_categories if valid_categories else _generate_adjusted_budgets(parent_budget, days_in_period)

        except Exception as e:
            print(f"Error generating AI budgets: {e}")
            return _generate_adjusted_budgets(parent_budget, days_in_period)
    else:
        return _generate_adjusted_budgets(parent_budget, days_in_period)


def _generate_adjusted_budgets(parent_budget: Dict, days_in_period: int) -> List[CategoryBudget]:
    """Generate adjusted budgets based on spending without AI"""
    adjusted_budgets = []

    for cat_budget in parent_budget["category_budgets"]:
        allocated = cat_budget["allocated_amount"]
        spent = cat_budget.get("spent_amount", 0)
        utilization = (spent / allocated * 100) if allocated > 0 else 0

        # Adjust based on utilization
        if utilization < 50:
            # Significant under-utilization - reduce by 20%
            new_amount = allocated * 0.8
        elif utilization < 80:
            # Slight under-utilization - reduce by 10%
            new_amount = allocated * 0.9
        elif utilization > 120:
            # Significant over-spending - increase by 20%
            new_amount = allocated * 1.2
        elif utilization > 100:
            # Slight over-spending - increase by 10%
            new_amount = allocated * 1.1
        else:
            # Good utilization (80-100%) - keep same
            new_amount = allocated

        adjusted_budgets.append(CategoryBudget(
            main_category=cat_budget["main_category"],
            allocated_amount=round(new_amount, 2),
            spent_amount=0,
            percentage_used=0,
            is_exceeded=False
        ))

    return adjusted_budgets


async def update_all_user_budgets(user_id: str):
    """Update all budgets for a user (called after transaction changes)"""
    # [FIX] Async find
    cursor = budgets_collection.find({"user_id": user_id})
    budgets = await cursor.to_list(length=None)

    for budget in budgets:
        # [FIX] Added await
        await update_budget_spent_amounts(user_id, budget["_id"], budget_doc=budget)