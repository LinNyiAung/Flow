import asyncio
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


# Import FinancialDataProcessor from the original file
from ai_chatbot import FinancialDataProcessor


class GeminiFinancialChatbot:
    """AI Chatbot with Gemini + Optimized RAG"""
    
    def __init__(self):
        self.last_usage = {}
        self.google_api_key = os.getenv("GOOGLE_API_KEY")
        if not self.google_api_key:
            print("Warning: GOOGLE_API_KEY not found")
        
        self.openai_api_key = os.getenv("OPENAI_API_KEY")
        if not self.openai_api_key:
            print("Warning: OPENAI_API_KEY not found (needed for embeddings)")
        
        try:
            # Still use OpenAI embeddings (Gemini doesn't have good embedding API via langchain)
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
        
        self.gemini_model = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
        
        # Initialize the new Gemini client
        self.client = None
        if self.google_api_key:
            try:
                from google import genai
                self.client = genai.Client(api_key=self.google_api_key)
                print("✅ Initialized new google.genai client")
            except Exception as e:
                print(f"❌ Failed to initialize genai client: {e}")
    
    # [FIX] Changed to async
    async def _get_or_create_vector_store(self, user_id: str) -> Chroma:
        """Get or create vector store for user"""
        if user_id not in self.user_vector_stores:
            processor = FinancialDataProcessor(user_id)
            
            # [FIX] Await async document creation
            documents = await processor.create_financial_documents()
            
            if not documents or not self.embeddings:
                return None
            
            try:
                split_documents = []
                for doc in documents:
                    if doc.metadata.get("type") in ["chronological_index", "goals_overview"]:
                        split_documents.append(doc)
                    else:
                        split_documents.extend(self.text_splitter.split_documents([doc]))
                
                # [FIX] Run blocking Chroma call in a thread
                vector_store = await asyncio.to_thread(
                    Chroma.from_documents,
                    documents=split_documents,
                    embedding=self.embeddings,
                    collection_name=f"user_gemini_{user_id}_{int(datetime.now().timestamp())}"
                )
                self.user_vector_stores[user_id] = vector_store
                print(f"✅ Created Gemini vector store with {len(split_documents)} chunks")
            except Exception as e:
                print(f"❌ Error creating Gemini vector store: {e}")
                return None
        
        return self.user_vector_stores[user_id]
    
    def refresh_user_data(self, user_id: str):
        """
        Invalidate user's vector store cache. 
        The next call to stream_chat will automatically rebuild it.
        """
        if user_id in self.user_vector_stores:
            try:
                self.user_vector_stores[user_id].delete_collection()
            except:
                pass
            del self.user_vector_stores[user_id]
        
        # REMOVED: self._get_or_create_vector_store(user_id)
        
        print(f"✅ Refreshed (Invalidated) data for user {user_id}")
    
    def _build_system_prompt(self, today: str, response_style: str = "normal") -> str:
        """Build enhanced system prompt for Gemini with Myanmar language support and response style"""
        
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

🌏 LANGUAGE CAPABILITY:
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
                prompt += f"  Total Balance: {currency_symbol}{data.get('balance', 0):,.2f}\n"
                
                # Goals allocation for this currency
                if goals_summary:
                    curr_goals = [g for g in goals_summary.get('goals_by_currency', {}).get(currency, [])]
                    if curr_goals:
                        allocated = sum(g.get('current_amount', 0) for g in curr_goals if g.get('status') == 'active')
                        prompt += f"  💎 Allocated to Goals: {currency_symbol}{allocated:,.2f}\n"
                        prompt += f"  ✨ Available Balance: {currency_symbol}{data.get('balance', 0) - allocated:,.2f}\n"
                
                prompt += f"  📈 Income: {currency_symbol}{data.get('total_inflow', 0):,.2f}\n"
                prompt += f"  📉 Expenses: {currency_symbol}{data.get('total_outflow', 0):,.2f}\n"
                
                # Budget info for this currency
                if budgets_summary:
                    curr_budgets = budgets_summary.get('budgets_by_currency', {}).get(currency, {})
                    if curr_budgets:
                        budget_allocated = curr_budgets.get('total_allocated', 0)
                        budget_spent = curr_budgets.get('total_spent', 0)
                        budget_remaining = curr_budgets.get('remaining', 0)
                        budget_percentage = curr_budgets.get('percentage_used', 0)
                        
                        prompt += f"  📊 Active Budget: {currency_symbol}{budget_allocated:,.2f}\n"
                        prompt += f"  💸 Budget Spent: {currency_symbol}{budget_spent:,.2f} ({budget_percentage:.1f}%)\n"
                        prompt += f"  💰 Budget Left: {currency_symbol}{budget_remaining:,.2f}\n"
                        
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
                
                prompt += f"  ✨ Available Balance: {currency_symbol}{available:,.2f}\n"
                
                
        # Goals summary by currency
        if goals_summary and goals_summary.get('goals_by_currency'):
            prompt += "\n🎯 GOALS BY CURRENCY:\n"
            for currency, curr_goals in goals_summary['goals_by_currency'].items():
                currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")
                active = [g for g in curr_goals if g.get('status') == 'active']
                achieved = [g for g in curr_goals if g.get('status') == 'achieved']
                prompt += f"  {currency_name}: {len(active)} active, {len(achieved)} achieved\n"
        
        # Budgets summary by currency
        if budgets_summary and budgets_summary.get('budgets_by_currency'):
            prompt += "\n📊 BUDGETS BY CURRENCY:\n"
            for currency, curr_budget_data in budgets_summary['budgets_by_currency'].items():
                currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")
                currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
                
                active_count = curr_budget_data.get('active_count', 0)
                total_allocated = curr_budget_data.get('total_allocated', 0)
                total_spent = curr_budget_data.get('total_spent', 0)
                percentage = curr_budget_data.get('percentage_used', 0)
                
                status_icon = "🔴" if percentage >= 100 else ("🟡" if percentage >= 80 else "🟢")
                
                prompt += f"  {currency_name}: {active_count} active budget(s) - "
                prompt += f"{currency_symbol}{total_spent:,.2f}/{currency_symbol}{total_allocated:,.2f} "
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
        """Stream chat response using Gemini Flash 2.5 with enhanced RAG"""
        try:
            if not self.client:
                yield "Gemini AI service is not available. API key not configured.", None
                return

            # [FIX] Direct await (Async Motor)
            user = await users_collection.find_one({"_id": user_id})
            if not user:
                yield "User not found. Please log in again.", None
                return
            
            processor = FinancialDataProcessor(user_id)
            
            # [FIX] Await async methods concurrently
            summary, goals, budgets = await asyncio.gather(
                processor.get_financial_summary(),
                processor.get_user_goals(),
                processor.get_user_budgets()
            )
            
            # Calculate goals summary (Logic remains same)
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
            
            # Calculate budgets summary (Logic remains same)
            budgets_summary = None
            if budgets:
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
                
                for curr, data in budgets_by_currency.items():
                    data['remaining'] = data['total_allocated'] - data['total_spent']
                    data['percentage_used'] = (data['total_spent'] / data['total_allocated'] * 100) if data['total_allocated'] > 0 else 0
                
                budgets_summary = {
                    "total_budgets": len(budgets),
                    "active_budgets": len(budgets),
                    "budgets_by_currency": budgets_by_currency
                }
            
            if summary.get("message") and not goals:
                yield "I don't have access to your financial data yet. Please add some transactions or goals first!", None
                return
            
            # Get relevant context from RAG
            context = ""
            
            # [FIX] Await async vector store creation
            vector_store = await self._get_or_create_vector_store(user_id)
            
            if vector_store:
                try:
                    # Detect query type
                    temporal_keywords = ["latest", "last", "recent", "newest", "today", "yesterday", "this week"]
                    goal_keywords = ["goal", "save", "saving", "target", "progress", "achieve", "reached"]
                    budget_keywords = ["budget", "spending", "spend", "expense", "limit", "exceeded", "remaining"]
                    
                    is_temporal = any(keyword in message.lower() for keyword in temporal_keywords)
                    is_goal_query = any(keyword in message.lower() for keyword in goal_keywords)
                    is_budget_query = any(keyword in message.lower() for keyword in budget_keywords)
                    
                    k_value = 12 if (is_temporal or is_goal_query or is_budget_query) else 6
                    
                    retriever = vector_store.as_retriever(
                        search_kwargs={"k": k_value}
                    )
                    
                    # [FIX] Run blocking retriever in a thread
                    relevant_docs = await asyncio.to_thread(retriever.invoke, message)
                    
                    # Prioritize important documents
                    if is_temporal or is_goal_query or is_budget_query:
                        priority_docs = [d for d in relevant_docs if d.metadata.get("priority") in ["critical", "high"]]
                        other_docs = [d for d in relevant_docs if d.metadata.get("priority") not in ["critical", "high"]]
                        relevant_docs = priority_docs + other_docs
                    
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
            
            today = datetime.now(timezone.utc).strftime("%A, %B %d, %Y")
            
            system_prompt = self._build_system_prompt(today, response_style)
            user_prompt = self._build_user_prompt(user, summary, goals_summary, budgets_summary, context, history_text, message, today)
            
            
            # Adjust temperature based on style
            temperature_map = {
                "normal": 0.3,
                "concise": 0.2,
                "explanatory": 0.4
            }
            
            try:
                # Approximate token count for logging
                estimated_input = len(system_prompt + user_prompt) // 4
                
                # Gemini streaming call (using sync client in a thread or async client if available)
                # Assuming 'self.client.models.generate_content_stream' is blocking:
                response = await self.client.aio.models.generate_content_stream(
                    model=self.gemini_model,
                    contents=[
                        # Note: Gemini system prompt is usually config, but putting it in text works too
                        f"{system_prompt}\n\nUSER QUERY: {user_prompt}"
                    ],
                    config={
                    "temperature": temperature_map.get(response_style, 0.3),
                    "max_output_tokens": 8192,
                }
                )
                
                full_response_text = ""
                
                # Iterate through the stream (this part is synchronous if response is a generator)
                async for chunk in response:
                    if chunk.text:
                        full_response_text += chunk.text
                        yield chunk.text, None
                        await asyncio.sleep(0.01)  # Yield control to event loop
                
                # Calculate final usage
                estimated_output = len(full_response_text) // 4
                
                # Try to get actual usage metadata if available
                # (Note: Google GenAI Python SDK usage metadata access varies by version)
                if hasattr(response, 'usage_metadata'):
                    actual_input = getattr(response.usage_metadata, 'prompt_token_count', estimated_input)
                    actual_output = getattr(response.usage_metadata, 'candidates_token_count', estimated_output)
                    actual_total = getattr(response.usage_metadata, 'total_token_count', actual_input + actual_output)
                else:
                    actual_input = estimated_input
                    actual_output = estimated_output
                    actual_total = actual_input + actual_output
                
                # If the response object has usage_metadata at the end (depends on SDK version)
                # You might access it here. For now, we fallback to estimates or the generator's final state.
                
                usage_data = {
                    'input_tokens': actual_input,
                    'output_tokens': actual_output,
                    'total_tokens': actual_total,
                    'model_name': self.gemini_model
                }
                
                yield "", usage_data
                    
            except Exception as usage_error:
                print(f"⚠️ Could not capture token usage: {usage_error}")
                yield "", None
            
        except Exception as e:
            print(f"❌ Gemini streaming chat error: {str(e)}")
            yield f"I encountered an error: {str(e)}", None
            

# Global Gemini chatbot instance
try:
    gemini_financial_chatbot = GeminiFinancialChatbot()
    print("✅ Gemini financial chatbot initialized successfully with Gemini + RAG + Goals")
except Exception as e:
    print(f"❌ Failed to initialize Gemini financial chatbot: {e}")
    gemini_financial_chatbot = None