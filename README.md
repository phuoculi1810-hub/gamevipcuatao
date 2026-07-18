# OKUPDATERAID - Auto Raid System

## 📁 Project Structure

```
d:\OKUPDATERAID\
├── scripts/              # Lua scripts
│   ├── raid1.lua        # Raid 1 automation script
│   └── raid2.lua        # Raid 2 automation script
├── utils/               # Utility scripts
│   ├── disable_lockon.lua   # Disable mobile lock-on
│   ├── buy_vest.lua        # Auto buy 80KG vest
│   └── click_pullup.lua    # Click nearest pullup machine
├── logic.txt            # Logic documentation
├── Loader.lua           # CORE BRAIN - Main automation script
├── server.js            # Railway server
├── package.json         # Node.js dependencies
├── .gitignore           # Git ignore rules
├── README.md            # This file
├── DEPLOYMENT.md        # Deployment guide
└── GIT_GUIDE.md         # Git guide
```

## 🧠 Main Workflow (logic.txt)

### CORE (Loader.lua)
1. **Initial Setup**
   - Đợi localplayer load và game load xong
   - Click Play Now
   - Nhích mất safezone
   - Tắt lockon

2. **Pullup Check**
   - Kiểm tra 2 vị trí pullup có người đang tập không
   - Nếu có → hop server ít người
   - Nếu không → tiếp tục

3. **Vest Check**
   - Kiểm tra inventory có 80KG Vest không
   - Nếu không → padding đến shop mua vest
   - Nếu có → tiếp tục

4. **Pullup Setup**
   - Padding đến vị trí pullup trống
   - Kiểm tra AutoMacro (true/false)
   - Nếu false → fire AutoMacro rồi làm bước trên
   - Equip 80KG vest
   - Click máy pullup gần nhất

5. **Raid Fire**
   - Check Railway API xem raid1/raid2 cooldown xong chưa
   - Nếu cooldown xong → fire raid event (Create rồi Start)
   - Nếu còn cooldown → gửi lên Railway đợi
   - Load raid script từ GitHub

### Defense Logic
- Trong lúc padding nếu bị incombat → đợi hết rồi hop server
- Quá 30s không trên máy pullup → hop server
- Nếu có người cướm máy pullup → hop server

## 🛡️ Defense Mechanisms

- **Combat Detection**: If attacked during padding → stop, wait for combat end, then hop server
- **Machine Theft**: If someone steals pullup machine → hop server (wait for combat end first if in combat)
- **30s Timeout**: If not on pullup for 30s → hop server (wait for combat end first if in combat)
- **Anti-Fly Padding**: Prevent being launched into the air when hitting obstacles

## 🏃 Padding Logic (from AutoFarmStrength_v8_new_update.lua)

- Uses PathfindingService for route calculation
- Enable Run when starting movement, disable when within 50 studs of target
- Auto-unequip tools if equipped during padding
- Check combat/kick every frame → stop and hop if detected
- Dodge blocking players using raycast (DETECT_DISTANCE = 6 studs)
- Anti-stuck: jump if not moving for 1.5s
- Returns: true = arrived safely, false = stopped (combat/kick)

## 📊 Railway Dashboard

Railway acts as the brain and can:
- View all account states
- Auto hop server button
- Hop server by JobID button
- Stop script state button (fire server, etc.)
- Fire raid1 button with cooldown check
- Fire raid2 button with cooldown check

## 🎯 Architecture

- **Railway**: Brain/controller - lưu trạng thái và cooldown
- **Loader.lua**: CORE BRAIN - xử lý toàn bộ flow từ load game đến raid
- **Raid scripts**: raid1.lua, raid2.lua - chạy riêng khi vào raid

## 📝 Script Descriptions

### Loader.lua (CORE BRAIN)
Main automation script that:
- Đợi localplayer load và game load xong
- Click Play Now
- Nhích mất safezone
- Tắt lock-on
- Kiểm tra 2 vị trí pullup có người không
- Kiểm tra và mua 80KG Vest nếu cần
- Padding đến vị trí pullup trống
- Kiểm tra và bật AutoMacro
- Equip vest và click máy pullup
- Check Railway API cho raid cooldown
- Fire raid events (Create rồi Start)
- Load raid scripts từ GitHub
- Defense logic (combat, theft, timeout)

### scripts/raid1.lua
Raid 1 automation:
- Cooldown management
- Auto-equip combat
- Auto-attack during waves
- Wave detection and handling
- Boss defeat detection

### scripts/raid2.lua
Raid 2 automation (VIP):
- Door breaking sequence (Door1, Door2)
- Pathfinding to doors
- Boss room entry
- Advanced combat logic

### utils/disable_lockon.lua
Disables mobile lock-on using multiple methods

### utils/buy_vest.lua
Auto-buys 80KG vest when near shop

### utils/click_pullup.lua
Finds and clicks nearest pullup machine

## 🔧 Configuration

Edit the following in Loader.lua:
- `RAILWAY_URL = "http://localhost:3000"` - Railway server URL
- `AGENT_RADIUS = 3.0` - Pathfinding agent radius
- Pullup coordinates (PULLUP_1, PULLUP_2)
- Shop vest coordinates (SHOP_VEST)
- `PULLUP_TIMEOUT = 30` - Pullup timeout in seconds

## 🚀 Usage

### Railway Deployment

1. **Deploy Railway Server:**
   ```bash
   # Install dependencies
   npm install
   
   # Start locally for testing
   npm start
   
   # Or deploy to Railway
   railway up
   ```

2. **Configure Scripts:**
   - Update `RAILWAY_URL` in all Lua scripts (main.lua, raid1.lua, raid2.lua)
   - Replace `http://localhost:3000` with your Railway URL
   - Example: `https://your-app.railway.app`

3. **Run Game Scripts:**
   - Run Loader.lua to start the automation
   - Script will automatically:
     - Wait for game load
     - Exit safe zone
     - Disable lock-on
     - Check and buy vest if needed
     - Find and use pullup machine
     - Fire raids when ready
     - Send status updates to Railway

4. **Monitor via Railway Dashboard:**
   - Access dashboard at your Railway URL
   - View all account states
   - Control raids, server hops, and script execution
   - Monitor cooldowns and combat status

### Railway API Endpoints

- `GET /api/states` - Get all account states
- `GET /api/state/:id` - Get specific account state
- `POST /api/state/:id/status` - Update account status
- `POST /api/state/:id/cooldown` - Update cooldown
- `GET /api/state/:id/cooldown/:raid` - Get cooldown status
- `POST /api/raid/:raid` - Fire raid command
- `GET /api/raid/:raid/check` - Check raid cooldown
- `POST /api/server/hop` - Server hop command
- `POST /api/script/stop` - Stop script command
- `POST /api/pullup/status` - Update pullup status
- `POST /api/combat/status` - Update combat status
- `POST /api/vest/status` - Update vest status
- `POST /api/automacro/status` - Update automacro status

## ⚠️ Notes

- All scripts use error handling (pcall) for robustness
- Combat detection is integrated throughout
- Server hopping is automatic when issues detected
- Cooldown is managed locally (no external server dependency)
- Raid scripts handle both cooldown checking and actual raid execution
