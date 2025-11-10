import asyncio
import json
from datetime import datetime, timedelta, timezone
from typing import List, Dict, Optional
from collections import defaultdict
import statistics
import uuid

from database import transactions_collection, budgets_collection, goals_collection, categories_collection
from budget_models import (
    BudgetPeriod, CategoryBudget, AIBudgetSuggestion, BudgetStatus
)
from config import settings

_auto_create_locks = {}


class BudgetAnalyzer:
    """Analyzes user's financial data for AI budget suggestions"""
    
    def __init__(self, user_id: str):
        self.user_id = user_id
    
    def analyze_spending_patterns(self, months: int = 3) -> Dict:
        """Analyze user's spending patterns over the last N months"""
        cutoff_date = datetime.now(timezone.utc) - timedelta(days=months * 30)
        
        transactions = list(transactions_collection.find({
            "user_id": self.user_id,
            "date": {"$gte": cutoff_date},
            "type": "outflow"
        }))
        
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
        
        # Analyze income
        income_transactions = list(transactions_collection.find({
            "user_id": self.user_id,
            "date": {"$gte": cutoff_date},
            "type": "inflow"
        }))
        
        total_income = sum(t["amount"] for t in income_transactions)
        monthly_income = total_income / months if income_transactions else 0
        
        # Check goals
        goals = list(goals_collection.find({
            "user_id": self.user_id,
            "status": "active"
        }))
        
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
        user_context: Optional[str] = None  # NEW
    ) -> AIBudgetSuggestion:
        """Generate AI budget suggestions"""
        
        # Analyze spending patterns
        analysis = self.analyze_spending_patterns(analysis_months)
        
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
                analysis, period, days_in_period, include_categories, user_context  # NEW parameter
            )
        else:
            suggestions = self._generate_basic_suggestions(
                analysis, days_in_period, include_categories
            )
        
        # Calculate totals
        total_budget = sum(cat.allocated_amount for cat in suggestions["categories"])
        
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
        user_context: Optional[str] = None
    ) -> Dict:
        """Use OpenAI to generate intelligent budget suggestions - ONLY uses predefined categories"""
        """Use OpenAI to generate intelligent budget suggestions"""
        from openai import AsyncOpenAI
        
        client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
        
        # NEW: Fetch available categories from database
        outflow_categories_doc = categories_collection.find_one({"_id": "outflow"})
        available_categories = []
        
        if outflow_categories_doc:
            for cat in outflow_categories_doc["categories"]:
                available_categories.append(cat["main_category"])
        
        # Create categories list string for the prompt
        categories_list = "\n".join([f"- {cat}" for cat in available_categories])
        
        # Prepare analysis context
        context = {
            "period_type": period.value,
            "days_in_period": days_in_period,
            "spending_analysis": analysis.get("categories", {}),
            "monthly_income": analysis.get("income", {}).get("monthly_average", 0),
            "monthly_expenses": analysis.get("total_expenses", 0) / analysis.get("analysis_period_months", 1),
            "active_goals": analysis.get("goals", {})
        }
        
        # NEW: Add user context if provided
        context_instruction = ""
        if user_context:
            context_instruction = f"\n\nUSER CONTEXT: {user_context}\nIMPORTANT: Adjust budget allocations based on this context. For example, if the user mentions travel, increase transportation and entertainment budgets accordingly."
        
        system_prompt = f"""You are a financial budgeting expert. Analyze the user's spending patterns and suggest realistic budgets.

    IMPORTANT: The budget period spans {days_in_period} days.

    AVAILABLE CATEGORIES (YOU MUST ONLY USE THESE):
    {categories_list}

    CRITICAL RULES:
    1. You MUST ONLY use categories from the "AVAILABLE CATEGORIES" list above
    2. DO NOT create or suggest any new category names
    3. If you see spending in a category not in the list, map it to the closest available category
    4. Suggest budgets based on historical spending patterns, scaled to the {days_in_period}-day period
    5. Consider income vs expenses ratio
    6. Account for active financial goals
    7. Add 10-15% buffer for categories with high variability
    8. Prioritize essential categories (Housing, Bills & Utilities, Food & Dining, Transportation)
    9. Suggest reasonable reductions for non-essential categories if overspending
    10. Ensure total budget doesn't exceed 80% of income (leave room for savings and goals)
    {context_instruction}

    Return JSON format:
    {{
        "categories": [
            {{
                "main_category": "category name from available list",
                "allocated_amount": 500.00,
                "spent_amount": 0,
                "percentage_used": 0,
                "is_exceeded": false
            }}
        ],
        "reasoning": "Detailed explanation of budget suggestions"
    }}"""

        user_prompt = f"""Based on this financial data, suggest a {period.value} budget:

    SPENDING ANALYSIS:
    {json.dumps(context, indent=2)}

    {f"Focus on these categories: {', '.join(include_categories)}" if include_categories else "Suggest budgets for relevant spending categories from the available list."}

    Calculate budgets for {days_in_period} days period.

    REMEMBER: Only use categories from the AVAILABLE CATEGORIES list provided."""

        response = await client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            response_format={"type": "json_object"},
            temperature=0.3
        )
        
        result = json.loads(response.choices[0].message.content)
        
        # NEW: Validate that all categories exist in the system
        valid_categories = []
        for cat in result["categories"]:
            category_name = cat["main_category"]
            
            # Check if category exists in available categories
            if category_name in available_categories:
                valid_categories.append(CategoryBudget(**cat))
            else:
                # Try to find closest match (case-insensitive)
                matched = False
                for available_cat in available_categories:
                    if available_cat.lower() == category_name.lower():
                        cat["main_category"] = available_cat  # Use correct casing
                        valid_categories.append(CategoryBudget(**cat))
                        matched = True
                        break
                
                if not matched:
                    print(f"Warning: AI suggested invalid category '{category_name}', skipping...")
        
        # Update result with validated categories
        result["categories"] = valid_categories
        
        # Add warning if some categories were skipped
        if len(valid_categories) < len(result.get("categories", [])):
            result["reasoning"] += "\n\nNote: Some suggested categories were not available in your system and were excluded."
        
        return result
    
    def _generate_basic_suggestions(
        self,
        analysis: Dict,
        days_in_period: int,
        include_categories: Optional[List[str]]
    ) -> Dict:
        """Generate basic budget suggestions without AI"""
        categories = []
        reasoning_parts = []
        
        if not analysis.get("sufficient_data"):
            # Very limited data - use conservative defaults
            default_budgets = {
                "Food & Dining": 400,
                "Transportation": 200,
                "Shopping": 150,
                "Entertainment": 100,
                "Bills & Utilities": 300,
                "Healthcare": 100,
                "Personal Care": 80
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
                    f"{cat}: ${period_budget:.2f} (based on ${monthly_avg:.2f}/month average, {stats['variability']} variability)"
                )
        
        reasoning = "Budget suggestions:\n" + "\n".join(reasoning_parts)
        
        return {
            "categories": categories,
            "reasoning": reasoning
        }


def calculate_budget_status(budget: Dict, current_date: datetime) -> BudgetStatus:
    """Calculate the current status of a budget"""
    if current_date.tzinfo is None:
        current_date = current_date.replace(tzinfo=timezone.utc)
    
    start_date = budget["start_date"]
    end_date = budget["end_date"]
    
    if start_date.tzinfo is None:
        start_date = start_date.replace(tzinfo=timezone.utc)
    if end_date.tzinfo is None:
        end_date = end_date.replace(tzinfo=timezone.utc)
    
    # Check if budget hasn't started yet
    if current_date < start_date:
        return BudgetStatus.UPCOMING
    
    # Check if budget period has ended
    if current_date > end_date:
        return BudgetStatus.COMPLETED
    
    # Check if any category is exceeded
    total_budget = budget["total_budget"]
    total_spent = budget["total_spent"]
    
    if total_spent > total_budget:
        return BudgetStatus.EXCEEDED
    
    # Check individual categories
    for cat_budget in budget["category_budgets"]:
        if cat_budget.get("is_exceeded", False):
            return BudgetStatus.EXCEEDED
    
    return BudgetStatus.ACTIVE


def is_budget_active(budget: Dict, current_date: datetime) -> bool:
    """Check if a budget is currently active (within its date range)"""
    if current_date.tzinfo is None:
        current_date = current_date.replace(tzinfo=timezone.utc)
    
    start_date = budget["start_date"]
    end_date = budget["end_date"]
    
    if start_date.tzinfo is None:
        start_date = start_date.replace(tzinfo=timezone.utc)
    if end_date.tzinfo is None:
        end_date = end_date.replace(tzinfo=timezone.utc)
    
    # Budget is active if current date is within the range (inclusive)
    is_active = start_date <= current_date <= end_date
    
    print(f"DEBUG is_budget_active: start={start_date}, current={current_date}, end={end_date}, active={is_active}")
    
    return is_active


def update_budget_spent_amounts(user_id: str, budget_id: str):
    """Recalculate spent amounts for a budget based on transactions"""
    budget = budgets_collection.find_one({"_id": budget_id, "user_id": user_id})
    if not budget:
        return
    
    # Get all transactions in budget period
    transactions = list(transactions_collection.find({
        "user_id": user_id,
        "type": "outflow",
        "date": {
            "$gte": budget["start_date"],
            "$lte": budget["end_date"]
        }
    }))
    
    # Track which transactions have been counted for total_spent
    counted_transaction_ids = set()
    
    # First pass: Calculate spent amounts for each category budget
    category_spent = {}
    for cat_budget in budget["category_budgets"]:
        budget_category = cat_budget["main_category"]
        spent = 0
        
        if " - " in budget_category:
            # This is a specific sub-category budget (e.g., "Shopping - Clothing")
            parts = budget_category.split(" - ", 1)
            main_cat = parts[0]
            sub_cat = parts[1]
            
            # Sum transactions that match both main and sub category
            for t in transactions:
                if t["main_category"] == main_cat and t["sub_category"] == sub_cat:
                    spent += t["amount"]
                    counted_transaction_ids.add(t["_id"])
        else:
            # This is a main category budget (e.g., "Shopping")
            # Sum all transactions with this main category
            for t in transactions:
                if t["main_category"] == budget_category:
                    spent += t["amount"]
                    counted_transaction_ids.add(t["_id"])
        
        category_spent[budget_category] = spent
    
    # Update category budgets with calculated amounts
    for cat_budget in budget["category_budgets"]:
        budget_category = cat_budget["main_category"]
        spent = category_spent.get(budget_category, 0)
        allocated = cat_budget["allocated_amount"]
        
        cat_budget["spent_amount"] = spent
        cat_budget["percentage_used"] = (spent / allocated * 100) if allocated > 0 else 0
        cat_budget["is_exceeded"] = spent > allocated
    
    # Calculate total_spent by summing only unique transactions
    total_spent = sum(t["amount"] for t in transactions if t["_id"] in counted_transaction_ids)
    
    # Calculate total_budget excluding hierarchical sub-categories
    total_budget = calculate_total_budget_excluding_subcategories(budget["category_budgets"])
    
    # Update budget totals
    remaining = total_budget - total_spent
    percentage_used = (total_spent / total_budget * 100) if total_budget > 0 else 0
    
    # Update status
    status = calculate_budget_status(budget, datetime.now(timezone.utc))
    is_active = is_budget_active(budget, datetime.now(timezone.utc))
    
    budgets_collection.update_one(
        {"_id": budget_id},
        {
            "$set": {
                "category_budgets": budget["category_budgets"],
                "total_budget": total_budget,
                "total_spent": total_spent,
                "remaining_budget": remaining,
                "percentage_used": percentage_used,
                "status": status.value,
                "is_active": is_active,
                "updated_at": datetime.now(timezone.utc)
            }
        }
    )
    
    # Check if budget just completed and should auto-create next
    if status == BudgetStatus.COMPLETED and budget.get("auto_create_enabled"):
        # Check if the previous status was NOT completed to avoid repeated triggers
        previous_status = budget.get("status")
        if previous_status != BudgetStatus.COMPLETED.value:
            print(f"Budget {budget_id} just completed, triggering auto-create...")
            # Get the updated budget document to pass to auto_create
            updated_budget = budgets_collection.find_one({"_id": budget_id})
            # Run auto-create asynchronously
            try:
                loop = asyncio.get_event_loop()
                if loop.is_running():
                    loop.create_task(auto_create_next_budget(updated_budget))
                else:
                    asyncio.run(auto_create_next_budget(updated_budget))
            except Exception as e:
                print(f"Error triggering auto-create: {e}")


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
    """
    Automatically create next budget based on completed budget
    Returns new budget ID if successful
    """
    budget_id = budget["_id"]
    
    # NEW: Check if this budget is already being processed
    if _auto_create_locks.get(budget_id, False):
        print(f"Auto-create already in progress for budget {budget_id}")
        return None
    
    if not budget.get("auto_create_enabled", False):
        return None
    
    # Only auto-create for completed budgets
    if budget["status"] != BudgetStatus.COMPLETED.value:
        return None
    
    # Check if next budget already exists
    end_date = budget["end_date"]
    next_start_date = end_date + timedelta(days=1)
    
    # Check if a budget already exists starting on this date with this parent
    existing = budgets_collection.find_one({
        "user_id": budget["user_id"],
        "parent_budget_id": budget_id,
        "start_date": next_start_date
    })
    
    if existing:
        print(f"Next budget already exists for budget {budget_id}: {existing['_id']}")
        return None
    
    # NEW: Set lock before processing
    _auto_create_locks[budget_id] = True
    
    try:
        # Calculate new dates based on period
        analyzer = BudgetAnalyzer(budget["user_id"])
        period = BudgetPeriod(budget["period"])
        new_start, new_end = analyzer.calculate_period_dates(
            period,
            next_start_date,
            None
        )
        
        # Generate category budgets
        if budget.get("auto_create_with_ai", False):
            print(f"Generating AI-based budget for next period...")
            category_budgets = await _generate_ai_category_budgets(
                budget["user_id"],
                period,
                new_start,
                new_end,
                parent_budget=budget
            )
        else:
            # Use same category budgets as parent
            category_budgets = [
                CategoryBudget(**cat) for cat in budget["category_budgets"]
            ]
        
        # Create new budget
        new_budget_id = str(uuid.uuid4())
        now = datetime.now(timezone.utc)
        
        total_budget = sum(cat.allocated_amount for cat in category_budgets)
        
        new_budget = {
            "_id": new_budget_id,
            "user_id": budget["user_id"],
            "name": budget['name'],  # Keep same name, remove "(Auto-created)"
            "period": budget["period"],
            "start_date": new_start,
            "end_date": new_end,
            "category_budgets": [cat.dict() for cat in category_budgets],
            "total_budget": total_budget,
            "total_spent": 0.0,
            "remaining_budget": total_budget,
            "percentage_used": 0.0,
            "status": BudgetStatus.UPCOMING.value,
            "description": budget.get("description"),
            "is_active": False,
            "auto_create_enabled": budget.get("auto_create_enabled", False),  # Carry forward
            "auto_create_with_ai": budget.get("auto_create_with_ai", False),  # Carry forward
            "parent_budget_id": budget["_id"],
            "created_at": now,
            "updated_at": now
        }
        
        budgets_collection.insert_one(new_budget)
        print(f"✅ Auto-created new budget: {new_budget_id} (from {budget_id})")
        
        return new_budget_id
        
    except Exception as e:
        print(f"❌ Error auto-creating budget: {str(e)}")
        import traceback
        traceback.print_exc()
        return None
    finally:
        # Always release lock
        _auto_create_locks.pop(budget_id, None)


async def _generate_ai_category_budgets(
    user_id: str,
    period: BudgetPeriod,
    start_date: datetime,
    end_date: datetime,
    parent_budget: Dict
) -> List[CategoryBudget]:
    """Generate AI-based category budgets using parent budget and recent data"""
    
    analyzer = BudgetAnalyzer(user_id)
    days_in_period = (end_date - start_date).days + 1
    
    # NEW: Fetch available categories from database
    outflow_categories_doc = categories_collection.find_one({"_id": "outflow"})
    available_categories = []
    
    if outflow_categories_doc:
        for cat in outflow_categories_doc["categories"]:
            available_categories.append(cat["main_category"])
    
    categories_list = "\n".join([f"- {cat}" for cat in available_categories])
    
    # Analyze spending from the completed budget period
    parent_start = parent_budget["start_date"]
    parent_end = parent_budget["end_date"]
    
    transactions = list(transactions_collection.find({
        "user_id": user_id,
        "type": "outflow",
        "date": {
            "$gte": parent_start,
            "$lte": parent_end
        }
    }))
    
    if not transactions:
        # No data, use parent budget allocations
        return [CategoryBudget(**cat) for cat in parent_budget["category_budgets"]]
    
    # Calculate actual spending per category from parent budget
    category_spending = {}
    for cat_budget in parent_budget["category_budgets"]:
        category_name = cat_budget["main_category"]
        category_spending[category_name] = cat_budget.get("spent_amount", 0)
    
    if settings.OPENAI_API_KEY:
        try:
            from openai import AsyncOpenAI
            client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
            
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

AVAILABLE CATEGORIES (YOU MUST ONLY USE THESE):
{categories_list}

CRITICAL RULES:
1. You MUST ONLY use categories from the "AVAILABLE CATEGORIES" list above
2. DO NOT create or suggest any new category names
3. Adjust budgets based on actual spending patterns
4. If a category was under-utilized (<80%), reduce allocation
5. If a category was over-utilized (>100%), increase allocation
6. If spending was 80-100%, keep similar allocation
7. Consider seasonal variations
8. Total budget should be reasonable based on past performance

Return JSON format:
{{
    "categories": [
        {{
            "main_category": "category name from available list",
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

REMEMBER: Only use categories from the AVAILABLE CATEGORIES list provided."""

            response = await client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt}
                ],
                response_format={"type": "json_object"},
                temperature=0.3
            )
            
            result = json.loads(response.choices[0].message.content)
            
            # NEW: Validate that all categories exist in the system
            valid_categories = []
            for cat in result["categories"]:
                category_name = cat["main_category"]
                
                # Check if category exists in available categories
                if category_name in available_categories:
                    valid_categories.append(CategoryBudget(**cat))
                else:
                    # Try to find closest match (case-insensitive)
                    matched = False
                    for available_cat in available_categories:
                        if available_cat.lower() == category_name.lower():
                            cat["main_category"] = available_cat
                            valid_categories.append(CategoryBudget(**cat))
                            matched = True
                            break
                    
                    if not matched:
                        print(f"Warning: AI suggested invalid category '{category_name}', skipping...")
            
            return valid_categories if valid_categories else _generate_adjusted_budgets(parent_budget, days_in_period)
            
        except Exception as e:
            print(f"Error generating AI budgets: {e}")
            # Fallback to adjusted budgets based on spending
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


def update_all_user_budgets(user_id: str):
    """Update all budgets for a user (called after transaction changes)"""
    budgets = list(budgets_collection.find({"user_id": user_id}))
    for budget in budgets:
        update_budget_spent_amounts(user_id, budget["_id"])