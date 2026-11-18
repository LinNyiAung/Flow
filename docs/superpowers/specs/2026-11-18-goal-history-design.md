# Goal history: design

Schema project #3 of 4, agreed 2026-11-15 and designed 2026-11-18.

**Status:** draft, waiting for the owner's approval.
**Changes:** how a goal's money is stored, plus a new "History" section on the goal screen.

## Intent and why

A goal stores one number, `goals.current_amount`. Every Add or Withdraw overwrites it, so nobody can see when money went in or out, how much it was, or who moved it. The same applies to the initial contribution set when the goal is created.

In a family book any member can add money to a goal and admins can withdraw it, so "who added how much, and when" is a real question for families. Today nothing can answer it.

The owner wants: **who added how much and when, shown on the goal.** *(Owner, 2026-11-18.)*

## Goals

- **A goal's money is a list of entries.** Each Add, Withdraw, initial contribution, or carried-over balance is one row that records:
  - the goal;
  - who did it (in a family book);
  - the signed amount;
  - when it happened.
- **The entries are the only record of a goal's money.** What a goal holds is the sum of its entries. There is no stored total that could disagree with them. *(Owner chose this over keeping a stored total, 2026-11-18: "I want the better option for the app".)*
- **The goal screen shows the history:**
  - a "History" section under "Goal information";
  - newest first, with the latest 10 shown;
  - "Show all" opens the full list.
- **Everything else behaves exactly as today:**
  - balances and "available for goals";
  - the dashboard's held-for-goals amount;
  - goal progress and status (active or achieved);
  - goal notifications and milestones;
  - budgets' goal figures;
  - reports and PDFs;
  - Ko Toe Pwar's chat, insights and custom insights;
  - the admin counts.
- The full backend suite, `flutter test` and `flutter analyze` pass (0 errors and 0 warnings; the 166 existing infos are fine). A browser check of a personal goal and a family goal passes.

## Non-goals

- **Ko Toe Pwar does not use the history yet.** It keeps seeing each goal's total. Using the history (for example "you add about K50,000 a month") is a possible later feature.
- **Reports and PDFs do not list entries.** They keep showing totals.
- **No admin panel change.**
- **No filtering or searching the history,** and no export.
- **No change to the Add/Withdraw sheet,** its rules or its error messages.

## Anti-goals

- **Money must never appear or vanish.**
  - For every book and currency, the balance, "available for goals" and the held-for-goals amount must be identical before and after the migration.
  - The same holds after every Add and Withdraw.
- **History must not be editable.**
  - No entry can be edited or deleted on its own.
  - A mistake is fixed with a Withdraw, which also shows in the list.
  - An entry disappears only when its goal (or its whole book) is deleted.
- **A goal must never go below zero.**
  - Today a CHECK on `current_amount` guarantees it. Without that column, the guarantee is code under the book's money lock (see Constraints) and tests.

## What the person sees

Goal screen, below "Goal information":

```
History
  + K50,000   Maya            18 Nov, 9:14 AM
  − K20,000   Aung (former)   12 Nov, 6:02 PM
  + K100,000  Maya            3 Nov, 8:30 PM
  + K30,000   Started with    1 Nov, 7:05 PM
            Show all (14)
```

- **Amount:**
  - `+` for money added and `−` for money taken out, in the goal's currency.
  - The same money format the goal screen already uses.
- **Who:**
  - Shown in family books only. In a personal book every entry is the owner's, so the name is left out.
  - Names come from family members, the same way transactions show "Added by":
    - a member who left keeps their name, marked as former (the existing `memberRefName` / `familyFormerName` wording);
    - this also covers a member who later deleted their account, since member rows keep `display_name` when `user_id` is cleared.
  - *(This replaces the "Former member" label proposed in conversation. It is my call: it matches how transactions already show people who left, and keeps the real name.)*
  - **Who is recorded:** the member who did it (the request's `book.member`), not the goal's creator or the family owner. For example, an admin's withdrawal records the admin.
  - **Member rows are never hard-deleted while they have goal entries.** Only untagged placeholders are hard-deleted today (`families/service.py` remove-member), and placeholders can't act, so they never have entries. As a safeguard, that delete also checks for goal entries, not just tags, and falls back to marking the member former. *(My call.)*
  - **An entry with no name in a family book** (which should not happen) shows no name, as transactions do.
- **When:** the entry's date and time in the phone's local time, in the format the transactions list uses.
- **Labels by entry kind:**
  - **Added or withdrawn:** the member's name (family book) or nothing (personal book).
  - **Initial contribution at creation:** "Started with". In a family book the creator's name is shown too.
  - **Carried over by the migration:** "Balance before history began". No name and no date: the true dates are unknown, and the date of the last change would mislead. Existing family goals show this as their first row even if members added the money. That's accepted: the past can't be recovered.
- **"Show all (N)"** appears only when there are more than 10 entries. It opens a "Goal history" screen with the same rows, loaded in pages as the person scrolls.
- **A goal with no entries** (created with nothing and never added to) shows a short line, "No money added yet".
- **After an Add or Withdraw,** the section refreshes together with the goal's amount.
- **Loading:** the section loads with its own `GET /history?limit=10` call; the goal response doesn't embed entries. If that call fails, the section alone shows "Couldn't load history" with a retry, and the rest of the goal screen works as usual. *(My call.)*
- **Who can see it:** everyone who can open the goal, including members of a read-only family.
- **New strings** are added in English and Myanmar. The Myanmar ones are marked as needing a native speaker's review.

## Constraints

- **Pre-launch.** Migrations are fine and a short deploy outage is fine *(owner, 2026-11-15)*.
  - Render's data is migrated, not reset, so the money anti-goal applies to it.
  - Take a database snapshot before deploying.
- **No lockstep app release.**
  - The goal API's request and response fields stay the same, including `current_amount`.
  - The history is a new endpoint.
  - The current phone app keeps working against the new backend; it simply doesn't show history until updated.
- **Money is exact.** Entry amounts use the same `MONEY` (NUMERIC) type and cent rounding as goals today.
- **Serialization.** Every goal money movement already runs inside `get_book_money_lock(book.id)`, whose writes commit or roll back together. These run there:
  - inserting an entry;
  - the over-target, available-balance and below-zero checks;
  - the status / `achieved_at` / `updated_at` update.

  The optimistic `update_amount_if_unchanged` guard goes away: the lock already serializes, and there is no amount column left to compare.
- **Stack.** FastAPI, SQLAlchemy Core, asyncpg, Alembic and Postgres on the backend; Flutter with Provider in the app.

## Approaches

| Approach | What it means | Outcome |
|---|---|---|
| **A. Keep `current_amount` and add a history table** | Entries are written in the same transaction as the total. No reader changes, but two records of the same money could drift if a future change writes one without the other. | Considered. |
| **B. Entries only** | Drop `current_amount` and compute each goal's total from its entries. One source of truth. Reads go through `sql/goals.py`, which returns the computed total under the same `current_amount` key, so most callers don't change. | **Chosen by the owner.** |
| **C. Store entries in `transactions`** | Rejected: goal money isn't spent. It would appear in the transactions list and change the balance maths. | Rejected. |

## The design

### Database

**New table `goal_entries`:**

| Column | Type | Notes |
|---|---|---|
| `id` | text PK | uuid4 |
| `goal_id` | text, not null | FK `goals.id` ON DELETE CASCADE |
| `kind` | text, not null | CHECK in `('start', 'add', 'withdraw', 'carried_over')` |
| `amount` | MONEY, not null | signed |
| `added_by_member_id` | text, null | FK `family_members.id` ON DELETE SET NULL; set in family books for `start`, `add`, `withdraw` |
| `created_at` | TS, not null | server default now() |

- **CHECKs on the sign:**
  - `withdraw` is negative;
  - `start`, `add` and `carried_over` are positive;
  - `amount <> 0` and |amount| < 1e16.
- **Indexes:**
  - `(goal_id, created_at DESC, id)` for the list, the counts and the per-goal sums;
  - `added_by_member_id`, as every SET NULL FK has.
- **`goals.current_amount` is dropped,** together with its CHECK.
- **Table name:** `goal_entries` rather than the working name `goal_contributions`, because the table also holds withdrawals. *(My call.)*

### Migration (one Alembic revision)

1. Create `goal_entries`.
2. For every goal with `current_amount > 0`, insert one `carried_over` entry:
   - the amount is `current_amount`;
   - there is no member;
   - `created_at` is the migration time. Every later entry is newer, so the carried-over row always sorts last. The app shows no date for this kind. *(My call: the goal's `updated_at` also moves on name or target edits, so it isn't the date the money moved.)*
3. Drop `goals.current_amount`.

**Downgrade:** re-add the column with default 0, set it to each goal's entry sum, re-add the CHECK, then drop the table. Totals survive a downgrade; the history itself (who, when, kind) is lost. That's accepted for a rollback.

**Goal deletion and balances:** deleting a goal cascades its entries. Nothing else is needed, because balances and "available for goals" are computed live from transactions and goal entries.

**All goal reads go through `sql/goals.py`.** Checked 2026-11-18: no other backend module reads `goals.c.current_amount` or queries `goals` directly. Every other `current_amount` hit reads the dict key that `sql/goals.py` returns. The e2e tests that seed or read `current_amount` directly need updating.

### Backend

- **`sql/goals.py`**
  - **Reads:** `get_goal` and `list_goals` return `current_amount` computed as the sum of the goal's entries (0 when there are none), as a float, exactly as now.
  - **Held amounts:** `allocated_by_currency` sums entries joined to their book's goals.
  - **Removed:** `update_amount_if_unchanged` and `"current_amount"` in `_MONEY_FIELDS`. `insert_goal` and `update_goal` no longer accept `current_amount`.
- **New `sql/goal_entries.py`**
  - `add_entry(goal_id, kind, amount, added_by_member_id)`.
  - `list_entries(goal_id, limit, offset)`, newest first, ties broken by id.
  - `count_entries(goal_id)`.
- **`goal_routes.py`**
  - **Create:**
    - inserts the goal;
    - if `initial_contribution > 0`, adds a `start` entry, with the creator's member id in a family book;
    - both happen inside the money lock.
  - **Contribute:** computes the current sum inside the lock, runs the same checks with the same messages, adds an `add` or `withdraw` entry, then updates status, `achieved_at` and `updated_at`.
  - **Update** (target change that flips status): reads the computed amount, otherwise unchanged.
  - **Delete:** unchanged. The entries cascade, and `returned_amount` is the computed sum read before deleting.
  - **New `GET /api/goals/{goal_id}/history?limit=10&offset=0`:**
    - returns `{ "entries": [...], "total": N }`;
    - each entry is `{ id, kind, amount, created_at, added_by }`, where `added_by` is `{ member_id, display_name }` or null;
    - this is the same `AddedBy` shape transactions use, and names come from `families_db.list_members` as transactions do;
    - `limit` is 1..50 (default 10) and `offset` ≥ 0;
    - 404 for a goal not in the request's book;
    - readable by anyone who can read the book.
- **Every other reader** of `current_amount` keeps working unchanged, because the key is still there:
  - budgets, notifications, insights, chat, reports;
  - `get_book_balance`;
  - admin counts, custom insights.

### App

- **New model** `GoalEntry`: kind, signed amount, `createdAt`, `addedBy` as `FamilyMemberRef?`.
- **New calls:**
  - `ApiService.getGoalHistory(goalId, limit, offset)`;
  - a matching method in `GoalProvider`, or a small dedicated loader. *(Builder's choice.)*
- **`goal_detail_screen.dart`:**
  - the "History" section, as sketched;
  - it reloads after a successful Add/Withdraw and on pull-to-refresh.
- **New "Goal history" screen:** the full list with paging (50 per page).
- **Strings** for the section title, "Started with", "Balance before history began", "No money added yet", "Show all ({n})" and the screen title.

## Tests

- **Migration test.** Seed goals with amounts 0, a whole number, and cents, in personal and family books and two currencies. Upgrade, then assert:
  - every goal's computed amount equals its old `current_amount`;
  - each non-zero goal has exactly one `carried_over` entry;
  - balances and held-for-goals amounts are identical per book and currency;
  - a downgrade restores the column with the same values.
- **Contribute** writes exactly one entry with the right kind, sign and member, or none on every refusal: over target, insufficient balance, below zero, zero amount, achieved goal, non-admin withdraw.
- **Create** with and without an initial contribution: a `start` entry or none.
- **Concurrency:** two Adds racing for the same available balance. One succeeds, one is refused, and entries match the total.
- **Delete** removes the entries and returns the right amount.
- **History endpoint:**
  - order and paging, including ties at the same second;
  - `total`;
  - names in family books, including a former member;
  - removing a placeholder member keeps it (as former) when it has goal entries;
  - the carried-over entry sorts below entries added after the migration;
  - `added_by` null in personal books;
  - 404 across books;
  - a read-only family member can read it.
- **App:** model parsing; the section's rows and labels for each kind, family and personal; "Show all" only above 10; refresh after Add/Withdraw.

## Left to the builder

- Query shape for the computed sum (correlated subquery, LATERAL or grouped join), as long as list reads stay one query.
- Exact widgets and spacing, following the goal screen's existing cards.
- Whether the history loader lives in `GoalProvider` or beside the screen.
