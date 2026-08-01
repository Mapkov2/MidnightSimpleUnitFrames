-- Assistant UnitFrame text and power value data.
-- Loaded after MSUF_AssistantRegistry_Unitframes_Data.lua so the shared data table exists.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Data = A.UnitframeRegistryData or {}
A.UnitframeRegistryData = Data

Data.TEXT_ANCHOR_VALUES = {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "FRAMELEFT", "FRAMECENTER", "FRAMERIGHT",
}
Data.HP_MODE_VALUES = {
    "PERCENT", "CURRENT", "MAX", "DEFICIT",
    "CURMAX", "CURPERCENT", "CURMAXPERCENT", "MAXPERCENT",
    "PERCENTCUR", "PERCENTMAX", "PERCENTCURMAX", "NONE",
}
Data.HP_MODE_ALIASES = {
    percent = "PERCENT",
    ["percent only"] = "PERCENT",
    current = "CURRENT",
    value = "CURRENT",
    max = "MAX",
    maximum = "MAX",
    deficit = "DEFICIT",
    missing = "DEFICIT",
    ["current max"] = "CURMAX",
    ["current / max"] = "CURMAX",
    ["current and max"] = "CURMAX",
    ["current percent"] = "CURPERCENT",
    ["current / percent"] = "CURPERCENT",
    ["current and percent"] = "CURPERCENT",
    ["current max percent"] = "CURMAXPERCENT",
    ["current / max / percent"] = "CURMAXPERCENT",
    ["max percent"] = "MAXPERCENT",
    ["max / percent"] = "MAXPERCENT",
    ["percent current"] = "PERCENTCUR",
    ["percent / current"] = "PERCENTCUR",
    ["percent max"] = "PERCENTMAX",
    ["percent / max"] = "PERCENTMAX",
    ["percent current max"] = "PERCENTCURMAX",
    ["percent / current / max"] = "PERCENTCURMAX",
    none = "NONE",
    off = "NONE",
    hidden = "NONE",
    -- How players actually name these two modes. "Show percentages instead of
    -- numbers" and "put the health number in the middle" both failed purely
    -- because "percentage" and "number" were not spelled out here.
    percentage = "PERCENT",
    percentages = "PERCENT",
    prozent = "PERCENT",
    prozentzahl = "PERCENT",
    prozentwert = "PERCENT",
    number = "CURRENT",
    numbers = "CURRENT",
    ["actual value"] = "CURRENT",
    absolute = "CURRENT",
    zahl = "CURRENT",
    zahlen = "CURRENT",
    wert = "CURRENT",
}
Data.POWER_MODE_VALUES = { "CURRENT", "MAX", "CURMAX", "PERCENT", "CURPERCENT", "CURMAXPERCENT", "NONE" }
Data.POWER_MODE_ALIASES = {
    current = "CURRENT",
    value = "CURRENT",
    max = "MAX",
    maximum = "MAX",
    ["current max"] = "CURMAX",
    ["current / max"] = "CURMAX",
    ["current and max"] = "CURMAX",
    percent = "PERCENT",
    ["percent only"] = "PERCENT",
    ["current percent"] = "CURPERCENT",
    ["current / percent"] = "CURPERCENT",
    ["current and percent"] = "CURPERCENT",
    ["current max percent"] = "CURMAXPERCENT",
    ["current / max / percent"] = "CURMAXPERCENT",
    none = "NONE",
    off = "NONE",
    hidden = "NONE",
}
Data.SEPARATOR_VALUES = { "", "-", "/", "\\", "|", "<", ">", "~", ":" }
Data.SEPARATOR_ALIASES = {
    space = "",
    blank = "",
    none = "",
    empty = "",
    dash = "-",
    hyphen = "-",
    minus = "-",
    slash = "/",
    ["forward slash"] = "/",
    backslash = "\\",
    pipe = "|",
    bar = "|",
    less = "<",
    ["less than"] = "<",
    greater = ">",
    ["greater than"] = ">",
    tilde = "~",
    colon = ":",
}
Data.DETACHED_POWER_SHAPE_VALUES = { "FOLLOW_CLASS", "BAR", "ROUND", "CRYSTAL", "ORB" }
Data.DETACHED_POWER_SHAPE_ALIASES = {
    follow = "FOLLOW_CLASS",
    followclass = "FOLLOW_CLASS",
    followclassresource = "FOLLOW_CLASS",
    class = "FOLLOW_CLASS",
    classresource = "FOLLOW_CLASS",
    auto = "FOLLOW_CLASS",
    automatic = "FOLLOW_CLASS",
    bar = "BAR",
    bars = "BAR",
    rectangle = "BAR",
    rectangular = "BAR",
    round = "ROUND",
    rounded = "ROUND",
    circle = "ROUND",
    circular = "ROUND",
    orb = "ORB",
    orbs = "ORB",
    sphere = "ORB",
    ball = "ORB",
    manaball = "ORB",
    manaorb = "ORB",
    powerball = "ORB",
    powerorb = "ORB",
    powersphere = "ORB",
    crystal = "CRYSTAL",
    crystals = "CRYSTAL",
    diamond = "CRYSTAL",
    diamonds = "CRYSTAL",
    gem = "CRYSTAL",
    hex = "CRYSTAL",
    hexagon = "CRYSTAL",
}
