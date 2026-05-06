# Monitor Dashboard Formalization — Design

**Date:** 2026-05-06  
**Status:** Approved for spec; awaiting user review before implementation plan  
**Surface:** `backend/monitor/`, especially `monitor.bg`, `monitor.schema`, `monitor.collectors.requests_`, `monitor.static/index.html`, and `monitor.static/controls.js`  
**Intent:** Formalize the monitor dashboard so it explains metrics clearly, filters each panel appropriately, and preserves user interaction state during background refresh.

## Summary

The monitor dashboard currently works as a compact operational surface, but it still carries signs of its initial "added-on" implementation:

- Request metrics mix real Astral app traffic with public internet probe traffic.
- Slow endpoint rows can show scanner payloads such as CGI traversal probes, SMB negotiation bytes, and raw TLS bytes.
- Several controls are visual or local-only rather than grounded in a consistent metric contract.
- Background refresh rebuilds service-card DOM, so a user working on the terminal side of a card can be flipped back to the front side.

This design keeps the dashboard's current visual direction, but formalizes the data model and interaction model. The default dashboard answers: **is Astral healthy?** Scanner/noise traffic is hidden by default and available only through explicit request filters.

## Goals

- Default Requests view shows Astral app traffic only.
- Scanner/noise traffic is classified and hidden unless explicitly selected.
- Every UI panel has controls that make sense for that panel's data.
- Existing global time range remains global.
- Filtered totals, charts, status bars, slowest tables, and diagnostic output all agree because they are computed from the same filtered record set.
- Background refresh updates data without resetting active UI state.
- Service-card terminal/front-face state survives refresh.
- Extensive logging and debugging aids make failures traceable to a specific pipeline stage, filter, classification rule, or renderer.
- Tests cover traffic classification, filter consistency, and refresh stability.

## Non-Goals

- No Grafana/Prometheus replacement.
- No new SaaS dependency.
- No broad visual redesign.
- No iOS app changes.
- No production deploy actions in this design/spec step.
- No full terminal exec implementation unless already covered by the existing AST-92 follow-up; this design only requires terminal face state to be preserved and prepared for real controls.

## Existing Architecture

The monitor is a separate FastAPI sidecar under `backend/monitor`.

```
nginx access.log / docker / redis / postgres / OCI
        │
        ▼
backend/monitor/bg.py background samplers
        │
        ▼
backend/monitor/collectors/*
        │
        ▼
GET /metrics validated by monitor.schema.MetricsResponse
        │
        ▼
static dashboard: index.html + controls.js
```

Relevant current behavior:

- `nginx_access_sampler` parses `/var/log/nginx/access.log` and computes request windows.
- `requests_.collect(window)` reads `NGINX_WINDOW_CACHE`.
- The UI calls `refreshAll()` every 30 seconds and then calls `renderAll()`.
- `renderServices()` replaces `#svc-grid.innerHTML`, which recreates card DOM and loses the terminal flip state.

## Approved Approach

Use **contract-backed panel filters**.

The backend owns shared metric meaning, especially request traffic classification. The frontend owns panel-specific controls and visual state. This avoids a UI-only patch where different renderers can quietly disagree about which records are included.

## Request Traffic Classification

Every parsed nginx access-log record gains a `traffic_class`.

Classes:

- `app`: Astral product/API usage. Default Requests view. Includes `/api/...` and any future product routes that represent real app behavior.
- `static`: media/static delivery, such as `/static/...`.
- `monitor`: monitor/dashboard traffic, such as `/monitor`, `/metrics`, `/control/...`, and monitor static assets.
- `noise`: exploit probes, traversal attempts, malformed protocol bytes, and known non-Astral public-host scans.
- `unknown`: valid HTTP that does not match a known Astral bucket.

The pasted examples are classified as `noise`:

- `POST /cgi-bin/.%2e/.../bin/sh`
- `POST /cgi-bin/%%32%65.../bin/sh`
- SMB-looking bytes beginning with `\x00\x00\x001\xFFSMB...`
- TLS-looking bytes beginning with `\x16\x03\x03...`

`POST /monitor/control/exec/start` is `monitor`, not app traffic.

## Requests Panel Contract

The Requests panel defaults to `traffic_class=app`.

Requests filters:

- Traffic class: `app` default; optionally `static`, `monitor`, `unknown`, `noise`.
- Method: all, GET, POST, DELETE, other.
- Status band: 2xx, 3xx, 4xx, 5xx.
- Path search: substring match.
- Ranking mode: slowest p95, highest count, highest error rate.

Filtered outputs:

- RPS chart.
- p95 chart.
- Headline RPS, p95, total.
- Status-code bars.
- Ranked endpoints table.
- Endpoint drill-down.
- `__diag()` requests block.

All of those outputs must be computed from the same filtered set. The UI must not apply one filter to the table and a different filter to totals.

Implementation shape:

- Keep `/metrics?range=6h` as the full-dashboard aggregate and make its embedded `requests` block use the default app-traffic filter.
- Add a dedicated request endpoint for panel-local request filtering:
  - `GET /metrics/requests?range=6h&traffic=app&method=all&status=all&q=&rank=p95`
  - The endpoint returns the same `RequestsBlock` shape plus active filter metadata if useful.
- Request-filter UI changes call the dedicated endpoint and update only the Requests panel state, not the whole dashboard.

This keeps global refresh simple while making the Requests panel independently filterable.

## Frontend State Model

Split frontend state into three explicit trees.

```js
STATE = {
  range: "6h",
  data: {},
  filters: {
    requests: {},
    services: {},
    logs: {},
    arq: {},
    storage: {},
    backups: {},
    deploys: {},
    audit: {},
    sql: {}
  },
  ui: {
    serviceCards: {},
    scroll: {},
    focused: null
  }
}
```

Rules:

- `STATE.data` may be replaced on refresh.
- `STATE.filters` persists panel controls.
- `STATE.ui` persists interaction state that is not metric data.
- Background refresh must not clear focused input text, SQL input, terminal input, log search, table scroll, service-card face, or expanded details.
- LocalStorage is allowed for useful defaults, but not required for every transient state.

## Panel Controls

Keep the existing global time-range control. Add panel-local controls that match each panel.

### Requests

Controls listed in the Requests panel contract. Defaults to Astral app traffic. Noise is rarely used and should be hidden behind an explicit selection, not surfaced as a headline panel.

### Service Cards

Front face:

- Metric view selector: CPU, memory, CPU+memory, restarts/health.
- Per-card refresh remains local to that service.
- Card face state survives global and per-card refresh.

Back face:

- Terminal/session controls scoped to the service card.
- Preserve face, focused input, scrollback, live/pause state, and output during background refresh.
- For now, terminal implementation may remain a stub if AST-92 is still the owner of real exec.

### Logs

Controls:

- Service.
- Minimum level.
- Text search.
- Live/pause.
- Ordering.
- Hide monitor refresh noise when useful.

### ARQ

Controls:

- Active/completed/failed.
- Source.
- Job function.
- Retryable-only for failed rows.

### Storage

Controls:

- Unit/view mode where helpful.
- Trend series visibility: postgres, media, block free, object storage.

### Backups

Controls:

- Status.
- Age/window.
- Bucket when more than one source exists.

### Deploys

Controls:

- Actor.
- Commit search.
- Healthy/failed.
- Image search.

### Audit

Controls:

- Action.
- Outcome.
- Source IP or actor when available.
- Text search.

### SQL

Controls:

- History.
- Row limit.
- Result-table search.
- Column visibility when practical.

## Refresh Stability

The core bug is that refresh rebuilds interactive DOM and loses UI state.

Required behavior:

- A flipped service card stays flipped after background refresh.
- A card's terminal side remains visible while its metrics update.
- Focused inputs are not cleared or blurred by refresh.
- SQL text and result table do not disappear on unrelated metric refresh.
- Logs and tables preserve scroll where practical.

Possible implementation patterns:

- Patch existing DOM nodes instead of wholesale `innerHTML` replacement for interactive surfaces.
- Or keep replacement rendering, but snapshot and restore `STATE.ui` immediately after render.

The implementation plan should favor the smallest reliable change. Service cards are the highest-priority surface because they have a known bug.

## Error And Empty States

The dashboard must distinguish:

- No app traffic in the selected window.
- Metrics collector unavailable.
- Filters hide all rows.
- Noise exists but is hidden by the current filter.

Degraded metadata should continue to use the existing amber section-dot pattern. Where useful, the degraded reason should name the affected panel/filter.

## Debuggability And Accountability

The implementation must assume dashboard behavior will need to be audited. When the UI looks wrong, it should be easy to determine which stage was wrong:

1. Raw nginx record parsing.
2. Traffic classification.
3. Window filtering.
4. Panel-specific filters.
5. Backend response serialization.
6. Frontend normalization.
7. Renderer output.

### Backend Structured Logs

Add structured monitor logs for the request metric pipeline:

- Sampler tick start/end with record counts, parse failures, selected windows, and elapsed time.
- Classification counts per window: `app`, `static`, `monitor`, `noise`, `unknown`.
- Top parse-failure examples, redacted and capped.
- Top noise examples, redacted and capped.
- Active request filter params and resulting included/excluded counts.
- Endpoint rank mode and candidate count.
- Collector degraded reasons, timeout stage, and whether last-good data was served.

Logging must be useful without leaking secrets:

- Never log auth headers, cookies, SQL result values, monitor control token, or full query strings containing token-like parameters.
- Cap example strings to a short length.
- Use stable reason codes instead of free-form-only messages.

### Classification Reason Codes

Traffic classification should return both class and reason internally:

```python
TrafficClassification(
    traffic_class="noise",
    reason="cgi_traversal_probe",
)
```

Reason codes should be stable enough for tests and diagnostics. Initial examples:

- `api_path`
- `static_path`
- `monitor_path`
- `cgi_traversal_probe`
- `binary_or_malformed_request`
- `known_probe_path`
- `valid_unknown_path`

The public `/metrics` response does not need to include every per-record reason. Debug surfaces can expose summarized reason counts.

### Debug Endpoints

Add a read-only, Basic-Auth-protected debug surface for request metrics:

- `GET /metrics/requests/debug?range=6h&limit=25`

The response should include:

- Active default filters.
- Counts by traffic class.
- Counts by classification reason.
- Parse failure count.
- A small redacted sample of included records.
- A small redacted sample of excluded/noise records.
- Sampler timestamp and elapsed time.

This endpoint is for diagnosis, not the normal dashboard render path.

### Frontend Debug Helpers

Extend the existing diagnostic helper pattern:

- `window.__diag()` includes active filters, request traffic-class counts, and whether Requests data came from `/metrics` or `/metrics/requests`.
- Add a focused request helper, for example `window.__diagRequests()`, that prints:
  - Current request filters.
  - Headline totals.
  - Status-code counts.
  - Table row count.
  - Last request endpoint URL.
  - Last request fetch error, if any.
- Log refresh lifecycle events in development/preview mode:
  - refresh started.
  - response received.
  - render started.
  - UI state restored.
  - refresh finished.

Frontend debug logs should be quiet by default in production. A localStorage flag such as `monitor_debug=1` can enable verbose browser logging.

### UI-Level Debug Affordances

Requests should include a compact "debug" affordance near the panel controls. It can be small and visually quiet, but it should let the user quickly copy a diagnostic bundle for the Requests panel.

The copied bundle should contain:

- Timestamp.
- Build SHA.
- Global range.
- Request filters.
- Traffic-class counts.
- Status-code counts.
- Top ranked endpoint paths.
- Degraded metadata.

This makes it easy to compare "what the UI showed" with "what the backend returned" without pasting the entire `/metrics` payload.

## Testing

Backend tests:

- Traffic classification for app/static/monitor/noise/unknown.
- The pasted scanner examples classify as `noise`.
- `POST /monitor/control/exec/start` classifies as `monitor`.
- Requests collector computes totals, chart series, status bars, and ranked endpoints from the same filtered records.
- Default request collection excludes `noise`, `monitor`, and `static`.
- Classification reason codes are stable for known scanner/probe examples.
- Debug summary counts match the same classified records used by the Requests panel.

Frontend tests or smoke checks:

- Flipped service card survives a mocked `refreshAll()`.
- Requests default hides scanner paths.
- Request filters survive refresh.
- Log filters survive refresh.
- Focused SQL input is not cleared by background refresh.
- Request diagnostic helper reports the same totals visible in the panel.

Schema tests:

- New request filter/class fields validate through Pydantic.
- `MetricsResponse` remains backwards-safe for panels outside Requests.
- Debug response schema validates and redacts sample values.

## Rollout Plan

Phase 1: Metric meaning

- Add request traffic classification.
- Make app traffic the default Requests view.
- Hide scanner/noise rows by default.
- Wire Requests filters to a consistent backend-backed block.
- Add structured request-pipeline logs and debug summary endpoint.
- Add backend tests.

Phase 2: Stable refresh

- Introduce `STATE.filters` and `STATE.ui`.
- Preserve service-card face state through refresh.
- Preserve focused inputs and scroll state for the highest-risk panels.
- Add frontend diagnostic helpers for refresh and Requests panel state.
- Add frontend smoke coverage where practical.

Phase 3: Panel controls

- Add purpose-built controls across services, logs, ARQ, storage, backups, deploys, audit, SQL, and terminal faces.
- Keep visual style consistent with the existing dashboard.
- Avoid decorative or non-functional controls.

## Risks

- Over-filtering could hide legitimate traffic. Mitigation: `unknown` remains available and separate from `noise`.
- UI-only filtering could cause mismatched totals. Mitigation: shared filtered request block and collector tests.
- DOM patching could make renderers harder to understand. Mitigation: prioritize explicit `STATE.ui` restoration first if it is simpler.
- LocalStorage filter state could become stale across releases. Mitigation: version any persisted filter keys.
- Verbose logs could create noise or leak sensitive data. Mitigation: structured reason codes, redaction, capped samples, and production-quiet frontend debug logs.

## Approval Notes

User-approved design decisions:

- Requests defaults to Astral traffic.
- Scanner/noise traffic is hidden and rarely used.
- Keep global time filter.
- Add per-panel controls where they make sense for the UI element.
- Terminal/card faces need their own controls and must not be reset by background refresh.
- Add extensive logging and debugging aids because AI-generated behavior needs to be easy to audit when it is wrong.
