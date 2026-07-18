-- [[ AUTO RAID 1 LOGIC ]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
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

-- Cooldown lưu local (không còn dùng server Railway nữa)
local localCooldown = 0        -- số giây còn lại
local lastCooldownUpdate = 0   -- os.time() lúc set cooldown gần nhất

local function setLocalCooldown(seconds)
    localCooldown = seconds + 15 -- +15s buffer giống code cũ
    lastCooldownUpdate = os.time()
    
    -- Send to Railway
    pcall(function()
        HttpService:RequestAsync({
            Url = RAILWAY_URL .. "/api/state/" .. ACCOUNT_ID .. "/cooldown",
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = HttpService:JSONEncode({ raid = "raid1", seconds = seconds })
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
    print("[Raid1 Status] " .. statusMsg)
    
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

-- 2. Đọc chuỗi thời gian cooldown "1 hour(s) 34 minute(s) 15 second(s)"
local function parseCooldown(text)
    local hours = string.match(text, "(%d+) hour") or 0
    local minutes = string.match(text, "(%d+) minute") or 0
    local seconds = string.match(text, "(%d+) second") or 0
    return (tonumber(hours) * 3600) + (tonumber(minutes) * 60) + tonumber(seconds)
end

-- Bỏ tag màu kiểu <Color=Green>...<Color=/> ra khỏi thông báo
local function stripColorTags(text)
    if not text then return "" end
    text = string.gsub(text, "<Color=[^>]->", "")
    text = string.gsub(text, "<Color/=?>", "")
    return text
end

-- 3. Hàm xử lý trong Raid
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
            print("[Raid1] Đã tự động trang bị vũ khí:", item.Name)
            return
        end
    end
    print("[Raid1] Cảnh báo: Không tìm thấy Combat nào hợp lệ trong Backpack!")
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

    print("[Raid1] Đã nhích khỏi safezone!")
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

-- Lấy số giây delay từ câu thông báo, VD "starting in 5 seconds" -> 5
local function parseWaitSeconds(text)
    local sec = string.match(text, "in (%d+) second")
    if sec then return tonumber(sec) end
    return nil
end

-- 4. Bắt thông báo qua ReplicatedStorage.NotifyEvent (thay cho scan TextLabel)
local function monitorNotifications()

    local function handleText(rawText, duration)
        if not rawText or rawText == "" then return end
        local cleaned = stripColorTags(rawText)
        local text = string.lower(cleaned)

        if string.find(text, "you can't create this raid") or string.find(text, "you can't start this raid") then
            local cdSeconds = parseCooldown(text)
            setLocalCooldown(cdSeconds)
            updateStatus("Đang chờ Cooldown (" .. cdSeconds .. "s)")
            print("[Raid1] Đã lưu Cooldown mới (local): ", cdSeconds, "giây")

        elseif string.find(text, "teleporting to the raid") then
            isTeleporting = true
            updateStatus("Teleporting Raid")
            print("[Raid1] Chuẩn bị vào raid, đã khóa vòng lặp Fire...")

        elseif string.find(text, "boss has been defeated") then
            updateStatus("Đã tiêu diệt Boss! Raid hoàn thành.")
            print("[Raid1] Boss đã chết! Raid xong.")
            stopAutoAttack()
            raidFinished = true

        elseif string.find(text, "teleporting back") then
            updateStatus("Teleporting Back")
            print("[Raid1] Đang teleport về sảnh...")

        elseif string.find(text, "wave has been cleared") then
            -- VD: "Wave has been cleared! Next wave is starting in 5 seconds."
            local waitSec = parseWaitSeconds(text) or duration or 5

            stopAutoAttack() -- Dừng click ngay khi wave đã sạch
            updateStatus("Đã dọn sạch Wave, chờ " .. waitSec .. "s sang Wave tiếp theo")
            print("[Raid1] Wave cleared, dừng click, đợi " .. waitSec .. "s...")

            task.delay(waitSec, function()
                if not raidFinished then
                    startAutoAttack() -- Click lại khi wave tiếp theo bắt đầu
                    print("[Raid1] Hết thời gian chờ, click lại!")
                end
            end)

        elseif string.find(text, "wave") and string.find(text, "starting") then
            -- VD: "Wave 10 is starting." hoặc "Wave 3 is starting."
            local waveNum = string.match(text, "wave (%d+)")
            if waveNum then
                if tonumber(waveNum) == 10 then
                    updateStatus("Wave 10 - BOSS bắt đầu!")
                    print("[Raid1] Wave 10 (Boss) bắt đầu!")
                else
                    updateStatus("Đang bắt đầu Wave " .. waveNum)
                    print("[Raid1] Wave " .. waveNum .. " bắt đầu.")
                end
            else
                updateStatus(cleaned)
                print("[Raid1] Thông báo: ", cleaned)
            end
        end
    end

    -- Hook chính: NotifyEvent (thông báo raid thật sự đi qua đây)
    pcall(function()
        local NotifyEvent = ReplicatedStorage:WaitForChild("NotifyEvent")
        NotifyEvent.OnClientEvent:Connect(function(msg, duration)
            handleText(msg, duration)
        end)
        print("[Raid1] Đã hook thành công NotifyEvent.OnClientEvent")
    end)
end

-- Cách kiểm tra đang ở trong Raid hay Game mặc định
local function checkIsInRaid()
    local playersCount = #Players:GetPlayers()

    if playersCount <= 1 then
        return true
    else
        return false
    end
end

-- 5. KHỞI ĐỘNG LOGIC
local function main()
    monitorNotifications()

    isInRaid = checkIsInRaid()

    if isInRaid then
        print("[Raid1] Đang ở trong Raid Place!")
        updateStatus("Đang đánh Raid Boss")

        if not LocalPlayer.Character then
            LocalPlayer.CharacterAdded:Wait()
        end

        task.wait(3)

        moveSlightly()
        equipCombat()
        startAutoAttack()

        while not raidFinished do
            task.wait(2)
        end
        print("[Raid1] Đã đánh xong Boss, đợi Teleport về...")

    else
        print("[Raid1] Đang ở Game mặc định. Bắt đầu logic Check Cooldown.")

        local function fireRaid()
            print("[Raid1] Bắn lệnh Create/Start để vào Raid hoặc Check CD...")
            updateStatus("Đang Check Raid/Vào Raid")
            pcall(function()
                ReplicatedStorage.Events.Party:FireServer("Create", "Raid1")
            end)
            task.wait(1.5)
            pcall(function()
                ReplicatedStorage.Events.Party:FireServer("Start", "Raid1")
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
                    print("[Raid1] Cooldown dưới 30s, Fire liên tục!")
                    fireRaid()
                else
                    updateStatus("Đang chờ CD (" .. remaining .. "s)")

                    if os.time() - lastResyncTime >= 30 then
                        print("[Raid1] Đã qua 30s, Fire để đồng bộ lại Cooldown!")
                        fireRaid()
                        lastResyncTime = os.time()
                    end
                end
            end
        end
    end
end

-- Chạy Script
main()
