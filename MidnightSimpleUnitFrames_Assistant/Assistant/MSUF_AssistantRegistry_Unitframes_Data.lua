-- Assistant UnitFrame registry static values.
-- Loaded before MSUF_AssistantRegistry_Unitframes.lua to keep the main registry
-- focused on registrations and apply behavior.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Data = A.UnitframeRegistryData or {}
A.UnitframeRegistryData = Data

Data.PORTRAIT_MODE_VALUES = { "OFF", "LEFT", "RIGHT" }
Data.PORTRAIT_RENDER_VALUES = { "2D", "CLASS" }
Data.PORTRAIT_SHAPE_VALUES = { "SQUARE", "CIRCLE", "ROUNDED", "DIAMOND" }
-- Unit frames additionally offer the stock Blizzard ring dressing; group
-- frames keep the four-value list above, so the two surfaces stay honest.
Data.PORTRAIT_SHAPE_VALUES_UNIT = { "SQUARE", "CIRCLE", "ROUNDED", "DIAMOND", "BLIZZARD" }
Data.PORTRAIT_BORDER_VALUES = { "NONE", "SOLID", "CLASS_COLOR", "REACTION", "CUSTOM" }
Data.PORTRAIT_PLACEMENT_VALUES = { "ATTACHED", "DETACHED", "OVERLAY" }
Data.PORTRAIT_ANCHOR_POINT_VALUES = {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}
Data.PORTRAIT_OVERLAY_ALIGN_VALUES = { "LEFT", "CENTER", "RIGHT", "FULL" }
Data.PORTRAIT_BORDER_ART_VALUES = { "FLAT", "RELIEF" }
Data.PORTRAIT_BORDER_DIRECTION_VALUES = { "UP", "RIGHT", "DOWN", "LEFT" }
Data.HEALTH_COLOR_MODE_VALUES = { "GLOBAL", "class", "gradient", "unified", "dark" }
Data.HEALTH_COLOR_MODE_ALIASES = {
    global = "GLOBAL",
    default = "GLOBAL",
    inherit = "GLOBAL",
    inherited = "GLOBAL",
    ["use global"] = "GLOBAL",
    ["follow global"] = "GLOBAL",
    ["global color"] = "GLOBAL",
    ["global scheme"] = "GLOBAL",
    ["global color scheme"] = "GLOBAL",
    class = "class",
    classes = "class",
    ["class color"] = "class",
    ["class colors"] = "class",
    ["class reaction"] = "class",
    ["class / reaction"] = "class",
    reaction = "class",
    gradient = "gradient",
    ["health gradient"] = "gradient",
    ["color gradient"] = "gradient",
    unified = "unified",
    ["unified color"] = "unified",
    ["one color"] = "unified",
    dark = "dark",
    ["dark mode"] = "dark",
    black = "dark",
    klassenfarbe = "class",
    klassenfarben = "class",
    klasse = "class",
    reaktion = "class",
    verlauf = "gradient",
    einheitlich = "unified",
    dunkel = "dark",
    schwarz = "dark",
}
Data.RANGE_LAYER_VALUES = { "frame", "health" }
Data.STATUS_ANCHOR_VALUES = {
    "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT",
    "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT",
    "NAMERIGHT", "NAMELEFT",
}
Data.STATUS_CORNER_ANCHOR_VALUES = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
Data.RAID_GROUP_STYLE_VALUES = { "PAREN", "BRACKET", "NONE" }
Data.STATUS_ANCHOR_ALIASES = {
    topleft = "TOPLEFT",
    ["top left"] = "TOPLEFT",
    upperleft = "TOPLEFT",
    ["upper left"] = "TOPLEFT",
    topright = "TOPRIGHT",
    ["top right"] = "TOPRIGHT",
    upperright = "TOPRIGHT",
    ["upper right"] = "TOPRIGHT",
    bottomleft = "BOTTOMLEFT",
    ["bottom left"] = "BOTTOMLEFT",
    lowerleft = "BOTTOMLEFT",
    ["lower left"] = "BOTTOMLEFT",
    bottomright = "BOTTOMRIGHT",
    ["bottom right"] = "BOTTOMRIGHT",
    lowerright = "BOTTOMRIGHT",
    ["lower right"] = "BOTTOMRIGHT",
    center = "CENTER",
    middle = "CENTER",
    top = "TOP",
    bottom = "BOTTOM",
    left = "LEFT",
    right = "RIGHT",
    nameright = "NAMERIGHT",
    ["name right"] = "NAMERIGHT",
    ["right to name"] = "NAMERIGHT",
    ["right to player name"] = "NAMERIGHT",
    nameleft = "NAMELEFT",
    ["name left"] = "NAMELEFT",
    ["left to name"] = "NAMELEFT",
    ["left to player name"] = "NAMELEFT",
}
Data.BOSS_LAYOUT_VALUES = { "VERTICAL_DOWN", "VERTICAL_UP", "HORIZONTAL_RIGHT", "HORIZONTAL_LEFT" }
Data.BOSS_LAYOUT_ALIASES = {
    ["vertical down"] = "VERTICAL_DOWN",
    down = "VERTICAL_DOWN",
    default = "VERTICAL_DOWN",
    ["top to bottom"] = "VERTICAL_DOWN",
    ["vertical up"] = "VERTICAL_UP",
    up = "VERTICAL_UP",
    ["bottom to top"] = "VERTICAL_UP",
    ["horizontal right"] = "HORIZONTAL_RIGHT",
    right = "HORIZONTAL_RIGHT",
    ["left to right"] = "HORIZONTAL_RIGHT",
    ["horizontal left"] = "HORIZONTAL_LEFT",
    left = "HORIZONTAL_LEFT",
    ["right to left"] = "HORIZONTAL_LEFT",
}
Data.RAID_GROUP_STYLE_ALIASES = {
    paren = "PAREN",
    parentheses = "PAREN",
    brackets = "BRACKET",
    bracket = "BRACKET",
    none = "NONE",
    plain = "NONE",
}
Data.TOT_INLINE_COLOR_VALUES = { "AUTO", "TOT_NAME", "TARGET_NAME", "NPC", "DEFAULT" }
Data.TOT_INLINE_COLOR_ALIASES = {
    auto = "AUTO",
    automatic = "AUTO",
    ["tot name"] = "TOT_NAME",
    ["target of target name"] = "TOT_NAME",
    ["target name"] = "TARGET_NAME",
    npc = "NPC",
    ["npc type"] = "NPC",
    type = "NPC",
    default = "DEFAULT",
    font = "DEFAULT",
    ["font color"] = "DEFAULT",
}
Data.TOT_INLINE_SEPARATOR_CUSTOM = "__CUSTOM__"
Data.LOAD_CONDITION_SPECS = {
    { key = "loadCondHideInHousing", label = "Hide in Housing", aliases = { "hide in housing", "housing load condition" } },
    { key = "loadCondHideInCombat", label = "Hide in Combat", aliases = { "hide in combat", "combat load condition" } },
    { key = "loadCondHideInGroup", label = "Hide in Group", aliases = { "hide in group", "group load condition" } },
    { key = "loadCondHideInInstance", label = "Hide in Instance", aliases = { "hide in instance", "instance load condition" } },
    { key = "loadCondHideInVehicle", label = "Hide in Vehicle", aliases = { "hide in vehicle", "vehicle load condition" } },
    { key = "loadCondHideMounted", label = "Hide Mounted", aliases = { "hide mounted", "mounted load condition" } },
    { key = "loadCondHideNoTarget", label = "Hide with No Target", aliases = { "hide with no target", "no target load condition" } },
    { key = "loadCondHideOutOfCombat", label = "Hide Out of Combat", aliases = { "hide out of combat", "out of combat load condition" } },
    { key = "loadCondHideOutOfCombatNoTarget", label = "Hide Out of Combat with No Target", aliases = { "hide out of combat with no target", "target or combat load condition" } },
    { key = "loadCondHideResting", label = "Hide Resting", aliases = { "hide resting", "resting load condition" } },
    { key = "loadCondHideSolo", label = "Hide Solo", aliases = { "hide solo", "solo load condition" } },
    { key = "loadCondHideStealthed", label = "Hide Stealthed", aliases = { "hide stealthed", "stealth load condition" } },
}
Data.STATUS_TEXT_STATE_SPECS = {
    {
        key = "showDead",
        attribute = "statusTextDead",
        label = "Dead Text Shows Dead Units",
        default = true,
        aliases = { "dead text dead units", "status text dead units", "show dead text for dead" },
    },
    {
        key = "showGhost",
        attribute = "statusTextGhost",
        label = "Dead Text Shows Ghost Units",
        default = true,
        aliases = { "dead text ghost units", "status text ghost units", "show ghost text" },
    },
    {
        key = "showAFK",
        attribute = "statusTextAFK",
        label = "Dead Text Shows AFK Units",
        default = false,
        aliases = { "dead text afk", "status text afk", "show afk text", "afk text", "afk indicator", "afk status indicator" },
    },
    {
        key = "showDND",
        attribute = "statusTextDND",
        label = "Dead Text Shows DND Units",
        default = false,
        aliases = { "dead text dnd", "status text dnd", "show dnd text", "dnd text", "dnd indicator", "dnd status indicator" },
    },
}
