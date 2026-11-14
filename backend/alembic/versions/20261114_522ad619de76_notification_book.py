"""notification book

Adds notifications.book: 'family' on the notices a family book sends to its members (budget and goal notices, insights
ready, and the recurring and custom-insight notices for a family entry or report), so the app can switch to the
family book before opening the budget, goal or report. NULL for personal notifications (and every existing row).

Revision ID: 522ad619de76
Revises: f3a9c1d7b5e2
Create Date: 2026-11-14 09:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = '522ad619de76'
down_revision: Union[str, None] = 'f3a9c1d7b5e2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('notifications', sa.Column('book', sa.Text(), nullable=True))
    op.create_check_constraint(op.f('ck_notifications_book'), 'notifications', "book IS NULL OR book = 'family'")


def downgrade() -> None:
    op.drop_constraint(op.f('ck_notifications_book'), 'notifications', type_='check')
    op.drop_column('notifications', 'book')
