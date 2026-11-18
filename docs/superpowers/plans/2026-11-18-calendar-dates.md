# Calendar Dates and Per-Person Timezones Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Store wall-clock dates honestly and give every person their own "today". Transactions keep the local date-time as entered. Budget, goal, recurrence and insight dates become calendar `DATE`s. Each person has a timezone taken from their phone, and once-per-book work follows the book's clock (the owner's, for a family book).

**Architecture:**
- One Alembic migration changes the column types, adds `users.timezone`, and adds a `local_job_runs` duplicate-guard table.
- `tz_utils` becomes timezone-explicit: every "today" helper takes a `ZoneInfo`.
- A request dependency saves the phone's `X-Timezone` header.
- Daily jobs move from fixed global cron times to a 15-minute tick. The tick runs each job for each person or book whose local clock has reached the job's time and hasn't run it that local day.
- The Flutter app sends the header and uses the new date shapes.

**Tech Stack:** FastAPI, SQLAlchemy Core, asyncpg, Alembic, Postgres 16 (e2e) and Render Postgres; APScheduler; Flutter with Provider; `flutter_timezone` (new); e2e Python scripts that print `[PASS]`/`[BUG]` lines.

**Spec:** `docs/superpowers/specs/2026-11-18-calendar-dates-design.md`

## Global Constraints

**Storage, all in one migration**
- File: `backend/alembic/versions/20261118_d4b7e1a9c260_calendar_dates.py`.
- Revision `d4b7e1a9c260`, down_revision `c1f0a8e2d93b`.

| Column | New type | Upgrade expression |
|---|---|---|
| `transactions.date` | `TIMESTAMP WITHOUT TIME ZONE NOT NULL` | `date AT TIME ZONE 'UTC'` |
| `transactions.recurrence_end_date` | `DATE NULL` | `(x AT TIME ZONE 'UTC')::date` |
| `transactions.recurrence_last_created_date` | `DATE NULL` | `(x AT TIME ZONE 'UTC')::date` |
| `budgets.start_date`, `budgets.end_date` | `DATE NOT NULL` | `(x AT TIME ZONE 'UTC')::date` |
| `goals.target_date` | `DATE NULL` | `(x AT TIME ZONE 'UTC')::date` |
| `insights.week_start`, `week_end`, `month_start`, `month_end` | `DATE NULL` | `(x AT TIME ZONE 'UTC')::date` |
| `users.timezone` (new) | `TEXT NULL` | none (NULL = default zone) |
| `local_job_runs` (new) | `job TEXT NOT NULL, subject_id TEXT NOT NULL, local_date DATE NOT NULL, claimed_at TIMESTAMPTZ NOT NULL DEFAULT now()`, PK `(job, subject_id, local_date)` | none |

- **Budget end dates:** the end date shown is kept (spec). A stored end of `00:00` becomes that same date, now inclusive.
- **Downgrade:**
  - Wall-clock values go back with `x AT TIME ZONE 'UTC'` (reversing the UTC label).
  - Budget `end_date` goes back as that date at `23:59:59.999999`.
  - Every other `DATE` goes back as midnight UTC.
  - `users.timezone` and `local_job_runs` are dropped.
- **Constraints and indexes:** existing CHECKs (budget `dates_ordered`) and indexes on these columns are kept or recreated on the new types.

**Python value conventions**
- Wall-clock values are **naive** `datetime`.
- Calendar dates are `date`.
- Instants are **aware UTC** `datetime`.
- Never compare an aware value with a naive one.

**API shapes** (lockstep release, so old apps need not work)
- **Transactions, transfers and recurring `date`:** local ISO with no offset, e.g. `"2026-11-18T23:40:00"`. Input with an offset or `Z` keeps its clock fields, and the offset is dropped without converting.
- **Calendar dates:** `"YYYY-MM-DD"`. This covers budget `start_date`/`end_date`, goal `target_date`, recurrence `end_date`, insight bounds and custom-insight ranges. Input given as a date-time string keeps its date part.
- **Instants:** unchanged UTC ISO.
- **Report requests:** the `timezone_offset` field is removed. Reports use the person's zone.
- **Transaction list filter:** takes local date-times or dates. An end given as a date (or as `00:00:00`) includes that whole day.

**Timezone header**
- The header is `X-Timezone`, carrying an IANA name, e.g. `Asia/Bangkok`.
- A valid name is saved to `users.timezone` when it differs.
- A missing or invalid name (`""`, `Mars/Base`, `+07:00`, longer than 64 chars) is ignored, with no error.

**Default zone and whose clock applies**
- **Default zone:** `SCHEDULER_TIMEZONE`, default `Asia/Yangon`. It is used when `users.timezone` is NULL.
- **Whose zone:**
  - Anything shown or sent to a person uses that person's zone. In a family book, that is the viewing or receiving member.
  - Once-per-book work uses the book zone: the person's zone for a personal book, the current owner's zone for a family book.

**Local-time jobs**

| job id | local time | subject | runs |
|---|---|---|---|
| `goal_deadline_reminders` | 09:00 daily | person | goal deadline reminders for the person's books (personal + family), day counts from the person's today |
| `budget_ending_reminders` | 09:00 daily | person | "ending soon" for running budgets in the person's books, day counts from the person's today |
| `payment_reminders` | 09:00 daily | person | recurring-payment reminders (personal book only, as today) |
| `unusual_spending` | 08:00 daily | person | unusual spending (personal book only, as today) |
| `budget_now_active` | 09:00 daily | book | "budget now active" for the book |
| `budget_rollovers` | 00:30 daily | book | auto-create next-period budgets |
| `recurring_transactions` | 06:00 daily | book | create due recurring children |
| `weekly_insights` | Monday 05:00 | book | weekly insight (`WEEKLY_INSIGHT_CRON`) |
| `monthly_insights` | day 1, 06:00 | book | monthly insight (`MONTHLY_INSIGHT_CRON`) |

- **Tick:** every 15 minutes (`minute="*/15"`, UTC).
- **Claim:**
  - A job runs for a subject once its local time has passed today.
  - It first claims `(job, subject_id, local_date)` in `local_job_runs`.
  - A failed run deletes its claim, so the next tick retries.

**Environment**
- Windows PowerShell only (Git Bash is broken).
- Commits:
  - Write the message to a UTF-8 no-BOM file and run `git commit -F`.
  - The message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Local throwaway DB and stub server only. Never read or print `.env*`.
- Keep CRLF in CRLF files.

**Commands**
- `$S` = `C:\Users\LINNYI~1\AppData\Local\Temp\claude\C--projects-Flow\88f449c7-2e35-4a07-890d-5a91aa9c3948\scratchpad`
- `$PY` = `$S\venv_final\Scripts\python.exe`
- `$PGBIN` = `$S\pg_dl\srv\pgsql\bin`
- **Start Postgres if it is down:**
  `Start-Process -FilePath "$PGBIN\pg_ctl.exe" -ArgumentList '-D','C:\projects\Flow\e2e\.data\pg','-o','"-p 54329 -c listen_addresses=127.0.0.1 -c timezone=UTC"','-l','C:\projects\Flow\e2e\logs\postgres.log','start' -WindowStyle Hidden`
  Wait about 10 s.
- **`$RUN` = `$S\pg\run_suite.ps1`:**
  - `& $RUN -NoSuite` resets the DB and (re)starts the stub on 127.0.0.1:8765. The stub loads code at start, so re-run it after every backend edit.
  - `& $RUN` runs the full backend suite. It takes hours, so run it only where a step says so.
  - `pgcompat.reset_postgres` TRUNCATEs every metadata table, so upgrade the e2e DB to the new head before the first GREEN run.
- **One e2e file:**
  `cd C:\projects\Flow\e2e; $env:PYTHONIOENCODING='utf-8'; $env:E2E_FAKE_AI='1'; & $PY -u <file>.py [sections]`
  Expected: no `[BUG]`/`[FAIL]` lines and exit 0.
- **Flutter:**
  - `cd C:\projects\Flow\frontend; C:\flutter\bin\flutter.bat test` and `... analyze`.
  - `analyze` pass means 0 errors, 0 warnings and no new infos (166 today).

## Review Focus

1. **Existing data keeps every date and time.** After upgrade, down and up again:
   - A transaction at 23:40 stays 23:40 on the same day.
   - A budget ending at `00:00` keeps its date (now inclusive).
   - A budget ending at `23:59:59.999` keeps its date.
   - Goal targets keep their day.

   Test: Task 1, `migration` section.
2. **A person in Myanmar notices nothing.**
   - With `users.timezone` NULL or `Asia/Yangon`, today, reminders at 09:00 Yangon, the 00:30 rollover and a transaction entered at 23:50 on the 18th all behave as before.
   - The 23:50 entry counts on the 18th.

   Tests: Task 2 (`today` section) and Task 3 (`ticks` section).
3. **A bad timezone header is ignored.**
   - `X-Timezone: Mars/Base`, an empty header and `+07:00` give a 200, and the stored zone is unchanged.
   - A 70-character value is ignored.

   Test: Task 2, `header` section.
4. **Exactly once per local day.**
   - Two ticks after 09:00 send one reminder.
   - A person whose zone changes from `Asia/Yangon` to `Asia/Tokyo` after their Yangon 09:00 run gets no second run that day.
   - A failed run is retried on the next tick.
   - On a DST spring-forward day in `America/New_York`, the 09:00 job runs once.

   Test: Task 3, `ticks` section.
5. **A family across timezones** (owner in `Asia/Yangon`, member in `Asia/Tokyo`):
   - The member's goal reminder comes in Tokyo's 09:00 run, with Tokyo's day count.
   - The family budget rolls over in the owner's 00:30 Yangon run.
   - A transaction the member enters for `2026-11-18T23:40:00` reads back as the 18th at 23:40 for the owner.

   Tests: Task 2 (`family` section) and Task 3 (`family` section).

---

### Task 1: Storage: migration, honest types, default zone only

**Files:**
- Create: `backend/alembic/versions/20261118_d4b7e1a9c260_calendar_dates.py`
- Modify: `backend/sql/tables.py` (the columns in Global Constraints; new `local_job_runs` table)
- Modify: `backend/tz_utils.py` (new API, below; remove `app_today`, `app_wall_clock_now`, `stored_calendar_date`, `day_bounds_utc`, `get_app_timezone`)
- Modify:
  - every reader and writer of those columns, i.e. every importer of the removed helpers;
  - the pydantic models with date fields: `models.py`, `budget_models.py`, `goal_models.py`, `recurrence_models.py`, `report_models.py`;
  - the routes and services that parse or compare them: `transaction_routes.py`, `budget_routes.py`, `budget_service.py`, `goal_routes.py`, `recurring_transaction_service.py`, `report_routes.py`, `family_routes.py`, `families/breakdown.py`, `families/transfers.py`, `insights_service.py`, `notification_service.py`, `ai_chatbot.py`, `custom_insights_service.py`, `custom_insight_routes.py`, `plans/periods.py`, `plans/access.py`, `insight_schedule.py`, `scheduler.py`, `generate_mock_data.py`;
  - the `sql/*.py` helpers that filter on these columns.
- Modify (e2e): fixtures that write or assert these dates, e.g. `e2e/test_api.py`, `test_books.py`, `test_family.py`, `test_plans.py`, `plans_insight_checks.py`, `plans_custom_insight_checks.py`, `test_goal_history.py` and others the full suite flags.
- Test: create `e2e/test_calendar_dates.py`, with sections `schema` and `migration`, in `test_goal_history.py`'s style (`check()`, `SECTIONS`, `test_plans.alembic`). Add it to `SUITES` and `PRINT_ONLY` in `e2e/run_backend_suite.py`.

**Interfaces:**
- **Produces `tz_utils`:**
  - `DEFAULT_APP_TIMEZONE = "Asia/Yangon"`.
  - `default_zone() -> ZoneInfo`: `SCHEDULER_TIMEZONE`, then `Asia/Yangon`, then UTC.
  - `is_valid_zone_name(name: Optional[str]) -> bool`: true only for a non-empty IANA name of at most 64 chars that `ZoneInfo` loads. Fixed-offset strings like `+07:00` are false.
  - `zone_for(name: Optional[str]) -> ZoneInfo`: `ZoneInfo(name)` if valid, else `default_zone()`.
  - `local_now(tz: ZoneInfo, now: Optional[datetime] = None) -> datetime`: **naive** wall clock.
  - `local_today(tz: ZoneInfo, now: Optional[datetime] = None) -> date`.
  - `local_midnight_utc(day: date, tz: ZoneInfo) -> datetime`: the aware UTC instant of local midnight.
  - `as_wall_clock(value) -> Optional[datetime]`: `str`, `datetime` or `date` → naive. An aware input drops `tzinfo` without converting; a date becomes 00:00.
  - `as_calendar_date(value) -> Optional[date]`: `str`, `datetime` or `date` → `date`. The date part is taken without conversion.
  - `day_bounds(start: date, end: date) -> tuple[datetime, datetime]`: naive `(start 00:00:00, end 23:59:59.999999)`.
  - `days_until(d: date, today: date) -> int`.
  - `previous_week_range(tz, now=None)`, `current_week_to_date_range(tz, now=None)`, `current_month_to_date_range(tz, now=None)`, `week_before_previous_range(tz, now=None)`, `previous_month_range(tz, now=None)`, `month_before_previous_range(tz, now=None)`: each returns naive `day_bounds`.
  - Unchanged: `as_utc`, `utc_now`, `is_expired`, `goal_reminder_threshold`, `is_budget_ending_soon`.
- **Produces `sql/tables.py`:** `local_job_runs` (Task 3 uses it) and `users.c.timezone` (Task 2 uses it).
- **In this task every caller passes `default_zone()`.** Task 2 replaces those with the person's or book's zone.
- **Budgets:** a budget is running when `start_date <= today <= end_date` (`today` = `local_today(zone)`). Period helpers (`calculate_period_dates`, `auto_create_next_budget`) step in whole days, with the end date inclusive. A custom period's length is `(end - start).days + 1` days.
- **JSON:** FastAPI's default encoder serialises a naive datetime as `"…T23:40:00"` and a `date` as `"YYYY-MM-DD"`. Check that `json_safe` and `row_to_doc` (`sql/docs.py`) keep both shapes.

- [ ] **Step 1: Write the failing tests** in `e2e/test_calendar_dates.py`.
  - **`schema`:**
    - Each column in the Global Constraints table has its new type and nullability (read from `information_schema.columns`).
    - `local_job_runs` has its PK.
    - The budget `dates_ordered` CHECK still refuses `end < start`.
  - **`migration`** (at revision `c1f0a8e2d93b`, seed by SQL, then upgrade, check, downgrade, check, upgrade, check; leave the DB at head in a `finally`):
    - A transaction `2026-11-18 23:40:00+00` reads `2026-11-18 23:40:00` after the upgrade and the same `timestamptz` after the downgrade.
    - A budget `2026-11-01 00:00+00` to `2026-12-01 00:00+00` becomes `2026-11-01` to `2026-12-01` (Review Focus 1). After the downgrade its end is `2026-12-01 23:59:59.999999+00`.
    - A monthly budget `2026-11-01 00:00` to `2026-11-30 23:59:59.999+00` becomes `2026-11-01` to `2026-11-30`.
    - A goal `target_date 2026-12-25 00:00+00` becomes `2026-12-25`.
    - A recurring parent's end and last-created pointer become dates. The `"{parent}:{YYYYMMDD}"` child ids are untouched.
    - Through the API after the upgrade:
      - `GET /api/transactions` returns `"date": "2026-11-18T23:40:00"`;
      - `GET /api/budgets/{id}` returns `"start_date": "2026-11-01"` and `"end_date": "2026-12-01"`;
      - the goal returns `"target_date": "2026-12-25"`.
    - API round trip: `POST /api/transactions` with `"date": "2026-11-18T23:40:00Z"` stores and returns `"2026-11-18T23:40:00"`. A budget created with `"start_date": "2026-11-01T00:00:00Z"` returns `"2026-11-01"`.
- [ ] **Step 2: Run them; they fail.**
  - Start the stub before editing code: `& $RUN -NoSuite`.
  - Then run `test_calendar_dates.py schema migration`.
  - Expected: BUGs on types and the missing table.
- [ ] **Step 3: Implement** the migration, `tables.py`, the `tz_utils` API and every caller, the models' validators (`as_wall_clock`/`as_calendar_date`), and the budget date rules above. Keep today's behaviour for a person in the default zone.
- [ ] **Step 4: Run** `& $RUN -NoSuite`, then `test_calendar_dates.py`, `test_api.py`, `test_books.py migration`, `test_goal_history.py` and `test_family.py`. Expected: exit 0, no BUG.
- [ ] **Step 5: Run the full suite once** (`& $RUN`). Expected: `== problems (0) ==`. A known flake, `test_plans create_concurrent_one_pending`, may be re-run alone.
- [ ] **Step 6: Commit** `feat(backend): calendar dates are DATE, transaction dates are local date-times; one migration`.

---

### Task 2: Each person's timezone, and "today" per request

**Files:**
- Create: `backend/user_zones.py`
- Modify:
  - `backend/utils.py` (`get_current_user` takes `request: Request` and calls `remember_timezone`);
  - `backend/sql/users.py` (`set_timezone`);
  - `backend/sql/families.py` (`owner_timezone`);
  - `backend/families/book.py` (if `Book` needs `zone`).
- Modify (callers that compute "today" during a request):
  - `transaction_routes.py` (AI extraction default date and prompts, recurrence re-arm);
  - `budget_routes.py` and `budget_service.py` (status on read and write);
  - `ai_chatbot.py`;
  - `insights_service.py` (on-demand generation, today's placeholder);
  - `custom_insight_routes.py` and `custom_insights_service.py` (range validation, attempt windows);
  - `report_routes.py` and `report_models.py` (drop `timezone_offset`; boundaries from the person's zone);
  - `family_routes.py` (breakdown);
  - `pdf_generator.py` (`generated_at` in the person's zone);
  - `plans/periods.py`, `plans/quota.py`, `plans/access.py` (week and month starts in the person's zone);
  - `main.py` (free once-per-month insight).
- Test: `e2e/test_calendar_dates.py`, sections `header`, `today` and `family`.

**Interfaces:**
- Consumes Task 1's `tz_utils` and `users.c.timezone`.
- **Produces `user_zones.py`:**
  - `TIMEZONE_HEADER = "X-Timezone"`.
  - `async def remember_timezone(user: dict, header_value: Optional[str]) -> dict`: if `is_valid_zone_name(header_value)` and it differs from `user.get("timezone")`, calls `users_db.set_timezone(user["_id"], header_value)`. Returns the user dict with `timezone` set.
  - `def user_zone(user: dict) -> ZoneInfo`: `zone_for(user.get("timezone"))`.
  - `async def book_zone(book_id: str) -> ZoneInfo`: a personal book uses its person's zone; a family book uses `families_db.owner_timezone(family_id)` through `zone_for`. A missing book gives `default_zone()`.
- **Produces SQL helpers:**
  - `users_db.set_timezone(user_id: str, name: str) -> None`.
  - `families_db.owner_timezone(family_id: str) -> Optional[str]`: the `users.timezone` of the family's current owner member.
- **Rule:** a request computes "today" with `user_zone(current_user)` when the result is shown to the caller. Writes that act on the book as a whole use `await book_zone(book.id)`: budget status persisted on write, a recurrence pointer re-arm, or a rollover triggered by a request.

- [ ] **Step 1: Write the failing tests.**
  - **`header`:**
    - `GET /api/auth/me` with `X-Timezone: Asia/Tokyo` saves `Asia/Tokyo`. A later request without the header keeps it.
    - `Mars/Base`, `""`, `+07:00` and a 70-char value each give 200 and leave the stored zone unchanged (Review Focus 3).
    - A new user has NULL until their first header.
  - **`today`:**
    - A person in `Asia/Tokyo` at an instant that is the 19th in Tokyo and the 18th in Yangon: the custom-insight range ending "today" accepts the 19th for them and refuses it for a Yangon person.
    - A report for "week" covers the Tokyo week for the Tokyo person.
    - The quota week resets at Tokyo midnight (`local_midnight_utc`).
    - A NULL-zone person behaves as `Asia/Yangon` (Review Focus 2).
    - Pin the instants with the stub's clock override if one exists; otherwise choose dates whose answer doesn't depend on the run time and say so in the report.
  - **`family`** (owner `Asia/Yangon`, member `Asia/Tokyo`):
    - The member posts `"2026-11-18T23:40:00"`, and the owner reads `"2026-11-18T23:40:00"` (Review Focus 5).
    - `book_zone` of the family book is Yangon, and becomes Tokyo after ownership passes to the member (use the existing transfer-ownership endpoint).
- [ ] **Step 2: Run them; they fail** (`& $RUN -NoSuite`, then `test_calendar_dates.py header today family`).
- [ ] **Step 3: Implement** `user_zones.py`, the SQL helpers, the `get_current_user` change and every request-path caller.
- [ ] **Step 4: Run** `& $RUN -NoSuite`, then `test_calendar_dates.py` (all sections), `test_api.py`, `test_family.py`, `test_plans.py` and `plans_custom_insight_checks` (through `test_plans.py`). Expected: exit 0.
- [ ] **Step 5: Commit** `feat(backend): each person's timezone from the phone decides their today`.

---

### Task 3: Daily jobs at each person's and each book's local time

**Files:**
- Create: `backend/local_jobs.py`
- Create: `backend/sql/local_job_runs.py`
- Modify: `backend/scheduler.py`. The 9 jobs in the Global Constraints table are replaced by one 15-minute tick. Hourly and other jobs keep their triggers, now with `timezone=default_zone()`.
- Modify:
  - `notification_service.py`: per-person handlers. The family goal and budget-ending guards become per member: `approaching_reminder_exists([member], …)` and `notifications_db.exists([member], "budget_ending_soon", budget_id=…)`. The per-budget `ending_soon_notified` claim is no longer the send guard.
  - `budget_service.py`: rollover per book.
  - `recurring_transaction_service.py`: due occurrences per book.
  - `insights_service.py`: weekly and monthly per book.
  - `insight_schedule.py`: the next-run time in the book's zone.
- Test: `e2e/test_calendar_dates.py`, sections `ticks` and `family_jobs`.

**Interfaces:**
- Consumes `user_zones.user_zone`, `user_zones.book_zone`, `tz_utils.local_now`/`local_today`, and `tables.local_job_runs`.
- **Produces `sql/local_job_runs.py`:**
  - `claim(job: str, subject_id: str, local_date: date) -> bool`: an `INSERT … ON CONFLICT DO NOTHING`; true if inserted.
  - `release(job, subject_id, local_date) -> None`.
- **Produces `local_jobs.py`:**
  - `LocalJob` (dataclass): `id: str`, `at: time`, `subject: Literal["person","book"]`, `handler: Callable[[str, date, ZoneInfo], Awaitable[None]]`, plus optional `weekday: Optional[int]` and `day: Optional[int]`.
  - `LOCAL_JOBS: list[LocalJob]` with exactly the rows of the Global Constraints table.
  - `async def run_due_local_jobs(now: Optional[datetime] = None) -> dict[str, int]`:
    - For each job and subject, compute the subject's `local_now`.
    - If its date matches the job's weekday or day rule and its time is at or after `at`, claim `(job.id, subject_id, local_today)` and await the handler.
    - On an exception, release the claim and log.
    - Returns the run counts per job.
  - Subjects:
    - "person" = every user with a personal book;
    - "book" = every personal book plus every family book that has an owner.
- **Handlers** (one per job; each acts only on its subject with the given `today` and zone):
  - `notification_service.goal_deadline_reminders_for_person(person_id, today, tz)`
  - `notification_service.budget_ending_reminders_for_person(person_id, today, tz)`
  - `notification_service.payment_reminders_for_person(person_id, today, tz)`
  - `notification_service.unusual_spending_for_person(person_id, today, tz)`
  - `notification_service.budget_now_active_for_book(book_id, today, tz)`
  - `budget_service.budget_rollovers_for_book(book_id, today, tz)`
  - `recurring_transaction_service.recurring_for_book(book_id, today, tz)`
  - `insights_service.weekly_insight_for_book(book_id, today, tz)`
  - `insights_service.monthly_insight_for_book(book_id, today, tz)`
- **Fan-out:** a per-person reminder in a family book goes only to that member, through `create_person_notification_from_key(member, …, links={"book_id": book_id, <subject>})`. Book-level notices keep `create_notification_from_key`.
- **Removed:** the old `*_for_all_users` / `check_*` global entry points, once nothing calls them.

- [ ] **Step 1: Write the failing tests**, driving `run_due_local_jobs(now=…)` in-process through the existing backend import pattern (`_backend_async` in `test_goal_history.py`).
  - **`ticks`:**
    - A Yangon person with a goal due in 7 days: `now` = 08:50 Yangon sends nothing, 09:05 sends one reminder, and 09:20 sends none.
    - The person's zone is set to `Asia/Tokyo` at 09:30 Yangon (11:00 Tokyo), and the next tick sends none (Review Focus 4).
    - The handler is made to raise once (monkeypatch); the claim is released, and the next tick sends it.
    - An `America/New_York` person on 2027-03-14 (spring forward) gets exactly one 09:00 run across ticks from 00:00 to 12:00.
    - A NULL-zone person's rollover runs at the 00:30 Yangon tick, not before (Review Focus 2).
  - **`family_jobs`** (owner `Asia/Yangon`, member `Asia/Tokyo`, a family goal due on a date that is 7 days away for Tokyo at Tokyo 09:00):
    - The member's reminder arrives in the tick at Tokyo 09:00, with a day count from Tokyo's today, and only to the member.
    - The owner's reminder arrives at Yangon 09:00.
    - The family budget rollover runs at the owner's 00:30, not at the member's (Review Focus 5).
    - The weekly family insight is generated once, on the owner's Monday 05:00.
- [ ] **Step 2: Run them; they fail** (`& $RUN -NoSuite`, then `test_calendar_dates.py ticks family_jobs`).
- [ ] **Step 3: Implement** `sql/local_job_runs.py`, `local_jobs.py`, the handlers and the scheduler change.
- [ ] **Step 4: Run** `& $RUN -NoSuite`, then `test_calendar_dates.py` (all sections), `test_api.py`, `test_family.py`, `test_plans.py` and `test_goal_history.py`. Expected: exit 0.
- [ ] **Step 5: Run the full suite once** (`& $RUN`). Expected: `== problems (0) ==`.
- [ ] **Step 6: Commit** `feat(backend): daily jobs run at each person's and each book's local time`.

---

### Task 4: App: send the timezone, use honest date shapes

**Files:**
- Modify: `frontend/pubspec.yaml` (add `flutter_timezone`, latest stable)
- Modify: `frontend/lib/services/api_service.dart`
  - Every request sends `X-Timezone` from `FlutterTimezone.getLocalTimezone()`, cached after the first read. On web the package reads the browser's zone. If reading fails, no header is sent.
  - Transaction, transfer and recurring dates are sent as local ISO with no `Z`.
  - Budget, goal target and recurrence end are sent as `YYYY-MM-DD`.
  - The report calls drop `timezone_offset`.
  - The transaction filter is sent as local values.
- Modify: `frontend/lib/utils/date_parsing.dart`
  - `parseWallClock*` stays; it reads offset-less strings as local.
  - Add `parseCalendarDate(String) -> DateTime` (local midnight) and `parseCalendarDateOrNull`.
  - Add `toCalendarDateString(DateTime) -> String` (`yyyy-MM-dd` of the local fields) and `toWallClockString(DateTime) -> String` (local ISO with no offset).
  - Remove `wallClockToUtcIso`, `startOfDayUtcIso` and `endOfDayUtcIso`.
- Modify: models `budget.dart`, `goal.dart`, `recurring_transaction.dart`, `report.dart`, `custom_insight.dart`, `insight.dart`, `transaction.dart`, `voice_image_models.dart`.
- Modify: screens and providers:
  - `create_budget_screen.dart`: build local dates, not `DateTime.utc`. Custom defaults pick an end date that is included, so "start + 30 days" becomes `start + 29 days`.
  - `budget_detail_screen.dart`, `transaction_provider.dart` (spending-pace fetch), `utils/spending_pace.dart`, `utils/date_picker_bounds.dart`, `home_screen.dart` ("days left" = end date minus today in whole days, as it reads today), and any other `DateTime.utc(...)` built from local fields for the API.
- Test: create `frontend/test/calendar_dates_test.dart` and update existing tests that assert the old shapes.

**Interfaces:**
- Consumes the API shapes and the `X-Timezone` header from Global Constraints.

- [ ] **Step 1: Write the failing tests** (`ApiService.httpClientOverride` as in `fcm_registration_test.dart`; fake the timezone reader with a static override, e.g. `ApiService.timezoneOverride = 'Asia/Tokyo'`).
  - Every request carries `X-Timezone: Asia/Tokyo`. With the reader failing, no header is sent and the request still succeeds.
  - Creating a transaction for local 18 Nov 23:40 sends `"date": "2026-11-18T23:40:00.000"` (or with no milliseconds), with no `Z`.
  - Creating a budget 1 Nov to 30 Nov sends `"start_date": "2026-11-01"` and `"end_date": "2026-11-30"`.
  - Parsing `"end_date": "2026-11-30"` gives a budget whose last day is the 30th, and the budget still counts as running all of 30 Nov.
  - "Days left" shows what it shows today: 0 ("ends today") on 30 Nov and 1 on 29 Nov.
  - A report request has no `timezone_offset` key.
  - The spending-pace fetch sends local bounds without `Z`, and a transaction at `"2026-11-18T23:40:00"` buckets on the 18th.
- [ ] **Step 2: Run them; they fail** (`flutter.bat test test/calendar_dates_test.dart`).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full `flutter.bat test` and `flutter.bat analyze`. Expected: all pass; 0 errors, 0 warnings, and no new infos.
- [ ] **Step 5: Commit** `feat(app): send the phone's timezone; calendar dates and local date-times`.

### After the tasks
The controller runs final verification:
- the full backend suite on a reset DB;
- `flutter test` and `flutter analyze`;
- a browser check, with the phone zone as `Asia/Yangon` and as another zone, of:
  - a transaction entered at 23:40;
  - a monthly budget's dates;
  - a goal deadline;
  - a family book.
