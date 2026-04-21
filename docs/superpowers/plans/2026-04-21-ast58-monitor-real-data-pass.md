# AST-58 Monitor Real-Data Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the gap between AST-57's `/metrics` payload and what the UI actually renders — every panel shows live data or explicit degraded markers; three always-mock sections are deleted; two real bugs (DOWN-badge false positives, empty Request Metrics panel) get fixed.

**Architecture:** Monitor-only + nginx config changes. Two new JS renderers (`renderCost`, `renderCert`) take over static HTML cells. One new OCI Usage API integration for real egress. One new nginx `stub_status` endpoint + thin scraper for real active_connections. One additional window (`1m_api`) in the existing `nginx_access_sampler`. One-line health synthesis in `_sample_once`. Three HTML section deletions.

**Tech Stack:** Python 3.11, FastAPI, pydantic v2, OCI SDK (usage_api), httpx, pytest + pytest-asyncio + fakeredis. HTML/JS vanilla (no build step).

**Design spec:** [docs/superpowers/specs/2026-04-21-ast58-monitor-real-data-pass-design.md](../specs/2026-04-21-ast58-monitor-real-data-pass-design.md)

**Follows:** [AST-57 OCI monitor dashboard](https://linear.app/nnetraganti/issue/AST-57)

---

## Conventions

- **Branch name**: `feature/ast-58-monitor-real-data-pass` (cut from `development` **after** AST-57 PR #48 merges; if it hasn't merged yet, cut from `feature/ast-57-oci-monitor-dashboard` and rebase later).
- **Commit prefix**: `[backend] AST-58 <desc>` on every commit.
- **Co-author trailer**: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.
- **Run tests**: `cd backend && python3 -m pytest monitor/tests/ -v` (pytest.ini has `asyncio_mode = auto`).
- **Run on A1 via SSH**: `ssh -i ~/.ssh/astral_oci ubuntu@astral-reader.duckdns.org`.
- **Compose env-file**: always `docker compose --env-file .env.oci` on the A1 — plain `docker compose` doesn't auto-load `.env.oci` (found this the hard way in AST-57).

---

## File Structure

**Create**

```
backend/monitor/collectors/_nginx_stub.py               # async fetch + text parse
backend/monitor/tests/collectors/test_nginx_stub.py     # parser + mocked fetch
backend/monitor/tests/collectors/test_cost_egress.py    # mocked Usage API
backend/monitor/tests/test_nginx_access_sampler_1m_api.py  # window emission
backend/monitor/tests/test_health_synthesis.py          # _sample_once health fix
```

**Modify**

- `backend/monitor/bg.py` — health synthesis (item 8); `_WINDOWS_S` gains `"1m_api"`; `nginx_access_sampler` computes the api-only window; `_fetch_service_extra("nginx")` uses `_nginx_stub`; `_fetch_service_extra("fastapi")` reads `1m_api`.
- `backend/monitor/collectors/cost.py` — new `_fetch_egress()`; `cost.collect()` uses `asyncio.gather` for budget + egress; `_fetch_always_free()` reads real egress.
- `backend/monitor/static/index.html` — delete §1b / §3b / §7b sections; add `renderCert()` + `renderCost()`; swap hardcoded container-ID pills for `s.container_id`; `renderAll()` calls both new renderers + drops inline egress logic (now inside `renderCost`); `renderRequests()` shows "(no traffic in this window)" placeholder when status-code sum is 0.
- `backend/nginx/nginx.conf` — add `location = /nginx_status` block.
- `CHANGELOG.md` — add AST-58 entry (final task).

**OCI-side (runbook only)**

- Append one statement to `astral-monitor-policy`: `Allow dynamic-group astral-a1-backup to read usage-reports in tenancy`.

---

## Phase 0 — Linear + branch

### Task 0: File Linear issue and cut feature branch

**Files:** none.

- [ ] **Step 1: File the Linear issue**

Using the Linear MCP tool (or web UI), create a new issue in team **Astral**:

- **Title**: `[backend] Monitor real-data pass + delete misleading sections`
- **Description**: link to spec `docs/superpowers/specs/2026-04-21-ast58-monitor-real-data-pass-design.md` and this plan; mention it follows AST-57.
- **Project**: Astral.
- **Priority**: Normal (3).

Record the returned ID (e.g. `AST-58`). Substitute it for any `NN` placeholders below.

- [ ] **Step 2: Cut the branch**

If AST-57's PR #48 has merged:

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git checkout development
git pull --ff-only origin development
git checkout -b feature/ast-58-monitor-real-data-pass
```

If AST-57 hasn't merged yet (common case — this plan is a direct follow-up):

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git checkout feature/ast-57-oci-monitor-dashboard
git pull --ff-only
git checkout -b feature/ast-58-monitor-real-data-pass
```

Expected: `Switched to a new branch 'feature/ast-58-monitor-real-data-pass'`.

- [ ] **Step 3: Verify clean working tree**

```bash
git status
```

Expected: `nothing to commit, working tree clean` (or just Xcode pbxproj noise — untracked `ios/Astral/Astral.xcodeproj/xcshareddata/` is fine).

---

## Phase 1 — Quick-wins (health, deletion, pills)

### Task 1: Synthesize `healthy` when container runs without a healthcheck

**Files:**
- Modify: `backend/monitor/bg.py`
- Create: `backend/monitor/tests/test_health_synthesis.py`

The UI renderer treats any `s.health !== 'healthy' && s.health !== 'starting'` as `DOWN`. Only postgres + astral_monitor have compose `healthcheck:` blocks → other 5 services report `health: None` → everything looks `DOWN`. Absence of a healthcheck is not evidence of unhealthiness; synthesize `healthy` when `status == "running"`.

- [ ] **Step 1: Write the failing test**

Create `backend/monitor/tests/test_health_synthesis.py`:

```python
"""_sample_once synthesizes health='healthy' when container is running but
has no Docker healthcheck defined."""
from unittest.mock import AsyncMock, MagicMock

import pytest

from monitor.bg import SERVICE_CACHE, _sample_once


def _container(name, status="running", health_status=None):
    c = MagicMock()
    c.name = f"backend-{name}-1"
    c.labels = {"com.docker.compose.service": name}
    c.short_id = "abc123def456"
    c.image.tags = [f"{name}:latest"]
    c.attrs = {"State": {
        "Status": status,
        "Health": {"Status": health_status} if health_status else None,
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
        "memory_stats": {"usage": 100_000_000, "stats": {"cache": 0}},
    }
    return c


@pytest.mark.asyncio
async def test_running_without_healthcheck_gets_healthy(monkeypatch):
    SERVICE_CACHE.clear()
    # Neutralize the extra-fetch so this test focuses on health synthesis
    async def _noop(*args, **kwargs):
        return {}
    monkeypatch.setattr("monitor.bg._fetch_service_extra", _noop)

    client = MagicMock()
    client.containers.list.return_value = [
        _container("redis", status="running", health_status=None),
    ]
    redis = MagicMock()
    redis.zadd = AsyncMock(return_value=1)
    redis.zremrangebyscore = AsyncMock(return_value=0)

    await _sample_once(client, redis)
    assert SERVICE_CACHE["redis"]["health"] == "healthy"


@pytest.mark.asyncio
async def test_real_healthcheck_status_preserved(monkeypatch):
    SERVICE_CACHE.clear()
    async def _noop(*args, **kwargs):
        return {}
    monkeypatch.setattr("monitor.bg._fetch_service_extra", _noop)

    client = MagicMock()
    client.containers.list.return_value = [
        _container("postgres", status="running", health_status="healthy"),
        _container("fastapi",  status="running", health_status="unhealthy"),
    ]
    redis = MagicMock()
    redis.zadd = AsyncMock(return_value=1)
    redis.zremrangebyscore = AsyncMock(return_value=0)

    await _sample_once(client, redis)
    assert SERVICE_CACHE["postgres"]["health"] == "healthy"
    assert SERVICE_CACHE["fastapi"]["health"] == "unhealthy"


@pytest.mark.asyncio
async def test_stopped_container_stays_none(monkeypatch):
    SERVICE_CACHE.clear()
    async def _noop(*args, **kwargs):
        return {}
    monkeypatch.setattr("monitor.bg._fetch_service_extra", _noop)

    client = MagicMock()
    client.containers.list.return_value = [
        _container("arq_worker", status="exited", health_status=None),
    ]
    redis = MagicMock()
    redis.zadd = AsyncMock(return_value=1)
    redis.zremrangebyscore = AsyncMock(return_value=0)

    await _sample_once(client, redis)
    assert SERVICE_CACHE["arq_worker"]["health"] is None
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd backend && python3 -m pytest monitor/tests/test_health_synthesis.py -v
```

Expected: `test_running_without_healthcheck_gets_healthy` FAILS with `assert None == 'healthy'`. Other two may pass incidentally.

- [ ] **Step 3: Patch `_sample_once` in `backend/monitor/bg.py`**

Find:

```python
        health_obj = state.get("Health")
        health = health_obj.get("Status") if isinstance(health_obj, dict) else None
        started_at = state.get("StartedAt") or ""
```

Replace with:

```python
        health_obj = state.get("Health")
        health = health_obj.get("Status") if isinstance(health_obj, dict) else None
        # Absence of a Docker healthcheck is not evidence of unhealthiness —
        # synthesize "healthy" for any container whose Docker state is
        # "running", so the UI's UP/DOWN badge reflects runtime reality
        # rather than compose healthcheck presence. Exited/dead containers
        # keep health=None and the renderer correctly flags them DOWN.
        if health is None and status == "running":
            health = "healthy"
        started_at = state.get("StartedAt") or ""
```

- [ ] **Step 4: Run the tests to verify all 3 pass**

```bash
cd backend && python3 -m pytest monitor/tests/test_health_synthesis.py -v
```

Expected: 3 passed.

- [ ] **Step 5: Run the full monitor suite to confirm no regression**

```bash
cd backend && python3 -m pytest monitor/tests/ -q
```

Expected: 43 passed (40 from AST-57 + 3 new).

- [ ] **Step 6: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git add backend/monitor/bg.py backend/monitor/tests/test_health_synthesis.py
git commit -m "$(cat <<'EOF'
[backend] AST-58 synthesize healthy status when no docker healthcheck

Services without compose healthcheck: blocks (redis, fastapi, arq_worker,
nginx, certbot) were reporting health=None to the UI, which the badge
renderer treats as DOWN. Only postgres + astral_monitor have real
healthchecks — the other 5 cards looked dead.

In _sample_once, if state.Health is None but state.Status == "running",
synthesize health="healthy". Absence of a healthcheck is not evidence
of unhealthiness. Exited/dead containers keep health=None so the
renderer correctly badges them DOWN.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Delete three always-mock HTML sections

**Files:**
- Modify: `backend/monitor/static/index.html`

These three sections render fabricated data the backend can never populate on a $0 solo-dev stack. Cleanest fix: delete.

- [ ] **Step 1: Find the three sections**

Run (from repo root):

```bash
grep -n 'SLO & ERROR BUDGET\|UPTIME CHECKS\|RECOMMENDATIONS' backend/monitor/static/index.html
```

Expected output (line numbers will match the current file):

```
651:  <!-- ─── 1b. SLO & ERROR BUDGET  (GCP Cloud Monitoring) ───────────────── -->
836:  <!-- ─── 3b. UPTIME CHECKS (GCP Uptime Monitoring) ─────────────────────── -->
1031:  <!-- ─── 7b. RECOMMENDATIONS (GCP Active Assist) ──────────────────────── -->
```

- [ ] **Step 2: Delete the §1b SLO section**

Open `backend/monitor/static/index.html`. Find:

```
  <!-- ─── 1b. SLO & ERROR BUDGET  (GCP Cloud Monitoring) ───────────────── -->
```

Delete every line from that comment up to (and including) the `</section>` that closes its `<section class="card ...">`. This section spans until approximately:

```
  </section>


  <!-- ─── 2. SERVICE HEALTH GRID ───────────────────────────────────────── -->
```

Keep the `<!-- ─── 2. SERVICE HEALTH GRID ... -->` comment line as the next line.

To verify the range before deleting, use:

```bash
sed -n '651,/SERVICE HEALTH GRID/p' backend/monitor/static/index.html | head -85
```

Delete the range from the `<!-- ─── 1b` line up to (but not including) the next `<!-- ─── 2.` marker.

- [ ] **Step 3: Delete the §3b UPTIME CHECKS section**

Same pattern. Find:

```
  <!-- ─── 3b. UPTIME CHECKS (GCP Uptime Monitoring) ─────────────────────── -->
```

Delete from there up to (but not including) the next `<!-- ─── 4.` or `<!-- ─── 5.` section marker (the adjacent full numbered section — likely §4 ARQ WORKER which doesn't have a `b` variant, or §5 STORAGE).

Verify next marker with:

```bash
grep -nE '^  <!-- ─── [0-9]+[a-z]?\.' backend/monitor/static/index.html | head -20
```

- [ ] **Step 4: Delete the §7b RECOMMENDATIONS section**

Same pattern. Find:

```
  <!-- ─── 7b. RECOMMENDATIONS (GCP Active Assist) ──────────────────────── -->
```

Delete from there up to (but not including) the next `<!-- ─── 8.` marker or the `<!-- ─── 9.` RECENT LOGS marker, whichever comes first.

- [ ] **Step 5: Confirm no dangling references**

```bash
grep -n 'slo\|uptime\|reco\|recommendations' backend/monitor/static/index.html
```

The only remaining matches should be inside `genDataMock()` (the retained dev fallback) + any innocuous prose. No `id="reco-grid"`, `id="uptime-rows"`, `id="slo-..."`, `id="inc-count"`, `id="reco-count"` etc outside the mock function.

If any of those IDs still exist outside `genDataMock`, delete those lines too.

- [ ] **Step 6: Open the HTML in a local browser (optional smoke)**

Open `backend/monitor/static/index.html` directly in a browser (File → Open). The dashboard should render without errors — the three deleted sections are gone, the remaining sections render with mock data from `genDataMock` (dev fallback, still lives).

- [ ] **Step 7: Commit**

```bash
git add backend/monitor/static/index.html
git commit -m "$(cat <<'EOF'
[backend] AST-58 delete three always-mock dashboard sections

- §1b SLO & Error Budget: synthesized error-budget grid, never backed.
- §3b Uptime Checks: 5 region probes that never fire (we don't run
  external synthetic monitoring on the solo-dev $0 stack).
- §7b Recommendations: 4 static advisory cards that never change.

Leaving these panels on a dashboard we otherwise trust erodes trust
in everything else. Real implementations can return later under their
own tickets when backed by live data.

No renderers to remove — all three sections were static HTML populated
inline via the mock generator; my real /metrics pipeline didn't touch
them. genDataMock() stays (unused but harmless dev fallback).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Container-ID copy pills from real state

**Files:**
- Modify: `backend/monitor/static/index.html`

`renderServices` hardcodes per-card copy pills with a fake ID like `'abc'+s.name.slice(0,2)+'f9d1b2'`. Each ServiceBlock already has a real `container_id` from docker-py; surface it.

- [ ] **Step 1: Find the current hardcoded pill logic**

```bash
grep -n "ab12cd34ef56\|f9d1b2" backend/monitor/static/index.html
```

Expected: one hit inside `renderServices` at around line 1535 (line numbers may have shifted from Task 2's deletions).

- [ ] **Step 2: Edit `renderServices`**

Find this line (inside the `renderServices` function's template literal):

```html
        <span class="copy" data-copy="${s.name === 'certbot' ? 'ab12cd34ef56' : 'abc'+s.name.slice(0,2)+'f9d1b2'}">${s.name === 'certbot' ? 'ab12cd34ef56' : 'abc'+s.name.slice(0,2)+'f9d1b2'} <svg
```

Replace with:

```html
        <span class="copy" data-copy="${s.container_id || ''}">${(s.container_id || '').slice(0,12)} <svg
```

This displays the first 12 chars of the real docker short container ID (matches the handoff's visual length) and copies the full ID on click.

- [ ] **Step 3: Quick visual smoke (optional)**

Open `backend/monitor/static/index.html` in a browser. The services grid should show short container IDs (e.g. `a7c3e9f0b2d1`) in the copy pills — different for each card — because the mock `genDataMock` also populates `container_id` (check that). If mock doesn't populate it, pill shows empty string and click copies empty — that's fine; real data will fill it in prod.

- [ ] **Step 4: Commit**

```bash
git add backend/monitor/static/index.html
git commit -m "$(cat <<'EOF'
[backend] AST-58 real container-ID copy pills

renderServices was using hardcoded per-service pseudo-IDs
('abc'+name.slice(0,2)+'f9d1b2' for most, 'ab12cd34ef56' for certbot).
/metrics already returns the real docker short-id on every ServiceBlock.
Surface it: display first 12 chars, copy full id on click.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2 — renderCert + renderCost

### Task 4: `renderCert(d.cert)` with color-coded days-left

**Files:**
- Modify: `backend/monitor/static/index.html` (cert section DOM ids + renderCert function + renderAll wiring)

Cert card is static HTML — domain, issuer, dates, days-left are hardcoded. `/metrics` already returns everything. Wire up a renderer.

- [ ] **Step 1: Locate the cert card + find existing DOM ids**

```bash
grep -n 'sec-cert\|CERTIFICATE\|days remaining\|fullchain\|Let.s Encrypt' backend/monitor/static/index.html | head -20
```

The card is the `<div class="section-head" id="sec-cert">` block from AST-57 + the following `<section>`. Note any existing `id=` attributes inside that section — likely NONE (the cert card was fully static).

- [ ] **Step 2: Add DOM ids to cert card cells**

Inside the `<section>` following `<div class="section-head" id="sec-cert">`, find the labels and values. The handoff has rows like:

```html
<div class="kv"><span class="k">domain</span><span class="v mono">astral-reader.duckdns.org</span></div>
<div class="kv"><span class="k">issuer</span><span class="v">Let's Encrypt R11</span></div>
<div class="kv"><span class="k">not before</span><span class="v mono">...</span></div>
<div class="kv"><span class="k">not after</span><span class="v mono">...</span></div>
<div class="kv"><span class="k">last renew</span><span class="v">...</span></div>
```

Plus the big days-remaining number on the right side of the card.

Add `id` attributes to the value spans so `renderCert` can write into them. Target the value-span elements (the `class="v"` side) and add:

- `id="cert-domain"` on the domain value span
- `id="cert-issuer"` on the issuer value span
- `id="cert-not-before"` on the not-before value span
- `id="cert-not-after"` on the not-after value span
- `id="cert-last-renew"` on the last-renew value span (contains both status badge + timestamp)
- `id="cert-days-left"` on the big days-remaining number element
- `id="cert-days-left-label"` on the "days remaining" label (for potential color class swap)

If the handoff HTML has slightly different structure (e.g. no `<div class="kv">` — direct `<dt>/<dd>` pairs or a `<table>`), add the ids to whichever inner element holds the value text. Match the existing structure; don't restructure.

- [ ] **Step 3: Add `renderCert` function**

In the JS section, find the block of `render*` functions (`renderServices`, `renderRequests`, etc.). After `renderBackups` and before `renderLogs`, add:

```js
function renderCert(){
  setDegradedDot('sec-cert', STATE.data.cert_meta);
  const c = STATE.data.cert;
  if(!c) return;

  const set = (id, val) => {
    const el = document.getElementById(id);
    if(el && val != null) el.textContent = val;
  };

  set('cert-domain',     c.domain || '—');
  set('cert-issuer',     c.issuer || '—');
  set('cert-not-before', c.not_before ? new Date(c.not_before).toUTCString().replace('GMT','UTC') : '—');
  set('cert-not-after',  c.not_after  ? new Date(c.not_after).toUTCString().replace('GMT','UTC')  : '—');

  const renew = c.last_renew || {};
  const renewText = renew.at
    ? `${renew.status.toUpperCase()}  ${new Date(renew.at).toUTCString().replace('GMT','UTC')}`
    : (renew.status ? renew.status.toUpperCase() : '—');
  set('cert-last-renew', renewText);

  // Big days-remaining number with color band
  const dEl = document.getElementById('cert-days-left');
  if(dEl){
    const d = c.days_left;
    if(d == null){
      dEl.textContent = '—';
      dEl.style.color = 'var(--muted)';
    } else {
      dEl.textContent = d;
      dEl.style.color = d > 30 ? 'var(--success)' : (d >= 14 ? 'var(--warning)' : 'var(--error)');
    }
  }
}
```

- [ ] **Step 4: Wire `renderCert` into `renderAll`**

Find:

```js
function renderAll(){
  renderServices();
  renderRequests();
  renderArq();
  renderStorage();
  renderBackups();
  renderLogs();
```

Add `renderCert();` right before `renderLogs();`:

```js
function renderAll(){
  renderServices();
  renderRequests();
  renderArq();
  renderStorage();
  renderBackups();
  renderCert();
  renderLogs();
```

The `setDegradedDot('sec-cert', STATE.data.cert_meta)` call I added to the bottom of `renderAll()` in AST-57 is now duplicated — remove it from `renderAll` (it's inside `renderCert` now). Find and delete:

```js
  setDegradedDot('sec-cert',     STATE.data.cert_meta);
```

(Only the `sec-cert` line — leave the other setDegradedDot calls intact.)

- [ ] **Step 5: Commit**

```bash
git add backend/monitor/static/index.html
git commit -m "$(cat <<'EOF'
[backend] AST-58 renderCert — wire live cert data + color-coded days-left

/metrics.cert (domain, issuer, not_before, not_after, days_left,
last_renew) was present since AST-57 but no renderer consumed it —
cert card was static HTML. Add id attrs on the card cells, add
renderCert() that writes them, color days_left green >30 / amber
14–30 / red <14. Invoked from renderAll(). setDegradedDot('sec-cert')
moved from renderAll's trailing block into renderCert where it belongs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `renderCost(d.cost)` + APPROACHING CAP badge

**Files:**
- Modify: `backend/monitor/static/index.html` (cost card DOM ids + renderCost function + renderAll rewire)

Cost tripwire card: `4/4 ocpu`, `24/24 GB RAM`, `152/200 GB block vol`, `0.18/10 TB egress` are all **static HTML values**. Only the egress gauge width updates (my AST-57 code). Take over everything.

- [ ] **Step 1: Find existing cost card IDs**

```bash
grep -nE 'id="(ocpu|ram|vol|egress|cost|gauge)' backend/monitor/static/index.html | head -20
```

You'll see at least:
- `id="egress-used"`, `id="egress-forecast"`, `id="gauge-egress"`, `id="gauge-vol"` (from handoff)
- `id="sec-cost"` (from AST-57)

- [ ] **Step 2: Add missing IDs to cost card**

Inside the cost tripwire card (after `<div class="section-head" id="sec-cost">` and before the next section head), find the 4 gauge rows and the $spend block. Ensure each dynamic element has an `id`. The handoff has:

- A1 OCPU row: `4 / 4` — add `id="ocpu-used"` on the used number and `id="ocpu-cap"` on the cap number; `id="gauge-ocpu"` on the bar's inner `<span>` (the width-animated element).
- A1 RAM row: `24 / 24 GB` — `id="ram-used"`, `id="ram-cap"`, `id="gauge-ram"`.
- Block Volume row: `152 / 200 GB` — `id="vol-used"`, `id="vol-cap"`, `id="gauge-vol"` (already exists in handoff).
- Egress row: `0.18 / 10.00 TB` — `id="egress-used"` (exists), `id="egress-cap"` (may not exist — add), `id="gauge-egress"` (exists).
- $spend block: `$0.00 / $1.00` — `id="cost-spend-mtd"`, `id="cost-spend-budget"`. If there's a forecast line, `id="cost-spend-forecast"`.

If the handoff's exact DOM shape differs (e.g. bars may use `<div class="bar">` with a child `<span>` for fill), add IDs on whichever element controls the width. Don't restructure the DOM.

- [ ] **Step 3: Add `renderCost` function**

Near `renderCert` (which you just added), insert:

```js
function renderCost(){
  setDegradedDot('sec-cost', STATE.data.cost_meta);
  const c = STATE.data.cost;
  if(!c) return;
  const af = c.always_free || {};

  const set = (id, val) => {
    const el = document.getElementById(id);
    if(el && val != null) el.textContent = val;
  };

  // Spend block
  set('cost-spend-mtd',      '$' + Number(c.month_to_date || 0).toFixed(2));
  set('cost-spend-budget',   '$' + Number(c.budget || 0).toFixed(2));
  set('cost-spend-forecast', '$' + Number(c.forecast || 0).toFixed(2));

  // Gauges — each entry is [used-id, cap-id, gauge-fill-id, usageObj, format]
  const rows = [
    ['ocpu-used',   'ocpu-cap',   'gauge-ocpu',   af.a1_ocpu,       v => String(Math.round(v))],
    ['ram-used',    'ram-cap',    'gauge-ram',    af.a1_ram_gb,     v => String(Math.round(v))],
    ['vol-used',    'vol-cap',    'gauge-vol',    af.block_vol_gb,  v => String(Math.round(v))],
    ['egress-used', 'egress-cap', 'gauge-egress', af.egress_tb,     v => Number(v).toFixed(2)],
  ];

  let worstPct = 0;
  for(const [usedId, capId, gaugeId, usage, fmt] of rows){
    if(!usage) continue;
    set(usedId, fmt(usage.used));
    set(capId,  fmt(usage.cap));
    const pct = usage.cap > 0 ? (usage.used / usage.cap) * 100 : 0;
    worstPct = Math.max(worstPct, pct);
    const gauge = document.getElementById(gaugeId);
    if(gauge){ gauge.style.width = Math.min(100, pct).toFixed(1) + '%'; }
  }

  // Section header badge — escalate from WITHIN CAPS to APPROACHING CAP at 80%
  const head = document.getElementById('sec-cost');
  if(head){
    const badge = head.querySelector('.badge');
    if(badge){
      if(worstPct >= 80){
        badge.className = 'badge badge-warn';
        const dot = badge.querySelector('.dot'); if(dot) dot.className = 'dot warn';
        const txt = badge.childNodes[badge.childNodes.length - 1];
        if(txt && txt.nodeType === Node.TEXT_NODE) txt.nodeValue = 'APPROACHING CAP';
      } else {
        badge.className = 'badge badge-ok';
        const dot = badge.querySelector('.dot'); if(dot) dot.className = 'dot ok';
        const txt = badge.childNodes[badge.childNodes.length - 1];
        if(txt && txt.nodeType === Node.TEXT_NODE) txt.nodeValue = 'WITHIN CAPS';
      }
    }
  }
}
```

- [ ] **Step 4: Rewire `renderAll`**

Find the current `renderAll` body. Remove these 4 lines (they're now handled inside `renderCost`):

```js
  // egress gauge
  const eg = STATE.data.cost.always_free.egress_tb;
  document.getElementById('egress-used').textContent = eg.used.toFixed(2);
  document.getElementById('egress-forecast').textContent = (eg.used*1.55).toFixed(2);
  document.getElementById('gauge-egress').style.width = (eg.used/eg.cap*100).toFixed(1)+'%';
```

Also remove (from AST-57):

```js
  setDegradedDot('sec-cost',     STATE.data.cost_meta);
```

Add `renderCost();` at the top of `renderAll`, right before `renderServices()`:

```js
function renderAll(){
  renderCost();
  renderServices();
  renderRequests();
  renderArq();
  renderStorage();
  renderBackups();
  renderCert();
  renderLogs();
  // remaining setDegradedDot calls for services/requests/arq/storage/backups/logs stay
  ...
  document.getElementById('asof').textContent = new Date(STATE.data.generated_at).toUTCString().replace('GMT','UTC');
}
```

- [ ] **Step 5: Quick visual smoke**

Open `backend/monitor/static/index.html` in a browser. All 4 cost gauges should reflect the mock `always_free` values and animate in. The `WITHIN CAPS` badge stays green because mock egress is 0.18/10 TB (< 80%).

- [ ] **Step 6: Commit**

```bash
git add backend/monitor/static/index.html
git commit -m "$(cat <<'EOF'
[backend] AST-58 renderCost — drive all 5 gauges + APPROACHING CAP badge

AST-57 only dynamically updated the egress gauge. OCPU (4/4), RAM
(24/24), and block-vol (152/200) were hardcoded in static HTML —
would never reflect reality if the monitor deployed on a differently-
shaped VM, and block-vol already drifts as /mnt/astral-media grows.

Take over: renderCost() reads d.cost.always_free.* + d.cost.* and
writes the used/cap numbers + gauge widths for all 5 dimensions.
Worst-case usage % triggers a badge swap from WITHIN CAPS (green) to
APPROACHING CAP (amber) at 80%. Removes the inline egress-gauge
logic from renderAll (now owned by renderCost).

setDegradedDot('sec-cost') moves into renderCost alongside the other
section-scoped degraded dots.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3 — Real-data collectors

### Task 6: `1m_api` window in `nginx_access_sampler` + fastapi reads it

**Files:**
- Modify: `backend/monitor/bg.py`
- Create: `backend/monitor/tests/test_nginx_access_sampler_1m_api.py`

`_fetch_service_extra("fastapi")` currently reads `NGINX_WINDOW_CACHE["1h"]` — a 1-hour rolling average. Useless as "current rps". Emit a parallel 60s window filtered to `/api/*` paths.

- [ ] **Step 1: Write the failing test**

Create `backend/monitor/tests/test_nginx_access_sampler_1m_api.py`:

```python
"""nginx_access_sampler emits a '1m_api' window filtered to /api/* paths.

The existing 5 windows (1h, 6h, 24h, 7d, 30d) count every request that
reaches nginx. '1m_api' is a narrower view used by the fastapi service
card footer to show live RPS for the prod API specifically.
"""
import pytest

from monitor.bg import _compute_window, _WINDOWS_S


def test_compute_window_api_filter():
    records = [
        # Non-api requests — included in normal windows, excluded from 1m_api
        {"ts_ms": 1000, "method": "GET", "path": "/monitor/",    "status": 200, "rt_ms": 12},
        {"ts_ms": 2000, "method": "GET", "path": "/metrics",      "status": 200, "rt_ms": 8},
        {"ts_ms": 3000, "method": "GET", "path": "/static/foo.png","status": 200, "rt_ms": 6},
        # api/* requests — both included and counted in 1m_api
        {"ts_ms": 4000, "method": "GET", "path": "/api/v1/comics","status": 200, "rt_ms": 40},
        {"ts_ms": 5000, "method": "GET", "path": "/api/v1/health","status": 200, "rt_ms": 4},
    ]
    # Simulate the filter the sampler will apply before calling _compute_window
    api_only = [r for r in records if r["path"].startswith("/api/")]
    out = _compute_window(api_only, "1m_api")
    assert out["status_codes"]["2xx"] == 2
    assert out["status_codes"]["5xx"] == 0
    # All non-api paths excluded
    assert all(e["path"].startswith("/api/") for e in out["slowest"])


def test_1m_api_registered_in_windows():
    assert "1m_api" in _WINDOWS_S
    # 60-second window
    assert _WINDOWS_S["1m_api"] == 60
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd backend && python3 -m pytest monitor/tests/test_nginx_access_sampler_1m_api.py -v
```

Expected: `test_1m_api_registered_in_windows` FAILS with `assert '1m_api' in _WINDOWS_S`.

- [ ] **Step 3: Register the new window**

In `backend/monitor/bg.py`, find:

```python
_WINDOWS_S = {"1h": 3600, "6h": 21600, "24h": 86400, "7d": 604800, "30d": 2592000}
```

Add the `1m_api` entry:

```python
_WINDOWS_S = {"1h": 3600, "6h": 21600, "24h": 86400, "7d": 604800, "30d": 2592000,
              "1m_api": 60}
```

- [ ] **Step 4: Filter + compute the `1m_api` window in `nginx_access_sampler`**

Find the `nginx_access_sampler` loop body. The current shape is:

```python
            for w, seconds in _WINDOWS_S.items():
                cutoff = now_ms - seconds * 1000
                window_records = [r for r in all_records if r["ts_ms"] >= cutoff]
                NGINX_WINDOW_CACHE[w] = _compute_window(window_records, w)
```

Replace with:

```python
            for w, seconds in _WINDOWS_S.items():
                cutoff = now_ms - seconds * 1000
                window_records = [r for r in all_records if r["ts_ms"] >= cutoff]
                # 1m_api: narrow to prod API paths only — used by the
                # fastapi service card for live RPS. Other windows stay
                # full-traffic (they drive the Request Metrics chart).
                if w == "1m_api":
                    window_records = [r for r in window_records
                                      if r["path"].startswith("/api/")]
                NGINX_WINDOW_CACHE[w] = _compute_window(window_records, w)
```

- [ ] **Step 5: Point fastapi extras at the new window**

Find `_fetch_service_extra`. Locate the `if svc == "fastapi":` branch. Currently:

```python
        if svc == "fastapi":
            import os as _os
            workers = int(_os.getenv("UVICORN_WORKERS", "1"))
            cached = NGINX_WINDOW_CACHE.get("1h", {})
            rps_pts = cached.get("series_rps", [])
            rps = float(rps_pts[-1][1]) if rps_pts else 0.0
            return {"workers": workers, "rps": f"{rps:.2f}"}
```

Replace with:

```python
        if svc == "fastapi":
            import os as _os
            workers = int(_os.getenv("UVICORN_WORKERS", "1"))
            # Use the 60-second /api/* window so rps is genuinely "last
            # minute of prod API traffic" rather than a 1-hour average.
            cached = NGINX_WINDOW_CACHE.get("1m_api", {})
            sc = cached.get("status_codes", {}) or {}
            total = sum(int(sc.get(k, 0) or 0) for k in ("2xx", "3xx", "4xx", "5xx"))
            rps = total / 60.0  # averaged over the 60 s window
            return {"workers": workers, "rps": f"{rps:.2f}"}
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd backend && python3 -m pytest monitor/tests/test_nginx_access_sampler_1m_api.py -v
```

Expected: 2 passed.

- [ ] **Step 7: Full suite regression**

```bash
cd backend && python3 -m pytest monitor/tests/ -q
```

Expected: all tests pass (was 43 after Task 1, now 45 after Task 6).

- [ ] **Step 8: Commit**

```bash
git add backend/monitor/bg.py backend/monitor/tests/test_nginx_access_sampler_1m_api.py
git commit -m "$(cat <<'EOF'
[backend] AST-58 narrow fastapi rps to last-60s /api/* traffic

Was reading the 1h window's last bucket — effectively a 1-hour rolling
average called "current rps". Now nginx_access_sampler also emits a
1m_api window: last 60 seconds, path filter /api/*, sharing the same
shape as the other windows. _fetch_service_extra("fastapi") reads it
and averages over 60 s so the fastapi card footer reflects actual
live API load.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: `_nginx_stub` scraper helper

**Files:**
- Create: `backend/monitor/collectors/_nginx_stub.py`
- Create: `backend/monitor/tests/collectors/test_nginx_stub.py`

Thin async helper: GET `http://nginx/nginx_status`, parse the 7-line text response, return a dict.

- [ ] **Step 1: Write the failing test**

Create `backend/monitor/tests/collectors/test_nginx_stub.py`:

```python
"""_nginx_stub parses the stub_status text format + fetches via httpx."""
from unittest.mock import AsyncMock, MagicMock

import pytest

from monitor.collectors import _nginx_stub as mod


STUB_SAMPLE = """Active connections: 7 
server accepts handled requests
 42 42 118
Reading: 0 Writing: 1 Waiting: 6 
"""


def test_parse_stub_text():
    out = mod.parse_stub(STUB_SAMPLE)
    assert out == {
        "active_connections": 7,
        "accepts": 42,
        "handled": 42,
        "total_requests": 118,
        "reading": 0,
        "writing": 1,
        "waiting": 6,
    }


def test_parse_handles_missing_third_line():
    bad = "Active connections: 3 \nReading: 0 Writing: 0 Waiting: 3\n"
    out = mod.parse_stub(bad)
    assert out == {}


@pytest.mark.asyncio
async def test_fetch_stub_success(monkeypatch):
    # Mock the httpx.AsyncClient context manager
    fake_response = MagicMock()
    fake_response.text = STUB_SAMPLE
    fake_response.status_code = 200
    fake_response.raise_for_status = MagicMock()

    class FakeClient:
        async def __aenter__(self):
            return self
        async def __aexit__(self, *args):
            return False
        async def get(self, url, timeout=None):
            return fake_response

    monkeypatch.setattr(mod.httpx, "AsyncClient", lambda *a, **kw: FakeClient())

    result = await mod.fetch_stub()
    assert result["active_connections"] == 7
    assert result["total_requests"] == 118


@pytest.mark.asyncio
async def test_fetch_stub_network_error_returns_empty(monkeypatch):
    class FakeClient:
        async def __aenter__(self):
            return self
        async def __aexit__(self, *args):
            return False
        async def get(self, url, timeout=None):
            raise ConnectionError("refused")

    monkeypatch.setattr(mod.httpx, "AsyncClient", lambda *a, **kw: FakeClient())

    result = await mod.fetch_stub()
    assert result == {}
```

- [ ] **Step 2: Run to verify fail**

```bash
cd backend && python3 -m pytest monitor/tests/collectors/test_nginx_stub.py -v
```

Expected: `ModuleNotFoundError: No module named 'monitor.collectors._nginx_stub'`.

- [ ] **Step 3: Implement `_nginx_stub.py`**

Create `backend/monitor/collectors/_nginx_stub.py`:

```python
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
from typing import Optional

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
        # The counts line is the line right after "server accepts handled requests"
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
```

- [ ] **Step 4: Run to verify pass**

```bash
cd backend && python3 -m pytest monitor/tests/collectors/test_nginx_stub.py -v
```

Expected: 4 passed.

- [ ] **Step 5: Wire into `_fetch_service_extra("nginx")`**

In `backend/monitor/bg.py`, find the `if svc == "nginx":` branch inside `_fetch_service_extra`. Currently:

```python
        if svc == "nginx":
            cached = NGINX_WINDOW_CACHE.get("1h", {})
            rps_pts = cached.get("series_rps", [])
            last_rps = float(rps_pts[-1][1]) if rps_pts else 0.0
            # Active connections isn't available without the nginx stub_status
            # module; use last-bucket rps as a rough "in-flight" proxy.
            sc = cached.get("status_codes", {}) or {}
            total = sum(int(sc.get(k, 0) or 0) for k in ("2xx", "3xx", "4xx", "5xx"))
            return {
                "active_connections": max(1, int(round(last_rps))),
                "reqs_total": total,
            }
```

Replace with:

```python
        if svc == "nginx":
            # Prefer real stub_status data; fall back to the 1h window
            # approximation if the scrape fails (stub_status not mounted,
            # nginx down, etc.).
            from monitor.collectors import _nginx_stub
            stub = await _nginx_stub.fetch_stub()
            if stub:
                return {
                    "active_connections": stub["active_connections"],
                    "reqs_total":         stub["total_requests"],
                }
            cached = NGINX_WINDOW_CACHE.get("1h", {})
            sc = cached.get("status_codes", {}) or {}
            total = sum(int(sc.get(k, 0) or 0) for k in ("2xx", "3xx", "4xx", "5xx"))
            return {"active_connections": 0, "reqs_total": total}
```

- [ ] **Step 6: Full suite regression**

```bash
cd backend && python3 -m pytest monitor/tests/ -q
```

Expected: all tests pass (49 now).

- [ ] **Step 7: Commit**

```bash
git add backend/monitor/collectors/_nginx_stub.py backend/monitor/tests/collectors/test_nginx_stub.py backend/monitor/bg.py
git commit -m "$(cat <<'EOF'
[backend] AST-58 real nginx active_connections via stub_status

New thin helper _nginx_stub.py: async GET http://nginx/nginx_status,
parse the 7-line text format into a flat dict. _fetch_service_extra
for the nginx service now prefers real stub data (active_connections,
total_requests) with graceful fallback to the 1h-window approximation
when the scrape fails (stub location not wired, nginx down, etc.).

Nginx-side location block for /nginx_status ships in the next commit
so this will fall back until then.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: nginx.conf — `location = /nginx_status`

**Files:**
- Modify: `backend/nginx/nginx.conf`

Expose `stub_status` on an internal-only path. `allow 172.19.0.0/16; deny all;` restricts to the compose network — the monitor is the only consumer.

- [ ] **Step 1: Edit `backend/nginx/nginx.conf`**

Find the existing `server { listen 443 ssl;` block. Inside it, right after the `location /metrics` block, add:

```nginx
        # Internal-only nginx runtime stats for the monitor service.
        # compose network 172.19.0.0/16 — no auth_basic, relying on
        # network isolation (deny all for anyone outside the subnet).
        location = /nginx_status {
            stub_status;
            allow 172.19.0.0/16;
            deny all;
            access_log off;
        }
```

The `access_log off;` prevents the monitor's scrape from polluting `/api/*` rps counts.

- [ ] **Step 2: Validate nginx syntax**

```bash
cd backend
docker run --rm -v "$(pwd)/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" \
           -v "$(pwd)/nginx/htpasswd:/etc/nginx/htpasswd:ro" \
           nginx:1.25-alpine nginx -t
```

(The `stub_status` directive requires the module — included in the official `nginx:1.25-alpine` image by default; no build-time flag.)

Expected:
```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

(Warnings about unresolvable upstreams at `-t` time are expected — nginx only resolves them via docker DNS at runtime.)

- [ ] **Step 3: Commit**

```bash
git add backend/nginx/nginx.conf
git commit -m "$(cat <<'EOF'
[backend] AST-58 nginx: expose stub_status on /nginx_status

Internal-only endpoint for the monitor service's nginx card. Network-
gated with allow 172.19.0.0/16 + deny all — the compose subnet is
the only consumer, and no auth_basic overhead on every poll.
access_log off; so the monitor's scrape doesn't inflate /api/* rps
counts in the Request Metrics window.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Real egress via OCI Usage API

**Files:**
- Modify: `backend/monitor/collectors/cost.py`
- Create: `backend/monitor/tests/collectors/test_cost_egress.py`
- Modify: `.env.example` (document optional OCI_USAGE_API_ENABLED flag)

The `egress_tb.used: 0.18` was a stub. Real egress comes from OCI Usage API `request_summarized_usages` with `granularity=MONTHLY, query_type=USAGE`, filtered to the Networking service's outbound-transfer sku.

- [ ] **Step 1: Write the failing test**

Create `backend/monitor/tests/collectors/test_cost_egress.py`:

```python
"""cost._fetch_egress: OCI Usage API mocked, returns TB used this month."""
from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest

from monitor.collectors import cost as cost_mod


@pytest.mark.asyncio
async def test_fetch_egress_sums_networking_items(monkeypatch):
    # OCI Usage API response shape: resp.data.items is a list of UsageSummary
    # objects; each has .service (str) and .computed_quantity (float, in GB).
    def _item(service, gb):
        i = MagicMock()
        i.service = service
        i.computed_quantity = gb
        i.sku_part_number = ""
        return i

    fake_resp = MagicMock()
    fake_resp.data.items = [
        _item("Networking",    1500.0),   # 1.5 TB outbound
        _item("Compute",       9000.0),   # ignored
        _item("Networking",    250.0),    # 250 GB — another outbound line item
        _item("Object Storage", 50.0),    # ignored
    ]

    async def _mock_call():
        return fake_resp

    monkeypatch.setattr(cost_mod, "_call_usage_api", _mock_call)

    # Required env
    monkeypatch.setenv("OCI_TENANCY_OCID", "ocid1.tenancy.oc1..fake")

    tb = await cost_mod._fetch_egress()
    assert tb == pytest.approx((1500 + 250) / 1024, rel=1e-3)  # ~1.709 TB


@pytest.mark.asyncio
async def test_fetch_egress_returns_none_on_error(monkeypatch):
    async def _boom():
        raise RuntimeError("IMDS unreachable")
    monkeypatch.setattr(cost_mod, "_call_usage_api", _boom)
    monkeypatch.setenv("OCI_TENANCY_OCID", "ocid1.tenancy.oc1..fake")

    tb = await cost_mod._fetch_egress()
    assert tb is None


@pytest.mark.asyncio
async def test_fetch_egress_no_tenancy_env(monkeypatch):
    monkeypatch.delenv("OCI_TENANCY_OCID", raising=False)
    tb = await cost_mod._fetch_egress()
    assert tb is None
```

- [ ] **Step 2: Run to verify fail**

```bash
cd backend && python3 -m pytest monitor/tests/collectors/test_cost_egress.py -v
```

Expected: `AttributeError: module 'monitor.collectors.cost' has no attribute '_fetch_egress'`.

- [ ] **Step 3: Implement `_fetch_egress` in `cost.py`**

Open `backend/monitor/collectors/cost.py`. Currently `_fetch_always_free()` hardcodes `egress_tb: {"used": 0.18, ...}`. Change to:

**3a.** Add `_fetch_egress()` + `_call_usage_api()` at module scope (near `_fetch_budget`):

```python
async def _call_usage_api():
    """OCI Usage API round-trip via instance-principal signer. Sync call
    wrapped in to_thread because the SDK is blocking."""
    def _sync():
        import oci
        from datetime import datetime, timezone, timedelta

        tenancy = os.getenv("OCI_TENANCY_OCID")
        if not tenancy:
            raise RuntimeError("OCI_TENANCY_OCID env var not set")

        signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
        client = oci.usage_api.UsageapiClient(config={}, signer=signer)

        now = datetime.now(timezone.utc)
        month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

        details = oci.usage_api.models.RequestSummarizedUsagesDetails(
            tenant_id=tenancy,
            time_usage_started=month_start,
            time_usage_ended=now,
            granularity="MONTHLY",
            query_type="USAGE",
            group_by=["service"],
        )
        return client.request_summarized_usages(details)

    return await asyncio.to_thread(_sync)


async def _fetch_egress() -> Optional[float]:
    """TB used on outbound networking this calendar month. None on failure."""
    if not os.getenv("OCI_TENANCY_OCID"):
        return None
    try:
        resp = await _call_usage_api()
        gb_total = 0.0
        for item in getattr(resp.data, "items", []) or []:
            svc = (getattr(item, "service", "") or "").lower()
            # Networking includes several sub-SKUs; we want the sum of all
            # "outbound" categories. Keep it simple: sum any line where
            # service == "Networking" (OCI's outbound transfer bills are
            # all under the Networking service family).
            if "networking" in svc:
                qty = float(getattr(item, "computed_quantity", 0.0) or 0.0)
                gb_total += qty
        return gb_total / 1024.0  # GB → TB
    except Exception as e:
        logger.debug("_fetch_egress failed: %s", e)
        return None
```

**3b.** Parallelize `collect()`. Currently:

```python
async def collect() -> CostBlock:
    budget = await _fetch_budget()
    af = await _fetch_always_free()
    ...
```

Change to:

```python
async def collect() -> CostBlock:
    # Budget + egress API calls run concurrently so cost collector
    # wall-time is max(budget, egress) rather than budget + egress.
    budget, egress_tb_used = await asyncio.gather(
        _fetch_budget(),
        _fetch_egress(),
        return_exceptions=False,
    )
    af = await _fetch_always_free(egress_tb_used=egress_tb_used)
    ...
```

**3c.** Thread the real egress value into `_fetch_always_free`. Currently:

```python
async def _fetch_always_free() -> dict:
    ...
    return {
        ...
        "egress_tb":     {"used": 0.18, "cap": 10, "unit": "TB"},
        ...
    }
```

Change signature + return:

```python
async def _fetch_always_free(egress_tb_used: Optional[float] = None) -> dict:
    ...
    # If Usage API returned None, fall back to 0 (degraded; UI shows real 0
    # rather than a lie). Real 0.xx rounding kept to 3 decimals.
    egress = round(egress_tb_used, 3) if egress_tb_used is not None else 0.0
    return {
        ...
        "egress_tb":     {"used": egress, "cap": 10, "unit": "TB"},
        ...
    }
```

- [ ] **Step 4: Run to verify tests pass**

```bash
cd backend && python3 -m pytest monitor/tests/collectors/test_cost_egress.py monitor/tests/collectors/test_cost.py -v
```

Expected: 3 new tests pass, existing 2 `test_cost.py` still pass (they mock `_fetch_budget` and `_fetch_always_free` — may need to also mock `_fetch_egress` now; check the existing test, add a mock if needed).

If `test_cost.py::test_collect_assembles_from_budget_api` now fails because `_fetch_egress` is trying to hit OCI: add one line before `monkeypatch.setattr(cost_mod, "_fetch_budget", _fb)` in that test:

```python
    async def _fegress():
        return 0.18
    monkeypatch.setattr(cost_mod, "_fetch_egress", _fegress)
```

- [ ] **Step 5: Full suite regression**

```bash
cd backend && python3 -m pytest monitor/tests/ -q
```

Expected: all pass (52 now: 43 + 2 [1m_api] + 4 [stub] + 3 [egress]).

- [ ] **Step 6: Document the new IAM policy in `.env.example`**

Append to `backend/.env.example`:

```
# OCI — budget tripwire and usage-reports read require:
#   Allow dynamic-group astral-a1-backup to read usage-budgets in tenancy
#   Allow dynamic-group astral-a1-backup to read usage-reports in tenancy
# (both scoped to tenancy; instance principal signer + monitor container only)
```

- [ ] **Step 7: Commit**

```bash
git add backend/monitor/collectors/cost.py backend/monitor/tests/collectors/test_cost_egress.py backend/monitor/tests/collectors/test_cost.py backend/.env.example
git commit -m "$(cat <<'EOF'
[backend] AST-58 real egress via OCI Usage API

Hardcoded egress_tb=0.18 in the cost collector was a stub. Now:

* new _fetch_egress() calls UsageapiClient.request_summarized_usages
  with granularity=MONTHLY, query_type=USAGE, group_by=service;
  sums 'Networking' line items' computed_quantity (GB), returns TB
* cost.collect() runs _fetch_budget and _fetch_egress concurrently
  via asyncio.gather so total wall-time is max(budget, egress)
* _fetch_always_free now takes egress_tb_used as an arg — reads real
  value, falls back to 0 (degraded) when the Usage API call failed

OCI IAM policy addition required (runbook, not repo):
  Allow dynamic-group astral-a1-backup to read usage-reports in tenancy
documented in backend/.env.example.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4 — Diagnose + fix empty Request Metrics

### Task 10: Investigate Request Metrics zero-data + apply fix

**Files:** depends on root cause. Candidate files:
- Modify (likely): `backend/monitor/static/index.html` (add "no traffic" placeholder in `renderRequests`)
- Modify (if volume/log_format drifted): `backend/nginx/nginx.conf` or `backend/docker-compose.yml`

This is a diagnostic task — 3 possible root causes identified in the spec. Check them in order; apply the fix matching whichever you hit.

- [ ] **Step 1: Volume-mount check**

SSH to the A1 and peek at what nginx is actually writing:

```bash
ssh -i ~/.ssh/astral_oci ubuntu@astral-reader.duckdns.org \
    'docker exec backend-nginx-1 wc -l /var/log/nginx/access.log && \
     docker exec backend-nginx-1 tail -5 /var/log/nginx/access.log'
```

**Expected if healthy**: nonzero line count + 5 lines that look like:

```
1.2.3.4 - astral [2026-04-21T15:30:05+00:00] "GET /metrics HTTP/1.1" 200 8234 rt=0.042 urt="0.040" "-" "Mozilla/5.0..."
```

**If file empty or missing**: nginx access_log directive isn't writing there. Check:

```bash
ssh -i ~/.ssh/astral_oci ubuntu@astral-reader.duckdns.org \
    'docker exec backend-nginx-1 nginx -T 2>&1 | grep -iE "access_log|log_format"'
```

Expected: `access_log /var/log/nginx/access.log astral;` and the `log_format astral '... rt=$request_time ...';` definition. If these are missing, the nginx.conf mount isn't live — verify:

```bash
ssh -i ~/.ssh/astral_oci ubuntu@astral-reader.duckdns.org \
    'docker inspect backend-nginx-1 --format "{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}"'
```

All four expected mounts must be present: `nginx.conf`, `htpasswd`, `letsencrypt`, `astral_media`, `nginx_access_logs`.

If the config or mount is wrong, `docker compose --env-file .env.oci up -d --force-recreate nginx` fixes it (Task 22 from AST-57 taught us `restart` doesn't re-read compose mounts).

- [ ] **Step 2: Log-format parse check**

With the log file populated, verify one line parses with the monitor's regex:

```bash
ssh -i ~/.ssh/astral_oci ubuntu@astral-reader.duckdns.org \
    'docker exec backend-astral_monitor-1 python3 -c "
import sys; sys.path.insert(0, \"/app\")
from monitor.bg import _parse_log_line
line = open(\"/var/log/nginx/access.log\").readline()
print(\"LINE:\", line.strip())
print(\"PARSED:\", _parse_log_line(line))
"'
```

Expected: `PARSED: {...}` with `method`, `path`, `status`, `rt_ms` keys. If `PARSED: None`, the log_format has drifted from `astral`. Compare the actual line shape to `_LOG_RE` in `backend/monitor/bg.py` and adjust whichever is wrong.

- [ ] **Step 3: Sampler cadence check**

Confirm `nginx_access_sampler` is running and has completed at least one tick:

```bash
ssh -i ~/.ssh/astral_oci ubuntu@astral-reader.duckdns.org \
    'docker exec backend-astral_monitor-1 python3 -c "
import sys; sys.path.insert(0, \"/app\")
from monitor.bg import NGINX_WINDOW_CACHE
for k, v in NGINX_WINDOW_CACHE.items():
    sc = v.get(\"status_codes\", {})
    print(f\"{k}: 2xx={sc.get(\\\"2xx\\\", 0)}  rps points={len(v.get(\\\"series_rps\\\", []))}\")
"'
```

Expected: non-empty `2xx` counts and rps series. If cache is empty on all windows, the sampler hasn't run yet (wait 60 s) or it crashed — check `docker compose logs astral_monitor --tail 40`.

- [ ] **Step 4: Add "no traffic" UI placeholder (always apply)**

Regardless of which fix was needed above, the UI should stop showing a flat chart at 0 when the window is genuinely empty. In `backend/monitor/static/index.html`, find `renderRequests`. Near the top:

```js
function renderRequests(){
  const r = STATE.data.requests;
  drawRequestChart(r.series_rps, r.series_p95_ms);
  document.getElementById('rps-now').textContent = r.series_rps.at(-1).toFixed(2);
  ...
```

Replace with:

```js
function renderRequests(){
  const r = STATE.data.requests;
  const sc = r.status_codes || {};
  const totalReqs = (sc['2xx']||0) + (sc['3xx']||0) + (sc['4xx']||0) + (sc['5xx']||0);
  const chartEl = document.getElementById('reqChart');

  if(totalReqs === 0){
    // No traffic in this window — show placeholder instead of a flat-zero chart.
    if(chartEl){
      chartEl.innerHTML = `<text x="50%" y="50%" text-anchor="middle"
        fill="var(--muted)" font-family="JetBrains Mono" font-size="12">
        (no traffic in this window)</text>`;
    }
    document.getElementById('rps-now').textContent = '0.00';
    document.getElementById('p95-now').innerHTML = `0<span class="text-muted text-sm ml-0.5">ms</span>`;
    document.getElementById('req-total').textContent = '0';
    document.getElementById('req-window').textContent = RANGE_LABELS[STATE.range];
    document.getElementById('sc-2').textContent = '0';
    document.getElementById('sc-3').textContent = '0';
    document.getElementById('sc-4').textContent = '0';
    document.getElementById('sc-5').textContent = '0';
    document.getElementById('statusBars').innerHTML = '';
    document.getElementById('slowest').innerHTML =
      '<tr><td colspan="3" class="text-muted mono text-[12px] py-3 text-center">no requests to rank</td></tr>';
    return;
  }

  drawRequestChart(r.series_rps, r.series_p95_ms);
  document.getElementById('rps-now').textContent = r.series_rps.at(-1).toFixed(2);
  ...
```

Keep the rest of the existing `renderRequests` body below the `...` unchanged.

- [ ] **Step 5: Regenerate traffic so the fix is visible**

On the A1:

```bash
ssh -i ~/.ssh/astral_oci ubuntu@astral-reader.duckdns.org \
    'for i in $(seq 1 10); do curl -sk https://astral-reader.duckdns.org/api/v1/health -o /dev/null; done'
```

Wait 60 s (one sampler tick), re-open the dashboard — Request Metrics should populate.

- [ ] **Step 6: Commit**

The commit scope depends on whether Step 1–3 required any backend fix. Common case (only UI placeholder):

```bash
git add backend/monitor/static/index.html
git commit -m "$(cat <<'EOF'
[backend] AST-58 Request Metrics placeholder when window is empty

When a window has zero parseable nginx access-log records,
renderRequests was drawing a flat-line chart with all zeros — looks
like the dashboard is broken even though it's just an idle system.
Now renders "(no traffic in this window)" inside the chart SVG plus
"no requests to rank" in the slowest-endpoints table when the
status-code sum is 0.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

If Step 1 revealed a volume or config drift that needed a compose/nginx edit, add those files to the commit and reword the message to reflect the actual fix.

---

## Phase 5 — Deploy + PR

### Task 11: Deploy to A1, add Usage API policy, smoke, open PR

**Files:**
- Modify: `CHANGELOG.md` (AST-58 entry)
- Runbook: OCI IAM policy update (not in repo)

- [ ] **Step 1: Append OCI policy statement**

From your laptop (OCI CLI configured in home region):

```bash
# Fetch the existing astral-monitor-policy id
TENANCY='ocid1.tenancy.oc1..aaaaaaaatjkppg2i7z3ad4itqk3u2lbvwqoglq254lcmjkd2zbmutvcw44lq'
POLICY_ID=$(oci --region us-sanjose-1 iam policy list \
    --compartment-id "$TENANCY" --all \
    --query 'data[?name==`astral-monitor-policy`].id | [0]' --raw-output)
echo "policy: $POLICY_ID"

# Read existing statements, append, update
oci --region us-sanjose-1 iam policy update \
    --policy-id "$POLICY_ID" \
    --statements '["Allow dynamic-group astral-a1-backup to read usage-budgets in tenancy","Allow dynamic-group astral-a1-backup to read usage-reports in tenancy"]' \
    --version-date "$(date -u +%Y-%m-%d)" \
    --force 2>&1 | head -30
```

Verify:

```bash
oci --region us-sanjose-1 iam policy get --policy-id "$POLICY_ID" \
    --query 'data.statements' --raw-output
```

Expected: 2 statements — one for `usage-budgets`, one for `usage-reports`.

- [ ] **Step 2: Pull + rebuild on the A1**

```bash
ssh -i ~/.ssh/astral_oci ubuntu@astral-reader.duckdns.org 'bash -s' <<'REMOTE'
set -e
cd /home/ubuntu/astral
git fetch origin
git checkout feature/ast-58-monitor-real-data-pass
git pull --ff-only 2>&1 | tail -2
cd backend
# Rebuild monitor (new httpx usage) + recreate nginx (new stub_status location)
docker compose --env-file .env.oci up -d --build astral_monitor 2>&1 | tail -4
docker compose --env-file .env.oci up -d --force-recreate nginx 2>&1 | tail -4
sleep 20
echo ""
echo "=== docker compose ps ==="
docker compose --env-file .env.oci ps
REMOTE
```

Expected: both services Up + healthy.

- [ ] **Step 3: Smoke-verify `/metrics` from inside the compose network**

```bash
ssh -i ~/.ssh/astral_oci ubuntu@astral-reader.duckdns.org 'bash -s' <<'REMOTE'
sleep 30  # let sampler + docker_sampler run a couple of cycles
docker exec backend-nginx-1 wget -qO- http://astral_monitor:8001/metrics | python3 -c "
import json, sys
d = json.load(sys.stdin)
print('services:', len(d.get('services', [])))
for s in d.get('services', []):
    print(f'  {s[\"name\"]:<12}  health={s.get(\"health\")}  extra={s.get(\"extra\")}')
print()
print('cost.always_free.egress_tb:', d['cost']['always_free']['egress_tb'])
print('cost.forecast: \$', d['cost']['forecast'])
print('cert.days_left:', d['cert']['days_left'])
print('requests.status_codes:', d['requests']['status_codes'])
nm = [k for k, v in d.items() if k.endswith('_meta') and v]
print('degraded:', nm or 'none')
"
REMOTE
```

Expected:
- All 6 services `health=healthy` (Task 1 fix)
- `extras` dict populated for every service (Task 7 + earlier)
- `egress_tb.used` is a real float, not 0.18 (Task 9)
- `cert.days_left` populated (AST-57 + Task 4 renders it)
- `requests.status_codes` non-zero (Task 10 or real traffic)
- No `_meta` degraded entries if all fetches succeeded

- [ ] **Step 4: Smoke externally**

From your laptop:

```bash
curl -sI -u astral:<pw> https://astral-reader.duckdns.org/monitor/ | head -3
# expected: HTTP/1.1 200 OK

curl -s -u astral:<pw> https://astral-reader.duckdns.org/metrics \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print('ok, egress TB:', d['cost']['always_free']['egress_tb']['used'])"
```

- [ ] **Step 5: Visual check from iPhone + desktop**

Open `https://astral-reader.duckdns.org/monitor/` on iPhone Safari and desktop Chrome. Verify:
- Services grid: all 6 show `UP` badges, container-ID pills show real IDs
- Cost tripwire: all 4 gauges render with real values, badge still `WITHIN CAPS`
- Request Metrics: either populated or shows the "(no traffic in this window)" placeholder
- ARQ, Storage, Backups: unchanged (still real)
- Certificate card: populated with real domain/issuer/dates + color-coded days
- Logs panel: flowing
- Footer timestamp: updates on manual refresh
- No SLO / Uptime Checks / Recommendations sections anywhere on the page

- [ ] **Step 6: Update CHANGELOG.md**

Add a new entry under today's date (`## 2026-04-21`) in the Backend section:

```markdown
- **AST-58** — Monitor dashboard real-data pass. Removed 3 always-mock sections (SLO, Uptime Checks, Recommendations). Added `renderCost` (drives all 5 Always-Free gauges + `WITHIN CAPS → APPROACHING CAP` badge at 80%) and `renderCert` (color-coded days-remaining: green >30, amber 14–30, red <14). Container-ID copy pills now use real `s.container_id`. Real egress via OCI Usage API (`request_summarized_usages`, granularity=MONTHLY, grouped by service — sums Networking line items). Real nginx `active_connections` + `total_requests` via new `location = /nginx_status` + `_nginx_stub` scraper. Fastapi rps narrowed from 1h average to last-60s `/api/*` via a new `1m_api` window in `nginx_access_sampler`. Fixed DOWN-badge false positives: containers without a compose healthcheck (redis, fastapi, arq_worker, nginx, certbot) now get `health=healthy` synthesized when their docker state is `running` — absence of a healthcheck isn't evidence of unhealthiness. Request Metrics panel now shows `(no traffic in this window)` instead of a flat-zero chart when status-code sum is 0. OCI IAM policy `astral-monitor-policy` gained one statement: `read usage-reports in tenancy`. 12 new unit tests (52 total). ([PR #NN](https://github.com/agenticCoder97/IosTestApp/pull/NN))
```

- [ ] **Step 7: Push + open PR**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git add CHANGELOG.md
git commit -m "[backend] AST-58 CHANGELOG entry

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push -u origin feature/ast-58-monitor-real-data-pass

gh pr create --base development --title "[backend] AST-58 monitor real-data pass" --body "$(cat <<'EOF'
## Summary

Closes the gap between AST-57's `/metrics` payload and what the UI actually renders. Every panel now shows live data or an explicit degraded marker. Three always-mock sections removed. Two real bugs discovered during AST-57 smoke testing fixed.

### Wiring
- `renderCert` — was static HTML; now reads `d.cert` with color-coded days-left
- `renderCost` — drives all 5 gauges + `APPROACHING CAP` badge at 80%
- Container-ID pills — real `s.container_id` instead of per-service pseudo-IDs

### Real data sources
- OCI Usage API (`request_summarized_usages`) → real monthly egress TB
- nginx `stub_status` → real `active_connections` / `total_requests`
- New `1m_api` window in `nginx_access_sampler` → real `/api/*` rps for the fastapi card

### Bug fixes
- Services without compose healthcheck blocks were reporting `health=None` → UI badge said DOWN. Now synthesize `healthy` when docker status is `running`.
- Request Metrics panel showed a flat-zero chart on empty windows. Now shows `(no traffic in this window)` placeholder.

### Removed
- §1b SLO & Error Budget — synthesized fake data
- §3b Uptime Checks — 5 region probes that never fire
- §7b Recommendations — 4 static advisory cards

Closes AST-58.

## Test plan
- [x] Unit: `cd backend && python3 -m pytest monitor/tests/` — 52 tests pass in <1 s.
- [x] OCI policy `astral-monitor-policy` appended with `read usage-reports in tenancy`.
- [x] A1 deploy: `docker compose --env-file .env.oci up -d --build astral_monitor` + `--force-recreate nginx`.
- [x] Smoke: `/metrics` returns live egress, all services `healthy`, request metrics populated.
- [x] Visual: iPhone + desktop — every card shows real data, no amber dots on healthy stack, three deleted sections gone.

Design spec: `docs/superpowers/specs/2026-04-21-ast58-monitor-real-data-pass-design.md`
Plan: `docs/superpowers/plans/2026-04-21-ast58-monitor-real-data-pass.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 8: Fill in the PR number in CHANGELOG**

After `gh pr create` returns the PR URL, edit `CHANGELOG.md` to replace `#NN` with the real PR number, then:

```bash
git add CHANGELOG.md
git commit --amend --no-edit
git push --force-with-lease
```

---

## Task Summary

| # | Task | Files |
|---|---|---|
| 0 | Linear + branch | — |
| 1 | Synthesize healthy status | bg.py + test_health_synthesis.py |
| 2 | Delete 3 mock sections | static/index.html |
| 3 | Real container-ID pills | static/index.html |
| 4 | renderCert + color-coded days | static/index.html |
| 5 | renderCost + APPROACHING CAP badge | static/index.html |
| 6 | 1m_api window + fastapi rps | bg.py + test_nginx_access_sampler_1m_api.py |
| 7 | _nginx_stub helper + nginx extras wiring | collectors/_nginx_stub.py + test + bg.py |
| 8 | nginx.conf stub_status location | nginx/nginx.conf |
| 9 | Real egress via OCI Usage API | collectors/cost.py + test_cost_egress.py + .env.example |
| 10 | Request Metrics diagnose + placeholder | static/index.html + possibly compose/nginx |
| 11 | Deploy + OCI policy + smoke + PR | CHANGELOG.md |

12 tasks, ~10 new unit tests (targeting 52 total), one-shot PR to `development`. Low deploy risk — monitor-only + nginx config.
