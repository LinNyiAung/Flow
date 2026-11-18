# Goal History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A goal's money becomes a list of entries (who, how much, when). The goal screen shows that history, and the goal's total is computed from the entries.

**Architecture:**
- A `goal_entries` table replaces `goals.current_amount`.
- `sql/goals.py` computes `current_amount` as the sum of the goal's entries and returns it under the same key, so every reader outside the goal routes is untouched.
- The goal routes write entries inside the existing book money lock.
- A new `GET /api/goals/{goal_id}/history` serves the list.
- The app adds a History section to the goal screen and a full "Goal history" screen.

**Tech Stack:**
- Python 3.12, FastAPI, SQLAlchemy Core + asyncpg, Alembic, PostgreSQL 17 (local e2e cluster).
- Flutter (Provider).
- e2e Python scripts in `e2e/`.

**Spec:** `docs/superpowers/specs/2026-11-18-goal-history-design.md`

## Global Constraints

**`goal_entries` table**

| Column | Rule |
|---|---|
| `id` | text uuid4, PK |
| `goal_id` | text NOT NULL, FK `goals.id` ON DELETE CASCADE |
| `kind` | text NOT NULL, CHECK `kind IN ('start','add','withdraw','carried_over')` (name `kind`) |
| `amount` | `MONEY` NOT NULL, signed |
| `added_by_member_id` | text NULL, FK `family_members.id` ON DELETE SET NULL |
| `created_at` | `TS` NOT NULL, server default `now()` |

- **Sign CHECK** (name `amount_sign`): `(kind = 'withdraw' AND amount < 0) OR (kind <> 'withdraw' AND amount > 0)`.
- **Size CHECK** (name `amount_finite`): `amount > -1e16 AND amount < 1e16`.
- **Indexes:**
  - `ix_goal_entries_goal_created` on `(goal_id, created_at, id)`;
  - `ix_goal_entries_added_by_member_id` on `added_by_member_id`.
- **`goals.current_amount` and its CHECK `current_non_negative_finite` are dropped.**

**Migration**
- File: `backend/alembic/versions/20261118_c1f0a8e2d93b_goal_entries.py`.
- Revision `c1f0a8e2d93b`, down_revision `7e3a91c4d5b8`.
- **Upgrade:** for every goal with `current_amount > 0`, insert one entry with:
  - `kind 'carried_over'` and `amount = current_amount`;
  - no member;
  - `created_at = now()`.

  Then drop the column.
- **Downgrade:**
  - re-add `current_amount MONEY NOT NULL DEFAULT 0`;
  - set it to the entry sum per goal;
  - re-add the CHECK;
  - drop the table.

**Who an entry records**
- In a family book: the acting member (`book.member["id"]`) for `start`, `add` and `withdraw`.
- In a personal book: NULL.
- `carried_over` entries always have NULL.

**API**
- `GET /api/goals/{goal_id}/history?limit=10&offset=0`:
  - `limit` 1..50 (default 10) and `offset` ≥ 0; anything else is a 422;
  - 404 `"Goal not found"` for a goal not in the request's book;
  - readable by anyone who can read the book (read-only families included).
- **Response:** `{"entries": [{"id", "kind", "amount", "created_at", "added_by"}], "total": N}`:
  - `amount` is signed;
  - `added_by` is `{"member_id", "display_name"}` (the existing `AddedBy` model) or null.
- **Order:** `created_at` DESC, then `id` DESC.
- **Goal responses don't change.** Every goal endpoint keeps the same request and response fields, `current_amount` included. Its messages and status codes don't change, except that the contribute endpoint's 409 "concurrent modification" path goes away.

**Money**
- All amounts are exact `MONEY`.
- A goal's `current_amount` is the sum of its entries (0.0 with none), returned as a float.
- Create and contribute take `get_book_money_lock(book.id)`. The entry insert and the goal status update happen inside it, so they commit together.

**App**
- Section title `History`, under "Goal information".
- Newest first, latest 10.
- `Show all ({n})` only when total > 10.
- **Row:**
  - the amount as `+`/`−` (U+2212) followed by `formatMoney(abs, currency)`;
  - the member name in family books only, via `memberRefName`;
  - local time `DateFormat('d MMM, h:mm a')`.
- **Labels:**
  - `start` → "Started with";
  - `carried_over` → "Balance before history began", with no name and no date.
- **Empty:** "No money added yet".
- **Load failure:** "Couldn't load history" with a retry. The rest of the screen is unaffected.
- **Full screen:** "Goal history", 50 per page, loading more as the person scrolls.
- **New strings:** English plus Myanmar. Each Myanmar string carries the comment `// needs native review`.

**Release and environment**
- The old app keeps working: there are no breaking API changes.
- Windows PowerShell only (Git Bash is broken).
- Commits: write the message to a UTF-8 no-BOM file and run `git commit -F`. The message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Local throwaway DB and stub server only; never production or real keys. Never read or print `.env*`. Keep CRLF in CRLF files.

**Commands used throughout:**
- `$S` = `C:\Users\LINNYI~1\AppData\Local\Temp\claude\C--projects-Flow\88f449c7-2e35-4a07-890d-5a91aa9c3948\scratchpad`
- `$PY` = `$S\venv_final\Scripts\python.exe`
- `$PGBIN` = `$S\pg_dl\srv\pgsql\bin`
- Start Postgres if it is down:
  `Start-Process -FilePath "$PGBIN\pg_ctl.exe" -ArgumentList '-D','C:\projects\Flow\e2e\.data\pg','-o','"-p 54329 -c listen_addresses=127.0.0.1 -c timezone=UTC"','-l','C:\projects\Flow\e2e\logs\postgres.log','start' -WindowStyle Hidden`
- `$RUN` = `$S\pg\run_suite.ps1`.
  - `& $RUN -NoSuite` resets the DB to head and starts the stub on 127.0.0.1:8765.
  - `& $RUN` runs the full backend suite, writing `$S\backend_suite.out`.
- One e2e file: `cd C:\projects\Flow\e2e; $env:PYTHONIOENCODING='utf-8'; $env:E2E_FAKE_AI='1'; & $PY -u test_goal_history.py [sections]`. Expected: no `[BUG]`/`[FAIL]` lines, exit 0. Reset with `-NoSuite` before each re-run.
- Flutter: `cd C:\projects\Flow\frontend; C:\flutter\bin\flutter.bat test` and `... analyze`. `analyze` exits 1 on infos. Pass means 0 errors, 0 warnings, and no new infos (166 exist today).

## Review Focus

1. **Cent amounts:**
   - `0.10 + 0.20` must hold exactly `0.30`;
   - adding exactly the remaining cents must flip the goal to achieved;
   - test in Task 1 (`money` section).
2. **Withdrawing everything:**
   - the goal holds `0.0`, is active again, and keeps both entries;
   - the dashboard's held amount drops to 0;
   - test in Task 1.
3. **Editing the target after entries exist:**
   - lowering it to the held sum makes the goal achieved;
   - raising it makes it active again, using the computed sum;
   - test in Task 1.
4. **A read-only family member:**
   - can read the history (200);
   - an Add attempt is refused and writes no entry;
   - test in Task 2.
5. **Paging past the end:**
   - `offset` ≥ total returns `entries: []` with the right `total`;
   - the app's "Goal history" screen stops loading at the end;
   - tests in Task 2 and Task 3.

---

### Task 1: Entries replace `current_amount` (schema, migration, money paths)

**Files:**
- Modify: `backend/sql/tables.py` (the `goals` table and new `goal_entries`).
- Create: `backend/alembic/versions/20261118_c1f0a8e2d93b_goal_entries.py`.
- Create: `backend/sql/goal_entries.py`.
- Modify:
  - `backend/sql/goals.py`: computed reads; remove `update_amount_if_unchanged` and `current_amount` from `_MONEY_FIELDS`.
  - `backend/goal_routes.py`: create ~36-112, update ~207-263, contribute ~266-393, delete ~395-424.
- Modify existing e2e that touch the column directly:
  - `e2e/test_books.py:184-188` `_goal_totals`: at head, sum `goal_entries` joined to `goals` by `book_id`. The pre-books `user_id` shape still reads `current_amount`, because that path runs at the old revision.
  - `e2e/plans_custom_insight_checks.py:1257`: insert an `add` entry of 50 instead of `UPDATE goals SET current_amount`.
- Create: `e2e/test_goal_history.py`, with sections `schema`, `migration`, `money` (this task) and `history` (Task 2). Follow `e2e/test_books.py`:
  - a `check()` that prints `[PASS]`/`[BUG]`;
  - a `SECTIONS` dict;
  - `test_plans.alembic` for migrations.
- Modify: `e2e/run_backend_suite.py`, adding `"test_goal_history"` to `SUITES`.

**Interfaces:**
- **Produces** `sql/goal_entries.py`:
  - `async add_entry(goal_id: str, kind: str, amount, added_by_member_id: Optional[str]) -> None`;
  - `async list_entries(goal_id: str, limit: int, offset: int) -> List[dict]`: `_id`, `goal_id`, `kind`, `amount` (float), `added_by_member_id`, `created_at`; ordered `created_at` DESC, `id` DESC;
  - `async count_entries(goal_id: str) -> int`;
  - `async member_has_entries(member_id: str) -> bool`.
- **Produces** `sql/goals.py`:
  - `get_goal`, `list_goals` and `update_goal` return dicts carrying `current_amount: float` (the entry sum);
  - `allocated_by_currency` sums entries;
  - `list_goals` stays one query.
- **Produces** `KIND_START, KIND_ADD, KIND_WITHDRAW, KIND_CARRIED_OVER` constants in `sql/goal_entries.py`.

- [ ] **Step 1: Write the failing tests** in `e2e/test_goal_history.py`
  - **`schema`:**
    - `goal_entries` has exactly the columns in Global Constraints;
    - `goals` has no `current_amount`;
    - each CHECK refuses its bad row: a `withdraw` with a positive amount, an `add` with a negative one, an `add` of 0, and kind `'gift'`;
    - deleting a goal deletes its entries;
    - deleting a `family_members` row sets the entry's `added_by_member_id` to NULL.
  - **`migration`:**
    - downgrade to `7e3a91c4d5b8`;
    - seed goals through SQL in two people's personal books and one family book: `current_amount` 0, 250, 12.34 and 999.99 in `usd` and `mmk`;
    - record each book's per-currency held sum;
    - upgrade to head, then assert:
      - each non-zero goal has exactly one `carried_over` entry equal to its old amount, with a NULL member;
      - zero goals have no entry;
      - per-book held sums are identical;
      - `GET /api/goals` for a seeded person returns the same `current_amount` values;
      - `GET /api/dashboard/balance?currency=`'s `available_balance` equals inflow − outflow − held;
    - downgrade: the column is back with the same values;
    - upgrade again and assert the same;
    - leave the DB at head.
  - **`money`:**
    - **Create:** with `initial_contribution` 30, one `start` entry of 30; without it, no entry.
    - **Contribute:**
      - +50 writes one `add` 50;
      - −20 writes one `withdraw` −20;
      - `current_amount` follows.
    - **Refusals** write no entry and keep their exact status and message: over target, insufficient balance, below zero, zero amount, achieved goal, and a family member's withdraw (403).
    - **Cents** (Review Focus 1): 0.10, then 0.20 → `current_amount == 0.30`. A goal with target 1.00 holding 0.70 plus 0.30 → status `achieved`.
    - **Withdrawing everything** (Review Focus 2): the goal holds 0.0, is `active` with `achieved_at` null, has two entries, and the summary `total_allocated` is 0.
    - **Target edit** (Review Focus 3): holding 100, set target 100 → `achieved`; set target 150 → `active`.
    - **Family:** `start`, `add` and `withdraw` record the acting member's id; personal entries record NULL.
    - **Concurrency:** balance 100 available; two parallel `+100` adds to two goals → exactly one 200 and one 400 "Insufficient balance". The entry sums equal the goals' totals.
    - **Delete:** a goal holding 80 → `returned_amount == 80`, its entries are gone, and the available balance rises by 80.

- [ ] **Step 2: Run them; they fail.**
  - `& $RUN -NoSuite`, then `& $PY -u test_goal_history.py schema migration money`.
  - Expected: `[BUG]` lines (no table yet).

- [ ] **Step 3: Implement the table, the migration, `sql/goal_entries.py` and the computed reads in `sql/goals.py`.**
  - The computed sum is a correlated scalar subquery, or a grouped LEFT JOIN, labelled `current_amount`.
  - `update_goal` returns the same computed shape.

- [ ] **Step 4: Switch `goal_routes.py` to entries.**
  - **Create:** insert the goal and, if `initial > 0`, a `start` entry, both inside the lock. The member is set only when `book.is_family`.
  - **Contribute:** inside the lock:
    - read the goal (computed amount);
    - run the same checks;
    - `add_entry(KIND_ADD or KIND_WITHDRAW, amount, member)`;
    - `update_goal(status, achieved_at, updated_at)`.

    Drop the 409 branch and `update_amount_if_unchanged`.
  - **Update and delete:** use the computed `current_amount` and are otherwise unchanged.

- [ ] **Step 5: Fix the two existing e2e files listed above. Then run the new sections plus `test_books.py migration` and `test_api.py`.**
  - Expected: all PASS, exit 0.
  - Then `& $RUN`. Expected: every suite exits 0 and `== problems` is empty.

- [ ] **Step 6: Commit** with the message `feat(backend): goal money is a list of entries; current_amount is their sum`.

### Task 2: History endpoint and member-delete guard

**Files:**
- Modify: `backend/goal_models.py`, adding `GoalEntryResponse` (`id`, `kind`, `amount: float`, `created_at`, `added_by: Optional[AddedBy]`) and `GoalHistoryResponse` (`entries`, `total`).
- Modify: `backend/goal_routes.py`, adding `GET /{goal_id}/history`.
  - Names come from `families_db.list_members(book.family["id"])` when `book.is_family`, the same way `transaction_routes._entry_people` gets them.
  - An id with no member row gives `added_by` null.
- Modify: `backend/families/service.py:307-311`. A placeholder is hard-deleted only when `not has_tags` **and** `not goal_entries_db.member_has_entries`; otherwise the existing `set_former` branch runs.
- Test: `e2e/test_goal_history.py`, section `history`.

**Interfaces:**
- **Consumes** `goal_entries.list_entries`, `count_entries` and `member_has_entries` from Task 1.
- **Produces** the HTTP contract in Global Constraints → API. The app (Task 3) parses it.

- [ ] **Step 1: Write the failing tests** (section `history`)
  - **Order:** 12 entries → the default call returns 10, newest first, with `total == 12`.
  - **Paging:**
    - `limit=5&offset=10` returns the 2 oldest;
    - `offset=12` returns `entries == []` and `total == 12` (Review Focus 5).
  - **Limits:** `limit=0`, `limit=51` and `offset=-1` → 422.
  - **Not found:** another book's goal → 404 `"Goal not found"`.
  - **Personal book:** every `added_by` is null.
  - **Family book:**
    - `added_by.display_name` is the adder's name;
    - after that member leaves the family, the same entry still returns their `display_name`;
    - the `carried_over` entry (seeded by SQL) has `added_by` null and sorts last.
  - **Read-only family** (Review Focus 4):
    - put the family book in read-only state the way `e2e/test_family.py` does;
    - a member's `GET /history` → 200;
    - `POST /contribute` → refused, with the entry count unchanged.
  - **Placeholder guard:**
    - a placeholder member with a goal entry (insert the entry by SQL with that member id);
    - the remove-member endpoint keeps the row as former;
    - the entry's `added_by` still names it;
    - a placeholder with no tags and no entries is still hard-deleted.

- [ ] **Step 2: Run them; they fail** (404 on the route).
  - Command: `& $RUN -NoSuite`, then `& $PY -u test_goal_history.py history`.

- [ ] **Step 3: Implement the models, the route and the guard.**
  - Declare the route before nothing that could shadow it.
  - `limit: int = Query(10, ge=1, le=50)`, `offset: int = Query(0, ge=0)`.

- [ ] **Step 4: Run** `test_goal_history.py` (all sections) and `test_family.py`.
  - Expected: all PASS, exit 0.

- [ ] **Step 5: Commit** with the message `feat(backend): goal history endpoint; placeholders with goal entries are kept as former`.

### Task 3: App: History section and Goal history screen

**Files:**
- Create: `frontend/lib/models/goal_entry.dart`:
  - `enum GoalEntryKind { start, add, withdraw, carriedOver }`, parsed from `start`, `add`, `withdraw` and `carried_over`;
  - `class GoalEntry { String id; GoalEntryKind kind; double amount; DateTime createdAt; FamilyMemberRef? addedBy; }` with `fromJson`;
  - `class GoalHistoryPage { List<GoalEntry> entries; int total; }` with `fromJson`.
- Modify: `frontend/lib/services/api_service.dart`, adding `static Future<GoalHistoryPage> getGoalHistory(String goalId, {int limit = 10, int offset = 0})` beside `contributeToGoal` (~1619). It throws `apiError(response, 'Failed to load goal history')` on non-200.
- Create:
  - `frontend/lib/screens/goals/goal_entry_tile.dart`: `GoalEntryTile(entry, currency, showName)`, one row;
  - `frontend/lib/screens/goals/goal_history_section.dart`: `GoalHistorySection(goal)` with its own loading, error and retry state. It exposes `reload()` through a `GlobalKey<GoalHistorySectionState>`;
  - `frontend/lib/screens/goals/goal_history_screen.dart`: the full list, 50 per page, loading the next page near the end and stopping when `entries.length == total`.
- Modify: `frontend/lib/screens/goals/goal_detail_screen.dart`.
  - Add the section below the "Goal information" card (~828).
  - Call `reload()` after a successful `_contributeToGoal` (~107).
  - Decide family or personal with the same check `edit_transaction_screen.dart:487` uses.
- Modify: `frontend/lib/services/localization_service.dart`. Add these keys to the English map (~300), the Myanmar map (~1583) and the getters (~2870):

  | Key | English | Myanmar draft (`// needs native review`) |
  |---|---|---|
  | `goalHistory` | History | မှတ်တမ်း |
  | `goalHistoryTitle` | Goal history | ရည်မှန်းချက် မှတ်တမ်း |
  | `goalEntryStartedWith` | Started with | စတင်ထည့်ငွေ |
  | `goalEntryCarriedOver` | Balance before history began | မှတ်တမ်းမစမီ လက်ကျန် |
  | `goalHistoryEmpty` | No money added yet | ငွေ မထည့်ရသေးပါ |
  | `goalHistoryShowAll` | Show all ({n}) | အားလုံးကြည့်ရန် ({n}) |
  | `goalHistoryLoadFailed` | Couldn't load history | မှတ်တမ်းကို ဖွင့်၍မရပါ |

  Reuse the existing retry string if there is one; otherwise add `retry` / `ထပ်စမ်းရန်`.
- Test: `frontend/test/goal_history_test.dart`. Fake the HTTP layer with `ApiService.httpClientOverride`, as `fcm_registration_test.dart` does.

**Interfaces:**
- **Consumes** the Task 2 HTTP contract and `FamilyMemberRef.tryParse` / `memberRefName` from `frontend/lib/utils/family_entries.dart`.

- [ ] **Step 1: Write the failing tests**
  - **Parsing:** `GoalEntry.fromJson` handles all four kinds, a negative amount, and `added_by` null and set.
  - **Personal goal:** with entries `add 50000`, `withdraw -20000` and `start 30000`:
    - rows show `+`, `−` and "Started with";
    - no names;
    - the `add` row shows `DateFormat('d MMM, h:mm a')` of its local time.
  - **Family goal:**
    - the adder's name shows;
    - a former member's name shows with the former marking from `memberRefName`.
  - **`carried_over`:** shows "Balance before history began" with no date and no name.
  - **Show all:**
    - `total: 14` → "Show all (14)" is visible, and tapping it opens `GoalHistoryScreen`;
    - `total: 10` → no "Show all".
  - **Empty:** `total: 0` → "No money added yet".
  - **Failure:**
    - a 500 → "Couldn't load history" and a retry, while the goal's amount and the Add button still show;
    - the retry after a 200 shows the rows.
  - **Reload:** after a successful contribute, the history endpoint is called again (count the fake client's calls).
  - **Goal history screen:**
    - with `total: 60`, it requests `offset=0&limit=50`, then `offset=50`, then stops;
    - no third request after scrolling to the end (Review Focus 5).

- [ ] **Step 2: Run them; they fail.**
  - Command: `C:\flutter\bin\flutter.bat test test/goal_history_test.dart`.

- [ ] **Step 3: Implement** the model, the API call, the tile, the section, the screen, the detail-screen wiring and the strings.

- [ ] **Step 4: Run the full checks.**
  - `flutter.bat test`: all pass.
  - `flutter.bat analyze`: 0 errors, 0 warnings, no new infos.

- [ ] **Step 5: Commit** with the message `feat(app): goal history section and screen`.

### After the tasks: final verification (controller)

- **Fresh database:** `dropdb` / `createdb`, `alembic upgrade head`, then `& $RUN`. Every suite exits 0.
- **Flutter:** `flutter test` and `flutter analyze` as in Task 3.
- **Browser check.** Build the web app and serve it, pointing at the stub.
  - **Personal goal:** create it with an initial amount, Add, then Withdraw. The History rows read as in the spec sketch, with no names.
  - **Family goal:** two members each Add. Their names show. "Show all" appears after 11 entries.
