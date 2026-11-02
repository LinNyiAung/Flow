"""trial reminders

Adds users.trial_reminder_3d_at and users.trial_reminder_last_at: when each Plus-trial reminder (3 days before the
trial ends, and on its last day) was sent, so the hourly job sends each at most once.

Revision ID: e1b6d3a8f245
Revises: c4e8b1a05d37
Create Date: 2026-11-02 15:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'e1b6d3a8f245'
down_revision: Union[str, None] = 'c4e8b1a05d37'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('users', sa.Column('trial_reminder_3d_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('trial_reminder_last_at', sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'trial_reminder_last_at')
    op.drop_column('users', 'trial_reminder_3d_at')
