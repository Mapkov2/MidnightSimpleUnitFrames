-- Repository-retained structural/lifecycle checks for the Auras3 module split.
local root = arg and arg[1] or "."
local loader = assert(loadfile(root .. "/.github/scripts/auras3_test_loader.lua"))()
local entries = {
    "MSUF_Auras3_SpellIndicators.lua", "MSUF_Auras3_UnitFrames.lua",
    "MSUF_Auras3_EditMode.lua", "MSUF_Auras3_Menu_Model.lua",
}
local seen, total = {}, 0
local function Forbidden()
    error("an Auras3 factory performed runtime work before entry-point composition", 2)
end

-- Factory registration may allocate its small module namespace. It must not
-- create frames, subscribe, schedule, load addons, or read/seed saved profiles.
_G.CreateFrame = Forbidden
_G.C_Timer = { After = Forbidden, NewTimer = Forbidden, NewTicker = Forbidden }
_G.C_AddOns = { LoadAddOn = Forbidden, IsAddOnLoaded = Forbidden }
_G.MSUF_DB = setmetatable({}, { __index = Forbidden, __newindex = Forbidden })
local namespace = { UF = {}, MSUF_Auras3 = {} }
for _, entry in ipairs(entries) do
    local path = root .. "/MidnightSimpleUnitFrames/Auras3/" .. entry
    local group = assert(loader.Group(path), "entry missing from the authoritative XML: " .. entry)
    assert(#group > 1, "entry has no contiguous prerequisite factory group: " .. entry)
    assert(group[#group]:match("([^/]+)$") == entry, "entry is not last in its XML group")
    for index, modulePath in ipairs(group) do
        assert(not seen[modulePath], "duplicate Auras3 XML module: " .. modulePath)
        seen[modulePath] = true
        local chunk = assert(loadfile(modulePath)) -- Includes actual Lua 5.1 local/upvalue limits.
        if index < #group then
            chunk("MidnightSimpleUnitFrames", namespace)
            total = total + 1
        end
    end
end
assert(namespace.MSUF_Auras3.__unitFrameBackendLoaded == nil,
    "factory registration prematurely initialized the native runtime")
assert(next(_G.MSUF_DB) == nil, "factory registration modified SavedVariables")

local runtime = loader.ReadGroup(root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua")
assert(not runtime:find("container.ApplyLayout =", 1, true), "MSUF replaced Blizzard's native layout")
assert(runtime:find("events = EMPTY_EVENTS", 1, true), "UF regained duplicate aura event ownership")
assert(runtime:find("container:SetEnabled(polarityVisible == true)", 1, true),
    "unit identity gating lost native registration ownership")
assert(runtime:find("_msufA3UnitAuraConfigCache", 1, true)
    and runtime:find("cached.visualGen == visualGen", 1, true)
    and runtime:find("cached.specSerial == specSerial", 1, true),
    "compiled frame configuration lost a cache-invalidation dimension")
assert(runtime:find("function A3.InvalidateUnitRuntimeConfig(unit)", 1, true),
    "Menu writes cannot invalidate unit configuration independently of UF serial")
assert(runtime:find("function A3.RefreshRoundedDispelOverlayMasks()", 1, true),
    "rounded changes lost native owner recreation")
print("PASS Auras3 refactor contracts: 4 XML entry groups, " .. total
    .. " inert factories, Lua 5.1 compilation and native/cache ownership")
