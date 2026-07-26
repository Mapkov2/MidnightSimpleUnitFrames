local rawPairs = pairs
local pairCalls = 0
_G.pairs = function(tbl)
    pairCalls = pairCalls + 1
    return rawPairs(tbl)
end

local auras = { shared = {} }
local root = { MSUF_Auras3 = {} }
function root.MSUF_Auras3.EnsureDB()
    return auras, auras.shared
end

local chunk, loadError = loadfile("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Menu_Model.lua")
assert(chunk, loadError)
chunk("MidnightSimpleUnitFrames", root)
_G.pairs = rawPairs

local model = assert(root.MSUF_Auras3.MenuModel, "Aura menu model missing")
local auraFilter = assert(_G.MSUF_GF_AuraFilter, "group AuraFilter missing")
local publicSpells = assert(auraFilter.PUBLIC_AURA_PRESET_SPELLS, "public aura presets missing")

local ptr6Published = {
    PRESERVATION_EVOKER = { 355941, 363502, 364343, 366155, 367364, 373267, 376788, 409895 },
    AUGMENTATION_EVOKER = { 360827, 395152, 395296, 410089, 410263, 410686, 413984 },
    RESTO_DRUID = { 774, 8936, 33763, 48438, 155777, 439530 },
    DISC_PRIEST = { 17, 194384, 1253593, 1300008, 1300009 },
    HOLY_PRIEST = { 139, 41635, 77489 },
    MISTWEAVER_MONK = { 115175, 119611, 124682, 450769, 1292922 },
    RESTO_SHAMAN = { 974, 383648, 61295, 382024, 207400, 444490 },
    HOLY_PALADIN = { 53563, 156322, 156910, 1244893, 200025, 431381 },
}
for presetKey, spellIDs in pairs(ptr6Published) do
    local preset = assert(publicSpells[presetKey], "missing PTR 6 preset " .. presetKey)
    for i = 1, #spellIDs do
        assert(preset[spellIDs[i]] == true,
            string.format("PTR 6 aura %d missing from %s", spellIDs[i], presetKey))
    end
end

local sated = assert(publicSpells.SATED, "Sated/Exhaustion preset missing")
for _, spellID in ipairs({ 57723, 57724, 80354, 95809, 160455, 264689 }) do
    assert(sated[spellID] == true, "Sated/Exhaustion aura missing: " .. spellID)
end

local compiledBlacklist = assert(auraFilter.BuildBlacklistHash({
    blacklistCats = { SATED = true, PRESERVATION_EVOKER = true },
}), "published aura blacklist did not compile")
assert(compiledBlacklist[57723] == true and compiledBlacklist[409895] == true,
    "published aura presets did not reach the group blacklist hash")

local groupAuraFile = assert(io.open("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupAuras.lua", "rb"))
local groupAuraSource = groupAuraFile:read("*a")
groupAuraFile:close()
assert(groupAuraSource:find("local GF_AURA_BLACKLIST_AVAILABLE = true", 1, true),
    "group Aura blacklist is not enabled for PTR 6")
assert(not groupAuraSource:find("Blacklist is unavailable in WoW 12.1", 1, true),
    "stale unavailable copy remains on the group Aura page")

pairCalls = 0
local _, shared = model.EnsureDB()
local firstSeedPairs = pairCalls
assert(shared.showBuffs == true and type(shared.filters) == "table",
    "first EnsureDB did not seed shared defaults")

pairCalls = 0
model.EnsureDB()
local cachedReadPairs = pairCalls
assert(cachedReadPairs < firstSeedPairs,
    "repeated EnsureDB still walks the complete defaults tree")

shared.filters = {}
model.EnsureDB()
assert(shared.filters.enabled == true,
    "replacement nested defaults table incorrectly reused its parent cache entry")

shared.showBuffs = nil
model.InvalidateDefaultSeedCache()
pairCalls = 0
model.EnsureDB()
assert(shared.showBuffs == true and pairCalls > cachedReadPairs,
    "explicit cache invalidation did not restore a removed default")

auras = { shared = {} }
pairCalls = 0
local _, replacementShared = model.EnsureDB()
assert(replacementShared.showDebuffs == true and pairCalls > cachedReadPairs,
    "replacement profile table incorrectly reused an old seed-cache entry")

print(string.format(
    "aura_menu_default_seed_cache_smoke: ok first=%d cached=%d replacement=%d",
    firstSeedPairs, cachedReadPairs, pairCalls))
