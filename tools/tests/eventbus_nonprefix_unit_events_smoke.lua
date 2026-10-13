-- Unit events whose name does not start with UNIT_ (PLAYER_FLAGS_CHANGED for AFK
-- and DND edges, INCOMING_RESURRECT_CHANGED) still carry a unit token first. The
-- EventBus must treat them like every other unit event: subscribe the shared
-- driver with RegisterUnitEvent for the union of the requested units and deliver
-- only the matching units. A unit filter on one of them used to be dropped
-- silently, so the subscriber saw every unit's toggle. The unit-frame engine
-- shares the same list through EventBus.IsUnitEvent.
-- Usage: lua tools/tests/eventbus_nonprefix_unit_events_smoke.lua <repoRoot>
local repo = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")

function secureexecuterange(tbl, fn, ...)
    for key, value in pairs(tbl) do fn(key, value, ...) end
end

local function NewFrame()
    local f = { events = {}, units = {}, plain = {} }
    function f:Hide() end
    function f:SetScript(kind, fn) self[kind] = fn end
    function f:RegisterEvent(e)
        self.events[e] = true
        self.plain[e] = true
    end
    function f:RegisterUnitEvent(e, ...)
        self.events[e] = true
        self.units[e] = { ... }
        return true
    end
    function f:UnregisterEvent(e)
        self.events[e] = nil
        self.units[e] = nil
        self.plain[e] = nil
    end
    function f:IsEventRegistered(e) return self.events[e] == true end
    return f
end

local frames = {}
function CreateFrame()
    local f = NewFrame()
    frames[#frames + 1] = f
    return f
end

local ns = { ExportPublic = function() end }
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Kernel/MSUF_EventBus.lua"))("MidnightSimpleUnitFrames", ns)
local bus, driver = ns.EventBus, frames[1]

local function Fire(event, ...) driver.OnEvent(driver, event, ...) end

local function Sorted(list)
    local out = {}
    for i = 1, #(list or {}) do out[i] = list[i] end
    table.sort(out)
    return table.concat(out, ",")
end

for _, event in ipairs({ "PLAYER_FLAGS_CHANGED", "INCOMING_RESURRECT_CHANGED" }) do
    local seen = {}
    local function Record(name)
        return function(_, unit) seen[#seen + 1] = name .. ":" .. tostring(unit) end
    end

    assert(bus:Register(event, "a", Record("a"), "target") == true, event .. ": filtered registration refused")
    assert(driver.plain[event] == nil, event .. ": a unit filter fell back to an unfiltered RegisterEvent")
    assert(Sorted(driver.units[event]) == "target", event .. ": driver not subscribed for target only")

    Fire(event, "party1")
    assert(#seen == 0, event .. ": the unit filter was dropped (party1 reached the subscriber)")
    Fire(event, "target")
    assert(#seen == 1 and seen[1] == "a:target", event .. ": the filtered unit was not delivered")

    assert(bus:Register(event, "b", Record("b"), { "focus", "target" }) == true, event .. ": second filter refused")
    assert(Sorted(driver.units[event]) == "focus,target", event .. ": driver units are not the union of the filters")
    seen = {}
    Fire(event, "focus")
    assert(#seen == 1 and seen[1] == "b:focus", event .. ": focus reached the wrong subscribers: " .. table.concat(seen, " "))

    bus:Unregister(event, "a")
    assert(Sorted(driver.units[event]) == "focus,target", event .. ": the remaining filter changed on unregister")
    bus:Unregister(event, "b")
    assert(driver.events[event] == nil, event .. ": the driver stayed subscribed after the last unregister")

    -- Like every unit event, a registration without a unit filter is refused.
    assert(bus:Register(event, "c", Record("c")) == false, event .. ": a filterless unit event was accepted")
    assert(driver.events[event] == nil, event .. ": a refused registration still subscribed the driver")
end

-- The classifier the engine consumes.
assert(type(bus.IsUnitEvent) == "function", "EventBus.IsUnitEvent is not published")
for _, event in ipairs({ "UNIT_AURA", "UNIT_HEALTH", "PLAYER_FLAGS_CHANGED", "INCOMING_RESURRECT_CHANGED" }) do
    assert(bus.IsUnitEvent(event) == true, event .. " must classify as a unit event")
end
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "" }) do
    assert(bus.IsUnitEvent(event) == false, event .. " must not classify as a unit event")
end
assert(bus.IsUnitEvent(nil) == false and bus.IsUnitEvent(7) == false, "a non-string is not an event name")

-- One list, two consumers: the engine core reads the bus's classifier and keeps no copy.
local handle = assert(io.open(repo .. "/MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua", "rb"))
local core = handle:read("*a"):gsub("\r\n", "\n")
handle:close()
assert(core:find("EventBus.IsUnitEvent", 1, true), "UF_Core must take IsUnitEvent from the EventBus")
assert(not core:find("NONPREFIX_UNIT_EVENTS", 1, true), "UF_Core must not keep its own copy of the non-prefixed unit events")

print("eventbus_nonprefix_unit_events_smoke: OK")
