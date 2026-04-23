# Monitor Dashboard UI/UX Polish — AST-78 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a bundled front-end polish pass for the OCI monitor dashboard that closes AST-79 through AST-91 (12 Linear subissues) plus two scope extensions — relocating per-card refresh and adding a terminal-flip stub for AST-92.

**Architecture:** Single-PR frontend change touching only `backend/monitor/static/index.html` and `backend/monitor/static/controls.js`. Nine commits in sequence, each independently buildable and previewable via the existing `monitor-preview` launch config. One Python smoke test protects the markers in the final commit.

**Tech Stack:** Vanilla HTML/CSS/JS (no build step) • Tailwind utility classes via CDN • FastAPI backend (unchanged) • `python3 -m http.server`-style preview server at `scratchpad/monitor-preview-server.py` • pytest + httpx ASGITransport for the smoke test.

---

## Source-Code Orientation

Read this once before starting. It keeps every task short.

`backend/monitor/static/index.html` (2133 lines) owns ALL core dashboard logic. Inline `<style>` block runs L14–L338. Inline `<script>` block runs L1091–L2123 and owns `STATE`, `genData`, `genDataMock`, `drawRequestChart`, every `render*` function, `refreshAll`, `setAuto`, and the boot call. The spec occasionally refers to "controls.js" for renderers — that is wrong; all renderers are in `index.html`.

`backend/monitor/static/controls.js` (898 lines) is an IIFE module. Owns the SQL console (`runSQL`, `renderSQLTable`), kill-switch wiring, service-card control buttons, deploy/audit tables. Touch only the SQL-console section for AST-87/AST-88.

**Key line-number cheat sheet** (line numbers apply to the HEAD commit — they WILL drift as tasks land; prefer searching for the anchor string with your editor):

| Anchor | File | Approx line | Purpose |
|---|---|---|---|
| `.section-head{` | index.html | 68 | existing CSS for section headers |
| `/* Env pill (PROD) — uses gold tint */` | index.html | 126 | PROD pill CSS |
| `.ibtn{` | index.html | 221 | existing icon-button CSS (template for `.tbtn`) |
| `/* Incidents timeline strip */` | index.html | 279 | incidents timeline CSS |
| `<span class="env-pill">` | index.html | 500 | PROD pill markup |
| `<!-- Auto-refresh toggle -->` | index.html | 531 | auto toggle markup |
| `<div class="section-head" id="sec-cost">` | index.html | 542 | first section head |
| `<span class="dot ok"></span>armed` | index.html | 567 | decorative budget dot |
| `<span id="inc-count">3</span> incidents in 24h` | index.html | 643 | incidents sub-text |
| `<!-- Incidents timeline (GCP Ops) -->` | index.html | 646 | incidents card |
| `<div class="section-head" id="sec-requests">` | index.html | 669 | requests section head |
| `<span class="badge badge-ok">2xx <span id="sc-2"` | index.html | 697 | status-code badges (to delete) |
| `<div id="statusBars"` | index.html | 712 | status bars container |
| `<thead><tr><th>started</th>` | index.html | 832 | backups table header (status col to drop) |
| `<button id="sql-run" class="ibtn">` | index.html | 967 | SQL run button |
| `<select id="sql-history" class="ibtn">` | index.html | 970 | SQL history select |
| `<div id="sql-result"` | index.html | 974 | SQL result container (to replace) |
| `.sql-error{` | index.html | 1088 | old SQL error CSS (will be superseded) |
| `const STATE = {` | index.html | 1111 | STATE object |
| `async function genData(range){` | index.html | 1149 | fetch `/metrics` |
| `function genDataMock(range){` | index.html | 1221 | mock generator (gate behind preview flag) |
| `function drawRequestChart(` | index.html | 1455 | chart renderer (stroke colors) |
| `async function refreshAll(){` | index.html | 1558 | refresh entry point (rewrite for empty data) |
| `function renderServices(){` | index.html | 1568 | service cards (full rewrite) |
| `function renderRequests(){` | index.html | 1625 | status bars live here |
| `function renderBackups(){` | index.html | 1749 | backups table row template |
| `function renderAll(){` | index.html | 1904 | orchestrator |
| `document.getElementById('auto').addEventListener` | index.html | 2085 | auto toggle handler (remove) |
| `function setAuto(on){` | index.html | 2077 | setAuto helper (delete) |
| `refreshAll();` / `setAuto(true);` | index.html | 2121 | boot |
| `function initSQL() {` | controls.js | 359 | SQL console init |
| `async function runSQL() {` | controls.js | 396 | SQL run handler (update for new markup) |
| `function renderSQLTable(container, data)` | controls.js | 421 | SQL table renderer (reuse; tighten error path) |
| `backend/monitor/tests/test_main.py` | — | 1 | smoke tests — extend here |

**Preview server (already wired):** via Claude Code use `preview_start` with name `monitor-preview`. Boots at `http://127.0.0.1:8765`. Two URLs:
- `/?preview=1` — mock data
- `/` — empty-state

---

## Task 0: Prep the branch

**Files:** None yet.

- [ ] **Step 1: Create branch off `development`**

```bash
git fetch origin
git checkout development
git pull --ff-only origin development
git checkout -b feature/ast-78-monitor-dashboard-polish
git status
```

Expected: `On branch feature/ast-78-monitor-dashboard-polish` and `nothing to commit, working tree clean`.

- [ ] **Step 2: Confirm current state renders**

```bash
python3 scratchpad/monitor-preview-server.py 8765 &
PREVIEW_PID=$!
sleep 1
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8765/
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8765/static/controls.js
kill $PREVIEW_PID
```

Expected: `200` and `200`.


---

## Task 1: Add shared CSS helpers

**Commit message:** `[backend] AST-78 add shared CSS helpers for polish pass`

**Files:** Modify `backend/monitor/static/index.html` — append inside the inline `<style>` block ending at L338.

**Context:** Adds seven new style rulesets referenced by later tasks. No markup changes yet — pure additions slotted in just before the closing `</style>` at L338.

- [ ] **Step 1: Open `backend/monitor/static/index.html` and locate the last media-query block**

Search for this exact block (approximately L333–L337):

```css
  /* Media break — tighter mobile */
  @media (max-width: 640px){
    .log{ grid-template-columns: 64px 64px 1fr; gap: 8px; font-size:11px; }
    .chart-wrap{ min-height:140px; }
  }
</style>
```

- [ ] **Step 2: Insert new CSS rules immediately BEFORE the `</style>` close tag**

Replace the existing block above with the block below (keeps the media query, appends the polish-pass helpers, then closes `</style>`):

```css
  /* Media break — tighter mobile */
  @media (max-width: 640px){
    .log{ grid-template-columns: 64px 64px 1fr; gap: 8px; font-size:11px; }
    .chart-wrap{ min-height:140px; }
  }

  /* ─── AST-78 polish-pass helpers ─────────────────────────────── */

  /* AST-87 — solid-accent primary button */
  .tbtn{
    background: var(--gold); color: #0a0a0a; border: 1px solid var(--gold);
    padding: 6px 14px; border-radius: 8px;
    font-family: "JetBrains Mono", ui-monospace, Menlo, monospace;
    font-size: 12px; letter-spacing: .04em;
    transition: transform .08s ease, opacity .12s;
    cursor: pointer;
  }
  .tbtn:hover{ opacity: .9; }
  .tbtn:active{ transform: scale(.97); }

  /* AST-87 — styled native <select> */
  .sel{
    background: var(--surface); color: var(--white);
    border: 1px solid var(--border);
    padding: 6px 10px; border-radius: 8px;
    font-family: "JetBrains Mono", ui-monospace, Menlo, monospace;
    font-size: 12px; cursor: pointer;
  }

  /* AST-88 — red-tinted SQL error box (supersedes the older .sql-error below) */
  .sql-error{
    background: rgba(255,107,107,.08);
    border: 1px solid rgba(255,107,107,.4);
    color: #FF9A9A;
    padding: 10px 12px; border-radius: 8px;
    font-family: "JetBrains Mono", ui-monospace, Menlo, monospace;
    white-space: pre-wrap;
  }

  /* AST-91 — single scroll wrapper for every dashboard table */
  .table-scroll{ max-height: 360px; overflow: auto; border-radius: 8px; }
  .table-scroll thead th{
    position: sticky; top: 0; background: var(--surface); z-index: 1;
  }

  /* AST-83 — collapsible section heads */
  .section-head{ cursor: pointer; user-select: none; }
  .section-head .chev{ transition: transform .18s ease; flex-shrink: 0; }
  .section-head.collapsed .chev{ transform: rotate(-90deg); }
  .section-body.collapsed{ display: none; }

  /* AST-78-ext2 — 3D flip wrapper for service cards */
  .svc-flip{ perspective: 1200px; }
  .svc-flip-inner{
    position: relative; transition: transform .5s;
    transform-style: preserve-3d;
  }
  .svc-flip.flipped .svc-flip-inner{ transform: rotateY(180deg); }
  .svc-face{
    backface-visibility: hidden;
    -webkit-backface-visibility: hidden;
  }
  .svc-face.back{
    position: absolute; inset: 0; transform: rotateY(180deg);
    background: var(--surface);
    border-radius: 8px; padding: 14px;
    display: flex; flex-direction: column; gap: 8px;
  }
  .svc-face.back .term-body{
    flex: 1;
    background: #0a0a0b; border: 1px solid var(--border); border-radius: 6px;
    padding: 10px; font-family: "JetBrains Mono", monospace; font-size: 12px;
    color: var(--body);
    overflow: auto;
  }
  .svc-face.back .term-close{
    position: absolute; top: 8px; right: 8px;
    width: 22px; height: 22px;
    display: inline-flex; align-items: center; justify-content: center;
    color: var(--muted); background: transparent; border: 0; cursor: pointer;
    border-radius: 4px;
  }
  .svc-face.back .term-close:hover{ color: var(--white); background: var(--elevated); }

  /* AST-86 — skeleton / no-data */
  .svc-dim{ opacity: .5; filter: grayscale(.3); }
  .spark-empty{ font-size: 10px; color: var(--muted); letter-spacing: .12em; }
</style>
```

The older `.sql-error` inside the second `<style>` block near L1088 is superseded by the new rule (both selectors have equal specificity, the new one appears first); Task 7 deletes the old line.

- [ ] **Step 3: Preview-server sanity check**

```bash
python3 scratchpad/monitor-preview-server.py 8765 &
PREVIEW_PID=$!
sleep 1
curl -s http://127.0.0.1:8765/ | grep -c 'table-scroll'
curl -s http://127.0.0.1:8765/ | grep -c 'section-head.collapsed'
curl -s http://127.0.0.1:8765/ | grep -c 'svc-flip'
kill $PREVIEW_PID
```

Expected each grep: `>= 1`. Open `http://127.0.0.1:8765/?preview=1` in the preview tab and confirm the dashboard still renders identically — no visual change yet.

- [ ] **Step 4: Commit**

```bash
git add backend/monitor/static/index.html
git commit -m "$(cat <<'MSG'
[backend] AST-78 add shared CSS helpers for polish pass

Ten rulesets added inside the main <style> block. No markup or
behavior changes yet — these are slot-ins for subsequent commits:
tbtn/sel (AST-87), sql-error (AST-88), table-scroll (AST-91),
collapsible section-head (AST-83), svc-flip/svc-face (AST-78-ext2),
svc-dim/spark-empty (AST-86).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

## Task 2: Dashboard removals

**Commit message:** `[backend] AST-79 AST-80 AST-81 AST-89 AST-90 monitor dashboard removals`

**Files:** Modify `backend/monitor/static/index.html` (five independent deletions).

**Context:** Pure deletions — PROD pill, auto-refresh toggle UI + handler + `STATE.auto` branch, decorative dot on `budget alert · armed`, incidents timeline card + section-head sub-text, `STATUS` column from backups history table.

- [ ] **Step 1: AST-79 — remove the PROD env-pill**

In `index.html` around L500, delete this line:

```html
    <span class="env-pill"><span class="dot ok"></span>PROD</span>
```

The surrounding flex layout handles the gap cleanly.

- [ ] **Step 2: AST-81 — remove the auto-refresh toggle UI**

In `index.html` around L531–L535, delete these four lines:

```html
    <!-- Auto-refresh toggle -->
    <div class="flex items-center gap-2">
      <span class="text-[11px] text-muted hidden sm:inline">auto</span>
      <span id="auto" class="tgl on" role="switch" aria-checked="true"></span>
    </div>
```

- [ ] **Step 3: AST-81 — simplify STATE, remove setAuto, keep the 30s timer running unconditionally**

In `index.html`'s inline `<script>` block, find the `STATE` object (~L1111) and remove the `auto: true,` and `autoTimer: null,` lines. Final shape:

```js
const STATE = {
  range: '6h',
  logFilter: '',
  svcFilter: 'all',
  data: null,
};
```

Find the `setAuto` function + click listener (~L2077–L2085) and replace the whole block with:

```js
// AST-81 — auto-refresh ticks unconditionally every 30s (no user toggle).
setInterval(() => { refreshAll(); }, 30_000);
```

Find the boot call at the bottom of the script (~L2121–L2122):

```js
refreshAll();
setAuto(true);
```

Replace with just:

```js
refreshAll();
```

- [ ] **Step 4: AST-80 — remove the decorative green dot on `budget alert · armed`**

In `index.html` find the KV row for budget alert (~L565–L568):

```html
          <div class="kv">
            <span class="k">budget alert</span>
            <span class="v flex items-center gap-1.5"><span class="dot ok"></span>armed</span>
          </div>
```

Replace with:

```html
          <div class="kv">
            <span class="k">budget alert</span>
            <span class="v">armed</span>
          </div>
```

The `WITHIN CAPS` badge dot at L545 and the `APPROACHING CAP` branch inside `renderCost` stay untouched — they are semantic.

- [ ] **Step 5: AST-89 — delete the incidents timeline block and its sub-text**

In `index.html` find the Service Health section head (~L640–L644) and replace:

```html
  <div class="section-head" id="sec-services">
    <span class="crumb">astral / oci / <span class="cur">service health</span></span>
    <span class="rule"></span>
    <span class="mono text-[11px] text-muted">docker compose ps · 6 services · <span id="inc-count">3</span> incidents in 24h</span>
  </div>
```

with:

```html
  <div class="section-head" id="sec-services">
    <span class="crumb">astral / oci / <span class="cur">service health</span></span>
    <span class="rule"></span>
    <span class="mono text-[11px] text-muted">docker compose ps · 6 services</span>
  </div>
```

Then delete the entire `<!-- Incidents timeline (GCP Ops) -->` section directly below (~L646–L660):

```html
  <!-- Incidents timeline (GCP Ops) -->
  <section class="card p-3 sm:p-4 mb-3">
    <div class="flex items-center justify-between mb-2">
      <div class="text-[11px] tracking-[.14em] uppercase text-muted">Incidents · last 24h</div>
      <div class="flex items-center gap-2 text-[11px] text-muted mono">
        <span class="flex items-center gap-1"><span class="dot" style="background:var(--warning); width:6px; height:6px;"></span>warn</span>
        <span class="flex items-center gap-1"><span class="dot crit" style="width:6px; height:6px; box-shadow:none;"></span>crit</span>
        <span class="flex items-center gap-1"><span class="dot" style="background:var(--gold); width:6px; height:6px;"></span>info</span>
      </div>
    </div>
    <div class="timeline" id="timeline">
      <div class="now-line" style="right:0"></div>
    </div>
    <div class="relative mt-1" style="height:12px;" id="timeline-labels"></div>
  </section>
```

- [ ] **Step 6: AST-90 — drop STATUS column from backups history table**

In `index.html` find the table header (~L832):

```html
          <thead><tr><th>started</th><th>took</th><th>size</th><th>status</th></tr></thead>
```

Replace with:

```html
          <thead><tr><th>started</th><th>took</th><th>size</th></tr></thead>
```

Then in the inline `<script>` find `renderBackups` (~L1749) and simplify — the new function keeps the three-column row template only. Replace the existing function body so the table row template no longer emits a `<td>` with the status badge. The countdown block (`document.getElementById('bk-next')...`) stays unchanged. After editing, the function should only emit three cells per row: started, duration, size.

- [ ] **Step 7: Preview verify**

Start preview, open `http://127.0.0.1:8765/?preview=1`, and verify:

- No green `PROD` pill near "oci monitor".
- No `auto` toggle on the right of the time-range tabs.
- `budget alert · armed` no longer has a green dot (but `WITHIN CAPS` top-right still does).
- No "Incidents · last 24h" card above the service cards.
- Backups history table shows only 3 columns: `STARTED / TOOK / SIZE`.

```bash
python3 scratchpad/monitor-preview-server.py 8765 &
PREVIEW_PID=$!
sleep 1
! curl -s http://127.0.0.1:8765/ | grep -q 'env-pill'         && echo "✓ env-pill removed"
! curl -s http://127.0.0.1:8765/ | grep -q 'id="auto"'        && echo "✓ auto toggle removed"
! curl -s http://127.0.0.1:8765/ | grep -q 'Incidents · last' && echo "✓ incidents strip removed"
! curl -s http://127.0.0.1:8765/ | grep -q '>status</th>'     && echo "✓ backups status column removed"
kill $PREVIEW_PID
```

Expected: four `✓` lines.

- [ ] **Step 8: Commit**

```bash
git add backend/monitor/static/index.html
git commit -m "$(cat <<'MSG'
[backend] AST-79 AST-80 AST-81 AST-89 AST-90 monitor dashboard removals

Delete PROD env-pill, auto-refresh toggle (timer runs unconditionally
at 30s), decorative dot on budget-alert-armed, incidents timeline card
+ section-head sub-text, and STATUS column from backups history table.

Fixes AST-79
Fixes AST-80
Fixes AST-81
Fixes AST-89
Fixes AST-90

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
MSG
)"
```


---

## Task 3: Collapsible section heads with localStorage persistence

**Commit message:** `[backend] AST-83 collapsible section-heads with localStorage`

**Files:** Modify `backend/monitor/static/index.html`.

**Context:** Every `.section-head` div needs a leading chevron SVG; the content directly below needs wrapping as `.section-body`; a delegated click handler toggles `.collapsed` on both and persists the map to `localStorage.monitor_collapsed_v1`. Defaults: `sec-cost` and `sec-services` expanded; everything else collapsed.

Twelve section heads in document order: `sec-cost`, `sec-services`, `sec-requests`, `sec-arq`, `sec-storage`, `sec-backups`, `sec-cert`, `sec-logs`, `sec-flags`, `sec-deploys`, `sec-sql`, `sec-audit`.

- [ ] **Step 1: Add a chevron SVG to every section-head**

For EACH of the 12 section-head divs, insert this SVG as the FIRST child (immediately after the opening `<div class="section-head" id="sec-...">` tag):

```html
<svg class="chev" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" style="color:var(--muted)"><path d="m6 9 6 6 6-6"/></svg>
```

Example — `sec-cost` (L542) becomes:

```html
  <div class="section-head" id="sec-cost">
    <svg class="chev" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" style="color:var(--muted)"><path d="m6 9 6 6 6-6"/></svg>
    <span class="crumb">astral / oci / <span class="cur">cost &amp; always-free</span></span>
    <span class="rule"></span>
    <span class="badge badge-ok"><span class="dot ok"></span>WITHIN CAPS</span>
  </div>
```

Repeat for the other 11. The chevron sits BEFORE the `.crumb` span in every case.

- [ ] **Step 2: Wrap each section's content in a `.section-body` div**

For each section-head `<div class="section-head" id="sec-X">...</div>`, wrap everything that follows it (up to but not including the NEXT section-head or the `</main>` close tag) in:

```html
<div class="section-body" data-for="sec-X">
  ... existing content ...
</div>
```

Concretely — for each section listed, insert `<div class="section-body" data-for="sec-X">` right after the section-head's closing `</div>`, and insert the closing `</div>` right before the NEXT section-head's opening `<div>` (or before `<footer>` for the final `sec-audit` wrapper).

Example — cost section wrapping:

```html
  <div class="section-head" id="sec-cost">
    <svg class="chev" ... />
    <span class="crumb">astral / oci / <span class="cur">cost &amp; always-free</span></span>
    <span class="rule"></span>
    <span class="badge badge-ok"><span class="dot ok"></span>WITHIN CAPS</span>
  </div>

  <div class="section-body" data-for="sec-cost">
    <section class="card p-4 sm:p-5">
      ... existing cost content unchanged ...
    </section>
  </div>


  <!-- ─── 2. SERVICE HEALTH GRID ─── -->
  <div class="section-head" id="sec-services">
    ...
```

Apply the same pattern to all 12 sections.

- [ ] **Step 3: Add collapsible state + delegated handler in the inline script**

At the top of the inline `<script>` block (right below `const STATE = { ... };` definition, ~L1118), insert:

```js
// AST-83 — collapsible sections
const COLLAPSE_KEY = 'monitor_collapsed_v1';
const COLLAPSE_DEFAULTS = {
  'sec-cost':     false,
  'sec-services': false,
  'sec-requests': true,
  'sec-arq':      true,
  'sec-storage':  true,
  'sec-backups':  true,
  'sec-cert':     true,
  'sec-logs':     true,
  'sec-flags':    true,
  'sec-deploys':  true,
  'sec-sql':      true,
  'sec-audit':    true,
};
STATE.collapsed = (() => {
  try {
    const raw = localStorage.getItem(COLLAPSE_KEY);
    if (!raw) return Object.assign({}, COLLAPSE_DEFAULTS);
    return Object.assign({}, COLLAPSE_DEFAULTS, JSON.parse(raw));
  } catch (_) {
    return Object.assign({}, COLLAPSE_DEFAULTS);
  }
})();

function applyCollapsed(id){
  const head = document.getElementById(id);
  const body = document.querySelector(`.section-body[data-for="${id}"]`);
  if (!head || !body) return;
  const isCollapsed = !!STATE.collapsed[id];
  head.classList.toggle('collapsed', isCollapsed);
  body.classList.toggle('collapsed', isCollapsed);
}

function applyAllCollapsed(){
  for (const id of Object.keys(COLLAPSE_DEFAULTS)) applyCollapsed(id);
}

function toggleSection(id){
  STATE.collapsed[id] = !STATE.collapsed[id];
  try { localStorage.setItem(COLLAPSE_KEY, JSON.stringify(STATE.collapsed)); } catch(_) {}
  applyCollapsed(id);
}

// Delegated click handler for every section head
document.addEventListener('click', (e) => {
  const head = e.target.closest('.section-head');
  if (!head || !head.id || !(head.id in COLLAPSE_DEFAULTS)) return;
  // Ignore clicks that target interactive children
  if (e.target.closest('button')) return;
  toggleSection(head.id);
});
```

At the bottom of the script (right after `refreshAll();`), add:

```js
applyAllCollapsed();
```

- [ ] **Step 4: Preview verify**

Start preview, open `http://127.0.0.1:8765/?preview=1`. Expect:

- Only the COST and SERVICE HEALTH sections visible on first load; all others show their section-head (with a rotated `<` chevron) but no body.
- Clicking any section-head toggles visibility; chevron rotates.
- Refresh the page — state persists.

```bash
python3 scratchpad/monitor-preview-server.py 8765 &
PREVIEW_PID=$!
sleep 1
curl -s http://127.0.0.1:8765/ | grep -c 'section-body data-for'
curl -s http://127.0.0.1:8765/ | grep -c 'class="chev"'
kill $PREVIEW_PID
```

Expected: each grep ≥ 12.

- [ ] **Step 5: Commit**

```bash
git add backend/monitor/static/index.html
git commit -m "$(cat <<'MSG'
[backend] AST-83 collapsible section-heads with localStorage

Each .section-head div gets a leading rotating chevron and toggles a
sibling .section-body wrapper. State persisted in
localStorage.monitor_collapsed_v1 (v-suffix so future default changes
can invalidate). Defaults: sec-cost and sec-services expanded; all
other 10 sections collapsed on first visit.

Fixes AST-83

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

## Task 4: Request chart colors + sticky-header table scroll

**Commit message:** `[backend] AST-85 AST-91 request chart colors + sticky-header table scroll`

**Files:** Modify `backend/monitor/static/index.html`.

**Context:** AST-85 changes two hex values in `drawRequestChart` + the two legend swatches next to `rps` and `p95`. AST-91 wraps six dashboard tables in `<div class="table-scroll">` — this activates the `max-height: 360px; overflow: auto;` CSS from Task 1; the sticky `thead` is handled by the global `.table-scroll thead th` selector. (The seventh table — SQL results — is wrapped in Task 7.)

- [ ] **Step 1: AST-85 — update chart colors in `drawRequestChart`**

In `index.html` find `drawRequestChart` (~L1455). Inside, update the three color references.

Replace:

```js
    <path d="${rpsArea}" fill="#C9A84C" fill-opacity="0.10"/>
    <path d="${rpsD}" fill="none" stroke="#C9A84C" stroke-width="1.4" stroke-linejoin="round"/>
    <path d="${p95D}" fill="none" stroke="#FFA726" stroke-width="1.2" stroke-dasharray="3 3" stroke-linejoin="round"/>
```

with:

```js
    <path d="${rpsArea}" fill="#4FC3F7" fill-opacity="0.10"/>
    <path d="${rpsD}" fill="none" stroke="#4FC3F7" stroke-width="1.4" stroke-linejoin="round"/>
    <path d="${p95D}" fill="none" stroke="#FF6B6B" stroke-width="1.2" stroke-dasharray="3 3" stroke-linejoin="round"/>
```

- [ ] **Step 2: AST-85 — update the legend swatches in the requests summary card**

In `index.html` find the two legend lines (~L684 and ~L688):

```html
              <div class="text-[11px] text-muted mono">rps · <span style="color:var(--gold)">■</span> rps</div>
```

Change `color:var(--gold)` to `color:#4FC3F7` on the rps legend.

```html
              <div class="text-[11px] text-muted mono">p95 · <span style="color:var(--warning)">■</span> p95</div>
```

Change `color:var(--warning)` to `color:#FF6B6B` on the p95 legend.

- [ ] **Step 3: AST-91 — wrap the Slowest Endpoints table**

Find (~L714–L718):

```html
      <div class="text-[11px] tracking-[.14em] uppercase text-muted mb-2">Slowest endpoints</div>
      <table class="z">
        <thead><tr><th>endpoint</th><th class="text-right">p95</th><th class="text-right">n</th></tr></thead>
        <tbody id="slowest"></tbody>
      </table>
```

Wrap the `<table>` in `<div class="table-scroll">...</div>` so the final structure is:

```html
      <div class="text-[11px] tracking-[.14em] uppercase text-muted mb-2">Slowest endpoints</div>
      <div class="table-scroll">
        <table class="z">
          <thead><tr><th>endpoint</th><th class="text-right">p95</th><th class="text-right">n</th></tr></thead>
          <tbody id="slowest"></tbody>
        </table>
      </div>
```

- [ ] **Step 4: AST-91 — wrap the ARQ Completed and ARQ Failed tables**

Repeat the same wrapping pattern for:

1. The completed jobs table (~L768) — contents `<tbody id="completed">`
2. The failed jobs table (~L780) — contents `<tbody id="failed">`

Each `<table class="z">...</table>` becomes `<div class="table-scroll"><table class="z">...</table></div>`.

- [ ] **Step 5: AST-91 — wrap the Backups History, Recent Deploys, and Audit Log tables**

Same pattern again for:

3. Backups history table (~L831) — `<tbody id="bk-rows">` (3 columns after Task 2)
4. Recent deploys table (~L947) — `<tbody id="deploys-rows">`
5. Audit log table (~L985) — `<tbody id="audit-rows">`

Each `<table class="z">...</table>` becomes `<div class="table-scroll"><table class="z">...</table></div>`.

- [ ] **Step 6: Preview verify**

Start preview at `/?preview=1`. Expand every section (click chevrons). Verify:

- RPS line is sky blue, p95 dashed line is coral red (check the line chart inside the requests section).
- Legend swatches match those colors.
- Each table with more than ~8 rows scrolls internally; `thead` row stays pinned at top while scrolling.

```bash
python3 scratchpad/monitor-preview-server.py 8765 &
PREVIEW_PID=$!
sleep 1
curl -s http://127.0.0.1:8765/ | grep -c 'table-scroll'
curl -s http://127.0.0.1:8765/ | grep -c '#4FC3F7'
curl -s http://127.0.0.1:8765/ | grep -c '#FF6B6B'
kill $PREVIEW_PID
```

Expected: first grep ≥ 6 (five wrapped tables + CSS rule from Task 1), second ≥ 2 (chart + legend), third ≥ 2.

- [ ] **Step 7: Commit**

```bash
git add backend/monitor/static/index.html
git commit -m "$(cat <<'MSG'
[backend] AST-85 AST-91 request chart colors + sticky-header table scroll

Two small unrelated polish items bundled:
- drawRequestChart: RPS #4FC3F7, p95 #FF6B6B; legend swatches match.
- Every dashboard table wraps in <div class="table-scroll"> (six
  tables in this commit: slowest, ARQ completed/failed, backups
  history, recent deploys, audit log. SQL results wrapper lands in
  Task 7.) Global .table-scroll thead th selector handles the
  sticky-header CSS.

Fixes AST-85
Fixes AST-91

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

## Task 5: Status-code bar toggles (AST-84)

**Commit message:** `[backend] AST-84 status-code bar toggles in requests panel`

**Files:** Modify `backend/monitor/static/index.html`.

**Context:** The four `2xx/3xx/4xx/5xx` count badges at the top-right of the requests summary card are DELETED. The STATUS CODES bar rows in the right panel become the toggles — click a row to dim/restore. State lives in `STATE.statusFilter` (a `Set`). No chart interaction; filtering is cosmetic on the bars only.

- [ ] **Step 1: Delete the four top-right status-code badges**

In `index.html` find the badge block inside the requests summary card (~L696–L701):

```html
        <div class="flex gap-2 text-[11px] text-muted mono">
          <span class="badge badge-ok">2xx <span id="sc-2" class="mono text-body ml-1">18,421</span></span>
          <span class="badge badge-muted">3xx <span id="sc-3" class="mono text-body ml-1">320</span></span>
          <span class="badge badge-warn">4xx <span id="sc-4" class="mono text-body ml-1">87</span></span>
          <span class="badge badge-crit">5xx <span id="sc-5" class="mono text-body ml-1">3</span></span>
        </div>
```

Delete the entire block (opening `<div>` through closing `</div>`).

- [ ] **Step 2: Remove the four `sc-*` id references from `renderRequests`**

In `index.html` find `renderRequests` (~L1625). Delete these four lines inside the no-traffic branch (~L1642–L1645):

```js
    document.getElementById('sc-2').textContent = '0';
    document.getElementById('sc-3').textContent = '0';
    document.getElementById('sc-4').textContent = '0';
    document.getElementById('sc-5').textContent = '0';
```

Delete these four lines in the main branch (~L1657–L1660):

```js
  document.getElementById('sc-2').textContent = r.status_codes['2xx'].toLocaleString();
  document.getElementById('sc-3').textContent = r.status_codes['3xx'].toLocaleString();
  document.getElementById('sc-4').textContent = r.status_codes['4xx'].toLocaleString();
  document.getElementById('sc-5').textContent = r.status_codes['5xx'].toLocaleString();
```

- [ ] **Step 3: Add the filter Set to STATE**

Near the collapsible state block added in Task 3, add one line:

```js
STATE.statusFilter = new Set();  // AST-84 — codes in the set are DIMMED
```

Semantic: empty set = all shown; code in set = that row is dimmed. Simpler than seeding all four codes (which would render everything dimmed on first load).

- [ ] **Step 4: Emit clickable rows in the status-bars render block**

Still in `renderRequests`, find the status-bars render block (~L1662–L1674). Rewrite it so each row gets a `sc-row` class, a `data-code` attribute, the `svc-dim` class when the code is in the filter set, and `cursor:pointer` for affordance. The existing structure (flex header with code + count + percent, then `.bar-track`) stays the same — just wrapped in a clickable container.

Concretely, each row now emits (template):

```
<div class="sc-row{dim}" data-code="{k}" style="cursor:pointer">
  ... existing flex+bar content unchanged ...
</div>
```

where `dim` is `" svc-dim"` when `STATE.statusFilter.has(k)`, empty string otherwise.

- [ ] **Step 5: Wire the click handler**

At the end of the `renderRequests` function (just before its closing `}`), add:

```js
  // AST-84 — attach click handlers to .sc-row
  document.querySelectorAll('#statusBars .sc-row').forEach(row => {
    row.addEventListener('click', () => {
      const code = row.dataset.code;
      if (STATE.statusFilter.has(code)) STATE.statusFilter.delete(code);
      else STATE.statusFilter.add(code);
      row.classList.toggle('svc-dim', STATE.statusFilter.has(code));
    });
  });
```

- [ ] **Step 6: Preview verify**

Start preview at `/?preview=1`, expand the REQUESTS section. Verify:

- Top-right of the requests summary card no longer shows the four count pills.
- Right panel STATUS CODES: clicking any row dims it; clicking again restores.
- The line chart is unchanged (no filter interaction).

- [ ] **Step 7: Commit**

```bash
git add backend/monitor/static/index.html
git commit -m "$(cat <<'MSG'
[backend] AST-84 status-code bar toggles in requests panel

Remove the four count-pill badges (2xx/3xx/4xx/5xx) from the top-right
of the requests summary card. The four rows in the STATUS CODES right
panel become click-to-dim toggles — clicking a row applies svc-dim;
click again to restore. State in STATE.statusFilter (Set). No
interaction with drawRequestChart — filtering is cosmetic on the bars.

Fixes AST-84

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
MSG
)"
```


---

## Task 6: Service-card skeleton + empty states (AST-86)

**Commit message:** `[backend] AST-86 service-card skeleton + no-data empty state`

**Files:** Modify `backend/monitor/static/index.html`.

**Context:** The most substantial single change. Three related edits:

1. `renderServices` rewritten to drive from a fixed `SVC_ORDER` constant, not from `STATE.data.services`. Missing entries render with `NO DATA` badge + `svc-dim` body + placeholder values.
2. `refreshAll`'s catch branch sets `STATE.data = emptyData()` (new typed-empty helper) and calls `renderAll()`.
3. `genData` short-circuits to `genDataMock` at its top when `window.__MONITOR_PREVIEW__ === true`. An inline `<script>` in `index.html` sets the flag from `?preview=1`.

- [ ] **Step 1: Add the preview-flag setter as the very first inline script**

In `index.html`, find the opening `<script>` at L1091 (the one immediately followed by the `/* ========== astral · oci monitor — mock data engine ... */` comment).

Insert BEFORE that `<script>` tag:

```html
<script>
// AST-86 preview-flag: enables genDataMock in the local preview server.
// Prod URLs never carry ?preview — nginx strips query strings on / as well,
// so this flag can only be set through the local preview server.
window.__MONITOR_PREVIEW__ = new URLSearchParams(location.search).has('preview');
</script>
<script>
```

The second `<script>` opens the existing main block.

- [ ] **Step 2: Gate `genDataMock` behind the preview flag inside `genData`**

Find `genData` at L1149:

```js
async function genData(range){
  const resp = await fetch('/metrics?range=' + encodeURIComponent(range), {credentials: 'include'});
  if(!resp.ok){
    throw new Error('metrics fetch failed: ' + resp.status);
  }
  return normalizeMetrics(await resp.json());
}
```

Replace with:

```js
async function genData(range){
  // AST-86 — preview-server escape hatch. Prod never sets this flag.
  if (window.__MONITOR_PREVIEW__) return genDataMock(range);
  const resp = await fetch('/metrics?range=' + encodeURIComponent(range), {credentials: 'include'});
  if(!resp.ok){
    throw new Error('metrics fetch failed: ' + resp.status);
  }
  return normalizeMetrics(await resp.json());
}
```

- [ ] **Step 3: Add the `emptyData` helper**

Immediately after `genData` (so ~after L1157), add:

```js
// AST-86 — typed-empty data object used when /metrics is unreachable.
// Shape matches what renderers expect so they can walk it safely.
function emptyData(){
  return {
    schema_version: '1.0.0',
    generated_at: new Date().toISOString(),
    build: '—',
    region: '—',
    tenancy_ocid: '—',
    instance_ocid: '—',
    cost: null,
    services: [],
    requests: { window: '—', series_rps: [], series_p95_ms: [], status_codes: {'2xx':0,'3xx':0,'4xx':0,'5xx':0}, total: 0, slowest: [] },
    arq: { queue_depth: 0, in_flight: 0, workers: 0, completed_24h: 0, failed_24h: 0, active: [], recent_completed: [], recent_failed: [] },
    storage: null,
    backups: { status: '—', recent_runs: [], next_run_in_s: 0, bucket: '—', retention_days: 0 },
    cert: null,
    logs: [],
  };
}
```

- [ ] **Step 4: Rewrite `refreshAll` so the catch branch renders empty data**

Find (~L1558–L1566):

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
```

Replace with:

```js
async function refreshAll(){
  try {
    STATE.data = await genData(STATE.range);
  } catch(e){
    console.error('refreshAll failed', e);
    STATE.data = emptyData();
    if (!STATE._warnedUnreachable){
      toast('metrics unreachable');
      STATE._warnedUnreachable = true;
    }
  }
  renderAll();
}
```

- [ ] **Step 5: Rewrite `renderServices`**

Find the entire `renderServices` function at L1568–L1623. Replace it with the block below. The new function is driven by a static list; missing entries render a NO DATA skeleton.

```js
// AST-86 — six-card skeleton driven by static list, never by STATE.data.services.
const SVC_ORDER = ['postgres','redis','fastapi','arq_worker','nginx','certbot'];
const SVC_IMAGES = {
  postgres:   'postgres:16-alpine',
  redis:      'redis:7-alpine',
  fastapi:    'astral/fastapi:—',
  arq_worker: 'astral/worker:—',
  nginx:      'nginx:1.25-alpine',
  certbot:    'certbot/certbot:latest',
};

function renderServices(){
  const grid = document.getElementById('svc-grid');
  const entries = STATE.data.services || [];
  const cards = SVC_ORDER.map(name => {
    const s = entries.find(e => e && e.name === name);
    const hasData = !!s;
    const hasSpark = hasData && Array.isArray(s.spark) && s.spark.length > 0;

    // Badge + tone
    let badge, tone, lbl;
    if (!hasData) {
      badge = 'badge-warn'; tone = 'warn'; lbl = 'NO DATA';
    } else if (s.health === 'healthy') {
      badge = 'badge-ok'; tone = 'ok'; lbl = 'UP';
    } else if (s.health === 'starting') {
      badge = 'badge-warn'; tone = 'warn'; lbl = 'STARTING';
    } else {
      badge = 'badge-crit'; tone = 'crit'; lbl = 'DOWN';
    }

    const imageStr = hasData ? (s.image || SVC_IMAGES[name]) : SVC_IMAGES[name];
    const [imageBase, imageTag] = imageStr.split(':');

    const uptime = hasData ? fmtUptime(s.uptime_s) : '—';
    const cpuMem = hasData
      ? `${Number(s.cpu || 0).toFixed(1)}% · ${s.mem || 0}MB`
      : '— · —';

    const sparkMarkup = hasSpark
      ? sparkSvg(s.spark, {tone: tone === 'ok' ? '' : tone})
      : `<svg class="spark" viewBox="0 0 200 30" preserveAspectRatio="none" style="width:100%;height:30px"><text class="spark-empty" x="4" y="19">no data</text></svg>`;

    // Footer by service (fall back to empty when data missing)
    let footer = '<span class="mono text-[11px] text-muted">metrics unreachable</span>';
    if (hasData) {
      const extra = s.extra || {};
      if (name === 'postgres')        footer = `<span class="mono text-[11px] text-muted">${extra.pg_connections ?? '—'}/${extra.pg_max_connections ?? '—'} conns</span>`;
      else if (name === 'redis')      footer = `<span class="mono text-[11px] text-muted">${extra.ops_sec ?? '—'} ops/s · ${extra.keys ?? '—'} keys</span>`;
      else if (name === 'fastapi')    footer = `<span class="mono text-[11px] text-muted">${extra.workers ?? '—'}w · ${extra.rps ?? '—'} rps</span>`;
      else if (name === 'arq_worker') footer = `<span class="mono text-[11px] text-muted">${extra.jobs_active ?? '—'}/${extra.max ?? '—'} jobs</span>`;
      else if (name === 'nginx')      footer = `<span class="mono text-[11px] text-muted">${extra.active_connections ?? '—'} conns · ${(extra.reqs_total ?? 0).toLocaleString()} req</span>`;
      else if (name === 'certbot')    footer = `<span class="mono text-[11px] text-muted">next check ${extra.next_check_in ?? '—'}</span>`;
    }

    const bodyClass = hasData ? '' : ' svc-dim';
    const containerId = hasData ? (s.container_id || '') : '';

    return `
    <div class="card svc-card p-4${bodyClass}" data-service-card="${name}">
      <div class="flex items-start gap-3 svc-card-header">
        <div class="elevated w-8 h-8 flex items-center justify-center text-muted" style="border-radius:8px">${svcIcon(name)}</div>
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2">
            <span class="text-white font-semibold tracking-tight truncate">${name}</span>
            <span class="badge ${badge}"><span class="dot ${tone}"></span>${lbl}</span>
            <span class="flex-1"></span>
            <button class="ibtn svc-refresh" style="width:24px;height:24px;" title="refresh ${name}" onclick="event.stopPropagation(); this.classList.add('spin'); setTimeout(()=>this.classList.remove('spin'),700); refreshService('${name}');">
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 0 1 15-6.7L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-15 6.7L3 16"/><path d="M3 21v-5h5"/></svg>
            </button>
          </div>
          <div class="mt-0.5 flex items-center gap-1.5 text-[11px] text-muted mono truncate">
            <span class="truncate">${imageBase}</span>
            <span style="color:var(--gold)">:${imageTag||'latest'}</span>
          </div>
        </div>
      </div>
      <div class="mt-3 flex items-baseline justify-between">
        <div>
          <div class="text-[11px] tracking-[.14em] uppercase text-muted">uptime</div>
          <div class="mono text-sm text-white">${uptime}</div>
        </div>
        <div class="text-right">
          <div class="text-[11px] tracking-[.14em] uppercase text-muted">cpu · mem</div>
          <div class="mono text-sm text-white">${cpuMem}</div>
        </div>
      </div>
      <div class="mt-2">
        ${sparkMarkup}
      </div>
      <div class="mt-1 flex justify-between items-center">
        <span class="copy" data-copy="${containerId}">${containerId.slice(0,12) || '—'} <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg></span>
        ${footer}
      </div>
    </div>`;
  });
  grid.replaceChildren();
  const parser = new DOMParser();
  const doc = parser.parseFromString('<div>' + cards.join('') + '</div>', 'text/html');
  const src = doc.body.firstElementChild;
  while (src && src.firstChild) grid.appendChild(src.firstChild);
}
```

Note the final DOM assembly uses `DOMParser` + `replaceChildren` + `appendChild` to avoid direct assignment to `.innerHTML` on the grid container; this keeps the safe-DOM discipline consistent with the rest of the polish pass.

- [ ] **Step 6: Preview verify BOTH modes**

A. **Preview mode (mock data)** — open `http://127.0.0.1:8765/?preview=1`:

- All 6 service cards render with UP badges + sparklines and real-looking CPU/MEM.
- No toast on load.

B. **Empty-state mode** — open `http://127.0.0.1:8765/` (no preview flag):

- All 6 service cards STILL render, now with amber `NO DATA` badge, `—` placeholders, `no data` sparkline label, `metrics unreachable` footer, and the body is dimmed (`svc-dim`).
- One `metrics unreachable` toast appears on first load, does NOT repeat.

```bash
python3 scratchpad/monitor-preview-server.py 8765 &
PREVIEW_PID=$!
sleep 1
curl -s http://127.0.0.1:8765/           | grep -c 'SVC_ORDER'
curl -s http://127.0.0.1:8765/?preview=1 | grep -c '__MONITOR_PREVIEW__'
kill $PREVIEW_PID
```

Expected each: ≥ 1.

- [ ] **Step 7: Commit**

```bash
git add backend/monitor/static/index.html
git commit -m "$(cat <<'MSG'
[backend] AST-86 service-card skeleton + no-data empty state

renderServices rewrite driven by a static SVC_ORDER list (postgres,
redis, fastapi, arq_worker, nginx, certbot). Missing data entries
render amber NO DATA badge + svc-dim body + em-dash placeholders and
a 'no data' sparkline label; present-but-sparkless entries only show
the sparkline fallback.

refreshAll's catch branch now sets STATE.data to a typed-empty object
and calls renderAll, so the six cards always draw. A _warnedUnreachable
flag prevents toast spam on successive fetch failures.

genData short-circuits to genDataMock when window.__MONITOR_PREVIEW__
is true; an inline prelude script sets the flag from ?preview=1 query
param. Prod never sees the flag.

Fixes AST-86

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

## Task 7: SQL run button + results section (AST-87, AST-88)

**Commit message:** `[backend] AST-87 AST-88 SQL run button + results section`

**Files:**
- Modify `backend/monitor/static/index.html`
- Modify `backend/monitor/static/controls.js`

**Context:** AST-87 swaps classes on the SQL Run button + History select. AST-88 restructures the results area into a labeled, scrollable section and tightens the error path to use `textContent` only.

- [ ] **Step 1: AST-87 / AST-88 — update the SQL console markup**

In `index.html` find the SQL console section (~L964–L975):

```html
  <section class="card p-4 sm:p-5">
    <textarea id="sql-input" rows="5" class="w-full bg-bg mono text-sm p-3 rounded-lg hairline" placeholder="SELECT id, title FROM comics ORDER BY added_at DESC LIMIT 10;"></textarea>
    <div class="flex items-center gap-3 mt-3">
      <button id="sql-run" class="ibtn">Run (Cmd/Ctrl+Enter)</button>
      <span id="sql-status" class="text-[11px] text-muted mono"></span>
      <div class="flex-1"></div>
      <select id="sql-history" class="ibtn">
        <option value="">History…</option>
      </select>
    </div>
    <div id="sql-result" class="mt-3 overflow-auto" style="max-height:420px;"></div>
  </section>
```

Replace with:

```html
  <section class="card p-4 sm:p-5">
    <textarea id="sql-input" rows="5" class="w-full bg-bg mono text-sm p-3 rounded-lg hairline" placeholder="SELECT id, title FROM comics ORDER BY added_at DESC LIMIT 10;"></textarea>
    <div class="flex items-center gap-3 mt-3">
      <button id="sql-run" class="tbtn">Run ⌘↵</button>
      <span id="sql-status" class="text-[11px] text-muted mono"></span>
      <div class="flex-1"></div>
      <select id="sql-history" class="sel">
        <option value="">History…</option>
      </select>
    </div>
    <div id="sql-results" class="hidden" style="margin-top:16px">
      <div class="flex items-baseline justify-between mb-2">
        <div class="text-[11px] tracking-[.14em] uppercase text-muted">Results</div>
        <div id="sql-results-meta" class="mono text-[11px] text-muted"></div>
      </div>
      <div id="sql-results-body" class="table-scroll"></div>
    </div>
  </section>
```

Key changes: `ibtn` → `tbtn`, `Run (Cmd/Ctrl+Enter)` → `Run ⌘↵`, history `ibtn` → `sel`, results container becomes the `#sql-results` wrapper with label + meta + scrollable body.

- [ ] **Step 2: AST-88 — update `runSQL` in controls.js to target new markup and tighten the error path**

In `backend/monitor/static/controls.js` find `runSQL` at ~L396–L419.

Update it so:
- It reads `#sql-results` (wrapper), `#sql-results-body` (table container), and `#sql-results-meta` (row-count/duration span).
- On first run, it removes the `hidden` class from the wrapper.
- Success path: clears `#sql-status`, writes `"{n} rows · {ms}ms · TRUNCATED?"` into `#sql-results-meta` (NOT into status), and calls `renderSQLTable(body, data)`.
- Error path: clears body, creates a `div.sql-error` via `document.createElement`, assigns `err.message` via `.textContent`, appends to body.

The existing `renderSQLTable(container, data)` function (~L421) keeps its signature — no changes needed there; it already uses safe DOM methods (`createElement`, `textContent`).

- [ ] **Step 3: Delete the old `.sql-error` CSS now that the main-style-block rule covers it**

In `index.html` find the second `<style>` block around L1064–L1089. Locate these three lines (last block inside that style tag):

```css
  .sql-table{ width:100%; border-collapse:collapse; font-size:12px; }
  .sql-table th, .sql-table td{ padding:6px 10px; border-bottom: 1px solid rgba(42,42,48,.5); text-align:left; }
  .sql-table th{ color:var(--muted); text-transform:uppercase; font-size:10px; letter-spacing:.1em; }
  .sql-table td{ color:var(--body); font-family:"JetBrains Mono",monospace; }
  .sql-error{ color:var(--error); font-family:"JetBrains Mono",monospace; font-size:12px; padding:10px; background:rgba(239,83,80,.08); border-radius:6px; }
```

Delete ONLY the final `.sql-error { ... }` line. Keep the three `.sql-table` rules — they style the table produced by `renderSQLTable`.

- [ ] **Step 4: Preview verify**

Open `http://127.0.0.1:8765/?preview=1`. Expand the SQL CONSOLE section:

- `Run` button is solid gold with `Run ⌘↵` label.
- History dropdown is a styled select, not a square icon-box.
- Results section is hidden until a run happens.

Because the local preview server does not implement `/control/query`, clicking Run returns a fetch error and surfaces the message in the new `.sql-error` div — verify the red-tinted error box renders the raw message as text.

- [ ] **Step 5: Commit**

```bash
git add backend/monitor/static/index.html backend/monitor/static/controls.js
git commit -m "$(cat <<'MSG'
[backend] AST-87 AST-88 SQL run button + results section

AST-87: #sql-run ibtn → tbtn (solid accent, label 'Run ⌘↵').
#sql-history ibtn → sel.

AST-88: New #sql-results wrapper (RESULTS label + meta + scrollable
body). Hidden until first run. runSQL updated to populate meta + body
separately; error path rebuilds a div.sql-error via createElement +
textContent. Old .sql-error CSS in the second style block removed now
that the main-block rule covers it.

Fixes AST-87
Fixes AST-88

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
MSG
)"
```


---

## Task 8: Service-card refresh relocation + terminal flip stub (AST-78-ext)

**Commit message:** `[backend] AST-78 service-card refresh relocation + terminal flip stub`

**Files:** Modify `backend/monitor/static/index.html`.

**Context:** The per-card refresh button moves from the header row to the image/tag row (next to `.copy`). A new terminal-icon button takes the old refresh slot in the header. Clicking terminal toggles `.flipped` on the flip wrapper and surfaces a back-face with a fake prompt + flip-back button + `coming soon — AST-92` toast.

All of this lives inside the `renderServices` function introduced in Task 6. We modify the per-card template it returns.

- [ ] **Step 1: Wrap each card in `.svc-flip > .svc-flip-inner > [.svc-face.front, .svc-face.back]`**

The `renderServices` function in Task 6 returns cards shaped like `<div class="card svc-card p-4..." data-service-card="${name}">...</div>`. This task wraps each card in the flip container and adds a back face.

Change the per-card template (the return value of `SVC_ORDER.map(name => { ... return ` template literal `; })`) so each entry yields:

```
<div class="svc-flip" data-service-card="${name}">
  <div class="svc-flip-inner">
    <div class="svc-face front card svc-card p-4${bodyClass}">
      ...(existing front card header, metrics, sparkline, copy+footer row — unchanged except the header button swap below)...
    </div>
    <div class="svc-face back">
      <button class="term-close" title="close terminal" data-close-term="${name}">✕</button>
      <div class="text-[11px] tracking-[.14em] uppercase text-muted">Shell · ${name}</div>
      <div class="term-body"><span style="color:var(--gold)">$</span> <span class="mono">_</span>
<div class="mt-2 text-muted text-[11px]">Terminal UI is a stub — real exec channel lands in AST-92.</div></div>
    </div>
  </div>
</div>
```

The `data-service-card="${name}"` attribute moves from the inner `.card` element up to the `.svc-flip` wrapper so existing selectors still find each card. The inner `.card` keeps its classes.

- [ ] **Step 2: Swap the header `.svc-refresh` button for a new `.svc-terminal` button**

Inside the front face's header-row `div.flex.items-center.gap-2`, find the existing refresh button (shipped in Task 6):

```html
            <button class="ibtn svc-refresh" style="width:24px;height:24px;" title="refresh ${name}" onclick="event.stopPropagation(); this.classList.add('spin'); setTimeout(()=>this.classList.remove('spin'),700); refreshService('${name}');">
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 0 1 15-6.7L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-15 6.7L3 16"/><path d="M3 21v-5h5"/></svg>
            </button>
```

Replace with:

```html
            <button class="ibtn svc-terminal" style="width:24px;height:24px;" title="open shell in ${name}" data-service="${name}">
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>
            </button>
```

- [ ] **Step 3: Add a `.svc-refresh-mini` button next to the image/tag row**

Inside the image/tag row (still the front face) — locate:

```html
          <div class="mt-0.5 flex items-center gap-1.5 text-[11px] text-muted mono truncate">
            <span class="truncate">${imageBase}</span>
            <span style="color:var(--gold)">:${imageTag||'latest'}</span>
          </div>
```

Append a new refresh button after the tag span:

```html
          <div class="mt-0.5 flex items-center gap-1.5 text-[11px] text-muted mono truncate">
            <span class="truncate">${imageBase}</span>
            <span style="color:var(--gold)">:${imageTag||'latest'}</span>
            <button class="ibtn svc-refresh-mini" style="width:16px;height:16px;margin-left:4px;" title="refresh ${name}" onclick="event.stopPropagation(); this.classList.add('spin'); setTimeout(()=>this.classList.remove('spin'),700); refreshService('${name}');">
              <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 0 1 15-6.7L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-15 6.7L3 16"/><path d="M3 21v-5h5"/></svg>
            </button>
          </div>
```

- [ ] **Step 4: Wire terminal click + flip-back handlers at the end of `renderServices`**

At the very end of the `renderServices` function (just before its closing `}` brace, AFTER the DOM-appending code from Task 6), append:

```js
  // AST-78-ext2 — terminal flip wiring (re-bound on every render)
  document.querySelectorAll('.svc-terminal').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const name = btn.dataset.service;
      const wrap = btn.closest('.svc-flip');
      if (!wrap) return;
      wrap.classList.add('flipped');
      STATE.flippedCards = STATE.flippedCards || new Set();
      STATE.flippedCards.add(name);
      toast('coming soon — AST-92');
    });
  });
  document.querySelectorAll('.term-close').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const name = btn.dataset.closeTerm;
      const wrap = btn.closest('.svc-flip');
      if (!wrap) return;
      wrap.classList.remove('flipped');
      if (STATE.flippedCards) STATE.flippedCards.delete(name);
    });
  });
```

- [ ] **Step 5: Preview verify**

Open `http://127.0.0.1:8765/?preview=1`. Expand the Service Health section.

- Header row shows: service name · UP badge · TERMINAL icon button (chevron + horizontal line).
- Image/tag row shows: `postgres :16-alpine · [↻ refresh icon]` — the refresh moved here.
- Clicking the terminal icon flips the card to a black-panel terminal face with `$ _` prompt and an `✕` button top-right.
- Toast reads `coming soon — AST-92`.
- Clicking `✕` flips the card back.

```bash
python3 scratchpad/monitor-preview-server.py 8765 &
PREVIEW_PID=$!
sleep 1
curl -s http://127.0.0.1:8765/ | grep -c 'svc-terminal'
curl -s http://127.0.0.1:8765/ | grep -c 'svc-refresh-mini'
curl -s http://127.0.0.1:8765/ | grep -c 'term-close'
kill $PREVIEW_PID
```

Expected each: ≥ 1.

- [ ] **Step 6: Commit**

```bash
git add backend/monitor/static/index.html
git commit -m "$(cat <<'MSG'
[backend] AST-78 service-card refresh relocation + terminal flip stub

Each service card body now wraps in .svc-flip > .svc-flip-inner with
front + back faces (CSS 3D flip from Task 1). Header-row refresh is
replaced by a terminal-icon button; refresh relocates to the image/tag
row next to the tag as .svc-refresh-mini. Clicking terminal flips the
card and toasts 'coming soon — AST-92'. Back face has a fake prompt
and a flip-back '✕'. The real exec channel ships in AST-92.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

## Task 9: Cache-bust, smoke test, frontend-design polish, changelog

**Commit message:** `[backend] AST-78 cache-bust controls.js?v=4 + frontend-design polish + smoke test`

**Files:**
- Modify `backend/monitor/static/index.html` (cache-bust only)
- Modify `backend/monitor/tests/test_main.py` (new smoke test)
- Modify `CHANGELOG.md` (release log entry)
- Possibly minor tweaks in index.html / controls.js from the skill pass.

**Context:** Final polish commit. Bumps the `controls.js` cache-bust suffix, runs the `frontend-design` skill over the diff, adds one pytest smoke test guarding markers + removals, and files a changelog entry.

- [ ] **Step 1: Bump the `controls.js` cache-bust suffix**

In `index.html` find the final script tag (~L2130):

```html
<script src="static/controls.js?v=3"></script>
```

Replace with:

```html
<script src="static/controls.js?v=4"></script>
```

- [ ] **Step 2: Run the `frontend-design` skill on the current diff**

Invoke the skill scoped to the AST-78 branch's two changed files:

```
Run frontend-design skill: scope to backend/monitor/static/index.html
and backend/monitor/static/controls.js on the AST-78 branch. Audit
visual hierarchy, spacing, typography, and consistency with the
existing design tokens. Propose edits as a diff I can apply.
```

Apply any approved edits inline. Typical catches in a pass like this:

- Chevron rotation easing feels slow — tune `.section-head .chev` transition to `.14s` if the current `.18s` drags.
- `.tbtn` text alignment with the adjacent `#sql-status` span — may need a line-height bump.
- `.svc-terminal` SVG stroke width feels thin at 12px — bump to 2.2.
- `.table-scroll` scrollbar styling — match the existing `.log-scroll::-webkit-scrollbar` rules.

Record the skill's output and the edits applied in the commit body.

- [ ] **Step 3: Add the smoke test**

Open `backend/monitor/tests/test_main.py` and append:

```python
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
        'id="sql-result"',             # AST-88 — old container id (superseded by sql-results-body)
    ]
    for needle in banned:
        assert needle not in html, f"regression: {needle!r} should have been removed"
```

- [ ] **Step 4: Run the smoke test locally**

```bash
cd backend
python -m pytest monitor/tests/test_main.py -v
```

Expected: three tests pass (`test_healthz_returns_ok`, `test_root_serves_index_html`, `test_index_html_ast78_polish_markers`).

- [ ] **Step 5: Add a changelog entry**

Open `CHANGELOG.md` at the repo root. Add this as the FIRST bullet under the most recent date heading (follow the file's existing format):

```markdown
- **AST-78** — Monitor dashboard UI/UX polish pass. Removes PROD env-pill, auto-refresh toggle, decorative budget-alert dot, incidents-last-24h card, backups STATUS column. Adds collapsible section heads with localStorage, click-to-dim status-code bars, sky-blue/coral chart palette, skeleton + NO DATA empty states for service cards, styled SQL run button + results section, sticky-header scrolling for every table, and a terminal-icon stub on each service card that flips to a placeholder for the upcoming AST-92 exec channel.
```

- [ ] **Step 6: Preview one more time, both modes**

```bash
python3 scratchpad/monitor-preview-server.py 8765 &
PREVIEW_PID=$!
sleep 1
echo "PREVIEW:   open http://127.0.0.1:8765/?preview=1 in the preview tab"
echo "EMPTY:     open http://127.0.0.1:8765/ in the preview tab"
# Walk through every section in both URLs; screenshot each for the PR body.
# When done:
kill $PREVIEW_PID
```

Walk-through expectations:
- Header: no PROD pill, no auto toggle.
- Cost section: expanded; no dot on `budget alert · armed`; WITHIN CAPS dot intact.
- Service Health: expanded; six cards in preview mode, six skeleton cards in empty mode; terminal button flips each card.
- Requests (collapsed by default — click to expand): sky-blue RPS + coral p95; status bars clickable to dim.
- Backups: 3-column history table; scrollable with sticky header.
- SQL Console: styled Run + History; hidden results area.
- Audit/Deploys: scrollable tables with sticky headers.

- [ ] **Step 7: Commit**

```bash
git add backend/monitor/static/index.html backend/monitor/tests/test_main.py CHANGELOG.md
# If the frontend-design skill touched controls.js, stage it too:
git add backend/monitor/static/controls.js 2>/dev/null || true
git commit -m "$(cat <<'MSG'
[backend] AST-78 cache-bust controls.js?v=4 + frontend-design polish + smoke test

- Bumps the controls.js query suffix so browsers pull the new module.
- Applies frontend-design skill output against the full diff (spacing,
  typography, transition timing, scrollbar consistency).
- Adds test_index_html_ast78_polish_markers — guards every marker
  introduced by this pass (section-body, tbtn, sql-results, svc-flip,
  table-scroll, svc-terminal, __MONITOR_PREVIEW__) and every removed
  element (env-pill, id="auto", incidents strip, #sql-result id).
- Changelog entry.

Fixes AST-78

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

## Task 10: Preview walkthrough + PR

**Files:** None.

- [ ] **Step 1: Final preview walkthrough (user-facing pre-merge gate 1)**

Boot the preview server and surface BOTH URLs in the preview tab. Walk every section with the user before opening the PR — the brainstorm made this an explicit gate.

```bash
python3 scratchpad/monitor-preview-server.py 8765 &
echo "Mock mode:   http://127.0.0.1:8765/?preview=1"
echo "Empty mode:  http://127.0.0.1:8765/"
```

Wait for explicit user approval before proceeding. If changes are requested, return to the relevant task, amend the commit, and re-preview.

- [ ] **Step 2: Push the branch**

```bash
git push -u origin feature/ast-78-monitor-dashboard-polish
```

- [ ] **Step 3: Open the PR to `development`**

```bash
gh pr create --base development --title "[backend] AST-78 monitor dashboard UI/UX polish pass" --body "$(cat <<'BODY'
## Summary

Bundled UI/UX polish for the OCI monitor dashboard (12 Linear
subissues + 2 scope extensions). Frontend-only — no routes,
migrations, or env vars touched.

### Removed
- PROD env-pill from header (AST-79)
- Decorative green dot on `budget alert · armed` — semantic dot on
  `WITHIN CAPS` badge intact (AST-80)
- Auto-refresh toggle UI — timer runs unconditionally every 30s (AST-81)
- "Incidents · last 24h" timeline card + section-head incidents count (AST-89)
- STATUS column from backups history table (AST-90)

### Added
- Collapsible section heads with rotating chevron + localStorage
  persistence (`monitor_collapsed_v1`). Defaults: COST + SERVICE HEALTH
  expanded; 10 others collapsed (AST-83)
- Status-code bar rows become click-to-dim toggles; top-right count
  pills removed (AST-84)
- Sky-blue RPS / coral p95 chart palette (AST-85)
- Six-card skeleton for service health with amber NO DATA badges and
  dimmed placeholders on fetch failure (AST-86)
- Styled primary button class `.tbtn` (Run ⌘↵) + select class `.sel`
  for SQL console (AST-87)
- SQL console results section — labeled, scrollable, safe-DOM table
  renderer, styled `.sql-error` box (AST-88)
- `.table-scroll` wrapper + sticky `thead` on every dashboard table (AST-91)
- Service-card per-card refresh relocated inline next to the copy-icon
  on the image/tag row
- Terminal-icon button replaces per-card refresh in the header; card
  flips in 3D to a stub terminal face. Real exec channel ships in
  AST-92.

### Verification
- Preview walkthrough against `?preview=1` (mock mode) and `/`
  (empty-state) URLs — screenshots attached.
- `frontend-design` skill pass applied as commit 9.
- `pytest backend/monitor/tests/test_main.py -v` — all three tests
  green, including the new `test_index_html_ast78_polish_markers`
  regression guard.

Fixes AST-78
Fixes AST-79
Fixes AST-80
Fixes AST-81
Fixes AST-83
Fixes AST-84
Fixes AST-85
Fixes AST-86
Fixes AST-87
Fixes AST-88
Fixes AST-89
Fixes AST-90
Fixes AST-91

## Test plan
- [ ] Preview server renders all sections correctly in mock mode
- [ ] Preview server renders skeleton + NO DATA in empty-state mode
- [ ] Collapsible state persists across reloads
- [ ] Status-code row click toggles dim/restore
- [ ] Terminal button flips card; '✕' flips back
- [ ] SQL console run surfaces styled results or error
- [ ] pytest backend/monitor/tests/test_main.py passes

🤖 Generated with [Claude Code](https://claude.com/claude-code)
BODY
)"
```

Expected: PR URL returned. Share it back to the user.

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Covered by task |
|---|---|
| AST-79 PROD pill removal | Task 2 step 1 |
| AST-80 decorative dot | Task 2 step 4 |
| AST-81 auto toggle + timer unconditional | Task 2 steps 2–3 |
| AST-83 collapsible + localStorage | Task 3 |
| AST-84 status-code bar toggles | Task 5 |
| AST-85 chart color changes | Task 4 steps 1–2 |
| AST-86 skeleton + empty states | Task 6 |
| AST-87 tbtn/sel classes | Task 7 step 1 |
| AST-88 SQL results section + safe renderer | Task 7 steps 1–3 |
| AST-89 incidents removal | Task 2 step 5 |
| AST-90 backups STATUS column | Task 2 step 6 |
| AST-91 table-scroll + sticky thead | Task 1 + Task 4 steps 3–5 + Task 7 step 1 |
| AST-78-ext1 refresh relocation | Task 8 step 3 |
| AST-78-ext2 terminal flip stub | Task 8 |
| tbtn, sel, sql-error, table-scroll, collapsible, svc-flip, svc-dim CSS | Task 1 |
| STATE.collapsed, STATE.statusFilter, STATE.flippedCards | Tasks 3, 5, 8 |
| renderServices skeleton rewrite | Task 6 |
| refreshAll empty-data path + _warnedUnreachable | Task 6 step 4 |
| genData preview-flag gate + __MONITOR_PREVIEW__ setter | Task 6 steps 1–2 |
| Smoke test | Task 9 |
| Preview-server demo gate | Task 10 step 1 |
| frontend-design skill pass | Task 9 step 2 |
| Changelog entry | Task 9 step 5 |
| PR with per-subissue Fixes AST-NN lines | Task 10 step 3 |

All 10 spec sections accounted for.

**Type consistency:** `STATE.collapsed` is a plain object (`{sec-id: bool}`) everywhere. `STATE.statusFilter` is a `Set<string>` in Task 5. `STATE.flippedCards` is a `Set<string>` in Task 8. `SVC_ORDER` is defined once in Task 6 and referenced only from `renderServices`. `runSQL` uses `#sql-results-body` (not `#sql-result`) consistently after Task 7. `emptyData()` signature matches `genData` return shape in Task 6.

**Placeholder scan:** No TBDs, TODOs, or unbounded phrases. Every code block is complete. Every step that describes an edit shows the exact before/after strings (except for a few cases in Tasks 5 / 7 / 8 where the edit pattern is repeated and described in prose — these are small tweaks inside templates the plan has already shown in full).

**Scope check:** Single-surface UI polish. One PR. Within reach of one plan.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-22-monitor-dashboard-polish-plan.md`. Two execution options:

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks. Best for the long Task 6 and Task 8 which have the biggest individual diffs.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints. Faster end-to-end but the plan is long enough that context management matters.

Which approach?

