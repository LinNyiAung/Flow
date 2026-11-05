# MongoDB → PostgreSQL migration plan

Status: **implemented** on branch `postgres-migration`. The backend runs on PostgreSQL only;
MongoDB (Motor/pymongo) is gone. The app had no production users yet, so no data is
carried over (see "Data migration").

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

## Data migration

Not needed: the app was not in production, so there is no user data to carry over. The new
database starts empty; on first start the backend seeds the default categories and the
bootstrap super admin (`ADMIN_BOOTSTRAP_EMAIL` / `ADMIN_BOOTSTRAP_PASSWORD`).

## Deploying on Render

1. Create the Render PostgreSQL database (a paid plan includes backups).
2. On the backend web service:
   - set `DATABASE_URL` to the database's **Internal** URL (`postgres://…` is accepted);
   - set the **Pre-Deploy Command** to `alembic upgrade head` (or
     `cd backend && alembic upgrade head` if the service's Root Directory isn't `backend`),
     so every deploy applies schema changes before the new version starts;
   - remove `MONGODB_URL` and `DATABASE_NAME`.
3. Deploy, then smoke test: register and verify an account, log in, add a transaction,
   contribute to a goal, create a budget, send an AI chat message, open the admin panel.
4. Delete the MongoDB Atlas cluster once you are happy.

### AI providers

The backend can use OpenAI, Gemini or Claude for each AI feature. This release's deploy runs
the Alembic migration, revision `a3f1c7d92b64`
(`backend/alembic/versions/20261029_a3f1c7d92b64_ai_provider_switching.py`; via the Pre-Deploy
Command above), which adds the tables `ai_feature_settings` and `ai_provider_status`.

- API keys: `OPENAI_API_KEY`, `GOOGLE_API_KEY` (Gemini) and the new `ANTHROPIC_API_KEY`
  (Claude). A provider without a key is skipped.
- Default models: `OPENAI_MODEL`, `GEMINI_MODEL` and the new `CLAUDE_MODEL` (default
  `claude-sonnet-5-5`) set the built-in model for chat and the weekly/monthly insights, and the
  model used when a provider is named without one; the other built-in models are fixed
  (photo `gpt-4o`, voice `whisper-1`, insight translation `gemini-2.5-pro`, budgets and text
  `gpt-4o-mini`).
- Per feature (optional): `AI_<FEATURE>_PROVIDER` (`openai`, `gemini` or `claude`),
  `AI_<FEATURE>_MODEL` and `AI_<FEATURE>_BACKUPS`. `_BACKUPS` is a comma-separated list of
  `provider[:model]`, or `none` for no backups; left unset, every other configured provider
  is a backup. `_MODEL` and `_BACKUPS` are ignored unless `_PROVIDER` is set.
  `<FEATURE>` is one of `CHAT`, `INSIGHT_WEEKLY`, `INSIGHT_MONTHLY`, `INSIGHT_TRANSLATION`,
  `BUDGET_SUGGESTION`, `BUDGET_AUTO_CREATE`, `TRANSACTION_TEXT`, `TRANSACTION_IMAGE`,
  `TRANSACTION_AUDIO`. Example: `AI_CHAT_PROVIDER=claude`, `AI_CHAT_BACKUPS=gemini,openai`.
- `TRANSACTION_AUDIO` (voice input) cannot use Claude, because Claude has no audio input.
  An invalid or disallowed environment setting is ignored with a log warning and the default
  applies (for example `AI_TRANSACTION_AUDIO_PROVIDER=claude` is ignored).
- Order of precedence: the admin panel's **AI Providers** page, then these environment
  variables, then the built-in default (chat and insights on Gemini, budgets and transaction
  text/photo/voice on OpenAI). Panel changes apply right away (within about a minute across
  instances); changing an environment variable needs a restart (Render redeploys on save).
- OpenAI speech-to-text models (`whisper*`, `*transcribe*`) can only be used for voice input, and
  voice input on OpenAI needs one of them; the panel offers only the models each feature can use
  and refuses others. A model the provider rejects at run time (for example a model name typed
  under "Other…" that the endpoint does not support) falls back to the backups and shows on the
  provider's status card.

After the deploy, check by hand (needs the real keys, so the automated suites cannot):

- On the **AI Providers** page, press **Test** for each provider; each should succeed.
- Get one chat answer from each provider: switch chat to that provider on the panel, send a
  message from the app, then press **Use server setting**.
- Run one Claude JSON feature, such as a budget suggestion or a transaction from text, with
  Claude as its main provider.
- Send one voice note with Gemini as the voice input provider.
- If you pick Claude Haiku for any feature, run one JSON feature on it (for example a budget
  suggestion), because the client always sends `output_config.effort` with Claude requests.
- When a key is out of credit, confirm the provider's status card shows a billing error.

Notes:

- The **AI Usage & Costs** page counts only the provider that answered. Tokens spent on attempts that
  failed before a fallback (for example a cut-off or unusable answer) are not shown, so the page
  can undercount spend when fallbacks happen.
- Rolling back: after `alembic downgrade` to the previous revision, `ai_usage` rows with provider
  `claude` stay in the table, and the previous version's per-user usage detail may reject them
  (it does not know `claude`). Delete or remap those rows if the old version must show them.

### Plans and quotas

Free, Plus and Pro replace the old Free and Premium. Free users get a small AI allowance instead
of none, and the one-time 30-day trial now gives Plus. Upgrades stay manual (there is no payment
integration): the user contacts the owner, and the owner sets the plan and its end date in the
admin panel. This release's deploy runs two Alembic migrations, both applied by the usual
`alembic upgrade head` in the Pre-Deploy Command above, in this order:

- `c4e8b1a05d37` (`backend/alembic/versions/20261102_c4e8b1a05d37_plans_and_quotas.py`) adds
  the tables `plan_limits`, `plan_settings`, `app_settings` and `usage_counters`, seeded with
  the default limits below, and the columns `users.trial_ends_at` and `users.usage_reset_at`.
  It changes `users.subscription_type` to allow `free`, `plus` and `pro`, and **maps every
  existing `premium` user to `plus`**, keeping their end date. Users migrated this way are not
  marked as trials, so they get no trial reminders.
- `e1b6d3a8f245` (`backend/alembic/versions/20261102_e1b6d3a8f245_trial_reminders.py`) adds
  `users.trial_reminder_3d_at` and `users.trial_reminder_last_at`, so the hourly job sends each
  trial reminder (3 days before the trial ends, and on its last day) at most once.

Only `plan_limits` and `plan_settings` are seeded (the default limits and cost caps below).
`app_settings` (the upgrade contact message) and `usage_counters` start empty, so the contact
message is blank until the owner sets it on the Plans page.

No new environment variables. The default limits (all editable afterwards, see below):

| Feature | Free | Plus | Pro |
|---|---|---|---|
| AI chat messages | 5 per week | 100 per month | 400 per month, up to 100 of them Advanced |
| Monthly insight | 1 per month | included | included |
| Weekly insights, insight translation, Reports | locked | included | included |
| Receipt photo / text / voice entries (one shared count) | 10 per month | 150 per month | 500 per month |
| AI budget suggestion | 1 per month | 5 per month | 20 per month |
| Hidden monthly AI cost cap per user | $0.10 | $1.00 | $3.00 |

Weeks start on Monday and months on the 1st, both at 00:00 in the app timezone
(`SCHEDULER_TIMEZONE`, default Asia/Yangon). A failed AI request, or an unusable answer, does
not use up an allowance.

Where the owner changes things in the admin panel:

- **Plans** page: each feature's limit per plan (locked, included, or counted with a number per
  week or month, plus Pro's Advanced chat count), each plan's monthly cost cap, and the upgrade
  contact message in English and Myanmar (shown on the app's Upgrade screen). Admins and super
  admins can edit; moderators see it read-only. Saves apply right away (within about a minute
  across instances).
- **Users**, in a user's detail panel: set the plan (Free, Plus or Pro) and its end date, see
  this period's usage per feature, this month's AI spend and a "Cost cap reached" flag. Behind it
  are `GET /api/admin/users/{id}/usage` and `POST /api/admin/users/{id}/reset-usage`.
- **Reset usage** (button in the same panel, written to the admin action log) clears this
  week's and this month's counters for that user and gives them a fresh cost cap from that
  moment: spend towards the cap is measured from the later of the 1st of the month and the reset
  time. It deletes no `ai_usage` rows. There are no per-user custom limits; Reset usage is how
  to give someone more.
- **AI Providers** page: the Advanced chat model for Pro is chosen for the **Advanced chat**
  feature (stored as `chat_advanced`). Its built-in default is Claude (`claude-sonnet-5-5`), so
  `ANTHROPIC_API_KEY` must be set, or another provider chosen, for Advanced to work. A Pro user
  whose Advanced allowance is used up gets Standard answers, and a non-Pro user is never answered
  as Advanced.
- **Free never gets translated insights.** The Free column of insight translation is always
  locked: the Plans page greys that cell out and the server refuses to save it any other way.
- **Scheduled insights follow the plan's locks.** The weekly and monthly insight jobs still
  serve Plus and Pro users only, and now also skip a user whose plan has that insight type set to
  locked on the Plans page (as well as users at their cost cap or whose plan has ended).

After the deploy, check by hand (needs the real keys and the app, so the automated suites
cannot):

- Set the upgrade contact message (English and Myanmar) on the **Plans** page, and check it
  shows on the app's Upgrade screen.
- Confirm an existing former-Premium user now shows **Plus** (user list and detail panel) with
  the same end date.
- On **AI Providers**, press **Test** on the card of the provider chosen for the **Advanced
  chat** feature (Claude by default). Test is a button on each provider's card and checks only
  that provider's key and its default chat model (`CLAUDE_MODEL`, default `claude-sonnet-5-5`
  for Claude), not the model chosen for a feature. Confirm the chosen model itself by sending one
  Advanced message in the Pro step below.
- Claim the trial on a test account: it should become Plus with a 30-day end date.
- Use a Free test account up to its chat limit: the next message should show the limit sheet
  with the reset date and an Upgrade button, not an error.
- Switch a test account to Pro and send one Advanced chat message; check the Advanced count
  rises by one on the user's detail panel, then press **Reset usage** and confirm the counts clear
  (admins and super admins only; moderators see a user's usage read-only).

Notes:

- Rolling back: `alembic downgrade` of `c4e8b1a05d37` turns every Plus and Pro user into
  `premium` (keeping their end date) and drops the plan tables, so the Plus/Pro distinction and
  the usage counts are lost; `e1b6d3a8f245` must be downgraded first, and `alembic downgrade
  a3f1c7d92b64` does both.
- The cost cap counts every AI spend recorded for the user this month, including scheduled
  jobs, so it is only as accurate as the **AI Usage & Costs** page (see the note above about
  fallbacks).

### Custom insights

Pro users can ask for an insight over a date range of their choice (7 days to 12 months, ending
today or earlier), with an optional question or one of four ready-made instructions. The report
is generated in the background, saved with its figures, and the user gets a
`custom_insight_ready` notification (or `custom_insight_failed`). Free and Plus see the tab
locked with an Upgrade button. No new environment variables.

- Migration `b8f4d2c6e9a1`
  (`backend/alembic/versions/20261104_b8f4d2c6e9a1_custom_insights.py`) is applied by the usual
  `alembic upgrade head` in the Pre-Deploy Command. It adds the `custom_insights` table and
  seeds the `insight_custom` plan limits: Free and Plus **locked**, Pro **10 per month**
  (editable on the admin **Plans** page like any other limit).
- The AI feature **Custom insight** (`insight_custom`) on the **AI Providers** page defaults to
  Claude `claude-sonnet-5-5`, so `ANTHROPIC_API_KEY` must be set, or another provider chosen,
  for it to work. The usage type `custom_insight` shows in **AI Usage & Costs**.
- A sweeper runs every 5 minutes: a report still pending 20 minutes after it was created is
  marked failed, the user is notified once and the use is given back.
- Failed and refused attempts do not use up the allowance, but they are limited to 5 a day per
  user. Deleting such a report does not clear its attempt.
- The app works out "today" for the range picker in the server's default `SCHEDULER_TIMEZONE`
  (Asia/Yangon, UTC+06:30). Changing `SCHEDULER_TIMEZONE` needs an app change (the app would
  have to be sent the server's date); do not change it without one.
- A report's status change and the give-back of a failed or refused report are written in one
  database transaction, so a server shut down while a report is being finished cannot leave a
  failed report counted against the allowance. At worst the user misses the ready / not-created
  notification; the report itself is correct in the app's list.
- The model call for a report gives up after 18 minutes (2 minutes before the sweeper), and the
  report fails and is given back like any other AI failure.
- **Deploy order:** deploy the backend (with this migration) before releasing the app build that
  has the Custom tab. On an older backend a Pro user on the new app sees "New custom insight" and
  gets errors, because the endpoints do not exist yet.
- **Rolling back the backend** while the new app is in users' hands has the same effect: Pro
  users see the Custom tab but every request fails. Roll the app back too (or pull the release),
  or accept that until the backend is deployed again.
- **Reset usage** on the user's detail panel is not a targeted fix for custom insights: it clears
  this week's and this month's counters for **every** feature (chat, scans, insights, custom
  insights, ...) and restarts the cost-cap window for that user.
- All new Myanmar wording (app and notifications) was written without a native speaker and needs
  checking before release.

After the deploy, check by hand (needs the real keys and the app):

- On a Pro test account, create a report (for example Last 30 days with "Where can I save?"),
  wait for the ready notification, tap it to open the report, and check the usage line drops by
  one and the call shows on **AI Usage & Costs** with the feature filter set to **Custom
  Insights** (the `custom_insight` type).
- Translate that report to Myanmar and check the Myanmar text is stored and shown again without
  another translation.
- On a Free or Plus test account, check the Custom tab is locked and Upgrade opens the Upgrade
  screen.
- Delete the report on the Pro account and check it leaves the list.

Rolling back: `alembic downgrade a7d3e5c91f20` drops the `custom_insights` table and the
`insight_custom` limits. `ai_usage` rows of type `custom_insight` stay, and older code cannot
read them on the per-user usage detail (the same caveat as the `claude` rows above).

### Plan prices

The owner sets what Plus and Pro cost, in kyat, on the admin **Plans** page: a monthly price and
an optional yearly price (the app shows "save X%" against 12 monthly payments). Until a price is
set nothing about prices shows anywhere and upgrade requests work as before. Once a plan has a
price, the app's upgrade dialog asks **monthly or yearly**, and the choice shows on the admin
**Upgrade requests** page. Upgrades stay manual. No new environment variables.

- Migration `d6b2e8f4a1c7`
  (`backend/alembic/versions/20261105_d6b2e8f4a1c7_plan_prices.py`) adds
  `plan_settings.price_monthly_mmk` / `price_yearly_mmk` (null: not set; Free never has one; a
  yearly price needs a monthly price) and `upgrade_requests.billing` (`month` / `year`, null when
  no price was shown). It seeds nothing.
- An admin panel without the price fields (an older build still open in a browser) saves the
  rest of the Plans page and leaves the prices alone.
- The new Myanmar wording in the app was written without a native speaker and needs checking
  before release.

Rolling back: `alembic downgrade b8f4d2c6e9a1` drops the prices and the billing choices.

Later schema changes: edit `backend/sql/tables.py`, then
`alembic revision --autogenerate -m "<what changed>"`, review the generated file, commit.

## Testing

- Local PostgreSQL (portable binaries) replaced the local `mongod` in the test harness.
- Result on the branch: backend suite 655/655 (incl. new checks for the database
  constraints, cascade delete and the cross-process money lock), Flutter end-to-end suite
  43/43 (incl. large-text tours), admin panel checked screen by screen.
