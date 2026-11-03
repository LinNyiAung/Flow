"""plans and quotas

Replaces the Free/Premium subscription with Free, Plus and Pro. Existing premium users become plus (their
expiry is kept). Adds the owner-editable plan limits and cost caps (seeded with the defaults), an app settings
table, per-user usage counters, and the users.trial_ends_at / users.usage_reset_at columns.

Revision ID: c4e8b1a05d37
Revises: a3f1c7d92b64
Create Date: 2026-11-02 09:00:00.000000
"""
from decimal import Decimal
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'c4e8b1a05d37'
down_revision: Union[str, None] = 'a3f1c7d92b64'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# (plan, feature, mode, quota, period). The defaults at the time of this migration; plans/catalog.py has the
# live copy (e2e/test_plans.py checks they agree on a fresh database).
_LIMITS = [
    ('free', 'chat', 'counted', 5, 'week'),
    ('free', 'chat_advanced', 'locked', None, None),
    ('free', 'insight_monthly', 'counted', 1, 'month'),
    ('free', 'insight_weekly', 'locked', None, None),
    ('free', 'insight_translation', 'locked', None, None),
    ('free', 'entry', 'counted', 10, 'month'),
    ('free', 'budget_suggestion', 'counted', 1, 'month'),
    ('free', 'reports', 'locked', None, None),
    ('plus', 'chat', 'counted', 100, 'month'),
    ('plus', 'chat_advanced', 'locked', None, None),
    ('plus', 'insight_monthly', 'included', None, None),
    ('plus', 'insight_weekly', 'included', None, None),
    ('plus', 'insight_translation', 'included', None, None),
    ('plus', 'entry', 'counted', 150, 'month'),
    ('plus', 'budget_suggestion', 'counted', 5, 'month'),
    ('plus', 'reports', 'included', None, None),
    ('pro', 'chat', 'counted', 400, 'month'),
    ('pro', 'chat_advanced', 'counted', 100, 'month'),
    ('pro', 'insight_monthly', 'included', None, None),
    ('pro', 'insight_weekly', 'included', None, None),
    ('pro', 'insight_translation', 'included', None, None),
    ('pro', 'entry', 'counted', 500, 'month'),
    ('pro', 'budget_suggestion', 'counted', 20, 'month'),
    ('pro', 'reports', 'included', None, None),
]
_COST_CAPS = [('free', Decimal('0.10')), ('plus', Decimal('1.00')), ('pro', Decimal('3.00'))]


def upgrade() -> None:
    # premium -> plus, keeping subscription_expires_at (NULL stays lifetime).
    op.drop_constraint(op.f('ck_users_subscription_type'), 'users', type_='check')
    op.execute("UPDATE users SET subscription_type = 'plus' WHERE subscription_type = 'premium'")
    op.create_check_constraint(op.f('ck_users_subscription_type'), 'users',
                               "subscription_type IN ('free','plus','pro')")
    op.add_column('users', sa.Column('trial_ends_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('usage_reset_at', sa.DateTime(timezone=True), nullable=True))

    plan_limits = op.create_table('plan_limits',
    sa.Column('plan', sa.Text(), nullable=False),
    sa.Column('feature', sa.Text(), nullable=False),
    sa.Column('mode', sa.Text(), nullable=False),
    sa.Column('quota', sa.Integer(), nullable=True),
    sa.Column('period', sa.Text(), nullable=True),
    sa.CheckConstraint("plan IN ('free','plus','pro')", name=op.f('ck_plan_limits_plan')),
    sa.CheckConstraint("mode IN ('locked','included','counted')", name=op.f('ck_plan_limits_mode')),
    sa.CheckConstraint("period IS NULL OR period IN ('week','month')", name=op.f('ck_plan_limits_period')),
    sa.CheckConstraint("mode <> 'counted' OR (quota IS NOT NULL AND quota >= 0 AND period IS NOT NULL)",
                       name=op.f('ck_plan_limits_counted_complete')),
    sa.PrimaryKeyConstraint('plan', 'feature', name=op.f('pk_plan_limits'))
    )
    plan_settings = op.create_table('plan_settings',
    sa.Column('plan', sa.Text(), nullable=False),
    sa.Column('cost_cap_usd', sa.Numeric(precision=12, scale=6), nullable=False),
    sa.CheckConstraint("plan IN ('free','plus','pro')", name=op.f('ck_plan_settings_plan')),
    sa.CheckConstraint('cost_cap_usd >= 0', name=op.f('ck_plan_settings_cost_cap_non_negative')),
    sa.PrimaryKeyConstraint('plan', name=op.f('pk_plan_settings'))
    )
    op.create_table('app_settings',
    sa.Column('key', sa.Text(), nullable=False),
    sa.Column('value', sa.Text(), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.PrimaryKeyConstraint('key', name=op.f('pk_app_settings'))
    )
    op.create_table('usage_counters',
    sa.Column('user_id', sa.Text(), nullable=False),
    sa.Column('feature', sa.Text(), nullable=False),
    sa.Column('period', sa.Text(), nullable=False),
    sa.Column('period_start', sa.Date(), nullable=False),
    sa.Column('used', sa.Integer(), server_default='0', nullable=False),
    sa.CheckConstraint("period IN ('week','month')", name=op.f('ck_usage_counters_period')),
    sa.CheckConstraint('used >= 0', name=op.f('ck_usage_counters_used_non_negative')),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_usage_counters_user_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('user_id', 'feature', 'period', 'period_start', name=op.f('pk_usage_counters'))
    )

    op.bulk_insert(plan_limits, [dict(plan=p, feature=f, mode=m, quota=q, period=per) for p, f, m, q, per in _LIMITS])
    op.bulk_insert(plan_settings, [dict(plan=p, cost_cap_usd=c) for p, c in _COST_CAPS])


def downgrade() -> None:
    op.drop_table('usage_counters')
    op.drop_table('app_settings')
    op.drop_table('plan_settings')
    op.drop_table('plan_limits')
    op.drop_column('users', 'usage_reset_at')
    op.drop_column('users', 'trial_ends_at')
    # Plus and Pro both become the old single paid plan, keeping subscription_expires_at.
    op.drop_constraint(op.f('ck_users_subscription_type'), 'users', type_='check')
    op.execute("UPDATE users SET subscription_type = 'premium' WHERE subscription_type IN ('plus','pro')")
    op.create_check_constraint(op.f('ck_users_subscription_type'), 'users',
                               "subscription_type IN ('free','premium')")
