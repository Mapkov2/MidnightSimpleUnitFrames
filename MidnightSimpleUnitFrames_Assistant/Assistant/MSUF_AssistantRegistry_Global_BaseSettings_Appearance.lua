-- Assistant Global base appearance setting registry.
-- Loaded before MSUF_AssistantRegistry_Global_BaseSettings.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.RegisterBaseAppearanceSettings(ctx)
    if type(ctx) ~= "table" then return end

    local ApplyVisuals = ctx.ApplyVisuals
    local ApplyColors = ctx.ApplyColors
    local ApplyFonts = ctx.ApplyFonts
    local RegisterGeneralNumberSetting = ctx.RegisterGeneralNumberSetting
    local RegisterGeneralEnum = ctx.RegisterGeneralEnum
    local RegisterGeneralString = ctx.RegisterGeneralString
    if type(ApplyVisuals) ~= "function" or type(ApplyColors) ~= "function" or type(ApplyFonts) ~= "function" then return end
    if type(RegisterGeneralNumberSetting) ~= "function" or type(RegisterGeneralEnum) ~= "function" then return end
    if type(RegisterGeneralString) ~= "function" then return end

    local BAR_MODE_ALIASES = {
        "bar mode", "bar color mode", "health bar mode", "bars mode", "bars color mode",
        "class colors", "class color mode", "unified bars", "gradient bars",
        "leisten modus", "balken modus", "klassenfarben", "verlauf balken",
    }
    RegisterGeneralEnum("barMode", "barMode", "Global Bar Mode", "dark", { "dark", "class", "unified", "gradient" }, BAR_MODE_ALIASES, {
        category = "Global / Bars",
        frameType = "bars",
        page = "opt_colors",
        apply = ApplyColors,
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
        "font palette color", "global font palette color", "text palette color", "palette font color",
        "schrift palettenfarbe", "text palettenfarbe",
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
end
