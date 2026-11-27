# Managing users from the admin panel (design)

Date: 2026-11-27. Area B of `docs/admin-audit-2026-11-25.md`, with area C's activity-log gaps.

## Intent

The owner wants to control as much of the app as possible from the admin panel. Areas 1-4 are done. Today an admin
can look at a person but can do little for them: set a plan by hand, reset AI usage, delete them. Support work (a
payment came in, someone can't sign in, someone abuses the app, a typo in an email) needs the admin to act on one
person safely, and every such action must leave a record.

The app is a consumer money app, so the owner chose the consumer pattern for account recovery: **no admin ever sets,
sees or knows a user's password**. Support can send the normal reset code, and after checking who they are talking
to, correct the sign-in email so the person can use the normal reset.

## Goals

1. **Grant an upgrade request in one click** (Upgrade Requests tab).
2. **Send a password reset code** to a person (the same email as "Forgot password").
3. **Correct a person's sign-in email** (super admin only), after the admin has checked who they are talking to.
4. **Edit a person's name and default currency.**
5. **Sign a person out everywhere.**
6. **Suspend and unsuspend a person**, with an internal reason.
7. **Send a message to one person** (an in-app notification and a push).
8. **A better users list:** sorting, more columns, a suspended filter, and one query per page instead of 5+ per user.
9. **Activity log:** admin sign-ins (success, failure, lockout) and feedback status changes and deletes are logged;
   the Logs tab pages back through all history and filters by admin, action and user.

Every action in 1-7 is logged with the admin, the person and what changed, and asks for a confirm that names the
person (name and email) before it runs.

## Who can do what

| Action | Moderator | Admin | Super admin |
|---|---|---|---|
| See users, details, upgrade requests (as now) | yes | yes | yes |
| Grant, send reset code, edit name/currency, sign out everywhere, suspend/unsuspend, message one person | no | yes | yes |
| Correct the sign-in email | no | no | yes |
| Logs tab (as now) | no | no | yes |

Moderators see the new buttons' information (for example "Suspended" and its reason) but not the buttons.

## How each part behaves

### 1. Grant an upgrade request
- Each pending request gets a "Grant" button: "Grant Plus for 1 month" / "Grant Pro for 1 year", from the request's
  plan and `billing` (no billing: 1 month).
- The end date: the length is added to the later of now and the end of the plan the person has now, when that plan
  is the same or higher and is a paid plan, not a trial. A trial or a lower plan starts from now.
- The confirm shows the person, the plan and the end date; the admin can change the end date there.
- Granting goes through the same path as setting a plan on the Users tab today: it closes the request (done; a person
  has at most one pending request) and
  tells the person their plan is active, and it is logged the same way.

### 2. Send a reset code
- Sends exactly the "Forgot password" email (6-digit code, 10 minutes, the person's language) and follows the same
  rules: the same rate limit per address, nothing sent while the account is locked out after wrong codes. The panel
  says plainly when nothing was sent and why (sent in the last minute, too many this hour, locked until a time). The
  limits stay as they are today (kept in memory); the self-service answer stays generic.
- Not offered for a suspended person.
- The admin never sees the code.

### 3. Correct the sign-in email (super admin only)
- The panel reminds the admin first: "Only do this after checking who you are talking to (recent entries, budget
  names, their plan)."
- The new address is normalised (trimmed, lower case) like sign-up, must be a valid address and not used by another
  account.
- On save: the person is signed out everywhere; an email goes to the **old** address saying the sign-in email was
  changed by support and to contact us if they didn't ask for it (it does not show the new address). The person then
  uses "Forgot password" with the new address; receiving that code is what proves the new address is theirs.
- An account that never verified its email (the common typo case: the verification email went to the wrong address)
  is handled by one rule for every reset: **completing a password reset with a code marks the account verified**,
  because receiving the code proves the address. So after a correction, the person resets and can sign in.
- Family membership is by account, so it is unaffected; a pending family invitation sent to the old address stays
  with the old address and expires as usual. Copies of the address in old records (feedback rows) stay as they were:
  they record who wrote it at the time.
- The log keeps the old and new address.

### 4. Edit name and default currency
- The same values the person can change in the app's own settings, with the same rules and the same effects (the
  builder reuses what the app's settings change does, rather than writing the columns directly).

### 5. Sign out everywhere
- Uses what a password reset already does: every token issued before is refused, and the person's devices are
  removed (no more pushes to them until they sign in again). The person is not told; the app shows its usual
  "signed out" behaviour.

### 6. Suspend and unsuspend
- Suspend needs a reason (internal, up to 500 characters). It is stored with when and by whom, and shown on the
  person's page and as a badge in the list.
- Suspending signs the person out everywhere (as in 5). After that:
  - signing in with the right password is refused with HTTP 423 (a wrong password still gets the usual 401, so the
    refusal never tells a stranger that an account exists or is suspended) and `{"detail": {"code": "account_suspended", "message": ...}}`, the message
    in the person's language: "This account is suspended. Please contact us." Not 403 (the installed app treats a
    refused sign-in with 403 as "email not verified" and sends the person to the wrong screen) and not 401 (that is
    "wrong password"). The installed app shows the message as the sign-in error, so no app release is needed. The
    fixed code lets a later app version show a screen of its own;
  - signing out already revokes every token, so old tokens get the usual 401; the suspension check in the token
    check is a second guard (423, same body), and renewing a session is refused;
  - "Forgot password" sends nothing (its answer stays the same generic one, as for an unknown address);
  - nothing is sent or run for them: no reminders, reports or other scheduled notices, no emails, no AI work, no
    broadcasts, and they can't be messaged. The exception is account-security email: the old-address notice of an
    email correction still goes out.
- What does not change: their data, their plan and its end date (a plan keeps running while suspended), and any
  family book they own or are in, which keeps working for the other members. Jobs that keep data correct keep
  running (repeating entries, the budget rollover), so their books are right if they are unsuspended; only jobs that
  notify, email or use AI skip them. The builder lists every such job in the plan (there is no single place today:
  device_jobs, notification_service, subscription_service, the report jobs, broadcast and the AI entry points).
- Unsuspend clears it; the person signs in again normally. Nothing that was skipped is sent afterwards.

### 7. Message one person
- From the person's page: a title, a message and a type, as in Broadcast; saved as an in-app notification and pushed
  to their devices. The panel shows how many devices it reached (0 is allowed: they see it next time they open the
  app).
- One-way: replies go through the existing contact links. Not offered for a suspended person.

### 8. Users list
- Sort: newest joined (default), oldest joined, last active, AI cost this month.
- Columns added: last active, language, AI cost this month, and a "Suspended" badge.
- Filter added: suspended.
- "Last active" keeps today's meaning (the latest entry in the personal book or chat activity).
- A page of users is loaded with a fixed number of queries, whatever the page size (today it is 5+ per user).

### 9. Activity log
- New log lines:
  - an admin sign-in that succeeds;
  - one that fails (the attempted email; never the password);
  - a lockout;
  - feedback status changes and feedback deletes.
  A failed sign-in with an address that is not an admin is logged with that address and no admin id (the log's admin
  id becomes optional). Attempts refused because the address is already locked out are not logged one by one; the
  lockout itself is one line. This keeps a password-guessing run from flooding the log.
- The Logs tab: newest first, pages back through all history, and filters by admin, by action and by the person's
  email.

## Calls I made (for the owner to check)

1. Suspension is shown through the sign-in error, with a fixed code (option A, owner chose "better long term"); a
   screen of its own can come in a later app release with no server change.
2. A suspended person's plan keeps running; suspending is not a refund or a pause.
3. Correcting an email doesn't move pending family invitations to the new address.
4. A reset code sent by an admin follows the same limits as one the person asks for, so an admin can't flood a
   person's inbox.
5. The grant adds to the current end date only for the same or a higher paid plan; a trial isn't extended.
6. Completing any password reset marks the account verified (the code proves the address). This is what makes the
   email correction work for someone who mistyped their email at sign-up.
7. Suspension stops notices, emails and AI, not data: repeating entries and budget rollovers keep running.
8. Security emails (the old-address notice) still reach a suspended person.
9. A wrong password on a suspended account gets the normal "wrong password" answer.

## Non-goals

- Temporary passwords, or an admin setting, seeing or learning a password.
- Signing in as a user ("impersonation").
- A dedicated "account suspended" screen in the app (later, through the code).
- CSV export, a person's notification history, two-factor sign-in for admins, changing an admin's role.
- Native pop-ups and the other panel-quality items of area C.

## Anti-goals (a failure even if it works)

- A suspended person still getting pushes, emails or reports, or still costing AI money.
- The installed app sending a suspended person to the "verify your email" screen.
- An email change that the old address is never told about.
- An action applied to the wrong person: every confirm names the person.
- An action that leaves no log line.

## Approaches

For suspension:

- **A. Through the existing sign-in (chosen).** Sign out everywhere, then refuse sign-in and requests with a fixed
  code and a translated message. Works on the installed app.
- **B. A dedicated screen.** Nicer, but needs an app release, and the installed app still needs A.
- Not considered further: hiding or deleting data, which delete already covers.

For recovery: **the consumer pattern (chosen)**, reset code plus a checked email correction. A temporary password
(the workplace-admin pattern) was rejected: anyone messaging support while pretending to be the user could take the
account.

## Left to the builder

Column names and the migration for the suspension record, route shapes, how the list query is built, where the new
texts live (they follow the existing translate/Texts pattern, so the two new texts and the new email are editable in
the Texts tab), and the panel's layout.

## Testing

- Backend e2e for every action and its role rules, each log line, every suspension effect (sign-in 423 with the
  code, an old token refused, renew refused, forgot-password silent, the jobs and broadcasts skipping them, the
  family book still working for others), the grant's end-date rules, the email correction (uniqueness, sign-out, the
  old-address email), the reset-code limits, and the list's sorting and query count.
- App: a check that the installed sign-in code shows the 423 message (no app change expected).
- Admin panel: lint and build; a browser check of each action with throwaway accounts.

## Deploy

One migration: the suspension record, the log's admin id made optional, and any indexes the Logs filters need.
Server only; no app release.
