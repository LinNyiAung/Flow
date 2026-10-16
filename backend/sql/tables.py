"""PostgreSQL schema (SQLAlchemy Core). Single source of truth for Alembic migrations.

Conventions (see docs/postgres-migration-plan.md):
- Primary keys are TEXT and keep the existing ids (uuid strings, "{parent}:{YYYYMMDD}").
- Money is NUMERIC (exact); AI cost NUMERIC(12,6).
- Wall-clock dates (transaction date, budget start/end, goal target date) keep today's
  meaning: local time stored with a UTC label, in timestamptz. Instants are real UTC.
- Statuses/types are TEXT + CHECK constraints rather than Postgres enum types.
- user_id foreign keys cascade on delete, so deleting a user is one atomic operation.
"""
from sqlalchemy import (
    Boolean, CheckConstraint, Column, Date, DateTime, ForeignKey, Index, Integer, MetaData,
    Numeric, SmallInteger, Table, Text, UniqueConstraint, func, text,
)
from sqlalchemy.dialects.postgresql import JSONB

metadata = MetaData(naming_convention={
    "ix": "ix_%(table_name)s_%(column_0_N_name)s",
    "uq": "uq_%(table_name)s_%(column_0_N_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
})

TS = DateTime(timezone=True)
MONEY = Numeric(18, 2)
CURRENCIES = "('usd','mmk','thb')"


def _user_fk(nullable: bool = False) -> Column:
    return Column("user_id", Text, ForeignKey("users.id", ondelete="CASCADE"), nullable=nullable, index=True)


users = Table(
    "users", metadata,
    Column("id", Text, primary_key=True),
    Column("name", Text, nullable=False),
    Column("email", Text, nullable=False),
    Column("password", Text, nullable=False),  # bcrypt hash
    Column("password_version", Integer, nullable=False, server_default="0"),
    Column("password_changed_at", TS),
    Column("subscription_type", Text, nullable=False, server_default="free"),
    Column("subscription_expires_at", TS),  # NULL = lifetime when premium
    Column("premium_ended_at", TS),
    Column("has_claimed_free_trial", Boolean, nullable=False, server_default=text("false")),
    Column("default_currency", Text, nullable=False, server_default="usd"),
    Column("language", Text, nullable=False, server_default="en"),
    Column("is_verified", Boolean, nullable=False, server_default=text("false")),
    Column("verified_at", TS),
    Column("verified_via", Text),
    Column("verification_token", Text),
    Column("verification_token_expires_at", TS),
    Column("password_reset_otp", Text),  # HMAC of the OTP, never the code itself
    Column("password_reset_otp_expiry", TS),
    Column("password_reset_attempts", Integer),
    Column("password_reset_attempts_since", TS),
    Column("password_reset_locked_until", TS),
    Column("password_reset_token", Text),  # sha256 of the reset token
    Column("password_reset_token_expiry", TS),
    Column("fcm_token", Text),
    Column("ai_data_stale", Boolean, nullable=False, server_default=text("false")),
    Column("created_at", TS, nullable=False, server_default=func.now()),
    CheckConstraint("subscription_type IN ('free','premium')", name="subscription_type"),
    CheckConstraint(f"default_currency IN {CURRENCIES}", name="default_currency"),
    CheckConstraint("language IN ('en','my')", name="language"),
    CheckConstraint("password_version >= 0", name="password_version"),
)
Index("uq_users_lower_email", func.lower(users.c.email), unique=True)
Index("uq_users_fcm_token", users.c.fcm_token, unique=True, postgresql_where=users.c.fcm_token.isnot(None))
Index("ix_users_premium", users.c.subscription_type, users.c.subscription_expires_at)
Index("ix_users_created_at", users.c.created_at)

transactions = Table(
    "transactions", metadata,
    Column("id", Text, primary_key=True),
    _user_fk(),
    Column("type", Text, nullable=False),
    Column("main_category", Text, nullable=False),
    Column("sub_category", Text, nullable=False),
    Column("amount", MONEY, nullable=False),
    Column("currency", Text, nullable=False, server_default="usd"),
    Column("date", TS, nullable=False),
    Column("description", Text),
    Column("recurrence_enabled", Boolean, nullable=False, server_default=text("false")),
    Column("recurrence_frequency", Text),
    Column("recurrence_day_of_week", SmallInteger),
    Column("recurrence_day_of_month", SmallInteger),
    Column("recurrence_month", SmallInteger),
    Column("recurrence_day_of_year", SmallInteger),
    Column("recurrence_end_date", TS),
    Column("recurrence_last_created_date", TS),
    Column("parent_transaction_id", Text, ForeignKey("transactions.id", ondelete="SET NULL")),
    Column("created_at", TS, nullable=False, server_default=func.now()),
    Column("updated_at", TS, nullable=False, server_default=func.now()),
    CheckConstraint("type IN ('inflow','outflow')", name="type"),
    CheckConstraint("amount > 0 AND amount < 1e16", name="amount_positive_finite"),
    CheckConstraint(f"currency IN {CURRENCIES}", name="currency"),
    CheckConstraint("recurrence_frequency IS NULL OR recurrence_frequency IN ('daily','weekly','monthly','annually')",
                    name="recurrence_frequency"),
    CheckConstraint("NOT recurrence_enabled OR recurrence_frequency IS NOT NULL", name="recurrence_needs_frequency"),
)
Index("ix_transactions_user_date", transactions.c.user_id, transactions.c.date)
Index("ix_transactions_user_type_date", transactions.c.user_id, transactions.c.type, transactions.c.date)
Index("ix_transactions_user_currency", transactions.c.user_id, transactions.c.currency)
Index("ix_transactions_parent_date", transactions.c.parent_transaction_id, transactions.c.date)
Index("ix_transactions_recurring", transactions.c.recurrence_enabled, postgresql_where=transactions.c.recurrence_enabled)
Index("ix_transactions_created_at", transactions.c.created_at)

goals = Table(
    "goals", metadata,
    Column("id", Text, primary_key=True),
    _user_fk(),
    Column("name", Text, nullable=False),
    Column("goal_type", Text, nullable=False),
    Column("status", Text, nullable=False, server_default="active"),
    Column("target_amount", MONEY, nullable=False),
    Column("current_amount", MONEY, nullable=False, server_default="0"),
    Column("currency", Text, nullable=False, server_default="usd"),
    Column("target_date", TS),
    Column("achieved_at", TS),
    Column("created_at", TS, nullable=False, server_default=func.now()),
    Column("updated_at", TS, nullable=False, server_default=func.now()),
    CheckConstraint("goal_type IN ('savings','debt_reduction','large_purchase')", name="goal_type"),
    CheckConstraint("status IN ('active','achieved')", name="status"),
    CheckConstraint("target_amount > 0 AND target_amount < 1e16", name="target_positive_finite"),
    CheckConstraint("current_amount >= 0 AND current_amount < 1e16", name="current_non_negative_finite"),
    CheckConstraint(f"currency IN {CURRENCIES}", name="currency"),
)
Index("ix_goals_user_status_currency", goals.c.user_id, goals.c.status, goals.c.currency)
Index("ix_goals_status_target_date", goals.c.status, goals.c.target_date)

budgets = Table(
    "budgets", metadata,
    Column("id", Text, primary_key=True),
    _user_fk(),
    Column("name", Text, nullable=False),
    Column("description", Text),
    Column("period", Text, nullable=False),
    Column("currency", Text, nullable=False, server_default="usd"),
    Column("start_date", TS, nullable=False),
    Column("end_date", TS, nullable=False),
    Column("total_budget", MONEY, nullable=False),
    Column("total_spent", MONEY, nullable=False, server_default="0"),
    Column("remaining_budget", MONEY, nullable=False, server_default="0"),
    Column("percentage_used", Numeric(9, 2), nullable=False, server_default="0"),
    Column("status", Text, nullable=False),
    Column("is_active", Boolean, nullable=False, server_default=text("false")),
    Column("auto_create_enabled", Boolean, nullable=False, server_default=text("false")),
    Column("auto_create_with_ai", Boolean, nullable=False, server_default=text("false")),
    Column("parent_budget_id", Text, ForeignKey("budgets.id", ondelete="SET NULL")),
    Column("rolled_over_to", Text, ForeignKey("budgets.id", ondelete="SET NULL")),
    Column("auto_create_claimed_at", TS),
    Column("started_notified", Boolean, nullable=False, server_default=text("false")),
    Column("started_notified_at", TS),
    Column("ending_soon_notified", Boolean, nullable=False, server_default=text("false")),
    Column("ending_soon_notified_at", TS),
    Column("created_at", TS, nullable=False, server_default=func.now()),
    Column("updated_at", TS, nullable=False, server_default=func.now()),
    CheckConstraint("period IN ('weekly','monthly','yearly','custom')", name="period"),
    CheckConstraint("status IN ('upcoming','active','completed','exceeded')", name="status"),
    CheckConstraint(f"currency IN {CURRENCIES}", name="currency"),
    CheckConstraint("end_date >= start_date", name="dates_ordered"),
    CheckConstraint("total_budget >= 0 AND total_budget < 1e16", name="total_non_negative_finite"),
    # NaN / Infinity fail "< 1e16" (NUMERIC accepts both, and NaN sorts above every number).
    CheckConstraint("total_spent < 1e16 AND remaining_budget > -1e16 AND remaining_budget < 1e16 AND percentage_used < 1e7",
                    name="totals_finite"),
)
Index("uq_budgets_rollover_child", budgets.c.user_id, budgets.c.parent_budget_id, budgets.c.start_date,
      unique=True, postgresql_where=budgets.c.parent_budget_id.isnot(None))
Index("ix_budgets_parent", budgets.c.parent_budget_id)
Index("ix_budgets_rollover_candidates", budgets.c.end_date, postgresql_where=budgets.c.auto_create_enabled)
Index("ix_budgets_user_window", budgets.c.user_id, budgets.c.currency, budgets.c.start_date, budgets.c.end_date)

budget_allocations = Table(
    "budget_allocations", metadata,
    Column("budget_id", Text, ForeignKey("budgets.id", ondelete="CASCADE"), primary_key=True),
    Column("position", SmallInteger, primary_key=True),
    Column("main_category", Text, nullable=False),  # "Main" or "Main - Sub"
    Column("allocated_amount", MONEY, nullable=False),
    Column("spent_amount", MONEY, nullable=False, server_default="0"),
    Column("percentage_used", Numeric(9, 2), nullable=False, server_default="0"),
    Column("is_exceeded", Boolean, nullable=False, server_default=text("false")),
    CheckConstraint("allocated_amount >= 0 AND allocated_amount < 1e16 AND spent_amount < 1e16 AND percentage_used < 1e7",
                    name="amounts_finite"),
)

notifications = Table(
    "notifications", metadata,
    Column("id", Text, primary_key=True),
    _user_fk(),
    Column("type", Text, nullable=False),
    Column("title", Text, nullable=False, server_default=""),
    Column("message", Text, nullable=False, server_default=""),
    # goal_id holds a goal, budget or transaction id depending on `type` (no FK).
    Column("goal_id", Text),
    Column("goal_name", Text),
    Column("currency", Text),
    Column("is_read", Boolean, nullable=False, server_default=text("false")),
    Column("reminder_threshold", SmallInteger),
    Column("reminder_target_date", Date),
    Column("created_at", TS, nullable=False, server_default=func.now()),
)
Index("ix_notifications_user_created", notifications.c.user_id, notifications.c.created_at.desc())
Index("ix_notifications_user_unread", notifications.c.user_id, postgresql_where=~notifications.c.is_read)
Index("ix_notifications_user_type_created", notifications.c.user_id, notifications.c.type, notifications.c.created_at)

notification_preferences = Table(
    "notification_preferences", metadata,
    Column("user_id", Text, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
    Column("preferences", JSONB, nullable=False, server_default=text("'{}'::jsonb")),
    Column("created_at", TS, nullable=False, server_default=func.now()),
    Column("updated_at", TS, nullable=False, server_default=func.now()),
)

insights = Table(
    "insights", metadata,
    Column("id", Text, primary_key=True),
    _user_fk(),
    Column("insight_type", Text, nullable=False),
    Column("ai_provider", Text, nullable=False),
    Column("content", Text, nullable=False),
    Column("content_mm", Text),
    Column("is_placeholder", Boolean, nullable=False, server_default=text("false")),
    Column("is_period_to_date", Boolean),
    Column("week_start", TS),
    Column("week_end", TS),
    Column("month_start", TS),
    Column("month_end", TS),
    Column("input_tokens", Integer),
    Column("output_tokens", Integer),
    Column("total_tokens", Integer),
    Column("expires_at", TS),
    Column("generated_at", TS, nullable=False, server_default=func.now()),
    CheckConstraint("insight_type IN ('weekly','monthly')", name="insight_type"),
    CheckConstraint("ai_provider IN ('openai','gemini')", name="ai_provider"),
    CheckConstraint("btrim(content) <> ''", name="content_not_blank"),
)
Index("ix_insights_latest", insights.c.user_id, insights.c.ai_provider, insights.c.insight_type,
      insights.c.generated_at.desc())

chat_sessions = Table(
    "chat_sessions", metadata,
    Column("id", Text, primary_key=True),
    _user_fk(),
    Column("created_at", TS, nullable=False, server_default=func.now()),
    Column("updated_at", TS, nullable=False, server_default=func.now()),
)
Index("ix_chat_sessions_user_updated", chat_sessions.c.user_id, chat_sessions.c.updated_at.desc())
Index("ix_chat_sessions_updated", chat_sessions.c.updated_at)

chat_messages = Table(
    "chat_messages", metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("session_id", Text, ForeignKey("chat_sessions.id", ondelete="CASCADE"), nullable=False),
    Column("role", Text, nullable=False),
    Column("content", Text, nullable=False),
    Column("timestamp", TS),
    CheckConstraint("role IN ('user','assistant')", name="role"),
)
Index("ix_chat_messages_session", chat_messages.c.session_id, chat_messages.c.id)

ai_usage = Table(
    "ai_usage", metadata,
    Column("id", Text, primary_key=True),
    _user_fk(),
    Column("feature_type", Text, nullable=False),
    Column("provider", Text, nullable=False),
    Column("model_name", Text, nullable=False),
    Column("input_tokens", Integer, nullable=False, server_default="0"),
    Column("output_tokens", Integer, nullable=False, server_default="0"),
    Column("total_tokens", Integer, nullable=False, server_default="0"),
    Column("estimated_cost_usd", Numeric(12, 6), nullable=False, server_default="0"),
    CheckConstraint("estimated_cost_usd >= 0 AND estimated_cost_usd < 1e6", name="cost_finite"),
    Column("created_at", TS, nullable=False, server_default=func.now()),
)
Index("ix_ai_usage_created", ai_usage.c.created_at)
Index("ix_ai_usage_user_created", ai_usage.c.user_id, ai_usage.c.created_at)
Index("ix_ai_usage_feature_created", ai_usage.c.feature_type, ai_usage.c.created_at)

admins = Table(
    "admins", metadata,
    Column("id", Text, primary_key=True),
    Column("name", Text, nullable=False),
    Column("email", Text, nullable=False),
    Column("password", Text, nullable=False),  # bcrypt hash
    Column("role", Text, nullable=False),
    # New admins get a random version (admin_utils.initial_admin_password_version); 0 is
    # what the code assumes for legacy admins without one.
    Column("password_version", Integer, nullable=False, server_default="0"),
    Column("password_changed_at", TS),
    Column("last_login", TS),
    Column("created_at", TS, nullable=False, server_default=func.now()),
    CheckConstraint("role IN ('super_admin','admin','moderator')", name="role"),
)
Index("uq_admins_lower_email", func.lower(admins.c.email), unique=True)

admin_action_logs = Table(
    "admin_action_logs", metadata,
    Column("id", Text, primary_key=True),
    # No foreign keys: the audit trail outlives deleted admins and users.
    Column("admin_id", Text, nullable=False),
    Column("admin_email", Text, nullable=False),
    Column("action", Text, nullable=False),
    Column("target_user_id", Text),
    Column("target_user_email", Text),
    Column("details", Text),
    Column("timestamp", TS, nullable=False, server_default=func.now()),
)
Index("ix_admin_action_logs_timestamp", admin_action_logs.c.timestamp.desc())

feedback = Table(
    "feedback", metadata,
    Column("id", Text, primary_key=True),
    _user_fk(),
    Column("user_email", Text),
    Column("user_name", Text),
    Column("category", Text, nullable=False),
    Column("message", Text, nullable=False),
    Column("rating", SmallInteger),
    Column("screenshot_url", Text),
    Column("status", Text, nullable=False, server_default="pending"),
    Column("created_at", TS, nullable=False, server_default=func.now()),
    CheckConstraint("category IN ('bug','feature_request','general','usability')", name="category"),
    CheckConstraint("status IN ('pending','reviewed','resolved')", name="status"),
    CheckConstraint("rating IS NULL OR rating BETWEEN 1 AND 5", name="rating"),
)
Index("ix_feedback_created", feedback.c.created_at.desc())

categories = Table(
    "categories", metadata,
    Column("type", Text, primary_key=True),
    Column("main_category", Text, primary_key=True),
    Column("sub_category", Text, primary_key=True),
    Column("main_position", SmallInteger, nullable=False),
    Column("sub_position", SmallInteger, nullable=False),
    CheckConstraint("type IN ('inflow','outflow')", name="type"),
)

app_versions = Table(
    "app_versions", metadata,
    Column("id", Text, primary_key=True),
    Column("version", Text, nullable=False),
    Column("platform", Text, nullable=False),
    Column("download_url", Text, nullable=False),
    Column("release_notes", Text),
    Column("is_force_update", Boolean, nullable=False, server_default=text("false")),
    Column("min_supported_version", Text),
    Column("is_active", Boolean, nullable=False, server_default=text("true")),
    Column("created_by_email", Text),
    Column("created_at", TS, nullable=False, server_default=func.now()),
    Column("updated_at", TS),
    UniqueConstraint("version", "platform", name="uq_app_versions_version_platform"),
    CheckConstraint("platform IN ('android','ios','all')", name="platform"),
)
Index("ix_app_versions_platform_active", app_versions.c.platform, app_versions.c.is_active, app_versions.c.created_at)
