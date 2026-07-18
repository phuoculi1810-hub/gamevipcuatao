-- [[ AUTO RAID 2 LOGIC ]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Railway Config
local RAILWAY_URL = "http://localhost:3000" -- Thay bằng URL Railway thực tế
local ACCOUNT_ID = LocalPlayer.Name

local isAttacking = false
local isInRaid = false
local raidFinished = false
local isTeleporting = false

-- ============================================================================
-- ⚙️ CẤU HÌNH PADDING (Pathfinding né tường / né người)
-- ============================================================================
local AGENT_RADIUS = 3.0
local DETECT_DISTANCE = 6
local STEER_OFFSET = 4
local DOOR_APPROACH_OFFSET = 12   -- TP cách cửa bao nhiêu stud rồi mới đi bộ vào
local DOOR_WALK_SPEED = 8         -- Tốc độ đi bộ chậm khi padding tới cửa (không dùng Run)

-- ============================================================================
-- 🚪 TỌA ĐỘ CỬA & PHÒNG BOSS RAID 2
-- ============================================================================
local DOOR_1_CFRAME = CFrame.new(
    -1480.296875, 198.39987182617188, -1954.6844482421875,
    0.999984443, 2.62872035e-08, 0.00557733839,
    -2.64498077e-08, 1, 2.90807094e-08,
    -0.00557733839, -2.92277758e-08, 0.999984443
)

local DOOR_2_CFRAME = CFrame.new(
    -1522.5589599609375, 198.39987182617188, -1979.7039794921875,
    0.978798807, 1.0990361e-07, -0.204824165,
    -1.04476818e-07, 1, 3.73091815e-08,
    0.204824165, -1.51188058e-08, 0.978798807
)

-- Vị trí trước cửa vào phòng boss (đi thẳng thêm chút để trigger teleport)
local ENTRANCE_CFRAME = CFrame.new(
    -1474.9471435546875, 198.39987182617188, -1998.409423828125,
    0.0731486827, 8.99302961e-08, -0.997321069,
    3.36267973e-08, 1, 9.26382242e-08,
    0.997321069, -4.03130791e-08, 0.0731486827
)

-- Vị trí đứng đánh Boss (sau khi đã teleport vào phòng boss)
local BOSS_ROOM_CFRAME = CFrame.new(
    -1628.3253173828125, 198.39987182617188, -1934.07861328125,
    0.0527792498, -2.27287735e-08, -0.998606205,
    -1.47837902e-08, 1, -2.35418636e-08,
    0.998606205, 1.6005707e-08, 0.0527792498
)

-- Cooldown lưu local (không dùng server ngoài nữa)
local localCooldown = 0
local lastCooldownUpdate = 0

local function setLocalCooldown(seconds)
    localCooldown = seconds + 15
    lastCooldownUpdate = os.time()
    
    -- Send to Railway
    pcall(function()
        HttpService:RequestAsync({
            Url = RAILWAY_URL .. "/api/state/" .. ACCOUNT_ID .. "/cooldown",
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = HttpService:JSONEncode({ raid = "raid2", seconds = seconds })
        })
    end)
end

local function getLocalCooldown()
    if localCooldown <= 0 then return 0 end
    local elapsed = os.time() - lastCooldownUpdate
    local remaining = localCooldown - elapsed
    if remaining < 0 then remaining = 0 end
    return remaining
end

local function updateStatus(statusMsg)
    print("[Raid2 Status] " .. statusMsg)
    
    -- Send to Railway
    pcall(function()
        HttpService:RequestAsync({
            Url = RAILWAY_URL .. "/api/state/" .. ACCOUNT_ID .. "/status",
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = HttpService:JSONEncode({ status = statusMsg })
        })
    end)
end

local function parseCooldown(text)
    local hours = string.match(text, "(%d+) hour") or 0
    local minutes = string.match(text, "(%d+) minute") or 0
    local seconds = string.match(text, "(%d+) second") or 0
    return (tonumber(hours) * 3600) + (tonumber(minutes) * 60) + tonumber(seconds)
end

local function stripColorTags(text)
    if not text then return "" end
    text = string.gsub(text, "<Color=[^>]->", "")
    text = string.gsub(text, "<Color/=?>", "")
    return text
end

-- 3. Hàm xử lý combat
local function equipCombat()
    local backpack = LocalPlayer:WaitForChild("Backpack")

    local validCombats = {
        ["Brawl"] = true,
        ["Sambo"] = true,
        ["Peek-a-Boo"] = true,
        ["Hitman"] = true,
        ["Northern Taekwondo"] = true,
        ["NorthernTaekwondo"] = true,
        ["Combat"] = true
    }

    for _, item in ipairs(backpack:GetChildren()) do
        if item:IsA("Tool") and validCombats[item.Name] then
            LocalPlayer.Character.Humanoid:EquipTool(item)
            print("[Raid2] Đã tự động trang bị vũ khí:", item.Name)
            return
        end
    end
    print("[Raid2] Cảnh báo: Không tìm thấy Combat nào hợp lệ trong Backpack!")
end

local function moveSlightly()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hrp  = char:WaitForChild("HumanoidRootPart")
    local hum  = char:WaitForChild("Humanoid")
    if not hrp or not hum then return end

    task.wait(0.5)

    local fwd = hrp.CFrame.LookVector

    hum:Move(fwd, true)
    task.wait(0.6)
    hum:Move(-fwd, true)
    task.wait(0.6)
    hum:Move(fwd, true)
    task.wait(0.6)
    hum:Move(Vector3.new(0, 0, 0), true)

    print("[Raid2] Đã nhích khỏi safezone!")
end

local function startAutoAttack()
    isAttacking = true
    task.spawn(function()
        while isAttacking and task.wait(0.1) do
            VirtualUser:ClickButton1(Vector2.new())
        end
    end)
end

local function stopAutoAttack()
    isAttacking = false
end

-- Đánh liên tục trong một khoảng thời gian cố định rồi tự dừng (fallback khi không tìm thấy cửa)
local function attackForSeconds(duration)
    startAutoAttack()
    task.wait(duration)
    stopAutoAttack()
end

-- Tìm Instance cửa (có Attribute "Hitable" = true) đang ở ngay phía trước nhân vật
local function findHitableDoorInFront()
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local rootPart = character:WaitForChild("HumanoidRootPart")

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = {character}

    local rayOrigin = rootPart.Position
    local rayDirection = rootPart.CFrame.LookVector * 15
    local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

    if result and result.Instance then
        local part = result.Instance
        if part:GetAttribute("Hitable") then
            return part
        end
        -- Union có thể trúng phần khác, thử tìm anh em cùng Parent có Attribute Hitable
        if part.Parent then
            for _, sibling in ipairs(part.Parent:GetChildren()) do
                if sibling:GetAttribute("Hitable") then
                    return sibling
                end
            end
        end
    end
    return nil
end

-- Lấy thẳng Instance cửa theo tên (VD "Door1", "Door2") từ Workspace.Hitable
local function getDoorInstanceByName(doorName)
    local hitableFolder = workspace:FindFirstChild("Hitable")
    if not hitableFolder then return nil end
    return hitableFolder:FindFirstChild(doorName)
end

-- Lấy Instance thật của cửa vào phòng Boss (Bank Vault)
local function getBossVaultEntrance()
    local hitableFolder = workspace:FindFirstChild("Hitable")
    if not hitableFolder then return nil end
    local vault = hitableFolder:FindFirstChild("BankVault")
    if not vault then return nil end
    return vault:FindFirstChild("TPPart") or vault:FindFirstChild("Cylinder")
end

-- Xoay nhân vật nhìn thẳng vào 1 Object
local function faceTowardsObject(rootPart, targetPart)
    if not targetPart or not targetPart.Parent then return end
    local targetPos = targetPart.Position
    local lookAtPos = Vector3.new(targetPos.X, rootPart.Position.Y, targetPos.Z)
    if (lookAtPos - rootPart.Position).Magnitude < 0.05 then return end
    rootPart.CFrame = CFrame.new(rootPart.Position, lookAtPos)
end

-- Đợi tới khi cửa vỡ
local function waitForDoorBreak(doorPart, timeoutSeconds)
    timeoutSeconds = timeoutSeconds or 15
    local broken = false

    local startHealth = doorPart:GetAttribute("Health")
    print("[Raid2] Máu cửa ban đầu: " .. tostring(startHealth))

    local healthConn = doorPart:GetAttributeChangedSignal("Health"):Connect(function()
        local hp = doorPart:GetAttribute("Health")
        print("[Raid2] Health cửa còn: " .. tostring(hp))
        if hp and hp <= 0 then
            broken = true
        end
    end)

    local ancestryConn = doorPart.AncestryChanged:Connect(function(_, newParent)
        if newParent == nil then
            print("[Raid2] Cửa đã bị gỡ khỏi Workspace.")
            broken = true
        end
    end)

    local startTime = os.clock()
    while not broken and (os.clock() - startTime) < timeoutSeconds do
        task.wait(0.1)
    end

    healthConn:Disconnect()
    ancestryConn:Disconnect()

    if broken then
        print("[Raid2] 🚪💥 Cửa đã vỡ!")
    else
        warn("[Raid2] ⚠️ Hết timeout nhưng chưa thấy cửa vỡ, tiếp tục theo kịch bản.")
    end

    return broken
end

-- ============================================================================
-- 🏃 PADDING: DI CHUYỂN THÔNG MINH TỚI TỌA ĐỘ
-- ============================================================================
local function checkPlayerBlocking(rootPart, raycastParams)
    local rayOrigin = rootPart.Position
    local rayDirection = rootPart.CFrame.LookVector * DETECT_DISTANCE
    local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

    if raycastResult and raycastResult.Instance then
        local hitModel = raycastResult.Instance:FindFirstAncestorOfClass("Model")
        if hitModel and hitModel:FindFirstChild("Humanoid") then
            local otherPlayer = Players:GetPlayerFromCharacter(hitModel)
            if otherPlayer then
                return true
            end
        end
    end
    return false
end

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

local function paddingToPosition(targetPosition, options)
    options = options or {}
    local useRun = options.useRun ~= false
    local slowWalkSpeed = options.walkSpeed

    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid")
    local rootPart = character:WaitForChild("HumanoidRootPart")

    humanoid.AutoRotate = true

    local originalWalkSpeed = humanoid.WalkSpeed
    if slowWalkSpeed then
        humanoid.WalkSpeed = slowWalkSpeed
    end

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = {character}

    local path = PathfindingService:CreatePath({
        AgentRadius = AGENT_RADIUS,
        AgentHeight = 5,
        AgentCanJump = true
    })

    print("🔍 [Padding] Đang tính toán lộ trình...")
    if useRun then startRun() end

    local success, err = pcall(function()
        path:ComputeAsync(rootPart.Position, targetPosition)
    end)

    if not (success and path.Status == Enum.PathStatus.Success) then
        warn("❌ [Padding] Không tìm thấy đường đi: " .. tostring(err))
        if useRun then stopRun() end
        if slowWalkSpeed then humanoid.WalkSpeed = originalWalkSpeed end
        return false
    end

    print("✅ [Padding] Lộ trình OK, bắt đầu di chuyển...")
    local waypoints = path:GetWaypoints()
    local arrivalThreshold = slowWalkSpeed and 3 or 5

    for i, waypoint in ipairs(waypoints) do
        if i > 1 then
            local wpTarget = waypoint.Position

            if waypoint.Action == Enum.PathWaypointAction.Jump then
                humanoid.Jump = true
            end

            local startTime = os.clock()
            while (rootPart.Position - wpTarget).Magnitude > arrivalThreshold do
                task.wait()

                if useRun then
                    local distToFinal = (rootPart.Position - targetPosition).Magnitude
                    if distToFinal <= 50 then
                        stopRun()
                    end
                end

                if checkPlayerBlocking(rootPart, raycastParams) then
                    local steerVector = rootPart.CFrame.RightVector * STEER_OFFSET
                    local dynamicTarget = wpTarget + steerVector
                    humanoid:MoveTo(dynamicTarget)
                else
                    humanoid:MoveTo(wpTarget)
                end

                if (os.clock() - startTime) > 1.5 then
                    humanoid.Jump = true
                    break
                end
            end
        end
    end

    if useRun then stopRun() end
    if slowWalkSpeed then humanoid.WalkSpeed = originalWalkSpeed end
    print("🎯 [Padding] Đã tới nơi!")
    return true
end

local function paddingToCFrame(targetCFrame, options)
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid")
    local rootPart = character:WaitForChild("HumanoidRootPart")

    options = options or {}
    local useRun = options.useRun ~= false
    local slowWalkSpeed = options.walkSpeed
    local arrivalThreshold = slowWalkSpeed and 3 or 5

    local arrived = paddingToPosition(targetCFrame.Position, options)

    if not arrived then
        warn("[Padding] Pathfinding thất bại, thử đi thẳng bằng MoveTo thường...")
        local originalWalkSpeed = humanoid.WalkSpeed
        if slowWalkSpeed then humanoid.WalkSpeed = slowWalkSpeed end
        if useRun then startRun() end
        humanoid:MoveTo(targetCFrame.Position)

        local start = os.clock()
        while (rootPart.Position - targetCFrame.Position).Magnitude > arrivalThreshold and (os.clock() - start) < 8 do
            task.wait()
        end
        if useRun then stopRun() end
        if slowWalkSpeed then humanoid.WalkSpeed = originalWalkSpeed end
    end

    humanoid:MoveTo(rootPart.Position)
    humanoid.AutoRotate = false
    rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    rootPart.CFrame = CFrame.new(rootPart.Position) * (targetCFrame - targetCFrame.Position)
    task.wait(0.2)

    print("[Padding] Đã chỉnh hướng nhìn chính xác.")
end

local function teleportAndStabilize(rootPart, targetCFrame, holdSeconds)
    holdSeconds = holdSeconds or 0.3
    local wasAnchored = rootPart.Anchored

    rootPart.Anchored = true
    rootPart.CFrame = targetCFrame
    task.wait(holdSeconds)

    rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    rootPart.Anchored = wasAnchored
end

local function getDoorApproachCFrames(doorPart, standCFrame, offsetStuds)
    offsetStuds = offsetStuds or DOOR_APPROACH_OFFSET
    local standPos = doorPart and doorPart.Position or standCFrame.Position
    local rotation = standCFrame - standCFrame.Position
    local backDir = -standCFrame.LookVector
    local nearPos = standPos + backDir * offsetStuds
    return CFrame.new(nearPos) * rotation, CFrame.new(standPos) * rotation
end

local function breakDoor(doorName, approxCFrame, maxAttackSeconds)
    print("[Raid2] Đang tìm cửa " .. doorName .. " trong Workspace...")
    local doorPart = getDoorInstanceByName(doorName)

    if doorPart then
        print("[Raid2] Đã tìm thấy Instance cửa: " .. doorPart:GetFullName())
    else
        warn("[Raid2] Không tìm thấy Instance '" .. doorName .. "', dùng toạ độ dự phòng.")
    end

    local nearCFrame, attackCFrame = getDoorApproachCFrames(doorPart, approxCFrame, DOOR_APPROACH_OFFSET)

    print("[Raid2] TP gần " .. doorName .. " rồi padding đi bộ vào...")
    updateStatus("TP gần cửa, đi bộ vào")

    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid")
    local rootPart = character:WaitForChild("HumanoidRootPart")

    humanoid:MoveTo(rootPart.Position)
    humanoid.AutoRotate = true
    rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

    teleportAndStabilize(rootPart, nearCFrame, 0.2)
    task.wait(0.15)

    local paddingOpts = { useRun = false, walkSpeed = DOOR_WALK_SPEED }
    paddingToCFrame(attackCFrame, paddingOpts)
    task.wait(0.15)

    if not doorPart then
        doorPart = findHitableDoorInFront()
    end

    if doorPart then
        faceTowardsObject(rootPart, doorPart)
    end

    equipCombat()
    updateStatus("Đang phá cửa...")
    startAutoAttack()

    if doorPart then
        local faceConn = RunService.Heartbeat:Connect(function()
            faceTowardsObject(rootPart, doorPart)
        end)

        print("[Raid2] Đang đánh " .. doorName .. ", đợi cửa vỡ...")
        waitForDoorBreak(doorPart, maxAttackSeconds or 15)

        faceConn:Disconnect()
    else
        warn("[Raid2] Không tìm thấy cửa Hitable, đánh theo thời gian dự phòng.")
        task.wait(maxAttackSeconds or 8)
    end

    stopAutoAttack()

    if character then
        local hum = character:FindFirstChild("Humanoid")
        if hum then hum.AutoRotate = true end
    end

    print("[Raid2] Đã xử lý xong " .. doorName .. "!")
end

local function parseWaitSeconds(text)
    local sec = string.match(text, "in (%d+) second")
    if sec then return tonumber(sec) end
    return nil
end

local function monitorNotifications()
    local function handleText(rawText, duration)
        if not rawText or rawText == "" then return end
        local cleaned = stripColorTags(rawText)
        local text = string.lower(cleaned)

        if string.find(text, "you can't create this raid") or string.find(text, "you can't start this raid") then
            local cdSeconds = parseCooldown(text)
            setLocalCooldown(cdSeconds)
            updateStatus("Đang chờ Cooldown (" .. cdSeconds .. "s)")
            print("[Raid2] Đã lưu Cooldown mới (local): ", cdSeconds, "giây")

        elseif string.find(text, "teleporting to the raid") then
            isTeleporting = true
            updateStatus("Teleporting Raid")
            print("[Raid2] Chuẩn bị vào raid, đã khóa vòng lặp Fire...")

        elseif string.find(text, "boss has been defeated") then
            updateStatus("Đã tiêu diệt Boss! Raid hoàn thành.")
            print("[Raid2] Boss đã chết! Raid xong.")
            stopAutoAttack()
            raidFinished = true

        elseif string.find(text, "teleporting back") then
            updateStatus("Teleporting Back")
            print("[Raid2] Đang teleport về sảnh...")

        elseif string.find(text, "wave has been cleared") then
            local waitSec = parseWaitSeconds(text) or duration or 5

            stopAutoAttack()
            updateStatus("Đã dọn sạch Wave, chờ " .. waitSec .. "s sang Wave tiếp theo")
            print("[Raid2] Wave cleared, dừng click, đợi " .. waitSec .. "s...")

            task.delay(waitSec, function()
                if not raidFinished then
                    startAutoAttack()
                    print("[Raid2] Hết thời gian chờ, click lại!")
                end
            end)

        elseif string.find(text, "wave") and string.find(text, "starting") then
            local waveNum = string.match(text, "wave (%d+)")
            if waveNum then
                if tonumber(waveNum) == 10 then
                    updateStatus("Wave 10 - BOSS bắt đầu!")
                    print("[Raid2] Wave 10 (Boss) bắt đầu!")
                else
                    updateStatus("Đang bắt đầu Wave " .. waveNum)
                    print("[Raid2] Wave " .. waveNum .. " bắt đầu.")
                end
            else
                updateStatus(cleaned)
                print("[Raid2] Thông báo: ", cleaned)
            end
        end
    end

    pcall(function()
        local NotifyEvent = ReplicatedStorage:WaitForChild("NotifyEvent")
        NotifyEvent.OnClientEvent:Connect(function(msg, duration)
            handleText(msg, duration)
        end)
        print("[Raid2] Đã hook thành công NotifyEvent.OnClientEvent")
    end)
end

local function checkIsInRaid()
    local playersCount = #Players:GetPlayers()
    if playersCount <= 1 then
        return true
    else
        return false
    end
end

-- ============================================================================
-- 🚪 CHUỖI PHÁ CỬA + VÀO PHÒNG BOSS (RIÊNG CHO RAID 2)
-- ============================================================================
local function doDoorSequenceAndEnterBossRoom()
    print("[Raid2] TP gần Door1, padding vào...")
    updateStatus("TP gần Door1")
    breakDoor("Door1", DOOR_1_CFRAME, 15)

    print("[Raid2] TP gần Door2, padding vào...")
    updateStatus("TP gần Door2")
    breakDoor("Door2", DOOR_2_CFRAME, 15)

    print("[Raid2] Đã phá xong 2 cửa, TP thẳng chạm TPPart -> vào phòng Boss.")
    updateStatus("Đang TP vào phòng Boss")

    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid")
    local rootPart = character:WaitForChild("HumanoidRootPart")

    humanoid.AutoRotate = false
    rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

    print("[Raid2] TP thẳng tới TPPart...")
    updateStatus("Đang TP tới TPPart")

    local vaultEntrance = getBossVaultEntrance()
    if vaultEntrance then
        print("[Raid2] TP thẳng vào TPPart để kích hoạt: " .. vaultEntrance:GetFullName())
        teleportAndStabilize(rootPart, CFrame.new(vaultEntrance.Position), 0.3)
    else
        warn("[Raid2] Không tìm thấy TPPart, TP thử theo ENTRANCE_CFRAME thay thế.")
        teleportAndStabilize(rootPart, ENTRANCE_CFRAME, 0.3)
    end

    task.wait(0.6)

    print("[Raid2] TP thẳng vào khu vực đánh Boss...")
    updateStatus("Đang TP vào khu vực Boss")

    teleportAndStabilize(rootPart, BOSS_ROOM_CFRAME, 0.3)
    task.wait(0.3)
    humanoid.AutoRotate = true

    equipCombat()
    startAutoAttack()
    print("[Raid2] Đã TP vào phòng Boss, bắt đầu đánh Boss!")
end

local function main()
    monitorNotifications()

    isInRaid = checkIsInRaid()

    if isInRaid then
        print("[Raid2] Đang ở trong Raid Place!")
        updateStatus("Đang xử lý Raid 2")

        if not LocalPlayer.Character then
            LocalPlayer.CharacterAdded:Wait()
        end

        task.wait(3)

        moveSlightly()

        doDoorSequenceAndEnterBossRoom()

        while not raidFinished do
            task.wait(2)
        end
        print("[Raid2] Đã đánh xong Boss, đợi Teleport về...")

    else
        print("[Raid2] Đang ở Game mặc định. Bắt đầu logic Check Cooldown.")

        local function fireRaid()
            print("[Raid2] Bắn lệnh Create/Start để vào Raid 2 hoặc Check CD...")
            updateStatus("Đang Check Raid/Vào Raid")
            pcall(function()
                ReplicatedStorage.Events.Party:FireServer("Create", "Raid2")
            end)
            task.wait(1.5)
            pcall(function()
                ReplicatedStorage.Events.Party:FireServer("Start", "Raid2")
            end)
        end

        local lastResyncTime = os.time()

        fireRaid()
        task.wait(5)

        while task.wait(5) do
            if isTeleporting then
                -- Đang chuẩn bị bay vào Raid, đứng im
            else
                local remaining = getLocalCooldown()

                if remaining <= 30 then
                    print("[Raid2] Cooldown dưới 30s, Fire liên tục!")
                    fireRaid()
                else
                    updateStatus("Đang chờ CD (" .. remaining .. "s)")

                    if os.time() - lastResyncTime >= 30 then
                        print("[Raid2] Đã qua 30s, Fire để đồng bộ lại Cooldown!")
                        fireRaid()
                        lastResyncTime = os.time()
                    end
                end
            end
        end
    end
end

main()
