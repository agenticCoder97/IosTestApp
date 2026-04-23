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
        "controls.js?v=11",              # cache bust
    ]
    for needle in required:
        assert needle in html, f"AST-92 marker missing: {needle}"
    assert "real exec channel lands in AST-92" not in html
    assert "Terminal UI is a stub" not in html
