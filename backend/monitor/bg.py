"""Long-lived background tasks for the monitor service."""
from __future__ import annotations

import asyncio
import logging
from collections import deque
from typing import Any, Awaitable, Callable, Deque

logger = logging.getLogger("monitor.bg")

_BACKOFF_INITIAL_S = 10
_BACKOFF_MAX_S = 60

SERVICE_CACHE: dict[str, dict[str, Any]] = {}
LOG_DEQUE: Deque[dict[str, Any]] = deque(maxlen=500)
NGINX_WINDOW_CACHE: dict[str, dict[str, Any]] = {}


async def supervise(factory: Callable[[], Awaitable[Any]], name: str) -> None:
    """Restart factory() on non-Cancelled exceptions with exponential backoff."""
    backoff = _BACKOFF_INITIAL_S
    while True:
        try:
            await factory()
            return
        except asyncio.CancelledError:
            raise
        except Exception as e:
            logger.exception("bg task %s died: %s — retry in %ss", name, e, backoff)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, _BACKOFF_MAX_S)


async def docker_sampler() -> None:
    raise NotImplementedError


async def log_tailer() -> None:
    raise NotImplementedError


async def nginx_access_sampler() -> None:
    raise NotImplementedError
