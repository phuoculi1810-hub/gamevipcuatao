-- =============================================================================
-- 💪 PULLUP CHECK SCRIPT - Kiểm tra trạng thái trên máy PullUp với timeout 60s
-- =============================================================================

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ============================================================================
-- ⚙️ CONFIG
-- ============================================================================
local TIMEOUT_SECONDS = 60  -- Timeout 60s nếu không ở trên pullup

-- ============================================================================
-- 🔁 STATE FLAGS
-- ============================================================================
local isOnPullup = false
local lastTimeOnPullup = os.time()
local pullupGui = nil

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

local function hopServer()
    print("🔀 Hop server do timeout pullup...")
    local TeleportService = game:GetService("TeleportService")
    local HttpService = game:GetService("HttpService")
    local placeId = game.PlaceId
    local currentServerId = game.JobId
    
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
    
    TeleportService:Teleport(placeId, player)
end

-- ============================================================================
-- 📊 PULLUP STATUS CHECK
-- ============================================================================

local function checkPullupStatus()
    pullupGui = playerGui:FindFirstChild("PullupGain")
    if not pullupGui then
        return false
    end
    
    -- Kiểm tra xem có Frame nào đang visible không
    for _, frame in pairs(pullupGui:GetDescendants()) do
        if frame:IsA("Frame") and frame.Visible then
            return true
        end
    end
    
    return false
end

-- ============================================================================
-- 🔄 MAIN MONITOR LOOP
-- ============================================================================

print("💪 Pullup Check Script đang khởi động...")
print("⏱️ Timeout:", TIMEOUT_SECONDS, "giây")

task.spawn(function()
    while task.wait(1) do
        local currentlyOnPullup = checkPullupStatus()
        
        if currentlyOnPullup then
            if not isOnPullup then
                print("✅ Đã lên máy PullUp")
            end
            isOnPullup = true
            lastTimeOnPullup = os.time()
        else
            if isOnPullup then
                print("❌ Đã rời máy PullUp")
            end
            isOnPullup = false
            
            -- Kiểm tra timeout
            local timeSinceLastOnPullup = os.time() - lastTimeOnPullup
            if timeSinceLastOnPullup >= TIMEOUT_SECONDS then
                print("⏱️ Timeout! Không ở trên PullUp quá", TIMEOUT_SECONDS, "giây")
                
                -- Nếu có incombat thì đợi hết rồi hop
                if isInCombat() then
                    print("⚔️ Đang InCombat → Đợi hết combat...")
                    waitForCombatEnd()
                end
                
                print("🔀 Hop server...")
                hopServer()
                break
            else
                local remaining = TIMEOUT_SECONDS - timeSinceLastOnPullup
                if remaining % 10 == 0 then  -- Print mỗi 10s
                    print("⏱️ Còn", remaining, "giây trước khi hop...")
                end
            end
        end
    end
end)

print("✅ Pullup Check Script đã chạy!")
