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
        """Create optimized documents for vector store"""
        transactions = self.get_user_transactions()
        summary = self.get_financial_summary()
        documents = []
        
        # Summary document
        summary_text = f"""
Financial Summary:
- Balance: ${summary.get('balance', 0):.2f}
- Total Income: ${summary.get('total_inflow', 0):.2f}
- Total Expenses: ${summary.get('total_outflow', 0):.2f}
- Transactions: {summary.get('total_transactions', 0)}
- Average Transaction: ${summary.get('avg_transaction_amount', 0):.2f}
- Period: {summary.get('date_range', {}).get('from', 'N/A')} to {summary.get('date_range', {}).get('to', 'N/A')}

Top Income: {json.dumps(summary.get('top_inflow_categories', {}), indent=2)}
Top Expenses: {json.dumps(summary.get('top_outflow_categories', {}), indent=2)}
Monthly Trends: {json.dumps(summary.get('monthly_trends', {}), indent=2)}
"""
        documents.append(Document(
            page_content=summary_text,
            metadata={"type": "summary", "user_id": self.user_id}
        ))
        
        # Group transactions by date to reduce document count
        transactions_by_date = {}
        for t in transactions:
            date_str = get_date_only(t["date"])
            if date_str not in transactions_by_date:
                transactions_by_date[date_str] = []
            transactions_by_date[date_str].append(t)
        
        # Create daily summary documents (more efficient than per-transaction)
        for date_str, daily_transactions in transactions_by_date.items():
            date_obj = ensure_utc_datetime(daily_transactions[0]["date"])
            daily_inflow = sum(t["amount"] for t in daily_transactions if t["type"] == "inflow")
            daily_outflow = sum(t["amount"] for t in daily_transactions if t["type"] == "outflow")
            
            daily_text = f"""
Date: {date_obj.strftime('%A, %B %d, %Y')} ({date_str})
Daily Summary: {len(daily_transactions)} transactions, +${daily_inflow:.2f} income, -${daily_outflow:.2f} expenses

Transactions:
"""
            for t in daily_transactions:
                daily_text += f"- {t['type'].title()}: ${t['amount']:.2f} - {t['main_category']} > {t['sub_category']}"
                if t.get("description"):
                    daily_text += f" - {t['description']}"
                daily_text += "\n"
            
            documents.append(Document(
                page_content=daily_text,
                metadata={
                    "type": "daily_summary",
                    "user_id": self.user_id,
                    "date": date_str,
                    "transaction_count": len(daily_transactions)
                }
            ))
        
        # Category summaries (only for top categories to reduce noise)
        all_categories = {}
        for t in transactions:
            cat_key = f"{t['main_category']} > {t['sub_category']}"
            if cat_key not in all_categories:
                all_categories[cat_key] = {"transactions": [], "total": 0, "type": t["type"]}
            all_categories[cat_key]["transactions"].append(t)
            all_categories[cat_key]["total"] += t["amount"]
        
        # Only document top 10 categories
        top_categories = sorted(all_categories.items(), key=lambda x: x[1]["total"], reverse=True)[:10]
        
        for category, data in top_categories:
            category_text = f"""
Category: {category}
Type: {data["type"].title()}
Total: ${data["total"]:.2f}
Transactions: {len(data["transactions"])}
Average: ${data["total"] / len(data["transactions"]):.2f}

Recent examples:
"""
            for t in data["transactions"][-3:]:  # Only 3 most recent
                date_obj = ensure_utc_datetime(t["date"])
                category_text += f"- {date_obj.strftime('%b %d')}: ${t['amount']:.2f}"
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
        
        print(f"Created {len(documents)} optimized documents")
        return documents


class FinancialChatbot:
    """AI Chatbot with RAG for financial data"""
    
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
            chunk_size=1000,
            chunk_overlap=100,
            separators=["\n\n", "\n", " ", ""]
        )
        self.user_vector_stores = {}
    
    def _get_or_create_vector_store(self, user_id: str) -> Chroma:
        """Get or create vector store for user"""
        if user_id not in self.user_vector_stores:
            processor = FinancialDataProcessor(user_id)
            documents = processor.create_financial_documents()
            
            if not documents or not self.embeddings:
                return None
            
            try:
                split_documents = self.text_splitter.split_documents(documents)
                vector_store = Chroma.from_documents(
                    documents=split_documents,
                    embedding=self.embeddings,
                    collection_name=f"user_{user_id}_{int(datetime.now().timestamp())}"
                )
                self.user_vector_stores[user_id] = vector_store
                print(f"Created vector store with {len(split_documents)} chunks")
            except Exception as e:
                print(f"Error creating vector store: {e}")
                return None
        
        return self.user_vector_stores[user_id]
    
    def refresh_user_data(self, user_id: str):
        """Refresh user's financial data in vector store"""
        # Clean up old vector store to prevent memory leak
        if user_id in self.user_vector_stores:
            try:
                self.user_vector_stores[user_id].delete_collection()
            except:
                pass
            del self.user_vector_stores[user_id]
        
        self._get_or_create_vector_store(user_id)
    
    def _build_system_prompt(self, today: str) -> str:
        """Build concise system prompt"""
        return f"""You are Flow Finance AI, a personal finance assistant with access to the user's transaction data.

Today's date: {today}

Your role:
- Answer questions about spending, income, and financial patterns
- Provide specific amounts, categories, and dates from actual data
- Offer practical financial advice based on their real transactions
- Be conversational and helpful

Important:
- Only use information from the provided financial data
- Format money as $X.XX
- If data is unavailable for a time period, say so clearly
- Never fabricate transaction details"""
    
    def _build_user_prompt(self, user: Dict, summary: Dict, context: str, history_text: str, message: str, today: str) -> str:
        """Build user prompt with essential data"""
        return f"""User: {user.get('name', 'User')}
Today: {today}

Financial Overview:
- Balance: ${summary.get('balance', 0):.2f}
- Income: ${summary.get('total_inflow', 0):.2f}
- Expenses: ${summary.get('total_outflow', 0):.2f}

Relevant Financial Data:
{context}

{f"Recent Conversation:{history_text}" if history_text else ""}

Question: {message}"""
    
    async def stream_chat(self, user_id: str, message: str, chat_history: Optional[List[Dict]] = None):
        """Stream chat response with user's financial data"""
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
                    retriever = vector_store.as_retriever(search_kwargs={"k": 5})
                    relevant_docs = retriever.invoke(message)
                    context = "\n\n".join([doc.page_content for doc in relevant_docs])
                except Exception as e:
                    print(f"Error retrieving documents: {e}")
                    context = json.dumps(summary, indent=2)
            
            # Prepare chat history (only last 2 exchanges)
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
                model="gpt-3.5-turbo",
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt}
                ],
                temperature=0.1,
                max_tokens=800,
                stream=True
            )
            
            async for chunk in stream:
                if chunk.choices[0].delta.content is not None:
                    yield chunk.choices[0].delta.content
            
        except Exception as e:
            print(f"Streaming chat error: {str(e)}")
            import traceback
            traceback.print_exc()
            yield f"I encountered an error: {str(e)}"
    
    def get_financial_insights(self, user_id: str) -> str:
        """Generate automatic financial insights"""
        try:
            processor = FinancialDataProcessor(user_id)
            summary = processor.get_financial_summary()
            
            if summary.get("message"):
                return "I don't have enough financial data to provide insights yet. Please add some transactions first!"
            
            today = datetime.now(timezone.utc).strftime("%A, %B %d, %Y")
            
            system_prompt = f"""You are Flow Finance AI, a financial analyst.
Today: {today}

Provide 4-5 key insights and actionable recommendations based on the user's financial data.
Be specific, friendly, and focus on practical advice."""
            
            user_prompt = f"""Analyze this financial data:

Balance: ${summary.get('balance', 0):.2f}
Income: ${summary.get('total_inflow', 0):.2f}
Expenses: ${summary.get('total_outflow', 0):.2f}
Transactions: {summary.get('total_transactions', 0)}
Period: {summary.get('date_range', {}).get('from', 'N/A')} to {summary.get('date_range', {}).get('to', 'N/A')}

Top Income: {json.dumps(summary.get('top_inflow_categories', {}), indent=2)}
Top Expenses: {json.dumps(summary.get('top_outflow_categories', {}), indent=2)}
Monthly Trends: {json.dumps(summary.get('monthly_trends', {}), indent=2)}"""
            
            if not self.openai_api_key:
                return "AI service is not available."
            
            from openai import OpenAI
            client = OpenAI(api_key=self.openai_api_key)
            
            response = client.chat.completions.create(
                model="gpt-3.5-turbo",
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt}
                ],
                temperature=0.1,
                max_tokens=1000
            )
            
            return response.choices[0].message.content
            
        except Exception as e:
            print(f"Insights error: {str(e)}")
            return "Unable to generate insights at this time."


# Global chatbot instance
try:
    financial_chatbot = FinancialChatbot()
    print("Financial chatbot initialized successfully")
except Exception as e:
    print(f"Failed to initialize financial chatbot: {e}")
    financial_chatbot = None