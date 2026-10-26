--// Zenith Hub | PC + Mobile single-file build\n--// รวมจาก ZenithHub_Pc.lua โดยเพิ่มการตรวจจับอุปกรณ์และปุ่ม BOOST มือถือ\n\nlocal WindUI = loadstring(game:HttpGet(
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"
))()

-- Services
local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local UIS           = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser   = game:GetService("VirtualUser") -- ⭐ สำหรับ Anti-AFK

local player = Players.LocalPlayer

-- Theme
WindUI:AddTheme({
    Name = "Revolution",
    Accent = Color3.fromHex("#1A1A1A"),
    Background = Color3.fromHex("#1A1A1A"),
    Outline = Color3.fromHex("#330000"),
    Text = Color3.fromHex("#FFFFFF"),
    Placeholder = Color3.fromHex("#808080"),
    Button = Color3.fromHex("#6A00FF"),
    Icon = Color3.fromHex("#D946FF"),
})

-- Main Window
local Window = WindUI:CreateWindow({
    Title = "Zenith Hub | ZingLangThanon",
    Icon = "monitor-cog",
    Author = "By Zenith",
    Folder = "Zenith hub",
    Size = UDim2.fromOffset(500, 440),
    Transparent = true,
    Theme = "Revolution",
})

-- Floating Open Button
Window:EditOpenButton({
    Title = "Zenith Hub",
    Icon = "monitor",
    CornerRadius = UDim.new(0, 16),
    StrokeThickness = 2,
    Color = ColorSequence.new(
        Color3.fromHex("#FF0F7B"),
        Color3.fromHex("#F89B29")
    ),
    OnlyMobile = false,
    Enabled = true,
    Draggable = true,
})

-- Tabs
local FARM_TAB    = Window:Tab({ Title = "AUTO FARM", Icon = "zap" })
local VEHICLETAB  = Window:Tab({ Title = "VEHICLE MODS", Icon = "car" })
local BOOSTTAB    = Window:Tab({ Title = "AUTO MODS", Icon = "rocket" })
local STATUSTAB   = Window:Tab({ Title = "STATUS", Icon = "wrench" })
local TELEPORTTAB = Window:Tab({ Title = "TELEPORT", Icon = "map-pin" })

FARM_TAB:Select()

-- Beta Tag
Window:Tag({
    Title = "Beta",
    Color = Color3.fromHex("#30ff6a"),
    Radius = 13,
})

-- ============================================================
-- CONFIG VARIABLES
-- ============================================================
local scriptActive = true
local isBoosting = false
local autoBoostEnabled = false 
local antiSpinEnabled = false 

local nitroPower         = 10
local targetMaxSpeed     = 280
local driftPower         = 5
local handlingMultiplier = 1.5
local boostSmooth        = 5   -- ยิ่งสูง ยิ่งไวขึ้น/ลง (1 = นุ่มมาก, 10 = ไว)
local boostAlpha         = 0   -- 0..1 ระดับบูสปัจจุบัน (ค่อย ๆ เพิ่ม/ลด)

-- ============================================================
-- AUTO FARM TAB
-- ============================================================
local CFG_FARM = {
    ARRIVE_RADIUS = 5,
    POLL_RATE = 0.1,
    JOB_BOARD_CFRAME = CFrame.new(-15074.61, -260.52, 6330.18), -- จุดรับงาน
}

local AUTO_JOB_ENABLED = false
local currentState = "Idle"
local currentPickupName, currentDeliveryName
local isProcessing = false

local JobRemotes = ReplicatedStorage:FindFirstChild("JobRemotes")
local JobSystem  = workspace:FindFirstChild("JobSystem")

if JobRemotes then
    local RequestSync = JobRemotes:FindFirstChild("RequestSync")
    local JobStateEvent = JobRemotes:FindFirstChild("JobState")
    if JobStateEvent then
        JobStateEvent.OnClientEvent:Connect(function(state)
            if type(state) ~= "table" then return end
            currentState = state.state or "Idle"
            currentPickupName   = state.pickup   and state.pickup.Name
            currentDeliveryName = state.delivery and state.delivery.Name
        end)
    end
    if RequestSync then pcall(function() RequestSync:FireServer() end) end
end

local function getHumanoid()
    local char = player.Character
    if not char then return nil, nil, nil end
    return char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart"), char
end

local function stopEverything()
    local hum, hrp = getHumanoid()
    if hum and hrp then
        pcall(function() hum:MoveTo(hrp.Position) end)
    end
end

local function scanAllPrompts()
    local list = {}
    if not JobSystem or not JobSystem.Parent then return list end
    for _, d in ipairs(JobSystem:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Parent and d.Parent:IsA("BasePart") then
            table.insert(list, {
                prompt = d, part = d.Parent, partName = d.Parent.Name,
                enabled = d.Enabled, hold = d.HoldDuration, distance = d.MaxActivationDistance
            })
        end
    end
    return list
end

local function findPartByName(name)
    if not JobSystem or not name then return nil end
    for _, d in ipairs(JobSystem:GetDescendants()) do
        if d:IsA("BasePart") and d.Name == name then return d end
    end
    return nil
end

local function pickActivePrompt()
    local list = scanAllPrompts()
    for _, info in ipairs(list) do
        if info.enabled then
            if currentState == "Idle" then return info end
            if currentState == "GoPickup" and (not currentPickupName or info.partName == currentPickupName) then return info end
            if currentState == "GoDeliver" and (not currentDeliveryName or info.partName == currentDeliveryName) then return info end
        end
    end
    return nil
end

local function walkTo(targetPart)
    local hum, hrp = getHumanoid()
    if not hum or not hrp or not targetPart then return false end

    local startTime = os.clock()
    local lastPos   = hrp.Position
    local lastCheck = os.clock()

    while AUTO_JOB_ENABLED and targetPart.Parent do
        hum, hrp = getHumanoid()
        if not hum or not hrp or hum.Health <= 0 or hum.SeatPart then return false end

        -- ถึงแล้ว
        if (hrp.Position - targetPart.Position).Magnitude <= CFG_FARM.ARRIVE_RADIUS then
            break
        end

        -- เดินไปหาเป้าหมาย (MoveTo หมดอายุเอง จึงสั่งซ้ำทุกรอบ)
        hum:MoveTo(targetPart.Position)

        -- ติดสิ่งกีดขวาง: ถ้า 1 วิขยับไม่ถึง 1 stud ให้กระโดด
        if os.clock() - lastCheck >= 1 then
            if (hrp.Position - lastPos).Magnitude < 1 then
                hum.Jump = true
            end
            lastPos   = hrp.Position
            lastCheck = os.clock()
        end

        -- เดินนานเกิน 30 วิ ถือว่าไปไม่ถึง
        if os.clock() - startTime > 30 then
            hum:MoveTo(hrp.Position)
            return false
        end

        task.wait(0.1)
    end

    hum, hrp = getHumanoid()
    if hum and hrp then hum:MoveTo(hrp.Position) end
    return AUTO_JOB_ENABLED
end

local function triggerPrompt(info)
    if not AUTO_JOB_ENABLED or not info or not info.prompt.Enabled then return false end

    local prompt = info.prompt

    -- กันมุมกล้องเพี้ยน/มีของบังแล้วกดไม่ติด
    pcall(function() prompt.RequiresLineOfSight = false end)

    local fired = false
    if fireproximityprompt then
        local origHold = prompt.HoldDuration
        pcall(function() prompt.HoldDuration = 0 end)
        fired = pcall(function() fireproximityprompt(prompt) end)
        pcall(function() prompt.HoldDuration = origHold end)
    end

    -- สำรอง: executor ไม่มี fireproximityprompt
    if not fired then
        local hold = info.hold or 0
        pcall(function() prompt:InputHoldBegin() end)
        task.wait(hold > 0 and hold + 0.05 or 0.05)
        pcall(function() prompt:InputHoldEnd() end)
    end

    task.wait(0.1)
    return true
end

-- ลูป Auto Farm
task.spawn(function()
    while true do
        task.wait(CFG_FARM.POLL_RATE)
        if not AUTO_JOB_ENABLED or isProcessing then continue end

        local hum, hrp = getHumanoid()
        if not hum or not hrp or hum.Health <= 0 or hum.SeatPart then continue end

        local info = pickActivePrompt()

        if not info then
            local target = nil
            if currentState == "GoDeliver" then target = findPartByName(currentDeliveryName)
            elseif currentState == "GoPickup" then target = findPartByName(currentPickupName) end

            if target then
                isProcessing = true
                walkTo(target)
                task.wait(0.2)
                local info2 = pickActivePrompt()
                if info2 then triggerPrompt(info2) end
                isProcessing = false
            end
            continue
        end

        if walkTo(info.part) then
            isProcessing = true
            local info2 = pickActivePrompt()
            if info2 then triggerPrompt(info2) end
            isProcessing = false
        end
    end
end)

-- ============================================================
-- ANTI-AFK SYSTEM (v2: Idled + ลูปสำรอง + ขยับตัวละคร)
-- ============================================================
local antiAfkEnabled = true
local idledConn

local function afkClick()
    pcall(function()
        local cam = workspace.CurrentCamera
        VirtualUser:CaptureController()
        VirtualUser:Button2Down(Vector2.new(0, 0), cam and cam.CFrame or CFrame.new())
        task.wait(0.1)
        VirtualUser:Button2Up(Vector2.new(0, 0), cam and cam.CFrame or CFrame.new())
    end)
end

local function afkMoveCharacter()
    -- ขยับเฉพาะตอนไม่ได้นั่งรถ และไม่ได้กำลังฟาร์มอยู่ (กันชนกับการเดินของ Auto Farm)
    if AUTO_JOB_ENABLED or isProcessing then return end
    local hum = getHumanoid()
    if not hum or hum.Health <= 0 or hum.SeatPart then return end
    pcall(function()
        hum:Move(Vector3.new(1, 0, 0), false)
        task.wait(0.25)
        hum:Move(Vector3.new(-1, 0, 0), false)
        task.wait(0.25)
        hum:Move(Vector3.new(0, 0, 0), false)
        hum.Jump = true
    end)
end

-- ชั้นที่ 1: Idled (ตอนเกมแจ้งว่านิ่งแล้ว)
idledConn = player.Idled:Connect(function()
    if not antiAfkEnabled then return end
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new(0, 0))
    print("[Anti-AFK] Idled triggered")
end)

-- ชั้นที่ 2: ลูปสำรอง กดจำลองทุก 55 วิ + ขยับตัวละครทุก ~2 นาที
task.spawn(function()
    local tick = 0
    while scriptActive do
        task.wait(55)
        if antiAfkEnabled then
            tick = tick + 1
            afkClick()
            if tick % 2 == 0 then afkMoveCharacter() end
        end
    end
end)

FARM_TAB:Section({ Title = "Auto Box Carry Job" })

FARM_TAB:Button({
    Title = "📍 วาร์ปไปจุดรับงาน",
    Desc = "ก่อนฟาร์มต้องวาปทุกรอบ",
    Icon = "map-pin",
    Locked = false,
    Callback = function()
        print("กำลังวาร์ปไปที่ Job Board...")
        local char = player.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            char.HumanoidRootPart.CFrame = CFG_FARM.JOB_BOARD_CFRAME
        end
    end
})

FARM_TAB:Toggle({
    Title = "Auto Box Carry Job",
    Desc = "ฟาร์มงานยกกล่อง (เดินปกติ)",
    Icon = "package",
    Type = "Checkbox",
    Value = false,
    Callback = function(state)
        AUTO_JOB_ENABLED = state
        print("[AutoFarm] Box Job:", state)
        if not state then stopEverything() end
    end
})

FARM_TAB:Button({
    Title = "Cancel Box Job",
    Desc = "ยกเลิกงานยกกล่อง",
    Locked = false,
    Callback = function()
        local CancelJob = JobRemotes and JobRemotes:FindFirstChild("CancelJob")
        if CancelJob then pcall(function() CancelJob:FireServer() end) end
    end
})

FARM_TAB:Toggle({
    Title = "Anti-AFK",
    Desc = "กันโดนเตะตอนยืนนิ่ง/ฟาร์มทิ้งไว้",
    Icon = "shield-check",
    Type = "Checkbox",
    Value = true,
    Callback = function(state)
        antiAfkEnabled = state
        print("[Anti-AFK]", state and "ON" or "OFF")
    end
})

-- ============================================================
-- VEHICLE MODS TAB
-- ============================================================
VEHICLETAB:Section({ Title = "Vehicle Settings" })

VEHICLETAB:Input({
    Title = "Target Max Speed",
    Desc = "ความเร็วสูงสุดที่ต้องการ",
    Icon = "rabbit",
    Value = "280",
    Callback = function(v)
        local num = tonumber(v)
        if num then targetMaxSpeed = num end
    end
})

VEHICLETAB:Slider({
    Title = "Nitro Intensity",
    Desc = "ความแรงของการพุ่ง (PC: กด X ค้าง / มือถือ: กดปุ่ม BOOST ค้าง)",
    Icon = "flame",
    Value = { Min = 1, Max = 100, Default = 10 },
    Callback = function(v) nitroPower = v end
})

VEHICLETAB:Slider({
    Title = "Drift Power",
    Desc = "ปรับแรงดริฟต์ของรถ",
    Icon = "wind",
    Value = { Min = 1, Max = 20, Default = 5 },
    Callback = function(v) driftPower = v end
})

VEHICLETAB:Slider({
    Title = "Handling Multiplier",
    Desc = "เพิ่มการยึดเกาะ/ควบคุมรถ",
    Icon = "gauge",
    Value = { Min = 1, Max = 5, Default = 1.5 },
    Callback = function(v) handlingMultiplier = v end
})

VEHICLETAB:Slider({
    Title = "Boost Smoothness",
    Desc = "ความนุ่มของการบูส (ต่ำ = นุ่ม/ค่อยๆ เร่ง, สูง = ไว)",
    Icon = "activity",
    Value = { Min = 1, Max = 10, Default = 5 },
    Callback = function(v) boostSmooth = v end
})

VEHICLETAB:Section({ Title = "Stability & Physics (ความนิ่ง)" })

VEHICLETAB:Toggle({
    Title = "Anti-Spin (กันรถสบัด)",
    Desc = "ช่วยลดการปัดตูด/เหวี่ยงเวลาเลี้ยวเร็วๆ",
    Icon = "shield",
    Type = "Checkbox",
    Value = false,
    Callback = function(state) antiSpinEnabled = state end
})

VEHICLETAB:Button({
    Title = "🔄 Auto-Right (พลิกรถกลับ)",
    Desc = "ถ้ารถคว่ำหรือล้อชี้ฟ้า กดปุ่มนี้เพื่อพลิกรถกลับมาตั้งตรง",
    Locked = false,
    Callback = function()
        local char = player.Character
        local seat = char and char:FindFirstChild("Humanoid") and char.Humanoid.SeatPart
        if seat and seat:IsA("VehicleSeat") then
            local pos = seat.Position
            seat.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) 
        end
    end
})

VEHICLETAB:Slider({
    Title = "Custom Gravity",
    Desc = "ปรับแรงโน้มถ่วง (196 = ปกติ / ลดลงเพื่อให้รถลอยขึ้น)",
    Icon = "arrow-down",
    Value = { Min = 50, Max = 196, Default = 196 },
    Callback = function(v) workspace.Gravity = v end
})

-- ============================================================
-- AUTO MODS TAB
-- ============================================================
BOOSTTAB:Section({ Title = "Auto Boost Modes" })

BOOSTTAB:Paragraph({
    Title = "ℹ️ วิธีการใช้งาน",
    Desc = "โหมดปกติ: กด X ค้าง \nโหมดออโต้: เปิด แล้วกด W (มือถือ: ปุ่มคันเร่ง) บูสจะทำงานเอง"
})

BOOSTTAB:Toggle({
    Title = "Auto Boost (ไม่ต้องกดพุ่ง)",
    Desc = "เปิดแล้วบูสเองเฉพาะตอนกด W / ปุ่มคันเร่ง ปล่อยแล้วหยุดบูส",
    Icon = "zap",
    Type = "Checkbox",
    Value = false,
    Callback = function(state) 
        autoBoostEnabled = state 
        if not state then isBoosting = false end
    end
})

-- ============================================================
-- STATUS TAB (Engine Status HUD)
-- ============================================================
STATUSTAB:Section({ Title = "Engine Status HUD" })

STATUSTAB:Paragraph({
    Title = "ℹ️ ข้อมูลสถานะ",
    Desc = "เปิดปุ่มด้านล่างเพื่อแสดงหน้าต่างสถานะเครื่องยนต์แบบเรียลไทม์ (สามารถลากหน้าต่างได้)"
})

local PARTS = {
    { id = "Piston",     name = "ลูกสูบ" },
    { id = "Block",      name = "เสื้อสูบ" },
    { id = "Head",       name = "ฝาสูบ" },
    { id = "Valves",     name = "วาล์ว" },
    { id = "Crankshaft", name = "ข้อเหวี่ยง" },
    { id = "ConRod",     name = "ก้านสูบ" },
    { id = "SparkPlug",  name = "หัวเทียน" },
    { id = "Oil",        name = "น้ำมันเครื่อง" },
}

local COLOR_OK   = Color3.fromRGB(80, 200, 120)
local COLOR_WARN = Color3.fromRGB(240, 190, 60)
local COLOR_LOW  = Color3.fromRGB(235, 80, 80)
local COLOR_NONE = Color3.fromRGB(110, 110, 120)

local function getCurrentCar()
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local seat = hum and hum.SeatPart
    if seat and seat:IsA("VehicleSeat") then
        local model = seat:FindFirstAncestorOfClass("Model")
        while model do
            if model:FindFirstChild("Tuner") or model:FindFirstChild("A-Chassis Tune") then
                return model
            end
            model = model:FindFirstAncestorOfClass("Model")
        end
    end
    return nil
end

local gui = Instance.new("ScreenGui")
gui.Name = "EngineStatusHUD"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local ROW_H = 26
local WIDTH = 250
local HEIGHT = 34 + 30 + (#PARTS * ROW_H) + 20

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(WIDTH, HEIGHT)
main.Position = UDim2.new(0.5, -WIDTH/2, 0.5, -HEIGHT/2)
main.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
main.BorderSizePixel = 0
main.Visible = false
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", main)
stroke.Color = Color3.fromRGB(60, 60, 75)

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 34)
header.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
header.BorderSizePixel = 0
header.Parent = main
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)

local titleLabel = Instance.new("TextLabel")
titleLabel.Text = "🔧 สถานะเครื่องยนต์"
titleLabel.Size = UDim2.new(1, -90, 1, 0)
titleLabel.Position = UDim2.fromOffset(12, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamMedium
titleLabel.TextColor3 = Color3.fromRGB(230, 230, 235)
titleLabel.TextSize = 14
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = header

local summaryLabel = Instance.new("TextLabel")
summaryLabel.Text = "--%"
summaryLabel.Size = UDim2.fromOffset(70, 34)
summaryLabel.Position = UDim2.new(1, -78, 0, 0)
summaryLabel.BackgroundTransparency = 1
summaryLabel.Font = Enum.Font.GothamBold
summaryLabel.TextColor3 = COLOR_NONE
summaryLabel.TextSize = 15
summaryLabel.TextXAlignment = Enum.TextXAlignment.Right
summaryLabel.Parent = header

local statusLine = Instance.new("TextLabel")
statusLine.Text = "รอข้อมูลจากเกม..."
statusLine.Size = UDim2.new(1, -24, 0, 22)
statusLine.Position = UDim2.fromOffset(12, 38)
statusLine.BackgroundTransparency = 1
statusLine.Font = Enum.Font.GothamMedium
statusLine.TextColor3 = Color3.fromRGB(170, 170, 185)
statusLine.TextSize = 11
statusLine.TextXAlignment = Enum.TextXAlignment.Left
statusLine.Parent = main

local rows = {}
for i, part in ipairs(PARTS) do
    local y = 64 + (i - 1) * ROW_H
    local name = Instance.new("TextLabel")
    name.Text = part.name
    name.Size = UDim2.fromOffset(100, ROW_H)
    name.Position = UDim2.fromOffset(12, y)
    name.BackgroundTransparency = 1
    name.Font = Enum.Font.GothamMedium
    name.TextColor3 = Color3.fromRGB(230, 230, 235)
    name.TextSize = 13
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.Parent = main

    local track = Instance.new("Frame")
    track.Size = UDim2.fromOffset(80, 8)
    track.Position = UDim2.fromOffset(114, y + 9)
    track.BackgroundColor3 = Color3.fromRGB(45, 45, 56)
    track.BorderSizePixel = 0
    track.Parent = main
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.fromScale(0, 1)
    fill.BackgroundColor3 = COLOR_NONE
    fill.BorderSizePixel = 0
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local pct = Instance.new("TextLabel")
    pct.Text = "--"
    pct.Size = UDim2.fromOffset(40, ROW_H)
    pct.Position = UDim2.fromOffset(198, y)
    pct.BackgroundTransparency = 1
    pct.Font = Enum.Font.GothamMedium
    pct.TextColor3 = Color3.fromRGB(230, 230, 235)
    pct.TextSize = 13
    pct.TextXAlignment = Enum.TextXAlignment.Right
    pct.Parent = main

    rows[part.id] = { fill = fill, pct = pct }
end

STATUSTAB:Toggle({
    Title = "เปิด/ปิด หน้าต่างสถานะ",
    Desc = "แสดงหรือซ่อน HUD สถานะเครื่องยนต์",
    Icon = "eye",
    Type = "Checkbox",
    Value = false,
    Callback = function(state) main.Visible = state end
})

local dragging, dragStart, startPos
header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)

UIS.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local d = input.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)

local function getColor(pct)
    if pct < 30 then return COLOR_LOW end
    if pct < 60 then return COLOR_WARN end
    return COLOR_OK
end

local function updateStatus()
    if not main.Visible then return end
    local car = getCurrentCar()
    if not car then
        titleLabel.Text = "🔧 สถานะเครื่องยนต์"
        summaryLabel.Text = "--%"
        summaryLabel.TextColor3 = COLOR_NONE
        statusLine.Text = "❌ ไม่ได้นั่งอยู่ในรถ"
        for _, row in pairs(rows) do
            row.fill.Size = UDim2.fromScale(0, 1)
            row.fill.BackgroundColor3 = COLOR_NONE
            row.pct.Text = "--"
            row.pct.TextColor3 = COLOR_NONE
        end
        return
    end
    titleLabel.Text = "🔧 " .. car.Name
    local total = 0
    local lowest = { pct = 100, name = "" }
    for _, part in ipairs(PARTS) do
        local val = car:GetAttribute("Eng_" .. part.id) or 100
        total = total + val
        local row = rows[part.id]
        row.fill.Size = UDim2.fromScale(math.clamp(val / 100, 0, 1), 1)
        row.fill.BackgroundColor3 = getColor(val)
        row.pct.Text = math.floor(val + 0.5) .. "%"
        row.pct.TextColor3 = getColor(val)
        if val < lowest.pct then
            lowest = { pct = val, name = part.name }
        end
    end
    local avg = total / #PARTS
    summaryLabel.Text = math.floor(avg + 0.5) .. "%"
    summaryLabel.TextColor3 = getColor(avg)
    if avg >= 60 then
        statusLine.Text = "🟢 สภาพรถโดยรวม: ดี"
    elseif avg >= 30 then
        statusLine.Text = "🟡 สภาพรถโดยรวม: เสื่อม (" .. lowest.name .. " แย่สุด)"
    else
        statusLine.Text = "🔴 สภาพรถโดยรวม: วิกฤต! (" .. lowest.name .. ")"
    end
end

task.spawn(function()
    while gui.Parent do
        pcall(updateStatus)
        task.wait(0.5)
    end
end)

-- ============================================================
-- TELEPORT TAB
-- ============================================================
TELEPORTTAB:Section({ Title = "Teleport Locations" })

local function teleportTo(cframe)
    local char = player.Character or player.CharacterAdded:Wait()
    local root = char:WaitForChild("HumanoidRootPart")
    if root then root.CFrame = cframe end
end

local Locations = {
    { Name = "จุดเกิด", CFrame = CFrame.new(-14599.95, -257.30, 7789.76, -0.056, 0, 0.998, 0, 1, 0, -0.998, 0, -0.056) },
    { Name = "เเข่งหลังถนน", CFrame = CFrame.new(-13686.17, -260.50, -458.60) },
    { Name = "ช่างขายอะไหล่", CFrame = CFrame.new(-14607.84, -259.97, 6066.72, 0.027, 0, -1.000, 0, 1, 0, 1.000, 0, 0.027) },
    { Name = "ห้องไดโน่เทส", CFrame = CFrame.new(-13602.78, -259.96, -656.04, 1.000, 0, 0.017, 0, 1, 0, -0.017, 0, 1.000) },
    { Name = "ภูเขา-เขื่อน", CFrame = CFrame.new(-13936.83, -98.13, -2952.20) },
    { Name = "งานขนกล่อง", CFrame = CFrame.new(-15065.06, -260.52, 6333.82) },
    { Name = "งานส่ง Delivery", CFrame = CFrame.new(-14804.56, -259.97, 2646.10) },
}

for _, loc in ipairs(Locations) do
    TELEPORTTAB:Button({
        Title = "📍 " .. loc.Name,
        Desc = "วาร์ปไป: " .. loc.Name,
        Locked = false,
        Callback = function()
            teleportTo(loc.CFrame)
            print("Teleported to:", loc.Name)
        end
    })
end

-- ============================================================
-- MOBILE BOOST BUTTON UI (ใช้ได้ทั้ง PC และมือถือ)
-- ============================================================
local isMobile = UIS.TouchEnabled and not UIS.KeyboardEnabled
local mobileGui = Instance.new("ScreenGui")
mobileGui.Name = "MobileBoostGui"
mobileGui.ResetOnSpawn = false
mobileGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
mobileGui.Enabled = isMobile -- แสดงปุ่มลอยเฉพาะมือถือโดยค่าเริ่มต้น
mobileGui.Parent = player:WaitForChild("PlayerGui")

local boostBtn = Instance.new("TextButton")
boostBtn.Name = "BoostBtn"
boostBtn.Size = UDim2.fromOffset(80, 80)
boostBtn.Position = UDim2.new(0.05, 0, 0.6, 0)
boostBtn.BackgroundColor3 = Color3.fromRGB(255, 60, 100)
boostBtn.Text = "BOOST\n🚀"
boostBtn.Font = Enum.Font.GothamBold
boostBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
boostBtn.TextSize = 14
boostBtn.Active = true
boostBtn.Draggable = true
boostBtn.Parent = mobileGui

Instance.new("UICorner", boostBtn).CornerRadius = UDim.new(1, 0)
local boostStroke = Instance.new("UIStroke", boostBtn)
boostStroke.Color = Color3.fromRGB(255, 255, 255)
boostStroke.Thickness = 2.5

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseBtn"
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.Position = UDim2.new(1, -14, 0, -14)
closeBtn.AnchorPoint = Vector2.new(0.5, 0.5)
closeBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
closeBtn.Text = "✕"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
closeBtn.TextSize = 16
closeBtn.Active = true
closeBtn.Parent = boostBtn

Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)
local closeStroke = Instance.new("UIStroke", closeBtn)
closeStroke.Color = Color3.fromRGB(80, 80, 85)
closeStroke.Thickness = 1.5

closeBtn.MouseButton1Click:Connect(function()
    mobileGui.Enabled = false
end)

boostBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        isBoosting = true
        boostBtn.BackgroundColor3 = Color3.fromRGB(0, 220, 100)
    end
end)

boostBtn.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        isBoosting = false
        boostBtn.BackgroundColor3 = Color3.fromRGB(255, 60, 100)
    end
end)

VEHICLETAB:Toggle({
    Title = "📱 ปุ่ม BOOST บนมือถือ",
    Desc = "เปิด/ปิดปุ่ม BOOST ลอยบนหน้าจอ (แนะนำให้เปิดบนมือถือ)",
    Icon = "smartphone",
    Type = "Checkbox",
    Value = isMobile,
    Callback = function(state)
        mobileGui.Enabled = state
    end
})

-- ============================================================
-- LOGIC SYSTEM (Vehicle Boost Fix - Mobile Safe)
-- ============================================================
RunService.Heartbeat:Connect(function(dt)
    if not scriptActive then return end

    local char = player.Character
    local seat = char and char:FindFirstChild("Humanoid") and char.Humanoid.SeatPart
    local inCar = seat and seat:IsA("VehicleSeat")
    -- อ่านค่าคันเร่งจริงของผู้เล่น (W บน PC / ปุ่มคันเร่งบนมือถือ)
    local throttleIn = 0
    if inCar then
        throttleIn = math.max(seat.ThrottleFloat, UIS:IsKeyDown(Enum.KeyCode.W) and 1 or 0)
    end
    -- Auto Boost ทำงานเฉพาะตอนเหยียบคันเร่ง / กดบูสเองทำงานเสมอ
    local wantBoost = inCar and (isBoosting or (autoBoostEnabled and throttleIn > 0.1))

    -- ค่อย ๆ ไล่ระดับบูส (ease in/out) ไม่กระชากตอนกด/ปล่อย
    local rate = wantBoost and boostSmooth or (boostSmooth * 0.8)
    local goal = wantBoost and 1 or 0
    boostAlpha = boostAlpha + (goal - boostAlpha) * math.min(1, dt * rate)
    if boostAlpha < 0.001 then boostAlpha = 0 end

    if not inCar then return end

    if antiSpinEnabled then
        if seat.AssemblyLinearVelocity.Magnitude > 50 then
            seat.TurnSpeed = 0.5
        else
            seat.TurnSpeed = 1
        end
    end

    if boostAlpha > 0 then
        local speed = seat.AssemblyLinearVelocity.Magnitude

        -- เพดานความเร็วไหลขึ้น-ลงตามระดับบูส
        seat.MaxSpeed = targetMaxSpeed + 50 * boostAlpha

        if isBoosting then
            seat.ThrottleFloat = math.max(seat.ThrottleFloat, boostAlpha)
        end

        -- แรงดัน: เร่งเป็นความเร่งต่อวินาที และค่อย ๆ เบาลงเมื่อใกล้ความเร็วเป้าหมาย
        local gap = (targetMaxSpeed - speed) / math.max(targetMaxSpeed * 0.25, 1)
        local taper = math.clamp(gap, 0, 1)
        taper = taper * taper * (3 - 2 * taper) -- smoothstep

        if taper > 0 then
            local accel = nitroPower * 6 -- studs/s^2
            local force = seat.AssemblyMass * accel * dt * boostAlpha * taper
            seat:ApplyImpulse(seat.CFrame.LookVector * force)
        end
    elseif seat.MaxSpeed > targetMaxSpeed then
        seat.MaxSpeed = targetMaxSpeed
    end
end)

-- Keybinds (สำหรับ PC)
UIS.InputBegan:Connect(function(input, processed)
    if not scriptActive or processed then return end

    if input.KeyCode == Enum.KeyCode.X then
        isBoosting = true
    elseif input.KeyCode == Enum.KeyCode.M then
        if Window and Window.Toggle then Window:Toggle() end
    elseif input.KeyCode == Enum.KeyCode.K then
        scriptActive = false
        autoBoostEnabled = false
        antiAfkEnabled = false
        if idledConn then idledConn:Disconnect() end
        workspace.Gravity = 196.2 
        if mobileGui then mobileGui:Destroy() end
        if Window and Window.Destroy then Window:Destroy() end
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.X then
        isBoosting = false
    end
end)

print("UI + Logic loaded successfully! (Zenith Hub + Auto Farm + Mobile Boost + Anti-AFK v2)")
