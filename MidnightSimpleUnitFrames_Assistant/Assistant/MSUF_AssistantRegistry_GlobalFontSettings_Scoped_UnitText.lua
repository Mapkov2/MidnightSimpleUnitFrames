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

    local EnsureDB = ctx.EnsureDB
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

    if type(EnsureDB) ~= "function" or type(GeneralDB) ~= "function" or type(RegisterScopedSetting) ~= "function" then return false end
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
        dbScopeKeys = { "nameNpcClassColor", "npcNameRed" },
        apply = ApplyFonts,
        reason = "MSUF_ASSISTANT_NPC_NAME_COLOR",
    })
    RegisterScopedSetting("fontScope", scope, "colorHealthTextByHealth", "healthTextColor", "Health Text Color Mode", "enum", "DEFAULT", SharedOrScopedAliases(scope, {
        "health text color", "hp text color", "health value color",
        "color text by health", "text color by health", "color health text",
        "health color text", "hp color text", "health text by health",
        "health text color by health", "hp text color by health",
        "health text class color", "hp text class color", "color hp text by class",
    }), {
        flag = "fontOverride",
        values = DEFAULT_HEALTH_VALUES,
        valueAliases = DEFAULT_HEALTH_ALIASES,
        get = function(scopeKey)
            local value = GlobalScopeRead(scopeKey, "fontOverride", GeneralDB(), "colorHealthTextByHealth", false)
            if value == "CLASS" then return "CLASS" end
            return (value == true or value == "HEALTH") and "HEALTH" or "DEFAULT"
        end,
        set = function(scopeKey, value)
            GlobalScopeWrite(scopeKey, "fontOverride", GeneralDB(), "colorHealthTextByHealth",
                value == "CLASS" and "CLASS" or (value == "HEALTH"))
        end,
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
        local function CopySharedNameShorteningOnTransition(scopeKey)
            if scopeKey == "shared" then return end
            local db = EnsureDB()
            local scoped = type(db[scopeKey]) == "table" and db[scopeKey] or {}
            db[scopeKey] = scoped
            if scoped.fontOverride == true then return end
            local general = GeneralDB()
            -- Preserve the complete effective state. Hidden local fields may
            -- be stale while the scope follows Shared, so do not reuse them.
            scoped.shortenNames = db.shortenNames == true
            scoped.shortenNameClipSide = (general.shortenNameClipSide == "RIGHT") and "RIGHT" or "LEFT"
            scoped.shortenNameMaxChars = tonumber(general.shortenNameMaxChars) or 6
            scoped.shortenNameShowDots = general.shortenNameShowDots ~= false
        end

        local function WriteScopedName(scopeKey, sharedTable, key, value)
            CopySharedNameShorteningOnTransition(scopeKey)
            GlobalScopeWrite(scopeKey, "fontOverride", sharedTable, key, value)
        end

        RegisterScopedSetting("fontScope", scope, "shortenNames", "nameShortening", "Name Shortening", "boolean", false, GlobalScopeAliases(scope, {
            "shorten names", "shorten unit names", "name shortening", "truncate names",
        }), {
            flag = "fontOverride",
            shared = "db",
            set = function(scopeKey, value) WriteScopedName(scopeKey, EnsureDB(), "shortenNames", value and true or false) end,
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_NAME_SHORTENING",
        })
        RegisterScopedSetting("fontScope", scope, "shortenNameClipSide", "nameTruncationStyle", "Name Truncation Style", "enum", "LEFT", GlobalScopeAliases(scope, {
            "truncation style", "name truncation style", "name clip side", "shorten name side",
        }), {
            flag = "fontOverride",
            values = NAME_TRUNCATION_VALUES,
            valueAliases = NAME_TRUNCATION_ALIASES,
            set = function(scopeKey, value)
                WriteScopedName(scopeKey, GeneralDB(), "shortenNameClipSide", value == "RIGHT" and "RIGHT" or "LEFT")
            end,
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_NAME_TRUNCATION_STYLE",
        })
        RegisterScopedSetting("fontScope", scope, "shortenNameMaxChars", "nameMaxChars", "Name Max Length", "number", 6, GlobalScopeAliases(scope, {
            "max name length", "name max length", "name max characters", "short name length",
        }), {
            flag = "fontOverride",
            min = 4,
            max = 30,
            set = function(scopeKey, value)
                value = math.floor((tonumber(value) or 6) + 0.5)
                if value < 4 then value = 4 elseif value > 30 then value = 30 end
                WriteScopedName(scopeKey, GeneralDB(), "shortenNameMaxChars", value)
            end,
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_NAME_MAX_LENGTH",
        })
        RegisterScopedSetting("fontScope", scope, "shortenNameNoEllipsis", "nameNoEllipsis", "Name No Ellipsis", "boolean", false, GlobalScopeAliases(scope, {
            "no ellipsis", "hide name ellipsis", "truncate without dots", "truncate without ellipsis",
            "shortened name dots", "name shortening dots", "name dots", "name ellipsis",
            "trailing dots on shortened names",
        }), {
            flag = "fontOverride",
            get = function(scopeKey) return not GlobalScopeRead(scopeKey, "fontOverride", GeneralDB(), "shortenNameShowDots", true) end,
            set = function(scopeKey, value)
                WriteScopedName(scopeKey, GeneralDB(), "shortenNameShowDots", not (value and true or false))
            end,
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_NAME_NO_ELLIPSIS",
            description = "Controls only the trailing ellipsis on shortened unit names. Name visibility and shortening length are separate controls.",
        })
    end
    return true
end
