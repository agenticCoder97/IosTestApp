# OCI Monitor Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a dark-mode single-page operational dashboard for the Astral OCI stack (6-service docker-compose), served by a new `astral_monitor` container behind nginx Basic Auth, with a `/metrics` endpoint populated by 8 collectors wired to docker, redis, postgres, OCI SDK, nginx logs, and the LE cert file.

**Architecture:** New isolated FastAPI service (`python:3.11-slim` + thin deps). Three long-lived bg tasks (`docker_sampler`, `log_tailer`, `nginx_access_sampler`) feed in-proc caches. 8 collectors read from those caches + Redis for slow/expensive values (OCI Budget API, `du`, `pg_database_size`, Object Storage list). Every collector wrapped in `safe()` so one failure becomes a degraded marker, never a 500. Handoff `Dashboard.html` served verbatim with three surgical JS edits to replace `genData()` with `fetch('/metrics')`.

**Tech Stack:** Python 3.11, FastAPI + uvicorn, pydantic v2, asyncpg, redis-py (async), docker-py, oci SDK (instance principal signer), cryptography, pytest + pytest-asyncio + fakeredis.

**Design spec:** [docs/superpowers/specs/2026-04-21-oci-monitor-dashboard-design.md](../specs/2026-04-21-oci-monitor-dashboard-design.md)

**Handoff:** `/Users/nicknetraganti/Downloads/design_handoff_oci_monitor/{Dashboard.html,README.md}`

---

## Conventions

- **Branch name**: `feature/ast-NN-oci-monitor-dashboard` (fill `NN` with the Linear issue id from Task 0).
- **Commit prefix**: `[backend] AST-NN` on every commit.
- **PR target**: `development` (never `main` / `production` / `release-1`).
- **Co-author tag**: every commit ends with `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.
- **Run tests**: `cd backend && python -m pytest monitor/tests/ -v` (uses the existing `backend/pytest.ini`; asyncio mode is `auto`).

---

## File Structure

**Create**

```
backend/
├── Dockerfile.monitor
├── monitor/
│   ├── __init__.py
│   ├── main.py
│   ├── schema.py
│   ├── cache.py
│   ├── bg.py
│   ├── collectors/
│   │   ├── __init__.py
│   │   ├── cost.py
│   │   ├── services.py
│   │   ├── requests_.py
│   │   ├── arq.py
│   │   ├── storage.py
│   │   ├── backups.py
│   │   ├── cert.py
│   │   └── logs.py
│   ├── static/
│   │   └── index.html
│   └── tests/
│       ├── __init__.py
│       ├── conftest.py
│       ├── test_schema.py
│       ├── test_cache.py
│       ├── test_safe.py
│       ├── test_docker_sampler.py
│       ├── test_bg_supervise.py
│       ├── test_metrics_endpoint.py
│       ├── test_main.py
│       └── collectors/
│           ├── __init__.py
│           ├── _fixtures/fullchain.pem
│           ├── test_cost.py
│           ├── test_services.py
│           ├── test_requests.py
│           ├── test_arq.py
│           ├── test_storage.py
│           ├── test_backups.py
│           ├── test_cert.py
│           └── test_logs.py
```

**Modify**

- `backend/docker-compose.yml` — add `astral_monitor` service; nginx `depends_on` gains `astral_monitor`; nginx volumes gain `./nginx/htpasswd:/etc/nginx/htpasswd:ro` + `nginx_access_logs:/var/log/nginx`; add `nginx_access_logs:` named volume.
- `backend/nginx/nginx.conf` — add `log_format` + `access_log` directives; add `/monitor/` + `/metrics` location blocks with `auth_basic`.
- `backend/requirements-test.txt` — add `fakeredis==2.26.*` + `cryptography==43.*` (cert collector tests import it; `oci` + `docker` stay lazy-imported inside collectors so no dep needed at test time).
- `CHANGELOG.md` — add AST-NN entry under today's date (final task).
- `.gitignore` — add `backend/nginx/htpasswd`.

**Create on A1 host (not in repo — managed via runbook in Task 22)**

- `backend/nginx/htpasswd` (gitignored).

---

## Phase 0 — Linear + branch

### Task 0: File Linear issue and cut feature branch

**Files:** none in this task.

- [ ] **Step 1: File the Linear issue**

Using the Linear MCP tool (or web UI), create a new issue in the **Astral** team (key `AST`):

- **Title**: `[backend] OCI monitor dashboard (/monitor + /metrics)`
- **Description**: link to spec at `docs/superpowers/specs/2026-04-21-oci-monitor-dashboard-design.md` and this plan.
- **Project**: Astral.

Record the returned ID (e.g. `AST-57`). Substitute it for `NN` everywhere below.

- [ ] **Step 2: Cut the branch**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git checkout development
git pull --ff-only origin development
git checkout -b feature/ast-NN-oci-monitor-dashboard
```

Expected: `Switched to a new branch 'feature/ast-NN-oci-monitor-dashboard'`.

- [ ] **Step 3: Verify clean working tree**

```bash
git status
```

Expected: `nothing to commit, working tree clean`.

---

## Phase 1 — Foundation (deployable skeleton)

At end of phase: `docker compose up -d astral_monitor` brings up a container that serves `GET /healthz` → `200 {"status":"ok"}` and `GET /` → the raw handoff HTML. Nginx routes `/monitor/` to it.

### Task 1: Directory skeleton + package markers

**Files:**
- Create: `backend/monitor/__init__.py`
- Create: `backend/monitor/collectors/__init__.py`
- Create: `backend/monitor/tests/__init__.py`
- Create: `backend/monitor/tests/collectors/__init__.py`
- Create: `backend/monitor/static/` (directory)

- [ ] **Step 1: Create empty package markers**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/backend"
mkdir -p monitor/collectors monitor/static monitor/tests/collectors/_fixtures
touch monitor/__init__.py monitor/collectors/__init__.py monitor/tests/__init__.py monitor/tests/collectors/__init__.py
```

Verify:
```bash
find monitor -type f | sort
```

- [ ] **Step 2: Commit**

```bash
git add backend/monitor
git commit -m "[backend] AST-NN scaffold monitor package layout

Empty __init__.py markers + directory tree for the new astral_monitor
service. No code yet.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Copy handoff HTML verbatim (pre-JS-patch)

**Files:**
- Create: `backend/monitor/static/index.html` — byte-for-byte copy of handoff.

- [ ] **Step 1: Copy the file**

```bash
cp "/Users/nicknetraganti/Downloads/design_handoff_oci_monitor/Dashboard.html" \
   "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/backend/monitor/static/index.html"
wc -l backend/monitor/static/index.html
```

Expected: ~1793 lines.

- [ ] **Step 2: Commit (verbatim — JS patches land in Phase 7)**

```bash
git add backend/monitor/static/index.html
git commit -m "[backend] AST-NN monitor: import handoff Dashboard.html verbatim

Pixel-locked design from design_handoff_oci_monitor/Dashboard.html,
unmodified. genData() still generates mock data — Phase 7 swaps it
for fetch('/metrics').

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Skeleton FastAPI app — `/healthz` + static index

**Files:**
- Create: `backend/monitor/main.py`
- Create: `backend/monitor/tests/conftest.py`
- Create: `backend/monitor/tests/test_main.py`

- [ ] **Step 1: Write the failing test**

Create `backend/monitor/tests/conftest.py`:

```python
"""Test harness for the monitor service."""
import os

os.environ.setdefault("REDIS_URL", "redis://localhost:6379/0")
os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://test:test@localhost:5432/test")
os.environ.setdefault("PROD", "false")
```

Create `backend/monitor/tests/test_main.py`:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd backend && python -m pytest monitor/tests/test_main.py -v
```

Expected: `ModuleNotFoundError: No module named 'monitor.main'`.

- [ ] **Step 3: Write the minimal implementation**

Create `backend/monitor/main.py`:

```python
"""Astral OCI monitor — FastAPI app entrypoint."""
from __future__ import annotations

import logging
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
logger = logging.getLogger("monitor")

_STATIC_DIR = Path(__file__).parent / "static"

app = FastAPI(title="astral-monitor", docs_url=None, redoc_url=None)
app.mount("/static", StaticFiles(directory=_STATIC_DIR), name="static")


@app.get("/healthz")
async def healthz() -> JSONResponse:
    return JSONResponse({"status": "ok"})


@app.get("/")
async def index() -> FileResponse:
    return FileResponse(_STATIC_DIR / "index.html", media_type="text/html")
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd backend && python -m pytest monitor/tests/test_main.py -v
```

Expected: both tests `PASSED`.

- [ ] **Step 5: Commit**

```bash
git add backend/monitor/__init__.py backend/monitor/main.py backend/monitor/tests/conftest.py backend/monitor/tests/test_main.py
git commit -m "[backend] AST-NN monitor: skeleton FastAPI app with /healthz

Minimal entrypoint. GET /healthz for compose healthcheck, GET / serves
the handoff HTML, GET /static/* serves assets.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `Dockerfile.monitor`

**Files:**
- Create: `backend/Dockerfile.monitor`

- [ ] **Step 1: Write the Dockerfile**

Create `backend/Dockerfile.monitor`:

```dockerfile
# Astral OCI monitor — lightweight sidecar for /monitor + /metrics.
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN pip install \
    "fastapi==0.115.*" \
    "uvicorn[standard]==0.32.*" \
    "pydantic==2.9.*" \
    "asyncpg==0.30.*" \
    "redis==5.2.*" \
    "docker==7.1.*" \
    "oci==2.134.*" \
    "cryptography==43.*" \
    "python-dateutil==2.9.*" \
    "httpx==0.27.*"

RUN useradd -r -u 1001 -m monitor
WORKDIR /app
COPY --chown=monitor:monitor monitor /app/monitor
USER monitor

EXPOSE 8001

CMD ["uvicorn", "monitor.main:app", "--host", "0.0.0.0", "--port", "8001", "--log-level", "info"]
```

- [ ] **Step 2: Build the image locally**

```bash
cd backend
docker build -f Dockerfile.monitor -t astral-monitor:dev .
```

Expected: build succeeds, ~180 MB.

- [ ] **Step 3: Smoke-run the container**

```bash
docker run --rm -d -p 8001:8001 --name monitor-smoke astral-monitor:dev
sleep 3
curl -s http://127.0.0.1:8001/healthz
docker stop monitor-smoke
```

Expected: `{"status":"ok"}`.

- [ ] **Step 4: Commit**

```bash
git add backend/Dockerfile.monitor
git commit -m "[backend] AST-NN monitor: Dockerfile.monitor

python:3.11-slim + fastapi/pydantic/asyncpg/redis/docker/oci/
cryptography pinned. Non-root user (uid 1001). ~180 MB image.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: docker-compose `astral_monitor` service

**Files:**
- Modify: `backend/docker-compose.yml`
- Modify: `.gitignore` (add `backend/nginx/htpasswd`)

- [ ] **Step 1: Add htpasswd to gitignore**

Append to `.gitignore`:

```
backend/nginx/htpasswd
```

- [ ] **Step 2: Insert `astral_monitor` service into `backend/docker-compose.yml`**

Add this block right after `arq_worker:` and before `nginx:`:

```yaml
  astral_monitor:
    build:
      context: .
      dockerfile: Dockerfile.monitor
    expose:
      - "8001"
    env_file:
      - .env.oci
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - letsencrypt:/etc/letsencrypt:ro
      - astral_media:/mnt/astral-media:ro
      - nginx_access_logs:/var/log/nginx:ro
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_started
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://127.0.0.1:8001/healthz"]
      interval: 30s
      timeout: 3s
      retries: 3
    restart: unless-stopped
    networks:
      - astral_net
```

In the `nginx:` block, replace `volumes:` with:

```yaml
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/htpasswd:/etc/nginx/htpasswd:ro
      - letsencrypt:/etc/letsencrypt:ro
      - astral_media:/mnt/astral-media:ro
      - nginx_access_logs:/var/log/nginx
```

Replace `nginx.depends_on` with:

```yaml
    depends_on:
      - fastapi
      - astral_monitor
```

In the top-level `volumes:` block, after `letsencrypt:`, add:

```yaml
  nginx_access_logs:
```

- [ ] **Step 3: Validate compose config**

```bash
cd backend
docker compose config > /tmp/compose-rendered.yml && echo "OK"
grep -c 'astral_monitor:' /tmp/compose-rendered.yml
grep -c 'nginx_access_logs' /tmp/compose-rendered.yml
```

Expected: `OK`, then `1`, then `3` (definition + 2 mounts).

- [ ] **Step 4: Create local htpasswd placeholder**

```bash
printf 'dev:$apr1$abcd1234$replacethis\n' > backend/nginx/htpasswd
```

(Placeholder — regenerated with real creds on the A1 in Task 22.)

- [ ] **Step 5: Commit**

```bash
git add backend/docker-compose.yml .gitignore
git commit -m "[backend] AST-NN compose: add astral_monitor service + nginx wiring

Adds astral_monitor with ro mounts for docker.sock, letsencrypt,
astral_media, nginx_access_logs. Nginx gains htpasswd mount + writes
access.log to new nginx_access_logs named volume (monitor reads).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Nginx config — `/monitor/`, `/metrics`, access log

**Files:**
- Modify: `backend/nginx/nginx.conf`

- [ ] **Step 1: Replace `backend/nginx/nginx.conf` with:**

```nginx
worker_processes auto;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;

    log_format astral '$remote_addr - $remote_user [$time_iso8601] '
                     '"$request" $status $body_bytes_sent '
                     'rt=$request_time urt="$upstream_response_time" '
                     '"$http_referer" "$http_user_agent"';

    access_log /var/log/nginx/access.log astral;

    server {
        listen 80;
        server_name _;
        return 301 https://$host$request_uri;
    }

    server {
        listen 443 ssl;
        server_name astral-reader.duckdns.org;

        ssl_certificate /etc/letsencrypt/live/astral-reader.duckdns.org/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/astral-reader.duckdns.org/privkey.pem;

        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;

        location /api/ {
            proxy_pass http://fastapi:8000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 300;
        }

        location /static/ {
            alias /mnt/astral-media/;
            expires 30d;
            add_header Cache-Control "public, immutable";
        }

        location = /monitor { return 301 /monitor/; }
        location /monitor/ {
            auth_basic "astral";
            auth_basic_user_file /etc/nginx/htpasswd;
            proxy_pass http://astral_monitor:8001/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_read_timeout 10;
        }

        location /metrics {
            auth_basic "astral";
            auth_basic_user_file /etc/nginx/htpasswd;
            proxy_pass http://astral_monitor:8001;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_read_timeout 10;
        }
    }
}
```

- [ ] **Step 2: Verify syntax**

```bash
cd backend
docker run --rm -v "$(pwd)/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" \
           -v "$(pwd)/nginx/htpasswd:/etc/nginx/htpasswd:ro" \
           nginx:1.25-alpine nginx -t
```

Expected: `configuration file /etc/nginx/nginx.conf test is successful`.

(Upstream resolution warnings at `-t` time are normal — nginx only resolves upstreams via docker DNS at runtime.)

- [ ] **Step 3: Commit**

```bash
git add backend/nginx/nginx.conf
git commit -m "[backend] AST-NN nginx: /monitor/ + /metrics location blocks + access_log

auth_basic-gated proxy to astral_monitor:8001 for both the HTML
dashboard (/monitor/) and JSON (/metrics). Custom log_format 'astral'
adds upstream response-time so nginx_access_sampler can compute p95.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 2 — Schema, cache, `safe()`

### Task 7: pydantic schema

**Files:**
- Create: `backend/monitor/schema.py`
- Create: `backend/monitor/tests/test_schema.py`

- [ ] **Step 1: Write the failing test**

Create `backend/monitor/tests/test_schema.py`:

```python
"""Golden parse test — the UI contract lives or dies on this."""
import pytest
from pydantic import ValidationError

from monitor.schema import MetricsResponse

GOLDEN = {
    "schema_version": "1.0.0",
    "generated_at": "2026-04-21T14:23:05Z",
    "build": "a7f3c9d",
    "tenancy_ocid": "ocid1.tenancy.oc1..aaaaaaaa3kf7sjr2",
    "region": "us-sanjose-1",
    "instance_ocid": "ocid1.instance.oc1.us-sanjose-1.an2g6l",
    "cost": {
        "currency": "USD", "month_to_date": 0.00, "forecast": 0.00,
        "budget": 1.00, "last_alert": None,
        "always_free": {
            "a1_ocpu":       {"used": 4,   "cap": 4,   "unit": "ocpu"},
            "a1_ram_gb":     {"used": 24,  "cap": 24,  "unit": "GB"},
            "block_vol_gb":  {"used": 152, "cap": 200, "unit": "GB"},
            "egress_tb":     {"used": 0.18,"cap": 10,  "unit": "TB"},
            "object_std_gb": {"used": 3.4, "cap": 20,  "unit": "GB"},
        },
    },
    "services": [{
        "name": "postgres", "image": "postgres:16-alpine",
        "container_id": "a7c3e9f0b2d1", "status": "up", "health": "healthy",
        "uptime_s": 864312, "cpu_pct": 2.4, "mem_mb": 412, "restarts": 0,
        "extra": {"pg_connections": 6, "pg_max_connections": 100},
        "spark_cpu": [0.8, 1.2, 1.1, 2.4, 3.0, 1.5, 0.9, 1.0] * 4,
    }],
    "requests": {
        "window": "6h",
        "series_rps": [[1713614400000, 1.2]],
        "series_p95_ms": [[1713614400000, 120]],
        "status_codes": {"2xx": 18421, "3xx": 320, "4xx": 87, "5xx": 3},
        "slowest": [{"method": "GET", "path": "/c/{s}/ch",
                     "p50_ms": 38, "p95_ms": 412, "p99_ms": 980, "count": 1284}],
    },
    "arq": {
        "queue_depth": 2, "in_flight": 1, "workers": 3,
        "completed_24h": 184, "failed_24h": 2,
        "active": [{"job_id": "a71f3c9d2b4e", "fn": "scrape_chapter",
                    "source": "ao3", "target": "ao3:1/ch3",
                    "started": "2026-04-21T14:21:55Z", "elapsed_s": 73}],
        "recent_completed": [{"job_id": "b71f3c9d2b4e", "fn": "scrape_chapter",
                              "source": "ao3", "target": "ao3:1/ch1",
                              "duration_s": 42, "finished": "2026-04-21T14:20:00Z"}],
        "recent_failed": [],
    },
    "storage": {
        "postgres_bytes": 2_147_483_648, "media_bytes": 142_000_000_000,
        "block_vol": {"total_bytes": 161_061_273_600, "used_bytes": 144_000_000_000,
                      "free_bytes": 17_061_273_600, "mount": "/mnt/astral-media"},
        "object_storage": {"bucket": "astral-backups",
                           "used_bytes": 3_650_000_000, "tier": "standard"},
        "trend_7d": {"postgres": [1,2,3], "media": [1,2,3],
                     "block_free": [1,2,3], "object_used": [1,2,3]},
    },
    "backups": {
        "last_pg_dump": "2026-04-20T03:00:12Z", "last_size_bytes": 2_050_000_000,
        "status": "ok", "next_run_in_s": 45_588, "bucket": "astral-backups",
        "retention_days": 56,
        "recent_runs": [{"started": "2026-04-20T03:00:00Z", "duration_s": 42,
                         "size_bytes": 2_050_000_000, "status": "ok"}],
    },
    "cert": {
        "domain": "astral-reader.duckdns.org", "issuer": "Let's Encrypt R11",
        "not_before": "2026-03-12T10:14:03Z", "not_after": "2026-06-10T10:14:02Z",
        "days_left": 51, "last_renew": {"at": "2026-04-15T12:00:07Z", "status": "ok"},
    },
    "logs": [{"ts": "2026-04-21T14:23:00.412Z", "svc": "nginx",
              "lvl": "info", "msg": "GET /x 200"}],
}


def test_golden_parse_succeeds():
    resp = MetricsResponse.model_validate(GOLDEN)
    assert resp.schema_version == "1.0.0"
    assert resp.cost.budget == 1.00
    assert resp.cost.always_free.a1_ocpu.used == 4
    assert resp.services[0].name == "postgres"
    assert resp.arq.queue_depth == 2
    assert resp.cert.days_left == 51
    assert resp.logs[0].svc == "nginx"


def test_missing_required_key_raises():
    bad = {**GOLDEN}
    del bad["cost"]
    with pytest.raises(ValidationError):
        MetricsResponse.model_validate(bad)


def test_degraded_meta_sidecar_accepted():
    with_meta = {**GOLDEN, "cost_meta": {
        "degraded": True, "reason": "oci api timeout",
        "last_good": "2026-04-21T14:18:00Z",
    }}
    resp = MetricsResponse.model_validate(with_meta)
    assert resp.cost_meta is not None
    assert resp.cost_meta.degraded is True
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd backend && python -m pytest monitor/tests/test_schema.py -v
```

Expected: `ModuleNotFoundError: No module named 'monitor.schema'`.

- [ ] **Step 3: Implement `schema.py`**

Create `backend/monitor/schema.py`:

```python
"""Pydantic v2 models for the /metrics response contract.

1:1 with the JSON schema comment block at the top of the handoff's
Dashboard.html. Any change here must be mirrored in the UI's render
functions — treat this as the UI contract.
"""
from __future__ import annotations

from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field


class CapUsage(BaseModel):
    used: float
    cap: float
    unit: str


class DegradedMeta(BaseModel):
    degraded: bool
    reason: str
    last_good: Optional[datetime] = None


class AlwaysFree(BaseModel):
    a1_ocpu:       CapUsage
    a1_ram_gb:     CapUsage
    block_vol_gb:  CapUsage
    egress_tb:     CapUsage
    object_std_gb: Optional[CapUsage] = None


class CostBlock(BaseModel):
    currency: str
    month_to_date: float
    forecast: float
    budget: float
    last_alert: Optional[datetime] = None
    always_free: AlwaysFree


class ServiceBlock(BaseModel):
    model_config = ConfigDict(extra="allow")

    name: str
    image: str
    container_id: str
    status: Literal["up", "restarting", "stopped", "unhealthy", "starting"]
    health: Optional[Literal["healthy", "starting", "unhealthy"]] = None
    uptime_s: int
    cpu_pct: float
    mem_mb: float
    restarts: int = 0
    extra: dict = Field(default_factory=dict)
    spark_cpu: list[float]


class SlowEndpoint(BaseModel):
    method: str
    path: str
    p50_ms: int
    p95_ms: int
    p99_ms: int
    count: int


class StatusCodes(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    two_xx:   int = Field(alias="2xx")
    three_xx: int = Field(alias="3xx")
    four_xx:  int = Field(alias="4xx")
    five_xx:  int = Field(alias="5xx")


class RequestsBlock(BaseModel):
    window: Literal["1h", "6h", "24h", "7d", "30d"]
    series_rps:    list[tuple[int, float]]
    series_p95_ms: list[tuple[int, float]]
    status_codes:  StatusCodes
    slowest:       list[SlowEndpoint]


class ArqActiveJob(BaseModel):
    job_id: str
    fn: str
    source: str
    target: str
    started: datetime
    elapsed_s: int


class ArqCompletedJob(BaseModel):
    job_id: str
    fn: str
    source: str
    target: str
    duration_s: int
    finished: datetime


class ArqFailedJob(BaseModel):
    job_id: str
    fn: str
    source: str
    target: str
    error: str = ""
    finished: datetime


class ArqBlock(BaseModel):
    queue_depth: int
    in_flight: int
    workers: int
    completed_24h: int
    failed_24h: int
    active: list[ArqActiveJob]
    recent_completed: list[ArqCompletedJob]
    recent_failed: list[ArqFailedJob]


class BlockVolStorage(BaseModel):
    total_bytes: int
    used_bytes: int
    free_bytes: int
    mount: str


class ObjectStorage(BaseModel):
    bucket: str
    used_bytes: int
    tier: str


class StorageTrend(BaseModel):
    postgres:    list[int]
    media:       list[int]
    block_free:  list[int]
    object_used: list[int]


class StorageBlock(BaseModel):
    postgres_bytes: Optional[int] = None
    media_bytes:    Optional[int] = None
    block_vol:      Optional[BlockVolStorage] = None
    object_storage: Optional[ObjectStorage] = None
    trend_7d:       StorageTrend


class BackupRun(BaseModel):
    started: datetime
    duration_s: int
    size_bytes: int
    status: str


class BackupsBlock(BaseModel):
    last_pg_dump: Optional[datetime] = None
    last_size_bytes: Optional[int] = None
    status: Literal["ok", "stale", "failed"]
    next_run_in_s: int
    bucket: str
    retention_days: int
    recent_runs: list[BackupRun]


class CertRenew(BaseModel):
    at: Optional[datetime] = None
    status: Literal["ok", "skipped", "failed"]


class CertBlock(BaseModel):
    domain: str
    issuer: Optional[str] = None
    not_before: Optional[datetime] = None
    not_after: Optional[datetime] = None
    days_left: Optional[int] = None
    last_renew: CertRenew


class LogLine(BaseModel):
    ts: datetime
    svc: str
    lvl: Literal["debug", "info", "warn", "error"]
    msg: str


class MetricsResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_version: str
    generated_at:   datetime
    build:          str
    tenancy_ocid:   str
    region:         str
    instance_ocid:  str

    cost:     CostBlock
    services: list[ServiceBlock]
    requests: RequestsBlock
    arq:      ArqBlock
    storage:  StorageBlock
    backups:  BackupsBlock
    cert:     CertBlock
    logs:     list[LogLine]

    cost_meta:     Optional[DegradedMeta] = None
    services_meta: Optional[DegradedMeta] = None
    requests_meta: Optional[DegradedMeta] = None
    arq_meta:      Optional[DegradedMeta] = None
    storage_meta:  Optional[DegradedMeta] = None
    backups_meta:  Optional[DegradedMeta] = None
    cert_meta:     Optional[DegradedMeta] = None
    logs_meta:     Optional[DegradedMeta] = None
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd backend && python -m pytest monitor/tests/test_schema.py -v
```

Expected: all three tests `PASSED`.

- [ ] **Step 5: Commit**

```bash
git add backend/monitor/schema.py backend/monitor/tests/test_schema.py
git commit -m "[backend] AST-NN monitor: pydantic v2 schema for /metrics contract

MetricsResponse + all nested blocks, 1:1 with the handoff's JSON schema.
Degraded-mode sidecars (*_meta) are optional. extra='forbid' on the
top level catches typo'd keys at serialize time.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Two-layer cache + `safe()` wrapper

**Files:**
- Modify: `backend/requirements-test.txt` — add fakeredis + cryptography.
- Create: `backend/monitor/cache.py`
- Create: `backend/monitor/tests/test_cache.py`
- Create: `backend/monitor/tests/test_safe.py`

- [ ] **Step 1: Add fakeredis to test requirements**

Edit `backend/requirements-test.txt` to:

```
pytest==8.3.3
pytest-asyncio==0.24.0
aiosqlite==0.20.0
httpx==0.27.2
fakeredis==2.26.*
cryptography==43.*
```

`oci` and `docker` stay as lazy imports inside collector `_fetch_*` functions — tests monkeypatch those functions and never trigger the import, so we save ~50 MB of test-env deps.

- [ ] **Step 2: Write failing tests**

Create `backend/monitor/tests/test_cache.py`:

```python
"""Two-layer cache: in-proc TTL eviction + Redis roundtrip via fakeredis."""
import pytest
from fakeredis import FakeAsyncRedis

from monitor.cache import InProcCache, RedisCache, set_last_good, get_last_good


@pytest.mark.asyncio
async def test_inproc_cache_returns_miss_until_set():
    c = InProcCache()
    assert c.get("k") is None
    c.set("k", "v", ttl=60)
    assert c.get("k") == "v"


@pytest.mark.asyncio
async def test_inproc_cache_evicts_after_ttl(monkeypatch):
    c = InProcCache()
    now = [1000.0]
    monkeypatch.setattr("monitor.cache.time.monotonic", lambda: now[0])
    c.set("k", "v", ttl=10)
    now[0] = 1005.0
    assert c.get("k") == "v"
    now[0] = 1011.0
    assert c.get("k") is None


@pytest.mark.asyncio
async def test_redis_cache_roundtrip():
    r = FakeAsyncRedis(decode_responses=True)
    c = RedisCache(r)
    await c.set("mon:k", {"a": 1, "b": [1, 2, 3]}, ttl=60)
    got = await c.get("mon:k")
    assert got == {"a": 1, "b": [1, 2, 3]}


@pytest.mark.asyncio
async def test_redis_cache_returns_none_on_miss():
    r = FakeAsyncRedis(decode_responses=True)
    c = RedisCache(r)
    assert await c.get("mon:missing") is None


@pytest.mark.asyncio
async def test_last_good_roundtrip():
    r = FakeAsyncRedis(decode_responses=True)
    payload = {"foo": "bar", "n": 42}
    await set_last_good(r, "cost", payload)
    assert await get_last_good(r, "cost") == payload
```

Create `backend/monitor/tests/test_safe.py`:

```python
"""safe() wrapper — passes through on success; degraded on timeout/exception."""
import asyncio

import pytest
from fakeredis import FakeAsyncRedis

from monitor.cache import safe


@pytest.mark.asyncio
async def test_safe_passes_through_on_success():
    r = FakeAsyncRedis(decode_responses=True)

    async def ok():
        return {"value": 1}

    data, meta = await safe(ok, "ok_collector", redis=r, timeout=1.0)
    assert data == {"value": 1}
    assert meta is None


@pytest.mark.asyncio
async def test_safe_marks_degraded_on_timeout():
    r = FakeAsyncRedis(decode_responses=True)

    async def hang():
        await asyncio.sleep(5)

    data, meta = await safe(hang, "slow", redis=r, timeout=0.05, fallback={"x": 0})
    assert data == {"x": 0}
    assert meta is not None and meta["degraded"] is True
    assert "timeout" in meta["reason"].lower()


@pytest.mark.asyncio
async def test_safe_marks_degraded_on_exception():
    r = FakeAsyncRedis(decode_responses=True)

    async def boom():
        raise RuntimeError("nope")

    data, meta = await safe(boom, "broken", redis=r, timeout=1.0, fallback={"x": 0})
    assert data == {"x": 0}
    assert meta is not None and meta["degraded"] is True
    assert "nope" in meta["reason"]


@pytest.mark.asyncio
async def test_safe_uses_last_good_when_available():
    from monitor.cache import set_last_good

    r = FakeAsyncRedis(decode_responses=True)
    await set_last_good(r, "flaky", {"cached_value": 7})

    async def boom():
        raise RuntimeError("temporary")

    data, meta = await safe(boom, "flaky", redis=r, timeout=1.0, fallback={"cached_value": 0})
    assert data == {"cached_value": 7}
    assert meta["degraded"] is True
```

- [ ] **Step 3: Run to verify they fail**

```bash
cd backend && python -m pytest monitor/tests/test_cache.py monitor/tests/test_safe.py -v
```

Expected: `ModuleNotFoundError: No module named 'monitor.cache'`.

- [ ] **Step 4: Implement `cache.py`**

Create `backend/monitor/cache.py`:

```python
"""Two-layer cache for the monitor service.

Layer 1: in-process dict with monotonic-clock TTL.
Layer 2: Redis (JSON + SETEX). Survives container restarts.

safe() gives every collector a degraded-fallback story.
"""
from __future__ import annotations

import asyncio
import json
import logging
import time
from typing import Any, Awaitable, Callable, Optional

import redis.asyncio as aioredis

logger = logging.getLogger("monitor.cache")

_LAST_GOOD_TTL_S = 86_400


class InProcCache:
    def __init__(self) -> None:
        self._store: dict[str, tuple[float, Any]] = {}

    def get(self, key: str) -> Optional[Any]:
        entry = self._store.get(key)
        if entry is None:
            return None
        expires_at, value = entry
        if time.monotonic() >= expires_at:
            self._store.pop(key, None)
            return None
        return value

    def set(self, key: str, value: Any, ttl: int) -> None:
        self._store[key] = (time.monotonic() + ttl, value)


class RedisCache:
    def __init__(self, redis: aioredis.Redis) -> None:
        self._r = redis

    async def get(self, key: str) -> Optional[Any]:
        raw = await self._r.get(key)
        if raw is None:
            return None
        try:
            return json.loads(raw)
        except (TypeError, ValueError):
            logger.warning("cache.RedisCache: bad JSON at key=%s", key)
            return None

    async def set(self, key: str, value: Any, ttl: int) -> None:
        try:
            await self._r.set(key, json.dumps(value, default=str), ex=ttl)
        except Exception as e:
            logger.debug("cache.RedisCache.set failed key=%s err=%s", key, e)


async def set_last_good(redis: aioredis.Redis, name: str, value: Any) -> None:
    try:
        await redis.set(
            f"mon:last_good:{name}",
            json.dumps(value, default=str),
            ex=_LAST_GOOD_TTL_S,
        )
    except Exception as e:
        logger.debug("set_last_good failed name=%s err=%s", name, e)


async def get_last_good(redis: aioredis.Redis, name: str) -> Optional[Any]:
    try:
        raw = await redis.get(f"mon:last_good:{name}")
        if raw is None:
            return None
        return json.loads(raw)
    except Exception as e:
        logger.debug("get_last_good failed name=%s err=%s", name, e)
        return None


async def safe(
    coll: Callable[[], Awaitable[Any]],
    name: str,
    *,
    redis: Optional[aioredis.Redis] = None,
    timeout: float = 2.0,
    fallback: Any = None,
) -> tuple[Any, Optional[dict]]:
    """Call coll() under a timeout; on failure fall back to last-known-good."""
    try:
        data = await asyncio.wait_for(coll(), timeout)
        if redis is not None:
            await set_last_good(redis, name, data)
        return data, None
    except asyncio.TimeoutError:
        reason = f"timeout after {timeout}s"
    except Exception as e:
        reason = f"{type(e).__name__}: {e}"[:120]
        logger.warning("collector %s failed: %s", name, reason)

    last = await get_last_good(redis, name) if redis is not None else None
    data_out = last if last is not None else fallback
    meta = {
        "degraded": True,
        "reason": reason,
        "last_good": _maybe_iso(last.get("generated_at") if isinstance(last, dict) else None),
    }
    return data_out, meta


def _maybe_iso(v: Any) -> Optional[str]:
    if v is None:
        return None
    if isinstance(v, str):
        return v
    if hasattr(v, "isoformat"):
        return v.isoformat()
    return str(v)


# ── module-level redis handle, set by main.lifespan ────────────────────

_REDIS: Optional[aioredis.Redis] = None


def set_redis(r: aioredis.Redis) -> None:
    global _REDIS
    _REDIS = r


def get_cache_redis_or_none() -> Optional[aioredis.Redis]:
    return _REDIS


def get_cache_redis() -> aioredis.Redis:
    if _REDIS is None:
        raise RuntimeError("monitor redis not initialized — call set_redis() in lifespan")
    return _REDIS
```

- [ ] **Step 5: Run to verify tests pass**

```bash
cd backend && python -m pytest monitor/tests/test_cache.py monitor/tests/test_safe.py -v
```

Expected: all 9 tests `PASSED`.

- [ ] **Step 6: Commit**

```bash
git add backend/requirements-test.txt backend/monitor/cache.py backend/monitor/tests/test_cache.py backend/monitor/tests/test_safe.py
git commit -m "[backend] AST-NN monitor: two-layer cache + safe() wrapper

InProcCache (monotonic TTL dict) for cheap+fast, RedisCache (JSON
SETEX) for expensive+slow. set_last_good/get_last_good back the
safe() request-path wrapper — any failure falls back to last-known
from Redis, then fallback, emitting a degraded-meta sidecar.

Adds fakeredis + cryptography to requirements-test.txt (oci + docker stay as lazy imports inside collectors).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 3 — Background samplers

### Task 9: `bg.py` — `supervise()` + stubs

**Files:**
- Create: `backend/monitor/bg.py`
- Create: `backend/monitor/tests/test_bg_supervise.py`

- [ ] **Step 1: Write the failing test**

Create `backend/monitor/tests/test_bg_supervise.py`:

```python
"""supervise() — catches exceptions, backs off, relaunches."""
import asyncio

import pytest

from monitor.bg import supervise


@pytest.mark.asyncio
async def test_supervise_restarts_after_exception(monkeypatch):
    call_count = {"n": 0}

    async def flaky():
        call_count["n"] += 1
        if call_count["n"] < 3:
            raise RuntimeError("boom")

    monkeypatch.setattr("monitor.bg._BACKOFF_INITIAL_S", 0.01)
    monkeypatch.setattr("monitor.bg._BACKOFF_MAX_S", 0.02)

    await supervise(flaky, "flaky")
    assert call_count["n"] == 3


@pytest.mark.asyncio
async def test_supervise_propagates_cancelled_error():
    async def hangs():
        await asyncio.Event().wait()

    task = asyncio.create_task(supervise(hangs, "hangs"))
    await asyncio.sleep(0.01)
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task


@pytest.mark.asyncio
async def test_supervise_returns_on_clean_exit(monkeypatch):
    async def clean():
        return

    monkeypatch.setattr("monitor.bg._BACKOFF_INITIAL_S", 0.01)
    await supervise(clean, "clean")
```

- [ ] **Step 2: Run to verify fail**

```bash
cd backend && python -m pytest monitor/tests/test_bg_supervise.py -v
```

Expected: `ModuleNotFoundError: No module named 'monitor.bg'`.

- [ ] **Step 3: Implement `bg.py` skeleton with supervise + stubs**

Create `backend/monitor/bg.py`:

```python
"""Long-lived background tasks for the monitor service."""
from __future__ import annotations

import asyncio
import logging
from collections import deque
from typing import Any, Awaitable, Callable, Deque

logger = logging.getLogger("monitor.bg")

_BACKOFF_INITIAL_S = 10
_BACKOFF_MAX_S = 60

SERVICE_CACHE: dict[str, dict[str, Any]] = {}
LOG_DEQUE: Deque[dict[str, Any]] = deque(maxlen=500)
NGINX_WINDOW_CACHE: dict[str, dict[str, Any]] = {}


async def supervise(factory: Callable[[], Awaitable[Any]], name: str) -> None:
    """Restart factory() on non-Cancelled exceptions with exponential backoff."""
    backoff = _BACKOFF_INITIAL_S
    while True:
        try:
            await factory()
            return
        except asyncio.CancelledError:
            raise
        except Exception as e:
            logger.exception("bg task %s died: %s — retry in %ss", name, e, backoff)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, _BACKOFF_MAX_S)


async def docker_sampler() -> None:
    raise NotImplementedError


async def log_tailer() -> None:
    raise NotImplementedError


async def nginx_access_sampler() -> None:
    raise NotImplementedError
```

- [ ] **Step 4: Run to verify pass**

```bash
cd backend && python -m pytest monitor/tests/test_bg_supervise.py -v
```

Expected: all 3 tests `PASSED`.

- [ ] **Step 5: Commit**

```bash
git add backend/monitor/bg.py backend/monitor/tests/test_bg_supervise.py
git commit -m "[backend] AST-NN monitor: bg supervise() + placeholder sampler stubs

supervise(factory, name) restart-with-backoff wrapper for long-lived
bg tasks. Shared state declarations (SERVICE_CACHE, LOG_DEQUE,
NGINX_WINDOW_CACHE) so collectors can import now; real bodies land
in subsequent tasks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: `docker_sampler` + `services` collector

**Files:**
- Modify: `backend/monitor/bg.py`
- Create: `backend/monitor/collectors/services.py`
- Create: `backend/monitor/tests/test_docker_sampler.py`
- Create: `backend/monitor/tests/collectors/test_services.py`

- [ ] **Step 1: Write failing tests**

Create `backend/monitor/tests/test_docker_sampler.py`:

```python
"""docker_sampler — single-tick population of SERVICE_CACHE."""
from unittest.mock import AsyncMock, MagicMock

import pytest

from monitor.bg import SERVICE_CACHE, _sample_once


def _fake_container(name):
    c = MagicMock()
    c.name = f"backend-{name}-1"
    c.labels = {"com.docker.compose.service": name}
    c.short_id = "abc123def456"
    c.image.tags = [f"{name}:latest"]
    c.attrs = {"State": {
        "Status": "running",
        "Health": {"Status": "healthy"},
        "StartedAt": "2026-04-21T10:00:00.0Z",
    }}
    c.stats.return_value = {
        "cpu_stats": {
            "cpu_usage": {"total_usage": 2_000_000_000},
            "system_cpu_usage": 100_000_000_000,
            "online_cpus": 4,
        },
        "precpu_stats": {
            "cpu_usage": {"total_usage": 1_000_000_000},
            "system_cpu_usage": 90_000_000_000,
        },
        "memory_stats": {"usage": 412_000_000, "stats": {"cache": 10_000_000}},
    }
    return c


@pytest.mark.asyncio
async def test_sample_once_populates_all_six_services():
    SERVICE_CACHE.clear()
    client = MagicMock()
    client.containers.list.return_value = [
        _fake_container(n) for n in (
            "postgres", "redis", "fastapi", "arq_worker", "nginx", "certbot"
        )
    ]

    redis = MagicMock()
    redis.zadd = AsyncMock(return_value=1)
    redis.zremrangebyscore = AsyncMock(return_value=0)

    await _sample_once(client, redis)

    assert set(SERVICE_CACHE.keys()) == {
        "postgres", "redis", "fastapi", "arq_worker", "nginx", "certbot"
    }
    fastapi = SERVICE_CACHE["fastapi"]
    assert fastapi["status"] == "up"
    assert fastapi["health"] == "healthy"
    assert fastapi["cpu_pct"] > 0
```

Create `backend/monitor/tests/collectors/test_services.py`:

```python
"""services.collect() reads SERVICE_CACHE."""
import pytest

from monitor.bg import SERVICE_CACHE
from monitor.collectors.services import collect


@pytest.mark.asyncio
async def test_collect_returns_all_populated_services():
    SERVICE_CACHE.clear()
    SERVICE_CACHE["postgres"] = {
        "name": "postgres", "image": "postgres:16-alpine",
        "container_id": "abc", "status": "up", "health": "healthy",
        "uptime_s": 1000, "cpu_pct": 2.4, "mem_mb": 412.0, "restarts": 0,
        "extra": {}, "spark_cpu": [1.0, 1.5, 2.0],
    }
    blocks = await collect()
    assert len(blocks) == 1
    assert blocks[0].name == "postgres"
    assert blocks[0].cpu_pct == 2.4


@pytest.mark.asyncio
async def test_collect_returns_empty_when_cache_empty():
    SERVICE_CACHE.clear()
    blocks = await collect()
    assert blocks == []
```

- [ ] **Step 2: Run to verify fail**

```bash
cd backend && python -m pytest monitor/tests/test_docker_sampler.py monitor/tests/collectors/test_services.py -v
```

Expected: import errors.

- [ ] **Step 3: Replace `docker_sampler` stub in `bg.py`**

Edit `backend/monitor/bg.py` — replace the `async def docker_sampler(): raise NotImplementedError` with:

```python
async def _sample_once(client, redis) -> None:
    """Single-tick: walk containers, update SERVICE_CACHE + Redis sparklines."""
    import time as _time
    from datetime import datetime, timezone

    now_ms = int(_time.time() * 1000)
    containers = client.containers.list(
        all=True,
        filters={"label": "com.docker.compose.project=backend"},
    )
    for c in containers:
        svc = c.labels.get("com.docker.compose.service")
        if not svc:
            continue
        state = c.attrs.get("State", {})
        status = state.get("Status", "unknown")
        health_obj = state.get("Health")
        health = health_obj.get("Status") if isinstance(health_obj, dict) else None
        started_at = state.get("StartedAt") or ""
        try:
            started_dt = datetime.fromisoformat(started_at.replace("Z", "+00:00"))
            uptime_s = int((datetime.now(timezone.utc) - started_dt).total_seconds())
        except Exception:
            uptime_s = 0

        try:
            stats = c.stats(stream=False)
        except Exception:
            stats = None

        cpu_pct = _compute_cpu_pct(stats) if stats else 0.0
        mem_mb = _compute_mem_mb(stats) if stats else 0.0

        image_tag = (c.image.tags or [""])[0]
        ui_status = {
            "running": "up", "restarting": "restarting",
            "exited": "stopped", "paused": "unhealthy",
            "dead": "unhealthy", "created": "starting",
        }.get(status, status)

        entry = SERVICE_CACHE.setdefault(svc, {
            "name": svc, "image": image_tag, "container_id": c.short_id,
            "status": ui_status, "health": health, "uptime_s": uptime_s,
            "cpu_pct": cpu_pct, "mem_mb": mem_mb, "restarts": 0,
            "extra": {}, "spark_cpu": [],
        })
        entry.update({
            "image": image_tag, "container_id": c.short_id,
            "status": ui_status, "health": health, "uptime_s": uptime_s,
            "cpu_pct": round(cpu_pct, 2), "mem_mb": round(mem_mb, 1),
        })
        entry["spark_cpu"] = (entry.get("spark_cpu", []) + [round(cpu_pct, 2)])[-120:]

        try:
            await redis.zadd(f"mon:sparkline:{svc}", {str(cpu_pct): now_ms})
            await redis.zremrangebyscore(
                f"mon:sparkline:{svc}", 0, now_ms - 7 * 24 * 3600 * 1000,
            )
        except Exception as e:
            logger.debug("sparkline update failed svc=%s err=%s", svc, e)


def _compute_cpu_pct(stats: dict) -> float:
    try:
        cpu_delta = stats["cpu_stats"]["cpu_usage"]["total_usage"] \
            - stats["precpu_stats"]["cpu_usage"]["total_usage"]
        sys_delta = stats["cpu_stats"]["system_cpu_usage"] \
            - stats["precpu_stats"]["system_cpu_usage"]
        cpus = stats["cpu_stats"].get("online_cpus", 1)
        if sys_delta <= 0 or cpu_delta < 0:
            return 0.0
        return (cpu_delta / sys_delta) * cpus * 100.0
    except (KeyError, TypeError):
        return 0.0


def _compute_mem_mb(stats: dict) -> float:
    try:
        usage = stats["memory_stats"].get("usage", 0)
        cache_bytes = stats["memory_stats"].get("stats", {}).get("cache", 0)
        return max(0.0, (usage - cache_bytes) / 1024 / 1024)
    except (KeyError, TypeError):
        return 0.0


async def docker_sampler() -> None:
    """Every 10s: one full pass."""
    import docker

    from monitor.cache import get_cache_redis_or_none
    client = docker.from_env()
    redis = get_cache_redis_or_none()

    while True:
        try:
            await _sample_once(client, redis)
        except Exception as e:
            logger.warning("docker_sampler tick failed: %s", e)
        await asyncio.sleep(10)
```

- [ ] **Step 4: Implement `collectors/services.py`**

Create `backend/monitor/collectors/services.py`:

```python
"""services collector — reads SERVICE_CACHE populated by docker_sampler."""
from __future__ import annotations

from monitor.bg import SERVICE_CACHE
from monitor.schema import ServiceBlock


async def collect() -> list[ServiceBlock]:
    blocks: list[ServiceBlock] = []
    for _name, entry in SERVICE_CACHE.items():
        blocks.append(ServiceBlock.model_validate(entry))
    order = {
        "postgres": 0, "redis": 1, "fastapi": 2,
        "arq_worker": 3, "nginx": 4, "certbot": 5,
    }
    blocks.sort(key=lambda b: order.get(b.name, 99))
    return blocks
```

- [ ] **Step 5: Run tests**

```bash
cd backend && python -m pytest monitor/tests/test_docker_sampler.py monitor/tests/collectors/test_services.py -v
```

Expected: all 4 tests `PASSED`.

- [ ] **Step 6: Commit**

```bash
git add backend/monitor/bg.py backend/monitor/collectors/services.py backend/monitor/tests/test_docker_sampler.py backend/monitor/tests/collectors/test_services.py
git commit -m "[backend] AST-NN monitor: docker_sampler bg task + services collector

_sample_once walks all compose containers, populates SERVICE_CACHE
with status/health/uptime/cpu_pct/mem_mb/spark_cpu, writes per-service
sparkline ZSET to Redis (7d ZREMRANGEBYSCORE). docker_sampler runs
every 10s under supervise(). services.collect() reads the in-proc
cache, ordered to match the handoff's 6-card grid.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 4 — Cheap collectors (cert, arq, storage, logs)

### Task 11: `cert` collector

**Files:**
- Create: `backend/monitor/collectors/cert.py`
- Create: `backend/monitor/tests/collectors/test_cert.py`
- Create: `backend/monitor/tests/collectors/_fixtures/fullchain.pem`

- [ ] **Step 1: Generate a test cert fixture**

```bash
cd backend/monitor/tests/collectors
openssl req -x509 -newkey rsa:2048 -nodes -keyout /tmp/_tk.key \
  -out _fixtures/fullchain.pem -days 30 \
  -subj "/CN=astral-reader.duckdns.org/O=Let's Encrypt Test/C=US" 2>/dev/null
rm -f /tmp/_tk.key
ls _fixtures/
```

Expected: `fullchain.pem` exists.

- [ ] **Step 2: Write the failing test**

Create `backend/monitor/tests/collectors/test_cert.py`:

```python
"""cert.collect() — parse the LE cert file."""
from pathlib import Path

import pytest

from monitor.collectors import cert as cert_mod


@pytest.mark.asyncio
async def test_collect_parses_valid_cert(monkeypatch):
    fixture = Path(__file__).parent / "_fixtures" / "fullchain.pem"
    monkeypatch.setattr(cert_mod, "CERT_PATH", fixture)
    monkeypatch.setattr(cert_mod, "LE_LOG_PATH", fixture.parent / "nonexistent.log")

    block = await cert_mod.collect()
    assert block.domain == "astral-reader.duckdns.org"
    assert block.days_left is not None and 0 < block.days_left <= 30
    assert block.not_after is not None


@pytest.mark.asyncio
async def test_collect_returns_placeholder_when_file_missing(monkeypatch, tmp_path):
    monkeypatch.setattr(cert_mod, "CERT_PATH", tmp_path / "missing.pem")
    monkeypatch.setattr(cert_mod, "LE_LOG_PATH", tmp_path / "missing.log")

    block = await cert_mod.collect()
    assert block.domain == "astral-reader.duckdns.org"
    assert block.days_left is None
    assert block.last_renew.status == "failed"
```

- [ ] **Step 3: Run to verify fail**

```bash
cd backend && python -m pytest monitor/tests/collectors/test_cert.py -v
```

Expected: `ModuleNotFoundError`.

- [ ] **Step 4: Implement `collectors/cert.py`**

Create `backend/monitor/collectors/cert.py`:

```python
"""cert collector — parse /etc/letsencrypt/.../fullchain.pem."""
from __future__ import annotations

import logging
from datetime import datetime, timezone
from pathlib import Path

from cryptography import x509
from cryptography.x509.oid import NameOID

from monitor.schema import CertBlock, CertRenew

logger = logging.getLogger("monitor.cert")

CERT_PATH = Path("/etc/letsencrypt/live/astral-reader.duckdns.org/fullchain.pem")
LE_LOG_PATH = Path("/etc/letsencrypt/logs/letsencrypt.log")


async def collect() -> CertBlock:
    if not CERT_PATH.exists():
        return _placeholder("cert file missing")

    try:
        pem = CERT_PATH.read_bytes()
        cert = x509.load_pem_x509_certificate(pem)
    except Exception as e:
        logger.warning("cert parse failed: %s", e)
        return _placeholder(f"parse error: {e}")

    not_before = cert.not_valid_before_utc
    not_after = cert.not_valid_after_utc
    days_left = max(0, int((not_after - datetime.now(timezone.utc)).total_seconds() / 86400))

    issuer_cn = next(
        (a.value for a in cert.issuer if a.oid == NameOID.COMMON_NAME),
        "unknown issuer",
    )
    subject_cn = next(
        (a.value for a in cert.subject if a.oid == NameOID.COMMON_NAME),
        "astral-reader.duckdns.org",
    )

    last_renew_at, last_renew_status = _read_last_renew()

    return CertBlock(
        domain=subject_cn,
        issuer=issuer_cn,
        not_before=not_before,
        not_after=not_after,
        days_left=days_left,
        last_renew=CertRenew(at=last_renew_at, status=last_renew_status),
    )


def _placeholder(reason: str) -> CertBlock:
    logger.info("cert placeholder: %s", reason)
    return CertBlock(
        domain="astral-reader.duckdns.org",
        issuer=None,
        not_before=None, not_after=None, days_left=None,
        last_renew=CertRenew(at=None, status="failed"),
    )


def _read_last_renew() -> tuple[datetime | None, str]:
    try:
        stat = CERT_PATH.stat()
        at = datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc)
    except Exception:
        return None, "failed"

    status = "ok"
    if LE_LOG_PATH.exists():
        try:
            tail = LE_LOG_PATH.read_text(errors="replace").splitlines()[-200:]
            if any("failed" in line.lower() for line in tail):
                status = "failed"
            elif any("skipped" in line.lower() for line in tail):
                status = "skipped"
        except Exception:
            pass
    return at, status
```

- [ ] **Step 5: Run tests**

```bash
cd backend && python -m pytest monitor/tests/collectors/test_cert.py -v
```

Expected: both tests `PASSED`.

- [ ] **Step 6: Commit**

```bash
git add backend/monitor/collectors/cert.py backend/monitor/tests/collectors/test_cert.py backend/monitor/tests/collectors/_fixtures/fullchain.pem
git commit -m "[backend] AST-NN monitor: cert collector (cryptography x509 parse)

Reads fullchain.pem, extracts subject/issuer CNs and not_before/after,
computes days_left. last_renew uses cert mtime as proxy; scans certbot
log for failed/skipped. Placeholder with degraded=True when file is
unreadable.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: `arq` collector

**Files:**
- Create: `backend/monitor/collectors/arq.py`
- Create: `backend/monitor/tests/collectors/test_arq.py`

- [ ] **Step 1: Write failing test**

Create `backend/monitor/tests/collectors/test_arq.py`:

```python
"""arq.collect() — pulls queue + in-flight + recent from Redis."""
import json
import time

import pytest
from fakeredis import FakeAsyncRedis

from monitor.collectors import arq as arq_mod


@pytest.mark.asyncio
async def test_collect_empty_queue(monkeypatch):
    r = FakeAsyncRedis(decode_responses=True)
    monkeypatch.setattr(arq_mod, "get_cache_redis", lambda: r)
    block = await arq_mod.collect()
    assert block.queue_depth == 0
    assert block.in_flight == 0
    assert block.active == []


@pytest.mark.asyncio
async def test_collect_populated_queue(monkeypatch):
    r = FakeAsyncRedis(decode_responses=True)
    for i in range(3):
        await r.zadd("arq:queue", {f"job_{i}": time.time() * 1000 + i})

    await r.hset(
        "arq:in_progress:job_inflight",
        mapping={"function": "scrape_chapter", "enqueue_time": int(time.time() * 1000 - 70_000)},
    )
    await r.set(
        "arq:job:job_inflight",
        json.dumps({
            "function": "scrape_chapter",
            "args": ["ao3:55312041/ch3"],
            "kwargs": {},
            "enqueue_time": int(time.time() * 1000 - 70_000),
        }),
    )

    monkeypatch.setattr(arq_mod, "get_cache_redis", lambda: r)

    block = await arq_mod.collect()
    assert block.queue_depth == 3
    assert block.in_flight == 1
    assert len(block.active) == 1
```

- [ ] **Step 2: Run to verify fail**

```bash
cd backend && python -m pytest monitor/tests/collectors/test_arq.py -v
```

Expected: `ModuleNotFoundError`.

- [ ] **Step 3: Implement `collectors/arq.py`**

Create `backend/monitor/collectors/arq.py`:

```python
"""arq collector — introspect ARQ state from Redis."""
from __future__ import annotations

import json
import logging
import os
import time
from datetime import datetime, timezone

from monitor.cache import get_cache_redis
from monitor.schema import ArqActiveJob, ArqBlock, ArqCompletedJob, ArqFailedJob

logger = logging.getLogger("monitor.arq")

_ARQ_MAX_JOBS = int(os.getenv("ARQ_MAX_JOBS", "3"))


async def collect() -> ArqBlock:
    r = get_cache_redis()

    queue_depth = int(await r.zcard("arq:queue") or 0)

    in_progress_keys = []
    async for k in r.scan_iter(match="arq:in_progress:*", count=200):
        in_progress_keys.append(k)
    in_flight = len(in_progress_keys)

    active = []
    now_ms = int(time.time() * 1000)
    for key in in_progress_keys[:20]:
        job_id = key.split(":", 2)[-1]
        payload = await r.get(f"arq:job:{job_id}")
        if not payload:
            continue
        try:
            jd = json.loads(payload)
        except Exception:
            continue
        fn = jd.get("function", "unknown")
        target = _extract_target(jd)
        source = _extract_source(target)
        enqueue = jd.get("enqueue_time", now_ms)
        started = datetime.fromtimestamp(enqueue / 1000, tz=timezone.utc)
        elapsed_s = max(0, int((now_ms - enqueue) / 1000))
        active.append(ArqActiveJob(
            job_id=job_id, fn=fn, source=source, target=target,
            started=started, elapsed_s=elapsed_s,
        ))

    completed_24h = int(await r.get("mon:arq_completed_24h") or 0)
    failed_24h = int(await r.get("mon:arq_failed_24h") or 0)

    recent_completed = await _recent_jobs(r, "arq:result:*", status_ok=True)
    recent_failed = await _recent_jobs(r, "arq:result:*", status_ok=False)

    return ArqBlock(
        queue_depth=queue_depth,
        in_flight=in_flight,
        workers=_ARQ_MAX_JOBS,
        completed_24h=completed_24h,
        failed_24h=failed_24h,
        active=active,
        recent_completed=[ArqCompletedJob(**d) for d in recent_completed],
        recent_failed=[ArqFailedJob(**d) for d in recent_failed],
    )


async def _recent_jobs(r, pattern: str, status_ok: bool, limit: int = 5) -> list[dict]:
    out = []
    async for key in r.scan_iter(match=pattern, count=200):
        if len(out) >= limit:
            break
        raw = await r.get(key)
        if not raw:
            continue
        try:
            jd = json.loads(raw)
        except Exception:
            continue
        if bool(jd.get("success")) != status_ok:
            continue
        job_id = key.split(":", 2)[-1]
        finished_at = jd.get("finish_time")
        enqueue = jd.get("enqueue_time", finished_at)
        duration_s = int((finished_at - enqueue) / 1000) if finished_at and enqueue else 0
        fn = jd.get("function", "unknown")
        target = _extract_target(jd)
        common = dict(
            job_id=job_id, fn=fn, source=_extract_source(target), target=target,
            finished=datetime.fromtimestamp((finished_at or 0) / 1000, tz=timezone.utc),
        )
        if status_ok:
            common["duration_s"] = duration_s
        else:
            common["error"] = str(jd.get("result") or "")[:120]
        out.append(common)
    return out


def _extract_target(jd: dict) -> str:
    args = jd.get("args") or []
    if args and isinstance(args[0], str):
        return args[0]
    return jd.get("function", "")


def _extract_source(target: str) -> str:
    for k in ("ao3", "ffnet", "nhentai", "toongod", "hentai20", "mangadex"):
        if target.startswith(k + ":") or k in target:
            return k
    return "unknown"
```

- [ ] **Step 4: Run tests**

```bash
cd backend && python -m pytest monitor/tests/collectors/test_arq.py -v
```

Expected: both tests `PASSED`.

- [ ] **Step 5: Commit**

```bash
git add backend/monitor/collectors/arq.py backend/monitor/tests/collectors/test_arq.py
git commit -m "[backend] AST-NN monitor: arq collector (redis introspection)

Reads arq:queue (ZCARD), arq:in_progress:* (SCAN), arq:result:*
(SCAN + filter success/failure). Emits ArqBlock with queue_depth,
in_flight, top-20 active jobs with elapsed_s, last-5 completed,
last-5 failed. Source classifier matches the 6 known scraper keys.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: `storage` collector

**Files:**
- Create: `backend/monitor/collectors/storage.py`
- Create: `backend/monitor/tests/collectors/test_storage.py`

- [ ] **Step 1: Write failing test**

Create `backend/monitor/tests/collectors/test_storage.py`:

```python
"""storage.collect() — statvfs + du + pg_database_size + OCI head."""
from unittest.mock import MagicMock

import pytest
from fakeredis import FakeAsyncRedis

from monitor.collectors import storage as storage_mod


@pytest.mark.asyncio
async def test_collect_assembles_from_all_sources(monkeypatch):
    fake_stat = MagicMock()
    fake_stat.f_frsize = 4096
    fake_stat.f_blocks = 39_322_624
    fake_stat.f_bavail = 4_165_352
    monkeypatch.setattr(storage_mod.os, "statvfs", lambda _p: fake_stat)

    async def _du(_path):
        return 142_000_000_000

    monkeypatch.setattr(storage_mod, "_du_bytes", _du)

    async def _pg(_pool):
        return 2_147_483_648

    monkeypatch.setattr(storage_mod, "_pg_db_size", _pg)

    async def _os_head():
        return {"bucket": "astral-backups", "used_bytes": 3_650_000_000, "tier": "standard"}

    monkeypatch.setattr(storage_mod, "_object_storage_head", _os_head)
    monkeypatch.setattr(storage_mod, "get_cache_redis", lambda: FakeAsyncRedis(decode_responses=True))
    monkeypatch.setattr(storage_mod, "get_pg_pool_or_none", lambda: None)

    block = await storage_mod.collect()
    assert block.postgres_bytes == 2_147_483_648
    assert block.media_bytes == 142_000_000_000
    assert block.block_vol.total_bytes == 4096 * 39_322_624
    assert block.object_storage.bucket == "astral-backups"


@pytest.mark.asyncio
async def test_collect_tolerates_missing_pg(monkeypatch):
    fake_stat = MagicMock(f_frsize=4096, f_blocks=1000, f_bavail=500)
    monkeypatch.setattr(storage_mod.os, "statvfs", lambda _p: fake_stat)

    async def _du(_path):
        return 0

    async def _none():
        return None

    monkeypatch.setattr(storage_mod, "_du_bytes", _du)
    monkeypatch.setattr(storage_mod, "_object_storage_head", _none)
    monkeypatch.setattr(storage_mod, "get_pg_pool_or_none", lambda: None)
    monkeypatch.setattr(storage_mod, "get_cache_redis", lambda: FakeAsyncRedis(decode_responses=True))

    block = await storage_mod.collect()
    assert block.postgres_bytes is None
```

- [ ] **Step 2: Run to verify fail**

```bash
cd backend && python -m pytest monitor/tests/collectors/test_storage.py -v
```

Expected: `ModuleNotFoundError`.

- [ ] **Step 3: Implement `collectors/storage.py`**

Create `backend/monitor/collectors/storage.py`:

```python
"""storage collector — statvfs + du + pg_database_size + OCI Object Storage."""
from __future__ import annotations

import asyncio
import logging
import os
from typing import Optional

from monitor.cache import get_cache_redis
from monitor.schema import BlockVolStorage, ObjectStorage, StorageBlock, StorageTrend

logger = logging.getLogger("monitor.storage")

MEDIA_DIR = "/mnt/astral-media"

_pg_pool_handle = None


def set_pg_pool(pool) -> None:
    global _pg_pool_handle
    _pg_pool_handle = pool


def get_pg_pool_or_none():
    return _pg_pool_handle


async def collect() -> StorageBlock:
    pg_bytes = await _pg_db_size(get_pg_pool_or_none())
    media_bytes = await _du_bytes(MEDIA_DIR)
    block_vol = _statvfs_block(MEDIA_DIR)
    obj = await _object_storage_head()
    trend = await _trend_7d()

    return StorageBlock(
        postgres_bytes=pg_bytes,
        media_bytes=media_bytes,
        block_vol=block_vol,
        object_storage=ObjectStorage(**obj) if obj else None,
        trend_7d=trend,
    )


def _statvfs_block(path: str) -> Optional[BlockVolStorage]:
    try:
        s = os.statvfs(path)
        total = s.f_blocks * s.f_frsize
        free = s.f_bavail * s.f_frsize
        used = total - free
        return BlockVolStorage(
            total_bytes=total, used_bytes=used, free_bytes=free, mount=path,
        )
    except Exception as e:
        logger.debug("statvfs %s failed: %s", path, e)
        return None


async def _du_bytes(path: str) -> Optional[int]:
    try:
        proc = await asyncio.create_subprocess_exec(
            "du", "-sb", path,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
        )
        out, _ = await asyncio.wait_for(proc.communicate(), timeout=8.0)
        return int(out.split(b"\t", 1)[0])
    except Exception as e:
        logger.debug("du -sb %s failed: %s", path, e)
        return None


async def _pg_db_size(pool) -> Optional[int]:
    if pool is None:
        return None
    try:
        async with pool.acquire() as conn:
            row = await conn.fetchrow("SELECT pg_database_size(current_database()) AS b")
            return int(row["b"]) if row else None
    except Exception as e:
        logger.debug("pg_database_size failed: %s", e)
        return None


async def _object_storage_head() -> Optional[dict]:
    try:
        import oci
        signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
        client = oci.object_storage.ObjectStorageClient(config={}, signer=signer)
        namespace = client.get_namespace().data
        resp = client.get_bucket(namespace, "astral-backups")
        used = resp.data.approximate_size or 0
        return {"bucket": "astral-backups", "used_bytes": int(used), "tier": "standard"}
    except Exception as e:
        logger.debug("object_storage_head failed: %s", e)
        return None


async def _trend_7d() -> StorageTrend:
    r = get_cache_redis()

    async def _z(key):
        try:
            members = await r.zrange(key, 0, -1)
            return [int(float(m)) for m in members]
        except Exception:
            return []

    pg = await _z("mon:sparkline:storage:postgres")
    media = await _z("mon:sparkline:storage:media")
    free = await _z("mon:sparkline:storage:block_free")
    obj = await _z("mon:sparkline:storage:object_used")
    return StorageTrend(
        postgres=pg or [0],
        media=media or [0],
        block_free=free or [0],
        object_used=obj or [0],
    )
```

- [ ] **Step 4: Run tests**

```bash
cd backend && python -m pytest monitor/tests/collectors/test_storage.py -v
```

Expected: both tests `PASSED`.

- [ ] **Step 5: Commit**

```bash
git add backend/monitor/collectors/storage.py backend/monitor/tests/collectors/test_storage.py
git commit -m "[backend] AST-NN monitor: storage collector

Four independent sources, each tolerating its own failure:
os.statvfs('/mnt/astral-media') for block-vol; du -sb subprocess
(8s timeout) for media_bytes; pg_database_size for postgres_bytes;
OCI GetBucket for object_storage. Trend_7d reads the hourly hoister's
ZSETs (populated by Task 21).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 14: `logs` collector

**Files:**
- Create: `backend/monitor/collectors/logs.py`
- Create: `backend/monitor/tests/collectors/test_logs.py`

- [ ] **Step 1: Write failing test**

Create `backend/monitor/tests/collectors/test_logs.py`:

```python
"""logs.collect() — slice LOG_DEQUE with optional svc+q filters."""
from datetime import datetime, timezone

import pytest

from monitor.bg import LOG_DEQUE
from monitor.collectors import logs as logs_mod


@pytest.mark.asyncio
async def test_collect_returns_recent_lines():
    LOG_DEQUE.clear()
    for i in range(150):
        LOG_DEQUE.append({
            "ts": datetime(2026, 4, 21, 14, 0, i % 60, tzinfo=timezone.utc),
            "svc": "fastapi" if i % 2 else "nginx",
            "lvl": "info", "msg": f"line {i}",
        })
    lines = await logs_mod.collect(limit=100)
    assert len(lines) == 100
    assert lines[-1].msg == "line 149"


@pytest.mark.asyncio
async def test_collect_filters_by_service():
    LOG_DEQUE.clear()
    for i in range(10):
        LOG_DEQUE.append({
            "ts": datetime(2026, 4, 21, 14, 0, i, tzinfo=timezone.utc),
            "svc": "fastapi" if i % 2 else "redis",
            "lvl": "info", "msg": f"line {i}",
        })
    lines = await logs_mod.collect(limit=100, svc="fastapi")
    assert all(line.svc == "fastapi" for line in lines)


@pytest.mark.asyncio
async def test_collect_filters_by_query():
    LOG_DEQUE.clear()
    LOG_DEQUE.append({
        "ts": datetime(2026, 4, 21, 14, 0, 0, tzinfo=timezone.utc),
        "svc": "fastapi", "lvl": "error",
        "msg": "TimeoutError on /api/v1/x",
    })
    LOG_DEQUE.append({
        "ts": datetime(2026, 4, 21, 14, 0, 1, tzinfo=timezone.utc),
        "svc": "fastapi", "lvl": "info", "msg": "hello",
    })
    lines = await logs_mod.collect(limit=100, q="Timeout")
    assert len(lines) == 1
    assert "Timeout" in lines[0].msg
```

- [ ] **Step 2: Run to verify fail**

```bash
cd backend && python -m pytest monitor/tests/collectors/test_logs.py -v
```

Expected: `ModuleNotFoundError`.

- [ ] **Step 3: Implement `collectors/logs.py`**

Create `backend/monitor/collectors/logs.py`:

```python
"""logs collector — slice LOG_DEQUE with optional svc + q filters."""
from __future__ import annotations

from typing import Optional

from monitor.bg import LOG_DEQUE
from monitor.schema import LogLine


async def collect(limit: int = 100, svc: Optional[str] = None, q: Optional[str] = None) -> list[LogLine]:
    matches: list[dict] = []
    for entry in LOG_DEQUE:
        if svc and entry["svc"] != svc:
            continue
        if q and q.lower() not in entry["msg"].lower():
            continue
        matches.append(entry)
    return [LogLine.model_validate(m) for m in matches[-limit:]]
```

- [ ] **Step 4: Run tests**

```bash
cd backend && python -m pytest monitor/tests/collectors/test_logs.py -v
```

Expected: all 3 tests `PASSED`.

- [ ] **Step 5: Commit**

```bash
git add backend/monitor/collectors/logs.py backend/monitor/tests/collectors/test_logs.py
git commit -m "[backend] AST-NN monitor: logs collector

Slices LOG_DEQUE (populated by log_tailer in a later task) with
optional service chip filter + case-insensitive substring query.
Returns at most limit newest matches, chronological order.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 5 — Expensive collectors (cost, backups, requests)

### Task 15: `cost` collector (OCI Budget API)

**Files:**
- Create: `backend/monitor/collectors/cost.py`
- Create: `backend/monitor/tests/collectors/test_cost.py`

- [ ] **Step 1: Write failing test**

Create `backend/monitor/tests/collectors/test_cost.py`:

```python
"""cost.collect() — OCI budget + always-free, all mocked."""
from unittest.mock import MagicMock

import pytest
from fakeredis import FakeAsyncRedis

from monitor.collectors import cost as cost_mod


@pytest.mark.asyncio
async def test_collect_assembles_from_budget_api(monkeypatch):
    fake_budget = MagicMock()
    fake_budget.data.actual_spend = 0.0
    fake_budget.data.forecasted_spend = 0.0
    fake_budget.data.amount = 1.0
    fake_budget.data.currency = "USD"

    async def _fb():
        return fake_budget

    async def _faf():
        return {
            "a1_ocpu":       {"used": 4,  "cap": 4,  "unit": "ocpu"},
            "a1_ram_gb":     {"used": 24, "cap": 24, "unit": "GB"},
            "block_vol_gb":  {"used": 152,"cap": 200,"unit": "GB"},
            "egress_tb":     {"used": 0.18,"cap": 10,"unit": "TB"},
            "object_std_gb": {"used": 3.4,"cap": 20,"unit": "GB"},
        }

    monkeypatch.setattr(cost_mod, "_fetch_budget", _fb)
    monkeypatch.setattr(cost_mod, "_fetch_always_free", _faf)
    monkeypatch.setattr(cost_mod, "get_cache_redis", lambda: FakeAsyncRedis(decode_responses=True))

    block = await cost_mod.collect()
    assert block.month_to_date == 0.0
    assert block.budget == 1.0
    assert block.always_free.a1_ocpu.used == 4


@pytest.mark.asyncio
async def test_collect_raises_on_oci_failure(monkeypatch):
    async def _raise():
        raise RuntimeError("IMDS unreachable")

    monkeypatch.setattr(cost_mod, "_fetch_budget", _raise)
    monkeypatch.setattr(cost_mod, "get_cache_redis", lambda: FakeAsyncRedis(decode_responses=True))
    with pytest.raises(RuntimeError):
        await cost_mod.collect()
```

- [ ] **Step 2: Run to verify fail**

```bash
cd backend && python -m pytest monitor/tests/collectors/test_cost.py -v
```

Expected: `ModuleNotFoundError`.

- [ ] **Step 3: Implement `collectors/cost.py`**

Create `backend/monitor/collectors/cost.py`:

```python
"""cost collector — OCI Budget API + Always-Free usage inference."""
from __future__ import annotations

import asyncio
import json
import logging
import os
from typing import Optional

from monitor.cache import get_cache_redis
from monitor.schema import AlwaysFree, CapUsage, CostBlock

logger = logging.getLogger("monitor.cost")

_BUDGET_OCID = os.getenv("OCI_BUDGET_OCID")


async def collect() -> CostBlock:
    budget = await _fetch_budget()
    af = await _fetch_always_free()

    return CostBlock(
        currency=getattr(budget.data, "currency", "USD"),
        month_to_date=float(getattr(budget.data, "actual_spend", 0.0) or 0.0),
        forecast=float(getattr(budget.data, "forecasted_spend", 0.0) or 0.0),
        budget=float(getattr(budget.data, "amount", 1.0) or 1.0),
        last_alert=None,
        always_free=AlwaysFree(
            a1_ocpu=CapUsage(**af["a1_ocpu"]),
            a1_ram_gb=CapUsage(**af["a1_ram_gb"]),
            block_vol_gb=CapUsage(**af["block_vol_gb"]),
            egress_tb=CapUsage(**af["egress_tb"]),
            object_std_gb=CapUsage(**af["object_std_gb"]) if "object_std_gb" in af else None,
        ),
    )


async def _fetch_budget():
    """OCI Budget API via instance-principal signer."""
    if not _BUDGET_OCID:
        raise RuntimeError("OCI_BUDGET_OCID env var not set")

    def _sync():
        import oci
        signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
        client = oci.budget.BudgetClient(config={}, signer=signer)
        return client.get_budget(_BUDGET_OCID)

    return await asyncio.to_thread(_sync)


async def _fetch_always_free() -> dict:
    """Assemble 5-dimension usage-vs-cap snapshot.

    block_vol_gb + object_std_gb read from storage last-good; others are
    static-config for the Always Free envelope.
    """
    r = get_cache_redis()
    used_block_gb = 150
    used_obj_gb = 0
    try:
        last = await r.get("mon:last_good:storage")
        if last:
            try:
                sd = json.loads(last)
                if sd.get("block_vol"):
                    used_block_gb = int(sd["block_vol"]["used_bytes"] / 1024**3)
                if sd.get("object_storage"):
                    used_obj_gb = round(sd["object_storage"]["used_bytes"] / 1024**3, 1)
            except Exception:
                pass
    except Exception:
        pass

    return {
        "a1_ocpu":       {"used": 4,  "cap": 4,  "unit": "ocpu"},
        "a1_ram_gb":     {"used": 24, "cap": 24, "unit": "GB"},
        "block_vol_gb":  {"used": used_block_gb, "cap": 200, "unit": "GB"},
        "egress_tb":     {"used": 0.18, "cap": 10, "unit": "TB"},
        "object_std_gb": {"used": used_obj_gb, "cap": 20, "unit": "GB"},
    }
```

- [ ] **Step 4: Run tests**

```bash
cd backend && python -m pytest monitor/tests/collectors/test_cost.py -v
```

Expected: both tests `PASSED`.

- [ ] **Step 5: Commit**

```bash
git add backend/monitor/collectors/cost.py backend/monitor/tests/collectors/test_cost.py
git commit -m "[backend] AST-NN monitor: cost collector (OCI Budget API)

instance-principal signer hits Budget API for month_to_date/forecast/
budget/currency. Always-Free usage for 5 dimensions — 4 static
(OCPU/RAM/egress caps), 2 live-read from storage last-good
(block_vol_gb, object_std_gb). egress is a static stub for v1
(real egress needs OCI Usage API; defer).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 16: `backups` collector (OCI Object Storage list)

**Files:**
- Create: `backend/monitor/collectors/backups.py`
- Create: `backend/monitor/tests/collectors/test_backups.py`

- [ ] **Step 1: Write failing test**

Create `backend/monitor/tests/collectors/test_backups.py`:

```python
"""backups.collect() — list astral-backups bucket."""
from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest

from monitor.collectors import backups as bk_mod


def _obj(name, size, time_created):
    o = MagicMock()
    o.name = name
    o.size = size
    o.time_created = time_created
    return o


@pytest.mark.asyncio
async def test_collect_parses_recent_runs(monkeypatch):
    async def _list():
        return [
            _obj("pg_dump_20260420_030012.sql.gz", 2_050_000_000,
                 datetime(2026, 4, 20, 3, 0, 42, tzinfo=timezone.utc)),
            _obj("pg_dump_20260413_030005.sql.gz", 2_010_000_000,
                 datetime(2026, 4, 13, 3, 0, 38, tzinfo=timezone.utc)),
        ]

    monkeypatch.setattr(bk_mod, "_list_bucket", _list)
    monkeypatch.setattr(bk_mod, "_NOW", lambda: datetime(2026, 4, 21, 10, 0, 0, tzinfo=timezone.utc))

    block = await bk_mod.collect()
    assert block.bucket == "astral-backups"
    assert block.last_size_bytes == 2_050_000_000
    assert block.status == "ok"
    assert len(block.recent_runs) == 2
    assert block.retention_days == 56


@pytest.mark.asyncio
async def test_collect_marks_stale_when_no_recent(monkeypatch):
    async def _list():
        return [_obj("pg_dump_20260301_030000.sql.gz", 1_000_000_000,
                     datetime(2026, 3, 1, 3, 0, 0, tzinfo=timezone.utc))]

    monkeypatch.setattr(bk_mod, "_list_bucket", _list)
    monkeypatch.setattr(bk_mod, "_NOW", lambda: datetime(2026, 4, 21, 10, 0, 0, tzinfo=timezone.utc))

    block = await bk_mod.collect()
    assert block.status == "stale"


@pytest.mark.asyncio
async def test_collect_empty_bucket_stale(monkeypatch):
    async def _list():
        return []

    monkeypatch.setattr(bk_mod, "_list_bucket", _list)
    monkeypatch.setattr(bk_mod, "_NOW", lambda: datetime(2026, 4, 21, 10, 0, 0, tzinfo=timezone.utc))

    block = await bk_mod.collect()
    assert block.status == "stale"
    assert block.last_pg_dump is None
```

- [ ] **Step 2: Run to verify fail**

```bash
cd backend && python -m pytest monitor/tests/collectors/test_backups.py -v
```

Expected: `ModuleNotFoundError`.

- [ ] **Step 3: Implement `collectors/backups.py`**

Create `backend/monitor/collectors/backups.py`:

```python
"""backups collector — list the astral-backups bucket (AST-51).

Cron: weekly Sunday 03:00 UTC. next_run_in_s computed from current time.
status = 'ok' if a dump exists <=10d old, 'stale' otherwise.
"""
from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta, timezone

from monitor.schema import BackupRun, BackupsBlock

logger = logging.getLogger("monitor.backups")

_BUCKET = "astral-backups"
_RETENTION_DAYS = 56
_STALE_AFTER_DAYS = 10


def _NOW() -> datetime:
    return datetime.now(timezone.utc)


async def collect() -> BackupsBlock:
    objects = await _list_bucket()
    objects = sorted(objects, key=lambda o: o.time_created, reverse=True)

    now = _NOW()

    recent_runs = [
        BackupRun(
            started=o.time_created,
            duration_s=0,
            size_bytes=int(o.size or 0),
            status="ok",
        )
        for o in objects[:10]
    ]

    if not objects:
        last_dump = None
        last_size = None
        status = "stale"
    else:
        last_dump = objects[0].time_created
        last_size = int(objects[0].size or 0)
        age_days = (now - last_dump).total_seconds() / 86400
        status = "ok" if age_days <= _STALE_AFTER_DAYS else "stale"

    return BackupsBlock(
        last_pg_dump=last_dump,
        last_size_bytes=last_size,
        status=status,
        next_run_in_s=_seconds_until_next_sunday_3am(now),
        bucket=_BUCKET,
        retention_days=_RETENTION_DAYS,
        recent_runs=recent_runs,
    )


def _seconds_until_next_sunday_3am(now: datetime) -> int:
    days_ahead = (6 - now.weekday()) % 7
    target = (now + timedelta(days=days_ahead)).replace(hour=3, minute=0, second=0, microsecond=0)
    if target <= now:
        target += timedelta(days=7)
    return int((target - now).total_seconds())


async def _list_bucket():
    def _sync():
        import oci
        signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
        client = oci.object_storage.ObjectStorageClient(config={}, signer=signer)
        ns = client.get_namespace().data
        out = client.list_objects(ns, _BUCKET, fields="name,size,timeCreated", limit=1000)
        return out.data.objects or []

    return await asyncio.to_thread(_sync)
```

- [ ] **Step 4: Run tests**

```bash
cd backend && python -m pytest monitor/tests/collectors/test_backups.py -v
```

Expected: all 3 tests `PASSED`.

- [ ] **Step 5: Commit**

```bash
git add backend/monitor/collectors/backups.py backend/monitor/tests/collectors/test_backups.py
git commit -m "[backend] AST-NN monitor: backups collector (OCI Object Storage list)

Lists astral-backups bucket objects, sorts by timeCreated desc,
emits BackupsBlock with last_pg_dump, status (ok if <=10d, stale
otherwise), next_run_in_s from AST-51 cron (Sunday 03:00 UTC),
10 most recent runs. retention_days pinned at 56 to match bucket
lifecycle.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 17: `nginx_access_sampler` + `requests` collector

**Files:**
- Modify: `backend/monitor/bg.py`
- Create: `backend/monitor/collectors/requests_.py`
- Create: `backend/monitor/tests/collectors/test_requests.py`

- [ ] **Step 1: Write failing tests**

Create `backend/monitor/tests/collectors/test_requests.py`:

```python
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
```

- [ ] **Step 2: Run to verify fail**

```bash
cd backend && python -m pytest monitor/tests/collectors/test_requests.py -v
```

Expected: import errors.

- [ ] **Step 3: Append nginx_access_sampler code to `bg.py`**

Append to `backend/monitor/bg.py` and replace the stub `async def nginx_access_sampler(): raise NotImplementedError`:

```python
# ─── nginx access log sampler ─────────────────────────────────────────

import re as _re
from datetime import datetime as _dt, timezone as _tz
from pathlib import Path as _Path

NGINX_ACCESS_PATH = _Path("/var/log/nginx/access.log")

_LOG_RE = _re.compile(
    r'^(?P<ip>\S+) - (?P<user>\S+) '
    r'\[(?P<ts>[^\]]+)\] '
    r'"(?P<method>\S+) (?P<path>\S+) (?P<proto>[^"]+)" '
    r'(?P<status>\d{3}) (?P<bytes>\d+|-) '
    r'rt=(?P<rt>[\d.]+) urt="(?P<urt>[^"]*)" '
    r'"(?P<referer>[^"]*)" "(?P<ua>[^"]*)"$'
)

_WINDOWS_S = {"1h": 3600, "6h": 21600, "24h": 86400, "7d": 604800, "30d": 2592000}


def _parse_log_line(line: str) -> dict | None:
    m = _LOG_RE.match(line.strip())
    if not m:
        return None
    try:
        ts = _dt.fromisoformat(m["ts"])
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=_tz.utc)
    except Exception:
        return None
    try:
        rt_ms = int(float(m["rt"]) * 1000)
    except Exception:
        rt_ms = 0
    return {
        "ts_ms": int(ts.timestamp() * 1000),
        "method": m["method"],
        "path": m["path"],
        "status": int(m["status"]),
        "rt_ms": rt_ms,
    }


def _compute_window(records: list[dict], window: str) -> dict:
    status_codes = {"2xx": 0, "3xx": 0, "4xx": 0, "5xx": 0}
    by_path: dict[tuple[str, str], list[int]] = {}
    bucket_ms = max(60_000, _WINDOWS_S[window] * 1000 // 60)
    series_rps_buckets: dict[int, int] = {}
    series_p95_buckets: dict[int, list[int]] = {}

    for r in records:
        s = r["status"]
        if   200 <= s < 300: status_codes["2xx"] += 1
        elif 300 <= s < 400: status_codes["3xx"] += 1
        elif 400 <= s < 500: status_codes["4xx"] += 1
        elif 500 <= s < 600: status_codes["5xx"] += 1
        by_path.setdefault((r["method"], r["path"]), []).append(r["rt_ms"])
        bucket = (r["ts_ms"] // bucket_ms) * bucket_ms
        series_rps_buckets[bucket] = series_rps_buckets.get(bucket, 0) + 1
        series_p95_buckets.setdefault(bucket, []).append(r["rt_ms"])

    series_rps = [[b, series_rps_buckets[b] / (bucket_ms / 1000)] for b in sorted(series_rps_buckets)]
    series_p95 = [[b, _pct(series_p95_buckets[b], 95)] for b in sorted(series_p95_buckets)]

    slowest = []
    for (method, path), rts in by_path.items():
        slowest.append({
            "method": method, "path": path,
            "p50_ms": _pct(rts, 50),
            "p95_ms": _pct(rts, 95),
            "p99_ms": _pct(rts, 99),
            "count": len(rts),
        })
    slowest.sort(key=lambda r: r["p95_ms"], reverse=True)
    slowest = slowest[:10]

    return {
        "window": window,
        "series_rps": series_rps,
        "series_p95_ms": series_p95,
        "status_codes": status_codes,
        "slowest": slowest,
    }


def _pct(values: list[int], p: int) -> int:
    if not values:
        return 0
    xs = sorted(values)
    k = int(len(xs) * p / 100)
    return xs[min(k, len(xs) - 1)]


async def nginx_access_sampler() -> None:
    """Every 60s: tail access.log, compute all 5 windows, write NGINX_WINDOW_CACHE."""
    while True:
        try:
            if not NGINX_ACCESS_PATH.exists():
                await asyncio.sleep(60)
                continue
            from collections import deque as _deque
            tail_buf: Deque[str] = _deque(maxlen=100_000)
            with NGINX_ACCESS_PATH.open("r", errors="replace") as fh:
                for line in fh:
                    tail_buf.append(line)

            now_ms = int(_dt.now(_tz.utc).timestamp() * 1000)
            all_records = []
            for line in tail_buf:
                rec = _parse_log_line(line)
                if rec is not None:
                    all_records.append(rec)

            for w, seconds in _WINDOWS_S.items():
                cutoff = now_ms - seconds * 1000
                window_records = [r for r in all_records if r["ts_ms"] >= cutoff]
                NGINX_WINDOW_CACHE[w] = _compute_window(window_records, w)
        except Exception as e:
            logger.warning("nginx_access_sampler failed: %s", e)
        await asyncio.sleep(60)
```

- [ ] **Step 4: Implement `collectors/requests_.py`**

Create `backend/monitor/collectors/requests_.py`:

```python
"""requests collector — reads NGINX_WINDOW_CACHE populated by nginx_access_sampler."""
from __future__ import annotations

from monitor.bg import NGINX_WINDOW_CACHE
from monitor.schema import RequestsBlock


async def collect(window: str = "6h") -> RequestsBlock:
    cached = NGINX_WINDOW_CACHE.get(window)
    if cached is None:
        return RequestsBlock(
            window=window,
            series_rps=[], series_p95_ms=[],
            status_codes={"2xx": 0, "3xx": 0, "4xx": 0, "5xx": 0},
            slowest=[],
        )
    return RequestsBlock.model_validate(cached)
```

- [ ] **Step 5: Run tests**

```bash
cd backend && python -m pytest monitor/tests/collectors/test_requests.py -v
```

Expected: all 5 tests `PASSED`.

- [ ] **Step 6: Commit**

```bash
git add backend/monitor/bg.py backend/monitor/collectors/requests_.py backend/monitor/tests/collectors/test_requests.py
git commit -m "[backend] AST-NN monitor: nginx_access_sampler + requests collector

_parse_log_line matches the astral log_format (rt=X urt=Y);
_compute_window aggregates into status_codes + RPS/p95 series
(60 buckets per window) + top-10 slowest by p95. sampler runs every
60s, precomputes all 5 windows into NGINX_WINDOW_CACHE. collect()
looks up the window in cache — fast, zero disk I/O on request path.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 6 — log_tailer + /metrics wiring

### Task 18: `log_tailer` bg task

**Files:**
- Modify: `backend/monitor/bg.py`

- [ ] **Step 1: Replace the log_tailer stub in `bg.py`**

Find `async def log_tailer() -> None: raise NotImplementedError` and replace with:

```python
# ─── log tailer ────────────────────────────────────────────────────────

_LOG_LEVEL_RE = _re.compile(r"\b(DEBUG|INFO|WARN|ERROR)\b", _re.IGNORECASE)
_REDACT_RES = [
    _re.compile(r"(Authorization:\s*[^\s]+)", _re.IGNORECASE),
    _re.compile(r"(Cookie:\s*[^\s]+)", _re.IGNORECASE),
    _re.compile(r"(token=[^&\s]+)", _re.IGNORECASE),
]


def _redact(msg: str) -> str:
    for r in _REDACT_RES:
        msg = r.sub(r"\1=REDACTED", msg)
    return msg


def _classify_level(msg: str, svc: str, status: int | None = None) -> str:
    if svc == "nginx" and status is not None:
        if status >= 500: return "error"
        if status >= 400: return "warn"
        return "info"
    m = _LOG_LEVEL_RE.search(msg)
    if m:
        return m.group(1).lower()
    return "info"


async def _follow_one(client, container, svc: str) -> None:
    """Follow a single container forever. Lines go to LOG_DEQUE."""
    def _iter():
        return container.logs(stream=True, follow=True, tail=0, timestamps=True)

    it = await asyncio.to_thread(_iter)
    while True:
        try:
            chunk = await asyncio.to_thread(next, it, None)
        except StopIteration:
            return
        if chunk is None:
            return
        try:
            line = chunk.decode("utf-8", errors="replace").rstrip("\n")
        except Exception:
            continue
        ts_str, _, rest = line.partition(" ")
        try:
            ts = _dt.fromisoformat(ts_str.replace("Z", "+00:00"))
        except Exception:
            ts = _dt.now(_tz.utc)
        msg = _redact(rest)
        lvl = _classify_level(msg, svc)
        LOG_DEQUE.append({"ts": ts, "svc": svc, "lvl": lvl, "msg": msg[:500]})


async def log_tailer() -> None:
    """Spin one _follow_one coroutine per compose service. Reattach on restart."""
    import docker

    client = docker.from_env()
    followers: dict[str, asyncio.Task] = {}

    while True:
        containers = await asyncio.to_thread(
            client.containers.list,
            all=True,
            filters={"label": "com.docker.compose.project=backend"},
        )
        by_svc = {
            c.labels.get("com.docker.compose.service"): c
            for c in containers
            if c.labels.get("com.docker.compose.service")
        }
        for svc, c in by_svc.items():
            t = followers.get(svc)
            if t is None or t.done():
                followers[svc] = asyncio.create_task(_follow_one(client, c, svc))
        await asyncio.sleep(30)
```

- [ ] **Step 2: No new unit tests**

Per spec §5: docker-py's follow=True generator is brittle to mock. Verified via smoke test in Task 22.

- [ ] **Step 3: Run full suite to confirm no regression**

```bash
cd backend && python -m pytest monitor/tests/ -v
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add backend/monitor/bg.py
git commit -m "[backend] AST-NN monitor: log_tailer bg task

One _follow_one coroutine per compose service, reading container
logs with timestamps + follow. Parses leading RFC3339 ts; infers
level from body (app services) or HTTP status (nginx). Redacts
Authorization/Cookie/token=. Appends to LOG_DEQUE (maxlen=500).
Reattach loop scans every 30s for new/restarted containers and
spins fresh followers on demand.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 19: `/metrics` endpoint + lifespan wiring

**Files:**
- Modify: `backend/monitor/main.py`
- Create: `backend/monitor/tests/test_metrics_endpoint.py`

- [ ] **Step 1: Write the failing test**

Create `backend/monitor/tests/test_metrics_endpoint.py`:

```python
"""Integration: GET /metrics aggregates all collectors, degrades gracefully."""
import pytest
from httpx import AsyncClient, ASGITransport


@pytest.mark.asyncio
async def test_metrics_returns_schema_shape(monkeypatch):
    from monitor.collectors import (
        cost, services, requests_, arq, storage, backups, cert, logs,
    )

    async def _cost():
        from monitor.schema import CostBlock, AlwaysFree, CapUsage
        return CostBlock(
            currency="USD", month_to_date=0.0, forecast=0.0, budget=1.0, last_alert=None,
            always_free=AlwaysFree(
                a1_ocpu=CapUsage(used=4, cap=4, unit="ocpu"),
                a1_ram_gb=CapUsage(used=24, cap=24, unit="GB"),
                block_vol_gb=CapUsage(used=150, cap=200, unit="GB"),
                egress_tb=CapUsage(used=0.1, cap=10, unit="TB"),
                object_std_gb=CapUsage(used=1, cap=20, unit="GB"),
            ),
        )

    monkeypatch.setattr(cost, "collect", _cost)

    async def _svc():
        return []

    monkeypatch.setattr(services, "collect", _svc)

    async def _req(window="6h"):
        from monitor.schema import RequestsBlock
        return RequestsBlock(
            window=window, series_rps=[], series_p95_ms=[],
            status_codes={"2xx": 0, "3xx": 0, "4xx": 0, "5xx": 0}, slowest=[],
        )

    monkeypatch.setattr(requests_, "collect", _req)

    async def _arq():
        from monitor.schema import ArqBlock
        return ArqBlock(
            queue_depth=0, in_flight=0, workers=3,
            completed_24h=0, failed_24h=0,
            active=[], recent_completed=[], recent_failed=[],
        )

    monkeypatch.setattr(arq, "collect", _arq)

    async def _sto():
        from monitor.schema import StorageBlock, StorageTrend
        return StorageBlock(
            postgres_bytes=None, media_bytes=None, block_vol=None, object_storage=None,
            trend_7d=StorageTrend(postgres=[0], media=[0], block_free=[0], object_used=[0]),
        )

    monkeypatch.setattr(storage, "collect", _sto)

    async def _bk():
        from monitor.schema import BackupsBlock
        return BackupsBlock(
            last_pg_dump=None, last_size_bytes=None, status="stale",
            next_run_in_s=3600, bucket="astral-backups",
            retention_days=56, recent_runs=[],
        )

    monkeypatch.setattr(backups, "collect", _bk)

    async def _ct():
        from monitor.schema import CertBlock, CertRenew
        return CertBlock(
            domain="astral-reader.duckdns.org", issuer=None,
            not_before=None, not_after=None, days_left=None,
            last_renew=CertRenew(at=None, status="failed"),
        )

    monkeypatch.setattr(cert, "collect", _ct)

    async def _lg(limit=100, svc=None, q=None):
        return []

    monkeypatch.setattr(logs, "collect", _lg)

    from monitor.main import app

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        resp = await c.get("/metrics?range=6h")
    assert resp.status_code == 200
    body = resp.json()
    for key in (
        "schema_version", "generated_at", "cost", "services", "requests",
        "arq", "storage", "backups", "cert", "logs",
    ):
        assert key in body
    assert body["cost"]["budget"] == 1.0
```

- [ ] **Step 2: Run to verify fail**

```bash
cd backend && python -m pytest monitor/tests/test_metrics_endpoint.py -v
```

Expected: endpoint not defined.

- [ ] **Step 3: Rewrite `monitor/main.py`**

Replace `backend/monitor/main.py` with:

```python
"""Astral OCI monitor — FastAPI entrypoint.

Routes:
  GET /healthz                  compose liveness probe
  GET /                         dashboard HTML
  GET /static/*                 static assets
  GET /metrics?range=6h         full aggregate
  GET /metrics/service/{name}   single ServiceBlock
  GET /metrics/logs/stream      Phase 2 — 501 for v1

Bg tasks started in lifespan: docker_sampler, log_tailer,
nginx_access_sampler (see monitor.bg).
"""
from __future__ import annotations

import asyncio
import logging
import os
import subprocess
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from functools import partial
from pathlib import Path

import redis.asyncio as aioredis
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from monitor import bg, cache
from monitor.collectors import arq, backups, cert, cost, logs as logs_coll
from monitor.collectors import requests_ as requests_coll
from monitor.collectors import services as services_coll
from monitor.collectors import storage
from monitor.schema import MetricsResponse

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
logger = logging.getLogger("monitor")

_STATIC_DIR = Path(__file__).parent / "static"
_REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379/0")
_DB_URL = os.getenv("DATABASE_URL", "postgresql+asyncpg://astral:astral@postgres:5432/astral")


@asynccontextmanager
async def lifespan(_app: FastAPI):
    redis = aioredis.from_url(_REDIS_URL, decode_responses=True, socket_connect_timeout=2)
    cache.set_redis(redis)

    import asyncpg
    pg_dsn = _DB_URL.replace("postgresql+asyncpg://", "postgresql://")
    try:
        pg_pool = await asyncpg.create_pool(pg_dsn, min_size=1, max_size=2, timeout=3)
        storage.set_pg_pool(pg_pool)
    except Exception as e:
        logger.warning("monitor pg pool failed: %s", e)
        pg_pool = None

    tasks = [
        asyncio.create_task(bg.supervise(bg.docker_sampler, "docker_sampler")),
        asyncio.create_task(bg.supervise(bg.log_tailer, "log_tailer")),
        asyncio.create_task(bg.supervise(bg.nginx_access_sampler, "nginx_access_sampler")),
    ]
    logger.info("monitor started: 3 bg tasks, redis=%s", _REDIS_URL)

    try:
        yield
    finally:
        for t in tasks:
            t.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        await redis.aclose()
        if pg_pool is not None:
            await pg_pool.close()


app = FastAPI(title="astral-monitor", docs_url=None, redoc_url=None, lifespan=lifespan)
app.mount("/static", StaticFiles(directory=_STATIC_DIR), name="static")


@app.get("/healthz")
async def healthz() -> JSONResponse:
    return JSONResponse({"status": "ok"})


@app.get("/")
async def index() -> FileResponse:
    return FileResponse(_STATIC_DIR / "index.html", media_type="text/html")


@app.get("/metrics")
async def metrics(range: str = Query("6h", pattern="^(1h|6h|24h|7d|30d)$")) -> JSONResponse:
    redis = cache.get_cache_redis_or_none()
    collectors = [
        ("cost", cost.collect),
        ("services", services_coll.collect),
        ("requests", partial(requests_coll.collect, range)),
        ("arq", arq.collect),
        ("storage", storage.collect),
        ("backups", backups.collect),
        ("cert", cert.collect),
        ("logs", partial(logs_coll.collect, 100)),
    ]
    results = await asyncio.gather(
        *[cache.safe(c, name, redis=redis, timeout=2.0, fallback=None)
          for name, c in collectors],
    )
    payload: dict = {
        "schema_version": "1.0.0",
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "build": _build_sha(),
        "tenancy_ocid": os.getenv("OCI_TENANCY_OCID", "unknown"),
        "region": os.getenv("OCI_REGION", "unknown"),
        "instance_ocid": os.getenv("OCI_INSTANCE_OCID", "unknown"),
    }
    for (name, _), (data, meta) in zip(collectors, results):
        if data is None and name in ("services", "logs"):
            data = []
        payload[name] = _serialize(data)
        if meta is not None:
            payload[f"{name}_meta"] = meta

    validated = MetricsResponse.model_validate(payload)
    return JSONResponse(validated.model_dump(mode="json", by_alias=True))


@app.get("/metrics/service/{name}")
async def metrics_service(name: str) -> JSONResponse:
    entry = bg.SERVICE_CACHE.get(name)
    if not entry:
        raise HTTPException(status_code=404, detail=f"unknown service: {name}")
    from monitor.schema import ServiceBlock
    block = ServiceBlock.model_validate(entry)
    return JSONResponse(block.model_dump(mode="json"))


@app.get("/metrics/logs/stream")
async def metrics_logs_stream() -> JSONResponse:
    raise HTTPException(status_code=501, detail="log stream is a phase-2 feature")


def _serialize(data):
    if data is None:
        return None
    if hasattr(data, "model_dump"):
        return data.model_dump(mode="json", by_alias=True)
    if isinstance(data, list):
        return [_serialize(d) for d in data]
    return data


def _build_sha() -> str:
    if sha := os.getenv("MONITOR_BUILD_SHA"):
        return sha[:7]
    try:
        out = subprocess.run(
            ["git", "-C", str(Path(__file__).resolve().parents[2]),
             "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, timeout=1,
        )
        return out.stdout.strip() or "unknown"
    except Exception:
        return "unknown"
```

- [ ] **Step 4: Run full test suite**

```bash
cd backend && python -m pytest monitor/tests/ -v
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add backend/monitor/main.py backend/monitor/tests/test_metrics_endpoint.py
git commit -m "[backend] AST-NN monitor: /metrics endpoint + lifespan bg task wiring

Lifespan opens redis + asyncpg pools, spins supervise()-wrapped
docker_sampler, log_tailer, nginx_access_sampler. GET /metrics fans
out to 8 collectors via asyncio.gather, each wrapped in safe()
(2s timeout + last-good fallback + degraded-meta sidecar). Payload
validated through MetricsResponse on the way out. GET /metrics/
service/{name} serves a single ServiceBlock from in-proc cache for
per-card refresh. /metrics/logs/stream returns 501 for v1.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 7 — UI wiring

### Task 20: Patch `static/index.html`

**Files:**
- Modify: `backend/monitor/static/index.html`

- [ ] **Step 1: Replace `genData()`**

Locate the existing `function genData(range){...}` block (around line 1151) and replace the entire function with:

```js
async function genData(range){
  const resp = await fetch('/metrics?range=' + encodeURIComponent(range), {credentials: 'include'});
  if(!resp.ok){
    throw new Error('metrics fetch failed: ' + resp.status);
  }
  return await resp.json();
}
```

- [ ] **Step 2: Replace `refreshService(name)`**

Locate `function refreshService(name){...}` (around line 1466) and replace the body:

```js
async function refreshService(name){
  try {
    const resp = await fetch('/metrics/service/' + encodeURIComponent(name), {credentials: 'include'});
    if(!resp.ok) throw new Error(resp.status);
    const block = await resp.json();
    const i = STATE.data.services.findIndex(s => s.name === name);
    if(i >= 0){ STATE.data.services[i] = block; }
    renderServices();
    toast('refreshed  ' + name);
  } catch(e){
    toast('refresh failed  ' + name);
    console.error('refreshService', name, e);
  }
}
```

- [ ] **Step 3: Add `refreshAll()` and rewire all call sites**

Near the bottom, find:

```js
STATE.data = genData(STATE.range);
renderAll();
```

Replace with:

```js
async function refreshAll(){
  try {
    STATE.data = await genData(STATE.range);
    renderAll();
  } catch(e){
    console.error('refreshAll failed', e);
    toast('metrics unreachable');
  }
}

refreshAll();
```

Find the auto-refresh setInterval block (around line 1750), replace its body with:

```js
if(on){
  STATE.autoTimer = setInterval(() => { refreshAll(); }, 30_000);
}
```

Find the manual-refresh click handler (around line 1727) — replace its assignment/render lines with:

```js
refreshAll();
```

Find the range-change handler (around line 1737) — keep the `STATE.range = ...` line but replace the subsequent regen/render lines with:

```js
refreshAll();
```

- [ ] **Step 4: Add `setDegradedDot` helper and wire it in each `renderX()`**

Near the top of the `<script>` block (after the STATE declaration), add:

```js
function setDegradedDot(sectionId, meta){
  const head = document.getElementById(sectionId);
  if(!head) return;
  const existing = head.querySelector('.degraded-dot');
  if(!meta || !meta.degraded){
    if(existing) existing.remove();
    return;
  }
  if(existing) return;
  const dot = document.createElement('span');
  dot.className = 'degraded-dot';
  dot.title = meta.reason + (meta.last_good ? '  last good ' + meta.last_good : '');
  dot.innerHTML = '&bull;';
  dot.style.cssText = 'color:var(--warning);margin-left:8px;font-size:18px;line-height:0;cursor:help;';
  head.appendChild(dot);
}
```

Find each `<div class="section-head">...</div>` tag for the 8 sections (Cost, Services, Requests, ARQ, Storage, Backups, Cert, Logs). Give each a unique id: `sec-cost`, `sec-services`, `sec-requests`, `sec-arq`, `sec-storage`, `sec-backups`, `sec-cert`, `sec-logs`.

At the start of each `renderX()` function (renderServices, renderRequests, renderArq, renderStorage, renderBackups, renderLogs, and the inline cost/cert renderers in `renderAll`), add:

```js
setDegradedDot('sec-<name>', STATE.data.<name>_meta);
```

(e.g. `setDegradedDot('sec-services', STATE.data.services_meta);`)

- [ ] **Step 5: Commit**

```bash
git add backend/monitor/static/index.html
git commit -m "[backend] AST-NN monitor: wire Dashboard.html to real /metrics

Three surgical JS edits per spec §2.7:
1. genData(range) fetches /metrics instead of mocking.
2. refreshService(name) fetches /metrics/service/{name}.
3. refreshAll() wraps genData+renderAll with try/catch + toast;
   used by initial load, auto-refresh, manual refresh, range change.

setDegradedDot() helper added to surface *_meta.degraded as amber
dots on section headers. All other UI behavior preserved verbatim.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 8 — Storage trend + deploy

### Task 21: Hourly storage trend hoister

**Files:**
- Modify: `backend/monitor/bg.py`
- Modify: `backend/monitor/main.py`

- [ ] **Step 1: Append `storage_trend_hoister` to `bg.py`**

Append at bottom of `backend/monitor/bg.py`:

```python
# ─── storage trend hoister ────────────────────────────────────────────

async def storage_trend_hoister() -> None:
    """Every hour, sample storage into Redis ZSETs so the UI's storage
    sparklines have 7d of history."""
    from monitor.collectors import storage
    from monitor.cache import get_cache_redis_or_none
    import time as _time

    while True:
        try:
            r = get_cache_redis_or_none()
            block = await storage.collect()
            now_ms = int(_time.time() * 1000)

            async def _push(key, val):
                if val is None or r is None:
                    return
                await r.zadd(f"mon:sparkline:storage:{key}", {str(int(val)): now_ms})
                await r.zremrangebyscore(
                    f"mon:sparkline:storage:{key}", 0, now_ms - 7 * 24 * 3600 * 1000,
                )

            await _push("postgres", block.postgres_bytes)
            await _push("media", block.media_bytes)
            await _push("block_free", block.block_vol.free_bytes if block.block_vol else None)
            await _push("object_used", block.object_storage.used_bytes if block.object_storage else None)
        except Exception as e:
            logger.warning("storage_trend_hoister failed: %s", e)
        await asyncio.sleep(3600)
```

- [ ] **Step 2: Register it in `main.py` lifespan**

In `backend/monitor/main.py`, inside `lifespan()`, extend the `tasks = [...]` list with:

```python
asyncio.create_task(bg.supervise(bg.storage_trend_hoister, "storage_trend_hoister")),
```

- [ ] **Step 3: Run full suite**

```bash
cd backend && python -m pytest monitor/tests/ -v
```

Expected: all tests still pass.

- [ ] **Step 4: Commit**

```bash
git add backend/monitor/bg.py backend/monitor/main.py
git commit -m "[backend] AST-NN monitor: hourly storage trend hoister

Fourth bg task supervise-wrapped; samples storage.collect() every
hour and writes postgres/media/block_free/object_used into
mon:sparkline:storage:* ZSETs (7d retention). Steady state: 672
entries × 4 series = ~12 KB Redis footprint.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 22: Deploy to A1 + smoke + PR

**Files:** `CHANGELOG.md` + runbook.

- [ ] **Step 1: On the A1, create the htpasswd**

SSH to the A1:

```bash
ssh ubuntu@<a1-ip>
cd /home/ubuntu/astral/backend
sudo apt install -y apache2-utils
htpasswd -c -B nginx/htpasswd astral
chmod 0640 nginx/htpasswd
```

- [ ] **Step 2: Append new env vars to `.env.oci` on the A1**

```bash
cd /home/ubuntu/astral
[ -z "$(grep '^OCI_BUDGET_OCID=' backend/.env.oci)" ] && echo 'OCI_BUDGET_OCID=<paste-budget-ocid>' >> backend/.env.oci
[ -z "$(grep '^OCI_TENANCY_OCID=' backend/.env.oci)" ] && echo "OCI_TENANCY_OCID=$(oci iam tenancy get | jq -r .data.id)" >> backend/.env.oci
[ -z "$(grep '^OCI_INSTANCE_OCID=' backend/.env.oci)" ] && echo "OCI_INSTANCE_OCID=$(curl -s -H 'Authorization: Bearer Oracle' http://169.254.169.254/opc/v2/instance/id)" >> backend/.env.oci
[ -z "$(grep '^OCI_REGION=' backend/.env.oci)" ] && echo 'OCI_REGION=us-sanjose-1' >> backend/.env.oci
chmod 0600 backend/.env.oci
```

Fill in `<paste-budget-ocid>` from the OCI Console → Governance → Budgets → (your $1 budget) → OCID.

- [ ] **Step 3: Pull the feature branch + build + bring up**

```bash
cd /home/ubuntu/astral
git fetch origin
git checkout feature/ast-NN-oci-monitor-dashboard
cd backend
docker compose build astral_monitor
docker compose up -d astral_monitor
docker compose restart nginx
sleep 5
docker compose ps astral_monitor
```

Expected: `astral_monitor` is Up + healthy.

- [ ] **Step 4: Smoke-verify each section from your laptop**

Run (fill in `<pw>` with the htpasswd password set in Step 1):

```bash
curl -s -u astral:<pw> https://astral-reader.duckdns.org/metrics | jq '. | keys'
# expected: ["arq","backups","build","cert","cost","generated_at","instance_ocid","logs","region","requests","schema_version","services","storage","tenancy_ocid"]

curl -s -u astral:<pw> https://astral-reader.duckdns.org/metrics | jq '.cost.budget'
# expected: 1

curl -s -u astral:<pw> https://astral-reader.duckdns.org/metrics | jq '.services | length'
# expected: 6 (allow 10s for docker_sampler to populate)

curl -s -u astral:<pw> https://astral-reader.duckdns.org/metrics | jq 'keys[] | select(endswith("_meta"))'
# expected: empty (no degraded sections)

curl -s -u astral:<pw> https://astral-reader.duckdns.org/metrics | jq '.cert.days_left'
# expected: > 0
```

- [ ] **Step 5: Visual check**

On iPhone Safari, visit `https://astral-reader.duckdns.org/monitor/` → Basic Auth prompt → dashboard loads. Confirm:
- No amber dots on section headers.
- Time-range buttons (1h/6h/24h/7d/30d) respond.
- Manual refresh button re-fetches.
- Log panel has recent lines.

Repeat on desktop Chrome at 1440×900.

- [ ] **Step 6: Induced-failure checks**

```bash
# on the A1:
docker compose stop redis
# wait 60s, curl /metrics, expect cost_meta / storage_meta / backups_meta with degraded: true
docker compose start redis
# wait 60s, curl /metrics, expect *_meta sidecars gone

docker compose restart fastapi
# from the dashboard, verify fastapi card shows STARTING, then UP
# verify log tail shows the restart lines
```

- [ ] **Step 7: Update `CHANGELOG.md`**

Add a new entry at the top of `CHANGELOG.md` under today's date (`## 2026-04-21`) in the Backend section:

```markdown
- **AST-NN** — OCI monitor dashboard: new `astral_monitor` service in the prod compose stack serves a pixel-locked dark-mode dashboard at `astral-reader.duckdns.org/monitor/` (Basic Auth). `/metrics` aggregates docker-compose service stats (docker_sampler), ARQ queue state, pg+media+block-vol+Object-Storage usage, OCI Budget API, LE cert expiry, nginx request metrics (1h/6h/24h/7d/30d), and a 500-line log tail — all behind a 2s `safe()` timeout so a single broken collector becomes a degraded amber-dot marker instead of a failed response. Total incremental OCI spend: $0. ([PR #NN](https://github.com/agenticCoder97/IosTestApp/pull/NN))
```

- [ ] **Step 8: Open the PR**

```bash
# laptop:
git push -u origin feature/ast-NN-oci-monitor-dashboard
gh pr create --base development --title "[backend] AST-NN OCI monitor dashboard" --body "## Summary
- New astral_monitor compose service serves a dark-mode dashboard at /monitor/ behind nginx Basic Auth.
- /metrics aggregates 8 collectors (cost/services/requests/arq/storage/backups/cert/logs) with safe() degraded fallbacks.
- Three bg samplers keep request-path latency <300 ms p95.

Fixes AST-NN.

## Test plan
- [x] Unit: pytest backend/monitor/tests/ — ~50 tests pass in <10s.
- [x] Smoke (A1): curl /metrics, visit /monitor/ from iPhone + desktop, induce redis-down + fastapi-restart.
- [x] No OCI cost impact — same A1 instance, same 6 services + ~90 MB for monitor.

Design spec: docs/superpowers/specs/2026-04-21-oci-monitor-dashboard-design.md
Plan: docs/superpowers/plans/2026-04-21-oci-monitor-dashboard.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 9: After PR number is known, commit the CHANGELOG entry**

Fill in the PR number in `CHANGELOG.md`, then:

```bash
git add CHANGELOG.md
git commit -m "[backend] AST-NN changelog entry

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

## Task Summary

| # | Task | Files |
|---|---|---|
| 0 | Linear + branch | — |
| 1 | Package skeleton | 4× __init__.py |
| 2 | Copy handoff HTML verbatim | static/index.html |
| 3 | Skeleton FastAPI app | main.py, test_main.py, conftest.py |
| 4 | Dockerfile.monitor | Dockerfile.monitor |
| 5 | Compose astral_monitor + htpasswd gitignore | docker-compose.yml, .gitignore, placeholder htpasswd |
| 6 | Nginx /monitor + /metrics + access_log | nginx/nginx.conf |
| 7 | pydantic schema | schema.py, test_schema.py |
| 8 | cache + safe() | cache.py, 2 tests, requirements-test.txt |
| 9 | bg supervise() + stubs | bg.py, test_bg_supervise.py |
| 10 | docker_sampler + services | bg.py, collectors/services.py, 2 tests |
| 11 | cert collector | collectors/cert.py + test + fixture |
| 12 | arq collector | collectors/arq.py + test |
| 13 | storage collector | collectors/storage.py + test |
| 14 | logs collector | collectors/logs.py + test |
| 15 | cost collector | collectors/cost.py + test |
| 16 | backups collector | collectors/backups.py + test |
| 17 | nginx_access_sampler + requests | bg.py, collectors/requests_.py + test |
| 18 | log_tailer | bg.py |
| 19 | /metrics endpoint + lifespan | main.py, test_metrics_endpoint.py |
| 20 | UI wiring | static/index.html |
| 21 | Storage trend hoister | bg.py, main.py |
| 22 | A1 deploy + smoke + PR | CHANGELOG.md |

23 tasks total (0–22). ~50 unit tests. Single PR to `development`.
