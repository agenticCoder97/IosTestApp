"""add comic archive columns (archived_at, archive_status)

Revision ID: c9d4e5f6a7b8
Revises: b8c3d4e5f6a7
Create Date: 2026-04-07 12:00:00.000000
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c9d4e5f6a7b8'
down_revision: Union[str, None] = 'b8c3d4e5f6a7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('comics', sa.Column('archived_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('comics', sa.Column('archive_status', sa.String(20), nullable=False, server_default='none'))


def downgrade() -> None:
    op.drop_column('comics', 'archive_status')
    op.drop_column('comics', 'archived_at')
