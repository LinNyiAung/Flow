import uuid
from dataclasses import replace
from datetime import date, datetime, timedelta, tzinfo, UTC
from notification_service import notify_monthly_insights_generated, notify_weekly_insights_generated
from plans import quota
from plans import store as plan_store
from plans.access import effective_plan
from plans.catalog import PAID_PLANS
from sql import budgets as budgets_db
from sql import families as families_db
from sql import transactions as transactions_db
from sql import goals as goals_db
from sql import insights as insights_db
from sql import books as books_db
from tz_utils import (
    as_calendar_date, as_utc, local_today, previous_week_range,
    week_before_previous_range, previous_month_range, month_before_previous_range,
    current_week_to_date_range, current_month_to_date_range,
)
from ai_chatbot import FinancialDataProcessor
from budget_categories import allocation_label
from budget_service import get_running_budgets
import logging
from typing import Optional
from ai_providers import errors as _errors
from ai_providers import runner as _runner
from ai_providers import settings as _ai_settings
from ai_providers.errors import AllProvidersFailed, UnusableAnswer
from ai_providers.types import Completion, Prompt

logger = logging.getLogger(__name__)


def get_week_date_range(tz: tzinfo):
    """
    Start/end of the most recent COMPLETE Monday-Sunday week.

    "Today" is evaluated in the book's zone `tz` (user_zones.book_zone) so the Monday 05:00 job (which is still Sunday
    in UTC) reviews the week that just ended, not the week before it. Boundaries are naive wall-clock day bounds, compared directly with the
    transaction dates.
    """
    return previous_week_range(tz)


def get_previous_week_date_range(tz: tzinfo):
    """Start/end of the week BEFORE the most recent complete week (for comparison)."""
    return week_before_previous_range(tz)


async def _skip_user(user: dict, feature: str, book_id: str, is_family: bool) -> bool:
    """True when a scheduled insight job (`feature`: insight_weekly / insight_monthly) must skip book `book_id`, whose
    plan user is `user`: their paid plan has ended (they count as Free at once, without waiting for the hourly expiry
    job), the owner locked that insight type on their plan, or their AI spend this month has reached their plan's
    hidden cost cap.

    is_family: `book_id` is a family book and `user` its owner; the cap then counts the owner's spend plus the book's
    own (ruling R16, quota.family_over_cost_cap)."""
    plan = effective_plan(user)
    if plan not in PAID_PLANS:
        logger.info(f"⏭️ Skipping book {book_id} of user {user['_id']} - subscription expired")
        return True
    if plan_store.limits(plan)[feature].mode == "locked":
        logger.info(f"⏭️ Skipping book {book_id} of user {user['_id']} - {feature} is locked on the {plan} plan")
        return True
    if await (quota.family_over_cost_cap(user, book_id) if is_family else quota.over_cost_cap(user)):
        logger.info(f"⏭️ Skipping book {book_id} of user {user['_id']} - monthly AI cost cap reached")
        return True
    return False


async def _has_period_insight(book_id: str, insight_type: str, tz: tzinfo) -> bool:
    """True when the book's latest real (non-placeholder) insight of `insight_type` (weekly / monthly) starts where the
    one generate_*_insight would make now in the book's zone `tz` starts: the last complete week / month, or (a quiet
    last period with activity in this one) the current period-to-date."""
    latest = await _latest_real_insight(book_id, insight_type)
    if not latest:
        return False
    if insight_type == "weekly":
        (complete, _), (to_date, _), key = get_week_date_range(tz), current_week_to_date_range(tz), "week_start"
    else:
        (complete, _), (to_date, _), key = get_month_date_range(tz), current_month_to_date_range(tz), "month_start"
    start = as_calendar_date(latest.get(key))
    if latest.get("is_period_to_date"):
        # A "so far" report counts only for the period still running. Once that period is complete, the report covered
        # just its first days: the complete period still needs its own report.
        return start == to_date.date()
    return start in {complete.date(), to_date.date()}


async def _scheduled_insight(book_id: str, tz: tzinfo, feature: str, generate, notify) -> None:
    """The book's scheduled insight of `feature` (insight_weekly / insight_monthly), made by `generate`
    (generate_weekly_insight / generate_monthly_insight) in the book's zone `tz`, announced by `notify`.

    The plan user is the user whose plan and cost cap _skip_user checks: a personal book's person, a family book's
    active owner (books_db.book_profile). Only a stored paid plan is considered (a Free user's weekly insight is locked
    and their monthly one is made on demand, main._free_monthly_insight), and _skip_user drops an ended plan, a locked
    type and a user at the cost cap. A family insight is stored and notified under the book (the notice fans out to the
    members), counts against nobody's allowance, and is skipped like the owner's own, or when the owner's spend plus
    the book's reaches the owner's monthly cost cap (R16). Never an allowance: the spend lands in ai_usage.

    A book that already has a real insight for the period this run would cover (_has_period_insight: the old cron made
    it on deploy day, or the period was already done) gets nothing: no AI call and no notice, and the run counts as done.

    An insight that can't be made (every provider failed) is logged and not retried until the next period, as before.
    """
    book = await books_db.get_book_row(book_id)
    plan_user = await books_db.book_profile(book_id) if book else None
    if plan_user is None or plan_user.get("subscription_type") not in PAID_PLANS:
        return
    label = feature.removeprefix("insight_")
    if await _has_period_insight(book_id, label, tz):
        logger.info(f"⏭️ Skipping book {book_id} - it already has its {label} insight for this period")
        return
    if await _skip_user(plan_user, feature, book_id, book["kind"] == "family"):
        return
    try:
        # background: the runner retries a rate-limited provider before falling back.
        result = await generate(book_id, notify=False, background=True, tz=tz)
    except Exception as e:  # noqa: BLE001
        logger.error(f"❌ Error generating {label} insight for {book_id}: {e}")
        return
    if not result:
        logger.warning(f"⚠️ Failed to generate {label} insight for book {book_id} (Returned None)")
        return
    logger.info(f"✅ Generated {label} insight for book {book_id} ({result.get('ai_provider')})")
    # One "insights ready" notification, only for a new real (non-placeholder) insight (a reused older insight
    # returned for a quiet period is not "new").
    if not result.get("is_placeholder") and not result.get("is_reused"):
        try:
            await notify(book_id)
        except Exception as notify_error:  # noqa: BLE001
            logger.error(f"⚠️ Failed to send {label} insights notification to {book_id}: {notify_error}")


async def _insight_profile(book_id: str) -> Optional[dict]:
    """The profile an insight prompt shows (USER, DEFAULT CURRENCY) for a book: a personal book's person (the users
    row); a family book's family name with its owner's settings (books_db.book_profile; default currency usd when the
    owner's account is gone). None when it isn't a book (e.g. a person's id)."""
    book = await books_db.get_book_row(book_id)
    if book is None:
        return None
    profile = await books_db.book_profile(book_id)
    if book["kind"] == "personal":
        return profile
    family = await families_db.get_family(book["family_id"])
    owner = profile or {}
    return {**owner, "name": (family or {}).get("name") or "Family",
            "default_currency": owner.get("default_currency") or "usd"}


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

    def __init__(self, message: str, rate_limited: bool = False, provider: Optional[str] = None,
                 billing: Optional[bool] = None):
        super().__init__(message)
        self.rate_limited = rate_limited
        self.provider = provider
        # Set (True/False) only when the provider runner's failures decided the outcome; the
        # rate-limit / billing verdict then comes from those failures, not from message text.
        self.billing = billing


def _runner_verdict(exc: Optional[BaseException]) -> Optional[InsightAIError]:
    """The first InsightAIError on the exception chain built from the runner's failures, if any."""
    for e in _errors.exception_chain(exc):
        if isinstance(e, InsightAIError) and e.billing is not None:
            return e
    return None


def _ai_error(e: AllProvidersFailed, feature: str, label: str) -> InsightAIError:
    """Every provider in the feature's chain failed: an InsightAIError for main.py's HTTP mapping."""
    kinds = ", ".join(f"{f.provider}/{f.model}={f.kind}" for f in e.failures) or "no provider available"
    return InsightAIError(
        f"{label}: every AI provider failed ({kinds})",
        rate_limited=e.all_rate_limited,
        provider=_ai_settings.resolve(feature).main.provider,
        billing=any(f.kind == "billing" for f in e.failures),
    )


# The patterns and matching logic live in ai_providers.errors; these are thin wrappers so the
# names used by main.py and the insights code keep working.
_RATE_LIMIT_TEXT = _errors.RATE_LIMIT_TEXT
_BILLING_TEXT = _errors.BILLING_TEXT


def is_billing_error(exc: Optional[BaseException]) -> bool:
    """True when the AI provider refused for lack of credit/billing, following __cause__/__context__."""
    verdict = _runner_verdict(exc)
    if verdict is not None:
        return bool(verdict.billing)
    return _errors.is_billing_error(exc)


def is_rate_limit_error(exc: Optional[BaseException]) -> bool:
    """True for openai.RateLimitError, Gemini 429 / RESOURCE_EXHAUSTED and similar, following __cause__/__context__.

    Billing / out-of-credit refusals are excluded (see is_billing_error): they are not
    transient, so telling users to retry in a few minutes would be wrong. When the provider
    runner's failures decided the outcome, it is a rate limit only if every provider was rate limited.
    """
    verdict = _runner_verdict(exc)
    if verdict is not None:
        return verdict.rate_limited and not verdict.billing
    return _errors.is_rate_limit_error(exc, extra=lambda e: isinstance(e, InsightAIError) and e.rate_limited)


# Stored insights always have non-blank content (enforced by the database; legacy
# documents with content None / "" were never migrated, as the code treated them as missing).
# One insight per book and period, whichever provider wrote it: reads take the newest row.
async def latest_valid_insight(book_id: str, insight_type: str):
    """Latest stored insight (placeholder or real) of the book, of any provider, or None."""
    return await insights_db.latest(book_id, insight_type)


async def _latest_real_insight(book_id: str, insight_type: str):
    """Latest stored non-placeholder insight of the book, of any provider, for the type (None if none)."""
    return await insights_db.latest(book_id, insight_type, real_only=True)


async def book_has_insight_data(book_id: str, insight_type: str, tz: tzinfo) -> bool:
    """
    Same notion of "has activity" as generate_*_insight: transactions in the last complete
    period OR in the current period-to-date (a brand-new user's first week), any goals, or
    running budgets (window contains today and status active/exceeded, after refreshing
    stale stored statuses). Used to replace a stored placeholder insight once real data exists.
    `tz`: the zone generate_*_insight would use (the book's, user_zones.book_zone).
    """
    if insight_type == "monthly":
        ranges = (get_month_date_range(tz), current_month_to_date_range(tz))
    else:
        ranges = (get_week_date_range(tz), current_week_to_date_range(tz))

    for start, end in ranges:
        if await transactions_db.has_transactions_between(book_id, start, end):
            return True
    if await goals_db.user_has_goals(book_id):
        return True
    # Cheap pre-check (any budget running today) before the refreshing lookup.
    if not await budgets_db.has_budget_containing(book_id, local_today(tz)):
        return False
    return len(await get_running_budgets(book_id)) > 0


async def _todays_placeholder(book_id: str, insight_type: str, tz: tzinfo):
    """The latest stored insight for the type if it is a placeholder generated today (in `tz`)."""
    latest = await latest_valid_insight(book_id, insight_type)
    if not latest or not latest.get("is_placeholder") or not latest.get("generated_at"):
        return None
    generated_on = local_today(tz, as_utc(latest["generated_at"]))
    return latest if generated_on == local_today(tz) else None


# Output token limits per answering provider, as before for OpenAI and Gemini (Gemini 2.5 "thinking"
# tokens count toward its limit). Claude thinks before answering and its thinking counts toward
# max_tokens, so it gets more room.
INSIGHT_MAX_TOKENS = {
    "insight_weekly": {"openai": 2500, "gemini": 8192, "claude": 12000},
    "insight_monthly": {"openai": 3000, "gemini": 8192, "claude": 12000},
    "insight_custom": {"openai": 2000, "gemini": 8192, "claude": 12000},
}
INSIGHT_TEMPERATURE = 0.7  # sent to OpenAI and Gemini as before; the Claude client never sends it


def _feature_prompt_call(feature: str, system: str, user: str, max_tokens: dict, temperature: float):
    """A runner `call` that builds the prompt for the answering target (its max tokens depend on the provider)."""
    async def call(client, t):
        prompt = Prompt(system=system, user=user, max_tokens=max_tokens[t.provider], temperature=temperature)
        return await _runner.default_call(prompt, feature)(client, t)
    return call


async def run_insight_model(feature: str, system_prompt: str, context: str, label: str, *,
                            user_id: Optional[str] = None, book_id: Optional[str] = None,
                            background: bool = False) -> _runner.RunResult:
    """Run the insight feature on its provider chain; the RunResult carries the completion and the answering target.

    The runner tracks usage under exactly one of `user_id` (a person: a personal book's insight, or the person who
    asked for a custom insight) and `book_id` (a family book's own weekly / monthly insight; see books_db.spend_owner).
    Raises InsightAIError when every provider failed (or the request itself failed).
    """
    who = f"user {user_id}" if user_id else f"book {book_id}"
    try:
        result = await _runner.run(
            feature, user_id=user_id, book_id=book_id, background=background,
            call=_feature_prompt_call(feature, system_prompt, context, INSIGHT_MAX_TOKENS[feature], INSIGHT_TEMPERATURE),
        )
    except AllProvidersFailed as e:
        raise _ai_error(e, feature, label) from e
    except Exception as e:
        # A request-level error (no fallback): same mapping as before the runner.
        raise InsightAIError(
            f"{label} request failed: {type(e).__name__}: {e}",
            rate_limited=is_rate_limit_error(e), provider=_ai_settings.resolve(feature).main.provider,
        ) from e

    c, t = result.completion, result.target
    if c.finish == "length":
        logger.warning(f"⚠️ {label} for {who} hit the output limit on {t.provider}/{t.model}")
    logger.info(
        f"🔢 [{t.provider.upper()} TOKEN USAGE - {label}] {who} | "
        f"in={c.input_tokens:,} out={c.output_tokens:,} total={c.input_tokens + c.output_tokens:,} | model={t.model}"
        + (f" | fallback from {result.fallback_from}" if result.fallback_from else "")
    )
    return result


async def _call_insight_model(feature: str, system_prompt: str, context: str, label: str, *,
                              user_id: Optional[str] = None, book_id: Optional[str] = None,
                              background: bool = False):
    """run_insight_model as (content, provider, in, out, total), for the weekly and monthly insights."""
    result = await run_insight_model(feature, system_prompt, context, label, user_id=user_id, book_id=book_id,
                                     background=background)
    c, t = result.completion, result.target
    return c.text, t.provider, c.input_tokens, c.output_tokens, c.input_tokens + c.output_tokens


async def generate_weekly_insight(book_id: str, notify: bool = False, background: bool = False, *, tz: tzinfo):
    """
    Generate the weekly insight of a book, on the "insight_weekly" provider chain. Its AI spend is the book's person's
    (a personal book) or the family book's own (books_db.spend_owner).

    notify: send the "weekly insights ready" notification. Off by default; the scheduled
    book's job sends exactly one notification. background: the scheduled job (the runner retries a rate-limited
    provider before moving on). tz: the zone of the book's week (user_zones.book_zone).
    """
    try:
        # Get date ranges
        week_start, week_end = get_week_date_range(tz)
        prev_week_start, prev_week_end = get_previous_week_date_range(tz)

        book = await books_db.get_book_row(book_id)
        user = await _insight_profile(book_id) if book else None
        if not user:
            logger.error(f"Book not found: {book_id}")
            return None

        # Get financial data processor for other data (goals/budgets)
        processor = FinancialDataProcessor(book_id, tz)

        # [FIX] Added await (Function updated to async below)
        current_week_data = await get_financial_summary(book_id, week_start, week_end)
        prev_week_data = await get_financial_summary(book_id, prev_week_start, prev_week_end)

        goals = await processor.get_user_goals()
        budgets = await report_budgets(book_id, week_start, week_end)

        # Efficient check for activity
        total_tx_count = _tx_count(current_week_data)
        has_activity = total_tx_count > 0 or len(goals) > 0 or len(budgets) > 0
        period_to_date = False

        if not has_activity:
            # Nothing in the last complete week. Before falling back to the welcome
            # placeholder: (1) a user with transactions in the CURRENT (incomplete) week gets
            # a period-to-date insight; (2) a returning user with real insight history keeps
            # seeing their latest real insight (no placeholder is stored over it).
            ptd_start, ptd_end = current_week_to_date_range(tz)
            ptd_data = await get_financial_summary(book_id, ptd_start, ptd_end)
            if _tx_count(ptd_data) > 0:
                logger.info(f"ℹ️  No activity last week for book {book_id}; generating week-to-date insight")
                period_to_date = True
                prev_week_data = current_week_data  # last complete week = comparison baseline
                current_week_data = ptd_data
                week_start, week_end = ptd_start, ptd_end
                budgets = await report_budgets(book_id, week_start, week_end)
                has_activity = True
            else:
                latest_real = await _latest_real_insight(book_id, "weekly")
                if latest_real:
                    logger.info(f"ℹ️  Quiet week for book {book_id}; keeping latest real weekly insight")
                    # is_reused is transient (not stored): callers must not announce it as new.
                    return {**latest_real, "is_reused": True}

        if not has_activity:
            logger.info(f"ℹ️  No financial activity found for book {book_id}, returning placeholder insight")
            # Don't pile up a new placeholder on every request: reuse today's.
            existing_placeholder = await _todays_placeholder(book_id, "weekly", tz)
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
                "book_id": book_id,
                "content": placeholder_content,
                "content_mm": None,
                "generated_at": now,
                "week_start": week_start.date(),
                "week_end": week_end.date(),
                "insight_type": "weekly",
                # No AI call: stored under the feature's current main provider.
                "ai_provider": _ai_settings.resolve("insight_weekly").main.provider,
                "expires_at": None,
                "is_placeholder": True
            }

            # [FIX] Added await
            await insights_db.insert_insight(new_insight)
            return new_insight

        # [FIX] Added await
        previous_insight = await _latest_real_insight(book_id, "weekly")

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
            today=local_today(tz),
        )

        system_prompt = _build_weekly_system_prompt()

        insights_content, ai_provider, input_tokens, output_tokens, total_tokens = await _call_insight_model(
            "insight_weekly", system_prompt, context, "Weekly Insight", background=background,
            **books_db.spend_owner(book),
        )

        if not _has_content(insights_content):
            logger.error(f"❌ {ai_provider} returned empty weekly insight for book {book_id}; not saving")
            return None

        insight_id = str(uuid.uuid4())
        now = datetime.now(UTC)

        new_insight = {
            "_id": insight_id,
            "book_id": book_id,
            "content": insights_content,
            "content_mm": None,
            "generated_at": now,
            "week_start": week_start.date(),
            "week_end": week_end.date(),
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
            await notify_weekly_insights_generated(book_id)
        logger.info(f"✅ Weekly insight generated for book {book_id} using {ai_provider}")
        return new_insight

    except InsightAIError as e:
        # Propagate so routes can map it (429 for provider rate limits, 502/503 otherwise);
        # the scheduled job catches it per user and moves on.
        logger.error(f"AI error generating weekly insight for book {book_id}: {e}")
        raise
    except Exception as e:
        logger.error(f"Error generating weekly insight for book {book_id}: {str(e)}")
        import traceback
        traceback.print_exc()
        return None



async def get_financial_summary(book_id, start_date, end_date):
    """
    Financial totals per currency and the top 5 spending categories per currency, summed in
    the database (summary stats instead of raw rows). Income and spending only: transfers are left out.
    """
    summary = await transactions_db.currency_totals(book_id, date_from=start_date, date_to=end_date)
    top_items = {}
    for c in await transactions_db.category_totals(book_id, type_="outflow", date_from=start_date, date_to=end_date):
        items = top_items.setdefault(c["currency"], [])
        if len(items) < 5:
            items.append({"category": f"{c['main_category']} > {c['sub_category']}", "amount": c["total"]})
    return {
        "summary": [
            {"_id": s["currency"], "inflow": s["total_inflow"], "outflow": s["total_outflow"], "count": s["count"]}
            for s in summary if s["count"]  # a currency with only transfers has no income or spending
        ],
        "categories": [{"_id": currency, "top_items": items} for currency, items in top_items.items()],
    }


def _build_weekly_system_prompt():
    """Build system prompt for weekly insights generation"""
    return """You are Ko Toe Pwar (ကိုတိုးပွား), the friendly money helper of the Toe Pwar app: an expert financial analyst providing weekly financial insights.

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


def change_text(previous: float, current: float, before: str) -> str:
    """The change from `previous` to `current` as the insight contexts print it: "+25.0%", or, with nothing in the
    earlier period (a percentage of nothing would read "+0.0%", i.e. unchanged), "none <before>" / "none in either".
    before: how the earlier period is named, e.g. "the week before"."""
    if previous > 0:
        return f"{(current - previous) / previous * 100:+.1f}%"
    return f"none {before}" if current > 0 else "none in either"


async def report_budgets(book_id: str, start, end) -> list:
    """The book's budgets whose days overlap the report period [start, end], as stored (newest first). A report on a
    finished week or month judges the budgets that ran then, not the ones running when it is made (on the Monday or
    the 1st, last period's budget has ended and the new one has almost nothing spent)."""
    return await budgets_db.budgets_overlapping(book_id, start, end)


def currency_label(code: str) -> tuple[str, str]:
    """(symbol, name) the insight contexts print money with: $ / USD, K / MMK, otherwise ฿ / THB."""
    return ("$" if code == "usd" else ("K" if code == "mmk" else "฿"),
            "USD" if code == "usd" else ("MMK" if code == "mmk" else "THB"))


def _weekly_money(sym: str, amount: float) -> str:
    return f"{sym}{amount:,.2f}"


def budget_days(budget, today: Optional[date] = None) -> str:
    """", Nov 01 to Nov 30, 2026" (", ended" after it when `today` is past its last day); "" for a budget without
    dates."""
    start, end = as_calendar_date(budget.get("start_date")), as_calendar_date(budget.get("end_date"))
    if not start or not end:
        return ""
    return f", {start:%b %d} to {end:%b %d, %Y}" + (", ended" if today and end < today else "")


def goals_budgets_context(goals, budgets, money=_weekly_money, *, header: str = "ACTIVE BUDGETS",
                          today: Optional[date] = None) -> str:
    """The goals and budgets block of an insight context (weekly and custom): per currency, at most 5 active goals
    with their progress, then each budget (with its days, when it has them) with its total and at most 5 category
    allocations. "" when both are empty. money(symbol, amount) formats each amount (the weekly format by default).
    header: the budgets block's title; today: marks budgets that have ended."""
    context = ""
    if goals:
        context += "\n=== FINANCIAL GOALS STATUS ===\n\n"
        goals_by_currency = {}
        for g in goals:
            goals_by_currency.setdefault(g.get("currency", "usd"), []).append(g)

        for curr, curr_goals in goals_by_currency.items():
            sym, name = currency_label(curr)
            active_goals = [g for g in curr_goals if g["status"] == "active"]

            context += f"{name} Goals:\n"
            for goal in active_goals[:5]:
                progress = (goal["current_amount"] / goal["target_amount"] * 100) if goal["target_amount"] > 0 else 0
                context += f"  - {goal['name']}: {money(sym, goal['current_amount'])} / {money(sym, goal['target_amount'])} ({progress:.1f}%)\n"
            context += "\n"

    if budgets:
        context += f"\n=== {header} ===\n\n"
        budgets_by_currency = {}
        for b in budgets:
            budgets_by_currency.setdefault(b.get("currency", "usd"), []).append(b)

        for curr, curr_budgets in budgets_by_currency.items():
            sym, name = currency_label(curr)

            context += f"{name} Budgets:\n"
            for budget in curr_budgets:
                utilization = budget.get("percentage_used", 0)
                status_emoji = "✅" if utilization < 80 else "⚠️" if utilization < 100 else "🚨"
                context += f"  {status_emoji} {budget['name']} ({budget['period']}{budget_days(budget, today)}):\n"
                context += f"     Total: {money(sym, budget['total_spent'])} / {money(sym, budget['total_budget'])} ({utilization:.1f}%)\n"

                # Show category breakdowns
                for cat_budget in budget.get('category_budgets', [])[:5]:
                    cat_util = cat_budget.get('percentage_used', 0)
                    context += f"       - {allocation_label(cat_budget)}: {money(sym, cat_budget['spent_amount'])} / {money(sym, cat_budget['allocated_amount'])} ({cat_util:.1f}%)\n"
                context += "\n"
    return context


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
    *,
    today: date,
):
    """Build context for weekly insights using aggregated data.

    period_to_date=True: current_week_data covers the current, still-running week
    (Monday..today) and prev_week_data the last complete week. today: the book's today.
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

TODAY: {today.strftime('%A, %B %d, %Y')}

REPORT PERIOD: CURRENT WEEK TO DATE (WEEK STILL IN PROGRESS): {week_start.strftime('%B %d, %Y')} (Monday) to {week_end.strftime('%B %d, %Y')} (today)
NOTE: The last complete week had no transactions, so this report covers the current week so far.
Do NOT call this period "last week", and do not treat the remaining days of the week as zero spending.

=== THIS WEEK'S FINANCIAL ACTIVITY SO FAR ===

Total Transactions: {total_tx}

"""
    else:
        context = f"""USER: {user.get('name', 'User')}
DEFAULT CURRENCY: {user.get('default_currency', 'usd').upper()}

TODAY: {today.strftime('%A, %B %d, %Y')} (Monday Morning)

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

            before = "the last complete week" if period_to_date else "the week before"
            income_change = change_text(prev["inflow"], current["inflow"], before)
            expense_change = change_text(prev["outflow"], current["outflow"], before)

            context += f"{currency_name}:\n"
            context += f"  Income: {currency_symbol}{prev['inflow']:,.2f} → {currency_symbol}{current['inflow']:,.2f} ({income_change})\n"
            context += f"  Expenses: {currency_symbol}{prev['outflow']:,.2f} → {currency_symbol}{current['outflow']:,.2f} ({expense_change})\n\n"

    context += goals_budgets_context(
        goals, budgets, today=today,
        header="BUDGETS DURING THIS WEEK SO FAR" if period_to_date else "BUDGETS DURING LAST WEEK")

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


async def weekly_insight_for_book(book_id: str, today: date, tz: tzinfo) -> None:
    """The book's weekly insight (local_jobs, Monday 05:00 on the book's clock: a personal book's person's, a family
    book's owner's), covering the book's last complete week (_scheduled_insight)."""
    await _scheduled_insight(book_id, tz, "insight_weekly", generate_weekly_insight, notify_weekly_insights_generated)


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
# translation plenty of room. Gemini 2.5 and Claude "thinking" tokens also count toward
# the limit (the Claude client streams requests this large).
TRANSLATION_MAX_TOKENS = {"openai": 8000, "gemini": 32768, "claude": 32000}
TRANSLATION_TEMPERATURE = 0.3  # sent to OpenAI and Gemini as before; the Claude client never sends it
# Max English characters per chunk when a single-shot translation was truncated.
TRANSLATION_CHUNK_CHARS = 2500


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


def _translation_call(english_content: str):
    """A runner `call` that translates `english_content` on ONE target, cut-off retry included.

    The single-shot attempt and, when it is cut off at the output limit (completion finish "length",
    whichever provider), the section-by-section retry all run on the same target, so a translation never
    mixes providers. A chunk that is still cut off (or refused, filtered or empty) raises UnusableAnswer:
    the runner then tries the next provider with the whole text. Every provider request is billed, so the
    returned Completion (or the error) lists them in `requests`, and the runner writes one usage row per
    request: the cut-off first attempt "rejected", the chunks whose text is used "used". On a give-up or an
    error after some chunks, every request billed so far is recorded as "rejected".
    """
    feature = "insight_translation"

    async def translate(client, t, text):
        prompt = Prompt(system=_TRANSLATION_SYSTEM_PROMPT, user=f"Translate this to Myanmar:\n\n{text}",
                        max_tokens=TRANSLATION_MAX_TOKENS[t.provider], temperature=TRANSLATION_TEMPERATURE)
        return await _runner.default_call(prompt, feature)(client, t)

    async def call(client, t):
        first = await translate(client, t, english_content)
        if first.finish != "length":
            return first  # the runner checks refusal / filtered / empty
        chunks = _split_markdown_sections(english_content)
        logger.warning(f"⚠️ Myanmar translation truncated on {t.provider}/{t.model}; "
                       f"retrying in {len(chunks)} section chunk(s)")
        billed = [replace(first, text="", outcome="rejected")]  # the cut-off text is replaced by the chunks

        def spent(text=""):
            """One Completion listing every billed request (its totals are their sums)."""
            return Completion(text, sum(r.input_tokens for r in billed), sum(r.output_tokens for r in billed), "stop",
                              served_model=next((r.served_model for r in billed if r.served_model), None),
                              cached_input_tokens=sum(r.cached_input_tokens for r in billed),
                              cache_write_tokens=sum(r.cache_write_tokens for r in billed),
                              estimated=any(r.estimated for r in billed), requests=tuple(billed))
        if len(chunks) <= 1:
            raise UnusableAnswer("translation cut off at the output limit", completion=spent())
        parts = []
        for chunk in chunks:
            try:
                c = await translate(client, t, chunk)
            except Exception as e:
                try:
                    e.billed_usage = spent()  # the requests billed before this error (see ai_providers.errors)
                except AttributeError:  # an exception type that takes no attributes: nothing to pass on
                    pass
                raise
            billed.append(replace(c, text=""))
            if c.finish == "refusal":
                raise UnusableAnswer("refusal", completion=spent())
            if c.finish != "stop" or not _has_content(c.text):
                raise UnusableAnswer(f"translation chunk {c.finish if c.finish != 'stop' else 'empty'}",
                                     completion=spent())
            parts.append(c.text.strip())
        return spent("\n\n".join(parts))

    return call


async def translate_insight_to_myanmar(
    english_content: str,
    user_id: Optional[str] = None,
    is_placeholder: bool = None,
    book_id: Optional[str] = None,
) -> str:
    """
    Translate English insights to Myanmar, on the "insight_translation" provider chain. The AI spend is recorded under
    `user_id` (the person) or, for a family book's own insight, `book_id` (the family book).

    Pass the insight's stored is_placeholder flag: placeholders get a canned translation
    and are never sent to the paid translation API. If the model output is truncated the
    content is re-translated section by section on the same provider (see _translation_call);
    if that is still truncated the next provider in the chain tries, and when none can, an
    InsightAIError is raised so callers never cache an incomplete content_mm.
    """
    try:
        if is_placeholder or (is_placeholder is None and _is_placeholder_text(english_content)):
            logger.info("Returning Myanmar placeholder (no AI call)")
            return MYANMAR_PLACEHOLDER

        if not _has_content(english_content):
            raise Exception("No content to translate")

        feature = "insight_translation"
        try:
            result = await _runner.run(feature, user_id=user_id, book_id=book_id,
                                       call=_translation_call(english_content))
        except AllProvidersFailed as e:
            raise _ai_error(e, feature, "Translation") from e
        return result.completion.text

    except InsightAIError as e:
        logger.error(f"Translation error: {e}")
        raise
    except Exception as e:
        logger.error(f"Translation error: {e}")
        # InsightAIError (an Exception subclass) lets routes map provider 429s to HTTP 429.
        raise InsightAIError(
            f"Failed to translate insights: {e}",
            rate_limited=is_rate_limit_error(e),
            provider=_ai_settings.resolve("insight_translation").main.provider,
        ) from e


def get_month_date_range(tz: tzinfo):
    """
    Start/end of the most recent COMPLETE calendar month, with "today" evaluated in the
    book's zone `tz` (see get_week_date_range).
    """
    return previous_month_range(tz)


def get_previous_month_date_range(tz: tzinfo):
    """Start/end of the month BEFORE the most recent complete month (for comparison)."""
    return month_before_previous_range(tz)


async def generate_monthly_insight(book_id: str, notify: bool = False, background: bool = False, *, tz: tzinfo):
    """
    Generate the monthly insight of a book, on the "insight_monthly" provider chain. Its AI spend is the book's
    person's (a personal book) or the family book's own (books_db.spend_owner).

    notify: send the "monthly insights ready" notification. Off by default; the scheduled
    book's job sends exactly one notification. background: the scheduled job (the runner retries a rate-limited
    provider before moving on). tz: the zone of the book's month (user_zones.book_zone).
    """
    try:
        # Get date ranges
        month_start, month_end = get_month_date_range(tz)
        prev_month_start, prev_month_end = get_previous_month_date_range(tz)

        book = await books_db.get_book_row(book_id)
        user = await _insight_profile(book_id) if book else None
        if not user:
            logger.error(f"Book not found: {book_id}")
            return None

        # Get financial data processor
        processor = FinancialDataProcessor(book_id, tz)

        # [FIX] Added await (Function is now async)
        current_month_data = await get_financial_summary(book_id, month_start, month_end)
        prev_month_data = await get_financial_summary(book_id, prev_month_start, prev_month_end)

        # Get goals & the budgets that ran during the month
        goals = await processor.get_user_goals()
        budgets = await report_budgets(book_id, month_start, month_end)

        # Check for activity
        total_tx_count = _tx_count(current_month_data)
        has_activity = total_tx_count > 0 or len(goals) > 0 or len(budgets) > 0
        period_to_date = False

        if not has_activity:
            # Nothing in the last complete month: month-to-date insight if the current month
            # has transactions, else keep the latest real insight (no placeholder over history).
            ptd_start, ptd_end = current_month_to_date_range(tz)
            ptd_data = await get_financial_summary(book_id, ptd_start, ptd_end)
            if _tx_count(ptd_data) > 0:
                logger.info(f"ℹ️  No activity last month for book {book_id}; generating month-to-date insight")
                period_to_date = True
                prev_month_data = current_month_data  # last complete month = comparison baseline
                current_month_data = ptd_data
                month_start, month_end = ptd_start, ptd_end
                budgets = await report_budgets(book_id, month_start, month_end)
                has_activity = True
            else:
                latest_real = await _latest_real_insight(book_id, "monthly")
                if latest_real:
                    logger.info(f"ℹ️  Quiet month for book {book_id}; keeping latest real monthly insight")
                    return {**latest_real, "is_reused": True}

        if not has_activity:
            logger.info(f"ℹ️  No financial activity found for book {book_id}, returning placeholder insight")
            # Don't pile up a new placeholder on every request: reuse today's.
            existing_placeholder = await _todays_placeholder(book_id, "monthly", tz)
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
                "book_id": book_id,
                "content": placeholder_content,
                "content_mm": None,
                "generated_at": now,
                "month_start": month_start.date(),
                "month_end": month_end.date(),
                "insight_type": "monthly",
                # No AI call: stored under the feature's current main provider.
                "ai_provider": _ai_settings.resolve("insight_monthly").main.provider,
                "expires_at": None,
                "is_placeholder": True
            }

            # [FIX] Added await
            await insights_db.insert_insight(new_insight)
            return new_insight

        # [FIX] Added await
        previous_insight = await _latest_real_insight(book_id, "monthly")

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
            today=local_today(tz),
        )

        system_prompt = _build_monthly_system_prompt()

        insights_content, ai_provider, input_tokens, output_tokens, total_tokens = await _call_insight_model(
            "insight_monthly", system_prompt, context, "Monthly Insight", background=background,
            **books_db.spend_owner(book),
        )

        if not _has_content(insights_content):
            logger.error(f"❌ {ai_provider} returned empty monthly insight for book {book_id}; not saving")
            return None

        insight_id = str(uuid.uuid4())
        now = datetime.now(UTC)

        new_insight = {
            "_id": insight_id,
            "book_id": book_id,
            "content": insights_content,
            "content_mm": None,
            "generated_at": now,
            "month_start": month_start.date(),
            "month_end": month_end.date(),
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
            await notify_monthly_insights_generated(book_id)
        logger.info(f"✅ Monthly insight generated for book {book_id} using {ai_provider}")
        return new_insight

    except InsightAIError as e:
        logger.error(f"AI error generating monthly insight for book {book_id}: {e}")
        raise
    except Exception as e:
        logger.error(f"Error generating monthly insight for book {book_id}: {str(e)}")
        import traceback
        traceback.print_exc()
        return None


def _build_monthly_system_prompt():
    """Build system prompt for monthly insights generation"""
    return """You are Ko Toe Pwar (ကိုတိုးပွား), the friendly money helper of the Toe Pwar app: an expert financial analyst providing monthly financial insights.

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
    *,
    today: date,
):
    """Build context for monthly insights using aggregated data.

    period_to_date=True: current_month_data covers the current, still-running month
    (1st..today) and prev_month_data the last complete month. today: the book's today.
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

TODAY: {today.strftime('%A, %B %d, %Y')}

REPORT PERIOD: CURRENT MONTH TO DATE (MONTH STILL IN PROGRESS): {month_start.strftime('%B %d, %Y')} to {month_end.strftime('%B %d, %Y')} (today)
NOTE: The last complete month had no transactions, so this report covers the current month so far.
Do NOT call this period "last month", and do not treat the remaining days of the month as zero spending.

=== THIS MONTH'S FINANCIAL ACTIVITY SO FAR ===

Total Transactions: {total_tx}

"""
    else:
        context = f"""USER: {user.get('name', 'User')}
DEFAULT CURRENCY: {user.get('default_currency', 'usd').upper()}

TODAY: {today.strftime('%A, %B %d, %Y')} (1st of the Month)

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

            before = "the last complete month" if period_to_date else "the month before"
            income_change = change_text(prev["inflow"], current["inflow"], before)
            expense_change = change_text(prev["outflow"], current["outflow"], before)

            context += f"{currency_name}:\n"
            context += f"  Income: {currency_symbol}{prev['inflow']:,.2f} → {currency_symbol}{current['inflow']:,.2f} ({income_change})\n"
            context += f"  Expenses: {currency_symbol}{prev['outflow']:,.2f} → {currency_symbol}{current['outflow']:,.2f} ({expense_change})\n\n"

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

    # The budgets that ran during the report's month (report_budgets), each with its days
    if budgets:
        context += ("\n=== BUDGETS DURING THIS MONTH SO FAR ===\n\n" if period_to_date
                    else "\n=== BUDGETS DURING LAST MONTH ===\n\n")
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
                context += f"  {status_emoji} {budget['name']} ({budget['period']}{budget_days(budget, today)}):\n"
                context += f"     Total: {sym}{budget['total_spent']:,.2f} / {sym}{budget['total_budget']:,.2f} ({utilization:.1f}%)\n"

                # Show category breakdowns
                for cat_budget in budget.get('category_budgets', [])[:8]:
                    cat_util = cat_budget.get('percentage_used', 0)
                    context += f"       - {allocation_label(cat_budget)}: {sym}{cat_budget['spent_amount']:,.2f} / {sym}{cat_budget['allocated_amount']:,.2f} ({cat_util:.1f}%)\n"
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


async def monthly_insight_for_book(book_id: str, today: date, tz: tzinfo) -> None:
    """The book's monthly insight (local_jobs, the 1st at 06:00 on the book's clock), covering the book's last complete
    month (_scheduled_insight). A Free user gets theirs on demand instead (main._free_monthly_insight)."""
    await _scheduled_insight(book_id, tz, "insight_monthly", generate_monthly_insight, notify_monthly_insights_generated)
