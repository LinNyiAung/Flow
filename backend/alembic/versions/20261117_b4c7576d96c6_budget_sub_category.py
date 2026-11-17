"""budget sub category

Adds budget_allocations.sub_category (NULL for a main-only line). Upgrade splits every "Main - Sub" main_category
on its first ' - ': main_category keeps the text before it, sub_category gets the text after it (NULL, never '', when
nothing follows the separator). Downgrade rejoins
them as main_category || ' - ' || sub_category and drops the column.

Revision ID: b4c7576d96c6
Revises: d846defddc6e
Create Date: 2026-11-17 09:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'b4c7576d96c6'
down_revision: Union[str, None] = 'd846defddc6e'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('budget_allocations', sa.Column('sub_category', sa.Text(), nullable=True))
    op.execute(
        "UPDATE budget_allocations "
        "SET sub_category = NULLIF(substr(main_category, strpos(main_category, ' - ') + 3), ''), "
        "    main_category = substr(main_category, 1, strpos(main_category, ' - ') - 1) "
        "WHERE strpos(main_category, ' - ') > 0"
    )


def downgrade() -> None:
    op.execute(
        "UPDATE budget_allocations SET main_category = main_category || ' - ' || sub_category "
        "WHERE sub_category IS NOT NULL"
    )
    op.drop_column('budget_allocations', 'sub_category')
