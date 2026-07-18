-- Regression coverage for inactive player castbar stop/failure storms.
_G = _G or _ENV

local root = arg and arg[1] or "."
local timers = {}
local invalidations = 0

_G.issecretvalue = function() return false end
_G.MSUF_IsCastbarEnabledForUnit = function() return true end
_G.C_Timer = {
    After = function(delay, callback)
        timers[#timers + 1] = { delay = delay, callback = callback }
    end,
}

local engine = {}
function engine:Invalidate()
    invalidations = invalidations + 1
end

local MSUF = {
    Castbars = { Engine = engine },
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}

assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_PlayerCastbarRuntime.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local onEvent = assert(_G.MSUF_PlayerCastbar_OnEvent)
local inactive = {}
onEvent(inactive, "UNIT_SPELLCAST_FAILED", "player", "failed-guid", 123, 456)
onEvent(inactive, "UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 123, nil, 456)
assert(invalidations == 0 and #timers == 0,
    "inactive failed/channel-stop events invalidated caches or armed a resync")

local active = {
    MSUF_castActive = true,
    _msufActiveCastUnit = "player",
    _msufActiveCastGUID = "active-guid",
    _msufActiveSpellID = 123,
    _msufActiveCastBarID = 456,
}
onEvent(active, "UNIT_SPELLCAST_FAILED", "player", "active-guid", 123, 456)
assert(invalidations == 2 and #timers == 1 and timers[1].delay == 0,
    "active failed cast lost its coalesced player/vehicle resync")
onEvent(active, "UNIT_SPELLCAST_FAILED", "player", "active-guid", 123, 456)
assert(invalidations == 4 and #timers == 1,
    "active failed-cast resync no longer coalesces to one callback")

local empower = { isEmpower = true }
onEvent(empower, "UNIT_SPELLCAST_FAILED", "player", "empower-guid", 321, 654)
assert(invalidations == 6,
    "empower failed event was incorrectly rejected by the inactive normal-cast guard")

print("PASS player castbar soft-resync guard: inactive storms are zero-work, active casts still resync")
