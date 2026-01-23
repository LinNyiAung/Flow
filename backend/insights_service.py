import uuid
import os
from datetime import datetime, timedelta, UTC
from notification_service import create_notification, notify_monthly_insights_generated, notify_weekly_insights_generated
from database import users_collection, insights_collection, budgets_collection
from ai_chatbot import financial_chatbot, FinancialDataProcessor
from ai_chatbot_gemini import gemini_financial_chatbot
import logging
from ai_usage_service import track_ai_usage
from ai_usage_models import AIFeatureType, AIProviderType

logger = logging.getLogger(__name__)

# Get API keys
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")


def get_week_date_range():
    """
    Get the start and end dates for the PREVIOUS week (Monday to Sunday)
    When run on Monday, this returns last week's Monday-Sunday
    """
    today = datetime.now(UTC)
    
    # Calculate last Monday (start of previous week)
    days_since_monday = today.weekday()  # Monday = 0, Sunday = 6
    
    # If today is Monday, go back 7 days to get last Monday
    # Otherwise, go back to last Monday
    if days_since_monday == 0:
        # It's Monday, so go back 7 days to last Monday
        week_start = (today - timedelta(days=7)).replace(hour=0, minute=0, second=0, microsecond=0)
    else:
        # Go back to the most recent Monday
        week_start = (today - timedelta(days=days_since_monday + 7)).replace(hour=0, minute=0, second=0, microsecond=0)
    
    # End of that week is Sunday
    week_end = (week_start + timedelta(days=6)).replace(hour=23, minute=59, second=59, microsecond=999999)
    
    return week_start, week_end


def get_previous_week_date_range():
    """
    Get the start and end dates for the week BEFORE the previous week
    (Two weeks ago: Monday to Sunday)
    """
    week_start, _ = get_week_date_range()
    
    # Go back one more week
    prev_week_start = (week_start - timedelta(days=7)).replace(hour=0, minute=0, second=0, microsecond=0)
    prev_week_end = (prev_week_start + timedelta(days=6)).replace(hour=23, minute=59, second=59, microsecond=999999)
    
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
        
        
        # Get budgets
        budgets = processor.get_user_budgets()
        
        # NEW: Check if user has any financial activity at all
        all_transactions = processor.get_user_transactions()
        has_activity = len(all_transactions) > 0 or len(goals) > 0 or len(budgets) > 0
        
        if not has_activity:
            logger.info(f"ℹ️  No financial activity found for user {user_id}, returning placeholder insight")
            # Return a placeholder insight without calling AI
            insight_id = str(uuid.uuid4())
            now = datetime.now(UTC)
            
            placeholder_content = """## 👋 Welcome to Flow Finance!

### 🎯 Get Started with Your Financial Journey

It looks like you're just getting started with Flow Finance. To generate personalized AI insights, you'll need to add some financial activities first.

### 📊 What to Add:

**💰 Transactions**
- Add your income and expenses
- Record your daily spending
- Track where your money goes

**🎯 Financial Goals**
- Set savings targets
- Plan for future purchases
- Track your progress

### ✨ What You'll Get:

Once you add your financial data, our AI will analyze your spending patterns and provide:
- **📈 Spending Analysis** - Understand where your money goes
- **💡 Personalized Recommendations** - Get actionable advice
- **🎯 Goal Progress** - Track your financial goals
- **⚠️ Alerts** - Stay informed about your finances
- **📊 Weekly Insights** - Regular financial health reports

### 🚀 Ready to Begin?

Start by adding your first transaction or creating a financial goal. The more data you provide, the better insights you'll receive!

---
*Your financial journey starts here. Let's make it count!* 💪"""
            
            new_insight = {
                "_id": insight_id,
                "user_id": user_id,
                "content": placeholder_content,
                "content_mm": None,
                "generated_at": now,
                "week_start": week_start,
                "week_end": week_end,
                "insight_type": "weekly",
                "ai_provider": ai_provider,
                "expires_at": None,
                "is_placeholder": True  # NEW: Flag to indicate this is a placeholder
            }
            
            insights_collection.insert_one(new_insight)
            return new_insight
        
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
            budgets,
            week_start,
            week_end,
            previous_insight
        )
        
        # Generate insights using AI
        system_prompt = _build_weekly_system_prompt()
        
        from openai import AsyncOpenAI
        from google import genai
        
        # NEW: Variables to track token usage
        input_tokens = 0
        output_tokens = 0
        total_tokens = 0
        
        if ai_provider == "gemini":
            client = genai.Client(api_key=GOOGLE_API_KEY)
            
            full_prompt = f"{system_prompt}\n\n{context}"
            
            response = client.models.generate_content(
                model=os.getenv("GEMINI_MODEL", "gemini-2.5-flash"),
                contents=full_prompt,
                config={
                    "temperature": 0.7,
                    "max_output_tokens": 8192,
                }
            )
            insights_content = response.text
            
            # NEW: Extract token usage from Gemini response
            if hasattr(response, 'usage_metadata'):
                input_tokens = getattr(response.usage_metadata, 'prompt_token_count', 0)
                output_tokens = getattr(response.usage_metadata, 'candidates_token_count', 0)
                total_tokens = getattr(response.usage_metadata, 'total_token_count', 0)
                
                logger.info(f"🔢 [GEMINI TOKEN USAGE - Weekly Insight] User: {user_id}")
                logger.info(f"   📥 Input tokens: {input_tokens:,}")
                logger.info(f"   📤 Output tokens: {output_tokens:,}")
                logger.info(f"   📊 Total tokens: {total_tokens:,}")

                # NEW: Track usage
                track_ai_usage(
                    user_id=user_id,
                    feature_type=AIFeatureType.WEEKLY_INSIGHT,
                    provider=AIProviderType.GEMINI,
                    model_name=os.getenv("GEMINI_MODEL", "gemini-2.5-flash"),
                    input_tokens=input_tokens,
                    output_tokens=output_tokens,
                    total_tokens=total_tokens
                )
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
            
            # NEW: Extract token usage from OpenAI response
            if hasattr(response, 'usage'):
                input_tokens = response.usage.prompt_tokens
                output_tokens = response.usage.completion_tokens
                total_tokens = response.usage.total_tokens
                
                logger.info(f"🔢 [OPENAI TOKEN USAGE - Weekly Insight] User: {user_id}")
                logger.info(f"   📥 Input tokens: {input_tokens:,}")
                logger.info(f"   📤 Output tokens: {output_tokens:,}")
                logger.info(f"   📊 Total tokens: {total_tokens:,}")
                logger.info(f"   🤖 Model: {chatbot.gpt_model}")

                # NEW: Track usage
                track_ai_usage(
                    user_id=user_id,
                    feature_type=AIFeatureType.WEEKLY_INSIGHT,
                    provider=AIProviderType.OPENAI,
                    model_name=chatbot.gpt_model,
                    input_tokens=input_tokens,
                    output_tokens=output_tokens,
                    total_tokens=total_tokens
                )
        
        # Save to database
        insight_id = str(uuid.uuid4())
        now = datetime.now(UTC)
        
        new_insight = {
            "_id": insight_id,
            "user_id": user_id,
            "content": insights_content,
            "content_mm": None,
            "generated_at": now,
            "week_start": week_start,
            "week_end": week_end,
            "insight_type": "weekly",
            "ai_provider": ai_provider,
            "expires_at": None,
            "is_placeholder": False,  # NEW: Flag to indicate this is real AI content
            # NEW: Store token usage
            "token_usage": {
                "input_tokens": input_tokens,
                "output_tokens": output_tokens,
                "total_tokens": total_tokens
            }
        }
        
        insights_collection.insert_one(new_insight)
        
        # Notify user that weekly insights are ready
        notify_weekly_insights_generated(user_id)
        
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

1. **📊 Last Week's Summary** - Overview of financial activity last week
   - Total income and expenses by currency
   - Net position (surplus/deficit)
   - Number of transactions
   - Key highlights

2. **📈 Week-over-Week Comparison** - Compare with the week before
   - Income changes (increase/decrease %)
   - Expense changes (increase/decrease %)
   - Spending pattern shifts
   - Notable differences

3. **💰 Spending Analysis** - Where the money went last week
   - Top expense categories by currency
   - Unusual or high spending areas
   - Comparison with previous weeks
   - Budget adherence (if applicable)

4. **📊 Budget Performance** - How budgets are tracking 
   - Overall budget utilization by currency
   - Categories over/under budget
   - Budget adherence trends
   - Recommendations for staying on track

5. **🎯 Goals Progress** - How goals advanced last week
   - Contributions made to goals by currency
   - Progress percentages
   - On-track vs. behind schedule analysis
   - Projected completion dates

6. **✨ Wins & Achievements** - Celebrate positive actions
   - Money saved
   - Goals reached
   - Budget adherence successes 
   - Good financial decisions
   - Positive habits noticed

7. **⚠️ Areas for Attention** - Concerns to address
   - Overspending categories
   - Budget overruns
   - Goals falling behind
   - Potential issues

8. **💡 Recommendations for This Week** - Actionable advice
   - Specific spending adjustments by currency
   - Budget corrections needed
   - Savings opportunities
   - Goal contribution suggestions
   - Habit changes to implement

9. **🎯 Weekly Challenge** - One specific goal for this week
   - Clear, measurable target
   - Motivational message

CRITICAL RULES:
- Be SPECIFIC with numbers, dates, categories, AND CURRENCIES
- Always compare with the week before when data is available
- Pay special attention to budget performance and adherence 
- Celebrate when users stay within budget 
- Provide ACTIONABLE recommendations, not generic advice
- Be encouraging and supportive in tone
- Format money as $X.XX (USD), X K (MMK), or ฿X.XX (THB)
- Use markdown formatting for clarity
- Add emojis for visual appeal
- Keep it concise but comprehensive (800-1200 words)
- Focus on LAST WEEK's activity (the complete Monday-Sunday that just ended)
- Provide recommendations for THIS WEEK (the new week that just started)
- If this is the first week, acknowledge it and provide baseline insights

Remember: This report is generated on Monday morning, reviewing the complete week (Monday-Sunday) that just ended, and providing actionable recommendations for the week ahead."""


def _build_weekly_context(
    user, 
    current_week_transactions, 
    prev_week_transactions,
    goals,
    budgets,
    week_start,
    week_end,
    previous_insight
):
    """Build context for weekly insights generation"""
    context = f"""USER: {user.get('name', 'User')}
DEFAULT CURRENCY: {user.get('default_currency', 'usd').upper()}

TODAY: {datetime.now(UTC).strftime('%A, %B %d, %Y')} (Monday Morning)

LAST WEEK'S PERIOD: {week_start.strftime('%B %d, %Y')} (Monday) to {week_end.strftime('%B %d, %Y')} (Sunday)

=== LAST WEEK'S FINANCIAL ACTIVITY ===

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
        currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
        currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")
        
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
        context += "\n\n=== WEEK BEFORE LAST COMPARISON ===\n\n"
        
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
            currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
            currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")
            
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
            currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
            currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")
            
            active_goals = [g for g in curr_goals if g["status"] == "active"]
            
            context += f"{currency_name} Goals:\n"
            for goal in active_goals[:5]:
                progress = (goal["current_amount"] / goal["target_amount"] * 100) if goal["target_amount"] > 0 else 0
                context += f"  - {goal['name']}: {currency_symbol}{goal['current_amount']:.2f} / {currency_symbol}{goal['target_amount']:.2f} ({progress:.1f}%)\n"
            context += "\n"
            
            
    # Budgets progress
    if budgets:
        context += "\n=== ACTIVE BUDGETS ===\n\n"
        
        budgets_by_currency = {}
        for b in budgets:
            currency = b.get("currency", "usd")
            if currency not in budgets_by_currency:
                budgets_by_currency[currency] = []
            budgets_by_currency[currency].append(b)
        
        for currency, curr_budgets in budgets_by_currency.items():
            currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
            currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")
            
            context += f"{currency_name} Budgets:\n"
            for budget in curr_budgets:
                utilization = budget.get("percentage_used", 0)
                status_emoji = "✅" if utilization < 80 else "⚠️" if utilization < 100 else "🚨"
                
                context += f"  {status_emoji} {budget['name']} ({budget['period']}):\n"
                context += f"     Total: {currency_symbol}{budget['total_spent']:.2f} / {currency_symbol}{budget['total_budget']:.2f} ({utilization:.1f}%)\n"
                
                # Show category breakdowns
                for cat_budget in budget['category_budgets'][:5]:  # Top 5 categories
                    cat_util = cat_budget.get('percentage_used', 0)
                    context += f"       - {cat_budget['main_category']}: {currency_symbol}{cat_budget['spent_amount']:.2f} / {currency_symbol}{cat_budget['allocated_amount']:.2f} ({cat_util:.1f}%)\n"
                
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


async def translate_insight_to_myanmar(english_content: str, ai_provider: str = "openai", user_id: str = None) -> str:
    """Translate English insights to Myanmar language"""
    try:
                # NEW: Check if this is a placeholder insight by checking for the welcome message
        is_placeholder = "Welcome to Flow Finance!" in english_content and "Get Started with Your Financial Journey" in english_content
        
        if is_placeholder:
            # Return Myanmar placeholder without calling AI API
            logger.info("Returning Myanmar placeholder for new user")
            myanmar_placeholder = """## 👋 Flow Finance မှ ကြိုဆိုပါတယ်!

### 🎯 သင့်ရဲ့ ငွေကြေးခရီးစဉ်ကို စတင်ပါ

Flow Finance နဲ့ စတင်အသုံးပြုနေပုံရပါတယ်။ AI မှ ပုဂ္ဂိုလ်ရေးအရ ဆန်းစစ်ချက်များ ရရှိရန် ပထမဆုံး သင့်ရဲ့ ငွေကြေးလှုပ်ရှားမှုများကို ထည့်သွင်းဖို့ လိုအပ်ပါတယ်။

### 📊 ထည့်သွင်းရမည့် အရာများ:

**💰 ငွေသွင်းထုတ်မှတ်တမ်းများ**
- ၀င်ငွေနှင့် အသုံးစရိတ်များ ထည့်သွင်းပါ
- နေ့စဉ် အသုံးစရိတ်များကို မှတ်တမ်းတင်ပါ
- သင့်ငွေ ဘယ်မှာသွားသလဲ ခြေရာခံပါ

**🎯 ငွေကြေး ရည်မှန်းချက်များ**
- ချွေတာမှု ပန်းတိုင်များ သတ်မှတ်ပါ
- အနာဂတ် ဝယ်ယူမှုများ စီစဉ်ပါ
- သင့်တိုးတက်မှုကို ခြေရာခံပါ

### ✨ သင်ရရှိမည့် အရာများ:

သင့်ရဲ့ ငွေကြေးအချက်အလက်များ ထည့်သွင်းပြီးသည်နှင့် ကျွန်ုပ်တို့၏ AI က သင့်အသုံးစရိတ် ပုံစံများကို ဆန်းစစ်ပြီး အောက်ပါအရာများ ပေးအပ်မည်:
- **📈 အသုံးစရိတ် ခွဲခြမ်းစိတ်ဖြာမှု** - သင့်ငွေ ဘယ်မှာသွားသလဲ နားလည်ပါ
- **💡 ပုဂ္ဂိုလ်ရေးအကြံပြုချက်များ** - လုပ်ဆောင်နိုင်သော အကြံဉာဏ်များ ရယူပါ
- **🎯 ပန်းတိုင် တိုးတက်မှု** - သင့်ငွေကြေး ရည်မှန်းချက်များကို ခြေရာခံပါ
- **⚠️ သတိပေးချက်များ** - သင့်ငွေကြေးအကြောင်း သတင်းအချက်အလက်များ ရယူပါ
- **📊 အပတ်စဉ် ဆန်းစစ်ချက်များ** - ပုံမှန် ငွေကြေးကျန်းမာရေး အစီရင်ခံစာများ

### 🚀 စတင်ရန် အသင့်ပြင်ပြီလား?

သင့်ပထမဆုံး ငွေသွင်းထုတ်မှတ်တမ်းကို ထည့်သွင်းခြင်း သို့မဟုတ် ငွေကြေး ရည်မှန်းချက်တစ်ခု ဖန်တီးခြင်းဖြင့် စတင်ပါ။ သင် ပေးသော အချက်အလက်များ များလေ၊ ပိုမိုကောင်းမွန်သော ဆန်းစစ်ချက်များ ရရှိမည် ဖြစ်ပါတယ်!

---
*သင့်ငွေကြေး ခရီးစဉ် ဤနေရာမှ စတင်ပါသည်။ အောင်မြင်အောင် လုပ်ကြပါစို့!* 💪"""
            return myanmar_placeholder
        
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
- Income: ဝင်ငွေ
- Expenses: ကုန်ကျစရိတ်
- Savings: စုဆောင်းငွေ
- Budget: ဘတ်ဂျက်
- Goals: ရည်မှန်းချက်များ
- Transaction: ငွေသွင်းထုတ်

Translate naturally while keeping the professional yet friendly tone."""

        if ai_provider == "gemini":
            from google import genai
            
            if not GOOGLE_API_KEY:
                raise Exception("Google API key not configured")
            
            # NEW: Using google.genai instead of google.generativeai
            client = genai.Client(api_key=GOOGLE_API_KEY)
            
            prompt = f"{system_prompt}\n\nTranslate this to Myanmar:\n\n{english_content}"
            
            response = client.models.generate_content(
                model="gemini-2.5-pro",
                contents=prompt,
                config={
                    "temperature": 0.3,
                    "max_output_tokens": 8192,
                }
            )
            
            myanmar_content = response.text


            # NEW: Track translation usage
            if hasattr(response, 'usage_metadata'):
                input_tokens = getattr(response.usage_metadata, 'prompt_token_count', 0)
                output_tokens = getattr(response.usage_metadata, 'candidates_token_count', 0)
                total_tokens = getattr(response.usage_metadata, 'total_token_count', 0)
                
                # Get user_id from the insight being translated
                # You'll need to pass user_id to this function
                track_ai_usage(
                    user_id=user_id,  # Add user_id parameter to function
                    feature_type=AIFeatureType.TRANSLATION,
                    provider=AIProviderType.GEMINI,
                    model_name="gemini-2.5-pro",
                    input_tokens=input_tokens,
                    output_tokens=output_tokens,
                    total_tokens=total_tokens
                )
            
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


            # NEW: Track translation usage
            if hasattr(response, 'usage'):
                input_tokens = response.usage.prompt_tokens
                output_tokens = response.usage.completion_tokens
                total_tokens = response.usage.total_tokens
                
                track_ai_usage(
                    user_id=user_id,  # Add user_id parameter to function
                    feature_type=AIFeatureType.TRANSLATION,
                    provider=AIProviderType.OPENAI,
                    model_name=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
                    input_tokens=input_tokens,
                    output_tokens=output_tokens,
                    total_tokens=total_tokens
                )
        
        return myanmar_content
        
    except Exception as e:
        logger.error(f"Translation error using {ai_provider}: {e}")
        raise Exception(f"Failed to translate insights: {str(e)}")
    
    
def get_month_date_range():
    """
    Get the start and end dates for the PREVIOUS month
    When run on the 1st, this returns last month's range
    """
    today = datetime.now(UTC)
    
    # Get first day of current month
    current_month_start = today.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    
    # Get last month's start (go back one month)
    if current_month_start.month == 1:
        month_start = current_month_start.replace(year=current_month_start.year - 1, month=12)
    else:
        month_start = current_month_start.replace(month=current_month_start.month - 1)
    
    # Get last day of that month (which is day before current month starts)
    month_end = (current_month_start - timedelta(days=1)).replace(hour=23, minute=59, second=59, microsecond=999999)
    
    return month_start, month_end


def get_previous_month_date_range():
    """
    Get the start and end dates for the month BEFORE the previous month
    (Two months ago)
    """
    month_start, _ = get_month_date_range()
    
    # Go back one more month
    if month_start.month == 1:
        prev_month_start = month_start.replace(year=month_start.year - 1, month=12)
    else:
        prev_month_start = month_start.replace(month=month_start.month - 1)
    
    # Get last day of that month
    prev_month_end = (month_start - timedelta(days=1)).replace(hour=23, minute=59, second=59, microsecond=999999)
    
    return prev_month_start, prev_month_end


async def generate_monthly_insight(user_id: str, ai_provider: str = "openai"):
    """Generate monthly insight for a specific user"""
    try:
        # Select chatbot based on provider
        chatbot = gemini_financial_chatbot if ai_provider == "gemini" else financial_chatbot
        
        if chatbot is None:
            logger.error(f"Chatbot not available for provider: {ai_provider}")
            return None
        
        # Get date ranges
        month_start, month_end = get_month_date_range()
        prev_month_start, prev_month_end = get_previous_month_date_range()
        
        # Get user data
        user = users_collection.find_one({"_id": user_id})
        if not user:
            logger.error(f"User not found: {user_id}")
            return None
        
        # Get financial data processor
        processor = FinancialDataProcessor(user_id)
        
        # Get current month transactions
        current_month_transactions = processor.get_user_transactions()
        current_month_transactions = [
            t for t in current_month_transactions
            if month_start <= processor.ensure_utc_datetime(t["date"]) <= month_end
        ]
        
        # Get previous month transactions
        prev_month_transactions = processor.get_user_transactions()
        prev_month_transactions = [
            t for t in prev_month_transactions
            if prev_month_start <= processor.ensure_utc_datetime(t["date"]) <= prev_month_end
        ]
        
        # Get goals
        goals = processor.get_user_goals()
        
        
        # Get budgets
        budgets = processor.get_user_budgets()
        
        
        # NEW: Check if user has any financial activity at all
        all_transactions = processor.get_user_transactions()
        has_activity = len(all_transactions) > 0 or len(goals) > 0 or len(budgets) > 0
        
        if not has_activity:
            logger.info(f"ℹ️  No financial activity found for user {user_id}, returning placeholder insight")
            # Return a placeholder insight without calling AI
            insight_id = str(uuid.uuid4())
            now = datetime.now(UTC)
            
            placeholder_content = """## 👋 Welcome to Flow Finance!

### 🎯 Get Started with Your Financial Journey

It looks like you're just getting started with Flow Finance. To generate personalized monthly AI insights, you'll need to add some financial activities first.

### 📊 What to Add:

**💰 Transactions**
- Add your income and expenses
- Record your daily spending
- Track where your money goes

**🎯 Financial Goals**
- Set savings targets
- Plan for future purchases
- Track your progress

### ✨ What You'll Get in Monthly Reports:

Once you add your financial data, our AI will provide comprehensive monthly analysis including:
- **📈 Month-over-Month Comparison** - Track your financial trends
- **💰 Spending Deep Dive** - Detailed expense breakdown
- **🎯 Goals Progress** - Monthly achievement tracking
- **📊 Financial Health Score** - Overall assessment
- **💡 Action Plan** - Specific recommendations for the month
- **🏆 Wins & Achievements** - Celebrate your success

### 🚀 Ready to Begin?

Start by adding your first transaction or creating a financial goal. The more data you provide, the better insights you'll receive!

---
*Your financial journey starts here. Let's make it count!* 💪"""
            
            new_insight = {
                "_id": insight_id,
                "user_id": user_id,
                "content": placeholder_content,
                "content_mm": None,
                "generated_at": now,
                "month_start": month_start,
                "month_end": month_end,
                "insight_type": "monthly",
                "ai_provider": ai_provider,
                "expires_at": None,
                "is_placeholder": True  # NEW: Flag to indicate this is a placeholder
            }
            
            insights_collection.insert_one(new_insight)
            return new_insight
        
        # Get previous month's insight for comparison
        previous_insight = insights_collection.find_one(
            {"user_id": user_id, "ai_provider": ai_provider, "insight_type": "monthly"},
            sort=[("generated_at", -1)]
        )
        
        # Build context for monthly insights
        context = _build_monthly_context(
            user, 
            current_month_transactions, 
            prev_month_transactions,
            goals,
            budgets,
            month_start,
            month_end,
            previous_insight
        )
        
        # Generate insights using AI
        system_prompt = _build_monthly_system_prompt()
        
        from openai import AsyncOpenAI
        from google import genai
        
        if ai_provider == "gemini":
            client = genai.Client(api_key=GOOGLE_API_KEY)
            
            full_prompt = f"{system_prompt}\n\n{context}"
            
            response = client.models.generate_content(
                model=os.getenv("GEMINI_MODEL", "gemini-2.5-flash"),
                contents=full_prompt,
                config={
                    "temperature": 0.7,
                    "max_output_tokens": 8192,
                }
            )
            insights_content = response.text


            # NEW: Track usage
            if hasattr(response, 'usage_metadata'):
                input_tokens = getattr(response.usage_metadata, 'prompt_token_count', 0)
                output_tokens = getattr(response.usage_metadata, 'candidates_token_count', 0)
                total_tokens = getattr(response.usage_metadata, 'total_token_count', 0)
                
                track_ai_usage(
                    user_id=user_id,
                    feature_type=AIFeatureType.MONTHLY_INSIGHT,
                    provider=AIProviderType.GEMINI,
                    model_name=os.getenv("GEMINI_MODEL", "gemini-2.5-flash"),
                    input_tokens=input_tokens,
                    output_tokens=output_tokens,
                    total_tokens=total_tokens
                )
        else:
            client = AsyncOpenAI(api_key=OPENAI_API_KEY)
            response = await client.chat.completions.create(
                model=chatbot.gpt_model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": context}
                ],
                temperature=0.7,
                max_tokens=3000
            )
            insights_content = response.choices[0].message.content


            # NEW: Track usage
            if hasattr(response, 'usage'):
                input_tokens = response.usage.prompt_tokens
                output_tokens = response.usage.completion_tokens
                total_tokens = response.usage.total_tokens
                
                track_ai_usage(
                    user_id=user_id,
                    feature_type=AIFeatureType.MONTHLY_INSIGHT,
                    provider=AIProviderType.OPENAI,
                    model_name=chatbot.gpt_model,
                    input_tokens=input_tokens,
                    output_tokens=output_tokens,
                    total_tokens=total_tokens
                )
        
        # Save to database
        insight_id = str(uuid.uuid4())
        now = datetime.now(UTC)
        
        new_insight = {
            "_id": insight_id,
            "user_id": user_id,
            "content": insights_content,
            "content_mm": None,
            "generated_at": now,
            "month_start": month_start,
            "month_end": month_end,
            "insight_type": "monthly",
            "ai_provider": ai_provider,
            "expires_at": None,
            "is_placeholder": False  # NEW: Flag to indicate this is real AI content
        }
        
        insights_collection.insert_one(new_insight)
        
        # Notify user that monthly insights are ready
        notify_monthly_insights_generated(user_id)
        
        logger.info(f"✅ Monthly insight generated for user {user_id} using {ai_provider}")
        return new_insight
        
    except Exception as e:
        logger.error(f"Error generating monthly insight for user {user_id}: {str(e)}")
        import traceback
        traceback.print_exc()
        return None


def _build_monthly_system_prompt():
    """Build system prompt for monthly insights generation"""
    return """You are Flow Finance AI, an expert financial analyst providing monthly financial insights.

Your task is to analyze the user's financial activity from the past month and generate a comprehensive monthly report.

MONTHLY INSIGHTS STRUCTURE:
Generate insights covering:

1. **📊 Last Month's Summary** - Complete overview of the month
   - Total income and expenses by currency
   - Net position (surplus/deficit)
   - Number of transactions
   - Key highlights and milestones

2. **📈 Month-over-Month Comparison** - Compare with the previous month
   - Income changes (increase/decrease %)
   - Expense changes (increase/decrease %)
   - Spending pattern shifts
   - Notable differences and trends

3. **💰 Spending Deep Dive** - Detailed expense analysis
   - Top expense categories by currency
   - Category breakdowns and percentages
   - Unusual or high spending areas
   - Month-to-month category changes
   - Budget adherence (if applicable)

4. **📊 Budget Performance Review** - Comprehensive budget analysis 
   - Overall budget utilization by currency
   - Category-level performance
   - Over/under spending trends
   - Month-over-month budget adherence
   - Budget efficiency recommendations

5. **🎯 Goals Progress** - Monthly goal achievements
   - Contributions made to goals by currency
   - Progress percentages and amounts
   - Goals completed or reached
   - On-track vs. behind schedule analysis
   - Projected completion timeline

6. **✨ Monthly Wins & Achievements** - Celebrate success
   - Money saved last month
   - Budget adherence successes 
   - Goals reached or significant progress
   - Good financial decisions
   - Positive habits established

7. **⚠️ Areas Needing Attention** - Financial concerns
   - Overspending categories
   - Budget overruns 
   - Goals falling behind
   - Concerning trends
   - Potential issues to address

8. **📊 Financial Health Score** - Overall assessment
   - Income stability
   - Expense control
   - Budget adherence 
   - Savings rate
   - Goal progress
   - Overall financial trajectory

9. **💡 Action Plan for This Month** - Specific recommendations
   - Spending adjustments by currency
   - Budget reallocations needed 
   - Savings targets
   - Goal contribution plans
   - Budget recommendations
   - Habit changes to implement

10. **🎯 Monthly Challenge** - One major goal for this month
    - Clear, measurable target
    - Actionable steps
    - Motivational message

CRITICAL RULES:
- Be VERY SPECIFIC with numbers, dates, categories, AND CURRENCIES
- Always compare with the previous month when data is available
- Analyze budget performance in detail 
- Provide specific budget adjustment recommendations 
- Provide DETAILED and ACTIONABLE recommendations
- Be encouraging yet realistic in tone
- Format money as $X.XX (USD), X K (MMK), or ฿X.XX (THB)
- Use markdown formatting for clarity
- Add emojis for visual appeal
- Keep it comprehensive but readable (1000-1500 words)
- Focus on LAST MONTH's complete activity (1st to last day of month)
- Provide detailed action plan for THIS MONTH (the new month starting)
- If this is the first month, acknowledge it and provide baseline insights

Remember: This report is generated on the 1st of the month, reviewing the complete previous month, and providing a detailed action plan for the month ahead."""


def _build_monthly_context(
    user, 
    current_month_transactions, 
    prev_month_transactions,
    goals,
    budgets,
    month_start,
    month_end,
    previous_insight
):
    """Build context for monthly insights generation"""
    context = f"""USER: {user.get('name', 'User')}
DEFAULT CURRENCY: {user.get('default_currency', 'usd').upper()}

TODAY: {datetime.now(UTC).strftime('%A, %B %d, %Y')} (1st of the Month)

LAST MONTH'S PERIOD: {month_start.strftime('%B %d, %Y')} to {month_end.strftime('%B %d, %Y')}

=== LAST MONTH'S FINANCIAL ACTIVITY ===

Total Transactions: {len(current_month_transactions)}

"""
    
    # Group current month by currency
    current_by_currency = {}
    for t in current_month_transactions:
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
        currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
        currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")
        
        context += f"\n{currency_name}:\n"
        context += f"  Income: {currency_symbol}{data['inflow']:.2f}\n"
        context += f"  Expenses: {currency_symbol}{data['outflow']:.2f}\n"
        context += f"  Net: {currency_symbol}{data['inflow'] - data['outflow']:.2f}\n"
        context += f"  Transactions: {len(data['transactions'])}\n"
        
        # Top spending categories
        context += f"\n  Top Spending Categories:\n"
        sorted_cats = sorted(data['categories'].items(), key=lambda x: x[1], reverse=True)
        for cat, amount in sorted_cats[:10]:  # Show more categories for monthly
            context += f"    - {cat}: {currency_symbol}{amount:.2f}\n"
    
    # Previous month comparison
    if prev_month_transactions:
        context += "\n\n=== PREVIOUS MONTH COMPARISON ===\n\n"
        
        prev_by_currency = {}
        for t in prev_month_transactions:
            currency = t.get("currency", "usd")
            if currency not in prev_by_currency:
                prev_by_currency[currency] = {"inflow": 0, "outflow": 0}
            
            if t["type"] == "inflow":
                prev_by_currency[currency]["inflow"] += t["amount"]
            else:
                prev_by_currency[currency]["outflow"] += t["amount"]
        
        for currency in set(list(current_by_currency.keys()) + list(prev_by_currency.keys())):
            currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
            currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")
            
            current = current_by_currency.get(currency, {"inflow": 0, "outflow": 0})
            prev = prev_by_currency.get(currency, {"inflow": 0, "outflow": 0})
            
            income_change = ((current["inflow"] - prev["inflow"]) / prev["inflow"] * 100) if prev["inflow"] > 0 else 0
            expense_change = ((current["outflow"] - prev["outflow"]) / prev["outflow"] * 100) if prev["outflow"] > 0 else 0
            
            context += f"{currency_name}:\n"
            context += f"  Income: {currency_symbol}{prev['inflow']:.2f} → {currency_symbol}{current['inflow']:.2f} ({income_change:+.1f}%)\n"
            context += f"  Expenses: {currency_symbol}{prev['outflow']:.2f} → {currency_symbol}{current['outflow']:.2f} ({expense_change:+.1f}%)\n\n"
    
    # Goals progress (same as weekly)
    if goals:
        context += "\n=== FINANCIAL GOALS STATUS ===\n\n"
        
        goals_by_currency = {}
        for g in goals:
            currency = g.get("currency", "usd")
            if currency not in goals_by_currency:
                goals_by_currency[currency] = []
            goals_by_currency[currency].append(g)
        
        for currency, curr_goals in goals_by_currency.items():
            currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
            currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")
            
            active_goals = [g for g in curr_goals if g["status"] == "active"]
            
            context += f"{currency_name} Goals:\n"
            for goal in active_goals[:5]:
                progress = (goal["current_amount"] / goal["target_amount"] * 100) if goal["target_amount"] > 0 else 0
                context += f"  - {goal['name']}: {currency_symbol}{goal['current_amount']:.2f} / {currency_symbol}{goal['target_amount']:.2f} ({progress:.1f}%)\n"
            context += "\n"
            
            
        
    ## Budgets progress
    if budgets:
        context += "\n=== ACTIVE BUDGETS ===\n\n"
        
        budgets_by_currency = {}
        for b in budgets:
            currency = b.get("currency", "usd")
            if currency not in budgets_by_currency:
                budgets_by_currency[currency] = []
            budgets_by_currency[currency].append(b)
        
        for currency, curr_budgets in budgets_by_currency.items():
            currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
            currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")
            
            context += f"{currency_name} Budgets:\n"
            for budget in curr_budgets:
                utilization = budget.get("percentage_used", 0)
                status_emoji = "✅" if utilization < 80 else "⚠️" if utilization < 100 else "🚨"
                
                context += f"  {status_emoji} {budget['name']} ({budget['period']}):\n"
                context += f"     Total: {currency_symbol}{budget['total_spent']:.2f} / {currency_symbol}{budget['total_budget']:.2f} ({utilization:.1f}%)\n"
                
                for cat_budget in budget['category_budgets'][:8]:  # More categories for monthly
                    cat_util = cat_budget.get('percentage_used', 0)
                    context += f"       - {cat_budget['main_category']}: {currency_symbol}{cat_budget['spent_amount']:.2f} / {currency_symbol}{cat_budget['allocated_amount']:.2f} ({cat_util:.1f}%)\n"
                
                context += "\n"
    
    # Previous insight summary
    if previous_insight:
        context += "\n=== PREVIOUS MONTH'S KEY RECOMMENDATIONS ===\n"
        context += f"(Review to see if user followed through)\n\n"
        prev_content = previous_insight.get("content", "")
        if len(prev_content) > 500:
            context += prev_content[:500] + "...\n"
        else:
            context += prev_content + "\n"
    
    context += "\n\nGenerate a comprehensive monthly financial insight report based on the above data."
    
    return context


def generate_monthly_insights_for_all_users():
    """Generate monthly insights for all premium users"""
    logger.info("📅 Starting monthly insights generation for all premium users...")
    
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
                logger.info(f"⏭️ Skipping user {user_id} - subscription expired")
                continue
            
            # Generate insights for both providers
            for provider in ["openai", "gemini"]:
                result = None
                try:
                    import asyncio
                    result = asyncio.run(generate_monthly_insight(user_id, provider))
                    
                    if result:
                        success_count += 1
                        logger.info(f"✅ Generated {provider} monthly insight for user {user_id}")
                    else:
                        error_count += 1
                        logger.warning(f"⚠️ Failed to generate {provider} monthly insight for user {user_id}")
                        
                except Exception as e:
                    error_count += 1
                    logger.error(f"❌ Error generating {provider} monthly insight for user {user_id}: {str(e)}")
                    
        except Exception as e:
            error_count += 1
            logger.error(f"❌ Error processing user {user_id}: {str(e)}")
    
    logger.info(f"✅ Monthly insights generation completed: {success_count} successful, {error_count} errors")