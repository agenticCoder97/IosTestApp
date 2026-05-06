"""nginx_access_sampler emits a '1m_api' window filtered to /api/* app paths.

The existing 5 dashboard windows default to app traffic in
NGINX_WINDOW_CACHE. '1m_api' is the narrower 60-second view used by the
fastapi service card footer to show live RPS for the prod API specifically.
"""
from monitor import requests_metrics
from monitor.bg import (
    NGINX_ACCESS_RECORDS,
    NGINX_ENDPOINT_CACHE,
    NGINX_WINDOW_CACHE,
    _refresh_nginx_request_caches,
)


def test_1m_api_app_only_block_counts_api_app_traffic():
    NGINX_ACCESS_RECORDS.clear()
    NGINX_WINDOW_CACHE.clear()
    NGINX_ENDPOINT_CACHE.clear()
    now_ms = 10_000_000
    records = [
        {
            "ts_ms": now_ms - 59_000,
            "method": "GET",
            "path": "/monitor/",
            "status": 200,
            "rt_ms": 12,
            "traffic_class": "monitor",
            "classification_reason": "monitor_path",
        },
        {
            "ts_ms": now_ms - 59_000,
            "method": "GET",
            "path": "/static/foo.png",
            "status": 200,
            "rt_ms": 6,
            "traffic_class": "static",
            "classification_reason": "static_path",
        },
        {
            "ts_ms": now_ms - 59_000,
            "method": "GET",
            "path": "/api/v1/comics",
            "status": 200,
            "rt_ms": 40,
            "traffic_class": "app",
            "classification_reason": "api_path",
        },
        {
            "ts_ms": now_ms - 59_000,
            "method": "GET",
            "path": "/api/v1/health",
            "status": 200,
            "rt_ms": 4,
            "traffic_class": "app",
            "classification_reason": "api_path",
        },
        {
            "ts_ms": now_ms - 60_001,
            "method": "GET",
            "path": "/api/old",
            "status": 200,
            "rt_ms": 1,
            "traffic_class": "app",
            "classification_reason": "api_path",
        },
    ]

    _refresh_nginx_request_caches(records, 0, [], now_ms=now_ms)

    out = NGINX_WINDOW_CACHE["1m_api"]
    assert out["status_codes"]["2xx"] == 2
    assert out["status_codes"]["5xx"] == 0
    assert all(endpoint["path"].startswith("/api/") for endpoint in out["slowest"])


def test_1m_api_registered_in_windows():
    assert requests_metrics.WINDOWS_S["1m_api"] == 60
