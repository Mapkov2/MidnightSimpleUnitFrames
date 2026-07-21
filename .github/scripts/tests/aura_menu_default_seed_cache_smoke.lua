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
