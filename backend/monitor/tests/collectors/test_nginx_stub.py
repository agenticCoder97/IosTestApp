"""_nginx_stub parses the stub_status text format + fetches via httpx."""
from unittest.mock import AsyncMock, MagicMock

import pytest

from monitor.collectors import _nginx_stub as mod


STUB_SAMPLE = """Active connections: 7
server accepts handled requests
 42 42 118
Reading: 0 Writing: 1 Waiting: 6
"""


def test_parse_stub_text():
    out = mod.parse_stub(STUB_SAMPLE)
    assert out == {
        "active_connections": 7,
        "accepts": 42,
        "handled": 42,
        "total_requests": 118,
        "reading": 0,
        "writing": 1,
        "waiting": 6,
    }


def test_parse_handles_missing_third_line():
    bad = "Active connections: 3 \nReading: 0 Writing: 0 Waiting: 3\n"
    out = mod.parse_stub(bad)
    assert out == {}


@pytest.mark.asyncio
async def test_fetch_stub_success(monkeypatch):
    fake_response = MagicMock()
    fake_response.text = STUB_SAMPLE
    fake_response.status_code = 200
    fake_response.raise_for_status = MagicMock()

    class FakeClient:
        async def __aenter__(self):
            return self
        async def __aexit__(self, *args):
            return False
        async def get(self, url, timeout=None):
            return fake_response

    monkeypatch.setattr(mod.httpx, "AsyncClient", lambda *a, **kw: FakeClient())

    result = await mod.fetch_stub()
    assert result["active_connections"] == 7
    assert result["total_requests"] == 118


@pytest.mark.asyncio
async def test_fetch_stub_network_error_returns_empty(monkeypatch):
    class FakeClient:
        async def __aenter__(self):
            return self
        async def __aexit__(self, *args):
            return False
        async def get(self, url, timeout=None):
            raise ConnectionError("refused")

    monkeypatch.setattr(mod.httpx, "AsyncClient", lambda *a, **kw: FakeClient())

    result = await mod.fetch_stub()
    assert result == {}
