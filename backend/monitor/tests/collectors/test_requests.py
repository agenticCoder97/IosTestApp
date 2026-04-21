"""nginx access log parsing + requests.collect()."""
import pytest

from monitor.bg import NGINX_WINDOW_CACHE, _parse_log_line, _compute_window
from monitor.collectors import requests_ as req_mod


def test_parse_valid_line():
    line = (
        '1.2.3.4 - dev [2026-04-21T14:23:05+00:00] '
        '"GET /api/v1/comics HTTP/1.1" 200 3412 '
        'rt=0.042 urt="0.040" "-" "iOS/Astral"'
    )
    rec = _parse_log_line(line)
    assert rec is not None
    assert rec["method"] == "GET"
    assert rec["path"] == "/api/v1/comics"
    assert rec["status"] == 200
    assert rec["rt_ms"] == 42


def test_parse_invalid_line_returns_none():
    assert _parse_log_line("junk") is None


def test_compute_window_emits_schema_shape():
    records = [
        {"ts_ms": 1000, "method": "GET", "path": "/a", "status": 200, "rt_ms": 10},
        {"ts_ms": 2000, "method": "GET", "path": "/a", "status": 200, "rt_ms": 20},
        {"ts_ms": 3000, "method": "GET", "path": "/b", "status": 500, "rt_ms": 500},
    ]
    out = _compute_window(records, "6h")
    assert out["window"] == "6h"
    assert out["status_codes"]["2xx"] == 2
    assert out["status_codes"]["5xx"] == 1
    assert len(out["slowest"]) >= 1


@pytest.mark.asyncio
async def test_collect_reads_cache():
    NGINX_WINDOW_CACHE.clear()
    NGINX_WINDOW_CACHE["24h"] = {
        "window": "24h",
        "series_rps": [[1_713_614_400_000, 1.2]],
        "series_p95_ms": [[1_713_614_400_000, 120]],
        "status_codes": {"2xx": 10, "3xx": 0, "4xx": 0, "5xx": 0},
        "slowest": [],
    }
    block = await req_mod.collect("24h")
    assert block.window == "24h"
    assert block.status_codes.two_xx == 10


@pytest.mark.asyncio
async def test_collect_returns_empty_when_not_yet_sampled():
    NGINX_WINDOW_CACHE.clear()
    block = await req_mod.collect("6h")
    assert block.window == "6h"
    assert block.series_rps == []
