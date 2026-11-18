# Real calendar dates and per-person timezones (schema project #4)

Status: design, 2026-11-18. Owner decisions are marked **(owner)**; calls made by Claude are marked **(Claude's call)**.

## Why

The Postgres migration kept "wall-clock" dates as local time with a UTC label ("fake UTC"):
- transaction dates;
- budget start and end dates;
- goal deadlines;
- repeat dates;
- insight periods.

A 9:00 AM transaction is stored as `09:00+00:00`.

Every "today" on the server comes from one global timezone (`SCHEDULER_TIMEZONE`, default `Asia/Yangon`). That covers reminders, budget periods, repeating transactions, insights, plan limits and custom-insight ranges. Some app screens use the phone's clock instead, and reports use an offset the phone sends.

It works for people in Myanmar. Anyone else sees "today" disagree between screens, and a 12:20 AM Bangkok entry can count as the wrong day in reminders and insights.

Users will be **mostly in Myanmar (owner)**, with some abroad, for example family members working overseas. The project:
- stores dates honestly;
- gives each person their own correct "today";
- changes nothing visible for people in Myanmar **(owner)**.

## Goals

1. **Transactions** (incl. transfers and recurring parents and children) store the local date and time picked on the phone, with no timezone. The value is what the person entered, shown the same on every screen for every family member.
2. **Calendar dates are stored as `DATE`:** budget start and end, goal target date, recurrence end date, the recurrence "last created" pointer, and insight week and month bounds.
3. **Real instants stay real UTC `timestamptz`, unchanged:** `created_at`, `updated_at`, `achieved_at`, goal history entries, plan expiry, notifications and the rest.
4. **Each person has a timezone**, read automatically from the phone. Nobody sets it **(owner)**. Without one, the person is treated as `Asia/Yangon`.
5. **Personal book:** everything that depends on "today" uses the person's timezone. That covers:
   - reminders at their local 9 AM;
   - budget periods and status;
   - repeating transactions;
   - weekly and monthly insights;
   - plan limits;
   - custom-insight ranges;
   - reports and PDFs;
   - AI chat and insight "today";
   - spending pace and "days left".
6. **Family book (owner):**
   - What each member sees or receives follows that member's own timezone: their notifications, their "today" and "this month", and their reports and insights.
   - Things that happen once for the whole book follow the owner's timezone, silently:
     - the budget rollover to the next period;
     - creating the day's repeating transaction;
     - a family budget's active/ended status;
     - family goal-deadline and budget-ending checks (who receives them, and when, is per member).
   - When ownership passes to someone else, the new owner's timezone applies from then on.
   - **Family weekly and monthly insights are once-per-book** **(Claude's call, from the owner's rule above):**
     - They stay one row per book, generated on the owner's clock with the owner's week and month bounds, as they are today.
     - The "insights ready" notice goes to every member when they're generated; it isn't held for each member's morning.
     - Per-member family insights would multiply AI cost and are out of scope.
   - **Family reminders follow each member's own day (owner: "each person gets them at their own 9 AM"):**
     - Goal-deadline and budget-ending reminders are computed and sent in each member's own 9 AM run.
     - The day counts ("ends in N days", 14/7/3/1 days) come from that member's own today, so they match what their phone shows.
     - The duplicate guards become per member and per local day. Today's per-book guards (a goal reminder "sent once any member has it", `budgets.ending_soon_notified`) are replaced.
   - **Event notices aren't scheduled** **(Claude's call):** "budget now active", "budget auto-created" and "insights ready" are sent when the event happens. Only the event's own timing follows the book's clock.
7. **Existing data converts without moving any date or time.** Today's stored values are the phone's wall clock with a UTC label, so dropping the label gives back exactly what each person entered.

## Non-goals

- A timezone setting or picker anywhere in the app **(owner)**.
- Showing other members' local times, or "entered in Bangkok" labels.
- Changing date formats, languages or calendars on screen.
- Admin dashboard changes. It keeps showing real instants as today.
- Recording which timezone a transaction was entered in.

## Anti-goals (failure even if it "works")

- Any existing transaction, budget, goal or repeat date shows a different day or time after the migration.
- A person in Myanmar notices any change in when reminders arrive, when budgets roll over, or which day an entry counts on.
- A reminder, rollover or repeating transaction runs twice for the same local day, or is skipped, including on the day someone's timezone changes or a family changes owner.
- A transaction appears on a different day for two members of the same family book.

## Approaches considered

- **A. Local date-time as entered + calendar `DATE`s + a timezone per person, used only for "today" (chosen).**
  - Matches how people think about money and how banks list transactions: a transaction belongs to a day.
  - It is the smallest honest change, because the app already treats these values as "what the phone showed".
  - Cost: two entries made at the same moment in different timezones may sort slightly out of order. `created_at` keeps the exact moment for anything that needs it.
- **B. Store an exact UTC moment plus the timezone it was entered in.** Every screen and filter must convert back to the entry's local day, which is more code everywhere and more ways for an entry to land on the wrong day for another family member. Rejected.
- **C. Keep the fake-UTC storage and only add per-person timezones.** This is the cheapest, but it keeps the convention this project exists to remove. Rejected.
- **Family book timing (owner):**
  - A configurable family timezone was rejected as too complicated.
  - "Everything per member" can't work for things that happen once per book.
  - The chosen split is: per member for what people see and receive, the owner's timezone for once-per-book events.

## Constraints

- **Pre-launch (owner):** migrations are fine and a short deploy outage is fine. The phone app and backend ship together, so old app versions need not keep working.
- One Alembic migration, with a working downgrade that puts back the fake-UTC labels, so the downgrade loses nothing.
- **Postgres on Render.** Take a DB snapshot before deploying.
- Myanmar has no daylight saving time, but other zones do, so the design must handle DST (see "Scheduled jobs").
- Myanmar is UTC+6:30, and India and Nepal use +5:30 and +5:45, so whole-hour scheduling is not enough.

## Design

### Storage

| Column | Today | After |
|---|---|---|
| `transactions.date` | timestamptz (fake UTC) | `timestamp without time zone`: local date-time as entered |
| `transactions.recurrence_end_date` | timestamptz | `date` |
| `transactions.recurrence_last_created_date` | timestamptz | `date` |
| `budgets.start_date`, `budgets.end_date` | timestamptz (end often 23:59:59.999) | `date`; `end_date` is the inclusive last day |
| `goals.target_date` | timestamptz | `date` |
| `insights.week_start/week_end/month_start/month_end` | timestamptz | `date` |
| `users.timezone` | (none) | `text NULL`, an IANA name such as `Asia/Yangon`; NULL means the default |

- **Migration:** `col AT TIME ZONE 'UTC'` gives the wall-clock timestamp, and `::date` gives the day.
- **Budgets whose stored end is midnight (00:00) keep the date shown** **(Claude's call; the owner noted that only their own pre-launch budgets are affected):**
  - Example: a custom budget shown as "1 Nov – 1 Dec" ends at 1 Dec 00:00 today. It becomes 1 Nov – 1 Dec with 1 Dec fully included, so it gains that day and rolls over a day later.
  - A start time that isn't midnight is widened to the whole start day.
  - From now on, a budget's end date is always its inclusive last day. The custom-budget screen's defaults pick an end date that is included, and the period length is computed in days.
  - The downgrade writes the end back as 23:59:59.999999 of the end day. That is the convention used for monthly and yearly budgets today, so nothing is lost.
- **Downgrade:** reverses this by labelling the values UTC again.
- **Existing constraints and indexes** (budget `dates_ordered`, date indexes) are rebuilt on the new types.
- **Recurring occurrence ids** `"{parent}:{YYYYMMDD}"` don't change, because the local day is identical.

### API shapes

Changing these is allowed under lockstep release **(owner)**.

- **Transaction-style dates** (`date` on transactions, transfers and recurring) are sent and returned as a local ISO date-time with no offset, for example `"2026-11-18T23:40:00"`.
- **Calendar dates** (budget start and end, goal target date, recurrence end, insight bounds, custom-insight range) are sent and returned as `"YYYY-MM-DD"`.
- **Instants keep their UTC ISO form.**
- **Filters:**
  - The transaction list filter takes local date-times or dates and compares them directly. An end given as a date is inclusive of that whole day.
  - Report custom ranges take `"YYYY-MM-DD"`.
  - The reports' `timezone_offset` field is removed; reports use the person's timezone.

### Where a person's timezone comes from

- **The app sends it automatically on every request.** It is the phone's IANA zone name, sent in a header such as `X-Timezone: Asia/Bangkok`.
  - **(Claude's call):** use a small package that reads the IANA name (e.g. `flutter_timezone`), because Dart's `DateTime` only gives an offset or abbreviation.
  - On web the app reads it from the browser.
- **The server validates the name against the tz database.** It ignores a missing or invalid header, saves a valid one to `users.timezone` when it differs, and uses it for that request.
- **Background jobs** use the saved `users.timezone`.
- **Fallback:** a person with no saved timezone gets the default zone, which is the existing `SCHEDULER_TIMEZONE` env var, default `Asia/Yangon` **(Claude's call: reuse it as the default)**.

### "Today" on the server

The single-zone helpers in `tz_utils.py` take a timezone argument:
- `app_today`;
- `app_wall_clock_now`;
- the period ranges;
- `days_until`;
- quota periods.

Callers pass one of:
- **The person's zone** for anything shown to or sent to a person. In a family book, that is the viewing or receiving member.
- **The book's zone** for once-per-book work: the person's zone for a personal book, the current owner's zone for a family book.

### Scheduled jobs

- **Jobs that fire at a local time** run on a short tick instead of one global cron time **(Claude's call: every 15 minutes, which covers the +5:45/+6:30 style offsets)**. These are the 9:00 goal and payment reminders, 08:00 unusual spending, 00:30 budget rollover, 06:00 repeating transactions, and the weekly and monthly insights.
- **Each tick handles the people or books whose local time has reached the job's time today** and that haven't been handled for that local day yet.
- **"Handled" is recorded per person or book and local date.** Each job either reuses its existing duplicate guard (for example notification `reminder_target_date`, recurring occurrence ids, budget claim timestamps) or gains one. The guard makes a job run exactly once per local day, even across:
  - a timezone change;
  - a DST jump;
  - a missed tick;
  - a family owner change.
- **Hourly and frequent jobs** (plan expiry, trial reminders, the */5 job) work on instants and stay as they are, except where they compute a local day.
- **The free-user once-per-calendar-month insight and quota periods** use the person's zone.

### App

- **Parsing:**
  - `parseWallClock*` reads local date-times as-is.
  - New helpers read and write `"YYYY-MM-DD"` for calendar dates.
  - `wallClockToUtcIso` and the UTC-day-bound helpers go away.
- **Budget, goal, recurrence and filter screens** send local values or dates instead of `DateTime.utc(...)`.
- **Requests:** every request carries the timezone header. The report calls stop sending `timezone_offset`.
- **Device "today":** spending pace, "days left" and goal overdue use the phone's today, which now agrees with the server's "today" for that person.

## What's left to the builder

- The exact tick design and the per-job duplicate guards, provided they meet the "exactly once per local day" anti-goal.
- Helper names and signatures in `tz_utils.py`, and how callers are threaded through.
- Header name and validation details; whether the timezone is also saved on sign-in.
- How the e2e suite fakes timezones (the stub already overrides `SCHEDULER_TIMEZONE`).
- Task split and order.
