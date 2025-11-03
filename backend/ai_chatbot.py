import os
import json
from typing import List, Dict, Any, Optional
from datetime import datetime, timedelta, timezone

from langchain_openai import OpenAIEmbeddings
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_community.vectorstores import Chroma
from langchain_core.documents import Document

from database import transactions_collection, users_collection, goals_collection
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
        
    def get_user_transactions(self, days_back: Optional[int] = None) -> List[Dict]:
        """Get user transactions from last N days, or all if days_back is None"""
        query = {"user_id": self.user_id}
        if days_back is not None:
            cutoff_date = datetime.now(timezone.utc) - timedelta(days=days_back)
            query["date"] = {"$gte": cutoff_date}
        
        try:
            transactions = list(transactions_collection.find(query).sort("date", -1))
            print(f"Found {len(transactions)} transactions for user {self.user_id}")
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
    
    def get_financial_summary(self) -> Dict[str, Any]:
        """Generate comprehensive financial summary"""
        transactions = self.get_user_transactions()
        
        if not transactions:
            return {"message": "No financial data available"}
        
        total_inflow = sum(t["amount"] for t in transactions if t["type"] == "inflow")
        total_outflow = sum(t["amount"] for t in transactions if t["type"] == "outflow")
        
        inflow_by_category = {}
        outflow_by_category = {}
        monthly_data = {}
        
        for t in transactions:
            category_key = f"{t['main_category']} > {t['sub_category']}"
            if t["type"] == "inflow":
                inflow_by_category[category_key] = inflow_by_category.get(category_key, 0) + t["amount"]
            else:
                outflow_by_category[category_key] = outflow_by_category.get(category_key, 0) + t["amount"]
            
            date_obj = ensure_utc_datetime(t["date"])
            month_key = date_obj.strftime("%Y-%m")
            if month_key not in monthly_data:
                monthly_data[month_key] = {"inflow": 0, "outflow": 0}
            monthly_data[month_key][t["type"]] += t["amount"]
        
        all_dates = [ensure_utc_datetime(t["date"]) for t in transactions]
        
        return {
            "total_transactions": len(transactions),
            "balance": total_inflow - total_outflow,
            "total_inflow": total_inflow,
            "total_outflow": total_outflow,
            "top_inflow_categories": dict(sorted(inflow_by_category.items(), key=lambda x: x[1], reverse=True)[:10]),
            "top_outflow_categories": dict(sorted(outflow_by_category.items(), key=lambda x: x[1], reverse=True)[:10]),
            "monthly_trends": monthly_data,
            "avg_transaction_amount": sum(t["amount"] for t in transactions) / len(transactions),
            "date_range": {
                "from": min(all_dates).isoformat(),
                "to": max(all_dates).isoformat()
            }
        }
    
    def create_financial_documents(self) -> List[Document]:
        """Create optimized documents for GPT-4 with clear chronological structure"""
        transactions = self.get_user_transactions()
        goals = self.get_user_goals()
        summary = self.get_financial_summary()
        documents = []
        
        # === FINANCIAL GOALS OVERVIEW ===
        if goals:
            goals_text = "╔═══════════════════════════════════════════════════╗\n"
            goals_text += "║           FINANCIAL GOALS OVERVIEW                ║\n"
            goals_text += "╚═══════════════════════════════════════════════════╝\n\n"
            
            active_goals = [g for g in goals if g["status"] == "active"]
            achieved_goals = [g for g in goals if g["status"] == "achieved"]
            
            total_allocated = sum(g["current_amount"] for g in active_goals)
            total_target = sum(g["target_amount"] for g in active_goals)
            
            goals_text += f"📊 Summary:\n"
            goals_text += f"  • Total Goals: {len(goals)}\n"
            goals_text += f"  • Active Goals: {len(active_goals)}\n"
            goals_text += f"  • Achieved Goals: {len(achieved_goals)}\n"
            goals_text += f"  • Total Allocated: ${total_allocated:.2f}\n"
            goals_text += f"  • Total Target (Active): ${total_target:.2f}\n"
            goals_text += f"  • Overall Progress: {(total_allocated / total_target * 100) if total_target > 0 else 0:.1f}%\n\n"
            
            if active_goals:
                goals_text += "🎯 ACTIVE GOALS:\n\n"
                for idx, g in enumerate(active_goals, 1):
                    progress = (g["current_amount"] / g["target_amount"] * 100) if g["target_amount"] > 0 else 0
                    remaining = g["target_amount"] - g["current_amount"]
                    
                    goals_text += f"──── Goal #{idx}: {g['name']} ────\n"
                    goals_text += f"Type: {g['goal_type'].replace('_', ' ').title()}\n"
                    goals_text += f"Target: ${g['target_amount']:.2f}\n"
                    goals_text += f"Current: ${g['current_amount']:.2f}\n"
                    goals_text += f"Remaining: ${remaining:.2f}\n"
                    goals_text += f"Progress: {progress:.1f}%\n"
                    
                    if g.get("target_date"):
                        target_date = ensure_utc_datetime(g["target_date"])
                        days_remaining = (target_date - datetime.now(timezone.utc)).days
                        goals_text += f"Target Date: {target_date.strftime('%B %d, %Y')}\n"
                        goals_text += f"Days Remaining: {days_remaining}\n"
                        
                        if days_remaining > 0 and remaining > 0:
                            daily_needed = remaining / days_remaining
                            goals_text += f"Daily Savings Needed: ${daily_needed:.2f}\n"
                    
                    goals_text += f"Created: {ensure_utc_datetime(g['created_at']).strftime('%b %d, %Y')}\n\n"
            
            if achieved_goals:
                goals_text += "🏆 ACHIEVED GOALS:\n\n"
                for idx, g in enumerate(achieved_goals, 1):
                    goals_text += f"✓ {g['name']}: ${g['target_amount']:.2f}\n"
                    if g.get("achieved_at"):
                        achieved_date = ensure_utc_datetime(g["achieved_at"])
                        goals_text += f"  Achieved: {achieved_date.strftime('%b %d, %Y')}\n"
                    goals_text += "\n"
            
            documents.append(Document(
                page_content=goals_text,
                metadata={
                    "type": "goals_overview",
                    "user_id": self.user_id,
                    "priority": "high"
                }
            ))
        
        # === CRITICAL: CHRONOLOGICAL INDEX ===
        chronological_text = "╔═══════════════════════════════════════════════════╗\n"
        chronological_text += "║   TRANSACTION TIMELINE - NEWEST TO OLDEST          ║\n"
        chronological_text += "╚═══════════════════════════════════════════════════╝\n\n"
        chronological_text += "⚠️ IMPORTANT: The transactions below are sorted NEWEST FIRST.\n"
        chronological_text += "When asked about 'latest', 'recent', 'last', or 'newest' - Transaction #1 is the MOST RECENT.\n\n"
        
        for idx, t in enumerate(transactions[:25], 1):
            date_obj = ensure_utc_datetime(t["date"])
            days_ago = (datetime.now(timezone.utc) - date_obj).days
            
            recency_indicator = "🔴 TODAY" if days_ago == 0 else f"📅 {days_ago} days ago"
            
            chronological_text += f"─── Transaction #{idx} ({recency_indicator}) ───\n"
            chronological_text += f"Date: {date_obj.strftime('%A, %B %d, %Y')} ({get_date_only(t['date'])})\n"
            chronological_text += f"Type: {t['type'].title()}\n"
            chronological_text += f"Amount: ${t['amount']:.2f}\n"
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
        
        # === FINANCIAL SUMMARY ===
        summary_text = "╔═══════════════════════════════════════════════════╗\n"
        summary_text += "║              FINANCIAL SUMMARY                       ║\n"
        summary_text += "╚═══════════════════════════════════════════════════╝\n\n"
        
        # Add goals impact to summary
        if goals:
            active_goals = [g for g in goals if g["status"] == "active"]
            total_allocated = sum(g["current_amount"] for g in active_goals)
            available_balance = summary.get('balance', 0) - total_allocated
            
            summary_text += f"💰 Balance Overview:\n"
            summary_text += f"Total Balance: ${summary.get('balance', 0):.2f}\n"
            summary_text += f"Allocated to Goals: ${total_allocated:.2f}\n"
            summary_text += f"Available Balance: ${available_balance:.2f}\n\n"
        else:
            summary_text += f"Current Balance: ${summary.get('balance', 0):.2f}\n"
        
        summary_text += f"Total Income: ${summary.get('total_inflow', 0):.2f}\n"
        summary_text += f"Total Expenses: ${summary.get('total_outflow', 0):.2f}\n"
        summary_text += f"Total Transactions: {summary.get('total_transactions', 0)}\n"
        summary_text += f"Average Transaction: ${summary.get('avg_transaction_amount', 0):.2f}\n"
        summary_text += f"Data Period: {summary.get('date_range', {}).get('from', 'N/A')[:10]} to {summary.get('date_range', {}).get('to', 'N/A')[:10]}\n\n"
        
        summary_text += "Top Income Sources:\n"
        for cat, amount in list(summary.get('top_inflow_categories', {}).items())[:5]:
            summary_text += f"  • {cat}: ${amount:.2f}\n"
        
        summary_text += "\nTop Expense Categories:\n"
        for cat, amount in list(summary.get('top_outflow_categories', {}).items())[:5]:
            summary_text += f"  • {cat}: ${amount:.2f}\n"
        
        documents.append(Document(
            page_content=summary_text,
            metadata={
                "type": "summary",
                "user_id": self.user_id
            }
        ))
        
        # === INDIVIDUAL GOAL DETAILS ===
        for goal in goals:
            goal_text = f"╔═══════════════════════════════════════════════════╗\n"
            goal_text += f"║   GOAL: {goal['name'][:40].center(40)}   ║\n"
            goal_text += f"╚═══════════════════════════════════════════════════╝\n\n"
            
            progress = (goal["current_amount"] / goal["target_amount"] * 100) if goal["target_amount"] > 0 else 0
            remaining = goal["target_amount"] - goal["current_amount"]
            
            goal_text += f"Status: {goal['status'].upper()}\n"
            goal_text += f"Type: {goal['goal_type'].replace('_', ' ').title()}\n"
            goal_text += f"Target Amount: ${goal['target_amount']:.2f}\n"
            goal_text += f"Current Amount: ${goal['current_amount']:.2f}\n"
            goal_text += f"Remaining: ${remaining:.2f}\n"
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
                        goal_text += f"  • Daily: ${daily_needed:.2f}\n"
                        goal_text += f"  • Weekly: ${weekly_needed:.2f}\n"
                        goal_text += f"  • Monthly: ${monthly_needed:.2f}\n"
            
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
                    "goal_status": goal["status"]
                }
            ))
        
        # === DAILY SUMMARIES (Last 30 days only) ===
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
            daily_inflow = sum(t["amount"] for t in daily_transactions if t["type"] == "inflow")
            daily_outflow = sum(t["amount"] for t in daily_transactions if t["type"] == "outflow")
            
            daily_text = f"─── {date_obj.strftime('%A, %B %d, %Y')} ({days_ago} days ago) ───\n\n"
            daily_text += f"Daily Summary: {len(daily_transactions)} transactions\n"
            daily_text += f"  Income: +${daily_inflow:.2f}\n"
            daily_text += f"  Expenses: -${daily_outflow:.2f}\n"
            daily_text += f"  Net: ${daily_inflow - daily_outflow:.2f}\n\n"
            daily_text += "Transactions:\n"
            
            for t in daily_transactions:
                daily_text += f"  • {t['type'].title()}: ${t['amount']:.2f} - {t['main_category']} > {t['sub_category']}"
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
        
        # === CATEGORY INSIGHTS ===
        all_categories = {}
        for t in transactions:
            cat_key = f"{t['main_category']} > {t['sub_category']}"
            if cat_key not in all_categories:
                all_categories[cat_key] = {"transactions": [], "total": 0, "type": t["type"]}
            all_categories[cat_key]["transactions"].append(t)
            all_categories[cat_key]["total"] += t["amount"]
        
        for category, data in sorted(all_categories.items(), key=lambda x: x[1]["total"], reverse=True)[:8]:
            category_text = f"─── Category: {category} ───\n\n"
            category_text += f"Type: {data['type'].title()}\n"
            category_text += f"Total: ${data['total']:.2f}\n"
            category_text += f"Transactions: {len(data['transactions'])}\n"
            category_text += f"Average: ${data['total'] / len(data['transactions']):.2f}\n\n"
            category_text += "Recent Examples:\n"
            
            for t in data['transactions'][:5]:
                date_obj = ensure_utc_datetime(t["date"])
                category_text += f"  • {date_obj.strftime('%b %d, %Y')}: ${t['amount']:.2f}"
                if t.get("description"):
                    category_text += f" - {t['description']}"
                category_text += "\n"
            
            documents.append(Document(
                page_content=category_text,
                metadata={
                    "type": "category",
                    "user_id": self.user_id,
                    "category": category
                }
            ))
        
        print(f"✅ Created {len(documents)} optimized documents for GPT-4 (including {len(goals)} goals)")
        return documents


class FinancialChatbot:
    """AI Chatbot with GPT-4 + Optimized RAG (Recommended Approach)"""
    
    def __init__(self):
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
        
        self.gpt_model = "gpt-4o-mini"
    
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
    
    def _build_system_prompt(self, today: str) -> str:
        """Build enhanced system prompt for GPT-4 with Myanmar language support"""
        return f"""You are Flow Finance AI, an expert personal finance assistant with complete access to the user's transaction history and financial goals.

    📅 Today's date: {today}

    🌏 LANGUAGE CAPABILITY:
    - You are FLUENT in both Myanmar (Burmese) and English language
    - Detect the user's language automatically from their message
    - If the user writes in Myanmar, respond ENTIRELY in Myanmar
    - If the user writes in English, respond ENTIRELY in English
    - Maintain consistency - don't mix languages unless the user does
    - Use natural, conversational Myanmar that feels native and friendly
    - For financial terms in Myanmar, use commonly understood terms (e.g., "ငွေ" for money, "စုငွေ" for savings, "ရည်မှန်းချက်" for goals)

    Your capabilities:
    - Answer questions about transactions with precision
    - Provide insights on financial goals and progress
    - Track goal achievements and suggest strategies
    - Calculate savings needed to reach goals
    - Identify spending patterns that affect goal progress
    - Provide spending insights and financial advice
    - Help users understand their finances holistically

    🎯 CRITICAL RULES FOR ACCURACY:

    1. TEMPORAL QUERIES ("latest", "recent", "last", "newest" or Myanmar: "နောက်ဆုံး", "မကြာသေးခင်က", "လတ်တလော"):
    - The data includes a CHRONOLOGICAL INDEX sorted NEWEST → OLDEST
    - Transaction #1 in that index is ALWAYS the most recent
    - Look for visual indicators like "🔴 TODAY" or "days ago"
    - NEVER confuse older transactions with newer ones

    2. GOALS AWARENESS:
    - Always check the GOALS OVERVIEW for the user's financial goals
    - When discussing balance, consider both total balance and available balance (after goal allocations)
    - Suggest how spending changes could help achieve goals faster
    - Celebrate progress and provide encouragement
    - Be specific about goal timelines and required savings rates

    3. DATE ACCURACY:
    - Today is {today}
    - Verify dates carefully before answering
    - Use the "days ago" information as a guide

    4. RESPONSE STYLE:
    - Answer the Question Directly
    - Get straight to what they asked
    - Don't add extra information unless it's truly relevant
    - Only mention related information if it directly impacts their question
    - Be Friendly, Not Chatty - Warm tone, but professional and to-the-point
    - Simple questions deserve simple answers (1-3 sentences)
    - Complex questions get thorough but focused answers
    - No filler, no unnecessary elaboration
    - Format money as $X.XX (or if in Myanmar: $X.XX ကျပ်)
    - Include specific dates when relevant
    - If unsure about something, say so honestly
    - Never fabricate transaction or goal details

    5. MYANMAR LANGUAGE SPECIFICS:
    - Use respectful Myanmar expressions naturally 
    - Keep financial advice clear and easy to understand
    - Use bullet points (•) for lists in Myanmar responses too
    - When translating amounts, keep the $ symbol but you can add context in Myanmar
    - Be warm and encouraging in Myanmar - financial discussions can be sensitive

    6. PRIORITIZATION:
    - For "latest/recent" queries, ALWAYS check the chronological index FIRST
    - For goal-related queries, check the goals overview and individual goal details
    - Consider the interplay between spending, saving, and goal progress

    Remember: Accuracy is more important than speed. Double-check dates and amounts! Respect their time. Answer what they asked, be friendly, and move on. 

    ဘာသာစကားကို သဘာဝကျကျ သုံးစွဲပါ။ (Use language naturally.)"""
    
    def _build_user_prompt(self, user: Dict, summary: Dict, goals_summary: Dict, context: str, history_text: str, message: str, today: str) -> str:
        """Build comprehensive user prompt"""
        prompt = f"""User Profile:
Name: {user.get('name', 'User')}
Today: {today}

Quick Overview:
💰 Total Balance: ${summary.get('balance', 0):.2f}
"""
        
        if goals_summary:
            prompt += f"""💎 Allocated to Goals: ${goals_summary.get('total_allocated', 0):.2f}
✨ Available Balance: ${summary.get('balance', 0) - goals_summary.get('total_allocated', 0):.2f}
🎯 Active Goals: {goals_summary.get('active_goals', 0)}
🏆 Achieved Goals: {goals_summary.get('achieved_goals', 0)}
"""
        
        prompt += f"""📈 Income: ${summary.get('total_inflow', 0):.2f}
📉 Expenses: ${summary.get('total_outflow', 0):.2f}

═══════════════════════════════════════════════════
                    FINANCIAL DATA
═══════════════════════════════════════════════════

{context}

{f"═══════════════════════════════════════════════════\n                CONVERSATION HISTORY\n═══════════════════════════════════════════════════{history_text}" if history_text else ""}

═══════════════════════════════════════════════════
                    USER QUESTION
═══════════════════════════════════════════════════

{message}

Please provide an accurate, helpful answer based on the financial data above."""
        
        return prompt
    
    async def stream_chat(self, user_id: str, message: str, chat_history: Optional[List[Dict]] = None):
        """Stream chat response using GPT-4 with enhanced RAG"""
        try:
            user = users_collection.find_one({"_id": user_id})
            if not user:
                yield "User not found. Please log in again."
                return
            
            processor = FinancialDataProcessor(user_id)
            summary = processor.get_financial_summary()
            goals = processor.get_user_goals()
            
            # Calculate goals summary
            goals_summary = None
            if goals:
                active_goals = [g for g in goals if g["status"] == "active"]
                achieved_goals = [g for g in goals if g["status"] == "achieved"]
                total_allocated = sum(g["current_amount"] for g in active_goals)
                
                goals_summary = {
                    "total_goals": len(goals),
                    "active_goals": len(active_goals),
                    "achieved_goals": len(achieved_goals),
                    "total_allocated": total_allocated
                }
            
            if summary.get("message") and not goals:
                yield "I don't have access to your financial data yet. Please add some transactions or goals first!"
                return
            
            # Get relevant context
            context = ""
            vector_store = self._get_or_create_vector_store(user_id)
            
            if vector_store:
                try:
                    # Detect query type
                    temporal_keywords = ["latest", "last", "recent", "newest", "today", "yesterday", "this week"]
                    goal_keywords = ["goal", "save", "saving", "target", "progress", "achieve", "reached"]
                    
                    is_temporal = any(keyword in message.lower() for keyword in temporal_keywords)
                    is_goal_query = any(keyword in message.lower() for keyword in goal_keywords)
                    
                    # Adjust retrieval strategy
                    k_value = 12 if (is_temporal or is_goal_query) else 6
                    
                    retriever = vector_store.as_retriever(
                        search_kwargs={"k": k_value}
                    )
                    relevant_docs = retriever.invoke(message)
                    
                    # Prioritize important documents
                    if is_temporal or is_goal_query:
                        priority_docs = [d for d in relevant_docs if d.metadata.get("priority") in ["critical", "high"]]
                        other_docs = [d for d in relevant_docs if d.metadata.get("priority") not in ["critical", "high"]]
                        relevant_docs = priority_docs + other_docs
                        
                        if is_goal_query:
                            print(f"🎯 Goal query detected - prioritized goals data")
                        if is_temporal:
                            print(f"📅 Temporal query detected - prioritized chronological index")
                    
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
            
            # Build prompts
            system_prompt = self._build_system_prompt(today)
            user_prompt = self._build_user_prompt(user, summary, goals_summary, context, history_text, message, today)
            
            # Stream response
            if not self.openai_api_key:
                yield "AI service is not available. OpenAI API key not configured."
                return
            
            from openai import AsyncOpenAI
            client = AsyncOpenAI(api_key=self.openai_api_key)
            
            stream = await client.chat.completions.create(
                model=self.gpt_model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt}
                ],
                temperature=0.3,
                max_tokens=1000,
                stream=True
            )
            
            async for chunk in stream:
                if chunk.choices[0].delta.content is not None:
                    yield chunk.choices[0].delta.content
            
        except Exception as e:
            print(f"❌ Streaming chat error: {str(e)}")
            import traceback
            traceback.print_exc()
            yield f"I encountered an error: {str(e)}"
            
            
            
    # Add these methods to the FinancialChatbot class in ai_chatbot.py
# Place them after the stream_chat method and before the closing of the class

    async def generate_insights(self, user_id: str) -> str:
        """Generate comprehensive financial insights using GPT-4"""
        try:
            from openai import AsyncOpenAI
            
            if not self.openai_api_key:
                raise Exception("OpenAI API key not configured")
            
            # Get user data
            user = users_collection.find_one({"_id": user_id})
            if not user:
                raise Exception("User not found")
            
            processor = FinancialDataProcessor(user_id)
            summary = processor.get_financial_summary()
            goals = processor.get_user_goals()
            transactions = processor.get_user_transactions()
            
            if not transactions and not goals:
                return "Add some transactions or financial goals to get personalized insights!"
            
            # Build comprehensive data context
            context = self._build_insight_context(user, summary, goals, transactions)
            
            # System prompt for insights generation
            system_prompt = """You are Flow Finance AI, an expert financial analyst providing personalized insights.

    Your task is to analyze the user's complete financial data and generate comprehensive, actionable insights.

    INSIGHT STRUCTURE:
    Generate insights covering ALL relevant areas:

    1. **Financial Health Overview** - Current state, trends, patterns
    2. **Spending Analysis** - Where money goes, concerning patterns, opportunities
    3. **Income Analysis** - Sources, stability, growth opportunities  
    4. **Savings & Goals Progress** - Goal tracking, recommendations, timeline analysis
    5. **Budget Recommendations** - Specific, actionable advice
    6. **Future Projections** - Where they're headed, what to watch
    7. **Celebration & Encouragement** - Acknowledge wins, motivate progress

    CRITICAL RULES:
    - Be COMPREHENSIVE - cover all aspects of their finances
    - Be SPECIFIC - use actual numbers, dates, categories from their data
    - Be ACTIONABLE - give concrete steps they can take
    - Be HONEST - point out both strengths and areas for improvement
    - Be ENCOURAGING - maintain a positive, supportive tone
    - NO LIMITATIONS - analyze everything thoroughly
    - Include comparisons (month-over-month, category ratios, goal progress)
    - Identify both opportunities and risks
    - Make predictions based on current trends

    Format with clear sections using markdown:
    - Use ## for main sections
    - Use **bold** for emphasis
    - Use bullet points for lists
    - Include specific dollar amounts and percentages
    - Add emojis for visual appeal (💰 📈 📉 🎯 ⚠️ ✅ 🎉)

    Length: 800-1500 words of detailed, personalized analysis."""

            today = datetime.now(timezone.utc).strftime("%A, %B %d, %Y")
            user_prompt = f"""Today's Date: {today}

    USER FINANCIAL DATA:
    {context}

    Generate comprehensive financial insights for this user. Analyze everything thoroughly and provide actionable recommendations."""

            client = AsyncOpenAI(api_key=self.openai_api_key)
            
            response = await client.chat.completions.create(
                model=self.gpt_model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt}
                ],
                temperature=0.7,  # More creative for insights
                max_tokens=2500
            )
            
            insights = response.choices[0].message.content
            return insights
            
        except Exception as e:
            print(f"Error generating insights: {e}")
            import traceback
            traceback.print_exc()
            raise Exception(f"Failed to generate insights: {str(e)}")

    def _build_insight_context(self, user: Dict, summary: Dict, goals: List[Dict], transactions: List[Dict]) -> str:
        """Build comprehensive context for insight generation"""
        context = f"User: {user.get('name', 'User')}\n\n"
        
        # Financial Summary
        context += "=== FINANCIAL OVERVIEW ===\n"
        context += f"Total Balance: ${summary.get('balance', 0):.2f}\n"
        context += f"Total Income: ${summary.get('total_inflow', 0):.2f}\n"
        context += f"Total Expenses: ${summary.get('total_outflow', 0):.2f}\n"
        context += f"Total Transactions: {summary.get('total_transactions', 0)}\n"
        context += f"Average Transaction: ${summary.get('avg_transaction_amount', 0):.2f}\n"
        
        if summary.get('date_range'):
            context += f"Data Period: {summary['date_range'].get('from', 'N/A')[:10]} to {summary['date_range'].get('to', 'N/A')[:10]}\n"
        
        context += "\n"
        
        # Goals Summary
        if goals:
            active_goals = [g for g in goals if g["status"] == "active"]
            achieved_goals = [g for g in goals if g["status"] == "achieved"]
            total_allocated = sum(g["current_amount"] for g in active_goals)
            total_target = sum(g["target_amount"] for g in active_goals)
            
            context += "=== FINANCIAL GOALS ===\n"
            context += f"Total Goals: {len(goals)}\n"
            context += f"Active Goals: {len(active_goals)}\n"
            context += f"Achieved Goals: {len(achieved_goals)}\n"
            context += f"Total Allocated: ${total_allocated:.2f}\n"
            context += f"Total Target: ${total_target:.2f}\n"
            context += f"Overall Progress: {(total_allocated / total_target * 100) if total_target > 0 else 0:.1f}%\n\n"
            
            for goal in active_goals[:5]:  # Top 5 active goals
                progress = (goal["current_amount"] / goal["target_amount"] * 100) if goal["target_amount"] > 0 else 0
                context += f"Goal: {goal['name']}\n"
                context += f"  Target: ${goal['target_amount']:.2f}\n"
                context += f"  Current: ${goal['current_amount']:.2f}\n"
                context += f"  Progress: {progress:.1f}%\n"
                if goal.get("target_date"):
                    target_date = ensure_utc_datetime(goal["target_date"])
                    days_remaining = (target_date - datetime.now(timezone.utc)).days
                    context += f"  Days Remaining: {days_remaining}\n"
                context += "\n"
        
        # Income Analysis
        context += "=== INCOME SOURCES ===\n"
        for cat, amount in list(summary.get('top_inflow_categories', {}).items())[:10]:
            context += f"{cat}: ${amount:.2f}\n"
        context += "\n"
        
        # Expense Analysis
        context += "=== EXPENSE CATEGORIES ===\n"
        for cat, amount in list(summary.get('top_outflow_categories', {}).items())[:10]:
            context += f"{cat}: ${amount:.2f}\n"
        context += "\n"
        
        # Monthly Trends
        if summary.get('monthly_trends'):
            context += "=== MONTHLY TRENDS ===\n"
            for month, data in sorted(summary['monthly_trends'].items(), reverse=True)[:6]:
                net = data['inflow'] - data['outflow']
                context += f"{month}:\n"
                context += f"  Income: ${data['inflow']:.2f}\n"
                context += f"  Expenses: ${data['outflow']:.2f}\n"
                context += f"  Net: ${net:.2f}\n"
            context += "\n"
        
        # Recent Transactions (last 20)
        context += "=== RECENT TRANSACTIONS ===\n"
        for t in transactions[:20]:
            date_obj = ensure_utc_datetime(t["date"])
            context += f"{date_obj.strftime('%Y-%m-%d')}: {t['type']} ${t['amount']:.2f} - {t['main_category']} > {t['sub_category']}"
            if t.get('description'):
                context += f" ({t['description']})"
            context += "\n"
        
        return context


# Global chatbot instance
try:
    financial_chatbot = FinancialChatbot()
    print("✅ Financial chatbot initialized successfully with GPT-4 + RAG + Goals")
except Exception as e:
    print(f"❌ Failed to initialize financial chatbot: {e}")
    financial_chatbot = None