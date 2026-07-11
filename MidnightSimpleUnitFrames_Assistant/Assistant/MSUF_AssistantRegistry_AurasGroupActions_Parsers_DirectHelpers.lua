-- Direct group aura blacklist parser intent helpers.
-- Loaded before MSUF_AssistantRegistry_AurasGroupActions_Parsers_Direct.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.BuildGroupDirectActionParserHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local Assistant = ctx.A or A
    local AuraActionNormalized = ctx.AuraActionNormalized
    if type(AuraActionNormalized) ~= "function" then return nil end

    local function GroupAuraCategoryHasUnitAuraScope(text)
        local P = Assistant.Parser or {}
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
        local P = Assistant.Parser or {}
        local normalized = AuraActionNormalized(text)
        local phrases = {
            "group aura", "group auras", "group frame aura", "group frame auras",
            "party aura", "party auras", "party buff", "party buffs", "party debuff", "party debuffs",
            "raid aura", "raid auras", "raid buff", "raid buffs", "raid debuff", "raid debuffs",
            "mythic raid aura", "mythic raid auras", "mythic raid buff", "mythic raid buffs",
            "group aura blacklist", "party aura blacklist", "raid aura blacklist",
            "party buff blacklist", "party debuff blacklist", "raid buff blacklist", "raid debuff blacklist",
            "for party", "on party", "in party", "for raid", "on raid", "in raid",
        }
        if type(P.ContainsAny) == "function" then return P.ContainsAny(normalized, phrases) end
        for i = 1, #phrases do
            if normalized:find(phrases[i], 1, true) then return true end
        end
        return false
    end

    local function DirectGroupAuraBlacklistScopeLane(text)
        local P = Assistant.Parser or {}
        local normalized = AuraActionNormalized(text)
        local scope = type(P.AuraGroupBlacklistScope) == "function" and P.AuraGroupBlacklistScope(normalized) or nil
        local lane = type(P.AuraGroupBlacklistLane) == "function" and P.AuraGroupBlacklistLane(normalized) or nil
        scope = Assistant.GroupAuraCategoryScope and Assistant.GroupAuraCategoryScope(scope) or (scope or "raid")
        lane = Assistant.GroupAuraCategoryLane and Assistant.GroupAuraCategoryLane(lane) or (lane or "buff")
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

    return {
        DirectGroupAuraBlacklistBlocked = DirectGroupAuraBlacklistBlocked,
        HasDirectGroupAuraBlacklistScope = HasDirectGroupAuraBlacklistScope,
        DirectGroupAuraBlacklistScopeLane = DirectGroupAuraBlacklistScopeLane,
        DirectGroupAuraBlacklistIntent = DirectGroupAuraBlacklistIntent,
    }
end
