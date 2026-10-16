# End-to-end tests

Runs the Flutter app's integration suite (`frontend/integration_test/`) on an
Android emulator against a local copy of the backend in which every external
service is stubbed. Nothing touches production: `.env` is never read, PostgreSQL
is a throwaway local cluster (`e2e/.data/pg`, database `flow_e2e`), and OpenAI, Gemini, SMTP and
Firebase are replaced with in-process fakes (`stubenv.py`). Outgoing e-mails
are written to `outbox.jsonl`; the tests read verification links and reset
codes from it through `outbox_server.py`.

## Run

```powershell
.\e2e\run_e2e.ps1 -Python <python with backend deps + httpx + psycopg> -PgBin <folder with initdb/pg_ctl/psql>
```

| Option | Effect |
| --- | --- |
| `-Name "^(04 Recurring\|05 Budgets) "` | Run only matching groups/tests (`flutter test --name`) |
| `-LargeText -Name "^14 Large text tour "` | Android font scale 1.3 and enable the large-text tour |
| `-Avd Small_Phone` | Emulator to boot if none is running |
| `-KeepRunning` | Leave PostgreSQL, the backend and the emulator up afterwards |

The script reuses anything already listening on 54329 (PostgreSQL), 8765 (backend)
and 8766 (outbox helper), applies the schema (`alembic upgrade head`), re-seeds five accounts (`seed_rich.py`), grants the
app's notification permission as soon as `flutter test` installs it (otherwise
Android's prompt blocks the first launch), and prints a pass/fail summary.
Full output is in `e2e/logs/flutter.log`.

## Files

- `stubenv.py`: isolation and fakes; import before any backend module.
- `pgcompat.py`: lets the suites read and write the PostgreSQL tables with pymongo-style calls; direct inserts go through the production migration converters.
- `run_backend_suite.py`: runs every backend API/job suite against the running server and prints a summary.
- `run_server.py`: backend on 127.0.0.1:8765 (`E2E_FAKE_AI=1` makes OpenAI calls succeed with canned replies; Gemini always fails).
- `seed_rich.py`: resets user data and creates the test accounts (premium, free, Myanmar-language, empty, delete-me) with transactions, budgets, goals, insights and notifications.
- `outbox_server.py`: serves `outbox.jsonl` to the emulator at `http://10.0.2.2:8766/outbox`.
