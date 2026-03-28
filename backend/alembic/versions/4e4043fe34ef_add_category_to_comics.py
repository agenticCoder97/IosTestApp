"""add category to comics

Revision ID: 4e4043fe34ef
Revises: 31ca05f5eadc
Create Date: 2026-03-28 06:28:43.891923
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '4e4043fe34ef'
down_revision: Union[str, None] = '31ca05f5eadc'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('comics', sa.Column('category', sa.String(length=200), nullable=True))


def downgrade() -> None:
    op.drop_column('comics', 'category')
