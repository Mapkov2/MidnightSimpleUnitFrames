-- Complete-operation cost of the shown cache owners, pinned to the 66f699c2 readings.
--
--   lua tools/tests/region_visibility_cost_smoke.lua <repo root> <flavor> [forward|reverse]
--   MSUF_BUDGET_MEASURE=1 prints the readings as PIN lines instead of asserting them.
--
-- Every operation runs on a fresh region fixture through the real exported entry:
-- the status runtime (all status regions share its setter), the exported Common
-- and Visuals setters, and the element modules' own hide entries. The VM count
-- is the number of Lua VM instructions run inside addon files, the native count
-- is every region mutation and secret query, the heap is the minimum of two
-- hook-free samples with the collector stopped. A candidate may be cheaper than
-- the pin on VM or heap; a native count must not change; nothing may allocate more.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "flavor required")
local order = arg[3] or "forward"
assert(order == "forward" or order == "reverse", "order must be forward or reverse")
local measureOnly = os.getenv("MSUF_BUDGET_MEASURE") == "1"
local Fixture = dofile(root .. "/tools/tests/region_visibility_world.lua")
local world, calls, Secrets = Fixture.Boot(root, flavor)
local core = world.core
local elements = core.UF.elements
local APIs = Fixture.APIs(world)
local NATIVE = { "SetShown", "Show", "Hide", "IsShown", "IsVisible", "issecretvalue" }

local function New() return Fixture.Region(world, calls, Secrets) end

-- name -> function returning the operation to run (fresh fixtures every call).
local OPS = {}
local NAMES = {}
local function Op(name, prepare)
    OPS[name] = prepare
    NAMES[#NAMES + 1] = name
end

local function Status(state, shown)
    return function()
        local badge, ring = New(), New()
        local frame = { levelBackdrop = badge, levelBackdropRing = ring }
        local runtime = core.UFStatusRuntime
        if state ~= "cold" then runtime.SetForeverLevelBadgeShown(frame, state == "warm-show") end
        return function() runtime.SetForeverLevelBadgeShown(frame, shown) end
    end
end
Op("status cold show", Status("cold", true))
Op("status cold hide", Status("cold", false))
Op("status warm show no-op", Status("warm-show", true))
Op("status warm hide no-op", Status("warm-hide", false))
Op("status show to hide", Status("warm-show", false))
Op("status hide to show", Status("warm-hide", true))
Op("status absent regions", function()
    local frame = {}
    return function() core.UFStatusRuntime.SetForeverLevelBadgeShown(frame, true) end
end)

for _, name in ipairs({ "Bars", "Visuals" }) do
    local setter = APIs[name]
    Op(name .. " setter cold show", function()
        local region = New()
        return function() setter(region, true) end
    end)
    Op(name .. " setter warm no-op", function()
        local region = New()
        setter(region, true)
        return function() setter(region, true) end
    end)
    Op(name .. " setter changed", function()
        local region = New()
        setter(region, true)
        return function() setter(region, false) end
    end)
end

-- The generic public boundary (compatibility seam for callers outside the core).
-- It is the one entry that asks whether its flag is secret, so a plain call pays
-- exactly one extra query; no core caller uses it any more.
local GENERIC = {}
local function Generic(name, prepare)
    GENERIC[name] = true
    Op(name, prepare)
end
Generic("generic Apply.Shown cold show", function()
    local region = New()
    return function() APIs.Apply(region, true) end
end)
Generic("generic Apply.Shown warm no-op", function()
    local region = New()
    APIs.Apply(region, true)
    return function() APIs.Apply(region, true) end
end)
Generic("generic Apply.Shown changed", function()
    local region = New()
    APIs.Apply(region, true)
    return function() APIs.Apply(region, false) end
end)
Generic("generic Apply.Shown secret", function()
    local region = New()
    local secret = Secrets.New("boolean")
    return function() APIs.Apply(region, secret) end
end)

local function ModuleHide(label, element, build)
    if not elements[element] then return end
    Op(label .. " cold hide", function()
        local frame = build(New())
        return function() elements[element].Disable(frame) end
    end)
    Op(label .. " warm hide no-op", function()
        local frame = build(New())
        elements[element].Disable(frame)
        return function() elements[element].Disable(frame) end
    end)
end
-- Group corner indicators: four corners, driven through the real threat updater.
local function CornerFrame()
    local frame = { MSUFUnitKey = "party1", MSUFGFCornerIndicators = {} }
    local cfg = { enabled = true, needsThreat = true, aggroSlots = {} }
    for index, key in ipairs({ "topleft", "topright", "bottomleft", "bottomright" }) do
        frame.MSUFGFCornerIndicators[key] = New()
        cfg.aggroSlots[index] = { key = key }
    end
    frame._msufGFCornerPreparedCfg = cfg
    return frame
end
local function Corners(label, prior, event, threat)
    Op("group corners " .. label, function()
        local frame = CornerFrame()
        local update = elements.GroupCornerIndicators.UpdateGroupThreat
        if prior ~= nil then update(frame, event, "party1", prior) end
        return function() update(frame, event, "party1", threat) end
    end)
end
Corners("threat show", nil, "UNIT_THREAT_SITUATION_UPDATE", true)
Corners("threat hide", true, "UNIT_THREAT_SITUATION_UPDATE", false)
Corners("threat repeat", true, "UNIT_THREAT_SITUATION_UPDATE", true)
Corners("flags repaint shown", true, "UNIT_FLAGS", true)
Corners("flags repaint hidden", false, "UNIT_FLAGS", false)

ModuleHide("threat text", "ThreatIndicator", function(r) return { threatIndicatorText = r } end)
ModuleHide("pet happiness", "PetHappinessIndicator", function(r) return { petHappinessIndicatorIcon = r } end)
ModuleHide("group corners", "GroupCornerIndicators", function(r) return { MSUFGFCornerIndicators = { topleft = r } } end)
ModuleHide("group visuals", "GroupVisuals", function(r) return { MSUFGFDispelOverlay = r } end)

local function IsMeasured(source)
    return source:find("/MidnightSimpleUnitFrames/", 1, true) ~= nil
end

local function Measure(name)
    local run = OPS[name]()
    Fixture.Reset(calls)
    local instructions = 0
    debug.sethook(function()
        local info = debug.getinfo(2, "S")
        if info and IsMeasured(info.source:gsub("\\", "/")) then instructions = instructions + 1 end
    end, "", 1)
    run()
    debug.sethook()
    local native = {}
    for _, key in ipairs(NATIVE) do native[key] = calls[key] end
    local heap
    for _ = 1, 2 do
        local sample = OPS[name]()
        assert(debug.gethook() == nil, "heap sample must be hook-free")
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        sample()
        local kb = collectgarbage("count") - before
        collectgarbage("restart")
        heap = heap and math.min(heap, kb) or kb
    end
    return { vm = instructions, native = native, heap = heap }
end

-- Readings of the parent 66f699c2 (MSUF_BUDGET_MEASURE=1 on that tree), except the four
-- generic rows at the end: they pin the new boundary. For a plain flag the parent read 11, 7
-- and 10 VM instructions there with no secret query; the boundary now asks once per call and
-- hands the plain flag to the trusted entry. No core caller uses it any more.
-- The parent truth-tested a secret flag, which the client rejects, so it has no secret row.
local PINS = {
    ["status cold show"] = { vm = 63, heap = 0.000000000,
        native = { SetShown = 2, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["status cold hide"] = { vm = 59, heap = 0.000000000,
        native = { SetShown = 2, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["status warm show no-op"] = { vm = 31, heap = 0.000000000,
        native = { SetShown = 0, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["status warm hide no-op"] = { vm = 29, heap = 0.000000000,
        native = { SetShown = 0, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["status show to hide"] = { vm = 59, heap = 0.000000000,
        native = { SetShown = 2, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["status hide to show"] = { vm = 63, heap = 0.000000000,
        native = { SetShown = 2, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["status absent regions"] = { vm = 23, heap = 0.000000000,
        native = { SetShown = 0, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["Bars setter cold show"] = { vm = 8, heap = 0.000000000,
        native = { SetShown = 1, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["Bars setter warm no-op"] = { vm = 4, heap = 0.000000000,
        native = { SetShown = 0, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["Bars setter changed"] = { vm = 8, heap = 0.000000000,
        native = { SetShown = 1, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["Visuals setter cold show"] = { vm = 13, heap = 0.000000000,
        native = { SetShown = 1, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["Visuals setter warm no-op"] = { vm = 6, heap = 0.000000000,
        native = { SetShown = 0, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["Visuals setter changed"] = { vm = 13, heap = 0.000000000,
        native = { SetShown = 1, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["threat text cold hide"] = { vm = 25, heap = 0.000000000,
        native = { SetShown = 0, Show = 0, Hide = 1, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["threat text warm hide no-op"] = { vm = 19, heap = 0.000000000,
        native = { SetShown = 0, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["pet happiness cold hide"] = { vm = 13, heap = 0.000000000,
        native = { SetShown = 0, Show = 0, Hide = 1, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["pet happiness warm hide no-op"] = { vm = 10, heap = 0.000000000,
        native = { SetShown = 0, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["group corners cold hide"] = { vm = 32, heap = 0.031250000,
        native = { SetShown = 1, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["group corners warm hide no-op"] = { vm = 28, heap = 0.000000000,
        native = { SetShown = 0, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["group corners threat show"] = { vm = 109, heap = 0.125000000,
        native = { SetShown = 4, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["group corners threat hide"] = { vm = 111, heap = 0.000000000,
        native = { SetShown = 4, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["group corners threat repeat"] = { vm = 24, heap = 0.000000000,
        native = { SetShown = 0, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["group corners flags repaint shown"] = { vm = 92, heap = 0.000000000,
        native = { SetShown = 0, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["group corners flags repaint hidden"] = { vm = 92, heap = 0.000000000,
        native = { SetShown = 0, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["group visuals cold hide"] = { vm = 103, heap = 0.093750000,
        native = { SetShown = 1, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["group visuals warm hide no-op"] = { vm = 99, heap = 0.000000000,
        native = { SetShown = 0, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 } },
    ["generic Apply.Shown cold show"] = { vm = 21, heap = 0.000000000,
        native = { SetShown = 1, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 1 } },
    ["generic Apply.Shown warm no-op"] = { vm = 16, heap = 0.000000000,
        native = { SetShown = 0, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 1 } },
    ["generic Apply.Shown changed"] = { vm = 20, heap = 0.000000000,
        native = { SetShown = 1, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 1 } },
    ["generic Apply.Shown secret"] = { vm = 10, heap = 0.000000000,
        native = { SetShown = 1, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 1 } },
}

local sequence = order == "forward" and NAMES or {}
if order == "reverse" then
    for i = #NAMES, 1, -1 do sequence[#sequence + 1] = NAMES[i] end
end

local failures = {}
local measured = {}
for _, name in ipairs(sequence) do
    local result = Measure(name)
    measured[name] = result
    local native = {}
    for _, key in ipairs(NATIVE) do native[#native + 1] = key .. "=" .. result.native[key] end
    if measureOnly then
        print(string.format("PIN\t%s\t%s\tvm=%d\t%s\theap=%.9f", flavor, name, result.vm, table.concat(native, ","), result.heap))
    else
        local pin = PINS[name]
        if not pin then
            failures[#failures + 1] = name .. ": no pinned reading"
        else
            if result.vm > pin.vm then failures[#failures + 1] = string.format("%s: %d VM instructions > %d", name, result.vm, pin.vm) end
            for _, key in ipairs(NATIVE) do
                if result.native[key] ~= pin.native[key] then
                    failures[#failures + 1] = string.format("%s: %s calls %d ~= %d", name, key, result.native[key], pin.native[key])
                end
            end
            if result.heap > pin.heap then
                failures[#failures + 1] = string.format("%s: heap %.9f KB > %.9f KB", name, result.heap, pin.heap)
            end
        end
    end
end

if not measureOnly then
    -- The comparison must be able to fail: a wrapper with one extra call and one transient table.
    local base = measured["Visuals setter cold show"]
    local pin = PINS["Visuals setter cold show"]
    local setter = APIs.Visuals
    local region = New()
    local instructions = 0
    debug.sethook(function()
        local info = debug.getinfo(2, "S")
        if info and (IsMeasured(info.source:gsub("\\", "/")) or info.source:find("region_visibility_cost_smoke", 1, true)) then
            instructions = instructions + 1
        end
    end, "", 1)
    local function Heavier(target) local transient = { target } setter(target, true) return transient end
    Heavier(region)
    debug.sethook()
    assert(instructions > pin.vm, "the VM comparison cannot detect an extra wrapper")
    local target = New()
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    Heavier(target)
    local kb = collectgarbage("count") - before
    collectgarbage("restart")
    assert(kb > pin.heap, "the heap comparison cannot detect a transient table")
    assert(base.vm <= pin.vm)
end
assert(#failures == 0, "complete-operation cost exceeds the pinned parent readings:\n" .. table.concat(failures, "\n"))
print(string.format("region_visibility_cost_smoke: %s (%s %s: %d operations)", measureOnly and "measure" or "ok", flavor, order, #sequence))
