"""create astral_readonly role for monitor SQL console

Revision ID: a3b4c5d6e7f8
Revises: f2a3b4c5d6e7
Create Date: 2026-04-22 18:30:00.000000

AST-75: the monitor dashboard ships a read-only SQL console that
connects as a dedicated Postgres role with SELECT-only privileges.
The password is read from the ASTRAL_READONLY_PASSWORD env var on
the Postgres container side; iff unset, a random one is generated
so the role still exists but can only be connected to by rotating
it manually. The monitor container passes MONITOR_READONLY_DSN
pointing at this role.
"""
from __future__ import annotations

import os

import sqlalchemy as sa
from alembic import op


revision = "a3b4c5d6e7f8"
down_revision = "f2a3b4c5d6e7"
branch_labels = None
depends_on = None


_ROLE = "astral_readonly"


def upgrade() -> None:
    password = os.getenv("ASTRAL_READONLY_PASSWORD", "astral_readonly")
    # Quote the password with dollar-quoting to avoid escaping issues.
    op.execute(f"""
        DO $do$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '{_ROLE}') THEN
                CREATE ROLE {_ROLE} LOGIN PASSWORD $pwd${password}$pwd$;
            END IF;
        END
        $do$;
    """)
    op.execute(f"GRANT CONNECT ON DATABASE {_conn_db()} TO {_ROLE};")
    op.execute(f"GRANT USAGE ON SCHEMA public TO {_ROLE};")
    op.execute(f"GRANT SELECT ON ALL TABLES IN SCHEMA public TO {_ROLE};")
    op.execute(f"GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO {_ROLE};")
    # Future tables created by app owner auto-grant to readonly.
    op.execute(
        f"ALTER DEFAULT PRIVILEGES IN SCHEMA public "
        f"GRANT SELECT ON TABLES TO {_ROLE};"
    )
    # Baseline safety net — 10s statement timeout matches the monitor
    # endpoint timeout.
    op.execute(f"ALTER ROLE {_ROLE} SET statement_timeout = '10s';")


def downgrade() -> None:
    op.execute(f"REVOKE ALL ON ALL TABLES IN SCHEMA public FROM {_ROLE};")
    op.execute(f"REVOKE ALL ON SCHEMA public FROM {_ROLE};")
    op.execute(f"REVOKE CONNECT ON DATABASE {_conn_db()} FROM {_ROLE};")
    op.execute(f"DROP ROLE IF EXISTS {_ROLE};")


def _conn_db() -> str:
    # Resolve the current database name at migration time so the DB
    # can be renamed without breaking the migration.
    conn = op.get_bind()
    return conn.execute(sa.text("SELECT current_database()")).scalar()
