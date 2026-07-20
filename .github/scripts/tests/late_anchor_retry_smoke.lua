-- Runtime regression for bounded late-anchor scheduling. A missing anchor may
-- appear several frames after login/ADDON_LOADED, but retries must still stop.
local root = arg and arg[1] or "."
local factoryPath = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Factory.lua"

local timers = {}
_G.C_Timer = {
    After = function(delay, callback)
        assert(type(delay) == "number" and delay >= 0, "invalid late-anchor retry delay")
        timers[#timers + 1] = { delay = delay, callback = callback }
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

-- Both SetPoint and parent ownership can create an invalid dependency chain.
local source = { MSUFUnitKey = "player" }
function source:GetNumPoints() return 0 end
local pointChild = {}
function pointChild:GetNumPoints() return 1 end
function pointChild:GetPoint() return "CENTER", source end
local parentChild = {}
function parentChild:GetNumPoints() return 0 end
function parentChild:GetParent() return source end
local unrelated = {}
function unrelated:GetNumPoints() return 0 end
MSUF.UF.frames.player = source
assert(factory.AnchorWouldCreateCycle(source, pointChild), "SetPoint dependency cycle was not detected")
assert(factory.AnchorWouldCreateCycle(source, parentChild), "parent dependency cycle was not detected")
assert(factory.IsAnchorCandidateAllowed(unrelated, "player"), "unrelated custom anchor was rejected")
assert(not factory.IsAnchorCandidateAllowed(parentChild, "player"), "unsafe picker target was accepted")
local missingFrame, missingName = factory.ResolveNamedAnchor("MSUF_TestLateAnchor")
assert(missingFrame == nil and missingName == "MSUF_TestLateAnchor", "missing named anchor was not reported")
_G.MSUF_TestLateAnchor = unrelated
local resolvedFrame, resolvedMissing = factory.ResolveNamedAnchor("MSUF_TestLateAnchor")
assert(resolvedFrame == unrelated and resolvedMissing == nil, "late named anchor did not resolve directly")
_G.MSUF_TestLateAnchor = nil

local function RunTimer()
    local timer = table.remove(timers, 1)
    assert(timer, "expected one queued late-anchor timer")
    timer.callback()
end

local anchorMissing = true
factory.Apply = function()
    applyCalls = applyCalls + 1
    if anchorMissing then
        assert(schedule() == false, "flush-time retry was not coalesced")
    end
    return true
end
factory.ForceReanchor = function()
    forceCalls = forceCalls + 1
    return true
end

assert(schedule() == true, "initial late-anchor request was not queued")
assert(schedule() == false, "duplicate queued request was not coalesced")
assert(#timers == 1, "duplicate late-anchor request created another timer")
RunTimer()
assert(applyCalls == 1 and forceCalls == 0, "ordinary late-anchor flush used the wrong apply path")
assert(#timers == 1 and timers[1].delay > 0, "missing target did not queue a delayed bounded retry")
anchorMissing = false
RunTimer()
assert(applyCalls == 2, "late target was not retried after the initial apply")
assert(#timers == 0, "resolved late target kept retrying")
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

-- Permanently missing targets receive only the fixed retry budget.
anchorMissing = true
applyCalls = 0
assert(schedule() == true, "bounded retry chain was not queued")
local timerRuns = 0
while #timers > 0 do
    timerRuns = timerRuns + 1
    assert(timerRuns <= 6, "late-anchor retry budget became unbounded")
    RunTimer()
end
assert(applyCalls == 6, "late-anchor retry budget changed unexpectedly")
assert(_G.MSUF_LateAnchorReanchorState.pending == false,
    "exhausted late-anchor retry state remained pending")

-- The no-timer fallback must have the same reentrancy guard.
_G.C_Timer = nil
forceCalls = 0
assert(schedule(true) == true, "synchronous late-anchor fallback did not run")
assert(forceCalls == 1, "synchronous force fallback did not flush exactly once")
assert(_G.MSUF_LateAnchorReanchorState.pending == false
    and _G.MSUF_LateAnchorReanchorState.flushing == false,
    "synchronous late-anchor state remained armed")

applyCalls = 0
assert(schedule() == true, "synchronous missing-anchor fallback did not run")
assert(applyCalls == 1, "synchronous missing-anchor fallback recursed")

print("PASS late anchor retry: bounded, coalesced, late-resolution-safe")
