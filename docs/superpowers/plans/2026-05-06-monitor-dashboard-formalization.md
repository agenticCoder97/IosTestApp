# Monitor Dashboard Formalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the monitor dashboard explain Astral metrics clearly by defaulting Requests to app traffic, hiding scanner noise unless selected, preserving UI state through refresh, and adding auditable debugging surfaces.

**Architecture:** Backend request meaning lives in focused request-classification and request-aggregation modules. `/metrics` keeps serving the full dashboard with app-default Requests, while `/metrics/requests` and `/metrics/requests/debug` serve panel-local request filtering and diagnostics. Frontend state is split into metric data, panel filters, and UI interaction state so background refresh updates data without resetting active controls.

**Tech Stack:** Python 3.11, FastAPI, Pydantic v2, pytest, vanilla HTML/CSS/JavaScript in `backend/monitor/static/index.html`, existing monitor sidecar patterns.

---

## File Structure

- Create `backend/monitor/traffic.py`: request traffic classification, reason codes, filter model, redaction helpers.
- Create `backend/monitor/requests_metrics.py`: request window aggregation, filtered `RequestsBlock` building, debug summary building.
- Create `backend/monitor/tests/test_traffic_classification.py`: classifier and redaction tests.
- Create `backend/monitor/tests/test_requests_metrics.py`: filtered aggregation and debug summary tests.
- Modify `backend/monitor/bg.py`: classify parsed access-log records, keep recent classified records, compute default app-only request windows, emit structured sampler logs.
- Modify `backend/monitor/collectors/requests_.py`: accept request filters and return filtered `RequestsBlock` from recent classified records.
- Modify `backend/monitor/schema.py`: add request filter/debug models while keeping `MetricsResponse` stable.
- Modify `backend/monitor/main.py`: add `/metrics/requests` and `/metrics/requests/debug`, make embedded `/metrics.requests` use app-default filters.
- Modify `backend/monitor/static/index.html`: add explicit `STATE.filters` and `STATE.ui`, Requests controls, request diagnostics helper, service-card face preservation.
- Modify `backend/monitor/static/controls.js`: avoid post-render decoration from resetting service-card state and keep debug logging quiet unless enabled.
- Modify `backend/monitor/tests/test_main.py`: route tests for request filters and debug endpoint.

Do not touch existing iOS files or Xcode project files in this work.

---

### Task 1: Add Traffic Classifier

**Files:**
- Create: `backend/monitor/traffic.py`
- Test: `backend/monitor/tests/test_traffic_classification.py`

- [ ] **Step 1: Write failing classifier tests**

Create `backend/monitor/tests/test_traffic_classification.py` with:

```python
from monitor.traffic import classify_request, redact_sample


def test_classifies_astral_api_as_app():
    c = classify_request("GET", "/api/v1/comics")
    assert c.traffic_class == "app"
    assert c.reason == "api_path"


def test_classifies_static_as_static():
    c = classify_request("GET", "/static/comics/x/001.jpg")
    assert c.traffic_class == "static"
    assert c.reason == "static_path"


def test_classifies_monitor_control_as_monitor():
    c = classify_request("POST", "/monitor/control/exec/start")
    assert c.traffic_class == "monitor"
    assert c.reason == "monitor_path"


def test_classifies_cgi_traversal_probe_as_noise():
    c = classify_request("POST", "/cgi-bin/.%2e/.%2e/.%2e/.%2e/bin/sh")
    assert c.traffic_class == "noise"
    assert c.reason == "cgi_traversal_probe"


def test_classifies_double_encoded_traversal_probe_as_noise():
    c = classify_request("POST", "/cgi-bin/%%32%65%%32%65/%%32%65%%32%65/bin/sh")
    assert c.traffic_class == "noise"
    assert c.reason == "cgi_traversal_probe"


def test_classifies_smb_bytes_as_noise():
    c = classify_request("GET", "\\x00\\x00\\x001\\xFFSMBr\\x00\\x00NT LM")
    assert c.traffic_class == "noise"
    assert c.reason == "binary_or_malformed_request"


def test_classifies_tls_bytes_as_noise():
    c = classify_request("GET", "\\x16\\x03\\x03\\x01\\xA5\\x01\\x00")
    assert c.traffic_class == "noise"
    assert c.reason == "binary_or_malformed_request"


def test_classifies_wordpress_probe_as_noise():
    c = classify_request("GET", "/wp-admin/setup-config.php")
    assert c.traffic_class == "noise"
    assert c.reason == "known_probe_path"


def test_classifies_valid_unknown_path_as_unknown():
    c = classify_request("GET", "/robots.txt")
    assert c.traffic_class == "unknown"
    assert c.reason == "valid_unknown_path"


def test_redact_sample_caps_and_removes_query_values():
    sample = redact_sample('/api/v1/comics?token=secret-value&name=abc', max_len=36)
    assert "secret-value" not in sample
    assert "token=REDACTED" in sample
    assert len(sample) <= 36
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
cd backend
PYTHONPATH=. pytest monitor/tests/test_traffic_classification.py -v
```

Expected: fails with `ModuleNotFoundError: No module named 'monitor.traffic'`.

- [ ] **Step 3: Implement classifier**

Create `backend/monitor/traffic.py`:

```python
"""Traffic classification and filtering helpers for monitor request metrics."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Literal
from urllib.parse import unquote
import re

TrafficClass = Literal["app", "static", "monitor", "noise", "unknown"]
StatusBand = Literal["all", "2xx", "3xx", "4xx", "5xx"]
RankMode = Literal["p95", "count", "error_rate"]


@dataclass(frozen=True)
class TrafficClassification:
    traffic_class: TrafficClass
    reason: str


@dataclass(frozen=True)
class RequestFilters:
    traffic: TrafficClass = "app"
    method: str = "all"
    status: StatusBand = "all"
    q: str = ""
    rank: RankMode = "p95"


_TOKEN_RE = re.compile(r"(?i)(token|auth|password|secret|key)=([^&\\s]+)")
_HEX_ESCAPE_RE = re.compile(r"\\x[0-9a-fA-F]{2}")
_CGI_TRAVERSAL_RE = re.compile(r"(?i)^/cgi-bin/.*(%2e|%%32%65|\\.\\.).*/bin/sh")
_KNOWN_PROBE_PREFIXES = (
    "/wp-admin",
    "/wp-login.php",
    "/phpmyadmin",
    "/.env",
    "/vendor/phpunit",
    "/boaform",
    "/HNAP1",
)


def classify_request(method: str, path: str) -> TrafficClassification:
    """Classify one nginx request path into dashboard traffic classes."""
    raw = path or ""
    decoded_once = _safe_unquote(raw)
    decoded_twice = _safe_unquote(decoded_once)
    lowered = decoded_twice.lower()

    if _looks_binary_or_malformed(raw):
        return TrafficClassification("noise", "binary_or_malformed_request")

    if raw.startswith("/api/") or raw == "/api":
        return TrafficClassification("app", "api_path")

    if raw.startswith("/static/"):
        return TrafficClassification("static", "static_path")

    if (
        raw == "/metrics"
        or raw.startswith("/metrics?")
        or raw.startswith("/monitor")
        or raw.startswith("/control/")
        or raw.startswith("/static/controls.js")
    ):
        return TrafficClassification("monitor", "monitor_path")

    if _CGI_TRAVERSAL_RE.search(raw) or _CGI_TRAVERSAL_RE.search(decoded_twice):
        return TrafficClassification("noise", "cgi_traversal_probe")

    if any(lowered.startswith(prefix.lower()) for prefix in _KNOWN_PROBE_PREFIXES):
        return TrafficClassification("noise", "known_probe_path")

    return TrafficClassification("unknown", "valid_unknown_path")


def status_band(status: int) -> Literal["2xx", "3xx", "4xx", "5xx"]:
    if 200 <= status < 300:
        return "2xx"
    if 300 <= status < 400:
        return "3xx"
    if 400 <= status < 500:
        return "4xx"
    return "5xx"


def record_matches_filters(record: dict, filters: RequestFilters) -> bool:
    if record.get("traffic_class") != filters.traffic:
        return False
    method = filters.method.upper()
    if method != "ALL" and str(record.get("method", "")).upper() != method:
        return False
    if filters.status != "all" and status_band(int(record.get("status", 0))) != filters.status:
        return False
    q = filters.q.strip().lower()
    if q and q not in str(record.get("path", "")).lower():
        return False
    return True


def redact_sample(value: str, max_len: int = 120) -> str:
    redacted = _TOKEN_RE.sub(lambda m: f"{m.group(1)}=REDACTED", value or "")
    return redacted[:max_len]


def _safe_unquote(value: str) -> str:
    try:
        return unquote(value)
    except Exception:
        return value


def _looks_binary_or_malformed(value: str) -> bool:
    if _HEX_ESCAPE_RE.search(value):
        return True
    return any(ord(ch) < 32 and ch not in ("\t", "\n", "\r") for ch in value)
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```bash
cd backend
PYTHONPATH=. pytest monitor/tests/test_traffic_classification.py -v
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add backend/monitor/traffic.py backend/monitor/tests/test_traffic_classification.py
git commit -m "[backend] add monitor request traffic classifier"
```

---

### Task 2: Add Filtered Request Aggregation And Debug Summary

**Files:**
- Create: `backend/monitor/requests_metrics.py`
- Test: `backend/monitor/tests/test_requests_metrics.py`

- [ ] **Step 1: Write failing aggregation tests**

Create `backend/monitor/tests/test_requests_metrics.py`:

```python
from monitor.requests_metrics import build_requests_block, build_request_debug
from monitor.traffic import RequestFilters


def _records():
    return [
        {"ts_ms": 1000, "method": "GET", "path": "/api/v1/comics", "status": 200, "rt_ms": 10, "traffic_class": "app", "classification_reason": "api_path"},
        {"ts_ms": 2000, "method": "POST", "path": "/api/v1/scrape", "status": 500, "rt_ms": 500, "traffic_class": "app", "classification_reason": "api_path"},
        {"ts_ms": 3000, "method": "GET", "path": "/static/comics/x/001.jpg", "status": 200, "rt_ms": 4, "traffic_class": "static", "classification_reason": "static_path"},
        {"ts_ms": 4000, "method": "POST", "path": "/cgi-bin/.%2e/bin/sh", "status": 404, "rt_ms": 30, "traffic_class": "noise", "classification_reason": "cgi_traversal_probe"},
        {"ts_ms": 5000, "method": "GET", "path": "/monitor/", "status": 200, "rt_ms": 8, "traffic_class": "monitor", "classification_reason": "monitor_path"},
    ]


def test_default_app_filter_excludes_static_monitor_and_noise():
    block = build_requests_block(_records(), "6h", RequestFilters())
    assert block.status_codes.two_xx == 1
    assert block.status_codes.five_xx == 1
    assert block.status_codes.four_xx == 0
    assert block.slowest[0].path == "/api/v1/scrape"
    assert all("cgi-bin" not in endpoint.path for endpoint in block.slowest)


def test_noise_filter_returns_noise_only():
    block = build_requests_block(_records(), "6h", RequestFilters(traffic="noise"))
    assert block.status_codes.four_xx == 1
    assert block.slowest[0].path == "/cgi-bin/.%2e/bin/sh"


def test_status_and_method_filters_apply_to_same_record_set():
    block = build_requests_block(_records(), "6h", RequestFilters(method="POST", status="5xx"))
    assert block.status_codes.five_xx == 1
    assert block.status_codes.two_xx == 0
    assert block.slowest[0].method == "POST"
    assert block.slowest[0].path == "/api/v1/scrape"


def test_rank_count_orders_by_request_count():
    records = _records() + [
        {"ts_ms": 6000, "method": "GET", "path": "/api/v1/comics", "status": 200, "rt_ms": 11, "traffic_class": "app", "classification_reason": "api_path"},
        {"ts_ms": 7000, "method": "GET", "path": "/api/v1/comics", "status": 200, "rt_ms": 12, "traffic_class": "app", "classification_reason": "api_path"},
    ]
    block = build_requests_block(records, "6h", RequestFilters(rank="count"))
    assert block.slowest[0].path == "/api/v1/comics"
    assert block.slowest[0].count == 3


def test_debug_summary_counts_match_classified_records():
    debug = build_request_debug(_records(), RequestFilters(), limit=2, sampler_meta={"elapsed_ms": 7})
    assert debug["filters"]["traffic"] == "app"
    assert debug["traffic_counts"]["app"] == 2
    assert debug["traffic_counts"]["noise"] == 1
    assert debug["reason_counts"]["cgi_traversal_probe"] == 1
    assert debug["included_count"] == 2
    assert debug["excluded_count"] == 3
    assert len(debug["included_samples"]) == 2
    assert debug["sampler"]["elapsed_ms"] == 7
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
cd backend
PYTHONPATH=. pytest monitor/tests/test_requests_metrics.py -v
```

Expected: fails with `ModuleNotFoundError: No module named 'monitor.requests_metrics'`.

- [ ] **Step 3: Implement aggregation module**

Create `backend/monitor/requests_metrics.py`:

```python
"""Request metric aggregation for the monitor dashboard."""
from __future__ import annotations

from collections import Counter
from typing import Any

from monitor.schema import RequestsBlock
from monitor.traffic import RequestFilters, record_matches_filters, redact_sample, status_band

_WINDOWS_S = {"1h": 3600, "6h": 21600, "24h": 86400, "7d": 604800, "30d": 2592000, "1m_api": 60}


def build_requests_block(records: list[dict[str, Any]], window: str, filters: RequestFilters) -> RequestsBlock:
    selected = [r for r in records if record_matches_filters(r, filters)]
    status_codes = {"2xx": 0, "3xx": 0, "4xx": 0, "5xx": 0}
    by_path: dict[tuple[str, str], list[dict[str, Any]]] = {}
    bucket_ms = max(60_000, _WINDOWS_S[window] * 1000 // 60)
    series_rps_buckets: dict[int, int] = {}
    series_p95_buckets: dict[int, list[int]] = {}

    for record in selected:
        band = status_band(int(record["status"]))
        status_codes[band] += 1
        key = (str(record["method"]), str(record["path"]))
        by_path.setdefault(key, []).append(record)
        bucket = (int(record["ts_ms"]) // bucket_ms) * bucket_ms
        series_rps_buckets[bucket] = series_rps_buckets.get(bucket, 0) + 1
        series_p95_buckets.setdefault(bucket, []).append(int(record["rt_ms"]))

    series_rps = [[b, series_rps_buckets[b] / (bucket_ms / 1000)] for b in sorted(series_rps_buckets)]
    series_p95 = [[b, _pct(series_p95_buckets[b], 95)] for b in sorted(series_p95_buckets)]

    slowest = []
    for (method, path), group in by_path.items():
        rts = [int(r["rt_ms"]) for r in group]
        total = len(group)
        errors = sum(1 for r in group if int(r["status"]) >= 400)
        slowest.append({
            "method": method,
            "path": path,
            "p50_ms": _pct(rts, 50),
            "p95_ms": _pct(rts, 95),
            "p99_ms": _pct(rts, 99),
            "count": total,
            "_error_rate": errors / total if total else 0,
        })

    if filters.rank == "count":
        slowest.sort(key=lambda row: (row["count"], row["p95_ms"]), reverse=True)
    elif filters.rank == "error_rate":
        slowest.sort(key=lambda row: (row["_error_rate"], row["count"]), reverse=True)
    else:
        slowest.sort(key=lambda row: (row["p95_ms"], row["count"]), reverse=True)

    public_slowest = [
        {k: v for k, v in row.items() if not k.startswith("_")}
        for row in slowest[:10]
    ]

    return RequestsBlock.model_validate({
        "window": window if window != "1m_api" else "1h",
        "series_rps": series_rps,
        "series_p95_ms": series_p95,
        "status_codes": status_codes,
        "slowest": public_slowest,
    })


def build_request_debug(
    records: list[dict[str, Any]],
    filters: RequestFilters,
    limit: int,
    sampler_meta: dict[str, Any] | None = None,
) -> dict[str, Any]:
    included = [r for r in records if record_matches_filters(r, filters)]
    excluded = [r for r in records if not record_matches_filters(r, filters)]
    traffic_counts = Counter(str(r.get("traffic_class", "unknown")) for r in records)
    reason_counts = Counter(str(r.get("classification_reason", "missing")) for r in records)
    return {
        "filters": {
            "traffic": filters.traffic,
            "method": filters.method,
            "status": filters.status,
            "q": filters.q,
            "rank": filters.rank,
        },
        "traffic_counts": dict(traffic_counts),
        "reason_counts": dict(reason_counts),
        "parse_failures": int((sampler_meta or {}).get("parse_failures", 0)),
        "included_count": len(included),
        "excluded_count": len(excluded),
        "included_samples": [_sample_record(r) for r in included[:limit]],
        "excluded_samples": [_sample_record(r) for r in excluded[:limit]],
        "sampler": sampler_meta or {},
    }


def _sample_record(record: dict[str, Any]) -> dict[str, Any]:
    return {
        "method": record.get("method"),
        "path": redact_sample(str(record.get("path", ""))),
        "status": record.get("status"),
        "rt_ms": record.get("rt_ms"),
        "traffic_class": record.get("traffic_class"),
        "reason": record.get("classification_reason"),
    }


def _pct(values: list[int], p: int) -> int:
    if not values:
        return 0
    xs = sorted(values)
    k = int(len(xs) * p / 100)
    return xs[min(k, len(xs) - 1)]
```

- [ ] **Step 4: Run aggregation tests**

Run:

```bash
cd backend
PYTHONPATH=. pytest monitor/tests/test_requests_metrics.py -v
```

Expected: all tests pass.

- [ ] **Step 5: Run classifier and aggregation tests together**

Run:

```bash
cd backend
PYTHONPATH=. pytest monitor/tests/test_traffic_classification.py monitor/tests/test_requests_metrics.py -v
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add backend/monitor/requests_metrics.py backend/monitor/tests/test_requests_metrics.py
git commit -m "[backend] add filtered monitor request aggregation"
```

---

### Task 3: Wire Classified Requests Into Sampler And Collectors

**Files:**
- Modify: `backend/monitor/bg.py`
- Modify: `backend/monitor/collectors/requests_.py`
- Test: `backend/monitor/tests/collectors/test_requests.py`
- Test: `backend/monitor/tests/test_nginx_access_sampler_1m_api.py`

- [ ] **Step 1: Add failing collector tests**

Append to `backend/monitor/tests/collectors/test_requests.py`:

```python
from monitor.bg import NGINX_ACCESS_RECORDS
from monitor.traffic import RequestFilters


@pytest.mark.asyncio
async def test_collect_defaults_to_app_traffic_only():
    NGINX_ACCESS_RECORDS.clear()
    NGINX_ACCESS_RECORDS.extend([
        {"ts_ms": 1000, "method": "GET", "path": "/api/v1/comics", "status": 200, "rt_ms": 10, "traffic_class": "app", "classification_reason": "api_path"},
        {"ts_ms": 2000, "method": "POST", "path": "/cgi-bin/.%2e/bin/sh", "status": 404, "rt_ms": 30, "traffic_class": "noise", "classification_reason": "cgi_traversal_probe"},
    ])
    block = await req_mod.collect("6h")
    assert block.status_codes.two_xx == 1
    assert block.status_codes.four_xx == 0
    assert all("cgi-bin" not in row.path for row in block.slowest)


@pytest.mark.asyncio
async def test_collect_accepts_noise_filter():
    NGINX_ACCESS_RECORDS.clear()
    NGINX_ACCESS_RECORDS.extend([
        {"ts_ms": 1000, "method": "GET", "path": "/api/v1/comics", "status": 200, "rt_ms": 10, "traffic_class": "app", "classification_reason": "api_path"},
        {"ts_ms": 2000, "method": "POST", "path": "/cgi-bin/.%2e/bin/sh", "status": 404, "rt_ms": 30, "traffic_class": "noise", "classification_reason": "cgi_traversal_probe"},
    ])
    block = await req_mod.collect("6h", RequestFilters(traffic="noise"))
    assert block.status_codes.four_xx == 1
    assert block.slowest[0].path == "/cgi-bin/.%2e/bin/sh"
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
cd backend
PYTHONPATH=. pytest monitor/tests/collectors/test_requests.py -v
```

Expected: fails because `NGINX_ACCESS_RECORDS` does not exist or `collect()` does not accept filters.

- [ ] **Step 3: Modify `bg.py` globals and parse classification**

In `backend/monitor/bg.py`, add imports near the existing nginx sampler imports:

```python
from monitor.requests_metrics import build_requests_block
from monitor.traffic import RequestFilters, classify_request, redact_sample
```

Add globals near `NGINX_WINDOW_CACHE`:

```python
NGINX_ACCESS_RECORDS: Deque[dict[str, Any]] = deque(maxlen=100_000)
NGINX_SAMPLER_META: dict[str, Any] = {
    "last_sample_at": None,
    "elapsed_ms": 0,
    "parse_failures": 0,
    "parse_failure_samples": [],
}
```

In `_parse_log_line`, after method/path/status/rt are parsed, classify the request and return the extra fields:

```python
    method = m["method"]
    path = m["path"]
    status = int(m["status"])
    classification = classify_request(method, path)
    return {
        "ts_ms": int(ts.timestamp() * 1000),
        "method": method,
        "path": path,
        "status": status,
        "rt_ms": rt_ms,
        "traffic_class": classification.traffic_class,
        "classification_reason": classification.reason,
    }
```

Replace the old per-window `_compute_window(window_records, w)` call inside `nginx_access_sampler()` with default app filtering:

```python
                NGINX_WINDOW_CACHE[w] = build_requests_block(
                    window_records,
                    w,
                    RequestFilters(traffic="app"),
                ).model_dump(mode="json", by_alias=True)
```

After reading records in `nginx_access_sampler()`, update the global deque and metadata:

```python
            import time as _time
            started = _time.monotonic()
            all_records, parse_failures, failure_samples = await asyncio.to_thread(_read_access_log_records)
            NGINX_ACCESS_RECORDS.clear()
            NGINX_ACCESS_RECORDS.extend(all_records)
            NGINX_SAMPLER_META.update({
                "last_sample_at": _dt.now(_tz.utc).isoformat().replace("+00:00", "Z"),
                "elapsed_ms": int((_time.monotonic() - started) * 1000),
                "parse_failures": parse_failures,
                "parse_failure_samples": failure_samples,
            })
```

Change `_read_access_log_records()` to return records, parse failure count, and samples:

```python
def _read_access_log_records() -> tuple[list[dict], int, list[str]]:
    from collections import deque as _deque

    if not NGINX_ACCESS_PATH.exists():
        return [], 0, []
    tail_buf: "deque[str]" = _deque(maxlen=100_000)
    with NGINX_ACCESS_PATH.open("r", errors="replace") as fh:
        for line in fh:
            tail_buf.append(line)
    out = []
    parse_failures = 0
    failure_samples: list[str] = []
    for line in tail_buf:
        rec = _parse_log_line(line)
        if rec is None:
            parse_failures += 1
            if len(failure_samples) < 10:
                failure_samples.append(redact_sample(line.strip()))
            continue
        out.append(rec)
    return out, parse_failures, failure_samples
```

- [ ] **Step 4: Modify `requests_.py` collector**

Replace `backend/monitor/collectors/requests_.py` with:

```python
"""requests collector — builds filtered request metrics from classified nginx records."""
from __future__ import annotations

from monitor.bg import NGINX_ACCESS_RECORDS, NGINX_WINDOW_CACHE
from monitor.requests_metrics import build_requests_block
from monitor.schema import RequestsBlock
from monitor.traffic import RequestFilters


async def collect(window: str = "6h", filters: RequestFilters | None = None) -> RequestsBlock:
    active = filters or RequestFilters()
    if active == RequestFilters():
        cached = NGINX_WINDOW_CACHE.get(window)
        if cached is not None:
            return RequestsBlock.model_validate(cached)

    records = list(NGINX_ACCESS_RECORDS)
    if not records:
        return RequestsBlock(
            window=window,
            series_rps=[],
            series_p95_ms=[],
            status_codes={"2xx": 0, "3xx": 0, "4xx": 0, "5xx": 0},
            slowest=[],
        )
    return build_requests_block(records, window, active)
```

- [ ] **Step 5: Run request collector tests**

Run:

```bash
cd backend
PYTHONPATH=. pytest monitor/tests/collectors/test_requests.py monitor/tests/test_nginx_access_sampler_1m_api.py -v
```

Expected: all tests pass. If `test_nginx_access_sampler_1m_api.py` still imports `_compute_window`, update that test to import and call `build_requests_block(api_only, "1m_api", RequestFilters(traffic="app"))`.

- [ ] **Step 6: Commit**

```bash
git add backend/monitor/bg.py backend/monitor/collectors/requests_.py backend/monitor/tests/collectors/test_requests.py backend/monitor/tests/test_nginx_access_sampler_1m_api.py
git commit -m "[backend] wire classified request metrics into monitor sampler"
```

---

### Task 4: Add Request Filter And Debug API Routes

**Files:**
- Modify: `backend/monitor/schema.py`
- Modify: `backend/monitor/main.py`
- Modify: `backend/monitor/tests/test_main.py`

- [ ] **Step 1: Write failing route tests**

Append to `backend/monitor/tests/test_main.py`:

```python
@pytest.mark.asyncio
async def test_metrics_requests_route_filters_noise():
    from monitor import bg
    from monitor.main import app

    bg.NGINX_ACCESS_RECORDS.clear()
    bg.NGINX_ACCESS_RECORDS.extend([
        {"ts_ms": 1000, "method": "GET", "path": "/api/v1/comics", "status": 200, "rt_ms": 10, "traffic_class": "app", "classification_reason": "api_path"},
        {"ts_ms": 2000, "method": "POST", "path": "/cgi-bin/.%2e/bin/sh", "status": 404, "rt_ms": 30, "traffic_class": "noise", "classification_reason": "cgi_traversal_probe"},
    ])

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        resp = await c.get("/metrics/requests?range=6h&traffic=noise")

    assert resp.status_code == 200
    body = resp.json()
    assert body["status_codes"]["4xx"] == 1
    assert body["slowest"][0]["path"] == "/cgi-bin/.%2e/bin/sh"


@pytest.mark.asyncio
async def test_metrics_requests_debug_returns_reason_counts():
    from monitor import bg
    from monitor.main import app

    bg.NGINX_ACCESS_RECORDS.clear()
    bg.NGINX_ACCESS_RECORDS.extend([
        {"ts_ms": 1000, "method": "GET", "path": "/api/v1/comics", "status": 200, "rt_ms": 10, "traffic_class": "app", "classification_reason": "api_path"},
        {"ts_ms": 2000, "method": "POST", "path": "/cgi-bin/.%2e/bin/sh", "status": 404, "rt_ms": 30, "traffic_class": "noise", "classification_reason": "cgi_traversal_probe"},
    ])
    bg.NGINX_SAMPLER_META.update({"elapsed_ms": 9, "parse_failures": 0})

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        resp = await c.get("/metrics/requests/debug?range=6h&limit=5")

    assert resp.status_code == 200
    body = resp.json()
    assert body["traffic_counts"]["app"] == 1
    assert body["traffic_counts"]["noise"] == 1
    assert body["reason_counts"]["cgi_traversal_probe"] == 1
    assert body["sampler"]["elapsed_ms"] == 9
```

- [ ] **Step 2: Run route tests and verify failure**

Run:

```bash
cd backend
PYTHONPATH=. pytest monitor/tests/test_main.py::test_metrics_requests_route_filters_noise monitor/tests/test_main.py::test_metrics_requests_debug_returns_reason_counts -v
```

Expected: both fail with HTTP 404.

- [ ] **Step 3: Add schema models**

In `backend/monitor/schema.py`, add:

```python
class RequestFiltersEcho(BaseModel):
    traffic: Literal["app", "static", "monitor", "noise", "unknown"]
    method: str
    status: Literal["all", "2xx", "3xx", "4xx", "5xx"]
    q: str
    rank: Literal["p95", "count", "error_rate"]


class RequestSample(BaseModel):
    method: str
    path: str
    status: int
    rt_ms: int
    traffic_class: str
    reason: str


class RequestDebugResponse(BaseModel):
    filters: RequestFiltersEcho
    traffic_counts: dict[str, int]
    reason_counts: dict[str, int]
    parse_failures: int
    included_count: int
    excluded_count: int
    included_samples: list[RequestSample]
    excluded_samples: list[RequestSample]
    sampler: dict
```

- [ ] **Step 4: Add routes**

In `backend/monitor/main.py`, import:

```python
from monitor.requests_metrics import build_request_debug
from monitor.traffic import RequestFilters
```

Add routes after `/metrics`:

```python
@app.get("/metrics/requests")
async def metrics_requests(
    range: str = Query("6h", pattern="^(1h|6h|24h|7d|30d)$"),
    traffic: str = Query("app", pattern="^(app|static|monitor|noise|unknown)$"),
    method: str = Query("all"),
    status: str = Query("all", pattern="^(all|2xx|3xx|4xx|5xx)$"),
    q: str = Query(""),
    rank: str = Query("p95", pattern="^(p95|count|error_rate)$"),
) -> JSONResponse:
    filters = RequestFilters(traffic=traffic, method=method, status=status, q=q, rank=rank)
    block = await requests_coll.collect(range, filters)
    return JSONResponse(block.model_dump(mode="json", by_alias=True))


@app.get("/metrics/requests/debug")
async def metrics_requests_debug(
    range: str = Query("6h", pattern="^(1h|6h|24h|7d|30d)$"),
    traffic: str = Query("app", pattern="^(app|static|monitor|noise|unknown)$"),
    method: str = Query("all"),
    status: str = Query("all", pattern="^(all|2xx|3xx|4xx|5xx)$"),
    q: str = Query(""),
    rank: str = Query("p95", pattern="^(p95|count|error_rate)$"),
    limit: int = Query(25, ge=1, le=100),
) -> JSONResponse:
    from monitor.schema import RequestDebugResponse

    filters = RequestFilters(traffic=traffic, method=method, status=status, q=q, rank=rank)
    debug = build_request_debug(
        list(bg.NGINX_ACCESS_RECORDS),
        filters,
        limit,
        sampler_meta=dict(bg.NGINX_SAMPLER_META),
    )
    validated = RequestDebugResponse.model_validate(debug)
    return JSONResponse(validated.model_dump(mode="json"))
```

- [ ] **Step 5: Run route tests**

Run:

```bash
cd backend
PYTHONPATH=. pytest monitor/tests/test_main.py::test_metrics_requests_route_filters_noise monitor/tests/test_main.py::test_metrics_requests_debug_returns_reason_counts -v
```

Expected: both pass.

- [ ] **Step 6: Run monitor backend tests touched by request changes**

Run:

```bash
cd backend
PYTHONPATH=. pytest monitor/tests/test_main.py monitor/tests/collectors/test_requests.py monitor/tests/test_traffic_classification.py monitor/tests/test_requests_metrics.py -v
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add backend/monitor/schema.py backend/monitor/main.py backend/monitor/tests/test_main.py
git commit -m "[backend] add monitor request filter debug endpoints"
```

---

### Task 5: Add Requests Panel Filters And Diagnostics

**Files:**
- Modify: `backend/monitor/static/index.html`
- Test: `backend/monitor/tests/test_main.py`

- [ ] **Step 1: Add HTML smoke test for new markers**

Extend `test_index_html_ast78_polish_markers` in `backend/monitor/tests/test_main.py` by adding these required markers:

```python
        "request-traffic",
        "request-method",
        "request-status",
        "request-rank",
        "__diagRequests",
        "monitor_debug",
```

Run:

```bash
cd backend
PYTHONPATH=. pytest monitor/tests/test_main.py::test_index_html_ast78_polish_markers -v
```

Expected: fails because the markers are not in the HTML.

- [ ] **Step 2: Add state split**

In `backend/monitor/static/index.html`, replace the existing `STATE` initializer with:

```js
const STATE = {
  range: '6h',
  logFilter: '',
  svcFilter: 'all',
  data: null,
  filters: {
    requests: {
      traffic: 'app',
      method: 'all',
      status: 'all',
      q: '',
      rank: 'p95',
      source: '/metrics',
      lastUrl: '',
      lastError: '',
    },
    services: {},
    logs: {},
    arq: {},
    storage: {},
    backups: {},
    deploys: {},
    audit: {},
    sql: {},
  },
  ui: {
    serviceCards: {},
    scroll: {},
    focused: null,
  },
};
```

Add debug helpers near the shared helper functions:

```js
function monitorDebugEnabled(){
  try { return localStorage.getItem('monitor_debug') === '1'; } catch(_) { return false; }
}
function debugLog(){
  if (!monitorDebugEnabled()) return;
  console.debug.apply(console, ['[monitor]'].concat(Array.from(arguments)));
}
```

- [ ] **Step 3: Add Requests controls markup**

In the Requests section header/card controls area near `id="req-window"` and `id="statusBars"`, add:

```html
<div id="request-controls" class="flex flex-wrap items-center gap-2 mb-4">
  <select id="request-traffic" class="sel" title="traffic class">
    <option value="app" selected>App</option>
    <option value="static">Static</option>
    <option value="monitor">Monitor</option>
    <option value="unknown">Unknown</option>
    <option value="noise">Noise</option>
  </select>
  <select id="request-method" class="sel" title="HTTP method">
    <option value="all" selected>All methods</option>
    <option value="GET">GET</option>
    <option value="POST">POST</option>
    <option value="DELETE">DELETE</option>
    <option value="PUT">PUT</option>
    <option value="PATCH">PATCH</option>
  </select>
  <select id="request-status" class="sel" title="status band">
    <option value="all" selected>All status</option>
    <option value="2xx">2xx</option>
    <option value="3xx">3xx</option>
    <option value="4xx">4xx</option>
    <option value="5xx">5xx</option>
  </select>
  <select id="request-rank" class="sel" title="rank endpoints by">
    <option value="p95" selected>p95</option>
    <option value="count">Count</option>
    <option value="error_rate">Error rate</option>
  </select>
  <input id="request-path" class="search" style="max-width:220px;padding-left:12px" placeholder="path filter" />
  <button id="request-debug-copy" class="ibtn" title="copy request diagnostics">?</button>
</div>
```

- [ ] **Step 4: Add request filter fetch functions**

Add before `renderRequests()`:

```js
function requestFilterParams(){
  const f = STATE.filters.requests;
  return new URLSearchParams({
    range: STATE.range,
    traffic: f.traffic,
    method: f.method,
    status: f.status,
    q: f.q,
    rank: f.rank,
  });
}

async function refreshRequestsOnly(){
  const f = STATE.filters.requests;
  const url = '/metrics/requests?' + requestFilterParams().toString();
  f.lastUrl = url;
  f.lastError = '';
  debugLog('requests refresh start', url);
  try {
    const resp = await fetch(url, {credentials: 'include'});
    if (!resp.ok) throw new Error('request metrics failed: ' + resp.status);
    STATE.data.requests = normalizeRequestBlock(await resp.json());
    f.source = '/metrics/requests';
    renderRequests();
    debugLog('requests refresh ok', STATE.data.requests.total);
  } catch(e) {
    f.lastError = e.message;
    debugLog('requests refresh failed', e.message);
    toast('request metrics failed');
  }
}

function normalizeRequestBlock(r){
  r.series_rps = (r.series_rps || []).map(p => Array.isArray(p) ? p[1] : p);
  r.series_p95_ms = (r.series_p95_ms || []).map(p => Array.isArray(p) ? p[1] : p);
  if(r.series_rps.length === 0) r.series_rps = [0];
  if(r.series_p95_ms.length === 0) r.series_p95_ms = [0];
  r.total = Object.values(r.status_codes || {}).reduce((a,b) => a + (b||0), 0);
  return r;
}
```

Change `normalizeMetrics(d)` to call `normalizeRequestBlock(r)` instead of duplicating request normalization.

- [ ] **Step 5: Wire request controls**

Add near existing event listeners:

```js
function syncRequestControlsFromState(){
  const f = STATE.filters.requests;
  const set = (id, val) => { const el = document.getElementById(id); if (el) el.value = val; };
  set('request-traffic', f.traffic);
  set('request-method', f.method);
  set('request-status', f.status);
  set('request-rank', f.rank);
  const path = document.getElementById('request-path');
  if (path) path.value = f.q;
}

function installRequestControls(){
  syncRequestControlsFromState();
  const bindSelect = (id, key) => {
    const el = document.getElementById(id);
    if (!el) return;
    el.addEventListener('change', () => {
      STATE.filters.requests[key] = el.value;
      refreshRequestsOnly();
    });
  };
  bindSelect('request-traffic', 'traffic');
  bindSelect('request-method', 'method');
  bindSelect('request-status', 'status');
  bindSelect('request-rank', 'rank');
  const path = document.getElementById('request-path');
  if (path) {
    path.addEventListener('input', () => {
      STATE.filters.requests.q = path.value;
      clearTimeout(path._t);
      path._t = setTimeout(refreshRequestsOnly, 250);
    });
  }
  const dbg = document.getElementById('request-debug-copy');
  if (dbg) dbg.addEventListener('click', copyRequestDiagnostics);
}
```

Call `installRequestControls()` in the boot section after initial DOM setup.

- [ ] **Step 6: Add request diagnostics helper**

Add after `window.__diag = async function(){...}`:

```js
window.__diagRequests = async function(){
  const r = (STATE.data && STATE.data.requests) || {};
  const f = STATE.filters.requests;
  const lines = [];
  lines.push('REQUESTS DIAGNOSTIC');
  lines.push('generated_at: ' + ((STATE.data && STATE.data.generated_at) || '—'));
  lines.push('build: ' + ((STATE.data && STATE.data.build) || '—'));
  lines.push('range: ' + STATE.range);
  lines.push('source: ' + f.source);
  lines.push('last_url: ' + (f.lastUrl || '—'));
  lines.push('last_error: ' + (f.lastError || '—'));
  lines.push('filters: ' + JSON.stringify({traffic:f.traffic, method:f.method, status:f.status, q:f.q, rank:f.rank}));
  lines.push('total: ' + (r.total || 0));
  lines.push('status: ' + JSON.stringify(r.status_codes || {}));
  lines.push('rows: ' + ((r.slowest || []).length));
  for (const row of (r.slowest || []).slice(0, 10)) {
    lines.push('  ' + row.method + ' ' + row.path + ' p95=' + row.p95_ms + ' count=' + row.count);
  }
  const text = lines.join('\n');
  console.log(text);
  try { await navigator.clipboard.writeText(text); toast('request diagnostics copied'); } catch(_) {}
  return text;
};

function copyRequestDiagnostics(){
  window.__diagRequests();
}
```

- [ ] **Step 7: Run HTML marker test**

Run:

```bash
cd backend
PYTHONPATH=. pytest monitor/tests/test_main.py::test_index_html_ast78_polish_markers -v
```

Expected: passes.

- [ ] **Step 8: Commit**

```bash
git add backend/monitor/static/index.html backend/monitor/tests/test_main.py
git commit -m "[backend] add request panel filters and diagnostics"
```

---

### Task 6: Preserve Service Card Face State Through Refresh

**Files:**
- Modify: `backend/monitor/static/index.html`
- Test: `backend/monitor/tests/test_main.py`

- [ ] **Step 1: Add HTML marker test for state helpers**

Extend `test_index_html_ast78_polish_markers` required markers with:

```python
        "rememberServiceFace",
        "restoreServiceFaces",
```

Run:

```bash
cd backend
PYTHONPATH=. pytest monitor/tests/test_main.py::test_index_html_ast78_polish_markers -v
```

Expected: fails because helpers are missing.

- [ ] **Step 2: Add service face helpers**

Add before `renderServices()`:

```js
function serviceUi(name){
  STATE.ui.serviceCards[name] = STATE.ui.serviceCards[name] || { face: 'front', metric: 'cpu_mem' };
  return STATE.ui.serviceCards[name];
}

function rememberServiceFace(name, face){
  serviceUi(name).face = face;
}

function restoreServiceFaces(){
  document.querySelectorAll('.svc-flip[data-service-card]').forEach(wrap => {
    const name = wrap.getAttribute('data-service-card');
    const ui = serviceUi(name);
    wrap.classList.toggle('flipped', ui.face === 'back');
  });
}
```

In the service card template, change:

```html
<div class="svc-flip" data-service-card="${name}">
```

to:

```html
<div class="svc-flip ${serviceUi(name).face === 'back' ? 'flipped' : ''}" data-service-card="${name}">
```

In the terminal button click handler, replace direct set usage with:

```js
      rememberServiceFace(name, 'back');
      wrap.classList.add('flipped');
```

In the close handler, replace deletion logic with:

```js
      rememberServiceFace(name, 'front');
      wrap.classList.remove('flipped');
```

At the end of `renderServices()`, after binding click handlers, call:

```js
  restoreServiceFaces();
```

- [ ] **Step 3: Add refresh lifecycle debug logs**

Modify `refreshAll()`:

```js
async function refreshAll(){
  debugLog('refreshAll start', {range: STATE.range});
  try {
    STATE.data = await genData(STATE.range);
    STATE.filters.requests.source = '/metrics';
    STATE.filters.requests.lastError = '';
  } catch(e){
    console.error('refreshAll failed', e);
    STATE.data = emptyData();
    STATE.filters.requests.lastError = e.message;
    if (!STATE._warnedUnreachable){
      toast('metrics unreachable');
      STATE._warnedUnreachable = true;
    }
  }
  debugLog('renderAll start');
  renderAll();
  restoreServiceFaces();
  debugLog('refreshAll done');
}
```

- [ ] **Step 4: Run marker test**

Run:

```bash
cd backend
PYTHONPATH=. pytest monitor/tests/test_main.py::test_index_html_ast78_polish_markers -v
```

Expected: passes.

- [ ] **Step 5: Manual browser verification**

Run a simple static server:

```bash
cd backend/monitor/static
python3 -m http.server 8765
```

Open `http://127.0.0.1:8765/?preview=1`, flip a service card to the terminal side, run this in the browser console:

```js
refreshAll()
```

Expected: the card remains on the terminal side after refresh.

- [ ] **Step 6: Commit**

```bash
git add backend/monitor/static/index.html backend/monitor/tests/test_main.py
git commit -m "[backend] preserve monitor service card state on refresh"
```

---

### Task 7: Add Panel-Local Controls For Remaining Dashboard Sections

**Files:**
- Modify: `backend/monitor/static/index.html`
- Modify: `backend/monitor/static/controls.js`
- Test: `backend/monitor/tests/test_main.py`

- [ ] **Step 1: Add marker test for remaining controls**

Extend `test_index_html_ast78_polish_markers` required markers with:

```python
        "logs-order",
        "arq-state-filter",
        "storage-series-filter",
        "backup-status-filter",
        "deploy-status-filter",
        "audit-action-filter",
        "sql-result-filter",
```

Run:

```bash
cd backend
PYTHONPATH=. pytest monitor/tests/test_main.py::test_index_html_ast78_polish_markers -v
```

Expected: fails because controls are missing.

- [ ] **Step 2: Add control markup**

Add compact controls to the matching existing panel markup:

```html
<select id="logs-order" class="sel" title="log order">
  <option value="newest" selected>Newest</option>
  <option value="oldest">Oldest</option>
</select>

<select id="arq-state-filter" class="sel" title="ARQ state">
  <option value="all" selected>All jobs</option>
  <option value="active">Active</option>
  <option value="completed">Completed</option>
  <option value="failed">Failed</option>
</select>

<select id="storage-series-filter" class="sel" title="storage series">
  <option value="all" selected>All storage</option>
  <option value="postgres">Postgres</option>
  <option value="media">Media</option>
  <option value="block">Block free</option>
  <option value="object">Object</option>
</select>

<select id="backup-status-filter" class="sel" title="backup status">
  <option value="all" selected>All backups</option>
  <option value="ok">OK</option>
  <option value="stale">Stale</option>
  <option value="failed">Failed</option>
</select>

<select id="deploy-status-filter" class="sel" title="deploy status">
  <option value="all" selected>All deploys</option>
  <option value="healthy">Healthy</option>
  <option value="failed">Failed</option>
</select>

<input id="audit-action-filter" class="search" style="max-width:220px;padding-left:12px" placeholder="audit action" />

<input id="sql-result-filter" class="search" style="max-width:220px;padding-left:12px" placeholder="filter results" />
```

Place each control in the relevant card/header, not in one global toolbar.

- [ ] **Step 3: Initialize filter defaults**

Extend `STATE.filters` defaults:

```js
logs: { order: 'newest' },
arq: { state: 'all' },
storage: { series: 'all' },
backups: { status: 'all' },
deploys: { status: 'all' },
audit: { action: '' },
sql: { resultFilter: '' },
```

- [ ] **Step 4: Apply local filters in renderers**

Modify `renderLogs()` before slicing:

```js
  let ordered = STATE.data.logs.slice();
  if ((STATE.filters.logs || {}).order === 'oldest') ordered = ordered.reverse();
  const visible = ordered.filter(l => {
```

Modify `renderArq()` to hide tables that do not match `STATE.filters.arq.state`:

```js
  const arqState = (STATE.filters.arq || {}).state || 'all';
  document.getElementById('active-jobs').closest('.card, .elevated')?.classList.toggle('hidden', arqState !== 'all' && arqState !== 'active');
```

Use the same pattern for completed and failed table containers by selecting their nearest card/table wrapper and toggling `hidden`.

Modify `renderStorage()` to filter `cells`:

```js
  const series = (STATE.filters.storage || {}).series || 'all';
  const filteredCells = series === 'all' ? cells : cells.filter(c => {
    const key = c.label.toLowerCase();
    if (series === 'postgres') return key.includes('postgres');
    if (series === 'media') return key.includes('media');
    if (series === 'block') return key.includes('block');
    if (series === 'object') return key.includes('object');
    return true;
  });
  document.getElementById('storage-grid').innerHTML = filteredCells.map(c => `
```

Modify `renderBackups()`:

```js
  const statusFilter = (STATE.filters.backups || {}).status || 'all';
  const runs = statusFilter === 'all'
    ? b.recent_runs
    : b.recent_runs.filter(r => r.status === statusFilter);
  document.getElementById('bk-rows').innerHTML = runs.map(r=>{
```

Modify `renderDeploys()` in `controls.js`:

```js
    const statusFilter = (window.STATE && window.STATE.filters && window.STATE.filters.deploys && window.STATE.filters.deploys.status) || 'all';
    const rows = statusFilter === 'all'
      ? deploys.recent
      : deploys.recent.filter(d => statusFilter === 'healthy' ? d.healthy : !d.healthy);
    if (!rows.length) {
      tbody.innerHTML = '<tr><td colspan="5" class="text-muted text-sm mono">No deploys match filter.</td></tr>';
      return;
    }
    for (const d of rows) {
```

Modify `loadAudit()` in `controls.js`:

```js
      const actionFilter = ((window.STATE && window.STATE.filters && window.STATE.filters.audit && window.STATE.filters.audit.action) || '').toLowerCase();
      const entries = data.entries.reverse().filter(e => !actionFilter || String(e.action || '').toLowerCase().includes(actionFilter));
      if (!entries.length) {
        tbody.innerHTML = '<tr><td colspan="5" class="text-muted text-sm mono">No audit entries match filter.</td></tr>';
        return;
      }
      for (const e of entries) {
```

Modify `renderSQLTable(container, data)` in `controls.js`:

```js
    const filter = ((window.STATE && window.STATE.filters && window.STATE.filters.sql && window.STATE.filters.sql.resultFilter) || '').toLowerCase();
    const rows = filter
      ? data.rows.filter(row => row.some(cell => String(cell === null ? 'NULL' : cell).toLowerCase().includes(filter)))
      : data.rows;
    for (const row of rows) {
```

- [ ] **Step 5: Wire remaining control events**

Add a DOMContentLoaded helper in `index.html` or `controls.js`:

```js
function installPanelControls(){
  const bindSelect = (id, section, key, render) => {
    const el = document.getElementById(id);
    if (!el) return;
    el.addEventListener('change', () => {
      STATE.filters[section][key] = el.value;
      render();
    });
  };
  bindSelect('logs-order', 'logs', 'order', renderLogs);
  bindSelect('arq-state-filter', 'arq', 'state', renderArq);
  bindSelect('storage-series-filter', 'storage', 'series', renderStorage);
  bindSelect('backup-status-filter', 'backups', 'status', renderBackups);
  bindSelect('deploy-status-filter', 'deploys', 'status', () => { if (window.renderDeploys) window.renderDeploys(); });
  const audit = document.getElementById('audit-action-filter');
  if (audit) audit.addEventListener('input', () => {
    STATE.filters.audit.action = audit.value;
    if (window.loadAudit) window.loadAudit();
  });
  const sql = document.getElementById('sql-result-filter');
  if (sql) sql.addEventListener('input', () => {
    STATE.filters.sql.resultFilter = sql.value;
    const last = STATE.filters.sql.lastResult;
    const body = document.getElementById('sql-results-body');
    if (last && body && window.renderSQLTable) window.renderSQLTable(body, last);
  });
}
```

Expose `renderDeploys`, `loadAudit`, and `renderSQLTable` from `controls.js`:

```js
  window.renderDeploys = renderDeploys;
  window.loadAudit = loadAudit;
  window.renderSQLTable = renderSQLTable;
```

Store last SQL result in `runSQL()` after a successful query:

```js
      if (window.STATE && window.STATE.filters && window.STATE.filters.sql) {
        window.STATE.filters.sql.lastResult = data;
      }
```

Call `installPanelControls()` during boot after initial render.

- [ ] **Step 6: Run marker test**

Run:

```bash
cd backend
PYTHONPATH=. pytest monitor/tests/test_main.py::test_index_html_ast78_polish_markers -v
```

Expected: passes.

- [ ] **Step 7: Commit**

```bash
git add backend/monitor/static/index.html backend/monitor/static/controls.js backend/monitor/tests/test_main.py
git commit -m "[backend] add local monitor panel controls"
```

---

### Task 8: Full Verification And Code Review

**Files:**
- Modify only files required by fixes found in this task.

- [ ] **Step 1: Run backend monitor tests**

Run:

```bash
cd backend
PYTHONPATH=. pytest monitor/tests -v
```

Expected: all monitor tests pass.

- [ ] **Step 2: Run targeted collector tests**

Run:

```bash
cd backend
PYTHONPATH=. pytest monitor/tests/collectors -v
```

Expected: all collector tests pass.

- [ ] **Step 3: Run static preview**

Run:

```bash
cd backend/monitor/static
python3 -m http.server 8765
```

Open `http://127.0.0.1:8765/?preview=1`.

Manual checks:

- Requests traffic dropdown defaults to `App`.
- Selecting `Noise` does not crash the panel when preview data has no noise.
- Flipping a service card and running `refreshAll()` leaves the card flipped.
- `localStorage.setItem('monitor_debug','1')` enables debug console logs.
- `__diagRequests()` prints and copies the diagnostic bundle.

- [ ] **Step 4: Review diff in code-review stance**

Run:

```bash
git diff --stat HEAD~7..HEAD
git diff HEAD~7..HEAD -- backend/monitor
```

Review for:

- Request totals, charts, status bars, and table all use one filtered record set.
- `noise` is hidden by default.
- Debug samples are redacted and capped.
- Frontend refresh does not clear active UI state.
- No iOS/Xcode files are staged.

- [ ] **Step 5: Fix any Critical or Important review findings**

For each finding, make the smallest code change, rerun the relevant test command from the task that introduced the bug, and commit:

```bash
git add <changed-files>
git commit -m "[backend] fix monitor dashboard formalization review issue"
```

- [ ] **Step 6: Final status check**

Run:

```bash
git status --short --branch
```

Expected:

- New monitor commits are present.
- Pre-existing user changes in iOS/Xcode may still be present.
- No accidental staged files.

---

## Self-Review Checklist

- Spec coverage: Tasks 1-4 cover request meaning, app-default Requests, hidden noise, debug logs, debug endpoint, and testable backend contract. Tasks 5-7 cover panel-local filters, diagnostics, refresh state, and remaining controls. Task 8 covers verification and code-review stance.
- Red-flag scan: no `TBD`, no generic "add tests" step, and no task relies on unnamed files.
- Type consistency: `RequestFilters`, `TrafficClassification`, `traffic_class`, `classification_reason`, `/metrics/requests`, and `/metrics/requests/debug` are introduced before use.
- Scope control: terminal exec remains outside this plan; terminal face state and controls are prepared without implementing the real exec channel.
