"""family book

Adds the family book schema. Each family owns a hidden users row (users.kind = 'family_book'); the family's
transactions, budgets, goals and insights are stored under that user id. Adds families, family_members (account members
and placeholders), family_invites and transaction_beneficiaries; transactions.added_by_member_id and transfer_id;
chat_sessions.book_id; and plan_settings.family_max_members / family_max_placeholders (free 0/0, plus 6/20, pro 6/20).

Revision ID: f3a9c1d7b5e2
Revises: e5b7c3a9d2f6
Create Date: 2026-11-13 09:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'f3a9c1d7b5e2'
down_revision: Union[str, None] = 'e5b7c3a9d2f6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# (plan, family_max_members, family_max_placeholders)
_LIMITS = [('free', 0, 0), ('plus', 6, 20), ('pro', 6, 20)]


def upgrade() -> None:
    op.add_column('users', sa.Column('kind', sa.Text(), server_default='person', nullable=False))
    op.create_check_constraint(op.f('ck_users_kind'), 'users', "kind IN ('person','family_book')")

    op.create_table('families',
    sa.Column('id', sa.Text(), nullable=False),
    sa.Column('name', sa.Text(), nullable=False),
    sa.Column('book_user_id', sa.Text(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['book_user_id'], ['users.id'], name=op.f('fk_families_book_user_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_families')),
    sa.UniqueConstraint('book_user_id', name=op.f('uq_families_book_user_id'))
    )

    op.create_table('family_members',
    sa.Column('id', sa.Text(), nullable=False),
    sa.Column('family_id', sa.Text(), nullable=False),
    sa.Column('user_id', sa.Text(), nullable=True),
    sa.Column('display_name', sa.Text(), nullable=False),
    sa.Column('kind', sa.Text(), nullable=False),
    sa.Column('role', sa.Text(), nullable=True),
    sa.Column('status', sa.Text(), server_default='active', nullable=False),
    sa.Column('joined_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('left_at', sa.DateTime(timezone=True), nullable=True),
    sa.CheckConstraint("kind IN ('account','placeholder')", name=op.f('ck_family_members_kind')),
    sa.CheckConstraint("role IS NULL OR role IN ('owner','admin','member')", name=op.f('ck_family_members_role')),
    sa.CheckConstraint("status IN ('active','former')", name=op.f('ck_family_members_status')),
    sa.ForeignKeyConstraint(['family_id'], ['families.id'], name=op.f('fk_family_members_family_id_families'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_family_members_user_id_users'), ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_family_members'))
    )
    op.create_index(op.f('ix_family_members_family_id'), 'family_members', ['family_id'], unique=False)
    op.create_index(op.f('ix_family_members_user_id'), 'family_members', ['user_id'], unique=False)
    # One family per person, and one owner per family.
    op.create_index('uq_family_members_user_active', 'family_members', ['user_id'], unique=True,
                    postgresql_where=sa.text("status = 'active' AND user_id IS NOT NULL"))
    op.create_index('uq_family_members_owner_active', 'family_members', ['family_id'], unique=True,
                    postgresql_where=sa.text("role = 'owner' AND status = 'active'"))

    op.create_table('family_invites',
    sa.Column('id', sa.Text(), nullable=False),
    sa.Column('family_id', sa.Text(), nullable=False),
    sa.Column('email', sa.Text(), nullable=False),
    sa.Column('invited_by_member_id', sa.Text(), nullable=True),
    sa.Column('link_member_id', sa.Text(), nullable=True),
    sa.Column('status', sa.Text(), server_default='pending', nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
    sa.CheckConstraint("status IN ('pending','accepted','declined','cancelled','expired')", name=op.f('ck_family_invites_status')),
    sa.ForeignKeyConstraint(['family_id'], ['families.id'], name=op.f('fk_family_invites_family_id_families'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['invited_by_member_id'], ['family_members.id'], name=op.f('fk_family_invites_invited_by_member_id_family_members'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['link_member_id'], ['family_members.id'], name=op.f('fk_family_invites_link_member_id_family_members'), ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_family_invites'))
    )
    op.create_index(op.f('ix_family_invites_family_id'), 'family_invites', ['family_id'], unique=False)
    op.create_index('uq_family_invites_pending_email', 'family_invites', ['family_id', 'email'], unique=True,
                    postgresql_where=sa.text("status = 'pending'"))

    op.add_column('transactions', sa.Column('added_by_member_id', sa.Text(), nullable=True))
    op.add_column('transactions', sa.Column('transfer_id', sa.Text(), nullable=True))
    op.create_foreign_key(op.f('fk_transactions_added_by_member_id_family_members'), 'transactions', 'family_members',
                          ['added_by_member_id'], ['id'], ondelete='SET NULL')
    op.create_index('ix_transactions_transfer_id', 'transactions', ['transfer_id'], unique=False)
    # The SET NULL foreign key's index: deleting a member row then doesn't scan every transaction.
    op.create_index('ix_transactions_added_by_member_id', 'transactions', ['added_by_member_id'], unique=False)

    op.create_table('transaction_beneficiaries',
    sa.Column('transaction_id', sa.Text(), nullable=False),
    sa.Column('member_id', sa.Text(), nullable=False),
    sa.ForeignKeyConstraint(['transaction_id'], ['transactions.id'], name=op.f('fk_transaction_beneficiaries_transaction_id_transactions'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['member_id'], ['family_members.id'], name=op.f('fk_transaction_beneficiaries_member_id_family_members'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('transaction_id', 'member_id', name=op.f('pk_transaction_beneficiaries'))
    )
    op.create_index(op.f('ix_transaction_beneficiaries_member_id'), 'transaction_beneficiaries', ['member_id'], unique=False)

    op.add_column('chat_sessions', sa.Column('book_id', sa.Text(), nullable=True))
    op.create_foreign_key(op.f('fk_chat_sessions_book_id_users'), 'chat_sessions', 'users', ['book_id'], ['id'], ondelete='CASCADE')
    # The CASCADE foreign key's index: deleting a book user (a family) then doesn't scan every chat session.
    op.create_index('ix_chat_sessions_book_id', 'chat_sessions', ['book_id'], unique=False)

    op.add_column('plan_settings', sa.Column('family_max_members', sa.SmallInteger(), server_default='0', nullable=False))
    op.add_column('plan_settings', sa.Column('family_max_placeholders', sa.SmallInteger(), server_default='0', nullable=False))
    op.create_check_constraint(op.f('ck_plan_settings_family_max_members_range'), 'plan_settings',
                               'family_max_members BETWEEN 0 AND 50')
    op.create_check_constraint(op.f('ck_plan_settings_family_max_placeholders_range'), 'plan_settings',
                               'family_max_placeholders BETWEEN 0 AND 50')
    for plan, members, placeholders in _LIMITS:
        op.execute(sa.text(
            "UPDATE plan_settings SET family_max_members = :m, family_max_placeholders = :p WHERE plan = :plan"
        ).bindparams(m=members, p=placeholders, plan=plan))


def downgrade() -> None:
    op.drop_constraint(op.f('ck_plan_settings_family_max_placeholders_range'), 'plan_settings', type_='check')
    op.drop_constraint(op.f('ck_plan_settings_family_max_members_range'), 'plan_settings', type_='check')
    op.drop_column('plan_settings', 'family_max_placeholders')
    op.drop_column('plan_settings', 'family_max_members')

    op.drop_index('ix_chat_sessions_book_id', table_name='chat_sessions')
    op.drop_constraint(op.f('fk_chat_sessions_book_id_users'), 'chat_sessions', type_='foreignkey')
    op.drop_column('chat_sessions', 'book_id')

    op.drop_table('transaction_beneficiaries')  # its index goes with it
    op.drop_index('ix_transactions_added_by_member_id', table_name='transactions')
    op.drop_index('ix_transactions_transfer_id', table_name='transactions')
    op.drop_constraint(op.f('fk_transactions_added_by_member_id_family_members'), 'transactions', type_='foreignkey')
    op.drop_column('transactions', 'transfer_id')
    op.drop_column('transactions', 'added_by_member_id')

    op.drop_table('family_invites')
    op.drop_table('family_members')
    op.drop_table('families')

    op.drop_constraint(op.f('ck_users_kind'), 'users', type_='check')
    op.drop_column('users', 'kind')
