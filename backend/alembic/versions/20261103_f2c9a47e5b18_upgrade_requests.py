"""upgrade requests

Adds upgrade_requests: a user's request (from the app) to be moved to Plus or Pro, which the owner handles in the
admin panel. At most one pending request per user; handled requests are kept as history.

Revision ID: f2c9a47e5b18
Revises: e1b6d3a8f245
Create Date: 2026-11-03 09:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'f2c9a47e5b18'
down_revision: Union[str, None] = 'e1b6d3a8f245'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('upgrade_requests',
    sa.Column('id', sa.Text(), nullable=False),
    sa.Column('user_id', sa.Text(), nullable=False),
    sa.Column('plan', sa.Text(), nullable=False),
    sa.Column('note', sa.Text(), nullable=True),
    sa.Column('status', sa.Text(), server_default='pending', nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('handled_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('handled_by', sa.Text(), nullable=True),
    sa.CheckConstraint("plan IN ('plus','pro')", name=op.f('ck_upgrade_requests_plan')),
    sa.CheckConstraint("status IN ('pending','done','dismissed')", name=op.f('ck_upgrade_requests_status')),
    sa.CheckConstraint('note IS NULL OR char_length(note) <= 500', name=op.f('ck_upgrade_requests_note_length')),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_upgrade_requests_user_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_upgrade_requests'))
    )
    op.create_index(op.f('ix_upgrade_requests_user_id'), 'upgrade_requests', ['user_id'], unique=False)
    op.create_index('ix_upgrade_requests_status_created', 'upgrade_requests',
                    ['status', sa.text('created_at DESC')], unique=False)
    op.create_index('uq_upgrade_requests_pending_user', 'upgrade_requests', ['user_id'], unique=True,
                    postgresql_where=sa.text("status = 'pending'"))


def downgrade() -> None:
    op.drop_table('upgrade_requests')  # its indexes go with it
