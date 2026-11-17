"""user devices

Push tokens move from users.fcm_token (one per person) into user_devices (one row per signed-in device; a token
belongs to exactly one account). Upgrade gives each non-NULL users.fcm_token a device row seen now, whose sign-in is
taken to expire 30 days from now (the real expiry is unknown; the app re-registers at its next start), then drops the
column and its unique index. Downgrade puts each person's most recently seen token back in users.fcm_token and drops
the table.

Revision ID: 7e3a91c4d5b8
Revises: b4c7576d96c6
Create Date: 2026-11-17 12:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = '7e3a91c4d5b8'
down_revision: Union[str, None] = 'b4c7576d96c6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'user_devices',
        sa.Column('id', sa.Text(), nullable=False),
        sa.Column('user_id', sa.Text(), nullable=False),
        sa.Column('token', sa.Text(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('last_seen_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('session_expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('sign_in_reminder_sent_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], name='fk_user_devices_user_id_users', ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id', name='pk_user_devices'),
        sa.UniqueConstraint('token', name='uq_user_devices_token'),
    )
    op.create_index('ix_user_devices_user_id', 'user_devices', ['user_id'], unique=False)
    # gen_random_uuid() is built in from PostgreSQL 13.
    op.execute(
        "INSERT INTO user_devices (id, user_id, token, created_at, last_seen_at, session_expires_at) "
        "SELECT gen_random_uuid()::text, id, fcm_token, now(), now(), now() + interval '30 days' "
        "FROM users WHERE fcm_token IS NOT NULL"
    )
    op.drop_index('uq_users_fcm_token', table_name='users', postgresql_where=sa.text('fcm_token IS NOT NULL'))
    op.drop_column('users', 'fcm_token')


def downgrade() -> None:
    op.add_column('users', sa.Column('fcm_token', sa.Text(), nullable=True))
    op.execute(
        "UPDATE users SET fcm_token = d.token FROM ("
        "  SELECT DISTINCT ON (user_id) user_id, token FROM user_devices"
        "  ORDER BY user_id, last_seen_at DESC, created_at DESC, id"
        ") d WHERE d.user_id = users.id"
    )
    op.create_index('uq_users_fcm_token', 'users', ['fcm_token'], unique=True,
                    postgresql_where=sa.text('fcm_token IS NOT NULL'))
    op.drop_index('ix_user_devices_user_id', table_name='user_devices')
    op.drop_table('user_devices')
