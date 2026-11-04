# Custom insights for Pro — design

## Intent
Weekly and monthly insights answer "how am I doing lately". Pro users also want to ask about a stretch of time they choose ("Thingyan week", "the three months since I changed jobs", "this year so far") and, optionally, a question about it ("where can I cut spending?"). Custom insights give Pro a clear, premium reason to exist next to Advanced chat: chat is a conversation that scrolls away; a custom insight is a saved, structured report about a chosen period.

## Goals
- A Pro user picks a date range, optionally gives a short instruction, and gets a saved report about their own money in that range.
- Reports look like the insights users already know and stay readable whatever the instruction.
- Cost stays predictable for the owner.

## Non-goals
- No change to weekly/monthly insights or their schedule.
- No chat-style follow-up questions on a report.
- No custom insights for Free or Plus (they see it locked, with an Upgrade path).

## Anti-goals
- Becoming a free general-purpose AI (homework, essays): off-topic instructions are refused.
- AI-invented figures: the key numbers must always be correct.
- A user losing an allowance to a failure: failed or refused reports never count.

## Owner's decisions
- **Who:** Pro only. Free and Plus see the feature locked with an Upgrade button.
- **Input:** a date range plus an optional instruction of at most 300 characters, or one of the ready-made instructions: "Where can I save?", "Compare with the previous period", "Biggest changes", "Check my budgets and goals". No instruction → the usual full insight for that range.
- **Range:** 7 days to 12 months.
- **Allowance:** 10 per month for Pro, editable on the admin Plans page like every other limit, separate from Advanced chat. The plan's monthly AI cost cap still applies.
- **Finance only:** the AI answers only about the user's own finances in that range; an off-topic instruction gets a polite refusal and is not counted.
- **Background:** generation runs in the background; the user gets a notification when it is ready.
- **Saved:** past custom insights are kept in a list (range, instruction, when made), each with the English / မြန်မာ toggle. Asking for the exact same range and instruction again shows the saved report instead of using another one.
- **Model:** the Advanced model (Claude) by default; the admin can change provider and model for custom insights on the AI Providers page.
- **Format:** Markdown with a fixed outline — **Summary**, **What I found**, **What to do next** — headings, bullets and bold only, no tables, with a length limit. Key figures for the period are computed by the app from the user's data and shown as cards above the AI text.

## How it fits the existing system
- **Plans:** a new quota feature `insight_custom` (Free locked, Plus locked, Pro counted 10 per month), seeded by migration into `plan_limits`, enforced through the existing `plans/quota` reserve → commit / release flow and the cost cap, and shown on the admin Plans page and in the app's plan comparison and usage lines.
- **AI providers:** a new AI feature `insight_custom` (all providers allowed; default Claude `claude-sonnet-5-5`, the Advanced chat default) with its own usage type, so it appears on the AI Providers page and in AI usage stats.
- **Translation:** Myanmar uses the existing insight translation path (`insight_translation`, included for Pro), on demand from the toggle, stored with the report.
- **Notifications:** a new type for "ready" (tap opens the report) and one for "couldn't create it" (says it was not counted).

## Claude's calls (builder may refine)
- **Storage:** a new table for custom insights rather than reusing `insights`: range (start and end dates, inclusive, in the app timezone), instruction (or preset key), status (`pending`, `ready`, `failed`, `refused`), English content, Myanmar content, the computed figures snapshot, provider/model/tokens, created and completed times. Deleted with the user. Users can delete their own reports; reports are otherwise kept.
- **Figures:** for each currency the user has in the range: income, spending, net, top spending categories, and the change versus the previous period of equal length. The same figures go into the AI's context so text and cards agree.
- **AI context:** the range's financial summary and the previous equal period's, plus budgets and goals active in the range, reusing the existing insight summary code where possible.
- **Off-topic detection:** the prompt tells the model to answer with a fixed marker when the instruction is not about the user's finances; the server turns that into `refused`, releases the use, and shows "That isn't something I can answer from your finances" in the list.
- **One at a time:** a user can have at most one `pending` report; a second request while one is pending is refused with a clear message.
- **Same request again:** reuse a `ready` report with the same range and the same instruction (compared after trimming and ignoring case) when no transaction in the range was created or edited after the report was made; otherwise generate a new one.
- **Stuck jobs:** a report still `pending` well past the insight timeout (for example 15 minutes) is marked `failed` and its use is given back, so a server restart mid-generation never costs the user.
- **App:** a third tab on the Insights screen, "Custom", next to Weekly and Monthly. For Pro: a "New custom insight" button opening a form (quick ranges such as last 30 days / last 3 months / this year so far, plus a date-range picker; the instruction field with the ready-made instructions as chips; "8 of 10 left this month"), and the list of past reports with their status. Opening a report shows the figure cards, the Markdown text, and the language toggle. For Free and Plus: a locked state with Upgrade.
- **Format safety in the app:** if the model still produces a table or other disallowed Markdown, the app shows it as plain text rather than a broken layout.
- **Gating follows the plan limits:** "Pro only" is the default in `plan_limits`, not a hard-coded check. If the owner sets `insight_custom` to counted or included for Plus on the Plans page, Plus gets it; no new validation rule forces it locked.
- **One outline for every custom insight:** the fixed Summary / What I found / What to do next outline is used with and without an instruction (one prompt). "Look like the insights users know" means the same Markdown look and screen style, not the weekly/monthly prompts' long section list.
- **After a plan change:** only creating a report is gated. A user who is no longer allowed to create keeps their list and can open and delete past reports. The Myanmar toggle shows a stored translation if one exists; a new translation follows the user's current `insight_translation` access (locked → shown locked with Upgrade, as on the Insights screen). A report already `pending` when the plan changes is finished. Free and Plus users with no past reports see only the locked state; with past reports they see the locked "New custom insight" plus their list.
- **Attempts that don't count:** refused and failed attempts never use the allowance, but a user can make at most 5 of them per day; after that, new requests are refused until the next day with a clear message. The cost cap still applies on top.

## Left to the builder
Exact API paths and payloads, the prompt wording, the migration layout, the length limit and max tokens, how the background work is run in this codebase, the form and list layout, and the EN/MM strings (the owner's Myanmar wording should be checked by a native speaker).
