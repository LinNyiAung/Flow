"""ai usage cost detail

Adds to ai_usage what is needed to price a call exactly and to re-price it later: served_model (the model the
provider says answered), cached_input_tokens, cache_write_tokens, audio_input_tokens (parts of input_tokens billed at
their own rates), audio_seconds (speech-to-text length), cost_estimated (tokens or duration were estimated, not
reported) and outcome ('used', 'rejected', 'cancelled'; NULL for older rows means used). Every column is nullable or
has a default, so existing rows stay valid. Run scripts/recalculate_ai_costs.py after the deploy to re-price old rows.

Revision ID: e5b7c3a9d2f6
Revises: a9c4f1e7b352
Create Date: 2026-11-07 18:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'e5b7c3a9d2f6'
down_revision: Union[str, None] = 'a9c4f1e7b352'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('ai_usage', sa.Column('served_model', sa.Text(), nullable=True))
    op.add_column('ai_usage', sa.Column('cached_input_tokens', sa.Integer(), server_default='0', nullable=False))
    op.add_column('ai_usage', sa.Column('cache_write_tokens', sa.Integer(), server_default='0', nullable=False))
    op.add_column('ai_usage', sa.Column('audio_input_tokens', sa.Integer(), server_default='0', nullable=False))
    op.add_column('ai_usage', sa.Column('audio_seconds', sa.Double(), nullable=True))
    op.add_column('ai_usage', sa.Column('cost_estimated', sa.Boolean(), server_default=sa.text('false'), nullable=False))
    op.add_column('ai_usage', sa.Column('outcome', sa.Text(), nullable=True))
    op.create_check_constraint(op.f('ck_ai_usage_outcome'), 'ai_usage',
                               "outcome IS NULL OR outcome IN ('used','rejected','cancelled')")


def downgrade() -> None:
    op.drop_constraint(op.f('ck_ai_usage_outcome'), 'ai_usage', type_='check')
    op.drop_column('ai_usage', 'outcome')
    op.drop_column('ai_usage', 'cost_estimated')
    op.drop_column('ai_usage', 'audio_seconds')
    op.drop_column('ai_usage', 'audio_input_tokens')
    op.drop_column('ai_usage', 'cache_write_tokens')
    op.drop_column('ai_usage', 'cached_input_tokens')
    op.drop_column('ai_usage', 'served_model')
