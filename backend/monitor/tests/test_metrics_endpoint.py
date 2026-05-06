"""Integration: GET /metrics aggregates all collectors, degrades gracefully."""
import pytest
from httpx import AsyncClient, ASGITransport

from monitor import bg


@pytest.mark.asyncio
async def test_metrics_returns_schema_shape(monkeypatch):
    from monitor.collectors import (
        cost, services, requests_, arq, storage, backups, cert, logs,
    )

    async def _cost():
        from monitor.schema import CostBlock, AlwaysFree, CapUsage
        return CostBlock(
            currency="USD", month_to_date=0.0, forecast=0.0, budget=1.0, last_alert=None,
            always_free=AlwaysFree(
                a1_ocpu=CapUsage(used=4, cap=4, unit="ocpu"),
                a1_ram_gb=CapUsage(used=24, cap=24, unit="GB"),
                block_vol_gb=CapUsage(used=150, cap=200, unit="GB"),
                egress_tb=CapUsage(used=0.1, cap=10, unit="TB"),
                object_std_gb=CapUsage(used=1, cap=20, unit="GB"),
            ),
        )

    monkeypatch.setattr(cost, "collect", _cost)

    async def _svc():
        return []

    monkeypatch.setattr(services, "collect", _svc)

    async def _req(window="6h"):
        from monitor.schema import RequestsBlock
        return RequestsBlock(
            window=window, series_rps=[], series_p95_ms=[],
            status_codes={"2xx": 0, "3xx": 0, "4xx": 0, "5xx": 0}, slowest=[],
        )

    monkeypatch.setattr(requests_, "collect", _req)

    async def _arq():
        from monitor.schema import ArqBlock
        return ArqBlock(
            queue_depth=0, in_flight=0, workers=3,
            completed_24h=0, failed_24h=0,
            active=[], recent_completed=[], recent_failed=[],
        )

    monkeypatch.setattr(arq, "collect", _arq)

    async def _sto():
        from monitor.schema import StorageBlock, StorageTrend
        return StorageBlock(
            postgres_bytes=None, media_bytes=None, block_vol=None, object_storage=None,
            trend_7d=StorageTrend(postgres=[0], media=[0], block_free=[0], object_used=[0]),
        )

    monkeypatch.setattr(storage, "collect", _sto)

    async def _bk():
        from monitor.schema import BackupsBlock
        return BackupsBlock(
            last_pg_dump=None, last_size_bytes=None, status="stale",
            next_run_in_s=3600, bucket="astral-backups",
            retention_days=56, recent_runs=[],
        )

    monkeypatch.setattr(backups, "collect", _bk)

    async def _ct():
        from monitor.schema import CertBlock, CertRenew
        return CertBlock(
            domain="astral-reader.duckdns.org", issuer=None,
            not_before=None, not_after=None, days_left=None,
            last_renew=CertRenew(at=None, status="failed"),
        )

    monkeypatch.setattr(cert, "collect", _ct)

    async def _lg(limit=bg.LOG_METRICS_LIMIT, svc=None, q=None):
        return []

    monkeypatch.setattr(logs, "collect", _lg)

    from monitor.main import app

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        resp = await c.get("/metrics?range=6h")
    assert resp.status_code == 200
    body = resp.json()
    for key in (
        "schema_version", "generated_at", "cost", "services", "requests",
        "arq", "storage", "backups", "cert", "logs",
    ):
        assert key in body
    assert body["cost"]["budget"] == 1.0


@pytest.mark.asyncio
async def test_endpoint_cache_normalizes_raw_paths():
    """Two concrete comic-page paths with different IDs must aggregate under one
    normalized key so that /metrics/endpoint?path=/api/v1/comics/{id}/...
    returns data rather than 404.
    """
    from monitor import bg
    from monitor.main import app
    from httpx import AsyncClient, ASGITransport

    records = [
        {"ts_ms": 1_000, "method": "GET", "path": "/api/v1/comics/abc/chapters/1/pages",
         "status": 200, "rt_ms": 300, "traffic_class": "app"},
        {"ts_ms": 2_000, "method": "GET", "path": "/api/v1/comics/xyz/chapters/3/pages",
         "status": 200, "rt_ms": 350, "traffic_class": "app"},
        {"ts_ms": 3_000, "method": "GET", "path": "/api/v1/comics/xyz/chapters/3/pages",
         "status": 500, "rt_ms": 900, "traffic_class": "app"},
    ]

    bg._build_endpoint_cache(records, "6h")

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        resp = await c.get(
            "/metrics/endpoint",
            params={"method": "GET", "path": "/api/v1/comics/{id}/chapters/{id}/pages", "range": "6h"},
        )

    assert resp.status_code == 200
    body = resp.json()
    assert body["total_requests"] == 3
    assert body["path"] == "/api/v1/comics/{id}/chapters/{id}/pages"
