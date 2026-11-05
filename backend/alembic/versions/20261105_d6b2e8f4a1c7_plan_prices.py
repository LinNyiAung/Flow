"""plan prices in MMK, and the billing period on upgrade requests

Adds plan_settings.price_monthly_mmk and plan_settings.price_yearly_mmk, the prices the owner sets for Plus and Pro
(null: not set; Free never has one; a yearly price needs a monthly price), and upgrade_requests.billing, the period the
user picked on their request ('month' / 'year'; null: no price was shown). Nothing is seeded.

Revision ID: d6b2e8f4a1c7
Revises: b8f4d2c6e9a1
Create Date: 2026-11-05 09:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'd6b2e8f4a1c7'
down_revision: Union[str, None] = 'b8f4d2c6e9a1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_PRICE_CHECKS = [
    ('price_monthly_positive', 'price_monthly_mmk IS NULL OR price_monthly_mmk > 0'),
    ('price_yearly_positive', 'price_yearly_mmk IS NULL OR price_yearly_mmk > 0'),
    ('free_has_no_price', "plan <> 'free' OR (price_monthly_mmk IS NULL AND price_yearly_mmk IS NULL)"),
    ('yearly_needs_monthly', 'price_yearly_mmk IS NULL OR price_monthly_mmk IS NOT NULL'),
]


def upgrade() -> None:
    op.add_column('plan_settings', sa.Column('price_monthly_mmk', sa.Integer(), nullable=True))
    op.add_column('plan_settings', sa.Column('price_yearly_mmk', sa.Integer(), nullable=True))
    for name, condition in _PRICE_CHECKS:
        op.create_check_constraint(op.f(f'ck_plan_settings_{name}'), 'plan_settings', condition)
    op.add_column('upgrade_requests', sa.Column('billing', sa.Text(), nullable=True))
    op.create_check_constraint(op.f('ck_upgrade_requests_billing'), 'upgrade_requests',
                               "billing IS NULL OR billing IN ('month','year')")


def downgrade() -> None:
    op.drop_constraint(op.f('ck_upgrade_requests_billing'), 'upgrade_requests', type_='check')
    op.drop_column('upgrade_requests', 'billing')
    for name, _ in _PRICE_CHECKS:
        op.drop_constraint(op.f(f'ck_plan_settings_{name}'), 'plan_settings', type_='check')
    op.drop_column('plan_settings', 'price_yearly_mmk')
    op.drop_column('plan_settings', 'price_monthly_mmk')
