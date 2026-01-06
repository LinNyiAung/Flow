import uuid
import os
from datetime import datetime, timedelta, UTC
from database import users_collection, insights_collection
from ai_chatbot import financial_chatbot, FinancialDataProcessor
from ai_chatbot_gemini import gemini_financial_chatbot
import logging

logger = logging.getLogger(__name__)

# Get API keys
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")


def get_week_date_range():
    """Get the start and end dates for the current week (Monday to Sunday)"""
    today = datetime.now(UTC)
    # Get the start of current week (Monday)
    days_since_monday = today.weekday()
    week_start = (today - timedelta(days=days_since_monday)).replace(hour=0, minute=0, second=0, microsecond=0)
    week_end = week_start + timedelta(days=6, hours=23, minutes=59, seconds=59)
    return week_start, week_end


def get_previous_week_date_range():
    """Get the start and end dates for the previous week"""
    week_start, _ = get_week_date_range()
    prev_week_end = week_start - timedelta(seconds=1)
    prev_week_start = prev_week_end - timedelta(days=6)
    prev_week_start = prev_week_start.replace(hour=0, minute=0, second=0, microsecond=0)
    return prev_week_start, prev_week_end


async def generate_weekly_insight(user_id: str, ai_provider: str = "openai"):
    """Generate weekly insight for a specific user"""
    try:
        # Select chatbot based on provider
        chatbot = gemini_financial_chatbot if ai_provider == "gemini" else financial_chatbot
        
        if chatbot is None:
            logger.error(f"Chatbot not available for provider: {ai_provider}")
            return None
        
        # Get date ranges
        week_start, week_end = get_week_date_range()
        prev_week_start, prev_week_end = get_previous_week_date_range()
        
        # Get user data
        user = users_collection.find_one({"_id": user_id})
        if not user:
            logger.error(f"User not found: {user_id}")
            return None
        
        # Get financial data processor
        processor = FinancialDataProcessor(user_id)
        
        # Get current week transactions
        current_week_transactions = processor.get_user_transactions()
        current_week_transactions = [
            t for t in current_week_transactions
            if week_start <= processor.ensure_utc_datetime(t["date"]) <= week_end
        ]
        
        # Get previous week transactions
        prev_week_transactions = processor.get_user_transactions()
        prev_week_transactions = [
            t for t in prev_week_transactions
            if prev_week_start <= processor.ensure_utc_datetime(t["date"]) <= prev_week_end
        ]
        
        # Get goals
        goals = processor.get_user_goals()
        
        # Get previous week's insight for comparison
        previous_insight = insights_collection.find_one(
            {"user_id": user_id, "ai_provider": ai_provider, "insight_type": "weekly"},
            sort=[("generated_at", -1)]
        )
        
        # Build context for weekly insights
        context = _build_weekly_context(
            user, 
            current_week_transactions, 
            prev_week_transactions,
            goals,
            week_start,
            week_end,
            previous_insight
        )
        
        # Generate insights using AI
        system_prompt = _build_weekly_system_prompt()
        
        from openai import AsyncOpenAI
        import google.generativeai as genai
        
        if ai_provider == "gemini":
            genai.configure(api_key=GOOGLE_API_KEY)
            model = genai.GenerativeModel(
                model_name=os.getenv("GEMINI_MODEL", "gemini-2.5-flash"),
                generation_config={
                    "temperature": 0.7,
                    "max_output_tokens": 8192,
                }
            )
            full_prompt = f"{system_prompt}\n\n{context}"
            response = model.generate_content(full_prompt)
            insights_content = response.text
        else:
            client = AsyncOpenAI(api_key=OPENAI_API_KEY)
            response = await client.chat.completions.create(
                model=chatbot.gpt_model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": context}
                ],
                temperature=0.7,
                max_tokens=2500
            )
            insights_content = response.choices[0].message.content
        
        # Save to database
        insight_id = str(uuid.uuid4())
        now = datetime.now(UTC)
        
        new_insight = {
            "_id": insight_id,
            "user_id": user_id,
            "content": insights_content,
            "content_mm": None,  # Can be generated later if needed
            "generated_at": now,
            "week_start": week_start,
            "week_end": week_end,
            "insight_type": "weekly",  # NEW field to identify weekly insights
            "ai_provider": ai_provider,
            "expires_at": None
        }
        
        insights_collection.insert_one(new_insight)
        
        logger.info(f"✅ Weekly insight generated for user {user_id} using {ai_provider}")
        return new_insight
        
    except Exception as e:
        logger.error(f"Error generating weekly insight for user {user_id}: {str(e)}")
        import traceback
        traceback.print_exc()
        return None


def _build_weekly_system_prompt():
    """Build system prompt for weekly insights generation"""
    return """You are Flow Finance AI, an expert financial analyst providing weekly financial insights.

Your task is to analyze the user's financial activity from the past week and generate a comprehensive weekly report.

WEEKLY INSIGHTS STRUCTURE:
Generate insights covering:

1. **📊 This Week's Summary** - Overview of financial activity this week
   - Total income and expenses by currency
   - Net position (surplus/deficit)
   - Number of transactions
   - Key highlights

2. **📈 Week-over-Week Comparison** - Compare with previous week
   - Income changes (increase/decrease %)
   - Expense changes (increase/decrease %)
   - Spending pattern shifts
   - Notable differences

3. **💰 Spending Analysis** - Where the money went this week
   - Top expense categories by currency
   - Unusual or high spending areas
   - Comparison with previous weeks
   - Budget adherence (if applicable)

4. **🎯 Goals Progress** - How goals advanced this week
   - Contributions made to goals by currency
   - Progress percentages
   - On-track vs. behind schedule analysis
   - Projected completion dates

5. **✨ Wins & Achievements** - Celebrate positive actions
   - Money saved
   - Goals reached
   - Good financial decisions
   - Positive habits noticed

6. **⚠️ Areas for Attention** - Concerns to address
   - Overspending categories
   - Budget overruns
   - Goals falling behind
   - Potential issues

7. **💡 Recommendations for Next Week** - Actionable advice
   - Specific spending adjustments by currency
   - Savings opportunities
   - Goal contribution suggestions
   - Habit changes to implement

8. **🎯 Weekly Challenge** - One specific goal for next week
   - Clear, measurable target
   - Motivational message

CRITICAL RULES:
- Be SPECIFIC with numbers, dates, categories, AND CURRENCIES
- Always compare with previous week when data is available
- Provide ACTIONABLE recommendations, not generic advice
- Be encouraging and supportive in tone
- Format money as $X.XX (USD) or X K (MMK)
- Use markdown formatting for clarity
- Add emojis for visual appeal
- Keep it concise but comprehensive (800-1200 words)
- Focus on the PAST WEEK's activity primarily
- If this is the first week, acknowledge it and provide baseline insights

Remember: This is a WEEKLY report focused on the week that just ended."""


def _build_weekly_context(
    user, 
    current_week_transactions, 
    prev_week_transactions,
    goals,
    week_start,
    week_end,
    previous_insight
):
    """Build context for weekly insights generation"""
    context = f"""USER: {user.get('name', 'User')}
DEFAULT CURRENCY: {user.get('default_currency', 'usd').upper()}

REPORTING PERIOD: {week_start.strftime('%B %d, %Y')} to {week_end.strftime('%B %d, %Y')}

=== THIS WEEK'S FINANCIAL ACTIVITY ===

Total Transactions: {len(current_week_transactions)}

"""
    
    # Group current week by currency
    current_by_currency = {}
    for t in current_week_transactions:
        currency = t.get("currency", "usd")
        if currency not in current_by_currency:
            current_by_currency[currency] = {"inflow": 0, "outflow": 0, "transactions": [], "categories": {}}
        
        current_by_currency[currency]["transactions"].append(t)
        if t["type"] == "inflow":
            current_by_currency[currency]["inflow"] += t["amount"]
        else:
            current_by_currency[currency]["outflow"] += t["amount"]
        
        # Track categories
        cat_key = f"{t['main_category']} > {t['sub_category']}"
        if cat_key not in current_by_currency[currency]["categories"]:
            current_by_currency[currency]["categories"][cat_key] = 0
        current_by_currency[currency]["categories"][cat_key] += t["amount"]
    
    for currency, data in current_by_currency.items():
        currency_symbol = "$" if currency == "usd" else "K"
        currency_name = "USD" if currency == "usd" else "MMK"
        
        context += f"\n{currency_name}:\n"
        context += f"  Income: {currency_symbol}{data['inflow']:.2f}\n"
        context += f"  Expenses: {currency_symbol}{data['outflow']:.2f}\n"
        context += f"  Net: {currency_symbol}{data['inflow'] - data['outflow']:.2f}\n"
        context += f"  Transactions: {len(data['transactions'])}\n"
        
        # Top spending categories
        context += f"\n  Top Spending Categories:\n"
        sorted_cats = sorted(data['categories'].items(), key=lambda x: x[1], reverse=True)
        for cat, amount in sorted_cats[:5]:
            context += f"    - {cat}: {currency_symbol}{amount:.2f}\n"
    
    # Previous week comparison
    if prev_week_transactions:
        context += "\n\n=== PREVIOUS WEEK COMPARISON ===\n\n"
        
        prev_by_currency = {}
        for t in prev_week_transactions:
            currency = t.get("currency", "usd")
            if currency not in prev_by_currency:
                prev_by_currency[currency] = {"inflow": 0, "outflow": 0}
            
            if t["type"] == "inflow":
                prev_by_currency[currency]["inflow"] += t["amount"]
            else:
                prev_by_currency[currency]["outflow"] += t["amount"]
        
        for currency in set(list(current_by_currency.keys()) + list(prev_by_currency.keys())):
            currency_symbol = "$" if currency == "usd" else "K"
            currency_name = "USD" if currency == "usd" else "MMK"
            
            current = current_by_currency.get(currency, {"inflow": 0, "outflow": 0})
            prev = prev_by_currency.get(currency, {"inflow": 0, "outflow": 0})
            
            income_change = ((current["inflow"] - prev["inflow"]) / prev["inflow"] * 100) if prev["inflow"] > 0 else 0
            expense_change = ((current["outflow"] - prev["outflow"]) / prev["outflow"] * 100) if prev["outflow"] > 0 else 0
            
            context += f"{currency_name}:\n"
            context += f"  Income: {currency_symbol}{prev['inflow']:.2f} → {currency_symbol}{current['inflow']:.2f} ({income_change:+.1f}%)\n"
            context += f"  Expenses: {currency_symbol}{prev['outflow']:.2f} → {currency_symbol}{current['outflow']:.2f} ({expense_change:+.1f}%)\n\n"
    
    # Goals progress
    if goals:
        context += "\n=== FINANCIAL GOALS STATUS ===\n\n"
        
        goals_by_currency = {}
        for g in goals:
            currency = g.get("currency", "usd")
            if currency not in goals_by_currency:
                goals_by_currency[currency] = []
            goals_by_currency[currency].append(g)
        
        for currency, curr_goals in goals_by_currency.items():
            currency_symbol = "$" if currency == "usd" else "K"
            currency_name = "USD" if currency == "usd" else "MMK"
            
            active_goals = [g for g in curr_goals if g["status"] == "active"]
            
            context += f"{currency_name} Goals:\n"
            for goal in active_goals[:5]:
                progress = (goal["current_amount"] / goal["target_amount"] * 100) if goal["target_amount"] > 0 else 0
                context += f"  - {goal['name']}: {currency_symbol}{goal['current_amount']:.2f} / {currency_symbol}{goal['target_amount']:.2f} ({progress:.1f}%)\n"
            context += "\n"
    
    # Previous insight summary (if exists)
    if previous_insight:
        context += "\n=== PREVIOUS WEEK'S KEY RECOMMENDATIONS ===\n"
        context += f"(Review to see if user followed through)\n\n"
        # Extract a brief summary from previous content if possible
        prev_content = previous_insight.get("content", "")
        if len(prev_content) > 500:
            context += prev_content[:500] + "...\n"
        else:
            context += prev_content + "\n"
    
    context += "\n\nGenerate a comprehensive weekly financial insight report based on the above data."
    
    return context


def generate_weekly_insights_for_all_users():
    """Generate weekly insights for all premium users"""
    logger.info("🔄 Starting weekly insights generation for all premium users...")
    
    # Find all premium users
    premium_users = users_collection.find({
        "subscription_type": "premium"
    })
    
    success_count = 0
    error_count = 0
    
    for user in premium_users:
        user_id = user["_id"]
        
        try:
            # Check subscription validity
            expires_at = user.get("subscription_expires_at")
            if expires_at and expires_at < datetime.now(UTC):
                logger.info(f"⏭️  Skipping user {user_id} - subscription expired")
                continue
            
            # Generate insights for both providers
            for provider in ["openai", "gemini"]:
                result = None
                try:
                    # Use sync wrapper for async function
                    import asyncio
                    result = asyncio.run(generate_weekly_insight(user_id, provider))
                    
                    if result:
                        success_count += 1
                        logger.info(f"✅ Generated {provider} weekly insight for user {user_id}")
                    else:
                        error_count += 1
                        logger.warning(f"⚠️ Failed to generate {provider} insight for user {user_id}")
                        
                except Exception as e:
                    error_count += 1
                    logger.error(f"❌ Error generating {provider} insight for user {user_id}: {str(e)}")
                    
        except Exception as e:
            error_count += 1
            logger.error(f"❌ Error processing user {user_id}: {str(e)}")
    
    logger.info(f"✅ Weekly insights generation completed: {success_count} successful, {error_count} errors")


async def translate_insight_to_myanmar(english_content: str, ai_provider: str = "openai") -> str:
    """Translate English insights to Myanmar language"""
    try:
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

        if ai_provider == "gemini":
            import google.generativeai as genai
            
            if not GOOGLE_API_KEY:
                raise Exception("Google API key not configured")
            
            genai.configure(api_key=GOOGLE_API_KEY)
            
            model = genai.GenerativeModel(
                model_name="gemini-2.5-pro",
                generation_config={
                    "temperature": 0.3,
                    "max_output_tokens": 8192,
                }
            )
            
            prompt = f"{system_prompt}\n\nTranslate this to Myanmar:\n\n{english_content}"
            response = model.generate_content(prompt)
            myanmar_content = response.text
            
        else:  # OpenAI
            from openai import AsyncOpenAI
            
            if not OPENAI_API_KEY:
                raise Exception("OpenAI API key not configured")
            
            client = AsyncOpenAI(api_key=OPENAI_API_KEY)
            
            response = await client.chat.completions.create(
                model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": f"Translate this to Myanmar:\n\n{english_content}"}
                ],
                temperature=0.3,
                max_tokens=3000
            )
            
            myanmar_content = response.choices[0].message.content
        
        return myanmar_content
        
    except Exception as e:
        logger.error(f"Translation error using {ai_provider}: {e}")
        raise Exception(f"Failed to translate insights: {str(e)}")