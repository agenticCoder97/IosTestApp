"""HTTP-level tests for POST /control/exec/start (AST-92)."""
from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient
from httpx import ASGITransport, AsyncClient
from starlette.websockets import WebSocketDisconnect


@pytest.fixture
def app_with_token(monkeypatch):
    monkeypatch.setenv("MONITOR_CONTROL_TOKEN", "s3cret")
    container = SimpleNamespace(id="abc123full", short_id="abc123")
    api = MagicMock()
    api.exec_create.return_value = {"Id": "exec-xyz"}

    class _Sock:
        _sock = MagicMock()
        def close(self): pass
    api.exec_start.return_value = _Sock()
    api.exec_inspect.return_value = {"Running": False}

    client = SimpleNamespace(
        containers=SimpleNamespace(list=lambda **_: [container]),
        api=api,
    )
    from monitor.control import docker_ops, exec as exec_mod
    monkeypatch.setattr(docker_ops, "_docker_client", lambda: client)
    monkeypatch.setattr(exec_mod, "_docker_client", lambda: client,
                        raising=False)
    exec_mod._REGISTRY.clear()
    exec_mod._SERVICE_LOCKS.clear()

    from monitor.main import app
    return app


@pytest.mark.asyncio
async def test_start_requires_token_header(app_with_token):
    transport = ASGITransport(app=app_with_token)
    async with AsyncClient(transport=transport, base_url="http://t") as c:
        resp = await c.post("/control/exec/start",
                            json={"service": "postgres", "cols": 80, "rows": 24})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_start_rejects_non_allowlisted_service(app_with_token):
    transport = ASGITransport(app=app_with_token)
    async with AsyncClient(transport=transport, base_url="http://t") as c:
        resp = await c.post(
            "/control/exec/start",
            json={"service": "astral_monitor", "cols": 80, "rows": 24},
            headers={"X-Monitor-Auth": "s3cret"},
        )
    assert resp.status_code == 400
    assert "not exec-allowed" in resp.json()["detail"]


@pytest.mark.asyncio
async def test_start_returns_session_id(app_with_token):
    transport = ASGITransport(app=app_with_token)
    async with AsyncClient(transport=transport, base_url="http://t") as c:
        resp = await c.post(
            "/control/exec/start",
            json={"service": "postgres", "cols": 80, "rows": 24},
            headers={"X-Monitor-Auth": "s3cret"},
        )
    assert resp.status_code == 200
    body = resp.json()
    assert "session_id" in body and len(body["session_id"]) == 32


@pytest.mark.asyncio
async def test_duplicate_start_returns_409(app_with_token):
    transport = ASGITransport(app=app_with_token)
    async with AsyncClient(transport=transport, base_url="http://t") as c:
        headers = {"X-Monitor-Auth": "s3cret"}
        body = {"service": "redis", "cols": 80, "rows": 24}
        r1 = await c.post("/control/exec/start", json=body, headers=headers)
        assert r1.status_code == 200
        r2 = await c.post("/control/exec/start", json=body, headers=headers)
    assert r2.status_code == 409
    assert "already open" in r2.json()["detail"]


@pytest.mark.asyncio
async def test_missing_token_env_returns_503(app_with_token, monkeypatch):
    monkeypatch.delenv("MONITOR_CONTROL_TOKEN", raising=False)
    transport = ASGITransport(app=app_with_token)
    async with AsyncClient(transport=transport, base_url="http://t") as c:
        resp = await c.post(
            "/control/exec/start",
            json={"service": "postgres", "cols": 80, "rows": 24},
            headers={"X-Monitor-Auth": "anything"},
        )
    assert resp.status_code == 503


# ── WebSocket handshake tests ─────────────────────────────────────────


def _start_session_sync(client: TestClient, service="postgres") -> str:
    r = client.post("/control/exec/start",
                    json={"service": service, "cols": 80, "rows": 24},
                    headers={"X-Monitor-Auth": "s3cret"})
    assert r.status_code == 200, r.text
    return r.json()["session_id"]


def test_ws_rejects_without_subprotocol(app_with_token):
    client = TestClient(app_with_token)
    sid = _start_session_sync(client)
    with pytest.raises(WebSocketDisconnect) as exc:
        with client.websocket_connect(f"/control/exec/{sid}"):
            pass
    assert exc.value.code == 1008


def test_ws_rejects_bad_token(app_with_token):
    client = TestClient(app_with_token)
    sid = _start_session_sync(client)
    with pytest.raises(WebSocketDisconnect) as exc:
        with client.websocket_connect(
            f"/control/exec/{sid}",
            subprotocols=["monitor-token", "wrong"],
        ):
            pass
    assert exc.value.code == 1008


def test_ws_rejects_unknown_session(app_with_token):
    client = TestClient(app_with_token)
    with pytest.raises(WebSocketDisconnect) as exc:
        with client.websocket_connect(
            "/control/exec/deadbeef",
            subprotocols=["monitor-token", "s3cret"],
        ):
            pass
    assert exc.value.code == 1008


def test_ws_rejects_bad_origin(app_with_token):
    client = TestClient(app_with_token)
    sid = _start_session_sync(client)
    with pytest.raises(WebSocketDisconnect) as exc:
        with client.websocket_connect(
            f"/control/exec/{sid}",
            subprotocols=["monitor-token", "s3cret"],
            headers={"origin": "https://evil.example.com"},
        ):
            pass
    assert exc.value.code == 1008


def test_ws_accepts_with_subprotocol_and_allowed_origin(app_with_token):
    client = TestClient(app_with_token)
    sid = _start_session_sync(client)
    # Default TestClient omits Origin — treated as allowed (server-to-server).
    with client.websocket_connect(
        f"/control/exec/{sid}",
        subprotocols=["monitor-token", "s3cret"],
    ) as ws:
        # Just accept/close — pumps land in Task 5.
        ws.close()
