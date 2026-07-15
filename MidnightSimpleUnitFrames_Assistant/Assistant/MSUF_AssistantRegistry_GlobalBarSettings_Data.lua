-- Assistant Global Bar registry static values and normalizers.
-- Loaded before the GlobalBarSettings installers; runtime bar refresh paths do not depend on this file.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalBarRegistry = A.GlobalBarRegistry or {}

local Data = A.GlobalBarRegistry.Data or {}
A.GlobalBarRegistry.Data = Data

Data.GRADIENT_DIRECTION_VALUES = { "RIGHT", "LEFT", "UP", "DOWN" }
Data.GRADIENT_DIRECTION_KEYS = {
    RIGHT = "gradientDirRight",
    LEFT = "gradientDirLeft",
    UP = "gradientDirUp",
    DOWN = "gradientDirDown",
}
Data.GRADIENT_DIRECTION_ALIASES = {
    right = "RIGHT",
    left = "LEFT",
    up = "UP",
    down = "DOWN",
    ["from right"] = "RIGHT",
    ["to right"] = "RIGHT",
    ["from left"] = "LEFT",
    ["to left"] = "LEFT",
    ["from top"] = "UP",
    ["to top"] = "UP",
    top = "UP",
    ["from bottom"] = "DOWN",
    ["to bottom"] = "DOWN",
    bottom = "DOWN",
    horizontalright = "RIGHT",
    horizontalleft = "LEFT",
    verticalup = "UP",
    verticaldown = "DOWN",
}
Data.OUTLINE_STRATA_VALUES = {
    "AUTO", "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG",
    "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP",
}
Data.OUTLINE_STRATA_ALIASES = {
    auto = "AUTO",
    frame = "AUTO",
    ["auto frame"] = "AUTO",
    background = "BACKGROUND",
    low = "LOW",
    medium = "MEDIUM",
    high = "HIGH",
    dialog = "DIALOG",
    fullscreen = "FULLSCREEN",
    ["full screen"] = "FULLSCREEN",
    fullscreen_dialog = "FULLSCREEN_DIALOG",
    ["fullscreen dialog"] = "FULLSCREEN_DIALOG",
    ["full screen dialog"] = "FULLSCREEN_DIALOG",
    tooltip = "TOOLTIP",
}
Data.ON_OFF_STORAGE = { off = 0, on = 1 }
Data.ON_OFF_VALUES = { "off", "on" }
Data.ON_OFF_ALIASES = { off = "off", disabled = "off", hide = "off", on = "on", enabled = "on", show = "on" }
Data.AGGRO_MODE_VALUES = { "ALL", "NON_TANK", "HEALER", "TANK" }
Data.AGGRO_MODE_ALIASES = {
    all = "ALL",
    everyone = "ALL",
    ["all roles"] = "ALL",
    nontank = "NON_TANK",
    ["non tank"] = "NON_TANK",
    ["non tanks"] = "NON_TANK",
    ["not tank"] = "NON_TANK",
    ["non-tank"] = "NON_TANK",
    ["non-tanks"] = "NON_TANK",
    healer = "HEALER",
    healers = "HEALER",
    ["healers only"] = "HEALER",
    tank = "TANK",
    tanks = "TANK",
    ["tanks only"] = "TANK",
}
Data.ABSORB_MODE_STORAGE = { off = 1, bar = 2 }
Data.ABSORB_MODE_VALUES = { "off", "bar" }
Data.ABSORB_MODE_ALIASES = { off = "off", disabled = "off", none = "off", bar = "bar", enabled = "bar", on = "bar" }
Data.ABSORB_ANCHOR_STORAGE = { left = 1, right = 2, follow = 3, overflow = 4, reverse = 5 }
Data.ABSORB_ANCHOR_VALUES = { "left", "right", "follow", "overflow", "reverse" }
Data.ABSORB_ANCHOR_ALIASES = {
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
Data.DISPEL_TRIGGER_VALUES = { "BY_ME", "BY_RAID", "DISPEL_TYPE" }
Data.DISPEL_TRIGGER_ALIASES = {
    byme = "BY_ME",
    ["by me"] = "BY_ME",
    dispellable = "BY_ME",
    mine = "BY_ME",
    byraid = "BY_RAID",
    ["by raid"] = "BY_RAID",
    ["by group"] = "BY_RAID",
    ["dispellable by group"] = "BY_RAID",
    type = "DISPEL_TYPE",
    dispeltype = "DISPEL_TYPE",
    ["dispel type"] = "DISPEL_TYPE",
    any = "DISPEL_TYPE",
    anytype = "DISPEL_TYPE",
    ["any dispel type"] = "DISPEL_TYPE",
    anydebuff = "DISPEL_TYPE",
    ["any debuff"] = "DISPEL_TYPE",
    alldebuffs = "DISPEL_TYPE",
}
Data.UNIT_DISPEL_TRIGGER_VALUES = { "BORDER", "BY_ME", "BY_RAID", "DISPEL_TYPE" }
Data.UNIT_DISPEL_TRIGGER_ALIASES = {
    border = "BORDER",
    same = "BORDER",
    inherit = "BORDER",
    ["same as border"] = "BORDER",
    byme = "BY_ME",
    ["by me"] = "BY_ME",
    dispellable = "BY_ME",
    byraid = "BY_RAID",
    ["by raid"] = "BY_RAID",
    ["by group"] = "BY_RAID",
    ["dispellable by group"] = "BY_RAID",
    type = "DISPEL_TYPE",
    dispeltype = "DISPEL_TYPE",
    ["dispel type"] = "DISPEL_TYPE",
    any = "DISPEL_TYPE",
    ["any dispel type"] = "DISPEL_TYPE",
    anydebuff = "DISPEL_TYPE",
    ["any debuff"] = "DISPEL_TYPE",
}
Data.UNIT_DISPEL_STYLE_VALUES = { "FULL", "TOP", "BOTTOM", "LEFT", "RIGHT" }
Data.UNIT_DISPEL_STYLE_ALIASES = {
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
Data.TEXTURE_KEY_ALIASES = TEXTURE_KEY_ALIASES

function Data.NormalizeTextureKeyForAssistant(value)
    value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then return "" end
    local lower = value:lower():gsub("%s+", " ")
    return TEXTURE_KEY_ALIASES[lower] or TEXTURE_KEY_ALIASES[lower:gsub("%s+", "")] or value
end
