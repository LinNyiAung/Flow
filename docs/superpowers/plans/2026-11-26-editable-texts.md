# Editable Texts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admins edit every server text (notifications, errors, limits, App control messages, feature names, contact
labels) and the two emails, in English and Myanmar, from a new admin "Texts" tab, without a redeploy.

**Architecture:** The wording in `notification_service.NOTIFICATION_TRANSLATIONS` stays the default; the email texts
join it as `email_*` keys. A new table holds overrides, one row per (key, language). A small module caches them
(load at startup, refresh every 60 s, update at once on save) and `translate()` checks it first. The emails are built
from these texts inside a fixed layout.

**Tech Stack:** FastAPI + SQLAlchemy Core (asyncpg) + Alembic on Postgres 16; React + Vite admin panel.

**Spec:** `docs/superpowers/specs/2026-11-26-editable-texts-design.md` (its "Calls made after the builder check" are
binding; there is NO "Myanmar reviewed" tick anywhere).

## Global Constraints

- Languages exactly `en` and `my`. A text's placeholders are the `{name}` fields of its English default; an edit in
  either language must have exactly the same set (none missing, none new), no positional `{}`, no format spec or
  conversion, balanced braces, not empty after trimming, at most 1,000 characters.
- Fallback order in `translate`: override for (key, lang) → code default for lang → code default for `en` → the key.
- A stored override that fails validation (hand-edited, or its key's placeholders changed in a release) is ignored
  and logged; the default is used.
- Concurrent saves: every save and reset sends the version it edited (`null` when there was no override); a mismatch
  is HTTP 409 `{"detail": {"code": "text_conflict", "message": "This text was changed by someone else. Reload to see it."}}`.
- An override stores the default it replaced; `default_changed` is true when that differs from the current default.
- Admin roles: moderators read (`require_moderator_or_above`), admins and super admins change
  (`require_admin_or_super`); every save and reset calls `log_admin_action` with key, language and old → new text
  (cut so the details stay under 2,000 characters).
- Email layout fixed; only these texts are editable (no placeholders in them): `email_verify_subject`,
  `email_verify_heading`, `email_verify_intro` (mentions 48 hours), `email_verify_button`, `email_verify_footer`,
  `email_reset_subject`, `email_reset_heading`, `email_reset_intro` (mentions 10 minutes), `email_reset_footer`.
  The reset email is in the person's language; the verification email is both languages (subject "EN / MY", English
  texts then Myanmar texts, one button labelled "EN / MY", the link also printed under the button).
- UTF-8 sources: Edit/Write tools or Python `io.open(..., encoding="utf-8", newline="")`; never PowerShell
  `Get-Content`/`Set-Content` on source files (Myanmar text).
- Branch `editable-texts`. Before each commit: `git checkout -- frontend/linux frontend/macos frontend/windows`.
  Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, written to a file and passed with `git commit -F`.
- Never read or print `.env` or other secret files. Tests use only the local stub server and test DB.

## Commands

- `$PY` = `C:\Users\LINNYI~1\AppData\Local\Temp\claude\C--projects-Flow\88f449c7-2e35-4a07-890d-5a91aa9c3948\scratchpad\venv_final\Scripts\python.exe`
- Postgres (127.0.0.1:54329) if down — start it detached, never with a piped `pg_ctl`:
  `$S='C:\Users\LINNYI~1\AppData\Local\Temp\claude\C--projects-Flow\88f449c7-2e35-4a07-890d-5a91aa9c3948\scratchpad'; Start-Process -FilePath "$S\pg_dl\srv\pgsql\bin\pg_ctl.exe" -ArgumentList "-D `"$S\pg_data`" -l `"$S\pg\postgres.log`" -o `"-p 54329 -h 127.0.0.1`" start" -WindowStyle Hidden`, then poll `& "$S\pg_dl\srv\pgsql\bin\pg_isready.exe" -h 127.0.0.1 -p 54329` until exit 0 (can take minutes).
- After a new migration: `Set-Location C:\projects\Flow\backend; $env:DATABASE_URL='postgresql://flow@127.0.0.1:54329/flow_e2e'; & $PY -m alembic upgrade head` (the stub restart below does NOT migrate).
- Restart the stub server on current code (resets data): `& "$S\pg\run_suite.ps1" -NoSuite`.
- One backend test file: `$env:E2E_FAKE_AI='1'; $env:PYTHONIOENCODING='utf-8'; Set-Location C:\projects\Flow\e2e; & $PY -u test_texts.py <sections>` (exit 0, no `[BUG]` = pass).
- Admin: `Set-Location C:\projects\Flow\admin; npm run lint; npm run build` (baseline: 1 pre-existing lint error in App.jsx).

## Review Focus

1. **A test leaves an override behind** in the shared DB, changing messages that other suites assert. Every section
   deletes its overrides in `finally`, and a final `clean` section checks the table is as it was at the start.
2. **An override with a placeholder the code no longer passes** (a release renamed `{date}`): `translate` must not
   raise `KeyError` into a notification job — such a stored row is ignored at load (Task 1) and the default used.
3. **`translate` called before the cache loads or with the DB down**: defaults, never an error (Task 1).
4. **Myanmar edits with Myanmar digits or braces-like characters** (`{` typed by mistake): validation names the
   problem; the server never stores an unparseable template (Task 1).
5. **The verification email in a client that hides buttons**: the link is also printed as text (Task 3).

---

### Task 1: Overrides store, validation and `translate`

**Files:**
- Create: `backend/text_overrides.py`
- Modify: `backend/sql/tables.py` (table `text_overrides`), create `backend/sql/text_overrides.py` (queries)
- Create: `backend/alembic/versions/20261126_c9e3a7d1f4b2_text_overrides.py` (`revision = 'c9e3a7d1f4b2'`, `down_revision = 'b7d2e9c4a1f3'`)
- Modify: `backend/notification_service.py` (`translate`, about line 331; add the nine `email_*` keys in `en` and `my`, wording taken from today's `email_service.py` texts; Myanmar written by you)
- Modify: `backend/main.py` startup/shutdown (load + refresh loop, as `app_control` at `main.py` startup)
- Create: `e2e/test_texts.py` (sections `store`), register in `e2e/run_backend_suite.py` `SUITES` and `PRINT_ONLY`

**Interfaces:**
- Table `text_overrides`: `key` Text, `lang` Text, PK (key, lang); `text` Text NOT NULL; `replaced_default` Text NOT NULL; `version` Integer NOT NULL; `updated_by` Text; `updated_at` TS default now.
- `backend/sql/text_overrides.py`: `read_all() -> List[dict]`, `upsert(key, lang, text, replaced_default, expected_version: Optional[int], admin_email) -> Optional[dict]` (returns None on a version mismatch; insert only when `expected_version is None` and no row exists; version starts at 1 and increments), `delete(key, lang, expected_version: int) -> Optional[bool]` (None on mismatch, False if no row).
- `backend/text_overrides.py`:
  - `LANGS = ("en", "my")`, `MAX_TEXT = 1000`
  - `def get(key: str, lang: str) -> Optional[str]` — the cached override or None (no DB, no import of notification_service at module import)
  - `def defaults() -> Dict[str, Dict[str, str]]` — `{key: {"en", "my"}}` from `NOTIFICATION_TRANSLATIONS` (imported inside the function)
  - `def placeholders(key: str) -> Set[str]` — via `string.Formatter().parse` on the English default
  - `def validate(key: str, lang: str, text: str) -> str` — the trimmed text, or `ValueError` with a readable message naming the missing/new placeholder; `KeyError`-style unknown key/lang -> `ValueError("Unknown text …")`
  - `def area(key: str) -> str` — by prefix: plans (`plan_`, `trial_`, `subscription_`, `upgrade_`, `payment_`), family (`family_`), budgets (`budget_`, `large_`, `unusual_`), goals (`goal_`), Ko Toe Pwar (`chat_`, `insight_`, `custom_`, `weekly_`, `monthly_`, `entry_`), App control (`app_`, `feature_`, `maintenance_`, `announcement_`), contact (`contact_`), emails (`email_`), else "other"
  - `class TextConflict(Exception)`
  - `async def load() -> None` (drops invalid rows with a warning; `_write_gen` stale-load guard as in `app_control.py`), `def start_refresh_loop(interval: float = 60.0) -> asyncio.Task`
  - `async def save(key, lang, text, expected_version: Optional[int], admin_email: str) -> dict` (validates; stores `replaced_default` = current default; raises `TextConflict`), `async def reset(key, lang, expected_version: int, admin_email: str) -> bool`
  - `def rows() -> Dict[Tuple[str, str], dict]` — cached rows for the admin listing
- `notification_service.translate(key, language, **kwargs)`: template = `text_overrides.get(key, lang)` or the default per the fallback order; format as now.

- [ ] **Step 1: Write the failing tests** (`store`, in-process with `_backend_async` as in `e2e/test_app_control.py`):

```python
import text_overrides as to
from notification_service import translate, NOTIFICATION_TRANSLATIONS as T
check(set(T["en"]) == set(T["my"]) and all(k in T["en"] for k in (
    "email_verify_subject", "email_verify_heading", "email_verify_intro", "email_verify_button", "email_verify_footer",
    "email_reset_subject", "email_reset_heading", "email_reset_intro", "email_reset_footer")), "store: email keys in en and my")
check(to.placeholders("plan_limit_reached_msg") == {"feature", "date"}, "store: placeholders from the English default")
for bad in ("{feature} only", "{feature} {date} {plan}", "{feature} {date} {", "{} {feature} {date}",
            "{feature:>5} {date}", "   ", "x" * 1001):
    try: to.validate("plan_limit_reached_msg", "my", bad); check(False, f"store: rejects {bad!r}")
    except ValueError: check(True, f"store: rejects {bad[:20]!r}")
check(to.validate("plan_limit_reached_msg", "en", "  {date}: no more {feature}  ") == "{date}: no more {feature}",
      "store: accepts reordered placeholders, trimmed")
# save en override -> translate returns it at once; my unchanged; reset -> default again
# save with a stale version -> TextConflict; reset with a stale version -> TextConflict
# replaced_default stored; after changing the stored replaced_default by SQL, rows() reports default_changed
# a hand-inserted row with "{nope}" for plan_limit_reached_msg is ignored by load() and translate() uses the default
# translate() before load / with an empty cache returns the default; an unknown key returns the key
# finally: delete every row this section created
```

- [ ] **Step 2: Run to see them fail** — migrate (Commands), restart the stub, `& $PY -u test_texts.py store`; expected `ModuleNotFoundError: text_overrides`.
- [ ] **Step 3: Implement** the table, migration (shape of `alembic/versions/20261121_f3d8a6c1e094_local_job_done.py`), queries, module, `translate` change, email keys, and startup wiring.
- [ ] **Step 4: Run to see them pass**; also `& $PY -u test_app_control.py` and `& $PY -u test_family.py` (they assert translated texts); all exit 0.
- [ ] **Step 5: Commit** — `feat(backend): text overrides on top of the code defaults`.

### Task 2: Admin API for texts

**Files:**
- Create: `backend/text_admin_routes.py` (router prefix `/api/admin/texts`); modify `backend/main.py` (include it next to the App control admin router)
- Test: `e2e/test_texts.py` section `admin_api`

**Interfaces:**
- `GET /api/admin/texts` (moderator+) -> `{"texts": [{"key", "area", "placeholders": [..sorted], "default": {"en", "my"}, "override": {"en": null | {"text", "version", "default_changed", "updated_by", "updated_at"}, "my": …}}]}`, sorted by area then key.
- `PUT /api/admin/texts/{key}/{lang}` (admin+), body `{"text": str, "version": int | null}` (`extra="forbid"`) -> the override object; 404 unknown key or lang; 422 `{"detail": "<readable>"}` on validation; 409 `text_conflict`. Log `text_update`.
- `DELETE /api/admin/texts/{key}/{lang}?version=N` (admin+) -> `{"reset": true}`; 404 when there is no override; 409 on a stale version. Log `text_reset`.

- [ ] **Step 1: Write the failing tests** (HTTP against the stub; admins made as in `e2e/test_devices.py:211-219`):
  moderator GET 200 and PUT 403; GET lists every key of `NOTIFICATION_TRANSLATIONS["en"]` once with its area and
  placeholders; admin PUT a valid `en` text for `plan_paid_required_msg` -> 200 version 1, and a Free user's
  `POST /api/insights/regenerate` now returns that text in its 403 message; PUT with the old version `null` again ->
  409 `text_conflict`; PUT missing a placeholder (pick a key that has one) -> 422 naming it; unknown key -> 404;
  DELETE with version 1 -> 200 and the Free user's message is the default again; DELETE again -> 404; the admin log
  has `text_update` and `text_reset` naming the key and language; `finally`: delete any override left.
- [ ] **Step 2: Run to see them fail** (404s), **Step 3: implement**, **Step 4: run to pass** (restart the stub first).
- [ ] **Step 5: Commit** — `feat(backend): admin API for editing texts`.

### Task 3: Emails from the editable texts

**Files:**
- Modify: `backend/email_service.py`, `backend/auth_routes.py` (the `send_otp_email` call at about line 337 passes the person's language via `plans.access.user_language(user)`)
- Test: `e2e/test_texts.py` section `emails`

**Interfaces:**
- `def build_verification_email(receiver_email: str, verification_token: str) -> EmailMessage` — both languages per Global Constraints; HTML (the reset email's existing style: card, heading, the button linking to the verification link) plus a plain-text alternative containing the link.
- `def build_reset_email(receiver_email: str, otp: str, lang: str) -> EmailMessage` — the existing reset layout with the code box, texts in `lang`, plain-text alternative containing the code.
- `send_verification_email(receiver_email, verification_token)` and `send_otp_email(receiver_email, otp, lang="en")` build with these and send as today (sender and error handling unchanged).

- [ ] **Step 1: Write the failing tests** (in-process; build only, never send): the reset email for `my` has the Myanmar subject and the code in both HTML and plain text; for `en` the English ones; the verification email subject contains both languages' subjects joined by " / ", the HTML has one link to `/api/auth/verify-email?…token=…` styled as a button, and the plain text contains the link; an `en` override of `email_reset_heading` (saved in-process with `text_overrides.save`) appears in the next reset email; Myanmar texts survive in the HTML (UTF-8); `finally`: reset the override.
- [ ] **Step 2: Run to fail**, **Step 3: implement**, **Step 4: run to pass**; also `& $PY -u test_api.py` (registration and password reset still work).
- [ ] **Step 5: Commit** — `feat(backend): the two emails use the editable texts, reset code in the person's language`.

### Task 4: Admin panel "Texts" tab

**Files:**
- Create: `admin/src/Texts.jsx` (split rows into `admin/src/TextRow.jsx` if the file passes ~500 lines)
- Modify: `admin/src/App.jsx` (sidebar entry `{ id: 'texts', icon: <a lucide icon such as Languages>, label: 'Texts' }` after App control; render `<Texts token={token} adminRole={admin.role} ConfirmDialog={ConfirmDialog} />` the way `AppControl` is rendered)

**Interfaces:**
- Consumes: Task 2's three endpoints through `apiRequest` (`admin/src/api.js`).

- [ ] **Step 1: Build the tab**: areas as sections with counts; a search box over key and both texts; a "Changed" filter. Each row: key, area, "Must keep: {date}, {feature}" (or "No placeholders"), and per language a textarea (with a character counter to 1,000) showing the override or the default, the default shown beneath when overridden, "Default changed since your edit" when `default_changed`, Save (enabled only when edited) and Reset (only when overridden; asks with `ConfirmDialog`). Errors (422 text, 409 conflict) show inline on that row and keep the typed text; a 409 offers "Reload this text". Moderators: everything read-only, no Save/Reset.
- [ ] **Step 2: Lint and build** — baseline only.
- [ ] **Step 3: Browser check** on the local stub (throwaway admin and moderator made as in `e2e/test_devices.py:211-219`; `$env:VITE_API_BASE_URL='http://127.0.0.1:8765'; npm run dev`): edit and save a Myanmar text, see "Changed"; a missing placeholder shows the inline error; reset with the dialog; the moderator view is read-only. Remove the overrides and the throwaway admins afterwards. If you have no browser tools, say so in the report.
- [ ] **Step 4: Commit** — `feat(admin): Texts tab`.

### Task 5: Whole-branch verification

- [ ] **Step 1:** Full backend suite in the background (`run_suite.ps1`); expected `== problems (0) ==` (rerun a known flake on its own and report it). If a migration test fails with "tables can have at most 1600 columns", recreate `flow_e2e` (drop/create, `alembic upgrade head`) and rerun — an environment issue.
- [ ] **Step 2:** `npm run lint; npm run build` in `admin`.
- [ ] **Step 3:** Update the spec's "Deploy" section if anything changed (migration `c9e3a7d1f4b2`, server only).
