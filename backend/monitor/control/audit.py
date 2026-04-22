"""Append-only audit log for every /control/* mutation.

Lives at /var/lib/astral-monitor/audit.log (one JSON object per line).
Reads are best-effort tail; writes are fire-and-forget.
"""
from __future__ import annotations

import json
import logging
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

logger = logging.getLogger("monitor.audit")

STATE_DIR = Path(os.getenv("MONITOR_STATE_DIR", "/var/lib/astral-monitor"))
AUDIT_PATH = STATE_DIR / "audit.log"


def record(action: str, *, ok: bool, detail: Any = None, source_ip: str | None = None) -> None:
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        entry = {
            "ts": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "action": action,
            "ok": ok,
            "detail": detail,
            "source_ip": source_ip,
        }
        with AUDIT_PATH.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(entry, default=str) + "\n")
    except Exception as e:
        logger.warning("audit record failed action=%s err=%s", action, e)


def tail(limit: int = 50) -> list[dict]:
    if not AUDIT_PATH.exists():
        return []
    try:
        with AUDIT_PATH.open("r", encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()[-limit:]
        out: list[dict] = []
        for line in lines:
            try:
                out.append(json.loads(line))
            except ValueError:
                continue
        return out
    except Exception as e:
        logger.debug("audit tail failed: %s", e)
        return []
