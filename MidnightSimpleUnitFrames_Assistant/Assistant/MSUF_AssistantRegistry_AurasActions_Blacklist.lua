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
    local ParseAuraCustomWhitelistAddAliasArgs = ctx.ParseAuraCustomWhitelistAddAliasArgs
    local ParseAuraCustomWhitelistRemoveAliasArgs = ctx.ParseAuraCustomWhitelistRemoveAliasArgs
    local ParseAuraCustomWhitelistClearAliasArgs = ctx.ParseAuraCustomWhitelistClearAliasArgs
    local ParseAuraCustomWhitelistSummaryAliasArgs = ctx.ParseAuraCustomWhitelistSummaryAliasArgs
    local RegisterBlacklistSummaryAction = A.AurasRegistry and A.AurasRegistry.RegisterBlacklistSummaryAction

    if not (Registry and type(Registry.RegisterAction) == "function") then return end
    if type(AuraModel) ~= "function" or type(ApplyAura) ~= "function" or type(AuraScopeLabel) ~= "function" then return end
    if type(ParseAuraBlacklistAddSpellAliasArgs) ~= "function" or type(ParseAuraBlacklistRemoveSpellAliasArgs) ~= "function" then return end
    if type(ParseAuraBlacklistClearAliasArgs) ~= "function" or type(ParseAuraBlacklistPresetAliasArgs) ~= "function" then return end
    if type(ParseAuraBlacklistSummaryAliasArgs) ~= "function" or type(RegisterBlacklistSummaryAction) ~= "function" then return end

    local function UnitScope(scope)
        return scope == "player" or scope == "target" or scope == "focus" or scope == "boss"
    end

    local function Lanes(lane)
        if lane == "buff" or lane == "debuff" then return { lane } end
        return { "buff", "debuff" }
    end

    local function LaneLabel(lane)
        if lane == "buff" then return "buffs" end
        if lane == "debuff" then return "debuffs" end
        return "buffs and debuffs"
    end

    local function RestrictionNote()
        return " Blizzard may reject exact harmful-aura filters on friendly units and exact helpful-aura filters on hostile units."
    end

    local function RequireModelAndScope(args)
        local Model = AuraModel()
        local scope = args and args.scope
        if not (Model and type(Model.AddBlacklistSpell) == "function") then
            return nil, nil, "Open Aura Filters first so I can edit the native hidden-aura list."
        end
        if not UnitScope(scope) then
            return nil, nil, "Choose Player, Target, Focus, or Boss so I know which unit-frame aura list to edit."
        end
        return Model, scope
    end

    Registry:RegisterAction({
        key = "aura_blacklist_add_spell",
        label = "Hide Aura Spell",
        type = "auras",
        combatSafe = true,
        aliases = {
            "blacklist", "blacklist spell", "blacklist aura", "blacklist aura spell",
            "block aura", "block aura spell", "ignore aura", "ignore aura spell",
            "hide", "suppress", "stop showing",
            "verstecke", "verstecken", "ausblenden", "aura ausblenden",
            "verstecke aura", "verstecke aura spell", "verstecke spell",
            "hide aura", "hide aura spell", "hide spell", "suppress aura", "suppress spell",
            "stop showing aura", "stop showing spell",
        },
        parseAliasArgs = ParseAuraBlacklistAddSpellAliasArgs,
        run = function(args)
            local value = args and args.value
            if type(value) ~= "string" or value == "" then return false, "Which spell do you want me to use? A spell ID, spell link, or full spell name is enough." end
            local Model, scope, err = RequireModelAndScope(args)
            if not Model then return false, err end
            local changed = false
            for _, lane in ipairs(Lanes(args and args.lane)) do
                changed = Model.AddBlacklistSpell(scope, value, lane) or changed
            end
            if changed then ApplyAura(scope, "MSUF_ASSISTANT_AURA_BLACKLIST_ADD") end
            local prefix = changed and "Done. Hidden " or "Already set. "
            return true, prefix .. tostring(value) .. " for " .. AuraScopeLabel(scope) .. " " .. LaneLabel(args and args.lane) .. "." .. RestrictionNote(), not changed and { noChange = true } or nil
        end,
    })

    Registry:RegisterAction({
        key = "aura_blacklist_remove_spell",
        label = "Allow Hidden Aura Spell",
        type = "auras",
        combatSafe = true,
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
            local value = args and args.value
            if type(value) ~= "string" or value == "" then return false, "Which spell do you want me to use? A spell ID, spell link, or full spell name is enough." end
            local Model, scope, err = RequireModelAndScope(args)
            if not Model then return false, err end
            local changed = false
            for _, lane in ipairs(Lanes(args and args.lane)) do
                changed = Model.RemoveBlacklistSpell(scope, value, lane) or changed
            end
            if changed then ApplyAura(scope, "MSUF_ASSISTANT_AURA_BLACKLIST_REMOVE") end
            return true, (changed and "Done. Allowed " or "Already allowed. ") .. tostring(value) .. " for " .. AuraScopeLabel(scope) .. " " .. LaneLabel(args and args.lane) .. ".", not changed and { noChange = true } or nil
        end,
    })

    Registry:RegisterAction({
        key = "aura_blacklist_clear_spells",
        label = "Clear Hidden Aura Spells",
        type = "auras",
        combatSafe = true,
        confirmRequired = true,
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
            local Model, scope, err = RequireModelAndScope(args)
            if not Model then return false, err end
            local count = 0
            for _, lane in ipairs(Lanes(args and args.lane)) do
                count = count + (tonumber(Model.ClearBlacklistSpells(scope, lane)) or 0)
            end
            if count > 0 then ApplyAura(scope, "MSUF_ASSISTANT_AURA_BLACKLIST_CLEAR") end
            return true, count > 0 and ("Done. Cleared " .. tostring(count) .. " hidden aura entries for " .. AuraScopeLabel(scope) .. " " .. LaneLabel(args and args.lane) .. ".") or "Already empty.", count == 0 and { noChange = true } or nil
        end,
    })

    Registry:RegisterAction({
        key = "aura_blacklist_add_preset",
        label = "Add Hidden Aura Preset",
        type = "auras",
        combatSafe = true,
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
            local preset = args and args.preset
            if type(preset) ~= "string" or preset == "" then return false, "Which hidden-aura preset do you want me to use?" end
            local Model, scope, err = RequireModelAndScope(args)
            if not Model then return false, err end
            local count = 0
            for _, lane in ipairs(Lanes(args and args.lane)) do
                count = count + (tonumber(Model.AddBlacklistPresetGroup(scope, preset, lane)) or 0)
            end
            if count > 0 then ApplyAura(scope, "MSUF_ASSISTANT_AURA_BLACKLIST_PRESET") end
            return true, count > 0 and ("Done. Added " .. tostring(count) .. " missing SpellIDs from " .. tostring(preset) .. " for " .. AuraScopeLabel(scope) .. " " .. LaneLabel(args and args.lane) .. "." .. RestrictionNote()) or "Already set. That preset added no new SpellIDs.", count == 0 and { noChange = true } or nil
        end,
    })

    if type(ParseAuraCustomWhitelistAddAliasArgs) == "function" then
        Registry:RegisterAction({
            key = "aura_custom_whitelist_add_spell",
            label = "Whitelist Custom Aura Spell",
            type = "auras",
            combatSafe = true,
            aliases = { "whitelist", "custom whitelist", "whitelist custom aura spell", "add custom whitelist spell" },
            parseAliasArgs = ParseAuraCustomWhitelistAddAliasArgs,
            run = function(args)
                local Model, scope, err = RequireModelAndScope(args)
                if not Model then return false, err end
                local changed, reason = Model.AddCustomContainerSpell(scope, args.index, args.value)
                if reason == "full" then return false, "Custom aura " .. tostring(args.index) .. " already has the maximum of 40 whitelist SpellIDs." end
                if reason == "invalid" then return false, "That spell could not be resolved to a SpellID." end
                if changed then ApplyAura(scope, "MSUF_ASSISTANT_AURA_CUSTOM_WHITELIST_ADD") end
                return true, (changed and "Done. Whitelisted " or "Already set. ") .. tostring(args.value) .. " in " .. AuraScopeLabel(scope) .. " Custom Aura " .. tostring(args.index) .. ".", not changed and { noChange = true } or nil
            end,
        })

        Registry:RegisterAction({
            key = "aura_custom_whitelist_remove_spell",
            label = "Remove Custom Aura Whitelist Spell",
            type = "auras",
            combatSafe = true,
            aliases = { "remove", "delete", "unwhitelist", "remove custom whitelist spell", "remove from custom whitelist", "unwhitelist custom aura spell" },
            parseAliasArgs = ParseAuraCustomWhitelistRemoveAliasArgs,
            run = function(args)
                local Model, scope, err = RequireModelAndScope(args)
                if not Model then return false, err end
                local changed, reason = Model.RemoveCustomContainerSpell(scope, args.index, args.value)
                if reason == "invalid" then return false, "That spell could not be resolved to a SpellID." end
                if changed then ApplyAura(scope, "MSUF_ASSISTANT_AURA_CUSTOM_WHITELIST_REMOVE") end
                return true, (changed and "Done. Removed " or "Already absent. ") .. tostring(args.value) .. " from " .. AuraScopeLabel(scope) .. " Custom Aura " .. tostring(args.index) .. ".", not changed and { noChange = true } or nil
            end,
        })

        Registry:RegisterAction({
            key = "aura_custom_whitelist_clear_spells",
            label = "Clear Custom Aura Whitelist",
            type = "auras",
            combatSafe = true,
            confirmRequired = true,
            aliases = { "clear", "empty", "reset", "clear custom whitelist", "empty custom aura whitelist", "reset custom aura whitelist" },
            parseAliasArgs = ParseAuraCustomWhitelistClearAliasArgs,
            run = function(args)
                local Model, scope, err = RequireModelAndScope(args)
                if not Model then return false, err end
                local count = tonumber(Model.ClearCustomContainerSpells(scope, args.index)) or 0
                if count > 0 then ApplyAura(scope, "MSUF_ASSISTANT_AURA_CUSTOM_WHITELIST_CLEAR") end
                return true, count > 0 and ("Done. Cleared " .. tostring(count) .. " whitelist SpellIDs from " .. AuraScopeLabel(scope) .. " Custom Aura " .. tostring(args.index) .. ".") or "Already empty.", count == 0 and { noChange = true } or nil
            end,
        })

        Registry:RegisterAction({
            key = "aura_custom_whitelist_summary",
            label = "Show Custom Aura Whitelist",
            type = "auras",
            combatSafe = true,
            aliases = { "show", "list", "current", "summary", "show custom whitelist", "list custom aura whitelist", "current custom whitelist" },
            parseAliasArgs = ParseAuraCustomWhitelistSummaryAliasArgs,
            run = function(args)
                local Model, scope, err = RequireModelAndScope(args)
                if not Model then return false, err end
                local entries = Model.CustomContainerSpellEntries(scope, args.index) or {}
                local out = {}
                for i = 1, #entries do out[#out + 1] = tostring(entries[i].text or entries[i].value) end
                local body = #out > 0 and table.concat(out, "\n") or "No whitelisted spells."
                return true, AuraScopeLabel(scope) .. " Custom Aura " .. tostring(args.index) .. " whitelist:\n" .. body
            end,
        })
    end

    RegisterBlacklistSummaryAction(ctx)
end
