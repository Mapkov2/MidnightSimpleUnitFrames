-- Assistant Castbars shared core data.
-- Loaded before MSUF_AssistantRegistry_Castbars_Core.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.CastbarsRegistry = A.CastbarsRegistry or {}

A.CastbarsRegistry.CASTBAR_KEYS = {
    player = { enable = "enablePlayerCastbar", backend = "castbarPlayerBackend", memory = "castbarPlayerBackendBeforeHide", w = "castbarPlayerBarWidth", h = "castbarPlayerBarHeight", x = "castbarPlayerOffsetX", y = "castbarPlayerOffsetY", match = "castbarPlayerMatchWidth" },
    target = { enable = "enableTargetCastbar", backend = "castbarTargetBackend", memory = "castbarTargetBackendBeforeHide", w = "castbarTargetBarWidth", h = "castbarTargetBarHeight", x = "castbarTargetOffsetX", y = "castbarTargetOffsetY", match = "castbarTargetMatchWidth" },
    focus = { enable = "enableFocusCastbar", backend = "castbarFocusBackend", memory = "castbarFocusBackendBeforeHide", w = "castbarFocusBarWidth", h = "castbarFocusBarHeight", x = "castbarFocusOffsetX", y = "castbarFocusOffsetY", match = "castbarFocusMatchWidth" },
    boss = { enable = "enableBossCastbar", backend = "bossCastbarBackend", memory = "bossCastbarBackendBeforeHide", w = "bossCastbarWidth", h = "bossCastbarHeight", x = "bossCastbarOffsetX", y = "bossCastbarOffsetY", match = "bossCastbarMatchWidth" },
}

A.CastbarsRegistry.CASTBAR_DETAIL_FIELDS = {
    player = { time = "showPlayerCastTime", icon = "castbarPlayerShowIcon", text = "castbarPlayerShowSpellName", timeFormat = "castbarPlayerTimeFormat" },
    target = { time = "showTargetCastTime", icon = "castbarTargetShowIcon", text = "castbarTargetShowSpellName", targetName = "castbarTargetShowTargetName", timeFormat = "castbarTargetTimeFormat" },
    focus = { time = "showFocusCastTime", icon = "castbarFocusShowIcon", text = "castbarFocusShowSpellName", targetName = "castbarFocusShowTargetName", timeFormat = "castbarFocusTimeFormat" },
    boss = { time = "showBossCastTime", icon = "showBossCastIcon", text = "showBossCastName", timeFormat = "bossCastTimeFormat" },
}
