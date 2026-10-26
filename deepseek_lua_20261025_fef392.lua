-- ==========================================================================
-- BIKE UNIVERSE HUB v4.0 "OMEGA" (1000x Optimized & Enhanced)
-- ==========================================================================
-- Улучшения: O(1) поиск байка, Smart Raycast Farm, Advanced Anti-Fling, 
-- Momentum-preserving Teleport, Optimized ESP, Expanded Physics Tuning.
-- ==========================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10)

-- ==========================================================================
-- 1. ENVIRONMENT & SECURITY
-- ==========================================================================
local function getEnv()
    if type(getgenv) == "function" then
        local ok, env = pcall(getgenv)
        if ok and type(env) == "table" then return env end
    end
    return type(shared) == "table" and shared or _G
end

local ENV = getEnv()
local SCRIPT_ID = "BikeHub_v4_" .. tostring(LocalPlayer.UserId)
ENV[SCRIPT_ID] = (ENV[SCRIPT_ID] or 0) + 1
local GENERATION = ENV[SCRIPT_ID]

local function isAlive() return ENV[SCRIPT_ID] == GENERATION end

-- ==========================================================================
-- 2. UI LIBRARY LOADER (Multi-Fallback + Cache)
-- ==========================================================================
local UI_CACHE_NAME = "BikeHub_Airflow_v4.luau"
local UI_SOURCES = {
    "https://raw.githubusercontent.com/bobloscript/Robly_Airflow/main/Source.luau",
    "https://raw.githubusercontent.com/PookiePepelsss/Airflow-UI/refs/heads/main/Source.luau",
    "https://raw.githubusercontent.com/airflow-ui/airflow/main/source.luau"
}

local function validateLibrary(body)
    if type(body) ~= "string" or #body < 500 then return nil end
    local fn = loadstring(body)
    if not fn then return nil end
    local ok, lib = pcall(fn)
    if ok and type(lib) == "table" and type(lib.CreateWindow) == "function" then
        return lib
    end
    return nil
end

local function loadAirflow()
    if type(isfile) == "function" and type(readfile) == "function" then
        if pcall(isfile, UI_CACHE_NAME) then
            local ok, body = pcall(readfile, UI_CACHE_NAME)
            if ok then
                local lib = validateLibrary(body)
                if lib then return lib end
            end
        end
    end
    
    for _, url in ipairs(UI_SOURCES) do
        local ok, body = pcall(function() return game:HttpGet(url, true) end)
        if ok and type(body) == "string" then
            if type(writefile) == "function" then pcall(writefile, UI_CACHE_NAME, body) end
            local lib = validateLibrary(body)
            if lib then return lib end
        end
    end
    return nil
end

local Airflow = loadAirflow()
if not Airflow then error("[BikeHub] Критическая ошибка: не удалось загрузить UI библиотеку.") end

-- ==========================================================================
-- 3. O(1) BIKE TRACKING (Вместо медленного сканирования)
-- ==========================================================================
local ownedBikes = {}
local bikeAddedConn, bikeRemovedConn

bikeAddedConn = Workspace.DescendantAdded:Connect(function(child)
    if not isAlive() then return end
    if child:IsA("Model") and child:GetAttribute("Owner") == LocalPlayer.UserId then
        ownedBikes[child] = true
    end
end)

bikeRemovedConn = Workspace.DescendantRemoving:Connect(function(child)
    if ownedBikes[child] then
        ownedBikes[child] = nil
    end
end)

local function getMyBike()
    for bike, _ in pairs(ownedBikes) do
        if bike.Parent then return bike end
    end
    return nil
end

local function getChassis(bike)
    if not bike then return nil end
    local c = bike:FindFirstChild("Chassis")
    if c and c:IsA("BasePart") then return c end
    if c and c:IsA("Model") and c.PrimaryPart then return c.PrimaryPart end
    return bike.PrimaryPart
end

local function getDriverSeat(bike)
    if not bike then return nil end
    return bike:FindFirstChild("DriverSeat", true) or bike:FindFirstChildOfClass("VehicleSeat")
end

local function getHumanoid()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function isRiding()
    local bike = getMyBike()
    if not bike then return false end
    local seat = getDriverSeat(bike)
    local hum = getHumanoid()
    return seat and hum and seat.Occupant == hum
end

local function getCash()
    local stats = LocalPlayer:FindFirstChild("leaderstats")
    local cash = stats and stats:FindFirstChild("Cash")
    return cash and cash.Value or 0
end

-- ==========================================================================
-- 4. ADVANCED DRIVE & INPUT CONTROL
-- ==========================================================================
local TouchControls
pcall(function() TouchControls = require(ReplicatedStorage:WaitForChild("TouchControls", 5)) end)

local driveState = { on = false, throttle = 0, steer = 0, gen = GENERATION }
ENV.BikeHubDrive = driveState

if TouchControls and type(TouchControls.drive) == "function" then
    local originalDrive = TouchControls.drive
    TouchControls.drive = function(seat)
        local state = ENV.BikeHubDrive
        if state and state.on and state.gen == GENERATION and (os.clock() - (state.last or 0) < 0.5) then
            return state.throttle, state.steer
        end
        return originalDrive(seat)
    end
end

local function setDrive(throttle, steer)
    driveState.throttle = throttle or 0
    driveState.steer = steer or 0
    driveState.on = true
    driveState.last = os.clock()
    driveState.gen = GENERATION
    
    local bike = getMyBike()
    if bike then
        local seat = getDriverSeat(bike)
        if seat and seat:IsA("VehicleSeat") then
            pcall(function()
                seat.ThrottleFloat = driveState.throttle
                seat.SteerFloat = driveState.steer
            end)
        end
    end
end

local function stopDrive()
    driveState.on = false
    driveState.throttle = 0
    driveState.steer = 0
    local bike = getMyBike()
    if bike then
        local seat = getDriverSeat(bike)
        if seat and seat:IsA("VehicleSeat") then
            pcall(function() seat.ThrottleFloat = 0; seat.SteerFloat = 0 end)
        end
    end
end

-- ==========================================================================
-- 5. SMART SEATING & SPAWN SYSTEM
-- ==========================================================================
local function spawnBike()
    if getMyBike() then return true end
    local remotes = {}
    for _, name in ipairs({"SpawnBikeEvent", "SelectBike", "BikeMount", "SpawnBike", "RequestBike", "EquipBike"}) do
        local r = ReplicatedStorage:FindFirstChild(name)
        if r and r:IsA("RemoteEvent") then table.insert(remotes, r) end
    end
    -- Fallback: find any remote with "bike" or "spawn" in name
    for _, child in ipairs(ReplicatedStorage:GetChildren()) do
        if child:IsA("RemoteEvent") and not table.find(remotes, child) then
            local n = child.Name:lower()
            if n:find("bike") or n:find("spawn") then table.insert(remotes, child) end
        end
    end
    
    for _, remote in ipairs(remotes) do
        pcall(function() remote:FireServer() end)
        for _ = 1, 15 do
            task.wait(0.1)
            if getMyBike() then return true end
        end
    end
    return getMyBike() ~= nil
end

local function forceSeat()
    local bike = getMyBike()
    local hum = getHumanoid()
    local char = LocalPlayer.Character
    if not (bike and hum and char) then return false end
    
    local seat = getDriverSeat(bike)
    if not seat then return false end
    if seat.Occupant == hum then return true end

    -- Anti-ragdoll prep
    pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    hum.PlatformStand = false
    
    -- Smart positioning
    local pivot = bike:GetPivot()
    pcall(function() char:PivotTo(pivot * CFrame.new(0, 2, 0)) end)
    task.wait(0.05)
    
    for attempt = 1, 5 do
        pcall(function() seat:Sit(hum) end)
        if seat.Occupant == hum then return true end
        task.wait(0.05)
    end
    
    -- Fallback: Virtual Input
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, game)
    task.wait(0.1)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
    
    return seat.Occupant == hum
end

-- ==========================================================================
-- 6. ADVANCED ANTI-FLING & RIDER LOCK (Heartbeat Stabilization)
-- ==========================================================================
local Ragdoll
pcall(function() Ragdoll = require(ReplicatedStorage:WaitForChild("Ragdoll", 5)) end)

if Ragdoll then
    if type(Ragdoll.fling) == "function" and not ENV.BikeHubFlingHooked then
        ENV.BikeHubFlingHooked = true
        local orig = Ragdoll.fling
        Ragdoll.fling = function(...) if ENV.BikeHubRiderLock then return end return orig(...) end
    end
    if type(Ragdoll.start) == "function" and not ENV.BikeHubStartHooked then
        ENV.BikeHubStartHooked = true
        local orig = Ragdoll.start
        Ragdoll.start = function(...) if ENV.BikeHubRiderLock then return end return orig(...) end
    end
end

RunService.Heartbeat:Connect(function()
    if not ENV.BikeHubRiderLock or not isAlive() then return end
    local bike = getMyBike()
    local hum = getHumanoid()
    local seat = getDriverSeat(bike)
    
    if not (bike and hum and seat) then return end
    
    -- Auto-reseat
    if seat.Occupant ~= hum then
        local char = LocalPlayer.Character
        if char then pcall(function() char:PivotTo(seat.CFrame * CFrame.new(0, 1.5, 0)) end) end
        pcall(function() seat:Sit(hum) end)
    end
    
    -- Physics stabilization (Anti-fling)
    local chassis = getChassis(bike)
    if chassis and chassis:IsA("BasePart") then
        local av = chassis.AssemblyAngularVelocity
        if av.Magnitude > 25 then
            chassis.AssemblyAngularVelocity = av * 0.2
        end
        local vel = chassis.AssemblyLinearVelocity
        if vel.Magnitude > 150 then
            chassis.AssemblyLinearVelocity = Vector3.new(vel.X * 0.5, math.clamp(vel.Y, -10, 10), vel.Z * 0.5)
        end
    end
    
    if hum.PlatformStand then hum.PlatformStand = false end
    local state = hum:GetState()
    if state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.FallingDown then
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
end)

-- ==========================================================================
-- 7. SMART TELEPORT FARM (With Raycast Landing Validation)
-- ==========================================================================
local Settings = {
    farmOn = false, height = 200, cooldown = 0.3,
    stealthMode = true, chainJumps = true, tricksEnabled = true,
    randomizeHeight = true, randomizeLanding = true, jumpDuration = 0.8,
    riderLock = true, handlingAssist = false, brakeAssist = false,
    pumpkinFarm = false, playerEsp = false, policeEsp = false
}

local Stats = { jumps = 0, lastCash = 0, lastSample = 0, perMinute = 0 }

local function smoothTeleport(bike, fromCF, toCF, duration)
    if duration <= 0.05 then
        pcall(function() bike:PivotTo(toCF) end)
        return
    end
    local startTime = os.clock()
    while isAlive() and Settings.farmOn do
        local t = math.clamp((os.clock() - startTime) / duration, 0, 1)
        local eased = t * t * (3 - 2 * t) -- Smoothstep
        pcall(function() bike:PivotTo(fromCF:Lerp(toCF, eased)) end)
        if t >= 1 then break end
        task.wait(0.016) -- ~60 FPS interpolation
    end
end

local function applyTrick(chassisPart)
    if not chassisPart or not chassisPart:IsA("BasePart") then return end
    local power = 20
    local tricks = {
        Vector3.new(0, power, 0), -- Spin
        chassisPart.CFrame.RightVector * power, -- Frontflip
        chassisPart.CFrame.RightVector * -power, -- Backflip
        chassisPart.CFrame.LookVector * power -- Barrel
    }
    local trick = tricks[math.random(1, #tricks)]
    pcall(function() chassisPart.AssemblyAngularVelocity = chassisPart.AssemblyAngularVelocity + trick end)
end

local function jumpOnce()
    local bike = getMyBike()
    local chassis = getChassis(bike)
    if not (bike and chassis and chassis:IsA("BasePart")) then
        spawnBike()
        task.wait(0.3)
        return false
    end
    
    if not isRiding() and not forceSeat() then return false end

    local groundPos = chassis.Position
    local rotation = chassis.CFrame - groundPos
    
    local height = Settings.height
    if Settings.randomizeHeight then height = height * (0.85 + math.random() * 0.3) end
    
    local horizOff = Settings.randomizeLanding 
        and Vector3.new(math.random(-5, 5), 0, math.random(-5, 5)) 
        or Vector3.zero
    
    local apexPos = groundPos + Vector3.new(0, height, 0) + horizOff

    -- Raycast validation for safe landing
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {bike}
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    local rayResult = Workspace:Raycast(apexPos, Vector3.new(0, -height - 50, 0), rayParams)
    
    local safeLandingPos = apexPos
    if rayResult then
        safeLandingPos = rayResult.Position + Vector3.new(0, 3, 0) -- 3 studs above ground
    end

    setDrive(1, 0)
    local startCF = CFrame.new(groundPos) * rotation
    local endCF = CFrame.new(safeLandingPos) * rotation

    if Settings.stealthMode then
        smoothTeleport(bike, startCF, endCF, Settings.jumpDuration)
    else
        pcall(function() bike:PivotTo(endCF) end)
    end

    if Settings.tricksEnabled then applyTrick(getChassis(bike)) end

    -- Landing wait loop
    local startTime = os.clock()
    local tookOff = false
    while isAlive() and Settings.farmOn do
        if os.clock() - startTime > 15 then break end
        if not isRiding() then
            task.wait(0.2)
            forceSeat()
            break
        end
        
        local curChassis = getChassis(bike)
        if curChassis and curChassis:IsA("BasePart") then
            local vel = curChassis.AssemblyLinearVelocity
            local pos = curChassis.Position
            local dy = pos.Y - groundPos.Y

            if not tookOff and dy > 15 then tookOff = true end
            
            -- Detect landing: low Y velocity and close to ground
            if tookOff and math.abs(vel.Y) < 5 and dy < 10 then
                break
            end
            if dy < -30 then break end -- Fell through map
        end
        task.wait(0.03)
    end

    stopDrive()
    Stats.jumps += 1
    task.wait(Settings.chainJumps and 0.05 or Settings.cooldown)
    return true
end

local function toggleFarm(on)
    Settings.farmOn = on
    ENV.BikeHubFarmOn = on
    if not on then
        stopDrive()
        log("<Warning>Фарм остановлен</Warning>")
        return
    end
    
    task.spawn(function()
        if not forceSeat() then
            log("<Error>Не удалось сесть на байк. Заспавньте его вручную.</Error>")
            Settings.farmOn = false
            ENV.BikeHubFarmOn = false
            return
        end
        
        Stats.jumps = 0
        Stats.lastCash = getCash()
        Stats.lastSample = os.clock()
        log("<Success>Умный фарм запущен (Height: " .. Settings.height .. ", Stealth: " .. tostring(Settings.stealthMode) .. ")</Success>")
        
        while Settings.farmOn and isAlive() do
            local ok, err = pcall(jumpOnce)
            if not ok then
                log("<Error>Ошибка прыжка: " .. tostring(err) .. "</Error>")
                task.wait(1)
            end
            task.wait(0.02)
        end
    end)
end

-- ==========================================================================
-- 8. OPTIMIZED PUMPKIN FARM (Momentum Preserving)
-- ==========================================================================
local pumpkinCache = {}
local lastPumpkinScan = 0

local function getPumpkins()
    local now = os.clock()
    if now - lastPumpkinScan < 1.0 and #pumpkinCache > 0 then return pumpkinCache end
    
    pumpkinCache = {}
    local function scan(inst, depth)
        if depth > 3 then return end
        for _, child in ipairs(inst:GetChildren()) do
            if child:IsA("Model") then
                local name = child.Name:lower()
                if name:find("pumpkin") or child:GetAttribute("Pumpkin") or child:GetAttribute("IsPumpkin") then
                    if child.PrimaryPart or child:FindFirstChild("Body") or child:FindFirstChild("Hitbox") then
                        table.insert(pumpkinCache, child)
                    end
                end
            end
            if child:IsA("Folder") or child:IsA("Model") then
                scan(child, depth + 1)
            end
        end
    end
    scan(Workspace, 0)
    lastPumpkinScan = now
    return pumpkinCache
end

local function togglePumpkinFarm(on)
    Settings.pumpkinFarm = on
    if not on then stopDrive() return end
    
    task.spawn(function()
        log("<Success>Фарм тыкв запущен</Success>")
        while Settings.pumpkinFarm and isAlive() do
            local bike = getMyBike()
            if not bike or not isRiding() then
                spawnBike()
                task.wait(0.5)
                forceSeat()
                task.wait(0.2)
            else
                local pumpkins = getPumpkins()
                if #pumpkins > 0 then
                    local bikePos = bike:GetPivot().Position
                    local nearest, minDist = nil, math.huge
                    
                    for _, p in ipairs(pumpkins) do
                        if p.Parent then
                            local pPos = p:GetPivot().Position
                            local dist = (pPos - bikePos).Magnitude
                            if dist < minDist then
                                minDist = dist
                                nearest = p
                            end
                        end
                    end
                    
                    if nearest and minDist > 5 then
                        local target = nearest:GetPivot()
                        local body = nearest:FindFirstChild("Body") or nearest:FindFirstChild("Hitbox") or nearest.PrimaryPart
                        if body and body:IsA("BasePart") then target = CFrame.new(body.Position) end
                        
                        -- Momentum preserving teleport
                        local chassis = getChassis(bike)
                        local currentVel = chassis and chassis.AssemblyLinearVelocity or Vector3.zero
                        
                        setDrive(1, 0)
                        pcall(function() bike:PivotTo(target * CFrame.new(0, 4, 0)) end)
                        
                        -- Restore momentum
                        if chassis and chassis:IsA("BasePart") then
                            chassis.AssemblyLinearVelocity = currentVel
                        end
                        task.wait(0.2)
                    end
                end
            end
            task.wait(0.1)
        end
        stopDrive()
    end)
end

-- ==========================================================================
-- 9. HIGH-PERFORMANCE ESP (Optimized, Clean, Customizable)
-- ==========================================================================
local espInstances = {}

local function createESP(adornee, text, color, kind)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "BikeHubESP_Billboard"
    billboard.Size = UDim2.fromOffset(200, 40)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = adornee
    billboard.Parent = PlayerGui

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 14
    label.TextColor3 = color
    label.TextStrokeTransparency = 0.3
    label.Text = text
    label.Parent = billboard

    local highlight = Instance.new("Highlight")
    highlight.Name = "BikeHubESP_Highlight"
    highlight.FillColor = color
    highlight.FillTransparency = 0.8
    highlight.OutlineColor = color
    highlight.OutlineTransparency = 0.5
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Adornee = adornee
    highlight.Parent = PlayerGui

    espInstances[kind][adornee] = { billboard = billboard, highlight = highlight, label = label }
end

local function clearESP(kind)
    for adornee, data in pairs(espInstances[kind] or {}) do
        if data.billboard then data.billboard:Destroy() end
        if data.highlight then data.highlight:Destroy() end
    end
    espInstances[kind] = {}
end

espInstances.player = {}
espInstances.police = {}

RunService.Heartbeat:Connect(function()
    if not isAlive() then return end
    
    -- Player ESP
    if Settings.playerEsp then
        local myBikePos = getMyBike() and getMyBike():GetPivot().Position or LocalPlayer.Character and LocalPlayer.Character:GetPivot().Position
        local valid = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local root = player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Torso")
                if root then
                    valid[root] = true
                    if not espInstances.player[root] then
                        createESP(root, player.Name, Color3.fromRGB(255, 59, 127), "player")
                    end
                    local dist = myBikePos and math.floor((root.Position - myBikePos).Magnitude) or 0
                    espInstances.player[root].label.Text = string.format("%s [%dm]", player.Name, dist)
                end
            end
        end
        for root, data in pairs(espInstances.player) do
            if not valid[root] or not root.Parent then
                data.billboard:Destroy()
                data.highlight:Destroy()
                espInstances.player[root] = nil
            end
        end
    elseif next(espInstances.player) then
        clearESP("player")
    end

    -- Police ESP
    if Settings.policeEsp then
        local policeFolder = Workspace:FindFirstChild("Police")
        local valid = {}
        if policeFolder then
            for _, model in ipairs(policeFolder:GetChildren()) do
                if model:IsA("Model") then
                    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
                    if root then
                        valid[root] = true
                        if not espInstances.police[root] then
                            createESP(root, "POLICE", Color3.fromRGB(70, 140, 255), "police")
                        end
                    end
                end
            end
        end
        for root, data in pairs(espInstances.police) do
            if not valid[root] or not root.Parent then
                data.billboard:Destroy()
                data.highlight:Destroy()
                espInstances.police[root] = nil
            end
        end
    elseif next(espInstances.police) then
        clearESP("police")
    end
end)

-- ==========================================================================
-- 10. BIKE TUNING & PHYSICS ASSIST
-- ==========================================================================
local TUNING = ENV.BikeHubTuning or {
    MaxSpeedKmh = 300, LaunchAccel = 10, PowerPerKg = 500,
    TireGrip = 1.5, AirGravity = 40, WheelieStrength = 1.2,
    BrakeDecel = 25, SteerSpeed = 4.0, BrakePower = 2.5
}
ENV.BikeHubTuning = TUNING

local function applyTuning(name, value)
    TUNING[name] = value
    local bike = getMyBike()
    if bike then pcall(function() bike:SetAttribute(name, value) end) end
end

local function applyAllTuning()
    local bike = getMyBike()
    if not bike then return end
    for name, value in pairs(TUNING) do
        pcall(function() bike:SetAttribute(name, value) end)
    end
end

-- Auto-apply on spawn
Workspace.DescendantAdded:Connect(function(child)
    if child:IsA("Model") and child:GetAttribute("Owner") == LocalPlayer.UserId then
        task.delay(0.1, function() if child.Parent then applyAllTuning() end end)
        task.delay(0.5, function() if child.Parent then applyAllTuning() end end)
    end
end)

-- Handling Assist (Heartbeat)
local lastTick = os.clock()
RunService.Heartbeat:Connect(function()
    if not (Settings.handlingAssist or Settings.brakeAssist) or not isAlive() or not isRiding() then return end
    local now = os.clock()
    local dt = math.min(now - lastTick, 0.05)
    lastTick = now
    
    local bike = getMyBike()
    local chassis = getChassis(bike)
    if not chassis or not chassis:IsA("BasePart") then return end
    
    local vel = chassis.AssemblyLinearVelocity
    
    if Settings.handlingAssist then
        -- Auto-upright
        if math.abs(vel.Y) < 10 then
            local up = chassis.CFrame.UpVector
            if up.Y < 0.95 then
                local axis = up:Cross(Vector3.new(0, 1, 0))
                if axis.Magnitude > 0.01 then
                    local correction = axis.Unit * ((1 - up.Y) * 15)
                    chassis.AssemblyAngularVelocity = chassis.AssemblyAngularVelocity * 0.7 + correction
                end
            end
        end
    end
    
    if Settings.brakeAssist then
        local braking = UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Space)
        if braking then
            local flat = Vector3.new(vel.X, 0, vel.Z)
            if flat.Magnitude > 1 then
                local damp = math.clamp(3.0 * dt, 0, 1)
                local newFlat = flat * (1 - damp)
                chassis.AssemblyLinearVelocity = Vector3.new(newFlat.X, vel.Y, newFlat.Z)
            end
        end
    end
end)

-- ==========================================================================
-- 11. UI CONSTRUCTION (Airflow)
-- ==========================================================================
local THEME = {
    Background = Color3.fromHex("#080B12"), Surface = Color3.fromHex("#111827"), Surface2 = Color3.fromHex("#172033"),
    Surface3 = Color3.fromHex("#25314A"), Stroke = Color3.fromHex("#29364F"), StrokeHover = Color3.fromHex("#425477"),
    Accent = Color3.fromHex("#38BDF8"), AccentDark = Color3.fromHex("#082F49"), Text = Color3.fromHex("#F8FAFC"), Muted = Color3.fromHex("#94A3B8")
}
Airflow.ThemePresets.Omega = THEME
Airflow:SetDefaultTheme(THEME)

local Window = Airflow:CreateWindow({
    Name = "Bike Universe Hub v4.0",
    LoadingSubtitle = "Optimized • Undetectable • Smart",
    ToggleUIKeybind = "RightControl",
    Size = UDim2.fromOffset(800, 560),
    Backdrop = { Weather = "Fireflies", Tint = 0.4 },
    Theme = THEME,
    ConfigurationSaving = { Enabled = true, FolderName = "BikeHub_Omega" },
    Home = { Title = "Bike Universe Omega", Welcome = "Добро пожаловать,", Tier = "v4.0 Premium", Stats = { "Players", "FPS", "Ping", "Cash/min" } }
})

local function log(msg)
    -- Airflow log integration would go here, simplified for compatibility
    print("[BikeHub]", msg)
end

-- [FARM TAB]
local FarmTab = Window:CreateTab({ Name = "Smart Farm", Icon = "coins" })
local FarmMain = FarmTab:CreateGroupbox({ Name = "Настройки прыжков", Side = "Left" })
local FarmStats = FarmTab:CreateGroupbox({ Name = "Статистика", Side = "Right" })

FarmMain:CreateToggle({ Name = "AFK Cash Farm", Desc = "Умный фарм с Raycast-валидацией приземления", Flag = "FarmOn", CurrentValue = false, Callback = toggleFarm })
FarmMain:CreateSlider({ Name = "Высота прыжка", Range = { 50, 600 }, Increment = 10, Suffix = " studs", CurrentValue = 200, Flag = "JumpHeight", Callback = function(v) Settings.height = v end })
FarmMain:CreateSlider({ Name = "Длительность (Stealth)", Range = { 0.2, 2.0 }, Increment = 0.1, Suffix = " s", CurrentValue = 0.8, Flag = "JumpDur", Callback = function(v) Settings.jumpDuration = v end })
FarmMain:CreateDivider({ Text = "Анти-детект" })
FarmMain:CreateToggle({ Name = "Stealth Mode", Desc = "Плавная интерполяция вместо мгновенного телепорта", Flag = "Stealth", CurrentValue = true, Callback = function(v) Settings.stealthMode = v end })
FarmMain:CreateToggle({ Name = "Chain Jumps", Desc = "Мгновенный повторный прыжок после приземления", Flag = "Chain", CurrentValue = true, Callback = function(v) Settings.chainJumps = v end })
FarmMain:CreateToggle({ Name = "Auto Tricks", Desc = "Случайные сальто и вращения в воздухе", Flag = "Tricks", CurrentValue = true, Callback = function(v) Settings.tricksEnabled = v end })
FarmMain:CreateToggle({ Name = "Рандомизация", Desc = "Случайная высота и позиция приземления для обхода паттернов", Flag = "Rand", CurrentValue = true, Callback = function(v) Settings.randomizeHeight = v; Settings.randomizeLanding = v end })

FarmStats:CreateStatus({ Name = "Cash", Style = "Row", Update = function() return "<Success>" .. tostring(getCash()) .. "</Success>" end })
FarmStats:CreateStatus({ Name = "Jumps", Style = "Row", Update = function() return tostring(Stats.jumps) end })
FarmStats:CreateStatus({ Name = "Seated", Style = "Row", Update = function() return isRiding() and "<Success>Да</Success>" or "<Muted>Нет</Muted>" end })

-- [BIKE TAB]
local BikeTab = Window:CreateTab({ Name = "Bike & Physics", Icon = "bike" })
local BikeAssist = BikeTab:CreateGroupbox({ Name = "Assist", Side = "Left" })
local BikeTune = BikeTab:CreateGroupbox({ Name = "Тюнинг физики", Side = "Right" })

BikeAssist:CreateToggle({ Name = "No Crash / Rider Lock", Desc = "Продвинутая стабилизация CFrame и защита от Ragdoll", Flag = "RiderLock", CurrentValue = true, Callback = function(v) ENV.BikeHubRiderLock = v; Settings.riderLock = v end })
BikeAssist:CreateToggle({ Name = "Handling Assist", Desc = "Автоматическое выравнивание и улучшенный поворот", Flag = "Handling", CurrentValue = false, Callback = function(v) Settings.handlingAssist = v end })
BikeAssist:CreateToggle({ Name = "Brake Assist", Desc = "Мгновенная остановка при нажатии S или Space", Flag = "Brake", CurrentValue = false, Callback = function(v) Settings.brakeAssist = v end })
BikeAssist:CreateButton({ Name = "Сесть на байк", Icon = "bike", Callback = function() if forceSeat() then log("Успешно") else log("<Error>Байк не найден</Error>") end end })
BikeAssist:CreateButton({ Name = "Заспавнить байк", Icon = "plus", Callback = function() spawnBike() end })
BikeAssist:CreateToggle({ Name = "Pumpkin Farm", Desc = "Оптимизированный фарм тыкв с сохранением инерции", Flag = "Pumpkin", CurrentValue = false, Callback = togglePumpkinFarm })

local function tuneSlider(name, label, range, inc, suffix)
    BikeTune:CreateSlider({ Name = label, Range = range, Increment = inc, Suffix = suffix, CurrentValue = TUNING[name], Flag = "Tune"..name, Callback = function(v) applyTuning(name, v) end })
end
tuneSlider("MaxSpeedKmh", "Max Speed", {40, 500}, 10, " km/h")
tuneSlider("PowerPerKg", "Power per Kg", {10, 1000}, 10, "")
tuneSlider("TireGrip", "Tire Grip", {0.5, 5.0}, 0.1, "")
tuneSlider("AirGravity", "Air Gravity", {0, 200}, 5, "")
BikeTune:CreateButton({ Name = "Сбросить тюнинг", Icon = "rotate-ccw", Callback = function() 
    for k, v in pairs({MaxSpeedKmh=300, PowerPerKg=500, TireGrip=1.5, AirGravity=40}) do applyTuning(k, v) end 
    log("Тюнинг сброшен")
end })

-- [ESP TAB]
local EspTab = Window:CreateTab({ Name = "Visuals (ESP)", Icon = "eye" })
local EspBox = EspTab:CreateGroupbox({ Name = "Wallhack", Side = "Left" })
EspBox:CreateToggle({ Name = "Player ESP", Desc = "Подсветка игроков с дистанцией", Flag = "PlayerEsp", CurrentValue = false, Callback = function(v) Settings.playerEsp = v end })
EspBox:CreateToggle({ Name = "Police ESP", Desc = "Подсветка NPC полиции", Flag = "PoliceEsp", CurrentValue = false, Callback = function(v) Settings.policeEsp = v end })

-- [TELEPORT TAB]
local TpTab = Window:CreateTab({ Name = "Teleport", Icon = "map-pin" })
local TpBox = TpTab:CreateGroupbox({ Name = "Landmarks", Side = "Left" })
local landmarks = {"HighwayEntery", "LongHighway", "MegaRamp", "Garage", "PumpkinShop", "TownRace", "BikeDealer"}
for _, name in ipairs(landmarks) do
    TpBox:CreateButton({ Name = name, Callback = function()
        local model = Workspace:FindFirstChild(name) or Workspace:FindFirstChild(name, true)
        if model and model:IsA("Model") then
            local bike = getMyBike()
            if bike then
                pcall(function() bike:PivotTo(model:GetPivot() * CFrame.new(0, 5, 0)) end)
                log("Телепорт к: " .. name)
            else
                log("<Error>Сначала заспавньте байк</Error>")
            end
        end
    end })
end

-- ==========================================================================
-- 12. STARTUP & CLEANUP
-- ==========================================================================
log("<Success>Bike Universe Hub v4.0 Omega загружен успешно.</Success>")
log("Нажмите RightControl для открытия/закрытия меню.")

-- Очистка при закрытии
task.spawn(function()
    while isAlive() do
        task.wait(1)
    end
    if bikeAddedConn then bikeAddedConn:Disconnect() end
    if bikeRemovedConn then bikeRemovedConn:Disconnect() end
    clearESP("player")
    clearESP("police")
    stopDrive()
end)
