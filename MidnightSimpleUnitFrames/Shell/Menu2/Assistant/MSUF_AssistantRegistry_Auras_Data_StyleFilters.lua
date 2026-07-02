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
    { key = "showDurationBar", label = "Show Duration Bar", defaultValue = false, words = { "show duration bar", "duration bar", "timer bar", "aura duration bar", "aura timer bar" } },
}

Data.AURA_COOLDOWN_SWIPE_DIRECTION_VALUES = { "NORMAL", "REVERSE" }
Data.AURA_COOLDOWN_SWIPE_DIRECTION_ALIASES = {
    normal = "NORMAL",
    default = "NORMAL",
    forward = "NORMAL",
    forwards = "NORMAL",
    ["normal swipe"] = "NORMAL",
    ["normal direction"] = "NORMAL",
    reverse = "REVERSE",
    reversed = "REVERSE",
    backward = "REVERSE",
    backwards = "REVERSE",
    ["reverse swipe"] = "REVERSE",
    ["reverse direction"] = "REVERSE",
}

Data.AURA_DURATION_BAR_POSITION_VALUES = { "BOTTOM", "TOP" }
Data.AURA_DURATION_BAR_POSITION_ALIASES = {
    bottom = "BOTTOM",
    lower = "BOTTOM",
    below = "BOTTOM",
    ["at bottom"] = "BOTTOM",
    ["on bottom"] = "BOTTOM",
    ["bottom edge"] = "BOTTOM",
    top = "TOP",
    upper = "TOP",
    above = "TOP",
    ["at top"] = "TOP",
    ["on top"] = "TOP",
    ["top edge"] = "TOP",
}

Data.AURA_DURATION_BAR_DISPLAY_VALUES = { "BAR_ONLY", "OVERLAY" }
Data.AURA_DURATION_BAR_DISPLAY_ALIASES = {
    bar = "BAR_ONLY",
    ["bar only"] = "BAR_ONLY",
    onlybar = "BAR_ONLY",
    separate = "BAR_ONLY",
    ["separate bar"] = "BAR_ONLY",
    icon = "OVERLAY",
    overlay = "OVERLAY",
    ["icon bar"] = "OVERLAY",
    ["icon and bar"] = "OVERLAY",
    ["icon plus bar"] = "OVERLAY",
    ["icon + bar"] = "OVERLAY",
}

Data.AURA_DURATION_BAR_DIRECTION_VALUES = { "REMAINING", "ELAPSED" }
Data.AURA_DURATION_BAR_DIRECTION_ALIASES = {
    remaining = "REMAINING",
    remainder = "REMAINING",
    countdown = "REMAINING",
    ["count down"] = "REMAINING",
    decreasing = "REMAINING",
    deplete = "REMAINING",
    depletion = "REMAINING",
    drain = "REMAINING",
    elapsed = "ELAPSED",
    ["elapsed time"] = "ELAPSED",
    elapsed_time = "ELAPSED",
    countup = "ELAPSED",
    ["count up"] = "ELAPSED",
    increasing = "ELAPSED",
    progress = "ELAPSED",
    ["fill up"] = "ELAPSED",
}

Data.AURA_LANE_STYLE_NUMBER_SPECS = {
    { key = "stackTextSize", label = "Stack Text Size", defaultValue = 14, minValue = 6, maxValue = 40, words = { "stack size", "stack text size", "stack count text size" } },
    { key = "stackTextOffsetX", label = "Stack Text X Offset", defaultValue = -1, minValue = -2000, maxValue = 2000, words = { "stack x", "stack x offset", "stack text x", "stack text x offset" } },
    { key = "stackTextOffsetY", label = "Stack Text Y Offset", defaultValue = 1, minValue = -2000, maxValue = 2000, words = { "stack y", "stack y offset", "stack text y", "stack text y offset" } },
    { key = "cooldownTextSize", label = "Cooldown Text Size", defaultValue = 14, minValue = 6, maxValue = 40, words = { "cooldown size", "cooldown text size", "timer text size" } },
    { key = "cooldownTextOffsetX", label = "Cooldown Text X Offset", defaultValue = 0, minValue = -2000, maxValue = 2000, words = { "cooldown x", "cooldown x offset", "cooldown text x", "timer text x offset" } },
    { key = "cooldownTextOffsetY", label = "Cooldown Text Y Offset", defaultValue = 0, minValue = -2000, maxValue = 2000, words = { "cooldown y", "cooldown y offset", "cooldown text y", "timer text y offset" } },
    { key = "cooldownDecimalSeconds", label = "Cooldown Decimal Threshold", defaultValue = 3, minValue = 0, maxValue = 30, words = { "cooldown decimals", "cooldown decimal", "cooldown decimal threshold", "timer decimals", "timer decimal threshold", "decimals below sec", "decimals below seconds", "decimal seconds" } },
    { key = "durationBarHeight", label = "Duration Bar Height", defaultValue = 2, minValue = 1, maxValue = 16, words = { "duration bar height", "timer bar height", "aura duration bar height", "aura timer bar height" } },
}

Data.AURA_FILTER_BOOLEAN_SPECS = {
    { lane = "buff", key = "onlyMine", label = "Buff Player Filter", words = { "buff player filter", "only my buffs", "my buffs only", "show only my buffs", "show my buffs only", "player buffs only", "own buffs only" } },
    { lane = "buff", key = "raid", label = "Buff Raid Filter", words = { "buff raid filter", "raid buffs filter", "raid buffs", "show raid buffs", "show only raid buffs", "raid buffs only" } },
    { lane = "buff", key = "raidInCombat", label = "Buff Raid In Combat Filter", words = { "buff raid in combat filter", "raid in combat buffs", "combat raid buffs", "show raid combat buffs", "show raid in combat buffs" } },
    { lane = "buff", key = "includeNameplateOnly", label = "Buff Include Nameplate-only Filter", words = { "buff nameplate-only filter", "buff nameplate only filter", "include nameplate-only buffs", "include nameplate only buffs", "nameplate-only buffs", "nameplate only buffs", "show nameplate-only buffs" } },
    { lane = "buff", key = "cancelable", label = "Buff Cancelable Filter", conflicts = { "notCancelable" }, words = { "buff cancelable filter", "cancelable buffs", "cancellable buffs", "show cancelable buffs", "show cancellable buffs" } },
    { lane = "buff", key = "notCancelable", label = "Buff Not Cancelable Filter", conflicts = { "cancelable" }, words = { "buff not cancelable filter", "not cancelable buffs", "not cancellable buffs", "non cancelable buffs", "non cancellable buffs", "uncancelable buffs", "uncancellable buffs", "show non cancelable buffs" } },
    { lane = "buff", key = "externalDefensive", label = "Buff External Defensive Filter", words = { "buff external defensive filter", "external defensive buffs", "external defensives", "external buffs", "show external defensives" } },
    { lane = "buff", key = "bigDefensive", label = "Buff Big Defensive Filter", words = { "buff big defensive filter", "big defensive buffs", "big defensives", "major defensive buffs", "major defensives", "defensive buffs", "show big defensives" } },
    { lane = "debuff", key = "onlyMine", label = "Debuff Player Filter", words = { "debuff player filter", "only my debuffs", "my debuffs only", "show only my debuffs", "show my debuffs only", "player debuffs only", "own debuffs only" } },
    { lane = "debuff", key = "raid", label = "Debuff Raid Filter", words = { "debuff raid filter", "raid debuffs filter", "raid debuffs", "show raid debuffs", "show only raid debuffs", "raid debuffs only" } },
    { lane = "debuff", key = "raidInCombat", label = "Debuff Raid In Combat Filter", words = { "debuff raid in combat filter", "raid in combat debuffs", "combat raid debuffs", "show raid combat debuffs", "show raid in combat debuffs" } },
    { lane = "debuff", key = "includeNameplateOnly", label = "Debuff Include Nameplate-only Filter", words = { "debuff nameplate-only filter", "debuff nameplate only filter", "include nameplate-only debuffs", "include nameplate only debuffs", "nameplate-only debuffs", "nameplate only debuffs", "show nameplate-only debuffs" } },
    { lane = "debuff", key = "includeDispellable", label = "Debuff Dispellable Filter", words = { "debuff dispellable filter", "dispellable debuffs", "dispellable debuffs only", "only dispellable debuffs", "show dispellable debuffs", "show only dispellable debuffs", "show dispellable only", "purgeable debuffs" } },
    { lane = "debuff", key = "crowdControl", label = "Debuff Crowd Control Filter", words = { "debuff crowd control filter", "crowd control debuffs", "crowd control debuffs only", "cc debuffs", "cc debuffs only", "show cc debuffs", "show crowd control debuffs" } },
}

Data.AURA_EXCLUSIVE_FILTER_VALUES = {
    buff = { "none" },
    debuff = { "none", "raid" },
}

Data.AURA_EXCLUSIVE_FILTER_ALIASES = {
    none = "none",
    off = "none",
    disabled = "none",
    raid = "raid",
    boss = "raid",
    encounter = "raid",
    all = "none",
    everything = "none",
}

Data.AURA_DEBUFF_TYPE_BORDER_VALUES = { "OFF", "BORDER", "SYMBOL" }
Data.AURA_DEBUFF_TYPE_BORDER_ALIASES = {
    off = "OFF",
    none = "OFF",
    disabled = "OFF",
    hide = "OFF",
    hidden = "OFF",
    border = "BORDER",
    ["border only"] = "BORDER",
    ["just border"] = "BORDER",
    outline = "BORDER",
    ["outline only"] = "BORDER",
    symbol = "SYMBOL",
    icon = "SYMBOL",
    ["border symbol"] = "SYMBOL",
    ["border and symbol"] = "SYMBOL",
    ["border plus symbol"] = "SYMBOL",
    ["border + symbol"] = "SYMBOL",
    ["with symbol"] = "SYMBOL",
    ["with icon"] = "SYMBOL",
}
