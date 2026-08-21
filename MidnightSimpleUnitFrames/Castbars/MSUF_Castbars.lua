--- Castbars/MSUF_Castbars.lua
---
--- Player castbar creation, backend application, castbar manager, and timer text
--- update loop. Newer castbar modules own most behavior; this file preserves the
--- historic globals and the shared runtime manager used by player, target, focus,
--- and boss castbars.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = (MSUF.ExportPublic) or function(name, value)
    _G[name] = value
    return value
end

local PlayerCastbarCast = _G.MSUF_PlayerCastbar_Cast
local PlayerCastbarOnEvent = _G.MSUF_PlayerCastbar_OnEvent
local UpdateLatencyZone = _G.MSUF_PlayerCastbar_UpdateLatencyZone
local LayoutEmpowerTicks = _G.MSUF_LayoutEmpowerTicks
local BlinkEmpowerTick = _G.MSUF_BlinkEmpowerTick
local IsEmpowerStageBlinkEnabled = _G.MSUF_IsEmpowerStageBlinkEnabled

local PLAYER_EMPOWER_EVENTS = {
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
}

local PLAYER_CAST_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
}

local RegisterCastbar
local UnregisterCastbar
local UpdateCastbarFrame

local function AfterZero(callback)
    if C_Timer and C_Timer.After then C_Timer.After(0, callback) end
end

local function Now()
    local now = GetTimePreciseSec or GetTime
    return now()
end

local function EnsureGeneralDB()
    local ensure = _G.MSUF_EnsureDB or _G.EnsureDB
    if type(ensure) == "function" then ensure() end

    local db = _G.MSUF_DB
    if not db then
        db = {}
        ExportPublic("MSUF_DB", db)
    end
    db.general = db.general or {}
    return db.general
end

local issecretvalue = _G.issecretvalue or function(_) return false end
local mathHuge = math.huge
local ToPlain = _G.ToPlain

local function ToPlainNumber(value)
    -- PERF fast path: a plain finite number needs no tostring/tonumber
    -- round-trip (that round-trip only exists to redact secrets and to map
    -- nan/inf to nil, which the guards below preserve exactly).
    if type(value) == "number" and issecretvalue(value) ~= true
        and value == value and value ~= mathHuge and value ~= -mathHuge then
        return value
    end

    if value == nil then return nil end
    if issecretvalue(value) == true then
        local converter = _G.MSUF_ToPlainNumber or ToPlain
        if type(converter) ~= "function" then return nil end
        value = converter(value)
        if value == nil or issecretvalue(value) == true then return nil end
    end

    local valueType = type(value)
    if valueType == "number" then
        if value == value and value ~= mathHuge and value ~= -mathHuge then
            return value
        end
        return nil
    elseif valueType == "string" then
        return tonumber(value)
    end
    return nil
end

local function SetText(fontString, text)
    if not fontString then return end
    if type(_G.MSUF_SetTextIfChanged) == "function" then
        _G.MSUF_SetTextIfChanged(fontString, text or "")
    elseif fontString.SetText then
        fontString:SetText(text or "")
    end
end

local function SyncTimeTextFollower(frame)
    local follower = frame and frame._msufTimeTextFollower
    local source = frame and frame.timeText
    if not (follower and source and source.GetText and follower.SetText) then return end
    local text = source:GetText()
    if _G.issecretvalue and _G.issecretvalue(text) == true then
        follower:SetText(text)
    else
        follower:SetText(text or "")
    end
end

ExportPublic("MSUF_Castbar_SyncTimeTextFollower", SyncTimeTextFollower)

local function SetCastTimeText(frame, remaining, total)
    if type(_G.MSUF_SetCastTimeText) == "function" then
        _G.MSUF_SetCastTimeText(frame, remaining, total)
    elseif frame and frame.timeText and frame.timeText.SetFormattedText then
        frame.timeText:SetFormattedText("%.1f", tonumber(remaining) or 0)
    end
    if frame and frame._msufTimeTextFollower then SyncTimeTextFollower(frame) end
end

local function SetCastTimeTextIfChanged(frame, remaining, total)
    if not (frame and frame.timeText) then return end

    local remainingDecimal = math.floor((remaining or 0) * 10)
    local totalDecimal = total and math.floor((total or 0) * 10) or -1
    local format = frame._msufCastTimeFormat or "CURRENT"
    if remainingDecimal == frame._msufLastTimeDecimal
        and totalDecimal == frame._msufLastTimeTotalDecimal
        and format == frame._msufLastTimeFormat
    then
        return
    end

    frame._msufLastTimeDecimal = remainingDecimal
    frame._msufLastTimeTotalDecimal = totalDecimal
    frame._msufLastTimeFormat = format
    SetCastTimeText(frame, remaining, total)
end

local function SetPlayerCastbarEventsRegistered(frame, enabled)
    if not frame then return end

    if enabled then
        if frame._msufPlayerEventsRegistered then return end
        for index = 1, #PLAYER_EMPOWER_EVENTS do
            frame:RegisterUnitEvent(PLAYER_EMPOWER_EVENTS[index], "player")
        end
        for index = 1, #PLAYER_CAST_EVENTS do
            frame:RegisterUnitEvent(PLAYER_CAST_EVENTS[index], "player", "vehicle")
        end
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:SetScript("OnEvent", PlayerCastbarOnEvent)
        frame._msufPlayerEventsRegistered = true
        return
    end

    if not frame._msufPlayerEventsRegistered then return end
    for index = 1, #PLAYER_EMPOWER_EVENTS do
        frame:UnregisterEvent(PLAYER_EMPOWER_EVENTS[index])
    end
    for index = 1, #PLAYER_CAST_EVENTS do
        frame:UnregisterEvent(PLAYER_CAST_EVENTS[index])
    end
    frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", nil)
    frame._msufPlayerEventsRegistered = nil
end

local function HardHidePlayerCastbar(frame)
    if not frame then return end

    if frame.hideTimer and frame.hideTimer.Cancel then frame.hideTimer:Cancel() end
    frame.hideTimer = nil
    if frame.SetScript then frame:SetScript("OnUpdate", nil) end

    frame.interruptFeedbackEndTime = nil
    frame.MSUF_castActive = false
    frame.MSUF_wantsEmpower = nil
    if frame.timeText then frame.timeText:SetText("") end
    if frame.latencyBar then frame.latencyBar:Hide() end
    if type(_G.MSUF_PlayerChannelHasteMarkers_Hide) == "function" then
        _G.MSUF_PlayerChannelHasteMarkers_Hide(frame)
    end
    if UnregisterCastbar then UnregisterCastbar(frame) end
    frame:Hide()
end

local function InitializeExistingPlayerCast()
    local playerFrame = _G.MSUF_PlayerCastbar
    if not (playerFrame and playerFrame._msufPlayerEventsRegistered and PlayerCastbarCast) then return end

    local buildState = _G.MSUF_BuildCastState
    local state = type(buildState) == "function" and buildState("player") or nil
    local active = state and state.active == true
    if not active
        and type(UnitHasVehicleUI) == "function"
        and UnitHasVehicleUI("player")
        and type(UnitExists) == "function"
        and UnitExists("vehicle")
    then
        state = type(buildState) == "function" and buildState("vehicle") or nil
        active = state and state.active == true
    end

    if active then PlayerCastbarCast(playerFrame) end
end

local function CreatePlayerCastbarFrame()
    local frame = CreateFrame("Frame", "MSUF_PlayerCastBar", UIParent)
    frame:SetClampedToScreen(true)
    frame.unit = "player"
    frame:SetSize(200, 18)

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetColorTexture(0, 0, 0, 0)
    frame.background = background

    local icon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
    frame.icon = icon

    local statusBar = CreateFrame("StatusBar", nil, frame)
    statusBar:SetPoint("LEFT", icon, "RIGHT", 0, 0)
    statusBar:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    statusBar:SetPoint("TOP", frame, "TOP", 0, 0)
    statusBar:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)

    local barTexture = "Interface\\TargetingFrame\\UI-StatusBar"
    if type(_G.MSUF_GetCastbarTexture) == "function" then
        barTexture = _G.MSUF_GetCastbarTexture() or barTexture
    end
    statusBar:SetStatusBarTexture(barTexture)
    statusBar:GetStatusBarTexture():SetHorizTile(false)
    frame.statusBar = statusBar

    local backgroundBar = frame:CreateTexture(nil, "ARTWORK")
    backgroundBar:SetPoint("TOPLEFT", statusBar, "TOPLEFT", 0, 0)
    backgroundBar:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 0)

    local backgroundTexture = barTexture
    if type(_G.MSUF_GetCastbarBackgroundTexture) == "function" then
        local texture = _G.MSUF_GetCastbarBackgroundTexture()
        if texture and texture ~= "" then backgroundTexture = texture end
    end
    backgroundBar:SetTexture(backgroundTexture)

    local red, green, blue, alpha = 0.176, 0.176, 0.176, 1
    if type(_G.MSUF_GetCastbarBackgroundColor) == "function" then
        red, green, blue, alpha = _G.MSUF_GetCastbarBackgroundColor()
    end
    backgroundBar:SetVertexColor(red, green, blue, alpha)
    frame.backgroundBar = backgroundBar

    local fontPath, fontSize, fontFlags = GameFontHighlight:GetFont()
    local castText = statusBar:CreateFontString(nil, "OVERLAY")
    castText:SetFont(fontPath, fontSize, fontFlags)
    castText:SetPoint("LEFT", statusBar, "LEFT", 2, 0)
    frame.castText = castText

    local general = EnsureGeneralDB()
    local timeOffsetX = general.castbarPlayerTimeOffsetX or -2
    local timeOffsetY = general.castbarPlayerTimeOffsetY or 0

    local timeText = statusBar:CreateFontString(nil, "OVERLAY")
    timeText:SetFont(fontPath, fontSize, fontFlags)
    timeText:SetPoint("RIGHT", statusBar, "RIGHT", timeOffsetX, timeOffsetY)
    timeText:SetJustifyH("RIGHT")
    timeText:SetText("")
    frame.timeText = timeText

    local latencyBar = statusBar:CreateTexture(nil, "OVERLAY")
    latencyBar:SetColorTexture(1, 0, 0, 0.25)
    latencyBar:SetPoint("TOPRIGHT", statusBar, "TOPRIGHT", 0, 0)
    latencyBar:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 0)
    latencyBar:SetWidth(0)
    latencyBar:Hide()
    frame.latencyBar = latencyBar

    if not frame.MSUF_latencyHooked and frame.HookScript then
        frame:HookScript("OnSizeChanged", function(changedFrame)
            if changedFrame
                and changedFrame.latencyBar
                and changedFrame.MSUF_latencyLastDurSec
                and changedFrame.MSUF_latencyLastDurSec > 0
            then
                UpdateLatencyZone(
                    changedFrame,
                    changedFrame.MSUF_latencyLastIsChanneled,
                    changedFrame.MSUF_latencyLastDurSec
                )
            end
        end)
        frame.MSUF_latencyHooked = true
    end

    if _G.MSUF_ApplyCastbarOutline then _G.MSUF_ApplyCastbarOutline(frame, true) end

    frame.empowerStageTicks = frame.empowerStageTicks or {}
    for index = 1, 4 do
        local tick = frame.empowerStageTicks[index]
        if not tick then
            tick = statusBar:CreateTexture(nil, "OVERLAY")
            tick:SetColorTexture(1, 1, 1, 0.8)
            frame.empowerStageTicks[index] = tick
        end
        tick:SetSize(3, 18)
        tick:Hide()
    end

    SetPlayerCastbarEventsRegistered(frame, true)
    local runtime = _G.MSUF_CastbarRuntime
    if runtime and runtime.PrewarmNativeTimeText then
        runtime:PrewarmNativeTimeText(frame)
    end
    frame:Hide()
    return frame
end

local function InitSafePlayerCastbar()
    if not _G.MSUF_PlayerCastbar then
        ExportPublic("MSUF_PlayerCastbar", CreatePlayerCastbarFrame())
    end
    AfterZero(InitializeExistingPlayerCast)
end

ExportPublic("MSUF_InitSafePlayerCastbar", InitSafePlayerCastbar)

local function PlayerCastbarApplyBackendState()
    local enabled = true
    local isCastbarEnabled = _G.MSUF_IsCastbarEnabledForUnit
    if type(isCastbarEnabled) == "function" then
        enabled = isCastbarEnabled("player") == true
    end

    -- Coldpath apply pass: re-sync the GCD bar's event registration so profile
    -- switches enable/disable it without a reload.
    if type(_G.MSUF_GCDBar_SyncRegistration) == "function" then
        _G.MSUF_GCDBar_SyncRegistration()
    end

    if enabled then
        InitSafePlayerCastbar()
        if _G.MSUF_PlayerCastbar then
            SetPlayerCastbarEventsRegistered(_G.MSUF_PlayerCastbar, true)
        end
        return _G.MSUF_PlayerCastbar
    end

    if _G.MSUF_PlayerCastbar then
        SetPlayerCastbarEventsRegistered(_G.MSUF_PlayerCastbar, false)
        HardHidePlayerCastbar(_G.MSUF_PlayerCastbar)
    end
    return nil
end

ExportPublic("MSUF_PlayerCastbar_ApplyBackendState", PlayerCastbarApplyBackendState)

ExportPublic("MSUF__castbarStyleGlobalRev", _G.MSUF__castbarStyleGlobalRev or 1)
ExportPublic("MSUF_CastbarStyleRev", _G.MSUF__castbarStyleGlobalRev)
local castbarStyleRev = _G.MSUF__castbarStyleGlobalRev

ExportPublic("MSUF__castTimeGlobalRev", _G.MSUF__castTimeGlobalRev or 1)
local castTimeRev = _G.MSUF__castTimeGlobalRev or 1

local applyGlowFade = _G.MSUF_ApplyCastbarGlowFade
local resetGlowFade = _G.MSUF_ResetCastbarGlowFade
local refreshStyleCache = _G.MSUF_RefreshCastbarStyleCache
local castbarRuntime = _G.MSUF_CastbarRuntime
local updateCastbarFrameRef

AfterZero(function()
    applyGlowFade = _G.MSUF_ApplyCastbarGlowFade or applyGlowFade
    resetGlowFade = _G.MSUF_ResetCastbarGlowFade or resetGlowFade
    refreshStyleCache = _G.MSUF_RefreshCastbarStyleCache or refreshStyleCache
    castbarRuntime = _G.MSUF_CastbarRuntime or castbarRuntime
    updateCastbarFrameRef = _G.MSUF_UpdateCastbarFrame
end)

local function BumpCastbarStyleRev()
    ExportPublic("MSUF__castbarStyleGlobalRev", (_G.MSUF__castbarStyleGlobalRev or 1) + 1)
    ExportPublic("MSUF_CastbarStyleRev", _G.MSUF__castbarStyleGlobalRev)
    castbarStyleRev = _G.MSUF__castbarStyleGlobalRev
end

ExportPublic("MSUF_BumpCastbarStyleRev", BumpCastbarStyleRev)

local function BumpCastTimeRev()
    ExportPublic("MSUF__castTimeGlobalRev", (_G.MSUF__castTimeGlobalRev or 1) + 1)
    castTimeRev = _G.MSUF__castTimeGlobalRev
    local runtime = castbarRuntime or _G.MSUF_CastbarRuntime
    if runtime and runtime.RefreshActiveWork then runtime:RefreshActiveWork() end
end

ExportPublic("MSUF_BumpCastTimeRev", BumpCastTimeRev)

local function CastTimeUnitKey(frame, unit)
    unit = tostring(unit or ""):lower()
    if frame and frame._msufIsBossCastbar then return "boss" end
    if unit:match("^boss%d+$") then return "boss" end
    return unit
end

local function RefreshCastTimeEnabled(frame)
    if not (frame and frame.unit) then return true end

    local runtime = castbarRuntime or _G.MSUF_CastbarRuntime
    if runtime and runtime.RefreshWorkConfig then
        local enabled = runtime:RefreshWorkConfig(frame, true)
        return enabled ~= false
    end

    local general = _G.MSUF_DB and _G.MSUF_DB.general
    if not general then
        frame._msufCastTimeEnabled = true
        return true
    end

    local unit = frame.unit
    local enabled = true
    if unit == "player" then
        enabled = general.showPlayerCastTime ~= false
    elseif unit == "target" then
        enabled = general.showTargetCastTime ~= false
    elseif unit == "focus" then
        enabled = general.showFocusCastTime ~= false
    elseif frame._msufIsBossCastbar or tostring(unit or ""):match("^boss%d+$") then
        enabled = general.showBossCastTime ~= false
    end

    local previousFormat = frame._msufCastTimeFormat
    local format = "CURRENT"
    if type(_G.MSUF_GetCastbarTimeFormat) == "function" then
        format = _G.MSUF_GetCastbarTimeFormat(CastTimeUnitKey(frame, unit), general)
    end
    frame._msufCastTimeFormat = format or "CURRENT"

    if previousFormat ~= frame._msufCastTimeFormat then
        frame._msufLastTimeDecimal = nil
        frame._msufLastTimeTotalDecimal = nil
        frame._msufLastTimeFormat = nil
    end

    frame._msufCastTimeEnabled = enabled and true or false
    return frame._msufCastTimeEnabled
end

local function IsCastTimeEnabled(frame, force)
    if not (frame and frame.unit) then return true end

    local revision = _G.MSUF__castTimeGlobalRev or 1
    if force or frame._msufCastTimeRev ~= revision or frame._msufCastTimeEnabled == nil then
        RefreshCastTimeEnabled(frame)
        frame._msufCastTimeRev = revision
    end

    return frame._msufCastTimeEnabled ~= false
end

ExportPublic("MSUF_IsCastTimeEnabled", function(frame)
    return IsCastTimeEnabled(frame, false)
end)

local oldManager = _G.MSUF_CastbarManager
if oldManager then
    if oldManager.SetScript then
        oldManager:SetScript("OnUpdate", nil)
    end
    if oldManager.Hide then oldManager:Hide() end
    if oldManager.active and wipe then wipe(oldManager.active) end
end

local CastbarManager = CreateFrame("Frame")
CastbarManager.active = {}
CastbarManager.low = {}
CastbarManager.high = {}
CastbarManager.failsafe = {}
CastbarManager:Hide()
ExportPublic("MSUF_CastbarManager", CastbarManager)

local activeCount = 0
local highFrequencyCount = 0
local failsafeOnlyCount = 0
local lowFrequencyInterval = 0.10
local failsafeInterval = 0.25
local managerTime = 0
local lowFrequencyTicker
local lowFrequencyLastTime
local failsafeTicker
local managerDriverMode = "IDLE"
local WORK_UNIT_FAILSAFE = castbarRuntime and castbarRuntime.WorkMask
    and castbarRuntime.WorkMask.UNIT_FAILSAFE or 32

local function StopCastbarIfUnitMissing(frame)
    if not frame or frame.unit == "player" or frame.interrupted then return false end

    local now = Now()
    local nextCheck = frame._msufUnitExistNext
    if nextCheck and now < nextCheck then return false end
    frame._msufUnitExistNext = now + failsafeInterval

    local unit = frame.unit
    local missing = unit and unit ~= ""
        and (
            (type(UnitExists) == "function" and not UnitExists(unit))
            or (type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost(unit))
        )
    if not missing then return false end

    if frame._msufIsBossCastbar and type(_G.MSUF_BossCastbar_Stop) == "function" then
        _G.MSUF_BossCastbar_Stop(frame)
    elseif type(_G.MSUF_CB_ResetStateOnStop) == "function" then
        _G.MSUF_CB_ResetStateOnStop(frame, "STOPPED")
    else
        if UnregisterCastbar then UnregisterCastbar(frame) end
        if frame.Hide then frame:Hide() end
    end
    return true
end

local function UpdateFastTextFrame(frame, elapsed)
    local remaining = frame._msufRemaining
    if not (frame._msufFastText and remaining) then return false end

    remaining = remaining - elapsed
    if remaining < 0 then remaining = 0 end
    frame._msufRemaining = remaining

    if remaining <= 0.001 then
        if frame.SetSucceeded then frame:SetSucceeded() else frame:Hide() end
        return true
    end

    local decimal = math.floor(remaining * 10)
    local format = frame._msufCastTimeFormat or "CURRENT"
    if format == "CURRENT" then
        if decimal ~= frame._msufLastTimeDecimal then
            frame._msufLastTimeDecimal = decimal
            frame._msufLastTimeTotalDecimal = -1
            frame._msufLastTimeFormat = format
            frame.timeText._msufLastText = nil
            frame.timeText:SetFormattedText("%.1f", remaining)
            if frame._msufTimeTextFollower then SyncTimeTextFollower(frame) end
        end
    else
        SetCastTimeTextIfChanged(frame, remaining, frame._msufPlainTotal)
    end

    if frame.MSUF_isChanneled then
        if remaining < 1.0 then
            local heavyIn = frame._msufHeavyIn or 0
            heavyIn = heavyIn - elapsed
            if heavyIn <= 0 then
                heavyIn = frame._msufTickInterval or 0.10
                local updater = updateCastbarFrameRef or _G.MSUF_UpdateCastbarFrame
                if updater then updater(frame, elapsed, nil, managerTime) end
            end
            frame._msufHeavyIn = heavyIn
        end
    elseif frame._msufCastbarGlowTick and applyGlowFade then
        local total = frame._msufPlainTotal
        if total and total > 0 then
            local glowIn = frame._msufGlowIn or 0
            glowIn = glowIn - elapsed
            if glowIn <= 0 then
                frame._msufGlowIn = 0.04
                applyGlowFade(frame, remaining, total)
            else
                frame._msufGlowIn = glowIn
            end
        end
    end

    return true
end

local function UpdateHeavyFrame(frame, elapsed)
    local heavyIn = frame._msufHeavyIn or 0
    heavyIn = heavyIn - elapsed
    if heavyIn <= 0 then
        heavyIn = frame._msufTickInterval or 0.10
        local updater = updateCastbarFrameRef or _G.MSUF_UpdateCastbarFrame
        if updater then updater(frame, elapsed, nil, managerTime) end
    end
    frame._msufHeavyIn = heavyIn
end

local function UpdateManagedFrame(frame, elapsed)
    local stopped = StopCastbarIfUnitMissing(frame)
    if not stopped and not UpdateFastTextFrame(frame, elapsed) then
        UpdateHeavyFrame(frame, elapsed)
    end
end

local function UpdateBucket(bucket, elapsed)
    local frame = next(bucket)
    while frame do
        local nextFrame = next(bucket, frame)
        -- Keep the recurring ticker path inlined; UpdateManagedFrame exists for
        -- the O(1) registration refresh and must not add another Lua call to
        -- every active castbar tick.
        local stopped = StopCastbarIfUnitMissing(frame)
        if not stopped and not UpdateFastTextFrame(frame, elapsed) then
            UpdateHeavyFrame(frame, elapsed)
        end
        frame = nextFrame
    end
end

local function UpdateFailsafeBucket()
    local bucket = CastbarManager.failsafe
    local frame = next(bucket)
    while frame do
        local nextFrame = next(bucket, frame)
        StopCastbarIfUnitMissing(frame)
        frame = nextFrame
    end
end

local RefreshManagerOnUpdate

local function StopLowFrequencyTicker()
    if lowFrequencyTicker then
        lowFrequencyTicker:Cancel()
        lowFrequencyTicker = nil
    end
    lowFrequencyLastTime = nil
end

local function StopFailsafeTicker()
    if failsafeTicker then
        failsafeTicker:Cancel()
        failsafeTicker = nil
    end
end

local function FailsafeTicker()
    if failsafeOnlyCount <= 0 then
        StopFailsafeTicker()
        return
    end
    UpdateFailsafeBucket()
end

local function RefreshFailsafeTicker()
    if failsafeOnlyCount <= 0 then
        StopFailsafeTicker()
        return
    end
    if not failsafeTicker and C_Timer and C_Timer.NewTicker then
        UpdateFailsafeBucket()
        if failsafeOnlyCount > 0 then
            failsafeTicker = C_Timer.NewTicker(failsafeInterval, FailsafeTicker)
        end
    end
end

local function LowFrequencyTicker()
    if activeCount - failsafeOnlyCount <= 0 then
        StopLowFrequencyTicker()
        if RefreshManagerOnUpdate then RefreshManagerOnUpdate() end
        return
    end

    if highFrequencyCount > 0 then
        StopLowFrequencyTicker()
        if RefreshManagerOnUpdate then RefreshManagerOnUpdate() end
        return
    end

    local now = Now()
    local elapsed = lowFrequencyLastTime and (now - lowFrequencyLastTime) or lowFrequencyInterval
    lowFrequencyLastTime = now

    if elapsed <= 0 or elapsed > 0.5 then
        elapsed = lowFrequencyInterval
    end

    managerTime = managerTime + elapsed
    UpdateBucket(CastbarManager.low, elapsed)
end

local function ManagerOnUpdate(manager, elapsed)
    if activeCount <= 0 then
        StopLowFrequencyTicker()
        StopFailsafeTicker()
        manager._msufLowTickAccum = 0
        managerDriverMode = "IDLE"
        manager:Hide()
        return
    end

    elapsed = elapsed or 0
    managerTime = managerTime + elapsed

    if highFrequencyCount > 0 then
        UpdateBucket(manager.high, elapsed)
    end

    local lowFrequencyCount = activeCount - highFrequencyCount - failsafeOnlyCount
    if lowFrequencyCount > 0 then
        local accumulated = (manager._msufLowTickAccum or 0) + elapsed
        if accumulated >= lowFrequencyInterval then
            manager._msufLowTickAccum = 0
            UpdateBucket(manager.low, accumulated)
        else
            manager._msufLowTickAccum = accumulated
        end
    else
        manager._msufLowTickAccum = 0
    end
end

RefreshManagerOnUpdate = function()
    if activeCount <= 0 then
        StopLowFrequencyTicker()
        StopFailsafeTicker()
        CastbarManager:SetScript("OnUpdate", nil)
        managerDriverMode = "IDLE"
        CastbarManager:Hide()
        return false
    end

    CastbarManager:Show()
    RefreshFailsafeTicker()

    local runtimeCount = activeCount - failsafeOnlyCount
    if runtimeCount <= 0 then
        StopLowFrequencyTicker()
        CastbarManager:SetScript("OnUpdate", nil)
        managerDriverMode = "FAILSAFE"
        return false
    end

    if highFrequencyCount > 0 then
        StopLowFrequencyTicker()
        CastbarManager:SetScript("OnUpdate", ManagerOnUpdate)
        managerDriverMode = "FRAME"
        return false
    end

    CastbarManager:SetScript("OnUpdate", nil)

    if C_Timer and C_Timer.NewTicker then
        local topologyChanged = managerDriverMode ~= "LOW_TICKER"
        if not lowFrequencyTicker then
            lowFrequencyLastTime = Now()
            lowFrequencyTicker = C_Timer.NewTicker(lowFrequencyInterval, LowFrequencyTicker)
        end
        managerDriverMode = "LOW_TICKER"
        if topologyChanged then
            -- A real driver hand-off (idle/failsafe/frame -> ticker) gets one
            -- immediate coherent pass. Steady-state Register/Unregister calls
            -- initialize only their affected frame below.
            UpdateBucket(CastbarManager.low, 0)
            return true
        end
        return false
    end

    local topologyChanged = managerDriverMode ~= "FRAME"
    managerDriverMode = "FRAME"
    CastbarManager:SetScript("OnUpdate", ManagerOnUpdate)
    if topologyChanged then
        UpdateBucket(CastbarManager.low, 0)
        return true
    end
    return false
end

CastbarManager:SetScript("OnHide", function(manager)
    StopLowFrequencyTicker()
    StopFailsafeTicker()
    manager:SetScript("OnUpdate", nil)
    managerDriverMode = "IDLE"
end)

local function FrameHasRuntimeWork(frame)
    if frame.IsShown and not frame:IsShown()
        and frame._msufPreview ~= true then
        return false
    end
    return frame.MSUF_castActive == true
        or frame.isEmpower == true
        or frame.MSUF_timerDriven == true
        or frame._msufPlainEndTime ~= nil
        or frame._msufPlainTotal ~= nil
        or frame.MSUF_durationObj ~= nil
        or frame.MSUF_castDuration ~= nil
        or frame.MSUF_channelDuration ~= nil
        or frame.castDuration ~= nil
        or frame.channelDuration ~= nil
end

local function CastbarOnHide(hiddenFrame)
    if hiddenFrame._msufInUnregister then return end
    if UnregisterCastbar then UnregisterCastbar(hiddenFrame) end
end

RegisterCastbar = function(frame)
    if not (frame and frame.statusBar) then return end
    if not (CastbarManager and CastbarManager.active) then return end

    if not FrameHasRuntimeWork(frame) then
        if CastbarManager.active[frame] == true and UnregisterCastbar then
            UnregisterCastbar(frame)
        end
        return
    end

    if not frame._msufOnHideHooked then
        frame._msufOnHideHooked = true
        frame:HookScript("OnHide", CastbarOnHide)
    end

    local runtime = castbarRuntime or _G.MSUF_CastbarRuntime
    local workMask
    if runtime and runtime.PrepareWork then
        workMask = runtime:PrepareWork(frame)
    else
        IsCastTimeEnabled(frame, true)
    end

    if workMask == 0 then
        if CastbarManager.active[frame] == true and UnregisterCastbar then
            UnregisterCastbar(frame)
            workMask = runtime:PrepareWork(frame)
        end
        if workMask == 0 and runtime:ArmNativeCompletion(frame) then
            return
        end
        workMask = runtime:PrepareWork(frame)
    elseif workMask == WORK_UNIT_FAILSAFE and runtime and runtime.ArmNativeCompletion then
        if not runtime:ArmNativeCompletion(frame) then
            workMask = runtime:PrepareWork(frame)
        end
    elseif runtime and runtime.CancelNativeCompletion then
        runtime:CancelNativeCompletion(frame)
    end

    frame._msufFastText = (frame.timeText and frame._msufCastTimeEnabled ~= false and frame.MSUF_timerDriven == true
        and frame._msufNativeTimeBound ~= true and not frame.isEmpower) or false

    if frame.isEmpower then
        frame._msufTickInterval = 0.03
    elseif frame._msufFastText ~= true and frame.MSUF_timerDriven ~= true then
        if frame._msufTickInterval == nil or frame._msufTickInterval > 0.05 then
            frame._msufTickInterval = 0.05
        end
    elseif frame._msufTickInterval == nil or frame._msufTickInterval < 0.10 then
        frame._msufTickInterval = 0.10
    end

    frame._msufHeavyIn = 0
    if frame._msufPlainEndTime then
        local remaining = frame._msufPlainEndTime - Now()
        frame._msufRemaining = (remaining > 0) and remaining or 0
    end

    local failsafeOnly = workMask == WORK_UNIT_FAILSAFE
        and C_Timer and type(C_Timer.NewTicker) == "function" or false
    local highFrequency = not failsafeOnly
        and frame._msufTickInterval and frame._msufTickInterval < 0.10 or false
    local wasActive = CastbarManager.active[frame] == true
    local wasHighFrequency = frame._msufManagerHighFreq == true
    local wasFailsafeOnly = frame._msufManagerFailsafeOnly == true
    if wasActive and wasHighFrequency then highFrequencyCount = highFrequencyCount - 1 end
    if wasActive and wasFailsafeOnly then failsafeOnlyCount = failsafeOnlyCount - 1 end
    if highFrequencyCount < 0 then highFrequencyCount = 0 end
    if failsafeOnlyCount < 0 then failsafeOnlyCount = 0 end
    frame._msufManagerHighFreq = highFrequency or nil
    frame._msufManagerFailsafeOnly = failsafeOnly or nil

    local oldBucket = frame._msufManagerBucket
    local newBucket = failsafeOnly and CastbarManager.failsafe
        or (highFrequency and CastbarManager.high or CastbarManager.low)
    if wasActive and oldBucket ~= newBucket then
        if oldBucket then oldBucket[frame] = nil end
        newBucket[frame] = true
        frame._msufManagerBucket = newBucket
    end

    if wasActive then
        if highFrequency then highFrequencyCount = highFrequencyCount + 1 end
        if failsafeOnly then failsafeOnlyCount = failsafeOnlyCount + 1 end
    else
        activeCount = activeCount + 1
        if highFrequency then highFrequencyCount = highFrequencyCount + 1 end
        if failsafeOnly then failsafeOnlyCount = failsafeOnlyCount + 1 end
        CastbarManager.active[frame] = true
        newBucket[frame] = true
        frame._msufManagerBucket = newBucket
    end

    local lowBucketScanned = RefreshManagerOnUpdate()
    -- Failsafe-only frames have no visual work: the first frame is sampled
    -- when its ticker starts and later additions retain that ticker's cadence.
    if not lowBucketScanned
        and not failsafeOnly
        and not highFrequency
        and CastbarManager.active[frame] == true
    then
        -- Preserve the old zero-delay low-frequency initialization without
        -- walking sibling frames. High-frequency casts already have a caller-
        -- owned initial render and enter the frame driver on the next tick.
        UpdateManagedFrame(frame, 0)
    end
end

UnregisterCastbar = function(frame)
    if not frame then return end
    if not (CastbarManager and CastbarManager.active) then return end

    frame._msufInUnregister = true
    local runtime = castbarRuntime or _G.MSUF_CastbarRuntime
    if runtime and runtime.DeactivateNative then runtime:DeactivateNative(frame) end
    if resetGlowFade then resetGlowFade(frame) end

    if CastbarManager.active[frame] then
        CastbarManager.active[frame] = nil
        if CastbarManager.low then CastbarManager.low[frame] = nil end
        if CastbarManager.high then CastbarManager.high[frame] = nil end
        if CastbarManager.failsafe then CastbarManager.failsafe[frame] = nil end

        activeCount = activeCount - 1
        if activeCount < 0 then activeCount = 0 end

        if frame._msufManagerHighFreq then
            highFrequencyCount = highFrequencyCount - 1
            if highFrequencyCount < 0 then highFrequencyCount = 0 end
        end
        if frame._msufManagerFailsafeOnly then
            failsafeOnlyCount = failsafeOnlyCount - 1
            if failsafeOnlyCount < 0 then failsafeOnlyCount = 0 end
        end
    end

    frame._msufHeavyIn = nil
    frame._msufHardStopNext = nil
    frame._msufUnitExistNext = nil
    frame._msufZeroCount = nil
    frame._msufLastTimeDecimal = nil
    frame._msufLastTimeTotalDecimal = nil
    frame._msufLastTimeFormat = nil
    frame._msufFastText = nil
    frame._msufRemaining = nil
    frame._msufGlowIn = nil
    frame._msufCastTimeWasEnabled = nil
    frame._msufManagerHighFreq = nil
    frame._msufManagerFailsafeOnly = nil
    frame._msufManagerBucket = nil
    frame._msufInUnregister = nil

    RefreshManagerOnUpdate()
end

local function CompleteOrHideFrame(frame)
    if frame.SetSucceeded then
        frame:SetSucceeded()
    else
        UnregisterCastbar(frame)
        if frame.Hide then frame:Hide() end
    end
end

local function UpdateEmpowerFrame(frame, now)
    local total = frame._msufEmpowerTotalNum
    if not total then
        total = ToPlainNumber(frame.empowerTotalWithGrace) or 0
        if total > 0 then frame._msufEmpowerTotalNum = total end
    end
    if total <= 0 then total = 0.01 end

    now = now or Now()
    local startTime = frame._msufEmpowerStartNum
    if not startTime then
        startTime = ToPlainNumber(frame.empowerStartTime) or now
        frame._msufEmpowerStartNum = startTime
    end

    local elapsed = now - startTime
    if elapsed < 0 then elapsed = 0 end
    if elapsed > total then elapsed = total end
    frame._msufEmpowerElapsed = elapsed

    if not frame._msufEmpowerMinMaxSet then
        frame._msufEmpowerMinMaxSet = true
        if frame.statusBar.SetMinMaxValues then frame.statusBar:SetMinMaxValues(0, total) end
    end
    if frame.statusBar.SetValue then frame.statusBar:SetValue(elapsed) end

    local baseTotal = frame._msufEmpowerBaseNum
    if not baseTotal then
        baseTotal = ToPlainNumber(frame.empowerTotalBase) or total
        if baseTotal > 0 then frame._msufEmpowerBaseNum = baseTotal end
    end
    if baseTotal <= 0 then baseTotal = total end

    if frame.timeText and frame._msufCastTimeEnabled ~= false then
        local remaining = baseTotal - elapsed
        if remaining < 0 then remaining = 0 end
        SetCastTimeTextIfChanged(frame, remaining, baseTotal)
    end

    if frame.MSUF_empowerLayoutPending and LayoutEmpowerTicks then
        LayoutEmpowerTicks(frame)
    end

    if frame.empowerStageEnds and frame.empowerTicks and BlinkEmpowerTick then
        frame.empowerNextStage = frame.empowerNextStage or 1
        local stageEnds = frame._msufEmpowerStageEndsNum
        while frame.empowerNextStage <= #frame.empowerStageEnds do
            local stageIndex = frame.empowerNextStage
            local stageEnd = stageEnds and stageEnds[stageIndex]
            if not stageEnd then
                stageEnd = frame.empowerStageEnds[stageIndex]
                if type(stageEnd) ~= "number" then stageEnd = ToPlainNumber(stageEnd) end
                if stageEnd and stageEnds then stageEnds[stageIndex] = stageEnd end
            end
            if not stageEnd then break end

            if elapsed >= stageEnd then
                if IsEmpowerStageBlinkEnabled and IsEmpowerStageBlinkEnabled() then
                    BlinkEmpowerTick(frame, stageIndex)
                end
                frame.empowerNextStage = stageIndex + 1
            else
                break
            end
        end
    end

    if frame._msufCastbarGlowTick and applyGlowFade and baseTotal > 0 then
        local remaining = baseTotal - elapsed
        if remaining < 0 then remaining = 0 end
        applyGlowFade(frame, remaining, baseTotal)
    end
end

local function CheckChannelHardStop(frame, sampleTime)
    if not frame.MSUF_isChanneled then return false end

    local nextCheck = frame._msufHardStopNext
    if nextCheck and sampleTime < nextCheck then return false end
    frame._msufHardStopNext = sampleTime + 0.15

    local unit = frame.unit
    if unit == "player" then
        local activeUnit = frame._msufActiveCastUnit
        if activeUnit == "player" or activeUnit == "vehicle" then
            unit = activeUnit
        end
    end
    if not unit or unit == "" then return false end

    local channelActive = UnitChannelInfo(unit) ~= nil
    if not channelActive and frame.unit == "player" then
        -- Vehicle transitions are event-owned, but the hard-stop guard must not
        -- produce a false completion during the narrow hand-off window. Probe
        -- the alternate token only after the stored active token returned no
        -- channel; the steady channel tick therefore performs one API read and
        -- never rebuilds a full cast state/DurationObject.
        local alternateUnit
        if unit == "vehicle" then
            alternateUnit = "player"
        elseif type(UnitHasVehicleUI) == "function"
            and UnitHasVehicleUI("player")
            and type(UnitExists) == "function"
            and UnitExists("vehicle")
        then
            alternateUnit = "vehicle"
        end
        if alternateUnit and UnitChannelInfo(alternateUnit) then
            frame._msufActiveCastUnit = alternateUnit
            channelActive = true
        end
    end

    if channelActive then
        frame._msufHardStopNoChannelSince = nil
        frame._msufHardStopChanThresh = nil
        return false
    end

    local noChannelSince = frame._msufHardStopNoChannelSince
    if not noChannelSince then
        frame._msufHardStopNoChannelSince = sampleTime

        local spellQueueMs = 0
        if GetCVar then spellQueueMs = tonumber(GetCVar("SpellQueueWindow") or "0") or 0 end
        if spellQueueMs < 0 then spellQueueMs = 0 end

        local threshold = 0.45
        local queueThreshold = (spellQueueMs / 1000) + 0.10
        if queueThreshold > threshold then threshold = queueThreshold end
        if threshold > 0.80 then threshold = 0.80 end
        frame._msufHardStopChanThresh = threshold
        return false
    end

    local threshold = frame._msufHardStopChanThresh or 0.45
    if (sampleTime - noChannelSince) >= threshold then
        if frame.SetSucceeded then frame:SetSucceeded() else frame:Hide() end
        return true
    end

    return false
end

local function InferRemainingFromStatusBar(frame)
    local statusBar = frame.statusBar
    if not (statusBar and statusBar.GetMinMaxValues and statusBar.GetValue) then return nil, nil end

    local minValue, maxValue = statusBar:GetMinMaxValues()
    local value = statusBar:GetValue()
    minValue = ToPlainNumber(minValue) or 0
    maxValue = ToPlainNumber(maxValue)
    value = ToPlainNumber(value)
    if not (maxValue and value and maxValue > minValue) then return nil, nil end

    local total = maxValue - minValue
    local assumeCountdown = frame._msufTimerAssumeCountdown
    if assumeCountdown == nil then
        if frame._msufCountsDown ~= nil then
            assumeCountdown = frame._msufCountsDown == true
        elseif frame.MSUF_timerDriven == true then
            assumeCountdown = frame.MSUF_isChanneled == true
        else
            local fromMin = math.abs(value - minValue)
            local fromMax = math.abs(maxValue - value)
            assumeCountdown = fromMax < fromMin
        end
        frame._msufTimerAssumeCountdown = assumeCountdown
    end

    local remaining = assumeCountdown and (value - minValue) or (maxValue - value)
    if remaining < 0 then remaining = 0 end
    if remaining > total then remaining = total end
    return remaining, total
end

local function ResolveDurationTotal(frame, durationObj, inferredTotal)
    local total = frame._msufPlainTotal
    if not total and durationObj.GetTotalDuration then
        total = ToPlainNumber(durationObj:GetTotalDuration())
    end
    if not total and inferredTotal then total = inferredTotal end
    if not total and frame.statusBar and frame.statusBar.GetMinMaxValues then
        local minValue, maxValue = frame.statusBar:GetMinMaxValues()
        minValue = ToPlainNumber(minValue) or 0
        maxValue = ToPlainNumber(maxValue)
        if maxValue and maxValue > minValue then total = maxValue - minValue end
    end
    return total
end

local function UpdateDurationObjectFrame(frame, now)
    local durationObj = frame.MSUF_durationObj
    if not (durationObj and (durationObj.GetRemainingDuration or durationObj.GetRemaining)) then return false end

    if frame._msufLastDurationObj ~= durationObj then
        frame._msufLastDurationObj = durationObj
        frame._msufTimerAssumeCountdown = nil
        frame._msufPlainEndTime = nil
        frame._msufPlainTotal = nil
        frame._msufRemaining = nil
        frame._msufZeroCount = nil
    end

    local plainEndTime = frame._msufPlainEndTime
    local remainingFromEnd = plainEndTime and (plainEndTime - now) or nil
    local shouldPollDuration = (not remainingFromEnd) or (remainingFromEnd < 1.0)
    local remaining
    local inferredTotal

    if shouldPollDuration then
        -- Hottest duration read in the addon (up to 20 Hz per bar in a cast's
        -- final second). 12.1 contract: no-arg getters cannot violate
        -- SecretArguments; secret returns are rejected by ToPlainNumber.
        local rawRemaining
        if durationObj.GetRemainingDuration then
            rawRemaining = durationObj:GetRemainingDuration()
        else
            rawRemaining = durationObj:GetRemaining()
        end
        remaining = ToPlainNumber(rawRemaining)

        if not remaining and frame.statusBar and frame.MSUF_timerDriven then
            remaining, inferredTotal = InferRemainingFromStatusBar(frame)
        end

        if not remaining and not remainingFromEnd then
            if frame.timeText
                and frame._msufCastTimeEnabled ~= false
                and frame._msufNativeTimeBound ~= true
                and rawRemaining ~= nil
            then
                if type(rawRemaining) == "number" and frame.timeText.SetFormattedText then
                    frame.timeText:SetFormattedText("%.1f", rawRemaining)
                else
                    SetText(frame.timeText, tostring(rawRemaining or ""))
                end
                frame._msufZeroCount = nil
            end
            return true
        end
    else
        remaining = remainingFromEnd
    end

    if not remaining then return true end
    if remaining < 0 then remaining = 0 end
    if shouldPollDuration then
        frame._msufPlainEndTime = now + remaining
        frame._msufRemaining = remaining
    end

    local needsLuaTimeText = frame.timeText
        and frame._msufCastTimeEnabled ~= false
        and frame._msufNativeTimeBound ~= true
    local needsTotal = frame._msufCastbarGlowTick or needsLuaTimeText
    local total
    if needsTotal then
        total = ResolveDurationTotal(frame, durationObj, inferredTotal)
    end

    if needsLuaTimeText then
        SetCastTimeTextIfChanged(frame, remaining, total)
    end

    if frame._msufCastbarGlowTick and applyGlowFade then
        if total and total > 0 then applyGlowFade(frame, remaining, total) end
    end

    if remaining <= 0.001 then
        frame._msufZeroCount = (frame._msufZeroCount or 0) + 1
        if frame._msufZeroCount >= 2 then
            frame._msufZeroCount = nil
            CompleteOrHideFrame(frame)
        end
    else
        frame._msufZeroCount = nil
    end

    return true
end

local function UpdateEndTimeFrame(frame, now)
    if not frame.endTime then return end

    local endTime = ToPlainNumber(frame.endTime) or 0
    local remaining = endTime - now
    if remaining < 0 then remaining = 0 end

    local total = frame._msufPlainTotal
    if total and total > 0 and frame.statusBar and frame.statusBar.SetValue then
        -- Cast type decides the count direction; the anchor only decides which
        -- edge the fill grows from (see MSUF_GetCastbarCountsDown).
        local value = frame._msufCountsDown and remaining or (total - remaining)
        if value < 0 then value = 0 end
        if value > total then value = total end
        frame.statusBar:SetValue(value)
    end

    if frame.timeText
        and frame._msufCastTimeEnabled ~= false
        and frame._msufNativeTimeBound ~= true
    then
        SetCastTimeTextIfChanged(frame, remaining, total)
    end

    if frame._msufCastbarGlowTick
        and applyGlowFade
        and frame.statusBar
        and frame.statusBar.GetMinMaxValues
    then
        local minValue, maxValue = frame.statusBar:GetMinMaxValues()
        minValue = ToPlainNumber(minValue) or 0
        maxValue = ToPlainNumber(maxValue)
        if maxValue and maxValue > minValue then
            local statusTotal = maxValue - minValue
            if statusTotal and statusTotal > 0 then
                applyGlowFade(frame, remaining, statusTotal)
            end
        end
    end

    if remaining <= 0.001 then CompleteOrHideFrame(frame) end
end

UpdateCastbarFrame = function(frame, elapsed, now, sampleTime)
    if not (frame and frame.statusBar) then return end
    if frame._msufCastbarWorkMask == 0 then return end

    local castTimeEnabled = frame._msufCastTimeEnabled
    if castTimeEnabled == nil or frame._msufCastTimeRev ~= castTimeRev then
        castTimeEnabled = IsCastTimeEnabled(frame, false)
    end

    if frame.timeText and not castTimeEnabled and frame._msufCastTimeWasEnabled then
        SetText(frame.timeText, "")
    end
    if frame._msufCastTimeWasEnabled ~= castTimeEnabled then
        frame._msufCastTimeWasEnabled = castTimeEnabled
    end

    if frame._msufCastbarStyleRev ~= castbarStyleRev then
        if refreshStyleCache then refreshStyleCache(frame) end
        frame._msufCastbarStyleRev = castbarStyleRev
    end

    sampleTime = sampleTime or 0
    if frame.isEmpower and frame.empowerStartTime and frame.empowerTotalWithGrace then
        UpdateEmpowerFrame(frame, now)
        return
    end

    if CheckChannelHardStop(frame, sampleTime) then return end

    now = now or Now()
    if UpdateDurationObjectFrame(frame, now) then return end
    UpdateEndTimeFrame(frame, now)
end

ExportPublic("MSUF_RegisterCastbar", RegisterCastbar)
ExportPublic("MSUF_UnregisterCastbar", UnregisterCastbar)
ExportPublic("MSUF_UpdateCastbarFrame", UpdateCastbarFrame)
