-- Assistant Auras group-category fallback data.
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

Data.GF_AURA_CATEGORY_FALLBACK = {
    { key = "RAID_BUFFS", label = "Long-term Raid Buffs", aliases = { "raid buffs", "long term raid buffs", "raid buff" } },
    { key = "PRESERVATION_EVOKER", label = "Preservation Evoker", aliases = { "preservation evoker", "pres evoker" } },
    { key = "AUGMENTATION_EVOKER", label = "Augmentation Evoker", aliases = { "augmentation evoker", "aug evoker" } },
    { key = "RESTO_DRUID", label = "Restoration Druid", aliases = { "resto druid", "restoration druid" } },
    { key = "DISC_PRIEST", label = "Discipline Priest", aliases = { "disc priest", "discipline priest" } },
    { key = "HOLY_PRIEST", label = "Holy Priest", aliases = { "holy priest" } },
    { key = "MISTWEAVER_MONK", label = "Mistweaver Monk", aliases = { "mistweaver monk", "mw monk" } },
    { key = "RESTO_SHAMAN", label = "Restoration Shaman", aliases = { "resto shaman", "restoration shaman" } },
    { key = "HOLY_PALADIN", label = "Holy Paladin", aliases = { "holy paladin", "holy pala" } },
    { key = "BLESSING_BRONZE", label = "Blessing of the Bronze", aliases = { "blessing of the bronze", "bronze blessing" } },
    { key = "SELF_BUFFS", label = "Long-term Self Buffs", aliases = { "self buffs", "long term self buffs" } },
    { key = "ROGUE_POISONS", label = "Rogue Poisons", aliases = { "rogue poisons", "poisons" } },
    { key = "SHAMAN_IMBUE", label = "Shaman Imbuements", aliases = { "shaman imbues", "shaman imbuements", "imbues" } },
    { key = "RESOURCE_AURAS", label = "Resource Auras", aliases = { "resource auras", "resource buffs" } },
    { key = "COOLDOWNS", label = "Cooldowns", aliases = { "cooldowns", "cooldown auras" } },
    { key = "SATED", label = "Sated / Exhaustion", aliases = { "sated", "exhaustion", "heroism exhaustion", "bloodlust exhaustion" } },
    { key = "DESERTER", label = "Deserter", aliases = { "deserter", "deserteur" } },
    { key = "CHALLENGE_DEBUFFS", label = "Challenge/Instance Debuffs", aliases = { "challenge debuffs", "instance debuffs", "challengers burden" } },
    { key = "CLASS_UTILITY", label = "Class/Utility Auras", aliases = { "class utility", "class utility auras" } },
    { key = "SKYRIDING", label = "Skyriding/Ride Along Auras", aliases = { "skyriding", "skyriding auras", "ride along" } },
}
