import asyncio
import uuid
import os
from datetime import datetime, timedelta, UTC
from notification_service import notify_monthly_insights_generated, notify_weekly_insights_generated
from sql import budgets as budgets_db
from sql import transactions as transactions_db
from sql import goals as goals_db
from sql import insights as insights_db
from sql import users as users_db
from tz_utils import (
    app_today, app_wall_clock_now, as_utc, get_app_timezone, is_expired, previous_week_range,
    week_before_previous_range, previous_month_range, month_before_previous_range,
    current_week_to_date_range, current_month_to_date_range,
)
from ai_chatbot import financial_chatbot, FinancialDataProcessor
from ai_chatbot_gemini import gemini_financial_chatbot
from budget_service import get_running_budgets
import logging
import re
from typing import Optional
from ai_usage_service import track_ai_usage
from ai_usage_models import AIFeatureType, AIProviderType

logger = logging.getLogger(__name__)

# Get API keys
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")


def get_week_date_range():
    """
    Start/end of the most recent COMPLETE Monday-Sunday week.

    "Today" is evaluated in the app/scheduler timezone (SCHEDULER_TIMEZONE, default
    Asia/Yangon) so the Monday 05:00 job (which is still Sunday in UTC) reviews the week
    that just ended, not the week before it. Boundaries are returned as UTC-labelled
    calendar-day bounds, matching how transaction dates are stored.
    """
    return previous_week_range()


def get_previous_week_date_range():
    """Start/end of the week BEFORE the most recent complete week (for comparison)."""
    return week_before_previous_range()


def _usage_int(value) -> int:
    """Token counts from SDK responses may be None; normalize to int."""
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def _has_content(text) -> bool:
    return isinstance(text, str) and bool(text.strip())


def _tx_count(summary_data: dict) -> int:
    return sum(item.get('count', 0) for item in (summary_data or {}).get('summary', []))


# ==================== AI ERROR CLASSIFICATION ====================

class InsightAIError(Exception):
    """
    An AI provider call (insight generation or translation) failed.

    rate_limited=True when the provider answered 429 / quota exhausted, so the API can
    return HTTP 429 instead of a generic 500. The message is internal (logged); routes
    must show their own friendly text, never str(exc).
    """

    def __init__(self, message: str, rate_limited: bool = False, provider: Optional[str] = None):
        super().__init__(message)
        self.rate_limited = rate_limited
        self.provider = provider


_RATE_LIMIT_TEXT = re.compile(r"\b429\b|RESOURCE_EXHAUSTED|rate[ _-]?limit|too many requests|quota", re.IGNORECASE)

# Out of credit / billing problems. Providers report these with rate-limit-like codes
# (Gemini: 402 RESOURCE_EXHAUSTED "prepayment credits are depleted"; OpenAI: 429
# insufficient_quota), but waiting a few minutes won't help: someone must top up.
_BILLING_TEXT = re.compile(
    r"credits? (are |is )?depleted|insufficient[_ ]quota|billing|prepay|payment required|exceeded your current quota",
    re.IGNORECASE,
)


def is_billing_error(exc: Optional[BaseException]) -> bool:
    """True when the AI provider refused for lack of credit/billing, following __cause__/__context__."""
    seen = set()
    while exc is not None and id(exc) not in seen:
        seen.add(id(exc))
        for attr in ("code", "status_code"):
            value = getattr(exc, attr, None)
            if value == 402 or str(value) in ("402", "insufficient_quota"):
                return True
        if _BILLING_TEXT.search(str(exc) or ""):
            return True
        exc = exc.__cause__ or exc.__context__
    return False


def is_rate_limit_error(exc: Optional[BaseException]) -> bool:
    """True for openai.RateLimitError, Gemini 429 / RESOURCE_EXHAUSTED and similar, following __cause__/__context__.

    Billing / out-of-credit refusals are excluded (see is_billing_error): they are not
    transient, so telling users to retry in a few minutes would be wrong.
    """
    if is_billing_error(exc):
        return False
    try:
        from openai import RateLimitError as _OpenAIRateLimitError
    except Exception:  # pragma: no cover - openai always installed in prod
        _OpenAIRateLimitError = None
    seen = set()
    while exc is not None and id(exc) not in seen:
        seen.add(id(exc))
        if isinstance(exc, InsightAIError) and exc.rate_limited:
            return True
        if _OpenAIRateLimitError is not None and isinstance(exc, _OpenAIRateLimitError):
            return True
        for attr in ("code", "status_code"):
            value = getattr(exc, attr, None)
            if value == 429 or str(value) == "429":
                return True
        status_value = str(getattr(exc, "status", "") or "")
        if "RESOURCE_EXHAUSTED" in status_value.upper() or status_value == "429":
            return True
        if _RATE_LIMIT_TEXT.search(str(exc) or ""):
            return True
        exc = exc.__cause__ or exc.__context__
    return False


# Stored insights always have non-blank content (enforced by the database; legacy
# documents with content None / "" were never migrated, as the code treated them as missing).
async def latest_valid_insight(user_id: str, ai_provider: str, insight_type: str):
    """Latest stored insight (placeholder or real), or None."""
    return await insights_db.latest(user_id, ai_provider, insight_type)


async def _latest_real_insight(user_id: str, ai_provider: str, insight_type: str):
    """Latest stored non-placeholder insight for provider/type (None if none)."""
    return await insights_db.latest(user_id, ai_provider, insight_type, real_only=True)


async def user_has_insight_data(user_id: str, insight_type: str = "weekly") -> bool:
    """
    Same notion of "has activity" as generate_*_insight: transactions in the last complete
    period OR in the current period-to-date (a brand-new user's first week), any goals, or
    running budgets (window contains today and status active/exceeded, after refreshing
    stale stored statuses). Used to replace a stored placeholder insight once real data exists.
    """
    if insight_type == "monthly":
        ranges = (get_month_date_range(), current_month_to_date_range())
    else:
        ranges = (get_week_date_range(), current_week_to_date_range())

    for start, end in ranges:
        if await transactions_db.has_transactions_between(user_id, start, end):
            return True
    if await goals_db.user_has_goals(user_id):
        return True
    # Cheap pre-check (any budget whose window contains now) before the refreshing lookup.
    wall_now = app_wall_clock_now()
    if not await budgets_db.has_budget_containing(user_id, wall_now):
        return False
    return len(await get_running_budgets(user_id)) > 0


async def _todays_placeholder(user_id: str, ai_provider: str, insight_type: str):
    """The latest stored insight for provider/type if it is a placeholder generated today (app timezone)."""
    latest = await latest_valid_insight(user_id, ai_provider, insight_type)
    if not latest or not latest.get("is_placeholder") or not latest.get("generated_at"):
        return None
    generated_on = as_utc(latest["generated_at"]).astimezone(get_app_timezone()).date()
    return latest if generated_on == app_today() else None


async def _call_insight_model(
    ai_provider: str,
    chatbot,
    system_prompt: str,
    context: str,
    openai_max_tokens: int,
    feature_type: AIFeatureType,
    user_id: str,
    label: str,
):
    """Call the selected provider and track usage. Returns (content|None, in, out, total)."""
    from openai import AsyncOpenAI
    from google import genai

    input_tokens = output_tokens = total_tokens = 0

    if ai_provider == "gemini":
        model_name = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
        full_prompt = f"{system_prompt}\n\n{context}"
        try:
            client = genai.Client(api_key=GOOGLE_API_KEY)
            # google-genai generate_content is blocking; run it off the event loop
            response = await asyncio.to_thread(
                client.models.generate_content,
                model=model_name,
                contents=full_prompt,
                config={"temperature": 0.7, "max_output_tokens": 8192}
            )
        except Exception as e:
            raise InsightAIError(
                f"Gemini {label} request failed: {type(e).__name__}: {e}",
                rate_limited=is_rate_limit_error(e), provider="gemini",
            ) from e
        content = response.text
        usage = getattr(response, "usage_metadata", None)
        if usage:
            input_tokens = _usage_int(getattr(usage, "prompt_token_count", 0))
            output_tokens = _usage_int(getattr(usage, "candidates_token_count", 0))
            total_tokens = _usage_int(getattr(usage, "total_token_count", 0)) or (input_tokens + output_tokens)
        provider_type = AIProviderType.GEMINI
    else:
        model_name = chatbot.gpt_model
        try:
            client = AsyncOpenAI(api_key=OPENAI_API_KEY)
            response = await client.chat.completions.create(
                model=model_name,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": context}
                ],
                temperature=0.7,
                max_tokens=openai_max_tokens
            )
        except Exception as e:
            raise InsightAIError(
                f"OpenAI {label} request failed: {type(e).__name__}: {e}",
                rate_limited=is_rate_limit_error(e), provider="openai",
            ) from e
        content = response.choices[0].message.content if response.choices else None
        usage = getattr(response, "usage", None)
        if usage:
            input_tokens = _usage_int(getattr(usage, "prompt_tokens", 0))
            output_tokens = _usage_int(getattr(usage, "completion_tokens", 0))
            total_tokens = _usage_int(getattr(usage, "total_tokens", 0)) or (input_tokens + output_tokens)
        provider_type = AIProviderType.OPENAI

    logger.info(
        f"🔢 [{provider_type.value.upper()} TOKEN USAGE - {label}] User: {user_id} | "
        f"in={input_tokens:,} out={output_tokens:,} total={total_tokens:,} | model={model_name}"
    )
    if input_tokens or output_tokens or total_tokens:
        await track_ai_usage(
            user_id=user_id,
            feature_type=feature_type,
            provider=provider_type,
            model_name=model_name,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            total_tokens=total_tokens
        )

    return content, input_tokens, output_tokens, total_tokens


async def generate_weekly_insight(user_id: str, ai_provider: str = "openai", notify: bool = False):
    """
    Generate weekly insight for a specific user.

    notify: send the "weekly insights ready" notification. Off by default; the scheduled
    all-users job sends exactly one notification per user after both providers ran.
    """
    try:
        # Select chatbot based on provider
        chatbot = gemini_financial_chatbot if ai_provider == "gemini" else financial_chatbot

        if chatbot is None:
            logger.error(f"Chatbot not available for provider: {ai_provider}")
            return None

        # Get date ranges
        week_start, week_end = get_week_date_range()
        prev_week_start, prev_week_end = get_previous_week_date_range()

        # [FIX] Added await
        user = await users_db.get_user(user_id)
        if not user:
            logger.error(f"User not found: {user_id}")
            return None

        # Get financial data processor for other data (goals/budgets)
        processor = FinancialDataProcessor(user_id)

        # [FIX] Added await (Function updated to async below)
        current_week_data = await get_financial_summary(user_id, week_start, week_end)
        prev_week_data = await get_financial_summary(user_id, prev_week_start, prev_week_end)

        # Note: Assuming processor methods handle async internally or return data synchronously for now.
        # If FinancialDataProcessor uses the same database.py, these might need updates too.
        goals = await processor.get_user_goals()
        budgets = await processor.get_user_budgets()

        # Efficient check for activity
        total_tx_count = _tx_count(current_week_data)
        has_activity = total_tx_count > 0 or len(goals) > 0 or len(budgets) > 0
        period_to_date = False

        if not has_activity:
            # Nothing in the last complete week. Before falling back to the welcome
            # placeholder: (1) a user with transactions in the CURRENT (incomplete) week gets
            # a period-to-date insight; (2) a returning user with real insight history keeps
            # seeing their latest real insight (no placeholder is stored over it).
            ptd_start, ptd_end = current_week_to_date_range()
            ptd_data = await get_financial_summary(user_id, ptd_start, ptd_end)
            if _tx_count(ptd_data) > 0:
                logger.info(f"ℹ️  No activity last week for user {user_id}; generating week-to-date insight")
                period_to_date = True
                prev_week_data = current_week_data  # last complete week = comparison baseline
                current_week_data = ptd_data
                week_start, week_end = ptd_start, ptd_end
                has_activity = True
            else:
                latest_real = await _latest_real_insight(user_id, ai_provider, "weekly")
                if latest_real:
                    logger.info(f"ℹ️  Quiet week for user {user_id}; keeping latest real weekly insight")
                    # is_reused is transient (not stored): callers must not announce it as new.
                    return {**latest_real, "is_reused": True}

        if not has_activity:
            logger.info(f"ℹ️  No financial activity found for user {user_id}, returning placeholder insight")
            # Don't pile up a new placeholder on every request: reuse today's.
            existing_placeholder = await _todays_placeholder(user_id, ai_provider, "weekly")
            if existing_placeholder:
                return existing_placeholder
            insight_id = str(uuid.uuid4())
            now = datetime.now(UTC)

            placeholder_content = """## 👋 Welcome to Toe Pwar!
### 🎯 Get Started with Your Financial Journey

It looks like you're just getting started with Toe Pwar. To generate personalized AI insights, you'll need to add some financial activities first.

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
                "is_placeholder": True
            }

            # [FIX] Added await
            await insights_db.insert_insight(new_insight)
            return new_insight

        # [FIX] Added await
        previous_insight = await _latest_real_insight(user_id, ai_provider, "weekly")

        # Build context
        context = _build_weekly_context(
            user,
            current_week_data,
            prev_week_data,
            goals,
            budgets,
            week_start,
            week_end,
            previous_insight,
            period_to_date=period_to_date,
        )

        system_prompt = _build_weekly_system_prompt()

        insights_content, input_tokens, output_tokens, total_tokens = await _call_insight_model(
            ai_provider=ai_provider,
            chatbot=chatbot,
            system_prompt=system_prompt,
            context=context,
            openai_max_tokens=2500,
            feature_type=AIFeatureType.WEEKLY_INSIGHT,
            user_id=user_id,
            label="Weekly Insight",
        )

        if not _has_content(insights_content):
            logger.error(f"❌ {ai_provider} returned empty weekly insight for user {user_id}; not saving")
            return None

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
            "is_placeholder": False,
            # True when the report covers the current, still-running week (Monday..today)
            # because the last complete week had no activity.
            "is_period_to_date": period_to_date,
            "token_usage": {
                "input_tokens": input_tokens,
                "output_tokens": output_tokens,
                "total_tokens": total_tokens
            }
        }

        # [FIX] Added await
        await insights_db.insert_insight(new_insight)
        if notify:
            await notify_weekly_insights_generated(user_id)
        logger.info(f"✅ Weekly insight generated for user {user_id} using {ai_provider}")
        return new_insight

    except InsightAIError as e:
        # Propagate so routes can map it (429 for provider rate limits, 502/503 otherwise);
        # the scheduled job gathers with return_exceptions=True.
        logger.error(f"AI error generating weekly insight for user {user_id}: {e}")
        raise
    except Exception as e:
        logger.error(f"Error generating weekly insight for user {user_id}: {str(e)}")
        import traceback
        traceback.print_exc()
        return None



async def get_financial_summary(user_id, start_date, end_date):
    """
    Financial totals per currency and the top 5 spending categories per currency, summed in
    the database (summary stats instead of raw rows).
    """
    summary = await transactions_db.currency_totals(user_id, date_from=start_date, date_to=end_date)
    top_items = {}
    for c in await transactions_db.category_totals(user_id, type_="outflow", date_from=start_date, date_to=end_date):
        items = top_items.setdefault(c["currency"], [])
        if len(items) < 5:
            items.append({"category": f"{c['main_category']} > {c['sub_category']}", "amount": c["total"]})
    return {
        "summary": [
            {"_id": s["currency"], "inflow": s["total_inflow"], "outflow": s["total_outflow"], "count": s["count"]}
            for s in summary
        ],
        "categories": [{"_id": currency, "top_items": items} for currency, items in top_items.items()],
    }


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
    current_week_data,  # Now accepts aggregation result
    prev_week_data,     # Now accepts aggregation result
    goals,
    budgets,
    week_start,
    week_end,
    previous_insight,
    period_to_date: bool = False,
):
    """Build context for weekly insights using aggregated data.

    period_to_date=True: current_week_data covers the current, still-running week
    (Monday..today) and prev_week_data the last complete week.
    """

    # Extract data for easier lookup
    curr_summary = {item['_id']: item for item in current_week_data.get('summary', [])}
    curr_cats = {item['_id']: item['top_items'] for item in current_week_data.get('categories', [])}

    prev_summary = {item['_id']: item for item in prev_week_data.get('summary', [])}

    # Calculate total transactions across all currencies
    total_tx = sum(item['count'] for item in curr_summary.values())

    if period_to_date:
        context = f"""USER: {user.get('name', 'User')}
DEFAULT CURRENCY: {user.get('default_currency', 'usd').upper()}

TODAY: {app_today().strftime('%A, %B %d, %Y')}

REPORT PERIOD: CURRENT WEEK TO DATE (WEEK STILL IN PROGRESS): {week_start.strftime('%B %d, %Y')} (Monday) to {week_end.strftime('%B %d, %Y')} (today)
NOTE: The last complete week had no transactions, so this report covers the current week so far.
Do NOT call this period "last week", and do not treat the remaining days of the week as zero spending.

=== THIS WEEK'S FINANCIAL ACTIVITY SO FAR ===

Total Transactions: {total_tx}

"""
    else:
        context = f"""USER: {user.get('name', 'User')}
DEFAULT CURRENCY: {user.get('default_currency', 'usd').upper()}

TODAY: {app_today().strftime('%A, %B %d, %Y')} (Monday Morning)

LAST WEEK'S PERIOD: {week_start.strftime('%B %d, %Y')} (Monday) to {week_end.strftime('%B %d, %Y')} (Sunday)

=== LAST WEEK'S FINANCIAL ACTIVITY ===

Total Transactions: {total_tx}

"""

    # Process Current Week Data
    for currency, data in curr_summary.items():
        # Fallback for currency code if missing
        if not currency: currency = "usd"

        currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
        currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")

        net = data['inflow'] - data['outflow']

        context += f"\n{currency_name}:\n"
        context += f"  Income: {currency_symbol}{data['inflow']:,.2f}\n"
        context += f"  Expenses: {currency_symbol}{data['outflow']:,.2f}\n"
        context += f"  Net: {currency_symbol}{net:,.2f}\n"
        context += f"  Transactions: {data['count']}\n"

        # Top spending categories from aggregation
        context += f"\n  Top Spending Categories:\n"
        top_items = curr_cats.get(currency, [])
        if top_items:
            for item in top_items:
                context += f"    - {item['category']}: {currency_symbol}{item['amount']:,.2f}\n"
        else:
            context += "    - No expenses recorded\n"

    # Previous week comparison
    if prev_summary:
        context += (
            "\n\n=== LAST COMPLETE WEEK COMPARISON (full week vs. this partial week) ===\n\n"
            if period_to_date else "\n\n=== WEEK BEFORE LAST COMPARISON ===\n\n"
        )

        # Union of all currencies found in both weeks
        all_currencies = set(list(curr_summary.keys()) + list(prev_summary.keys()))

        for currency in all_currencies:
            if not currency: continue

            currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
            currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")

            current = curr_summary.get(currency, {"inflow": 0, "outflow": 0})
            prev = prev_summary.get(currency, {"inflow": 0, "outflow": 0})

            # Calculate % change
            income_change = ((current["inflow"] - prev["inflow"]) / prev["inflow"] * 100) if prev["inflow"] > 0 else 0
            expense_change = ((current["outflow"] - prev["outflow"]) / prev["outflow"] * 100) if prev["outflow"] > 0 else 0

            context += f"{currency_name}:\n"
            context += f"  Income: {currency_symbol}{prev['inflow']:,.2f} → {currency_symbol}{current['inflow']:,.2f} ({income_change:+.1f}%)\n"
            context += f"  Expenses: {currency_symbol}{prev['outflow']:,.2f} → {currency_symbol}{current['outflow']:,.2f} ({expense_change:+.1f}%)\n\n"

    # --- GOALS & BUDGETS Logic remains exactly the same as before ---

    # Goals progress
    if goals:
        context += "\n=== FINANCIAL GOALS STATUS ===\n\n"
        goals_by_currency = {}
        for g in goals:
            curr = g.get("currency", "usd")
            if curr not in goals_by_currency: goals_by_currency[curr] = []
            goals_by_currency[curr].append(g)

        for curr, curr_goals in goals_by_currency.items():
            sym = "$" if curr == "usd" else ("K" if curr == "mmk" else "฿")
            name = "USD" if curr == "usd" else ("MMK" if curr == "mmk" else "THB")
            active_goals = [g for g in curr_goals if g["status"] == "active"]

            context += f"{name} Goals:\n"
            for goal in active_goals[:5]:
                progress = (goal["current_amount"] / goal["target_amount"] * 100) if goal["target_amount"] > 0 else 0
                context += f"  - {goal['name']}: {sym}{goal['current_amount']:,.2f} / {sym}{goal['target_amount']:,.2f} ({progress:.1f}%)\n"
            context += "\n"

    # Budgets progress
    if budgets:
        context += "\n=== ACTIVE BUDGETS ===\n\n"
        budgets_by_currency = {}
        for b in budgets:
            curr = b.get("currency", "usd")
            if curr not in budgets_by_currency: budgets_by_currency[curr] = []
            budgets_by_currency[curr].append(b)

        for curr, curr_budgets in budgets_by_currency.items():
            sym = "$" if curr == "usd" else ("K" if curr == "mmk" else "฿")
            name = "USD" if curr == "usd" else ("MMK" if curr == "mmk" else "THB")

            context += f"{name} Budgets:\n"
            for budget in curr_budgets:
                utilization = budget.get("percentage_used", 0)
                status_emoji = "✅" if utilization < 80 else "⚠️" if utilization < 100 else "🚨"
                context += f"  {status_emoji} {budget['name']} ({budget['period']}):\n"
                context += f"     Total: {sym}{budget['total_spent']:,.2f} / {sym}{budget['total_budget']:,.2f} ({utilization:.1f}%)\n"

                # Show category breakdowns
                for cat_budget in budget.get('category_budgets', [])[:5]:
                    cat_util = cat_budget.get('percentage_used', 0)
                    context += f"       - {cat_budget['main_category']}: {sym}{cat_budget['spent_amount']:,.2f} / {sym}{cat_budget['allocated_amount']:,.2f} ({cat_util:.1f}%)\n"
                context += "\n"

    # Previous insight summary
    if previous_insight:
        context += "\n=== PREVIOUS WEEK'S KEY RECOMMENDATIONS ===\n"
        context += f"(Review to see if user followed through)\n\n"
        prev_content = previous_insight.get("content") or ""
        context += (prev_content[:500] + "...\n") if len(prev_content) > 500 else (prev_content + "\n")

    if period_to_date:
        context += (
            "\n\nGenerate a weekly financial insight report for the CURRENT WEEK SO FAR "
            f"({week_start.strftime('%B %d')} to today, week still in progress) based on the above data. "
            "Say clearly in the summary that it covers the week to date."
        )
    else:
        context += "\n\nGenerate a comprehensive weekly financial insight report based on the above data."
    return context


async def generate_weekly_insights_for_all_users():
    """Generate weekly insights for all premium users using Bounded Concurrency"""
    logger.info("🔄 Starting weekly insights generation (Concurrent Mode)...")

    # 1. Fetch all premium users quickly to release DB cursor
    # Projection only gets necessary fields to save memory
    users = await users_db.list_fields(["subscription_expires_at"], users_db.users.c.subscription_type == "premium")

    if not users:
        logger.info("ℹ️ No premium users found for weekly insights.")
        return

    logger.info(f"📊 Processing {len(users)} premium users for weekly insights...")

    # 2. Semaphore to limit concurrency (e.g., 5 users at a time = ~10 concurrent AI calls)
    # Adjust this number based on your OpenAI/Gemini tier limits.
    sem = asyncio.Semaphore(5)

    success_count = 0
    error_count = 0

    async def process_user_weekly(user):
        nonlocal success_count, error_count
        user_id = user["_id"]

        async with sem:  # Wait for a free slot in the semaphore
            try:
                # Check subscription validity
                if is_expired(user.get("subscription_expires_at")):
                    logger.info(f"⏭️ Skipping user {user_id} - subscription expired")
                    return

                # Run both providers concurrently for this user
                # This cuts processing time per user in half
                tasks = [
                    generate_weekly_insight(user_id, "openai", notify=False),
                    generate_weekly_insight(user_id, "gemini", notify=False)
                ]

                results = await asyncio.gather(*tasks, return_exceptions=True)

                for provider, result in zip(["openai", "gemini"], results):
                    if isinstance(result, Exception):
                        logger.error(f"❌ Error generating {provider} weekly insight for {user_id}: {str(result)}")
                        error_count += 1
                    elif result:
                        logger.info(f"✅ Generated {provider} weekly insight for user {user_id}")
                        success_count += 1
                    else:
                        logger.warning(f"⚠️ Failed to generate {provider} weekly insight for user {user_id} (Returned None)")
                        error_count += 1

                # Exactly one "insights ready" notification per user per run, and only
                # when at least one provider produced a real (non-placeholder) insight.
                # (a reused older insight returned for a quiet period is not "new").
                if any(
                    isinstance(r, dict) and not r.get("is_placeholder") and not r.get("is_reused")
                    for r in results
                ):
                    try:
                        await notify_weekly_insights_generated(user_id)
                    except Exception as notify_error:
                        logger.error(f"⚠️ Failed to send weekly insights notification to {user_id}: {notify_error}")

            except Exception as e:
                logger.error(f"❌ Critical error processing user {user_id}: {str(e)}")
                error_count += 1

    # 3. Create and run all tasks
    # This fires off the workers, which will respect the semaphore limit
    tasks = [process_user_weekly(user) for user in users]
    await asyncio.gather(*tasks)

    logger.info(f"✅ Weekly insights generation completed: {success_count} successful, {error_count} errors")


MYANMAR_PLACEHOLDER = """## 👋 Toe Pwar မှ ကြိုဆိုပါတယ်!

### 🎯 သင့်ရဲ့ ငွေကြေးခရီးစဉ်ကို စတင်ပါ

Toe Pwar နဲ့ စတင်အသုံးပြုနေပုံရပါတယ်။ AI မှ ပုဂ္ဂိုလ်ရေးအရ ဆန်းစစ်ချက်များ ရရှိရန် ပထမဆုံး သင့်ရဲ့ ငွေကြေးလှုပ်ရှားမှုများကို ထည့်သွင်းဖို့ လိုအပ်ပါတယ်။

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


_TRANSLATION_SYSTEM_PROMPT = """You are a professional translator specializing in financial content.
Translate the following financial insights from English to Myanmar (Burmese) language.

CRITICAL RULES:
1. Maintain ALL formatting including markdown (##, **, bullets, emojis)
2. Keep financial terms clear and understandable in Myanmar
3. Preserve all numbers, percentages, and dollar amounts exactly
4. Use natural, conversational Myanmar that feels native
5. Keep emojis exactly as they are
6. Maintain the same structure and sections
7. Output ONLY the translation, with no preamble or commentary

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

# Myanmar output is token-heavy (several tokens per Burmese syllable), so give the
# translation plenty of room. Gemini 2.5 "thinking" tokens also count toward the limit.
TRANSLATION_OPENAI_MAX_TOKENS = 8000
TRANSLATION_GEMINI_MAX_TOKENS = 32768
TRANSLATION_GEMINI_MODEL = "gemini-2.5-pro"
# Max English characters per chunk when a single-shot translation was truncated.
TRANSLATION_CHUNK_CHARS = 2500


class TranslationTruncatedError(Exception):
    """The model hit its output limit, so the translation is incomplete (must not be cached)."""


def _is_placeholder_text(english_content: str) -> bool:
    """Legacy fallback for insights stored before is_placeholder was reliable (incl. the old 'Tow Pwar' typo)."""
    text = english_content or ""
    return "Get Started with Your Financial Journey" in text and (
        "Welcome to Toe Pwar!" in text or "Welcome to Tow Pwar!" in text
    )


def _split_markdown_sections(text: str, max_chars: int = TRANSLATION_CHUNK_CHARS) -> list:
    """Split markdown into chunks on heading boundaries, packing sections up to max_chars."""
    sections, current = [], []
    for line in text.splitlines(keepends=True):
        if line.lstrip().startswith("#") and current:
            sections.append("".join(current))
            current = []
        current.append(line)
    if current:
        sections.append("".join(current))

    chunks, buf = [], ""
    for section in sections:
        if buf and len(buf) + len(section) > max_chars:
            chunks.append(buf)
            buf = ""
        buf += section
    if buf:
        chunks.append(buf)
    return chunks


def _finish_reason_name(value) -> str:
    if value is None:
        return ""
    return str(getattr(value, "name", value)).upper()


async def _translate_once(english_content: str, ai_provider: str, user_id: str = None):
    """Translate one piece of text. Returns (myanmar_text, truncated: bool)."""
    if ai_provider == "gemini":
        from google import genai

        if not GOOGLE_API_KEY:
            raise Exception("Google API key not configured")

        client = genai.Client(api_key=GOOGLE_API_KEY)
        prompt = f"{_TRANSLATION_SYSTEM_PROMPT}\n\nTranslate this to Myanmar:\n\n{english_content}"

        response = await asyncio.to_thread(
            client.models.generate_content,
            model=TRANSLATION_GEMINI_MODEL,
            contents=prompt,
            config={
                "temperature": 0.3,
                "max_output_tokens": TRANSLATION_GEMINI_MAX_TOKENS,
            }
        )

        myanmar_content = response.text
        candidates = getattr(response, "candidates", None) or []
        finish = _finish_reason_name(getattr(candidates[0], "finish_reason", None)) if candidates else ""
        truncated = "MAX_TOKENS" in finish

        usage = getattr(response, "usage_metadata", None)
        if usage:
            input_tokens = _usage_int(getattr(usage, "prompt_token_count", 0))
            output_tokens = _usage_int(getattr(usage, "candidates_token_count", 0))
            total_tokens = _usage_int(getattr(usage, "total_token_count", 0)) or (input_tokens + output_tokens)
            await track_ai_usage(
                user_id=user_id,
                feature_type=AIFeatureType.TRANSLATION,
                provider=AIProviderType.GEMINI,
                model_name=TRANSLATION_GEMINI_MODEL,
                input_tokens=input_tokens,
                output_tokens=output_tokens,
                total_tokens=total_tokens
            )
    else:  # OpenAI
        from openai import AsyncOpenAI

        if not OPENAI_API_KEY:
            raise Exception("OpenAI API key not configured")

        client = AsyncOpenAI(api_key=OPENAI_API_KEY)
        model_name = os.getenv("OPENAI_MODEL", "gpt-4o-mini")

        response = await client.chat.completions.create(
            model=model_name,
            messages=[
                {"role": "system", "content": _TRANSLATION_SYSTEM_PROMPT},
                {"role": "user", "content": f"Translate this to Myanmar:\n\n{english_content}"}
            ],
            temperature=0.3,
            max_tokens=TRANSLATION_OPENAI_MAX_TOKENS
        )

        choice = response.choices[0] if response.choices else None
        myanmar_content = choice.message.content if choice else None
        truncated = _finish_reason_name(getattr(choice, "finish_reason", None)) == "LENGTH"

        usage = getattr(response, "usage", None)
        if usage:
            input_tokens = _usage_int(getattr(usage, "prompt_tokens", 0))
            output_tokens = _usage_int(getattr(usage, "completion_tokens", 0))
            total_tokens = _usage_int(getattr(usage, "total_tokens", 0)) or (input_tokens + output_tokens)
            await track_ai_usage(
                user_id=user_id,
                feature_type=AIFeatureType.TRANSLATION,
                provider=AIProviderType.OPENAI,
                model_name=model_name,
                input_tokens=input_tokens,
                output_tokens=output_tokens,
                total_tokens=total_tokens
            )

    if not _has_content(myanmar_content):
        raise Exception("Translation model returned empty output")
    return myanmar_content, truncated


async def translate_insight_to_myanmar(
    english_content: str,
    ai_provider: str = "openai",
    user_id: str = None,
    is_placeholder: bool = None,
) -> str:
    """
    Translate English insights to Myanmar.

    Pass the insight's stored is_placeholder flag: placeholders get a canned translation
    and are never sent to the paid translation API. If the model output is truncated
    (OpenAI finish_reason == "length" / Gemini MAX_TOKENS) the content is re-translated
    section by section; if that is still truncated an exception is raised so callers
    never cache an incomplete content_mm.
    """
    try:
        if is_placeholder or (is_placeholder is None and _is_placeholder_text(english_content)):
            logger.info("Returning Myanmar placeholder (no AI call)")
            return MYANMAR_PLACEHOLDER

        if not _has_content(english_content):
            raise Exception("No content to translate")

        myanmar_content, truncated = await _translate_once(english_content, ai_provider, user_id)
        if not truncated:
            return myanmar_content

        chunks = _split_markdown_sections(english_content)
        logger.warning(
            f"⚠️ Myanmar translation truncated ({ai_provider}); retrying in {len(chunks)} section chunk(s)"
        )
        if len(chunks) <= 1:
            raise TranslationTruncatedError("Translation output was truncated")

        translated_parts = []
        for chunk in chunks:
            part, part_truncated = await _translate_once(chunk, ai_provider, user_id)
            if part_truncated:
                raise TranslationTruncatedError("Translation output was truncated")
            translated_parts.append(part.strip())
        return "\n\n".join(translated_parts)

    except Exception as e:
        logger.error(f"Translation error using {ai_provider}: {e}")
        # InsightAIError (an Exception subclass) lets routes map provider 429s to HTTP 429.
        raise InsightAIError(
            f"Failed to translate insights: {e}",
            rate_limited=is_rate_limit_error(e), provider=ai_provider,
        ) from e


def get_month_date_range():
    """
    Start/end of the most recent COMPLETE calendar month, with "today" evaluated in the
    app/scheduler timezone (see get_week_date_range).
    """
    return previous_month_range()


def get_previous_month_date_range():
    """Start/end of the month BEFORE the most recent complete month (for comparison)."""
    return month_before_previous_range()


async def generate_monthly_insight(user_id: str, ai_provider: str = "openai", notify: bool = False):
    """
    Generate monthly insight for a specific user.

    notify: send the "monthly insights ready" notification. Off by default; the scheduled
    all-users job sends exactly one notification per user after both providers ran.
    """
    try:
        # Select chatbot based on provider
        chatbot = gemini_financial_chatbot if ai_provider == "gemini" else financial_chatbot

        if chatbot is None:
            logger.error(f"Chatbot not available for provider: {ai_provider}")
            return None

        # Get date ranges
        month_start, month_end = get_month_date_range()
        prev_month_start, prev_month_end = get_previous_month_date_range()

        # [FIX] Added await
        user = await users_db.get_user(user_id)
        if not user:
            logger.error(f"User not found: {user_id}")
            return None

        # Get financial data processor
        processor = FinancialDataProcessor(user_id)

        # [FIX] Added await (Function is now async)
        current_month_data = await get_financial_summary(user_id, month_start, month_end)
        prev_month_data = await get_financial_summary(user_id, prev_month_start, prev_month_end)

        # Get goals & budgets
        goals = await processor.get_user_goals()
        budgets = await processor.get_user_budgets()

        # Check for activity
        total_tx_count = _tx_count(current_month_data)
        has_activity = total_tx_count > 0 or len(goals) > 0 or len(budgets) > 0
        period_to_date = False

        if not has_activity:
            # Nothing in the last complete month: month-to-date insight if the current month
            # has transactions, else keep the latest real insight (no placeholder over history).
            ptd_start, ptd_end = current_month_to_date_range()
            ptd_data = await get_financial_summary(user_id, ptd_start, ptd_end)
            if _tx_count(ptd_data) > 0:
                logger.info(f"ℹ️  No activity last month for user {user_id}; generating month-to-date insight")
                period_to_date = True
                prev_month_data = current_month_data  # last complete month = comparison baseline
                current_month_data = ptd_data
                month_start, month_end = ptd_start, ptd_end
                has_activity = True
            else:
                latest_real = await _latest_real_insight(user_id, ai_provider, "monthly")
                if latest_real:
                    logger.info(f"ℹ️  Quiet month for user {user_id}; keeping latest real monthly insight")
                    return {**latest_real, "is_reused": True}

        if not has_activity:
            logger.info(f"ℹ️  No financial activity found for user {user_id}, returning placeholder insight")
            # Don't pile up a new placeholder on every request: reuse today's.
            existing_placeholder = await _todays_placeholder(user_id, ai_provider, "monthly")
            if existing_placeholder:
                return existing_placeholder

            insight_id = str(uuid.uuid4())
            now = datetime.now(UTC)

            placeholder_content = """## 👋 Welcome to Toe Pwar!
### 🎯 Get Started with Your Financial Journey

It looks like you're just getting started with Toe Pwar. To generate personalized monthly AI insights, you'll need to add some financial activities first.

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
                "is_placeholder": True
            }

            # [FIX] Added await
            await insights_db.insert_insight(new_insight)
            return new_insight

        # [FIX] Added await
        previous_insight = await _latest_real_insight(user_id, ai_provider, "monthly")

        # Build context
        context = _build_monthly_context(
            user,
            current_month_data,
            prev_month_data,
            goals,
            budgets,
            month_start,
            month_end,
            previous_insight,
            period_to_date=period_to_date,
        )

        system_prompt = _build_monthly_system_prompt()

        insights_content, input_tokens, output_tokens, total_tokens = await _call_insight_model(
            ai_provider=ai_provider,
            chatbot=chatbot,
            system_prompt=system_prompt,
            context=context,
            openai_max_tokens=3000,
            feature_type=AIFeatureType.MONTHLY_INSIGHT,
            user_id=user_id,
            label="Monthly Insight",
        )

        if not _has_content(insights_content):
            logger.error(f"❌ {ai_provider} returned empty monthly insight for user {user_id}; not saving")
            return None

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
            "is_placeholder": False,
            # True when the report covers the current, still-running month (1st..today).
            "is_period_to_date": period_to_date,
            "token_usage": {
                "input_tokens": input_tokens,
                "output_tokens": output_tokens,
                "total_tokens": total_tokens
            }
        }

        # [FIX] Added await
        await insights_db.insert_insight(new_insight)
        if notify:
            await notify_monthly_insights_generated(user_id)
        logger.info(f"✅ Monthly insight generated for user {user_id} using {ai_provider}")
        return new_insight

    except InsightAIError as e:
        logger.error(f"AI error generating monthly insight for user {user_id}: {e}")
        raise
    except Exception as e:
        logger.error(f"Error generating monthly insight for user {user_id}: {str(e)}")
        import traceback
        traceback.print_exc()
        return None


def _build_monthly_system_prompt():
    """Build system prompt for monthly insights generation"""
    return """You are Toe Pwar AI, an expert financial analyst providing monthly financial insights.

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
    current_month_data, 
    prev_month_data,
    goals,
    budgets,
    month_start,
    month_end,
    previous_insight,
    period_to_date: bool = False,
):
    """Build context for monthly insights using aggregated data.

    period_to_date=True: current_month_data covers the current, still-running month
    (1st..today) and prev_month_data the last complete month.
    """

    # Extract data from aggregation structure
    curr_summary = {item['_id']: item for item in current_month_data.get('summary', [])}
    curr_cats = {item['_id']: item['top_items'] for item in current_month_data.get('categories', [])}

    prev_summary = {item['_id']: item for item in prev_month_data.get('summary', [])}

    # Calculate total transactions
    total_tx = sum(item['count'] for item in curr_summary.values())

    if period_to_date:
        context = f"""USER: {user.get('name', 'User')}
DEFAULT CURRENCY: {user.get('default_currency', 'usd').upper()}

TODAY: {app_today().strftime('%A, %B %d, %Y')}

REPORT PERIOD: CURRENT MONTH TO DATE (MONTH STILL IN PROGRESS): {month_start.strftime('%B %d, %Y')} to {month_end.strftime('%B %d, %Y')} (today)
NOTE: The last complete month had no transactions, so this report covers the current month so far.
Do NOT call this period "last month", and do not treat the remaining days of the month as zero spending.

=== THIS MONTH'S FINANCIAL ACTIVITY SO FAR ===

Total Transactions: {total_tx}

"""
    else:
        context = f"""USER: {user.get('name', 'User')}
DEFAULT CURRENCY: {user.get('default_currency', 'usd').upper()}

TODAY: {app_today().strftime('%A, %B %d, %Y')} (1st of the Month)

LAST MONTH'S PERIOD: {month_start.strftime('%B %d, %Y')} to {month_end.strftime('%B %d, %Y')}

=== LAST MONTH'S FINANCIAL ACTIVITY ===

Total Transactions: {total_tx}

"""

    # Process Current Month Data
    for currency, data in curr_summary.items():
        if not currency: currency = "usd"

        currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
        currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")

        net = data['inflow'] - data['outflow']

        context += f"\n{currency_name}:\n"
        context += f"  Income: {currency_symbol}{data['inflow']:,.2f}\n"
        context += f"  Expenses: {currency_symbol}{data['outflow']:,.2f}\n"
        context += f"  Net: {currency_symbol}{net:,.2f}\n"
        context += f"  Transactions: {data['count']}\n"

        # Top spending categories
        context += f"\n  Top Spending Categories:\n"
        top_items = curr_cats.get(currency, [])
        if top_items:
            for item in top_items:
                context += f"    - {item['category']}: {currency_symbol}{item['amount']:,.2f}\n"
        else:
            context += "    - No expenses recorded\n"

    # Previous Month Comparison
    if prev_summary:
        context += (
            "\n\n=== LAST COMPLETE MONTH COMPARISON (full month vs. this partial month) ===\n\n"
            if period_to_date else "\n\n=== PREVIOUS MONTH COMPARISON ===\n\n"
        )

        all_currencies = set(list(curr_summary.keys()) + list(prev_summary.keys()))

        for currency in all_currencies:
            if not currency: continue

            currency_symbol = "$" if currency == "usd" else ("K" if currency == "mmk" else "฿")
            currency_name = "USD" if currency == "usd" else ("MMK" if currency == "mmk" else "THB")

            current = curr_summary.get(currency, {"inflow": 0, "outflow": 0})
            prev = prev_summary.get(currency, {"inflow": 0, "outflow": 0})

            # Calculate % change
            income_change = ((current["inflow"] - prev["inflow"]) / prev["inflow"] * 100) if prev["inflow"] > 0 else 0
            expense_change = ((current["outflow"] - prev["outflow"]) / prev["outflow"] * 100) if prev["outflow"] > 0 else 0

            context += f"{currency_name}:\n"
            context += f"  Income: {currency_symbol}{prev['inflow']:,.2f} → {currency_symbol}{current['inflow']:,.2f} ({income_change:+.1f}%)\n"
            context += f"  Expenses: {currency_symbol}{prev['outflow']:,.2f} → {currency_symbol}{current['outflow']:,.2f} ({expense_change:+.1f}%)\n\n"

    # Goals - Logic remains same
    if goals:
        context += "\n=== FINANCIAL GOALS STATUS ===\n\n"
        goals_by_currency = {}
        for g in goals:
            curr = g.get("currency", "usd")
            if curr not in goals_by_currency: goals_by_currency[curr] = []
            goals_by_currency[curr].append(g)

        for curr, curr_goals in goals_by_currency.items():
            sym = "$" if curr == "usd" else ("K" if curr == "mmk" else "฿")
            name = "USD" if curr == "usd" else ("MMK" if curr == "mmk" else "THB")
            active_goals = [g for g in curr_goals if g["status"] == "active"]

            context += f"{name} Goals:\n"
            for goal in active_goals[:5]:
                progress = (goal["current_amount"] / goal["target_amount"] * 100) if goal["target_amount"] > 0 else 0
                context += f"  - {goal['name']}: {sym}{goal['current_amount']:,.2f} / {sym}{goal['target_amount']:,.2f} ({progress:.1f}%)\n"
            context += "\n"

    # Budgets - Logic remains same
    if budgets:
        context += "\n=== ACTIVE BUDGETS ===\n\n"
        budgets_by_currency = {}
        for b in budgets:
            curr = b.get("currency", "usd")
            if curr not in budgets_by_currency: budgets_by_currency[curr] = []
            budgets_by_currency[curr].append(b)

        for curr, curr_budgets in budgets_by_currency.items():
            sym = "$" if curr == "usd" else ("K" if curr == "mmk" else "฿")
            name = "USD" if curr == "usd" else ("MMK" if curr == "mmk" else "THB")

            context += f"{name} Budgets:\n"
            for budget in curr_budgets:
                utilization = budget.get("percentage_used", 0)
                status_emoji = "✅" if utilization < 80 else "⚠️" if utilization < 100 else "🚨"
                context += f"  {status_emoji} {budget['name']} ({budget['period']}):\n"
                context += f"     Total: {sym}{budget['total_spent']:,.2f} / {sym}{budget['total_budget']:,.2f} ({utilization:.1f}%)\n"

                # Show category breakdowns
                for cat_budget in budget.get('category_budgets', [])[:8]:
                    cat_util = cat_budget.get('percentage_used', 0)
                    context += f"       - {cat_budget['main_category']}: {sym}{cat_budget['spent_amount']:,.2f} / {sym}{cat_budget['allocated_amount']:,.2f} ({cat_util:.1f}%)\n"
                context += "\n"

    # Previous insight
    if previous_insight:
        context += "\n=== PREVIOUS MONTH'S KEY RECOMMENDATIONS ===\n"
        context += f"(Review to see if user followed through)\n\n"
        prev_content = previous_insight.get("content") or ""
        context += (prev_content[:500] + "...\n") if len(prev_content) > 500 else (prev_content + "\n")

    if period_to_date:
        context += (
            "\n\nGenerate a monthly financial insight report for the CURRENT MONTH SO FAR "
            f"({month_start.strftime('%B %d')} to today, month still in progress) based on the above data. "
            "Say clearly in the summary that it covers the month to date."
        )
    else:
        context += "\n\nGenerate a comprehensive monthly financial insight report based on the above data."
    return context


async def generate_monthly_insights_for_all_users():
    """Generate monthly insights for all premium users using Bounded Concurrency"""
    logger.info("📅 Starting monthly insights generation (Concurrent Mode)...")

    # 1. Fetch all premium users
    users = await users_db.list_fields(["subscription_expires_at"], users_db.users.c.subscription_type == "premium")

    if not users:
        logger.info("ℹ️ No premium users found for monthly insights.")
        return

    logger.info(f"📊 Processing {len(users)} premium users for monthly insights...")

    # 2. Semaphore to limit concurrency
    sem = asyncio.Semaphore(5)

    success_count = 0
    error_count = 0

    async def process_user_monthly(user):
        nonlocal success_count, error_count
        user_id = user["_id"]

        async with sem:
            try:
                # Check subscription validity
                if is_expired(user.get("subscription_expires_at")):
                    logger.info(f"⏭️ Skipping user {user_id} - subscription expired")
                    return

                # Run both providers concurrently
                tasks = [
                    generate_monthly_insight(user_id, "openai", notify=False),
                    generate_monthly_insight(user_id, "gemini", notify=False)
                ]

                results = await asyncio.gather(*tasks, return_exceptions=True)

                for provider, result in zip(["openai", "gemini"], results):
                    if isinstance(result, Exception):
                        logger.error(f"❌ Error generating {provider} monthly insight for {user_id}: {str(result)}")
                        error_count += 1
                    elif result:
                        logger.info(f"✅ Generated {provider} monthly insight for user {user_id}")
                        success_count += 1
                    else:
                        logger.warning(f"⚠️ Failed to generate {provider} monthly insight for user {user_id} (Returned None)")
                        error_count += 1

                # Exactly one "insights ready" notification per user per run, and only
                # when at least one provider produced a real (non-placeholder) insight.
                # (a reused older insight returned for a quiet period is not "new").
                if any(
                    isinstance(r, dict) and not r.get("is_placeholder") and not r.get("is_reused")
                    for r in results
                ):
                    try:
                        await notify_monthly_insights_generated(user_id)
                    except Exception as notify_error:
                        logger.error(f"⚠️ Failed to send monthly insights notification to {user_id}: {notify_error}")

            except Exception as e:
                logger.error(f"❌ Critical error processing user {user_id}: {str(e)}")
                error_count += 1

    # 3. Run all tasks
    tasks = [process_user_monthly(user) for user in users]
    await asyncio.gather(*tasks)

    logger.info(f"✅ Monthly insights generation completed: {success_count} successful, {error_count} errors")