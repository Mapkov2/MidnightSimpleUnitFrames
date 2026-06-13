local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local P = A.Parser or {}
A.Parser = P

local Registry = A.Registry
local Normalize = P.Normalize
local Compact = P.Compact
local AliasRelationText = P.AliasRelationText
local RelativeNumberDeltaForText = P.RelativeNumberDeltaForText
local ValueForRegistrySetting = P.ValueForRegistrySetting
local MissingValueResponse = P.MissingValueResponse

if not (Normalize and Compact and AliasRelationText and ValueForRegistrySetting) then return end

-- Exact-alias acceleration for registry settings.
-- This index catches precise multi-word aliases before slower fuzzy scoring. Common command
-- words are ignored as triggers so broad phrases do not fan out across the whole registry.
local MAX_EXACT_ALIAS_TOKENS = 8
local COMMON_EXACT_ALIAS_TOKENS = {
    a = true,
    an = true,
    ["and"] = true,
    change = true,
    disable = true,
    enable = true,
    ["for"] = true,
    make = true,
    move = true,
    nudge = true,
    of = true,
    off = true,
    on = true,
    set = true,
    shift = true,
    the = true,
    to = true,
    turn = true,
    player = true,
    target = true,
    focus = true,
    pet = true,
    boss = true,
    party = true,
    raid = true,
    frame = true,
    frames = true,
}

local function Tokens(text)
    local out = {}
    for token in Normalize(text):gmatch("%S+") do out[#out + 1] = token end
    return out
end

local function AddIndexAlias(index, setting, alias)
    alias = Normalize(alias)
    if alias == "" then return end
    local tokens = Tokens(alias)
    local count = #tokens
    if count == 0 or count > MAX_EXACT_ALIAS_TOKENS then return end
    index.byLength[count] = index.byLength[count] or {}
    index.byLength[count][alias] = index.byLength[count][alias] or {}
    index.byLength[count][alias][#index.byLength[count][alias] + 1] = setting
    for i = 1, #tokens do
        local token = tokens[i]
        if not COMMON_EXACT_ALIAS_TOKENS[token] then index.triggerTokens[token] = true end
    end
    if count > index.maxTokens then index.maxTokens = count end
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
        local setting = settings[i]
        local aliases = type(setting) == "table" and setting.exactAliases or nil
        for j = 1, #(aliases or {}) do AddIndexAlias(index, setting, aliases[j]) end
    end

    P._registryExactAliasSettings = settings
    P._registryExactAliasCount = #settings
    P._registryExactAliasIndex = index
    return index
end

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
        or text:find("group frames", 1, true) ~= nil
        or text:find("groupframes", 1, true) ~= nil
end

local function AddMatches(out, seen, index, tokens)
    local maxLen = math.min(index.maxTokens or 0, #tokens, MAX_EXACT_ALIAS_TOKENS)
    for len = maxLen, 1, -1 do
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

local function GuardedSettingResponse(setting, text, raw)
    local guard = type(setting) == "table" and setting.intentGuard or nil
    if type(guard) ~= "function" then return nil end
    local ok, result, status, message = pcall(guard, setting, text, raw)
    if not ok then return nil end
    if type(result) == "table" then return result end
    if result == false then
        return {
            kind = "unknown",
            status = status or "failed",
            text = message or "I could not safely use that matched setting.",
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
        local ok, result = pcall(value, spec, companionSetting, text, primaryValue)
        if not ok then return nil, nil end
        value = result
    end

    local relativeDelta = spec and spec.relativeDelta
    if type(relativeDelta) == "function" then
        local ok, result = pcall(relativeDelta, spec, companionSetting, text, primaryValue)
        if not ok then return value, nil end
        relativeDelta = result
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

function P.ParseRegistryExactAliasShortcut(text, raw)
    local allSettings = Registry and Registry:AllSettings() or {}
    if #allSettings == 0 then return nil end

    local index = EnsureIndex(allSettings)
    if (index.maxTokens or 0) <= 0 then return nil end

    local tokens = Tokens(text)
    if not HasTriggerToken(index, tokens) then return nil end

    local matches, seen = {}, {}
    AddMatches(matches, seen, index, tokens)
    local relation = AliasRelationText(text)
    if relation ~= text then AddMatches(matches, seen, index, Tokens(relation)) end
    if #matches == 0 then return nil end

    local bestScore = 0
    for i = 1, #matches do if matches[i].score > bestScore then bestScore = matches[i].score end end

    local changes, missingValue, seenChangeKeys = {}, {}, {}
    for i = 1, #matches do
        local match = matches[i]
        if match.score == bestScore then
            local setting = match.setting
            local guarded = GuardedSettingResponse(setting, text, raw)
            if guarded then return guarded end
            local relativeDelta = setting.type == "number" and RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text) or nil
            local value
            if relativeDelta == nil then value = ValueForRegistrySetting(setting, text, raw) end
            if value ~= nil or relativeDelta ~= nil then
                AddExactAliasChange(changes, seenChangeKeys, setting, value, relativeDelta, match.score, text)
            elseif setting.type ~= "boolean" then
                missingValue[#missingValue + 1] = { setting = setting, score = match.score }
            end
        end
    end

    if #changes == 0 then return MissingValueResponse and MissingValueResponse(missingValue, raw) or nil end
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
            label = setting and setting.label or "Assistant setting change",
            summary = "Registry exact-alias setting change.",
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
                label = "Multiple matching settings",
                summary = "Registry exact-alias multi-scope setting change.",
            }
        end
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Multiple matching settings",
            summary = "Registry exact-alias match needs a more specific target.",
        }
    end

    local setting = changes[1].setting
    return {
        kind = "changes",
        changes = changes,
        label = setting and setting.label or "Assistant setting change",
        summary = "Registry exact-alias setting change.",
    }
end
