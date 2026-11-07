"""plan renewal reminders

Adds users.plan_reminder_3d_for and users.plan_reminder_last_for: the plan end date (subscription_expires_at) for
which each paid-plan reminder (3 days before the plan ends, and on its last day) was sent, so the hourly job sends each
at most once per end date, and again when the admin extends the plan to a new end date.

Revision ID: a9c4f1e7b352
Revises: d6b2e8f4a1c7
Create Date: 2026-11-07 10:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'a9c4f1e7b352'
down_revision: Union[str, None] = 'd6b2e8f4a1c7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('users', sa.Column('plan_reminder_3d_for', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('plan_reminder_last_for', sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'plan_reminder_last_for')
    op.drop_column('users', 'plan_reminder_3d_for')
