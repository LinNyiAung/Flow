"""goal entries

A goal's money moves from goals.current_amount (one number, overwritten by every Add and Withdraw) into goal_entries
(one signed row per movement; what a goal holds is their sum). Upgrade gives every goal holding money one
'carried_over' entry of its current_amount, with no member and created now (the real dates are unknown), then drops
the column and its CHECK. Downgrade puts the column back holding each goal's entry sum, re-adds the CHECK and drops the
table (the history itself is lost).

Revision ID: c1f0a8e2d93b
Revises: 7e3a91c4d5b8
Create Date: 2026-11-18 12:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'c1f0a8e2d93b'
down_revision: Union[str, None] = '7e3a91c4d5b8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'goal_entries',
        sa.Column('id', sa.Text(), nullable=False),
        sa.Column('goal_id', sa.Text(), nullable=False),
        sa.Column('kind', sa.Text(), nullable=False),
        sa.Column('amount', sa.Numeric(precision=18, scale=2), nullable=False),
        sa.Column('added_by_member_id', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.CheckConstraint("kind IN ('start','add','withdraw','carried_over')", name=op.f('ck_goal_entries_kind')),
        sa.CheckConstraint("(kind = 'withdraw' AND amount < 0) OR (kind <> 'withdraw' AND amount > 0)",
                           name=op.f('ck_goal_entries_amount_sign')),
        sa.CheckConstraint('amount > -1e16 AND amount < 1e16', name=op.f('ck_goal_entries_amount_finite')),
        sa.ForeignKeyConstraint(['goal_id'], ['goals.id'], name=op.f('fk_goal_entries_goal_id_goals'), ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['added_by_member_id'], ['family_members.id'],
                                name=op.f('fk_goal_entries_added_by_member_id_family_members'), ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id', name=op.f('pk_goal_entries')),
    )
    op.create_index('ix_goal_entries_goal_created', 'goal_entries', ['goal_id', 'created_at', 'id'], unique=False)
    op.create_index('ix_goal_entries_added_by_member_id', 'goal_entries', ['added_by_member_id'], unique=False)
    # gen_random_uuid() is built in from PostgreSQL 13.
    op.execute(
        "INSERT INTO goal_entries (id, goal_id, kind, amount, added_by_member_id, created_at) "
        "SELECT gen_random_uuid()::text, id, 'carried_over', current_amount, NULL, now() "
        "FROM goals WHERE current_amount > 0"
    )
    op.drop_constraint(op.f('ck_goals_current_non_negative_finite'), 'goals', type_='check')
    op.drop_column('goals', 'current_amount')


def downgrade() -> None:
    op.add_column('goals', sa.Column('current_amount', sa.Numeric(precision=18, scale=2), server_default='0',
                                     nullable=False))
    op.execute(
        "UPDATE goals SET current_amount = e.total FROM ("
        "  SELECT goal_id, SUM(amount) AS total FROM goal_entries GROUP BY goal_id"
        ") e WHERE e.goal_id = goals.id"
    )
    op.create_check_constraint(op.f('ck_goals_current_non_negative_finite'), 'goals',
                               'current_amount >= 0 AND current_amount < 1e16')
    op.drop_index('ix_goal_entries_added_by_member_id', table_name='goal_entries')
    op.drop_index('ix_goal_entries_goal_created', table_name='goal_entries')
    op.drop_table('goal_entries')
