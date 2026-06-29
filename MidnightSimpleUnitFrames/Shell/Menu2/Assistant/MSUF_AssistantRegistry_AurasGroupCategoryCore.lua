-- Assistant group aura category helper core.
-- Builds category and direct blacklist helpers used by settings and actions.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local A = MSUF.Assistant or {}
MSUF.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.BuildGroupAuraCategoryCore(ctx)
    if type(ctx) ~= "table" then return nil end

    local ARef = ctx.A or A
    local AuraModel = ctx.AuraModel
    local GFAuraGroup = ctx.GFAuraGroup
    local ApplyGroup = ctx.ApplyGroup
    local GF_AURA_CATEGORY_FALLBACK = ctx.GF_AURA_CATEGORY_FALLBACK or {}

    if type(AuraModel) ~= "function" or type(GFAuraGroup) ~= "function" then return nil end
    if type(ApplyGroup) ~= "function" then return nil end

    local BuildGroupAuraCategoryResolverCore = A.AurasRegistry and A.AurasRegistry.BuildGroupAuraCategoryResolverCore
    local ResolverCore = type(BuildGroupAuraCategoryResolverCore) == "function" and BuildGroupAuraCategoryResolverCore({
        AuraModel = AuraModel,
        GF_AURA_CATEGORY_FALLBACK = GF_AURA_CATEGORY_FALLBACK,
    }) or nil
    if type(ResolverCore) ~= "table" then return nil end
    local GFAuraCategoryScope = ResolverCore.GFAuraCategoryScope
    local GFAuraCategoryScopeLabel = ResolverCore.GFAuraCategoryScopeLabel
    local GFAuraCategoryLane = ResolverCore.GFAuraCategoryLane
    local GFAuraCategoryLaneLabel = ResolverCore.GFAuraCategoryLaneLabel
    local GFAuraCategoryLanePlural = ResolverCore.GFAuraCategoryLanePlural
    local GFAuraCategoryValues = ResolverCore.GFAuraCategoryValues
    local GFAuraCategoryLabel = ResolverCore.GFAuraCategoryLabel
    local ResolveGFAuraCategory = ResolverCore.ResolveGFAuraCategory
    if type(GFAuraCategoryScope) ~= "function" or type(GFAuraCategoryLane) ~= "function" then return nil end
    if type(ResolveGFAuraCategory) ~= "function" or type(GFAuraCategoryValues) ~= "function" then return nil end

    local function ReadGFAuraCategoryState(scope, lane, catKey)
        scope = GFAuraCategoryScope(scope)
        lane = GFAuraCategoryLane(lane)
        catKey = ResolveGFAuraCategory(catKey) or catKey
        local Model = AuraModel()
        if Model and type(Model.ReadGroupBlacklistCategoryState) == "function" then
            local state = Model.ReadGroupBlacklistCategoryState(scope, lane, catKey)
            if type(state) == "table" then return state end
        end
        local function read(kind)
            local group = GFAuraGroup(kind, lane)
            return type(group.blacklistCats) == "table" and group.blacklistCats[catKey] == true
        end
        if scope == "party" then return { party = read("party") } end
        return { raid = read("raid"), mythicraid = read("mythicraid") }
    end

    local function WriteGFAuraCategoryKind(kind, lane, catKey, value)
        local group = GFAuraGroup(kind, lane)
        if type(group.blacklistCats) ~= "table" then group.blacklistCats = {} end
        group.blacklistCats[catKey] = value and true or nil
    end

    local function WriteGFAuraCategoryState(scope, lane, catKey, value)
        scope = GFAuraCategoryScope(scope)
        lane = GFAuraCategoryLane(lane)
        catKey = ResolveGFAuraCategory(catKey) or catKey
        if type(catKey) ~= "string" or catKey == "" then return false end
        local Model = AuraModel()
        if Model and type(Model.WriteGroupBlacklistCategoryState) == "function" then
            return Model.WriteGroupBlacklistCategoryState(scope, lane, catKey, value)
        end
        if type(value) == "table" then
            if scope == "party" then
                WriteGFAuraCategoryKind("party", lane, catKey, value.party == true)
            else
                WriteGFAuraCategoryKind("raid", lane, catKey, value.raid == true)
                WriteGFAuraCategoryKind("mythicraid", lane, catKey, value.mythicraid == true)
            end
            return true
        end
        if scope == "party" then
            WriteGFAuraCategoryKind("party", lane, catKey, value)
        else
            WriteGFAuraCategoryKind("raid", lane, catKey, value)
            WriteGFAuraCategoryKind("mythicraid", lane, catKey, value)
        end
        return true
    end

    local function ReadGFAuraCategorySetting(scope, lane, catKey)
        local state = ReadGFAuraCategoryState(scope, lane, catKey)
        if GFAuraCategoryScope(scope) == "party" then return state.party == true end
        local raid = state.raid == true
        local mythic = state.mythicraid == true
        if raid == mythic then return raid end
        return state
    end

    local function SameGFAuraCategoryState(oldValue, newValue)
        if type(oldValue) ~= "table" then return oldValue == newValue end
        if oldValue.party ~= nil then return (oldValue.party == true) == (newValue == true) end
        return (oldValue.raid == true) == (newValue == true) and (oldValue.mythicraid == true) == (newValue == true)
    end

    local function ApplyGFAuraCategory(scope)
        scope = GFAuraCategoryScope(scope)
        if scope == "party" then
            ApplyGroup("party", "auras")
        else
            ApplyGroup("raid", "auras")
            ApplyGroup("mythicraid", "auras")
        end
    end

    local BuildGroupAuraBlacklistCore = A.AurasRegistry and A.AurasRegistry.BuildGroupAuraBlacklistCore
    local GroupAuraBlacklistCore = type(BuildGroupAuraBlacklistCore) == "function" and BuildGroupAuraBlacklistCore({
        A = ARef,
        AuraModel = AuraModel,
        GFAuraCategoryScope = GFAuraCategoryScope,
        GFAuraCategoryLane = GFAuraCategoryLane,
    }) or nil
    if type(GroupAuraBlacklistCore) ~= "table" then return nil end

    local BuildGroupAuraCategorySummaryCore = A.AurasRegistry.BuildGroupAuraCategorySummaryCore
    local CategorySummaryCore = type(BuildGroupAuraCategorySummaryCore) == "function" and BuildGroupAuraCategorySummaryCore({
        AuraModel = AuraModel,
        GFAuraGroup = GFAuraGroup,
        GFAuraCategoryScope = GFAuraCategoryScope,
        GFAuraCategoryLane = GFAuraCategoryLane,
        GFAuraCategoryValues = GFAuraCategoryValues,
        GFAuraCategoryLabel = GFAuraCategoryLabel,
        ReadGFAuraCategorySetting = ReadGFAuraCategorySetting,
        WriteGFAuraCategoryState = WriteGFAuraCategoryState,
        ApplyGFAuraCategory = ApplyGFAuraCategory,
    }) or {}
    local GFAuraCategorySummary = CategorySummaryCore.GFAuraCategorySummary
    local ClearGFAuraCategoryBlacklist = CategorySummaryCore.ClearGFAuraCategoryBlacklist

    ARef.ResolveAuraGroupCategory = ResolveGFAuraCategory
    ARef.AuraGroupCategoryLabel = GFAuraCategoryLabel
    ARef.GroupAuraCategoryScope = GFAuraCategoryScope
    ARef.GroupAuraCategoryScopeLabel = GFAuraCategoryScopeLabel
    ARef.GroupAuraCategoryLane = GFAuraCategoryLane
    ARef.GroupAuraCategoryLanePlural = GFAuraCategoryLanePlural
    ARef.WriteGroupAuraCategoryState = WriteGFAuraCategoryState
    ARef.ApplyGroupAuraCategory = ApplyGFAuraCategory
    ARef.GroupAuraCategorySummary = GFAuraCategorySummary
    ARef.ClearGroupAuraCategoryBlacklist = ClearGFAuraCategoryBlacklist

    return {
        GFAuraCategoryValues = GFAuraCategoryValues,
        GFAuraCategoryLabel = GFAuraCategoryLabel,
        GFAuraCategoryScopeLabel = GFAuraCategoryScopeLabel,
        GFAuraCategoryLaneLabel = GFAuraCategoryLaneLabel,
        ReadGFAuraCategorySetting = ReadGFAuraCategorySetting,
        WriteGFAuraCategoryState = WriteGFAuraCategoryState,
        SameGFAuraCategoryState = SameGFAuraCategoryState,
        ApplyGFAuraCategory = ApplyGFAuraCategory,
    }
end
