import asyncio
import os
import json
from typing import List, Dict, Any, Optional
from datetime import datetime, timedelta, timezone

from langchain_openai import OpenAIEmbeddings
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_community.vectorstores import Chroma
from langchain_core.documents import Document

from budget_service import update_budget_spent_amounts
from database import transactions_collection, users_collection, goals_collection, budgets_collection
from dotenv import load_dotenv

load_dotenv()


def ensure_utc_datetime(dt) -> datetime:
    """Ensure datetime is timezone-aware UTC"""
    if dt is None:
        return None
    
    if isinstance(dt, str):
        dt = datetime.fromisoformat(dt.replace("Z", "+00:00"))
    
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    elif dt.tzinfo != timezone.utc:
        dt = dt.astimezone(timezone.utc)
    
    return dt


def get_date_only(dt: datetime) -> str:
    """Extract date string in YYYY-MM-DD format"""
    return ensure_utc_datetime(dt).strftime("%Y-%m-%d")


class FinancialDataProcessor:
    """Processes user's financial data for RAG"""
    
    def __init__(self, user_id: str):
        self.user_id = user_id
        
        
    def ensure_utc_datetime(self, dt) -> datetime:
        """Ensure datetime is timezone-aware UTC (instance method wrapper)"""
        return ensure_utc_datetime(dt)
        
    def get_user_transactions(self, days_back: int = 90, limit: int = 500) -> List[Dict]:
        """
        Get recent user transactions.
        Defaults to last 90 days or max 500 items to prevent OOM.
        """
        query = {"user_id": self.user_id}
        
        # 1. Apply Date Filter (Default 90 days)
        if days_back:
            cutoff_date = datetime.now(timezone.utc) - timedelta(days=days_back)
            query["date"] = {"$gte": cutoff_date}
        
        try:
            # 2. Apply Hard Limit (Default 500 docs) to prevent memory explosion
            transactions = list(
                transactions_collection.find(query)
                .sort("date", -1)
                .limit(limit)
            )
            print(f"Found {len(transactions)} transactions for user {self.user_id} (Limit: {limit}, Days: {days_back})")
            return transactions
        except Exception as e:
            print(f"Error fetching transactions: {e}")
            return []
    
    def get_user_goals(self) -> List[Dict]:
        """Get user's financial goals"""
        try:
            goals = list(goals_collection.find({"user_id": self.user_id}).sort("created_at", -1))
            print(f"Found {len(goals)} goals for user {self.user_id}")
            return goals
        except Exception as e:
            print(f"Error fetching goals: {e}")
            return []
        
    def get_user_budgets(self) -> List[Dict]:
        """Get user's active budgets"""
        try:         
            # Get active budgets
            budgets = list(budgets_collection.find({
                "user_id": self.user_id,
                "is_active": True,
                "status": "active"
            }).sort("created_at", -1))
            
            # Update spent amounts for each budget
            for budget in budgets:
                try:
                    update_budget_spent_amounts(self.user_id, budget["_id"])
                except Exception as e:
                    print(f"Error updating budget {budget['_id']}: {e}")
            
            # Refresh budget data after updates
            budgets = list(budgets_collection.find({
                "user_id": self.user_id,
                "is_active": True,
                "status": "active"
            }).sort("created_at", -1))
            
            print(f"Found {len(budgets)} active budgets for user {self.user_id}")
            return budgets
        except Exception as e:
            print(f"Error fetching budgets: {e}")
            return []
    
    def get_financial_summary(self) -> Dict[str, Any]:
        """
        Generate comprehensive financial summary using optimized MongoDB Aggregation.
        Replaces Python-side processing to prevent OOM errors on large datasets.
        """
        try:
            pipeline = [
                {"$match": {"user_id": self.user_id}},
                {"$facet": {
                    # 1. General stats per currency
                    "currency_stats": [
                        {"$group": {
                            "_id": "$currency",
                            "total_inflow": {"$sum": {"$cond": [{"$eq": ["$type", "inflow"]}, "$amount", 0]}},
                            "total_outflow": {"$sum": {"$cond": [{"$eq": ["$type", "outflow"]}, "$amount", 0]}},
                            "count": {"$sum": 1},
                            "total_amount_sum": {"$sum": "$amount"},
                            "min_date": {"$min": "$date"},
                            "max_date": {"$max": "$date"}
                        }}
                    ],
                    # 2. Category breakdowns per currency and type
                    "category_stats": [
                        {"$group": {
                            "_id": {
                                "currency": "$currency",
                                "type": "$type",
                                "category": {"$concat": ["$main_category", " > ", "$sub_category"]}
                            },
                            "total": {"$sum": "$amount"}
                        }},
                        {"$sort": {"total": -1}}
                    ]
                }}
            ]

            # Execute single DB query
            result = list(transactions_collection.aggregate(pipeline))[0]
            
            # Process results into expected structure
            currency_summaries = {}
            total_transactions_all = 0
            
            # Initialize currency objects
            for stat in result.get("currency_stats", []):
                currency = stat["_id"] if stat["_id"] else "usd"
                total_transactions_all += stat["count"]
                
                currency_summaries[currency] = {
                    "total_inflow": stat["total_inflow"],
                    "total_outflow": stat["total_outflow"],
                    "balance": stat["total_inflow"] - stat["total_outflow"],
                    "total_transactions": stat["count"],
                    "avg_transaction_amount": stat["total_amount_sum"] / stat["count"] if stat["count"] > 0 else 0,
                    "date_range": {
                        "from": ensure_utc_datetime(stat["min_date"]).isoformat() if stat["min_date"] else None,
                        "to": ensure_utc_datetime(stat["max_date"]).isoformat() if stat["max_date"] else None
                    },
                    "top_inflow_categories": {},
                    "top_outflow_categories": {}
                }

            # Populate categories (already sorted by DB)
            for cat in result.get("category_stats", []):
                curr = cat["_id"].get("currency", "usd")
                tx_type = cat["_id"].get("type")
                cat_name = cat["_id"].get("category")
                amount = cat["total"]
                
                if curr not in currency_summaries:
                    continue
                    
                # Fill top 10 categories
                target_dict = (
                    currency_summaries[curr]["top_inflow_categories"] 
                    if tx_type == "inflow" 
                    else currency_summaries[curr]["top_outflow_categories"]
                )
                
                if len(target_dict) < 10:
                    target_dict[cat_name] = amount

            print(f"✅ Generated summary for user {self.user_id} using Aggregation Pipeline")
            
            return {
                "currencies": currency_summaries,
                "total_transactions": total_transactions_all
            }

        except Exception as e:
            print(f"Error generating financial summary: {e}")
            return {"message": "Error generating financial summary"}
    
    def create_financial_documents(self) -> List[Document]:
        """Create optimized documents for GPT-4 with multi-currency support"""
        transactions = self.get_user_transactions()
        goals = self.get_user_goals()
        budgets = self.get_user_budgets()
        summary = self.get_financial_summary()
        documents = []
        
        # === FINANCIAL GOALS OVERVIEW (MULTI-CURRENCY) ===
        if goals:
            # Group goals by currency
            goals_by_currency = {}
            for g in goals:
                currency = g.get("currency", "usd")
                if currency not in goals_by_currency:
                    goals_by_currency[currency] = []
                goals_by_currency[currency].append(g)
            
            goals_text = "═══════════════════════════════════════════════════\n"
            goals_text += "║           FINANCIAL GOALS OVERVIEW                ║\n"
            goals_text += "═══════════════════════════════════════════════════\n\n"
            
            for currency, curr_goals in goals_by_currency.items():
                currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
                currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")
                
                active_goals = [g for g in curr_goals if g["status"] == "active"]
                achieved_goals = [g for g in curr_goals if g["status"] == "achieved"]
                
                total_allocated = sum(g["current_amount"] for g in active_goals)
                total_target = sum(g["target_amount"] for g in active_goals)
                
                goals_text += f"💰 {currency_name} GOALS:\n"
                goals_text += f"  • Total Goals: {len(curr_goals)}\n"
                goals_text += f"  • Active Goals: {len(active_goals)}\n"
                goals_text += f"  • Achieved Goals: {len(achieved_goals)}\n"
                goals_text += f"  • Total Allocated: {currency_symbol}{total_allocated:.2f}\n"
                goals_text += f"  • Total Target (Active): {currency_symbol}{total_target:.2f}\n"
                goals_text += f"  • Overall Progress: {(total_allocated / total_target * 100) if total_target > 0 else 0:.1f}%\n\n"
                
                if active_goals:
                    goals_text += f"🎯 ACTIVE {currency_name} GOALS:\n\n"
                    for idx, g in enumerate(active_goals, 1):
                        progress = (g["current_amount"] / g["target_amount"] * 100) if g["target_amount"] > 0 else 0
                        remaining = g["target_amount"] - g["current_amount"]
                        
                        goals_text += f"──── Goal #{idx}: {g['name']} ────\n"
                        goals_text += f"Type: {g['goal_type'].replace('_', ' ').title()}\n"
                        goals_text += f"Target: {currency_symbol}{g['target_amount']:.2f}\n"
                        goals_text += f"Current: {currency_symbol}{g['current_amount']:.2f}\n"
                        goals_text += f"Remaining: {currency_symbol}{remaining:.2f}\n"
                        goals_text += f"Progress: {progress:.1f}%\n"
                        
                        if g.get("target_date"):
                            target_date = ensure_utc_datetime(g["target_date"])
                            days_remaining = (target_date - datetime.now(timezone.utc)).days
                            goals_text += f"Target Date: {target_date.strftime('%B %d, %Y')}\n"
                            goals_text += f"Days Remaining: {days_remaining}\n"
                            
                            if days_remaining > 0 and remaining > 0:
                                daily_needed = remaining / days_remaining
                                goals_text += f"Daily Savings Needed: {currency_symbol}{daily_needed:.2f}\n"
                        
                        goals_text += f"Created: {ensure_utc_datetime(g['created_at']).strftime('%b %d, %Y')}\n\n"
                
                if achieved_goals:
                    goals_text += f"🏆 ACHIEVED {currency_name} GOALS:\n\n"
                    for idx, g in enumerate(achieved_goals, 1):
                        goals_text += f"✓ {g['name']}: {currency_symbol}{g['target_amount']:.2f}\n"
                        if g.get("achieved_at"):
                            achieved_date = ensure_utc_datetime(g["achieved_at"])
                            goals_text += f"  Achieved: {achieved_date.strftime('%b %d, %Y')}\n"
                        goals_text += "\n"
                
                goals_text += "\n"
            
            documents.append(Document(
                page_content=goals_text,
                metadata={
                    "type": "goals_overview",
                    "user_id": self.user_id,
                    "priority": "high"
                }
            ))
            
            
        # === BUDGETS OVERVIEW (MULTI-CURRENCY) ===
        if budgets:
            # Group budgets by currency
            budgets_by_currency = {}
            for b in budgets:
                currency = b.get("currency", "usd")
                if currency not in budgets_by_currency:
                    budgets_by_currency[currency] = []
                budgets_by_currency[currency].append(b)
            
            budgets_text = "╔═══════════════════════════════════════════════════╗\n"
            budgets_text += "║           ACTIVE BUDGETS OVERVIEW                 ║\n"
            budgets_text += "╚═══════════════════════════════════════════════════╝\n\n"
            
            for currency, curr_budgets in budgets_by_currency.items():
                currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
                currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")
                
                total_allocated = sum(b["total_budget"] for b in curr_budgets)
                total_spent = sum(b["total_spent"] for b in curr_budgets)
                overall_remaining = total_allocated - total_spent
                overall_percentage = (total_spent / total_allocated * 100) if total_allocated > 0 else 0
                
                budgets_text += f"💰 {currency_name} BUDGETS:\n"
                budgets_text += f"  • Total Active Budgets: {len(curr_budgets)}\n"
                budgets_text += f"  • Total Allocated: {currency_symbol}{total_allocated:.2f}\n"
                budgets_text += f"  • Total Spent: {currency_symbol}{total_spent:.2f}\n"
                budgets_text += f"  • Overall Remaining: {currency_symbol}{overall_remaining:.2f}\n"
                budgets_text += f"  • Overall Usage: {overall_percentage:.1f}%\n\n"
                
                budgets_text += f"📊 ACTIVE {currency_name} BUDGETS:\n\n"
                for idx, b in enumerate(curr_budgets, 1):
                    start_date = ensure_utc_datetime(b["start_date"])
                    end_date = ensure_utc_datetime(b["end_date"])
                    days_remaining = (end_date - datetime.now(timezone.utc)).days
                    days_total = (end_date - start_date).days + 1
                    
                    budgets_text += f"──── Budget #{idx}: {b['name']} ────\n"
                    budgets_text += f"Period: {b['period'].title()}\n"
                    budgets_text += f"Duration: {start_date.strftime('%b %d, %Y')} - {end_date.strftime('%b %d, %Y')}\n"
                    budgets_text += f"Days Remaining: {days_remaining} of {days_total}\n"
                    budgets_text += f"Total Budget: {currency_symbol}{b['total_budget']:.2f}\n"
                    budgets_text += f"Total Spent: {currency_symbol}{b['total_spent']:.2f}\n"
                    budgets_text += f"Remaining: {currency_symbol}{b['remaining_budget']:.2f}\n"
                    budgets_text += f"Usage: {b['percentage_used']:.1f}%\n"
                    
                    # Status indicator
                    if b['percentage_used'] >= 100:
                        budgets_text += f"Status: 🔴 EXCEEDED\n"
                    elif b['percentage_used'] >= 80:
                        budgets_text += f"Status: 🟡 HIGH USAGE (Caution)\n"
                    else:
                        budgets_text += f"Status: 🟢 ON TRACK\n"
                    
                    budgets_text += f"\nCategory Breakdown:\n"
                    for cat in b['category_budgets']:
                        cat_name = cat['main_category']
                        cat_allocated = cat['allocated_amount']
                        cat_spent = cat['spent_amount']
                        cat_remaining = cat_allocated - cat_spent
                        cat_percentage = cat.get('percentage_used', 0)
                        
                        status_icon = "🔴" if cat.get('is_exceeded') else ("🟡" if cat_percentage >= 80 else "🟢")
                        
                        budgets_text += f"  {status_icon} {cat_name}:\n"
                        budgets_text += f"     Budget: {currency_symbol}{cat_allocated:.2f} | "
                        budgets_text += f"Spent: {currency_symbol}{cat_spent:.2f} | "
                        budgets_text += f"Left: {currency_symbol}{cat_remaining:.2f} | "
                        budgets_text += f"{cat_percentage:.1f}%\n"
                    
                    budgets_text += "\n"
            
            documents.append(Document(
                page_content=budgets_text,
                metadata={
                    "type": "budgets_overview",
                    "user_id": self.user_id,
                    "priority": "high"
                }
            ))
        
        # === CRITICAL: CHRONOLOGICAL INDEX (MULTI-CURRENCY) ===
        chronological_text = "═══════════════════════════════════════════════════\n"
        chronological_text += "║   TRANSACTION TIMELINE - NEWEST TO OLDEST          ║\n"
        chronological_text += "═══════════════════════════════════════════════════\n\n"
        chronological_text += "⚠️ IMPORTANT: The transactions below are sorted NEWEST FIRST.\n"
        chronological_text += "When asked about 'latest', 'recent', 'last', or 'newest' - Transaction #1 is the MOST RECENT.\n\n"
        
        for idx, t in enumerate(transactions[:25], 1):
            date_obj = ensure_utc_datetime(t["date"])
            days_ago = (datetime.now(timezone.utc) - date_obj).days
            
            currency = t.get("currency", "usd")
            currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
            currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")

            
            recency_indicator = "🔴 TODAY" if days_ago == 0 else f"📅 {days_ago} days ago"
            
            chronological_text += f"─── Transaction #{idx} ({recency_indicator}) ───\n"
            chronological_text += f"Date: {date_obj.strftime('%A, %B %d, %Y')} ({get_date_only(t['date'])})\n"
            chronological_text += f"Type: {t['type'].title()}\n"
            chronological_text += f"Amount: {currency_symbol}{t['amount']:.2f} ({currency_name})\n"
            chronological_text += f"Category: {t['main_category']} > {t['sub_category']}\n"
            if t.get("description"):
                chronological_text += f"Description: {t['description']}\n"
            chronological_text += "\n"
        
        if len(transactions) > 25:
            chronological_text += f"... plus {len(transactions) - 25} older transactions\n"
        
        documents.append(Document(
            page_content=chronological_text,
            metadata={
                "type": "chronological_index",
                "user_id": self.user_id,
                "priority": "critical"
            }
        ))
        
        # === FINANCIAL SUMMARY (MULTI-CURRENCY) ===
        summary_text = "═══════════════════════════════════════════════════\n"
        summary_text += "║              FINANCIAL SUMMARY                       ║\n"
        summary_text += "═══════════════════════════════════════════════════\n\n"
        
        if summary.get("currencies"):
            for currency, data in summary["currencies"].items():
                currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
                currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")
                
                summary_text += f"💰 {currency_name} SUMMARY:\n"
                summary_text += f"Current Balance: {currency_symbol}{data.get('balance', 0):.2f}\n"
                
                # Add goals impact if exists
                curr_goals = [g for g in goals if g.get("currency", "usd") == currency and g["status"] == "active"]
                if curr_goals:
                    total_allocated = sum(g["current_amount"] for g in curr_goals)
                    available_balance = data.get('balance', 0) - total_allocated
                    
                    summary_text += f"Allocated to Goals: {currency_symbol}{total_allocated:.2f}\n"
                    summary_text += f"Available Balance: {currency_symbol}{available_balance:.2f}\n"
                
                summary_text += f"Total Income: {currency_symbol}{data.get('total_inflow', 0):.2f}\n"
                summary_text += f"Total Expenses: {currency_symbol}{data.get('total_outflow', 0):.2f}\n"
                summary_text += f"Total Transactions: {data.get('total_transactions', 0)}\n"
                summary_text += f"Average Transaction: {currency_symbol}{data.get('avg_transaction_amount', 0):.2f}\n"
                summary_text += f"Data Period: {data.get('date_range', {}).get('from', 'N/A')[:10]} to {data.get('date_range', {}).get('to', 'N/A')[:10]}\n\n"
                
                summary_text += f"Top Income Sources ({currency_name}):\n"
                for cat, amount in list(data.get('top_inflow_categories', {}).items())[:5]:
                    summary_text += f"  • {cat}: {currency_symbol}{amount:.2f}\n"
                
                summary_text += f"\nTop Expense Categories ({currency_name}):\n"
                for cat, amount in list(data.get('top_outflow_categories', {}).items())[:5]:
                    summary_text += f"  • {cat}: {currency_symbol}{amount:.2f}\n"
                
                summary_text += "\n"
        
        documents.append(Document(
            page_content=summary_text,
            metadata={
                "type": "summary",
                "user_id": self.user_id
            }
        ))
        
        # === INDIVIDUAL GOAL DETAILS (with currency) ===
        for goal in goals:
            currency = goal.get("currency", "usd")
            currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
            currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")
            
            goal_text = f"═══════════════════════════════════════════════════\n"
            goal_text += f"║   GOAL: {goal['name'][:40].center(40)}   ║\n"
            goal_text += f"═══════════════════════════════════════════════════\n\n"
            
            progress = (goal["current_amount"] / goal["target_amount"] * 100) if goal["target_amount"] > 0 else 0
            remaining = goal["target_amount"] - goal["current_amount"]
            
            goal_text += f"Currency: {currency_name}\n"
            goal_text += f"Status: {goal['status'].upper()}\n"
            goal_text += f"Type: {goal['goal_type'].replace('_', ' ').title()}\n"
            goal_text += f"Target Amount: {currency_symbol}{goal['target_amount']:.2f}\n"
            goal_text += f"Current Amount: {currency_symbol}{goal['current_amount']:.2f}\n"
            goal_text += f"Remaining: {currency_symbol}{remaining:.2f}\n"
            goal_text += f"Progress: {progress:.1f}%\n\n"
            
            if goal.get("target_date"):
                target_date = ensure_utc_datetime(goal["target_date"])
                goal_text += f"Target Date: {target_date.strftime('%B %d, %Y')}\n"
                
                if goal["status"] == "active":
                    days_remaining = (target_date - datetime.now(timezone.utc)).days
                    goal_text += f"Days Remaining: {days_remaining}\n"
                    
                    if days_remaining > 0 and remaining > 0:
                        daily_needed = remaining / days_remaining
                        weekly_needed = daily_needed * 7
                        monthly_needed = daily_needed * 30
                        
                        goal_text += f"\nSavings Needed:\n"
                        goal_text += f"  • Daily: {currency_symbol}{daily_needed:.2f}\n"
                        goal_text += f"  • Weekly: {currency_symbol}{weekly_needed:.2f}\n"
                        goal_text += f"  • Monthly: {currency_symbol}{monthly_needed:.2f}\n"
            
            goal_text += f"\nCreated: {ensure_utc_datetime(goal['created_at']).strftime('%B %d, %Y')}\n"
            
            if goal.get("achieved_at"):
                achieved_date = ensure_utc_datetime(goal["achieved_at"])
                goal_text += f"Achieved: {achieved_date.strftime('%B %d, %Y')}\n"
                
                created_date = ensure_utc_datetime(goal["created_at"])
                days_taken = (achieved_date - created_date).days
                goal_text += f"Time Taken: {days_taken} days\n"
            
            documents.append(Document(
                page_content=goal_text,
                metadata={
                    "type": "goal_detail",
                    "user_id": self.user_id,
                    "goal_id": goal["_id"],
                    "goal_name": goal["name"],
                    "goal_status": goal["status"],
                    "currency": currency
                }
            ))
        
        
        # === INDIVIDUAL BUDGET DETAILS (with currency) ===
        for budget in budgets:
            currency = budget.get("currency", "usd")
            currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
            currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")
            
            start_date = ensure_utc_datetime(budget["start_date"])
            end_date = ensure_utc_datetime(budget["end_date"])
            days_remaining = (end_date - datetime.now(timezone.utc)).days
            days_total = (end_date - start_date).days + 1
            days_elapsed = days_total - days_remaining
            
            budget_text = f"╔═══════════════════════════════════════════════════╗\n"
            budget_text += f"║   BUDGET: {budget['name'][:40].center(40)}   ║\n"
            budget_text += f"╚═══════════════════════════════════════════════════╝\n\n"
            
            budget_text += f"Currency: {currency_name}\n"
            budget_text += f"Period: {budget['period'].title()}\n"
            budget_text += f"Start Date: {start_date.strftime('%B %d, %Y')}\n"
            budget_text += f"End Date: {end_date.strftime('%B %d, %Y')}\n"
            budget_text += f"Days Elapsed: {days_elapsed} / {days_total}\n"
            budget_text += f"Days Remaining: {days_remaining}\n\n"
            
            budget_text += f"💰 OVERALL BUDGET:\n"
            budget_text += f"Total Budget: {currency_symbol}{budget['total_budget']:.2f}\n"
            budget_text += f"Total Spent: {currency_symbol}{budget['total_spent']:.2f}\n"
            budget_text += f"Remaining: {currency_symbol}{budget['remaining_budget']:.2f}\n"
            budget_text += f"Usage: {budget['percentage_used']:.1f}%\n"
            
            if budget['percentage_used'] >= 100:
                budget_text += f"⚠️  BUDGET EXCEEDED by {currency_symbol}{budget['total_spent'] - budget['total_budget']:.2f}\n"
            elif budget['percentage_used'] >= 80:
                budget_text += f"⚠️  CAUTION: High usage - {currency_symbol}{budget['remaining_budget']:.2f} remaining\n"
            
            # Daily rate analysis
            if days_remaining > 0:
                daily_rate_current = budget['total_spent'] / days_elapsed if days_elapsed > 0 else 0
                daily_budget_remaining = budget['remaining_budget'] / days_remaining
                
                budget_text += f"\n📊 SPENDING RATE:\n"
                budget_text += f"Current Daily Avg: {currency_symbol}{daily_rate_current:.2f}\n"
                budget_text += f"Daily Budget Left: {currency_symbol}{daily_budget_remaining:.2f}\n"
                
                if daily_rate_current > daily_budget_remaining:
                    budget_text += f"⚠️  Spending faster than budget allows!\n"
            
            budget_text += f"\n📋 CATEGORY BUDGETS:\n\n"
            for cat in budget['category_budgets']:
                cat_name = cat['main_category']
                cat_allocated = cat['allocated_amount']
                cat_spent = cat['spent_amount']
                cat_remaining = cat_allocated - cat_spent
                cat_percentage = cat.get('percentage_used', 0)
                
                budget_text += f"──── {cat_name} ────\n"
                budget_text += f"Allocated: {currency_symbol}{cat_allocated:.2f}\n"
                budget_text += f"Spent: {currency_symbol}{cat_spent:.2f}\n"
                budget_text += f"Remaining: {currency_symbol}{cat_remaining:.2f}\n"
                budget_text += f"Usage: {cat_percentage:.1f}%\n"
                
                if cat.get('is_exceeded'):
                    budget_text += f"🔴 EXCEEDED by {currency_symbol}{abs(cat_remaining):.2f}\n"
                elif cat_percentage >= 80:
                    budget_text += f"🟡 HIGH USAGE - approaching limit\n"
                else:
                    budget_text += f"🟢 ON TRACK\n"
                
                budget_text += "\n"
            
            documents.append(Document(
                page_content=budget_text,
                metadata={
                    "type": "budget_detail",
                    "user_id": self.user_id,
                    "budget_id": budget["_id"],
                    "budget_name": budget["name"],
                    "currency": currency
                }
            ))

        # === DAILY SUMMARIES (Last 30 days, multi-currency) ===
        transactions_by_date = {}
        for t in transactions:
            date_str = get_date_only(t["date"])
            if date_str not in transactions_by_date:
                transactions_by_date[date_str] = []
            transactions_by_date[date_str].append(t)
        
        recent_cutoff = datetime.now(timezone.utc) - timedelta(days=30)
        
        for date_str, daily_transactions in sorted(transactions_by_date.items(), reverse=True)[:30]:
            date_obj = ensure_utc_datetime(daily_transactions[0]["date"])
            
            if date_obj < recent_cutoff:
                continue
            
            days_ago = (datetime.now(timezone.utc) - date_obj).days
            
            # Group by currency
            currency_totals = {}
            for t in daily_transactions:
                currency = t.get("currency", "usd")
                if currency not in currency_totals:
                    currency_totals[currency] = {"inflow": 0, "outflow": 0, "transactions": []}
                
                if t["type"] == "inflow":
                    currency_totals[currency]["inflow"] += t["amount"]
                else:
                    currency_totals[currency]["outflow"] += t["amount"]
                
                currency_totals[currency]["transactions"].append(t)
            
            daily_text = f"─── {date_obj.strftime('%A, %B %d, %Y')} ({days_ago} days ago) ───\n\n"
            daily_text += f"Daily Summary: {len(daily_transactions)} transactions\n\n"
            
            for currency, totals in currency_totals.items():
                currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
                currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")
                
                daily_text += f"{currency_name}:\n"
                daily_text += f"  Income: +{currency_symbol}{totals['inflow']:.2f}\n"
                daily_text += f"  Expenses: -{currency_symbol}{totals['outflow']:.2f}\n"
                daily_text += f"  Net: {currency_symbol}{totals['inflow'] - totals['outflow']:.2f}\n\n"
            
            daily_text += "Transactions:\n"
            for t in daily_transactions:
                currency = t.get("currency", "usd")
                currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
                currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")
                
                daily_text += f"  • {t['type'].title()}: {currency_symbol}{t['amount']:.2f} ({currency_name}) - {t['main_category']} > {t['sub_category']}"
                if t.get("description"):
                    daily_text += f" ({t['description']})"
                daily_text += "\n"
            
            documents.append(Document(
                page_content=daily_text,
                metadata={
                    "type": "daily_summary",
                    "user_id": self.user_id,
                    "date": date_str,
                    "days_ago": days_ago
                }
            ))
        
        # === CATEGORY INSIGHTS (group by currency) ===
        categories_by_currency = {}
        for t in transactions:
            currency = t.get("currency", "usd")
            if currency not in categories_by_currency:
                categories_by_currency[currency] = {}
            
            cat_key = f"{t['main_category']} > {t['sub_category']}"
            if cat_key not in categories_by_currency[currency]:
                categories_by_currency[currency][cat_key] = {"transactions": [], "total": 0, "type": t["type"]}
            
            categories_by_currency[currency][cat_key]["transactions"].append(t)
            categories_by_currency[currency][cat_key]["total"] += t["amount"]
        
        for currency, categories in categories_by_currency.items():
            currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
            currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")
            
            for category, data in sorted(categories.items(), key=lambda x: x[1]["total"], reverse=True)[:8]:
                category_text = f"─── Category: {category} ({currency_name}) ───\n\n"
                category_text += f"Type: {data['type'].title()}\n"
                category_text += f"Total: {currency_symbol}{data['total']:.2f}\n"
                category_text += f"Transactions: {len(data['transactions'])}\n"
                category_text += f"Average: {currency_symbol}{data['total'] / len(data['transactions']):.2f}\n\n"
                category_text += "Recent Examples:\n"
                
                for t in data['transactions'][:5]:
                    date_obj = ensure_utc_datetime(t["date"])
                    category_text += f"  • {date_obj.strftime('%b %d, %Y')}: {currency_symbol}{t['amount']:.2f}"
                    if t.get("description"):
                        category_text += f" - {t['description']}"
                    category_text += "\n"
                
                documents.append(Document(
                    page_content=category_text,
                    metadata={
                        "type": "category",
                        "user_id": self.user_id,
                        "category": category,
                        "currency": currency
                    }
                ))
        
        print(f"✅ Created {len(documents)} optimized documents for GPT-4 (including {len(goals)} goals, {len(budgets)} budgets, multi-currency)")
        return documents


class FinancialChatbot:
    """AI Chatbot with GPT-4 + Optimized RAG (Recommended Approach)"""
    
    def __init__(self):
        self.last_usage = {}
        self.openai_api_key = os.getenv("OPENAI_API_KEY")
        if not self.openai_api_key:
            print("Warning: OPENAI_API_KEY not found")
        
        try:
            self.embeddings = OpenAIEmbeddings(
                api_key=self.openai_api_key,
                model="text-embedding-3-small"
            )
        except Exception as e:
            print(f"Error initializing embeddings: {e}")
            self.embeddings = None
        
        self.text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=1500,
            chunk_overlap=200,
            separators=["\n\n", "\n", " ", ""]
        )
        self.user_vector_stores = {}
        
        self.gpt_model = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
    
    def _get_or_create_vector_store(self, user_id: str) -> Chroma:
        """Get or create vector store for user"""
        if user_id not in self.user_vector_stores:
            processor = FinancialDataProcessor(user_id)
            documents = processor.create_financial_documents()
            
            if not documents or not self.embeddings:
                return None
            
            try:
                split_documents = []
                for doc in documents:
                    # Never split chronological index or goals overview
                    if doc.metadata.get("type") in ["chronological_index", "goals_overview"]:
                        split_documents.append(doc)
                    else:
                        split_documents.extend(self.text_splitter.split_documents([doc]))
                
                vector_store = Chroma.from_documents(
                    documents=split_documents,
                    embedding=self.embeddings,
                    collection_name=f"user_{user_id}_{int(datetime.now().timestamp())}"
                )
                self.user_vector_stores[user_id] = vector_store
                print(f"✅ Created vector store with {len(split_documents)} chunks")
            except Exception as e:
                print(f"❌ Error creating vector store: {e}")
                return None
        
        return self.user_vector_stores[user_id]
    
    def refresh_user_data(self, user_id: str):
        """Refresh user's financial data in vector store"""
        if user_id in self.user_vector_stores:
            try:
                self.user_vector_stores[user_id].delete_collection()
            except:
                pass
            del self.user_vector_stores[user_id]
        
        self._get_or_create_vector_store(user_id)
        print(f"✅ Refreshed data for user {user_id}")
    
    def _build_system_prompt(self, today: str, response_style: str = "normal") -> str:
        """Build enhanced system prompt for GPT-4 with Myanmar language support and response style"""
        
        # Define style-specific instructions
        style_instructions = {
            "normal": """
    - Answer directly and clearly
    - Include relevant details
    - Use 2-4 sentences for simple questions, more for complex ones
    - Balance between brevity and completeness
    """,
            "concise": """
    - Be extremely brief and direct
    - Use 1-2 sentences maximum
    - Focus only on the core answer
    - Eliminate all unnecessary words
    - Use bullet points for lists
    - Example: "Balance: $1,234.56" instead of "Your current balance is $1,234.56"
    """,
            "explanatory": """
    - Provide detailed, thorough explanations
    - Include context, reasoning, and background information
    - Break down complex topics into steps
    - Add relevant examples and scenarios
    - Explain the "why" behind numbers and patterns
    - Use 5-10 sentences or more as needed
    - Help users understand not just "what" but "why" and "how"
    """
        }
        
        style_instruction = style_instructions.get(response_style, style_instructions["normal"])
        
        return f"""You are Flow Finance AI, an expert personal finance assistant with complete access to the user's transaction history, financial goals, and budgets.

📅 Today's date: {today}

🌍 LANGUAGE CAPABILITY:
- You are FLUENT in both Myanmar (Burmese) and English language
- Detect the user's language automatically from their message
- If the user writes in Myanmar, respond ENTIRELY in Myanmar
- If the user writes in English, respond ENTIRELY in English
- Maintain consistency - don't mix languages unless the user does
- Use natural, conversational Myanmar that feels native and friendly
- For financial terms in Myanmar, use commonly understood terms (e.g., "ငွေ" for money, "စုငွေ" for savings, "ရည်မှန်းချက်" for goals, "ဘတ်ဂျက်" for budget)

💱 MULTI-CURRENCY CAPABILITY:
- The user can have transactions, goals, and budgets in multiple currencies (USD, MMK, THB)  
- ALWAYS specify the currency when discussing amounts (e.g., "$100 USD", "50,000 K MMK", or "฿1,000 THB") 
- When comparing amounts across currencies, mention they are in different currencies
- Currency symbols: USD uses "$", MMK uses "K" or "Ks", THB uses "฿"  
- NEVER mix currencies in calculations without explicit conversion
- If asked about "total balance" or "overall finances", break down by currency
- When discussing goals or budgets, always mention which currency they are in

Your capabilities:
- Answer questions about transactions with precision (multi-currency aware)
- Provide insights on financial goals and progress (per currency)
- Track goal achievements and suggest strategies
- Monitor budget performance and spending patterns (per currency)
- Alert users to budget overruns or high usage
- Provide budget vs actual spending analysis
- Calculate savings needed to reach goals (in the goal's currency)
- Identify spending patterns that affect goal progress and budget compliance (currency-specific)
- Provide spending insights and financial advice
- Help users understand their finances holistically across currencies

🎯 CRITICAL RULES FOR ACCURACY:

1. TEMPORAL QUERIES ("latest", "recent", "last", "newest" or Myanmar: "နောက်ဆုံး", "မကြာသေးသော", "လတ်တလော"):
- The data includes a CHRONOLOGICAL INDEX sorted NEWEST → OLDEST
- Transaction #1 in that index is ALWAYS the most recent
- Look for visual indicators like "🔴 TODAY" or "days ago"
- NEVER confuse older transactions with newer ones

2. CURRENCY AWARENESS:
- ALWAYS mention currency when discussing amounts
- Format: "$X.XX (USD)" or "X K (MMK)"
- Never add amounts from different currencies without mentioning it
- If comparing multi-currency data, present them separately
- Be explicit: "You have $500 USD and 1,000,000 K MMK"

3. GOALS AWARENESS (MULTI-CURRENCY):
- Always check the GOALS OVERVIEW for the user's financial goals
- Goals are currency-specific - mention which currency each goal uses
- When discussing balance, consider both total balance and available balance per currency
- Suggest how spending changes could help achieve goals faster
- Celebrate progress and provide encouragement
- Be specific about goal timelines and required savings rates (in goal's currency)

4. BUDGET AWARENESS (MULTI-CURRENCY):
- Always check the BUDGETS OVERVIEW for active budgets
- Budgets are currency-specific and period-based (weekly, monthly, yearly)
- Monitor budget usage percentages and alert when approaching limits (80%+)
- Compare actual spending vs budgeted amounts by category
- Warn about exceeded budgets or categories (100%+)
- Consider daily spending rates vs remaining budget
- Suggest spending adjustments to stay within budget
- Relate spending to both budgets AND goals

5. DATE ACCURACY:
- Today is {today}
- Verify dates carefully before answering
- Use the "days ago" information as a guide
- For budgets, calculate days remaining vs days elapsed

6. RESPONSE STYLE - {response_style.upper()}:
{style_instructions.get(response_style, style_instructions["normal"])}

7. FORMATTING:
- Format money as $X.XX (USD) or X K (MMK)
- Include specific dates when relevant
- If unsure about something, say so honestly
- Never fabricate transaction, goal, or budget details

8. MYANMAR LANGUAGE SPECIFICS:
- Use respectful Myanmar expressions naturally 
- Keep financial advice clear and easy to understand
- Use bullet points (•) for lists in Myanmar responses too
- When translating amounts, keep currency symbols: $X.XX or X K
- Be warm and encouraging in Myanmar - financial discussions can be sensitive

9. PRIORITIZATION:
- For "latest/recent" queries, ALWAYS check the chronological index FIRST
- For goal-related queries, check the goals overview and individual goal details
- For budget-related queries, check the budgets overview and individual budget details
- For currency-specific queries, filter by the mentioned currency
- Consider the interplay between spending, budgets, saving, and goal progress per currency

10. BUDGET-SPECIFIC ADVICE:
- When discussing spending, ALWAYS consider if it affects active budgets
- Warn proactively if spending patterns suggest budget will be exceeded
- Celebrate staying within budget limits
- Suggest budget adjustments based on actual spending patterns
- Link budget performance to financial goals
- Provide actionable insights: "To stay on track, limit [category] spending to $X per day"

Remember: Accuracy is more important than speed. Double-check dates, amounts, AND currencies! Respect their time and adapt your verbosity to their preference. Help users make informed decisions by considering their budgets, goals, and spending together.

ဘာသာစကားကို သဘာဝကျကျ သုံးပါ။ (Use language naturally.)"""
    
    def _build_user_prompt(self, user: Dict, summary: Dict, goals_summary: Dict, budgets_summary: Dict, context: str, history_text: str, message: str, today: str) -> str:
        """Build comprehensive user prompt with multi-currency support including budgets"""
        prompt = f"""User Profile:
    Name: {user.get('name', 'User')}
    Default Currency: {user.get('default_currency', 'usd').upper()}
    Today: {today}

    Quick Overview:
    """
        
        # Multi-currency balance display
        if summary.get("currencies"):
            prompt += "💰 BALANCES BY CURRENCY:\n"
            for currency, data in summary["currencies"].items():
                currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
                currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")
                
                prompt += f"\n{currency_name}:\n"
                prompt += f"  Total Balance: {currency_symbol}{data.get('balance', 0):.2f}\n"
                
                # Goals allocation for this currency
                if goals_summary:
                    curr_goals = [g for g in goals_summary.get('goals_by_currency', {}).get(currency, [])]
                    if curr_goals:
                        allocated = sum(g.get('current_amount', 0) for g in curr_goals if g.get('status') == 'active')
                        prompt += f"  💎 Allocated to Goals: {currency_symbol}{allocated:.2f}\n"
                        prompt += f"  ✨ Available Balance: {currency_symbol}{data.get('balance', 0) - allocated:.2f}\n"
                
                # Budget info for this currency
                if budgets_summary:
                    curr_budgets = budgets_summary.get('budgets_by_currency', {}).get(currency, {})
                    if curr_budgets:
                        budget_allocated = curr_budgets.get('total_allocated', 0)
                        budget_spent = curr_budgets.get('total_spent', 0)
                        budget_remaining = curr_budgets.get('remaining', 0)
                        budget_percentage = curr_budgets.get('percentage_used', 0)
                        
                        prompt += f"  📊 Active Budget: {currency_symbol}{budget_allocated:.2f}\n"
                        prompt += f"  💸 Budget Spent: {currency_symbol}{budget_spent:.2f} ({budget_percentage:.1f}%)\n"
                        prompt += f"  💰 Budget Left: {currency_symbol}{budget_remaining:.2f}\n"
                        
                        if budget_percentage >= 100:
                            prompt += f"  ⚠️  BUDGET EXCEEDED!\n"
                        elif budget_percentage >= 80:
                            prompt += f"  🟡 High budget usage - caution needed\n"
                
                # Calculate available balance (after goals and considering budget)
                available = data.get('balance', 0)
                if goals_summary:
                    curr_goals = [g for g in goals_summary.get('goals_by_currency', {}).get(currency, [])]
                    if curr_goals:
                        allocated = sum(g.get('current_amount', 0) for g in curr_goals if g.get('status') == 'active')
                        available -= allocated
                
                prompt += f"  ✨ Available Balance: {currency_symbol}{available:.2f}\n"
                prompt += f"  📈 Income: {currency_symbol}{data.get('total_inflow', 0):.2f}\n"
                prompt += f"  📉 Expenses: {currency_symbol}{data.get('total_outflow', 0):.2f}\n"
        
        # Goals summary by currency
        if goals_summary and goals_summary.get('goals_by_currency'):
            prompt += "\n🎯 GOALS BY CURRENCY:\n"
            for currency, curr_goals in goals_summary['goals_by_currency'].items():
                currency_name = "USD" if currency == "usd" else "MMK"
                active = [g for g in curr_goals if g.get('status') == 'active']
                achieved = [g for g in curr_goals if g.get('status') == 'achieved']
                prompt += f"  {currency_name}: {len(active)} active, {len(achieved)} achieved\n"
        
        # Budgets summary by currency
        if budgets_summary and budgets_summary.get('budgets_by_currency'):
            prompt += "\n📊 BUDGETS BY CURRENCY:\n"
            for currency, curr_budget_data in budgets_summary['budgets_by_currency'].items():
                currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
                currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")
                
                active_count = curr_budget_data.get('active_count', 0)
                total_allocated = curr_budget_data.get('total_allocated', 0)
                total_spent = curr_budget_data.get('total_spent', 0)
                percentage = curr_budget_data.get('percentage_used', 0)
                
                status_icon = "🔴" if percentage >= 100 else ("🟡" if percentage >= 80 else "🟢")
                
                prompt += f"  {currency_name}: {active_count} active budget(s) - "
                prompt += f"{currency_symbol}{total_spent:.2f}/{currency_symbol}{total_allocated:.2f} "
                prompt += f"({percentage:.1f}%) {status_icon}\n"
        
        prompt += f"""

    ╔══════════════════════════════════════════════════╗
                        FINANCIAL DATA
    ╚══════════════════════════════════════════════════╝

    {context}

    {f"╔══════════════════════════════════════════════════╗\n            CONVERSATION HISTORY\n╚══════════════════════════════════════════════════╝\n{history_text}" if history_text else ""}

    ╔══════════════════════════════════════════════════╗
                        USER QUESTION
    ╚══════════════════════════════════════════════════╝

    {message}

    Please provide an accurate, helpful answer based on the financial data above. Remember to specify currencies when discussing amounts, and consider budgets, goals, and spending together!"""
        
        return prompt
    
    async def stream_chat(self, user_id: str, message: str, chat_history: Optional[List[Dict]] = None, response_style: str = "normal"):
        """Stream chat response using GPT-4 with enhanced RAG and response style"""
        try:
            if not self.openai_api_key:
                yield "AI service is not available. OpenAI API key not configured.", None # ✅ FIXED
                return

            # Run DB lookup in thread
            user = await asyncio.to_thread(users_collection.find_one, {"_id": user_id})
            if not user:
                yield "User not found. Please log in again.", None
                return
            
            processor = FinancialDataProcessor(user_id)
            
            # Fetch all financial data in parallel threads to prevent blocking
            summary_task = asyncio.to_thread(processor.get_financial_summary)
            goals_task = asyncio.to_thread(processor.get_user_goals)
            budgets_task = asyncio.to_thread(processor.get_user_budgets)
            
            # Wait for all data concurrently
            summary, goals, budgets = await asyncio.gather(summary_task, goals_task, budgets_task)
            
            # Calculate goals summary
            goals_summary = None
            if goals:                  
                active_goals = [g for g in goals if g["status"] == "active"]
                achieved_goals = [g for g in goals if g["status"] == "achieved"]
                total_allocated = sum(g["current_amount"] for g in active_goals)
                
                # Group goals by currency
                goals_by_currency = {}
                for goal in goals:
                    curr = goal.get('currency', 'usd')
                    if curr not in goals_by_currency:
                        goals_by_currency[curr] = []
                    goals_by_currency[curr].append(goal)
                
                goals_summary = {
                    "total_goals": len(goals),
                    "active_goals": len(active_goals),
                    "achieved_goals": len(achieved_goals),
                    "total_allocated": total_allocated,
                    "goals_by_currency": goals_by_currency
                }
            
            # Calculate budgets summary (NEW)
            budgets_summary = None
            if budgets:
                # Group budgets by currency
                budgets_by_currency = {}
                for budget in budgets:
                    curr = budget.get('currency', 'usd')
                    if curr not in budgets_by_currency:
                        budgets_by_currency[curr] = {
                            'budgets': [],
                            'active_count': 0,
                            'total_allocated': 0,
                            'total_spent': 0,
                            'remaining': 0,
                            'percentage_used': 0
                        }
                    
                    budgets_by_currency[curr]['budgets'].append(budget)
                    budgets_by_currency[curr]['active_count'] += 1
                    budgets_by_currency[curr]['total_allocated'] += budget['total_budget']
                    budgets_by_currency[curr]['total_spent'] += budget['total_spent']
                
                # Calculate remaining and percentage for each currency
                for curr, data in budgets_by_currency.items():
                    data['remaining'] = data['total_allocated'] - data['total_spent']
                    data['percentage_used'] = (data['total_spent'] / data['total_allocated'] * 100) if data['total_allocated'] > 0 else 0
                
                budgets_summary = {
                    "total_budgets": len(budgets),
                    "active_budgets": len(budgets),
                    "budgets_by_currency": budgets_by_currency
                }
            
            if summary.get("message") and not goals and not budgets:
                yield "I don't have access to your financial data yet. Please add some transactions, goals, or budgets first!", None # ✅ FIXED
                return
            
            # Get relevant context
            context = ""
            # Run vector store creation/fetching in thread (Heavy CPU/Embedding)
            vector_store = await asyncio.to_thread(self._get_or_create_vector_store, user_id)
            
            if vector_store:
                try:
                    # Detect query type
                    temporal_keywords = ["latest", "last", "recent", "newest", "today", "yesterday", "this week"]
                    goal_keywords = ["goal", "save", "saving", "target", "progress", "achieve", "reached"]
                    budget_keywords = ["budget", "spending", "spend", "expense", "limit", "exceeded", "remaining"]  # NEW
                    
                    is_temporal = any(keyword in message.lower() for keyword in temporal_keywords)
                    is_goal_query = any(keyword in message.lower() for keyword in goal_keywords)
                    is_budget_query = any(keyword in message.lower() for keyword in budget_keywords)  # NEW
                    
                    # Adjust retrieval strategy
                    k_value = 12 if (is_temporal or is_goal_query or is_budget_query) else 6
                    
                    retriever = vector_store.as_retriever(
                        search_kwargs={"k": k_value}
                    )            
                    # Run the retrieval search in a thread
                    relevant_docs = await asyncio.to_thread(retriever.invoke, message)
                    
                    # Prioritize important documents
                    if is_temporal or is_goal_query or is_budget_query:  # NEW
                        priority_docs = [d for d in relevant_docs if d.metadata.get("priority") in ["critical", "high"]]
                        other_docs = [d for d in relevant_docs if d.metadata.get("priority") not in ["critical", "high"]]
                        relevant_docs = priority_docs + other_docs
                        
                        if is_goal_query:
                            print(f"🎯 Goal query detected - prioritized goals data")
                        if is_temporal:
                            print(f"📅 Temporal query detected - prioritized chronological index")
                        if is_budget_query:  # NEW
                            print(f"📊 Budget query detected - prioritized budgets data")
                    
                    context = "\n\n".join([doc.page_content for doc in relevant_docs])
                    
                except Exception as e:
                    print(f"❌ Error retrieving documents: {e}")
                    context = json.dumps(summary, indent=2)
            
            # Prepare chat history
            history_text = ""
            if chat_history:
                for msg in chat_history[-4:]:
                    role = "You" if msg.get("role") == "user" else "Assistant"
                    history_text += f"\n{role}: {msg.get('content', '')}"
            
            # Get today's date
            today = datetime.now(timezone.utc).strftime("%A, %B %d, %Y")
            
            # Build prompts with response style
            system_prompt = self._build_system_prompt(today, response_style)
            
            user_prompt = self._build_user_prompt(user, summary, goals_summary, budgets_summary, context, history_text, message, today)
            
            # Stream response
            if not self.openai_api_key:
                yield "AI service is not available. OpenAI API key not configured."
                return
            
            from openai import AsyncOpenAI
            client = AsyncOpenAI(api_key=self.openai_api_key)
            
            
            # Adjust temperature based on style
            temperature_map = {
                "normal": 0.3,
                "concise": 0.2,  # More deterministic for brevity
                "explanatory": 0.4  # Slightly more creative for explanations
            }
            
            # --- CHANGED SECTION STARTS HERE ---
            
            stream = await client.chat.completions.create(
                model=self.gpt_model,
                messages=[
                    {"role": "system", "content": system_prompt}, # Ensure you have system_prompt var
                    {"role": "user", "content": user_prompt}      # Ensure you have user_prompt var
                ],
                temperature=temperature_map.get(response_style, 0.3),
                max_tokens=1000,
                stream=True,
                stream_options={"include_usage": True}  # REQUIRED for usage tracking
            )

            final_usage_data = None
            
            async for chunk in stream:
                # 1. Capture Usage (usually in the last chunk)
                if hasattr(chunk, 'usage') and chunk.usage is not None:
                    final_usage_data = {
                        'input_tokens': chunk.usage.prompt_tokens,
                        'output_tokens': chunk.usage.completion_tokens,
                        'total_tokens': chunk.usage.total_tokens,
                        'model_name': self.gpt_model
                    }
                
                # 2. Capture Content
                if chunk.choices and chunk.choices[0].delta.content:
                    content = chunk.choices[0].delta.content
                    yield content, None

            # 3. Yield final usage packet
            yield "", final_usage_data
            
        except Exception as e:
            print(f"❌ Streaming chat error: {str(e)}")
            yield f"I encountered an error: {str(e)}", None
            
# Global chatbot instance
try:
    financial_chatbot = FinancialChatbot()
    print("✅ Financial chatbot initialized successfully with GPT-4 + RAG + Goals")
except Exception as e:
    print(f"❌ Failed to initialize financial chatbot: {e}")
    financial_chatbot = None