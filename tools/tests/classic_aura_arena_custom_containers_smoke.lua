-- Classic Custom Aura containers on Arena frames
-- (Game/Classic/Auras/MSUF_Auras3_Features.lua, EffectiveContainers).
--
-- The menu keeps one Arena record for every arena slot: Menu_Common's
-- NormalizeUnit maps arena1..arena5 to "arena" and Menu_Containers writes
-- customContainers.perUnit.arena. The Classic compiler looked the record up by
-- the frame's own unit (perUnit.arena1), so every Custom Aura container on the
-- TBC and Mists arena frames, the "Dots on target" preset included, stayed empty
-- while Edit Mode still previewed them (re-review R6). Mainline reads the same
-- record through UnitCustomContainerScope (Runtime_CustomConfig.lua).
--
-- Runs per Classic flavor with the flavor's real client model and TOC order.
-- The containers are written through the real menu model:
--   * TBC and Mists: every arena slot the client publishes compiles a custom lane
--     and the preset target-DoT lane from the one Arena record;
--   * Vanilla has no arena units, so its client publishes no arena slot and the
--     arena mapping has nothing to reach;
--   * on every flavor the boss record stays shared by boss1..boss5 and target
--     keeps its own record.
-- Arguments: repository root, flavor (Vanilla, TBC or Mists), then optionally
-- the features path (mutation runs).
local root = assert(arg[1], "repository root argument missing")
root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))
local flavor = assert(arg[2], "flavor argument missing")
local featuresOverride = arg[3]

-- Client placement: the project globals and the X-MSUF-Client tag the flavor's TOC carries.
local PROJECT_IDS = { Vanilla = 2, TBC = 5, Mists = 19 }
assert(PROJECT_IDS[flavor], "unknown Classic flavor: " .. tostring(flavor))
_G.WOW_PROJECT_MAINLINE, _G.WOW_PROJECT_CLASSIC = 1, 2
_G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC, _G.WOW_PROJECT_MISTS_CLASSIC = 5, 19
_G.WOW_PROJECT_ID = PROJECT_IDS[flavor]
_G.C_AddOns = { GetAddOnMetadata = function(_, field)
    if field == "X-MSUF-Client" then return flavor end
    return nil
end }
_G.C_EventUtils = { IsEventValid = function() return true end }
_G.UnitClass = function() return "Rogue", "ROGUE" end
_G.GetSpellInfo = function(spellID) return "Spell " .. tostring(spellID) end

local namespace = {
    MSUF_Auras3 = {},
    UF = { RegisterElement = function() end },
    ExportPublic = function(name, value) _G[name] = value; return value end,
}
_G.MSUF_NS, _G.MSUF = namespace, namespace
_G.MSUF_DB = { auras3 = { enabled = true, shared = {}, perUnit = {} } }

local manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
-- The menu model reads the stored-token check from the real profile normalizer.
assert(loadfile(root .. "/tools/tests/profile_normalize_loader.lua"))().Install(root, namespace)
local FEATURES = "MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_Features.lua"
manifest.LoadSelected(root, flavor, namespace, {
    "Game/Shared/Initialize.lua", "State/MSUF_AuraDefaults.lua",
    "Auras3/MSUF_Auras3_Core.lua", "Auras3/MSUF_Auras3_IconShape.lua",
    "Game/Classic/Auras/MSUF_Auras3_DataShared.lua",
    "Game/" .. flavor .. "/Auras/MSUF_Auras3_DotData.lua",
    "Game/" .. flavor .. "/Auras/MSUF_Auras3_DefensiveData.lua",
    "Game/Classic/Auras/MSUF_Auras3_Visuals.lua", "Game/Classic/Auras/MSUF_Auras3_Features.lua",
    "Game/Classic/Auras/MSUF_Auras3_Compile.lua",
    "Auras3/MenuModel/MSUF_Auras3_Menu_Schema.lua", "Auras3/MenuModel/MSUF_Auras3_Menu_Common.lua",
    "Auras3/MenuModel/MSUF_Auras3_Menu_Storage.lua", "Auras3/MenuModel/MSUF_Auras3_Menu_Presets.lua",
    "Auras3/MenuModel/MSUF_Auras3_Menu_GroupFilters.lua", "Auras3/MenuModel/MSUF_Auras3_Menu_Appearance.lua",
    "Auras3/MenuModel/MSUF_Auras3_Menu_Containers.lua", "Auras3/MenuModel/MSUF_Auras3_Menu_CustomSpells.lua",
    "Auras3/MenuModel/MSUF_Auras3_Menu_Filters.lua", "Auras3/MSUF_Auras3_Menu_Model.lua",
}, function(path)
    local features = featuresOverride and path:sub(-#FEATURES) == FEATURES
    return loadfile(features and featuresOverride or path)
end)
local client = namespace.Client
assert(client and client.IsClassic == true and client.Flavor == flavor,
    "precondition: the client model did not place " .. flavor)
local A3 = namespace.MSUF_Auras3
local features = assert(A3.ClassicFeatures, "Classic feature compiler did not load")
local Model = assert(A3.MenuModel, "shared Aura menu model did not load")
-- The profile's tree as written: the core's full normalizer needs the whole
-- State layer behind it, and the menu model shapes the roots it writes itself.
A3.EnsureDB = function()
    local auras = _G.MSUF_DB.auras3
    return auras, auras.shared
end

-- A known target DoT of this flavor, so the preset compiles its lane.
local knownDot
for _, spells in pairs(A3.TargetDotData or {}) do
    for i = 1, #spells do
        local spellID = tonumber(spells[i] and spells[i][1])
        if spellID and (not knownDot or spellID < knownDot) then knownDot = spellID end
    end
end
assert(knownDot, "precondition: " .. flavor .. " ships no target DoT data")

-- Written the way the Arena, Boss and Target pages write them.
local function Write(scope, index, spellIDs, auraType)
    local item = assert(Model.CustomContainer(scope, index, true), "menu returned no container for " .. scope)
    item.enabled = true
    item.spellIDs = spellIDs
    if auraType then item.auraType = auraType end
    return item
end
Write("arena1", 1, "999001", "BUFF")
Write("arena", A3.PRESET_CUSTOM_CONTAINER_INDEX, tostring(knownDot))
Write("boss", 1, "999002", "BUFF")
Write("target", 1, "999003", "BUFF")
local auras = Model.EnsureDB()
local perUnit = auras.customContainers.perUnit
assert(type(perUnit.arena) == "table" and perUnit.arena1 == nil,
    "precondition: the menu no longer keeps one Arena record for every arena slot")

local presetKind = "custom" .. tostring(A3.PRESET_CUSTOM_CONTAINER_INDEX)
local slots = tonumber(client.MaxArenaOpponents) or 0
if flavor == "Vanilla" then
    assert(slots == 0 and client.SupportsUnit("arena1") == false,
        "Vanilla published arena slots, but Classic Era has no arena units")
else
    assert(slots == 5 and client.SupportsUnit("arena1") == true,
        "precondition: " .. flavor .. " publishes " .. tostring(slots) .. " arena slots, expected 5")
end
for i = 1, slots do
    local unit = "arena" .. i
    local lanes = features.CompileUnitLanes(auras, unit, {}, 0)
    assert(lanes and lanes.custom1 and lanes.custom1.includeSpellIDs[999001] == true,
        flavor .. " " .. unit .. " compiled no lane for the Arena Custom Aura container")
    assert(lanes[presetKind] and lanes[presetKind].includeSpellIDs[knownDot] == true
        and lanes[presetKind].appearanceKind == "targetDots",
        flavor .. " " .. unit .. " compiled no lane for the Arena \"Dots on target\" preset")
end

-- The Boss record still serves boss1..boss5, Target keeps its own record, and
-- neither borrows the Arena one.
for i = 1, 5 do
    local lanes = features.CompileUnitLanes(auras, "boss" .. i, {}, 0)
    assert(lanes and lanes.custom1 and lanes.custom1.includeSpellIDs[999002] == true
        and lanes[presetKind] == nil,
        flavor .. " boss" .. i .. " no longer compiles the shared Boss record alone")
end
local targetLanes = features.CompileUnitLanes(auras, "target", {}, 0)
assert(targetLanes and targetLanes.custom1 and targetLanes.custom1.includeSpellIDs[999003] == true
    and targetLanes[presetKind] == nil,
    flavor .. " target no longer compiles its own record alone")

print("classic aura arena custom containers smoke passed: " .. flavor .. " (" .. slots .. " arena slots)")
