--- Castbars/MSUF_BossCastbars.lua
--- Live boss castbar pool and boss-unit event driver.
---
--- Boss castbars reuse the generic castbar frame/runtime stack, but they need
--- their own frame pool, boss-specific anchoring, encounter/unit lifecycle
--- handling, and menu-facing enable/position globals.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local MAX_BOSS_FRAMES = tonumber(_G.MSUF_MAX_BOSS_FRAMES or _G.MAX_BOSS_FRAMES) or 5
if MAX_BOSS_FRAMES < 1 or MAX_BOSS_FRAMES > 12 then
    MAX_BOSS_FRAMES = 5
end
local UnitExists = _G.UnitExists
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitIsUnconscious = _G.UnitIsUnconscious

local CAST_EVENTS = {
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

local function EnsureDB()
    if type(_G.EnsureDB) == "function" then
        _G.EnsureDB()
    end
end

local function InCombat()
    return _G.MSUF_InCombat == true
        or ((_G.InCombatLockdown and _G.InCombatLockdown()) and true or false)
        or ((_G.UnitAffectingCombat and _G.UnitAffectingCombat("player")) and true or false)
end

local function BossCastbarsEnabled()
    EnsureDB()

    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local shouldUseMSUF = _G.MSUF_ShouldUseMSUFCastbar

    if type(shouldUseMSUF) == "function" then
        return shouldUseMSUF("boss", general) == true
    end

    return (not general) or general.enableBossCastbar ~= false
end

local function SetPointIfChanged(frame, point, relativeTo, relativePoint, offsetX, offsetY, preserveOffsets)
    if not frame then
        return false
    end

    offsetX = tonumber(offsetX) or 0
    offsetY = tonumber(offsetY) or 0
    if not preserveOffsets then
        offsetX = math.floor(offsetX + 0.5)
        offsetY = math.floor(offsetY + 0.5)
    end

    local currentPoint, currentRelativeTo, currentRelativePoint, currentX, currentY = frame:GetPoint(1)
    if currentPoint == point
        and currentRelativeTo == relativeTo
        and currentRelativePoint == relativePoint
        and math.abs((tonumber(currentX) or 0) - offsetX) <= 0.01
        and math.abs((tonumber(currentY) or 0) - offsetY) <= 0.01
    then
        return false
    end

    frame:ClearAllPoints()
    frame:SetPoint(point, relativeTo, relativePoint, offsetX, offsetY)
    return true
end

local function SetWidthIfChanged(frame, width)
    width = tonumber(width)
    if not (frame and width and width > 0) then
        return false
    end

    if frame.GetWidth and math.abs((frame:GetWidth() or 0) - width) <= 0.01 then
        return false
    end

    frame:SetWidth(width)
    return true
end

local function SetHeightIfChanged(frame, height)
    height = tonumber(height)
    if not (frame and height and height > 0) then
        return false
    end

    if frame.GetHeight and math.abs((frame:GetHeight() or 0) - height) <= 0.01 then
        return false
    end

    frame:SetHeight(height)
    return true
end

local function Snap(frame, value)
    value = tonumber(value) or 0
    if type(_G.MSUF_Snap) == "function" then
        return _G.MSUF_Snap(frame, value)
    end
    return math.floor(value + 0.5)
end

--- Applies only internal boss castbar region layout. Positioning relative to
--- boss unit frames or UIParent is handled by UpdateBossCastbarAnchor.
local function ApplyBossCastbarLayout(frame)
    if not (frame and frame.statusBar) then
        return
    end

    EnsureDB()

    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    local refreshFrame = _G.MSUF_RefreshCastbarFrame
    if type(refreshFrame) == "function" then
        refreshFrame(frame, "boss", general)
    elseif type(_G.MSUF_ApplyCastbarDetailLayout) == "function" then
        _G.MSUF_ApplyCastbarDetailLayout(frame, "boss", general)
    end
    if type(_G.MSUF_ApplyCastbarSparkVisual) == "function" then
        _G.MSUF_ApplyCastbarSparkVisual(frame, general)
    end
end

--- Anchor/size pass for one boss castbar. This can be called from settings,
--- login, encounter events, and preview sync, so it only mutates when values
--- actually changed.
local function UpdateBossCastbarAnchorBase(frame)
    if not frame then
        return false
    end

    EnsureDB()

    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    local unit = frame.unit or "boss1"
    local bossIndex = tonumber(tostring(unit):match("boss(%d+)")) or 1

    local desiredWidth
    local desiredHeight
    local preserveWidth
    if type(_G.MSUF_GetCastbarDesiredSize) == "function" then
        desiredWidth, desiredHeight, preserveWidth = _G.MSUF_GetCastbarDesiredSize(unit, general, frame, 240, 12)
    else
        desiredWidth = tonumber(general.bossCastbarWidth)
        desiredHeight = tonumber(general.bossCastbarHeight)
    end

    if desiredWidth and not preserveWidth then
        desiredWidth = Snap(frame, desiredWidth)
    end
    if desiredHeight then
        desiredHeight = Snap(frame, desiredHeight)
    end

    local changed = false
    local sizeChanged = false
    local heightChanged = SetHeightIfChanged(frame, desiredHeight or frame:GetHeight() or 18)
    changed = heightChanged or changed
    sizeChanged = heightChanged or sizeChanged

    local offsetX = Snap(frame, tonumber(general.bossCastbarOffsetX) or 0)
    local offsetY = Snap(frame, tonumber(general.bossCastbarOffsetY) or 0)

    if general.bossCastbarDetached == true then
        local layoutX = 0
        local layoutY = -((bossIndex - 1) * 34)

        if type(_G.MSUF_GetBossLayoutDelta) == "function" then
            local bossDB = (_G.MSUF_DB and _G.MSUF_DB.boss) or {}
            layoutX, layoutY = _G.MSUF_GetBossLayoutDelta(bossIndex, bossDB)
            layoutX = tonumber(layoutX) or 0
            layoutY = tonumber(layoutY) or layoutY
        end

        changed = SetPointIfChanged(frame, "CENTER", UIParent, "CENTER", offsetX + layoutX, offsetY + (tonumber(layoutY) or 0))
            or changed
        local widthChanged = SetWidthIfChanged(frame, desiredWidth or frame:GetWidth() or 240)
        changed = widthChanged or changed
        sizeChanged = widthChanged or sizeChanged
    else
        local unitFrame = _G["MSUF_" .. unit]
        if unitFrame and unitFrame.GetWidth then
            local source = (type(_G.MSUF_GetCastbarUnitframeWidthSource) == "function"
                and _G.MSUF_GetCastbarUnitframeWidthSource(unit)) or unitFrame
            local autoX = 0
            if type(_G.MSUF_GetCastbarAutoAnchorOffsetX) == "function" then
                autoX = _G.MSUF_GetCastbarAutoAnchorOffsetX(general, unit, frame)
            end
            local bottomInset = 0
            if type(_G.MSUF_GetCastbarUnitframeBottomInset) == "function" then
                bottomInset = _G.MSUF_GetCastbarUnitframeBottomInset(unit, frame)
            end
            local gap = 3
            if type(_G.MSUF_GetPhysicalPixelSize) == "function" then
                gap = _G.MSUF_GetPhysicalPixelSize(frame, 3)
            else
                gap = Snap(frame, gap)
            end
            changed = SetPointIfChanged(frame, "TOPLEFT", source, "BOTTOMLEFT",
                offsetX + autoX, offsetY - bottomInset - gap, true) or changed

            local width = desiredWidth
            if not width and source and source.GetWidth then
                width = source:GetWidth()
                if width and width > 0 and source ~= frame then
                    local sourceScale = (source.GetEffectiveScale and source:GetEffectiveScale()) or 1
                    local frameScale = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
                    if frameScale <= 0 then frameScale = 1 end
                    width = width * sourceScale / frameScale
                end
            end
            local widthChanged = SetWidthIfChanged(frame, width or unitFrame:GetWidth() or 240)
            changed = widthChanged or changed
            sizeChanged = widthChanged or sizeChanged
        else
            changed = SetPointIfChanged(
                frame,
                "TOPRIGHT",
                UIParent,
                "TOPRIGHT",
                -420 + offsetX,
                (-220 + offsetY) - ((bossIndex - 1) * 34)
            ) or changed
            local widthChanged = SetWidthIfChanged(frame, desiredWidth or frame:GetWidth() or 240)
            changed = widthChanged or changed
            sizeChanged = widthChanged or sizeChanged
        end
    end

    return changed, sizeChanged
end

local function UpdateBossCastbarAnchor(frame, forceLayout)
    local changed, sizeChanged = UpdateBossCastbarAnchorBase(frame)
    -- Moving between fallback UIParent and the live boss unitframe changes only
    -- the external anchor. Internal icon/text/spark geometry depends on size,
    -- not position, so do not rebuild every region on a pure reanchor.
    if sizeChanged or forceLayout then ApplyBossCastbarLayout(frame) end
    return changed
end

local function ClearBossCastbarFontAttempt(frame)
    local clear = _G.MSUF_ClearFontStringApplyCaches
    local regions = { frame and frame.castText, frame and frame.timeText, frame and frame.castTargetText }
    for index = 1, #regions do
        local fontString = regions[index]
        if fontString then
            if type(clear) == "function" then clear(fontString) end
            fontString._msufCastbarFontKey = nil
            fontString._msufCastbarFontEpoch = nil
            fontString._msufCastbarFontReady = nil
        end
    end
end

--- The generic driver can receive the first spellcast event long after the
--- encounter lifecycle pass. Validate the boss-only geometry and detail-font
--- generation immediately before that cast becomes visible. The common case
--- remains comparison-only; a full layout is performed only for stale state.
local function PrepareBossCastbarForCast(frame)
    if not frame then return false end
    local _, sizeChanged = UpdateBossCastbarAnchorBase(frame)
    local fontEpoch = tonumber(_G.MSUF_FontApplyEpoch) or 0
    local visualRevision = tonumber(_G.MSUF__castbarStyleGlobalRev) or 1
    local layoutStale = frame._msufCastbarDetailLayoutUnit ~= "boss"
        or frame._msufCastbarDetailLayoutFontEpoch ~= fontEpoch
        or frame._msufCastbarDetailLayoutVisualRev ~= visualRevision
    local retryFont = frame._msufCastbarDetailFontsReady == false
        and frame._msufBossCastbarFontRetryEpoch ~= fontEpoch
    if retryFont then
        frame._msufBossCastbarFontRetryEpoch = fontEpoch
        ClearBossCastbarFontAttempt(frame)
    end
    if sizeChanged or layoutStale or retryFont then
        ApplyBossCastbarLayout(frame)
        return true
    end
    return false
end

local function BossUnitUnavailable(unit)
    if not unit or unit == "" then
        return true
    end

    if UnitExists and not UnitExists(unit) then
        return true
    end

    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
        return true
    end

    return UnitIsUnconscious and UnitIsUnconscious(unit) or false
end

local function StopBossCastbar(frame)
    if not frame then
        return
    end

    -- Boss lifecycle teardown is terminal. It must override the short
    -- interrupted-feedback hold or Runtime:Stop intentionally keeps the bar
    -- visible while invalidating that hold's delayed hide callback.
    frame.interrupted = nil

    if type(_G.MSUF_CB_ResetStateOnStop) == "function" then
        _G.MSUF_CB_ResetStateOnStop(frame, "STOPPED")
    elseif frame.Hide then
        frame:Hide()
    end
end

local function BuildBossCastState(frame)
    local unit = frame and frame.unit
    local getEngine = _G.MSUF_GetCastbarEngine
    local engine = type(getEngine) == "function" and getEngine() or nil
    if engine and type(engine.Invalidate) == "function" then
        engine:Invalidate(unit)
    end
    if engine and type(engine.BuildState) == "function" then
        return engine:BuildState(unit, frame), true
    end
    return nil, false
end

local function RefreshBossCastbarFromUnit(frame, refreshLayout)
    if not frame then return false end
    if BossUnitUnavailable(frame.unit) then
        StopBossCastbar(frame)
        return false
    end

    -- A roster/targetability refresh owns the current boss token. Release any
    -- stale interrupt hold before Cast() rebuilds (or clears) that unit state.
    if frame.interrupted then StopBossCastbar(frame) end

    -- Probe the shared same-frame cast-state cache before touching geometry.
    -- Boss units can exist while no gameplay cast/channel is active; in that
    -- dominant lifecycle case, terminal cleanup is sufficient and avoids a
    -- complete anchor/layout/driver pass for an invisible bar.
    local state, stateKnown = BuildBossCastState(frame)
    if stateKnown and not (state and state.active == true) then
        StopBossCastbar(frame)
        return false
    end

    -- Encounter/lifecycle events need current geometry for a real active cast,
    -- but a full visual refresh is only necessary when that geometry changed.
    -- Visual settings already own their explicit force-layout path.
    if refreshLayout then frame:UpdateAnchor(false) end
    if frame.Cast then frame:Cast(state) end
    return true
end

--- Boss castbars listen to the same spellcast events as target/focus plus
--- encounter lifecycle events that reveal or invalidate boss units.
local function SetBossEventsRegistered(frame, enabled)
    if not frame then
        return
    end

    if enabled then
        if frame._msufBossEventsRegistered then
            return
        end

        for index = 1, #CAST_EVENTS do
            frame:RegisterUnitEvent(CAST_EVENTS[index], frame.unit)
        end

        -- UNIT_HEALTH is attached only for active casts by the generic driver.
        -- UNIT_FLAGS stays sparse/persistent so delayed death and interrupted
        -- feedback states still terminate without a ticker or combat-log hook.
        frame:RegisterUnitEvent("UNIT_FLAGS", frame.unit)
        frame._msufDriverEventsRegistered = true
        frame._msufBossEventsRegistered = true
        frame._msufCastLifecycleOwned = true
        return
    end

    frame:UnregisterAllEvents()
    frame._msufDriverEventsRegistered = nil
    frame._msufBossEventsRegistered = nil
    frame._msufBossHealthEventRegistered = nil
    frame._msufCastLifecycleOwned = nil
end

--- Create or reuse one boss castbar frame. The generic driver handles most cast
--- behavior; this hook only adds boss lifecycle reactions.
local function EnsureBossCastbar(index, enabled)
    local unit = "boss" .. index
    local name = "MSUF_BossCastbar" .. index

    local frame = _G[name]
    if not frame then
        local createCastbar = _G.MSUF_CreateCastBar
        if type(createCastbar) ~= "function" then
            return nil
        end

        frame = createCastbar(name, unit)
    end

    if not frame then
        return nil
    end

    frame.unit = unit
    frame._msufBarKey = unit
    frame._msufIsBossCastbar = true
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(50 + index)
    frame.ApplyLayout = ApplyBossCastbarLayout
    frame.PrepareForCast = PrepareBossCastbarForCast
    frame.UpdateAnchor = UpdateBossCastbarAnchor
    frame.UpdateAnchorBase = UpdateBossCastbarAnchorBase

    if not frame._msufBossHooked then
        frame._msufBossHooked = true
        frame:HookScript("OnEvent", function(eventFrame, event, eventUnit)
            -- The generic driver owns active-only UNIT_HEALTH. Keep its hot
            -- path out of the boss lifecycle branch chain below.
            if event == "UNIT_HEALTH" then return end

            if event == "UNIT_FLAGS"
                and eventFrame:IsShown()
                and BossUnitUnavailable(eventFrame.unit)
            then
                StopBossCastbar(eventFrame)
            end
        end)
    end

    SetBossEventsRegistered(frame, enabled == true)
    frame:UpdateAnchor(true)
    frame:Hide()

    return frame
end

local function EnsureBossCastbars()
    if _G.MSUF_BossCastbars then
        return _G.MSUF_BossCastbars, false
    end

    if not BossCastbarsEnabled() then
        return nil, false
    end

    local bossCastbars = {}
    ExportPublic("MSUF_BossCastbars", bossCastbars)

    for index = 1, MAX_BOSS_FRAMES do
        local frame = EnsureBossCastbar(index, true)
        bossCastbars[index] = frame

        if frame and UnitExists(frame.unit) and frame.Cast then
            frame:Cast()
        end
    end

    return bossCastbars, true
end

local bossPoolRefreshQueued = false
local bossPoolRefreshGeneration = 0
local bossPoolRefreshPendingGeneration

local function FlushBossPoolLifecycle()
    bossPoolRefreshQueued = false
    if bossPoolRefreshPendingGeneration ~= bossPoolRefreshGeneration then return end
    bossPoolRefreshPendingGeneration = nil
    if not BossCastbarsEnabled() then return end

    local bossCastbars = _G.MSUF_BossCastbars
    if not bossCastbars then return end
    for index = 1, #bossCastbars do
        RefreshBossCastbarFromUnit(bossCastbars[index], true)
    end
end

local function QueueBossPoolLifecycle()
    bossPoolRefreshPendingGeneration = bossPoolRefreshGeneration
    if bossPoolRefreshQueued then return end
    bossPoolRefreshQueued = true

    local scheduleOnce = _G.MSUF_ScheduleOnce
    if type(scheduleOnce) == "function" then
        scheduleOnce("MSUF_BOSS_POOL_LIFECYCLE", FlushBossPoolLifecycle)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, FlushBossPoolLifecycle)
    else
        FlushBossPoolLifecycle()
    end
end

local function CancelBossPoolLifecycle()
    bossPoolRefreshGeneration = bossPoolRefreshGeneration + 1
    bossPoolRefreshPendingGeneration = nil
end

local function HandleBossPoolLifecycle(event, eventUnit)
    local bossCastbars = _G.MSUF_BossCastbars
    local created
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        bossCastbars, created = EnsureBossCastbars()
        if not bossCastbars or created == true then return end
    elseif not bossCastbars then
        return
    end

    if event == "ENCOUNTER_END" then
        -- A queued engage/world refresh must never resurrect a cast after the
        -- terminal encounter event. The stable callback remains harmless in
        -- the scheduler and rejects this older generation when it runs.
        CancelBossPoolLifecycle()
        for index = 1, #bossCastbars do
            StopBossCastbar(bossCastbars[index])
        end
        return
    end

    if event == "UNIT_TARGETABLE_CHANGED" then
        if type(eventUnit) ~= "string" then return end
        local index = tonumber(eventUnit:match("^boss(%d+)$"))
        local frame = index and bossCastbars[index]
        if frame and frame.unit == eventUnit then
            RefreshBossCastbarFromUnit(frame, false)
        end
        return
    end

    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD"
        or event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" or event == "ENCOUNTER_START" then
        -- These lifecycle notifications commonly arrive as one same-frame
        -- burst. Collapse the whole burst into one next-frame pool pass so five
        -- boss bars are refreshed once, not once per overlapping notification.
        -- Targetability stays immediate and unit-specific; ENCOUNTER_END stays
        -- immediate and invalidates this queued work.
        QueueBossPoolLifecycle()
    end
end

local function RefreshBossPreviewIfAllowed()
    if not InCombat() and type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
        _G.MSUF_UpdateBossCastbarPreview()
    end
end

local function ApplyBossCastbarPositionSetting(forceLayout, skipPreviewRefresh, geometryOnly)
    local bossCastbars = _G.MSUF_BossCastbars or EnsureBossCastbars()
    if not bossCastbars then
        return
    end

    for index = 1, #bossCastbars do
        local frame = bossCastbars[index]
        if frame then
            if geometryOnly and frame.UpdateAnchorBase then
                frame:UpdateAnchorBase()
            else
                frame:UpdateAnchor(forceLayout ~= false)
            end
        end
    end

    if not skipPreviewRefresh then RefreshBossPreviewIfAllowed() end
end

--- Public menu/profile entry. Keep backend flags, event subscriptions, live
--- frame state, visuals, and previews synchronized from this one path.
local function SetBossCastbarsEnabled(enabled)
    EnsureDB()

    enabled = enabled and true or false

    local general = _G.MSUF_DB and _G.MSUF_DB.general
    if general then
        local setBackend = _G.MSUF_SetCastbarBackend
        if type(setBackend) == "function" then
            setBackend("boss", enabled and "MSUF" or "HIDE", general)
        else
            general.enableBossCastbar = enabled
        end
    end

    local bossCastbars = enabled and (_G.MSUF_BossCastbars or EnsureBossCastbars()) or _G.MSUF_BossCastbars
    if not bossCastbars then
        return
    end

    for index = 1, #bossCastbars do
        local frame = bossCastbars[index]
        if frame then
            SetBossEventsRegistered(frame, enabled)

            if enabled then
                if frame.UpdateAnchorBase then frame:UpdateAnchorBase() else frame:UpdateAnchor(true) end
                if UnitExists(frame.unit) and frame.Cast then
                    frame:Cast()
                end
            else
                StopBossCastbar(frame)
            end
        end
    end

    local refreshed
    if type(_G.MSUF_ApplyCastbarVisualsForUnit) == "function" then
        _G.MSUF_ApplyCastbarVisualsForUnit("boss")
        refreshed = true
    elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals("boss")
        refreshed = true
    end

    if not refreshed then RefreshBossPreviewIfAllowed() end
end

local function ApplyBossCastbarsEnabled()
    local enabled = BossCastbarsEnabled()
    SetBossCastbarsEnabled(enabled)
    if _G.MSUF_BossCastbars_SyncLifecycle then _G.MSUF_BossCastbars_SyncLifecycle(enabled) end
end

ExportPublic("MSUF_ApplyBossCastbarPositionSetting", ApplyBossCastbarPositionSetting)
ExportPublic("MSUF_ApplyBossCastbarsEnabled", ApplyBossCastbarsEnabled)
ExportPublic("MSUF_BossCastbar_Stop", StopBossCastbar)

local bossLifecycleFrame
local function SyncBossLifecycle(enabled)
    enabled = enabled == true
    if type(_G.MSUF_EventBus_Unregister) == "function" then
        _G.MSUF_EventBus_Unregister("PLAYER_LOGIN", "MSUF_BOSS_CASTBARS_LOGIN")
        _G.MSUF_EventBus_Unregister("PLAYER_ENTERING_WORLD", "MSUF_BOSS_CASTBARS_WORLD")
        _G.MSUF_EventBus_Unregister("INSTANCE_ENCOUNTER_ENGAGE_UNIT", "MSUF_BOSS_CASTBARS_ENGAGE")
        _G.MSUF_EventBus_Unregister("ENCOUNTER_START", "MSUF_BOSS_CASTBARS_START")
        _G.MSUF_EventBus_Unregister("ENCOUNTER_END", "MSUF_BOSS_CASTBARS_END")
        _G.MSUF_EventBus_Unregister("UNIT_TARGETABLE_CHANGED", "MSUF_BOSS_CASTBARS_TARGETABLE")
    end
    if bossLifecycleFrame then bossLifecycleFrame:UnregisterAllEvents() end
    if not enabled then
        CancelBossPoolLifecycle()
        return false
    end
    if type(_G.MSUF_EventBus_Register) == "function" then
        _G.MSUF_EventBus_Register("PLAYER_LOGIN", "MSUF_BOSS_CASTBARS_LOGIN", HandleBossPoolLifecycle, nil, true)
        _G.MSUF_EventBus_Register("PLAYER_ENTERING_WORLD", "MSUF_BOSS_CASTBARS_WORLD", HandleBossPoolLifecycle)
        _G.MSUF_EventBus_Register("INSTANCE_ENCOUNTER_ENGAGE_UNIT", "MSUF_BOSS_CASTBARS_ENGAGE", HandleBossPoolLifecycle)
        _G.MSUF_EventBus_Register("ENCOUNTER_START", "MSUF_BOSS_CASTBARS_START", HandleBossPoolLifecycle)
        _G.MSUF_EventBus_Register("ENCOUNTER_END", "MSUF_BOSS_CASTBARS_END", HandleBossPoolLifecycle)
        _G.MSUF_EventBus_Register("UNIT_TARGETABLE_CHANGED", "MSUF_BOSS_CASTBARS_TARGETABLE", HandleBossPoolLifecycle)
    else
        bossLifecycleFrame = bossLifecycleFrame or CreateFrame("Frame")
        bossLifecycleFrame:SetScript("OnEvent", function(_, event, ...)
            HandleBossPoolLifecycle(event, ...)
        end)
        bossLifecycleFrame:RegisterEvent("PLAYER_LOGIN")
        bossLifecycleFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        bossLifecycleFrame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        bossLifecycleFrame:RegisterEvent("ENCOUNTER_START")
        bossLifecycleFrame:RegisterEvent("ENCOUNTER_END")
        bossLifecycleFrame:RegisterEvent("UNIT_TARGETABLE_CHANGED")
    end
    return true
end
ExportPublic("MSUF_BossCastbars_SyncLifecycle", SyncBossLifecycle)
SyncBossLifecycle(BossCastbarsEnabled())
