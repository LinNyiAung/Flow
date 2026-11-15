# Books Table Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every person a personal book and every family a family book in a new `books` table. Key all book data by `book_id`, keep `users` for people only, and replace `notifications.goal_id` with typed links. Behaviour stays the same, apart from fixing family "auto-create with AI" budgets.

**Architecture:**
- **Schema:** `books` is the owner of transactions, budgets, goals, insights and custom insights. `get_book` resolves the `X-Book` header to a `books.id`, and every data helper takes `book_id`.
- **Migration:** one Alembic migration converts existing data and has a working downgrade.
- **Per person:** AI cost, quotas, chat history and notifications stay with the person.
- **Per book:** a family book's AI spend is recorded on `ai_usage.book_id`.

**Tech Stack:**
- Python 3.12, FastAPI, SQLAlchemy Core + asyncpg, Alembic, PostgreSQL 17 (local e2e cluster).
- e2e scripts in `e2e/`.
- Admin React in `admin/`.

**Spec:** `docs/superpowers/specs/2026-11-15-books-table-design.md`

## Global Constraints

- **Migrations:**
  - One new Alembic migration, `down_revision = '522ad619de76'`. The two family migrations are not rewritten.
  - The downgrade must work on a populated database: `test_plans` downgrades through it while other tests' data is present.
- **Books:**
  - `books`: `id` text uuid4 (never equal to a user id), `kind` `'personal'|'family'`, `person_id` (FK users, CASCADE, unique where not null), `family_id` (FK families, CASCADE, unique where not null), `ai_data_stale` boolean default false, `created_at`.
  - A CHECK ties `kind` to exactly one owner column.
- **Book data:**
  - `transactions`, `budgets`, `goals`, `insights` and `custom_insights` lose `user_id` and gain `book_id` (NOT NULL, FK `books.id` ON DELETE CASCADE).
  - Indexes keep their names with `user` → `book`.
- **Other tables:**
  - `chat_sessions`: keeps `user_id` (the person). `book_id` becomes NOT NULL, FK `books.id` CASCADE; personal chats point at the personal book.
  - `ai_usage`: `user_id` nullable; new `book_id` FK `books.id` ON DELETE SET NULL, indexed. No CHECK. A deleted family's rows keep their cost with both NULL.
  - `families`: loses `book_user_id`.
  - `users`: loses `kind`, its CHECK, `ai_data_stale`, and every book row.
- **Notifications:**
  - Typed links replace the text `goal_id` and `book`, each a FK with ON DELETE SET NULL and indexed: `goal_id`→goals, `budget_id`→budgets, `transaction_id`→transactions, `custom_insight_id`→custom_insights, `family_invite_id`→family_invites, `family_id`→families, `book_id`→books.
  - A CHECK allows at most one of the six subject links.
- **Settings for a family book:** family insights and family AI budgets use the **owner's** `default_currency` and `language`.
- **Family AI-budgets fix:** "auto-create with AI" family budgets follow the owner's plan and AI cost cap (R16), and their spend goes to `ai_usage.book_id`. With a Free owner or over the cap, they get the non-AI amounts.
- **AI spend:**
  - Work on a personal book is recorded under `user_id` = the person.
  - Work on a family book (weekly/monthly insights scheduled or on demand, their Myanmar translations, AI-made budgets) is recorded under `book_id`, with `user_id` NULL.
  - Chat, entry AI, budget suggestions and custom insights stay under the asking person.
- **API (no old-app compatibility; the owner's phone is updated with the backend):**
  - Transaction, budget, goal and insight responses carry `book_id` and no `user_id`.
  - Notifications (API and push data) carry `subject_id` (the one typed link set; null in the API, `""` in push) instead of `goal_id`, plus `book` (`'family'` when the notice's book is a family book).
  - Notification responses keep `user_id` (the recipient).
  - The app's models and notification handling are renamed to match (Task 7).
- **Renaming:** helpers, services and doc dicts rename the data id from `user_id` to `book_id`, with no aliases left behind.
- **Environment:**
  - Windows PowerShell only; Git Bash is broken.
  - Local throwaway DB and stub server only; never production or real keys.
  - Never read or print `.env*`.

**Commands used throughout:**
- `$PY` = `C:\Users\LINNYI~1\AppData\Local\Temp\claude\C--projects-Flow\88f449c7-2e35-4a07-890d-5a91aa9c3948\scratchpad\venv_final\Scripts\python.exe`
- `$RUN` = `...\88f449c7-2e35-4a07-890d-5a91aa9c3948\scratchpad\pg\run_suite.ps1`
  - `& $RUN -NoSuite` resets the DB and starts the stub server on 127.0.0.1:8765.
  - `& $RUN` also runs the full backend suite.
- Start Postgres first if it's down: `pg_ctl ... -D C:\projects\Flow\e2e\.data\pg -o "-p 54329 ..." start`.
- A single e2e file: `cd C:\projects\Flow\e2e; $env:PYTHONIOENCODING='utf-8'; & $PY -u <file>.py`. Expected: no `[BUG]` lines, exit 0.

## Plan decisions (rulings made while planning)

- **P1. Red window.** The column rename can't be split into steps that each leave the whole suite passing: Task 1 drops `user_id`, and every data query is converted in Tasks 2–6. Each task runs the e2e files it owns, and the full backend suite must pass from Task 6 on. This overrides the spec's "each step leaves the suite passing", which it left to the builder.
- **P2. A person row with no personal book** (written by older code or by tests inserting into `users` directly) gets one on demand. `get_current_user` calls `ensure_personal_book`, an idempotent `INSERT … ON CONFLICT DO NOTHING`, when the join finds none. Registration still creates it up front.
- **P3. `get_current_user` returns the user dict with an extra key `personal_book_id`.** It's loaded in the same query as the user, so there is one lookup per request.
- **P4. A test helper translation.** `e2e/pgcompat.py` translates a `user_id` key into that person's personal book id, in inserts and filters on `transactions`, `goals`, `budgets`, `insights` and `custom_insights`. This keeps about 100 test seed sites unchanged. Raw `db.sql(...)` strings are rewritten by hand.
- **P5. Insight notices** store `book_id` for both personal and family books, and dedupe on it. The old `no_goal_id` / `goal_id=book` dedupe goes.
- **P6. The money lock** is a `FOR UPDATE` row lock on `books`. The in-process asyncio lock dict stays, keyed by book id. Locks are taken in sorted id order, as today.

## Review Focus

1. **A person id still used where a book id belongs:** a personal dashboard, report or job that quietly shows nothing after the migration. A person who had data before the migration must see the same balance, transactions, budgets and goals through the API afterwards. Tested in Task 2 (`migrated person sees the same data`) and Task 4 (jobs).
2. **The downgrade on a populated database:** balances, goal amounts and transfer pairs survive down and up again. Tested in Task 1 (`down then up keeps every balance`).
3. **Deleting a family or an owner's account** when the family has AI spend, notices and chats: the delete succeeds, its spend stays in the admin totals, and its notices stay with their links cleared. Tested in Task 5 (notices) and Task 6 (spend).
4. **A user row with no personal book** (P2) logs in and works on an empty personal book, with no 500. Tested in Task 2 (`user without a book gets one`).
5. **A notice whose linked item is deleted** stays in the list, opens nothing, and still shows its text. In the app, tapping it shows the usual "not found" handling, with no crash. Tested in Task 5 (backend) and Task 8's browser check (app).

---

### Task 1: Schema and migration

**Files:**
- Modify: `backend/sql/tables.py`. Add `books`; change transactions, budgets, goals, insights, custom_insights, chat_sessions, ai_usage, families, users and notifications as in Global Constraints.
- Create: `backend/alembic/versions/20261115_<rev>_books.py`. `revision` is any new 12-hex id; `down_revision = '522ad619de76'`.
- Modify: `backend/sql/docs.py`. The row↔doc mappers use `book_id` instead of `user_id` for the five book-data tables; the notification mapper uses the typed links.
- Create: `e2e/test_books.py`, with sections `section_schema` and `section_migration` (later tasks add sections).
- Modify: `e2e/run_backend_suite.py` to register `test_books.py` before `test_family.py`.
- Modify: `e2e/test_family.py` `section_schema`. It now expects no `users.kind`, no `families.book_user_id`, `chat_sessions.book_id` NOT NULL, and the books constraints instead of the old ones.

**Interfaces:**
- Produces: the schema in Global Constraints; the table objects `tables.books`, `tables.notifications` (new columns); the doc keys `book_id` (data docs), `goal_id`/`budget_id`/`transaction_id`/`custom_insight_id`/`family_invite_id`/`family_id`/`book_id` (notification docs).

**Migration contents (upgrade, one transaction):**
1. Create `books`.
2. Insert a personal book (new uuid4) for every `users` row with `kind = 'person'`.
3. Insert a family book per family with `id = families.book_user_id`.
4. On each book-data table: add `book_id`, then fill it. A row owned by a person gets that person's personal book id; a row owned by a book user gets the same id. Then set NOT NULL, drop `user_id` and its indexes, and add the FK and the renamed indexes (including `uq_budgets_rollover_child` and `uq_custom_insights_pending_book`).
5. Fill `chat_sessions.book_id` (NULL → the person's personal book) and add the FK to `books`.
6. `ai_usage`: add `book_id`. Rows whose `user_id` is a book user get `book_id` = that id and `user_id` NULL. Make `user_id` nullable.
7. Copy `users.ai_data_stale` into `books.ai_data_stale` (a person's value goes to their personal book; a book user's value to its family book).
8. **Notifications:**
   1. Add the seven typed columns.
   2. Map the old `goal_id` by `type`, using the type table below. A value with no matching row in the target table stays NULL.
   3. Set `book_id`:
      - for goal, budget, transaction and custom-insight subjects: that subject's `book_id`;
      - for `weekly_insights_generated` / `monthly_insights_generated`: the old `goal_id` when it was a book user, else the recipient's personal book;
      - otherwise: NULL.
   4. Drop the old `goal_id` text column and the `book` column with its CHECK, then add the FKs and indexes and the at-most-one CHECK.
9. Drop `families.book_user_id`, delete `users` rows with `kind = 'family_book'`, then drop `users.kind`, its CHECK and `users.ai_data_stale`.

**Type → link table (from `notification_service`; every type must appear):**
- `goal_progress`, `goal_achieved`, `goal_milestone`, `goal_approaching_date` → `goal_id`.
- `budget_threshold`, `budget_exceeded`, `budget_ending_soon`, `budget_now_active`, `budget_started`, `budget_auto_created` → `budget_id`.
- `large_transaction`, `recurring_transaction_created`, `recurring_transaction_ended`, `recurring_transaction_disabled` → `transaction_id`.
- `custom_insight_ready`, `custom_insight_failed` → `custom_insight_id`.
- `family_invite` → `family_invite_id`.
- `family_invite_accepted`, `family_removed`, `family_owner` → `family_id`.
- `weekly_insights_generated`, `monthly_insights_generated` → `book_id` only.
- No link: `unusual_spending`, `payment_reminder`, the subscription/plan types and broadcasts.

**Downgrade:** the exact reverse.
1. Re-create the book users (`kind 'family_book'`, email `family-<family_id>@book.invalid`, a bcrypt hash of a random secret, `subscription_type 'free'`, language `'en'`, verified) with `id` = the family book id.
2. Restore `users.kind` and `users.ai_data_stale`, and `families.book_user_id`.
3. Map `book_id` back to `user_id`: a personal book maps to its `person_id`, a family book to its id.
4. `chat_sessions.book_id`: personal → NULL.
5. `ai_usage`: `book_id` → `user_id`. Rows with both NULL (a deleted family's spend) are deleted, because the old schema can't hold them.
6. Notifications: the typed links collapse back into `goal_id` (the one link that's set; for insight notices, `book_id` when it's a family book). `book = 'family'` where `book_id` is a family book.
7. Drop `books`.

- [ ] **Step 1: Write the failing tests** in `e2e/test_books.py`.
  - **`section_schema`:** assert (via `information_schema` / `pg_indexes` / `_violates`, as in `test_family.section_schema`):
    - `books` has its columns;
    - a second personal book for the same person is refused;
    - a book with `kind='personal'` and `family_id` set is refused;
    - `transactions.book_id` is NOT NULL and `transactions.user_id` doesn't exist (likewise for budgets, goals, insights, custom_insights);
    - `users.kind` and `families.book_user_id` don't exist;
    - `ai_usage.user_id` is nullable;
    - a notification with both `goal_id` and `budget_id` set is refused;
    - the indexes `ix_transactions_book_date`, `uq_budgets_rollover_child`, `uq_custom_insights_pending_book` and `ix_ai_usage_book_id` exist.
  - **`section_migration`:**
    1. `alembic downgrade 522ad619de76`.
    2. With raw SQL in the old shape, seed: two persons A and B with personal transactions (MMK and USD), a budget with allocations, a goal with `current_amount`, an insight and a custom insight; a family with a book user, family transactions, a transfer pair (A ↔ family), a family goal, chat sessions personal (book_id NULL) and family; `ai_usage` rows for A and for the book user; `users.ai_data_stale = true` on the book user; and notices of types `goal_achieved`, `budget_started`, `large_transaction`, `custom_insight_ready`, `family_invite`, `family_owner`, `weekly_insights_generated` (personal and family) and `unusual_spending`.
    3. Record each owner's per-currency sum of inflow − outflow and goal totals.
    4. `alembic upgrade head`, then assert:
       - every row sits on the right book (A's on A's personal book, family rows on the family book whose id equals the old book user id);
       - per-book sums and goal totals equal the recorded ones;
       - both transfer legs share `transfer_id` and sit on A's book and the family book;
       - no `users` row has a book id;
       - the family book's `ai_data_stale` is true;
       - each notice's typed link and `book_id` are as in the table;
       - the book user's `ai_usage` rows have `book_id` set and `user_id` NULL.
    5. **`down then up keeps every balance`:** downgrade to `522ad619de76` and assert the old shape and the same sums, the book user back with `kind 'family_book'`, and the notices' `goal_id`/`book` restored. Upgrade head again and assert the sums once more.
    6. Clean up the seeded rows.
- [ ] **Step 2: Run and confirm failure.** `& $RUN -NoSuite`, then run `test_books.py`. Expected: `[BUG]` lines (no `books` table).
- [ ] **Step 3: Implement** the `tables.py` changes, the migration, the `docs.py` mappers and the `test_family.section_schema` expectations.
- [ ] **Step 4: Run and confirm success.** `& $RUN -NoSuite` (fresh DB at head), then run `test_books.py`. Expected: all `[PASS]`, exit 0. The app's other routes may fail until Task 2 (P1).
- [ ] **Step 5: Commit.** `feat(db): books table, book_id on book data, typed notification links (migration)`

### Task 2: Books in the request path: creation, resolution, locks, balance, freshness

**Files:**
- Create: `backend/sql/books.py`.
- Modify:
  - `backend/sql/users.py`: remove `IS_PERSON` and its uses, `is_book_user`, `create_book_user`, `claim_ai_data_fresh`, `mark_ai_data_stale` and `money_lock`; `get_person` → `get_user`.
  - `backend/utils.py`: `get_current_user` (P2/P3), the money locks, and the balance helper.
  - `backend/families/book.py`: `get_book` and `Book.personal`.
  - `backend/auth_routes.py`: `register` creates the personal book in the same transaction; the login lookup drops its `kind` filter.
  - `backend/families/service.py`:
    - `create_family` creates the family book;
    - family deletion and an owner's account deletion delete the family (the book cascades) instead of `users_db.delete_user(book_user_id)`;
    - `_notify` drops its non-person filter.
  - `backend/sql/families.py`: replace `book_user_id` with lookups through `books`. `family_for_book(book_id)`, `account_user_ids_for_book(book_id)`, `active_member_user_id(book_id, member_id)` and `books_with_paid_owner(plans)` return the family book id.
  - Every caller of the removed or renamed helpers, as listed in the code map, including:
    - `admin_routes.py`: `get_person` → `get_user`;
    - `notification_service.py:344`: `create_notification`'s book-user refusal goes;
    - `recurring_transaction_service._notice_recipient`;
    - `insights_service._insight_profile`.
- Modify: `e2e/test_money_lock.py` (locks are on books) and `e2e/pgcompat.py` (P4).
- Test: `e2e/test_books.py`, new section `section_books_in_requests`.

**Interfaces:**
- **Consumes:** Task 1's schema.
- **Produces (`backend/sql/books.py`):**
  - `async def create_personal_book(person_id: str, *, conn=None) -> str`
  - `async def ensure_personal_book(person_id: str) -> str` (idempotent; returns the id)
  - `async def create_family_book(family_id: str, *, conn=None) -> str`
  - `async def personal_book_id(person_id: str) -> Optional[str]`
  - `async def family_book_id(family_id: str) -> Optional[str]`
  - `async def get_book_row(book_id: str) -> Optional[dict]` (keys `id`, `kind`, `person_id`, `family_id`, `ai_data_stale`)
  - `async def book_profile(book_id: str) -> Optional[dict]`: the person whose settings the book uses. Personal: that person. Family: the owner (`families_db.owner_user`). This is the user dict with `default_currency`, `language`, plan fields and `_id`.
  - `async def mark_ai_data_stale(book_id: str) -> None`
  - `async def claim_ai_data_fresh(book_id: str) -> bool`
  - `@asynccontextmanager async def money_lock(book_id: str)`: `FOR UPDATE` on the books row inside `transaction()`.
- **Produces (`backend/utils.py`):** `get_book_money_lock(book_id)`, `get_books_money_locks(book_ids)` (same semantics as the old ones, P6), and `async def get_book_balance(book_id: str, currency: Optional[str] = None) -> dict`. `get_book_balance` gives what `get_user_balance` gave; a currency default that came from the data owner's `users` row now comes from `book_profile`. The old names are removed.
- **Produces:** `get_current_user` returns the user dict plus `personal_book_id`. `Book.personal(person: dict) -> Book` uses `person["personal_book_id"]`. `get_book` returns `Book.id` = a `books.id` in both modes; the family book is found via `family_book_id(family["id"])`. `Book.family` no longer has `book_user_id`.

- [ ] **Step 1: Write the failing tests** in `section_books_in_requests`.
  - **`register creates one personal book`:** after `POST /api/auth/register`, `books` has exactly one personal row for the new user id, and its id ≠ the user id.
  - **`creating a family creates one family book`:** after `POST /api/family` (as a Plus user), exactly one family book exists for that family. `GET /api/transactions` with `X-Book: family` answers 200 with `[]`.
  - **`user without a book gets one`:** `INSERT INTO users` directly (as `test_plans` does), log in, `GET /api/transactions` → 200 `[]`, and now exactly one personal book exists.
  - **`a person id is not a book id`:** `transactions_db.find_transactions(<A's user id>)` (backend async, the Task 3 signature `book_id` positional) returns `[]`, even though A has transactions in their personal book.
  - **`migrated person sees the same data`:** seed old-shape data for a person as in Task 1's `section_migration` (downgrade, seed, upgrade). Log in as that person through the API (set a known password hash in the seed). `GET /api/transactions` count and the `GET /api/dashboard`/balance totals equal the seeded ones.
  - **`book freshness flag`:** a `POST /api/transactions` in the personal book sets that book's `ai_data_stale`. In Family mode it sets the family book's. `claim_ai_data_fresh` returns True once, then False.
  - **`deleting a family deletes its book`:** after the owner deletes the family, no family book row is left, and its transactions are gone.
  - **`test_money_lock.py`** updated to lock book ids. Its concurrency assertions stay the same (two concurrent goal contributions can't overspend; transfer locks are taken in sorted order without deadlock).
- [ ] **Step 2: Run and confirm failure.** `& $RUN -NoSuite`, then `test_books.py` and `test_money_lock.py`. Expected: the new section has `[BUG]` lines.
- [ ] **Step 3: Implement** `sql/books.py`, the `utils` and `get_book` changes, registration and family creation/deletion, the removals, and the P4 translation in `pgcompat` (look up the personal book with `personal_book_id`, creating it with `ensure_personal_book` when missing).
- [ ] **Step 4: Run and confirm success.** `& $RUN -NoSuite`; `test_books.py` and `test_money_lock.py`. Expected: all `[PASS]`.
- [ ] **Step 5: Commit.** `feat(backend): books in the request path: creation, resolution, locks, balance, freshness`

### Task 3: Book data: SQL helpers and routes

**Files:**
- Modify, renaming the data-id parameter `user_id` → `book_id` and the filter `c.user_id` → `c.book_id`:
  - `backend/sql/transactions.py`: every function in the code map §1, including `active_user_ids(since)`, which now returns the person ids of personal books.
  - `backend/sql/budgets.py`, `backend/sql/goals.py`, `backend/sql/insights.py`, `backend/sql/custom_insights.py` (`insert_pending`'s conflict target `book_id`), `backend/sql/chat.py`.
  - `backend/sql/families.py`: `outflow_shares` and `transfer_totals` take `book_id`.
- Modify the routes:
  - `backend/transaction_routes.py`, `backend/goal_routes.py`, `backend/budget_routes.py`, `backend/report_routes.py`, `backend/custom_insight_routes.py`;
  - `backend/families/transfers.py`: the personal leg uses `book.person["personal_book_id"]` everywhere, including in the locks, `mark_ai_data_stale` and leg matching;
  - `backend/families/breakdown.py`;
  - `backend/main.py`: the balance/dashboard route, `_generate_counted` and `_free_monthly_insight` (no more `data_id or user["_id"]`; pass the book id), and the chat route's book (`chat_db` gets `book.id` for both modes).
- Modify the response models: `models.py` `TransactionResponse`, `budget_models.BudgetResponse`, `goal_models.GoalResponse` and `insight_models.InsightResponse` replace `user_id: str` with `book_id: str`.
- Modify `backend/admin_routes.py:563-568, 613-620`: per-user counts read the person's personal book.
- Test:
  - update `e2e/test_api.py`, `e2e/test_family.py` (sections `book_scope`, `entries_breakdown`, `breakdown_rounding`, `transfers`, `budgets_goals`), `e2e/plans_custom_insight_checks.py` and `e2e/plans_chat_checks.py`;
  - convert their raw SQL from `user_id` to `book_id` on the five tables, and drop `Book.personal(...)` call shapes;
  - new `test_books.py` section `section_api_shape`.

**Interfaces:**
- **Consumes:** Task 2's `Book.id`, `get_book_balance`, `get_book_money_lock`, `get_books_money_locks`, `books_db.*`.
- **Produces:** every helper in code map §1 with `book_id` as its first parameter, keeping its name, e.g. `find_transactions(book_id, *, ...)`, `list_budgets(book_id, *, ...)`, `allocated_by_currency(book_id)`. Docs carry `book_id`. `chat_db.append_exchange(user_id, messages, keep_last, now, book_id)` takes `book_id` as required.

- [ ] **Step 1: Write the failing tests.**
  - **`section_api_shape`:** a created transaction, budget, goal and generated insight carry `book_id` equal to the personal book id and have no `user_id` key. In Family mode `book_id` equals the family book id.
  - Update the existing tests named above to the new columns. Their behavioural assertions stay unchanged: privacy, transfers, breakdown, permissions.
- [ ] **Step 2: Run and confirm failure.** `& $RUN -NoSuite`, then `test_books.py`, `test_api.py`, `test_family.py`, `plans_custom_insight_checks.py` (via `test_plans.py`, which imports it) and `plans_chat_checks.py`. Expected: failures where code still filters `c.user_id`.
- [ ] **Step 3: Implement** the renames and the route changes.
- [ ] **Step 4: Run and confirm success.** The same files, all `[PASS]`. For `test_plans.py`, expect `1095/1095 passed` plus any new checks.
- [ ] **Step 5: Commit.** `refactor(backend): book data keyed by book_id in SQL helpers and routes`

### Task 4: Services and jobs on books (and the family AI-budgets fix)

**Files:**
- Modify:
  - `backend/insights_service.py`:
    - `_job_targets` returns `(book_id, plan_user, is_family)` for personal books of paid persons and family books of paid owners;
    - `_skip_user` takes the book;
    - `_insight_profile` uses `books_db.book_profile`;
    - `generate_weekly_insight` / `generate_monthly_insight` / `run_insight_model` / `translate_insight_to_myanmar` take `book_id`;
    - notify via the book.
  - `backend/budget_service.py`:
    - `BudgetAnalyzer(book_id, language, ai_user_id)`;
    - `get_running_budgets`, `update_budget_spent_amounts`, `update_relevant_budgets`, `update_budgets_in_range`, `auto_create_next_budget`, `update_all_user_budgets` → `update_all_book_budgets(book_id)`, `process_due_budget_rollovers`;
    - `_owner_gets_ai_budgets(book_id)` uses `book_profile` and, for a family book, `quota.family_over_cost_cap(owner, book_id)`;
    - `_ai_category_budgets` passes the book to the runner (Task 6 records it).
  - `backend/recurring_transaction_service.py`: `_notice_recipient` uses `books_db.get_book_row`; `_refresh_user_after_recurring` → `_refresh_book_after_recurring(book_id, ...)`.
  - `backend/notification_service.py`: the unusual-spending and recurring-payment jobs iterate persons and use their personal book (family books stay excluded, R14); `notification_recipients(book_id)`; `create_notification_from_key` fans out by book kind.
  - `backend/ai_chatbot.py`: `FinancialDataProcessor(book_id)`, `get_family_context` via `family_for_book(book_id)`, the vector cache keyed by book id.
  - `backend/scheduler.py`: the call sites.
  - `backend/subscription_service.py`: drop the `kind` filters only.
- Test:
  - update `e2e/test_jobs.py`, `e2e/test_jobs2.py`, `e2e/test_regressions*.py`, `e2e/test_round3.py`, `e2e/test_round5.py`, `e2e/test_backend_r4.py`, `e2e/test_plan_expiry.py`, `e2e/plans_insight_checks.py`, `e2e/test_ai_providers.py` (insights parts), and `e2e/test_family.py` `section_ai` and `section_recurring_children`;
  - new `test_books.py` section `section_jobs`.

**Interfaces:**
- **Consumes:** Tasks 2–3.
- **Produces:** `update_all_book_budgets(book_id)`, and `insights_service._job_targets(feature) -> List[Tuple[str, dict, bool]]`.

- [ ] **Step 1: Write the failing tests** in `section_jobs`.
  - **`weekly job covers each book once`:** paid persons P1, P2 and Free F, and a family owned by P1. Run the weekly insight job with the AI stubbed. Exactly one insight each is written for P1's book, P2's book and the family book, and none for F.
  - **`recurring job uses the entry's book`:** a recurring parent in a family book creates its child in the family book, and the notice goes to the adder only (R14).
  - **`family AI budgets follow the owner`:** a family budget with `auto_create_enabled` and `auto_create_with_ai`.
    - Owner on Plus: `process_due_budget_rollovers` calls the stubbed `budget_auto_create` once, and the next budget's allocations are the AI's.
    - Owner on Free: no AI call, and the non-AI amounts are used.
  - **`unusual spending skips family books`:** a family book with an unusual spike makes no `unusual_spending` notice. A person's book does.
  - Update the listed files to the new names and columns, keeping their assertions.
- [ ] **Step 2: Run and confirm failure.** `& $RUN -NoSuite`; the files above. Expected: failures.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run and confirm success.** The same files, all `[PASS]`.
- [ ] **Step 5: Commit.** `refactor(backend): services and jobs work on books; family AI budgets follow the owner's plan`

### Task 5: Typed notification links

**Files:**
- Modify:
  - `backend/sql/notifications.py`: the new `exists(...)` and `approaching_reminder_exists(...)` signatures, and `_row` keeps the typed keys.
  - `backend/notification_service.py`: every writer in the type → link table stores the matching key; insight notices store `book_id` (P5); the family marker comes from the book's kind; the push data carries `subject_id` (the one subject link set, `""` if none) instead of `goal_id`, and `book: 'family'` when the book is a family book.
  - `backend/families/service.py` (the invite/accept/removed/owner notices), `backend/recurring_transaction_service.py` and `backend/custom_insights_service.py` writers.
  - `backend/main.py`: the notification routes' response (`subject_id` = coalesce of the six links; `extra.book` = `'family'` when the book is a family book).
  - `backend/notification_models.py`: `NotificationResponse.goal_id` → `subject_id`, and the comments.
- Test: update `e2e/test_family.py` `section_notifications` (including the push `data.goal_id` → `data.subject_id`), `e2e/plans_custom_insight_checks.py` and `e2e/test_regressions3.py` (their `goal_id` asserts become `subject_id`); new `test_books.py` section `section_notification_links`.

**Interfaces:**
- **Consumes:** Tasks 1–4.
- **Produces:** `async def exists(user_id: str | Iterable[str], types, *, goal_id=None, budget_id=None, transaction_id=None, custom_insight_id=None, family_invite_id=None, family_id=None, book_id=None, goal_name=None, currency=None, since=None, no_subject: bool = False) -> bool`; `async def approaching_reminder_exists(user_id, goal_id, threshold, target_key, since) -> bool` (unchanged shape, now on the typed `goal_id`).

- [ ] **Step 1: Write the failing tests** in `section_notification_links`.
  - **`each notice stores its typed link`:** trigger a `goal_achieved`, a `budget_started`, a `large_transaction` and a `custom_insight_ready` notice, and a family invite, then check each row's typed column holds the subject id and the other subject links are NULL.
  - **`API and push carry subject_id and book`:** `GET /api/notifications` returns `subject_id` equal to the subject id and no `goal_id` key. A family-book notice has `extra.book == 'family'`, and the push data (captured by the stub) has `subject_id` and `book` and no `goal_id`.
  - **`deleting the subject keeps the notice`:** delete the goal; its `goal_achieved` notice is still listed with the same text, and `subject_id` is null.
  - **`insight notices dedupe per book`:** running the weekly job twice makes one `weekly_insights_generated` notice per recipient per book.
- [ ] **Step 2: Run and confirm failure.** `& $RUN -NoSuite`; `test_books.py`, `test_family.py`, `test_regressions3.py`, `test_plans.py`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run and confirm success.** The same files, all `[PASS]`.
- [ ] **Step 5: Commit.** `refactor(backend): notifications link their subject with typed foreign keys`

### Task 6: AI spend per book, cost caps, the admin report; full suite

**Files:**
- Modify:
  - `backend/ai_usage_service.py`: `track_ai_usage(user_id: Optional[str], feature_type, ..., book_id: Optional[str] = None)`, with exactly one of them set.
  - `backend/ai_providers/runner.py`: `run` / `run_stream` accept `book_id` and pass it through.
  - `backend/sql/ai_usage.py`:
    - `insert_usage` writes `book_id`;
    - `user_cost_since(user_id, since)` and a new `book_cost_since(book_id, since)`;
    - `overall_stats` counts distinct non-null `user_id`;
    - `per_user_stats` returns rows with `user_id`, `book_id`, `user_name`, `user_email`. A family book is labelled "Family · <name>" with the owner's email; spend with both NULL is one row labelled "Deleted family";
    - `user_detail(user_id, ...)` and a new `book_detail(book_id, ...)`;
    - `feature_stats` aggregates both columns.
  - `backend/plans/quota.py`: `_at_cost_cap` and `family_over_cost_cap(owner, book_id)` / `require_under_cost_cap(..., book_id=...)` add `book_cost_since(book_id)`.
  - `backend/insights_service.py`, `backend/main.py` (`_ensure_myanmar_translation`'s `cost_user_id` → `cost_book_id` for family) and `backend/budget_service.py` record family-book spend with `book_id` (personal: `user_id` = the person).
  - `backend/admin_routes.py`: new `GET /api/admin/ai-usage/book/{book_id}`, beside the user one; `ai_usage_models` gain `book_id: Optional[str]`.
  - `admin/src/AIUsageStats.jsx` and `admin/src/api.js`: rows key on `user_id ?? book_id ?? 'deleted-family'`; selecting a family row loads `/api/admin/ai-usage/book/{book_id}`; the "Deleted family" row has no detail.
- Test:
  - update `e2e/test_ai_providers.py`, `e2e/plans_insight_checks.py`, `e2e/plans_quota_checks.py`, `e2e/plans_entry_checks.py`, `e2e/plans_subscription_checks.py` and `e2e/test_family.py` `section_ai` / `section_account_deletion` to the new `ai_usage` columns;
  - new `test_books.py` section `section_ai_spend`.

**Interfaces:**
- **Consumes:** Tasks 1–5.
- **Produces:** `book_cost_since(book_id: str, since: datetime) -> Decimal`, `book_detail(book_id, feature_type=None, limit=...)`, the admin route above, and `track_ai_usage(..., book_id=...)`.

- [ ] **Step 1: Write the failing tests** in `section_ai_spend`.
  - **`family insight spend is on the book`:** a family weekly insight (AI stubbed) writes an `ai_usage` row with `book_id` = the family book and `user_id` NULL. A personal one writes `user_id` = the person and `book_id` NULL.
  - **`owner cap counts the book`:** the owner's spend plus the book's spend over the plan cap makes `family_over_cost_cap` True.
  - **`deleting a family keeps its spend`:**
    1. The owner deletes the family; the request answers 200.
    2. The family's `ai_usage` rows remain with both columns NULL.
    3. `GET /api/admin/ai-usage/users` includes one "Deleted family" row whose cost equals theirs.
    4. `/api/admin/ai-usage/stats` total cost is unchanged by the delete.
    5. An owner's own account deletion (last member) likewise answers 200.
  - **`admin book detail`:** `GET /api/admin/ai-usage/book/{family_book_id}` lists that book's rows, and the users list shows "Family · <name>" with `book_id` set.
- [ ] **Step 2: Run and confirm failure.** `& $RUN -NoSuite`; `test_books.py`.
- [ ] **Step 3: Implement.** Then build the admin panel: `cd C:\projects\Flow\admin; npm run build`. Expected: build succeeds.
- [ ] **Step 4: Run the full backend suite.** First recreate `flow_e2e` (`dropdb`/`createdb -h 127.0.0.1 -p 54329 -U flow flow_e2e`, then `alembic upgrade head` from `backend`), then `& $RUN`. Expected: `TOTAL` with 0 problems and 0 crashes (P1: the suite must be green from here on).
- [ ] **Step 5: Commit.** `feat(backend): AI spend per book; admin AI report shows family and deleted-family rows`

### Task 7: The app follows the renamed fields

**Files:**
- Modify:
  - `frontend/lib/models/transaction.dart`, `budget.dart`, `goal.dart`, `insight.dart`: `userId` / `json['user_id']` → `bookId` / `json['book_id']`.
  - `frontend/lib/models/notification.dart`: `goalId` / `'goal_id'` → `subjectId` / `'subject_id'`, in fromJson, toJson and copyWith. `userId` stays (the recipient).
  - `frontend/lib/utils/push_tap.dart`: the payload becomes `type|subject_id|book`; the record field is `subjectId`.
  - `frontend/lib/utils/custom_insight_push.dart`, `frontend/lib/services/fcm_service.dart` (reads `data['subject_id']`), `frontend/lib/services/notification_opener.dart` (`open(type, {subjectId, ...})`, `openPush`, `_bookTarget`), `frontend/lib/services/notification_service.dart`, `frontend/lib/screens/notifications/notifications_screen.dart`, `frontend/lib/main.dart`.
  - Leave `frontend/lib/models/report.dart`'s `goalId` alone: it is a goal-progress report row, not a notification.
- Test: update every `frontend/test` file whose JSON fixtures or assertions use `user_id` on these models or `goal_id` / `goalId` on notifications and push taps. Find them with `rg -l "goal_id|goalId|'user_id'" frontend/test`.

**Interfaces:**
- **Consumes:** the API shape in Global Constraints.
- **Produces:**
  - `Transaction.bookId`, `Budget.bookId`, `Goal.bookId`, `Insight.bookId`;
  - `NotificationModel.subjectId`;
  - `typedef PushTap = ({String type, String? subjectId, bool family})`;
  - `pushTapPayload(Object? type, Object? subjectId, Object? book)`;
  - `NotificationOpener.open(String type, {String? subjectId, bool family = false, VoidCallback? onClosed})`.

- [ ] **Step 1: Update the tests first.** The fixtures use `book_id` / `subject_id`; assertions read `bookId` / `subjectId`. Add one test, `push data with subject_id opens the goal`: `fcm_service`'s tap handler given `{'type': 'goal_achieved', 'subject_id': 'g1', 'book': 'family'}` opens goal `g1` in Family mode, with the same expectation as the existing `goal_id` test.
- [ ] **Step 2: Run them and confirm failure.** `cd C:\projects\Flow\frontend; C:\flutter\bin\flutter.bat test`. Expected: compile errors or failures on the renamed fields.
- [ ] **Step 3: Rename** in the files above.
- [ ] **Step 4: Run and confirm success.** `flutter test` → "All tests passed!"; `flutter analyze` → 0 errors, 0 warnings, and no new infos in the changed files.
- [ ] **Step 5: Commit.** `refactor(app): models read book_id; notifications and push taps use subject_id`

### Task 8: Final verification

**Files:** none, unless a check fails.

- [ ] **Step 1:** `cd C:\projects\Flow\frontend; C:\flutter\bin\flutter.bat test` → "All tests passed!". `flutter analyze` → 0 errors, 0 warnings.
- [ ] **Step 2: Browser check.**
  1. `flutter build web --release --dart-define=API_BASE_URL=http://127.0.0.1:8765`.
  2. `& $RUN -NoSuite`; seed with `e2e/seed_rich.py`, then the scratchpad `family_seed/seed_family.py`.
  3. Serve `build\web` on 8093.
  4. As Maya (en) and Aung (my), check the dashboards in both books, add an entry with For whom, a transfer, the Reports breakdown, a family goal contribution, notifications opening the right item in the right book, and family chat.
- [ ] **Step 3: Admin check.** Run the admin dev build against the stub and open the AI-usage page; the family row opens its detail.
- [ ] **Step 4: Clean up.** Stop the servers and Postgres, and remove any temporary `.claude/launch.json`.
