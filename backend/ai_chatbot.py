import os
import json
from typing import List, Dict, Any, Optional
from datetime import datetime, timedelta, timezone

from langchain_openai import OpenAIEmbeddings
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_community.vectorstores import Chroma
from langchain.schema import Document

from database import transactions_collection, users_collection
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
        summary = self.get_financial_summary()
        documents = []
        
        # === CRITICAL: CHRONOLOGICAL INDEX ===
        # This is THE MOST IMPORTANT document for "latest/recent" queries
        chronological_text = "╔══════════════════════════════════════════════════════╗\n"
        chronological_text += "║   TRANSACTION TIMELINE - NEWEST TO OLDEST          ║\n"
        chronological_text += "╚══════════════════════════════════════════════════════╝\n\n"
        chronological_text += "⚠️ IMPORTANT: The transactions below are sorted NEWEST FIRST.\n"
        chronological_text += "When asked about 'latest', 'recent', 'last', or 'newest' - Transaction #1 is the MOST RECENT.\n\n"
        
        for idx, t in enumerate(transactions[:25], 1):  # Top 25 most recent
            date_obj = ensure_utc_datetime(t["date"])
            days_ago = (datetime.now(timezone.utc) - date_obj).days
            
            # Visual indicator for very recent transactions
            recency_indicator = "🔴 TODAY" if days_ago == 0 else f"📅 {days_ago} days ago"
            
            chronological_text += f"═══ Transaction #{idx} ({recency_indicator}) ═══\n"
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
        summary_text = "╔══════════════════════════════════════════════════════╗\n"
        summary_text += "║              FINANCIAL SUMMARY                       ║\n"
        summary_text += "╚══════════════════════════════════════════════════════╝\n\n"
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
            
            daily_text = f"═══ {date_obj.strftime('%A, %B %d, %Y')} ({days_ago} days ago) ═══\n\n"
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
            category_text = f"═══ Category: {category} ═══\n\n"
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
        
        print(f"✅ Created {len(documents)} optimized documents for GPT-4")
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
        
        # Use GPT-4o-mini for best balance of cost/performance
        # Upgrade to "gpt-4o" or "gpt-4-turbo" if you need even better accuracy
        self.gpt_model = "gpt-4o-mini"
    
    def _get_or_create_vector_store(self, user_id: str) -> Chroma:
        """Get or create vector store for user"""
        if user_id not in self.user_vector_stores:
            processor = FinancialDataProcessor(user_id)
            documents = processor.create_financial_documents()
            
            if not documents or not self.embeddings:
                return None
            
            try:
                # Keep chronological index intact, split others carefully
                split_documents = []
                for doc in documents:
                    if doc.metadata.get("type") == "chronological_index":
                        # NEVER split the chronological index
                        split_documents.append(doc)
                    else:
                        # Split other documents
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
        """Build enhanced system prompt for GPT-4"""
        return f"""You are Flow Finance AI, an expert personal finance assistant with complete access to the user's transaction history.

📅 Today's date: {today}

Your capabilities:
- Answer questions about transactions with precision
- Provide spending insights and financial advice
- Identify patterns and trends
- Help users understand their finances

🎯 CRITICAL RULES FOR ACCURACY:

1. TEMPORAL QUERIES ("latest", "recent", "last", "newest"):
   - The data includes a CHRONOLOGICAL INDEX sorted NEWEST → OLDEST
   - Transaction #1 in that index is ALWAYS the most recent
   - Look for visual indicators like "🔴 TODAY" or "days ago"
   - NEVER confuse older transactions with newer ones

2. DATE ACCURACY:
   - Today is {today}
   - Verify dates carefully before answering
   - Use the "days ago" information as a guide

3. RESPONSE STYLE:
   - Be conversational and friendly
   - Format money as $X.XX
   - Include specific dates when relevant
   - If unsure about something, say so honestly
   - Never fabricate transaction details

4. PRIORITIZATION:
   - For "latest/recent" queries, ALWAYS check the chronological index FIRST
   - The chronological index is your source of truth for recency

Remember: Accuracy is more important than speed. Double-check dates!"""
    
    def _build_user_prompt(self, user: Dict, summary: Dict, context: str, history_text: str, message: str, today: str) -> str:
        """Build comprehensive user prompt"""
        return f"""User Profile:
Name: {user.get('name', 'User')}
Today: {today}

Quick Overview:
💰 Balance: ${summary.get('balance', 0):.2f}
📈 Income: ${summary.get('total_inflow', 0):.2f}
📉 Expenses: ${summary.get('total_outflow', 0):.2f}

═══════════════════════════════════════════════════════
                    FINANCIAL DATA
═══════════════════════════════════════════════════════

{context}

{f"═══════════════════════════════════════════════════════\n                CONVERSATION HISTORY\n═══════════════════════════════════════════════════════{history_text}" if history_text else ""}

═══════════════════════════════════════════════════════
                    USER QUESTION
═══════════════════════════════════════════════════════

{message}

Please provide an accurate, helpful answer based on the financial data above."""
    
    async def stream_chat(self, user_id: str, message: str, chat_history: Optional[List[Dict]] = None):
        """Stream chat response using GPT-4 with enhanced RAG"""
        try:
            user = users_collection.find_one({"_id": user_id})
            if not user:
                yield "User not found. Please log in again."
                return
            
            processor = FinancialDataProcessor(user_id)
            summary = processor.get_financial_summary()
            
            if summary.get("message"):
                yield "I don't have access to your financial data yet. Please add some transactions first!"
                return
            
            # Get relevant context
            context = ""
            vector_store = self._get_or_create_vector_store(user_id)
            
            if vector_store:
                try:
                    # Determine if this is a temporal query
                    temporal_keywords = ["latest", "last", "recent", "newest", "today", "yesterday", "this week"]
                    is_temporal = any(keyword in message.lower() for keyword in temporal_keywords)
                    
                    # Fetch more documents for temporal queries to ensure chronological index is included
                    k_value = 10 if is_temporal else 6
                    
                    retriever = vector_store.as_retriever(
                        search_kwargs={"k": k_value}
                    )
                    relevant_docs = retriever.invoke(message)
                    
                    # For temporal queries, ensure chronological index is at the top
                    if is_temporal:
                        chrono_docs = [d for d in relevant_docs if d.metadata.get("type") == "chronological_index"]
                        other_docs = [d for d in relevant_docs if d.metadata.get("type") != "chronological_index"]
                        relevant_docs = chrono_docs + other_docs
                        print(f"📅 Temporal query detected - prioritized chronological index")
                    
                    context = "\n\n".join([doc.page_content for doc in relevant_docs])
                    
                except Exception as e:
                    print(f"❌ Error retrieving documents: {e}")
                    # Fallback to summary
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
            user_prompt = self._build_user_prompt(user, summary, context, history_text, message, today)
            
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
                temperature=0.1,
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


# Global chatbot instance
try:
    financial_chatbot = FinancialChatbot()
    print("✅ Financial chatbot initialized successfully with GPT-4 + RAG")
except Exception as e:
    print(f"❌ Failed to initialize financial chatbot: {e}")
    financial_chatbot = None