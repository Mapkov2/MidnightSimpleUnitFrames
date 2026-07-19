-- Runtime regression for late-anchor one-shot scheduling. A missing anchor may
-- request another reanchor while Factory.Apply is still running; that request
-- must not create an endless zero-delay timer chain.
local root = arg and arg[1] or "."
local factoryPath = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Factory.lua"

local timers = {}
_G.C_Timer = {
    After = function(delay, callback)
        assert(delay == 0, "late-anchor retry is not a next-frame one-shot")
        timers[#timers + 1] = callback
    end,
}
_G.InCombatLockdown = function() return false end
_G.UIParent = {}

local eventFrames = {}
_G.CreateFrame = function()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(kind, callback) self.scripts[kind] = callback end
    eventFrames[#eventFrames + 1] = frame
    return frame
end

local MSUF = {
    UF = {
        Factory = {},
        frames = {},
        unitOrder = {},
    },
}
function MSUF.ExportPublic(name, value)
    _G[name] = value
    return value
end

local chunk, loadError = loadfile(factoryPath)
assert(chunk, loadError)
chunk("MidnightSimpleUnitFrames", MSUF)

local schedule = assert(_G.MSUF_ScheduleLateAnchorReanchor)
local factory = assert(MSUF.UF.Factory)
local applyCalls = 0
local forceCalls = 0

local function RunTimer()
    local callback = table.remove(timers, 1)
    assert(callback, "expected one queued late-anchor timer")
    callback()
end

factory.Apply = function()
    applyCalls = applyCalls + 1
    assert(applyCalls == 1, "missing anchor recursively re-entered Factory.Apply")
    assert(schedule() == false, "flush-time retry was not suppressed")
    return true
end
factory.ForceReanchor = function()
    forceCalls = forceCalls + 1
    assert(schedule() == false, "forced flush recursively scheduled another apply")
    return true
end

assert(schedule() == true, "initial late-anchor request was not queued")
assert(schedule() == false, "duplicate queued request was not coalesced")
assert(#timers == 1, "duplicate late-anchor request created another timer")
RunTimer()
assert(applyCalls == 1 and forceCalls == 0, "ordinary late-anchor flush used the wrong apply path")
assert(#timers == 0, "flush-time retry created an endless timer chain")
assert(_G.MSUF_LateAnchorReanchorState.pending == false
    and _G.MSUF_LateAnchorReanchorState.flushing == false,
    "late-anchor state remained armed after flush")

applyCalls = 0
assert(schedule() == true, "second late-anchor request was not queued")
assert(schedule(true) == false, "queued force upgrade was not coalesced")
assert(#timers == 1, "force upgrade created another timer")
RunTimer()
assert(applyCalls == 0 and forceCalls == 1, "queued force upgrade did not use ForceReanchor once")
assert(#timers == 0, "forced flush created an endless timer chain")

-- The no-timer fallback must have the same reentrancy guard.
_G.C_Timer = nil
forceCalls = 0
assert(schedule(true) == true, "synchronous late-anchor fallback did not run")
assert(forceCalls == 1, "synchronous force fallback did not flush exactly once")
assert(_G.MSUF_LateAnchorReanchorState.pending == false
    and _G.MSUF_LateAnchorReanchorState.flushing == false,
    "synchronous late-anchor state remained armed")

print("PASS late anchor retry: one-shot, coalesced, reentrancy-safe")
