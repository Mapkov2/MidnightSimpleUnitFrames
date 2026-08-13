-- Assistant exact-alias parser: fast path for deterministic registry alias phrases.
-- It narrows candidate work before fuzzy parsing and must stay side-effect free.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local P = A.Parser or {}
A.Parser = P

local Registry = A.Registry
local Data = A.ParserData or {}
A.ParserData = Data
local ExactAliasData = Data.REGISTRY_EXACT_ALIAS or {}
local Normalize = P.Normalize
local Compact = P.Compact
local AliasRelationText = P.AliasRelationText
local RelativeNumberDeltaForText = P.RelativeNumberDeltaForText
local ValueForRegistrySetting = P.ValueForRegistrySetting
local MissingValueResponse = P.MissingValueResponse

if not (Normalize and Compact and AliasRelationText and ValueForRegistrySetting) then return end

-- Exact-alias acceleration for registry options.
-- This index catches precise multi-word aliases before slower fuzzy scoring. Common command
-- words are ignored as triggers so broad phrases do not fan out across the whole registry.
local MAX_EXACT_ALIAS_TOKENS = ExactAliasData.MAX_EXACT_ALIAS_TOKENS or 8
-- The eight-token ceiling above bounds the FLOATING n-gram window in
-- AddMatches, which costs (lengths x start positions) per input. A control's
-- own visible label is not a window candidate -- it is only ever looked up as a
-- whole phrase, an O(1) bucket hit -- so capping it at eight bought nothing and
-- silently unindexed every longer name. "Raid / Mythic Raid Buff Hidden
-- Category Shaman Imbuements" is nine tokens, so typing the label exactly as
-- the menu prints it reached no control at all (36 of them). AddMatches still
-- clamps its own window to MAX_EXACT_ALIAS_TOKENS, so this changes no hot path.
local MAX_EXACT_LABEL_TOKENS = ExactAliasData.MAX_EXACT_LABEL_TOKENS or 16
local COMMON_EXACT_ALIAS_TOKENS = ExactAliasData.COMMON_EXACT_ALIAS_TOKENS or {}

local function Tokens(text)
    local out = {}
    for token in Normalize(text):gmatch("%S+") do out[#out + 1] = token end
    return out
end

local function AliasNormalizationMaskHas(mask, index)
    if type(mask) ~= "number" then return false end
    local bit = 2 ^ ((tonumber(index) or 1) - 1)
    return (mask % (bit * 2)) >= bit
end

-- Registry registration records which aliases still need the parser's full
-- normalizer. Most generated aliases are already canonical, so honoring that
-- bitmask avoids normalizing and caching tens of thousands of identical
-- strings while preserving byte-for-byte parser-normalization semantics.
local function PreparedSettingAlias(setting, alias, index, exact)
    if type(alias) ~= "string" then return Normalize(alias) end
    if type(setting) == "table" and setting._assistantAliasNormVersion == 2 then
        local mask = exact and setting._assistantExactAliasNormMask or setting._assistantAliasNormMask
        if not AliasNormalizationMaskHas(mask, index) then return alias end
    end
    return Normalize(alias)
end

local function AddIndexAlias(index, setting, alias, minTokens, maxTokens)
    if alias == "" then return end
    maxTokens = tonumber(maxTokens) or MAX_EXACT_ALIAS_TOKENS
    -- The alias is already normalized by PreparedSettingAlias. Count without
    -- allocating a temporary token table for every retained registry phrase.
    local count = 0
    for _ in alias:gmatch("%S+") do
        count = count + 1
        if count > maxTokens then return end
    end
    minTokens = tonumber(minTokens) or 1
    if count < minTokens then return end
    if count == 0 or count > maxTokens then return end
    index.byLength[count] = index.byLength[count] or {}
    local bucket = index.byLength[count][alias]
    if not bucket then
        bucket = {}
        index.byLength[count][alias] = bucket
    end
    -- Distinct alias spellings can normalize to the same phrase ("colour" ->
    -- "color"); keep each setting once per bucket so uniqueness checks hold.
    for i = 1, #bucket do
        if bucket[i] == setting then return end
    end
    bucket[#bucket + 1] = setting
    for token in alias:gmatch("%S+") do
        if not COMMON_EXACT_ALIAS_TOKENS[token] then index.triggerTokens[token] = true end
    end
    if count > index.maxTokens then index.maxTokens = count end
end

local function ShouldIndexNormalAlias(setting, alias)
    local key = tostring(setting and setting.key or "")
    if key:match("^bars%.playerHPBar") then
        local normalized = Normalize(alias)
        if normalized:find("player hp", 1, true)
            and not normalized:find("class resource", 1, true)
            and not normalized:find("class resources", 1, true)
            and not normalized:find("second", 1, true)
            and not normalized:find("duplicate", 1, true)
        then
            return false
        end
    end
    return true
end

local function EnsureIndex(settings)
    settings = settings or {}
    if P._registryExactAliasSettings == settings
        and P._registryExactAliasCount == #settings
        and type(P._registryExactAliasIndex) == "table" then
        return P._registryExactAliasIndex
    end

    local index = { byLength = {}, maxTokens = 0, triggerTokens = {} }

    -- Visible labels are only safe to index when they identify one setting.
    -- Several families deliberately share a label between a scoped twin and its
    -- base ("Party Aggro Shows For" is both barScope.gf_party.aggroMode and
    -- gf_party.aggroMode), and curated aliases are what disambiguate them --
    -- indexing the shared label makes both claim it and the curated choice
    -- loses. Count first, index only the unambiguous ones.
    local actionAliases = type(P.ExactActionAliasSet) == "function" and P.ExactActionAliasSet() or {}
    local labelOwners = {}
    for i = 1, #settings do
        -- This ownership pre-pass normalizes every visible label before the
        -- alias-building loop below. It must obey the same deferred-job budget;
        -- otherwise the first cold callback can block for the entire registry
        -- even though the later alias work yields correctly.
        if i % 32 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
        local label = type(settings[i]) == "table" and settings[i].label or nil
        if type(label) == "string" and label ~= "" then
            local normalized = Normalize(label)
            if normalized ~= "" then labelOwners[normalized] = (labelOwners[normalized] or 0) + 1 end
        end
    end

    local aliasWork = 0
    local function MaybeYieldAliasWork()
        aliasWork = aliasWork + 1
        -- A single setting can retain dozens of normal/exact aliases. Yield
        -- checks only between settings let one alias-heavy bucket exceed the
        -- per-frame job budget during a cold index build.
        if aliasWork % 16 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
    end
    for i = 1, #settings do
        if i % 64 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
        local setting = settings[i]
        local exactAliases = type(setting) == "table" and setting.exactAliases or nil
        for j = 1, #(exactAliases or {}) do
            AddIndexAlias(index, setting, PreparedSettingAlias(setting, exactAliases[j], j, true), 1)
            MaybeYieldAliasWork()
        end
        local aliases = type(setting) == "table" and setting.aliases or nil
        for j = 1, #(aliases or {}) do
            if ShouldIndexNormalAlias(setting, aliases[j]) then
                AddIndexAlias(index, setting, PreparedSettingAlias(setting, aliases[j], j, false), 2)
                MaybeYieldAliasWork()
            end
        end
        -- The name the player reads in the menu must always reach its own
        -- setting. Several families only carry attribute-derived aliases
        -- ("party buffs category blacklist Cooldowns") and never the visible
        -- label, so "turn on Party Buff Hidden Category Cooldowns" missed the
        -- exact lane entirely and a broad aura shortcut claimed it -- reading
        -- "Hidden" out of the label as an off-cue and disabling the whole Buff
        -- lane instead. Indexing the label closes that whole class.
        -- Normalize directly: PreparedSettingAlias only skips normalization for
        -- aliases the registry pre-normalized at a known index, and the label
        -- is not one of them, so routing it through there would index the raw
        -- capitalized string and never match a normalized query.
        local label = type(setting) == "table" and setting.label or nil
        if type(label) == "string" and label ~= "" then
            local normalizedLabel = Normalize(label)
            -- Actions outrank settings in the regular pipeline; a label that
            -- also names an action ("Crosshair Melee Range Spell") must not
            -- invert that from inside the pre-pass. Action aliases usually
            -- carry the command verb ("set crosshair melee range spell") that a
            -- label never has, so compare the verb-prefixed forms as well.
            local shadowsAction = actionAliases[normalizedLabel] == true
            if not shadowsAction then
                for _, verb in ipairs({ "set", "change", "show", "open", "reset" }) do
                    if actionAliases[verb .. " " .. normalizedLabel] then
                        shadowsAction = true
                        break
                    end
                end
            end
            if normalizedLabel ~= "" and labelOwners[normalizedLabel] == 1 and not shadowsAction then
                AddIndexAlias(index, setting, normalizedLabel, 1, MAX_EXACT_LABEL_TOKENS)
                MaybeYieldAliasWork()
            end
        end
    end

    P._registryExactAliasSettings = settings
    P._registryExactAliasCount = #settings
    P._registryExactAliasIndex = index
    return index
end

P._EnsureRegistryExactAliasIndex = EnsureIndex

local MAX_EXACT_ALIAS_LOOKUP_CACHE_RESULTS = 32

local function CopySettingBucket(bucket, limit)
    if type(bucket) ~= "table" or #bucket == 0 then return nil end
    local out = {}
    local bounded = math.max(1, math.floor(tonumber(limit) or 16))
    for i = 1, math.min(#bucket, bounded) do out[i] = bucket[i] end
    return out
end

-- Read-only setting-location questions should not have to construct and retain
-- the parser's complete mutation index. Reuse it when it already exists;
-- otherwise perform one exact prepared-alias scan and retain only the latest
-- bounded result. Registration order, alias eligibility, and match limits are
-- identical to the full index path.
local function FindRegistryExactAliasSettings(settings, subject, limit)
    settings = settings or {}
    subject = Normalize(subject)
    local tokenCount = 0
    for _ in subject:gmatch("%S+") do tokenCount = tokenCount + 1 end
    if subject == "" or tokenCount < 1 or tokenCount > MAX_EXACT_LABEL_TOKENS then return nil end
    limit = math.max(1, math.floor(tonumber(limit) or 16))

    local completeIndex = P._registryExactAliasSettings == settings
        and P._registryExactAliasCount == #settings
        and type(P._registryExactAliasIndex) == "table"
        and P._registryExactAliasIndex or nil
    if completeIndex then
        -- Whole-phrase bucket hit, so a long label costs the same as a short
        -- alias and the higher ceiling above applies here.
        local byLength = completeIndex.byLength and completeIndex.byLength[tokenCount]
        return CopySettingBucket(byLength and byLength[subject], limit)
    end
    -- The fallback below scans every setting's aliases, and only labels are
    -- indexed beyond the alias ceiling. Scanning for a subject no alias can be
    -- that long is pure cost, so keep the historical bound off the index.
    if tokenCount > MAX_EXACT_ALIAS_TOKENS then return nil end

    local cached = P._registryExactAliasLookupCache
    if type(cached) == "table"
        and cached.settings == settings
        and cached.count == #settings
        and cached.subject == subject
        and cached.tokenCount == tokenCount
        and cached.limit == limit
    then
        return cached.bucket ~= false and CopySettingBucket(cached.bucket, limit) or nil
    end

    local bucket, seen = {}, {}
    for i = 1, #settings do
        if i % 64 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
        local setting = settings[i]
        local matched = false
        local exactAliases = type(setting) == "table" and setting.exactAliases or nil
        for j = 1, #(exactAliases or {}) do
            if PreparedSettingAlias(setting, exactAliases[j], j, true) == subject then
                matched = true
                break
            end
        end
        if not matched and tokenCount >= 2 then
            local aliases = type(setting) == "table" and setting.aliases or nil
            for j = 1, #(aliases or {}) do
                local alias = PreparedSettingAlias(setting, aliases[j], j, false)
                if alias == subject and ShouldIndexNormalAlias(setting, aliases[j]) then
                    matched = true
                    break
                end
            end
        end
        if matched and setting and not seen[setting] then
            seen[setting] = true
            bucket[#bucket + 1] = setting
            if #bucket >= limit then break end
        end
    end

    local cacheBucket
    if #bucket == 0 then
        cacheBucket = false
    elseif #bucket <= MAX_EXACT_ALIAS_LOOKUP_CACHE_RESULTS then
        cacheBucket = bucket
    end
    P._registryExactAliasLookupCache = cacheBucket ~= nil and {
        settings = settings,
        count = #settings,
        subject = subject,
        tokenCount = tokenCount,
        limit = limit,
        bucket = cacheBucket,
    } or nil
    return #bucket > 0 and CopySettingBucket(bucket, limit) or nil
end

P._FindRegistryExactAliasSettings = FindRegistryExactAliasSettings

local function HasTriggerToken(index, tokens)
    local triggers = index and index.triggerTokens
    if not triggers then return true end
    for i = 1, #(tokens or {}) do
        if triggers[tokens[i]] then return true end
    end
    return false
end

local function HasExactAliasBulkScope(text)
    text = Normalize(text)
    return (" " .. text .. " "):find(" all ", 1, true) ~= nil
        or (" " .. text .. " "):find(" every ", 1, true) ~= nil
        or (" " .. text .. " "):find(" alle ", 1, true) ~= nil
        or (" " .. text .. " "):find(" jede ", 1, true) ~= nil
        or (" " .. text .. " "):find(" jeder ", 1, true) ~= nil
        or text:find("group frame", 1, true) ~= nil
        or text:find("group frames", 1, true) ~= nil
        or text:find("groupframes", 1, true) ~= nil
        or text:find("group aura", 1, true) ~= nil
        or text:find("group auras", 1, true) ~= nil
        or text:find("group buff", 1, true) ~= nil
        or text:find("group buffs", 1, true) ~= nil
        or text:find("group debuff", 1, true) ~= nil
        or text:find("group debuffs", 1, true) ~= nil
end

local function AddMatches(out, seen, index, tokens, minLen)
    local maxLen = math.min(index.maxTokens or 0, #tokens, MAX_EXACT_ALIAS_TOKENS)
    for len = maxLen, math.max(1, tonumber(minLen) or 1), -1 do
        local bucket = index.byLength and index.byLength[len]
        if bucket then
            for startIndex = 1, (#tokens - len + 1) do
                local phrase = table.concat(tokens, " ", startIndex, startIndex + len - 1)
                local settings = bucket[phrase]
                if settings then
                    for i = 1, #settings do
                        local setting = settings[i]
                        if setting and not seen[setting] then
                            seen[setting] = true
                            out[#out + 1] = { setting = setting, score = #Compact(phrase) }
                        end
                    end
                end
            end
        end
        if #out > 0 then return len end
    end
    return nil
end

-- Full-phrase pre-pass support: the priority call from A.Parse only fires when
-- the WHOLE command (minus a leading command verb and a trailing "to <value>")
-- equals exactly one indexed alias. Floating n-gram windows are far too eager
-- for a stage that runs before the topical fast paths.
-- Relative verbs (raise/lower/increase/decrease) are deliberately absent: they
-- describe a delta, and their own lanes own that. Everything here states an
-- exact value or polarity. "configure", "update", "modify" and the English
-- "activate"/"deactivate" were missing, so "configure range fade raid to on"
-- fell to the fuzzy lane and asked which control while the identical sentence
-- with "set" applied.
local COMMAND_VERB_TOKENS = {
    set = true, change = true, make = true, turn = true, toggle = true,
    enable = true, disable = true, show = true, hide = true, use = true,
    put = true, switch = true, adjust = true,
    configure = true, update = true, modify = true,
    customize = true, customise = true, tweak = true,
    activate = true, deactivate = true,
}
local POSITIVE_VERBS = { enable = true, show = true, activate = true }
local NEGATIVE_VERBS = { disable = true, hide = true, deactivate = true }

-- Politeness and address tokens carry no meaning for matching, but they sit in
-- front of the verb, so the verb scan below never started and "please set
-- Player Width to 100" matched nothing.
-- "msuf" is deliberately absent: it is a real VALUE ("set general boss castbar
-- backend to MSUF"), and stripping it as trailing filler silently retargeted
-- those commands. It stays in the post-verb determiner list below, where a
-- value can never appear.
local COMMAND_FILLER_TOKENS = {
    please = true, pls = true, kindly = true, just = true, now = true, fully = true,
    hey = true, hi = true, hello = true, assistant = true,
    ok = true, okay = true, also = true,
    bitte = true, mal = true, jetzt = true,
}

-- Determiners and possessives sit between the verb and the option name ("set
-- MY player width", "set MSUF player width"). They are never part of a label.
local COMMAND_DETERMINER_TOKENS = {
    the = true, my = true, our = true, its = true, msuf = true,
    der = true, die = true, das = true, den = true, dem = true, mein = true, meine = true,
}

local function SubjectPhrase(tokens)
    local i = 1
    local boolFromVerb
    while tokens[i] and COMMAND_FILLER_TOKENS[tokens[i]] do i = i + 1 end
    -- A trailing "please" is politeness, not a value.
    local last = #tokens
    while last > i and COMMAND_FILLER_TOKENS[tokens[last]] do last = last - 1 end
    if last < #tokens then
        local trimmed = {}
        for k = 1, last do trimmed[k] = tokens[k] end
        tokens = trimmed
    end
    local afterFiller = i
    while tokens[i] and COMMAND_VERB_TOKENS[tokens[i]] do
        if POSITIVE_VERBS[tokens[i]] then boolFromVerb = true end
        if NEGATIVE_VERBS[tokens[i]] then boolFromVerb = false end
        i = i + 1
        while tokens[i] and COMMAND_DETERMINER_TOKENS[tokens[i]] do i = i + 1 end
    end
    if i == afterFiller then
        -- Players drop the verb once they know the option name ("Boss Absorb
        -- Bar Height to 51"). That is only a command when an explicit value
        -- tail follows, so require a "to <value>"; a bare option name stays a
        -- question. The caller still demands that everything before the tail
        -- equal exactly one indexed alias, which keeps this from being eager.
        local hasValueTail = false
        for k = 2, #tokens - 1 do
            if tokens[k] == "to" or tokens[k] == "=" then hasValueTail = true break end
        end
        if not hasValueTail then return nil end
    end
    if tokens[i] == "on" then
        boolFromVerb = true
        i = i + 1
    elseif tokens[i] == "off" then
        boolFromVerb = false
        i = i + 1
    end
    local j = #tokens
    -- Boolean commands carry no value, so "to" belongs to the option name
    -- ("detached power bar anchor to class power"); only cut a value tail for
    -- set-style commands.
    if boolFromVerb == nil then
        local lastTo
        for k = i + 1, #tokens - 1 do
            if tokens[k] == "to" or tokens[k] == "=" then lastTo = k end
        end
        if lastTo then
            j = lastTo - 1
        elseif j > i and tokens[j]:match("^[-+]?%d+%.?%d*$") then
            -- "make Boss Absorb Bar Height 51" drops the "to" as well as the
            -- verb. A trailing bare number is the value, never part of an
            -- option name -- labels that genuinely end in a digit were already
            -- matched whole by the caller before this tail is considered.
            j = j - 1
        end
    end
    if j < i then return nil end
    return table.concat(tokens, " ", i, j), (j - i + 1), boolFromVerb
end

-- Action aliases outrank the pre-pass: in the regular pipeline the action
-- alias shortcut runs before the setting exact-alias stage, and the pre-pass
-- must not invert that.
local function ActionAliasSet()
    local actions = Registry and Registry.AllActions and Registry:AllActions() or {}
    if P._exactActionAliasSet and P._exactActionAliasCount == #actions then
        return P._exactActionAliasSet
    end
    local set = {}
    local aliasWork = 0
    for i = 1, #actions do
        local action = actions[i]
        if type(action) == "table" then
            local lists = { action.aliases, action.exactAliases }
            for l = 1, 2 do
                local list = lists[l]
                for j = 1, #(list or {}) do
                    local norm = Normalize(list[j])
                    if norm ~= "" then set[norm] = true end
                    aliasWork = aliasWork + 1
                    if aliasWork % 16 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
                end
            end
        end
    end
    P._exactActionAliasSet = set
    P._exactActionAliasCount = #actions
    return set
end

-- Exposed on P because EnsureIndex is defined above this point and so cannot
-- capture the local; the label pass needs it to avoid shadowing an action.
P.ExactActionAliasSet = ActionAliasSet

-- Registration domains can register the same feature twice (e.g.
-- "gf_party.dispelOverlayStyle" and "barScope.gf_party.dispelOverlayStyle"). When
-- every hit shares the same attribute and effective scope, the hits are
-- equivalent and the canonical two-segment key wins deterministically.
local function ReduceEquivalentHits(hits)
    local function normText(value)
        value = tostring(value or ""):lower():gsub("[^%w]", "")
        return (value:gsub("background", "bg"))
    end
    local function keyParts(setting)
        local key = tostring(setting.key or "")
        local midScope = key:match("^[^.]+%.([^.]+)%.")
        local firstSeg = key:match("^([^.]+)%.")
        return midScope or firstSeg or key, select(2, key:gsub("%.", ""))
    end
    local baseScope = keyParts(hits[1])
    local baseAttr = normText(hits[1].attribute)
    if baseAttr == "" then return nil end
    local best, bestDots
    for i = 1, #hits do
        local setting = hits[i]
        local scope, dots = keyParts(setting)
        if scope ~= baseScope or normText(setting.attribute) ~= baseAttr then return nil end
        if not best or dots < bestDots then
            best, bestDots = setting, dots
        end
    end
    return best
end

local function FullPhraseMatch(index, tokens, minTokens)
    local subject, count, boolFromVerb = SubjectPhrase(tokens)
    if not subject then return nil end
    local requestedMinTokens = tonumber(minTokens) or 4
    -- A unique two-word numeric control with an explicit value tail is already
    -- deterministic ("set target width to 300"). Resolve that narrow shape in
    -- the cold full-phrase pass. Otherwise the compound parser falls through
    -- several broad registries before eventually producing this same plan,
    -- leaving a long unsliced tail immediately after the cold index finishes.
    local explicitTwoTokenNumber = count == 2 and requestedMinTokens == 3 and boolFromVerb == nil
        and (tokens[1] == "set" or tokens[1] == "change" or tokens[1] == "adjust")
    if explicitTwoTokenNumber then
        local hasValueTail = false
        for i = 2, #tokens - 1 do
            if tokens[i] == "to" then
                hasValueTail = true
                break
            end
        end
        explicitTwoTokenNumber = hasValueTail
    end
    if count < requestedMinTokens and not explicitTwoTokenNumber then return nil end
    local bucket = index.byLength and index.byLength[count]
    local hits = bucket and bucket[subject]
    if not hits or #hits == 0 then return nil end
    if ActionAliasSet()[subject] then return nil end
    local setting = hits[1]
    if #hits > 1 then
        setting = ReduceEquivalentHits(hits)
        if not setting then return nil end
    end
    explicitTwoTokenNumber = explicitTwoTokenNumber and setting.type == "number"
    if count < requestedMinTokens and not explicitTwoTokenNumber then return nil end
    -- Short phrases on hand-written settings stay with their dedicated flows
    -- unless the caller explicitly opted into a shorter full-phrase match.
    -- A.Parse uses three tokens here because an exact three-word control name
    -- (for example "party buff tooltip") is already more specific than a
    -- topical parent/lane shortcut. Keep the historical four-token floor for
    -- callers that do not provide an explicit threshold.
    local handWrittenMinTokens = requestedMinTokens
    if not setting.generated and count < handWrittenMinTokens and not explicitTwoTokenNumber then return nil end
    return setting, subject, boolFromVerb
end

local function GuardedSettingResponse(setting, text, raw)
    local guard = type(setting) == "table" and setting.intentGuard or nil
    if type(guard) ~= "function" then return nil end
    local result, status, message = guard(setting, text, raw)
    if type(result) == "table" then return result end
    if result == false then
        return {
            kind = "unknown",
            status = status or "failed",
            text = message or "I found a matching option. Which value do you want me to use before I apply it?",
        }
    end
    return nil
end

local function TextHasAny(text, terms)
    if type(terms) ~= "table" then return true end
    local hay = " " .. Normalize(text) .. " "
    for i = 1, #terms do
        local term = Normalize(terms[i])
        if term ~= "" and hay:find(" " .. term .. " ", 1, true) then return true end
    end
    return false
end

local function ResolveCompanionValue(spec, companionSetting, text, primaryValue)
    local value = spec and spec.value
    if type(value) == "function" then
        value = value(spec, companionSetting, text, primaryValue)
    end

    local relativeDelta = spec and spec.relativeDelta
    if type(relativeDelta) == "function" then
        relativeDelta = relativeDelta(spec, companionSetting, text, primaryValue)
    end
    return value, relativeDelta
end

local function AddExactAliasChange(changes, seenKeys, setting, value, relativeDelta, score, text)
    local key = tostring(setting and setting.key or "")
    if key ~= "" and not seenKeys[key] then
        seenKeys[key] = true
        changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, matchScore = score }
    end

    local companions = type(setting) == "table" and setting.companionChanges or nil
    if type(companions) ~= "table" then return end
    for i = 1, #companions do
        local spec = companions[i]
        local companionKey = tostring(spec and spec.key or "")
        local companionSetting = companionKey ~= "" and Registry and Registry:GetSetting(companionKey) or nil
        local whenValue = spec and spec.whenValue
        if companionSetting
            and not seenKeys[companionKey]
            and (whenValue == nil or whenValue == value)
            and TextHasAny(text, spec.whenTextHas)
        then
            local companionValue, companionRelativeDelta = ResolveCompanionValue(spec, companionSetting, text, value)
            if companionValue ~= nil or companionRelativeDelta ~= nil then
                local companion = { setting = companionSetting, value = companionValue, relativeDelta = companionRelativeDelta, matchScore = score, companion = true }
                seenKeys[companionKey] = true
                if spec.prepend == true then
                    table.insert(changes, 1, companion)
                else
                    changes[#changes + 1] = companion
                end
            end
        end
    end
end

-- Build a normal transactional plan for one setting that the Router already
-- identified by its complete label or alias.  Keeping this beside the exact
-- alias matcher preserves intent guards and companion changes while avoiding
-- a second fuzzy search that could redirect a very specific command.
function P.PlanForExactRegistrySetting(setting, text, raw)
    if type(setting) ~= "table" then return nil end
    local guarded = GuardedSettingResponse(setting, text, raw)
    if guarded then return guarded end

    -- The words may name a family whose bare form is one control while the
    -- stated value belongs to a sibling: "make the frame border half
    -- transparent" resolves the thickness slider and then turns it down.
    -- Only pays for a lookup when the sentence states a colour or an opacity.
    local router = A.RouterPrivate
    if type(router) == "table" and type(router.SiblingSettingForStatedValueKind) == "function" then
        local sibling = router.SiblingSettingForStatedValueKind(raw or text)
        if sibling and sibling ~= setting then
            local siblingPlan = router.StatedValueKindSiblingPlan(raw or text)
            if siblingPlan then return siblingPlan end
        end
    end

    local relativeDelta = setting.type == "number" and RelativeNumberDeltaForText
        and RelativeNumberDeltaForText(setting, text) or nil
    local value
    if relativeDelta == nil then value = ValueForRegistrySetting(setting, text, raw) end
    if value == nil and relativeDelta == nil then
        return MissingValueResponse and MissingValueResponse({ { setting = setting, score = 30000 } }, raw) or nil
    end

    local changes, seen = {}, {}
    AddExactAliasChange(changes, seen, setting, value, relativeDelta, 30000, text)
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1 and true or nil,
        label = setting.label or "Assistant option change",
        summary = "Changes the exactly named MSUF option.",
        raw = raw,
        sourceText = raw,
        exactSettingMutation = true,
    }
end

function P.ParseRegistryExactAliasShortcut(text, raw, opts)
    -- The immediate Submit fast path calls this matcher before the Router.
    -- Never let a problem report, option-list request, or subjective policy
    -- request become a write merely because one alias appears in the sentence.
    if type(P.NonMutatingIntent) == "function" and P.NonMutatingIntent(text) then return nil end
    local allSettings = Registry and Registry:AllSettings() or {}
    if #allSettings == 0 then return nil end

    local index = EnsureIndex(allSettings)
    if (index.maxTokens or 0) <= 0 then return nil end

    -- opts.minTokens: only accept matches of at least this many tokens.
    -- opts.fullPhrase: priority pre-pass mode used by A.Parse. The command
    -- (minus leading verb and trailing "to <value>") must equal exactly one
    -- indexed alias; anything looser defers to the topical fast paths.
    local minTokens = type(opts) == "table" and tonumber(opts.minTokens) or nil
    local fullPhrase = type(opts) == "table" and opts.fullPhrase == true
    local fullPhraseMatchedSetting

    local tokens = Tokens(text)
    if not HasTriggerToken(index, tokens) then return nil end

    local matches, seen = {}, {}
    local forcedBooleanValue
    if fullPhrase then
        local setting, subject, boolFromVerb = FullPhraseMatch(index, tokens, minTokens)
        if not setting then return nil end
        -- Hand-written settings often have dedicated parsers with richer
        -- value handling; only claim them when value parsing is trivially
        -- safe: booleans, numbers, and plain enum words. Pipe-styled filter
        -- values ("HELPFUL|PLAYER") and free strings stay on their dedicated
        -- routes. Generated settings have no dedicated parser, so the
        -- pre-pass is their only path.
        if not setting.generated and setting.type ~= "boolean" and setting.type ~= "number" then
            local fixedString = setting.type == "string" and setting.closedValues == true
                and type(setting.values) == "table" and #setting.values > 0
            -- Colours are deliberately NOT claimed here: a colour lane upstream
            -- of this pre-pass owns them, and widening this guard regressed the
            -- gate without reaching that lane. The known consequence is that a
            -- fully-named colour ("Arcane Mage Arcane Charges 1 Color to red")
            -- is answered by the broader Mage Class Bar Color instead; fixing
            -- that belongs in the colour lane's own precedence, not here.
            if not fixedString and (setting.type ~= "enum" or text:find("|", 1, true)) then return nil end
        end
        matches[1] = { setting = setting, score = #Compact(subject) }
        fullPhraseMatchedSetting = setting
        seen[setting] = true
        if setting.type == "boolean" and boolFromVerb ~= nil then
            -- When the stored flag is inverted relative to the spoken feature
            -- ("class resource when full" -> classPowerHideWhenFull), "turn on"
            -- means show the feature, so flip the verb-derived value. Only
            -- applies when the negation word is absent from the alias itself.
            local hay = (tostring(setting.attribute or "") .. " " .. tostring(setting.label or "")):lower()
            local subjectText = " " .. subject .. " "
            for word in ("hide hidden disable disabled suppress kill"):gmatch("%S+") do
                if hay:find(word, 1, true) and not subjectText:find(" " .. word .. " ", 1, true) then
                    boolFromVerb = not boolFromVerb
                    break
                end
            end
            forcedBooleanValue = boolFromVerb
        end
    else
        AddMatches(matches, seen, index, tokens, minTokens)
        local relation = AliasRelationText(text)
        if relation ~= text then AddMatches(matches, seen, index, Tokens(relation), minTokens) end
    end
    if #matches == 0 then return nil end

    local bestScore = 0
    for i = 1, #matches do if matches[i].score > bestScore then bestScore = matches[i].score end end

    local changes, missingValue, seenChangeKeys = {}, {}, {}
    for i = 1, #matches do
        local match = matches[i]
        if match.score == bestScore then
            local setting = match.setting
            local allowed = true
            if type(P.RegistrySettingMayMatchExactAlias) == "function" then
                allowed = P.RegistrySettingMayMatchExactAlias(setting, text) == true
            end
            if allowed then
                local guarded = GuardedSettingResponse(setting, text, raw)
                if guarded then return guarded end
                local relativeDelta = setting.type == "number" and RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text) or nil
                local value
                if relativeDelta == nil then
                    -- Full-phrase mode derives booleans from the command verb
                    -- ("turn on X no ellipsis" is true even though the alias
                    -- itself contains a negation word).
                    if forcedBooleanValue ~= nil and setting.type == "boolean" then
                        value = forcedBooleanValue
                    else
                        value = ValueForRegistrySetting(setting, text, raw)
                    end
                end
                if value ~= nil or relativeDelta ~= nil then
                    AddExactAliasChange(changes, seenChangeKeys, setting, value, relativeDelta, match.score, text)
                elseif setting.type ~= "boolean" then
                    missingValue[#missingValue + 1] = { setting = setting, score = match.score }
                end
            end
        end
    end

    if #changes == 0 then
        -- Pre-pass mode must stay silent so the sentence keeps flowing through
        -- the regular pipeline instead of dead-ending in a value question.
        -- A bare change/adjust request for one exact boolean label is the safe
        -- exception: the subject is fully resolved, but no polarity was given.
        if fullPhrase then
            if fullPhraseMatchedSetting and fullPhraseMatchedSetting.type == "boolean"
                and (tokens[1] == "change" or tokens[1] == "adjust")
                and (type(P.RegistrySettingMayMatchExactAlias) ~= "function"
                    or P.RegistrySettingMayMatchExactAlias(fullPhraseMatchedSetting, text) == true)
            then
                return MissingValueResponse and MissingValueResponse({
                    { setting = fullPhraseMatchedSetting, score = 30000 },
                }, raw) or nil
            end
            return nil
        end
        return MissingValueResponse and MissingValueResponse(missingValue, raw) or nil
    end
    local primaryChangeCount = 0
    for i = 1, #changes do
        if not changes[i].companion then primaryChangeCount = primaryChangeCount + 1 end
    end
    if #changes > 1 and primaryChangeCount == 1 then
        local setting
        for i = 1, #changes do
            if not changes[i].companion then
                setting = changes[i].setting
                break
            end
        end
        return {
            kind = "changes",
            changes = changes,
            bulkSafe = true,
            label = setting and setting.label or "Assistant option change",
            summary = "Changes the matched option.",
        }
    end
    if #changes > 1 then
        if HasExactAliasBulkScope(text)
            or (P.ShouldApplyMultipleAuraLaneChanges and P.ShouldApplyMultipleAuraLaneChanges(text, changes))
        then
            return {
                kind = "changes",
                changes = changes,
                bulkSafe = P.AreBulkSafeAuraSettingChanges and P.AreBulkSafeAuraSettingChanges(changes) or nil,
                label = "Multiple matching options",
                summary = "Changes multiple matched options.",
            }
        end
        if A.ContextEngineEnabled ~= false and P.ScoreSettingCandidates then
            local scored = P.ScoreSettingCandidates(changes, { context = A.ConversationContext and A.ConversationContext() or nil })
            if type(scored) == "table" and #scored > 0 then changes = scored end
        end
    end
    if #changes > 1 then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Multiple matching options",
            summary = "Asks for a more specific target.",
        }
    end

    local setting = changes[1].setting
    return {
        kind = "changes",
        changes = changes,
        label = setting and setting.label or "Assistant option change",
        summary = "Changes the matched option.",
    }
end
