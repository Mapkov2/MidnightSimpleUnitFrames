-- Castbars/MSUF_CastbarManager.lua
-- Phase 3C/3D: Shared OnUpdate manager (scheduler-only).
-- IMPORTANT: No UI ownership here. All visuals/time text remain in MSUF_UpdateCastbarFrame.

local manager = _G.MSUF_CastbarManager3
if not manager then
    manager = CreateFrame("Frame", "MSUF_CastbarManager3", UIParent)
    _G.MSUF_CastbarManager3 = manager
end

manager.active = manager.active or {}
manager._msufStamp = manager._msufStamp or 0
manager:Hide()

local function Now()
    return (GetTimePreciseSec and GetTimePreciseSec()) or GetTime()
end

local function HasDriverTick()
    return type(_G.MSUF_CB_DriverTick) == "function"
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

manager:SetScript("OnUpdate", function(self, elapsed)
    if not HasDriverTick() then
        self:Hide()
        return
    end

    local stamp = (self._msufStamp or 0) + 1
    self._msufStamp = stamp

    local now = Now()
    local active = self.active

    for frame in pairs(active) do
        if not frame or not frame.statusBar then
            active[frame] = nil
        else
            -- Coalesce: at most one tick per frame per OnUpdate, even if re-entrant paths try to tick again.
            if frame._msufManagerStamp ~= stamp then
                frame._msufManagerStamp = stamp
                if ShouldTickFrame(frame) then
                    _G.MSUF_CB_DriverTick(frame, now, elapsed)
                end
            end
        end
    end

    if not next(active) then
        self:Hide()
    end
end)

-- Public globals (used by MSUF_Castbars.lua). Keep names unique to avoid collisions.
_G.MSUF_CB_Register = function(frame)
    if not frame then return end
    manager.active[frame] = true
    -- Bootstrap ticks so bars that start hidden still get their first apply tick(s).
    frame._msufManagerWarmTicks = 4
    -- Force immediate scheduling on first tick.
    frame._msufNextTick = 0
    manager:Show()
end

_G.MSUF_CB_Unregister = function(frame)
    if not frame then return end
    manager.active[frame] = nil
    if not next(manager.active) then
        manager:Hide()
    end
end
