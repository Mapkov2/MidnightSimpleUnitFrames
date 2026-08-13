-- Aura blacklist action parser helpers.
-- Loaded before MSUF_AssistantRegistry_AurasActions_Parsers.lua; shares normalized text helpers from that builder.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.BuildBlacklistActionParsers(ctx)
    if type(ctx) ~= "table" then return nil end

    local Assistant = ctx.A or A
    local AuraActionNormalized = ctx.AuraActionNormalized
    local AuraActionEditScope = ctx.AuraActionEditScope
    local AuraActionContainsAny = ctx.AuraActionContainsAny
    local AuraActionHasToken = ctx.AuraActionHasToken

    if type(AuraActionNormalized) ~= "function" or type(AuraActionEditScope) ~= "function" then return nil end
    if type(AuraActionContainsAny) ~= "function" or type(AuraActionHasToken) ~= "function" then return nil end

    local function ParseAuraBlacklistScopeAliasArgs(text)
        local P = Assistant.Parser or {}
        local normalized = AuraActionNormalized(text)
        local scope = type(P.AuraBlacklistScope) == "function" and P.AuraBlacklistScope(normalized) or AuraActionEditScope(normalized)
        if not scope then return false end
        local lane = type(P.AuraBlacklistLane) == "function" and P.AuraBlacklistLane(normalized) or "both"
        return { scope = scope, lane = lane or "both" }, {
            summary = "Uses the native exact-SpellID hidden-aura list for the selected aura lane.",
        }
    end

    local function AuraBlacklistHasDirectGroupScope(text)
        local normalized = AuraActionNormalized(text)
        if AuraActionContainsAny(normalized, {
            "player aura", "player auras", "target aura", "target auras",
            "focus aura", "focus auras", "boss aura", "boss auras",
        }) then
            return false
        end
        return AuraActionContainsAny(normalized, {
            "group aura", "group auras", "group frame aura", "group frame auras",
            "party aura", "party auras", "party buff", "party buffs", "party debuff", "party debuffs",
            "raid aura", "raid auras", "raid buff", "raid buffs", "raid debuff", "raid debuffs",
            "mythic raid aura", "mythic raid auras", "mythic raid buff", "mythic raid buffs",
            "for party", "on party", "in party", "for raid", "on raid", "in raid",
        })
    end

    local function ParseAuraBlacklistSummaryAliasArgs(text)
        if AuraActionNormalized(text):find("whitelist", 1, true) then return false end
        if not AuraActionContainsAny(text, {
            "show", "list", "summary", "current", "what is", "whats",
            "zeige", "anzeigen", "auflisten", "liste", "aktuell", "aktuelle",
        }) then
            return false
        end
        if AuraBlacklistHasDirectGroupScope(text) then return false end
        local args = ParseAuraBlacklistScopeAliasArgs(text)
        if not args then return false end
        return args, {
            summary = "Shows native exact-SpellID hidden aura entries.",
        }
    end

    local function ParseAuraBlacklistClearAliasArgs(text)
        if AuraActionNormalized(text):find("whitelist", 1, true) then return false end
        if not AuraActionContainsAny(text, {
            "clear", "empty", "reset", "allow all", "remove all", "delete all", "unblacklist all",
            "all spells", "all auras", "every spell", "every aura",
        }) then
            return false
        end
        if AuraBlacklistHasDirectGroupScope(text) then return false end
        local args = ParseAuraBlacklistScopeAliasArgs(text)
        if not args then return false end
        return args, {
            summary = "Clears native exact-SpellID hidden aura entries for the selected lane.",
        }
    end

    local function ParseAuraBlacklistSpellAliasArgs(text, raw)
        local P = Assistant.Parser or {}
        local normalized = AuraActionNormalized(text)
        if normalized:find("whitelist", 1, true) then return false end
        if normalized:find("permanent", 1, true) and not normalized:find("%d") then return false end
        if AuraBlacklistHasDirectGroupScope(normalized) then return false end
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
        if not scope then return false end
        local lane = type(P.AuraBlacklistLane) == "function" and P.AuraBlacklistLane(normalized) or "both"
        return { scope = scope, lane = lane or "both", value = value }, {
            summary = "Edits the native exact-SpellID hidden-aura list for the selected aura lane.",
        }
    end

    local function ParseAuraBlacklistAddSpellAliasArgs(text, raw)
        local normalized = AuraActionNormalized(text)
        if normalized:find("remove", 1, true) or normalized:find("delete", 1, true)
            or normalized:find("allow", 1, true) or normalized:find("unblacklist", 1, true)
            or normalized:find("unblock", 1, true) or normalized:find("entfernen", 1, true)
            or normalized:find("loeschen", 1, true) or normalized:find("unhide", 1, true)
            or normalized:find("zeige", 1, true) or normalized:find("anzeigen", 1, true)
            or normalized:find("auflisten", 1, true)
            or normalized:find("stop hiding", 1, true)
            or (normalized:find("show", 1, true) and normalized:find("again", 1, true))
            or (normalized:find("let", 1, true) and normalized:find("show", 1, true)) then
            return false
        end
        local P = Assistant.Parser or {}
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
        local P = Assistant.Parser or {}
        local normalized = AuraActionNormalized(text)
        if normalized:find("whitelist", 1, true) then return false end
        local containsAny = type(P.ContainsAny) == "function" and P.ContainsAny or nil
        if normalized:find("quick preset", 1, true) or normalized:find("quick setup", 1, true) then return false end
        if AuraBlacklistHasDirectGroupScope(normalized) then return false end
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
        if not scope then return false end
        local lane = type(P.AuraBlacklistLane) == "function" and P.AuraBlacklistLane(normalized) or "both"
        return { scope = scope, lane = lane or "both", preset = preset }, {
            summary = "Adds missing preset SpellIDs to the native hidden-aura list.",
        }
    end

    local function CustomWhitelistArgs(text, raw, mode)
        local P = Assistant.Parser or {}
        local normalized = AuraActionNormalized(text)
        if not normalized:find("whitelist", 1, true) or not normalized:find("custom", 1, true) then return false end
        local index = tonumber(normalized:match("custom%s+aura%s*([123])") or normalized:match("custom%s*([123])"))
        if not index then return false end
        local isRemove = normalized:find("remove", 1, true) or normalized:find("delete", 1, true)
            or normalized:find("unwhitelist", 1, true) or normalized:find("entfernen", 1, true)
        local isClear = normalized:find("clear", 1, true) or normalized:find("empty", 1, true)
            or normalized:find("reset", 1, true) or normalized:find("remove all", 1, true)
        local isSummary = AuraActionHasToken(normalized, "show") or AuraActionHasToken(normalized, "list")
            or AuraActionHasToken(normalized, "current") or AuraActionHasToken(normalized, "summary")
            or AuraActionHasToken(normalized, "zeige") or AuraActionHasToken(normalized, "auflisten")
        if mode == "remove" and not isRemove then return false end
        if mode == "clear" and not isClear then return false end
        if mode == "summary" and not isSummary then return false end
        if mode == "add" and (isRemove or isClear or isSummary) then return false end
        local scope = type(P.AuraBlacklistScope) == "function" and P.AuraBlacklistScope(normalized) or AuraActionEditScope(normalized)
        if not scope then return false end
        local args = { scope = scope, index = index }
        if mode == "add" or mode == "remove" then
            args.value = type(P.AuraBlacklistSpellValue) == "function" and P.AuraBlacklistSpellValue(raw or text) or nil
            if type(args.value) ~= "string" or args.value == "" then return false end
        end
        return args, { summary = "Edits the exact-SpellID whitelist for a unit-frame custom aura container." }
    end

    local function ParseAuraCustomWhitelistAddAliasArgs(text, raw) return CustomWhitelistArgs(text, raw, "add") end
    local function ParseAuraCustomWhitelistRemoveAliasArgs(text, raw) return CustomWhitelistArgs(text, raw, "remove") end
    local function ParseAuraCustomWhitelistClearAliasArgs(text, raw) return CustomWhitelistArgs(text, raw, "clear") end
    local function ParseAuraCustomWhitelistSummaryAliasArgs(text, raw) return CustomWhitelistArgs(text, raw, "summary") end

    return {
        ParseAuraBlacklistAddSpellAliasArgs = ParseAuraBlacklistAddSpellAliasArgs,
        ParseAuraBlacklistRemoveSpellAliasArgs = ParseAuraBlacklistRemoveSpellAliasArgs,
        ParseAuraBlacklistClearAliasArgs = ParseAuraBlacklistClearAliasArgs,
        ParseAuraBlacklistPresetAliasArgs = ParseAuraBlacklistPresetAliasArgs,
        ParseAuraBlacklistSummaryAliasArgs = ParseAuraBlacklistSummaryAliasArgs,
        ParseAuraCustomWhitelistAddAliasArgs = ParseAuraCustomWhitelistAddAliasArgs,
        ParseAuraCustomWhitelistRemoveAliasArgs = ParseAuraCustomWhitelistRemoveAliasArgs,
        ParseAuraCustomWhitelistClearAliasArgs = ParseAuraCustomWhitelistClearAliasArgs,
        ParseAuraCustomWhitelistSummaryAliasArgs = ParseAuraCustomWhitelistSummaryAliasArgs,
    }
end
