# AST-92 — Monitor dashboard · docker-exec terminal channel

**Linear:** [AST-92](https://linear.app/nnetraganti/issue/AST-92/monitor-dashboard-docker-exec-terminal-channel-for-service-cards)
**Follow-up to:** [AST-78](https://linear.app/nnetraganti/issue/AST-78/monitor-dashboard-uiux-polish-pass)
**Date:** 2026-04-23

## Purpose

Replace the AST-78 "coming soon" stub on the monitor-dashboard service cards with a real interactive shell. Clicking the terminal icon on a service card flips the card and opens an xterm.js terminal bound to `docker exec` inside the corresponding compose service, brokered by the monitor FastAPI process. Same control-plane auth story as every other `/control/*` endpoint.

## Scope

### In scope

- `POST /control/exec/start` — allocates a docker exec session for an allowlisted service.
- `WS /control/exec/{session_id}` — bidirectional stdio pump + control channel.
- xterm.js wired into the existing flipped-card DOM (`.term-body`).
- Nginx WebSocket proxy config.
- Auth, allowlist, audit, idle watchdog, session cap.

### Out of scope (explicit)

- Multi-user collaboration on one session.
- Persistent scroll-back after the card is flipped back.
- File transfer UX inside the terminal.
- `docker exec` into `astral_monitor` itself (self-exec — deliberately excluded).

## Architecture

```
Browser                     Nginx                   Monitor FastAPI              Docker Engine
───────                     ─────                   ────────────────             ─────────────
xterm.js
  │  POST /monitor/control/exec/start  (X-Monitor-Auth header)
  │ ───────────────────────────────► proxy ──────► require_auth
  │                                                │  allowlist check
  │                                                │  session-cap lock
  │                                                │  docker.APIClient.exec_create(tty=True, stdin=True)
  │                                                │  docker.APIClient.exec_start(socket=True, tty=True)
  │                                                │  register Session(id=uuid4)  ──────►  /containers/{id}/exec
  │ ◄────────────────────── {session_id} ◄────────┤                                            │
  │                                                                                            │
  │  WS /monitor/control/exec/{session_id}        (Sec-WebSocket-Protocol: monitor-token,<tok>)│
  │ ───────────────────────────────► Upgrade ────► websocket.accept(subprotocol=…)             │
  │                                                │  start _pump_stdout task  ────────────►   │
  │                                                │  start _pump_stdin  task  ◄───────────►   │
  │  ◄═══════ binary frames (stdout) ══════════════┤                                           │
  │  ═══════► binary frames (stdin) ═══════════════►                                           │
  │  ═══════► text frame {"type":"resize",…} ══════► exec_resize(h=rows, w=cols) ───────────►  │
  │  ◄═══════ text frame {"type":"closed",…} ◄═════┤                                           │
```

## Protocol (wire format)

One WS per session. Frames multiplexed by WS frame type:

| Direction | Frame | Payload |
|-----------|-------|---------|
| server → client | **binary** | raw stdout/stderr bytes from the docker socket (no framing) |
| client → server | **binary** | raw stdin bytes typed into xterm |
| client → server | **text** | JSON `{"type":"resize","cols":N,"rows":N}` |
| client → server | **text** | JSON `{"type":"ping"}` (app-level keepalive) |
| server → client | **text** | JSON `{"type":"pong"}` |
| server → client | **text** | JSON `{"type":"closed","reason":"idle"\|"server-shutdown"\|"exec-exited"}` before server-side close |

**Why binary for I/O:** avoids UTF-8 decoding across chunk boundaries (docker socket reads can split multibyte runes). xterm.js accepts `Uint8Array` via `term.write()` and handles partial UTF-8 internally.

**Why no JSON wrapper on the hot path:** 1.5 × fewer bytes on the wire, zero per-keystroke JSON parsing, and no escape-sequence ambiguity.

## Auth

- POST uses the existing `require_auth` dependency — `X-Monitor-Auth` header matched against `MONITOR_CONTROL_TOKEN`. Missing env → 503, mismatch → 401. No new mechanism.
- WS uses the `Sec-WebSocket-Protocol` subprotocol header: client offers `['monitor-token', <token>]`; server accepts the `monitor-token` subprotocol only if the second offering matches the env token. On mismatch, server rejects the handshake with close code 1008 ("policy violation").
- `Origin` header must match the allowlist: `https://astral-reader.duckdns.org`, `http://localhost:*`, `http://192.168.0.108:*`. Mismatch → close 1008.
- Nginx `auth_basic` on `/monitor/` is the outer gate and applies to the WS upgrade too.

## Allowlist

Hard-coded set of compose service names (not taken from request body):

```python
EXEC_ALLOWLIST = {"postgres", "redis", "fastapi", "arq_worker", "nginx", "certbot"}
```

Rationale: covers every runtime service the user might want to debug; excludes `astral_monitor` to avoid a shell inside the control plane (foot-gun — could kill own FastAPI, corrupt audit log).

Unknown service → 400 `{"detail": "service not exec-allowed"}`.

## Shell

`["/bin/sh"]` for all six services. No `-l` (avoids profile scripts that spam `postgres` with legal notices), no `-i` (a TTY-attached shell is already interactive via `isatty()`). Every image in the stack ships `/bin/sh` — alpine (ash), debian-slim (dash), nginx-alpine (ash). No fallback logic needed.

## Session lifecycle

### Start

1. Lookup container via `com.docker.compose.project=backend` + `com.docker.compose.service={name}` labels (reuse the pattern in `docker_ops.restart_service`).
2. Acquire the per-service `asyncio.Lock` (prevents double-click races).
3. If a `Session` for this service already exists and is still live → release lock, return `409` `{"detail": "session already open for {service}"}`.
4. `APIClient.exec_create(container_id, cmd=["/bin/sh"], stdin=True, tty=True, stdout=True, stderr=True)` → `{exec_id}`.
5. `APIClient.exec_start(exec_id, socket=True, tty=True, demux=False)` → raw `SocketIO`. Access the underlying socket via `sock._sock` for reads/writes (docker-py wraps urllib3's response socket).
6. Register `Session(session_id=uuid4().hex, service, exec_id, sock, created_at, last_activity)`.
7. Audit: `exec.start` with `{service, session_id}`.
8. Return `{session_id}`.

### WS upgrade

1. Look up `Session` by path param. Missing / wrong / expired → close 1008 "unknown session".
2. Validate subprotocol + Origin (above).
3. `websocket.accept(subprotocol="monitor-token")`.
4. Spawn two asyncio tasks:
   - `_pump_stdout(session, websocket)`: repeatedly `await asyncio.to_thread(sock._sock.recv, 4096)` → `await websocket.send_bytes(chunk)`. Updates `last_activity`.
   - `_pump_stdin(session, websocket)`: `receive()` on the WS → if `bytes` → `await asyncio.to_thread(sock._sock.sendall, data)`; if `text` → JSON parse → resize/ping branches.
5. Watchdog task checks `now - last_activity` every 30 s; if > 600 s → send closed frame, close WS, tear down.

### Close

On any of: client close, WS error, idle timeout, or exec exit (recv returns b''):

1. Send `{"type":"closed","reason":…}` text frame if possible.
2. Write `exit\n` to stdin to nudge the shell.
3. `sock.close()` (docker-py's `SocketIO.close()`).
4. `exec_inspect(exec_id)` once; log `Running: true/false`. Docker has no `exec_kill` — if `Running: true`, orphaned until container restart. Acceptable; audit row records it.
5. Remove `Session` from the registry under the per-service lock.
6. Audit: `exec.close` with `{service, session_id, duration_s, orphaned: bool}`.

## Backpressure

- Stdout pump reads in 4 KB chunks and awaits `websocket.send_bytes()` directly — WS backpressure naturally throttles the read loop. No intermediate queue.
- Stdin pump: WS message delivery is serial; no buffering needed.
- Hard cap on stdout read rate: if cumulative bytes sent in the last 1 s exceed 1 MB, insert a 50 ms sleep before the next read. Protects against `cat /dev/urandom`. Audit trips a `overflow_throttled_count` detail on session close.

## Resize handling

Client sends `{"type":"resize","cols":C,"rows":R}` on FitAddon `fit()` and on `ResizeObserver` ticks. Server validates `1 <= cols <= 500`, `1 <= rows <= 200`, then calls `APIClient.exec_resize(exec_id, height=R, width=C)`. **Argument order is height first, width second** — canonical footgun.

## Nginx config

Add to `http {}` block:

```nginx
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
```

Replace the existing `/monitor/` location body so WS upgrades pass through cleanly. Key additions:

```nginx
location /monitor/ {
    auth_basic "astral";
    auth_basic_user_file /etc/nginx/htpasswd;
    set $monitor_upstream http://astral_monitor:8001;
    rewrite ^/monitor(/.*)$ $1 break;
    proxy_pass $monitor_upstream;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;

    # WebSocket upgrade
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;

    # WS sessions need long-lived, unbuffered transport
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
    proxy_buffering off;
}
```

Non-WS requests (regular JSON API) still work because the upgrade headers only activate when the client sends `Upgrade: websocket`, and `proxy_buffering off` has no material effect on small JSON responses at the single-user scale.

## Frontend

### Library delivery

xterm 5.x via CDN (matches existing Tailwind-from-CDN pattern in `index.html`):

```html
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@xterm/xterm@5/css/xterm.css">
<script src="https://cdn.jsdelivr.net/npm/@xterm/xterm@5/lib/xterm.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/@xterm/addon-fit@0.10/lib/addon-fit.min.js"></script>
```

(No `addon-attach` — we implement binary I/O ourselves to support the control channel.)

### `mountTerminal(wrap, service)` in controls.js

Replaces the `toast('coming soon — AST-92')` call at `index.html:1824`.

```
1. Read token from localStorage.
2. fetch POST /monitor/control/exec/start, body {service, cols: 80, rows: 24}
   with header X-Monitor-Auth.
   409 → show "session already open" banner inside the flipped card.
   Other error → show error banner.
3. Instantiate Terminal + FitAddon; terminal.open(termBody).
4. Open WebSocket to wss?://host/monitor/control/exec/<session_id>
   with subprotocols ['monitor-token', token]. binaryType = 'arraybuffer'.
5. On ws.open → fit (delayed: see below) → send initial resize frame.
6. term.onData(d → ws.send(new TextEncoder().encode(d)))  // binary stdin
7. ws.onmessage handler:
       if event.data instanceof ArrayBuffer → term.write(new Uint8Array(event.data))
       else → JSON.parse(event.data), dispatch 'pong' | 'closed'
8. ResizeObserver on .term-body → fitAddon.fit() → send resize text frame.
9. term-close button → ws.close(1000, 'user-close') → term.dispose().
10. beforeunload → ws.close(1000, 'tab-close').
```

### Card-flip interaction

- `fitAddon.fit()` is deferred until the card's `transitionend` event fires on the `.svc-flip-inner` element. Reading `clientWidth` mid-flip returns zero (CSS 3D transforms + opacity animation).
- After fit, call `terminal.focus()` — otherwise keystrokes fall through to the dashboard.
- The terminal's xterm root div must have `tabindex="0"` so focus works; xterm sets this by default but the surrounding `.term-body` also needs `outline: none` and `cursor: text`.

### Global shortcut guard

Every global keyboard handler in controls.js (`⌘K`, `/`, section-collapse toggles) gets an early return:

```js
if (document.activeElement?.closest('.term-body')) return;
```

### Disconnect & reconnect UX

On `ws.onclose` (non-user-initiated):

- Overlay on the flipped card: "Shell disconnected · [Reconnect]".
- Reconnect button tears down state and calls `mountTerminal(wrap, service)` again (new session_id, fresh shell).
- User-initiated closes (close button, flip-back, tab close) skip the overlay.

### Cache bust

Bump `controls.js?v=4` to `controls.js?v=5` in index.html.

## Audit log additions

Two new actions in `monitor_audit`:

| action | detail |
|--------|--------|
| `exec.start` | `{service, session_id}` |
| `exec.close` | `{service, session_id, duration_s, reason, orphaned: bool}` |

## Backend file layout

```
backend/monitor/control/
  exec.py            ← NEW. Session type, EXEC_ALLOWLIST, start_session,
                       _pump_stdout, _pump_stdin, watchdog, close_session.
  routes.py          ← EDIT. Add POST /control/exec/start + WS /control/exec/{id}.
  docker_ops.py      ← EDIT. Extract _find_compose_container(service) helper
                       (reused by restart + exec).
backend/monitor/tests/
  test_control_exec.py          ← NEW. Auth / allowlist / session cap /
                                  audit / watchdog / resize-arg-order.
  test_control_exec_protocol.py ← NEW. Binary-frame passthrough, control-
                                  frame dispatch, origin allowlist,
                                  subprotocol handshake.
backend/monitor/static/
  index.html         ← EDIT. xterm includes, stub replaced, v=5 cache bust.
  controls.js        ← EDIT. mountTerminal, shortcut guard, disconnect UX.
backend/nginx/
  nginx.conf         ← EDIT. map block + WS upgrade headers on /monitor/.
```

No new Python deps. `docker==7.1.*` is already pinned. FastAPI's built-in WebSocket (ships via `uvicorn[standard]`'s websockets extra) is enough.

## Error handling matrix

| Condition | Response |
|-----------|----------|
| `MONITOR_CONTROL_TOKEN` unset | 503 on POST; 1008 on WS |
| Bad `X-Monitor-Auth` | 401 |
| Missing/wrong subprotocol on WS | 1008 close |
| `Origin` not allowlisted | 1008 close |
| Service not in `EXEC_ALLOWLIST` | 400 |
| Container not found | 500 "no container for service X" |
| docker API error on `exec_create` | 500, audited as `exec.start` ok=false |
| Session already open for service | 409 |
| Unknown `session_id` on WS | 1008 close "unknown session" |
| Malformed JSON in text frame | Ignore frame; log at WARN |
| Resize values out of bounds | Ignore; log at DEBUG |
| Shell exits inside container | Server closes WS with `{reason: "exec-exited"}` |
| Idle > 600s | Server closes WS with `{reason: "idle"}` |

## Testing strategy

### Unit (mocked docker)

- `monkeypatch` `docker.from_env` to a stub returning a fake container + fake `APIClient` with recording `exec_create` / `exec_start` / `exec_resize`.
- Assert argument shapes exactly (argument order for `exec_resize` is a named test case).
- Stub the `SocketIO` with an `io.BytesIO` + fake `_sock` attribute supporting `recv`/`sendall`.

### Protocol

- Spin up FastAPI test client, connect a WS using the Starlette `TestClient.websocket_connect`.
- Send binary frame → verify `sendall` recorded.
- Send text `{"type":"resize",…}` → verify `exec_resize` called with `height`/`width` correctly.
- Missing subprotocol → `TestClient.websocket_connect` raises `WebSocketDisconnect(code=1008)`.

### Manual smoke

After deploy:
1. Open `/monitor/`, click terminal icon on `fastapi` card.
2. Expect a `sh` prompt. Run `ls /app` → see app source.
3. Resize window → terminal reflows.
4. Click close (×). Re-open. Expect a fresh session (confirm audit log).
5. Open two tabs, try to start two sessions on the same service → second returns 409.
6. Leave idle 10 min → server closes WS with overlay banner.

## Risk acknowledgments

- **Orphaned exec processes.** Docker has no `exec_kill`. A user running `sleep infinity` inside the shell and closing the tab leaves the process alive until container restart. Documented; audit records it.
- **Monitor restart mid-session.** Deploy hook restarts the monitor container; all active WS sessions die without graceful close. User sees the disconnect banner and reconnects. No session state is meaningful across restarts.
- **CDN outage.** jsdelivr down → xterm unavailable → terminal icon shows an error banner on click. The rest of the dashboard still works since xterm is loaded async. Acceptable; matches the Tailwind CDN dependency we already accept.
- **Token exposure window.** Same as existing `/control/*` endpoints — the token sits in browser localStorage alongside every other control action. AST-92 does not change the trust model.
