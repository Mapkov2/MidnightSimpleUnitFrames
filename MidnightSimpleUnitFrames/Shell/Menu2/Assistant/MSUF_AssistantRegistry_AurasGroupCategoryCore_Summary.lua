-- Assistant group aura category summary helpers.
-- Loaded before MSUF_AssistantRegistry_AurasGroupCategoryCore.lua; the core passes category state helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local A = MSUF.Assistant or {}
MSUF.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.BuildGroupAuraCategorySummaryCore(ctx)
    if type(ctx) ~= "table" then return nil end

    local AuraModel = ctx.AuraModel
    local GFAuraGroup = ctx.GFAuraGroup
    local GFAuraCategoryScope = ctx.GFAuraCategoryScope
    local GFAuraCategoryLane = ctx.GFAuraCategoryLane
    local GFAuraCategoryValues = ctx.GFAuraCategoryValues
    local GFAuraCategoryLabel = ctx.GFAuraCategoryLabel
    local ReadGFAuraCategorySetting = ctx.ReadGFAuraCategorySetting
    local WriteGFAuraCategoryState = ctx.WriteGFAuraCategoryState
    local ApplyGFAuraCategory = ctx.ApplyGFAuraCategory

    if type(AuraModel) ~= "function" or type(GFAuraGroup) ~= "function" then return nil end
    if type(GFAuraCategoryScope) ~= "function" or type(GFAuraCategoryLane) ~= "function" then return nil end
    if type(GFAuraCategoryValues) ~= "function" or type(GFAuraCategoryLabel) ~= "function" then return nil end
    if type(ReadGFAuraCategorySetting) ~= "function" or type(WriteGFAuraCategoryState) ~= "function" then return nil end
    if type(ApplyGFAuraCategory) ~= "function" then return nil end

    local function GFAuraCategorySummary(scope, lane)
        scope = GFAuraCategoryScope(scope)
        lane = GFAuraCategoryLane(lane)
        local statePrefix = scope == "party" and "party" or "raid"
        local group = GFAuraGroup(statePrefix, lane)
        local cats = type(group.blacklistCats) == "table" and group.blacklistCats or nil
        if type(cats) ~= "table" then return "The hidden aura category list has no entries." end
        local out = {}
        for key, enabled in pairs(cats) do
            if enabled == true then out[#out + 1] = GFAuraCategoryLabel(key) end
        end
        table.sort(out)
        if #out == 0 then return "The hidden aura category list has no entries." end
        return table.concat(out, "\n")
    end

    local function ClearGFAuraCategoryBlacklist(scope, lane)
        scope = GFAuraCategoryScope(scope)
        lane = GFAuraCategoryLane(lane)
        local values = GFAuraCategoryValues()
        local count = 0
        for i = 1, #values do
            local item = values[i]
            local catKey = item and (item.key or item.value)
            if catKey then
                local state = ReadGFAuraCategorySetting(scope, lane, catKey)
                local wasBlocked = state == true
                if type(state) == "table" then
                    if state.party == true or state.raid == true or state.mythicraid == true then wasBlocked = true end
                end
                if wasBlocked then
                    WriteGFAuraCategoryState(scope, lane, catKey, false)
                    count = count + 1
                end
            end
        end
        if count > 0 then ApplyGFAuraCategory(scope) end
        return count
    end

    return {
        GFAuraCategorySummary = GFAuraCategorySummary,
        ClearGFAuraCategoryBlacklist = ClearGFAuraCategoryBlacklist,
    }
end
