-- Assistant ClassPower Player HP static values.
-- Loaded after MSUF_AssistantRegistry_ClassPower_Data.lua; consumers read A.ClassPowerRegistryData.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Data = A.ClassPowerRegistryData or {}
A.ClassPowerRegistryData = Data

Data.PLAYER_HP_ANCHOR_ALIASES = {
    classtop = "CLASS_TOP",
    classabove = "CLASS_TOP",
    aboveclass = "CLASS_TOP",
    aboveclassresource = "CLASS_TOP",
    classbottom = "CLASS_BOTTOM",
    classbelow = "CLASS_BOTTOM",
    belowclass = "CLASS_BOTTOM",
    belowclassresource = "CLASS_BOTTOM",
    powertop = "POWER_TOP",
    abovePower = "POWER_TOP",
    abovepower = "POWER_TOP",
    aboveplayerpower = "POWER_TOP",
    powerbottom = "POWER_BOTTOM",
    belowpower = "POWER_BOTTOM",
    belowplayerpower = "POWER_BOTTOM",
    underpower = "POWER_BOTTOM",
}

Data.PLAYER_HP_WIDTH_MODE_ALIASES = {
    class = "class",
    classresource = "class",
    classresources = "class",
    power = "power",
    playerpower = "power",
    detachedpower = "power",
    player = "player",
    playerframe = "player",
    unitframe = "player",
    custom = "custom",
    manual = "custom",
}

Data.PLAYER_HP_SHAPE_ALIASES = {
    bar = "BAR",
    classic = "BAR",
    default = "BAR",
    follow = "FOLLOW_POWER",
    followpower = "FOLLOW_POWER",
    followplayerpower = "FOLLOW_POWER",
    ["follow player power"] = "FOLLOW_POWER",
    power = "FOLLOW_POWER",
    powershape = "FOLLOW_POWER",
    ["power shape"] = "FOLLOW_POWER",
    round = "ROUND",
    circle = "ROUND",
    circular = "ROUND",
    dot = "ROUND",
    dots = "ROUND",
    crystal = "CRYSTAL",
    diamond = "CRYSTAL",
    gem = "CRYSTAL",
    gems = "CRYSTAL",
    orb = "ORB",
    sphere = "ORB",
    kugel = "ORB",
}

Data.PLAYER_HP_COLOR_MODE_ALIASES = {
    global = "GLOBAL",
    inherit = "GLOBAL",
    inherited = "GLOBAL",
    followglobal = "GLOBAL",
    class = "CLASS",
    classcolor = "CLASS",
    ["class color"] = "CLASS",
    classcolour = "CLASS",
    ["class colour"] = "CLASS",
    klassenfarbe = "CLASS",
    dark = "DARK",
    darkmode = "DARK",
    ["dark mode"] = "DARK",
    black = "DARK",
    gradient = "GRADIENT",
    hpgradient = "GRADIENT",
    healthgradient = "GRADIENT",
    ["hp gradient"] = "GRADIENT",
    ["health gradient"] = "GRADIENT",
}

Data.PLAYER_HP_TEXT_MODE_ALIASES = {
    none = "NONE",
    off = "NONE",
    percent = "PERCENT",
    percentage = "PERCENT",
    current = "CURRENT",
    cur = "CURRENT",
    max = "MAX",
    maximum = "MAX",
    deficit = "DEFICIT",
    missing = "DEFICIT",
    curmax = "CURMAX",
    currentmax = "CURMAX",
    currentmaximum = "CURMAX",
    currentpercent = "CURPERCENT",
    curpercent = "CURPERCENT",
    currentpercentage = "CURPERCENT",
    currentmaxpercent = "CURMAXPERCENT",
    curmaxpercent = "CURMAXPERCENT",
    maxpercent = "MAXPERCENT",
    percentcurrent = "PERCENTCUR",
    percentcur = "PERCENTCUR",
    percentmax = "PERCENTMAX",
    percentcurrentmax = "PERCENTCURMAX",
}

Data.PLAYER_HP_TEXT_MODES = {
    "PERCENT", "CURRENT", "MAX", "DEFICIT", "CURMAX", "CURPERCENT",
    "CURMAXPERCENT", "MAXPERCENT", "PERCENTCUR", "PERCENTMAX",
    "PERCENTCURMAX", "NONE",
}
