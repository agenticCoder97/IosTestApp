"""nginx_access_sampler emits a '1m_api' window filtered to /api/* paths.

The existing 5 windows (1h, 6h, 24h, 7d, 30d) count every request that
reaches nginx. '1m_api' is a narrower view used by the fastapi service
card footer to show live RPS for the prod API specifically.
"""
import pytest

from monitor.bg import _compute_window, _WINDOWS_S


def test_compute_window_api_filter():
    records = [
        {"ts_ms": 1000, "method": "GET", "path": "/monitor/",    "status": 200, "rt_ms": 12},
        {"ts_ms": 2000, "method": "GET", "path": "/metrics",      "status": 200, "rt_ms": 8},
        {"ts_ms": 3000, "method": "GET", "path": "/static/foo.png","status": 200, "rt_ms": 6},
        {"ts_ms": 4000, "method": "GET", "path": "/api/v1/comics","status": 200, "rt_ms": 40},
        {"ts_ms": 5000, "method": "GET", "path": "/api/v1/health","status": 200, "rt_ms": 4},
    ]
    api_only = [r for r in records if r["path"].startswith("/api/")]
    out = _compute_window(api_only, "1m_api")
    assert out["status_codes"]["2xx"] == 2
    assert out["status_codes"]["5xx"] == 0
    assert all(e["path"].startswith("/api/") for e in out["slowest"])


def test_1m_api_registered_in_windows():
    assert "1m_api" in _WINDOWS_S
    assert _WINDOWS_S["1m_api"] == 60
