local player = game:GetService("Players").LocalPlayer

-- ==========================================
-- HỆ THỐNG AUTO BUY VEST 80KG CHÍNH XÁC
-- ==========================================
local function autoBuyVest80KG()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ClickDetector") or obj:IsA("ProximityPrompt") then
            -- Chuyển tên về dạng chữ thường để so sánh
            local itemName = string.lower(obj.Parent.Name)
            
            -- Logic: Phải chứa từ "vest" VÀ chứa con số "80"
            -- Dù tên là "Vest 80KG" hay "80KG Vest" script vẫn bắt được
            if string.find(itemName, "vest") and string.find(itemName, "80") then
                
                -- Tìm phần tử basepart để lấy vị trí
                local pos = (obj.Parent:IsA("BasePart") and obj.Parent.Position) 
                            or (obj.Parent:FindFirstChildWhichIsA("BasePart") and obj.Parent:FindFirstChildWhichIsA("BasePart").Position)
                
                -- Khoảng cách an toàn 20 mét
                if pos and (hrp.Position - pos).Magnitude < 20 then
                    if obj:IsA("ClickDetector") then
                        fireclickdetector(obj)
                    else
                        fireproximityprompt(obj)
                    end
                    print("💰 Đã mua thành công Vest 80KG:", obj.Parent.Name)
                end
            end
        end
    end
end

-- Vòng lặp chạy mỗi 0.5 giây
task.spawn(function()
    while task.wait(0.5) do
        autoBuyVest80KG()
    end
end)

print("✅ Đã kích hoạt Auto Buy [Vest 80KG].")