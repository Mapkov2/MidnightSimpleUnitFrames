_G = _G or _ENV

dofile("tools/assistant_dashboard_smoke.lua")
local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant runtime missing")
local P = assert(A.Parser, "Assistant parser missing")
local settings = assert(A.Registry):AllSettings()
local actions = A.Registry:AllActions()

local function token(index)
    local chars = { "a", "a", "a", "a" }
    for at = #chars, 1, -1 do
        chars[at] = string.char(97 + (index % 26))
        index = math.floor(index / 26)
    end
    return "a" .. table.concat(chars)
end

for i = 1, 5000 do
    local value = token(i)
    P.RegistryCandidateSettings(value, settings, true)
    P.RegistryActionAliasCandidates(actions, value, true)
end

local function count(map)
    local total = 0
    for _ in pairs(map or {}) do total = total + 1 end
    return total
end

local function upvalue(fn, wanted)
    for index = 1, 64 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then return value, index end
    end
    error("missing upvalue " .. tostring(wanted))
end

local function resetUpvalue(fn, wanted, value)
    local _, index = upvalue(fn, wanted)
    assert(debug.setupvalue(fn, index, value) == wanted, "failed to reset " .. wanted)
end

local registryCount = count(P._registryCandidateFuzzyTokenCache)
local actionIndex = P._registryActionAliasIndex or {}
local actionCount = count(actionIndex.fuzzyTokenCache)
assert(registryCount <= 2048, "registry fuzzy cache exceeded bound: " .. tostring(registryCount))
assert(actionCount <= 1024, "action fuzzy cache exceeded bound: " .. tostring(actionCount))

-- Score-cache eviction used to shift all 4,096 order entries for every new
-- score once full. Verify the O(1) head queue remains bounded and evicts FIFO.
P.ClearSettingMatchScoreCache()
for i = 1, 6000 do
    P.SettingMatchScoreCachePut({ key = "cache.setting." .. tostring(i) }, "same prompt", i)
end
local matchCount = count(P._settingMatchScoreCache)
local matchHead = tonumber(P._settingMatchScoreCacheHead) or 1
local matchOrder = P._settingMatchScoreCacheOrder or {}
assert(matchCount <= 4096, "setting match-score cache exceeded bound: " .. tostring(matchCount))
assert(#matchOrder - matchHead + 1 <= 4096, "setting match-score order exceeded active bound")
assert(P.SettingMatchScoreCacheGet({ key = "cache.setting.1" }, "same prompt") == nil,
    "setting match-score cache did not evict its oldest entry")
assert(P.SettingMatchScoreCacheGet({ key = "cache.setting.6000" }, "same prompt") == 6000,
    "setting match-score cache lost its newest entry")

-- The two generational caches must count cold-generation promotions. Without
-- this check, repeatedly touching the cold generation can grow the hot table
-- beyond the nominal 8,192-entry window on every generation swap.
local cacheNormalize = upvalue(P.Normalize, "CacheNormalize")
resetUpvalue(P.Normalize, "normalizeCacheHot", {})
resetUpvalue(P.Normalize, "normalizeCacheCold", {})
resetUpvalue(cacheNormalize, "normalizeCacheHotCount", 0)
for i = 1, 8300 do P.Normalize("normalize " .. token(i)) end
for i = 1, 8192 do P.Normalize("normalize " .. token(i)) end
local normalizeHot = upvalue(P.Normalize, "normalizeCacheHot")
local normalizeCold = upvalue(P.Normalize, "normalizeCacheCold")
assert(count(normalizeHot) <= 8192 and count(normalizeCold) <= 8192,
    string.format("normalize generations exceeded bounds hot=%d cold=%d", count(normalizeHot), count(normalizeCold)))

local candidateTokens = upvalue(P._AddCandidateIndexTokens, "CandidateIndexTokens")
local cacheCandidateTokens = upvalue(candidateTokens, "CacheCandidateIndexTokens")
resetUpvalue(candidateTokens, "candidateIndexTokenCacheHot", {})
resetUpvalue(candidateTokens, "candidateIndexTokenCacheCold", {})
resetUpvalue(cacheCandidateTokens, "candidateIndexTokenCacheHotCount", 0)
for i = 1, 8300 do P._AddCandidateIndexTokens({}, "candidate " .. token(i)) end
for i = 1, 8192 do P._AddCandidateIndexTokens({}, "candidate " .. token(i)) end
local candidateHot = upvalue(candidateTokens, "candidateIndexTokenCacheHot")
local candidateCold = upvalue(candidateTokens, "candidateIndexTokenCacheCold")
assert(count(candidateHot) <= 8192 and count(candidateCold) <= 8192,
    string.format("candidate-token generations exceeded bounds hot=%d cold=%d", count(candidateHot), count(candidateCold)))

-- The phrase-token cache uses the same head/compaction shape. Exercise enough
-- unique phrases to cross the bound and one full compaction threshold.
local cachedFuzzyTokens = upvalue(P.FuzzyPhraseMatch, "CachedFuzzyPhraseTokens")
resetUpvalue(cachedFuzzyTokens, "fuzzyPhraseTokenCache", {})
resetUpvalue(cachedFuzzyTokens, "fuzzyPhraseTokenCacheOrder", {})
resetUpvalue(cachedFuzzyTokens, "fuzzyPhraseTokenCacheHead", 1)
for i = 1, 9000 do P.FuzzyPhraseMatch("zzzzzz", "phrase " .. token(i)) end
local fuzzyPhraseCache = upvalue(cachedFuzzyTokens, "fuzzyPhraseTokenCache")
local fuzzyPhraseOrder = upvalue(cachedFuzzyTokens, "fuzzyPhraseTokenCacheOrder")
local fuzzyPhraseHead = upvalue(cachedFuzzyTokens, "fuzzyPhraseTokenCacheHead")
assert(count(fuzzyPhraseCache) <= 4096, "phrase-token cache exceeded bound")
assert(#fuzzyPhraseOrder - fuzzyPhraseHead + 1 <= 4096, "phrase-token order exceeded active bound")

A.SetMenuRuntimeActive(false, "fuzzy-cache-smoke")
assert(count(P._registryCandidateFuzzyTokenCache) == 0, "registry fuzzy cache survived menu close")
assert(count((P._registryActionAliasIndex or {}).fuzzyTokenCache) == 0, "action fuzzy cache survived menu close")
assert(count(P._settingMatchScoreCache) <= 4096,
    "bounded setting match-score cache grew during menu shutdown")
P.ClearSettingMatchScoreCache()
assert(count(P._settingMatchScoreCache) == 0 and tonumber(P._settingMatchScoreCacheHead) == 1,
    "setting match-score cache clear contract failed")

print(("assistant_fuzzy_cache_bounds_smoke: ok registry=%d action=%d match=%d normalize=%d/%d candidate=%d/%d phrase=%d")
    :format(registryCount, actionCount, matchCount, count(normalizeHot), count(normalizeCold),
        count(candidateHot), count(candidateCold), count(fuzzyPhraseCache)))
