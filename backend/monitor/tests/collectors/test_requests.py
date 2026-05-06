"""nginx access log parsing + requests.collect()."""
from datetime import UTC, datetime

import pytest

from monitor.bg import NGINX_ACCESS_RECORDS, NGINX_WINDOW_CACHE, _parse_log_line
from monitor.collectors import requests_ as req_mod
from monitor.requests_metrics import build_requests_block
from monitor.traffic import RequestFilters


def _now_ms() -> int:
    return int(datetime.now(UTC).timestamp() * 1000)


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
    assert rec["traffic_class"] == "app"
    assert rec["classification_reason"] == "api_path"


def test_parse_invalid_line_returns_none():
    assert _parse_log_line("junk") is None


def test_build_requests_block_emits_schema_shape():
    records = [
        {
            "ts_ms": 1000,
            "method": "GET",
            "path": "/api/a",
            "status": 200,
            "rt_ms": 10,
            "traffic_class": "app",
            "classification_reason": "api_path",
        },
        {
            "ts_ms": 2000,
            "method": "GET",
            "path": "/api/a",
            "status": 200,
            "rt_ms": 20,
            "traffic_class": "app",
            "classification_reason": "api_path",
        },
        {
            "ts_ms": 3000,
            "method": "GET",
            "path": "/api/b",
            "status": 500,
            "rt_ms": 500,
            "traffic_class": "app",
            "classification_reason": "api_path",
        },
    ]
    out = build_requests_block(records, "6h", RequestFilters())
    assert out.window == "6h"
    assert out.status_codes.two_xx == 2
    assert out.status_codes.five_xx == 1
    assert len(out.slowest) >= 1


@pytest.mark.asyncio
async def test_collect_reads_cache():
    NGINX_WINDOW_CACHE.clear()
    NGINX_ACCESS_RECORDS.clear()
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
    NGINX_ACCESS_RECORDS.clear()
    block = await req_mod.collect("6h")
    assert block.window == "6h"
    assert block.series_rps == []


@pytest.mark.asyncio
async def test_collect_defaults_to_app_traffic_only():
    NGINX_WINDOW_CACHE.clear()
    NGINX_ACCESS_RECORDS.clear()
    now_ms = _now_ms()
    NGINX_ACCESS_RECORDS.extend(
        [
            {
                "ts_ms": now_ms,
                "method": "GET",
                "path": "/api/v1/comics",
                "status": 200,
                "rt_ms": 10,
                "traffic_class": "app",
                "classification_reason": "api_path",
            },
            {
                "ts_ms": now_ms,
                "method": "POST",
                "path": "/cgi-bin/.%2e/bin/sh",
                "status": 404,
                "rt_ms": 30,
                "traffic_class": "noise",
                "classification_reason": "cgi_traversal_probe",
            },
        ]
    )

    block = await req_mod.collect("1h")

    assert block.status_codes.two_xx == 1
    assert block.status_codes.four_xx == 0
    assert [endpoint.path for endpoint in block.slowest] == ["/api/v1/comics"]


@pytest.mark.asyncio
async def test_collect_accepts_noise_filter():
    NGINX_WINDOW_CACHE.clear()
    NGINX_ACCESS_RECORDS.clear()
    now_ms = _now_ms()
    NGINX_ACCESS_RECORDS.extend(
        [
            {
                "ts_ms": now_ms,
                "method": "GET",
                "path": "/api/v1/comics",
                "status": 200,
                "rt_ms": 10,
                "traffic_class": "app",
                "classification_reason": "api_path",
            },
            {
                "ts_ms": now_ms,
                "method": "POST",
                "path": "/cgi-bin/.%2e/bin/sh",
                "status": 404,
                "rt_ms": 30,
                "traffic_class": "noise",
                "classification_reason": "cgi_traversal_probe",
            },
        ]
    )

    block = await req_mod.collect("1h", filters=RequestFilters(traffic="noise"))

    assert block.status_codes.two_xx == 0
    assert block.status_codes.four_xx == 1
    assert [endpoint.path for endpoint in block.slowest] == ["/cgi-bin/.%2e/bin/sh"]


@pytest.mark.asyncio
async def test_collect_filter_respects_window_range():
    NGINX_WINDOW_CACHE.clear()
    NGINX_ACCESS_RECORDS.clear()
    now_ms = _now_ms()
    outside_window_ms = now_ms - 3_600_001
    NGINX_ACCESS_RECORDS.extend(
        [
            {
                "ts_ms": outside_window_ms,
                "method": "GET",
                "path": "/api/old",
                "status": 200,
                "rt_ms": 10,
                "traffic_class": "app",
                "classification_reason": "api_path",
            },
            {
                "ts_ms": outside_window_ms,
                "method": "POST",
                "path": "/cgi-bin/old",
                "status": 404,
                "rt_ms": 30,
                "traffic_class": "noise",
                "classification_reason": "cgi_traversal_probe",
            },
            {
                "ts_ms": now_ms,
                "method": "POST",
                "path": "/cgi-bin/new",
                "status": 404,
                "rt_ms": 40,
                "traffic_class": "noise",
                "classification_reason": "cgi_traversal_probe",
            },
        ]
    )

    block = await req_mod.collect("1h", filters=RequestFilters(traffic="noise"))

    assert block.status_codes.four_xx == 1
    assert [endpoint.path for endpoint in block.slowest] == ["/cgi-bin/new"]
