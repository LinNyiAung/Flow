"""upgrade request contact: the user's Viber number

Adds upgrade_requests.viber_number, the number the user gave on their request so the owner can contact them on Viber
(null: the owner uses the account email).

Revision ID: a7d3e5c91f20
Revises: f2c9a47e5b18
Create Date: 2026-11-03 14:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'a7d3e5c91f20'
down_revision: Union[str, None] = 'f2c9a47e5b18'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('upgrade_requests', sa.Column('viber_number', sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column('upgrade_requests', 'viber_number')
