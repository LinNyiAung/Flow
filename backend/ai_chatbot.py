import os
from typing import List, Dict, Any, Optional
from datetime import datetime, timedelta, timezone
import json
import numpy as np

from langchain_openai import OpenAIEmbeddings
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_community.vectorstores import Chroma
from langchain.schema import Document

from database import transactions_collection, users_collection
from config import settings
from dotenv import load_dotenv

load_dotenv()


class FinancialDataProcessor:
    """Processes user's financial data for RAG"""
    
    def __init__(self, user_id: str):
        self.user_id = user_id
        
    def get_user_transactions(self, days_back: Optional[int] = None) -> List[Dict]:
        """Get user transactions from last N days, or all transactions if days_back is None"""
        query = {"user_id": self.user_id}
        
        # Only apply date filter if days_back is specified
        if days_back is not None:
            start_date = datetime.now(timezone.utc) - timedelta(days=days_back)
            query["date"] = {"$gte": start_date}
        
        transactions = list(
            transactions_collection
            .find(query)
            .sort("date", -1)
        )
        
        print(f"Found {len(transactions)} transactions for user {self.user_id} (days_back: {days_back})")
        return transactions
    
    def get_financial_summary(self) -> Dict[str, Any]:
        """Generate financial summary for the user"""
        # Get ALL transactions, not just recent ones
        transactions = self.get_user_transactions(days_back=None)
        
        print(f"Processing {len(transactions)} transactions for summary")
        
        if not transactions:
            return {"message": "No financial data available"}
        
        # Calculate totals
        total_inflow = sum(t["amount"] for t in transactions if t["type"] == "inflow")
        total_outflow = sum(t["amount"] for t in transactions if t["type"] == "outflow")
        balance = total_inflow - total_outflow
        
        # Category analysis
        inflow_by_category = {}
        outflow_by_category = {}
        
        for t in transactions:
            category_key = f"{t['main_category']} > {t['sub_category']}"
            if t["type"] == "inflow":
                inflow_by_category[category_key] = inflow_by_category.get(category_key, 0) + t["amount"]
            else:
                outflow_by_category[category_key] = outflow_by_category.get(category_key, 0) + t["amount"]
        
        # Monthly trends
        monthly_data = {}
        for t in transactions:
            # Handle both timezone-aware and naive datetime objects
            if isinstance(t["date"], str):
                date_obj = datetime.fromisoformat(t["date"].replace("Z", "+00:00"))
            else:
                date_obj = t["date"]
            
            month_key = date_obj.strftime("%Y-%m")
            if month_key not in monthly_data:
                monthly_data[month_key] = {"inflow": 0, "outflow": 0}
            monthly_data[month_key][t["type"]] += t["amount"]
        
        summary = {
            "total_transactions": len(transactions),
            "balance": balance,
            "total_inflow": total_inflow,
            "total_outflow": total_outflow,
            "top_inflow_categories": dict(sorted(inflow_by_category.items(), key=lambda x: x[1], reverse=True)[:10]),
            "top_outflow_categories": dict(sorted(outflow_by_category.items(), key=lambda x: x[1], reverse=True)[:10]),
            "monthly_trends": monthly_data,
            "avg_transaction_amount": sum(t["amount"] for t in transactions) / len(transactions) if transactions else 0,
            "date_range": {
                "from": min(t["date"] for t in transactions).isoformat() if transactions else None,
                "to": max(t["date"] for t in transactions).isoformat() if transactions else None
            }
        }
        
        print(f"Generated summary: Balance=${balance:.2f}, Inflow=${total_inflow:.2f}, Outflow=${total_outflow:.2f}")
        return summary
    
    def create_financial_documents(self) -> List[Document]:
        """Create documents for vector store from financial data"""
        # Get ALL transactions for the user
        transactions = self.get_user_transactions(days_back=None)
        summary = self.get_financial_summary()
        
        documents = []
        
        print(f"Creating documents from {len(transactions)} transactions")
        
        # Add summary document
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
        
        # Add individual transaction documents with enhanced date information
        for transaction in transactions:
            # Handle datetime formatting
            if isinstance(transaction["date"], str):
                date_obj = datetime.fromisoformat(transaction["date"].replace("Z", "+00:00"))
            else:
                date_obj = transaction["date"]
            
            date_str = date_obj.isoformat()
            
            # Add human-readable date information
            day_of_week = date_obj.strftime("%A")  # Monday, Tuesday, etc.
            month_name = date_obj.strftime("%B")   # January, February, etc.
            year = date_obj.year
            week_number = date_obj.isocalendar()[1]  # ISO week number
            
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
            
            This is a {transaction["type"]} transaction that occurred on {day_of_week}, {month_name} {date_obj.day}, {year}.
            It belongs to the {transaction["main_category"]} category, specifically for {transaction["sub_category"]}.
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
        
        # Group transactions by category for better context
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
            
            for t in data["transactions"][-5:]:  # Last 5 transactions
                if isinstance(t["date"], str):
                    date_obj = datetime.fromisoformat(t["date"].replace("Z", "+00:00"))
                else:
                    date_obj = t["date"]
                
                date_str = date_obj.isoformat()
                day_of_week = date_obj.strftime("%A")
                month_name = date_obj.strftime("%B")
                
                category_text += f"""
                - {day_of_week}, {month_name} {date_obj.day}, {date_obj.year}: ${t["amount"]:.2f} - {t.get("description", "No description")}
                """
            
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
        # Initialize OpenAI API key
        self.openai_api_key = os.getenv("OPENAI_API_KEY")
        if not self.openai_api_key:
            print("Warning: OPENAI_API_KEY not found, chatbot may not work properly")
        
        print(f"Initializing chatbot with API key: {self.openai_api_key[:10] if self.openai_api_key else 'None'}...")
        
        # Initialize components
        try:
            self.embeddings = OpenAIEmbeddings(
                api_key=self.openai_api_key,
                model="text-embedding-3-small"  # More cost-effective
            )
        except Exception as e:
            print(f"Error initializing embeddings: {e}")
            self.embeddings = None
        
        # Text splitter for documents
        self.text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=800,
            chunk_overlap=100,
            separators=["\n\n", "\n", " ", ""]
        )
        
        # Storage for user vector stores
        self.user_vector_stores = {}
    
    def _get_or_create_vector_store(self, user_id: str) -> Chroma:
        """Get or create vector store for user"""
        print(f"Getting vector store for user: {user_id}")
        
        if user_id not in self.user_vector_stores:
            # Process user's financial data
            processor = FinancialDataProcessor(user_id)
            documents = processor.create_financial_documents()
            
            if not documents:
                print("No documents created - user has no financial data")
                return None
            
            # Split documents
            split_documents = self.text_splitter.split_documents(documents)
            print(f"Split into {len(split_documents)} document chunks")
            
            # Create vector store with unique collection name
            try:
                if not self.embeddings:
                    print("Embeddings not initialized, cannot create vector store")
                    return None
                    
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
        print(f"Refreshing data for user: {user_id}")
        if user_id in self.user_vector_stores:
            del self.user_vector_stores[user_id]
        
        # This will recreate the vector store with fresh data
        self._get_or_create_vector_store(user_id)
        
        
    async def stream_chat(self, user_id: str, message: str, chat_history: Optional[List[Dict]] = None):
        """Stream chat response with user's financial data"""
        try:
            print(f"Processing streaming chat for user {user_id}: {message[:50]}...")
            
            # Get user info
            user = users_collection.find_one({"_id": user_id})
            if not user:
                yield "User not found. Please make sure you're logged in."
                return
            
            # Get basic financial summary first for fallback
            processor = FinancialDataProcessor(user_id)
            summary = processor.get_financial_summary()
            
            # Check if user has any transactions
            if summary.get("message"):
                yield "I don't have access to your financial data yet. Please add some transactions first!"
                return
            
            # Get vector store
            vector_store = self._get_or_create_vector_store(user_id)
            
            # Get relevant context from vector store
            context = ""
            if vector_store:
                try:
                    retriever = vector_store.as_retriever(search_kwargs={"k": 6})
                    relevant_docs = retriever.invoke(message)
                    print(f"Retrieved {len(relevant_docs)} relevant documents")
                    
                    # Combine context from relevant documents
                    context = "\n\n".join([doc.page_content for doc in relevant_docs])
                    print(f"Context length: {len(context)} characters")
                    
                except Exception as e:
                    print(f"Error retrieving documents: {e}")
                    context = "Using financial summary as fallback context."
            
            # Prepare chat history text
            history_text = ""
            if chat_history:
                for msg in chat_history[-3:]:  # Last 3 messages for context
                    role = "User" if msg.get("role") == "user" else "Assistant"
                    history_text += f"{role}: {msg.get('content', '')}\n"
            
            # Get current date information
            now = datetime.now(timezone.utc)
            current_date_str = now.strftime("%A, %B %d, %Y")  # e.g., "Monday, October 01, 2025"
            current_time_str = now.strftime("%I:%M %p %Z")     # e.g., "02:30 PM UTC"
            current_week = now.isocalendar()[1]
            
            # ============ SEPARATED PROMPTS ============
            
            # SYSTEM PROMPT - Role, capabilities, and instructions
            system_prompt = f"""You are Flow Finance AI, a helpful personal finance assistant with access to the user's actual financial transaction data.

CRITICAL DATE AWARENESS:
- Today's date is: {current_date_str}
- Current time: {current_time_str}
- Current week: Week {current_week} of {now.year}
- Current month: {now.strftime("%B %Y")}
- Current year: {now.year}

When users ask about time periods:
- "today" = {now.strftime("%B %d, %Y")}
- "this week" = Week {current_week} of {now.year}
- "this month" = {now.strftime("%B %Y")}
- "last week" = Week {current_week - 1} of {now.year}
- "last month" = {(now.replace(day=1) - timedelta(days=1)).strftime("%B %Y")}
- Always calculate relative dates from today's date

Your capabilities:
- Analyze user's real financial transactions with accurate date awareness
- Answer questions about specific days, weeks, months, and date ranges
- Provide specific insights based on actual amounts, categories, and dates
- Offer actionable financial recommendations based on temporal patterns
- Compare spending across different time periods

Instructions:
- Always base your answers on the user's ACTUAL financial data provided
- Pay careful attention to transaction dates when answering time-specific questions
- When users ask about "today", "yesterday", "this week", "last month", etc., calculate the exact date range
- Be specific with amounts, categories, AND dates when available
- Provide actionable insights and recommendations
- Always format money amounts as $X.XX
- Always format dates in a human-readable way (e.g., "Monday, October 1, 2025")
- If you cannot find specific information for a requested time period, clearly state that
- Be conversational, friendly, and helpful
- Never make up data - only use what's provided in the context
- Only answer about the asked content"""

            # USER PROMPT - User-specific data and the actual question
            user_prompt = f"""User Information:
- Name: {user.get('name', 'User')}
- Email: {user.get('email', '')}

Current Date and Time Reference:
- Today is: {current_date_str}
- Current time: {current_time_str}
- Current week: Week {current_week} of {now.year}
- Current month: {now.strftime("%B %Y")}

Current Financial Summary:
- Balance: ${summary.get('balance', 0):.2f}
- Total Income: ${summary.get('total_inflow', 0):.2f}  
- Total Expenses: ${summary.get('total_outflow', 0):.2f}
- Total Transactions: {summary.get('total_transactions', 0)}

Top Income Categories:
{json.dumps(summary.get('top_inflow_categories', {}), indent=2)}

Top Expense Categories:
{json.dumps(summary.get('top_outflow_categories', {}), indent=2)}

Detailed Context from User's Financial Data (includes transaction dates):
{context}

Chat History:
{history_text}

User's Question: {message}

Remember: Use today's date ({current_date_str}) as your reference point for all relative time questions."""
            
            # Get streaming response from OpenAI
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
                stream=True  # Enable streaming
            )
            
            print("Starting streaming response...")
            async for chunk in stream:
                if chunk.choices[0].delta.content is not None:
                    content = chunk.choices[0].delta.content
                    yield content
            
        except Exception as e:
            print(f"Streaming chat error: {str(e)}")
            import traceback
            traceback.print_exc()
            yield f"I'm sorry, I encountered an error while processing your request: {str(e)}"
    
    def get_financial_insights(self, user_id: str) -> str:
        """Generate automatic financial insights for user"""
        try:
            processor = FinancialDataProcessor(user_id)
            summary = processor.get_financial_summary()
            
            if summary.get("message"):
                return "I don't have enough financial data to provide insights yet. Please add some transactions first!"
            
            # Get current date information
            now = datetime.now(timezone.utc)
            current_date_str = now.strftime("%A, %B %d, %Y")
            
            # ============ SEPARATED PROMPTS FOR INSIGHTS ============
            
            # System prompt for insights
            system_prompt = f"""You are Flow Finance AI, a financial analyst providing personalized insights based on real user data.

Current Date: {current_date_str}

Your role:
- Analyze financial patterns and trends with date awareness
- Identify potential savings opportunities
- Provide specific, actionable recommendations
- Speak directly to the user in a friendly, conversational tone
- Reference actual amounts, categories, AND dates from their data
- Use temporal context (recent vs older transactions, monthly trends, etc.)"""
            
            # User prompt with financial data
            user_prompt = f"""Analyze this user's financial data and provide 4-5 key insights and actionable recommendations.

Today's date for reference: {current_date_str}

Financial Summary:
- Current Balance: ${summary.get('balance', 0):.2f}
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

Provide insights on:
1. Spending patterns and trends (reference specific time periods)
2. Top expense categories and potential savings
3. Income vs expense ratio
4. Specific actionable recommendations
5. Any concerning trends or positive financial behaviors (note if they're recent or ongoing)"""
            
            # Get response from OpenAI
            if not self.openai_api_key:
                return "AI service is not available. OpenAI API key not configured."
                
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
            return "Unable to generate insights at this time. Please try again later."


# Global chatbot instance
try:
    financial_chatbot = FinancialChatbot()
    print("Financial chatbot initialized successfully")
except Exception as e:
    print(f"Failed to initialize financial chatbot: {e}")
    financial_chatbot = None