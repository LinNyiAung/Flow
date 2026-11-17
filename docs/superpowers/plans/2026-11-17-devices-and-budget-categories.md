# Devices, Budget Categories and Sign-in Renewal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three changes:
- Budget lines store main and sub category in separate columns.
- Push tokens live in a `user_devices` table, so every signed-in device gets notifications. Expired sign-ins get one reminder instead.
- Using the app renews the sign-in.

**Architecture:**
- **Budget categories:** one migration splits `budget_allocations.main_category` into main + `sub_category`. A small helper module gives every reader the same `(main, sub)` key and `"Main - Sub"` display label. The AI keeps answering in the old text shape and is split at parse time.
- **Devices:** a second migration adds `user_devices` and drops `users.fcm_token`. A new `sql/devices.py` owns all device reads and writes. A new `firebase_service.send_push` sends to a list of tokens and reports which are dead.
- **Renewal:** a `POST /api/auth/renew-session` endpoint, and the app calls it at most daily.

**Tech Stack:**
- Python 3.12, FastAPI, SQLAlchemy Core + asyncpg, Alembic, PostgreSQL 17 (local e2e cluster), firebase_admin.
- Flutter (Provider).
- Admin React (Vite).
- e2e Python scripts in `e2e/`.

**Spec:** `docs/superpowers/specs/2026-11-17-devices-and-budget-categories-design.md`

**Code map:** `docs/superpowers/plans/2026-11-17-devices-and-budget-categories-codemap.md`. It lists every call site with line numbers. Each task brief points at the map sections it needs.

## Global Constraints

**Budget lines**
- `main_category` holds only the main category.
- `sub_category` is NULL for a main-only line, never `""`.
- A request whose `main_category` contains `" - "` gets 422.
- A blank `sub_category` is stored as NULL.
- There is no new category validation on budget create or update.

**Budget migration**
- Upgrade splits on the **first** `" - "`: main = text before it, sub = text after.
- Downgrade rejoins as `main || ' - ' || sub` and drops the column.

**Budget behaviour that must not change**
- A main-only line counts every transaction of that main.
- A sub line counts only transactions with that main and that sub.
- A transaction matching both a main line and its sub line adds to the budget total once.
- A sub line's allocation counts toward the default total only if its main has no line of its own.
- Alert texts read exactly as today, with a sub line named `'Main - Sub'`.

**`user_devices` table**

| Column | Rule |
|---|---|
| `id` | text uuid4, PK |
| `user_id` | FK `users.id` ON DELETE CASCADE, indexed |
| `token` | text NOT NULL **unique** |
| `created_at` | |
| `last_seen_at` | |
| `session_expires_at` | NOT NULL |
| `sign_in_reminder_sent_at` | NULL |

**Device migration**
- `users.fcm_token` and `uq_users_fcm_token` are dropped.
- Upgrade gives one row per non-NULL token, with `last_seen_at` = now and `session_expires_at` = now + 30 days.
- Downgrade puts each user's most recently seen token back.

**Registering a device**
- If the token belongs to another account, move it to the caller.
- If `previous_token` names a row of the caller, that row takes the new token.
- Every registration sets `last_seen_at` = now, `session_expires_at` = the request token's `exp`, and `sign_in_reminder_sent_at` = NULL.

**Logout**
- `DELETE /api/auth/fcm-token` takes JSON `{"fcm_token": "..."}`.
- It removes that row only if it is the caller's, and answers 200 either way.
- A missing or blank token gets 422.

**Sending**
- Every person-targeted push and silent data message goes to every device of that person whose `session_expires_at` > now.
- Broadcasts go to the active devices of every targeted person.
- A token Firebase reports as unregistered has its row deleted. Other errors keep the row.

**Password**
- A password reset deletes every device row of that person.
- A password change deletes every row except the one whose token is sent in the change-password body as `fcm_token`. With no token sent, it deletes every row.

**Sign-in reminder**
- An hourly job finds devices with `session_expires_at` <= now and `sign_in_reminder_sent_at` NULL.
- It sends one push and stamps the row. Push data is `{"type": "sign_in_reminder"}`, with no amounts, names or ids.
- English text: title `Sign in to Toe Pwar`, body `You've been signed out. Sign in to keep getting your budget and goal alerts.`
- Myanmar text exists too and is flagged for native review.
- No in-app notification row.

**Stale devices**
- A daily job deletes rows whose `last_seen_at` is older than **60 days**.

**Renewal**
- `POST /api/auth/renew-session` returns `{"access_token", "token_type": "bearer"}`.
- The token is valid for the full `ACCESS_TOKEN_EXPIRE_MINUTES` from now, with the same `uid` and current `pwv`.
- An expired or revoked token gets 401.
- The app renews when its stored token is more than **1 day** old (`iat`), at session restore and when the app returns to the foreground.

**Admin**
- User list and detail show `device_count`.
- Detail lists each device's `created_at` and `last_seen_at`.
- **Tokens never appear in any admin response.**
- "Push enabled" counts people with at least one device row.

**Release and environment**
- No old-app compatibility: the API, the app and the admin panel change together.
- Windows PowerShell only (Git Bash is broken).
- Append to files with `[IO.File]::AppendAllText(path, text, (New-Object Text.UTF8Encoding($false)))`.
- Commits: write the message to a UTF-8 no-BOM file and run `git commit -F`. The message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Local throwaway DB and stub server only; never production or real keys. Never read or print `.env*`. Keep CRLF in CRLF files.

**Commands used throughout:**
- `$PY` = `C:\Users\LINNYI~1\AppData\Local\Temp\claude\C--projects-Flow\88f449c7-2e35-4a07-890d-5a91aa9c3948\scratchpad\venv_final\Scripts\python.exe`
- `$PGBIN` = `...\88f449c7-2e35-4a07-890d-5a91aa9c3948\scratchpad\pg_dl\srv\pgsql\bin`
- Start Postgres if it is down:
  `Start-Process -FilePath "$PGBIN\pg_ctl.exe" -ArgumentList '-D','C:\projects\Flow\e2e\.data\pg','-o','"-p 54329 -c listen_addresses=127.0.0.1 -c timezone=UTC"','-l','C:\projects\Flow\e2e\logs\postgres.log','start' -WindowStyle Hidden`
- `$RUN` = `...\88f449c7-2e35-4a07-890d-5a91aa9c3948\scratchpad\pg\run_suite.ps1`.
  - `& $RUN -NoSuite` resets the DB and starts the stub on 127.0.0.1:8765.
  - `& $RUN` runs the full backend suite. Its output goes to `backend_suite.out` in the 88f449c7 scratchpad.
- One e2e file: `cd C:\projects\Flow\e2e; $env:PYTHONIOENCODING='utf-8'; $env:E2E_FAKE_AI='1'; & $PY -u <file>.py [sections]`. Expected: no `[BUG]` lines, exit 0. Always reset with `-NoSuite` before re-running a file.
- Flutter: `cd C:\projects\Flow\frontend; C:\flutter\bin\flutter.bat test` and `... analyze`.
- Admin: `cd C:\projects\Flow\admin; npm run build`.
- Never report a test result you have not seen in command output.

## Plan decisions

- **P1. The AI's budget output is unchanged.**
  - The prompts, `_BUDGET_JSON_SCHEMA` and `stubenv`'s fake answer keep `"main_category": "Main"` or `"Main - Sub"`.
  - `_valid_budget_categories` splits the text with `split_legacy_label` before validating.
  - Why: the AI works fine with one string; changing the schema would churn the prompts, the e2e schema assertion and the stub for no user gain.
- **P2. One helper module, `backend/budget_categories.py`,** gives every backend reader the same key and label. No other file splits or joins `" - "` (the AI parse goes through `split_legacy_label`).
- **P3. Two migrations,** one per part, chained: Task 1 `d846defddc6e` → budget; Task 4 budget → devices.
- **P4. No red window.** Each task leaves every e2e file it touches green. The full suite runs in Tasks 6 and 9.
- **P5. `send_push` replaces `send_fcm_notification` and `send_fcm_data_message`.**
  - Broadcasts keep `send_fcm_to_multiple`, which now also returns the unregistered tokens.
  - The e2e stub fakes `send_push` and `send_fcm_to_multiple` by name. Its fakes report any token starting with `dead-` as unregistered.
- **P6. The register endpoint reads `exp` through a new dependency,** `utils.get_token_expiry`. `get_current_user` is not changed.

## Review Focus

1. **A budget with a main line and its own sub line** (e.g. Food 300 and Food › Groceries 100). A grocery purchase updates both lines but adds to the budget total once. Pinned in Task 2, `parity`.
2. **Editing a budget that has sub lines.** The edit screen sends every line back; each line keeps its spent amount and alert state, and no "exceeded" alert re-fires. Pinned in Task 1, `api` (`PUT keeps each line's spent`).
3. **One phone, two accounts.** Sign in as A, log out, sign in as B on the same token: A gets nothing on that phone, B gets everything. Pinned in Task 4, `register` (`a token moves to the new account`).
4. **A token refresh while the app was closed.** On the next start the app sends `previous_token`: still one row, and the old token gets nothing. Pinned in Task 4, `register` (backend) and Task 8 (`fcm previous token`).
5. **Renewal racing a logout.** A renewal answer that arrives after logout must not store a token or sign the person back in. Pinned in Task 8 (`late renewal after logout is dropped`).

---

### Task 1: Budget categories: schema, data layer, API

**Files:**
- Create:
  - `backend/budget_categories.py`
  - `backend/alembic/versions/20261117_<rev>_budget_sub_category.py`
  - `e2e/test_budget_categories.py`
- Modify:
  - `backend/sql/tables.py` (`budget_allocations`)
  - `backend/sql/docs.py` (`budget_doc`, `allocation_rows`)
  - `backend/budget_models.py`
  - `backend/budget_routes.py` (`update_budget` previous-line keying, docstring)
  - `e2e/pgcompat.py` (`_insert_allocations` column list)
  - `e2e/run_backend_suite.py` (`SUITES` and `PRINT_ONLY`)
- Code map: §1.1–1.3, §3.

**Interfaces:**
- **Produces** in `backend/budget_categories.py`:
  - `allocation_key(cat: Mapping) -> tuple[str, str | None]`: `(main_category, sub_category or None)`, reading `sub_category` with `.get`.
  - `allocation_label(cat: Mapping) -> str`: `"Main - Sub"` when there is a sub, else `"Main"`.
  - `split_legacy_label(text: str) -> tuple[str, str | None]`: splits on the first `" - "`.
- **Produces:** migration revision id `REV_BUDGET_SUB`. Task 4 chains on it, and the test file holds it as a constant.
- **Produces:** API budget lines `{"main_category", "sub_category", "allocated_amount", ...}`.

- [ ] **Step 1: Write the failing tests** in `e2e/test_budget_categories.py`.
  - Copy `test_books.py`'s section and argv pattern (code map §8).
  - Use two real seeded outflow sub-categories of different mains. `Food & Daily Living` › `Groceries` is one; pick the other from the category seed in `backend/database.py`.
  - **`migration`:**
    1. Downgrade to `d846defddc6e`.
    2. Insert, with raw SQL, a budget with allocation texts `"<Main1> - <Sub1>"` and `"<Main2>"`.
    3. Upgrade to head. Expect `(Main1, Sub1)` and `(Main2, NULL)`, with amounts unchanged.
    4. Downgrade. Expect texts equal to the originals.
    5. Upgrade again.
    6. Finally: upgrade head and clean up.
  - **`api`:**
    - `create keeps sub`: create with lines `{Main1, Sub1, 100}` and `{Main2, null, 50}`. The POST response and a GET both return those `main_category` / `sub_category` values.
    - `old format refused`: `main_category: "Main1 - Sub1"` gets 422, on both create and PUT.
    - `blank sub is null`: `sub_category: ""` is stored and returned as `null`.
    - `GET round-trips`: PUT the exact `category_budgets` array from a GET; expect 200.
    - `PUT keeps each line's spent`:
      1. Seed a budget with lines `{Main1, null}` and `{Main1, Sub1}`.
      2. Set their stored `spent_amount` / `percentage_used` / `is_exceeded` to different values, with raw SQL.
      3. PUT with changed allocations.
      4. Each line still has its own stored spent values (no collision on `main_category`).
- [ ] **Step 2: Run and confirm failure.** `& $RUN -NoSuite`; `test_budget_categories.py migration api`. Expected: `[BUG]` lines (no column, no field).
- [ ] **Step 3: Implement.**
  - The migration (`down_revision = 'd846defddc6e'`). Split with SQL `strpos` / `substr` on the first `' - '`.
  - The table column, and fix the comment.
  - `budget_doc` adds `sub_category`. `allocation_rows` writes `cat.get("sub_category") or None`.
  - `CategoryBudget.sub_category: Optional[str] = None`. On `CategoryBudgetIn` add validators: `" - "` in main is a `ValueError` (422); a blank sub becomes `None`.
  - `budget_routes.update_budget` keys previous lines with `allocation_key`.
  - pgcompat: add `sub_category` to the INSERT columns and values.
  - Register `test_budget_categories` in both `SUITES` and `PRINT_ONLY`.
- [ ] **Step 4: Run and confirm success.**
  - `test_budget_categories.py migration api`: all `[PASS]`.
  - Then `test_api.py`, `test_round3.py` and `test_books.py migration`. These round-trip budgets and downgrade through the new migration. All must pass.
- [ ] **Step 5: Commit.** `feat(backend): budget lines store the sub-category in its own column`

### Task 2: Budget categories: spending, totals, alerts, AI, rollover

**Files:**
- Modify:
  - `backend/budget_service.py`:
    - `update_budget_spent_amounts`
    - `calculate_total_budget_excluding_subcategories`
    - `_valid_budget_categories`
    - `generate_ai_suggestions` (the total call)
    - `auto_create_next_budget`
    - `_ai_category_budgets` (spending map)
    - `_generate_adjusted_budgets`
  - `backend/notification_service.py`: only if `check_budget_notifications` needs a label parameter. Callers pass `allocation_label(cat)` as `category_name`.
  - `backend/ai_chatbot.py:574-583`, `:794-801`
  - `backend/insights_service.py:639-641`, `:1484-1486`
  - `e2e/test_budget_categories.py`
- Code map: §1.4–1.6, §3 (AI stub and schema notes).

**Interfaces:**
- **Consumes:** Task 1's `allocation_key`, `allocation_label`, `split_legacy_label`.
- **Produces:** unchanged signatures. `calculate_total_budget_excluding_subcategories(category_budgets: List[Dict]) -> float` now reads `sub_category`.

- [ ] **Step 1: Write the failing tests** in section `parity` (needs the stub server).
  - `spent per line`:
    1. Create a budget with lines Main1 300 (no sub), Main1 › Sub1 100, and Main2 › Sub2 50.
    2. Add outflows: Main1/Sub1 40, Main1/<another Main1 sub> 20, Main2/Sub2 10, Main2/<another Main2 sub> 5.
    3. Refresh.
    4. Expect spent: Main1 = 60, Main1›Sub1 = 40, Main2›Sub2 = 10. Expect `total_spent` = 70.
  - `default total`: the same budget created without `total_budget` has `total_budget` = 350 (Main1 300 + Main2›Sub2 50).
  - `sub alert text`:
    1. Push Main1›Sub1 over 100%.
    2. The newest `budget_exceeded` notice message contains `'<Main1> - <Sub1>'`.
    3. It is identical to `translate("budget_exceeded_msg", "en", label="'<Main1> - <Sub1>'", budget_name=...)`. Use the template's real placeholders.
  - `AI answer split`, in-process: `budget_service._parse_budget_answer(<categories>)` on a JSON answer with main_category values:
    - `"<Main1> - <Sub1>"` gives main Main1, sub Sub1;
    - `"food & daily living"` gives main `Food & Daily Living`, sub None;
    - `"Nope"` is dropped;
    - `"<Main1> - Nope"` is dropped.
  - `rollover keeps sub`: `budget_service._generate_adjusted_budgets(parent, 31)` and the non-AI path of `auto_create_next_budget` both keep `sub_category` on the copied lines.
- [ ] **Step 2: Run and confirm failure.** `test_budget_categories.py parity`.
- [ ] **Step 3: Implement.**
  - Key every map on `allocation_key`.
  - Label every printed line with `allocation_label`.
  - Split AI text only in `_valid_budget_categories`, via `split_legacy_label`, before `_append_valid_category`.
  - Prompts and `_BUDGET_JSON_SCHEMA` stay as they are (P1).
  - After this task, no file other than `budget_categories.py` contains `split(" - "` or `f"{...} - {...}"` for categories. Check with Grep.
- [ ] **Step 4: Run and confirm success.**
  - `test_budget_categories.py migration api parity`.
  - `test_ai_providers.py`, `test_jobs.py`, `test_regressions_all.py`, `test_family.py budgets_goals ai`.
  - `test_plans.py`, with `E2E_FAKE_AI=1`.
  - All must pass.
- [ ] **Step 5: Commit.** `refactor(backend): budget spending, totals, alerts and AI use (main, sub) lines`

### Task 3: Budget categories in the app

**Files:**
- Modify:
  - `frontend/lib/models/budget.dart` (`CategoryBudget`)
  - `frontend/lib/screens/budgets/create_budget_screen.dart`
  - `frontend/lib/screens/budgets/edit_budget_screen.dart`
  - `frontend/lib/screens/budgets/budget_detail_screen.dart`
  - `frontend/lib/screens/budgets/ai_budget_suggestion_screen.dart`
- Test:
  - `frontend/test/budget_sub_category_test.dart` (new)
  - `frontend/test/edit_budget_total_test.dart`
- Code map: §2.

**Interfaces:**
- **Consumes:** the API line shape from Task 1.
- **Produces:**
  - `CategoryBudget({required String mainCategory, String? subCategory, ...})`.
  - `String get label`: `"Main - Sub"` or `"Main"`.
  - `fromJson` reads `sub_category`. `toJson` writes `sub_category`, which is null for main-only.

- [ ] **Step 1: Write the failing tests.**
  - `budget_sub_category_test.dart`:
    - `fromJson reads sub_category`, and `toJson writes it` (null for main-only);
    - `label composes Main - Sub`.
  - `edit_budget_total_test.dart`:
    - `edit sends main and sub separately`: open the edit screen with a budget holding `{Main1, Sub1}`, save, and the fake `updateBudget` receives `mainCategory == 'Main1'` and `subCategory == 'Sub1'`;
    - `below-spent check compares main and sub`: lines `{A, null}` and `{A, X}` with different spent values are each matched to their own original.
- [ ] **Step 2: Run and confirm failure.** `flutter test test/budget_sub_category_test.dart test/edit_budget_total_test.dart`.
- [ ] **Step 3: Implement.**
  - Remove every `' - '` split and join in the two budget screens. Use `mainCategory` / `subCategory`.
  - Display uses `label` everywhere. That includes `iconForCategoryName(cat.label)`, so icons stay identical.
  - Duplicate checks and total calculations use the pair.
- [ ] **Step 4: Run and confirm success.** `flutter test` gives "All tests passed!". `flutter analyze` gives 0 errors, 0 warnings, and no new infos in changed files.
- [ ] **Step 5: Commit.** `refactor(app): budget lines carry main and sub category separately`

### Task 4: Devices: table, registration, logout, sending to every device

**Files:**
- Create:
  - `backend/alembic/versions/20261117_<rev>_user_devices.py`
  - `backend/sql/devices.py`
  - `e2e/test_devices.py`
- Modify:
  - `backend/sql/tables.py` (add `user_devices`; drop `fcm_token` and its index)
  - `backend/sql/users.py`: remove `set_device_token` and `clear_device_token`. `HAS_DEVICE` becomes the EXISTS from `sql/devices.py`.
  - `backend/utils.py`: add `get_token_expiry`.
  - `backend/notification_models.py`: `FcmTokenUpdate.previous_token`; new `FcmTokenRemove`.
  - `backend/main.py`: the two endpoints.
  - `backend/firebase_service.py`: add `send_push`; remove `send_fcm_notification` and `send_fcm_data_message`; `send_fcm_to_multiple` also returns `unregistered`.
  - The senders:
    - `notification_service.create_notification`
    - `subscription_service.expire_paid_plans`
    - `admin_routes.update_user_subscription`
    - `admin_routes.broadcast_notification`
  - `e2e/stubenv.py` (fakes per P5); `e2e/pgcompat.py` (add `user_devices` to `TABLES`).
  - Every e2e site that reads or writes `users.fcm_token` (code map §7):
    - `dbtweak.py`
    - `plans_subscription_checks.py:193, :542`
    - `test_api.py:646-656`
    - `test_books.py:1127`
    - `test_family.py:169, :2093-2094`
    - `test_plan_expiry.py:40-118` (monkeypatch the new sender name)
  - `e2e/run_backend_suite.py`: add `test_devices` to `SUITES` and `PRINT_ONLY`.
- Code map: §4.1–4.4, §4.8, §7, §8.

**Interfaces:**
- **Consumes:** `REV_BUDGET_SUB` (the new migration's `down_revision`).
- **Produces** in `backend/sql/devices.py`:
  - `register(user_id: str, token: str, previous_token: str | None, session_expires_at: datetime, now: datetime) -> int`: rows detached from other accounts. Concurrent-safe: unique token, `INSERT ... ON CONFLICT (token) DO UPDATE`.
  - `remove(user_id: str, token: str) -> bool`
  - `remove_all(user_id: str, keep_token: str | None = None) -> int`
  - `active_tokens(user_id: str, now: datetime) -> list[str]`
  - `active_tokens_for(user_ids: Iterable[str], now: datetime) -> list[str]`
  - `delete_tokens(tokens: Iterable[str]) -> int`
  - `HAS_DEVICE` (a SQLAlchemy EXISTS clause on `users.c.id`)
- **Produces** in `backend/utils.py`: `async def get_token_expiry(credentials = Depends(security)) -> datetime`. It decodes with `_decode_user_token`.
- **Produces** in `backend/firebase_service.py`: `send_push(tokens: list[str], title: str | None, body: str | None, data: dict | None) -> dict` with keys `"success"`, `"failure"` and `"unregistered": list[str]`. When `title` is None it is a data-only message, built the way `send_fcm_data_message` was. It is blocking, so call it via `asyncio.to_thread` / `run_in_threadpool`.
  - After every send, callers pass `unregistered` to `devices.delete_tokens`.
  - In `create_notification`, deletion happens back on the event loop: the thread returns the result and an awaited continuation deletes.
- **Produces:** the endpoint contracts in Global Constraints. `previous_token` is optional in `FcmTokenUpdate`. `FcmTokenRemove.fcm_token` is required and non-blank.

- [ ] **Step 1: Write the failing tests** in `e2e/test_devices.py`, copying `test_books.py`'s pattern. A `pushes(token)` helper reads `outbox.jsonl` the same way `test_books` does.
  - **`migration`:**
    1. Downgrade to `REV_BUDGET_SUB`.
    2. Set `users.fcm_token = 'mig-<tag>'` on one user.
    3. Upgrade. Expect exactly one device row with that token, `session_expires_at` within 1 minute of now + 30 days, and `sign_in_reminder_sent_at` NULL.
    4. Downgrade. Expect `users.fcm_token = 'mig-<tag>'`.
    5. Upgrade.
  - **`register`:**
    - `two devices both get pushes`: A registers `a1-<tag>` and `a2-<tag>`; a notice for A produces pushes to both.
    - `a token moves to the new account`: B registers `a1-<tag>`. Then a notice for A reaches only `a2`, and one for B reaches `a1`.
    - `previous token replaces the row`: A registers `a3` with `previous_token = a2`. A has rows {a3}, and `a2` gets nothing.
    - `expiry follows the request token`: the stored `session_expires_at` equals the bearer token's `exp`, and the stamp is NULL after registering.
    - `concurrent same token`: two simultaneous registrations of one token by A give one row.
  - **`logout`:**
    - `DELETE removes only that device`: A deletes `a3`; the other device keeps getting pushes.
    - `another account's token is untouched`: A deletes B's `a1` and gets 200, and the row is still B's.
    - `missing token is 422`: send `{}` and `{"fcm_token": " "}`.
  - **`dead_tokens`:** A registers `dead-<tag>` and `live-<tag>`. A notice for A deletes the `dead-` row and keeps the `live-` row. A broadcast does the same.
  - **`expired_session`:** set one of A's rows to `session_expires_at = now - 1 minute`. A notice for A does not push to it and still pushes to the active one.
- [ ] **Step 2: Run and confirm failure.** `& $RUN -NoSuite`; `test_devices.py migration register logout dead_tokens expired_session`.
- [ ] **Step 3: Implement** per Interfaces and Global Constraints.
  - Senders call `active_tokens` / `active_tokens_for`.
  - `update_user_subscription` keeps its `fcm_refresh_sent` response key: true if at least one device got it.
  - The stub fakes:
    - record one `fcm_send` line per token (keys `token`, `fcm_token`, `title`, `body`, `data`), so the existing `pushes()` helpers keep working;
    - report `dead-*` tokens as unregistered.
- [ ] **Step 4: Run and confirm success.**
  - `test_devices.py` (all sections).
  - `test_api.py`, `test_plan_expiry.py`, `test_books.py notification_links migration`, `test_family.py schema notifications`.
  - `test_plans.py`, with `E2E_FAKE_AI=1`.
  - All must pass.
- [ ] **Step 5: Commit.** `feat(backend): push tokens live in user_devices; every signed-in device gets notifications`

### Task 5: Devices: sign-in reminder, stale clean-up, password changes

**Files:**
- Create: `backend/device_jobs.py`
- Modify:
  - `backend/sql/devices.py`: add `claim_sign_in_reminders` and `delete_stale`.
  - `backend/scheduler.py`
  - `backend/notification_service.py`: add the `NOTIFICATION_TRANSLATIONS` keys `sign_in_reminder_title` / `sign_in_reminder_msg` in `en` and `my`. Push-only, so not in `NOTIFICATION_LINKS`.
  - `backend/auth_routes.py`: reset-password and change-password.
  - `backend/models.py`: `PasswordChange.fcm_token: Optional[str] = None`.
  - `e2e/test_devices.py`
- Code map: §4.4–4.6.

**Interfaces:**
- **Consumes:** Task 4's `sql/devices.py` and `send_push`.
- **Produces:**
  - `devices.claim_sign_in_reminders(now: datetime) -> list[dict]`: rows `{token, user_id, language}`, stamped atomically in the same statement (`UPDATE ... RETURNING`), so two job runs never double-send.
  - `devices.delete_stale(now: datetime, days: int = 60) -> int`
  - `device_jobs.send_sign_in_reminders(now: datetime | None = None) -> int`: pushes sent.
  - `device_jobs.delete_stale_devices(now: datetime | None = None) -> int`
  - Scheduler jobs:
    - `id="sign_in_reminders"`, `CronTrigger(minute=35)`, `misfire_grace_time=3600`, `coalesce=True`
    - `id="stale_devices"`, `CronTrigger(hour=3, minute=15)`, `misfire_grace_time=6*3600`, `coalesce=True`

- [ ] **Step 1: Write the failing tests**, section `reminder` (in-process calls to `device_jobs` against the e2e DB, as `test_plan_expiry` does):
  - `expired device gets one reminder`:
    1. An English user's device has `session_expires_at` in the past.
    2. `send_sign_in_reminders()` returns at least 1.
    3. The push has title `Sign in to Toe Pwar` and body `You've been signed out. Sign in to keep getting your budget and goal alerts.`, and data exactly `{"type": "sign_in_reminder"}`.
    4. No notifications row is created.
  - `Myanmar user gets the Myanmar text`: for a `language='my'` user, the title equals `translate("sign_in_reminder_title", "my")`.
  - `sent once`: a second run sends nothing to that device.
  - `re-register resets`: re-register (stamp cleared, new expiry), then expire it again. The next run sends again.
  - `active device gets none`.
- [ ] Section `stale`: a row with `last_seen_at` 61 days ago is deleted; one at 59 days is kept.
- [ ] Section `password`:
  - `reset removes every device`: after the forgot-password reset flow (use the e2e reset helpers in `test_api.py`), the person has 0 rows.
  - `change keeps the sender's device`: change-password with `fcm_token = d1` leaves rows {d1}.
  - `change without token removes all`.
- [ ] **Step 2: Run and confirm failure.** `test_devices.py reminder stale password`.
- [ ] **Step 3: Implement** per Interfaces. The Myanmar strings are a best-effort translation. Mark them in a comment `# needs native review`.
- [ ] **Step 4: Run and confirm success.** `test_devices.py` (all sections), `test_api.py`.
- [ ] **Step 5: Commit.** `feat(backend): sign-in reminder for expired devices, stale device clean-up, password changes drop devices`

### Task 6: Devices in the admin panel; full backend suite

**Files:**
- Modify:
  - `backend/admin_models.py`: `UserListResponse.device_count: int = 0`. `UserDetailResponse.device_count` and `devices: List[DeviceInfo]`. New `DeviceInfo(created_at, last_seen_at)`.
  - `backend/admin_routes.py`: user list, user detail, broadcast stats.
  - `backend/sql/devices.py`: add `count_for(user_ids) -> dict[str, int]` (one query for the list page) and `list_for(user_id) -> list[dict]`.
  - `admin/src/App.jsx`:
    - user list Activity cell: "N devices";
    - `openUser` fetches `api.getUser` so the modal has detail fields;
    - detail grid: device count, plus a device list showing created and last seen.
  - `e2e/test_devices.py`
- Code map: §4.7, §6.

**Interfaces:**
- **Consumes:** Task 4's `sql/devices.py`.
- **Produces:** admin response fields as above. No token anywhere in them.

- [ ] **Step 1: Write the failing tests**, section `admin`:
  - `list shows device count`: a user with 2 devices shows `device_count == 2` in `GET /api/admin/users?search=<email>`.
  - `detail lists devices without tokens`:
    - `GET /api/admin/users/{id}` has 2 `devices`, each with `created_at` and `last_seen_at`;
    - the raw response text contains neither token string.
  - `push enabled counts people`: `GET /api/admin/broadcast-stats` `users_with_push_enabled` goes up by exactly 1 after a person with 2 devices registers.
- [ ] **Step 2: Run and confirm failure.** `test_devices.py admin`.
- [ ] **Step 3: Implement**, then run `npm run build` in `admin/` (expect success).
- [ ] **Step 4: Full backend suite.**
  1. Recreate `flow_e2e`: `dropdb` / `createdb -h 127.0.0.1 -p 54329 -U flow flow_e2e`.
  2. Run `alembic upgrade head` from `backend` with `$PY`.
  3. Run `& $RUN`, with nothing else touching the DB.

  Expected: `TOTAL` with 0 problems and 0 crashes, and every suite (including `test_budget_categories` and `test_devices`) exits 0. Quote these lines verbatim in the report, from `backend_suite.out`:
  - each suite's exit line;
  - the `TOTAL`, `problems` and `crashes` lines.
- [ ] **Step 5: Commit.** `feat(admin): device counts and device list per user`

### Task 7: Sign-in renewal endpoint

**Files:**
- Modify:
  - `backend/auth_routes.py`: new route.
  - `e2e/test_devices.py`
- Code map: §4.3–4.4.

**Interfaces:**
- **Produces:** `POST /api/auth/renew-session`, `Depends(get_current_user)`. It returns `{"access_token": _issue_token(current_user), "token_type": "bearer"}`.

- [ ] **Step 1: Write the failing tests**, section `renewal`:
  - `renewed token lasts 30 days from now`: decode both tokens with `jwt` and the stub's `SECRET_KEY`. The new `exp` is within 1 minute of now + `ACCESS_TOKEN_EXPIRE_MINUTES`, and later than the old `exp`. `uid` and `pwv` are equal.
  - `renewed token works`: `GET /api/auth/me` with it returns 200.
  - `expired token refused`: a token made with `utils.create_access_token(..., expires_delta=timedelta(seconds=-1))` gets 401.
  - `revoked token refused`: a token issued before a password change gets 401.
- [ ] **Step 2: Run and confirm failure.** `test_devices.py renewal`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run and confirm success.** `test_devices.py renewal`, `test_api.py`.
- [ ] **Step 5: Commit.** `feat(backend): renew-session endpoint`

### Task 8: The app: device registration, logout, change-password, renewal

**Files:**
- Create:
  - `frontend/lib/utils/jwt_claims.dart`
  - `frontend/test/session_renewal_test.dart`
  - `frontend/test/fcm_registration_test.dart`
- Modify:
  - `frontend/lib/services/fcm_service.dart`:
    - remember the last registered token in SharedPreferences, key `fcm_last_registered_token`;
    - send it as `previous_token` when it differs;
    - fix the false comment at :16-17.
  - `frontend/lib/services/api_service.dart`:
    - `updateFCMToken(String fcmToken, {String? previousToken})`;
    - `deleteFCMToken({String? authToken, required String fcmToken})` sends the JSON body;
    - the override becomes `Future<void> Function(String authToken, String fcmToken)?`;
    - new `renewSession()`;
    - `changePassword` sends `fcm_token`.
  - `frontend/lib/providers/auth_provider.dart`:
    - `_unregisterFcm` skips the call and the pending save when `FCMService().fcmToken` is null;
    - `_flushPendingFcmUnregister` passes `pending.fcmToken`, and clears an entry whose `fcmToken` is null;
    - `changePassword` re-registers FCM after success;
    - new `renewSessionIfDue()`.
  - `frontend/lib/main.dart`: an `AppLifecycleListener(onResume: ...)` on mobile calls `renewSessionIfDue()`. The web-only `_refreshOnResume` behaviour is unchanged.
  - `frontend/test/web_platform_test.dart`: gives the Android logout test a push token through a seam, and uses the new override signature.
- Code map: §5.

**Interfaces:**
- **Consumes:** Tasks 4, 5 and 7 endpoints.
- **Produces:**
  - `DateTime? jwtIssuedAt(String token)` in `jwt_claims.dart`. It reads the payload's `iat` without verifying the signature, and returns null on any malformed token.
  - `Future<void> AuthProvider.renewSessionIfDue()`:
    1. Do nothing if there is no token, or if `jwtIssuedAt` is less than 1 day ago.
    2. Call `ApiService.renewSession()`.
    3. Store the new token only if the stored token is still the one that was renewed and no logout happened since. Use the same `_authGeneration` guard as `checkAuthStatus`.
    4. Then call `_registerFcmFor(user.id)`.
    5. On a network or 5xx error, keep the stored token. On 401, use the usual session-expired path.
  - `checkAuthStatus` calls `renewSessionIfDue()` after `/me` succeeds and before `_registerFcmFor`.

- [ ] **Step 1: Write the failing tests.**
  - `session_renewal_test.dart`:
    - `jwtIssuedAt reads iat`, and returns null for garbage;
    - `renews when token is older than a day`: the fake `renewSession` is called once and the new token is stored;
    - `no renewal when token is fresh`;
    - `late renewal after logout is dropped`: start a renewal, log out before it answers, then let it answer. No token is stored and the user stays signed out;
    - `server error keeps the token`.
  - `fcm_registration_test.dart`:
    - `fcm previous token`: after a refresh from `t1` to `t2`, `updateFCMToken` receives `('t2', previousToken: 't1')`;
    - `logout without a push token makes no DELETE and saves no pending retry`;
    - `pending retry sends the stored push token`;
    - `pending entry without a push token is cleared`.
  - `sign_in_reminder opens nothing`: `notificationOpensSomething('sign_in_reminder')` is false. The push only opens the app; no change is needed for the tap.
  - `web_platform_test.dart`: the Android logout test still expects one DELETE, now with the injected push token.
- [ ] **Step 2: Run and confirm failure.** `flutter test test/session_renewal_test.dart test/fcm_registration_test.dart test/web_platform_test.dart`.
- [ ] **Step 3: Implement.** Use test seams in the style of the existing `deleteFcmTokenOverride` / `@visibleForTesting`. Add no new package dependency: decode the payload with `dart:convert` base64Url.
- [ ] **Step 4: Run and confirm success.** `flutter test` gives "All tests passed!". `flutter analyze` gives 0 errors, 0 warnings, and no new infos in changed files.
- [ ] **Step 5: Commit.** `feat(app): every device registers its push token; sign-in renews; logout and password change unregister correctly`

### Task 9: Final verification

**Files:** none, unless a check fails.

- [ ] **Step 1: Full backend suite on a fresh DB**, as in Task 6 Step 4. Quote the verbatim lines.
- [ ] **Step 2:** `flutter test` and `flutter analyze`; `npm run build` in `admin/`.
- [ ] **Step 3: Browser check.**
  1. Build the web app: `flutter build web --release --dart-define=API_BASE_URL=http://127.0.0.1:8765`.
  2. Run `& $RUN -NoSuite`, then `e2e/seed_rich.py`, and serve `build\web` on 8093.
  3. As a seeded user:
     - create a budget with a main line and a sub line of the same main;
     - edit it;
     - check the lines show `Main - Sub` with the same icons as before;
     - add a sub-category expense and check both lines' spent amounts.
  4. Admin panel (dev build with `VITE_API_BASE_URL=http://127.0.0.1:8765`): the user list shows device counts, and the user modal lists devices without tokens. Seed a device first via `POST /api/auth/update-fcm-token`.
  5. Push and renewal can't be exercised on web (FCM is off there). Their tests stand.
- [ ] **Step 4: Clean up.** Stop servers and Postgres, and remove any temporary `.claude/launch.json`.
