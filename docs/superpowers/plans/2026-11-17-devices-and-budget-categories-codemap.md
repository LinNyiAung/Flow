# Code map: devices and budget categories (2026-11-17)

Read-only map for the plan. Paths are relative to `C:\projects\Flow`. Line numbers are as of branch `devices-and-categories` (clean tree, HEAD `ae43938`).
Design: `docs/superpowers/specs/2026-11-17-devices-and-budget-categories-design.md`.

---

## 1. Budget categories, backend

### 1.1 Table, migrations, doc mapping
- `backend/sql/tables.py:267-278` `budget_allocations = Table(...)`. PK `(budget_id, position)`; columns `main_category Text NOT NULL` (comment at :271 says `"Main" or "Main - Sub"`), `allocated_amount`, `spent_amount`, `percentage_used`, `is_exceeded`; CHECK `amounts_finite`. **Needs:** comment fixed, new `Column("sub_category", Text)` (nullable).
- Alembic head today: **`d846defddc6e`** (`backend/alembic/versions/20261115_d846defddc6e_books.py`, `down_revision = '522ad619de76'`). Chain tail: `...f3a9c1d7b5e2` -> `522ad619de76` -> `d846defddc6e`.
- Naming: `backend/alembic.ini:6` `file_template = %(year)d%(month).2d%(day).2d_%(rev)s_%(slug)s` -> `20261117_<12hex>_<slug>.py`. File header = docstring with `Revision ID` / `Revises` / `Create Date`, then `revision: str`, `down_revision: Union[str, None]`, `branch_labels`, `depends_on`, `upgrade()`, `downgrade()` (see `20261114_522ad619de76_notification_book.py`). Constraint names use `op.f('ck_<table>_<name>')`.
- `backend/sql/docs.py:98` `budget_doc(row, allocations)`: builds `category_budgets` list; entries at :104-110 hold `main_category, allocated_amount, spent_amount, percentage_used, is_exceeded` (sorted by `position`). **Needs:** add `"sub_category": a["sub_category"]`.
- `backend/sql/docs.py:125` `allocation_rows(budget_id, category_budgets)`: accepts pydantic models (`model_dump`) or dicts; builds insert rows at :129-137 (`cat["main_category"]` at :132). **Needs:** `"sub_category": cat.get("sub_category") or None` (use `.get`: many in-process docs/fixtures have no `sub_category` key; blank -> None).
- `backend/sql/budgets.py` (the only allocation reader/writer; imports `allocation_rows, budget_doc, budget_row` :13, table alias `a` :14):
  - `_docs(rows)` :26 -> `select(a)` for all allocations, `budget_doc`; reads `select(a)` so a new column flows through automatically.
  - `insert_budget(doc)` :132 -> `insert(a), allocations` (:140); `update_budget(budget_id, fields, ...)` :143 pops `category_budgets` (:149), deletes all allocation rows then re-inserts via `allocation_rows` (:161-164). No column list to change; only `allocation_rows` / `budget_doc`.
  - Read funcs that return docs with allocations: `get_budget` :41, `list_budgets` :53, `budgets_overlapping` :64, `rollover_candidates` :111, `ending_soon_candidates` :117, `now_active_candidates` :124.

### 1.2 Models
- `backend/budget_models.py:32` `class CategoryBudget(BaseModel)`: `main_category: str; allocated_amount: float; spent_amount=0.0; percentage_used=0.0; is_exceeded=False`. **Needs:** `sub_category: Optional[str] = None`.
- `:40` `class CategoryBudgetIn(CategoryBudget)`: `allocated_amount: NonNegativeAmount`. **Needs:** validator (on the `In` class so stored/legacy reads stay lenient): `main_category` containing `" - "` -> 422; blank `sub_category` -> None.
- Nested in: `BudgetCreate.category_budgets: List[CategoryBudgetIn]` :49; `BudgetUpdate.category_budgets: Optional[List[CategoryBudgetIn]]` :63 (comment :64-66 mentions sub-categories); `BudgetResponse.category_budgets: List[CategoryBudget]` :80; `AIBudgetSuggestion.category_budgets: List[CategoryBudget]` :132.

### 1.3 `backend/budget_routes.py`
- `_category_budget(cat: dict) -> CategoryBudget` :48 (builds response model from stored dict; falls back to `model_construct` on ValidationError). Gets `sub_category` automatically once the model has it; stored dict must carry key (or None default applies).
- `_budget_response(b)` :58 (maps `category_budgets` :66).
- `POST /ai-suggest` `get_ai_budget_suggestions` :104 / `_ai_budget_suggestions` :132 -> `BudgetAnalyzer.generate_ai_suggestions`. Returns `AIBudgetSuggestion` (so AI categories reach the app as split fields).
- `POST ""` `create_budget(budget_data: BudgetCreate, book)` :168-273: `"category_budgets": [{**cat.model_dump(), "spent_amount": 0.0, ...}]` :219-222 (model_dump will include `sub_category` automatically). `total_budget` is the user's value :225.
- `PUT /{budget_id}` `update_budget(budget_id, budget_data, book)` :396-498:
  - **:434-438** `previous = {c.get("main_category"): c ...}` and **:442** `old = previous.get(cat_dict.get("main_category"))`: keeps stored spent/percentage/is_exceeded per category so alerts don't re-fire. Keyed by main text only. **Needs:** key `(main_category, sub_category)` or a "Main - Sub" is no longer found and a sub line would match/miss wrongly (a main line and its sub line would collide on `main_category`).
  - :455 `calculate_total_budget_excluding_subcategories(category_budgets)` when no total sent.
  - docstring :405-408 mentions `"Main - Sub"`.
- `POST /{budget_id}/refresh` :541: no category logic.
- Import of the total helper: `:20`.

### 1.4 `backend/budget_service.py`
(the design names `_calculate_total_budget_excluding_subs`; the real function is the public `calculate_total_budget_excluding_subcategories`)
- `_append_valid_category(target, cat: Dict)` :55: `CategoryBudget(**CategoryBudgetIn(**cat).model_dump())`. Passing a dict with a `"Main - Sub"` main will now be refused by the new validator -> this swallows the exception (:59-60) and silently skips the category. Needs the split to happen before it (see `_valid_budget_categories`).
- `_BUDGET_JSON_SCHEMA` :65-87: closed object, item properties/required = `main_category, allocated_amount, spent_amount, percentage_used, is_exceeded`, `additionalProperties: False`. Used by both prompts via `_budget_call` :95. e2e asserts the `required` set (see 3.x). Builder choice: keep the AI's text shape and split after parsing, or add `sub_category`.
- `_valid_budget_categories(raw_categories: List, categories_structure: List[Dict]) -> List[CategoryBudget]` :104-133: **splits** `category_name.split(" - ", 1)` :114-115; sub branch validates main in list :116, sub in `category_struct["sub_categories"]` :120; main-only branch :124; case-insensitive main match :127-131 (mutates `cat["main_category"] = match`). Output must carry `main_category` + `sub_category`.
- `_parse_budget_answer(categories_structure)` :136-158 -> calls `_valid_budget_categories` :152.
- `BudgetAnalyzer.generate_ai_suggestions` ... :342 `calculate_total_budget_excluding_subcategories([{"main_category": cat.main_category, "allocated_amount": ...}])` (comment :340-341 says `"Main - Sub"`). **Needs:** pass `sub_category` too.
- `BudgetAnalyzer._generate_with_ai` :378-510: **prompt text** :426-470 (rules 3, 6, 7 at :436-442 say format `"Main Category Name - Sub Category Name"`; example :438 `"Food & Dining - Restaurants"`; EXAMPLES :453-456 with `"Example Main - Example Sub"`; JSON template :458-470 `"main_category": "category name or category name - sub category name"`) and user prompt :472-488. Categories listed from `get_categories_doc("outflow")` :393-409.
- `BudgetAnalyzer._generate_basic_suggestions` :512 builds `CategoryBudget(main_category=cat, ...)` at :545 and :577: main-only (cat keys from `analysis["categories"]`, built from `t["main_category"]` at :195). No change beyond optional default.
- `update_budget_spent_amounts(book_id, budget_id, budget_doc=None, trigger_auto_create=True)` :739-953:
  - :775-778 `old_category_percentages = {cat["main_category"]: ...}` **keyed by main text**.
  - :783-789 spend per (main, sub) from `transactions_db.category_totals`.
  - :793 `budget_category_keys = set(cat["main_category"] ...)`.
  - **:810-811** `main_key = main_cat`, `sub_key = f"{main_cat} - {sub_cat}"` (the join), :817-824 match main bucket then sub bucket; :827-828 `total_spent_accum += amount` once per group if either matched (this is the "counts once" rule).
  - :831-843 `budget_category = cat_budget["main_category"]`; `category_spent_map.get(budget_category)` lookup.
  - :850-852 `calculate_total_budget_excluding_subcategories(budget["category_budgets"])` when `total_budget` is None.
  - :867-876 `budgets_db.update_budget(... "category_budgets": budget["category_budgets"] ...)` rewrites rows.
  - :882-895 per category `check_budget_notifications(..., category_name=cat_name)` with `cat_name = cat_budget["main_category"]` and `old_category_percentages.get(cat_name, 0)` (:885).
  - **Needs:** buckets keyed by `(main, sub_or_None)`: main-only line = every tx with that main (any sub); sub line = tx with that main and that sub; notifications get a composed display label (see 1.5).
- `calculate_total_budget_excluding_subcategories(category_budgets: List[Dict]) -> float` :1069-1101: **splits** `" - "` at :1080-1081 and tests `" - " not in` at :1093; sub counted only if its main has no line. **Needs:** rewrite on `sub_category is None`. Callers: `budget_routes.py:20,455`; `budget_service.py:342, 852, 1183, 1188`.
- `auto_create_next_budget(budget: Dict) -> Optional[str]` :1104: non-AI copy `_append_valid_category(category_budgets, cat)` for each parent doc :1171-1172 (parent docs now include `sub_category`); reset spend :1176-1179 (`cat.model_dump()` carries `sub_category`); total :1181-1188 (comment :1182 `"Main" + "Main - Sub"`); `insert_budget` :1225.
- `_generate_ai_category_budgets(book_id, period, start_date, end_date, parent_budget) -> List[CategoryBudget]` :1272 (thin wrapper; also called by e2e `test_ai_providers.py:4049`).
- `_ai_category_budgets(book_id, period, start_date, end_date, parent_budget) -> Tuple[List[CategoryBudget], bool]` :1283: fallback copies parent cats :1326-1329; `category_spending[cat_budget["main_category"]] = spent` :1333-1334 (**keyed by main text; a sub line would overwrite its main's entry**); prompt context :1345-1353 passes `parent_budget["category_budgets"]` verbatim to the AI as JSON (will now show split fields); **prompt text** :1355-1393 (rules 5-6 :1371-1372 format `"Main Category Name - Sub Category Name"`; template :1385); parse :1406 via `_parse_budget_answer`.
- `_generate_adjusted_budgets(parent_budget: Dict, days_in_period: int) -> List[CategoryBudget]` :1421-1455: rebuilds `CategoryBudget(main_category=cat_budget["main_category"], allocated_amount=..., ...)` :1447-1453. **Needs:** carry `sub_category` (it would silently drop it today's way; and an AI-less auto-create would turn every sub line into a main line).

### 1.5 `backend/notification_service.py`
- `check_budget_notifications(book_id, budget_id, old_percentage, new_percentage, budget_name, category_name: str = None)` :644-664. Inner `budget_label(lang)` :649-650 returns `f"'{category_name}'"` or `"overall"` / `"စုစုပေါင်း"`. Passed as `label=` callable to `create_notification_from_key` (:653-657 threshold 80%, :659-664 exceeded 100%). Message templates: `NOTIFICATION_TRANSLATIONS["en"]["budget_threshold_msg"]` :43 / `budget_exceeded_msg` :45 (and `my` :159, :161): `"... your {label} budget in '{budget_name}'..."`. **Needs:** callers pass a composed label (`"Main - Sub"` when a sub exists) or a `sub_category` param; text must stay byte-identical. Only callers: `budget_service.py:888-895` (category) and :899-906 (total, `category_name=None`).

### 1.6 Other backend readers of allocation `main_category` (grep `category_budgets|main_category` excluding alembic)
- `backend/ai_chatbot.py:574-575` (`for cat in b['category_budgets']: cat_name = cat['main_category']`, printed as `{cat_name}:` :583) and `:794-795` (`──── {cat_name} ────` :801). **Need:** display `"Main - Sub"` when sub present (keeps the AI-context text as today).
- `backend/insights_service.py:639-641` and `:1484-1486`: `cat_budget['main_category']` printed with spent/allocated. Same fix.
- No allocation reads in: `report_routes.py`, `custom_insights_service.py` (its `main_category` is transactions), `recurring_transaction_service.py`, `families/` (no breakdown allocation read; `families/transfers.py` is transactions), `generate_mock_data.py` (transactions only), `database.py` (category seed), `category_matching.py` (transactions). No backend seed script writes allocations.
- Transaction-side `main_category`/`sub_category` stay as is (`models.py:141-197`, `sql/tables.py:96-97`, `sql/transactions.py:223-229` `category_totals` returns `main_category, sub_category, total` per currency/type; this is the source for spend).

---

## 2. Budget categories, app (`frontend/`)

- `frontend/lib/models/budget.dart:10` `class CategoryBudget {String mainCategory; double allocatedAmount, spentAmount, percentageUsed; bool isExceeded}`; ctor :17 (all `required`), `fromJson` :25 (`json['main_category']`), `toJson` :35. **Needs:** `final String? subCategory` (optional named ctor param so tests compile), `fromJson` reads `json['sub_category']`, `toJson` writes it (send `sub_category` null/omitted for main-only), plus a display getter composing `"Main - Sub"` for every label.
- Nested in `Budget.categoryBudgets` :53 (`Budget.fromJson` :130) and the AI suggestion class (:236, fromJson :264). Extension `CategoryOverState.isOverIn` :175; `Budget.categoriesOver` :162.
- `frontend/lib/services/api_service.dart:2185 createBudget(...)` -> `'category_budgets': categoryBudgets.map((cat) => cat.toJson())` :2201; `:2307 updateBudget(...)` -> :2322. Nothing else to change (they serialise via `toJson`). `frontend/lib/providers/budget_provider.dart:134,150,218,231` pass the list through.
- `frontend/lib/screens/budgets/create_budget_screen.dart` (every `' - '` use):
  - :303-328 `_validateDuplicateCategory(String mainCategory, String? subCategory)`: :309-313 `existingMain.contains(' - ')` / `split(' - ')`; compares :315-324.
  - :330-358 `_calculateTotalBudget()`: :335-337 split, :346 `!contains(' - ')`.
  - :1062-1098 `_CategoryCapSheetState._loadCategories`: :1073-1091 `initialCategory!.mainCategory` split on `' - '` to preselect main/sub chips.
  - :1128-1131 `_submit`: `displayName += ' - $_selectedSubCategory'` (**the join**) then :1139-1147 `CategoryBudget(mainCategory: displayName, ...)`. **Needs:** `mainCategory: _selectedMainCategory!, subCategory: _selectedSubCategory` (note `'All'`?? duplicate check treats `'All'` as main-only at :316/:321; the sheet stores `_selectedSubCategory = null` for main-only).
  - display of line: :986 `iconForCategoryName(catBudget.mainCategory)` and :998 `catBudget.mainCategory` (row label). :435 `_categoryBudgets = result.categoryBudgets;` (from the AI suggestion screen).
- `frontend/lib/screens/budgets/edit_budget_screen.dart`:
  - :62-94 `_validateDuplicateCategory(mainCategory, subCategory, {excludeIndex})`: split :75-79.
  - :100-139 `_calculateTotalBudget` / `_sumOfCaps` (static): split :116-118, :127.
  - :145-161 `_categoriesBelowSpent`: **:150 `orig.mainCategory == cat.mainCategory`** matches originals by the combined text (needs main AND sub compare).
  - :476 `belowSpent.map((c) => c.mainCategory).join(', ')`, :705 icon, :717 row label.
  - :785-819 `_loadCategories`: split :795-798, :800-811.
  - :849-852 `_submit` join `' - $_selectedSubCategory'`; :860-868 `CategoryBudget(mainCategory: displayName, ...)`.
- Other displays of an allocation label (must still print `Main - Sub`): `screens/budgets/budget_detail_screen.dart:487` (`categoriesOver ... c.mainCategory`), :754 (icon) and :759 (label) in `_buildCategoryCard` :720; `screens/budgets/ai_budget_suggestion_screen.dart:485-508` (`catBudget.mainCategory`). `lib/utils/category_icons.dart:7 iconForCategoryName(String name)` does substring matching on the whole label (e.g. `'taxi'`, `'rent'`), so pass the composed label to keep icons identical.
- Tests under `frontend/test` that build `CategoryBudget` (all main-only, none has a `"Main - Sub"` fixture; they compile unchanged if `subCategory` is an optional named param):
  - `test/budget_over_state_test.dart:33` (`_cat(name, cap, spent)` helper), used :66-82, :186, :213-216.
  - `test/edit_budget_total_test.dart:36` (`_cat`), :55-59; fake `updateBudget` :16-31 records `sentCategories`.
  - `test/myanmar_budget_text_test.dart:45-46`.
  - JSON fixtures with `'category_budgets': []`: `test/bug_fixes_round2_test.dart:49`, `test/family_screen_test.dart:789`; `categoryBudgets: []`: `dashboard_myanmar_test.dart:99`, `family_budgets_goals_test.dart:81`.
  - `integration_test/flows/budget_goal_flows.dart:24 addCategoryCap(mainCategory, amount)` (taps chips; no strings to change).

---

## 3. Budget categories, e2e

No e2e file sends or asserts a `"Main - Sub"` allocation string. Grepping for the separator next to `main_category` / `category_budgets` finds nothing; every allocation in e2e is main-only. What does break or needs attention:

- `e2e/pgcompat.py:233-238` `_insert_allocations(cur, allocations)`: **raw SQL** `INSERT INTO budget_allocations (budget_id, position, main_category, allocated_amount, spent_amount, percentage_used, is_exceeded) VALUES (...)`: column list is hard-coded and uses the dict keys from `D.allocation_rows`; with a new `sub_category` key in the row dict the named `%(...)s` binding still works but the column is not written. **Needs:** add `sub_category` to the column list and `%(sub_category)s`. Also reads: `:174-176` `SELECT * FROM budget_allocations` -> `D.budget_doc` (fine); `:305-306` delete + `_insert_allocations` on `$set category_budgets`. `TABLES` set :27-29 (add `"user_devices"` if tests use `db.user_devices`).
- `e2e/test_books.py:225` raw `INSERT INTO budget_allocations (budget_id, position, main_category, allocated_amount)` in `_seed_old_shape` (runs after `downgrade BEFORE_BOOKS`, i.e. below the new migrations, so it keeps working; the migration then upgrades through the new budget migration with rows `"Food"`, `"Transport"` main-only). `:409-410` counts allocations after upgrade (== 2).
- Places that create budgets via the API with main-only allocations (all still valid; responses now contain `"sub_category": null`): `test_api.py:387, 397, 406, 458, 462, 466, 989`; `test_backend_r4.py:34, 71, 73`; `test_books.py:708, 961, 985, 1152, 1583`; `test_family.py:683, 1523, 1532, 1860, 2126, 2281`; `test_load.py:49`; `seed_rich.py:84, 88, 90`; `test_round3.py:41, 48` (PUT sends back `cur["category_budgets"]` from a GET: so the GET response shape, now including `sub_category: null`, round-trips into `CategoryBudgetIn`; must be accepted); `test_regressions_all.py:101`; `test_regressions3.py:33`; `test_sweep.py:91`; `plans_entry_checks.py:307, 368, 398`; `plans_custom_insight_checks.py:604`.
- Docs inserted directly (no `sub_category` key, so the code must use `.get`): `test_jobs.py:124, 131`; `test_books.py:961`; `test_ai_providers.py:4041` (parent doc passed in-process to `bs._generate_ai_category_budgets` :4049 and `bs._generate_adjusted_budgets(parent, 31)` :4108).
- AI stub / schema assertions: `e2e/stubenv.py:269-275` answers any prompt containing `"allocated_amount"` with main-only categories (`Food & Daily Living` 450, `Transportation` 120). `e2e/test_ai_providers.py:4064` asserts the JSON schema `item["required"] == {"main_category","allocated_amount","spent_amount","percentage_used","is_exceeded"}` (breaks if the schema's required set changes); :4098-4104 sends `"food & daily living"` (case-insensitive main match) and `"Nope"` through `_parse_budget_answer`; :3927-3964, :4073-4131 assert `category_budgets[0].allocated_amount == 450`.
- New e2e needed for the design: sub lines (create/update/PUT validation 422 for `" - "`, spent/total/alert parity, rollover copy keeps sub, migration of existing `"Main - Sub"` rows both ways). No existing helper seeds a sub line.

---

## 4. Devices, backend

### 4.1 Every reference (grep `fcm_token|set_device_token|clear_device_token|HAS_DEVICE|send_fcm_*`, excluding alembic)
- `backend/sql/tables.py:79` `Column("fcm_token", Text)` on `users`; `:87` `Index("uq_users_fcm_token", users.c.fcm_token, unique=True, postgresql_where=users.c.fcm_token.isnot(None))`. (Initial migration creates it: `alembic/versions/20261016_799d29a14d00_initial_schema.py:109`, drops :388.) -> remove both; add `user_devices`.
- `backend/sql/users.py:49` `HAS_DEVICE = users.c.fcm_token.isnot(None)` (used by `admin_routes.py:1045`). -> becomes an EXISTS on `user_devices`.
- `backend/sql/users.py:236` `set_device_token(user_id: str, token: str) -> int`: in one transaction nulls the token on other users (`released` count) then sets it on `user_id`. `:246` `clear_device_token(user_id: str) -> None`: `update_user(user_id, fcm_token=None)` (clears whichever device). -> replaced by device-table functions.
- `backend/sql/users.py:13,16-21` `_COLUMNS` / `_values` raise `KeyError` for an unknown column: any caller doing `update_user(..., fcm_token=...)` or `list_fields(["fcm_token"])` will raise once the column is gone (`list_fields` :91 does `users.c[c]`).
- `backend/main.py:1110-1128` `POST /api/auth/update-fcm-token` `update_fcm_token(payload: FcmTokenUpdate, current_user)`: calls `users_db.set_device_token(user_id, token)` :1122, logs "detached from N other user(s)", returns `{"message": ...}`; any exception -> 500 "Failed to update FCM token".
- `backend/main.py:1131-1139` `DELETE /api/auth/fcm-token` `delete_fcm_token(current_user)`: takes no body/query today, calls `users_db.clear_device_token(current_user["_id"])`.
- `backend/main.py:35` imports `FcmTokenUpdate` from `notification_models`; **model lives at `backend/notification_models.py:52-62`** (`fcm_token: str = Field(..., min_length=1, max_length=4096)`; validator strips, rejects empty). Needs `previous_token: Optional[str]`.
- `backend/notification_service.py:6` `from firebase_service import send_fcm_notification`; `:401-402` `user = await users_db.get_user(user_id); fcm_token = user.get("fcm_token")`; `:405-428` `send_background_fcm()` (sync, runs `asyncio.to_thread`; builds `fcm_data` `notification_id, type, subject_id, goal_name, currency` + `book: "family"`) calls `send_fcm_notification(fcm_token=..., title=..., body=..., data=...)` :419-424; `:425-426` prints "User has no FCM token". Fire-and-forget task :432-441 (`_background_tasks`). Single push point for all stored notices.
- `backend/subscription_service.py:21` imports `send_fcm_data_message`; `:73-77` `users_db.list_fields(["subscription_type", "subscription_expires_at", "fcm_token", "language"], ...)` in `expire_paid_plans`; `:110-118` silent `{"type": "subscription_updated", "subscription_type": "free"}` via `asyncio.to_thread(send_fcm_data_message, user["fcm_token"], {...})`.
- `backend/admin_routes.py:45` imports `send_fcm_data_message, send_fcm_to_multiple`; `:711-725` `update_user_subscription`: `fcm_token = user.get("fcm_token")`, `run_in_threadpool(send_fcm_data_message, fcm_token, {"type": "subscription_updated", "subscription_type": ...})`, response key `fcm_refresh_sent` (asserted by e2e `plans_subscription_checks.py:195`); `:954` `users_db.list_fields(["fcm_token"], *conditions)` in `broadcast_notification`; `:964-1009` collects `fcm_tokens`, `list(dict.fromkeys(fcm_tokens))`, `run_in_threadpool(send_fcm_to_multiple, fcm_tokens=..., title=..., body=..., data={"type", "is_broadcast": "true"})`, returns `{"success","failure"}` -> `BroadcastNotificationResponse.fcm_sent/fcm_failed`; `:1045-1050` `get_broadcast_stats`: `has_fcm = users_db.HAS_DEVICE`, `_plan_counts(now, has_fcm)` (:85-92, passes extra `*conditions` to `users_db.count_users`), `users_db.count_users(has_fcm)`.
- No other backend file mentions them (no scripts/tests in `backend/`).

### 4.2 `backend/firebase_service.py` (failure reporting today)
- `initialize_firebase()` :8; module `_firebase_app`.
- `send_fcm_notification(fcm_token: str, title: str, body: str, data: dict = None) -> bool` :41-89: returns `False` if app not initialised :48-50; `except messaging.UnregisteredError:` prints and returns False :83-86 with `# TODO: Remove this token from database`; other `Exception` prints, False :87-89. Caller cannot tell "unregistered" from any other failure.
- `_stringify_data(data)` :92; `send_fcm_data_message(fcm_token: str, data: dict = None) -> bool` :97-131 (same shape, `UnregisteredError` :126-128 prints only).
- `FCM_MULTICAST_LIMIT = 500` :134; `send_fcm_to_multiple(fcm_tokens: list[str], title: str, body: str, data: dict = None) -> dict` :137-202: returns `{"success": n, "failure": n}`. Per-response errors only printed: `:190-193` `for idx, resp in enumerate(response.responses): if not resp.success: print(f'Failed to send to token {start + idx}: {resp.exception}')`. `resp.exception` there is where an `UnregisteredError` per token appears; the token strings are not returned, so the caller can't delete rows. Chunk-level exception :195-199 counts the whole chunk as failure.
- All three are blocking; callers use `asyncio.to_thread` / `run_in_threadpool`.

### 4.3 `main.py`, `utils.py`: is the token `exp` exposed?
- **No.** `backend/utils.py:61` `_decode_user_token(token: str) -> dict` returns the full payload (including `exp`, `iat`, `uid`, `pwv`, `sub`) but `get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security))` :90-135 returns only the users row (+ `personal_book_id`); the payload is dropped. `security = HTTPBearer()` :24. The register-device endpoint needs `exp`: either add `Depends(security)` and call `_decode_user_token(credentials.credentials)["exp"]` in the endpoint, or have `get_current_user` attach e.g. `user["_token_exp"]` (it is used by ~every route, so attach cheaply). `create_access_token(data, expires_delta)` :39-50 sets `exp` (datetime) and `iat` (int seconds). `verify_token` :85.
- `ACCESS_TOKEN_EXPIRE_MINUTES = 43200` at `backend/config.py:13` (30 days); `ALGORITHM = "HS256"` :11; `SECRET_KEY` :10.

### 4.4 `backend/auth_routes.py` (router prefix `/api/auth` :50)
- `_issue_token(user: dict) -> str` :134-138: `create_access_token({"sub": email, "uid": _id, "pwv": password_version}, timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES))`. Used by: register :200, login :286, change-password :498. Reuse for `renew-session`.
- `POST /register` :154; `POST /login` :267 (response `Token` = `access_token, token_type, user`; `models.py:117`).
- `POST /forgot-password/reset-password` `reset_password(request)` :388-423: ends with `users_db.reset_password_with_token(user["_id"], stored_token_hash, hashed_pw, password_changed_now())` :420 (bumps `password_version`, `sql/users.py:168`); returns :423. **Needs:** delete all of the user's device rows after the success check (:420).
- `PUT /change-password` `change_password(password_data, current_user)` :463-500: `users_db.change_password(...)` :494 (`sql/users.py:176`, bumps `password_version`, returns updated user), returns new `access_token` :498. **Needs:** delete every device row except the one making the change (requires the device's token in the request body `PasswordChange` in `models.py`, or delete-all and let the app re-register; note `ApiService.changePassword` already stores the new token but `AuthProvider.changePassword` :671-691 does not re-register FCM).
- `DELETE /delete-account` `delete_account(body, current_user)` :503-538: `users_db.delete_user` inside `transaction()` :520-526; `user_devices.user_id ON DELETE CASCADE` handles devices; nothing else needed.
- New endpoint `POST /api/auth/renew-session` goes here (auth: `Depends(get_current_user)`, return `_issue_token(current_user)`); a revoked/expired token already 401s in `get_current_user` (:106-129 `pwv` check).

### 4.5 `backend/scheduler.py` (job registration)
- `start_scheduler()` :21: `AsyncIOScheduler(timezone=app_tz)` :29; each job is `scheduler.add_job(<async fn>, trigger=CronTrigger(timezone=app_tz, ...), id="...", name="...", replace_existing=True, [misfire_grace_time=..., coalesce=True])`. Imports at top :4-16. Called from `main.py:126-127` (`app.state.scheduler = start_scheduler()`).
- Existing hourly pattern (copy for the reminder): `expire_paid_plans` :88-96 `CronTrigger(minute=5)`, `misfire_grace_time=3600, coalesce=True`; `send_trial_reminders` :100-108 and `send_plan_renewal_reminders` :113-121 both `minute=20`. Daily pattern: `budget_rollovers` :75-83 `hour=0, minute=30, misfire_grace_time=6*3600, coalesce=True`. Add e.g. `send_sign_in_reminders` hourly (e.g. `minute=35`) and `delete_stale_devices` daily (off-peak). Job functions live in services (`subscription_service.py` has the `claim_*`-then-send pattern for "at most once").

### 4.6 Localization of push strings
- `backend/notification_service.py:31` `NOTIFICATION_TRANSLATIONS = {"en": {...}, "my": {...}}` (en :32-147, my :148-261); flat `"<key>": "text with {placeholders}"`; title/message keys come in pairs (`xxx_title`, `xxx_msg`). `translate(key: str, language: str, **kwargs) -> str` :282-285 (falls back to `en`, then the key). `get_user_language(user_id)` :275; `plans.access.user_language(user: Mapping) -> str` (`backend/plans/access.py:51`, returns "en"/"my"). Add `sign_in_reminder_title` / `sign_in_reminder_msg` to both dicts (Myanmar needs native review). Note the frozen-copy comment at :327-329: `NOTIFICATION_LINKS` lists every stored notice type; a push-only reminder is not a stored notice so it does not belong there. e2e `test_family.py:2077-2079` reads `NOTIFICATION_TRANSLATIONS["en"/"my"]` keys directly.
- Brand text: existing messages already say "Toe Pwar" (e.g. :79, :81).

### 4.7 `admin_routes.py` and `admin_models.py`
- `GET /api/admin/users` `get_all_users(current_admin, skip, limit, search, subscription_type) -> List[UserListResponse]` :549-600: per user loops `books_db.personal_book_id`, counts, `last_active`; builds `UserListResponse` :586-598. Data from `users_db.admin_list(...)` (`sql/users.py:100`, `select(users)`).
- `GET /api/admin/users/{user_id}` `get_user_detail(user_id, current_admin) -> UserDetailResponse` :603-655.
- `backend/admin_models.py:54` `class UserListResponse(BaseModel)` (id, name, email, subscription_type, effective_plan, subscription_expires_at, default_currency, created_at, total_transactions, total_goals, last_active); `:80` `class UserDetailResponse` (same + language, total_budgets, total_chat_sessions); `:147` `BroadcastNotificationResponse(message, total_users, notifications_sent, fcm_sent, fcm_failed)`. Add `device_count: int = 0` to both user models and `devices: List[DeviceInfo]` (`created_at`, `last_seen_at`; no tokens) to the detail model.
- Broadcast push: `broadcast_notification` :936-1035 (see 4.1). Plan-update push: `update_user_subscription` :658-... (push at :709-725). `DELETE /users/{user_id}` :807 (cascade covers devices).

### 4.8 `backend/sql/users.py` device-related
- `HAS_DEVICE` :49, `set_device_token` :236, `clear_device_token` :246 (above).
- `list_fields(columns: Iterable[str], *conditions) -> List[Dict]` :91-97: `select(users.c.id + users.c[c])`; callers passing `"fcm_token"`: `subscription_service.py:74`, `admin_routes.py:954`. After the change those need to read from the new devices module instead. No other `list_fields` call selects `fcm_token`.
- `count_users(*conditions)` :77, `user_ids(*conditions)` :84, `admin_list` :100. `get_user` :53 returns `row_to_doc` (all columns; `fcm_token` currently in the doc: `notification_service.py:402`, `admin_routes.py:711`).
- Pattern for new module: other `sql/*.py` modules (`sql/notifications.py`, `sql/budgets.py`) use `from sql.db import execute, fetch_all, fetch_one, fetch_value, transaction, write_returning`.

---

## 5. Devices, app (`frontend/`)

- `frontend/lib/services/fcm_service.dart` (`class FCMService`, singleton):
  - `String? _fcmToken` :31, getter `fcmToken` :33.
  - `initialize()` :35-86: returns on web :36; `requestPermission` :42; **only when authorised** `_fcmToken = await _fcm.getToken()` :52; `_fcm.onTokenRefresh.listen((newToken) { _fcmToken = newToken; _sendTokenToBackend(newToken); })` :55-59 (**no previous token kept**); permission denied -> `_fcmToken` stays null :80-82.
  - `sendTokenToBackend()` :108-113 (web-guard; sends `_fcmToken` if non-null); `_sendTokenToBackend(String token)` :115-125: returns if `ApiService.getToken() == null` :118, calls `ApiService.updateFCMToken(token)` :120, swallows errors (prints). **Needs:** remember last registered token (SharedPreferences) and send as `previous_token`.
  - Foreground handler `_handleForegroundMessage` :127-158; background handler :13-18 (comment at :16-17 claims "The app will call checkAuthStatus() on resume" which is not true on mobile, see below).
  - Tap handling: `_handleMessageOpenedApp` :160; `_onNotificationTapped` :165; `_handleNotificationNavigation(Map<String,dynamic>)` :182-206: calls `notificationRefreshesPlan(type)` and, only if `notificationOpensSomething(type)` (`lib/models/notification.dart:116`), sets `_pendingOpen` and `retryPendingOpen()`. **An unknown type like `sign_in_reminder` only prints and does nothing**: the OS already opens the app, so "tapping opens the app" holds with no change. Foreground: `_showLocalNotification` :229-272 uses `_getNotificationColor(type)` :274 (default colour for unknown) and `pushTapPayload(...)` returns null for types that open nothing (`lib/utils/push_tap.dart:10-11`). `notification_opener.dart:99` `if (!notificationOpensSomething(type)) return true;`.
  - Test seam `handleNotificationNavigationForTest` :180.
- `frontend/lib/services/api_service.dart`:
  - `getToken()` :562 (`SharedPreferences` key `'access_token'`), `saveToken(String)` :567, `removeToken()` :572, `removeTokenIfMatches(String token)` :579.
  - `updateFCMToken(String fcmToken)` :643-653: `POST /api/auth/update-fcm-token`, body `{'fcm_token': fcmToken}`; non-200 -> `apiError`.
  - `deleteFcmTokenOverride` :657 (`Future<void> Function(String authToken)?`, test seam) and `deleteFCMToken({String? authToken})` :661-677: `DELETE /api/auth/fcm-token`, overriding the Authorization header with the captured logout token :668; sends **no token**. **Needs:** an `fcmToken` parameter (body or query) and the seam signature updated.
  - `_sessionCheckExemptPaths` :439-447 includes `'/api/auth/fcm-token'` (prefix match `path.startsWith`), so a 401 there does not sign out; `/api/auth/update-fcm-token` is NOT exempt (a 401 on registration triggers `onSessionExpired`); a new `/api/auth/renew-session` would not be exempt either, which gives the desired "401 = usual session-expired handling". `isSessionRejection(Object)` :391. `checkSessionInvalidated` :463.
  - `changePassword({...})` :865-896 saves the fresh `access_token` from the response :880-888.
  - `login` :717, `register` :695 (saveToken :709, :732). No JWT decoding anywhere in `frontend/lib` (no `iat`/`exp` parsing, no jwt package in pubspec).
- `frontend/lib/providers/auth_provider.dart`:
  - fields `_fcmDeleteInFlight` :36, `_pendingFcmFlush` :39, `_authGeneration` :23 (superseded guard), `_authCheckInFlight` :18.
  - `_sendFCMToken()` :111; `_registerFcmFor(String userId)` :123-129 (waits for in-flight DELETE :125-126, `_flushPendingFcmUnregister(signedInUserId: userId)` :127, then `_sendFCMToken()` :128; web returns :124); `_flushPendingFcmUnregister({String? signedInUserId})` :134-163 (loads `PendingFcmUnregister`; same-user -> `clear()` :140-143; else `ApiService.deleteFCMToken(authToken: pending.authToken)` :145; 401/403 clears :150-153; else keeps).
  - Call sites of `_registerFcmFor`: register :374, login :397, `checkAuthStatus` :628.
  - `logout()` :482-513: captures token, `_cancelAuthCheck()`, wipes state, `removeTokenIfMatches(token)` :507, `unawaited(_unregisterFcm(token: token, userId: userId))` :512. `_unregisterFcm({required String token, String? userId})` :520-568: web returns :523; reads `FCMService().fcmToken` :526 (informational), `ApiService.deleteFCMToken(authToken: token)` :530, 5 s timeout :546, on failure/timeout (except 401/403 :553-556) `PendingFcmUnregister.save(PendingFcmUnregister(authToken, userId, fcmToken))` :558-562. **Needs:** skip the call and the pending save when the device has no push token; send the token.
  - `handleSessionExpired(String token)` :574-594; `checkAuthStatus()` :602-655 (restore: `getCurrentUser()` :621, then `_registerFcmFor(user.id)` :628; signed-out branch flushes pending :634). `changePassword(...)` :671-691 (no FCM step). `refreshUserSilently()` :268.
  - **No app-lifecycle hook on mobile.** `frontend/lib/main.dart:146-148`: `if (PlatformInfo.isWeb) { _lifecycleListener = AppLifecycleListener(onResume: _refreshOnResume); }`; `_refreshOnResume` :219-227 (refreshUserSilently, plan refresh, unread count, family refresh). Renewal on foreground therefore needs this listener created on mobile too (or a separate one), and it must not change the web-only behaviour of `_refreshOnResume` unintentionally.
- `frontend/lib/services/pending_fcm_unregister.dart` `class PendingFcmUnregister` :9: fields `authToken` (required), `userId`, `fcmToken` ("informational", :19-20); `toJson` :28, `fromJson` :34, `load` :47, `save` :59, `clear` :64, `clearIfAuthToken(String)` :71; key `'pending_fcm_unregister'`. The stored `fcmToken` is exactly what the new DELETE needs; the flush at `auth_provider.dart:145` must pass `pending.fcmToken` (and skip/clear when it is null).
- Tests touching this (`frontend/test`):
  - `web_platform_test.dart:12-24` sets `ApiService.deleteFcmTokenOverride = (String authToken) async {...}`; `:43-51` **"logout on Android still unregisters" expects `deleteCalls == ['old-token']`** while `FCMService().fcmToken` is null in tests (no Firebase). Under the design (no push token -> skip DELETE) this test fails and needs a token injected/seam. `:31-41` web logout must not call it; `:53-61` FCMService inert on web.
  - `bug_fixes_round2_test.dart:216` (`/api/auth/fcm-token` exempt path), `:264-280` pending-unregister round trip (`PendingFcmUnregister(authToken: 'a1', userId: 'u1', fcmToken: 'f1')`), `:230-238` `handleSessionExpired`, `:241-250` logout vs auth check, `:63,232,244,255` build `AuthProvider()`.
  - `family_screen_test.dart:28,935-945` `FCMService().setOpenFromPushHandler` / `handleNotificationNavigationForTest`.
  - Many widget tests create `AuthProvider()` (e.g. `widget_test.dart:54`, `upgrade_contact_test.dart:629 _SignedInAuth`); any new constructor side effect (e.g. a lifecycle listener or timer in the constructor) would run in all of them.

---

## 6. Devices, admin JS (`admin/src`)

- `admin/src/App.jsx:32-33` `api.getUsers(token, params)` -> `GET /api/admin/users`; `api.getUser(token, userId)` -> `GET /api/admin/users/{id}`. (`api.js` has `apiRequest` :97, `getUserUsage` :175, `resetUserUsage` :178; users calls live in `App.jsx`, not `api.js`.)
- User list table: `App.jsx:1500-1546` (headers :1502 `['User','Subscription','Activity','Joined','Actions']`; Activity cell :1529-1532 shows `total_transactions` and `total_goals`: add a "N devices" line here from `user.device_count`).
- User detail modal: `App.jsx:1750-1859` (`selectedUser` state :1065). Statistics grid :1833-1848 (items Transactions, Goals, Currency, Joined; add Devices count here) and the new devices list (created / last seen, no tokens) after it. **`openUser(user)` :1258-1261 sets `selectedUser` to the LIST row** (`UserListResponse`), so detail-only fields (language, total_budgets, a `devices` list) are not present; only `openUserById` :1264-1267 loads the detail endpoint (`api.getUser`). To show a device list, `openUser` must fetch `api.getUser` (or the list response must carry devices).
- Broadcast reach tiles: `App.jsx:1670-1674` use `broadcastStats.users_with_push_enabled`, `free_with_push`, etc. (field names unchanged by the design).

---

## 7. e2e infrastructure for pushes

- Stub entry: `e2e/run_server.py:9-11` `import main` then `stubenv.patch_loaded_modules()`; `e2e/stubenv.py` blocks `.env` (:21-23), sets `FIREBASE_CREDENTIALS_PATH` to a missing file and `FIREBASE_CREDENTIALS_JSON_STR` `{}` (:36-37).
- `stubenv.py:621-645` replaces `firebase_admin.messaging.send`, `send_each_for_multicast`, `send_multicast`: `_send` records `{"kind":"fcm_send","token","title"}`; `_send_multi` records `{"kind":"fcm_multicast","n"}` and returns `_BatchResp(success_count=n, failure_count=0, responses=[])` (so per-response failures such as `UnregisteredError` cannot be simulated today; `responses` is empty).
- `stubenv.py:651-676` `patch_loaded_modules()`: for **every backend module** (`__file__` under `BACKEND`) replaces, **by function name**, `initialize_firebase` (records `firebase_init`), `send_fcm_notification` (`fake_send(*a, **k)` records `fcm_send` with `fcm_token, title, body, data`, returns `True`), `send_fcm_to_multiple` (`fake_send_multi`, records `fcm_multicast` with `n` and `title`, returns `{"success": n, "failure": 0}`). **`send_fcm_data_message` is NOT patched**: the real one runs, sees `_firebase_app is None` (no creds, `initialize_firebase` faked) and returns `False` without recording. Any new sender function (e.g. `send_fcm_to_tokens`, a data-multicast helper, the reminder sender) is not stubbed unless added to that tuple and given a recording fake with the same return shape (any richer return type like per-token results must be mirrored there).
- Capture for assertions: **file** `e2e/outbox.jsonl` (`stubenv.OUTBOX`, `record(kind, **payload)` :42 appends one JSON line); a tiny HTTP reader `e2e/outbox_server.py` on port 8766. Assertions read the file directly: `e2e/test_books.py:1106-1111` and `e2e/test_family.py:2065-2070` define `pushes(token)` filtering lines containing `"fcm_send"` and matching `r.get("fcm_token")` or `r.get("token")`; `plans_chat_checks.py:29-31`, `test_ai_providers.py:66-68`, `test_jobs.py:163` read the same file for AI calls. In-process alternative: `e2e/test_plan_expiry.py:82-83` monkeypatches `ss.send_fcm_data_message = lambda token, data=None: pushes.append((token, data)) or True` (subscription_service namespace) and asserts `pushes == [("fcm-token-expired-en", {"type": "subscription_updated", "subscription_type": "free"})]` :118.
- Every e2e line that sets or asserts `fcm_token` (all break when the column goes; they must move to `user_devices` via `db.sql("INSERT INTO user_devices ...")`, `db.user_devices` after adding it to `pgcompat.TABLES`, or the register-token API):
  - `e2e/dbtweak.py:30` prints `u.get("fcm_token")`.
  - `e2e/plans_subscription_checks.py:193` `db.users.update_one(... {"$set": {"fcm_token": f"t4s-token-{tag}"}})` (then :195 asserts `fcm_refresh_sent` in the admin response); `:542` sets `t4s-push-{d}` for `dashboard_counts_per_plan`; `:553-554` asserts `plus_with_push`, `pro_with_push`, `paid_with_push`, `free_with_push` deltas (the `HAS_DEVICE` EXISTS semantics must produce the same counts; `session_expires_at` must not matter for "push enabled").
  - `e2e/test_api.py:646-656`: update token OK (:646-647), `{}` body "-> 500" :648-649 (really 422 today; see surprises), `B` registers same token as `A` (:650), `a_tok = db.users.find_one(...).get("fcm_token")` :651-652 "same device token stays on two accounts" bug check, `DELETE /api/auth/fcm-token` with no body :653-655 and `b_tok` read :654, re-register :656.
  - `e2e/test_books.py:1127` `UPDATE users SET fcm_token = ...` (notification_links section: pushes asserted via `pushes(f"fcm-links-{p|q}-{tag}")` :1203-1211).
  - `e2e/test_family.py:169` `UPDATE users SET fcm_token = 'owner-fcm-token'`; `:2093-2094` `SET language = 'my', fcm_token = ...` for Dad/Mum; asserts `pushes(f"fcm-mum-{tag}")` / `fcm-dad` :2150-2151, :2283 (titles in en / my from `NOTIFICATION_TRANSLATIONS`).
  - `e2e/test_plan_expiry.py:40-44` `user(..., fcm=None)` sets `"fcm_token": fcm` in `db.users.update_one`; `:51, :57` pass `fcm="fcm-token-expired-en"` / `"fcm-token-lapsed"`; `:83-118` assertions above.
- Other e2e that rely on the single-token model implicitly: none found outside the files above.

---

## 8. Suite runner

- `e2e/run_backend_suite.py:17-19` `SUITES = ["test_api", "test_jobs", "test_jobs2", "test_regressions_all", "test_regressions2", "test_regressions3", "test_round3", "test_backend_r4", "test_round5", "test_sweep", "test_load", "test_burst_pooled", "test_plan_expiry", "test_money_lock", "test_app_download", "test_ai_providers", "test_books", "test_family", "test_plans", "test_goals_summary"]`. Runner runs each as `python -u <name>.py` (no argv), parses `[PASS]/[BUG]/[FAIL]/[INFO]` lines, logs `logs_<name>.txt`. `PRINT_ONLY` set :73 lists suites that only print (and are not also recorded in `api_results.json`): a new print-only `test_devices` must be added to **both** `SUITES` and `PRINT_ONLY`, else its checks are double-counted (or its crash is the only signal). Problem filter :79 keeps only `PRINT_ONLY` suites' printed problems.
- `e2e/test_books.py` pattern to copy:
  - header docstring (:1-24) with a "Sections:" list; `os.environ.setdefault("E2E_FAKE_AI", "1")`, `sys.path.insert(0, e2e dir)`, `import stubenv` (:31-34); `db = __import__("pgcompat").get_db()` :36; global `failures` :37; `check(ok, name, detail="")` :44-48 prints `[PASS] ` / `[BUG] `.
  - one `section_<name>()` function per area; registry `SECTIONS = {"schema": section_schema, ...}` :1640-1642; `main()` :1645-1653: `wanted = sys.argv[1:] or list(SECTIONS)`, unknown names -> message + `sys.exit(2)`, runs each, `sys.exit(1 if failures else 0)`; `if __name__ == "__main__": main()` :1656. Sections needing the server say so ("Needs the stub server on 127.0.0.1:8765"); API sections use `httpx`/`c` clients created inside the section (e.g. `_api_people(c, tag, made)` :649, `_admin_headers(c)` :1378, `_drop_people(made)` :669).
  - Migration section helpers: `import test_plans as t` (`t.alembic(*args)`, `t.connect()`, `t.current_revision(conn)`: `test_plans.py:40-53`) and `plans_subscription_checks.head_revision()` (:26, reads the head from `alembic.ini`, so a new head is picked up automatically); downgrade to a revision constant such as `BEFORE_BOOKS = "522ad619de76"` (:39), seed old-shape rows with raw SQL, upgrade head, compare, downgrade/upgrade again, `finally: upgrade head` and clean up (`section_migration` :276-359). `test_family.py` has a similar `SECTIONS`/argv pattern (grep count 5).
- `e2e/run_e2e.ps1:83-87` runs `alembic upgrade head` before suites; `e2e/pgcompat.py:382-387` truncates every table in `T.metadata.sorted_tables` (a new `user_devices` table is cleaned automatically).

---

## Surprises (things that contradict or complicate the design)

1. **No lifecycle hook on mobile.** `main.dart:146-148` creates the `AppLifecycleListener(onResume: ...)` only when `PlatformInfo.isWeb`. "Renew when the app returns to the foreground" needs a new mobile hook. The comment in `fcm_service.dart:16-17` claiming checkAuthStatus runs on resume is false.
2. **`get_current_user` drops the token payload**; `exp` is not available to the register endpoint without re-decoding (`utils._decode_user_token`) or attaching it to the user dict.
3. **Function name differs from design:** `calculate_total_budget_excluding_subcategories` (public, 5 call sites), not `_calculate_total_budget_excluding_subs`.
4. **Existing `PUT` budget logic keys previous spend by `main_category` text** (`budget_routes.py:434-442`) and so does `update_budget_spent_amounts` (`budget_service.py:775-778, 885`), `_ai_category_budgets` (`:1333-1334`) and the app's `_categoriesBelowSpent` (`edit_budget_screen.dart:150`). All must key on `(main, sub)`, not just the SQL migration and the split sites.
5. **`_generate_adjusted_budgets` and `allocation_rows` read fixtures with no `sub_category` key** (e2e `test_jobs.py:124`, `test_books.py:961`, `test_ai_providers.py:4041` insert docs directly); use `.get`. Also `_append_valid_category` swallows validation errors, so the new "no `' - '` in main" validator would silently drop old-format categories rather than fail.
6. **e2e pgcompat has hard-coded `INSERT INTO budget_allocations` column list** (`pgcompat.py:236-238`); without edit, `sub_category` is never written by e2e inserts/updates.
7. **AI JSON schema is asserted by e2e** (`test_ai_providers.py:4064` required set), and `stubenv.py:269` keys the fake budget answer on the string `"allocated_amount"` in the prompt; changing the shape/prompt wording needs those updated.
8. **The stub fakes Firebase by function name** (`stubenv.patch_loaded_modules`): new send helpers are not stubbed (they would hit the "Firebase not initialized" branch and return False), `send_fcm_data_message` is already unstubbed, and the multicast fake returns `responses=[]`, so "Firebase says unregistered -> row deleted" cannot be tested without extending the stub (e.g. a recorder + a way to inject `UnregisteredError` / failed per-token responses).
9. **Firebase send helpers return `bool`/counts only**, and the single-user push runs in a worker thread (`notification_service.py:405-441`): deleting a dead device row needs a richer return (which tokens were unregistered) and an async step back on the loop.
10. **`DELETE /api/auth/fcm-token` is in the app's session-exempt paths** and `web_platform_test.dart:43-51` ("logout on Android still unregisters", expects `['old-token']` with `FCMService().fcmToken == null`) conflicts with "no push token -> skip the DELETE"; that test needs a token seam. `deleteFcmTokenOverride`'s signature is `(String authToken)`.
11. **Admin modal gets the list row, not the detail response** (`App.jsx:1258-1261`), so a device list needs `openUser` to fetch `GET /users/{id}` (or the list response to carry devices).
12. **`test_api.py:648-649`** labels `{}` body as "-> 500" but `FcmTokenUpdate` makes it a 422 today; and `test_api.py:650-652` already encodes the "token belongs to one account" rule (second account steals it) via `users.fcm_token`: all of `test_api.py:646-656` must be rewritten against `user_devices`.
13. **Change-password push token:** `ApiService.changePassword` stores the new JWT but nothing re-registers the device (`auth_provider.dart:671-691`); `reset_password` runs while possibly signed-out on that device, so device rows of the resetting person on *this* phone are also dropped (design intends this).
14. **`iconForCategoryName` matches substrings on the whole label** (`category_icons.dart:7`); the composed `"Main - Sub"` label must still be what is passed (the sub text can pick the icon today).
15. **`e2e/test_books.py` `section_migration` downgrades through the new migrations** (to `522ad619de76`) and re-upgrades with seeded data: both new migrations' downgrade/upgrade run on that data (budget rows with main-only allocations, users possibly with `fcm_token` after downgrade), so they must be reversible on populated data; `head_revision()` is read from scripts so no constant needs bumping.
