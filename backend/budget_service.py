import json
from datetime import datetime, timedelta, timezone
from typing import List, Dict, Optional
from collections import defaultdict
import statistics

from database import transactions_collection, budgets_collection, goals_collection
from budget_models import (
    BudgetPeriod, CategoryBudget, AIBudgetSuggestion, BudgetStatus
)
from config import settings


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
            "total_expenses": sum(data["total"] for data in category_stats.values())
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
            # Start of week (Monday)
            days_since_monday = start_date.weekday()
            week_start = start_date - timedelta(days=days_since_monday)
            week_start = week_start.replace(hour=0, minute=0, second=0, microsecond=0)
            week_end = week_start + timedelta(days=6, hours=23, minutes=59, seconds=59)
            return week_start, week_end
        
        elif period == BudgetPeriod.MONTHLY:
            # Start of month
            month_start = start_date.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
            # End of month
            if start_date.month == 12:
                month_end = start_date.replace(month=12, day=31, hour=23, minute=59, second=59)
            else:
                next_month = start_date.replace(month=start_date.month + 1, day=1)
                month_end = (next_month - timedelta(days=1)).replace(hour=23, minute=59, second=59)
            return month_start, month_end
        
        elif period == BudgetPeriod.YEARLY:
            # Start of year
            year_start = start_date.replace(month=1, day=1, hour=0, minute=0, second=0, microsecond=0)
            year_end = start_date.replace(month=12, day=31, hour=23, minute=59, second=59)
            return year_start, year_end
    
    async def generate_ai_suggestions(
        self,
        period: BudgetPeriod,
        start_date: datetime,
        end_date: Optional[datetime] = None,
        analysis_months: int = 3,
        include_categories: Optional[List[str]] = None
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
                analysis, period, days_in_period, include_categories
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
        include_categories: Optional[List[str]]
    ) -> Dict:
        """Use OpenAI to generate intelligent budget suggestions"""
        from openai import AsyncOpenAI
        
        client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
        
        # Prepare analysis context
        context = {
            "period_type": period.value,
            "days_in_period": days_in_period,
            "spending_analysis": analysis.get("categories", {}),
            "monthly_income": analysis.get("income", {}).get("monthly_average", 0),
            "monthly_expenses": analysis.get("total_expenses", 0) / analysis.get("analysis_period_months", 1),
            "active_goals": analysis.get("goals", {})
        }
        
        system_prompt = """You are a financial budgeting expert. Analyze the user's spending patterns and suggest realistic budgets.

RULES:
1. Suggest budgets based on historical spending patterns
2. Consider income vs expenses ratio
3. Account for active financial goals
4. Add 10-15% buffer for categories with high variability
5. Prioritize essential categories (housing, utilities, food, transportation)
6. Suggest reasonable reductions for non-essential categories if overspending
7. Ensure total budget doesn't exceed 80% of income (leave room for savings and goals)

Return JSON format:
{
    "categories": [
        {
            "main_category": "category name",
            "allocated_amount": 500.00,
            "spent_amount": 0,
            "percentage_used": 0,
            "is_exceeded": false
        }
    ],
    "reasoning": "Detailed explanation of budget suggestions"
}"""

        user_prompt = f"""Based on this financial data, suggest a {period.value} budget:

SPENDING ANALYSIS:
{json.dumps(context, indent=2)}

{f"Focus on these categories: {', '.join(include_categories)}" if include_categories else "Suggest budgets for all spending categories."}

Calculate budgets for {days_in_period} days period."""

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
        
        # Convert to CategoryBudget objects
        result["categories"] = [
            CategoryBudget(**cat) for cat in result["categories"]
        ]
        
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
    
    return start_date <= current_date <= end_date


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
    
    # Track counted transactions to avoid double counting in total_spent
    counted_transaction_ids = set()
    
    # Update budget categories
    for cat_budget in budget["category_budgets"]:
        budget_category = cat_budget["main_category"]
        spent = 0
        
        # Check if this is a main category or main + sub category budget
        if " - " in budget_category:
            # This is a specific sub-category budget (e.g., "Shopping - Clothing")
            parts = budget_category.split(" - ", 1)
            main_cat = parts[0]
            sub_cat = parts[1]
            
            # Sum transactions that match both main and sub category
            for t in transactions:
                if t["main_category"] == main_cat and t["sub_category"] == sub_cat:
                    spent += t["amount"]
                    # Mark transaction as counted for total_spent calculation
                    counted_transaction_ids.add(t["_id"])
        else:
            # This is a main category budget (e.g., "Shopping")
            # Sum all transactions with this main category, regardless of sub-category
            for t in transactions:
                if t["main_category"] == budget_category:
                    spent += t["amount"]
                    # Mark transaction as counted for total_spent calculation
                    counted_transaction_ids.add(t["_id"])
        
        allocated = cat_budget["allocated_amount"]
        
        cat_budget["spent_amount"] = spent
        cat_budget["percentage_used"] = (spent / allocated * 100) if allocated > 0 else 0
        cat_budget["is_exceeded"] = spent > allocated
    
    # Calculate total_spent by summing only unique transactions (no double counting)
    total_spent = sum(t["amount"] for t in transactions if t["_id"] in counted_transaction_ids)
    
    # Update budget totals
    remaining = budget["total_budget"] - total_spent
    percentage_used = (total_spent / budget["total_budget"] * 100) if budget["total_budget"] > 0 else 0
    
    # Update status
    status = calculate_budget_status(budget, datetime.now(timezone.utc))
    is_active = is_budget_active(budget, datetime.now(timezone.utc))
    
    budgets_collection.update_one(
        {"_id": budget_id},
        {
            "$set": {
                "category_budgets": budget["category_budgets"],
                "total_spent": total_spent,
                "remaining_budget": remaining,
                "percentage_used": percentage_used,
                "status": status.value,
                "is_active": is_active,
                "updated_at": datetime.now(timezone.utc)
            }
        }
    )


def update_all_user_budgets(user_id: str):
    """Update all budgets for a user (called after transaction changes)"""
    budgets = list(budgets_collection.find({"user_id": user_id}))
    for budget in budgets:
        update_budget_spent_amounts(user_id, budget["_id"])