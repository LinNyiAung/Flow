# MongoDB → PostgreSQL migration plan

Status: **proposal for review** (branch `postgres-migration`). Nothing in the backend has
been changed yet.

## Goals and non-goals

- **Same API.** Every endpoint keeps its path, request and response shape, so the Flutter
  app and the admin panel need **no changes**. The existing end-to-end suites (640 backend
  checks, 43 Flutter tests, admin panel checks) are the acceptance test.
- **Stronger data guarantees** — the reason for switching: column types, `NOT NULL`,
  `CHECK` constraints, exact money, foreign keys with cascades, real transactions, and
  unique constraints that today are only "check then insert".
- **Not in scope:** new features, API changes, UI changes.

## Stack

| Piece | Choice | Why |
| --- | --- | --- |
| Database | PostgreSQL 16 on Render | Same host/region as the backend, private network |
| Driver / ORM | SQLAlchemy 2.0 (async) + asyncpg | Async like Motor today; typed models; mature |
| Schema migrations | Alembic | Versioned, reviewable schema changes from now on |

Configuration: one `DATABASE_URL` env var replaces `MONGODB_URL` + `DATABASE_NAME`.

## Key design decisions (please confirm)

1. **Money is exact: `NUMERIC(18,2)`** for amounts/balances (`NUMERIC(12,6)` for AI cost),
   with `CHECK (amount > 0)` where the API already requires it. Today amounts are floats,
   which is why the code needs NaN/infinity filters everywhere; those filters go away.
   The API still returns plain JSON numbers.
2. **Dates keep today's exact meaning.** Wall-clock dates (transaction date, budget
   start/end, goal target date) stay "local time stored with a UTC label" in
   `timestamptz` columns, so none of the timezone logic that took several rounds to get
   right has to change. Real instants (`created_at` etc.) stay real UTC.
3. **IDs stay as they are** (`TEXT` primary keys holding the current UUID strings, and the
   `"{parent}:{YYYYMMDD}"` ids of auto-created recurring transactions), so links in
   existing data and in the apps keep working.
4. **Balances are computed, not cached.** The `users.balances` cache and its version
   counter existed because Mongo aggregations were slow; an indexed SQL `SUM` is fast at
   this scale and can't go stale. Same numbers returned.
5. **Deleting a user cascades in the database** (`ON DELETE CASCADE` on `user_id`), in one
   transaction, instead of nine separate `delete_many` calls that can half-fail.
6. **Per-user money lock moves into the database** (`SELECT … FOR UPDATE` on the user's
   row). Today's lock lives in server memory, so it only works with a single server process.
7. **Text + `CHECK` instead of Postgres enum types** for statuses/types (e.g.
   `status IN ('active','achieved')`): same safety, much easier to extend later.

## Schema

`users` columns marked † are moved from the user document as-is.

### users
| column | type | notes |
| --- | --- | --- |
| id | text PK | |
| name | text NOT NULL | |
| email | text NOT NULL | unique on `lower(email)` (replaces case-insensitive index) |
| password_hash | text NOT NULL | |
| password_version | int NOT NULL default 0 | |
| password_changed_at | timestamptz | |
| subscription_type | text NOT NULL default 'free' CHECK in ('free','premium') | |
| subscription_expires_at | timestamptz | NULL = lifetime |
| premium_ended_at | timestamptz | |
| has_claimed_free_trial | bool NOT NULL default false | |
| default_currency | text NOT NULL default 'usd' CHECK in ('usd','mmk','thb') | |
| language | text NOT NULL default 'en' CHECK in ('en','my') | |
| is_verified | bool NOT NULL default false | |
| verified_at | timestamptz | |
| verification_token, verification_token_expires_at | text, timestamptz | |
| password_reset_otp_hash, _otp_expiry, _attempts, _attempts_since, _locked_until, _token_hash, _token_expiry | † | reset/OTP state |
| fcm_token | text | unique where not null (one account per device) |
| ai_data_stale | bool NOT NULL default false | |
| created_at | timestamptz NOT NULL | |

### transactions
| column | type | notes |
| --- | --- | --- |
| id | text PK | |
| user_id | text NOT NULL → users ON DELETE CASCADE | |
| type | text NOT NULL CHECK in ('inflow','outflow') | |
| main_category, sub_category | text NOT NULL | names, as today (no FK, keeps legacy data valid) |
| amount | numeric(18,2) NOT NULL CHECK > 0 | |
| currency | text NOT NULL | |
| date | timestamptz NOT NULL | wall-clock, see decision 2 |
| description | text | |
| recurrence_enabled | bool NOT NULL default false | |
| recurrence_frequency | text CHECK in (daily, weekly, monthly, annually) | |
| recurrence_day_of_week / _day_of_month / _month / _day_of_year | smallint | |
| recurrence_end_date, recurrence_last_created_date | timestamptz | |
| parent_transaction_id | text → transactions ON DELETE SET NULL | |
| created_at, updated_at | timestamptz NOT NULL | |

Indexes: `(user_id, date)`, `(user_id, type, date)`, `(user_id, currency)`,
`(parent_transaction_id, date)`, partial `(recurrence_enabled) WHERE recurrence_enabled`.

### goals
`id`, `user_id` → users CASCADE, `name`, `goal_type` CHECK, `status` CHECK,
`target_amount numeric(18,2) CHECK > 0`, `current_amount numeric(18,2) CHECK >= 0`,
`currency`, `target_date`, `achieved_at`, `created_at`, `updated_at`.
Index `(user_id, status, currency)`, `(status, target_date)`.

### budgets + budget_allocations
`budgets`: `id`, `user_id` → CASCADE, `name`, `description`, `period` CHECK, `currency`,
`start_date`, `end_date` (CHECK end ≥ start), `total_budget`, `total_spent`,
`remaining_budget`, `percentage_used`, `status` CHECK, `is_active`,
`auto_create_enabled`, `auto_create_with_ai`, `parent_budget_id` → budgets SET NULL,
`rolled_over_to` → budgets SET NULL, `auto_create_claimed_at`, `started_notified(_at)`,
`ending_soon_notified(_at)`, `created_at`, `updated_at`.
Unique partial `(user_id, parent_budget_id, start_date) WHERE parent_budget_id IS NOT NULL`
(same as today), partial `(end_date) WHERE auto_create_enabled`.

`budget_allocations` (replaces the embedded `category_budgets` array):
`budget_id` → budgets CASCADE, `position`, `category` (`"Main"` or `"Main - Sub"`),
`allocated_amount`, `spent_amount`, `percentage_used`, `is_exceeded`; PK `(budget_id, position)`.

### notifications
`id`, `user_id` → CASCADE, `type`, `title`, `message`, `goal_id`, `goal_name`
(kept: they hold a goal/budget/transaction id depending on `type`, so no FK), `currency`,
`is_read`, `created_at`, `reminder_threshold smallint`, `reminder_target_date date`.
Index `(user_id, created_at DESC)`, `(user_id, is_read)`, `(user_id, type, created_at)`.

### Other tables
| table | shape |
| --- | --- |
| notification_preferences | `user_id` PK → CASCADE, `preferences jsonb` (keeps arbitrary keys, as today), timestamps — the PK fixes today's duplicate-row race |
| insights | `id`, `user_id` → CASCADE, `insight_type`, `ai_provider`, `content` NOT NULL, `content_mm`, `is_placeholder`, `is_period_to_date`, `period_start`, `period_end`, `input/output/total_tokens`, `generated_at`; index `(user_id, ai_provider, insight_type, generated_at DESC)` |
| chat_sessions + chat_messages | session per user; `chat_messages(session_id, id, role, content, created_at)`; the 20-message cap is enforced in the same transaction as the insert |
| ai_usage | `id`, `user_id` → CASCADE, `feature_type`, `provider`, `model_name`, token ints, `estimated_cost_usd numeric(12,6)`, `created_at`; index `(created_at)`, `(user_id, created_at)` |
| admins | `id`, `name`, `email` unique on `lower(email)`, `password_hash`, `role` CHECK, `password_version`, `password_changed_at`, `last_login`, `created_at` |
| admin_action_logs | `id`, `admin_id`, `admin_email`, `action`, `target_user_id`, `target_user_email`, `details`, `timestamp` (no FKs: logs outlive deleted users/admins) |
| feedback | `id`, `user_id` → CASCADE, `user_email`, `user_name`, `category` CHECK, `message`, `rating` CHECK 1–5, `screenshot_url`, `status` NOT NULL default 'pending', `created_at` |
| categories | `type`, `main_category`, `sub_category`, `position`; unique `(type, main_category, sub_category)` |
| app_versions | as today + unique `(version, platform)` (fixes today's check-then-insert) |
| quarantined_transactions | raw JSON of rows rejected by the data checks, with reason (audit only) |

## Code changes

About **300 database calls in 21 files**, including 11 aggregation pipelines. They become
SQL via a small repository layer per area, keeping each route's behaviour identical. Order
(each step leaves the full test suite green):

1. Foundation: models, Alembic baseline, engine/session, test harness on local Postgres.
2. Users & auth (register, login, verification, reset/OTP, admins).
3. Transactions, recurring transactions, balances.
4. Goals.
5. Budgets (+ allocations, rollovers, notifications flags).
6. Notifications & preferences; scheduler jobs; subscription expiry.
7. Insights, chat, AI usage.
8. Admin panel endpoints, app versions, feedback, reports.
9. Remove Motor/pymongo.

## Data migration (one-time)

A rerunnable script copies MongoDB → PostgreSQL:

- Reads every collection, applies the same cleanup rules as `scripts/data_cleanup.py`
  (lowercase emails, legacy defaults, string dates parsed), and writes in dependency order.
- Rows that can't satisfy the constraints (e.g. NaN amounts) go to
  `quarantined_transactions` with the reason, never silently dropped.
- **Verification report**: row counts per table, and per user and currency the inflow /
  outflow totals, goal allocations and budget totals computed in both databases — must
  match exactly.

Rehearsal: run it against a **copy** of production (a `mongodump` restored locally, or a
read-only connection you run yourself), review the report, fix, repeat.

## Cutover (production)

1. Create the Render PostgreSQL database; run Alembic migrations.
2. Final rehearsal on a fresh production copy.
3. Maintenance window (expected minutes): put the backend in read-only/maintenance mode,
   run the migration, check the verification report, deploy the PostgreSQL backend
   (`DATABASE_URL`), smoke-test login / transactions / budgets / AI.
4. **Rollback**: MongoDB is left untouched and read-only for a few weeks; rolling back is
   redeploying the previous version.

## Testing

- Local PostgreSQL (portable binaries) replaces the local `mongod` in the test harness.
- Backend suite (640 checks), Flutter end-to-end suite (43 tests incl. large-text tours)
  and the admin panel checks must all pass unchanged before cutover; plus new tests for
  the constraints (e.g. negative amount rejected by the database, cascade delete, unique
  device token) and the migration script's verification.

## Open questions

1. Confirm decisions 1–7 above.
2. Render PostgreSQL plan/size (a paid plan is needed for production backups).
3. Who runs the production rehearsal: you (with a read-only connection), or by giving me a
   `mongodump` of production to restore locally?
