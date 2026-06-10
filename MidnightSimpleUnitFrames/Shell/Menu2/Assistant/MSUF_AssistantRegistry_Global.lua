local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry or { settings = {}, settingsByKey = {}, actions = {}, actionsByKey = {}, todos = {} }
A.Registry = Registry
A.Workflow = A.Workflow or {}

local C = A.RegistryCore
if type(C) ~= "table" then return end

-- Global registry domain. Shared helpers live in MSUF_AssistantRegistry_Core.lua.
local Registry = C.Registry
local UNIT_LABELS = C.UNIT_LABELS
local AddAliasesForUnit = C.AddAliasesForUnit
local EnsureDB = C.EnsureDB
local GeneralDB = C.GeneralDB
local BarsDB = C.BarsDB
local GameplayDB = C.GameplayDB
local ClampNumber = C.ClampNumber
local CallGlobal = C.CallGlobal
local ApplyGeneral = C.ApplyGeneral
local ApplyVisuals = C.ApplyVisuals
local ApplyColors = C.ApplyColors
local ApplyCastbarColors = C.ApplyCastbarColors
local ApplyGameplayColors = C.ApplyGameplayColors
local ApplyClassPowerColors = C.ApplyClassPowerColors
local ApplyAuraColors = C.ApplyAuraColors
local ApplyPortraitColors = C.ApplyPortraitColors
local ApplyFonts = C.ApplyFonts
local ApplyBars = C.ApplyBars
local ApplyBarGradients = C.ApplyBarGradients
local ApplyBarOutline = C.ApplyBarOutline
local ApplyRoundedBars = C.ApplyRoundedBars
local ApplyAggroBorder = C.ApplyAggroBorder
local ApplyDispelPurgeBorder = C.ApplyDispelPurgeBorder
local ApplyBossTargetBorder = C.ApplyBossTargetBorder
local ApplyHighlightBorders = C.ApplyHighlightBorders
local ApplyAbsorbBars = C.ApplyAbsorbBars
local ApplyClassPower = C.ApplyClassPower
local ApplyDetachedPowerBar = C.ApplyDetachedPowerBar
local ApplyDetachedPowerBarOutline = C.ApplyDetachedPowerBarOutline
local ApplyCastbar = C.ApplyCastbar
local RegisterGeneralBoolean = C.RegisterGeneralBoolean
local RegisterGeneralNumberSetting = C.RegisterGeneralNumberSetting
local RegisterGeneralEnum = C.RegisterGeneralEnum
local RegisterGeneralString = C.RegisterGeneralString
local RegisterGeneralMappedEnum = C.RegisterGeneralMappedEnum
local RegisterBarsBoolean = C.RegisterBarsBoolean
local RegisterBarsString = C.RegisterBarsString
local RegisterBarsNumber = C.RegisterBarsNumber
local RegisterBarsEnum = C.RegisterBarsEnum
local RegisterGameplayBoolean = C.RegisterGameplayBoolean
local GLOBAL_SCOPE_ORDER = C.GLOBAL_SCOPE_ORDER
local NormalizeGlobalScope = C.NormalizeGlobalScope
local GlobalScopeLabel = C.GlobalScopeLabel
local GlobalScopeIsGroup = C.GlobalScopeIsGroup
local GlobalScopeHasOverride = C.GlobalScopeHasOverride
local GlobalScopeSetOverride = C.GlobalScopeSetOverride
local GlobalScopeRead = C.GlobalScopeRead
local GlobalScopeWrite = C.GlobalScopeWrite
local GlobalScopeAliases = C.GlobalScopeAliases
local RegisterScopedSetting = C.RegisterScopedSetting
local RegisterScopedMappedEnum = C.RegisterScopedMappedEnum

local BAR_MODE_ALIASES = {
    "bar mode", "bar color mode", "health bar mode", "bars mode", "bars color mode",
    "dark mode", "class colors", "class color mode", "unified bars", "gradient bars",
    "leisten modus", "balken modus", "dunkler modus", "klassenfarben", "verlauf balken",
}
RegisterGeneralEnum("barMode", "barMode", "Global Bar Mode", "dark", { "dark", "class", "unified", "gradient" }, BAR_MODE_ALIASES, {
    category = "Global / Bars",
    frameType = "bars",
    apply = ApplyVisuals,
    reason = "MSUF_ASSISTANT_BAR_MODE",
    valueAliases = {
        dark = "dark",
        dunkel = "dark",
        black = "dark",
        class = "class",
        classes = "class",
        classcolor = "class",
        classcolors = "class",
        klassenfarben = "class",
        unified = "unified",
        same = "unified",
        einheitlich = "unified",
        gradient = "gradient",
        verlauf = "gradient",
    },
})

RegisterGeneralString("fontKey", "fontFamily", "Global Font", "FRIZQT", {
    "font", "font family", "global font", "shared font", "sharedmedia font",
}, {
    category = "Global / Fonts",
    frameType = "fonts",
    apply = ApplyFonts,
    reason = "MSUF_ASSISTANT_FONT_FAMILY",
    normalizeValue = function(value)
        value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
        return value ~= "" and value or "FRIZQT"
    end,
})

RegisterGeneralNumberSetting("fontSize", "fontSize", "Global Font Size", 14, 8, 32, {
    "font size", "global font size", "text size", "schrift groesse", "schriftgroesse", "globale schriftgroesse",
}, {
    category = "Global / Fonts",
    frameType = "fonts",
    apply = ApplyFonts,
    reason = "MSUF_ASSISTANT_FONT_SIZE",
})

RegisterGeneralEnum("fontColor", "fontColor", "Global Font Palette Color", "white", {
    "white", "black", "red", "green", "blue", "yellow", "cyan", "magenta", "orange", "purple", "pink", "turquoise", "grey", "gray", "brown", "gold",
}, {
    "font color", "global font color", "text color", "schriftfarbe", "textfarbe",
}, {
    category = "Global / Fonts",
    frameType = "fonts",
    apply = ApplyVisuals,
    reason = "MSUF_ASSISTANT_FONT_COLOR",
    valueAliases = {
        grey = "grey",
        gray = "grey",
        weiss = "white",
        schwarz = "black",
        rot = "red",
        gruen = "green",
        blau = "blue",
        gelb = "yellow",
        lila = "purple",
        violett = "purple",
        rosa = "pink",
        tuerkis = "turquoise",
        gold = "gold",
    },
})

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
local DEFAULT_NPC_VALUES = { "DEFAULT", "NPC" }
local DEFAULT_NPC_ALIASES = {
    default = "DEFAULT",
    palette = "DEFAULT",
    npc = "NPC",
    red = "NPC",
    npcred = "NPC",
    ["npc red"] = "NPC",
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
        }), {
            flag = "fontOverride",
            values = DEFAULT_NPC_VALUES,
            valueAliases = DEFAULT_NPC_ALIASES,
            get = function(scopeKey) return GlobalScopeRead(scopeKey, "fontOverride", GeneralDB(), "npcNameRed", false) and "NPC" or "DEFAULT" end,
            set = function(scopeKey, value) GlobalScopeWrite(scopeKey, "fontOverride", GeneralDB(), "npcNameRed", value == "NPC") end,
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

RegisterGeneralBoolean("slashMenuSnapEnabled", "menuSnap", "Menu Edge Snap", true, {
    "menu edge snap", "edge snap", "window snap", "menu snapping", "snapping feature", "snap feature",
    "menu snap feature", "windows style edge snap", "windows-style edge snap", "enable windows style edge snap for this menu",
    "enable windows-style edge snap for this menu", "fenster andocken",
}, { category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_MENU_SNAP" })
Registry:RegisterSetting({
    key = "general.hideAdvancedMenu",
    label = "Advanced Menu Section",
    category = "Global / Misc",
    unit = "global",
    frameType = "misc",
    attribute = "advancedMenuVisible",
    type = "boolean",
    aliases = { "advanced menu", "advanced menu section", "advanced section", "hide advanced menu", "hide advanced menu section", "show advanced menu", "show advanced menu section", "erweitertes menu" },
    get = function() return GeneralDB().hideAdvancedMenu ~= true end,
    set = function(value) GeneralDB().hideAdvancedMenu = not (value and true or false) end,
    apply = function()
        ApplyGeneral("MSUF_ASSISTANT_ADVANCED_MENU", { preview = false, applyAll = false, notify = false })
        if M and type(M.RefreshAdvancedNavVisibility) == "function" then M.RefreshAdvancedNavVisibility() end
    end,
    combatSafe = false,
})
RegisterGeneralBoolean("reduceMotion", "reduceMotion", "Reduce Menu Motion", false, {
    "reduce motion", "menu motion", "animations", "reduce animations", "reduce menu motion", "menu animations", "bewegung reduzieren",
}, { category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_REDUCE_MOTION" })
RegisterGeneralBoolean("showWelcomeMessage", "welcomeMessage", "Welcome Message", true, {
    "welcome message", "startup welcome", "start message", "show welcome message", "login welcome message", "startup message", "willkommensnachricht",
}, { category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_WELCOME" })
RegisterGeneralBoolean("versionCheckEnabled", "versionCheck", "Peer Version Check", true, {
    "version check", "peer version check", "update check", "enable version check", "peer-to-peer version check", "version check peer to peer", "versions pruefung", "versionscheck",
}, { category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_VERSION_CHECK" })
RegisterGeneralBoolean("showMinimapIcon", "minimapIcon", "MSUF Minimap Icon", true, {
    "minimap icon", "minimap button", "msuf minimap icon", "msuf minimap button", "show minimap icon", "hide minimap icon", "minikarten symbol",
}, { category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_MINIMAP_ICON" })
RegisterGeneralBoolean("playTargetSelectLostSounds", "targetSounds", "Target Select/Lost Sounds", false, {
    "target sounds", "target sound", "target lost sound", "target lost sounds", "target select sound", "target select sounds",
    "target select lost sounds", "play sound on target", "play sound on target lost", "play sound on target select", "ziel sound", "ziel sounds",
}, { category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_TARGET_SOUNDS" })
Registry:RegisterSetting({
    key = "general.disableBlizzardUnitFrames",
    label = "Blizzard Unitframes",
    category = "Global / Misc",
    unit = "global",
    frameType = "misc",
    attribute = "blizzardFramesVisible",
    type = "boolean",
    aliases = { "blizzard unitframes", "blizzard unit frames", "disable blizzard unitframes", "disable blizzard unit frames", "enable blizzard unitframes", "enable blizzard unit frames", "blizzard frames", "standard frames", "default frames" },
    get = function() return GeneralDB().disableBlizzardUnitFrames == false end,
    set = function(value) GeneralDB().disableBlizzardUnitFrames = not (value and true or false) end,
    apply = function() ApplyGeneral("MSUF_ASSISTANT_BLIZZARD_FRAMES", { preview = false, applyAll = false }) end,
    combatSafe = false,
    requiresReload = true,
})

Registry:RegisterSetting({
    key = "general.hardKillBlizzardPlayerFrame",
    label = "Fully Hide Blizzard PlayerFrame",
    category = "Global / Misc",
    unit = "global",
    frameType = "misc",
    attribute = "hardKillBlizzardPlayerFrame",
    type = "boolean",
    aliases = {
        "fully hide blizzard playerframe", "hard hide blizzard playerframe",
        "hard kill blizzard playerframe", "resource bar compatibility",
        "blizzard player frame compatibility", "hide blizzard player frame completely",
        "fully hide blizzard player frame", "hard hide blizzard player frame",
        "hard kill blizzard player frame", "fully hide blizzard playerframe resource bar compatibility",
        "fully hide blizzard playerframe - resource bar compatibility",
    },
    get = function() return GeneralDB().hardKillBlizzardPlayerFrame == true end,
    set = function(value) GeneralDB().hardKillBlizzardPlayerFrame = value and true or false end,
    apply = function()
        ApplyGeneral("MSUF_ASSISTANT_HARDKILL_PLAYERFRAME", { preview = false, applyAll = false })
        if type(_G.MSUF_ShowReloadRecommendedPopup) == "function" then _G.MSUF_ShowReloadRecommendedPopup("Blizzard PlayerFrame hide mode") end
    end,
    combatSafe = false,
    requiresReload = true,
})

Registry:RegisterSetting({
    key = "general.menuLocale",
    label = "Menu Language",
    category = "Global / Misc",
    unit = "global",
    frameType = "misc",
    attribute = "menuLocale",
    type = "enum",
    aliases = { "menu language", "msuf language", "menu locale", "locale", "language" },
    values = { "auto", "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" },
    valueAliases = {
        auto = "auto",
        blizzard = "auto",
        default = "auto",
        english = "enUS",
        ["english us"] = "enUS",
        ["us english"] = "enUS",
        ["english gb"] = "enGB",
        ["british english"] = "enGB",
        german = "deDE",
        deutsch = "deDE",
        spanish = "esES",
        ["spanish eu"] = "esES",
        ["spanish mx"] = "esMX",
        mexican = "esMX",
        french = "frFR",
        francais = "frFR",
        italian = "itIT",
        portuguese = "ptBR",
        brazilian = "ptBR",
        russian = "ruRU",
        korean = "koKR",
        chinese = "zhCN",
        simplified = "zhCN",
        traditional = "zhTW",
        taiwan = "zhTW",
    },
    get = function()
        local value = GeneralDB().menuLocale
        if value == "enUS" or value == "enGB" or value == "deDE" or value == "esES" or value == "esMX"
            or value == "frFR" or value == "itIT" or value == "ptBR" or value == "ruRU"
            or value == "koKR" or value == "zhCN" or value == "zhTW"
        then
            return value
        end
        return "auto"
    end,
    set = function(value) GeneralDB().menuLocale = tostring(value or "auto") end,
    apply = function()
        local value = GeneralDB().menuLocale or "auto"
        ApplyGeneral("MSUF_ASSISTANT_LOCALE", { preview = false, applyAll = false })
        if M and type(M.ApplyLocaleSelection) == "function" then M.ApplyLocaleSelection(value) end
        if M and type(M.InvalidatePage) == "function" then M.InvalidatePage() end
        if M and type(M.SelectPage) == "function" then M.SelectPage("opt_misc") end
    end,
    combatSafe = true,
})

Registry:RegisterSetting({
    key = "general.unitTooltipProvider",
    label = "Unitframe Tooltip Source",
    category = "Global / Misc",
    unit = "global",
    frameType = "misc",
    attribute = "tooltipProvider",
    type = "enum",
    aliases = { "tooltip source", "unitframe tooltip source", "unit tooltip source", "group frame tooltip source", "game tooltip source", "gametooltip source" },
    values = { "GAME", "MSUF" },
    valueAliases = {
        game = "GAME",
        gametooltip = "GAME",
        blizzard = "GAME",
        addoncompatible = "GAME",
        msuf = "MSUF",
        custom = "MSUF",
        panel = "MSUF",
    },
    get = function() return A.Workflow.ReadTooltipProvider() end,
    set = function(value) A.Workflow.WriteTooltipSettings(value, A.Workflow.ReadTooltipAnchor()) end,
    apply = function() A.Workflow.RefreshTooltipPreview() end,
    combatSafe = false,
})

Registry:RegisterSetting({
    key = "general.unitTooltipAnchor",
    label = "Unitframe Tooltip Anchor",
    category = "Global / Misc",
    unit = "global",
    frameType = "misc",
    attribute = "tooltipAnchor",
    type = "enum",
    aliases = { "tooltip anchor", "unitframe tooltip anchor", "unit tooltip anchor", "tooltip position", "tooltip location" },
    values = { "EXTERNAL", "FIXED", "CURSOR" },
    valueAliases = {
        external = "EXTERNAL",
        addon = "EXTERNAL",
        blizzard = "EXTERNAL",
        fixed = "FIXED",
        msuffixed = "FIXED",
        cursor = "CURSOR",
        mouse = "CURSOR",
        modern = "CURSOR",
    },
    get = function() return A.Workflow.ReadTooltipAnchor() end,
    set = function(value) A.Workflow.WriteTooltipSettings(A.Workflow.ReadTooltipProvider(), value) end,
    apply = function() A.Workflow.RefreshTooltipPreview() end,
    combatSafe = false,
})

Registry:RegisterSetting({
    key = "general.unitTooltipMode",
    label = "Show Unitframe Tooltips",
    category = "Global / Misc",
    unit = "global",
    frameType = "misc",
    attribute = "tooltipMode",
    type = "enum",
    aliases = { "show unitframe tooltips", "unitframe tooltips", "unit frame tooltips", "unit tooltips", "group frame tooltips", "tooltips", "show tooltips", "tooltip mode", "tooltip visibility" },
    values = { "ALWAYS", "OOC", "MODIFIER", "NEVER" },
    valueAliases = {
        always = "ALWAYS",
        on = "ALWAYS",
        show = "ALWAYS",
        ooc = "OOC",
        outofcombat = "OOC",
        ["out of combat"] = "OOC",
        modifier = "MODIFIER",
        key = "MODIFIER",
        alt = "MODIFIER",
        ctrl = "MODIFIER",
        shift = "MODIFIER",
        never = "NEVER",
        off = "NEVER",
        hide = "NEVER",
        disable = "NEVER",
    },
    get = function() return A.Workflow.NormalizeTooltipMode(GeneralDB().unitTooltipMode) end,
    set = function(value) A.Workflow.WriteTooltipBehavior(value, GeneralDB().unitTooltipModifier or "ALT") end,
    apply = function() A.Workflow.RefreshTooltipPreview() end,
    combatSafe = false,
})

Registry:RegisterSetting({
    key = "general.unitTooltipModifier",
    label = "Tooltip Modifier Key",
    category = "Global / Misc",
    unit = "global",
    frameType = "misc",
    attribute = "tooltipModifier",
    type = "enum",
    aliases = { "tooltip modifier", "tooltip modifier key", "unit tooltip modifier", "unitframe tooltip modifier" },
    values = { "ALT", "CTRL", "SHIFT" },
    valueAliases = {
        alt = "ALT",
        option = "ALT",
        ctrl = "CTRL",
        control = "CTRL",
        shift = "SHIFT",
    },
    get = function() return A.Workflow.NormalizeTooltipModifier(GeneralDB().unitTooltipModifier) end,
    set = function(value) A.Workflow.WriteTooltipBehavior(GeneralDB().unitTooltipMode or "MODIFIER", value) end,
    apply = function() A.Workflow.RefreshTooltipPreview() end,
    combatSafe = false,
})

Registry:RegisterSetting({
    key = "general.styleEnabled",
    label = "MSUF Style Module",
    category = "Modules / Style",
    unit = "global",
    frameType = "modules",
    attribute = "styleEnabled",
    type = "boolean",
    aliases = { "msuf style", "msuf style module", "midnight style", "style module", "module style" },
    get = function() return A.Workflow.ModuleStyleEnabled() end,
    set = function(value) A.Workflow.SetModuleStyleEnabled(value and true or false) end,
    apply = function() CallGlobal("MSUF_ApplyModules") end,
    combatSafe = true,
})

Registry:RegisterSetting({
    key = "general.dropdownStyleMode",
    label = "Dropdown Style",
    category = "Modules / Style",
    unit = "global",
    frameType = "modules",
    attribute = "dropdownStyle",
    type = "enum",
    aliases = { "dropdown style", "dropdown style mode", "dropdown module style", "menu dropdown style" },
    values = { "msuf", "old" },
    valueAliases = {
        msuf = "msuf",
        modern = "msuf",
        superellipse = "msuf",
        midnight = "msuf",
        old = "old",
        legacy = "old",
        blizzard = "old",
        classic = "old",
    },
    get = function() return A.Workflow.DropdownStyleMode() end,
    set = function(value) A.Workflow.SetDropdownStyleMode(value) end,
    apply = function() end,
    combatSafe = true,
})

RegisterGeneralBoolean("castbarShowGlow", "glow", "Castbar Glow", false, {
    "castbar glow", "cast bar glow", "castbar glow effect", "zauberleiste glow",
}, { category = "Global / Castbar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_GLOW" })
RegisterGeneralBoolean("castbarShowLatency", "latency", "Castbar Latency Indicator", true, {
    "castbar latency", "latency indicator", "castbar latency indicator", "latenz anzeige",
}, { category = "Global / Castbar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_LATENCY" })
RegisterGeneralBoolean("castbarShowSpark", "spark", "Castbar Spark", false, {
    "castbar spark", "spark", "leading edge highlight", "zauberleiste spark",
}, { category = "Global / Castbar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_SPARK" })
RegisterGeneralBoolean("castbarSparkOverflow", "sparkOverflow", "Castbar Spark Overflow", true, {
    "spark overflow", "castbar spark overflow", "spark extends beyond bar",
}, { category = "Global / Castbar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_SPARK_OVERFLOW" })
RegisterGeneralBoolean("castbarShowChannelTicks", "channelTicks", "Castbar Channel Tick Lines", false, {
    "channel ticks", "castbar ticks", "tick lines", "kanal ticks",
}, { category = "Global / Castbar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_TICKS" })
RegisterGeneralBoolean("castbarInterruptShake", "interruptShake", "Castbar Interrupt Shake", false, {
    "interrupt shake", "castbar shake", "shake on interrupt", "unterbrechung wackeln",
}, { category = "Global / Castbar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_SHAKE" })
RegisterGeneralBoolean("castbarUnifiedDirection", "unifiedDirection", "Unified Castbar Fill Direction", false, {
    "castbar unified direction", "same castbar direction", "all castbars same direction",
}, { category = "Global / Castbar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_UNIFIED_DIRECTION" })
RegisterGeneralBoolean("castbarOpositeDirectionTarget", "oppositeTargetDirection", "Opposite Fill Direction For Target", false, {
    "opposite target castbar direction", "target opposite fill direction", "target castbar opposite direction",
}, { category = "Global / Castbar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_TARGET_DIRECTION" })
RegisterGeneralNumberSetting("castbarShakeStrength", "shakeStrength", "Castbar Shake Strength", 8, 0, 30, {
    "castbar shake strength", "shake strength", "interrupt shake strength",
}, { category = "Global / Castbar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_SHAKE_STRENGTH" })
RegisterGeneralEnum("castbarFillDirection", "fillDirection", "Castbar Fill Direction", "RTL", { "RTL", "LTR" }, {
    "castbar fill direction", "fill direction", "cast direction", "zauberleiste fuellrichtung",
}, {
    category = "Global / Castbar",
    frameType = "castbarGlobal",
    apply = ApplyCastbar,
    reason = "MSUF_ASSISTANT_CASTBAR_FILL_DIRECTION",
    valueAliases = {
        left = "RTL",
        rtl = "RTL",
        righttoleft = "RTL",
        links = "RTL",
        right = "LTR",
        ltr = "LTR",
        lefttoright = "LTR",
        rechts = "LTR",
    },
})


local GRADIENT_DIRECTION_VALUES = { "RIGHT", "LEFT", "UP", "DOWN" }
local GRADIENT_DIRECTION_KEYS = {
    RIGHT = "gradientDirRight",
    LEFT = "gradientDirLeft",
    UP = "gradientDirUp",
    DOWN = "gradientDirDown",
}
local GRADIENT_DIRECTION_ALIASES = {
    right = "RIGHT",
    left = "LEFT",
    up = "UP",
    down = "DOWN",
    horizontalright = "RIGHT",
    horizontalleft = "LEFT",
    verticalup = "UP",
    verticaldown = "DOWN",
}
local ON_OFF_STORAGE = { off = 0, on = 1 }
local ON_OFF_VALUES = { "off", "on" }
local ON_OFF_ALIASES = { off = "off", disabled = "off", hide = "off", on = "on", enabled = "on", show = "on" }
local ABSORB_MODE_STORAGE = { off = 1, bar = 2 }
local ABSORB_MODE_VALUES = { "off", "bar" }
local ABSORB_MODE_ALIASES = { off = "off", disabled = "off", none = "off", bar = "bar", enabled = "bar", on = "bar" }
local ABSORB_ANCHOR_STORAGE = { left = 1, right = 2, follow = 3, overflow = 4, reverse = 5 }
local ABSORB_ANCHOR_VALUES = { "left", "right", "follow", "overflow", "reverse" }
local ABSORB_ANCHOR_ALIASES = {
    left = "left",
    right = "right",
    follow = "follow",
    ["follow hp"] = "follow",
    hp = "follow",
    overflow = "overflow",
    ["follow overflow"] = "overflow",
    reverse = "reverse",
    max = "reverse",
}
local DISPEL_TRIGGER_VALUES = { "BY_ME", "DISPEL_TYPE", "ANY_DEBUFF" }
local DISPEL_TRIGGER_ALIASES = {
    byme = "BY_ME",
    ["by me"] = "BY_ME",
    dispellable = "BY_ME",
    mine = "BY_ME",
    type = "DISPEL_TYPE",
    dispeltype = "DISPEL_TYPE",
    ["dispel type"] = "DISPEL_TYPE",
    anytype = "DISPEL_TYPE",
    any = "ANY_DEBUFF",
    anydebuff = "ANY_DEBUFF",
    ["any debuff"] = "ANY_DEBUFF",
    alldebuffs = "ANY_DEBUFF",
}
local UNIT_DISPEL_TRIGGER_VALUES = { "BORDER", "BY_ME", "DISPEL_TYPE", "ANY_DEBUFF" }
local UNIT_DISPEL_TRIGGER_ALIASES = {
    border = "BORDER",
    same = "BORDER",
    inherit = "BORDER",
    ["same as border"] = "BORDER",
    byme = "BY_ME",
    ["by me"] = "BY_ME",
    dispellable = "BY_ME",
    type = "DISPEL_TYPE",
    dispeltype = "DISPEL_TYPE",
    ["dispel type"] = "DISPEL_TYPE",
    any = "ANY_DEBUFF",
    anydebuff = "ANY_DEBUFF",
    ["any debuff"] = "ANY_DEBUFF",
}
local UNIT_DISPEL_STYLE_VALUES = { "FULL", "TOP", "BOTTOM", "LEFT", "RIGHT" }
local UNIT_DISPEL_STYLE_ALIASES = {
    full = "FULL",
    fullframe = "FULL",
    ["full frame"] = "FULL",
    top = "TOP",
    bottom = "BOTTOM",
    left = "LEFT",
    right = "RIGHT",
}
local TEXTURE_KEY_ALIASES = {
    blizzard = "Blizzard",
    flat = "Flat",
    solid = "Flat",
    white = "Flat",
    raidhp = "RaidHP",
    ["raid hp"] = "RaidHP",
    raidhealth = "RaidHP",
    ["raid health"] = "RaidHP",
    raidpower = "RaidPower",
    ["raid power"] = "RaidPower",
    skills = "Skills",
    skill = "Skills",
    outline = "Outline",
    tooltipborder = "TooltipBorder",
    ["tooltip border"] = "TooltipBorder",
    dialogbg = "DialogBG",
    ["dialog bg"] = "DialogBG",
    parchment = "Parchment",
}

local function NormalizeTextureKeyForAssistant(value)
    value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then return "" end
    local lower = value:lower():gsub("%s+", " ")
    return TEXTURE_KEY_ALIASES[lower] or TEXTURE_KEY_ALIASES[lower:gsub("%s+", "")] or value
end

RegisterGeneralString("barTexture", "texture", "Global Bar Texture", "Solid", {
    "bar texture", "bars texture", "global bar texture", "global bars texture", "health bar texture", "power bar texture", "foreground bar texture", "foreground texture", "foreground bar texture",
}, {
    category = "Global / Bars / Textures",
    frameType = "globalBars",
    apply = ApplyBars,
    reason = "MSUF_ASSISTANT_BAR_TEXTURE",
    normalizeValue = NormalizeTextureKeyForAssistant,
})
RegisterGeneralString("barBackgroundTexture", "backgroundTexture", "Global Bar Background Texture", "Solid", {
    "bar background texture", "global bar background texture", "background bar texture", "bar bg texture", "background texture", "background texture bars", "bars background texture",
}, {
    category = "Global / Bars / Textures",
    frameType = "globalBars",
    apply = ApplyBars,
    reason = "MSUF_ASSISTANT_BAR_BACKGROUND_TEXTURE",
    normalizeValue = NormalizeTextureKeyForAssistant,
})
RegisterGeneralBoolean("enableGradient", "healthGradient", "HP Bar Gradient", false, {
    "hp bar gradient", "health bar gradient", "health gradient", "hp gradient",
}, { category = "Global / Bars / Gradient", frameType = "globalBars", apply = ApplyBarGradients, reason = "MSUF_ASSISTANT_HP_GRADIENT" })
RegisterGeneralBoolean("enablePowerGradient", "powerGradient", "Power Bar Gradient", false, {
    "power bar gradient", "power gradient", "mana gradient",
}, { category = "Global / Bars / Gradient", frameType = "globalBars", apply = ApplyBarGradients, reason = "MSUF_ASSISTANT_POWER_GRADIENT" })
RegisterGeneralNumberSetting("gradientStrength", "gradientStrength", "Bar Gradient Strength", 0.45, 0, 1, {
    "gradient strength", "bar gradient strength", "health gradient strength", "power gradient strength",
}, { category = "Global / Bars / Gradient", frameType = "globalBars", apply = ApplyBarGradients, reason = "MSUF_ASSISTANT_GRADIENT_STRENGTH", step = 0.05, percent = true })
Registry:RegisterSetting({
    key = "general.gradientDirection",
    label = "Bar Gradient Direction",
    category = "Global / Bars / Gradient",
    unit = "global",
    frameType = "globalBars",
    attribute = "gradientDirection",
    type = "enum",
    aliases = { "gradient direction", "bar gradient direction", "health gradient direction", "power gradient direction" },
    values = GRADIENT_DIRECTION_VALUES,
    valueAliases = GRADIENT_DIRECTION_ALIASES,
    get = function()
        local g = GeneralDB()
        for i = 1, #GRADIENT_DIRECTION_VALUES do
            local value = GRADIENT_DIRECTION_VALUES[i]
            if g[GRADIENT_DIRECTION_KEYS[value]] == true then return value end
        end
        local value = g.gradientDirection
        return GRADIENT_DIRECTION_KEYS[value] and value or "RIGHT"
    end,
    set = function(value)
        if not GRADIENT_DIRECTION_KEYS[value] then value = "RIGHT" end
        local g = GeneralDB()
        for i = 1, #GRADIENT_DIRECTION_VALUES do
            local dir = GRADIENT_DIRECTION_VALUES[i]
            g[GRADIENT_DIRECTION_KEYS[dir]] = dir == value
        end
        g.gradientDirection = value
    end,
    apply = function() ApplyBarGradients("MSUF_ASSISTANT_GRADIENT_DIRECTION") end,
    combatSafe = false,
})

RegisterGeneralMappedEnum("absorbTextMode", "absorbMode", "Absorb Display Mode", "bar", ABSORB_MODE_VALUES, ABSORB_MODE_STORAGE, {
    "absorb display mode", "absorb mode", "absorb bars",
}, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_ABSORB_MODE", valueAliases = ABSORB_MODE_ALIASES })
RegisterGeneralMappedEnum("absorbAnchorMode", "absorbAnchor", "Absorb Bar Anchor", "right", ABSORB_ANCHOR_VALUES, ABSORB_ANCHOR_STORAGE, {
    "absorb bar anchor", "absorb anchor", "absorb anchoring",
}, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_ABSORB_ANCHOR", valueAliases = ABSORB_ANCHOR_ALIASES })
RegisterGeneralBoolean("showSelfHealPrediction", "healPrediction", "Heal Prediction Overlay", false, {
    "heal prediction", "heal prediction overlay", "incoming heal prediction", "self heal prediction",
}, {
    category = "Global / Bars / Absorb",
    frameType = "globalBars",
    apply = function(reason)
        CallGlobal("MSUF_RefreshSelfHealPredUnitEvent")
        ApplyAbsorbBars(reason)
    end,
    reason = "MSUF_ASSISTANT_HEAL_PREDICTION",
})
RegisterGeneralMappedEnum("healPredAnchorMode", "healPredictionAnchor", "Heal Prediction Anchor", "follow", ABSORB_ANCHOR_VALUES, ABSORB_ANCHOR_STORAGE, {
    "heal prediction anchor", "heal prediction anchoring", "incoming heal anchor",
}, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_HEAL_PREDICTION_ANCHOR", valueAliases = ABSORB_ANCHOR_ALIASES })
RegisterGeneralNumberSetting("absorbBarOpacity", "absorbOpacity", "Absorb Bar Opacity", 0.75, 0, 1, {
    "absorb bar opacity", "absorb opacity", "absorb alpha",
}, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_ABSORB_OPACITY", step = 0.05, percent = true })
RegisterGeneralString("absorbBarTexture", "absorbTexture", "Absorb Bar Texture", "", {
    "absorb bar texture", "absorb texture",
}, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_ABSORB_TEXTURE", normalizeValue = NormalizeTextureKeyForAssistant })
RegisterGeneralString("healAbsorbBarTexture", "healAbsorbTexture", "Heal Absorb Bar Texture", "", {
    "heal absorb texture", "heal-absorb texture", "heal absorb bar texture",
}, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_HEAL_ABSORB_TEXTURE", normalizeValue = NormalizeTextureKeyForAssistant })
RegisterGeneralNumberSetting("healAbsorbBarOpacity", "healAbsorbOpacity", "Heal Absorb Bar Opacity", 1, 0, 1, {
    "heal absorb opacity", "heal-absorb opacity", "heal absorb bar opacity",
}, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_HEAL_ABSORB_OPACITY", step = 0.05, percent = true })

RegisterBarsNumber("barOutlineThickness", "outline", "Global Bar Outline Thickness", 1, 0, 8, {
    "bar outline thickness", "bar outline", "global bar outline", "global frame outline", "frame outline", "frame outline thickness",
    "bar border thickness", "bar border", "frame border", "global frame border", "border thickness", "outline thickness",
    "make border thicker", "make border thinner", "make border bigger", "make border smaller",
    "make frame outline bigger", "make frame outline smaller", "make outline bigger", "make outline smaller",
    "border thicker", "border thinner", "border bigger", "border smaller", "outline thicker", "outline thinner", "outline bigger", "outline smaller",
}, { category = "Global / Bars / Outline", frameType = "globalBars", apply = ApplyBarOutline, reason = "MSUF_ASSISTANT_BAR_OUTLINE" })
RegisterBarsBoolean("roundedFramesEnabled", "rounded", "Rounded Frame Texture", false, {
    "rounded frame texture", "rounded frames", "round corners", "rounded corners", "rounded texture",
}, { category = "Global / Bars / Rounded", frameType = "globalBars", apply = ApplyRoundedBars, reason = "MSUF_ASSISTANT_ROUNDED_FRAMES", requiresReload = true })
RegisterBarsBoolean("roundedUnitFrames", "roundedUnitFrames", "Rounded Unit Frames", true, {
    "rounded unit frames", "rounded unitframes", "unit frame corners", "unitframe corners",
}, { category = "Global / Bars / Rounded", frameType = "globalBars", apply = ApplyRoundedBars, reason = "MSUF_ASSISTANT_ROUNDED_UNIT_FRAMES" })
RegisterBarsBoolean("roundedGroupFrames", "roundedGroupFrames", "Rounded Group Frames", true, {
    "rounded group frames", "rounded party frames", "rounded raid frames", "group frame corners",
}, { category = "Global / Bars / Rounded", frameType = "globalBars", apply = ApplyRoundedBars, reason = "MSUF_ASSISTANT_ROUNDED_GROUP_FRAMES" })
RegisterBarsBoolean("roundedPowerBars", "roundedPowerBars", "Rounded Power Bars", true, {
    "rounded power bars", "rounded powerbar", "power bar corners", "powerbar corners",
}, { category = "Global / Bars / Rounded", frameType = "globalBars", apply = ApplyRoundedBars, reason = "MSUF_ASSISTANT_ROUNDED_POWER_BARS" })
RegisterBarsBoolean("roundedMouseover", "roundedMouseover", "Rounded Mouseover Highlights", true, {
    "rounded mouseover", "rounded hover", "rounded hover border", "mouseover rounded", "rounded mouseover highlights",
}, { category = "Global / Bars / Rounded", frameType = "globalBars", apply = ApplyRoundedBars, reason = "MSUF_ASSISTANT_ROUNDED_MOUSEOVER" })

RegisterGeneralNumberSetting("highlightBorderThickness", "highlightBorder", "Highlight Border Thickness", 2, 1, 30, {
    "highlight border thickness", "highlight border size", "aggro border size", "dispel border size",
}, { category = "Global / Bars / Highlight Borders", frameType = "globalBars", apply = ApplyHighlightBorders, reason = "MSUF_ASSISTANT_HIGHLIGHT_BORDER_THICKNESS" })
RegisterGeneralMappedEnum("aggroOutlineMode", "aggroBorder", "Aggro Border", "on", ON_OFF_VALUES, ON_OFF_STORAGE, {
    "aggro border", "threat border", "aggro outline",
}, { category = "Global / Bars / Highlight Borders", frameType = "globalBars", apply = ApplyAggroBorder, reason = "MSUF_ASSISTANT_AGGRO_BORDER", valueAliases = ON_OFF_ALIASES })
RegisterGeneralMappedEnum("dispelOutlineMode", "dispelBorder", "Dispel Border", "on", ON_OFF_VALUES, ON_OFF_STORAGE, {
    "dispel border", "dispellable border", "dispel outline",
}, { category = "Global / Bars / Highlight Borders", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_DISPEL_BORDER", valueAliases = ON_OFF_ALIASES })
RegisterGeneralEnum("dispelBorderTrigger", "dispelBorderTrigger", "Dispel Border Detects", "BY_ME", DISPEL_TRIGGER_VALUES, {
    "dispel border detects", "dispel border trigger", "dispel detection",
}, { category = "Global / Bars / Highlight Borders", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_DISPEL_BORDER_TRIGGER", valueAliases = DISPEL_TRIGGER_ALIASES })
RegisterGeneralMappedEnum("purgeOutlineMode", "purgeBorder", "Purge Border", "off", ON_OFF_VALUES, ON_OFF_STORAGE, {
    "purge border", "purge outline", "purgeable border",
}, { category = "Global / Bars / Highlight Borders", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_PURGE_BORDER", valueAliases = ON_OFF_ALIASES })
RegisterGeneralMappedEnum("bossTargetOutlineMode", "bossTargetBorder", "Boss Target Border", "on", ON_OFF_VALUES, ON_OFF_STORAGE, {
    "boss target border", "boss target highlight", "boss target outline",
}, {
    category = "Global / Bars / Highlight Borders",
    frameType = "globalBars",
    apply = ApplyBossTargetBorder,
    reason = "MSUF_ASSISTANT_BOSS_TARGET_BORDER",
    valueAliases = ON_OFF_ALIASES,
    afterSet = function(value) GeneralDB().bossTargetHighlightEnabled = value == "on" end,
})
RegisterGeneralBoolean("hlPrioEnabled", "highlightPriority", "Custom Highlight Priority", false, {
    "custom highlight priority", "highlight priority", "border priority", "highlight border priority",
}, {
    category = "Global / Bars / Highlight Borders",
    frameType = "globalBars",
    apply = ApplyHighlightBorders,
    reason = "MSUF_ASSISTANT_HIGHLIGHT_PRIORITY",
})

RegisterGeneralBoolean("unitDispelOverlayEnabled", "unitDispelOverlay", "UnitFrame Dispel Overlay", false, {
    "unitframe dispel overlay", "unit frame dispel overlay", "dispel overlay", "health bar dispel overlay",
}, { category = "Global / Bars / UnitFrame Dispel Overlay", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_OVERLAY" })
RegisterGeneralEnum("unitDispelOverlayTrigger", "unitDispelOverlayTrigger", "UnitFrame Dispel Overlay Detects", "BORDER", UNIT_DISPEL_TRIGGER_VALUES, {
    "unitframe dispel overlay detects", "unitframe dispel overlay trigger", "dispel overlay detects",
}, { category = "Global / Bars / UnitFrame Dispel Overlay", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_OVERLAY_TRIGGER", valueAliases = UNIT_DISPEL_TRIGGER_ALIASES })
RegisterGeneralEnum("unitDispelOverlayStyle", "unitDispelOverlayStyle", "UnitFrame Dispel Overlay Style", "FULL", UNIT_DISPEL_STYLE_VALUES, {
    "unitframe dispel overlay style", "dispel overlay style", "unit frame dispel overlay style",
}, { category = "Global / Bars / UnitFrame Dispel Overlay", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_OVERLAY_STYLE", valueAliases = UNIT_DISPEL_STYLE_ALIASES })
RegisterGeneralBoolean("unitDispelOverlayOnHealth", "unitDispelOverlayHealthOnly", "UnitFrame Dispel Overlay Current Health Only", true, {
    "dispel overlay current health only", "unitframe dispel overlay current health", "dispel overlay on health only",
}, { category = "Global / Bars / UnitFrame Dispel Overlay", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_OVERLAY_HEALTH" })
RegisterGeneralNumberSetting("unitDispelOverlayAlpha", "unitDispelOverlayOpacity", "UnitFrame Dispel Overlay Opacity", 0.35, 0.05, 1, {
    "dispel overlay opacity", "unitframe dispel overlay opacity", "dispel overlay alpha",
}, { category = "Global / Bars / UnitFrame Dispel Overlay", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_OVERLAY_ALPHA", step = 0.05, percent = true })

RegisterBarsBoolean("smoothPowerBar", "smoothPower", "Smooth Power Bar", true, {
    "smooth power bar", "smooth power", "smooth mana bar", "power bar smoothing",
}, { category = "Global / Bars / Power", frameType = "globalBars", apply = ApplyBars, reason = "MSUF_ASSISTANT_SMOOTH_POWER" })
RegisterBarsBoolean("realtimePowerText", "realtimePowerText", "Realtime Power Text", true, {
    "realtime power text", "real time power text", "instant power text", "accurate power text",
}, { category = "Global / Bars / Power", frameType = "globalBars", apply = ApplyBars, reason = "MSUF_ASSISTANT_REALTIME_POWER_TEXT" })

for _, scope in ipairs(GLOBAL_SCOPE_ORDER) do
    RegisterScopedSetting("barScope", scope, "override", "override", "Bars Override", "boolean", false, GlobalScopeAliases(scope, {
        "bars override", "custom bars", "custom bar settings", "bar custom settings",
    }), {
        flag = "hlOverride",
        get = function(scopeKey) return GlobalScopeHasOverride(scopeKey, "hlOverride") end,
        set = function(scopeKey, value) GlobalScopeSetOverride(scopeKey, "hlOverride", value and true or false) end,
        apply = ApplyBars,
        reason = "MSUF_ASSISTANT_BARS_OVERRIDE",
        description = "Enables or disables custom Global Bars settings for this scope.",
    })
    RegisterScopedSetting("barScope", scope, "barTexture", "texture", "Bar Texture", "string", "Blizzard", GlobalScopeAliases(scope, {
        "bar texture", "bars texture", "global bar texture", "global bars texture", "health bar texture", "power bar texture", "foreground bar texture", "foreground texture", "foreground bar texture",
    }), {
        flag = "hlOverride",
        normalizeValue = NormalizeTextureKeyForAssistant,
        apply = ApplyBars,
        reason = "MSUF_ASSISTANT_SCOPED_BAR_TEXTURE",
    })
    RegisterScopedSetting("barScope", scope, "barBackgroundTexture", "backgroundTexture", "Bar Background Texture", "string", "", GlobalScopeAliases(scope, {
        "bar background texture", "background bar texture", "bar bg texture",
    }), {
        flag = "hlOverride",
        normalizeValue = NormalizeTextureKeyForAssistant,
        apply = ApplyBars,
        reason = "MSUF_ASSISTANT_SCOPED_BAR_BACKGROUND_TEXTURE",
    })
    RegisterScopedSetting("barScope", scope, "enableGradient", "healthGradient", "HP Bar Gradient", "boolean", false, GlobalScopeAliases(scope, {
        "hp bar gradient", "health bar gradient", "health gradient", "hp gradient",
    }), {
        flag = "hlOverride",
        apply = ApplyBarGradients,
        reason = "MSUF_ASSISTANT_SCOPED_HP_GRADIENT",
    })
    RegisterScopedSetting("barScope", scope, "enablePowerGradient", "powerGradient", "Power Bar Gradient", "boolean", false, GlobalScopeAliases(scope, {
        "power bar gradient", "power gradient", "mana gradient",
    }), {
        flag = "hlOverride",
        apply = ApplyBarGradients,
        reason = "MSUF_ASSISTANT_SCOPED_POWER_GRADIENT",
    })
    RegisterScopedSetting("barScope", scope, "gradientStrength", "gradientStrength", "Bar Gradient Strength", "number", 0.45, GlobalScopeAliases(scope, {
        "gradient strength", "bar gradient strength", "health gradient strength", "power gradient strength",
    }), {
        flag = "hlOverride",
        min = 0,
        max = 1,
        step = 0.05,
        percent = true,
        apply = ApplyBarGradients,
        reason = "MSUF_ASSISTANT_SCOPED_GRADIENT_STRENGTH",
    })
    RegisterScopedSetting("barScope", scope, "gradientDirection", "gradientDirection", "Bar Gradient Direction", "enum", "RIGHT", GlobalScopeAliases(scope, {
        "gradient direction", "bar gradient direction", "health gradient direction", "power gradient direction",
    }), {
        flag = "hlOverride",
        values = GRADIENT_DIRECTION_VALUES,
        valueAliases = GRADIENT_DIRECTION_ALIASES,
        get = function(scopeKey)
            for i = 1, #GRADIENT_DIRECTION_VALUES do
                local value = GRADIENT_DIRECTION_VALUES[i]
                if GlobalScopeRead(scopeKey, "hlOverride", GeneralDB(), GRADIENT_DIRECTION_KEYS[value], false) == true then return value end
            end
            local value = GlobalScopeRead(scopeKey, "hlOverride", GeneralDB(), "gradientDirection", "RIGHT")
            return GRADIENT_DIRECTION_KEYS[value] and value or "RIGHT"
        end,
        set = function(scopeKey, value)
            if not GRADIENT_DIRECTION_KEYS[value] then value = "RIGHT" end
            for i = 1, #GRADIENT_DIRECTION_VALUES do
                local dir = GRADIENT_DIRECTION_VALUES[i]
                GlobalScopeWrite(scopeKey, "hlOverride", GeneralDB(), GRADIENT_DIRECTION_KEYS[dir], dir == value)
            end
            GlobalScopeWrite(scopeKey, "hlOverride", GeneralDB(), "gradientDirection", value)
        end,
        apply = ApplyBarGradients,
        reason = "MSUF_ASSISTANT_SCOPED_GRADIENT_DIRECTION",
    })
    RegisterScopedMappedEnum("barScope", scope, "absorbTextMode", "absorbMode", "Absorb Display Mode", "bar", ABSORB_MODE_VALUES, ABSORB_MODE_STORAGE, GlobalScopeAliases(scope, {
        "absorb display mode", "absorb mode", "absorb bars",
    }), {
        flag = "hlOverride",
        valueAliases = ABSORB_MODE_ALIASES,
        apply = ApplyAbsorbBars,
        reason = "MSUF_ASSISTANT_SCOPED_ABSORB_MODE",
    })
    RegisterScopedMappedEnum("barScope", scope, "absorbAnchorMode", "absorbAnchor", "Absorb Bar Anchor", "right", ABSORB_ANCHOR_VALUES, ABSORB_ANCHOR_STORAGE, GlobalScopeAliases(scope, {
        "absorb bar anchor", "absorb anchor", "absorb anchoring",
    }), {
        flag = "hlOverride",
        valueAliases = ABSORB_ANCHOR_ALIASES,
        apply = ApplyAbsorbBars,
        reason = "MSUF_ASSISTANT_SCOPED_ABSORB_ANCHOR",
    })
    RegisterScopedSetting("barScope", scope, "absorbBarOpacity", "absorbOpacity", "Absorb Bar Opacity", "number", 0.75, GlobalScopeAliases(scope, {
        "absorb bar opacity", "absorb opacity", "absorb alpha",
    }), {
        flag = "hlOverride",
        min = 0,
        max = 1,
        step = 0.05,
        percent = true,
        apply = ApplyAbsorbBars,
        reason = "MSUF_ASSISTANT_SCOPED_ABSORB_OPACITY",
    })
    RegisterScopedSetting("barScope", scope, "absorbBarTexture", "absorbTexture", "Absorb Bar Texture", "string", "", GlobalScopeAliases(scope, {
        "absorb bar texture", "absorb texture",
    }), {
        flag = "hlOverride",
        normalizeValue = NormalizeTextureKeyForAssistant,
        apply = ApplyAbsorbBars,
        reason = "MSUF_ASSISTANT_SCOPED_ABSORB_TEXTURE",
    })
    RegisterScopedSetting("barScope", scope, "healAbsorbBarTexture", "healAbsorbTexture", "Heal Absorb Bar Texture", "string", "", GlobalScopeAliases(scope, {
        "heal absorb texture", "heal-absorb texture", "heal absorb bar texture",
    }), {
        flag = "hlOverride",
        normalizeValue = NormalizeTextureKeyForAssistant,
        apply = ApplyAbsorbBars,
        reason = "MSUF_ASSISTANT_SCOPED_HEAL_ABSORB_TEXTURE",
    })
    RegisterScopedSetting("barScope", scope, "healAbsorbBarOpacity", "healAbsorbOpacity", "Heal Absorb Bar Opacity", "number", 1, GlobalScopeAliases(scope, {
        "heal absorb opacity", "heal-absorb opacity", "heal absorb bar opacity",
    }), {
        flag = "hlOverride",
        min = 0,
        max = 1,
        step = 0.05,
        percent = true,
        apply = ApplyAbsorbBars,
        reason = "MSUF_ASSISTANT_SCOPED_HEAL_ABSORB_OPACITY",
    })
    RegisterScopedSetting("barScope", scope, "barOutlineThickness", "outline", "Bar Outline Thickness", "number", 1, GlobalScopeAliases(scope, {
        "bar outline thickness", "bar outline", "frame outline thickness", "bar border thickness",
    }), {
        flag = "hlOverride",
        shared = "bars",
        min = 0,
        max = 8,
        apply = ApplyBarOutline,
        reason = "MSUF_ASSISTANT_SCOPED_BAR_OUTLINE",
    })
    RegisterScopedSetting("barScope", scope, "highlightBorderThickness", "highlightBorder", "Highlight Border Thickness", "number", 2, GlobalScopeAliases(scope, {
        "highlight border thickness", "highlight border size", "aggro border size", "dispel border size",
    }), {
        flag = "hlOverride",
        min = 1,
        max = 30,
        apply = ApplyHighlightBorders,
        reason = "MSUF_ASSISTANT_SCOPED_HIGHLIGHT_BORDER",
    })
    RegisterScopedMappedEnum("barScope", scope, "aggroOutlineMode", "aggroBorder", "Aggro Border", "on", ON_OFF_VALUES, ON_OFF_STORAGE, GlobalScopeAliases(scope, {
        "aggro border", "threat border", "aggro outline",
    }), {
        flag = "hlOverride",
        valueAliases = ON_OFF_ALIASES,
        apply = ApplyAggroBorder,
        reason = "MSUF_ASSISTANT_SCOPED_AGGRO_BORDER",
    })
    RegisterScopedMappedEnum("barScope", scope, "dispelOutlineMode", "dispelBorder", "Dispel Border", "on", ON_OFF_VALUES, ON_OFF_STORAGE, GlobalScopeAliases(scope, {
        "dispel border", "dispellable border", "dispel outline",
    }), {
        flag = "hlOverride",
        valueAliases = ON_OFF_ALIASES,
        apply = ApplyDispelPurgeBorder,
        reason = "MSUF_ASSISTANT_SCOPED_DISPEL_BORDER",
    })
    RegisterScopedSetting("barScope", scope, "dispelBorderTrigger", "dispelBorderTrigger", "Dispel Border Detects", "enum", "BY_ME", GlobalScopeAliases(scope, {
        "dispel border detects", "dispel border trigger", "dispel detection",
    }), {
        flag = "hlOverride",
        values = DISPEL_TRIGGER_VALUES,
        valueAliases = DISPEL_TRIGGER_ALIASES,
        apply = ApplyDispelPurgeBorder,
        reason = "MSUF_ASSISTANT_SCOPED_DISPEL_TRIGGER",
    })
    RegisterScopedMappedEnum("barScope", scope, "purgeOutlineMode", "purgeBorder", "Purge Border", "off", ON_OFF_VALUES, ON_OFF_STORAGE, GlobalScopeAliases(scope, {
        "purge border", "purge outline", "purgeable border",
    }), {
        flag = "hlOverride",
        valueAliases = ON_OFF_ALIASES,
        apply = ApplyDispelPurgeBorder,
        reason = "MSUF_ASSISTANT_SCOPED_PURGE_BORDER",
    })
    if GlobalScopeIsGroup(scope) then
        RegisterScopedSetting("barScope", scope, "healPredEnabled", "healPrediction", "Heal Prediction Overlay", "boolean", false, GlobalScopeAliases(scope, {
            "heal prediction", "heal prediction overlay", "incoming heal prediction",
        }), {
            flag = "hlOverride",
            apply = ApplyAbsorbBars,
            reason = "MSUF_ASSISTANT_SCOPED_HEAL_PREDICTION",
        })
        RegisterScopedMappedEnum("barScope", scope, "healPredAnchorMode", "healPredictionAnchor", "Heal Prediction Anchor", "follow", ABSORB_ANCHOR_VALUES, ABSORB_ANCHOR_STORAGE, GlobalScopeAliases(scope, {
            "heal prediction anchor", "heal prediction anchoring", "incoming heal anchor",
        }), {
            flag = "hlOverride",
            valueAliases = ABSORB_ANCHOR_ALIASES,
            apply = ApplyAbsorbBars,
            reason = "MSUF_ASSISTANT_SCOPED_HEAL_PREDICTION_ANCHOR",
        })
    else
        RegisterScopedSetting("barScope", scope, "unitDispelOverlayEnabled", "unitDispelOverlay", "UnitFrame Dispel Overlay", "boolean", false, GlobalScopeAliases(scope, {
            "unitframe dispel overlay", "unit frame dispel overlay", "dispel overlay", "health bar dispel overlay",
        }), {
            flag = "hlOverride",
            apply = ApplyDispelPurgeBorder,
            reason = "MSUF_ASSISTANT_SCOPED_UNIT_DISPEL_OVERLAY",
        })
        RegisterScopedSetting("barScope", scope, "unitDispelOverlayTrigger", "unitDispelOverlayTrigger", "UnitFrame Dispel Overlay Detects", "enum", "BORDER", GlobalScopeAliases(scope, {
            "unitframe dispel overlay detects", "unitframe dispel overlay trigger", "dispel overlay detects",
        }), {
            flag = "hlOverride",
            values = UNIT_DISPEL_TRIGGER_VALUES,
            valueAliases = UNIT_DISPEL_TRIGGER_ALIASES,
            apply = ApplyDispelPurgeBorder,
            reason = "MSUF_ASSISTANT_SCOPED_UNIT_DISPEL_OVERLAY_TRIGGER",
        })
        RegisterScopedSetting("barScope", scope, "unitDispelOverlayStyle", "unitDispelOverlayStyle", "UnitFrame Dispel Overlay Style", "enum", "FULL", GlobalScopeAliases(scope, {
            "unitframe dispel overlay style", "dispel overlay style", "unit frame dispel overlay style",
        }), {
            flag = "hlOverride",
            values = UNIT_DISPEL_STYLE_VALUES,
            valueAliases = UNIT_DISPEL_STYLE_ALIASES,
            apply = ApplyDispelPurgeBorder,
            reason = "MSUF_ASSISTANT_SCOPED_UNIT_DISPEL_OVERLAY_STYLE",
        })
        RegisterScopedSetting("barScope", scope, "unitDispelOverlayOnHealth", "unitDispelOverlayHealthOnly", "UnitFrame Dispel Overlay Current Health Only", "boolean", true, GlobalScopeAliases(scope, {
            "dispel overlay current health only", "unitframe dispel overlay current health", "dispel overlay on health only",
        }), {
            flag = "hlOverride",
            apply = ApplyDispelPurgeBorder,
            reason = "MSUF_ASSISTANT_SCOPED_UNIT_DISPEL_OVERLAY_HEALTH",
        })
        RegisterScopedSetting("barScope", scope, "unitDispelOverlayAlpha", "unitDispelOverlayOpacity", "UnitFrame Dispel Overlay Opacity", "number", 0.35, GlobalScopeAliases(scope, {
            "dispel overlay opacity", "unitframe dispel overlay opacity", "dispel overlay alpha",
        }), {
            flag = "hlOverride",
            min = 0.05,
            max = 1,
            step = 0.05,
            percent = true,
            apply = ApplyDispelPurgeBorder,
            reason = "MSUF_ASSISTANT_SCOPED_UNIT_DISPEL_OVERLAY_ALPHA",
        })
    end
end

local function ResetGlobalScopeOverride(flag, scope, applyFn, reason)
    scope = NormalizeGlobalScope(scope)
    if scope == "shared" then return false, "Shared scope has no override to reset." end
    GlobalScopeSetOverride(scope, flag, false)
    if type(applyFn) == "function" then applyFn(reason) end
    return true, "Done. " .. GlobalScopeLabel(scope) .. " now follows Shared settings."
end

local function ResetAllGlobalScopeOverrides(flag, applyFn, reason, label)
    for _, scope in ipairs(GLOBAL_SCOPE_ORDER) do
        GlobalScopeSetOverride(scope, flag, false)
    end
    if type(applyFn) == "function" then applyFn(reason) end
    return true, "Done. Reset all scoped " .. tostring(label or "override") .. " overrides."
end

Registry:RegisterAction({
    key = "reset_scoped_global_bars_override",
    label = "Reset Scoped Bars Override",
    type = "globalBars",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        return ResetGlobalScopeOverride("hlOverride", args and args.scope, ApplyBars, "MSUF_ASSISTANT_RESET_SCOPED_BARS")
    end,
})

Registry:RegisterAction({
    key = "reset_all_scoped_global_bars_overrides",
    label = "Reset All Scoped Bars Overrides",
    type = "globalBars",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    run = function()
        return ResetAllGlobalScopeOverrides("hlOverride", ApplyBars, "MSUF_ASSISTANT_RESET_ALL_SCOPED_BARS", "Bars")
    end,
})

Registry:RegisterAction({
    key = "reset_scoped_global_font_override",
    label = "Reset Scoped Font Override",
    type = "fonts",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        return ResetGlobalScopeOverride("fontOverride", args and args.scope, ApplyFonts, "MSUF_ASSISTANT_RESET_SCOPED_FONTS")
    end,
})

Registry:RegisterAction({
    key = "reset_all_scoped_global_font_overrides",
    label = "Reset All Scoped Font Overrides",
    type = "fonts",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    run = function()
        return ResetAllGlobalScopeOverrides("fontOverride", ApplyFonts, "MSUF_ASSISTANT_RESET_ALL_SCOPED_FONTS", "Font")
    end,
})


Registry:RegisterAction({
    key = "toggle_absorb_bar_test",
    label = "Toggle Absorb Bar Test",
    type = "globalBars",
    combatSafe = true,
    run = function(args)
        local value = args and args.value
        if value == nil then value = not (_G.MSUF_AbsorbTextureTestMode == true) end
        local fn = _G.MSUF_SetAbsorbTextureTestMode
        if type(fn) == "function" then
            fn(value and true or false, "shared")
        else
            _G.MSUF_AbsorbTextureTestMode = value and true or false
            _G.MSUF_AbsorbTextureTestScope = "shared"
        end
        ApplyAbsorbBars("MSUF_ASSISTANT_ABSORB_TEST")
        return true, (value and "Enabled" or "Disabled") .. " absorb prediction bar test."
    end,
})

Registry:RegisterAction({
    key = "toggle_highlight_border_test",
    label = "Toggle Highlight Border Test",
    type = "globalBars",
    combatSafe = true,
    run = function(args)
        local kind = tostring(args and args.kind or "aggro")
        local enabled = args and args.value
        if enabled == nil then enabled = true end
        local setterName
        if kind == "dispel" then setterName = "MSUF_SetDispelBorderTestMode"
        elseif kind == "purge" then setterName = "MSUF_SetPurgeBorderTestMode"
        elseif kind == "bossTarget" then setterName = "MSUF_SetBossTargetBorderTestMode"
        else kind, setterName = "aggro", "MSUF_SetAggroBorderTestMode" end
        local fn = _G[setterName]
        if type(fn) == "function" then
            if kind == "bossTarget" then fn(enabled and true or false) else fn(enabled and true or false, "shared") end
        else
            _G["MSUF_" .. kind .. "BorderTestMode"] = enabled and true or false
        end
        return true, (enabled and "Enabled" or "Disabled") .. " " .. tostring(kind) .. " border test."
    end,
})

Registry:RegisterAction({
    key = "set_dispel_border_test_type",
    label = "Set Dispel Border Test Type",
    type = "globalBars",
    combatSafe = true,
    run = function(args)
        local value = tostring(args and args.value or "Magic")
        local allowed = { Magic = true, Curse = true, Disease = true, Poison = true, Bleed = true }
        if not allowed[value] then value = "Magic" end
        _G.MSUF_DispelBorderTestType = value
        local gp = M and M.GlobalPage
        if gp and type(gp.RefreshBorderTestModes) == "function" then gp.RefreshBorderTestModes() end
        return true, "Done. Dispel border test type set to " .. value .. "."
    end,
})

local COLOR_ALIASES = {
    gray = "grey",
    violet = "purple",
    aqua = "cyan",
    teal = "turquoise",
    weiss = "white",
    schwarz = "black",
    rot = "red",
    gruen = "green",
    blau = "blue",
    gelb = "yellow",
    lila = "purple",
    rosa = "pink",
    tuerkis = "turquoise",
}

local FALLBACK_COLORS = {
    white = { 1, 1, 1 },
    black = { 0, 0, 0 },
    red = { 1, 0, 0 },
    green = { 0, 1, 0 },
    blue = { 0, 0, 1 },
    yellow = { 1, 1, 0 },
    cyan = { 0, 1, 1 },
    magenta = { 1, 0, 1 },
    orange = { 1, 0.5, 0 },
    purple = { 0.6, 0, 0.8 },
    pink = { 1, 0.6, 0.8 },
    turquoise = { 0, 0.9, 0.8 },
    grey = { 0.5, 0.5, 0.5 },
    brown = { 0.6, 0.3, 0.1 },
    gold = { 1, 0.85, 0.1 },
}

local function Clamp01(value)
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function ColorFromName(name)
    name = tostring(name or ""):lower()
    name = COLOR_ALIASES[name] or name
    local palette = (MSUF and MSUF.MSUF_FONT_COLORS) or _G.MSUF_FONT_COLORS or FALLBACK_COLORS
    local color = palette and palette[name]
    if type(color) == "table" then
        return Clamp01(color[1] or color.r or 1), Clamp01(color[2] or color.g or 1), Clamp01(color[3] or color.b or 1), name
    end
    color = FALLBACK_COLORS[name]
    if type(color) == "table" then return color[1], color[2], color[3], name end
    return nil
end
A.ColorFromName = A.ColorFromName or ColorFromName

local function HexToColor(hex)
    hex = tostring(hex or ""):match("^#?(%x%x%x%x%x%x)$")
    if not hex then return nil end
    local r = tonumber(hex:sub(1, 2), 16) or 255
    local g = tonumber(hex:sub(3, 4), 16) or 255
    local b = tonumber(hex:sub(5, 6), 16) or 255
    return r / 255, g / 255, b / 255, "#" .. hex:upper()
end
A.HexToColor = A.HexToColor or HexToColor

local function ColorAPI()
    return (MSUF and MSUF._colorsAPI) or {}
end

local function ColorValue(r, g, b, label)
    return {
        r = Clamp01(r),
        g = Clamp01(g),
        b = Clamp01(b),
        label = label,
    }
end

local function ColorComponents(value, dr, dg, db)
    if type(value) == "table" then
        return Clamp01(value.r or value[1] or dr), Clamp01(value.g or value[2] or dg), Clamp01(value.b or value[3] or db)
    end
    if type(value) == "string" then
        local r, g, b = ColorFromName(value)
        if r then return r, g, b end
    end
    return Clamp01(dr), Clamp01(dg), Clamp01(db)
end

local function ColorSame(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    local ar, ag, ab = ColorComponents(a, 0, 0, 0)
    local br, bg, bb = ColorComponents(b, 0, 0, 0)
    return math.abs(ar - br) < 0.0005 and math.abs(ag - bg) < 0.0005 and math.abs(ab - bb) < 0.0005
end

local function ColorSetting(key, label, aliases, getRGB, setRGB, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = key,
        label = label,
        category = opts.category or "Colors",
        unit = opts.unit or "global",
        frameType = opts.frameType or "colors",
        attribute = opts.attribute or key,
        type = "color",
        aliases = aliases,
        get = function()
            local r, g, b, colorLabel = getRGB()
            return ColorValue(r, g, b, colorLabel)
        end,
        set = function(value)
            local r, g, b = ColorComponents(value, opts.defaultR or 1, opts.defaultG or 1, opts.defaultB or 1)
            setRGB(r, g, b, value)
        end,
        sameValue = ColorSame,
        apply = opts.apply or ApplyColors,
        combatSafe = opts.combatSafe == true,
    })
end

local function ApiRGB(getName, dr, dg, db, fallback)
    local fn = ColorAPI()[getName]
    if type(fn) == "function" then
        local r, g, b = fn()
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
    end
    if type(fallback) == "function" then
        local r, g, b = fallback()
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
    end
    return dr, dg, db
end

local function ApiSetRGB(setName, r, g, b, alpha)
    local fn = ColorAPI()[setName]
    if type(fn) == "function" then
        if alpha ~= nil then fn(r, g, b, alpha) else fn(r, g, b) end
        return true
    end
    return false
end

local function GeneralRGB(prefix, dr, dg, db)
    local g = GeneralDB()
    return tonumber(g[prefix .. "R"]) or dr, tonumber(g[prefix .. "G"]) or dg, tonumber(g[prefix .. "B"]) or db
end

local function SetGeneralRGB(prefix, r, gCol, b)
    local g = GeneralDB()
    g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"] = r, gCol, b
end

local function GeneralRGBAlias(primaryPrefix, legacyPrefix, dr, dg, db)
    local g = GeneralDB()
    return tonumber(g[primaryPrefix .. "R"]) or tonumber(g[legacyPrefix .. "R"]) or dr,
        tonumber(g[primaryPrefix .. "G"]) or tonumber(g[legacyPrefix .. "G"]) or dg,
        tonumber(g[primaryPrefix .. "B"]) or tonumber(g[legacyPrefix .. "B"]) or db
end

local function SetGeneralRGBAlias(primaryPrefix, legacyPrefix, r, gCol, b)
    local g = GeneralDB()
    g[primaryPrefix .. "R"], g[primaryPrefix .. "G"], g[primaryPrefix .. "B"] = r, gCol, b
    g[legacyPrefix .. "R"], g[legacyPrefix .. "G"], g[legacyPrefix .. "B"] = r, gCol, b
end

local function TableRGB(tbl, key, dr, dg, db)
    local t = tbl and tbl[key]
    if type(t) == "table" then
        local r = tonumber(t.r or t[1] or t["1"])
        local g = tonumber(t.g or t[2] or t["2"])
        local b = tonumber(t.b or t[3] or t["3"])
        if r and g and b then return r, g, b end
    end
    return dr, dg, db
end

local function SetTableRGB(tbl, key, r, gCol, b)
    if type(tbl) == "table" then tbl[key] = { r, gCol, b } end
end

local function EnsurePowerOverrides()
    local g = GeneralDB()
    g.powerColorOverrides = type(g.powerColorOverrides) == "table" and g.powerColorOverrides or {}
    return g.powerColorOverrides
end

local function PowerDefaultRGB(token)
    local color = _G.PowerBarColor and token and _G.PowerBarColor[token]
    if type(color) == "table" then
        local r = tonumber(color.r or color[1])
        local g = tonumber(color.g or color[2])
        local b = tonumber(color.b or color[3])
        if r and g and b then return r, g, b end
    end
    return 0.8, 0.8, 0.8
end

local function PowerOverrideRGB(token)
    local dr, dg, db = PowerDefaultRGB(token)
    return TableRGB(GeneralDB().powerColorOverrides, token, dr, dg, db)
end

local function SetPowerOverrideRGB(token, r, gCol, b)
    EnsurePowerOverrides()[token] = { r, gCol, b }
end

local CP_SLOT_DEFAULTS = {
    COMBO_POINTS_1 = { 0.00, 0.95, 1.00 },
    COMBO_POINTS_2 = { 0.00, 0.95, 1.00 },
    COMBO_POINTS_3 = { 1.00, 1.00, 0.00 },
    COMBO_POINTS_4 = { 1.00, 1.00, 0.00 },
    COMBO_POINTS_5 = { 1.00, 1.00, 0.00 },
    COMBO_POINTS_6 = { 1.00, 0.05, 0.05 },
    COMBO_POINTS_7 = { 1.00, 0.05, 0.05 },
}

local function EnsureClassPowerOverrides()
    local g = GeneralDB()
    g.classPowerColorOverrides = type(g.classPowerColorOverrides) == "table" and g.classPowerColorOverrides or {}
    g.classPowerBgColorOverrides = type(g.classPowerBgColorOverrides) == "table" and g.classPowerBgColorOverrides or {}
    return g
end

local function ClassPowerDefaultRGB(token)
    local slot = CP_SLOT_DEFAULTS[token]
    if slot then return slot[1], slot[2], slot[3] end
    if token == "CHARGED" then return 0.60, 0.20, 0.80 end
    if token == "RESOURCE_TEXT" then return ApiRGB("GetGlobalFontColor", 1, 1, 1, function() return GeneralRGB("fontColorCustom", 1, 1, 1) end) end
    if token == "SOUL_FRAGMENTS" then return 0.00, 0.80, 0.00 end
    if token == "SOUL_FRAGMENTS_META" then return 0.60, 0.20, 0.93 end
    if token == "MAELSTROM" or token == "MAELSTROM_POWER" then return PowerDefaultRGB("MAELSTROM") end
    if token == "MAELSTROM_ABOVE_5" then return 1.00, 0.50, 0.00 end
    if token == "ASTRAL_POWER" or token == "AP_PREDICTION" then return PowerDefaultRGB("LUNAR_POWER") end
    if token == "ECLIPSE_SOLAR" then return 0.82, 0.56, 0.25 end
    if token == "ECLIPSE_LUNAR" then return 0.41, 0.49, 0.82 end
    if token == "ECLIPSE_CA" then return 0.30, 1.00, 0.43 end
    if token == "STAGGER_GREEN" then return 0.52, 1.00, 0.52 end
    if token == "STAGGER_YELLOW" then return 1.00, 0.98, 0.72 end
    if token == "STAGGER_RED" then return 1.00, 0.42, 0.42 end
    if token == "SOUL_FRAGMENTS_VENG" then return 0.34, 0.06, 0.46 end
    if token == "INSANITY" then return PowerDefaultRGB("INSANITY") end
    if token == "WHIRLWIND" then return 0.20, 0.80, 0.20 end
    if token == "TIP_OF_THE_SPEAR" then return 0.60, 0.80, 0.20 end
    if token == "ICICLES" then return 0.50, 0.80, 1.00 end
    if token == "EBON_MIGHT" then return 0.40, 0.80, 0.60 end
    return PowerDefaultRGB(token)
end

local function ClassPowerRGB(token)
    local dr, dg, db = ClassPowerDefaultRGB(token)
    return TableRGB(GeneralDB().classPowerColorOverrides, token, dr, dg, db)
end

local function SetClassPowerRGB(token, r, gCol, b)
    EnsureClassPowerOverrides().classPowerColorOverrides[token] = { r, gCol, b }
end

local function ClassPowerBgRGB(token)
    return TableRGB(GeneralDB().classPowerBgColorOverrides, token, 0, 0, 0)
end

local function SetClassPowerBgRGB(token, r, gCol, b)
    EnsureClassPowerOverrides().classPowerBgColorOverrides[token] = { r, gCol, b }
end

local function AuraSharedDB()
    local db = GeneralDB()
    db.auras3 = type(db.auras3) == "table" and db.auras3 or {}
    db.auras3.shared = type(db.auras3.shared) == "table" and db.auras3.shared or {}
    return db.auras3.shared
end

local function SetAllPortraitRGB(prefix, r, gCol, b)
    local general = GeneralDB()
    general[prefix .. "R"], general[prefix .. "G"], general[prefix .. "B"] = r, gCol, b
    local db = EnsureDB()
    for _, unit in ipairs({ "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }) do
        db[unit] = type(db[unit]) == "table" and db[unit] or {}
        db[unit][prefix .. "R"], db[unit][prefix .. "G"], db[unit][prefix .. "B"] = r, gCol, b
    end
end


function A.Workflow.ClampScale(value, minValue, maxValue)
    return ClampNumber(value, minValue or 0.25, maxValue or 1.5, 0.01)
end

function A.Workflow.GlobalScaleState()
    local g = GeneralDB()
    g.UIScale = type(g.UIScale) == "table" and g.UIScale or { Enabled = false, Scale = 1 }
    local ui = g.UIScale
    ui.Enabled = ui.Enabled == true
    ui.Scale = A.Workflow.ClampScale(ui.Scale, 0.3, 1.5) or 1
    return g, ui
end

function A.Workflow.PixelScale()
    if type(_G.MSUF_GetPixelPerfectScale) == "function" then
        local value = tonumber(_G.MSUF_GetPixelPerfectScale())
        if value then return A.Workflow.ClampScale(value, 0.3, 1.5) or 1 end
    end
    if type(_G.GetPhysicalScreenSize) == "function" then
        local _, height = _G.GetPhysicalScreenSize()
        height = tonumber(height)
        if height and height > 0 then return A.Workflow.ClampScale(768 / height, 0.3, 1.5) or 1 end
    end
    return 1
end

function A.Workflow.GlobalScalePresetValue(preset)
    preset = tostring(preset or "custom"):lower()
    if preset == "1080" or preset == "1080p" then return true, 768 / 1080, "1080p" end
    if preset == "1440" or preset == "1440p" then return true, 768 / 1440, "1440p" end
    if preset == "4k" or preset == "2160" or preset == "2160p" then return true, 768 / 2160, "4k" end
    if preset == "pixel" or preset == "pixel perfect" then return true, A.Workflow.PixelScale(), "pixel" end
    if preset == "off" or preset == "auto" or preset == "disabled" then return false, 1, "auto" end
    return nil, nil, nil
end

function A.Workflow.SetGlobalScaleState(enabled, value, preset)
    local g, ui = A.Workflow.GlobalScaleState()
    ui.Enabled = enabled == true
    ui.Scale = A.Workflow.ClampScale(value or ui.Scale, 0.3, 1.5) or 1
    g.globalUiScalePreset = preset or (ui.Enabled and "custom" or "auto")
    g.globalUiScaleValue = ui.Enabled and ui.Scale or nil
end

function A.Workflow.PushGlobalScale()
    local _, ui = A.Workflow.GlobalScaleState()
    if ui.Enabled and type(_G.MSUF_SetGlobalUiScale) == "function" then
        _G.MSUF_SetGlobalUiScale(ui.Scale, true)
    elseif (not ui.Enabled) and type(_G.MSUF_ResetGlobalUiScale) == "function" then
        _G.MSUF_ResetGlobalUiScale(true)
    end
    ApplyGeneral("MSUF_ASSISTANT_GLOBAL_UI_SCALE", { preview = true, applyAll = false })
end

function A.Workflow.ApplyScalePreset(preset)
    local enabled, value, key = A.Workflow.GlobalScalePresetValue(preset)
    if enabled == nil then return false, "I do not know that global UI scale preset." end
    A.Workflow.SetGlobalScaleState(enabled, value, key)
    A.Workflow.PushGlobalScale()
    return true, enabled and ("Done. Applied global UI scale preset " .. tostring(key) .. ".") or "Done. Global UI scale override is off."
end

function A.Workflow.ApplyMsufScale(value)
    local scale = A.Workflow.ClampScale(value, 0.25, 1.5) or 1
    GeneralDB().msufUiScale = scale
    if type(_G.MSUF_ApplyMsufScale) == "function" then _G.MSUF_ApplyMsufScale(scale) end
    ApplyGeneral("MSUF_ASSISTANT_MSUF_SCALE", { preview = true, applyAll = false })
    local UF = MSUF and MSUF.UF
    if UF and type(UF.Apply) == "function" then UF.Apply(nil) end
end

function A.Workflow.ApplyMenuScale(value)
    local scale = A.Workflow.ClampScale(value, 0.25, 1.5) or 1
    GeneralDB().slashMenuScale = scale
    if M and M.frame and type(M.frame.SetScale) == "function" then
        M.frame:SetScale((M.GetEffectiveMenuScale and M.GetEffectiveMenuScale(scale)) or scale)
    end
end

function A.Workflow.ModuleStyleEnabled()
    if type(_G.MSUF_StyleIsEnabled) == "function" then return _G.MSUF_StyleIsEnabled() and true or false end
    return GeneralDB().styleEnabled ~= false
end

function A.Workflow.SetModuleStyleEnabled(enabled)
    enabled = enabled and true or false
    if type(_G.MSUF_SetStyleEnabled) == "function" then
        _G.MSUF_SetStyleEnabled(enabled)
    else
        GeneralDB().styleEnabled = enabled
    end
    GeneralDB().styleEnabled = enabled
    CallGlobal("MSUF_ApplyModules")
end

function A.Workflow.NormalizeDropdownStyleMode(mode)
    mode = tostring(mode or "msuf"):lower()
    if mode == "old" or mode == "blizzard" or mode == "legacy" then return "old" end
    return "msuf"
end

function A.Workflow.DropdownStyleMode()
    if type(_G.MSUF_GetDropdownStyleMode) == "function" then return A.Workflow.NormalizeDropdownStyleMode(_G.MSUF_GetDropdownStyleMode()) end
    return A.Workflow.NormalizeDropdownStyleMode(GeneralDB().dropdownStyleMode)
end

function A.Workflow.SetDropdownStyleMode(mode)
    mode = A.Workflow.NormalizeDropdownStyleMode(mode)
    if type(_G.MSUF_ApplyDropdownStyleModeImmediate) == "function" then
        _G.MSUF_ApplyDropdownStyleModeImmediate(mode)
    elseif type(_G.MSUF_SetDropdownStyleMode) == "function" then
        _G.MSUF_SetDropdownStyleMode(mode)
        GeneralDB().dropdownStyleMode = mode
    else
        GeneralDB().dropdownStyleMode = mode
    end
end

function A.Workflow.NormalizeTooltipMode(mode)
    mode = tostring(mode or "ALWAYS"):upper()
    if mode == "OOC" or mode == "MODIFIER" or mode == "NEVER" then return mode end
    if mode == "OFF" then return "NEVER" end
    return "ALWAYS"
end

function A.Workflow.NormalizeTooltipModifier(modifier)
    modifier = tostring(modifier or "ALT"):upper()
    if modifier == "CTRL" or modifier == "SHIFT" then return modifier end
    return "ALT"
end

function A.Workflow.ReadTooltipProvider()
    local g = GeneralDB()
    if g.unitTooltipProvider == "MSUF" then return "MSUF" end
    if g.unitTooltipProvider == "GAME" then return "GAME" end
    return g.disableUnitInfoTooltips == false and "MSUF" or "GAME"
end

function A.Workflow.ReadTooltipAnchor()
    local g = GeneralDB()
    local anchor = g.unitTooltipAnchor
    if anchor == "EXTERNAL" or anchor == "FIXED" or anchor == "CURSOR" then return anchor end
    if A.Workflow.ReadTooltipProvider() == "MSUF" then
        return g.unitInfoTooltipStyle == "modern" and "CURSOR" or "FIXED"
    end
    if type(g.tooltipPosX) == "number" and type(g.tooltipPosY) == "number" then return "FIXED" end
    if g.unitInfoTooltipStyle == "modern" then return "CURSOR" end
    return "EXTERNAL"
end

function A.Workflow.RefreshTooltipPreview()
    local tooltips = MSUF and MSUF.Tooltips
    if tooltips and type(tooltips.Refresh) == "function" then tooltips.Refresh() end
    local editActive = _G.MSUF_UnitEditModeActive == true
    if not editActive and type(_G.MSUF_IsMSUFEditModeActive) == "function" then editActive = _G.MSUF_IsMSUFEditModeActive() and true or false end
    if editActive and type(_G.MSUF_Tooltip_ShowEditPreview) == "function" then _G.MSUF_Tooltip_ShowEditPreview() end
end

function A.Workflow.WriteTooltipSettings(provider, anchor)
    local g = GeneralDB()
    provider = provider == "MSUF" and "MSUF" or "GAME"
    if anchor ~= "FIXED" and anchor ~= "CURSOR" and anchor ~= "EXTERNAL" then anchor = "EXTERNAL" end
    if provider == "MSUF" and anchor == "EXTERNAL" then anchor = "FIXED" end
    g.unitTooltipProvider = provider
    g.unitTooltipAnchor = anchor
    g.disableUnitInfoTooltips = provider ~= "MSUF"
    g.unitInfoTooltipStyle = anchor == "CURSOR" and "modern" or "classic"
    ApplyGeneral("MSUF_ASSISTANT_TOOLTIPS", { preview = false, applyAll = false, notify = false })
    A.Workflow.RefreshTooltipPreview()
end

function A.Workflow.WriteTooltipBehavior(mode, modifier)
    local g = GeneralDB()
    g.unitTooltipMode = A.Workflow.NormalizeTooltipMode(mode)
    g.unitTooltipModifier = A.Workflow.NormalizeTooltipModifier(modifier)
    ApplyGeneral("MSUF_ASSISTANT_TOOLTIP_BEHAVIOR", { preview = false, applyAll = false, notify = false })
    A.Workflow.RefreshTooltipPreview()
end


Registry:RegisterSetting({
    key = "general.globalUiScale",
    label = "Global WoW UI Scale",
    category = "Dashboard / Scaling",
    unit = "global",
    frameType = "dashboard",
    attribute = "globalUiScale",
    type = "number",
    min = 0.3,
    max = 1.5,
    step = 0.01,
    percent = true,
    aliases = { "global ui scale", "wow ui scale", "global wow scale", "global scale" },
    get = function()
        local _, ui = A.Workflow.GlobalScaleState()
        return ui.Scale
    end,
    set = function(value)
        A.Workflow.SetGlobalScaleState(true, value, "custom")
    end,
    apply = function() A.Workflow.PushGlobalScale() end,
    combatSafe = false,
})

Registry:RegisterSetting({
    key = "general.globalUiScaleEnabled",
    label = "Global WoW UI Scale Override",
    category = "Dashboard / Scaling",
    unit = "global",
    frameType = "dashboard",
    attribute = "globalUiScaleEnabled",
    type = "boolean",
    aliases = { "global ui scale override", "wow ui scale override", "global scale override" },
    get = function()
        local _, ui = A.Workflow.GlobalScaleState()
        return ui.Enabled == true
    end,
    set = function(value)
        local _, ui = A.Workflow.GlobalScaleState()
        A.Workflow.SetGlobalScaleState(value and true or false, ui.Scale, value and "custom" or "auto")
    end,
    apply = function() A.Workflow.PushGlobalScale() end,
    combatSafe = false,
})

Registry:RegisterSetting({
    key = "general.msufUiScale",
    label = "MSUF Frame Scale",
    category = "Dashboard / Scaling",
    unit = "global",
    frameType = "dashboard",
    attribute = "msufFrameScale",
    type = "number",
    min = 0.25,
    max = 1.5,
    step = 0.01,
    percent = true,
    aliases = { "msuf frame scale", "msuf ui scale", "unit frame scale", "frame scale" },
    get = function() return A.Workflow.ClampScale(GeneralDB().msufUiScale or 1, 0.25, 1.5) or 1 end,
    set = function(value) GeneralDB().msufUiScale = A.Workflow.ClampScale(value, 0.25, 1.5) or 1 end,
    apply = function() A.Workflow.ApplyMsufScale(GeneralDB().msufUiScale or 1) end,
    combatSafe = false,
})

Registry:RegisterSetting({
    key = "general.slashMenuScale",
    label = "MSUF Menu Scale",
    category = "Dashboard / Scaling",
    unit = "global",
    frameType = "dashboard",
    attribute = "menuScale",
    type = "number",
    min = 0.25,
    max = 1.5,
    step = 0.01,
    percent = true,
    aliases = { "msuf menu scale", "menu scale", "configuration menu scale", "dashboard scale" },
    get = function() return A.Workflow.ClampScale(GeneralDB().slashMenuScale or 1, 0.25, 1.5) or 1 end,
    set = function(value) GeneralDB().slashMenuScale = A.Workflow.ClampScale(value, 0.25, 1.5) or 1 end,
    apply = function() A.Workflow.ApplyMenuScale(GeneralDB().slashMenuScale or 1) end,
    combatSafe = false,
})

Registry:RegisterAction({
    key = "apply_global_scale_preset",
    label = "Apply Global UI Scale Preset",
    type = "preset",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        return A.Workflow.ApplyScalePreset(args and args.preset)
    end,
})

Registry:RegisterAction({
    key = "set_global_font_color",
    label = "Set Global Font Color",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local r, g, b = args and args.r, args and args.g, args and args.b
        if type(args and args.color) == "string" then
            local cr, cg, cb = ColorFromName(args.color)
            if cr then r, g, b = cr, cg, cb end
        end
        if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
            return false, "I need a color name, hex value, or RGB value."
        end
        r, g, b = Clamp01(r), Clamp01(g), Clamp01(b)
        local api = MSUF and MSUF._colorsAPI
        if api and type(api.SetGlobalFontColor) == "function" then
            api.SetGlobalFontColor(r, g, b)
        else
            local gen = GeneralDB()
            gen.useCustomFontColor = true
            gen.fontColorCustomR, gen.fontColorCustomG, gen.fontColorCustomB = r, g, b
        end
        ApplyVisuals("MSUF_ASSISTANT_FONT_COLOR_CUSTOM")
        return true, "Done. Global font color set to " .. tostring(args and args.label or args and args.color or "custom") .. "."
    end,
})

Registry:RegisterAction({
    key = "reset_global_font_color",
    label = "Reset Global Font Color",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local api = MSUF and MSUF._colorsAPI
        if api and type(api.ResetGlobalFontToPalette) == "function" then
            api.ResetGlobalFontToPalette()
        else
            local gen = GeneralDB()
            gen.useCustomFontColor = false
            gen.fontColorCustomR, gen.fontColorCustomG, gen.fontColorCustomB = nil, nil, nil
        end
        ApplyVisuals("MSUF_ASSISTANT_FONT_COLOR_RESET")
        return true, "Done. Global font color follows the palette again."
    end,
})

local function RegisterAssistantColorSettings()
ColorSetting("general.customFontColor", "Global Font Color", {
    "custom font color", "main font color", "global custom font color",
}, function()
    return ApiRGB("GetGlobalFontColor", 1, 1, 1, function() return GeneralRGB("fontColorCustom", 1, 1, 1) end)
end, function(r, g, b)
    if not ApiSetRGB("SetGlobalFontColor", r, g, b) then
        local gen = GeneralDB()
        gen.useCustomFontColor = true
        gen.fontColorCustomR, gen.fontColorCustomG, gen.fontColorCustomB = r, g, b
    end
end, { category = "Colors / Global Font", attribute = "customFontColor", apply = ApplyColors })

local COLOR_CLASS_TOKENS = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
    "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}
local COLOR_CLASS_LABELS = {
    WARRIOR = "Warrior",
    PALADIN = "Paladin",
    HUNTER = "Hunter",
    ROGUE = "Rogue",
    PRIEST = "Priest",
    DEATHKNIGHT = "Death Knight",
    SHAMAN = "Shaman",
    MAGE = "Mage",
    WARLOCK = "Warlock",
    MONK = "Monk",
    DRUID = "Druid",
    DEMONHUNTER = "Demon Hunter",
    EVOKER = "Evoker",
}

for i = 1, #COLOR_CLASS_TOKENS do
    local token = COLOR_CLASS_TOKENS[i]
    local label = COLOR_CLASS_LABELS[token] or token
    local lower = label:lower()
    ColorSetting("classColors." .. token, label .. " Class Bar Color", {
        lower .. " class color", lower .. " class bar color", lower .. " bar color", lower .. " color",
    }, function()
        local fn = ColorAPI().GetClassColor
        if type(fn) == "function" then return fn(token) end
        local db = GeneralDB()
        if type(db.classColors) == "table" then
            local color = db.classColors[token]
            if type(color) == "table" then return color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1 end
        end
        local rc = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token]
        if rc then return rc.r, rc.g, rc.b end
        return 1, 1, 1
    end, function(r, g, b)
        local fn = ColorAPI().SetClassColor
        if type(fn) == "function" then
            fn(token, r, g, b)
        else
            local db = GeneralDB()
            db.classColors = type(db.classColors) == "table" and db.classColors or {}
            db.classColors[token] = { r = r, g = g, b = b }
        end
    end, { category = "Colors / Class Bar", attribute = "classColor", apply = ApplyColors })
end

ColorSetting("general.classBarBgColor", "Bar Background Tint", {
    "bar background tint", "bar tint", "class bar background color", "bar background color",
}, function()
    return ApiRGB("GetClassBarBgColor", 0, 0, 0, function() return GeneralRGB("classBarBg", 0, 0, 0) end)
end, function(r, g, b)
    if not ApiSetRGB("SetClassBarBgColor", r, g, b) then SetGeneralRGB("classBarBg", r, g, b) end
end, { category = "Colors / Bar Background", attribute = "barBackgroundTint", defaultR = 0, defaultG = 0, defaultB = 0, apply = ApplyColors })

Registry:RegisterSetting({
    key = "general.barBgMatchHPColor",
    label = "Background Follows HP Color",
    category = "Colors / Bar Background",
    unit = "global",
    frameType = "colors",
    attribute = "barBackgroundFollowsHP",
    type = "boolean",
    aliases = { "background follows hp color", "bar background follows hp", "background matches hp" },
    get = function()
        local fn = ColorAPI().GetBarBgMatchHP
        if type(fn) == "function" then return fn() == true end
        return GeneralDB().barBgMatchHPColor == true
    end,
    set = function(value)
        local fn = ColorAPI().SetBarBgMatchHP
        if type(fn) == "function" then
            fn(value and true or false)
        else
            local g = GeneralDB()
            g.barBgMatchHPColor = value and true or false
            if value then g.barBgClassColor = false end
        end
    end,
    apply = ApplyColors,
    combatSafe = false,
})

Registry:RegisterSetting({
    key = "general.barBgClassColor",
    label = "Health Background Follows Class Color",
    category = "Colors / Bar Background",
    unit = "global",
    frameType = "colors",
    attribute = "barBackgroundFollowsClass",
    type = "boolean",
    aliases = { "health background follows class color", "bar background class color", "background follows class color" },
    get = function()
        local fn = ColorAPI().GetBarBgClassColor
        if type(fn) == "function" then return fn() == true end
        return GeneralDB().barBgClassColor == true
    end,
    set = function(value)
        local fn = ColorAPI().SetBarBgClassColor
        if type(fn) == "function" then
            fn(value and true or false)
        else
            local g = GeneralDB()
            g.barBgClassColor = value and true or false
            if value then g.barBgMatchHPColor = false end
        end
    end,
    apply = ApplyColors,
    combatSafe = false,
})

RegisterGeneralBoolean("darkBgCustomColor", "darkModeCustomBackgroundColor", "Custom Color In Dark Mode", false, {
    "custom color in dark mode", "dark mode custom background color", "dark mode custom color",
}, { category = "Colors / Bar Background", frameType = "colors", apply = ApplyColors, reason = "MSUF_ASSISTANT_DARK_MODE_CUSTOM_COLOR" })

ColorSetting("general.unifiedBarColor", "Unified Bar Color", {
    "unified bar color", "unified color", "all frames color",
}, function()
    return GeneralRGB("unifiedBar", 0.10, 0.60, 0.90)
end, function(r, g, b)
    SetGeneralRGB("unifiedBar", r, g, b)
end, { category = "Colors / Unitframe Global Coloring", attribute = "unifiedBarColor", defaultR = 0.10, defaultG = 0.60, defaultB = 0.90, apply = ApplyColors })

RegisterGeneralNumberSetting("darkBarGray", "darkModeBarColor", "Dark Mode Bar Color", 0.07, 0, 1, {
    "dark mode bar color", "dark bar color", "dark mode brightness", "dark bar brightness",
}, { category = "Colors / Unitframe Global Coloring", frameType = "colors", apply = ApplyColors, reason = "MSUF_ASSISTANT_DARK_BAR_GRAY", step = 0.01, percent = true })

RegisterGeneralBoolean("enableHealthGradient", "healthColorGradient", "Health Color Gradient", true, {
    "health color gradient", "color health by gradient", "unitframe health gradient",
}, { category = "Colors / Unitframe Global Coloring", frameType = "colors", apply = ApplyColors, reason = "MSUF_ASSISTANT_HEALTH_COLOR_GRADIENT" })

local COLOR_NPC_ROWS = {
    { key = "friendly", label = "Friendly NPC Color", dr = 0, dg = 1, db = 0, aliases = { "friendly npc color", "friendly reaction color" } },
    { key = "neutral", label = "Neutral NPC Color", dr = 1, dg = 1, db = 0, aliases = { "neutral npc color", "neutral reaction color" } },
    { key = "enemy", label = "Enemy NPC Color", dr = 0.85, dg = 0.10, db = 0.10, aliases = { "enemy npc color", "hostile npc color", "enemy reaction color" } },
    { key = "dead", label = "Dead NPC Color", dr = 0.40, dg = 0.40, db = 0.40, aliases = { "dead npc color", "dead unit color" } },
}

for i = 1, #COLOR_NPC_ROWS do
    local row = COLOR_NPC_ROWS[i]
    ColorSetting("npcColors." .. row.key, row.label, row.aliases, function()
        local fn = ColorAPI().GetNPCColor
        if type(fn) == "function" then return fn(row.key) end
        return TableRGB(GeneralDB().npcColors, row.key, row.dr, row.dg, row.db)
    end, function(r, g, b)
        local fn = ColorAPI().SetNPCColor
        if type(fn) == "function" then
            fn(row.key, r, g, b)
        else
            local db = GeneralDB()
            db.npcColors = type(db.npcColors) == "table" and db.npcColors or {}
            db.npcColors[row.key] = { r = r, g = g, b = b }
        end
    end, { category = "Colors / Unitframe Colors", attribute = "npcColor", defaultR = row.dr, defaultG = row.dg, defaultB = row.db, apply = ApplyColors })
end

ColorSetting("general.petFrameColor", "Pet Frame Color", {
    "pet frame color", "pet color", "pet bar color",
}, function()
    return ApiRGB("GetPetFrameColor", 0, 0.8, 0, function() return GeneralRGB("petFrameColor", 0, 0.8, 0) end)
end, function(r, g, b)
    if not ApiSetRGB("SetPetFrameColor", r, g, b) then SetGeneralRGB("petFrameColor", r, g, b) end
end, { category = "Colors / Unitframe Colors", attribute = "petColor", defaultR = 0, defaultG = 0.8, defaultB = 0, apply = ApplyColors })

Registry:RegisterSetting({
    key = "general.npcColorMode",
    label = "NPC Type Colors",
    category = "Colors / NPC Type",
    unit = "global",
    frameType = "colors",
    attribute = "npcTypeColors",
    type = "boolean",
    aliases = { "npc type colors", "npc type coloring", "npc role colors" },
    get = function()
        local fn = ColorAPI().GetNPCColorMode
        if type(fn) == "function" then return fn() == "type" end
        return GeneralDB().npcColorMode == "type"
    end,
    set = function(value)
        local mode = value and "type" or "reaction"
        local fn = ColorAPI().SetNPCColorMode
        if type(fn) == "function" then fn(mode) else GeneralDB().npcColorMode = mode end
    end,
    apply = ApplyColors,
    combatSafe = false,
})
RegisterGeneralBoolean("npcTypeColorBar", "npcTypeColorHPBar", "NPC Type Color HP Bar", true, {
    "npc type color hp bar", "npc type color health bar", "npc role color hp",
}, { category = "Colors / NPC Type", frameType = "colors", apply = ApplyColors, reason = "MSUF_ASSISTANT_NPC_TYPE_HP_COLOR" })
RegisterGeneralBoolean("npcTypeColorText", "npcTypeColorNameText", "NPC Type Color Name Text", true, {
    "npc type color name text", "npc type color names", "npc role color names",
}, { category = "Colors / NPC Type", frameType = "colors", apply = ApplyColors, reason = "MSUF_ASSISTANT_NPC_TYPE_TEXT_COLOR" })
for _, item in ipairs({
    { key = "npcTypeTarget", label = "NPC Type Color Target", aliases = { "npc type colors target", "target npc type colors" } },
    { key = "npcTypeFocus", label = "NPC Type Color Focus", aliases = { "npc type colors focus", "focus npc type colors" } },
    { key = "npcTypeBoss", label = "NPC Type Color Boss", aliases = { "npc type colors boss", "boss npc type colors" } },
    { key = "npcTypeToT", label = "NPC Type Color Target of Target", aliases = { "npc type colors targettarget", "targettarget npc type colors", "tot npc type colors" } },
}) do
    RegisterGeneralBoolean(item.key, item.key, item.label, true, item.aliases, {
        category = "Colors / NPC Type",
        frameType = "colors",
        apply = ApplyColors,
        reason = "MSUF_ASSISTANT_" .. item.key,
    })
end

local COLOR_NPC_TYPE_ROWS = {
    { key = "npcBoss", label = "Boss NPC Type Color", dr = 0.74, dg = 0.11, db = 0, aliases = { "boss npc type color", "npc boss color", "boss type color" } },
    { key = "npcMiniboss", label = "Miniboss NPC Type Color", dr = 0.56, dg = 0, db = 0.74, aliases = { "miniboss npc type color", "lieutenant npc color", "npc miniboss color" } },
    { key = "npcCaster", label = "Caster NPC Type Color", dr = 0, dg = 0.45, db = 0.74, aliases = { "caster npc type color", "npc caster color", "caster type color" } },
    { key = "npcMelee", label = "Melee NPC Type Color", dr = 0.99, dg = 0.99, db = 0.99, aliases = { "melee npc type color", "npc melee color", "melee type color" } },
    { key = "npcRegular", label = "Regular NPC Type Color", dr = 0.70, dg = 0.56, db = 0.33, aliases = { "regular npc type color", "npc regular color", "regular type color" } },
}
for i = 1, #COLOR_NPC_TYPE_ROWS do
    local row = COLOR_NPC_TYPE_ROWS[i]
    ColorSetting("npcColors." .. row.key, row.label, row.aliases, function()
        local fn = ColorAPI().GetNPCColor
        if type(fn) == "function" then return fn(row.key) end
        return TableRGB(GeneralDB().npcColors, row.key, row.dr, row.dg, row.db)
    end, function(r, g, b)
        local fn = ColorAPI().SetNPCColor
        if type(fn) == "function" then
            fn(row.key, r, g, b)
        else
            local db = GeneralDB()
            db.npcColors = type(db.npcColors) == "table" and db.npcColors or {}
            db.npcColors[row.key] = { r = r, g = g, b = b }
        end
    end, { category = "Colors / NPC Type", attribute = "npcTypeColor", defaultR = row.dr, defaultG = row.dg, defaultB = row.db, apply = ApplyColors })
end

ColorSetting("general.absorbBarColor", "Absorb Bar Color", {
    "absorb bar color", "absorb color", "absorb overlay color",
}, function()
    return ApiRGB("GetAbsorbOverlayColor", 1, 1, 1, function() return GeneralRGB("absorbBarColor", 1, 1, 1) end)
end, function(r, g, b)
    if not ApiSetRGB("SetAbsorbOverlayColor", r, g, b, 0.45) then SetGeneralRGB("absorbBarColor", r, g, b) end
end, { category = "Colors / Bar Colors", attribute = "absorbColor", apply = ApplyColors })
ColorSetting("general.healAbsorbBarColor", "Heal-Absorb Bar Color", {
    "heal absorb bar color", "heal absorb color", "heal-absorb color",
}, function()
    return ApiRGB("GetHealAbsorbOverlayColor", 0.7, 0, 0, function() return GeneralRGB("healAbsorbBarColor", 0.7, 0, 0) end)
end, function(r, g, b)
    if not ApiSetRGB("SetHealAbsorbOverlayColor", r, g, b, 0.45) then SetGeneralRGB("healAbsorbBarColor", r, g, b) end
end, { category = "Colors / Bar Colors", attribute = "healAbsorbColor", defaultR = 0.7, apply = ApplyColors })
ColorSetting("general.powerBarBgColor", "Power Bar Background Color", {
    "power bar background color", "power background color", "mana bar background color",
}, function()
    return ApiRGB("GetPowerBarBackgroundColor", 0, 0, 0, function() return GeneralRGB("powerBarBgColor", 0, 0, 0) end)
end, function(r, g, b)
    if not ApiSetRGB("SetPowerBarBackgroundColor", r, g, b) then SetGeneralRGB("powerBarBgColor", r, g, b) end
end, { category = "Colors / Bar Colors", attribute = "powerBackgroundColor", defaultR = 0, defaultG = 0, defaultB = 0, apply = ApplyColors })
ColorSetting("general.aggroBorderColor", "Aggro Border Color", {
    "aggro border color", "threat border color", "aggro outline color",
}, function()
    return ApiRGB("GetAggroBorderColor", 1, 0.5, 0, function() return GeneralRGBAlias("hlAggroColor", "aggroBorderColor", 1, 0.5, 0) end)
end, function(r, g, b)
    if not ApiSetRGB("SetAggroBorderColor", r, g, b) then SetGeneralRGBAlias("hlAggroColor", "aggroBorderColor", r, g, b) end
end, { category = "Colors / Bar Colors", attribute = "aggroBorderColor", defaultR = 1, defaultG = 0.5, defaultB = 0, apply = ApplyColors })
ColorSetting("general.purgeBorderColor", "Purge Border Color", {
    "purge border color", "purgeable border color", "purge outline color",
}, function()
    return GeneralRGBAlias("hlPurgeColor", "purgeBorderColor", 1, 0.85, 0)
end, function(r, g, b)
    SetGeneralRGBAlias("hlPurgeColor", "purgeBorderColor", r, g, b)
end, { category = "Colors / Bar Colors", attribute = "purgeBorderColor", defaultR = 1, defaultG = 0.85, defaultB = 0, apply = ApplyColors })
ColorSetting("general.barOutlineColor", "Bar Outline Color", {
    "bar outline color", "frame outline color", "bar border color", "bars border color", "border outline color", "outline border color",
}, function()
    return ApiRGB("GetBarOutlineColor", 0, 0, 0, function() return GeneralRGB("barOutlineColor", 0, 0, 0) end)
end, function(r, g, b)
    local gdb = GeneralDB()
    gdb.barOutlineColorMode = nil
    gdb.barOutlineColorA = 1
    if not ApiSetRGB("SetBarOutlineColor", r, g, b) then SetGeneralRGB("barOutlineColor", r, g, b) end
end, { category = "Colors / Bar Colors", attribute = "barOutlineColor", defaultR = 0, defaultG = 0, defaultB = 0, apply = ApplyColors })
for _, scope in ipairs(GLOBAL_SCOPE_ORDER) do
    Registry:RegisterSetting({
        key = "barScope." .. NormalizeGlobalScope(scope) .. ".barOutlineColor",
        label = GlobalScopeLabel(scope) .. " Bar Outline Color",
        category = "Global / Bars / Scoped",
        unit = NormalizeGlobalScope(scope),
        frameType = "globalBars",
        attribute = "barOutlineColor",
        type = "color",
        aliases = GlobalScopeAliases(scope, { "bar outline color", "frame outline color", "bar border color", "bars border color", "border outline color", "outline border color", "border color", "outline color" }),
        get = function()
            return {
                r = Clamp01(GlobalScopeRead(scope, "hlOverride", GeneralDB(), "barOutlineColorR", 0)),
                g = Clamp01(GlobalScopeRead(scope, "hlOverride", GeneralDB(), "barOutlineColorG", 0)),
                b = Clamp01(GlobalScopeRead(scope, "hlOverride", GeneralDB(), "barOutlineColorB", 0)),
            }
        end,
        set = function(value)
            local r, g, b = ColorComponents(value, 0, 0, 0)
            GlobalScopeWrite(scope, "hlOverride", GeneralDB(), "barOutlineColorR", r)
            GlobalScopeWrite(scope, "hlOverride", GeneralDB(), "barOutlineColorG", g)
            GlobalScopeWrite(scope, "hlOverride", GeneralDB(), "barOutlineColorB", b)
        end,
        sameValue = ColorSame,
        apply = function() ApplyBarOutline("MSUF_ASSISTANT_SCOPED_BAR_OUTLINE_COLOR") end,
        combatSafe = false,
    })
end
RegisterGeneralBoolean("powerBarBgMatchBarColor", "powerBackgroundMatchesHP", "Power Background Matches HP", false, {
    "power background matches hp", "power bar background matches hp", "power background follows hp",
}, { category = "Colors / Bar Colors", frameType = "colors", apply = ApplyColors, reason = "MSUF_ASSISTANT_POWER_BG_MATCH_HP" })

RegisterGeneralEnum("hlDispelColorMode", "dispelColorMode", "Dispel Color Mode", "SINGLE", { "SINGLE", "TYPE" }, {
    "dispel color mode", "dispel colors mode", "debuff type color mode",
}, {
    category = "Colors / Dispel",
    frameType = "colors",
    apply = ApplyColors,
    reason = "MSUF_ASSISTANT_DISPEL_COLOR_MODE",
    valueAliases = { single = "SINGLE", one = "SINGLE", type = "TYPE", types = "TYPE", pertype = "TYPE", debufftype = "TYPE" },
})
ColorSetting("general.hlDispelColor", "Dispel Color", {
    "dispel color", "dispel border color", "all dispel color", "single dispel color",
}, function()
    return GeneralRGBAlias("hlDispelColor", "dispelBorderColor", 0.25, 0.75, 1)
end, function(r, g, b)
    SetGeneralRGBAlias("hlDispelColor", "dispelBorderColor", r, g, b)
end, { category = "Colors / Dispel", attribute = "dispelColor", defaultR = 0.25, defaultG = 0.75, defaultB = 1, apply = ApplyColors })

for _, row in ipairs({
    { key = "Magic", label = "Magic Dispel Color", dr = 0.20, dg = 0.60, db = 1.00, aliases = { "magic dispel color", "magic debuff color" } },
    { key = "Curse", label = "Curse Dispel Color", dr = 0.60, dg = 0.00, db = 1.00, aliases = { "curse dispel color", "curse debuff color" } },
    { key = "Disease", label = "Disease Dispel Color", dr = 0.60, dg = 0.40, db = 0.00, aliases = { "disease dispel color", "disease debuff color" } },
    { key = "Poison", label = "Poison Dispel Color", dr = 0.00, dg = 0.60, db = 0.00, aliases = { "poison dispel color", "poison debuff color" } },
    { key = "Bleed", label = "Bleed Dispel Color", dr = 0.80, dg = 0.10, db = 0.10, aliases = { "bleed dispel color", "bleed debuff color" } },
}) do
    ColorSetting("general.dispelType" .. row.key, row.label, row.aliases, function()
        return GeneralRGB("dispelType" .. row.key, row.dr, row.dg, row.db)
    end, function(r, g, b)
        SetGeneralRGB("dispelType" .. row.key, r, g, b)
    end, { category = "Colors / Dispel", attribute = "dispelTypeColor", defaultR = row.dr, defaultG = row.dg, defaultB = row.db, apply = ApplyColors })
end

for _, row in ipairs({
    { key = "castbarInterruptible", label = "Interruptible Cast Color", get = "GetInterruptibleCastColor", set = "SetInterruptibleCastColor", dr = 0, dg = 0.9, db = 0.8, aliases = { "interruptible cast color", "interruptible castbar color", "castbar interruptible color", "interrupt castbar color", "castbar interrupt color", "kickable cast color", "kickable castbar color" } },
    { key = "castbarNonInterruptible", label = "Non-Interruptible Cast Color", get = "GetNonInterruptibleCastColor", set = "SetNonInterruptibleCastColor", dr = 0.4, dg = 0.01, db = 0.01, aliases = { "non interruptible cast color", "non interruptible castbar color", "noninterruptible cast color", "noninterruptible castbar color", "not interruptible castbar color", "uninterruptible cast color", "uninterruptible castbar color", "unkickable cast color", "unkickable castbar color", "not kickable castbar color" } },
    { key = "castbarInterruptFeedback", label = "Interrupt Feedback Cast Color", get = "GetInterruptFeedbackCastColor", set = "SetInterruptFeedbackCastColor", dr = 1, dg = 0.82, db = 0, aliases = { "interrupt feedback color", "castbar interrupt feedback color", "interrupt color all castbars", "interrupt color for all castbars", "interrupted cast color", "interrupted castbar color", "after interrupt cast color" } },
    { key = "castbarFont", label = "Castbar Text Color", get = "GetCastbarTextColor", set = "SetCastbarTextColor", dr = 1, dg = 1, db = 1, aliases = { "castbar text color", "castbar font color", "cast bar text color", "castbar spell name color", "castbar spell name text color", "castbar spell color", "castbar spell text color", "spell name color", "spell text color" } },
}) do
    ColorSetting("general." .. row.key .. "Color", row.label, row.aliases, function()
        return ApiRGB(row.get, row.dr, row.dg, row.db, function() return GeneralRGB(row.key, row.dr, row.dg, row.db) end)
    end, function(r, g, b)
        local fallbackPrefix = row.key
        if row.key == "castbarFont" then fallbackPrefix = "castbarFont" end
        if not ApiSetRGB(row.set, r, g, b) then SetGeneralRGB(fallbackPrefix, r, g, b) end
    end, { category = "Colors / Castbar", attribute = row.key .. "Color", defaultR = row.dr, defaultG = row.dg, defaultB = row.db, apply = ApplyCastbarColors })
end

ColorSetting("general.castbarBorderColor", "Castbar Border Color", {
    "castbar border color", "cast bar border color", "castbar outline color",
}, function()
    return ApiRGB("GetCastbarBorderColor", 0, 0, 0, function() return GeneralRGB("castbarBorder", 0, 0, 0) end)
end, function(r, g, b)
    if not ApiSetRGB("SetCastbarBorderColor", r, g, b, 1) then SetGeneralRGB("castbarBorder", r, g, b) end
end, { category = "Colors / Castbar", attribute = "castbarBorderColor", defaultR = 0, defaultG = 0, defaultB = 0, apply = ApplyCastbarColors })

ColorSetting("general.castbarBackgroundColor", "Castbar Background Color", {
    "castbar background color", "cast bar background color", "castbar bg color",
}, function()
    return ApiRGB("GetCastbarBackgroundColor", 0.10, 0.10, 0.10, function() return GeneralRGB("castbarBg", 0.10, 0.10, 0.10) end)
end, function(r, g, b)
    if not ApiSetRGB("SetCastbarBackgroundColor", r, g, b, 0.85) then SetGeneralRGB("castbarBg", r, g, b) end
end, { category = "Colors / Castbar", attribute = "castbarBackgroundColor", defaultR = 0.10, defaultG = 0.10, defaultB = 0.10, apply = ApplyCastbarColors })

RegisterGeneralBoolean("playerCastbarOverrideEnabled", "playerCastbarOverride", "Player Castbar Color Override", true, {
    "player castbar color override", "player castbar override", "player cast color override",
}, { category = "Colors / Castbar", frameType = "colors", apply = ApplyCastbarColors, reason = "MSUF_ASSISTANT_PLAYER_CASTBAR_OVERRIDE" })
RegisterGeneralEnum("playerCastbarOverrideMode", "playerCastbarOverrideMode", "Player Castbar Override Mode", "CLASS", { "CLASS", "CUSTOM" }, {
    "player castbar override mode", "player castbar color mode",
}, {
    category = "Colors / Castbar",
    frameType = "colors",
    apply = ApplyCastbarColors,
    reason = "MSUF_ASSISTANT_PLAYER_CASTBAR_OVERRIDE_MODE",
    valueAliases = { class = "CLASS", classcolor = "CLASS", custom = "CUSTOM", color = "CUSTOM", manual = "CUSTOM" },
})
ColorSetting("general.playerCastbarOverrideColor", "Player Castbar Override Color", {
    "player castbar override color", "player castbar custom color", "player cast custom color",
}, function()
    return ApiRGB("GetPlayerCastbarOverrideColor", 0, 0.6, 1, function() return GeneralRGB("playerCastbarOverride", 0, 0.6, 1) end)
end, function(r, g, b)
    if not ApiSetRGB("SetPlayerCastbarOverrideColor", r, g, b) then SetGeneralRGB("playerCastbarOverride", r, g, b) end
end, { category = "Colors / Castbar", attribute = "playerCastbarOverrideColor", defaultR = 0, defaultG = 0.6, defaultB = 1, apply = ApplyCastbarColors })

ColorSetting("general.kickReadyColor", "Kick Ready Color", {
    "kick ready color", "interrupt ready color", "ready kick color",
}, function()
    return TableRGB(GeneralDB(), "kickReadyColor", 0, 1, 0)
end, function(r, g, b)
    SetTableRGB(GeneralDB(), "kickReadyColor", r, g, b)
end, { category = "Colors / Castbar", attribute = "kickReadyColor", defaultR = 0, defaultG = 1, defaultB = 0, apply = ApplyCastbarColors })
ColorSetting("general.kickNotReadyColor", "Kick Not Ready Color", {
    "kick not ready color", "interrupt not ready color", "kick cooldown color",
}, function()
    return TableRGB(GeneralDB(), "kickNotReadyColor", 1, 0, 0)
end, function(r, g, b)
    SetTableRGB(GeneralDB(), "kickNotReadyColor", r, g, b)
end, { category = "Colors / Castbar", attribute = "kickNotReadyColor", defaultR = 1, defaultG = 0, defaultB = 0, apply = ApplyCastbarColors })

RegisterGeneralBoolean("highlightEnabled", "mouseoverHighlight", "Mouseover Highlight", true, {
    "mouseover highlight", "hover highlight", "unitframe mouseover highlight",
}, { category = "Colors / Mouseover Highlight", frameType = "colors", apply = ApplyColors, reason = "MSUF_ASSISTANT_MOUSEOVER_HIGHLIGHT" })
ColorSetting("general.highlightColor", "Mouseover Highlight Color", {
    "mouseover highlight color", "hover highlight color", "unitframe highlight color",
}, function()
    local color = GeneralDB().highlightColor
    if type(color) == "table" then return TableRGB(GeneralDB(), "highlightColor", 1, 1, 1) end
    local r, g, b = ColorFromName(color or "white")
    return r or 1, g or 1, b or 1
end, function(r, g, b)
    GeneralDB().highlightColor = { r, g, b }
end, { category = "Colors / Mouseover Highlight", attribute = "mouseoverHighlightColor", apply = ApplyColors })
ColorSetting("general.bossTargetHighlightColor", "Boss Target Highlight Color", {
    "boss target highlight color", "boss target color", "boss target border highlight color",
}, function()
    return TableRGB(GeneralDB(), "bossTargetHighlightColor", 1, 0.82, 0)
end, function(r, g, b)
    SetTableRGB(GeneralDB(), "bossTargetHighlightColor", r, g, b)
end, { category = "Colors / Mouseover Highlight", attribute = "bossTargetHighlightColor", defaultR = 1, defaultG = 0.82, defaultB = 0, apply = ApplyColors })

ColorSetting("gameplay.combatTimerColor", "Combat Timer Text Color", {
    "combat timer text color", "combat timer color",
}, function()
    return TableRGB(GameplayDB(), "combatTimerColor", 1, 1, 1)
end, function(r, g, b)
    SetTableRGB(GameplayDB(), "combatTimerColor", r, g, b)
end, { category = "Colors / Gameplay", frameType = "gameplay", attribute = "combatTimerColor", apply = ApplyGameplayColors })
ColorSetting("gameplay.combatStateEnterColor", "Combat Enter Text Color", {
    "combat enter text color", "combat enter color", "combat state enter color",
}, function()
    return TableRGB(GameplayDB(), "combatStateEnterColor", 1, 1, 1)
end, function(r, g, b)
    local gp = GameplayDB()
    SetTableRGB(gp, "combatStateEnterColor", r, g, b)
    if gp.combatStateColorSync then SetTableRGB(gp, "combatStateLeaveColor", r, g, b) end
end, { category = "Colors / Gameplay", frameType = "gameplay", attribute = "combatStateEnterColor", apply = ApplyGameplayColors })
ColorSetting("gameplay.combatStateLeaveColor", "Combat Leave Text Color", {
    "combat leave text color", "combat leave color", "combat state leave color",
}, function()
    return TableRGB(GameplayDB(), "combatStateLeaveColor", 0.7, 0.7, 0.7)
end, function(r, g, b)
    SetTableRGB(GameplayDB(), "combatStateLeaveColor", r, g, b)
end, { category = "Colors / Gameplay", frameType = "gameplay", attribute = "combatStateLeaveColor", defaultR = 0.7, defaultG = 0.7, defaultB = 0.7, apply = ApplyGameplayColors })
RegisterGameplayBoolean("combatStateColorSync", "combatStateColorSync", "Sync Combat State Colors", false, {
    "sync combat state colors", "sync combat enter leave colors", "same combat state colors",
}, { category = "Colors / Gameplay", frameType = "gameplay", apply = ApplyGameplayColors, reason = "MSUF_ASSISTANT_COMBAT_STATE_COLOR_SYNC" })
ColorSetting("gameplay.crosshairInRangeColor", "Crosshair In-Range Color", {
    "crosshair in range color", "combat crosshair in range color", "melee range in color",
}, function()
    return TableRGB(GameplayDB(), "crosshairInRangeColor", 0, 1, 0)
end, function(r, g, b)
    SetTableRGB(GameplayDB(), "crosshairInRangeColor", r, g, b)
end, { category = "Colors / Gameplay", frameType = "gameplay", attribute = "crosshairInRangeColor", defaultR = 0, defaultG = 1, defaultB = 0, apply = ApplyGameplayColors })
ColorSetting("gameplay.crosshairOutRangeColor", "Crosshair Out-of-Range Color", {
    "crosshair out of range color", "crosshair out-of-range color", "combat crosshair out range color", "melee range out color",
}, function()
    return TableRGB(GameplayDB(), "crosshairOutRangeColor", 1, 0, 0)
end, function(r, g, b)
    SetTableRGB(GameplayDB(), "crosshairOutRangeColor", r, g, b)
end, { category = "Colors / Gameplay", frameType = "gameplay", attribute = "crosshairOutRangeColor", defaultR = 1, defaultG = 0, defaultB = 0, apply = ApplyGameplayColors })

local COLOR_POWER_TOKENS = {
    { key = "MANA", label = "Mana" },
    { key = "RAGE", label = "Rage" },
    { key = "ENERGY", label = "Energy" },
    { key = "FOCUS", label = "Focus" },
    { key = "RUNIC_POWER", label = "Runic Power" },
    { key = "INSANITY", label = "Insanity" },
    { key = "FURY", label = "Fury" },
    { key = "PAIN", label = "Pain" },
    { key = "ESSENCE", label = "Essence" },
    { key = "LUNAR_POWER", label = "Astral Power" },
    { key = "MAELSTROM", label = "Maelstrom" },
}
A.PowerColorTokens = COLOR_POWER_TOKENS
for i = 1, #COLOR_POWER_TOKENS do
    local token = COLOR_POWER_TOKENS[i].key
    local label = COLOR_POWER_TOKENS[i].label
    local lower = label:lower()
    local aliases = { lower .. " power color", lower .. " bar color", lower .. " resource color" }
    if token ~= "FOCUS" then aliases[#aliases + 1] = lower .. " color" end
    ColorSetting("general.powerColorOverrides." .. token, label .. " Power Bar Color", aliases, function()
        return PowerOverrideRGB(token)
    end, function(r, g, b)
        SetPowerOverrideRGB(token, r, g, b)
    end, { category = "Colors / Power", attribute = "powerColor", apply = ApplyColors })
end

local function KnownPowerColorToken(token)
    token = tostring(token or ""):upper():gsub("%s+", "_")
    for i = 1, #COLOR_POWER_TOKENS do
        local row = COLOR_POWER_TOKENS[i]
        if row.key == token then return row.key, row.label end
    end
    return nil, nil
end

Registry:RegisterAction({
    key = "reset_power_color_token",
    label = "Reset Power Bar Token Color",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local token, label = KnownPowerColorToken(args and args.token)
        if not token then return false, "I need a known power color token." end
        EnsurePowerOverrides()[token] = nil
        ApplyColors("MSUF_ASSISTANT_RESET_POWER_COLOR_TOKEN")
        return true, "Done. Reset " .. tostring(label) .. " power bar color."
    end,
})

local COLOR_CP_TOKENS = {
    { key = "COMBO_POINTS", label = "Combo Points" },
    { key = "HOLY_POWER", label = "Holy Power" },
    { key = "SOUL_SHARDS", label = "Soul Shards" },
    { key = "CHI", label = "Chi" },
    { key = "ARCANE_CHARGES", label = "Arcane Charges" },
    { key = "RUNES", label = "Runes" },
    { key = "ESSENCE", label = "Essence" },
    { key = "CHARGED", label = "Empowered / Charged" },
    { key = "SOUL_FRAGMENTS", label = "Soul Fragments" },
    { key = "SOUL_FRAGMENTS_META", label = "Soul Fragments Void Meta" },
    { key = "MAELSTROM", label = "Maelstrom Weapon" },
    { key = "MAELSTROM_ABOVE_5", label = "Maelstrom Weapon 5+" },
    { key = "ASTRAL_POWER", label = "Astral Power" },
    { key = "AP_PREDICTION", label = "Astral Prediction" },
    { key = "ECLIPSE_SOLAR", label = "Eclipse Solar" },
    { key = "ECLIPSE_LUNAR", label = "Eclipse Lunar" },
    { key = "ECLIPSE_CA", label = "Celestial Alignment" },
    { key = "STAGGER_GREEN", label = "Stagger Light" },
    { key = "STAGGER_YELLOW", label = "Stagger Moderate" },
    { key = "STAGGER_RED", label = "Stagger Heavy" },
    { key = "SOUL_FRAGMENTS_VENG", label = "Soul Fragments Vengeance" },
    { key = "INSANITY", label = "Insanity" },
    { key = "MAELSTROM_POWER", label = "Maelstrom Power" },
    { key = "WHIRLWIND", label = "Whirlwind" },
    { key = "TIP_OF_THE_SPEAR", label = "Tip of the Spear" },
    { key = "ICICLES", label = "Icicles" },
    { key = "EBON_MIGHT", label = "Ebon Might" },
    { key = "RESOURCE_TEXT", label = "Resource Text" },
}
A.ClassPowerColorTokens = COLOR_CP_TOKENS
for i = 1, #COLOR_CP_TOKENS do
    local token = COLOR_CP_TOKENS[i].key
    local label = COLOR_CP_TOKENS[i].label
    local lower = label:lower()
    ColorSetting("general.classPowerColorOverrides." .. token, label .. " Color", {
        lower .. " color", lower .. " class power color", lower .. " class resource color", lower .. " resource color",
    }, function()
        return ClassPowerRGB(token)
    end, function(r, g, b)
        SetClassPowerRGB(token, r, g, b)
    end, { category = "Colors / Class Power", attribute = "classPowerColor", apply = ApplyClassPowerColors })
    ColorSetting("general.classPowerBgColorOverrides." .. token, label .. " Background Color", {
        lower .. " background color", lower .. " class power background color", lower .. " resource background color",
    }, function()
        return ClassPowerBgRGB(token)
    end, function(r, g, b)
        SetClassPowerBgRGB(token, r, g, b)
    end, { category = "Colors / Class Power", attribute = "classPowerBackgroundColor", defaultR = 0, defaultG = 0, defaultB = 0, apply = ApplyClassPowerColors })
end
for i = 1, 7 do
    local token = "COMBO_POINTS_" .. tostring(i)
    ColorSetting("general.classPowerColorOverrides." .. token, "Combo Point " .. tostring(i) .. " Color", {
        "combo point " .. tostring(i), "combo point " .. tostring(i) .. " color",
        "combo point slot " .. tostring(i), "combo point slot " .. tostring(i) .. " color",
        "cp " .. tostring(i), "cp " .. tostring(i) .. " color",
    }, function()
        return ClassPowerRGB(token)
    end, function(r, g, b)
        BarsDB().classPowerComboPointColorMode = "custom"
        SetClassPowerRGB(token, r, g, b)
    end, { category = "Colors / Class Power", attribute = "comboPointSlotColor", apply = ApplyClassPowerColors })
end

local function KnownClassPowerColorToken(token)
    token = tostring(token or "")
    for i = 1, #COLOR_CP_TOKENS do
        if COLOR_CP_TOKENS[i].key == token then return token, COLOR_CP_TOKENS[i].label end
    end
    for i = 1, 7 do
        local slot = "COMBO_POINTS_" .. tostring(i)
        if token == slot then return token, "Combo Point " .. tostring(i) end
    end
    return nil, nil
end

Registry:RegisterAction({
    key = "reset_class_power_color_token",
    label = "Reset Class Resource Token Color",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local token, label = KnownClassPowerColorToken(args and args.token)
        if not token then return false, "I need a known Class Resource color token." end
        local g = EnsureClassPowerOverrides()
        if args and args.background then
            g.classPowerBgColorOverrides[token] = nil
            ApplyClassPowerColors("MSUF_ASSISTANT_RESET_CLASS_POWER_BG_COLOR")
            return true, "Done. Reset " .. tostring(label) .. " background color."
        end
        g.classPowerColorOverrides[token] = nil
        ApplyClassPowerColors("MSUF_ASSISTANT_RESET_CLASS_POWER_COLOR")
        return true, "Done. Reset " .. tostring(label) .. " color."
    end,
})

Registry:RegisterAction({
    key = "reset_class_power_combo_slot_colors",
    label = "Reset Combo Point Slot Colors",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local g = EnsureClassPowerOverrides()
        for i = 1, 7 do g.classPowerColorOverrides["COMBO_POINTS_" .. tostring(i)] = nil end
        ApplyClassPowerColors("MSUF_ASSISTANT_RESET_COMBO_POINT_SLOT_COLORS")
        return true, "Done. Reset combo point slot colors."
    end,
})

ColorSetting("general.aurasOwnBuffHighlightColor", "Own Buff Highlight Color", {
    "own buff highlight color", "my buff highlight color", "aura own buff color",
}, function()
    return TableRGB(GeneralDB(), "aurasOwnBuffHighlightColor", 1, 0.85, 0.2)
end, function(r, g, b)
    SetTableRGB(GeneralDB(), "aurasOwnBuffHighlightColor", r, g, b)
end, { category = "Colors / Auras", attribute = "ownBuffHighlightColor", defaultR = 1, defaultG = 0.85, defaultB = 0.2, apply = ApplyAuraColors })
ColorSetting("general.aurasOwnDebuffHighlightColor", "Own Debuff Highlight Color", {
    "own debuff highlight color", "my debuff highlight color", "aura own debuff color",
}, function()
    return TableRGB(GeneralDB(), "aurasOwnDebuffHighlightColor", 1, 0.85, 0.2)
end, function(r, g, b)
    SetTableRGB(GeneralDB(), "aurasOwnDebuffHighlightColor", r, g, b)
end, { category = "Colors / Auras", attribute = "ownDebuffHighlightColor", defaultR = 1, defaultG = 0.85, defaultB = 0.2, apply = ApplyAuraColors })
ColorSetting("general.aurasStackCountColor", "Aura Stack Count Text Color", {
    "stack count text color", "aura stack color", "aura stack count color",
}, function()
    return TableRGB(GeneralDB(), "aurasStackCountColor", 1, 1, 1)
end, function(r, g, b)
    SetTableRGB(GeneralDB(), "aurasStackCountColor", r, g, b)
end, { category = "Colors / Auras", attribute = "auraStackColor", apply = ApplyAuraColors })
ColorSetting("auras3.shared.pandemicColor", "Pandemic Window Color", {
    "pandemic window color", "pandemic color", "aura pandemic color",
}, function()
    local sh = AuraSharedDB()
    return tonumber(sh.pandemicR) or 0, tonumber(sh.pandemicG) or 0.4, tonumber(sh.pandemicB) or 1
end, function(r, g, b)
    local sh = AuraSharedDB()
    sh.pandemicR, sh.pandemicG, sh.pandemicB = r, g, b
end, { category = "Colors / Auras", attribute = "pandemicColor", defaultR = 0, defaultG = 0.4, defaultB = 1, apply = ApplyAuraColors })
RegisterGeneralBoolean("aurasCooldownTextUseBuckets", "auraCooldownBuckets", "Color Aura Timers By Remaining Time", true, {
    "color aura timers by remaining time", "aura timer bucket colors", "aura cooldown bucket colors",
}, { category = "Colors / Auras", frameType = "colors", apply = ApplyAuraColors, reason = "MSUF_ASSISTANT_AURA_TIMER_BUCKETS" })
for _, row in ipairs({
    { key = "aurasCooldownTextSafeColor", label = "Aura Cooldown Safe Text Color", dr = 1, dg = 1, db = 1, aliases = { "aura cooldown safe color", "cooldown text safe color", "aura timer safe color" } },
    { key = "aurasCooldownTextWarningColor", label = "Aura Cooldown Warning Text Color", dr = 1, dg = 0.85, db = 0.2, aliases = { "aura cooldown warning color", "cooldown text warning color", "aura timer warning color" } },
    { key = "aurasCooldownTextUrgentColor", label = "Aura Cooldown Urgent Text Color", dr = 1, dg = 0.55, db = 0.1, aliases = { "aura cooldown urgent color", "cooldown text urgent color", "aura timer urgent color" } },
}) do
    ColorSetting("general." .. row.key, row.label, row.aliases, function()
        return TableRGB(GeneralDB(), row.key, row.dr, row.dg, row.db)
    end, function(r, g, b)
        SetTableRGB(GeneralDB(), row.key, r, g, b)
    end, { category = "Colors / Auras", attribute = row.key, defaultR = row.dr, defaultG = row.dg, defaultB = row.db, apply = ApplyAuraColors })
end

ColorSetting("general.portraitBorderColor", "Portrait Border Color", {
    "portrait border color", "portrait custom border color",
}, function()
    return GeneralRGB("portraitBorderColor", 1, 1, 1)
end, function(r, g, b)
    SetAllPortraitRGB("portraitBorderColor", r, g, b)
end, { category = "Colors / Portrait", attribute = "portraitBorderColor", apply = ApplyPortraitColors })
ColorSetting("general.portraitBgColor", "Portrait Background Color", {
    "portrait background color", "portrait bg color",
}, function()
    return GeneralRGB("portraitBgColor", 0.05, 0.05, 0.05)
end, function(r, g, b)
    SetAllPortraitRGB("portraitBgColor", r, g, b)
end, { category = "Colors / Portrait", attribute = "portraitBackgroundColor", defaultR = 0.05, defaultG = 0.05, defaultB = 0.05, apply = ApplyPortraitColors })

Registry:RegisterAction({
    key = "reset_class_colors",
    label = "Reset Class Bar Colors",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local fn = ColorAPI().ResetAllClassColors
        if type(fn) == "function" then fn() else GeneralDB().classColors = nil end
        ApplyColors("MSUF_ASSISTANT_RESET_CLASS_COLORS")
        return true, "Done. Class bar colors reset."
    end,
})

Registry:RegisterAction({
    key = "reset_bar_background_color",
    label = "Reset Bar Background Tint",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local fn = ColorAPI().ResetClassBarBgColor
        if type(fn) == "function" then
            fn()
        else
            local g = GeneralDB()
            g.classBarBgR, g.classBarBgG, g.classBarBgB = nil, nil, nil
        end
        ApplyColors("MSUF_ASSISTANT_RESET_BAR_BACKGROUND_COLOR")
        return true, "Done. Bar background tint reset."
    end,
})

Registry:RegisterAction({
    key = "reset_unitframe_colors",
    label = "Reset Unitframe Colors",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local fn = ColorAPI().ResetAllNPCColors
        if type(fn) == "function" then fn() else GeneralDB().npcColors = nil end
        ApplyColors("MSUF_ASSISTANT_RESET_UNITFRAME_COLORS")
        return true, "Done. Unitframe colors reset."
    end,
})

Registry:RegisterAction({
    key = "reset_npc_type_colors",
    label = "Reset NPC Type Colors",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local fn = ColorAPI().ResetNPCTypeColors
        if type(fn) == "function" then fn() else GeneralDB().npcColors = nil end
        ApplyColors("MSUF_ASSISTANT_RESET_NPC_TYPE_COLORS")
        return true, "Done. NPC type colors reset."
    end,
})

Registry:RegisterAction({
    key = "reset_bar_colors",
    label = "Reset Bar Colors",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local g = GeneralDB()
        for _, prefix in ipairs({ "absorbBarColor", "healAbsorbBarColor", "powerBarBgColor", "aggroBorder", "purgeBorderColor", "barOutlineColor" }) do
            g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"], g[prefix .. "A"] = nil, nil, nil, nil
        end
        g.hlAggroColorR, g.hlAggroColorG, g.hlAggroColorB = nil, nil, nil
        g.hlPurgeColorR, g.hlPurgeColorG, g.hlPurgeColorB = nil, nil, nil
        g.aggroBorderColorR, g.aggroBorderColorG, g.aggroBorderColorB = nil, nil, nil
        g.powerBarBgMatchBarColor = nil
        ApplyColors("MSUF_ASSISTANT_RESET_BAR_COLORS")
        return true, "Done. Bar colors reset."
    end,
})

Registry:RegisterAction({
    key = "reset_dispel_colors",
    label = "Reset Dispel Colors",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local g = GeneralDB()
        g.dispelBorderColorR, g.dispelBorderColorG, g.dispelBorderColorB = nil, nil, nil
        g.hlDispelColorR, g.hlDispelColorG, g.hlDispelColorB = nil, nil, nil
        g.hlDispelColorMode = nil
        for _, key in ipairs({ "Magic", "Curse", "Disease", "Poison", "Bleed" }) do
            local prefix = "dispelType" .. key
            g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"] = nil, nil, nil
        end
        ApplyColors("MSUF_ASSISTANT_RESET_DISPEL_COLORS")
        return true, "Done. Dispel colors reset."
    end,
})

Registry:RegisterAction({
    key = "reset_castbar_colors",
    label = "Reset Castbar Colors",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local api = ColorAPI()
        if type(api.ResetCastbarTextColorToGlobal) == "function" then api.ResetCastbarTextColorToGlobal() end
        if type(api.ResetCastbarBorderColor) == "function" then api.ResetCastbarBorderColor() end
        if type(api.ResetCastbarBackgroundColor) == "function" then api.ResetCastbarBackgroundColor() end
        local g = GeneralDB()
        g.castbarFontR, g.castbarFontG, g.castbarFontB = nil, nil, nil
        g.castbarBorderR, g.castbarBorderG, g.castbarBorderB, g.castbarBorderA = nil, nil, nil, nil
        g.castbarBgR, g.castbarBgG, g.castbarBgB, g.castbarBgA = nil, nil, nil, nil
        g.castbarInterruptibleR, g.castbarInterruptibleG, g.castbarInterruptibleB = nil, nil, nil
        g.castbarNonInterruptibleR, g.castbarNonInterruptibleG, g.castbarNonInterruptibleB = nil, nil, nil
        g.castbarInterruptFeedbackR, g.castbarInterruptFeedbackG, g.castbarInterruptFeedbackB = nil, nil, nil
        g.playerCastbarOverrideEnabled = false
        g.playerCastbarOverrideMode = "CLASS"
        g.playerCastbarOverrideR, g.playerCastbarOverrideG, g.playerCastbarOverrideB = nil, nil, nil
        g.kickReadyColor, g.kickNotReadyColor = nil, nil
        ApplyCastbarColors("MSUF_ASSISTANT_RESET_CASTBAR_COLORS")
        return true, "Done. Castbar colors reset."
    end,
})

Registry:RegisterAction({
    key = "reset_gameplay_colors",
    label = "Reset Gameplay Colors",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local gp = GameplayDB()
        gp.combatTimerColor = { 1, 1, 1 }
        gp.combatStateEnterColor = { 1, 1, 1 }
        gp.combatStateLeaveColor = gp.combatStateColorSync and { 1, 1, 1 } or { 0.7, 0.7, 0.7 }
        gp.crosshairInRangeColor = { 0, 1, 0 }
        gp.crosshairOutRangeColor = { 1, 0, 0 }
        ApplyGameplayColors("MSUF_ASSISTANT_RESET_GAMEPLAY_COLORS")
        return true, "Done. Gameplay colors reset."
    end,
})

Registry:RegisterAction({
    key = "reset_aura_colors",
    label = "Reset Aura Colors",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local g = GeneralDB()
        g.aurasOwnBuffHighlightColor = { 1, 0.85, 0.2 }
        g.aurasOwnDebuffHighlightColor = { 1, 0.85, 0.2 }
        g.aurasStackCountColor = { 1, 1, 1 }
        g.aurasCooldownTextSafeColor = nil
        g.aurasCooldownTextWarningColor = { 1, 0.85, 0.2 }
        g.aurasCooldownTextUrgentColor = { 1, 0.55, 0.1 }
        local sh = AuraSharedDB()
        sh.pandemicR, sh.pandemicG, sh.pandemicB = 0, 0.4, 1
        ApplyAuraColors("MSUF_ASSISTANT_RESET_AURA_COLORS")
        return true, "Done. Aura colors reset."
    end,
})

Registry:RegisterAction({
    key = "reset_portrait_colors",
    label = "Reset Portrait Colors",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        SetAllPortraitRGB("portraitBorderColor", 1, 1, 1)
        SetAllPortraitRGB("portraitBgColor", 0.05, 0.05, 0.05)
        local g = GeneralDB()
        g.portraitBorderColorA = 1
        g.portraitBgColorA = 0.85
        ApplyPortraitColors("MSUF_ASSISTANT_RESET_PORTRAIT_COLORS")
        return true, "Done. Portrait colors reset."
    end,
})

Registry:RegisterAction({
    key = "reset_resource_colors",
    label = "Reset Resource Colors",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local g = GeneralDB()
        g.powerColorOverrides = nil
        g.classPowerColorOverrides = nil
        g.classPowerBgColorOverrides = nil
        ApplyClassPowerColors("MSUF_ASSISTANT_RESET_RESOURCE_COLORS")
        return true, "Done. Resource colors reset."
    end,
})
end
RegisterAssistantColorSettings()
