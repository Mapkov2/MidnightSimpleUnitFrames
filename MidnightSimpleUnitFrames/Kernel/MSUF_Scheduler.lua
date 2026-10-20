--- MSUF_Scheduler.lua - central next-frame scheduler
--- Replaces scattered C_Timer.After(0, ...) runtime deferrals with keyed,
--- deduped scheduling. Secret-safe: no protected/secret API reads here.
---
--- Two keyed policies, deliberately different (pinned by
--- tools/tests/scheduler_pending_key_policy_smoke.lua):
---   * RunNextFrame / ScheduleOnce: the FIRST function queued for a key wins.
---     While the key is pending, further calls are ignored whatever function
---     they pass; the key is free again once the callback has been taken from
---     the queue (before it runs), so a callback can queue its own key again.
---     The key defaults to the function, so one function queued twice runs once.
---   * ScheduleAfter / ScheduleAt: the LAST function and the LAST deadline win
---     (debounce). Every call replaces the pending function and moves the deadline.
--- The two keep separate tables: one key can be pending in both, and
--- IsScheduled / CancelScheduled only see delayed work.

local addonName, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS or {})

local type = type
local C_Timer = _G.C_Timer

local Scheduler = MSUF.Scheduler or {}
MSUF.Scheduler = Scheduler

local pending = Scheduler.pending or {}
local queue = Scheduler.queue or {}
Scheduler.pending = pending
Scheduler.queue = queue
Scheduler.head = Scheduler.head or 1
Scheduler.tail = Scheduler.tail or 0

local frame = Scheduler.frame or _G.CreateFrame("Frame", "MSUF_SchedulerFrame")
Scheduler.frame = frame

local FlushNextFrame
local function ArmNextFrame()
    frame:SetScript("OnUpdate", FlushNextFrame)
end

-- Each callback runs through secureexecuterange (every client: Blizzard's
-- CallbackRegistry dispatches with it): an error goes to the error handler and
-- the next callback still runs in the same frame. One reusable slot per call
-- site keeps this allocation-free. A harness without it calls directly.
local RunEach = _G.secureexecuterange
if type(RunEach) ~= "function" then
    RunEach = function(list, fn, ...)
        for i = 1, #list do fn(i, list[i], ...) end
    end
end
local function Call(_, callback) callback() end
local queuedSlot, delayedSlot = {}, {}
local function RunIsolated(slot, callback)
    slot[1] = callback
    RunEach(slot, Call)
    slot[1] = nil
end

-- Keep the driver armed until the queue is drained. Advance/remove the current
-- item before calling it: an error is visible and the queue continues at the
-- next item without replaying the failure or stranding pending work.
function FlushNextFrame()
    local head = Scheduler.head or 1
    local snapshotTail = Scheduler.tail or 0
    while head <= snapshotTail do
        local key = queue[head]
        queue[head] = nil
        head = head + 1
        Scheduler.head = head
        if key ~= nil then
            local callback = pending[key]
            pending[key] = nil
            if callback then RunIsolated(queuedSlot, callback) end
        end
    end
    local liveTail = Scheduler.tail or 0
    if liveTail >= head then
        local count = 0
        for i = head, liveTail do
            local key = queue[i]
            queue[i] = nil
            if key ~= nil then
                count = count + 1
                queue[count] = key
            end
        end
        Scheduler.head, Scheduler.tail = 1, count
        if count > 0 then return end
    else
        Scheduler.head, Scheduler.tail = 1, 0
    end
    Scheduler.nextFrameActive = false
    frame:SetScript("OnUpdate", nil)
end

-- First function wins: a key that is already pending keeps its function.
local function QueueNextFrame(key, fn)
    if pending[key] then return end

    pending[key] = fn
    local tail = (Scheduler.tail or 0) + 1
    Scheduler.tail = tail
    queue[tail] = key

    if not Scheduler.nextFrameActive then
        Scheduler.nextFrameActive = true
        ArmNextFrame()
    end
end

--- Next-frame run deduped by the function itself (the key is fn).
function Scheduler.RunNextFrame(fn)
    assert(type(fn) == "function", "MSUF scheduler requires a callback function")
    QueueNextFrame(fn, fn)
end

--- Next-frame run deduped by key; the first function queued for a pending key
--- is the one that runs (see the policy note at the top of this file).
function Scheduler.ScheduleOnce(key, fn)
    assert(type(fn) == "function", "MSUF scheduler requires a callback function")
    key = key or fn
    QueueNextFrame(key, fn)
end

--- Delayed keyed scheduling.
---
--- 12.1.5 and Forever ship C_Timer.NewTimedSignalMap: one native callback map
--- drives many keyed deadlines, and a key is rescheduled by signalling it again
--- instead of being cancelled and recreated. That drops the per-call closure and
--- timer object C_Timer.After allocates, which is what matters here - the dense
--- callers fire in bursts (target swap, roster change, menu refresh), not steadily.
---
--- One numeric signal key is registered per logical key and kept for the
--- session. TimerUtil retains registered callbacks for the map's lifetime, so
--- registering per call would leak; after the first use a reschedule costs one
--- signal call plus one table store and allocates nothing. Keys are therefore
--- meant to be stable identities (a string, a module table, a frame), never a
--- value minted per call. Delays and deadlines are public numbers only.
---
--- Clients without the map (Midnight 12.1.0 live, every Classic client)
--- use C_Timer.After with one runner closure cached per key, so a reschedule
--- allocates nothing there either: a superseded timer still fires, and only the
--- timer that is due (or the last one outstanding) runs the work.
local delayedPending = Scheduler.delayedPending or {}
local delayedKeys = Scheduler.delayedKeys or {}
local delayedRunners = Scheduler.delayedRunners or {}
local delayedOutstanding = Scheduler.delayedOutstanding or {}
local delayedDeadline = Scheduler.delayedDeadline or {}
Scheduler.delayedPending = delayedPending
Scheduler.delayedKeys = delayedKeys
Scheduler.delayedRunners = delayedRunners
Scheduler.delayedOutstanding = delayedOutstanding
Scheduler.delayedDeadline = delayedDeadline

local signalMap = Scheduler.signalMap
if signalMap == nil then
    -- TimerUtil only wraps the native constructor: require that too.
    local timerUtil = _G.TimerUtil
    if C_Timer and C_Timer.NewTimedSignalMap and timerUtil and timerUtil.CreateTimedSignalCallbackMap then
        signalMap = timerUtil.CreateTimedSignalCallbackMap()
    else
        signalMap = false
    end
    Scheduler.signalMap = signalMap
end

-- Resolve the supported timer backend once. Missing platform services are a
-- startup error; a delayed callback must never silently become synchronous.
local after
local GetTime = _G.GetTime
if not signalMap then
    after = assert(C_Timer and C_Timer.After, "MSUF scheduler requires C_Timer.After")
end

local function RunDelayed(key)
    local fn = delayedPending[key]
    if fn == nil then return end
    delayedPending[key] = nil
    RunIsolated(delayedSlot, fn)
end

local function SignalKey(key)
    local signalKey = delayedKeys[key]
    if signalKey == nil then
        signalKey = signalMap:RegisterCallback(function() RunDelayed(key) end)
        delayedKeys[key] = signalKey
    end
    return signalKey
end

--- Schedule fn under key after delay seconds. A second call for the same key
--- replaces both the pending function and its deadline (the last call wins),
--- which is the debounce shape most C_Timer.After callers hand-rolled with a
--- guard flag. This is the opposite of ScheduleOnce, whose first function wins.
function Scheduler.ScheduleAfter(key, delay, fn)
    assert(type(fn) == "function", "MSUF scheduler requires a callback function")
    key = key or fn
    assert(type(delay) == "number" and delay >= 0 and delay < math.huge,
        "MSUF scheduler requires a finite, non-negative delay")
    delayedPending[key] = fn

    if signalMap then
        signalMap:SignalAfter(SignalKey(key), delay)
        return true
    end

    -- Without TimedSignalMap a pending C_Timer.After cannot be replaced. The
    -- runner of a timer that fires before the newest deadline steps aside while
    -- another timer is still outstanding; the last one always runs the work, so
    -- a clock disagreement can only delay it, never drop it.
    local runner = delayedRunners[key]
    if runner == nil then
        runner = function()
            local outstanding = (delayedOutstanding[key] or 1) - 1
            delayedOutstanding[key] = outstanding
            if delayedPending[key] == nil then return end
            if outstanding > 0 and (not GetTime or GetTime() + 0.001 < delayedDeadline[key]) then return end
            RunDelayed(key)
        end
        delayedRunners[key] = runner
    end
    delayedOutstanding[key] = (delayedOutstanding[key] or 0) + 1
    delayedDeadline[key] = GetTime and (GetTime() + delay) or 0
    after(delay, runner)
    return true
end

--- ScheduleAfter's policy for an absolute GetTime() deadline (a GetTimePreciseSec
--- caller passes a delay instead); a past deadline is clamped to now.
function Scheduler.ScheduleAt(key, at, fn)
    assert(type(fn) == "function", "MSUF scheduler requires a callback function")
    key = key or fn
    assert(type(at) == "number" and at > -math.huge and at < math.huge,
        "MSUF scheduler requires a finite deadline")
    local now = GetTime()
    if signalMap then
        delayedPending[key] = fn
        signalMap:SignalAt(SignalKey(key), at > now and at or now)
        return true
    end
    local delay = at - now
    return Scheduler.ScheduleAfter(key, delay > 0 and delay or 0, fn)
end

function Scheduler.CancelScheduled(key)
    if key == nil then return false end
    local had = delayedPending[key] ~= nil
    delayedPending[key] = nil
    local signalKey = delayedKeys[key]
    if signalMap and signalKey ~= nil then
        signalMap:CancelSignal(signalKey)
    end
    return had
end

function Scheduler.IsScheduled(key)
    return key ~= nil and delayedPending[key] ~= nil
end


local ExportPublic = MSUF.ExportPublic

ExportPublic("MSUF_Scheduler", Scheduler)
ExportPublic("MSUF_RunNextFrame", Scheduler.RunNextFrame)
ExportPublic("MSUF_ScheduleOnce", Scheduler.ScheduleOnce)
--- Deprecated compatibility alias of MSUF_RunNextFrame, kept for external callers.
ExportPublic("MSUF_Core_RunNextFrame", Scheduler.RunNextFrame)
MSUF.Compat = MSUF.Compat or {}
MSUF.Compat.DeprecatedAliases = MSUF.Compat.DeprecatedAliases or {}
MSUF.Compat.DeprecatedAliases.MSUF_Core_RunNextFrame = "MSUF_RunNextFrame"

ExportPublic("MSUF_ScheduleAfter", Scheduler.ScheduleAfter)
ExportPublic("MSUF_CancelScheduled", Scheduler.CancelScheduled)
