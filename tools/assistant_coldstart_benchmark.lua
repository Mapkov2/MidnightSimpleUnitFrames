_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local function elapsedMs(started)
    return (os.clock() - started) * 1000
end

local function collectKb()
    collectgarbage("collect")
    collectgarbage("collect")
    return collectgarbage("count")
end

local function initRuntime()
    local MSUF = { MSUF2 = {} }
    _G.MSUF_NS = MSUF
    _G.MSUF2 = MSUF.MSUF2
    _G.MSUF_DB = {
        general = {}, bars = {}, gameplay = {}, player = {}, target = {}, focus = {}, pet = {},
        units = { player = {}, target = {}, focus = {}, pet = {} },
        groups = { party = {}, raid = {}, mythicraid = {} },
    }

    local loaderPath = exists("tools/assistant_runtime_manifest_loader.lua")
        and "tools/assistant_runtime_manifest_loader.lua"
        or "../tools/assistant_runtime_manifest_loader.lua"
    local RuntimeManifest = dofile(loaderPath)
    local beforeKb = collectKb()
    local started = os.clock()
    local loaded = RuntimeManifest.LoadAssistantRuntime(MSUF)
    local loadMs = elapsedMs(started)
    local retainedKb = collectKb() - beforeKb
    local A = assert(MSUF.Assistant, "Assistant namespace missing")
    A.GetContext = A.GetContext or function() return {} end
    return MSUF, A, loaded, loadMs, retainedKb
end

local function normalize(value)
    value = tostring(value or ""):lower()
    value = value:gsub("\195\164", "ae"):gsub("\195\182", "oe"):gsub("\195\188", "ue"):gsub("\195\159", "ss")
    value = value:gsub("[^%w_]+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return value
end

local function registryStats(A)
    local settings = assert(A.Registry and A.Registry:AllSettings(), "Assistant settings missing")
    local normalizeAlias = type(A.Normalize) == "function" and A.Normalize or normalize
    local aliases, exactAliases, duplicateExact, oneTokenExact, maxRefs = 0, 0, 0, 0, 0
    for i = 1, #settings do
        local setting = settings[i]
        local normalSeen = {}
        for j = 1, #(setting.aliases or {}) do
            aliases = aliases + 1
            normalSeen[normalizeAlias(setting.aliases[j])] = true
        end
        for j = 1, #(setting.exactAliases or {}) do
            local norm = normalizeAlias(setting.exactAliases[j])
            exactAliases = exactAliases + 1
            if normalSeen[norm] then duplicateExact = duplicateExact + 1 end
            if norm ~= "" and not norm:find(" ", 1, true) then oneTokenExact = oneTokenExact + 1 end
        end
        maxRefs = math.max(maxRefs, #(setting.aliases or {}) + #(setting.exactAliases or {}))
    end
    return #settings, aliases, exactAliases, duplicateExact, oneTokenExact, maxRefs
end

local function stableValue(value, seen)
    local kind = type(value)
    if kind ~= "table" then return kind .. ":" .. tostring(value) end
    seen = seen or {}
    if seen[value] then return "cycle" end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = { "{" }
    for i = 1, #keys do
        local key = keys[i]
        parts[#parts + 1] = stableValue(key, seen) .. "=" .. stableValue(value[key], seen)
    end
    parts[#parts + 1] = "}"
    seen[value] = nil
    return table.concat(parts, "\031")
end

local MSUF, A, loaded, loadMs, retainedKb = initRuntime()
local settings, aliases, exactAliases, duplicateExact, oneTokenExact, maxRefs = registryStats(A)
io.write(string.format(
    "runtime load_ms=%.3f retained_kb=%.1f scripts=%d settings=%d aliases=%d exact=%d refs=%d duplicate_exact=%d one_token_exact=%d max_refs=%d\n",
    loadMs, retainedKb, #loaded, settings, aliases, exactAliases, aliases + exactAliases,
    duplicateExact, oneTokenExact, maxRefs
))

local mode = tostring(arg and arg[1] or "runtime")
if mode == "aliases" then
    local allSettings = A.Registry:AllSettings()
    local normalizeAlias = type(A.Normalize) == "function" and A.Normalize or normalize
    local registryNormalizeAlias = A.RegistryCore and A.RegistryCore.NormalizeSettingAlias
    local duplicateCount, exactOneTokens = 0, {}
    local normalizationMismatches, mismatchExamples = 0, {}
    local tokenMismatches = {}
    local preparedMismatches, flaggedEntries, flaggedSettings = 0, 0, 0
    local function maskHas(mask, index)
        if type(mask) ~= "number" then return false end
        local bit = 2 ^ (index - 1)
        return (mask % (bit * 2)) >= bit
    end
    local function inspectTokens(alias)
        if type(registryNormalizeAlias) ~= "function" then return end
        for token in tostring(alias or ""):lower():gmatch("%S+") do
            local registryNorm = registryNormalizeAlias(token)
            local parserNorm = normalizeAlias(token)
            if registryNorm ~= parserNorm then tokenMismatches[token] = parserNorm end
        end
    end
    for i = 1, #allSettings do
        local setting = allSettings[i]
        local aliasNormMask = setting._assistantAliasNormMask
        local exactAliasNormMask = setting._assistantExactAliasNormMask
        if type(aliasNormMask) == "number" then flaggedSettings = flaggedSettings + 1 end
        if type(exactAliasNormMask) == "number" then flaggedSettings = flaggedSettings + 1 end
        local normalSeen = {}
        for j = 1, #(setting.aliases or {}) do
            local alias = setting.aliases[j]
            local flagged = maskHas(aliasNormMask, j)
            local prepared = flagged and normalizeAlias(alias) or alias
            if flagged then flaggedEntries = flaggedEntries + 1 end
            if setting._assistantAliasNormVersion ~= 2 or prepared ~= normalizeAlias(alias) then
                preparedMismatches = preparedMismatches + 1
            end
            inspectTokens(alias)
            normalSeen[normalizeAlias(alias)] = true
            if type(registryNormalizeAlias) == "function" and registryNormalizeAlias(alias) ~= normalizeAlias(alias) then
                normalizationMismatches = normalizationMismatches + 1
                if #mismatchExamples < 12 then
                    mismatchExamples[#mismatchExamples + 1] = tostring(alias) .. " => "
                        .. tostring(registryNormalizeAlias(alias)) .. " <> " .. tostring(normalizeAlias(alias))
                end
            end
        end
        for j = 1, #(setting.exactAliases or {}) do
            local alias = setting.exactAliases[j]
            local flagged = maskHas(exactAliasNormMask, j)
            local prepared = flagged and normalizeAlias(alias) or alias
            if flagged then flaggedEntries = flaggedEntries + 1 end
            if setting._assistantAliasNormVersion ~= 2 or prepared ~= normalizeAlias(alias) then
                preparedMismatches = preparedMismatches + 1
            end
            inspectTokens(alias)
            local norm = normalizeAlias(alias)
            if type(registryNormalizeAlias) == "function" and registryNormalizeAlias(alias) ~= norm then
                normalizationMismatches = normalizationMismatches + 1
                if #mismatchExamples < 12 then
                    mismatchExamples[#mismatchExamples + 1] = tostring(alias) .. " => "
                        .. tostring(registryNormalizeAlias(alias)) .. " <> " .. tostring(norm)
                end
            end
            if normalSeen[norm] and norm:find(" ", 1, true) then duplicateCount = duplicateCount + 1 end
            if norm ~= "" and not norm:find(" ", 1, true) then exactOneTokens[norm] = true end
            if normalSeen[norm] or (norm ~= "" and not norm:find(" ", 1, true)) then
                io.write(string.format(
                    "alias_detail key=%s duplicate=%s one_token=%s alias=%s norm=%s\n",
                    tostring(setting.key), tostring(normalSeen[norm] == true),
                    tostring(norm ~= "" and not norm:find(" ", 1, true)), tostring(alias), norm
                ))
            end
        end
    end
    assert(duplicateCount == 0, "normalized multiword exact aliases still duplicate normal aliases: " .. tostring(duplicateCount))
    assert(exactOneTokens.buffs and exactOneTokens.debuffs, "required exact one-word aura aliases were not retained")
    assert(maxRefs <= 48, "per-setting alias retention exceeds 16 normal + 32 exact extras: " .. tostring(maxRefs))
    assert(preparedMismatches == 0, "prepared alias normalization mismatch count: " .. tostring(preparedMismatches))
    io.write(string.format(
        "alias_normalization mismatches=%d examples=%s\n",
        normalizationMismatches, table.concat(mismatchExamples, " | ")
    ))
    local mismatchTokens = {}
    for token, replacement in pairs(tokenMismatches) do
        mismatchTokens[#mismatchTokens + 1] = token .. "=" .. replacement
    end
    table.sort(mismatchTokens)
    io.write("alias_token_normalization " .. table.concat(mismatchTokens, " | ") .. "\n")
    io.write(string.format(
        "prepared_aliases version=2 mismatches=%d flagged_entries=%d flagged_settings=%d\n",
        preparedMismatches, flaggedEntries, flaggedSettings
    ))
end

if mode == "indices" then
    local P = assert(A.Parser, "Assistant parser namespace missing")
    local allSettings = A.Registry:AllSettings()
    P._registryExactAliasSettings = nil
    P._registryExactAliasCount = nil
    P._registryExactAliasIndex = nil
    local beforeExactKb = collectKb()
    local exactStarted = os.clock()
    local exactIndex = assert(P._EnsureRegistryExactAliasIndex(allSettings), "Exact alias index missing")
    local exactMs = elapsedMs(exactStarted)
    local exactKb = collectKb() - beforeExactKb
    local exactPhrases, exactRefs = 0, 0
    for _, byPhrase in pairs(exactIndex.byLength or {}) do
        for _, bucket in pairs(byPhrase) do
            exactPhrases = exactPhrases + 1
            exactRefs = exactRefs + #bucket
        end
    end
    io.write(string.format(
        "exact_index build_ms=%.3f retained_kb=%.1f phrases=%d refs=%d max_tokens=%d\n",
        exactMs, exactKb, exactPhrases, exactRefs, tonumber(exactIndex.maxTokens) or 0
    ))

    P._registryCandidateIndexSettings = nil
    P._registryCandidateIndexCount = nil
    P._registryCandidateIndexFull = nil
    P._registryCandidateIndexByToken = nil
    P._registryCandidateIndexFuzzyBuckets = nil
    P._registryCandidateIndexAll = nil
    local beforeCandidateKb = collectKb()
    local candidateStarted = os.clock()
    P._EnsureRegistryCandidateIndex(allSettings, true)
    local candidateMs = elapsedMs(candidateStarted)
    local candidateKb = collectKb() - beforeCandidateKb
    local candidateTokens, candidateRefs = 0, 0
    for _, bucket in pairs(P._registryCandidateIndexByToken or {}) do
        candidateTokens = candidateTokens + 1
        candidateRefs = candidateRefs + #bucket
    end
    io.write(string.format(
        "candidate_index build_ms=%.3f retained_kb=%.1f tokens=%d refs=%d settings=%d\n",
        candidateMs, candidateKb, candidateTokens, candidateRefs,
        #(P._registryCandidateIndexAll or {})
    ))
end

if mode == "normalizers" then
    local allSettings = A.Registry:AllSettings()
    local registryNormalize = assert(A.RegistryCore and A.RegistryCore.NormalizeSettingAlias, "Registry alias normalizer missing")
    local aliases = {}
    for i = 1, #allSettings do
        local setting = allSettings[i]
        for j = 1, #(setting.aliases or {}) do aliases[#aliases + 1] = setting.aliases[j] end
        for j = 1, #(setting.exactAliases or {}) do aliases[#aliases + 1] = setting.exactAliases[j] end
    end
    local started = os.clock()
    local registryBytes = 0
    for i = 1, #aliases do registryBytes = registryBytes + #registryNormalize(aliases[i]) end
    local registryMs = elapsedMs(started)
    started = os.clock()
    local parserBytes = 0
    for i = 1, #aliases do parserBytes = parserBytes + #A.Normalize(aliases[i]) end
    local parserMs = elapsedMs(started)
    assert(registryBytes == parserBytes, "normalizer byte checksum mismatch")
    io.write(string.format(
        "normalizers refs=%d registry_ms=%.3f parser_ms=%.3f checksum=%d\n",
        #aliases, registryMs, parserMs, registryBytes
    ))
end

if mode == "knowledge_search" then
    local K = assert(A.Knowledge, "Knowledge namespace missing")
    K.MarkDirty()
    K.EnsureIndex()
    local queries = {
        "where can I turn off focus kick tracker?",
        "where do I make focus kick tracker bigger?",
        "where is focus kick tracker width",
        "focus kick tracker size",
        "focus kick tracker position",
        "focus kick tracker anchor",
    }
    for i = 1, #queries do
        local results = K.Search(queries[i], 8, { ignoreCurrentPage = true }) or {}
        io.write("knowledge_search query=" .. queries[i] .. "\n")
        for rank = 1, #results do
            local item = results[rank].item or {}
            io.write(string.format(
                "  rank=%d score=%.1f key=%s label=%s page=%s\n",
                rank, tonumber(results[rank].score) or 0, tostring(item.key),
                tostring(item.label), tostring(item.page)
            ))
        end
    end
end

if mode == "knowledge" or mode == "knowledge_profile" or mode == "all" then
    assert(A.Knowledge and type(A.Knowledge.EnsureIndex) == "function", "Knowledge index missing")
    local normalizeCalls, normalizeBytes = 0, 0
    if mode == "knowledge_profile" and type(A.Normalize) == "function" then
        local originalNormalize = A.Normalize
        A.Normalize = function(value)
            normalizeCalls = normalizeCalls + 1
            normalizeBytes = normalizeBytes + #(tostring(value or ""))
            return originalNormalize(value)
        end
    end
    A.Knowledge.MarkDirty()
    local beforeKb = collectKb()
    local started = os.clock()
    local index = A.Knowledge.EnsureIndex()
    local buildMs = elapsedMs(started)
    local retainedIndexKb = collectKb() - beforeKb
    local aliasNorms, haystackBytes = 0, 0
    for i = 1, #(index.items or {}) do
        aliasNorms = aliasNorms + #(index.items[i].aliasNorms or {})
        haystackBytes = haystackBytes + #(index.items[i].haystack or "")
    end
    io.write(string.format(
        "knowledge build_ms=%.3f retained_kb=%.1f items=%d alias_norms=%d haystack_bytes=%d\n",
        buildMs, retainedIndexKb, #(index.items or {}), aliasNorms, haystackBytes
    ))
    if mode == "knowledge_profile" then
        io.write(string.format("knowledge_profile normalize_calls=%d normalize_bytes=%d\n", normalizeCalls, normalizeBytes))
    end
end

if mode == "submit" or mode == "all" then
    local questions = {
        "what is target frame width",
        "where is raid ready check",
        "what depends on target buffs",
        "why is player power text hidden",
        "how do profiles work",
        "explain class resource width mode",
        "where can I change castbar texture",
        "why are party frames missing",
        "what are your limits",
        "answer in German what is aura filtering",
    }
    local beforeDb = stableValue(_G.MSUF_DB)
    local totalMs, maxMs = 0, 0
    for i = 1, #questions do
        local started = os.clock()
        local result = A.Submit(questions[i])
        local ms = elapsedMs(started)
        totalMs = totalMs + ms
        maxMs = math.max(maxMs, ms)
        io.write(string.format(
            "submit index=%d ms=%.3f status=%s text_bytes=%d question=%s\n",
            i, ms, tostring(result and (result.status or result.result) or "nil"),
            #(tostring(result and result.text or "")), questions[i]
        ))
    end
    io.write(string.format(
        "submit_summary avg_ms=%.3f max_ms=%.3f db_unchanged=%s\n",
        totalMs / #questions, maxMs, tostring(beforeDb == stableValue(_G.MSUF_DB))
    ))
end
