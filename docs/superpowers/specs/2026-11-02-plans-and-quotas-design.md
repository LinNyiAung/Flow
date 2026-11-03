# Plans and AI quotas: design

Date: 2026-11-02. Branch `plans-and-quotas`, cut from `ai-provider-switching`, which it builds on: the AI provider runner, the AI Providers admin page and usage cost records.

## Why

Today the app has two plans, Free and Premium. Every AI feature is Premium-only: chat, weekly and monthly insights with translation, budget suggestions, receipt photo, text and voice entry. Reports are Premium-only too. A new user can claim one 30-day Premium trial, and after it ends they get no AI at all.

The owner wants a small free allowance instead of a hard wall. Free users keep seeing what the AI can do, and running out becomes the natural moment to upgrade. The owner also wants two paid plans, Plus and Pro, with Pro offering a smarter "Advanced" chat. Spending on AI must stay predictable per user.

The app is not released yet. No one has paid, and payment is out of scope.

## Goals

1. **Three plans: Free, Plus and Pro.** They replace Free and Premium.
2. **Counted allowances.** Each plan gets per-period counts for each AI feature. The owner edits them in the admin panel, and changes apply without a redeploy.
3. **Users always know where they stand.** Each AI feature shows what's left. Reaching a limit gives a friendly message with an Upgrade button, never a bare error.
4. **Advanced chat for Pro.** Pro users get a Standard / Advanced switch in AI chat. Advanced uses a provider and model the owner picks on the AI Providers page.
5. **A hidden monthly cost cap per user**, set per plan. It protects the owner from runaway spend.
6. **The trial becomes a Plus trial.** When it ends, the user drops to Free with its allowances, not to nothing.

## Non-goals

- **Payment.** Upgrading stays manual: the user contacts the owner, and the owner sets the plan and end date in the admin panel, as Premium works today.
- **Credits or cost-based allowances shown to users.** Users only ever see counts.
- **Per-plan provider or model choice for other features.** Only chat gets Advanced. Every other feature uses its AI Providers setting for all plans.
- **Compatibility with old app builds.** The app is unreleased, so the backend and the app change together.

## Anti-goals

These would count as failure even if everything technically works:

- A user hits a limit and sees an error with no explanation, no reset time and no Upgrade path.
- Two quick requests both slip past the last allowance. Checking and counting must be atomic per user and feature.
- A failed AI request (an error, every provider down, an unusable answer) uses up the user's allowance.
- A Free user loses any non-AI feature they have today: manual transactions, budgets, goals and so on.
- The owner has no way to see that a user hit the cost cap, or no way to give someone more.

## Plans and starting limits

These are the defaults seeded on first deploy. All of them are editable on the admin Plans page.

| Feature | Free | Plus | Pro |
|---|---|---|---|
| AI chat messages | 5 per week | 100 per month | 400 per month, of which up to 100 may be Advanced |
| Monthly insight | 1 per month | included | included |
| Weekly insights | not included | included | included |
| Insight translation (Myanmar) | not included | included | included |
| Receipt photo / text / voice entry (one combined count) | 10 per month | 150 per month | 500 per month |
| AI budget suggestion | 1 per month | 5 per month | 20 per month |
| Reports | not included | included | included |
| Hidden monthly AI cost cap per user | $0.10 | $1.00 | $3.00 |

"Not included" means the feature is locked for that plan. The app shows it with the Upgrade path, as Premium-locked features are shown today. "Included" means it is available with no count, or, for insights, generated as today.

**Periods.** Weekly allowances reset on Monday at 00:00 and monthly ones on the 1st at 00:00, in the app timezone (`SCHEDULER_TIMEZONE`, default Asia/Yangon, the same one the scheduler uses). Each feature's period type (week or month) is part of the plan settings, so the owner can change, for example, Free chat from 5 per week to 20 per month.

## What counts as one use

- **One user action is one use**, counted only when the AI produced a usable answer. Failed requests count nothing (anti-goals).
- **Chat:** one message the user sends is one use, however long the answer.
  - An Advanced message counts once towards the chat total and once towards the Advanced allowance.
  - If the answer started streaming and the user then disconnects, it counts.
- **Usable answer.** An answer is usable when the runner returns one: no exception, and the feature's own parse succeeds. An extraction that validly finds zero transactions still counts, because the AI did the work. A chat answer the runner treats as unusable (empty, refused, filtered) does not count.
- **Entry:** receipt photo, a text entry (single or multiple transactions) and a voice entry each count once, against the one shared count.
  - Voice is one use even though it makes two AI calls (transcribe, then extract). The builder decides how, for example by counting at the extraction step only when it follows a transcription. Whatever the mechanism, the user sees one use.
- **Budget suggestion:** one request is one use.
- **Insights:**
  - **Free.** The monthly insight is generated on demand, when the Free user opens Insights, not by the scheduled job. That avoids spending on inactive Free users.
    - **Trigger.** A new generation happens only when the user has no real (non-placeholder) monthly insight for the current calendar month. It covers the same period the scheduled monthly job would cover if it ran now, so the two always produce the same kind of insight.
    - **What counts.** A real insight counts as the month's 1. A "welcome"/no-data placeholder does not count.
    - **Insight already stored.** If one exists for this month, for example from the scheduler while the user was still on Plus, it is shown and nothing is counted.
    - **No regenerating.** Free users cannot regenerate it.
    - **Generation fails.** If generation fails, the latest older insight is shown as today and nothing is counted.
  - **Plus and Pro.** The scheduled weekly and monthly jobs keep generating for them as today, and these don't count against anything. Manual regenerate keeps today's rules.

## Insight language

The language an insight is shown in no longer follows the app language. The Insights screen has its own **English / မြန်မာ** toggle, remembered on the device.

- **Plus and Pro.**
  - The toggle starts on the app language, and the user can flip it at any time.
  - Each insight is translated once and the translation is stored, so flipping back and forth costs nothing more.
  - The app asks the server for the language the toggle shows, not the app language.
- **Free.**
  - Insights are always shown in English.
  - The မြန်မာ option is visible but locked. Tapping it opens the Upgrade screen.
  - The server never translates for a Free user, even if the request asks for Myanmar. It returns English with an indication that translation is not included in the plan.
- **Scheduled background AI jobs** (for example budget auto-create) never count against allowances. They only run for users whose plan includes the feature. The builder checks each scheduled AI job against today's Premium filter and applies "Plus or Pro" where it says Premium.

## Advanced chat (Pro only)

- **The Advanced feature on the AI Providers page.** It is a new row, "Advanced chat", with its own provider, model and backups, like every other feature. Its built-in default is Claude with `claude-sonnet-5-5`, with backups chosen the way they are for other features. If Claude isn't configured, the normal fallback rules apply.
- **The switch in chat.** Pro users see a Standard / Advanced switch in the chat screen. The choice is remembered on the device. Free and Plus users don't see it.
- **Advanced allowance used up.** When a Pro user's Advanced allowance is used up, their next Advanced message is answered by Standard. It shows a short note that Advanced is used up until the reset date, and the switch returns to Standard.
- **Backups.** An Advanced message answered by one of the Advanced row's backups still counts as Advanced. The backup is the owner's configured Advanced chain.
- **Server-side check.** The server enforces the plan. An Advanced request from a non-Pro user is answered as Standard, or rejected; the builder chooses which. It is never answered as Advanced.

## Hidden cost cap

- **How spend is measured.** Each user's AI spend this calendar month (app timezone) is taken from the existing `ai_usage` cost records, for every feature the user triggered. Scheduled jobs count too, because they are real spend on that user.
- **When it's checked.** Before any user-initiated AI action, if the user's spend this month is at or above their plan's cap, the action is refused. The user sees a polite message: "You've reached this month's AI limit; it resets on <date>." It includes the Upgrade path when a higher plan exists. Scheduled insight jobs skip that user for the rest of the month.
- **What the owner sees.** The user's admin page shows a "Cost cap reached" flag with the month's spend.
- **Reset usage.** It stores a reset time for that user. From then on, the user's spend towards the cap is measured from the later of the month start and the reset time, so they get a fresh full cap for the rest of the month. `ai_usage` rows are never deleted, because cost reports depend on them. There are no per-user custom caps or limits; Reset is the owner's way to give someone more.
- **It's a hidden safety net.** Users never see costs or the cap amount.

## Trial and plan changes

- The one-time 30-day trial gives Plus. The existing claim flow stays; the plan it sets becomes `plus`.
- Existing `premium` users, including trials, become `plus` with the same end date. This is a one-time data migration, and `premium` stops being a valid plan.
- **Plan end.**
  - A Plus or Pro plan with an end date in the past is treated as Free immediately, as Premium expiry works today.
  - The hourly expiry job moves the user to `free` and sends the existing "has ended" notification, reworded for the plan name.
- **Trial reminders.** For trial users only, new notifications are sent 3 days before the trial ends and on the last day. They are in English and Myanmar, like the other notifications.
  - **Telling a trial apart.** A trial needs its own marker, because `has_claimed_free_trial` stays true forever. Use a `trial_ends_at` (or similar) set when the trial is claimed and cleared whenever an admin changes the user's plan.
  - **Who counts as on a trial.** Only users with that marker, while it is in the future, get reminders and show as "trial" in the app. Users migrated from Premium are not marked as trials.
- **Batch transaction saving.** `POST /api/transactions/batch-create` is not an AI call and becomes open to every signed-in user. Free users can already add transactions one by one, and the Free voice and text flows need it to save their result.
- **Reports scope.** Reports stays exactly as gated today: the app locks the Reports screen for Free, and the server gates the PDF download. Plus and Pro replace Premium in both places. The report data endpoints are not newly gated.
- **Plan changes mid-period.** Allowances use the current plan's limits against this period's usage so far. For example, a Free user who used 5 chats and upgrades to Plus has 95 of 100 left this month. The builder decides how a weekly Free count maps onto a monthly Plus count, and records the call.

## App (Flutter, mobile and web)

- **Remaining allowance on each AI feature.** Every AI entry point shows what's left in a small, unobtrusive line, for example "3 of 5 left this week". That includes chat, insights, receipt, text and voice entry, and budget suggestion. Pro chat shows the Advanced remaining when Advanced is selected.
- **Hitting a limit.** It shows a friendly sheet or dialog saying what ran out, when it resets, and an Upgrade button.
- **Locked features.** Weekly insights, translation and Reports on Free show the same Upgrade path.
- **Upgrade screen.** This is the existing subscription screen, reworked. It compares Free, Plus and Pro with the current limits from the server, so the screen never hard-codes numbers. It marks the user's current plan and shows an **upgrade contact message**. The owner edits that message in English and Myanmar on the admin Plans page, for example "Message us on Viber at …". The app has no contact info today.
- **Plan names.** These replace "Premium" everywhere in the app: the badge, the drawer, settings, the home screen and so on. Every new string is added in English and Myanmar.

## Admin panel (React)

- **New "Plans" page.** It is a table of every feature for Free, Plus and Pro.
  - Each cell is one of three states: **locked**, **included** (no count), or **counted**, with a number and a period of week or month. Pro chat also has its Advanced sub-count.
  - It also has each plan's monthly cost cap, and the upgrade contact message in English and Myanmar. Save applies immediately (refresh within about a minute, as on the AI Providers page). Moderators see it read-only; admins and super admins can change it.
- **User list and user page.**
  - The plan picker offers Free, Plus and Pro, with an end date.
  - The user page shows this period's usage per feature (for example "Chat 3/5 this week, Entries 7/10 this month, Advanced 12/100"), this month's AI spend, and the cost-cap flag.
  - A "Reset usage" button clears this period's counts and the cost-cap flag for that user. It is logged in admin action logs, like other admin changes.
- **Dashboard and broadcasts.** These count and target Free, Plus and Pro, plus "all paid" (Plus or Pro).
- **AI Providers page.** It gains the "Advanced chat" row.

## Backend

- **Plans and checks.** These replace the single Premium check. A dependency or helper answers three questions:
  - Is this feature included in this user's plan?
  - Is there allowance left?
  - Is the user under the cost cap?
- **Check-and-count is atomic per user, feature and period**, so concurrent requests can't overspend.
- **Reaching a limit returns a response the app can recognise without reading message text.** It carries a stable error code, the feature, the reset time, and whether an upgrade would help. The builder picks the HTTP status and body shape. A locked feature returns the same kind of response.
- **One endpoint gives the app everything it needs:** the user's plan, end date and trial state, plus each feature's limit, period, used count and reset time. The app uses it for the counters and the Upgrade screen.
- **Plan limits are stored in the database and seeded with the defaults above.** They are read with a short cache, like AI provider settings.
- **`users.subscription_type` allows `free`, `plus` and `pro`,** with an Alembic migration that maps `premium` to `plus`.

## Testing expectations

These follow the project's existing approach: the backend e2e suites in `e2e/` against the stubbed server, admin lint and build, `flutter analyze` and `flutter test`, and the Flutter integration flows. Specifically:

- every limit, period reset and plan transition (trial → Free, Free → Plus mid-period, expiry);
- that concurrent requests can't overspend;
- that failed AI calls don't count;
- that voice counts once;
- Advanced falling back to Standard when used up;
- the cost cap refusing and the admin reset clearing it;
- that moderators can't edit plans.

## Left to the builder

- Table and column design for usage counters and plan limits.
- The HTTP status and error body for "limit reached" and "not included".
- How voice is counted once, and how a weekly count maps across a plan change mid-period. Record both calls.
- The visual design of the counters, the limit sheet and the Upgrade screen, following the app's existing style.
- Whether a non-Pro Advanced request is downgraded or rejected.

## Owner decisions recorded in conversation

- Plans: Free, Plus and Pro; the trial gives Plus; current Premium users become Plus.
- Starting limits: the table above, editable in the admin panel.
- Pro gets a user-facing Standard / Advanced switch in chat only, with up to 100 Advanced messages within its 400 per month. The owner picks the Advanced provider and model.
- Allowances are counts for users, plus a hidden per-user monthly cost cap per plan.
- No payment integration yet; upgrades are manual.

- Free insights are English only. Insight language is chosen with its own toggle on the Insights screen, independent of the app language. Myanmar is locked for Free.

## Calls made by Claude (check these)

- Free on-demand monthly insight:
  - generated only when there's no real insight for the current month;
  - placeholders and failures don't count;
  - an existing insight is shown for free.
- Usable answer: an extraction that finds zero transactions still counts; an empty or refused chat answer doesn't.
- An Advanced message answered by an Advanced backup counts as Advanced.
- Trials get their own end-date marker. Only marked trials get reminders, and migrated Premium users are not trials.
- "Reset usage" gives a fresh cost cap from the reset time and deletes no usage records. There are no per-user custom limits.
- Batch transaction saving opens to all users.
- Reports stay gated as today, with Plus/Pro instead of Premium.
- Plan cells are locked, included or counted. The upgrade contact message is edited on the Plans page.

- A failed AI request doesn't count. A chat message counts once, however long the answer.
- Free users' monthly insight is generated on demand, not by the scheduled job.
- Scheduled jobs don't count against allowances, but their spend does count towards the cost cap.
- Hitting the cost cap pauses user-initiated AI until the 1st, rather than only turning off Advanced.
- The Advanced built-in default is Claude Sonnet.
- The cost caps start at $0.10 / $1 / $3.
- The upgrade screen shows a contact message.
