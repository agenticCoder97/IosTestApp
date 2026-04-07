"""add fanfic stats columns (hits, kudos, comments, bookmarks, freeform_tags)

Revision ID: a7b2c3d4e5f6
Revises: 4e4043fe34ef
Create Date: 2026-04-07 00:00:00.000000
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a7b2c3d4e5f6'
down_revision: Union[str, None] = '4e4043fe34ef'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('fanfics', sa.Column('freeform_tags', sa.String(length=4000), nullable=True))
    op.add_column('fanfics', sa.Column('hits', sa.Integer(), nullable=True))
    op.add_column('fanfics', sa.Column('kudos', sa.Integer(), nullable=True))
    op.add_column('fanfics', sa.Column('comments_count', sa.Integer(), nullable=True))
    op.add_column('fanfics', sa.Column('bookmarks_count', sa.Integer(), nullable=True))


def downgrade() -> None:
    op.drop_column('fanfics', 'bookmarks_count')
    op.drop_column('fanfics', 'comments_count')
    op.drop_column('fanfics', 'kudos')
    op.drop_column('fanfics', 'hits')
    op.drop_column('fanfics', 'freeform_tags')
