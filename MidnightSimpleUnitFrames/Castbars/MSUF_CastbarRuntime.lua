--- Castbars/MSUF_CastbarRuntime.lua
--- Applies normalized cast-state to visible castbar frames.
---
--- Runtime is the shared mutation layer: timer duration, reverse fill, icon/text,
--- registration with the castbar manager, interrupt visuals, and stop cleanup all
--- pass through here. Keep API reads in Engine/Driver and keep static frame
--- construction in Frames.

local _, ns = ...
ns = ns or _G.MSUF_NS or {}

local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local Runtime = ns.MSUF_CastbarRuntime or {}
ns.MSUF_CastbarRuntime = Runtime
ExportPublic("MSUF_CastbarRuntime", Runtime)

local StatusBarInterpolation = _G.Enum and _G.Enum.StatusBarInterpolation
local StatusBarTimerDirection = _G.Enum and _G.Enum.StatusBarTimerDirection

local INTERPOLATION_IMMEDIATE = (
    type(StatusBarInterpolation) == "table"
    and type(StatusBarInterpolation.Immediate) == "number"
) and StatusBarInterpolation.Immediate or nil

local TIMER_DIRECTION_ELAPSED = (
    type(StatusBarTimerDirection) == "table"
    and type(StatusBarTimerDirection.ElapsedTime) == "number"
) and StatusBarTimerDirection.ElapsedTime or nil

local TIMER_DIRECTION_REMAINING = (
    type(StatusBarTimerDirection) == "table"
    and type(StatusBarTimerDirection.RemainingTime) == "number"
) and StatusBarTimerDirection.RemainingTime or nil

local REASON_SUCCEEDED = "SUCCEEDED"
local REASON_FAILED = "FAILED"
local REASON_INTERRUPTED = "INTERRUPTED"
local REASON_STOPPED = "STOPPED"
local REASON_HARDHIDE = "HARDHIDE"

local EMPTY_OPTIONS = {}
local STOP_TIMERS = { "hideTimer", "succeededTimer" }

local function DisableFrameOnUpdate(frame)
    if not frame or not frame.SetScript then return end
    frame:SetScript("OnUpdate", nil)
end

local function CancelTimerHandle(timer)
    local timerType = type(timer)
    if timerType ~= "table" and timerType ~= "userdata" then
        return
    end

    local cancel = timer.Cancel
    if type(cancel) == "function" then
        cancel(timer)
    end
end

local function Now()
    return (GetTimePreciseSec and GetTimePreciseSec()) or GetTime()
end

--- Dragonflight+ APIs may return value wrappers. Convert only to plain scalars
--- here so the rest of Runtime can compare and cache safely.
local function PlainNumber(value)
    if value == nil then
        return nil
    end

    local toPlain = _G.ToPlain
    if type(toPlain) == "function" then
        local plain = toPlain(value)
        plain = tonumber(tostring(plain))
        if plain ~= nil then
            return plain
        end
    end

    local valueType = type(value)
    if valueType == "number" or valueType == "string" then
        return tonumber(tostring(value))
    end

    return nil
end

local function SetText(frame, textKey, value)
    local fontString = frame and frame[textKey]
    if not fontString then
        return
    end

    local applyTexts = _G.MSUF_CB_ApplyTexts
    if type(applyTexts) == "function" then
        if textKey == "castText" then
            applyTexts(frame, nil, value or "", nil)
        elseif textKey == "timeText" then
            applyTexts(frame, nil, nil, value or "")
        end
    elseif fontString.SetText then
        fontString:SetText(value or "")
    end
end

local function TimerDirection(parent, isChanneled)
    if parent and parent.isEmpower == true then
        return TIMER_DIRECTION_ELAPSED
    end

    if isChanneled == true then
        return TIMER_DIRECTION_REMAINING
    end

    return TIMER_DIRECTION_ELAPSED
end

local function ResolveReverseFill(frame, state, isChanneled)
    if state and state.reverseFill ~= nil then
        return state.reverseFill == true
    end

    if type(_G.MSUF_GetCastbarReverseFillForFrame) == "function" then
        return _G.MSUF_GetCastbarReverseFillForFrame(frame, isChanneled and true or false) == true
    end

    if type(_G.MSUF_GetReverseFillSafe) == "function" then
        return _G.MSUF_GetReverseFillSafe(frame, isChanneled and true or false) == true
    end

    return false
end

--- Prefer Blizzard's StatusBar timer object when available. That lets the
--- client drive smooth progress while MSUF only updates text/glow at its own
--- managed cadence.
function Runtime:ApplyTimer(statusBar, durationObj, reverseFill, isChanneled)
    if not statusBar then
        return false
    end

    if statusBar.SetReverseFill then
        statusBar:SetReverseFill(reverseFill and true or false)
    end

    if not durationObj or not statusBar.SetTimerDuration then
        return false
    end

    local parent = statusBar.GetParent and statusBar:GetParent() or nil
    local timerDirection = TimerDirection(parent, isChanneled)

    if INTERPOLATION_IMMEDIATE ~= nil and timerDirection ~= nil then
        statusBar:SetTimerDuration(durationObj, INTERPOLATION_IMMEDIATE, timerDirection)
    else
        statusBar:SetTimerDuration(durationObj)
    end

    return true
end

function Runtime:ClearTimer()
    return false
end

--- Snapshot duration into plain numbers for fallback text updates and manager
--- buckets. The duration object remains authoritative when the client supports
--- timer-driven StatusBars.
function Runtime:SnapshotDuration(frame, durationObj)
    if not (frame and durationObj) then
        return nil, nil
    end

    local remaining
    if durationObj.GetRemainingDuration then
        remaining = durationObj:GetRemainingDuration()
    elseif durationObj.GetRemaining then
        remaining = durationObj:GetRemaining()
    end

    local total
    if durationObj.GetTotalDuration then
        total = durationObj:GetTotalDuration()
    end

    remaining = PlainNumber(remaining)
    total = PlainNumber(total)

    if remaining and remaining > 0 then
        frame._msufPlainEndTime = Now() + remaining
        frame._msufRemaining = remaining
    else
        frame._msufPlainEndTime = nil
        frame._msufRemaining = nil
    end

    frame._msufPlainTotal = total
    return remaining, total
end

--- Shared active-cast entry used by both readable and legacy driver paths.
--- Options allow callers to skip work they already performed, but the default
--- path fully updates visuals and registers the frame with the manager.
function Runtime:ApplyActive(frame, state, options)
    if not (frame and state and state.active == true) then
        return false
    end

    local durationObj = state.durationObj
    local spellName = state.spellName
    if not durationObj or not spellName then
        return false
    end

    options = options or EMPTY_OPTIONS

    local castType = state.castType or state.phase or "CAST"
    local isChanneled = castType == "CHANNEL"
    local unit = frame.unit or state.unit

    frame.interrupted = nil
    frame.MSUF_castActive = true
    frame.MSUF_durationObj = durationObj
    frame.MSUF_isChanneled = isChanneled

    if options.channelDirect ~= nil then
        frame.MSUF_channelDirect = options.channelDirect and true or nil
    elseif isChanneled and (unit == "target" or unit == "focus") then
        frame.MSUF_channelDirect = true
    else
        frame.MSUF_channelDirect = nil
    end

    if options.resetRuntime ~= false then
        frame.castDuration = nil
        frame.castElapsed = nil
        frame.endTime = nil
        frame.MSUF_timerDriven = nil
        frame.MSUF_timerRangeSet = nil
        frame._msufLastSBValue = nil
        frame._msufHardStopNoChannelSince = nil
        frame._msufHardStopNoCastSince = nil
    end

    if frame.icon and state.icon then
        frame.icon:SetTexture(state.icon)
    end

    SetText(frame, "castText", state.text or spellName or "")

    if options.skipSnapshot ~= true then
        self:SnapshotDuration(frame, durationObj)
    end

    local reverseFill = ResolveReverseFill(frame, state, isChanneled)
    frame._msufStripeReverseFill = reverseFill and true or false
    local timerDriven = self:ApplyTimer(frame.statusBar, durationObj, reverseFill, isChanneled) and true or false
    frame.MSUF_timerDriven = timerDriven
    frame._msufTimerAssumeCountdown = timerDriven and (isChanneled == true) or nil

    local castState = frame._msufCastState or state
    if options.skipCastState ~= true then
        frame._msufCastState = castState
        castState.key = frame._msufBarKey or castState.key
        castState.unit = unit
        castState.active = true
        castState.phase = castType
        castState.castType = castType
        castState.spellName = spellName
        castState.text = state.text or spellName
        castState.icon = state.icon
        castState.durationObj = durationObj
        castState.holdUntil = nil
    end

    if options.skipColor ~= true and frame.UpdateColorForInterruptible then
        frame:UpdateColorForInterruptible()
    end

    if options.skipShow ~= true and frame.Show then
        frame:Show()
    end

    if options.skipRegister ~= true and type(_G.MSUF_RegisterCastbar) == "function" then
        _G.MSUF_RegisterCastbar(frame)
    end

    if options.skipTimeText ~= true
        and frame.timeText
        and type(_G.MSUF_UpdateCastTimeText_FromStatusBar) == "function"
    then
        _G.MSUF_UpdateCastTimeText_FromStatusBar(frame)
    end

    if type(_G.MSUF_UF_ApplyCastbarRangeAlpha) == "function" then
        _G.MSUF_UF_ApplyCastbarRangeAlpha(frame, nil, true)
    end

    return true
end

--- Interrupt feedback is a short-lived visual hold, not an active cast. It uses
--- the same frame so range alpha, outlines, and kick-ready state remain aligned.
function Runtime:ApplyInterrupt(frame, options)
    if not frame then
        return
    end

    options = options or EMPTY_OPTIONS

    local statusBar = frame.statusBar
    if not statusBar then
        return
    end

    if statusBar.SetMinMaxValues then
        statusBar:SetMinMaxValues(0, 1)
    end

    if statusBar.SetValue then
        statusBar:SetValue(options.barValue or 1)
    end

    if options.reverseFill ~= nil and statusBar.SetReverseFill then
        statusBar:SetReverseFill(options.reverseFill and true or false)
    end

    local red = options.colorR or 0.8
    local green = options.colorG or 0.1
    local blue = options.colorB or 0.1

    if type(_G.MSUF_SetStatusBarColorIfChanged) == "function" then
        _G.MSUF_SetStatusBarColorIfChanged(statusBar, red, green, blue, 1)
    elseif statusBar.SetStatusBarColor then
        statusBar:SetStatusBarColor(red, green, blue, 1)
    end

    SetText(frame, "castText", options.label or "Interrupted")
    SetText(frame, "timeText", "")

    if frame.Show then
        frame:Show()
    end

    if frame.SetAlpha then
        frame:SetAlpha(1)
    end

    if type(_G.MSUF_UF_ApplyCastbarRangeAlpha) == "function" then
        _G.MSUF_UF_ApplyCastbarRangeAlpha(frame, nil, true)
    end

    if options.skipShake ~= true and type(_G.MSUF_PlayCastbarShake) == "function" then
        _G.MSUF_PlayCastbarShake(frame)
    end
end

--- Stop cleanup must be centralized because casts can end through normal stop,
--- fail, interrupt, hard hide, unit death, backend disable, or preview teardown.
function Runtime:Stop(frame, reasonOrOptions)
    if not frame then
        return
    end

    local reason = reasonOrOptions
    if type(reasonOrOptions) == "table" then
        reason = reasonOrOptions.reason or reasonOrOptions.kind or reasonOrOptions[1]
    end

    if type(reason) ~= "string" then
        reason = REASON_STOPPED
    end

    DisableFrameOnUpdate(frame)

    if type(_G.MSUF_UnregisterCastbar) == "function" then
        _G.MSUF_UnregisterCastbar(frame)
    end

    frame.MSUF_durationObj = nil
    frame._msufPlainEndTime = nil
    frame._msufRemaining = nil
    frame._msufFastText = nil
    frame._msufPlainTotal = nil
    frame.MSUF_isChanneled = nil
    frame.MSUF_channelDirect = nil
    frame.MSUF_timerDriven = nil
    frame.MSUF_timerRangeSet = nil
    frame._msufLastSBValue = nil
    frame.castDuration = nil
    frame.castElapsed = nil
    frame.MSUF_castActive = false

    local castState = frame._msufCastState
    if castState then
        castState.unit = frame.unit
        castState.key = frame._msufBarKey or frame.unit
        castState.active = false
        castState.phase = (reason == REASON_INTERRUPTED) and "INTERRUPT" or "IDLE"
        castState.durationObj = nil
        castState.holdUntil = nil
    end

    if reason == REASON_HARDHIDE then
        SetText(frame, "timeText", "")

        if frame.latencyBar then
            frame.latencyBar:Hide()
        end

        if frame.Hide then
            frame:Hide()
        end

        return
    end

    if reason == REASON_STOPPED then
        SetText(frame, "timeText", "")
        SetText(frame, "castText", "")

        if frame.latencyBar then
            frame.latencyBar:Hide()
        end

        if not frame.interrupted and frame.Hide then
            frame:Hide()
        end

        return
    end

    for index = 1, #STOP_TIMERS do
        local timerKey = STOP_TIMERS[index]
        local timer = frame[timerKey]

        CancelTimerHandle(timer)

        frame[timerKey] = nil
    end

    if frame.isEmpower and type(_G.MSUF_ClearEmpowerState) == "function" then
        _G.MSUF_ClearEmpowerState(frame)
    end

    if reason == REASON_SUCCEEDED or reason == REASON_FAILED then
        SetText(frame, "castText", "")
        SetText(frame, "timeText", "")

        if frame.Hide then
            frame:Hide()
        end
    end
end

function Runtime:BuildState(unit, previousState)
    local engine = (_G.MSUF_GetCastbarEngine and _G.MSUF_GetCastbarEngine()) or nil
    if engine and engine.BuildState then
        return engine:BuildState(unit, previousState)
    end

    return nil
end

--- Compatibility globals for older castbar files. New code should call Runtime
--- methods through ns when possible, but these exports keep load order flexible.
ExportPublic("MSUF_ApplyTimerAndFill", function(statusBar, durationObj, reverseFill, isChanneled)
    return Runtime:ApplyTimer(statusBar, durationObj, reverseFill, isChanneled)
end)

ExportPublic("MSUF_ApplyCastbarTimerDirection", function(statusBar, durationObj, reverseFill, isChanneled)
    return Runtime:ApplyTimer(statusBar, durationObj, reverseFill, isChanneled)
end)

ExportPublic("MSUF_ClearCastbarTimerDuration", function(statusBar)
    return Runtime:ClearTimer(statusBar)
end)

ExportPublic("MSUF_Castbar_ApplyActiveDuration", function(frame, state, options)
    return Runtime:ApplyActive(frame, state, options)
end)

ExportPublic("MSUF_ApplyInterruptBarVisuals", function(frame, options)
    return Runtime:ApplyInterrupt(frame, options)
end)

ExportPublic("MSUF_CB_ResetStateOnStop", function(frame, reason, options)
    return Runtime:Stop(frame, reason, options)
end)

ExportPublic("MSUF_CastbarRuntime_PlainNumber", PlainNumber)
