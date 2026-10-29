"""ai provider switching

Adds the admin-panel AI settings and provider status tables, records which provider a fallback
came from on ai_usage, and lets insights be stored for the 'claude' provider.

Revision ID: a3f1c7d92b64
Revises: 799d29a14d00
Create Date: 2026-10-29 10:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = 'a3f1c7d92b64'
down_revision: Union[str, None] = '799d29a14d00'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('ai_feature_settings',
    sa.Column('feature', sa.Text(), nullable=False),
    sa.Column('main_provider', sa.Text(), nullable=False),
    sa.Column('main_model', sa.Text(), nullable=False),
    sa.Column('backups', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_by', sa.Text(), nullable=True),
    sa.PrimaryKeyConstraint('feature', name=op.f('pk_ai_feature_settings'))
    )
    op.create_table('ai_provider_status',
    sa.Column('provider', sa.Text(), nullable=False),
    sa.Column('last_error', sa.Text(), nullable=True),
    sa.Column('last_error_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('last_success_at', sa.DateTime(timezone=True), nullable=True),
    sa.PrimaryKeyConstraint('provider', name=op.f('pk_ai_provider_status'))
    )
    op.add_column('ai_usage', sa.Column('fallback_from', sa.Text(), nullable=True))
    op.create_check_constraint(op.f('ck_ai_usage_fallback_from'), 'ai_usage',
                               "fallback_from IS NULL OR fallback_from IN ('openai','gemini','claude')")
    op.drop_constraint(op.f('ck_insights_ai_provider'), 'insights', type_='check')
    op.create_check_constraint(op.f('ck_insights_ai_provider'), 'insights',
                               "ai_provider IN ('openai','gemini','claude')")


def downgrade() -> None:
    # Claude insights cannot exist under the old constraint.
    op.execute("DELETE FROM insights WHERE ai_provider = 'claude'")
    op.drop_constraint(op.f('ck_insights_ai_provider'), 'insights', type_='check')
    op.create_check_constraint(op.f('ck_insights_ai_provider'), 'insights',
                               "ai_provider IN ('openai','gemini')")
    op.drop_constraint(op.f('ck_ai_usage_fallback_from'), 'ai_usage', type_='check')
    op.drop_column('ai_usage', 'fallback_from')
    op.drop_table('ai_provider_status')
    op.drop_table('ai_feature_settings')
