-- Assistant GroupFrames static registry data.
-- Loaded before MSUF_AssistantRegistry_GroupFrames.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistryData = A.GroupFramesRegistryData or {}

A.GroupFramesRegistryData.GROUP_BAR_MODE_VALUES = { "GLOBAL", "CLASS", "dark", "unified", "GRADIENT", "CUSTOM" }
A.GroupFramesRegistryData.GROUP_HEALTH_MODE_VALUES = { "CLASS", "GRADIENT", "CUSTOM" }
A.GroupFramesRegistryData.GROUP_TEXT_MODE_VALUES = {
    "NONE", "PERCENT", "CURRENT", "MAX", "DEFICIT", "CURMAX", "CURPERCENT",
    "CURMAXPERCENT", "MAXPERCENT", "PERCENTCUR", "PERCENTMAX", "PERCENTCURMAX",
}
A.GroupFramesRegistryData.GROUP_ANCHOR_VALUES = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT" }
A.GroupFramesRegistryData.GROUP_CORNER_ANCHOR_VALUES = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
A.GroupFramesRegistryData.GROUP_DISPEL_TRIGGER_VALUES = { "BORDER", "BY_ME", "BY_RAID", "DISPEL_TYPE" }
A.GroupFramesRegistryData.GROUP_DISPEL_STYLE_VALUES = { "FULL", "BOTTOM", "TOP", "LEFT", "RIGHT" }
A.GroupFramesRegistryData.GROUP_STRIPE_EDGE_VALUES = { "BOTTOM", "TOP" }
A.GroupFramesRegistryData.GROUP_RANGE_LAYER_VALUES = { "frame", "health" }
A.GroupFramesRegistryData.GROUP_DELIMITER_VALUES = { " ", "  ", " / ", " - ", " : ", " | " }
A.GroupFramesRegistryData.GROUP_STATUS_ICON_STYLE_VALUES = {
    "BLIZZARD", "CLASSIC", "MIDNIGHT", "UXPRO", "GLOSSY_ORBS", "DARK_EMBOSS",
    "GLASS_PANELS", "NEON_OUTLINE", "RING_SYMBOLS", "DOTS", "SHAPES", "DIAMONDS", "SQUARES",
}
A.GroupFramesRegistryData.GROUP_STATUS_ICON_PACK_VALUES = {
    "DEFAULT", "BLIZZARD", "CLASSIC", "MIDNIGHT", "UXPRO", "GLOSSY_ORBS", "DARK_EMBOSS",
    "GLASS_PANELS", "NEON_OUTLINE", "RING_SYMBOLS", "DOTS", "SHAPES", "DIAMONDS", "SQUARES",
}
A.GroupFramesRegistryData.GROUP_STATUS_ANCHOR_VALUES = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT" }

A.GroupFramesRegistryData.GROUP_REVERSE_FILL_BOOLEAN_ALIASES = {
    ["right to left"] = true,
    ["fill right to left"] = true,
    ["fill backwards"] = true,
    ["fill backward"] = true,
    ["fills backwards"] = true,
    ["fills backward"] = true,
    ["reverse fill"] = true,
    ["reverse direction"] = true,
    ["fill reverse"] = true,
    ["fill reversed"] = true,
    ["other way"] = true,
    ["left to right"] = false,
    ["fill left to right"] = false,
    ["fill left"] = false,
    ["normal direction"] = false,
    ["normal fill"] = false,
    ["fill normal"] = false,
    ["forward fill"] = false,
    ["fill forward"] = false,
    ["same direction"] = false,
}

A.GroupFramesRegistryData.GROUP_TEXT_MODE_ALIASES = {
    none = "NONE",
    off = "NONE",
    hide = "NONE",
    hidden = "NONE",
    percent = "PERCENT",
    percentage = "PERCENT",
    pct = "PERCENT",
    current = "CURRENT",
    cur = "CURRENT",
    value = "CURRENT",
    max = "MAX",
    maximum = "MAX",
    deficit = "DEFICIT",
    missing = "DEFICIT",
    curmax = "CURMAX",
    currentmax = "CURMAX",
    ["current max"] = "CURMAX",
    curpercent = "CURPERCENT",
    currentpercent = "CURPERCENT",
    ["current percent"] = "CURPERCENT",
    curmaxpercent = "CURMAXPERCENT",
    ["current max percent"] = "CURMAXPERCENT",
    maxpercent = "MAXPERCENT",
    ["max percent"] = "MAXPERCENT",
    percentcur = "PERCENTCUR",
    ["percent current"] = "PERCENTCUR",
    percentmax = "PERCENTMAX",
    ["percent max"] = "PERCENTMAX",
    percentcurmax = "PERCENTCURMAX",
    ["percent current max"] = "PERCENTCURMAX",
}

A.GroupFramesRegistryData.GROUP_DELIMITER_ALIASES = {
    space = " ",
    single = " ",
    doublespace = "  ",
    ["double space"] = "  ",
    slash = " / ",
    forwardslash = " / ",
    ["forward slash"] = " / ",
    hyphen = " - ",
    dash = " - ",
    minus = " - ",
    colon = " : ",
    pipe = " | ",
    verticalbar = " | ",
    ["vertical bar"] = " | ",
}

A.GroupFramesRegistryData.GROUP_ANCHOR_ALIASES = {
    topleft = "TOPLEFT",
    ["top left"] = "TOPLEFT",
    top = "TOP",
    topcenter = "TOP",
    ["top center"] = "TOP",
    ["top centre"] = "TOP",
    topright = "TOPRIGHT",
    ["top right"] = "TOPRIGHT",
    left = "LEFT",
    center = "CENTER",
    centre = "CENTER",
    middle = "CENTER",
    right = "RIGHT",
}

A.GroupFramesRegistryData.GROUP_CORNER_ANCHOR_ALIASES = {
    topleft = "TOPLEFT",
    ["top left"] = "TOPLEFT",
    top = "TOPLEFT",
    topright = "TOPRIGHT",
    ["top right"] = "TOPRIGHT",
    bottomleft = "BOTTOMLEFT",
    ["bottom left"] = "BOTTOMLEFT",
    bottom = "BOTTOMRIGHT",
    bottomright = "BOTTOMRIGHT",
    ["bottom right"] = "BOTTOMRIGHT",
}

A.GroupFramesRegistryData.GROUP_STATUS_ANCHOR_ALIASES = {
    topleft = "TOPLEFT",
    ["top left"] = "TOPLEFT",
    topright = "TOPRIGHT",
    ["top right"] = "TOPRIGHT",
    bottomleft = "BOTTOMLEFT",
    ["bottom left"] = "BOTTOMLEFT",
    bottomright = "BOTTOMRIGHT",
    ["bottom right"] = "BOTTOMRIGHT",
    center = "CENTER",
    centre = "CENTER",
    middle = "CENTER",
    top = "TOP",
    bottom = "BOTTOM",
    left = "LEFT",
    right = "RIGHT",
}

A.GroupFramesRegistryData.GROUP_STATUS_ICON_STYLE_ALIASES = {
    blizzard = "BLIZZARD",
    default = "BLIZZARD",
    classic = "CLASSIC",
    old = "CLASSIC",
    midnight = "MIDNIGHT",
    msuf = "MIDNIGHT",
    ux = "UXPRO",
    uxpro = "UXPRO",
    ["ux pro"] = "UXPRO",
    glossy = "GLOSSY_ORBS",
    ["glossy orbs"] = "GLOSSY_ORBS",
    dark = "DARK_EMBOSS",
    ["dark emboss"] = "DARK_EMBOSS",
    glass = "GLASS_PANELS",
    ["glass panels"] = "GLASS_PANELS",
    neon = "NEON_OUTLINE",
    ["neon outline"] = "NEON_OUTLINE",
    ring = "RING_SYMBOLS",
    ["ring symbols"] = "RING_SYMBOLS",
    dots = "DOTS",
    shapes = "SHAPES",
    diamonds = "DIAMONDS",
    squares = "SQUARES",
}

A.GroupFramesRegistryData.GROUP_STATUS_ICON_PACK_ALIASES = {
    inherit = "DEFAULT",
    global = "DEFAULT",
    default = "DEFAULT",
    ["follow global"] = "DEFAULT",
    blizzard = "BLIZZARD",
    classic = "CLASSIC",
    old = "CLASSIC",
    midnight = "MIDNIGHT",
    msuf = "MIDNIGHT",
    ux = "UXPRO",
    uxpro = "UXPRO",
    ["ux pro"] = "UXPRO",
    glossy = "GLOSSY_ORBS",
    ["glossy orbs"] = "GLOSSY_ORBS",
    dark = "DARK_EMBOSS",
    ["dark emboss"] = "DARK_EMBOSS",
    glass = "GLASS_PANELS",
    ["glass panels"] = "GLASS_PANELS",
    neon = "NEON_OUTLINE",
    ["neon outline"] = "NEON_OUTLINE",
    ring = "RING_SYMBOLS",
    ["ring symbols"] = "RING_SYMBOLS",
    dots = "DOTS",
    shapes = "SHAPES",
    diamonds = "DIAMONDS",
    squares = "SQUARES",
}
