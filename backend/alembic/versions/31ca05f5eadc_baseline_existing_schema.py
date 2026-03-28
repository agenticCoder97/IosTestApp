"""baseline — existing schema

Revision ID: 31ca05f5eadc
Revises:
Create Date: 2026-03-28 06:27:45.223145
"""
from typing import Sequence, Union

# revision identifiers, used by Alembic.
revision: str = '31ca05f5eadc'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Baseline: tables already exist via create_all(). Nothing to do.
    pass


def downgrade() -> None:
    pass
