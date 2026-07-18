-- Test click pullup theo đúng logic script_asura_dich_mahoa.lua
local player = game:GetService("Players").LocalPlayer
local VIM = game:GetService("VirtualInputManager")
local hrp = player.Character:WaitForChild("HumanoidRootPart")
local pGui = player.PlayerGui

-- Tìm máy gần nhất có Center + ClickDetector (y chang script_asura)
local best, bestD = nil, math.huge
for _, obj in ipairs(workspace.Trainings["Pull-ups"]:GetChildren()) do
    if obj:IsA("Model") and obj:FindFirstChild("Center") and obj:FindFirstChild("ClickDetector") then
        local d = (hrp.Position - obj.Center.Position).Magnitude
        print("Found: "..obj.Name.." dist:"..math.floor(d))
        if d < bestD then bestD=d; best=obj end
    end
end

if not best then
    print("Không tìm thấy máy có Center!")
    -- Thử không cần Center
    for _, obj in ipairs(workspace.Trainings["Pull-ups"]:GetChildren()) do
        if obj:IsA("Model") and obj:FindFirstChild("ClickDetector") then
            local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            if part then
                local d = (hrp.Position - part.Position).Magnitude
                print("No-Center Found: "..obj.Name.." dist:"..math.floor(d))
                if d < bestD then bestD=d; best=obj end
            end
        end
    end
end

if not best then print("Vẫn không tìm thấy!"); return end

print("Chọn: "..best.Name)
fireclickdetector(best.ClickDetector)
task.wait(1)

-- Check UI
local ui = pGui:FindFirstChild("PullupGain")
print("PullupGain: "..(ui and tostring(ui.Enabled) or "nil"))
if not ui or not ui.Enabled then print("UI không hiện!"); return end

local frame = ui:FindFirstChild("Frame")
local durBtn = frame and frame:FindFirstChild("Durability")

-- Thử getconnections để lấy callback của button
local conns = getconnections and getconnections(durBtn.MouseButton1Click)
if conns then
    print("Connections trên MouseButton1Click: "..#conns)
    for i, c in ipairs(conns) do
        print("  ["..i.."] enabled="..tostring(c.Enabled).." func="..tostring(c.Function))
        -- Gọi thẳng function
        local ok, err = pcall(c.Function)
        print("  Call result: "..tostring(ok).." "..tostring(err))
    end
else
    print("getconnections không khả dụng, thử Activated...")
    local conns2 = getconnections and getconnections(durBtn.Activated)
    if conns2 then
        print("Connections trên Activated: "..#conns2)
        for i, c in ipairs(conns2) do
            local ok, err = pcall(c.Function)
            print("  ["..i.."] Call: "..tostring(ok).." "..tostring(err))
        end
    else
        print("getconnections không có!")
    end
end

task.wait(0.5)
local frame2 = ui:FindFirstChild("Frame2")
print("Frame2 visible: "..tostring(frame2 and frame2.Visible))
