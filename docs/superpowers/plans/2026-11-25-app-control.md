# App Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An admin "App control" tab that pauses features for everyone, opens/closes sign-ups and the free trial,
pauses new families, puts the app into maintenance, and shows announcement banners; enforced by the server and shown
by the app.

**Architecture:** The switches and maintenance live in one validated JSON document in the existing `app_settings`
key/value table (key `app_control`), cached in memory like `plans/store.py` (load at startup, refresh every 60 s,
updated at once on save). Announcements get their own table. Routes call `app_control.require_on(key, lang)`; an ASGI
gate refuses app requests during maintenance. `GET /api/app/config` tells the app what is paused, whether it is in
maintenance, and which announcement to show.

**Tech Stack:** FastAPI + SQLAlchemy Core (asyncpg) + Alembic on Postgres 16; Flutter with Provider; React + Vite admin.

**Spec:** `docs/superpowers/specs/2026-11-25-app-control-design.md` (read it first; its "Calls made after the builder
check" section is binding).

## Global Constraints

- Switch keys, exactly: `chat`, `voice`, `receipts`, `budget_ideas`, `reports`, `custom_reports`, `translation`,
  `signups`, `free_trial`, `family_new`.
- English switch names (for the standard message): chat "Chat with Ko Toe Pwar", voice "Voice entry", receipts
  "Receipt photos", budget_ideas "Budget ideas", reports "Weekly and monthly reports", custom_reports "Custom reports",
  translation "Myanmar translation", signups "Sign-ups", free_trial "The free trial", family_new "New families and
  invites". Myanmar names are written by the implementer and join the native review.
- Standard paused message (English): "{feature} is paused for now. Please try again later." Standard maintenance
  message (English): "Toe Pwar is under maintenance. Please try again soon." Myanmar versions by the implementer.
- A paused request: HTTP 403, `{"detail": {"code": "feature_paused", "feature": "<key>", "message": "<text>"}}`, raised
  before any plan allowance is reserved. Maintenance: HTTP 503,
  `{"detail": {"code": "maintenance", "message": "<en>\n\n<my>", "back_by": "<ISO or null>"}}`.
- Owner messages: at most 300 characters each. Testers: at most 50 emails, stored trimmed and lowercased.
  Announcement texts: 1-500 characters, both languages required; link `http(s)` only, at most 500 characters; link
  labels at most 40 characters.
- The admin API (`/api/admin/...`) is never blocked. Moderators read; admins and super admins change
  (`require_moderator_or_above` / `require_admin_or_super`). Every change calls `log_admin_action`.
- Reading what exists always works while paused (saved reports, chat history, family books, stored translations).
- UTF-8 sources: edit with the Edit tool or Python `io.open(..., encoding="utf-8", newline="")`; never PowerShell
  `Get-Content`/`Set-Content` on source files.
- Work on branch `app-control`. Before each commit: `git checkout -- frontend/linux frontend/macos frontend/windows`.
  Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Flutter analyzer baseline: 166 infos, no warnings or errors; it must not grow.

## Commands

- `$PY` = `C:\Users\LINNYI~1\AppData\Local\Temp\claude\C--projects-Flow\88f449c7-2e35-4a07-890d-5a91aa9c3948\scratchpad\venv_final\Scripts\python.exe`
- Restart the stub server on the current code with a fresh test DB (Postgres must be up on 127.0.0.1:54329):
  `& 'C:\Users\LINNYI~1\AppData\Local\Temp\claude\C--projects-Flow\88f449c7-2e35-4a07-890d-5a91aa9c3948\scratchpad\pg\run_suite.ps1' -NoSuite`
- Run one backend test file: `$env:E2E_FAKE_AI='1'; $env:PYTHONIOENCODING='utf-8'; Set-Location C:\projects\Flow\e2e; & $PY -u test_app_control.py <sections>`
  (exit 0 and no `[BUG]` lines = pass).
- Full backend suite: the same `run_suite.ps1` without `-NoSuite` (about an hour; run it in the background).
- Flutter: `Set-Location C:\projects\Flow\frontend; flutter test <file>`; `flutter analyze`.
- Admin: `Set-Location C:\projects\Flow\admin; npm run lint; npm run build`.

## Review Focus

1. **A test run leaves maintenance or a pause on** in the shared e2e database: every later suite then fails. Each
   section of `test_app_control.py` restores the original document in `finally`, and the last section checks the
   stored document equals the one at the start (Task 1, Task 4).
2. **The web app can't read a 503/403 from the gate** if the gate sits outside CORS: the gate is added before
   `CORSMiddleware` so CORS wraps it; a test sends an `Origin` header and expects `access-control-allow-origin` on the
   503, and an `OPTIONS` preflight still succeeds during maintenance (Task 4).
3. **A corrupted or older stored document** (bad JSON, unknown keys, missing keys): load keeps "nothing paused" and
   logs; unknown switch keys are dropped; missing ones default to not paused (Task 1).
4. **Tester emails with different case or spaces** (" Tester@Example.com"): matched case-insensitively, trimmed (Task 1
   validation, Task 4 gate test).
5. **Announcement time windows and zones:** a future start isn't shown, a past end isn't shown, naive datetimes are
   rejected, an end before the start is rejected; a signed-out config call gets no announcement (Task 3).

---

### Task 1: Settings store, switch checks and the admin settings API

**Files:**
- Create: `backend/app_control.py`
- Create: `backend/sql/app_control.py` (this task: settings read/write only)
- Create: `backend/app_control_routes.py` (this task: `admin_router`, prefix `/api/admin/app-control`, with `GET ""` and `PUT ""`)
- Modify: `backend/notification_service.py` (en + my keys)
- Modify: `backend/main.py` startup/shutdown (`main.py:108-146`); include `admin_router` next to `plans_admin_router` (`main.py:100-105`)
- Create: `e2e/test_app_control.py` (sections `store`, `admin_api`), register it in `e2e/run_backend_suite.py` `SUITES` and `PRINT_ONLY`

**Interfaces:**
- Produces (`backend/app_control.py`):
  - `SWITCHES: tuple[str, ...]` (the ten keys, in the Global Constraints order)
  - `SETTINGS_KEY = "app_control"`, `MAX_MESSAGE = 300`, `MAX_TESTERS = 50`
  - `class FeaturePaused(HTTPException)`: `__init__(self, key: str, lang: str)`; status 403; `detail` = `paused_detail(key, lang)` without the two extra keys below.
  - `def paused_detail(key: str, lang: str) -> dict`: `{"code": "feature_paused", "feature": key, "resets_at": None, "upgrade_available": False, "message": paused_message(key, lang)}` (the shape `translation_unavailable` already uses)
  - `def is_paused(key: str) -> bool`; `def require_on(key: str, lang: str = "en") -> None` (raises `FeaturePaused`)
  - `def paused_message(key: str, lang: str) -> str`: the owner's text for `lang` if not empty, else `translate("feature_paused_msg", lang, feature=translate(f"app_switch_{key}", lang))`; `lang` other than "my" means "en"
  - `def both_languages(key: str) -> str`: `paused_message(key, "en") + "\n\n" + paused_message(key, "my")` (signed-out refusals)
  - `def maintenance_on() -> bool`, `def maintenance_message(lang: str) -> str` (owner's text or `translate("maintenance_msg", lang)`), `def maintenance_back_by() -> Optional[datetime]`, `def is_tester(email: Optional[str]) -> bool`
  - `def validate(doc: Mapping) -> dict` (raises `ValueError` with one readable message), `def snapshot() -> dict`
  - `async def load() -> None`, `async def save(doc: Mapping, admin_id: str) -> dict`, `def start_refresh_loop(interval: float = 60.0) -> asyncio.Task`
- Produces (`backend/sql/app_control.py`): `async def read_settings() -> Optional[str]`, `async def write_settings(value: str) -> None` (upsert into `app_settings`, like `sql/plans.py:66-69`)
- Document shape (stored as JSON text under `SETTINGS_KEY`, returned by `snapshot()` and `validate()`):
  `{"switches": {<key>: {"paused": bool, "message_en": str, "message_my": str}}, "maintenance": {"on": bool, "message_en": str, "message_my": str, "back_by": <ISO 8601 with offset> | None, "testers": [str]}}`
  After validation every switch key is present; unknown keys are an error in `validate` but are dropped (logged) in `load`.
- Admin endpoints (JSON):
  - `GET /api/admin/app-control` (moderator+) -> `{"settings": snapshot(), "switches": [{"key", "name_en"}...]}`
  - `PUT /api/admin/app-control` (admin+) body = the document -> the saved document; 422 `{"detail": "<readable>"}` on `ValueError`; log action `app_control_update`, details naming what changed (e.g. `"paused: voice; maintenance: on"`), at most 2000 characters. Request model with `extra="forbid"` as in `plans_admin_routes.py:31-75`.

- [ ] **Step 1: Write the failing tests** in `e2e/test_app_control.py`, section `store` (in-process, `_backend_async` as in `e2e/test_ai_correctness.py:49-57`; helper `check(ok, name, detail)` the same way):

```python
import app_control as ac
check(ac.SWITCHES == ("chat", "voice", "receipts", "budget_ideas", "reports", "custom_reports", "translation",
                      "signups", "free_trial", "family_new"), "store: the ten switches")
doc = ac.validate({"switches": {"voice": {"paused": True, "message_en": "Back at 5", "message_my": ""}},
                   "maintenance": {"on": False, "message_en": "", "message_my": "", "back_by": None,
                                   "testers": [" Tester@Example.com "]}})
check(set(doc["switches"]) == set(ac.SWITCHES) and doc["switches"]["chat"]["paused"] is False,
      "store: missing switches default to not paused")
check(doc["maintenance"]["testers"] == ["tester@example.com"], "store: testers trimmed and lowercased")
for bad in ({"switches": {"nope": {"paused": True}}}, {"switches": {"voice": {"paused": "yes"}}},
            {"switches": {"voice": {"paused": True, "message_en": "x" * 301}}},
            {"maintenance": {"on": True, "testers": ["not-an-email"]}},
            {"maintenance": {"on": True, "testers": [f"t{i}@e.com" for i in range(51)]}},
            {"maintenance": {"on": True, "back_by": "2026-12-01T10:00:00"}}):  # naive time
    try:
        ac.validate(bad); check(False, f"store: rejects {bad}")
    except ValueError:
        check(True, f"store: rejects {list(bad)}")
# save -> cache -> load round trip (restore the original document in finally)
# after save(voice paused, message_en "Back at 5"):
check(ac.is_paused("voice") and not ac.is_paused("chat"), "store: save applies at once")
check(ac.paused_message("voice", "en") == "Back at 5", "store: the owner's English message")
check(ac.paused_message("voice", "my") == translate("feature_paused_msg", "my", feature=translate("app_switch_voice", "my")),
      "store: an empty Myanmar message uses the standard one")
check(ac.paused_message("chat", "en") == "Chat with Ko Toe Pwar is paused for now. Please try again later.",
      "store: the standard English message names the feature")
# FeaturePaused: status 403, detail code feature_paused, feature voice, message in the language asked
# load() with a stored value "not json" and with {"switches": {"nope": {...}, "voice": {"paused": true}}}:
#   the first leaves nothing paused (logged), the second pauses voice and drops "nope"
check(ac.is_tester("TESTER@example.com") and not ac.is_tester(None), "store: tester match ignores case")
```

  Section `admin_api` (HTTP against the stub; admins made as in `e2e/test_devices.py:211-219`, one `moderator`, one
  `admin`): moderator GET 200 and PUT 403; admin PUT with a bad document -> 422 with readable text; admin PUT with
  voice paused -> 200, a GET shows it, the admin log has `app_control_update` mentioning "voice"; `finally`: PUT the
  original document back.

- [ ] **Step 2: Run them to see them fail**

Run: `& $PY -u test_app_control.py store admin_api` (from `e2e`, after `run_suite.ps1 -NoSuite`). Expected: `ModuleNotFoundError: app_control`.

- [ ] **Step 3: Implement `backend/app_control.py`, `backend/sql/app_control.py` and the two admin endpoints** with the interfaces above; mirror `plans/store.py` (cache globals, `_write_gen` stale-load guard at `plans/store.py:311-379`, refresh loop at `:407-429`). `back_by` is parsed with `datetime.fromisoformat` and must be timezone-aware. Add to `NOTIFICATION_TRANSLATIONS` (en and my): `feature_paused_msg`, `maintenance_msg`, and `app_switch_<key>` for every switch. In `main.py` startup load it in a `try` and start the refresh loop (same pattern as `plan_store`, `main.py:121-126`); cancel it on shutdown.

- [ ] **Step 4: Run the tests to see them pass**

Run: `run_suite.ps1 -NoSuite` (restarts the server on the new code), then `& $PY -u test_app_control.py store admin_api`. Expected: exit 0, no `[BUG]`.

- [ ] **Step 5: Commit**

```bash
git add backend/app_control.py backend/sql/app_control.py backend/app_control_routes.py backend/notification_service.py backend/main.py e2e/test_app_control.py e2e/run_backend_suite.py
git commit -m "feat(backend): app control settings store, switch checks and admin settings API"
```

### Task 2: Enforce the switches on the routes and jobs

**Files:**
- Modify: `backend/main.py` (chat `:341`, `:474`; insights `_generate_for` `:592`, `_free_monthly_insight` `:810`, `_translate_if_possible` `:707`, `translate-myanmar` `:1036`)
- Modify: `backend/transaction_routes.py` (`:1050` transcribe-audio, `:1127` extract-from-text, `:1172` extract-multiple-from-text, `:1342` extract-from-image)
- Modify: `backend/budget_routes.py:106` (ai-suggest), `backend/budget_service.py:1358` (`_owner_gets_ai_budgets`)
- Modify: `backend/custom_insight_routes.py:122` (create), `:232` (translate)
- Modify: `backend/insights_service.py:91` (`_scheduled_insight`)
- Modify: `backend/auth_routes.py:155` (register), `:580` (claim-free-trial)
- Modify: `backend/family_routes.py:111` (create), `:198` (invites), `:213` (accept)
- Test: `e2e/test_app_control.py` section `switches`

**Interfaces:**
- Consumes: `app_control.require_on`, `is_paused`, `paused_detail`, `both_languages`, `FeaturePaused` (Task 1); `PUT /api/admin/app-control` (Task 1) to pause switches on the stub server; `plans.access.user_language(user)`.

- [ ] **Step 1: Write the failing tests** (section `switches`). Switches are paused over HTTP with `PUT /api/admin/app-control` (the stub server is a separate process; in-process `save` would not reach it); the in-process checks (`_scheduled_insight`, `_owner_gets_ai_budgets`) pause with `app_control.save` inside their own `_backend_async` call. Restore the original document in `finally`. Users: a Plus user, a Free user and a Myanmar-language Plus user, made like `e2e/test_ai_correctness.py:65-79`. Assertions:

```python
# each paused switch refuses its routes with 403 feature_paused, the feature key, and the user's language
for key, method, path in [("chat", "post", "/api/chat"), ("chat", "post", "/api/chat/stream"),
                          ("voice", "post", "/api/transactions/extract-from-text"),
                          ("voice", "post", "/api/transactions/extract-multiple-from-text"),
                          ("receipts", "post", "/api/transactions/extract-from-image"),
                          ("budget_ideas", "post", "/api/budgets/ai-suggest"),
                          ("reports", "post", "/api/insights/regenerate"),
                          ("custom_reports", "post", "/api/custom-insights"),
                          ("translation", "post", "/api/insights/translate-myanmar"),
                          ("free_trial", "post", "/api/auth/claim-free-trial"),
                          ("family_new", "post", "/api/family"), ("family_new", "post", "/api/family/invites")]:
    r = ...  # minimal valid body for each route
    d = r.json().get("detail", {})
    check(r.status_code == 403 and d.get("code") == "feature_paused" and d.get("feature") == key, f"switches: {path}")
# transcribe-audio: paused voice -> 403 before the upload is read; nothing counted:
check(usage_counter("entry") == before, "switches: a paused voice entry uses no entry allowance")
# a Myanmar-language user gets the Myanmar message
# register while signups paused -> 403 feature_paused with both languages in the message; no user row created
# chat history (GET /api/chat/history) and GET /api/family still work while chat / family_new are paused
# GET /api/insights with a stored weekly insight and reports paused -> 200 with the stored insight (no new one)
# GET /api/insights with nothing stored and reports paused -> 403 feature_paused (reports)
# GET /api/insights?language=mm (Plus, stored English insight without content_mm) with translation paused ->
#   200, English content, translation_unavailable.code == "feature_paused"; a stored content_mm is still returned
# _scheduled_insight with reports paused: no insight made, no error raised (in-process, generate replaced by a stub
#   that records calls: not called)
# _owner_gets_ai_budgets is False for a Plus owner while budget_ideas is paused (in-process)
# after un-pausing everything, POST /api/chat works again
```

- [ ] **Step 2: Run them to see them fail** — `& $PY -u test_app_control.py switches`; expected `[BUG]` lines (200s or 422s instead of 403).

- [ ] **Step 3: Implement.** Each route calls `app_control.require_on(key, user_language(current_user))` as its first line after authentication, before `quota.reserve`/`quota.use` or reading the upload. Register: if `is_paused("signups")`, raise `HTTPException(403, {"code": "feature_paused", "feature": "signups", "message": both_languages("signups")})` before anything is written. Reports: the check goes in `_generate_for` (language of `book.person`) and in `_free_monthly_insight` before it generates (a stored older real insight is still shown; with none, `FeaturePaused` reaches the client — it is an `HTTPException`, so the existing `except (HTTPException, PlanError): raise` passes it on). Translation inside reads: at the top of `_translate_if_possible`, if `is_paused("translation")` and `_needs_translation_call(insight)`, return `(insight, paused_detail("translation", user_language(user)))`. Scheduled reports: in `_scheduled_insight`, after the plan check, `if is_paused("reports"): logger.info(...); return` (the run counts as done; skipped periods are not made up). Budget renewal: first line of `_owner_gets_ai_budgets`: `if is_paused("budget_ideas"): return False`.

- [ ] **Step 4: Run the tests to see them pass** — expected exit 0. Also run `& $PY -u test_ai_providers.py` and `& $PY -u test_family.py` (nothing paused: unchanged behaviour); expected exit 0.

- [ ] **Step 5: Commit** — `git commit -m "feat(backend): paused features are refused by the server"` (all files above).

### Task 3: Announcements and the app config endpoint

**Files:**
- Modify: `backend/app_control_routes.py` (announcement endpoints on `admin_router`; new `public_router` with `GET /api/app/config`)
- Modify: `backend/sql/tables.py` (table `announcements`), `backend/sql/app_control.py` (announcement queries)
- Create: `backend/alembic/versions/20261125_b7d2e9c4a1f3_announcements.py` (`revision = 'b7d2e9c4a1f3'`, `down_revision = 'f3d8a6c1e094'`; creates and drops the table)
- Modify: `backend/main.py` (include `public_router` next to the other routers, `main.py:100-105`)
- Test: `e2e/test_app_control.py` sections `announcements`, `config`

**Interfaces:**
- Table `announcements`: `id` Text PK (uuid4 hex), `text_en` Text, `text_my` Text, `style` Text (CHECK in ('info','warning')), `link_url` Text NULL, `link_label_en` Text NULL, `link_label_my` Text NULL, `plans` ARRAY(Text) NOT NULL, `starts_at` TS NOT NULL, `ends_at` TS NULL, `created_by` Text, `created_at` TS default now, `updated_at` TS default now.
- `sql/app_control.py`: `list_announcements() -> List[dict]` (newest start first), `create_announcement(row) -> dict`, `update_announcement(id, row) -> Optional[dict]`, `delete_announcement(id) -> bool`, `live_announcement(plan: str, now: datetime) -> Optional[dict]` (`starts_at <= now`, `ends_at` null or `> now`, `plan = ANY(plans)`, newest `starts_at` first, limit 1).
- `app_control.validate_announcement(body: Mapping) -> dict` (rules in Global Constraints; `plans` a non-empty subset of `plans.catalog.PLANS`; `starts_at` aware; `ends_at` aware and after `starts_at`; label without link is an error).
- Announcement endpoints (JSON):
  - `GET /api/admin/app-control/announcements` (moderator+) -> list; `POST` (admin+) -> created; `PUT /announcements/{announcement_id}` (admin+); `DELETE` (admin+); log `announcement_create` / `announcement_update` / `announcement_delete`
- `GET /api/app/config?lang=en|my` (default en; Authorization optional: a missing or invalid token means signed out, never 401) ->
  `{"maintenance": {"on": bool, "message": str, "back_by": str|None, "can_enter": bool}, "paused": {<key>: <message>}, "announcement": null | {"id", "updated_at", "style", "text", "link_url", "link_label"}}`.
  `paused` lists only paused switches, messages in `lang`. `can_enter` is true when maintenance is off or the token's email is a tester. The announcement is chosen by the signed-in user's `effective_plan`; signed out: null. `link_label` falls back to "Open" / its Myanmar text when empty.

- [ ] **Step 1: Write the failing tests** (sections `announcements`, `config`):

```python
# announcements: create (plans ["plus"], starts now-1h, ends now+1h) -> 200; bad link "ftp://x" -> 422;
#   naive starts_at -> 422; ends before starts -> 422; missing text_my -> 422; update; delete; each logged
# config (signed out, lang my): no announcement; paused messages in Myanmar
# config (Plus user): the live plus announcement in their lang; a Free user: none; a future one (starts now+1h): none;
#   an ended one: none; two live ones: the newer start wins
# config with an invalid token -> 200 and signed-out answer
# config maintenance on with the user a tester -> can_enter true; not a tester -> false
# finally: delete the test announcements and PUT the original settings document back
```

- [ ] **Step 2: Run to see them fail** — `& $PY -u test_app_control.py announcements config` after `run_suite.ps1 -NoSuite` (the reset runs the new migration); expected 404s.

- [ ] **Step 3: Implement** the table, the migration (copy the shape of `alembic/versions/20261121_f3d8a6c1e094_local_job_done.py`), the queries, `validate_announcement`, the announcement endpoints and `public_router` (request models with `extra="forbid"`, as in `plans_admin_routes.py:31-75`). The config endpoint decodes the token with `utils._decode_user_token` inside `try` and looks the user up by email only to read the plan.

- [ ] **Step 4: Run to see them pass**; also `& $PY -u test_budget_categories.py` (its migration checks walk the chain to head); expected exit 0.

- [ ] **Step 5: Commit** — `git commit -m "feat(backend): announcements and the app config endpoint"`.

### Task 4: Maintenance gate

**Files:**
- Modify: `backend/app_control.py` (add `class MaintenanceGate` — ASGI middleware), `backend/main.py` (register it **before** the `CORSMiddleware` block at `main.py:154`, so CORS wraps it)
- Test: `e2e/test_app_control.py` section `maintenance` and the final section `clean`

**Interfaces:**
- `MaintenanceGate(app)`: while `maintenance_on()`, an HTTP request whose path starts with `/api/` gets the 503 body from Global Constraints unless: the path starts with `/api/admin/`, `/api/app/config`, `/api/app/check-version`, `/api/app/latest-android`, `/api/plan/public`, `/api/auth/login`, `/api/auth/verify-email`, `/api/auth/resend-verification`, `/api/auth/forgot-password/`; or it is `GET /api/auth/me` (so older apps reach their home screen and show the message on their next action); or the bearer token decodes (`utils._decode_user_token`, in `try`) to a tester's email. `OPTIONS` requests always pass. Paths outside `/api/` always pass.

- [ ] **Step 1: Write the failing tests** (section `maintenance`, HTTP against the stub, maintenance turned on through `PUT /api/admin/app-control`, testers `[" Tester@Example.com "]` with a user registered as `tester@example.com`):

```python
r = c.get("/api/transactions", headers=user_h)
check(r.status_code == 503 and r.json()["detail"]["code"] == "maintenance", "maintenance: the app API is closed")
check("\n\n" in r.json()["detail"]["message"], "maintenance: the message carries both languages")
check(c.get("/api/transactions", headers=tester_h).status_code == 200, "maintenance: a tester gets in")
check(c.get("/api/admin/app-control", headers=admin_h).status_code == 200, "maintenance: the admin API stays open")
for path in ("/api/app/config", "/api/plan/public", "/api/app/latest-android"):
    check(c.get(path).status_code != 503, f"maintenance: {path} stays open")
check(c.post("/api/auth/login", json={...tester...}).status_code == 200, "maintenance: sign-in stays open")
check(c.get("/api/auth/me", headers=user_h).status_code == 200, "maintenance: GET /api/auth/me stays open")
r = c.get("/api/transactions", headers={**user_h, "Origin": "https://app.example.com"})
check(r.status_code == 503 and "access-control-allow-origin" in r.headers, "maintenance: the 503 carries CORS headers")
r = c.options("/api/transactions", headers={"Origin": "https://app.example.com",
                                             "Access-Control-Request-Method": "GET"})
check(r.status_code == 200, "maintenance: a CORS preflight still passes")
check(c.get("/").status_code != 503, "maintenance: the root health check stays open")
# finally: maintenance off; then /api/transactions is 200 again
# section clean: the stored document equals the one read at the very start of the run; no test announcements left
```

- [ ] **Step 2: Run to see them fail** — expected `[BUG]` (200 instead of 503).

- [ ] **Step 3: Implement `MaintenanceGate`** (shape of `RejectNulCharacters`, `main.py:169-188`; the `back_by` is `maintenance_back_by().isoformat()` or null).

- [ ] **Step 4: Run to see them pass**; then `& $PY -u test_api.py` (nothing on: unchanged); expected exit 0.

- [ ] **Step 5: Commit** — `git commit -m "feat(backend): maintenance mode gate"`.

### Task 5: Admin panel "App control" tab

**Files:**
- Create: `admin/src/AppControl.jsx`
- Modify: `admin/src/App.jsx` (sidebar list at `App.jsx:1284-1299`: `{ id: 'app-control', icon: <a lucide icon such as ToggleLeft>, label: 'App control' }`; render `<AppControl token={token} adminRole={admin.role} />` next to the Plans tab at `App.jsx:1460`)

**Interfaces:**
- Consumes: the Task 3 admin endpoints through `apiRequest` from `admin/src/api.js` (as `PlansSettings.jsx` does).

- [ ] **Step 1: Build the tab** with sections Maintenance; Ko Toe Pwar features (chat, voice, receipts, budget_ideas, reports, custom_reports, translation); Accounts (signups, free_trial); Family (family_new); Announcements. Each switch: a toggle, English and Myanmar message fields with a 300-character counter, and a one-line preview of what users see (the owner's text or the standard sentence with the switch name). One Save button for the settings document showing "Unsaved changes" like `PlansSettings.jsx`; server errors shown inline (not `alert`). Maintenance: toggle, both messages, "back by" (a `datetime-local` input converted to an ISO string with the browser's offset), testers (one email per line). Turning maintenance on, or pausing sign-ups, asks with the in-page `ConfirmDialog` (`App.jsx:60`), naming the testers who can still get in. Announcements: list grouped Live / Scheduled / Ended, create/edit form (both texts with counters, style, link + labels, plan checkboxes, start, optional end), delete with `ConfirmDialog`, preview in both languages. Moderators see everything read-only (inputs disabled, no Save).

- [ ] **Step 2: Lint and build** — `npm run lint; npm run build`; expected no errors.

- [ ] **Step 3: Browser check** against the local stub server (`VITE_API_BASE_URL=http://127.0.0.1:8765`, `npm run dev`): sign in as a test super admin; pause voice with a message, save, reload: it stays; turn maintenance on (the dialog appears), then off; create, edit and delete an announcement. Leave the settings as they were.

- [ ] **Step 4: Commit** — `git commit -m "feat(admin): App control tab"`.

### Task 6: App: config, maintenance screen, sign-ups closed

**Files:**
- Create: `frontend/lib/models/app_config.dart`, `frontend/lib/providers/app_control_provider.dart`, `frontend/lib/screens/maintenance/maintenance_screen.dart`
- Modify: `frontend/lib/services/api_service.dart` (`getAppConfig`; the signal hook in `_ApiClient`), `frontend/lib/main.dart` (provider registration at `main.dart:326`; the start-up flow at `main.dart:448-497`), `frontend/lib/screens/auth/register_screen.dart`, `frontend/lib/screens/auth/login_screen.dart:269`, `frontend/lib/services/localization_service.dart` (en + my)
- Test: `frontend/test/app_control_test.dart`

**Interfaces:**
- `class AppConfig { final bool maintenanceOn; final String maintenanceMessage; final DateTime? backBy; final bool canEnter; final Map<String, String> paused; final Announcement? announcement; static const AppConfig open; factory AppConfig.fromJson(Map<String, dynamic>); }`
- `class Announcement { final String id; final String updatedAt; final String style; final String text; final String? linkUrl; final String linkLabel; }`
- `ApiService.getAppConfig({required String lang}) -> Future<AppConfig>` (`GET /api/app/config?lang=`, sends the token when there is one; the app's `mm`/`my` language code mapped to `my`)
- `ApiService.onAppControlSignal` (`void Function()?`): `_ApiClient` calls it after any response that is 403 with `detail.code == "feature_paused"` or 503 with `detail.code == "maintenance"`.
- `class AppControlProvider extends ChangeNotifier with WidgetsBindingObserver { AppConfig get config; bool isPaused(String key); String? pausedMessage(String key); bool get blocked; Future<void> refresh(); }` — `blocked` = `maintenanceOn && !canEnter`; `refresh()` on construction, on `AppLifecycleState.resumed`, when the signed-in user changes, and on `onAppControlSignal`; a failed fetch keeps the last config (initially `AppConfig.open`). The fetcher is injectable for tests.

- [ ] **Step 1: Write the failing tests:** `AppConfig.fromJson` (all fields; unknown keys ignored; missing → open); provider: refresh applies, a failed refresh keeps the last config, `blocked` only when not a tester; `MaintenanceScreen` shows the message and the "back by" time in local time, Retry calls `refresh`, the "Sign in" link only when signed out; the register screen with `signups` paused shows the message and a disabled Create button; the login screen's Register link, when paused, shows the message instead of opening the screen.

- [ ] **Step 2: Run** `flutter test test/app_control_test.dart` — expected failures (missing files).

- [ ] **Step 3: Implement.** In `main.dart` the gate goes before Step 1 of the flow: `if (appControl.blocked && !_showTesterSignIn) return MaintenanceScreen(onSignIn: ...)`; tapping "Sign in" shows the login screen; after a sign-in the provider refreshes (a tester then passes). New strings (en + my): maintenance title, "Back by {time}", Retry, "Sign in". Messages from the server are shown as given.

- [ ] **Step 4: Run** the test file, then `flutter test` and `flutter analyze` — expected all pass, 166 infos.

- [ ] **Step 5: Commit** — `git commit -m "feat(app): app config, maintenance screen and closed sign-ups"`.

### Task 7: App: announcement banner and paused buttons

**Files:**
- Create: `frontend/lib/widgets/announcement_banner.dart`, `frontend/lib/widgets/paused_feature.dart`
- Modify: the dashboard in `frontend/lib/screens/home/home_screen.dart` (banner at the top of the dashboard content), and the entry points:
  voice `home_screen.dart:1721`, `add_transaction_screen.dart:267`, `transactions_list_screen.dart:287`;
  receipts `home_screen.dart:1739`, `add_transaction_screen.dart:273`, `transactions_list_screen.dart:303`;
  chat: the input of `AiChatScreen` (route `/ai-chat`, `main.dart:299`); budget ideas `create_budget_screen.dart:360`;
  reports: the regenerate action that calls `InsightProvider.regenerateInsights`; custom reports: the submit in
  `screens/insights/custom_insight_form.dart` and the translate action in `custom_insight_report_screen.dart`;
  free trial `subscription_screen.dart:339`; family: create `family_screen.dart:222`, the invite action, accept
  `family_invitations_screen.dart:50`
- Test: `frontend/test/app_control_widgets_test.dart`

**Interfaces:**
- `bool showIfPaused(BuildContext context, String key)`: when `AppControlProvider.isPaused(key)`, shows the message in a SnackBar and returns true (the caller then does nothing).
- `Widget PausedLook({required String featureKey, required Widget child})`: the child at 40% opacity while paused (still tappable, so the tap shows the message).
- `AnnouncementBanner()`: shows `config.announcement` unless dismissed; info/warning colours from the theme; the link opens with `url_launcher` outside the app; the close button stores `"<id>@<updatedAt>"` in SharedPreferences key `dismissed_announcement` (an edited announcement has a new `updatedAt`, so it shows again).

- [ ] **Step 1: Write the failing tests:** the banner shows the text, hides after close, stays hidden on rebuild, shows again when `updatedAt` changes, shows nothing when there is no announcement; `showIfPaused` shows the server's message and returns true only when paused; `PausedLook` greys only when paused; one entry point per kind (the voice button on the home screen) shows the message instead of opening `VoiceInputScreen` while paused.

- [ ] **Step 2: Run** `flutter test test/app_control_widgets_test.dart` — expected failures.

- [ ] **Step 3: Implement** the widgets and wire every entry point listed above (wrap in `PausedLook`, start the handler with `if (showIfPaused(context, '<key>')) return;`).

- [ ] **Step 4: Run** the test file, `flutter test`, `flutter analyze` — all pass, 166 infos.

- [ ] **Step 5: Commit** — `git commit -m "feat(app): announcement banner and paused feature buttons"`.

### Task 8: Whole-branch verification

- [ ] **Step 1:** Full backend suite in the background (`run_suite.ps1`); expected `== problems (0) ==` (a known flake is rerun on its own and reported).
- [ ] **Step 2:** `flutter test` and `flutter analyze` on the branch; `npm run lint; npm run build` in `admin`.
- [ ] **Step 3:** Browser check of the web app against the stub server: pause voice → the home voice button is grey and shows the message; publish an announcement for Free → it shows on a Free user's dashboard and stays closed after closing; maintenance on → the maintenance screen; a tester signs in and gets through; maintenance off. Restore the settings.
- [ ] **Step 4:** Update the deploy notes in the spec's "Deploy" section if anything changed (migration `b7d2e9c4a1f3`; server and app together).
