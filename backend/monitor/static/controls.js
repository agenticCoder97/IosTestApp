/* astral-monitor — dashboard control plane (AST-70..77).
 *
 * Augments the existing dashboard bundle with live interaction:
 *   - Kill switches (AST-70)
 *   - Service restart buttons (AST-71)
 *   - ARQ retry buttons (AST-72)
 *   - SSE live log stream with filter toolbar (AST-73)
 *   - On-demand backup trigger (AST-74)
 *   - SQL console (AST-75)
 *   - Endpoint latency drill-down (AST-76)
 *   - Deploy log (AST-77, renders from /metrics response)
 *   - Audit tail
 *
 * Auth: every mutating call sends X-Monitor-Auth. Token lives in
 * localStorage and is prompted for on first write.
 */
(function () {
  'use strict';

  const TOKEN_KEY = 'monitor_control_token';
  const SQL_HISTORY_KEY = 'monitor_sql_history';
  const SQL_HISTORY_MAX = 10;

  function getToken() { return localStorage.getItem(TOKEN_KEY) || ''; }
  function setToken(t) { localStorage.setItem(TOKEN_KEY, t); }
  function clearToken() { localStorage.removeItem(TOKEN_KEY); }

  function promptForToken() {
    return new Promise((resolve) => {
      const modal = document.getElementById('token-modal');
      const input = document.getElementById('token-input');
      const save = document.getElementById('token-save');
      const cancel = document.getElementById('token-cancel');
      modal.style.display = 'flex';
      input.value = '';
      input.focus();
      const done = (value) => {
        modal.style.display = 'none';
        save.onclick = null;
        cancel.onclick = null;
        input.onkeydown = null;
        resolve(value);
      };
      save.onclick = () => { const v = input.value.trim(); if (v) { setToken(v); done(v); } };
      cancel.onclick = () => done(null);
      input.onkeydown = (e) => { if (e.key === 'Enter') save.click(); if (e.key === 'Escape') cancel.click(); };
    });
  }

  async function authFetch(url, opts) {
    opts = opts || {};
    let token = getToken();
    if (!token) {
      token = await promptForToken();
      if (!token) throw new Error('control token required');
    }
    opts.headers = Object.assign({}, opts.headers, { 'X-Monitor-Auth': token });
    const resp = await fetch(url, opts);
    if (resp.status === 401) {
      clearToken();
      throw new Error('invalid control token — cleared, try again');
    }
    return resp;
  }

  function toast(msg, cls) {
    const t = document.getElementById('toast');
    const m = document.getElementById('toast-msg');
    if (!t || !m) return;
    m.textContent = msg;
    t.classList.add('show');
    t.style.color = (cls === 'err' ? 'var(--error)' : (cls === 'ok' ? 'var(--success)' : ''));
    setTimeout(() => t.classList.remove('show'), 2400);
  }

  function esc(s) { return String(s).replace(/[&<>"']/g, (c) => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c])); }

  function relTime(iso) {
    try {
      const t = new Date(iso).getTime();
      const s = Math.max(0, Math.round((Date.now() - t) / 1000));
      if (s < 60) return s + 's ago';
      if (s < 3600) return Math.round(s / 60) + 'm ago';
      if (s < 86400) return Math.round(s / 3600) + 'h ago';
      return Math.round(s / 86400) + 'd ago';
    } catch (_e) { return '—'; }
  }

  // ── AST-70: Kill switches ──────────────────────────────────
  async function loadFlags() {
    const grid = document.getElementById('flags-grid');
    if (!grid) return;
    try {
      const resp = await authFetch('control/flags');
      if (!resp.ok) throw new Error('flags fetch failed: ' + resp.status);
      const data = await resp.json();
      grid.innerHTML = '';
      for (const f of data.flags) {
        const card = document.createElement('div');
        card.className = 'flag-card';
        card.innerHTML =
          '<div class="flex items-start justify-between gap-3">' +
            '<div><span class="flag-key">' + esc(f.key) + '</span>' +
            '<span class="flag-source">' + esc(f.source) + '</span></div>' +
            '<label class="toggle"><input type="checkbox" ' + (f.value ? 'checked' : '') +
            ' data-flag="' + esc(f.key) + '"><span class="slider"></span></label>' +
          '</div>' +
          '<div class="flag-desc">' + esc(f.description || '') + '</div>' +
          '<div class="flag-changed">' + (f.changed_at ? 'changed ' + esc(f.changed_at) + ' by ' + esc(f.changed_by || '?') : '—') + '</div>';
        grid.appendChild(card);
      }
      grid.querySelectorAll('input[data-flag]').forEach((el) => {
        el.addEventListener('change', async (e) => {
          const key = e.target.getAttribute('data-flag');
          const value = e.target.checked;
          if (key === 'MANGADEX_DISABLED' && value) {
            if (!confirm('Disable MangaDex? New scrapes will 503; in-flight continue.')) {
              e.target.checked = !value;
              return;
            }
          }
          try {
            const resp = await authFetch('control/flags', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ key, value }),
            });
            if (!resp.ok) throw new Error('flag set failed: ' + resp.status);
            toast(key + ' = ' + value, 'ok');
            loadFlags();
            loadAudit();
          } catch (err) {
            toast(err.message, 'err');
            e.target.checked = !value;
          }
        });
      });
    } catch (err) {
      grid.innerHTML = '<div class="text-muted text-sm mono">' + esc(err.message) + '</div>';
    }
  }

  // ── AST-71: Service restart ────────────────────────────────
  function decorateServiceCards() {
    const grid = document.getElementById('svc-grid');
    if (!grid) return;
    grid.querySelectorAll('[data-service-card]').forEach((card) => {
      if (card.querySelector('.svc-ctrl-btn[data-restart]')) return;
      const svc = card.getAttribute('data-service-card');
      if (!svc || svc === 'certbot') return;
      const btn = document.createElement('button');
      btn.className = 'svc-ctrl-btn';
      btn.setAttribute('data-restart', svc);
      btn.innerHTML = '↻ restart';
      btn.title = 'restart ' + svc;
      const header = card.querySelector('.svc-card-header') || card;
      header.appendChild(btn);
      btn.addEventListener('click', () => restartService(svc, btn));
    });
  }

  async function restartService(svc, btn) {
    if (svc === 'postgres' || svc === 'redis') {
      if (!confirm('Restart ' + svc + '? Briefly disconnects all clients.')) return;
    }
    const original = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = '⋯ restarting';
    try {
      const resp = await authFetch('control/restart/' + encodeURIComponent(svc), { method: 'POST' });
      if (!resp.ok) throw new Error('restart failed: ' + resp.status);
      toast(svc + ' restarted', 'ok');
      loadAudit();
    } catch (err) {
      toast(err.message, 'err');
    } finally {
      setTimeout(() => { btn.disabled = false; btn.innerHTML = original; }, 3000);
    }
  }

  // ── AST-72: ARQ retry ──────────────────────────────────────
  function decorateFailedJobs() {
    const tbody = document.getElementById('failed');
    if (!tbody) return;
    tbody.querySelectorAll('tr[data-job-id]').forEach((tr) => {
      if (tr.querySelector('button[data-retry]')) return;
      const jobId = tr.getAttribute('data-job-id');
      if (!jobId) return;
      const btn = document.createElement('button');
      btn.className = 'svc-ctrl-btn';
      btn.setAttribute('data-retry', jobId);
      btn.innerHTML = '↩ retry';
      btn.addEventListener('click', () => retryJob(jobId, btn));
      tr.lastElementChild.appendChild(btn);
    });
  }

  async function retryJob(jobId, btn) {
    btn.disabled = true;
    btn.innerHTML = '… queued';
    try {
      const resp = await authFetch('control/retry-job/' + encodeURIComponent(jobId), { method: 'POST' });
      if (!resp.ok) throw new Error('retry failed: ' + resp.status);
      const data = await resp.json();
      toast('re-queued as ' + data.new_job_id, 'ok');
      loadAudit();
    } catch (err) {
      toast(err.message, 'err');
      btn.disabled = false;
      btn.innerHTML = '↩ retry';
    }
  }

  // ── AST-73: SSE log stream ─────────────────────────────────
  let logES = null;
  let logLive = false;

  function ensureLogToolbar() {
    const header = document.querySelector('#sec-logs');
    const card = header && header.nextElementSibling;
    if (!card) return;
    if (card.querySelector('#log-controls')) return;
    const container = document.createElement('div');
    container.id = 'log-controls';
    container.innerHTML =
      '<select id="log-level" class="ibtn" title="minimum level">' +
        '<option value="debug">debug+</option>' +
        '<option value="info" selected>info+</option>' +
        '<option value="warn">warn+</option>' +
        '<option value="error">error</option>' +
      '</select>' +
      '<button id="log-live" class="ibtn" title="toggle live tail">● Live</button>';
    const target = card.querySelector('.p-3, .p-4') || card.firstElementChild;
    target.appendChild(container);
    document.getElementById('log-live').addEventListener('click', () => { logLive ? stopLive() : startLive(); });
    document.getElementById('log-level').addEventListener('change', () => { if (logLive) { stopLive(); startLive(); } });
  }

  function startLive() {
    const stream = document.getElementById('log-stream');
    if (!stream) return;
    const level = (document.getElementById('log-level') || {}).value || 'info';
    const svc = (window.STATE && window.STATE.svcFilter && window.STATE.svcFilter !== 'all')
      ? window.STATE.svcFilter : '';
    const q = (document.getElementById('log-filter') || {}).value || '';
    let url = '/metrics/logs/stream?level=' + encodeURIComponent(level);
    if (svc) url += '&service=' + encodeURIComponent(svc);
    if (q) url += '&q=' + encodeURIComponent(q);
    logES = new EventSource(url);
    logES.onmessage = (ev) => {
      try { appendLogLine(stream, JSON.parse(ev.data)); } catch (_e) { /* ignore */ }
    };
    logES.onerror = () => { stopLive(); toast('log stream disconnected', 'err'); };
    logLive = true;
    const btn = document.getElementById('log-live');
    btn.classList.add('on');
    btn.textContent = '■ Stop';
    const dot = document.querySelector('#sec-logs .live-dot');
    if (dot) dot.classList.add('on');
  }

  function stopLive() {
    if (logES) { logES.close(); logES = null; }
    logLive = false;
    const btn = document.getElementById('log-live');
    if (btn) { btn.classList.remove('on'); btn.textContent = '● Live'; }
    const dot = document.querySelector('#sec-logs .live-dot');
    if (dot) dot.classList.remove('on');
  }

  function appendLogLine(stream, entry) {
    const div = document.createElement('div');
    div.className = 'log-line';
    const ts = (entry.ts || '').replace('T', ' ').replace('Z', '');
    const lvl = entry.lvl || 'info';
    const color = lvl === 'error' ? 'var(--error)' : lvl === 'warn' ? 'var(--warning)' : 'var(--body)';
    div.innerHTML = '<span class="text-muted mono">' + esc(ts) + '</span> ' +
      '<span class="badge badge-muted mono">' + esc(entry.svc || '') + '</span> ' +
      '<span style="color:' + color + '">' + esc(entry.msg || '') + '</span>';
    stream.appendChild(div);
    while (stream.children.length > 1000) stream.removeChild(stream.firstChild);
    const nearBottom = stream.scrollHeight - stream.scrollTop - stream.clientHeight < 40;
    if (nearBottom) stream.scrollTop = stream.scrollHeight;
  }

  // ── AST-74: On-demand backup ───────────────────────────────
  function ensureBackupButton() {
    const header = document.getElementById('sec-backups');
    if (!header || header.querySelector('#backup-run')) return;
    const run = document.createElement('button');
    run.id = 'backup-run';
    run.className = 'ibtn';
    run.innerHTML = '▶ Run backup now';
    run.style.marginLeft = '8px';
    run.addEventListener('click', runBackup);
    header.appendChild(run);

    const dl = document.createElement('button');
    dl.id = 'backup-dl';
    dl.className = 'ibtn';
    dl.innerHTML = '⬇ latest dump';
    dl.style.marginLeft = '8px';
    dl.addEventListener('click', async () => {
      try {
        const resp = await authFetch('control/backup/download/latest');
        if (!resp.ok) throw new Error('download failed: ' + resp.status);
        const blob = await resp.blob();
        const cd = resp.headers.get('content-disposition') || '';
        const match = /filename="?([^";]+)"?/.exec(cd);
        const fname = match ? match[1] : 'astral-backup.dump';
        const a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = fname;
        a.click();
        URL.revokeObjectURL(a.href);
      } catch (err) { toast(err.message, 'err'); }
    });
    header.appendChild(dl);
  }

  async function runBackup() {
    const btn = document.getElementById('backup-run');
    btn.disabled = true;
    btn.innerHTML = '… running';
    try {
      const start = await authFetch('control/backup', { method: 'POST' });
      if (!start.ok) {
        if (start.status === 409) throw new Error('backup already running');
        throw new Error('backup start failed: ' + start.status);
      }
      const info = await start.json();
      const t0 = Date.now();
      const poll = async () => {
        const st = await authFetch('control/backup/' + info.job_id);
        if (!st.ok) return;
        const s = await st.json();
        const secs = Math.round((Date.now() - t0) / 1000);
        btn.innerHTML = '… ' + s.status + ' (' + secs + 's)';
        if (s.status === 'running') { setTimeout(poll, 2000); return; }
        btn.disabled = false;
        if (s.status === 'done') {
          btn.innerHTML = '✓ ' + (s.size_bytes / 1e6).toFixed(1) + 'MB in ' + s.duration_s + 's';
          toast('backup complete', 'ok');
        } else {
          btn.innerHTML = '▶ Run backup now';
          toast('backup failed: ' + (s.error || 'unknown'), 'err');
        }
        loadAudit();
      };
      setTimeout(poll, 1500);
    } catch (err) {
      toast(err.message, 'err');
      btn.disabled = false;
      btn.innerHTML = '▶ Run backup now';
    }
  }

  // ── AST-75: SQL console ────────────────────────────────────
  function initSQL() {
    const input = document.getElementById('sql-input');
    const run = document.getElementById('sql-run');
    const hist = document.getElementById('sql-history');
    if (!input || !run) return;
    run.addEventListener('click', runSQL);
    input.addEventListener('keydown', (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') { e.preventDefault(); runSQL(); }
    });
    hist.addEventListener('change', () => { if (hist.value) input.value = hist.value; });
    refreshHistoryDropdown();
  }

  function pushHistory(sql) {
    let list = [];
    try { list = JSON.parse(localStorage.getItem(SQL_HISTORY_KEY) || '[]'); } catch (_) { list = []; }
    list = list.filter((x) => x !== sql);
    list.unshift(sql);
    list = list.slice(0, SQL_HISTORY_MAX);
    localStorage.setItem(SQL_HISTORY_KEY, JSON.stringify(list));
    refreshHistoryDropdown();
  }

  function refreshHistoryDropdown() {
    const hist = document.getElementById('sql-history');
    if (!hist) return;
    let list = [];
    try { list = JSON.parse(localStorage.getItem(SQL_HISTORY_KEY) || '[]'); } catch (_) { list = []; }
    hist.innerHTML = '<option value="">History…</option>';
    for (const s of list) {
      const opt = document.createElement('option');
      opt.value = s;
      opt.textContent = s.length > 80 ? s.slice(0, 80) + '…' : s;
      hist.appendChild(opt);
    }
  }

  async function runSQL() {
    const input = document.getElementById('sql-input');
    const status = document.getElementById('sql-status');
    const wrapper = document.getElementById('sql-results');
    const body = document.getElementById('sql-results-body');
    const meta = document.getElementById('sql-results-meta');
    const sql = (input.value || '').trim();
    if (!sql) return;
    status.textContent = 'running…';
    if (meta) meta.textContent = '';
    if (body) body.replaceChildren();
    if (wrapper) wrapper.classList.remove('hidden');
    try {
      const resp = await authFetch('control/query', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sql }),
      });
      const data = await resp.json();
      if (!resp.ok) throw new Error(data.detail || ('query failed: ' + resp.status));
      status.textContent = '';
      if (meta) {
        const suffix = data.truncated ? ' · TRUNCATED' : '';
        meta.textContent = data.row_count + ' rows · ' + data.duration_ms + 'ms' + suffix;
      }
      renderSQLTable(body, data);
      pushHistory(sql);
    } catch (err) {
      status.textContent = '';
      if (meta) meta.textContent = 'error';
      if (body) {
        body.replaceChildren();
        const div = document.createElement('div');
        div.className = 'sql-error';
        div.textContent = err.message;
        body.appendChild(div);
      }
    }
  }

  function renderSQLTable(container, data) {
    container.replaceChildren();
    if (!data.columns || !data.columns.length) {
      const empty = document.createElement('div');
      empty.className = 'text-muted text-sm mono';
      empty.textContent = 'no rows';
      container.appendChild(empty);
      return;
    }
    const t = document.createElement('table');
    t.className = 'sql-table';
    const thead = document.createElement('thead');
    const trh = document.createElement('tr');
    for (const c of data.columns) { const th = document.createElement('th'); th.textContent = c; trh.appendChild(th); }
    thead.appendChild(trh); t.appendChild(thead);
    const tbody = document.createElement('tbody');
    for (const row of data.rows) {
      const tr = document.createElement('tr');
      for (const cell of row) {
        const td = document.createElement('td');
        td.textContent = cell === null ? 'NULL' : String(cell);
        if (cell === null) td.style.color = 'var(--muted)';
        tr.appendChild(td);
      }
      tbody.appendChild(tr);
    }
    t.appendChild(tbody);
    container.appendChild(t);
  }

  // ── AST-76: Endpoint drill-down ────────────────────────────
  function decorateSlowest() {
    const tbody = document.getElementById('slowest');
    if (!tbody) return;
    tbody.querySelectorAll('tr').forEach((tr) => {
      if (tr.hasAttribute('data-ep-wired')) return;
      tr.setAttribute('data-ep-wired', '1');
      tr.style.cursor = 'pointer';
      tr.addEventListener('click', () => {
        const cells = tr.querySelectorAll('td');
        if (cells.length < 2) return;
        const method = (cells[0].textContent || 'GET').trim().toUpperCase();
        const path = (cells[1].textContent || '').trim();
        openEndpointModal(method, path);
      });
    });
  }

  async function openEndpointModal(method, path) {
    const modal = document.getElementById('endpoint-modal');
    const title = document.getElementById('ep-title');
    const range = (window.STATE && window.STATE.range) || '6h';
    title.textContent = method + ' ' + path + ' · ' + range;
    document.getElementById('ep-total').textContent = '…';
    document.getElementById('ep-err').textContent = '…';
    document.getElementById('ep-peak').textContent = '…';
    document.getElementById('ep-chart').innerHTML = '';
    document.getElementById('ep-status-bars').innerHTML = '';
    modal.style.display = 'flex';
    try {
      const url = '/metrics/endpoint?method=' + encodeURIComponent(method) +
        '&path=' + encodeURIComponent(path) + '&range=' + encodeURIComponent(range);
      const resp = await fetch(url, { credentials: 'include' });
      if (!resp.ok) throw new Error('no data (' + resp.status + ')');
      const data = await resp.json();
      document.getElementById('ep-total').textContent = data.total_requests.toLocaleString();
      document.getElementById('ep-err').textContent = data.error_rate_pct.toFixed(2) + '%';
      document.getElementById('ep-err').style.color = data.error_rate_pct > 5 ? 'var(--error)' : 'var(--body)';
      document.getElementById('ep-peak').textContent = data.peak_p99_ms + ' ms';
      renderEndpointChart(data.buckets);
      renderEndpointStatusBars(data.buckets);
    } catch (err) {
      document.getElementById('ep-total').textContent = err.message;
    }
  }

  function renderEndpointChart(buckets) {
    const svg = document.getElementById('ep-chart');
    if (!buckets.length) {
      svg.innerHTML = '<text x="50%" y="50%" fill="var(--muted)" font-size="12" text-anchor="middle" font-family="monospace">no data</text>';
      return;
    }
    const W = 800, H = 220, pad = 30;
    const maxL = Math.max.apply(null, buckets.map((b) => b.p99_ms).concat([1]));
    const xAt = (i) => pad + (W - 2 * pad) * (i / Math.max(1, buckets.length - 1));
    const yAt = (v) => H - pad - (H - 2 * pad) * (v / maxL);
    const line = (sel) => buckets.map((b, i) => (i === 0 ? 'M' : 'L') + xAt(i) + ',' + yAt(b[sel])).join(' ');
    svg.innerHTML =
      '<path d="' + line('p99_ms') + '" stroke="#EF5350" stroke-width="1.5" fill="none"/>' +
      '<path d="' + line('p95_ms') + '" stroke="#FFA726" stroke-width="1.5" fill="none"/>' +
      '<path d="' + line('p50_ms') + '" stroke="#C9A84C" stroke-width="1.5" fill="none"/>' +
      '<g font-family="monospace" font-size="10" fill="var(--muted)">' +
      '<text x="' + pad + '" y="14">p99 ' + maxL + 'ms</text>' +
      '<text x="' + (W - 160) + '" y="14">— p50 — p95 — p99</text></g>';
  }

  function renderEndpointStatusBars(buckets) {
    const container = document.getElementById('ep-status-bars');
    const totals = { '2xx':0, '3xx':0, '4xx':0, '5xx':0 };
    for (const b of buckets) {
      totals['2xx'] += b.status_2xx || 0;
      totals['3xx'] += b.status_3xx || 0;
      totals['4xx'] += b.status_4xx || 0;
      totals['5xx'] += b.status_5xx || 0;
    }
    const sum = totals['2xx'] + totals['3xx'] + totals['4xx'] + totals['5xx'] || 1;
    const pct = (k) => ((totals[k] / sum) * 100).toFixed(1);
    container.innerHTML =
      '<div class="flex gap-2 text-[11px] mono">' +
        '<span class="badge badge-ok">2xx ' + totals['2xx'] + ' (' + pct('2xx') + '%)</span>' +
        '<span class="badge badge-muted">3xx ' + totals['3xx'] + '</span>' +
        '<span class="badge badge-warn">4xx ' + totals['4xx'] + '</span>' +
        '<span class="badge badge-crit">5xx ' + totals['5xx'] + '</span>' +
      '</div>';
  }

  function closeEndpointModal() {
    const m = document.getElementById('endpoint-modal');
    if (m) m.style.display = 'none';
  }

  // ── AST-77: Deploys block ──────────────────────────────────
  function renderDeploys() {
    const tbody = document.getElementById('deploys-rows');
    if (!tbody) return;
    const deploys = (window.STATE && window.STATE.data && window.STATE.data.deploys) || { recent: [] };
    if (!deploys.recent || !deploys.recent.length) {
      tbody.innerHTML = '<tr><td colspan="5" class="text-muted text-sm mono">No deploys recorded yet.</td></tr>';
      return;
    }
    tbody.innerHTML = '';
    for (const d of deploys.recent) {
      const imgs = (d.images_pulled || [])
        .map((x) => '<span class="badge badge-muted mono">' + esc(x) + '</span>').join(' ');
      const outcome = d.healthy
        ? '<span class="badge badge-ok"><span class="dot ok"></span>healthy</span>'
        : '<span class="badge badge-crit"><span class="dot crit"></span>failed</span>';
      const tr = document.createElement('tr');
      tr.innerHTML =
        '<td class="mono">' + esc(relTime(d.ts)) + '</td>' +
        '<td class="mono">' + (d.commit_sha ? esc(String(d.commit_sha).slice(0, 8)) : '—') + '</td>' +
        '<td>' + (imgs || '<span class="text-muted mono">—</span>') + '</td>' +
        '<td class="mono">' + (d.duration_s || 0) + 's</td>' +
        '<td>' + outcome + '</td>';
      tbody.appendChild(tr);
    }
  }

  // ── Audit log tail ─────────────────────────────────────────
  async function loadAudit() {
    const tbody = document.getElementById('audit-rows');
    if (!tbody) return;
    try {
      const resp = await authFetch('control/audit?limit=20');
      if (!resp.ok) throw new Error('audit fetch failed: ' + resp.status);
      const data = await resp.json();
      if (!data.entries.length) {
        tbody.innerHTML = '<tr><td colspan="5" class="text-muted text-sm mono">No actions recorded.</td></tr>';
        return;
      }
      tbody.innerHTML = '';
      for (const e of data.entries.reverse()) {
        const outcome = e.ok
          ? '<span class="badge badge-ok">ok</span>'
          : '<span class="badge badge-crit">fail</span>';
        const detail = typeof e.detail === 'object' ? JSON.stringify(e.detail) : (e.detail || '');
        const tr = document.createElement('tr');
        tr.innerHTML =
          '<td class="mono">' + esc(relTime(e.ts)) + '</td>' +
          '<td class="mono">' + esc(e.action) + '</td>' +
          '<td>' + outcome + '</td>' +
          '<td class="mono text-xs">' + esc(detail) + '</td>' +
          '<td class="mono text-xs text-muted">' + esc(e.source_ip || '—') + '</td>';
        tbody.appendChild(tr);
      }
    } catch (err) {
      tbody.innerHTML = '<tr><td colspan="5" class="text-muted text-sm mono">' + esc(err.message) + '</td></tr>';
    }
  }

  // ── Post-render decoration (the base dashboard re-renders on refresh) ──
  function installMutationHooks() {
    const grid = document.getElementById('svc-grid');
    const failed = document.getElementById('failed');
    const slowest = document.getElementById('slowest');
    const targets = [grid, failed, slowest].filter(Boolean);
    const obs = new MutationObserver(() => {
      decorateServiceCards();
      decorateFailedJobs();
      decorateSlowest();
      renderDeploys();
    });
    for (const t of targets) obs.observe(t, { childList: true, subtree: true });
  }

  document.addEventListener('DOMContentLoaded', () => {
    const epClose = document.getElementById('ep-close');
    if (epClose) epClose.addEventListener('click', closeEndpointModal);
    const epModal = document.getElementById('endpoint-modal');
    if (epModal) epModal.addEventListener('click', (e) => { if (e.target.id === 'endpoint-modal') closeEndpointModal(); });
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeEndpointModal(); });
    const logoutLink = document.getElementById('ctrl-logout');
    if (logoutLink) logoutLink.addEventListener('click', (e) => { e.preventDefault(); clearToken(); toast('token cleared'); });

    ensureLogToolbar();
    ensureBackupButton();
    initSQL();
    installMutationHooks();

    const firstRun = () => {
      decorateServiceCards();
      decorateFailedJobs();
      decorateSlowest();
      renderDeploys();
      loadFlags();
      loadAudit();
    };
    setTimeout(firstRun, 500);
    setInterval(renderDeploys, 15000);
    setInterval(loadAudit, 30000);
    setInterval(loadFlags, 30000);
  });
})();

