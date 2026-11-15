# Book chip in the top bar: design

**Status:** waiting for the owner's approval.
**Builds on:** the family book (`docs/superpowers/specs/2026-11-13-family-book-design.md`).

## Why

The owner dislikes how screens show which book is open:
- Personal screens show just the title ("Budgets").
- Family screens add the family name ("Budgets · Maya's family").
- This is my reading, not stated by the owner: the two modes look lopsided (Personal has no label). Family titles get long and are cut off in Myanmar at phone width. You can only switch books from the dashboard or the side menu.

## Approaches considered

- **A. A book chip in the top bar.** Every book screen has a chip on the right of its top bar that names the open book in both modes; tapping it switches books.
  - Owner's choice.
  - It treats both modes alike, keeps titles short and lets you switch from anywhere.
- **B. A book line under the title.** A small second line names the book; tapping the title switches.
  - Quieter, but it's less obvious that you can tap it, and the top bar gets taller.
- **C. Colour the whole app by book**, plus a slim "Maya's family" strip.
  - You can tell the book apart without reading anything.
  - But it is a bigger visual change, colour alone isn't enough for people who can't tell colours apart, and you still can't switch in place.

## What gets built (A)

### 1. Titles go back to plain
`bookTitle()` and its " · family name" suffix are removed, so every screen title is just its name in both modes.

### 2. The chip
A compact pill in the top bar's actions, before the screen's own icons.

**What it shows:**
- Personal mode: `👤 Personal ▾`
- Family mode: `👪 <family name> ▾`

**Look:** the same icons, colours and pill shape as the dashboard switch, so the two read as one control. It never takes more than about 40% of the bar's width; a long family name ends in "…" (the sheet shows it in full). It shows a lock (instead of "▾") while the family is read-only.

**Which screens show it**, i.e. the screens that show one book's data:
- Transactions
- Budgets
- Goals
- Financial Reports
- Inflow Analytics and Outflow Analytics
- Ko Toe Pwar's insights
- the custom insight report
- Ko Toe Pwar chat

**Where it doesn't show:**
- **Detail and edit screens** (a budget, a goal, editing an entry): an item belongs to one book, so switching there makes no sense. My call; the dashboard switch and the chip on the list screens cover switching.
- **The dashboard:** it keeps its Personal / family segmented switch as it is, and the side menu keeps its switch too.
- **People who aren't in a family:** no chip anywhere, so the app looks as it always did.

**Ko Toe Pwar chat:** its subtitle stops repeating the family name ("Answers about your family book" stays); the chip carries the name.

### 3. Switching from the chip
Tapping the chip opens a small bottom sheet:
- **Title:** "Which book?"
- **Rows:** Personal, and the family's name in full, each with its icon; a tick marks the open book.
- **Picking the other book** switches and reopens the same screen in that book. For example, on Budgets you land on the family's Budgets. This reuses `openInBook`, which already closes the other book's screens before switching, so the other book's data is never on screen. Your place on the screen (scroll position, chosen month, currency filter) resets to that screen's defaults. My call: carrying it across books would show settings that may not fit the other book.
- **Picking the open book** just closes the sheet.

### 4. Words (EN / MY)

| Use | English | Myanmar |
|---|---|---|
| Sheet title | "Which book?" | ဘယ်စာရင်းကို ကြည့်မလဲ |
| Personal label | existing `bookPersonal` | existing `bookPersonal` |
| Chip's screen-reader label | "Book: Personal. Tap to switch" / "Book: <name>. Tap to switch" | Myanmar equivalent |

The new Myanmar text joins the native-speaker review list.

## Goals
- At a glance, every book screen says which book is open, the same way in both modes.
- You can switch books without leaving the screen you're on.
- Titles fit at 360 px in English and Myanmar.

## Non-goals
- No change to how books work, what each book contains, permissions or the backend.
- No change to the dashboard switch, the side-menu switch or the "Adding to: …" chip on a new entry.

## Anti-goals
- The other book's data must never show, even for a moment, after a switch (the rule from the family book).
- The app must not change for people who aren't in a family.

## Left to the builder
- The chip widget's exact sizes and spacing within the top bar (it must not push the screen's own icons off at 360 px).
- How each screen is reopened after the switch (by route name, or by passing the screen to rebuild).
- Tests:
  - the chip shows in both modes and not without a family;
  - tapping it and picking the other book lands on the same screen in that book;
  - the titles carry no family name;
  - the 360 px fit in English and Myanmar;
  - no chip on detail and edit screens.
