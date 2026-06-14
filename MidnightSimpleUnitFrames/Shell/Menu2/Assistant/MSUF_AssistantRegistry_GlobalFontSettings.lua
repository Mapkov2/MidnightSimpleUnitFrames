-- Assistant Global Font registry: exposes shared font, size, outline, and override controls.
-- Writes must preserve Menu2 fallback semantics and avoid direct FontString runtime ownership.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local C = A.RegistryCore
if type(C) ~= "table" then return end

-- Scoped Global Fonts assistant registry domain.
local GeneralDB = C.GeneralDB
local ApplyFonts = C.ApplyFonts
local GLOBAL_SCOPE_ORDER = C.GLOBAL_SCOPE_ORDER
local NormalizeGlobalScope = C.NormalizeGlobalScope
local GlobalScopeIsGroup = C.GlobalScopeIsGroup
local GlobalScopeHasOverride = C.GlobalScopeHasOverride
local GlobalScopeSetOverride = C.GlobalScopeSetOverride
local GlobalScopeRead = C.GlobalScopeRead
local GlobalScopeWrite = C.GlobalScopeWrite
local GlobalScopeAliases = C.GlobalScopeAliases
local RegisterScopedSetting = C.RegisterScopedSetting

if type(GeneralDB) ~= "function" or type(RegisterScopedSetting) ~= "function" then return end
if type(GLOBAL_SCOPE_ORDER) ~= "table" or type(GlobalScopeAliases) ~= "function" then return end
if type(NormalizeGlobalScope) ~= "function" or type(GlobalScopeIsGroup) ~= "function" then return end
if type(GlobalScopeHasOverride) ~= "function" or type(GlobalScopeSetOverride) ~= "function" then return end
if type(GlobalScopeRead) ~= "function" or type(GlobalScopeWrite) ~= "function" then return end
do
local function SharedOrScopedAliases(scope, aliases, suffix)
    if NormalizeGlobalScope(scope) == "shared" then return aliases end
    return GlobalScopeAliases(scope, aliases, suffix)
end

local FONT_OUTLINE_VALUES = { "OUTLINE", "THICKOUTLINE", "NONE" }
local FONT_OUTLINE_ALIASES = {
    outline = "OUTLINE",
    normal = "OUTLINE",
    default = "OUTLINE",
    thick = "THICKOUTLINE",
    thickoutline = "THICKOUTLINE",
    ["thick outline"] = "THICKOUTLINE",
    bold = "THICKOUTLINE",
    none = "NONE",
    off = "NONE",
    nooutline = "NONE",
    ["no outline"] = "NONE",
}
local FONT_RENDERING_VALUES = { "SMOOTH", "SHARP" }
local FONT_RENDERING_ALIASES = {
    smooth = "SMOOTH",
    normal = "SMOOTH",
    soft = "SMOOTH",
    sharp = "SHARP",
    crisp = "SHARP",
    pixel = "SHARP",
    monochrome = "SHARP",
    mono = "SHARP",
    pixelscharf = "SHARP",
    ["pixel sharp"] = "SHARP",
}
local FONT_SHADOW_STRENGTH_VALUES = { "SOFT", "NORMAL", "DEEP" }
local FONT_SHADOW_STRENGTH_ALIASES = {
    soft = "SOFT",
    subtle = "SOFT",
    leicht = "SOFT",
    normal = "NORMAL",
    default = "NORMAL",
    standard = "NORMAL",
    deep = "DEEP",
    strong = "DEEP",
    heavy = "DEEP",
    stark = "DEEP",
}
local CLASS_DEFAULT_VALUES = { "DEFAULT", "CLASS" }
local CLASS_DEFAULT_ALIASES = {
    default = "DEFAULT",
    palette = "DEFAULT",
    class = "CLASS",
    classcolor = "CLASS",
    ["class color"] = "CLASS",
    classcolored = "CLASS",
}
local DEFAULT_NPC_VALUES = { "DEFAULT", "NPC", "CLASS" }
local DEFAULT_NPC_ALIASES = {
    default = "DEFAULT",
    palette = "DEFAULT",
    npc = "NPC",
    red = "NPC",
    npcred = "NPC",
    ["npc red"] = "NPC",
    reaction = "NPC",
    ["reaction color"] = "NPC",
    class = "CLASS",
    classcolor = "CLASS",
    ["class color"] = "CLASS",
    classcolored = "CLASS",
    ["npc class"] = "CLASS",
    ["npc class color"] = "CLASS",
}
local DEFAULT_HEALTH_VALUES = { "DEFAULT", "HEALTH" }
local DEFAULT_HEALTH_ALIASES = {
    default = "DEFAULT",
    palette = "DEFAULT",
    health = "HEALTH",
    hp = "HEALTH",
    healthcolor = "HEALTH",
    ["health color"] = "HEALTH",
}
local DEFAULT_RESOURCE_VALUES = { "DEFAULT", "RESOURCE" }
local DEFAULT_RESOURCE_ALIASES = {
    default = "DEFAULT",
    palette = "DEFAULT",
    resource = "RESOURCE",
    power = "RESOURCE",
    powercolor = "RESOURCE",
    ["power color"] = "RESOURCE",
}

local function NormalizeFontTextAlpha(value)
    value = tonumber(value) or 1
    if value > 1 and value <= 100 then value = value / 100 end
    if value <= 0.75 then return 0.70 end
    if value <= 0.925 then return 0.85 end
    return 1
end

local function ScopedFontOutline(scope)
    if GlobalScopeIsGroup(scope) then
        local value = GlobalScopeRead(scope, "fontOverride", GeneralDB(), "fontOutline", "OUTLINE")
        return value == "THICKOUTLINE" and "THICKOUTLINE" or (value == "NONE" and "NONE" or "OUTLINE")
    end
    if GlobalScopeRead(scope, "fontOverride", GeneralDB(), "noOutline", false) then return "NONE" end
    if GlobalScopeRead(scope, "fontOverride", GeneralDB(), "boldText", false) then return "THICKOUTLINE" end
    return "OUTLINE"
end

local function SetScopedFontOutline(scope, value)
    value = FONT_OUTLINE_ALIASES[value] or value
    if value ~= "THICKOUTLINE" and value ~= "NONE" then value = "OUTLINE" end
    if GlobalScopeIsGroup(scope) then
        GlobalScopeWrite(scope, "fontOverride", GeneralDB(), "fontOutline", value)
        return
    end
    GlobalScopeWrite(scope, "fontOverride", GeneralDB(), "boldText", value == "THICKOUTLINE")
    GlobalScopeWrite(scope, "fontOverride", GeneralDB(), "noOutline", value == "NONE")
end

local function ScopedFontNameColor(scope)
    if GlobalScopeIsGroup(scope) then
        return GlobalScopeRead(scope, "fontOverride", GeneralDB(), "nameColorMode", "DEFAULT") == "CLASS" and "CLASS" or "DEFAULT"
    end
    return GlobalScopeRead(scope, "fontOverride", GeneralDB(), "nameClassColor", false) and "CLASS" or "DEFAULT"
end

local function SetScopedFontNameColor(scope, value)
    value = value == "CLASS" and "CLASS" or "DEFAULT"
    if GlobalScopeIsGroup(scope) then
        GlobalScopeWrite(scope, "fontOverride", GeneralDB(), "nameColorMode", value)
    else
        GlobalScopeWrite(scope, "fontOverride", GeneralDB(), "nameClassColor", value == "CLASS")
    end
end

for _, scope in ipairs(GLOBAL_SCOPE_ORDER) do
    RegisterScopedSetting("fontScope", scope, "override", "override", "Font Override", "boolean", false, GlobalScopeAliases(scope, {
        "font override", "custom fonts", "custom font settings", "font custom settings",
    }), {
        flag = "fontOverride",
        get = function(scopeKey) return GlobalScopeHasOverride(scopeKey, "fontOverride") end,
        set = function(scopeKey, value) GlobalScopeSetOverride(scopeKey, "fontOverride", value and true or false) end,
        apply = ApplyFonts,
        reason = "MSUF_ASSISTANT_FONT_OVERRIDE",
        description = "Enables or disables custom font settings for this scope.",
    })
    RegisterScopedSetting("fontScope", scope, "fontSize", "fontSize", "Font Size", "number", 14, GlobalScopeAliases(scope, {
        "font size", "text size", "global font size", "scope font size",
    }), {
        flag = "fontOverride",
        min = 8,
        max = 32,
        apply = ApplyFonts,
        reason = "MSUF_ASSISTANT_SCOPED_FONT_SIZE",
    })
end

for _, scope in ipairs({ "shared", "player", "target", "targettarget", "focustarget", "focus", "pet", "boss", "gf_party", "gf_raid" }) do
    RegisterScopedSetting("fontScope", scope, "outline", "outline", "Font Outline", "enum", "OUTLINE", SharedOrScopedAliases(scope, {
        "font outline", "text outline", "outline style",
    }), {
        flag = "fontOverride",
        values = FONT_OUTLINE_VALUES,
        valueAliases = FONT_OUTLINE_ALIASES,
        get = ScopedFontOutline,
        set = SetScopedFontOutline,
        apply = ApplyFonts,
        reason = "MSUF_ASSISTANT_FONT_OUTLINE",
    })
    RegisterScopedSetting("fontScope", scope, "fontMonochrome", "rendering", "Rendering", "enum", "SMOOTH", SharedOrScopedAliases(scope, {
        "font rendering", "text rendering", "font smoothing", "text smoothing", "sharp text", "pixel font", "monochrome font",
    }), {
        flag = "fontOverride",
        values = FONT_RENDERING_VALUES,
        valueAliases = FONT_RENDERING_ALIASES,
        get = function(scopeKey) return GlobalScopeRead(scopeKey, "fontOverride", GeneralDB(), "fontMonochrome", false) and "SHARP" or "SMOOTH" end,
        set = function(scopeKey, value) GlobalScopeWrite(scopeKey, "fontOverride", GeneralDB(), "fontMonochrome", value == "SHARP") end,
        apply = ApplyFonts,
        reason = "MSUF_ASSISTANT_FONT_RENDERING",
    })
    RegisterScopedSetting("fontScope", scope, "fontTextAlpha", "textOpacity", "Text Opacity", "number", 1, SharedOrScopedAliases(scope, {
        "text opacity", "font opacity", "text alpha", "font alpha",
    }), {
        flag = "fontOverride",
        min = 0.7,
        max = 1,
        step = 0.05,
        percent = true,
        get = function(scopeKey) return NormalizeFontTextAlpha(GlobalScopeRead(scopeKey, "fontOverride", GeneralDB(), "fontTextAlpha", 1)) end,
        set = function(scopeKey, value) GlobalScopeWrite(scopeKey, "fontOverride", GeneralDB(), "fontTextAlpha", NormalizeFontTextAlpha(value)) end,
        apply = ApplyFonts,
        reason = "MSUF_ASSISTANT_FONT_TEXT_ALPHA",
    })
    RegisterScopedSetting("fontScope", scope, "fontBaselineOffset", "baseline", "Baseline", "number", 0, SharedOrScopedAliases(scope, {
        "text baseline", "font baseline", "baseline offset", "vertical font offset", "font y nudge", "text y nudge",
    }), {
        flag = "fontOverride",
        min = -4,
        max = 4,
        step = 1,
        apply = ApplyFonts,
        reason = "MSUF_ASSISTANT_FONT_BASELINE",
    })
    RegisterScopedSetting("fontScope", scope, "nameColorMode", "nameColor", "Name Text Color Mode", "enum", "DEFAULT", SharedOrScopedAliases(scope, {
        "name color", "name text color", "player name color", "unit name color",
        "name text by class", "name text color by class", "color name by class",
        "color name text by class", "class color name text", "class colored name text",
    }), {
        flag = "fontOverride",
        values = CLASS_DEFAULT_VALUES,
        valueAliases = CLASS_DEFAULT_ALIASES,
        get = ScopedFontNameColor,
        set = SetScopedFontNameColor,
        apply = ApplyFonts,
        reason = "MSUF_ASSISTANT_NAME_COLOR_MODE",
    })
    RegisterScopedSetting("fontScope", scope, "textBackdrop", "textShadow", "Text Shadow", "boolean", true, SharedOrScopedAliases(scope, {
        "text shadow", "font shadow", "shadow text", "shadow",
    }), {
        flag = "fontOverride",
        apply = ApplyFonts,
        reason = "MSUF_ASSISTANT_FONT_SHADOW",
    })
    RegisterScopedSetting("fontScope", scope, "fontShadowStrength", "shadowStrength", "Shadow Strength", "enum", "NORMAL", SharedOrScopedAliases(scope, {
        "shadow strength", "text shadow strength", "font shadow strength", "shadow intensity",
    }), {
        flag = "fontOverride",
        values = FONT_SHADOW_STRENGTH_VALUES,
        valueAliases = FONT_SHADOW_STRENGTH_ALIASES,
        apply = ApplyFonts,
        reason = "MSUF_ASSISTANT_FONT_SHADOW_STRENGTH",
    })
    if not GlobalScopeIsGroup(scope) then
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
                values = { "LEFT", "RIGHT" },
                valueAliases = {
                    left = "LEFT",
                    endletters = "LEFT",
                    ["keep end"] = "LEFT",
                    right = "RIGHT",
                    startletters = "RIGHT",
                    ["keep start"] = "RIGHT",
                },
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
    end
end

end
