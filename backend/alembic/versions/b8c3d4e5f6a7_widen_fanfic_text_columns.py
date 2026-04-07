"""widen fanfic text columns (fandom, relationship, characters, warnings) to TEXT

Revision ID: b8c3d4e5f6a7
Revises: a7b2c3d4e5f6
Create Date: 2026-04-07 00:00:00.000000
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b8c3d4e5f6a7'
down_revision: Union[str, None] = 'a7b2c3d4e5f6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.alter_column('fanfics', 'fandom', type_=sa.Text(), existing_nullable=True)
    op.alter_column('fanfics', 'relationship', type_=sa.Text(), existing_nullable=True)
    op.alter_column('fanfics', 'characters', type_=sa.Text(), existing_nullable=True)
    op.alter_column('fanfics', 'warnings', type_=sa.Text(), existing_nullable=True)


def downgrade() -> None:
    op.alter_column('fanfics', 'fandom', type_=sa.String(500), existing_nullable=True)
    op.alter_column('fanfics', 'relationship', type_=sa.String(500), existing_nullable=True)
    op.alter_column('fanfics', 'characters', type_=sa.String(1000), existing_nullable=True)
    op.alter_column('fanfics', 'warnings', type_=sa.String(500), existing_nullable=True)
