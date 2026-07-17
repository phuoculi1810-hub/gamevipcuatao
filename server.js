/**
 * Raid2 Bot Server — Railway deploy
 * Dashboard + API cho game script Lua sync trạng thái & nhận lệnh
 */

const express = require("express");
const cors = require("cors");
const { v4: uuidv4 } = require("uuid");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 3000;
const API_KEY = process.env.API_KEY || ""; // optional — để trống = không check

app.use(cors());
app.use(express.json({ limit: "1mb" }));

// ─── In-memory store ─────────────────────────────────────────────────────────
/** @type {Map<string, AccountRecord>} */
const accounts = new Map();

/**
 * @typedef {Object} AccountRecord
 * @property {string} id
 * @property {string} username
 * @property {string} jobId
 * @property {string} state
 * @property {string} detail
 * @property {number} raid1Cooldown
 * @property {number} raid2Cooldown
 * @property {boolean} inCombat
 * @property {boolean} macroOn
 * @property {boolean} hasVest
 * @property {boolean} onPullup
 * @property {boolean} stopped
 * @property {Object|null} pendingCommand
 * @property {number} lastSeen
 * @property {number} createdAt
 */

function now() {
  return Date.now();
}

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
    inCombat: false,
    macroOn: false,
    hasVest: false,
    onPullup: false,
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

function authMiddleware(req, res, next) {
  if (!API_KEY) return next();
  const key = req.headers["x-api-key"] || req.query.key;
  if (key !== API_KEY) {
    return res.status(401).json({ error: "Unauthorized" });
  }
  next();
}

// ─── API: Game client ────────────────────────────────────────────────────────

/** Đăng ký / heartbeat từ game script */
app.post("/api/register", authMiddleware, (req, res) => {
  const { username, jobId, accountId } = req.body || {};

  let acc = accountId ? accounts.get(accountId) : null;
  if (!acc && username) acc = findByUsername(username);
  if (!acc) acc = createAccount(username, jobId);

  acc.username = username || acc.username;
  acc.jobId = jobId || acc.jobId;
  acc.lastSeen = now();

  res.json({ ok: true, accountId: acc.id, stopped: acc.stopped });
});

/** Game gửi trạng thái lên Railway */
app.post("/api/status", authMiddleware, (req, res) => {
  const body = req.body || {};
  const acc = accounts.get(body.accountId);
  if (!acc) {
    return res.status(404).json({ error: "Account not found" });
  }

  const fields = [
    "state",
    "detail",
    "jobId",
    "raid1Cooldown",
    "raid2Cooldown",
    "inCombat",
    "macroOn",
    "hasVest",
    "onPullup",
  ];
  for (const f of fields) {
    if (body[f] !== undefined) acc[f] = body[f];
  }
  acc.lastSeen = now();

  res.json({
    ok: true,
    stopped: acc.stopped,
    command: acc.pendingCommand,
  });

  // one-shot command
  if (acc.pendingCommand && acc.pendingCommand.oneShot !== false) {
    acc.pendingCommand = null;
  }
});

/** Game poll lệnh từ dashboard */
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
      pendingCommand: a.pendingCommand ? a.pendingCommand.type : null,
      offline: now() - a.lastSeen > 60_000,
    }));
  res.json({ accounts: list, count: list.length });
});

app.post("/api/accounts/:id/hop", (req, res) => {
  const cmd = queueCommand(req.params.id, { type: "HOP_SERVER", oneShot: true });
  if (!cmd) return res.status(404).json({ error: "Not found" });
  res.json({ ok: true, command: cmd });
});

app.post("/api/accounts/:id/hop-job", (req, res) => {
  const { jobId } = req.body || {};
  if (!jobId) return res.status(400).json({ error: "jobId required" });
  const cmd = queueCommand(req.params.id, {
    type: "HOP_JOB",
    jobId: String(jobId),
    oneShot: true,
  });
  if (!cmd) return res.status(404).json({ error: "Not found" });
  res.json({ ok: true, command: cmd });
});

app.post("/api/accounts/:id/stop", (req, res) => {
  const acc = accounts.get(req.params.id);
  if (!acc) return res.status(404).json({ error: "Not found" });
  acc.stopped = true;
  queueCommand(req.params.id, { type: "STOP", oneShot: true });
  res.json({ ok: true, stopped: true });
});

app.post("/api/accounts/:id/resume", (req, res) => {
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

app.post("/api/accounts/:id/check-cooldown", (req, res) => {
  const cmd = queueCommand(req.params.id, {
    type: "CHECK_COOLDOWN",
    oneShot: true,
  });
  if (!cmd) return res.status(404).json({ error: "Not found" });
  res.json({ ok: true, command: cmd });
});

app.delete("/api/accounts/:id", (req, res) => {
  const ok = accounts.delete(req.params.id);
  res.json({ ok });
});

// ─── Dashboard HTML ───────────────────────────────────────────────────────────

app.get("/", (_req, res) => {
  res.type("html").send(DASHBOARD_HTML);
});

app.get("/health", (_req, res) => {
  res.json({ ok: true, accounts: accounts.size, uptime: process.uptime() });
});

// ─── Start ───────────────────────────────────────────────────────────────────

app.listen(PORT, () => {
  console.log(`Raid2 Bot Server running on port ${PORT}`);
  console.log(`Dashboard: http://localhost:${PORT}`);
  if (API_KEY) console.log("API_KEY enabled");
});

// ─── Dashboard (inline) ──────────────────────────────────────────────────────

const DASHBOARD_HTML = `<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Raid2 Bot — CPanel</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:system-ui,-apple-system,sans-serif;background:#0f1117;color:#e4e4e7;min-height:100vh;padding:24px}
    h1{font-size:1.4rem;margin-bottom:4px}
    .sub{color:#71717a;font-size:.85rem;margin-bottom:20px}
    .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(320px,1fr));gap:16px}
    .card{background:#18181b;border:1px solid #27272a;border-radius:12px;padding:16px}
    .card h2{font-size:1rem;margin-bottom:8px;display:flex;align-items:center;gap:8px}
    .dot{width:8px;height:8px;border-radius:50%;display:inline-block}
    .dot.on{background:#22c55e}.dot.off{background:#ef4444}
    .row{display:flex;justify-content:space-between;font-size:.82rem;padding:3px 0;color:#a1a1aa}
    .row b{color:#e4e4e7;font-weight:500}
    .btns{display:flex;flex-wrap:wrap;gap:6px;margin-top:12px}
    button{border:none;border-radius:8px;padding:6px 10px;font-size:.75rem;cursor:pointer;font-weight:600}
    .btn-hop{background:#2563eb;color:#fff}
    .btn-stop{background:#dc2626;color:#fff}
    .btn-resume{background:#16a34a;color:#fff}
    .btn-raid{background:#7c3aed;color:#fff}
    .btn-check{background:#ca8a04;color:#fff}
    .btn-del{background:#3f3f46;color:#a1a1aa}
    input[type=text]{background:#27272a;border:1px solid #3f3f46;color:#fff;border-radius:6px;padding:5px 8px;font-size:.75rem;width:120px}
    .toolbar{display:flex;gap:10px;align-items:center;margin-bottom:16px}
    .toolbar button{background:#27272a;color:#e4e4e7;border:1px solid #3f3f46}
    .empty{color:#71717a;text-align:center;padding:40px}
    .state-tag{display:inline-block;background:#27272a;padding:2px 8px;border-radius:6px;font-size:.75rem;color:#a78bfa}
  </style>
</head>
<body>
  <h1>Raid2 Bot — Dashboard</h1>
  <p class="sub">Theo dõi account realtime · Gửi lệnh hop / raid / stop</p>
  <div class="toolbar">
    <button onclick="load()">Refresh</button>
    <span id="count" class="sub"></span>
  </div>
  <div id="grid" class="grid"><p class="empty">Đang tải...</p></div>
  <script>
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
    function fmtCd(s) {
      if (!s || s <= 0) return 'Ready';
      const h = Math.floor(s/3600), m = Math.floor((s%3600)/60), sec = s%60;
      if (h) return h+'h '+m+'m';
      if (m) return m+'m '+sec+'s';
      return sec+'s';
    }
    function card(a) {
      const offline = a.offline;
      return \`<div class="card">
        <h2><span class="dot \${offline?'off':'on'}"></span>\${a.username}</h2>
        <div class="row"><span>State</span><span class="state-tag">\${a.state}</span></div>
        <div class="row"><span>Detail</span><b>\${a.detail||'-'}</b></div>
        <div class="row"><span>JobId</span><b style="font-size:.7rem;word-break:break-all">\${a.jobId||'-'}</b></div>
        <div class="row"><span>Raid1 CD</span><b>\${fmtCd(a.raid1Cooldown)}</b></div>
        <div class="row"><span>Raid2 CD</span><b>\${fmtCd(a.raid2Cooldown)}</b></div>
        <div class="row"><span>Combat</span><b>\${a.inCombat?'YES':'no'}</b></div>
        <div class="row"><span>Macro</span><b>\${a.macroOn?'ON':'off'}</b></div>
        <div class="row"><span>Vest</span><b>\${a.hasVest?'yes':'no'}</b></div>
        <div class="row"><span>PullUp</span><b>\${a.onPullup?'yes':'no'}</b></div>
        <div class="row"><span>Stopped</span><b>\${a.stopped?'YES':'no'}</b></div>
        <div class="btns">
          <button class="btn-hop" onclick="act('\${a.id}','hop')">Hop server</button>
          <input type="text" id="job-\${a.id}" placeholder="JobId"/>
          <button class="btn-hop" onclick="act('\${a.id}','hop-job',{jobId:document.getElementById('job-\${a.id}').value})">Hop JobId</button>
          <button class="btn-stop" onclick="act('\${a.id}','stop')">Stop</button>
          <button class="btn-resume" onclick="act('\${a.id}','resume')">Resume</button>
          <button class="btn-raid" onclick="act('\${a.id}','fire-raid1')">Fire Raid1</button>
          <button class="btn-raid" onclick="act('\${a.id}','fire-raid2')">Fire Raid2</button>
          <button class="btn-check" onclick="act('\${a.id}','check-cooldown')">Check CD</button>
          <button class="btn-del" onclick="fetch('/api/accounts/\${a.id}',{method:'DELETE'}).then(load)">Xóa</button>
        </div>
      </div>\`;
    }
    async function load() {
      const data = await api('/api/accounts');
      document.getElementById('count').textContent = data.count + ' account(s)';
      const grid = document.getElementById('grid');
      if (!data.accounts.length) {
        grid.innerHTML = '<p class="empty">Chưa có account nào kết nối</p>';
        return;
      }
      grid.innerHTML = data.accounts.map(card).join('');
    }
    load();
    setInterval(load, 5000);
  </script>
</body>
</html>`;
