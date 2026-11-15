# Books table: code map (2026-11-15)

This is a read-only survey of the code at main 4d7dad1 / fbbf0da, made to plan `2026-11-15-books-table.md`. Line numbers are approximate once tasks start changing files; search by function name.

## 1. SQL helpers keyed by the data owner (`user_id` → `book_id`)

Inserts take a `doc` whose owner key becomes `book_id`.

**transactions.py**
- insert_transaction(doc), insert_many(docs)
- update_transaction(transaction_id, user_id, fields)
- disable_recurrence(transaction_id, user_id=None)
- delete_transaction(transaction_id, user_id)
- get_transaction(transaction_id, user_id=None)
- `_filtered`, used by:
  - find_transactions(user_id, *, type_, currency, date_from, date_to, date_before, skip, limit, include_transfers)
  - currency_totals(user_id, *, ...)
  - category_totals(user_id, *, ...)
- child_exists_between(user_id, parent_id, start, end)
- has_transactions_between(user_id, start, end)
- changed_since(user_id, start, end, since)
- currencies(user_id)
- count_transactions(user_id=None)
- latest_created_at(user_id)
- active_user_ids(since): it joins users.kind = 'person'.
- No owner filter: delete_transfer, transfer_legs, recurring_parents, set_recurrence_pointer.

**budgets.py**
- get_budget(budget_id, user_id=None)
- list_budgets(user_id, *, currency, period)
- budgets_overlapping(user_id, start, end, currency=None)
- created_since(user_id, start, end, since)
- has_budget_containing(user_id, moment)
- count_budgets(user_id=None)
- find_child(user_id, parent_id)
- find_existing_next(user_id, parent_id, name, period, currency, day_start, day_end)
- insert_budget(doc)
- update_budget(budget_id, fields, *, user_id=None, expected_updated_at)
- delete_budget(budget_id, user_id)
- Selected by budget rather than owner: rollover_candidates, ending_soon_candidates, now_active_candidates.

**goals.py**
- insert_goal(doc)
- get_goal(goal_id, user_id=None)
- list_goals(user_id=None, *, status, currency, target_between)
- changed_since(user_id, since)
- delete_goal(goal_id, user_id)
- count_goals(user_id=None)
- user_has_goals(user_id)
- allocated_by_currency(user_id)

**insights.py**
- insert_insight(doc)
- latest(user_id, insight_type, real_only, ai_provider)
- delete_for_user(user_id, ai_provider, insight_type)

**custom_insights.py**
- insert_pending(doc): its conflict target is the partial unique index on `user_id` where status = 'pending' (`uq_custom_insights_pending_user`).
- get(report_id, user_id=None, include_deleted)
- list_summaries(user_id, limit, before)
- has_pending(user_id)
- find_ready_match(user_id, start_date, end_date, instruction_key)
- count_attempts_since(user_id, since)
- delete_for_user(report_id, user_id, now)
- No owner filter: finish, fail_stuck, set_translation.

**chat.py**
- Already keyed by person plus `book_id` (NULL = personal): `_of(user_id, book_id)`, append_exchange(user_id, messages, keep_last, now, book_id=None), history(user_id, limit, book_id=None), clear(user_id, book_id=None).
- latest_activity(user_id), count_sessions(user_id=None)
- active_user_ids(since): it joins users.kind = 'person'.

**ai_usage.py**
- insert_usage(doc)
- user_cost_since(user_id, since)
- overall_stats(start, end): `unique_users` counts persons only.
- per_user_stats(...): joins users, plus families.book_user_id and family_members; `_family_label` relabels book users.
- user_detail(user_id, feature_type, limit)
- feature_stats(features, start, end): `array_agg(distinct user_id)`.
- backup_answer_counts(since)

**notifications.py**
- list_for_user, mark_read, mark_all_read, delete_notification, unread_count: keyed by the recipient person; these stay.
- `_owner(user_id | iterable)`
- exists(user_id|ids, types, *, goal_id, goal_name, currency, since, no_goal_id)
- approaching_reminder_exists(user_id|ids, goal_id, threshold, target_key, since)
- insert_notification(doc), insert_many(docs): `_row` drops unknown keys.

**users.py**
- IS_PERSON, used by count_users / user_ids / list_fields / admin_list
- get_person, is_book_user, create_book_user
- claim_ai_data_fresh, mark_ai_data_stale
- money_lock (FOR UPDATE on the users row), lock_user

**families.py**
- outflow_shares(book_user_id, ...) and transfer_totals(book_user_id, ...): filter transactions.user_id.
- insert_family(family_id, name, book_user_id), family_for_book(book_user_id), books_with_paid_owner(plans), account_user_ids_for_book(book_user_id), active_member_user_id(book_user_id, member_id), owner_user(family_id).

## 2. Callers (the data id today is `book.id` unless flagged)

**transaction_routes.py**
- Writes `"user_id": book.id`.
- Reads and writes transactions; get_user_money_lock(book.id).
- `_ensure_goal_allocations_covered` → get_user_balance.
- check_large_transaction(user_id=book.id).
- update_relevant_budgets(book.id), update_all_user_budgets(book.id), mark_ai_data_stale(book.id), disable_recurrence_for_*(…, book.id).
- AI usage under `current_user["_id"]` (the person, intended): `_run_ai` / `_log_ai_usage`.

**goal_routes.py**
- `"user_id": book.id`.
- get_user_money_lock(book.id), get_user_balance(book.id), mark_ai_data_stale(book.id), check_goal_notifications / check_milestone_amount(user_id=book.id).

**budget_routes.py**
- `"user_id": book.id`; update_budget_spent_amounts(book.id); notify_budget_started(user_id=book.id); mark_ai_data_stale(book.id).
- BudgetAnalyzer(book.id, ..., ai_user_id=current_user["_id"]).
- FLAG: `book.person.get("default_currency")` (~:317).

**main.py**
- get_user_balance(book.id).
- Chat: `data_id = book.id`, claim_ai_data_fresh(data_id), `_invalidate_ai_caches(data_id)`, stream_chat(user_id=data_id, person_id=user_id), chat_db.history/clear(book.person["_id"], book_id), `_chat_book_id(book)` (family → book.id, personal → None).
- Insights:
  - `_generate_insight`.
  - FLAG: `_generate_counted(user, type, data_id=None)` uses `data_id or user["_id"]`.
  - FLAG: `_free_monthly_insight` uses `data_id or user["_id"]`.
  - latest_valid_insight(book.id), insights_db.delete_for_user(book.id, ...).
  - `_ensure_myanmar_translation` records `cost_user_id or user["_id"]`.
  - Owner cap: `quota.require_under_cost_cap(owner, ..., book_user_id=book.id)`.
- analyze_unusual_spending(book.id).
- Notification routes: recipient person; `NotificationResponse(goal_id=..., extra={"book": ...})`.

**custom_insight_routes.py**
- `uid = book.id`; compute_figures, find_ready_match, has_pending, count_attempts_since, insert_pending, list_summaries, get, delete_for_user; changed_since and created_since on uid.
- `cis.counter_keys(reservation, uid)` adds the asking person as a 4th item when it differs from the row owner.
- Translate uses `user_id=current_user["_id"]`.

**custom_insights_service.py**
- compute_figures(user_id).
- run_report: `uid = row["user_id"]`; `_insight_profile` → users_db.get_user(uid); list_goals(uid), budgets_overlapping(uid).
- `run_insight_model(..., _asker(row))`; `_asker` returns the person from counter_keys[3], else row["user_id"]; `_give_back` / `_reservation` use the person.

**insights_service.py**
- `_job_targets`, `_skip_user(user, feature, book_user_id)`.
- `_insight_profile`: `kind == "family_book"`, family_for_book, owner_user.
- latest_valid_insight, `_latest_real_insight`, user_has_insight_data.
- generate_weekly_insight(user_id): users_db.get_user, FinancialDataProcessor, get_financial_summary (currency_totals / category_totals), insert_insight with "user_id".
- generate_monthly_insight (same shape).
- run_insight_model(user_id) → `_runner.run(feature, user_id=...)`; translate_insight_to_myanmar(user_id=...); notify_weekly/monthly_insights_generated(user_id).

**budget_service.py**
- BudgetAnalyzer(user_id, language, ai_user_id): find_transactions, list_goals; AI usage under ai_user_id.
- get_running_budgets, update_budget_spent_amounts (category_totals; check_budget_notifications(user_id=...)), refresh_budget_state_if_stale (`budget["user_id"]`), `_find_child_budget`, process_due_budget_rollovers (`budget["user_id"]`), update_relevant_budgets, update_budgets_in_range.
- auto_create_next_budget(budget): `user_id = budget["user_id"]`, BudgetAnalyzer, find_existing_next, insert_budget, notify_budget_auto_created.
- `_owner_gets_ai_budgets(user_id)`: users_db.get_user. For a family book user this reads a fake Free plan (the bug), and quota.over_cost_cap reads the book user.
- `_ai_category_budgets`: `_runner.run("budget_auto_create", user_id=user_id)`, so the cost is recorded under the data id.
- update_all_user_budgets(user_id).

**recurring_transaction_service.py**
- Driven by transactions: `transaction["user_id"]`.
- `_notice_recipient`: is_book_user, active_member_user_id.
- `_refresh_user_after_recurring(user_id, ...)`: mark_ai_data_stale, update_budgets_in_range.
- disable_recurrence_for_transaction / for_parent(…, user_id).

**families/transfers.py**
- `_refresh(leg["user_id"])`.
- FLAG: these use the person id as the personal data id:
  - `source = person["_id"] if to_family else book.id`
  - `leg(person["_id"], ...)`
  - `get_users_money_locks((person["_id"], book.id))`
  - mark_ai_data_stale for (person, book) and for each leg
  - leg matching `x["user_id"] == person["_id"]`
- get_user_balance(source); `_check_destination` get_user_balance(inflow["user_id"]).

**families/breakdown.py**: `fdb.outflow_shares(family["book_user_id"], ...)`.

**families/service.py**: create_book_user + insert_family in create_family; `users_db.delete_user(family["book_user_id"])` on family delete and in the owner's account deletion; `_notify` skips non-person users.

**report_routes.py**: currency_totals / category_totals / list_goals / find_transactions(book.id). FLAG: `book.person.get("default_currency")`.

**ai_chatbot.py**: FinancialDataProcessor(user_id), with find_transactions, list_goals, get_running_budgets, currency_totals and category_totals; get_family_context (family_for_book(self.user_id), transfer_totals, list_members); the vector cache keyed by data id; stream_chat(user_id=data id, person_id=asker), whose AI usage is under person_id.

**utils.py**: get_user_balance (users_db.get_user for default_currency, currency_totals, allocated_by_currency); get_current_user rejects non-person.

**admin_routes.py**
- FLAG: per-user counts use the person id as the data id (user list ~563-568, user detail ~613-620).
- active_user_ids; totals count_transactions() / count_goals(); delete user (before_account_delete, then delete_user).

## 3. Book-user specifics

- **book_user_id:** families sql, ai_usage.py (join), tables.py, book.py, breakdown.py, service.py, main.py (cost cap), plans/quota.py (`_at_cost_cap`, family_over_cost_cap, require_under_cost_cap), insights_service.py (`_skip_user`, `_job_targets`, notices), ai_chatbot.py, e2e test_family.py.
- **kind filters:** users.py (IS_PERSON), ai_usage.py, chat.py, families.py (books_with_paid_owner), transactions.py (active_user_ids), auth_routes.py (login lookup), utils.py, insights_service.py, families/service.py.
- **is_book_user:** notification_service.py (create_notification refusal, notification_recipients, unusual-spending / recurring-payment skips), recurring_transaction_service.py.
- **create_book_user:** families/service.py only (email `family-{id}@book.invalid`, random password, free, en).
- **Book.personal:** book.py; e2e plans_custom_insight_checks.py and test_ai_providers.py.

## 4. Money locks

- `sql/users.py` money_lock(user_id): `transaction()`, then `SELECT users.id ... FOR UPDATE`.
- `utils.py`: `_user_money_locks` is a WeakValueDictionary of asyncio.Lock. get_user_money_lock takes the process lock, then the row lock.
- get_users_money_locks: sorted and deduped ids; all process locks, then one transaction, then the row locks in order.
- users_db.lock_user is a separate lock used by before_account_delete.
- Callers: goal_routes, transaction_routes, transfers, e2e/test_money_lock.py.

## 5. ai_data_stale

- **Column:** users.ai_data_stale.
- **SQL:** users.claim_ai_data_fresh / mark_ai_data_stale.
- **Claimed:** main.py chat stream (claim, then `_invalidate_ai_caches`).
- **Marked by:** budget_routes, goal_routes, transaction_routes, families/transfers.py, recurring_transaction_service.
- **e2e:** test_family.py reads and resets it.

## 6. Jobs (all registered in scheduler.py)

| Job | Selection |
|---|---|
| Weekly / monthly insights | `_job_targets`: paid persons (`users_db.list_fields`), plus `families_db.books_with_paid_owner` |
| Unusual spending | `users_db.user_ids()`, then `analyze_unusual_spending(user_id)` |
| Recurring payment reminders | `users_db.user_ids()` |
| Recurring transactions | `transactions_db.recurring_parents()`, grouped by transaction owner |
| Budget rollover | `budgets_db.rollover_candidates` (`budget["user_id"]`) |
| Budget period notices | ending_soon / now_active candidates; recipients `notification_recipients(budget["user_id"])` |
| Goal reminders | `list_goals(status="active", target_between)`; `notification_recipients(goal["user_id"])` |
| Plan expiry, trial and renewal reminders | `users_db.list_fields` on users |
| Custom insight sweeper | `ci.fail_stuck` |
| Admin broadcast | `users_db.list_fields(["fcm_token"], ...)` |

## 7. Notifications

- **Writers:** everything goes through notification_service.create_notification; create_notification_from_key fans out for a family book (`notification_recipients`, `family_marker` / FAMILY_MARKER).
- **Push data:** notification_id, type, goal_id (`""` if none), goal_name, currency, and `book` when set.
- **type → goal_id meaning:**
  - goal id: goal_progress, goal_achieved, goal_milestone, goal_approaching_date
  - budget id: budget_threshold, budget_exceeded, budget_ending_soon, budget_now_active, budget_started, budget_auto_created
  - transaction id: large_transaction, recurring_transaction_created (the newest child), recurring_transaction_ended (the parent), recurring_transaction_disabled (the parent)
  - nothing: unusual_spending, payment_reminder
  - nothing (personal) or the book user id (family): weekly/monthly_insights_generated. Dedupe uses goal_id=book for family and no_goal_id for personal.
  - report id: custom_insight_ready, custom_insight_failed
  - invite id: family_invite
  - family id: family_invite_accepted, family_removed, family_owner
  - nothing: the subscription and plan types, upgrade_request_declined, admin broadcasts
- **Dedupe readers:** sql/notifications.exists / approaching_reminder_exists, and their notification_service callers.

## 8. ai_usage: who is recorded today

| Feature | Recorded under |
|---|---|
| chat, chat_advanced | the person |
| insight_weekly / insight_monthly | the data id (person for personal, book user for family) |
| insight_translation | the person (personal) or the book (family, `cost_user_id`); custom insight translation: the person |
| insight_custom | the asking person |
| budget_suggestion | the person |
| budget_auto_create | the data id (book user for family) |
| transaction_text / image / audio | the person |

- **The only insert site:** ai_usage_service.track_ai_usage, called from ai_providers/runner.py.
- **Cost cap:** plans/quota.py `month_spend` + `user_cost_since(book_user_id)` for family books.
- **Admin:** /api/admin/ai-usage/stats, /users, /user/{user_id}, /stats/budgets, /stats/transactions. admin/src/AIUsageStats.jsx keys rows by `user.user_id` and opens `/api/admin/ai-usage/user/${id}`.

## 9. API models exposing user_id

- models.TransactionResponse, budget_models.BudgetResponse, goal_models.GoalResponse, insight_models.InsightResponse: these carry the data owner.
- notification_models.NotificationResponse: the recipient person.
- chat_models.ChatSession.user_id.
- ai_usage_models (AIUsageCreate, AIUsageResponse, UserAIUsageStats).
- The custom insights API returns no user_id.

## 10. Inserts into users

- App code: auth_routes.register → users_db.insert_user (the only one); users_db.create_book_user (from create_family).
- e2e direct inserts:
  - raw `INSERT INTO users`: test_ai_providers.py, test_plans.py, test_family.py (a family_book row);
  - Core inserts: test_ai_providers.py;
  - `users_db.insert_user`: test_money_lock.py;
  - `create_book_user`: test_family.py.
- seed_rich.py uses the API for users.

## 11. Alembic

- Head is `522ad619de76` (notification_book), down `f3a9c1d7b5e2` (family_book).
- Earlier chain: 799d29a14d00 → a3f1c7d92b64 → c4e8b1a05d37 → e1b6d3a8f245 → f2c9a47e5b18 → a7d3e5c91f20 → b8f4d2c6e9a1 → d6b2e8f4a1c7 → a9c4f1e7b352 → e5b7c3a9d2f6 → f3a9c1d7b5e2 → 522ad619de76.
- e2e/plans_subscription_checks.py reads the head from the scripts (`head_revision()`). It also downgrades to older revisions and back, through this migration, on a populated DB.

## 12. e2e direct DB access

- **pgcompat.py:** a pymongo-style adapter. `TABLES` lists most tables, but not custom_insights, chat_messages or budget_allocations. It uses `sql.docs` mappers; `reset_postgres` truncates everything but plan_limits and plan_settings.
- **dbtweak.py:** `insights.insert_one` with user_id.
- **Heavy raw-SQL users of the book tables:**
  - test_family.py: ~45 lines, plus ai_data_stale, families and book_user_id.
  - plans_custom_insight_checks.py: ~24.
  - test_ai_providers.py: raw SQL plus ~20 Core lines on ai_usage.c.user_id.
  - plans_insight_checks.py, plans_quota_checks.py, plans_entry_checks.py, plans_subscription_checks.py, plans_chat_checks.py, plans_upgrade_request_checks.py.
  - test_api.py: includes a count loop over book tables by user_id.
  - Also test_regressions_all.py, test_round3.py, test_jobs.py, test_backend_r4.py, test_sweep.py, test_plan_expiry.py, test_regressions2.py, test_regressions3.py, test_round5.py, test_jobs2.py, test_load.py and seed_rich.py.
- **Notification goal_id assertions:** plans_custom_insight_checks.py, test_family.py (including the push `data.goal_id`), test_regressions3.py.
