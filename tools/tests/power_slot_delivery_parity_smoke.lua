-- The power text route delivers its slots through WritePowerValueSlots, which inlines the loop of
-- Text.UpdateTextSlotsSecret for the power slots (a shared helper adds a call to every power event).
-- Both must hand every writer the same arguments in the same order, for plain, secret and published values.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local World = dofile(root .. "/tools/tests/health_tick_world.lua")
local w = World.New(root, flavor)
local f, text, Secrets = w.single, w.h.world.core.UFText, w.Secrets
assert(text.UpdateTextSlotsSecret and text.UpdatePower and text.PowerPercent, "text route exports missing")

local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = Copy(child) end
    return result
end

local function Record(calls, kind, index)
    return function(...)
        calls[#calls + 1] = { kind = kind, index = index, n = select("#", ...), ... }
    end
end

-- Slot 1 keeps a secret writer, slot 2 has none and falls back to the plain writer.
local function Arm(rt, calls)
    for i = 1, rt.powerSlotCount do
        local slot = rt.powerSlots[i]
        slot.secretWriter = i == 1 and Record(calls, "secret", i) or nil
        slot.writer = Record(calls, "plain", i)
    end
end

local function Same(a, b) return rawequal(a, b) end

local function Compare(label, left, right)
    assert(#left == #right, label .. ": writer call count " .. #left .. " vs " .. #right)
    for i = 1, #left do
        local a, b = left[i], right[i]
        assert(a.kind == b.kind and a.index == b.index and a.n == b.n, label .. ": call " .. i .. " shape")
        for j = 1, a.n do
            assert(Same(a[j], b[j]), label .. ": call " .. i .. " argument " .. j)
        end
    end
    return #left
end

local serial = 0
local function Prepare(second)
    f.MSUFUnitKey = "player"
    local spec = Copy(f.MSUFSpec)
    serial = serial + 1
    spec.key, spec.scope, spec._msufTextLayoutRevision = "player", "single", serial
    spec.text.powerLeft, spec.text.powerCenter, spec.text.powerRight = "CURMAX", second, "NONE"
    spec.text.powerColorByType = false
    text.Apply(f, spec)
    local rt = f._msufTextRuntime
    rt.powerPlain = false
    assert(rt.powerSlotCount == 2 and rt.powerSlots[1].secretWriter, "power slots were not compiled")
    return rt
end

local function Deliver(rt, label, power, powerMax, published)
    local viaRoute, direct = {}, {}
    Arm(rt, viaRoute)
    rt._dispatchPowerPercent, rt._dispatchPowerPercentReady = published, published ~= nil
    text.UpdatePower(f, "UNIT_DISPLAYPOWER", "player", power, powerMax)
    Arm(rt, direct)
    text.UpdateTextSlotsSecret(rt.powerSlots, rt.powerSlotCount, power, powerMax, "player", text.PowerPercent,
        rt.powerNeedsPercent, rt, published, published ~= nil)
    return Compare(label, viaRoute, direct)
end

local checked = 0
local rt = Prepare("CURRENT")
for _, case in ipairs({
    { "plain values", 30, 100 },
    { "secret current", Secrets.New("number"), 100 },
    { "secret maximum", 30, Secrets.New("number") },
    { "secret both", Secrets.New("number"), Secrets.New("number") },
}) do
    checked = checked + Deliver(rt, case[1], case[2], case[3], nil)
end
rt = Prepare("CURPERCENT")
assert(rt.powerNeedsPercent == true, "percent slot did not request the percent")
for _, case in ipairs({
    { "published plain percent", 30, 100, 30 },
    { "published secret percent", 30, 100, Secrets.New("number") },
    { "secret values, secret percent", Secrets.New("number"), Secrets.New("number"), Secrets.New("number") },
}) do
    checked = checked + Deliver(rt, case[1], case[2], case[3], case[4])
end
assert(checked >= 14, "parity compared too few writer calls: " .. checked)

-- Malformed slot tables deliver nothing on either route and raise nothing.
for _, mode in ipairs({ "nil-slots", "false-slot", "empty-slot", "dead-writers" }) do
    rt = Prepare("CURRENT")
    if mode == "nil-slots" then rt.powerSlots = nil
    elseif mode == "false-slot" then rt.powerSlots = { false }
    elseif mode == "empty-slot" then rt.powerSlots = { {} }
    else rt.powerSlots = { { secretWriter = false, writer = false } } end
    rt.powerSlotCount = 1
    text.UpdatePower(f, "UNIT_DISPLAYPOWER", "player", 30, 100)
    text.UpdateTextSlotsSecret(rt.powerSlots, rt.powerSlotCount, 30, 100, "player", text.PowerPercent, false, rt, nil, false)
end

print("power_slot_delivery_parity_smoke: ok (" .. flavor .. ", " .. checked .. " writer calls compared)")
