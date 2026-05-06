# Backend Load Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and execute two k6 load test scripts that find the FastAPI + Postgres saturation point under a mixed read/write workload and validate the AO3/FFNet scrape pipeline end-to-end.

**Architecture:** `api-load-test.js` ramps virtual users from 1 to 100 over 16 minutes, each running a five-step reader session loop (comics list → comic detail → chapter pages → progress write → stats). `scrape-pipeline-test.js` distributes 30 real fic URLs across 30 VUs — each VU fires one scrape job and polls it to completion, letting k6 track per-source completion rates. Both run with `BASE_URL` injected via env var so the same script works for the internal OCI run and the external Mac run.

**Tech Stack:** k6 (JavaScript, ES modules), targeting FastAPI at `http://fastapi:8000` (internal) or `https://astral-reader.duckdns.org` (external). No external dependencies beyond k6 itself — no jslib imports.

**Spec:** `docs/superpowers/specs/2026-05-06-load-test-design.md`

---

## File Map

| Path | Action | Responsibility |
|------|--------|----------------|
| `loadtest/README.md` | Create | Setup and run instructions |
| `loadtest/fic-urls.js` | Create | 15 AO3 + 15 FFNet URL arrays |
| `loadtest/api-load-test.js` | Create | VU ramp test — reads, progress writes, stages, thresholds |
| `loadtest/scrape-pipeline-test.js` | Create | Scrape burst + per-VU polling, per-source Rate metrics |

---

## Task 1: Scaffold `loadtest/` directory and README

**Files:**
- Create: `loadtest/README.md`

- [ ] **Step 1: Create the directory and README**

```bash
mkdir -p loadtest
```

Write `loadtest/README.md`:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add loadtest/README.md
git commit -m "[backend] add loadtest scaffold and README"
```

---

## Task 2: Create `fic-urls.js` — URL arrays

**Files:**
- Create: `loadtest/fic-urls.js`

- [ ] **Step 1: Populate AO3 URLs**

Visit `https://archiveofourown.org/works?sort_column=kudos_count&direction=desc&commit=Sort+and+Filter` and pick 13 multi-chapter English works (any fandom) that have been on the site for years. Add their work URLs alongside the two pre-confirmed entries below.

Create `loadtest/fic-urls.js`:

```js
// 15 well-known AO3 works sorted by all-time kudos.
// IDs 1335295 and 2002705 are confirmed stable as of 2026.
// Remaining 13: sourced from archiveofourown.org sorted by kudos —
// visit the URL in Task 2 Step 1 to refresh if any return 404.
export const AO3_URLS = [
  'https://archiveofourown.org/works/1335295',  // All the Young Dudes (HP)
  'https://archiveofourown.org/works/2002705',  // Twist and Shout (SPN)
  // ADD 13 MORE HERE — one URL per line, same format
];

// 15 well-known FFNet works sorted by all-time favorites.
// ID 5782108 is confirmed stable as of 2026.
// Remaining 14: visit fanfiction.net, browse HP → sort by Favorites,
// pick long (20+ chapter) multi-chapter works.
export const FFNET_URLS = [
  'https://www.fanfiction.net/s/5782108/1/Harry-Potter-and-the-Methods-of-Rationality',
  // ADD 14 MORE HERE — one URL per line, same format
];
```

- [ ] **Step 2: Verify the arrays have exactly 15 entries each**

```bash
node -e "
const { AO3_URLS, FFNET_URLS } = await import('./loadtest/fic-urls.js');
console.log('AO3:', AO3_URLS.length, 'FFNet:', FFNET_URLS.length);
if (AO3_URLS.length !== 15 || FFNET_URLS.length !== 15) process.exit(1);
" --input-type=module
```

Expected output:
```
AO3: 15 FFNet: 15
```

- [ ] **Step 3: Commit**

```bash
git add loadtest/fic-urls.js
git commit -m "[backend] add fic URL arrays for scrape load test"
```

---

## Task 3: Create `api-load-test.js`

**Files:**
- Create: `loadtest/api-load-test.js`

- [ ] **Step 1: Write the script**

Create `loadtest/api-load-test.js`:

```js
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';

export const options = {
  stages: [
    { duration: '1m',  target: 5   },  // warm-up
    { duration: '2m',  target: 5   },  // baseline hold
    { duration: '2m',  target: 25  },  // ramp
    { duration: '2m',  target: 25  },  // hold
    { duration: '2m',  target: 50  },  // ramp
    { duration: '2m',  target: 50  },  // hold
    { duration: '2m',  target: 100 },  // push
    { duration: '2m',  target: 100 },  // hold
    { duration: '1m',  target: 0   },  // cool-down
  ],
  thresholds: {
    http_req_duration:                          ['p(95)<500', 'p(95)<2000'],
    http_req_failed:                            ['rate<0.05'],
    'http_req_duration{name:progress_write}':   ['p(95)<1000'],
  },
};

export function setup() {
  const listRes = http.get(`${BASE_URL}/api/v1/comics?page=1&page_size=20`);
  check(listRes, { 'setup: comics list 200': r => r.status === 200 });

  const body = listRes.json();
  const comics = (body.items || []).filter(c => c.total_chapters > 0);

  if (comics.length === 0) {
    throw new Error('setup: no comics found — seed the database before running');
  }

  // Fetch up to 5 comic details to collect (comicId, chapterId, chapterNumber) tuples.
  // list_comics omits chapters (include_chapters=False in comic_service.py:110),
  // so we need the individual GET to get chapter UUIDs.
  const targets = [];
  for (const comic of comics.slice(0, 5)) {
    const detailRes = http.get(`${BASE_URL}/api/v1/comics/${comic.id}`);
    if (detailRes.status !== 200) continue;
    const detail = detailRes.json();
    const chapters = (detail.chapters || []).filter(ch => ch.scrape_status === 'scraped');
    for (const ch of chapters.slice(0, 3)) {
      targets.push({
        comicId: comic.id,
        chapterId: ch.id,
        chapterNumber: Math.round(ch.chapter_number),
      });
    }
  }

  if (targets.length === 0) {
    throw new Error('setup: no scraped chapters found — run a scrape job first');
  }

  return { targets };
}

export default function (data) {
  const target = data.targets[Math.floor(Math.random() * data.targets.length)];
  const headers = { 'Content-Type': 'application/json' };

  // 1 — list comics
  const listRes = http.get(
    `${BASE_URL}/api/v1/comics?page=1&page_size=20`,
    { tags: { name: 'comics_list' } },
  );
  check(listRes, { 'comics_list 200': r => r.status === 200 });
  sleep(0.5 + Math.random() * 0.5);

  // 2 — comic detail
  const detailRes = http.get(
    `${BASE_URL}/api/v1/comics/${target.comicId}`,
    { tags: { name: 'comic_detail' } },
  );
  check(detailRes, { 'comic_detail 200': r => r.status === 200 });
  sleep(0.5 + Math.random() * 0.5);

  // 3 — chapter pages
  const pagesRes = http.get(
    `${BASE_URL}/api/v1/comics/${target.comicId}/chapters/${target.chapterId}/pages`,
    { tags: { name: 'chapter_pages' } },
  );
  check(pagesRes, { 'chapter_pages 200': r => r.status === 200 });
  sleep(0.5 + Math.random() * 0.5);

  // 4 — write progress (ComicProgressRequest requires last_chapter_number: int)
  const progressRes = http.put(
    `${BASE_URL}/api/v1/progress/comic/${target.comicId}`,
    JSON.stringify({ last_chapter_number: target.chapterNumber }),
    { headers, tags: { name: 'progress_write' } },
  );
  check(progressRes, { 'progress_write 200': r => r.status === 200 });
  sleep(0.5 + Math.random() * 0.5);

  // 5 — stats
  const statsRes = http.get(
    `${BASE_URL}/api/v1/stats`,
    { tags: { name: 'stats' } },
  );
  check(statsRes, { 'stats 200': r => r.status === 200 });
  sleep(0.5 + Math.random() * 0.5);
}
```

- [ ] **Step 2: Verify the script parses cleanly**

```bash
k6 inspect loadtest/api-load-test.js
```

Expected: k6 prints the script options (stages, thresholds) with no errors.

- [ ] **Step 3: Commit**

```bash
git add loadtest/api-load-test.js
git commit -m "[backend] add api-load-test.js VU ramp script"
```

---

## Task 4: Smoke-test `api-load-test.js`

- [ ] **Step 1: Run a 30-second smoke test at 1 VU**

This confirms `setup()` connects, comic IDs resolve, and the progress write body is accepted (no 422s).

```bash
BASE_URL=https://astral-reader.duckdns.org \
  k6 run --vus 1 --duration 30s loadtest/api-load-test.js
```

- [ ] **Step 2: Verify no 422s in the output**

Expected: all five checks pass green (`✓`). The output should show something like:

```
✓ setup: comics list 200
✓ comics_list 200
✓ comic_detail 200
✓ chapter_pages 200
✓ progress_write 200
✓ stats 200
```

If `progress_write` shows 422: the `last_chapter_number` type is wrong. Check that `target.chapterNumber` is an integer (`Math.round` is applied in setup — confirm it's not NaN).

If `chapter_pages` shows 404: the chapter was soft-deleted or `scrape_status !== 'scraped'`. The `setup()` filter on `scrape_status === 'scraped'` should prevent this — check your database has at least one fully scraped comic.

- [ ] **Step 3: Confirm no errors and move on (no commit needed for this task)**

---

## Task 5: Create `scrape-pipeline-test.js`

**Files:**
- Create: `loadtest/scrape-pipeline-test.js`

This script distributes 30 fic URLs across 30 VUs. Each VU fires one `POST /api/v1/scrape/fanfic`, then polls its own job every 10 seconds until it reaches a terminal state (`complete`, `partial`, or `failed`) or 30 minutes elapses. k6 custom `Rate` metrics track per-source completion so thresholds can validate AO3 ≥80% complete and FFNet 100% terminal.

- [ ] **Step 1: Write the script**

Create `loadtest/scrape-pipeline-test.js`:

```js
import http from 'k6/http';
import { check, sleep } from 'k6';
import { SharedArray } from 'k6/data';
import { Rate } from 'k6/metrics';
import { AO3_URLS, FFNET_URLS } from './fic-urls.js';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15';

// Terminal states from JobStatus enum in backend/app/core/constants.py
const TERMINAL = new Set(['complete', 'partial', 'failed']);
const POLL_INTERVAL_S = 10;
const POLL_TIMEOUT_S  = 30 * 60; // 30 minutes

// Custom metrics for per-source threshold tracking
const scrapeComplete  = new Rate('scrape_complete');  // tracks source:ao3 complete rate
const scrapeTerminal  = new Rate('scrape_terminal');  // tracks source:ffnet terminal rate

// SharedArray is read-once at init time, shared across all VUs (read-only).
// 30 entries: 15 AO3 then 15 FFNet, so VU index maps directly to a unique fic.
const fics = new SharedArray('fics', () => [
  ...AO3_URLS.map(url => ({ url, source: 'ao3' })),
  ...FFNET_URLS.map(url => ({ url, source: 'ffnet' })),
]);

export const options = {
  // 30 VUs, 1 iteration each. Each VU owns one fic: fires the scrape, then polls to completion.
  vus: 30,
  iterations: 30,
  maxDuration: '35m',
  thresholds: {
    // AO3: at least 80% of AO3 jobs must reach 'complete'
    'scrape_complete{source:ao3}':   ['rate>=0.8'],
    // FFNet: all FFNet jobs must reach any terminal state (complete, partial, or failed)
    'scrape_terminal{source:ffnet}': ['rate>=1.0'],
    // Enqueue latency: POST is just a DB insert + Redis enqueue
    'http_req_duration{name:scrape_enqueue}': ['p(95)<300'],
  },
};

export default function () {
  // Each VU picks its fic by VU index (1-based → 0-based).
  // With vus=30 and iterations=30, __VU ranges 1..30 covering all 30 fics exactly once.
  const fic = fics[(__VU - 1) % fics.length];
  const headers = { 'Content-Type': 'application/json' };

  // ── Phase A: enqueue the scrape job ──────────────────────────────────────
  const enqueueRes = http.post(
    `${BASE_URL}/api/v1/scrape/fanfic`,
    JSON.stringify({ url: fic.url, source_key: fic.source, cookies: [], user_agent: UA }),
    { headers, tags: { name: 'scrape_enqueue' } },
  );

  const enqueueOk = check(enqueueRes, {
    'scrape enqueue 202': r => r.status === 202,
  });

  if (!enqueueOk) {
    console.error(`[VU${__VU}] enqueue failed: status=${enqueueRes.status} url=${fic.url}`);
    // Record as not complete / not terminal so it counts against thresholds
    scrapeComplete.add(0, { source: fic.source });
    scrapeTerminal.add(0, { source: fic.source });
    return;
  }

  const jobId = enqueueRes.json('id');
  if (!jobId) {
    console.error(`[VU${__VU}] enqueue returned no job id — body: ${enqueueRes.body}`);
    scrapeComplete.add(0, { source: fic.source });
    scrapeTerminal.add(0, { source: fic.source });
    return;
  }

  // ── Phase B: poll this VU's job until terminal state or timeout ───────────
  let elapsed = 0;
  let status  = 'queued';

  while (!TERMINAL.has(status) && elapsed < POLL_TIMEOUT_S) {
    sleep(POLL_INTERVAL_S);
    elapsed += POLL_INTERVAL_S;

    const pollRes = http.get(
      `${BASE_URL}/api/v1/scrape/${jobId}`,
      { tags: { name: 'scrape_poll' } },
    );

    if (pollRes.status !== 200) {
      console.warn(`[VU${__VU}] poll returned ${pollRes.status} for job ${jobId}`);
      continue;
    }

    status = pollRes.json('status') || 'unknown';
    console.log(`[VU${__VU}] job=${jobId} source=${fic.source} status=${status} elapsed=${elapsed}s`);
  }

  const isTerminal = TERMINAL.has(status);
  const isComplete = status === 'complete';

  if (!isTerminal) {
    console.error(`[VU${__VU}] job=${jobId} timed out after ${elapsed}s, last status=${status}`);
  }

  scrapeComplete.add(isComplete ? 1 : 0, { source: fic.source });
  scrapeTerminal.add(isTerminal ? 1 : 0, { source: fic.source });
}
```

- [ ] **Step 2: Verify the script parses cleanly**

```bash
k6 inspect loadtest/scrape-pipeline-test.js
```

Expected: k6 prints options (vus: 30, iterations: 30, maxDuration: 35m0s) with no errors.

- [ ] **Step 3: Commit**

```bash
git add loadtest/scrape-pipeline-test.js
git commit -m "[backend] add scrape-pipeline-test.js — burst enqueue + per-VU polling"
```

---

## Task 6: Smoke-test `scrape-pipeline-test.js`

- [ ] **Step 1: Run a single-VU smoke test (1 fic only)**

This fires one real scrape against AO3, polls it, and exits. Confirms the enqueue body is accepted (no 422), job ID is returned, and polling resolves to a terminal state.

```bash
BASE_URL=https://astral-reader.duckdns.org \
  k6 run --vus 1 --iterations 1 loadtest/scrape-pipeline-test.js
```

- [ ] **Step 2: Verify the output**

Expected: the enqueue check passes and the job reaches `complete` or `partial` within ~10 minutes (AO3 fics are typically short). Watch for these log lines:

```
[VU1] job=<uuid> source=ao3 status=running elapsed=10s
[VU1] job=<uuid> source=ao3 status=complete elapsed=60s
✓ scrape enqueue 202
```

If `status` stays `queued` for more than 3 poll cycles: check ARQ worker is running (`docker compose ps` on OCI — or locally if testing against `localhost`).

If enqueue returns 422: the request body is malformed. Check that `source_key` is exactly `"ao3"` (confirmed in `SourceKey` enum at `backend/app/core/constants.py:4`).

- [ ] **Step 3: No commit needed — move to Task 7**

---

## Task 7: Run A — OCI internal baseline

> **Pre-condition:** Both smoke tests passed. Open the monitor dashboard at `https://astral-reader.duckdns.org/monitor/` and the live log tail in a second terminal before starting.

- [ ] **Step 1: Copy scripts to OCI**

```bash
scp -i ~/.ssh/astral_oci \
  loadtest/api-load-test.js loadtest/scrape-pipeline-test.js loadtest/fic-urls.js \
  ubuntu@astral-reader.duckdns.org:~/astral-loadtest/
```

- [ ] **Step 2: SSH in and fire scrape jobs (t=0:00)**

```bash
ssh -i ~/.ssh/astral_oci ubuntu@astral-reader.duckdns.org
```

From your Mac (in a separate terminal, while SSHed in OCI is standing by):

```bash
BASE_URL=https://astral-reader.duckdns.org \
  k6 run --out json=loadtest/results-scrape.json loadtest/scrape-pipeline-test.js
```

This runs for up to 35 minutes. Let it run in the background — move to the next step after ~5 minutes (all 30 jobs will be enqueued by then even if polling is still in progress).

- [ ] **Step 3: Verify network name and start Run A (t=0:05, from OCI SSH session)**

```bash
docker network ls | grep astral
# Expected output contains: backend_astral_net
# If the name differs, substitute it in the docker run command below.

mkdir -p ~/astral-loadtest

docker run --rm \
  --network backend_astral_net \
  -v ~/astral-loadtest:/scripts \
  -e BASE_URL=http://fastapi:8000 \
  grafana/k6 run \
    --out json=/scripts/results-internal.json \
    /scripts/api-load-test.js
```

Expected: k6 prints stage progress every 10 seconds. Watch p95 climb as VUs increase.

- [ ] **Step 4: Record the saturation points from the k6 summary**

When Run A finishes, k6 prints a summary. Note:
- The stage (VU count) where `http_req_duration p(95)` first crossed 500 ms
- The stage where it first crossed 2000 ms
- Whether `progress_write` degraded before the read routes
- Whether any thresholds failed (✗ in the summary)

- [ ] **Step 5: Post-test health check**

```bash
curl -s https://astral-reader.duckdns.org/api/v1/health | jq .
```

Expected: `{"status": "ok"}` within 1 second. If it times out: check `docker compose ps` for restarted containers.

- [ ] **Step 6: Copy results file back to Mac**

```bash
scp -i ~/.ssh/astral_oci \
  ubuntu@astral-reader.duckdns.org:~/astral-loadtest/results-internal.json \
  loadtest/results-internal.json
```

---

## Task 8: Run B — Mac external full-stack

> **Pre-condition:** Run A finished and health check passed. Wait at least 2 minutes after Run A completes before starting Run B so the server is fully idle.

- [ ] **Step 1: Start Run B (t=0:25)**

```bash
BASE_URL=https://astral-reader.duckdns.org \
  k6 run --out json=loadtest/results-external.json loadtest/api-load-test.js
```

- [ ] **Step 2: Record the saturation points from the k6 summary**

Same metrics as Task 7 Step 4. Compare:

| Metric | Run A (internal) | Run B (external) | Delta |
|--------|-----------------|-----------------|-------|
| Baseline p95 at 5 VUs | | | |
| VU count where p95 > 500 ms | | | |
| VU count where p95 > 2000 ms | | | |
| Error onset VU count | | | |
| `progress_write` p95 at 100 VUs | | | |

Fill in from the two `--out json` files or k6's terminal summary.

- [ ] **Step 3: Post-test health check**

```bash
curl -s https://astral-reader.duckdns.org/api/v1/health | jq .
```

Expected: `{"status": "ok"}` within 1 second.

- [ ] **Step 4: Check scrape pipeline results**

By this point the `scrape-pipeline-test.js` run should be complete or nearly so. Check its summary output for:
- `scrape_complete{source:ao3}` rate ≥ 0.8 (threshold pass)
- `scrape_terminal{source:ffnet}` rate ≥ 1.0 (threshold pass — any terminal state)
- Any AO3 jobs that timed out (logged as `[VU*] timed out`) indicate an ARQ worker issue

- [ ] **Step 5: Commit results**

```bash
git add loadtest/results-internal.json loadtest/results-external.json loadtest/results-scrape.json
git commit -m "[backend] add load test results — internal and external runs"
```

---

## Next Steps (post-test)

Based on results, apply fixes in a follow-up plan:

| Finding | Fix |
|---------|-----|
| Saturation at 25–50 VUs, Postgres connections maxed | Tune `pool_size` and `max_overflow` in SQLAlchemy engine config |
| Saturation at 50–100 VUs, CPU-bound | Add `--workers 2` to `Dockerfile` CMD (A1 has 4 OCPUs) |
| `progress_write` degrades before reads | Add a DB index or review transaction isolation in `progress_service.py` |
| FFNet terminal rate < 100% | Set `FFNET_NEW_SCRAPER_DISABLED=true` in `.env.oci` to force FicHub fallback |
| AO3 complete rate < 80% | Check ARQ logs for the failed job IDs — likely rate-limited or restricted fics |
