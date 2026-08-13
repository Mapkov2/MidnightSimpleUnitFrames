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
    { attr = "showTooltip", label = "Aura Tooltips", defaultValue = true, aliases = { "aura tooltips", "show aura tooltips", "aura tooltip", "show aura tooltip" } },
    { attr = "cooldownSwipeDarkenOnLoss", label = "Cooldown Swipe Darkens on Loss", defaultValue = false, aliases = { "swipe darkens on loss", "cooldown swipe darkens", "darken aura swipe on loss", "darken cooldown swipe" } },
    { attr = "useDebuffTypeBorders", label = "Dispel-type Borders", defaultValue = false, aliases = { "dispel type borders", "debuff type borders", "aura dispel borders", "aura debuff type borders" } },
}

-- Auras2 reminder metadata is intentionally retired. Auras3 has no reminder
-- renderer, so an Assistant setting would only persist dead state.
Data.AURA_REMINDER_SPECS = {}
