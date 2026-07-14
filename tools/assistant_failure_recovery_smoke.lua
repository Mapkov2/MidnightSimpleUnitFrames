_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local root = exists("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_Assistant.lua") and "." or ".."
local menuShown = true
local openedPages = {}
local Registry = {}
function Registry:GetSetting() return nil end
function Registry:GetAction(key)
    if key ~= "open_page" then return nil end
    return {
        key = "open_page",
        label = "Open MSUF Page",
        mutability = "navigation",
        run = function(args)
            openedPages[#openedPages + 1] = tostring(args and args.page or "")
            return true, "Opened " .. tostring(args and args.label or args and args.page or "MSUF page") .. "."
        end,
    }
end
local MSUF = {
    MSUF2 = { frame = { IsShown = function() return menuShown end } },
    Assistant = { Registry = Registry },
}
_G.MSUF_NS, _G.MSUF2 = MSUF, MSUF.MSUF2
_G.GetTime = function() return os.clock() end
_G.GetTimePreciseSec = function() return os.clock() end
_G.InCombatLockdown = function() return false end
_G.UnitAffectingCombat = function() return false end

local timers = {}
local timerMode = "normal"
_G.C_Timer = {
    NewTimer = function(_, callback)
        if timerMode == "throw" then error("synthetic runtime NewTimer failure") end
        if timerMode == "nil" then return nil end
        if timerMode == "sync_nil" then callback(); return nil end
        local timer = { callback = callback, cancelled = false, fired = false }
        function timer:Cancel() self.cancelled = true end
        timers[#timers + 1] = timer
        return timer
    end,
    After = function() error("failure recovery used non-cancellable C_Timer.After") end,
    NewTicker = function() error("failure recovery created a ticker") end,
}

local function fireAll(limit)
    local fired = 0
    while fired < (limit or 20) do
        local nextTimer
        for i = 1, #timers do
            if not timers[i].cancelled and not timers[i].fired then nextTimer = timers[i]; break end
        end
        if not nextTimer then return fired end
        nextTimer.fired = true
        nextTimer.callback()
        fired = fired + 1
    end
    error("failure recovery timers did not quiesce")
end

local inputChunk, inputLoadError = loadfile(root .. "/MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_ActionInputs.lua")
assert(inputChunk, inputLoadError)
inputChunk("MidnightSimpleUnitFrames_Assistant", MSUF)

local chunk, loadError = loadfile(root .. "/MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_Assistant.lua")
assert(chunk, loadError)
chunk("MidnightSimpleUnitFrames_Assistant", MSUF)

local A = assert(MSUF.Assistant, "Assistant namespace missing")
local AP = assert(A.RuntimePrivate, "Assistant runtime-private namespace missing")

-- The bridge hands its promoted first message to this public scheduler. A
-- broken timer API must execute that accepted callback once, report success,
-- and reset its queue state; returning a fake success without doing the work
-- loses the first message, while returning false after doing it duplicates it.
for _, mode in ipairs({ "throw", "nil", "sync_nil" }) do
    timerMode = mode
    local submits = 0
    local ok, accepted = pcall(A.ScheduleMenuRuntimeNextFrame, "assistant.scheduler." .. mode, function()
        submits = submits + 1
    end)
    assert(ok and accepted == true, mode .. ": runtime scheduler did not contain the timer failure")
    assert(submits == 1, mode .. ": accepted first-message callback did not run exactly once")
    assert(AP.nextFrameQueued == false and AP.nextFrameTimer == nil,
        mode .. ": runtime scheduler stayed pinned after timer failure")
end
timerMode = "normal"
local normalSubmits = 0
assert(A.ScheduleMenuRuntimeNextFrame("assistant.scheduler.normal", function()
    normalSubmits = normalSubmits + 1
end) == true, "normal runtime scheduler rejected a valid callback")
assert(normalSubmits == 0, "normal runtime scheduler did not defer the callback")
fireAll()
assert(normalSubmits == 1, "normal runtime scheduler did not run the callback exactly once")

local history, refreshes = {}, 0
A.AddHistory = function(role, text, status, summary)
    history[#history + 1] = { role = role, text = text, status = status, summary = summary }
end
A.GetHistory = function() return history end

local function control()
    local value = { enabled = false }
    function value:Enable() self.enabled = true end
    function value:SetText(text) self.text = text end
    function value:SetFocus() self.focused = true end
    return value
end

local busyTimer = { cancelled = false }
function busyTimer:Cancel() self.cancelled = true end
A.dashboardUI = {
    input = control(),
    send = control(),
    _msufAssistantBusyTimer = busyTimer,
    _msufAssistantBusyPulse = true,
}
A._menuRuntimeTimers = { ["assistant.dashboard.busy"] = busyTimer }
A.RefreshUI = function()
    local ui = A.dashboardUI
    if not ui or A.IsBusy() then return end
    if ui.input and ui.input.Enable then ui.input:Enable() end
    if ui.send and ui.send.Enable then ui.send:Enable() end
    if ui.send and ui.send.SetText then ui.send:SetText("Send") end
end
A.RequestRefreshUI = function()
    refreshes = refreshes + 1
    A.RefreshUI()
    return true
end

local query = "change the grow direction of player buffs"
local originalBuild = AP.BuildDeferredSubmitSteps
AP.BuildDeferredSubmitSteps = function() error("synthetic pre-job failure") end
A._busy = false
local callbackCount, callbackResult = 0, nil
local recovered = A.SubmitDeferred(query, function(result)
    callbackCount = callbackCount + 1
    callbackResult = result
end)
AP.BuildDeferredSubmitSteps = originalBuild

assert(type(recovered) == "table" and recovered.status == "failed", "pre-job exception did not return a normal failure result")
assert(tostring(recovered.text):find("Sorry", 1, true), "failure response is missing a human apology")
assert(tostring(recovered.text):find("Assistant recovered and is still ready", 1, true), "failure response does not explain recovery")
assert(tostring(recovered.text):find("Aura Style: Buffs", 1, true), "failure response did not suggest the likely aura page")
assert(tostring(recovered.text):find("Player", 1, true) and tostring(recovered.text):find("Growth", 1, true),
    "failure response did not retain the prompt's scope and control")
assert(type(recovered.searchResults) == "table" and recovered.searchResults[1].page == "auras3_buffs",
    "failure response did not provide an openable best-effort page")
assert(callbackCount == 1 and callbackResult == recovered, "deferred failure callback was not completed exactly once")
assert(A.IsBusy() == false, "pre-job exception left the Assistant busy")
assert(A.dashboardUI.input.enabled and A.dashboardUI.send.enabled, "pre-job exception left Dashboard input disabled")
assert(A.dashboardUI.input.focused and A.dashboardUI.send.text == "Send", "Dashboard input state was not restored")
assert(busyTimer.cancelled and A.dashboardUI._msufAssistantBusyTimer == nil and A.dashboardUI._msufAssistantBusyPulse == nil,
    "failure recovery left the busy pulse alive")
assert(#history == 2 and history[1].role == "user" and history[1].text == query and history[2].role == "assistant",
    "failure recovery did not preserve a single user/assistant turn")
assert(refreshes > 0, "failure recovery did not request a Dashboard refresh")

-- A parser/router exception is normalized inside a real deferred job. The job
-- pump must finish, restore the Dashboard, and record exactly one apology.
history = {}
A.pendingResults = nil
A.dashboardUI.input.enabled, A.dashboardUI.input.focused = false, false
A.dashboardUI.send.enabled, A.dashboardUI.send.text = false, "Stop"
A.RouteInput = function() error("synthetic router failure") end
local routedCallbackCount, routedResult = 0, nil
local routedQueued = A.SubmitDeferred(query, function(result)
    routedCallbackCount = routedCallbackCount + 1
    routedResult = result
end)
assert(type(routedQueued) == "table" and routedQueued.status == "queued", "router failure did not enter the deferred job pump")
assert(A.IsBusy() == true, "deferred router failure was not busy before its job slice")
fireAll()
assert(type(routedResult) == "table" and routedResult.status == "failed", "router exception escaped the deferred job")
assert(routedCallbackCount == 1, "router exception did not complete its deferred callback exactly once")
assert(A.IsBusy() == false, "router exception left the deferred Assistant busy")
assert(A.dashboardUI.input.enabled and A.dashboardUI.send.enabled and A.dashboardUI.send.text == "Send",
    "router exception did not restore Dashboard controls")
local apologyCount, assistantCount = 0, 0
for i = 1, #history do
    if history[i].role == "assistant" then
        assistantCount = assistantCount + 1
        if tostring(history[i].text):find("Sorry", 1, true) then apologyCount = apologyCount + 1 end
    end
end
assert(#history == 2 and history[1].role == "user" and assistantCount == 1 and apologyCount == 1,
    "router exception did not record exactly one user turn and one apology")
assert(tostring(routedResult.text):find("Aura Style: Buffs", 1, true), "router exception lost local page suggestions")

-- Once the broken router is available again, the normal pending-result path
-- must understand both a numeric choice and the natural "open it" follow-up.
A.RouteInput = function(text, fallback) return fallback(text) end
local openedByNumber = A.Submit("1")
assert(type(openedByNumber) == "table" and openedByNumber.status == "navigated", "numeric fallback choice was not navigated")
assert(openedPages[#openedPages] == "auras3_buffs", "numeric fallback choice opened the wrong page")
local openedNaturally = A.Submit("open it")
assert(type(openedNaturally) == "table" and openedNaturally.status == "navigated", "'open it' did not reuse the fallback result")
assert(openedPages[#openedPages] == "auras3_buffs" and #openedPages == 2, "'open it' did not open the suggested page")
A.RouteInput = nil

-- A completion callback can also fail after a job step. It must not pin the
-- UI in busy state or leave a timer/ticker source behind.
history = {}
A.dashboardUI.input.enabled, A.dashboardUI.input.focused = false, false
A.dashboardUI.send.enabled, A.dashboardUI.send.text = false, "Stop"
A._busy = true
A.StartJob("assistant.submit", {
    function() return { text = "synthetic result", status = "info" } end,
}, function()
    error("synthetic completion failure")
end, { requestText = query })

fireAll()
assert(A.IsBusy() == false, "completion exception left the Assistant busy")
assert(A.dashboardUI.input.enabled and A.dashboardUI.send.enabled and A.dashboardUI.send.text == "Send",
    "completion exception did not restore Dashboard controls")
assert(type(A.lastAssistantJobError) == "table" and tostring(A.lastAssistantJobError.message):find("synthetic completion failure", 1, true),
    "completion exception was not retained for diagnostics")

io.write("assistant_failure_recovery_smoke: ok\n")
