# AST-58 — Monitor dashboard: real-data pass

**Date**: 2026-04-21
**Status**: Approved, ready for implementation plan
**Linear**: AST-58 (to be filed)
**Follows**: [AST-57 OCI monitor dashboard](https://linear.app/nnetraganti/issue/AST-57/backend-oci-monitor-dashboard-monitor-metrics)

## Summary

AST-57 shipped the monitor dashboard with a pixel-locked UI and a working `/metrics` endpoint. Several cards still render placeholder or hardcoded values. This pass closes the gap: every rendered number becomes live, three always-mock sections are removed, and two real bugs surfaced during smoke testing get fixed.

## Goals

- Every rendered panel on `/monitor/` shows live data or an explicit `—` / degraded marker. No hardcoded stubs, no fantasy numbers.
- Delete sections that were never backed and never will be on a solo-dev $0/month stack.
- Fix two data-layer bugs that crept in during AST-57 deploy: the DOWN-badge false positives and the empty Request Metrics panel.
- Keep prod-API code untouched. All changes are monitor-only + nginx config.

## Non-goals

- FastAPI request-counter middleware (the cheap `last 60s of /api/* from nginx log` approach wins for this pass).
- Resize-aware A1 OCPU/RAM reporting — hardcoded `4/4` and `24/24` stay (correct today; rewriting the shape equals a tenant-scale change, which is not this ticket).
- Storage trend-delta labels (`+32MB / 7d`) — wait for the hourly hoister to accumulate real 7d history first.
- Visual redesign — pixel-lock to the handoff is preserved.

## Scope — 9 items

### 1. Delete three always-mock sections

`backend/monitor/static/index.html`. Remove the following HTML ranges (header + body):

- §1b **SLO & Error Budget** — synthesized fake error-budget grid
- §3b **Uptime Checks** — 5 region probes that never fire
- §7b **Recommendations** — 4 static advisory cards

No JS to remove; all three were populated from static HTML, no renderers touched them. Keep `genDataMock()` intact (harmless dev fallback).

### 2. `renderCert(d.cert)` — wire the existing cert block

Cert card currently shows hardcoded HTML. A proper renderer replaces the static cells and adds a color-coded days-left badge.

- New `function renderCert()` called from `renderAll()`.
- Pulls `domain`, `issuer`, `not_before`, `not_after`, `days_left`, `last_renew.at`, `last_renew.status` from `STATE.data.cert`.
- Days-left color: `green >30`, `amber 14–30`, `red <14`. Matches handoff §8.
- Needs unique DOM ids on the cert card cells. If they don't already exist, add `id="cert-domain"`, `id="cert-issuer"`, `id="cert-days-left"`, etc.

### 3. Container-ID copy pills from real state

`renderServices` currently hardcodes per-card copy pills:

```js
`${s.name === 'certbot' ? 'ab12cd34ef56' : 'abc'+s.name.slice(0,2)+'f9d1b2'}`
```

Replace with `s.container_id.slice(0, 12)` + `data-copy="${s.container_id}"`. `container_id` is already on every `ServiceBlock`.

### 4. `renderCost(d.cost)` — drive all 5 gauges

Cost tripwire card shows `4/4 ocpu`, `24/24 GB RAM`, `152/200 GB block`, `0.18/10 TB egress` as **static HTML**. Only the egress gauge is currently updated dynamically (by my AST-57 code in `renderAll`).

- New `function renderCost()` called from `renderAll()`, takes over all 5 gauge + spend updates. Removes the inline egress logic from `renderAll()`.
- Adds ids on the cost card (`#ocpu-used`, `#ocpu-cap`, `#gauge-ocpu`, analogous for ram / vol / egress) where missing.
- Updates `#cost-spend-mtd`, `#cost-spend-forecast`, `#cost-spend-budget`.
- Computes worst-case % across the 5 gauges: if any > 80%, swap the section-head badge from `<badge-ok>WITHIN CAPS</badge-ok>` to `<badge-warn>APPROACHING CAP</badge-warn>`.

### 5. Real OCI egress via Usage API

The `egress_tb.used: 0.18` in `cost.py` is a lie — I pinned it when writing the collector. Real egress needs `UsageClient.request_summarized_usages(...)`.

- New `_fetch_egress()` in `backend/monitor/collectors/cost.py`:
  - Call `oci.usage_api.UsageapiClient.request_summarized_usages` with:
    - `tenant_id = OCI_TENANCY_OCID`
    - `time_usage_started = start of current calendar month (UTC)`
    - `time_usage_ended = now (UTC)`
    - `granularity = MONTHLY`
    - `query_type = USAGE`
    - `group_by = ["service"]`
    - Filter result for service name matching `Networking` or `Outbound Data Transfer`.
  - Sum reported units, convert to TB.
  - Wrapped in `asyncio.to_thread` (sync SDK call).
- `cost.collect()` runs `_fetch_budget()` and `_fetch_egress()` concurrently via `asyncio.gather` so cost collector wall-time stays ≈ one API round-trip.
- `_fetch_always_free()` reads the egress value from its sibling's result instead of the hardcoded constant.
- On failure: fallback to last-good OR `egress_tb.used: 0` + `egress_meta.degraded=True`.

**OCI side (runbook, not repo code):** append one statement to `astral-monitor-policy`:

```
Allow dynamic-group astral-a1-backup to read usage-reports in tenancy
```

### 6. nginx `stub_status` for real active-connections + request totals

Dashboard currently approximates `active_connections` as "last-bucket rps" (bad proxy). Real data comes from nginx's built-in `ngx_http_stub_status_module`.

- `backend/nginx/nginx.conf` — add a private location on the existing server block:

  ```nginx
  location = /nginx_status {
      stub_status;
      allow 172.19.0.0/16;   # compose net — monitor container
      deny all;
  }
  ```
  No auth_basic needed because the `deny all` handles everyone outside the compose net.

- New helper `backend/monitor/collectors/_nginx_stub.py`:
  - Async `fetch_nginx_stats() -> dict` using `httpx.AsyncClient` against `http://nginx/nginx_status`.
  - Parses the 7-line text response (`Active connections: N` + `server accepts handled requests` + `N N N` + `Reading/Writing/Waiting: N N N`) into a dict.

- `bg.py._fetch_service_extra("nginx")` uses this helper. If the scrape fails, fall back to the current last-bucket-rps approximation (already in place).

### 7. Narrow fastapi rps to last-60s `/api/*` traffic

`_fetch_service_extra("fastapi")` currently reads `NGINX_WINDOW_CACHE["1h"]` and takes the last bucket, which is still a 1-minute average over 1h of history. Not useful.

- `nginx_access_sampler` gains one additional window computation: `NGINX_WINDOW_CACHE["1m_api"]`.
  - Window size: 60 seconds.
  - Path filter: only records where `path.startswith("/api/")`.
  - Emits same schema: `{series_rps, series_p95_ms, status_codes, slowest, window: "1m_api"}`.
- `_fetch_service_extra("fastapi")` reads `NGINX_WINDOW_CACHE["1m_api"]`, takes the full-window rps (not last bucket), formats as `f"{rps:.2f}"`.

### 8. Fix `DOWN` badge false positives

Backend bug. `_sample_once` writes `health = None` for any container that has no `healthcheck:` directive (which is all 7 services except postgres + astral_monitor). UI renderer treats `s.health !== 'healthy' && s.health !== 'starting'` as `DOWN`.

Backend fix in `bg.py._sample_once`:

```python
health = health_obj.get("Status") if isinstance(health_obj, dict) else None
if health is None and status == "running":
    health = "healthy"
```

Absence of a healthcheck is not evidence of unhealthiness. Containers where status is anything but `running` keep `health = None`, and the renderer correctly flags them.

### 9. Diagnose + fix empty Request Metrics

Symptom: chart flat at 0, status codes all 0. Means `nginx_access_sampler` read no parseable records.

Diagnostic steps (run during deploy, fix whichever applies):

- **(a) Volume-mount check**: `docker exec backend-nginx-1 tail /var/log/nginx/access.log` — should show recent lines. If empty: nginx isn't writing there (wrong `access_log` path or volume mount failed).
- **(b) Log-format check**: if lines exist but sampler isn't parsing them, dump one line through the `_LOG_RE` regex. If it returns `None`, nginx's active `log_format` has drifted from `astral` back to `combined`.
- **(c) Cadence check**: the sampler runs every 60 s. If the dashboard has been open < 1 minute, show "(no data yet)" rather than zeros.

Expected fix location:
- (a) compose volume spec, already `nginx_access_logs:/var/log/nginx:rw` on nginx and `:ro` on monitor — verify during deploy.
- (b) nginx.conf `log_format astral '...'` + `access_log /var/log/nginx/access.log astral;` — verify at runtime via `docker exec backend-nginx-1 nginx -T`.
- (c) UI change: in `renderRequests`, if `r.status_codes` sum == 0 AND `r.series_rps` length <= 1, show "(no traffic in this window)" instead of rendering a flat chart. Small JS tweak.

## Files touched

### Modify

- `backend/monitor/static/index.html` — delete 3 sections; add `renderCert` + `renderCost`; swap container-ID pill logic; call both new renderers from `renderAll`; "no traffic" placeholder in `renderRequests`; ensure required `id=...` attrs exist on cert + cost cards.
- `backend/monitor/bg.py` — health-status synthesis (item 8); `nginx_access_sampler` emits additional `1m_api` window (item 7); `_fetch_service_extra("nginx")` uses `_nginx_stub`; `_fetch_service_extra("fastapi")` reads `1m_api`.
- `backend/monitor/collectors/cost.py` — new `_fetch_egress()`; `cost.collect()` uses `asyncio.gather`; `_fetch_always_free()` reads real egress.
- `backend/nginx/nginx.conf` — add `location = /nginx_status` block.

### Create

- `backend/monitor/collectors/_nginx_stub.py` — async fetch + parse helper.
- `backend/monitor/tests/collectors/test_nginx_stub.py` — parser unit tests.
- `backend/monitor/tests/collectors/test_cost_egress.py` — mocked Usage API test.
- `backend/monitor/tests/test_nginx_access_sampler_1m_api.py` — window-emission test.
- `backend/monitor/tests/test_health_synthesis.py` — _sample_once health-synthesis test.

### OCI-side (runbook only)

- Append one policy statement to `astral-monitor-policy` for `usage-reports`.

## Testing

- Per-new-module unit tests (above). ~10 new tests.
- Full suite: `cd backend && python3 -m pytest monitor/tests/` should stay green (currently 40 passing; after this pass, ~50).
- Smoke-test on the A1 post-deploy: open `/monitor/`, visually confirm every card renders live data. Induce `docker compose stop redis` and confirm appropriate degraded dots.

## Deploy risk

Low. No prod-API code touched. Changes are additive on monitor side (2 new renderers, 1 new collector helper, 1 new OCI call) + subtractive on HTML (3 section deletes) + a one-liner backend health fix. The nginx.conf change adds one internal-only location. Rollback = revert the PR.

## References

- AST-57 spec: [docs/superpowers/specs/2026-04-21-oci-monitor-dashboard-design.md](2026-04-21-oci-monitor-dashboard-design.md)
- Handoff: `/Users/nicknetraganti/Downloads/design_handoff_oci_monitor/`
- OCI Usage API: <https://docs.oracle.com/en-us/iaas/api/#/en/usage-api/20200107/>
- nginx `ngx_http_stub_status_module`: <https://nginx.org/en/docs/http/ngx_http_stub_status_module.html>
