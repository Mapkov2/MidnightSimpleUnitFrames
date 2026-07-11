-- Aura action parser helpers.
-- Loaded before MSUF_AssistantRegistry_AurasActions.lua; keeps alias parsing out of action registrations.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.BuildActionParsers(ctx)
    if type(ctx) ~= "table" then return nil end

    local Assistant = ctx.A or A
    local Menu = ctx.M or M
    local AuraScopeFromArg = ctx.AuraScopeFromArg
    if type(AuraScopeFromArg) ~= "function" then return nil end

    local function AuraActionNormalized(text)
        local P = Assistant.Parser or {}
        if type(P.Normalize) == "function" then return P.Normalize(text) end
        return tostring(text or ""):lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    end

    local function AuraActionEditScope(text)
        local P = Assistant.Parser or {}
        local normalized = AuraActionNormalized(text)
        local scope = type(P.AuraEditScopeForText) == "function" and P.AuraEditScopeForText(normalized) or nil
        if not scope and type(P.AuraBlacklistScope) == "function" then scope = P.AuraBlacklistScope(normalized) end
        scope = AuraScopeFromArg(scope or Menu.auraScope or "shared")
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
            summary = "Selects the Aura page editing target.",
        }
    end

    local function ParseAuraScopeResetAliasArgs(text)
        local P = Assistant.Parser or {}
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
            summary = "Resets one Aura editing target back to Shared.",
        }
    end

    local function ParseAuraAllResetAliasArgs(text)
        local P = Assistant.Parser or {}
        local normalized = AuraActionNormalized(text)
        if type(P.ContainsAny) == "function" then
            if not P.ContainsAny(normalized, { "reset", "clear", "remove", "zuruecksetzen" }) then return false end
        elseif not (normalized:find("reset", 1, true) or normalized:find("clear", 1, true)
            or normalized:find("remove", 1, true) or normalized:find("zuruecksetzen", 1, true)) then
            return false
        end
        if not (normalized:find("all", 1, true) or normalized:find("every", 1, true)) then return false end
        return {}, {
            summary = "Resets all Aura overrides.",
        }
    end

    local function ParseAuraQuickPresetAliasArgs(text)
        local P = Assistant.Parser or {}
        local normalized = AuraActionNormalized(text)
        local preset = type(P.AuraQuickPresetForText) == "function" and P.AuraQuickPresetForText(normalized) or nil
        if not preset then return false end
        local scope = type(P.AuraBlacklistScope) == "function" and P.AuraBlacklistScope(normalized) or AuraActionEditScope(normalized)
        return { scope = scope or "shared", preset = preset }, {
            summary = "Applies the Auras quick setup.",
        }
    end

    local function AuraActionContainsAny(text, phrases)
        local P = Assistant.Parser or {}
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

    Assistant.AurasRegistry = Assistant.AurasRegistry or {}
    Assistant.AurasRegistry.ActionHelpers = {
        AuraActionNormalized = AuraActionNormalized,
        AuraActionEditScope = AuraActionEditScope,
        AuraActionContainsAny = AuraActionContainsAny,
        AuraActionHasToken = AuraActionHasToken,
    }

    local BuildBlacklistActionParsers = Assistant.AurasRegistry.BuildBlacklistActionParsers
    local BlacklistParsers = type(BuildBlacklistActionParsers) == "function" and BuildBlacklistActionParsers({
        A = Assistant,
        AuraActionNormalized = AuraActionNormalized,
        AuraActionEditScope = AuraActionEditScope,
        AuraActionContainsAny = AuraActionContainsAny,
        AuraActionHasToken = AuraActionHasToken,
    }) or {}

    return {
        ParseAuraEditScopeAliasArgs = ParseAuraEditScopeAliasArgs,
        ParseAuraScopeResetAliasArgs = ParseAuraScopeResetAliasArgs,
        ParseAuraAllResetAliasArgs = ParseAuraAllResetAliasArgs,
        ParseAuraQuickPresetAliasArgs = ParseAuraQuickPresetAliasArgs,
        ParseAuraBlacklistAddSpellAliasArgs = BlacklistParsers.ParseAuraBlacklistAddSpellAliasArgs,
        ParseAuraBlacklistRemoveSpellAliasArgs = BlacklistParsers.ParseAuraBlacklistRemoveSpellAliasArgs,
        ParseAuraBlacklistClearAliasArgs = BlacklistParsers.ParseAuraBlacklistClearAliasArgs,
        ParseAuraBlacklistPresetAliasArgs = BlacklistParsers.ParseAuraBlacklistPresetAliasArgs,
        ParseAuraBlacklistSummaryAliasArgs = BlacklistParsers.ParseAuraBlacklistSummaryAliasArgs,
        ParseAuraCustomWhitelistAddAliasArgs = BlacklistParsers.ParseAuraCustomWhitelistAddAliasArgs,
        ParseAuraCustomWhitelistRemoveAliasArgs = BlacklistParsers.ParseAuraCustomWhitelistRemoveAliasArgs,
        ParseAuraCustomWhitelistClearAliasArgs = BlacklistParsers.ParseAuraCustomWhitelistClearAliasArgs,
        ParseAuraCustomWhitelistSummaryAliasArgs = BlacklistParsers.ParseAuraCustomWhitelistSummaryAliasArgs,
    }
end
