-- =============================================================================
-- 🧠 MAIN SCRIPT - CORE BRAIN - Bộ não điều khiển toàn bộ quy trình
-- State Machine: Game Default → Pullup Training → Raid (nếu cooldown xong)
-- =============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ============================================================================
-- ⚙️ CONFIG
-- ============================================================================
local AGENT_RADIUS = 3.0
local DETECT_DISTANCE = 6
local STEER_OFFSET = 4

-- Railway Config
local RAILWAY_URL = "http://localhost:3000" -- Thay bằng URL Railway thực tế
local ACCOUNT_ID = player.Name -- Sử dụng username làm Account ID

-- Tọa độ quan trọng
local PULLUP_1 = Vector3.new(-2066.056152, 8.374999, -1719.620483)
local PULLUP_2 = Vector3.new(-2053.761963, 8.374999, -1718.615112)
local SHOP_VEST = Vector3.new(-2069.079346, 8.374999, -1667.621826)

-- ============================================================================
-- 🔁 STATE FLAGS
-- ============================================================================
local currentState = "game_default" -- game_default, on_pullup, raid1, raid2
local isPathfinding = false
local stopPathfinding = false
local kickDetected = false
local currentServerId = game.JobId
local scriptRunning = true

-- ============================================================================
-- ⏳ WAIT FOR CHARACTER
-- ============================================================================
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

-- ============================================================================
-- 🔧 UTILITY FUNCTIONS
-- ============================================================================

local function isInCombat()
    return player:GetAttribute("InCombat") == true
end

local function waitForCombatEnd()
    while isInCombat() do
        task.wait(1)
    end
end

local function getEquippedTool()
    local char = player.Character
    return char and char:FindFirstChildOfClass("Tool") or nil
end

local function unequipCurrentTool()
    local char = player.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum:UnequipTools()
            task.wait(0.15)
        end
    end
end

local function equipToolByName(name)
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return false end
    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") and string.lower(tool.Name) == string.lower(name) then
            humanoid:EquipTool(tool)
            return true
        end
    end
    return false
end

-- ============================================================================
-- 🌐 RAILWAY COMMUNICATION
-- ============================================================================

local function sendToRailway(endpoint, data)
    local url = RAILWAY_URL .. endpoint
    local success, response = pcall(function()
        return HttpService:RequestAsync({
            Url = url,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = HttpService:JSONEncode(data)
        })
    end)
    
    if success then
        return true, response
    else
        warn("❌ Railway communication failed:", response)
        return false, response
    end
end

local function updateStatus(status)
    currentState = status
    sendToRailway("/api/state/" .. ACCOUNT_ID .. "/status", { status = status })
    print("📊 Status updated:", status)
end

local function updateCooldown(raid, seconds)
    sendToRailway("/api/state/" .. ACCOUNT_ID .. "/cooldown", { raid = raid, seconds = seconds })
    print("⏱️ Cooldown updated:", raid, seconds, "s")
end

local function updatePullupStatus(isOnPullup)
    sendToRailway("/api/pullup/status", { accountId = ACCOUNT_ID, isOnPullup = isOnPullup })
    print("💪 Pullup status updated:", isOnPullup)
end

local function updateCombatStatus(isInCombat)
    sendToRailway("/api/combat/status", { accountId = ACCOUNT_ID, isInCombat = isInCombat })
    print("⚔️ Combat status updated:", isInCombat)
end

local function updateVestStatus(vestOwned)
    sendToRailway("/api/vest/status", { accountId = ACCOUNT_ID, vestOwned = vestOwned })
    print("🦺 Vest status updated:", vestOwned)
end

local function updateAutoMacroStatus(enabled)
    sendToRailway("/api/automacro/status", { accountId = ACCOUNT_ID, enabled = enabled })
    print("🔧 AutoMacro status updated:", enabled)
end

-- ============================================================================
-- 🎮 STATE DETECTION
-- ============================================================================
local function detectGameState()
    -- Kiểm tra xem đang ở map default hay trong raid
    local mapName = workspace:GetAttribute("MapName") or "default"
    
    if string.find(string.lower(mapName), "raid1") or string.find(string.lower(mapName), "raid 1") then
        return "raid1"
    elseif string.find(string.lower(mapName), "raid2") or string.find(string.lower(mapName), "raid 2") then
        return "raid2"
    else
        return "game_default"
    end
end

-- ============================================================================
-- 🚂 RAILWAY COOLDOWN CHECK
-- ============================================================================
local function checkRaidCooldown(raidName)
    local url = RAILWAY_URL .. "/api/state/" .. ACCOUNT_ID .. "/cooldown/" .. raidName
    local success, response = pcall(function()
        return HttpService:RequestAsync({
            Url = url,
            Method = "GET"
        })
    end)
    
    if success and response then
        local data = HttpService:JSONDecode(response.Body)
        if data and data.cooldown then
            return data.cooldown <= 0, data.cooldown
        end
    end
    
    -- Nếu không thể check, mặc định là chưa cooldown
    return false, 9999
end

-- ============================================================================
-- 📥 LOAD RAID SCRIPTS FROM GITHUB
-- ============================================================================
local RAID_SCRIPTS_URL = "https://raw.githubusercontent.com/phuoculi1810-hub/gamevipcuatao/main/scripts"

local function loadRaidScript(raidName)
    local url = RAID_SCRIPTS_URL .. "/" .. raidName .. ".lua"
    print("📥 Loading raid script:", url)
    
    local success, response = pcall(function()
        return game:HttpGet(url)
    end)
    
    if success and response then
        local ok, err = pcall(function()
            loadstring(response)()
        end)
        
        if ok then
            print("✅ Raid script loaded successfully:", raidName)
            return true
        else
            warn("❌ Error executing raid script:", err)
            return false
        end
    else
        warn("❌ Failed to load raid script:", response)
        return false
    end
end

local function hasVestInInventory()
    local backpack = player:FindFirstChild("Backpack")
    local char = player.Character
    local sources = {}
    
    if backpack then
        for _, t in ipairs(backpack:GetChildren()) do
            if t:IsA("Tool") then table.insert(sources, t) end
        end
    end
    local eq = getEquippedTool()
    if eq then table.insert(sources, eq) end
    
    for _, tool in ipairs(sources) do
        local n = string.lower(tool.Name)
        if string.find(n, "vest") and string.find(n, "80") then
            updateVestStatus(true)
            return true
        end
    end
    updateVestStatus(false)
    return false
end

-- ============================================================================
-- 🔀 SERVER HOP
-- ============================================================================
local function hopServer()
    print("🔀 Đang tìm server thấp hơn để hop...")
    local placeId = game.PlaceId
    
    local ok, result = pcall(function()
        return game:HttpGet(
            "https://games.roblox.com/v1/games/" .. placeId ..
            "/servers/Public?sortOrder=Asc&limit=25"
        )
    end)
    
    if ok then
        local data = pcall(function() return HttpService:JSONDecode(result) end) and HttpService:JSONDecode(result)
        if data and data.data then
            local best, bestCount = nil, math.huge
            for _, s in ipairs(data.data) do
                if s.id ~= currentServerId and s.playing < s.maxPlayers and s.playing < bestCount then
                    bestCount = s.playing
                    best = s
                end
            end
            if best then
                print("✅ Hop → server:", best.id, "| Players:", bestCount)
                TeleportService:TeleportToPlaceInstance(placeId, best.id, player)
                return
            end
        end
    end
    
    print("⚠️ Không tìm được server tốt hơn, dùng Teleport thường...")
    TeleportService:Teleport(placeId, player)
end

-- ============================================================================
-- 🚨 COMBAT + KICK HANDLER
-- ============================================================================
local function handleCombatOrKick()
    if kickDetected then
        print("🚨 Kick detected → Hop server ngay!")
        updateCombatStatus(true)
        hopServer()
        return true
    end
    if isInCombat() then
        print("⚔️ InCombat! Dừng và đợi hết combat...")
        updateCombatStatus(true)
        stopPathfinding = true
        humanoid:MoveTo(rootPart.Position)
        
        while isInCombat() do
            if kickDetected then
                print("🚨 Kick trong lúc combat → Hop ngay!")
                hopServer()
                return true
            end
            task.wait(1)
        end
        
        updateCombatStatus(false)
        print("✅ Hết combat → Hop server...")
        hopServer()
        return true
    end
    return false
end

-- ============================================================================
-- 📢 KICK / SHUTDOWN DETECTION
-- ============================================================================
game.Close:Connect(function()
    kickDetected = true
    print("⚠️ Server đóng! Hop ngay...")
    hopServer()
end)

local function onDisconnected(message)
    message = tostring(message or "")
    print("🔌 Disconnect nhận được:", message)
    if message:find("288") or message:find("shut down") or message:find("Disconnected") then
        kickDetected = true
        print("🚨 Phát hiện Error 288 → Hop server ngay!")
        task.wait(1)
        hopServer()
    end
end

game:GetService("Players").LocalPlayer.OnTeleport:Connect(function(state, placeId, spawnName)
    if state == Enum.TeleportState.Failed then
        print("⚠️ Teleport thất bại → thử lại hop...")
        task.wait(2)
        hopServer()
    end
end)

pcall(function()
    local coreGui = game:GetService("CoreGui")
    coreGui.DescendantAdded:Connect(function(obj)
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            local txt = obj.Text or ""
            if txt:find("288") or txt:find("shut down") or txt:lower():find("disconnected") then
                onDisconnected(txt)
            end
        end
    end)
end)

-- ============================================================================
-- 🏃 PATHFINDING (padding)
-- ============================================================================
local function startRun()
    pcall(function()
        ReplicatedStorage.Events.EventCore:FireServer("Run", "Start", true, 2)
    end)
    print("🏃 Bật Run!")
end

local function stopRun()
    pcall(function()
        ReplicatedStorage.Events.EventCore:FireServer("Run", "Start", false)
    end)
    print("🚶 Tắt Run")
end

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.FilterDescendantsInstances = {character}

local function checkPlayerBlocking()
    local result = workspace:Raycast(
        rootPart.Position,
        rootPart.CFrame.LookVector * DETECT_DISTANCE,
        raycastParams
    )
    if result and result.Instance then
        local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
        if hitModel and hitModel:FindFirstChild("Humanoid") then
            return Players:GetPlayerFromCharacter(hitModel) ~= nil
        end
    end
    return false
end

local function padTo(targetPosition)
    stopPathfinding = false
    isPathfinding = true
    
    local path = PathfindingService:CreatePath({
        AgentRadius = AGENT_RADIUS,
        AgentHeight = 5,
        AgentCanJump = true,
    })
    
    print("🔍 Tính lộ trình → ", targetPosition)
    startRun()
    
    local ok, err = pcall(function()
        path:ComputeAsync(rootPart.Position, targetPosition)
    end)
    
    if not (ok and path.Status == Enum.PathStatus.Success) then
        warn("❌ Pathfinding thất bại:", tostring(err))
        stopRun()
        isPathfinding = false
        return false
    end
    
    local waypoints = path:GetWaypoints()
    local lastPosition = rootPart.Position
    local stuckCounter = 0
    
    for i, waypoint in ipairs(waypoints) do
        if stopPathfinding then break end
        if i == 1 then continue end
        
        if getEquippedTool() then
            print("🖐️ Tự equip trong lúc padding → Unequip")
            unequipCurrentTool()
        end
        
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            humanoid.Jump = true
        end
        
        local targetPos = waypoint.Position
        local startTime = os.clock()
        
        while (rootPart.Position - targetPos).Magnitude > 5 do
            if stopPathfinding then break end
            task.wait()
            
            if getEquippedTool() then unequipCurrentTool() end
            
            if kickDetected or isInCombat() then
                stopRun()
                isPathfinding = false
                handleCombatOrKick()
                return false
            end
            
            local distToTarget = (rootPart.Position - targetPos).Magnitude
            if distToTarget <= 50 then
                stopRun()
            end
            
            -- Anti-fly: Check nếu bị hất lên quá cao
            if rootPart.Position.Y > targetPos.Y + 10 then
                print("🚀 Anti-fly: Bị hất lên quá cao → Reset position")
                humanoid:MoveTo(lastPosition)
                task.wait(0.5)
            end
            
            -- Anti-stuck: Check nếu không di chuyển
            local currentPos = rootPart.Position
            local movedDistance = (currentPos - lastPosition).Magnitude
            if movedDistance < 0.5 then
                stuckCounter = stuckCounter + 1
                if stuckCounter > 3 then
                    print("⚠️ Anti-stuck: Kẹt cứng → Jump và né")
                    humanoid.Jump = true
                    if checkPlayerBlocking() then
                        humanoid:MoveTo(targetPos + rootPart.CFrame.RightVector * (STEER_OFFSET * 2))
                    else
                        humanoid:MoveTo(targetPos + Vector3.new(0, 5, 0))
                    end
                    stuckCounter = 0
                end
            else
                stuckCounter = 0
            end
            lastPosition = currentPos
            
            if checkPlayerBlocking() then
                humanoid:MoveTo(targetPos + rootPart.CFrame.RightVector * STEER_OFFSET)
            else
                humanoid:MoveTo(targetPos)
            end
            
            if (os.clock() - startTime) > 1.5 then
                humanoid.Jump = true
                break
            end
        end
    end
    
    stopRun()
    isPathfinding = false
    if stopPathfinding then return false end
    print("🎯 Đến đích:", targetPosition)
    return true
end

-- ============================================================================
-- 📱 TẮT LOCK-ON MOBILE
-- ============================================================================
local function clickDisableLockOn()
    print("📱 Tắt Lock-On mobile...")
    local mobileGui = playerGui:FindFirstChild("Mobile")
    local mobileButtons = mobileGui and mobileGui:FindFirstChild("MobileButtons")
    local shiftLock = mobileButtons and mobileButtons:FindFirstChild("ShiftLock")
    
    if shiftLock then
        pcall(function() shiftLock:Activate() end)
        task.wait(0.2)
        pcall(function() firesignal(shiftLock.MouseButton1Click) end)
        task.wait(0.2)
        pcall(function()
            firesignal(shiftLock.MouseButton1Down)
            task.wait(0.1)
            firesignal(shiftLock.MouseButton1Up)
        end)
        print("✅ Đã tắt Lock-On")
    else
        print("ℹ️ Không tìm thấy ShiftLock")
    end
end

-- ============================================================================
-- 🔄 MAIN LOGIC
-- ============================================================================

local function moveToClearSafezone()
    local ch = player.Character
    if not ch then return end
    local hrp = ch:FindFirstChild("HumanoidRootPart")
    local hum = ch:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end
    
    local fwd = hrp.CFrame.LookVector * 2
    hum:Move(fwd, true)
    task.wait(0.5)
    hum:Move(-fwd, true)
    task.wait(0.5)
    hum:Move(Vector3.new(0, 0, 0), true)
    print("✅ Đã nhích khỏi safezone")
end

local function checkPlayersNearPullup()
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player then
            local char = otherPlayer.Character
            if char then
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local dist1 = (hrp.Position - PULLUP_1).Magnitude
                    local dist2 = (hrp.Position - PULLUP_2).Magnitude
                    if dist1 < 10 or dist2 < 10 then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function checkAutoMacro()
    local settingsFrame = playerGui:FindFirstChild("AutoMacroV2")
    if not settingsFrame then 
        updateAutoMacroStatus(false)
        return false 
    end
    
    settingsFrame = settingsFrame:FindFirstChild("Frame")
    if not settingsFrame then 
        updateAutoMacroStatus(false)
        return false 
    end
    
    local macroBtnFolder = settingsFrame:FindFirstChild("MacroBTN", true)
    if not macroBtnFolder then 
        updateAutoMacroStatus(false)
        return false 
    end
    
    local textButton = macroBtnFolder:FindFirstChild("TextButton")
    if not textButton then 
        updateAutoMacroStatus(false)
        return false 
    end
    
    local isEnabled = textButton.Text == "TRUE"
    updateAutoMacroStatus(isEnabled)
    return isEnabled
end

local function buy80KGVest()
    print("🛒 Đang mua 80KG Vest...")
    
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ClickDetector") or obj:IsA("ProximityPrompt") then
            local itemName = string.lower(obj.Parent.Name)
            
            if string.find(itemName, "vest") and string.find(itemName, "80") then
                local pos = (obj.Parent:IsA("BasePart") and obj.Parent.Position) 
                            or (obj.Parent:FindFirstChildWhichIsA("BasePart") and obj.Parent:FindFirstChildWhichIsA("BasePart").Position)
                
                if pos and (rootPart.Position - pos).Magnitude < 20 then
                    if obj:IsA("ClickDetector") then
                        fireclickdetector(obj)
                    else
                        fireproximityprompt(obj)
                    end
                    print("💰 Đã mua Vest 80KG")
                    return true
                end
            end
        end
    end
    return false
end

local function clickNearestPullup()
    local best, bestD = nil, math.huge
    for _, obj in ipairs(workspace.Trainings["Pull-ups"]:GetChildren()) do
        if obj:IsA("Model") and obj:FindFirstChild("Center") and obj:FindFirstChild("ClickDetector") then
            local d = (rootPart.Position - obj.Center.Position).Magnitude
            if d < bestD then bestD = d; best = obj end
        end
    end
    
    if not best then
        for _, obj in ipairs(workspace.Trainings["Pull-ups"]:GetChildren()) do
            if obj:IsA("Model") and obj:FindFirstChild("ClickDetector") then
                local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
                if part then
                    local d = (rootPart.Position - part.Position).Magnitude
                    if d < bestD then bestD = d; best = obj end
                end
            end
        end
    end
    
    if best then
        fireclickdetector(best.ClickDetector)
        print("✅ Đã click máy PullUp:", best.Name)
        return true
    end
    return false
end

-- ============================================================================
-- 🎯 STATE MACHINE - GAME DEFAULT
-- ============================================================================
local function handleGameDefaultState()
    print("🎮 State: GAME_DEFAULT")
    updateStatus("game_default")
    
    -- 1. Di chuyển khỏi safezone
    print("🚶 Nhích khỏi safezone...")
    moveToClearSafezone()
    task.wait(3)
    
    -- 2. Tắt lockon
    print("📱 Tắt lock-on...")
    clickDisableLockOn()
    task.wait(1)
    
    -- 3. Kiểm tra 2 máy pullup có người không
    if checkPlayersNearPullup() then
        print("⚠️ Có người ở 2 máy pullup → Hop server")
        updateStatus("hopping_server")
        hopServer()
        return
    end
    print("✅ 2 máy pullup trống")
    
    -- 4. Kiểm tra inventory có vest không
    if not hasVestInInventory() then
        print("🛒 Chưa có 80KG Vest → Đi mua")
        updateStatus("buying_vest")
        local arrived = padTo(SHOP_VEST)
        if arrived then
            buy80KGVest()
            task.wait(1)
        end
    else
        print("✅ Đã có 80KG Vest")
    end
    
    -- 5. Kiểm tra lại pullup sau khi mua vest
    if checkPlayersNearPullup() then
        print("⚠️ Sau khi mua vest, 2 máy bị chiếm → Hop server")
        updateStatus("hopping_server")
        hopServer()
        return
    end
    
    -- 6. Padding đến pullup
    print("🏃 Padding đến vị trí pullup...")
    updateStatus("padding_to_pullup")
    local arrived = padTo(PULLUP_1)
    if not arrived then
        print("❌ Không thể đến được pullup → Hop server")
        hopServer()
        return
    end
    
    -- 7. Chọn máy không có người và tập
    if equipToolByName("80KG Vest") or equipToolByName("Vest 80KG") then
        print("✅ Đã equip Vest")
    end
    
    -- 8. Kiểm tra AutoMacro
    if not checkAutoMacro() then
        print("🔴 AutoMacro đang OFF → Bật lên")
        pcall(function()
            ReplicatedStorage.Events.EventCore:FireServer("AutoMacro")
        end)
        task.wait(0.5)
        
        if not checkAutoMacro() then
            print("❌ Không bật được AutoMacro → Hop server")
            hopServer()
            return
        end
    end
    print("✅ AutoMacro đang ON")
    
    -- 9. Click máy pullup
    clickNearestPullup()
    
    -- 10. Chuyển sang state on_pullup
    currentState = "on_pullup"
    updateStatus("on_pullup")
    updatePullupStatus(true)
    print("💪 Đang tập pullup...")
end

-- ============================================================================
-- 🎯 STATE MACHINE - ON PULLUP (CHECK RAID COOLDOWN + DEFENSE)
-- ============================================================================
local function handleOnPullupState()
    print("💪 State: ON_PULLUP - Checking raid cooldown...")
    updateStatus("on_pullup")
    
    local pullupTimeoutStart = os.time()
    local PULLUP_TIMEOUT = 60 -- 60 giây timeout
    
    while scriptRunning do
        task.wait(5) -- Check mỗi 5 giây
        
        -- 1. Check combat defense
        if isInCombat() then
            print("⚔️ InCombat trong lúc pullup → Đợi hết combat rồi hop")
            updateCombatStatus(true)
            waitForCombatEnd()
            updateCombatStatus(false)
            print("✅ Hết combat → Hop server")
            updateStatus("hopping_server")
            hopServer()
            return
        end
        
        -- 2. Check pullup machine theft
        if checkPlayersNearPullup() then
            print("⚠️ Có người cướm máy pullup → Hop server")
            updateStatus("hopping_server")
            hopServer()
            return
        end
        
        -- 3. Check 60s pullup timeout
        local timeOnPullup = os.time() - pullupTimeoutStart
        if timeOnPullup >= PULLUP_TIMEOUT then
            print("⏱️ Không ở trên pullup 60s → Hop server")
            updateStatus("hopping_server")
            hopServer()
            return
        end
        
        -- 4. Check raid1 cooldown
        local raid1Ready, raid1Cooldown = checkRaidCooldown("raid1")
        local raid2Ready, raid2Cooldown = checkRaidCooldown("raid2")
        
        print("📊 Raid1 Cooldown:", raid1Cooldown, "s | Raid2 Cooldown:", raid2Cooldown, "s | Pullup Time:", timeOnPullup, "s")
        
        if raid1Ready then
            print("✅ Raid1 cooldown xong → Đi raid1")
            currentState = "raid1"
            return
        end
        
        if raid2Ready then
            print("✅ Raid2 cooldown xong → Đi raid2")
            currentState = "raid2"
            return
        end
        
        -- 5. Nếu còn cooldown, tiếp tục tập pullup
        print("⏳ Còn cooldown → Tiếp tục tập pullup")
        
        -- Check xem còn trên máy pullup không
        if not checkAutoMacro() then
            print("⚠️ AutoMacro tắt → Re-enable")
            pcall(function()
                ReplicatedStorage.Events.EventCore:FireServer("AutoMacro")
            end)
        end
    end
end

-- ============================================================================
-- 🎯 STATE MACHINE - RAID1
-- ============================================================================
local function handleRaid1State()
    print("⚔️ State: RAID1")
    updateStatus("raid1")
    
    -- Load và chạy raid1 script
    local loaded = loadRaidScript("raid1")
    if loaded then
        print("✅ Raid1 script đang chạy...")
        -- Raid script sẽ tự quản lý, sau khi xong sẽ teleport về map default
        -- Khi về map default, state sẽ detect lại
    else
        print("❌ Không thể load raid1 script → Về pullup")
        currentState = "on_pullup"
    end
end

-- ============================================================================
-- 🎯 STATE MACHINE - RAID2
-- ============================================================================
local function handleRaid2State()
    print("⚔️ State: RAID2")
    updateStatus("raid2")
    
    -- Load và chạy raid2 script
    local loaded = loadRaidScript("raid2")
    if loaded then
        print("✅ Raid2 script đang chạy...")
        -- Raid script sẽ tự quản lý, sau khi xong sẽ teleport về map default
        -- Khi về map default, state sẽ detect lại
    else
        print("❌ Không thể load raid2 script → Về pullup")
        currentState = "on_pullup"
    end
end

-- ============================================================================
-- 🎯 MAIN LOOP - STATE MACHINE
-- ============================================================================
print("🧠 Main Script CORE BRAIN đang khởi động...")
updateStatus("initializing")

-- Đợi load xong
while not game:IsLoaded() do task.wait(0.5) end
while not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") do
    task.wait(0.5)
end
task.wait(2)
print("✅ Game load xong!")

-- Main State Machine Loop
while scriptRunning do
    -- Detect current game state
    local detectedState = detectGameState()
    print("🎮 Detected state:", detectedState)
    
    -- Handle based on state
    if detectedState == "game_default" then
        if currentState == "game_default" or currentState == "on_pullup" then
            if currentState == "game_default" then
                handleGameDefaultState()
            else
                handleOnPullupState()
            end
        else
            -- Nếu từ raid về map default, reset về game_default
            currentState = "game_default"
            handleGameDefaultState()
        end
    elseif detectedState == "raid1" then
        currentState = "raid1"
        handleRaid1State()
    elseif detectedState == "raid2" then
        currentState = "raid2"
        handleRaid2State()
    else
        print("⚠️ Unknown state, default to game_default")
        currentState = "game_default"
        handleGameDefaultState()
    end
    
    task.wait(1)
end

print("🧠 Main Script đã dừng")
