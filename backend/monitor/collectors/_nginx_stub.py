"""nginx ngx_http_stub_status_module scraper.

Parses the 7-line text response from `location = /nginx_status`:

    Active connections: 7
    server accepts handled requests
     42 42 118
    Reading: 0 Writing: 1 Waiting: 6

Returns a flat dict of ints or {} on any error. The monitor's
_fetch_service_extra("nginx") consumes this for the nginx card's
footer live stats.
"""
from __future__ import annotations

import logging
import re

import httpx

logger = logging.getLogger("monitor.nginx_stub")

_STUB_URL = "http://nginx/nginx_status"
_TIMEOUT_S = 2.0

_ACTIVE_RE  = re.compile(r"Active connections:\s*(\d+)")
_ACCEPTS_RE = re.compile(r"\s*(\d+)\s+(\d+)\s+(\d+)\s*")
_READING_RE = re.compile(r"Reading:\s*(\d+)\s+Writing:\s*(\d+)\s+Waiting:\s*(\d+)")


def parse_stub(text: str) -> dict:
    """Parse stub_status text. Returns {} if the expected 4-line shape is missing."""
    try:
        m_active = _ACTIVE_RE.search(text)
        m_read   = _READING_RE.search(text)
        if not (m_active and m_read):
            return {}
        lines = text.splitlines()
        counts = None
        for i, ln in enumerate(lines):
            if "accepts handled requests" in ln and i + 1 < len(lines):
                m = _ACCEPTS_RE.match(lines[i + 1])
                if m:
                    counts = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
                break
        if counts is None:
            return {}
        return {
            "active_connections": int(m_active.group(1)),
            "accepts":             counts[0],
            "handled":             counts[1],
            "total_requests":      counts[2],
            "reading":             int(m_read.group(1)),
            "writing":             int(m_read.group(2)),
            "waiting":             int(m_read.group(3)),
        }
    except Exception as e:
        logger.debug("parse_stub failed: %s", e)
        return {}


async def fetch_stub() -> dict:
    """HTTP GET /nginx_status via docker-internal hostname, parse the response.

    Returns {} on any network or parse error — caller falls back to its
    existing approximation.
    """
    try:
        async with httpx.AsyncClient(base_url="") as c:
            resp = await c.get(_STUB_URL, timeout=_TIMEOUT_S)
            resp.raise_for_status()
            return parse_stub(resp.text)
    except Exception as e:
        logger.debug("fetch_stub failed: %s", e)
        return {}
