-- Assistant Auras registry static values.
-- Loaded before MSUF_AssistantRegistry_Auras.lua; this file only holds cold lookup
-- metadata for native 12.1 aura container settings.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Data = A.AurasRegistryData or {}
A.AurasRegistryData = Data

Data.AURA_UNITS = { "player", "target", "focus", "boss" }
Data.AURA_SCOPES = { "shared", "player", "target", "focus", "boss" }
Data.AURA_LANES = {
    { key = "buff", label = "Buff", plural = "Buffs" },
    { key = "debuff", label = "Debuff", plural = "Debuffs" },
}
Data.GF_AURA_GROUPS = { "party", "raid", "mythicraid" }
Data.GF_AURA_CATEGORY_SCOPES = { "party", "raid" }
Data.GF_AURA_ANCHORS = { "CENTER", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
Data.GF_AURA_GROWTH = { "RIGHTDOWN", "LEFTDOWN", "RIGHTUP", "LEFTUP" }
Data.GF_AURA_FILTER_VALUES = {
    buff = { "ALL", "PLAYER", "RAID", "RAID_IN_COMBAT", "EXTERNAL_DEFENSIVE", "BIG_DEFENSIVE" },
    debuff = { "ALL", "PLAYER", "RAID", "RAID_IN_COMBAT", "RAID_PLAYER_DISPELLABLE", "CROWD_CONTROL" },
}
Data.GF_AURA_FILTER_ALIASES = {
    all = "ALL",
    ["all auras"] = "ALL",
    ["all buffs"] = "ALL",
    ["all debuffs"] = "ALL",
    everything = "ALL",
    normal = "ALL",
    default = "ALL",
    ["no filter"] = "ALL",
    ["filter off"] = "ALL",
    ["show all"] = "ALL",
    player = "PLAYER",
    mine = "PLAYER",
    ["my buff"] = "PLAYER",
    ["my buffs"] = "PLAYER",
    ["my buffs only"] = "PLAYER",
    ["my debuff"] = "PLAYER",
    ["my debuffs"] = "PLAYER",
    ["my debuffs only"] = "PLAYER",
    ["my auras"] = "PLAYER",
    ["player only"] = "PLAYER",
    ["mine only"] = "PLAYER",
    ["own only"] = "PLAYER",
    raid = "RAID",
    ["raid buffs"] = "RAID",
    ["raid buffs only"] = "RAID",
    ["raid debuffs"] = "RAID",
    ["raid debuffs only"] = "RAID",
    boss = "RAID",
    encounter = "RAID",
    ["boss debuffs"] = "RAID",
    ["encounter debuffs"] = "RAID",
    ["raid combat"] = "RAID_IN_COMBAT",
    ["raid in combat"] = "RAID_IN_COMBAT",
    ["raid in combat only"] = "RAID_IN_COMBAT",
    ["combat raid"] = "RAID_IN_COMBAT",
    dispellable = "RAID_PLAYER_DISPELLABLE",
    ["dispellable debuffs"] = "RAID_PLAYER_DISPELLABLE",
    ["dispellable debuffs only"] = "RAID_PLAYER_DISPELLABLE",
    ["only dispellable"] = "RAID_PLAYER_DISPELLABLE",
    ["only dispellable debuffs"] = "RAID_PLAYER_DISPELLABLE",
    purgeable = "RAID_PLAYER_DISPELLABLE",
    ["purgeable debuffs"] = "RAID_PLAYER_DISPELLABLE",
    ["player dispellable"] = "RAID_PLAYER_DISPELLABLE",
    cc = "CROWD_CONTROL",
    ["cc debuffs"] = "CROWD_CONTROL",
    ["cc debuffs only"] = "CROWD_CONTROL",
    ["crowd control"] = "CROWD_CONTROL",
    ["crowd control debuffs"] = "CROWD_CONTROL",
    external = "EXTERNAL_DEFENSIVE",
    externals = "EXTERNAL_DEFENSIVE",
    ["external defensive"] = "EXTERNAL_DEFENSIVE",
    ["external defensives"] = "EXTERNAL_DEFENSIVE",
    ["external buffs"] = "EXTERNAL_DEFENSIVE",
    defensive = "BIG_DEFENSIVE",
    defensives = "BIG_DEFENSIVE",
    ["big defensive"] = "BIG_DEFENSIVE",
    ["big defensives"] = "BIG_DEFENSIVE",
    ["major defensive"] = "BIG_DEFENSIVE",
    ["major defensives"] = "BIG_DEFENSIVE",
    ["defensive buffs"] = "BIG_DEFENSIVE",
}
Data.AURA_SCOPE_ALIASES = {
    shared = { "shared", "global", "all auras", "all aura", "auras", "aura" },
}

Data.AURA_EDIT_SCOPES = { "shared", "player", "target", "focus", "boss", "party", "raid" }
Data.AURA_EDIT_SCOPE_VALUES = { "shared", "player", "target", "focus", "boss", "party", "raid" }
Data.AURA_EDIT_SCOPE_ALIASES = {
    shared = "shared",
    global = "shared",
    all = "shared",
    player = "player",
    spieler = "player",
    target = "target",
    ziel = "target",
    focus = "focus",
    fokus = "focus",
    boss = "boss",
    boss1 = "boss",
    boss2 = "boss",
    boss3 = "boss",
    boss4 = "boss",
    boss5 = "boss",
    party = "party",
    group = "party",
    gruppe = "party",
    raid = "raid",
    mythicraid = "raid",
    ["mythic raid"] = "raid",
    schlachtzug = "raid",
}

Data.AURA_LANE_MENU_VALUES = { "buff", "debuff" }
Data.AURA_STYLE_LANE_ALIASES = { "aura style lane", "aura style tab", "aura style filter type", "aura buffs tab", "aura debuffs tab", "buff aura style", "debuff aura style" }
Data.AURA_STYLE_LANE_EXACT_ALIASES = { "aura style lane", "aura style tab", "aura buffs tab", "aura debuffs tab" }
Data.AURA_FILTER_LANE_ALIASES = { "aura filter lane", "aura filter tab", "aura filter type", "aura buff filters tab", "aura debuff filters tab", "buff aura filters", "debuff aura filters" }
Data.AURA_FILTER_LANE_EXACT_ALIASES = { "aura filter lane", "aura filter tab", "aura buff filters tab", "aura debuff filters tab" }
Data.AURA_LANE_MENU_ALIASES = {
    buff = "buff",
    buffs = "buff",
    bufftab = "buff",
    ["buff tab"] = "buff",
    debuff = "debuff",
    debuffs = "debuff",
    debufftab = "debuff",
    ["debuff tab"] = "debuff",
}

Data.AURA_UX_MODE_VALUES = { "basic", "advanced" }
Data.AURA_UX_MODE_ALIASES = {
    "aura settings view", "aura view", "aura settings mode", "show aura settings",
    "basic aura settings", "advanced aura settings", "all aura settings",
}
Data.AURA_UX_MODE_EXACT_ALIASES = {
    "aura settings view", "aura view", "aura settings mode", "show aura settings",
    "basic aura settings", "advanced aura settings", "all aura settings",
    "basic aura options", "advanced aura options", "all aura options",
}
Data.AURA_UX_MODE_VALUE_ALIASES = {
    basic = "basic",
    simple = "basic",
    normal = "basic",
    advanced = "advanced",
    all = "advanced",
    allsettings = "advanced",
    ["all settings"] = "advanced",
}

Data.AURA_RELATIVE_SIZE_NOUNS = {
    "bigger", "larger", "smaller", "groesser", "kleiner",
    "icon bigger", "icon larger", "icon smaller", "icon groesser", "icon kleiner",
    "icons bigger", "icons larger", "icons smaller", "icons groesser", "icons kleiner",
    "size bigger", "size larger", "size smaller", "size groesser", "size kleiner",
    "icon size bigger", "icon size larger", "icon size smaller", "icon size groesser", "icon size kleiner",
}
