"""logs collector — slice LOG_DEQUE with optional svc + q filters."""
from __future__ import annotations

from typing import Optional

from monitor.bg import LOG_DEQUE
from monitor.schema import LogLine


async def collect(limit: int = 100, svc: Optional[str] = None, q: Optional[str] = None) -> list[LogLine]:
    matches: list[dict] = []
    for entry in LOG_DEQUE:
        if svc and entry["svc"] != svc:
            continue
        if q and q.lower() not in entry["msg"].lower():
            continue
        matches.append(entry)
    return [LogLine.model_validate(m) for m in matches[-limit:]]
