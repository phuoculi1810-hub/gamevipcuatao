local player = game:GetService("Players").LocalPlayer

local mobileGui = player.PlayerGui:FindFirstChild("Mobile")
local mobileButtons = mobileGui and mobileGui:FindFirstChild("MobileButtons")
local shiftLock = mobileButtons and mobileButtons:FindFirstChild("ShiftLock")

if shiftLock then
    print("Found ShiftLock, trying to activate...")
    
    -- Thu 1: Activate
    pcall(function() shiftLock:Activate() end)
    task.wait(0.2)
    
    -- Thu 2: firesignal
    pcall(function()
        firesignal(shiftLock.MouseButton1Click)
    end)
    task.wait(0.2)
    
    -- Thu 3: MouseButton1Down + Up
    pcall(function()
        firesignal(shiftLock.MouseButton1Down)
        task.wait(0.1)
        firesignal(shiftLock.MouseButton1Up)
    end)
    
    print("Done")
else
    print("ShiftLock not found")
end
