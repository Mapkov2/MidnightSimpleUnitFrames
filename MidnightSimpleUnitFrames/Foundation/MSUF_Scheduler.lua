-- MSUF_Scheduler.lua — central next-frame / delayed scheduler
-- Replaces scattered C_Timer.After(0, ...) runtime deferrals with keyed,
-- deduped scheduling. Secret-safe: no protected/secret API reads here.

local addonName, ns = ...
ns = ns or (_G.MSUF_NS or {})
_G.MSUF_NS = ns

local C_Timer = _G.C_Timer
local type = type

local Scheduler = ns.Scheduler or {}
ns.Scheduler = Scheduler

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

local function FlushNextFrame()
    if frame then frame:SetScript("OnUpdate", nil) end
    Scheduler.nextFrameActive = false

    local head = Scheduler.head or 1
    local tail = Scheduler.tail or 0
    while head <= tail do
        local key = queue[head]
        queue[head] = nil
        head = head + 1

        local cb = pending[key]
        pending[key] = nil
        if type(cb) == "function" then cb() end
    end
    Scheduler.head, Scheduler.tail = 1, 0
end

local function QueueNextFrame(key, fn)
    if pending[key] then return end

    pending[key] = fn
    local tail = (Scheduler.tail or 0) + 1
    Scheduler.tail = tail
    queue[tail] = key

    if frame then
        if not Scheduler.nextFrameActive then
            Scheduler.nextFrameActive = true
            frame:SetScript("OnUpdate", FlushNextFrame)
        end
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, FlushNextFrame)
    else
        FlushNextFrame()
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

function Scheduler.ScheduleDelayOnce(key, delay, fn)
    if type(fn) ~= "function" then return end
    key = key or fn
    if pending[key] then return end
    pending[key] = fn

    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0, function()
            local cb = pending[key]
            pending[key] = nil
            if type(cb) == "function" then cb() end
        end)
    else
        local cb = pending[key]
        pending[key] = nil
        if type(cb) == "function" then cb() end
    end
end

_G.MSUF_Scheduler = Scheduler
_G.MSUF_RunNextFrame = Scheduler.RunNextFrame
_G.MSUF_ScheduleOnce = Scheduler.ScheduleOnce
_G.MSUF_ScheduleDelayOnce = Scheduler.ScheduleDelayOnce
_G.MSUF_Core_RunNextFrame = _G.MSUF_Core_RunNextFrame or Scheduler.RunNextFrame
