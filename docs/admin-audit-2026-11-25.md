# Admin panel audit (2026-11-25)

The owner wants to control as much of the app as possible from the admin panel. This is what the panel does today,
what in the app is still fixed in code, and the suggested improvements. Static reading only; nothing was changed.

## What the panel does today

Panel: `admin/src` (React + Vite). Backend: `admin_routes.py`, `ai_admin_routes.py`, `plans_admin_routes.py`,
`app_version_routes.py`. Roles: moderator (read-only), admin (write), super admin (deletes, admins, logs).

| Tab | Can do |
|---|---|
| Overview | 11 counters (users by plan, active, new, entries, goals, pending requests). Read-only. |
| Users | Search by name/email, plan filter, 50 per page. Detail: set plan + expiry, see/reset AI usage, devices, delete (super admin). |
| Broadcast | Push + in-app message to all / free / plus / pro / paid. |
| App versions | Android/iOS versions, download URL, notes, force update, minimum version. |
| AI usage & costs | Cost by user, family book, feature, date range. Read-only. |
| AI providers | Provider health; main model and backups per feature; test call. |
| Plans | Per-plan feature limits, cost caps, prices, family limits, upgrade texts, owner contact links. |
| Upgrade requests | Pending / done / dismissed; mark done, dismiss (notifies the user). |
| Feedback | Filter, change status, delete. |
| Admins, Activity logs | Super admin: create/delete admins; last 50 audit entries. |

## A. Things that can't be controlled yet (new control)

1. **App switches and announcements (none exist today).** No remote config, maintenance mode, registration switch,
   per-feature kill switch or in-app banner. The app fetches only `/api/plan` and the version check at start.
   - Maintenance mode with a message (en/my).
   - Registration open/closed.
   - Turn a feature off for everyone: chat, voice, receipt photos, insights, budget ideas, family, custom reports.
     The server enforces it (works for old app versions too); new app versions hide the button.
   - Announcement banner: en/my text, audience (plan), start/end dates, optional link.
   - Foundation: an `app_settings` table, audited admin edits, and `GET /api/app/config` read by the app at start.
2. **Editable messages.** About 140 notification texts per language (`notification_service.py`) and the emails
   (`email_service.py`) are in code. Admin overrides per key and language, with `{placeholder}` checks and
   reset-to-default. It would also be the place to do the Myanmar native review.
3. **Tunable numbers** (with safe min/max bounds):
   - Free trial length, 30 days (`auth_routes.py:602`).
   - Trial/renewal reminder lead times, 3 days and 1 day (`subscription_service.py:37-40`).
   - Budget alert at 80% (also baked into the alert text), goal reminder days 14/7/3/1, "ending soon" 3 days.
   - Unusual-spending rule (3x average, floors and cap per currency).
   - Chat message length and history, custom-report limits, family invite validity (14 days).
   - Default budgets for new users per category and currency (`budget_service.py:52-59`).
   - Risk: changing an alert threshold mid-period can re-fire or skip one alert.
4. **Job times.** Reminders 09:00, unusual spending 08:00, recurring entries 06:00, weekly report Monday 05:00,
   monthly report the 1st at 06:00 (`local_jobs.py`, `insight_schedule.py`). The reminder and report times are safe
   to make editable (a change can skip or repeat once that day); the rollover and tick interval should stay in code.
5. **Ko Toe Pwar's tone.** Every prompt repeats the persona. An editable persona/tone snippet is reasonable; the
   output rules (JSON shapes, categories, figures) must stay in code.
6. **Category editor.** The `categories` table exists, but entries and budgets store category names as text and
   some code matches names, so renames need a data migration. Do last, if at all.

Stays in code or env: secrets and keys, database, CORS/proxy, currencies (touch too many places), the API address.

## B. Managing users

- No way to edit a user's name/email/currency, suspend or ban, sign them out of all devices, or send a password reset.
- Upgrade requests: no one-click "grant the requested plan"; the admin has to go to Users and set it by hand.
- Users list: no sorting (joined, last active, AI cost); "last active", budgets, chat sessions and language are
  returned but not shown. The list query runs 5+ queries per user (`admin_routes.py:569-590`).
- No message to a single user, no notification history, no export (CSV).

## C. Panel quality and safety

- Audit log gaps: feedback status/delete and admin logins (success and failure) aren't logged; the Logs tab shows
  only the last 50, with no paging or filter by admin/action/user.
- Admins: can't change another admin's role or reset their password. No 2FA. Login lockout is in memory only.
- Native `alert`/`confirm` pop-ups throughout `App.jsx`; some errors are silently ignored (user detail,
  pending badge, feedback stats). Plans "Save" replaces everything with no confirm or summary of changes.
- Broadcast: confirm doesn't show how many people get it; no preview, history or scheduling.
- Lists capped without paging: AI usage users (50), upgrade requests (200).
- Overview has no trends (sign-ups, active users, revenue, AI cost over time).
- `App.jsx` is ~2,000 lines; worth splitting as it grows.
- Admin token is kept in `localStorage` (8 h) with no idle logout.

## Suggested order

1. A1 app switches and announcements (the foundation the rest reuses), with B's one-click upgrade grant.
2. A2 editable messages (and the Myanmar review through it).
3. A3 tunable numbers and A4 job times, on the same settings table.
4. B user management, C audit/log fixes.
5. A5 tone, A6 categories.
