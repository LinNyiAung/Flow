"""local job runs record when they finished

local_job_runs.done_at: set when a local-time job's run for its subject finished. A claim with no done_at whose
claimed_at is older than local_job_runs.STALE_AFTER was left by a process that died mid-run, and a later tick that day
claims it again (every job's own duplicate guards make a re-run safe). Existing claims are marked done at their claim
time (they ran). Downgrade drops the column.

Revision ID: f3d8a6c1e094
Revises: e7c2f9a4b815
Create Date: 2026-11-21 12:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'f3d8a6c1e094'
down_revision: Union[str, None] = 'e7c2f9a4b815'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('local_job_runs', sa.Column('done_at', sa.DateTime(timezone=True), nullable=True))
    op.execute('UPDATE local_job_runs SET done_at = claimed_at')


def downgrade() -> None:
    op.drop_column('local_job_runs', 'done_at')
