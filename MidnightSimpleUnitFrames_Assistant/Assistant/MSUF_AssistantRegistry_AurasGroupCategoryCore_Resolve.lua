-- Assistant group aura category resolver helpers.
-- Loaded before MSUF_AssistantRegistry_AurasGroupCategoryCore.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local A = MSUF.Assistant or {}
MSUF.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.BuildGroupAuraCategoryResolverCore(ctx)
    if type(ctx) ~= "table" then return nil end

    local AuraModel = ctx.AuraModel
    local GF_AURA_CATEGORY_FALLBACK = ctx.GF_AURA_CATEGORY_FALLBACK or {}
    if type(AuraModel) ~= "function" then return nil end

    local function CompactAuraCategory(value)
        return tostring(value or ""):lower():gsub("[^%w]+", "")
    end

    local function GFAuraCategoryScope(scope)
        return scope == "party" and "party" or "raid"
    end

    local function GFAuraCategoryScopeLabel(scope)
        return GFAuraCategoryScope(scope) == "party" and "Party" or "Raid / Mythic Raid"
    end

    local function GFAuraCategoryLane(lane)
        return lane == "debuff" and "debuff" or "buff"
    end

    local function GFAuraCategoryLaneLabel(lane)
        return GFAuraCategoryLane(lane) == "debuff" and "Debuff" or "Buff"
    end

    local function GFAuraCategoryLanePlural(lane)
        return GFAuraCategoryLane(lane) == "debuff" and "Debuffs" or "Buffs"
    end

    local function GFAuraCategoryValues()
        local Model = AuraModel()
        if Model and type(Model.GroupBlacklistCategoryValues) == "function" then
            local values = Model.GroupBlacklistCategoryValues()
            if type(values) == "table" and #values > 0 then return values end
        end
        return GF_AURA_CATEGORY_FALLBACK
    end

    local function FallbackCategoryLabel(catKey)
        catKey = tostring(catKey or "")
        for i = 1, #GF_AURA_CATEGORY_FALLBACK do
            local item = GF_AURA_CATEGORY_FALLBACK[i]
            if item and (item.key == catKey or item.value == catKey) then
                return item.label or item.text or catKey
            end
        end
        return nil
    end

    local function GFAuraCategoryLabel(catKey)
        catKey = tostring(catKey or "")
        local fallbackLabel = FallbackCategoryLabel(catKey)
        if fallbackLabel and fallbackLabel ~= "" then return fallbackLabel end
        local Model = AuraModel()
        if Model and type(Model.GroupBlacklistCategoryLabel) == "function" then
            local label = Model.GroupBlacklistCategoryLabel(catKey)
            if type(label) == "string" and label ~= "" then return label end
        end
        if catKey == "RAID_BUFFS" then return "Raid / Mythic Buffs" end
        local values = GFAuraCategoryValues()
        for i = 1, #values do
            local item = values[i]
            if item and (item.key == catKey or item.value == catKey) then return item.label or item.text or catKey end
        end
        return catKey
    end

    local function ResolveGFAuraCategory(value)
        local Model = AuraModel()
        if Model and type(Model.ResolveGroupBlacklistCategory) == "function" then
            local resolved = Model.ResolveGroupBlacklistCategory(value)
            if type(resolved) == "string" and resolved ~= "" then return resolved end
        end
        local compact = CompactAuraCategory(value)
        if compact == "" then return nil end
        local values = GFAuraCategoryValues()
        local bestKey, bestLen
        for i = 1, #values do
            local item = values[i]
            local key = item and (item.key or item.value)
            if key then
                local candidates = { key, item.label, item.text }
                if type(item.aliases) == "table" then
                    for j = 1, #item.aliases do candidates[#candidates + 1] = item.aliases[j] end
                end
                for j = 1, #candidates do
                    local token = CompactAuraCategory(candidates[j])
                    if token ~= "" then
                        local matchLen
                        if compact == token then
                            matchLen = #token
                        elseif #token >= 5 and compact:find(token, 1, true) then
                            matchLen = #token
                        end
                        if matchLen and (not bestLen or matchLen > bestLen) then
                            bestKey, bestLen = key, matchLen
                        end
                    end
                end
            end
        end
        return bestKey
    end

    return {
        GFAuraCategoryScope = GFAuraCategoryScope,
        GFAuraCategoryScopeLabel = GFAuraCategoryScopeLabel,
        GFAuraCategoryLane = GFAuraCategoryLane,
        GFAuraCategoryLaneLabel = GFAuraCategoryLaneLabel,
        GFAuraCategoryLanePlural = GFAuraCategoryLanePlural,
        GFAuraCategoryValues = GFAuraCategoryValues,
        GFAuraCategoryLabel = GFAuraCategoryLabel,
        ResolveGFAuraCategory = ResolveGFAuraCategory,
    }
end
