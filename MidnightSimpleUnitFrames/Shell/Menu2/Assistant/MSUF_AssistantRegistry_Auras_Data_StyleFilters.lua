-- Assistant Auras style/filter setting specs.
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

Data.AURA_LANE_STYLE_BOOLEAN_SPECS = {
    { key = "showStackCount", label = "Show Stack Count", defaultValue = true, words = { "show stack count", "stack count", "stacks" } },
    { key = "showCooldownText", label = "Show Cooldown Text", defaultValue = true, words = { "show cooldown text", "cooldown text", "timer text" } },
    { key = "showCooldownSwipe", label = "Show Cooldown Swipe", defaultValue = true, words = { "show cooldown swipe", "cooldown swipe", "timer swipe" } },
}

Data.AURA_LANE_STYLE_NUMBER_SPECS = {
    { key = "stackTextSize", label = "Stack Text Size", defaultValue = 14, minValue = 6, maxValue = 40, words = { "stack size", "stack text size", "stack count text size" } },
    { key = "stackTextOffsetX", label = "Stack Text X Offset", defaultValue = -1, minValue = -2000, maxValue = 2000, words = { "stack x", "stack x offset", "stack text x", "stack text x offset" } },
    { key = "stackTextOffsetY", label = "Stack Text Y Offset", defaultValue = 1, minValue = -2000, maxValue = 2000, words = { "stack y", "stack y offset", "stack text y", "stack text y offset" } },
    { key = "cooldownTextSize", label = "Cooldown Text Size", defaultValue = 14, minValue = 6, maxValue = 40, words = { "cooldown size", "cooldown text size", "timer text size" } },
    { key = "cooldownTextOffsetX", label = "Cooldown Text X Offset", defaultValue = 0, minValue = -2000, maxValue = 2000, words = { "cooldown x", "cooldown x offset", "cooldown text x", "timer text x offset" } },
    { key = "cooldownTextOffsetY", label = "Cooldown Text Y Offset", defaultValue = 0, minValue = -2000, maxValue = 2000, words = { "cooldown y", "cooldown y offset", "cooldown text y", "timer text y offset" } },
}

Data.AURA_FILTER_BOOLEAN_SPECS = {
    { lane = "buff", key = "onlyMine", label = "Buff Player Filter", words = { "buff player filter", "only my buffs", "my buffs only" } },
    { lane = "buff", key = "raid", label = "Buff Raid Filter", words = { "buff raid filter", "raid buffs filter" } },
    { lane = "buff", key = "raidInCombat", label = "Buff Raid In Combat Filter", words = { "buff raid in combat filter", "raid in combat buffs" } },
    { lane = "buff", key = "cancelable", label = "Buff Cancelable Filter", words = { "buff cancelable filter", "cancelable buffs" } },
    { lane = "buff", key = "notCancelable", label = "Buff Not Cancelable Filter", words = { "buff not cancelable filter", "not cancelable buffs" } },
    { lane = "buff", key = "externalDefensive", label = "Buff External Defensive Filter", words = { "buff external defensive filter", "external defensive buffs", "external defensives" } },
    { lane = "buff", key = "bigDefensive", label = "Buff Big Defensive Filter", words = { "buff big defensive filter", "big defensive buffs", "major defensive buffs" } },
    { lane = "debuff", key = "onlyMine", label = "Debuff Player Filter", words = { "debuff player filter", "only my debuffs", "my debuffs only" } },
    { lane = "debuff", key = "raid", label = "Debuff Raid Filter", words = { "debuff raid filter", "raid debuffs filter" } },
    { lane = "debuff", key = "raidInCombat", label = "Debuff Raid In Combat Filter", words = { "debuff raid in combat filter", "raid in combat debuffs" } },
    { lane = "debuff", key = "includeDispellable", label = "Debuff Dispellable Filter", words = { "debuff dispellable filter", "dispellable debuffs" } },
    { lane = "debuff", key = "crowdControl", label = "Debuff Crowd Control Filter", words = { "debuff crowd control filter", "crowd control debuffs", "cc debuffs" } },
}

Data.AURA_EXCLUSIVE_FILTER_VALUES = {
    buff = { "none", "important" },
    debuff = { "none", "important", "raid" },
}

Data.AURA_EXCLUSIVE_FILTER_ALIASES = {
    none = "none",
    off = "none",
    disabled = "none",
    important = "important",
    importantonly = "important",
    ["important only"] = "important",
    raid = "raid",
    boss = "raid",
    encounter = "raid",
    all = "none",
    everything = "none",
}
