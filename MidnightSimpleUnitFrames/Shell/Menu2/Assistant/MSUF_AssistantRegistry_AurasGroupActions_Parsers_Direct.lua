-- Direct group aura blacklist parser helpers.
-- Loaded before MSUF_AssistantRegistry_AurasGroupActions.lua; no runtime aura scan paths depend on this file.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.BuildGroupDirectActionParsers(ctx)
    if type(ctx) ~= "table" then return nil end

    local Assistant = ctx.A or A
    local helpers = ctx.helpers or (Assistant.AurasRegistry and Assistant.AurasRegistry.ActionHelpers) or nil
    if type(helpers) ~= "table" then return nil end

    local AuraActionNormalized = helpers.AuraActionNormalized
    local AuraActionContainsAny = helpers.AuraActionContainsAny
    local AuraActionHasToken = helpers.AuraActionHasToken
    if type(AuraActionNormalized) ~= "function" or type(AuraActionContainsAny) ~= "function" then return nil end
    if type(AuraActionHasToken) ~= "function" then return nil end

    local BuildGroupDirectActionParserHelpers = Assistant.AurasRegistry and Assistant.AurasRegistry.BuildGroupDirectActionParserHelpers
    local DirectHelpers = type(BuildGroupDirectActionParserHelpers) == "function" and BuildGroupDirectActionParserHelpers({
        A = Assistant,
        AuraActionNormalized = AuraActionNormalized,
    }) or nil
    if type(DirectHelpers) ~= "table" then return nil end
    local DirectGroupAuraBlacklistBlocked = DirectHelpers.DirectGroupAuraBlacklistBlocked
    local HasDirectGroupAuraBlacklistScope = DirectHelpers.HasDirectGroupAuraBlacklistScope
    local DirectGroupAuraBlacklistScopeLane = DirectHelpers.DirectGroupAuraBlacklistScopeLane
    local DirectGroupAuraBlacklistIntent = DirectHelpers.DirectGroupAuraBlacklistIntent
    if type(DirectGroupAuraBlacklistBlocked) ~= "function" or type(HasDirectGroupAuraBlacklistScope) ~= "function" then return nil end
    if type(DirectGroupAuraBlacklistScopeLane) ~= "function" or type(DirectGroupAuraBlacklistIntent) ~= "function" then return nil end

    local function ParseGroupAuraDirectBlacklistSpellAliasArgs(text, raw)
        if not DirectGroupAuraBlacklistIntent(text) then return false end
        local normalized = AuraActionNormalized(text)
        if normalized:find("all spells", 1, true) or normalized:find("all auras", 1, true)
            or normalized:find("every spell", 1, true) or normalized:find("every aura", 1, true)
            or normalized:find("clear all", 1, true) or normalized:find("allow all", 1, true)
            or normalized:find("remove all", 1, true) or normalized:find("delete all", 1, true) then
            return false
        end
        local P = Assistant.Parser or {}
        local value = type(P.AuraBlacklistSpellValue) == "function" and P.AuraBlacklistSpellValue(raw or text) or nil
        if type(value) ~= "string" or value == "" then return false end
        local scope, lane = DirectGroupAuraBlacklistScopeLane(normalized)
        return { scope = scope, lane = lane, value = value }, {
            summary = "Edits the native exact-SpellID hidden-aura list for the selected group lane.",
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
        local P = Assistant.Parser or {}
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
            summary = "Clears native exact-SpellID hidden-aura entries for the selected group lane.",
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
        local P = Assistant.Parser or {}
        local preset = type(P.AuraBlacklistPresetForText) == "function" and P.AuraBlacklistPresetForText(normalized) or nil
        if not preset then return false end
        if not (normalized:find("preset", 1, true) or normalized:find("blacklist", 1, true)
            or normalized:find("ignore", 1, true) or normalized:find("block", 1, true)) then
            return false
        end
        local scope, lane = DirectGroupAuraBlacklistScopeLane(normalized)
        return { scope = scope, lane = lane, preset = preset }, {
            summary = "Adds missing preset SpellIDs to the native group hidden-aura list.",
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
            summary = "Shows native exact-SpellID hidden aura entries for group frames.",
        }
    end

    return {
        ParseGroupAuraDirectBlacklistAddSpellAliasArgs = ParseGroupAuraDirectBlacklistAddSpellAliasArgs,
        ParseGroupAuraDirectBlacklistRemoveSpellAliasArgs = ParseGroupAuraDirectBlacklistRemoveSpellAliasArgs,
        ParseGroupAuraDirectBlacklistClearAliasArgs = ParseGroupAuraDirectBlacklistClearAliasArgs,
        ParseGroupAuraDirectBlacklistPresetAliasArgs = ParseGroupAuraDirectBlacklistPresetAliasArgs,
        ParseGroupAuraDirectBlacklistSummaryAliasArgs = ParseGroupAuraDirectBlacklistSummaryAliasArgs,
    }
end
