"""Kill-switch feature flags backed by Redis.

Flags live at `mon:flag:<KEY>` as JSON:
    {"value": bool, "changed_at": iso8601, "changed_by": str}

Consumer pattern (main app / ARQ worker) should read the Redis key
first and fall back to os.getenv(KEY) when absent. Worker picks up
flag changes on its next job tick with no restart needed.
"""
from __future__ import annotations

import json
import logging
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional

from monitor.cache import get_cache_redis

logger = logging.getLogger("monitor.flags")

# Ordered: the UI renders toggles in this order.
MANAGED_FLAGS: list[str] = [
    "MANGADEX_DISABLED",
    "FFNET_NEW_SCRAPER_DISABLED",
    "MANGADEX_AUTO_SWITCH_SOURCE",
]

_DESCRIPTIONS: dict[str, str] = {
    "MANGADEX_DISABLED":
        "Hard-stops new mangadex scrapes (HTTP 503) and disables the "
        "toongod/hentai20 matcher. Does NOT cancel already-running jobs.",
    "FFNET_NEW_SCRAPER_DISABLED":
        "Skip FanFicFare for FFNet and serve all FFNet scrapes through "
        "FicHub fallback.",
    "MANGADEX_AUTO_SWITCH_SOURCE":
        "Master toggle for the mangadex source auto-switcher on "
        "toongod/hentai20 adds.",
}


@dataclass
class FlagState:
    key: str
    value: bool
    source: str                  # "redis-override" | "env" | "default"
    description: str
    changed_at: Optional[str] = None
    changed_by: Optional[str] = None


def _parse_bool(raw: str) -> bool:
    return raw.strip().lower() in ("1", "true", "yes", "on")


async def read_all() -> list[FlagState]:
    r = get_cache_redis()
    out: list[FlagState] = []
    for key in MANAGED_FLAGS:
        redis_raw = await r.get(f"mon:flag:{key}")
        if redis_raw:
            try:
                data = json.loads(redis_raw)
                out.append(FlagState(
                    key=key,
                    value=bool(data.get("value", False)),
                    source="redis-override",
                    description=_DESCRIPTIONS.get(key, ""),
                    changed_at=data.get("changed_at"),
                    changed_by=data.get("changed_by"),
                ))
                continue
            except (ValueError, TypeError) as e:
                logger.debug("flag override for %s failed to parse, falling back to env: %s", key, e)
        env_raw = os.getenv(key)
        if env_raw is not None:
            out.append(FlagState(
                key=key,
                value=_parse_bool(env_raw),
                source="env",
                description=_DESCRIPTIONS.get(key, ""),
            ))
        else:
            # Flag-specific defaults — match the documented behaviour
            # in CLAUDE.md when no env value is set.
            default_value = key == "MANGADEX_AUTO_SWITCH_SOURCE"
            out.append(FlagState(
                key=key,
                value=default_value,
                source="default",
                description=_DESCRIPTIONS.get(key, ""),
            ))
    return out


async def set_flag(key: str, value: bool, *, changed_by: str = "monitor-ui") -> FlagState:
    if key not in MANAGED_FLAGS:
        raise ValueError(f"unknown flag: {key}")
    r = get_cache_redis()
    payload = {
        "value": bool(value),
        "changed_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "changed_by": changed_by,
    }
    await r.set(f"mon:flag:{key}", json.dumps(payload))
    return FlagState(
        key=key, value=bool(value), source="redis-override",
        description=_DESCRIPTIONS.get(key, ""),
        changed_at=payload["changed_at"], changed_by=changed_by,
    )
