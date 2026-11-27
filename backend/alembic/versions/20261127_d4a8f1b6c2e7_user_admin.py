"""user admin

users: suspended_at / suspended_reason / suspended_by (an admin's suspension of an account; the reason is 1-500
characters). admin_action_logs: admin_id is nullable (a failed admin sign-in has no admin row) and two indexes serve
the Logs tab filters (admin e-mail, action). Downgrade drops the columns and indexes and makes admin_id NOT NULL again
after deleting the rows whose admin_id is null.

Revision ID: d4a8f1b6c2e7
Revises: c9e3a7d1f4b2
Create Date: 2026-11-27 12:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'd4a8f1b6c2e7'
down_revision: Union[str, None] = 'c9e3a7d1f4b2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('users', sa.Column('suspended_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('suspended_reason', sa.Text(), nullable=True))
    op.add_column('users', sa.Column('suspended_by', sa.Text(), nullable=True))
    op.create_check_constraint(op.f('ck_users_suspended_reason_len'), 'users',
                               'char_length(suspended_reason) <= 500')
    op.alter_column('admin_action_logs', 'admin_id', existing_type=sa.Text(), nullable=True)
    op.create_index('ix_admin_action_logs_admin_email_ts', 'admin_action_logs',
                    [sa.text('lower(admin_email)'), sa.text('timestamp DESC')])
    op.create_index('ix_admin_action_logs_action_ts', 'admin_action_logs',
                    ['action', sa.text('timestamp DESC')])


def downgrade() -> None:
    op.drop_index('ix_admin_action_logs_action_ts', table_name='admin_action_logs')
    op.drop_index('ix_admin_action_logs_admin_email_ts', table_name='admin_action_logs')
    op.execute('DELETE FROM admin_action_logs WHERE admin_id IS NULL')
    op.alter_column('admin_action_logs', 'admin_id', existing_type=sa.Text(), nullable=False)
    op.drop_constraint(op.f('ck_users_suspended_reason_len'), 'users', type_='check')
    op.drop_column('users', 'suspended_by')
    op.drop_column('users', 'suspended_reason')
    op.drop_column('users', 'suspended_at')
