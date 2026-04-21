# Monitor dashboard — Requests + Logs + time-filter bug fixes

**Date**: 2026-04-21
**Status**: Approved, ready for implementation plan
**Linear**: to be filed (follow-up to AST-57 / AST-58)
**Follows**: [AST-58 monitor real-data pass](2026-04-21-ast58-monitor-real-data-pass-design.md)

## Summary

Three user-visible problems on the live `/monitor/` dashboard:

1. **Requests section shows all zeros** — rps, p95, status codes, slowest endpoints are all empty (`(no traffic in this window)` / `no requests to rank` empty-state copy is rendered).
2. **FastAPI logs and astral_monitor logs don't appear in the Logs view** — even though both containers are actively emitting log lines that are visible via `docker logs`.
3. **Top time-range filter `1h / 6h / 24h / 7d / 30d` appears not to work** — clicking different ranges produces identical Requests data.

All three trace to a small number of shared root causes. This spec covers the minimum set of changes that fixes all three.

## Root causes

### A. nginx access.log is a symlink to `/dev/stdout`

The `nginx:1.25-alpine` image ships with `/var/log/nginx/access.log → /dev/stdout` (a build-time symlink so logs appear in `docker logs`). When compose created the `nginx_access_logs` named volume for the first time, Docker populated it with the image's `/var/log/nginx/` contents — including that symlink. Every subsequent nginx start writes to the symlink (which resolves to the nginx container's stdout), **not to a real file**. The monitor container mounts the same volume `:ro` and reads `/var/log/nginx/access.log`, but from the monitor's side the symlink resolves to the *monitor's* `/dev/stdout`, yielding no useful records. `nginx_access_sampler` therefore finds zero lines matching `_LOG_RE`, and `NGINX_WINDOW_CACHE` stays empty across all five windows.

Consequences:
- Requests section renders zeros (correctly reflecting an empty cache).
- Time filter appears broken because every window returns the same empty `RequestsBlock`.

### B. `_follow_one` starts with `tail=0` and the log deque is too small

`bg._follow_one` opens each compose service's log stream with `tail=0` (docker-py: "no history, only new lines"). On monitor startup, every follower begins from zero history. Quiet services (uvicorn with little traffic, the monitor's own periodic polls) produce sparse new output, so the Logs view looks empty for those services even though log_tailer is working correctly for chatty ones (nginx, postgres).

The deque (`maxlen=500`) compounds this: nginx alone emits one access-log line per proxied request (including the monitor's own `/nginx_status` poll every 10 s, plus dashboard refreshes). Within a few minutes, the most recent 500 lines are nearly all nginx, which starves the 100-line tail that the logs collector returns to the UI. Fastapi and astral_monitor entries end up present in theory but invisible in practice.

### C. UI chip bar has no `astral_monitor` entry

`static/index.html:938-944` hardcodes chips for `all, nginx, fastapi, postgres, redis, arq, certbot`. If the user clicks any chip other than `all`, `astral_monitor` lines are filtered out. This is independent of A and B but surfaces the same symptom.

### D. The "Metrics Explorer" pill bar above the chart is purely decorative

`static/index.html:691-709` renders a GCP-style query pill bar with four chips (`metric`, `agg`, `group by`, `status != 2xx`) and a `PromQL` copy badge. The chips show dropdown carets and hover styles. **None of them have click handlers or data bindings.** They were copied from a design handoff and never wired up. Users click the carets and nothing happens, which contributes to the "Requests section is broken" perception.

### E. Uvicorn access-log verification

Not yet confirmed whether the prod uvicorn invocation has access logs enabled. If disabled (`--no-access-log` or `--log-level=warning`), fastapi stdout is genuinely quiet between errors and `tail=200` alone won't help. This is a single-line check against the fastapi Dockerfile / compose command.

## Goals

- Requests section renders real numbers within one `nginx_access_sampler` tick (≤60 s) of deploy.
- Clicking `1h / 6h / 24h / 7d / 30d` produces visibly different values in the Requests section when the windows actually differ.
- Logs view shows fastapi and astral_monitor lines within a few seconds of any relevant activity.
- The decorative "Metrics Explorer" bar is removed — the UI no longer suggests interactivity that doesn't exist.
- All changes ship as one PR. Existing CD workflow deploys them via the same `push origin development` flow.

## Non-goals

- Wiring up a real Metrics Explorer (metric/agg/group-by switcher). This is a proper feature, not a bugfix; file as a follow-up ticket if wanted.
- Per-service round-robin in the logs collector (return last 60/svc instead of last 400 mixed). Only consider if bumping the deque + UI limit doesn't fix log starvation in practice.
- Custom nginx Dockerfile. A compose `command:` override solves the symlink in one line.
- Changing nginx's log format or any prod-API code paths.

## Scope — 5 changes

### 1. Fix nginx `access.log` to write to a real file

**File**: `backend/docker-compose.yml`

Override the nginx service's `command:` to delete the symlinks before launching:

```yaml
nginx:
  image: nginx:1.25-alpine
  command: >
    sh -c "rm -f /var/log/nginx/access.log /var/log/nginx/error.log &&
           exec nginx -g 'daemon off;'"
```

Idempotent (the `rm -f` is a no-op once the symlinks are gone). Runs on every container start. No image rebuild needed.

**One-time cleanup on OCI server** after deploy — the existing stale symlinks in the volume need to go:

```bash
# Option A — drop the volume entirely (no log history to preserve)
docker compose stop nginx
docker volume rm backend_nginx_access_logs
docker compose up -d nginx

# Option B — surgical, keeps the volume
docker compose exec nginx rm -f /var/log/nginx/access.log /var/log/nginx/error.log
docker compose restart nginx
```

Prefer Option B during deploy to avoid any transient race where nginx serves requests before the volume is recreated.

### 2. `tail=0 → tail=200` in `_follow_one`

**File**: `backend/monitor/bg.py` (line ~274)

```python
def _iter():
    return container.logs(stream=True, follow=True, tail=200, timestamps=True)
```

Gives each newly-attached follower 200 lines of history on startup. Combined with `LOG_DEQUE.maxlen = 2000` (see change 4), this gives the UI enough context to show quieter services the moment the monitor starts.

### 3. Verify / enable uvicorn access logs

**Files**: `backend/Dockerfile` (and any compose `command:` override for fastapi).

Read the current uvicorn invocation:
- If it includes `--no-access-log` or `--log-level=warning`/`error`, remove those flags (or set `--log-level=info`, uvicorn's default).
- If uvicorn is already running with default logging, no change. Document the confirmation in the PR description.

### 4. Bump log buffer sizes

**Files**: `backend/monitor/bg.py`, `backend/monitor/main.py`

- `LOG_DEQUE: Deque[dict[str, Any]] = deque(maxlen=500)` → `deque(maxlen=2000)`
- `("logs", partial(logs_coll.collect, 100), ...)` → `partial(logs_coll.collect, 400)`

Memory overhead is ~1 MB at steady state (500 bytes/line average × 2000 lines). UI still slices the last 100 for display; the larger backend window gives per-service filters enough room to find non-nginx entries.

### 5. Add `astral_monitor` chip + delete Metrics Explorer pills

**File**: `backend/monitor/static/index.html`

**5a — add chip** (around line 943, after the `certbot` chip):

```html
<span class="svc-chip" data-svc="astral_monitor">
  <span class="dot" style="background:var(--gold);width:6px;height:6px;"></span>monitor
</span>
```

Reuses the existing click handler at line 1980; no JS changes. The chip label is `monitor` for brevity, but `data-svc="astral_monitor"` matches the compose service name exactly so the filter at line 1751 works without a mapping (unlike the `arq_worker → arq` normalization already present).

Colour: use `var(--muted)` (`#6B6B7A`) for the chip dot. Every other service colour is already taken (lavender = postgres log chips, teal = arq, blue = nginx, gold = fastapi, red = redis, warning orange = certbot). `--muted` is palette-safe and not used as a service colour anywhere else.

**5b — delete the Metrics Explorer pill bar**:

Remove:
- Lines 691–709 — the `<div>` containing `mx-chip` pills for `metric / agg / group by / status` and the `PromQL` badge.
- Lines 316–325 — the `.mx-chip` CSS rules (orphaned once the markup is removed).

No JS removal needed — the chips had no handlers and the renderers don't reference them.

**Visual consequence**: the Requests card header collapses to just the "Requests/sec · p95 latency" section label and the big numbers. The top border of the card becomes flush. Reviewer should confirm this looks right during PR review; if it looks too bare, a simple section label can replace the bar.

## Testing / verification

After deploy, verify on the live instance:

1. **`docker compose exec nginx ls -la /var/log/nginx/access.log`** — should show a regular file (no `->` symlink marker), non-zero size after any HTTPS request.
2. **`curl -u astral:<pw> https://astral-reader.duckdns.org/metrics?range=6h | jq '.requests'`** — within 60 s of deploy, `status_codes.2xx` should be non-zero and `series_rps` should be a non-empty array.
3. **Dashboard Requests section** — rps/p95/total show live numbers; clicking `1h` vs `30d` produces visibly different values (at minimum, different `series_rps` point counts).
4. **Dashboard Logs view** — clicking `fastapi` and `monitor` chips each shows lines within a few seconds of a dashboard refresh. The `all` view should contain a mix of services, not >80% nginx.
5. **Metrics Explorer bar** — the pill row above the chart is gone; no dropdown carets in the Requests header.

## Risks & mitigations

- **nginx `command:` override syntax error** → container crash-loops. Mitigation: exercise the override locally with `docker compose up nginx` before pushing.
- **`tail=200` on six containers = 1200 lines backfilled on every monitor restart** → deque is 2000 so nothing overflows. OK.
- **uvicorn flag change affects prod API performance** → unlikely; enabling access logs has negligible overhead at this scale. If it shows up in monitoring, revert is one flag.
- **Removing the Metrics Explorer bar visually changes the Requests card** → reviewer confirms during PR review. If it looks incomplete, add a simple section label in the same PR.
- **One-time volume cleanup on OCI** → Option B (exec + rm + restart) is safer than dropping the volume; the deploy runbook will call it out explicitly.

## Rollout

Single PR against `development`. The existing CD workflow change-detector will set:

- `DEPLOY_APP=true` (if the fastapi Dockerfile or compose command changes in change 3)
- `DEPLOY_MONITOR=true` (changes 2, 4, 5)
- `DEPLOY_NGINX=true` (change 1)

Post-deploy runbook (SSH to OCI):

```bash
# One-time cleanup of stale symlinks in the named volume
docker compose exec nginx rm -f /var/log/nginx/access.log /var/log/nginx/error.log
docker compose restart nginx

# Verify
docker compose exec nginx ls -la /var/log/nginx/access.log    # regular file
curl -u astral:<pw> https://astral-reader.duckdns.org/healthz  # 200
# wait 60s, then check the dashboard
```

## Out-of-scope follow-ups

File these as separate Linear tickets if desired:
- Real Metrics Explorer (metric switcher, agg window, endpoint/status/method group-by) — proper feature work.
- Per-service round-robin log sampling (guarantees every service gets equal UI airtime regardless of traffic skew).
- Switch nginx JSON logging to structured records, drop the regex parser.
- Prometheus / Grafana replacement for the whole dashboard if this stack ever outgrows the DIY approach.
