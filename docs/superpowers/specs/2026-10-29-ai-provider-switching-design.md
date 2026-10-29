# AI provider switching (OpenAI, Gemini, Claude): design

Status: draft for the owner's approval. Date: 2026-10-29.

## Intent and why

Toe Pwar's AI features are hard-wired today:

- AI chat and insights are built to support OpenAI or Gemini, but the app always sends Gemini.
- Every other AI feature is OpenAI only, with model names written into the code.

When a provider runs out of credit, has its key revoked, or goes down, the features on it break until someone changes code.

The owner wants three things:

1. **Add Claude** (Anthropic) as a third provider alongside OpenAI and Google Gemini.
2. **Decide, per AI feature, which provider and model it uses**, and change that at any time. Only the owner (admins) decides; app users never choose.
3. **Keep working when a provider fails.** If the chosen provider can't serve a request (no credit, bad key, outage, rate limit), the app quietly tries backup providers for that same request. The admin panel shows which provider is failing.

The trigger the owner named is running out of API credit at one provider.

## Goals

- One switchable setting per AI feature: main provider plus model, and an ordered list of backups, each with its own provider and model.
- The setting can come from the admin panel (takes effect immediately, no restart), or from server environment variables (Render or the VPS; takes effect on restart). Admin panel beats environment, and environment beats the built-in default.
- Automatic fallback to backups on provider-level failures, invisible to the app user.
- A status box on a new admin "AI" page: per provider, whether it is working, its last error, and how many requests went to a backup.
- AI usage and cost tracking that records the provider and model that actually answered, including Claude, and when a fallback happened.
- App users see no provider choice anywhere. The assistant is simply "Toe Pwar AI".

## Non-goals

- Per-user provider choice.
- E-mail, push or other alerts about failing providers. The owner chose the status box only.
- Switching the embeddings used for chat search (RAG). They stay on OpenAI `text-embedding-3-small`; see "Embeddings" below.
- Spending limits, budgets, or automatic switching based on price.
- Storing or showing API keys in the database or the admin panel.

## Anti-goals (would count as failure even if it "works")

- A bad request (for example a malformed prompt or an oversized input) being retried on every provider, burning credit on all three.
- An app user seeing an error while a configured, working backup could have answered.
- An API key, or any part of one, appearing in the admin panel, API responses, logs, or the status box.
- Breaking Android apps already installed on phones. Old apps send `ai_provider=gemini` or `ai_provider=openai` on chat and insights calls, and must keep working.
- Producing insights twice per user (once per provider) as the scheduled jobs do today. With one owner-chosen provider, generate once.

## The switchable features

Each feature gets a stable key, used in settings, environment variable names, and the admin page.

| Key | Feature (today's code) | Allowed providers | Built-in default (matches today) |
|---|---|---|---|
| `chat` | AI chat, streamed (`ai_chatbot.py`, `ai_chatbot_gemini.py`, `main.py` `/api/chat/stream`) | openai, gemini, claude | gemini `gemini-2.5-flash` |
| `insight_weekly` | weekly insight (`insights_service.py`) | openai, gemini, claude | gemini `gemini-2.5-flash` |
| `insight_monthly` | monthly insight | openai, gemini, claude | gemini `gemini-2.5-flash` |
| `insight_translation` | Myanmar translation of insights | openai, gemini, claude | gemini `gemini-2.5-pro` |
| `budget_suggestion` | AI budget suggestion (`budget_service.py`) | openai, gemini, claude | openai `gpt-4o-mini` |
| `budget_auto_create` | auto-created next-period budgets | openai, gemini, claude | openai `gpt-4o-mini` |
| `transaction_text` | transactions from typed text, single and multiple (`transaction_routes.py`) | openai, gemini, claude | openai `gpt-4o-mini` |
| `transaction_image` | transactions from a receipt photo (vision) | openai, gemini, claude | openai `gpt-4o` |
| `transaction_audio` | voice input, speech to text | openai, gemini (**not claude**) | openai `whisper-1` |

Notes:

- **Claude can't do audio.** Anthropic's model overview (checked 2026-10-29) states that current Claude models accept text and image input and produce text output. The admin page must not offer Claude for `transaction_audio`, and the backend must reject that setting.
- **Gemini voice transcription is new code.** Today voice is Whisper only. Gemini gets an audio-transcription path so that voice has a real backup.
- **Built-in defaults reproduce today's behaviour.** Deploying this change without touching any setting changes nothing for users. Chat and insights are on Gemini because the app sends Gemini today.
- **"No backups" is allowed** (owner's decision). A feature can be set to have no backups at all. If its provider then fails, the request fails as it does today and no credit is spent at another provider. "No backups" is different from "backups not set":
  - In the admin panel, it is an explicit choice next to the backup list.
  - In the environment, it is written `AI_<FEATURE>_BACKUPS=none`.
  - An unset or empty variable means the default backups.

  The feature settings table shows "No backups" clearly for such features.
- **Default backups.** When no backup list is set, the backups are the other providers that are allowed for the feature and configured (have a key), in the fixed order openai → gemini → claude, minus the main one. Each uses that provider's default model for the feature (see "Default models").

## Where a setting comes from

For each feature, the effective setting is resolved in this order. The first source that sets something wins.

1. **Admin panel.** Stored in the database. Each feature has a "use server setting" option that clears the panel override for that feature.
2. **Environment variables**, read at startup:
   - `AI_<FEATURE>_PROVIDER`, e.g. `AI_CHAT_PROVIDER=claude`
   - `AI_<FEATURE>_MODEL`, e.g. `AI_CHAT_MODEL=claude-sonnet-5-5`
   - `AI_<FEATURE>_BACKUPS`, an ordered comma list of `provider:model` (model optional), e.g. `openai:gpt-4o-mini,gemini`

   The feature name is the key from the table in upper case (`CHAT`, `INSIGHT_WEEKLY`, ...).
3. **Built-in default** from the table above.

**Default models per provider.** Used when a provider is named without a model:

| Provider | Variable | Default |
|---|---|---|
| openai | `OPENAI_MODEL` (exists today) | `gpt-4o-mini` |
| gemini | `GEMINI_MODEL` (exists today) | `gemini-2.5-flash` |
| claude | `CLAUDE_MODEL` (new) | **`claude-sonnet-5-5`**, the owner's choice |

There are two exceptions to these defaults:

- `transaction_image` on OpenAI defaults to `gpt-4o`.
- `transaction_audio` defaults to `whisper-1` on OpenAI, and on Gemini to the Gemini default model.

**Keys** stay in environment variables only:

- `OPENAI_API_KEY` (exists)
- `GOOGLE_API_KEY` (exists)
- `ANTHROPIC_API_KEY` (new)

A provider without a key counts as "not configured". It is skipped for fallback, and the admin page shows it as such. Choosing it as a main provider is allowed but shows a warning.

**A feature's setting resolves as one unit** (main provider, model and backups together), not field by field. *(Builder-check call.)*

- If the admin panel has a setting for a feature, the panel's main provider, model and backups are all used, and the environment is ignored for that feature.
- Otherwise, if `AI_<FEATURE>_PROVIDER` is set, the environment unit is used. A missing model means the provider's default model, and missing backups means the default backups.
- `AI_<FEATURE>_MODEL` or `AI_<FEATURE>_BACKUPS` without `AI_<FEATURE>_PROVIDER` is invalid. It is logged and ignored, so a model name is never paired with the wrong provider.
- The "where it comes from" column shows one source per feature.

**Invalid settings.** An invalid setting from any source (unknown provider, Claude for audio, malformed backups string) is logged and ignored, and resolution falls through to the next source. The admin API rejects invalid settings with a clear message rather than storing them.

**Taking effect immediately.** The backend runs as a single process. Settings are cached in memory and the cache is refreshed whenever the admin API changes a setting. A periodic re-read (about every 60 seconds) is a safety net in case of more than one worker.

## Fallback behaviour

A request for a feature walks its chain: the main provider, then each backup in order.

**What causes a move to the next provider.** Only failures that mean "this provider can't serve right now":

- authentication or permission errors (bad or revoked key);
- billing or quota errors: out of credit, `insufficient_quota`, HTTP 402. This includes Anthropic's "credit balance is too low" error, which arrives as a 400 with that message;
- rate limits (429, Gemini `RESOURCE_EXHAUSTED`);
- server errors and overload (5xx, Anthropic 529);
- timeouts and connection errors, after the SDK's own retries;
- model not found or not available for the key (misconfiguration);
- the provider not being configured;
- for Claude, a final `stop_reason: "refusal"` (see "Claude specifics");
- **an unusable answer**, even though the call succeeded. *(Builder-check call.)* Examples:
  - an empty reply;
  - a Gemini safety block or an empty candidate;
  - an OpenAI `content_filter` finish;
  - JSON for a budget or transaction feature that won't parse or fails validation;
  - JSON cut off at the token limit.

  The next provider is tried for this request, but an unusable answer does **not** mark the provider unhealthy. Insight translation keeps its own retry for cut-off replies before giving up on a provider.

**What does not cause a move.** Request-level errors that would fail on any provider, such as an invalid image, an input that is too large, or a malformed request. These fail the request as today, with no fallback. If the builder can't classify an error, the builder decides; prefer treating it as request-level to avoid the credit-burning anti-goal.

**Chat streaming.** Fallback is only allowed **before the first text chunk has been sent to the app**. Once chunks are flowing, a failure ends the reply with today's error frame. Text from two providers must never be stitched together.

**Cooling off.** A failure marks something unhealthy for a short time, and requests skip it while it is unhealthy. *(Builder-check call.)* What gets marked depends on the error:

- **The whole provider**, about 5 minutes, for errors that affect the whole key: auth, billing, provider not configured, and repeated server errors or outages.
- **Only that provider and model pair:**
  - about 5 minutes for model not found or not available;
  - about 60 seconds for rate limits, since these are counted per model.

  So a typo in one feature's model name, or a 429 on `gemini-2.5-pro` during translation, does not push every other feature off that provider.

The status box shows provider-level state on each card, and lists any models that are currently cooling off under that card.

**Scheduled insight jobs on rate limits.** *(Builder-check call, in line with the owner's concern about credit.)* No user is waiting on the scheduled weekly and monthly insight jobs. On a rate limit (429) they **back off and retry the same provider** a few times before falling back. They fall back immediately only on hard failures: billing, auth, model not found, or the provider being down after retries. This stops a burst of 429s from moving a whole batch onto a costlier backup. User-facing requests, including manually regenerating an insight, follow the normal immediate-fallback rule.

If every provider in a chain is unhealthy, the chain still tries them in order rather than failing without trying. Health is kept in memory; it resets on restart, which is acceptable.

**Insights jobs and placeholders.** Today's behaviour stays: when AI is down, a stored or placeholder insight is returned rather than a 5xx. This only applies when the whole chain fails.

## Status box and usage tracking

**New admin "AI" page** (sidebar entry), with two parts.

**1. Providers status box.** One card each for OpenAI, Gemini and Claude:

- configured or not (from key presence only; never show the key);
- status:
  - **working**: last call succeeded;
  - **failing**: last call failed with a provider-level error;
  - **cooling off until hh:mm**: currently marked unhealthy;
  - **unused**: no calls since start;
- last error: a short, safe message (error type and provider message, with anything key-like stripped) and its time;
- last success time;
- requests answered by a backup because this provider failed, in the last 24 hours.

A **"Test" button** per configured provider sends one tiny request to check the key and model. It spends a negligible amount of credit, and the button says so.

**2. Feature settings table.** One row per feature:

- main provider and model;
- ordered backups, each with provider and model; add, remove and reorder;
- where the effective setting comes from: admin panel, server setting, or built-in;
- a "use server setting" action.

Model pickers offer a list of known current models for that provider, plus "type a model name" for models released later. Providers not allowed for a feature (Claude on audio) are not offered.

Status needs to survive restarts for the "last error" and 24-hour counts:

- persist per-provider last error, last error time and last success time in a small table (or equivalent);
- derive the 24-hour backup counts from usage records (below).

**Usage tracking changes:**

- Add `claude` as a provider everywhere one is enumerated:
  - `AIProviderType`
  - `chat_models.AIProvider`
  - the `insights.ai_provider` CHECK constraint (Alembic migration)
  - the pricing table
- Add Claude pricing for at least `claude-sonnet-5-5` ($2 input / $10 output per 1M tokens), `claude-haiku-5-5` ($0.10 / $0.50) and `claude-opus-5-5` ($4 / $20).
- Each usage record stores the provider and model that **actually answered**, plus a new nullable `fallback_from` holding the provider that failed first when a fallback happened.
- Calls that fail on every provider still record nothing, as today.
- Cost totals per provider become generic (one per provider) instead of the hard-coded `openai_cost` / `gemini_cost` fields. This applies to the stats queries, the response models and `AIUsageStats.jsx`.

## Feature-by-feature behaviour changes

**Chat**

- One chatbot with interchangeable provider back ends replaces the two near-duplicate classes. It keeps the shared pieces: the RAG retrieval, the prompt building, the history handling (last 4 messages) and the streaming contract (`chunk` / `done` / `error` frames).
- The persona is "Toe Pwar AI" for every provider.
- The request's `ai_provider` field is accepted and **ignored**, so old apps keep working. An invalid value is still rejected by validation, as today; the test for `"bard"` keeps passing.

**Insights**

- Generated **once** per user and period with the insight feature's chain. The scheduled jobs and the manual `generate-weekly` route stop looping over both providers.
- `insights.ai_provider` records which provider actually generated the insight.
- Reads return the latest insight **regardless of provider**. The `ai_provider` query parameter on the insights routes is accepted and ignored.
- Existing rows for both providers stay. Readers take the newest across them.
- Translation keeps today's truncation handling (detect a cut-off reply, then retry by section) for every provider. For Claude, the cut-off signal is `stop_reason: "max_tokens"`.

**Budgets and transaction extraction**

- They read their provider and model from the feature setting instead of hard-coded `gpt-4o-mini` / `gpt-4o` / `whisper-1`.
- They keep producing the same JSON as today, whichever provider answers.
- Existing non-AI fallbacks stay as they are: basic budget suggestions when there is no key or data, and adjusted budgets when auto-create fails.

**Embeddings**

- They stay on OpenAI.
- If OpenAI is out of credit, building the chat search index fails. Chat then already falls back to its JSON summary of the user's data and still answers, just with less detail. This is accepted for now.

## Claude specifics

- Use the official `anthropic` Python SDK (new pinned dependency), async client. Keep Claude code in its own module, separate from the OpenAI and Gemini code.
- Default model `claude-sonnet-5-5`.
- **Do not send `temperature`, `top_p` or `top_k` to Claude.** Since 2026-10-21 these return a 400 on every Claude model. Today's OpenAI and Gemini calls set temperature; the Claude adapter must not.
- Sonnet 5.5 thinks by default. Use `output_config.effort` to control cost and speed:
  - start at `low` for chat and extraction;
  - start at `medium` for insights and translation;
  - adjust after measuring.

  `max_tokens` must leave room for thinking. Today's 1000-token chat limit is too low for Claude; the builder sets suitable limits.
- **JSON features:** use Claude structured outputs (`output_config.format` with a JSON schema) for the budget and transaction features.
- **Receipt photo:** send it as a base64 image content block.
- **Refusals:** on Claude Sonnet 5.5, enable Anthropic's server-side refusal fallback (`fallbacks: "default"`, beta `server-side-fallback-2026-07-01`). If the final response still has `stop_reason: "refusal"`, treat it as a failure for this request and try the next provider in the chain. A refusal does not mark Claude unhealthy.
- **Chat:** stream with the SDK's streaming API so the first chunk arrives quickly.
- Read token usage from the response for cost tracking.

## The app (Flutter, phone and web)

- Remove the provider choice from the app's code: the `AIProvider` enum use in chat and insights, `setAIProvider`, and the `ai_provider` request parameter. There is no picker on any screen today, so nothing visible is removed.
- The app stops sending `ai_provider`; the backend ignores it from old apps.
- Wherever the app names the assistant, it says "Toe Pwar AI".

## Admin roles

- Moderators and above can **view** the AI page.
- Admins and super admins can **change** settings and press "Test". This follows the `app_versions` precedent: create and update require admin or super admin.
- Every settings change is written to `admin_action_logs`.

## Testing

**Backend suite** (`e2e/`):

- **Fake Claude.** Add a fake Claude client in `stubenv.py`, patched before import like the OpenAI one, with the same `E2E_FAKE_AI` switch. Make each fake provider able to simulate failures (billing, auth, 429, 5xx, timeout, refusal) on demand, so fallback can be tested.
- **New checks:**
  - setting precedence: panel, then environment, then built-in, plus "use server setting";
  - invalid settings are rejected, including Claude for audio;
  - fallback on each provider-level error type;
  - **no** fallback on request-level errors;
  - the chat rule: fallback before the first chunk, none after;
  - cooling off;
  - the status box API (data, permissions, no key material in responses);
  - usage records with `fallback_from`;
  - old-app compatibility: `ai_provider` sent and ignored;
  - insights jobs generate once per user.
- **Existing tests to update.** Several expect today's behaviour:
  - Gemini chat yields an error frame;
  - jobs run both providers;
  - seeds insert insights for both providers.

  Update them to the new behaviour; don't delete them.

**Flutter end-to-end suite:** must still pass, including the large-text tours.

**Real providers:** a short manual check against the real providers, with the owner's keys on the live server, after deploy.

## Constraints

- One backend process, as today, because the scheduler runs in-process. In-memory caches and health are acceptable.
- PostgreSQL with Alembic. Every schema change ships as a migration that runs on deploy (`alembic upgrade head`).
- Runs on Render now and may move to a VPS. Configuration through environment variables must work on both.
- Old Android apps in the field must keep working (see the anti-goals).

## Left to the builder

- Module layout. For example, one provider interface with OpenAI, Gemini and Claude implementations, plus a "run with fallback" helper.
- Exact error classification per SDK, within the rules above.
- Prompt wording adjustments per provider, as long as outputs keep today's shape.
- Exact effort levels and token limits for Claude, after measuring.
- The known-model lists shown in the admin pickers.
- The storage shape for panel settings and provider status. A table is expected.
- The admin page layout, within the content listed above.
