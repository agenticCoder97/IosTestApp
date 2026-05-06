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
