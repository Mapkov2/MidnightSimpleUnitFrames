_G = _G or _ENV

package.path = "tools/?.lua;tools/AssistantTraining/?.lua;" .. package.path
require("wow_stubs")

local Loader = require("assistant_runtime_manifest_loader")
assert(Loader.LoadAssistantRuntime(_G.MSUF_NS, { useCompanionPrivate = true }))

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant runtime missing")
local P = assert(A.Parser, "Assistant parser missing")
local Registry = assert(A.Registry, "Assistant registry missing")
local AutoCoverage = assert(A.AutoCoverage, "Assistant AutoCoverage missing")

-- The compound controller operates on the complete release registry. Fill it
-- before installing the timer probe so registry generation is not mistaken for
-- deferred-submit callback work.
assert(type(AutoCoverage.Fill) == "function", "AutoCoverage.Fill missing")
AutoCoverage.Fill()

P._registryExactAliasSettings = nil
P._registryExactAliasCount = nil
P._registryExactAliasIndex = nil
P._registryExactAliasLookupCache = nil
P._exactActionAliasSet = nil
P._exactActionAliasCount = nil

local targetWidth = assert(Registry:GetSetting("target.width"), "Target Width setting missing")
local targetPortrait = assert(Registry:GetSetting("target.portraitMode"), "Target Portrait Position setting missing")
local oldWidth, oldPortrait = targetWidth.get(), targetPortrait.get()

local timers = {}
_G.GetTimePreciseSec = function() return os.clock() end
_G.C_Timer = _G.C_Timer or {}
_G.C_Timer.NewTimer = function(_, callback)
    local handle = { cancelled = false }
    function handle:Cancel() self.cancelled = true end
    timers[#timers + 1] = { callback = callback, handle = handle }
    return handle
end

-- Match the in-game deferred job budget. The regression is about the longest
-- individual timer callback, not aggregate cold-index construction time.
A.jobBudgetMs = 2
A.jobMaxStepsPerFrame = 4

collectgarbage("collect")
local callbackResult, callbackCalls
callbackCalls = 0
local submitStarted = os.clock()
local immediate = assert(A.SubmitDeferred(
    "set target width to 300 and target portrait position to left",
    function(result)
        callbackCalls = callbackCalls + 1
        callbackResult = result
    end
), "cold compound SubmitDeferred returned nil")
local submitMs = (os.clock() - submitStarted) * 1000

assert(immediate.status == "queued", "cold compound request was not deferred")
assert(callbackCalls == 0, "cold compound callback ran during SubmitDeferred preflight")
assert(P._registryExactAliasIndex == nil, "SubmitDeferred preflight built the exact-alias index")

local callbackCount, maxCallbackMs, totalCallbackMs = 0, 0, 0
while #timers > 0 do
    assert(callbackCount < 400, "cold compound job exceeded 400 timer callbacks")
    local timer = table.remove(timers, 1)
    if not timer.handle.cancelled then
        callbackCount = callbackCount + 1
        local callbackStarted = os.clock()
        timer.callback()
        local elapsedMs = (os.clock() - callbackStarted) * 1000
        totalCallbackMs = totalCallbackMs + elapsedMs
        if elapsedMs > maxCallbackMs then maxCallbackMs = elapsedMs end
    end
end

assert(callbackCalls == 1, "cold compound completion callback count was " .. tostring(callbackCalls))
assert(type(callbackResult) == "table", "cold compound completion result missing")
assert((callbackResult.status or callbackResult.result) == "applied",
    "cold compound result was " .. tostring(callbackResult.status or callbackResult.result))
assert(tonumber(targetWidth.get()) == 300, "cold compound did not set Target Width to 300")
assert(targetPortrait.get() == "LEFT", "cold compound did not set Target Portrait Position to LEFT")
assert(type(P._registryExactAliasIndex) == "table", "cold compound did not build the exact-alias index")
assert(submitMs <= 8, string.format("SubmitDeferred preflight %.3f ms exceeds 8 ms", submitMs))
assert(maxCallbackMs <= 8, string.format("cold compound callback %.3f ms exceeds 8 ms", maxCallbackMs))

-- The earlier exact resolution must remain behaviorally identical: both
-- clauses are one atomic transaction and one undo restores both values.
local undo = assert(A.Submit("undo"), "cold compound undo result missing")
assert((undo.status or undo.result) == "applied", "cold compound undo was not applied")
assert(targetWidth.get() == oldWidth, "cold compound undo did not restore Target Width")
assert(targetPortrait.get() == oldPortrait, "cold compound undo did not restore Target Portrait Position")

io.write(string.format(
    "assistant cold compound callback perf passed: submit=%.3f ms callbacks=%d max=%.3f ms total=%.3f ms\n",
    submitMs, callbackCount, maxCallbackMs, totalCallbackMs
))
