--- Castbars/MSUF_ArenaCastbars.lua
--- Live arena castbar pool and arena-unit event driver.
---
--- Arena castbars reuse the generic castbar frame/runtime stack, but they need
--- their own frame pool, arena-specific anchoring, opponent lifecycle handling
--- (ARENA_OPPONENT_UPDATE / PVP_MATCH_STATE_CHANGED instead of encounter
--- events), and menu-facing enable/position globals. Mirrors MSUF_BossCastbars.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local MAX_ARENA_FRAMES = 3
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

local function ArenaCastbarsEnabled()
    EnsureDB()

    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local shouldUseMSUF = _G.MSUF_ShouldUseMSUFCastbar

    if type(shouldUseMSUF) == "function" then
        return shouldUseMSUF("arena", general) == true
    end

    return (not general) or general.enableArenaCastbar ~= false
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

--- Applies only internal arena castbar region layout. Positioning relative to
--- arena unit frames or UIParent is handled by UpdateArenaCastbarAnchor.
local function ApplyArenaCastbarLayout(frame)
    if not (frame and frame.statusBar) then
        return
    end

    EnsureDB()

    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    local refreshFrame = _G.MSUF_RefreshCastbarFrame
    if type(refreshFrame) == "function" then
        refreshFrame(frame, "arena", general)
    elseif type(_G.MSUF_ApplyCastbarDetailLayout) == "function" then
        _G.MSUF_ApplyCastbarDetailLayout(frame, "arena", general)
    end
    if type(_G.MSUF_ApplyCastbarSparkVisual) == "function" then
        _G.MSUF_ApplyCastbarSparkVisual(frame, general)
    end
end

--- Anchor/size pass for one arena castbar. Called from settings, login,
--- opponent lifecycle events, and preview sync; mutates only on real changes.
local function UpdateArenaCastbarAnchorBase(frame)
    if not frame then
        return false
    end

    EnsureDB()

    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    local unit = frame.unit or "arena1"
    local arenaIndex = tonumber(tostring(unit):match("arena(%d+)")) or 1

    local desiredWidth
    local desiredHeight
    local preserveWidth
    if type(_G.MSUF_GetCastbarDesiredSize) == "function" then
        desiredWidth, desiredHeight, preserveWidth = _G.MSUF_GetCastbarDesiredSize(unit, general, frame, 240, 12)
    else
        desiredWidth = tonumber(general.arenaCastbarWidth)
        desiredHeight = tonumber(general.arenaCastbarHeight)
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

    local offsetX = Snap(frame, tonumber(general.arenaCastbarOffsetX) or 0)
    local offsetY = Snap(frame, tonumber(general.arenaCastbarOffsetY) or 0)

    if general.arenaCastbarDetached == true then
        local layoutX = 0
        local layoutY = -((arenaIndex - 1) * 34)

        if type(_G.MSUF_GetArenaLayoutDelta) == "function" then
            local arenaDB = (_G.MSUF_DB and _G.MSUF_DB.arena) or {}
            layoutX, layoutY = _G.MSUF_GetArenaLayoutDelta(arenaIndex, arenaDB)
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
                (-320 + offsetY) - ((arenaIndex - 1) * 34)
            ) or changed
            local widthChanged = SetWidthIfChanged(frame, desiredWidth or frame:GetWidth() or 240)
            changed = widthChanged or changed
            sizeChanged = widthChanged or sizeChanged
        end
    end

    return changed, sizeChanged
end

local function UpdateArenaCastbarAnchor(frame, forceLayout)
    local changed, sizeChanged = UpdateArenaCastbarAnchorBase(frame)
    -- Moving between fallback UIParent and the live arena unitframe changes
    -- only the external anchor; internal geometry depends on size alone.
    if sizeChanged or forceLayout then ApplyArenaCastbarLayout(frame) end
    return changed
end

local function ClearArenaCastbarFontAttempt(frame)
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

--- Validate arena-only geometry and detail-font generation right before a cast
--- becomes visible; comparison-only in the common case.
local function PrepareArenaCastbarForCast(frame)
    if not frame then return false end
    local _, sizeChanged = UpdateArenaCastbarAnchorBase(frame)
    local fontEpoch = tonumber(_G.MSUF_FontApplyEpoch) or 0
    local visualRevision = tonumber(_G.MSUF__castbarStyleGlobalRev) or 1
    local layoutStale = frame._msufCastbarDetailLayoutUnit ~= "arena"
        or frame._msufCastbarDetailLayoutFontEpoch ~= fontEpoch
        or frame._msufCastbarDetailLayoutVisualRev ~= visualRevision
    local retryFont = frame._msufCastbarDetailFontsReady == false
        and frame._msufArenaCastbarFontRetryEpoch ~= fontEpoch
    if retryFont then
        frame._msufArenaCastbarFontRetryEpoch = fontEpoch
        ClearArenaCastbarFontAttempt(frame)
    end
    if sizeChanged or layoutStale or retryFont then
        ApplyArenaCastbarLayout(frame)
        return true
    end
    return false
end

local function ArenaUnitUnavailable(unit)
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

local function StopArenaCastbar(frame)
    if not frame then
        return
    end

    -- Arena lifecycle teardown is terminal (round end, opponent destroyed).
    frame.interrupted = nil

    if type(_G.MSUF_CB_ResetStateOnStop) == "function" then
        _G.MSUF_CB_ResetStateOnStop(frame, "STOPPED")
    elseif frame.Hide then
        frame:Hide()
    end
end

local function BuildArenaCastState(frame)
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

local function RefreshArenaCastbarFromUnit(frame, refreshLayout)
    if not frame then return false end
    if ArenaUnitUnavailable(frame.unit) then
        StopArenaCastbar(frame)
        return false
    end

    -- An opponent lifecycle refresh owns the current arena token. Release any
    -- stale interrupt hold before Cast() rebuilds (or clears) that unit state.
    if frame.interrupted then StopArenaCastbar(frame) end

    local state, stateKnown = BuildArenaCastState(frame)
    if stateKnown and not (state and state.active == true) then
        StopArenaCastbar(frame)
        return false
    end

    if refreshLayout then frame:UpdateAnchor(false) end
    if frame.Cast then frame:Cast(state) end
    return true
end

--- Arena castbars listen to the same spellcast events as target/focus plus
--- opponent lifecycle events that reveal or invalidate arena units.
local function SetArenaEventsRegistered(frame, enabled)
    if not frame then
        return
    end

    if enabled then
        if frame._msufArenaEventsRegistered then
            return
        end

        for index = 1, #CAST_EVENTS do
            frame:RegisterUnitEvent(CAST_EVENTS[index], frame.unit)
        end

        -- UNIT_FLAGS stays sparse/persistent so delayed death and interrupted
        -- feedback states still terminate without a ticker.
        frame:RegisterUnitEvent("UNIT_FLAGS", frame.unit)
        frame._msufDriverEventsRegistered = true
        frame._msufArenaEventsRegistered = true
        frame._msufCastLifecycleOwned = true
        return
    end

    frame:UnregisterAllEvents()
    frame._msufDriverEventsRegistered = nil
    frame._msufArenaEventsRegistered = nil
    frame._msufCastLifecycleOwned = nil
end

--- Create or reuse one arena castbar frame. The generic driver handles most
--- cast behavior; this hook only adds arena lifecycle reactions.
local function EnsureArenaCastbar(index, enabled)
    local unit = "arena" .. index
    local name = "MSUF_ArenaCastbar" .. index

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
    frame._msufIsArenaCastbar = true
    frame._msufArenaIndex = index
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(56 + index)
    frame.ApplyLayout = ApplyArenaCastbarLayout
    frame.PrepareForCast = PrepareArenaCastbarForCast
    frame.UpdateAnchor = UpdateArenaCastbarAnchor
    frame.UpdateAnchorBase = UpdateArenaCastbarAnchorBase

    if not frame._msufArenaHooked then
        frame._msufArenaHooked = true
        frame:HookScript("OnEvent", function(eventFrame, event)
            if event == "UNIT_HEALTH" then return end

            if event == "UNIT_FLAGS"
                and eventFrame:IsShown()
                and ArenaUnitUnavailable(eventFrame.unit)
            then
                StopArenaCastbar(eventFrame)
            end
        end)
    end

    SetArenaEventsRegistered(frame, enabled == true)
    frame:UpdateAnchor(true)
    frame:Hide()

    return frame
end

local function EnsureArenaCastbars()
    if _G.MSUF_ArenaCastbars then
        return _G.MSUF_ArenaCastbars, false
    end

    if not ArenaCastbarsEnabled() then
        return nil, false
    end

    local arenaCastbars = {}
    ExportPublic("MSUF_ArenaCastbars", arenaCastbars)

    for index = 1, MAX_ARENA_FRAMES do
        local frame = EnsureArenaCastbar(index, true)
        arenaCastbars[index] = frame

        if frame and UnitExists(frame.unit) and frame.Cast then
            frame:Cast()
        end
    end

    return arenaCastbars, true
end

local arenaPoolRefreshQueued = false
local arenaPoolRefreshGeneration = 0
local arenaPoolRefreshPendingGeneration

local function FlushArenaPoolLifecycle()
    arenaPoolRefreshQueued = false
    if arenaPoolRefreshPendingGeneration ~= arenaPoolRefreshGeneration then return end
    arenaPoolRefreshPendingGeneration = nil
    if not ArenaCastbarsEnabled() then return end

    local arenaCastbars = _G.MSUF_ArenaCastbars
    if not arenaCastbars then return end
    for index = 1, #arenaCastbars do
        RefreshArenaCastbarFromUnit(arenaCastbars[index], true)
    end
end

local function QueueArenaPoolLifecycle()
    arenaPoolRefreshPendingGeneration = arenaPoolRefreshGeneration
    if arenaPoolRefreshQueued then return end
    arenaPoolRefreshQueued = true

    local scheduleOnce = _G.MSUF_ScheduleOnce
    if type(scheduleOnce) == "function" then
        scheduleOnce("MSUF_ARENA_POOL_LIFECYCLE", FlushArenaPoolLifecycle)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, FlushArenaPoolLifecycle)
    else
        FlushArenaPoolLifecycle()
    end
end

local function CancelArenaPoolLifecycle()
    arenaPoolRefreshGeneration = arenaPoolRefreshGeneration + 1
    arenaPoolRefreshPendingGeneration = nil
end

local function MatchIsComplete()
    local isComplete = _G.C_PvP and _G.C_PvP.IsMatchComplete
    return type(isComplete) == "function" and isComplete() == true
end

local function HandleArenaPoolLifecycle(event, eventUnit)
    local arenaCastbars = _G.MSUF_ArenaCastbars
    local created
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        arenaCastbars, created = EnsureArenaCastbars()
        if not arenaCastbars or created == true then return end
    elseif not arenaCastbars then
        return
    end

    if event == "PVP_MATCH_STATE_CHANGED" and MatchIsComplete() then
        -- Terminal: a queued opponent refresh must never resurrect a cast
        -- after the match has completed.
        CancelArenaPoolLifecycle()
        for index = 1, #arenaCastbars do
            StopArenaCastbar(arenaCastbars[index])
        end
        return
    end

    if event == "ARENA_OPPONENT_UPDATE" then
        -- Per-unit payload: seen/unseen/destroyed/cleared and Solo Shuffle
        -- round rebinds. Refresh only the owning bar immediately. A secret
        -- token must not reach string.match - fall through to the queued
        -- pool pass instead of erroring once per burst event.
        local issecret = _G.issecretvalue
        if type(eventUnit) == "string" and (not issecret or issecret(eventUnit) ~= true) then
            local index = tonumber(eventUnit:match("^arena(%d+)$"))
            local frame = index and arenaCastbars[index]
            if frame and frame.unit == eventUnit then
                RefreshArenaCastbarFromUnit(frame, false)
                return
            end
        end
        QueueArenaPoolLifecycle()
        return
    end

    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD"
        or event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS"
        or event == "PVP_MATCH_STATE_CHANGED" then
        -- These lifecycle notifications commonly arrive as one same-frame
        -- burst. Collapse the burst into one next-frame pool pass.
        QueueArenaPoolLifecycle()
    end
end

local function RefreshArenaPreviewIfAllowed()
    if not InCombat() and type(_G.MSUF_UpdateArenaCastbarPreview) == "function" then
        _G.MSUF_UpdateArenaCastbarPreview()
    end
end

local function ApplyArenaCastbarPositionSetting(forceLayout, skipPreviewRefresh, geometryOnly)
    local arenaCastbars = _G.MSUF_ArenaCastbars or EnsureArenaCastbars()
    if not arenaCastbars then
        return
    end

    for index = 1, #arenaCastbars do
        local frame = arenaCastbars[index]
        if frame then
            if geometryOnly and frame.UpdateAnchorBase then
                frame:UpdateAnchorBase()
            else
                frame:UpdateAnchor(forceLayout ~= false)
            end
        end
    end

    if not skipPreviewRefresh then RefreshArenaPreviewIfAllowed() end
end

--- Public menu/profile entry. Keep backend flags, event subscriptions, live
--- frame state, visuals, and previews synchronized from this one path.
local function SetArenaCastbarsEnabled(enabled)
    EnsureDB()

    enabled = enabled and true or false

    local general = _G.MSUF_DB and _G.MSUF_DB.general
    if general then
        local setBackend = _G.MSUF_SetCastbarBackend
        if type(setBackend) == "function" then
            setBackend("arena", enabled and "MSUF" or "HIDE", general)
        else
            general.enableArenaCastbar = enabled
        end
    end

    local arenaCastbars = enabled and (_G.MSUF_ArenaCastbars or EnsureArenaCastbars()) or _G.MSUF_ArenaCastbars
    if not arenaCastbars then
        return
    end

    for index = 1, #arenaCastbars do
        local frame = arenaCastbars[index]
        if frame then
            SetArenaEventsRegistered(frame, enabled)

            if enabled then
                if frame.UpdateAnchorBase then frame:UpdateAnchorBase() else frame:UpdateAnchor(true) end
                if UnitExists(frame.unit) and frame.Cast then
                    frame:Cast()
                end
            else
                StopArenaCastbar(frame)
            end
        end
    end

    local refreshed
    if type(_G.MSUF_ApplyCastbarVisualsForUnit) == "function" then
        _G.MSUF_ApplyCastbarVisualsForUnit("arena")
        refreshed = true
    elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals("arena")
        refreshed = true
    end

    if not refreshed then RefreshArenaPreviewIfAllowed() end
end

local function ApplyArenaCastbarsEnabled()
    local enabled = ArenaCastbarsEnabled()
    SetArenaCastbarsEnabled(enabled)
    if _G.MSUF_ArenaCastbars_SyncLifecycle then _G.MSUF_ArenaCastbars_SyncLifecycle(enabled) end
end

ExportPublic("MSUF_ApplyArenaCastbarPositionSetting", ApplyArenaCastbarPositionSetting)
ExportPublic("MSUF_ApplyArenaCastbarsEnabled", ApplyArenaCastbarsEnabled)
ExportPublic("MSUF_ArenaCastbar_Stop", StopArenaCastbar)

local arenaLifecycleFrame
local function SyncArenaLifecycle(enabled)
    enabled = enabled == true
    if type(_G.MSUF_EventBus_Unregister) == "function" then
        _G.MSUF_EventBus_Unregister("PLAYER_LOGIN", "MSUF_ARENA_CASTBARS_LOGIN")
        _G.MSUF_EventBus_Unregister("PLAYER_ENTERING_WORLD", "MSUF_ARENA_CASTBARS_WORLD")
        _G.MSUF_EventBus_Unregister("ARENA_OPPONENT_UPDATE", "MSUF_ARENA_CASTBARS_OPPONENT")
        _G.MSUF_EventBus_Unregister("ARENA_PREP_OPPONENT_SPECIALIZATIONS", "MSUF_ARENA_CASTBARS_PREP")
        _G.MSUF_EventBus_Unregister("PVP_MATCH_STATE_CHANGED", "MSUF_ARENA_CASTBARS_MATCH")
    end
    if arenaLifecycleFrame then arenaLifecycleFrame:UnregisterAllEvents() end
    if not enabled then
        CancelArenaPoolLifecycle()
        return false
    end
    if type(_G.MSUF_EventBus_Register) == "function" then
        _G.MSUF_EventBus_Register("PLAYER_LOGIN", "MSUF_ARENA_CASTBARS_LOGIN", HandleArenaPoolLifecycle, nil, true)
        _G.MSUF_EventBus_Register("PLAYER_ENTERING_WORLD", "MSUF_ARENA_CASTBARS_WORLD", HandleArenaPoolLifecycle)
        _G.MSUF_EventBus_Register("ARENA_OPPONENT_UPDATE", "MSUF_ARENA_CASTBARS_OPPONENT", HandleArenaPoolLifecycle)
        _G.MSUF_EventBus_Register("ARENA_PREP_OPPONENT_SPECIALIZATIONS", "MSUF_ARENA_CASTBARS_PREP", HandleArenaPoolLifecycle)
        _G.MSUF_EventBus_Register("PVP_MATCH_STATE_CHANGED", "MSUF_ARENA_CASTBARS_MATCH", HandleArenaPoolLifecycle)
    else
        arenaLifecycleFrame = arenaLifecycleFrame or CreateFrame("Frame")
        arenaLifecycleFrame:SetScript("OnEvent", function(_, event, ...)
            HandleArenaPoolLifecycle(event, ...)
        end)
        arenaLifecycleFrame:RegisterEvent("PLAYER_LOGIN")
        arenaLifecycleFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        arenaLifecycleFrame:RegisterEvent("ARENA_OPPONENT_UPDATE")
        arenaLifecycleFrame:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
        arenaLifecycleFrame:RegisterEvent("PVP_MATCH_STATE_CHANGED")
    end
    return true
end
ExportPublic("MSUF_ArenaCastbars_SyncLifecycle", SyncArenaLifecycle)
SyncArenaLifecycle(ArenaCastbarsEnabled())
