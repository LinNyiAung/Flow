# Numbers and times: tunable settings from the admin panel (design)

Date: 2026-11-27. Areas 3 (tunable numbers) and 4 (job times) of `docs/admin-audit-2026-11-25.md`.

## Intent

The owner wants to control as much of the app as possible from the admin panel (the audit's ask). Areas 1 (App
control) and 2 (Texts) are done. This adds the numbers that shape reminders, alerts, the trial and invites, and the
local times of the daily jobs, so they can be changed without a redeploy. The case the owner named: a longer free
trial for a promotion.

## Goals

- From a new admin tab, "Numbers & times", an admin changes the settings listed below. Each has a default (today's
  value, kept in code), a safe allowed range, and a one-line note on what it affects and when a change takes effect.
- A change takes effect on the server within a minute (at once on the worker that saved it), like App control.
- The app shows the same trial length and invite validity the server uses (read from the server).
- Every save is in the admin activity log, with each changed setting's old and new value.
- Two admins saving at once: the second save is refused ("changed by someone else, reload"), not lost.

## The settings

Numbers (area 3):

| Setting | Default | Allowed | Notes |
|---|---|---|---|
| Free trial length (days) | 30 | 7-90 | Trials claimed after the change (the trial starts when a person claims it, `POST /claim-free-trial`, not at sign-up); running trials keep their end date. |
| Trial / renewal "ends soon" reminder (days before) | 3 | 2-14, and less than the trial length | One value for both (as today). The "last day" reminder stays at 1 day: its text says "within 24 hours". |
| Goal reminder days (days before the target date) | 14, 7, 3, 1 | 1-4 distinct whole days, each 1-60 | |
| Budget "ending soon" (days before the end) | 3 | 1-14 | |
| Family invite validity (days) | 14 | 1-60 | New invites only; sent invites keep their expiry. |
| Large expense: times the person's average | 3 | 1.5-10 | Rule 1 of unusual spending (one big expense). |
| Large expense: minimum amount, per currency | K100,000 / $100 / ฿2,000 | above 0, at most K100,000,000 / $100,000 / ฿2,000,000 | The floor of rule 1. With no spending history yet, the bar is 1.5x this minimum (a fixed 1.5 in code; today's 150,000 / 150, unchanged for MMK and USD). |
| Unusual week: times the usual weekly amount | 1.5 | 1.1-5 | Rule 2 (one category's week). |
| Unusual week: minimum difference, per currency | K50,000 / $50 / ฿1,000 | above 0, same maximums | |

The currencies are the app's three (MMK, USD, THB); any other currency uses the USD values, as today.

Times (area 4), each on the person's (or book's) own clock, in 15-minute steps (the job tick runs every 15 minutes):

| Setting | Default | Allowed | Covers |
|---|---|---|---|
| Reminders | 09:00 | 07:00-21:00 | goal deadline, budget ending, payment reminders, "budget now active" |
| Unusual spending check | 08:00 | 07:00-21:00 | |

Both start no earlier than 07:00 so they always run after the overnight rollover (00:30) and the repeating entries
(06:00), as today. The trial and plan reminders are not local-time jobs (they run hourly) and are unchanged.
| Weekly report | Monday 05:00 | 01:00-23:00 (time only; Monday stays) | |
| Monthly report | the 1st, 06:00 | 01:00-23:00 (time only; the 1st stays) | |

Behaviour change to note: Thai baht today shares the USD floors (100 and 50), so ฿100 counts as a large expense.
The new baht defaults (฿2,000 and ฿1,000) follow the ratio the default budgets already use (about 20 baht per dollar).

## Calls made after the builder check (mine, for the owner to check)

1. **The trial length applies when a trial is claimed**, not at sign-up (that is how trials work today), so people
   who signed up earlier but haven't claimed yet get the new length too. Good for a promotion.
2. **The "ends soon" reminder must be shorter than the trial**, refused on save otherwise (else everyone would get
   "your trial ends soon" right after claiming).
3. **Changing the "ends soon" window doesn't resend**: a person who already had that reminder for this trial or
   plan doesn't get it again; a person who hadn't gets it on the next hourly run if they are now inside the window.
4. **Reminder and unusual-spending times start at 07:00 at the earliest**, so the order of the overnight jobs holds.
5. **Unusual-spending amounts have a maximum per currency** (above), so a typo can't switch the alerts off.
6. **The app's texts keep Myanmar digits** in Myanmar ("ရက် ၃၀"), as now.
7. **Conflicts are checked against the stored record**, not a server's cache, so a stale page is always refused.

## Non-goals (kept in code)

- The 80% budget alert: "80%" is written in the alert's title and message, the app's settings screen, the budget
  colours and Ko Toe Pwar's prompts, and changing it mid-period can re-fire or skip an alert.
- Chat limits (message length, history): cost protection, already covered by the per-plan AI cost caps.
- Starting budgets for new users (a category x currency grid, rarely changed; the AI suggests budgets anyway). Can be
  added later as another setting.
- The overnight budget rollover (00:30) and repeating entries (06:00): other jobs depend on their order.
- The weekly report's day and the monthly report's day; per-person or per-plan values; the "last day" reminder.
- The website: it does not state the trial length today, so nothing there needs to follow.

## Anti-goals (a failure even if it works)

- A bad value breaking reminders or jobs: every value is checked against its range on save; a stored value that is
  missing or out of range falls back to its default (and is logged), field by field.
- A change causing a burst of repeats: a job never runs twice for the same local date (the existing
  `local_job_runs` claim), so a new time takes effect at once without double runs or skips; notices keep their
  existing duplicate guards.
- The app promising a trial length the server doesn't give: the app reads it from the server.

## Approaches

1. **Their own settings record (chosen by the owner).** A JSON document in the existing `app_settings` table under
   its own key, cached in memory, loaded at startup, refreshed every minute and updated at once on save (the App
   control pattern, `app_control.py`). No migration. Saves never touch App control's switches. A version number in
   the record refuses a stale save.
2. **Added to App control's document.** Less code, but one save writes switches and numbers together (two admins in
   different sections could undo each other) and its validation grows into one long list.
3. **One row per setting with versions (like Texts).** Per-setting history and conflict checks, but a row and
   migration work for about fifteen numbers changed a few times a year. The activity log already gives the history.

The owner asked which is best long term; option 1: a new setting is one entry in code (default, range, label) and
appears in the panel on its own; the areas stay separate; the log keeps history; the version check covers option 3's
real advantage.

## How it works

- **Catalogue in code:** one place lists every setting: key, default, kind (days, list of days, multiplier, amount per
  currency, time of day), range, and the panel's label and note (English; the panel is English-only today). The
  panel renders from the catalogue the API returns, so a setting added later needs no panel change.
- **Stored document:** only the values that differ from the defaults, plus `version`. Reading a setting: the stored
  value if present and valid, else the default.
- **Readers:** each place that uses a number today reads it through the settings module instead of its constant:
  - trial length when a trial is claimed (`auth_routes.py` `claim-free-trial`, `timedelta(days=30)`);
  - the "ends soon" window (`subscription_service.TRIAL_REMINDER_SOON` / `PLAN_REMINDER_SOON`);
  - goal reminder days and budget "ending soon" (`tz_utils.GOAL_REMINDER_THRESHOLDS`, `BUDGET_ENDING_SOON_DAYS`,
    and the windows built from them in `notification_service`);
  - invite validity (`families/service.py` `INVITE_DAYS`);
  - the two unusual-spending rules (`notification_service.check_large_transaction`, `analyze_unusual_spending`);
  - the job times (`local_jobs.LOCAL_JOBS`, and the weekly/monthly crons in `insight_schedule.py`, which the app's
    "Next insight" line also reads, so it follows the setting).
- **App:** `GET /api/app/config` (public, already read at start) gains the trial length and invite validity. The app
  shows the trial length on the subscription screen ("ONE MONTH FREE", "Claim 1 month free", and "You now have 1 month
  of free Plus access" after claiming): at 30 days the words stay as they are; any other length reads in days
  ("45 DAYS FREE", "Claim 45 days free", "You now have 45 days of free Plus access"). The family invite intro says
  "The invitation lasts {n} days". Both languages (Myanmar digits in Myanmar, as now); 30 and 14 when the server
  doesn't send them. (The unused "Try 30 days" string is left alone.) Needs an app release; older apps keep the fixed words.
- **Admin API:** read (moderator and up, `require_moderator_or_above`): the catalogue with each setting's default,
  range, note and current value, and the version. Save (admin and super admin, `require_admin_or_super`, as App
  control): the changed values with the version it was editing; refused with a clear message per invalid field
  (including the cross-field rule), or with a conflict when the stored version moved on (checked against the stored
  record, not the cache). Logged with old and new values.

## Admin panel: "Numbers & times" tab

- Grouped: Trial and plans, Reminders, Unusual spending, Family, Job times.
- Each setting: label, note, current value (editable), default, allowed range, a "Use default" button; changed fields
  marked.
- One Save for the page with a confirm showing the changes (old -> new); invalid fields shown inline; a conflict shows
  "changed by someone else, reload" and keeps the typing.
- Moderators see it read-only.

## Testing

- Backend e2e: defaults with nothing stored; save, range checks per kind, the conflict, moderator read-only, the log
  line; a stored bad value falls back to the default; each reader follows a changed value (trial end at sign-up,
  invite expiry, goal and budget reminder windows, the "ends soon" reminder, both unusual-spending rules including
  baht, a job's local time via the tick with a fixed `now`, the "Next insight" time); the public config carries the
  two numbers. Tests change settings only over HTTP or by patching in-process, and restore them (the stub caches the
  table, as with App control and Texts).
- App: unit tests for the two texts with a server value and with the fallback.
- Admin panel: lint and build; a browser check of editing, a range error, the confirm, and the conflict.

## Left to the builder

The settings key and document shape, the module and file names, the tab's component split and look, how the version
check is done in SQL, whether the readers take the value per call or per job run.

## Deploy

No migration. Ship the server first (the app falls back without it). The app texts need an app release.
