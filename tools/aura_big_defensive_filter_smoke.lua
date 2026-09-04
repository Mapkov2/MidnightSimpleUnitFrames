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
assert(loadfile("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_GroupHighlightsData.lua"))("MidnightSimpleUnitFrames", MSUF)
assert(loadfile("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators.lua"))("MidnightSimpleUnitFrames", MSUF)
local spellRuntime = assert(A3.SpellIndicators)
assert(loadfile("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Menu_Model.lua"))("MidnightSimpleUnitFrames", MSUF)
local groupAuraFilter = assert(_G.MSUF_GF_AuraFilter)
assert(groupAuraFilter.NormalizeFilterToken("buff", "BigDefensive") == "BigDefensive"
    and groupAuraFilter.NormalizeFilterToken("buff", "MSUF_GROUP_HIGHLIGHTS_V1") == "MSUF_GROUP_HIGHLIGHTS_V1"
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
local highlights, highlightsSignature, highlightsCount = A3.GetGroupHighlightsSpellIDHash()
local sameHighlights, sameHighlightsSignature, sameHighlightsCount = A3.GetGroupHighlightsSpellIDHash()
assert(highlights == sameHighlights
    and highlightsSignature == sameHighlightsSignature
    and highlightsCount == sameHighlightsCount,
    "Group Highlights catalog should be shared and stable")
assert(highlightsCount == 122 and highlightsSignature:find("^groupHighlights:12%.1%.0%.69497%-v1:122$"),
    "unexpected Group Highlights data baseline")
for _, spellID in ipairs({ 48707, 212800, 22812, 363534, 190319, 10060, 871, 81782, 185422, 114018, 115834 }) do
    assert(highlights[spellID] == true, "missing Group Highlights Spell ID " .. tostring(spellID))
end
for _, spellID in ipairs({ 1784, 5215, 5217, 188501, 199261, 377362, 389794 }) do
    assert(highlights[spellID] == nil, "noisy aura leaked into Group Highlights: " .. tostring(spellID))
end
local resolvedHighlights, resolvedHighlightsSignature, resolvedHighlightsCount =
    groupAuraFilter.ResolveBuffIncludeHash("MSUF_GROUP_HIGHLIGHTS_V1")
assert(resolvedHighlights == highlights
    and resolvedHighlightsSignature == highlightsSignature
    and resolvedHighlightsCount == 122,
    "Group Highlights resolver copied or changed the shared catalog")
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
local requiredContainerStart = assert(runtime:find("local NATIVE_AURA_CONTAINER_METHODS = {", 1, true))
local requiredButtonStart = assert(runtime:find("local NATIVE_AURA_BUTTON_METHODS = {", requiredContainerStart, true))
local requiredContractStop = assert(runtime:find("local function ValidateNativeAuraContainerContract", requiredButtonStart, true))
local requiredContainerMethods = runtime:sub(requiredContainerStart, requiredButtonStart - 1)
local requiredButtonMethods = runtime:sub(requiredButtonStart, requiredContractStop - 1)
for _, methodName in ipairs({
    "SetEditModePreviewEnabled", "SetAuraGroupEnabled", "SetAuraSlotEnabled", "SetItemEnchantmentEnabled",
}) do
    assert(not has(requiredContainerMethods, '"' .. methodName .. '"'),
        "Retail 12.1 AuraContainer contract requires later method " .. methodName)
end
for _, methodName in ipairs({
    "SetCasterName", "ClearCasterName", "AddPandemicEnterAnimation",
    "AddPandemicActiveAnimation", "AddPandemicLeaveAnimation",
}) do
    assert(not has(requiredButtonMethods, '"' .. methodName .. '"'),
        "Retail 12.1 AuraButton contract requires later method " .. methodName)
end
assert(has(runtime, 'if type(container.SetEditModePreviewEnabled) == "function" then'),
    "later Edit Mode preview API is not capability-gated")
local spellIndicatorSource = readFile("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators.lua")
assert(has(spellIndicatorSource, 'and type(button.AddPandemicActiveAnimation) == "function"'),
    "later Pandemic animation API is not capability-gated")
assert(has(runtime, "ConfigureCuratedBigDefensiveLane(lane)"), "runtime does not compile curated Big Defensive lanes")
assert(has(runtime, "SyncCuratedBigDefensiveContainer(container)"), "identity refresh does not switch safe Big Defensive variants")
assert(has(runtime, "if playerScoped then filter = filter .. \"|PLAYER\" end"), "Player modifier is not explicit")
assert(not has(runtime, "elseif nonPlayerScoped then"), "classification filters still inject implicit !PLAYER")
assert(has(runtime, "local installCandidatesFirst = filterChanged and candidatesChanged")
    and has(runtime, "candidateFilters and candidateFilters.includeSpellIDs ~= nil")
    and has(runtime, "if installCandidatesFirst then"),
    "exact-ID transition is not fail-closed")
assert(not has(runtime, "container:UnregisterEvent(\"AURA_DATA_PROVIDER_SWITCH\")"),
    "CustomAuraContainer event registrations must remain Blizzard-owned")
assert(has(runtime, "A3._DirectIdentityRefreshUnitWithUnitAuraGate")
    and has(runtime, "A3._DirectIdentityRefreshUnit = A3._DirectIdentityRefreshUnitBase"),
    "ordinary Unit exact-ID owners do not topology-switch the direct identity route")
assert(has(runtime, 'identityCandidateMode = helpful and "assist" or "hostile"'),
    "ordinary Unit custom exact-ID lanes lack compiled polarity metadata")
assert(has(runtime, 'type(_G.UnitIsPlayerControlledOrGroupMember) ~= "function"'),
    "Group HELPFUL exact-ID lanes retained the obsolete party assist gate")
assert(has(runtime, 'return unitCanAssist("player", unit, true, true)')
    and has(runtime, 'return unitCanAssist("player", unit)'),
    "identity candidate checks do not select the Retail/Classic UnitCanAssist contract")
local refreshAllStart = assert(runtime:find("A3._DoRefreshAll = function()", 1, true))
local refreshAllStop = assert(runtime:find("A3._FlushCoalescedRefreshAll = function()", refreshAllStart, true))
local refreshAllBody = runtime:sub(refreshAllStart, refreshAllStop - 1)
local beginTopology = assert(refreshAllBody:find("A3._BeginDirectIdentityEventTopologyBatch()", 1, true))
local applyAll = assert(refreshAllBody:find('A3._RequestUnitNow("*")', 1, true))
local endTopology = assert(refreshAllBody:find("A3._EndDirectIdentityEventTopologyBatch()", 1, true))
assert(beginTopology < applyAll and applyAll < endTopology,
    "full Aura refresh does not batch identity-event topology")
local flushStop = assert(runtime:find("function A3._FlushDeferredAuraRuntime()", refreshAllStop, true))
local flushBody = runtime:sub(refreshAllStop, flushStop - 1)
assert(has(flushBody, "DrainDirectIdentityEventTopologyBatch()")
    and has(flushBody, "A3._refreshAllIncomplete == true")
    and has(flushBody, "return A3.RefreshAll()"),
    "aborted Aura refresh cannot unwind and retry on the next frame")
assert(not has(flushBody, "directIdentityEventTopologyBatchDepth"),
    "refresh recovery reads the NativeRuntime-private topology depth")
assert(has(runtime, "DrainDirectIdentityEventTopologyBatch = DrainDirectIdentityEventTopologyBatch"),
    "NativeRuntime does not export its topology recovery helper")
assert(has(runtime, "local DrainDirectIdentityEventTopologyBatch = NativeRuntime.DrainDirectIdentityEventTopologyBatch"),
    "public Aura orchestration does not retain the topology recovery helper")
local topologyStart = assert(runtime:find("local directIdentityRefreshEventFrame", 1, true))
local topologyStop = assert(runtime:find("local function DirectIdentityRefreshEventsAlreadyCover", topologyStart, true))
local topologyBlock = runtime:sub(topologyStart, topologyStop - 1)
local topologyLoader = loadstring or load
local topologyChunk, topologyLoadError = topologyLoader([[
local A3 = {}
]] .. topologyBlock .. [[
return A3._BeginDirectIdentityEventTopologyBatch,
    A3._EndDirectIdentityEventTopologyBatch,
    DrainDirectIdentityEventTopologyBatch
]], "@aura_topology_recovery")
assert(topologyChunk, topologyLoadError)
local beginBatch, endBatch, drainBatch = topologyChunk()
assert(beginBatch() == 1 and beginBatch() == 2, "topology batch depth did not increment")
assert(drainBatch() == true, "topology recovery did not drain an interrupted batch")
assert(endBatch() == false and drainBatch() == false,
    "topology recovery left a stale batch depth")
local publicRefreshStart = assert(runtime:find("function A3.RefreshAll()", refreshAllStop, true))
local publicRefreshStop = assert(runtime:find("function A3.RefreshRoundedDispelOverlayMasks()", publicRefreshStart, true))
local publicRefreshBody = runtime:sub(publicRefreshStart, publicRefreshStop - 1)
local scheduleUnlock = publicRefreshBody:find("RunNextFrame(A3._FlushCoalescedRefreshAll)", 1, true)
local runRefresh = publicRefreshBody:find("A3._DoRefreshAll()", 1, true)
assert(scheduleUnlock and runRefresh and scheduleUnlock < runRefresh,
    "Aura RefreshAll does not arm its coalescing unlock before synchronous work")
assert(has(publicRefreshBody, "A3._refreshAllIncomplete = true")
    and has(publicRefreshBody, "A3._refreshAllIncomplete = nil"),
    "Aura RefreshAll does not expose an interrupted pass to its unlock callback")

local mixedRoot = assert(spellRuntime.CompileSlots("target", {
    enabled = true,
    items = {
        { enabled = true, key = "neutral", nativeFilter = "HELPFUL", allowAnyAura = true,
            placed = { type = "icon" } },
        { enabled = true, key = "assist", nativeFilter = "HELPFUL",
            includeSpellIDs = { [9001] = true }, placed = { type = "icon" } },
        { enabled = true, key = "hostile", nativeFilter = "HARMFUL",
            includeSpellIDs = { [9002] = true }, placed = { type = "icon" } },
    },
}))
local unitPrimary, unitAssist, unitHostile = spellRuntime.PartitionUnitRoot(mixedRoot)
assert(unitPrimary and unitPrimary.rootKey == "SpellIndicators" and #unitPrimary.slots == 1,
    "neutral Unit indicators did not retain the historical owner key")
assert(unitAssist and unitAssist.rootKey == "SpellIndicatorsAssist"
    and unitAssist.identityCandidateMode == "assist",
    "HELPFUL exact-ID Unit indicators were not isolated")
assert(unitHostile and unitHostile.rootKey == "SpellIndicatorsHostile"
    and unitHostile.identityCandidateMode == "hostile",
    "HARMFUL exact-ID Unit indicators were not isolated")

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
_G.UnitIsPlayerControlledOrGroupMember = function() return true end
_G.UnitCanAssist = function(source, unit, canAssistImmune, canAssistUninteractable)
    assert(source == "player" and unit == "target"
        and canAssistImmune == true and canAssistUninteractable == true,
        "friendly Target used the old UnitCanAssist contract")
    return true
end
assert((effective(lane)) == "HELPFUL|PLAYER", "friendly Target should use curated IDs")
_G.UnitCanAssist = function(source, unit, canAssistImmune, canAssistUninteractable)
    assert(source == "player" and unit == "target"
        and canAssistImmune == true and canAssistUninteractable == true,
        "hostile Target used the old UnitCanAssist contract")
    return false
end
assert((effective(lane)) == "HELPFUL|BIG_DEFENSIVE|PLAYER", "hostile Target should use native fallback")
_G.UnitCanAssist = function(source, unit, canAssistImmune, canAssistUninteractable)
    assert(source == "player" and unit == "target"
        and canAssistImmune == true and canAssistUninteractable == true,
        "secret Target used the old UnitCanAssist contract")
    return { secret = true }
end
assert((effective(lane)) == "HELPFUL|BIG_DEFENSIVE|PLAYER", "secret Target disposition should fail closed")
_G.UnitIsPlayerControlledOrGroupMember = nil
_G.UnitCanAssist = function(...)
    assert(select("#", ...) == 2, "legacy Target used Retail UnitCanAssist arguments")
    local source, unit = ...
    assert(source == "player" and unit == "target", "legacy Target used the wrong assist identity")
    return true
end
assert((effective(lane)) == "HELPFUL|PLAYER", "legacy friendly Target should use the two-argument API")

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
assert(has(buffItems, "overrides duration filters"),
    "Group Highlights tooltip does not explain its durationless-state policy")

local groupConfig = readFile("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua")
assert(has(groupConfig, "out.buffIncludeHash, out.buffIncludeSignature, allowDurationless = AuraIncludeHash")
    and has(groupConfig, "if allowDurationless then")
    and has(groupConfig, 'out[prefix .. "HidePermanent"] = false')
    and has(groupConfig, 'out[prefix .. "MaxDuration"] = 0'),
    "Group Highlights can still inherit generic duration candidate filters")

local profiles = readFile("MidnightSimpleUnitFrames/State/MSUF_Profiles.lua")
assert(has(profiles, "MSUF_PROFILEIO_CURRENT_NORMALIZATION_REVISION = 21")
    and has(profiles, "MSUF_ProfileIO_NormalizeGFAuraFilterTokens(profile, false)")
    and has(profiles, "MSUF_ProfileIO_NormalizeGFAuraFilterTokens(profile, true)"),
    "stored/imported profiles do not repair retired Group filter tokens")
local groupDB = readFile("MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua")
assert(has(groupDB, "g.filterToken = normalize(gk, g.filterToken)"),
    "active Group DB cold repair does not normalize retired filter tokens")
assert(has(groupDB, "local state = createCanonical(true)")
    and has(profiles, '"canonical Group Aura reset", createCanonical, true'),
    "existing-profile repair can inherit new factory-only Group Aura defaults")

local assistantData = readFile("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_Auras_Data.lua")
local groupValues = assert(assistantData:match("Data%.GF_AURA_FILTER_VALUES = {(.-)}%s*Data%.GF_AURA_FILTER_ALIASES"))
assert(not has(groupValues, "CancelablePlayer") and not has(groupValues, "INCLUDE_NAME_PLATE_ONLY"), "Assistant still exposes removed Group choices")

print("aura_big_defensive_filter_smoke: ok")
