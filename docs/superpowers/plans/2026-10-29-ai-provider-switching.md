# AI Provider Switching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the owner choose OpenAI, Gemini or Claude (and the model) for each AI feature, from the admin panel or server settings, with automatic fallback to backups and a provider status box.

**Architecture:** A new `backend/ai_providers/` package holds four parts:

- the feature catalogue;
- setting resolution (admin panel, then environment, then built-in);
- error classification and health/cool-off;
- one client per provider behind a common interface, plus a runner that walks a feature's chain of providers.

Every AI call site in the backend is moved onto the runner. The admin panel gets an "AI" page backed by new admin routes. The Flutter app stops sending a provider.

**Tech Stack:**
- Backend: Python 3.12, FastAPI, SQLAlchemy Core async with asyncpg, Alembic, PostgreSQL 16.
- AI SDKs: `openai` 3.28.0, `google-genai` 2.29.0, and `anthropic` (new; Python SDK 1.x).
- Admin panel: React/Vite. App: Flutter 3.32.1.
- Tests: the e2e suites in `e2e/`, run against a stubbed local server.

**Spec:** `docs/superpowers/specs/2026-10-29-ai-provider-switching-design.md`. Read it before any task; this plan argues from it.

## Global Constraints

- Provider ids are exactly `openai`, `gemini`, `claude`. Feature keys are exactly `chat`, `insight_weekly`, `insight_monthly`, `insight_translation`, `budget_suggestion`, `budget_auto_create`, `transaction_text`, `transaction_image`, `transaction_audio`.
- Claude is never allowed for `transaction_audio`.
- Built-in defaults (deploying with no new settings must change nothing for users):

  | Feature | Default |
  |---|---|
  | `chat`, `insight_weekly`, `insight_monthly` | `gemini:gemini-2.5-flash` |
  | `insight_translation` | `gemini:gemini-2.5-pro` |
  | `budget_suggestion`, `budget_auto_create`, `transaction_text` | `openai:gpt-4o-mini` |
  | `transaction_image` | `openai:gpt-4o` |
  | `transaction_audio` | `openai:whisper-1` |

- Default models per provider:
  - `OPENAI_MODEL` default `gpt-4o-mini`
  - `GEMINI_MODEL` default `gemini-2.5-flash`
  - `CLAUDE_MODEL` default `claude-sonnet-5-5`

  Exceptions:
  - `transaction_image`/openai defaults to `gpt-4o`;
  - `transaction_audio`/openai defaults to `whisper-1`;
  - `transaction_audio`/gemini uses the Gemini default model.
- Environment variables per feature:
  - `AI_<FEATURE>_PROVIDER`
  - `AI_<FEATURE>_MODEL`
  - `AI_<FEATURE>_BACKUPS`: comma list of `provider[:model]`, or `none`.
- API keys come only from `OPENAI_API_KEY`, `GOOGLE_API_KEY` and `ANTHROPIC_API_KEY`. A key, or any part of one, must never appear in an API response, the admin UI, the status table or logs.
- **Never send `temperature`, `top_p` or `top_k` to Claude.** They return a 400 since 2026-10-21.
- Claude client: the official `anthropic` SDK, async client. Read `python/claude-api/README.md` and the structured-outputs and streaming docs in the claude-api skill before writing Claude code; never guess SDK names.
- On Claude Sonnet 5.5 / Opus 5.5 / Fable 5.1, send `fallbacks="default"` with beta `server-side-fallback-2026-07-01` via `client.beta.messages`.
- Old installed apps keep working: `ai_provider` in chat bodies and insights query strings is accepted, validated as today, and ignored.
- One backend process. In-memory caches and health are fine. Every schema change is an Alembic migration (`cd backend && alembic upgrade head`).
- Never read or print `backend/.env`. All testing runs against the local stubbed server (`e2e/`), never production.
- Each dependency added is pinned to an exact version in `backend/requirements.txt`.

## Review Focus

1. **A main provider with no API key.** Saving it from the panel succeeds with a warning. Requests skip it as `not_configured` and go to backups. With "no backups", the feature fails as today. *(Tests in Task 6 and Task 7.)*
2. **A typo in one feature's model name.** For example a wrong Claude model on `chat`: only that provider and model pair cools off. Other features on the same provider keep working, and the status card lists the cooled model. *(Task 4, Task 6.)*
3. **Every provider in the chain fails for chat.** The app gets today's error frame, nothing is saved to chat history, and no usage row is written. *(Task 8.)*
4. **Duplicates in a saved setting.** A backup list that repeats the main target or an entry is rejected with 422 by the admin API. *(Task 7.)*
5. **A provider error that echoes the key.** For example OpenAI's "Incorrect API key provided: sk-…". The text stored and returned by status and "Test" is redacted: nothing matching `sk-[A-Za-z0-9_-]{6,}`, `AIza[0-9A-Za-z_-]{10,}` or `sk-ant-[A-Za-z0-9_-]{6,}` survives. *(Task 4, Task 7.)*

---

## File map

**New backend package `backend/ai_providers/`:**

| File | Responsibility |
|---|---|
| `__init__.py` | Re-exports `run`, `run_stream`, `Prompt`, `Completion`, `Target`, `AllProvidersFailed`, `UnusableAnswer` |
| `features.py` | Feature catalogue: keys, allowed providers, built-in defaults, default models, known-model lists, Claude effort and token limits per feature |
| `types.py` | Dataclasses `Target`, `Prompt`, `Completion`, `FeatureSetting` |
| `settings.py` | Resolution panel → env → built-in; in-memory cache; `chain(feature)` |
| `errors.py` | `ProviderFailure`, `UnusableAnswer`, `AllProvidersFailed`, `classify()`, `redact()` |
| `health.py` | Cool-off state (provider-wide and per provider+model); persisting last error and last success |
| `clients/base.py` | `ProviderClient` protocol, `get_client()` |
| `clients/openai_client.py` | OpenAI client |
| `clients/gemini_client.py` | Gemini client |
| `clients/claude_client.py` | Claude client |
| `runner.py` | `run()`, `run_stream()`: walks the chain, falls back, cools off, tracks usage |

**Other new backend files:**
- `backend/sql/ai_settings.py`: rows for panel settings and provider status.
- `backend/ai_admin_routes.py`: `/api/admin/ai/*`.
- `backend/alembic/versions/20261029_<rev>_ai_provider_switching.py`.

**Backend files modified:**
- `backend/requirements.txt`
- `backend/sql/tables.py`
- `backend/ai_usage_models.py`, `backend/ai_usage_service.py`, `backend/sql/ai_usage.py`
- `backend/ai_chatbot.py`
- `backend/ai_chatbot_gemini.py` (deleted)
- `backend/main.py`
- `backend/insights_service.py`, `backend/scheduler.py` (if the job signatures change)
- `backend/budget_service.py`, `backend/transaction_routes.py`
- `backend/chat_models.py`, `backend/admin_routes.py`

**Admin panel:**
- `admin/src/AISettings.jsx` (new)
- `admin/src/api.js`
- `admin/src/App.jsx`
- `admin/src/AIUsageStats.jsx`

**Flutter:**
- `frontend/lib/models/chat.dart`
- `frontend/lib/providers/chat_provider.dart`, `frontend/lib/providers/insight_provider.dart`
- `frontend/lib/services/api_service.dart`
- `frontend/lib/screens/ai/ai_chat_screen.dart`, `frontend/lib/screens/insights/insights_screen.dart` (only where they reference `AIProvider`)

**Tests:**
- `e2e/stubenv.py` (fakes for all three providers, plus a failure-control file)
- `e2e/test_ai_providers.py` (new print-only suite)
- `e2e/run_backend_suite.py` (register the suite)
- Updates to `e2e/test_api.py`, `e2e/test_backend_r4.py`, `e2e/test_jobs.py`, `e2e/test_jobs2.py`

**Docs:**
- `docs/web-version.md`, the Render section in `docs/postgres-migration-plan.md`: list the new environment variables.

## How to run things (used by every task)

Use this environment:

- Python: `C:\Users\LINNYI~1\AppData\Local\Temp\claude\C--projects-Flow\88f449c7-2e35-4a07-890d-5a91aa9c3948\scratchpad\venv_final\Scripts\python.exe`, called **PY** below. It has the backend requirements plus httpx and psycopg. Install new requirements into it.
- PostgreSQL binaries: `…\scratchpad\pg_dl\srv\pgsql\bin`, called **PGBIN**.

To restart the server and run one suite:

```powershell
& "<scratchpad>\pg\run_suite.ps1" -NoSuite      # (re)starts the stubbed server on :8765 with E2E_FAKE_AI=1; PostgreSQL on :54329 must be running
& PY -u e2e\test_ai_providers.py
```

Start PostgreSQL first if it isn't listening:

```powershell
& PGBIN\pg_ctl.exe -D <scratchpad>\pg_data -o "-p 54329" -w start
```

Then, with `DATABASE_URL=postgresql://flow@127.0.0.1:54329/flow_e2e`, run `cd backend; PY -m alembic upgrade head`.

- Full backend suite: `& "<scratchpad>\pg\run_suite.ps1"`.
- Flutter end-to-end: `e2e\run_e2e.ps1 -Python PY -PgBin PGBIN`.

**Writing tests in `e2e/test_ai_providers.py`.** Follow `e2e/test_app_download.py`:

1. `import stubenv` first, then `os.chdir(stubenv.BACKEND)`.
2. Define a `check(ok, name, detail)` that prints `[PASS]` or `[BUG]`.
3. Use `httpx.Client(base_url="http://127.0.0.1:8765")` for HTTP checks.
4. Import backend modules **in-process** for pure-logic checks. Settings, errors and health are plain Python and need no server. When an in-process check needs the database, use `asyncio.run(...)`.
5. Exit non-zero if any check failed.
6. Log in as admin by inserting your own admins into `db.admins`, so you don't trip the root admin's login lockout from `test_api`:
   - one with role `admin`;
   - one with role `moderator`;
   - use passwords hashed with `admin_utils.get_password_hash`, then call `POST /api/admin/login`.

---

### Task 1: Dependency, provider fakes and the failure-control file

**Files:**
- Modify: `backend/requirements.txt`
- Modify: `e2e/stubenv.py`
- Create: `e2e/test_ai_providers.py` (skeleton plus fake self-checks)
- Modify: `e2e/run_backend_suite.py` (add `"test_ai_providers"` to `SUITES` and `PRINT_ONLY`)

**Interfaces:**
- Produces, in `stubenv`:
  - `FAKE_CONTROL` (path `e2e/.data/fake_ai.json`)
  - `set_fake_ai(**kinds: str) -> None`, e.g. `set_fake_ai(claude="billing", openai="timeout")`
  - `clear_fake_ai() -> None`
  - `FakeAPIError(Exception)` with attributes `status_code: int`, `code: str | None`, `message: str`
  - Fakes for `openai.AsyncOpenAI`, `google.genai.Client` and `anthropic.AsyncAnthropic` that read `FAKE_CONTROL` on every call.
  - Every fake call appends `record("ai_call", provider=<id>, target=<method>, model=<model>)` to the outbox.
- **Failure kinds** a fake must honour:

  | Kind | Behaviour |
  |---|---|
  | `billing` | `FakeAPIError(402, "insufficient_quota", "You exceeded your current quota")`. Claude: `FakeAPIError(400, None, "Your credit balance is too low to access the Anthropic API")` |
  | `auth` | 401 |
  | `rate_limit` | 429 |
  | `server` | 503. Claude: 529 |
  | `timeout` | raise `TimeoutError` |
  | `model_not_found` | 404 |
  | `bad_request` | 400, message `"invalid image"` |
  | `refusal` | Claude only: a response whose `stop_reason` is `"refusal"` |
  | `empty` | a successful response with empty text |
  | `bad_json` | a successful response whose text is `"not json"` |
  | `fail_mid_stream` | streaming only: one chunk, then a 503 |
  | `echo_key` | 401 with the message `"Incorrect API key provided: sk-e2eSECRETabcdef123"` |

- With no control entry, a fake succeeds. It returns the same canned bodies the OpenAI fake returns today (single or multi transaction JSON, `FAKE_REPLY`, a 3-chunk stream, usage 10/5/15). Gemini and Claude fakes must succeed in fake mode too; today Gemini always fails.
- Each fake implements exactly the SDK surface its client (Task 5) calls. Write the fakes to the shapes below, then keep them in sync with Task 5:
  - **OpenAI:** `chat.completions.create(model, messages, max_tokens, response_format?, stream?, stream_options?)` and `audio.transcriptions.create(model, file, language?)` returning `.text`.
  - **Gemini:** `client.aio.models.generate_content(model, contents, config)` and `client.aio.models.generate_content_stream(...)`. Responses carry `.text`, `.candidates[0].finish_reason` (e.g. `"STOP"`, `"MAX_TOKENS"`, `"SAFETY"`), and `.usage_metadata.prompt_token_count` / `.candidates_token_count`.
  - **Claude:** `client.beta.messages.create(...)` and `client.beta.messages.stream(...)`. `stream` is an async context manager with an async `text_stream` and `await get_final_message()`. Responses carry `.content=[block(type="text", text=...)]`, `.stop_reason`, and `.usage.input_tokens` / `.output_tokens`.

- [ ] **Step 1: Add the `anthropic` dependency and install it.** Run `PY -m pip index versions anthropic`. Pin the newest 1.x release in `backend/requirements.txt` as `anthropic==<version>`, then `PY -m pip install -r backend/requirements.txt`. Expected: `PY -c "import anthropic; print(anthropic.__version__)"` prints that version.

- [ ] **Step 2: Write the failing fake self-checks** in `e2e/test_ai_providers.py`, all in-process:
  - `fake_claude_succeeds`: `await anthropic.AsyncAnthropic().beta.messages.create(model="claude-sonnet-5-5", max_tokens=100, messages=[{"role": "user", "content": "hi"}])` returns `stop_reason == "end_turn"`, non-empty text and `usage.input_tokens == 10`.
  - `fake_gemini_succeeds`: `await genai.Client().aio.models.generate_content(model="gemini-2.5-flash", contents="hi")` gives a non-empty `.text`.
  - `fake_control_billing`: after `set_fake_ai(claude="billing")`, the Claude call raises `FakeAPIError` with `status_code == 400` and `"credit balance is too low" in message`. `clear_fake_ai()` restores success.
  - `fake_records_calls`: the outbox gains an `ai_call` line with `provider == "claude"`.

- [ ] **Step 3: Run it and check it fails.** Run `PY -u e2e\test_ai_providers.py`. Expected: fails (no Claude fake, Gemini raises `AIStubError`).

- [ ] **Step 4: Implement the fakes and control helpers** in `e2e/stubenv.py`:
  - Keep the existing OpenAI fake bodies.
  - Patch `anthropic.AsyncAnthropic`, plus `anthropic.Anthropic` with the raiser, before backend import, the same way `openai.AsyncOpenAI` is patched.
  - Set `ANTHROPIC_API_KEY=sk-ant-e2e-stub` in the env block.
  - Outside fake mode (`E2E_FAKE_AI` unset), all three keep raising `AIStubError` as today.

- [ ] **Step 5: Run it and check it passes.** Run `PY -u e2e\test_ai_providers.py`. Expected: 4 PASS, exit 0.

- [ ] **Step 6: Commit.** `git add backend/requirements.txt e2e/stubenv.py e2e/test_ai_providers.py e2e/run_backend_suite.py`, then `git commit -m "test: fakes for OpenAI, Gemini and Claude with on-demand failures"`.

---

### Task 2: Feature catalogue and setting resolution (environment and built-in)

**Files:**
- Create: `backend/ai_providers/__init__.py`, `backend/ai_providers/features.py`, `backend/ai_providers/types.py`, `backend/ai_providers/settings.py`
- Test: `e2e/test_ai_providers.py`

**Interfaces:**
- Produces, in `types.py`:

  ```python
  @dataclass(frozen=True)
  class Target:
      provider: str
      model: str

  @dataclass(frozen=True)
  class FeatureSetting:
      main: Target
      backups: tuple[Target, ...] | None   # None = default backups, () = "no backups"
      source: str                          # "panel" | "server" | "default"

  @dataclass
  class Prompt:
      system: str
      user: str
      image: bytes | None = None
      image_mime: str | None = None
      json_schema: dict | None = None
      max_tokens: int = 2000

  @dataclass
  class Completion:
      text: str
      input_tokens: int
      output_tokens: int
      finish: str   # "stop" | "length" | "filtered" | "refusal"
  ```

- Produces, in `features.py`:
  - `PROVIDERS = ("openai", "gemini", "claude")`
  - `FEATURES: dict[str, FeatureSpec]`, where `FeatureSpec(key, label, allowed: tuple[str, ...], default: Target, usage_type: AIFeatureType)`
  - `default_model(feature: str, provider: str) -> str`
  - `KNOWN_MODELS: dict[str, list[str]]`:
    - openai: `gpt-4o-mini`, `gpt-4o`, `whisper-1`
    - gemini: `gemini-2.5-flash`, `gemini-2.5-pro`
    - claude: `claude-sonnet-5-5`, `claude-haiku-5-5`, `claude-opus-5-5`
  - `CLAUDE_EFFORT: dict[str, str]`: `chat`, `transaction_text`, `transaction_image`, `budget_suggestion` and `budget_auto_create` → `"low"`; the insight and translation features → `"medium"`.
  - `usage_type` maps:
    - `insight_weekly` → `WEEKLY_INSIGHT`
    - `insight_monthly` → `MONTHLY_INSIGHT`
    - `insight_translation` → `TRANSLATION`
    - `transaction_text` → `TRANSACTION_TEXT_EXTRACTION`
    - `transaction_image` → `TRANSACTION_IMAGE_EXTRACTION`
    - `transaction_audio` → `TRANSACTION_AUDIO_TRANSCRIPTION`
    - each remaining feature to the `AIFeatureType` of the same name
- Produces, in `settings.py`:
  - `parse_env(feature: str, environ: Mapping[str, str]) -> FeatureSetting | None`
  - `validate(feature: str, s: FeatureSetting) -> list[str]`: returns error messages (empty list = valid). It checks:
    - unknown provider;
    - provider not allowed for the feature;
    - empty model;
    - a backup equal to `main`;
    - duplicate backups.
  - `resolve(feature: str) -> FeatureSetting`
  - `chain(feature: str, configured: Callable[[str], bool]) -> list[Target]`: `main` first, then the backups. When `backups is None`, the backups are the configured allowed providers other than `main.provider`, in `PROVIDERS` order, each with `default_model(feature, p)`.
  - `set_panel_cache(rows: dict[str, FeatureSetting]) -> None`: Task 3 fills the panel layer.

- [ ] **Step 1: Write the failing resolution checks** in-process, passing an explicit `environ` dict to `parse_env`:
  - `env_unit`: `{"AI_CHAT_PROVIDER": "claude"}` → `main == Target("claude", "claude-sonnet-5-5")`, `backups is None`, `source == "server"`.
  - `env_model_without_provider_ignored`: `{"AI_CHAT_MODEL": "claude-haiku-5-5"}` → `parse_env` returns `None`.
  - `env_backups_none`: `{"AI_CHAT_PROVIDER": "openai", "AI_CHAT_BACKUPS": "none"}` → `backups == ()`.
  - `env_backups_list`: `"gemini:gemini-2.5-pro,claude"` → `(Target("gemini", "gemini-2.5-pro"), Target("claude", "claude-sonnet-5-5"))`.
  - `env_claude_audio_rejected`: `{"AI_TRANSACTION_AUDIO_PROVIDER": "claude"}` → `None`, with a logged warning.
  - `builtin_defaults`: with no panel rows and an empty environ, each feature resolves to the Global Constraints default with `source == "default"`.
  - `chain_default_backups`: chat default, with `configured = lambda p: p != "claude"` → `[gemini:gemini-2.5-flash, openai:gpt-4o-mini]`. With every provider configured, `claude:claude-sonnet-5-5` is appended.
  - `chain_no_backups`: a `FeatureSetting` with `backups=()` → a chain holding only `main`.
  - `validate_duplicates`: a backup equal to `main` and a repeated backup each produce one error.

- [ ] **Step 2: Run it and check it fails.** Run `PY -u e2e\test_ai_providers.py`. Expected: `ModuleNotFoundError: ai_providers`.

- [ ] **Step 3: Implement `features.py`, `types.py` and `settings.py`.** `resolve` reads `os.environ` at call time, through a module-level env snapshot refreshed by `settings.reload_env()`, so a restart picks up changes. Invalid environment units are logged with `logging.warning` and skipped.

- [ ] **Step 4: Run it and check it passes.** Expected: all Task 2 checks PASS.

- [ ] **Step 5: Commit.** `git commit -m "feat(ai): feature catalogue and setting resolution"`.

---

### Task 3: Database: panel settings, provider status, usage `fallback_from`, insights CHECK

**Files:**
- Modify: `backend/sql/tables.py`. Add to `ai_usage`:
  - `fallback_from` Text nullable;
  - CHECK `fallback_from IS NULL OR fallback_from IN ('openai','gemini','claude')`.

  Change the `insights` CHECK to `ai_provider IN ('openai','gemini','claude')`.
- Create: `backend/alembic/versions/20261029_<rev>_ai_provider_switching.py`, with `down_revision = '799d29a14d00'` and a working downgrade.
- Create: `backend/sql/ai_settings.py`
- Modify: `backend/ai_providers/settings.py` (panel layer)
- Test: `e2e/test_ai_providers.py`

**New tables:**
- `ai_feature_settings`:
  - `feature` Text PK
  - `main_provider` Text not null
  - `main_model` Text not null
  - `backups` JSONB nullable. Null = default backups; `[]` = none; otherwise a list of `{"provider","model"}`.
  - `updated_at` timestamptz not null
  - `updated_by` Text
- `ai_provider_status`:
  - `provider` Text PK
  - `last_error` Text
  - `last_error_at` timestamptz
  - `last_success_at` timestamptz

**Interfaces:**
- Produces, in `sql/ai_settings.py`:
  - `async def list_feature_settings() -> list[dict]`
  - `async def upsert_feature_setting(feature: str, main_provider: str, main_model: str, backups: list[dict] | None, updated_by: str) -> None`
  - `async def delete_feature_setting(feature: str) -> bool`
  - `async def get_provider_status() -> dict[str, dict]`
  - `async def record_provider_error(provider: str, message: str, at: datetime) -> None`
  - `async def record_provider_success(provider: str, at: datetime) -> None`
- Produces, in `settings.py`:
  - `async def load_panel() -> None`: reads the rows into the cache; invalid rows are logged and skipped.
  - `async def save_panel(feature: str, s: FeatureSetting, admin_email: str) -> None`: validates, upserts, refreshes the cache. Raises `ValueError(list_of_errors)` on invalid input.
  - `async def clear_panel(feature: str) -> None`
  - `start_refresh_loop()`: about every 60 s, called from `main.py` startup next to the scheduler.
  - `def setting_warnings(s: FeatureSetting, configured: Callable[[str], bool]) -> list[str]`: one warning when `s.main.provider` isn't configured. Used by Task 7.

- [ ] **Step 1: Write the failing checks.**
  - `migration_applied`: in-process with psycopg, `ai_feature_settings` and `ai_provider_status` exist, `ai_usage.fallback_from` exists, and inserting an insight with `ai_provider='claude'` succeeds.
  - `panel_wins_over_env`: after `save_panel("chat", FeatureSetting(Target("openai", "gpt-4o"), (), "panel"), "t@x")` with `AI_CHAT_PROVIDER=claude` in the env snapshot, `resolve("chat")` gives `main == Target("openai", "gpt-4o")`, `backups == ()` and `source == "panel"`.
  - `clear_panel_falls_back_to_env`: after `clear_panel("chat")`, `source == "server"`.
  - `backups_null_vs_empty_roundtrip`: `None` and `()` survive a save and reload as distinct values.

- [ ] **Step 2: Run them and check they fail** (`PY -u e2e\test_ai_providers.py`). Expected: FAIL, missing tables.

- [ ] **Step 3: Implement the migration, tables, `sql/ai_settings.py` and the panel layer**, then run `cd backend; PY -m alembic upgrade head`. Also check that `PY -m alembic downgrade -1`, then `upgrade head`, both succeed.

- [ ] **Step 4: Run them and check they pass.**

- [ ] **Step 5: Commit.** `git commit -m "feat(ai): tables for panel settings, provider status and fallback tracking"`.

---

### Task 4: Error classification, redaction and health/cool-off

**Files:**
- Create: `backend/ai_providers/errors.py`, `backend/ai_providers/health.py`
- Modify: `backend/insights_service.py`. Move the patterns behind `is_billing_error`, `is_rate_limit_error`, `_RATE_LIMIT_TEXT` and `_BILLING_TEXT` into `errors.py`, and have the insights versions call it so `main.py` keeps working.
- Test: `e2e/test_ai_providers.py`

**Interfaces:**
- Produces, in `errors.py`:
  - `KINDS = ("auth", "billing", "rate_limit", "server", "timeout", "model_not_found", "not_configured", "refusal", "unusable")`
  - `@dataclass class ProviderFailure: provider: str; model: str; kind: str; message: str` (message already redacted)
  - `class UnusableAnswer(Exception)`: raised by a parser to mean "try the next provider, don't cool off".
  - `class AllProvidersFailed(Exception)` with `failures: list[ProviderFailure]` and a property `all_rate_limited: bool`.
  - `def classify(exc: BaseException, provider: str, model: str) -> ProviderFailure | None`. `None` means a request-level error: no fallback.
  - `def redact(text: str) -> str`: the Review Focus #5 patterns are replaced by `[redacted]`, and the result is truncated to 300 characters.
- **Classification rules.** Read `status_code` or `status`, `code`, `type(exc).__name__` and `str(exc)`, walking `__cause__` / `__context__` as `is_rate_limit_error` does today:

  | Condition | Kind |
  |---|---|
  | `TimeoutError`, `asyncio.TimeoutError`, or SDK `APITimeoutError` / `APIConnectionError` (any of the three SDKs) | `timeout` |
  | 401 or 403 | `auth` |
  | 402, `insufficient_quota`, or a message matching the billing regex or `credit balance is too low` | `billing` (checked before the 400 rule) |
  | 429 or `RESOURCE_EXHAUSTED` | `rate_limit` |
  | 404, or a message containing `model` together with `not found` / `does not exist` | `model_not_found` |
  | ≥ 500, 529, or `overloaded` | `server` |
  | other 400 / 422 | `None` |
  | anything else | `None` |

- Produces, in `health.py`:
  - `def is_available(t: Target, now: float | None = None) -> bool`
  - `def mark_failure(f: ProviderFailure, now: float | None = None) -> None`:
    - provider-wide, 300 s, for `auth`, `billing`, `not_configured`, and `server` on the second consecutive server failure;
    - provider+model, 300 s, for `model_not_found`;
    - provider+model, 60 s, for `rate_limit`;
    - nothing for `refusal`, `unusable` or `timeout` (a single timeout).
  - `def mark_success(t: Target) -> None`: resets the consecutive-server counter.
  - `def snapshot() -> dict[str, dict]`: per provider, `cooling_until` (epoch or `None`) and `cooling_models: {model: until}`.
  - `async def persist_failure(f)` and `async def persist_success(t)`: write to `ai_provider_status`, swallowing database errors.

- [ ] **Step 1: Write the failing checks**, all in-process:
  - `classify_table`: each `FakeAPIError` from Task 1's kinds maps to its kind. `bad_request` → `None`; `ValueError("x")` → `None`; `TimeoutError()` → `timeout`.
  - `classify_claude_billing_400`: `FakeAPIError(400, None, "Your credit balance is too low…")` → `billing`.
  - `redact_keys`: `redact("Incorrect API key provided: sk-e2eSECRETabcdef123")` contains no `sk-e2e`; the same holds for `AIzaSyAbcdefghijk123` and `sk-ant-api03-abcdef`.
  - `cooloff_model_scoped`: after `mark_failure(ProviderFailure("claude", "claude-typo", "model_not_found", ""))`:
    - `is_available(Target("claude", "claude-typo"))` is `False`;
    - `is_available(Target("claude", "claude-sonnet-5-5"))` is `True`;
    - with `now = +301`, both are `True`.
  - `cooloff_provider_scoped`: a `billing` failure makes every claude model unavailable for 300 s.
  - `rate_limit_60s`: available again at +61 s.
  - `server_needs_two`: one `server` failure leaves the target available; two consecutive ones mark the provider unavailable.

- [ ] **Step 2: Run them and check they fail.**

- [ ] **Step 3: Implement `errors.py` and `health.py`, and point `insights_service`'s helpers at `errors.py`.**

- [ ] **Step 4: Run them and check they pass.**

- [ ] **Step 5: Commit.** `git commit -m "feat(ai): error classification, key redaction and cool-off"`.

---

### Task 5: Provider clients (OpenAI, Gemini, Claude)

**Files:**
- Create: `backend/ai_providers/clients/__init__.py`, `clients/base.py`, `clients/openai_client.py`, `clients/gemini_client.py`, `clients/claude_client.py`
- Test: `e2e/test_ai_providers.py`

**Interfaces:**
- Produces, in `clients/base.py`:

  ```python
  class ProviderClient(Protocol):
      name: str
      def configured(self) -> bool
      async def complete(self, model: str, prompt: Prompt, *, effort: str | None = None) -> Completion
      def stream(self, model: str, prompt: Prompt, *, effort: str | None = None) -> AsyncIterator[str | Completion]
          # yields text chunks, then exactly one Completion (text="", usage, finish)
      async def transcribe(self, model: str, audio: bytes, filename: str, language: str | None) -> Completion
          # Claude raises NotImplementedError
      async def ping(self, model: str) -> None   # tiny request, max_tokens about 16
  ```

  `def get_client(provider: str) -> ProviderClient` keeps one instance per provider.
- `configured()` is `bool(os.getenv(<KEY>))`.
- Finish mapping:

  | Provider | Raw value | Finish |
  |---|---|---|
  | OpenAI | `"length"` | `"length"` |
  | OpenAI | `"content_filter"` | `"filtered"` |
  | Gemini | `MAX_TOKENS` | `"length"` |
  | Gemini | `SAFETY` / `PROHIBITED_CONTENT` / `BLOCKLIST` | `"filtered"` |
  | Claude | `max_tokens` | `"length"` |
  | Claude | `refusal` | `"refusal"` |
  | any | anything else | `"stop"` |

**Per-client requirements:**
- **OpenAI.**
  - `json_schema` set → `response_format={"type": "json_object"}`.
  - Images are sent as today: a base64 `image_url` data URI.
  - `transcribe` uses `audio.transcriptions.create`; tokens are estimated as `len(text)//4`, as today.
  - Streaming uses `stream_options={"include_usage": True}`.
- **Gemini.**
  - Uses `client.aio.models.generate_content` / `generate_content_stream`, which are true async calls.
  - `system_instruction` comes from `prompt.system`.
  - `json_schema` set → `response_mime_type="application/json"`.
  - Images go in as `Part.from_bytes`.
  - `transcribe` sends the audio bytes, with a mime type from the file extension, plus the instruction "Transcribe this audio exactly. Reply with only the transcript." and the language hint when given.
  - Usage falls back to `len // 4` when `usage_metadata` is missing, as today.
- **Claude.**
  - Uses the `client.beta.messages` endpoint.
  - System goes in `system`. Images go in as a base64 image block before the text.
  - JSON features: `prompt.json_schema` → structured outputs via `output_config.format`, using the exact shape from the claude-api skill's structured-outputs docs.
  - Effort: `output_config.effort = effort`.
  - Refusal fallback: for `claude-sonnet-5-5`, `claude-opus-5-5` and `claude-fable-5-1`, add `betas=["server-side-fallback-2026-07-01"]` and `fallbacks="default"`.
  - Never set temperature, top_p or top_k.
  - When `prompt.max_tokens > 16000`, `complete` uses `stream(...)` plus `get_final_message()` to avoid HTTP timeouts.
  - Text is the concatenation of the `text` blocks; ignore `thinking` and `fallback` blocks.

- [ ] **Step 1: Write the failing checks**, in-process against the fakes:
  - `client_complete_each`: for each provider, `await get_client(p).complete(m, Prompt("sys", "hi"))` returns non-empty text, `finish == "stop"` and `input_tokens > 0`.
  - `client_json_each`: with `json_schema={"type": "object"}`, the text parses as JSON.
  - `client_stream_each`: collecting `stream()` gives ≥ 2 string chunks and then one `Completion`.
  - `claude_no_sampling_params`: the fake records the kwargs it received. Assert there is no `temperature` / `top_p` / `top_k`, and that `fallbacks == "default"` for `claude-sonnet-5-5`.
  - `claude_refusal_finish`: after `set_fake_ai(claude="refusal")`, `finish == "refusal"`.
  - `gemini_transcribe`: returns the fake's transcript text.
  - `claude_transcribe_not_supported`: raises `NotImplementedError`.

- [ ] **Step 2: Run them and check they fail.**

- [ ] **Step 3: Implement the three clients**, keeping the Task 1 fakes in sync with the exact SDK calls used.

- [ ] **Step 4: Run them and check they pass.**

- [ ] **Step 5: Commit.** `git commit -m "feat(ai): OpenAI, Gemini and Claude clients behind one interface"`.

---

### Task 6: The runner (fallback, cool-off, usage tracking, status)

**Files:**
- Create: `backend/ai_providers/runner.py`
- Modify: `backend/ai_usage_models.py`:
  - `AIProviderType.CLAUDE = "claude"`;
  - `ChatRequest.ai_provider` stays as it is, in `chat_models.py`.
- Modify: `backend/ai_usage_service.py`:
  - `track_ai_usage(..., fallback_from: str | None = None)`;
  - `PRICING["claude"]`: `claude-sonnet-5-5` 2.00/10.00, `claude-haiku-5-5` 0.10/0.50, `claude-opus-5-5` 4.00/20.00 per 1M tokens.
- Test: `e2e/test_ai_providers.py`

**Interfaces:**
- Consumes:
  - `settings.chain`, `settings.resolve` (Tasks 2–3)
  - `errors.classify`, `UnusableAnswer`, `AllProvidersFailed` (Task 4)
  - `health.*` (Task 4)
  - `get_client` (Task 5)
- Produces:

  ```python
  @dataclass
  class RunResult(Generic[T]):
      value: T
      target: Target
      fallback_from: str | None
      completion: Completion

  async def run(feature: str, *, user_id: str | None,
                call: Callable[[ProviderClient, Target], Awaitable[Completion]],
                parse: Callable[[Completion], T] = lambda c: c,
                background: bool = False) -> RunResult[T]

  async def run_stream(feature: str, *, user_id: str | None, prompt: Prompt
                       ) -> AsyncIterator[str | RunResult[str]]
      # yields chunks, then one RunResult (value = full text)
  ```

**Algorithm for `run`.** This is the one place a body is specified.

```
targets = chain(feature, configured=lambda p: get_client(p).configured())
available = [t for t in targets if health.is_available(t)] or targets   # all cooling → still try in order
failures = []
for t in available:
    client = get_client(t.provider)
    if not client.configured():
        failures.append(ProviderFailure(t.provider, t.model, "not_configured", "no API key")); continue
    attempts = 3 if background else 1
    for attempt in range(attempts):
        try:
            c = await call(client, t)
            if c.finish == "refusal": raise UnusableAnswer("refusal")   # recorded as kind "refusal"
            if c.finish == "filtered" or not c.text.strip(): raise UnusableAnswer(c.finish or "empty")
            value = parse(c)                      # parse may raise UnusableAnswer
        except UnusableAnswer as e:
            failures.append(ProviderFailure(..., "refusal" if str(e) == "refusal" else "unusable", ...)); break
        except Exception as e:
            f = classify(e, t.provider, t.model)
            if f is None: raise                   # request-level: no fallback, no health change
            if background and f.kind == "rate_limit" and attempt < attempts - 1:
                await asyncio.sleep(2 ** attempt * 5); continue
            health.mark_failure(f); await health.persist_failure(f); failures.append(f); break
        else:
            health.mark_success(t); await health.persist_success(t)
            fallback_from = failures[0].provider if failures else None
            if user_id: await track_ai_usage(user_id, FEATURES[feature].usage_type, t.provider, t.model,
                                              c.input_tokens, c.output_tokens, c.input_tokens + c.output_tokens,
                                              fallback_from=fallback_from)
            return RunResult(value, t, fallback_from, c)
raise AllProvidersFailed(failures)
```

- `track_ai_usage` takes `AIProviderType`, so pass `AIProviderType(t.provider)`.
- `call` is responsible for passing `effort=CLAUDE_EFFORT.get(feature)` when `t.provider == "claude"`. Provide `def default_call(prompt: Prompt, feature: str)`, which returns a `call` doing `client.complete(t.model, prompt, effort=...)`, so most features don't repeat this.
- `run_stream` uses the same chain and rules. It may move to the next target **only until the first non-empty chunk has been yielded**. After that, any exception propagates. A `Completion` with `finish == "refusal"` or empty text before any chunk counts as unusable. It tracks usage like `run`.

- [ ] **Step 1: Write the failing checks.** Each sets the panel with `save_panel` and the fakes with `set_fake_ai`, then calls `run(..., call=default_call(Prompt("s", "u"), "chat"))` in-process. Read the latest outbox `ai_call` lines to see which providers were called.
  - `fallback_on_billing`: chat = `claude` with default backups; `claude="billing"` → `target.provider == "openai"` (first configured in `PROVIDERS` order that isn't claude: openai), `fallback_from == "claude"`. The `ai_usage` row has provider `openai` and `fallback_from` `claude`.
  - `fallback_each_kind`: the same holds for `auth`, `rate_limit`, `server`, `timeout`, `model_not_found`, `refusal`, `empty` and `bad_json`. For `bad_json`, use a `parse` that calls `json.loads` and raises `UnusableAnswer` on error.
  - `no_fallback_on_bad_request`: `claude="bad_request"` → the exception propagates; the outbox shows no openai or gemini call after the claude call.
  - `no_backups_fails`: backups `()` plus `claude="billing"` → `AllProvidersFailed`, with exactly one failure.
  - `not_configured_main_skipped`: with `ANTHROPIC_API_KEY` removed from `os.environ` inside the check (restored after), chat = claude → it answers from openai with `fallback_from == "claude"`.
  - `cooled_target_skipped_next_time`: after a billing fallback, a second `run` doesn't call claude at all.
  - `model_typo_scoped`: chat = `claude:claude-typo` with `claude="model_not_found"` applied only to that model (extend the control file with `"claude@claude-typo": "model_not_found"`). Then `insight_weekly` = `claude:claude-sonnet-5-5` still answers from claude.
  - `background_retries_rate_limit`: with `claude="rate_limit"` for the first 2 calls only (control entry `{"claude": {"kind": "rate_limit", "times": 2}}`) and `background=True` → answered by claude, `fallback_from is None`. Patch `asyncio.sleep` to a no-op in-process for speed.
  - `stream_fallback_before_first_chunk`: `run_stream` with `claude="server"` yields openai chunks and then a `RunResult` with `fallback_from == "claude"`.
  - `stream_no_fallback_after_chunk`: `claude="fail_mid_stream"` → one chunk, then an exception; no openai call.
  - `status_persisted_redacted`: after `claude="echo_key"`, `get_provider_status()["claude"]["last_error"]` contains no `sk-e2e`.

- [ ] **Step 2: Run them and check they fail.**

- [ ] **Step 3: Implement the runner, the pricing and the `track_ai_usage` signature**, and extend the stubenv control format with `provider@model` keys and `{"kind", "times"}` values.

- [ ] **Step 4: Run them and check they pass.**

- [ ] **Step 5: Commit.** `git commit -m "feat(ai): runner with fallback, cool-off and usage tracking"`.

---

### Task 7: Admin API for settings, status and test

**Files:**
- Create: `backend/ai_admin_routes.py`. Register it in `backend/main.py` with `app.include_router(ai_admin_router)`. Call `await settings.load_panel()` and `settings.start_refresh_loop()` on startup.
- Test: `e2e/test_ai_providers.py`

**Interfaces** (all under `/api/admin/ai`):
- `GET /settings` (`require_moderator_or_above`) returns:

  ```json
  {"providers": [{"id","label","configured": bool,"known_models": [...]}],
   "features": [{"key","label","allowed": [...],
                 "effective": {"main": {"provider","model"}, "backups": [...] | null, "source"},
                 "default_chain": [{"provider","model"}],
                 "panel": {...same shape...} | null}]}
  ```

  `default_chain` is what `backups: null` expands to right now, so the UI can show it.
- `PUT /settings/{feature}` (`require_admin_or_super`):
  - Body: `{"main": {"provider","model"}, "backups": [{"provider","model"}] | null}`. Here `null` means default backups and `[]` means no backups.
  - Returns 200 with the new effective setting, plus `"warnings": [...]` when the main provider isn't configured.
  - Returns 422 with the `validate()` messages.
  - Returns 404 for an unknown feature.
  - Logs with `log_admin_action(admin_id, admin_email, "ai_setting_update", ...)`.
- `DELETE /settings/{feature}` (`require_admin_or_super`): clears the panel row ("use server setting"). Logged as `ai_setting_reset`.
- `GET /status` (`require_moderator_or_above`): per provider, with all text redacted:
  - `configured`
  - `state`: `"working" | "failing" | "cooling" | "unused"`
  - `cooling_until`, `cooling_models`
  - `last_error`, `last_error_at`, `last_success_at`
  - `backup_answers_24h`: the count of `ai_usage` rows in the last 24 h with `fallback_from = provider`

  State rules:
  - **cooling** if `health.snapshot()` shows provider-wide cooling;
  - **failing** if `last_error_at > last_success_at`;
  - **working** if `last_success_at` is set;
  - **unused** otherwise.
- `POST /test/{provider}` (`require_admin_or_super`): body `{"model": str | null}`. Calls `client.ping(model or the provider default)`. Returns `{"ok": true}` or `{"ok": false, "error": <redacted>}`. Records success or failure in health and status.

- [ ] **Step 1: Write the failing HTTP checks**, using your own `admin` and `moderator` accounts (see "How to run things"):
  - `settings_get_moderator_ok`: 200; 9 features; `chat.effective.source == "default"`; the claude provider is `configured: true`.
  - `settings_put_admin_ok_and_applied`: PUT chat to claude with backups `[]` → 200. A following chat request (Task 8 reuses this check) uses claude. Do the GET check here: `effective.source == "panel"`.
  - `settings_put_moderator_forbidden`: 403.
  - `settings_put_claude_audio_422`: PUT `transaction_audio` main claude → 422.
  - `settings_put_duplicates_422`: backups repeating main → 422.
  - `unconfigured_warning` (in-process, since the test server has every key): `settings.setting_warnings(FeatureSetting(Target("claude", "claude-sonnet-5-5"), (), "panel"), configured=lambda p: p != "claude")` returns exactly one warning that names Claude. The PUT handler returns `setting_warnings(...)` as `warnings`.
  - `settings_delete_resets`: DELETE → `source` back to `server` or `default`.
  - `status_shape_and_redaction`: after `set_fake_ai(claude="echo_key")` and `POST /test/claude` → `ok: false`. The error and `GET /status` contain no `sk-e2e`, and `state == "failing"`.
  - `status_backup_count`: after one fallback from claude (see Task 6), `backup_answers_24h` for claude is ≥ 1.
  - `admin_logs_written`: `GET /api/admin/logs` contains `ai_setting_update`.

- [ ] **Step 2: Restart the server (`run_suite.ps1 -NoSuite`), run the checks and confirm they fail.**

- [ ] **Step 3: Implement the routes.**

- [ ] **Step 4: Restart the server, run the checks and confirm they pass.**

- [ ] **Step 5: Commit.** `git commit -m "feat(ai): admin API for provider settings, status and test"`.

---

### Task 8: Chat on the runner (one chatbot, `ai_provider` ignored)

**Files:**
- Modify: `backend/ai_chatbot.py`. `FinancialChatbot` keeps RAG, prompt building, the vector-store cache and `refresh_user_data`. `stream_chat` builds a `Prompt` (system plus user prompt as today, `max_tokens` about 4000) and delegates to `runner.run_stream("chat", user_id=..., prompt=...)`. It yields `(chunk, None)`, and finally `("", {"input_tokens", "output_tokens", "total_tokens", "model_name", "provider", "fallback_from"})`. Persona is "Toe Pwar AI".
- Delete: `backend/ai_chatbot_gemini.py`.
- Modify: `backend/main.py`:
  - `/api/chat/stream`: drop the per-provider bot selection; the runner already tracks usage, so remove the duplicate `track_ai_usage` call.
  - `/api/chat/refresh-data`: accept and ignore `ai_provider`.
  - `_invalidate_ai_caches`: one bot.
  - `AllProvidersFailed` → today's `{"error", "done": true}` frame, with history not saved.
- Test: `e2e/test_ai_providers.py`

- [ ] **Step 1: Write the failing HTTP checks**, as a premium user from `seed_rich` or registered in the suite:
  - `chat_uses_panel_provider`: with chat = claude via PUT, `POST /api/chat/stream` streams chunks, and the outbox's last `ai_call` has `provider == "claude"`.
  - `chat_ignores_ai_provider_field`: sending `"ai_provider": "gemini"` still uses claude.
  - `chat_invalid_ai_provider_422`: `"ai_provider": "bard"` → 422.
  - `chat_fallback_invisible`: `claude="billing"` with default backups → a normal reply, with no `error` frame.
  - `chat_all_fail_error_frame_no_history`: backups `[]` with `claude="billing"` → an error frame. The `chat_messages` count is unchanged, and no new `ai_usage` row exists.

- [ ] **Step 2: Restart the server and run the checks. Expected: FAIL.**

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Restart the server and run the checks. Expected: PASS.** Also run `PY -u e2e\test_api.py` and update the chat checks at lines ~675–697 to the new behaviour (Gemini now answers via the fake). Don't delete them.

- [ ] **Step 5: Commit.** `git commit -m "feat(ai): chat runs on the provider runner; one chatbot"`.

---

### Task 9: Insights on the runner (generate once, read across providers, translation)

**Files:**
- Modify: `backend/insights_service.py`:
  - **`_call_insight_model`** → `runner.run("insight_weekly" | "insight_monthly", user_id=..., call=default_call(prompt, feature), background=<from caller>)`. Keep today's temperature-free prompt content. Keep max tokens about 2500 / 3000, and about 12000 for Claude because of thinking.
  - **Stored provider.** `ai_provider` on the stored insight is `result.target.provider`.
  - **Translation.** `_translate_once` → `runner.run("insight_translation", ...)`. The truncation check uses `completion.finish == "length"`, then today's chunked retry by section. Delete the hard-coded `TRANSLATION_GEMINI_MODEL`.
  - **Reads.** `latest_valid_insight`, `_latest_real_insight` and `_todays_placeholder` ignore `ai_provider` and take the newest row for user and type across providers. Change `sql/insights.py latest()` to make `ai_provider` optional.
  - **Placeholders.** Placeholder rows are stored with the feature's current main provider.
  - **Jobs.** `generate_weekly_insights_for_all_users` and the monthly job generate **once per user** with `background=True`.
  - **Errors.** `AllProvidersFailed` → `InsightAIError(rate_limited=e.all_rate_limited, provider=<main provider>)`, so the `_insight_http_error` mapping in `main.py` keeps working.
- Modify: `backend/main.py`:
  - The insights routes accept and ignore `ai_provider`.
  - `POST /api/insights/generate-weekly` stops looping over providers.
- Test: `e2e/test_ai_providers.py`; update `e2e/test_jobs.py`, `e2e/test_jobs2.py`, `e2e/test_backend_r4.py` and the insights part of `e2e/test_api.py`.

- [ ] **Step 1: Write the failing checks:**
  - `insight_regenerate_uses_setting`: `insight_weekly` = claude, then `POST /api/insights/regenerate?ai_provider=openai` → the stored row has `ai_provider == "claude"`.
  - `insight_get_ignores_provider`: `GET /api/insights?ai_provider=gemini` returns that same claude-generated insight.
  - `translation_on_claude`: `insight_translation` = claude, then `POST /api/insights/translate-myanmar` → `content_mm` is set, and the outbox shows a claude call.
  - `translation_length_retry`: with the fake returning `finish="length"` for the first translation call (control kind `length_once`, added to stubenv), the chunked retry runs and still produces `content_mm`.
  - `job_generates_once_per_user`: running the weekly job in-process for one premium user inserts exactly 1 new insight row, not 2.
  - `all_fail_returns_placeholder`: every provider set to `server` → GET insights returns the stored or placeholder insight with a 200, not a 5xx (mirrors `test_backend_r4`).

- [ ] **Step 2: Restart the server and run the checks. Expected: FAIL.**

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Restart the server and run the checks. Expected: PASS.** Then run `test_jobs.py`, `test_jobs2.py`, `test_backend_r4.py`, `test_regressions_all.py` and `test_api.py`. Update any expectation that assumes two providers, so it expects one row per user per period; don't delete checks.

- [ ] **Step 5: Commit.** `git commit -m "feat(ai): insights generated once per user via the provider runner"`.

---

### Task 10: Budgets on the runner

**Files:**
- Modify: `backend/budget_service.py`:
  - `_generate_with_ai` → `runner.run("budget_suggestion", ...)`.
  - `_generate_ai_category_budgets` → `runner.run("budget_auto_create", ...)`.
  - Each builds a `Prompt` with `json_schema` (a JSON schema matching the object today's prompt asks for; write it as a module constant).
  - `parse` does `json.loads` plus today's field checks, raising `UnusableAnswer` on failure.
  - Remove the hard-coded `"gpt-4o-mini"` and the now-duplicate `track_ai_usage` calls.
  - Keep `_generate_basic_suggestions` and `_generate_adjusted_budgets` as the final fallback when `AllProvidersFailed`.
- Modify: `backend/budget_routes.py`. `AllProvidersFailed` → 503 `"AI is temporarily unavailable"`, instead of 500 with `str(e)`.
- Test: `e2e/test_ai_providers.py`

- [ ] **Step 1: Write the failing checks:**
  - `budget_suggest_on_claude`: `budget_suggestion` = claude → `POST /api/budgets/ai-suggest` returns 200, and the outbox shows a claude call.
  - `budget_bad_json_falls_back`: `claude="bad_json"` → 200 from openai. The `ai_usage` row has `fallback_from == "claude"`.
  - `budget_all_fail_503`: backups `[]` plus `claude="server"` → 503 (or basic suggestions, if the route already falls back to them), never a 500.

- [ ] **Step 2: Run them and confirm FAIL.**

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run them and confirm PASS, then run `test_api.py` budget sections.**

- [ ] **Step 5: Commit.** `git commit -m "feat(ai): budget AI features run on the provider runner"`.

---

### Task 11: Transaction text, receipt and voice on the runner

**Files:**
- Modify: `backend/transaction_routes.py`:
  - **`/extract-from-text`, `/extract-multiple-from-text`** → `runner.run("transaction_text", ...)`. Schema constants match today's JSON bodies; `parse` validates and raises `UnusableAnswer`.
  - **`/extract-from-image`** → `runner.run("transaction_image", ...)`, with `Prompt(image=<bytes>, image_mime=<detected>)`.
  - **`/transcribe-audio`** → `runner.run("transaction_audio", ..., call=lambda c, t: c.transcribe(t.model, data, filename, language))`.
  - Remove the hard-coded `gpt-4o-mini`, `gpt-4o` and `whisper-1`, and the duplicate tracking.
  - **Errors:**
    - `AllProvidersFailed` → 503 `"AI is temporarily unavailable"`;
    - a request-level error → 400 with a safe message;
    - keep the existing 502 for a response that passed `parse` but fails later checks.
- Test: `e2e/test_ai_providers.py`

- [ ] **Step 1: Write the failing checks:**
  - `text_extract_on_gemini`: `transaction_text` = gemini → 200, with the canned transaction.
  - `image_extract_on_claude`: `transaction_image` = claude, POST a tiny valid PNG → 200, and the outbox's claude call contains an image block.
  - `audio_falls_back_to_gemini`: `transaction_audio` = openai with `openai="billing"` → 200 transcript from gemini.
  - `image_bad_request_no_fallback`: `claude="bad_request"` → 400; no openai call.

- [ ] **Step 2: Run them and confirm FAIL.**

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run them and confirm PASS, then run `test_api.py` transaction sections and `test_sweep.py`.**

- [ ] **Step 5: Commit.** `git commit -m "feat(ai): transaction AI features run on the provider runner"`.

---

### Task 12: Usage statistics per provider (backend and admin page)

**Files:**
- Modify: `backend/sql/ai_usage.py`. `overall_stats` and `per_user_stats` return `cost_by_provider: dict[str, float]` (grouped by `provider`) instead of the fixed openai and gemini sums.
- Modify: `backend/ai_usage_models.py`. In `UserAIUsageStats` and `AIUsageStatsResponse`, replace `openai_cost` / `gemini_cost` with `cost_by_provider: dict[str, float]`.
- Modify: `backend/admin_routes.py`, the ai-usage endpoints. Include `fallback_from` in the per-record output of `/ai-usage/user/{id}`.
- Modify: `admin/src/AIUsageStats.jsx`:
  - one cost card per provider present in `cost_by_provider`;
  - per-user columns generated from the providers;
  - the per-record line shows `provider · model`, plus "(backup for <fallback_from>)" when set.
- Test: `e2e/test_ai_providers.py`

- [ ] **Step 1: Write the failing check.** `usage_stats_include_claude`: after a claude-answered request, `GET /api/admin/ai-usage/stats` has `cost_by_provider["claude"] > 0`. `/ai-usage/user/{id}` records include `fallback_from`.

- [ ] **Step 2: Run it and confirm FAIL.**

- [ ] **Step 3: Implement the backend, then the admin UI.**

- [ ] **Step 4: Run it and confirm PASS.** Then `cd admin; npm run lint; npm run build`: both succeed with no new warnings.

- [ ] **Step 5: Commit.** `git commit -m "feat(ai): usage stats per provider including Claude and backups"`.

---

### Task 13: Admin "AI" page

**Files:**
- Create: `admin/src/AISettings.jsx`
- Modify: `admin/src/api.js`. Add `getAISettings()`, `updateAISetting(feature, body)`, `resetAISetting(feature)`, `getAIStatus()` and `testAIProvider(provider, model)`, calling the Task 7 endpoints.
- Modify: `admin/src/App.jsx`. Add a sidebar item `{ id: 'ai', icon: <a lucide icon already used, or Bot>, label: 'AI Providers' }` next to the existing items around line 1121, and render `<AISettings />` for it.

**Content** (spec "Status box and usage tracking"):
- **Status cards**, one per provider:
  - configured badge;
  - state chip (working / failing / cooling until hh:mm / unused);
  - last error and time;
  - last success;
  - backup answers in 24 h;
  - cooling models;
  - a "Test" button with the note "sends one tiny request (costs a fraction of a cent)". Hidden for moderators, disabled when not configured.
- **Feature table**, one row per feature:
  - main provider select, limited to `allowed`;
  - model select from `known_models`, plus "Other…" with a text input;
  - backups mode: "Default (…)" showing `default_chain`, "No backups", or "Custom", with an ordered list (add, remove, move up and down);
  - source badge (Admin panel / Server setting / Built-in);
  - "Save" and "Use server setting" buttons;
  - 422 messages shown inline;
  - `warnings` shown after save.
- Moderators see everything read-only, gated with `canWrite()` from `api.js`.
- The status refreshes every 30 s while the page is open.

- [ ] **Step 1: Build check.** `cd admin; npm run lint; npm run build`. Expected: success.

- [ ] **Step 2: Manual browser check against the stubbed server.**
  1. Start the stubbed backend.
  2. Start the admin panel: `$env:VITE_API_BASE_URL="http://127.0.0.1:8765"; npm run dev`.
  3. Log in with the suite's `admin` account.
  4. Save chat → Claude with "No backups", and confirm the source badge reads "Admin panel".
  5. Press Test on Claude with `set_fake_ai(claude="billing")` active, and confirm the card shows "failing" with a redacted error.
  6. Log in as `moderator` and confirm there are no Save or Test buttons.
  7. Check at 375 px width that nothing overflows.

- [ ] **Step 3: Commit.** `git commit -m "feat(admin): AI Providers page with status box and per-feature settings"`.

---

### Task 14: Flutter app stops choosing a provider

**Files:**
- Modify: `frontend/lib/models/chat.dart`. Remove the `AIProvider` enum and `ChatRequest.aiProvider` / `'ai_provider'`.
- Modify: `frontend/lib/providers/chat_provider.dart`, `frontend/lib/providers/insight_provider.dart`. Remove `_aiProvider`, `setAIProvider` and the provider defaults in `reset()`.
- Modify: `frontend/lib/services/api_service.dart`:
  - `streamChatMessage`: no `aiProvider` parameter.
  - `getInsights`, `regenerateInsights`, `deleteInsights`, `translateInsightsToMyanmar`, `refreshAiData`: no `ai_provider` query parameter.
- Modify: any screen or widget that still references `AIProvider`. Find them with a search for `AIProvider` and `aiProvider` under `frontend/lib`, and remove each reference.
- The assistant's display name is "Toe Pwar AI". Search the localisation for the current chat-assistant name and change it only if it names GPT or Gemini.

- [ ] **Step 1: Search.** `rg -n "AIProvider|aiProvider|ai_provider" frontend/lib frontend/test frontend/integration_test` lists every use.

- [ ] **Step 2: Remove them.** Run `cd frontend; flutter analyze`. Expected: no new issues compared with `main`.

- [ ] **Step 3: Unit tests.** Run `flutter test`. Expected: all pass, 84 or more.

- [ ] **Step 4: End-to-end tests.** Run `e2e\run_e2e.ps1 -Python PY -PgBin PGBIN`, then `-LargeText -Name "^14 Large text tour "`. Expected: 41 passed plus 2 passed, 0 failed. Chat and insights must now pass with the default Gemini route via the fake.

- [ ] **Step 5: Commit.** `git commit -m "feat(app): stop sending an AI provider; the server decides"`.

---

### Task 15: Full regression and deploy notes

**Files:**
- Modify: `docs/web-version.md` and `docs/postgres-migration-plan.md` ("Deploying on Render"). Add a short "AI providers" section that:
  - lists `ANTHROPIC_API_KEY` and `CLAUDE_MODEL`;
  - explains `AI_<FEATURE>_PROVIDER` / `_MODEL` / `_BACKUPS` (with `none`), with the feature keys;
  - says that the admin panel's AI page overrides them;
  - notes that the deploy runs a migration.

- [ ] **Step 1: Run the full backend suite.** Run `& "<scratchpad>\pg\run_suite.ps1"`. Expected: `problems (0)`, `crashes (0)`, with `test_ai_providers` included.

- [ ] **Step 2: Run the full Flutter end-to-end suite**, normal and large text, as in Task 14 Step 4.

- [ ] **Step 3: Check no secret material leaked into the code.** Run `rg -n "sk-[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{30,}|sk-ant-api" backend admin/src frontend/lib e2e`. Expected: no matches beyond the obvious fake test strings.

- [ ] **Step 4: Commit the docs.** `git commit -m "docs: AI provider settings for deploy"`.
