--- MSUF_Scheduler.lua - central next-frame scheduler
--- Replaces scattered C_Timer.After(0, ...) runtime deferrals with keyed,
--- deduped scheduling. Secret-safe: no protected/secret API reads here.

local addonName, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS or {})

local C_Timer = _G.C_Timer
local type = type
local pcall = pcall

local function ReportCallbackError(err)
    local handler = _G.geterrorhandler and _G.geterrorhandler()
    if type(handler) == "function" then
        local reported = pcall(handler, err)
        if reported then return end
    end
    if type(_G.print) == "function" then
        _G.print("|cffffd700MSUF Scheduler:|r", tostring(err))
    end
end

local function InvokeCallback(fn)
    local ok, err = pcall(fn)
    if not ok then ReportCallbackError(err) end
end

local Scheduler = MSUF.Scheduler or {}
MSUF.Scheduler = Scheduler

local pending = Scheduler.pending or {}
local queue = Scheduler.queue or {}
Scheduler.pending = pending
Scheduler.queue = queue
Scheduler.head = Scheduler.head or 1
Scheduler.tail = Scheduler.tail or 0

local frame = Scheduler.frame
if not frame and _G.CreateFrame then
    frame = _G.CreateFrame("Frame", "MSUF_SchedulerFrame")
    Scheduler.frame = frame
end

local FlushNextFrame
local function ArmNextFrame()
    if frame then
        frame:SetScript("OnUpdate", FlushNextFrame)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, FlushNextFrame)
    else
        FlushNextFrame()
    end
end

--- PERF (4.22 Beta hotfix): Re-entry safety + leftover preservation.
---
--- Problem: callbacks executed inside this loop can re-schedule via
--- ScheduleOnce/RunNextFrame. Without a snapshot of `tail` taken BEFORE the
--- loop, the loop would extend itself within the same frame --- this is the
--- runaway pattern that produced 1739x amplification on GROUP_ROSTER_UPDATE
--- bursts and 67ms frame stalls in the prior trace.
---
--- We snapshot `snapshotTail` once. Items appended during this flush land at
--- queue[snapshotTail+1..Scheduler.tail] and are NOT processed this frame.
--- Without explicit handling those leftovers would be silently dropped when
--- we reset Scheduler.head/tail. So we compact them to the front and
--- re-arm the OnUpdate driver for the next frame.
---
--- Net result: one schedule = one execution per frame, no re-entry storm,
--- no lost work. Pure Lua state --- secret-safe by construction.
function FlushNextFrame()
    if frame then
        frame:SetScript("OnUpdate", nil)
    end
    Scheduler.nextFrameActive = false

    local head = Scheduler.head or 1
    local snapshotTail = Scheduler.tail or 0

    --- Each queued callback is a fault boundary. Report failures through the
    --- normal error handler, but always finish the drain/compaction bookkeeping
    --- so one feature cannot strand unrelated next-frame work.
    while head <= snapshotTail do
        local key = queue[head]
        queue[head] = nil
        head = head + 1
        Scheduler.head = head

        if key ~= nil then
            local cb = pending[key]
            pending[key] = nil
            if type(cb) == "function" then InvokeCallback(cb) end
        end
    end

    --- Items appended during the flush (snapshotTail+1 .. Scheduler.tail).
    --- Compact them to the head of the queue and arm next-frame flush.
    local liveTail = Scheduler.tail or 0
    if liveTail >= head then
        local writeIdx = 0
        for i = head, liveTail do
            local key = queue[i]
            queue[i] = nil
            if key ~= nil then
                writeIdx = writeIdx + 1
                queue[writeIdx] = key
            end
        end
        if writeIdx <= 0 then
            Scheduler.head, Scheduler.tail = 1, 0
            return
        end
        Scheduler.head = 1
        Scheduler.tail = writeIdx
        if not Scheduler.nextFrameActive then
            Scheduler.nextFrameActive = true
            ArmNextFrame()
        end
    else
        Scheduler.head, Scheduler.tail = 1, 0
    end
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

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

ExportPublic("MSUF_Scheduler", Scheduler)
ExportPublic("MSUF_RunNextFrame", Scheduler.RunNextFrame)
ExportPublic("MSUF_ScheduleOnce", Scheduler.ScheduleOnce)
ExportPublic("MSUF_Core_RunNextFrame", _G.MSUF_Core_RunNextFrame or Scheduler.RunNextFrame)
