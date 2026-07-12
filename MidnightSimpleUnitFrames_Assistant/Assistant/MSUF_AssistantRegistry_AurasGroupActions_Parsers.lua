-- Group aura action parser helpers.
-- Loaded before MSUF_AssistantRegistry_AurasGroupActions.lua; keeps alias parsing out of action registrations.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.BuildGroupActionParsers(ctx)
    if type(ctx) ~= "table" then return nil end

    local Assistant = ctx.A or A
    local helpers = ctx.helpers or (Assistant.AurasRegistry and Assistant.AurasRegistry.ActionHelpers) or nil
    if type(helpers) ~= "table" then return nil end

    local AuraActionNormalized = helpers.AuraActionNormalized
    local AuraActionContainsAny = helpers.AuraActionContainsAny
    if type(AuraActionNormalized) ~= "function" or type(AuraActionContainsAny) ~= "function" then return nil end

    local function GroupAuraCategoryHasUnitAuraScope(text)
        local P = Assistant.Parser or {}
        local normalized = AuraActionNormalized(text)
        local phrases = {
            "player aura", "player auras", "target aura", "target auras",
            "focus aura", "focus auras", "boss aura", "boss auras",
        }
        if type(P.ContainsAny) == "function" then return P.ContainsAny(normalized, phrases) end
        for i = 1, #phrases do
            if normalized:find(phrases[i], 1, true) then return true end
        end
        return false
    end

    local function GroupAuraCategoryAliasBlocked(text)
        local normalized = AuraActionNormalized(text)
        return normalized:find("copy category", 1, true)
            or normalized:find("copy categories", 1, true)
            or normalized:find("group copy", 1, true)
            or normalized:find("unit copy", 1, true)
    end

    local function GroupAuraCategoryScopeLane(text)
        local P = Assistant.Parser or {}
        local normalized = AuraActionNormalized(text)
        local scope = type(P.AuraGroupBlacklistScope) == "function" and P.AuraGroupBlacklistScope(normalized) or nil
        local lane = type(P.AuraGroupBlacklistLane) == "function" and P.AuraGroupBlacklistLane(normalized) or nil
        scope = Assistant.GroupAuraCategoryScope and Assistant.GroupAuraCategoryScope(scope) or (scope or "raid")
        lane = Assistant.GroupAuraCategoryLane and Assistant.GroupAuraCategoryLane(lane) or (lane or "buff")
        return scope, lane
    end

    local function GroupAuraCategoryForAlias(text)
        local P = Assistant.Parser or {}
        local normalized = AuraActionNormalized(text)
        local category = type(P.AuraGroupBlacklistCategoryForText) == "function" and P.AuraGroupBlacklistCategoryForText(normalized) or nil
        if not category and Assistant.ResolveAuraGroupCategory then category = Assistant.ResolveAuraGroupCategory(normalized) end
        return category
    end

    local function ParseGroupAuraCategorySetAliasArgs(text)
        local normalized = AuraActionNormalized(text)
        if GroupAuraCategoryAliasBlocked(normalized) then return false end
        if GroupAuraCategoryHasUnitAuraScope(normalized) then return false end
        if AuraActionContainsAny(normalized, { "show", "list", "summary", "current", "what is", "whats" }) then return false end
        if not (normalized:find("category", 1, true) or normalized:find("categories", 1, true) or normalized:find("public", 1, true)) then
            return false
        end
        if normalized:find("clear all", 1, true) or normalized:find("allow all", 1, true)
            or normalized:find("remove all", 1, true) or normalized:find("reset", 1, true)
            or normalized:find("every category", 1, true) or normalized:find("all categories", 1, true) then
            return false
        end
        local category = GroupAuraCategoryForAlias(normalized)
        if not category then return false end
        local value
        if normalized:find("allow", 1, true) or normalized:find("unblacklist", 1, true)
            or normalized:find("remove", 1, true) or normalized:find("clear", 1, true)
            or normalized:find("include", 1, true) then
            value = false
        elseif normalized:find("blacklist", 1, true) or normalized:find("hide", 1, true)
            or normalized:find("block", 1, true) or normalized:find("exclude", 1, true)
            or normalized:find("disable", 1, true) then
            value = true
        end
        if value == nil then return false end
        local scope, lane = GroupAuraCategoryScopeLane(normalized)
        return { scope = scope, lane = lane, category = category, value = value }, {
            summary = "Hides or allows a live group-aura category for the selected scope and lane.",
        }
    end

    local function ParseGroupAuraCategorySummaryAliasArgs(text)
        local normalized = AuraActionNormalized(text)
        if GroupAuraCategoryAliasBlocked(normalized) then return false end
        if not (normalized:find("summary", 1, true) or normalized:find("list", 1, true)
            or normalized:find("current", 1, true) or normalized:find("what is", 1, true)
            or (normalized:find("show", 1, true) and normalized:find("blacklist", 1, true))) then
            return false
        end
        local scope, lane = GroupAuraCategoryScopeLane(normalized)
        return { scope = scope, lane = lane }, {
            summary = "Shows the live hidden aura categories for the selected group-frame lane.",
        }
    end

    local function ParseGroupAuraCategoryClearAliasArgs(text)
        local normalized = AuraActionNormalized(text)
        if GroupAuraCategoryAliasBlocked(normalized) then return false end
        if not (normalized:find("clear all", 1, true) or normalized:find("allow all", 1, true)
            or normalized:find("unblacklist all", 1, true) or normalized:find("remove all", 1, true)
            or normalized:find("reset", 1, true)
            or ((normalized:find("clear", 1, true) or normalized:find("allow", 1, true)
                or normalized:find("remove", 1, true) or normalized:find("empty", 1, true))
                and (normalized:find("all categories", 1, true) or normalized:find("every category", 1, true)
                    or normalized:find("categories", 1, true)))) then
            return false
        end
        local scope, lane = GroupAuraCategoryScopeLane(normalized)
        return { scope = scope, lane = lane }, {
            summary = "Clears the live hidden-category list for the selected group-aura scope and lane.",
        }
    end

    local BuildGroupDirectActionParsers = Assistant.AurasRegistry and Assistant.AurasRegistry.BuildGroupDirectActionParsers
    if type(BuildGroupDirectActionParsers) ~= "function" then return nil end
    local DirectActionParsers = BuildGroupDirectActionParsers({
        A = Assistant,
        helpers = helpers,
    })
    if type(DirectActionParsers) ~= "table" then return nil end

    return {
        ParseGroupAuraCategorySetAliasArgs = ParseGroupAuraCategorySetAliasArgs,
        ParseGroupAuraCategorySummaryAliasArgs = ParseGroupAuraCategorySummaryAliasArgs,
        ParseGroupAuraCategoryClearAliasArgs = ParseGroupAuraCategoryClearAliasArgs,
        ParseGroupAuraDirectBlacklistAddSpellAliasArgs = DirectActionParsers.ParseGroupAuraDirectBlacklistAddSpellAliasArgs,
        ParseGroupAuraDirectBlacklistRemoveSpellAliasArgs = DirectActionParsers.ParseGroupAuraDirectBlacklistRemoveSpellAliasArgs,
        ParseGroupAuraDirectBlacklistClearAliasArgs = DirectActionParsers.ParseGroupAuraDirectBlacklistClearAliasArgs,
        ParseGroupAuraDirectBlacklistPresetAliasArgs = DirectActionParsers.ParseGroupAuraDirectBlacklistPresetAliasArgs,
        ParseGroupAuraDirectBlacklistSummaryAliasArgs = DirectActionParsers.ParseGroupAuraDirectBlacklistSummaryAliasArgs,
    }
end
