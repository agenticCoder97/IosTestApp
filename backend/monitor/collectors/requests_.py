"""requests collector — reads NGINX_WINDOW_CACHE populated by nginx_access_sampler."""
from __future__ import annotations

from monitor.bg import NGINX_WINDOW_CACHE
from monitor.schema import RequestsBlock


async def collect(window: str = "6h") -> RequestsBlock:
    cached = NGINX_WINDOW_CACHE.get(window)
    if cached is None:
        return RequestsBlock(
            window=window,
            series_rps=[], series_p95_ms=[],
            status_codes={"2xx": 0, "3xx": 0, "4xx": 0, "5xx": 0},
            slowest=[],
        )
    return RequestsBlock.model_validate(cached)
