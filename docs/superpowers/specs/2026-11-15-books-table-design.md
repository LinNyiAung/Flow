# Books table (and notification links): design

This is the first of four schema projects, in the owner's agreed order:
1. this one: books, plus typed notification links;
2. a tidy-up: a push-devices table, and budget category limits split into main and sub;
3. goal contribution history;
4. real calendar dates.

**Status:** draft, waiting for the owner's approval.
**Builds on:** the family book (`docs/superpowers/specs/2026-11-13-family-book-design.md`).
**Changes:** how book data is stored; nothing the user sees.

## Intent and why

Today each family owns a hidden row in `users` (`kind = 'family_book'`), and the family's data is stored under that row's id. Personal data is stored under the person's own user id. This made the family book cheap to build, but it means:

- `users` no longer means "people":
  - every bulk read of `users` has to filter `kind`;
  - the family build needed about half a dozen patches for this (admin counts, the plan-expiry job, insight jobs, the AI-cost report, notifications, login refusal);
  - a future feature that forgets the filter shows a phantom user.
- A book's id and a person's id are the same kind of value, and for personal books the very same value. Passing a person's id where a book id belongs works by accident instead of failing.
- Book rows carry fake person data: an `.invalid` email, the hash of a thrown-away password, a plan and a language.

The owner chose to fix this now, while the app is still in development and has no real users' data to protect. The fix is approach A: real books, each with its own id.

## Goals

- A `books` table:
  - every person has exactly one personal book;
  - every family has exactly one family book;
  - each book has its own id, never equal to any user id.
- All book data is keyed by `book_id` → `books.id`.
- `users` holds only people: the `kind` column, the hidden family rows and every `kind` filter are gone.
- **Mixing ids fails loudly.** A person id used where a book id belongs finds nothing or is refused by a foreign key. It never quietly reads or writes another book.
- Everything works as it does today:
  - every behaviour of the personal and family books;
  - transfers, the "who it was for" tags, roles, read-only families, notifications, Ko Toe Pwar (chat, insights, custom insights) and quotas.
- The full backend suite, `flutter test` and `flutter analyze` pass, and a browser check of both books passes.

## Non-goals

- No new features. One family per person stays, and so does one personal book per person.
- No change to the app's screens, the `X-Book` header or the routes. The app's models and notification handling follow the renamed fields (see API).
- No change to the admin panel beyond what keeps its numbers right (the AI-usage report's family rows; see Admin).
- No behaviour change, except fixing family "auto-create with AI" budgets (see Jobs).

## Anti-goals

- Personal data must never become readable from another person's or a family's book, not even for a moment during the migration.
- Money must never appear or vanish. Balances, held-for-goals amounts and transfer pairs must be identical before and after the migration.
- *(Dropped on the owner's word: the only installed app is the owner's own phone, which is updated together with the backend. Old app builds are not supported against the new backend.)*

## Constraints

- **Stack:** PostgreSQL with SQLAlchemy Core and asyncpg; migrations with Alembic.
- **Migrations:**
  - One new Alembic migration, on top of the two family migrations.
  - It needs a working downgrade: the e2e suite's `test_plans` runs downgrade/upgrade cycles.
  - The two family migrations may already be on Render, so they are not rewritten.
  - **Deploying:** a short outage is acceptable (the owner's answer). The migration runs as one step, not as an expand/contract sequence. The old backend may return errors until the new one is up. Render's data is migrated, not reset, so the money anti-goal applies to it.
- **Environment:**
  - Windows; local throwaway databases and stubs only, never production or real keys.
  - Never read or print `.env` files.
- **App compatibility:** the app is released together with this change (see API); no older app build has to keep working.

## Approaches considered

- **A. Real books with their own ids** (owner's choice). Described below.
  - The id of a person and a book can never coincide, so mistakes fail loudly.
  - This is the biggest change: personal data is re-pointed to new ids, and every query and service is renamed.
- **B. A books table where a personal book reuses its owner's id.**
  - A smaller migration: personal rows don't move.
  - The two ids being equal for personal books keeps the "works by accident" trap. Rejected for that reason.
- **C. Keep the hidden users, and add a guard test and a docs note.**
  - Cheapest, but the overloading of `users` stays. Rejected: the app is pre-launch and the owner wants the right model while it's cheap.

## Design

### Schema

**New table `books`:**

| Column | Type | Notes |
|---|---|---|
| `id` | text, primary key | A uuid4, generated for every book. |
| `kind` | text, not null | `'personal'` or `'family'`. |
| `person_id` | text, FK `users.id` ON DELETE CASCADE | Set only for personal books. Unique where not null: one personal book per person. |
| `family_id` | text, FK `families.id` ON DELETE CASCADE | Set only for family books. Unique where not null. |
| `ai_data_stale` | boolean, not null, default false | Moved here from `users`: Ko Toe Pwar's cached view of a book is out of date. `mark_ai_data_stale` / `claim_ai_data_fresh` take a book id. |
| `created_at` | timestamptz, default now() | |

- A CHECK makes `kind` match exactly one owner column: `(kind = 'personal' AND person_id IS NOT NULL AND family_id IS NULL) OR (kind = 'family' AND family_id IS NOT NULL AND person_id IS NULL)`.

**Book data moves from `user_id` to `book_id`** (text, NOT NULL, FK `books.id` ON DELETE CASCADE) on these tables:
- `transactions`
- `budgets`
- `goals`
- `insights`
- `custom_insights`

The existing `user_id` indexes and unique indexes are re-created on `book_id`, with the same names apart from `user` → `book`. Child tables (`budget_allocations`, `transaction_beneficiaries`, `chat_messages`) are unchanged; they hang off their parent.

**Changes elsewhere:**
- **`chat_sessions`:** keeps `user_id`, the person, because chat history is private per person. Its `book_id` becomes NOT NULL, FK `books.id` ON DELETE CASCADE, and points at the book chatted about. A personal chat points at the person's personal book; until now it was NULL.
- **`ai_usage`:** keeps `user_id`, but it becomes nullable. A new nullable `book_id` (FK `books.id` ON DELETE SET NULL, indexed) holds every AI spend that belongs to a family book, whose cost counts toward the owner's cap (ruling R16):
  - weekly and monthly family insights, scheduled or on demand;
  - their Myanmar translations;
  - AI-made family budgets (see Jobs).

  Person spend stays under `user_id` with `book_id` NULL. There is no CHECK requiring one of the two: when a family is deleted, its spend rows keep their cost with both columns NULL, so the admin's AI-cost totals stay true (*my call*). Today those rows were deleted with the book user.
- **`families`:** loses `book_user_id`; a family's book is found through `books.family_id`.
- **`users`:** loses `kind`, its CHECK, `ai_data_stale` (now on `books`), and every book row. Book rows are deleted after their data has moved.
- **Family-book settings that lived on the book user:**
  - Family insights and AI-made family budgets use the owner's `default_currency` and `language`, as R16 already says for currency (*my call*).
  - Everything else on those rows was fake and goes.
- **`notifications`: typed links instead of `goal_id`** (the owner asked for this fix in the same piece of work). `goal_id` holds a goal, budget, transaction, custom-insight, family-invite, family or book id depending on `type`, has no FK, and leaves notices about deleted things pointing at nothing. It is replaced by nullable, typed links, each a FK with ON DELETE SET NULL:

  | Column | FK |
  |---|---|
  | `goal_id` | `goals.id` (now only ever a goal) |
  | `budget_id` | `budgets.id` |
  | `transaction_id` | `transactions.id` |
  | `custom_insight_id` | `custom_insights.id` |
  | `family_invite_id` | `family_invites.id` |
  | `family_id` | `families.id` |

  - **One subject at most:** a CHECK allows at most one of these six per row.
  - **Which book the notice is about:** a separate `book_id` (FK `books.id`, ON DELETE SET NULL) replaces the text marker `book`. The family marker is `book_id` pointing at a family book. Insight notices dedupe on `book_id` instead of storing the book id in `goal_id`.
  - **On delete:** SET NULL, not CASCADE (*my call*). The notice stays in the person's list with its text, but stops opening a thing that no longer exists.
  - **Indexes:** each link has an index; the dedupe lookups that used `goal_id` use the matching typed column.
  - **The migration** maps every existing row by its `type` into the right column. A value that doesn't match a row in the target table is left NULL.
  - **The builder:** writes the type → column table from `notification_service`, and every type must appear in it. `sql/notifications.exists` / `approaching_reminder_exists` take the typed column instead of `goal_id`.
  - **API and push data:** a notice carries `subject_id` (whichever typed link is set) and `book` (`'family'` when its book is a family book). See API.
- **Unchanged (person data, keyed by person):**
  - `notifications` stays keyed by its person;
  - `notification_preferences`, `usage_counters` and `upgrade_requests`;
  - `family_members`, `family_invites`, `admins` and feedback.

### Migration (data)

In one transaction:
1. Create `books`.
2. Insert one personal book, with a new uuid, for every `users` row where `kind = 'person'`.
3. Insert one family book per family, reusing the family's current `book_user_id` value as the book id. That id stops being a user id once its users row is deleted in step 6, so data rows simply switch which table their FK points at.
4. On each book-data table:
   1. add `book_id`;
   2. fill it: for rows owned by a person, the person's personal book id; for rows owned by a book user, the same id (now a family book id);
   3. set it NOT NULL;
   4. drop `user_id` and its indexes;
   5. add the new FK and indexes.
5. Rewrite `chat_sessions.book_id` (NULL → the person's personal book id) and add the new FK. In `ai_usage`, rows whose `user_id` is a book user move to `book_id`, and their `user_id` becomes NULL.
6. Drop `families.book_user_id`, delete the book users, drop `users.kind` and its CHECK.

The downgrade reverses this:
- it re-creates the book users (kind `family_book`, the reserved email domain, a random password hash) with ids equal to the family book ids;
- it moves data back to `user_id`, using the personal book's person for personal books and the family book's id for family books;
- it restores `families.book_user_id` and drops `books`.

### Code

**Book resolution.**
- `get_book` returns a `Book` whose `id` is always a `books.id`.
- Personal: the caller's personal book, looked up by `person_id`. Family: the family's book, looked up by `family_id`.
- `Book.personal(person)` becomes a lookup, or takes the book id, because a person's id is no longer their book's id.
- Builder's choice: load the personal book id together with the user in `get_current_user`, or look it up in `get_book`. Either way it must be one indexed lookup per request at most.

**Book creation.**
- Registration creates the person's personal book in the same transaction as the user. Every existing way of creating a user does this, including the admin's.
- Creating a family creates its family book in the same transaction.
- `create_book_user` / `is_book_user` and the `IS_PERSON` filters are removed.

**Renaming.**
- Every SQL helper, service and job that takes or stores a book's data id renames it from `user_id` to `book_id`.
- This covers `utils.get_user_balance`, the money locks (`get_user_money_lock`, `get_users_money_locks`), budget recalculation, recurring entries, insight and custom-insight services, transfers, the family breakdown, reports/PDF and the chatbot's data reads.
- Old names don't stay behind as aliases. A renamed column means any missed call site fails at once instead of silently using the person's id.

**Jobs.**
- The weekly/monthly insight jobs, the recurring-entry job and the budget jobs iterate over books (personal books of eligible people, family books of paid owners), not over `users` rows.
- **Who gets a book's notices:** a personal book notifies its person. A family book fans out to its active account members, as now (R14).
- **Family budgets set to "auto-create with AI"** (*my call*, the one behaviour change in this work):
  - **Today:** they never use AI, because the check reads the hidden book user's fake Free plan, so they silently get the non-AI amounts. That's a bug.
  - **Now:** they follow the owner's plan and AI cost cap, like family insights (R16), and the spend is recorded under `ai_usage.book_id`.
  - **Fallback:** with the owner on Free or over the cap, they get the non-AI amounts as before.

**Admin.**
- The AI-usage report labels a family book's spend "Family · <name>", now read from `ai_usage.book_id`.
  - Its rows carry `book_id` (and `user_id` null).
  - The admin page keys and links them by `book_id`, through a book detail endpoint (`/api/admin/ai-usage/book/{id}`) next to the user one.
  - This is a small change to `admin/src/AIUsageStats.jsx` and `api.js` (*my call*: keeping these numbers right is in scope).
  - A deleted family's leftover spend shows as one "Deleted family" row.
- "Active users" and the other counts read `users` with no filter needed.
- Deleting a user cascades to their personal book and its data. The family rules for an owner deleting their account (hand over or delete first) are unchanged.

### API

The owner's phone is the only installed app, so the API is cleaned up rather than kept compatible. The app changes with it:

- **Data responses:** transactions, budgets, goals and insights carry `book_id` and no longer `user_id`. The app's models rename `userId` to `bookId`; nothing in the app compared it.
- **Notifications and push data:**
  - `goal_id` becomes `subject_id`: the one typed link that is set, else null in the API and `""` in push data.
  - `book` stays the family marker (`'family'` when the notice's book is a family book).
  - The app's notification model, notification opener, push-tap payload (`type|subject_id|book`) and FCM handling rename `goalId` to `subjectId`.
- **Notification responses** keep `user_id`: it is the recipient person.
- **Deploying:** the backend and the owner's app are updated together. An old app build stops working against the new backend.

### Testing

- **Migration test:** upgrade a database seeded with personal data, a family with entries, a transfer pair, budgets, goals, insights, custom insights, chat sessions in both books and AI usage for both. Then assert:
  - every row's book is right;
  - balances and held-for-goals amounts are identical before and after for every book;
  - transfer legs still pair;
  - no `users` row has a book's id.

  Then downgrade, and assert the old shape and the same balances.
- **Personal data stays private:**
  - a member's request in Family mode never returns rows from any personal book;
  - a person's personal book is never readable by another person.

  The family suite already has these, re-pointed to book ids.
- **Ko Toe Pwar's freshness flag:** a write to a book (personal and family) marks that book's `ai_data_stale`, and the chat sees it. Tested for both kinds, because an update that matches no row would fail silently.
- **Deleting a family or an owner's account** works, and that family's AI spend stays in the admin totals.
- **Family auto-create-with-AI budgets:**
  - with a paid owner, the AI is used and its spend is recorded under the family book;
  - with a Free owner, the non-AI amounts are used.
- **Notification links:**
  - every notice type stores its subject in the matching typed column;
  - deleting a goal, budget, transaction, report, invite or family leaves its notices in the list with the link cleared;
  - the API and push carry `subject_id` and `book`, and the app opens the right item from both;
  - the migration maps old rows by type.
- **Ids fail loudly:** a test passes a person's id where a book id belongs to a data helper and expects an empty result or an FK error, never another book's rows.
- **Registration:** a new user has exactly one personal book, and a new family has exactly one family book.
- **Jobs:** the insight, recurring and budget jobs cover personal and family books exactly once each.
- **The full backend suite and `flutter test` pass.** Tests that seeded `transactions.user_id` and similar directly are updated to seed through the book.

## Left to the builder

- Where the personal book id is loaded (see Book resolution).
- Index names beyond "user → book", the migration's revision id and the batching of updates.
- The order of the code changes, provided each step leaves the suite passing.
