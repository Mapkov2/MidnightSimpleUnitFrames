-- Assistant Global Bar registry: exposes shared bar texture, border, opacity, and color controls.
-- Writes must flow through registry helpers so global overrides and previews stay synchronized.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local C = A.RegistryCore
if type(C) ~= "table" then return end

-- Global Bars assistant registry domain.
local Registry = C.Registry
local GeneralDB = C.GeneralDB
local CallGlobal = C.CallGlobal
local ApplyBars = C.ApplyBars
local ApplyBarGradients = C.ApplyBarGradients
local ApplyBarOutline = C.ApplyBarOutline
local ApplyRoundedBars = C.ApplyRoundedBars
local ApplyAggroBorder = C.ApplyAggroBorder
local ApplyDispelPurgeBorder = C.ApplyDispelPurgeBorder
local ApplyBossTargetBorder = C.ApplyBossTargetBorder
local ApplyHighlightBorders = C.ApplyHighlightBorders
local ApplyAbsorbBars = C.ApplyAbsorbBars
local RegisterGeneralBoolean = C.RegisterGeneralBoolean
local RegisterGeneralNumberSetting = C.RegisterGeneralNumberSetting
local RegisterGeneralEnum = C.RegisterGeneralEnum
local RegisterGeneralString = C.RegisterGeneralString
local RegisterGeneralMappedEnum = C.RegisterGeneralMappedEnum
local RegisterBarsBoolean = C.RegisterBarsBoolean
local RegisterBarsNumber = C.RegisterBarsNumber
local GLOBAL_SCOPE_ORDER = C.GLOBAL_SCOPE_ORDER
local GlobalScopeIsGroup = C.GlobalScopeIsGroup
local GlobalScopeHasOverride = C.GlobalScopeHasOverride
local GlobalScopeSetOverride = C.GlobalScopeSetOverride
local GlobalScopeRead = C.GlobalScopeRead
local GlobalScopeWrite = C.GlobalScopeWrite
local GlobalScopeAliases = C.GlobalScopeAliases
local RegisterScopedSetting = C.RegisterScopedSetting
local RegisterScopedMappedEnum = C.RegisterScopedMappedEnum

if not (Registry and type(Registry.RegisterSetting) == "function") then return end
if type(GeneralDB) ~= "function" or type(RegisterScopedSetting) ~= "function" then return end
if type(GLOBAL_SCOPE_ORDER) ~= "table" or type(GlobalScopeAliases) ~= "function" then return end
if type(RegisterGeneralString) ~= "function" or type(RegisterGeneralMappedEnum) ~= "function" then return end
if type(RegisterBarsBoolean) ~= "function" or type(RegisterBarsNumber) ~= "function" then return end
if type(RegisterGeneralBoolean) ~= "function" or type(RegisterGeneralNumberSetting) ~= "function" then return end
if type(RegisterGeneralEnum) ~= "function" or type(RegisterScopedMappedEnum) ~= "function" then return end
if type(GlobalScopeIsGroup) ~= "function" or type(GlobalScopeHasOverride) ~= "function" then return end
if type(GlobalScopeSetOverride) ~= "function" or type(GlobalScopeRead) ~= "function" or type(GlobalScopeWrite) ~= "function" then return end
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
