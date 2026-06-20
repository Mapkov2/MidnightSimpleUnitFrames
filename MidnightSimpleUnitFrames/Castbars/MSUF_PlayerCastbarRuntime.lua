--- Castbars/MSUF_PlayerCastbarRuntime.lua
--- Player castbar runtime.
---
--- Player is special because it supports vehicle casts, latency display,
--- empower stages, interrupt feedback, channel haste markers, and optional
--- Blizzard backend ownership. Keep shared visual/runtime behavior in the
--- neighboring Castbar modules; this file owns player event interpretation.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local C_Timer = _G.C_Timer
local type = type
local tonumber = tonumber
local tostring = tostring
local select = select
local math_max = math.max
local math_abs = math.abs

local function EnsureDBLazy()
    local fn = _G.MSUF_EnsureDBLazy
    if type(fn) == "function" then
        fn()
    elseif not _G.MSUF_DB and type(_G.EnsureDB) == "function" then
        _G.EnsureDB()
    end
end

local function PlainNumber(value)
    local fn = _G.MSUF_CastbarRuntime_PlainNumber
    if type(fn) == "function" then
        return fn(value)
    end

    if value == nil then return nil end
    local toPlain = _G.ToPlain
    if type(toPlain) == "function" then
        local plain = toPlain(value)
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

local function CallEmpowerStart(frame, stage)
    local fn = _G.MSUF_PlayerCastbar_EmpowerStart
    if fn then fn(frame, stage) end
end

local function ClearEmpower(frame, hideFrame)
    local fn = _G.MSUF_PlayerCastbar_ClearEmpower
    if fn then fn(frame, hideFrame) end
end

local function UpdateChannelHasteMarkers(frame, force)
    local fn = _G.MSUF_PlayerChannelHasteMarkers_Update
    if fn then fn(frame, force) end
end

local function HideChannelHasteMarkers(frame)
    local fn = _G.MSUF_PlayerChannelHasteMarkers_Hide
    if fn then fn(frame) end
end

local function ApplyLatencyBar(frame, pct, isChanneled)
    if not frame or not frame.latencyBar or not frame.statusBar then return end

    local width = frame.statusBar:GetWidth() or 0
    width = width * (pct or 0)
    local reverseFill = _G.MSUF_GetReverseFillSafe(frame, isChanneled and true or false)
    reverseFill = reverseFill and true or false

    frame.latencyBar:ClearAllPoints()
    if reverseFill then
        frame.latencyBar:SetPoint("TOPLEFT", frame.statusBar, "TOPLEFT", 0, 0)
        frame.latencyBar:SetPoint("BOTTOMLEFT", frame.statusBar, "BOTTOMLEFT", 0, 0)
    else
        frame.latencyBar:SetPoint("TOPRIGHT", frame.statusBar, "TOPRIGHT", 0, 0)
        frame.latencyBar:SetPoint("BOTTOMRIGHT", frame.statusBar, "BOTTOMRIGHT", 0, 0)
    end

    frame.latencyBar:SetWidth(width)
    if width and width > 0 then
        frame.latencyBar:Show()
    else
        frame.latencyBar:Hide()
    end
end

local function FlushLatencyPending(frame, generation)
    if not frame then return end

    local pending = frame._msufLatencyPending
    if not pending then return end
    if generation and pending.generation ~= generation then return end

    ApplyLatencyBar(frame, pending.pct or 0, pending.isChanneled and true or false)
end

local latencyQueue = {}

local function FlushLatencyQueue()
    local queue = latencyQueue
    local count = #queue
    if count <= 0 then return end

    local index = 1
    while index <= count do
        local frame = queue[index]
        local generation = queue[index + 1]
        FlushLatencyPending(frame, generation)
        queue[index] = nil
        queue[index + 1] = nil
        index = index + 2
    end
end

local function UpdateLatencyZone(frame, isChanneled, durationSeconds)
    if not frame or not frame.latencyBar or not frame.statusBar then return end

    durationSeconds = PlainNumber(durationSeconds)
    EnsureDBLazy()

    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    if general.castbarShowLatency == false then
        frame.latencyBar:Hide()
        return
    end
    if (frame.MSUF_testMode or frame._msufIsPreview) and not _G.MSUF_UnitEditModeActive then
        frame.latencyBar:Hide()
        return
    end
    if not durationSeconds or type(durationSeconds) ~= "number" or durationSeconds <= 0 then
        frame.latencyBar:Hide()
        return
    end

    local _, _, homeMS, worldMS = _G.GetNetStats()
    local networkMS = math_max(homeMS or 0, worldMS or 0)
    local queueWindowMS = tonumber(_G.GetCVar("SpellQueueWindow") or "0") or 0
    local latencyMS = math_max(networkMS, queueWindowMS)
    local durationMS = durationSeconds * 1000
    local pct = durationMS > 0 and (latencyMS / durationMS) or 0
    if pct > 1 then pct = 1 end
    if pct < 0 then pct = 0 end

    frame.MSUF_latencyLastPct = pct
    frame.MSUF_latencyLastIsChanneled = isChanneled and true or false
    frame.MSUF_latencyLastDurSec = durationSeconds

    local statusWidth = frame.statusBar:GetWidth() or 0
    local pending = frame._msufLatencyPending
    if not pending then
        pending = {}
        frame._msufLatencyPending = pending
    end
    pending.pct = pct
    pending.isChanneled = isChanneled and true or false
    pending.generation = (pending.generation or 0) + 1

    local generation = pending.generation
    if not statusWidth or statusWidth <= 1 then
        latencyQueue[#latencyQueue + 1] = frame
        latencyQueue[#latencyQueue + 1] = generation
        C_Timer.After(0, FlushLatencyQueue)
        return
    end

    FlushLatencyPending(frame, generation)
end

local function UpdateColorForInterruptible(frame)
    if not frame or not frame.statusBar then return end

    EnsureDBLazy()
    local general = _G.MSUF_DB and _G.MSUF_DB.general or {}

    if general.playerCastbarOverrideEnabled then
        if not (frame.interruptFeedbackEndTime and _G.GetTime() < frame.interruptFeedbackEndTime) then
            local mode = general.playerCastbarOverrideMode
            local red, green, blue

            if mode == "CUSTOM" then
                red = tonumber(general.playerCastbarOverrideR)
                green = tonumber(general.playerCastbarOverrideG)
                blue = tonumber(general.playerCastbarOverrideB)
            else
                local _, classToken = _G.UnitClass("player")
                if classToken then
                    if type(_G.MSUF_GetClassBarColor) == "function" then
                        red, green, blue = _G.MSUF_GetClassBarColor(classToken)
                    end
                    if not red and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken] then
                        local color = _G.RAID_CLASS_COLORS[classToken]
                        red, green, blue = color.r, color.g, color.b
                    end
                end
            end

            if red and green and blue then
                if type(_G.MSUF_SetStatusBarColorIfChanged) == "function" then
                    _G.MSUF_SetStatusBarColorIfChanged(frame.statusBar, red, green, blue, 1)
                else
                    frame.statusBar:SetStatusBarColor(red, green, blue, 1)
                end
                return
            end
        end
    end

    local forceNotInterruptible = false
    local unit = frame.unit or "player"
    local nameplateAPI = _G.C_NamePlate
    local nameplate = nameplateAPI
        and nameplateAPI.GetNamePlateForUnit
        and nameplateAPI.GetNamePlateForUnit(unit, _G.issecure())
    if nameplate then
        local nativeCastbar = (nameplate.UnitFrame and nameplate.UnitFrame.castBar) or nameplate.castBar or nameplate.CastBar
        local barType = nativeCastbar and nativeCastbar.barType
        if barType == "uninterruptable"
            or barType == "uninterruptible"
            or barType == "uninterruptibleSpell"
            or barType == "shield" then
            forceNotInterruptible = true
        end
    end
    if frame.isNotInterruptible then
        forceNotInterruptible = true
    end

    local red, green, blue, alpha
    if forceNotInterruptible then
        if _G.MSUF_GetNonInterruptibleCastColor then
            red, green, blue = _G.MSUF_GetNonInterruptibleCastColor()
            alpha = 1
        end
        if not red or not green or not blue then
            local key = general.castbarNonInterruptibleColor or "red"
            local color = _G.MSUF_GetColorFromKey and _G.MSUF_GetColorFromKey(key)
            if color then red, green, blue, alpha = color:GetRGBA() end
        end
        if not red or not green or not blue then
            red, green, blue, alpha = 0.4, 0.01, 0.01, 1
        end
    else
        if _G.MSUF_GetInterruptibleCastColor then
            red, green, blue = _G.MSUF_GetInterruptibleCastColor()
            alpha = 1
        end
        if not red or not green or not blue then
            local key = general.castbarInterruptibleColor or "turquoise"
            local color = _G.MSUF_GetColorFromKey and _G.MSUF_GetColorFromKey(key)
            if color then red, green, blue, alpha = color:GetRGBA() end
        end
        if not red or not green or not blue then
            red, green, blue, alpha = 0, 1, 0.9, 1
        end
    end

    if type(_G.MSUF_SetStatusBarColorIfChanged) == "function" then
        _G.MSUF_SetStatusBarColorIfChanged(frame.statusBar, red, green, blue, alpha or 1)
    else
        frame.statusBar:SetStatusBarColor(red, green, blue, alpha or 1)
    end
end

local function GetInterruptFeedbackColor()
    EnsureDBLazy()
    local general = _G.MSUF_DB and _G.MSUF_DB.general or {}
    local red = tonumber(general.castbarInterruptR)
    local green = tonumber(general.castbarInterruptG)
    local blue = tonumber(general.castbarInterruptB)
    if red and green and blue then
        return red, green, blue, 1
    end

    local key = general.castbarInterruptColor or "red"
    if _G.MSUF_GetColorFromKey then
        local color = _G.MSUF_GetColorFromKey(key)
        if color then return color:GetRGBA() end
    end

    return 0.8, 0.1, 0.1, 1
end

local INTERRUPT_FEEDBACK_DURATION = _G.MSUF_INTERRUPT_FEEDBACK_DURATION or 0.5

local function GetEffectiveUnit(frame)
    local unit = (frame and frame.unit) or "player"
    if unit == "player"
        and type(_G.UnitHasVehicleUI) == "function"
        and _G.UnitHasVehicleUI("player")
        and type(_G.UnitExists) == "function"
        and _G.UnitExists("vehicle") then
        if (type(_G.UnitCastingInfo) == "function" and _G.UnitCastingInfo("vehicle"))
            or (type(_G.UnitChannelInfo) == "function" and _G.UnitChannelInfo("vehicle")) then
            return "vehicle"
        end
    end
    return unit
end

local function ClearActiveCastIdentity(frame)
    if not frame then return end
    frame._msufActiveCastGUID = nil
    frame._msufActiveSpellID = nil
    frame._msufActiveCastBarID = nil
end

local function StoreActiveCastIdentity(frame, castGUID, spellID, castBarID)
    if not frame then return end
    frame._msufActiveCastGUID = castGUID
    frame._msufActiveSpellID = spellID
    frame._msufActiveCastBarID = castBarID
end

local function ActiveUnitMatches(frame, unit)
    if not frame then return false end
    if not unit then return true end
    if not frame._msufActiveCastUnit then return true end
    return unit == frame._msufActiveCastUnit
end

local function ActiveCastBarIDMatches(frame, castBarID)
    if not frame then return false end
    if not castBarID then return true end
    if not frame._msufActiveCastBarID then return true end
    return castBarID == frame._msufActiveCastBarID
end

local function IsDifferentActiveCast(frame, castGUID, spellID, castBarID)
    if not frame then return false end
    if castBarID and frame._msufActiveCastBarID and castBarID ~= frame._msufActiveCastBarID then return true end
    if castGUID and frame._msufActiveCastGUID and castGUID ~= frame._msufActiveCastGUID then return true end
    if spellID and frame._msufActiveSpellID and spellID ~= frame._msufActiveSpellID then return true end
    return false
end

local function ResetTimingFields(frame)
    if not frame then return end
    frame.endTime = nil
    frame._msufPlainEndTime = nil
    frame._msufPlainTotal = nil
    frame._msufRemaining = nil
    frame._msufLastTimeDecimal = nil
    frame._msufZeroCount = nil
    frame._msufLastDurationObj = nil
    frame._msufTimerAssumeCountdown = nil
end

local function CaptureCastTimes(frame, startMS, endMS)
    if not frame then return end

    ResetTimingFields(frame)
    startMS = PlainNumber(startMS)
    endMS = PlainNumber(endMS)

    local now = _G.GetTime()
    if type(endMS) == "number" then
        local endSeconds = endMS / 1000
        local remaining = endSeconds - now
        frame.endTime = endSeconds
        if type(remaining) == "number" and remaining > 0 then
            frame._msufPlainEndTime = endSeconds
            frame._msufRemaining = remaining
        end
    end

    if type(startMS) == "number" and type(endMS) == "number" then
        local total = (endMS - startMS) / 1000
        if type(total) == "number" and total > 0 then
            frame._msufPlainTotal = total
        end
    end
end

local function SetStatusBarRemaining(frame, totalSeconds, remainingSeconds, reverseFill)
    if not (frame and frame.statusBar and frame.statusBar.SetMinMaxValues and frame.statusBar.SetValue) then return end

    totalSeconds = PlainNumber(totalSeconds) or 0
    remainingSeconds = PlainNumber(remainingSeconds) or totalSeconds
    if totalSeconds < 0 then totalSeconds = 0 end
    if remainingSeconds < 0 then remainingSeconds = 0 end
    if remainingSeconds > totalSeconds then remainingSeconds = totalSeconds end
    if totalSeconds <= 0 then totalSeconds = 0.001 end

    frame.statusBar:SetMinMaxValues(0, totalSeconds)
    if reverseFill then
        frame.statusBar:SetValue(remainingSeconds)
    else
        frame.statusBar:SetValue(totalSeconds - remainingSeconds)
    end
end

local function PlainBoolean(value)
    local isSecret = _G.issecretvalue
    if type(isSecret) == "function" and isSecret(value) == true then
        local toPlain = _G.ToPlain
        if type(toPlain) ~= "function" then return false end
        value = toPlain(value)
        if type(isSecret) == "function" and isSecret(value) == true then return false end
    end
    if value == nil then return false end
    return value == true
end

local function ApplyActiveCast(
    frame,
    unit,
    castType,
    spellName,
    text,
    icon,
    startMS,
    endMS,
    apiNotInterruptibleRaw,
    spellID,
    castGUID,
    castBarID,
    durationObj
)
    local isChannel = castType == "CHANNEL"

    frame.interruptFeedbackEndTime = nil
    frame.interrupted = nil
    frame.MSUF_castActive = true
    frame._msufActiveCastUnit = unit
    frame._msufChanNilSince = nil
    frame._msufCastNilSince = nil
    frame._msufHardStopNilSince = nil
    StoreActiveCastIdentity(frame, isChannel and nil or castGUID, spellID, castBarID)
    frame.MSUF_castDuration = isChannel and nil or durationObj
    frame.MSUF_channelDuration = isChannel and durationObj or nil
    frame.MSUF_channelTotal = nil

    local reverseFill = _G.MSUF_GetReverseFillSafe(frame, isChannel)
    local timerDriven = false

    if durationObj then
        local state = frame._msufPlayerState or {}
        frame._msufPlayerState = state
        state.active = true
        state.unit = unit
        state.castType = castType
        state.spellName = spellName
        state.text = text or spellName
        state.icon = icon
        state.spellId = spellID
        state.startTimeMS = startMS
        state.endTimeMS = endMS
        state.durationObj = durationObj
        state.reverseFill = reverseFill
        timerDriven = _G.MSUF_Castbar_ApplyActiveDuration(frame, state, {
            skipColor = true,
            skipRegister = true,
            skipTimeText = true,
            skipShow = true,
        }) and true or false
    else
        frame.MSUF_durationObj = nil
        frame.MSUF_isChanneled = isChannel
        frame.MSUF_timerDriven = nil
        if frame.icon then frame.icon:SetTexture(icon or nil) end
        if frame.castText then
            if type(_G.MSUF_CB_ApplyTexts) == "function" then
                _G.MSUF_CB_ApplyTexts(frame, nil, spellName or "", nil)
            else
                _G.MSUF_SetTextIfChanged(frame.castText, spellName or "")
            end
        end
    end

    frame._msufStripeReverseFill = reverseFill and true or false
    if isChannel then
        frame.MSUF_channelDirect = nil
    else
        HideChannelHasteMarkers(frame)
    end

    local notInterruptible = frame.isNotInterruptible == true
    if PlainBoolean(apiNotInterruptibleRaw) then
        notInterruptible = true
    end
    frame.isNotInterruptible = notInterruptible

    CaptureCastTimes(frame, startMS, endMS)
    if not timerDriven and frame._msufPlainTotal and frame._msufRemaining then
        SetStatusBarRemaining(frame, frame._msufPlainTotal, frame._msufRemaining, reverseFill)
    end

    UpdateColorForInterruptible(frame)

    local totalDuration
    if durationObj and durationObj.GetTotalDuration then
        totalDuration = PlainNumber(durationObj:GetTotalDuration())
    end
    if not isChannel and totalDuration == nil and durationObj and durationObj.GetRemainingDuration then
        totalDuration = PlainNumber(durationObj:GetRemainingDuration())
    end
    if totalDuration == nil then
        totalDuration = frame._msufPlainTotal
    end
    if isChannel then
        frame.MSUF_channelTotal = totalDuration
    end

    UpdateLatencyZone(frame, isChannel, totalDuration)
    frame:SetScript("OnUpdate", nil)
    frame:SetOnUpdateMode("Disabled")
    frame.MSUF_durationObj = durationObj
    frame.MSUF_timerDriven = timerDriven and true or nil

    _G.MSUF_EnsureCastbarManager()
    if _G.MSUF_RegisterCastbar then _G.MSUF_RegisterCastbar(frame) end
    if _G.MSUF_UpdateCastbarFrame then
        local now = (_G.GetTimePreciseSec and _G.GetTimePreciseSec()) or _G.GetTime()
        _G.MSUF_UpdateCastbarFrame(frame, 0, now)
    end

    frame:Show()
    if isChannel then
        UpdateChannelHasteMarkers(frame, true)
    end
end

local CAST_START_EVENTS = {
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_INTERRUPTIBLE = true,
    UNIT_SPELLCAST_NOT_INTERRUPTIBLE = true,
    UNIT_SPELLCAST_SENT = true,
}

local CAST_STOP_EVENTS = {
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
}

local CHANNEL_START_EVENTS = {
    UNIT_SPELLCAST_CHANNEL_START = true,
}

local function StopPlayerCastbar(frame)
    frame._msufChanNilSince = nil
    frame._msufCastNilSince = nil
    frame._msufHardStopNilSince = nil
    frame.MSUF_channelDuration = nil
    frame.MSUF_castDuration = nil
    frame.MSUF_channelTotal = nil
    ResetTimingFields(frame)
    ClearActiveCastIdentity(frame)
    frame._msufActiveCastUnit = nil
    HideChannelHasteMarkers(frame)

    if _G.MSUF_CB_ResetStateOnStop then
        _G.MSUF_CB_ResetStateOnStop(frame, "STOPPED")
    else
        frame:SetScript("OnUpdate", nil)
        frame:SetOnUpdateMode("Disabled")
        if _G.MSUF_UnregisterCastbar then _G.MSUF_UnregisterCastbar(frame) end
        if frame.latencyBar then frame.latencyBar:Hide() end
        if frame.timeText then _G.MSUF_SetTextIfChanged(frame.timeText, "") end
        frame:Hide()
    end
    if frame.statusBar and frame.statusBar.SetValue then
        frame.statusBar:SetValue(0)
    end
end

local function UnhaltedUpdate(frame, event)
    if not frame or not frame.unit or not frame.statusBar then return end
    if frame.isEmpower then return end

    local unit = GetEffectiveUnit(frame)
    if event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        frame.isNotInterruptible = false
    elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        frame.isNotInterruptible = true
    elseif event == "UNIT_SPELLCAST_START"
        or event == "UNIT_SPELLCAST_SENT"
        or event == "UNIT_SPELLCAST_CHANNEL_START" then
        frame.isNotInterruptible = false
    end

    if CAST_START_EVENTS[event] then
        local spellName, text, icon, startMS, endMS, _, castGUID, apiNotInterruptibleRaw, spellID, castBarID =
            _G.UnitCastingInfo(unit)
        if not spellName then
            if _G.UnitChannelInfo(unit) then
                return UnhaltedUpdate(frame, "UNIT_SPELLCAST_CHANNEL_START")
            end
            return UnhaltedUpdate(frame, "UNIT_SPELLCAST_STOP")
        end

        local durationObj
        if type(_G.UnitCastingDuration) == "function" then
            durationObj = _G.UnitCastingDuration(unit)
        end
        ApplyActiveCast(
            frame,
            unit,
            "CAST",
            spellName,
            text,
            icon,
            startMS,
            endMS,
            apiNotInterruptibleRaw,
            spellID,
            castGUID,
            castBarID,
            durationObj
        )
        return
    end

    if CHANNEL_START_EVENTS[event] then
        local spellName, text, icon, startMS, endMS, _, apiNotInterruptibleRaw, spellID, _, _, castBarID =
            _G.UnitChannelInfo(unit)
        if not spellName then
            if _G.UnitCastingInfo(unit) then
                return UnhaltedUpdate(frame, "UNIT_SPELLCAST_START")
            end
            return UnhaltedUpdate(frame, "UNIT_SPELLCAST_STOP")
        end

        local durationObj
        if type(_G.UnitChannelDuration) == "function" then
            durationObj = _G.UnitChannelDuration(unit)
        end
        ApplyActiveCast(
            frame,
            unit,
            "CHANNEL",
            spellName,
            text,
            icon,
            startMS,
            endMS,
            apiNotInterruptibleRaw,
            spellID,
            nil,
            castBarID,
            durationObj
        )
        return
    end

    if CAST_STOP_EVENTS[event] then
        StopPlayerCastbar(frame)
    end
end

local function CastPlayerCastbar(frame)
    if not frame or not frame.unit or not frame.statusBar then return end
    if frame.isEmpower then return end
    if frame.MSUF_testMode then return end

    local unit = GetEffectiveUnit(frame)
    if _G.UnitCastingInfo(unit) then
        UnhaltedUpdate(frame, "UNIT_SPELLCAST_START")
    elseif _G.UnitChannelInfo(unit) then
        UnhaltedUpdate(frame, "UNIT_SPELLCAST_CHANNEL_START")
    else
        UnhaltedUpdate(frame, "UNIT_SPELLCAST_STOP")
    end
end

local function ScheduleSoftResync(frame)
    if not frame then return end

    local token = (frame._msufSoftResyncToken or 0) + 1
    frame._msufSoftResyncToken = token
    C_Timer.After(0, function()
        if not frame or frame._msufSoftResyncToken ~= token then return end
        if frame.isEmpower or frame.MSUF_testMode then return end
        CastPlayerCastbar(frame)
    end)
end

local function HideIfNoLongerCasting(owner)
    local frame = owner and owner.msuCastbarFrame
    if not frame or not frame.unit then return end
    if frame.MSUF_testMode then return end

    local unit = frame.unit or "player"
    if unit == "player"
        and type(_G.UnitHasVehicleUI) == "function"
        and _G.UnitHasVehicleUI("player")
        and type(_G.UnitExists) == "function"
        and _G.UnitExists("vehicle") then
        if (type(_G.UnitCastingInfo) == "function" and _G.UnitCastingInfo("vehicle"))
            or (type(_G.UnitChannelInfo) == "function" and _G.UnitChannelInfo("vehicle")) then
            unit = "vehicle"
        end
    end

    local cast = _G.UnitCastingInfo(unit)
    local channel = _G.UnitChannelInfo(unit)
    if cast or channel then
        if _G.MSUF_PlayerCastbar_Cast then
            _G.MSUF_PlayerCastbar_Cast(frame)
        end
        return
    end

    frame:SetScript("OnUpdate", nil)
    frame:SetOnUpdateMode("Disabled")
    if frame.timeText then _G.MSUF_SetTextIfChanged(frame.timeText, "") end
    if _G.MSUF_UnregisterCastbar then _G.MSUF_UnregisterCastbar(frame) end
    frame._msufActiveCastGUID = nil
    frame._msufActiveSpellID = nil
    frame._msufActiveCastBarID = nil
    frame._msufActiveCastUnit = nil
    frame:Hide()
end

local function ShowInterruptFeedback(frame, label)
    if not frame or not frame.statusBar then return end

    EnsureDBLazy()
    local playerDB = (_G.MSUF_DB and _G.MSUF_DB.player) or {}
    if playerDB.showInterrupt == false then
        frame:SetScript("OnUpdate", nil)
        frame:SetOnUpdateMode("Disabled")
        frame.interruptFeedbackEndTime = nil
        if frame.timeText then _G.MSUF_SetTextIfChanged(frame.timeText, "") end
        if frame.statusBar and frame.statusBar.SetValue then frame.statusBar:SetValue(0) end
        frame:Hide()
        return
    end

    if frame.hideTimer then
        frame._msufHideToken = (frame._msufHideToken or 0) + 1
        frame.hideTimer = nil
    end

    frame:SetScript("OnUpdate", nil)
    frame:SetOnUpdateMode("Disabled")
    if _G.MSUF_UnregisterCastbar then _G.MSUF_UnregisterCastbar(frame) end
    frame.MSUF_durationObj = nil
    frame.MSUF_channelDirect = nil
    frame.MSUF_timerDriven = nil
    frame.MSUF_timerRangeSet = nil
    if _G.MSUF_ClearCastbarTimerDuration and frame.statusBar then
        _G.MSUF_ClearCastbarTimerDuration(frame.statusBar)
    end
    frame._msufActiveCastUnit = nil
    frame._msufActiveCastGUID = nil
    frame._msufActiveSpellID = nil
    frame._msufActiveCastBarID = nil
    frame._msufChanNilSince = nil
    frame.interruptFeedbackEndTime = _G.GetTime() + INTERRUPT_FEEDBACK_DURATION

    local reverseFill = _G.MSUF_GetReverseFillSafe and _G.MSUF_GetReverseFillSafe(frame, false) or false
    _G.MSUF_ApplyInterruptBarVisuals(frame, {
        barValue = 1,
        colorR = 0.8,
        colorG = 0.1,
        colorB = 0.1,
        reverseFill = reverseFill,
        label = label or _G.INTERRUPTED,
    })

    local duration = INTERRUPT_FEEDBACK_DURATION
    if type(duration) ~= "number" then duration = 0.5 end
    if duration < 0 then duration = 0 end

    frame._msufHideToken = (frame._msufHideToken or 0) + 1
    local token = frame._msufHideToken
    C_Timer.After(duration, function()
        if frame and frame._msufHideToken == token then
            HideIfNoLongerCasting({ msuCastbarFrame = frame })
        end
    end)
end

local function DisablePlayerCastbar(frame)
    frame:SetScript("OnUpdate", nil)
    frame:SetOnUpdateMode("Disabled")
    if _G.MSUF_UnregisterCastbar then _G.MSUF_UnregisterCastbar(frame) end
    frame.interruptFeedbackEndTime = nil
    ClearActiveCastIdentity(frame)
    frame._msufActiveCastUnit = nil
    if frame.timeText then _G.MSUF_SetTextIfChanged(frame.timeText, "") end
    if frame.latencyBar then frame.latencyBar:Hide() end
    frame:Hide()
end

local function HandleEmpowerEvent(frame, event, ...)
    if event == "UNIT_SPELLCAST_EMPOWER_START" or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        CallEmpowerStart(frame, select(3, ...))
        return true
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        ClearEmpower(frame, true)
        return true
    end
    return false
end

local function HandleActiveEmpowerEvent(frame, event)
    if not frame.isEmpower then return false end

    if event == "UNIT_SPELLCAST_INTERRUPTED" then
        if type(_G.MSUF_PlayerCastbar_ShowInterruptFeedback) == "function" then
            _G.MSUF_PlayerCastbar_ShowInterruptFeedback(frame, "Interrupted")
        else
            ClearEmpower(frame, true)
        end
        return true
    elseif event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_SUCCEEDED" then
        ClearEmpower(frame, true)
        return true
    end

    return false
end

local function PlayerCastbarOnEvent(frame, event, ...)
    if not _G.MSUF_IsCastbarEnabledForUnit("player") then
        DisablePlayerCastbar(frame)
        return
    end
    if frame.MSUF_testMode then return end

    local eventUnit = select(1, ...)

    if HandleEmpowerEvent(frame, event, ...) then return end
    if HandleActiveEmpowerEvent(frame, event, ...) then return end

    if event == "UNIT_SPELLCAST_INTERRUPTED" then
        if not ActiveUnitMatches(frame, eventUnit) then return end

        local castGUID = select(2, ...)
        local spellID = select(3, ...)
        local castBarID = select(5, ...)
        if IsDifferentActiveCast(frame, castGUID, spellID, castBarID) then return end

        ClearActiveCastIdentity(frame)
        ShowInterruptFeedback(frame, _G.INTERRUPTED)
        return
    end

    if not frame.isEmpower then
        if event == "UNIT_SPELLCAST_START"
            or event == "UNIT_SPELLCAST_SENT"
            or event == "UNIT_SPELLCAST_CHANNEL_START"
            or event == "UNIT_SPELLCAST_INTERRUPTIBLE"
            or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            UnhaltedUpdate(frame, event)
            return
        elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" or event == "UNIT_SPELLCAST_DELAYED" then
            if not ActiveUnitMatches(frame, eventUnit) then return end
            local castBarID = select(4, ...)
            if not ActiveCastBarIDMatches(frame, castBarID) then return end
            CastPlayerCastbar(frame)
            return
        elseif event == "UNIT_SPELLCAST_STOP" then
            if not ActiveUnitMatches(frame, eventUnit) then return end
            local castBarID = select(4, ...)
            if not ActiveCastBarIDMatches(frame, castBarID) then return end
            UnhaltedUpdate(frame, event)
            return
        elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            if not ActiveUnitMatches(frame, eventUnit) then return end
            local castBarID = select(5, ...)
            if not ActiveCastBarIDMatches(frame, castBarID) then return end
            ScheduleSoftResync(frame)
            return
        elseif event == "UNIT_SPELLCAST_FAILED" then
            if not ActiveUnitMatches(frame, eventUnit) then return end

            local castGUID = select(2, ...)
            local spellID = select(3, ...)
            local castBarID = select(4, ...)
            if IsDifferentActiveCast(frame, castGUID, spellID, castBarID) then return end

            ScheduleSoftResync(frame)
            return
        end
    end

    if event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        frame.isNotInterruptible = false
        UpdateColorForInterruptible(frame)
    elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        frame.isNotInterruptible = true
        UpdateColorForInterruptible(frame)
    end
end

ExportPublic("MSUF_PlayerCastbar_UpdateLatencyZone", UpdateLatencyZone)
ExportPublic("MSUF_PlayerCastbar_UpdateColorForInterruptible", UpdateColorForInterruptible)
ExportPublic("MSUF_GetInterruptFeedbackColor", GetInterruptFeedbackColor)
ExportPublic("MSUF_PlayerCastbar_HideIfNoLongerCasting", HideIfNoLongerCasting)
ExportPublic("MSUF_PlayerCastbar_ShowInterruptFeedback", ShowInterruptFeedback)
ExportPublic("MSUF_PlayerCastbar_GetEffectiveUnit", GetEffectiveUnit)
ExportPublic("MSUF_PlayerCastbar_UnhaltedUpdate", UnhaltedUpdate)
ExportPublic("MSUF_PlayerCastbar_Cast", CastPlayerCastbar)
ExportPublic("MSUF_PlayerCastbar_OnEvent", PlayerCastbarOnEvent)
