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
    local UNIT_DISPEL_SYMBOL_STYLE_VALUES = ctx.UNIT_DISPEL_SYMBOL_STYLE_VALUES or {}
    local UNIT_DISPEL_SYMBOL_MODE_VALUES = ctx.UNIT_DISPEL_SYMBOL_MODE_VALUES or {}
    local UNIT_DISPEL_SYMBOL_GROWTH_VALUES = ctx.UNIT_DISPEL_SYMBOL_GROWTH_VALUES or {}
    local UNIT_DISPEL_SYMBOL_ANCHOR_VALUES = ctx.UNIT_DISPEL_SYMBOL_ANCHOR_VALUES or {}
    local UNIT_DISPEL_SYMBOL_STRATA_VALUES = ctx.UNIT_DISPEL_SYMBOL_STRATA_VALUES or {}

    if type(GeneralDB) ~= "function" then return end
    if type(ApplyBars) ~= "function" or type(ApplyBarOutline) ~= "function" or type(ApplyRoundedBars) ~= "function" then return end
    if type(ApplyAggroBorder) ~= "function" or type(ApplyDispelPurgeBorder) ~= "function" then return end
    if type(ApplyBossTargetBorder) ~= "function" or type(ApplyHighlightBorders) ~= "function" then return end
    if type(RegisterGeneralBoolean) ~= "function" or type(RegisterGeneralNumberSetting) ~= "function" then return end
    if type(RegisterGeneralEnum) ~= "function" or type(RegisterGeneralMappedEnum) ~= "function" then return end
    if type(RegisterBarsBoolean) ~= "function" or type(RegisterBarsNumber) ~= "function" or type(RegisterBarsEnum) ~= "function" then return end

    RegisterBarsNumber("barOutlineThickness", "outline", "Global Bar Outline Thickness", 1, 0, 8, {
        -- Human wording first: the registry keeps only the first
        -- MAX_SETTING_ALIASES entries and drops the rest in silence.
        "bar outline thickness", "frame outline thickness", "border thickness", "outline thickness",
        "border around my frames", "border around the frames", "put a border around my frames",
        "chunkier outline", "chunkier outline around my frames", "chunkier frame outline",
        "make border thicker", "make border thinner", "make frame outline bigger",
        "make outline bigger", "make outline smaller", "thicker frame border",
        "bar outline", "frame outline", "frame border", "bar border thickness",
    }, { category = "Global / Bars / Outline", frameType = "globalBars", apply = ApplyBarOutline, reason = "MSUF_ASSISTANT_BAR_OUTLINE" })
    RegisterBarsNumber("barOutlineLayer", "layer", "Global Bar Outline Layer", 0, 0, 30, {
        "bar outline strata", "bar outline layer", "frame outline strata", "frame outline layer",
        "global bar outline strata", "global frame outline strata", "outline strata", "outline layer",
        -- "draw the frame outline on layer 5" has no contiguous "outline
        -- layer" token pair, so Thickness ("frame outline" + a number) used
        -- to win and wrote 5 into the wrong control.
        "outline on layer", "frame outline on layer", "draw the frame outline on layer",
    }, {
        category = "Global / Bars / Outline",
        frameType = "globalBars",
        apply = ApplyBarOutline,
        reason = "MSUF_ASSISTANT_BAR_OUTLINE_LAYER",
        step = 1,
        description = "Controls the shared bar and frame outline Layer (0-30).",
    })
    RegisterGeneralNumberSetting("barOutlineColorA", "barOutlineOpacity", "Global Bar Outline Opacity", 1, 0, 1, {
        "bar outline opacity", "bar outline alpha", "frame outline opacity", "frame outline alpha",
        "bar border opacity", "bar border alpha", "frame border opacity", "frame border alpha",
        "outline opacity", "outline alpha",
        -- "make the frame border half transparent" routed to Thickness via
        -- its bare "frame border" alias and wrote thickness 0. Transparency
        -- wording belongs to opacity, whatever the value words are.
        "frame border half transparent", "border half transparent",
        "frame border transparent", "outline half transparent",
        "frame border transparency", "border transparency", "outline transparency",
    }, {
        category = "Global / Bars / Outline",
        frameType = "globalBars",
        apply = ApplyBarOutline,
        reason = "MSUF_ASSISTANT_BAR_OUTLINE_OPACITY",
        step = 0.05,
        percent = true,
        description = "Controls the alpha channel used by the shared bar/frame outline color.",
    })
    -- "square" is how a player asks for rounding OFF, and it appears in no
    -- on/off word list; without these the sentence resolved the control and
    -- then had no value to apply.
    -- Longest match wins, so the negations have to be longer than the bare
    -- "round" they contain -- otherwise "don't round the unit frames" reads as
    -- the word "round" and switches rounding ON.
    local ROUNDED_POLARITY = {
        square = false, squared = false, ["square corners"] = false, ["sharp corners"] = false,
        ["dont round"] = false, ["do not round"] = false, ["never round"] = false,
        ["stop rounding"] = false, ["no rounding"] = false, ["not rounded"] = false,
        ["dont round my party and raid frames"] = false, ["dont round my"] = false,
        rounded = true, round = true, ["round corners"] = true, ["rounded corners"] = true,
        ["soft corners"] = true,
    }
    RegisterBarsBoolean("roundedFramesEnabled", "rounded", "Rounded Frame Texture", false, {
        "rounded frame texture", "rounded frames", "round corners", "rounded corners", "rounded texture",
        "soft corners", "square frames", "square corners", "frames square", "frames rounded",
    }, {
        category = "Global / Bars / Rounded",
        frameType = "globalBars",
        apply = ApplyRoundedBars,
        reason = "MSUF_ASSISTANT_ROUNDED_FRAMES",
        requiresReload = true,
        valueAliases = ROUNDED_POLARITY,
        description = "Master switch for the rounded frame style. Each surface below can still opt out.",
    })
    RegisterBarsNumber("roundedCornerStrength", "roundedCornerStrength", "Rounded Corner Strength", 3, 1, 5, {
        "rounded corner strength", "corner rounding", "rounding strength", "corner radius", "rounded radius",
        "stronger rounded corners", "weaker rounded corners", "subtle rounded corners",
        "corners rounder", "make the corners rounder", "rounder corners", "sharper corners",
        "how round the corners are",
    }, {
        category = "Global / Bars / Rounded",
        frameType = "globalBars",
        apply = ApplyRoundedBars,
        reason = "MSUF_ASSISTANT_ROUNDED_CORNER_STRENGTH",
        step = 1,
        description = "Controls the shared corner shape used by rounded masks, outlines, highlights, mouseover edges, and power bars.",
    })
    RegisterBarsBoolean("roundedUnitFrames", "roundedUnitFrames", "Rounded Unit Frames", true, {
        "rounded unit frames", "rounded unitframes", "unit frame corners", "unitframe corners",
        "unit frames square", "square unit frames", "round the unit frames",
    }, {
        category = "Global / Bars / Rounded",
        frameType = "globalBars",
        apply = ApplyRoundedBars,
        reason = "MSUF_ASSISTANT_ROUNDED_UNIT_FRAMES",
        valueAliases = ROUNDED_POLARITY,
    })
    RegisterBarsBoolean("roundedGroupFrames", "roundedGroupFrames", "Rounded Group Frames", true, {
        "rounded group frames", "rounded party frames", "rounded raid frames", "group frame corners",
        "group frames square", "square group frames", "party and raid frames square",
        "round the party frames", "round the raid frames",
    }, {
        category = "Global / Bars / Rounded",
        frameType = "globalBars",
        apply = ApplyRoundedBars,
        reason = "MSUF_ASSISTANT_ROUNDED_GROUP_FRAMES",
        valueAliases = ROUNDED_POLARITY,
    })
    RegisterBarsBoolean("roundedPowerBars", "roundedPowerBars", "Rounded Power Bars", true, {
        "rounded power bars", "rounded powerbar", "power bar corners", "powerbar corners",
        "power bars square", "square power bars", "mana bars square", "round the power bars",
        "round the mana bars",
    }, {
        category = "Global / Bars / Rounded",
        frameType = "globalBars",
        apply = ApplyRoundedBars,
        reason = "MSUF_ASSISTANT_ROUNDED_POWER_BARS",
        valueAliases = ROUNDED_POLARITY,
    })
    RegisterBarsBoolean("roundedCastbars", "roundedCastbars", "Rounded Castbars", false, {
        "rounded castbars", "castbar corners", "cast bars rounded", "rounded cast bars",
        "castbars square", "square castbars", "round the castbars", "round my castbars",
    }, {
        valueAliases = ROUNDED_POLARITY,
        category = "Global / Bars / Rounded",
        frameType = "globalBars",
        apply = ApplyRoundedBars,
        reason = "MSUF_ASSISTANT_ROUNDED_CASTBARS",
        description = "Rounds MSUF castbar surfaces and outlines without changing Blizzard castbars, spell icons, or the GCD bar.",
    })
    RegisterBarsBoolean("roundedClassResources", "roundedClassResources", "Rounded Class Resources", false, {
        "rounded class resources", "rounded combo points", "rounded soul shards", "class resource corners",
        "class resources square", "square class resources", "round the class resource bars",
        "round the class resources",
    }, {
        valueAliases = ROUNDED_POLARITY,
        category = "Global / Bars / Rounded",
        frameType = "globalBars",
        apply = ApplyRoundedBars,
        reason = "MSUF_ASSISTANT_ROUNDED_CLASS_RESOURCES",
        description = "Rounds rectangular Class Resource bars without changing Circle, Diamond, or Hex shapes.",
    })
    RegisterBarsBoolean("roundedMouseover", "roundedMouseover", "Rounded Mouseover Highlights", true, {
        "rounded mouseover", "rounded hover", "rounded hover border", "mouseover rounded", "rounded mouseover highlights",
        "mouseover highlight square", "square mouseover highlight", "hover highlight square",
    }, {
        category = "Global / Bars / Rounded",
        frameType = "globalBars",
        apply = ApplyRoundedBars,
        reason = "MSUF_ASSISTANT_ROUNDED_MOUSEOVER",
        valueAliases = ROUNDED_POLARITY,
    })

    RegisterGeneralNumberSetting("highlightBorderThickness", "highlightBorder", "Highlight Border Thickness", 2, 1, 30, {
        "highlight border thickness", "highlight border size", "aggro border size", "dispel border size",
        "aggro and dispel border", "aggro and dispel border thickness", "purge border size",
        "boss target border size", "highlight border width", "how thick the highlight border is",
    }, { category = "Global / Bars / Highlight Borders", frameType = "globalBars", apply = ApplyHighlightBorders, reason = "MSUF_ASSISTANT_HIGHLIGHT_BORDER_THICKNESS" })
    RegisterGeneralMappedEnum("aggroOutlineMode", "aggroBorder", "Aggro Border", "on", ON_OFF_VALUES, ON_OFF_STORAGE, {
        "aggro border", "threat border", "aggro outline", "threat highlight", "aggro highlight",
        "border when i have aggro", "border when i have threat", "border when something is attacking me",
        "highlight when i have aggro", "highlight the frame when i have threat",
        "highlighting frames when i have threat", "show me when i pull aggro",
        "frame when something is attacking me", "highlight the frame when something is attacking me",
        "stop highlighting frames when i have threat", "highlighting frames when i have threat",
    }, { category = "Global / Bars / Highlight Borders", frameType = "globalBars", apply = ApplyAggroBorder, reason = "MSUF_ASSISTANT_AGGRO_BORDER", valueAliases = ON_OFF_ALIASES })
    RegisterGeneralEnum("aggroMode", "aggroMode", "Aggro Shows For", "ALL", AGGRO_MODE_VALUES, {
        "aggro shows for", "aggro role filter", "aggro non tanks", "aggro not tank", "threat non tanks",
        "aggro border roles", "who the aggro border shows for", "aggro border when i am not the tank",
        "aggro border only when i am not the tank", "aggro role", "threat border roles",
    }, {
        category = "Global / Bars / Highlight Borders",
        frameType = "globalBars",
        apply = ApplyAggroBorder,
        reason = "MSUF_ASSISTANT_AGGRO_MODE",
        valueAliases = AGGRO_MODE_ALIASES,
    })
    RegisterGeneralMappedEnum("dispelOutlineMode", "dispelBorder", "Dispel Border", "on", ON_OFF_VALUES, ON_OFF_STORAGE, {
        "dispel border", "dispellable border", "dispel outline", "dispel highlight",
        "border when there is a debuff i can dispel", "border for dispellable debuffs",
        "highlight dispellable debuffs", "border when someone has a dispellable debuff",
    }, { category = "Global / Bars / Highlight Borders", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_DISPEL_BORDER", valueAliases = ON_OFF_ALIASES })
    RegisterGeneralEnum("dispelBorderTrigger", "dispelBorderTrigger", "Dispel Border Detects", "DISPEL_TYPE", DISPEL_TRIGGER_VALUES, {
        "dispel border detects", "dispel border trigger", "dispel detection",
        "what the dispel border reacts to", "dispel border reacts to", "dispel border react to",
        "which debuffs the dispel border shows", "dispel border rule",
        "only react to debuffs i can dispel myself", "dispel border should only react to debuffs",
        "react to debuffs i can dispel myself",
    }, { category = "Global / Bars / Highlight Borders", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_DISPEL_BORDER_TRIGGER", valueAliases = DISPEL_TRIGGER_ALIASES })
    RegisterGeneralMappedEnum("purgeOutlineMode", "purgeBorder", "Purge Border", "off", ON_OFF_VALUES, ON_OFF_STORAGE, {
        "purge border", "purge outline", "purgeable border", "purge highlight",
        "border when the target has a buff i can purge", "border for stealable buffs",
        "highlight purgeable buffs", "border for purgeable buffs",
    }, { category = "Global / Bars / Highlight Borders", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_PURGE_BORDER", valueAliases = ON_OFF_ALIASES })
    RegisterGeneralMappedEnum("bossTargetOutlineMode", "bossTargetBorder", "Boss Target Border", "on", ON_OFF_VALUES, ON_OFF_STORAGE, {
        "boss target border", "boss target highlight", "boss target outline",
        "who the boss is attacking", "highlighting who the boss is attacking",
        "border for the boss target", "mark who the boss is targeting", "boss aggro target border",
        "stop highlighting who the boss is attacking", "highlighting who the boss is attacking",
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
        "which highlight border wins", "which border wins", "decide which highlight border wins",
        "which border is shown first", "order of the highlight borders",
    }, {
        category = "Global / Bars / Highlight Borders",
        frameType = "globalBars",
        apply = ApplyHighlightBorders,
        reason = "MSUF_ASSISTANT_HIGHLIGHT_PRIORITY",
    })

    local function UnitDispelOptions(opts)
        opts = opts or {}
        opts.page = "uf_player"
        opts.category = tostring(opts.category or "Unitframes / Dispel")
            :gsub("^Global / Bars / UnitFrame ", "Frames / Unitframes / ")
        return opts
    end
    local function RegisterUnitDispelBoolean(dbKey, attr, label, defaultValue, aliases, opts)
        return RegisterGeneralBoolean(dbKey, attr, label, defaultValue, aliases, UnitDispelOptions(opts))
    end
    local function RegisterUnitDispelNumber(dbKey, attr, label, defaultValue, minValue, maxValue, aliases, opts)
        return RegisterGeneralNumberSetting(dbKey, attr, label, defaultValue, minValue, maxValue, aliases, UnitDispelOptions(opts))
    end
    local function RegisterUnitDispelEnum(dbKey, attr, label, defaultValue, values, aliases, opts)
        return RegisterGeneralEnum(dbKey, attr, label, defaultValue, values, aliases, UnitDispelOptions(opts))
    end

    RegisterUnitDispelBoolean("unitDispelOverlayEnabled", "unitDispelOverlay", "UnitFrame Dispel Overlay", false, {
        "unitframe dispel overlay", "unit frame dispel overlay", "dispel overlay", "health bar dispel overlay",
    }, { category = "Global / Bars / UnitFrame Dispel Overlay", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_OVERLAY" })
    RegisterUnitDispelEnum("unitDispelOverlayTrigger", "unitDispelOverlayTrigger", "UnitFrame Dispel Overlay Detects", "BORDER", UNIT_DISPEL_TRIGGER_VALUES, {
        "unitframe dispel overlay detects", "unitframe dispel overlay trigger", "dispel overlay detects",
    }, { category = "Global / Bars / UnitFrame Dispel Overlay", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_OVERLAY_TRIGGER", valueAliases = UNIT_DISPEL_TRIGGER_ALIASES })
    RegisterUnitDispelEnum("unitDispelOverlayStyle", "unitDispelOverlayStyle", "UnitFrame Dispel Overlay Style", "FULL", UNIT_DISPEL_STYLE_VALUES, {
        "unitframe dispel overlay style", "dispel overlay style", "unit frame dispel overlay style",
    }, { category = "Global / Bars / UnitFrame Dispel Overlay", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_OVERLAY_STYLE", valueAliases = UNIT_DISPEL_STYLE_ALIASES })
    RegisterUnitDispelBoolean("unitDispelOverlayOnHealth", "unitDispelOverlayHealthOnly", "UnitFrame Dispel Overlay Current Health Only", true, {
        "dispel overlay current health only", "unitframe dispel overlay current health", "dispel overlay on health only",
    }, { category = "Global / Bars / UnitFrame Dispel Overlay", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_OVERLAY_HEALTH" })
    RegisterUnitDispelNumber("unitDispelOverlayAlpha", "unitDispelOverlayOpacity", "UnitFrame Dispel Overlay Opacity", 0.35, 0.05, 1, {
        "dispel overlay opacity", "unitframe dispel overlay opacity", "dispel overlay alpha",
    }, { category = "Global / Bars / UnitFrame Dispel Overlay", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_OVERLAY_ALPHA", step = 0.05, percent = true })

    -- UnitFrame dispel SYMBOL. Same shape as the overlay block above: the
    -- generated AutoCoverage entries alone carry no category or frameType, so
    -- without these the settings exist but route to no Menu2 page.
    RegisterUnitDispelBoolean("unitDispelSymbolEnabled", "unitDispelSymbol", "UnitFrame Dispel Symbol", false, {
        "unitframe dispel symbol", "unit frame dispel symbol", "dispel symbol", "debuff type symbol",
        "show debuff type", "which debuff type",
    }, { category = "Global / Bars / UnitFrame Dispel Symbol", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_SYMBOL" })
    RegisterUnitDispelEnum("unitDispelSymbolStyle", "unitDispelSymbolStyle", "UnitFrame Dispel Symbol Set", "BLIZZARD", UNIT_DISPEL_SYMBOL_STYLE_VALUES, {
        "dispel symbol set", "unitframe dispel symbol set", "debuff type symbol set", "dispel symbol style",
    }, { category = "Global / Bars / UnitFrame Dispel Symbol", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_SYMBOL_STYLE" })
    RegisterUnitDispelEnum("unitDispelSymbolMode", "unitDispelSymbolMode", "UnitFrame Dispel Symbol Shows", "ALL", UNIT_DISPEL_SYMBOL_MODE_VALUES, {
        "dispel symbol shows", "dispel symbol mode", "one symbol per dispel type",
    }, { category = "Global / Bars / UnitFrame Dispel Symbol", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_SYMBOL_MODE" })
    RegisterUnitDispelEnum("unitDispelSymbolTrigger", "unitDispelSymbolTrigger", "UnitFrame Dispel Symbol Detects", "BORDER", UNIT_DISPEL_TRIGGER_VALUES, {
        "dispel symbol detects", "unitframe dispel symbol trigger", "dispel symbol trigger",
    }, { category = "Global / Bars / UnitFrame Dispel Symbol", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_SYMBOL_TRIGGER", valueAliases = UNIT_DISPEL_TRIGGER_ALIASES })
    RegisterUnitDispelEnum("unitDispelSymbolAnchor", "unitDispelSymbolAnchor", "UnitFrame Dispel Symbol Anchor", "TOPRIGHT", UNIT_DISPEL_SYMBOL_ANCHOR_VALUES, {
        "dispel symbol anchor", "dispel symbol position", "where is the dispel symbol",
    }, { category = "Global / Bars / UnitFrame Dispel Symbol", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_SYMBOL_ANCHOR" })
    RegisterUnitDispelEnum("unitDispelSymbolGrowth", "unitDispelSymbolGrowth", "UnitFrame Dispel Symbol Grow", "RIGHT", UNIT_DISPEL_SYMBOL_GROWTH_VALUES, {
        "dispel symbol grow", "dispel symbol growth", "dispel symbol direction",
    }, { category = "Global / Bars / UnitFrame Dispel Symbol", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_SYMBOL_GROWTH" })
    RegisterUnitDispelNumber("unitDispelSymbolSize", "unitDispelSymbolSize", "UnitFrame Dispel Symbol Size", 14, 4, 48, {
        "dispel symbol size", "unitframe dispel symbol size", "how big is the dispel symbol",
    }, { category = "Global / Bars / UnitFrame Dispel Symbol", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_SYMBOL_SIZE", step = 1 })
    RegisterUnitDispelNumber("unitDispelSymbolSpacing", "unitDispelSymbolSpacing", "UnitFrame Dispel Symbol Spacing", 2, 0, 32, {
        "dispel symbol spacing", "gap between dispel symbols",
    }, { category = "Global / Bars / UnitFrame Dispel Symbol", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_SYMBOL_SPACING", step = 1 })
    RegisterUnitDispelNumber("unitDispelSymbolX", "unitDispelSymbolOffsetX", "UnitFrame Dispel Symbol Offset X", 0, -128, 128, {
        "dispel symbol offset x", "move dispel symbol horizontally",
    }, { category = "Global / Bars / UnitFrame Dispel Symbol", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_SYMBOL_X", step = 1 })
    RegisterUnitDispelNumber("unitDispelSymbolY", "unitDispelSymbolOffsetY", "UnitFrame Dispel Symbol Offset Y", 0, -128, 128, {
        "dispel symbol offset y", "move dispel symbol vertically",
    }, { category = "Global / Bars / UnitFrame Dispel Symbol", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_SYMBOL_Y", step = 1 })
    RegisterUnitDispelNumber("unitDispelSymbolAlpha", "unitDispelSymbolOpacity", "UnitFrame Dispel Symbol Opacity", 1, 0.05, 1, {
        "dispel symbol opacity", "dispel symbol alpha",
    }, { category = "Global / Bars / UnitFrame Dispel Symbol", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_SYMBOL_ALPHA", step = 0.05, percent = true })
    RegisterUnitDispelNumber("unitDispelSymbolLayer", "unitDispelSymbolLayer", "UnitFrame Dispel Symbol Effect Layer", 8, 0, 30, {
        "dispel symbol layer", "dispel symbol effect layer",
    }, { category = "Global / Bars / UnitFrame Dispel Symbol", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_SYMBOL_LAYER", step = 1 })
    RegisterUnitDispelEnum("unitDispelSymbolStrata", "unitDispelSymbolStrata", "UnitFrame Dispel Symbol Strata", "AUTO", UNIT_DISPEL_SYMBOL_STRATA_VALUES, {
        "dispel symbol strata", "dispel symbol frame strata",
    }, { category = "Global / Bars / UnitFrame Dispel Symbol", frameType = "globalBars", apply = ApplyDispelPurgeBorder, reason = "MSUF_ASSISTANT_UNIT_DISPEL_SYMBOL_STRATA" })

    RegisterBarsBoolean("smoothPowerBar", "smoothPower", "Smooth Power Bar", false, {
        "smooth power bar", "smooth power", "smooth mana bar", "power bar smoothing",
        "animate the power bar", "power bar animation", "mana bar animation",
        "power bar slide", "mana bar slide instead of jumping", "power bar animate smoothly",
        "mana bar to slide instead of jumping", "power bar to slide instead of jumping",
        "make the power bar animate smoothly", "power bar animate smoothly",
    }, {
        category = "Global / Bars / Power",
        frameType = "globalBars",
        apply = ApplyBars,
        reason = "MSUF_ASSISTANT_SMOOTH_POWER",
        description = "Animates power bar changes instead of snapping straight to the new value.",
    })
    RegisterBarsBoolean("realtimePowerText", "realtimePowerText", "Realtime Power Text", true, {
        "realtime power text", "real time power text", "instant power text", "accurate power text",
        "power text updates instantly", "power text update instantly", "power number accuracy",
        "mana number accurate", "mana number accurate at all times", "power text accuracy",
        "power text to update instantly", "power text to update instantly at all times",
    }, {
        category = "Global / Bars / Power",
        frameType = "globalBars",
        apply = ApplyBars,
        reason = "MSUF_ASSISTANT_REALTIME_POWER_TEXT",
        description = "Reads the power number every frame so it matches the bar exactly, instead of following the smoothed value.",
    })
end
