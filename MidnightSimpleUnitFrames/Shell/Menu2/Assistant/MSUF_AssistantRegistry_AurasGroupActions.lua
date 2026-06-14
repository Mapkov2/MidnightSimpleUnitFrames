local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- Group aura assistant action domain.
-- Depends on MSUF_AssistantRegistry_AurasActions.lua for shared alias helpers.
local ctx = A.AurasRegistry and A.AurasRegistry.Actions
local helpers = A.AurasRegistry and A.AurasRegistry.ActionHelpers or nil
if type(ctx) ~= "table" or type(helpers) ~= "table" then return end

local Registry = ctx.Registry
A = ctx.A or A
M = ctx.M or M
local AuraActionNormalized = helpers.AuraActionNormalized
local AuraActionContainsAny = helpers.AuraActionContainsAny
local AuraActionHasToken = helpers.AuraActionHasToken

if not (Registry and type(Registry.RegisterAction) == "function") then return end
if type(AuraActionNormalized) ~= "function" or type(AuraActionContainsAny) ~= "function" or type(AuraActionHasToken) ~= "function" then return end
local function GroupAuraCategoryHasUnitAuraScope(text)
    local P = A.Parser or {}
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
    local P = A.Parser or {}
    local normalized = AuraActionNormalized(text)
    local scope = type(P.AuraGroupBlacklistScope) == "function" and P.AuraGroupBlacklistScope(normalized) or nil
    local lane = type(P.AuraGroupBlacklistLane) == "function" and P.AuraGroupBlacklistLane(normalized) or nil
    scope = A.GroupAuraCategoryScope and A.GroupAuraCategoryScope(scope) or (scope or "raid")
    lane = A.GroupAuraCategoryLane and A.GroupAuraCategoryLane(lane) or (lane or "buff")
    return scope, lane
end

local function GroupAuraCategoryForAlias(text)
    local P = A.Parser or {}
    local normalized = AuraActionNormalized(text)
    local category = type(P.AuraGroupBlacklistCategoryForText) == "function" and P.AuraGroupBlacklistCategoryForText(normalized) or nil
    if not category and A.ResolveAuraGroupCategory then category = A.ResolveAuraGroupCategory(normalized) end
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
        summary = "Edits the group-frame public aura category blacklist through registered action metadata.",
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
        summary = "Shows the group-frame public aura category blacklist through registered action metadata.",
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
        summary = "Allows all public aura categories through registered action metadata.",
    }
end

local function DirectGroupAuraBlacklistBlocked(text)
    local normalized = AuraActionNormalized(text)
    return GroupAuraCategoryAliasBlocked(normalized)
        or GroupAuraCategoryHasUnitAuraScope(normalized)
        or normalized:find("category", 1, true) ~= nil
        or normalized:find("categories", 1, true) ~= nil
        or normalized:find("public category", 1, true) ~= nil
        or normalized:find("public categories", 1, true) ~= nil
end

local function HasDirectGroupAuraBlacklistScope(text)
    local P = A.Parser or {}
    local normalized = AuraActionNormalized(text)
    local phrases = {
        "group aura", "group auras", "group frame aura", "group frame auras",
        "party aura", "party auras", "party buff", "party buffs", "party debuff", "party debuffs",
        "raid aura", "raid auras", "raid buff", "raid buffs", "raid debuff", "raid debuffs",
        "mythic raid aura", "mythic raid auras", "mythic raid buff", "mythic raid buffs",
        "group aura blacklist", "party aura blacklist", "raid aura blacklist",
        "party buff blacklist", "party debuff blacklist", "raid buff blacklist", "raid debuff blacklist",
        "for party", "on party", "for raid", "on raid",
    }
    if type(P.ContainsAny) == "function" then return P.ContainsAny(normalized, phrases) end
    for i = 1, #phrases do
        if normalized:find(phrases[i], 1, true) then return true end
    end
    return false
end

local function DirectGroupAuraBlacklistScopeLane(text)
    local P = A.Parser or {}
    local normalized = AuraActionNormalized(text)
    local scope = type(P.AuraGroupBlacklistScope) == "function" and P.AuraGroupBlacklistScope(normalized) or nil
    local lane = type(P.AuraGroupBlacklistLane) == "function" and P.AuraGroupBlacklistLane(normalized) or nil
    scope = A.GroupAuraCategoryScope and A.GroupAuraCategoryScope(scope) or (scope or "raid")
    lane = A.GroupAuraCategoryLane and A.GroupAuraCategoryLane(lane) or (lane or "buff")
    return scope, lane
end

local function DirectGroupAuraBlacklistIntent(text)
    if DirectGroupAuraBlacklistBlocked(text) then return false end
    if not HasDirectGroupAuraBlacklistScope(text) then return false end
    local normalized = AuraActionNormalized(text)
    if not (normalized:find("blacklist", 1, true) ~= nil
        or normalized:find("blacklisted", 1, true) ~= nil
        or normalized:find("aura", 1, true) ~= nil
        or normalized:find("buff", 1, true) ~= nil
        or normalized:find("debuff", 1, true) ~= nil
        or normalized:find("spell", 1, true) ~= nil) then
        return false
    end
    return normalized:find("blacklist", 1, true) ~= nil
        or normalized:find("blacklisted", 1, true) ~= nil
        or normalized:find("blocked", 1, true) ~= nil
        or normalized:find("block", 1, true) ~= nil
        or normalized:find("ignore", 1, true) ~= nil
        or normalized:find("allow", 1, true) ~= nil
        or normalized:find("remove", 1, true) ~= nil
        or normalized:find("clear", 1, true) ~= nil
        or normalized:find("reset", 1, true) ~= nil
        or normalized:find("unblacklist", 1, true) ~= nil
        or normalized:find("unblock", 1, true) ~= nil
        or normalized:find("hide", 1, true) ~= nil
end

local function ParseGroupAuraDirectBlacklistSpellAliasArgs(text, raw)
    if not DirectGroupAuraBlacklistIntent(text) then return false end
    local normalized = AuraActionNormalized(text)
    if normalized:find("all spells", 1, true) or normalized:find("all auras", 1, true)
        or normalized:find("every spell", 1, true) or normalized:find("every aura", 1, true)
        or normalized:find("clear all", 1, true) or normalized:find("allow all", 1, true)
        or normalized:find("remove all", 1, true) or normalized:find("delete all", 1, true) then
        return false
    end
    local P = A.Parser or {}
    local value = type(P.AuraBlacklistSpellValue) == "function" and P.AuraBlacklistSpellValue(raw or text) or nil
    if type(value) ~= "string" or value == "" then return false end
    local scope, lane = DirectGroupAuraBlacklistScopeLane(normalized)
    return { scope = scope, lane = lane, value = value }, {
        summary = "Edits the direct group-frame aura blacklist through registered action metadata.",
    }
end

local function ParseGroupAuraDirectBlacklistAddSpellAliasArgs(text, raw)
    local normalized = AuraActionNormalized(text)
    if normalized:find("remove", 1, true) or normalized:find("delete", 1, true)
        or normalized:find("allow", 1, true) or normalized:find("unblacklist", 1, true)
        or normalized:find("unblock", 1, true) or normalized:find("unhide", 1, true)
        or normalized:find("clear", 1, true) or normalized:find("reset", 1, true) then
        return false
    end
    local P = A.Parser or {}
    if normalized:find("preset", 1, true)
        and type(P.AuraBlacklistPresetForText) == "function"
        and P.AuraBlacklistPresetForText(normalized) then
        return false
    end
    return ParseGroupAuraDirectBlacklistSpellAliasArgs(text, raw)
end

local function ParseGroupAuraDirectBlacklistRemoveSpellAliasArgs(text, raw)
    local normalized = AuraActionNormalized(text)
    if not (normalized:find("remove", 1, true) or normalized:find("delete", 1, true)
        or normalized:find("allow", 1, true) or normalized:find("unblacklist", 1, true)
        or normalized:find("unblock", 1, true) or normalized:find("unhide", 1, true)) then
        return false
    end
    return ParseGroupAuraDirectBlacklistSpellAliasArgs(text, raw)
end

local function ParseGroupAuraDirectBlacklistClearAliasArgs(text)
    if not DirectGroupAuraBlacklistIntent(text) then return false end
    local normalized = AuraActionNormalized(text)
    if not (normalized:find("clear all", 1, true) or normalized:find("allow all", 1, true)
        or normalized:find("unblacklist all", 1, true) or normalized:find("remove all", 1, true)
        or normalized:find("delete all", 1, true) or normalized:find("reset", 1, true)
        or normalized:find("empty", 1, true)
        or ((normalized:find("clear", 1, true) or normalized:find("allow", 1, true)
            or normalized:find("remove", 1, true) or normalized:find("delete", 1, true))
            and (normalized:find("all spells", 1, true) or normalized:find("every spell", 1, true)
                or normalized:find("all auras", 1, true) or normalized:find("every aura", 1, true)))) then
        return false
    end
    local scope, lane = DirectGroupAuraBlacklistScopeLane(normalized)
    return { scope = scope, lane = lane }, {
        summary = "Allows all direct spell entries through registered action metadata.",
    }
end

local function ParseGroupAuraDirectBlacklistPresetAliasArgs(text)
    if not DirectGroupAuraBlacklistIntent(text) then return false end
    local normalized = AuraActionNormalized(text)
    if AuraActionContainsAny(normalized, { "show", "list", "summary", "current", "what is", "whats" }) then return false end
    if normalized:find("remove", 1, true) or normalized:find("delete", 1, true)
        or normalized:find("allow", 1, true) or normalized:find("unblacklist", 1, true)
        or normalized:find("unblock", 1, true) or normalized:find("clear", 1, true)
        or AuraActionHasToken(normalized, "reset") or normalized:find("empty", 1, true)
        or normalized:find("all spells", 1, true) or normalized:find("all auras", 1, true)
        or normalized:find("every spell", 1, true) or normalized:find("every aura", 1, true) then
        return false
    end
    local P = A.Parser or {}
    local preset = type(P.AuraBlacklistPresetForText) == "function" and P.AuraBlacklistPresetForText(normalized) or nil
    if not preset then return false end
    if not (normalized:find("preset", 1, true) or normalized:find("blacklist", 1, true)
        or normalized:find("ignore", 1, true) or normalized:find("block", 1, true)) then
        return false
    end
    local scope, lane = DirectGroupAuraBlacklistScopeLane(normalized)
    return { scope = scope, lane = lane, preset = preset }, {
        summary = "Adds a curated direct group-frame aura blacklist preset through registered action metadata.",
    }
end

local function ParseGroupAuraDirectBlacklistSummaryAliasArgs(text)
    local normalized = AuraActionNormalized(text)
    if DirectGroupAuraBlacklistBlocked(normalized) then return false end
    if not HasDirectGroupAuraBlacklistScope(normalized) then return false end
    if not (normalized:find("summary", 1, true) or normalized:find("list", 1, true)
        or normalized:find("current", 1, true) or normalized:find("what is", 1, true)
        or (normalized:find("show", 1, true) and normalized:find("blacklist", 1, true))) then
        return false
    end
    if not (normalized:find("blacklist", 1, true) or normalized:find("blacklisted", 1, true)
        or normalized:find("blocked", 1, true) or normalized:find("ignore", 1, true)) then
        return false
    end
    local scope, lane = DirectGroupAuraBlacklistScopeLane(normalized)
    return { scope = scope, lane = lane }, {
        summary = "Shows the direct group-frame aura blacklist through registered action metadata.",
    }
end

Registry:RegisterAction({
    key = "aura_group_category_blacklist_set",
    label = "Set Group Aura Category Blacklist",
    type = "auras",
    combatSafe = false,
    captureSnapshot = true,
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
        if not catKey then return false, "I need a known public aura category." end
        local value = args and args.value == true
        local changed = A.WriteGroupAuraCategoryState(scope, lane, catKey, value)
        A.ApplyGroupAuraCategory(scope)
        local verb = value and "blacklisted" or "allowed"
        local prefix = changed and "Done. " or "Already set. "
        return true, prefix .. A.AuraGroupCategoryLabel(catKey) .. " is " .. verb .. " for " .. A.GroupAuraCategoryScopeLabel(scope) .. " " .. A.GroupAuraCategoryLanePlural(lane) .. "."
    end,
})

Registry:RegisterAction({
    key = "aura_group_category_blacklist_summary",
    label = "Show Group Aura Category Blacklist",
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
        return true, A.GroupAuraCategoryScopeLabel(scope) .. " " .. A.GroupAuraCategoryLanePlural(lane) .. " category blacklist:\n" .. A.GroupAuraCategorySummary(scope, lane)
    end,
})

Registry:RegisterAction({
    key = "aura_group_category_blacklist_clear",
    label = "Clear Group Aura Category Blacklist",
    type = "auras",
    combatSafe = false,
    captureSnapshot = true,
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
        local count = A.ClearGroupAuraCategoryBlacklist and A.ClearGroupAuraCategoryBlacklist(scope, lane) or 0
        local target = A.GroupAuraCategoryScopeLabel(scope) .. " " .. A.GroupAuraCategoryLanePlural(lane)
        if count and count > 0 then
            return true, "Done. Allowed all public aura categories for " .. target .. ". Cleared " .. tostring(count) .. " category blacklist " .. (count == 1 and "entry." or "entries.")
        end
        return true, "Already set. No public aura categories are blacklisted for " .. target .. "."
    end,
})

Registry:RegisterAction({
    key = "aura_group_blacklist_add_spell",
    label = "Add Group Aura Blacklist Spell",
    type = "auras",
    combatSafe = false,
    captureSnapshot = true,
    aliases = {
        "blacklist", "hide", "block", "ignore",
        "blacklist group aura spell", "blacklist group frame aura spell",
        "blacklist party aura spell", "blacklist raid aura spell",
        "hide group aura spell", "hide party aura spell", "hide raid aura spell",
        "block group aura spell", "block party aura spell", "block raid aura spell",
    },
    parseAliasArgs = ParseGroupAuraDirectBlacklistAddSpellAliasArgs,
    run = function(args)
        local scope = A.GroupAuraCategoryScope(args and args.scope)
        local lane = A.GroupAuraCategoryLane(args and args.lane)
        local value = args and args.value
        if type(value) ~= "string" or value == "" then return false, "I need a spell ID, spell link, or resolvable spell name." end
        if not A.AddGroupAuraBlacklistSpell(scope, lane, value) then return false, "That spell could not be resolved for the group aura blacklist." end
        A.ApplyGroupAuraCategory(scope)
        return true, "Done. Added " .. tostring(value) .. " to the " .. A.GroupAuraCategoryScopeLabel(scope) .. " " .. A.GroupAuraCategoryLanePlural(lane) .. " blacklist."
    end,
})

Registry:RegisterAction({
    key = "aura_group_blacklist_remove_spell",
    label = "Remove Group Aura Blacklist Spell",
    type = "auras",
    combatSafe = false,
    captureSnapshot = true,
    aliases = {
        "remove", "allow", "unblacklist", "unblock", "unhide",
        "remove group aura blacklist spell", "remove group frame aura blacklist spell",
        "allow group aura spell", "allow party aura spell", "allow raid aura spell",
        "unblacklist group aura spell", "unblacklist party aura spell", "unblacklist raid aura spell",
        "show group aura spell", "show party aura spell", "show raid aura spell",
    },
    parseAliasArgs = ParseGroupAuraDirectBlacklistRemoveSpellAliasArgs,
    run = function(args)
        local scope = A.GroupAuraCategoryScope(args and args.scope)
        local lane = A.GroupAuraCategoryLane(args and args.lane)
        local value = args and args.value
        if type(value) ~= "string" or value == "" then return false, "I need a spell ID, spell link, or resolvable spell name." end
        A.RemoveGroupAuraBlacklistSpell(scope, lane, value)
        A.ApplyGroupAuraCategory(scope)
        return true, "Done. Removed " .. tostring(value) .. " from the " .. A.GroupAuraCategoryScopeLabel(scope) .. " " .. A.GroupAuraCategoryLanePlural(lane) .. " blacklist."
    end,
})

Registry:RegisterAction({
    key = "aura_group_blacklist_clear_spells",
    label = "Clear Group Aura Blacklist",
    type = "auras",
    combatSafe = false,
    captureSnapshot = true,
    aliases = {
        "clear", "clear all", "allow all", "remove all", "reset",
        "clear group aura blacklist", "clear group frame aura blacklist",
        "clear party aura blacklist", "clear raid aura blacklist",
        "allow all group aura spells", "allow all party aura spells", "allow all raid aura spells",
        "remove all group aura blacklist spells", "remove all party aura blacklist spells", "remove all raid aura blacklist spells",
    },
    parseAliasArgs = ParseGroupAuraDirectBlacklistClearAliasArgs,
    run = function(args)
        local scope = A.GroupAuraCategoryScope(args and args.scope)
        local lane = A.GroupAuraCategoryLane(args and args.lane)
        local count = A.ClearGroupAuraBlacklistSpells(scope, lane)
        A.ApplyGroupAuraCategory(scope)
        local target = A.GroupAuraCategoryScopeLabel(scope) .. " " .. A.GroupAuraCategoryLanePlural(lane)
        if count and count > 0 then
            return true, "Done. Allowed all direct spell blacklist entries for " .. target .. ". Cleared " .. tostring(count) .. " blacklisted " .. (count == 1 and "spell." or "spells.")
        end
        return true, "Already set. No direct spells are blacklisted for " .. target .. "."
    end,
})

Registry:RegisterAction({
    key = "aura_group_blacklist_add_preset",
    label = "Add Group Aura Blacklist Preset",
    type = "auras",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    aliases = {
        "group aura blacklist preset", "group frame aura blacklist preset",
        "party aura blacklist preset", "raid aura blacklist preset",
        "blacklist preset for group auras", "blacklist preset for party auras", "blacklist preset for raid auras",
        "aura blacklist preset", "add aura blacklist preset", "blacklist aura preset", "add blacklist preset",
    },
    parseAliasArgs = ParseGroupAuraDirectBlacklistPresetAliasArgs,
    run = function(args)
        local scope = A.GroupAuraCategoryScope(args and args.scope)
        local lane = A.GroupAuraCategoryLane(args and args.lane)
        local preset = args and args.preset
        if type(preset) ~= "string" or preset == "" then return false, "I need an aura blacklist preset name." end
        local count = A.AddGroupAuraBlacklistPreset(scope, lane, preset)
        A.ApplyGroupAuraCategory(scope)
        return true, "Done. Added " .. tostring(count or 0) .. " preset spells to the " .. A.GroupAuraCategoryScopeLabel(scope) .. " " .. A.GroupAuraCategoryLanePlural(lane) .. " blacklist."
    end,
})

Registry:RegisterAction({
    key = "aura_group_blacklist_summary",
    label = "Show Group Aura Blacklist",
    type = "auras",
    combatSafe = true,
    aliases = {
        "show group aura blacklist", "show group frame aura blacklist",
        "list group aura blacklist", "list party aura blacklist", "list raid aura blacklist",
        "current group aura blacklist", "current party aura blacklist", "current raid aura blacklist",
        "show aura blacklist", "list aura blacklist", "current aura blacklist",
        "show party buff aura blacklist", "show party debuff aura blacklist",
        "show raid buff aura blacklist", "show raid debuff aura blacklist",
        "show party buff blacklist", "show party debuff blacklist",
        "show raid buff blacklist", "show raid debuff blacklist",
        "list party buff aura blacklist", "list party debuff aura blacklist",
        "list raid buff aura blacklist", "list raid debuff aura blacklist",
        "list party buff blacklist", "list party debuff blacklist",
        "list raid buff blacklist", "list raid debuff blacklist",
        "current party buff aura blacklist", "current party debuff aura blacklist",
        "current raid buff aura blacklist", "current raid debuff aura blacklist",
        "current party buff blacklist", "current party debuff blacklist",
        "current raid buff blacklist", "current raid debuff blacklist",
    },
    parseAliasArgs = ParseGroupAuraDirectBlacklistSummaryAliasArgs,
    run = function(args)
        local scope = A.GroupAuraCategoryScope(args and args.scope)
        local lane = A.GroupAuraCategoryLane(args and args.lane)
        return true, A.GroupAuraCategoryScopeLabel(scope) .. " " .. A.GroupAuraCategoryLanePlural(lane) .. " blacklist:\n" .. tostring(A.GroupAuraBlacklistSummary(scope, lane))
    end,
})
