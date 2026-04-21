"""services collector — reads SERVICE_CACHE populated by docker_sampler."""
from __future__ import annotations

from monitor.bg import SERVICE_CACHE
from monitor.schema import ServiceBlock


async def collect() -> list[ServiceBlock]:
    blocks: list[ServiceBlock] = []
    for _name, entry in SERVICE_CACHE.items():
        blocks.append(ServiceBlock.model_validate(entry))
    order = {
        "postgres": 0, "redis": 1, "fastapi": 2,
        "arq_worker": 3, "nginx": 4, "certbot": 5,
    }
    blocks.sort(key=lambda b: order.get(b.name, 99))
    return blocks
