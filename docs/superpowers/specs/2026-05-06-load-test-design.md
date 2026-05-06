# Load Test Design — Astral Backend API

**Date:** 2026-05-06  
**Target:** `astral-reader.duckdns.org` (OCI A1 ARM, Always Free)  
**Tool:** k6  
**Billing risk:** None — A1 compute is Always Free; Run B egress (~50–200 MB) is negligible against 10 TB/month free allowance.

---

## Goals

1. Find the saturation point of the FastAPI + Postgres + Redis stack under a realistic mixed workload.
2. Measure the full degradation curve — latency inflation before hard errors, not just the failure threshold.
3. Validate the scrape pipeline end-to-end against 15 real AO3 fics and 15 real FFNet fics.
4. Quantify nginx + TLS + network overhead by comparing an internal Docker-network run against an external internet run.

---

## Architecture Context

| Layer | Detail |
|-------|--------|
| FastAPI | Single uvicorn worker (no `--workers` flag), async |
| Postgres | SQLAlchemy async, connection pool at default settings |
| Redis | 128 MB cap, allkeys-lru eviction |
| ARQ worker | `ARQ_MAX_JOBS=3` concurrent scrape jobs |
| nginx | `worker_processes auto`, `worker_connections 1024`, no rate limiting |
| Host | OCI A1 ARM, Always Free (4 OCPUs, 24 GB RAM available to the stack) |

Expected first saturation signal: Postgres connection pool contention in the 25–50 VU range.

---

## Two Test Scripts

### Script 1 — `api-load-test.js`

Mixed read/write VU ramp. Simulates a realistic reader session loop.

**Session loop per VU:**

| Step | Endpoint | Tag |
|------|----------|-----|
| 1 | `GET /api/v1/comics?page=1&page_size=20` | `comics_list` |
| 2 | `GET /api/v1/comics/{id}` (random from step 1) | `comic_detail` |
| 3 | `GET /api/v1/comics/{id}/chapters/{chapter_id}/pages` | `chapter_pages` |
| 4 | `PUT /api/v1/progress/comic/{id}` | `progress_write` |
| 5 | `GET /api/v1/stats` | `stats` |
| — | Sleep 0.5–1s between steps | — |

Comic and chapter IDs are resolved in k6's `setup()` function (one `GET /api/v1/comics` call before VUs start) — no hardcoded IDs.

**Excluded routes:** all scrape endpoints, all delete endpoints, `/health` (too trivial to pollute metrics), fanfic routes (separate concern).

**Ramp stages:**

| Stage | Duration | Target VUs | Purpose |
|-------|----------|------------|---------|
| Warm-up | 1 min | 0 → 5 | Settle JIT, establish clean baseline |
| Baseline hold | 2 min | 5 | Measure healthy p95 |
| Ramp | 2 min | 5 → 25 | First pressure point |
| Hold | 2 min | 25 | Observe connection pool stability |
| Ramp | 2 min | 25 → 50 | Mid pressure |
| Hold | 2 min | 50 | Watch for pool saturation |
| Ramp | 2 min | 50 → 100 | Push toward breaking point |
| Hold | 2 min | 100 | Confirm sustained behaviour at peak |
| Cool-down | 1 min | 100 → 0 | Observe recovery |

**Total: ~16 minutes.**

**Thresholds:**

```
http_req_duration{p:95} < 500ms    (green — healthy ops)
http_req_duration{p:95} < 2000ms   (amber — degraded but functional)
http_req_failed rate < 0.05         (hard error gate: >5% = notable failure)
```

Per-route breakdown via `name` tag in k6 summary — identifies which endpoint degrades first. `progress_write` expected to degrade before read routes due to Postgres write lock contention.

---

### Script 2 — `scrape-pipeline-test.js`

End-to-end scrape pipeline validation. Two phases.

**Phase A — Burst enqueue (~5 min):**

Ramp 1→20 VUs. Each VU picks a URL from a shuffled SharedArray of 30 fics (15 AO3 + 15 FFNet) and fires `POST /api/v1/scrape/fanfic`. Records the returned job ID. Tests how fast the API accepts and enqueues jobs under concurrent load.

Request body per scrape:
```json
{
  "url": "<fic_url>",
  "source_key": "ao3" | "ffnet",
  "cookies": [],
  "user_agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15"
}
```

Public fics require no login cookies.

**Fic list — AO3 (15 fics):**  
Well-known multi-chapter works sourced from AO3's all-time kudos statistics. Fandoms: Harry Potter, MCU, Supernatural, Teen Wolf, Check Please. A handful may return 404 or restricted at scrape time — treated as expected failures.

**Fic list — FFNet (15 fics):**  
Well-known long-running works from FFNet's all-time favorites list. Same fandoms. FFNet scrapes may fail due to FicHub/FanFicFare instability — any terminal state (`completed` or `failed`) is treated as a pass.

**Phase A threshold:**
```
POST /api/v1/scrape/fanfic acceptance rate ≥ 95%
POST p(95) < 300ms  (it's just a DB insert + Redis enqueue)
```

**Phase B — Pipeline drain (~15–20 min, passive):**

After all 30 jobs are enqueued, k6 polls a random sample of 10 job IDs every 30s via `GET /api/v1/scrape/{id}`. Reports `pending / running / completed / failed` counts until all jobs reach a terminal state or a 30-minute timeout fires.

ARQ processes 3 jobs concurrently. Drain time estimate: ~10–20 minutes depending on fic length.

**Phase B thresholds:**

| Check | Threshold | Rationale |
|-------|-----------|-----------|
| AO3 completed | ≥ 80% of AO3 jobs | Some fics may be restricted or deleted |
| FFNet terminal | any state | Known flaky source; failure is informative |

---

## Run Order & Timing

```
t=0:00  scrape-pipeline-test.js Phase A  (local Mac → nginx → fastapi)
t=0:05  api-load-test.js Run A           (OCI internal → fastapi:8000 direct)
t=0:05  ARQ begins draining scrape queue (3 concurrent, ~15–20 min)
t=0:22  Run A complete → results-internal.json saved
t=0:25  api-load-test.js Run B           (local Mac → nginx → fastapi)
t=0:41  Run B complete → results-external.json saved
t=0:45  Scrape queue fully drained
```

Runs A and B both overlap with active ARQ scrape jobs — intentional. The scrape worker competes for the same Postgres connection pool and Redis, reflecting real concurrent background pressure.

---

## Setup Commands

### Install k6

**Local Mac:**
```bash
brew install k6
```

**OCI server (Run A):**
No install needed — k6 runs as a Docker container on the `astral_net` network.

### Copy scripts to OCI

```bash
scp -i ~/.ssh/astral_oci \
  api-load-test.js scrape-pipeline-test.js \
  ubuntu@astral-reader.duckdns.org:~/astral-loadtest/
```

### Run A — Internal

```bash
ssh -i ~/.ssh/astral_oci ubuntu@astral-reader.duckdns.org

# Verify network name
docker network ls | grep astral
# Expected: backend_astral_net

mkdir -p ~/astral-loadtest

docker run --rm \
  --network backend_astral_net \
  -v ~/astral-loadtest:/scripts \
  -e BASE_URL=http://fastapi:8000 \
  grafana/k6 run \
    --out json=/scripts/results-internal.json \
    /scripts/api-load-test.js
```

### Run B — External

```bash
BASE_URL=https://astral-reader.duckdns.org \
  k6 run --out json=results-external.json api-load-test.js
```

### Post-test health check

```bash
curl -s https://astral-reader.duckdns.org/api/v1/health | jq .
# Expect: 200 OK within 1 second
```

---

## Observation During the Test

### Monitor dashboard panels to watch

Open `https://astral-reader.duckdns.org/monitor/` before starting.

| Panel | Watch for |
|-------|-----------|
| Request rate | Should climb linearly with VUs; a flat line = nginx or fastapi queuing |
| Endpoint p95 latency | Non-linear climb marks the saturation point |
| ARQ queue depth | Near 0 during API test; spikes during scrape drain are expected |
| Postgres connections | Pool exhaustion appears here before 5xx errors |
| Container memory | FastAPI should stay flat; ARQ worker may grow during scrape jobs |

### Live log tail (second SSH tab)

```bash
docker compose logs -f fastapi 2>&1 | grep -E "elapsed_ms|ERROR|WARNING"
```

The `log_requests` middleware logs every `elapsed_ms` — latency climbs are visible here before k6 reports them.

---

## Safety Rails

1. **Hard VU cap at 100** — baked into ramp stages. Saturation occurs well before this on a single-worker async server.
2. **No scrape endpoints in api-load-test.js** — excluded to avoid queuing ARQ jobs during the VU ramp.
3. **No delete endpoints in either script** — idempotent reads and progress writes only.
4. **Scrape test before API ramp** — if scrape request body is malformed, abort before the load test starts.
5. **Abort at 10% error rate** — `Ctrl+C` kills the test; k6 prints a partial summary with enough data to read the degradation curve.
6. **Cool-down verification** — confirm `GET /api/v1/health` returns 200 after each run.

---

## What to Compare Between Runs

| Metric | Expected delta | Interpretation |
|--------|---------------|----------------|
| Baseline p95 at 5 VUs | 20–80ms higher on Run B | Home network RTT + TLS handshake overhead |
| Saturation VU count | Same on both | Server is the bottleneck, not the network |
| p95 at 100 VUs | Within ~50ms | nginx adds negligible overhead at saturation |
| Error onset VU | Same on both | Errors are server-side, not network drops |

If Run B saturates at significantly fewer VUs than Run A: nginx is a bottleneck (unlikely given current config).

---

## Next Steps After the Test

1. Record the VU count where p95 crossed 500ms and 2000ms.
2. Record which route degraded first (`progress_write` expected).
3. If Postgres connection pool is the bottleneck: tune `pool_size` and `max_overflow` in SQLAlchemy.
4. If uvicorn is the bottleneck: add `--workers 2` to the Dockerfile CMD (A1 has 4 OCPUs; 2 workers is safe on Always Free).
5. Record AO3 completion rate and FFNet terminal rate from the scrape test.
6. If FFNet failure rate is high: set `FFNET_NEW_SCRAPER_DISABLED=true` in `.env.oci` to fall back to FicHub.
