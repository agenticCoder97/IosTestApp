import pytest
from httpx import AsyncClient, ASGITransport


@pytest.mark.asyncio
async def test_healthz_returns_ok():
    from monitor.main import app

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        resp = await c.get("/healthz")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


@pytest.mark.asyncio
async def test_root_serves_index_html():
    from monitor.main import app

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        resp = await c.get("/")
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("text/html")
    assert b"<title>astral" in resp.content.lower()


@pytest.mark.asyncio
async def test_index_html_ast78_polish_markers():
    """Protects the AST-78 polish surface from regressions."""
    from monitor.main import app

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        resp = await c.get("/")
    assert resp.status_code == 200
    html = resp.text

    required = [
        "section-body",          # AST-83 collapsible wrappers
        "tbtn",                  # AST-87 primary-button class
        "sql-results",           # AST-88 results wrapper
        "svc-flip",              # AST-78-ext2 flip wrapper
        "table-scroll",          # AST-91 table wrapper
        "svc-terminal",          # AST-78-ext2 terminal button
        "__MONITOR_PREVIEW__",   # AST-86 preview-flag setter
        "req-traffic",           # AST-93 request filter controls
        "req-controls",          # AST-93 filter bar wrapper
        "refreshRequestsOnly",   # AST-93 filter-aware fetch function
        "deploy-status",         # AST-95 deploy status filter
        "audit-action",          # AST-95 audit action filter
        "installPanelControls",  # AST-95 panel control wiring
    ]
    for needle in required:
        assert needle in html, f"missing marker: {needle}"

    banned = [
        'class="env-pill"',            # AST-79
        'id="auto"',                   # AST-81 toggle UI
        "Incidents · last 24h",        # AST-89
        'id="sql-result"',             # AST-88 — old container id
    ]
    for needle in banned:
        assert needle not in html, f"regression: {needle!r} should have been removed"


@pytest.mark.asyncio
async def test_index_html_ast92_terminal_markers():
    """Protects AST-92 terminal shell surface."""
    from monitor.main import app
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        resp = await c.get("/")
    html = resp.text
    required = [
        "@xterm/xterm@5",                # CDN include
        "@xterm/addon-fit",              # fit addon
        'data-min-term="',               # minimize button data attr
        'data-term-body="',              # term-body data attr
        "controls.js?v=12",              # cache bust
    ]
    for needle in required:
        assert needle in html, f"AST-92 marker missing: {needle}"
    assert "real exec channel lands in AST-92" not in html
    assert "Terminal UI is a stub" not in html


@pytest.mark.asyncio
async def test_metrics_requests_route_filters_noise():
    from datetime import UTC, datetime

    from monitor import bg
    from monitor.main import app

    bg.NGINX_ACCESS_RECORDS.clear()
    now_ms = int(datetime.now(UTC).timestamp() * 1000)
    bg.NGINX_ACCESS_RECORDS.extend([
        {"ts_ms": now_ms, "method": "GET", "path": "/api/v1/comics", "status": 200, "rt_ms": 10,
         "traffic_class": "app", "classification_reason": "api_path"},
        {"ts_ms": now_ms, "method": "POST", "path": "/cgi-bin/.%2e/bin/sh", "status": 404, "rt_ms": 30,
         "traffic_class": "noise", "classification_reason": "cgi_traversal_probe"},
    ])

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        resp = await c.get("/metrics/requests?range=1h&traffic=noise")

    assert resp.status_code == 200
    body = resp.json()
    assert body["status_codes"]["4xx"] == 1
    assert body["slowest"][0]["path"] == "/cgi-bin/.%2e/bin/sh"


@pytest.mark.asyncio
async def test_metrics_requests_debug_returns_reason_counts():
    from datetime import UTC, datetime

    from monitor import bg
    from monitor.main import app

    bg.NGINX_ACCESS_RECORDS.clear()
    now_ms = int(datetime.now(UTC).timestamp() * 1000)
    bg.NGINX_ACCESS_RECORDS.extend([
        {"ts_ms": now_ms, "method": "GET", "path": "/api/v1/comics", "status": 200, "rt_ms": 10,
         "traffic_class": "app", "classification_reason": "api_path"},
        {"ts_ms": now_ms, "method": "POST", "path": "/cgi-bin/.%2e/bin/sh", "status": 404, "rt_ms": 30,
         "traffic_class": "noise", "classification_reason": "cgi_traversal_probe"},
    ])
    bg.NGINX_SAMPLER_META.update({"elapsed_ms": 9, "parse_failures": 0})

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        resp = await c.get("/metrics/requests/debug?range=1h&limit=5")

    assert resp.status_code == 200
    body = resp.json()
    assert body["traffic_counts"]["app"] == 1
    assert body["traffic_counts"]["noise"] == 1
    assert body["reason_counts"]["cgi_traversal_probe"] == 1
    assert body["sampler"]["elapsed_ms"] == 9
