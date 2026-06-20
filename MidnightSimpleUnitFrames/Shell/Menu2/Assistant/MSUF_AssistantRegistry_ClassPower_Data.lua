-- Assistant ClassPower registry static values.
-- Loaded before MSUF_AssistantRegistry_ClassPower.lua so that behavior stays in the
-- registry module and cold lookup data stays isolated.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Data = A.ClassPowerRegistryData or {}
A.ClassPowerRegistryData = Data

Data.CLASS_POWER_WIDTH_MODE_ALIASES = {
    player = "player",
    frame = "player",
    playerframe = "player",
    playerwidth = "player",
    playerframewidth = "player",
    unitframe = "player",
    unitframewidth = "player",
    cooldown = "cooldown",
    cooldowns = "cooldown",
    essentialcooldown = "cooldown",
    essentialcooldowns = "cooldown",
    essentialcooldownmanager = "cooldown",
    cooldownmanager = "cooldown",
    cooldownsmanager = "cooldown",
    cdmwidth = "cooldown",
    cdm = "cooldown",
    utility = "utility",
    utilitycooldown = "utility",
    utilitycooldowns = "utility",
    utilitycooldownmanager = "utility",
    trackedbuff = "tracked_buffs",
    trackedbuffs = "tracked_buffs",
    bufftracker = "tracked_buffs",
    trackedbuffwidth = "tracked_buffs",
    custom = "custom",
    manual = "custom",
    auto = "auto_pips",
    autofit = "auto_pips",
    autofitpips = "auto_pips",
    fitpips = "auto_pips",
    pips = "auto_pips",
    pipwidth = "auto_pips",
    compact = "auto_pips",
}

Data.CLASS_POWER_SHAPE_ALIASES = {
    bar = "BAR",
    bars = "BAR",
    rectangle = "BAR",
    rectangular = "BAR",
    default = "BAR",
    circle = "CIRCLE",
    circles = "CIRCLE",
    round = "CIRCLE",
    dot = "CIRCLE",
    dots = "CIRCLE",
    orb = "CIRCLE",
    orbs = "CIRCLE",
    diamond = "DIAMOND",
    diamonds = "DIAMOND",
    gem = "DIAMOND",
    gems = "DIAMOND",
    crystal = "DIAMOND",
    hex = "HEX",
    hexagon = "HEX",
    hexagons = "HEX",
}

Data.CLASS_POWER_SHAPE_ALIGN_ALIASES = {
    left = "LEFT",
    start = "LEFT",
    center = "CENTER",
    centred = "CENTER",
    middle = "CENTER",
    right = "RIGHT",
    endside = "RIGHT",
}

Data.COMBO_POINT_COLOR_MODE_ALIASES = {
    default = "default",
    resource = "default",
    resourcecolor = "default",
    ramp = "ramp",
    comboramp = "ramp",
    gradient = "ramp",
    custom = "custom",
    slots = "custom",
}

Data.DETACHED_POWER_WIDTH_MODE_ALIASES = {
    manual = "manual",
    custom = "manual",
    player = "manual",
    cooldown = "cooldown",
    cooldowns = "cooldown",
    essentialcooldown = "cooldown",
    essentialcooldowns = "cooldown",
    cdm = "cooldown",
    utility = "utility",
    utilitycooldown = "utility",
    utilitycooldowns = "utility",
    trackedbuff = "tracked_buffs",
    trackedbuffs = "tracked_buffs",
    bufftracker = "tracked_buffs",
}
