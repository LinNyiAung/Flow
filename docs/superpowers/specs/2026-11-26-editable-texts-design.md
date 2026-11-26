# Editable texts: server messages and emails from the admin panel (design)

Date: 2026-11-26. Area 2 of `docs/admin-audit-2026-11-25.md`.

## Intent

The owner wants to change, from the admin panel and without a redeploy, the words users read that come from the
server: notifications, error and limit messages, plan and trial texts, App control's standard messages, feature
names, contact labels, and the two emails. Each English text sits beside its Myanmar one, both editable.

## Goals

- Every server text in `notification_service.NOTIFICATION_TRANSLATIONS` (132 keys today, each `en` and `my`) and the
  two emails (sign-up verification, password-reset code) can be edited per language, and reset to the default.
- The wording in code stays the default. An edit is stored as an override of one text in one language; reset deletes
  the override. Texts added to the code later appear automatically with their default wording.
- An edit can't break a message: the placeholders it must keep (`{plan}`, `{date}`, …) are checked on save.
- An edit takes effect on the server within a minute (at once on the worker that saved it). Every change is in the
  admin activity log, naming the text and language.
- Emails: the reset code goes in the person's language; the verification email shows English first and Myanmar
  below it, in one email.

## Non-goals

- The app's own screen texts (about 1,200 per language, built into the app). Decided with the owner: not now; their
  Myanmar review will be a separate spreadsheet job (export, review, apply in code, ship in a release).
- Adding languages beyond `en` and `my`.
- Editing the email layout (colours, button, logo): only the words.
- Rewording notifications already sent: they are stored with their text at the time (`notifications.title` /
  `message`), so an edit applies to new ones.
- Editing AI prompts (area 5 of the audit).
- A Myanmar review checklist ("reviewed" ticks) in the dashboard. Proposed, then dropped by the owner: the review
  may be tracked in another form (e.g. a spreadsheet export), not in the admin panel.

## Anti-goals (a failure even if it works)

- **A typo in the panel breaking a message for users**: a missing or unknown placeholder, or an unbalanced brace,
  must be refused on save, never discovered when a notification fails to render.
- **The texts becoming unreadable if the overrides can't load**: until a load succeeds, or if a stored override is
  invalid, the code default is used.
- **Two people editing at once losing each other's work**: each save touches only the text and language it changed.

## Approaches

1. **Overrides table on top of the code defaults (chosen by the owner).** One row per edited text and language; the
   server uses the override if present, else the code default. Per-text saves, an exact activity log, new code texts
   appear automatically.
2. **One settings document (like App control).** Simpler, but a save replaces all edits, so concurrent edits are
   lost and the log can only say "texts changed".
3. **All texts in the database as the source.** Every future text change in code would need a migration, and the
   defaults could drift from the code.

## Decisions made with the owner

- Scope A: server texts and the two emails; app screen texts are out (see Non-goals).
- Option 1 storage: overrides on top of the code defaults.
- Emails: the password-reset code in the person's language; the verification email in both languages (English
  first, Myanmar below), since the server doesn't know the language at sign-up. A later sign-up language picker can
  switch it to one language.
- No "Myanmar reviewed" tick in the dashboard (the owner, 2026-11-26).

## Calls made after the builder check (mine, for the owner to check)

1. **An override remembers the default it replaced.** When a release changes that default, the panel marks the text
   "default changed since your edit" so the owner can compare and keep or reset.
2. **Emails are several short texts slotted into a fixed layout**, not one free body:
   - reset email: subject, heading, intro (says the code expires in 10 minutes), footer (ignore if you didn't
     ask); the code itself sits in its fixed box.
   - verification email: subject, heading, intro (says the link expires in 48 hours), button label, footer; the
     link sits behind the fixed button (and is printed under it for clients that hide buttons).
   - These texts have no placeholders (the code and link are placed by the layout), so the placeholder rule —
     "the same set as the default" — means "none". A plain-text version is built from the same texts.
   - Two-language verification email: the subject is "English / Myanmar"; one layout with the English texts then
     the Myanmar texts; one button whose label shows both languages.
3. **Two people saving the same text at once: the second save is refused, not lost.** Each save and reset sends the
   version it was editing; if the text changed in the meantime, the panel shows "changed by someone else — reload"
   and keeps the person's typing so they can redo it.

## Texts and placeholders

- The catalogue is the keys of `NOTIFICATION_TRANSLATIONS["en"]` plus the email texts. The email texts become keys
  in the same table, so they follow the same rules (for example `email_verify_subject`, `email_verify_body`,
  `email_reset_subject`, `email_reset_body`; exact names are the builder's call), each with `en` and `my` defaults.
  The Myanmar email defaults are written by the builder (they need the owner's native check, outside the panel).
- A text's placeholders are the `{name}` fields in its English default. An edit (either language) must contain
  exactly the same set: none missing, none new. Literal braces are not allowed in edits (the defaults don't use
  them). Length limit per text: 1,000 characters (emails' bodies up to 3,000).
- The emails' code and link are placed by the fixed layout, not by placeholders (see the calls above); the expiry
  times stay as they are today (48 hours, 10 minutes), written as text the owner can edit.
- Each text has an area for grouping in the panel, derived from its key (`plan_…`, `family_…`, `budget_…`,
  `goal_…`, `chat_…`/`insight_…`/`custom_…` (Ko Toe Pwar), `app_…`/`feature_…`/`maintenance_…`/`announcement_…`
  (App control), `contact_…`, `email_…`, others), and an optional one-line "where it's used" note kept beside the
  key in code (builder's call how).

## How the server uses them

- `notification_service.translate(key, language, **kwargs)` is the single place texts are looked up today
  (`notification_service.py:333`). It takes the override for (key, language) if there is one, else the code
  default, then formats as now.
- Overrides are cached in memory, loaded at startup, refreshed every minute and updated at once on save (the same
  pattern as `plans/store.py` and `app_control.py`). A stored override that fails validation (e.g. edited by hand)
  is ignored and logged.
- Emails are rendered through the same lookup: the reset email in `user_language(user)`; the verification email with
  both languages. The HTML layout of the reset email stays; the verification email gets the same layout (today it
  is plain text only), with a plain-text alternative.

## Admin panel: the Texts tab

- A new "Texts" tab. Areas as sections or a filter; a search over key and text (both languages); a "changed" filter.
- Each text: key, area, the "where it's used" note, the placeholders it must keep, the English default and the
  Myanmar default, and the current English and Myanmar texts (editable), "Save" and "Reset" per language (reset
  asks for confirmation), and the "default changed since your edit" mark when it applies.
- A save that fails validation shows the reason inline (which placeholder is missing or new).
- Moderators see everything read-only; admins and super admins change. Every save and reset is logged with
  `log_admin_action` (key, language, and for a save the old and new text, cut to fit the log).

## Storage

- One new table (a migration): per (key, language) the override text, the default it replaced, a version for the
  concurrent-save check, who changed it and when. Reset deletes the row. Builder's call on the exact layout.
- Deleting a key from the code leaves its stored rows unused; they are ignored (and listed nowhere).

## Testing

- Backend e2e: an override changes what `translate` returns (and a notification created after it), reset restores
  the default; placeholder validation (missing, new, unbalanced braces, too long); an invalid stored row is ignored;
  the cache reload; moderator read-only, admin write, every change logged; the reset email in the person's language
  and the verification email with both languages (rendered, not sent: the sending function is replaced in tests);
  new code keys appear with their defaults; tests restore everything they change.
- Admin panel: lint and build; a browser check of editing, reset, the "changed" filter and the inline error.

## Left to the builder

The table layout, the key names of the email texts, how the "where it's used" notes are stored, the tab's component
split and look, the Myanmar email defaults' wording, within the decisions above.

## Deploy

One migration (the overrides table). Server only: no app release needed. Existing texts are unchanged until edited.
