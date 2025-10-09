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
    
    # If it's a string, parse it
    if isinstance(dt, str):
        dt = datetime.fromisoformat(dt.replace("Z", "+00:00"))
    
    # If naive, assume UTC
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    
    # Convert to UTC if not already
    if dt.tzinfo != timezone.utc:
        dt = dt.astimezone(timezone.utc)
    
    return dt


class FinancialDataProcessor:
    """Processes user's financial data for RAG"""
    
    def __init__(self, user_id: str):
        self.user_id = user_id
        
    def get_user_transactions(self, days_back: Optional[int] = None) -> List[Dict]:
        """Get user transactions from last N days, or all if days_back is None"""
        query = {"user_id": self.user_id}
        if days_back is not None:
            query["date"] = {"$gte": datetime.now(timezone.utc) - timedelta(days=days_back)}
        
        transactions = list(transactions_collection.find(query).sort("date", -1))
        print(f"Found {len(transactions)} transactions for user {self.user_id}")
        return transactions
    
    def get_financial_summary(self) -> Dict[str, Any]:
        """Generate comprehensive financial summary"""
        transactions = self.get_user_transactions()
        
        if not transactions:
            return {"message": "No financial data available"}
        
        # Calculate totals
        total_inflow = sum(t["amount"] for t in transactions if t["type"] == "inflow")
        total_outflow = sum(t["amount"] for t in transactions if t["type"] == "outflow")
        
        # Category analysis
        inflow_by_category = {}
        outflow_by_category = {}
        monthly_data = {}
        
        for t in transactions:
            # Category aggregation
            category_key = f"{t['main_category']} > {t['sub_category']}"
            if t["type"] == "inflow":
                inflow_by_category[category_key] = inflow_by_category.get(category_key, 0) + t["amount"]
            else:
                outflow_by_category[category_key] = outflow_by_category.get(category_key, 0) + t["amount"]
            
            # Monthly trends - ensure timezone consistency
            date_obj = ensure_utc_datetime(t["date"])
            month_key = date_obj.strftime("%Y-%m")
            if month_key not in monthly_data:
                monthly_data[month_key] = {"inflow": 0, "outflow": 0}
            monthly_data[month_key][t["type"]] += t["amount"]
        
        # Get date range with proper timezone handling
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
    
    def _format_date(self, transaction: Dict) -> tuple:
        """Format transaction date into various formats with timezone awareness"""
        # Ensure timezone-aware datetime
        date_obj = ensure_utc_datetime(transaction["date"])
        
        return (
            date_obj.isoformat(),
            date_obj.strftime("%A"),  # Day of week
            date_obj.strftime("%B"),  # Month name
            date_obj.year,
            date_obj.isocalendar()[1],  # Week number
            date_obj
        )
    
    def create_financial_documents(self) -> List[Document]:
        """Create documents for vector store from financial data"""
        transactions = self.get_user_transactions()
        summary = self.get_financial_summary()
        documents = []
        
        # Summary document
        summary_text = f"""
        Financial Summary for User:
        - Total Balance: ${summary.get('balance', 0):.2f}
        - Total Income: ${summary.get('total_inflow', 0):.2f}
        - Total Expenses: ${summary.get('total_outflow', 0):.2f}
        - Number of Transactions: {summary.get('total_transactions', 0)}
        - Average Transaction: ${summary.get('avg_transaction_amount', 0):.2f}
        - Date Range: {summary.get('date_range', {}).get('from', 'N/A')} to {summary.get('date_range', {}).get('to', 'N/A')}
        
        Top Income Categories:
        {json.dumps(summary.get('top_inflow_categories', {}), indent=2)}
        
        Top Expense Categories:
        {json.dumps(summary.get('top_outflow_categories', {}), indent=2)}
        
        Monthly Trends:
        {json.dumps(summary.get('monthly_trends', {}), indent=2)}
        """
        documents.append(Document(
            page_content=summary_text,
            metadata={"type": "financial_summary", "user_id": self.user_id}
        ))
        
        # Transaction documents
        for transaction in transactions:
            date_str, day_of_week, month_name, year, week_number, date_obj = self._format_date(transaction)
            
            transaction_text = f"""
            Transaction Details:
            Date: {date_str}
            Human-readable Date: {day_of_week}, {month_name} {date_obj.day}, {year}
            Week Number: Week {week_number} of {year}
            Day of Week: {day_of_week}
            Month: {month_name} {year}
            Type: {transaction["type"].title()}
            Category: {transaction["main_category"]} > {transaction["sub_category"]}
            Amount: ${transaction["amount"]:.2f}
            Description: {transaction.get("description", "N/A")}
            """
            
            documents.append(Document(
                page_content=transaction_text,
                metadata={
                    "type": "transaction",
                    "user_id": self.user_id,
                    "transaction_type": transaction["type"],
                    "category": transaction["main_category"],
                    "subcategory": transaction["sub_category"],
                    "amount": transaction["amount"],
                    "date": date_str,
                    "day_of_week": day_of_week,
                    "month": month_name,
                    "year": year,
                    "week_number": week_number
                }
            ))
        
        # Category analysis documents
        category_groups = {}
        for t in transactions:
            category = f"{t['main_category']} > {t['sub_category']}"
            if category not in category_groups:
                category_groups[category] = {"transactions": [], "total": 0, "type": t["type"]}
            category_groups[category]["transactions"].append(t)
            category_groups[category]["total"] += t["amount"]
        
        for category, data in category_groups.items():
            category_text = f"""
            Category Analysis: {category}
            Type: {data["type"].title()}
            Total Amount: ${data["total"]:.2f}
            Number of Transactions: {len(data["transactions"])}
            Average per Transaction: ${data["total"] / len(data["transactions"]):.2f}
            
            Recent Transactions in this category:
            """
            
            for t in data["transactions"][-5:]:
                _, day_of_week, month_name, _, _, date_obj = self._format_date(t)
                category_text += f"\n- {day_of_week}, {month_name} {date_obj.day}, {date_obj.year}: ${t['amount']:.2f} - {t.get('description', 'No description')}"
            
            documents.append(Document(
                page_content=category_text,
                metadata={
                    "type": "category_analysis",
                    "user_id": self.user_id,
                    "category": category,
                    "transaction_type": data["type"],
                    "total_amount": data["total"]
                }
            ))
        
        print(f"Created {len(documents)} documents for vector store")
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
            chunk_size=800,
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
                    collection_name=f"user_{user_id}_finances_{int(datetime.now().timestamp())}"
                )
                self.user_vector_stores[user_id] = vector_store
                print(f"Created vector store with {len(split_documents)} documents")
            except Exception as e:
                print(f"Error creating vector store: {e}")
                return None
        
        return self.user_vector_stores[user_id]
    
    def refresh_user_data(self, user_id: str):
        """Refresh user's financial data in vector store"""
        if user_id in self.user_vector_stores:
            del self.user_vector_stores[user_id]
        self._get_or_create_vector_store(user_id)
    
    def _get_current_date_context(self) -> Dict[str, Any]:
        """Get current date and time context in UTC"""
        now = datetime.now(timezone.utc)
        return {
            "now": now,
            "date_str": now.strftime("%A, %B %d, %Y"),
            "date_only": now.strftime("%Y-%m-%d"),  # Added for clarity
            "time_str": now.strftime("%I:%M %p %Z"),
            "week": now.isocalendar()[1],
            "month": now.strftime("%B %Y"),
            "year": now.year,
            "last_week": now.isocalendar()[1] - 1,
            "last_month": (now.replace(day=1) - timedelta(days=1)).strftime("%B %Y")
        }
    
    def _build_system_prompt(self, date_context: Dict) -> str:
        """Build system prompt with date awareness"""
        return f"""You are Flow Finance AI, a helpful personal finance assistant with access to the user's actual financial transaction data.

CRITICAL DATE AWARENESS:
- Today's date is: {date_context['date_str']} (UTC)
- Today's date in YYYY-MM-DD format: {date_context['date_only']}
- Current time: {date_context['time_str']}
- Current week: Week {date_context['week']} of {date_context['year']}
- Current month: {date_context['month']}

IMPORTANT: All transaction dates in the system are stored in UTC timezone. When comparing dates:
- Compare only the DATE portion (YYYY-MM-DD), not the time
- A transaction is "today" if its date matches {date_context['date_only']}
- A transaction is "this week" if it falls in week {date_context['week']} of {date_context['year']}
- A transaction is "this month" if it falls in {date_context['month']}

When users ask about time periods:
- "today" = transactions dated {date_context['date_only']}
- "this week" = Week {date_context['week']} of {date_context['year']}
- "this month" = {date_context['month']}
- "last week" = Week {date_context['last_week']} of {date_context['year']}
- "last month" = {date_context['last_month']}

Your capabilities:
- Analyze user's real financial transactions with accurate date awareness
- Answer questions about specific days, weeks, months, and date ranges
- Provide specific insights based on actual amounts, categories, and dates
- Offer actionable financial recommendations based on temporal patterns

Instructions:
- Always base answers on ACTUAL financial data provided
- Pay careful attention to transaction dates for time-specific questions
- Compare dates carefully - transactions from October 1st or October 2nd are NOT "today" if today is October 9th
- Be specific with amounts, categories, AND dates
- Format money as $X.XX and dates human-readably
- If information for a time period is unavailable, clearly state that
- If there are no transactions for a requested time period, say so explicitly
- Be conversational, friendly, and helpful
- Never make up data
- Only answer about the asked content"""
    
    def _build_user_prompt(self, user: Dict, summary: Dict, context: str, history_text: str, message: str, date_context: Dict) -> str:
        """Build user prompt with all necessary data"""
        return f"""User Information:
- Name: {user.get('name', 'User')}
- Email: {user.get('email', '')}

Current Date and Time Reference (UTC):
- Today is: {date_context['date_str']}
- Today's date: {date_context['date_only']}
- Current time: {date_context['time_str']}
- Current week: Week {date_context['week']} of {date_context['year']}
- Current month: {date_context['month']}

IMPORTANT: When looking for "today's" transactions, look for transactions dated exactly {date_context['date_only']}.

Current Financial Summary (All Time):
- Balance: ${summary.get('balance', 0):.2f}
- Total Income: ${summary.get('total_inflow', 0):.2f}  
- Total Expenses: ${summary.get('total_outflow', 0):.2f}
- Total Transactions: {summary.get('total_transactions', 0)}

Top Income Categories:
{json.dumps(summary.get('top_inflow_categories', {}), indent=2)}

Top Expense Categories:
{json.dumps(summary.get('top_outflow_categories', {}), indent=2)}

Detailed Context from User's Financial Data:
{context}

Chat History:
{history_text}

User's Question: {message}

Remember: Today is {date_context['date_only']}. Only transactions with this exact date are "today's" transactions."""
    
    async def stream_chat(self, user_id: str, message: str, chat_history: Optional[List[Dict]] = None):
        """Stream chat response with user's financial data"""
        try:
            # Get user and summary
            user = users_collection.find_one({"_id": user_id})
            if not user:
                yield "User not found. Please make sure you're logged in."
                return
            
            processor = FinancialDataProcessor(user_id)
            summary = processor.get_financial_summary()
            
            if summary.get("message"):
                yield "I don't have access to your financial data yet. Please add some transactions first!"
                return
            
            # Get context from vector store
            context = ""
            vector_store = self._get_or_create_vector_store(user_id)
            if vector_store:
                try:
                    retriever = vector_store.as_retriever(search_kwargs={"k": 6})
                    relevant_docs = retriever.invoke(message)
                    context = "\n\n".join([doc.page_content for doc in relevant_docs])
                except Exception as e:
                    print(f"Error retrieving documents: {e}")
                    context = "Using financial summary as fallback context."
            
            # Prepare chat history
            history_text = ""
            if chat_history:
                for msg in chat_history[-3:]:
                    role = "User" if msg.get("role") == "user" else "Assistant"
                    history_text += f"{role}: {msg.get('content', '')}\n"
            
            # Build prompts
            date_context = self._get_current_date_context()
            system_prompt = self._build_system_prompt(date_context)
            user_prompt = self._build_user_prompt(user, summary, context, history_text, message, date_context)
            
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
            yield f"I'm sorry, I encountered an error: {str(e)}"
    
    def get_financial_insights(self, user_id: str) -> str:
        """Generate automatic financial insights"""
        try:
            processor = FinancialDataProcessor(user_id)
            summary = processor.get_financial_summary()
            
            if summary.get("message"):
                return "I don't have enough financial data to provide insights yet. Please add some transactions first!"
            
            date_context = self._get_current_date_context()
            
            system_prompt = f"""You are Flow Finance AI, a financial analyst providing personalized insights.

Current Date: {date_context['date_str']} (UTC)

Analyze financial patterns and trends with date awareness, identify savings opportunities, and provide specific, actionable recommendations in a friendly, conversational tone."""
            
            user_prompt = f"""Analyze this user's financial data and provide 4-5 key insights and actionable recommendations.

Today's date: {date_context['date_str']}

Financial Summary:
- Current Balance: ${summary.get('balance', 0):.2f}
- Total Income: ${summary.get('total_inflow', 0):.2f}
- Total Expenses: ${summary.get('total_outflow', 0):.2f}
- Number of Transactions: {summary.get('total_transactions', 0)}
- Date Range: {summary.get('date_range', {}).get('from', 'N/A')} to {summary.get('date_range', {}).get('to', 'N/A')}

Top Income Categories:
{json.dumps(summary.get('top_inflow_categories', {}), indent=2)}

Top Expense Categories:
{json.dumps(summary.get('top_outflow_categories', {}), indent=2)}

Monthly Trends:
{json.dumps(summary.get('monthly_trends', {}), indent=2)}

Provide insights on spending patterns, top expense categories, income vs expense ratio, specific recommendations, and concerning or positive trends."""
            
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