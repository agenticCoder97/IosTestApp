# Astral Backend Load Test

k6-based load tests. Two scripts:

- `api-load-test.js` — VU ramp (mixed reads + progress writes), ~16 min
- `scrape-pipeline-test.js` — Scrape 30 real fics (15 AO3 + 15 FFNet), poll to completion, ~35 min

## Prerequisites

**Local Mac:**
```bash
brew install k6
```

**OCI server (Run A — internal):**
No install needed. k6 runs as a Docker container on `backend_astral_net`.

## Run order

### Step 1 — Copy scripts to OCI
```bash
scp -i ~/.ssh/astral_oci \
  loadtest/api-load-test.js loadtest/scrape-pipeline-test.js loadtest/fic-urls.js \
  ubuntu@astral-reader.duckdns.org:~/astral-loadtest/
```

### Step 2 — Fire scrape jobs (from Mac)
```bash
BASE_URL=https://astral-reader.duckdns.org \
  k6 run --out json=loadtest/results-scrape.json loadtest/scrape-pipeline-test.js
```

### Step 3 — Run A: internal OCI baseline (SSH into OCI)
```bash
# Verify network name first
docker network ls | grep astral
# Expected: backend_astral_net

docker run --rm \
  --network backend_astral_net \
  -v ~/astral-loadtest:/scripts \
  -e BASE_URL=http://fastapi:8000 \
  grafana/k6 run \
    --out json=/scripts/results-internal.json \
    /scripts/api-load-test.js
```

### Step 4 — Run B: external Mac (after Run A finishes)
```bash
BASE_URL=https://astral-reader.duckdns.org \
  k6 run --out json=loadtest/results-external.json loadtest/api-load-test.js
```

### Step 5 — Post-test health check
```bash
curl -s https://astral-reader.duckdns.org/api/v1/health | jq .
# Expect: {"status": "ok"} within 1 second
```

## What to watch

Open `https://astral-reader.duckdns.org/monitor/` before starting.

In a second terminal:
```bash
ssh -i ~/.ssh/astral_oci ubuntu@astral-reader.duckdns.org
cd /home/ubuntu/astral/backend
docker compose logs -f fastapi 2>&1 | grep -E "elapsed_ms|ERROR|WARNING"
```

## Abort condition

If error rate crosses 10% at any stage, press Ctrl+C. k6 prints a partial summary — you have enough data from the degradation curve.

## Interpreting results

- First VU stage where p95 crosses 500 ms = healthy ceiling
- First VU stage where p95 crosses 2000 ms = degraded-but-functional ceiling
- `progress_write` p95 expected to degrade before read routes (write lock contention)
- Run A vs Run B delta at 5 VUs baseline ≈ home network RTT + TLS overhead (directional, not controlled — see spec caveat)
