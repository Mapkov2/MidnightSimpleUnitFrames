-- Standalone regression for the EventBus global/unit dispatch fast paths.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

local reportedErrors = {}
_G.geterrorhandler = function()
    return function(err)
        reportedErrors[#reportedErrors + 1] = tostring(err)
    end
end

local driver
_G.CreateFrame = function(frameType)
    Equal(frameType, "Frame", "event bus driver type")

    local frame = {
        registered = {},
        scripts = {},
    }

    function frame:Hide()
        self.hidden = true
    end

    function frame:IsEventRegistered(event)
        return self.registered[event] ~= nil
    end

    function frame:RegisterEvent(event)
        self.registered[event] = { kind = "global" }
    end

    function frame:RegisterUnitEvent(event, ...)
        self.registered[event] = { kind = "unit", units = { ... } }
    end

    function frame:UnregisterEvent(event)
        self.registered[event] = nil
    end

    function frame:SetScript(script, callback)
        self.scripts[script] = callback
    end

    driver = frame
    return frame
end

local MSUF = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}

local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_EventBus.lua"))
local bus = chunk("MidnightSimpleUnitFrames", MSUF)
Check(type(bus) == "table", "event bus did not load")
Check(driver and driver.hidden, "event bus driver was not created and hidden")
Check(type(driver.scripts.OnEvent) == "function", "event bus OnEvent script missing")

local function Fire(event, ...)
    driver.scripts.OnEvent(driver, event, ...)
end

-- Global dispatch snapshots the initial list, removes once-handlers after their
-- callback, and keeps callbacks registered during dispatch for the next event.
local globalLog = {}
local function LateGlobalHandler()
    globalLog[#globalLog + 1] = "late"
end

Check(bus:Register("TEST_GLOBAL", "first", function()
    globalLog[#globalLog + 1] = "first"
    bus:Register("TEST_GLOBAL", "late", LateGlobalHandler)
end), "global handler registration failed")
Check(bus:Register("TEST_GLOBAL", "once", function()
    globalLog[#globalLog + 1] = "once"
end, nil, true), "global once-handler registration failed")

Fire("TEST_GLOBAL", "payload")
Fire("TEST_GLOBAL", "payload")
Equal(table.concat(globalLog, ","), "first,once,first,late", "global dispatch order")
Equal(bus.handlers.TEST_GLOBAL.dd, 0, "global dispatch depth leaked")

-- Preserve the existing once-after-callback behavior: replacing the same key
-- from inside its callback can clear `once` before the dispatcher evaluates it.
local mutableInitialCalls, mutableReplacementCalls = 0, 0
local function MutableReplacement()
    mutableReplacementCalls = mutableReplacementCalls + 1
end

Check(bus:Register("TEST_MUTABLE_ONCE", "mutable", function()
    mutableInitialCalls = mutableInitialCalls + 1
    bus:Register("TEST_MUTABLE_ONCE", "mutable", MutableReplacement, nil, false)
end, nil, true), "mutable once-handler registration failed")

Fire("TEST_MUTABLE_ONCE")
Fire("TEST_MUTABLE_ONCE")
Equal(mutableInitialCalls, 1, "mutable once initial callback count")
Equal(mutableReplacementCalls, 1, "mutable once replacement callback count")
Equal(bus.handlers.TEST_MUTABLE_ONCE.dd, 0, "mutable once dispatch depth leaked")

-- Unregistering during dispatch marks the entry dead, compacts it after the
-- current fanout, and releases the driver's event registration.
Check(bus:Register("TEST_SELF_REMOVE", "self", function()
    bus:Unregister("TEST_SELF_REMOVE", "self")
end), "self-removing handler registration failed")
Fire("TEST_SELF_REMOVE")
Check(bus.handlers.TEST_SELF_REMOVE == nil, "self-removing event was retained")
Check(not driver:IsEventRegistered("TEST_SELF_REMOVE"), "self-removing driver event was retained")

-- SafeCall must continue fanout after an error, remove a failing once-handler,
-- and leave dispatch depth balanced.
local survivorCalls = 0
Check(bus:Register("TEST_ERROR", "boom", function()
    error("intentional event bus smoke error")
end, nil, true), "failing once-handler registration failed")
Check(bus:Register("TEST_ERROR", "survivor", function()
    survivorCalls = survivorCalls + 1
end), "error survivor registration failed")

Fire("TEST_ERROR")
Fire("TEST_ERROR")
Equal(#reportedErrors, 1, "reported callback error count")
Check(reportedErrors[1]:find("intentional event bus smoke error", 1, true), "unexpected callback error")
Equal(survivorCalls, 2, "error stopped later or future handlers")
Equal(bus.handlers.TEST_ERROR.dd, 0, "error dispatch depth leaked")

-- UNIT_* events use the filtered path and keep the driver's unit-registration
-- union synchronized as handlers are added and removed.
local playerCalls, targetCalls = 0, 0
Check(bus:Register("UNIT_TEST_EVENT", "player", function(event, unit, value)
    Equal(event, "UNIT_TEST_EVENT", "player unit event name")
    Equal(unit, "player", "player unit filter")
    Equal(value, 17, "player unit payload")
    playerCalls = playerCalls + 1
end, "player"), "player unit-handler registration failed")
Check(bus:Register("UNIT_TEST_EVENT", "target", function(event, unit, value)
    Equal(event, "UNIT_TEST_EVENT", "target unit event name")
    Equal(unit, "target", "target unit filter")
    Equal(value, 23, "target unit payload")
    targetCalls = targetCalls + 1
end, { target = true }), "target unit-handler registration failed")

local unitRegistration = driver.registered.UNIT_TEST_EVENT
Check(unitRegistration and unitRegistration.kind == "unit", "unit event was not registered as unit-filtered")
local registeredUnits = {}
for i = 1, #unitRegistration.units do
    registeredUnits[unitRegistration.units[i]] = true
end
Check(registeredUnits.player and registeredUnits.target, "unit registration union is incomplete")

Fire("UNIT_TEST_EVENT", "player", 17)
Fire("UNIT_TEST_EVENT", "target", 23)
Fire("UNIT_TEST_EVENT", "focus", 99)
Equal(playerCalls, 1, "player unit-handler call count")
Equal(targetCalls, 1, "target unit-handler call count")
Equal(bus.handlers.UNIT_TEST_EVENT.dd, 0, "unit dispatch depth leaked")

bus:Unregister("UNIT_TEST_EVENT", "player")
unitRegistration = driver.registered.UNIT_TEST_EVENT
Equal(#unitRegistration.units, 1, "unit registration was not narrowed")
Equal(unitRegistration.units[1], "target", "wrong remaining unit registration")
bus:Unregister("UNIT_TEST_EVENT", "target")
Check(bus.handlers.UNIT_TEST_EVENT == nil, "empty unit event was retained")
Check(not driver:IsEventRegistered("UNIT_TEST_EVENT"), "empty unit driver event was retained")

print("PASS event bus dispatch: global/unit fast paths, mutation, once, filtering, and error isolation")
