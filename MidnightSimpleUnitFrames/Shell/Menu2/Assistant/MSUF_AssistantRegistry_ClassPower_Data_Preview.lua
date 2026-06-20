-- Assistant ClassPower preview resource values and aliases.
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

Data.CLASS_POWER_PREVIEW_VALUES = {
    "deathknight_runes",
    "demonhunter_devourer",
    "demonhunter_vengeance",
    "druid_feral",
    "druid_balance",
    "evoker_essence",
    "evoker_augmentation_ebon",
    "hunter_survival_tip",
    "mage_arcane",
    "monk_brewmaster",
    "monk_windwalker",
    "paladin_holy_power",
    "priest_shadow",
    "rogue_combo",
    "shaman_elemental",
    "shaman_enhancement",
    "warlock_soul_shards",
    "warlock_destruction",
    "warrior_whirlwind",
}

Data.CLASS_POWER_PREVIEW_LABELS = {
    deathknight_runes = "Death Knight - Runes",
    demonhunter_devourer = "Demon Hunter - Soul Fragments",
    demonhunter_vengeance = "Demon Hunter - Vengeance Fragments",
    druid_feral = "Druid - Feral Combo Points",
    druid_balance = "Druid - Balance (no class bar)",
    evoker_essence = "Evoker - Essence",
    evoker_augmentation_ebon = "Evoker - Augmentation Ebon Might",
    hunter_survival_tip = "Hunter - Survival Tip of the Spear",
    mage_arcane = "Mage - Arcane Charges",
    monk_brewmaster = "Monk - Brewmaster Stagger",
    monk_windwalker = "Monk - Windwalker Chi",
    paladin_holy_power = "Paladin - Holy Power",
    priest_shadow = "Priest - Shadow Insanity",
    rogue_combo = "Rogue - Combo Points",
    shaman_elemental = "Shaman - Elemental Maelstrom",
    shaman_enhancement = "Shaman - Enhancement Maelstrom Weapon",
    warlock_soul_shards = "Warlock - Soul Shards",
    warlock_destruction = "Warlock - Destruction Soul Shards",
    warrior_whirlwind = "Warrior - Whirlwind Stacks",
}

Data.CLASS_POWER_PREVIEW_ALIASES = {
    ["death knight"] = "deathknight_runes",
    dk = "deathknight_runes",
    runes = "deathknight_runes",
    ["demon hunter soul fragments"] = "demonhunter_devourer",
    ["soul fragments"] = "demonhunter_devourer",
    ["vengeance fragments"] = "demonhunter_vengeance",
    vengeance = "demonhunter_vengeance",
    ["feral combo points"] = "druid_feral",
    feral = "druid_feral",
    ["balance druid"] = "druid_balance",
    boomkin = "druid_balance",
    essence = "evoker_essence",
    evoker = "evoker_essence",
    ["ebon might"] = "evoker_augmentation_ebon",
    augmentation = "evoker_augmentation_ebon",
    aug = "evoker_augmentation_ebon",
    ["tip of the spear"] = "hunter_survival_tip",
    hunter = "hunter_survival_tip",
    ["arcane charges"] = "mage_arcane",
    mage = "mage_arcane",
    stagger = "monk_brewmaster",
    monk = "monk_windwalker",
    brewmaster = "monk_brewmaster",
    chi = "monk_windwalker",
    windwalker = "monk_windwalker",
    ["holy power"] = "paladin_holy_power",
    paladin = "paladin_holy_power",
    insanity = "priest_shadow",
    shadow = "priest_shadow",
    ["combo points"] = "rogue_combo",
    combo = "rogue_combo",
    rogue = "rogue_combo",
    maelstrom = "shaman_elemental",
    elemental = "shaman_elemental",
    ["maelstrom weapon"] = "shaman_enhancement",
    enhancement = "shaman_enhancement",
    ["soul shards"] = "warlock_soul_shards",
    warlock = "warlock_soul_shards",
    destruction = "warlock_destruction",
    whirlwind = "warrior_whirlwind",
    warrior = "warrior_whirlwind",
}
