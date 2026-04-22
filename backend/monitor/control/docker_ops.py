"""Docker operations (restart, exec_run) invoked from /control/*.

Requires /var/run/docker.sock mounted read-write in the monitor
container (the compose default is :ro; widened in docker-compose.yml).
"""
from __future__ import annotations

import asyncio
import logging
from typing import Optional

logger = logging.getLogger("monitor.control.docker")

RESTARTABLE_SERVICES = {
    "fastapi", "arq_worker", "postgres", "redis", "nginx", "astral_monitor",
}
STATEFUL_SERVICES = {"postgres", "redis"}


def _docker_client():
    import docker
    return docker.from_env()


async def restart_service(service: str, *, timeout_s: int = 20) -> dict:
    if service not in RESTARTABLE_SERVICES:
        raise ValueError(f"service not restartable: {service}")

    def _do_restart() -> dict:
        client = _docker_client()
        containers = client.containers.list(
            all=True,
            filters={
                "label": [
                    "com.docker.compose.project=backend",
                    f"com.docker.compose.service={service}",
                ],
            },
        )
        if not containers:
            raise RuntimeError(f"no container for service {service}")
        container = containers[0]
        container.restart(timeout=timeout_s)
        container.reload()
        return {
            "service": service,
            "container_id": container.short_id,
            "status": container.status,
        }

    return await asyncio.to_thread(_do_restart)


async def exec_in_container(
    service: str, cmd: list[str], *, timeout_s: float = 60.0,
) -> dict:
    """Run a command in the named compose service and return
    stdout/stderr/exit_code."""

    def _do_run() -> dict:
        client = _docker_client()
        containers = client.containers.list(
            filters={
                "label": [
                    "com.docker.compose.project=backend",
                    f"com.docker.compose.service={service}",
                ],
            },
        )
        if not containers:
            raise RuntimeError(f"no running container for service {service}")
        container = containers[0]
        result = container.exec_run(cmd, demux=True)
        stdout, stderr = result.output
        return {
            "exit_code": result.exit_code,
            "stdout": (stdout or b"").decode("utf-8", errors="replace"),
            "stderr": (stderr or b"").decode("utf-8", errors="replace"),
        }

    return await asyncio.wait_for(asyncio.to_thread(_do_run), timeout_s)


def short_container_for(service: str) -> Optional[str]:
    try:
        client = _docker_client()
        cs = client.containers.list(
            all=True,
            filters={
                "label": [
                    "com.docker.compose.project=backend",
                    f"com.docker.compose.service={service}",
                ],
            },
        )
        return cs[0].short_id if cs else None
    except Exception as e:
        logger.debug("short_container_for %s failed: %s", service, e)
        return None
