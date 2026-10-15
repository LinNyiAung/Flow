# Maintenance scripts

## `data_cleanup.py` — one-off data cleanup

Finds (and optionally fixes) legacy data that the API now tolerates but that should be
cleaned up:

| Check | Dry-run (default) | `--apply` |
|---|---|---|
| a) transactions with NaN / ±Infinity amounts | report (ids, users) | move to `quarantined_transactions` (+ `quarantine_reason`, `quarantined_at`), invalidate those users' balance cache |
| b) user e-mails differing only by case | report groups (id, e-mail, created_at, last activity, verified, #transactions) for **manual** merging | lowercase e-mails that have **no** conflict (those users must sign in again) |
| c) users without `is_verified` | report count | nothing — needs the separate `--mark-legacy-verified` flag (sets `is_verified=True`) |
| d) insights with null / empty content | report | delete them |
| e) summary | printed | printed |

It connects with `MONGODB_URL` / `DATABASE_NAME` from the backend settings (`config.py`,
which reads `backend/.env` like the app; real environment variables take precedence). The
connection string is never printed — only host:port and the database name.

### How to run

1. **Back up first**, e.g.
   `mongodump --uri "<MONGODB_URL>" --db <DATABASE_NAME> --out backup-YYYYMMDD`
2. Dry-run (changes nothing) and read the report:
   ```bash
   cd backend
   python scripts/data_cleanup.py
   ```
3. Apply the fixes (asks you to type the database name to confirm; `--yes` skips the prompt):
   ```bash
   python scripts/data_cleanup.py --apply
   ```
4. Only if you want legacy accounts without `is_verified` to be able to log in:
   ```bash
   python scripts/data_cleanup.py --mark-legacy-verified
   ```
5. Merge the case-conflicting accounts from b) by hand (the script never touches them),
   then re-run the dry-run: it should report nothing left to do. Re-running is safe
   (idempotent).

Quarantined transactions stay in `quarantined_transactions` (same `_id`), so they can be
inspected or restored manually; delete that collection once you no longer need it.
