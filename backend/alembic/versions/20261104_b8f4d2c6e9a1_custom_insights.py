"""custom insights

Adds custom_insights: a Pro user's AI report on a date range they pick (optionally a preset question or a free-text
instruction). A report is created pending and moves once to ready / failed / refused; at most one pending report per user.
Also seeds the new quota feature insight_custom into plan_limits: Free and Plus locked, Pro 10 a month.

Revision ID: b8f4d2c6e9a1
Revises: a7d3e5c91f20
Create Date: 2026-11-04 09:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = 'b8f4d2c6e9a1'
down_revision: Union[str, None] = 'a7d3e5c91f20'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# (plan, feature, mode, quota, period). The defaults at the time of this migration; plans/catalog.py has the live copy.
_LIMITS = [
    ('free', 'insight_custom', 'locked', None, None),
    ('plus', 'insight_custom', 'locked', None, None),
    ('pro', 'insight_custom', 'counted', 10, 'month'),
]


def upgrade() -> None:
    op.create_table('custom_insights',
    sa.Column('id', sa.Text(), nullable=False),
    sa.Column('user_id', sa.Text(), nullable=False),
    sa.Column('start_date', sa.Date(), nullable=False),
    sa.Column('end_date', sa.Date(), nullable=False),
    sa.Column('preset', sa.Text(), nullable=True),
    sa.Column('instruction', sa.Text(), nullable=True),
    sa.Column('instruction_key', sa.Text(), server_default='', nullable=False),
    sa.Column('status', sa.Text(), server_default='pending', nullable=False),
    sa.Column('content', sa.Text(), nullable=True),
    sa.Column('content_mm', sa.Text(), nullable=True),
    sa.Column('figures', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    sa.Column('ai_provider', sa.Text(), nullable=True),
    sa.Column('ai_model', sa.Text(), nullable=True),
    sa.Column('input_tokens', sa.Integer(), nullable=True),
    sa.Column('output_tokens', sa.Integer(), nullable=True),
    sa.Column('counter_keys', postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'[]'::jsonb"), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
    sa.CheckConstraint("status IN ('pending','ready','failed','refused')", name=op.f('ck_custom_insights_status')),
    sa.CheckConstraint('end_date >= start_date', name=op.f('ck_custom_insights_date_range')),
    sa.CheckConstraint("preset IS NULL OR preset IN ('where_to_save','compare_previous','biggest_changes','budgets_goals')", name=op.f('ck_custom_insights_preset')),
    sa.CheckConstraint('instruction IS NULL OR char_length(instruction) <= 300', name=op.f('ck_custom_insights_instruction_length')),
    sa.CheckConstraint('preset IS NULL OR instruction IS NULL', name=op.f('ck_custom_insights_preset_or_instruction')),
    sa.CheckConstraint("status <> 'ready' OR (content IS NOT NULL AND btrim(content) <> '')", name=op.f('ck_custom_insights_ready_has_content')),
    sa.CheckConstraint("deleted_at IS NULL OR status IN ('failed','refused')", name=op.f('ck_custom_insights_deleted_only_failed_refused')),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_custom_insights_user_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_custom_insights'))
    )
    op.create_index(op.f('ix_custom_insights_user_id'), 'custom_insights', ['user_id'], unique=False)
    op.create_index('ix_custom_insights_user_created', 'custom_insights', ['user_id', sa.text('created_at DESC')], unique=False)
    op.create_index('uq_custom_insights_pending_user', 'custom_insights', ['user_id'], unique=True,
                    postgresql_where=sa.text("status = 'pending'"))

    plan_limits = sa.table('plan_limits', sa.column('plan', sa.Text), sa.column('feature', sa.Text),
                           sa.column('mode', sa.Text), sa.column('quota', sa.Integer), sa.column('period', sa.Text))
    op.bulk_insert(plan_limits, [dict(plan=p, feature=f, mode=m, quota=q, period=per) for p, f, m, q, per in _LIMITS])


def downgrade() -> None:
    op.drop_table('custom_insights')  # its indexes go with it
    op.execute("DELETE FROM plan_limits WHERE feature = 'insight_custom'")
    op.execute("DELETE FROM usage_counters WHERE feature = 'insight_custom'")
