"""requests collector — reads classified nginx request metrics."""
from __future__ import annotations

from monitor.bg import NGINX_ACCESS_RECORDS, NGINX_WINDOW_CACHE
from monitor.requests_metrics import build_requests_block, records_for_window
from monitor.schema import RequestsBlock
from monitor.traffic import RequestFilters


async def collect(
    window: str = "6h",
    filters: RequestFilters | None = None,
) -> RequestsBlock:
    if filters is None:
        cached = NGINX_WINDOW_CACHE.get(window)
        if cached is not None:
            return RequestsBlock.model_validate(cached)
        filters = RequestFilters()

    records = records_for_window(list(NGINX_ACCESS_RECORDS), window)
    return build_requests_block(records, window, filters)
