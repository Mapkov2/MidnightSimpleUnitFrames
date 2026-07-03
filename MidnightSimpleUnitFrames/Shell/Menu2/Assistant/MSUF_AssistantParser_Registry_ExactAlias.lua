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
local COMMON_EXACT_ALIAS_TOKENS = ExactAliasData.COMMON_EXACT_ALIAS_TOKENS or {}

local function Tokens(text)
    local out = {}
    for token in Normalize(text):gmatch("%S+") do out[#out + 1] = token end
    return out
end

local function AddIndexAlias(index, setting, alias, minTokens)
    alias = Normalize(alias)
    if alias == "" then return end
    local tokens = Tokens(alias)
    local count = #tokens
    minTokens = tonumber(minTokens) or 1
    if count < minTokens then return end
    if count == 0 or count > MAX_EXACT_ALIAS_TOKENS then return end
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
    for i = 1, #tokens do
        local token = tokens[i]
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
    for i = 1, #settings do
        if i % 64 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
        local setting = settings[i]
        local exactAliases = type(setting) == "table" and setting.exactAliases or nil
        for j = 1, #(exactAliases or {}) do AddIndexAlias(index, setting, exactAliases[j], 1) end
        local aliases = type(setting) == "table" and setting.aliases or nil
        for j = 1, #(aliases or {}) do
            if ShouldIndexNormalAlias(setting, aliases[j]) then
                AddIndexAlias(index, setting, aliases[j], 2)
            end
        end
    end

    P._registryExactAliasSettings = settings
    P._registryExactAliasCount = #settings
    P._registryExactAliasIndex = index
    return index
end

P._EnsureRegistryExactAliasIndex = EnsureIndex

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
local COMMAND_VERB_TOKENS = {
    set = true, change = true, make = true, turn = true, toggle = true,
    enable = true, disable = true, show = true, hide = true, use = true,
    put = true, switch = true, adjust = true,
}
local POSITIVE_VERBS = { enable = true, show = true }
local NEGATIVE_VERBS = { disable = true, hide = true }

local function SubjectPhrase(tokens)
    local i = 1
    local boolFromVerb
    while tokens[i] and COMMAND_VERB_TOKENS[tokens[i]] do
        if POSITIVE_VERBS[tokens[i]] then boolFromVerb = true end
        if NEGATIVE_VERBS[tokens[i]] then boolFromVerb = false end
        i = i + 1
    end
    if i == 1 then return nil end
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
            if tokens[k] == "to" then lastTo = k end
        end
        if lastTo then j = lastTo - 1 end
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
    for i = 1, #actions do
        local action = actions[i]
        if type(action) == "table" then
            local lists = { action.aliases, action.exactAliases }
            for l = 1, 2 do
                local list = lists[l]
                for j = 1, #(list or {}) do
                    local norm = Normalize(list[j])
                    if norm ~= "" then set[norm] = true end
                end
            end
        end
    end
    P._exactActionAliasSet = set
    P._exactActionAliasCount = #actions
    return set
end

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
    if not subject or count < (tonumber(minTokens) or 4) then return nil end
    local bucket = index.byLength and index.byLength[count]
    local hits = bucket and bucket[subject]
    if not hits or #hits == 0 then return nil end
    if ActionAliasSet()[subject] then return nil end
    local setting = hits[1]
    if #hits > 1 then
        setting = ReduceEquivalentHits(hits)
        if not setting then return nil end
    end
    -- Short phrases on hand-written settings stay with their dedicated flows
    -- ("global font color" is a workflow); generated settings may claim them
    -- because nothing else answers for those keys.
    if not setting.generated and count < 4 then return nil end
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

function P.ParseRegistryExactAliasShortcut(text, raw, opts)
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
            if setting.type ~= "enum" or text:find("|", 1, true) then return nil end
        end
        matches[1] = { setting = setting, score = #Compact(subject) }
        seen[setting] = true
        if setting.type == "boolean" and boolFromVerb ~= nil then
            -- When the stored flag is inverted relative to the spoken feature
            -- ("class resource when full" -> classPowerHideWhenFull), "turn on"
            -- means show the feature, so flip the verb-derived value. Only
            -- applies when the negation word is absent from the alias itself.
            local hay = (tostring(setting.attribute or "") .. " " .. tostring(setting.label or "")):lower()
            local subjectText = " " .. subject .. " "
            for word in ("hide hidden disable disabled suppress"):gmatch("%S+") do
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
        if fullPhrase then return nil end
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
