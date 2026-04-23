# AST-78 — Monitor dashboard UI/UX polish pass

**Date:** 2026-04-22
**Linear parent:** [AST-78](https://linear.app/nnetraganti/issue/AST-78/monitor-dashboard-uiux-polish-pass)
**Branch:** `feature/ast-78-monitor-dashboard-polish` (off `development`)
**Surface:** `backend/monitor/static/index.html` + `backend/monitor/static/controls.js`
**Backend impact:** none (no routes, migrations, env vars)

---

## 1. Summary

A front-end-only polish pass on the OCI monitor dashboard. Bundles 12 Linear subissues (AST-79…AST-91, excluding AST-82 which is an unrelated deploy-workflow bug) plus two scope extensions discovered during brainstorming (per-card refresh relocation and a terminal-flip stub). Ships as one PR against `development` with `Fixes AST-NN` lines for every included subissue.

The design intentionally trades Linear's original per-subissue descriptions for a few small reinterpretations that the user preferred during the walkthrough:

- **AST-84** no longer filters the RPS chart — instead the STATUS CODES bar rows themselves become click-to-dim toggles; the four 2xx/3xx/4xx/5xx badges at the top-right of the requests summary are deleted outright.
- **AST-86** no longer silently renders fake-healthy mock data on fetch failure. The fix is "always render 6 cards as a skeleton; on missing data show `NO DATA` + dimmed placeholders," with `genDataMock` preserved only for the local preview server behind a `?preview=1` flag.

Two new items not in Linear:

- **AST-78-ext1** — per-service-card refresh button moves inline next to the copy-icon on the image row.
- **AST-78-ext2** — terminal-icon button replaces the old refresh slot; clicking flips the card (CSS 3D flip) to a terminal face sized to the card. Stub only — emits a `coming soon — AST-92` toast. Real exec channel lives in [AST-92](https://linear.app/nnetraganti/issue/AST-92/monitor-dashboard-docker-exec-terminal-channel-for-service-cards).

## 2. Scope table

| ID | Kind | Change |
|---|---|---|
| AST-79 | remove | Drop `PROD` env-pill from header. |
| AST-80 | remove | Drop decorative green dot on `budget alert · armed`; keep the dot inside the `WITHIN CAPS` badge (semantic). |
| AST-81 | remove | Drop the `auto` refresh toggle from the header. Auto-refresh timer still ticks every 30s silently. |
| AST-83 | add | All `section-head` blocks become clickable; a leading chevron SVG rotates to indicate state. Collapsed/expanded state persists in `localStorage.monitor_collapsed` keyed by section id. Defaults: `sec-cost` and `sec-services` expanded, all others collapsed. |
| AST-84 | modify | Delete the four 2xx/3xx/4xx/5xx count badges at the top-right of the requests summary card. In the STATUS CODES section below, each bar row becomes a toggle that dims/restores itself on click. Toggle state in `STATE.statusFilter` (`Set` of codes). No interaction with `drawRequestChart`. |
| AST-85 | modify | `drawRequestChart` — RPS line stroke `#4FC3F7`, p95 dashed stroke `#FF6B6B`. Legend swatches + text update to match. |
| AST-86 | modify | `renderServices` always renders the six compose-service cards as a skeleton driven by a static list, not by `STATE.data.services`. When a card's data entry is missing, render an amber `NO DATA` badge, `—` placeholders for CPU/MEM/UPTIME, empty sparkline SVG with `no data` text, and `metrics unreachable` in the footer. When data exists but `spark_cpu` is absent, only the sparkline area shows `no data`. `refreshAll`'s catch block now sets `STATE.data` to a typed-empty object and calls `renderAll()` — no fake-healthy fill. `genDataMock` is preserved but gated behind `window.__MONITOR_PREVIEW__` (set from `?preview=1` query param). |
| AST-87 | modify | `#sql-run` — class `ibtn` → `tbtn` (solid-accent gold fill), innerText `Run ⌘↵`. `#sql-history` — class `ibtn` → `sel`. |
| AST-88 | add | New `<div id="sql-results" class="hidden">` below the run bar. Contains a `RESULTS` label, a right-aligned `{n} rows · {ms}ms` meta span, and a `<div class="table-scroll" id="sql-results-body">`. A new `renderSQLTable(result)` function in `controls.js` builds the table via `document.createElement` + `textContent` only (no `innerHTML`); on error it writes into a styled `.sql-error` div. |
| AST-89 | remove | Delete the `<!-- Incidents timeline (GCP Ops) -->` card and the `{N} incidents in 24h` subtitle from the Service Health `section-head`. |
| AST-90 | remove | Drop the `STATUS` column from the backups history table (summary KV cards above already surface status). |
| AST-91 | add | Every scrollable table wraps in `<div class="table-scroll">` (max-height 360px, `overflow:auto`). The single global selector `.table-scroll thead th { position: sticky; top: 0; background: var(--surface); z-index: 1; }` handles all seven tables: slowest endpoints, ARQ completed, ARQ failed, backups history, recent deploys, audit log, SQL results. |
| AST-78-ext1 | add | `.svc-refresh-mini` button rendered inline next to the `.copy` span on the image/tag row of each service card. Identical behavior to the old `.svc-refresh` (calls `refreshService(name)`). |
| AST-78-ext2 | add | `.svc-terminal` button replaces the header-row `.svc-refresh`. Each card wraps in `.svc-flip > .svc-flip-inner > [.svc-face.front, .svc-face.back]`. Clicking terminal toggles `.flipped` class and emits `coming soon — AST-92` toast. Back face contains a fake `pre > $ _` prompt and a flip-back `✕` button top-right. Sized to the card via `position:absolute; inset:0` on `.svc-face.back`. |

## 3. Shared CSS helpers (new, added once to `<style>` in `index.html`)

```css
/* AST-87 */
.tbtn { background: var(--gold); color: #0a0a0a; border: 1px solid var(--gold);
  padding: 6px 14px; border-radius: 8px; font-family: ui-monospace, Menlo, monospace;
  font-size: 12px; letter-spacing: .04em; transition: transform .08s ease, opacity .12s; }
.tbtn:hover { opacity: .9 }
.tbtn:active { transform: scale(.97) }

/* AST-87 */
.sel { background: var(--surface); color: var(--white); border: 1px solid var(--border);
  padding: 6px 10px; border-radius: 8px; font-family: ui-monospace, Menlo, monospace;
  font-size: 12px; }

/* AST-88 */
.sql-error { background: rgba(255,107,107,.08); border: 1px solid rgba(255,107,107,.4);
  color: #FF9A9A; padding: 10px 12px; border-radius: 8px;
  font-family: ui-monospace, Menlo, monospace; white-space: pre-wrap; }

/* AST-91 */
.table-scroll { max-height: 360px; overflow: auto; border-radius: 8px; }
.table-scroll thead th { position: sticky; top: 0; background: var(--surface); z-index: 1; }

/* AST-83 */
.section-head { cursor: pointer; user-select: none; }
.section-head .chev { transition: transform .18s ease; }
.section-head.collapsed .chev { transform: rotate(-90deg); }
.section-body.collapsed { display: none; }

/* AST-78-ext2 */
.svc-flip { perspective: 1200px; }
.svc-flip-inner { position: relative; transition: transform .5s; transform-style: preserve-3d; }
.svc-flip.flipped .svc-flip-inner { transform: rotateY(180deg); }
.svc-face { backface-visibility: hidden; }
.svc-face.back { position: absolute; inset: 0; transform: rotateY(180deg); }

/* AST-86 */
.svc-dim { opacity: .5; filter: grayscale(.3); }
.spark-empty { font-size: 10px; color: var(--muted); letter-spacing: .12em; }
```

## 4. State model additions (`controls.js`)

```js
STATE.collapsed = JSON.parse(localStorage.getItem('monitor_collapsed') || 'null')
                ?? { 'sec-cost': false, 'sec-services': false,
                     'sec-requests': true, 'sec-arq': true, 'sec-storage': true,
                     'sec-backups': true, 'sec-cert': true, 'sec-logs': true,
                     'sec-flags': true, 'sec-deploys': true,
                     'sec-sql': true, 'sec-audit': true };
STATE.statusFilter = new Set(['2xx','3xx','4xx','5xx']);
STATE.flippedCards = new Set();
```

The existing `STATE.autoRefresh` is removed; the refresh `setInterval` runs unconditionally.

## 5. Error / empty-state contract (AST-86)

`renderServices(data)` flow:

1. Source of truth for the card list: a static array `SVC_ORDER = ['postgres','redis','fastapi','arq_worker','nginx','certbot']`. Never derived from `STATE.data.services`.
2. For each name, `const entry = (STATE.data.services || []).find(s => s.name === name)`.
3. Missing entry → render card with:
   - amber `NO DATA` badge where `UP/STARTING/DOWN` would go
   - `.svc-dim` class applied to the card body
   - `—` in CPU, MEM, UPTIME positions
   - sparkline `<svg>` containing only `<text class="spark-empty" x="4" y="50%">no data</text>`
   - footer text `metrics unreachable`
4. Entry present but `spark_cpu` missing/empty → same sparkline fallback, all other values render normally.
5. Entry present, `spark_cpu` present → as today.

`refreshAll`:

```js
async function refreshAll() {
  try {
    STATE.data = await genData(STATE.range);
  } catch (e) {
    console.error('refreshAll failed', e);
    STATE.data = emptyData();      // typed empty object
    if (!STATE._warnedUnreachable) { toast('metrics unreachable'); STATE._warnedUnreachable = true; }
  }
  renderAll();
}
```

The `_warnedUnreachable` flag prevents toast spam on successive 404s.

`genData(range)` (the existing fetch-from-`/metrics` function) short-circuits to `genDataMock(range)` at its top when `window.__MONITOR_PREVIEW__ === true` — the flag is set by an inline `<script>` in `index.html` from `new URLSearchParams(location.search).has('preview')`. Prod builds never see the flag set, so `genDataMock` is only reachable through the local preview server; the empty-state path is what runs against a reachable-but-quiet backend, and the `catch` branch of `refreshAll` is what runs against a 404ing backend. The two states look the same to the user (skeleton + `NO DATA`) — the distinction exists so `metrics unreachable` only toasts on the fetch-failure path.

## 6. Build sequence (commits within the single PR)

Ordered so each commit is independently buildable and previewable:

1. `[backend] AST-78 add shared CSS helpers` — CSS-only, no behavior change.
2. `[backend] AST-79 AST-80 AST-81 AST-89 AST-90 monitor dashboard removals` — pure deletions (PROD pill, auto toggle, armed dot, incidents strip, backups STATUS column).
3. `[backend] AST-83 collapsible section-heads with localStorage` — body wrapping, chevron insertion, delegated click handler, defaults.
4. `[backend] AST-85 AST-91 request chart colors + sticky-header table scroll` — two small independent changes.
5. `[backend] AST-84 status-code bar toggles` — filter set, click handlers, dim class.
6. `[backend] AST-86 service-card skeleton + no-data states` — renderServices rewrite, refreshAll refactor, preview flag.
7. `[backend] AST-87 AST-88 SQL run button + results section` — both SQL items together.
8. `[backend] AST-78 service-card refresh relocation + terminal flip stub` — the two scope extensions; terminal back-face is stub only.
9. `[backend] AST-78 cache-bust controls.js?v=4 + frontend-code skill polish` — final pass edits from the `/frontend-code` skill review.

## 7. Verification strategy

### Local preview server

Already wired: `.claude/launch.json` contains a `monitor-preview` config that runs `scratchpad/monitor-preview-server.py 8765`. The server mirrors the FastAPI mount layout (`GET /` → `static/index.html`, `GET /static/*` → `static/*`). API endpoints 404 intentionally so the dashboard exercises its empty-state paths.

Two URLs:

- `http://127.0.0.1:8765/?preview=1` — `window.__MONITOR_PREVIEW__=true`, `genDataMock` fills every surface. Use for visual demo and `/frontend-code` skill review.
- `http://127.0.0.1:8765/` — preview flag off, all surfaces render empty-state (AST-86 skeleton, empty ARQ/backups/logs/SQL). Use for regression checks.

### Automated smoke

Extend `backend/monitor/tests/test_main.py` with one new test:

```python
async def test_index_html_contains_expected_sections(async_client):
    r = await async_client.get("/")
    html = r.text
    for needle in ["section-body", "tbtn", "sql-results", "svc-flip", "table-scroll"]:
        assert needle in html, f"missing {needle}"
    for removed in ["env-pill", "incidents-strip", "id=\"auto\"", "monitor_auto_refresh"]:
        assert removed not in html, f"regression: {removed} still present"
```

Protects the removals and the new markers against accidental regressions.

### Pre-merge gates

1. **Preview demo** — boot `monitor-preview`, walk through each section in the preview tab against the mock data; confirm each change matches this spec.
2. **`/frontend-code` skill pass** — invoke the skill against the final diff. Any polish edits (spacing, typography, hierarchy) land in commit 9.
3. **Open PR to `development`** — PR body contains one `Fixes AST-NN` line per subissue plus `Fixes AST-78` so Linear auto-closes the parent. Changelog entry at the top of `CHANGELOG.md` summarizing the batch.

## 8. Out of scope

- Backend docker-exec channel — tracked in [AST-92](https://linear.app/nnetraganti/issue/AST-92/monitor-dashboard-docker-exec-terminal-channel-for-service-cards).
- `actions/checkout@v4` bump and `docker compose up -d` recreate flake — tracked in [AST-82](https://linear.app/nnetraganti/issue/AST-82/deploy-workflow-fix-docker-compose-recreate-flake-bump-actionscheckout).
- Any monitor dashboard feature work (new charts, new endpoints, auth flow redesign) — future issues.

## 9. Risks and mitigations

- **Preview flag leaks to prod.** If `?preview=1` or the sentinel cookie ever appears in a prod request, fake-healthy data would render. Mitigation: sentinel is read from URL only (not localStorage); prod nginx strips query strings on `/` in a belt-and-braces rewrite (already in place for cache headers).
- **Collapsed state corrupts across releases.** If defaults change, stale localStorage `monitor_collapsed` will override them. Mitigation: key includes a schema version suffix (`monitor_collapsed_v1`); bump on incompatible changes.
- **Sticky thead z-index collision with the auth token modal.** The token modal uses `z-index: 50`; `.table-scroll thead th` uses `z-index: 1`. Verified no overlap, but note here for future modal work.
- **3D flip on Safari WebKit sometimes double-paints backface.** Mitigation: `-webkit-backface-visibility: hidden` is set alongside the standard property.

## 10. Open questions

None — all clarifications resolved during brainstorming.
