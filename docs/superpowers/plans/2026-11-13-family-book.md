# Family Book Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** households form a family with a shared family book (its own wallet, budgets, goals, insights and Ko Toe Pwar context), with placeholder members, roles, invitations and a Personal / Family switch for the whole app, while every personal book stays strictly private.

**Architecture:**
- **One hidden "book user" per family.** Each family gets a hidden row in `users` (`kind = 'family_book'`). Family transactions, budgets, goals and insights are stored with `user_id = <book user id>`, so every existing per-user query, job and AI context works unchanged on a family book when it is handed the book id.
- **The book is resolved once per request.** A FastAPI dependency `get_book` reads the `X-Book` header (`family` or personal), checks membership, and gives each route the id to query. Routes stop using `current_user["_id"]` for financial data.
- **In the app,** one header added in `ApiService._getHeaders()` switches every call. A `BookModeProvider` holds the mode and resets the per-user providers when it changes.

**Tech stack:**
- FastAPI, SQLAlchemy Core on asyncpg, Alembic, PostgreSQL;
- Flutter with Provider;
- the e2e suite in `e2e/` (stub server and Postgres on port 54329);
- the React admin page in `admin/`.

**Spec:** `docs/superpowers/specs/2026-11-13-family-book-design.md`. Read it first; it is the authority. This plan is how to build it.

## Global Constraints
- **Shell:** use PowerShell; Git Bash is broken. **Never read or print any `.env*` file.** Use only the local throwaway Postgres and the stub server.
- **Tests first:** every behaviour change gets a failing test first.
  - backend: an e2e file in `e2e/`;
  - app: a widget or unit test in `frontend/test/`.
- **Before each commit:**
  - run `flutter analyze` on the touched Dart files (no new issues);
  - run the touched e2e files;
  - at the end of each app task, run the whole `flutter test`.
- **Commits:**
  - small, one per task step group;
  - write the message to a file with `[IO.File]::WriteAllText(path, text, (New-Object Text.UTF8Encoding($false)))`, using LF, then run `git commit -F <file>`;
  - end every message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`;
  - no push or merge.
- **Local environment:**
  - PGBIN = `C:\Users\LINNYI~1\AppData\Local\Temp\claude\C--projects-Flow\88f449c7-2e35-4a07-890d-5a91aa9c3948\scratchpad\pg_dl\srv\pgsql\bin`
  - start Postgres: `Start-Process -FilePath "$PGBIN\pg_ctl.exe" -ArgumentList '-D','C:\projects\Flow\e2e\.data\pg','-o','"-p 54329 -c listen_addresses=127.0.0.1 -c timezone=UTC"','-l','C:\projects\Flow\e2e\logs\postgres.log','start' -WindowStyle Hidden`
  - migrate: `alembic upgrade head` in `backend`, with `DATABASE_URL=postgresql://flow@127.0.0.1:54329/flow_e2e`
  - stub server: `C:\Users\LINNYI~1\AppData\Local\Temp\claude\C--projects-Flow\88f449c7-2e35-4a07-890d-5a91aa9c3948\scratchpad\pg\run_suite.ps1 -NoSuite` (it resets the database)
  - Python: `...\88f449c7-2e35-4a07-890d-5a91aa9c3948\scratchpad\venv_final\Scripts\python.exe`
  - run each e2e file with `PYTHONIOENCODING=utf-8` and `E2E_FAKE_AI=1`
  - afterwards, stop the server on port 8765 and run `pg_ctl … stop -m fast`
- **Strings:** every new string gets an EN entry, an MY entry and a getter in `localization_service.dart`, and backend notification texts go in `NOTIFICATION_TRANSLATIONS` under both `en` and `my`. Write natural, short Myanmar and list every new MY string in the task report.
- **Shared app helpers:** use `formatMoney`, `AppDates`, `AppBarTitle`, `AppBarSaveButton`, `showAppBottomSheet` and `AppListRow`. Check every new screen at 360 px in Myanmar with no overflow, in light and dark.
- **Names and mascot:** the AI helper is "Ko Toe Pwar / ကိုတိုးပွား". The mascot rules are in `frontend/lib/widgets/mascot.dart`:
  - empty states only when there is truly no data;
  - never on sign-in, register or plans.
- **Ids:** `str(uuid.uuid4())`, as elsewhere.
- **Migrations:** chain from head `e5b7c3a9d2f6`, with the file name `YYYYMMDD_<12hex>_<slug>.py`. Name constraints with `op.f(...)`.
- **Spec numbers:** at most **6** account members (owner included) and **20** placeholders; invites expire after **14 days**; creating a family needs **Plus or Pro**; joining is free.

## Review Focus
1. **Reading by id across books:**
   - a personal transaction, budget or goal fetched by its id with `X-Book: family` must return 404;
   - so must another member's personal record fetched by id in either mode.

   The test is in Task 4.
2. **Switching modes mid-request:** if the mode changes while a request is in flight, a late personal response must never fill the family screens, and the reverse. The test is in Task 13.
3. **The owner's plan lapsing during a session:**
   - the next family write gets a clear read-only error (`family_read_only`);
   - the app shows the read-only banner and disables the + button.

   The tests are in Tasks 4 and 13.
4. **Being removed while the app is open:**
   - the next family request answers `no_family`;
   - the app switches back to Personal and says why.

   The tests are in Tasks 4 and 12.
5. **Transfers with currencies:**
   - a transfer in a currency the family hasn't used yet works;
   - MMK amounts stay whole kyat;
   - a transfer larger than the source book's available balance is refused.

   The test is in Task 6.

---

## Plan decisions (beyond the spec)
- **Book user rows:**
  - `kind = 'family_book'`;
  - email `family-<family_id>@book.invalid`;
  - a random unusable password hash;
  - `is_verified = true`, `subscription_type = 'free'`, `language = 'en'`.

  They can never log in, and are excluded from admin user lists and stats, broadcasts, plan expiry and all-user AI jobs (Task 2). Deleting a family deletes its book user, and the FK cascade removes the family's data.
- **The family's own data** has no `user_id` FK to any person. `family_members.user_id` uses `ON DELETE SET NULL`, so a person's account deletion never deletes family history.
- **Transfer balance check:** a transfer is refused when the amount is more than the source book's *available* balance (balance minus money held for goals) in that currency. This is code `transfer_insufficient`.
- **Custom insights in Family mode** are stored under the book, so the family shares the list. They count against the requester's allowance.
- **Family insights** (weekly and monthly) run for families whose owner is on Plus or Pro. They aren't counted against anyone's quota; their AI cost is recorded under the book user.
- **Notifications that belong to a family book** (budget threshold or exceeded, goal achieved or progress, budget started or auto-created) go to every active account member, each in their own language and following their own preferences. Recurring-entry notifications go only to the member who created the recurring entry.

## File structure
**Backend**
- `backend/alembic/versions/20261113_<rev>_family_book.py`: the schema for all of Task 1.
- `backend/sql/families.py`: data access for families, members, invites and beneficiaries.
- `backend/families/__init__.py`, `backend/families/book.py`: `Book` and `get_book` (Task 4).
- `backend/families/service.py`: the family rules (Task 3).
- `backend/families/transfers.py`: Task 6.
- `backend/families/breakdown.py`: Task 5.
- `backend/family_routes.py`: `/api/family/*` and `/api/transfers/*`.
- Changes to the existing route and service files, as each task lists.

**App**
- `frontend/lib/models/family.dart`
- `frontend/lib/providers/book_mode_provider.dart`
- `frontend/lib/providers/family_provider.dart`
- `frontend/lib/screens/family/`:
  - `family_screen.dart`
  - `family_invite_screen.dart`
  - `family_invitations_screen.dart`
  - `family_member_sheet.dart`
  - `transfer_sheet.dart`
- `frontend/lib/widgets/book_switch.dart`
- `frontend/lib/widgets/for_whom_picker.dart`
- `frontend/lib/widgets/read_only_banner.dart`

**Admin:** `admin/src/PlansSettings.jsx`, `admin/src/planLabels.js`.

**e2e:** `e2e/test_family.py`, added to `run_backend_suite.py` `SUITES` and `PRINT_ONLY` before `test_plans`.

---

### Task 1: Schema

**Files:**
- Create: `backend/alembic/versions/20261113_<rev>_family_book.py`
- Modify: `backend/sql/tables.py`
- Modify: `e2e/pgcompat.py` (add the new tables to `TABLES`)
- Test: `e2e/test_family.py` (new; a section "schema")

**Interfaces, produced as columns:**
- `users.kind` Text NOT NULL, server_default `'person'`, CHECK in `('person','family_book')`.
- `families`:
  - `id` Text PK
  - `name` Text NOT NULL
  - `book_user_id` Text NOT NULL UNIQUE, FK `users.id` ON DELETE CASCADE
  - `created_at`, `updated_at` TS
- `family_members`:
  - `id` Text PK
  - `family_id` FK `families` CASCADE
  - `user_id` Text NULL, FK `users` SET NULL
  - `display_name` Text NOT NULL
  - `kind` CHECK in `('account','placeholder')`
  - `role` Text NULL, CHECK in `('owner','admin','member')`; NULL for placeholders
  - `status` CHECK in `('active','former')`, default `'active'`
  - `joined_at`, `left_at` TS
  - partial unique index on `user_id` WHERE `status='active' AND user_id IS NOT NULL` (one family per person)
  - partial unique index on `family_id` WHERE `role='owner' AND status='active'` (one owner)
- `family_invites`:
  - `id` Text PK
  - `family_id` FK CASCADE
  - `email` Text NOT NULL, stored lowercased
  - `invited_by_member_id` FK `family_members` SET NULL
  - `link_member_id` FK `family_members` SET NULL, NULL allowed
  - `status` CHECK in `('pending','accepted','declined','cancelled','expired')`
  - `created_at`, `expires_at` TS
  - partial unique index on `(family_id, email)` WHERE `status='pending'`
- `transactions` gains:
  - `added_by_member_id` Text NULL, FK `family_members` SET NULL
  - `transfer_id` Text NULL, indexed
- `transaction_beneficiaries`:
  - `transaction_id` FK `transactions` CASCADE
  - `member_id` FK `family_members` CASCADE
  - PK on both columns
- `chat_sessions` gains `book_id` Text NULL, FK `users.id` CASCADE (NULL = personal).
- `plan_settings` gains:
  - `family_max_members` SmallInteger NOT NULL, default 0
  - `family_max_placeholders` SmallInteger NOT NULL, default 0
  - CHECK both between 0 and 50
  - seeded: free 0 / 0, plus 6 / 20, pro 6 / 20

The downgrade drops all of this.

- [ ] **Step 1:** In `test_family.py`, write the section "schema". It checks, through `db.sql(...)` against `information_schema`, that every column and table above exists, and that inserting two active owner rows for one family violates the unique index.
- [ ] **Step 2:** Run it against the current head. Expected: `[BUG]` lines.
- [ ] **Step 3:** Write the migration and the `tables.py` definitions, following `20261104_b8f4d2c6e9a1_custom_insights.py` (`op.create_table`, `op.f` names, `postgresql_where` for partial indexes). Add the tables to `pgcompat.TABLES`.
- [ ] **Step 4:** Run `alembic upgrade head`, then `alembic downgrade -1`, then `alembic upgrade head`, then the schema section. Expected: all PASS.
- [ ] **Step 5:** Commit.

### Task 2: Book users are invisible and can't log in

**Files:**
- Modify:
  - `backend/sql/users.py` (add `create_book_user(family_id: str) -> str`, `is_book_user(user_id) -> bool`, and `kind = 'person'` filters in `list_fields`, the admin listing and counting helpers, and `active_paid` / `effectively_free`)
  - `backend/auth_routes.py` (the login and forgot-password paths treat a `family_book` user as not found)
  - `backend/utils.py` (`get_current_user` rejects `kind == 'family_book'` with 401)
  - `backend/admin_routes.py` (user list, detail, stats and broadcast exclude book users)
  - `backend/subscription_service.py` (`expire_paid_plans` skips them)
  - `backend/sql/transactions.py` and `backend/sql/chat.py` (`active_user_ids` joins `users` with `kind='person'`)
- Test: `e2e/test_family.py`, section "book users"

**Interfaces:**
- Produces:
  - `async def create_book_user(family_id: str, *, conn=None) -> str`, which returns the new user id;
  - the invariant that no endpoint or job lists or authenticates a `family_book` user.

- [ ] **Step 1:** Write a failing section that inserts a book user with `create_book_user` and checks:
  - logging in as `family-<id>@book.invalid` with any password → 401;
  - `/api/admin/users` and admin stats don't include it (as a super admin made with `test_plans.make_admins`);
  - the admin broadcast count doesn't include it;
  - `expire_paid_plans` leaves it alone.
- [ ] **Step 2:** Run it. Expected: `[BUG]` lines.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the section, then `test_api.py` on a fresh database. Expected: all PASS, and `test_api` still 242 PASS.
- [ ] **Step 5:** Commit.

### Task 3: Families, members, invitations: rules and API

**Files:**
- Create:
  - `backend/sql/families.py`
  - `backend/families/__init__.py`
  - `backend/families/service.py`
  - `backend/family_routes.py`
- Modify:
  - `backend/main.py` (include the router)
  - `backend/plans/store.py`, `backend/sql/plans.py`, `backend/plans_routes.py` (add `family_limits(plan) -> tuple[int,int]`, loaded from the `plan_settings` columns; `GET /api/plan` returns `family: {max_members, max_placeholders}` for the user's effective plan)
  - `backend/notification_service.py` and `backend/notification_models.py` (types `family_invite`, `family_invite_accepted`, `family_removed`, with EN and MY texts)
- Test: `e2e/test_family.py`, section "family rules"

**Interfaces (produced):** `/api/family`. Responses are JSON. Errors use `{"detail": {"code": ..., "message": ...}}`, with codes `no_family`, `already_in_family`, `not_allowed`, `family_full`, `placeholders_full`, `plan_required`, `invite_invalid`, `owner_must_hand_over`, `confirm_mismatch`.
- `GET /api/family` returns `{"family": null}` when the caller is in no family. Otherwise it returns `{"family": {"id","name","read_only"}, "me": {"member_id","role"}, "members": [{"id","display_name","kind","role","status","is_me"}], "invites": [...pending, admins only], "limits": {"max_members","max_placeholders"}}`.
- `POST /api/family {"name"}`:
  - requires `effective_plan` to be plus or pro (`plan_required`), and the caller to be in no family;
  - creates the family, its book user and the owner member, in one `transaction()`.
- `PATCH /api/family {"name"}`: admins.
- `DELETE /api/family {"confirm_name"}`:
  - owner only; `confirm_name` must equal the family name;
  - deletes the book user (the cascade removes everything).
- `POST /api/family/placeholders {"display_name"}`: admins; ≤ `max_placeholders` active placeholders.
- `PATCH /api/family/members/{id} {"display_name"?, "role"?}`:
  - admins rename;
  - only the owner changes `role` between admin and member;
  - the owner's own role can't be set this way.
- `DELETE /api/family/members/{id}`:
  - admins;
  - an account member becomes former (`left_at`), and is notified with `family_removed`;
  - a placeholder with tagged entries becomes former; without tags it is deleted;
  - the owner can't be removed.
- `POST /api/family/leave`: any member except the owner (`owner_must_hand_over`); the caller becomes former.
- `POST /api/family/transfer-ownership {"member_id"}`: owner only, to an active account member. The old owner becomes admin.
- `POST /api/family/invites {"email", "link_member_id"?}`:
  - admins;
  - the active account members plus pending invites must stay ≤ `max_members` (`family_full`);
  - `link_member_id` must be a placeholder or a former member of this family;
  - expires 14 days after creation;
  - if the email belongs to a person account, notify them with `family_invite`.
- `DELETE /api/family/invites/{id}`: admins; status becomes cancelled.
- `GET /api/family/invites/mine`: the caller's pending, unexpired invites, matched case-insensitively by email.
- `POST /api/family/invites/{id}/accept`:
  - the caller's email must match, the invite must be pending and not expired, and the caller must be in no family (`already_in_family`);
  - if `link_member_id` is set, that member row becomes the caller's account member (kind `account`, role `member`, status `active`, `user_id` = caller), so its tags carry over;
  - otherwise a former member of this family with the same `user_id` is reactivated;
  - otherwise a new member is created;
  - admins are notified with `family_invite_accepted`.
- `POST /api/family/invites/{id}/decline`.
- Expired invites are resolved lazily on every read: status becomes `expired` when `expires_at < now`.

- [ ] **Step 1:** Write the section with these cases (users are made with `plans_entry_checks.register`; plans are set directly in the DB):
  - A Free user's `POST /api/family` → 403 `plan_required`. A Plus user → 200, and they are the owner.
  - The Plus owner invites a Free user, who sees it in `invites/mine`, accepts, and appears as `member`. Joining is free.
  - A member (not admin) trying to invite, add a placeholder, rename or remove → 403 `not_allowed`.
  - The owner makes the member an admin; the admin can invite. The admin trying to change roles → 403.
  - A 7th account member (6 active plus a pending invite) → `family_full`. A 21st placeholder → `placeholders_full`.
  - An invite linked to placeholder "Ma Ma", accepted: the member list has one "Ma Ma" row, now kind account, with the same member id.
  - An invite whose `expires_at` is set in the past → accepting it gives `invite_invalid` and its status reads `expired`. A cancelled invite can't be accepted.
  - A user already in a family accepting another family's invite → `already_in_family`.
  - The owner calling leave → `owner_must_hand_over`. Transfer ownership, then the old owner leaves; they are now former.
  - A former member is invited again and accepts → the same member id is active again.
  - Removing a placeholder with no entries deletes it. Delete with the wrong `confirm_name` → `confirm_mismatch`; with the right one → the book user row is gone.
- [ ] **Step 2:** Run it. Expected: failures.
- [ ] **Step 3:** Implement `sql/families.py` (plain Core queries like `sql/goals.py`), the rules in `families/service.py`, and the thin routes in `family_routes.py`.
- [ ] **Step 4:** Run the section. Expected: all PASS.
- [ ] **Step 5:** Commit.

### Task 4: The book dependency, and every financial route scoped to it

**Files:**
- Create: `backend/families/book.py`
- Modify: every route that reads or writes financial data, replacing the data `user_id` with `book.id`:
  - `backend/main.py`: dashboard balance, chat, chat history, chat refresh-data, insights GET / DELETE / regenerate / translate / generate-weekly, analyze-spending
  - `backend/transaction_routes.py`: all endpoints, including batch-create and the AI extraction endpoints that create entries
  - `backend/budget_routes.py`: all
  - `backend/goal_routes.py`: all
  - `backend/report_routes.py`: all
  - `backend/custom_insight_routes.py`: all
- Test: `e2e/test_family.py`, section "book scope and privacy"

**Interfaces:**
- Produces, in `families/book.py`:
  - `@dataclass(frozen=True) class Book: id: str; kind: Literal["personal","family"]; person: dict; family: dict | None; member: dict | None; read_only: bool`
  - `async def get_book(current_user: dict = Depends(get_current_user), x_book: str | None = Header(None, alias="X-Book")) -> Book`:
    - `x_book in (None, "", "personal")` → personal, with `id = current_user["_id"]`;
    - `"family"` → the caller's active membership, or 409 `no_family`, giving `id = family.book_user_id`;
    - `read_only` is true when the owner's `effective_plan` is not in `PAID_PLANS`.
  - `def require_writable(book: Book) -> None`: 403 `family_read_only` for a read-only family book.
  - `def require_admin(book: Book) -> None`: 403 `not_allowed` unless the role is owner or admin.
  - `def can_change_entry(book: Book, entry: dict) -> bool`:
    - personal: always;
    - family: admins, or `entry["added_by_member_id"] == book.member["id"]`.
- **Quota calls** (`quota.reserve` / `use` / `require_unlocked`) stay on `current_user`, the person. Only the data id changes.
- **AI data staleness** is marked on `book.id`.

- [ ] **Step 1:** Write the section. It creates a family of Mum (owner) and Dad (member), gives each personal entries, a personal budget and a personal goal, and adds family entries. Then it checks:
  - with `X-Book: family`, the lists, balance, budgets, goals, reports and summaries for Mum and Dad are identical, and contain only family records;
  - without the header, each sees only their own personal records;
  - **Review Focus 1:** a GET, PUT or DELETE of Dad's personal transaction, budget or goal id by Mum, in either mode, gives 404; Mum's own personal id with `X-Book: family` gives 404;
  - `X-Book: family` for a user in no family gives 409 `no_family`;
  - **Review Focus 4:** Dad is removed, and his next `X-Book: family` request gives 409 `no_family`;
  - **Review Focus 3:** the owner's `subscription_expires_at` is set in the past, then:
    - a family POST transaction gives 403 `family_read_only`;
    - family GETs still work;
    - personal writes still work.
- [ ] **Step 2:** Run it. Expected: failures.
- [ ] **Step 3:** Implement `book.py`. Then go route by route, adding `book: Book = Depends(get_book)` and calling `require_writable(book)` on every family write. Background tasks such as `update_relevant_budgets` get `book.id`.
- [ ] **Step 4:** Run the section, `test_api.py` (fresh database), `test_goals_summary.py` and `test_ai_providers.py`. Expected: all PASS; the existing suites are unchanged.
- [ ] **Step 5:** Commit.

### Task 5: Who added it, who it was for, and the per-person breakdown

**Files:**
- Create: `backend/families/breakdown.py`
- Modify:
  - `backend/transaction_routes.py`: create, update and batch-create accept `for_whom: list[str] | None`. Entries carry `added_by_member_id`. The response adds `added_by: {"member_id","display_name"} | null` and `for_whom: [member_id…]`, where an empty list means Whole family.
  - `backend/sql/families.py`: `set_beneficiaries(transaction_id, member_ids)` and `beneficiaries_for(transaction_ids) -> dict[str, list[str]]`.
  - `backend/models.py`: the transaction request and response models.
  - `backend/family_routes.py`: `GET /api/family/breakdown`.
- Test: `e2e/test_family.py`, section "entries and breakdown"

**Interfaces:**
- `for_whom` validation:
  - only in a family book (a personal book gives 400);
  - member ids must be **active** members of this family; account or placeholder both allowed;
  - duplicates are removed;
  - `None` or `[]` means Whole family.
- Edit and delete of a family entry: `can_change_entry`, otherwise 403 `not_allowed`.
- `GET /api/family/breakdown?start_date=&end_date=&currency=` returns `{"currency", "total_spent", "rows": [{"member_id": null|id, "display_name": "Whole family"|name, "status": "active"|"former", "amount"}]}`:
  - only outflows, excluding transfers;
  - an entry for n members adds `amount / n` to each;
  - the Whole family row has `member_id null`;
  - rows are sorted by amount, descending;
  - amounts are rounded to the currency's display precision (MMK to whole kyat, others to cents), with the remainder from rounding added to the first member's share so the rows sum to the total.

- [ ] **Step 1:** Failing cases:
  - Mum adds K60,000 for [Ma Ma, Ko Ko] → the breakdown shows Ma Ma 30,000 and Ko Ko 30,000.
  - Whole family K850,000 → its own row.
  - $10.00 for three members → 3.34 / 3.33 / 3.33, summing to 10.00.
  - Dad (member) editing Mum's entry → 403; Dad editing his own entry → 200; an admin editing Dad's entry → 200.
  - `for_whom` with another family's member id, or a former member → 400.
  - Dad leaves → his tagged history still shows with `status: former`.
- [ ] **Step 2:** Run it. Expected: failures.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run it. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 6: Transfers between a personal wallet and the family wallet

**Files:**
- Create: `backend/families/transfers.py`
- Modify:
  - `backend/sql/transactions.py`:
    - `currency_totals` returns per currency `inflow`, `outflow` (both excluding transfers) plus `transfer_in` and `transfer_out`;
    - `category_totals`, `has_transactions_between` and `changed_since` exclude transfers;
    - `find_transactions` gains `include_transfers: bool = True`, which is `False` for reports, insights, budgets, the chat context and the large-transaction profile.
  - `backend/utils.py`: `get_user_balance` balance = `inflow - outflow + transfer_in - transfer_out`, and the returned `total_inflow` / `total_outflow` exclude transfers.
  - `backend/budget_service.py`, `backend/report_routes.py`, `backend/insights_service.py`, `backend/custom_insights_service.py`, `backend/ai_chatbot.py`, `backend/notification_service.py` (`check_large_transaction`, `analyze_unusual_spending`): exclude transfers.
  - `backend/transaction_routes.py`:
    - PUT on a row with `transfer_id` → 400 `transfer_not_editable`;
    - DELETE on such a row → 400 `use_transfer_undo`;
    - list responses include `transfer_id`.
  - `backend/family_routes.py`: the transfer endpoints.
- Test: `e2e/test_family.py`, section "transfers"

**Interfaces (produced):**
- `POST /api/transfers {"direction": "to_family"|"to_personal", "amount", "currency", "date", "description"?}`:
  - the caller must be an active member, and the family not read-only;
  - inside one `transaction()`, holding both books' money locks (`get_user_money_lock` for the person and for the book; take them in sorted id order), it inserts two transactions with the same `transfer_id`:
    - the source book gets an outflow and the destination book an inflow;
    - `main_category "Transfer"`, `sub_category "Family wallet"`;
    - the family-side row has `added_by_member_id` = the caller;
  - it refuses with 400 `transfer_insufficient` when the amount is more than the source book's available balance (`get_user_balance(...)["available_balance"]`) in that currency;
  - it returns `{"transfer_id", "personal_transaction_id", "family_transaction_id"}`.
- `DELETE /api/transfers/{transfer_id}`: only the person who made it (the personal side's `user_id == caller`) → deletes both rows in one `transaction()`. Anyone else gets 403 `not_allowed`, including admins.

- [ ] **Step 1:** Failing cases:
  - Mum moves K100,000 to the family → Mum's balance −100,000 and the family's +100,000, while both books' `total_inflow` and `total_outflow` are unchanged.
  - Neither book's budget spending, reports, categories or the breakdown includes it.
  - Moving $5 into a family with no USD yet works (**Review Focus 5**).
  - Moving more than the available balance → `transfer_insufficient`.
  - Dad takes K20,000 out (`to_personal`) → it shows in the family list with `transfer_id` and `added_by` Dad.
  - Mum (owner) deleting Dad's transfer → 403; Dad deleting it → both rows gone.
  - PUT on a transfer row → 400.
  - An MMK transfer of 1500.4 is stored as given and displays as whole kyat in the app (the amount is round-tripped).
- [ ] **Step 2:** Run it. Expected: failures.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the section, `test_api.py` (fresh database), `test_goals_summary.py`, `test_ai_providers.py` and `test_plans.py`. Expected: all PASS.
- [ ] **Step 5:** Commit.

### Task 7: Family budget and goal permissions

**Files:**
- Modify:
  - `backend/budget_routes.py`: in a family book, create, update, delete, refresh-settings and ai-suggest → `require_admin`.
  - `backend/goal_routes.py`: in a family book, create, update and delete → `require_admin`. `contribute` with amount > 0 → any member; amount < 0 (withdraw) → `require_admin`.
- Test: `e2e/test_family.py`, section "budgets and goals"

- [ ] **Step 1:** Failing cases:
  - a member creating a family budget → 403; an admin → 200;
  - a member adding K20,000 to a family goal → 200, and the family's available balance drops by 20,000;
  - a member withdrawing → 403; an admin withdrawing → 200;
  - personal budgets and goals are unaffected.
- [ ] **Step 2:** Run it. Expected: failures.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run it. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 8: Notifications for family books

**Files:**
- Modify:
  - `backend/notification_service.py`:
    - `create_notification(user_id, ...)` checks whether `user_id` is a book user. If it is, it fans out to every active account member: each member's prefs (`should_send_notification`), language (`get_user_language`) and FCM token are used, and the title and message are re-rendered per language.
    - For this, budget and goal callers pass the translation key and kwargs instead of pre-rendered text. Add `create_notification_from_key(user_id, notification_type, title_key, msg_key, *, goal_id, goal_name, currency, extra, **fmt)` and switch the budget and goal callers to it.
  - `backend/recurring_transaction_service.py`: for a book parent, notify only the member who created it (`added_by_member_id` → its `user_id`). If that member is former, notify nobody.
- Test: `e2e/test_family.py`, section "family notifications"

- [ ] **Step 1:** Failing cases:
  - a family budget crosses 80% → Mum (en) and Dad (my) each get one `budget_threshold` notification in their own language; the book user gets none;
  - a family goal reaches 100% via a contribution → both get `goal_achieved`;
  - a family entry by itself → no notification;
  - Dad turns budget notifications off → only Mum gets them.
- [ ] **Step 2:** Run it. Expected: failures.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the section, then `test_ai_providers.py` and `test_plans.py`. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 9: Ko Toe Pwar and insights for the family book

**Files:**
- Modify:
  - `backend/main.py`:
    - `/api/chat/stream` calls `financial_chatbot.stream_chat(user_id=book.id, ...)`, while quota and cost stay on the person;
    - `save_chat_session` / `sql/chat.py` store and read sessions by `(user_id=person, book_id=None | book.id)`;
    - chat history GET and DELETE filter the same way.
  - `backend/sql/chat.py`: `append_exchange`, `history` and `clear` take `book_id: str | None`.
  - `backend/ai_chatbot.py`:
    - in a family book, the context adds a "FAMILY" section: the member names and this month's per-person breakdown from `families.breakdown`;
    - the prompt says "You are answering about the user's family book (shared household money), not their personal money".
  - `backend/insights_service.py`: weekly and monthly jobs also iterate family books whose owner's `effective_plan` is paid (weekly for plus and pro; monthly for all paid). They generate under `book_user_id` with `notify` fanning out through Task 8, and skip when the owner is over the cost cap.
- Test: `e2e/test_family.py`, section "ai" (with `E2E_FAKE_AI=1`)

- [ ] **Step 1:** Failing cases:
  - The context built in-process with `FinancialDataProcessor(book_id)` contains family entries and none of Mum's personal entries.
  - Mum's family-mode chat history isn't visible to Dad's family-mode history; Mum's personal history isn't in her family-mode history.
  - The weekly job creates one insight under the book user for a Plus owner, and none when the owner is Free.
  - The chat with `X-Book: family` counts against Dad's own chat quota.
- [ ] **Step 2:** Run it. Expected: failures.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the section, then `test_ai_providers.py`. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 10: Family limits on the admin Plans page

**Files:**
- Modify:
  - `backend/plans_admin_routes.py`: `PlanBody` gains `family_max_members: int | None` and `family_max_placeholders: int | None`, plus `_snapshot` and `_changes`.
  - `backend/plans/store.py`: `_validate` checks the range 0–50 and that Free is 0 / 0 or more.
  - `admin/src/PlansSettings.jsx`: two number fields per plan, beside the prices.
  - `admin/src/planLabels.js`: their labels.
- Test: `e2e/test_family.py`, section "limits"

- [ ] **Step 1:** Failing cases:
  - `PUT /api/admin/plans` sets plus `family_max_members` to 4 → `GET /api/plan` for a Plus user reports 4, and a 5th invite → `family_full`;
  - a value of 51 → 422.
- [ ] **Step 2:** Run it. Expected: failures.
- [ ] **Step 3:** Implement. For the admin page, run `npm run build` in `admin/` and check it builds.
- [ ] **Step 4:** Run the section, then `test_plans.py`. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 11: Account deletion keeps family history

**Files:**
- Modify:
  - `backend/families/service.py`: `async def before_account_delete(user_id: str) -> None`:
    - not in a family → nothing;
    - a member → becomes former;
    - the owner → ownership passes to the longest-standing active admin (`joined_at`), otherwise the longest-standing active account member, who becomes owner; if nobody is left, the family is deleted (its book user).
  - `backend/auth_routes.py` (`delete-account`) and `backend/admin_routes.py` (admin delete user) call it before `users_db.delete_user`, in the same `transaction()`.
- Test: `e2e/test_family.py`, section "account deletion"

- [ ] **Step 1:** Failing cases:
  - Dad deletes his account → the family entries he added remain, and `added_by` shows "Dad" as former;
  - the owner (with an admin) deletes → the admin is the owner;
  - the owner (only members left) deletes → the oldest member is the owner;
  - the owner (alone) deletes → the family is gone.
- [ ] **Step 2:** Run it. Expected: failures.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the section, then `test_api.py` (fresh database). Expected: PASS.
- [ ] **Step 5:** Commit, and add `test_family` to `run_backend_suite.py` `SUITES` and `PRINT_ONLY` (before `test_plans`).

---

### Task 12: App foundation: book header, mode, family data

**Files:**
- Create:
  - `frontend/lib/models/family.dart`
  - `frontend/lib/providers/book_mode_provider.dart`
  - `frontend/lib/providers/family_provider.dart`
- Modify:
  - `frontend/lib/services/api_service.dart`:
    - `_getHeaders()` adds `'X-Book': 'family'` when `ApiService.bookMode == BookMode.family`;
    - all family endpoints from Tasks 3, 5 and 6;
    - `ApiException` exposes `code`;
    - the transaction JSON includes `for_whom`.
  - `frontend/lib/models/transaction.dart`: `transferId`, `addedBy` (`FamilyMemberRef?`), `forWhom` (`List<String>`), `bool get isTransfer`.
  - `frontend/lib/models/plan_status.dart`: `familyMaxMembers` and `familyMaxPlaceholders`.
  - `frontend/lib/main.dart`: the providers, the reset on account switch, and loading the mode at start.
- Test:
  - `frontend/test/family_api_test.dart` (MockClient pattern from `test/api_fallback_messages_test.dart`, with one shared MockClient and a swappable responder)
  - `frontend/test/book_mode_provider_test.dart`

**Interfaces (produced):**
- `enum BookMode { personal, family }`.
- `static BookMode ApiService.bookMode = BookMode.personal`.
- `class BookModeProvider with ChangeNotifier`:
  - `static const prefsKey = 'book_mode'`
  - `BookMode mode`
  - `Future<void> load()`
  - `Future<void> setMode(BookMode)`: sets `ApiService.bookMode`, persists it, and calls `onModeChanged`
  - `void reset()`: back to personal, re-read from the device on the next load
  - `VoidCallback? onModeChanged`
- `class FamilyProvider with ChangeNotifier`:
  - `Family? family`, `FamilyMember? me`, `List<FamilyMember> members`, `List<FamilyInvite> invites`, `List<FamilyInvite> myInvites`, `bool readOnly`
  - `bool get isAdmin`, `bool get isOwner`, `bool get inFamily`
  - `Future<void> refresh()`
  - methods mirroring every Task 3 endpoint, each returning `Future<String?>` (null on success, otherwise a localized error)
  - `void reset()`
- Models in `family.dart`:
  - `Family(id, name, readOnly)`
  - `FamilyMember(id, displayName, kind, role, status, isMe)`
  - `FamilyInvite(id, email, linkMemberId, expiresAt, familyName?)`
  - `FamilyMemberRef(memberId, displayName)`
  - `BreakdownRow(memberId, displayName, status, amount)`
- In `main.dart`, `onModeChanged` calls `_resetUserState()` (except `FamilyProvider` and `BookModeProvider`) and the Home key becomes `ValueKey('home-$userId-${mode.name}')`.
- **Review Focus 4:** any `ApiException` with code `no_family` while in family mode makes `BookModeProvider` switch to personal, makes `FamilyProvider` refresh, and shows a snackbar `familyNoLongerMember`.

- [ ] **Step 1:** Failing tests:
  - `X-Book` is absent in personal mode and `family` in family mode, for `getTransactions` and `streamChatMessage`;
  - the mode persists across `load()`;
  - `reset()` returns to personal;
  - a `no_family` response flips the mode to personal.
- [ ] **Step 2:** Run `flutter test test/family_api_test.dart test/book_mode_provider_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run those tests, then the whole `flutter test`. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 13: The Personal / Family switch

**Files:**
- Create:
  - `frontend/lib/widgets/book_switch.dart` (`BookSwitch()`: a two-segment control, Personal and the family name, shown only when `FamilyProvider.inFamily`)
  - `frontend/lib/widgets/read_only_banner.dart` (`ReadOnlyBanner()`: shown in family mode when `readOnly`; text `familyReadOnlyBanner`; an owner gets an Upgrade button to `/subscription`)
- Modify:
  - `frontend/lib/screens/home/home_screen.dart`: `BookSwitch` as the first sliver above the hero; `ReadOnlyBanner` below it; the + button is disabled when read-only.
  - `frontend/lib/widgets/app_drawer.dart`: `BookSwitch` after the profile header (around line 206).
  - The other money screens' app bars show which book is open: transactions, budgets, goals, analytics, reports, insights and chat. In family mode the title is suffixed with " · " plus the family name, through a helper `bookTitle(context, String title)` in `book_switch.dart`.
- Test: `frontend/test/book_switch_test.dart`

- [ ] **Step 1:** Failing tests:
  - not in a family → no switch;
  - in a family → the switch shows, and tapping Family calls `setMode(family)` and Home rebuilds;
  - **Review Focus 2:** a personal `fetchTransactions` response that arrives after switching to family is dropped (the providers' `_generation` is bumped by `reset()`);
  - a read-only family shows the banner and a disabled +;
  - EN and MY at 360 px have no overflow.
- [ ] **Step 2:** Run it. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the whole `flutter test`. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 14: Family management screens and invitations

**Files:**
- Create:
  - `frontend/lib/screens/family/family_screen.dart`:
    - **no family:** a Plus or Pro user sees "Create a family" (name field); a Free user sees the same entry with an Upgrade button (`PlanLimitSheet`-style); there is no mascot;
    - **in a family:** the members list (role chips, former members in a collapsed section), placeholders, pending invites (admins), and the actions by role:
      - rename;
      - invite;
      - add placeholder;
      - member sheet;
      - leave;
      - transfer ownership (owner);
      - delete (owner, with a typed name).
  - `frontend/lib/screens/family/family_member_sheet.dart`: rename, make admin / remove admin (owner only), remove (admin).
  - `frontend/lib/screens/family/family_invite_screen.dart`: an email field and an optional "This is …" link to a placeholder or former member.
  - `frontend/lib/screens/family/family_invitations_screen.dart`: the invitee's pending invites, with Join and Decline. Join while already in a family shows `familyLeaveFirst`.
- Modify:
  - `frontend/lib/screens/settings/settings_screen.dart`: a "Family" section with `AppListRow`, between Account and Appearance.
  - `frontend/lib/screens/notifications/notifications_screen.dart`: `family_invite` opens `FamilyInvitationsScreen`.
  - `frontend/lib/screens/settings/edit_profile_screen.dart`: the delete list adds a line when the user is in a family: `familyDeleteAccountNote` (the owner variant says ownership passes on).
  - `main.dart`: route `/family`.
- Test: `frontend/test/family_screen_test.dart`

- [ ] **Step 1:** Failing tests, using a fake `FamilyProvider`:
  - Free → the Upgrade path, and create is disabled;
  - Plus → create calls `createFamily`;
  - the member role hides invite, placeholder and remove;
  - the owner sees role changes and delete, and delete needs the exact name typed;
  - the invitations screen calls accept and decline;
  - at 360 px in MY, light and dark, there is no overflow.
- [ ] **Step 2:** Run it. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the whole `flutter test`. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 15: Family entries in the app: book, who it was for, who added it, transfers

**Files:**
- Create:
  - `frontend/lib/widgets/for_whom_picker.dart` (`ForWhomPicker({required List<FamilyMember> members, required List<String> selected, required ValueChanged<List<String>> onChanged})`: "Whole family" plus a multi-select of active members; the empty selection means Whole family)
  - `frontend/lib/screens/family/transfer_sheet.dart` (`showTransferSheet(context, {required TransferDirection direction})`: amount, currency, date, note; shows `transfer_insufficient` inline)
- Modify:
  - `frontend/lib/screens/transactions/add_transaction_screen.dart`:
    - a book chip at the top of `_buildEntryHeader`, "Adding to: Personal / <family>", which can be tapped to flip the book for this entry; the request uses that book;
    - a "For whom" row in the Date / Note / Repeat card (family book only).
  - `frontend/lib/screens/transactions/edit_transaction_screen.dart`:
    - a "For whom" row (family);
    - an "Added by <name>" line;
    - Save and Delete are disabled unless `can change`: admin, or the entry's `addedBy.memberId == me.id`;
    - a transfer row opens read-only with "Undo transfer", shown only to its maker.
  - `frontend/lib/services/api_service.dart`: `createTransaction` takes `BookMode? bookOverride` for the flipped book.
  - `frontend/lib/screens/home/home_screen.dart`: the add-options sheet gets "Move to family wallet" (personal mode) / "Take from family wallet" (family mode) when in a family.
  - The transactions list and Recent rows: transfers get a transfer icon, the label `transferToFamily` / `transferFromFamily`, and no category.
  - `frontend/lib/screens/charts/*_analytics_screen.dart`: exclude `isTransfer`.
- Test: `frontend/test/family_entry_test.dart`

- [ ] **Step 1:** Failing tests:
  - the add screen in family mode shows the book chip with the family name;
  - flipping to Personal sends no `X-Book`;
  - the For whom picker sends `for_whom` with two ids; Whole family sends `[]`;
  - in the edit screen as a member, someone else's entry has Save and Delete disabled, and your own has them enabled;
  - a transfer row shows Undo for its maker only;
  - the transfer sheet shows the insufficient error;
  - the analytics totals ignore transfers;
  - EN and MY at 360 px, including the crowded add top bar, have no overflow.
- [ ] **Step 2:** Run it. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the whole `flutter test`. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 16: Family budgets and goals in the app

**Files:**
- Modify:
  - `frontend/lib/screens/budgets/budgets_screen.dart`, `budget_detail_screen.dart`: in family mode, non-admins don't see create, edit or delete.
  - `frontend/lib/screens/goals/goals_screen.dart`, `goal_detail_screen.dart`, `add_goal_screen.dart`:
    - non-admins don't see create, edit or delete;
    - "Add money" is shown to all;
    - "Withdraw" is admins only.
- Test: `frontend/test/family_budgets_goals_test.dart`

- [ ] **Step 1:** Failing tests:
  - as a member in family mode: no create FAB on Budgets or Goals, Add money visible, Withdraw hidden;
  - as an admin: all visible;
  - in personal mode: unchanged.
- [ ] **Step 2:** Run it. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the whole `flutter test`. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 17: The "Who we spent on" breakdown in Reports

**Files:**
- Modify:
  - `frontend/lib/screens/report/reports_screen.dart`: in family mode, a "Who we spent on" card after the summary tiles. It has one row per `BreakdownRow` (name, amount, share bar), with former members marked and the Whole family row first when present. Data comes from `ApiService.getFamilyBreakdown(start, end, currency)`, injected through a `BreakdownLoader` seam like `ReportLoader`.
  - `frontend/lib/services/api_service.dart`: `getFamilyBreakdown`.
- Test: `frontend/test/family_breakdown_test.dart`

- [ ] **Step 1:** Failing tests:
  - family mode shows the card with the rows in order and amounts through `formatMoney` (MMK whole kyat);
  - personal mode shows no card;
  - at 360 px in MY, long names wrap.
- [ ] **Step 2:** Run it. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the whole `flutter test`. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 18: Ko Toe Pwar and insights in Family mode, in the app

**Files:**
- Modify:
  - `frontend/lib/screens/ai/ai_chat_screen.dart`:
    - in family mode, the subtitle reads `askAboutFamily` ("Answers about your family book"), the welcome text is `familyChatGreeting`, and the suggested questions become `familySuggestions` ("How much did we spend this month?", "What did we spend on Ma Ma?" with the first placeholder's name, or "on the kids" when there is none);
    - history is reloaded on a mode change (the provider reset already clears it).
  - `frontend/lib/screens/insights/insights_screen.dart`: in family mode, the header shows the family name, and the Custom tab's empty state says reports are shared with the family (`familyCustomInsightsShared`).
- Test: `frontend/test/family_chat_test.dart`

- [ ] **Step 1:** Failing tests:
  - family mode shows the family subtitle and suggestions;
  - sending in family mode sends `X-Book: family` (the streamer seam receives a request while `ApiService.bookMode` is family);
  - switching modes clears the messages.
- [ ] **Step 2:** Run it. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the whole `flutter test`. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 19: Whole-branch verification

- [ ] **Step 1:** Run the whole backend suite (`run_suite.ps1`, i.e. `run_backend_suite.py`). Expected: no BUG or FAIL; `test_family` all PASS.
- [ ] **Step 2:** Run the whole `flutter test`, and `flutter analyze` on every changed file. Expected: all pass, no new issues.
- [ ] **Step 3:** Build the release web app and seed a family: Mum (Plus, en, owner), Dad (Free, my, member), placeholders Ma Ma and Grandma, family entries, a transfer, a family budget and goal. Check by eye, at 360 px and 390 px, EN and MY, light and dark:
  - the switch;
  - the family screen;
  - add with For whom;
  - edit permissions;
  - the transfer;
  - the breakdown in Reports;
  - the chat in Family mode;
  - the read-only state after expiring Mum's plan.

  Record any defects as new tasks.
- [ ] **Step 4:** Commit any fixes. Stop the servers.
