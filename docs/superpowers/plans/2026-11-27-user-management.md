# Managing Users from the Admin Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admins can grant upgrade requests in one click, send a reset code, correct a sign-in email, edit name and
currency, sign a person out everywhere, suspend and unsuspend, and message one person; the users list sorts and loads
in a fixed number of queries; admin sign-ins and feedback changes are logged and the Logs tab pages and filters.

**Architecture:** A suspension record on `users` plus one guard (`account_guard.py`) used by sign-in and the token
check; one choke point in `notification_service.create_notification` stops notices to suspended people. Admin actions
on a person live in a new router `backend/user_admin_routes.py`. Plan setting is extracted from
`update_user_subscription` into one function the Users tab and the new Grant button share. The panel gets the actions
in the user modal, a Grant button, and a pageable, filterable Logs tab.

**Tech Stack:** FastAPI + SQLAlchemy Core (asyncpg) on Postgres 16, Alembic; React + Vite admin panel; Flutter app
(test only); e2e tests in `e2e/` against the local stub.

**Spec:** `docs/superpowers/specs/2026-11-27-user-management-design.md` (binding).

## Global Constraints

- No admin ever sets, sees or learns a password or a reset code. No temporary passwords, no impersonation.
- Roles: moderators read only (they see suspension status and reason, not the buttons); admin and super admin do
  every action except the email correction, which is super admin only (`require_super_admin`); the Logs tab stays
  super admin only.
- Suspended sign-in and token refusal: HTTP **423** with body
  `{"detail": {"code": "account_suspended", "message": <translate("account_suspended_msg", person's language)>}}`.
  Never 403 or 401 for a suspension. A wrong password on a suspended account still gets today's 401.
- Texts (both languages, in `NOTIFICATION_TRANSLATIONS`, so they are editable in the Texts tab):
  - `account_suspended_msg`: en "This account is suspended. Please contact us."; my "ဤအကောင့်ကို ရပ်ဆိုင်းထားပါသည်။ ကျွန်ုပ်တို့ထံ ဆက်သွယ်ပေးပါ။"
  - `email_changed_subject`: en "Your Toe Pwar sign-in email was changed"; my "တိုးပွား အကောင့်ဝင်သည့် အီးမေးလ် ပြောင်းလဲထားပါသည်"
  - `email_changed_heading`: en "Sign-in email changed"; my "အကောင့်ဝင်သည့် အီးမေးလ် ပြောင်းလဲပြီး"
  - `email_changed_intro`: en "Our support team changed the email you use to sign in to Toe Pwar. If you asked for this, you don't need to do anything. If you didn't, contact us right away."; my "တိုးပွား အကူအညီအဖွဲ့က သင် အကောင့်ဝင်ရာတွင် သုံးသော အီးမေးလ်ကို ပြောင်းလဲပေးထားပါသည်။ သင်ကိုယ်တိုင် တောင်းဆိုခဲ့ပါက ဘာမှ လုပ်ရန် မလိုပါ။ မတောင်းဆိုခဲ့ပါက ကျွန်ုပ်တို့ထံ ချက်ချင်း ဆက်သွယ်ပါ။"
  - `email_changed_footer`: en "You're getting this because this address was the sign-in email of a Toe Pwar account."; my "ဤလိပ်စာသည် တိုးပွား အကောင့်တစ်ခု၏ အကောင့်ဝင်သည့် အီးမေးလ် ဖြစ်ခဲ့သောကြောင့် ဤအီးမေးလ်ကို ရရှိခြင်း ဖြစ်ပါသည်။"
  - `email_changed_subject` and `email_changed_heading` go in `text_overrides._SINGLE_LINE`. The email never shows the
    new address.
- Suspension reason: required, stripped, 1-500 characters. Stored with `suspended_at` and `suspended_by` (admin id).
- Every admin action on a person is logged with `log_admin_action` (target id and email set) under these action names:
  `user_suspended`, `user_unsuspended`, `user_signed_out`, `user_profile_updated` ("name: a -> b; default_currency:
  x -> y", changed fields only), `user_email_changed` ("old -> new"), `user_reset_code_sent`, `user_message_sent`
  (the title), `upgrade_request_granted` ("plus until 2026-12-27"), and for admins `admin_login`,
  `admin_login_failed`, `admin_locked_out`, `feedback_status_changed` ("pending -> resolved"), `feedback_deleted`.
- Grant length: billing "month" or null = 30 days, "year" = 365 days (the panel's existing day counts). Base = the
  current `subscription_expires_at` when the person's effective plan is paid, not a trial, of rank >= the requested
  plan and that end is in the future; otherwise now.
- AI cost this month in the users list: the sum of `ai_usage.estimated_cost_usd` for the user since the start of the
  current **UTC** calendar month (labelled "AI cost (this month, UTC)" in the panel).
- Every new texts key has both "en" and "my" (test_texts asserts equal key sets). Edit files with Myanmar text only
  with the Edit/Write tools, never PowerShell Get-Content/Set-Content.
- Tests use only the local stub (127.0.0.1:8765, `E2E_FAKE_AI=1`) and the local e2e DB; throwaway admins and users
  are created per test and removed in `finally`. Never read or print `.env` files.
- Before each commit: `git checkout -- frontend/linux frontend/macos frontend/windows`. Commit messages end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; write the message to a file and `git commit -F`.

## Commands

- `$PY` = `C:\Users\LINNYI~1\AppData\Local\Temp\claude\C--projects-Flow\88f449c7-2e35-4a07-890d-5a91aa9c3948\scratchpad\venv_final\Scripts\python.exe`
- `$S` = `C:\Users\LINNYI~1\AppData\Local\Temp\claude\C--projects-Flow\88f449c7-2e35-4a07-890d-5a91aa9c3948\scratchpad`
- Postgres (127.0.0.1:54329) if down — start it detached, never with a piped `pg_ctl`:
  `Start-Process -FilePath "$S\pg_dl\srv\pgsql\bin\pg_ctl.exe" -ArgumentList "-D `"$S\pg_data`" -l `"$S\pg\postgres.log`" -o `"-p 54329 -h 127.0.0.1`" start" -WindowStyle Hidden`,
  then poll `& "$S\pg_dl\srv\pgsql\bin\pg_isready.exe" -h 127.0.0.1 -p 54329` until exit 0.
- Migrate the e2e DB: set `DATABASE_URL` to the flow_e2e URL that `$S\pg\run_suite.ps1` uses for the stub, then
  `Set-Location C:\projects\Flow\backend; & $PY -m alembic upgrade head` (`run_suite.ps1` does not migrate).
  Downgrade check: `alembic downgrade -1` then `upgrade head`.
- Restart the stub (:8765) on current code: `& "$S\pg\run_suite.ps1" -NoSuite`. Needed after any backend change an
  HTTP test exercises.
- One test file: `$env:E2E_FAKE_AI='1'; $env:PYTHONIOENCODING='utf-8'; Set-Location C:\projects\Flow\e2e; & $PY -u test_user_admin.py <sections>`
  (exit 0 and no `[BUG]` = pass). Also `test_sweep.py`, `test_texts.py`, `test_api.py` where a task says so.
- Admin: `Set-Location C:\projects\Flow\admin; npm run lint; npm run build` (baseline: 1 pre-existing lint error in App.jsx).
- App: `Set-Location C:\projects\Flow\frontend; flutter test test/suspended_login_test.dart; flutter analyze` (baseline 166 infos).

## Review Focus

1. **A suspended person who is a family member or owner**: the family book's rollover, repeating entries and
   insights keep working for the other members, while no notice reaches the suspended person (Task 4 test).
2. **An admin correcting an email to one another account uses with different case** (`Bob@x.com` vs `bob@x.com`):
   409 `email_taken`, never a 500 from the unique index (Task 3 test).
3. **Granting a request twice, or after the person cancelled it** (two admins, two tabs): the second grant is a 409
   and the plan is extended once, not twice (Task 5 test).
4. **A reset code asked for by the admin right after the person asked for one themselves**: the panel gets
   `recent` with a retry time; nothing is sent; the person's own flow is unchanged (Task 3 test).
5. **Logs filters with odd input** (`%`, `_`, quotes, 300 characters, an unknown action): no 5xx and no wildcard
   leaks (`%` matches only a literal `%`) (Task 7 test).

---

### Task 1: Suspension record, the guard, and verified-on-reset

**Files:**
- Create: `backend/account_guard.py`, `backend/alembic/versions/20261127_<12hex>_user_admin.py`, `e2e/test_user_admin.py`,
  `frontend/test/suspended_login_test.dart`
- Modify: `backend/sql/tables.py` (users: `suspended_at` TS, `suspended_reason` Text with a CHECK of length <= 500,
  `suspended_by` Text; `admin_action_logs.admin_id` nullable; indexes `ix_admin_action_logs_admin_email_ts`
  (lower(admin_email), timestamp desc), `ix_admin_action_logs_action_ts` (action, timestamp desc)),
  `backend/sql/users.py`, `backend/utils.py` (`get_current_user`), `backend/auth_routes.py` (login, forgot-password
  request, resend verification, reset), `backend/notification_service.py` (texts), `backend/text_overrides.py`
  (`_SINGLE_LINE`), `backend/admin_models.py` (`AdminActionLog.admin_id: Optional[str]`), `e2e/run_backend_suite.py`
  (register `test_user_admin` in SUITES and PRINT_ONLY)

**Interfaces:**
- Produces:
  - `account_guard.SUSPENDED_CODE = "account_suspended"`; `account_guard.is_suspended(user: Mapping) -> bool`;
    `account_guard.suspended_error(user: Mapping) -> HTTPException` (423, the Global Constraints body, the person's
    language via `user_language`).
  - `users_db.suspend(user_id: str, reason: str, admin_id: str, now: datetime) -> bool` (False if already suspended,
    one conditional UPDATE); `users_db.unsuspend(user_id: str) -> bool` (False if not suspended);
    `users_db.sign_out_everywhere(user_id: str) -> None` (bumps `password_version`, sets `password_changed_at` with
    `password_changed_now()`, then `devices_db.remove_all(user_id)`).
  - The texts keys of Global Constraints.
- The migration: head is `c9e3a7d1f4b2`; it mirrors tables.py exactly, and its downgrade drops the columns and
  indexes and makes `admin_id` NOT NULL again after deleting rows whose `admin_id` is null.

- [ ] **Step 1: Write the failing tests** in `e2e/test_user_admin.py` (header, `check`, `_admin`, `_person` helpers as
  in `test_tunables.py`; sections `guard` and `clean`):
  - `guard`: a verified person with a password; suspend them in-process (`users_db.suspend`) then:
    - login with the right password → 423, `detail.code == "account_suspended"`, `detail.message` equals the en text;
      with `language` set to "my" → the Myanmar text;
    - login with a wrong password → 401 "Incorrect email or password";
    - their old token on `GET /api/auth/me` → 401 (signed out by `sign_out_everywhere`, which the test calls as the
      suspend route will);
    - a token issued in-process after suspension (`_issue_token`) on `/api/auth/me` and `/api/auth/renew-session` → 423
      with the same body;
    - `POST /api/auth/forgot-password/request-otp` → 200 with the generic message and no `smtp` line for them in
      outbox.jsonl; the same for resend-verification;
    - `users_db.suspend` a second time → False; `unsuspend` → True, then login → 200; `unsuspend` again → False.
  - `guard` (verified on reset): an unverified person completes request-otp → verify-otp (`latest_otp`) →
    reset-password, then login → 200 and `is_verified` is true in the DB.
  - `clean`: no throwaway users or admins left.
  - Flutter `suspended_login_test.dart`: `ApiService.apiError(http.Response(<423 body>, 423), 'Login failed')`
    has `message == "This account is suspended. Please contact us."` and `code == "account_suspended"`.

- [ ] **Step 2: Run to fail** (`& $PY -u test_user_admin.py guard clean`; the Flutter test passes already if the app
  needs no change — that is the expected result and proves no app release is needed).

- [ ] **Step 3: Implement**: the migration and tables.py; the users helpers; the guard; in `get_current_user` the
  suspension check after the token checks and before the verified check; in `login` after the password check and
  before the verified check; forgot-password request and resend-verification return their generic answer without
  sending for a suspended person; `reset_password_with_token` also sets `is_verified=True` and `verified_at=now`
  (when not already verified); the texts.

- [ ] **Step 4: Migrate the e2e DB, restart the stub, run to pass**: `test_user_admin.py guard clean`, `test_texts.py`,
  `test_api.py`; alembic downgrade -1 and upgrade head both succeed.

- [ ] **Step 5: Commit** — `feat(backend): suspended accounts are refused at sign-in; a completed reset verifies the email`.

### Task 2: Admin actions on a person (suspend, sign out, profile, message)

**Files:**
- Create: `backend/user_admin_routes.py` (router prefix `/api/admin/users`)
- Modify: `backend/main.py` (include the router), `backend/auth_routes.py` (extract the name rule), `backend/admin_routes.py`
  (user detail adds the suspension), `backend/admin_models.py`, `e2e/test_user_admin.py` (section `actions`)

**Interfaces:**
- Consumes: Task 1's `users_db.suspend`, `unsuspend`, `sign_out_everywhere`, `account_guard.is_suspended`.
- Produces (all `require_admin_or_super`, 404 for an unknown user, every success logged per Global Constraints):
  - `POST /api/admin/users/{id}/suspend` body `{"reason": str}` → 200 `{"suspended_at", "suspended_reason"}`; 409
    `{"detail": {"code": "already_suspended", "message"}}`; signs out everywhere.
  - `POST /api/admin/users/{id}/unsuspend` → 200; 409 `not_suspended`.
  - `POST /api/admin/users/{id}/sign-out` → 200 `{"devices_removed": int}`.
  - `PUT /api/admin/users/{id}/profile` body `{"name"?: str, "default_currency"?: Currency}` (extra fields forbidden,
    at least one) → 200 the updated detail; the name follows the app's rule and side effect through
    `auth_routes.apply_profile_name(user_id: str, raw_name: str) -> str` (raises 400 as today; does the update and
    `families_service.follow_profile_name` in one transaction; `update_profile` now calls it). No-change → 200, no log.
  - `POST /api/admin/users/{id}/message` body `{"title", "message", "notification_type": "system_broadcast" |
    "admin_announcement"}` (stripped, not blank, the broadcast lengths) → 200 `{"devices": int}` (pushes that
    succeeded); stored as one notification row like broadcast; 409 `user_suspended` for a suspended person.
  - `GET /api/admin/users/{id}` adds `suspension: null | {"at", "reason", "by_email"}` (by_email null when the admin
    is gone); `UserListResponse` gets `suspended: bool` (Task 6 fills the rest of the list).

- [ ] **Step 1: Write the failing tests** (section `actions`): moderator → 403 on each POST/PUT and sees `suspension`
  in the detail; admin suspend with reason "  spam  " → stored "spam", the person's old token → 401, devices gone,
  log line `user_suspended` with the reason; suspend again → 409; empty reason and 501 characters → 422; unsuspend →
  200 then 409; sign-out → `devices_removed` equals the devices made; profile `{"name": "B"}` → 400, `{"name":
  "Bo Bo"}` → 200 and their family member name follows (a family made in the test), `{"default_currency": "thb"}` →
  200, `{}` → 422, log details `name: <old> -> Bo Bo`; message → a `notifications` row for them with the title, one
  `fcm_send` in outbox.jsonl when they have a device, `{"devices": 1}`; message to a suspended person → 409; unknown
  id → 404 on each.

- [ ] **Step 2: Run to fail**, then **Step 3: Implement**, restart the stub, **Step 4: run to pass**
  (`test_user_admin.py guard actions clean`, `test_sweep.py`, `test_family.py`).

- [ ] **Step 5: Commit** — `feat(backend): suspend, sign out, edit and message a person from the admin API`.

### Task 3: Reset code and email correction

**Files:**
- Modify: `backend/auth_routes.py` (limiter and reset-code issuing), `backend/email_service.py`,
  `backend/user_admin_routes.py`, `e2e/test_user_admin.py` (section `recovery`)

**Interfaces:**
- Produces:
  - `_SlidingWindowRateLimiter.check(key: str, now: float | None = None) -> Optional[float]`: None when allowed (and
    the hit is recorded, as `allow` does), else the seconds until the first full rule frees up (no hit recorded);
    `allow` keeps working (it becomes `check(...) is None`).
  - `auth_routes.issue_reset_code(user: dict) -> ResetCodeResult` where `ResetCodeResult` is a dataclass
    `(sent: bool, reason: Literal["sent", "recent", "hourly_limit", "locked", "suspended"], retry_at: datetime | None)`;
    "recent" when the 60-second rule is the one blocking, "hourly_limit" when only the hour rule is;
    `request_password_reset_otp` uses it and keeps its generic answer; it schedules `send_otp_email` itself through
    a passed `BackgroundTasks`.
  - `email_service.send_email_changed_email(old_email: str, lang: str) -> None` (texts of Global Constraints, `_card`
    layout without a code box).
  - `POST /api/admin/users/{id}/reset-code` (admin or super) → 200 `{"sent": true}` or 409
    `{"detail": {"code": "reset_code_not_sent", "reason", "retry_at", "message"}}`; logged only when sent.
  - `PUT /api/admin/users/{id}/email` (**super admin only**) body `{"email": NormalizedEmail}` → 200 `{"email"}`;
    409 `email_taken` (checked first, and the unique-index IntegrityError also maps to it); same address → 200, no
    change, no log; on change: update, `sign_out_everywhere`, `send_email_changed_email(old, language)` in the
    background (also for a suspended person), log `user_email_changed` "old -> new".

- [ ] **Step 1: Write the failing tests** (section `recovery`): admin reset-code → 200 and one `smtp` line to the person
  whose code `latest_otp` reads and which completes a reset; at once again → 409 `recent` with `retry_at` about 60 s
  ahead; after 5 sends within the hour (simulate by moving the limiter clock in-process or by priming its hits) →
  `hourly_limit`; while `password_reset_locked_until` is ahead → `locked` with that time; suspended → `suspended`;
  the person's own request right after an admin send gets the generic 200 and sends nothing. Email: admin (not super)
  → 403; super with `"  New@Example.COM "` → 200 stored `new@example.com`, old token → 401, an `smtp` line to the OLD
  address whose body has the en intro and not the new address, log `user_email_changed`; another account's address in
  other case → 409 `email_taken`; invalid address → 422; the person can then complete "Forgot password" with the new
  address and sign in (unverified before → verified after).

- [ ] **Step 2: Run to fail**, **Step 3: Implement**, restart, **Step 4: run to pass** (`guard actions recovery clean`,
  `test_api.py`, `test_sweep.py`).

- [ ] **Step 5: Commit** — `feat(backend): admins send reset codes and correct sign-in emails`.

### Task 4: Suspended people get no notices, broadcasts or AI work

**Files:**
- Modify: `backend/notification_service.py` (`create_notification`), `backend/admin_routes.py` (broadcast and
  broadcast-stats), `backend/insights_service.py` (`_skip_user`), `backend/budget_service.py`
  (`_owner_gets_ai_budgets`), `backend/sql/users.py` (a `not_suspended()` condition), `e2e/test_user_admin.py`
  (section `effects`)

**Interfaces:**
- Consumes: Task 1's columns and `is_suspended`.
- Produces: `users_db.not_suspended() -> ColumnElement` (`users.c.suspended_at.is_(None)`), used by broadcast,
  broadcast-stats, and the notification check.
- Rules: `create_notification` stores and pushes nothing when the recipient is suspended (read with the preferences it
  already loads, no extra query when possible); scheduled insights and AI auto-budgets skip a **personal** book whose
  owner is suspended; a family book is never skipped for a suspended owner or member (its other members still get
  their notices). Data jobs are untouched.

- [ ] **Step 1: Write the failing tests** (section `effects`, with `local_jobs`/service calls in-process and a fixed
  `now`, as `test_tunables.py` `times` does):
  - a suspended person with a goal due in 7 days: the goal-reminder handler stores no notification for them; an
    unsuspended twin gets one;
  - trial "ends soon" for a suspended person on trial: no notification;
  - broadcast to "all" → no row for the suspended person; broadcast-stats counts exclude them;
  - weekly insight for a suspended person's personal book: skipped (no insight row, no `ai_usage` row);
  - budget rollover for their personal book still rolls the budget over (data), without AI budgets;
  - a family book owned by a suspended person with one active member: the rollover runs, the active member gets
    `budget_now_active`, the suspended owner gets nothing.

- [ ] **Step 2: Run to fail**, **Step 3: Implement**, restart, **Step 4: run to pass** (`guard actions recovery effects clean`,
  `test_family.py`, `test_plans.py`, `test_calendar_dates.py`).

- [ ] **Step 5: Commit** — `feat(backend): suspended people get no notices, broadcasts or AI work`.

### Task 5: One-click grant

**Files:**
- Modify: `backend/admin_routes.py` (extract plan setting), `backend/plans_admin_routes.py`, `e2e/test_user_admin.py`
  (section `grant`)

**Interfaces:**
- Produces:
  - `admin_routes.apply_plan(admin: dict, user: dict, plan: str, expires_at: datetime | None) -> dict`: the body of
    today's `update_user_subscription` (set plan, close covered requests and log it, notify, silent push, log
    `updated_user_subscription`); `update_user_subscription` calls it; behaviour unchanged.
  - `plans_admin_routes.grant_until(user: dict, plan: str, billing: str | None, now: datetime) -> datetime` (Global
    Constraints rule).
  - `_request_row` adds `grant_until` (ISO) for pending requests.
  - `POST /api/admin/upgrade-requests/{id}/grant` (admin or super) body `{"expires_at"?: datetime}` (default
    `grant_until`; must be in the future, else 422) → 200 the request row (status done); 404 missing; 409 already
    handled (checked with the conditional `mark`, so two grants can't both apply). Logs `upgrade_request_granted`.

- [ ] **Step 1: Write the failing tests** (section `grant`): free person, Plus month request → `grant_until` = now+30 d
  (±1 min), grant → plan plus until then, request done, a `plan_activated` notification, log line; Plus person
  (expires in 10 d) Plus year request → base is their end: +365 d from it; Plus person asking Pro → from now; trial
  person → from now; a custom `expires_at` in the past → 422; granting the same request twice (two calls) → 200 then
  409 and the end date moved once; existing `PUT /users/{id}/subscription` checks in `test_plans.py` still pass.

- [ ] **Step 2: Run to fail**, **Step 3: Implement**, restart, **Step 4: run to pass** (`... grant clean`, `test_plans.py`,
  `test_sweep.py`).

- [ ] **Step 5: Commit** — `feat(backend): grant an upgrade request in one call`.

### Task 6: Users list: sorting, columns, fixed queries

**Files:**
- Modify: `backend/sql/users.py` (`admin_list`), `backend/admin_routes.py` (`get_all_users`), `backend/admin_models.py`,
  `e2e/test_user_admin.py` (section `list`)

**Interfaces:**
- Produces: `GET /api/admin/users` gains `sort: "newest" | "oldest" | "last_active" | "ai_cost"` (default newest) and
  `status: "active" | "suspended"` (optional); each row adds `language`, `ai_cost_month` (float, UTC month),
  `suspended`, keeps every current field with the same meaning. `admin_list` returns rows with the counts, last
  active, device count and AI cost already joined (grouped subqueries), so the route does no per-user query.
  Ties sort by `created_at desc, id`; `last_active` sorts nulls last.

- [ ] **Step 1: Write the failing tests** (section `list`): three throwaway people with known entries, chats and
  `ai_usage` rows (one last month, which doesn't count) — each sort orders them as expected (filter with `search` on
  a test prefix); `status=suspended` returns only the suspended one; the fields match what the detail route says;
  query count: in-process, count statements executed by `get_all_users` (wrap the module's connection execute) for a
  page of 2 and a page of 6 — equal; `sort=bad` → 422.

- [ ] **Step 2: Run to fail**, **Step 3: Implement**, restart, **Step 4: run to pass** (`... list clean`, `test_api.py`,
  `test_sweep.py`).

- [ ] **Step 5: Commit** — `feat(backend): users list sorts, shows activity and AI cost, loads in fixed queries`.

### Task 7: Activity log gaps, paging and filters

**Files:**
- Modify: `backend/admin_routes.py` (login, lockout helpers, feedback routes, logs route), `backend/admin_utils.py`
  (`log_admin_action(admin_id: Optional[str], ...)`), `backend/sql/admins.py` (`list_logs`), `e2e/test_user_admin.py`
  (section `logs`)

**Interfaces:**
- Produces:
  - `_admin_record_failure(key) -> bool` (True exactly when this failure starts the lockout).
  - Login logs `admin_login` on success; `admin_login_failed` (admin_id the admin's or None, admin_email the
    attempted address lower-cased, no password) on a bad password or unknown address; `admin_locked_out` once when
    the lock starts; nothing for attempts refused with 429.
  - Feedback status change logs `feedback_status_changed` ("old -> new", target the feedback's user), only when it
    changed; delete logs `feedback_deleted` (row read first).
  - `admins_db.list_logs(skip, limit, admin_email=None, action=None, user_email=None)`: `admin_email` and `action` are
    exact (admin email case-insensitive); `user_email` is a case-insensitive substring with `%`, `_` and `\` escaped.
  - `GET /api/admin/logs` gains `admin_email`, `action`, `user_email` (max 200 characters) query params;
    `GET /api/admin/logs/filters` → `{"actions": [...distinct], "admin_emails": [...distinct]}` (super admin).

- [ ] **Step 1: Write the failing tests** (section `logs`): a good admin login → `admin_login`; wrong password →
  `admin_login_failed` with no password text in details; an unknown address → a row with `admin_id` null; 5 failures
  → exactly one `admin_locked_out`, and the 6th attempt (429) adds no row; feedback status pending → resolved → one
  line, the same status again → none; delete → `feedback_deleted`; filters: by action, by admin email (other case),
  by user email substring; `user_email="%"` matches no row unless an email contains `%`; 300-character filter → 422;
  paging `skip=1&limit=1` returns the second newest; `/logs/filters` lists the test's actions; moderator and admin →
  403.

- [ ] **Step 2: Run to fail**, **Step 3: Implement**, restart, **Step 4: run to pass** (`... logs clean`, `test_sweep.py`,
  `test_api.py`).

- [ ] **Step 5: Commit** — `feat(backend): log admin sign-ins and feedback changes; logs page and filter`.

### Task 8: Panel: users list and the person's actions

**Files:**
- Create: `admin/src/UserActions.jsx` (the actions block inside the user modal)
- Modify: `admin/src/App.jsx` (Users tab, the modal, its use of ConfirmDialog), `admin/src/api.js`

**Interfaces:**
- Consumes: Tasks 2, 3 and 6 routes.
- Produces: api.js helpers `suspendUser`, `unsuspendUser`, `signOutUser`, `updateUserProfile`, `changeUserEmail`,
  `sendUserResetCode`, `messageUser` (pattern of `updateTunables`); `formatErrorDetail` unwraps an object `detail`
  with a `message` field (so 409 and 423 bodies show their message).
- The Users tab: sort select (Newest joined, Oldest joined, Last active, AI cost this month), a Suspended filter, new
  columns Last active, Language, AI cost (this month, UTC), a "Suspended" badge.
- The modal (writable roles): Suspend (reason box) / Unsuspend, Sign out everywhere, Edit name, Default currency,
  Send reset code (shows "Sent" or the reason with the time), Message (title, message, type), and for super admins
  Correct sign-in email with the reminder "Only do this after checking who you are talking to (recent entries,
  budget names, their plan)." Every action confirms through `ConfirmDialog` with the person's name and email; no
  `window.confirm`/`alert` in the new code. Moderators see the suspension status and reason only.

- [ ] **Step 1: Implement** (no unit tests in the admin app); **Step 2:** `npm run lint` at baseline and `npm run build`
  passes; a render check if available.

- [ ] **Step 3: Commit** — `feat(admin): person actions and a better users list`.

### Task 9: Panel: Grant button and the Logs tab

**Files:**
- Modify: `admin/src/UpgradeRequests.jsx`, `admin/src/App.jsx` (Logs tab), `admin/src/api.js`

**Interfaces:**
- Consumes: Tasks 5 and 7 routes.
- Upgrade Requests: each pending request (writable roles) gets "Grant Plus for 1 month" / "… 1 year" (from billing);
  its ConfirmDialog shows the person, the plan and `grant_until` as a date input the admin may change; on 409 it
  shows the message and reloads.
- Logs tab: filters (Action select and Admin select from `/logs/filters`, a person-email search box), newest first,
  "Older" / "Newer" paging by 50, the target email and details shown; failed sign-ins without an admin show the
  attempted address.

- [ ] **Step 1: Implement**; **Step 2:** lint at baseline and build passes.

- [ ] **Step 3: Commit** — `feat(admin): grant button on upgrade requests; logs page and filter`.

After Task 9 the controller does the browser check of Tasks 8 and 9 against the stub with throwaway admins and
people (every action, a 409, a moderator's view, the Logs filters), then the full backend suite.
