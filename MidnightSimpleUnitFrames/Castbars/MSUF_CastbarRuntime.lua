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

-- A castbar only belongs in the Lua manager while at least one of these jobs
-- still has to be performed by Lua.  The mask is compiled when a cast starts
-- (and when the cold settings revision changes), never in the update loop.
local WORK_TIME_TEXT = 1
local WORK_GLOW = 2
local WORK_CHANNEL = 4
local WORK_EMPOWER = 8
local WORK_DURATION_FALLBACK = 16
local WORK_UNIT_FAILSAFE = 32

Runtime.WorkMask = Runtime.WorkMask or {
    TIME_TEXT = WORK_TIME_TEXT,
    GLOW = WORK_GLOW,
    CHANNEL = WORK_CHANNEL,
    EMPOWER = WORK_EMPOWER,
    DURATION_FALLBACK = WORK_DURATION_FALLBACK,
    UNIT_FAILSAFE = WORK_UNIT_FAILSAFE,
}

local activeDurationFrames = Runtime._activeDurationFrames
if not activeDurationFrames then
    activeDurationFrames = setmetatable({}, { __mode = "k" })
    Runtime._activeDurationFrames = activeDurationFrames
end

local function MaskHas(mask, flag)
    return type(mask) == "number" and (mask % (flag * 2)) >= flag
end

local function MaskAdd(mask, flag)
    if MaskHas(mask, flag) then return mask end
    return mask + flag
end

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

local plainIsSecret = _G.issecretvalue or function(_) return false end
local plainHuge = math.huge

--- Dragonflight+ APIs may return value wrappers. Convert only to plain scalars
--- here so the rest of Runtime can compare and cache safely.
local function PlainNumber(value)
    if value == nil then
        return nil
    end

    -- The duration APIs normally return an ordinary number. Avoid ToPlain and
    -- the allocating tostring/tonumber round-trip on that overwhelmingly hot
    -- path while retaining the wrapper fallback below.
    if type(value) == "number" and plainIsSecret(value) ~= true
        and value == value and value ~= plainHuge and value ~= -plainHuge then
        return value
    end

    local toPlain = _G.ToPlain
    if type(toPlain) == "function" then
        local plain = toPlain(value)
        if plain ~= nil and plainIsSecret(plain) ~= true then
            local plainType = type(plain)
            if plainType == "number" then
                if plain == plain and plain ~= plainHuge and plain ~= -plainHuge then
                    return plain
                end
                return nil
            elseif plainType == "string" then
                return tonumber(plain)
            end

            -- Compatibility fallback for an unexpected ToPlain wrapper type.
            return tonumber(tostring(plain))
        end
    end

    local valueType = type(value)
    if valueType == "number" then
        if plainIsSecret(value) ~= true
            and value == value and value ~= plainHuge and value ~= -plainHuge then
            return value
        end
    elseif valueType == "string" and plainIsSecret(value) ~= true then
        return tonumber(value)
    end

    return nil
end

local nativeTextFormats
local nativeTextFormatsUnavailable

local function BuildNativeTextFormats()
    if nativeTextFormats then return nativeTextFormats end
    if nativeTextFormatsUnavailable then return nil end

    local durationUtil = _G.C_DurationUtil
    local stringUtil = _G.C_StringUtil
    local durationProperties = _G.Enum and _G.Enum.DurationTextBindingProperty
    local rounding = _G.Enum and _G.Enum.NumericRuleFormatRounding
    local createFormatter = stringUtil and stringUtil.CreateNumericRuleFormatter
    if type(durationUtil) ~= "table"
        or type(durationUtil.CreateDurationTextBinding) ~= "function"
        or type(createFormatter) ~= "function"
        or type(durationProperties) ~= "table"
        or type(rounding) ~= "table"
    then
        nativeTextFormatsUnavailable = true
        return nil
    end

    local ok, formatter = pcall(createFormatter)
    if not ok or not formatter or type(formatter.SetBreakpoints) ~= "function" then
        nativeTextFormatsUnavailable = true
        return nil
    end

    ok = pcall(formatter.SetBreakpoints, formatter, {
        {
            threshold = 0,
            step = 0.1,
            rounding = rounding.Nearest,
            format = "%.1f",
        },
    })
    if not ok then
        nativeTextFormatsUnavailable = true
        return nil
    end

    local remaining = { property = durationProperties.RemainingDuration, formatter = formatter }
    local elapsed = { property = durationProperties.ElapsedDuration, formatter = formatter }
    local total = { property = durationProperties.TotalDuration, formatter = formatter }

    nativeTextFormats = {
        CURRENT = { "{}", { remaining } },
        CURRENT_MAX = { "{} / {}", { remaining, total } },
        ELAPSED = { "{}", { elapsed } },
        MAX_CURRENT = { "{} / {}", { total, remaining } },
        ELAPSED_MAX = { "{} / {}", { elapsed, total } },
        MAX_ELAPSED = { "{} / {}", { total, elapsed } },
    }
    return nativeTextFormats
end

local function DisableNativeTimeText(frame)
    if not frame then return end

    local binding = frame._msufDurationTextBinding
    if binding then
        local disabled = type(binding.Disable) == "function"
            and pcall(binding.Disable, binding)
        if not disabled and type(binding.SetEnabled) == "function" then
            pcall(binding.SetEnabled, binding, false)
        end
    end
    -- DurationTextBinding mutates the FontString behind MSUF's Lua-side diff
    -- cache. Invalidate that cache so the next Lua clear/update cannot be skipped
    -- against a stale pre-binding value.
    if frame.timeText then frame.timeText._msufLastText = nil end
    frame._msufNativeTimeBound = nil
end

local function ApplyNativeTimeText(frame, durationObj, format)
    if not (frame and frame.timeText and durationObj) then return false end

    local formats = BuildNativeTextFormats()
    local formatSpec = formats and formats[format]
    if not formatSpec then return false end

    local binding = frame._msufDurationTextBinding
    if not binding then
        local createBinding = _G.C_DurationUtil and _G.C_DurationUtil.CreateDurationTextBinding
        if type(createBinding) ~= "function" then return false end

        local ok
        ok, binding = pcall(createBinding)
        if not ok or not binding then return false end
        frame._msufDurationTextBinding = binding
    end

    local configured = frame._msufDurationTextConfigured == true
    if not configured then
        local ok = type(binding.SetFontString) == "function"
            and pcall(binding.SetFontString, binding, frame.timeText)
        if not ok then
            DisableNativeTimeText(frame)
            return false
        end

        ok = type(binding.SetUpdateInterval) == "function"
            and pcall(binding.SetUpdateInterval, binding, 0.10)
        if not ok then
            DisableNativeTimeText(frame)
            return false
        end
        frame._msufDurationTextConfigured = true
    end

    if frame._msufDurationTextFormat ~= format then
        local ok = type(binding.SetTextFormat) == "function"
            and pcall(binding.SetTextFormat, binding, formatSpec[1], formatSpec[2])
        if not ok then
            DisableNativeTimeText(frame)
            return false
        end
        frame._msufDurationTextFormat = format
    end

    local ok = type(binding.SetDuration) == "function"
        and pcall(binding.SetDuration, binding, durationObj)
    if not ok then
        DisableNativeTimeText(frame)
        return false
    end

    ok = type(binding.SetEnabled) == "function"
        and pcall(binding.SetEnabled, binding, true)
    if not ok then
        DisableNativeTimeText(frame)
        return false
    end

    if type(binding.UpdateFontString) == "function" then
        pcall(binding.UpdateFontString, binding)
    end
    frame.timeText._msufLastText = nil
    frame._msufNativeTimeBound = true
    return true
end

local function CastTimeUnitKey(frame, unit)
    unit = tostring(unit or ""):lower()
    if frame and frame._msufIsBossCastbar then return "boss" end
    if unit:match("^boss%d+$") then return "boss" end
    return unit
end

--- Compile settings shared by the text and manager paths.  DB reads are cold:
--- one per castbar settings revision, not one per manager registration/tick.
function Runtime:RefreshWorkConfig(frame, force)
    if not frame then return true, "CURRENT", 0 end

    local revision = _G.MSUF__castTimeGlobalRev or 1
    if not force
        and frame._msufCastTimeRev == revision
        and frame._msufCastTimeEnabled ~= nil
        and frame._msufCastbarConfigMask ~= nil
    then
        return frame._msufCastTimeEnabled, frame._msufCastTimeFormat, frame._msufCastbarConfigMask
    end

    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local unit = frame.unit
    local enabled = true
    if general then
        if unit == "player" then
            enabled = general.showPlayerCastTime ~= false
        elseif unit == "target" then
            enabled = general.showTargetCastTime ~= false
        elseif unit == "focus" then
            enabled = general.showFocusCastTime ~= false
        elseif frame._msufIsBossCastbar or tostring(unit or ""):match("^boss%d+$") then
            enabled = general.showBossCastTime ~= false
        end
    end

    local format = "CURRENT"
    if general and type(_G.MSUF_GetCastbarTimeFormat) == "function" then
        format = _G.MSUF_GetCastbarTimeFormat(CastTimeUnitKey(frame, unit), general) or format
    end

    if frame._msufCastTimeFormat ~= format then
        frame._msufLastTimeDecimal = nil
        frame._msufLastTimeTotalDecimal = nil
        frame._msufLastTimeFormat = nil
    end

    local glowEnabled = general == nil or general.castbarShowGlow ~= false
    local configMask = glowEnabled and WORK_GLOW or 0

    frame._msufCastTimeEnabled = enabled and true or false
    frame._msufCastTimeFormat = format
    frame._msufCastTimeRev = revision
    frame._msufCastbarConfigMask = configMask
    return frame._msufCastTimeEnabled, format, configMask
end

function Runtime:PrepareWork(frame)
    if not frame then return WORK_DURATION_FALLBACK end

    local hadGlowTick = frame._msufCastbarGlowTick == true
    local castTimeEnabled, format, mask = self:RefreshWorkConfig(frame, false)
    local durationObj = frame.MSUF_durationObj
    local isChanneled = frame.MSUF_isChanneled == true
    local isEmpower = frame.isEmpower == true
    local timerDriven = frame.MSUF_timerDriven == true

    if isChanneled then mask = MaskAdd(mask, WORK_CHANNEL) end
    if isEmpower then mask = MaskAdd(mask, WORK_EMPOWER) end
    if not timerDriven or not durationObj then
        mask = MaskAdd(mask, WORK_DURATION_FALLBACK)
    end
    if frame.unit ~= "player" then
        mask = MaskAdd(mask, WORK_UNIT_FAILSAFE)
    end

    local canUseNativeText = not isChanneled
        and not isEmpower
        and timerDriven
        and durationObj ~= nil
        and frame._msufPlainEndTime ~= nil

    if frame.timeText and castTimeEnabled then
        if canUseNativeText and ApplyNativeTimeText(frame, durationObj, format) then
            -- The client owns the text cadence; no Lua text work bit.
        else
            DisableNativeTimeText(frame)
            mask = MaskAdd(mask, WORK_TIME_TEXT)
        end
    else
        DisableNativeTimeText(frame)
        if frame.timeText and frame.timeText.SetText then frame.timeText:SetText("") end
    end

    local timerAPI = _G.C_Timer
    if not isChanneled
        and not isEmpower
        and timerDriven
        and (frame._msufPlainEndTime == nil
            or frame._msufNativeCompletionUnsafe == true
            or type(timerAPI) ~= "table"
            or type(timerAPI.NewTimer) ~= "function")
    then
        mask = MaskAdd(mask, WORK_DURATION_FALLBACK)
    end

    frame._msufCastbarWorkMask = mask
    frame._msufCastbarGlowTick = MaskHas(mask, WORK_GLOW) or nil
    if hadGlowTick and frame._msufCastbarGlowTick ~= true then
        local resetGlow = _G.MSUF_ResetCastbarGlowFade
        if type(resetGlow) == "function" then resetGlow(frame) end
    end
    return mask
end

function Runtime:NeedsManager(frame)
    return not (frame and frame._msufCastbarWorkMask == 0)
end

function Runtime:CancelNativeCompletion(frame)
    if not frame then return end
    CancelTimerHandle(frame._msufNativeCompletionTimer)
    frame._msufNativeCompletionTimer = nil
end

local function NativeCompletionCallback(frame)
    frame._msufNativeCompletionTimer = nil
    local workMask = frame._msufCastbarWorkMask
    if frame.MSUF_castActive ~= true
        or (workMask ~= 0 and workMask ~= WORK_UNIT_FAILSAFE)
        or frame.MSUF_isChanneled == true
        or frame.isEmpower == true
        or (frame.IsShown and not frame:IsShown())
    then
        return
    end

    local durationObj = frame.MSUF_durationObj
    local getter = durationObj and (durationObj.GetRemainingDuration or durationObj.GetRemaining)
    local remaining
    if type(getter) == "function" then
        local ok, rawRemaining = pcall(getter, durationObj)
        if ok then remaining = PlainNumber(rawRemaining) end
    end

    if remaining and remaining > 0.001 then
        frame._msufPlainEndTime = Now() + remaining
        Runtime:ArmNativeCompletion(frame)
        return
    end

    if remaining == nil then
        -- A duration that became unreadable/secret stays on the proven manager
        -- path.  Do not guess whether it expired.
        frame._msufNativeCompletionUnsafe = true
        Runtime:PrepareWork(frame)
        if type(_G.MSUF_RegisterCastbar) == "function" then
            _G.MSUF_RegisterCastbar(frame)
        end
        return
    end

    if frame.SetSucceeded then
        frame:SetSucceeded()
    else
        Runtime:Stop(frame, REASON_SUCCEEDED)
    end
end

function Runtime:ArmNativeCompletion(frame)
    local workMask = frame and frame._msufCastbarWorkMask
    if not (frame
        and (workMask == 0 or workMask == WORK_UNIT_FAILSAFE)
        and frame._msufPlainEndTime) then
        return false
    end

    local timerAPI = _G.C_Timer
    if not (timerAPI and type(timerAPI.NewTimer) == "function") then return false end

    self:CancelNativeCompletion(frame)
    if not frame._msufNativeCompletionCallback then
        frame._msufNativeCompletionCallback = function()
            NativeCompletionCallback(frame)
        end
    end

    local delay = frame._msufPlainEndTime - Now() + 0.05
    if delay < 0.05 then delay = 0.05 end
    local ok, timer = pcall(timerAPI.NewTimer, delay, frame._msufNativeCompletionCallback)
    if not ok or not timer then
        frame._msufNativeCompletionUnsafe = true
        self:PrepareWork(frame)
        return false
    end

    frame._msufNativeCompletionTimer = timer
    return true
end

function Runtime:DeactivateNative(frame)
    if not frame then return end
    self:CancelNativeCompletion(frame)
    DisableNativeTimeText(frame)
end

--- End active-duration ownership without changing interrupt/hold visuals.
--- Terminal paths that intentionally keep the frame visible use this instead
--- of Stop(), so cold settings refreshes cannot resurrect the finished cast.
function Runtime:ReleaseActive(frame)
    if not frame then return end

    activeDurationFrames[frame] = nil
    self:DeactivateNative(frame)
    frame.MSUF_castActive = false
    frame.MSUF_durationObj = nil
    frame.MSUF_timerDriven = nil
    frame.MSUF_timerRangeSet = nil
    frame._msufPlainEndTime = nil
    frame._msufRemaining = nil
    frame._msufFastText = nil
    frame._msufPlainTotal = nil
    frame._msufCastbarWorkMask = nil
    frame._msufCastbarGlowTick = nil
    frame._msufNativeCompletionUnsafe = nil
end

function Runtime:RefreshActiveWork()
    local register = _G.MSUF_RegisterCastbar
    if type(register) ~= "function" then return end

    for frame in pairs(activeDurationFrames) do
        if frame.MSUF_castActive == true then
            self:PrepareWork(frame)
            register(frame)
        end
    end
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

    local ok
    if INTERPOLATION_IMMEDIATE ~= nil and timerDirection ~= nil then
        ok = pcall(statusBar.SetTimerDuration, statusBar, durationObj, INTERPOLATION_IMMEDIATE, timerDirection)
    else
        ok = pcall(statusBar.SetTimerDuration, statusBar, durationObj)
    end

    return ok == true
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
        local ok, value = pcall(durationObj.GetRemainingDuration, durationObj)
        if ok then remaining = value end
    elseif durationObj.GetRemaining then
        local ok, value = pcall(durationObj.GetRemaining, durationObj)
        if ok then remaining = value end
    end

    local total
    if durationObj.GetTotalDuration then
        local ok, value = pcall(durationObj.GetTotalDuration, durationObj)
        if ok then total = value end
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

    self:CancelNativeCompletion(frame)
    frame._msufNativeCompletionUnsafe = nil
    activeDurationFrames[frame] = true

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
        and frame._msufNativeTimeBound ~= true
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
    self:ReleaseActive(frame)

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
    activeDurationFrames[frame] = nil
    self:DeactivateNative(frame)

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
    frame._msufCastbarWorkMask = nil
    frame._msufCastbarGlowTick = nil
    frame._msufNativeCompletionUnsafe = nil

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
