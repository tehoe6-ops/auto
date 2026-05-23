-- ══════════════════════════════════════════════════════════════
--   Auto Fuel Farm | Survive the Apocalypse
--   Flow: หา Fuel → วาป → กด E เก็บ → วาปเครื่องปั่นไฟ → กด E ใส่
-- ══════════════════════════════════════════════════════════════

local Players  = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local VIM      = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer

-- ─── Config ───────────────────────────────────────────────────
local Config = {
    Enabled        = false,
    FuelName       = "Fuel",       -- ชื่อ item fuel (แก้ได้ใน GUI)
    GeneratorName  = "Generator",  -- ชื่อเครื่องปั่นไฟ (แก้ได้ใน GUI)
    TeleportDelay  = 0.35,         -- หน่วงหลัง teleport
    PressEDelay    = 0.6,          -- หน่วงหลังกด E
    SearchRadius   = 5000,
}

-- ─── States ───────────────────────────────────────────────────
local S = {
    IDLE         = { text = "รอเริ่มต้น",                  color = Color3.fromRGB(120,120,130) },
    FIND_FUEL    = { text = "กำลังหา Fuel...",              color = Color3.fromRGB(230,180,40)  },
    GO_FUEL      = { text = "วาปไปหา Fuel",                color = Color3.fromRGB(80,180,255)  },
    COLLECT      = { text = "กด E เก็บ Fuel",              color = Color3.fromRGB(80,220,120)  },
    FIND_GEN     = { text = "กำลังหาเครื่องปั่นไฟ...",     color = Color3.fromRGB(230,180,40)  },
    GO_GEN       = { text = "วาปไปเครื่องปั่นไฟ",          color = Color3.fromRGB(80,180,255)  },
    INSERT       = { text = "กด E ใส่ Fuel",               color = Color3.fromRGB(180,100,255) },
    NO_FUEL      = { text = "ไม่พบ Fuel ในแมป",            color = Color3.fromRGB(220,80,80)   },
    NO_GEN       = { text = "ไม่พบเครื่องปั่นไฟ",          color = Color3.fromRGB(220,80,80)   },
    DEAD         = { text = "ตัวละครตาย รอ respawn...",     color = Color3.fromRGB(200,60,60)   },
}

-- ─── UI refs (assign ทีหลัง) ──────────────────────────────────
local StatusText  = nil
local StatusBox   = nil
local CountLabel  = nil
local cycleCount  = 0

local function setState(s)
    if StatusText then
        StatusText.Text      = s.text
        StatusText.TextColor3 = s.color
    end
    if StatusBox then
        TweenService:Create(StatusBox, TweenInfo.new(0.2), {
            BackgroundColor3 = Color3.fromRGB(
                math.clamp(s.color.R * 255 * 0.15, 0, 255) / 255,
                math.clamp(s.color.G * 255 * 0.15, 0, 255) / 255,
                math.clamp(s.color.B * 255 * 0.15, 0, 255) / 255
            )
        }):Play()
    end
end

-- ─── Helpers ──────────────────────────────────────────────────
local function getCharParts()
    local c = LocalPlayer.Character
    if not c then return nil, nil, nil end
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

local function pressE()
    VIM:SendKeyEvent(true,  Enum.KeyCode.E, false, game)
    task.wait(0.1)
    VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game)
end

local function findNearest(keyword, myPos)
    local best, bestDist = nil, Config.SearchRadius
    local kw = keyword:lower()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name:lower():find(kw, 1, true)
        and not Players:GetPlayerFromCharacter(obj)
        and not Players:GetPlayerFromCharacter(obj.Parent) then
            local pos = getPos(obj)
            if pos then
                local d = (myPos - pos).Magnitude
                if d < bestDist then best, bestDist = obj, d end
            end
        end
    end
    return best, bestDist
end

-- ─── Main Farm Loop ───────────────────────────────────────────
local farmThread = nil

local function stopFarm()
    if farmThread then
        task.cancel(farmThread)
        farmThread = nil
    end
    Config.Enabled = false
    setState(S.IDLE)
end

local function startFarm()
    stopFarm()
    Config.Enabled = true
    cycleCount = 0

    farmThread = task.spawn(function()
        while Config.Enabled do
            local _, hrp, hum = getCharParts()

            -- รอ respawn
            if not hrp or not hum or hum.Health <= 0 then
                setState(S.DEAD)
                task.wait(2)
                continue
            end

            -- ── 1. หา Fuel ──────────────────────────────────
            setState(S.FIND_FUEL)
            local fuel = findNearest(Config.FuelName, hrp.Position)
            if not fuel then
                setState(S.NO_FUEL)
                task.wait(2)
                continue
            end

            -- ── 2. วาปไป Fuel ───────────────────────────────
            setState(S.GO_FUEL)
            local fpos = getPos(fuel)
            if fpos then
                teleportTo(hrp, fpos)
                task.wait(Config.TeleportDelay)
            end

            -- ── 3. กด E เก็บ Fuel ───────────────────────────
            setState(S.COLLECT)
            pressE()
            task.wait(Config.PressEDelay)

            -- ── 4. หาเครื่องปั่นไฟ ──────────────────────────
            local _, hrp2, hum2 = getCharParts()
            if not hrp2 or not hum2 or hum2.Health <= 0 then continue end

            setState(S.FIND_GEN)
            local gen = findNearest(Config.GeneratorName, hrp2.Position)
            if not gen then
                setState(S.NO_GEN)
                task.wait(2)
                continue
            end

            -- ── 5. วาปไปเครื่องปั่นไฟ ───────────────────────
            setState(S.GO_GEN)
            local gpos = getPos(gen)
            if gpos then
                teleportTo(hrp2, gpos)
                task.wait(Config.TeleportDelay)
            end

            -- ── 6. กด E ใส่ Fuel ────────────────────────────
            setState(S.INSERT)
            pressE()
            task.wait(Config.PressEDelay)

            -- นับรอบ
            cycleCount += 1
            if CountLabel then
                CountLabel.Text = ("ทำไปแล้ว: %d รอบ"):format(cycleCount)
            end

            task.wait(0.1)
        end
    end)
end

-- ─── GUI Builder ──────────────────────────────────────────────
local function corner(p, r) local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,r or 8) c.Parent=p end
local function pad(p,t,b,l,r) local u=Instance.new("UIPadding") u.PaddingTop=UDim.new(0,t) u.PaddingBottom=UDim.new(0,b) u.PaddingLeft=UDim.new(0,l) u.PaddingRight=UDim.new(0,r) u.Parent=p end

local gui = Instance.new("ScreenGui")
gui.Name           = "FuelFarmGUI"
gui.ResetOnSpawn   = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent         = LocalPlayer:WaitForChild("PlayerGui")

-- ── Main Frame ──
local Frame = Instance.new("Frame")
Frame.Size             = UDim2.new(0, 300, 0, 370)
Frame.Position         = UDim2.new(0, 16, 0.5, -185)
Frame.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
Frame.BorderSizePixel  = 0
Frame.Active           = true
Frame.Draggable        = true
Frame.Parent           = gui
corner(Frame, 14)

-- shadow
local Shad = Instance.new("Frame")
Shad.Size              = UDim2.new(1,16,1,16)
Shad.Position          = UDim2.new(0,-8,0,6)
Shad.BackgroundColor3  = Color3.new(0,0,0)
Shad.BackgroundTransparency = 0.6
Shad.BorderSizePixel   = 0
Shad.ZIndex            = Frame.ZIndex - 1
Shad.Parent            = Frame
corner(Shad, 18)

-- ── Title ──
local Title = Instance.new("Frame")
Title.Size             = UDim2.new(1,0,0,40)
Title.BackgroundColor3 = Color3.fromRGB(25,90,210)
Title.BorderSizePixel  = 0
Title.Parent           = Frame
corner(Title, 14)
-- กันมุมล่างของ title โผล่
local TitleFix = Instance.new("Frame")
TitleFix.Size             = UDim2.new(1,0,0.5,0)
TitleFix.Position         = UDim2.new(0,0,0.5,0)
TitleFix.BackgroundColor3 = Color3.fromRGB(25,90,210)
TitleFix.BorderSizePixel  = 0
TitleFix.Parent           = Title

local TitleLbl = Instance.new("TextLabel")
TitleLbl.Size              = UDim2.new(1,-12,1,0)
TitleLbl.Position          = UDim2.new(0,12,0,0)
TitleLbl.BackgroundTransparency = 1
TitleLbl.Text              = "Fuel Auto Farm"
TitleLbl.TextColor3        = Color3.new(1,1,1)
TitleLbl.Font              = Enum.Font.GothamBold
TitleLbl.TextSize          = 15
TitleLbl.TextXAlignment    = Enum.TextXAlignment.Left
TitleLbl.Parent            = Title

local SubLbl = Instance.new("TextLabel")
SubLbl.Size                = UDim2.new(1,-12,0,14)
SubLbl.Position            = UDim2.new(0,12,0,24)
SubLbl.BackgroundTransparency = 1
SubLbl.Text                = "Survive the Apocalypse"
SubLbl.TextColor3          = Color3.fromRGB(180,200,255)
SubLbl.Font                = Enum.Font.Gotham
SubLbl.TextSize            = 11
SubLbl.TextXAlignment      = Enum.TextXAlignment.Left
SubLbl.Parent              = Title

-- ── Status Box ──
local SBox = Instance.new("Frame")
SBox.Name              = "StatusBox"
SBox.Size              = UDim2.new(1,-20,0,56)
SBox.Position          = UDim2.new(0,10,0,50)
SBox.BackgroundColor3  = Color3.fromRGB(20,20,30)
SBox.BorderSizePixel   = 0
SBox.Parent            = Frame
corner(SBox, 10)
StatusBox = SBox

local SBoxTitle = Instance.new("TextLabel")
SBoxTitle.Size             = UDim2.new(1,0,0,18)
SBoxTitle.Position         = UDim2.new(0,10,0,4)
SBoxTitle.BackgroundTransparency = 1
SBoxTitle.Text             = "สถานะ"
SBoxTitle.TextColor3       = Color3.fromRGB(100,100,115)
SBoxTitle.Font             = Enum.Font.Gotham
SBoxTitle.TextSize         = 10
SBoxTitle.TextXAlignment   = Enum.TextXAlignment.Left
SBoxTitle.Parent           = SBox

local STxt = Instance.new("TextLabel")
STxt.Size                  = UDim2.new(1,-20,0,24)
STxt.Position              = UDim2.new(0,10,0,22)
STxt.BackgroundTransparency = 1
STxt.Text                  = S.IDLE.text
STxt.TextColor3            = S.IDLE.color
STxt.Font                  = Enum.Font.GothamBold
STxt.TextSize              = 14
STxt.TextXAlignment        = Enum.TextXAlignment.Left
STxt.TextWrapped           = true
STxt.Parent                = SBox
StatusText = STxt

-- รอบนับ
local CntLbl = Instance.new("TextLabel")
CntLbl.Size                = UDim2.new(1,-20,0,14)
CntLbl.Position            = UDim2.new(0,10,0,112)
CntLbl.BackgroundTransparency = 1
CntLbl.Text                = "ทำไปแล้ว: 0 รอบ"
CntLbl.TextColor3          = Color3.fromRGB(150,150,170)
CntLbl.Font                = Enum.Font.Gotham
CntLbl.TextSize            = 11
CntLbl.TextXAlignment      = Enum.TextXAlignment.Left
CntLbl.Parent              = Frame
CountLabel = CntLbl

-- ── Input helper ──
local function makeInput(parent, label, placeholder, default, yPos, onChange)
    local lbl = Instance.new("TextLabel")
    lbl.Size               = UDim2.new(1,-20,0,14)
    lbl.Position           = UDim2.new(0,10,0,yPos)
    lbl.BackgroundTransparency = 1
    lbl.Text               = label
    lbl.TextColor3         = Color3.fromRGB(160,160,175)
    lbl.Font               = Enum.Font.Gotham
    lbl.TextSize           = 11
    lbl.TextXAlignment     = Enum.TextXAlignment.Left
    lbl.Parent             = parent

    local box = Instance.new("TextBox")
    box.Size               = UDim2.new(1,-20,0,30)
    box.Position           = UDim2.new(0,10,0,yPos+16)
    box.BackgroundColor3   = Color3.fromRGB(24,24,36)
    box.BorderSizePixel    = 0
    box.Text               = default
    box.PlaceholderText    = placeholder
    box.TextColor3         = Color3.new(1,1,1)
    box.PlaceholderColor3  = Color3.fromRGB(90,90,110)
    box.Font               = Enum.Font.Gotham
    box.TextSize           = 13
    box.ClearTextOnFocus   = false
    box.Parent             = parent
    corner(box, 7)

    box:GetPropertyChangedSignal("Text"):Connect(function()
        onChange(box.Text)
    end)
    return box
end

makeInput(Frame, "ชื่อ Fuel ในเกม", "เช่น: Fuel, Jerry Can ...", Config.FuelName, 132,
    function(v) Config.FuelName = v end)

makeInput(Frame, "ชื่อเครื่องปั่นไฟ", "เช่น: Generator, PowerGen ...", Config.GeneratorName, 188,
    function(v) Config.GeneratorName = v end)

makeInput(Frame, "Delay (วินาที, ต่ำสุด 0.1)", "0.35", tostring(Config.TeleportDelay), 244,
    function(v)
        local n = tonumber(v)
        if n and n >= 0.1 then Config.TeleportDelay = n end
    end)

-- ── Toggle Button ──
local Btn = Instance.new("TextButton")
Btn.Size               = UDim2.new(1,-20,0,42)
Btn.Position           = UDim2.new(0,10,0,310)
Btn.BackgroundColor3   = Color3.fromRGB(35,160,75)
Btn.BorderSizePixel    = 0
Btn.Text               = "START"
Btn.TextColor3         = Color3.new(1,1,1)
Btn.Font               = Enum.Font.GothamBold
Btn.TextSize           = 16
Btn.Parent             = Frame
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
        Btn.Text             = "START"
        Btn.BackgroundColor3 = Color3.fromRGB(35,160,75)
    else
        startFarm()
        Btn.Text             = "STOP"
        Btn.BackgroundColor3 = Color3.fromRGB(190,45,45)
    end
end)

-- ── Footer ──
local Foot = Instance.new("TextLabel")
Foot.Size              = UDim2.new(1,0,0,16)
Foot.Position          = UDim2.new(0,0,1,-18)
Foot.BackgroundTransparency = 1
Foot.Text              = "ลาก GUI ได้  |  Roblox Pro"
Foot.TextColor3        = Color3.fromRGB(65,65,80)
Foot.Font              = Enum.Font.Gotham
Foot.TextSize          = 10
Foot.TextXAlignment    = Enum.TextXAlignment.Center
Foot.Parent            = Frame

print("[FuelFarm] โหลดสำเร็จ! กด START เพื่อเริ่ม")
