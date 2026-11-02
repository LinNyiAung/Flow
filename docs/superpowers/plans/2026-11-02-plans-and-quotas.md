# Plans and AI Quotas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Free/Premium with Free, Plus and Pro. Each plan gets per-feature AI allowances (counts per week or month) that the owner edits in the admin panel. Pro gets an Advanced chat mode, every plan has a hidden per-user monthly cost cap, and the trial becomes Plus.

**Architecture:**
- A new backend package `backend/plans/` holds:
  - the plan catalogue and defaults;
  - the DB-backed limits store, cached and refreshed every 60 s like `ai_providers/settings.py`;
  - period maths in the app timezone;
  - a quota engine with atomic reserve → commit/release on counters, plus the cost-cap check against `ai_usage`.
- Every AI route reserves a use before calling the AI runner and commits only on a usable answer.
- The app reads one endpoint, `GET /api/plan`, for its counters and the Upgrade screen. It recognises limit responses by a stable error code.
- The admin panel gets a Plans page. The user page gets plan, usage and reset controls.

**Tech Stack:** FastAPI, SQLAlchemy Core async, Alembic, PostgreSQL 16; React/Vite admin; Flutter (mobile + web); print-only e2e suites in `e2e/` against the stubbed server.

**Spec:** `docs/superpowers/specs/2026-11-02-plans-and-quotas-design.md`

## Global Constraints

- **Plans** are exactly `free`, `plus` and `pro`. `premium` is no longer a valid `users.subscription_type`; the migration maps it to `plus` and keeps `subscription_expires_at`.
- **Quota feature keys** are exactly `chat`, `chat_advanced`, `insight_monthly`, `insight_weekly`, `insight_translation`, `entry`, `budget_suggestion` and `reports`.
- **Limit modes** are exactly `locked`, `included` and `counted`. A `counted` limit has `quota: int >= 0` and `period: "week" | "month"`.
- **Defaults**, seeded by the migration:
  - free: chat counted 5/week; chat_advanced locked; insight_monthly counted 1/month; insight_weekly locked; insight_translation locked; entry counted 10/month; budget_suggestion counted 1/month; reports locked; cost cap 0.10.
  - plus: chat counted 100/month; chat_advanced locked; insight_monthly, insight_weekly and insight_translation included; entry counted 150/month; budget_suggestion counted 5/month; reports included; cost cap 1.00.
  - pro: chat counted 400/month; chat_advanced counted 100/month; insight_monthly, insight_weekly and insight_translation included; entry counted 500/month; budget_suggestion counted 20/month; reports included; cost cap 3.00.
- **Periods:**
  - Weeks start Monday 00:00 and months start on the 1st at 00:00, both in `tz_utils.get_app_timezone()`.
  - `resets_at` is the next period start, given as a UTC ISO datetime.
- **What counts:**
  - A failed AI request never uses an allowance: an exception, `AllProvidersFailed`, or the runner's unusable answer.
  - An extraction that validly finds zero transactions still counts.
  - Scheduled jobs never count, but their spend counts toward the cost cap.
- **Limit responses** use HTTP 403 for `plan_feature_locked` and HTTP 429 for `plan_limit_reached` and `plan_cost_cap`. The body is `{"detail": {"code", "feature", "resets_at", "upgrade_available", "message"}}`. `message` is in the user's language (English or Myanmar) via `notification_service.translate`. The app never parses `message` to decide behaviour.
- **Roles:** moderators view the Plans page and user usage; only admins and super admins change plans, limits and usage, or reset usage. Every change is written to admin action logs.
- **Language:** every new user-facing string (app, notifications, limit messages) exists in English and Myanmar.
- **Users never see costs or cap amounts.**
- **Security:** never read or print `backend/.env` or any `.env*` file. Test only against the local throwaway Postgres (port 54329) and the stubbed server on :8765. Never push.
- **Suite health:** after every task the full backend suite (`run_suite.ps1`) reports `problems (0)` and `crashes (0)`. A task that breaks an existing suite's premium-based setup updates that suite in the same task. Tests are changed, never weakened.

## Review Focus

1. **Two requests at once on the last allowance**, for example a double-tap on send. Exactly one passes. (Task 3, `concurrent_last_use`.)
2. **A plan change mid-period.** A Free user with 5 chats this week who becomes Plus has 95 of 100 left this month, not 100. A Plus user who drops to Free mid-month is measured against this week's uses. (Task 3, `plan_change_mid_period`.)
3. **The AI fails after a reservation, or the client disconnects mid-stream.** A failure before the first chunk releases the use; a disconnect after the first chunk keeps it. (Task 5, `chat_fail_releases` / `chat_disconnect_counts`.)
4. **An expired Plus or Pro user calling a counted feature before the hourly expiry job has run** is treated as Free immediately. (Task 4, `expired_plus_is_free_now`.)
5. **The owner lowers a limit below what a user already used**, for example a Free chat quota from 5 to 3 after 4 uses. The user is at the limit with remaining 0, never negative, and the app shows "0 left". (Task 3, `limit_lowered_below_used`.)

---

### Task 1: Schema, plan catalogue and migration

**Files:**
- Create: `backend/plans/__init__.py`, `backend/plans/catalog.py`
- Create: `backend/alembic/versions/20261102_<rev>_plans_and_quotas.py`
- Modify: `backend/sql/tables.py`
- Modify: `backend/models.py` (`SubscriptionType` becomes FREE/PLUS/PRO)
- Modify: every backend reference to `"premium"` that compares plan values, as the minimum to keep behaviour: Premium checks become "plus or pro" and active-premium filters become active-paid. Task 4 does the full subscription rework, so here only rename and keep things working.
- Test: `e2e/test_plans.py` (new, print-only), registered in `e2e/run_backend_suite.py` `SUITES` and `PRINT_ONLY`. Also update the existing suites' premium setup (`test_premium_expiry`, `test_api`, `test_ai_providers`, `seed_rich`, `test_jobs*`, `test_sweep`, `test_backend_r4`, `test_load`, `test_regressions_all`, `test_app_download`, `pgcompat`) to `plus`.

**Interfaces:**
- Produces in `plans/catalog.py`:
  - `PLANS = ("free", "plus", "pro")`
  - `PAID_PLANS = ("plus", "pro")`
  - `FEATURES = ("chat", "chat_advanced", "insight_monthly", "insight_weekly", "insight_translation", "entry", "budget_suggestion", "reports")`
  - `@dataclass(frozen=True) class Limit: mode: str; quota: int | None = None; period: str | None = None`
  - `DEFAULT_LIMITS: dict[str, dict[str, Limit]]`
  - `DEFAULT_COST_CAPS: dict[str, float]`
- Produces these tables:
  - `plan_limits(plan text, feature text, mode text, quota int null, period text null, PK(plan, feature))`, with CHECKs on the mode, period and plan values;
  - `plan_settings(plan text PK, cost_cap_usd numeric not null)`;
  - `app_settings(key text PK, value text not null, updated_at timestamptz)`;
  - `usage_counters(user_id text FK users ON DELETE CASCADE, feature text, period text, period_start date, used int not null default 0, PK(user_id, feature, period, period_start))`.
- Produces new `users` columns: `trial_ends_at timestamptz null` and `usage_reset_at timestamptz null`.
- The `users.subscription_type` CHECK becomes `IN ('free','plus','pro')`.

- [ ] **Step 1: Write the failing checks** in `e2e/test_plans.py`:
  - `schema_has_plan_tables`: the four tables exist.
  - `defaults_seeded`: `plan_limits` rows equal `DEFAULT_LIMITS` for all 24 (plan, feature) pairs, and `plan_settings` caps equal 0.10, 1.00 and 3.00.
  - `premium_migrated_to_plus`: insert a user with `premium` and an expiry at the pre-migration revision, upgrade, and the user is `plus` with the same expiry. Use the Alembic up/down approach the AI-provider migration checks used.
  - `downgrade_maps_back`: downgrade maps `plus` and `pro` back to `premium`, and upgrade is clean again.
- [ ] **Step 2: Run them and confirm they FAIL.**
- [ ] **Step 3: Implement** the catalogue, the tables, and the migration with seed and `premium`→`plus`. The downgrade maps plus and pro to premium and drops the new tables and columns. Update `SubscriptionType` and the backend `premium` comparisons. Update the existing suites' setup to `plus`.
- [ ] **Step 4: Run `test_plans.py`, then the full suite.** Expect all PASS, and `problems (0)` and `crashes (0)`.
- [ ] **Step 5: Commit** `feat(plans): Free/Plus/Pro schema, defaults and premium migration`.

### Task 2: Limits store, periods and admin Plans API

**Files:**
- Create: `backend/plans/store.py`, `backend/plans/periods.py`, `backend/sql/plans.py`, `backend/plans_admin_routes.py`
- Modify: `backend/main.py` (router, startup `load` and refresh loop, the same pattern as `ai_providers.settings`)
- Test: `e2e/test_plans.py`

**Interfaces:**
- `periods.period_start(period: str, now: datetime) -> date`, computed in the app timezone.
- `periods.resets_at(period: str, now: datetime) -> datetime`, in UTC.
- `periods.month_start_utc(now) -> datetime`
- `store.limits(plan: str) -> dict[str, Limit]`
- `store.cost_cap(plan: str) -> float`
- `store.upgrade_contact() -> {"en": str, "my": str}`
- `async store.load()`, `store.start_refresh_loop()`
- `async store.save(plan_rows: dict, caps: dict, contact: dict, admin_id: str)`, which validates and raises `ValueError` with a clear message.
- **HTTP endpoints:**
  - `GET /api/admin/plans` (moderator+) returns `{"plans": {plan: {"limits": {feature: {mode, quota, period}}, "cost_cap_usd": float}}, "upgrade_contact": {"en", "my"}}`.
  - `PUT /api/admin/plans` (admin+) takes the same body and returns 422 with the message on invalid input.
  - Changes apply in this process immediately and in others within 60 s.
- **Validation rules:**
  - Every plan × feature is present.
  - `counted` needs `quota >= 0` and a valid period; `locked` and `included` need both to be null.
  - `chat_advanced` may be non-locked only when `chat` is not locked.
  - Cost cap is `>= 0`.
  - Each contact text is ≤ 500 characters.

- [ ] **Step 1: Write the failing checks:**
  - `period_week_starts_monday_yangon`: for 2026-11-02 23:30 UTC (2026-11-03 06:00 Yangon), the week start is 2026-11-02 and `resets_at` is 2026-11-08T17:30:00Z.
  - `period_month_boundary`: for 2026-11-30 18:00 UTC (Yangon 00:30 on Dec 1), the month start is 2026-12-01.
  - `admin_plans_get_defaults`
  - `admin_plans_put_applies`: set free chat to 20/month, then GET reflects it and `store.limits("free")["chat"]` matches over HTTP via `/api/plan` in Task 3. Here, check it via GET.
  - `admin_plans_put_invalid_422`: a counted entry with no period gives 422.
  - `admin_plans_moderator_read_only`: GET returns 200 and PUT returns 403.
  - `admin_plans_logged`: the PUT appears in admin action logs.
  - The suite restores the defaults at its start and end.
- [ ] **Step 2: Run them and confirm they FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them and confirm they PASS.** Run the full suite and expect 0 problems.
- [ ] **Step 5: Commit** `feat(plans): limits store, periods and admin Plans API`.

### Task 3: Quota engine, cost cap and `GET /api/plan`

**Files:**
- Create: `backend/plans/quota.py`, `backend/plans/access.py`, `backend/plans_routes.py`
- Modify: `backend/sql/plans.py` (counter ops), `backend/sql/ai_usage.py` (`user_cost_since`)
- Modify: `backend/main.py` (router and exception handler)
- Test: `e2e/test_plans.py`

**Interfaces:**
- `access.effective_plan(user: dict, now: datetime | None = None) -> str`. It returns `free` when the plan is plus or pro with an end date in the past.
- `access.is_trial(user, now) -> bool`. True when `trial_ends_at` is set and in the future.
- `class PlanError(Exception)`, with `status`, `code`, `feature`, `resets_at`, `upgrade_available` and `lang`. An app-level exception handler renders it in the Global Constraints shape.
- `async quota.reserve(user: dict, feature: str, *, also: tuple[str, ...] = ()) -> Reservation`. It raises `PlanError`.
  - **Order of checks:**
    1. Locked → 403 `plan_feature_locked`.
    2. Cost cap reached → 429 `plan_cost_cap`. The cap counts spend since `max(month_start_utc, users.usage_reset_at)`, from `ai_usage` cost.
    3. Counted with no allowance left → 429 `plan_limit_reached`.
  - **The reservation itself** happens in one DB transaction and increments both the week and the month counter rows for each reserved feature. The plan's period row is incremented only `WHERE used < quota` via `INSERT … ON CONFLICT DO UPDATE … WHERE … RETURNING`. If any conditional increment fails, roll back and raise. The other-period row is incremented unconditionally.
  - **`also`** reserves extra features atomically together, for example `chat` + `chat_advanced`.
  - **Included features** reserve nothing but still pass the cost-cap check.
  - **`upgrade_available`** is true when some higher plan has the feature unlocked with a larger quota, or included.
- `Reservation.commit()` and `async Reservation.release()` (decrements the same rows, idempotent).
- `async with quota.use(user, feature, also=()) as r:`. It releases on exception unless already committed, and commits on clean exit.
- `async quota.status(user) -> dict`: the body of `GET /api/plan`.
- `GET /api/plan` (any signed-in user) returns:
  ```
  {"plan", "expires_at", "is_trial", "trial_ends_at",
   "features": {feature: {"mode", "limit", "period", "used", "remaining", "resets_at"}},
   "catalog": {plan: {feature: {"mode", "quota", "period"}}},
   "upgrade_contact": {"en", "my"}}
  ```
  - `used` comes from this period's counter of the plan's period type.
  - `remaining = max(0, limit - used)`.
  - Locked and included features have null counts.
- `async quota.reset_usage(user_id: str, admin_id: str)` deletes this week's and this month's counter rows and sets `usage_reset_at = now`. Task 4 calls it from the admin endpoint.
- `async quota.over_cost_cap(user: dict) -> bool`, for the scheduled jobs.

- [ ] **Step 1: Write the failing checks.** Exercise the engine in-process inside one `asyncio.run(main())`; the endpoint checks go over HTTP.
  - `reserve_counts_until_limit`: a Free user gets 5 chat commits, then the sixth reserve raises 429 `plan_limit_reached` with `resets_at` = next Monday.
  - `release_returns_use`: reserve then release leaves `used` at 0.
  - `concurrent_last_use`: with 4 used, 5 concurrent reserves give exactly 1 success.
  - `plan_change_mid_period`: a Free user with 5 chats this week, set to Plus, has `remaining` 95 in `/api/plan`. Dropped back to Free in the same week, they are at the limit.
  - `limit_lowered_below_used`: 4 used, quota lowered to 3 via the admin API, so `remaining` is 0 and reserve gives 429.
  - `locked_is_403`: Free `insight_weekly` gives 403 `plan_feature_locked` with `upgrade_available` true.
  - `cost_cap_blocks`: insert `ai_usage` cost 0.11 for a Free user this month, so reserve gives 429 `plan_cost_cap`.
  - `reset_restores_cap`: `reset_usage`, then reserve succeeds, and the `ai_usage` rows are still present.
  - `plan_status_shape`: `/api/plan` has all 8 features, a catalog for 3 plans and the contact.
  - `limit_message_language`: with the user's language set to `my`, `message` is the Myanmar text.
- [ ] **Step 2: Run them and confirm they FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them and confirm they PASS.** Run the full suite and expect 0 problems.
- [ ] **Step 5: Commit** `feat(plans): quota engine, cost cap and plan status endpoint`.

### Task 4: Subscriptions, trial and admin user controls

**Files:**
- Modify: `backend/utils.py`. Replace `require_premium` with `require_paid`, a dependency that raises a `PlanError`-style 403 when `effective_plan` is free. Keep the name `require_premium` nowhere.
- Modify: `backend/subscription_service.py`:
  - generalise expiry to plus and pro, with "plan has ended" wording;
  - add `send_trial_reminders(now)`.
- Modify: `backend/scheduler.py`. Run the trial-reminder job hourly and send each reminder at most once, tracked with new columns or a notifications check; the implementer chooses.
- Modify: `backend/auth_routes.py`:
  - `claim-free-trial` sets `plus`, `subscription_expires_at = now + 30 days` and `trial_ends_at` to the same value;
  - `subscription-status` returns `{subscription_type, plan, is_paid, is_trial, expires_at, is_expired}`.
- Modify: `backend/admin_routes.py`, `backend/admin_models.py`, `backend/sql/users.py`:
  - the subscription update accepts free, plus and pro and always clears `trial_ends_at`;
  - dashboard counts per plan;
  - broadcast targets are `all | free | plus | pro | paid`;
  - `GET /api/admin/users/{id}/usage` (moderator+) returns `{plan, features: {feature: {used, limit, period}}, month_spend_usd, cost_cap_usd, cost_cap_reached}`;
  - `POST /api/admin/users/{id}/reset-usage` (admin+) calls `quota.reset_usage` and is logged.
- Modify: `backend/notification_service.py`. Add the EN/MY strings `trial_ending_soon_*` and `trial_ends_today_*`, and the reworded `subscription_expired_*` naming the plan.
- Test: `e2e/test_plans.py`, and update `e2e/test_premium_expiry.py` (it may be renamed to `test_plan_expiry.py`; update the suite list if so).

- [ ] **Step 1: Write the failing checks:**
  - `trial_sets_plus_and_marker`
  - `admin_set_plan_clears_trial`
  - `expired_plus_is_free_now`: a Plus user with an end date 1 minute ago gets 403 `plan_feature_locked` for weekly insights, before any expiry job runs.
  - `expiry_job_downgrades_plus_and_pro`
  - `trial_reminder_3_days`: a trial ending in 2.5 days gets one reminder, and a second run sends no second one.
  - `trial_reminder_last_day`
  - `no_reminder_for_admin_granted`
  - `admin_usage_view`
  - `admin_reset_usage_logged`
  - `moderator_cannot_reset`
  - `broadcast_targets_paid`
  - `dashboard_counts_per_plan`
- [ ] **Step 2: Run them and confirm they FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them and confirm they PASS.** Run the full suite and expect 0 problems.
- [ ] **Step 5: Commit** `feat(plans): plan expiry, Plus trial with reminders, admin usage controls`.

### Task 5: Chat quotas and Advanced chat

**Files:**
- Modify: `backend/ai_providers/features.py`. Add the feature `chat_advanced` ("Advanced chat"), allowed for all three providers. Its built-in default is `claude` / `claude-sonnet-5-5`; backups follow the same default rule as other features.
- Modify: `backend/chat_models.py`. `ChatRequest.mode: Literal["standard", "advanced"] = "standard"`.
- Modify: `backend/main.py` (`/api/chat/stream`, `/api/chat`) and `backend/ai_chatbot.py`:
  - **Standard** reserves `chat`.
  - **Advanced from a Pro user**: reserve `chat` with `also=("chat_advanced",)` and run the `chat_advanced` feature chain.
  - **Advanced with no Advanced allowance left**: answer as Standard (reserve `chat` only) and report `advanced_exhausted: true`.
  - **Advanced from a non-Pro user**: answer as Standard. The server never answers Advanced to a non-Pro user.
  - **Committing**: commit after the first chunk is sent. Release if the runner fails before the first chunk.
  - **The stream tells the app** the mode actually used and whether Advanced was exhausted. Use the stream's existing metadata or event mechanism (read the current format first) and add `{"mode_used": "standard"|"advanced", "advanced_exhausted": bool}` once at the start.
- Modify: `admin/src/AISettings.jsx` only if the new feature row doesn't appear automatically from the API.
- Test: `e2e/test_plans.py`, `e2e/test_ai_providers.py` (feature count and the new row).

- [ ] **Step 1: Write the failing checks:**
  - `chat_counts_and_limits`: a Free user gets 5 streamed chats, and the sixth gets 429 `plan_limit_reached`.
  - `chat_fail_releases`: with `set_fake_ai` failing every provider, the chat fails and `used` is unchanged.
  - `chat_disconnect_counts`: the client closes after the first chunk, and `used` goes up by 1.
  - `advanced_uses_advanced_chain`: Pro with Advanced has the fake outbox's provider equal to the `chat_advanced` main, `mode_used` advanced, and both counters +1.
  - `advanced_exhausted_falls_back`: Pro with `chat_advanced` used 100/100 gets a Standard answer with `advanced_exhausted` true, and only `chat` +1.
  - `advanced_from_plus_is_standard`
  - `advanced_backup_counts_advanced`: the `chat_advanced` main is billing-failing and the backup answers, so it counts as Advanced.
- [ ] **Step 2: Run them and confirm they FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them and confirm they PASS.** Run the full suite and expect 0 problems.
- [ ] **Step 5: Commit** `feat(plans): chat quotas and Pro Advanced chat`.

### Task 6: Entry, budget and report gates

**Files:**
- Modify: `backend/transaction_routes.py`:
  - `extract-from-text`, `extract-multiple-from-text` and `extract-from-image` each reserve `entry` via `quota.use`.
  - `transcribe-audio` reserves `entry` and commits only for a non-empty transcript. It returns `voice_token`: an HMAC over `user_id|sha256(transcript)|expiry`, signed with the app's existing JWT secret and valid for 15 minutes.
  - `extract-multiple-from-text` and `extract-from-text` accept an optional `voice_token`. A valid token whose transcript hash matches the request text skips reserving. Any other token is ignored and the request counts normally.
  - `batch-create` uses `get_current_user`, so it is open to all users.
  - All `require_premium` uses are removed.
- Modify: `backend/budget_routes.py`. `ai-suggest` reserves `budget_suggestion`.
- Modify: `backend/budget_service.py`. The AI-optimised budget auto-create runs only when the owner's `effective_plan` is plus or pro and they're not over the cost cap. Otherwise it uses the existing non-AI adjusted budget.
- Modify: `backend/report_routes.py`. `/download` requires `reports` not locked: 403 `plan_feature_locked` for Free.
- Test: `e2e/test_plans.py`, plus updates to `test_api.py` and `test_sweep.py` where they assume Premium-only entry endpoints.

- [ ] **Step 1: Write the failing checks:**
  - `entry_shared_count`: text, image and multiple-text all draw from one count, and the 11th Free use gets 429.
  - `entry_zero_found_counts`: a canned "no transactions" answer counts.
  - `entry_fail_releases`
  - `voice_counts_once`: transcribe, then extract-multiple with the `voice_token`, adds +1 in total.
  - `voice_token_wrong_text_counts`: the same token with different text counts.
  - `voice_silent_no_count`
  - `batch_create_open_to_free`
  - `budget_suggest_limit`: a Free user gets 1, and the second gets 429.
  - `auto_create_ai_only_paid`: the Free owner's auto-create makes no AI call, and the Plus owner's does.
  - `report_download_locked_free`
- [ ] **Step 2: Run them and confirm they FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them and confirm they PASS.** Run the full suite and expect 0 problems.
- [ ] **Step 5: Commit** `feat(plans): entry, budget and report gates; voice counts once`.

### Task 7: Insights by plan and language

**Files:**
- Modify: `backend/main.py` (the `/api/insights*` routes) and `backend/insights_service.py`.
  - **All insight routes:** `get_current_user` plus plan checks.
  - **`GET /api/insights?insight_type=weekly`:** locked for Free (403).
  - **`GET /api/insights?insight_type=monthly` for Free:**
    - If a real (non-placeholder) monthly insight exists for the current calendar month, return it with no count.
    - Otherwise reserve `insight_monthly` and generate the same period the scheduled monthly job would. Commit only if the result is a real insight. A placeholder or a failure releases the reservation, and a failure falls back to the latest older insight as today.
  - **`POST /api/insights/regenerate` and `/generate-weekly`:** locked for Free.
  - **Language:** the `language` query parameter is honoured as the requested display language, independent of the user's profile language.
    - Plus and Pro: Myanmar is translated once and stored, as today.
    - Free: never translated. The response is English with `"translation_locked": true` whenever Myanmar was requested.
  - **`/translate-myanmar`:** locked for Free.
- Modify the scheduled weekly and monthly generators: select users whose `effective_plan` is plus or pro, which replaces the `subscription_type == "premium"` filter, and skip users `over_cost_cap`.
- Test: `e2e/test_plans.py`, and update the insight checks in existing suites.

- [ ] **Step 1: Write the failing checks:**
  - `free_monthly_on_demand_counts_once`: the first GET generates and counts 1, and a second GET returns the same insight with no new count.
  - `free_monthly_placeholder_no_count`: a user with no data gets a placeholder and `used` 0.
  - `free_monthly_existing_shown_free`: a stored insight from a Plus period is returned with `used` 0.
  - `free_weekly_locked`
  - `free_myanmar_returns_english_locked`: the fake outbox shows no translation call.
  - `plus_myanmar_translated_independent_of_profile`: the profile language is `en` and `?language=mm` returns Myanmar.
  - `scheduler_skips_free_and_capped`
- [ ] **Step 2: Run them and confirm they FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them and confirm they PASS.** Run the full suite and expect 0 problems.
- [ ] **Step 5: Commit** `feat(plans): insights by plan; language chosen per request`.

### Task 8: Admin panel: Plans page and user plan controls

**Files:**
- Create: `admin/src/PlansSettings.jsx`. A table of features × plans:
  - each cell has a mode select, plus a quota and period when the mode is `counted`;
  - each plan has a cost cap input;
  - there are two contact textareas (EN, MY);
  - Save and inline 422 messages;
  - read-only for moderators via `canWrite()`.
- Modify: `admin/src/api.js`. Add `getPlans()`, `updatePlans(body)`, `getUserUsage(id)` and `resetUserUsage(id)`.
- Modify: `admin/src/App.jsx`:
  - a sidebar item "Plans";
  - the user list and user page plan picker offer Free/Plus/Pro;
  - the user page shows a usage panel (per-feature used/limit/period, month spend, a "Cost cap reached" badge) and a "Reset usage" button for admins, with a confirm dialog;
  - the dashboard shows counts per plan;
  - broadcast targets add Plus, Pro and Paid;
  - every "Premium" label is replaced.
- Test: `cd admin; npm run lint; npm run build`, plus a manual browser check against the stubbed server, as in the AI-provider Task 13.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Run `npm run lint` and `npm run build`.** Expect success with no new warnings.
- [ ] **Step 3: Manual check:**
  1. As admin, change Free chat to 3/week and save. Reload: it persists.
  2. Open a Free user who used 2 chats and see "Chat 2/3 this week". Press Reset usage and see 0/3.
  3. Log in as moderator: there are no Save or Reset buttons.
  4. At 375 px width, nothing overflows.
  5. Restore the defaults.
- [ ] **Step 4: Commit** `feat(admin): Plans page and per-user plan usage controls`.

### Task 9: App: plan model, counters, limit sheet and Upgrade screen

**Files:**
- Modify: `frontend/lib/models/user.dart`. Replace the premium fields with `plan` (`free|plus|pro`), `isPaid`, `isPro`, `isTrial` and `trialEndsAt`.
- Create: `frontend/lib/models/plan_status.dart`. It parses `/api/plan`.
- Create: `frontend/lib/providers/plan_provider.dart`. It loads and refreshes `/api/plan` on app start, after every AI action and on an FCM `subscription_updated` message.
- Modify: `frontend/lib/services/api_service.dart`:
  - `getPlanStatus()`;
  - an exception type that carries the limit `code`, `feature`, `resetsAt` and `upgradeAvailable` from 403 and 429 bodies;
  - the `voice_token` pass-through between transcribe and extract.
- Create: `frontend/lib/widgets/plan_usage_line.dart` ("3 of 5 left this week") and `frontend/lib/widgets/plan_limit_sheet.dart`. The sheet says what ran out, when it resets, and an Upgrade button when `upgradeAvailable`.
- Modify: the AI entry points so they show `PlanUsageLine` and handle the limit exception with the sheet:
  - `screens/ai/ai_chat_screen.dart`;
  - `screens/transactions/image_input_screen.dart` and `voice_input_screen.dart`, and the text entry screen;
  - `screens/budgets/create_budget_screen.dart`;
  - `screens/insights/insights_screen.dart`.
- Modify: `frontend/lib/screens/subscription/subscription_screen.dart`. It compares Free/Plus/Pro from `catalog`, marks the current plan, and shows `upgrade_contact` in the app language.
- Modify: every `isPremium` / "Premium" use, in the files the spec section lists (`home_screen`, `settings_screen`, `app_drawer`, `premium_badge` renamed to `plan_badge`, `reports_screen`, `transactions_list_screen`, `edit_profile_screen`, `auth_provider`), to use the plan.
- Modify: `frontend/lib/services/localization_service.dart`. Add every new string in EN and MY.
- Test: `flutter analyze` (no new issues), and `flutter test` with new unit tests for `PlanStatus.fromJson` and the limit-exception parsing.

- [ ] **Step 1: Write the failing unit tests:**
  - `plan_status_parses_counts`;
  - `limit_exception_from_429`;
  - `remaining_never_negative_display`.
- [ ] **Step 2: Run `flutter test` and confirm they FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `flutter analyze` and `flutter test`.** Expect them to pass with no new analyzer issues.
- [ ] **Step 5: Commit** `feat(app): plans, usage counters, limit sheet and Upgrade screen`.

### Task 10: App: Advanced switch and insight language toggle

**Files:**
- Modify: `frontend/lib/screens/ai/ai_chat_screen.dart`, `providers/chat_provider.dart` and `services/api_service.dart`:
  - a Standard / Advanced segmented switch, visible only when `isPro`;
  - the switch is remembered in shared preferences and sends `mode`;
  - it reads `mode_used` and `advanced_exhausted` from the stream. When Advanced is exhausted, it shows a short note with the reset date and flips the switch to Standard.
  - The usage line shows Advanced remaining while Advanced is selected.
- Modify: `frontend/lib/screens/insights/insights_screen.dart` and `providers/insight_provider.dart`:
  - an English / မြန်မာ toggle, remembered on the device, that starts on the app language for paid users;
  - requests send the toggle's language;
  - for Free, မြန်မာ shows a lock and opens the Upgrade screen, and the insight shows in English.
- Test: `flutter analyze`, `flutter test`, and the Flutter integration flows. Update the `integration_test` flows and accounts that assume Premium to use Plus/Pro, and add:
  - `free_chat_limit_sheet`: a Free account sends 5 messages, and the 6th shows the limit sheet with Upgrade;
  - `pro_advanced_switch`: a Pro account sees the switch, and the Plus account does not;
  - `free_insight_myanmar_locked`.
- [ ] **Step 1: Implement**, including updating the integration accounts and flows.
- [ ] **Step 2: Run `flutter analyze` and `flutter test`.**
- [ ] **Step 3: Run the full Flutter e2e** with `e2e\run_e2e.ps1 -Python <PY> -PgBin <PGBIN>`, then `-LargeText -Name "^14 Large text tour "`. Expect 0 failed, with the new flows included.
- [ ] **Step 4: Commit** `feat(app): Pro Advanced chat switch and insight language toggle`.

### Task 11: Full regression and deploy notes

**Files:**
- Modify: `docs/postgres-migration-plan.md` ("Deploying on Render"). Add a "Plans and quotas" section covering:
  - the migration revision and what it does (premium → plus);
  - where the owner edits limits, caps and the contact message;
  - "Reset usage";
  - a post-deploy checklist: set the contact message; claim a trial on a test account; use a Free account to its chat limit; switch a test account to Pro and send one Advanced message.
- [ ] **Step 1:** Run the full backend suite. Expect `problems (0)` and `crashes (0)`.
- [ ] **Step 2:** Run the admin lint and build, `flutter analyze` and `flutter test`.
- [ ] **Step 3:** Secret scan, as in the AI-provider Task 15: exclude `.env*` and report paths only.
- [ ] **Step 4: Commit** `docs: plans and quotas deploy notes`.
