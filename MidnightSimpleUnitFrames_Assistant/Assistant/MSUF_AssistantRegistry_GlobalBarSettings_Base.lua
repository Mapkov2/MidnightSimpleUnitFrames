-- Assistant Global Bar base/highlight setting registry.
-- Loaded before MSUF_AssistantRegistry_GlobalBarSettings.lua; the main file passes shared helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalBarRegistry = A.GlobalBarRegistry or {}

function A.GlobalBarRegistry.RegisterBaseBarSettings(ctx)
    if type(ctx) ~= "table" then return end

    local GeneralDB = ctx.GeneralDB
    local ApplyBars = ctx.ApplyBars
    local ApplyBarOutline = ctx.ApplyBarOutline
    local ApplyRoundedBars = ctx.ApplyRoundedBars
    local ApplyAggroBorder = ctx.ApplyAggroBorder
    local ApplyDispelPurgeBorder = ctx.ApplyDispelPurgeBorder
    local ApplyBossTargetBorder = ctx.ApplyBossTargetBorder
    local ApplyHighlightBorders = ctx.ApplyHighlightBorders
    local RegisterGeneralBoolean = ctx.RegisterGeneralBoolean
    local RegisterGeneralNumberSetting = ctx.RegisterGeneralNumberSetting
    local RegisterGeneralEnum = ctx.RegisterGeneralEnum
    local RegisterGeneralMappedEnum = ctx.RegisterGeneralMappedEnum
    local RegisterBarsBoolean = ctx.RegisterBarsBoolean
    local RegisterBarsNumber = ctx.RegisterBarsNumber
    local RegisterBarsEnum = ctx.RegisterBarsEnum
    local ON_OFF_STORAGE = ctx.ON_OFF_STORAGE or {}
    local ON_OFF_VALUES = ctx.ON_OFF_VALUES or {}
    local ON_OFF_ALIASES = ctx.ON_OFF_ALIASES
    local AGGRO_MODE_VALUES = ctx.AGGRO_MODE_VALUES or {}
    local AGGRO_MODE_ALIASES = ctx.AGGRO_MODE_ALIASES
    local DISPEL_TRIGGER_VALUES = ctx.DISPEL_TRIGGER_VALUES or {}
    local DISPEL_TRIGGER_ALIASES = ctx.DISPEL_TRIGGER_ALIASES
    local UNIT_DISPEL_TRIGGER_VALUES = ctx.UNIT_DISPEL_TRIGGER_VALUES or {}
    local UNIT_DISPEL_TRIGGER_ALIASES = ctx.UNIT_DISPEL_TRIGGER_ALIASES
    local UNIT_DISPEL_STYLE_VALUES = ctx.UNIT_DISPEL_STYLE_VALUES or {}
    local UNIT_DISPEL_STYLE_ALIASES = ctx.UNIT_DISPEL_STYLE_ALIASES

    if type(GeneralDB) ~= "function" then return end
    if type(ApplyBars) ~= "function" or type(ApplyBarOutline) ~= "function" or type(ApplyRoundedBars) ~= "function" then return end
    if type(ApplyAggroBorder) ~= "function" or type(ApplyDispelPurgeBorder) ~= "function" then return end
    if type(ApplyBossTargetBorder) ~= "function" or type(ApplyHighlightBorders) ~= "function" then return end
    if type(RegisterGeneralBoolean) ~= "function" or type(RegisterGeneralNumberSetting) ~= "function" then return end
    if type(RegisterGeneralEnum) ~= "function" or type(RegisterGeneralMappedEnum) ~= "function" then return end
    if type(RegisterBarsBoolean) ~= "function" or type(RegisterBarsNumber) ~= "function" or type(RegisterBarsEnum) ~= "function" then return end

    RegisterBarsNumber("barOutlineThickness", "outline", "Global Bar Outline Thickness", 1, 0, 8, {
        "bar outline thickness", "bar outline thicknesses", "bar outline", "global bar outline", "global frame outline", "frame outline", "frame outline thickness",
        "bar border thickness", "bar border", "frame border", "global frame border", "border thickness", "outline thickness",
        "make border thicker", "make border thinner", "make border bigger", "make border smaller",
        "make frame outline bigger", "make frame outline smaller", "make outline bigger", "make outline smaller",
        "border thicker", "border thinner", "border bigger", "border smaller", "outline thicker", "outline thinner", "outline bigger", "outline smaller",
    }, { category = "Global / Bars / Outline", frameType = "globalBars", apply = ApplyBarOutline, reason = "MSUF_ASSISTANT_BAR_OUTLINE" })
    RegisterBarsNumber("barOutlineLayer", "layer", "Global Bar Outline Layer", 0, 0, 30, {
        "bar outline strata", "bar outline layer", "frame outline strata", "frame outline layer",
        "global bar outline strata", "global frame outline strata", "outline strata", "outline layer",
    }, {
        category = "Global / Bars / Outline",
        frameType = "globalBars",
        apply = ApplyBarOutline,
        reason = "MSUF_ASSISTANT_BAR_OUTLINE_LAYER",
        step = 1,
        description = "Controls the shared bar and frame outline draw order on the unified Layer 0-30 scale.",
    })
    RegisterGeneralNumberSetting("barOutlineColorA", "barOutlineOpacity", "Global Bar Outline Opacity", 1, 0, 1, {
        "bar outline opacity", "bar outline alpha", "frame outline opacity", "frame outline alpha",
        "bar border opacity", "bar border alpha", "frame border opacity", "frame border alpha",
        "outline opacity", "outline alpha",
    }, {
        category = "Global / Bars / Outline",
        frameType = "globalBars",
        apply = ApplyBarOutline,
        reason = "MSUF_ASSISTANT_BAR_OUTLINE_OPACITY",
        step = 0.05,
        percent = true,
        description = "Controls the alpha channel used by the shared bar/frame outline color.",
    })
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
    RegisterGeneralEnum("aggroMode", "aggroMode", "Aggro Shows For", "ALL", AGGRO_MODE_VALUES, {
        "aggro shows for", "aggro role filter", "aggro non tanks", "aggro not tank", "threat non tanks",
    }, {
        category = "Global / Bars / Highlight Borders",
        frameType = "globalBars",
        apply = ApplyAggroBorder,
        reason = "MSUF_ASSISTANT_AGGRO_MODE",
        valueAliases = AGGRO_MODE_ALIASES,
    })
    RegisterGeneralMappedEnum("dispelOutlineMode", "dispelBorder", "Dispel Border", "on", ON_OFF_VALUES, ON_OFF_STORAGE, {
        "dispel border", "dispellable border", "dispel outline",
    }, { category = "Global / Bars / Highlight Borders", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_DISPEL_BORDER", valueAliases = ON_OFF_ALIASES })
    RegisterGeneralEnum("dispelBorderTrigger", "dispelBorderTrigger", "Dispel Border Detects", "DISPEL_TYPE", DISPEL_TRIGGER_VALUES, {
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
        "highlight prio", "border prio", "custom highlight prio", "highlight prioritaet", "border prioritaet",
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
end
