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

💱 MULTI-CURRENCY CAPABILITY:
- The user can have transactions, goals, and budgets in multiple currencies (USD, MMK)
- ALWAYS specify the currency when discussing amounts (e.g., "$100 USD" or "50,000 K MMK")
- When comparing amounts across currencies, mention they are in different currencies
- Currency symbols: USD uses "$", MMK uses "K" or "Ks"
- NEVER mix currencies in calculations without explicit conversion
- If asked about "total balance" or "overall finances", break down by currency
- When discussing goals or budgets, always mention which currency they are in

Your capabilities:
- Answer questions about transactions with precision (multi-currency aware)
- Provide insights on financial goals and progress (per currency)
- Track goal achievements and suggest strategies
- Calculate savings needed to reach goals (in the goal's currency)
- Identify spending patterns that affect goal progress (currency-specific)
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

4. DATE ACCURACY:
- Today is {today}
- Verify dates carefully before answering
- Use the "days ago" information as a guide

5. RESPONSE STYLE - {response_style.upper()}:
{style_instructions.get(response_style, style_instructions["normal"])}

6. FORMATTING:
- Format money as $X.XX (USD) or X K (MMK)
- Include specific dates when relevant
- If unsure about something, say so honestly
- Never fabricate transaction or goal details

7. MYANMAR LANGUAGE SPECIFICS:
- Use respectful Myanmar expressions naturally 
- Keep financial advice clear and easy to understand
- Use bullet points (•) for lists in Myanmar responses too
- When translating amounts, keep currency symbols: $X.XX or X K
- Be warm and encouraging in Myanmar - financial discussions can be sensitive

8. PRIORITIZATION:
- For "latest/recent" queries, ALWAYS check the chronological index FIRST
- For goal-related queries, check the goals overview and individual goal details
- For currency-specific queries, filter by the mentioned currency
- Consider the interplay between spending, saving, and goal progress per currency

Remember: Accuracy is more important than speed. Double-check dates, amounts, AND currencies! Respect their time and adapt your verbosity to their preference.

ဘာသာစကား အတူကို ဂရုစိုက်ပါ။ (Use language naturally.)"""
    
    def _build_user_prompt(self, user: Dict, summary: Dict, goals_summary: Dict, context: str, history_text: str, message: str, today: str) -> str:
        """Build comprehensive user prompt with multi-currency support"""
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
                currency_symbol = "$" if currency == "usd" else "K"
                currency_name = "USD" if currency == "usd" else "MMK"
                
                prompt += f"\n{currency_name}:\n"
                prompt += f"  Total Balance: {currency_symbol}{data.get('balance', 0):.2f}\n"
                
                # Goals allocation for this currency
                if goals_summary:
                    curr_goals = [g for g in goals_summary.get('goals_by_currency', {}).get(currency, [])]
                    if curr_goals:
                        allocated = sum(g.get('current_amount', 0) for g in curr_goals if g.get('status') == 'active')
                        prompt += f"  💎 Allocated to Goals: {currency_symbol}{allocated:.2f}\n"
                        prompt += f"  ✨ Available Balance: {currency_symbol}{data.get('balance', 0) - allocated:.2f}\n"
                
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
        
        prompt += f"""

    ╔══════════════════════════════════════════════╗
                        FINANCIAL DATA
    ╚══════════════════════════════════════════════╝

    {context}

    {f"╔══════════════════════════════════════════════╗\n                CONVERSATION HISTORY\n╚══════════════════════════════════════════════╝{history_text}" if history_text else ""}

    ╔══════════════════════════════════════════════╗
                        USER QUESTION
    ╚══════════════════════════════════════════════╝

    {message}

    Please provide an accurate, helpful answer based on the financial data above. Remember to specify currencies when discussing amounts!"""
        
        return prompt
    
    async def stream_chat(self, user_id: str, message: str, chat_history: Optional[List[Dict]] = None, response_style: str = "normal"):
        """Stream chat response using Gemini with enhanced RAG and response style"""
        try:
            import google.generativeai as genai
            
            if not self.google_api_key:
                yield "Gemini service is not available. Google API key not configured."
                return
            
            genai.configure(api_key=self.google_api_key)
            
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
                # Group goals by currency for summary
                goals_by_currency = {}
                for g in goals:
                    currency = g.get("currency", "usd")
                    if currency not in goals_by_currency:
                        goals_by_currency[currency] = []
                    goals_by_currency[currency].append(g)
                
                active_goals = [g for g in goals if g["status"] == "active"]
                achieved_goals = [g for g in goals if g["status"] == "achieved"]
                total_allocated = sum(g["current_amount"] for g in active_goals)
                
                goals_summary = {
                    "total_goals": len(goals),
                    "active_goals": len(active_goals),
                    "achieved_goals": len(achieved_goals),
                    "total_allocated": total_allocated,
                    "goals_by_currency": goals_by_currency
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
            
            # Build prompts with response style
            system_prompt = self._build_system_prompt(today, response_style)
            user_prompt = self._build_user_prompt(user, summary, goals_summary, context, history_text, message, today)
            
            # Adjust temperature based on style
            temperature_map = {
                "normal": 0.3,
                "concise": 0.2,
                "explanatory": 0.4
            }
            
            # Create Gemini model
            model = genai.GenerativeModel(
                model_name=self.gemini_model,
                generation_config={
                    "temperature": temperature_map.get(response_style, 0.3),
                    "max_output_tokens": 1000,
                }
            )
            
            # Combine system and user prompts for Gemini
            full_prompt = f"{system_prompt}\n\n{user_prompt}"
            
            # Stream response
            response = model.generate_content(full_prompt, stream=True)
            
            for chunk in response:
                if chunk.text:
                    yield chunk.text
            
        except Exception as e:
            print(f"❌ Gemini streaming chat error: {str(e)}")
            import traceback
            traceback.print_exc()
            yield f"I encountered an error: {str(e)}"

    async def translate_insights_to_myanmar(self, english_content: str) -> str:
        """Translate English insights to Myanmar language using Gemini"""
        try:
            import google.generativeai as genai
            
            if not self.google_api_key:
                raise Exception("Google API key not configured")
            
            genai.configure(api_key=self.google_api_key)
            
            system_prompt = """You are a professional translator specializing in financial content. 
    Translate the following financial insights from English to Myanmar (Burmese) language.

    CRITICAL RULES:
    1. Maintain ALL formatting including markdown (##, **, bullets, emojis)
    2. Keep financial terms clear and understandable in Myanmar
    3. Preserve all numbers, percentages, and dollar amounts exactly
    4. Use natural, conversational Myanmar that feels native
    5. Keep emojis exactly as they are
    6. Maintain the same structure and sections

    For financial terms:
    - Money: ငွေ
    - Balance: လက်ကျန်ငွေ
    - Income: ၀င်ငွေ
    - Expenses: ကုန်ကျစရိတ်
    - Savings: စုဆောင်းငွေ
    - Budget: ဘတ်ဂျက်
    - Goals: ရည်မှန်းချက်များ
    - Transaction: ငွေသွင်းထုတ်

    Translate naturally while keeping the professional yet friendly tone."""

            model = genai.GenerativeModel(
                model_name=self.gemini_model,
                generation_config={
                    "temperature": 0.3,
                    "max_output_tokens": 8192,
                }
            )
            
            prompt = f"{system_prompt}\n\nTranslate this to Myanmar:\n\n{english_content}"
            
            response = model.generate_content(prompt)
            myanmar_content = response.text
            
            return myanmar_content
            
        except Exception as e:
            print(f"Gemini translation error: {e}")
            raise Exception(f"Failed to translate insights: {str(e)}")

    async def generate_insights(self, user_id: str) -> str:
        """Generate comprehensive financial insights using Gemini"""
        try:
            import google.generativeai as genai
            
            if not self.google_api_key:
                raise Exception("Google API key not configured")
            
            genai.configure(api_key=self.google_api_key)
            
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

💱 MULTI-CURRENCY AWARENESS:
- The user may have transactions, goals, and budgets in multiple currencies (USD, MMK)
- ALWAYS specify currency when discussing amounts
- Format: "$X.XX (USD)" or "X K (MMK)"
- Analyze each currency separately when relevant
- When comparing across currencies, mention they cannot be directly added
- Provide insights per currency and overall strategy

INSIGHT STRUCTURE:
Generate insights covering ALL relevant areas:

1. **Financial Health Overview** - Current state, trends, patterns (per currency)
2. **Spending Analysis** - Where money goes, concerning patterns, opportunities (by currency)
3. **Income Analysis** - Sources, stability, growth opportunities (by currency)
4. **Savings & Goals Progress** - Goal tracking, recommendations, timeline analysis (per currency)
5. **Multi-Currency Strategy** - If applicable, discuss balance between currencies
6. **Budget Recommendations** - Specific, actionable advice (currency-specific)
7. **Future Projections** - Where they're headed, what to watch (per currency)
8. **Celebration & Encouragement** - Acknowledge wins, motivate progress

CRITICAL RULES:
- Be COMPREHENSIVE - cover all aspects of their finances
- Be SPECIFIC - use actual numbers, dates, categories, AND CURRENCIES from their data
- Be ACTIONABLE - give concrete steps they can take
- Be HONEST - point out both strengths and areas for improvement
- Be ENCOURAGING - maintain a positive, supportive tone
- ALWAYS mention currency with amounts
- NO LIMITATIONS - analyze everything thoroughly
- Include comparisons (month-over-month, category ratios, goal progress)
- Identify both opportunities and risks
- Make predictions based on current trends

Format with clear sections using markdown:
- Use ## for main sections
- Use **bold** for emphasis
- Use bullet points for lists
- Include specific dollar/kyat amounts with currency labels
- Add emojis for visual appeal (💰 📈 📉 🎯 ⚠️ ✅ 🎉)

Length: 800-1500 words of detailed, personalized analysis."""

            today = datetime.now(timezone.utc).strftime("%A, %B %d, %Y")
            user_prompt = f"""Today's Date: {today}

    USER FINANCIAL DATA:
    {context}

    Generate comprehensive financial insights for this user. Analyze everything thoroughly and provide actionable recommendations."""

            model = genai.GenerativeModel(
                model_name=self.gemini_model,
                generation_config={
                    "temperature": 0.7,
                    "max_output_tokens": 8192,
                }
            )
            
            full_prompt = f"{system_prompt}\n\n{user_prompt}"
            response = model.generate_content(full_prompt)
            insights = response.text
            
            return insights
            
        except Exception as e:
            print(f"Error generating Gemini insights: {e}")
            import traceback
            traceback.print_exc()
            raise Exception(f"Failed to generate insights: {str(e)}")

    def _build_insight_context(self, user: Dict, summary: Dict, goals: List[Dict], transactions: List[Dict]) -> str:
        """Build comprehensive context for insight generation with multi-currency"""
        context = f"User: {user.get('name', 'User')}\n"
        context += f"Default Currency: {user.get('default_currency', 'usd').upper()}\n\n"
        
        # Multi-currency financial summary
        if summary.get("currencies"):
            context += "=== FINANCIAL OVERVIEW (BY CURRENCY) ===\n"
            for currency, data in summary["currencies"].items():
                currency_symbol = "$" if currency == "usd" else "K"
                currency_name = "USD" if currency == "usd" else "MMK"
                
                context += f"\n{currency_name}:\n"
                context += f"Total Balance: {currency_symbol}{data.get('balance', 0):.2f}\n"
                context += f"Total Income: {currency_symbol}{data.get('total_inflow', 0):.2f}\n"
                context += f"Total Expenses: {currency_symbol}{data.get('total_outflow', 0):.2f}\n"
                context += f"Total Transactions: {data.get('total_transactions', 0)}\n"
                context += f"Average Transaction: {currency_symbol}{data.get('avg_transaction_amount', 0):.2f}\n"
                
                if data.get('date_range'):
                    context += f"Data Period: {data['date_range'].get('from', 'N/A')[:10]} to {data['date_range'].get('to', 'N/A')[:10]}\n"
            
            context += "\n"
        
        # Goals summary by currency
        if goals:
            goals_by_currency = {}
            for g in goals:
                currency = g.get("currency", "usd")
                if currency not in goals_by_currency:
                    goals_by_currency[currency] = []
                goals_by_currency[currency].append(g)
            
            context += "=== FINANCIAL GOALS (BY CURRENCY) ===\n"
            for currency, curr_goals in goals_by_currency.items():
                currency_symbol = "$" if currency == "usd" else "K"
                currency_name = "USD" if currency == "usd" else "MMK"
                
                active_goals = [g for g in curr_goals if g["status"] == "active"]
                achieved_goals = [g for g in curr_goals if g["status"] == "achieved"]
                total_allocated = sum(g["current_amount"] for g in active_goals)
                total_target = sum(g["target_amount"] for g in active_goals)
                
                context += f"\n{currency_name} Goals:\n"
                context += f"Total Goals: {len(curr_goals)}\n"
                context += f"Active Goals: {len(active_goals)}\n"
                context += f"Achieved Goals: {len(achieved_goals)}\n"
                context += f"Total Allocated: {currency_symbol}{total_allocated:.2f}\n"
                context += f"Total Target: {currency_symbol}{total_target:.2f}\n"
                context += f"Overall Progress: {(total_allocated / total_target * 100) if total_target > 0 else 0:.1f}%\n\n"
                
                for goal in active_goals[:5]:
                    progress = (goal["current_amount"] / goal["target_amount"] * 100) if goal["target_amount"] > 0 else 0
                    context += f"Goal: {goal['name']}\n"
                    context += f"  Target: {currency_symbol}{goal['target_amount']:.2f}\n"
                    context += f"  Current: {currency_symbol}{goal['current_amount']:.2f}\n"
                    context += f"  Progress: {progress:.1f}%\n"
                    if goal.get("target_date"):
                        target_date = ensure_utc_datetime(goal["target_date"])
                        days_remaining = (target_date - datetime.now(timezone.utc)).days
                        context += f"  Days Remaining: {days_remaining}\n"
                    context += "\n"
        
        # Income/Expense Analysis by currency
        if summary.get("currencies"):
            for currency, data in summary["currencies"].items():
                currency_symbol = "$" if currency == "usd" else "K"
                currency_name = "USD" if currency == "usd" else "MMK"
                
                context += f"=== {currency_name} INCOME SOURCES ===\n"
                for cat, amount in list(data.get('top_inflow_categories', {}).items())[:10]:
                    context += f"{cat}: {currency_symbol}{amount:.2f}\n"
                context += "\n"
                
                context += f"=== {currency_name} EXPENSE CATEGORIES ===\n"
                for cat, amount in list(data.get('top_outflow_categories', {}).items())[:10]:
                    context += f"{cat}: {currency_symbol}{amount:.2f}\n"
                context += "\n"
                
                # Monthly Trends
                if data.get('monthly_data'):
                    context += f"=== {currency_name} MONTHLY TRENDS ===\n"
                    for month, month_data in sorted(data['monthly_data'].items(), reverse=True)[:6]:
                        net = month_data['inflow'] - month_data['outflow']
                        context += f"{month}:\n"
                        context += f"  Income: {currency_symbol}{month_data['inflow']:.2f}\n"
                        context += f"  Expenses: {currency_symbol}{month_data['outflow']:.2f}\n"
                        context += f"  Net: {currency_symbol}{net:.2f}\n"
                    context += "\n"
        
        # Recent Transactions (last 20, with currency)
        context += "=== RECENT TRANSACTIONS ===\n"
        for t in transactions[:20]:
            date_obj = ensure_utc_datetime(t["date"])
            currency = t.get("currency", "usd")
            currency_symbol = "$" if currency == "usd" else "K"
            currency_name = "USD" if currency == "usd" else "MMK"
            
            context += f"{date_obj.strftime('%Y-%m-%d')}: {t['type']} {currency_symbol}{t['amount']:.2f} ({currency_name}) - {t['main_category']} > {t['sub_category']}"
            if t.get('description'):
                context += f" ({t['description']})"
            context += "\n"
        
        return context


# Global Gemini chatbot instance
try:
    gemini_financial_chatbot = GeminiFinancialChatbot()
    print("✅ Gemini financial chatbot initialized successfully with Gemini + RAG + Goals")
except Exception as e:
    print(f"❌ Failed to initialize Gemini financial chatbot: {e}")
    gemini_financial_chatbot = None