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

local ExportPublic = MSUF.ExportPublic

ExportPublic("MSUF_Scheduler", Scheduler)
ExportPublic("MSUF_RunNextFrame", Scheduler.RunNextFrame)
ExportPublic("MSUF_ScheduleOnce", Scheduler.ScheduleOnce)
ExportPublic("MSUF_Core_RunNextFrame", Scheduler.RunNextFrame)
