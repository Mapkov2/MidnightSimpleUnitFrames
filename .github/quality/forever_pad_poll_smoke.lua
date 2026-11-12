-- Smoke test for the Forever pad poll in Game/Forever/PadNavigation.lua. The
-- 4 Hz ticker runs only while the Gamepad UI is on or still has something to
-- release; INPUT_DEVICE_INTERFACE_TRANSITION starts it again.
-- Run: lua forever_pad_poll_smoke.lua <workspace root>
-- Recorded 2026-11-11: polls per second while the Gamepad UI is off, before 4 -> after 0
-- (POLL_INTERVAL 0.25 s; the old unconditional ticker fired 1000 times in 1000 simulated
-- intervals, the stopped ticker fires 0 times).

local root = assert(arg[1], "repository root required")
local path = root .. "/MidnightSimpleUnitFrames/Game/Forever/PadNavigation.lua"
local chunk = assert(loadfile(path))

local function newFrame(world, kind)
    local frame = { kind = kind, events = {}, scripts = {} }
    function frame:RegisterEvent(name) self.events[name] = true end
    function frame:UnregisterEvent(name) self.events[name] = nil end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    world.frames[#world.frames + 1] = frame
    return frame
end

-- Fresh stubs for one load of the file. Each world owns its tickers, frames and
-- counters; the globals it installs are replaced by the next world.
local function newWorld(options)
    local world = {
        tickers = {}, frames = {}, exported = {},
        updates = 0, polls = 0, combat = false,
        gamepadUI = options.gamepadUI == true,
    }
    _G.CreateFrame = function(kind) return newFrame(world, kind) end
    _G.C_Timer = {
        NewTicker = function(interval, callback)
            assert(type(callback) == "function", "NewTicker needs a callback")
            local ticker = { interval = interval, callback = callback, cancelled = false, fires = 0 }
            function ticker:Cancel() self.cancelled = true end
            world.tickers[#world.tickers + 1] = ticker
            return ticker
        end,
        After = function() end,
    }
    _G.InCombatLockdown = function() return world.combat end
    _G.InputUtil = { IsGamepadUIEnabled = function() return world.gamepadUI end }
    _G.GetCVarBool = nil
    world.ns = {
        Client = { IsForever = options.forever ~= false },
        -- PadNavigation only needs PixelLayoutRegion(frame) to return the frame.
        Require = function(name)
            assert(name == "MSUF_PixelLayoutRegion", "unexpected Require: " .. tostring(name))
            return function(frame) return frame end
        end,
        ExportPublic = function(name, value) world.exported[name] = value end,
        UnitMenus = { UpdateGamepad = function() world.updates = world.updates + 1 end },
    }
    return world
end

-- One simulated callback of a ticker, as the client would deliver it.
local function fire(world, ticker)
    ticker.fires = ticker.fires + 1
    world.polls = world.polls + 1
    ticker.callback(ticker)
end

local function fireLive(world)
    local count = #world.tickers
    for index = 1, count do
        local ticker = world.tickers[index]
        if not ticker.cancelled then fire(world, ticker) end
    end
end

local function liveCount(world)
    local live = 0
    for index = 1, #world.tickers do
        if not world.tickers[index].cancelled then live = live + 1 end
    end
    return live
end

local function sendEvent(world, name)
    local frame = world.frames[1]
    frame.scripts.OnEvent(frame, name)
end

local function load(options)
    local world = newWorld(options)
    chunk("MidnightSimpleUnitFrames", world.ns)
    assert(#world.frames == 1, "exactly one frame (the event frame) must be created at load")
    local eventFrame = world.frames[1]
    assert(eventFrame.scripts.OnEvent, "the event frame needs an OnEvent script")
    world.eventFrame = eventFrame
    return world
end

-- a. Other clients return early: no frame, no ticker, no exported module.
do
    local world = newWorld({ forever = false })
    chunk("MidnightSimpleUnitFrames", world.ns)
    assert(#world.frames == 0, "a. non-Forever client must create no event frame")
    assert(#world.tickers == 0, "a. non-Forever client must start no ticker")
    assert(world.exported.MSUF_PadNavigation == nil and world.ns.PadNavigation == nil,
        "a. non-Forever client must export no PadNavigation module")
    print("a ok: non-Forever client returns early")
end

-- b. The interface-style event is registered.
do
    local world = load({ gamepadUI = false })
    assert(world.eventFrame.events.INPUT_DEVICE_INTERFACE_TRANSITION,
        "b. INPUT_DEVICE_INTERFACE_TRANSITION must be registered")
    print("b ok: INPUT_DEVICE_INTERFACE_TRANSITION is registered")
end

-- c. Login with the Gamepad UI off: one ticker, its first fire cleans up and
-- stops it, and nothing fires afterwards (budget: 1000 further intervals, 0 polls).
do
    local world = load({ gamepadUI = false })
    sendEvent(world, "PLAYER_LOGIN")
    assert(#world.tickers == 1, "c. login must create exactly one ticker, got " .. #world.tickers)
    local ticker = world.tickers[1]
    fire(world, ticker)
    assert(world.updates == 1, "c. first poll must call UpdateGamepad once, got " .. world.updates)
    assert(ticker.cancelled, "c. first poll with the Gamepad UI off must cancel the ticker")
    assert(liveCount(world) == 0, "c. no ticker may be live after the stop")
    local pollsBefore, updatesBefore = world.polls, world.updates
    for _ = 1, 1000 do fireLive(world) end
    assert(world.polls == pollsBefore, "g. 1000 intervals with the Gamepad UI off must run 0 polls, ran "
        .. (world.polls - pollsBefore))
    assert(world.updates == updatesBefore, "g. no UpdateGamepad call may follow the stop")
    print("c ok: login with the Gamepad UI off creates one ticker that stops after one cleanup poll")
    print("g ok: 1000 simulated intervals with the Gamepad UI off ran 0 polls")
end

-- d. Login with the Gamepad UI on: the ticker keeps running and is never cancelled.
do
    local world = load({ gamepadUI = true })
    sendEvent(world, "PLAYER_LOGIN")
    assert(#world.tickers == 1, "d. login must create exactly one ticker")
    local ticker = world.tickers[1]
    for _ = 1, 20 do fire(world, ticker) end
    assert(not ticker.cancelled, "d. the ticker must keep running while the Gamepad UI is on")
    assert(ticker.fires == 20, "d. expected 20 fires, got " .. ticker.fires)
    print("d ok: login with the Gamepad UI on keeps the ticker over 20 fires")
end

-- e. Off out of combat: the next poll cleans up and stops; on again starts one ticker.
do
    local world = load({ gamepadUI = true })
    sendEvent(world, "PLAYER_LOGIN")
    local first = world.tickers[1]
    world.gamepadUI = false
    sendEvent(world, "INPUT_DEVICE_INTERFACE_TRANSITION")
    assert(#world.tickers == 1, "e. the transition to off must not create a ticker")
    fire(world, first)
    assert(world.updates == 1, "e. the poll after switching off must clean up (UpdateGamepad once)")
    assert(first.cancelled and liveCount(world) == 0, "e. the poll after switching off must stop the ticker")

    world.gamepadUI = true
    sendEvent(world, "INPUT_DEVICE_INTERFACE_TRANSITION")
    assert(#world.tickers == 2, "e. switching on must start exactly one new ticker, got " .. #world.tickers)
    assert(liveCount(world) == 1, "e. exactly one ticker may run after switching on")
    sendEvent(world, "INPUT_DEVICE_INTERFACE_TRANSITION")
    assert(#world.tickers == 2 and liveCount(world) == 1,
        "e. a second transition while the ticker runs must not create a second ticker")
    local second = world.tickers[2]
    for _ = 1, 5 do fire(world, second) end
    assert(not second.cancelled, "e. the restarted ticker must keep running with the Gamepad UI on")
    print("e ok: off out of combat stops after one cleanup poll; on starts exactly one ticker")
end

-- f. Off during combat: the ticker keeps running and cleans up on every poll; the
-- first poll out of combat stops it.
do
    local world = load({ gamepadUI = true })
    sendEvent(world, "PLAYER_LOGIN")
    local ticker = world.tickers[1]
    sendEvent(world, "PLAYER_REGEN_DISABLED")
    world.combat = true
    world.gamepadUI = false
    sendEvent(world, "INPUT_DEVICE_INTERFACE_TRANSITION")
    local updatesBefore = world.updates
    for _ = 1, 5 do fire(world, ticker) end
    assert(not ticker.cancelled, "f. the ticker must keep running through the fight")
    assert(world.updates == updatesBefore + 5,
        "f. UpdateGamepad must be called on every poll during combat, got " .. (world.updates - updatesBefore))
    sendEvent(world, "PLAYER_REGEN_ENABLED")
    world.combat = false
    fire(world, ticker)
    assert(ticker.cancelled and liveCount(world) == 0,
        "f. the first poll after combat must stop the ticker with the Gamepad UI off")
    print("f ok: off during combat keeps the ticker until the first poll out of combat")
end

print("forever_pad_poll_smoke: all scenarios a-g passed")
