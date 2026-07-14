_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local loaderPath = exists("tools/assistant_runtime_manifest_loader.lua")
    and "tools/assistant_runtime_manifest_loader.lua"
    or "../tools/assistant_runtime_manifest_loader.lua"
local RuntimeManifest = dofile(loaderPath)
local assistantRoot = RuntimeManifest.ResolveCompanionRoot() .. "/Assistant/"

local combat, menuShown = true, true
local timers, timerCount = {}, 0
local framesCreated, eventRegistrations, onUpdates = 0, 0, 0

local MSUF = {
    MSUF2 = {
        frame = { IsShown = function() return menuShown end },
    },
}
_G.MSUF_NS, _G.MSUF2 = MSUF, MSUF.MSUF2
_G.GetTime = function() return os.clock() end
_G.GetTimePreciseSec = function() return os.clock() end
_G.InCombatLockdown = function() return combat end
_G.UnitAffectingCombat = function(unit) return unit == "player" and combat or false end

_G.CreateFrame = function()
    framesCreated = framesCreated + 1
    local frame = {}
    function frame:RegisterEvent()
        eventRegistrations = eventRegistrations + 1
    end
    function frame:RegisterUnitEvent()
        eventRegistrations = eventRegistrations + 1
    end
    function frame:SetScript(kind, fn)
        if kind == "OnUpdate" and fn then onUpdates = onUpdates + 1 end
    end
    return frame
end

_G.C_Timer = {
    NewTimer = function(_, callback)
        timerCount = timerCount + 1
        local timer = { callback = callback, cancelled = false, fired = false }
        function timer:Cancel() self.cancelled = true end
        function timer:Fire(force)
            if self.fired then return false end
            self.fired = true
            if self.cancelled and not force then return false end
            self.callback()
            return true
        end
        timers[#timers + 1] = timer
        return timer
    end,
    After = function() error("Assistant used non-cancellable C_Timer.After") end,
    NewTicker = function() error("Assistant used a repeating ticker") end,
}

local function firePending(limit)
    limit = limit or 32
    local fired = 0
    while fired < limit do
        local timer
        for i = 1, #timers do
            if not timers[i].cancelled and not timers[i].fired then timer = timers[i]; break end
        end
        if not timer then return fired end
        timer:Fire()
        fired = fired + 1
    end
    error("Assistant timers did not quiesce")
end

local chunk, err = loadfile(assistantRoot .. "MSUF_Assistant.lua")
assert(chunk, err)
chunk("MidnightSimpleUnitFrames_Assistant", MSUF)

local undoChunk, undoError = loadfile(assistantRoot .. "MSUF_AssistantUndo.lua")
assert(undoChunk, undoError)
undoChunk("MidnightSimpleUnitFrames_Assistant", MSUF)

local A = assert(MSUF.Assistant, "Assistant namespace missing")
assert(type(A.StartJob) == "function", "StartJob missing")
assert(type(A.ResumeCombatDeferredJobs) == "function", "combat resume helper missing")
assert(framesCreated == 0 and eventRegistrations == 0 and onUpdates == 0 and timerCount == 0,
    "Assistant core created a passive runtime source while loading")

local handledInputs, historyWrites, deferredCallbacks = 0, 0, 0
A.HandleCommandInput = function()
    handledInputs = handledInputs + 1
    return { text = "unexpected parse", status = "failed" }
end
A.AddHistory = function() historyWrites = historyWrites + 1 end

local function normalizedWords(text)
    return " " .. tostring(text or ""):lower():gsub("[%p%c]", " "):gsub("%s+", " ") .. " "
end

local function assertEnglishCombatOutput(label, result)
    assert(type(result) == "table", label .. ": missing combat result")
    local text = tostring(result.text or "")
    local haystack = normalizedWords(text)
    for _, term in ipairs({ "spieler", "ziel", "aus", "anzeigen", "abbrechen", "anwenden", "ausfuehren" }) do
        assert(not haystack:find(" " .. term .. " ", 1, true), label .. ": German term leaked: " .. term)
    end
    assert(text:find("combat ends", 1, true), label .. ": missing post-combat guidance")
end

local directInput = A.HandleInput("turn off player frame")
assert(directInput and directInput.status == "combat", "HandleInput did not hard-block combat")
assert(handledInputs == 0 and historyWrites == 0 and timerCount == 0, "HandleInput did work in combat")
assertEnglishCombatOutput("HandleInput", directInput)

local submitInput = A.Submit("spieler name aus")
assert(submitInput and submitInput.status == "combat", "Submit did not hard-block combat")
assert(handledInputs == 0 and historyWrites == 0 and timerCount == 0, "Submit did work in combat")
assertEnglishCombatOutput("Submit", submitInput)

local deferredInput = A.SubmitDeferred("turn off player frame", function() deferredCallbacks = deferredCallbacks + 1 end)
assert(deferredInput and deferredInput.status == "combat", "SubmitDeferred did not hard-block combat")
assert(handledInputs == 0 and historyWrites == 0 and deferredCallbacks == 0 and timerCount == 0,
    "SubmitDeferred did work in combat")
assert(A.IsBusy() == false, "SubmitDeferred marked Assistant busy in combat")

-- A combat-paused job owns no event or timer. Merely ending combat must not
-- resume it; the explicit menu activation is the only resume trigger.
local ran, done = 0, false
A.StartJob("combat.paused", { function() ran = ran + 1 end }, function() done = true end)
assert(ran == 0 and done == false and timerCount == 0, "job ran/scheduled in combat")
assert(A._assistantJobsCombatDeferred == true and #A._assistantJobs == 1, "combat job was not preserved")
assert(framesCreated == 0 and eventRegistrations == 0, "combat job registered a PLAYER_REGEN/event frame")

combat = false
assert(ran == 0 and done == false and timerCount == 0, "combat end automatically resumed Assistant work")
A.SetMenuRuntimeActive(true, "menu-reopen")
assert(timerCount == 1 and ran == 0, "menu reopen did not schedule exactly one explicit resume slice")
firePending()
assert(ran == 1 and done == true and #A._assistantJobs == 0, "menu reopen did not resume the job exactly once")

-- A timer already queued before combat is cancelled. Even a forced race callback
-- must recheck combat/menu state before running its step.
ran, done = 0, false
A.StartJob("combat.timer-race", { function() ran = ran + 1 end }, function() done = true end)
local raceTimer = assert(timers[#timers], "pre-combat job timer missing")
combat = true
A.SetMenuRuntimeActive(false, "combat")
assert(raceTimer.cancelled, "combat deactivation did not cancel the job timer")
raceTimer:Fire(true)
assert(ran == 0 and done == false, "cancelled timer race performed work in combat")
local timersAtCombatEnd = timerCount
combat, menuShown = false, false
assert(ran == 0 and timerCount == timersAtCombatEnd, "combat end resumed a hidden-menu job")
A.ResumeCombatDeferredJobs("still-hidden")
assert(ran == 0 and timerCount == timersAtCombatEnd, "manual resume bypassed hidden-menu gate")
menuShown = true
A.SetMenuRuntimeActive(true, "post-combat-menu-reopen")
firePending()
assert(ran == 1 and done == true, "post-combat menu reopen did not resume exactly once")

-- Refresh replay is eventless too.
combat, menuShown = true, true
A._menuRuntimeActive = true
local refreshCount = 0
A.RefreshUI = function() refreshCount = refreshCount + 1 end
local timersBeforeRefresh = timerCount
local refreshOk = A.RequestRefreshUI("combat_refresh")
assert(refreshOk == true and refreshCount == 0 and timerCount == timersBeforeRefresh,
    "combat refresh ran or scheduled a timer")
assert(A._refreshAfterCombat == true and eventRegistrations == 0, "combat refresh registered an event")
combat = false
assert(refreshCount == 0 and timerCount == timersBeforeRefresh, "combat end automatically replayed refresh")
A.SetMenuRuntimeActive(true, "refresh-menu-reopen")
firePending()
assert(refreshCount == 1 and A._refreshAfterCombat == nil, "menu reopen did not replay refresh exactly once")

-- Broad Undo/apply work uses the same central cancellable scheduler. Closing
-- between request and next-frame execution must retain the logical apply, clear
-- timer latches, and re-arm exactly once on an explicit safe reopen.
combat, menuShown = false, true
local broadCallbacks = 0
assert(A.RequestBroadApply("combat-smoke-broad", function() broadCallbacks = broadCallbacks + 1 end) == true,
    "broad apply was not scheduled")
local broadTimer = assert(timers[#timers], "broad apply next-frame timer missing")
assert(A.undoNextFrameQueued == true and A._broadApplyState.scheduled == true, "broad apply did not own queued state")
menuShown = false
A.SetMenuRuntimeActive(false, "broad-hide")
assert(broadTimer.cancelled == true, "menu hide did not cancel broad apply timer")
assert(not A.undoNextFrameQueued, "menu hide retained the Undo scheduler latch")
assert(A._broadApplyState.scheduled == true and broadCallbacks == 0, "menu hide discarded or ran pending broad apply")
broadTimer:Fire(true)
assert(broadCallbacks == 0, "forced cancelled broad callback ran while hidden")
menuShown = true
A.SetMenuRuntimeActive(true, "broad-reopen")
firePending()
assert(broadCallbacks == 1, "explicit reopen did not resume broad apply exactly once")
assert(not A.undoNextFrameQueued and not A._broadApplyState.scheduled and not A._broadApplyState.running,
    "broad apply left a scheduler/running latch after completion")
assert(#(A.undoNextFrameOrder or {}) == 0, "broad apply retained next-frame order entries")

assert(A.RequestBroadApply("combat-smoke-broad-second", function() broadCallbacks = broadCallbacks + 1 end) == true,
    "second broad apply could not schedule after resume")
firePending()
assert(broadCallbacks == 2, "second broad apply did not complete")

menuShown = false
A.SetMenuRuntimeActive(false, "broad-hidden-direct")
assert(A.RequestBroadApply("combat-smoke-hidden", function() broadCallbacks = broadCallbacks + 1 end) == false,
    "hidden direct broad apply reported scheduled")
assert(not A._broadApplyState.scheduled and not A.undoNextFrameQueued,
    "hidden direct broad apply stranded scheduler state")
menuShown = true
A.SetMenuRuntimeActive(true, "broad-hidden-direct-reopen")
assert(broadCallbacks == 2, "failed hidden broad apply unexpectedly replayed")

combat = true
for _, api in ipairs({
    "RecordPerfSample", "RecordSlowPerfSample", "GetLastPerfSample", "GetLastSlowPerfSample",
    "GetPerfTrace", "ClearPerfTrace", "PerformanceWarmupStatusText",
}) do
    assert(A[api] == nil, "removed built-in profiler API returned: " .. api)
end
assert(A._perfTrace == nil and A.lastAssistantPerf == nil and A.lastSlowAssistantPerf == nil,
    "removed built-in profiler state returned")

assert(type(A.WarmupPerformanceIndexes) ~= "function" and type(A.CancelPerformanceWarmup) ~= "function",
    "removed background warmup job API returned")
assert(not (type(A._assistantJobs) == "table" and #A._assistantJobs > 0), "combat path retained a job")

_G.MSUF_GlobalDB = { global = {} }
local recorded = A.RecordNoMatch("combat unknown setting", { status = "failed" }, "combat-smoke")
assert(recorded == nil and _G.MSUF_GlobalDB.global.assistantNoMatch == nil,
    "NoMatch telemetry recorded in combat")

combat, menuShown = false, true
A.SetMenuRuntimeActive(true, "telemetry-menu-open")
recorded = A.RecordNoMatch("target mystery anchor", { status = "failed" }, "combat-smoke")
assert(type(recorded) == "table" and recorded.owner == "anchor-intent" and recorded.candidate == "Anchor wording",
    "out-of-combat NoMatch classification failed")

assert(framesCreated == 0 and eventRegistrations == 0 and onUpdates == 0,
    "Assistant combat scheduler owns an event frame or OnUpdate")
print(("assistant_combat_smoke: ok timers=%d events=%d frames=%d"):format(timerCount, eventRegistrations, framesCreated))
