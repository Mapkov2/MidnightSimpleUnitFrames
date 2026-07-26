-- Assistant Auras blacklist preset values and aliases.
-- Loaded after MSUF_AssistantRegistry_Auras_Data.lua; consumers read A.AurasRegistryData.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Data = A.AurasRegistryData or {}
A.AurasRegistryData = Data

Data.AURA_BLACKLIST_PRESET_VALUES = {
    "RAID_BUFFS", "PRESERVATION_EVOKER", "AUGMENTATION_EVOKER", "RESTO_DRUID", "DISC_PRIEST",
    "HOLY_PRIEST", "MISTWEAVER_MONK", "RESTO_SHAMAN", "HOLY_PALADIN", "BLESSING_BRONZE",
    "SELF_BUFFS", "ROGUE_POISONS", "SHAMAN_IMBUE", "RESOURCE_AURAS", "COOLDOWNS",
    "SATED", "DESERTER", "CHALLENGE_DEBUFFS", "CLASS_UTILITY", "SKYRIDING",
}
Data.AURA_BLACKLIST_PRESET_ALIASES = {
    raidbuffs = "RAID_BUFFS",
    ["raid buffs"] = "RAID_BUFFS",
    preservationevoker = "PRESERVATION_EVOKER",
    ["preservation evoker"] = "PRESERVATION_EVOKER",
    augmentationevoker = "AUGMENTATION_EVOKER",
    ["augmentation evoker"] = "AUGMENTATION_EVOKER",
    restodruid = "RESTO_DRUID",
    ["resto druid"] = "RESTO_DRUID",
    disciplinepriest = "DISC_PRIEST",
    ["discipline priest"] = "DISC_PRIEST",
    discpriest = "DISC_PRIEST",
    ["disc priest"] = "DISC_PRIEST",
    holypriest = "HOLY_PRIEST",
    ["holy priest"] = "HOLY_PRIEST",
    mistweavermonk = "MISTWEAVER_MONK",
    ["mistweaver monk"] = "MISTWEAVER_MONK",
    restoshaman = "RESTO_SHAMAN",
    ["resto shaman"] = "RESTO_SHAMAN",
    holypaladin = "HOLY_PALADIN",
    ["holy paladin"] = "HOLY_PALADIN",
    blessingbronze = "BLESSING_BRONZE",
    ["blessing bronze"] = "BLESSING_BRONZE",
    selfbuffs = "SELF_BUFFS",
    ["self buffs"] = "SELF_BUFFS",
    roguepoisons = "ROGUE_POISONS",
    ["rogue poisons"] = "ROGUE_POISONS",
    shamanimbue = "SHAMAN_IMBUE",
    ["shaman imbue"] = "SHAMAN_IMBUE",
    resourceauras = "RESOURCE_AURAS",
    ["resource auras"] = "RESOURCE_AURAS",
    cooldowns = "COOLDOWNS",
    sated = "SATED",
    exhaustion = "SATED",
    deserter = "DESERTER",
    deserteur = "DESERTER",
    challengedebuffs = "CHALLENGE_DEBUFFS",
    ["challenge debuffs"] = "CHALLENGE_DEBUFFS",
    ["challenge instance debuffs"] = "CHALLENGE_DEBUFFS",
    ["instance debuffs"] = "CHALLENGE_DEBUFFS",
    ["challengers burden"] = "CHALLENGE_DEBUFFS",
    classutility = "CLASS_UTILITY",
    ["class utility"] = "CLASS_UTILITY",
    ["class utility auras"] = "CLASS_UTILITY",
    skyriding = "SKYRIDING",
    ["skyriding auras"] = "SKYRIDING",
    ["ride along"] = "SKYRIDING",
    ridealong = "SKYRIDING",
}
