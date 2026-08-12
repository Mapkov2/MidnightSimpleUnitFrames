local function readFile(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local function has(text, literal)
    return text:find(literal, 1, true) ~= nil
end

local MSUF = { MSUF_Auras3 = {} }
_G.MSUF_NS = MSUF
assert(loadfile("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_DefensiveData.lua"))("MidnightSimpleUnitFrames", MSUF)
local A3 = assert(MSUF.MSUF_Auras3)
assert(loadfile("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Menu_Model.lua"))("MidnightSimpleUnitFrames", MSUF)
local groupAuraFilter = assert(_G.MSUF_GF_AuraFilter)
assert(groupAuraFilter.NormalizeFilterToken("buff", "BigDefensive") == "BigDefensive"
    and groupAuraFilter.NormalizeFilterToken("debuff", "CROWD_CONTROL") == "CROWD_CONTROL",
    "current Group Aura filters were not preserved")
for _, token in ipairs({ "IMPORTANT", "Cancelable", "NotCancelablePlayer", "INCLUDE_NAME_PLATE_ONLY", "unknown" }) do
    assert(groupAuraFilter.NormalizeFilterToken("buff", token) == "ALL",
        "retired Group Buff filter was not reset: " .. token)
end
for _, token in ipairs({ "IMPORTANT", "RaidPlayer", "RaidInCombatPlayer", "INCLUDE_NAME_PLATE_ONLY", "unknown" }) do
    assert(groupAuraFilter.NormalizeFilterToken("debuff", token) == "ALL",
        "retired Group Debuff filter was not reset: " .. token)
end
assert(groupAuraFilter.ResolveBuffFilter("IMPORTANT") == "HELPFUL"
    and groupAuraFilter.ResolveDebuffFilter("RaidPlayer") == "HARMFUL",
    "runtime still executes retired Group Aura filters")
local hash, signature = A3.GetBigDefensiveSpellIDHash()
local sameHash, sameSignature = A3.GetBigDefensiveSpellIDHash()
assert(hash == sameHash, "Big Defensive hash should be cached")
assert(signature == sameSignature and signature:find("^bigDefensive:"), "Big Defensive signature should be stable")
assert(A3.BigDefensiveDataVersion == "EUI-8.8.3+12.1.0.69189", "unexpected curated-data baseline")

local required = {
    48707, 444741, 101568, 212800, 207771, 1261872, 404381, 374349,
    1309793, 115203, 120954, 1241059, 498, 403876, 27827, 132413,
    190456, 1277297, 385391, 871,
}
for i = 1, #required do
    assert(hash[required[i]] == true, "missing curated defensive Spell ID " .. tostring(required[i]))
end

local intentionallyExcluded = {
    49039, 442715, 1266616, 427912, 209426, 192081, 393903, 472708,
    235313, 11426, 235450, 432180, 184662, 114216, 45242, 202147,
}
for i = 1, #intentionallyExcluded do
    assert(hash[intentionallyExcluded[i]] ~= true, "disabled/noisy EUI entry leaked into curated list: " .. tostring(intentionallyExcluded[i]))
end

local runtime = readFile("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua")
assert(has(runtime, "ConfigureCuratedBigDefensiveLane(lane)"), "runtime does not compile curated Big Defensive lanes")
assert(has(runtime, "SyncCuratedBigDefensiveContainer(container)"), "identity refresh does not switch safe Big Defensive variants")
assert(has(runtime, "if playerScoped then filter = filter .. \"|PLAYER\" end"), "Player modifier is not explicit")
assert(not has(runtime, "elseif nonPlayerScoped then"), "classification filters still inject implicit !PLAYER")
assert(has(runtime, "if broadening and candidatesChanged then"), "friendly transition is not fail-closed")

local blockStart = assert(runtime:find("local function RemoveNativeFilterToken", 1, true))
local blockStop = assert(runtime:find("local function FinalizeLane", blockStart, true))
local block = runtime:sub(blockStart, blockStop - 1)
local loader = loadstring or load
local chunk, loadError = loader([[
local A3, NormalizeNativeFilterString, issecretvalue = ...
local table_concat = table.concat
]] .. block .. [[
return ConfigureCuratedBigDefensiveLane, EffectiveLaneFilters
]], "@big_defensive_runtime")
assert(chunk, loadError)
local runtimeA3 = {
    GetBigDefensiveSpellIDHash = function()
        return { [48707] = true, [444741] = true }, "bigDefensive:48707,444741"
    end,
}
local function normalize(filter) return filter end
local function secret(value) return type(value) == "table" and value.secret == true end
local configure, effective = chunk(runtimeA3, normalize, secret)
local lane = configure({
    unit = "player",
    nativeFilter = "HELPFUL|BIG_DEFENSIVE|PLAYER",
    candidateFilters = { excludeSpellIDs = { [123] = true } },
    candidateFilterSignature = "excludeSpellIDs:123",
})
local native, candidates, candidateSignature = effective(lane)
assert(native == "HELPFUL|PLAYER", "friendly curated filter did not remove BIG_DEFENSIVE")
assert(candidates.includeSpellIDs[48707] and candidates.excludeSpellIDs[123], "curated include list did not preserve blacklist")
assert(has(candidateSignature, "bigDefensive:48707,444741"), "curated signature missing")
lane.unit = "party1"
assert((effective(lane)) == "HELPFUL|PLAYER", "Party should always use curated IDs")
lane.unit = "boss1"
assert((effective(lane)) == "HELPFUL|BIG_DEFENSIVE|PLAYER", "Boss should use the secret-safe native fallback")
lane.unit = "target"
_G.UnitCanAssist = function() return true end
assert((effective(lane)) == "HELPFUL|PLAYER", "friendly Target should use curated IDs")
_G.UnitCanAssist = function() return false end
assert((effective(lane)) == "HELPFUL|BIG_DEFENSIVE|PLAYER", "hostile Target should use native fallback")
_G.UnitCanAssist = function() return { secret = true } end
assert((effective(lane)) == "HELPFUL|BIG_DEFENSIVE|PLAYER", "secret Target disposition should fail closed")

local model = readFile("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Menu_Model.lua")
assert(has(model, "BIGDEFENSIVE = \"BIG_DEFENSIVE\","), "Group Big Defensive still excludes player-cast auras")
assert(has(model, "RAIDINCOMBAT = \"RAID_IN_COMBAT\","), "Group Raid In Combat still excludes player-cast auras")
assert(has(model, "GF_AURA_FILTER.NormalizeFilterToken = NormalizeGFStoredFilterToken"),
    "Group filter-token migration contract is missing")
local nativeFilterStart = assert(model:find("local GF_NATIVE_BUFF_FILTERS", 1, true))
local nativeFilterStop = assert(model:find("local function ResolveGFNativeFilter", nativeFilterStart, true))
local nativeFilters = model:sub(nativeFilterStart, nativeFilterStop - 1)
assert(not has(nativeFilters, "IMPORTANT")
    and not has(nativeFilters, "CANCELABLE")
    and not has(nativeFilters, "INCLUDENAMEPLATEONLY")
    and not has(nativeFilters, "RAIDINCOMBATPLAYER"),
    "retired Group filters remain executable in the native resolver")
local buffItems = assert(model:match("GF_AURA_FILTER%.BUFF_FILTER_ITEMS = {(.-)}%s*GF_AURA_FILTER%.DEBUFF_FILTER_ITEMS"))
local debuffItems = assert(model:match("GF_AURA_FILTER%.DEBUFF_FILTER_ITEMS = {(.-)}%s*local function GFNativeFilterKey"))
assert(not has(buffItems, "CancelablePlayer") and not has(buffItems, "IMPORTANT"), "obsolete Group Buff choices remain visible")
assert(not has(debuffItems, "INCLUDE_NAME_PLATE_ONLY") and not has(debuffItems, "IMPORTANT"), "modifier/no-op Group Debuff choices remain visible")

local profiles = readFile("MidnightSimpleUnitFrames/State/MSUF_Profiles.lua")
assert(has(profiles, "MSUF_PROFILEIO_CURRENT_NORMALIZATION_REVISION = 21")
    and has(profiles, "MSUF_ProfileIO_NormalizeGFAuraFilterTokens(profile, false)")
    and has(profiles, "MSUF_ProfileIO_NormalizeGFAuraFilterTokens(profile, true)"),
    "stored/imported profiles do not repair retired Group filter tokens")
local groupDB = readFile("MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua")
assert(has(groupDB, "g.filterToken = normalize(gk, g.filterToken)"),
    "active Group DB cold repair does not normalize retired filter tokens")

local assistantData = readFile("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_Auras_Data.lua")
local groupValues = assert(assistantData:match("Data%.GF_AURA_FILTER_VALUES = {(.-)}%s*Data%.GF_AURA_FILTER_ALIASES"))
assert(not has(groupValues, "CancelablePlayer") and not has(groupValues, "INCLUDE_NAME_PLATE_ONLY"), "Assistant still exposes removed Group choices")

print("aura_big_defensive_filter_smoke: ok")
