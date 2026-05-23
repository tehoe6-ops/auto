-- ══════════════════════════════════════════════════════════════
--   Auto Fuel Farm | Survive the Apocalypse
--   Flow: วาปไปโซน Fuel → แม่เหล็กดูด Fuel มาหาตัว → กด F เก็บ → วาปไป Generator
-- ══════════════════════════════════════════════════════════════

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local VIM          = game:GetService("VirtualInputManager")

local LocalPlayer  = Players.LocalPlayer

-- ─── Config ───────────────────────────────────────────────────
local Config = {
    Enabled        = false,
    FuelName       = "Fuel",
    GeneratorName  = "Generator",
    MagnetRadius   = 60,    -- รัศมีแม่เหล็กดูด fuel (studs)
    MagnetTime     = 4,     -- ดูดนานกี่วินาที
    MagnetSpeed    = 0.05,  -- อัปเดตทุกกี่วิ (ยิ่งต่ำยิ่งเร็ว)
    TeleportDelay  = 0.4,
    ActionDelay    = 0.5,
}

-- ─── States ───────────────────────────────────────────────────
local S = {
    IDLE      = { text = "รอเริ่มต้น",                   color = Color3.fromRGB(120,120,135) },
    GO_FUEL   = { text = "วาปไปโซน Fuel",                color = Color3.fromRGB(80,180,255)  },
    MAGNET    = { text = "แม่เหล็กดูด Fuel...",          color = Color3.fromRGB(255,180,40)  },
    COLLECT   = { text = "กด F เก็บ Fuel",               color = Color3.fromRGB(80,220,120)  },
    GO_GEN    = { text = "วาปไปเครื่องปั่นไฟ",           color = Color3.fromRGB(180,100,255) },
    WAIT_GEN  = { text = "ถึงเครื่องปั่นไฟแล้ว รอรอบถัดไป", color = Color3.fromRGB(80,220,120) },
    NO_FUEL   = { text = "ไม่พบ Fuel ในแมป รอ...",       color = Color3.fromRGB(220,80,80)   },
    NO_GEN    = { text = "ไม่พบเครื่องปั่นไฟ",           color = Color3.fromRGB(220,80,80)   },
    DEAD      = { text = "ตาย รอ respawn...",             color = Color3.fromRGB(180,50,50)   },
}

local StatusText, StatusBox, InfoLabel, CountLabel
local cycleCount = 0

local function setState(s)
    if StatusText then
        StatusText.Text       = s.text
        StatusText.TextColor3 = s.color
    end
    if StatusBox then
        local r,g,b = s.color.R*0.13, s.color.G*0.13, s.color.B*0.13
        TweenService:Create(StatusBox, TweenInfo.new(0.2), {
            BackgroundColor3 = Color3.new(r,g,b)
        }):Play()
    end
end

-- ─── Helpers ──────────────────────────────────────────────────
local function getCharParts()
    local c = LocalPlayer.Character
    if not c then return nil,nil,nil end
    return c, c:FindFirstChild("HumanoidRootPart"), c:FindFirstChild("Humanoid")
end

local function getPos(obj)
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Model") then
        if obj.PrimaryPart then return obj.PrimaryPart.Position end
        for _, d in ipairs(obj:GetDescendants()) do
            if d:IsA("BasePart") then return d.Position end
        end
    end
    return nil
end

local function teleportTo(hrp, pos)
    hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
end

local function pressKey(key)
    VIM:SendKeyEvent(true,  key, false, game)
    task.wait(0.08)
    VIM:SendKeyEvent(false, key, false, game)
end

local function openBackpack()
    for _, g in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
        if (g:IsA("TextButton") or g:IsA("ImageButton"))
        and g.Name:lower():find("backpack",1,true) then
            g:activate()
            task.wait(0.2)
            return
        end
    end
    pressKey(Enum.KeyCode.Tab)
    task.wait(0.2)
end

-- ─── หา Fuel ทั้งหมด ──────────────────────────────────────────
local function findAllFuels()
    local list = {}
    local kw = Config.FuelName:lower()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:lower() == kw
        and not Players:GetPlayerFromCharacter(obj) then
            table.insert(list, obj)
        end
    end
    return list
end

-- ─── หา Generator ─────────────────────────────────────────────
local function findGenerator(myPos)
    local kw = Config.GeneratorName:lower()
    local best, bestD = nil, math.huge
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:lower():find(kw,1,true)
        and not Players:GetPlayerFromCharacter(obj) then
            local pos = getPos(obj)
            if pos then
                local d = (myPos - pos).Magnitude
                if d < bestD then best, bestD = obj, d end
            end
        end
    end
    return best
end

-- ─── หา Fuel ที่ใกล้ที่สุด ────────────────────────────────────
local function findNearestFuel(myPos)
    local fuels = findAllFuels()
    local best, bestD = nil, math.huge
    for _, f in ipairs(fuels) do
        local pos = getPos(f)
        if pos then
            local d = (myPos - pos).Magnitude
            if d < bestD then best, bestD = f, d end
        end
    end
    return best
end

-- ─── แม่เหล็กดูด Fuel มาหาตัว ────────────────────────────────
-- ย้าย Model ของ Fuel ให้มาอยู่รอบๆ ตัวละคร
local function runMagnet(hrp, duration)
    local endTime = tick() + duration
    local fuelCount = 0
    local angle = 0

    while tick() < endTime and Config.Enabled do
        fuelCount = 0
        local fuels = findAllFuels()

        for _, fuel in ipairs(fuels) do
            local fpos = getPos(fuel)
            if fpos and (hrp.Position - fpos).Magnitude <= Config.MagnetRadius then
                -- วางรอบๆ ตัวละครเป็นวงกลม ไม่ซ้อนกัน
                angle = angle + 0.4
                local offset = Vector3.new(
                    math.cos(angle) * 2,
                    0,
                    math.sin(angle) * 2
                )
                local target = hrp.Position + offset

                -- ย้าย Model ทั้งก้อน
                if fuel.PrimaryPart then
                    fuel:SetPrimaryPartCFrame(CFrame.new(target))
                else
                    for _, part in ipairs(fuel:GetDescendants()) do
                        if part:IsA("BasePart") then
                            part.CFrame = CFrame.new(target)
                        end
                    end
                end

                fuelCount += 1
            end
        end

        if InfoLabel then
            local remaining = math.max(0, math.ceil(endTime - tick()))
            InfoLabel.Text = ("แม่เหล็ก: ดูด %d Fuel  |  เหลือ %ds"):format(fuelCount, remaining)
        end

        task.wait(Config.MagnetSpeed)
    end
end

-- ─── Main Loop ────────────────────────────────────────────────
local farmThread = nil

local function stopFarm()
    if farmThread then task.cancel(farmThread) farmThread = nil end
    Config.Enabled = false
    setState(S.IDLE)
    if InfoLabel then InfoLabel.Text = "" end
end

local function startFarm()
    stopFarm()
    Config.Enabled = true
    cycleCount = 0

    farmThread = task.spawn(function()
        while Config.Enabled do
            local _, hrp, hum = getCharParts()
            if not hrp or not hum or hum.Health <= 0 then
                setState(S.DEAD)
                task.wait(2)
                continue
            end

            -- ── 1. หา Fuel ที่ใกล้ที่สุด แล้ววาปไป ──────────
            setState(S.GO_FUEL)
            local nearFuel = findNearestFuel(hrp.Position)
            if not nearFuel then
                setState(S.NO_FUEL)
                task.wait(3)
                continue
            end

            local fpos = getPos(nearFuel)
            if fpos then
                teleportTo(hrp, fpos)
                task.wait(Config.TeleportDelay)
            end

            -- ── 2. เปิด Backpack ──────────────────────────────
            openBackpack()

            -- ── 3. แม่เหล็กดูด Fuel มาหาตัว ──────────────────
            setState(S.MAGNET)
            local _, hrp2 = getCharParts()
            if not hrp2 then task.wait(1) continue end

            runMagnet(hrp2, Config.MagnetTime) -- ดูดนาน X วิ

            -- ── 4. กด F เก็บ Fuel ────────────────────────────
            setState(S.COLLECT)
            for i = 1, 5 do -- กด F หลายครั้งเพื่อให้แน่ใจ
                pressKey(Enum.KeyCode.F)
                task.wait(0.2)
            end
            task.wait(Config.ActionDelay)

            -- ── 5. วาปไป Generator ────────────────────────────
            local _, hrp3, hum3 = getCharParts()
            if not hrp3 or not hum3 or hum3.Health <= 0 then
                task.wait(1) continue
            end

            setState(S.GO_GEN)
            local gen = findGenerator(hrp3.Position)
            if not gen then
                setState(S.NO_GEN)
                task.wait(3)
                continue
            end

            local gpos = getPos(gen)
            if gpos then
                teleportTo(hrp3, gpos)
                task.wait(Config.TeleportDelay)
            end

            -- ── 6. ถึง Generator แล้ว (ผู้เล่นกด F เอง) ───────
            setState(S.WAIT_GEN)
            if InfoLabel then InfoLabel.Text = "ถึง Generator แล้ว! กด F ใส่ Fuel ได้เลย" end

            cycleCount += 1
            if CountLabel then
                CountLabel.Text = ("ทำไปแล้ว: %d รอบ"):format(cycleCount)
            end

            task.wait(4) -- รอให้ผู้เล่นใส่ fuel เอง ก่อนวนรอบถัดไป
        end
    end)
end

-- ─── GUI ──────────────────────────────────────────────────────
local function corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = p
end

local gui = Instance.new("ScreenGui")
gui.Name = "FuelFarmGUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local Frame = Instance.new("Frame")
Frame.Size             = UDim2.new(0, 310, 0, 390)
Frame.Position         = UDim2.new(0, 16, 0.5, -195)
Frame.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
Frame.BorderSizePixel  = 0
Frame.Active           = true
Frame.Draggable        = true
Frame.Parent           = gui
corner(Frame, 14)

local Shad = Instance.new("Frame")
Shad.Size = UDim2.new(1,16,1,16)
Shad.Position = UDim2.new(0,-8,0,6)
Shad.BackgroundColor3 = Color3.new(0,0,0)
Shad.BackgroundTransparency = 0.6
Shad.BorderSizePixel = 0
Shad.ZIndex = Frame.ZIndex - 1
Shad.Parent = Frame
corner(Shad, 18)

-- Title
local Title = Instance.new("Frame")
Title.Size = UDim2.new(1,0,0,42)
Title.BackgroundColor3 = Color3.fromRGB(25,90,210)
Title.BorderSizePixel = 0
Title.Parent = Frame
corner(Title, 14)

local TFix = Instance.new("Frame")
TFix.Size = UDim2.new(1,0,0.5,0)
TFix.Position = UDim2.new(0,0,0.5,0)
TFix.BackgroundColor3 = Color3.fromRGB(25,90,210)
TFix.BorderSizePixel = 0
TFix.Parent = Title

local TitleLbl = Instance.new("TextLabel")
TitleLbl.Size = UDim2.new(1,-12,0,22)
TitleLbl.Position = UDim2.new(0,12,0,3)
TitleLbl.BackgroundTransparency = 1
TitleLbl.Text = "Fuel Auto Farm  |  Magnet Mode"
TitleLbl.TextColor3 = Color3.new(1,1,1)
TitleLbl.Font = Enum.Font.GothamBold
TitleLbl.TextSize = 14
TitleLbl.TextXAlignment = Enum.TextXAlignment.Left
TitleLbl.Parent = Title

local SubLbl = Instance.new("TextLabel")
SubLbl.Size = UDim2.new(1,-12,0,13)
SubLbl.Position = UDim2.new(0,12,0,25)
SubLbl.BackgroundTransparency = 1
SubLbl.Text = "Survive the Apocalypse"
SubLbl.TextColor3 = Color3.fromRGB(170,195,255)
SubLbl.Font = Enum.Font.Gotham
SubLbl.TextSize = 10
SubLbl.TextXAlignment = Enum.TextXAlignment.Left
SubLbl.Parent = Title

-- Status Box
local SBox = Instance.new("Frame")
SBox.Size = UDim2.new(1,-20,0,60)
SBox.Position = UDim2.new(0,10,0,52)
SBox.BackgroundColor3 = Color3.fromRGB(20,20,30)
SBox.BorderSizePixel = 0
SBox.Parent = Frame
corner(SBox, 10)
StatusBox = SBox

local STitle = Instance.new("TextLabel")
STitle.Size = UDim2.new(1,-10,0,16)
STitle.Position = UDim2.new(0,10,0,3)
STitle.BackgroundTransparency = 1
STitle.Text = "สถานะปัจจุบัน"
STitle.TextColor3 = Color3.fromRGB(80,80,100)
STitle.Font = Enum.Font.Gotham
STitle.TextSize = 10
STitle.TextXAlignment = Enum.TextXAlignment.Left
STitle.Parent = SBox

local STxt = Instance.new("TextLabel")
STxt.Size = UDim2.new(1,-20,0,30)
STxt.Position = UDim2.new(0,10,0,18)
STxt.BackgroundTransparency = 1
STxt.Text = S.IDLE.text
STxt.TextColor3 = S.IDLE.color
STxt.Font = Enum.Font.GothamBold
STxt.TextSize = 14
STxt.TextXAlignment = Enum.TextXAlignment.Left
STxt.TextWrapped = true
STxt.Parent = SBox
StatusText = STxt

-- Info label (แม่เหล็ก progress)
local ILbl = Instance.new("TextLabel")
ILbl.Size = UDim2.new(1,-20,0,16)
ILbl.Position = UDim2.new(0,10,0,120)
ILbl.BackgroundTransparency = 1
ILbl.Text = ""
ILbl.TextColor3 = Color3.fromRGB(255,200,60)
ILbl.Font = Enum.Font.GothamBold
ILbl.TextSize = 11
ILbl.TextXAlignment = Enum.TextXAlignment.Left
ILbl.Parent = Frame
InfoLabel = ILbl

local CLbl = Instance.new("TextLabel")
CLbl.Size = UDim2.new(1,-20,0,14)
CLbl.Position = UDim2.new(0,10,0,138)
CLbl.BackgroundTransparency = 1
CLbl.Text = "ทำไปแล้ว: 0 รอบ"
CLbl.TextColor3 = Color3.fromRGB(130,130,150)
CLbl.Font = Enum.Font.Gotham
CLbl.TextSize = 11
CLbl.TextXAlignment = Enum.TextXAlignment.Left
CLbl.Parent = Frame
CountLabel = CLbl

-- Input helper
local function makeInput(labelTxt, placeholder, default, yPos, onChange)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1,-20,0,14)
    lbl.Position = UDim2.new(0,10,0,yPos)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelTxt
    lbl.TextColor3 = Color3.fromRGB(150,150,170)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = Frame

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1,-20,0,28)
    box.Position = UDim2.new(0,10,0,yPos+16)
    box.BackgroundColor3 = Color3.fromRGB(22,22,34)
    box.BorderSizePixel = 0
    box.Text = default
    box.PlaceholderText = placeholder
    box.TextColor3 = Color3.new(1,1,1)
    box.PlaceholderColor3 = Color3.fromRGB(80,80,100)
    box.Font = Enum.Font.Gotham
    box.TextSize = 13
    box.ClearTextOnFocus = false
    box.Parent = Frame
    corner(box, 7)
    box:GetPropertyChangedSignal("Text"):Connect(function() onChange(box.Text) end)
end

makeInput("ชื่อ Model Fuel", "Fuel", Config.FuelName, 162,
    function(v) Config.FuelName = v end)

makeInput("ชื่อ Model Generator", "Generator", Config.GeneratorName, 210,
    function(v) Config.GeneratorName = v end)

makeInput("รัศมีแม่เหล็ก (studs)", "60", tostring(Config.MagnetRadius), 258,
    function(v) local n=tonumber(v) if n and n>0 then Config.MagnetRadius=n end end)

makeInput("เวลาดูด Fuel (วินาที)", "4", tostring(Config.MagnetTime), 306,
    function(v) local n=tonumber(v) if n and n>=1 then Config.MagnetTime=n end end)

-- Toggle button
local Btn = Instance.new("TextButton")
Btn.Size = UDim2.new(1,-20,0,40)
Btn.Position = UDim2.new(0,10,0,348)
Btn.BackgroundColor3 = Color3.fromRGB(35,160,75)
Btn.BorderSizePixel = 0
Btn.Text = "START"
Btn.TextColor3 = Color3.new(1,1,1)
Btn.Font = Enum.Font.GothamBold
Btn.TextSize = 16
Btn.Parent = Frame
corner(Btn, 10)

Btn.MouseEnter:Connect(function()
    TweenService:Create(Btn,TweenInfo.new(0.15),{BackgroundTransparency=0.2}):Play()
end)
Btn.MouseLeave:Connect(function()
    TweenService:Create(Btn,TweenInfo.new(0.15),{BackgroundTransparency=0}):Play()
end)
Btn.MouseButton1Click:Connect(function()
    if Config.Enabled then
        stopFarm()
        Btn.Text = "START"
        Btn.BackgroundColor3 = Color3.fromRGB(35,160,75)
    else
        startFarm()
        Btn.Text = "STOP"
        Btn.BackgroundColor3 = Color3.fromRGB(190,45,45)
    end
end)

local Foot = Instance.new("TextLabel")
Foot.Size = UDim2.new(1,0,0,14)
Foot.Position = UDim2.new(0,0,1,-16)
Foot.BackgroundTransparency = 1
Foot.Text = "ลาก GUI ได้  |  Roblox Pro"
Foot.TextColor3 = Color3.fromRGB(55,55,70)
Foot.Font = Enum.Font.Gotham
Foot.TextSize = 10
Foot.TextXAlignment = Enum.TextXAlignment.Center
Foot.Parent = Frame

print("[FuelFarm] โหลดสำเร็จ! กด START เพื่อเริ่ม")
