-- Aura blacklist assistant action registrations.
-- Loaded before MSUF_AssistantRegistry_AurasActions.lua; the main action file passes parser helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.RegisterBlacklistActions(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local AuraModel = ctx.AuraModel
    local ApplyAura = ctx.ApplyAura
    local AuraScopeLabel = ctx.AuraScopeLabel
    local ParseAuraBlacklistAddSpellAliasArgs = ctx.ParseAuraBlacklistAddSpellAliasArgs
    local ParseAuraBlacklistRemoveSpellAliasArgs = ctx.ParseAuraBlacklistRemoveSpellAliasArgs
    local ParseAuraBlacklistClearAliasArgs = ctx.ParseAuraBlacklistClearAliasArgs
    local ParseAuraBlacklistPresetAliasArgs = ctx.ParseAuraBlacklistPresetAliasArgs
    local ParseAuraBlacklistSummaryAliasArgs = ctx.ParseAuraBlacklistSummaryAliasArgs
    local RegisterBlacklistSummaryAction = A.AurasRegistry and A.AurasRegistry.RegisterBlacklistSummaryAction

    if not (Registry and type(Registry.RegisterAction) == "function") then return end
    if type(AuraModel) ~= "function" or type(ApplyAura) ~= "function" or type(AuraScopeLabel) ~= "function" then return end
    if type(ParseAuraBlacklistAddSpellAliasArgs) ~= "function" or type(ParseAuraBlacklistRemoveSpellAliasArgs) ~= "function" then return end
    if type(ParseAuraBlacklistClearAliasArgs) ~= "function" or type(ParseAuraBlacklistPresetAliasArgs) ~= "function" then return end
    if type(ParseAuraBlacklistSummaryAliasArgs) ~= "function" or type(RegisterBlacklistSummaryAction) ~= "function" then return end

    Registry:RegisterAction({
        key = "aura_blacklist_add_spell",
        label = "Hide Aura Spell",
        type = "auras",
        combatSafe = false,
        captureSnapshot = true,
        aliases = {
            "blacklist", "blacklist spell", "blacklist aura", "blacklist aura spell",
            "block aura", "block aura spell", "ignore aura", "ignore aura spell",
            "hide", "suppress", "stop showing",
            "hide aura", "hide aura spell", "hide spell", "suppress aura", "suppress spell",
            "stop showing aura", "stop showing spell",
        },
        parseAliasArgs = ParseAuraBlacklistAddSpellAliasArgs,
        run = function(args)
            local Model = AuraModel()
            if not (Model and type(Model.AddBlacklistSpell) == "function") then return false, "Open Aura Filters first so I can change hidden auras." end
            local scope = args and args.scope or "shared"
            local value = args and args.value
            if type(value) ~= "string" or value == "" then return false, "Which spell do you want me to use? A spell ID, spell link, or full spell name is enough." end
            if not Model.AddBlacklistSpell(scope, value) then return false, "I don't recognize that spell yet. A spell ID or full spell name is enough." end
            ApplyAura(scope, "MSUF_ASSISTANT_AURA_BLACKLIST_ADD")
            return true, "Done. " .. tostring(value) .. " is now hidden for " .. AuraScopeLabel(scope) .. " auras."
        end,
    })

    Registry:RegisterAction({
        key = "aura_blacklist_remove_spell",
        label = "Allow Hidden Aura Spell",
        type = "auras",
        combatSafe = false,
        captureSnapshot = true,
        aliases = {
            "remove", "allow",
            "remove aura blacklist spell", "remove spell from aura blacklist",
            "allow aura spell", "allow spell", "allow aura",
            "unblacklist", "unblacklist spell", "unblacklist aura",
            "unblock aura", "unblock spell",
            "unhide", "stop hiding", "show", "let",
            "unhide aura", "unhide spell", "stop hiding aura", "stop hiding spell",
            "show aura again", "show spell again", "let aura show", "let spell show",
        },
        parseAliasArgs = ParseAuraBlacklistRemoveSpellAliasArgs,
        run = function(args)
            local Model = AuraModel()
            if not (Model and type(Model.RemoveBlacklistSpell) == "function") then return false, "Open Aura Filters first so I can change hidden auras." end
            local scope = args and args.scope or "shared"
            local value = args and args.value
            if type(value) ~= "string" or value == "" then return false, "Which spell do you want me to use? A spell ID, spell link, or full spell name is enough." end
            Model.RemoveBlacklistSpell(scope, value)
            ApplyAura(scope, "MSUF_ASSISTANT_AURA_BLACKLIST_REMOVE")
            return true, "Done. " .. tostring(value) .. " can show again for " .. AuraScopeLabel(scope) .. " auras."
        end,
    })

    Registry:RegisterAction({
        key = "aura_blacklist_clear_spells",
        label = "Clear Hidden Aura Spells",
        type = "auras",
        combatSafe = false,
        captureSnapshot = true,
        aliases = {
            "clear aura blacklist", "clear all aura blacklist", "allow all aura blacklist",
            "allow all aura blacklist spells", "remove all aura blacklist spells",
            "empty aura blacklist", "reset aura blacklist", "delete all aura blacklist spells",
            "clear player aura blacklist", "clear target aura blacklist", "clear focus aura blacklist", "clear boss aura blacklist",
            "empty player aura blacklist", "empty target aura blacklist", "empty focus aura blacklist", "empty boss aura blacklist",
            "reset player aura blacklist", "reset target aura blacklist", "reset focus aura blacklist", "reset boss aura blacklist",
            "allow all player aura blacklist spells", "allow all target aura blacklist spells",
            "allow all focus aura blacklist spells", "allow all boss aura blacklist spells",
            "delete all player aura blacklist spells", "delete all target aura blacklist spells",
            "delete all focus aura blacklist spells", "delete all boss aura blacklist spells",
        },
        parseAliasArgs = ParseAuraBlacklistClearAliasArgs,
        run = function(args)
            local Model = AuraModel()
            if not (Model and type(Model.ClearBlacklistSpells) == "function") then return false, "Open Aura Filters first so I can change hidden auras." end
            local scope = args and args.scope or "shared"
            local count = Model.ClearBlacklistSpells(scope)
            ApplyAura(scope, "MSUF_ASSISTANT_AURA_BLACKLIST_CLEAR")
            if count and count > 0 then
                return true, "Done. Cleared hidden spells for " .. AuraScopeLabel(scope) .. " auras. Removed " .. tostring(count) .. " " .. (count == 1 and "spell." or "spells.")
            end
            return true, "Already set. " .. AuraScopeLabel(scope) .. " auras have no hidden spell entries."
        end,
    })

    Registry:RegisterAction({
        key = "aura_blacklist_add_preset",
        label = "Add Hidden Aura Preset",
        type = "auras",
        combatSafe = false,
        confirmRequired = true,
        captureSnapshot = true,
        aliases = {
            "aura blacklist", "aura blacklist preset", "blacklist preset", "blacklist aura preset",
            "add aura blacklist preset", "add blacklist preset",
            "blacklist raid buffs", "ignore raid buffs", "block raid buffs",
            "blacklist cooldowns", "ignore cooldowns", "block cooldowns",
            "blacklist self buffs", "ignore self buffs", "block self buffs",
            "blacklist preservation evoker", "ignore preservation evoker",
            "blacklist augmentation evoker", "ignore augmentation evoker",
            "blacklist resto druid", "blacklist restoration druid", "ignore resto druid",
            "blacklist disc priest", "blacklist discipline priest", "ignore disc priest",
            "blacklist holy priest", "ignore holy priest",
            "blacklist mistweaver monk", "ignore mistweaver monk",
            "blacklist resto shaman", "blacklist restoration shaman", "ignore resto shaman",
            "blacklist holy paladin", "blacklist holy pala", "ignore holy paladin",
            "blacklist blessing of the bronze", "ignore blessing of the bronze",
            "blacklist rogue poisons", "ignore rogue poisons",
            "blacklist shaman imbues", "ignore shaman imbues",
            "blacklist resource auras", "ignore resource auras",
        },
        parseAliasArgs = ParseAuraBlacklistPresetAliasArgs,
        run = function(args)
            local Model = AuraModel()
            if not (Model and type(Model.AddBlacklistPresetGroup) == "function") then return false, "Open Aura Filters first so I can add that hidden-aura preset." end
            local scope = args and args.scope or "shared"
            local preset = args and args.preset
            if type(preset) ~= "string" or preset == "" then return false, "Which hidden-aura preset do you want me to use?" end
            local count = Model.AddBlacklistPresetGroup(scope, preset)
            ApplyAura(scope, "MSUF_ASSISTANT_AURA_BLACKLIST_PRESET")
            return true, "Done. Added " .. tostring(count or 0) .. " spells from that preset to hidden " .. AuraScopeLabel(scope) .. " auras."
        end,
    })

    RegisterBlacklistSummaryAction(ctx)
end
