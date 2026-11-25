"""announcements table

App control: notices the owner shows inside the app to the users of chosen plans between two instants. Downgrade drops
the table.

Revision ID: b7d2e9c4a1f3
Revises: f3d8a6c1e094
Create Date: 2026-11-25 12:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = 'b7d2e9c4a1f3'
down_revision: Union[str, None] = 'f3d8a6c1e094'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'announcements',
        sa.Column('id', sa.Text(), nullable=False),
        sa.Column('text_en', sa.Text(), nullable=False),
        sa.Column('text_my', sa.Text(), nullable=False),
        sa.Column('style', sa.Text(), nullable=False),
        sa.Column('link_url', sa.Text(), nullable=True),
        sa.Column('link_label_en', sa.Text(), nullable=True),
        sa.Column('link_label_my', sa.Text(), nullable=True),
        sa.Column('plans', postgresql.ARRAY(sa.Text()), nullable=False),
        sa.Column('starts_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('ends_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_by', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.CheckConstraint("style IN ('info','warning')", name=op.f('ck_announcements_style')),
        sa.PrimaryKeyConstraint('id', name=op.f('pk_announcements')),
    )


def downgrade() -> None:
    op.drop_table('announcements')
