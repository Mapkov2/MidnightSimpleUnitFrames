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
local BuildActionParsers = A.AurasRegistry and A.AurasRegistry.BuildActionParsers
local ActionParsers = type(BuildActionParsers) == "function" and BuildActionParsers({
    A = A,
    M = M,
    AuraScopeFromArg = AuraScopeFromArg,
}) or nil
if type(ActionParsers) ~= "table" then return end

local ParseAuraEditScopeAliasArgs = ActionParsers.ParseAuraEditScopeAliasArgs
local ParseAuraScopeResetAliasArgs = ActionParsers.ParseAuraScopeResetAliasArgs
local ParseAuraAllResetAliasArgs = ActionParsers.ParseAuraAllResetAliasArgs
local ParseAuraQuickPresetAliasArgs = ActionParsers.ParseAuraQuickPresetAliasArgs
local ParseAuraBlacklistAddSpellAliasArgs = ActionParsers.ParseAuraBlacklistAddSpellAliasArgs
local ParseAuraBlacklistRemoveSpellAliasArgs = ActionParsers.ParseAuraBlacklistRemoveSpellAliasArgs
local ParseAuraBlacklistClearAliasArgs = ActionParsers.ParseAuraBlacklistClearAliasArgs
local ParseAuraBlacklistPresetAliasArgs = ActionParsers.ParseAuraBlacklistPresetAliasArgs
local ParseAuraBlacklistSummaryAliasArgs = ActionParsers.ParseAuraBlacklistSummaryAliasArgs
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
        if scope == "shared" then return false, "Shared auras are the base options; choose Player, Target, Focus, or Boss to reset overrides." end
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

local RegisterQuickPresetAction = A.AurasRegistry and A.AurasRegistry.RegisterQuickPresetAction
if type(RegisterQuickPresetAction) == "function" then
    RegisterQuickPresetAction({
        Registry = Registry,
        M = M,
        AuraScopeLabel = AuraScopeLabel,
        ParseAuraQuickPresetAliasArgs = ParseAuraQuickPresetAliasArgs,
    })
end

local RegisterBlacklistActions = A.AurasRegistry and A.AurasRegistry.RegisterBlacklistActions
if type(RegisterBlacklistActions) == "function" then
    RegisterBlacklistActions({
        Registry = Registry,
        AuraModel = AuraModel,
        ApplyAura = ApplyAura,
        AuraScopeLabel = AuraScopeLabel,
        ParseAuraBlacklistAddSpellAliasArgs = ParseAuraBlacklistAddSpellAliasArgs,
        ParseAuraBlacklistRemoveSpellAliasArgs = ParseAuraBlacklistRemoveSpellAliasArgs,
        ParseAuraBlacklistClearAliasArgs = ParseAuraBlacklistClearAliasArgs,
        ParseAuraBlacklistPresetAliasArgs = ParseAuraBlacklistPresetAliasArgs,
        ParseAuraBlacklistSummaryAliasArgs = ParseAuraBlacklistSummaryAliasArgs,
    })
end
