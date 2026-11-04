# Custom Insights for Pro Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pro users pick a date range (7 days to 12 months) and, optionally, a short instruction, and get a saved Markdown report about their own money in that range, made in the background, with figure cards the app computes and an English / မြန်မာ toggle.

**Architecture:** A new quota feature and AI feature, both keyed `insight_custom` (plans catalogue plus a migration seed; AI providers catalogue with its own usage type `custom_insight`). A new `custom_insights` table and data layer (`sql/custom_insights.py`), a generation service (`custom_insights_service.py`) that runs each report as an asyncio task, and a router (`custom_insight_routes.py`) that validates, applies the reuse rule, reserves the allowance and starts the task. A scheduler job fails stuck reports and gives their use back. The app gets a data layer (model, API, `CustomInsightProvider`) and a third "Custom" tab on the Insights screen with a form, a list and a report screen.

**Tech Stack:** FastAPI + SQLAlchemy Core (async) + Alembic on PostgreSQL; the `ai_providers` runner; Flutter (provider, flutter_markdown); React admin (Vite).

**Spec:** `docs/superpowers/specs/2026-11-04-custom-insights-design.md` (binding; this plan argues from it).

## Global Constraints

- The spec is binding. Where it leaves a choice to the builder, the value fixed in this plan applies; don't change it.
- Fixed values: quota feature and AI feature key `insight_custom`; AI usage type `custom_insight`; default limits Free `locked`, Plus `locked`, Pro `counted` 10 per `month`; AI default `claude` / `claude-sonnet-5-5` (all three providers allowed); range 7 days to 12 months inclusive, ending today or earlier (app timezone); instruction at most 300 characters after trimming; presets `where_to_save`, `compare_previous`, `biggest_changes`, `budgets_goals`; outline headings `## Summary`, `## What I found`, `## What to do next`; off-topic marker `[[NOT_FINANCE]]`; at most 5 failed or refused attempts per local day; a report still `pending` 20 minutes after it was created counts as stuck.
- No change to how weekly or monthly insights behave, or to their schedule. `e2e/plans_insight_checks.py` must keep passing unchanged.
- Backend tests are print-only e2e check scripts (`check(ok, "name: what it proves", detail)` prints `[PASS]`/`[BUG]`). There is no pytest. They run against the stub server on `127.0.0.1:8765` (`E2E_FAKE_AI=1`, fake OpenAI/Gemini/Claude in `e2e/stubenv.py`) and the local Postgres `postgresql://flow@127.0.0.1:54329/flow_e2e`. Never test against production.
- Never open, print, grep or cut any `.env` file.
- New backend checks go in `e2e/plans_custom_insight_checks.py`, which `e2e/test_plans.py` calls. `test_plans` stays the LAST entry of `run_backend_suite.SUITES` (it runs alembic downgrade/upgrade).
- The full backend suite (`run_backend_suite.py`) must end with `== problems (0) ==` and `== crashes (0) ==`.
- `flutter analyze` must report no more than 186 issues. `flutter test` must pass in full. In `admin/`, `npm run lint` and `npm run build` must be clean.
- Every user-facing string comes in English and Myanmar. App strings go in both maps of `frontend/lib/services/localization_service.dart` and get a getter. Server strings go in `NOTIFICATION_TRANSLATIONS["en"]` and `["my"]` in `backend/notification_service.py`. Flag new Myanmar wording in the commit message ("MM wording to be checked by a native speaker").
- The shell is PowerShell (Git Bash is broken on this machine). `$py` is the Python interpreter that has the backend deps (the one `e2e/run_e2e.ps1 -Python` gets).
- Harness commands (PowerShell):
  - Schema: `$env:DATABASE_URL='postgresql://flow@127.0.0.1:54329/flow_e2e'; Push-Location C:\projects\Flow\backend; & $py -m alembic upgrade head 2>&1 | % { "$_" }; Pop-Location`
  - (Re)start the stub server after ANY backend change, before HTTP checks: `Get-NetTCPConnection -LocalPort 8765 -State Listen -EA SilentlyContinue | % { Stop-Process -Id $_.OwningProcess -Force }; $env:E2E_FAKE_AI='1'; $env:PYTHONIOENCODING='utf-8'; Start-Process $py -ArgumentList '-u C:\projects\Flow\e2e\run_server.py' -WindowStyle Hidden -RedirectStandardOutput C:\projects\Flow\e2e\logs\server.log -RedirectStandardError C:\projects\Flow\e2e\logs\server_err.log`, then wait until `Invoke-RestMethod http://127.0.0.1:8765/` answers.
  - One suite: `& $py -u C:\projects\Flow\e2e\test_plans.py 2>&1 | Select-String '\[BUG\]|passed'`. All suites: `& $py C:\projects\Flow\e2e\run_backend_suite.py`
- Commit once per task, on branch `custom-insights`. Don't push. Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

- **A transaction in the range is deleted, or its date moved out of the range, after a report was made.** Deleting leaves no `updated_at`, so the spec's "created or edited after" rule alone would reuse a stale report. The reuse rule also requires the freshly computed figures to equal the stored snapshot. Test: Task 5 `reuse_after_delete_regenerates`.
- **Double tap on Create (two POSTs at once).** Expected: one report and one use. The second request gets 409 and its reservation is given back. Test: Task 5 `create_concurrent_one_pending`.
- **The sweeper and a slow job race.** The job finishes after the sweeper has already failed the report. Expected: the use is given back exactly once, the late answer is dropped, and the user gets one notification. Whoever moves the row out of `pending` owns the give-back and the notification. Test: Task 4 `sweeper_then_late_finish_no_double_give_back`.
- **A user deletes refused or failed reports to get round the 5-a-day limit.** Expected: deleting hides them but they still count. Failed and refused rows are soft-deleted (content cleared). Test: Task 5 `attempts_survive_delete`.
- **A "ready" notification is tapped after the report was deleted.** Expected: a "This custom insight was deleted" state, not a crash or endless spinner. Test: Task 7 `report_screen_deleted_state`.

---

## File map

| File | Responsibility | Task |
|---|---|---|
| `backend/plans/catalog.py` | quota feature + defaults | 1 |
| `backend/sql/tables.py`, `backend/alembic/versions/20261104_b8f4d2c6e9a1_custom_insights.py` | table + seed | 1 |
| `backend/sql/custom_insights.py` (new) | all SQL on `custom_insights` | 1 |
| `backend/sql/transactions.py` | `changed_since` | 1 |
| `backend/ai_usage_models.py`, `backend/ai_providers/features.py`, `backend/ai_providers/clients/base.py` | AI feature | 2 |
| `admin/src/planLabels.js`, `admin/src/AIUsageStats.jsx` | admin labels | 2 |
| `backend/notification_models.py`, `backend/notification_service.py`, `backend/plans/access.py` | notifications | 3 |
| `backend/custom_insights_service.py` (new), `backend/insights_service.py`, `backend/scheduler.py`, `e2e/stubenv.py` | generation, sweeper | 4 |
| `backend/custom_insight_routes.py` (new), `backend/main.py` | HTTP API | 5 |
| `frontend/lib/models/custom_insight.dart`, `lib/utils/custom_insight_ranges.dart`, `lib/utils/safe_markdown.dart`, `lib/providers/custom_insight_provider.dart` (new); `api_service.dart`, `plan_status.dart`, `notification_event_bus.dart`, `fcm_service.dart`, `main.dart` | app data layer | 6 |
| `frontend/lib/screens/insights/custom_*.dart`, `lib/widgets/custom_insight_figures.dart`, `lib/widgets/insight_markdown.dart` (new); `insights_screen.dart`, `notification.dart`, `notifications_screen.dart`, `services/notification_service.dart` | app UI | 7 |
| `frontend/integration_test/flows/ai_flows.dart`, `docs/postgres-migration-plan.md` | e2e + deploy notes | 8 |

---

### Task 1: Quota feature `insight_custom`, the `custom_insights` table and its data layer

**Files:**
- Modify: `backend/plans/catalog.py` (FEATURES, DEFAULT_LIMITS)
- Modify: `backend/sql/tables.py` (add `custom_insights` after `insights`)
- Create: `backend/alembic/versions/20261104_b8f4d2c6e9a1_custom_insights.py`
- Create: `backend/sql/custom_insights.py`
- Modify: `backend/sql/transactions.py` (add `changed_since`)
- Modify: `backend/notification_service.py` (`plan_feature_insight_custom` en/my)
- Modify: `e2e/test_plans.py` (catalog expectations, 24 → 27 rows, call the new module)
- Create: `e2e/plans_custom_insight_checks.py`

**Interfaces:**
- Consumes: `plans.catalog.Limit`; `sql.db.execute/fetch_one/fetch_all/write_returning/transaction`; `sql.docs.row_to_doc` (`id` → `_id`); `_user_fk()` in tables.py.
- Produces:
  - `catalog.FEATURES == ("chat", "chat_advanced", "insight_monthly", "insight_weekly", "insight_translation", "insight_custom", "entry", "budget_suggestion", "reports")`. Its `DEFAULT_LIMITS`: free and plus `Limit("locked")`, pro `Limit("counted", 10, "month")`.
  - Table `custom_insights`:
    - Columns: `id TEXT PK`; `user_id TEXT` FK users ON DELETE CASCADE, indexed; `start_date DATE NOT NULL`; `end_date DATE NOT NULL`; `preset TEXT NULL`; `instruction TEXT NULL`; `instruction_key TEXT NOT NULL DEFAULT ''`; `status TEXT NOT NULL DEFAULT 'pending'`; `content TEXT NULL`; `content_mm TEXT NULL`; `figures JSONB NULL`; `ai_provider TEXT NULL`; `ai_model TEXT NULL`; `input_tokens INT NULL`; `output_tokens INT NULL`; `counter_keys JSONB NOT NULL DEFAULT '[]'`; `created_at TS NOT NULL DEFAULT now()`; `completed_at TS NULL`; `deleted_at TS NULL`.
    - CHECKs (convention names): `status IN ('pending','ready','failed','refused')`; `end_date >= start_date`; `preset IS NULL OR preset IN ('where_to_save','compare_previous','biggest_changes','budgets_goals')`; `instruction IS NULL OR char_length(instruction) <= 300`; `preset IS NULL OR instruction IS NULL`; `status <> 'ready' OR (content IS NOT NULL AND btrim(content) <> '')`; `deleted_at IS NULL OR status IN ('failed','refused')`.
    - Indexes: `ix_custom_insights_user_created (user_id, created_at DESC)`; unique `uq_custom_insights_pending_user (user_id) WHERE status = 'pending'`.
  - Migration `revision = 'b8f4d2c6e9a1'`, `down_revision = 'a7d3e5c91f20'`.
    - Upgrade creates the table and indexes, then bulk-inserts its own copy of the three `plan_limits` rows: `('free','insight_custom','locked',None,None)`, `('plus','insight_custom','locked',None,None)`, `('pro','insight_custom','counted',10,'month')`. Use `sa.table('plan_limits', ...)` as the c4e8b1a05d37 migration does.
    - Downgrade drops the table and deletes the `plan_limits` and `usage_counters` rows with `feature = 'insight_custom'`.
  - `backend/sql/custom_insights.py`. Every function returns `row_to_doc` dicts (`_id`, `start_date`/`end_date` as `date`, `figures` dict, `counter_keys` list of `[feature, period, "YYYY-MM-DD"]`):
    - `async def insert_pending(doc: dict) -> bool`: an INSERT ON CONFLICT DO NOTHING on the partial index (`index_where=text("status = 'pending'")`, as in `sql/upgrade_requests.py`). Returns False when the user already has a pending row.
    - `async def get(report_id: str, user_id: str | None = None, include_deleted: bool = False) -> dict | None`
    - `async def list_for_user(user_id: str, limit: int = 100) -> list[dict]`: newest first, not deleted.
    - `async def has_pending(user_id: str) -> bool`
    - `async def find_ready_match(user_id: str, start_date: date, end_date: date, instruction_key: str) -> dict | None`: the newest `ready`, not-deleted row with those exact values.
    - `async def count_attempts_since(user_id: str, since: datetime) -> int`: rows with status `failed`/`refused` and `created_at >= since`. Deleted rows count too.
    - `async def finish(report_id: str, *, status: str, now: datetime, content: str | None = None, ai_provider: str | None = None, ai_model: str | None = None, input_tokens: int | None = None, output_tokens: int | None = None) -> dict | None`: `UPDATE … WHERE id = :id AND status = 'pending' RETURNING *`. Returns None when the row is no longer pending.
    - `async def fail_stuck(before: datetime, now: datetime) -> list[dict]`: one UPDATE that sets every `pending` row with `created_at < before` to `failed` and `completed_at = now`, RETURNING the rows.
    - `async def set_translation(report_id: str, content_mm: str) -> None`
    - `async def delete_for_user(report_id: str, user_id: str, now: datetime) -> str`: returns one of `"deleted"` (a `ready` row is removed), `"hidden"` (a `failed`/`refused` row gets `deleted_at = now` and `instruction`, `preset`, `content`, `content_mm`, `figures` = NULL), `"pending"` (nothing changed) or `"missing"`.
  - `transactions_db.changed_since(user_id: str, start: datetime, end: datetime, since: datetime) -> bool`: True when a transaction dated in [start, end] has `created_at > since` or `updated_at > since`.
  - `e2e/plans_custom_insight_checks.py`:
    - `def migration_checks(t)` (sync) and `async def run(t)`. `run` calls this task's `await storage_checks(t, h)`; later tasks add `notification_checks`, `generation_checks` and `route_checks` to it, in that order.
    - A small helper object `h`, built in `run`, with: `h.c` (httpx client on :8765), `h.db` (pgcompat), `h.AD` (admin headers), `h.register(name, lang="en") -> (uid, headers)`, `h.set_plan(uid, plan) -> bool`, `h.used(uid, period="month") -> int` (the insight_custom counter), `h.set_used(uid, n)`, `h.add_tx(headers, type_, amount, day: date, main="Food & Daily Living", sub="Groceries", currency="usd") -> str`.
    - Copy the patterns of `plans_insight_checks.py`: users tagged `t9c-…`, admins made via `t.make_admins`, everything removed in a `finally`.

- [ ] **Step 1: Write the failing checks**

In `e2e/test_plans.py`:
- `catalog_checks`: the FEATURES tuple above. The `spec` dict gains `"insight_custom": L("locked")` for free and plus and `L("counted", 10, "month")` for pro. The "24" texts and `len(...) == 24` become 27, in `catalog_checks`, `defaults_seeded` and `store_checks`.
- `main()`: call `plans_custom_insight_checks.migration_checks(sys.modules[__name__])` right after `migration_checks()`.
- `plans_checks()`: `await plans_custom_insight_checks.run(sys.modules[__name__])` after the upgrade-request checks.

In `plans_custom_insight_checks.py`:

```python
# migration_checks(t): uses t.alembic, t.connect, t.current_revision, t.table_names, t.seeded_limits
check(ok_down and "custom_insights" not in t.table_names(conn)
      and not any(f == "insight_custom" for (_, f) in t.seeded_limits(conn)),
      "custom_migration_down: downgrade to a7d3e5c91f20 drops custom_insights and the insight_custom limits")
check(ok_up and t.seeded_limits(conn)[("pro", "insight_custom")] == ("counted", 10, "month")
      and t.seeded_limits(conn)[("plus", "insight_custom")] == ("locked", None, None),
      "custom_migration_up: upgrade re-creates the table and seeds Free/Plus locked, Pro 10 a month")
check(t.current_revision(conn) == "b8f4d2c6e9a1", "custom_migration: the database is left at head")
# storage_checks(t, h) (in-process, sql.custom_insights):
check(await ci.insert_pending(doc_a) is True and await ci.insert_pending(doc_a2) is False
      and await ci.insert_pending(doc_b_other_user) is True, "storage_one_pending_per_user")
check(await ci.finish(a, status="ready", content="## Summary\nx", now=now) is not None
      and await ci.finish(a, status="failed", now=now) is None, "storage_finish_only_from_pending")
check(not t.accepted(conn, ("INSERT INTO custom_insights (id, user_id, start_date, end_date, status) VALUES (%s, %s, %s, %s, 'ready')", (...))),
      "storage_ready_needs_content")
check(await ci.delete_for_user(ready_id, uid, now) == "deleted" and await ci.get(ready_id) is None,
      "storage_delete_ready_removes_row")
check(await ci.delete_for_user(failed_id, uid, now) == "hidden" and failed_id not in ids(await ci.list_for_user(uid))
      and await ci.count_attempts_since(uid, day_start) == 1, "storage_delete_failed_hides_but_counts")
check(await ci.delete_for_user(pending_id, uid, now) == "pending", "storage_delete_pending_refused")
check(await ci.fail_stuck(now - timedelta(minutes=20), now) == [old_pending_row_as_failed]
      and await ci.fail_stuck(now - timedelta(minutes=20), now) == [], "storage_fail_stuck_once")
check(match["_id"] == ready2 and await ci.find_ready_match(uid, s, e, "other") is None, "storage_find_ready_match")
check(await transactions_db.changed_since(uid, s_bound, e_bound, before_edit) is True
      and await transactions_db.changed_since(uid, s_bound, e_bound, after_edit) is False, "storage_changed_since")
check(rows_after_user_delete == 0, "storage_cascade: deleting the user deletes their custom insights")
p = h.c.get("/api/plan", headers=pro_h).json()["features"]["insight_custom"]
check(p["mode"] == "counted" and p["limit"] == 10 and p["period"] == "month" and p["used"] == 0,
      "plan_status_insight_custom: GET /api/plan shows Pro 10 a month")
```

- [ ] **Step 2: Run and watch it fail.** Run the harness `test_plans` command. Expected: `[BUG] catalog: FEATURES …` and `ModuleNotFoundError`/`[BUG]` lines for the new checks.

- [ ] **Step 3: Implement.** Make the catalog, table, migration, `sql/custom_insights.py` and `changed_since` match the Interfaces above. Add the translations `"plan_feature_insight_custom": "custom insights"` (en) and `"စိတ်ကြိုက် သုံးသပ်ချက်"` (my), so PlanError messages name the feature. Then run the schema command and restart the stub server.

- [ ] **Step 4: Run again.** Run the harness `test_plans` command. Expected: no `[BUG]` lines; the last line reads `N/N passed`.

- [ ] **Step 5: Commit.**
```powershell
git add backend/plans/catalog.py backend/sql/tables.py backend/sql/custom_insights.py backend/sql/transactions.py backend/notification_service.py backend/alembic/versions/20261104_b8f4d2c6e9a1_custom_insights.py e2e/test_plans.py e2e/plans_custom_insight_checks.py
git commit -m "feat(backend): insight_custom quota feature and the custom_insights table" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: AI feature `insight_custom`, its usage type and the admin labels

**Files:**
- Modify: `backend/ai_usage_models.py`, `backend/ai_providers/features.py`, `backend/ai_providers/clients/base.py`
- Modify: `admin/src/planLabels.js`, `admin/src/AIUsageStats.jsx`
- Test: `e2e/test_ai_providers.py`

**Interfaces:**
- Consumes: the quota feature key `insight_custom` (Task 1).
- Produces:
  - `AIFeatureType.CUSTOM_INSIGHT = "custom_insight"`.
  - `features.FEATURES["insight_custom"] == FeatureSpec("insight_custom", "Custom insight", PROVIDERS, Target("claude", "claude-sonnet-5-5"), AIFeatureType.CUSTOM_INSIGHT)`, placed right after `insight_translation`.
  - `CLAUDE_EFFORT["insight_custom"] == "medium"`; `"insight_custom" in LONG_TIMEOUT_FEATURES`, so `request_timeout("insight_custom") == 300`.
  - Not in `_ENV_MODEL_FEATURES`, so the built-in model is fixed.
  - Admin: `FEATURES` in planLabels.js lists `'insight_custom'` after `'insight_translation'`, and `FEATURE_LABELS.insight_custom = 'Custom insight'`. The AIUsageStats feature filter gains `<option value="custom_insight">Custom Insights</option>`. The AI Providers page lists features from the API, so it needs no change.

- [ ] **Step 1: Update the expectations in `e2e/test_ai_providers.py`**
  - The catalogue key set gains `"insight_custom"`.
  - A new check: `catalogue: insight_custom is 'Custom insight', all providers, built-in claude-sonnet-5-5`.
  - The usage-type map gains `"insight_custom": AIFeatureType.CUSTOM_INSIGHT`.
  - `CLAUDE_EFFORT` gains `"insight_custom": "medium"`.
  - A new check: `check(request_timeout("insight_custom") == 300, "timeout_custom_insight_long")`.
  - `ADMIN_FEATURES` gains `"insight_custom"` after `"insight_translation"`, and `len(body["features"]) == 11`.
  - A new HTTP check, `usage_filter_custom_insight`: as a moderator, `GET /api/admin/ai-usage/user/{user_id}?feature_type=custom_insight` answers 200, where it answered 422 before the enum value existed.
- [ ] **Step 2: Run it and watch it fail.** `& $py -u C:\projects\Flow\e2e\test_ai_providers.py 2>&1 | Select-String '\[BUG\]'`. Expected: the catalogue, usage, effort and settings_get checks fail.
- [ ] **Step 3: Implement** the backend lines above and the two admin edits. Restart the stub server.
- [ ] **Step 4: Run it again** and expect no `[BUG]` lines. Then run `Push-Location C:\projects\Flow\admin; npm run lint; npm run build; Pop-Location`. Expected: no lint errors, and the build succeeds.
- [ ] **Step 5: Commit** (`feat: insight_custom AI feature (default Claude) and admin labels`, with the Co-Authored-By line).

---

### Task 3: "Ready" and "couldn't create it" notifications

**Files:**
- Modify: `backend/notification_models.py`, `backend/notification_service.py`, `backend/plans/access.py`
- Test: `e2e/plans_custom_insight_checks.py` (add `notification_checks`)

**Interfaces:**
- Consumes: `create_notification(user_id, notification_type, title, message, goal_id=…)`, `translate(key, lang, **kw)`, `get_user_language(user_id)`.
- Produces:
  - `NotificationType.CUSTOM_INSIGHT_READY = "custom_insight_ready"` and `CUSTOM_INSIGHT_FAILED = "custom_insight_failed"`. Both are also `True` in the default preferences dict of `get_user_notification_preferences`. No new settings toggle.
  - `plans.access.format_day(day: date, lang: str) -> str`: the same output as `format_date` for that calendar day ("Nov 4, 2026" / "4 နိုဝင်ဘာ 2026"), with no timezone conversion.
  - `async def notify_custom_insight_ready(user_id: str, report_id: str, start: date, end: date) -> None`
  - `async def notify_custom_insight_failed(user_id: str, report_id: str, start: date, end: date, refused: bool) -> None`
  - Both store `goal_id = report_id` (the app opens the report from it; the codebase already reuses `goal_id` for budget and transaction ids). `{range}` is `f"{format_day(start, lang)} – {format_day(end, lang)}"`. Failures are logged and swallowed.
  - English copy (exact). The implementer writes the Myanmar:
    - `custom_insight_ready_title`: "Your custom insight is ready 📊"
    - `custom_insight_ready_msg`: "Your insight for {range} is ready. Tap to read it."
    - `custom_insight_failed_title`: "Custom insight not created"
    - `custom_insight_failed_msg`: "We couldn't create your insight for {range}. It wasn't counted, so you can try again."
    - `custom_insight_refused_msg`: "That isn't something I can answer from your finances, so no insight was created for {range}. It wasn't counted."
  - A refusal uses the failed type and title with the refused message.

- [ ] **Step 1: Write `notification_checks(t, h)`** (in-process; read rows with `t.connect()`):
```python
check(row["type"] == "custom_insight_ready" and row["goal_id"] == rid and "Oct 6, 2026 – Nov 4, 2026" in row["message"],
      "notify_custom_ready: stored with the report id and the date range")
check(f["type"] == "custom_insight_failed" and "wasn't counted" in f["message"], "notify_custom_failed: says it was not counted")
check(r["message"] != f["message"] and "answer from your finances" in r["message"], "notify_custom_refused: its own message")
check(MYANMAR.search(mm_row["title"]) and MYANMAR.search(mm_row["message"]), "notify_custom_myanmar: a Myanmar user gets Myanmar text")
check(format_day(date(2026, 12, 1), "en") == "Dec 1, 2026" and format_day(date(2026, 12, 1), "my") == "1 ဒီဇင်ဘာ 2026", "format_day")
```
- [ ] **Step 2: Run the harness `test_plans` command.** Expected: `[BUG]`/ImportError on `notify_custom_insight_ready`.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run it again** and expect no `[BUG]` lines.
- [ ] **Step 5: Commit** (`feat(backend): custom insight ready / not created notifications`; note "MM wording to be checked by a native speaker").

---

### Task 4: Generation service: figures, prompt, off-topic marker, background job, stuck-job sweeper

**Files:**
- Create: `backend/custom_insights_service.py`
- Modify: `backend/insights_service.py` (extract `run_insight_model`; add the `INSIGHT_MAX_TOKENS["insight_custom"]` entry; nothing else changes)
- Modify: `backend/tz_utils.py` (public `day_bounds_utc`)
- Modify: `backend/scheduler.py` (sweeper job)
- Modify: `e2e/stubenv.py` (fake kind `off_topic`)
- Test: `e2e/plans_custom_insight_checks.py` (add `generation_checks`)

**Interfaces:**
- Consumes:
  - From Task 1: `sql.custom_insights.{get, finish, fail_stuck}`, and the row shape (`counter_keys` = `[[feature, period, "YYYY-MM-DD"], …]`).
  - From Task 3: `notify_custom_insight_ready` / `notify_custom_insight_failed`.
  - `insights_service.get_financial_summary(user_id, start_dt, end_dt)` (per-currency inflow/outflow/count, and the top 5 outflow categories as "Main > Sub").
  - `quota.Reservation(user_id, keys)` and `quota.give_back(r)`; `goals_db.list_goals(user_id)`; `budgets_db.budgets_overlapping(user_id, start_dt, end_dt)`; `users_db.get_user`.
- Produces:
  - `tz_utils.day_bounds_utc(start: date, end: date) -> tuple[datetime, datetime]` (`_day_bounds_utc` becomes an alias of it).
  - `insights_service.run_insight_model(feature, system_prompt, context, user_id, label, background=False) -> RunResult`. It carries the current body of `_call_insight_model`, including the error mapping to `InsightAIError`. `_call_insight_model` becomes a wrapper that returns the same 5-tuple as now. Add `INSIGHT_MAX_TOKENS["insight_custom"] = {"openai": 2000, "gemini": 8192, "claude": 12000}`.
  - In `custom_insights_service`:
    - Constants: `PRESETS: dict[str, str]` = {"where_to_save": "Where can I save?", "compare_previous": "Compare with the previous period", "biggest_changes": "Biggest changes", "budgets_goals": "Check my budgets and goals"}; `OFF_TOPIC_MARKER = "[[NOT_FINANCE]]"`; `MIN_DAYS = 7`; `MAX_INSTRUCTION_LENGTH = 300`; `MAX_FAILED_ATTEMPTS_PER_DAY = 5`; `STUCK_AFTER = timedelta(minutes=20)`.
    - `class RangeError(ValueError)`
    - `def validate_range(start: date, end: date, today: date) -> None` raises RangeError when: `end < start`, `(end - start).days + 1 < 7`, `end > today`, or `end >= one_year_after(start)`.
    - `def one_year_after(d: date) -> date` gives the same day next year; Feb 29 becomes Mar 1.
    - `def previous_period(start: date, end: date) -> tuple[date, date]` returns the equal-length period that ends the day before `start`.
    - `def instruction_key(preset: str | None, instruction: str | None) -> str` returns `""` for none, `"preset:<key>"` for a preset, and `"text:" + instruction.strip().casefold()` for free text.
    - `def instruction_text(row: dict) -> str | None` returns the PRESETS text or the instruction.
    - `async def compute_figures(user_id: str, start: date, end: date) -> dict`, in exactly this shape:
      `{"previous_start": "YYYY-MM-DD", "previous_end": "YYYY-MM-DD", "currencies": [{"currency": "usd", "income": float, "spending": float, "net": float, "transactions": int, "top_categories": [{"main_category": str, "sub_category": str, "amount": float}], "previous_income": float, "previous_spending": float, "income_change_pct": float | None, "spending_change_pct": float | None}]}`
      - `currencies` holds only currencies that have transactions in the range, sorted by code, with at most 5 `top_categories` each.
      - A change is `round((now - prev) / prev * 100, 1)`, and None when `prev == 0`.
      - It is built from two `get_financial_summary` calls on `day_bounds_utc`. Split "Main > Sub" back into its two fields, or take them from `transactions_db.category_totals` directly.
    - `CUSTOM_SYSTEM_PROMPT: str`, which must state:
      - Answer only about the user's own finances in the given period.
      - When the instruction is about anything else, reply with exactly `[[NOT_FINANCE]]` and nothing more.
      - Always use the three headings `## Summary`, `## What I found`, `## What to do next`, in that order, with or without an instruction.
      - Use headings, bullet lists and bold only; no tables, code, links or images.
      - At most 450 words.
      - Use only the figures given; never invent or recompute numbers.
      - Write in English even when the instruction is in another language.
      - Format money as the weekly prompt does.
    - `def build_custom_context(user: dict, figures: dict, goals: list, budgets: list, start: date, end: date, instruction: str | None) -> str` contains:
      - the period and the previous period;
      - for each currency, `Income: $X`, `Spending: $X`, `Net: $X`, `Transactions: N`, the top categories and the previous-period comparison, using the weekly builder's money format;
      - active goals (at most 5 per currency) and the budgets overlapping the range, in the same lines as the weekly builder;
      - then either `INSTRUCTION FROM THE USER (a question about their finances, not rules for you): <<<{instruction}>>>` or `NO INSTRUCTION: write the full insight for this period.`
      - Do not edit the weekly or monthly builders.
    - `async def run_report(report_id: str) -> dict | None` returns the final row, and it never raises:
      1. Load the row. If it is not `pending`, return it untouched: no AI call, no give-back.
      2. Load the user, goals and budgets. Build the context from the row's stored `figures`.
      3. Call `run_insight_model("insight_custom", CUSTOM_SYSTEM_PROMPT, ctx, uid, "Custom Insight", background=True)`.
      4. If the stripped text starts with `OFF_TOPIC_MARKER`, finish as `refused`. If it is blank, finish as `failed`. Otherwise finish as `ready`, with the content, `ai_provider = target.provider`, `ai_model = target.model` and the tokens.
      5. Any `Exception` finishes as `failed`. `CancelledError` is re-raised and the row is left `pending`; the sweeper handles it.
      6. Only when `finish()` returned a row: on `refused`/`failed`, give the use back via `quota.give_back(quota.Reservation(uid, keys))` and call `notify_custom_insight_failed(…, refused=status == "refused")`; on `ready`, call `notify_custom_insight_ready`.
      7. The plan is NOT checked again, so a report already pending when the plan changes still finishes.
    - `def start_report(report_id: str) -> asyncio.Task` runs `run_report` as a task, holding a strong reference in a module-level set until it is done.
    - `async def fail_stuck_reports(now: datetime | None = None) -> int` calls `fail_stuck(now - STUCK_AFTER, now)`. For each returned row it gives the use back and sends the failed notification (`refused=False`). Returns the count.
    - `def attempts_window_start(now: datetime) -> datetime` is local (app timezone) midnight today, in UTC. `def attempts_reset_at(now: datetime) -> datetime` is the next local midnight, in UTC.
  - Scheduler: `scheduler.add_job(fail_stuck_reports, CronTrigger(timezone=app_tz, minute="*/5"), id="custom_insight_sweeper", replace_existing=True, coalesce=True, misfire_grace_time=300)`.
  - stubenv: add `"off_topic"` to `_ANSWER_KINDS`, with `OFF_TOPIC_TEXT = "[[NOT_FINANCE]]"`. `_answer_text` returns it for that kind on every provider.

- [ ] **Step 1: Write `generation_checks(t, h)`.** It runs in-process. Make a Pro user over HTTP and add transactions with `h.add_tx`. The range is `today-29 .. today`; the previous period is the 30 days before it. Range transactions: inflow 1000 usd, outflow 200 Groceries, outflow 50 "Transportation"/"Taxi". Previous period: outflow 100.

  To create pending rows, reserve with `quota.reserve(user, "insight_custom")`, then call `ci.insert_pending` with `counter_keys` from `r.keys` and the figures from `compute_figures`, then `r.commit()`.
```python
check(f["currencies"] == [{"currency": "usd", "income": 1000.0, "spending": 250.0, "net": 750.0, "transactions": 3,
      "top_categories": [{"main_category": "Food & Daily Living", "sub_category": "Groceries", "amount": 200.0},
                         {"main_category": "Transportation", "sub_category": "Taxi", "amount": 50.0}],
      "previous_income": 0.0, "previous_spending": 100.0, "income_change_pct": None, "spending_change_pct": 150.0}],
      "figures_computed_from_data")
check(previous_period(date(2026,11,1), date(2026,11,30)) == (date(2026,10,2), date(2026,10,31)), "previous_period_equal_length")
check(ok(today - timedelta(6), today) and bad(today - timedelta(5), today) and bad(today, today + timedelta(1))
      and ok(date(2025,11,5), date(2026,11,4)) and bad(date(2025,11,4), date(2026,11,4))
      and one_year_after(date(2028,2,29)) == date(2029,3,1), "validate_range_bounds")
check(instruction_key(None, "  Where Can I SAVE? ") == instruction_key(None, "where can i save?") != instruction_key("where_to_save", None)
      and instruction_key(None, None) == "", "instruction_key_trim_casefold")
check(stubenv.OFF_TOPIC_TEXT == OFF_TOPIC_MARKER, "stub_marker_matches")
# ready
row = await run_report(rid)
check(row["status"] == "ready" and row["content"] == stubenv.FAKE_REPLY and row["ai_provider"] == "claude"
      and row["ai_model"] == "claude-sonnet-5-5" and row["input_tokens"] == 10 and row["completed_at"] and h.used(uid) == 1,
      "run_report_ready: stored with provider, model, tokens; the use stays counted")
prompt = str(stubenv.LAST_KWARGS["claude"])
check("## What to do next" in CUSTOM_SYSTEM_PROMPT and "Spending: $250.00" in prompt and "<<<Where can I save?>>>" in prompt,
      "run_report_context: the model gets the computed figures and the instruction")
check(notif_types(uid) == ["custom_insight_ready"], "run_report_ready_notifies")
# refused: stubenv.set_fake_ai(claude="off_topic"); failed: stubenv.set_fake_ai(openai="server", gemini="server", claude="server")
check(row["status"] == "refused" and row["content"] is None and h.used(uid) == 0 and last_notif(uid)["type"] == "custom_insight_failed",
      "run_report_refused_not_counted")
check(row["status"] == "failed" and h.used(uid) == 0, "run_report_failed_not_counted")
check(h.set_plan(uid, "free") and (await run_report(rid4))["status"] == "ready" and h.used(uid) == 1,
      "run_report_finishes_after_plan_change")
# sweeper: a pending row with created_at = now - 25 min (UPDATE via t.connect)
check(await fail_stuck_reports() == 1 and h.used(uid) == 0 and (await ci.get(rid5))["status"] == "failed", "sweeper_fails_and_gives_back")
check((await run_report(rid5))["status"] == "failed" and h.used(uid) == 0 and ai_calls_made == 0 and notif_count_after == notif_count_before,
      "sweeper_then_late_finish_no_double_give_back")
check(await fail_stuck_reports() == 0, "sweeper_idempotent")
sched = scheduler.start_scheduler(); job = sched.get_job("custom_insight_sweeper"); sched.shutdown(wait=False)
check(job is not None, "sweeper_scheduled_every_5_minutes")
```
  Clear the fakes (`stubenv.clear_fake_ai()`) and reset the provider cool-offs in a `finally`, as `plans_insight_checks.reset_ai` does.
- [ ] **Step 2: Run the harness `test_plans` command.** Expected: an ImportError on `custom_insights_service`, reported as `[BUG]`.
- [ ] **Step 3: Implement** the Interfaces above. Restart the stub server (scheduler and stubenv changed).
- [ ] **Step 4: Run it again** and expect no `[BUG]` lines, `plans_insight_checks` included (weekly and monthly are unchanged).
- [ ] **Step 5: Commit** (`feat(backend): custom insight generation, off-topic refusal and stuck-job sweeper`).

---

### Task 5: HTTP API: create (with the reuse rule and gating), list, open, translate, delete

**Files:**
- Create: `backend/custom_insight_routes.py`
- Modify: `backend/main.py` (`app.include_router(custom_insight_router)`)
- Modify: `backend/notification_service.py` (route error messages, en/my)
- Test: `e2e/plans_custom_insight_checks.py` (add `route_checks`)

**Interfaces:**
- Consumes:
  - From Task 4: `validate_range`, `RangeError`, `compute_figures`, `instruction_key`, `PRESETS`, `MAX_INSTRUCTION_LENGTH`, `MAX_FAILED_ATTEMPTS_PER_DAY`, `attempts_window_start`, `attempts_reset_at`, `start_report`; `tz_utils.day_bounds_utc`, `app_today`.
  - From Task 1: `sql.custom_insights.*`, `transactions_db.changed_since`.
  - `quota.require_unlocked`, `quota.reserve`, `quota.give_back`; `insights_service.translate_insight_to_myanmar`, `InsightAIError`, `is_rate_limit_error`; `utils.get_current_user`. PlanError is rendered by the app-wide handler.
- Produces: `router = APIRouter(prefix="/api/custom-insights", tags=["custom insights"])`. The app (Task 6) builds against these shapes:
  - **Summary** keys: `id, start_date ("YYYY-MM-DD"), end_date, preset (key|null), instruction (str|null), status ("pending"|"ready"|"failed"|"refused"), created_at (ISO UTC), completed_at (ISO|null), has_myanmar (bool)`.
  - **Detail** = the summary plus `content (str|null), content_mm (str|null), figures (the Task 4 figures object|null)`. A stored `content_mm` is always returned, whatever the current plan.
  - Non-plan error body: `{"detail": {"code": str, "message": str (user's language), "resets_at": ISO|null}}`. Codes: `custom_insight_invalid_range` (422), `custom_insight_invalid_instruction` (422), `custom_insight_no_data` (422), `custom_insight_pending` (409), `custom_insight_attempts` (429, `resets_at` = next local midnight), `custom_insight_not_ready` (409). The English messages, from `NOTIFICATION_TRANSLATIONS` (the implementer writes the Myanmar):
    - `custom_insight_range_msg`: "Choose from 7 days to 12 months, ending today or earlier."
    - `custom_insight_instruction_msg`: "Use one ready-made instruction or your own, of at most 300 characters."
    - `custom_insight_no_data_msg`: "There are no transactions in these dates, so there is nothing to report on."
    - `custom_insight_pending_msg`: "Your previous custom insight is still being created. Please wait until it's ready."
    - `custom_insight_attempts_msg`: "Today's limit of 5 custom insights that couldn't be created has been reached. Please try again tomorrow."
    - `custom_insight_not_ready_msg`: "This custom insight isn't ready yet."
  - `POST ""`, with body `{start_date, end_date, preset?, instruction?}` (pydantic, `extra="forbid"`). The checks run in this order:
    1. Strip the instruction; an empty one becomes None. Both preset and instruction given, or an instruction longer than 300 characters → `invalid_instruction`. An unknown preset → pydantic's own 422.
    2. `validate_range(..., app_today())` → `invalid_range`.
    3. `quota.require_unlocked(user, "insight_custom")` → a 403 PlanError.
    4. `compute_figures`. No currencies → `no_data`.
    5. Reuse: a `find_ready_match` result is reused when `changed_since(uid, *day_bounds_utc(s, e), match.created_at)` is False AND `match["figures"] == figures`. Then answer **200** `{"report": detail, "reused": true}`, with no reservation.
    6. `has_pending` → `pending`.
    7. `count_attempts_since(uid, attempts_window_start(now)) >= 5` → `attempts`.
    8. `r = await quota.reserve(user, "insight_custom")`; PlanError 403/429 passes through.
    9. `insert_pending(...)` with `counter_keys = [[f, p, d.isoformat()] for f, p, d in r.keys]`, the figures and the instruction key. If it returns False, `give_back(r)` and answer `pending`.
    10. `r.commit()`, then `start_report(id)`. Answer **202** `{"report": detail, "reused": false}`.
  - `GET ""` → `{"reports": [summary, …]}` (newest first, not deleted, at most 100). It is open to any plan.
  - `GET "/{report_id}"` → detail; another user's report or a deleted one → 404.
  - `POST "/{report_id}/translate"` → detail.
    - 404 when the report is missing. Not `ready` → `not_ready`.
    - When `content_mm` is already stored, return it without reserving anything.
    - Otherwise `quota.reserve(user, "insight_translation")`. A locked plan gives a 403 `plan_feature_locked` with feature `insight_translation`; Free is always locked there.
    - Then `translate_insight_to_myanmar(content, user_id=uid, is_placeholder=False)`, `set_translation`, `commit`. Any failure gives the use back. `InsightAIError` → 429 when `is_rate_limit_error`, else 503, each with a plain-text detail.
  - `DELETE "/{report_id}"` → `{"deleted": true}` when the data layer answers "deleted" or "hidden"; 404 for "missing"; 409 `not_ready` for "pending".

- [ ] **Step 1: Write `route_checks(t, h)`** over HTTP. `wait(h, rid)` polls `GET /api/custom-insights/{rid}` every 0.5 s until the status is not `pending` (60 s timeout).
```python
check(r.status_code == 202 and r.json()["reused"] is False and r.json()["report"]["status"] == "pending" and h.used(pro) == 1,
      "create_pending_counts_one")
check(wait(h, rid)["status"] == "ready" and set(d) == SUMMARY_KEYS | {"content", "content_mm", "figures"}, "create_becomes_ready: detail shape")
check(set(c.get(LIST, headers=ph).json()["reports"][0]) == SUMMARY_KEYS, "list_shape")
check(r2.status_code == 200 and r2.json()["reused"] and r2.json()["report"]["id"] == rid and h.used(pro) == 1 and not calls,
      "reuse_same_range_instruction_ignores_case_and_spaces")       # instruction "  WHERE can I save?  " vs "where can I save?"
check(post_after_new_tx.status_code == 202, "reuse_after_new_transaction_regenerates")
check(post_after_edit.status_code == 202, "reuse_after_edit_regenerates")            # PUT /api/transactions/{id} amount
check(post_after_delete.status_code == 202, "reuse_after_delete_regenerates")        # DELETE a range transaction
check(code(r) == (409, "custom_insight_pending"), "create_while_pending_refused")    # pending row inserted via ci.insert_pending
check(sorted([s1, s2]) == [202, 409] and h.used(u) == 1 and pending_rows(u) == 1, "create_concurrent_one_pending")  # two threads
check(code(post(days=6)) == (422, "custom_insight_invalid_range") and post(days=7).status_code == 202, "range_min_7_days")
check(code(post(start=today.replace(year=today.year - 1), end=today)) == (422, "custom_insight_invalid_range")
      and post(start=today.replace(year=today.year - 1) + timedelta(1), end=today).status_code == 202, "range_max_12_months")
check(code(post(end=today + timedelta(1))) == (422, "custom_insight_invalid_range"), "range_not_in_future")
check(code(post(preset="where_to_save", instruction="x")) == (422, "custom_insight_invalid_instruction")
      and code(post(instruction="က" * 301)) == (422, "custom_insight_invalid_instruction")
      and post(instruction="က" * 300).status_code == 202, "instruction_300_chars_incl_myanmar")
check(post(instruction="   ").json()["report"]["instruction"] is None, "instruction_blank_is_none")
check(code(post_for(empty_user)) == (422, "custom_insight_no_data") and h.used(empty_user) == 0, "no_data_not_counted")
check(plan_error(post_for(plus_user), 403, "plan_feature_locked", "insight_custom")
      and plan_error(post_for(free_user), 403, "plan_feature_locked", "insight_custom"), "free_plus_locked")
check(put_plans(plus counted 3/month) and post_for(plus_user).status_code == 202, "gating_follows_plan_limits")
check(plan_error(post_after_set_used_10, 429, "plan_limit_reached", "insight_custom"), "limit_reached_10")
check(plan_error(post_after_add_cost_3, 429, "plan_cost_cap", "insight_custom"), "cost_cap_applies")
check(code(post_with_5_failed_today) == (429, "custom_insight_attempts") and resets_at == attempts_reset_at(now).isoformat()
      and post_with_4_failed_today.status_code == 202, "attempts_limit_5_per_day")
check(code(post_after_deleting_the_5) == (429, "custom_insight_attempts"), "attempts_survive_delete")
check(refused_via_http["status"] == "refused" and h.used(u) == 0, "off_topic_refused_over_http")   # set_fake_ai(claude="off_topic")
# translation
check(tr.json()["content_mm"] and h.used(pro, feature="insight_translation") == 0 and second_tr_calls == 0, "translate_pro_once")
check(downgraded_free.get(detail).json()["content_mm"] == stored_mm and downgraded_free.get(LIST).status_code == 200,
      "after_downgrade_list_open_and_stored_myanmar_shown")
check(plan_error(free_translate_unstored, 403, "plan_feature_locked", "insight_translation"), "translate_locked_follows_plan")
check(code(translate_pending) == (409, "custom_insight_not_ready"), "translate_not_ready")
# delete
check(delete(ready).json() == {"deleted": True} and c.get(detail_of_ready).status_code == 404, "delete_ready")
check(delete(other_users).status_code == 404 and c.get(other_users_detail).status_code == 404, "other_user_404")
check(delete(pending).status_code == 409, "delete_pending_refused")
```
  Wrap the checks in `try/finally`: `stubenv.clear_fake_ai()`, restore the default plans with `t.default_body()`, and remove the users.
- [ ] **Step 2: Restart the stub server and run the harness `test_plans` command.** Expected: the POSTs answer 404, so `[BUG]` lines appear.
- [ ] **Step 3: Implement** the router, register it in `main.py` and add the translations. Restart the stub server.
- [ ] **Step 4: Run it again** and expect no `[BUG]` lines.
- [ ] **Step 5: Commit** (`feat(backend): custom insights API with reuse, gating and translation`; flag the MM wording).

---

### Task 6: App data layer: model, API, ranges, safe Markdown, provider

**Files:**
- Create: `frontend/lib/models/custom_insight.dart`, `frontend/lib/utils/custom_insight_ranges.dart`, `frontend/lib/utils/safe_markdown.dart`, `frontend/lib/providers/custom_insight_provider.dart`
- Modify: `frontend/lib/services/api_service.dart`, `frontend/lib/models/plan_status.dart`, `frontend/lib/services/notification_event_bus.dart`, `frontend/lib/services/fcm_service.dart`, `frontend/lib/main.dart`, `frontend/lib/services/localization_service.dart` (`planFeature_insight_custom` only)
- Test: `frontend/test/custom_insight_test.dart`

**Interfaces:**
- Consumes: the HTTP API of Task 5 (summary and detail keys, the figures object, the error codes, 200 reused / 202 new); `PlanLimitException.tryParse`; `ApiService.apiError`, `_getHeaders`, `_notifyPlanUsage`; `parseInstantOrNull`.
- Produces (Task 7 builds on these):
  - `PlanFeature.insightCustom = 'insight_custom'`, placed in `PlanFeature.all` right after `insightTranslation`. Strings `planFeature_insight_custom`: 'Custom insights' (en) and 'စိတ်ကြိုက် သုံးသပ်ချက်' (my).
  - `custom_insight.dart`:
    - `enum CustomInsightStatus { pending, ready, failed, refused, unknown }`
    - `class CustomInsightPreset { static const whereToSave = 'where_to_save', comparePrevious = 'compare_previous', biggestChanges = 'biggest_changes', budgetsGoals = 'budgets_goals'; static const all = [...] }`
    - `class CategoryAmount {mainCategory, subCategory, amount}`
    - `class CurrencyFigures {currency, income, spending, net, transactions, topCategories, previousIncome, previousSpending, double? incomeChangePct, double? spendingChangePct}`
    - `class CustomInsightFigures {DateTime previousStart, previousEnd; List<CurrencyFigures> currencies}`
    - `class CustomInsight {id, DateTime startDate, DateTime endDate, String? preset, String? instruction, CustomInsightStatus status, DateTime createdAt, DateTime? completedAt, bool hasMyanmar, String? content, String? contentMm, CustomInsightFigures? figures; factory fromJson; CustomInsight copyWith({String? contentMm, ...})}`. Dates are local date-only `DateTime(y, m, d)`.
    - `class CustomInsightRequest {DateTime startDate, endDate; String? preset; String? instruction; Map<String, dynamic> toJson()}` sends `yyyy-MM-dd`, with a trimmed instruction or none.
    - `class CustomInsightCreateResult {CustomInsight report; bool reused}`
  - `api_service.dart`:
    - `class CustomInsightRequestException extends ApiException { static const invalidRange = 'custom_insight_invalid_range', invalidInstruction = 'custom_insight_invalid_instruction', noData = 'custom_insight_no_data', pending = 'custom_insight_pending', attempts = 'custom_insight_attempts', notReady = 'custom_insight_not_ready'; final String code; final DateTime? resetsAt; static CustomInsightRequestException? tryParse(int statusCode, String body) }`. It parses any `detail.code` that starts with `custom_insight_`.
    - `ApiService.createCustomInsight(CustomInsightRequest) -> Future<CustomInsightCreateResult>` accepts 200 or 202 and calls `_notifyPlanUsage()`.
    - `getCustomInsights() -> Future<List<CustomInsight>>`; `getCustomInsight(String id) -> Future<CustomInsight>`; `translateCustomInsight(String id) -> Future<CustomInsight>` (calls `_notifyPlanUsage()` on success); `deleteCustomInsight(String id) -> Future<void>`.
    - Errors: a plan error becomes a `PlanLimitException`; a custom code becomes a `CustomInsightRequestException`; anything else `apiError`.
  - `custom_insight_ranges.dart`:
    - `const customInsightMinDays = 7`; `const customInstructionMaxLength = 300`.
    - `enum CustomQuickRange { last30Days, last3Months, thisYear }`
    - `class DateRangeChoice {DateTime start, end}`
    - `DateRangeChoice quickRange(CustomQuickRange r, DateTime today)`. last30Days = `today-29 .. today`; last3Months = `DateTime(y, m-3, d+1) .. today`; thisYear = `Jan 1 .. today`.
    - `enum CustomRangeProblem { endBeforeStart, tooShort, tooLong, inFuture }`
    - `CustomRangeProblem? customRangeProblem(DateTime start, DateTime end, DateTime today)` uses the same rules as the server; tooLong means `!end.isBefore(DateTime(start.year + 1, start.month, start.day))`.
  - `safe_markdown.dart`:
    - `bool hasDisallowedMarkdown(String md)` is true for a pipe-table row with its `|---|` separator row, a code fence, an HTML tag or an image `![`.
    - `String markdownToPlainText(String md)` strips heading `#`s, `**`/`__`/`*` emphasis, table pipes and separator rows, code fences and HTML tags, and keeps the line breaks.
  - `NotificationEventBus`: `Stream<void> get onCustomInsightUpdated` and `void notifyCustomInsightUpdated()`. `fcm_service._handleForegroundMessage` calls it for the `custom_insight_ready` and `custom_insight_failed` types, and still shows the local notification.
  - `custom_insight_provider.dart`:
    - `abstract class CustomInsightClient { list(); get(id); create(request); translate(id); delete(id); }` mirrors the ApiService methods; `class ApiCustomInsightClient implements CustomInsightClient`.
    - `class CustomInsightProvider with ChangeNotifier`. Constructor: `CustomInsightProvider({CustomInsightClient? client, Duration pollInterval = const Duration(seconds: 5), VoidCallback? onUsageChanged})`; `onUsageChanged` defaults to `() => ApiService.onPlanUsageChanged?.call()`.
    - Getters: `reports`, `isLoading`, `error`, `hasPending`, `lastErrorCode`, `lastError`, `lastPlanLimit`, `CustomInsight? detail(String id)`.
    - `Future<void> load()`
    - `Future<CustomInsightCreateResult?> create(CustomInsightRequest r)` puts the report at the top of the list and starts polling when it is pending. It returns null on failure, with the failure in `lastErrorCode`/`lastError`/`lastPlanLimit`.
    - `Future<CustomInsight?> open(String id)` caches the detail.
    - `Future<CustomInsight?> translate(String id)`
    - `Future<bool> delete(String id)`
    - `void reset()` (and `dispose`) stops the timer.
    - Polling calls `client.list()` every `pollInterval` while `hasPending`. It stops when nothing is pending, and it calls `onUsageChanged` when a report leaves `pending` as `failed` or `refused`. It listens to `onCustomInsightUpdated` and calls `load()`.
    - It is registered in `main.dart`'s MultiProvider and reset in `_resetUserState`.

- [ ] **Step 1: Write `test/custom_insight_test.dart`**
```dart
test('custom_insight_from_json: detail with figures; unknown status is unknown', () {
  final r = CustomInsight.fromJson(detailJson);          // the Task 5 detail shape
  expect(r.status, CustomInsightStatus.ready);
  expect(r.figures!.currencies.single.spendingChangePct, 150.0);
  expect(r.figures!.currencies.single.incomeChangePct, isNull);
  expect(CustomInsight.fromJson({...detailJson, 'status': 'weird'}).status, CustomInsightStatus.unknown);
});
test('request_to_json: yyyy-MM-dd, trimmed instruction, blank instruction omitted', ...);
test('quick_ranges', () {
  final t = DateTime(2026, 11, 4);
  expect(quickRange(CustomQuickRange.last30Days, t).start, DateTime(2026, 10, 6));
  expect(quickRange(CustomQuickRange.last3Months, t).start, DateTime(2026, 8, 5));
  expect(quickRange(CustomQuickRange.thisYear, t).start, DateTime(2026, 1, 1));
  final jan3 = DateTime(2027, 1, 3);
  final y = quickRange(CustomQuickRange.thisYear, jan3);
  expect(customRangeProblem(y.start, y.end, jan3), CustomRangeProblem.tooShort);
});
test('range_problem_bounds', () {
  final t = DateTime(2026, 11, 4);
  expect(customRangeProblem(DateTime(2026, 10, 30), t, t), CustomRangeProblem.tooShort);   // 6 days
  expect(customRangeProblem(DateTime(2026, 10, 29), t, t), isNull);                        // 7 days
  expect(customRangeProblem(DateTime(2025, 11, 5), t, t), isNull);
  expect(customRangeProblem(DateTime(2025, 11, 4), t, t), CustomRangeProblem.tooLong);
  expect(customRangeProblem(t, t.add(const Duration(days: 7)), t), CustomRangeProblem.inFuture);
});
test('safe_markdown: table → plain text; outline is safe', () {
  expect(hasDisallowedMarkdown('## Summary\n- **Food** up 10%'), isFalse);
  const table = '| a | b |\n|---|---|\n| 1 | 2 |';
  expect(hasDisallowedMarkdown(table), isTrue);
  expect(markdownToPlainText('## Summary\n**Bold** $table'), isNot(contains('|')));
  expect(markdownToPlainText('## Summary\n**Bold**'), 'Summary\nBold');
});
test('request_exception_parse: 409 pending, 429 attempts with resets_at; plan codes are not custom', ...);
test('provider_create_polls_until_ready_and_refreshes_usage_on_refused', () async {
  // FakeClient: create → pending; list → pending, then refused. pollInterval 10 ms.
  // expect hasPending false at the end, usageChangedCalls == 1, reports.first.status refused
});
test('provider_create_error_codes', () async { /* pending → lastErrorCode == CustomInsightRequestException.pending; PlanLimitException → lastPlanLimit */ });
test('provider_delete_and_reset', ...);
test('plan_feature_custom_named_in_both_languages', () {
  expect(PlanFeature.all, contains(PlanFeature.insightCustom));
  // en and my knownPlanFeatureName('insight_custom') non-null
});
```
- [ ] **Step 2: Run it and watch it fail.** `Set-Location C:\projects\Flow\frontend; flutter test test\custom_insight_test.dart`. Expected: compile errors (missing files).
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `flutter test test\custom_insight_test.dart` and then `flutter test`. Expected: all pass. Then run `flutter analyze`; expected: no more than 186 issues.
- [ ] **Step 5: Commit** (`feat(app): custom insight model, API, ranges and provider`).

---

### Task 7: App UI: Custom tab, form, list, report screen, notifications

**Files:**
- Create: `frontend/lib/screens/insights/custom_insights_tab.dart`, `frontend/lib/screens/insights/custom_insight_form.dart`, `frontend/lib/screens/insights/custom_insight_report_screen.dart`, `frontend/lib/widgets/custom_insight_figures.dart`, `frontend/lib/widgets/insight_markdown.dart`
- Modify: `frontend/lib/screens/insights/insights_screen.dart`, `frontend/lib/models/notification.dart`, `frontend/lib/screens/notifications/notifications_screen.dart`, `frontend/lib/services/notification_service.dart`, `frontend/lib/services/fcm_service.dart` (colour), `frontend/lib/services/localization_service.dart`
- Test: `frontend/test/custom_insights_screen_test.dart`

**Interfaces:**
- Consumes:
  - From Task 6: `CustomInsightProvider` (`reports`, `create`, `open`, `translate`, `delete`, `lastErrorCode`, `lastPlanLimit`, `hasPending`), `CustomInsightClient` (for test fakes), `CustomInsight`/`CustomInsightStatus`/`CustomInsightPreset`, `quickRange`/`customRangeProblem`, `hasDisallowedMarkdown`/`markdownToPlainText`, `PlanFeature.insightCustom`.
  - Existing: `PlanUsageLine(feature:)` (gives "8 of 10 left this month"), `showPlanLimitSheet`, `PlanProvider.isLocked(key, whenUnknown:)`, `AuthProvider.isPro/isPaid`, `InsightProvider.setInsightType/insightType`, `Currency` from `models/user.dart` for symbols.
- Produces:
  - Insights screen:
    - `InsightsScreen.customTabArgument = 'custom'`. The `/insights` route opens on the Custom tab when `ModalRoute.of(context)?.settings.arguments == 'custom'`.
    - `_periodToggle` gets a third segment, `ValueKey('insight-type-custom')`, labelled `insightTabCustom`. When `insightType == 'custom'` the body is `CustomInsightsTab()`, and `_fetchInsights` and `_isTypeLocked` do nothing for `'custom'`. `InsightProvider.fetchInsights` is never called with `'custom'`.
  - `insightMarkdownStyle(Color headingColor, Color bodyColor) -> MarkdownStyleSheet` in `widgets/insight_markdown.dart`: `_reportMarkdownStyle` moved there, and the Insights screen uses it.
  - `CustomInsightsTab` (keys: `custom-insight-locked`, `custom-insight-upgrade`, `custom-insight-new`, `custom-insight-item-<id>`, `custom-insight-status-<id>`):
    - Locked = `PlanProvider.isLocked(PlanFeature.insightCustom, whenUnknown: !auth.isPro)`.
    - Locked with no past reports: only the locked card, with an Upgrade button that opens `/subscription`.
    - Locked with past reports: the locked card, then the list (open and delete still work).
    - Unlocked: `PlanUsageLine(feature: PlanFeature.insightCustom)`, the "New custom insight" button and the list.
    - Each list item shows the range, the instruction (the preset label, or the text, or `customInsightFullInsight`) and the status line. A refused item reads exactly `customStatusRefused`.
  - `Future<void> showCustomInsightForm(BuildContext context)` (keys: `custom-range-last30Days`, `custom-range-last3Months`, `custom-range-thisYear`, `custom-range-pick`, `custom-preset-<key>`, `custom-instruction-field`, `custom-insight-create`):
    - Quick-range chips (a chip whose range has a `customRangeProblem` is disabled), plus a `showDateRangePicker` (last date today).
    - The instruction field (`maxLength: 300`) and preset chips; picking a chip clears the text and typing clears the chip.
    - `PlanUsageLine` for insight_custom. Create is disabled while the range has a problem.
    - On create: `reused` shows the snackbar `customInsightReused` and opens the report. A new pending report shows `customInsightCreating`. `lastPlanLimit` opens `showPlanLimitSheet`. `lastErrorCode` shows the string mapped to that code (fallback: the server message).
  - `CustomInsightReportScreen({required String reportId})` (keys: `custom-report-body`, `custom-figures-<currency>`, `custom-lang-en`, `custom-lang-mm`, `custom-report-deleted`, `custom-report-delete`):
    - It loads the report via `provider.open(id)`. A 404 shows `customReportDeleted`.
    - Then: a header with the range and instruction; `CustomInsightFigureCards(figures)` (per currency: income, spending, net, change vs the previous period; null shows `customReportNoPrevious`; up to 5 top categories); then the body. The body is a `MarkdownBody` with `insightMarkdownStyle`, or a `SelectableText(markdownToPlainText(content))` when `hasDisallowedMarkdown`.
    - The EN/MM toggle starts on English and never translates on open. MM shows a stored `contentMm` at once, whatever the plan. Without one: when translation is locked (`!auth.isPaid || PlanProvider.isLocked(PlanFeature.insightTranslation)`), MM carries a lock and opens `/subscription`; otherwise MM calls `provider.translate(id)`, with `lastPlanLimit` opening `showPlanLimitSheet` and any other failure a snackbar.
    - A delete action asks `customInsightDeleteConfirm`.
  - Notifications:
    - `NotificationType.custom_insight_ready` and `custom_insight_failed`, each with `// ignore: constant_identifier_names`.
    - Every exhaustive switch (notifications_screen icon and colour, `services/notification_service.dart` colour) handles both: `Icons.auto_awesome_rounded`; ready `scheme.primary`, failed `scheme.onSurfaceVariant`.
    - Tap on ready with a `goalId`: `Navigator.push(MaterialPageRoute(builder: (_) => CustomInsightReportScreen(reportId: goalId)))`. Tap on failed: `Navigator.pushNamed(context, '/insights', arguments: InsightsScreen.customTabArgument)`.
  - Strings (en exact; the implementer writes the Myanmar):
    - Tab and locked card: `insightTabCustom` 'Custom'; `customInsightNew` 'New custom insight'; `customInsightLockedTitle` 'Custom insights come with Pro'; `customInsightLockedBody` 'Pick any dates, ask a question about them, and get a saved report about your own money.'; `customInsightUpgrade` 'Upgrade to Pro'.
    - Form: `customRangeLast30Days` 'Last 30 days'; `customRangeLast3Months` 'Last 3 months'; `customRangeThisYear` 'This year so far'; `customRangePick` 'Choose dates'; `customInstructionLabel` 'What would you like to know? (optional)'; `customInstructionHint` 'For example: where can I cut spending?'; `customPresetWhereToSave` 'Where can I save?'; `customPresetComparePrevious` 'Compare with the previous period'; `customPresetBiggestChanges` 'Biggest changes'; `customPresetBudgetsGoals` 'Check my budgets and goals'; `customInsightCreate` 'Create insight'; `customInsightCreating` "Creating your insight. We'll let you know when it's ready."; `customInsightReused` 'You already have this insight, so here is the saved one.'
    - Range problems: `customRangeTooShort` 'Choose at least 7 days.'; `customRangeTooLong` 'Choose at most 12 months.'; `customRangeInFuture` "The dates can't be in the future."; `customRangeEndBeforeStart` 'The end date is before the start date.'
    - Statuses: `customStatusPending` 'Being created…'; `customStatusFailed` "Couldn't be created. It wasn't counted."; `customStatusRefused` "That isn't something I can answer from your finances".
    - Error codes: `customErrorPending` 'Your previous custom insight is still being created.'; `customErrorAttempts` 'Too many custom insights could not be created today. Please try again tomorrow.'; `customErrorNoData` 'There are no transactions in these dates.'
    - Report: `customInsightFullInsight` 'Full insight'; `customReportIncome` 'Income'; `customReportSpending` 'Spending'; `customReportNet` 'Net'; `customReportVsPrevious` 'vs the previous period'; `customReportNoPrevious` 'Nothing to compare with'; `customReportTopSpending` 'Top spending'; `customReportDeleted` 'This custom insight was deleted.'; `customInsightDelete` 'Delete'; `customInsightDeleteConfirm` 'Delete this custom insight?'; `customInsightEmptyList` 'No custom insights yet.'

- [ ] **Step 1: Write `test/custom_insights_screen_test.dart`.** Use a `FakeCustomInsightClient`, a `PlanProvider(loader: …)` with the chosen insight_custom/insight_translation modes, and an `AuthProvider` stub as in `test/plan_provider_test.dart`.
```dart
testWidgets('locked_plus_no_reports: only the locked card with Upgrade', ...);          // find.byKey('custom-insight-upgrade'), no items
testWidgets('locked_with_past_reports: locked card and the list', ...);
testWidgets('pro_tab_usage_and_form: "8 of 10 left this month", preset chip sends where_to_save', ...);  // fake.lastRequest.preset
testWidgets('form_disables_create_for_short_range_and_thisYear_in_early_january', ...);
testWidgets('list_status_lines: refused reads the exact refusal sentence; failed says not counted', ...);
testWidgets('report_figures_and_markdown: custom-figures-usd shows 250.00 spending; MarkdownBody shown', ...);
testWidgets('report_table_shown_as_plain_text: no MarkdownBody, no "|" in the text', ...);
testWidgets('report_myanmar_stored_shown_without_translate_call', ...);                 // fake.translateCalls == 0
testWidgets('report_myanmar_locked_opens_upgrade', ...);                                 // lock icon under custom-lang-mm
testWidgets('report_screen_deleted_state', ...);                                         // get throws ApiException(statusCode: 404)
testWidgets('insights_screen_custom_tab: third segment shows CustomInsightsTab; InsightProvider fetcher never gets "custom"', ...);
test('notification_types_parse: custom_insight_ready / custom_insight_failed', ...);
```
- [ ] **Step 2: Run it and watch it fail.** `flutter test test\custom_insights_screen_test.dart`. Expected: compile errors.
- [ ] **Step 3: Implement** the Interfaces above.
- [ ] **Step 4: Run** `flutter test`. Expected: all pass. Then `flutter analyze`; expected: no more than 186 issues.
- [ ] **Step 5: Commit** (`feat(app): Custom insights tab, form, report screen and notifications`; flag the MM wording).

---

### Task 8: End-to-end flows, full regression and deploy notes

**Files:**
- Modify: `frontend/integration_test/flows/ai_flows.dart` (two tests in group `09 Insights`)
- Modify: `docs/postgres-migration-plan.md` (new section `### Custom insights`, after "Plans and quotas")

**Interfaces:**
- Consumes:
  - Widget keys from Task 7: `insight-type-custom`, `custom-insight-new`, `custom-range-last30Days`, `custom-preset-where_to_save`, `custom-insight-create`, `custom-insight-item-<id>`, `custom-figures-usd`, `custom-report-body`, `custom-insight-upgrade`.
  - From Task 6: `CustomInsightProvider` (find it with `Provider.of` on the `InsightsScreen` element, as `insightProvider()` does) and `PlanFeature.insightCustom`.
  - Seeded accounts in `support/accounts.dart`: `pro` (its Advanced allowance is used up later, in group 10; insight_custom is separate) and `plus`. Don't use `free` (Felix) after group 12.
- Produces: no code interfaces.

- [ ] **Step 1: Add the flows.**
  - `custom_insights_pro: Pro creates a custom insight from a ready-made instruction, reads figures and text, the same request shows the saved one`:
    1. `login(pro)`, then Insights, then tap `insight-type-custom`.
    2. Check `usageText('insight_custom') == L.planUsageLeftMonth(10, 10)`.
    3. Tap New, Last 30 days, the `where_to_save` chip, then Create. Poll the provider until the report is `ready` (90 s).
    4. Check `usageText == L.planUsageLeftMonth(9, 10)`. Open the item; expect `custom-figures-usd` and the text 'Fake answer'.
    5. Go back and repeat the same request. Expect `L.customInsightReused` and the usage still at 9 of 10.
    6. Open Notifications and tap the first `find.textContaining('Your custom insight is ready')` (the server's English title). Expect `CustomInsightReportScreen`.
  - `custom_insights_locked_plus: Plus sees Custom locked and Upgrade opens the Upgrade screen`: `login(plus)`, then the Custom tab. Expect `custom-insight-upgrade`; tapping it shows `SubscriptionScreen`.
- [ ] **Step 2: Run the group.** `.\e2e\run_e2e.ps1 -Python $py -PgBin <pg bin> -Name "^09 Insights "`. Expected: all tests in group 09 pass. If no emulator or AVD is available, say so in the report and don't claim the flows passed.
- [ ] **Step 3: Write the deploy notes**, in the style of "Plans and quotas":
  - Migration `b8f4d2c6e9a1` (`backend/alembic/versions/20261104_b8f4d2c6e9a1_custom_insights.py`), applied by the Pre-Deploy `alembic upgrade head`. It adds the `custom_insights` table and seeds `insight_custom` (Free and Plus locked, Pro 10 a month).
  - The AI feature **Custom insight** defaults to Claude `claude-sonnet-5-5`, so `ANTHROPIC_API_KEY` is needed, or another provider chosen.
  - The usage type `custom_insight` appears in AI Usage & Costs.
  - The 5-minute sweeper fails reports still pending after 20 minutes and gives their use back.
  - Failed and refused attempts are limited to 5 a day.
  - Rollback: `alembic downgrade a7d3e5c91f20` drops the table and the limits. `ai_usage` rows of type `custom_insight` stay, and older code cannot read them on the per-user usage detail.
  - Manual checks after the deploy: create one report on a Pro test account, confirm the notification, the Myanmar toggle and the count on the user's detail panel. Then confirm that a Plus account sees the locked tab.
- [ ] **Step 4: Run the full regression.** Every command must meet its expectation:
  - `& $py C:\projects\Flow\e2e\run_backend_suite.py` → `== problems (0) ==` and `== crashes (0) ==`; `test_plans` is still the last suite.
  - `Set-Location C:\projects\Flow\frontend; flutter analyze` → no more than 186 issues; `flutter test` → all pass.
  - `Set-Location C:\projects\Flow\admin; npm run lint; npm run build` → clean.
- [ ] **Step 5: Commit** (`test(e2e): custom insights flows; docs: custom insights deploy notes`).

---

## Self-review

1. **Spec coverage.** Every requirement in the spec has a task:
   - Pro only, with Free and Plus locked behind Upgrade: T1, T5 (`free_plus_locked`), T7 (locked states).
   - Gating follows the plan limits: T5 `gating_follows_plan_limits`.
   - Date range plus an optional instruction of at most 300 characters, or a preset; no instruction gives the full insight: T4 (prompt and context), T5 (validation), T7 (form).
   - Range of 7 days to 12 months: T4 `validate_range`, T5, T6.
   - Allowance of 10 a month, editable on the admin Plans page: T1, T2 labels.
   - Cost cap: T5 `cost_cap_applies`.
   - Finance only, with off-topic answers refused and not counted: T4, T5.
   - Background generation with notifications: T3, T4, T7.
   - Saved list, with the toggle and translation stored with the report: T5, T7.
   - Same request again shows the saved report: T5 reuse checks.
   - Advanced model by default, changeable on AI Providers: T2.
   - Fixed outline, no tables, length limit: T4 prompt; T7 plain-text fallback.
   - Figures computed by the app, shown as cards and given to the AI: T4 `figures_computed_from_data` and `run_report_context`; T7 cards.
   - Storage columns, deleted with the user, users can delete: T1.
   - One pending report at a time: T1 index, T5.
   - Stuck jobs: T4.
   - After a plan change: T4 `run_report_finishes_after_plan_change`; T5 `after_downgrade_*` and `translate_locked_follows_plan`; T7 locked-with-reports.
   - At most 5 non-counting attempts a day: T5.
   - Plan comparison and usage lines: T6 `PlanFeature.all` (the comparison table is built from it) and T7 `PlanUsageLine`.
   - AI usage stats: T2.
   - Weekly and monthly unchanged: T4 Step 4 keeps `plans_insight_checks` green.
   - Deploy notes: T8.
2. **Step scan.** Each code step names its file, its signatures and the fixed values. Function bodies appear only as the ordered POST algorithm and the `run_report` ownership rule, which the tests don't determine on their own.
3. **Type consistency.** These names are used the same way everywhere:
   - `counter_keys` (`[[feature, period, "YYYY-MM-DD"]]`): T1 / T4 / T5.
   - The figures keys: T4 / T5 / T6 `CurrencyFigures`.
   - The error codes: T5 / T6 `CustomInsightRequestException`.
   - `instruction_key`: T4 / T5.
   - `goal_id` = report id: T3 / T7.
   - The widget keys: T7 / T8.
   - `insight_custom` (quota and AI feature) vs `custom_insight` (usage type): T1 / T2.
4. **Review Focus.** Each of the five has its test in the owning task: `reuse_after_delete_regenerates` and `create_concurrent_one_pending` (T5), `sweeper_then_late_finish_no_double_give_back` (T4), `attempts_survive_delete` (T5), `report_screen_deleted_state` (T7).
5. **Proportion.** The plan gives signatures, values and assertions; there are no function bodies beyond the two ordered algorithms. The tasks are sized for one reviewer gate each.
