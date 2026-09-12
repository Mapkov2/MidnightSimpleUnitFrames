--- MSUF_Scheduler.lua - central next-frame scheduler
--- Replaces scattered C_Timer.After(0, ...) runtime deferrals with keyed,
--- deduped scheduling. Secret-safe: no protected/secret API reads here.

local addonName, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS or {})

local type = type

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

-- Keep the driver armed until the queue is drained. Advance/remove the current
-- item before calling it: an error is visible and the next frame can continue
-- at the next item without replaying the failure or stranding pending work.
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
            if callback then callback() end
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

function Scheduler.RunNextFrame(fn)
    if type(fn) ~= "function" then return end
    QueueNextFrame(fn, fn)
end

function Scheduler.ScheduleOnce(key, fn)
    if type(fn) ~= "function" then return end
    key = key or fn
    QueueNextFrame(key, fn)
end

--- Delayed keyed scheduling.
---
--- 12.1.5 ships TimedSignalMap: one native callback map drives many keyed
--- deadlines, and a key is rescheduled by signalling it again instead of being
--- cancelled and recreated. That drops the per-call closure and timer object
--- C_Timer.After allocates, which is what matters here - the dense callers fire
--- in bursts (target swap, roster change, menu refresh), not steadily.
---
--- One numeric signal key is registered per logical key and kept for the
--- session. TimerUtil retains registered callbacks for the map's lifetime, so
--- registering per call would leak; after the first use a reschedule costs one
--- SignalAfter plus one table store and allocates nothing. Keys are therefore
--- meant to be stable identities (a string, a module table, a frame), never a
--- value minted per call.
local delayedPending = Scheduler.delayedPending or {}
local delayedKeys = Scheduler.delayedKeys or {}
local delayedGenerations = Scheduler.delayedGenerations or {}
Scheduler.delayedPending = delayedPending
Scheduler.delayedKeys = delayedKeys
Scheduler.delayedGenerations = delayedGenerations

local signalMap = Scheduler.signalMap
if signalMap == nil then
    local timerUtil = _G.TimerUtil
    if timerUtil and type(timerUtil.CreateTimedSignalCallbackMap) == "function" then
        signalMap = timerUtil.CreateTimedSignalCallbackMap()
    else
        signalMap = false
    end
    Scheduler.signalMap = signalMap
end

local function RunDelayed(key)
    local fn = delayedPending[key]
    if fn == nil then return end
    delayedPending[key] = nil
    fn()
end

--- Schedule fn under key after delay seconds. A second call for the same key
--- replaces both the pending function and its deadline, which is the debounce
--- shape most C_Timer.After callers hand-rolled with a guard flag.
function Scheduler.ScheduleAfter(key, delay, fn)
    if type(fn) ~= "function" then return false end
    key = key or fn
    delay = tonumber(delay) or 0
    if delay < 0 then delay = 0 end
    delayedPending[key] = fn

    if signalMap then
        local signalKey = delayedKeys[key]
        if signalKey == nil then
            signalKey = signalMap:RegisterCallback(function() RunDelayed(key) end)
            delayedKeys[key] = signalKey
        end
        signalMap:SignalAfter(signalKey, delay)
        return true
    end

    -- Without TimedSignalMap a pending C_Timer.After cannot be replaced, so a
    -- generation counter retires the stale one instead of cancelling it.
    local generation = (delayedGenerations[key] or 0) + 1
    delayedGenerations[key] = generation
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, function()
            if delayedGenerations[key] ~= generation then return end
            RunDelayed(key)
        end)
        return true
    end
    RunDelayed(key)
    return true
end

function Scheduler.CancelScheduled(key)
    if key == nil then return false end
    local had = delayedPending[key] ~= nil
    delayedPending[key] = nil
    local signalKey = delayedKeys[key]
    if signalMap and signalKey ~= nil then
        signalMap:CancelSignal(signalKey)
    else
        delayedGenerations[key] = (delayedGenerations[key] or 0) + 1
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
ExportPublic("MSUF_Core_RunNextFrame", Scheduler.RunNextFrame)

ExportPublic("MSUF_ScheduleAfter", Scheduler.ScheduleAfter)
ExportPublic("MSUF_CancelScheduled", Scheduler.CancelScheduled)
