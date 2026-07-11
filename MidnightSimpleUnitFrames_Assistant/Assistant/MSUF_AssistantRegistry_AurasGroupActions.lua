local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- Group aura assistant action domain.
-- Depends on AurasActions for shared alias helpers and AurasGroupActions_Parsers for parse helpers.
local registryNS = A.AurasRegistry
local ctx = registryNS and registryNS.Actions
local helpers = registryNS and registryNS.ActionHelpers or nil
if type(ctx) ~= "table" or type(helpers) ~= "table" then return end

local Registry = ctx.Registry
A = ctx.A or A
M = ctx.M or M

if not (Registry and type(Registry.RegisterAction) == "function") then return end

local BuildGroupActionParsers = (A.AurasRegistry and A.AurasRegistry.BuildGroupActionParsers)
    or (registryNS and registryNS.BuildGroupActionParsers)
local GroupActionParsers = type(BuildGroupActionParsers) == "function" and BuildGroupActionParsers({
    A = A,
    helpers = helpers,
}) or nil
if type(GroupActionParsers) ~= "table" then return end

local ParseGroupAuraCategorySetAliasArgs = GroupActionParsers.ParseGroupAuraCategorySetAliasArgs
local ParseGroupAuraCategorySummaryAliasArgs = GroupActionParsers.ParseGroupAuraCategorySummaryAliasArgs
local ParseGroupAuraCategoryClearAliasArgs = GroupActionParsers.ParseGroupAuraCategoryClearAliasArgs
local ParseGroupAuraDirectBlacklistAddSpellAliasArgs = GroupActionParsers.ParseGroupAuraDirectBlacklistAddSpellAliasArgs
local ParseGroupAuraDirectBlacklistRemoveSpellAliasArgs = GroupActionParsers.ParseGroupAuraDirectBlacklistRemoveSpellAliasArgs
local ParseGroupAuraDirectBlacklistClearAliasArgs = GroupActionParsers.ParseGroupAuraDirectBlacklistClearAliasArgs
local ParseGroupAuraDirectBlacklistPresetAliasArgs = GroupActionParsers.ParseGroupAuraDirectBlacklistPresetAliasArgs
local ParseGroupAuraDirectBlacklistSummaryAliasArgs = GroupActionParsers.ParseGroupAuraDirectBlacklistSummaryAliasArgs

local function GroupCategoryTarget(scope, lane)
    return A.GroupAuraCategoryScopeLabel(scope) .. " " .. A.GroupAuraCategoryLanePlural(lane)
end

Registry:RegisterAction({
    key = "aura_group_category_blacklist_set",
    label = "Set Hidden Group Aura Category",
    type = "auras",
    combatSafe = true,
    aliases = {
        "blacklist", "allow", "hide", "block", "exclude", "include",
        "category blacklist", "public category blacklist", "blacklist category",
        "blacklisted category", "blacklist public category", "allow category",
        "unblacklist category", "remove category blacklist",
        "raid buff category blacklist", "raid debuff category blacklist",
        "party buff category blacklist", "party debuff category blacklist",
    },
    parseAliasArgs = ParseGroupAuraCategorySetAliasArgs,
    run = function(args)
        local scope = A.GroupAuraCategoryScope(args and args.scope)
        local lane = A.GroupAuraCategoryLane(args and args.lane)
        local catKey = A.ResolveAuraGroupCategory(args and args.category)
        if not catKey then return false, "Which aura category do you want me to hide or allow?" end
        local value = args and args.value == true
        local changed = A.WriteGroupAuraCategoryState(scope, lane, catKey, value)
        if changed and type(A.ApplyGroupAuraCategory) == "function" then A.ApplyGroupAuraCategory(scope) end
        local verb = value and "Hidden " or "Allowed "
        return true, (changed and "Done. " or "Already set. ") .. verb .. A.AuraGroupCategoryLabel(catKey) .. " for " .. GroupCategoryTarget(scope, lane) .. ".", not changed and { noChange = true } or nil
    end,
})

Registry:RegisterAction({
    key = "aura_group_category_blacklist_summary",
    label = "Show Hidden Group Aura Categories",
    type = "auras",
    combatSafe = true,
    aliases = {
        "show category blacklist", "show public category blacklist",
        "category blacklist summary", "public category blacklist summary",
        "list category blacklist", "current category blacklist",
        "show raid buff category blacklist", "show party debuff category blacklist",
        "list raid buff category blacklist", "list raid debuff category blacklist",
        "list party buff category blacklist", "list party debuff category blacklist",
        "current raid buff category blacklist", "current raid debuff category blacklist",
        "current party buff category blacklist", "current party debuff category blacklist",
    },
    parseAliasArgs = ParseGroupAuraCategorySummaryAliasArgs,
    run = function(args)
        local scope = A.GroupAuraCategoryScope(args and args.scope)
        local lane = A.GroupAuraCategoryLane(args and args.lane)
        return true, "Hidden categories for " .. GroupCategoryTarget(scope, lane) .. ":\n" .. A.GroupAuraCategorySummary(scope, lane)
    end,
})

Registry:RegisterAction({
    key = "aura_group_category_blacklist_clear",
    label = "Clear Hidden Group Aura Categories",
    type = "auras",
    combatSafe = true,
    confirmRequired = true,
    aliases = {
        "clear category blacklist", "clear all category blacklist",
        "allow all categories", "allow all public categories",
        "allow all aura categories", "allow all public aura categories",
        "remove all category blacklist", "reset category blacklist",
        "clear all raid buff category blacklist", "clear all party debuff category blacklist",
        "reset raid buff category blacklist", "reset raid debuff category blacklist",
        "reset party buff category blacklist", "reset party debuff category blacklist",
        "allow all raid buff categories", "allow all party debuff categories",
    },
    parseAliasArgs = ParseGroupAuraCategoryClearAliasArgs,
    run = function(args)
        local scope = A.GroupAuraCategoryScope(args and args.scope)
        local lane = A.GroupAuraCategoryLane(args and args.lane)
        local count = tonumber(A.ClearGroupAuraCategoryBlacklist(scope, lane)) or 0
        return true, count > 0 and ("Done. Cleared " .. tostring(count) .. " hidden categories for " .. GroupCategoryTarget(scope, lane) .. ".") or "Already empty.", count == 0 and { noChange = true } or nil
    end,
})

local RegisterGroupDirectBlacklistActions = (A.AurasRegistry and A.AurasRegistry.RegisterGroupDirectBlacklistActions)
    or (registryNS and registryNS.RegisterGroupDirectBlacklistActions)
if type(RegisterGroupDirectBlacklistActions) == "function" then
    RegisterGroupDirectBlacklistActions({
        Registry = Registry,
        A = A,
        ParseGroupAuraDirectBlacklistAddSpellAliasArgs = ParseGroupAuraDirectBlacklistAddSpellAliasArgs,
        ParseGroupAuraDirectBlacklistRemoveSpellAliasArgs = ParseGroupAuraDirectBlacklistRemoveSpellAliasArgs,
        ParseGroupAuraDirectBlacklistClearAliasArgs = ParseGroupAuraDirectBlacklistClearAliasArgs,
        ParseGroupAuraDirectBlacklistPresetAliasArgs = ParseGroupAuraDirectBlacklistPresetAliasArgs,
        ParseGroupAuraDirectBlacklistSummaryAliasArgs = ParseGroupAuraDirectBlacklistSummaryAliasArgs,
    })
end
