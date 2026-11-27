# Numbers and Times Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admins change the trial length, reminder timing, invite validity, the unusual-spending rules and four job
times from a new admin "Numbers & times" tab, without a redeploy; the app shows the server's trial length and invite
validity.

**Architecture:** A new `tunables` module holds a catalogue of settings (default, range, label, note) in code and
caches one JSON record (`app_settings` key `tunables`: only non-default values plus `version`), loaded at startup,
refreshed every 60 s and updated at once on save, like `app_control.py`. Each place that used a constant reads
`tunables.get(...)`. The admin API saves with a version compare-and-swap in SQL. The public `/api/app/config` gains
`numbers`.

**Tech Stack:** FastAPI + SQLAlchemy Core (asyncpg) on Postgres 16; React + Vite admin panel; Flutter app (Provider).

**Spec:** `docs/superpowers/specs/2026-11-27-numbers-and-times-design.md` (its tables, ranges and "Calls made after
the builder check" are binding).

## Global Constraints

- The catalogue (key: default; allowed), exactly:
  - `trial_days`: 30; whole days 7-90.
  - `ends_soon_days`: 3; whole days 2-14, and less than `trial_days` (cross-field, checked on the merged values).
  - `goal_reminder_days`: [14, 7, 3, 1]; 1-4 distinct whole days, each 1-60 (stored sorted high to low).
  - `budget_ending_soon_days`: 3; whole days 1-14.
  - `invite_days`: 14; whole days 1-60.
  - `large_expense_multiple`: 3; number 1.5-10.
  - `large_expense_min`: {"mmk": 100000, "usd": 100, "thb": 2000}; each above 0, at most {"mmk": 100000000, "usd": 100000, "thb": 2000000}.
  - `unusual_week_multiple`: 1.5; number 1.1-5.
  - `unusual_week_min_diff`: {"mmk": 50000, "usd": 50, "thb": 1000}; same rules and maximums as `large_expense_min`.
  - `reminders_time`: "09:00"; "HH:MM" on 15-minute steps, 07:00-21:00.
  - `unusual_spending_time`: "08:00"; same, 07:00-21:00.
  - `weekly_report_time`: "05:00"; same, 01:00-23:00 (Monday stays).
  - `monthly_report_time`: "06:00"; same, 01:00-23:00 (the 1st stays).
- Whole days are JSON integers (not floats, not strings, not booleans). Numbers are int or float, finite, never
  booleans. Amounts: currency `mmk`, `usd`, `thb`; any other currency uses the `usd` value. The no-history large-expense
  bar is a fixed `1.5 *` the currency's `large_expense_min`.
- Groups shown in the panel, in this order: "Trial and plans" (`trial_days`, `ends_soon_days`), "Reminders"
  (`goal_reminder_days`, `budget_ending_soon_days`), "Unusual spending" (the four), "Family" (`invite_days`),
  "Job times" (the four times).
- A stored value that is missing, of the wrong type or out of range is ignored (its default used) and warned about once
  per distinct bad value; a stored record that isn't JSON leaves every default. Readers never raise.
- 422 body: `{"detail": {"code": "settings_invalid", "errors": {"<key>": "<readable message>"}}}`.
  409 body: `{"detail": {"code": "settings_conflict", "message": "These settings were changed by someone else. Reload to see them."}}`.
  The conflict is checked against the stored row in SQL (compare-and-swap on `version`), never the cache.
- Roles: read `require_moderator_or_above`; save `require_admin_or_super`. Each save calls `log_admin_action` with
  action `tunables_update` and details `"<key>: <old> -> <new>; ..."` (cut to 2,000 characters, as App control).
- Times are on the person's or book's own clock; a job still runs at most once per local date (`local_job_runs`).
- App texts: at 30 trial days the existing month wording stays; otherwise day wording. Myanmar text uses Myanmar
  digits for the number.
- UTF-8 sources: Edit/Write tools or Python `io.open(..., encoding="utf-8", newline="")`; never PowerShell
  `Get-Content`/`Set-Content` on source files (Myanmar text).
- Branch `numbers-and-times`. Before each commit: `git checkout -- frontend/linux frontend/macos frontend/windows`.
  Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, written to a file with the Write tool and passed with
  `git commit -F`.
- Never read or print `.env` or other secret files. Tests use only the local stub server and test DB.

## Commands

- `$PY` = `C:\Users\LINNYI~1\AppData\Local\Temp\claude\C--projects-Flow\88f449c7-2e35-4a07-890d-5a91aa9c3948\scratchpad\venv_final\Scripts\python.exe`
- `$S` = `C:\Users\LINNYI~1\AppData\Local\Temp\claude\C--projects-Flow\88f449c7-2e35-4a07-890d-5a91aa9c3948\scratchpad`
- Postgres (127.0.0.1:54329) if down — start it detached, never with a piped `pg_ctl`:
  `Start-Process -FilePath "$S\pg_dl\srv\pgsql\bin\pg_ctl.exe" -ArgumentList "-D `"$S\pg_data`" -l `"$S\pg\postgres.log`" -o `"-p 54329 -h 127.0.0.1`" start" -WindowStyle Hidden`,
  then poll `& "$S\pg_dl\srv\pgsql\bin\pg_isready.exe" -h 127.0.0.1 -p 54329` until exit 0.
- Restart the stub server (:8765) on current code (resets data): `& "$S\pg\run_suite.ps1" -NoSuite`. Needed after
  any backend change an HTTP test exercises.
- One backend test file: `$env:E2E_FAKE_AI='1'; $env:PYTHONIOENCODING='utf-8'; Set-Location C:\projects\Flow\e2e; & $PY -u test_tunables.py <sections>`
  (exit 0 and no `[BUG]` = pass).
- Admin: `Set-Location C:\projects\Flow\admin; npm run lint; npm run build` (baseline: 1 pre-existing lint error in App.jsx).
- App: `Set-Location C:\projects\Flow\frontend; flutter test; flutter analyze` (baseline 166 infos, no warnings or errors).

## Review Focus

1. **A test leaves a changed setting behind** in the shared `tunables` row, changing reminders other suites assert:
   HTTP saves are restored in `finally`; in-process tests use a private key or patch the cache; the `clean` section
   checks the row is as it was at the start (Task 1 adds it, every task keeps it last).
2. **Python's `True` is an `int`**, and JSON allows `1e999`/`NaN` in some encoders: `True`, `3.5` days, `"3"`, NaN and
   infinity are refused (Task 1 tests).
3. **The first save ever (no row yet) racing another first save**: one wins, the other gets 409, not a 500 or a lost
   write (Task 1 tests the SQL compare-and-swap with version 0).
4. **A changed value leaving the cross-field rule broken**: lowering `trial_days` to 7 while `ends_soon_days` is 9 is
   refused, whichever of the two the save changes (Task 1).
5. **Old app or old server**: the app gets no `numbers` (older server) and shows 30 / 14 words; an old app ignores the
   new key (Task 6 tests the fallback).

---

### Task 1: The settings store

**Files:**
- Create: `backend/tunables.py`, `backend/sql/tunables.py`, `e2e/test_tunables.py`
- Modify: `backend/main.py` (load at startup and start the refresh loop, next to `app_control` at lines 137-140; cancel
  on shutdown next to lines 163-166), `e2e/run_backend_suite.py` (add `"test_tunables"` to `SUITES`)

**Interfaces:**
- Produces (`backend/tunables.py`):
  - `SETTINGS_KEY = "tunables"` (in `sql/tunables.py`, re-exported).
  - `CATALOGUE: tuple[Setting, ...]`; `Setting` (frozen dataclass): `key, kind, default, group, label, note, min, max`;
    kind is one of `"days"`, `"day_list"`, `"number"`, `"amounts"`, `"time"`.
  - `get(key: str) -> Any` — the effective value (cached valid stored value, else the default); `KeyError` for an
    unknown key (programming error).
  - `amount_for(key: str, currency: str) -> float` — the currency's amount (`usd` for unknown currencies).
  - `time_of(key: str) -> datetime.time`.
  - `catalogue() -> list[dict]` — per setting: `key, kind, group, label, note, default, min, max, value, changed`.
  - `version() -> int` — the cached record's version (0 when nothing stored).
  - `class SettingsInvalid(ValueError)` with `.errors: dict[str, str]`; `class SettingsConflict(Exception)`.
  - `validate(values: Mapping[str, Any]) -> dict` — the full effective set after merging `values` over the current
    effective values; raises `SettingsInvalid` (all field errors at once, plus the cross-field one under `ends_soon_days`).
  - `async load() -> None`; `start_refresh_loop(interval: float = 60.0) -> asyncio.Task`.
  - `async save(values: Mapping[str, Any], expected_version: int, admin_id: str) -> dict` — validates, stores only the
    values that differ from defaults with `version = expected_version + 1`, updates the cache, returns
    `{"changes": [(key, old, new), ...], "version": int}`; raises `SettingsInvalid` or `SettingsConflict`.
- Produces (`backend/sql/tunables.py`): `async read() -> Optional[str]`;
  `async write_if_version(value: str, expected_version: int) -> bool` — when `expected_version == 0`, insert only if no
  row exists (`ON CONFLICT DO NOTHING`); otherwise `UPDATE app_settings SET value = :v WHERE key = 'tunables' AND
  (value::jsonb ->> 'version')::int = :expected`; True when one row was written.

- [ ] **Step 1: Write the failing tests** — `e2e/test_tunables.py` with sections `store` and `clean`, in the style of
  `e2e/test_app_control.py` (check() printing `[PASS]`/`[BUG]`, `SECTIONS`, exit 1 on failure). In-process tests point
  `sql.tunables.SETTINGS_KEY` at a private key `"tunables_e2e"` (as `test_app_control.py` does with `E2E_KEY`) and
  delete it in `finally`. Checks:
  - with nothing stored: `get("trial_days") == 30`, `get("goal_reminder_days") == [14, 7, 3, 1]`,
    `amount_for("large_expense_min", "thb") == 2000`, `amount_for("large_expense_min", "eur") == 100`,
    `time_of("reminders_time") == time(9, 0)`, `version() == 0`; `catalogue()` lists the 13 keys in group order.
  - `validate` refuses, each naming the key: `{"trial_days": True}`, `{"trial_days": 3.5}`, `{"trial_days": "30"}`,
    `{"trial_days": 6}`, `{"trial_days": 91}`, `{"goal_reminder_days": []}`, `{"goal_reminder_days": [7, 7]}`,
    `{"goal_reminder_days": [1, 2, 3, 4, 5]}`, `{"goal_reminder_days": [61]}`, `{"large_expense_multiple": float("nan")}`,
    `{"large_expense_multiple": 1.4}`, `{"large_expense_min": {"mmk": 0, "usd": 100, "thb": 2000}}`,
    `{"large_expense_min": {"mmk": 100000}}` (all three currencies required), `{"large_expense_min": {"usd": 100001, "mmk": 1, "thb": 1}}`,
    `{"reminders_time": "06:45"}`, `{"reminders_time": "09:10"}`, `{"reminders_time": "9:00"}`, `{"nope": 1}`;
    and the cross-field rule both ways: `{"trial_days": 7, "ends_soon_days": 9}` and, with `ends_soon_days` 9 saved,
    `{"trial_days": 7}` → error under `ends_soon_days`.
  - `validate({"goal_reminder_days": [1, 14, 7]})` stores `[14, 7, 1]`.
  - save at version 0 → version 1, stored JSON holds only the changed key and `"version": 1`; a second save at
    version 0 → `SettingsConflict`; two concurrent saves at the same version (`asyncio.gather`) → exactly one succeeds.
  - saving a value equal to its default removes it from the stored record.
  - a stored record with `{"version": 2, "trial_days": "x", "invite_days": 20, "nope": 5}` loads as trial 30, invite
    20, version 2 (warned, not raised); a stored `"not json"` loads all defaults.
  - `clean`: the real `tunables` row is the same as when the run started (read it first, compare at the end).

- [ ] **Step 2: Run them to see them fail** — `& $PY -u test_tunables.py store clean`; expected: import error on
  `tunables`.

- [ ] **Step 3: Implement `backend/sql/tunables.py` and `backend/tunables.py`** with the interfaces above, following
  `app_control.py` (cache, `_write_gen` stale-load guard, refresh loop, `snapshot` copy). Labels and notes come from
  the spec's tables (English).

- [ ] **Step 4: Wire `backend/main.py`** (load in a try like `app_control.load()`, start the loop, cancel on shutdown)
  and add `test_tunables` to `e2e/run_backend_suite.py` `SUITES`.

- [ ] **Step 5: Run the tests** — `& $PY -u test_tunables.py store clean` passes; `& $PY -u test_app_control.py`
  still passes.

- [ ] **Step 6: Commit** — `feat(backend): tunable settings store (numbers and times)`.

### Task 2: Admin API and the app's config

**Files:**
- Create: `backend/tunables_routes.py`
- Modify: `backend/main.py` (include the router), `backend/app_control_routes.py` (`app_config` adds `numbers`),
  `e2e/test_tunables.py` (sections `admin_api`, `public_config`), `e2e/test_sweep.py` only if it needs the new admin
  paths listed (check how it treats `/api/admin/texts`)

**Interfaces:**
- Consumes: Task 1's `catalogue()`, `version()`, `save()`, `SettingsInvalid`, `SettingsConflict`, `get()`.
- Produces:
  - `GET /api/admin/tunables` → `{"settings": catalogue(), "version": version()}`.
  - `PUT /api/admin/tunables`, body `{"values": {key: value, ...}, "version": int}` (extra fields forbidden) → the same
    shape as GET after the save; 422 / 409 bodies as in Global Constraints; logged as `tunables_update`.
  - `GET /api/app/config` gains `"numbers": {"trial_days": int, "invite_days": int}` (signed in or not).

- [ ] **Step 1: Write the failing tests** (HTTP against the stub; throwaway admins made like `test_texts.py`'s
  `_admin`, removed in `finally`; every save restored in `finally` by saving the starting values at the then-current
  version):
  - moderator GET 200 with 13 settings and `version`; moderator PUT 403; no token 401.
  - admin PUT `{"values": {"trial_days": 45, "reminders_time": "10:00"}, "version": v}` → 200, `trial_days` value 45 and
    `changed` true; the latest `admin_action_logs` row for that admin has action `tunables_update` and details
    containing `trial_days: 30 -> 45` and `reminders_time: 09:00 -> 10:00`.
  - PUT with the old version → 409 with `code == "settings_conflict"`.
  - PUT `{"values": {"trial_days": 3, "invite_days": 0}}` → 422, `errors` has both keys.
  - `GET /api/app/config` without a token → `numbers == {"trial_days": 45, "invite_days": 14}` while saved, and 30 after
    the restore.

- [ ] **Step 2: Run to fail**, restart the stub after Step 3, **Step 4: run to pass**
  (`& $PY -u test_tunables.py store admin_api public_config clean`) and `& $PY -u test_sweep.py`.

- [ ] **Step 3: Implement** `tunables_routes.py` (pattern of `app_control_routes.py`: `admin_router` with prefix
  `/api/admin/tunables`) and the `numbers` entry in `app_config`.

- [ ] **Step 5: Commit** — `feat(backend): admin API for numbers and times; the app config carries the trial and invite lengths`.

### Task 3: The numbers take effect

**Files:**
- Modify: `backend/auth_routes.py:607` (trial length), `backend/subscription_service.py:37-40,144,150,188,195` (the
  "ends soon" window; docstrings that say 3 days), `backend/notification_service.py:664,673,733,741` (goal and budget
  windows, passing the settings to `goal_reminder_threshold(..., thresholds=...)` and `is_budget_ending_soon(..., window=...)`),
  `backend/notification_service.py:852-856` (rule 1) and `:940-942` (rule 2), `backend/families/service.py:47,460`
  (invite days), `e2e/test_tunables.py` (section `numbers`)
- Do not import `tunables` into `tz_utils.py` (keep it dependency-free; its constants stay as the defaults' source or
  are removed if unused).

**Interfaces:**
- Consumes: Task 1's `get`, `amount_for`. Tests change values by patching the cache in-process (a helper
  `_with_values(dict)` context manager in the test that sets and restores the module cache) or over HTTP (trial claim).

- [ ] **Step 1: Write the failing tests** (section `numbers`):
  - over HTTP: save `trial_days` 45, register and verify a throwaway user, `POST /api/auth/claim-free-trial` →
    `trial_ends_at` is 45 days from now (±5 minutes); restore in `finally`; delete the user.
  - in-process, `ends_soon_days` 5: a trial user whose `trial_ends_at` is 4.5 days ahead gets `trial_ending_soon` from
    `send_trial_reminders(now)`; one 6 days ahead gets nothing; a second run sends nothing more. Same for
    `send_plan_renewal_reminders` with `plan_ending_soon`.
  - in-process, `goal_reminder_days` [10, 2]: a goal due in 9 days gets a reminder with threshold 10 from
    `goal_deadline_reminders_for_person`; due in 12 days gets none.
  - in-process, `budget_ending_soon_days` 5: a budget ending in 5 days gets `budget_ending_soon`; in 6, none.
  - in-process, `invite_days` 3: a new invite's `expires_at` is 3 days after creation.
  - in-process, rule 1 with `large_expense_multiple` 2 and the THB default: a ฿1,500 expense with no profile → no
    notice (bar ฿3,000); ฿3,000 → notice; with profile `avg_transaction` 2,000 → bar max(4,000, 2,000) → ฿3,500 no
    notice, ฿4,000 notice. MMK default without profile: 150,000 → notice, 149,999 → none.
  - in-process, rule 2 with `unusual_week_multiple` 2: this week 2.1x the weekly average and above the minimum
    difference → `unusual_spending`; 1.9x → none.
  - all test rows (users, goals, budgets, invites, transactions, notifications) deleted in `finally`.

- [ ] **Step 2: Run to fail**, **Step 3: implement** each reader with `tunables.get(...)` read per call,
  **Step 4: run to pass** (`& $PY -u test_tunables.py numbers clean`) and the suites that cover these readers:
  `test_api.py`, `test_family.py`, `test_calendar_dates.py`, and whichever suite runs `plans_subscription_checks.py`
  (find it with a search for that name in `e2e/`).

- [ ] **Step 5: Commit** — `feat(backend): trial, reminders, invites and unusual spending follow the admin settings`.

### Task 4: The job times take effect

**Files:**
- Modify: `backend/local_jobs.py:42-78` (`LocalJob` gains `time_key: Optional[str] = None`; the fixed time becomes the
  field `default_at`, and `at` becomes a property: `tunables.time_of(time_key)` when set, else `default_at`; so
  `job.at` keeps working for `is_due`, the sort in `run_due_local_jobs` and the e2e helpers),
  `backend/insight_schedule.py:16-26` (`cron_for` builds `{"day_of_week": "mon", "hour", "minute"}` and
  `{"day": 1, "hour", "minute"}` from `weekly_report_time` / `monthly_report_time`; the two constants are removed),
  `e2e/plans_insight_checks.py:540-555` (the check that `local_jobs` and `insight_schedule` share the cron dicts
  becomes: the weekly and monthly jobs' `at`, `weekday` and `day` equal what `cron_for` gives), `e2e/test_tunables.py`
  (section `times`)

**Interfaces:**
- Consumes: Task 1's `time_of`.
- `time_key` per job: the goal, budget-ending, payment and budget-now-active jobs → `reminders_time`;
  `unusual_spending` → `unusual_spending_time`; `weekly_insights` → `weekly_report_time`; `monthly_insights` →
  `monthly_report_time`; `budget_rollovers` and `recurring_transactions` → none (fixed 00:30 and 06:00).

- [ ] **Step 1: Write the failing tests** (section `times`, in-process, cache patched and restored):
  - `reminders_time` "10:30": the `goal_deadline_reminders` job's `is_due` is False at a wall clock of 10:15 and True
    at 10:30; `budget_rollovers` is unchanged (`at == time(0, 30)`).
  - `unusual_spending_time` "07:15" → that job is due at 07:15.
  - `weekly_report_time` "07:45": `next_scheduled_insight_at("weekly", ZoneInfo("Asia/Yangon"), now)` for a Sunday
    noon `now` is the next Monday 07:45 Yangon time; the `weekly_insights` job is due Monday 07:45, not Monday 07:30,
    and not on Tuesday.
  - `monthly_report_time` "02:00": the next monthly insight is the 1st at 02:00.
  - moving a time after the job already ran today doesn't run it again: claim the job for a subject's today with
    `run_due_local_jobs(now, jobs=[job])`, change the time to later, run again later that day → 0 runs.

- [ ] **Step 2: Run to fail**, **Step 3: implement**, **Step 4: run to pass** (`& $PY -u test_tunables.py times clean`)
  and `test_calendar_dates.py`, `test_plans.py` (it runs `plans_insight_checks.py`).

- [ ] **Step 5: Commit** — `feat(backend): reminder, unusual-spending and report times follow the admin settings`.

### Task 5: The admin tab

**Files:**
- Create: `admin/src/Tunables.jsx` (the page: load, group, Save with confirm, conflict and errors),
  `admin/src/TunableField.jsx` (one setting's input by kind)
- Modify: `admin/src/App.jsx` (sidebar entry `{ id: 'numbers', icon: Gauge, label: 'Numbers & times' }` after
  `texts`, and `{activeTab === 'numbers' && <Tunables token={token} adminRole={admin.role} ConfirmDialog={ConfirmDialog} />}`),
  `admin/src/api.js` (`getTunables(token)`, `updateTunables(token, body)`)

**Interfaces:**
- Consumes: Task 2's GET/PUT shapes and error bodies (`ApiError.status` and `.detail`).

- [ ] **Step 1: Build the page.** Inputs by kind: `days` a number input with min/max; `day_list` a text input
  "14, 7, 3, 1"; `number` a number input with step 0.1; `amounts` three inputs labelled MMK / USD / THB; `time` a
  select of the 15-minute steps inside the range. Each setting shows its label, note, "Default: …", "Allowed: …",
  a "Use default" button, and a "Changed" mark when its value differs from the default. One Save at the bottom,
  disabled when nothing changed; it opens `ConfirmDialog` listing `label: old → new` for each edited field, then PUTs
  only the edited fields with the loaded `version`. 422: each `errors[key]` shown under its field. 409: a banner with
  the message and a "Reload" button that refetches while keeping the edited fields and showing the server's value
  beside each edited one. Moderators (`!canWrite(adminRole)`): inputs disabled, no Save.
- [ ] **Step 2: Check** — `npm run lint` (baseline only) and `npm run build` pass; a browser check against the stub
  (`admin` preview, a throwaway admin): change the trial length and a time, confirm, see the saved values; an
  out-of-range value shows its inline error; a conflict (save from a second session first) shows the banner and keeps
  the typing. Restore every value afterwards.
- [ ] **Step 3: Commit** — `feat(admin): Numbers & times tab`.

### Task 6: The app shows the server's numbers

**Files:**
- Modify: `frontend/lib/models/app_config.dart` (`trialDays`, `inviteDays` from `json['numbers']`; 30 / 14 when
  missing, not an int, or outside 1-365; `AppConfig.open` uses 30 / 14),
  `frontend/lib/services/localization_service.dart` (new strings and methods below),
  `frontend/lib/screens/subscription/subscription_screen.dart:135,324,351`,
  `frontend/lib/screens/family/family_invite_screen.dart:88`
- Create: `frontend/test/trial_invite_texts_test.dart`

**Interfaces:**
- Consumes: Task 2's `numbers` in `/api/app/config`; `AppControlProvider.config` (already provided app-wide).
- Produces (in `AppLocalizations`):
  - `String trialFreeCaps(int days)`, `String claimTrialFree(int days)`, `String trialFreeAccessGranted(int days)`:
    at 30 the existing `oneMonthFreeCaps`, `claimOneMonthFree`, `oneMonthFreePlusAccess`; otherwise new keys
    `daysFreeCaps` ("{n} DAYS FREE" / "{n} ရက် အခမဲ့"), `claimDaysFree` ("Claim {n} days free" / "{n} ရက် အခမဲ့ ရယူရန်"),
    `daysFreePlusAccess` ("You now have {n} days of free Plus access. Enjoy all features!" /
    "သင့်တွင် ယခု {n} ရက် အခမဲ့ Plus အသုံးပြုခွင့် ရရှိပါပြီ။ လုပ်ဆောင်ချက်အားလုံးကို ခံစားလိုက်ပါ!").
  - `String familyInviteIntroDays(int days)` from `familyInviteIntro` rewritten with `{n}` ("… The invitation lasts {n}
    days." / "… ဖိတ်ကြားချက်က {n} ရက် ခံပါတယ်။").
  - In Myanmar the `{n}` is written with Myanmar digits (a small private helper mapping 0-9 to ၀-၉).

- [ ] **Step 1: Write the failing tests** — `AppConfig.fromJson({})` → 30 / 14; `{"numbers": {"trial_days": 45,
  "invite_days": 3}}` → 45 / 3; `{"numbers": {"trial_days": "45", "invite_days": 0}}` → 30 / 14; English
  `trialFreeCaps(30) == 'ONE MONTH FREE'`, `trialFreeCaps(45) == '45 DAYS FREE'`, `claimTrialFree(45) == 'Claim 45 days free'`;
  Myanmar `claimTrialFree(45) == '၄၅ ရက် အခမဲ့ ရယူရန်'`, `familyInviteIntroDays(14)` ends with `'၁၄ ရက် ခံပါတယ်။'`.
- [ ] **Step 2: Run to fail** (`flutter test test/trial_invite_texts_test.dart`), **Step 3: implement** (screens read
  `context.watch<AppControlProvider>().config.trialDays` / `.inviteDays`), **Step 4: run to pass**, then `flutter test`
  and `flutter analyze` at the baseline.
- [ ] **Step 5: Commit** — `feat(app): the trial and invite lengths come from the server`.

### Task 7: Verify

- [ ] Full backend suite: `& "$S\pg\run_suite.ps1"` (about an hour); TOTAL with no problems or crashes; known flakes
  (test_books deadlock, test_family) pass on a rerun of that file alone.
- [ ] `flutter test`, `flutter analyze` (baseline), admin `npm run lint` (baseline) and `npm run build`.
- [ ] The `clean` check: the real `tunables` row is absent or as it was before the work started.
- [ ] Spec Deploy section still true: no migration; server first; app release for the texts.
