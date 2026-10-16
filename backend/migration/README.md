# MongoDB → PostgreSQL data migration

One-time copy of the production data into PostgreSQL. `run.py` reads a `mongodump`
folder (or a live MongoDB), converts every document with `convert.py`, and writes
everything in **one transaction** that is verified before it commits. It is a dry run
unless you pass `--write`.

```bash
cd backend
pip install -r requirements.txt -r migration/requirements.txt
```

## What it does with problem data

| Situation | What happens |
| --- | --- |
| Row that can't be valid (NaN / negative amount, no date, unknown currency, insight without text, admin with an unknown role, …) | Copied unchanged into `quarantined_records` with the reason; not used by the app |
| Row whose owner account no longer exists | Same (reason "owner account no longer exists") |
| Link to a deleted recurring transaction / budget | Link cleared, row kept |
| Same device token on several accounts | Kept on the newest account (the device re-registers it) |
| Duplicate notification preferences / app versions | Newest kept, others set aside |
| Two accounts whose e-mails differ only by letter case | **Stops the run** (exit code 2) and lists them: merge or delete in MongoDB first |

The report ends with every user whose balance differs from what the old app showed and
the documents that cause it (for example a negative amount that the old app counted, or
a transaction without a currency that it left out).

After writing, it re-reads the row counts and the per-user/currency transaction, goal
and budget totals from PostgreSQL. If anything differs from the plan, the whole
transaction is rolled back (exit code 3) and nothing changes.

## Rehearsal (do this first, as often as needed)

1. Make a dump of production. This only reads from MongoDB:
   ```bash
   mongodump --uri "<MONGODB_URL>" --db <DATABASE_NAME> --out dump-YYYYMMDD
   ```
2. Dry run against it and keep the report:
   ```bash
   python -m migration.run --dump dump-YYYYMMDD/<DATABASE_NAME> --report rehearsal.json
   ```
3. Resolve anything listed under **BLOCKING** in MongoDB, then repeat.
4. Optionally write into a local database and click through the app against it:
   ```bash
   alembic upgrade head                      # with DATABASE_URL pointing at the local database
   python -m migration.run --dump dump-YYYYMMDD/<DATABASE_NAME> --database-url <local url> --write
   ```

## Cutover on Render

1. Create the Render PostgreSQL database. A paid plan includes backups.
2. On the backend service, set **Pre-Deploy Command** to `alembic upgrade head`, so
   every deploy applies schema changes first.
3. From your machine, using the database's **External** URL:
   ```bash
   DATABASE_URL=<external url> alembic upgrade head
   ```
4. **Maintenance window starts:** suspend the backend service. This stops the API and the
   scheduled jobs, so nothing writes to MongoDB any more.
5. Take a fresh `mongodump`. It is both the migration source and your backup.
6. Run the migration. It must end with "written and verified":
   ```bash
   python -m migration.run --dump dump-YYYYMMDD/<DATABASE_NAME> --database-url <external url> --write --report cutover.json
   ```
7. Set `DATABASE_URL` on the backend service to the **Internal** URL, deploy the
   PostgreSQL version and resume the service.
8. Smoke test: log in, check the dashboard balance, add and delete a transaction,
   contribute to a goal, open budgets, send an AI chat message, open the admin panel.

**Rollback:** MongoDB is not modified by any of this. Redeploy the previous version with
`MONGODB_URL` set. Anything users entered after the cutover exists only in PostgreSQL.

## Afterwards (after a few quiet weeks)

- Remove `MONGODB_URL` / `DATABASE_NAME` from Render and `config.py`.
- Delete this folder and `scripts/data_cleanup.py`.
- Delete the MongoDB cluster. Keep the last dump somewhere safe.
