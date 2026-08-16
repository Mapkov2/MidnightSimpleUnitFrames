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
local UnitIsConnected = _G.UnitIsConnected
local UnitShouldDisplaySpellTargetName = _G.UnitShouldDisplaySpellTargetName
local UnitSpellTargetName = _G.UnitSpellTargetName
local UnitSpellTargetClass = _G.UnitSpellTargetClass
local C_ClassColor_GetClassColor = _G.C_ClassColor and _G.C_ClassColor.GetClassColor
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local type = type
local tonumber = tonumber
local tostring = tostring
local castbarEngine = MSUF.Castbars and MSUF.Castbars.Engine
local castbarRuntime = MSUF.MSUF_CastbarRuntime or _G.MSUF_CastbarRuntime
local ApplyInterruptValues = castbarRuntime and castbarRuntime.ApplyInterruptValues

local function CastbarEngine()
    if castbarEngine then return castbarEngine end
    local getter = _G.MSUF_GetCastbarEngine
    castbarEngine = type(getter) == "function" and getter() or nil
    return castbarEngine
end

ExportPublic("MSUF_INTERRUPT_FEEDBACK_DURATION", _G.MSUF_INTERRUPT_FEEDBACK_DURATION or 0.5)

local ACTIVE_DURATION_OPTIONS = {
    skipColor = true,
    skipRegister = true,
    skipTimeText = true,
    skipShow = true,
}

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

local ACTIVE_LIFECYCLE_EVENTS = {
    "UNIT_FLAGS",
    "UNIT_CONNECTION",
}

local SetCastLifecycleActive
local HandleUnitDeathEvent

-- Target/focus token changes are owned by the permanent driver events, while
-- dead/ghost and disconnect events are needed only for the short lifetime of
-- an active cast. UNIT_FLAGS is Blizzard's authoritative dead/ghost lifecycle
-- signal and avoids routing every high-frequency UNIT_HEALTH tick through the
-- castbar fallback. Boss frames already own a richer encounter lifecycle.
SetCastLifecycleActive = function(frame, active)
    if not frame or frame.unit == "player" then return true end

    if frame._msufIsBossCastbar then
        local lifecycleReady = frame._msufBossEventsRegistered == true
        if not lifecycleReady then
            if frame._msufBossHealthEventRegistered then
                frame:UnregisterEvent("UNIT_HEALTH")
                frame._msufBossHealthEventRegistered = nil
            end
            frame._msufCastLifecycleOwned = nil
            return false
        end

        if active then
            if not frame._msufBossHealthEventRegistered then
                frame:RegisterUnitEvent("UNIT_HEALTH", frame.unit)
                frame._msufBossHealthEventRegistered = true
            end
        elseif frame._msufBossHealthEventRegistered then
            frame:UnregisterEvent("UNIT_HEALTH")
            frame._msufBossHealthEventRegistered = nil
        end

        frame._msufCastLifecycleOwned = true
        return frame._msufCastLifecycleOwned == true
    end

    if frame.unit ~= "target" and frame.unit ~= "focus" then
        frame._msufCastLifecycleOwned = nil
        return false
    end

    if not active then
        if frame._msufCastLifecycleMode == nil
            and frame._msufActiveLifecycleEventsRegistered == nil
            and frame._msufCastLifecycleOwned == nil
        then
            return true
        end
        if frame._msufActiveLifecycleEventsRegistered then
            for index = 1, #ACTIVE_LIFECYCLE_EVENTS do
                frame:UnregisterEvent(ACTIVE_LIFECYCLE_EVENTS[index])
            end
        end
        frame._msufActiveLifecycleEventsRegistered = nil
        frame._msufCastLifecycleMode = nil
        frame._msufCastLifecycleOwned = nil
        return true
    end

    if frame._msufActiveLifecycleEventsRegistered then
        frame._msufCastLifecycleOwned = true
        return true
    end

    -- RegisterUnitEvent with a compile-time event literal and a validated unit
    -- token does not fail; the old per-event rollback branch was dead weight.
    for index = 1, #ACTIVE_LIFECYCLE_EVENTS do
        frame:RegisterUnitEvent(ACTIVE_LIFECYCLE_EVENTS[index], frame.unit)
    end

    frame._msufActiveLifecycleEventsRegistered = true
    frame._msufCastLifecycleMode = "FLAGS"
    frame._msufCastLifecycleOwned = true
    return true
end

ExportPublic("MSUF_Castbar_SetLifecycleActive", SetCastLifecycleActive)

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
    SetCastLifecycleActive(frame, false)
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
    local uf = MSUF and MSUF.UF
    local unitFrame = uf and type(uf.GetFrame) == "function" and uf.GetFrame(unit) or nil
    unitFrame = unitFrame or (uf and uf.frames and uf.frames[unit]) or _G["MSUF_" .. unit]
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
local RuntimePlainNumber = _G.MSUF_CastbarRuntime_PlainNumber
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

    if RuntimePlainNumber then
        return RuntimePlainNumber(value)
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

local function ToPlainBool(value)
    if value == nil then return false end
    if toPlainIsSecret(value) == true and ToPlain then
        value = ToPlain(value)
    end
    return value == true or value == 1 or value == "true"
end

local function ToKnownPlainBool(value)
    if value == nil then return nil end
    if toPlainIsSecret(value) == true then
        if not ToPlain then return nil end
        value = ToPlain(value)
        if value == nil or toPlainIsSecret(value) == true then return nil end
    end
    if value == true or value == 1 or value == "true" then return true end
    if value == false or value == 0 or value == "false" then return false end
    return nil
end

local function CastStateActive(state)
    return state ~= nil and ToPlainBool(state.active) == true
end

local function CastStateHasSpell(state)
    return CastStateActive(state) and state.spellName ~= nil
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
        local countsDown = frame._msufCountsDown
        if countsDown ~= nil then
            assumeCountdown = countsDown == true
        elseif frame.MSUF_timerDriven == true then
            assumeCountdown = frame.MSUF_isChanneled == true
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
    if frame._msufNativeTimeBound == true then return end

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

local function ClearFrameOnUpdate(frame)
    if not (frame and frame.SetScript) or frame._msufDriverOnUpdateCleared == true then return end
    frame:SetScript("OnUpdate", nil)
    -- Driver frames are bare Frames and this module never installs a Lua
    -- OnUpdate. Remember the one-time cleanup so idle target swaps do not
    -- repeat the native SetScript transition.
    frame._msufDriverOnUpdateCleared = true
end

local function BuildState(frame)
    local engine = CastbarEngine()
    if engine and engine.BuildState then
        return engine:BuildState(frame.unit, frame)
    end
    return nil
end

local function PublishState(frame, state, event)
    local engine = CastbarEngine()
    if engine and engine.Notify and frame and frame.unit then
        engine:Notify(frame.unit, state, event)
    end
end

local function InvalidateBuildState(unit)
    local engine = CastbarEngine()
    if engine and engine.Invalidate then
        engine:Invalidate(unit)
    end
end

local function ResetFallbackTiming(frame)
    frame.endTime = nil
    frame._msufPlainEndTime = nil
    frame._msufPlainTotal = nil
    frame._msufRemaining = nil
    frame._msufLastTimeDecimal = nil
    frame._msufLastTimeTotalDecimal = nil
    frame._msufTimerAssumeCountdown = nil
    frame._msufCountsDown = nil
    frame._msufPushbackMS = nil
    frame._msufLastSBValue = nil
    frame._msufZeroCount = nil
end

local function CaptureFallbackTiming(frame, state)
    if not (frame and state) then return nil, nil end
    local startMS = ToPlainNumber(state.startTimeMS)
    local endMS = ToPlainNumber(state.endTimeMS)
    if type(endMS) ~= "number" then
        return nil, nil
    end

    local now = GetTime and GetTime() or 0
    local endSeconds = endMS / 1000
    local remaining = endSeconds - now
    if type(remaining) ~= "number" or remaining <= 0 then
        return nil, nil
    end

    local total
    if type(startMS) == "number" then
        total = (endMS - startMS) / 1000
    end
    if type(total) ~= "number" or total <= 0 then
        total = remaining
    end
    if remaining > total then
        remaining = total
    end

    frame.endTime = endSeconds
    frame._msufPlainEndTime = endSeconds
    frame._msufPlainTotal = total
    frame._msufRemaining = remaining
    return remaining, total
end

local function SetFallbackStatusBar(frame, remaining, total, reverseFill, countsDown)
    local statusBar = frame and frame.statusBar
    if not (statusBar and statusBar.SetMinMaxValues and statusBar.SetValue) then
        return false
    end
    if statusBar.SetReverseFill then
        statusBar:SetReverseFill(reverseFill and true or false)
    end
    if total <= 0 then
        total = 0.001
    end
    if remaining < 0 then
        remaining = 0
    elseif remaining > total then
        remaining = total
    end
    statusBar:SetMinMaxValues(0, total)
    -- The anchor stays where the fill direction put it; only the value decides
    -- whether the bar fills (elapsed) or drains (remaining).
    statusBar:SetValue(countsDown and remaining or (total - remaining))
    return true
end

local function ApplyFallbackActiveDuration(frame, state, isChannel)
    ResetFallbackTiming(frame)
    local remaining, total = CaptureFallbackTiming(frame, state)
    if not (remaining and total) then
        return false
    end

    frame.interrupted = nil
    frame.MSUF_castActive = true
    frame.MSUF_durationObj = nil
    frame.MSUF_timerDriven = nil
    frame.MSUF_isChanneled = isChannel
    frame.MSUF_channelDirect = (isChannel and (frame.unit == "target" or frame.unit == "focus")) and true or nil
    frame._msufHardStopNoChannelSince = nil
    frame._msufHardStopNoCastSince = nil

    if frame.icon and state.icon then
        frame.icon:SetTexture(state.icon)
    end
    if type(_G.MSUF_CB_ApplyTexts) == "function" then
        _G.MSUF_CB_ApplyTexts(frame, nil, state.text or state.spellName or "", nil)
    elseif frame.castText and frame.castText.SetText then
        frame.castText:SetText(state.text or state.spellName or "")
    end

    local reverseFill = state.reverseFill
    if reverseFill == nil and type(_G.MSUF_GetReverseFillSafe) == "function" then
        reverseFill = _G.MSUF_GetReverseFillSafe(frame, isChannel)
    end
    reverseFill = reverseFill == true
    frame._msufStripeReverseFill = reverseFill
    local countsDown = type(_G.MSUF_GetCastbarCountsDown) == "function"
        and _G.MSUF_GetCastbarCountsDown(frame, isChannel and true or false) == true
    frame._msufCountsDown = countsDown
    frame._msufPushbackMS = ToPlainNumber(state.delayTimeMS)
    if not SetFallbackStatusBar(frame, remaining, total, reverseFill, countsDown) then
        return false
    end

    local castState = frame._msufCastState or {}
    frame._msufCastState = castState
    castState.key = frame._msufBarKey or frame.unit
    castState.unit = frame.unit
    castState.active = true
    castState.phase = state.castType or (isChannel and "CHANNEL" or "CAST")
    castState.castType = castState.phase
    castState.spellName = state.spellName
    castState.text = state.text or state.spellName
    castState.icon = state.icon
    castState.durationObj = nil
    castState.holdUntil = nil
    return true
end

local function StoreActiveStateIdentity(frame, state)
    if not frame then return end

    if CastStateActive(state) then
        frame._msufActiveSeq = state.spellSequenceID
        return
    end

    frame._msufActiveSeq = nil
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
    if frame.MSUF_castActive == true or frame.interrupted or frame.hideTimer then return false end
    if frame.IsShown and frame:IsShown() then return false end
    return true
end

local function RefreshFromEngine(frame, event)
    if frame.interrupted then return end

    local state = BuildState(frame)
    StoreActiveStateIdentity(frame, state)
    if not CastStateHasSpell(state) and CastbarAlreadyIdle(frame) then
        PublishState(frame, state, event)
        return state, false
    end
    frame:Cast(state)
    PublishState(frame, state, event)
    return state, true
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

local function StopDriverFrame(frame, reason)
    if not frame then return end

    ClearStopExpectation(frame)
    ClearStartRetry(frame)
    HideChannelHasteMarkers(frame)
    if frame.castTargetText then
        if type(_G.MSUF_SetTextIfChanged) == "function" then
            _G.MSUF_SetTextIfChanged(frame.castTargetText, "")
        else
            frame.castTargetText:SetText("")
        end
        frame.castTargetText:Hide()
    end
    _G.MSUF_CB_ResetStateOnStop(frame, reason)
    PublishState(frame, nil, reason)
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
        if CastStateActive(state) then
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
        if CastStateActive(state) then
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
        if CastStateActive(state) then
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
        if CastStateActive(state) then
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
        if CastStateActive(state) then
            StoreActiveStateIdentity(frame, state)
            frame:Cast(state)
        end
    end

    frame._msufInactiveRecheckCB = function()
        frame._msufInactiveRecheckPending = nil
        local token = frame._msufInactiveRecheckToken
        frame._msufInactiveRecheckToken = nil
        if frame._msufHideToken ~= token or not frame.unit then return end
        frame.hideTimer = nil

        local nextState = BuildState(frame)
        if CastStateActive(nextState) then
            frame:Cast(nextState)
            return
        end

        _G.MSUF_CB_ResetStateOnStop(frame, "STOPPED")
    end

    frame._msufInterruptHideCB = function()
        local token = frame._msufInterruptHideToken
        local deadline = frame._msufInterruptHideDeadline
        if frame._msufHideToken ~= token or not frame.unit then
            frame._msufInterruptHidePending = nil
            frame._msufInterruptHideToken = nil
            frame._msufInterruptHideDeadline = nil
            return
        end

        local now = (type(GetTime) == "function") and GetTime() or 0
        if deadline and deadline > now then
            C_Timer.After(deadline - now, frame._msufInterruptHideCB)
            return
        end

        frame._msufInterruptHidePending = nil
        frame._msufInterruptHideToken = nil
        frame._msufInterruptHideDeadline = nil
        frame.hideTimer = nil
        local nextState = BuildState(frame)
        if CastStateActive(nextState) then
            frame.interrupted = nil
            frame:Cast(nextState)
            return
        end

        if frame.interrupted then
            frame.interrupted = nil
            frame:Hide()
        end
    end
end

local function AdvanceCastToken(frame)
    frame._msufCastToken = (frame._msufCastToken or 0) + 1
    return frame._msufCastToken
end

local function InvalidateTargetFocusState(frame)
    ClearStopExpectation(frame)
    ClearStartRetry(frame)
    AdvanceCastToken(frame)
    frame.interrupted = nil
    frame.MSUF_kickInterruptibleConfirmed = nil
    StoreActiveStateIdentity(frame, nil)
    InvalidateBuildState(frame.unit)
end

local function CastTargetTextEnabled(frame)
    if not (frame and frame.castTargetText) then return false end
    local unit = frame.unit
    if unit == "target" then
        return _G.MSUF_DB and _G.MSUF_DB.general and _G.MSUF_DB.general.castbarTargetShowTargetName == true
    elseif unit == "focus" then
        return _G.MSUF_DB and _G.MSUF_DB.general and _G.MSUF_DB.general.castbarFocusShowTargetName == true
    elseif frame._msufIsBossCastbar or tostring(unit or ""):match("^boss%d+$") then
        return _G.MSUF_DB and _G.MSUF_DB.general and _G.MSUF_DB.general.showBossCastTargetName == true
    end
    return false
end

local function SetCastTargetText(frame, text)
    local fs = frame and frame.castTargetText
    if not fs then return end
    if type(_G.MSUF_SetTextIfChanged) == "function" then
        _G.MSUF_SetTextIfChanged(fs, text)
    else
        fs:SetText(text)
    end
end

local function SetCastTargetTextPlainColorIfChanged(fs, red, green, blue)
    if fs._msufCastTargetColorPlain == true
        and fs._msufCastTargetColorR == red
        and fs._msufCastTargetColorG == green
        and fs._msufCastTargetColorB == blue
    then
        return
    end
    fs._msufCastTargetColorPlain = true
    fs._msufCastTargetColorR = red
    fs._msufCastTargetColorG = green
    fs._msufCastTargetColorB = blue
    fs:SetTextColor(red, green, blue)
end

local function ApplyCastTargetTextColor(frame, classFilename)
    local fs = frame and frame.castTargetText
    if not fs then return end
    -- A per-castbar target-name color is the most specific choice the user can
    -- make, so it wins over the shared custom color and over the class-color
    -- fallback below. Checked here because this path recolors on every cast and
    -- would otherwise overwrite what the castbar font pass applied.
    local getDetailColor = _G.MSUF_GetCastbarDetailTextColor
    if type(getDetailColor) == "function" and frame.unit then
        local r, g, b, custom = getDetailColor(frame.unit, "TargetName")
        if custom == true then
            SetCastTargetTextPlainColorIfChanged(fs, r, g, b)
            return
        end
    end
    local getCustomColor = _G.MSUF_GetCastbarTargetNameColor
    if type(getCustomColor) == "function" then
        local r, g, b, custom = getCustomColor()
        if custom == true then
            SetCastTargetTextPlainColorIfChanged(fs, r, g, b)
            return
        end
    end
    if classFilename and type(C_ClassColor_GetClassColor) == "function" then
        -- UnitSpellTargetClass returns a secret value. Passing it directly to
        -- C_ClassColor is allowed for tainted callers; indexing any Lua table
        -- with it is not.
        local classColor = C_ClassColor_GetClassColor(classFilename)
        if classColor and type(classColor.GetRGB) == "function" then
            -- GetRGB may return secret numbers. SetTextColor explicitly accepts
            -- them, but Lua comparisons do not. Mark the plain cache invalid
            -- and forward the tuple without retaining or inspecting it.
            fs._msufCastTargetColorPlain = nil
            fs:SetTextColor(classColor:GetRGB())
            return
        end
    end
    SetCastTargetTextPlainColorIfChanged(fs, 1, 1, 1)
end
ExportPublic("MSUF_ApplyCastTargetTextColor", ApplyCastTargetTextColor)

local function AdvanceBuildStateGeneration(unit)
    local engine = CastbarEngine()
    if engine and engine.AdvanceGeneration then
        return engine:AdvanceGeneration(unit)
    end
end

local function ResolveCastTargetInfo(state)
    local engine = (_G.MSUF_GetCastbarEngine and _G.MSUF_GetCastbarEngine()) or nil
    if engine and type(engine.ResolveTargetInfo) == "function" then
        return engine:ResolveTargetInfo(state)
    end

    local unit = state and state.unit
    if not (unit and UnitShouldDisplaySpellTargetName and UnitSpellTargetName) then
        return nil
    end
    if not UnitShouldDisplaySpellTargetName(unit) then
        return nil
    end

    local targetName = UnitSpellTargetName(unit)
    local targetClass
    if UnitSpellTargetClass then targetClass = UnitSpellTargetClass(unit) end
    return targetName, targetClass, true
end

local function UpdateCastTargetText(frame, state)
    local fs = frame and frame.castTargetText
    if not fs then return end
    if not CastTargetTextEnabled(frame) or not CastStateHasSpell(state) then
        SetCastTargetText(frame, "")
        fs:Hide()
        return
    end

    local targetName, targetClass, targetNameAllowed = ResolveCastTargetInfo(state)
    if targetNameAllowed ~= true then
        SetCastTargetText(frame, "")
        fs:Hide()
        return
    end

    SetCastTargetText(frame, targetName)
    ApplyCastTargetTextColor(frame, targetClass)
    fs:Show()
end

local function RefreshCastTargetText(frame)
    if not (frame and frame.castTargetText) then return end
    if not CastTargetTextEnabled(frame) then
        UpdateCastTargetText(frame, nil)
        return
    end
    UpdateCastTargetText(frame, BuildState(frame))
end
ExportPublic("MSUF_RefreshCastTargetText", RefreshCastTargetText)

local function RefreshAllCastTargetTextColors()
    local function RefreshLive(frame)
        if frame and frame.castTargetText then RefreshCastTargetText(frame) end
    end
    local function RefreshPreview(frame)
        if frame and frame.castTargetText then ApplyCastTargetTextColor(frame) end
    end

    RefreshLive(_G.MSUF_TargetCastbar or _G.MSUF_TargetCastBar)
    RefreshLive(_G.MSUF_FocusCastbar or _G.MSUF_FocusCastBar)
    RefreshPreview(_G.MSUF_TargetCastbarPreview)
    RefreshPreview(_G.MSUF_FocusCastbarPreview)

    local bossCastbars = _G.MSUF_BossCastbars
    local maxBossFrames = tonumber(_G.MSUF_MAX_BOSS_FRAMES or _G.MAX_BOSS_FRAMES) or 5
    if maxBossFrames < 1 or maxBossFrames > 12 then maxBossFrames = 5 end
    for index = 1, maxBossFrames do
        RefreshLive((bossCastbars and bossCastbars[index])
            or _G["MSUF_BossCastbar" .. index]
            or _G["MSUF_boss" .. index .. "CastBar"])
        RefreshPreview(index == 1 and (_G.MSUF_BossCastbarPreview or _G.MSUF_BossCastbarPreview1)
            or _G["MSUF_BossCastbarPreview" .. index])
    end
end
ExportPublic("MSUF_RefreshAllCastTargetTextColors", RefreshAllCastTargetTextColors)

local function RefreshTargetFocusChanged(frame)
    if not frame then return false end
    local wasIdle = CastbarAlreadyIdle(frame)
    InvalidateTargetFocusState(frame)

    -- Blizzard's live TargetSpellBarMixin resolves UnitCastingInfo and
    -- UnitChannelInfo synchronously on PLAYER_TARGET_CHANGED. Do the same:
    -- retire the old unit first, then build the replacement state in this
    -- event instead of paying for a zero-delay callback on every target swap.
    if not wasIdle then
        StopDriverFrame(frame, "HARDHIDE")
    else
        ClearFrameOnUpdate(frame)
    end

    local state = BuildState(frame)
    if CastStateHasSpell(state) then
        StoreActiveStateIdentity(frame, state)
        frame:Cast(state)
        return true
    end

    return false
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

HandleUnitDeathEvent = function(frame, event)
    if not frame:IsShown() or frame.interrupted or frame.MSUF_castActive ~= true then return end

    local unit = frame.unit
    local exists, dead, connected
    -- UNIT_HEALTH is the active-boss fast signal. Keep that hot path to the
    -- single authoritative death read; sparse FLAGS/CONNECTION events own the
    -- missing-unit and connection fallbacks.
    if event ~= "UNIT_HEALTH" and unit then
        exists = ToKnownPlainBool(UnitExists(unit))
        if UnitIsConnected then connected = ToKnownPlainBool(UnitIsConnected(unit)) end
    end
    if unit and UnitIsDeadOrGhost then
        dead = ToKnownPlainBool(UnitIsDeadOrGhost(unit))
    end
    if exists == false or dead == true or connected == false then
        StopDriverFrame(frame, "STOPPED")
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

--- Cold path (an interrupt is a one-shot): builds the "Interrupted by <name>"
--- label from the event's interrupter GUID, mirroring Blizzard's
--- CastingBarMixin:GetInterruptText. Fails open to the plain label whenever the
--- per-unit toggle is off or identity is restricted (secret GUID/name), so a
--- PvP-restricted interrupter can never raise.
function _G.MSUF_Castbar_ResolveInterruptLabel(interruptedBy, unit, fallback)
    fallback = fallback or "Interrupted"
    local issecret = _G.issecretvalue
    if interruptedBy == nil or (issecret and issecret(interruptedBy) == true) then
        return fallback
    end
    local db = _G.MSUF_DB
    local unitDB = db and unit and db[unit] or nil
    if unitDB == nil and type(unit) == "string" and unit:find("^boss") ~= nil then
        unitDB = db and db.boss or nil
    end
    if not (unitDB and unitDB.showInterruptSource == true) then
        return fallback
    end
    local nameFromGUID = _G.UnitNameFromGUID
    if type(nameFromGUID) ~= "function" then return fallback end
    local name = nameFromGUID(interruptedBy)
    if (issecret and issecret(name) == true) or type(name) ~= "string" or name == "" then
        return fallback
    end
    local classFromGUID = _G.UnitClassFromGUID
    if type(classFromGUID) == "function" then
        local _, classFilename = classFromGUID(interruptedBy)
        if not (issecret and issecret(classFilename) == true)
            and type(classFilename) == "string" and classFilename ~= "" then
            -- Class color through the secret-safe C API, never a Lua table
            -- keyed by class (castbar_target_name_color contract).
            local getClassColor = _G.C_ClassColor and _G.C_ClassColor.GetClassColor
            local classColor = type(getClassColor) == "function" and getClassColor(classFilename) or nil
            if classColor and classColor.WrapTextInColorCode then
                name = classColor:WrapTextInColorCode(name)
            end
        end
    end
    local fmt = _G.SPELL_INTERRUPTED_BY
    if type(fmt) == "string" and fmt:find("%%s") ~= nil then
        return fmt:format(name)
    end
    return fallback
end

local function HandleDriverEvent(frame, event, eventUnit, _castID, _spellID, interruptedBy)
    if frame._msufDriverBackendEnabled ~= true then
        if frame.unit == "target" or frame.unit == "focus" then
            SetDriverEventsRegistered(frame, frame.unit, false)
        end
        StopDriverFrame(frame, "HARDHIDE")
        return
    end

    if (event == "PLAYER_TARGET_CHANGED" and frame.unit == "target")
        or (event == "PLAYER_FOCUS_CHANGED" and frame.unit == "focus") then
        RefreshTargetFocusChanged(frame)
        return
    end

    if event == "UNIT_HEALTH" or event == "UNIT_FLAGS" or event == "UNIT_CONNECTION" then
        HandleUnitDeathEvent(frame, event)
        return
    end

    event = NormalizeEventForUnit(frame, event)

    if event == "UNIT_SPELLCAST_START"
        or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_EMPOWER_START" then
        ClearStopExpectation(frame)
        ClearStartRetry(frame)
        AdvanceBuildStateGeneration(frame.unit)
        local token = AdvanceCastToken(frame)
        frame.isNotInterruptible = false
        frame.MSUF_kickInterruptibleConfirmed = nil
        local state = RefreshFromEngine(frame, event)

        if not CastStateHasSpell(state) then
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
        InvalidateBuildState(frame.unit)
        if event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
            and (frame._msufStopTimer1 or frame._msufStopTimer2 or frame._msufStopTimer3) then
            ClearStopExpectation(frame)
            AdvanceCastToken(frame)
        end
        RefreshFromEngine(frame, event)
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
        InvalidateBuildState(frame.unit)
        if frame.unit ~= "player" then
            RefreshFromEngine(frame, event)
            return
        end

        local state = BuildState(frame)
        if CastStateActive(state) then
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
        local state = frame._msufCastState
        if state then
            state.isNotInterruptible = false
            state.apiNotInterruptibleRaw = false
        end
        PublishState(frame, state, event)
        return
    end

    if event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        if eventUnit ~= frame.unit then return end
        frame.isNotInterruptible = true
        frame.MSUF_kickInterruptibleConfirmed = false
        frame._msufApiNotInterruptibleRaw = true
        if frame.UpdateColorForInterruptible then _G.MSUF_CB_ApplyColor(frame) end
        local state = frame._msufCastState
        if state then
            state.isNotInterruptible = true
            state.apiNotInterruptibleRaw = true
        end
        PublishState(frame, state, event)
        return
    end

    if event == "UNIT_SPELLCAST_INTERRUPTED" then
        if eventUnit ~= frame.unit then return end
        ClearStopExpectation(frame)
        frame.MSUF_kickInterruptibleConfirmed = nil
        frame:SetInterrupted(interruptedBy)
        PublishState(frame, nil, event)
        return
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
    frame._msufCastbarDriver = true
    frame._msufBarKey = unit
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
        return HandleDriverEvent(self, event, eventUnit, ...)
    end)

    function frame:Cast(state)
        if not (CastStateHasSpell(state) and state.unit == self.unit) then
            state = BuildState(self)
        end

        if state ~= nil then
            self._msufApiNotInterruptibleRaw = state.apiNotInterruptibleRaw
        else
            self._msufApiNotInterruptibleRaw = nil
        end

        local spellName, label, icon, startTimeMS, endTimeMS
        local isChannel = false
        if CastStateHasSpell(state) then
            spellName = state.spellName
            label = state.text or state.spellName
            icon = state.icon
            startTimeMS = state.startTimeMS
            endTimeMS = state.endTimeMS
            isChannel = state.castType == "CHANNEL"
        end

        if self.hideTimer then
            self._msufHideToken = (self._msufHideToken or 0) + 1
            self.hideTimer = nil
        end
        if self.succeededTimer then
            self.succeededTimer = nil
        end

        local durationObj = (state and state.durationObj ~= nil) and state.durationObj or nil
        if durationObj == nil and CastStateActive(state) then
            local sequenceID = state.spellSequenceID
            if type(sequenceID) == "number"
                and self._msufLastDurationSeq == sequenceID
                and self._msufLastDurationObj ~= nil then
                durationObj = self._msufLastDurationObj
                state.durationObj = durationObj
            end
        end

        if CastStateActive(state) and durationObj ~= nil then
            local sequenceID = state.spellSequenceID
            if type(sequenceID) == "number" then
                self._msufLastDurationSeq = sequenceID
                self._msufLastDurationObj = durationObj
            end
        elseif not CastStateActive(state) then
            self._msufApiNotInterruptibleRaw = nil
            self._msufLastDurationSeq = nil
            self._msufLastDurationObj = nil
        end

        if self.isEmpower then
            ClearEmpowerState(self)
        end

        if spellName and (durationObj or ApplyFallbackActiveDuration(self, state, isChannel)) then
            if self.PrepareForCast then self:PrepareForCast() end
            SetCastLifecycleActive(self, true)
            if durationObj then
                state.durationObj = durationObj
                state.text = label or spellName
                state.icon = icon
                _G.MSUF_Castbar_ApplyActiveDuration(self, state, ACTIVE_DURATION_OPTIONS)
            end

            -- ApplyActive already resolved and installed reverse fill for the
            -- native-duration path. Only the legacy fallback still needs the
            -- global resolver.
            local reverseFill
            if durationObj then reverseFill = self._msufStripeReverseFill end
            if reverseFill == nil then
                reverseFill = _G.MSUF_GetReverseFillSafe(self, isChannel)
            end
            reverseFill = reverseFill == true
            self._msufStripeReverseFill = reverseFill
            UpdateChannelHasteMarkers(self, true)

            if self.UpdateColorForInterruptible then
                -- ApplyColor owns the single KickReady refresh; pass the state
                -- through so the decorator does not have to infer it again.
                _G.MSUF_CB_ApplyColor(self, state)
            end
            self:Show()
            self.MSUF_castActive = true
            if _G.MSUF_RegisterCastbar then
                _G.MSUF_RegisterCastbar(self)
            end
            if self.timeText
                and self._msufNativeTimeBound ~= true
                and self._msufCastTimeEnabled ~= false
            then
                _G.MSUF_UpdateCastTimeText_FromStatusBar(self)
            end
            UpdateCastTargetText(self, state)

            if self.unit ~= "player" then
                self._msufZeroCount = nil
                ClearFrameOnUpdate(self)
            end
        else
            SetCastLifecycleActive(self, false)
            ClearFrameOnUpdate(self)
            self.MSUF_castActive = false
            self.MSUF_kickInterruptibleConfirmed = nil
            UpdateCastTargetText(self, nil)
            if self.kickReadyBox then self.kickReadyBox:Hide() end
            if _G.MSUF_KickReady_RefreshFrame then _G.MSUF_KickReady_RefreshFrame(self, nil) end

            if self.hideTimer then
                self._msufHideToken = (self._msufHideToken or 0) + 1
            end
            self.hideTimer = true
            self._msufHideToken = (self._msufHideToken or 0) + 1
            EnsureDriverCallbacks(self)
            self._msufInactiveRecheckToken = self._msufHideToken
            if not self._msufInactiveRecheckPending then
                self._msufInactiveRecheckPending = true
                C_Timer.After(0, self._msufInactiveRecheckCB)
            end
        end

    end

    function frame:SetInterrupted(interruptedBy)
        HideChannelHasteMarkers(self)
        ClearFrameOnUpdate(self)
        self._msufHideToken = (self._msufHideToken or 0) + 1
        self._msufInactiveRecheckToken = nil
        self._msufInterruptHideToken = nil
        self._msufInterruptHideDeadline = nil
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
        local interruptLabel = "Interrupted"
        if type(_G.MSUF_Castbar_ResolveInterruptLabel) == "function" then
            interruptLabel = _G.MSUF_Castbar_ResolveInterruptLabel(interruptedBy, self.unit, interruptLabel)
        end
        if ApplyInterruptValues then
            ApplyInterruptValues(castbarRuntime, self, 1, reverseFill, interruptLabel)
        else
            _G.MSUF_ApplyInterruptBarVisuals(self, {
                barValue = 1,
                reverseFill = reverseFill,
                label = interruptLabel,
            })
        end

        local getFeedbackDuration = _G.MSUF_GetInterruptFeedbackDuration
        local feedbackDuration = type(getFeedbackDuration) == "function" and getFeedbackDuration() or 0.5

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
        EnsureDriverCallbacks(self)
        self._msufInterruptHideToken = self._msufHideToken
        self._msufInterruptHideDeadline = ((type(GetTime) == "function") and GetTime() or 0) + feedbackDuration
        if not self._msufInterruptHidePending then
            self._msufInterruptHidePending = true
            C_Timer.After(feedbackDuration, self._msufInterruptHideCB)
        end
    end

    function frame:SetSucceeded()
        HideChannelHasteMarkers(self)
        if self.interrupted then return end

        ClearFrameOnUpdate(self)
        _G.MSUF_CB_ResetStateOnStop(self, "SUCCEEDED")
        PublishState(self, nil, "SUCCEEDED")
    end

    SetDriverEventsRegistered(frame, unit, true)
    AnchorDriverFrameToUnitFrame(frame, unit)
    BuildCastbarFrameElements(frame)
    ClearFrameOnUpdate(frame)
    -- Resolve the shared ColorObjects while this hidden frame is constructed;
    -- otherwise their first CreateColor calls land in the first active cast.
    if frame.UpdateColorForInterruptible then
        frame:UpdateColorForInterruptible()
    end
    local runtime = MSUF.MSUF_CastbarRuntime or _G.MSUF_CastbarRuntime
    if runtime and runtime.PrewarmNativeTimeText then
        runtime:PrewarmNativeTimeText(frame)
    end
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

local function EnsureDriverUnit(unit)
    if not IsCastbarEnabledForUnit(unit) then
        return nil
    end

    if unit == "target" then
        local frame = _G.MSUF_TargetCastBar or _G.MSUF_TargetCastbar
        if frame and frame._msufCastbarDriver == true then
            return frame
        end
        frame = _G.TargetCastBar
        if frame and frame._msufCastbarDriver == true then
            return frame
        end
        return CreateCastBar("MSUF_TargetCastBar", "target")
    elseif unit == "focus" then
        local frame = _G.MSUF_FocusCastBar or _G.MSUF_FocusCastbar
        if frame and frame._msufCastbarDriver == true then
            return frame
        end
        frame = _G.FocusCastBar
        if frame and frame._msufCastbarDriver == true then
            return frame
        end
        return CreateCastBar("MSUF_FocusCastBar", "focus")
    end

    return nil
end

local function CancelTimerField(frame, key)
    if not frame then return end

    if key == "hideTimer" then
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

    ClearFrameOnUpdate(frame)
    CancelTimerField(frame, "hideTimer")
    CancelTimerField(frame, "_msufStopTimer1")
    CancelTimerField(frame, "_msufStopTimer2")
    CancelTimerField(frame, "_msufStopTimer3")
    CancelTimerField(frame, "_msufStartRetryTimer")
    frame._msufStartRetryPending = nil
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
end

local function GetExistingDriverFrame(unit)
    if unit == "target" then
        local frame = _G.MSUF_TargetCastBar or _G.MSUF_TargetCastbar
        if frame and frame._msufCastbarDriver == true then return frame end
        frame = _G.TargetCastBar
        if frame and frame._msufCastbarDriver == true then return frame end
    elseif unit == "focus" then
        local frame = _G.MSUF_FocusCastBar or _G.MSUF_FocusCastbar
        if frame and frame._msufCastbarDriver == true then return frame end
        frame = _G.FocusCastBar
        if frame and frame._msufCastbarDriver == true then return frame end
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

local function ApplyCastbarUnitCold(unit)
    if type(_G.MSUF_ApplyCastbarUnitAndSync) == "function" then
        _G.MSUF_ApplyCastbarUnitAndSync(unit)
        return true
    end
    if unit == "target" and type(_G.MSUF_ReanchorTargetCastBarBase) == "function" then
        _G.MSUF_ReanchorTargetCastBarBase()
    elseif unit == "focus" and type(_G.MSUF_ReanchorFocusCastBarBase) == "function" then
        _G.MSUF_ReanchorFocusCastBarBase()
    elseif unit == "player" and type(_G.MSUF_ReanchorPlayerCastBarBase) == "function" then
        _G.MSUF_ReanchorPlayerCastBarBase()
    end
    if type(_G.MSUF_ApplyCastbarVisualsForUnit) == "function" then
        _G.MSUF_ApplyCastbarVisualsForUnit(unit)
        return true
    end
    return false
end

local function MSUF_CastbarDriver_OnLogin()
    local any = _G.MSUF_AreAnyCastbarsEnabled
    if type(any) == "function" and not any() then return end
    ApplyDriverBackendState("target")
    ApplyDriverBackendState("focus")
    local applied = false
    applied = ApplyCastbarUnitCold("target") or applied
    applied = ApplyCastbarUnitCold("focus") or applied
    applied = ApplyCastbarUnitCold("player") or applied
    if not applied then
        if _G.MSUF_UpdateCastbarVisuals then _G.MSUF_UpdateCastbarVisuals() end
    end
    if _G.MSUF_UpdateCastbarTextures then _G.MSUF_UpdateCastbarTextures() end
end

local function MSUF_CastbarDriver_OnEnteringWorld()
    local any = _G.MSUF_AreAnyCastbarsEnabled
    if type(any) == "function" and not any() then return end
    ApplyDriverBackendState("target")
    ApplyDriverBackendState("focus")

    if _G.MSUF_EventBus_Unregister then
        _G.MSUF_EventBus_Unregister("PLAYER_ENTERING_WORLD", "MSUF_CASTBAR_DRIVER_WORLD")
    end
end

local function SyncCastbarDriverLifecycle(runNow)
    if not _G.MSUF_EventBus_Register then return false end
    if _G.MSUF_EventBus_Unregister then
        _G.MSUF_EventBus_Unregister("PLAYER_LOGIN", "MSUF_CASTBAR_DRIVER_LOGIN")
        _G.MSUF_EventBus_Unregister("PLAYER_ENTERING_WORLD", "MSUF_CASTBAR_DRIVER_WORLD")
    end
    local any = _G.MSUF_AreAnyCastbarsEnabled
    if type(any) == "function" and not any() then return false end
    _G.MSUF_EventBus_Register("PLAYER_LOGIN", "MSUF_CASTBAR_DRIVER_LOGIN", MSUF_CastbarDriver_OnLogin, nil, true)
    _G.MSUF_EventBus_Register("PLAYER_ENTERING_WORLD", "MSUF_CASTBAR_DRIVER_WORLD", MSUF_CastbarDriver_OnEnteringWorld)
    if runNow == true then MSUF_CastbarDriver_OnLogin() end
    return true
end
SyncCastbarDriverLifecycle(false)

ExportPublic("MSUF_UpdateCastTimeText_FromStatusBar", MSUF_UpdateCastTimeText_FromStatusBar)
ExportPublic("MSUF_CreateCastBar", CreateCastBar)
ExportPublic("MSUF_CastbarDriver_ApplyBackendState", ApplyDriverBackendState)
ExportPublic("MSUF_CastbarDriver_SyncLifecycle", SyncCastbarDriverLifecycle)
