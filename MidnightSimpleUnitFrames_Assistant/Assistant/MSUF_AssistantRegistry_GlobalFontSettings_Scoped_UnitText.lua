-- Assistant Global Font scoped unit text registry.
-- Loaded before MSUF_AssistantRegistry_GlobalFontSettings_Scoped.lua; isolates non-group font text settings.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.RegisterScopedUnitFontTextSettings(ctx, scope)
    if type(ctx) ~= "table" or type(scope) ~= "string" or scope == "" then return false end

    local GeneralDB = ctx.GeneralDB
    local ApplyFonts = ctx.ApplyFonts
    local GlobalScopeRead = ctx.GlobalScopeRead
    local GlobalScopeWrite = ctx.GlobalScopeWrite
    local GlobalScopeAliases = ctx.GlobalScopeAliases
    local RegisterScopedSetting = ctx.RegisterScopedSetting
    local FontContext = ctx.FontContext or {}
    local FontData = FontContext.FontData or {}

    local DEFAULT_NPC_VALUES = FontData.DEFAULT_NPC_VALUES
    local DEFAULT_NPC_ALIASES = FontData.DEFAULT_NPC_ALIASES
    local DEFAULT_HEALTH_VALUES = FontData.DEFAULT_HEALTH_VALUES
    local DEFAULT_HEALTH_ALIASES = FontData.DEFAULT_HEALTH_ALIASES
    local DEFAULT_RESOURCE_VALUES = FontData.DEFAULT_RESOURCE_VALUES
    local DEFAULT_RESOURCE_ALIASES = FontData.DEFAULT_RESOURCE_ALIASES
    local NAME_TRUNCATION_VALUES = FontData.NAME_TRUNCATION_VALUES
    local NAME_TRUNCATION_ALIASES = FontData.NAME_TRUNCATION_ALIASES
    local SharedOrScopedAliases = FontContext.SharedOrScopedAliases

    if type(GeneralDB) ~= "function" or type(RegisterScopedSetting) ~= "function" then return false end
    if type(GlobalScopeRead) ~= "function" or type(GlobalScopeWrite) ~= "function" then return false end
    if type(GlobalScopeAliases) ~= "function" or type(SharedOrScopedAliases) ~= "function" then return false end
    if type(DEFAULT_NPC_VALUES) ~= "table" or type(DEFAULT_NPC_ALIASES) ~= "table" then return false end
    if type(DEFAULT_HEALTH_VALUES) ~= "table" or type(DEFAULT_HEALTH_ALIASES) ~= "table" then return false end
    if type(DEFAULT_RESOURCE_VALUES) ~= "table" or type(DEFAULT_RESOURCE_ALIASES) ~= "table" then return false end
    if type(NAME_TRUNCATION_VALUES) ~= "table" or type(NAME_TRUNCATION_ALIASES) ~= "table" then return false end

    RegisterScopedSetting("fontScope", scope, "npcNameRed", "npcNameColor", "NPC Name Text Color", "enum", "DEFAULT", SharedOrScopedAliases(scope, {
        "npc name color", "npc name red", "npc text color",
        "npc name class color", "color npc name by class", "class color npc name",
        "npc class colored name", "npc reaction color",
    }), {
        flag = "fontOverride",
        values = DEFAULT_NPC_VALUES,
        valueAliases = DEFAULT_NPC_ALIASES,
        get = function(scopeKey)
            if GlobalScopeRead(scopeKey, "fontOverride", GeneralDB(), "nameNpcClassColor", false) then return "CLASS" end
            return GlobalScopeRead(scopeKey, "fontOverride", GeneralDB(), "npcNameRed", false) and "NPC" or "DEFAULT"
        end,
        set = function(scopeKey, value)
            GlobalScopeWrite(scopeKey, "fontOverride", GeneralDB(), "nameNpcClassColor", value == "CLASS")
            GlobalScopeWrite(scopeKey, "fontOverride", GeneralDB(), "npcNameRed", value == "NPC")
        end,
        apply = ApplyFonts,
        reason = "MSUF_ASSISTANT_NPC_NAME_COLOR",
    })
    RegisterScopedSetting("fontScope", scope, "colorHealthTextByHealth", "healthTextColor", "Health Text Color Mode", "enum", "DEFAULT", SharedOrScopedAliases(scope, {
        "health text color", "hp text color", "health value color",
        "color text by health", "text color by health", "color health text",
        "health color text", "hp color text", "health text by health",
        "health text color by health", "hp text color by health",
    }), {
        flag = "fontOverride",
        values = DEFAULT_HEALTH_VALUES,
        valueAliases = DEFAULT_HEALTH_ALIASES,
        get = function(scopeKey) return GlobalScopeRead(scopeKey, "fontOverride", GeneralDB(), "colorHealthTextByHealth", false) and "HEALTH" or "DEFAULT" end,
        set = function(scopeKey, value) GlobalScopeWrite(scopeKey, "fontOverride", GeneralDB(), "colorHealthTextByHealth", value == "HEALTH") end,
        apply = ApplyFonts,
        reason = "MSUF_ASSISTANT_HEALTH_TEXT_COLOR",
    })
    RegisterScopedSetting("fontScope", scope, "colorPowerTextByType", "powerTextColor", "Power Text Color Mode", "enum", "DEFAULT", SharedOrScopedAliases(scope, {
        "power text color", "mana text color", "resource text color", "power value color",
        "color text by power", "text color by power", "color text by resource",
        "text color by resource", "color text by mana", "text color by mana",
        "color power text", "power color text", "mana color text", "resource color text",
        "power text by power", "power text by type", "power text color by power",
        "mana text color by mana", "resource text color by resource",
    }), {
        flag = "fontOverride",
        values = DEFAULT_RESOURCE_VALUES,
        valueAliases = DEFAULT_RESOURCE_ALIASES,
        get = function(scopeKey) return GlobalScopeRead(scopeKey, "fontOverride", GeneralDB(), "colorPowerTextByType", false) and "RESOURCE" or "DEFAULT" end,
        set = function(scopeKey, value) GlobalScopeWrite(scopeKey, "fontOverride", GeneralDB(), "colorPowerTextByType", value == "RESOURCE") end,
        apply = ApplyFonts,
        reason = "MSUF_ASSISTANT_POWER_TEXT_COLOR",
    })
    if scope ~= "player" then
        RegisterScopedSetting("fontScope", scope, "shortenNames", "nameShortening", "Name Shortening", "boolean", false, GlobalScopeAliases(scope, {
            "shorten names", "shorten unit names", "name shortening", "truncate names",
        }), {
            flag = "fontOverride",
            shared = "db",
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_NAME_SHORTENING",
        })
        RegisterScopedSetting("fontScope", scope, "shortenNameClipSide", "nameTruncationStyle", "Name Truncation Style", "enum", "LEFT", GlobalScopeAliases(scope, {
            "truncation style", "name truncation style", "name clip side", "shorten name side",
        }), {
            flag = "fontOverride",
            values = NAME_TRUNCATION_VALUES,
            valueAliases = NAME_TRUNCATION_ALIASES,
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_NAME_TRUNCATION_STYLE",
        })
        RegisterScopedSetting("fontScope", scope, "shortenNameMaxChars", "nameMaxChars", "Name Max Length", "number", 6, GlobalScopeAliases(scope, {
            "max name length", "name max length", "name max characters", "short name length",
        }), {
            flag = "fontOverride",
            min = 4,
            max = 30,
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_NAME_MAX_LENGTH",
        })
        RegisterScopedSetting("fontScope", scope, "shortenNameNoEllipsis", "nameNoEllipsis", "Name No Ellipsis", "boolean", false, GlobalScopeAliases(scope, {
            "no ellipsis", "hide name ellipsis", "truncate without dots", "truncate without ellipsis",
        }), {
            flag = "fontOverride",
            get = function(scopeKey) return not GlobalScopeRead(scopeKey, "fontOverride", GeneralDB(), "shortenNameShowDots", true) end,
            set = function(scopeKey, value) GlobalScopeWrite(scopeKey, "fontOverride", GeneralDB(), "shortenNameShowDots", not (value and true or false)) end,
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_NAME_NO_ELLIPSIS",
        })
    end
    return true
end
