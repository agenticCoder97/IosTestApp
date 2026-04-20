"""add comic mangadex swap columns

Revision ID: f2a3b4c5d6e7
Revises: e1f2a3b4c5d6
Create Date: 2026-04-19 22:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


revision = "f2a3b4c5d6e7"
down_revision = "e1f2a3b4c5d6"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "comics",
        sa.Column("previous_source", sa.String(length=50), nullable=True),
    )
    op.add_column(
        "comics",
        sa.Column("previous_source_url", sa.String(length=2000), nullable=True),
    )
    op.add_column(
        "comics",
        sa.Column("match_confidence", sa.Float(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("comics", "match_confidence")
    op.drop_column("comics", "previous_source_url")
    op.drop_column("comics", "previous_source")
