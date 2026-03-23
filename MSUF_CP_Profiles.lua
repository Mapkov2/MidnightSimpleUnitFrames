-- ============================================================================
-- MSUF_CP_Profiles.lua
-- Phase 1 ClassPower split: data-only event profiles for active render modes.
-- Loaded before Core/MSUF_ClassPower.lua.
-- ============================================================================

local K = _G.MSUF_CP_CONST or {}
local CPK = K.CPK or {}
local MODE = CPK.MODE or {}

_G.MSUF_CP_MODE_EVENT_PROFILE = {
    [MODE.NONE]           = { power = false, maxPower = false, aura = false, rune = false, health = false, pointCharge = false, warlockPred = false },
    [MODE.SEGMENTED]      = { power = true,  maxPower = true,  aura = false, rune = false, health = false, pointCharge = true,  warlockPred = false },
    [MODE.FRACTIONAL]     = { power = true,  maxPower = true,  aura = false, rune = false, health = false, pointCharge = false, warlockPred = true  },
    [MODE.RUNE_CD]        = { power = false, maxPower = false, aura = false, rune = true,  health = false, pointCharge = false, warlockPred = false },
    [MODE.AURA_SEGMENTED] = { power = false, maxPower = false, aura = true,  rune = false, health = false, pointCharge = false, warlockPred = false },
    [MODE.AURA_SINGLE]    = { power = false, maxPower = false, aura = true,  rune = false, health = false, pointCharge = false, warlockPred = false },
    [MODE.CONTINUOUS]     = { power = true,  maxPower = false, aura = false, rune = false, health = false, pointCharge = false, warlockPred = false },
    [MODE.TIMER_BAR]      = { power = false, maxPower = false, aura = true,  rune = false, health = false, pointCharge = false, warlockPred = false },
    [MODE.STAGGER]        = { power = false, maxPower = false, aura = true,  rune = false, health = true,  pointCharge = false, warlockPred = false },
}
