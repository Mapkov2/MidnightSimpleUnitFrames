-- Classic aura rank / name matching smoke.
--
-- Vanilla, TBC and Mists ship no SpellName alias catalog. Their aura payloads
-- are readable, so every lane that carries includeSpellIDs also carries
-- includeSpellNames and the backend matches the aura name when the ID misses.
-- That is what lets a rank-1 or cast ID match every rank (Vanilla/TBC) and the
-- aura ID (Mists cast-versus-aura drift) on whatever client build is running,
-- the way WeakAuras matches auras by name on Classic. The catalog this replaced
-- could only ever add IDs that share the exact same name, so the name match
-- covers everything it did. Explicit A3.AuraSpellIDAliases stay for pairs whose
-- names differ.
local root = assert(arg[1], "repository root argument missing")
root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))

local function readFile(rel)
    local handle = assert(io.open(root .. "/" .. rel, "rb"), "missing file: " .. rel)
    local text = handle:read("*a")
    handle:close()
    return (text:gsub("\r\n", "\n"))
end

local function exists(rel)
    local handle = io.open(root .. "/" .. rel, "rb")
    if handle then handle:close() return true end
    return false
end

local function count(set)
    local n = 0
    for _ in pairs(set or {}) do n = n + 1 end
    return n
end

local Manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
local ownership = readFile("tools/classic-owned-addon-paths.txt")

-- 1. Manifests: no catalog, no catalog resolver, nothing left to regenerate.
for _, flavor in ipairs({ "Vanilla", "TBC", "Mists" }) do
    local paths = Manifest.Paths(root, flavor)
    for _, path in ipairs(paths) do
        assert(not path:find("/AliasData/", 1, true), flavor .. " must not load an alias catalog: " .. path)
        assert(not path:find("MSUF_Auras3_AuraAliases.lua", 1, true),
            flavor .. " must not load the SpellName catalog resolver")
    end
    local joined = table.concat(paths, "\n")
    assert(joined:find("Game/Classic/Auras/MSUF_Auras3_DataShared.lua", 1, true),
        flavor .. " must load the shared Classic data helpers")
    assert(joined:find("Game/Classic/Auras/MSUF_Auras3_Features.lua", 1, true),
        flavor .. " must load the Classic feature compiler")
    assert(not readFile("MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_" .. flavor .. ".toc"):find("AliasData", 1, true),
        flavor .. " TOC still names alias data")
    assert(not exists("MidnightSimpleUnitFrames/Game/" .. flavor .. "/Auras/AliasData/MSUF_Auras3_AliasData_Common.lua"),
        flavor .. " still ships a generated alias catalog")
    assert(not ownership:find("Game/" .. flavor .. "/Auras/AliasData/", 1, true),
        flavor .. " alias data is still declared Classic-owned")
    assert(not exists(".github/auras3-alias-catalog-" .. flavor:lower() .. ".json"),
        flavor .. " alias catalog manifest is still present")
end

-- 2. Every compile site that builds an include-ID set builds the name set next
-- to it, and both runtime predicates consult it when the ID misses.
local compileSource = readFile("MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_Compile.lua")
assert(compileSource:find("includeSpellNames = A3.ClassicFeatures.NameHash(includeSpellIDs)", 1, true),
    "Buff/Debuff include lists must compile an aura-name set")
local featuresSource = readFile("MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_Features.lua")
assert(featuresSource:find("includeSpellNames = NameHash(spellIDs),", 1, true),
    "custom, preset and indicator lanes must compile an aura-name set")
assert(featuresSource:find("cfg.includeSpellNames and cfg.includeSpellNames[name] == true", 1, true),
    "Features.MatchAura must fall back to the aura name")
-- Legacy GetSpellInfo is synchronous on Classic; C_Spell.GetSpellName is lazy
-- and returned nil for uncached IDs, which would leave the name set empty.
assert(featuresSource:find("if type(GetSpellInfo) == \"function\" then\n        name = GetSpellInfo(spellID)", 1, true),
    "Classic name sets must resolve through the synchronous legacy GetSpellInfo first")
local backendSource = readFile("MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua")
assert(backendSource:find("and cfg.includeSpellNames[name] == true", 1, true),
    "ShouldShowAura must fall back to the aura name")

-- 3. Behaviour on the real feature compiler. Each fixture: a configured ID, its
-- name, and live aura IDs with the same name (Rejuvenation and Power Word:
-- Shield ranks on Vanilla, Rejuvenation and Blessing of Protection ranks on TBC,
-- the Renewing Mist cast -> aura and Lifebloom drift on Mists).
local CASES = {
    Vanilla = {
        { 774, "Rejuvenation", { 1058, 1430, 2090, 3627, 25299 } },
        { 17, "Power Word: Shield", { 592, 600, 10901 } },
    },
    TBC = {
        { 774, "Rejuvenation", { 1058, 25299, 26981, 26982 } },
        { 1022, "Blessing of Protection", { 5599, 10278 } },
    },
    Mists = {
        { 115151, "Renewing Mist", { 119611 } },
        { 33763, "Lifebloom", { 33778 } },
    },
}
local UNRELATED = { spellId = 116849, name = "Life Cocoon" }

local function NoFilter() return false end
local function Timed() return true end

for _, flavor in ipairs({ "Vanilla", "TBC", "Mists" }) do
    local cases = CASES[flavor]
    local dot, defensive = cases[1], cases[2]
    local names = {}
    for _, case in ipairs(cases) do names[case[1]] = case[2] end

    local A3 = {
        TargetDotData = { PRIEST = { { dot[1], dot[2] } } },
        PlayerDefensiveData = { PRIEST = { { defensive[1], defensive[2] } } },
    }
    local namespace = {
        Client = { IsClassic = true }, MSUF_Auras3 = A3,
        UF = { RegisterElement = function() end }, ExportPublic = function() end,
    }
    _G.MSUF_NS = namespace
    _G.UnitClass = function() return "Priest", "PRIEST" end
    _G.GetSpellInfo = function(spellID) return names[spellID] end
    _G.C_Spell = nil
    Manifest.LoadSelected(root, flavor, namespace, {
        "Game/Classic/Auras/MSUF_Auras3_DataShared.lua",
        "Game/Classic/Auras/MSUF_Auras3_Features.lua",
        "Game/Classic/Auras/MSUF_Auras3_Compile.lua",
    })
    local features = assert(A3.ClassicFeatures, flavor .. " Classic feature compiler did not load")
    assert(A3.CompileCustomAuraAliases == nil, flavor .. " must not install the SpellName catalog resolver")
    assert(A3.AuraAliasCatalog == nil, flavor .. " must not carry a SpellName catalog")

    -- The expander adds the configured ID and explicit aliases, nothing else.
    local out = {}
    A3.AddAuraSpellIDAndAliases(out, dot[1])
    assert(count(out) == 1 and out[dot[1]] == true, flavor .. " expander broadened an ID without an explicit alias")
    A3.AuraSpellIDAliases[424242] = { 434343 }
    out = {}
    A3.AddAuraSpellIDAndAliases(out, 424242)
    assert(count(out) == 2 and out[424242] == true and out[434343] == true,
        flavor .. " explicit cross-name aliases must still expand")
    A3.AuraSpellIDAliases[424242] = nil

    local auras = { customContainers = { perUnit = {
        player = { items = {
            [4] = { enabled = true, playerDefensives = true, placed = { size = 24, max = 4 }, filters = {} },
        } },
        target = { items = {
            [1] = { enabled = true, auraType = "BUFF", spellIDs = tostring(defensive[1]),
                placed = { size = 20, max = 2 }, filters = {} },
            [4] = { enabled = true, targetDots = true, auraType = "DEBUFF", spellIDs = tostring(dot[1]),
                placed = { size = 22, max = 4 }, filters = {} },
        } },
    } } }

    local playerLanes = features.CompileUnitLanes(auras, "player", nil, 0)
    local targetLanes, _, targetSource = features.CompileUnitLanes(auras, "target", nil, 0)
    local lanes = {
        { label = "Player Defensives", lane = assert(playerLanes and playerLanes.custom4, flavor .. " defensive lane"), case = defensive },
        { label = "custom container", lane = assert(targetLanes and targetLanes.custom1, flavor .. " custom lane"), case = defensive },
        { label = "Target DoTs", lane = assert(targetLanes and targetLanes.custom4, flavor .. " DoT lane"), case = dot },
    }
    for _, item in ipairs(lanes) do
        local lane, case = item.lane, item.case
        local where = flavor .. " " .. item.label
        assert(count(lane.includeSpellIDs) == 1 and lane.includeSpellIDs[case[1]] == true,
            where .. " must keep exactly the configured ID")
        assert(count(lane.includeSpellNames) == 1 and lane.includeSpellNames[case[2]] == true,
            where .. " must compile the configured spell's name")
        local instance = 0
        local function Match(spellID, name)
            instance = instance + 1
            return features.MatchAura(lane, "target", {
                spellId = spellID, name = name, duration = 10,
                auraInstanceID = instance, isPlayerAura = true,
            }, NoFilter, Timed)
        end
        assert(Match(case[1], case[2]) == true, where .. " lost its own configured ID")
        for _, liveID in ipairs(case[3]) do
            assert(Match(liveID, case[2]) == true,
                string.format("%s must match same-name aura %d (%s)", where, liveID, case[2]))
        end
        assert(Match(UNRELATED.spellId, UNRELATED.name) == false, where .. " matched an unrelated aura")
    end

    -- A custom container still deduplicates every same-name rank out of the
    -- base Debuff lane, not just the configured ID.
    local buff, debuff = {}, {}
    features.ApplyAutoExclusions(buff, debuff, targetLanes, targetSource, "target")
    for _, liveID in ipairs(dot[3]) do
        assert(features.IsAutoExcluded(debuff, { spellId = liveID, name = dot[2] }) == true,
            string.format("%s Debuff lane must auto-exclude same-name aura %d", flavor, liveID))
    end
    assert(features.IsAutoExcluded(debuff, UNRELATED) == false, flavor .. " auto-excluded an unrelated aura")
    print(string.format("classic_aura_rank_name_match_smoke: %s ok", flavor))
end

print("classic_aura_rank_name_match_smoke: ok")
