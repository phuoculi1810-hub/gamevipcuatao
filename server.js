// =============================================================================
// 🧠 RAILWAY SERVER - Bộ não điều khiển Auto Raid System
// =============================================================================

const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(bodyParser.json());
app.use(express.static('public'));

// =============================================================================
// 📊 STATE MANAGEMENT
// =============================================================================

// Global state for all accounts
const accountStates = new Map();

// Initialize account state
function getAccountState(accountId) {
    if (!accountStates.has(accountId)) {
        accountStates.set(accountId, {
            id: accountId,
            status: 'idle', // idle, loading, clicking_play, moving_safezone, disabling_lockon, checking_pullup, padding_glass, padding_shop, buying_vest, checking_automacro, equipping_vest, padding_pullup, clicking_pullup, on_pullup, checking_cooldown, firing_raid1, firing_raid2, in_raid1, in_raid2, raid_wave, raid_boss, teleporting_back, hopping_server
            lastUpdate: new Date().toISOString(),
            cooldown: {
                raid1: 0,
                raid2: 0,
                raid1StartTime: null,
                raid2StartTime: null
            },
            serverId: null,
            isInCombat: false,
            isOnPullup: false,
            lastPullupTime: null,
            vestOwned: false,
            autoMacroEnabled: false,
            currentWave: null,
            raidType: null // 'raid1' or 'raid2'
        });
    }
    return accountStates.get(accountId);
}

// =============================================================================
// 🔧 UTILITY FUNCTIONS
// =============================================================================

function updateAccountState(accountId, updates) {
    const state = getAccountState(accountId);
    Object.assign(state, updates);
    state.lastUpdate = new Date().toISOString();
    return state;
}

function formatCooldown(seconds) {
    if (seconds <= 0) return 'Ready';
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = seconds % 60;
    
    if (hours > 0) return `${hours}h ${minutes}m ${secs}s`;
    if (minutes > 0) return `${minutes}m ${secs}s`;
    return `${secs}s`;
}

// =============================================================================
// 📡 API ENDPOINTS
// =============================================================================

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Get all account states
app.get('/api/states', (req, res) => {
    const states = Array.from(accountStates.values());
    res.json({ accounts: states });
});

// Get specific account state
app.get('/api/state/:accountId', (req, res) => {
    const { accountId } = req.params;
    const state = getAccountState(accountId);
    res.json(state);
});

// Update account status with detailed info
app.post('/api/state/:accountId/status', (req, res) => {
    const { accountId } = req.params;
    const { status, raidType, wave } = req.body;
    
    if (!status) {
        return res.status(400).json({ error: 'Status is required' });
    }
    
    const updates = { status };
    if (raidType) updates.raidType = raidType;
    if (wave) updates.currentWave = wave;
    
    const state = updateAccountState(accountId, updates);
    console.log(`[Status Update] ${accountId}: ${status}`);
    res.json({ success: true, state });
});

// Update cooldown with timestamp
app.post('/api/state/:accountId/cooldown', (req, res) => {
    const { accountId } = req.params;
    const { raid, seconds } = req.body;
    
    if (!raid || seconds === undefined) {
        return res.status(400).json({ error: 'Raid type and seconds are required' });
    }
    
    const state = getAccountState(accountId);
    const now = new Date();
    
    if (raid === 'raid1') {
        state.cooldown.raid1 = seconds;
        state.cooldown.raid1StartTime = now.toISOString();
    } else if (raid === 'raid2') {
        state.cooldown.raid2 = seconds;
        state.cooldown.raid2StartTime = now.toISOString();
    }
    
    state.lastUpdate = now.toISOString();
    console.log(`[Cooldown Update] ${accountId} ${raid}: ${seconds}s`);
    res.json({ success: true, state });
});

// Get cooldown status
app.get('/api/state/:accountId/cooldown/:raid', (req, res) => {
    const { accountId, raid } = req.params;
    const state = getAccountState(accountId);
    
    let cooldown = 0;
    if (raid === 'raid1') {
        cooldown = state.cooldown.raid1;
    } else if (raid === 'raid2') {
        cooldown = state.cooldown.raid2;
    }
    
    res.json({ 
        raid, 
        cooldown, 
        formatted: formatCooldown(cooldown),
        ready: cooldown <= 0
    });
});

// Fire raid command
app.post('/api/raid/:raid', (req, res) => {
    const { raid } = req.params;
    const { accountId } = req.body;
    
    if (!accountId) {
        return res.status(400).json({ error: 'AccountId is required' });
    }
    
    if (raid !== 'raid1' && raid !== 'raid2') {
        return res.status(400).json({ error: 'Invalid raid type' });
    }
    
    const state = getAccountState(accountId);
    
    // Check cooldown
    const cooldown = raid === 'raid1' ? state.cooldown.raid1 : state.cooldown.raid2;
    if (cooldown > 0) {
        return res.json({ 
            success: false, 
            message: 'Cooldown active', 
            cooldown,
            formatted: formatCooldown(cooldown)
        });
    }
    
    // Update status
    const newStatus = raid === 'raid1' ? 'raid1' : 'raid2';
    updateAccountState(accountId, { status: newStatus });
    
    // In real implementation, this would send command to the game client
    console.log(`[Raid Command] Account ${accountId} firing ${raid}`);
    
    res.json({ 
        success: true, 
        raid, 
        accountId,
        message: `Firing ${raid} for account ${accountId}`
    });
});

// Check raid cooldown
app.get('/api/raid/:raid/check', (req, res) => {
    const { raid } = req.params;
    const { accountId } = req.query;
    
    if (!accountId) {
        return res.status(400).json({ error: 'AccountId is required' });
    }
    
    const state = getAccountState(accountId);
    let cooldown = 0;
    
    if (raid === 'raid1') {
        cooldown = state.cooldown.raid1;
    } else if (raid === 'raid2') {
        cooldown = state.cooldown.raid2;
    }
    
    res.json({ 
        raid, 
        accountId,
        cooldown, 
        formatted: formatCooldown(cooldown),
        ready: cooldown <= 0
    });
});

// Server hop command
app.post('/api/server/hop', (req, res) => {
    const { accountId, jobId } = req.body;
    
    if (!accountId) {
        return res.status(400).json({ error: 'AccountId is required' });
    }
    
    const state = getAccountState(accountId);
    
    if (jobId) {
        // Hop to specific server
        updateAccountState(accountId, { serverId: jobId });
        console.log(`[Server Hop] Account ${accountId} hopping to server ${jobId}`);
    } else {
        // Auto hop to least populated server
        console.log(`[Server Hop] Account ${accountId} auto hopping`);
    }
    
    res.json({ 
        success: true, 
        accountId,
        jobId: jobId || 'auto',
        message: 'Server hop command sent'
    });
});

// Stop script command
app.post('/api/script/stop', (req, res) => {
    const { accountId } = req.body;
    
    if (!accountId) {
        return res.status(400).json({ error: 'AccountId is required' });
    }
    
    updateAccountState(accountId, { status: 'idle' });
    console.log(`[Script Control] Account ${accountId} script stopped`);
    
    res.json({ 
        success: true, 
        accountId,
        message: 'Script stopped'
    });
});

// Update pullup status
app.post('/api/pullup/status', (req, res) => {
    const { accountId, isOnPullup } = req.body;
    
    if (!accountId) {
        return res.status(400).json({ error: 'AccountId is required' });
    }
    
    const state = getAccountState(accountId);
    
    if (isOnPullup) {
        state.isOnPullup = true;
        state.lastPullupTime = new Date().toISOString();
        state.status = 'on_pullup';
    } else {
        state.isOnPullup = false;
    }
    
    state.lastUpdate = new Date().toISOString();
    
    res.json({ success: true, state });
});

// Update combat status
app.post('/api/combat/status', (req, res) => {
    const { accountId, isInCombat } = req.body;
    
    if (!accountId) {
        return res.status(400).json({ error: 'AccountId is required' });
    }
    
    const state = getAccountState(accountId);
    state.isInCombat = isInCombat;
    state.lastUpdate = new Date().toISOString();
    
    res.json({ success: true, state });
});

// Update vest status
app.post('/api/vest/status', (req, res) => {
    const { accountId, vestOwned } = req.body;
    
    if (!accountId) {
        return res.status(400).json({ error: 'AccountId is required' });
    }
    
    const state = getAccountState(accountId);
    state.vestOwned = vestOwned;
    state.lastUpdate = new Date().toISOString();
    
    res.json({ success: true, state });
});

// Update automacro status
app.post('/api/automacro/status', (req, res) => {
    const { accountId, enabled } = req.body;
    
    if (!accountId) {
        return res.status(400).json({ error: 'AccountId is required' });
    }
    
    const state = getAccountState(accountId);
    state.autoMacroEnabled = enabled;
    state.lastUpdate = new Date().toISOString();
    
    res.json({ success: true, state });
});

// =============================================================================
// ⏱️ AUTOMATIC COOLDOWN COUNTDOWN
// =============================================================================

// Update cooldowns every second
setInterval(() => {
    const now = new Date();
    
    for (const [accountId, state] of accountStates.entries()) {
        let updated = false;
        
        // Update Raid1 cooldown
        if (state.cooldown.raid1 > 0 && state.cooldown.raid1StartTime) {
            const elapsed = Math.floor((now - new Date(state.cooldown.raid1StartTime)) / 1000);
            const remaining = Math.max(0, state.cooldown.raid1 - elapsed);
            
            if (remaining !== state.cooldown.raid1) {
                state.cooldown.raid1 = remaining;
                updated = true;
                
                if (remaining === 0) {
                    console.log(`[Cooldown Ready] ${accountId} Raid1 cooldown finished!`);
                    // Update status to indicate ready
                    if (state.status === 'waiting_cooldown') {
                        state.status = 'idle';
                    }
                }
            }
        }
        
        // Update Raid2 cooldown
        if (state.cooldown.raid2 > 0 && state.cooldown.raid2StartTime) {
            const elapsed = Math.floor((now - new Date(state.cooldown.raid2StartTime)) / 1000);
            const remaining = Math.max(0, state.cooldown.raid2 - elapsed);
            
            if (remaining !== state.cooldown.raid2) {
                state.cooldown.raid2 = remaining;
                updated = true;
                
                if (remaining === 0) {
                    console.log(`[Cooldown Ready] ${accountId} Raid2 cooldown finished!`);
                    if (state.status === 'waiting_cooldown') {
                        state.status = 'idle';
                    }
                }
            }
        }
        
        if (updated) {
            state.lastUpdate = now.toISOString();
        }
    }
}, 1000);

// =============================================================================
// 🎮 DASHBOARD UI
// =============================================================================

app.get('/', (req, res) => {
    res.send(`
<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OKUPDATERAID - Railway Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            color: #eee;
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        
        h1 {
            text-align: center;
            margin-bottom: 30px;
            color: #00d9ff;
            text-shadow: 0 0 10px rgba(0, 217, 255, 0.5);
        }
        
        .account-card {
            background: rgba(255, 255, 255, 0.1);
            border-radius: 15px;
            padding: 20px;
            margin-bottom: 20px;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.1);
        }
        
        .account-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 15px;
        }
        
        .account-id {
            font-size: 1.2em;
            font-weight: bold;
            color: #00d9ff;
        }
        
        .status-badge {
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.9em;
            font-weight: bold;
        }
        
        .status-idle { background: #6c757d; }
        .status-padding { background: #ffc107; color: #000; }
        .status-buying_vest { background: #17a2b8; }
        .status-on_pullup { background: #28a745; }
        .status-raid1 { background: #dc3545; }
        .status-raid2 { background: #6610f2; }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 15px;
        }
        
        .stat-item {
            background: rgba(0, 0, 0, 0.2);
            padding: 10px;
            border-radius: 8px;
        }
        
        .stat-label {
            font-size: 0.8em;
            color: #aaa;
            margin-bottom: 5px;
        }
        
        .stat-value {
            font-size: 1.1em;
            font-weight: bold;
        }
        
        .cooldown-ready { color: #28a745; }
        .cooldown-active { color: #ffc107; }
        
        .button-group {
            display: flex;
            gap: 10px;
            flex-wrap: wrap;
        }
        
        .btn {
            padding: 10px 20px;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-weight: bold;
            transition: all 0.3s;
        }
        
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.3);
        }
        
        .btn-primary { background: #00d9ff; color: #000; }
        .btn-success { background: #28a745; color: #fff; }
        .btn-warning { background: #ffc107; color: #000; }
        .btn-danger { background: #dc3545; color: #fff; }
        .btn-info { background: #17a2b8; color: #fff; }
        
        .add-account {
            background: rgba(0, 217, 255, 0.1);
            border: 2px dashed #00d9ff;
            border-radius: 15px;
            padding: 30px;
            text-align: center;
            cursor: pointer;
            margin-bottom: 20px;
            transition: all 0.3s;
        }
        
        .add-account:hover {
            background: rgba(0, 217, 255, 0.2);
        }
        
        .add-account h2 {
            color: #00d9ff;
            margin-bottom: 10px;
        }
        
        .add-account p {
            color: #aaa;
        }
        
        .refresh-btn {
            position: fixed;
            bottom: 20px;
            right: 20px;
            width: 60px;
            height: 60px;
            border-radius: 50%;
            background: #00d9ff;
            color: #000;
            border: none;
            cursor: pointer;
            font-size: 24px;
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.3);
            transition: all 0.3s;
        }
        
        .refresh-btn:hover {
            transform: rotate(180deg);
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🧠 OKUPDATERAID RAID CONTROL</h1>
        
        <div class="add-account" onclick="addAccount()">
            <h2>+ Thêm Account</h2>
            <p>Nhập Account ID để thêm vào hệ thống</p>
        </div>
        
        <div id="accounts-container"></div>
    </div>
    
    <button class="refresh-btn" onclick="loadStates()">🔄</button>
    
    <script>
        let accounts = [];
        
        function loadStates() {
            fetch('/api/states')
                .then(res => res.json())
                .then(data => {
                    accounts = data.accounts;
                    renderAccounts();
                });
        }
        
        function renderAccounts() {
            const container = document.getElementById('accounts-container');
            container.innerHTML = accounts.map(account => \`
                <div class="account-card">
                    <div class="account-header">
                        <span class="account-id">\${account.id}</span>
                        <span class="status-badge status-\${account.status}">\${account.status.toUpperCase()}</span>
                    </div>
                    
                    <div class="stats-grid">
                        <div class="stat-item">
                            <div class="stat-label">Raid 1 CD</div>
                            <div class="stat-value \${account.cooldown.raid1 > 0 ? 'cooldown-active' : 'cooldown-ready'}">
                                \${formatCooldown(account.cooldown.raid1)}
                            </div>
                        </div>
                        <div class="stat-item">
                            <div class="stat-label">Raid 2 CD</div>
                            <div class="stat-value \${account.cooldown.raid2 > 0 ? 'cooldown-active' : 'cooldown-ready'}">
                                \${formatCooldown(account.cooldown.raid2)}
                            </div>
                        </div>
                        <div class="stat-item">
                            <div class="stat-label">Combat</div>
                            <div class="stat-value">\${account.isInCombat ? '⚔️ YES' : '✅ NO'}</div>
                        </div>
                        <div class="stat-item">
                            <div class="stat-label">Pullup</div>
                            <div class="stat-value">\${account.isOnPullup ? '💪 YES' : '❌ NO'}</div>
                        </div>
                        <div class="stat-item">
                            <div class="stat-label">Vest</div>
                            <div class="stat-value">\${account.vestOwned ? '✅ YES' : '❌ NO'}</div>
                        </div>
                        <div class="stat-item">
                            <div class="stat-label">AutoMacro</div>
                            <div class="stat-value">\${account.autoMacroEnabled ? '✅ ON' : '❌ OFF'}</div>
                        </div>
                    </div>
                    
                    <div class="button-group">
                        <button class="btn btn-primary" onclick="fireRaid('\${account.id}', 'raid1')">🔥 Raid 1</button>
                        <button class="btn btn-primary" onclick="fireRaid('\${account.id}', 'raid2')">🔥 Raid 2</button>
                        <button class="btn btn-info" onclick="checkCooldown('\${account.id}', 'raid1')">Check Raid 1</button>
                        <button class="btn btn-info" onclick="checkCooldown('\${account.id}', 'raid2')">Check Raid 2</button>
                        <button class="btn btn-warning" onclick="hopServer('\${account.id}')">🔄 Hop Server</button>
                        <button class="btn btn-danger" onclick="stopScript('\${account.id}')">⏹️ Stop</button>
                    </div>
                </div>
            \`).join('');
        }
        
        function formatCooldown(seconds) {
            if (seconds <= 0) return 'READY';
            const hours = Math.floor(seconds / 3600);
            const minutes = Math.floor((seconds % 3600) / 60);
            const secs = seconds % 60;
            
            if (hours > 0) return \`\${hours}h \${minutes}m \${secs}s\`;
            if (minutes > 0) return \`\${minutes}m \${secs}s\`;
            return \`\${secs}s\`;
        }
        
        function addAccount() {
            const accountId = prompt('Nhập Account ID:');
            if (accountId) {
                fetch('/api/state/' + accountId, { method: 'POST' })
                    .then(() => loadStates());
            }
        }
        
        function fireRaid(accountId, raid) {
            fetch('/api/raid/' + raid, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ accountId })
            })
            .then(res => res.json())
            .then(data => {
                alert(data.message);
                loadStates();
            });
        }
        
        function checkCooldown(accountId, raid) {
            fetch('/api/raid/' + raid + '/check?accountId=' + accountId)
                .then(res => res.json())
                .then(data => {
                    alert(\`\${raid.toUpperCase()} Cooldown: \${data.formatted}\`);
                });
        }
        
        function hopServer(accountId) {
            const jobId = prompt('Nhập JobID (để trống để auto hop):');
            fetch('/api/server/hop', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ accountId, jobId: jobId || null })
            })
            .then(res => res.json())
            .then(data => {
                alert(data.message);
            });
        }
        
        function stopScript(accountId) {
            if (confirm('Dừng script cho account ' + accountId + '?')) {
                fetch('/api/script/stop', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ accountId })
                })
                .then(res => res.json())
                .then(data => {
                    alert(data.message);
                    loadStates();
                });
            }
        }
        
        // Auto refresh every 5 seconds
        setInterval(loadStates, 5000);
        
        // Initial load
        loadStates();
    </script>
</body>
</html>
    `);
});

// =============================================================================
// 🚀 START SERVER
// =============================================================================

app.listen(PORT, () => {
    console.log(`🧠 Railway Server running on port ${PORT}`);
    console.log(`📊 Dashboard: http://localhost:${PORT}`);
    console.log(`🔌 API Endpoints:`);
    console.log(`   GET  /api/states - Get all account states`);
    console.log(`   GET  /api/state/:id - Get specific account state`);
    console.log(`   POST /api/state/:id/status - Update account status`);
    console.log(`   POST /api/state/:id/cooldown - Update cooldown`);
    console.log(`   GET  /api/state/:id/cooldown/:raid - Get cooldown status`);
    console.log(`   POST /api/raid/:raid - Fire raid command`);
    console.log(`   GET  /api/raid/:raid/check - Check raid cooldown`);
    console.log(`   POST /api/server/hop - Server hop command`);
    console.log(`   POST /api/script/stop - Stop script command`);
    console.log(`   POST /api/pullup/status - Update pullup status`);
    console.log(`   POST /api/combat/status - Update combat status`);
    console.log(`   POST /api/vest/status - Update vest status`);
    console.log(`   POST /api/automacro/status - Update automacro status`);
});
