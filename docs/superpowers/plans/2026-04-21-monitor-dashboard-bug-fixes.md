# Monitor dashboard bug fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three user-visible bugs on the OCI monitor dashboard — empty Requests section, missing FastAPI/monitor logs, non-functional time-range filter — plus cleanup of decorative-only "Metrics Explorer" pills.

**Architecture:** Five surgical changes across one compose file, two Python modules, and one HTML file. No new modules, no refactors, no new tests beyond two tiny guards. Ships as a single PR to `development`; existing CD workflow auto-deploys. A post-deploy one-time cleanup on the OCI server removes the stale `/dev/stdout` symlinks left behind in the `nginx_access_logs` named volume.

**Tech Stack:** Python 3.11 (FastAPI, asyncio, docker-py), pytest + pytest-asyncio, nginx:1.25-alpine, vanilla HTML/CSS/JS, Docker Compose.

**Spec:** [docs/superpowers/specs/2026-04-21-monitor-dashboard-bug-fixes-design.md](../specs/2026-04-21-monitor-dashboard-bug-fixes-design.md)

---

## Preflight — already confirmed

**Uvicorn access logs are already enabled.** `backend/Dockerfile:18` is:
```dockerfile
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```
No `--no-access-log` flag, no `--log-level` override → uvicorn emits access logs at the default `INFO` level. The fastapi-logs-missing symptom is NOT caused by suppressed uvicorn output. Change #3 from the spec ("verify / enable uvicorn access logs") is therefore a no-op. Task 1 + `tail=200` + bigger LOG_DEQUE buffer will surface those logs on their own. No Dockerfile change needed.

---

## File Structure

### Modified files

| Path | Responsibility after this PR |
|---|---|
| `backend/docker-compose.yml` | nginx service gets a `command:` override that deletes `/dev/stdout` symlinks before launching nginx |
| `backend/monitor/bg.py` | `LOG_DEQUE.maxlen = 2000` (was 500); `_follow_one` uses `tail=200` (was 0) |
| `backend/monitor/main.py` | Logs collector limit `400` (was `100`) in the `collectors` list |
| `backend/monitor/static/index.html` | Adds `astral_monitor` chip to the log-filter bar; deletes the non-functional "Metrics Explorer" pill row + the orphaned `.mx-chip` CSS rules |

### New / modified test files

| Path | Coverage |
|---|---|
| `backend/monitor/tests/test_bg_log_buffers.py` (new) | Asserts `LOG_DEQUE.maxlen == 2000`; asserts `_follow_one` invokes `container.logs` with `tail=200` |

Existing tests in `backend/monitor/tests/` MUST continue to pass. No rewrites.

### Unchanged but referenced

| Path | Why it matters |
|---|---|
| `backend/monitor/collectors/logs.py` | Already accepts a `limit` kwarg; only the caller in `main.py` changes |
| `backend/nginx/nginx.conf` | Log format + access_log directive already correct; no change |
| `backend/Dockerfile` | Confirmed correct during preflight — no change |

---

## Task 1: Fix nginx `access.log` symlink via compose `command:` override

Makes nginx delete the build-time `/dev/stdout` symlinks before starting so it writes real files to the `nginx_access_logs` named volume that the monitor can read.

**Files:**
- Modify: `backend/docker-compose.yml` (nginx service block, around line 98–108)

- [ ] **Step 1: Read current nginx service block**

Run:
```bash
grep -nA 15 "^  nginx:" backend/docker-compose.yml
```

Expected output: nginx service with `image: nginx:1.25-alpine` but **no** `command:` key yet.

- [ ] **Step 2: Add `command:` override to nginx service**

Edit `backend/docker-compose.yml`. Inside the `nginx:` service block, add the `command:` key immediately after `image:`. Final block should look like:

```yaml
  nginx:
    image: nginx:1.25-alpine
    command: >
      sh -c "rm -f /var/log/nginx/access.log /var/log/nginx/error.log &&
             exec nginx -g 'daemon off;'"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/htpasswd:/etc/nginx/htpasswd:ro
      - letsencrypt:/etc/letsencrypt:ro
      - astral_media:/mnt/astral-media:ro
      - nginx_access_logs:/var/log/nginx
    depends_on:
      - fastapi
      - astral_monitor
    restart: unless-stopped
    networks:
      - astral_net
```

Reasoning:
- The `rm -f` is idempotent — no-op if the symlinks were already replaced with real files.
- `exec nginx` replaces the shell process so signals (`docker stop`, healthchecks) still propagate to nginx.
- The YAML `>` folded-block scalar keeps the inline shell command readable.

- [ ] **Step 3: Validate the compose file syntax**

Run:
```bash
cd backend && docker compose config --quiet && echo OK
```

Expected: `OK` and exit 0. Any YAML indentation error will surface here.

- [ ] **Step 4: Commit**

```bash
git add backend/docker-compose.yml
git commit -m "[backend] override nginx command to replace /dev/stdout symlinks so access.log writes to a real file"
```

---

## Task 2: Bump `LOG_DEQUE` maxlen and `_follow_one` tail parameter

Two one-line changes in `backend/monitor/bg.py`, verified by a small new test file.

**Files:**
- Modify: `backend/monitor/bg.py:15` (LOG_DEQUE maxlen) and `backend/monitor/bg.py:274` (tail=)
- Create: `backend/monitor/tests/test_bg_log_buffers.py`

- [ ] **Step 1: Write the failing test file**

Create `backend/monitor/tests/test_bg_log_buffers.py`:

```python
"""Regression tests for LOG_DEQUE size and _follow_one tail backfill."""
from unittest.mock import MagicMock

import pytest

from monitor import bg


def test_log_deque_maxlen_is_2000():
    """LOG_DEQUE must buffer at least 2000 lines so per-service filters in
    the UI still find non-nginx entries after nginx's per-request bursts."""
    assert bg.LOG_DEQUE.maxlen == 2000


@pytest.mark.asyncio
async def test_follow_one_requests_200_line_backfill(monkeypatch):
    """_follow_one must pass tail=200 to container.logs() so newly-attached
    followers pick up recent history on monitor restart."""
    captured = {}

    def fake_logs(**kwargs):
        captured.update(kwargs)
        return iter([])  # empty stream — loop exits on StopIteration

    container = MagicMock()
    container.logs = fake_logs

    await bg._follow_one(client=MagicMock(), container=container, svc="fastapi")

    assert captured.get("tail") == 200
    assert captured.get("stream") is True
    assert captured.get("follow") is True
    assert captured.get("timestamps") is True
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd backend && python -m pytest monitor/tests/test_bg_log_buffers.py -v
```

Expected: both tests FAIL. First fails with `assert 500 == 2000`; second fails with `assert 0 == 200`.

- [ ] **Step 3: Bump LOG_DEQUE maxlen**

Edit `backend/monitor/bg.py`. Line 15 changes from:

```python
LOG_DEQUE: Deque[dict[str, Any]] = deque(maxlen=500)
```

to:

```python
LOG_DEQUE: Deque[dict[str, Any]] = deque(maxlen=2000)
```

- [ ] **Step 4: Bump `_follow_one` tail parameter**

Edit `backend/monitor/bg.py`. In `_follow_one` (around line 274), the `_iter` inner function changes from:

```python
def _iter():
    return container.logs(stream=True, follow=True, tail=0, timestamps=True)
```

to:

```python
def _iter():
    # tail=200 gives newly-attached followers recent history on monitor
    # restart, so quiet services (fastapi, astral_monitor) are visible in
    # the Logs view immediately rather than only after new traffic arrives.
    return container.logs(stream=True, follow=True, tail=200, timestamps=True)
```

- [ ] **Step 5: Run test to verify it passes**

Run:
```bash
cd backend && python -m pytest monitor/tests/test_bg_log_buffers.py -v
```

Expected: both tests PASS.

- [ ] **Step 6: Run the full monitor test suite to catch regressions**

Run:
```bash
cd backend && python -m pytest monitor/tests/ -v
```

Expected: all tests pass. No existing test asserts `maxlen == 500` or `tail == 0`, so nothing breaks.

- [ ] **Step 7: Commit**

```bash
git add backend/monitor/bg.py backend/monitor/tests/test_bg_log_buffers.py
git commit -m "[backend] bump LOG_DEQUE to 2000 lines and _follow_one tail=200 so quieter services stay visible in Logs view"
```

---

## Task 3: Bump logs collector default limit from 100 → 400 in `main.py`

The backend-side slice of `LOG_DEQUE` returned by `/metrics`. Larger window → UI filter has more entries to find per-service matches in, even when nginx dominates recent traffic.

**Files:**
- Modify: `backend/monitor/main.py:135`

- [ ] **Step 1: Read the current collectors list**

Run:
```bash
grep -nA 12 "collectors = \[" backend/monitor/main.py
```

Expected: line 135 is `("logs",     partial(logs_coll.collect, 100),             lambda: [],              2.0),`.

- [ ] **Step 2: Change the logs collector default from 100 to 400**

Edit `backend/monitor/main.py`. The `("logs", ...)` entry in the `collectors` list changes from:

```python
("logs",     partial(logs_coll.collect, 100),             lambda: [],              2.0),
```

to:

```python
("logs",     partial(logs_coll.collect, 400),             lambda: [],              2.0),
```

No other changes in this file. The `logs_coll.collect` signature already accepts `limit` as its first positional arg (`backend/monitor/collectors/logs.py:10`).

- [ ] **Step 3: Run the metrics endpoint integration test**

Run:
```bash
cd backend && python -m pytest monitor/tests/test_metrics_endpoint.py -v
```

Expected: all existing tests pass. The payload shape doesn't change — only the upper bound on `logs[]` length shifts from 100 to 400.

- [ ] **Step 4: Commit**

```bash
git add backend/monitor/main.py
git commit -m "[backend] raise /metrics logs default limit 100 to 400 so chatty services don't starve the UI filter"
```

---

## Task 4: Add `astral_monitor` chip to the Logs filter bar

The monitor is a backend compose service and its log lines ARE captured by `log_tailer`, but the UI has no chip for it. Without a chip, the lines are only visible when `all` is selected. This change adds a filter chip.

**Files:**
- Modify: `backend/monitor/static/index.html` (around line 944, inside the `.svc-chip` container)

- [ ] **Step 1: Read the current chip row**

Run:
```bash
grep -n 'class="svc-chip' backend/monitor/static/index.html
```

Expected: lines 938–944 show chips for `all, nginx, fastapi, postgres, redis, arq, certbot`.

- [ ] **Step 2: Insert the `astral_monitor` chip after `certbot`**

Edit `backend/monitor/static/index.html`. Immediately after the `certbot` chip line (line 944), insert:

```html
        <span class="svc-chip" data-svc="astral_monitor"><span class="dot" style="background:var(--muted);width:6px;height:6px;"></span>monitor</span>
```

Reasoning for `data-svc="astral_monitor"`:
- `renderLogs()` at line 1750 normalizes `arq_worker → arq` for chip matching, but NOT `astral_monitor`. Keeping `data-svc` identical to the compose service name means no JS change.
- The chip label `monitor` is for user brevity; `data-svc` is what the filter compares against `l.svc` from the backend.
- Colour `var(--muted)` (`#6B6B7A`) is the only palette-safe colour not already used by another service.

- [ ] **Step 3: Verify the chip list is complete**

Run:
```bash
grep -c 'class="svc-chip' backend/monitor/static/index.html
```

Expected: `8` — one `all` + seven services (nginx, fastapi, postgres, redis, arq, certbot, astral_monitor).

- [ ] **Step 4: Commit**

```bash
git add backend/monitor/static/index.html
git commit -m "[backend] add astral_monitor chip to Logs filter bar"
```

---

## Task 5: Delete the non-functional Metrics Explorer pill bar + orphaned CSS

The pill bar above the Requests chart (`metric`, `agg`, `group by`, `status != 2xx`, `PromQL` badge) has zero event handlers and zero data bindings. It was copied from a design handoff and never wired up; the dropdown carets make it look interactive. Remove the markup AND its now-orphaned CSS.

**Files:**
- Modify: `backend/monitor/static/index.html` (delete markup 691–709, delete CSS 316–325)

- [ ] **Step 1: Read and confirm the markup to delete**

Run:
```bash
sed -n '691,709p' backend/monitor/static/index.html
```

Expected output starts with `<!-- Metrics Explorer (GCP) -->` (or the `<div class="flex items-center gap-1.5 ...">` opening tag) and ends with the closing `</div>` before the "Requests/sec · p95 latency" header.

- [ ] **Step 2: Delete the Metrics Explorer markup block**

Edit `backend/monitor/static/index.html`. Delete lines 691–709 — the entire `<div class="flex items-center gap-1.5 flex-wrap mb-4 pb-3 border-b border-border/70">` block and its children. **Do not** delete anything outside this block. The next sibling should be the `<div class="flex items-baseline justify-between flex-wrap gap-2">` opening the rps/p95 header row.

After deletion, the parent `<div class="card p-4 sm:p-5">` at line 689 should contain, as its first child, the rps/p95 header row (previously line 711), followed by the chart SVG.

- [ ] **Step 3: Read and confirm the orphaned CSS**

Run:
```bash
sed -n '316,325p' backend/monitor/static/index.html
```

Expected: lines 316–325 contain `.mx-chip`, `.mx-chip .k`, `.mx-chip .v`, `.mx-chip:hover` rules.

- [ ] **Step 4: Delete the orphaned `.mx-chip` CSS rules**

Edit `backend/monitor/static/index.html`. Delete the entire `.mx-chip` rule block (the ~10 lines that previously lived at 316–325 before the markup deletion shifted line numbers).

Also check for any `.mx-op` rule (it was referenced in the deleted markup). If present, delete it too. Search after editing:

```bash
grep -n "mx-chip\|mx-op\|mx-metric\|mx-agg\|mx-group" backend/monitor/static/index.html
```

Expected: zero matches (or only matches inside strings that are unrelated — verify each).

- [ ] **Step 5: Verify no JS references the deleted IDs**

Run:
```bash
grep -n "getElementById('mx-" backend/monitor/static/index.html
```

Expected: zero matches. (There were no handlers to begin with; this just confirms nothing silently broke.)

- [ ] **Step 6: Verify the HTML parses and the page still serves**

Run:
```bash
cd backend && python -m pytest monitor/tests/test_main.py::test_root_serves_index_html -v
```

Expected: PASS. The test asserts `<title>astral` is present and the status code is 200 — deleting decorative markup can't break either.

- [ ] **Step 7: Commit**

```bash
git add backend/monitor/static/index.html
git commit -m "[backend] remove non-functional Metrics Explorer pill bar and orphaned .mx-chip CSS from monitor dashboard"
```

---

## Task 6: Push and run post-deploy verification on OCI

CD workflow auto-deploys on push to `development`. After the deploy finishes, a one-time cleanup on the OCI server removes the stale `/dev/stdout` symlinks that are still sitting in the `nginx_access_logs` named volume (Task 1's `command:` override kicks in on *new* container starts, but the existing volume contents were populated from the image and persist across restarts).

**Files:** none (runbook-only task).

- [ ] **Step 1: Push the branch and trigger the CD workflow**

```bash
git push origin development
```

Expected: push succeeds; GitHub Actions "Deploy to OCI A1" workflow triggers.

- [ ] **Step 2: Wait for the workflow to complete and confirm success**

Run:
```bash
gh run list --branch development --limit 1
```

Expected: the most recent run shows `completed success`. If it shows `failure`, inspect with `gh run view <id> --log-failed` before proceeding.

- [ ] **Step 3: SSH to OCI and clean up the stale symlinks (Option B — surgical)**

```bash
ssh ubuntu@astral-reader.duckdns.org
cd ~/astral/backend
docker compose exec nginx rm -f /var/log/nginx/access.log /var/log/nginx/error.log
docker compose restart nginx
```

Expected: nginx restarts within ~2 s. No error output.

- [ ] **Step 4: Verify access.log is a real file**

```bash
docker compose exec nginx ls -la /var/log/nginx/access.log
```

Expected: output shows a regular file (`-rw-...`), NOT a symlink (`-> /dev/stdout`).

- [ ] **Step 5: Verify nginx is actually writing to it**

Hit the dashboard once to generate traffic:

```bash
curl -s -u astral:<password> https://astral-reader.duckdns.org/monitor/ > /dev/null
sleep 2
docker compose exec nginx wc -l /var/log/nginx/access.log
```

Expected: `wc -l` returns ≥ 1. If it returns 0, the `command:` override didn't apply — check `docker compose logs nginx --tail 20` for errors and re-run step 3.

- [ ] **Step 6: Verify the monitor picks up the data within 60 s**

```bash
# wait for one nginx_access_sampler tick
sleep 65
curl -s -u astral:<password> https://astral-reader.duckdns.org/metrics?range=6h | jq '.requests | {status_codes, series_rps_len: (.series_rps | length)}'
```

Expected: `status_codes.2xx` is ≥ 1 (the curl hit), `series_rps_len` is ≥ 1.

- [ ] **Step 7: Verify the dashboard end-to-end**

Open `https://astral-reader.duckdns.org/monitor/` in a browser.

Check:
- Requests section shows live rps/p95/total numbers (not zeros)
- Clicking `1h` vs `30d` changes the displayed values
- Logs view has an additional `monitor` chip in the filter bar
- Clicking the `fastapi` chip reveals uvicorn access-log lines
- Clicking the `monitor` chip reveals monitor log lines
- The "Metrics Explorer" pill row above the chart is gone

---

## Self-review checklist

Reviewing the plan against the spec:

**1. Spec coverage** — every spec requirement maps to a task:
- Spec "Fix #1 nginx symlink" → Task 1 ✓
- Spec "Fix #2 tail=200" → Task 2 (step 4) ✓
- Spec "Fix #3 uvicorn verify" → Preflight section (confirmed no-op) ✓
- Spec "Fix #4 LOG_DEQUE + logs limit" → Task 2 (step 3) + Task 3 ✓
- Spec "Fix #5a astral_monitor chip" → Task 4 ✓
- Spec "Fix #5b remove Metrics Explorer" → Task 5 ✓
- Spec "Verification" section → Task 6 ✓
- Spec "Rollout / post-deploy runbook" → Task 6 ✓

**2. Placeholder scan** — searched the plan for "TBD", "TODO", "appropriate", "similar to", vague phrases. None found. Every step has exact paths, full code, and exact commands.

**3. Type / name consistency**:
- `LOG_DEQUE`, `_follow_one`, `logs_coll.collect`, `partial`, `data-svc`, `var(--muted)` — all used consistently across tasks.
- The new test file's `_follow_one` call signature matches the real signature (`client`, `container`, `svc`).
- Compose service name `astral_monitor` matches what the backend label query filters for and what the chip's `data-svc` attribute stores.

**4. TDD discipline**:
- Task 2 follows full red-green-commit TDD with a new test file.
- Tasks 1, 3, 4, 5 are config / HTML / single-line changes; TDD adds no value there. Existing test suite runs on each verify existing invariants.
- Task 6 is a runbook; no code or tests.

---

## Execution

Plan complete and saved to `docs/superpowers/plans/2026-04-21-monitor-dashboard-bug-fixes.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
