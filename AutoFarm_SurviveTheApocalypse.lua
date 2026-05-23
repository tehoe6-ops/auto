-- ══════════════════════════════════════════════════════════════
--   Auto Fuel Farm | Survive the Apocalypse
--   Flow: กด 1 ถือกระเป๋า → วาปหา Fuel → ชี้เมาส์ที่ Fuel → กด F
--         → วาปไป Generator → ชี้เมาส์ที่ Generator → กด F ใส่
-- ══════════════════════════════════════════════════════════════

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local VIM          = game:GetService("VirtualInputManager")
local Camera       = workspace.CurrentCamera

local LocalPlayer  = Players.LocalPlayer

-- ─── Config ───────────────────────────────────────────────────
local Config = {
    Enabled       = false,
    FuelName      = "Fuel",
    GeneratorName = "Generator",
    TeleportDelay = 0.35,  -- หน่วงหลัง teleport
    AimDelay      = 0.25,  -- หน่วงหลังชี้เมาส์
    KeyDelay      = 0.3,   -- หน่วงหลังกดปุ่ม
    MaxFuelPerRun = 5,     -- เก็บสูงสุดกี่อันต่อรอบ
    WaitAtGen     = 3,     -- รอที่ Generator ก่อนวนรอบใหม่
}

-- ─── States ───────────────────────────────────────────────────
local S = {
    IDLE     = { text = "รอเริ่มต้น",                   color = Color3.fromRGB(120,120,135) },
    EQUIP    = { text = "กด 1 ถือกระเป๋า",              color = Color3.fromRGB(230,160,40)  },
    GO_FUEL  = { text = "วาปไปหา Fuel",                  color = Color3.fromRGB(80,180,255)  },
    AIM_FUEL = { text = "ชี้เมาส์ที่ Fuel...",           color = Color3.fromRGB(255,220,60)  },
    PRESSF   = { text = "กด F เก็บ Fuel",               color = Color3.fromRGB(80,220,120)  },
    GO_GEN   = { text = "วาปไปเครื่องปั่นไฟ",           color = Color3.fromRGB(180,100,255) },
    AIM_GEN  = { text = "ชี้เมาส์ที่เครื่องปั่นไฟ...",  color = Color3.fromRGB(255,220,60)  },
    INSERTF  = { text = "กด F ใส่ Fuel",                color = Color3.fromRGB(255,120,60)  },
    DONE     = { text = "ใส่ Fuel เสร็จ รอรอบถัดไป",   color = Color3.fromRGB(80,220,120)  },
    NO_FUEL  = { text = "ไม่พบ Fuel ในแมป รอ...",       color = Color3.fromRGB(220,80,80)   },
    NO_GEN   = { text = "ไม่พบเครื่องปั่นไฟ",           color = Color3.fromRGB(220,80,80)   },
    DEAD     = { text = "ตาย รอ respawn...",             color = Color3.fromRGB(180,50,50)   },
}

local StatusText, StatusBox, InfoLabel, CountLabel
local cycleCount = 0

local function setState(s)
    if StatusText then
        StatusText.Text       = s.text
        StatusText.TextColor3 = s.color
    end
    if StatusBox then
        TweenService:Create(StatusBox, TweenInfo.new(0.2), {
            BackgroundColor3 = Color3.new(s.color.R*0.13, s.color.G*0.13, s.color.B*0.13)
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
    -- วาปมาอยู่ข้างๆ แทนที่จะอยู่เหนือ เพื่อให้เมาส์ชี้ได้ง่ายขึ้น
    hrp.CFrame = CFrame.new(pos + Vector3.new(2, 1, 0))
end

local function pressKey(key)
    VIM:SendKeyEvent(true,  key, false, game)
    task.wait(0.08)
    VIM:SendKeyEvent(false, key, false, game)
end

-- ─── ชี้เมาส์ไปที่ตำแหน่ง 3D ────────────────────────────────
local function aimMouseAt(worldPos)
    -- แปลง world position → screen position
    local screenPos, onScreen = Camera:WorldToScreenPoint(worldPos)

    if onScreen then
        VIM:SendMouseMoveEvent(screenPos.X, screenPos.Y, game)
    else
        -- ถ้าอยู่นอกจอ ให้ชี้กลางจอก่อน แล้วค่อย aim ใหม่
        local vp = Camera.ViewportSize
        VIM:SendMouseMoveEvent(vp.X / 2, vp.Y / 2, game)
        task.wait(0.1)
        local sp2, _ = Camera:WorldToScreenPoint(worldPos)
        VIM:SendMouseMoveEvent(sp2.X, sp2.Y, game)
    end

    task.wait(Config.AimDelay)
end

-- ─── หา Fuel / Generator ──────────────────────────────────────
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

local function sortByDist(list, from)
    table.sort(list, function(a, b)
        local pa = getPos(a) or Vector3.new()
        local pb = getPos(b) or Vector3.new()
        return (from - pa).Magnitude < (from - pb).Magnitude
    end)
    return list
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

            -- ── กด 1 ถือกระเป๋าก่อน ──────────────────────────
            setState(S.EQUIP)
            pressKey(Enum.KeyCode.One)
            task.wait(Config.KeyDelay)

            -- ── หา Fuel ───────────────────────────────────────
            local fuels = findAllFuels()
            if #fuels == 0 then
                setState(S.NO_FUEL)
                task.wait(3)
                continue
            end
            fuels = sortByDist(fuels, hrp.Position)

            -- ── วาปหา Fuel ทีละอัน ────────────────────────────
            local collected = 0
            for _, fuel in ipairs(fuels) do
                if not Config.Enabled then break end
                if collected >= Config.MaxFuelPerRun then break end

                local _, hrpN, humN = getCharParts()
                if not hrpN or not humN or humN.Health <= 0 then break end

                local fpos = getPos(fuel)
                if not fpos then continue end

                -- 1. วาปไปข้างๆ Fuel
                setState(S.GO_FUEL)
                if InfoLabel then
                    InfoLabel.Text = ("เก็บ %d/%d"):format(collected, Config.MaxFuelPerRun)
                end
                teleportTo(hrpN, fpos)
                task.wait(Config.TeleportDelay)

                -- 2. ชี้เมาส์ไปที่ Fuel
                setState(S.AIM_FUEL)
                aimMouseAt(fpos)

                -- 3. กด F เก็บ
                setState(S.PRESSF)
                pressKey(Enum.KeyCode.F)
                task.wait(Config.KeyDelay)

                collected += 1
            end

            if collected == 0 then
                task.wait(1)
                continue
            end

            -- ── วาปไป Generator ───────────────────────────────
            local _, hrp2, hum2 = getCharParts()
            if not hrp2 or not hum2 or hum2.Health <= 0 then
                task.wait(1) continue
            end

            local gen = findGenerator(hrp2.Position)
            if not gen then
                setState(S.NO_GEN)
                task.wait(3)
                continue
            end

            local gpos = getPos(gen)
            if not gpos then task.wait(1) continue end

            setState(S.GO_GEN)
            teleportTo(hrp2, gpos)
            task.wait(Config.TeleportDelay)

            -- ชี้เมาส์ที่ Generator
            setState(S.AIM_GEN)
            aimMouseAt(gpos)

            -- กด F ใส่ Fuel
            setState(S.INSERTF)
            pressKey(Enum.KeyCode.F)
            task.wait(Config.KeyDelay)

            -- เสร็จรอบ
            cycleCount += 1
            setState(S.DONE)
            if CountLabel then
                CountLabel.Text = ("ทำไปแล้ว: %d รอบ  |  เก็บ %d อัน"):format(cycleCount, collected)
            end
            if InfoLabel then InfoLabel.Text = "" end

            task.wait(Config.WaitAtGen)
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
Frame.Size             = UDim2.new(0, 310, 0, 400)
Frame.Position         = UDim2.new(0, 16, 0.5, -200)
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
TitleLbl.Text = "Fuel Auto Farm"
TitleLbl.TextColor3 = Color3.new(1,1,1)
TitleLbl.Font = Enum.Font.GothamBold
TitleLbl.TextSize = 15
TitleLbl.TextXAlignment = Enum.TextXAlignment.Left
TitleLbl.Parent = Title

local SubLbl = Instance.new("TextLabel")
SubLbl.Size = UDim2.new(1,-12,0,13)
SubLbl.Position = UDim2.new(0,12,0,26)
SubLbl.BackgroundTransparency = 1
SubLbl.Text = "กด 1 → วาป → ชี้เมาส์ → กด F"
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
STitle.Size = UDim2.new(1,-10,0,15)
STitle.Position = UDim2.new(0,10,0,4)
STitle.BackgroundTransparency = 1
STitle.Text = "สถานะปัจจุบัน"
STitle.TextColor3 = Color3.fromRGB(80,80,100)
STitle.Font = Enum.Font.Gotham
STitle.TextSize = 10
STitle.TextXAlignment = Enum.TextXAlignment.Left
STitle.Parent = SBox

local STxt = Instance.new("TextLabel")
STxt.Size = UDim2.new(1,-20,0,30)
STxt.Position = UDim2.new(0,10,0,20)
STxt.BackgroundTransparency = 1
STxt.Text = S.IDLE.text
STxt.TextColor3 = S.IDLE.color
STxt.Font = Enum.Font.GothamBold
STxt.TextSize = 14
STxt.TextXAlignment = Enum.TextXAlignment.Left
STxt.TextWrapped = true
STxt.Parent = SBox
StatusText = STxt

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
    box.Position = UDim2.new(0,10,0,yPos+15)
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

makeInput("เก็บ Fuel สูงสุดกี่อันต่อรอบ", "5", tostring(Config.MaxFuelPerRun), 258,
    function(v) local n=tonumber(v) if n and n>=1 then Config.MaxFuelPerRun=math.floor(n) end end)

makeInput("Delay ระหว่างปุ่ม (วินาที)", "0.3", tostring(Config.KeyDelay), 306,
    function(v) local n=tonumber(v) if n and n>=0.1 then Config.KeyDelay=n end end)

local Btn = Instance.new("TextButton")
Btn.Size = UDim2.new(1,-20,0,40)
Btn.Position = UDim2.new(0,10,0,352)
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
