"""PostgreSQL schema (SQLAlchemy Core). Single source of truth for Alembic migrations.

Conventions (see docs/postgres-migration-plan.md):
- Primary keys are TEXT and keep the existing ids (uuid strings, "{parent}:{YYYYMMDD}").
- Money is NUMERIC (exact); AI cost NUMERIC(12,6).
- Transaction dates are the local date and time the person picked, with no timezone (timestamp without time zone).
  Calendar dates (budget start/end, goal target date, recurrence end and pointer, insight bounds) are DATE; a budget's
  end date is its inclusive last day. Instants are real UTC (timestamptz).
- Statuses/types are TEXT + CHECK constraints rather than Postgres enum types.
- user_id foreign keys cascade on delete, so deleting a user is one atomic operation.
- Book data (transactions, budgets, goals, insights, custom insights) is keyed by book_id -> books.id, never by a
  person's id: a person's personal book has its own id. users holds people only.
"""
from sqlalchemy import (
    Boolean, CheckConstraint, Column, Date, DateTime, Double, ForeignKey, Index, Integer, MetaData,
    Numeric, SmallInteger, Table, Text, UniqueConstraint, func, text,
)
from sqlalchemy.dialects.postgresql import ARRAY, JSONB

metadata = MetaData(naming_convention={
    "ix": "ix_%(table_name)s_%(column_0_N_name)s",
    "uq": "uq_%(table_name)s_%(column_0_N_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
})

TS = DateTime(timezone=True)
WALL_CLOCK = DateTime(timezone=False)  # a local date and time, with no timezone
MONEY = Numeric(18, 2)
CURRENCIES = "('usd','mmk','thb')"


def _user_fk(nullable: bool = False) -> Column:
    return Column("user_id", Text, ForeignKey("users.id", ondelete="CASCADE"), nullable=nullable, index=True)


def _notice_link(name: str, table: str) -> Column:
    return Column(name, Text, ForeignKey(f"{table}.id", ondelete="SET NULL"), index=True)


def _book_fk(index: bool = True) -> Column:
    """The owner of a row of book data: deleting the book (its person or family) deletes the row."""
    return Column("book_id", Text, ForeignKey("books.id", ondelete="CASCADE"), nullable=False, index=index)


users = Table(
    "users", metadata,
    Column("id", Text, primary_key=True),
    Column("name", Text, nullable=False),
    Column("email", Text, nullable=False),
    Column("password", Text, nullable=False),  # bcrypt hash
    Column("password_version", Integer, nullable=False, server_default="0"),
    Column("password_changed_at", TS),
    Column("subscription_type", Text, nullable=False, server_default="free"),
    Column("subscription_expires_at", TS),  # NULL = lifetime when on a paid plan (plus / pro)
    Column("premium_ended_at", TS),
    Column("trial_ends_at", TS),  # set while the plan is the free-trial grant; NULL otherwise
    Column("usage_reset_at", TS),  # admin "reset usage": allowances and cost cap count from here
    Column("trial_reminder_3d_at", TS),  # when the "trial ends soon" reminder went out (each reminder is sent at most once)
    Column("trial_reminder_last_at", TS),  # when the "last day of the trial" reminder went out
    # The plan end date (subscription_expires_at) the paid-plan reminders were sent for: once per end date, so an
    # admin extension to a new end date re-arms them.
    Column("plan_reminder_3d_for", TS),  # "your plan ends soon"
    Column("plan_reminder_last_for", TS),  # "your plan ends today"
    Column("has_claimed_free_trial", Boolean, nullable=False, server_default=text("false")),
    Column("default_currency", Text, nullable=False, server_default="usd"),
    Column("language", Text, nullable=False, server_default="en"),
    Column("timezone", Text),  # the person's IANA zone, read from their phone; NULL: the default zone (tz_utils)
    Column("timezone_changed_at", TS),  # when timezone was last saved: it may change at most once per 24 hours
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
    Column("created_at", TS, nullable=False, server_default=func.now()),
    CheckConstraint("subscription_type IN ('free','plus','pro')", name="subscription_type"),
    CheckConstraint(f"default_currency IN {CURRENCIES}", name="default_currency"),
    CheckConstraint("language IN ('en','my')", name="language"),
    CheckConstraint("password_version >= 0", name="password_version"),
)
Index("uq_users_lower_email", func.lower(users.c.email), unique=True)
Index("ix_users_premium", users.c.subscription_type, users.c.subscription_expires_at)
Index("ix_users_created_at", users.c.created_at)

# One row per device a person is signed in on (its push token). A token belongs to exactly one account.
user_devices = Table(
    "user_devices", metadata,
    Column("id", Text, primary_key=True),
    _user_fk(),
    Column("token", Text, nullable=False),
    Column("created_at", TS, nullable=False, server_default=func.now()),
    Column("last_seen_at", TS, nullable=False, server_default=func.now()),  # every registration of the token
    # The exp of the sign-in token the device last registered with: after it, the device gets no pushes.
    Column("session_expires_at", TS, nullable=False),
    Column("sign_in_reminder_sent_at", TS),  # the "sign in again" reminder for the current expiry; NULL: not sent
    UniqueConstraint("token"),
)

transactions = Table(
    "transactions", metadata,
    Column("id", Text, primary_key=True),
    _book_fk(),
    Column("type", Text, nullable=False),
    Column("main_category", Text, nullable=False),
    Column("sub_category", Text, nullable=False),
    Column("amount", MONEY, nullable=False),
    Column("currency", Text, nullable=False, server_default="usd"),
    Column("date", WALL_CLOCK, nullable=False),
    Column("description", Text),
    Column("recurrence_enabled", Boolean, nullable=False, server_default=text("false")),
    Column("recurrence_frequency", Text),
    Column("recurrence_day_of_week", SmallInteger),
    Column("recurrence_day_of_month", SmallInteger),
    Column("recurrence_month", SmallInteger),
    Column("recurrence_day_of_year", SmallInteger),
    Column("recurrence_end_date", Date),
    Column("recurrence_last_created_date", Date),  # the date of the last occurrence handled
    Column("parent_transaction_id", Text, ForeignKey("transactions.id", ondelete="SET NULL")),
    # Family book: who recorded it, and the id shared by the two legs of a transfer between books.
    Column("added_by_member_id", Text, ForeignKey("family_members.id", ondelete="SET NULL")),
    Column("transfer_id", Text),
    Column("created_at", TS, nullable=False, server_default=func.now()),
    Column("updated_at", TS, nullable=False, server_default=func.now()),
    CheckConstraint("type IN ('inflow','outflow')", name="type"),
    CheckConstraint("amount > 0 AND amount < 1e16", name="amount_positive_finite"),
    CheckConstraint(f"currency IN {CURRENCIES}", name="currency"),
    CheckConstraint("recurrence_frequency IS NULL OR recurrence_frequency IN ('daily','weekly','monthly','annually')",
                    name="recurrence_frequency"),
    CheckConstraint("NOT recurrence_enabled OR recurrence_frequency IS NOT NULL", name="recurrence_needs_frequency"),
)
Index("ix_transactions_book_date", transactions.c.book_id, transactions.c.date)
Index("ix_transactions_book_type_date", transactions.c.book_id, transactions.c.type, transactions.c.date)
Index("ix_transactions_book_currency", transactions.c.book_id, transactions.c.currency)
Index("ix_transactions_parent_date", transactions.c.parent_transaction_id, transactions.c.date)
Index("ix_transactions_recurring", transactions.c.recurrence_enabled, postgresql_where=transactions.c.recurrence_enabled)
Index("ix_transactions_created_at", transactions.c.created_at)
Index("ix_transactions_transfer_id", transactions.c.transfer_id)
Index("ix_transactions_added_by_member_id", transactions.c.added_by_member_id)  # the SET NULL FK's index

# Family book. Each family owns one books row (kind 'family'); its transactions, budgets, goals and insights are stored
# under that book id. family_members.user_id is SET NULL so deleting a person never deletes family history.
families = Table(
    "families", metadata,
    Column("id", Text, primary_key=True),
    Column("name", Text, nullable=False),
    Column("created_at", TS, nullable=False, server_default=func.now()),
    Column("updated_at", TS, nullable=False, server_default=func.now()),
)

# Books own the book data. Every person has exactly one personal book and every family exactly one family book; a book's
# id is a uuid4 of its own, never equal to a user id. ai_data_stale: Ko Toe Pwar's cached view of the book is out of date.
books = Table(
    "books", metadata,
    Column("id", Text, primary_key=True),
    Column("kind", Text, nullable=False),
    Column("person_id", Text, ForeignKey("users.id", ondelete="CASCADE")),  # personal books only
    Column("family_id", Text, ForeignKey("families.id", ondelete="CASCADE")),  # family books only
    Column("ai_data_stale", Boolean, nullable=False, server_default=text("false")),
    Column("created_at", TS, nullable=False, server_default=func.now()),
    CheckConstraint("(kind = 'personal' AND person_id IS NOT NULL AND family_id IS NULL) OR "
                    "(kind = 'family' AND family_id IS NOT NULL AND person_id IS NULL)", name="kind_owner"),
)
Index("uq_books_person_id", books.c.person_id, unique=True, postgresql_where=books.c.person_id.isnot(None))
Index("uq_books_family_id", books.c.family_id, unique=True, postgresql_where=books.c.family_id.isnot(None))

family_members = Table(
    "family_members", metadata,
    Column("id", Text, primary_key=True),
    Column("family_id", Text, ForeignKey("families.id", ondelete="CASCADE"), nullable=False, index=True),
    Column("user_id", Text, ForeignKey("users.id", ondelete="SET NULL")),
    Column("display_name", Text, nullable=False),
    Column("kind", Text, nullable=False),
    Column("role", Text),  # NULL for placeholders
    Column("status", Text, nullable=False, server_default="active"),
    Column("joined_at", TS, nullable=False, server_default=func.now()),
    Column("left_at", TS),
    CheckConstraint("kind IN ('account','placeholder')", name="kind"),
    CheckConstraint("role IS NULL OR role IN ('owner','admin','member')", name="role"),
    CheckConstraint("status IN ('active','former')", name="status"),
)
Index("ix_family_members_user_id", family_members.c.user_id)
# One family per person, and one owner per family.
Index("uq_family_members_user_active", family_members.c.user_id, unique=True,
      postgresql_where=text("status = 'active' AND user_id IS NOT NULL"))
Index("uq_family_members_owner_active", family_members.c.family_id, unique=True,
      postgresql_where=text("role = 'owner' AND status = 'active'"))

family_invites = Table(
    "family_invites", metadata,
    Column("id", Text, primary_key=True),
    Column("family_id", Text, ForeignKey("families.id", ondelete="CASCADE"), nullable=False, index=True),
    Column("email", Text, nullable=False),  # stored lowercased
    Column("invited_by_member_id", Text, ForeignKey("family_members.id", ondelete="SET NULL")),
    Column("link_member_id", Text, ForeignKey("family_members.id", ondelete="SET NULL")),  # placeholder to take over
    Column("status", Text, nullable=False, server_default="pending"),
    Column("created_at", TS, nullable=False, server_default=func.now()),
    Column("expires_at", TS, nullable=False),
    CheckConstraint("status IN ('pending','accepted','declined','cancelled','expired')", name="status"),
)
Index("uq_family_invites_pending_email", family_invites.c.family_id, family_invites.c.email, unique=True,
      postgresql_where=text("status = 'pending'"))

transaction_beneficiaries = Table(
    "transaction_beneficiaries", metadata,
    Column("transaction_id", Text, ForeignKey("transactions.id", ondelete="CASCADE"), primary_key=True),
    Column("member_id", Text, ForeignKey("family_members.id", ondelete="CASCADE"), primary_key=True),
)
Index("ix_transaction_beneficiaries_member_id", transaction_beneficiaries.c.member_id)

goals = Table(
    "goals", metadata,
    Column("id", Text, primary_key=True),
    _book_fk(),
    Column("name", Text, nullable=False),
    Column("goal_type", Text, nullable=False),
    Column("status", Text, nullable=False, server_default="active"),
    Column("target_amount", MONEY, nullable=False),
    Column("currency", Text, nullable=False, server_default="usd"),
    Column("target_date", Date),
    Column("achieved_at", TS),
    Column("created_at", TS, nullable=False, server_default=func.now()),
    Column("updated_at", TS, nullable=False, server_default=func.now()),
    CheckConstraint("goal_type IN ('savings','debt_reduction','large_purchase')", name="goal_type"),
    CheckConstraint("status IN ('active','achieved')", name="status"),
    CheckConstraint("target_amount > 0 AND target_amount < 1e16", name="target_positive_finite"),
    CheckConstraint(f"currency IN {CURRENCIES}", name="currency"),
)
Index("ix_goals_book_status_currency", goals.c.book_id, goals.c.status, goals.c.currency)
Index("ix_goals_status_target_date", goals.c.status, goals.c.target_date)

# A goal's money: one row per movement (the initial contribution, an Add, a Withdraw, or the balance carried over when
# history began). What a goal holds is the sum of its entries; there is no stored total. Entries are never edited or
# deleted on their own, only with their goal. added_by_member_id: the acting member in a family book, else NULL.
goal_entries = Table(
    "goal_entries", metadata,
    Column("id", Text, primary_key=True),
    Column("goal_id", Text, ForeignKey("goals.id", ondelete="CASCADE"), nullable=False),
    Column("kind", Text, nullable=False),
    Column("amount", MONEY, nullable=False),  # signed: a withdraw is negative, every other kind positive
    Column("added_by_member_id", Text, ForeignKey("family_members.id", ondelete="SET NULL")),
    Column("created_at", TS, nullable=False, server_default=func.now()),
    CheckConstraint("kind IN ('start','add','withdraw','carried_over')", name="kind"),
    CheckConstraint("(kind = 'withdraw' AND amount < 0) OR (kind <> 'withdraw' AND amount > 0)", name="amount_sign"),
    CheckConstraint("amount > -1e16 AND amount < 1e16", name="amount_finite"),
)
Index("ix_goal_entries_goal_created", goal_entries.c.goal_id, goal_entries.c.created_at, goal_entries.c.id)
Index("ix_goal_entries_added_by_member_id", goal_entries.c.added_by_member_id)  # the SET NULL FK's index

budgets = Table(
    "budgets", metadata,
    Column("id", Text, primary_key=True),
    _book_fk(),
    Column("name", Text, nullable=False),
    Column("description", Text),
    Column("period", Text, nullable=False),
    Column("currency", Text, nullable=False, server_default="usd"),
    Column("start_date", Date, nullable=False),
    Column("end_date", Date, nullable=False),  # the inclusive last day
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
Index("uq_budgets_rollover_child", budgets.c.book_id, budgets.c.parent_budget_id, budgets.c.start_date,
      unique=True, postgresql_where=budgets.c.parent_budget_id.isnot(None))
Index("ix_budgets_parent", budgets.c.parent_budget_id)
Index("ix_budgets_rollover_candidates", budgets.c.end_date, postgresql_where=budgets.c.auto_create_enabled)
Index("ix_budgets_book_window", budgets.c.book_id, budgets.c.currency, budgets.c.start_date, budgets.c.end_date)

budget_allocations = Table(
    "budget_allocations", metadata,
    Column("budget_id", Text, ForeignKey("budgets.id", ondelete="CASCADE"), primary_key=True),
    Column("position", SmallInteger, primary_key=True),
    Column("main_category", Text, nullable=False),  # the main category only
    Column("sub_category", Text),  # NULL for a main-only line (never '')
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
    # The notice's subject: at most one typed link, set by `type` (notification_service.NOTIFICATION_LINKS). SET NULL:
    # a notice outlives the thing it was about and keeps its text, it just stops opening it.
    _notice_link("goal_id", "goals"),
    _notice_link("budget_id", "budgets"),
    _notice_link("transaction_id", "transactions"),
    _notice_link("custom_insight_id", "custom_insights"),
    _notice_link("family_invite_id", "family_invites"),
    _notice_link("family_id", "families"),
    # The book the notice is about (a family book: the app opens it in Family mode); NULL: no book.
    _notice_link("book_id", "books"),
    Column("goal_name", Text),
    Column("currency", Text),
    Column("is_read", Boolean, nullable=False, server_default=text("false")),
    Column("reminder_threshold", SmallInteger),
    Column("reminder_target_date", Date),
    Column("created_at", TS, nullable=False, server_default=func.now()),
    CheckConstraint("num_nonnulls(goal_id, budget_id, transaction_id, custom_insight_id, family_invite_id, family_id) <= 1",
                    name="one_subject"),
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

# Scheduled jobs that run at a local time (09:00 reminders, the 00:30 rollover, ...): one row per job, subject (a person
# or a book) and local date it ran for. A run first claims its row, so it runs at most once per local day; a failed
# run deletes its claim so the next tick retries.
local_job_runs = Table(
    "local_job_runs", metadata,
    Column("job", Text, primary_key=True),
    Column("subject_id", Text, primary_key=True),
    Column("local_date", Date, primary_key=True),
    Column("claimed_at", TS, nullable=False, server_default=func.now()),
    Column("done_at", TS),  # the run finished; NULL: running, or left by a process that died (sql.local_job_runs)
)

insights = Table(
    "insights", metadata,
    Column("id", Text, primary_key=True),
    _book_fk(),
    Column("insight_type", Text, nullable=False),
    Column("ai_provider", Text, nullable=False),
    Column("content", Text, nullable=False),
    Column("content_mm", Text),
    Column("is_placeholder", Boolean, nullable=False, server_default=text("false")),
    Column("is_period_to_date", Boolean),
    Column("week_start", Date),
    Column("week_end", Date),
    Column("month_start", Date),
    Column("month_end", Date),
    Column("input_tokens", Integer),
    Column("output_tokens", Integer),
    Column("total_tokens", Integer),
    Column("expires_at", TS),
    Column("generated_at", TS, nullable=False, server_default=func.now()),
    CheckConstraint("insight_type IN ('weekly','monthly')", name="insight_type"),
    CheckConstraint("ai_provider IN ('openai','gemini','claude')", name="ai_provider"),
    CheckConstraint("btrim(content) <> ''", name="content_not_blank"),
)
Index("ix_insights_latest", insights.c.book_id, insights.c.ai_provider, insights.c.insight_type,
      insights.c.generated_at.desc())

# Custom insights (Pro): an AI report on a date range the user picks, optionally with a preset question or free-text
# instruction. A row is created `pending` and moves once to ready / failed / refused. At most one pending row per book.
# counter_keys: the quota counter rows the report reserved, as [feature, period, "YYYY-MM-DD"] lists (given back on failure).
# A deleted failed / refused row is kept hidden (deleted_at set, its text cleared) so it still counts as an attempt.
custom_insights = Table(
    "custom_insights", metadata,
    Column("id", Text, primary_key=True),
    # No single-column book_id index: ix_custom_insights_book_created below leads with book_id.
    _book_fk(index=False),
    Column("start_date", Date, nullable=False),
    Column("end_date", Date, nullable=False),
    Column("preset", Text),
    Column("instruction", Text),
    Column("instruction_key", Text, nullable=False, server_default=""),  # normalised instruction/preset, for reuse matching
    Column("status", Text, nullable=False, server_default="pending"),
    Column("content", Text),
    Column("content_mm", Text),
    Column("figures", JSONB),  # snapshot of the figures the report was written from
    Column("ai_provider", Text),
    Column("ai_model", Text),
    Column("input_tokens", Integer),
    Column("output_tokens", Integer),
    Column("counter_keys", JSONB, nullable=False, server_default=text("'[]'::jsonb")),
    Column("created_at", TS, nullable=False, server_default=func.now()),
    Column("completed_at", TS),
    Column("deleted_at", TS),
    CheckConstraint("status IN ('pending','ready','failed','refused')", name="status"),
    CheckConstraint("end_date >= start_date", name="date_range"),
    CheckConstraint("preset IS NULL OR preset IN ('where_to_save','compare_previous','biggest_changes','budgets_goals')",
                    name="preset"),
    CheckConstraint("instruction IS NULL OR char_length(instruction) <= 300", name="instruction_length"),
    CheckConstraint("preset IS NULL OR instruction IS NULL", name="preset_or_instruction"),
    CheckConstraint("status <> 'ready' OR (content IS NOT NULL AND btrim(content) <> '')", name="ready_has_content"),
    CheckConstraint("deleted_at IS NULL OR status IN ('failed','refused')", name="deleted_only_failed_refused"),
)
Index("ix_custom_insights_book_created", custom_insights.c.book_id, custom_insights.c.created_at.desc())
Index("uq_custom_insights_pending_book", custom_insights.c.book_id, unique=True,
      postgresql_where=custom_insights.c.status == "pending")

chat_sessions = Table(
    "chat_sessions", metadata,
    Column("id", Text, primary_key=True),
    _user_fk(),  # the person: chat history is private per person
    Column("book_id", Text, ForeignKey("books.id", ondelete="CASCADE"), nullable=False),  # the book chatted about
    Column("created_at", TS, nullable=False, server_default=func.now()),
    Column("updated_at", TS, nullable=False, server_default=func.now()),
)
Index("ix_chat_sessions_user_updated", chat_sessions.c.user_id, chat_sessions.c.updated_at.desc())
Index("ix_chat_sessions_updated", chat_sessions.c.updated_at)
Index("ix_chat_sessions_book_id", chat_sessions.c.book_id)  # the CASCADE FK's index

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
    # Who the spend is recorded under: the person (user_id), or a family book's own work (book_id, user_id NULL; it
    # counts toward the owner's cost cap). No CHECK: a deleted family's rows keep their cost with both NULL.
    _user_fk(nullable=True),
    Column("book_id", Text, ForeignKey("books.id", ondelete="SET NULL"), index=True),
    Column("feature_type", Text, nullable=False),
    Column("provider", Text, nullable=False),
    Column("model_name", Text, nullable=False),
    Column("input_tokens", Integer, nullable=False, server_default="0"),
    Column("output_tokens", Integer, nullable=False, server_default="0"),
    Column("total_tokens", Integer, nullable=False, server_default="0"),
    Column("estimated_cost_usd", Numeric(12, 6), nullable=False, server_default="0"),
    CheckConstraint("estimated_cost_usd >= 0 AND estimated_cost_usd < 1e6", name="cost_finite"),
    Column("created_at", TS, nullable=False, server_default=func.now()),
    # The provider that failed before this one answered (a fallback happened); NULL = no fallback.
    Column("fallback_from", Text),
    CheckConstraint("fallback_from IS NULL OR fallback_from IN ('openai','gemini','claude')", name="fallback_from"),
    # Cost detail (migration e5b7c3a9d2f6), kept so a price change can be re-applied exactly. input_tokens is the
    # whole billed input; cached_input_tokens / cache_write_tokens / audio_input_tokens are parts of it.
    Column("served_model", Text),  # the model the provider says answered; NULL: not reported (or an older row)
    Column("cached_input_tokens", Integer, nullable=False, server_default="0"),
    Column("cache_write_tokens", Integer, nullable=False, server_default="0"),
    Column("audio_input_tokens", Integer, nullable=False, server_default="0"),
    Column("audio_seconds", Double),  # speech-to-text audio length, when the provider reports it
    Column("cost_estimated", Boolean, nullable=False, server_default=text("false")),  # tokens/duration estimated
    # used: the answer the user got; rejected: billed but unusable (the next provider was asked); cancelled: a
    # stream that ended early after text started. NULL (older rows) means used.
    Column("outcome", Text),
    CheckConstraint("outcome IS NULL OR outcome IN ('used','rejected','cancelled')", name="outcome"),
)
Index("ix_ai_usage_created", ai_usage.c.created_at)
Index("ix_ai_usage_user_created", ai_usage.c.user_id, ai_usage.c.created_at)
Index("ix_ai_usage_feature_created", ai_usage.c.feature_type, ai_usage.c.created_at)

# Admin-panel AI provider settings (one row per feature that has an override) and per-provider health.
ai_feature_settings = Table(
    "ai_feature_settings", metadata,
    Column("feature", Text, primary_key=True),
    Column("main_provider", Text, nullable=False),
    Column("main_model", Text, nullable=False),
    # NULL = default backups; [] = no backups; else a list of {"provider", "model"}.
    Column("backups", JSONB),
    Column("updated_at", TS, nullable=False, server_default=func.now()),
    Column("updated_by", Text),
)

ai_provider_status = Table(
    "ai_provider_status", metadata,
    Column("provider", Text, primary_key=True),
    Column("last_error", Text),
    Column("last_error_at", TS),
    Column("last_success_at", TS),
)

# Plans and AI quotas. plan_limits / plan_settings hold the owner-editable allowances (seeded by the migration
# with plans.catalog's defaults); usage_counters counts what each user has used in the current week / month.
plan_limits = Table(
    "plan_limits", metadata,
    Column("plan", Text, primary_key=True),
    Column("feature", Text, primary_key=True),
    Column("mode", Text, nullable=False),
    Column("quota", Integer),  # counted only
    Column("period", Text),  # counted only
    CheckConstraint("plan IN ('free','plus','pro')", name="plan"),
    CheckConstraint("mode IN ('locked','included','counted')", name="mode"),
    CheckConstraint("period IS NULL OR period IN ('week','month')", name="period"),
    CheckConstraint("mode <> 'counted' OR (quota IS NOT NULL AND quota >= 0 AND period IS NOT NULL)", name="counted_complete"),
)

plan_settings = Table(
    "plan_settings", metadata,
    Column("plan", Text, primary_key=True),
    Column("cost_cap_usd", Numeric(12, 6), nullable=False),
    # What a paid plan costs, in whole kyat; null: the owner has not set it (the app shows no price).
    Column("price_monthly_mmk", Integer),
    Column("price_yearly_mmk", Integer),  # optional, a discount on 12 months
    # Family limits: account members (owner included) and placeholders. 0: the plan cannot create a family.
    Column("family_max_members", SmallInteger, nullable=False, server_default="0"),
    Column("family_max_placeholders", SmallInteger, nullable=False, server_default="0"),
    CheckConstraint("family_max_members BETWEEN 0 AND 50", name="family_max_members_range"),
    CheckConstraint("family_max_placeholders BETWEEN 0 AND 50", name="family_max_placeholders_range"),
    CheckConstraint("plan IN ('free','plus','pro')", name="plan"),
    CheckConstraint("cost_cap_usd >= 0", name="cost_cap_non_negative"),
    CheckConstraint("price_monthly_mmk IS NULL OR price_monthly_mmk > 0", name="price_monthly_positive"),
    CheckConstraint("price_yearly_mmk IS NULL OR price_yearly_mmk > 0", name="price_yearly_positive"),
    CheckConstraint("plan <> 'free' OR (price_monthly_mmk IS NULL AND price_yearly_mmk IS NULL)", name="free_has_no_price"),
    CheckConstraint("price_yearly_mmk IS NULL OR price_monthly_mmk IS NOT NULL", name="yearly_needs_monthly"),
)

app_settings = Table(
    "app_settings", metadata,
    Column("key", Text, primary_key=True),
    Column("value", Text, nullable=False),
    Column("updated_at", TS, nullable=False, server_default=func.now()),
)

# An admin's replacement for one server text in one language (Texts tab); the code default is used when none.
text_overrides = Table(
    "text_overrides", metadata,
    Column("key", Text, primary_key=True),
    Column("lang", Text, primary_key=True),
    Column("text", Text, nullable=False),
    Column("replaced_default", Text, nullable=False),  # the default this override replaced when it was saved
    Column("version", Integer, nullable=False),
    Column("updated_by", Text),
    Column("updated_at", TS, nullable=False, server_default=func.now()),
)

# A notice the owner shows inside the app to the users of some plans between two instants (App control).
announcements = Table(
    "announcements", metadata,
    Column("id", Text, primary_key=True),
    Column("text_en", Text, nullable=False),
    Column("text_my", Text, nullable=False),
    Column("style", Text, nullable=False),
    Column("link_url", Text),
    Column("link_label_en", Text),
    Column("link_label_my", Text),
    Column("plans", ARRAY(Text), nullable=False),
    Column("starts_at", TS, nullable=False),
    Column("ends_at", TS),  # null: no end
    Column("created_by", Text),
    Column("created_at", TS, nullable=False, server_default=func.now()),
    Column("updated_at", TS, nullable=False, server_default=func.now()),
    CheckConstraint("style IN ('info','warning')", name="style"),
)

usage_counters = Table(
    "usage_counters", metadata,
    Column("user_id", Text, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
    Column("feature", Text, primary_key=True),
    Column("period", Text, primary_key=True),
    Column("period_start", Date, primary_key=True),
    Column("used", Integer, nullable=False, server_default="0"),
    CheckConstraint("period IN ('week','month')", name="period"),
    CheckConstraint("used >= 0", name="used_non_negative"),
)

# Upgrades are manual (no payments): a user asks for Plus or Pro from the app and the owner handles it in the admin
# panel. At most one pending request per user; a request is kept (done / dismissed) as history.
upgrade_requests = Table(
    "upgrade_requests", metadata,
    Column("id", Text, primary_key=True),
    _user_fk(),
    Column("plan", Text, nullable=False),
    Column("note", Text),
    Column("viber_number", Text),  # for the owner to contact the user on Viber; null: use the account email
    Column("billing", Text),  # 'month' / 'year', the price the user picked; null: the plan had no price
    Column("status", Text, nullable=False, server_default="pending"),
    Column("created_at", TS, nullable=False, server_default=func.now()),
    Column("handled_at", TS),
    Column("handled_by", Text),  # admin id (no foreign key: the record outlives a deleted admin)
    CheckConstraint("plan IN ('plus','pro')", name="plan"),
    CheckConstraint("status IN ('pending','done','dismissed')", name="status"),
    CheckConstraint("note IS NULL OR char_length(note) <= 500", name="note_length"),
    CheckConstraint("billing IS NULL OR billing IN ('month','year')", name="billing"),
)
Index("uq_upgrade_requests_pending_user", upgrade_requests.c.user_id, unique=True,
      postgresql_where=upgrade_requests.c.status == "pending")
Index("ix_upgrade_requests_status_created", upgrade_requests.c.status, upgrade_requests.c.created_at.desc())

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
