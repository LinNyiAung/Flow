# Family Spending Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A "Family spending" screen (side drawer, family members only) showing, month by month, how much of the
family book was spent on each person, with a per-person deep dive.

**Architecture:** Two read-only server endpoints under `/api/family/spending` built on the existing per-person split
(`families/breakdown.py`, refactored to expose each entry's shares), one SQL query per view against the family book
only. Two Flutter screens with injectable loaders (as `ReportsScreen` does), a route and a drawer item.

**Tech Stack:** FastAPI, SQLAlchemy Core (asyncpg), Postgres 16; Flutter with Provider, fl_chart 0.68.

**Spec:** `docs/superpowers/specs/2026-11-21-family-spending-design.md` (read it; it is the authority).

## Global Constraints
- Counting = `families/breakdown.py` rules: outflows only, transfer legs excluded, per-entry floor split at the
  currency quantum (MMK 0 decimals, others 2), leftover to the entry's first listed member (join order), untagged
  entries on Whole family (member_id null), never divided, former members keep rows. Reuse the code; never copy it.
- A month is the calendar month of the entry's own (wall-clock) date. Bounds come from
  `calculate_report_dates(ReportPeriod.CUSTOM, first_day, last_day, user_zone(person))`, exactly as `/breakdown` does.
- Only the family book is read (`books_db.family_book_id(family["id"])`). Nothing from a personal book, ever.
- Access: any active member of the caller's family, via `book: Book = Depends(get_book)` and
  `book.family if book.is_family else await service.family_of(book.person)` (409 `no_family` otherwise). Read-only
  families can still view. No plan check.
- Currency default: `await service.family_currency(family["id"])`; unknown codes fall back to `usd` (as `/breakdown`).
- Month query parameter: `YYYY-MM`; anything else is 422.
- Every new user-visible string in English and Myanmar (`localization_service.dart`). Whole family is shown with the
  app's own string, never the server's `display_name` (as `BreakdownRow.isWholeFamily` does in Reports).
- Ko Toe Pwar (`Mascot`) only on the empty state for a family with no spending at all; never next to figures.
- Commits: message file + `git commit -F`, ending `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`;
  `git checkout -- frontend/linux frontend/macos frontend/windows` before committing.
- Flutter analyze must stay at the 166-info baseline with 0 warnings / 0 errors.

## Review Focus
1. **Reports agreement:** a person's month figure equals the `/api/family/breakdown` row for that month and currency
   (both use the same split). Pinned in Task 1 (`spending: matches the breakdown`).
2. **Personal leak:** a member's personal outflow tagged nowhere near the family must not appear in any response.
   Pinned in Task 1 and Task 2 (`spending: a personal entry never shows`).
3. **Former member / removed placeholder:** months they had spending in still list them, status `former`. Task 1.
4. **Month edges:** an entry on the last day of a month at 23:59 belongs to that month; one on the 1st at 00:00 to the
   next. Task 1 (`spending: month edges`).
5. **Unknown or other family's member_id** on the person endpoint: 404 `not_found`, nothing leaked. Task 2.

---

### Task 1: Server: shares refactor and the month overview

**Files:**
- Modify: `backend/families/breakdown.py` (split `compute` into a reusable per-entry step)
- Modify: `backend/sql/families.py` (`outflow_shares` gains columns; add `spending_firsts`)
- Create: `backend/families/spending.py`
- Modify: `backend/family_routes.py` (new route)
- Test: `e2e/test_family.py` (new section `spending`, added to `SECTIONS`)

**Interfaces:**
- Produces, `families/breakdown.py`:
  `entry_shares(currency: str, shares: List[Mapping], members: List[Mapping]) -> Dict[str, Dict[str, Any]]`:
  entry id -> `{"amount": Decimal, "for": [member_id...], "split": {member_key: Decimal}}` where `member_key` is a
  member id or `None` (Whole family). `compute()` keeps its signature and output and is rewritten to sum these.
- Produces, `sql/families.py`: `outflow_shares(book_id, currency, date_from, date_to)` rows also carry `date`,
  `main_category`, `sub_category`, `description`, `added_by_member_id` (same row grain and order as today).
  `spending_firsts(book_id) -> Dict[str, datetime]`: currency -> earliest outflow date (transfer legs excluded).
- Produces, `families/spending.py`:
  `async def month_overview(family: Mapping, person: Mapping, currency: str, month: date) -> Dict[str, Any]`
  (`month` = the 1st of the month), returning
  `{"currency", "month": "YYYY-MM", "total", "previous_total", "rows": [{"member_id", "display_name", "status",
  "amount", "previous_amount"}], "currencies": [codes sorted], "first_month": "YYYY-MM" | None}`.
  Rows = this month's `compute` rows (same order: largest first, Whole family first on ties); `previous_amount` = that
  key's amount in the previous month, 0.0 if none. `first_month` is for the requested currency.
  Helper `def parse_month(value: str) -> date` (ValueError when not `YYYY-MM` with month 1..12).
- Produces, route: `GET /api/family/spending?month=YYYY-MM&currency=…` (currency optional).

- [ ] **Step 1: Write the failing checks** — new `section_spending()` in `e2e/test_family.py`, set up like
  `section_entries_breakdown` (Mum on Plus creates the family, Dad joins, placeholders Ma Ma and Ko Ko; Loner outside).
  Entries, all dated in 2025 (no interference from today's recurring jobs), MMK unless stated:
  - 2025-03-10: 90,000 for [Ma Ma, Ko Ko]; 50,000 untagged; 20,000 for [Mum]
  - 2025-04-30 23:59: 30,000 for [Ma Ma] (added by Mum); 2025-05-01 00:00: 7,000 for [Ma Ma] (dates sent in the
    wall-clock form the app sends, so they land on those calendar days)
  - 2025-04-20: 12,000 for [Ma Ma], sub-category Snacks, **added by Dad** (used by Task 2)
  - 2025-04-15: $10.00 USD for [Ma Ma, Ko Ko, Dad]
  - a Mum **personal** outflow 2025-04-15, 999,999 MMK (no `X-Book`)
  - a family transfer leg in April (Mum moves 100,000 into the family wallet)
  Checks (each a `check(...)` with these names):
  - `spending: April MMK` → `GET /api/family/spending?month=2025-04&currency=mmk` is 200 with total 42,000,
    previous_total 160,000, rows `[(mama, 42000.0, previous 45000.0)]` (Whole family, Ko Ko and Mum are absent: no
    April MMK spending); currencies `["mmk", "usd"]`; first_month `"2025-03"`.
  - `spending: month edges` → May has Ma Ma 7,000; April's figure excludes it.
  - `spending: matches the breakdown` → for March and April (MMK and USD), every row amount equals the
    `/api/family/breakdown` row for the month's first..last day.
  - `spending: USD split` → April USD rows are 3.34 / 3.33 / 3.33 (leftover to the first in join order), total 10.0.
  - `spending: a personal entry never shows` → no response amount or total includes 999,999; transfer legs excluded.
  - `spending: former` → after Dad leaves, April USD still lists Dad with status `former`. (Keep this check last in
    the section: Task 2's checks go before it, while Dad is still a member.)
  - `spending: default currency` → no `currency` → the family's currency (`mmk` here: Mum's default is set to MMK in
    setup with `PUT /api/auth/me` `default_currency` as `section_family_currency` does).
  - `spending: errors` → `month=2025-13` and `month=2025-4` and `month=abc` are 422; Loner gets 409 `no_family`;
    a month with nothing is total 0, rows `[]`.
  - `spending: any member` → Dad (with and without `X-Book: family`) gets the same April body as Mum.
- [ ] **Step 2: Run it, expect failures** — with the stub server up (`& $RUN -NoSuite`):
  `& $PY e2e\test_family.py spending` → FAIL (404 on the route), and `breakdown_rounding` / `entries_breakdown` still
  pass.
- [ ] **Step 3: Implement** `entry_shares` (move the per-entry split out of `compute`; `compute` sums it), the extra
  `outflow_shares` columns, `spending_firsts`, `parse_month`, `month_overview` (one `outflow_shares` call spanning the
  previous month's first day to this month's last day, bucketed by `row["date"]` month; bounds per Global
  Constraints) and the route (422 on `parse_month` ValueError).
- [ ] **Step 4: Run** `& $PY e2e\test_family.py spending entries_breakdown breakdown_rounding` → all PASS.
- [ ] **Step 5: Commit** `feat(backend): family spending month overview (/api/family/spending)`.

### Task 2: Server: the person deep dive

**Files:**
- Modify: `backend/families/spending.py`, `backend/family_routes.py`
- Test: `e2e/test_family.py` (`section_spending` grows; same setup)

**Interfaces:**
- Consumes: Task 1's `entry_shares`, `outflow_shares` (with the new columns), `parse_month`.
- Produces: `async def person_month(family, person, currency: str, month: date, member_id: Optional[str]) ->
  Dict[str, Any]` (None = Whole family) and `GET /api/family/spending/person?month=YYYY-MM&currency=…&member_id=…`,
  returning
  `{"currency", "month", "member_id", "display_name", "status", "amount", "previous_amount",
  "categories": [{"main_category", "amount", "sub_categories": [{"sub_category", "amount"}]}],
  "trend": [{"month": "YYYY-MM", "amount"}] (exactly 6, oldest first, ending at `month`),
  "top_entries": [{"id", "date" (ISO date), "main_category", "sub_category", "description", "amount" (the entry's),
  "share" (this person's), "split_between" (number of people it was for; 0 for Whole family)}] (≤ 5),
  "added_by": [{"member_id", "display_name", "count"}]}`.
  Categories and sub-categories sorted by amount desc, then name. Top entries by share desc, then date desc, then id.
  added_by = this month's entries for the person counted per `added_by_member_id`, most first; names from the family's
  members (former included). A member_id that isn't in this family (or doesn't exist) → `service` 404 `not_found`.
  One `outflow_shares` call spanning the trend's first month to `month`'s last day.

- [ ] **Step 1: Write the failing checks** (Task 1's data; inserted before the `spending: former` check):
  - `spending person: Ma Ma April` → amount 42,000 (30,000 + 12,000), previous_amount 45,000; categories
    `[("Food & Daily Living", 42000.0, [("Groceries", 30000.0), ("Snacks", 12000.0)])]`; trend months
    `2024-11..2025-04` with `[0, 0, 0, 0, 45000.0, 42000.0]`; top_entries shares `[30000.0, 12000.0]`, each
    `split_between` 1; added_by `[(Mum, 1), (Dad, 1)]` (tie order: join order).
  - `spending person: shared entry` → Ko Ko in March: one top entry, amount 90,000, share 45,000, split_between 2.
  - `spending person: Whole family` → no `member_id`, March: amount 50,000, display_name "Whole family",
    top entry split_between 0.
  - `spending person: a personal entry never shows` → Mum's person view for April has no 999,999 entry.
  - `spending person: errors` → another family's placeholder id → 404 `not_found`; random id → 404; Loner → 409.
- [ ] **Step 2: Run** `& $PY e2e\test_family.py spending` → the new checks FAIL (404 route).
- [ ] **Step 3: Implement** `person_month` and the route.
- [ ] **Step 4: Run** `& $PY e2e\test_family.py spending entries_breakdown breakdown_rounding` → all PASS.
- [ ] **Step 5: Commit** `feat(backend): family spending per-person deep dive`.

### Task 3: App: the month overview screen, route and drawer item

**Files:**
- Create: `frontend/lib/models/family_spending.dart`
- Modify: `frontend/lib/services/api_service.dart` (two calls next to `getFamilyBreakdown`)
- Create: `frontend/lib/screens/family/family_spending_screen.dart`
- Modify: `frontend/lib/main.dart` (`_routes`: `'/family-spending'`), `frontend/lib/widgets/app_drawer.dart`,
  `frontend/lib/services/localization_service.dart`
- Test: `frontend/test/family_spending_test.dart`

**Interfaces:**
- Consumes: Task 1's response shape (and Task 2's for the models).
- Produces, models (all `fromJson`, tolerant like `FamilyBreakdown`): `FamilySpendingOverview {Currency currency;
  DateTime month; double total, previousTotal; List<FamilySpendingRow> rows; List<Currency> currencies; DateTime?
  firstMonth}`, `FamilySpendingRow {String? memberId; String displayName; String status; double amount,
  previousAmount; bool get isWholeFamily; bool get isFormer}`, and for Task 4: `FamilyPersonSpending`,
  `CategorySpending {String mainCategory; double amount; List<SubCategorySpending> subCategories}`,
  `SubCategorySpending`, `MonthAmount {DateTime month; double amount}`, `SpendingEntry {String id; DateTime date;
  String mainCategory, subCategory; String? description; double amount, share; int splitBetween}`,
  `AddedByCount {String memberId, displayName; int count}`. Months parse from `YYYY-MM` to the 1st (local DateTime).
- Produces, API: `ApiService.getFamilySpending(DateTime month, {Currency? currency})` and
  `ApiService.getFamilyPersonSpending(DateTime month, {String? memberId, Currency? currency})`, month sent as `YYYY-MM`.
- Produces, screen: `FamilySpendingScreen({FamilySpendingLoader? loader, PersonSpendingLoader? personLoader,
  DateTime Function()? now})` with `typedef FamilySpendingLoader = Future<FamilySpendingOverview> Function(DateTime
  month, {Currency? currency})` (and `PersonSpendingLoader` matching the person call, passed on to Task 4's screen).
- Produces, change label helper (used by Task 4 too) in the same file: `String? spendingChange(AppLocalizations l,
  double amount, double previous)` → `null` when both 0, `l.familySpendingNew` when previous is 0, else
  `"▲ 40%"` / `"▼ 10%"` / `"0%"` (rounded whole percent of previous).

- [ ] **Step 1: Write the failing widget tests** (fake loaders; `now` fixed at 2025-04-18):
  - `opens on the current month and lists rows largest first` → title area shows "April 2025"; rows Whole family (app
    string, not the server's), Ma Ma, Mum in loader order with amounts formatted by `formatMoney`; share percentages
    of the total; Ma Ma shows "▲ 40%", a row with previous 0 shows the "New" string.
  - `month arrows move and stop at the bounds` → next is disabled on the current month; previous stops at
    `firstMonth`; each move calls the loader with that month.
  - `currency picker lists only currencies with spending` → picking USD reloads with `currency: Currency.usd`.
  - `a former member is marked former`.
  - `empty month vs no spending at all` → a month with rows `[]` but currencies non-empty shows the plain "no family
    spending this month" text and no `Mascot`; currencies empty shows the `Mascot` empty state.
  - `tapping a row opens the person screen` (pushes Task 4's screen; until Task 4 lands, assert the push with a
    `NavigatorObserver`).
  - `drawer shows Family spending only in a family` → `AppDrawer` with a `FamilyProvider` whose `inFamily` is false
    has no item; true has it, and tapping goes to `/family-spending`.
  - Myanmar: every new getter is non-empty and differs from English (the pattern in `custom_insights_screen_test`).
- [ ] **Step 2: Run** `flutter test test/family_spending_test.dart` → FAIL (missing files).
- [ ] **Step 3: Implement** models, API calls, screen (HeroCard-style total with the change vs last month, rows with a
  `ProgressMeter` share bar), the route, the drawer item (`Icons.family_restroom_rounded`, after Reports, shown when
  `Provider.of<FamilyProvider?>(context)?.inFamily == true`), and the strings: `familySpending` "Family spending" /
  Myanmar, `familySpendingTotal` "Spent on the family", `familySpendingVsLast` "vs {month}", `familySpendingNew` "New",
  `familySpendingNoneThisMonth`, `familySpendingNoneYet`, `familySpendingWholeFamily` (reuse the Reports string if
  one exists), `familySpendingFormer` (reuse if one exists).
- [ ] **Step 4: Run** `flutter test test/family_spending_test.dart` → PASS; `flutter analyze` → 166 infos, 0 warnings.
- [ ] **Step 5: Commit** `feat(app): Family spending screen (month overview) in the side drawer`.

### Task 4: App: the person deep dive screen

**Files:**
- Create: `frontend/lib/screens/family/family_person_spending_screen.dart`
- Modify: `frontend/lib/screens/family/family_spending_screen.dart` (row tap pushes it),
  `frontend/lib/services/localization_service.dart`
- Test: `frontend/test/family_spending_test.dart` (new group)

**Interfaces:**
- Consumes: Task 3's models, `PersonSpendingLoader`, `spendingChange`.
- Produces: `FamilyPersonSpendingScreen({required DateTime month, required Currency currency, String? memberId,
  required String displayName, required PersonSpendingLoader loader})`.

- [ ] **Step 1: Write the failing widget tests** (fake loader):
  - `shows the person's month and change` → name (Whole family via the app string), amount, change label.
  - `categories largest first, expand to sub-categories` → main rows in order; tapping one shows its sub-categories.
  - `trend shows six bars, the selected month last` → a `BarChart` with 6 groups, values from the loader.
  - `biggest entries show share and split` → an entry with splitBetween 3 shows "shared with 2 others" (Myanmar
    string too); splitBetween 0 or 1 shows no split line; entries are not tappable (no `InkWell`/`onTap`).
  - `added by line` → "Added by Mum (6), Dad (2)" built from `AddedByCount`s.
  - `load error shows retry` → the loader throws `ApiException('x')`; a retry button calls it again.
  - Myanmar getters non-empty and different.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** the screen (`fl_chart` `BarChart` for the trend, month labels via `DateFormat.MMM`
  in the app locale; categories as expandable rows; strings `familySpendingByCategory`, `familySpendingTrend`,
  `familySpendingBiggest`, `familySpendingSharedWith(n)`, `familySpendingAddedBy(list)`).
- [ ] **Step 4: Run** `flutter test` (whole suite) → all pass; `flutter analyze` → baseline.
- [ ] **Step 5: Commit** `feat(app): Family spending person deep dive`.

### Final verification (after Task 4)
- Full backend suite (`& $RUN`), whole `flutter test`, `flutter analyze`.
- Browser check on the local stub with seeded e2e accounts: a family with entries in two months; drawer item visible
  only for the family member; numbers equal the Reports "Who we spent on" section for the same month.
