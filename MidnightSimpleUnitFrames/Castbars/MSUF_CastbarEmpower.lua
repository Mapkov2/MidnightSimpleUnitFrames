--- Castbars/MSUF_CastbarEmpower.lua
--- Empower castbar support.
---
--- Computes empower stage timing and draws stage tick/blink visuals for
--- castbars. This stays isolated from the main castbar runtime because empower
--- APIs vary by client/build.

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

local function DurationToSeconds(value)
    value = PlainNumber(value)
    if not value then return nil end
    if value > 20 then
        value = value / 1000
    end
    return value
end

local function GetEmpowerStageDuration(unit, stageIndex)
    if type(_G.GetUnitEmpowerStageDuration) ~= "function" then return nil end

    local duration = _G.GetUnitEmpowerStageDuration(unit, stageIndex)
    duration = DurationToSeconds(duration)
    if not duration or duration <= 0 then
        return nil
    end
    return duration
end

local function BuildEmpowerTimeline(unit, castState)
    local stageEnds = {}
    local totalStage = 0
    local stageCount

    if type(_G.GetUnitEmpowerStageCount) == "function" then
        local count = PlainNumber(_G.GetUnitEmpowerStageCount(unit))
        if count and count > 0 then
            stageCount = count
        end
    end

    local zeroBased = GetEmpowerStageDuration(unit, 0) ~= nil
    local firstStageIndex = zeroBased and 0 or 1

    if stageCount then
        for displayIndex = 1, stageCount do
            local apiIndex = zeroBased and (displayIndex - 1) or displayIndex
            local duration = GetEmpowerStageDuration(unit, apiIndex)
            if not duration then break end
            totalStage = totalStage + duration
            stageEnds[#stageEnds + 1] = totalStage
        end
    else
        for apiIndex = firstStageIndex, firstStageIndex + 9 do
            local duration = GetEmpowerStageDuration(unit, apiIndex)
            if not duration then break end
            totalStage = totalStage + duration
            stageEnds[#stageEnds + 1] = totalStage
        end
    end

    local holdAtMax = 0
    if type(_G.GetUnitEmpowerHoldAtMaxTime) == "function" then
        holdAtMax = DurationToSeconds(_G.GetUnitEmpowerHoldAtMaxTime(unit)) or 0
        if holdAtMax < 0 then holdAtMax = 0 end
    end

    local castStartSec, castEndSec, castTotal
    if castState or type(_G.UnitCastingInfo) == "function" then
        local startMS, endMS
        if castState then
            startMS, endMS = castState.startTimeMS, castState.endTimeMS
        else
            local _, _, _, apiStartMS, apiEndMS = _G.UnitCastingInfo(unit)
            startMS, endMS = apiStartMS, apiEndMS
        end
        startMS = PlainNumber(startMS)
        endMS = PlainNumber(endMS)
        if startMS and endMS and endMS > startMS then
            castStartSec = startMS / 1000
            castEndSec = endMS / 1000
            castTotal = (endMS - startMS) / 1000
        end
    end

    local totalWithGrace = totalStage + holdAtMax
    if castTotal and castTotal > 0 then
        if totalWithGrace <= 0 then
            totalWithGrace = castTotal
        elseif castTotal > totalWithGrace then
            totalWithGrace = castTotal
        end

        if totalStage > 0 then
            local inferredHold = castTotal - totalStage
            if inferredHold < 0 then inferredHold = 0 end
            if holdAtMax <= 0 or math_abs(holdAtMax - inferredHold) > 0.15 then
                holdAtMax = inferredHold
            end
        end
    end

    if not totalWithGrace or totalWithGrace <= 0 then
        totalWithGrace = 3.0
    end
    if totalWithGrace <= 0 then
        totalWithGrace = 0.01
    end

    return {
        stageEnds = stageEnds,
        totalStage = totalStage,
        maxHold = holdAtMax,
        totalBase = totalWithGrace,
        totalWithGrace = totalWithGrace,
        grace = 0,
        castStartSec = castStartSec,
        castEndSec = castEndSec,
        castTotal = castTotal,
        zeroBased = zeroBased,
        stageCount = stageCount,
    }
end

local TICK_BASE_ALPHA = 0.85
local TICK_BASE_WIDTH = 2
local TICK_GLOW_WIDTH = 12
local TICK_BLINK_WIDTH = 4
local DEFAULT_BLINK_TIME = 0.14

local STAGE_SEGMENT_COLORS = {
    { 0.20, 0.90, 0.20, 0.18 },
    { 0.95, 0.80, 0.20, 0.18 },
    { 1.00, 0.55, 0.20, 0.18 },
    { 1.00, 0.25, 0.25, 0.18 },
}

local cachedUnifiedDirection
local cachedColorStages

local function GetEmpowerStageBlinkTime()
    EnsureDBLazy()
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local seconds = general and general.empowerStageBlinkTime
    if type(seconds) ~= "number" then
        seconds = DEFAULT_BLINK_TIME
    end
    if seconds < 0.05 then seconds = 0.05 end
    if seconds > 1.00 then seconds = 1.00 end
    return seconds
end

local function IsEmpowerStageBlinkEnabled()
    EnsureDBLazy()
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    return (not general) or (general.empowerStageBlink ~= false)
end

local function EnsureEmpowerTicks(frame, count)
    if not frame or not frame.statusBar then return end

    frame.empowerTicks = frame.empowerTicks or {}
    local barHeight = frame.statusBar:GetHeight() or 18

    for index = 1, count do
        local tick = frame.empowerTicks[index]
        if not tick then
            tick = frame.statusBar:CreateTexture(nil, "OVERLAY")
            tick:SetTexture("Interface/Buttons/WHITE8x8")
            tick:SetVertexColor(1, 1, 1, TICK_BASE_ALPHA)
            tick:SetWidth(TICK_BASE_WIDTH)
            tick.MSUF_baseAlpha = TICK_BASE_ALPHA
            tick.MSUF_baseWidth = TICK_BASE_WIDTH
            frame.empowerTicks[index] = tick
        end

        tick:SetHeight(barHeight)
        tick:Show()

        if not tick.MSUF_flash then
            local flash = frame.statusBar:CreateTexture(nil, "OVERLAY")
            flash:SetTexture("Interface/Buttons/WHITE8x8")
            flash:SetBlendMode("ADD")
            flash:SetVertexColor(1.0, 0.10, 0.10, 0.0)
            flash:Hide()
            tick.MSUF_flash = flash

            local group = flash:CreateAnimationGroup()
            local alpha = group:CreateAnimation("Alpha")
            alpha:SetFromAlpha(1.0)
            alpha:SetToAlpha(0.0)
            alpha:SetDuration(GetEmpowerStageBlinkTime())
            tick.MSUF_flashAnim = alpha
            group:SetScript("OnFinished", function()
                if flash then
                    flash:Hide()
                    flash:SetAlpha(0.0)
                end
            end)
            tick.MSUF_flashGroup = group
        end

        if tick.MSUF_flash then
            tick.MSUF_flash:SetHeight(barHeight)
        end
        if tick.MSUF_glow then
            tick.MSUF_glow:SetHeight(barHeight)
        end
    end

    for index = count + 1, #frame.empowerTicks do
        local tick = frame.empowerTicks[index]
        if tick then
            tick:Hide()
            if tick.MSUF_glow then tick.MSUF_glow:Hide() end
            if tick.MSUF_flash then tick.MSUF_flash:Hide() end
        end
    end
end

local function EnsureEmpowerStageSegments(frame, count)
    if not frame or not frame.statusBar then return end

    frame.empowerSegments = frame.empowerSegments or {}
    local created
    for index = 1, count do
        local segment = frame.empowerSegments[index]
        if not segment then
            segment = frame.statusBar:CreateTexture(nil, "ARTWORK")
            segment:SetColorTexture(1, 1, 1, 0.18)
            segment:SetBlendMode("ADD")
            frame.empowerSegments[index] = segment
            created = true
        end
        segment:Show()
    end

    for index = count + 1, #frame.empowerSegments do
        frame.empowerSegments[index]:Hide()
    end
    if created and type(_G.MSUF_RoundedCastbar_RefreshFrame) == "function" then
        _G.MSUF_RoundedCastbar_RefreshFrame(frame)
    end
end

local function GetUnifiedDirection()
    local db = _G.MSUF_DB
    if db and db.general ~= nil then
        cachedUnifiedDirection = db.general.castbarUnifiedDirection and true or false
        return cachedUnifiedDirection
    end
    if cachedUnifiedDirection ~= nil then
        return cachedUnifiedDirection
    end

    if type(_G.MSUF_EnsureDB) == "function" then
        _G.MSUF_EnsureDB()
        db = _G.MSUF_DB
    end
    cachedUnifiedDirection = (db and db.general and db.general.castbarUnifiedDirection) and true or false
    return cachedUnifiedDirection
end

local function GetUnifiedFillEnabled(frame)
    local enabled = GetUnifiedDirection()
    if frame then
        frame.MSUF_cachedUnifiedDirection = enabled
    end
    return enabled
end

local function IsEmpowerColorStagesEnabled()
    local db = _G.MSUF_DB
    if db and db.general ~= nil then
        cachedColorStages = not (db.general.empowerColorStages == false)
        return cachedColorStages
    end
    if cachedColorStages ~= nil then
        return cachedColorStages
    end

    if type(_G.MSUF_EnsureDB) == "function" then
        _G.MSUF_EnsureDB()
        db = _G.MSUF_DB
    end
    cachedColorStages = not (db and db.general and db.general.empowerColorStages == false)
    return cachedColorStages
end

local function LayoutEmpowerStageSegments(frame)
    if not frame or not frame.isEmpower or not frame.statusBar then return end
    if not frame.empowerStageEnds or not frame.empowerTotalWithGrace then return end

    if not IsEmpowerColorStagesEnabled() then
        if frame.empowerSegments then
            for index = 1, #frame.empowerSegments do
                local segment = frame.empowerSegments[index]
                if segment then segment:Hide() end
            end
        end
        return
    end

    local barWidth = frame.statusBar:GetWidth() or 0
    if barWidth <= 1 then
        frame.MSUF_empowerLayoutPending = true
        return
    end

    local total = frame.empowerTotalWithGrace
    local stageEnds = frame.empowerStageEnds
    local barHeight = frame.statusBar:GetHeight() or 18
    local reverseFill = (frame.statusBar.GetReverseFill and frame.statusBar:GetReverseFill()) or false

    local segmentCount = #stageEnds
    local lastStageEnd = stageEnds[#stageEnds] or 0
    local hasHoldSegment = total and lastStageEnd and total > (lastStageEnd + 0.001)
    if hasHoldSegment then
        segmentCount = segmentCount + 1
    end

    EnsureEmpowerStageSegments(frame, segmentCount)

    local function LayoutSegment(index, startTime, endTime, color)
        if not total or total <= 0 then return end

        local segment = frame.empowerSegments[index]
        if not segment then return end

        local startRatio = startTime / total
        local endRatio = endTime / total
        if startRatio < 0 then startRatio = 0 elseif startRatio > 1 then startRatio = 1 end
        if endRatio < 0 then endRatio = 0 elseif endRatio > 1 then endRatio = 1 end
        if endRatio < startRatio then endRatio = startRatio end

        local leftRatio = startRatio
        local rightRatio = endRatio

        local left = barWidth * leftRatio
        local right = barWidth * rightRatio
        local width = right - left
        if width < 0 then width = 0 end

        local red, green, blue, alpha = 1, 1, 1, 0.18
        if color then
            red, green, blue, alpha = color[1], color[2], color[3], color[4]
        end

        segment:SetColorTexture(red, green, blue, alpha)
        segment:SetHeight(barHeight)
        segment:ClearAllPoints()
        if reverseFill then
            segment:SetPoint("TOPRIGHT", frame.statusBar, "TOPRIGHT", -left, 0)
            segment:SetPoint("BOTTOMRIGHT", frame.statusBar, "BOTTOMRIGHT", -left, 0)
        else
            segment:SetPoint("TOPLEFT", frame.statusBar, "TOPLEFT", left, 0)
            segment:SetPoint("BOTTOMLEFT", frame.statusBar, "BOTTOMLEFT", left, 0)
        end
        segment:SetWidth(width)
    end

    local previousEnd = 0
    for index = 1, #stageEnds do
        local stageEnd = stageEnds[index] or previousEnd
        local color = STAGE_SEGMENT_COLORS[index] or STAGE_SEGMENT_COLORS[#STAGE_SEGMENT_COLORS]
        LayoutSegment(index, previousEnd, stageEnd, color)
        previousEnd = stageEnd
    end

    if hasHoldSegment then
        LayoutSegment(#stageEnds + 1, previousEnd, total, { 1, 1, 1, 0.10 })
    end

    frame.MSUF_empowerLayoutPending = false
end

local function BlinkEmpowerTick(frame, index)
    if not frame or not frame.empowerTicks then return end

    local tick = frame.empowerTicks[index]
    if not tick then return end

    local flash = tick.MSUF_flash
    local flashGroup = tick.MSUF_flashGroup
    local baseAlpha = tick.MSUF_baseAlpha or TICK_BASE_ALPHA
    local baseWidth = tick.MSUF_baseWidth or TICK_BASE_WIDTH
    tick.MSUF_baseWidth = baseWidth
    tick.MSUF_blinkToken = (tick.MSUF_blinkToken or 0) + 1
    local token = tick.MSUF_blinkToken

    if flash then
        flash:SetVertexColor(1.0, 0.10, 0.10, 1.0)
        flash:SetAlpha(1.0)
        flash:Show()
        if flashGroup then
            if tick.MSUF_flashAnim then
                tick.MSUF_flashAnim:SetDuration(GetEmpowerStageBlinkTime())
            end
            flashGroup:Stop()
            flashGroup:Play()
        end
    end

    if tick.SetWidth then tick:SetWidth(TICK_BLINK_WIDTH) end
    if tick.SetVertexColor then
        tick:SetVertexColor(1.0, 0.10, 0.10, 1.0)
    elseif tick.SetColorTexture then
        tick:SetColorTexture(1.0, 0.10, 0.10, 1.0)
    end

    local blinkTime = GetEmpowerStageBlinkTime()
    C_Timer.After(blinkTime, function()
        if not tick or token ~= tick.MSUF_blinkToken then return end

        if tick.SetWidth then tick:SetWidth(baseWidth) end
        if tick.SetVertexColor then
            tick:SetVertexColor(1.0, 1.0, 1.0, baseAlpha)
        elseif tick.SetColorTexture then
            tick:SetColorTexture(1.0, 1.0, 1.0, baseAlpha)
        elseif tick.SetAlpha then
            tick:SetAlpha(baseAlpha)
        end
    end)
end

local function LayoutEmpowerTicks(frame)
    if not frame or not frame.isEmpower or not frame.statusBar then return end
    if not frame.empowerStageEnds or not frame.empowerTotalWithGrace then return end

    local barWidth = frame.statusBar:GetWidth() or 0
    if barWidth <= 1 then
        frame.MSUF_empowerLayoutPending = true
        return
    end

    local total = frame.empowerTotalWithGrace
    local stageEnds = frame.empowerStageEnds
    local reverseFill = (frame.statusBar.GetReverseFill and frame.statusBar:GetReverseFill()) or false

    LayoutEmpowerStageSegments(frame)
    EnsureEmpowerTicks(frame, #stageEnds)

    for index = 1, #stageEnds do
        local ratio = stageEnds[index] / total
        if ratio < 0 then ratio = 0 elseif ratio > 1 then ratio = 1 end

        local x = barWidth * ratio
        local tick = frame.empowerTicks[index]
        tick:ClearAllPoints()
        if reverseFill then
            tick:SetPoint("CENTER", frame.statusBar, "RIGHT", -x, 0)
        else
            tick:SetPoint("CENTER", frame.statusBar, "LEFT", x, 0)
        end

        local glow = tick.MSUF_glow
        if glow then
            glow:ClearAllPoints()
            glow:SetPoint("CENTER", tick, "CENTER", 0, 0)
            glow:SetWidth(TICK_GLOW_WIDTH)
            glow:SetHeight(frame.statusBar:GetHeight() or 18)
        end

        local flash = tick.MSUF_flash
        if flash then
            flash:ClearAllPoints()
            flash:SetPoint("CENTER", tick, "CENTER", 0, 0)
            local flashWidth = TICK_BLINK_WIDTH * 3
            if flashWidth < 10 then flashWidth = 10 end
            flash:SetWidth(flashWidth)
            flash:SetHeight(frame.statusBar:GetHeight() or 18)
        end
    end

    frame.MSUF_empowerLayoutPending = false
end

local function PlayerCastbarEmpowerStart(frame)
    if not frame or not frame.statusBar then return end

    frame.isEmpower = true
    frame.interruptFeedbackEndTime = nil
    if frame.latencyBar then frame.latencyBar:Hide() end

    local castState = type(_G.MSUF_BuildCastState) == "function" and _G.MSUF_BuildCastState("player") or nil
    local spellName = castState and castState.spellName
    local icon = castState and castState.icon
    if not spellName then
        spellName, _, icon = _G.UnitCastingInfo("player")
        if not spellName then spellName, _, icon = _G.UnitChannelInfo("player") end
    end

    if frame.icon and icon then
        frame.icon:SetTexture(icon)
    end
    if frame.castText then
        if type(_G.MSUF_CB_ApplyTexts) == "function" then
            _G.MSUF_CB_ApplyTexts(frame, nil, spellName or "", nil)
        else
            _G.MSUF_SetTextIfChanged(frame.castText, spellName or "")
        end
    end

    local timeline = BuildEmpowerTimeline("player", castState)
    local now = ((_G.GetTimePreciseSec and _G.GetTimePreciseSec()) or _G.GetTime())
    frame.empowerStartTime = timeline.castStartSec or now
    frame.empowerStageEnds = timeline.stageEnds
    frame.empowerTotalBase = timeline.totalBase
    frame.empowerTotalWithGrace = timeline.totalWithGrace
    frame.empowerNextStage = 1
    frame._msufEmpowerStartNum = PlainNumber(frame.empowerStartTime) or now
    frame._msufEmpowerTotalNum = PlainNumber(frame.empowerTotalWithGrace) or 0
    frame._msufEmpowerBaseNum = PlainNumber(frame.empowerTotalBase) or frame._msufEmpowerTotalNum

    if timeline.stageEnds then
        local numericEnds = {}
        for index = 1, #timeline.stageEnds do
            numericEnds[index] = PlainNumber(timeline.stageEnds[index])
        end
        frame._msufEmpowerStageEndsNum = numericEnds
    else
        frame._msufEmpowerStageEndsNum = nil
    end

    local reverseFill = _G.MSUF_GetReverseFillSafe(frame, true)
    local durationObj = castState and castState.durationObj
    if not durationObj and type(_G.UnitCastingDuration) == "function" then
        durationObj = _G.UnitCastingDuration("player")
    end
    local runtime = _G.MSUF_CastbarRuntime
    if runtime and type(runtime.RetainDuration) == "function" then
        durationObj = runtime:RetainDuration(frame, durationObj)
    end

    _G.MSUF_ApplyTimerAndFill(frame.statusBar, durationObj, reverseFill, false, true)
    -- Empower bars fill on elapsed time; clear any drain flag left by a channel.
    frame._msufCountsDown = false
    frame.MSUF_durationObj = durationObj
    frame.statusBar:SetMinMaxValues(0, frame.empowerTotalWithGrace)

    local elapsed = now - (frame.empowerStartTime or now)
    if elapsed < 0 then elapsed = 0 end
    if elapsed > frame.empowerTotalWithGrace then elapsed = frame.empowerTotalWithGrace end
    frame.statusBar:SetValue(elapsed)

    frame.MSUF_empowerLayoutPending = false
    LayoutEmpowerTicks(frame)

    if not frame.MSUF_empowerSizeHooked and frame.statusBar and frame.statusBar.HookScript then
        frame.MSUF_empowerSizeHooked = true
        frame.statusBar:HookScript("OnSizeChanged", function()
            if frame.isEmpower and frame.MSUF_empowerLayoutPending then
                LayoutEmpowerTicks(frame)
            end
        end)
    end

    frame:SetScript("OnUpdate", nil)
    frame:Show()
    if type(_G.MSUF_RegisterCastbar) == "function" then _G.MSUF_RegisterCastbar(frame) end
    if type(_G.MSUF_UpdateCastbarFrame) == "function" then _G.MSUF_UpdateCastbarFrame(frame, 0) end

    local updateColor = _G.MSUF_PlayerCastbar_UpdateColorForInterruptible
    if type(updateColor) == "function" then
        updateColor(frame)
    end

end

local function PlayerCastbarClearEmpower(frame, hideFrame)
    if not frame then return end

    frame.isEmpower = nil
    frame.empowerStartTime = nil
    frame.empowerStageEnds = nil
    frame.empowerTotalBase = nil
    frame.empowerTotalWithGrace = nil
    frame.empowerNextStage = nil
    frame._msufEmpowerStartNum = nil
    frame._msufEmpowerTotalNum = nil
    frame._msufEmpowerBaseNum = nil
    frame._msufEmpowerStageEndsNum = nil
    frame.MSUF_empowerLayoutPending = false

    if frame.empowerTicks then
        for index = 1, #frame.empowerTicks do
            local tick = frame.empowerTicks[index]
            if tick then
                if tick.Hide then tick:Hide() end
                if tick.MSUF_glow and tick.MSUF_glow.Hide then tick.MSUF_glow:Hide() end
                if tick.MSUF_flash and tick.MSUF_flash.Hide then tick.MSUF_flash:Hide() end
            end
        end
    end

    if frame.empowerSegments then
        for index = 1, #frame.empowerSegments do
            local segment = frame.empowerSegments[index]
            if segment and segment.Hide then segment:Hide() end
        end
    end

    if not hideFrame then return end

    if frame.SetScript then
        frame:SetScript("OnUpdate", nil)
    end
    if type(_G.MSUF_UnregisterCastbar) == "function" then
        _G.MSUF_UnregisterCastbar(frame)
    end
    if frame.timeText then
        _G.MSUF_SetTextIfChanged(frame.timeText, "")
    end
    if frame.latencyBar and frame.latencyBar.Hide then
        frame.latencyBar:Hide()
    end
    if frame.Hide then
        frame:Hide()
    end
end

ExportPublic("MSUF_BuildEmpowerTimeline", BuildEmpowerTimeline)
ExportPublic("MSUF_BlinkEmpowerTick", BlinkEmpowerTick)
ExportPublic("MSUF_LayoutEmpowerTicks", LayoutEmpowerTicks)
ExportPublic("MSUF_EnsureEmpowerTicks", EnsureEmpowerTicks)
ExportPublic("MSUF_EnsureEmpowerStageSegments", EnsureEmpowerStageSegments)
ExportPublic("MSUF_LayoutEmpowerStageSegments", LayoutEmpowerStageSegments)
ExportPublic("MSUF_GetUnifiedDirection", GetUnifiedDirection)
ExportPublic("MSUF_GetUnifiedFillEnabled", GetUnifiedFillEnabled)
ExportPublic("MSUF_IsEmpowerColorStagesEnabled", IsEmpowerColorStagesEnabled)
ExportPublic("MSUF_GetEmpowerStageBlinkTime", GetEmpowerStageBlinkTime)
ExportPublic("MSUF_IsEmpowerStageBlinkEnabled", IsEmpowerStageBlinkEnabled)
ExportPublic("MSUF_PlayerCastbar_EmpowerStart", PlayerCastbarEmpowerStart)
ExportPublic("MSUF_PlayerCastbar_ClearEmpower", PlayerCastbarClearEmpower)
