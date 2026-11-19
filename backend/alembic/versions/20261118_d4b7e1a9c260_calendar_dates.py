"""calendar dates

The fake-UTC dates become honest types (schema project #4). Today's values are the phone's wall clock with a UTC label,
so dropping the label gives back exactly what each person entered:
- transactions.date: timestamptz -> timestamp without time zone (the local date and time as entered);
- transactions.recurrence_end_date / recurrence_last_created_date, budgets.start_date / end_date, goals.target_date and
  the insights' week / month bounds: timestamptz -> DATE (the UTC-labelled day). A budget's end becomes its inclusive
  last day: an end stored at 00:00 keeps its date (that day is now included), one at 23:59:59.999 keeps its date; a
  start time that isn't midnight widens to its whole day.
Adds users.timezone (an IANA name; NULL means the default zone), users.timezone_changed_at (when it was last saved: it
may change at most once per 24 hours) and local_job_runs (one claim per local-time job, subject and local date; indexed
on local_date).

Downgrade labels the values UTC again: a wall-clock value as that UTC time, a budget end as 23:59:59.999999 of its day
(the convention monthly and yearly budgets use), a recurring parent's last-created pointer as its day at the parent's
time (the old code takes the next occurrence's time from it) and every other date as midnight UTC; then drops users.timezone,
users.timezone_changed_at and local_job_runs. Each table is converted in one ALTER TABLE, so its CHECKs (budgets dates_ordered) and indexes are
rebuilt on the new types.

Revision ID: d4b7e1a9c260
Revises: c1f0a8e2d93b
Create Date: 2026-11-18 18:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'd4b7e1a9c260'
down_revision: Union[str, None] = 'c1f0a8e2d93b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_INSIGHT_BOUNDS = ('week_start', 'week_end', 'month_start', 'month_end')


def _to_day(column: str) -> str:
    return f'ALTER COLUMN {column} TYPE date USING ({column} AT TIME ZONE \'UTC\')::date'


def _to_midnight_utc(column: str) -> str:
    return f'ALTER COLUMN {column} TYPE timestamptz USING {column}::timestamp AT TIME ZONE \'UTC\''


def upgrade() -> None:
    # The old backend may still be serving: take every table's lock up front, in one order, before converting any.
    op.execute("LOCK TABLE transactions, budgets, goals, insights IN ACCESS EXCLUSIVE MODE")
    op.execute('ALTER TABLE transactions '
               'ALTER COLUMN "date" TYPE timestamp without time zone USING "date" AT TIME ZONE \'UTC\', '
               f'{_to_day("recurrence_end_date")}, {_to_day("recurrence_last_created_date")}')
    op.execute(f'ALTER TABLE budgets {_to_day("start_date")}, {_to_day("end_date")}')
    op.execute(f'ALTER TABLE goals {_to_day("target_date")}')
    op.execute('ALTER TABLE insights ' + ', '.join(_to_day(c) for c in _INSIGHT_BOUNDS))

    op.add_column('users', sa.Column('timezone', sa.Text(), nullable=True))
    op.add_column('users', sa.Column('timezone_changed_at', sa.DateTime(timezone=True), nullable=True))
    op.create_table(
        'local_job_runs',
        sa.Column('job', sa.Text(), nullable=False),
        sa.Column('subject_id', sa.Text(), nullable=False),
        sa.Column('local_date', sa.Date(), nullable=False),
        sa.Column('claimed_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.PrimaryKeyConstraint('job', 'subject_id', 'local_date', name=op.f('pk_local_job_runs')),
    )
    # The tick's claimed_since and forget_before filter on local_date alone (the primary key leads with job).
    op.create_index('ix_local_job_runs_local_date', 'local_job_runs', ['local_date'])


def downgrade() -> None:
    op.execute("LOCK TABLE transactions, budgets, goals, insights IN ACCESS EXCLUSIVE MODE")
    op.drop_index('ix_local_job_runs_local_date', table_name='local_job_runs')
    op.drop_table('local_job_runs')
    op.drop_column('users', 'timezone_changed_at')
    op.drop_column('users', 'timezone')

    # The old code takes the next occurrence's time of day from the last-created pointer, so the pointer goes back at
    # the parent's time (every occurrence keeps it), not midnight. Its own ALTER, while "date" is still the naive
    # wall clock.
    op.execute('ALTER TABLE transactions ALTER COLUMN recurrence_last_created_date TYPE timestamptz '
               'USING (recurrence_last_created_date + "date"::time) AT TIME ZONE \'UTC\'')
    op.execute('ALTER TABLE transactions '
               'ALTER COLUMN "date" TYPE timestamptz USING "date" AT TIME ZONE \'UTC\', '
               f'{_to_midnight_utc("recurrence_end_date")}')
    op.execute(f'ALTER TABLE budgets {_to_midnight_utc("start_date")}, '
               'ALTER COLUMN end_date TYPE timestamptz USING (end_date + time \'23:59:59.999999\') AT TIME ZONE \'UTC\'')
    op.execute(f'ALTER TABLE goals {_to_midnight_utc("target_date")}')
    op.execute('ALTER TABLE insights ' + ', '.join(_to_midnight_utc(c) for c in _INSIGHT_BOUNDS))
