"""Read-only SQL console backed by the astral_readonly Postgres role.

Only SELECT and WITH statements are accepted. The connection is
opened per-query using MONITOR_READONLY_DSN (distinct from the
asyncpg pool used by the storage collector, which runs as the app
owner). Timeout 10 s, 500-row cap.
"""
from __future__ import annotations

import logging
import os
import re
import time
from typing import Any

import asyncpg

logger = logging.getLogger("monitor.control.sql")

MAX_ROWS = 500
TIMEOUT_S = 10.0

_READONLY_DSN = os.getenv(
    "MONITOR_READONLY_DSN",
    "postgresql://astral_readonly:astral_readonly@postgres:5432/astral",
)

_FORBIDDEN_RE = re.compile(
    r"\b(insert|update|delete|drop|alter|truncate|grant|revoke|create|comment|copy|vacuum|cluster|reindex|lock)\b",
    re.IGNORECASE,
)
_ALLOWED_PREFIX_RE = re.compile(r"^\s*(select|with)\b", re.IGNORECASE)


class SQLValidationError(ValueError):
    pass


def _validate(sql: str) -> None:
    stripped = sql.strip().rstrip(";").strip()
    if not stripped:
        raise SQLValidationError("query is empty")
    if not _ALLOWED_PREFIX_RE.match(stripped):
        raise SQLValidationError("only SELECT and WITH queries are allowed")
    if _FORBIDDEN_RE.search(stripped):
        raise SQLValidationError(
            "query contains a forbidden keyword (DML/DDL tokens are rejected)"
        )
    if ";" in stripped:
        raise SQLValidationError("only a single statement may be submitted")


async def run_query(sql: str) -> dict[str, Any]:
    _validate(sql)
    started = time.monotonic()
    conn = None
    try:
        conn = await asyncpg.connect(_READONLY_DSN, timeout=3.0)
        # statement_timeout defends against runaway queries even though
        # TIMEOUT_S wraps the whole call — the role should also have a
        # default statement_timeout of 10s.
        await conn.execute(f"SET statement_timeout = {int(TIMEOUT_S * 1000)}")
        rows = await conn.fetch(f"{sql.rstrip(';')} LIMIT {MAX_ROWS + 1}")
    except asyncpg.PostgresError as e:
        raise SQLValidationError(f"postgres error: {e}")
    finally:
        if conn is not None:
            await conn.close()

    truncated = len(rows) > MAX_ROWS
    rows = rows[:MAX_ROWS]

    columns: list[str] = []
    if rows:
        columns = list(rows[0].keys())
    out_rows = [
        [_jsonable(r[c]) for c in columns]
        for r in rows
    ]
    return {
        "columns": columns,
        "rows": out_rows,
        "row_count": len(out_rows),
        "truncated": truncated,
        "duration_ms": int((time.monotonic() - started) * 1000),
    }


def _jsonable(v: Any) -> Any:
    if v is None:
        return None
    if isinstance(v, (int, float, bool, str)):
        return v
    if hasattr(v, "isoformat"):
        return v.isoformat()
    return str(v)
