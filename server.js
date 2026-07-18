/**
 * Raid2 Bot Server — Railway deploy v2
 * Dashboard + API: trạng thái padding, combat, raid wave, cooldown realtime
 */

const express = require("express");
const cors    = require("cors");
const { v4: uuidv4 } = require("uuid");

const app  = express();
const PORT = process.env.PORT || 3000;
const API_KEY = process.env.API_KEY || "";

app.use(cors());
app.use(express.json({ limit: "1mb" }));

// ─── In-memory store ─────────────────────────────────────────────────────────
/** @type {Map<string, AccountRecord>} */
const accounts = new Map();

/**
 * @typedef {Object} AccountRecord
 * @property {string}  id
 * @property {string}  username
 * @property {string}  jobId
 * @property {string}  state        — INIT | LOADING | PADDING | BUYING_VEST | PULLUP | RAID_WAITING | IN_RAID | HOP | STOPPED
 * @property {string}  detail       — mô tả chi tiết bước hiện tại
 * @property {number}  raid1Cooldown  — giây còn lại (realtime, server trừ dần)
 * @property {number}  raid2Cooldown
 * @property {number}  raid1CooldownSetAt  — Date.now() lúc client báo cooldown
 * @property {number}  raid2CooldownSetAt
 * @property {boolean} inCombat
 * @property {boolean} macroOn
 * @property {boolean} hasVest
 * @property {boolean} onPullup
 * @property {number}  waveNumber   — wave hiện tại trong raid (0 = lobby/chờ)
 * @property {boolean} stopped
 * @property {Object|null} pendingCommand
 * @property {number}  lastSeen
 * @property {number}  createdAt
 */

function now() { return Date.now(); }

function createAccount(username, jobId) {
  const id = uuidv4();
  const record = {
    id,
    username: username || "unknown",
    jobId: jobId || "",
    state: "INIT",
    detail: "",
    raid1Cooldown: 0,
    raid2Cooldown: 0,
    raid1CooldownSetAt: 0,
    raid2CooldownSetAt: 0,
    inCombat: false,
    macroOn: false,
    hasVest: false,
    onPullup: false,
    waveNumber: 0,
    stopped: false,
    pendingCommand: null,
    lastSeen: now(),
    createdAt: now(),
  };
  accounts.set(id, record);
  return record;
}

function findByUsername(username) {
  for (const acc of accounts.values()) {
    if (acc.username === username) return acc;
  }
  return null;
}

/** Tính cooldown realtime (server tự trừ theo thời gian đã qua) */
function getRemainingCooldown(acc, raidNum) {
  const raw = raidNum === 1 ? acc.raid1Cooldown : acc.raid2Cooldown;
  const setAt = raidNum === 1 ? acc.raid1CooldownSetAt : acc.raid2CooldownSetAt;
  if (!raw || raw <= 0) return 0;
  const elapsed = Math.floor((now() - setAt) / 1000);
  const remaining = raw - elapsed;
  return remaining > 0 ? remaining : 0;
}

function authMiddleware(req, res, next) {
  if (!API_KEY) return next();
  const key = req.headers["x-api-key"] || req.query.key;
  if (key !== API_KEY) return res.status(401).json({ error: "Unauthorized" });
  next();
}

// ─── API: Game client ────────────────────────────────────────────────────────

/** Đăng ký / heartbeat */
app.post("/api/register", authMiddleware, (req, res) => {
  const { username, jobId, accountId } = req.body || {};
  let acc = accountId ? accounts.get(accountId) : null;
  if (!acc && username) acc = findByUsername(username);
  if (!acc) acc = createAccount(username, jobId);

  acc.username = username || acc.username;
  acc.jobId    = jobId    || acc.jobId;
  acc.lastSeen = now();

  res.json({ ok: true, accountId: acc.id, stopped: acc.stopped });
});

/** Game gửi trạng thái lên */
app.post("/api/status", authMiddleware, (req, res) => {
  const body = req.body || {};
  const acc  = accounts.get(body.accountId);
  if (!acc) return res.status(404).json({ error: "Account not found" });

  const fields = [
    "state","detail","jobId",
    "inCombat","macroOn","hasVest","onPullup","waveNumber",
  ];
  for (const f of fields) {
    if (body[f] !== undefined) acc[f] = body[f];
  }

  // Cooldown: client gửi số giây tại thời điểm nhận từ server
  if (body.raid1Cooldown !== undefined && body.raid1Cooldown > 0) {
    acc.raid1Cooldown      = body.raid1Cooldown;
    acc.raid1CooldownSetAt = now();
  }
  if (body.raid2Cooldown !== undefined && body.raid2Cooldown > 0) {
    acc.raid2Cooldown      = body.raid2Cooldown;
    acc.raid2CooldownSetAt = now();
  }

  acc.lastSeen = now();

  res.json({
    ok: true,
    stopped: acc.stopped,
    command: acc.pendingCommand,
  });

  if (acc.pendingCommand && acc.pendingCommand.oneShot !== false) {
    acc.pendingCommand = null;
  }
});

/** Poll lệnh */
app.get("/api/commands/:accountId", authMiddleware, (req, res) => {
  const acc = accounts.get(req.params.accountId);
  if (!acc) return res.status(404).json({ error: "Not found" });
  const cmd = acc.pendingCommand;
  if (cmd && cmd.oneShot !== false) acc.pendingCommand = null;
  res.json({ command: cmd, stopped: acc.stopped });
});

// ─── API: Dashboard actions ──────────────────────────────────────────────────

function queueCommand(accountId, command) {
  const acc = accounts.get(accountId);
  if (!acc) return null;
  acc.pendingCommand = { ...command, queuedAt: now() };
  return acc.pendingCommand;
}

app.get("/api/accounts", (req, res) => {
  const list = [...accounts.values()]
    .sort((a, b) => b.lastSeen - a.lastSeen)
    .map((a) => ({
      ...a,
      raid1CooldownRemaining: getRemainingCooldown(a, 1),
      raid2CooldownRemaining: getRemainingCooldown(a, 2),
      pendingCommand: a.pendingCommand ? a.pendingCommand.type : null,
      offline: now() - a.lastSeen > 60_000,
    }));
  res.json({ accounts: list, count: list.length });
});

app.post("/api/accounts/:id/hop",      (req, res) => {
  const cmd = queueCommand(req.params.id, { type: "HOP_SERVER", oneShot: true });
  if (!cmd) return res.status(404).json({ error: "Not found" });
  res.json({ ok: true, command: cmd });
});

app.post("/api/accounts/:id/hop-job",  (req, res) => {
  const { jobId } = req.body || {};
  if (!jobId) return res.status(400).json({ error: "jobId required" });
  const cmd = queueCommand(req.params.id, { type: "HOP_JOB", jobId: String(jobId), oneShot: true });
  if (!cmd) return res.status(404).json({ error: "Not found" });
  res.json({ ok: true, command: cmd });
});

app.post("/api/accounts/:id/stop",     (req, res) => {
  const acc = accounts.get(req.params.id);
  if (!acc) return res.status(404).json({ error: "Not found" });
  acc.stopped = true;
  queueCommand(req.params.id, { type: "STOP", oneShot: true });
  res.json({ ok: true, stopped: true });
});

app.post("/api/accounts/:id/resume",   (req, res) => {
  const acc = accounts.get(req.params.id);
  if (!acc) return res.status(404).json({ error: "Not found" });
  acc.stopped = false;
  queueCommand(req.params.id, { type: "RESUME", oneShot: true });
  res.json({ ok: true, stopped: false });
});

app.post("/api/accounts/:id/fire-raid1", (req, res) => {
  const cmd = queueCommand(req.params.id, { type: "FIRE_RAID1", oneShot: true });
  if (!cmd) return res.status(404).json({ error: "Not found" });
  res.json({ ok: true, command: cmd });
});

app.post("/api/accounts/:id/fire-raid2", (req, res) => {
  const cmd = queueCommand(req.params.id, { type: "FIRE_RAID2", oneShot: true });
  if (!cmd) return res.status(404).json({ error: "Not found" });
  res.json({ ok: true, command: cmd });
});

app.delete("/api/accounts/:id",        (req, res) => {
  res.json({ ok: accounts.delete(req.params.id) });
});

// ─── Health & Dashboard ───────────────────────────────────────────────────────

app.get("/health", (_req, res) => {
  res.json({ ok: true, accounts: accounts.size, uptime: process.uptime() });
});

app.get("/", (_req, res) => res.type("html").send(DASHBOARD_HTML));

app.listen(PORT, () => {
  console.log(`Raid2 Bot Server v2 running on port ${PORT}`);
  if (API_KEY) console.log("API_KEY enabled");
});

// ─── Dashboard HTML ───────────────────────────────────────────────────────────

const DASHBOARD_HTML = `<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>Raid2 Bot — Dashboard</title>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap');
    *{box-sizing:border-box;margin:0;padding:0}
    :root{
      --bg:#0a0a0f;--surface:#111118;--border:#1e1e2e;--border2:#2a2a40;
      --text:#e2e8f0;--muted:#64748b;--accent:#7c3aed;--accent2:#6d28d9;
      --green:#22c55e;--red:#ef4444;--yellow:#f59e0b;--blue:#3b82f6;--cyan:#06b6d4;
    }
    body{font-family:'Inter',system-ui,sans-serif;background:var(--bg);color:var(--text);min-height:100vh;padding:0}
    /* Header */
    .header{background:linear-gradient(135deg,#1a0533 0%,#0a0a1f 50%,#001a33 100%);border-bottom:1px solid var(--border2);padding:20px 28px;display:flex;align-items:center;justify-content:space-between}
    .header-left h1{font-size:1.5rem;font-weight:700;background:linear-gradient(90deg,#a78bfa,#60a5fa);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
    .header-left p{color:var(--muted);font-size:.82rem;margin-top:3px}
    .header-right{display:flex;align-items:center;gap:12px}
    .live-badge{display:flex;align-items:center;gap:6px;background:rgba(34,197,94,.12);border:1px solid rgba(34,197,94,.3);border-radius:20px;padding:4px 12px;font-size:.75rem;color:var(--green);font-weight:600}
    .live-dot{width:7px;height:7px;border-radius:50%;background:var(--green);animation:pulse 1.5s infinite}
    @keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}
    /* Toolbar */
    .toolbar{padding:16px 28px;display:flex;align-items:center;gap:12px;border-bottom:1px solid var(--border)}
    .btn{border:none;border-radius:8px;padding:7px 14px;font-size:.78rem;cursor:pointer;font-weight:600;transition:all .15s}
    .btn-refresh{background:var(--border2);color:var(--text)}
    .btn-refresh:hover{background:#333350}
    #count{color:var(--muted);font-size:.82rem}
    /* Grid */
    .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(340px,1fr));gap:16px;padding:20px 28px}
    /* Card */
    .card{background:var(--surface);border:1px solid var(--border);border-radius:14px;padding:0;overflow:hidden;transition:border-color .2s,transform .2s}
    .card:hover{border-color:var(--border2);transform:translateY(-1px)}
    .card-header{padding:14px 16px;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid var(--border)}
    .card-username{font-size:1rem;font-weight:700;display:flex;align-items:center;gap:8px}
    .status-dot{width:9px;height:9px;border-radius:50%;flex-shrink:0}
    .dot-online{background:var(--green);box-shadow:0 0 6px rgba(34,197,94,.6)}
    .dot-offline{background:var(--red)}
    .state-badge{padding:3px 10px;border-radius:20px;font-size:.7rem;font-weight:700;letter-spacing:.04em;text-transform:uppercase}
    /* State colors */
    .s-INIT,.s-LOADING{background:rgba(100,116,139,.2);color:#94a3b8}
    .s-PADDING,.s-BUYING_VEST{background:rgba(59,130,246,.18);color:#93c5fd}
    .s-PULLUP{background:rgba(124,58,237,.18);color:#c4b5fd}
    .s-RAID_WAITING{background:rgba(245,158,11,.18);color:#fcd34d}
    .s-IN_RAID{background:rgba(239,68,68,.2);color:#fca5a5}
    .s-HOP{background:rgba(6,182,212,.18);color:#67e8f9}
    .s-STOPPED{background:rgba(100,116,139,.1);color:#475569}
    /* Stats grid */
    .stats{display:grid;grid-template-columns:1fr 1fr;gap:0}
    .stat{padding:9px 16px;border-bottom:1px solid var(--border);border-right:1px solid var(--border)}
    .stat:nth-child(2n){border-right:none}
    .stat:nth-last-child(-n+2){border-bottom:none}
    .stat-label{font-size:.68rem;color:var(--muted);text-transform:uppercase;letter-spacing:.05em;margin-bottom:3px}
    .stat-val{font-size:.85rem;font-weight:600;color:var(--text)}
    .stat-val.ok{color:var(--green)}
    .stat-val.warn{color:var(--yellow)}
    .stat-val.danger{color:var(--red)}
    .stat-val.info{color:#93c5fd}
    /* Detail bar */
    .detail-bar{padding:8px 16px;background:rgba(124,58,237,.06);border-top:1px solid var(--border);font-size:.75rem;color:#a78bfa;display:flex;align-items:center;gap:6px;min-height:34px}
    /* Cooldown bar */
    .cd-bar-wrap{padding:10px 16px;border-top:1px solid var(--border)}
    .cd-label{font-size:.68rem;color:var(--muted);text-transform:uppercase;letter-spacing:.04em;margin-bottom:5px}
    .cd-bars{display:flex;flex-direction:column;gap:5px}
    .cd-row{display:flex;align-items:center;gap:8px;font-size:.75rem}
    .cd-name{color:var(--muted);width:50px}
    .cd-track{flex:1;height:5px;background:#1e1e2e;border-radius:3px;overflow:hidden}
    .cd-fill{height:100%;border-radius:3px;transition:width .5s}
    .cd-fill.r1{background:linear-gradient(90deg,#7c3aed,#a78bfa)}
    .cd-fill.r2{background:linear-gradient(90deg,#0369a1,#38bdf8)}
    .cd-time{color:var(--text);font-weight:600;width:55px;text-align:right}
    /* Actions */
    .actions{padding:10px 16px;border-top:1px solid var(--border);display:flex;flex-wrap:wrap;gap:5px}
    .btn-hop{background:#1d4ed8;color:#fff}
    .btn-hop:hover{background:#2563eb}
    .btn-stop{background:#b91c1c;color:#fff}
    .btn-stop:hover{background:#dc2626}
    .btn-resume{background:#15803d;color:#fff}
    .btn-resume:hover{background:#16a34a}
    .btn-raid{background:#5b21b6;color:#fff}
    .btn-raid:hover{background:#7c3aed}
    .btn-del{background:var(--border2);color:var(--muted)}
    .btn-del:hover{background:#333350;color:var(--text)}
    .hop-row{display:flex;align-items:center;gap:4px;width:100%}
    .hop-row input{flex:1;background:var(--border);border:1px solid var(--border2);color:var(--text);border-radius:6px;padding:5px 8px;font-size:.72rem;font-family:monospace}
    /* Empty state */
    .empty{color:var(--muted);text-align:center;padding:60px 20px;font-size:.9rem}
    .empty-icon{font-size:2.5rem;margin-bottom:12px}
    /* Scrollbar */
    ::-webkit-scrollbar{width:5px}::-webkit-scrollbar-track{background:var(--bg)}::-webkit-scrollbar-thumb{background:var(--border2);border-radius:3px}
  </style>
</head>
<body>
  <div class="header">
    <div class="header-left">
      <h1>⚔️ Raid2 Bot Dashboard</h1>
      <p>Theo dõi trạng thái realtime · Gửi lệnh hop / raid / stop</p>
    </div>
    <div class="header-right">
      <div class="live-badge"><div class="live-dot"></div>LIVE</div>
    </div>
  </div>
  <div class="toolbar">
    <button class="btn btn-refresh" onclick="load()">🔄 Refresh</button>
    <span id="count">Đang tải...</span>
  </div>
  <div id="grid" class="grid"><div class="empty"><div class="empty-icon">🔌</div>Đang kết nối...</div></div>

  <script>
    // Cooldown max gốc để vẽ thanh progress (fallback 3600s = 1h)
    const cdMax = {};

    async function api(path, opts) {
      const r = await fetch(path, opts);
      return r.json();
    }
    async function act(id, action, body) {
      await api('/api/accounts/' + id + '/' + action, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: body ? JSON.stringify(body) : undefined
      });
      load();
    }

    function fmtSec(s) {
      if (!s || s <= 0) return '<span style="color:var(--green)">Ready ✅</span>';
      const h = Math.floor(s / 3600);
      const m = Math.floor((s % 3600) / 60);
      const sec = s % 60;
      if (h) return h + 'h ' + m + 'm ' + sec + 's';
      if (m) return m + 'm ' + sec + 's';
      return sec + 's';
    }

    function stateClass(s) {
      return 's-' + (s || 'INIT');
    }

    function stateIcon(s) {
      const icons = {
        INIT:'🔄', LOADING:'⏳', PADDING:'🏃', BUYING_VEST:'🛒',
        PULLUP:'💪', RAID_WAITING:'⚔️', IN_RAID:'🔥', HOP:'🔀', STOPPED:'⏹️'
      };
      return icons[s] || '❓';
    }

    function cdBar(remaining, raidNum, accId) {
      // Track max seen cooldown per account/raid
      const key = accId + '_r' + raidNum;
      if (remaining > 0 && (!cdMax[key] || remaining > cdMax[key])) {
        cdMax[key] = remaining;
      }
      const max = cdMax[key] || 3600;
      const pct = remaining <= 0 ? 100 : Math.max(2, Math.round((1 - remaining / max) * 100));
      const label = 'Raid' + raidNum;
      const fillClass = raidNum === 1 ? 'r1' : 'r2';
      return \`<div class="cd-row">
        <span class="cd-name">\${label}</span>
        <div class="cd-track"><div class="cd-fill \${fillClass}" style="width:\${pct}%"></div></div>
        <span class="cd-time">\${fmtSec(remaining)}</span>
      </div>\`;
    }

    function wave(n) {
      if (!n || n <= 0) return '<span style="color:var(--muted)">—</span>';
      if (n >= 10) return '<span style="color:var(--red);font-weight:700">BOSS 💀</span>';
      return '<span style="color:var(--yellow)">Wave ' + n + '</span>';
    }

    function yn(v, trueLabel, falseLabel) {
      trueLabel  = trueLabel  || 'YES';
      falseLabel = falseLabel || 'no';
      return v
        ? '<span class="stat-val ok">' + trueLabel + '</span>'
        : '<span class="stat-val">' + falseLabel + '</span>';
    }

    function card(a) {
      const offlineCls = a.offline ? 'dot-offline' : 'dot-online';
      const r1 = a.raid1CooldownRemaining || 0;
      const r2 = a.raid2CooldownRemaining || 0;
      const timeSince = Math.floor((Date.now() - a.lastSeen) / 1000);
      const seenAgo = timeSince < 5 ? 'Vừa xong' : timeSince + 's trước';

      return \`<div class="card">
        <div class="card-header">
          <div class="card-username">
            <span class="status-dot \${offlineCls}"></span>
            \${a.username}
            \${a.stopped ? '<span style="color:var(--red);font-size:.7rem">(STOPPED)</span>' : ''}
          </div>
          <span class="state-badge \${stateClass(a.state)}">\${stateIcon(a.state)} \${a.state}</span>
        </div>

        <div class="stats">
          <div class="stat">
            <div class="stat-label">InCombat</div>
            \${yn(a.inCombat, '⚔️ YES', '🛡️ no')}
          </div>
          <div class="stat">
            <div class="stat-label">Macro</div>
            \${yn(a.macroOn, '✅ ON', '❌ off')}
          </div>
          <div class="stat">
            <div class="stat-label">Vest 80KG</div>
            \${yn(a.hasVest, '✅ có', '❌ chưa')}
          </div>
          <div class="stat">
            <div class="stat-label">PullUp</div>
            \${yn(a.onPullup, '💪 Đang tập', '— không')}
          </div>
          <div class="stat">
            <div class="stat-label">Wave</div>
            \${wave(a.waveNumber)}
          </div>
          <div class="stat">
            <div class="stat-label">Seen</div>
            <span class="stat-val \${a.offline ? 'danger' : 'ok'}">\${seenAgo}</span>
          </div>
        </div>

        <div class="detail-bar">📋 \${a.detail || '—'}</div>

        <div class="cd-bar-wrap">
          <div class="cd-label">Raid Cooldown</div>
          <div class="cd-bars">
            \${cdBar(r1, 1, a.id)}
            \${cdBar(r2, 2, a.id)}
          </div>
        </div>

        <div class="actions">
          <button class="btn btn-hop" onclick="act('\${a.id}','hop')">🔀 Hop</button>
          <button class="btn btn-stop" onclick="act('\${a.id}','stop')">⏹ Stop</button>
          <button class="btn btn-resume" onclick="act('\${a.id}','resume')">▶️ Resume</button>
          <button class="btn btn-raid" onclick="act('\${a.id}','fire-raid1')">⚔️ Raid1</button>
          <button class="btn btn-raid" onclick="act('\${a.id}','fire-raid2')">⚔️ Raid2</button>
          <button class="btn btn-del" onclick="fetch('/api/accounts/\${a.id}',{method:'DELETE'}).then(load)">🗑 Xóa</button>
          <div class="hop-row">
            <input type="text" id="job-\${a.id}" placeholder="JobId để hop vào server cụ thể..."/>
            <button class="btn btn-hop" onclick="act('\${a.id}','hop-job',{jobId:document.getElementById('job-\${a.id}').value})">Hop JobId</button>
          </div>
        </div>
      </div>\`;
    }

    async function load() {
      const data = await api('/api/accounts');
      const cnt  = document.getElementById('count');
      const grid = document.getElementById('grid');
      cnt.textContent = data.count + ' account(s) kết nối';
      if (!data.accounts.length) {
        grid.innerHTML = '<div class="empty"><div class="empty-icon">🔌</div>Chưa có account nào kết nối</div>';
        return;
      }
      grid.innerHTML = data.accounts.map(card).join('');
    }

    load();
    setInterval(load, 4000);
  </script>
</body>
</html>`;
