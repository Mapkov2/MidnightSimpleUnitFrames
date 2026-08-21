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
Data.AURA_SCOPES = { "player", "target", "focus", "boss" }
Data.AURA_LANES = {
    { key = "buff", label = "Buff", plural = "Buffs" },
    { key = "debuff", label = "Debuff", plural = "Debuffs" },
}
Data.GF_AURA_GROUPS = { "party", "raid", "mythicraid" }
Data.GF_AURA_CATEGORY_SCOPES = { "party", "raid" }
Data.GF_AURA_ANCHORS = { "CENTER", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
Data.GF_AURA_GROWTH = { "RIGHTDOWN", "LEFTDOWN", "RIGHTUP", "LEFTUP", "UP", "DOWN" }
Data.GF_AURA_FILTER_VALUES = {
    buff = {
        "ALL", "Player", "BigDefensive", "BigDefensivePlayer", "ExternalDefensive",
        "ExternalDefensivePlayer", "RaidInCombat", "Raid", "RaidPlayer",
    },
    debuff = {
        "ALL", "Player", "Raid", "RaidInCombat", "RAID_PLAYER_DISPELLABLE",
        "DISPELLABLE", "CROWD_CONTROL", "NonPlayer",
    },
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
    player = "Player",
    mine = "Player",
    ["my buff"] = "Player",
    ["my buffs"] = "Player",
    ["my buffs only"] = "Player",
    ["my debuff"] = "Player",
    ["my debuffs"] = "Player",
    ["my debuffs only"] = "Player",
    ["my auras"] = "Player",
    ["player only"] = "Player",
    ["mine only"] = "Player",
    ["own only"] = "Player",
    raid = "Raid",
    ["raid buffs"] = "Raid",
    ["raid buffs only"] = "Raid",
    ["raid debuffs"] = "Raid",
    ["raid debuffs only"] = "Raid",
    boss = "Raid",
    encounter = "Raid",
    ["boss debuffs"] = "Raid",
    ["encounter debuffs"] = "Raid",
    ["player raid"] = "RaidPlayer",
    ["raid player"] = "RaidPlayer",
    ["my raid"] = "RaidPlayer",
    ["my raid buffs"] = "RaidPlayer",
    ["my raid debuffs"] = "RaidPlayer",
    ["raid combat"] = "RaidInCombat",
    ["raid in combat"] = "RaidInCombat",
    ["raid in combat only"] = "RaidInCombat",
    ["combat raid"] = "RaidInCombat",
    ["player raid combat"] = "RaidInCombatPlayer",
    ["player raid in combat"] = "RaidInCombatPlayer",
    ["my raid in combat"] = "RaidInCombatPlayer",
    nameplate = "INCLUDE_NAME_PLATE_ONLY",
    ["nameplate only"] = "INCLUDE_NAME_PLATE_ONLY",
    ["nameplate-only"] = "INCLUDE_NAME_PLATE_ONLY",
    ["nameplate auras"] = "INCLUDE_NAME_PLATE_ONLY",
    ["nameplate buffs"] = "INCLUDE_NAME_PLATE_ONLY",
    ["nameplate debuffs"] = "INCLUDE_NAME_PLATE_ONLY",
    ["include nameplate"] = "INCLUDE_NAME_PLATE_ONLY",
    ["include nameplate only"] = "INCLUDE_NAME_PLATE_ONLY",
    ["include nameplate-only"] = "INCLUDE_NAME_PLATE_ONLY",
    cancelable = "Cancelable",
    cancellable = "Cancelable",
    ["cancelable buffs"] = "Cancelable",
    ["cancellable buffs"] = "Cancelable",
    ["only cancelable"] = "Cancelable",
    ["only cancellable"] = "Cancelable",
    ["only cancelable buffs"] = "Cancelable",
    ["only cancellable buffs"] = "Cancelable",
    ["my cancelable"] = "CancelablePlayer",
    ["my cancelable buffs"] = "CancelablePlayer",
    ["player cancelable"] = "CancelablePlayer",
    ["player cancelable buffs"] = "CancelablePlayer",
    ["not cancelable"] = "NotCancelable",
    ["not cancellable"] = "NotCancelable",
    ["non cancelable"] = "NotCancelable",
    ["non cancellable"] = "NotCancelable",
    uncancelable = "NotCancelable",
    uncancellable = "NotCancelable",
    ["not cancelable buffs"] = "NotCancelable",
    ["not cancellable buffs"] = "NotCancelable",
    ["non cancelable buffs"] = "NotCancelable",
    ["non cancellable buffs"] = "NotCancelable",
    ["uncancelable buffs"] = "NotCancelable",
    ["uncancellable buffs"] = "NotCancelable",
    ["my not cancelable"] = "NotCancelablePlayer",
    ["my not cancelable buffs"] = "NotCancelablePlayer",
    ["player not cancelable"] = "NotCancelablePlayer",
    dispellable = "RAID_PLAYER_DISPELLABLE",
    ["dispellable debuffs"] = "RAID_PLAYER_DISPELLABLE",
    ["dispellable debuffs only"] = "RAID_PLAYER_DISPELLABLE",
    ["only dispellable"] = "RAID_PLAYER_DISPELLABLE",
    ["only dispellable debuffs"] = "RAID_PLAYER_DISPELLABLE",
    purgeable = "RAID_PLAYER_DISPELLABLE",
    ["purgeable debuffs"] = "RAID_PLAYER_DISPELLABLE",
    ["player dispellable"] = "Raid",
    ["dispellable by me"] = "Raid",
    ["dispelable by me"] = "Raid",
    ["dispellable by group"] = "RAID_PLAYER_DISPELLABLE",
    ["dispelable by group"] = "RAID_PLAYER_DISPELLABLE",
    ["group dispellable"] = "RAID_PLAYER_DISPELLABLE",
    ["any dispel type"] = "DISPELLABLE",
    ["all dispel types"] = "DISPELLABLE",
    ["dispellable regardless of group"] = "DISPELLABLE",
    important = "IMPORTANT",
    ["important aura"] = "IMPORTANT",
    ["important auras"] = "IMPORTANT",
    ["important buffs"] = "IMPORTANT",
    ["important debuffs"] = "IMPORTANT",
    cc = "CROWD_CONTROL",
    ["cc debuffs"] = "CROWD_CONTROL",
    ["cc debuffs only"] = "CROWD_CONTROL",
    ["crowd control"] = "CROWD_CONTROL",
    ["crowd control debuffs"] = "CROWD_CONTROL",
    ["non-player"] = "NonPlayer",
    ["non-player aura"] = "NonPlayer",
    ["non-player auras"] = "NonPlayer",
    ["non-player debuff"] = "NonPlayer",
    ["non-player debuffs"] = "NonPlayer",
    ["not from a player"] = "NonPlayer",
    ["not caused by a player"] = "NonPlayer",
    external = "ExternalDefensive",
    externals = "ExternalDefensive",
    ["external defensive"] = "ExternalDefensive",
    ["external defensives"] = "ExternalDefensive",
    ["external buffs"] = "ExternalDefensive",
    ["my external"] = "ExternalDefensivePlayer",
    ["my externals"] = "ExternalDefensivePlayer",
    ["my external defensive"] = "ExternalDefensivePlayer",
    ["player external defensive"] = "ExternalDefensivePlayer",
    defensive = "BigDefensive",
    defensives = "BigDefensive",
    ["big defensive"] = "BigDefensive",
    ["big defensives"] = "BigDefensive",
    ["major defensive"] = "BigDefensive",
    ["major defensives"] = "BigDefensive",
    ["defensive buffs"] = "BigDefensive",
    ["my defensive"] = "BigDefensivePlayer",
    ["my defensives"] = "BigDefensivePlayer",
    ["my big defensive"] = "BigDefensivePlayer",
    ["my major defensive"] = "BigDefensivePlayer",
}
Data.AURA_SCOPE_ALIASES = {}

Data.AURA_EDIT_SCOPES = { "player", "target", "focus", "boss", "party", "raid" }
Data.AURA_EDIT_SCOPE_VALUES = { "player", "target", "focus", "boss", "party", "raid" }
Data.AURA_EDIT_SCOPE_ALIASES = {
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
