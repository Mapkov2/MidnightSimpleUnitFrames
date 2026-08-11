-- Assistant UnitFrame status icon pack and symbol values.
-- Loaded after MSUF_AssistantRegistry_Unitframes_Data.lua so shared data table exists.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Data = A.UnitframeRegistryData or {}
A.UnitframeRegistryData = Data

Data.STATUS_ICON_PACK_FALLBACK_VALUES = {
    "BLIZZARD", "CLASSIC", "MIDNIGHT", "UXPRO", "GLOSSY_ORBS",
    "DARK_EMBOSS", "GLASS_PANELS", "NEON_OUTLINE", "RING_SYMBOLS",
    "DOTS", "SHAPES", "DIAMONDS", "SQUARES",
}
Data.COMBAT_SYMBOL_VALUES = {
    "DEFAULT", "weapon_axes_crossed", "weapon_bows_crossed",
    "weapon_crossbows_crossed", "weapon_daggers_crossed",
    "weapon_fishing_poles_crossed", "weapon_fist_crossed",
    "weapon_guns_crossed", "weapon_maces_crossed",
    "weapon_polearms_crossed", "weapon_shuriken",
    "weapon_staves_crossed", "weapon_swords_crossed",
    "weapon_thrown_crossed", "weapon_wands_crossed",
    "weapon_warglaives_crossed",
}
Data.RESTED_SYMBOL_VALUES = {
    "DEFAULT", "rested_blizzard_animated", "rested_moonzzz", "rested_moonzzzz",
    "rested_sleep_zzzz", "rested_zzz_compact",
    "rested_zzz_diag", "rested_zzz_stack",
}
Data.RESS_SYMBOL_VALUES = { "DEFAULT", "resurrection_ankh", "resurrection_cross", "resurrection_soul", "resurrection_wings" }
Data.STATUS_SYMBOL_ALIASES = {
    default = "DEFAULT",
    axes = "weapon_axes_crossed",
    ["weapon axes"] = "weapon_axes_crossed",
    ["weapon axes crossed"] = "weapon_axes_crossed",
    bows = "weapon_bows_crossed",
    ["weapon bows"] = "weapon_bows_crossed",
    ["weapon bows crossed"] = "weapon_bows_crossed",
    crossbows = "weapon_crossbows_crossed",
    ["weapon crossbows"] = "weapon_crossbows_crossed",
    daggers = "weapon_daggers_crossed",
    ["weapon daggers"] = "weapon_daggers_crossed",
    fishing = "weapon_fishing_poles_crossed",
    ["fishing poles"] = "weapon_fishing_poles_crossed",
    fist = "weapon_fist_crossed",
    ["fist weapons"] = "weapon_fist_crossed",
    guns = "weapon_guns_crossed",
    maces = "weapon_maces_crossed",
    polearms = "weapon_polearms_crossed",
    shuriken = "weapon_shuriken",
    staves = "weapon_staves_crossed",
    swords = "weapon_swords_crossed",
    thrown = "weapon_thrown_crossed",
    wands = "weapon_wands_crossed",
    warglaives = "weapon_warglaives_crossed",
    ["animated zzz"] = "rested_blizzard_animated",
    ["blizzard animated zzz"] = "rested_blizzard_animated",
    ["blizzard zzz"] = "rested_blizzard_animated",
    ["blizzard zzz animation"] = "rested_blizzard_animated",
    moon = "rested_moonzzz",
    ["moon 3 z"] = "rested_moonzzz",
    ["moon 4 z"] = "rested_moonzzzz",
    sleep = "rested_sleep_zzzz",
    ["sleep zzzz"] = "rested_sleep_zzzz",
    compact = "rested_zzz_compact",
    ["compact zzz"] = "rested_zzz_compact",
    diagonal = "rested_zzz_diag",
    ["diagonal zzz"] = "rested_zzz_diag",
    stacked = "rested_zzz_stack",
    ["stacked zzz"] = "rested_zzz_stack",
    ankh = "resurrection_ankh",
    cross = "resurrection_cross",
    soul = "resurrection_soul",
    wings = "resurrection_wings",
    ["angelic wings"] = "resurrection_wings",
}
