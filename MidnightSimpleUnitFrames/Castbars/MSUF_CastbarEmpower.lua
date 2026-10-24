--- Empower castbar support.
---
--- Computes empower stage timing and draws stage tick/blink visuals for
--- castbars. This stays isolated from the main castbar runtime because empower
--- APIs vary by client/build.

local _, MSUF = ...
local Castbars = MSUF.Require("MSUF", "Castbars/MSUF_CastbarEmpower.lua").Castbars
local Config = Castbars.Config
local Empower = Castbars.Empower
local Engine = Castbars.Engine
local Manager = Castbars.Manager
local Player = Castbars.Player
local PublicAPI = Castbars.PublicAPI
local Rounded = Castbars.Rounded
local Runtime = Castbars.Runtime
local Utils = Castbars.Utils

local Publish = PublicAPI.Publish

local FILE = "Castbars/MSUF_CastbarEmpower.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local EnsureDB = MSUF.Require("MSUF_EnsureDB", FILE)
local SetTextIfChanged = MSUF.Require("MSUF_SetTextIfChanged", FILE)

local C_Timer = C_Timer
local issecretvalue = issecretvalue
local type = type
local tonumber = tonumber
local tostring = tostring
local math_abs = math.abs

-- MSUF_CastbarUtils.lua loads first and owns the shared scalar unwrapper and
-- the lazy DB bootstrap.
local EnsureDBLazy = Utils.EnsureDBLazy
local PlainNumber = Utils.Castbar_PlainNumber

local function DurationToSeconds(value)
    value = PlainNumber(value)
    if not value then return nil end
    if value > 20 then
        value = value / 1000
    end
    return value
end

local function GetEmpowerStageDuration(unit, stageIndex)
    if type(GetUnitEmpowerStageDuration) ~= "function" then return nil end

    local duration = GetUnitEmpowerStageDuration(unit, stageIndex)
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

    if type(GetUnitEmpowerStageCount) == "function" then
        local count = PlainNumber(GetUnitEmpowerStageCount(unit))
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
    if type(GetUnitEmpowerHoldAtMaxTime) == "function" then
        holdAtMax = DurationToSeconds(GetUnitEmpowerHoldAtMaxTime(unit)) or 0
        if holdAtMax < 0 then holdAtMax = 0 end
    end

    local castStartSec, castEndSec, castTotal
    if castState or type(UnitCastingInfo) == "function" then
        local startMS, endMS
        if castState then
            startMS, endMS = castState.startTimeMS, castState.endTimeMS
        else
            local _, _, _, apiStartMS, apiEndMS = UnitCastingInfo(unit)
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

local cachedColorStages

local blinkRevision, blinkEnabled, blinkTime

local function RefreshBlinkConfig()
    local general = Config.Read().general
    local seconds = general and general.empowerStageBlinkTime
    if type(seconds) ~= "number" then
        seconds = DEFAULT_BLINK_TIME
    end
    if seconds < 0.05 then seconds = 0.05 end
    if seconds > 1.00 then seconds = 1.00 end
    blinkTime = seconds
    blinkEnabled = (not general) or (general.empowerStageBlink ~= false)
    blinkRevision = Config.revision
end

local function GetEmpowerStageBlinkTime()
    if blinkRevision ~= Config.revision then RefreshBlinkConfig() end
    return blinkTime
end

local function IsEmpowerStageBlinkEnabled()
    if blinkRevision ~= Config.revision then RefreshBlinkConfig() end
    return blinkEnabled
end

local function AnimateTickFlash(tick, flash)
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
local function CreateTickBuilder(AnimateFlash)
return function(frame, count)
    if not frame or not frame.statusBar then return end

    frame.empowerTicks = frame.empowerTicks or {}
    local barHeight = frame.statusBar:GetHeight() or 18

    for index = 1, count do
        local tick = frame.empowerTicks[index]
        if not tick then
            tick = PixelLayoutRegion(frame.statusBar:CreateTexture(nil, "OVERLAY"))
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
            local flash = PixelLayoutRegion(frame.statusBar:CreateTexture(nil, "OVERLAY"))
            flash:SetTexture("Interface/Buttons/WHITE8x8")
            flash:SetBlendMode("ADD")
            flash:SetVertexColor(1.0, 0.10, 0.10, 0.0)
            flash:Hide()
            tick.MSUF_flash = flash

            AnimateFlash(tick, flash)
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
end
local EnsureEmpowerTicks = CreateTickBuilder(AnimateTickFlash)

local function EnsureEmpowerStageSegments(frame, count)
    if not frame or not frame.statusBar then return end

    frame.empowerSegments = frame.empowerSegments or {}
    local created
    for index = 1, count do
        local segment = frame.empowerSegments[index]
        if not segment then
            segment = PixelLayoutRegion(frame.statusBar:CreateTexture(nil, "ARTWORK"))
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
    if created then
        -- Castbars/MSUF_CastbarRounded.lua (loads after this file).
        Rounded.RoundedCastbar_RefreshFrame(frame)
    end
end

local function IsEmpowerColorStagesEnabled()
    local db = Config.Read()
    if db and db.general ~= nil then
        cachedColorStages = not (db.general.empowerColorStages == false)
        return cachedColorStages
    end
    if cachedColorStages ~= nil then
        return cachedColorStages
    end

    EnsureDB()
    db = Config.Read()
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

--- The reset of one tick's blink, built once per tick: a blink must not build
--- a closure. Every blink schedules it once; only the last pending timer (the
--- last blink's deadline) restores the base width and colour, as a re-blink
--- before the reset keeps the tick lit until the later blink ends.
local function TickBlinkReset(tick)
    local reset = tick.MSUF_blinkReset
    if reset then return reset end
    reset = function()
        -- The blink counted itself and stored the base width before it
        -- scheduled this; tick creation is the only other writer of both.
        local pending = tick.MSUF_blinkPending - 1
        tick.MSUF_blinkPending = pending
        if pending > 0 then return end

        local baseWidth = tick.MSUF_baseWidth
        local baseAlpha = tick.MSUF_baseAlpha or TICK_BASE_ALPHA
        if tick.SetWidth then tick:SetWidth(baseWidth) end
        if tick.SetVertexColor then
            tick:SetVertexColor(1.0, 1.0, 1.0, baseAlpha)
        elseif tick.SetColorTexture then
            tick:SetColorTexture(1.0, 1.0, 1.0, baseAlpha)
        elseif tick.SetAlpha then
            tick:SetAlpha(baseAlpha)
        end
    end
    tick.MSUF_blinkReset = reset
    return reset
end

local function BlinkEmpowerTick(frame, index)
    if not frame or not frame.empowerTicks then return end

    local tick = frame.empowerTicks[index]
    if not tick then return end

    local flash = tick.MSUF_flash
    local flashGroup = tick.MSUF_flashGroup
    tick.MSUF_baseWidth = tick.MSUF_baseWidth or TICK_BASE_WIDTH
    tick.MSUF_blinkPending = (tick.MSUF_blinkPending or 0) + 1

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

    C_Timer.After(GetEmpowerStageBlinkTime(), tick.MSUF_blinkReset or TickBlinkReset(tick))
end

local function CreateTickLayout(EnsureEmpowerTicks)
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
return LayoutEmpowerTicks
end
local LayoutEmpowerTicks = CreateTickLayout(EnsureEmpowerTicks)
local function NoSampleAnimation() end
function Empower.CreateSampleLayout()
    return CreateTickLayout(CreateTickBuilder(NoSampleAnimation))
end
--- Preview-only: the crossed stage's blink at a given phase (0..1) without a timer.
function Empower.PaintSampleBlink(frame, index, phase)
    local ticks = frame.empowerTicks
    for i = 1, ticks and #ticks or 0 do
        local tick, flash = ticks[i], ticks[i].MSUF_flash
        local on = i == index and phase ~= nil
        tick:SetWidth(on and TICK_BLINK_WIDTH or tick.MSUF_baseWidth)
        if on then tick:SetVertexColor(1.0, 0.10, 0.10, 1.0) else tick:SetVertexColor(1.0, 1.0, 1.0, tick.MSUF_baseAlpha) end
        if flash then
            flash:SetVertexColor(1.0, 0.10, 0.10, 1.0)
            flash:SetAlpha(on and (1 - phase) or 0)
            if on then flash:Show() else flash:Hide() end
        end
    end
end

local function PlayerCastbarEmpowerStart(frame)
    if not frame or not frame.statusBar then return end

    frame.isEmpower = true
    frame.interruptFeedbackEndTime = nil
    if frame.latencyBar then frame.latencyBar:Hide() end

    -- Castbars/MSUF_CastbarEngine.lua (loads after this file).
    local castState = Engine.BuildCastState("player")
    local spellName = castState and castState.spellName
    local icon = castState and castState.icon
    -- SecretWhenUnitSpellCastRestricted: only a plain missing name falls back.
    if not issecretvalue(spellName) and not spellName then
        spellName, _, icon = UnitCastingInfo("player")
        if not spellName then spellName, _, icon = UnitChannelInfo("player") end
    end

    if frame.icon and icon then
        frame.icon:SetTexture(icon)
    end
    if frame.castText then
        Utils.CB_ApplyTexts(frame, nil, spellName or "", nil)
    end

    local timeline = BuildEmpowerTimeline("player", castState)
    local now = ((GetTimePreciseSec and GetTimePreciseSec()) or GetTime())
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

    local reverseFill = Utils.GetReverseFillSafe(frame, true)
    local durationObj = castState and castState.durationObj
    if not durationObj and type(UnitCastingDuration) == "function" then
        durationObj = UnitCastingDuration("player")
    end
    local runtime = Castbars.Runtime
    if runtime and type(runtime.RetainDuration) == "function" then
        durationObj = runtime:RetainDuration(frame, durationObj)
    end

    Runtime.ApplyTimerAndFill(frame.statusBar, durationObj, reverseFill, false, true)
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
    -- Castbars/MSUF_Castbars.lua (loads after this file) owns the manager.
    Manager.RegisterCastbar(frame)
    Manager.UpdateCastbarFrame(frame, 0)

    local updateColor = Player.PlayerCastbar_UpdateColorForInterruptible
    if type(updateColor) == "function" then
        updateColor(frame)
    end

end

-- hot path: kept whole (perf rule)
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
    Manager.UnregisterCastbar(frame)
    if frame.timeText then
        SetTextIfChanged(frame.timeText, "")
    end
    if frame.latencyBar and frame.latencyBar.Hide then
        frame.latencyBar:Hide()
    end
    if frame.Hide then
        frame:Hide()
    end
end

Empower.BlinkEmpowerTick = BlinkEmpowerTick
Empower.LayoutEmpowerTicks = LayoutEmpowerTicks
Empower.GetEmpowerStageBlinkTime = GetEmpowerStageBlinkTime
Publish("MSUF_GetEmpowerStageBlinkTime", Empower.GetEmpowerStageBlinkTime)
Empower.IsEmpowerStageBlinkEnabled = IsEmpowerStageBlinkEnabled
Publish("MSUF_IsEmpowerStageBlinkEnabled", Empower.IsEmpowerStageBlinkEnabled)
Empower.PlayerCastbar_EmpowerStart = PlayerCastbarEmpowerStart
Empower.PlayerCastbar_ClearEmpower = PlayerCastbarClearEmpower
