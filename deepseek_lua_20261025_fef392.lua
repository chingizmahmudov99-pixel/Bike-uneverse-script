--!nonstrict
--[[
    Bike Universe Hub — merged & patched edition.
    Игровая логика + встроенный загрузчик AirFlow с дисковым кэшем.
    Файл 3 (старая AirFlow) не используется — несовместим с Log/Status/ButtonRow.
]]

----------------------------------------------------------------------
-- Services
----------------------------------------------------------------------
local Players              = game:GetService("Players")
local RunService           = game:GetService("RunService")
local VirtualInputManager  = game:GetService("VirtualInputManager")
local UserInputService     = game:GetService("UserInputService")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

----------------------------------------------------------------------
-- ENV helper (закрывает дыру с getgenv)
----------------------------------------------------------------------
local function getEnv()
    if type(getgenv) == "function" then
        local ok, env = pcall(getgenv)
        if ok and type(env) == "table" then return env end
    end
    if type(shared) == "table" then return shared end
    return _G
end
local ENV = getEnv()

local Ragdoll
pcall(function()
    Ragdoll = require(ReplicatedStorage:WaitForChild("Ragdoll", 5))
end)

local function short(value)
    if type(value) ~= "number" then return "-" end
    local text = tostring(math.floor(value))
    return (text:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^%s+", ""))
end

----------------------------------------------------------------------
-- AirFlow library loading (cache -> URL -> error)
----------------------------------------------------------------------
local UI_CACHE    = "BikeHub_AirflowCache.lua"
local UI_SOURCES  = {
    "https://raw.githubusercontent.com/bobloscript/Robly_Airflow/main/Source.luau",
    "https://raw.githubusercontent.com/PookiePepelsss/Airflow-UI/refs/heads/main/Source.luau",
}

local function tryLoadLibrary(body)
    if type(body) ~= "string" or #body < 1000 then return nil end
    local fn = loadstring(body)
    if not fn then return nil end
    local ok, lib = pcall(fn)
    if ok and type(lib) == "table" and type(lib.CreateWindow) == "function" then
        return lib
    end
    return nil
end

local function readCache()
    if type(isfile) ~= "function" or type(readfile) ~= "function" then return nil end
    local ok = pcall(function() return isfile(UI_CACHE) end)
    if not ok then return nil end
    local ok2, body = pcall(readfile, UI_CACHE)
    if ok2 then return tryLoadLibrary(body) end
    return nil
end

local function writeCache(body)
    if type(writefile) ~= "function" or type(body) ~= "string" then return end
    pcall(writefile, UI_CACHE, body)
end

local function fetchFirst()
    for _, url in ipairs(UI_SOURCES) do
        local ok, body = pcall(function() return game:HttpGet(url) end)
        if ok and type(body) == "string" then
            writeCache(body)
            local lib = tryLoadLibrary(body)
            if lib then return lib end
        end
    end
    return nil
end

local Airflow = readCache() or fetchFirst()
if not Airflow then
    error("[Bike Universe Hub] AirFlow UI could not be loaded " ..
          "(cache empty and all mirrors failed).")
end

----------------------------------------------------------------------
-- Bike helpers
----------------------------------------------------------------------
local function myBike()
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") and child:GetAttribute("Owner") == LocalPlayer.UserId then
            return child
        end
    end
end

local function chassis()
    local bike = myBike()
    return bike and (bike:FindFirstChild("Chassis") or bike.PrimaryPart) or nil
end

local function driverSeat()
    local bike = myBike()
    return bike and bike:FindFirstChild("DriverSeat") or nil
end

local function humanoid()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid") or nil
end

local function bikePosition()
    local bike = myBike()
    return bike and bike:GetPivot().Position or nil
end

local function isRiding()
    local seat, hum = driverSeat(), humanoid()
    return seat ~= nil and hum ~= nil and seat.Occupant == hum
end

local function cash()
    local stats = LocalPlayer:FindFirstChild("leaderstats")
    local value = stats and stats:FindFirstChild("Cash")
    return value and value.Value or 0
end

----------------------------------------------------------------------
-- Drive control
----------------------------------------------------------------------
local TouchControls
pcall(function()
    TouchControls = require(ReplicatedStorage:WaitForChild("TouchControls"))
end)

local driveState = ENV.__BikeHubDrive
if not driveState then
    driveState = { on = false, throttle = 0, steer = 0 }
    ENV.__BikeHubDrive = driveState
end

if TouchControls and type(TouchControls.drive) == "function" then
    local marker = ENV.__BikeHubDriveMarker
    if TouchControls.drive ~= marker then
        local originalDrive = TouchControls.drive
        local hooked
        hooked = function(seat)
            local state = ENV.__BikeHubDrive
            if state and state.on and state.gen == ENV.__BikeHubGen
                and (os.clock() - (state.last or 0) < 0.4) then
                return state.throttle, state.steer
            end
            return originalDrive(seat)
        end
        TouchControls.drive = hooked
        ENV.__BikeHubDriveMarker = hooked
    end
end

local function drive(throttle, steer)
    driveState.throttle = throttle or 0
    driveState.steer = steer or 0
    driveState.on = true
    driveState.last = os.clock()
    driveState.gen = ENV.__BikeHubGen
end

local function driveStop()
    driveState.on = false
    driveState.last = 0
    driveState.throttle = 0
    driveState.steer = 0
end

----------------------------------------------------------------------
-- Key mirroring
----------------------------------------------------------------------
local heldKeys = {}

local function key(code, down)
    if heldKeys[code] == down then return end
    heldKeys[code] = down
    pcall(function()
        VirtualInputManager:SendKeyEvent(down, code, false, game)
    end)
end

local function releaseKeys()
    for code, down in pairs(heldKeys) do
        if down then
            pcall(function()
                VirtualInputManager:SendKeyEvent(false, code, false, game)
            end)
        end
    end
    heldKeys = {}
end

----------------------------------------------------------------------
-- Seating / bike spawn
----------------------------------------------------------------------
local log
local riderLockSet
local spawnBike
local pumpkinList
local teleportBike

spawnBike = function()
    if myBike() then return true end
    for _, name in ipairs({ "SpawnBikeEvent", "SelectBike", "BikeMount" }) do
        local remote = ReplicatedStorage:FindFirstChild(name)
        if remote and remote:IsA("RemoteEvent") then
            pcall(function() remote:FireServer() end)
            for _ = 1, 10 do
                task.wait(0.2)
                if myBike() then return true end
            end
        end
    end
    return myBike() ~= nil
end

local function standBikeUp(bike)
    local pivot = bike:GetPivot()
    if pivot.UpVector.Y > 0.6 then return true end
    local look = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z)
    if look.Magnitude < 0.05 then look = Vector3.new(0, 0, -1) end
    local position = pivot.Position + Vector3.new(0, 3, 0)
    pcall(function()
        bike:PivotTo(CFrame.lookAt(position, position + look.Unit))
    end)
    task.wait(0.2)
    if bike:GetPivot().UpVector.Y > 0.6 then return true end

    local spawn = ReplicatedStorage:FindFirstChild("SpawnBikeEvent")
    if spawn and spawn:IsA("RemoteEvent") then
        pcall(function() spawn:FireServer() end)
        for _ = 1, 12 do
            task.wait(0.25)
            local again = myBike()
            if again and again:GetPivot().UpVector.Y > 0.6 then
                return true
            end
        end
    end
    return false
end

local function seatUp()
    local seat, hum, bike = driverSeat(), humanoid(), myBike()
    if not (seat and hum and bike) then
        spawnBike()
        seat, hum, bike = driverSeat(), humanoid(), myBike()
    end
    if not (seat and hum and bike) then return false end
    if seat.Occupant == hum then return true end

    local char = LocalPlayer.Character
    if not char then return false end
    if Ragdoll and Ragdoll.isActive and Ragdoll.isActive(char) then
        pcall(function() Ragdoll.stop(char) end)
    end
    if hum.PlatformStand then hum.PlatformStand = false end
    pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    pcall(function() hum.Sit = false end)
    task.wait(0.1)

    standBikeUp(bike)
    seat, hum, bike = driverSeat(), humanoid(), myBike()
    if not (seat and hum and bike) then return false end

    for attempt = 1, 3 do
        pcall(function()
            char:PivotTo(seat.CFrame * CFrame.new(0, attempt == 1 and 1.5 or 0.4, 0))
        end)
        task.wait(0.1)
        pcall(function() seat:Sit(hum) end)
        for _ = 1, 8 do
            if seat.Occupant == hum then return true end
            task.wait(0.05)
        end
    end

    local pivot = bike:GetPivot()
    pcall(function() char:PivotTo(pivot * CFrame.new(2.5, 2, 0)) end)
    task.wait(0.15)
    local mountSkip = ReplicatedStorage:FindFirstChild("BikeMountSkip")
    if mountSkip and mountSkip:IsA("RemoteEvent") then
        pcall(function() mountSkip:FireServer(bike) end)
    end
    key(Enum.KeyCode.W, true)
    for _ = 1, 30 do
        if seat.Occupant == hum then break end
        task.wait(0.05)
    end
    key(Enum.KeyCode.W, false)
    return seat.Occupant == hum
end

----------------------------------------------------------------------
-- Never crash hook
----------------------------------------------------------------------
if Ragdoll and type(Ragdoll.fling) == "function" and not ENV.__BikeHubFlingHooked then
    ENV.__BikeHubFlingHooked = true
    local originalFling = Ragdoll.fling
    Ragdoll.fling = function(...)
        if ENV.__BikeFarmOn or ENV.__BikeHubRiderLock then return end
        return originalFling(...)
    end
end

local function riderLockTick()
    local seat, hum = driverSeat(), humanoid()
    if not (seat and hum) then return end
    if ENV.__BikeHubRiderLock and seat.Occupant ~= hum then
        local char = LocalPlayer.Character
        if char then
            pcall(function() char:PivotTo(seat.CFrame * CFrame.new(0, 1.5, 0)) end)
        end
        pcall(function() seat:Sit(hum) end)
    end
    if hum.PlatformStand then hum.PlatformStand = false end
    local state = hum:GetState()
    if state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.FallingDown then
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
end

----------------------------------------------------------------------
-- Settings / stats
----------------------------------------------------------------------
local Settings = {
    farmOn = false, height = 140, cooldown = 3.0,
    wheelieOn = false, riderLock = false,
    handlingAssist = false, brakeAssist = false,
    pumpkinFarm = false, playerEsp = false, policeEsp = false,
}

local Stats = {
    jumps = 0, lastCash = 0, lastSample = 0, perMinute = 0,
    launchPosition = nil, launchRotation = nil,
}

local Window
local UiRefs = {}

ENV.__BikeHubGen = (ENV.__BikeHubGen or 0) + 1
local SCRIPT_GENERATION = ENV.__BikeHubGen

local function scriptAlive()
    return ENV.__BikeHubGen == SCRIPT_GENERATION
end

----------------------------------------------------------------------
-- 1. TELEPORT FARM
----------------------------------------------------------------------
local anchor

local function captureAnchor()
    local part = chassis()
    anchor = part and part.Position or nil
end

local function holdAnchor()
    local bike, part = myBike(), chassis()
    if not (bike and part) then return end
    if not anchor then anchor = part.Position end
    local rotation = part.CFrame - part.CFrame.Position
    pcall(function() bike:PivotTo(CFrame.new(anchor) * rotation) end)
    part.AssemblyLinearVelocity = Vector3.zero
    part.AssemblyAngularVelocity = Vector3.zero
end

local function jumpOnce()
    local bike, part = myBike(), chassis()
    if not (bike and part) then
        spawnBike()
        task.wait(0.2)
        return false
    end
    if not isRiding() and not seatUp() then return false end

    if not bike:GetAttribute("Airborne") then
        Stats.launchPosition = part.Position
        Stats.launchRotation = part.CFrame - part.CFrame.Position
    end
    local base = Stats.launchPosition or part.Position
    local rotation = Stats.launchRotation or (part.CFrame - part.CFrame.Position)

    drive(1)
    bike:PivotTo(CFrame.new(base + Vector3.new(math.random(-25, 25), Settings.height, math.random(-25, 25))) * rotation)

    local started = os.clock()
    local lostRider = false
    while bike:GetAttribute("Airborne") and os.clock() - started < 30 do
        if not (Settings.farmOn and scriptAlive()) then return false end
        if not isRiding() then lostRider = true; break end
        task.wait(0.1)
    end
    if lostRider or bike:GetAttribute("Airborne") then
        bike:PivotTo(CFrame.new(base + Vector3.new(0, 6, 0)) * rotation)
        task.wait(0.5)
        seatUp()
    end
    task.wait(Settings.cooldown)
    drive(1)
    Stats.jumps += 1
    return true
end

local function farmSet(on)
    Settings.farmOn = on
    ENV.__BikeFarmOn = on
    if not on then
        driveStop()
        releaseKeys()
        Stats.launchPosition = nil
        Stats.launchRotation = nil
        log("Farm off")
        if UiRefs.farm then UiRefs.farm:Set(false, true) end
        return
    end
    task.spawn(function()
        if not seatUp() then
            log("<Warning>No bike found - spawn one first</Warning>")
            Settings.farmOn = false
            ENV.__BikeFarmOn = false
            if UiRefs.farm then UiRefs.farm:Set(false, true) end
            return
        end
        Stats.jumps = 0
        Stats.lastCash = cash()
        Stats.lastSample = os.clock()
        log(string.format("Farm on - jumps of %d studs", Settings.height))
        while Settings.farmOn and scriptAlive() do
            local ok, err = pcall(jumpOnce)
            if not ok then
                log("<Error>Jump: " .. tostring(err) .. "</Error>")
                task.wait(1)
            elseif not Settings.farmOn then
                break
            end
            task.wait(0.05)
        end
    end)
    if UiRefs.farm then UiRefs.farm:Set(true, true) end
end

----------------------------------------------------------------------
-- 2. AUTO WHEELIE
----------------------------------------------------------------------
local function wheelieCycle(throttle)
    key(Enum.KeyCode.LeftControl, false)
    task.wait(0.05)
    key(Enum.KeyCode.LeftControl, true)
    drive(throttle or 1, 0)
    task.wait(0.45)
    drive(0.2, 0)
    task.wait(0.45)
end

local function wheelieSet(on)
    Settings.wheelieOn = on
    ENV.__BikeHubWheelie = on
    if on then
        captureAnchor()
        log("Auto wheelie on")
        task.spawn(function()
            while Settings.wheelieOn and scriptAlive() do
                if isRiding() then
                    wheelieCycle(1)
                    holdAnchor()
                else
                    seatUp()
                    task.wait(0.2)
                end
            end
            driveStop()
            releaseKeys()
        end)
    else
        driveStop()
        releaseKeys()
        log("Auto wheelie off")
    end
    if UiRefs.wheelie then UiRefs.wheelie:Set(on, true) end
end

----------------------------------------------------------------------
-- 3. RIDER LOCK
----------------------------------------------------------------------
riderLockSet = function(on)
    Settings.riderLock = on
    ENV.__BikeHubRiderLock = on
    log(on and "Rider lock on" or "Rider lock off")
    if UiRefs.riderLock then UiRefs.riderLock:Set(on, true) end
end

----------------------------------------------------------------------
-- 4. PUMPKIN FARM
----------------------------------------------------------------------
pumpkinList = function()
    local list = {}
    local folder = workspace:FindFirstChild("MyPumpkins")
    if folder then
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("Model") and child:FindFirstChild("Body") then
                table.insert(list, child)
            end
        end
    end
    if #list > 0 then return list end
    local function scan(inst, depth)
        if depth > 4 then return end
        for _, child in ipairs(inst:GetChildren()) do
            if child:IsA("Model") and child.Name:lower():find("pumpkin") and child:FindFirstChild("Body") then
                table.insert(list, child)
            end
            if not child:IsA("Model") then scan(child, depth + 1) end
        end
    end
    scan(workspace, 0)
    return list
end

local function pumpkinSet(on)
    Settings.pumpkinFarm = on
    if on then
        task.spawn(function()
            while Settings.pumpkinFarm and scriptAlive() do
                local bike = myBike()
                local list = pumpkinList()
                if bike and #list > 0 then
                    local nearest, best
                    for _, pumpkin in ipairs(list) do
                        local distance = (pumpkin:GetPivot().Position - bike:GetPivot().Position).Magnitude
                        if not best or distance < best then
                            nearest, best = pumpkin, distance
                        end
                    end
                    if nearest then
                        drive(1, 0)
                        teleportBike(nearest:GetPivot() * CFrame.new(0, 6, 0))
                        task.wait(0.4)
                        drive(1, 0)
                        task.wait(0.4)
                    else
                        task.wait(0.5)
                    end
                else
                    task.wait(1)
                end
            end
        end)
        log("<Warning>Pumpkin farm on (experimental)</Warning>")
    else
        log("Pumpkin farm off")
    end
    if UiRefs.pumpkin then UiRefs.pumpkin:Set(on, true) end
end

----------------------------------------------------------------------
-- 5 + 6. ESP
----------------------------------------------------------------------
local esp = { player = {}, police = {} }

local function makeEsp(adornee, text, color)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "BikeHubEsp"
    billboard.Size = UDim2.fromOffset(220, 40)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = adornee
    billboard.Parent = PlayerGui

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 14
    label.TextColor3 = color
    label.TextStrokeTransparency = 0.4
    label.Text = text
    label.Parent = billboard

    local highlight = Instance.new("Highlight")
    highlight.Name = "BikeHubHighlight"
    highlight.FillColor = color
    highlight.FillTransparency = 0.75
    highlight.OutlineColor = color
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Adornee = adornee
    highlight.Parent = PlayerGui

    return { billboard = billboard, highlight = highlight, label = label }
end

local function clearEsp(kind)
    for _, entry in pairs(esp[kind]) do
        if entry.billboard then entry.billboard:Destroy() end
        if entry.highlight then entry.highlight:Destroy() end
    end
    esp[kind] = {}
end

local function clearOldEsp()
    for _, child in ipairs(PlayerGui:GetChildren()) do
        if child.Name == "BikeHubEsp" or child.Name == "BikeHubHighlight" then
            child:Destroy()
        end
    end
end
task.spawn(clearOldEsp)

local function refreshPlayerEsp()
    local alive = {}
    local me = bikePosition()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local torso = player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Torso")
            if torso then
                alive[torso] = true
                if not esp.player[torso] then
                    esp.player[torso] = makeEsp(torso, player.Name, Color3.fromRGB(255, 59, 127))
                end
                local distance = me and math.floor((torso.Position - me).Magnitude) or 0
                esp.player[torso].label.Text = string.format("%s  [%d]", player.Name, distance)
            end
        end
    end
    for torso, entry in pairs(esp.player) do
        if not alive[torso] or not torso.Parent then
            entry.billboard:Destroy()
            entry.highlight:Destroy()
            esp.player[torso] = nil
        end
    end
end

local function refreshPoliceEsp()
    local alive = {}
    local folder = workspace:FindFirstChild("Police")
    if not folder then return end
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") then
            local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
            if root then
                alive[root] = true
                if not esp.police[root] then
                    esp.police[root] = makeEsp(root, "POLICE", Color3.fromRGB(70, 140, 255))
                end
            end
        end
    end
    for root, entry in pairs(esp.police) do
        if not alive[root] or not root.Parent then
            entry.billboard:Destroy()
            entry.highlight:Destroy()
            esp.police[root] = nil
        end
    end
end

task.spawn(function()
    while scriptAlive() do
        pcall(function()
            if Settings.playerEsp then refreshPlayerEsp()
            elseif next(esp.player) then clearEsp("player") end
            if Settings.policeEsp then refreshPoliceEsp()
            elseif next(esp.police) then clearEsp("police") end
        end)
        task.wait(0.5)
    end
end)

----------------------------------------------------------------------
-- 7. BIKE TUNING
----------------------------------------------------------------------
local TUNING_DEFAULTS = {
    MaxSpeedKmh = 400, LaunchAccel = 5.5, PowerPerKg = 250,
    TireGrip = 1.35, AirGravity = 50, WheelieStrength = 1.1,
    BrakeDecel = 22, SteerSpeed = 3.5, BrakePower = 2.0,
}

local TUNING_VALUES = ENV.__BikeHubTuningValues
if type(TUNING_VALUES) ~= "table" then
    TUNING_VALUES = {}
    ENV.__BikeHubTuningValues = TUNING_VALUES
end
for name, defaultValue in pairs(TUNING_DEFAULTS) do
    if type(TUNING_VALUES[name]) ~= "number" then
        TUNING_VALUES[name] = defaultValue
    end
end

if TUNING_VALUES.BrakeDecel == 7 then TUNING_VALUES.BrakeDecel = 22 end
if TUNING_VALUES.TireGrip  == 0.95 then TUNING_VALUES.TireGrip = 1.35 end
if TUNING_VALUES.LaunchAccel == 4.2 then TUNING_VALUES.LaunchAccel = 5.5 end
if TUNING_VALUES.MaxSpeedKmh > 400 then TUNING_VALUES.MaxSpeedKmh = 400 end
if TUNING_VALUES.PowerPerKg > 250 then TUNING_VALUES.PowerPerKg = 250 end
if TUNING_VALUES.TireGrip > 3 then TUNING_VALUES.TireGrip = 3 end
if TUNING_VALUES.BrakeDecel > 50 then TUNING_VALUES.BrakeDecel = 50 end
if TUNING_VALUES.LaunchAccel > 30 then TUNING_VALUES.LaunchAccel = 30 end
if TUNING_VALUES.SteerSpeed > 10 then TUNING_VALUES.SteerSpeed = 10 end
if TUNING_VALUES.BrakePower > 10 then TUNING_VALUES.BrakePower = 10 end

local function applyTuningToBike(bike, name, value)
    if bike and bike.Parent and bike:IsA("Model") then
        pcall(function() bike:SetAttribute(name, value) end)
    end
end

local function applyAllTuning(bike)
    bike = bike or myBike()
    if not bike then return false end
    for name, value in pairs(TUNING_VALUES) do
        if TUNING_DEFAULTS[name] ~= nil then
            applyTuningToBike(bike, name, value)
        end
    end
    return true
end

local function applyTuning(name, value)
    if TUNING_DEFAULTS[name] == nil or type(value) ~= "number" then return end
    TUNING_VALUES[name] = value
    ENV.__BikeHubTuningValues = TUNING_VALUES
    applyTuningToBike(myBike(), name, value)
end

local function resetTuning()
    for name, value in pairs(TUNING_DEFAULTS) do
        TUNING_VALUES[name] = value
    end
    ENV.__BikeHubTuningValues = TUNING_VALUES
    applyAllTuning()
    log("Bike tuning reset to defaults; values will stay applied to future bikes")
end

workspace.ChildAdded:Connect(function(child)
    task.spawn(function()
        for attempt = 1, 12 do
            if not scriptAlive() then return end
            if child:IsA("Model") and child:GetAttribute("Owner") == LocalPlayer.UserId then
                for _, delayTime in ipairs({ 0, 0.15, 0.5, 1 }) do
                    if delayTime > 0 then task.wait(delayTime) end
                    if child.Parent and child:GetAttribute("Owner") == LocalPlayer.UserId then
                        applyAllTuning(child)
                    end
                end
                log("Saved bike tuning applied to spawned bike")
                return
            end
            task.wait(0.1)
        end
    end)
end)

task.spawn(function()
    for _ = 1, 20 do
        if not scriptAlive() then return end
        local bike = myBike()
        if bike then applyAllTuning(bike); return end
        task.wait(0.25)
    end
end)

----------------------------------------------------------------------
-- Handling / brake assist
----------------------------------------------------------------------
local lastHandlingTick = os.clock()

local function handlingTick()
    local now = os.clock()
    local dt = math.min(now - lastHandlingTick, 0.05)
    lastHandlingTick = now
    if dt <= 0 then return end
    if not (Settings.handlingAssist or Settings.brakeAssist) then return end
    if not isRiding() then return end
    local bike, part = myBike(), chassis()
    if not (bike and part) then return end

    local vel = part.AssemblyLinearVelocity

    if Settings.handlingAssist then
        if math.abs(vel.Y) < 8 then
            local up = part.CFrame.UpVector
            if up.Y < 0.7 and up.Y > 0.1 then
                local targetUp = Vector3.new(0, 1, 0)
                local axis = up:Cross(targetUp)
                if axis.Magnitude > 0.01 then
                    local strength = (1 - up.Y) * 3
                    part.AssemblyAngularVelocity = part.AssemblyAngularVelocity
                        + axis.Unit * strength * dt
                end
            end
        end
        local steerInput = 0
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then steerInput -= 1 end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then steerInput += 1 end
        if steerInput ~= 0 and math.abs(vel.Y) < 6 then
            local flat = Vector3.new(vel.X, 0, vel.Z)
            if flat.Magnitude > 4 then
                local right = part.CFrame.RightVector
                local push = right * steerInput * flat.Magnitude * dt * 0.6
                part.AssemblyLinearVelocity = vel + Vector3.new(push.X, 0, push.Z)
                vel = part.AssemblyLinearVelocity
            end
        end
    end

    if Settings.brakeAssist then
        local braking = UserInputService:IsKeyDown(Enum.KeyCode.S)
            or UserInputService:IsKeyDown(Enum.KeyCode.Space)
        if braking then
            local flat = Vector3.new(vel.X, 0, vel.Z)
            if flat.Magnitude > 1 then
                local damp = math.clamp(1.5 * dt, 0, 1)
                local newFlat = flat * (1 - damp)
                part.AssemblyLinearVelocity = Vector3.new(newFlat.X, vel.Y, newFlat.Z)
            end
        end
    end
end

----------------------------------------------------------------------
-- 8. TELEPORTS
----------------------------------------------------------------------
local LANDMARKS = {
    "HighwayEntery", "LongHighway", "HighwayRace", "HighwayTunnels",
    "MegaRamp", "Garage", "PumpkinSHop", "PumpkinBikeStand",
    "TownRace", "BikeDealer", "LuxuryStand", "VargShowcase",
}

local savedSpots = {}

teleportBike = function(cframe)
    local bike = myBike()
    local char = LocalPlayer.Character
    if not bike then
        if char then pcall(function() char:PivotTo(cframe) end) end
        spawnBike()
        return false
    end
    local seat, hum = driverSeat(), humanoid()
    if seat and hum and seat.Occupant ~= hum then
        pcall(function() seat:Sit(hum) end)
        task.wait(0.1)
    end
    local seated = seat and hum and seat.Occupant == hum
    bike:PivotTo(cframe)
    if char and not seated then
        pcall(function() char:PivotTo(cframe * CFrame.new(0, 2.2, 0)) end)
    end
    for _ = 1, 6 do
        task.wait(0.06)
        if (bike:GetPivot().Position - cframe.Position).Magnitude > 30 then
            bike:PivotTo(cframe)
            if char and not seated then
                pcall(function() char:PivotTo(cframe * CFrame.new(0, 2.2, 0)) end)
            end
        end
    end
    if not isRiding() then seatUp() end
    return true
end

local function landmarkCFrame(name)
    local model = workspace:FindFirstChild(name)
    if model and model:IsA("Model") then
        return model:GetPivot() * CFrame.new(0, 4, 0)
    end
    return nil
end

----------------------------------------------------------------------
-- WINDOW
----------------------------------------------------------------------
local THEME = {
    Background = Color3.fromHex("#0A0A0C"),
    Surface    = Color3.fromHex("#141418"),
    Surface2   = Color3.fromHex("#1A1A20"),
    Surface3   = Color3.fromHex("#2A2A33"),
    Stroke     = Color3.fromHex("#26262E"),
    StrokeHover= Color3.fromHex("#3C3C49"),
    Accent     = Color3.fromHex("#FF3B7F"),
    AccentDark = Color3.fromHex("#1A0710"),
    Text       = Color3.fromHex("#F5F5F7"),
    Muted      = Color3.fromHex("#8D8D99"),
}

Airflow.ThemePresets.Robscript = THEME
Airflow:SetDefaultTheme(THEME)

Window = Airflow:CreateWindow({
    Name = "Bike Universe Hub",
    LoadingSubtitle = "farm, tricks, ESP",
    ToggleUIKeybind = "RightControl",
    Size = UDim2.fromOffset(780, 540),
    Backdrop = { Weather = "Fireflies", Tint = 0.35 },
    Theme = THEME,
    ConfigurationSaving = { Enabled = true, FolderName = "BikeUniverseHub" },
    Home = {
        Title = "Bike Universe Hub",
        Welcome = "Welcome back,",
        Tier = "v2.2",
        Stats = { "Players", "Session", "FPS", "Ping", "Game", "Executor" },
    },
})

local LogTab = Window:CreateTab({ Name = "Logs", Icon = "scroll-text" })
local LogBox = LogTab:CreateGroupbox({ Name = "What the script is doing", Side = "Left" })
local LogElement = LogBox:CreateLog({
    Name = "Activity", MaxEntries = 300, MaxRows = 14,
    Timestamps = true, EmptyText = "Nothing yet",
})

log = function(message)
    if LogElement then LogElement:Push(tostring(message)) end
end

----------------------------------------------------------------------
-- FARM TAB
----------------------------------------------------------------------
local FarmTab  = Window:CreateTab({ Name = "Farm", Icon = "coins" })
local FarmMain = FarmTab:CreateGroupbox({ Name = "Air time farm", Side = "Left" })
local FarmInfo = FarmTab:CreateGroupbox({ Name = "Numbers", Side = "Right" })

UiRefs.farm = FarmMain:CreateToggle({
    Name = "AFK cash farm",
    Desc = "Throws the bike up, keeps the throttle open and lets the fall pay",
    Flag = "FarmOn", CurrentValue = false,
    Callback = function(on) farmSet(on) end,
})

FarmMain:CreateSlider({
    Name = "Jump height", Desc = "Higher jump, longer fall, more cash per landing",
    Range = { 80, 500 }, Increment = 20, Suffix = " studs",
    CurrentValue = 300, Flag = "JumpHeight",
    Callback = function(value) Settings.height = value end,
})

FarmMain:CreateSlider({
    Name = "Jump cooldown",
    Desc = "How long the bike stands on the ground before the next jump",
    Range = { 0.2, 3 }, Increment = 0.1, Suffix = " s",
    CurrentValue = 0.6, Flag = "JumpCooldown",
    Callback = function(value) Settings.cooldown = value end,
})

FarmInfo:CreateStatus({
    Name = "Cash", Style = "Row", Pin = true,
    Update = function() return "<Success>" .. short(cash()) .. "</Success>" end,
})

FarmInfo:CreateStatus({
    Name = "Per minute", Style = "Row",
    Update = function()
        local now = os.clock()
        local delta = cash() - (Stats.lastCash or cash())
        local window = now - (Stats.lastSample or now)
        if window > 5 then
            Stats.perMinute = delta * (60 / window)
            Stats.lastSample = now
            Stats.lastCash = cash()
        end
        return short(Stats.perMinute)
    end,
})

FarmInfo:CreateStatus({
    Name = "Jumps", Style = "Row",
    Update = function() return tostring(Stats.jumps) end,
})

FarmInfo:CreateStatus({
    Name = "Seated", Style = "Row",
    Update = function() return isRiding() and "<Success>yes</Success>" or "<Muted>no</Muted>" end,
})

FarmInfo:CreateParagraph({
    Title = "How it pays",
    Content = "Cash comes from trick lines, and air time is what a line is worth. The farm throws the bike straight up, "
        .. "keeps full throttle on the way down, and the landing closes the line and pays out.",
})

----------------------------------------------------------------------
-- BIKE TAB
----------------------------------------------------------------------
local BikeTab  = Window:CreateTab({ Name = "Bike", Icon = "bike" })
local BikeMain = BikeTab:CreateGroupbox({ Name = "Assist", Side = "Left" })
local BikeTune = BikeTab:CreateGroupbox({ Name = "Movement", Side = "Right" })
local BikeInfo = BikeTab:CreateGroupbox({ Name = "Status", Side = "Right" })

UiRefs.wheelie = BikeMain:CreateToggle({
    Name = "Auto wheelie", Desc = "Holds a wheelie and keeps you on the bike",
    Flag = "Wheelie", CurrentValue = false,
    Callback = function(on) wheelieSet(on) end,
})

UiRefs.riderLock = BikeMain:CreateToggle({
    Name = "No crash / no ragdoll",
    Desc = "The crash call is blocked, so the game cannot throw you off",
    Flag = "RiderLock", CurrentValue = false,
    Callback = function(on) riderLockSet(on) end,
})

UiRefs.handling = BikeMain:CreateToggle({
    Name = "Handling assist",
    Desc = "Anti-flip + sharper steering while riding",
    Flag = "HandlingAssist", CurrentValue = false,
    Callback = function(on)
        Settings.handlingAssist = on
        log(on and "Handling assist on" or "Handling assist off")
    end,
})

UiRefs.brake = BikeMain:CreateToggle({
    Name = "Brake assist",
    Desc = "Extra stopping power while holding S or Space",
    Flag = "BrakeAssist", CurrentValue = false,
    Callback = function(on)
        Settings.brakeAssist = on
        log(on and "Brake assist on" or "Brake assist off")
    end,
})

BikeMain:CreateButton({
    Name = "Sit on the bike", Icon = "bike",
    Callback = function()
        task.spawn(function()
            if seatUp() then log("On the bike")
            else log("<Warning>No bike nearby - spawn one first</Warning>") end
        end)
    end,
})

UiRefs.pumpkin = BikeMain:CreateToggle({
    Name = "Pumpkin farm",
    Desc = "Experimental: hops you onto the nearest pumpkin",
    Flag = "PumpkinFarm", CurrentValue = false,
    Callback = function(on) pumpkinSet(on) end,
})

local function tuningSlider(name, label, range, increment, suffix, flag)
    BikeTune:CreateSlider({
        Name = label, Range = range, Increment = increment, Suffix = suffix,
        CurrentValue = TUNING_VALUES[name], Flag = flag,
        Callback = function(value) applyTuning(name, value) end,
    })
end

tuningSlider("MaxSpeedKmh",     "Max speed",       {40, 400}, 5,    " km/h", "TuneSpeed")
tuningSlider("LaunchAccel",     "Launch accel",    {1, 30},   0.5,  nil,     "TuneAccel")
tuningSlider("PowerPerKg",      "Power per kg",    {10, 250}, 5,    nil,     "TunePower")
tuningSlider("TireGrip",        "Tire grip",       {0.2, 3},  0.05, nil,     "TuneGrip")
tuningSlider("AirGravity",      "Air gravity",     {0, 120},  5,    nil,     "TuneAirGravity")
tuningSlider("WheelieStrength", "Wheelie strength",{0.2, 4},  0.1,  nil,     "TuneWheelie")
tuningSlider("BrakeDecel",      "Brake decel",     {1, 50},   1,    nil,     "TuneBrake")
tuningSlider("SteerSpeed",      "Steer speed",     {0.5, 10}, 0.5,  nil,     "TuneSteer")
tuningSlider("BrakePower",      "Brake power",     {0.5, 10}, 0.5,  nil,     "TuneBrakePower")

BikeTune:CreateButton({
    Name = "Reset tuning", Icon = "rotate-ccw",
    Callback = function() resetTuning
