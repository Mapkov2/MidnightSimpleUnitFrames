-- Direct group aura blacklist assistant action registrations.
-- Loaded before MSUF_AssistantRegistry_AurasGroupActions.lua; the main action file passes parser helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.RegisterGroupDirectBlacklistActions(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local Assistant = ctx.A or A
    local ParseGroupAuraDirectBlacklistAddSpellAliasArgs = ctx.ParseGroupAuraDirectBlacklistAddSpellAliasArgs
    local ParseGroupAuraDirectBlacklistRemoveSpellAliasArgs = ctx.ParseGroupAuraDirectBlacklistRemoveSpellAliasArgs
    local ParseGroupAuraDirectBlacklistClearAliasArgs = ctx.ParseGroupAuraDirectBlacklistClearAliasArgs
    local ParseGroupAuraDirectBlacklistPresetAliasArgs = ctx.ParseGroupAuraDirectBlacklistPresetAliasArgs
    local ParseGroupAuraDirectBlacklistSummaryAliasArgs = ctx.ParseGroupAuraDirectBlacklistSummaryAliasArgs

    if not (Registry and type(Registry.RegisterAction) == "function") then return end
    if type(ParseGroupAuraDirectBlacklistAddSpellAliasArgs) ~= "function" or type(ParseGroupAuraDirectBlacklistRemoveSpellAliasArgs) ~= "function" then return end
    if type(ParseGroupAuraDirectBlacklistClearAliasArgs) ~= "function" or type(ParseGroupAuraDirectBlacklistPresetAliasArgs) ~= "function" then return end
    if type(ParseGroupAuraDirectBlacklistSummaryAliasArgs) ~= "function" then return end

    local function Apply(scope)
        if type(Assistant.ApplyGroupAuraCategory) == "function" then Assistant.ApplyGroupAuraCategory(scope) end
    end

    local function Target(scope, lane)
        return Assistant.GroupAuraCategoryScopeLabel(scope) .. " " .. Assistant.GroupAuraCategoryLanePlural(lane)
    end

    local function RestrictionNote()
        return " Blizzard may reject exact harmful-aura filters on friendly units and exact helpful-aura filters on hostile units."
    end

    Registry:RegisterAction({
        key = "aura_group_blacklist_add_spell",
        label = "Hide Group Aura Spell",
        type = "auras",
        combatSafe = true,
        aliases = {
            "blacklist", "hide", "block", "ignore",
            "blacklist group aura spell", "blacklist group frame aura spell",
            "blacklist party aura spell", "blacklist raid aura spell",
            "hide group aura spell", "hide party aura spell", "hide raid aura spell",
            "block group aura spell", "block party aura spell", "block raid aura spell",
        },
        parseAliasArgs = ParseGroupAuraDirectBlacklistAddSpellAliasArgs,
        run = function(args)
            local scope = Assistant.GroupAuraCategoryScope(args and args.scope)
            local lane = Assistant.GroupAuraCategoryLane(args and args.lane)
            local value = args and args.value
            if type(value) ~= "string" or value == "" then return false, "Which spell do you want me to use? A spell ID, spell link, or full spell name is enough." end
            local changed = Assistant.AddGroupAuraBlacklistSpell(scope, lane, value)
            if changed then Apply(scope) end
            return true, (changed and "Done. Hidden " or "Already set. ") .. tostring(value) .. " for " .. Target(scope, lane) .. "." .. RestrictionNote(), not changed and { noChange = true } or nil
        end,
    })

    Registry:RegisterAction({
        key = "aura_group_blacklist_remove_spell",
        label = "Allow Hidden Group Aura Spell",
        type = "auras",
        combatSafe = true,
        aliases = {
            "remove", "allow", "unblacklist", "unblock", "unhide",
            "remove group aura blacklist spell", "remove group frame aura blacklist spell",
            "allow group aura spell", "allow party aura spell", "allow raid aura spell",
            "unblacklist group aura spell", "unblacklist party aura spell", "unblacklist raid aura spell",
            "show group aura spell", "show party aura spell", "show raid aura spell",
        },
        parseAliasArgs = ParseGroupAuraDirectBlacklistRemoveSpellAliasArgs,
        run = function(args)
            local scope = Assistant.GroupAuraCategoryScope(args and args.scope)
            local lane = Assistant.GroupAuraCategoryLane(args and args.lane)
            local value = args and args.value
            if type(value) ~= "string" or value == "" then return false, "Which spell do you want me to use? A spell ID, spell link, or full spell name is enough." end
            local changed = Assistant.RemoveGroupAuraBlacklistSpell(scope, lane, value)
            if changed then Apply(scope) end
            return true, (changed and "Done. Allowed " or "Already allowed. ") .. tostring(value) .. " for " .. Target(scope, lane) .. ".", not changed and { noChange = true } or nil
        end,
    })

    Registry:RegisterAction({
        key = "aura_group_blacklist_clear_spells",
        label = "Clear Hidden Group Aura Spells",
        type = "auras",
        combatSafe = true,
        confirmRequired = true,
        aliases = {
            "clear", "clear all", "allow all", "remove all", "reset",
            "clear group aura blacklist", "clear group frame aura blacklist",
            "clear party aura blacklist", "clear raid aura blacklist",
            "allow all group aura spells", "allow all party aura spells", "allow all raid aura spells",
            "remove all group aura blacklist spells", "remove all party aura blacklist spells", "remove all raid aura blacklist spells",
        },
        parseAliasArgs = ParseGroupAuraDirectBlacklistClearAliasArgs,
        run = function(args)
            local scope = Assistant.GroupAuraCategoryScope(args and args.scope)
            local lane = Assistant.GroupAuraCategoryLane(args and args.lane)
            local count = tonumber(Assistant.ClearGroupAuraBlacklistSpells(scope, lane)) or 0
            if count > 0 then Apply(scope) end
            return true, count > 0 and ("Done. Cleared " .. tostring(count) .. " hidden aura entries for " .. Target(scope, lane) .. ".") or "Already empty.", count == 0 and { noChange = true } or nil
        end,
    })

    Registry:RegisterAction({
        key = "aura_group_blacklist_add_preset",
        label = "Add Hidden Group Aura Preset",
        type = "auras",
        combatSafe = true,
        aliases = {
            "group aura blacklist preset", "group frame aura blacklist preset",
            "party aura blacklist preset", "raid aura blacklist preset",
            "blacklist preset for group auras", "blacklist preset for party auras", "blacklist preset for raid auras",
            "aura blacklist preset", "add aura blacklist preset", "blacklist aura preset", "add blacklist preset",
        },
        parseAliasArgs = ParseGroupAuraDirectBlacklistPresetAliasArgs,
        run = function(args)
            local scope = Assistant.GroupAuraCategoryScope(args and args.scope)
            local lane = Assistant.GroupAuraCategoryLane(args and args.lane)
            local preset = args and args.preset
            if type(preset) ~= "string" or preset == "" then return false, "Which hidden-aura preset do you want me to use?" end
            local count = tonumber(Assistant.AddGroupAuraBlacklistPreset(scope, lane, preset)) or 0
            if count > 0 then Apply(scope) end
            return true, count > 0 and ("Done. Added " .. tostring(count) .. " missing SpellIDs from " .. tostring(preset) .. " for " .. Target(scope, lane) .. "." .. RestrictionNote()) or "Already set. That preset added no new SpellIDs.", count == 0 and { noChange = true } or nil
        end,
    })

    Registry:RegisterAction({
        key = "aura_group_blacklist_summary",
        label = "Show Hidden Group Aura Spells",
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
            local scope = Assistant.GroupAuraCategoryScope(args and args.scope)
            local lane = Assistant.GroupAuraCategoryLane(args and args.lane)
            return true, Target(scope, lane) .. " blacklist:\n" .. tostring(Assistant.GroupAuraBlacklistSummary(scope, lane))
        end,
    })
end
