"""deploys collector — tail deploys.jsonl written by the deploy hook.

Each line is a JSON object:
  {"ts": "...", "images_pulled": [...], "healthy": bool, "duration_s": int}

Missing file is treated as "no deploys yet" — the UI shows an empty
state rather than an error.
"""
from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Optional

from monitor.control.audit import STATE_DIR
from monitor.schema import DeployEvent, DeploysBlock

logger = logging.getLogger("monitor.deploys")

DEPLOYS_PATH = STATE_DIR / "deploys.jsonl"
_MAX_LINES = 25
_SHOW_N = 5


def _parse(line: str) -> Optional[DeployEvent]:
    try:
        data = json.loads(line)
    except ValueError:
        return None
    ts = data.get("ts")
    try:
        when = datetime.fromisoformat(str(ts).replace("Z", "+00:00")) if ts else datetime.now(timezone.utc)
    except ValueError:
        when = datetime.now(timezone.utc)
    return DeployEvent(
        ts=when,
        images_pulled=list(data.get("images_pulled") or []),
        healthy=bool(data.get("healthy", True)),
        duration_s=int(data.get("duration_s") or 0),
        commit_sha=data.get("commit_sha"),
        actor=data.get("actor"),
    )


async def collect() -> DeploysBlock:
    if not DEPLOYS_PATH.exists():
        return DeploysBlock(recent=[])
    try:
        with DEPLOYS_PATH.open("r", encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()[-_MAX_LINES:]
    except Exception as e:
        logger.debug("deploys read failed: %s", e)
        return DeploysBlock(recent=[])

    parsed = [p for p in (_parse(l) for l in lines) if p is not None]
    parsed.sort(key=lambda d: d.ts, reverse=True)
    return DeploysBlock(recent=parsed[:_SHOW_N])
