"""drop the budget "ending soon" flag

budgets.ending_soon_notified / ending_soon_notified_at were the once-per-budget guard of the "budget ending soon"
notice. Since calendar dates (d4b7e1a9c260) that notice is guarded per person by the notice itself, so nothing reads or
sets them. Downgrade adds them back unset (false, NULL): the old code then sends at most one more "ending soon" notice
per running budget.

Revision ID: e7c2f9a4b815
Revises: d4b7e1a9c260
Create Date: 2026-11-19 12:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'e7c2f9a4b815'
down_revision: Union[str, None] = 'd4b7e1a9c260'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_column('budgets', 'ending_soon_notified_at')
    op.drop_column('budgets', 'ending_soon_notified')


def downgrade() -> None:
    op.add_column('budgets', sa.Column('ending_soon_notified', sa.Boolean(), server_default=sa.text('false'),
                                       nullable=False))
    op.add_column('budgets', sa.Column('ending_soon_notified_at', sa.DateTime(timezone=True), nullable=True))
