-- =============1. SERVICES
-- ==========================================================================
local Players              = game:GetService("Players")
local RunService           = game:GetService("RunService")
local VirtualInputManager  = game:GetService("VirtualInputManager")
local UserInputService     = game:GetService("UserInputService")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ==========================================================================
-- 2. ENV + generation (early — scriptAlive used in §8)
-- ==========================================================================
local function getEnv()
    if type(getgenv) == "function" then
        local ok, env = pcall(getgenv)
        if ok and type(env) == "table" then return env end
    end
    if type(shared) == "table" then return shared end
    return _G
end
local ENV = getEnv()

ENV.__BikeHubGen = (ENV.__BikeHubGen or 0) + 1
local SCRIPT_GENERATION = ENV.__BikeHubGen

local function scriptAlive()
    return ENV.__BikeHubGen == SCRIPT_GENERATION
end

local Ragdoll
pcall(function()
    Ragdoll = require(ReplicatedStorage:WaitForChild("Ragdoll", 5))
end)

local function short(value)
    if type(value) ~= "number" then return "-" end
    local text = tostring(math.floor(value))
    return (text:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^%s+", ""))
end

-- ==========================================================================
-- 3. AirFlow loading
-- ==========================================================================
local EMBED_LIBRARY = nil

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

local Airflow = (EMBED_LIBRARY and tryLoadLibrary(EMBED_LIBRARY))
    or readCache()
    or fetchFirst()

if not Airflow then
    error("[Bike Universe Hub] AirFlow UI could not be loaded")
end

-- ==========================================================================
-- 4. Bike helpers (cached)
-- ==========================================================================
local bikeCache = nil
local bikeCacheLastScan = 0
local BIKE_SCAN_INTERVAL = 0.2

workspace.DescendantAdded:Connect(function(child)
    if not scriptAlive() then return end
    if child:IsA("Model") and child:GetAttribute("Owner") == LocalPlayer.UserId then
        bikeCache = child
        bikeCacheLastScan = 0
    end
end)

local function scanForBike()
    local found
    local function scan(inst, depth)
        if found or depth > 4 then return end
        for _, child in ipairs(inst:GetChildren()) do
            if child:IsA("Model") and child:GetAttribute("Owner") == LocalPlayer.UserId then
                found = child; return
            end
            if child:IsA("Folder") or child:IsA("Model") then
                scan(child, depth + 1)
            end
        end
    end
    scan(workspace, 0)
    return found
end

local function myBike()
    if bikeCache and bikeCache.Parent then
        if bikeCache:GetAttribute("Owner") == LocalPlayer.UserId then
            return bikeCache
        end
        bikeCache = nil
    end
    local now = os.clock()
    if (now - bikeCacheLastScan) < BIKE_SCAN_INTERVAL then
        return nil
    end
    bikeCacheLastScan = now
    local found = scanForBike()
    bikeCache = found
    return found
end

local function chassis()
    local bike = myBike()
    if not bike then return nil end
    local c = bike:FindFirstChild("Chassis")
    if c then
        if c:IsA("BasePart") then return c end
        if c:IsA("Model") and c.PrimaryPart then return c.PrimaryPart end
    end
    return bike.PrimaryPart
end

local function driverSeat()
    local bike = myBike()
    if not bike then return nil end
    return bike:FindFirstChild("DriverSeat", true) or bike:FindFirstChildOfClass("VehicleSeat")
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

-- ==========================================================================
-- 5. Drive control
-- ==========================================================================
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
                and (os.clock() - (state.last or 0) < 0.5) then
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

local function applyDrive(throttle, steer)
    throttle = throttle or 0
    steer = steer or 0
    local seat = driverSeat()
    if seat and seat:IsA("VehicleSeat") then
        pcall(function()
            seat.ThrottleFloat = throttle
            seat.SteerFloat = steer
        end)
    end
    drive(throttle, steer)
end

local function applyDriveStop()
    local seat = driverSeat()
    if seat and seat:IsA("VehicleSeat") then
        pcall(function()
            seat.ThrottleFloat = 0
            seat.SteerFloat = 0
        end)
    end
    driveStop()
end

-- ==========================================================================
-- 6. Key mirroring
-- ==========================================================================
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

-- ==========================================================================
-- 7. Seating / bike spawn
-- ==========================================================================
local log
local riderLockSet
local spawnBike
local pumpkinList
local teleportBike

spawnBike = function()
    if myBike() then return true end
    local remotes = {}
    for _, name in ipairs({
        "SpawnBikeEvent", "SelectBike", "BikeMount", "SpawnBike",
        "RequestBike", "EquipBike", "GetBike", "MountBike"
    }) do
        local r = ReplicatedStorage:FindFirstChild(name)
        if r and r:IsA("RemoteEvent") then table.insert(remotes, r) end
    end
    for _, child in ipairs(ReplicatedStorage:GetChildren()) do
        if child:IsA("RemoteEvent") and not table.find(remotes, child) then
            local n = child.Name:lower()
            if n:find("bike") or n:find("spawn") then
                table.insert(remotes, child)
            end
        end
    end
    for _, remote in ipairs(remotes) do
        bikeCache = nil
        bikeCacheLastScan = 0
        pcall(function() remote:FireServer() end)
        for _ = 1, 10 do
            task.wait(0.2)
            if myBike() then return true end
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

-- ==========================================================================
-- 8. Never-crash + rider lock tick
-- ==========================================================================
if Ragdoll and type(Ragdoll.fling) == "function" and not ENV.__BikeHubFlingHooked then
    ENV.__BikeHubFlingHooked = true
    local originalFling = Ragdoll.fling
    Ragdoll.fling = function(...)
        if ENV.__BikeFarmOn or ENV.__BikeHubRiderLock then return end
        return originalFling(...)
    end
end

if Ragdoll and type(Ragdoll.start) == "function" and not ENV.__BikeHubStartHooked then
    ENV.__BikeHubStartHooked = true
    local originalStart = Ragdoll.start
    Ragdoll.start = function(...)
        if ENV.__BikeFarmOn or ENV.__BikeHubRiderLock then return end
        return originalStart(...)
    end
end

local function riderLockTick()
    local seat, hum = driverSeat(), humanoid()
    if not (seat and hum) then return end
    if ENV.__BikeHubRiderLock then
        if seat.Occupant ~= hum then
            local char = LocalPlayer.Character
            if char then
                pcall(function() char:PivotTo(seat.CFrame * CFrame.new(0, 1.5, 0)) end)
            end
            pcall(function() seat:Sit(hum) end)
        end
    end
    if hum.PlatformStand then hum.PlatformStand = false end
    local state = hum:GetState()
    if state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.FallingDown then
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
    if ENV.__BikeHubRiderLock then
        local part = chassis()
        if part and part:IsA("BasePart") then
            local av = part.AssemblyAngularVelocity
            if av.Magnitude > 30 then
                part.AssemblyAngularVelocity = av * 0.3
            end
        end
    end
end

task.spawn(function()
    while scriptAlive() do
        if ENV.__BikeHubRiderLock then
            pcall(riderLockTick)
        end
        task.wait(0.05)
    end
end)

-- ==========================================================================
-- 9. Settings / stats
-- ==========================================================================
local Settings = {
    farmOn = false,
    height = 140,
    cooldown = 0.6,
    wheelieOn = false, riderLock = false,
    handlingAssist = false, brakeAssist = false,
    pumpkinFarm = false, playerEsp = false, policeEsp = false,
    -- farm v2.4
    stealthMode = true,
    chainJumps = true,
    tricksEnabled = false,
    randomizeHeight = true,
    randomizeLanding = true,
    jumpDuration = 1.2,
    safeSpeed = false,
}

local Stats = {
    jumps = 0, lastCash = 0, lastSample = 0, perMinute = 0,
}

local Window
local UiRefs = {}

-- ==========================================================================
-- 10. TELEPORT FARM — v2.4 (stealth + chain + tricks)
-- ==========================================================================
local function smoothTeleport(bike, fromCF, toCF, duration)
    if duration <= 0 then
        pcall(function() bike:PivotTo(toCF) end)
        return
    end
    local startTime = os.clock()
    while scriptAlive() and Settings.farmOn do
        local t = (os.clock() - startTime) / duration
        if t >= 1 then break end
        local eased = t * t * (3 - 2 * t)
        local cf = fromCF:Lerp(toCF, eased)
        pcall(function() bike:PivotTo(cf) end)
        task.wait(0.03)
    end
    if scriptAlive() and Settings.farmOn then
        pcall(function() bike:PivotTo(toCF) end)
    end
end

local function applyTrick(part, kind)
    if not part or not part:IsA("BasePart") then return end
    local power = 15
    local trick
    if kind == "spin" then
        trick = Vector3.new(0, power, 0)
    elseif kind == "frontflip" then
        trick = part.CFrame.RightVector * power
    elseif kind == "backflip" then
        trick = part.CFrame.RightVector * -power
    elseif kind == "barrel" then
        trick = part.CFrame.LookVector * power
    end
    if trick then
        pcall(function()
            part.AssemblyAngularVelocity = part.AssemblyAngularVelocity + trick
        end)
    end
end

local function jumpOnce()
    local bike, part = myBike(), chassis()
    if not (bike and part) or not part:IsA("BasePart") then
        spawnBike()
        task.wait(0.4)
        return false
    end
    if not isRiding() and not seatUp() then return false end

    local groundPos = part.Position
    local rotation = part.CFrame - part.CFrame.Position

    local height = Settings.height
    if Settings.randomizeHeight then
        height = height * (0.85 + math.random() * 0.30)
    end

    local horizOff = Settings.randomizeLanding
        and Vector3.new(math.random(-8, 8), 0, math.random(-8, 8))
        or Vector3.zero

    local apexPos = groundPos + Vector3.new(0, height, 0) + horizOff

    applyDrive(1, 0)

    local startCF = CFrame.new(groundPos) * rotation
    local endCF   = CFrame.new(apexPos)   * rotation

    if Settings.stealthMode then
        smoothTeleport(bike, startCF, endCF, Settings.jumpDuration)
    else
        pcall(function() bike:PivotTo(endCF) end)
    end

    if Settings.tricksEnabled then
        local cur = chassis()
        if cur and cur:IsA("BasePart") then
            local trick = ({ "spin", "frontflip", "backflip", "barrel" })[math.random(1, 4)]
            applyTrick(cur, trick)
        end
    end

    -- Wait for landing
    local startTime = os.clock()
    local lastDrive = 0
    local tookOff = false

    while scriptAlive() and Settings.farmOn do
        if os.clock() - startTime > 25 then break end
        if not isRiding() then
            task.wait(0.3)
            seatUp()
            task.wait(0.3)
            break
        end
        if os.clock() - lastDrive > 0.15 then
            applyDrive(1, 0)
            lastDrive = os.clock()
        end
        local cur = chassis()
        if cur and cur:IsA("BasePart") then
            local vel = cur.AssemblyLinearVelocity
            local pos = cur.Position
            local dy = pos.Y - groundPos.Y

            if not tookOff and dy > 20 then
                tookOff = true
            end

            if tookOff and math.abs(vel.Y) < 8 and dy < 20 then
                break -- landed
            end
            if dy < -50 then break end -- fell through
        end
        task.wait(0.05)
    end

    applyDriveStop()
    Stats.jumps += 1

    if Settings.chainJumps then
        task.wait(0.15)
    else
        task.wait(Settings.cooldown)
    end

    return true
end

local function farmSet(on)
    Settings.farmOn = on
    ENV.__BikeFarmOn = on
    if not on then
        applyDriveStop()
        releaseKeys()
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
        task.wait(0.3)
        Stats.jumps = 0
        Stats.lastCash = cash()
        Stats.lastSample = os.clock()
        log(string.format("Farm on — height %d, stealth=%s, chain=%s",
            Settings.height, tostring(Settings.stealthMode), tostring(Settings.chainJumps)))
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

-- ==========================================================================
-- 11. Forest trees remover
-- ==========================================================================
local forestWatchConn = nil

local function findForestFolder()
    return workspace:FindFirstChild("ForestTrees")
        or workspace:FindFirstChild("ForestTrees", true)
end

local function purgeForestFolder(folder)
    if not folder or not folder.Parent then return 0 end
    local count = 0
    for _, child in ipairs(folder:GetChildren()) do
        if pcall(function() child:Destroy() end) then
            count += 1
        end
    end
    pcall(function() folder:Destroy() end)
    return count
end

local function forestAutoRemove(on)
    if on then
        local folder = findForestFolder()
        if folder then
            local n = purgeForestFolder(folder)
            log(string.format("<Success>Removed ForestTrees: %d object(s) + folder</Success>", n))
        else
            log("ForestTrees not found (nothing to remove — still watching)")
        end
        if forestWatchConn then forestWatchConn:Disconnect() end
        forestWatchConn = workspace.ChildAdded:Connect(function(child)
            if not scriptAlive() then return end
            if child.Name ~= "ForestTrees" then return end
            task.defer(function()
                task.wait(0.05)
                if child and child.Parent then
                    local n = purgeForestFolder(child)
                    log(string.format("<Success>ForestTrees respawned — removed again (%d objects)</Success>", n))
                end
            end)
        end)
        log("ForestTrees watch active")
    else
        if forestWatchConn then
            forestWatchConn:Disconnect()
            forestWatchConn = nil
            log("ForestTrees watch stopped")
        end
    end
end

-- ==========================================================================
-- 12. WHEELIE
-- ==========================================================================
local wheelieAnchor
local function captureAnchor()
    local part = chassis()
    wheelieAnchor = part and part.Position or nil
end
local function holdAnchor()
    local bike, part = myBike(), chassis()
    if not (bike and part) then return end
    if not wheelieAnchor then wheelieAnchor = part.Position end
    local rotation = part.CFrame - part.CFrame.Position
    pcall(function() bike:PivotTo(CFrame.new(wheelieAnchor) * rotation) end)
    part.AssemblyLinearVelocity = Vector3.zero
    part.AssemblyAngularVelocity = Vector3.zero
end

local function wheelieCycle(throttle)
    key(Enum.KeyCode.LeftControl, false)
    task.wait(0.05)
    key(Enum.KeyCode.LeftControl, true)
    applyDrive(throttle or 1, 0)
    task.wait(0.45)
    applyDrive(0.2, 0)
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
            applyDriveStop()
            releaseKeys()
        end)
    else
        applyDriveStop()
        releaseKeys()
        log("Auto wheelie off")
    end
    if UiRefs.wheelie then UiRefs.wheelie:Set(on, true) end
end

-- ==========================================================================
-- 13. RIDER LOCK
-- ==========================================================================
riderLockSet = function(on)
    Settings.riderLock = on
    ENV.__BikeHubRiderLock = on
    log(on and "Rider lock on" or "Rider lock off")
    if UiRefs.riderLock then UiRefs.riderLock:Set(on, true) end
end

-- ==========================================================================
-- 14. PUMPKIN FARM
-- ==========================================================================
local pumpkinCache = nil
local pumpkinCacheTime = 0
local PUMPKIN_CACHE_TTL = 3

pumpkinList = function()
    local list = {}
    local seen = {}
    local function add(p)
        if p and not seen[p] then
            seen[p] = true
            table.insert(list, p)
        end
    end
    local function isPumpkinModel(child)
        if not child:IsA("Model") then return false end
        local n = child.Name:lower()
        local flagged = n:find("pumpkin")
            or child:GetAttribute("Pumpkin")
            or child:GetAttribute("IsPumpkin")
        if not flagged then return false end
        return child.PrimaryPart ~= nil
            or child:FindFirstChild("Body") ~= nil
            or child:FindFirstChild("Hitbox") ~= nil
    end
    for _, name in ipairs({"MyPumpkins", "Pumpkins", "PumpkinFolder", "Farm"}) do
        local folder = workspace:FindFirstChild(name)
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                if isPumpkinModel(child) then add(child) end
            end
        end
    end
    if #list > 0 then
        pumpkinCache = list
        pumpkinCacheTime = os.clock()
        return list
    end
    local now = os.clock()
    if pumpkinCache and (now - pumpkinCacheTime) < PUMPKIN_CACHE_TTL then
        local valid = true
        for _, p in ipairs(pumpkinCache) do
            if not p.Parent then valid = false; break end
        end
        if valid then return pumpkinCache end
    end
    local function scan(inst, depth)
        if depth > 4 then return end
        for _, child in ipairs(inst:GetChildren()) do
            if isPumpkinModel(child) then add(child) end
            if not child:IsA("Model") or child:IsA("Folder") then
                scan(child, depth + 1)
            end
        end
    end
    scan(workspace, 0)
    pumpkinCache = list
    pumpkinCacheTime = now
    return list
end

local function pumpkinSet(on)
    Settings.pumpkinFarm = on
    ENV.__BikeHubPumpkin = on
    if on then
        task.spawn(function()
            log("<Warning>Pumpkin farm on (experimental)</Warning>")
            while Settings.pumpkinFarm and scriptAlive() do
                local bike = myBike()
                if not bike then
                    spawnBike(); task.wait(1)
                elseif not isRiding() then
                    seatUp(); task.wait(0.3)
                else
                    local list = pumpkinList()
                    if #list > 0 then
                        local bikePos = bike:GetPivot().Position
                        local nearest, best
                        for _, pumpkin in ipairs(list) do
                            if pumpkin.Parent then
                                local d = (pumpkin:GetPivot().Position - bikePos).Magnitude
                                if not best or d < best then
                                    nearest, best = pumpkin, d
                                end
                            end
                        end
                        if nearest then
                            local target = nearest:GetPivot()
                            local body = nearest:FindFirstChild("Body")
                                or nearest:FindFirstChild("Hitbox")
                                or nearest.PrimaryPart
                            if body and body:IsA("BasePart") then
                                target = CFrame.new(body.Position)
                            end
                            applyDrive(1, 0)
                            teleportBike(target * CFrame.new(0, 4, 0))
                            task.wait(0.35)
                            applyDrive(1, 0)
                            task.wait(0.35)
                        end
                    else
                        task.wait(1)
                    end
                end
                task.wait(0.1)
            end
            applyDriveStop()
        end)
    else
        log("Pumpkin farm off")
    end
    if UiRefs.pumpkin then UiRefs.pumpkin:Set(on, true) end
end

-- ==========================================================================
-- 15. ESP
-- ==========================================================================
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

task.spawn(function()
    for _, child in ipairs(PlayerGui:GetChildren()) do
        if child.Name == "BikeHubEsp" or child.Name == "BikeHubHighlight" then
            child:Destroy()
        end
    end
end)

local function refreshPlayerEsp()
    local alive = {}
    local me = bikePosition()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local torso = player.Character:FindFirstChild("HumanoidRootPart")
                or player.Character:FindFirstChild("Torso")
            if torso then
                alive[torso] = true
                if not esp.player[torso] then
                    esp.player[torso] = makeEsp(torso, player.Name, Color3.fromRGB(255, 59, 127))
                end
                local dist = me and math.floor((torso.Position - me).Magnitude) or 0
                esp.player[torso].label.Text = string.format("%s  [%d]", player.Name, dist)
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

-- ==========================================================================
-- 16. BIKE TUNING
-- ==========================================================================
local TUNING_LIMITS = {
    MaxSpeedKmh = { min = 40, max = 300 },
    LaunchAccel = { min = 1, max = 30 },
    PowerPerKg = { min = 10, max = 500 },
    TireGrip = { min = 0.2, max = 3 },
    AirGravity = { min = 0, max = 120 },
    WheelieStrength = { min = 0.2, max = 4 },
    BrakeDecel = { min = 1, max = 50 },
    SteerSpeed = { min = 0.5, max = 10 },
    BrakePower = { min = 0.5, max = 10 },
}

local TUNING_DEFAULTS = {
    MaxSpeedKmh = 300, LaunchAccel = 8, PowerPerKg = 500,
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
for name, limits in pairs(TUNING_LIMITS) do
    local current = TUNING_VALUES[name]
    if type(current) ~= "number" then
        TUNING_VALUES[name] = TUNING_DEFAULTS[name]
    else
        TUNING_VALUES[name] = math.clamp(current, limits.min, limits.max)
    end
end

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
    local limits = TUNING_LIMITS[name]
    if not limits or type(value) ~= "number" or value ~= value then return end
    value = math.clamp(value, limits.min, limits.max)
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
    log("Bike tuning reset to defaults")
end

local function watchContainer(container)
    container.ChildAdded:Connect(function(child)
        if not scriptAlive() then return end
        if child:IsA("Model") and child:GetAttribute("Owner") == LocalPlayer.UserId then
            task.spawn(function()
                for _, delayTime in ipairs({ 0, 0.15, 0.5, 1, 2 }) do
                    if delayTime > 0 then task.wait(delayTime) end
                    if scriptAlive() and child.Parent then
                        applyAllTuning(child)
                    end
                end
                log("Saved bike tuning applied to spawned bike")
            end)
        elseif child:IsA("Folder") or child:IsA("Model") then
            watchContainer(child)
        end
    end)
end

watchContainer(workspace)
for _, child in ipairs(workspace:GetChildren()) do
    if child:IsA("Folder") or child:IsA("Model") then
        if child:FindFirstChildOfClass("Model") then
            watchContainer(child)
        end
    end
end

task.spawn(function()
    for _ = 1, 30 do
        if not scriptAlive() then return end
        local bike = myBike()
        if bike then applyAllTuning(bike); return end
        task.wait(0.25)
    end
end)

-- ==========================================================================
-- 17. HANDLING / BRAKE ASSIST
-- ==========================================================================
local lastHandlingTick = os.clock()

local function handlingTick()
    local now = os.clock()
    local dt = math.min(now - lastHandlingTick, 0.05)
    lastHandlingTick = now
    if dt <= 0 then return end
    if not (Settings.handlingAssist or Settings.brakeAssist) then return end
    if not isRiding() then return end
    local bike = myBike()
    if not bike then return end
    local part = chassis()
    if not part or not part:IsA("BasePart") then
        part = bike.PrimaryPart
        if not part then return end
    end
    local vel = part.AssemblyLinearVelocity
    if Settings.handlingAssist then
        if math.abs(vel.Y) < 12 then
            local up = part.CFrame.UpVector
            if up.Y < 0.92 then
                local axis = up:Cross(Vector3.new(0, 1, 0))
                if axis.Magnitude > 0.01 then
                    local errorAmt = 1 - up.Y
                    local correction = axis.Unit * (errorAmt * 12)
                    part.AssemblyAngularVelocity = part.AssemblyAngularVelocity * 0.6 + correction
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
                local push = right * steerInput * flat.Magnitude * dt * 0.8
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
                local damp = math.clamp(2.0 * dt, 0, 1)
                local newFlat = flat * (1 - damp)
                part.AssemblyLinearVelocity = Vector3.new(newFlat.X, vel.Y, newFlat.Z)
            end
        end
    end
end

RunService.Heartbeat:Connect(function()
    if Settings.handlingAssist or Settings.brakeAssist then
        pcall(handlingTick)
    end
end)

-- ==========================================================================
-- 18. TELEPORTS
-- ==========================================================================
local LANDMARKS = {
    "HighwayEntery", "LongHighway", "HighwayRace", "HighwayTunnels",
    "MegaRamp", "Garage", "PumpkinSHop", "PumpkinBikeStand",
    "TownRace", "BikeDealer", "LuxuryStand", "VargShowcase",
}

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
    pcall(function() bike:PivotTo(cframe) end)
    if char and not seated then
        pcall(function() char:PivotTo(cframe * CFrame.new(0, 2.2, 0)) end)
    end
    for _ = 1, 8 do
        task.wait(0.06)
        local bp = chassis()
        if bp and bp:IsA("BasePart") then
            if (bp.Position - cframe.Position).Magnitude > 20 then
                pcall(function() bike:PivotTo(cframe) end)
                if char and not seated then
                    pcall(function() char:PivotTo(cframe * CFrame.new(0, 2.2, 0)) end)
                end
            end
        end
    end
    if not isRiding() then seatUp() end
    return true
end

local function landmarkCFrame(name)
    local model = workspace:FindFirstChild(name) or workspace:FindFirstChild(name, true)
    if model and model:IsA("Model") then
        return model:GetPivot() * CFrame.new(0, 4, 0)
    end
    return nil
end

-- ==========================================================================
-- 19. WINDOW
-- ==========================================================================
local THEME = {
    Background = Color3.fromHex("#080B12"),
    Surface    = Color3.fromHex("#111827"),
    Surface2   = Color3.fromHex("#172033"),
    Surface3   = Color3.fromHex("#25314A"),
    Stroke     = Color3.fromHex("#29364F"),
    StrokeHover= Color3.fromHex("#425477"),
    Accent     = Color3.fromHex("#38BDF8"),
    AccentDark = Color3.fromHex("#082F49"),
    Text       = Color3.fromHex("#F8FAFC"),
    Muted      = Color3.fromHex("#94A3B8"),
}

Airflow.ThemePresets.Robscript = THEME
Airflow:SetDefaultTheme(THEME)

Window = Airflow:CreateWindow({
    Name = "Bike Universe Hub",
    LoadingSubtitle = "Bike tuning • handling • controls",
    ToggleUIKeybind = "RightControl",
    Size = UDim2.fromOffset(780, 540),
    Backdrop = { Weather = "Fireflies", Tint = 0.35 },
    Theme = THEME,
    ConfigurationSaving = { Enabled = true, FolderName = "BikeUniverseHub" },
    Home = {
        Title = "Bike Universe Hub",
        Welcome = "Welcome back,",
        Tier = "v3.0",
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

-- ==========================================================================
-- 20. FARM TAB
-- ==========================================================================
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
    Desc = "Only used when chain jumps are off",
    Range = { 0.2, 3 }, Increment = 0.1, Suffix = " s",
    CurrentValue = 0.6, Flag = "JumpCooldown",
    Callback = function(value) Settings.cooldown = value end,
})

FarmMain:CreateDivider({ Text = "anti-detection" })

UiRefs.stealth = FarmMain:CreateToggle({
    Name = "Stealth mode (smooth jumps)",
    Desc = "Interpolates position smoothly - much less likely to trip position-based AC",
    Flag = "StealthMode", CurrentValue = true,
    Callback = function(on)
        Settings.stealthMode = on
        log(on and "Stealth jumps on" or "Stealth jumps off (instant teleport)")
    end,
})

UiRefs.chain = FarmMain:CreateToggle({
    Name = "Chain jumps",
    Desc = "Re-jumps immediately on landing - skips the long cooldown",
    Flag = "ChainJumps", CurrentValue = true,
    Callback = function(on)
        Settings.chainJumps = on
        log(on and "Chain jumps on (max speed)" or "Chain jumps off")
    end,
})

UiRefs.tricks = FarmMain:CreateToggle({
    Name = "Auto tricks",
    Desc = "Random spins/flips while airborne - bonuses if game pays for tricks",
    Flag = "TricksEnabled", CurrentValue = false,
    Callback = function(on)
        Settings.tricksEnabled = on
        log(on and "Auto tricks on" or "Auto tricks off")
    end,
})

UiRefs.randH = FarmMain:CreateToggle({
    Name = "Randomize height",
    Desc = "Varies jump height ±15% to defeat pattern detection",
    Flag = "RandHeight", CurrentValue = true,
    Callback = function(on) Settings.randomizeHeight = on end,
})

UiRefs.randL = FarmMain:CreateToggle({
    Name = "Randomize landing",
    Desc = "Varies landing position ±8 studs to look natural",
    Flag = "RandLanding", CurrentValue = true,
    Callback = function(on) Settings.randomizeLanding = on end,
})

FarmMain:CreateSlider({
    Name = "Jump duration",
    Desc = "Time to reach apex in stealth mode (higher = smoother)",
    Range = { 0.4, 3 }, Increment = 0.1, Suffix = " s",
    CurrentValue = 1.2, Flag = "JumpDuration",
    Callback = function(value) Settings.jumpDuration = value end,
})

FarmMain:CreateDivider({ Text = "world" })

UiRefs.forestTrees = FarmMain:CreateToggle({
    Name = "Keep ForestTrees removed",
    Desc = "Deletes Workspace.ForestTrees (+ everything inside) and re-removes on respawn",
    Flag = "ForestRemove", CurrentValue = false,
    Callback = function(on) forestAutoRemove(on) end,
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
    Title = "Why it earns more now",
    Content = "Chain jumps remove the 3s cooldown between cycles. Auto tricks multiply bonus if the game pays for them. "
        .. "Randomized height and landing avoid pattern detection, so the loop runs longer without a kick. "
        .. "Stealth mode interpolates movement so position jumps don't look like teleports.",
})

-- ==========================================================================
-- 21. BIKE TAB
-- ==========================================================================
local BikeTab  = Window:CreateTab({ Name = "Bike", Icon = "bike" })
local BikeMain = BikeTab:CreateGroupbox({ Name = "Assist", Side = "Left" })
local BikeTune = BikeTab:CreateGroupbox({ Name = "Movement", Side = "Right" })

UiRefs.wheelie = BikeMain:CreateToggle({
    Name = "Auto wheelie", Desc = "Holds a wheelie and keeps you on the bike",
    Flag = "Wheelie", CurrentValue = false,
    Callback = function(on) wheelieSet(on) end,
})

UiRefs.riderLock = BikeMain:CreateToggle({
    Name = "No crash / no ragdoll",
    Desc = "Blocks crash/ragdoll and auto-recovers if thrown off",
    Flag = "RiderLock", CurrentValue = false,
    Callback = function(on) riderLockSet(on) end,
})

UiRefs.handling = BikeMain:CreateToggle({
    Name = "Handling assist",
    Desc = "Auto-upright + sharper steering while riding",
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

UiRefs.safeSpeed = BikeMain:CreateToggle({
    Name = "Safe speed cap",
    Desc = "Caps PowerPerKg→150 and MaxSpeedKmh→200 to avoid speed-based AC",
    Flag = "SafeSpeed", CurrentValue = false,
    Callback = function(on)
        Settings.safeSpeed = on
        if on then
            Settings._savedPower = TUNING_VALUES.PowerPerKg
            Settings._savedMaxSpeed = TUNING_VALUES.MaxSpeedKmh
            applyTuning("PowerPerKg", math.min(TUNING_VALUES.PowerPerKg, 150))
            applyTuning("MaxSpeedKmh", math.min(TUNING_VALUES.MaxSpeedKmh, 200))
            log("<Success>Safe speed cap on (150 power, 200 km/h)</Success>")
        else
            if Settings._savedPower then applyTuning("PowerPerKg", Settings._savedPower) end
            if Settings._savedMaxSpeed then applyTuning("MaxSpeedKmh", Settings._savedMaxSpeed) end
            log("Safe speed cap off")
        end
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

tuningSlider("MaxSpeedKmh",     "Max speed",        {40, 300},  5,    " km/h", "TuneSpeed")
tuningSlider("LaunchAccel",     "Acceleration",     {1, 30},    0.5,  nil,     "TuneAccel")
tuningSlider("PowerPerKg",      "Power per kg",     {10, 500},  5,    nil,     "TunePower")
tuningSlider("TireGrip",        "Tire grip",        {0.2, 3},   0.05, nil,     "TuneGrip")
tuningSlider("AirGravity",      "Air gravity",      {0, 120},   5,    nil,     "TuneAirGravity")
tuningSlider("WheelieStrength", "Wheelie strength", {0.2, 4},   0.1,  nil,     "TuneWheelie")
tuningSlider("BrakeDecel",      "Brake decel",      {1, 50},    1,    nil,     "TuneBrake")
tuningSlider("SteerSpeed",      "Steer speed",      {0.5, 10},  0.5,  nil,     "TuneSteer")
tuningSlider("BrakePower",      "Brake power",      {0.5, 10},  0.5,  nil,     "TuneBrakePower")

BikeTune:CreateButton({
    Name = "Reset tuning", Icon = "rotate-ccw",
    Callback = function() resetTuning() end,
})

-- ==========================================================================
-- 22. ESP TAB
-- ==========================================================================
local EspTab = Window:CreateTab({ Name = "ESP", Icon = "eye" })
local EspBox = EspTab:CreateGroupbox({ Name = "Wallhack", Side = "Left" })
EspBox:CreateToggle({
    Name = "Player ESP", Desc = "Highlight players with distance labels",
    Flag = "PlayerEsp", CurrentValue = false,
    Callback = function(on)
        Settings.playerEsp = on
        log(on and "Player ESP on" or "Player ESP off")
    end,
})
EspBox:CreateToggle({
    Name = "Police ESP", Desc = "Highlight police NPCs",
    Flag = "PoliceEsp", CurrentValue = false,
    Callback = function(on)
        Settings.policeEsp = on
        log(on and "Police ESP on" or "Police ESP off")
    end,
})

-- ==========================================================================
-- 23. TELEPORT TAB
-- ==========================================================================
local TpTab = Window:CreateTab({ Name = "Teleport", Icon = "map-pin" })
local TpBox = TpTab:CreateGroupbox({ Name = "Landmarks", Side = "Left" })

for _, name in ipairs(LANDMARKS) do
    TpBox:CreateButton({
        Name = name,
        Callback = function()
            local cf = landmarkCFrame(name)
            if cf then
                teleportBike(cf)
                log("Teleported to " .. name)
            else
                log("<Warning>Landmark not found: " .. name .. "</Warning>")
            end
        end,
    })
end

-- ==========================================================================
-- 24. Startup
-- ==========================================================================
log("Bike Universe Hub v3.0 loaded.")
log("Tuning UI ready: max speed 300 km/h, power per kg 500")
log("Press RightControl to toggle the UI.")
