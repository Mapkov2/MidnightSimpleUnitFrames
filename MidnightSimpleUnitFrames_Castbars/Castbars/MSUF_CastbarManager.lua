-- Castbars/MSUF_CastbarManager.lua
-- Step 5: Dense ActiveSet (array + swap-remove) for lower iteration overhead and fewer hash ops.
-- Scheduler-only: no UI ownership here. All visuals/time text remain in MSUF_UpdateCastbarFrame.

local manager = _G.MSUF_CastbarManager3
if not manager then
    manager = CreateFrame("Frame", "MSUF_CastbarManager3", UIParent)
    _G.MSUF_CastbarManager3 = manager
end

-- Dense ActiveSet
manager._active = manager._active or {}
manager._activeCount = manager._activeCount or 0

-- Re-entrancy safe queues (Register/Unregister can be called from inside DriverTick)
manager._pendingAdd = manager._pendingAdd or {}
manager._pendingAddCount = manager._pendingAddCount or 0
manager._pendingRemove = manager._pendingRemove or {}
manager._pendingRemoveCount = manager._pendingRemoveCount or 0

manager._msufStamp = manager._msufStamp or 0
manager:Hide()

local function Now()
    return (GetTimePreciseSec and GetTimePreciseSec()) or GetTime()
end

local function ShouldTickFrame(frame)
    -- Hard gate (perf): only tick when we have work.
    -- Warm ticks allow the initial 1-2 ticks to bootstrap visibility/state on target/focus/boss.
    local warm = frame._msufManagerWarmTicks or 0
    if warm > 0 then
        frame._msufManagerWarmTicks = warm - 1
        return true
    end
    return (frame._msufAppliedActive == true) or (frame.MSUF_timerDriven == true)
end

local function RemoveAt(list, count, i, frame)
    local last = list[count]
    if i ~= count then
        list[i] = last
        if last then
            last._msufManagerIndex = i
        end
    end
    list[count] = nil

    if frame then
        frame._msufManagerIndex = nil
        frame._msufManagerIdleStreak = nil
        frame._msufManagerWarmTicks = nil
    end

    return count - 1
end

local function IsActive(list, frame)
    local idx = frame._msufManagerIndex
    return (idx and list[idx] == frame) and idx or nil
end

local function RegisterImmediate(frame)
    local list = manager._active
    local idx = IsActive(list, frame)
    if not idx then
        local count = manager._activeCount + 1
        list[count] = frame
        manager._activeCount = count
        frame._msufManagerIndex = count
    end

    frame._msufManagerWarmTicks = 4
    frame._msufManagerIdleStreak = nil
    frame._msufNextTick = 0

    manager:Show()
end

local function UnregisterImmediate(frame)
    local list = manager._active
    local count = manager._activeCount
    local idx = IsActive(list, frame)
    if not idx or count <= 0 then
        frame._msufManagerIndex = nil
        frame._msufManagerIdleStreak = nil
        frame._msufManagerWarmTicks = nil
        return
    end

    manager._activeCount = RemoveAt(list, count, idx, frame)
    if manager._activeCount <= 0 then
        manager:Hide()
    end
end

local function QueueAdd(frame)
    if frame._msufManagerPendingAdd then return end
    frame._msufManagerPendingAdd = true

    local n = (manager._pendingAddCount or 0) + 1
    manager._pendingAddCount = n
    manager._pendingAdd[n] = frame
end

local function QueueRemove(frame)
    if frame._msufManagerPendingRemove then return end
    frame._msufManagerPendingRemove = true

    local n = (manager._pendingRemoveCount or 0) + 1
    manager._pendingRemoveCount = n
    manager._pendingRemove[n] = frame
end

local function FlushQueues(list, count)
    -- Remove first so a remove+add in same tick ends up registered (stable behavior for "restart" paths).
    local prCount = manager._pendingRemoveCount or 0
    if prCount > 0 then
        local pr = manager._pendingRemove
        for k = 1, prCount do
            local f = pr[k]
            pr[k] = nil
            if f then
                f._msufManagerPendingRemove = nil
                local idx = IsActive(list, f)
                if idx then
                    count = RemoveAt(list, count, idx, f)
                else
                    f._msufManagerIndex = nil
                    f._msufManagerIdleStreak = nil
                    f._msufManagerWarmTicks = nil
                end
            end
        end
        manager._pendingRemoveCount = 0
    end

    local paCount = manager._pendingAddCount or 0
    if paCount > 0 then
        local pa = manager._pendingAdd
        for k = 1, paCount do
            local f = pa[k]
            pa[k] = nil
            if f then
                f._msufManagerPendingAdd = nil

                local idx = IsActive(list, f)
                if not idx then
                    count = count + 1
                    list[count] = f
                    f._msufManagerIndex = count
                end

                f._msufManagerWarmTicks = 4
                f._msufManagerIdleStreak = nil
                f._msufNextTick = 0
            end
        end
        manager._pendingAddCount = 0
    end

    return count
end

manager:SetScript("OnUpdate", function(self, elapsed)
    local DriverTick = _G.MSUF_CB_DriverTick
    if type(DriverTick) ~= "function" then
        self:Hide()
        return
    end

    manager._msufTicking = true

    local stamp = (self._msufStamp or 0) + 1
    self._msufStamp = stamp

    local now = Now()
    local list = self._active
    local count = self._activeCount

    local i = 1
    while i <= count do
        local frame = list[i]

        -- Drop invalid frames immediately.
        if (not frame) or (not frame.statusBar) then
            count = RemoveAt(list, count, i, frame)
        elseif frame._msufManagerPendingRemove then
            frame._msufManagerPendingRemove = nil
            count = RemoveAt(list, count, i, frame)
        else
            -- Coalesce: at most one tick per frame per OnUpdate.
            if frame._msufManagerStamp ~= stamp then
                frame._msufManagerStamp = stamp

                if ShouldTickFrame(frame) then
                    frame._msufManagerIdleStreak = nil
                    DriverTick(frame, now, elapsed)
                    i = i + 1
                else
                    -- Step 4: ActiveSet Hard-Unregister (fail-safe)
                    local s = frame._msufManagerIdleStreak
                    s = s and (s + 1) or 1
                    if s >= 2 then
                        count = RemoveAt(list, count, i, frame)
                    else
                        frame._msufManagerIdleStreak = s
                        i = i + 1
                    end
                end
            else
                i = i + 1
            end
        end
    end

    manager._msufTicking = nil

    -- Flush any Register/Unregister calls that happened inside DriverTick.
    count = FlushQueues(list, count)

    self._activeCount = count
    if count <= 0 then
        self:Hide()
    end
end)

-- Public globals (used by MSUF_Castbars.lua). Keep names unique to avoid collisions.
_G.MSUF_CB_Register = function(frame)
    if not frame then return end
    if manager._msufTicking then
        QueueAdd(frame)
        -- Ensure manager is running so the queued add flushes promptly.
        manager:Show()
    else
        RegisterImmediate(frame)
    end
end

_G.MSUF_CB_Unregister = function(frame)
    if not frame then return end
    if manager._msufTicking then
        QueueRemove(frame)
    else
        UnregisterImmediate(frame)
    end
end
