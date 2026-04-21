# OCI Monitor Dashboard — Design

**Date**: 2026-04-21
**Status**: Approved, ready for implementation plan
**Linear**: new AST issue to be filed under project Astral before implementation starts

## Summary

A single-page, dark-mode operational dashboard for the Astral backend running on
OCI Always-Free. Surfaces everything the OCI Console hides from a dev
perspective: docker-compose service health, request/latency metrics, ARQ worker
queue, storage footprints, pg_dump backups, TLS cert expiry, and a live log
stream — plus a cost tripwire that makes $0/month drift immediately visible.

Tuned for **one developer**, read on iPhone + desktop. Dense over spacious, dark
over light, terminal-adjacent over corporate. Pixel-locked to the handoff at
`/Users/nicknetraganti/Downloads/design_handoff_oci_monitor/Dashboard.html` —
all colors, spacing, and layout come from that file.

## Goals / Non-goals

**In scope (v1)**
- Full 10-section dashboard, all sections real-data from day one.
- New `astral_monitor` docker-compose service on the A1 VM, isolated from `fastapi`.
- Nginx Basic Auth gate; one htpasswd user.
- Auto-refresh (30s default), manual refresh (`r`), per-service refresh, time-range selector.
- Degraded-mode handling: one broken subsystem does not break the whole dashboard.

**Out of scope (not v1)**
- SSE log streaming (`/metrics/logs/stream`) — stubbed, ship polling only.
- Nginx-log parser for request metrics beyond a simple middleware counter.
- Light mode.
- Any auth beyond Basic Auth (no SSO, no MFA).
- Alerting / paging (the OCI budget alert covers the one real cost risk).
- Historical data beyond 7d sparklines.

## Constraints

- **$0/month OCI spend** — must stay inside Always Free envelope. Incremental
  cost of the monitor must be zero (compute, storage, egress).
- **No new SaaS dependency** — no Datadog, Grafana Cloud, Sentry, log aggregator.
- **Isolation from prod API** — the monitor cannot crash or slow down `fastapi`.
  Separate container, separate failure domain.
- **Solo-dev maintenance budget** — no premature testing infrastructure; no
  frameworks where a file will do.

---

## 1. Architecture

New service in the existing `backend/docker-compose.yml`. No new repo, no new
host, no new subdomain.

### Topology

```
iPhone/Mac ──HTTPS──▶ nginx ─┬─ /api/*           ──▶ fastapi  :8000  (unchanged)
                              ├─ /static/*         ──▶ astral_media volume (unchanged)
                              └─ /monitor/, /metrics*  ──▶ astral_monitor :8001  (NEW)
                                 ↑ auth_basic gate

astral_monitor ─▶ postgres (existing astral_net)
                ─▶ redis    (existing astral_net)
                ─▶ /var/run/docker.sock   (ro bind mount)
                ─▶ /etc/letsencrypt        (ro volume mount)
                ─▶ /mnt/astral-media       (ro bind mount, for du/df)
                ─▶ OCI IMDS v2             (instance-principal budget API)
```

### Repository layout

```
backend/
├── docker-compose.yml          # + astral_monitor service block
├── Dockerfile.monitor          # new; python:3.11-slim base
├── nginx/
│   ├── nginx.conf              # + /monitor/ + /metrics location blocks, auth_basic
│   └── htpasswd                # new, gitignored; A1-side only
└── monitor/                    # new top-level dir, parallel to app/
    ├── main.py                 # FastAPI app, routes, lifespan
    ├── schema.py               # pydantic v2 models for /metrics contract
    ├── cache.py                # @cached decorator, Redis + in-proc layers
    ├── bg.py                   # docker_sampler, log_tailer, nginx_access_sampler
    ├── collectors/
    │   ├── cost.py
    │   ├── services.py
    │   ├── requests_.py
    │   ├── arq.py
    │   ├── storage.py
    │   ├── backups.py
    │   ├── cert.py
    │   └── logs.py
    ├── static/
    │   └── index.html          # handoff Dashboard.html with genData() swapped for fetch
    └── tests/
        ├── conftest.py
        ├── test_schema.py
        └── test_collectors/
```

### docker-compose.yml addition (sketch)

```yaml
astral_monitor:
  build: { context: ., dockerfile: Dockerfile.monitor }
  env_file: .env.oci
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock:ro
    - letsencrypt:/etc/letsencrypt:ro
    - astral_media:/mnt/astral-media:ro
  depends_on:
    postgres: { condition: service_healthy }
    redis:    { condition: service_started }
  healthcheck:
    test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8001/healthz')"]
    interval: 30s
    timeout: 3s
    retries: 3
  restart: unless-stopped
  networks: [astral_net]
```

No host ports exposed; only nginx reaches it on `astral_net`.

### nginx.conf addition

```nginx
# inside the existing https server block for astral-reader.duckdns.org
location = /monitor { return 301 /monitor/; }
location /monitor/ {
    auth_basic "astral";
    auth_basic_user_file /etc/nginx/htpasswd;
    proxy_pass http://astral_monitor:8001/;
}
location /metrics {
    auth_basic "astral";
    auth_basic_user_file /etc/nginx/htpasswd;
    proxy_pass http://astral_monitor:8001;
}
```

`htpasswd` is created once on the A1 via `htpasswd -c /etc/nginx/htpasswd astral`
and mounted into the nginx container at the same path.

### Cost envelope

- Image: `python:3.11-slim` + FastAPI + asyncpg + redis-py + docker + oci + cryptography ≈ 180 MB.
- RAM idle: ~90 MB; active poll: ~150 MB. Within A1 24 GB envelope.
- CPU: near zero; event loop mostly idle between bg ticks.
- Incremental egress: ~28 MB/day per device × 2 devices = 1.7 GB/mo. 0.017% of the 10 TB Always-Free egress.
- Incremental storage: 180 MB image + ~400 KB Redis sparklines. Zero to block-volume free space.

Net OCI spend: $0/month. Stays inside every Always Free cap.

---

## 2. Components

### 2.1 `schema.py` — the UI contract

Pydantic v2 models for every top-level key of `/metrics`, 1:1 with the JSON
schema comment block at the top of `Dashboard.html`. Collectors return
instances; FastAPI serializes; never hand-rolled dicts. Golden test against the
handoff's example JSON is the regression fence.

Top-level shape (keys required unless marked):

```
MetricsResponse:
  schema_version: str    # "1.0.0"
  generated_at:   datetime (UTC, ISO 8601 with Z)
  build:          str    # short git SHA of monitor container
  tenancy_ocid:   str
  region:         str
  instance_ocid:  str
  cost:           CostBlock
  services:       list[ServiceBlock]      # len == 6
  requests:       RequestsBlock
  arq:            ArqBlock
  storage:        StorageBlock
  backups:        BackupsBlock
  cert:           CertBlock
  logs:           list[LogLine]           # ≤ 500, newest last
  # sibling "*_meta" fields added per-block when degraded (optional)
```

### 2.2 `cache.py` — two-tier caching

Single `@cached(key, ttl, layer='redis'|'inproc')` decorator. Redis-backed keys
use the existing `app.cache.redis_pool` pattern (shared singleton, ArqRedis
pool, opened in lifespan). In-proc layer is a dict keyed by (func, args) with a
monotonic-clock expiry check.

Writes via `cache.set_last_good(name, data)` on every successful collector call,
keyed at `mon:last_good:{name}` with 24h TTL. Used by the `safe()` wrapper
(section 4) to serve stale data when a collector fails.

### 2.3 `bg.py` — long-lived background tasks

Three tasks started in the FastAPI `lifespan` context, each wrapped in a
`supervise(coro, name)` helper that catches exceptions, logs, applies
exponential backoff (10s → 30s → 60s cap), and relaunches. `CancelledError`
propagates normally on shutdown.

**`docker_sampler`** (10s cadence)
- `docker.from_env().containers.list(all=True, filters={'label': 'com.docker.compose.project=backend'})`
- For each of the 6 services, pull `.stats(stream=False)` + `.attrs['State']`.
- Push `{cpu_pct, mem_mb, status, health, uptime_s}` into the in-proc dict at `mon:svc:{name}`.
- Append `cpu_pct` to a per-service Redis ZSET `mon:sparkline:{name}` (score = epoch ms), trim entries older than 7d.

**`log_tailer`** (continuous)
- For each of the 6 services, run `containers.logs(stream=True, follow=True, tail=0, timestamps=True)` in a coroutine.
- Parse `ts | level | msg` (level via regex `(DEBUG|INFO|WARN|ERROR)`; default `info`).
- Redact `Authorization`, `Cookie`, and `token=\S+` patterns before append.
- Push into a single `collections.deque(maxlen=500)`.
- On `docker events → container:start`, reattach the per-container follower (handles restarts transparently).

**`nginx_access_sampler`** (60s cadence)
- Tails `/mnt/astral-media/nginx-access.log` (bind-mounted into nginx and monitor containers).
- Window: last 1h / 6h / 24h / 7d / 30d — pre-compute all five windows on every tick, cache at `mon:requests:{range}`.
- Emits `series_rps`, `series_p95_ms`, `status_codes`, and `slowest[]` (top-10 p95 by path).
- For v1: simple stdlib parsing of the default nginx log format; no deps added.

### 2.4 Collectors

One module per top-level key. Each exports `async def collect() -> BlockModel`.
All use `@cached(...)` — cadence below is the TTL, not the implementation
frequency (collectors are pull-only; only bg samplers push).

| Module | Data source | TTL | Degraded → |
|---|---|---|---|
| `cost.py` | OCI Budget API (`GetBudget`, `ListAlertRules`) via instance-principal signer; Always-Free usage inferred from config constants + `storage.py` values | 300s Redis | last-known + `reason: "oci api"` |
| `services.py` | Reads `bg.docker_sampler` dict | 0s (always current) | `[]` + `reason: "docker socket missing"` |
| `requests_.py` | Reads `bg.nginx_access_sampler` cache for the requested range | 60s in-proc | empty series + `reason: "log unreadable"` |
| `arq.py` | Redis `HGETALL arq:*`, `ZRANGE arq:queue`, `KEYS arq:result:*` | 15s in-proc | zeros + `reason: "redis unreachable"` |
| `storage.py` | `statvfs('/mnt/astral-media')`; `du -sb` subprocess for media dir; `SELECT pg_database_size(current_database())` on pg pool; OCI Object Storage `HeadBucket` on `astral-backups` | 120s Redis | zeros + `reason: str(e)` |
| `backups.py` | `oci os object list --bucket astral-backups`, parse `pg_dump_YYYYMMDD_HHMMSS.sql.gz`; `next_run_in_s` computed from the AST-51 cron schedule (weekly, Sunday 03:00 UTC) hardcoded in the collector | 300s Redis | `status: "stale"` + `reason: "oci api"` |
| `cert.py` | `cryptography.x509.load_pem_x509_certificate(/etc/letsencrypt/live/astral-reader.duckdns.org/fullchain.pem)`; `last_renew` from letsencrypt log mtime | 3600s in-proc | `days_left: null` + `reason: "cert unreadable"` |
| `logs.py` | Slices `bg.log_tailer.deque` with optional `?svc=` + `?q=` filters, default `limit=100` | 0s (deque) | `[]` if tailer down |

### 2.5 `main.py` — routes

```
GET /           → FileResponse(monitor/static/index.html)
GET /static/*   → StaticFiles mount (fonts later; v1 uses Google Fonts CDN)
GET /metrics    → fan out to all collectors via asyncio.gather, serialize MetricsResponse
GET /metrics/service/{name}   → single ServiceBlock, served from bg.docker_sampler cache
GET /metrics/logs/stream      → Phase 2; in v1 returns 501 Not Implemented
GET /healthz    → 200 if process alive (no downstream checks) — used by compose healthcheck
```

Aggregation uses `asyncio.gather(*[safe(c, name) for c, name in collectors])` so
one slow collector does not block the rest. Each is wrapped in
`asyncio.wait_for(timeout=2.0)`.

### 2.6 `Dockerfile.monitor`

```dockerfile
FROM python:3.11-slim
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir \
    fastapi==0.115.* uvicorn[standard]==0.32.* \
    asyncpg==0.30.* redis==5.2.* docker==7.1.* \
    oci==2.134.* cryptography==43.* python-dateutil==2.9.*
COPY monitor /app/monitor
WORKDIR /app
RUN useradd -r -u 1001 monitor && chown -R monitor /app
USER monitor
CMD ["uvicorn", "monitor.main:app", "--host", "0.0.0.0", "--port", "8001"]
```

Single-stage, no venv, ~180 MB. Non-root user (note: the docker socket bypasses
this — see section 4 security posture).

### 2.7 `static/index.html`

The handoff's `Dashboard.html`, verbatim, with three surgical edits:

1. Delete the body of `genData(range)` and replace with
   `async function genData(range){ const r = await fetch('/metrics?range='+range,{credentials:'include'}); if(!r.ok) throw new Error(r.status); return await r.json(); }`.
2. Per-service refresh: `async function refreshService(name){ const r = await fetch('/metrics/service/'+name,{credentials:'include'}); const block = await r.json(); const i = STATE.data.services.findIndex(s=>s.name===name); STATE.data.services[i] = block; renderServices(); }`.
3. All `renderX()` functions updated to also read `STATE.data[x + '_meta']` and
   render an amber dot + tooltip on the section header when
   `STATE.data[x + '_meta']?.degraded === true`.

Everything else (CSS, layout, keyboard shortcuts, toast, copy pills, time-range
selector, auto-refresh toggle) is untouched.

---

## 3. Data Flow & Caching

### Service lifespan

```
uvicorn start
  └─ FastAPI lifespan enter
      ├─ open_redis_pool()       (singleton, same pattern as app.cache.redis_pool)
      ├─ open_pg_pool(min=1, max=2)   (read-only workload)
      ├─ open_docker_client()    (verifies /var/run/docker.sock mount)
      └─ supervise(docker_sampler)
          supervise(log_tailer)
          supervise(nginx_access_sampler)
uvicorn serve
  └─ GET /metrics → asyncio.gather(collectors) → MetricsResponse
SIGTERM
  └─ lifespan exit
      ├─ cancel bg tasks, await with 2s grace
      └─ close pools, close docker client
```

### `GET /metrics?range=6h` lifecycle

Target: <300 ms p95 (so 30s auto-refresh never stacks).

```
asyncio.gather(
  safe(cost.collect, "cost"),
  safe(services.collect, "services"),
  safe(partial(requests_.collect, range), "requests"),
  safe(arq.collect, "arq"),
  safe(storage.collect, "storage"),
  safe(backups.collect, "backups"),
  safe(cert.collect, "cert"),
  safe(partial(logs.collect, limit=100), "logs"),
)
  → MetricsResponse.model_dump_json()   # ~8–12 KB gzipped
```

### Cache key table

| Key | Layer | TTL | Refreshed by |
|---|---|---|---|
| `mon:cost` | Redis | 300s | Request-path fetch (first miss after TTL) |
| `mon:storage` | Redis | 120s | Request-path fetch |
| `mon:backups` | Redis | 300s | Request-path fetch |
| `mon:sparkline:{svc}` | Redis ZSET | 7d (aged off on insert) | `docker_sampler` bg loop |
| `mon:sparkline:storage:{postgres\|media\|block_free\|object_used}` | Redis ZSET | 7d | Hourly bg tick |
| `mon:svc:{name}` | in-proc dict | 10s (overwrite) | `docker_sampler` |
| `mon:arq` | in-proc | 15s | Request-path fetch |
| `mon:requests:{range}` | in-proc | 60s | Request-path fetch (populated by `nginx_access_sampler`) |
| `mon:cert` | in-proc | 3600s | Request-path fetch |
| `mon:logs` | in-proc deque(500) | n/a | `log_tailer` stream |
| `mon:last_good:{name}` | Redis | 24h | `safe()` wrapper on every success |

Policy: expensive + slow-moving (OCI API, `du`, `pg_database_size`) → Redis so
the cache survives `docker compose restart astral_monitor`. Cheap + fast-moving
(docker stats, ARQ state, log buffer) → in-proc.

### Per-service refresh flow

UI click on the card's refresh icon →

```
spin icon 700ms
fetch('/metrics/service/fastapi')
  └─ monitor reads bg.docker_sampler's in-proc entry for `fastapi`
  └─ returns ServiceBlock
UI patches STATE.data.services[i], calls renderServices()
```

Round-trip <50 ms — feels instant, no full re-poll.

### Auto-refresh behavior

- Default ON, 30s interval (`STATE.auto = true`, stored in `localStorage`).
- Cache TTLs chosen so two consecutive 30s polls fall inside the slow caches
  (cost + storage + cert all hit Redis).
- When `document.hidden === true` (tab backgrounded), the interval is paused.
  Resumes + fires an immediate poll on `visibilitychange`. Saves egress on
  forgotten-open tabs.

### Growth control

- `docker_sampler` writes 8,640 entries/day/service × 6 = 51,840/day total.
- Every insert does `ZADD mon:sparkline:{svc} {ts} {cpu}` + `ZREMRANGEBYSCORE mon:sparkline:{svc} 0 (now-7d)`.
- Steady state: 60,480 entries × 6 = ~360 KB Redis footprint. Well under the
  128 MB `maxmemory` on the existing Redis service.

---

## 4. Error Handling & Degraded Modes

**Rule**: `/metrics` returns 200 with `degraded` markers as long as anything
succeeds. Only returns 500 if the monitor itself (pydantic serialization, core
FastAPI plumbing) is broken. A monitor that 500s when the system it monitors is
broken is useless.

### Per-collector envelope

Each block in the response gets an optional sibling when a failure occurred:

```json
{
  "cost": {...},                  // last-known or zero-struct
  "cost_meta": {
    "degraded": true,
    "reason": "oci budget api timeout",
    "last_good": "2026-04-21T09:12:03Z"
  },
  ...
}
```

The UI renders a small amber dot + tooltip on the section header when
`*_meta.degraded === true`. No cascading red banner — a broken ARQ section does
not make the cost card look alarming.

### `safe()` wrapper

```python
async def safe(coll, name, timeout=2.0):
    try:
        data = await asyncio.wait_for(coll(), timeout)
        await cache.set_last_good(name, data, ttl=86400)
        return data, None
    except asyncio.TimeoutError:
        last = await cache.get_last_good(name)
        return last or empty_block(name), {"degraded": True, "reason": "timeout", "last_good": last.generated_at if last else None}
    except Exception as e:
        last = await cache.get_last_good(name)
        logger.warning("collector %s failed: %s", name, e)
        return last or empty_block(name), {"degraded": True, "reason": str(e)[:80], "last_good": last.generated_at if last else None}
```

### Failure scenarios

| Failure | Monitor behavior | UI behavior |
|---|---|---|
| `/var/run/docker.sock` not mounted | `services` returns `[]`, `logs` returns `[]`, both blocks `degraded` | Grid empty + banner "monitor has no docker access — check compose mount" |
| OCI instance-principal token unavailable | `cost` + `backups` return last Redis cache, `*_meta.reason = "imds unreachable"` | Cost/backups cards render last-known + amber dot |
| Cert file unreadable | `cert.days_left = null`, `degraded` | Days-remaining shows `—`, amber dot |
| Redis down | In-proc caches keep serving; anything Redis-only (cost, storage, backups) returns `degraded` | Three amber dots |
| Postgres down | `storage.postgres_bytes = null` only; other blocks unaffected | One gauge shows `—` |
| `docker_sampler` task crashes | `supervise` wrapper restarts with backoff; `services` cache goes stale > 10s → `degraded` | Sparklines freeze, amber dot until recovery |
| `log_tailer` loses a container on restart | On `docker events → container:start`, follower auto-reconnects | Brief gap in logs, no UI error |
| Single collector raises, others fine | That block `degraded`, others clean | One amber dot, rest of dashboard accurate |

### Circuit breaker (OCI API only)

- 3 consecutive failures → open circuit for 5 min → serve last Redis value +
  `degraded: true`.
- After 5 min: single probe (half-open). Success resets the breaker; failure
  re-opens for 5 min.
- Rationale: the Budget API has a soft rate limit and we are nowhere near it,
  but this protects against an OCI-side outage turning into a log flood.

### Monitor self-errors

Distinguished from system-under-monitor errors.

- `GET /healthz` → 200 if the process is alive. No downstream checks. Powers
  compose healthcheck.
- Startup validation: if `/var/run/docker.sock` missing **and** env `PROD=true`
  → FATAL log + exit 1. Dev mode (`PROD=false`) tolerates it and reports
  `services: []` degraded.
- Pydantic serialization errors → bubble as 500 with traceback. These are
  monitor bugs and we want them loud.

### Security posture

- `docker.sock:ro` — **note**: Docker daemon does not honor `:ro` (API-level
  access = full control). The `:ro` is documentation. Compensating controls:
  - monitor container runs as non-root (`USER 1001` in Dockerfile),
  - no user-supplied input reaches docker API calls (no shell-out from `?svc=`
    param; params validated against an enum of the 6 known service names),
  - never executes untrusted code paths.
- `htpasswd`, `.env.oci` — both gitignored. Managed via A1 runbook, not repo.
- `/metrics` payload contains OCIDs + container IDs. Fine behind Basic Auth;
  would be sensitive if exposed. Nginx config asserts `auth_basic` on every
  location block that proxies to `astral_monitor`.
- Log payload: redact `Authorization:`, `Cookie:`, and `token=\S+` patterns in
  the log tailer before append to the deque. Single regex pass per line.

### Bg task supervision

```python
async def supervise(factory, name):
    backoff = 10
    while True:
        try:
            await factory()         # long-lived coroutine
            return                  # graceful exit
        except asyncio.CancelledError:
            raise                   # propagate on shutdown
        except Exception as e:
            logger.exception("bg task %s died: %s", name, e)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, 60)
```

Never lets a bg task silently die; never cascades a single-task failure into a
service-wide crash.

---

## 5. Testing

Match rigor to stakes. A monitor returning wrong numbers is mildly annoying,
not data loss — so we test heavily where it's cheap + high-signal, skip where
it is expensive + low-signal.

### What gets tests

| Layer | Coverage | Tooling |
|---|---|---|
| `schema.py` | Golden parse: load the handoff's example JSON, assert no `ValidationError`. Contract fence with the UI. | `pytest` |
| Each collector | Happy path + every degraded mode from section 4 (timeout, exception, empty response). ~5 per collector × 8 = ~40 tests. | `pytest-asyncio`, `unittest.mock` |
| `safe()` wrapper | 3 tests: success passes through, timeout → degraded, exception → degraded with last-known. | `pytest-asyncio` |
| `cache.py` | 2 tests: Redis roundtrip (fakeredis), in-proc TTL eviction. | `fakeredis` |
| `docker_sampler` | 1 test: given mocked `docker.from_env()` returning 6 containers, one tick populates the in-proc dict correctly. Don't test the loop itself. | `pytest-asyncio` |
| `/metrics` integration | One test using `httpx.AsyncClient` against FastAPI app. All collectors mocked. Asserts response validates against `MetricsResponse`. | existing backend `conftest.py` pattern |

### What does NOT get tests

- `Dashboard.html` — reference code; breaks are obvious on eyeball. No
  Playwright/Selenium for v1.
- `log_tailer` streaming loop — docker-py's `follow=True` generator is hard to
  fake, and failures manifest immediately in the Recent Logs panel. Smoke-test
  it manually.
- OCI SDK — not our code. We test *that we handle its errors*, not its calls.
- Nginx config — one `curl -u user:pass https://astral-reader.duckdns.org/metrics`
  during smoke.

### Smoke test (manual, runbook in PR)

1. `docker compose up -d astral_monitor` on the A1.
2. `curl -s -u user:pass https://astral-reader.duckdns.org/metrics | jq '. | keys'` — assert top-level keys match schema.
3. Open `https://astral-reader.duckdns.org/monitor/` in Safari on iPhone → Basic Auth prompt → dashboard loads → all cards populated, no amber dots.
4. `docker compose stop redis` → within 2 polls: cost/storage/backups show amber dots, other sections stay green. `docker compose start redis` → next poll clears dots.
5. `docker compose restart fastapi` → within 15s the `fastapi` card shows `STARTING` → back to `UP`. Log tail shows the restart.
6. Revoke the A1's IAM dynamic-group membership temporarily → cost card goes amber (last-known), nothing else breaks. Re-add.

### CI

Add one job to the existing backend CI — `pytest backend/monitor/tests/`. No
OCI calls, no docker socket, no Redis required (fakeredis). Runs in <10s.

---

## Open questions (to resolve during implementation planning)

- Exact cron schedule + source path for nginx access log bind-mount. Requires
  touching nginx.conf + verifying log rotation plan. [small]
- Whether to self-host Inter + JetBrains Mono in v1 or stay on Google Fonts
  CDN. CDN is simpler; self-hosting tightens the "no external deps" story.
  Deferred to post-merge. [tiny]
- Log-level regex: current plan is `(DEBUG|INFO|WARN|ERROR)` case-insensitive.
  Nginx logs don't have a level field — infer `INFO` for 2xx/3xx, `WARN` for
  4xx, `ERROR` for 5xx by response code. Codify in `log_tailer`. [small]

## References

- Design handoff: `/Users/nicknetraganti/Downloads/design_handoff_oci_monitor/Dashboard.html` + `README.md`
- Related: `backend/docker-compose.yml` (current prod stack), `backend/nginx/nginx.conf`, `backend/scripts/astral-backup-setup.md` (instance-principal pattern reused for OCI SDK auth)
- Project CLAUDE.md — "OCI Cost Policy (non-negotiable)" section
