# Family spending screen: design

## Intent
The family book answers "how much did we spend?" everywhere already: dashboard, analytics, reports. It answers "who
did we spend it on?" only as one list at the bottom of Reports ("Who we spent on", `GET /api/family/breakdown`). The
owner wants a screen built around **the people the money was spent on**: each month, how much went on each family
member (and on the whole family), and a deep dive into one person that no other screen gives: what was spent on them,
on what, how it changes month to month.

It is for parents looking back over a month ("Thida cost us 40% more than last month: what was it?") and keeping an
eye on each person over time.

## Goals
- **Month by month:** one calendar month at a time, with previous / next month.
- **On whom:** spending per person it was for, largest first, with each person's change against the previous month.
- **Whole family apart:** spending tagged to nobody stays on its own "Whole family" row. It is never divided among the
  members and never added to anyone's figure (owner's decision).
- **Person deep dive:** tap a person (or Whole family) for: what was spent on them this month by category, their last
  6 months as a trend, their biggest entries this month, and, as a small secondary line, who added the entries for them.
- **Only for families:** an item in the side drawer, shown only to a person who is in a family.

## Non-goals
- **Who spent / who paid.** The app records who *added* an entry, not who paid. The owner chose to focus on whom; the
  only "who" on this screen is the small "added by" line in the deep dive. No "Paid by" field is added.
- **A "full cost" estimate** (a person's figure plus a share of Whole family). Rejected by the owner: figures are only
  what was tagged.
- Income, transfers, budgets and goals per person. (Transfers into the family wallet per member exist on the server,
  `transfer_totals`, but are not part of this screen.)
- Custom date ranges, a yearly view, exporting, Ko Toe Pwar commentary on this screen.
- Several currencies on screen at once.

## Anti-goals (a failure even if everything else works)
- **A leak:** anything from a member's Personal book (entries, totals, categories) appears on this screen or in its
  responses. Only the family book is read.
- **Numbers that disagree:** a person's monthly figure differs from the Reports "Who we spent on" row for the same
  month and currency.
- **Lost people:** a member who left, or a removed placeholder, disappears from months they had spending in.

## Constraints
- Counting rules are the existing ones (`backend/families/breakdown.py`, family-book spec "Who it was for"):
  outflows only; transfer legs excluded; an entry for n people adds amount / n to each, rounded per entry at the
  currency's precision (MMK whole kyat, others cents) with the leftover on the first listed member (ruling R11); an
  untagged entry goes to Whole family; former members keep their rows. This screen must reuse that code, not copy it.
- Entry dates are wall-clock dates as entered (calendar-dates project): a month is the calendar month of the entry's
  own date. No timezone conversion.
- One currency at a time, defaulting to the family's currency (`service.family_currency`, the owner's default
  currency), as `/api/family/breakdown` does.
- Every active account member can view it, admins and members alike, and also while the family is read-only (owner's
  plan lapsed): it only reads. No plan check beyond being in a family (joining is free on any plan).
- English and Myanmar text for everything new. Ko Toe Pwar placement rules apply (empty state only when the family
  truly has no spending at all; not on the figures).

## Approaches
- **A. A new screen with its own server endpoints (chosen).** Extend the breakdown on the server to return, per
  person, the month's amount, the previous month's amount, categories, a 6-month trend and the biggest entries. Fast
  (one request per view), and the splitting rules stay in one place so Reports and this screen always agree. Costs the
  most: new endpoints, their tests and a new screen.
- **B. A new screen built in the app from existing requests.** No server change, but 7+ requests per view, and the app
  would need its own copy of the splitting and rounding rules (drift risk); the transaction list can't filter by "for
  whom" anyway. Rejected.
- **C. Grow the Reports section.** Smallest change, but it stays at the bottom of a long report and follows the
  report's date range, not months. Works against the person-focused, monthly intent. Rejected.

The owner picked A, opened from the side drawer.

## The screen (owner's decisions, with Claude's calls marked)
**Overview** (one month):
```
 ◀  November 2026  ▶                          MMK ▾
 Spent on the family: 1,240,000 (▲12% vs Oct)

 Whole family   610,000  ████████████  49%
 Thida          340,000  ███████       27%  ▲ 40%
 Mya            180,000  ████          15%
 Ko Ko          110,000  ██             9%  ▼ 10%
```
- Rows: Whole family and every person with spending in the month, largest first (the breakdown's order). The share
  bar and percentage are of the month's total. The change is against the same person's previous month; no change
  shown when the previous month had nothing for them ("new"). *(Claude's call: "new" label wording.)*
- A former member or removed placeholder is marked "former" (as Reports does).
- People with nothing that month are not listed. *(Claude's call.)*
- Month switcher: back to the family's first month with spending in the selected currency; not past the current
  month. *(Claude's call.)* Opens on the current month.
- Currency picker: the currencies the family book has spending in; default the family's currency. *(Claude's call:
  list only currencies with spending, falling back to the family's currency when none.)*

**Person deep dive** (tap a row; Whole family opens the same view for untagged spending):
- The person's amount this month and its change against last month.
- **By category:** this month's amount per main category (their share of each entry), largest first; a main category
  expands to its sub-categories. *(Claude's call: main categories first, sub-categories on tap.)*
- **Trend:** the 6 months ending at the selected month, one bar per month. *(Claude's call: bars, not a line.)*
- **Biggest entries:** up to 5 of the month's entries for them, by their share: date, description or category, their
  share, and "shared with N others" when it was split. Not tappable: the app has no read-only entry view, and its
  edit screen works on whichever book is switched on, which may be Personal here. *(Claude's call.)*
- **Added by:** one small line, e.g. "Added by Mya (6), Ko Ko (2)".

**Drawer:** a "Family spending" item, shown only when the person is in a family (whatever the Personal / Family
switch says). It always shows the family book, so it does not depend on the switch. *(Claude's call: the item's
name and icon; placement with Analytics / Reports.)*

## The server (Claude's calls; the builder may refine)
- `GET /api/family/spending?month=YYYY-MM&currency=…`: the overview. Response: currency, month, total, previous
  month's total, rows (member_id or null for Whole family, display_name, status, amount, previous_amount), the
  currencies with spending, and the first month with spending.
- `GET /api/family/spending/person?month=YYYY-MM&currency=…&member_id=…` (no member_id: Whole family): categories
  (main with sub-categories), the 6-month trend, the top 5 entries with their share and how many they were split
  between, and the added-by counts.
- Both: any active member of the caller's family; 404-style `no_family` (409, as the family routes do) for someone
  without one. Read only from the family book (`books_db.family_book_id`), never a personal book.
- The per-entry share must come from the same code as `families/breakdown.compute` (refactor it to expose each
  entry's per-person share, then sum), so totals match Reports exactly. The share query (`outflow_shares`) returns
  only id, amount and member; the deep dive needs each entry's date, main / sub category, description and added-by
  member too, so it is extended (or a sibling query added) rather than read per entry.

## What's left to the builder
Exact response shapes and names, the query structure (one query per view is enough at family scale), widget
structure, the drawer icon, chart styling within the app's existing chart widgets, loading and error states following
the app's patterns, and the tests (server e2e checks in the existing style; Flutter widget tests with fake loaders).
