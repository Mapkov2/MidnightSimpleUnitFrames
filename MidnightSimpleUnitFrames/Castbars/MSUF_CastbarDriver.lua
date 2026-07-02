--- Castbars/MSUF_CastbarDriver.lua
--- Target/focus castbar driver.
---
--- Owns unit spellcast event registration, delayed stop confirmation,
--- death/unit-change cleanup, and the handoff from Engine cast-state to Runtime
--- application for non-player castbars. Keep this file event-oriented; visual
--- changes belong in Frames/Runtime/Visuals where possible.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local C_Timer = _G.C_Timer
local GetTime = _G.GetTime
local GetCVar = _G.GetCVar
local UnitExists = _G.UnitExists
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local type = type
local tonumber = tonumber
local tostring = tostring

ExportPublic("MSUF_INTERRUPT_FEEDBACK_DURATION", _G.MSUF_INTERRUPT_FEEDBACK_DURATION or 0.5)

local function IsCastbarEnabledForUnit(unit)
    unit = unit or ""

    local resolver = _G.MSUF_IsCastbarEnabledForUnit
    if type(resolver) == "function" then
        local enabled = resolver(unit)
        if enabled ~= nil then
            return enabled
        end
    end

    if type(_G.MSUF_EnsureDBLazy) == "function" then
        _G.MSUF_EnsureDBLazy()
    elseif type(_G.MSUF_EnsureDB) == "function" then
        _G.MSUF_EnsureDB()
    end

    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    if not general then
        return true
    end

    local shouldUseCastbar = _G.MSUF_ShouldUseMSUFCastbar
    if type(shouldUseCastbar) == "function" then
        return shouldUseCastbar(unit, general) == true
    end

    if unit == "player" then
        return general.enablePlayerCastbar ~= false
    elseif unit == "target" then
        return general.enableTargetCastbar ~= false
    elseif unit == "focus" then
        return general.enableFocusCastbar ~= false
    end

    return true
end

local CASTBAR_UNIT_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_INTERRUPTED",
}

local function SetDriverEventsRegistered(frame, unit, enabled)
    if not frame then return end

    if enabled then
        frame._msufDriverBackendEnabled = true
        if frame._msufDriverEventsRegistered then return end
        for index = 1, #CASTBAR_UNIT_EVENTS do
            frame:RegisterUnitEvent(CASTBAR_UNIT_EVENTS[index], unit)
        end
        if unit == "target" or unit == "focus" then
            frame:RegisterEvent("PLAYER_" .. unit:upper() .. "_CHANGED")
        end
        frame._msufDriverEventsRegistered = true
        return
    end

    if not frame._msufDriverEventsRegistered then return end
    for index = 1, #CASTBAR_UNIT_EVENTS do
        frame:UnregisterEvent(CASTBAR_UNIT_EVENTS[index])
    end
    if unit == "target" or unit == "focus" then
        frame:UnregisterEvent("PLAYER_" .. unit:upper() .. "_CHANGED")
    end
    frame._msufDriverEventsRegistered = nil
    frame._msufDriverBackendEnabled = nil
end

local function AnchorDriverFrameToUnitFrame(frame, unit)
    local unitFrame = _G["MSUF_" .. unit]
    if not unitFrame then return end

    frame:ClearAllPoints()
    if unit == "target" then
        frame:SetPoint("BOTTOMLEFT", unitFrame, "TOPLEFT", 0, 5)
    elseif unit == "focus" then
        frame:SetPoint("TOPLEFT", unitFrame, "BOTTOMLEFT", 0, -5)
    elseif unit == "player" then
        frame:SetPoint("BOTTOM", unitFrame, "TOP", 0, 5)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -300)
    end

    local width = unitFrame:GetWidth()
    if width and width > 0 then
        frame:SetWidth(width)
    end
end

local function HideChannelHasteMarkers(frame)
    local fn = _G.MSUF_PlayerChannelHasteMarkers_Hide
    if type(fn) == "function" then
        fn(frame)
    end
end

local function UpdateChannelHasteMarkers(frame, force)
    local fn = _G.MSUF_PlayerChannelHasteMarkers_Update
    if type(fn) == "function" then
        fn(frame, force)
    end
end

local ToPlain = _G.ToPlain
local toPlainIsSecret = _G.issecretvalue or function(_) return false end
local toPlainHuge = math.huge

local function ToPlainNumber(value)
    if value == nil then return nil end

    -- PERF fast path: a plain finite number needs no tostring/tonumber
    -- round-trip (that round-trip only exists to redact secrets and to map
    -- nan/inf to nil, which the guards below preserve exactly).
    if type(value) == "number" and toPlainIsSecret(value) ~= true
        and value == value and value ~= toPlainHuge and value ~= -toPlainHuge then
        return value
    end

    if ToPlain then
        local plain = ToPlain(value)
        local number = tonumber(tostring(plain))
        if number ~= nil then
            return number
        end
    end

    local valueType = type(value)
    if valueType == "number" or valueType == "string" then
        return tonumber(tostring(value))
    end

    return nil
end

local function GetRemainingFromStatusBar(frame)
    local statusBar = frame and frame.statusBar
    if not (statusBar and statusBar.GetValue and statusBar.GetMinMaxValues) then
        return nil
    end

    local value = ToPlainNumber(statusBar:GetValue())
    local minValue, maxValue = statusBar:GetMinMaxValues()
    minValue = ToPlainNumber(minValue)
    maxValue = ToPlainNumber(maxValue)
    if not (value and minValue and maxValue) then
        return nil
    end

    local total = maxValue - minValue
    if not (type(total) == "number" and total > 0) then
        return nil
    end

    local assumeCountdown = frame._msufTimerAssumeCountdown
    local previous = frame._msufLastSBValue
    frame._msufLastSBValue = value
    if assumeCountdown == nil then
        if frame.MSUF_timerDriven == true then
            assumeCountdown = frame.MSUF_isChanneled == true
        elseif frame._msufStripeReverseFill == true then
            assumeCountdown = true
        else
            assumeCountdown = previous ~= nil and value < (previous - 0.0001)
        end
        frame._msufTimerAssumeCountdown = assumeCountdown and true or false
    end

    local remaining = assumeCountdown and (value - minValue) or (maxValue - value)
    if type(remaining) ~= "number" then
        return nil
    end
    if remaining < 0 then
        remaining = 0
    end
    return remaining
end

local function MSUF_UpdateCastTimeText_FromStatusBar(frame)
    if not (frame and frame.timeText) then return end

    if not (type(_G.MSUF_IsCastTimeEnabled) == "function" and _G.MSUF_IsCastTimeEnabled(frame)) then
        _G.MSUF_SetTextIfChanged(frame.timeText, "")
        return
    end

    local remaining = GetRemainingFromStatusBar(frame)
    if type(remaining) ~= "number" then
        _G.MSUF_SetTextIfChanged(frame.timeText, "")
        return
    end

    local total = frame._msufPlainTotal
    if not total and frame.statusBar and frame.statusBar.GetMinMaxValues then
        local minValue, maxValue = frame.statusBar:GetMinMaxValues()
        minValue = ToPlainNumber(minValue) or 0
        maxValue = ToPlainNumber(maxValue)
        if maxValue and maxValue > minValue then
            total = maxValue - minValue
        end
    end

    _G.MSUF_SetCastTimeText(frame, remaining, total)
end

local ClearEmpowerState = _G.MSUF_ClearEmpowerState or function() end

local function SetSafetyOnUpdate(frame, enabled)
    if not frame then return end

    if enabled then
        frame._msufSafetyNext = nil
        frame._msufSafetyOnUpdate = nil
        frame:SetScript("OnUpdate", nil)
        return
    end

    frame._msufSafetyOnUpdate = nil
    frame._msufSafetyNext = nil
    frame:SetScript("OnUpdate", nil)
end

local function BuildState(frame)
    local engine = (_G.MSUF_GetCastbarEngine and _G.MSUF_GetCastbarEngine()) or nil
    if engine and engine.BuildState then
        return engine:BuildState(frame.unit, frame)
    end
    return nil
end

local function StoreActiveStateIdentity(frame, state)
    if not frame then return end

    if state and state.active then
        frame._msufActiveSeq = state.spellSequenceID
        frame._msufActiveCastType = state.castType
        return
    end

    frame._msufActiveSeq = nil
    frame._msufActiveCastType = nil
end

local function ActiveSequenceChanged(frame, sequenceID)
    if not frame or sequenceID == nil then
        return false
    end

    local activeSeq = frame._msufActiveSeq
    if activeSeq == nil then
        return false
    end
    if type(sequenceID) ~= "number" or type(activeSeq) ~= "number" then
        return false
    end

    return activeSeq ~= sequenceID
end

local function CastbarAlreadyIdle(frame)
    if not frame then return true end
    if frame.MSUF_castActive == true or frame.interrupted or frame.timer or frame.hideTimer then return false end
    if frame.IsShown and frame:IsShown() then return false end
    return true
end

local function RefreshFromEngine(frame)
    if frame.interrupted then return end

    local state = BuildState(frame)
    StoreActiveStateIdentity(frame, state)
    if not (state and state.active and state.spellName) and CastbarAlreadyIdle(frame) then return end
    frame:Cast(state)
end

local function ClearStopExpectation(frame)
    if not frame then return end

    frame._msufStopExpToken = -1
    frame._msufStopTimer1 = nil
    frame._msufStopTimer2 = nil
    frame._msufStopTimer3 = nil
end

local function ClearStartRetry(frame)
    if not frame then return end

    frame._msufStartRetryToken = -1
    frame._msufStartRetryTimer = nil
    frame._msufStartRetryPending = nil
end

local function StopDriverFrame(frame, reason, unregisterCastbar)
    if not frame then return end

    SetSafetyOnUpdate(frame, false)
    ClearStopExpectation(frame)
    ClearStartRetry(frame)
    HideChannelHasteMarkers(frame)
    _G.MSUF_CB_ResetStateOnStop(frame, reason)
    if unregisterCastbar and _G.MSUF_UnregisterCastbar then
        _G.MSUF_UnregisterCastbar(frame)
    end
end

local function EnsureDriverCallbacks(frame)
    if frame._msufDriverCBReady then return end
    frame._msufDriverCBReady = true

    local function StopExpectationInvalid()
        if not frame or frame.interrupted then
            return true
        end
        return (frame._msufCastToken or 0) ~= (frame._msufStopExpToken or 0)
    end

    frame._msufStopCB_chanT1 = function()
        if StopExpectationInvalid() then return end

        local state = BuildState(frame)
        if state and state.active then
            StoreActiveStateIdentity(frame, state)
            frame:Cast(state)
            return
        end

        if ActiveSequenceChanged(frame, frame._msufStopExpSeq) then
            RefreshFromEngine(frame)
            return
        end

        frame._msufStopTimer2 = true
        C_Timer.After(frame._msufStopT2 or 0.08, frame._msufStopCB_chanT2)
    end

    frame._msufStopCB_chanT2 = function()
        if StopExpectationInvalid() then return end

        local state = BuildState(frame)
        if state and state.active then
            StoreActiveStateIdentity(frame, state)
            frame:Cast(state)
            return
        end

        if ActiveSequenceChanged(frame, frame._msufStopExpSeq) then
            RefreshFromEngine(frame)
            return
        end

        frame:SetSucceeded()
    end

    frame._msufStopCB_failsafe = function()
        if StopExpectationInvalid() then return end

        local state = BuildState(frame)
        if state and state.active then
            StoreActiveStateIdentity(frame, state)
            frame:Cast(state)
            return
        end

        if ActiveSequenceChanged(frame, frame._msufStopExpSeq) then
            RefreshFromEngine(frame)
            return
        end

        frame:SetSucceeded()
    end

    frame._msufStopCB_castT1 = function()
        if StopExpectationInvalid() then return end

        local state = BuildState(frame)
        if state and state.active then
            StoreActiveStateIdentity(frame, state)
            frame:Cast(state)
            return
        end

        if ActiveSequenceChanged(frame, frame._msufStopExpSeq) then
            RefreshFromEngine(frame)
            return
        end

        frame:SetSucceeded()
    end

    frame._msufStartRetryCB = function()
        frame._msufStartRetryPending = nil
        frame._msufStartRetryTimer = nil
        if not frame or frame.interrupted then return end
        if (frame._msufCastToken or 0) ~= (frame._msufStartRetryToken or 0) then return end

        local state = BuildState(frame)
        if state and state.active then
            StoreActiveStateIdentity(frame, state)
            frame:Cast(state)
        end
    end

    frame._msufDeathRecheckCB = function()
        frame._msufDeathRecheckPending = nil
        if not frame:IsShown() or frame.interrupted then return end

        local unit = frame.unit
        if unit and (not UnitExists(unit) or (UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit))) then
            StopDriverFrame(frame, "STOPPED", false)
        end
    end
end

local function AdvanceCastToken(frame)
    frame._msufCastToken = (frame._msufCastToken or 0) + 1
    return frame._msufCastToken
end

local function ScheduleStopConfirmation(frame, castType)
    if not frame or frame.interrupted then return end

    local token = frame._msufCastToken or 0
    local activeSeq = frame._msufActiveSeq
    ClearStopExpectation(frame)
    EnsureDriverCallbacks(frame)
    frame._msufStopExpToken = token
    frame._msufStopExpSeq = activeSeq

    if castType == "CHANNEL" then
        local queueWindowMS = 0
        if GetCVar then
            queueWindowMS = tonumber(GetCVar("SpellQueueWindow") or "0") or 0
        end
        if queueWindowMS < 0 then
            queueWindowMS = 0
        end

        local stopWindow = (queueWindowMS / 1000) + 0.08
        if stopWindow < 0.20 then stopWindow = 0.20 end
        if stopWindow > 0.70 then stopWindow = 0.70 end

        local firstDelay = 0.12
        if firstDelay > stopWindow then
            firstDelay = stopWindow
        end

        local secondDelay = stopWindow - firstDelay
        if secondDelay < 0.08 then
            secondDelay = 0.08
        end

        local failsafeDelay = stopWindow + 0.55
        if failsafeDelay < 0.70 then failsafeDelay = 0.70 end
        if failsafeDelay > 1.20 then failsafeDelay = 1.20 end

        frame._msufStopT2 = secondDelay
        frame._msufStopTimer1 = true
        C_Timer.After(firstDelay, frame._msufStopCB_chanT1)
        frame._msufStopTimer3 = true
        C_Timer.After(failsafeDelay, frame._msufStopCB_failsafe)
        return
    end

    frame._msufStopTimer1 = true
    C_Timer.After(0.12, frame._msufStopCB_castT1)
    frame._msufStopTimer3 = true
    C_Timer.After(0.40, frame._msufStopCB_failsafe)
end

local function HandleUnitDeathEvent(frame)
    if not frame:IsShown() or frame.interrupted then return end

    local unit = frame.unit
    if unit and (not UnitExists(unit) or (UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit))) then
        StopDriverFrame(frame, "STOPPED", false)
        return
    end

    if not frame._msufDeathRecheckPending then
        EnsureDriverCallbacks(frame)
        frame._msufDeathRecheckPending = true
        C_Timer.After(0.1, frame._msufDeathRecheckCB)
    end
end

local function NormalizeEventForUnit(frame, event)
    if frame.unit == "player" then
        if event == "UNIT_SPELLCAST_EMPOWER_START" or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
            frame.MSUF_wantsEmpower = true
        elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
            frame.MSUF_wantsEmpower = nil
        elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
            frame.MSUF_wantsEmpower = nil
        end
        return event
    end

    frame.MSUF_wantsEmpower = nil
    if event == "UNIT_SPELLCAST_EMPOWER_START" then
        return "UNIT_SPELLCAST_START"
    elseif event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        return "UNIT_SPELLCAST_DELAYED"
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        return "UNIT_SPELLCAST_STOP"
    end

    return event
end

local function HandleDriverEvent(frame, event, eventUnit)
    if frame._msufDriverBackendEnabled ~= true then
        if frame.unit == "target" or frame.unit == "focus" then
            SetDriverEventsRegistered(frame, frame.unit, false)
        end
        StopDriverFrame(frame, "HARDHIDE", true)
        return
    end

    if event == "UNIT_HEALTH" then
        HandleUnitDeathEvent(frame)
        return
    end

    event = NormalizeEventForUnit(frame, event)

    if event == "UNIT_SPELLCAST_START"
        or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_EMPOWER_START" then
        ClearStopExpectation(frame)
        ClearStartRetry(frame)
        local token = AdvanceCastToken(frame)
        frame.isNotInterruptible = false
        frame.MSUF_kickInterruptibleConfirmed = nil
        RefreshFromEngine(frame)

        local state = BuildState(frame)
        if not (state and state.active and state.spellName) then
            EnsureDriverCallbacks(frame)
            frame._msufStartRetryToken = token
            if not frame._msufStartRetryPending then
                frame._msufStartRetryPending = true
                frame._msufStartRetryTimer = true
                C_Timer.After(0.05, frame._msufStartRetryCB)
            end
        end
        return
    end

    if event == "UNIT_SPELLCAST_DELAYED"
        or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
        or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        if event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
            and (frame._msufStopTimer1 or frame._msufStopTimer2 or frame._msufStopTimer3) then
            ClearStopExpectation(frame)
            AdvanceCastToken(frame)
        end
        RefreshFromEngine(frame)
        return
    end

    if event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        frame.MSUF_kickInterruptibleConfirmed = nil
        ScheduleStopConfirmation(frame, "CAST")
        return
    end

    if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        frame.MSUF_kickInterruptibleConfirmed = nil
        ScheduleStopConfirmation(frame, "CHANNEL")
        return
    end

    if event == "UNIT_SPELLCAST_FAILED" then
        frame.MSUF_kickInterruptibleConfirmed = nil
        ScheduleStopConfirmation(frame, "CAST")
        return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if frame.unit ~= "player" then
            RefreshFromEngine(frame)
            return
        end

        local state = BuildState(frame)
        if state and state.active then
            StoreActiveStateIdentity(frame, state)
            frame:Cast(state)
        end
        return
    end

    if event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        if eventUnit ~= frame.unit then return end
        frame.isNotInterruptible = false
        frame.MSUF_kickInterruptibleConfirmed = true
        frame._msufApiNotInterruptibleRaw = false
        if frame.UpdateColorForInterruptible then _G.MSUF_CB_ApplyColor(frame) end
        if _G.MSUF_KickReady_RefreshFrame then _G.MSUF_KickReady_RefreshFrame(frame, nil) end
        return
    end

    if event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        if eventUnit ~= frame.unit then return end
        frame.isNotInterruptible = true
        frame.MSUF_kickInterruptibleConfirmed = false
        frame._msufApiNotInterruptibleRaw = true
        if frame.UpdateColorForInterruptible then _G.MSUF_CB_ApplyColor(frame) end
        if _G.MSUF_KickReady_RefreshFrame then _G.MSUF_KickReady_RefreshFrame(frame, nil) end
        return
    end

    if event == "UNIT_SPELLCAST_INTERRUPTED" then
        if eventUnit ~= frame.unit then return end
        ClearStopExpectation(frame)
        frame.MSUF_kickInterruptibleConfirmed = nil
        frame:SetInterrupted()
        return
    end

    if (event == "PLAYER_TARGET_CHANGED" and frame.unit == "target")
        or (event == "PLAYER_FOCUS_CHANGED" and frame.unit == "focus") then
        ClearStopExpectation(frame)
        ClearStartRetry(frame)
        AdvanceCastToken(frame)
        frame._msufInterruptToken = (frame._msufInterruptToken or 0) + 1
        frame.timer = nil
        frame.interrupted = nil
        frame.MSUF_kickInterruptibleConfirmed = nil
        RefreshFromEngine(frame)
    end
end

local function BuildCastbarFrameElements(frame)
    if type(_G.MSUF_BuildCastbarFrameElements) == "function" then
        return _G.MSUF_BuildCastbarFrameElements(frame)
    end
    if _G.MSUF_DevPrint then
        _G.MSUF_DevPrint("MSUF: MSUF_BuildCastbarFrameElements missing")
    end
    return nil
end

local function CreateCastBar(frameName, unit)
    local frame = CreateFrame("Frame", frameName, UIParent)
    frame:SetClampedToScreen(true)
    frame.unit = unit
    frame.reverseFill = false
    function frame:UpdateColorForInterruptible()
        if not (self and self.statusBar and self.statusBar.SetStatusBarColor) then
            return
        end

        if not _G.MSUF_DB and type(_G.EnsureDB) == "function" then
            _G.EnsureDB()
        end

        local forcedNotInterruptible = self.isNotInterruptible == true
        local castR, castG, castB, nonR, nonG, nonB = _G.MSUF_ResolveCastbarColors()
        local rawApiNotInterruptible = self._msufApiNotInterruptibleRaw
        if forcedNotInterruptible then
            rawApiNotInterruptible = true
        end

        local unavailableR, unavailableG, unavailableB, unavailableA, interruptReadyBool, useUnavailableColor
        if type(_G.MSUF_Castbar_GetInterruptUnavailableTintArgs) == "function" then
            unavailableR, unavailableG, unavailableB, unavailableA, interruptReadyBool, useUnavailableColor =
                _G.MSUF_Castbar_GetInterruptUnavailableTintArgs(self)
        end

        if type(_G.MSUF_Castbar_ApplyNonInterruptibleTint) == "function" then
            _G.MSUF_Castbar_ApplyNonInterruptibleTint(
                self,
                rawApiNotInterruptible,
                nonR,
                nonG,
                nonB,
                1,
                castR,
                castG,
                castB,
                1,
                forcedNotInterruptible,
                unavailableR,
                unavailableG,
                unavailableB,
                unavailableA,
                interruptReadyBool,
                useUnavailableColor
            )
        elseif forcedNotInterruptible then
            _G.MSUF_SetStatusBarColorIfChanged(self.statusBar, nonR, nonG, nonB, 1)
        else
            _G.MSUF_SetStatusBarColorIfChanged(self.statusBar, castR, castG, castB, 1)
        end
    end

    frame:SetScript("OnEvent", function(self, event, eventUnit, ...)
        HandleDriverEvent(self, event, eventUnit, ...)
    end)

    function frame:Cast(state)
        if not (state and state.active and state.unit == self.unit and state.spellName) then
            state = BuildState(self)
        end

        if state ~= nil then
            self._msufApiNotInterruptibleRaw = state.apiNotInterruptibleRaw
        else
            self._msufApiNotInterruptibleRaw = nil
        end

        local spellName, label, icon, startTimeMS, endTimeMS
        local isChannel = false
        if state and state.active and state.spellName then
            spellName = state.spellName
            label = state.text or state.spellName
            icon = state.icon
            startTimeMS = state.startTimeMS
            endTimeMS = state.endTimeMS
            isChannel = state.castType == "CHANNEL"
            self._msufCastSpellID = state.spellId
            self._msufCastSpellSeq = state.spellSequenceID
        end

        if self.hideTimer then
            self._msufHideToken = (self._msufHideToken or 0) + 1
            self.hideTimer = nil
        end
        if self.succeededTimer then
            self._msufSucceededToken = (self._msufSucceededToken or 0) + 1
            self.succeededTimer = nil
        end

        local durationObj = (state and state.durationObj ~= nil) and state.durationObj or nil
        if durationObj == nil and state and state.active then
            local sequenceID = state.spellSequenceID
            if type(sequenceID) == "number"
                and self._msufLastDurationSeq == sequenceID
                and self._msufLastDurationObj ~= nil then
                durationObj = self._msufLastDurationObj
                state.durationObj = durationObj
            end
        end

        if state and state.active and durationObj ~= nil then
            local sequenceID = state.spellSequenceID
            if type(sequenceID) == "number" then
                self._msufLastDurationSeq = sequenceID
                self._msufLastDurationObj = durationObj
            end
        elseif not (state and state.active) then
            self._msufApiNotInterruptibleRaw = nil
            self._msufLastDurationSeq = nil
            self._msufLastDurationObj = nil
        end

        if self.isEmpower then
            ClearEmpowerState(self)
        end

        if spellName and durationObj then
            state.durationObj = durationObj
            state.text = label or spellName
            state.icon = icon
            _G.MSUF_Castbar_ApplyActiveDuration(self, state, {
                skipColor = true,
                skipRegister = true,
                skipTimeText = true,
                skipShow = true,
            })

            local reverseFill = _G.MSUF_GetReverseFillSafe(self, isChannel)
            self._msufStripeReverseFill = reverseFill
            UpdateChannelHasteMarkers(self, true)

            if self.UpdateColorForInterruptible then
                _G.MSUF_CB_ApplyColor(self)
            end
            if _G.MSUF_RegisterCastbar then
                _G.MSUF_RegisterCastbar(self)
            end
            if self.timeText then
                _G.MSUF_UpdateCastTimeText_FromStatusBar(self)
            end

            self:Show()
            self.MSUF_castActive = true

            if _G.MSUF_KickReady_RefreshFrame then
                if not self._msufKickReadyDeferredCB then
                    self._msufKickReadyDeferredCB = function()
                        if self and self.MSUF_castActive == true and _G.MSUF_KickReady_RefreshFrame then
                            _G.MSUF_KickReady_RefreshFrame(self, nil)
                        end
                    end
                end
                C_Timer.After(0, self._msufKickReadyDeferredCB)
            end

            if self.unit ~= "player" then
                self._msufZeroCount = nil
                SetSafetyOnUpdate(self, true)
            end
        else
            SetSafetyOnUpdate(self, false)
            self.MSUF_castActive = false
            self.MSUF_kickInterruptibleConfirmed = nil
            if self.kickReadyBox then self.kickReadyBox:Hide() end
            if _G.MSUF_KickReady_RefreshFrame then _G.MSUF_KickReady_RefreshFrame(self, nil) end

            if self.hideTimer then
                self._msufHideToken = (self._msufHideToken or 0) + 1
            end
            self.hideTimer = true
            self._msufHideToken = (self._msufHideToken or 0) + 1
            local hideToken = self._msufHideToken
            C_Timer.After(0, function()
                if not self or self._msufHideToken ~= hideToken or not self.unit then return end

                local nextState = BuildState(self)
                if nextState and nextState.active then
                    self:Cast(nextState)
                    return
                end

                _G.MSUF_CB_ResetStateOnStop(self, "STOPPED")
            end)
        end

        if self.timer then
            self._msufInterruptToken = (self._msufInterruptToken or 0) + 1
            self.timer = nil
        end

        local feedbackDuration = _G.MSUF_INTERRUPT_FEEDBACK_DURATION or 0.5
        if type(feedbackDuration) ~= "number" then feedbackDuration = 0.5 end
        if feedbackDuration < 0 then feedbackDuration = 0 end

        self.timer = true
        self._msufInterruptToken = (self._msufInterruptToken or 0) + 1
        local interruptToken = self._msufInterruptToken
        C_Timer.After(feedbackDuration, function()
            if self._msufInterruptToken == interruptToken and self.interrupted then
                self.interrupted = nil
                self:Hide()
            end
        end)
    end

    function frame:SetInterrupted()
        HideChannelHasteMarkers(self)
        SetSafetyOnUpdate(self, false)
        _G.MSUF_CB_ResetStateOnStop(self, "INTERRUPTED")
        self.interrupted = true
        self._msufApiNotInterruptibleRaw = nil
        self.MSUF_castActive = false
        self.MSUF_kickInterruptibleConfirmed = nil
        if self.kickReadyBox then self.kickReadyBox:Hide() end
        if _G.MSUF_KickReady_RefreshFrame then _G.MSUF_KickReady_RefreshFrame(self, nil) end
        if type(_G.MSUF_EnsureDBLazy) == "function" then _G.MSUF_EnsureDBLazy() end

        local unitDB = (self.unit and _G.MSUF_DB and _G.MSUF_DB[self.unit]) or nil
        if unitDB and unitDB.showInterrupt == false then
            self.interrupted = nil
            if self.castText and _G.MSUF_CB_ApplyTexts then
                _G.MSUF_CB_ApplyTexts(self, nil, "", nil)
            end
            if self.timeText and _G.MSUF_CB_ApplyTexts then
                _G.MSUF_CB_ApplyTexts(self, nil, nil, "")
            end
            self:Hide()
            return
        end

        local reverseFill = _G.MSUF_GetReverseFillSafe(self, false)
        _G.MSUF_ApplyInterruptBarVisuals(self, {
            barValue = 1,
            colorR = 1,
            colorG = 0,
            colorB = 0,
            reverseFill = reverseFill,
            label = "Interrupted",
        })

        local feedbackDuration = _G.MSUF_INTERRUPT_FEEDBACK_DURATION or 0.5
        if type(feedbackDuration) ~= "number" then feedbackDuration = 0.5 end
        if feedbackDuration < 0 then feedbackDuration = 0 end

        if self._msufCastState then
            local now = (type(GetTime) == "function") and GetTime() or 0
            local castState = self._msufCastState
            castState.unit = self.unit
            castState.key = self._msufBarKey or self.unit
            castState.active = false
            castState.phase = "INTERRUPT"
            castState.durationObj = nil
            castState.holdUntil = now + feedbackDuration
        end

        self.hideTimer = true
        self._msufHideToken = (self._msufHideToken or 0) + 1
        local hideToken = self._msufHideToken
        C_Timer.After(feedbackDuration, function()
            if not self or self._msufHideToken ~= hideToken or not self.unit then return end

            local nextState = BuildState(self)
            if nextState and nextState.active then
                self.interrupted = nil
                self:Cast(nextState)
                return
            end

            if self.interrupted then
                self.interrupted = nil
                self:Hide()
            end
        end)
    end

    function frame:SetSucceeded()
        HideChannelHasteMarkers(self)
        if self.interrupted then return end

        SetSafetyOnUpdate(self, false)
        _G.MSUF_CB_ResetStateOnStop(self, "SUCCEEDED")
    end

    SetDriverEventsRegistered(frame, unit, true)
    AnchorDriverFrameToUnitFrame(frame, unit)
    BuildCastbarFrameElements(frame)
    frame:Hide()

    if unit == "target" then
        ExportPublic("MSUF_TargetCastbar", frame)
        ExportPublic("MSUF_TargetCastBar", frame)
    elseif unit == "focus" then
        ExportPublic("MSUF_FocusCastbar", frame)
        ExportPublic("MSUF_FocusCastBar", frame)
    elseif unit == "player" then
        ExportPublic("MSUF_PlayerCastbar", frame)
        ExportPublic("MSUF_PlayerCastBar", frame)
    end

    return frame
end

local function MSUF_EnsureCastbarManager()
    if _G.MSUF_CastbarManager
        and _G.MSUF_RegisterCastbar
        and _G.MSUF_UnregisterCastbar
        and _G.MSUF_UpdateCastbarFrame then
        return
    end
end

local function EnsureDriverUnit(unit)
    if not IsCastbarEnabledForUnit(unit) then
        return nil
    end

    if unit == "target" then
        if not _G.TargetCastBar then
            return CreateCastBar("TargetCastBar", "target")
        end
        return _G.TargetCastBar
    elseif unit == "focus" then
        if not _G.FocusCastBar then
            return CreateCastBar("FocusCastBar", "focus")
        end
        return _G.FocusCastBar
    end

    return nil
end

local function CancelTimerField(frame, key)
    if not frame then return end

    if key == "timer" then
        frame._msufInterruptToken = (frame._msufInterruptToken or 0) + 1
    elseif key == "hideTimer" then
        frame._msufHideToken = (frame._msufHideToken or 0) + 1
    elseif key == "_msufStartRetryTimer" then
        frame._msufStartRetryToken = -1
    elseif key == "_msufStopTimer1" or key == "_msufStopTimer2" or key == "_msufStopTimer3" then
        frame._msufStopExpToken = -1
    end

    frame[key] = nil
end

local function HardHideDriverFrame(frame)
    if not frame then return end

    SetSafetyOnUpdate(frame, false)
    CancelTimerField(frame, "timer")
    CancelTimerField(frame, "hideTimer")
    CancelTimerField(frame, "_msufStopTimer1")
    CancelTimerField(frame, "_msufStopTimer2")
    CancelTimerField(frame, "_msufStopTimer3")
    CancelTimerField(frame, "_msufStartRetryTimer")
    frame._msufStartRetryPending = nil
    frame._msufDeathRecheckPending = nil
    frame.MSUF_castActive = false
    frame.interrupted = nil
    frame.MSUF_kickInterruptibleConfirmed = nil
    HideChannelHasteMarkers(frame)

    if _G.MSUF_CB_ResetStateOnStop then
        _G.MSUF_CB_ResetStateOnStop(frame, "HARDHIDE")
    elseif frame.Hide then
        frame:Hide()
    end

    if _G.MSUF_UnregisterCastbar then
        _G.MSUF_UnregisterCastbar(frame)
    end
    if frame.SetScript then
        frame:SetScript("OnUpdate", nil)
    end
    if frame.Hide then
        frame:Hide()
    end
end

local function GetExistingDriverFrame(unit)
    if unit == "target" then
        return _G.TargetCastBar or _G.MSUF_TargetCastBar or _G.MSUF_TargetCastbar
    elseif unit == "focus" then
        return _G.FocusCastBar or _G.MSUF_FocusCastBar or _G.MSUF_FocusCastbar
    end
    return nil
end

local function ApplyDriverBackendState(unit)
    if unit ~= "target" and unit ~= "focus" then
        return nil
    end

    local enabled = IsCastbarEnabledForUnit(unit)
    local frame = GetExistingDriverFrame(unit)
    if enabled then
        frame = frame or EnsureDriverUnit(unit)
        if frame then
            SetDriverEventsRegistered(frame, unit, true)
        end
        return frame
    end

    if frame then
        SetDriverEventsRegistered(frame, unit, false)
        HardHideDriverFrame(frame)
    end

    return nil
end

local function MSUF_CastbarDriver_OnLogin()
    ApplyDriverBackendState("target")
    ApplyDriverBackendState("focus")
    if _G.MSUF_ReanchorTargetCastBar then _G.MSUF_ReanchorTargetCastBar() end
    if _G.MSUF_ReanchorFocusCastBar then _G.MSUF_ReanchorFocusCastBar() end
    if _G.MSUF_ReanchorPlayerCastBar then _G.MSUF_ReanchorPlayerCastBar() end
    if _G.MSUF_UpdateCastbarVisuals then _G.MSUF_UpdateCastbarVisuals() end
    if _G.MSUF_UpdateCastbarTextures then _G.MSUF_UpdateCastbarTextures() end
end

local function MSUF_CastbarDriver_OnEnteringWorld()
    ApplyDriverBackendState("target")
    ApplyDriverBackendState("focus")

    if _G.PetCastingBarFrame then
        _G.PetCastingBarFrame:UnregisterAllEvents()
        _G.PetCastingBarFrame:Hide()
        _G.PetCastingBarFrame:HookScript("OnShow", function(frame)
            frame:Hide()
        end)
    end

    if _G.MSUF_EventBus_Unregister then
        _G.MSUF_EventBus_Unregister("PLAYER_ENTERING_WORLD", "MSUF_CASTBAR_DRIVER_WORLD")
    end
end

if _G.MSUF_EventBus_Register then
    _G.MSUF_EventBus_Register("PLAYER_LOGIN", "MSUF_CASTBAR_DRIVER_LOGIN", MSUF_CastbarDriver_OnLogin, nil, true)
    _G.MSUF_EventBus_Register("PLAYER_ENTERING_WORLD", "MSUF_CASTBAR_DRIVER_WORLD", MSUF_CastbarDriver_OnEnteringWorld)
end

ExportPublic("MSUF_EnsureCastbarManager", MSUF_EnsureCastbarManager)
ExportPublic("MSUF_CastbarDriver_OnLogin", MSUF_CastbarDriver_OnLogin)
ExportPublic("MSUF_CastbarDriver_OnEnteringWorld", MSUF_CastbarDriver_OnEnteringWorld)
ExportPublic("MSUF_UpdateCastTimeText_FromStatusBar", MSUF_UpdateCastTimeText_FromStatusBar)
ExportPublic("MSUF_CreateCastBar", CreateCastBar)
ExportPublic("MSUF_CastbarDriver_EnsureUnit", EnsureDriverUnit)
ExportPublic("MSUF_CastbarDriver_ApplyBackendState", ApplyDriverBackendState)
