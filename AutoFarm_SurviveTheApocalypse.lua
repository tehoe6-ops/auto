-- ══════════════════════════════════════════════════════════════
--   Auto Farm | Survive the Apocalypse
--   Features: Auto Teleport, Auto Collect, GUI Toggle, Item Filter
--   วิธีใช้: รันผ่าน Executor (Synapse X / KRNL / Fluxus / ฯลฯ)
-- ══════════════════════════════════════════════════════════════

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

-- ─── Config (แก้ได้ตามต้องการ) ───────────────────────────────
local Config = {
    Enabled       = false,
    ItemFilter    = "Emerald", -- ชื่อ item ที่ต้องการ (เว้นว่าง = เก็บทุกอย่าง)
    TeleportDelay = 0.15, -- หน่วงเวลาระหว่าง teleport แต่ละครั้ง (วินาที)
    SearchRadius  = 3000, -- รัศมีสูงสุดในการค้นหา item
    CollectOffset = 2,    -- ระยะ offset เหนือ item เวลา teleport ไป
}

-- ─── ชื่อ Folder / Parent ที่มักเก็บ item ในเกม survival ──────
-- ปรับตาม workspace ของเกม Survive the Apocalypse จริงๆ ได้เลย
local ITEM_SEARCH_ROOTS = {
    workspace,
}

-- ─── Helper: ดึง Character ปัจจุบัน ─────────────────────────
local function getCharParts()
    local char = LocalPlayer.Character
    if not char then return nil, nil, nil end
    local hrp  = char:FindFirstChild("HumanoidRootPart")
    local hum  = char:FindFirstChild("Humanoid")
    return char, hrp, hum
end

-- ─── Helper: หาตำแหน่งของ object ────────────────────────────
local function getPosition(obj)
    if obj:IsA("BasePart") then
        return obj.Position
    elseif obj:IsA("Model") then
        if obj.PrimaryPart then return obj.PrimaryPart.Position end
        for _, d in ipairs(obj:GetDescendants()) do
            if d:IsA("BasePart") then return d.Position end
        end
    end
    return nil
end

-- ─── Helper: ตรวจว่า object เป็น item ที่ต้องการ ─────────────
local function isTargetItem(obj)
    -- ข้าม BasePart ที่เป็นส่วนของตัวละคร
    if Players:GetPlayerFromCharacter(obj)
    or Players:GetPlayerFromCharacter(obj.Parent) then
        return false
    end

    -- รับเฉพาะ Model หรือ BasePart ที่ไม่ใช่ map (CanCollide + ไม่ใหญ่เกินไป)
    if obj:IsA("BasePart") then
        if obj.Size.Magnitude > 40 then return false end  -- ข้ามส่วน map ขนาดใหญ่
    elseif not obj:IsA("Model") then
        return false
    end

    -- กรองชื่อ
    if Config.ItemFilter ~= "" then
        return obj.Name:lower():find(Config.ItemFilter:lower(), 1, true) ~= nil
    end

    return true
end

-- ─── หา item ที่ใกล้ที่สุด ────────────────────────────────────
local function findNearestItem(myPos)
    local nearest, nearestDist = nil, Config.SearchRadius

    for _, root in ipairs(ITEM_SEARCH_ROOTS) do
        for _, obj in ipairs(root:GetDescendants()) do
            if isTargetItem(obj) then
                local pos = getPosition(obj)
                if pos then
                    local dist = (myPos - pos).Magnitude
                    if dist < nearestDist then
                        nearest, nearestDist = obj, dist
                    end
                end
            end
        end
    end

    return nearest, nearestDist
end

-- ─── Teleport ─────────────────────────────────────────────────
local function teleportTo(hrp, pos)
    hrp.CFrame = CFrame.new(pos + Vector3.new(0, Config.CollectOffset, 0))
end

-- ─── Touch item (กระตุ้น Touched event) ──────────────────────
local function touchItem(hrp, obj)
    local pos = getPosition(obj)
    if pos then
        hrp.CFrame = CFrame.new(pos + Vector3.new(0, 1, 0))
    end
end

-- ─── Main Farm Loop ───────────────────────────────────────────
local farmConn = nil

local function startLoop()
    if farmConn then farmConn:Disconnect() end

    farmConn = RunService.Heartbeat:Connect(function()
        if not Config.Enabled then return end

        local _, hrp, hum = getCharParts()
        if not hrp or not hum or hum.Health <= 0 then return end

        local item = findNearestItem(hrp.Position)
        if item then
            local pos = getPosition(item)
            if pos then
                teleportTo(hrp, pos)
                task.wait(0.05)
                touchItem(hrp, item)
                task.wait(Config.TeleportDelay)
            end
        else
            task.wait(0.5) -- ไม่เจอ item พักรอสักครู่
        end
    end)
end

startLoop()

-- ─── GUI ──────────────────────────────────────────────────────
local function makeCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = parent
    return c
end

local function makeLabel(parent, text, pos, size, fontSize, color, xAlign)
    local l = Instance.new("TextLabel")
    l.Size             = size  or UDim2.new(1, -20, 0, 18)
    l.Position         = pos   or UDim2.new(0, 10, 0, 0)
    l.BackgroundTransparency = 1
    l.Text             = text
    l.TextColor3       = color or Color3.fromRGB(210, 210, 220)
    l.TextSize         = fontSize or 12
    l.Font             = Enum.Font.Gotham
    l.TextXAlignment   = xAlign or Enum.TextXAlignment.Left
    l.TextWrapped      = true
    l.Parent           = parent
    return l
end

-- ScreenGui
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name          = "AutoFarmGUI"
ScreenGui.ResetOnSpawn  = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent        = LocalPlayer:WaitForChild("PlayerGui")

-- Main Frame (Draggable)
local Frame = Instance.new("Frame")
Frame.Size              = UDim2.new(0, 290, 0, 260)
Frame.Position          = UDim2.new(0, 16, 0.5, -130)
Frame.BackgroundColor3  = Color3.fromRGB(15, 15, 22)
Frame.BorderSizePixel   = 0
Frame.Active            = true
Frame.Draggable         = true
Frame.Parent            = ScreenGui
makeCorner(Frame, 12)

-- Drop shadow (fake)
local Shadow = Instance.new("Frame")
Shadow.Size             = UDim2.new(1, 14, 1, 14)
Shadow.Position         = UDim2.new(0, -7, 0, 4)
Shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
Shadow.BackgroundTransparency = 0.65
Shadow.BorderSizePixel  = 0
Shadow.ZIndex           = Frame.ZIndex - 1
Shadow.Parent           = Frame
makeCorner(Shadow, 16)

-- Title Bar
local TitleBar = Instance.new("Frame")
TitleBar.Size           = UDim2.new(1, 0, 0, 38)
TitleBar.BackgroundColor3 = Color3.fromRGB(30, 80, 200)
TitleBar.BorderSizePixel = 0
TitleBar.Parent         = Frame
makeCorner(TitleBar, 12)

-- patch corners ด้านล่างของ TitleBar ให้เป็นสี่เหลี่ยม
local TitlePatch = Instance.new("Frame")
TitlePatch.Size         = UDim2.new(1, 0, 0.5, 0)
TitlePatch.Position     = UDim2.new(0, 0, 0.5, 0)
TitlePatch.BackgroundColor3 = Color3.fromRGB(30, 80, 200)
TitlePatch.BorderSizePixel = 0
TitlePatch.Parent       = TitleBar

Instance.new("TextLabel", TitleBar).BackgroundTransparency = 1
local TitleLbl = makeLabel(TitleBar, "Auto Farm  |  Survive the Apocalypse",
    UDim2.new(0, 10, 0, 0), UDim2.new(1, -10, 1, 0), 13,
    Color3.fromRGB(255, 255, 255), Enum.TextXAlignment.Left)
TitleLbl.Font = Enum.Font.GothamBold

-- ── Filter Input ──
makeLabel(Frame, "Filter ชื่อ Item  (เว้นว่าง = เก็บทั้งหมด)",
    UDim2.new(0, 10, 0, 46), UDim2.new(1, -20, 0, 16), 11)

local FilterBox = Instance.new("TextBox")
FilterBox.Size              = UDim2.new(1, -20, 0, 30)
FilterBox.Position          = UDim2.new(0, 10, 0, 64)
FilterBox.BackgroundColor3  = Color3.fromRGB(28, 28, 40)
FilterBox.BorderSizePixel   = 0
FilterBox.Text              = "Emerald"
FilterBox.PlaceholderText   = "เช่น: Emerald, medkit, ammo ..."
FilterBox.TextColor3        = Color3.fromRGB(255, 255, 255)
FilterBox.PlaceholderColor3 = Color3.fromRGB(100, 100, 115)
FilterBox.TextSize          = 13
FilterBox.Font              = Enum.Font.Gotham
FilterBox.ClearTextOnFocus  = false
FilterBox.Parent            = Frame
makeCorner(FilterBox, 7)

FilterBox:GetPropertyChangedSignal("Text"):Connect(function()
    Config.ItemFilter = FilterBox.Text
end)

-- ── Delay Input ──
makeLabel(Frame, "Teleport Delay (วินาที, ต่ำสุด 0.05)",
    UDim2.new(0, 10, 0, 104), UDim2.new(1, -20, 0, 16), 11)

local DelayBox = Instance.new("TextBox")
DelayBox.Size              = UDim2.new(1, -20, 0, 30)
DelayBox.Position          = UDim2.new(0, 10, 0, 122)
DelayBox.BackgroundColor3  = Color3.fromRGB(28, 28, 40)
DelayBox.BorderSizePixel   = 0
DelayBox.Text              = tostring(Config.TeleportDelay)
DelayBox.TextColor3        = Color3.fromRGB(255, 255, 255)
DelayBox.TextSize          = 13
DelayBox.Font              = Enum.Font.Gotham
DelayBox.ClearTextOnFocus  = false
DelayBox.Parent            = Frame
makeCorner(DelayBox, 7)

DelayBox.FocusLost:Connect(function()
    local v = tonumber(DelayBox.Text)
    if v and v >= 0.05 then
        Config.TeleportDelay = v
    else
        DelayBox.Text = tostring(Config.TeleportDelay)
    end
end)

-- ── Status Label ──
local StatusLbl = makeLabel(Frame, "สถานะ: หยุดทำงาน",
    UDim2.new(0, 10, 0, 162), UDim2.new(1, -20, 0, 16), 11,
    Color3.fromRGB(180, 180, 190), Enum.TextXAlignment.Center)

-- ── Toggle Button ──
local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size             = UDim2.new(1, -20, 0, 40)
ToggleBtn.Position         = UDim2.new(0, 10, 0, 182)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 170, 80)
ToggleBtn.BorderSizePixel  = 0
ToggleBtn.Text             = "START AUTO FARM"
ToggleBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
ToggleBtn.TextSize         = 15
ToggleBtn.Font             = Enum.Font.GothamBold
ToggleBtn.Parent           = Frame
makeCorner(ToggleBtn, 10)

-- Hover effect
ToggleBtn.MouseEnter:Connect(function()
    TweenService:Create(ToggleBtn, TweenInfo.new(0.15), {
        BackgroundTransparency = 0.2
    }):Play()
end)
ToggleBtn.MouseLeave:Connect(function()
    TweenService:Create(ToggleBtn, TweenInfo.new(0.15), {
        BackgroundTransparency = 0
    }):Play()
end)

-- Toggle logic
ToggleBtn.MouseButton1Click:Connect(function()
    Config.Enabled = not Config.Enabled

    if Config.Enabled then
        ToggleBtn.Text             = "STOP AUTO FARM"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
        StatusLbl.Text             = "สถานะ: กำลังทำงาน..."
        StatusLbl.TextColor3       = Color3.fromRGB(80, 220, 100)
    else
        ToggleBtn.Text             = "START AUTO FARM"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 170, 80)
        StatusLbl.Text             = "สถานะ: หยุดทำงาน"
        StatusLbl.TextColor3       = Color3.fromRGB(180, 180, 190)
    end
end)

-- ── Footer ──
makeLabel(Frame, "ลาก GUI ได้  |  by Roblox Pro",
    UDim2.new(0, 0, 1, -20), UDim2.new(1, 0, 0, 18), 10,
    Color3.fromRGB(80, 80, 100), Enum.TextXAlignment.Center)

-- ── อัปเดต status ทุก 0.5 วิ แสดง item ที่เจอ ──
task.spawn(function()
    while task.wait(0.5) do
        if Config.Enabled then
            local _, hrp = getCharParts()
            if hrp then
                local item, dist = findNearestItem(hrp.Position)
                if item then
                    StatusLbl.Text = ("กำลังเก็บ: %s  (%.0f studs)"):format(item.Name, dist)
                else
                    StatusLbl.Text = "กำลังหา item... (ไม่พบในรัศมี)"
                end
            end
        end
    end
end)

print("[AutoFarm] โหลดสำเร็จ! กดปุ่ม START AUTO FARM เพื่อเริ่มเก็บของ")
