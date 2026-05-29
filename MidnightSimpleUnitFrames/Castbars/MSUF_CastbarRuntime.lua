-- Castbars/MSUF_CastbarRuntime.lua
-- Compact runtime core for all MSUF castbars.
--
-- This module owns the hot runtime surface:
--   * DurationObject -> StatusBar timer setup
--   * plain duration snapshots for text/safety updates
--   * active cast/channel application
--   * interrupt bar visuals
--   * stop/reset lifecycle
--
-- Options, previews, anchoring, frame construction, empower layout, latency, and
-- boss/player event adapters stay in their existing files.

local addonName, ns = ...
ns = ns or {}

local R = ns.MSUF_CastbarRuntime or {}
ns.MSUF_CastbarRuntime = R
_G.MSUF_CastbarRuntime = R

local enumInterp = _G.Enum and _G.Enum.StatusBarInterpolation
local enumDir = _G.Enum and _G.Enum.StatusBarTimerDirection

local TIMER_INTERP_IMMEDIATE = (type(enumInterp) == "table" and type(enumInterp.Immediate) == "number") and enumInterp.Immediate or nil
local TIMER_DIR_ELAPSED = (type(enumDir) == "table" and type(enumDir.ElapsedTime) == "number") and enumDir.ElapsedTime or nil
local TIMER_DIR_REMAINING = (type(enumDir) == "table" and type(enumDir.RemainingTime) == "number") and enumDir.RemainingTime or nil

local STOP_REASON_SUCCEEDED = "SUCCEEDED"
local STOP_REASON_FAILED = "FAILED"
local STOP_REASON_INTERRUPTED = "INTERRUPTED"
local STOP_REASON_STOPPED = "STOPPED"
local STOP_REASON_HARDHIDE = "HARDHIDE"

local EMPTY_OPTS = {}
local STOP_TIMER_KEYS = { "hideTimer", "succeededTimer", "timer" }

local function Now()
    return (GetTimePreciseSec and GetTimePreciseSec()) or GetTime()
end

local function PlainNumber(v)
    if v == nil then return nil end
    local toPlain = _G.ToPlain
    if type(toPlain) == "function" then
        local pv = toPlain(v)
        local pn = tonumber(tostring(pv))
        if pn ~= nil then return pn end
    end
    local t = type(v)
    if t == "number" or t == "string" then
        return tonumber(tostring(v))
    end
    return nil
end

local function SetText(frame, which, text)
    local fs = frame and frame[which]
    if not fs then return end
    local applyTexts = _G.MSUF_CB_ApplyTexts
    if type(applyTexts) == "function" then
        if which == "castText" then
            applyTexts(frame, nil, text or "", nil)
        elseif which == "timeText" then
            applyTexts(frame, nil, nil, text or "")
        end
    elseif fs.SetText then
        fs:SetText(text or "")
    end
end

local function ResolveTimerDirection(frame, isChanneled)
    if frame and frame.isEmpower == true then
        return TIMER_DIR_ELAPSED
    end
    if isChanneled == true then
        return TIMER_DIR_REMAINING
    end
    return TIMER_DIR_ELAPSED
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

function R:ApplyTimer(statusBar, durationObj, reverseFill, isChanneled)
    if not statusBar then return false end

    if statusBar.SetReverseFill then
        statusBar:SetReverseFill(reverseFill and true or false)
    end

    if not durationObj or not statusBar.SetTimerDuration then
        return false
    end

    local owner = statusBar.GetParent and statusBar:GetParent() or nil
    local direction = ResolveTimerDirection(owner, isChanneled)

    if TIMER_INTERP_IMMEDIATE ~= nil and direction ~= nil then
        statusBar:SetTimerDuration(durationObj, TIMER_INTERP_IMMEDIATE, direction)
    else
        statusBar:SetTimerDuration(durationObj)
    end

    return true
end

function R:SetTimerDuration(statusBar, durationObj, isChanneled)
    if not statusBar or not durationObj or not statusBar.SetTimerDuration then
        return false
    end

    local owner = statusBar.GetParent and statusBar:GetParent() or nil
    local direction = ResolveTimerDirection(owner, isChanneled)
    if TIMER_INTERP_IMMEDIATE ~= nil and direction ~= nil then
        statusBar:SetTimerDuration(durationObj, TIMER_INTERP_IMMEDIATE, direction)
    else
        statusBar:SetTimerDuration(durationObj)
    end

    return true
end

function R:SetReverseFill(statusBar, reverseFill)
    if not statusBar or not statusBar.SetReverseFill then return false end
    statusBar:SetReverseFill(reverseFill and true or false)
    return true
end

function R:ClearTimer(statusBar)
    -- Midnight rejects nil duration. Clear by replacing visual state manually in
    -- stop/interrupt paths; the next cast installs a fresh DurationObject.
    return false
end

function R:SnapshotDuration(frame, durationObj)
    if not (frame and durationObj) then return nil, nil end

    local rem
    if durationObj.GetRemainingDuration then
        rem = durationObj:GetRemainingDuration()
    elseif durationObj.GetRemaining then
        rem = durationObj:GetRemaining()
    end

    local total
    if durationObj.GetTotalDuration then
        total = durationObj:GetTotalDuration()
    end

    local remNum = PlainNumber(rem)
    local totalNum = PlainNumber(total)

    if remNum and remNum > 0 then
        frame._msufPlainEndTime = Now() + remNum
        frame._msufRemaining = remNum
    else
        frame._msufPlainEndTime = nil
        frame._msufRemaining = nil
    end

    frame._msufPlainTotal = totalNum
    return remNum, totalNum
end

function R:ApplyActive(frame, state, opts)
    if not (frame and state and state.active == true) then return false end

    local durationObj = state.durationObj
    local spellName = state.spellName
    if not durationObj or not spellName then return false end

    opts = opts or EMPTY_OPTS

    local castType = state.castType or state.phase or "CAST"
    local isChanneled = (castType == "CHANNEL")
    local unit = frame.unit or state.unit

    frame.interrupted = nil
    frame.MSUF_castActive = true
    frame.MSUF_durationObj = durationObj
    frame.MSUF_isChanneled = isChanneled

    if opts.channelDirect ~= nil then
        frame.MSUF_channelDirect = opts.channelDirect and true or nil
    elseif isChanneled and (unit == "target" or unit == "focus") then
        frame.MSUF_channelDirect = true
    else
        frame.MSUF_channelDirect = nil
    end

    if opts.resetRuntime ~= false then
        frame.castDuration = nil
        frame.castElapsed = nil
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

    if opts.skipSnapshot ~= true then
        self:SnapshotDuration(frame, durationObj)
    end

    local reverseFill = ResolveReverseFill(frame, state, isChanneled)
    frame._msufStripeReverseFill = reverseFill and true or false
    frame.MSUF_timerDriven = self:ApplyTimer(frame.statusBar, durationObj, reverseFill, isChanneled) and true or false

    local st = frame._msufCastState or state
    if opts.skipCastState ~= true then
        frame._msufCastState = st
        st.key = frame._msufBarKey or st.key
        st.unit = unit
        st.active = true
        st.phase = castType
        st.castType = castType
        st.spellName = spellName
        st.text = state.text or spellName
        st.icon = state.icon
        st.durationObj = durationObj
        st.holdUntil = nil
    end

    if opts.skipColor ~= true and frame.UpdateColorForInterruptible then
        frame:UpdateColorForInterruptible()
    end

    if opts.skipRegister ~= true and type(_G.MSUF_RegisterCastbar) == "function" then
        _G.MSUF_RegisterCastbar(frame)
    end

    if opts.skipTimeText ~= true and frame.timeText and type(_G.MSUF_UpdateCastTimeText_FromStatusBar) == "function" then
        _G.MSUF_UpdateCastTimeText_FromStatusBar(frame)
    end

    if opts.skipShow ~= true and frame.Show then
        frame:Show()
    end

    return true
end

function R:ApplyInterrupt(frame, opts)
    if not frame then return end
    opts = opts or EMPTY_OPTS

    local sb = frame.statusBar
    if not sb then return end

    if sb.SetMinMaxValues then sb:SetMinMaxValues(0, 1) end
    if sb.SetValue then sb:SetValue(opts.barValue or 1) end

    if opts.reverseFill ~= nil and sb.SetReverseFill then
        sb:SetReverseFill(opts.reverseFill and true or false)
    end

    local r = opts.colorR or 0.8
    local g = opts.colorG or 0.1
    local b = opts.colorB or 0.1
    if type(_G.MSUF_SetStatusBarColorIfChanged) == "function" then
        _G.MSUF_SetStatusBarColorIfChanged(sb, r, g, b, 1)
    elseif sb.SetStatusBarColor then
        sb:SetStatusBarColor(r, g, b, 1)
    end

    SetText(frame, "castText", opts.label or "Interrupted")
    SetText(frame, "timeText", "")

    if frame.Show then frame:Show() end
    if frame.SetAlpha then frame:SetAlpha(1) end

    if opts.skipShake ~= true and type(_G.MSUF_PlayCastbarShake) == "function" then
        _G.MSUF_PlayCastbarShake(frame)
    end
end

function R:Stop(frame, reasonOrState, opts)
    if not frame then return end
    opts = opts or EMPTY_OPTS

    local reason = reasonOrState
    if type(reasonOrState) == "table" then
        reason = reasonOrState.reason or reasonOrState.kind or reasonOrState[1]
    end
    if type(reason) ~= "string" then
        reason = STOP_REASON_STOPPED
    end

    if frame.SetScript then frame:SetScript("OnUpdate", nil) end
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

    local st = frame._msufCastState
    if st then
        st.unit = frame.unit
        st.key = frame._msufBarKey or frame.unit
        st.active = false
        st.phase = (reason == STOP_REASON_INTERRUPTED) and "INTERRUPT" or "IDLE"
        st.durationObj = nil
        st.holdUntil = nil
    end

    if reason == STOP_REASON_HARDHIDE then
        SetText(frame, "timeText", "")
        if frame.latencyBar then frame.latencyBar:Hide() end
        if frame.Hide then frame:Hide() end
        return
    end

    if reason == STOP_REASON_STOPPED then
        SetText(frame, "timeText", "")
        SetText(frame, "castText", "")
        if frame.latencyBar then frame.latencyBar:Hide() end
        if not frame.interrupted and frame.Hide then frame:Hide() end
        return
    end

    for i = 1, #STOP_TIMER_KEYS do
        local key = STOP_TIMER_KEYS[i]
        local t = frame[key]
        if t and t.Cancel then t:Cancel() end
        frame[key] = nil
    end

    if frame.isEmpower and type(_G.MSUF_ClearEmpowerState) == "function" then
        _G.MSUF_ClearEmpowerState(frame)
    end

    if reason == STOP_REASON_SUCCEEDED or reason == STOP_REASON_FAILED then
        SetText(frame, "castText", "")
        SetText(frame, "timeText", "")
        if frame.Hide then frame:Hide() end
        return
    end

    -- INTERRUPTED deliberately leaves text/show/color to ApplyInterrupt callers.
end

function R:BuildState(unit, frameHint)
    local E = (_G.MSUF_GetCastbarEngine and _G.MSUF_GetCastbarEngine()) or nil
    if E and E.BuildState then
        return E:BuildState(unit, frameHint)
    end
    return nil
end

-- Compatibility globals used throughout existing modules.
_G.MSUF_ApplyTimerAndFill = function(statusBar, durationObj, reverseFill, isChanneled)
    return R:ApplyTimer(statusBar, durationObj, reverseFill, isChanneled)
end

_G.MSUF_SetStatusBarTimerDuration = function(statusBar, durationObj, isChanneled)
    return R:SetTimerDuration(statusBar, durationObj, isChanneled)
end

_G.MSUF_SetStatusBarReverseFill = function(statusBar, reverseFill)
    return R:SetReverseFill(statusBar, reverseFill)
end

_G.MSUF_ApplyCastbarTimerDirection = function(statusBar, durationObj, reverseFill, isChanneled)
    return R:ApplyTimer(statusBar, durationObj, reverseFill, isChanneled)
end

_G.MSUF_ApplyStatusBarTimerAndReverse = _G.MSUF_ApplyCastbarTimerDirection

_G.MSUF_ClearCastbarTimerDuration = function(statusBar)
    return R:ClearTimer(statusBar)
end
_G.MSUF_ClearStatusBarTimerDuration = _G.MSUF_ClearCastbarTimerDuration

_G.MSUF_Castbar_ApplyActiveDuration = function(frame, state, opts)
    return R:ApplyActive(frame, state, opts)
end

_G.MSUF_ApplyInterruptBarVisuals = function(frame, opts)
    return R:ApplyInterrupt(frame, opts)
end

_G.MSUF_CB_ResetStateOnStop = function(frame, reasonOrState, opts)
    return R:Stop(frame, reasonOrState, opts)
end

_G.MSUF_CastbarRuntime_PlainNumber = PlainNumber
