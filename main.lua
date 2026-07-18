-- =============================================================================
-- RAID2 AUTO BOT — Main Game Script
-- Deploy: push folder deploy/ lên GitHub → Railway chạy server.js
-- Game: load script này trong executor, sửa SERVER_URL trỏ tới Railway
-- =============================================================================

-- ⚙️ CẤU HÌNH — SỬA TRƯỚC KHI CHẠY
local CONFIG = {
    SERVER_URL  = "https://gamevipcuatao-production.up.railway.app",  -- URL Railway sau deploy
    API_KEY     = "",                                  -- trùng env API_KEY trên Railway (để trống nếu không dùng)
    SYNC_INTERVAL = 8,                                 -- giây — gửi status lên server

    -- Tọa độ
    SHOP_VEST     = Vector3.new(-2069.079346, 8.374999, -1667.621826),
    PULLUP_SPOTS  = {
        Vector3.new(-2066.056152, 8.374999, -1719.620483),  -- PULL UP 1
        Vector3.new(-2053.761963, 8.374999, -1718.615112),  -- PULL UP 2
    },
    PULLUP_AREA   = Vector3.new(-2060.0, 8.374999, -1719.0), -- điểm padding tới khu pullup

    CHECK_RADIUS  = 10,   -- studs — check người ở pullup
    VEST_NAME     = "80KG Vest",
    MACRO_RETRIES = 3,
}

-- =============================================================================
-- SERVICES
-- =============================================================================
local Players            = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local TeleportService    = game:GetService("TeleportService")
local HttpService        = game:GetService("HttpService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local VirtualUser        = game:GetService("VirtualUser")
local RunService         = game:GetService("RunService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- =============================================================================
-- STATE
-- =============================================================================
local STATE = {
    accountId      = nil,
    current        = "INIT",
    detail         = "",
    stopped        = false,
    isPathfinding  = false,
    stopPath       = false,
    macroOn        = false,
    onPullup       = false,
    isTeleporting  = false,
    raid1CD        = 0,
    raid2CD        = 0,
    raid1CDUpdated = 0,
    raid2CDUpdated = 0,
    jobId          = game.JobId,
}

local AGENT_RADIUS    = 3.0
local DETECT_DISTANCE = 6
local STEER_OFFSET    = 4

local character, humanoid, rootPart

local function refreshCharacter()
    character = player.Character or player.CharacterAdded:Wait()
    humanoid  = character:WaitForChild("Humanoid")
    rootPart  = character:WaitForChild("HumanoidRootPart")
end

refreshCharacter()
player.CharacterAdded:Connect(function()
    task.wait(0.5)
    refreshCharacter()
end)

-- =============================================================================
-- LOG
-- =============================================================================
local function log(msg)
    print("[Raid2Bot][" .. STATE.current .. "] " .. tostring(msg))
end

local function setState(name, detail)
    STATE.current = name
    STATE.detail  = detail or ""
    log(detail or name)
    pushStatus()
end

-- =============================================================================
-- HTTP — sync Railway (hỗ trợ nhiều executor)
-- =============================================================================
local function httpRequest(opts)
    opts = opts or {}
    local url     = opts.Url or opts.url
    local method  = string.upper(opts.Method or opts.method or "GET")
    local headers = opts.Headers or opts.headers or {}
    local body    = opts.Body or opts.body

    if CONFIG.API_KEY ~= "" then
        headers["X-Api-Key"] = CONFIG.API_KEY
    end
    headers["Content-Type"] = headers["Content-Type"] or "application/json"

    -- syn.request (Synapse / most executors)
    if syn and syn.request then
        local ok, res = pcall(syn.request, {
            Url     = url,
            Method  = method,
            Headers = headers,
            Body    = body,
        })
        if ok and res then
            return res.StatusCode or res.status, res.Body or res.body or ""
        end
    end

    -- request() global
    if request then
        local ok, res = pcall(request, {
            Url     = url,
            Method  = method,
            Headers = headers,
            Body    = body,
        })
        if ok and res then
            return res.StatusCode or 200, res.Body or ""
        end
    end

    -- HttpService fallback (Roblox built-in — cần HttpEnabled)
    local ok, result = pcall(function()
        if method == "GET" then
            return HttpService:GetAsync(url, true)
        else
            return HttpService:PostAsync(url, body or "{}", Enum.HttpContentType.ApplicationJson, true)
        end
    end)
    if ok then return 200, result end
    return 0, ""
end

local function postJson(path, data)
    local url = CONFIG.SERVER_URL .. path
    local body = HttpService:JSONEncode(data)
    local code, resBody = httpRequest({ Url = url, Method = "POST", Body = body })
    if code >= 200 and code < 300 and resBody ~= "" then
        local ok, parsed = pcall(function() return HttpService:JSONDecode(resBody) end)
        if ok then return parsed end
    end
    return nil
end

function pushStatus()
    if CONFIG.SERVER_URL:find("YOUR-APP") then return end
    task.spawn(function()
        local data = {
            accountId     = STATE.accountId,
            state         = STATE.current,
            detail        = STATE.detail,
            jobId         = STATE.jobId,
            raid1Cooldown = getRemainingCD("raid1"),
            raid2Cooldown = getRemainingCD("raid2"),
            inCombat      = isInCombat(),
            macroOn       = STATE.macroOn,
            hasVest       = hasItemInInventory(CONFIG.VEST_NAME),
            onPullup      = STATE.onPullup,
        }
        local res = postJson("/api/status", data)
        if res then
            if res.stopped then STATE.stopped = true end
            if res.command then handleCommand(res.command) end
        end
    end)
end

local function registerAccount()
    if CONFIG.SERVER_URL:find("YOUR-APP") then
        log("⚠️ Chưa cấu hình SERVER_URL — bỏ qua Railway sync")
        return
    end
    local res = postJson("/api/register", {
        username  = player.Name,
        jobId     = STATE.jobId,
        accountId = STATE.accountId,
    })
    if res and res.accountId then
        STATE.accountId = res.accountId
        STATE.stopped   = res.stopped or false
        log("✅ Đăng ký Railway: " .. STATE.accountId)
    end
end

-- =============================================================================
-- COMMANDS từ Dashboard
-- =============================================================================
function handleCommand(cmd)
    if not cmd or not cmd.type then return end
    log("📩 Lệnh từ dashboard: " .. cmd.type)

    if cmd.type == "STOP" then
        STATE.stopped = true
        setState("STOPPED", "Dừng bởi dashboard")
    elseif cmd.type == "RESUME" then
        STATE.stopped = false
        setState("RESUMING", "Tiếp tục bởi dashboard")
    elseif cmd.type == "HOP_SERVER" then
        task.spawn(hopServer)
    elseif cmd.type == "HOP_JOB" and cmd.jobId then
        task.spawn(function() hopToJobId(cmd.jobId) end)
    elseif cmd.type == "FIRE_RAID1" then
        task.spawn(function() fireRaid("Raid1") end)
    elseif cmd.type == "FIRE_RAID2" then
        task.spawn(function() fireRaid("Raid2") end)
    elseif cmd.type == "CHECK_COOLDOWN" then
        task.spawn(function()
            fireRaid("Raid1")
            task.wait(2)
            fireRaid("Raid2")
        end)
    end
end

-- Poll commands định kỳ
task.spawn(function()
    while task.wait(CONFIG.SYNC_INTERVAL) do
        registerAccount()
        pushStatus()
        if STATE.accountId and not CONFIG.SERVER_URL:find("YOUR-APP") then
            local url = CONFIG.SERVER_URL .. "/api/commands/" .. STATE.accountId
            local code, body = httpRequest({ Url = url, Method = "GET" })
            if code == 200 and body ~= "" then
                local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
                if ok and data.command then handleCommand(data.command) end
                if ok and data.stopped then STATE.stopped = data.stopped end
            end
        end
    end
end)

-- =============================================================================
-- UTILITIES
-- =============================================================================
function isInCombat()
    return player:GetAttribute("InCombat") == true
end

local function waitForCombatEnd()
    while isInCombat() do task.wait(0.5) end
end

function hasItemInInventory(name)
    local bp = player:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and t.Name == name then return true end
        end
    end
    local char = player.Character
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") and t.Name == name then return true end
        end
    end
    return false
end

local function equipToolByName(name)
    local bp = player:FindFirstChild("Backpack")
    if not bp then return false end
    for _, t in ipairs(bp:GetChildren()) do
        if t:IsA("Tool") and t.Name == name then
            humanoid:EquipTool(t)
            return true
        end
    end
    return false
end

function getRemainingCD(which)
    local cd, updated
    if which == "raid1" then
        cd, updated = STATE.raid1CD, STATE.raid1CDUpdated
    else
        cd, updated = STATE.raid2CD, STATE.raid2CDUpdated
    end
    if cd <= 0 then return 0 end
    local elapsed = os.time() - updated
    local rem = cd - elapsed
    return rem > 0 and rem or 0
end

local function setCooldown(which, seconds)
    if which == "raid1" then
        STATE.raid1CD = seconds + 15
        STATE.raid1CDUpdated = os.time()
    else
        STATE.raid2CD = seconds + 15
        STATE.raid2CDUpdated = os.time()
    end
    pushStatus()
end

-- =============================================================================
-- CLICK PLAY (Loader logic)
-- =============================================================================
local function clickPlayNow()
    local VIM = game:GetService("VirtualInputManager")

    local function isOnScreen(g)
        if not g.Visible then return false end
        if g.AbsoluteSize.X <= 0 then return false end
        return true
    end

    local function clickBtn(g)
        local cx = g.AbsolutePosition.X + g.AbsoluteSize.X / 2
        local cy = g.AbsolutePosition.Y + g.AbsoluteSize.Y / 2
        pcall(function()
            VIM:SendMouseButtonEvent(cx, cy, 0, true, game, 0)
            task.wait(0.08)
            VIM:SendMouseButtonEvent(cx, cy, 0, false, game, 0)
        end)
        pcall(function() firesignal(g.MouseButton1Click) end)
        pcall(function() g:Activate() end)
    end

    for _ = 1, 60 do
        for _, g in ipairs(playerGui:GetDescendants()) do
            if (g:IsA("TextButton") or g:IsA("ImageButton"))
            and g.Name:lower() == "play" and isOnScreen(g) then
                clickBtn(g)
                log("✅ Clicked Play")
                return true
            end
        end
        task.wait(0.5)
    end
    return false
end

-- =============================================================================
-- SAFE ZONE — nhích bằng Move, không MoveTo
-- =============================================================================
local function leaveSafeZone()
    setState("SAFEZONE", "Nhích khỏi safe zone")
    refreshCharacter()
    local fwd = rootPart.CFrame.LookVector
    humanoid:Move(fwd, true);  task.wait(0.6)
    humanoid:Move(-fwd, true); task.wait(0.6)
    humanoid:Move(fwd * 0.5, true); task.wait(0.4)
    humanoid:Move(Vector3.zero, true)
    log("✅ Thoát safezone")
end

-- =============================================================================
-- LOCK ON OFF
-- =============================================================================
local function disableLockOn()
    local mobileGui = playerGui:FindFirstChild("Mobile")
    local btns = mobileGui and mobileGui:FindFirstChild("MobileButtons")
    local shiftLock = btns and btns:FindFirstChild("ShiftLock")
    if shiftLock then
        pcall(function() shiftLock:Activate() end)
        task.wait(0.2)
        pcall(function() firesignal(shiftLock.MouseButton1Click) end)
        log("✅ Tắt LockOn")
    end
end

-- =============================================================================
-- SERVER HOP
-- =============================================================================
function hopServer()
    setState("HOPPING", "Tìm server ít người nhất")
    local placeId = game.PlaceId
    local currentId = game.JobId

    local ok, result = pcall(function()
        return game:HttpGet(
            "https://games.roblox.com/v1/games/" .. placeId ..
            "/servers/Public?sortOrder=Asc&limit=25"
        )
    end)

    if ok then
        local data = HttpService:JSONDecode(result)
        if data and data.data then
            local best, bestCount = nil, math.huge
            for _, s in ipairs(data.data) do
                if s.id ~= currentId and s.playing < s.maxPlayers and s.playing < bestCount then
                    bestCount = s.playing
                    best = s
                end
            end
            if best then
                log("Hop → " .. best.id .. " (" .. bestCount .. " players)")
                TeleportService:TeleportToPlaceInstance(placeId, best.id, player)
                return
            end
        end
    end

    log("Fallback Teleport thường")
    TeleportService:Teleport(placeId, player)
end

function hopToJobId(jobId)
    setState("HOPPING", "Hop JobId: " .. tostring(jobId))
    TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, player)
end

-- =============================================================================
-- CHECK PLAYER NEAR POSITION
-- =============================================================================
local function isPlayerNear(pos, radius)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hrp and (hrp.Position - pos).Magnitude <= radius then
                return true, p.Name
            end
        end
    end
    return false
end

local function anyPullupSpotOccupied()
    for i, pos in ipairs(CONFIG.PULLUP_SPOTS) do
        local occupied, name = isPlayerNear(pos, CONFIG.CHECK_RADIUS)
        if occupied then
            return true, "Spot" .. i .. " — " .. name
        end
    end
    return false
end

-- =============================================================================
-- RUN REMOTE
-- =============================================================================
local function startRun()
    pcall(function()
        ReplicatedStorage.Events.EventCore:FireServer("Run", "Start", true, 2)
    end)
end

local function stopRun()
    pcall(function()
        ReplicatedStorage.Events.EventCore:FireServer("Run", "Start", false)
    end)
end

-- =============================================================================
-- PADDING (anti-fly cơ bản)
-- =============================================================================
local function checkPlayerBlocking()
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { character }
    local result = workspace:Raycast(rootPart.Position, rootPart.CFrame.LookVector * DETECT_DISTANCE, params)
    if result and result.Instance then
        local model = result.Instance:FindFirstAncestorOfClass("Model")
        if model and model:FindFirstChild("Humanoid") then
            return Players:GetPlayerFromCharacter(model) ~= nil
        end
    end
    return false
end

local function antiFlyCheck()
    -- Nếu Y tăng bất thường hoặc velocity Y cao → zero velocity
    local vel = rootPart.AssemblyLinearVelocity
    if vel.Y > 40 or rootPart.Position.Y > CONFIG.PULLUP_AREA.Y + 25 then
        rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
        rootPart.AssemblyAngularVelocity = Vector3.zero
        humanoid:MoveTo(rootPart.Position)
        log("⚠️ Anti-fly: reset velocity Y")
        return true
    end
    return false
end

local function padTo(targetPos)
    STATE.isPathfinding = true
    STATE.stopPath = false

    local path = PathfindingService:CreatePath({
        AgentRadius = AGENT_RADIUS,
        AgentHeight = 5,
        AgentCanJump = true,
    })

    startRun()
    local ok = pcall(function() path:ComputeAsync(rootPart.Position, targetPos) end)
    if not ok or path.Status ~= Enum.PathStatus.Success then
        stopRun()
        STATE.isPathfinding = false
        return false
    end

    local lastY = rootPart.Position.Y
    for i, wp in ipairs(path:GetWaypoints()) do
        if i == 1 or STATE.stopPath or STATE.stopped then break end

        if isInCombat() then
            setState("INCOMBAT", "Dừng padding — InCombat")
            stopRun()
            humanoid:MoveTo(rootPart.Position)
            STATE.isPathfinding = false
            waitForCombatEnd()
            hopServer()
            return false
        end

        if wp.Action == Enum.PathWaypointAction.Jump then humanoid.Jump = true end

        local wpPos = wp.Position
        local t0 = os.clock()
        while (rootPart.Position - wpPos).Magnitude > 5 do
            if STATE.stopPath or STATE.stopped then break end
            task.wait()

            antiFlyCheck()

            if isInCombat() then
                stopRun()
                humanoid:MoveTo(rootPart.Position)
                STATE.isPathfinding = false
                waitForCombatEnd()
                hopServer()
                return false
            end

            if (rootPart.Position - targetPos).Magnitude <= 50 then stopRun() end

            if checkPlayerBlocking() then
                humanoid:MoveTo(wpPos + rootPart.CFrame.RightVector * STEER_OFFSET)
            else
                humanoid:MoveTo(wpPos)
            end

            if math.abs(rootPart.Position.Y - lastY) > 8 then
                rootPart.AssemblyLinearVelocity = Vector3.zero
                lastY = rootPart.Position.Y
            end

            if os.clock() - t0 > 2 then humanoid.Jump = true; break end
        end
    end

    stopRun()
    humanoid:MoveTo(rootPart.Position)
    STATE.isPathfinding = false
    return not STATE.stopPath
end

-- =============================================================================
-- BUY VEST
-- =============================================================================
local function buyVest80KG()
    setState("BUY_VEST", "Mua 80KG Vest")
    for _ = 1, 10 do
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("ClickDetector") or obj:IsA("ProximityPrompt") then
                local n = string.lower(obj.Parent.Name)
                if n:find("vest") and n:find("80") then
                    local pos = obj.Parent:IsA("BasePart") and obj.Parent.Position
                        or (obj.Parent:FindFirstChildWhichIsA("BasePart") and obj.Parent:FindFirstChildWhichIsA("BasePart").Position)
                    if pos and (rootPart.Position - pos).Magnitude < 25 then
                        if obj:IsA("ClickDetector") then fireclickdetector(obj)
                        else fireproximityprompt(obj) end
                    end
                end
            end
        end
        if hasItemInInventory(CONFIG.VEST_NAME) then
            log("✅ Đã có Vest")
            return true
        end
        task.wait(0.5)
    end
    return hasItemInInventory(CONFIG.VEST_NAME)
end

-- =============================================================================
-- AUTO MACRO
-- =============================================================================
local function isMacroTrue()
    local ok, result = pcall(function()
        local frame = playerGui.AutoMacroV2.Frame:FindFirstChild("Settings")
        local folder = frame and frame:FindFirstChild("MacroBTN", true)
        local btn = folder and folder:FindFirstChild("TextButton")
        return btn and btn.Text == "TRUE"
    end)
    return ok and result
end

local function enableMacro()
    for attempt = 1, CONFIG.MACRO_RETRIES do
        if isMacroTrue() then
            STATE.macroOn = true
            log("✅ AutoMacro TRUE")
            return true
        end
        pcall(function()
            ReplicatedStorage.Events.EventCore:FireServer("AutoMacro")
        end)
        task.wait(0.8)
        if isMacroTrue() then
            STATE.macroOn = true
            return true
        end
        log("Macro attempt " .. attempt .. " — vẫn FALSE")
    end
    STATE.macroOn = false
    return false
end

-- =============================================================================
-- PULLUP — chọn máy trống gần nhất
-- =============================================================================
local function isMachineOccupied(machine)
    local center = machine:FindFirstChild("Center")
    local pos = center and center.Position
        or (machine.PrimaryPart and machine.PrimaryPart.Position)
        or (machine:FindFirstChildWhichIsA("BasePart") and machine:FindFirstChildWhichIsA("BasePart").Position)
    if not pos then return true end
    return isPlayerNear(pos, 6)
end

local function findFreePullupMachine()
    local trainings = workspace:FindFirstChild("Trainings")
    local pullups = trainings and trainings:FindFirstChild("Pull-ups")
    if not pullups then return nil end

    local best, bestD = nil, math.huge
    for _, obj in ipairs(pullups:GetChildren()) do
        if obj:IsA("Model") and obj:FindFirstChild("ClickDetector") and not isMachineOccupied(obj) then
            local center = obj:FindFirstChild("Center")
            local pos = center and center.Position or obj:GetPivot().Position
            local d = (rootPart.Position - pos).Magnitude
            if d < bestD then bestD = d; best = obj end
        end
    end
    return best
end

local function clickPullupAndSelectDurability()
    local machine = findFreePullupMachine()
    if not machine then
        log("⚠️ Không có máy pullup trống")
        return false
    end

    log("Click máy: " .. machine.Name)
    fireclickdetector(machine.ClickDetector)
    task.wait(1.2)

    local ui = playerGui:FindFirstChild("PullupGain")
    if not ui or not ui.Enabled then
        log("⚠️ PullupGain UI không hiện")
        return false
    end

    local frame = ui:FindFirstChild("Frame")
    local durBtn = frame and frame:FindFirstChild("Durability")
    if durBtn then
        pcall(function() firesignal(durBtn.MouseButton1Click) end)
        pcall(function() durBtn:Activate() end)
        if getconnections then
            for _, c in ipairs(getconnections(durBtn.MouseButton1Click)) do
                pcall(function() c:Fire() end)
            end
        end
    end

    task.wait(0.5)
    STATE.onPullup = ui.Enabled
    return STATE.onPullup
end

-- Monitor bị cướp máy
local pullupMonitorConn = nil
local function startPullupMonitor()
    if pullupMonitorConn then pullupMonitorConn:Disconnect() end
    local ui = playerGui:FindFirstChild("PullupGain")
    if not ui then return end

    pullupMonitorConn = ui:GetPropertyChangedSignal("Enabled"):Connect(function()
        if not ui.Enabled and STATE.onPullup then
            STATE.onPullup = false
            log("⚠️ Bị cướp máy / mất PullUp")
            task.spawn(function()
                if isInCombat() then waitForCombatEnd() end
                hopServer()
            end)
        end
    end)
end

-- =============================================================================
-- RAID — fire remote + parse notify
-- =============================================================================
local function parseCooldown(text)
    local h = tonumber(text:match("(%d+) hour")) or 0
    local m = tonumber(text:match("(%d+) minute")) or 0
    local s = tonumber(text:match("(%d+) second")) or 0
    return h * 3600 + m * 60 + s
end

local function stripTags(text)
    text = text:gsub("<Color=[^>]->", ""):gsub("<Color/=?>", "")
    return text
end

local notifyHooked = false
local function hookNotify()
    if notifyHooked then return end
    notifyHooked = true
    pcall(function()
        ReplicatedStorage.NotifyEvent.OnClientEvent:Connect(function(msg)
            if not msg then return end
            local clean = stripTags(msg):lower()

            if clean:find("can't create") or clean:find("can't start") then
                local sec = parseCooldown(clean)
                if clean:find("raid2") or clean:find("raid 2") then
                    setCooldown("raid2", sec)
                else
                    setCooldown("raid1", sec)
                end
                log("Cooldown: " .. sec .. "s")

            elseif clean:find("teleporting to the raid") then
                STATE.isTeleporting = true
                setState("IN_RAID", "Teleporting to raid")

            elseif clean:find("boss has been defeated") then
                setState("RAID_DONE", "Boss defeated")
                STATE.isTeleporting = false

            elseif clean:find("teleporting back") then
                setState("BACK_TO_LOBBY", "Teleporting back")
                STATE.isTeleporting = false
            end
        end)
    end)
end

function fireRaid(raidName)
    hookNotify()
    setState("FIRE_RAID", raidName)
    pcall(function()
        ReplicatedStorage.Events.Party:FireServer("Create", raidName)
    end)
    task.wait(1.5)
    pcall(function()
        ReplicatedStorage.Events.Party:FireServer("Start", raidName)
    end)
end

local function checkIsInRaidPlace()
    return #Players:GetPlayers() <= 1
end

-- Logic raid trong place (gọi khi detect đang ở raid)
local function runRaidLogic(raidName)
    setState("RAIDING", raidName)
    if not player.Character then player.CharacterAdded:Wait() end
    task.wait(2)
    leaveSafeZone()

    -- Equip combat
    local combats = { Brawl=true, Sambo=true, ["Peek-a-Boo"]=true, Hitman=true,
        ["Northern Taekwondo"]=true, NorthernTaekwondo=true, Combat=true }
    local bp = player:WaitForChild("Backpack")
    for _, item in ipairs(bp:GetChildren()) do
        if item:IsA("Tool") and combats[item.Name] then
            humanoid:EquipTool(item)
            break
        end
    end

    -- Auto attack
    local attacking = true
    task.spawn(function()
        while attacking do
            VirtualUser:ClickButton1(Vector2.new())
            task.wait(0.1)
        end
    end)

    -- Chờ boss defeated (NotifyEvent hook sẽ set state)
    local timeout = 600
    local t0 = os.clock()
    while STATE.current ~= "RAID_DONE" and STATE.current ~= "BACK_TO_LOBBY" and (os.clock() - t0) < timeout do
        task.wait(2)
    end
    attacking = false
    log("Raid kết thúc / timeout")
end

-- =============================================================================
-- MAIN FLOW
-- =============================================================================
local function waitForGameLoad()
    while not game:IsLoaded() do task.wait(0.5) end
    while not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") do
        task.wait(0.5)
    end
    task.wait(2)
end

local function mainLoop()
    waitForGameLoad()
    registerAccount()
    hookNotify()
    clickPlayNow()
    task.wait(1)

    -- Nếu đang ở raid place
    if checkIsInRaidPlace() and workspace:FindFirstChild("Hitable") then
        runRaidLogic("Raid2")
        return
    end

    leaveSafeZone()
    task.wait(1)
    disableLockOn()
    task.wait(0.5)

    while true do
        if STATE.stopped then
            setState("STOPPED", "Chờ resume...")
            task.wait(3)
            continue
        end

        -- 1. Check pullup spots occupied
        setState("CHECK_PULLUP", "Kiểm tra người ở pullup")
        local occupied, info = anyPullupSpotOccupied()
        if occupied then
            setState("HOP", "Có người: " .. info)
            if isInCombat() then waitForCombatEnd() end
            hopServer()
            return
        end

        -- 2. Vest
        if not hasItemInInventory(CONFIG.VEST_NAME) then
            setState("GOTO_SHOP", "Padding tới shop vest")
            padTo(CONFIG.SHOP_VEST)
            buyVest80KG()
            if not hasItemInInventory(CONFIG.VEST_NAME) then
                log("⚠️ Mua vest fail — hop")
                hopServer()
                return
            end
        end

        -- 3. Padding tới khu pullup
        setState("GOTO_PULLUP", "Padding tới khu pullup")
        padTo(CONFIG.PULLUP_AREA)

        -- 4. AutoMacro
        setState("MACRO", "Bật AutoMacro")
        if not enableMacro() then
            setState("HOP", "Macro FALSE sau " .. CONFIG.MACRO_RETRIES .. " lần")
            hopServer()
            return
        end

        -- 5. Equip vest + click pullup
        equipToolByName(CONFIG.VEST_NAME)
        setState("PULLUP", "Lên máy pullup")
        if not clickPullupAndSelectDurability() then
            hopServer()
            return
        end
        startPullupMonitor()

        -- 6. Fire raid khi cooldown hết
        setState("FARM_PULLUP", "Đang farm — check raid CD")

        while STATE.onPullup and not STATE.stopped do
            if isInCombat() then
                setState("INCOMBAT", "InCombat trên máy")
                humanoid:MoveTo(rootPart.Position)
                waitForCombatEnd()
                hopServer()
                return
            end

            local cd1 = getRemainingCD("raid1")
            local cd2 = getRemainingCD("raid2")

            if cd1 <= 0 and not STATE.isTeleporting then
                fireRaid("Raid1")
                task.wait(8)
                if checkIsInRaidPlace() then
                    runRaidLogic("Raid1")
                    return
                end
            elseif cd2 <= 0 and not STATE.isTeleporting then
                fireRaid("Raid2")
                task.wait(8)
                if checkIsInRaidPlace() then
                    runRaidLogic("Raid2")
                    return
                end
            end

            -- Re-check pullup UI
            local ui = playerGui:FindFirstChild("PullupGain")
            STATE.onPullup = ui and ui.Enabled or false
            if not STATE.onPullup then break end

            task.wait(10)
        end

        task.wait(2)
    end
end

-- =============================================================================
-- START
-- =============================================================================
log("🚀 Raid2 Bot khởi động — SERVER_URL: " .. CONFIG.SERVER_URL)
task.spawn(mainLoop)
