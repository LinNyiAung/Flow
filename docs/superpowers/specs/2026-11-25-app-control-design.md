# App control: feature switches, maintenance mode and announcements (design)

Date: 2026-11-25. Area 1 of `docs/admin-audit-2026-11-25.md`.

## Intent

The owner wants to control as much of the app as possible from the admin panel, without a redeploy or an app
release. Today the panel can change plans, prices, limits, AI providers and app versions, but it can't pause
anything for everyone, close the app for maintenance, or tell users something inside the app. This adds an
**App control** tab that can:

- pause individual features for everyone, with the owner's own message;
- open or close sign-ups and the free trial offer;
- pause new families and invites;
- put the whole app into maintenance with a message;
- show announcement banners in English and Myanmar.

Typical uses: an AI provider is down or costs spike (pause chat or voice), a risky deploy (maintenance), a
promotion or a known problem (announcement).

## Goals

- Every switch is changed in the admin panel, is enforced by the server, and is shown properly in the app.
- A change takes effect on the server within a minute (at once on the worker that saved it), and in the app the
  next time it starts or comes back to the front.
- Older app versions that don't know about any of this are still protected by the server and, wherever they
  can, show the owner's message (they already show `detail.message` from an error body:
  `ApiService._detailToMessage`, `frontend/lib/services/api_service.dart:519-548`).
- Every change is in the admin activity log.

## Non-goals

- Per-user or per-plan feature switches (plan limits already do per-plan), gradual rollouts, A/B tests.
- Editing the app's or notifications' texts (area 2), tunable numbers (area 3), job times (area 4).
- Pausing the core money features (entries, budgets, goals, reports screen) one by one: maintenance covers the
  "close everything" case.
- Firebase Remote Config or any new Google service account (decided with the owner; see Approaches).

## Anti-goals (a failure even if it works)

- **Locking people out of their own money records** by a feature switch. Pausing family stops new families and
  invites only; existing family books keep working. Maintenance is the only full block, and it is explicit.
- **A paused feature that looks like a crash** or like "upgrade to unlock". A paused feature always says it is
  paused, with the owner's message or the standard one.
- **The owner locking themselves out.** The admin panel and its API are never blocked; maintenance asks for
  confirmation and lets tester accounts through.
- **A broken setting breaking the app.** If the app can't read the config, it carries on as if nothing is paused
  (the server still enforces).

## Approaches

1. **Our own settings in the database, edited in the panel, enforced by the server, read by the app (chosen).**
   One place for the truth; the server refuses a paused request even from old apps; the panel uses the existing
   admin sign-in, roles and activity log.
2. **Firebase Remote Config (rejected by the owner).** The values live on Google's servers, normally edited in
   Firebase's website; editing them from our panel needs a Google service account and Google's whole-template
   API. Only the app reads them, so the server would still need its own copy to enforce a pause, and apps cache
   them (up to 12 hours by default). The web app would need the Firebase web SDK.
3. **Reuse the plan limits ("locked" on every plan).** Shows "upgrade to unlock" (wrong for a pause) and only
   covers the AI allowances, not sign-ups, the trial, family or maintenance.

## Decisions made with the owner

- **Paused, not hidden:** a paused feature's button stays visible, greyed; tapping it shows the message.
- **Everything is in our admin panel.** No Firebase Remote Config, no new Google service account. The existing
  Firebase push notifications are unchanged.
- **The feature list, maintenance, announcements and timing below were shown to the owner and accepted.**

## Calls made after the builder check (mine, for the owner to check)

1. **No "typed entries" switch.** The app has no typed AI entry; the text-reading routes are only voice entry's
   second step. They come under the Voice switch, so pausing voice can't break halfway after using an allowance.
2. **Pausing budget ideas also stops the AI in automatic budget renewal**, which then uses its existing non-AI
   amounts. Otherwise a pause for cost or an outage would leave that background AI spend running.
3. **Maintenance keeps open:** email verification, password reset, the landing site's prices and download link,
   and the version check.
4. **Pausing translation shows reports in English with the existing note** rather than an error, because the app
   gets Myanmar reports by reading them, not with a button.

## The switches

Each switch has: on/off, and an optional message in English and in Myanmar. An empty message uses the standard
one, "Paused for now: {feature}. Please try again later." (and its Myanmar text), with the feature's name.
(Changed 2026-11-26 from "{feature} is paused for now", which read wrongly for plural names such as "Sign-ups".)

| Switch | Server routes it refuses while paused | Where the app greys it |
|---|---|---|
| Chat | `POST /api/chat`, `POST /api/chat/stream` (history stays readable) | chat input / chat entry point |
| Voice entry | `POST /api/transactions/transcribe-audio`, and `extract-from-text` / `extract-multiple-from-text` (today only voice's second step uses them, `screens/transactions/voice_extraction.dart`) | voice button |
| Receipt photos | `POST /api/transactions/extract-from-image` | camera / photo button |
| Budget ideas | `POST /api/budgets/ai-suggest`; and the automatic budget renewal uses its non-AI amounts instead of asking the AI (`_ai_category_budgets` already falls back) | "suggest" button |
| Weekly and monthly reports | report generation in `GET /api/insights` (when it would generate), `POST /api/insights/regenerate`, `POST /api/insights/generate-weekly`; the scheduled reports (`insights_service._scheduled_insight`) | generate / regenerate buttons |
| Custom reports | `POST /api/custom-insights` | custom report button |
| Myanmar translation | `POST /api/insights/translate-myanmar`, `POST /api/custom-insights/{id}/translate`; and the Myanmar read of a report (`GET /api/insights?language=mm` translates while reading): while paused it returns the English report with the existing "translation isn't available" note, not an error | custom report translate button; the weekly/monthly report simply shows in English with the note |
| Sign-ups | `POST /api/auth/register` | register screen |
| Free trial offer | `POST /api/auth/claim-free-trial` | the trial offer |
| New families and invites | `POST /api/family`, `POST /api/family/invites`, `POST /api/family/invites/{id}/accept` | create family, invite, accept invite |

- Reading what already exists always works while paused: saved reports, chat history, family books.
- **Scheduled reports while paused are skipped, not made up later** (the owner's call). A report job that finds
  its feature paused counts as done for that period.
- A paused request is refused with HTTP 403 and
  `{"detail": {"code": "feature_paused", "feature": "<switch key>", "message": "<in the user's language>"}}`.
  It is checked before any plan allowance is used, so nothing is counted.
- When report generation is paused, `GET /api/insights` still returns the latest saved report; it just doesn't
  make a new one.

## Maintenance mode

- Settings: on/off, a message (en/my, with a standard one if empty), an optional "back by" time, and a list of
  tester emails.
- While on, the server refuses every app API request with HTTP 503 and
  `{"detail": {"code": "maintenance", "message": "...", "back_by": "<ISO time or null>"}}`, except:
  - the admin API (`/api/admin/...`) and the admin login;
  - the config endpoint (below);
  - sign-in, email verification and the password-reset steps, so testers can get in;
  - the landing site's public reads (`GET /api/plan/public`, `GET /api/app/latest-android`) and the version check
    (`POST /api/app/check-version`), so the public site keeps its prices and download link and old apps can still
    be told to update;
  - requests from a tester (the token's email is on the list).
- The app shows a maintenance screen (message, "back by" time in the user's zone, a retry button, and a small
  "Sign in" link so a tester who is signed out can get in). It checks again on retry and when it comes back to
  the front.
- Scheduled jobs keep running (they are server-side; a reminder may arrive while the app is closed). Turning
  maintenance on in the panel asks for confirmation, naming who stays able to get in.
- Builder to check: how an old app version reacts to a 503 at start (its session restore treats 5xx as "server
  waking up" and retries). If that hides the message, let `GET /api/auth/me` through during maintenance so old
  apps reach the home screen and show the message on their next action.

## Announcements

- Several can be set up ahead. Each has: English text, Myanmar text (both required), style (info or warning),
  an optional link (URL plus its button label in en/my), the plans it shows to (any of free/plus/pro), a start
  time and an optional end time.
- The app shows the newest live announcement for the user's plan at the top of the dashboard, in the user's
  language, with a close button. Closing it hides it on that device; editing it later shows it again (the
  device remembers the id and the last-changed time).
- Only `http(s)` links are accepted; the app opens them outside the app.

## Config the app reads

- `GET /api/app/config`, works signed in or not. Signed in, it answers for that person (their plan, whether
  they are a tester). Shape (names are the builder's call):
  - `maintenance`: on, message, back_by, and whether this person may still get in;
  - `paused`: each switch's key with its message, in the person's language (signed-out: the language the app
    asks for);
  - `announcement`: the one to show now, or none.
- The app reads it at start (before the login screen, so sign-ups and maintenance show there too) and every time
  it comes back to the front. A failed read keeps the last known config, or "nothing paused" if there is none.

## Storage

- An app settings record holding the switches and maintenance (one validated document, like the plan settings
  in `plans/store.py`), and an announcements table. A new Alembic migration creates both; no existing table
  changes.
- The server keeps the settings in memory, refreshed every minute and updated at once on save (the same pattern
  as `plans/store.py` and the AI settings, `main.py:113-126`). Until the first load succeeds, nothing is paused.

## Admin panel: the App control tab

- Sections: Maintenance; Ko Toe Pwar features; Accounts (sign-ups, free trial); Family; Announcements.
- Each switch: a toggle, the two message fields, and a preview of what users will see.
- Announcements: a list (live, scheduled, ended), create, edit, delete, preview in both languages.
- Moderators can see the tab; admins and super admins can change it. Every change is logged with
  `log_admin_action`, saying what changed.
- Turning maintenance on, and pausing sign-ups, ask for confirmation.

## The app

- A config provider read at start and on resume; the maintenance screen in the start-up flow in `main.dart`
  (before the login and home screens); the sign-ups-closed state on the register screen; the banner on the
  dashboard; the greyed buttons listed above, each showing the message when tapped.
- A `feature_paused` or `maintenance` error from any call (the config may be up to a resume old) shows the
  server's message and refreshes the config.
- New app strings in English and Myanmar (the Myanmar ones join the native review).

## Testing

- Backend e2e (a new test file registered in `run_backend_suite.py`): each switch refuses its routes with
  `feature_paused` and the right language, without using an allowance; reading still works; paused scheduled
  reports are skipped and not made up; maintenance blocks the app API but not the admin API, the config, sign-in
  or a tester; announcements by plan and time window; settings validation (bad links, missing Myanmar text);
  only admins can change settings and every change is logged; the cache refresh.
- Flutter tests: the config provider (start, resume, failed read), the maintenance screen, the banner (shows,
  closes, comes back after an edit), a greyed button showing the message, the register screen when closed.
- Admin panel: it builds and lints; a browser check of the tab against the local test server.

## Left to the builder

Exact field and key names, the table layout, the panel's component split, the app widget structure, the exact
standard message wording (both languages), and how the greyed state looks, within the decisions above.

## Deploy

One migration; ship the server and the app together. Old app versions are protected by the server and show the
messages as errors; the banner and the maintenance screen need the new app version.

Migration `b7d2e9c4a1f3` (the announcements table) must be applied with `alembic upgrade head` before or together
with the new server; the announcement routes fail without the table. Ship the server first or together with the app:
an app without the new server fails open (it reads no config and shows nothing paused).
