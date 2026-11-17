# Devices and budget categories: design

Schema project #2 of 4, agreed 2026-11-15 and designed 2026-11-17. It has three parts, built in this order:

1. **Budget categories:** a budget line stores its main and sub category in two columns instead of one `"Main - Sub"` text.
2. **Devices:** push tokens move from `users.fcm_token` into a `user_devices` table.
   - Every device a person is signed in on gets their notifications.
   - A device whose sign-in has expired stops getting them and receives one "sign in again" reminder.
3. **Sign-in renewal:** using the app extends the sign-in, so active people are never signed out after 30 days.

## Why

**Budget categories.**
- `budget_allocations.main_category` holds either `"Food & Daily Living"` or `"Food & Daily Living - Groceries"`.
- Every reader splits that text on `" - "`:
  - `budget_service._valid_budget_categories`, `update_budget_spent_amounts` and `_calculate_total_budget_excluding_subs`;
  - `create_budget_screen.dart` and `edit_budget_screen.dart`.
- The sub category is hidden inside a string, every place has to agree on the separator, and a category name containing `" - "` would break it.
- Transactions already store `main_category` and `sub_category` separately.

**Devices.**
- `users.fcm_token` holds one token per person. Signing in on a second device quietly takes notifications away from the first.
- `DELETE /api/auth/fcm-token` (on logout) clears the token whichever device logs out, so logging out of a tablet silences the phone.
- When Firebase answers "unregistered", `firebase_service` only prints it (`# TODO: Remove this token from database`). Dead tokens are kept forever.
- A sign-in lasts 30 days (`ACCESS_TOKEN_EXPIRE_MINUTES = 43200`). After that the app shows the sign-in screen but can't unregister its token (it gets 401), so the signed-out phone keeps receiving the person's notifications, amounts and budget names included.

**Sign-in renewal.** There is no renewal endpoint, so even someone who uses the app daily is signed out every 30 days.

## Goals

- **Budget lines** carry `main_category` (always) and `sub_category` (NULL for a main-only line), in the database, the API and the app.
- **Spending, totals, alerts and AI-made budgets** behave exactly as today for every existing budget.
- **Notifications:**
  - Every device a person is signed in on gets every push and silent data message meant for them.
  - Logging out on one device stops pushes to that device only.
  - A token Firebase reports as dead is removed.
- **Admin panel:** shows how many devices each person has, and when each was last seen, so shared accounts can be spotted later.
- **Expired sign-ins:**
  - A device whose sign-in has expired gets no further notifications until someone signs in on it again.
  - It gets one generic "sign in again" reminder instead, with no personal data. *(Owner's decision, 2026-11-17.)*
- **Sign-in renewal:** someone who opens the app at least once every 30 days is never signed out by expiry. *(Owner's decision, 2026-11-17.)*

## Non-goals

- **No limit on devices** signed in at once, and no automatic sign-out of older devices. The owner weighed this against account sharing on paid plans and decided against it for now:
  - AI limits are per account, so sharing doesn't raise cost;
  - sharing a money app exposes all your spending;
  - the family feature is the honest way to share;
  - a limit would sign honest phone-plus-tablet users out.

  The device table should make a limit a small later step, but nothing here builds one.
- **No per-device sign-in sessions.** Sign-in tokens stay stateless JWTs with the password-version check. Renewal issues a new one; nothing tracks or revokes individual sign-ins.
- **No web push.**
- **No change** to which notifications are sent, their text, or their links.
- **No old-app compatibility.** Only the owner's phone exists, and it is updated together with the backend (same as the books project).

## Anti-goals (a failure even if it technically works)

- **The owner's phone stops getting notifications after the deploy.** The migration must carry each existing `users.fcm_token` into a device row.
- **Any existing budget shows different spent amounts, totals, percentages or alerts after the migration.**
- **A device that was signed out keeps receiving another account's pushes.** Today a token belongs to one account; that must stay true.
- **A signed-out phone shows a person's amounts, budget names or goal names** in a notification. The sign-in reminder is the only push such a phone gets, and it carries no personal data.
- **An active person is signed out every month.**

## Constraints

- **Release:**
  - The app is pre-launch.
  - A short deploy outage is fine.
  - Migrations are fine.
- **Database:** Postgres, SQLAlchemy Core, one Alembic migration per part (or one for both). Each has a working downgrade on populated data.
- **Coordinated release:** the API and the Flutter app change together (`frontend/`), plus the admin panel (`admin/`) for device counts.
- **Tests:** the e2e suite (`e2e/`, run by `run_backend_suite.py`) and `flutter test` must stay green.
- **Environment:**
  - Windows PowerShell only.
  - Use only a local throwaway DB and the stub server.
  - Never read `.env*`.

## Approaches considered

**Devices: who gets a notification.**
- **A. Every signed-in device** *(chosen by the owner)*. This needs a devices table, sending to all of a person's tokens, and logout removing only that device.
- **B. Only the most recent device** (today's behaviour, stored more cleanly). It is less work, but the table would then add almost nothing.

**Devices: limiting shared accounts.**
- **A.** A limit of 2 devices with auto sign-out of the oldest.
- **B.** Per-plan limits.
- **C.** No limit, admin visibility only *(chosen)*.

A and B need per-device sign-in sessions checked on every request, and would sign out honest multi-device users. The sharing they guard against hasn't happened yet. C gives the evidence first.

**Devices whose sign-in has expired.**
- **A. Stop sending, plus one generic reminder** *(chosen by the owner)*. Personal figures stay off a signed-out phone.
- **B. Keep sending, as today.** Reminders might bring people back, but anyone holding the phone can read the text.

**Sign-in renewal.**
- **A. In this project** *(chosen by the owner)*. Without it, every active user would be signed out, and get the reminder, every month.
- **B. Later.**

**Budget categories.**
- **A. Two columns,** `main_category` and nullable `sub_category` *(chosen)*. This is the same shape as `transactions`.
- **B. An FK to the `categories` table.** Categories are a global seeded list. An FK cannot express a main-only line cleanly (`sub_category` NULL skips the whole composite FK). It would also block an admin renaming a category, and transactions don't use one.
- **C. Keep the text.** This is the problem we're fixing.

## Part 1: budget categories

**Schema.**
- `budget_allocations.main_category` keeps its name and now holds only the main category.
- New column `sub_category Text NULL`.
- **Migration upgrade:** for every row whose `main_category` contains `' - '`, split on the **first** occurrence: main = text before it, sub = text after. Other rows keep `main_category` with `sub_category` NULL.
- **Downgrade:** joins them back as `main || ' - ' || sub` and drops the column.

**API.**
- `CategoryBudget` (in `budget_models.py`) gains `sub_category: Optional[str] = None`, in both requests and responses.
- `main_category` must be the main category only. A request whose `main_category` still contains `" - "` is refused with 422, because no old app exists.
- A blank `sub_category` is treated as NULL.
- *Designer's call:* no new category validation. Budget create and update accept any category text today (only the AI path checks against the category list), and that stays as it is. Adding validation could stop people saving edits to existing budgets whose stored names aren't in today's list. It is not part of this project.

**Behaviour that must not change.**
- **Spent amounts** (`update_budget_spent_amounts`):
  - A main-only line counts every transaction in that main category.
  - A sub line counts only transactions with that main and that sub.
  - A transaction matching both a main line and its sub line adds to the budget total once.
- **Budget total excluding subs** (`_calculate_total_budget_excluding_subs`): a sub line's allocation counts toward the total only if its main has no line of its own.
- **AI-made budgets** (`_valid_budget_categories`, auto-create with AI, budget suggestions): the same categories are accepted and refused as today.
- **Category alerts** (exceeded and approaching): same thresholds, same text. Wherever a message names a sub line today as `"Main - Sub"`, it still reads exactly the same. The text is composed at display time.

**App.**
- The `CategoryBudget` model gains `subCategory`.
- The create and edit budget screens stop building and splitting `"Main - Sub"` strings and send the two fields.
- Every screen shows a line exactly as it does today.

## Part 2: devices

**Schema.** A new table `user_devices`:

| Column | Type / rule |
|---|---|
| `id` | text uuid4, primary key |
| `user_id` | FK `users.id` ON DELETE CASCADE, indexed |
| `token` | text, NOT NULL, **unique** (a token belongs to exactly one account) |
| `created_at` | timestamp |
| `last_seen_at` | timestamp, updated every time the device registers its token |
| `session_expires_at` | timestamp, NOT NULL: the expiry (`exp`) of the sign-in token the device last registered with |
| `sign_in_reminder_sent_at` | timestamp, NULL: when the "sign in again" reminder was sent for the current expiry |

- `users.fcm_token` and its unique index `uq_users_fcm_token` are dropped.
- **Upgrade:** creates one device row per user with a non-NULL `fcm_token`, with:
  - `last_seen_at` = migration time;
  - `session_expires_at` = migration time + 30 days. *Designer's call:* the real expiry isn't known. The app re-registers at its next start, which sets the true value.
- **Downgrade:** puts each user's most recently seen token back in `users.fcm_token`.

**Registering a device: `POST /api/auth/update-fcm-token`.** The path stays the same. The body is `{"fcm_token": ..., "previous_token": ...}`, where `previous_token` is optional.
- If the token is registered to another account, move it to the caller. The old account stops getting pushes on that device, as today's "detach" does.
- If the caller already has the token, update `last_seen_at`.
- If `previous_token` is given and belongs to the caller, that row takes the new token. One phone stays one row across Firebase token refreshes.
- Otherwise insert a new row.
- **Sign-in fields, every time:**
  - `session_expires_at` = the `exp` of the bearer token the request was made with;
  - `sign_in_reminder_sent_at` = NULL.
- This must be safe when two requests race (unique token, upsert).
- **App:**
  - The app remembers the token it last registered.
  - On `onTokenRefresh` it sends that token as `previous_token`.
  - At sign-in and session restore it also sends the remembered token if it differs from the current one. This covers a refresh that happened while the app was closed.

**Unregistering on logout: `DELETE /api/auth/fcm-token`.**
- The request now names the device's token. The builder chooses body or query parameter, and the app's pending-unregister retry (`pending_fcm_unregister.dart`) already stores the token.
- It removes that device row only if it belongs to the caller, and answers 200 either way, so a retry is harmless.
- A request without a token is refused with 422; no old app exists.
- **App:** when the device has no push token (for example, notification permission was refused), logout skips this call and stores no pending retry. Today only 401/403 clear a pending retry, so a 422 would be retried forever.

**Sending.** Every place that today reads one `fcm_token` sends to all of the person's devices instead:
- `notification_service.create_notification`: the push;
- `subscription_service`: the "plan expired" silent data message;
- `admin_routes`: the "plan updated" silent data message, and broadcasts (all target users' tokens, de-duplicated, chunked as today).

Only devices whose `session_expires_at` is in the future receive these. A device whose sign-in has expired gets nothing but the reminder below.

When Firebase reports a token as unregistered (`messaging.UnregisteredError`, or the multicast per-token equivalent), that device row is deleted. Other errors keep the row.

**Sign-in reminder.**
- A scheduled job, at least hourly, finds devices whose `session_expires_at` has passed and whose `sign_in_reminder_sent_at` is NULL.
- It sends each one push and stamps `sign_in_reminder_sent_at`:
  - in the person's language (English / Myanmar, from `users.language`);
  - English text: title "Sign in to Toe Pwar", body "You've been signed out. Sign in to keep getting your budget and goal alerts." The Myanmar text needs native review, like other new strings.
  - It carries no amounts, names or ids.
  - Push data `type = sign_in_reminder`.
- The reminder is a push only: no row in the in-app notification list.
- It is sent once per expiry. A new registration (a sign-in, then the app registering its token) resets the stamp.
- **App:** tapping the reminder opens the app. When signed out it lands on the sign-in screen as usual. When signed in again in the meantime, it just opens the app.
- After an explicit logout or a password reset the device row is gone, so no reminder is sent. Those people know they signed out.

**Password changes.**
- After a password **reset** (forgot password), every device row of that person is deleted. Every device is signed out by the password-version check, so none should keep getting their pushes.
- After a password **change** from inside the app, every device row except the one making the change is deleted. That device is still signed in, since it gets a fresh token.
- *Builder's choice:* send the device's token with the change-password request, or delete all rows and have the app re-register right after. Either is fine as long as the result is the same.
- This is new: today the token survives both. It is the designer's call, following the anti-goal "a signed-out device keeps receiving pushes".

**Admin.**
- The user list and user detail show a device count. User detail lists each device's `created_at` and `last_seen_at`; tokens are never shown.
- "Users with push enabled" counts people with at least one device (`users_db.HAS_DEVICE` becomes an EXISTS).

**App.**
- Logout's `DELETE` sends the device's token.
- Registration is unchanged: at sign-in, at session restore and on token refresh.

## Part 3: sign-in renewal

**Endpoint.** A new `POST /api/auth/renew-session` (authenticated):
- It answers with a fresh access token, valid for the full `ACCESS_TOKEN_EXPIRE_MINUTES` from now, with the same `uid` and current `pwv`.
- It accepts only a currently valid token. An expired token, or one revoked by a password change, gets 401 exactly as any other request, so renewal can never bring back a sign-in.

**App.**
- When does it renew? When the session is restored at app start, and when the app comes back to the foreground. It renews only if the stored token is more than 1 day old, so at most about once a day.
- The new token replaces the stored one.
- The app then re-registers its push token, so the device's `session_expires_at` moves forward too.
- Before checking a token's age, the app reads the token's `iat` / `exp` claims. Tokens are JWTs; the app does not verify the signature, it only reads the claims.
- If renewal fails:
  - **Offline or a server error:** the stored token is kept, and the app retries next time.
  - **401:** the usual session-expired handling (sign-in screen).
- Renewal must not race the existing logout and session-restore guards in `auth_provider.dart`. A late renewal answer must not store a token after a logout, which is the same rule the "superseded" checks follow today.

**Security note (designer's call).**
- A sliding sign-in means a stolen token stays usable for as long as it keeps being renewed.
- The existing defence still holds: changing or resetting the password bumps `pwv` and kills every token at once.
- Per-sign-in revocation is out of scope (see Non-goals).

## Left to the builder

- Whether the two parts share one migration or have one each.
- Body vs query parameter for the logout DELETE; how change-password keeps the current device (see above).
- Where the "send to all of a person's devices" helper lives, and whether single-person sends use multicast or a loop.
- Test names and placement. Each goal and anti-goal needs a test, including the migration of an existing token and existing `"Main - Sub"` budgets (spent and totals equal before and after).

## Designer's calls

- `sub_category` NULL, not an empty string, for main-only lines. This matches `transactions`, where the sub is required.
- Old-format requests are refused (422) rather than parsed.
- Device rows are deleted after a password reset or change.
- **Devices not seen for 60 days are deleted** by a daily job. Active devices refresh `last_seen_at` at every sign-in and session restore. This keeps the admin device count honest after a reinstall or cleared app data: the old row would otherwise linger, because Firebase only reports a dead token when something is sent to it.
- **One phone stays one row across token refreshes,** via `previous_token`, not via a new device-id column.
- **Renewal timing:** renew when the stored token is more than 1 day old, at app start and when the app returns to the foreground. Each renewal gives a full new 30 days.
- **The reminder:** sent at most once per expiry, as a push only, with the wording above. It is not sent after an explicit logout or a password reset.
