local addonName, ns = ...
ns = ns or {}

local _G = _G

-- =============================================================
-- Fast-path replacement for protected calls.
-- Intentionally does NOT catch errors (for maximum performance).
-- Preserves (ok, ...) return convention and returns false if fn is not callable.
-- =============================================================
if not _G.MSUF_FastCall then
    function _G.MSUF_FastCall(fn, ...)
        if type(fn) ~= "function" then
            return false
        end
        return true, fn(...)
    end
end

-- =============================================================
-- Global helper: "any edit mode" (MSUF Edit Mode OR Blizzard Edit Mode)
-- =============================================================
if not _G.MSUF_IsInAnyEditMode then
    -- MSUF-only Edit Mode:
    -- Blizzard Edit Mode integration is intentionally disabled (Blizzard lifecycle currently unreliable).
    function _G.MSUF_IsInAnyEditMode()
        local st = rawget(_G, "MSUF_EditState")
        if type(st) == "table" and st.active == true then
            return true
        end
        if rawget(_G, "MSUF_UnitEditModeActive") == true then
            return true
        end
        return false
    end
end

local MSUF_FastCall = _G.MSUF_FastCall
local type = _G.type
local tostring = _G.tostring
local print = _G.print
local pcall = _G.pcall
local GetTime = _G.GetTime
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local C_Timer = _G.C_Timer
local debugprofilestop = _G.debugprofilestop
local profEnabled = ns and ns.MSUF_ProfileEnabled
local profStart   = ns and ns.MSUF_ProfileStart
local profStop    = ns and ns.MSUF_ProfileStop
local InCombatLockdown = _G.InCombatLockdown
local table_insert = _G.table and _G.table.insert
local table_remove = _G.table and _G.table.remove

-- =============================================================
-- MSUF_UpdateManager
--
-- Goal (perf):
--   * "Do nothing when nothing is due" (no idle OnUpdate scanning)
--   * Timer-driven wakeups (single next-due timer)
--   * Optional OnUpdate only for ultra-small intervals
--   * Optional safeCalls (FastCall wrapper) for debugging
--
-- Public API (kept):
--   :Register(name, fn, interval [, priority])
--   :Unregister(name)
--   :SetEnabled(name, enabled)
--   :SetSafeCalls(enabled)
--
-- interval can be number seconds or function returning number seconds.
-- fn receives (interval)
-- =============================================================

if not _G.MSUF_UpdateManager then
    _G.MSUF_UpdateManager = {}
end
local UM = _G.MSUF_UpdateManager

if type(UM.entries) ~= "table" then UM.entries = {} end
if type(UM.activeList) ~= "table" then UM.activeList = {} end
if type(UM.activeIndex) ~= "table" then UM.activeIndex = {} end
if type(UM._errOnce) ~= "table" then UM._errOnce = {} end
if type(UM.activeCount) ~= "number" then UM.activeCount = 0 end

-- =============================================================
-- Static callbacks (perf): avoid allocating new closures on every wakeup.
-- These are stored on UM so they persist across reloads.
-- =============================================================
if type(UM._onUpdateFn) ~= "function" then
    UM._onUpdateFn = function()
        -- Signature for OnUpdate is (self, elapsed) but we don't need args.
        UM:_ScheduleNext()
    end
end

if type(UM._timerWakeFn) ~= "function" then
    UM._timerWakeFn = function()
        -- Wake called by C_Timer.NewTimer or C_Timer.After.
        -- NewTimer handle is cleared here; After() has no handle so we track it separately.
        UM._timer = nil
        UM._afterPending = nil
        UM._afterDueAt = nil
        UM:_ScheduleNext()
    end
end

-- Optional: for the rare client path where we can only use After() (no cancellable handle),
-- we may need an earlier wake than the pending After. We do that via a short-lived OnUpdate
-- that only checks a single timestamp (no scanning) and then returns to normal scheduling.
if type(UM._sleepOnUpdateFn) ~= "function" then
    UM._sleepOnUpdateFn = function()
        local untilAt = UM._sleepUntil
        if not untilAt then
            UM:_StopOnUpdate()
            return
        end
        local now = (GetTime and GetTime()) or 0
        if now >= untilAt then
            UM._sleepUntil = nil
            UM:_ScheduleNext()
        end
    end
end

-- Internal scheduling state (coalescing / "schedule once")
-- _scheduledMode: "onupdate" | "timer" | "after" | nil
-- _scheduledDueAt: absolute time (GetTime) for the next wake in timer/after modes.
if type(UM._scheduledMode) ~= "string" then UM._scheduledMode = nil end
if type(UM._scheduledDueAt) ~= "number" then UM._scheduledDueAt = nil end
if type(UM._afterPending) ~= "boolean" then UM._afterPending = nil end
if type(UM._afterDueAt) ~= "number" then UM._afterDueAt = nil end
if type(UM._sleepUntil) ~= "number" then UM._sleepUntil = nil end

-- Default FAST (no FastCall wrapping). Can be flipped to true for debugging.
if UM.safeCalls == nil then UM.safeCalls = false end

-- If the earliest interval is <= this, we keep an OnUpdate loop (timers get spammy).
-- Otherwise we sleep using a single C_Timer.NewTimer wakeup.
if type(UM.minOnUpdateInterval) ~= "number" then
    UM.minOnUpdateInterval = 0.03
end

-- Cap catch-up work to prevent spiral-of-death after lag spikes.
if type(UM.maxCatchUp) ~= "number" then
    UM.maxCatchUp = 2
end

-- Budgeted runner (ms) to smooth CPU spikes. Set to 0 to disable.
if type(UM.timeBudgetMsCombat) ~= "number" then UM.timeBudgetMsCombat = 0.45 end
if type(UM.timeBudgetMsOOC) ~= "number" then UM.timeBudgetMsOOC = 0.80 end
if type(UM.budgetYieldDelay) ~= "number" then UM.budgetYieldDelay = 0.0 end

-- Lower number = higher priority (runs earlier when multiple tasks are due).
if type(UM.defaultPriority) ~= "number" then UM.defaultPriority = 50 end

function UM:_EnsureFrame()
    if self.frame then return self.frame end
    if not CreateFrame then return nil end
    local f = CreateFrame("Frame", "MSUF_UpdateManagerFrame", UIParent)
    if not f then return nil end
    f:Hide()
    self.frame = f
    return f
end

-- Ensure a single OnUpdate is running (no re-SetScript churn).
-- Used for high-frequency scheduling and for the After() fallback "sleep".
function UM:_EnsureOnUpdate(fn)
    local f = self:_EnsureFrame()
    if not f then return nil end
    if f:GetScript("OnUpdate") ~= fn then
        f:SetScript("OnUpdate", fn)
    end
    f:Show()
    self._scheduledMode = "onupdate"
    self._scheduledDueAt = nil
    return f
end

function UM:_Activate(name)
    if not name then return end
    if self.activeIndex and self.activeIndex[name] then return end

    local list = self.activeList
    local entries = self.entries
    local e = entries and entries[name]
    local pr = (e and type(e.priority) == "number" and e.priority) or (self.defaultPriority or 50)

    -- Insert by priority (stable). Activation is rare; O(n) is fine.
    local insertAt = #list + 1
    for j = 1, #list do
        local other = list[j]
        local oe = other and entries and entries[other]
        local opr = (oe and type(oe.priority) == "number" and oe.priority) or (self.defaultPriority or 50)
        if pr < opr then
            insertAt = j
            break
        end
    end

    if table_insert then
        table_insert(list, insertAt, name)
    else
        -- Fallback: manual insert
        list[#list + 1] = nil
        for k = #list, insertAt + 1, -1 do
            list[k] = list[k - 1]
        end
        list[insertAt] = name
    end

    -- Rebuild indices from insertion point
    for k = insertAt, #list do
        local n = list[k]
        if n then self.activeIndex[n] = k end
    end
    self.activeCount = #list
end

function UM:_Deactivate(name)
    if not name or not self.activeIndex then return end
    local idx = self.activeIndex[name]
    if not idx then return end

    local list = self.activeList
    if table_remove then
        table_remove(list, idx)
    else
        for k = idx, (#list - 1) do
            list[k] = list[k + 1]
        end
        list[#list] = nil
    end

    self.activeIndex[name] = nil
    -- Rebuild indices from removal point
    for k = idx, #list do
        local n = list[k]
        if n then self.activeIndex[n] = k end
    end
    self.activeCount = #list
end

function UM:_HasActive()
    return (self.activeCount or 0) > 0
end

function UM:_GetRunBudgetMs()
    local b
    if InCombatLockdown and InCombatLockdown() then
        b = self.timeBudgetMsCombat
    else
        b = self.timeBudgetMsOOC
    end
    if type(b) ~= "number" or b <= 0 then
        return nil
    end
    if not debugprofilestop then
        return nil
    end
    return b
end

function UM:_PrintOnce(name, err)
    name = name or "unknown"
    if self._errOnce[name] then return end
    self._errOnce[name] = true
    if print then
        print("|cffff5555MSUF UpdateManager error|r in '" .. tostring(name) .. "': " .. tostring(err))
    end
end

function UM:SetSafeCalls(enabled)
    self.safeCalls = not not enabled
end

function _G.MSUF_UpdateManager_SetSafeCalls(enabled)
    if _G.MSUF_UpdateManager and _G.MSUF_UpdateManager.SetSafeCalls then
        _G.MSUF_UpdateManager:SetSafeCalls(enabled)
    end
end

function UM:SetPerfMode(mode)
    if mode == "safe" then
        self.safeCalls = true
    else
        self.safeCalls = false
    end
end

function _G.MSUF_UpdateManager_SetPerfMode(mode)
    if _G.MSUF_UpdateManager and _G.MSUF_UpdateManager.SetPerfMode then
        _G.MSUF_UpdateManager:SetPerfMode(mode)
    end
end

function UM:_ResolveInterval(e, name)
    if not e then return nil end
    local i = e.interval
    if type(i) == "function" then
        if self.safeCalls then
            local ok, v = pcall(i)
            if ok then
                i = v
            else
                -- Only fires in safeCalls/debug mode.
                self:_PrintOnce((name or "unknown") .. ".interval", v)
                i = nil
            end
        else
            i = i()
        end
    end
    if type(i) ~= "number" or i <= 0 then
        return nil
    end
    return i
end

function UM:_CancelTimer()
    local t = self._timer
    if t and t.Cancel then
        t:Cancel()
    end
    self._timer = nil
    if self._scheduledMode == "timer" then
        self._scheduledMode = nil
        self._scheduledDueAt = nil
    end
end

function UM:_StopOnUpdate()
    local f = self.frame
    if f then
        f:SetScript("OnUpdate", nil)
        f:Hide()
    end
    if self._scheduledMode == "onupdate" then
        self._scheduledMode = nil
    end
    self._sleepUntil = nil
end

function UM:_StopIfIdle()
    if not self:_HasActive() then
        self:_CancelTimer()
        self:_StopOnUpdate()
    end
end

-- =============================================================
-- Core runner (timer or OnUpdate)
-- =============================================================
function UM:_RunDue(now)
    now = now or (GetTime and GetTime()) or 0

    local safeCalls = self.safeCalls
    local maxCatch = self.maxCatchUp or 2

    local list = self.activeList
    local entries = self.entries

    local nextDue = nil
    local minInterval = nil

    local budgetMs = self:_GetRunBudgetMs()
    local t0 = budgetMs and debugprofilestop and debugprofilestop() or nil
    local budgetStop = false

    local function overBudget()
        if not t0 then return false end
        return (debugprofilestop() - t0) >= budgetMs
    end

    local doProf = (type(profEnabled) == "function") and profEnabled() and (type(profStart) == "function") and (type(profStop) == "function")

    local i = 1
    while i <= #list do
        if overBudget() then
            budgetStop = true
            break
        end

        local name = list[i]
        local e = name and entries[name]

        if not (e and e.enabled and type(e.fn) == "function") then
            self:_Deactivate(name)
        else
            local interval = self:_ResolveInterval(e, name)
            if not interval then
                -- invalid interval => disable
                e.enabled = false
                self:_Deactivate(name)
            else
                -- Track min interval for deciding timer vs OnUpdate
                if not minInterval or interval < minInterval then
                    minInterval = interval
                end

                -- Initialize next time
                if type(e.next) ~= "number" then
                    e.next = now + interval
                end

                local ran = 0
                while e.next <= now and ran < maxCatch do
                    ran = ran + 1
                    local prevNext = e.next

                    if doProf then profStart("UM." .. tostring(name)) end

                    if safeCalls then
                        -- Only used in debug mode; hot path stays pcall-free.
                        local ok, err = pcall(e.fn, interval)
                        if doProf then profStop("UM." .. tostring(name)) end
                        if not ok then
                            e.enabled = false
                            self:_Deactivate(name)
                            self:_PrintOnce(name, err)
                            break
                        end
                    else
                        e.fn(interval)
                        if doProf then profStop("UM." .. tostring(name)) end
                    end
                    if overBudget() then
                        budgetStop = true
                        break
                    end

                    if not e.enabled then
                        self:_Deactivate(name)
                        break
                    end

                    local currNext = e.next
                    if type(currNext) ~= "number" then
                        e.next = now + interval
                    elseif currNext == prevNext then
                        e.next = currNext + interval
                    end
                end

                if budgetStop then
                    -- Stop processing further tasks this frame.
                    break
                end

                -- If we are still behind after maxCatch, jump forward to avoid spirals.
                if e.enabled and e.next <= now then
                    e.next = now + interval
                end

                if e.enabled then
                    if not nextDue or e.next < nextDue then
                        nextDue = e.next
                    end
                end

                i = i + 1
            end
        end
    end

    if budgetStop then
        local yd = self.budgetYieldDelay or 0
        if yd < 0 then yd = 0 end
        nextDue = now + yd
    end

    return nextDue, minInterval
end

function UM:_ScheduleNext()
    if not self:_HasActive() then
        self:_StopIfIdle()
        return
    end

    local now = (GetTime and GetTime()) or 0
    local nextDue, minInterval = self:_RunDue(now)

    if not self:_HasActive() or not nextDue then
        self:_StopIfIdle()
        return
    end

    local delay = nextDue - now
    if delay < 0 then delay = 0 end

    local useOnUpdate = (type(minInterval) == "number" and minInterval <= (self.minOnUpdateInterval or 0))

    local dueAt = now + delay

    if useOnUpdate then
        -- High-frequency mode: keep a single OnUpdate running.
        -- Cancel any cancellable timer; After() cannot be cancelled and is ignored.
        if self._scheduledMode ~= "onupdate" then
            self:_CancelTimer()
        end
        self:_EnsureOnUpdate(self._onUpdateFn)
        return
    end

    -- Timer-driven mode (single next-due wake).
    -- Stop any active OnUpdate scan/sleep.
    self:_StopOnUpdate()

    -- Prefer cancellable timers.
    if C_Timer and C_Timer.NewTimer then
        -- Schedule only once: if an existing timer wakes earlier/equal, keep it.
        if self._scheduledMode == "timer" and self._timer and type(self._scheduledDueAt) == "number" and self._scheduledDueAt <= dueAt then
            return
        end
        self:_CancelTimer()
        self._timer = C_Timer.NewTimer(delay, self._timerWakeFn)
        self._scheduledMode = "timer"
        self._scheduledDueAt = dueAt
        return
    end

    -- Fallback: After() is not cancellable. Track a single pending wake; if we need an earlier wake,
    -- use the lightweight sleep-OnUpdate until that earlier time.
    if C_Timer and C_Timer.After then
        if self._afterPending and type(self._afterDueAt) == "number" then
            if self._afterDueAt <= dueAt then
                self._scheduledMode = "after"
                self._scheduledDueAt = self._afterDueAt
                return
            end
            self._sleepUntil = dueAt
            self:_EnsureOnUpdate(self._sleepOnUpdateFn)
            self._scheduledMode = "after"
            self._scheduledDueAt = self._afterDueAt
            return
        end

        self:_CancelTimer()
        self._afterPending = true
        self._afterDueAt = dueAt
        self._scheduledMode = "after"
        self._scheduledDueAt = dueAt
        C_Timer.After(delay, self._timerWakeFn)
        return
    end

    -- Ultimate fallback: no timer API.
    self:_EnsureOnUpdate(self._onUpdateFn)
    return
end

function UM:Register(name, fn, interval, priority)
    if type(name) ~= "string" or name == "" then return end
    if type(fn) ~= "function" then return end

    local e = self.entries[name]
    if type(e) ~= "table" then
        e = {}
        self.entries[name] = e
    end

    e.fn = fn
    e.interval = interval
    e.enabled = true
    e.next = nil
    e.priority = (type(priority) == "number" and priority) or e.priority or (self.defaultPriority or 50)

    self:_Activate(name)
    self:_ScheduleNext()
end

function UM:Unregister(name)
    if type(name) ~= "string" or name == "" then return end
    self:_Deactivate(name)
    self.entries[name] = nil
    self:_StopIfIdle()
end



-- =============================================================
-- Kick(name)
--   Force a task to run ASAP (next frame) without waiting for its interval.
--   Intended for event-driven/budgeted flushes (e.g., UFCoreFlush), where
--   we want: Event -> MarkDirty -> Flush next frame.
--
-- Behavior:
--   * Ensures the entry is active.
--   * Sets e.next = now so it is due.
--   * Cancels any sleeping timer and forces a short OnUpdate wake.
--
-- Note:
--   Kick does NOT execute the task immediately; it wakes the scheduler.
-- =============================================================
function UM:Kick(name)
    if type(name) ~= "string" or name == "" then return end
    local entries = self.entries
    local e = entries and entries[name]
    if type(e) ~= "table" then return end

    -- Ensure it is active/enabled.
    if not e.enabled then
        e.enabled = true
        e.next = nil
        self:_Activate(name)
    elseif self.activeIndex and not self.activeIndex[name] then
        self:_Activate(name)
    end

    local now = (GetTime and GetTime()) or 0
    e.next = now

    -- PERF: If we're already running in OnUpdate mode, do NOT churn timers / SetScript / Show().
    -- The scheduler will run next frame anyway; marking e.next is sufficient.
    if self._scheduledMode == "onupdate" then
        return
    end

    -- Cancel any cancellable timer and wake via OnUpdate.
    -- (Kick intentionally does NOT execute the task immediately.)
    self:_CancelTimer()
    self:_EnsureOnUpdate(self._onUpdateFn)
end

function _G.MSUF_UpdateManager_Kick(name)
    local um = _G.MSUF_UpdateManager
    if um and um.Kick then
        um:Kick(name)
    end
end
function UM:SetEnabled(name, enabled)
    if type(name) ~= "string" or name == "" then return end
    local e = self.entries[name]
    if type(e) ~= "table" then
        self:_StopIfIdle()
        return
    end

    local on = not not enabled
    e.enabled = on
    if on then
        e.next = nil
        self:_Activate(name)
        self:_ScheduleNext()
    else
        e.next = nil
        self:_Deactivate(name)
        self:_StopIfIdle()
    end
end

ns.MSUF_UpdateManager = UM
