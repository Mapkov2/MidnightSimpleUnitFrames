local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- Auras assistant action domain.
-- Depends on MSUF_AssistantRegistry_Auras.lua for shared setting helpers.
local ctx = A.AurasRegistry and A.AurasRegistry.Actions
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
A = ctx.A or A
M = ctx.M or M
local AuraScopeFromArg = ctx.AuraScopeFromArg
local AuraScopeLabel = ctx.AuraScopeLabel
local AuraModel = ctx.AuraModel
local ApplyAura = ctx.ApplyAura
local ResetAuraScope = ctx.ResetAuraScope
local ResetAllAuraOverrides = ctx.ResetAllAuraOverrides

if not (Registry and type(Registry.RegisterAction) == "function") then return end
if type(AuraScopeFromArg) ~= "function" or type(AuraScopeLabel) ~= "function" then return end
if type(AuraModel) ~= "function" or type(ApplyAura) ~= "function" then return end
local function AuraActionNormalized(text)
    local P = A.Parser or {}
    if type(P.Normalize) == "function" then return P.Normalize(text) end
    return tostring(text or ""):lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function AuraActionEditScope(text)
    local P = A.Parser or {}
    local normalized = AuraActionNormalized(text)
    local scope = type(P.AuraEditScopeForText) == "function" and P.AuraEditScopeForText(normalized) or nil
    if not scope and type(P.AuraBlacklistScope) == "function" then scope = P.AuraBlacklistScope(normalized) end
    scope = AuraScopeFromArg(scope or M.auraScope or "shared")
    if scope ~= "shared" and scope ~= "player" and scope ~= "target" and scope ~= "focus" and scope ~= "boss" and scope ~= "party" and scope ~= "raid" then
        scope = "shared"
    end
    return scope
end

local function ParseAuraEditScopeAliasArgs(text)
    local normalized = AuraActionNormalized(text)
    if normalized:find("reset", 1, true) or normalized:find("clear", 1, true)
        or normalized:find("remove", 1, true) or normalized:find("zuruecksetzen", 1, true) then
        return false
    end
    return { scope = AuraActionEditScope(text) }, {
        summary = "Selects the Aura page editing scope through registered action metadata.",
    }
end

local function ParseAuraScopeResetAliasArgs(text)
    local P = A.Parser or {}
    local normalized = AuraActionNormalized(text)
    if type(P.ContainsAny) == "function" then
        if not P.ContainsAny(normalized, { "reset", "clear", "remove", "zuruecksetzen" }) then return false end
    elseif not (normalized:find("reset", 1, true) or normalized:find("clear", 1, true)
        or normalized:find("remove", 1, true) or normalized:find("zuruecksetzen", 1, true)) then
        return false
    end
    local scope = AuraActionEditScope(text)
    if scope == "shared" then return false end
    return { scope = scope }, {
        summary = "Resets one Aura editing scope back to Shared through registered action metadata.",
    }
end

local function ParseAuraAllResetAliasArgs(text)
    local P = A.Parser or {}
    local normalized = AuraActionNormalized(text)
    if type(P.ContainsAny) == "function" then
        if not P.ContainsAny(normalized, { "reset", "clear", "remove", "zuruecksetzen" }) then return false end
    elseif not (normalized:find("reset", 1, true) or normalized:find("clear", 1, true)
        or normalized:find("remove", 1, true) or normalized:find("zuruecksetzen", 1, true)) then
        return false
    end
    if not (normalized:find("all", 1, true) or normalized:find("every", 1, true)) then return false end
    return {}, {
        summary = "Resets all Aura overrides through registered action metadata.",
    }
end

local function ParseAuraQuickPresetAliasArgs(text)
    local P = A.Parser or {}
    local normalized = AuraActionNormalized(text)
    local preset = type(P.AuraQuickPresetForText) == "function" and P.AuraQuickPresetForText(normalized) or nil
    if not preset then return false end
    local scope = type(P.AuraBlacklistScope) == "function" and P.AuraBlacklistScope(normalized) or AuraActionEditScope(normalized)
    return { scope = scope or "shared", preset = preset }, {
        summary = "Applies the shared Auras quick setup helper through registered action metadata.",
    }
end

local function ParseAuraBlacklistScopeAliasArgs(text)
    local P = A.Parser or {}
    local normalized = AuraActionNormalized(text)
    local scope = type(P.AuraBlacklistScope) == "function" and P.AuraBlacklistScope(normalized) or AuraActionEditScope(normalized)
    return { scope = scope or "shared" }, {
        summary = "Reads or clears Aura blacklist state through registered action metadata.",
    }
end

local function AuraActionContainsAny(text, phrases)
    local P = A.Parser or {}
    local normalized = AuraActionNormalized(text)
    if type(P.ContainsAny) == "function" then return P.ContainsAny(normalized, phrases) end
    for i = 1, #(phrases or {}) do
        if normalized:find(tostring(phrases[i] or ""), 1, true) then return true end
    end
    return false
end

local function AuraActionHasToken(text, token)
    token = tostring(token or "")
    for value in AuraActionNormalized(text):gmatch("%S+") do
        if value == token then return true end
    end
    return false
end

local function AuraBlacklistHasDirectGroupScope(text)
    local normalized = AuraActionNormalized(text)
    if AuraActionContainsAny(normalized, {
        "player aura", "player auras", "target aura", "target auras",
        "focus aura", "focus auras", "boss aura", "boss auras",
    }) then
        return false
    end
    if not normalized:find("blacklist", 1, true) then return false end
    return AuraActionContainsAny(normalized, {
        "group aura", "group auras", "group frame aura", "group frame auras",
        "party aura", "party auras", "party buff", "party buffs", "party debuff", "party debuffs",
        "raid aura", "raid auras", "raid buff", "raid buffs", "raid debuff", "raid debuffs",
        "mythic raid aura", "mythic raid auras", "mythic raid buff", "mythic raid buffs",
        "for party", "on party", "for raid", "on raid",
    })
end

local function ParseAuraBlacklistSummaryAliasArgs(text)
    if not AuraActionContainsAny(text, { "show", "list", "summary", "current", "what is", "whats" }) then
        return false
    end
    if AuraBlacklistHasDirectGroupScope(text) then return false end
    local args = ParseAuraBlacklistScopeAliasArgs(text)
    if not args then return false end
    return args, {
        summary = "Shows Aura blacklist state through registered action metadata.",
    }
end

local function ParseAuraBlacklistClearAliasArgs(text)
    if not AuraActionContainsAny(text, {
        "clear", "empty", "reset", "allow all", "remove all", "delete all", "unblacklist all",
        "all spells", "all auras", "every spell", "every aura",
    }) then
        return false
    end
    local args = ParseAuraBlacklistScopeAliasArgs(text)
    if not args then return false end
    return args, {
        summary = "Clears Aura blacklist state through registered action metadata.",
    }
end

local function ParseAuraBlacklistSpellAliasArgs(text, raw)
    local P = A.Parser or {}
    local normalized = AuraActionNormalized(text)
    if normalized:find("all spells", 1, true) or normalized:find("all auras", 1, true)
        or normalized:find("every spell", 1, true) or normalized:find("every aura", 1, true)
        or normalized:find("clear all", 1, true) or normalized:find("allow all", 1, true)
        or normalized:find("remove all", 1, true) or normalized:find("delete all", 1, true) then
        return false
    end
    if not (normalized:find("aura", 1, true) or normalized:find("buff", 1, true)
        or normalized:find("debuff", 1, true) or normalized:find("spell", 1, true)) then
        return false
    end
    local value = type(P.AuraBlacklistSpellValue) == "function" and P.AuraBlacklistSpellValue(raw or text) or nil
    if type(value) ~= "string" or value == "" then return false end
    local scope = type(P.AuraBlacklistScope) == "function" and P.AuraBlacklistScope(normalized) or AuraActionEditScope(normalized)
    return { scope = scope or "shared", value = value }, {
        summary = "Edits a single Aura blacklist spell through registered action metadata.",
    }
end

local function ParseAuraBlacklistAddSpellAliasArgs(text, raw)
    local normalized = AuraActionNormalized(text)
    if normalized:find("remove", 1, true) or normalized:find("delete", 1, true)
        or normalized:find("allow", 1, true) or normalized:find("unblacklist", 1, true)
        or normalized:find("unblock", 1, true) or normalized:find("entfernen", 1, true)
        or normalized:find("loeschen", 1, true) or normalized:find("unhide", 1, true)
        or normalized:find("stop hiding", 1, true)
        or (normalized:find("show", 1, true) and normalized:find("again", 1, true))
        or (normalized:find("let", 1, true) and normalized:find("show", 1, true)) then
        return false
    end
    local P = A.Parser or {}
    if type(P.AuraBlacklistPresetForText) == "function" and P.AuraBlacklistPresetForText(normalized) then
        return false
    end
    return ParseAuraBlacklistSpellAliasArgs(text, raw)
end

local function ParseAuraBlacklistRemoveSpellAliasArgs(text, raw)
    local normalized = AuraActionNormalized(text)
    if not (normalized:find("remove", 1, true) or normalized:find("delete", 1, true)
        or normalized:find("allow", 1, true) or normalized:find("unblacklist", 1, true)
        or normalized:find("unblock", 1, true) or normalized:find("entfernen", 1, true)
        or normalized:find("loeschen", 1, true) or normalized:find("unhide", 1, true)
        or normalized:find("stop hiding", 1, true)
        or (normalized:find("show", 1, true) and normalized:find("again", 1, true))
        or (normalized:find("let", 1, true) and normalized:find("show", 1, true))) then
        return false
    end
    return ParseAuraBlacklistSpellAliasArgs(text, raw)
end

local function ParseAuraBlacklistPresetAliasArgs(text)
    local P = A.Parser or {}
    local normalized = AuraActionNormalized(text)
    local containsAny = type(P.ContainsAny) == "function" and P.ContainsAny or nil
    if normalized:find("quick preset", 1, true) or normalized:find("quick setup", 1, true) then return false end
    if normalized:find("category", 1, true) or normalized:find("categories", 1, true) then return false end
    if containsAny and containsAny(normalized, { "show", "list", "summary", "current", "what is", "whats" }) then
        return false
    end
    if normalized:find("remove", 1, true) or normalized:find("delete", 1, true)
        or normalized:find("allow", 1, true) or normalized:find("unblacklist", 1, true)
        or normalized:find("unblock", 1, true) or normalized:find("entfernen", 1, true)
        or normalized:find("loeschen", 1, true) or normalized:find("clear", 1, true)
        or AuraActionHasToken(normalized, "reset") or normalized:find("empty", 1, true)
        or normalized:find("all spells", 1, true) or normalized:find("all auras", 1, true)
        or normalized:find("every spell", 1, true) or normalized:find("every aura", 1, true) then
        return false
    end
    if not (normalized:find("blacklist", 1, true) or normalized:find("blocked", 1, true)
        or normalized:find("block", 1, true) or normalized:find("ignore", 1, true)) then
        return false
    end
    local preset = type(P.AuraBlacklistPresetForText) == "function" and P.AuraBlacklistPresetForText(normalized) or nil
    if not preset then return false end
    local scope = type(P.AuraBlacklistScope) == "function" and P.AuraBlacklistScope(normalized) or AuraActionEditScope(normalized)
    return { scope = scope or "shared", preset = preset }, {
        summary = "Adds a curated Aura blacklist preset through registered action metadata.",
    }
end
A.AurasRegistry = A.AurasRegistry or {}
A.AurasRegistry.ActionHelpers = {
    AuraActionNormalized = AuraActionNormalized,
    AuraActionEditScope = AuraActionEditScope,
    AuraActionContainsAny = AuraActionContainsAny,
    AuraActionHasToken = AuraActionHasToken,
}
Registry:RegisterAction({
    key = "set_aura_edit_scope",
    label = "Set Aura Editing Scope",
    type = "navigation",
    combatSafe = true,
    aliases = {
        "aura editing scope", "aura scope", "edit auras", "edit player auras", "edit target auras",
        "edit focus auras", "edit boss auras", "edit party auras", "edit raid auras",
        "select aura scope", "switch aura scope",
    },
    parseAliasArgs = ParseAuraEditScopeAliasArgs,
    run = function(args)
        local scope = AuraScopeFromArg(args and args.scope)
        if scope ~= "shared" and scope ~= "player" and scope ~= "target" and scope ~= "focus" and scope ~= "boss" and scope ~= "party" and scope ~= "raid" then scope = "shared" end
        if type(M.PersistMenuStateValue) == "function" then M.PersistMenuStateValue("auraScope", scope) else M.auraScope = scope end
        if scope == "party" or scope == "raid" then
            if type(M.PersistMenuStateValue) == "function" then M.PersistMenuStateValue("auraStyleGFScope", scope) else M.auraStyleGFScope = scope end
        end
        if type(M.SelectPage) == "function" then M.SelectPage("auras3") elseif type(M.Open) == "function" then M.Open("auras3") end
        if type(M.Refresh) == "function" then M.Refresh() end
        if type(M.InvalidatePage) == "function" then M.InvalidatePage("auras3") end
        return true, "Done. Editing " .. AuraScopeLabel(scope) .. " auras."
    end,
})

Registry:RegisterAction({
    key = "reset_aura_scope_overrides",
    label = "Reset Aura Scope Overrides",
    type = "reset",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    aliases = {
        "reset aura scope", "reset aura overrides", "reset custom aura settings",
        "reset aura custom settings", "reset player aura overrides", "reset target aura overrides",
        "reset focus aura overrides", "reset boss aura overrides",
        "reset player aura scope", "reset target aura scope", "reset focus aura scope", "reset boss aura scope",
        "reset player aura custom settings", "reset target aura custom settings",
        "reset focus aura custom settings", "reset boss aura custom settings",
        "reset player custom aura settings", "reset target custom aura settings",
        "reset focus custom aura settings", "reset boss custom aura settings",
        "clear player aura overrides", "clear target aura overrides",
        "clear focus aura overrides", "clear boss aura overrides",
        "remove player aura overrides", "remove target aura overrides",
        "remove focus aura overrides", "remove boss aura overrides",
        "clear player aura custom settings", "clear target aura custom settings",
        "clear focus aura custom settings", "clear boss aura custom settings",
        "clear player custom aura settings", "clear target custom aura settings",
        "clear focus custom aura settings", "clear boss custom aura settings",
        "remove player aura custom settings", "remove target aura custom settings",
        "remove focus aura custom settings", "remove boss aura custom settings",
        "remove player custom aura settings", "remove target custom aura settings",
        "remove focus custom aura settings", "remove boss custom aura settings",
        "clear player aura scope", "clear target aura scope",
        "clear focus aura scope", "clear boss aura scope",
        "remove player aura scope", "remove target aura scope",
        "remove focus aura scope", "remove boss aura scope",
    },
    parseAliasArgs = ParseAuraScopeResetAliasArgs,
    run = function(args)
        local scope = AuraScopeFromArg(args and args.scope)
        if scope == "shared" then return false, "Shared auras are the base settings; choose Player, Target, Focus, or Boss to reset overrides." end
        ResetAuraScope(scope)
        ApplyAura(scope, "MSUF_ASSISTANT_AURA_SCOPE_RESET")
        if type(M.Refresh) == "function" then M.Refresh() end
        if type(M.InvalidatePage) == "function" then M.InvalidatePage("auras3") end
        return true, "Done. Reset " .. AuraScopeLabel(scope) .. " aura overrides."
    end,
})

Registry:RegisterAction({
    key = "reset_all_aura_overrides",
    label = "Reset All Aura Overrides",
    type = "reset",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    aliases = {
        "reset all aura overrides", "reset every aura override", "clear all aura overrides",
        "remove all aura overrides", "reset all auras",
        "reset all aura custom settings", "reset all custom aura settings",
        "clear all aura custom settings", "clear all custom aura settings",
        "remove all aura custom settings", "remove all custom aura settings",
    },
    parseAliasArgs = ParseAuraAllResetAliasArgs,
    aliasNoArgs = true,
    run = function()
        ResetAllAuraOverrides()
        ApplyAura("shared", "MSUF_ASSISTANT_AURA_ALL_OVERRIDES_RESET")
        if type(M.Refresh) == "function" then M.Refresh() end
        if type(M.InvalidatePage) == "function" then M.InvalidatePage("auras3") end
        return true, "Done. Reset all aura overrides."
    end,
})

Registry:RegisterAction({
    key = "apply_aura_quick_preset",
    label = "Apply Aura Quick Preset",
    type = "preset",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    aliases = {
        "apply aura preset", "apply aura quick preset", "use aura preset", "use aura quick preset",
        "aura quick setup", "auras quick setup", "aura preset setup", "aura setup preset",
        "apply clean aura preset", "apply focused aura preset", "apply performance aura preset",
        "use clean aura preset", "use focused aura preset", "use performance aura preset",
        "use clean aura quick preset", "use focused aura quick preset", "use performance aura quick preset",
        "use clean preset", "use focused preset", "use performance preset",
        "clean aura quick setup", "focused aura quick setup", "performance aura quick setup",
    },
    parseAliasArgs = ParseAuraQuickPresetAliasArgs,
    run = function(args)
        local preset = args and args.preset
        local scope = args and args.scope or "shared"
        if type(preset) ~= "string" or preset == "" then return false, "I need an aura quick preset name." end
        if not (M and type(M.ApplyAuraQuickPreset) == "function") then return false, "Aura quick presets are not available yet." end
        local ok, label = M.ApplyAuraQuickPreset(scope, preset)
        if not ok then return false, "Aura quick preset " .. tostring(preset) .. " was not found." end
        return true, "Done. Applied " .. tostring(label or preset) .. " aura quick preset to " .. tostring(scope) .. " auras."
    end,
})

Registry:RegisterAction({
    key = "aura_blacklist_add_spell",
    label = "Add Aura Blacklist Spell",
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
        if not (Model and type(Model.AddBlacklistSpell) == "function") then return false, "Aura blacklist editing is not available right now." end
        local scope = args and args.scope or "shared"
        local value = args and args.value
        if type(value) ~= "string" or value == "" then return false, "I need a spell ID, spell link, or resolvable spell name." end
        if not Model.AddBlacklistSpell(scope, value) then return false, "That spell could not be resolved for the aura blacklist." end
        ApplyAura(scope, "MSUF_ASSISTANT_AURA_BLACKLIST_ADD")
        return true, "Done. Added " .. tostring(value) .. " to the " .. AuraScopeLabel(scope) .. " aura blacklist."
    end,
})

Registry:RegisterAction({
    key = "aura_blacklist_remove_spell",
    label = "Remove Aura Blacklist Spell",
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
        if not (Model and type(Model.RemoveBlacklistSpell) == "function") then return false, "Aura blacklist editing is not available right now." end
        local scope = args and args.scope or "shared"
        local value = args and args.value
        if type(value) ~= "string" or value == "" then return false, "I need a spell ID, spell link, or resolvable spell name." end
        Model.RemoveBlacklistSpell(scope, value)
        ApplyAura(scope, "MSUF_ASSISTANT_AURA_BLACKLIST_REMOVE")
        return true, "Done. Removed " .. tostring(value) .. " from the " .. AuraScopeLabel(scope) .. " aura blacklist."
    end,
})

Registry:RegisterAction({
    key = "aura_blacklist_clear_spells",
    label = "Clear Aura Blacklist",
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
        if not (Model and type(Model.ClearBlacklistSpells) == "function") then return false, "Aura blacklist editing is not available right now." end
        local scope = args and args.scope or "shared"
        local count = Model.ClearBlacklistSpells(scope)
        ApplyAura(scope, "MSUF_ASSISTANT_AURA_BLACKLIST_CLEAR")
        if count and count > 0 then
            return true, "Done. Allowed all spells for the " .. AuraScopeLabel(scope) .. " aura blacklist. Cleared " .. tostring(count) .. " blacklisted " .. (count == 1 and "spell." or "spells.")
        end
        return true, "Already set. No spells are blacklisted for the " .. AuraScopeLabel(scope) .. " aura blacklist."
    end,
})

Registry:RegisterAction({
    key = "aura_blacklist_add_preset",
    label = "Add Aura Blacklist Preset",
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
        if not (Model and type(Model.AddBlacklistPresetGroup) == "function") then return false, "Aura blacklist presets are not available right now." end
        local scope = args and args.scope or "shared"
        local preset = args and args.preset
        if type(preset) ~= "string" or preset == "" then return false, "I need an aura blacklist preset name." end
        local count = Model.AddBlacklistPresetGroup(scope, preset)
        ApplyAura(scope, "MSUF_ASSISTANT_AURA_BLACKLIST_PRESET")
        return true, "Done. Added " .. tostring(count or 0) .. " preset spells to the " .. AuraScopeLabel(scope) .. " aura blacklist."
    end,
})

Registry:RegisterAction({
    key = "aura_blacklist_summary",
    label = "Show Aura Blacklist",
    type = "auras",
    combatSafe = true,
    aliases = {
        "show aura blacklist", "list aura blacklist", "aura blacklist summary",
        "current aura blacklist", "what is aura blacklist",
        "show player aura blacklist", "show target aura blacklist", "show focus aura blacklist", "show boss aura blacklist",
        "show current player aura blacklist", "show current target aura blacklist",
        "show current focus aura blacklist", "show current boss aura blacklist",
        "list player aura blacklist", "list target aura blacklist", "list focus aura blacklist", "list boss aura blacklist",
        "current player aura blacklist", "current target aura blacklist",
        "current focus aura blacklist", "current boss aura blacklist",
        "what is player aura blacklist", "what is target aura blacklist",
        "what is focus aura blacklist", "what is boss aura blacklist",
        "player aura blacklist summary", "target aura blacklist summary",
        "focus aura blacklist summary", "boss aura blacklist summary",
    },
    parseAliasArgs = ParseAuraBlacklistSummaryAliasArgs,
    run = function(args)
        local Model = AuraModel()
        if not (Model and type(Model.BlacklistSummary) == "function") then return false, "Aura blacklist reading is not available right now." end
        local scope = args and args.scope or "shared"
        return true, AuraScopeLabel(scope) .. " aura blacklist:\n" .. tostring(Model.BlacklistSummary(scope))
    end,
})
