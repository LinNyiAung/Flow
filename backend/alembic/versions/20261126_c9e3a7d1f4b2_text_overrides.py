"""text overrides

text_overrides: an admin's replacement for one server text (notification_service keys, the two emails) in one
language. replaced_default records the code default the override replaced, so the admin panel can flag an override
whose default has since changed. version is the optimistic-concurrency counter. Downgrade drops the table.

Revision ID: c9e3a7d1f4b2
Revises: b7d2e9c4a1f3
Create Date: 2026-11-26 12:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'c9e3a7d1f4b2'
down_revision: Union[str, None] = 'b7d2e9c4a1f3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'text_overrides',
        sa.Column('key', sa.Text(), nullable=False),
        sa.Column('lang', sa.Text(), nullable=False),
        sa.Column('text', sa.Text(), nullable=False),
        sa.Column('replaced_default', sa.Text(), nullable=False),
        sa.Column('version', sa.Integer(), nullable=False),
        sa.Column('updated_by', sa.Text(), nullable=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.PrimaryKeyConstraint('key', 'lang'),
    )


def downgrade() -> None:
    op.drop_table('text_overrides')
