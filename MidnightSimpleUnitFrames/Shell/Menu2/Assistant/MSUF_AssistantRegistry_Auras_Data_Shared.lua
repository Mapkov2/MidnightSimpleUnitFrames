-- Assistant Auras shared option static values.
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

Data.AURA_SHARED_BOOLEAN_SPECS = {
    { attr = "showBuffs", label = "Show Buffs", defaultValue = true, aliases = { "show aura buffs", "show buffs", "aura buffs", "buff auras", "buffs" } },
    { attr = "showDebuffs", label = "Show Debuffs", defaultValue = true, aliases = { "show aura debuffs", "show debuffs", "aura debuffs", "debuff auras", "debuffs" } },
    { attr = "highlightOwnBuffs", label = "Highlight Own Buffs", defaultValue = false, aliases = { "highlight own buffs", "highlight my buffs", "own buff highlight", "my buff highlight" } },
    { attr = "highlightOwnDebuffs", label = "Highlight Own Debuffs", defaultValue = false, aliases = { "highlight own debuffs", "highlight my debuffs", "own debuff highlight", "my debuff highlight" } },
    { attr = "showTooltip", label = "Aura Tooltips", defaultValue = true, aliases = { "aura tooltips", "show aura tooltips", "aura tooltip", "show aura tooltip" } },
    { attr = "clickThroughAuras", label = "Click-through Auras", defaultValue = false, aliases = { "click through auras", "click-through auras", "aura click through", "aura click-through" } },
    { attr = "cooldownSwipeDarkenOnLoss", label = "Cooldown Swipe Darkens on Loss", defaultValue = false, aliases = { "swipe darkens on loss", "cooldown swipe darkens", "darken aura swipe on loss", "darken cooldown swipe" } },
    { attr = "useDebuffTypeBorders", label = "Dispel-type Borders", defaultValue = false, aliases = { "dispel type borders", "debuff type borders", "aura dispel borders", "aura debuff type borders" } },
}

Data.AURA_REMINDER_SPECS = {
    { key = "FORTITUDE", label = "Power Word: Fortitude", aliases = { "fortitude reminder", "power word fortitude reminder", "priest stamina reminder" } },
    { key = "ARCANE_INTELLECT", label = "Arcane Intellect", aliases = { "arcane intellect reminder", "intellect reminder", "mage intellect reminder" } },
    { key = "MARK_OF_WILD", label = "Mark of the Wild", aliases = { "mark of the wild reminder", "motw reminder", "druid buff reminder" } },
    { key = "BATTLE_SHOUT", label = "Battle Shout", aliases = { "battle shout reminder", "warrior buff reminder" } },
    { key = "SKYFURY", label = "Skyfury", aliases = { "skyfury reminder", "shaman skyfury reminder" } },
    { key = "SOURCE_OF_MAGIC", label = "Source of Magic", aliases = { "source of magic reminder", "evoker source of magic reminder" } },
    { key = "BLESSING_BRONZE", label = "Blessing of the Bronze", aliases = { "blessing of the bronze reminder", "bronze reminder", "evoker bronze reminder" } },
    { key = "ROGUE_LETHAL", label = "Lethal Poison", aliases = { "lethal poison reminder", "rogue lethal poison reminder" } },
    { key = "ROGUE_NONLETHAL", label = "Non-Lethal Poison", aliases = { "non lethal poison reminder", "non-lethal poison reminder", "rogue non lethal reminder" } },
}
