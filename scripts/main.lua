-- =============================================================================
-- 🧠 MAIN SCRIPT - Bộ não điều khiển toàn bộ quy trình
-- Railway sẽ điều khiển script này qua các state
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
local currentState = "idle" -- idle, padding_to_pullup, buying_vest, on_pullup, raid1, raid2
local isPathfinding = false
local stopPathfinding = false
local kickDetected = false
local currentServerId = game.JobId

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
-- 🎯 MAIN LOOP
-- ============================================================================
print("🧠 Main Script đang khởi động...")
updateStatus("initializing")

-- Đợi load xong
while not game:IsLoaded() do task.wait(0.5) end
while not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") do
    task.wait(0.5)
end
task.wait(2)
print("✅ Game load xong!")

-- Di chuyển khỏi safezone
updateStatus("exiting_safezone")
moveToClearSafezone()
task.wait(3)

-- Tắt lockon
clickDisableLockOn()
task.wait(1)

-- Kiểm tra vị trí pullup
if checkPlayersNearPullup() then
    print("⚠️ Có người ở vị trí pullup → Hop server")
    updateStatus("hopping_server")
    hopServer()
else
    print("✅ Vị trí pullup trống")
    
    -- Kiểm tra vest
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
    
    -- Đi đến pullup
    print("🏃 Đi đến vị trí pullup...")
    updateStatus("padding_to_pullup")
    local arrived = padTo(PULLUP_1)
    if arrived then
        -- Kiểm tra automacro
        if not checkAutoMacro() then
            print("🔴 AutoMacro đang OFF → Bật lên")
            pcall(function()
                ReplicatedStorage.Events.EventCore:FireServer("AutoMacro")
            end)
            task.wait(0.5)
            
            if not checkAutoMacro() then
                print("❌ Không bật được AutoMacro → Hop server")
                updateStatus("hopping_server")
                hopServer()
                return
            end
        end
        
        print("✅ AutoMacro đang ON")
        
        -- Equip vest
        if equipToolByName("80KG Vest") or equipToolByName("Vest 80KG") then
            print("✅ Đã equip Vest")
        end
        
        -- Click máy pullup
        clickNearestPullup()
        
        -- Chuyển sang state pullup
        updateStatus("on_pullup")
        updatePullupStatus(true)
        print("💪 Đang ở trên máy PullUp")
    end
end

print("🧠 Main Script đã hoàn thành khởi động")
