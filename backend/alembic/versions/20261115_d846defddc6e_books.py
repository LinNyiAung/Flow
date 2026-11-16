"""books

Replaces the hidden family "book users" with a real books table. Every person gets a personal book (a new uuid4) and
every family a family book (whose id is the family's old book_user_id, so family rows simply change which table their
key points at). transactions, budgets, goals, insights and custom_insights move from user_id to book_id;
chat_sessions.book_id becomes NOT NULL (a personal chat points at the personal book); ai_usage gets book_id (a book
user's spend moves there, user_id becomes nullable); users.ai_data_stale moves to books. notifications.goal_id (an id of
whatever `type` meant) and notifications.book are replaced by typed links (goal, budget, transaction, custom insight,
family invite, family; at most one) plus book_id. A weekly / monthly insight notice links its book: a live family
book, else the recipient's personal book when it had no goal_id (a personal insight notice), else none (a deleted
family's). Finally the book users, families.book_user_id, users.kind and users.ai_data_stale go. Deleting the book
users also removes, by cascade, their usage_counters and notification_preferences rows, including those of orphan
book users (a deleted family's book user, which gets no book).

The downgrade is the exact reverse and works on a populated database: it re-creates the book users with the family book
ids, maps book_id back to user_id, and collapses the typed links back into goal_id / book. AI spend whose family was
deleted (user_id and book_id both NULL) can't be held by the old schema and is deleted.

Revision ID: d846defddc6e
Revises: 522ad619de76
Create Date: 2026-11-15 09:00:00.000000
"""
import secrets
from typing import Sequence, Union

from alembic import op
import bcrypt
import sqlalchemy as sa

revision: str = 'd846defddc6e'
down_revision: Union[str, None] = '522ad619de76'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

TS = sa.DateTime(timezone=True)

# The five book-data tables: (single-column index on the owner?, [(old index, new index, columns, kwargs)]).
# Index names follow "user -> book"; ix_insights_latest and uq_budgets_rollover_child keep their names.
_DESC_CREATED = sa.text('created_at DESC')
_DESC_GENERATED = sa.text('generated_at DESC')
_BOOK_DATA = {
    'transactions': (True, [
        ('ix_transactions_user_date', 'ix_transactions_book_date', ['{o}', 'date'], {}),
        ('ix_transactions_user_type_date', 'ix_transactions_book_type_date', ['{o}', 'type', 'date'], {}),
        ('ix_transactions_user_currency', 'ix_transactions_book_currency', ['{o}', 'currency'], {}),
    ]),
    'budgets': (True, [
        ('ix_budgets_user_window', 'ix_budgets_book_window', ['{o}', 'currency', 'start_date', 'end_date'], {}),
        ('uq_budgets_rollover_child', 'uq_budgets_rollover_child', ['{o}', 'parent_budget_id', 'start_date'],
         {'unique': True, 'postgresql_where': sa.text('parent_budget_id IS NOT NULL')}),
    ]),
    'goals': (True, [
        ('ix_goals_user_status_currency', 'ix_goals_book_status_currency', ['{o}', 'status', 'currency'], {}),
    ]),
    'insights': (True, [
        ('ix_insights_latest', 'ix_insights_latest', ['{o}', 'ai_provider', 'insight_type', _DESC_GENERATED], {}),
    ]),
    'custom_insights': (False, [  # no single-column index: ix_custom_insights_*_created leads with the owner
        ('ix_custom_insights_user_created', 'ix_custom_insights_book_created', ['{o}', _DESC_CREATED], {}),
        ('uq_custom_insights_pending_user', 'uq_custom_insights_pending_book', ['{o}'],
         {'unique': True, 'postgresql_where': sa.text("status = 'pending'")}),
    ]),
}

# notification type -> the typed link that holds the old goal_id (from notification_service). Types not listed
# (unusual_spending, payment_reminder, the subscription / plan types, broadcasts) link nothing; the weekly / monthly
# insight notices link only their book.
_LINK_BY_TYPE = {
    'goal_id': ('goal_progress', 'goal_achieved', 'goal_milestone', 'goal_approaching_date'),
    'budget_id': ('budget_threshold', 'budget_exceeded', 'budget_ending_soon', 'budget_now_active', 'budget_started',
                  'budget_auto_created'),
    'transaction_id': ('large_transaction', 'recurring_transaction_created', 'recurring_transaction_ended',
                       'recurring_transaction_disabled'),
    'custom_insight_id': ('custom_insight_ready', 'custom_insight_failed'),
    'family_invite_id': ('family_invite',),
    'family_id': ('family_invite_accepted', 'family_removed', 'family_owner'),
}
_INSIGHT_NOTICES = ('weekly_insights_generated', 'monthly_insights_generated')
# typed link -> the table it points at, and (for book data) whose book_id is the notice's book.
_LINK_TABLE = {'goal_id': 'goals', 'budget_id': 'budgets', 'transaction_id': 'transactions',
               'custom_insight_id': 'custom_insights', 'family_invite_id': 'family_invites', 'family_id': 'families'}
_BOOK_LINKS = ('goal_id', 'budget_id', 'transaction_id', 'custom_insight_id')


def _sql(statement: str, **params) -> None:
    op.execute(sa.text(statement).bindparams(**params) if params else sa.text(statement))


def _in(types) -> str:
    return '(' + ', '.join(f"'{t}'" for t in types) + ')'


def _cols(cols, owner):
    return [c.format(o=owner) if isinstance(c, str) else c for c in cols]


def upgrade() -> None:
    # 1. books
    op.create_table('books',
    sa.Column('id', sa.Text(), nullable=False),
    sa.Column('kind', sa.Text(), nullable=False),
    sa.Column('person_id', sa.Text(), nullable=True),
    sa.Column('family_id', sa.Text(), nullable=True),
    sa.Column('ai_data_stale', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    sa.Column('created_at', TS, server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint("(kind = 'personal' AND person_id IS NOT NULL AND family_id IS NULL) OR "
                       "(kind = 'family' AND family_id IS NOT NULL AND person_id IS NULL)",
                       name=op.f('ck_books_kind_owner')),
    sa.ForeignKeyConstraint(['person_id'], ['users.id'], name=op.f('fk_books_person_id_users'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['family_id'], ['families.id'], name=op.f('fk_books_family_id_families'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_books'))
    )
    op.create_index('uq_books_person_id', 'books', ['person_id'], unique=True,
                    postgresql_where=sa.text('person_id IS NOT NULL'))
    op.create_index('uq_books_family_id', 'books', ['family_id'], unique=True,
                    postgresql_where=sa.text('family_id IS NOT NULL'))

    # 2. A personal book for every person; 3. a family book per family, with the book user's id. (7. ai_data_stale
    # moves with them.) A book user with no family owns nothing the old schema would keep: it is deleted in step 9.
    _sql("INSERT INTO books (id, kind, person_id, ai_data_stale, created_at) "
         "SELECT gen_random_uuid()::text, 'personal', id, ai_data_stale, created_at FROM users WHERE kind = 'person'")
    _sql("INSERT INTO books (id, kind, family_id, ai_data_stale, created_at) "
         "SELECT f.book_user_id, 'family', f.id, u.ai_data_stale, f.created_at "
         "FROM families f JOIN users u ON u.id = f.book_user_id")

    # 4. Book data: user_id -> book_id.
    for table, (single_index, indexes) in _BOOK_DATA.items():
        op.add_column(table, sa.Column('book_id', sa.Text(), nullable=True))
        _sql(f"UPDATE {table} t SET book_id = b.id FROM books b WHERE b.person_id = t.user_id")
        _sql(f"UPDATE {table} t SET book_id = b.id FROM books b WHERE b.kind = 'family' AND b.id = t.user_id")
        # Rows of a book user without a family: the old schema deletes them with that user (step 9).
        _sql(f"DELETE FROM {table} WHERE book_id IS NULL")
        op.alter_column(table, 'book_id', nullable=False)
        for old, _new, _cols_, _kw in indexes:
            op.drop_index(old, table_name=table)
        if single_index:
            op.drop_index(op.f(f'ix_{table}_user_id'), table_name=table)
        op.drop_constraint(op.f(f'fk_{table}_user_id_users'), table, type_='foreignkey')
        op.drop_column(table, 'user_id')
        op.create_foreign_key(op.f(f'fk_{table}_book_id_books'), table, 'books', ['book_id'], ['id'], ondelete='CASCADE')
        if single_index:
            op.create_index(op.f(f'ix_{table}_book_id'), table, ['book_id'], unique=False)
        for _old, new, cols, kw in indexes:
            op.create_index(new, table, _cols(cols, 'book_id'), **kw)

    # 5. chat_sessions.book_id: NULL (personal) -> the person's personal book; the FK now points at books.
    op.drop_constraint(op.f('fk_chat_sessions_book_id_users'), 'chat_sessions', type_='foreignkey')
    _sql("UPDATE chat_sessions c SET book_id = b.id FROM books b WHERE c.book_id IS NULL AND b.person_id = c.user_id")
    _sql("DELETE FROM chat_sessions WHERE book_id IS NULL OR book_id NOT IN (SELECT id FROM books)")
    op.alter_column('chat_sessions', 'book_id', nullable=False)
    op.create_foreign_key(op.f('fk_chat_sessions_book_id_books'), 'chat_sessions', 'books', ['book_id'], ['id'],
                          ondelete='CASCADE')

    # 6. ai_usage: a book user's spend moves to book_id with user_id NULL (a family-less book user's keeps its cost
    # with both NULL).
    op.add_column('ai_usage', sa.Column('book_id', sa.Text(), nullable=True))
    op.alter_column('ai_usage', 'user_id', nullable=True)
    _sql("UPDATE ai_usage a SET book_id = b.id FROM books b WHERE b.kind = 'family' AND b.id = a.user_id")
    _sql("UPDATE ai_usage SET user_id = NULL WHERE user_id IN (SELECT id FROM users WHERE kind = 'family_book')")
    op.create_foreign_key(op.f('fk_ai_usage_book_id_books'), 'ai_usage', 'books', ['book_id'], ['id'], ondelete='SET NULL')
    op.create_index(op.f('ix_ai_usage_book_id'), 'ai_usage', ['book_id'], unique=False)

    # 8. notifications: typed links instead of goal_id, book_id instead of book.
    op.alter_column('notifications', 'goal_id', new_column_name='legacy_goal_id')
    for link in (*_LINK_TABLE, 'book_id'):
        op.add_column('notifications', sa.Column(link, sa.Text(), nullable=True))
    for link, types in _LINK_BY_TYPE.items():
        target = _LINK_TABLE[link]
        _sql(f"UPDATE notifications n SET {link} = n.legacy_goal_id WHERE n.type IN {_in(types)} "
             f"AND EXISTS (SELECT 1 FROM {target} x WHERE x.id = n.legacy_goal_id)")
    for link in _BOOK_LINKS:
        _sql(f"UPDATE notifications n SET book_id = x.book_id FROM {_LINK_TABLE[link]} x WHERE x.id = n.{link}")
    _sql(f"UPDATE notifications n SET book_id = CASE "
         f"WHEN n.legacy_goal_id IN (SELECT id FROM books WHERE kind = 'family') THEN n.legacy_goal_id "
         f"WHEN n.legacy_goal_id IS NOT NULL THEN NULL "  # a deleted family's book user: no book (not the personal one)
         f"ELSE (SELECT b.id FROM books b WHERE b.person_id = n.user_id) END "
         f"WHERE n.type IN {_in(_INSIGHT_NOTICES)}")
    op.drop_column('notifications', 'legacy_goal_id')
    op.drop_constraint(op.f('ck_notifications_book'), 'notifications', type_='check')
    op.drop_column('notifications', 'book')
    for link, target in (*_LINK_TABLE.items(), ('book_id', 'books')):
        op.create_foreign_key(op.f(f'fk_notifications_{link}_{target}'), 'notifications', target, [link], ['id'],
                              ondelete='SET NULL')
        op.create_index(op.f(f'ix_notifications_{link}'), 'notifications', [link], unique=False)
    op.create_check_constraint(op.f('ck_notifications_one_subject'), 'notifications',
                               'num_nonnulls(goal_id, budget_id, transaction_id, custom_insight_id, family_invite_id, '
                               'family_id) <= 1')

    # 9. The book users go: families.book_user_id first (its FK would cascade to the family), then the rows, then
    # users.kind and users.ai_data_stale.
    op.drop_constraint(op.f('uq_families_book_user_id'), 'families', type_='unique')
    op.drop_constraint(op.f('fk_families_book_user_id_users'), 'families', type_='foreignkey')
    op.drop_column('families', 'book_user_id')
    _sql("DELETE FROM users WHERE kind = 'family_book'")
    op.drop_constraint(op.f('ck_users_kind'), 'users', type_='check')
    op.drop_column('users', 'kind')
    op.drop_column('users', 'ai_data_stale')


def downgrade() -> None:
    # 1-2. users.kind and users.ai_data_stale; the book users again (ids = the family book ids), and
    # families.book_user_id.
    op.add_column('users', sa.Column('kind', sa.Text(), server_default='person', nullable=False))
    op.create_check_constraint(op.f('ck_users_kind'), 'users', "kind IN ('person','family_book')")
    op.add_column('users', sa.Column('ai_data_stale', sa.Boolean(), server_default=sa.text('false'), nullable=False))
    _sql("UPDATE users u SET ai_data_stale = b.ai_data_stale FROM books b WHERE b.person_id = u.id")
    bind = op.get_bind()
    family_books = bind.execute(sa.text(
        "SELECT b.id, b.family_id, b.ai_data_stale, b.created_at FROM books b WHERE b.kind = 'family'")).fetchall()
    for book_id, family_id, stale, created_at in family_books:
        # It can never log in: the hash is of a random secret that is thrown away (as users.create_book_user did).
        password = bcrypt.hashpw(secrets.token_urlsafe(32).encode(), bcrypt.gensalt()).decode()
        _sql("INSERT INTO users (id, name, email, password, kind, is_verified, subscription_type, language, "
             "ai_data_stale, created_at) VALUES (:id, 'Family book', :email, :password, 'family_book', true, 'free', "
             "'en', :stale, :created_at)",
             id=book_id, email=f'family-{family_id}@book.invalid', password=password, stale=stale, created_at=created_at)
    op.add_column('families', sa.Column('book_user_id', sa.Text(), nullable=True))
    _sql("UPDATE families f SET book_user_id = b.id FROM books b WHERE b.family_id = f.id")
    op.alter_column('families', 'book_user_id', nullable=False)
    op.create_foreign_key(op.f('fk_families_book_user_id_users'), 'families', 'users', ['book_user_id'], ['id'],
                          ondelete='CASCADE')
    op.create_unique_constraint(op.f('uq_families_book_user_id'), 'families', ['book_user_id'])

    # 6. notifications: the one typed link set (for an insight notice: its book, when a family book) back into
    # goal_id, and book = 'family' where the notice's book is a family book.
    op.drop_constraint(op.f('ck_notifications_one_subject'), 'notifications', type_='check')
    op.add_column('notifications', sa.Column('legacy_goal_id', sa.Text(), nullable=True))
    op.add_column('notifications', sa.Column('book', sa.Text(), nullable=True))
    family_book = "n.book_id IN (SELECT id FROM books WHERE kind = 'family')"
    _sql(f"UPDATE notifications n SET legacy_goal_id = COALESCE({', '.join(f'n.{c}' for c in _LINK_TABLE)}, "
         f"CASE WHEN n.type IN {_in(_INSIGHT_NOTICES)} AND {family_book} THEN n.book_id END)")
    _sql(f"UPDATE notifications n SET book = 'family' WHERE {family_book}")
    for link, target in (*_LINK_TABLE.items(), ('book_id', 'books')):
        op.drop_index(op.f(f'ix_notifications_{link}'), table_name='notifications')
        op.drop_constraint(op.f(f'fk_notifications_{link}_{target}'), 'notifications', type_='foreignkey')
        op.drop_column('notifications', link)
    op.alter_column('notifications', 'legacy_goal_id', new_column_name='goal_id')
    op.create_check_constraint(op.f('ck_notifications_book'), 'notifications', "book IS NULL OR book = 'family'")

    # 5. ai_usage: book_id -> user_id. Rows with neither (a deleted family's spend) can't be kept by the old schema.
    _sql("UPDATE ai_usage a SET user_id = CASE b.kind WHEN 'personal' THEN b.person_id ELSE b.id END "
         "FROM books b WHERE a.user_id IS NULL AND b.id = a.book_id")
    _sql("DELETE FROM ai_usage WHERE user_id IS NULL")
    op.drop_index(op.f('ix_ai_usage_book_id'), table_name='ai_usage')
    op.drop_constraint(op.f('fk_ai_usage_book_id_books'), 'ai_usage', type_='foreignkey')
    op.drop_column('ai_usage', 'book_id')
    op.alter_column('ai_usage', 'user_id', nullable=False)

    # 4. chat_sessions.book_id: personal -> NULL; the FK points at users (the book users) again.
    op.drop_constraint(op.f('fk_chat_sessions_book_id_books'), 'chat_sessions', type_='foreignkey')
    op.alter_column('chat_sessions', 'book_id', nullable=True)
    _sql("UPDATE chat_sessions SET book_id = NULL WHERE book_id IN (SELECT id FROM books WHERE kind = 'personal')")
    op.create_foreign_key(op.f('fk_chat_sessions_book_id_users'), 'chat_sessions', 'users', ['book_id'], ['id'],
                          ondelete='CASCADE')

    # 3. Book data: book_id -> user_id (a personal book's person; a family book's id, now its book user's).
    for table, (single_index, indexes) in _BOOK_DATA.items():
        op.add_column(table, sa.Column('user_id', sa.Text(), nullable=True))
        _sql(f"UPDATE {table} t SET user_id = CASE b.kind WHEN 'personal' THEN b.person_id ELSE b.id END "
             f"FROM books b WHERE b.id = t.book_id")
        op.alter_column(table, 'user_id', nullable=False)
        for _old, new, _cols_, _kw in indexes:
            op.drop_index(new, table_name=table)
        if single_index:
            op.drop_index(op.f(f'ix_{table}_book_id'), table_name=table)
        op.drop_constraint(op.f(f'fk_{table}_book_id_books'), table, type_='foreignkey')
        op.drop_column(table, 'book_id')
        op.create_foreign_key(op.f(f'fk_{table}_user_id_users'), table, 'users', ['user_id'], ['id'], ondelete='CASCADE')
        if single_index:
            op.create_index(op.f(f'ix_{table}_user_id'), table, ['user_id'], unique=False)
        for old, _new, cols, kw in indexes:
            op.create_index(old, table, _cols(cols, 'user_id'), **kw)

    # 7. books
    op.drop_table('books')  # its indexes go with it
