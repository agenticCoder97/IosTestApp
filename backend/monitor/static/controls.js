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

  // Seeds localStorage from the server's MONITOR_CONTROL_TOKEN. Nginx Basic
  // Auth on /monitor/ is the real gate — the in-browser token is just a
  // convenience so the user never sees a token-paste modal.
  async function seedTokenFromServer() {
    try {
      const resp = await fetch('control/config');
      if (!resp.ok) return;
      const data = await resp.json();
      if (data && data.token) setToken(data.token);
    } catch (_) { /* offline / CSP / 404 — leave token as-is */ }
  }

  async function authFetch(url, opts) {
    opts = opts || {};
    if (!getToken()) await seedTokenFromServer();
    const token = getToken();
    opts.headers = Object.assign({}, opts.headers, { 'X-Monitor-Auth': token });
    const resp = await fetch(url, opts);
    if (resp.status === 401) {
      clearToken();
      await seedTokenFromServer();
      throw new Error('control token rejected — refreshed, retry');
    }
    if (resp.status === 503) {
      throw new Error('control plane disabled (MONITOR_CONTROL_TOKEN unset)');
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
  // SVG helpers — line-stroke glyphs matching the rest of the dashboard.
  function buildSvg(attrs, children) {
    const NS = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(NS, 'svg');
    for (const k of Object.keys(attrs)) svg.setAttribute(k, attrs[k]);
    for (const child of children) {
      const el = document.createElementNS(NS, child.tag);
      for (const k of Object.keys(child.attrs || {})) el.setAttribute(k, child.attrs[k]);
      svg.appendChild(el);
    }
    return svg;
  }
  function playIcon() {
    return buildSvg(
      { width: '11', height: '11', viewBox: '0 0 24 24', fill: 'currentColor' },
      [{ tag: 'polygon', attrs: { points: '6,4 20,12 6,20' } }]
    );
  }
  function downloadIcon() {
    return buildSvg(
      { width: '11', height: '11', viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor',
        'stroke-width': '2', 'stroke-linecap': 'round', 'stroke-linejoin': 'round' },
      [
        { tag: 'path', attrs: { d: 'M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4' } },
        { tag: 'polyline', attrs: { points: '7 10 12 15 17 10' } },
        { tag: 'line', attrs: { x1: '12', y1: '15', x2: '12', y2: '3' } },
      ]
    );
  }

  function resetBackupBtn(btn) {
    btn.replaceChildren(playIcon());
    btn.title = 'run backup now';
    btn.disabled = false;
  }

  function ensureBackupButton() {
    const host = document.getElementById('bk-actions');
    if (!host || host.querySelector('#backup-run')) return;

    const run = document.createElement('button');
    run.id = 'backup-run';
    run.className = 'ibtn';
    run.style.width = '22px';
    run.style.height = '22px';
    resetBackupBtn(run);
    run.addEventListener('click', runBackup);
    host.appendChild(run);

    const dl = document.createElement('button');
    dl.id = 'backup-dl';
    dl.className = 'ibtn';
    dl.style.width = '22px';
    dl.style.height = '22px';
    dl.title = 'download latest dump';
    dl.replaceChildren(downloadIcon());
    dl.addEventListener('click', async () => {
      try {
        const resp = await authFetch('control/backup/download/latest');
        if (!resp.ok) throw new Error('download failed: ' + resp.status);
        const blob = await resp.blob();
        const cd = resp.headers.get('content-disposition') || '';
        const matched = cd.match(/filename="?([^";]+)"?/);
        const fname = matched ? matched[1] : 'astral-backup.dump';
        const a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = fname;
        a.click();
        URL.revokeObjectURL(a.href);
      } catch (err) { toast(err.message, 'err'); }
    });
    host.appendChild(dl);
  }

  async function runBackup() {
    const btn = document.getElementById('backup-run');
    btn.disabled = true;
    btn.replaceChildren();
    btn.textContent = '…';
    btn.title = 'backup running';
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
        btn.textContent = secs + 's';
        btn.title = 'backup ' + s.status + ' · ' + secs + 's';
        if (s.status === 'running') { setTimeout(poll, 2000); return; }
        if (s.status === 'done') {
          btn.textContent = '✓';
          btn.title = (s.size_bytes / 1e6).toFixed(1) + 'MB in ' + s.duration_s + 's';
          toast('backup complete', 'ok');
          setTimeout(() => resetBackupBtn(btn), 4000);
        } else {
          resetBackupBtn(btn);
          toast('backup failed: ' + (s.error || 'unknown'), 'err');
        }
        loadAudit();
      };
      setTimeout(poll, 1500);
    } catch (err) {
      toast(err.message, 'err');
      resetBackupBtn(btn);
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
      if (tr.classList.contains('ep-drilldown-row')) return;
      tr.setAttribute('data-ep-wired', '1');
      tr.style.cursor = 'pointer';
      tr.addEventListener('click', () => {
        const method = (tr.dataset.method || 'GET').trim().toUpperCase();
        const path   = (tr.dataset.path   || '').trim();
        if (!path) return;
        toggleInlineDrilldown(tr, method, path);
      });
    });
  }

  function toggleInlineDrilldown(tr, method, path) {
    const tbody = tr.parentElement;
    if (!tbody) return;
    const next = tr.nextElementSibling;
    const isOpenHere = next && next.classList.contains('ep-drilldown-row') &&
      next.dataset.epPath === path && next.dataset.epMethod === method;

    tbody.querySelectorAll('tr.ep-drilldown-row').forEach(r => r.remove());
    tbody.querySelectorAll('tr.ep-row-open').forEach(r => r.classList.remove('ep-row-open'));
    if (isOpenHere) return;

    const tpl = document.getElementById('endpoint-drilldown-template');
    if (!tpl) return;
    const headerRow = tr.parentElement.parentElement.querySelector('thead tr');
    const colCount = headerRow ? headerRow.children.length : 6;
    const drillTr = document.createElement('tr');
    drillTr.className = 'ep-drilldown-row';
    drillTr.dataset.epPath = path;
    drillTr.dataset.epMethod = method;
    const td = document.createElement('td');
    td.colSpan = colCount;
    td.appendChild(tpl.content.cloneNode(true));
    drillTr.appendChild(td);
    tr.after(drillTr);
    tr.classList.add('ep-row-open');

    drillTr.addEventListener('click', (e) => e.stopPropagation());
    const seg = drillTr.querySelector('#ep-range-seg');
    if (seg) {
      seg.querySelectorAll('button').forEach((b) => {
        b.addEventListener('click', (e) => {
          e.stopPropagation();
          const r = b.getAttribute('data-r');
          if (!r) return;
          seg.querySelectorAll('button').forEach((x) => x.classList.toggle('active', x === b));
          loadInlineDrilldown(drillTr, method, path, r);
        });
      });
    }
    const copyBtn = drillTr.querySelector('#ep-copy');
    if (copyBtn) {
      copyBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        navigator.clipboard?.writeText(method + ' ' + path).then(() => toast('path copied'));
      });
    }
    loadInlineDrilldown(drillTr, method, path, (window.STATE && window.STATE.range) || '6h');
  }

  async function loadInlineDrilldown(drillTr, method, path, range) {
    setEndpointMethod(drillTr, method);
    const pathEl = drillTr.querySelector('#ep-path');
    if (pathEl) pathEl.textContent = path;
    const lbl = drillTr.querySelector('#ep-range-label');
    if (lbl) lbl.textContent = 'last ' + range;
    const seg = drillTr.querySelector('#ep-range-seg');
    if (seg) seg.querySelectorAll('button').forEach(b => b.classList.toggle('active', b.getAttribute('data-r') === range));
    ['ep-total','ep-rps','ep-err','ep-err-count','ep-p50','ep-p95','ep-peak','ep-apdex','ep-p95-trend'].forEach(id => {
      const el = drillTr.querySelector('#' + id);
      if (el) el.textContent = '…';
    });
    const chart = drillTr.querySelector('#ep-chart');
    if (chart) chart.innerHTML = '';
    try {
      const url = '/metrics/endpoint?method=' + encodeURIComponent(method) +
        '&path=' + encodeURIComponent(path) + '&range=' + encodeURIComponent(range);
      const resp = await fetch(url, { credentials: 'include' });
      if (!resp.ok) throw new Error('no data (' + resp.status + ')');
      const data = await resp.json();
      data.method = data.method || method;
      data.path = data.path || path;
      data.range = data.range || range;
      paintEndpoint(drillTr, data);
    } catch (err) {
      const total = drillTr.querySelector('#ep-total');
      if (total) total.textContent = err.message;
    }
  }

  function setEndpointMethod(root, method) {
    const el = root.querySelector('#ep-method');
    if (!el) return;
    el.textContent = method;
    el.className = 'ep-method ' + method.toLowerCase();
  }

  function fmtNum(n) {
    if (n == null || isNaN(n)) return '—';
    if (n >= 1e6) return (n/1e6).toFixed(1) + 'M';
    if (n >= 1e3) return (n/1e3).toFixed(1) + 'k';
    return n.toLocaleString();
  }

  function rangeSeconds(r) {
    return ({'1h':3600,'6h':6*3600,'24h':24*3600,'7d':7*86400,'30d':30*86400})[r] || 6*3600;
  }

  function paintEndpoint(root, data) {
    setEndpointMethod(root, data.method);
    const pathEl = root.querySelector('#ep-path');
    if (pathEl) pathEl.textContent = data.path;
    const total = data.total_requests || 0;
    const errs = data.error_count != null ? data.error_count : Math.round(total * (data.error_rate_pct || 0) / 100);
    const rps = total / Math.max(1, rangeSeconds(data.range));
    const totalEl = root.querySelector('#ep-total');
    if (totalEl) totalEl.textContent = fmtNum(total);
    const rpsEl = root.querySelector('#ep-rps');
    if (rpsEl) rpsEl.textContent = rps >= 10 ? rps.toFixed(1) : rps.toFixed(2);
    const errEl = root.querySelector('#ep-err');
    if (errEl) {
      errEl.textContent = (data.error_rate_pct || 0).toFixed(2) + '%';
      errEl.style.color = (data.error_rate_pct || 0) > 5 ? 'var(--error)' : ((data.error_rate_pct || 0) > 1 ? 'var(--warning)' : 'var(--body)');
    }
    const errCountEl = root.querySelector('#ep-err-count');
    if (errCountEl) errCountEl.textContent = fmtNum(errs);
    const p50El = root.querySelector('#ep-p50');
    if (p50El) p50El.textContent = data.p50_ms != null ? data.p50_ms : '—';
    const p95El = root.querySelector('#ep-p95');
    if (p95El) p95El.textContent = data.p95_ms != null ? data.p95_ms : '—';
    const peakEl = root.querySelector('#ep-peak');
    if (peakEl) peakEl.textContent = data.peak_p99_ms != null ? data.peak_p99_ms : '—';
    const apdexEl = root.querySelector('#ep-apdex');
    if (apdexEl) apdexEl.textContent = data.apdex != null ? Number(data.apdex).toFixed(2) : '—';
    const trendEl = root.querySelector('#ep-p95-trend');
    if (trendEl) trendEl.textContent = data.p95_delta_pct == null ? '—' : data.p95_delta_pct.toFixed(1) + '%';
    renderEndpointChart(root, data.buckets || []);
    renderEndpointRibbon(root, data.buckets || []);
    renderEndpointDonut(root, data.buckets || []);
    renderEndpointSamples(root, data.samples || []);
    renderEndpointStatusBars(root, data.buckets || []);
  }

  function renderEndpointChart(root, buckets) {
    const svg = root.querySelector('#ep-chart');
    const tip = root.querySelector('#ep-tip');
    if (!buckets.length) {
      svg.innerHTML = '<text x="50%" y="50%" fill="var(--muted)" font-size="12" text-anchor="middle" font-family="monospace">no data</text>';
      if (tip) tip.style.display = 'none';
      return;
    }
    const W = 800, H = 220, pad = 30;
    const maxL = Math.max.apply(null, buckets.map((b) => b.p99_ms).concat([1]));
    const step = (W - 2 * pad) / Math.max(1, buckets.length - 1);
    const xAt = (i) => pad + i * step;
    const yAt = (v) => H - pad - (H - 2 * pad) * (v / maxL);
    const line = (sel) => buckets.map((b, i) => (i === 0 ? 'M' : 'L') + xAt(i).toFixed(1) + ',' + yAt(b[sel]).toFixed(1)).join(' ');

    let xlabels = '';
    const nTicks = Math.min(5, buckets.length);
    for (let i = 0; i < nTicks; i++) {
      const idx = nTicks === 1 ? 0 : Math.round(i * (buckets.length - 1) / (nTicks - 1));
      if (!buckets[idx] || !buckets[idx].ts_ms) continue;
      const hhmm = new Date(buckets[idx].ts_ms).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false });
      xlabels += '<text x="' + xAt(idx).toFixed(1) + '" y="' + (H - 6) + '" text-anchor="middle" fill="var(--muted)" font-size="9" font-family="monospace">' + hhmm + '</text>';
    }

    svg.innerHTML =
      '<path d="' + line('p99_ms') + '" stroke="#EF5350" stroke-width="1.5" fill="none"/>' +
      '<path d="' + line('p95_ms') + '" stroke="#FFA726" stroke-width="1.5" fill="none"/>' +
      '<path d="' + line('p50_ms') + '" stroke="#C9A84C" stroke-width="1.5" fill="none"/>' +
      xlabels +
      '<text x="' + pad + '" y="14" font-family="monospace" font-size="10" fill="var(--muted)">p99 ' + maxL + 'ms</text>' +
      '<line x1="' + (W-155) + '" x2="' + (W-143) + '" y1="10" y2="10" stroke="#C9A84C" stroke-width="1.5"/>' +
      '<text x="' + (W-139) + '" y="14" font-family="monospace" font-size="10" fill="var(--muted)">p50</text>' +
      '<line x1="' + (W-115) + '" x2="' + (W-103) + '" y1="10" y2="10" stroke="#FFA726" stroke-width="1.5"/>' +
      '<text x="' + (W-99) + '" y="14" font-family="monospace" font-size="10" fill="var(--muted)">p95</text>' +
      '<line x1="' + (W-75) + '" x2="' + (W-63) + '" y1="10" y2="10" stroke="#EF5350" stroke-width="1.5"/>' +
      '<text x="' + (W-59) + '" y="14" font-family="monospace" font-size="10" fill="var(--muted)">p99</text>' +
      '<line id="ep-xhair" x1="-1" x2="-1" y1="' + pad + '" y2="' + (H-pad) + '" stroke="var(--muted)" stroke-width="0.8" stroke-dasharray="2 2" opacity="0"/>' +
      '<rect id="ep-hover-zone" x="' + pad + '" y="' + pad + '" width="' + (W-2*pad) + '" height="' + (H-2*pad) + '" fill="transparent" style="cursor:crosshair"/>';

    const zone = svg.querySelector('#ep-hover-zone');
    const xhair = svg.querySelector('#ep-xhair');
    if (zone && tip) {
      const wrap = svg.parentElement;
      zone.addEventListener('mousemove', e => {
        const wRect = wrap.getBoundingClientRect();
        const svgRect = svg.getBoundingClientRect();
        const svgX = (e.clientX - svgRect.left) / svgRect.width * W;
        const rawIdx = (svgX - pad) / step;
        const idx = Math.max(0, Math.min(buckets.length - 1, Math.round(rawIdx)));
        const ptX = xAt(idx);
        xhair.setAttribute('x1', ptX.toFixed(1));
        xhair.setAttribute('x2', ptX.toFixed(1));
        xhair.setAttribute('opacity', '1');
        const b = buckets[idx];
        const timeStr = b.ts_ms ? new Date(b.ts_ms).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false }) : '';
        const parts = [];
        if (timeStr) parts.push('<span style="color:var(--muted)">' + timeStr + '</span>');
        parts.push('<span style="color:#C9A84C">p50 ' + b.p50_ms + 'ms</span>');
        parts.push('<span style="color:#FFA726">p95 ' + b.p95_ms + 'ms</span>');
        parts.push('<span style="color:#EF5350">p99 ' + b.p99_ms + 'ms</span>');
        parts.push('<span style="color:var(--muted)">n=' + b.count + '</span>');
        tip.innerHTML = parts.join('  ');
        tip.style.display = 'block';
        const tx = e.clientX - wRect.left;
        const ty = e.clientY - wRect.top;
        tip.style.left = (tx + 12) + 'px';
        tip.style.top  = Math.max(0, ty - 32) + 'px';
        if (tx + 12 + tip.offsetWidth > wRect.width) tip.style.left = (tx - tip.offsetWidth - 12) + 'px';
      });
      zone.addEventListener('mouseleave', () => {
        xhair.setAttribute('opacity', '0');
        tip.style.display = 'none';
      });
    }
  }

  function renderEndpointRibbon(root, buckets) {
    const ribbon = root.querySelector('#ep-ribbon');
    const axis = root.querySelector('#ep-ribbon-axis');
    const winLbl = root.querySelector('#ep-ribbon-window');
    if (!ribbon) return;
    ribbon.innerHTML = '';
    if (!buckets.length) {
      ribbon.innerHTML = '<div class="text-[11px] mono text-muted">no data</div>';
      if (axis) axis.innerHTML = '';
      if (winLbl) winLbl.textContent = '—';
      return;
    }
    for (const b of buckets) {
      const s2=b.status_2xx||0, s3=b.status_3xx||0, s4=b.status_4xx||0, s5=b.status_5xx||0;
      const total = s2+s3+s4+s5;
      let cls = 'rnone';
      if (total > 0) {
        if (s5 > 0 && s2 > 0) cls = 'rmix-crit';
        else if (s5 > 0) cls = 'r5xx';
        else if (s4 > Math.max(1, total*0.05) && s2 > 0) cls = 'rmix-warn';
        else if (s4 > Math.max(1, total*0.05)) cls = 'r4xx';
        else if (s3 > total*0.5) cls = 'r3xx';
        else cls = 'r2xx';
      }
      const cell = document.createElement('div');
      cell.className = 'seg ' + cls;
      ribbon.appendChild(cell);
    }
    if (winLbl) {
      const first = buckets[0].ts_ms ? new Date(buckets[0].ts_ms) : null;
      const last = buckets[buckets.length-1].ts_ms ? new Date(buckets[buckets.length-1].ts_ms) : null;
      const fmt = d => d ? d.toLocaleTimeString([], {hour:'2-digit',minute:'2-digit',hour12:false}) : '';
      winLbl.textContent = first && last ? fmt(first) + ' -> ' + fmt(last) : '—';
    }
    if (axis) {
      axis.innerHTML = '';
      const ticks = Math.min(5, buckets.length);
      for (let i = 0; i < ticks; i++) {
        const idx = ticks === 1 ? 0 : Math.round(i * (buckets.length - 1) / (ticks - 1));
        const ts = buckets[idx] && buckets[idx].ts_ms;
        const span = document.createElement('span');
        span.textContent = ts ? new Date(ts).toLocaleTimeString([], {hour:'2-digit',minute:'2-digit',hour12:false}) : '';
        axis.appendChild(span);
      }
    }
  }

  function renderEndpointDonut(root, buckets) {
    const svg = root.querySelector('#ep-donut');
    const list = root.querySelector('#ep-dist-list');
    const pctEl = root.querySelector('#ep-donut-pct');
    if (!svg || !list) return;
    const totals = { '2xx':0, '3xx':0, '4xx':0, '5xx':0 };
    for (const b of buckets) {
      totals['2xx'] += b.status_2xx || 0;
      totals['3xx'] += b.status_3xx || 0;
      totals['4xx'] += b.status_4xx || 0;
      totals['5xx'] += b.status_5xx || 0;
    }
    const total = totals['2xx'] + totals['3xx'] + totals['4xx'] + totals['5xx'];
    const colors = { '2xx':'#4CAF50', '3xx':'#6B6B7A', '4xx':'#FFA726', '5xx':'#EF5350' };
    if (total === 0) {
      svg.innerHTML = '<circle cx="60" cy="60" r="44" fill="none" stroke="rgba(107,107,122,.25)" stroke-width="14"/>';
      if (pctEl) pctEl.textContent = '—';
      list.innerHTML = '<div class="text-[11px] mono text-muted">no data</div>';
      return;
    }
    const okPct = (totals['2xx'] / total) * 100;
    if (pctEl) pctEl.textContent = okPct.toFixed(1) + '%';
    const cx=60, cy=60, r=44, sw=14, C=2*Math.PI*r;
    let offset = 0;
    let segs = '<circle cx="'+cx+'" cy="'+cy+'" r="'+r+'" fill="none" stroke="rgba(107,107,122,.18)" stroke-width="'+sw+'"/>';
    for (const k of ['2xx','3xx','4xx','5xx']) {
      const v = totals[k];
      if (!v) continue;
      const len = (v/total) * C;
      segs += '<circle cx="'+cx+'" cy="'+cy+'" r="'+r+'" fill="none" stroke="'+colors[k]+'" stroke-width="'+sw+'"' +
        ' stroke-dasharray="'+len.toFixed(2)+' '+(C-len).toFixed(2)+'" stroke-dashoffset="'+(-offset).toFixed(2)+'"' +
        ' transform="rotate(-90 '+cx+' '+cy+')" stroke-linecap="butt"/>';
      offset += len;
    }
    svg.innerHTML = segs;
    list.innerHTML = '';
    for (const k of ['2xx','3xx','4xx','5xx']) {
      const v = totals[k], pct = (v/total)*100;
      const row = document.createElement('div');
      row.className = 'ep-dist-item';
      row.innerHTML =
        '<span class="ep-dist-sw" style="background:'+colors[k]+'"></span>' +
        '<span class="ep-dist-k mono">'+k+'</span>' +
        '<div class="ep-dist-bar"><span style="width:'+pct.toFixed(1)+'%;background:'+colors[k]+'"></span></div>' +
        '<span class="ep-dist-v mono">'+v.toLocaleString()+'</span>' +
        '<span class="ep-dist-p mono text-muted">'+pct.toFixed(1)+'%</span>';
      list.appendChild(row);
    }
  }

  function renderEndpointSamples(root, samples) {
    const tbody = root.querySelector('#ep-samples');
    const meta = root.querySelector('#ep-samples-meta');
    if (!tbody) return;
    tbody.innerHTML = '';
    if (!samples || !samples.length) {
      tbody.innerHTML = '<tr><td colspan="5" class="text-muted text-[11px] mono">no recent samples</td></tr>';
      if (meta) meta.textContent = '0 samples';
      return;
    }
    if (meta) meta.textContent = samples.length + ' samples';
    for (const s of samples.slice(0, 30)) {
      const tr = document.createElement('tr');
      const code = s.status || 0;
      const cls = code >= 500 ? 'badge-crit' : code >= 400 ? 'badge-warn' : code >= 300 ? 'badge-muted' : 'badge-ok';
      const ts = s.ts_ms ? new Date(s.ts_ms) : null;
      const tStr = ts ? ts.toLocaleTimeString([], {hour:'2-digit',minute:'2-digit',second:'2-digit',hour12:false}) : '—';
      tr.innerHTML =
        '<td class="mono text-muted">'+esc(tStr)+'</td>' +
        '<td><span class="badge '+cls+' mono">'+code+'</span></td>' +
        '<td class="text-right mono">'+(s.latency_ms!=null ? s.latency_ms+' ms' : '—')+'</td>' +
        '<td class="mono">'+esc(s.client_ip || '—')+'</td>' +
        '<td class="mono text-muted" title="'+esc(s.ua || '')+'">'+esc(s.ua || '—')+'</td>';
      tbody.appendChild(tr);
    }
  }

  function renderEndpointStatusBars(root, buckets) {
    const container = root.querySelector('#ep-status-bars');
    if (!container) return;
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
    const deployStatusFilter = (window.STATE && window.STATE.filters && window.STATE.filters.deploys && window.STATE.filters.deploys.status) || 'all';
    const deployRows = deployStatusFilter === 'healthy' ? (deploys.recent || []).filter(d => d.healthy)
                     : deployStatusFilter === 'failed'  ? (deploys.recent || []).filter(d => !d.healthy)
                     : (deploys.recent || []);
    if (!deployRows.length) {
      tbody.innerHTML = '<tr><td colspan="5" class="text-muted text-sm mono">No deploys recorded yet.</td></tr>';
      return;
    }
    tbody.innerHTML = '';
    for (const d of deployRows) {
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
      const auditActionFilter = (window.STATE && window.STATE.filters && window.STATE.filters.audit && window.STATE.filters.audit.action) || '';
      const auditEntries = auditActionFilter
        ? (data.entries || []).filter(e => e.action && e.action.includes(auditActionFilter))
        : (data.entries || []);
      if (!auditEntries.length) {
        tbody.innerHTML = '<tr><td colspan="5" class="text-muted text-sm mono">No actions recorded.</td></tr>';
        return;
      }
      tbody.innerHTML = '';
      for (const e of auditEntries.reverse()) {
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

  // ── AST-95: expose panel renderers so installPanelControls() can re-invoke
  // them when panel-local filter state changes without a full /metrics reload ──
  window.renderDeploys  = renderDeploys;
  window.loadAudit      = loadAudit;
  window.renderSQLTable = renderSQLTable;

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
    document.addEventListener('keydown', (e) => {
      if (window._termHasFocus && window._termHasFocus()) return;
      if (e.key === 'Escape') {
        document.querySelectorAll('tr.ep-drilldown-row').forEach(r => r.remove());
        document.querySelectorAll('tr.ep-row-open').forEach(r => r.classList.remove('ep-row-open'));
      }
    });

    // One-time seed from the server so control actions never trigger a prompt.
    seedTokenFromServer();

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

// ── AST-92 docker-exec terminal ──────────────────────────────────────
window.STATE = window.STATE || {};
STATE.terms = STATE.terms || {};   // service → { termHost, term, fitAddon, ws, sessionId, mountedAt, stale }

// Per-service command palette. Picking one types it into the attached
// shell and hits Enter. Commands are hard-coded here — never taken from
// user input — so there's no injection surface. Kept small (5 per svc).
// Every command has been verified to run in its container's actual image:
// postgres/redis/nginx/certbot are alpine; fastapi + arq_worker are
// python:3.11-slim, which means NO redis-cli / procps / alembic.ini in
// the image — so arq_worker uses the `redis` python module instead.
window.PRESET_CMDS = {
  postgres: [
    {label: 'migration head',          cmd: "psql -U astral -d astral -c 'SELECT version_num FROM alembic_version;'"},
    {label: 'list tables',             cmd: "psql -U astral -d astral -c '\\dt'"},
    {label: 'row counts (top 20)',     cmd: "psql -U astral -d astral -c \"SELECT relname AS table, n_live_tup AS rows, n_dead_tup AS dead FROM pg_stat_user_tables ORDER BY n_live_tup DESC LIMIT 20;\""},
    {label: 'table sizes (top 10)',    cmd: "psql -U astral -d astral -c \"SELECT relname AS table, pg_size_pretty(pg_total_relation_size(relid)) AS size FROM pg_stat_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 10;\""},
    {label: 'active queries',          cmd: "psql -U astral -d astral -c \"SELECT pid, state, now()-query_start AS runtime, substring(query, 1, 60) AS q FROM pg_stat_activity WHERE state <> 'idle' AND pid <> pg_backend_pid() ORDER BY query_start;\""},
  ],
  redis: [
    {label: 'dbsize',                  cmd: 'redis-cli dbsize'},
    {label: 'scan astral:*',           cmd: "redis-cli --scan --pattern 'astral:*' | head -30"},
    {label: 'bigkeys',                 cmd: 'redis-cli --bigkeys | tail -20'},
    {label: 'monitor 10s (live)',      cmd: 'timeout 10 redis-cli monitor 2>/dev/null || echo "(monitor ended)"'},
    {label: 'memory usage',            cmd: 'redis-cli info memory | head -15'},
  ],
  fastapi: [
    {label: 'route list',              cmd: "python -c \"from app.main import app\\nfor r in app.routes:\\n    print(getattr(r, 'methods', '') or '', getattr(r, 'path', r))\""},
    {label: 'health probe',            cmd: 'curl -sS http://127.0.0.1:8000/healthz || curl -sS http://127.0.0.1:8000/ | head -20'},
    {label: 'key pkg versions',        cmd: "pip show fastapi sqlalchemy asyncpg arq pydantic | grep -E 'Name:|Version:'"},
    {label: 'disk usage',              cmd: 'df -h /'},
    {label: 'astral env vars',         cmd: "env | grep -E '^ASTRAL_|^MONITOR_|^ARQ_|^FFNET_|^MANGADEX_' | sort"},
  ],
  arq_worker: [
    {label: 'arq check',               cmd: 'arq --check app.worker.WorkerSettings'},
    {label: 'queue depth',             cmd: "python -c \"import os, redis; r=redis.from_url(os.environ['REDIS_URL']); print('arq:queue ->', r.llen('arq:queue'))\""},
    {label: 'in-progress jobs',        cmd: "python -c \"import os, redis; r=redis.from_url(os.environ['REDIS_URL']); keys=list(r.scan_iter('arq:in-progress:*')); print(f'{len(keys)} in-progress'); [print(' ', k.decode()) for k in keys[:20]]\""},
    {label: 'recent results',          cmd: "python -c \"import os, redis; r=redis.from_url(os.environ['REDIS_URL']); keys=list(r.scan_iter('arq:result:*')); print(f'{len(keys)} result keys'); [print(' ', k.decode()) for k in keys[:10]]\""},
    {label: 'worker env',              cmd: "env | grep -E '^ARQ_|^REDIS_|^DATABASE_' | sort"},
  ],
  nginx: [
    {label: 'nginx -t (test)',         cmd: 'nginx -t'},
    {label: 'nginx -T (dump config)',  cmd: 'nginx -T 2>&1 | head -80'},
    {label: 'status codes (last 100)', cmd: "awk '{print $9}' /var/log/nginx/access.log 2>/dev/null | tail -100 | sort | uniq -c | sort -rn"},
    {label: '5xx tail',                cmd: "grep -E ' 5[0-9][0-9] ' /var/log/nginx/access.log 2>/dev/null | tail -20 || echo '(no 5xx or no log)'"},
    {label: 'reload config',           cmd: 'nginx -s reload'},
  ],
  certbot: [
    {label: 'list certificates',       cmd: 'certbot certificates'},
    {label: 'renew --dry-run',         cmd: 'certbot renew --dry-run'},
    {label: 'cert expiry (openssl)',   cmd: 'for c in /etc/letsencrypt/live/*/cert.pem; do echo "$c"; openssl x509 -enddate -noout -in "$c"; done'},
    {label: 'show renewal config',     cmd: 'cat /etc/letsencrypt/renewal/*.conf 2>/dev/null | head -60'},
    {label: 'renewal hooks dir',       cmd: 'ls -la /etc/letsencrypt/renewal-hooks/'},
  ],
};

function sendPresetCommand(service, cmd){
  if (!cmd) return;
  const entry = STATE.terms && STATE.terms[service];
  if (!entry || !entry.ws || entry.ws.readyState !== WebSocket.OPEN) return;
  entry.ws.send(new TextEncoder().encode(cmd + '\r'));
  // Server echoes the command back (TTY echo in prod, explicit echo in
  // the preview stub), so the typed text appears in the terminal card
  // without us having to local-echo. Just make sure the terminal has
  // focus so subsequent keystrokes go to the right place.
  try { entry.term.focus(); } catch(_){}
}
window.sendPresetCommand = sendPresetCommand;

// If the service grid already painted before this file finished loading,
// its preset-dropdown <option>s were built against an empty PRESET_CMDS.
// Re-run the render so the options appear without waiting for the next
// 30 s auto-refresh tick.
(function _rehydratePresets(){
  if (typeof window.renderServices !== 'function') return;
  if (!window.STATE || !window.STATE.data || !window.STATE.data.services) return;
  if (!document.querySelector('.svc-flip')) return;
  try { window.renderServices(); } catch(_){}
})();

// Close any open preset-command popover menu on outside click or Escape.
// Bound once globally — the per-render handlers in index.html only open
// and item-click; they don't need their own outside-click listener.
document.addEventListener('click', (e) => {
  if (e.target.closest && e.target.closest('.term-cmd-wrap')) return;
  document.querySelectorAll('.term-cmd-menu').forEach(m => {
    if (!m.hidden) {
      m.hidden = true;
      const btn = document.querySelector(`[data-cmd-button="${m.dataset.cmdMenu}"]`);
      if (btn) btn.setAttribute('aria-expanded', 'false');
    }
  });
});
document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  const open = document.querySelector('.term-cmd-menu:not([hidden])');
  if (!open) return;
  open.hidden = true;
  const btn = document.querySelector(`[data-cmd-button="${open.dataset.cmdMenu}"]`);
  if (btn) { btn.setAttribute('aria-expanded', 'false'); btn.focus(); }
});

function _monitorBase(){
  return location.pathname.startsWith('/monitor/') ? '/monitor' : '';
}

function _wsURL(sessionId){
  const scheme = location.protocol === 'https:' ? 'wss' : 'ws';
  return `${scheme}://${location.host}${_monitorBase()}/control/exec/${sessionId}`;
}

async function _postExecStart(service, cols, rows, token){
  const r = await fetch(`${_monitorBase()}/control/exec/start`, {
    method: 'POST',
    headers: {'Content-Type': 'application/json', 'X-Monitor-Auth': token || ''},
    body: JSON.stringify({service, cols, rows}),
  });
  if (r.status === 409) {
    const e = new Error('session-already-open'); e.status = 409; throw e;
  }
  if (!r.ok) {
    const e = new Error(await r.text()); e.status = r.status; throw e;
  }
  return r.json();
}

function _clearChildren(el){
  while (el.firstChild) el.removeChild(el.firstChild);
}

function _showTermBanner(termBody, message){
  const banner = document.createElement('div');
  banner.className = 'term-banner';
  banner.textContent = message;
  banner.style.cssText = 'padding:6px 10px;color:var(--warning);font-size:12px;';
  termBody.appendChild(banner);
}

async function openTerminal(wrap, service){
  const termBody = wrap.querySelector('.term-body');
  if (!termBody) return;

  // Warm-reopen path: existing live session → just re-attach.
  const prior = STATE.terms[service];
  if (prior && prior.ws && prior.ws.readyState === WebSocket.OPEN && !prior.stale) {
    if (!termBody.contains(prior.termHost)) {
      _clearChildren(termBody);
      termBody.appendChild(prior.termHost);
    }
    _afterFlipForward(wrap, prior);
    return;
  }
  const wasStale = !!(prior && prior.stale);
  if (prior) {
    try { prior.ws && prior.ws.close(); } catch(_){}
    delete STATE.terms[service];
  }

  // Cold open.
  _clearChildren(termBody);
  const token = (localStorage.getItem('monitor_control_token') || '').trim();
  if (!token) {
    _showTermBanner(termBody, 'Missing control token — set it in the dashboard.');
    return;
  }

  let startResp;
  try {
    startResp = await _postExecStart(service, 80, 24, token);
  } catch (e) {
    if (e.status === 409) {
      _showTermBanner(termBody,
        'Session already open (close the other tab, or wait 10 min for idle timeout).');
    } else {
      _showTermBanner(termBody, `Shell start failed: ${e.message || e.status}`);
    }
    return;
  }

  const termHost = document.createElement('div');
  termHost.style.cssText = 'width:100%;height:100%;';
  termBody.appendChild(termHost);

  // eslint-disable-next-line no-undef
  const term = new Terminal({
    fontFamily: '"JetBrains Mono", ui-monospace, monospace',
    fontSize: 11,
    theme: {background: '#0A0A0B', foreground: '#C8C8D4', cursor: '#C9A84C'},
    convertEol: true,
    cursorBlink: true,
  });
  // eslint-disable-next-line no-undef
  const fitAddon = new FitAddon.FitAddon();
  term.loadAddon(fitAddon);
  term.open(termHost);
  if (wasStale) {
    term.writeln('\x1b[33m[shell reconnected — previous session timed out]\x1b[0m');
  }

  const ws = new WebSocket(_wsURL(startResp.session_id), ['monitor-token', token]);
  ws.binaryType = 'arraybuffer';

  term.onData(d => {
    if (ws.readyState === WebSocket.OPEN) ws.send(new TextEncoder().encode(d));
  });

  ws.addEventListener('message', ev => {
    if (typeof ev.data === 'string') {
      let ctrl; try { ctrl = JSON.parse(ev.data); } catch(_) { return; }
      if (ctrl.type === 'closed') {
        term.writeln(`\r\n\x1b[33m[shell ${ctrl.reason || 'closed'}]\x1b[0m`);
      }
      return;
    }
    term.write(new Uint8Array(ev.data));
  });

  ws.addEventListener('close', () => {
    const entry = STATE.terms[service];
    if (entry) entry.stale = true;
  });

  STATE.terms[service] = {
    termHost, term, fitAddon, ws,
    sessionId: startResp.session_id,
    mountedAt: Date.now(),
    stale: false,
  };

  _afterFlipForward(wrap, STATE.terms[service]);
}

function _afterFlipForward(wrap, entry){
  const inner = wrap.querySelector('.svc-flip-inner');
  let settled = false;
  const done = () => {
    if (settled) return;
    settled = true;
    try { entry.fitAddon.fit(); } catch(_){}
    entry.term.focus();
    if (entry.ws && entry.ws.readyState === WebSocket.OPEN) {
      entry.ws.send(JSON.stringify({
        type: 'resize', cols: entry.term.cols, rows: entry.term.rows,
      }));
    }
  };
  const handler = (ev) => {
    if (ev.target !== inner) return;
    inner.removeEventListener('transitionend', handler);
    done();
  };
  if (inner) inner.addEventListener('transitionend', handler);
  setTimeout(done, 400);

  if (!wrap._termResizeObs) {
    wrap._termResizeObs = new ResizeObserver(() => {
      try { entry.fitAddon.fit(); } catch(_){}
      if (entry.ws && entry.ws.readyState === WebSocket.OPEN) {
        entry.ws.send(JSON.stringify({
          type: 'resize', cols: entry.term.cols, rows: entry.term.rows,
        }));
      }
    });
    wrap._termResizeObs.observe(wrap.querySelector('.term-body'));
  }
}

// Invoked from existing global keyboard-shortcut handlers.
window._termHasFocus = function(){
  return !!document.activeElement?.closest('.term-body');
};

window.addEventListener('beforeunload', () => {
  if (!STATE.terms) return;
  for (const k of Object.keys(STATE.terms)) {
    try { STATE.terms[k].ws && STATE.terms[k].ws.close(1000, 'tab-close'); } catch(_){}
  }
});
