# OKUPDATERAID - Auto Raid System

## 📁 Project Structure

```
d:\OKUPDATERAID\
├── scripts/              # Main automation scripts
│   ├── main.lua         # Main brain script - controls entire workflow
│   ├── pullup_check.lua # Pullup status monitor with 60s timeout
│   ├── raid1.lua        # Raid 1 automation script
│   └── raid2.lua        # Raid 2 automation script
├── utils/               # Utility scripts
│   ├── disable_lockon.lua   # Disable mobile lock-on
│   ├── buy_vest.lua        # Auto buy 80KG vest
│   └── click_pullup.lua    # Click nearest pullup machine
├── logic.txt            # Logic documentation
├── Loader.lua           # Game loader script
├── server.js            # Railway server
├── package.json         # Node.js dependencies
├── .gitignore           # Git ignore rules
├── README.md            # This file
├── DEPLOYMENT.md        # Deployment guide
└── GIT_GUIDE.md         # Git guide
```

## 🧠 Main Workflow (logic.txt)

### 1. Initial Setup
- Load script and wait for GameLoad
- Move 2-3 studs to exit safe zone (no MoveTo)
- Disable lock-on (scriptclicklockonmobile.lua)

### 2. Pullup Position Check
- Check if players are near pullup positions (10 studs radius)
  - Pullup 1: -2066.056152, 8.374999, -1719.620483
  - Pullup 2: -2053.761963, 8.374999, -1718.615112
- If players present → hop server (least populated)

### 3. Vest Check & Purchase
- Check inventory for "80KG Vest"
- If not present:
  - Pad to shop vest: -2069.079346, 8.374999, -1667.621826
  - Buy 80KG Vest (mua_vest.txt)

### 4. Pullup Machine
- Pad to pullup position
- Check if machine is free (no players)
- Use check_automacro_true_false.txt
  - If false → fire remote event to enable AutoMacro
  - Fire once and recheck
  - If true → OK, if false → hop server
- Equip 80KG Vest
- Click nearest pullup machine

### 5. Raid System
- Fire remote raid 1
  - If teleport message → OK
  - If cooldown message → save to Railway, wait, then retry
  - If entered raid → switch to raid state
  - When teleporting to raid 1 → wait for load, then run raid1 script
- Fire remote raid 2
  - Same logic as raid 1
  - When teleporting to raid 2 → wait for load, then run raid2 script

## 🛡️ Defense Mechanisms

- **Combat Detection**: If attacked during padding → stop, wait for combat end, then hop server
- **Machine Theft**: If someone steals pullup machine → hop server (wait for combat end first if in combat)
- **60s Timeout**: If not on pullup for 60s → hop server (wait for combat end first if in combat)
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

- **Railway**: Brain/controller
- **Main script**: Handles player, vest, padding, and defense during pullup
- **Raid logic**: Runs separately when entering raid, controlled by the brain

## 📝 Script Descriptions

### scripts/main.lua
Main brain script that:
- Waits for game load
- Exits safe zone
- Disables lock-on
- Checks pullup positions
- Manages vest purchase
- Handles pullup machine interaction
- Controls raid firing

### scripts/pullup_check.lua
Monitors pullup status with:
- 60s timeout if not on pullup
- Combat detection before hopping
- Automatic server hop on timeout

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

Edit the following in scripts/main.lua:
- `AGENT_RADIUS = 3.0` - Pathfinding agent radius
- `DETECT_DISTANCE = 6` - Raycast detection distance
- `STEER_OFFSET = 4` - Steering offset for dodging players
- Pullup coordinates (PULLUP_1, PULLUP_2)
- Shop vest coordinates (SHOP_VEST)

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
