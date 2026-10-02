--- Castbars/MSUF_CastbarPools.lua
--- One parameterized module for the indexed hostile-unit castbar pools.
---
--- Boss and arena castbars reuse the generic castbar frame/runtime stack (the
--- driver owns every spellcast event). What a pool adds is the same for both
--- kinds: a frame pool, pool-specific anchoring, a unit lifecycle (encounter or
--- opponent events) and the menu-facing enable/position entry points. Each
--- kind is a descriptor (MSUF_BossCastbars.lua, MSUF_ArenaCastbars.lua) passed
--- to Pools.Define, which builds the kind's closures once; the per-cast paths
--- read only upvalues, never the descriptor.
---
--- Descriptor fields:
---   kind            castbar config/backend key ("boss", "arena")
---   unitPrefix      unit token prefix; unit = unitPrefix .. index
---   maxFrames       pool size (client fact, read once)
---   hasUnits        false where the client has no such units: the pool is never
---                   built and the profile keeps its backend
---   framePrefix     global frame name prefix (MSUF_BossCastbar1 ...)
---   poolGlobal      global pool table name (MSUF_BossCastbars)
---   kindFlag        frame flag other castbar modules read (_msufIsBossCastbar)
---   indexField      optional per-frame index field (_msufArenaIndex)
---   frameLevelBase  frame level of the bar at index 0 (bars are HIGH strata)
---   fallbackY       TOPRIGHT-of-UIParent y offset of bar 1 without a unit frame
---   enableKey       legacy general.<key> switch when no backend resolver exists
---   db              general keys: offsetX, offsetY, detached, width, height
---   layoutDelta     global name of the detached per-index layout resolver
---   previewUpdate   global name of the kind's preview refresh
---   lifecycle       { event, key, action = "pass"|"unit"|"terminal", prewarm,
---                     once, units, supported, terminalWhen, unitFallback }
---   scheduleKeys    { pass = "...", prewarm = "..." } (prewarm optional)
---   exports         global names: positionSetting, applyEnabled, stop,
---                   syncLifecycle
---
--- Returns the kind's module table (also MSUF.Castbars.Pools.kinds[kind]).

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

MSUF.Castbars = MSUF.Castbars or {}
local Pools = MSUF.Castbars.Pools or {}
MSUF.Castbars.Pools = Pools

local type = type
local tonumber = tonumber
local math_floor = math.floor
local math_abs = math.abs
local UnitExists = _G.UnitExists
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitIsUnconscious = _G.UnitIsUnconscious

-- Shared geometry of every pool. Kinds differ only in the fallback y offset
-- (descriptor.fallbackY) and their frame level band (descriptor.frameLevelBase).
-- Vertical pitch (px) between stacked bars when they are detached from, or
-- have no, unit frame to anchor to.
local ROW_PITCH = 34
-- TOPRIGHT-of-UIParent fallback x offset (px) of bar 1 when no unit frame
-- exists; the user offsets are added on top.
local FALLBACK_X = -420
-- Gap (px) between a unit frame's bottom edge and its castbar.
local UNITFRAME_GAP = 3
Pools.ROW_PITCH = ROW_PITCH
Pools.FALLBACK_X = FALLBACK_X
Pools.UNITFRAME_GAP = UNITFRAME_GAP

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

-- Regions whose castbar font caches are cleared together. Keyed by field name
-- so the per-frame clear allocates nothing.
local FONT_REGIONS = { "castText", "timeText", "castTargetText" }

local function EnsureDB()
    if type(_G.MSUF_EnsureDB) == "function" then
        _G.MSUF_EnsureDB()
    end
end

local function InCombat()
    return _G.MSUF_InCombat == true
        or ((_G.InCombatLockdown and _G.InCombatLockdown()) and true or false)
        or ((_G.UnitAffectingCombat and _G.UnitAffectingCombat("player")) and true or false)
end
Pools.InCombat = InCombat

local function SetPointIfChanged(frame, point, relativeTo, relativePoint, offsetX, offsetY, preserveOffsets)
    if not frame then
        return false
    end

    offsetX = tonumber(offsetX) or 0
    offsetY = tonumber(offsetY) or 0
    if not preserveOffsets then
        offsetX = math_floor(offsetX + 0.5)
        offsetY = math_floor(offsetY + 0.5)
    end

    local currentPoint, currentRelativeTo, currentRelativePoint, currentX, currentY = frame:GetPoint(1)
    if currentPoint == point
        and currentRelativeTo == relativeTo
        and currentRelativePoint == relativePoint
        and math_abs((tonumber(currentX) or 0) - offsetX) <= 0.01
        and math_abs((tonumber(currentY) or 0) - offsetY) <= 0.01
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

    if frame.GetWidth and math_abs((frame:GetWidth() or 0) - width) <= 0.01 then
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

    if frame.GetHeight and math_abs((frame:GetHeight() or 0) - height) <= 0.01 then
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
    return math_floor(value + 0.5)
end
Pools.Snap = Snap

local function ClearFontAttempt(frame)
    if not frame then return end
    local clear = _G.MSUF_ClearFontStringApplyCaches
    for index = 1, #FONT_REGIONS do
        local fontString = frame[FONT_REGIONS[index]]
        if fontString then
            if type(clear) == "function" then clear(fontString) end
            fontString._msufCastbarFontKey = nil
            fontString._msufCastbarFontEpoch = nil
            fontString._msufCastbarFontReady = nil
        end
    end
end

local function UnitUnavailable(unit)
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
Pools.UnitUnavailable = UnitUnavailable

--- Pool castbars listen to the same spellcast events as target/focus plus
--- UNIT_FLAGS. UNIT_HEALTH is attached only for active casts by the generic
--- driver (SetCastLifecycleActive); UNIT_FLAGS stays sparse/persistent so
--- delayed death and interrupted feedback states still terminate without a
--- ticker or combat-log hook.
local function SetEventsRegistered(frame, enabled)
    if not frame then
        return
    end

    if enabled then
        if frame._msufPoolEventsRegistered then
            return
        end

        for index = 1, #CAST_EVENTS do
            frame:RegisterUnitEvent(CAST_EVENTS[index], frame.unit)
        end
        frame:RegisterUnitEvent("UNIT_FLAGS", frame.unit)
        frame._msufDriverEventsRegistered = true
        frame._msufPoolEventsRegistered = true
        frame._msufCastLifecycleOwned = true
        return
    end

    frame:UnregisterAllEvents()
    frame._msufDriverEventsRegistered = nil
    frame._msufPoolEventsRegistered = nil
    frame._msufPoolHealthEventRegistered = nil
    frame._msufCastLifecycleOwned = nil
end

local function BuildCastState(frame)
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

--- Lifecycle teardown is terminal (encounter end, round end, opponent
--- destroyed). It must override the short interrupted-feedback hold, or
--- Runtime:Stop intentionally keeps the bar visible while invalidating that
--- hold's delayed hide callback.
local function StopCastbar(frame)
    if not frame then
        return
    end

    frame.interrupted = nil

    if type(_G.MSUF_CB_ResetStateOnStop) == "function" then
        _G.MSUF_CB_ResetStateOnStop(frame, "STOPPED")
    elseif frame.Hide then
        frame:Hide()
    end
end
Pools.Stop = StopCastbar

--- The kind's frame hook for the persistent UNIT_FLAGS: a bar whose unit died
--- or vanished stops. The generic driver owns active-only UNIT_HEALTH; keep its
--- hot path out of this branch chain.
local function OnPoolFrameEvent(frame, event)
    if event == "UNIT_HEALTH" then return end

    if event == "UNIT_FLAGS"
        and frame:IsShown()
        and UnitUnavailable(frame.unit)
    then
        StopCastbar(frame)
    end
end

local kinds = Pools.kinds or {}
Pools.kinds = kinds
--- Every defined kind, in definition order (boss, then arena).
local order = Pools.order or {}
Pools.order = order

--- Builds one pool from its descriptor. Called once per kind at load.
function Pools.Define(desc)
    local KIND = desc.kind
    local UNIT_PREFIX = desc.unitPrefix
    local MAX_FRAMES = desc.maxFrames
    local HAS_UNITS = desc.hasUnits ~= false
    local FRAME_PREFIX = desc.framePrefix
    local POOL_GLOBAL = desc.poolGlobal
    local KIND_FLAG = desc.kindFlag
    local INDEX_FIELD = desc.indexField
    local FRAME_LEVEL_BASE = desc.frameLevelBase
    local FALLBACK_Y = desc.fallbackY
    local ENABLE_KEY = desc.enableKey
    local DB_OFFSET_X = desc.db.offsetX
    local DB_OFFSET_Y = desc.db.offsetY
    local DB_DETACHED = desc.db.detached
    local DB_WIDTH = desc.db.width
    local DB_HEIGHT = desc.db.height
    local LAYOUT_DELTA = desc.layoutDelta
    local PREVIEW_UPDATE = desc.previewUpdate
    local SCHEDULE_PASS = desc.scheduleKeys.pass
    local SCHEDULE_PREWARM = desc.scheduleKeys.prewarm
    local EXPORTS = desc.exports

    local pool = { descriptor = desc, kind = KIND, maxFrames = MAX_FRAMES }
    kinds[KIND] = pool
    order[#order + 1] = pool

    local function Enabled()
        if not HAS_UNITS then return false end
        EnsureDB()

        local general = _G.MSUF_DB and _G.MSUF_DB.general
        local shouldUseMSUF = _G.MSUF_ShouldUseMSUFCastbar

        if type(shouldUseMSUF) == "function" then
            return shouldUseMSUF(KIND, general) == true
        end

        return (not general) or general[ENABLE_KEY] ~= false
    end
    pool.Enabled = Enabled

    --- Applies only internal region layout. Positioning relative to the unit
    --- frames or UIParent is handled by UpdateAnchor.
    local function ApplyLayout(frame)
        if not (frame and frame.statusBar) then
            return
        end

        EnsureDB()

        local general = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
        local refreshFrame = _G.MSUF_RefreshCastbarFrame
        if type(refreshFrame) == "function" then
            refreshFrame(frame, KIND, general)
        elseif type(_G.MSUF_ApplyCastbarDetailLayout) == "function" then
            _G.MSUF_ApplyCastbarDetailLayout(frame, KIND, general)
        end
        if type(_G.MSUF_ApplyCastbarSparkVisual) == "function" then
            _G.MSUF_ApplyCastbarSparkVisual(frame, general)
        end
    end

    --- Anchor/size pass for one bar. Called from settings, login, lifecycle
    --- events and preview sync, so it only mutates when values changed.
    local function UpdateAnchorBase(frame)
        if not frame then
            return false
        end

        EnsureDB()

        local general = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
        local index = frame._msufPoolIndex or 1
        local unit = frame.unit or (UNIT_PREFIX .. index)

        local desiredWidth
        local desiredHeight
        local preserveWidth
        if type(_G.MSUF_GetCastbarDesiredSize) == "function" then
            desiredWidth, desiredHeight, preserveWidth = _G.MSUF_GetCastbarDesiredSize(unit, general, frame, 240, 12)
        else
            desiredWidth = tonumber(general[DB_WIDTH])
            desiredHeight = tonumber(general[DB_HEIGHT])
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

        local offsetX = Snap(frame, tonumber(general[DB_OFFSET_X]) or 0)
        local offsetY = Snap(frame, tonumber(general[DB_OFFSET_Y]) or 0)

        if general[DB_DETACHED] == true then
            local layoutX = 0
            local layoutY = -((index - 1) * ROW_PITCH)

            local layoutDelta = _G[LAYOUT_DELTA]
            if type(layoutDelta) == "function" then
                local unitDB = (_G.MSUF_DB and _G.MSUF_DB[KIND]) or {}
                layoutX, layoutY = layoutDelta(index, unitDB)
                layoutX = tonumber(layoutX) or 0
                layoutY = tonumber(layoutY) or layoutY
            end

            changed = SetPointIfChanged(frame, "CENTER", UIParent, "CENTER", offsetX + layoutX,
                offsetY + (tonumber(layoutY) or 0)) or changed
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
                local gap
                if type(_G.MSUF_GetPhysicalPixelSize) == "function" then
                    gap = _G.MSUF_GetPhysicalPixelSize(frame, UNITFRAME_GAP)
                else
                    gap = Snap(frame, UNITFRAME_GAP)
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
                    FALLBACK_X + offsetX,
                    (FALLBACK_Y + offsetY) - ((index - 1) * ROW_PITCH)
                ) or changed
                local widthChanged = SetWidthIfChanged(frame, desiredWidth or frame:GetWidth() or 240)
                changed = widthChanged or changed
                sizeChanged = widthChanged or sizeChanged
            end
        end

        -- Position/profile/unitframe refresh owners all converge here. Once
        -- this pass validated the live provider and size for the current
        -- visual revision, the next spellcast does not need to repeat the same
        -- native geometry reads merely because the bar became active.
        frame._msufPoolAnchorValidationRev = tonumber(_G.MSUF__castbarStyleGlobalRev) or 1
        return changed, sizeChanged
    end

    local function UpdateAnchor(frame, forceLayout)
        local changed, sizeChanged = UpdateAnchorBase(frame)
        -- Moving between the fallback UIParent anchor and the live unit frame
        -- changes only the external anchor. Internal icon/text/spark geometry
        -- depends on size, not position, so a pure reanchor rebuilds nothing.
        if sizeChanged or forceLayout then ApplyLayout(frame) end
        return changed
    end

    --- The generic driver can receive the first spellcast event long after the
    --- lifecycle pass. Validate the pool geometry and detail-font generation
    --- right before that cast becomes visible. The common case stays
    --- comparison-only; a full layout runs only for stale state.
    local function PrepareForCast(frame)
        if not frame then return false end
        local fontEpoch = tonumber(_G.MSUF_FontApplyEpoch) or 0
        local visualRevision = tonumber(_G.MSUF__castbarStyleGlobalRev) or 1
        local sizeChanged = false
        if frame._msufPoolAnchorValidationRev ~= visualRevision then
            local _
            _, sizeChanged = UpdateAnchorBase(frame)
        end
        local layoutStale = frame._msufCastbarDetailLayoutUnit ~= KIND
            or frame._msufCastbarDetailLayoutFontEpoch ~= fontEpoch
            or frame._msufCastbarDetailLayoutVisualRev ~= visualRevision
        local retryFont = frame._msufCastbarDetailFontsReady == false
            and frame._msufPoolFontRetryEpoch ~= fontEpoch
        if retryFont then
            frame._msufPoolFontRetryEpoch = fontEpoch
            ClearFontAttempt(frame)
        end
        if sizeChanged or layoutStale or retryFont then
            ApplyLayout(frame)
            return true
        end
        return false
    end

    local function RefreshFromUnit(frame, refreshLayout)
        if not frame then return false end
        if UnitUnavailable(frame.unit) then
            StopCastbar(frame)
            return false
        end

        -- A lifecycle refresh owns the current unit token. Release any stale
        -- interrupt hold before Cast() rebuilds (or clears) that unit state.
        if frame.interrupted then StopCastbar(frame) end

        -- Probe the shared same-frame cast-state cache before touching
        -- geometry. Units can exist while no cast is active; in that dominant
        -- case, terminal cleanup is enough and avoids a complete
        -- anchor/layout/driver pass for an invisible bar.
        local state, stateKnown = BuildCastState(frame)
        if stateKnown and not (state and state.active == true) then
            StopCastbar(frame)
            return false
        end

        -- Lifecycle events need current geometry for a real active cast, but a
        -- full visual refresh is only necessary when that geometry changed.
        -- Visual settings already own their explicit force-layout path.
        if refreshLayout then frame:UpdateAnchor(false) end
        if frame.Cast then frame:Cast(state) end
        return true
    end

    --- Create or reuse one bar. The generic driver handles the cast behaviour;
    --- this only adds the pool's frame identity and lifecycle reactions.
    local function EnsureCastbar(index, enabled)
        local unit = UNIT_PREFIX .. index
        local name = FRAME_PREFIX .. index

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
        frame[KIND_FLAG] = true
        frame._msufPoolIndex = index
        if INDEX_FIELD then frame[INDEX_FIELD] = index end
        frame:SetFrameStrata("HIGH")
        frame:SetFrameLevel(FRAME_LEVEL_BASE + index)
        frame.ApplyLayout = ApplyLayout
        frame.PrepareForCast = PrepareForCast
        frame.UpdateAnchor = UpdateAnchor
        frame.UpdateAnchorBase = UpdateAnchorBase

        if not frame._msufPoolHooked then
            frame._msufPoolHooked = true
            frame:HookScript("OnEvent", OnPoolFrameEvent)
        end

        SetEventsRegistered(frame, enabled == true)
        frame:UpdateAnchor(true)
        frame:Hide()

        return frame
    end

    local function EnsureCastbars()
        local existing = _G[POOL_GLOBAL]
        if existing then
            return existing, false
        end

        if not Enabled() then
            return nil, false
        end

        local castbars = {}
        ExportPublic(POOL_GLOBAL, castbars)

        for index = 1, MAX_FRAMES do
            local frame = EnsureCastbar(index, true)
            castbars[index] = frame

            if frame and UnitExists(frame.unit) and frame.Cast then
                frame:Cast()
            end
        end

        return castbars, true
    end
    pool.Ensure = EnsureCastbars

    function pool.Castbars()
        return _G[POOL_GLOBAL]
    end

    --------------------------------------------------------------------
    -- Lifecycle: one next-frame pass per same-frame burst, a generation that
    -- a terminal event bumps so a queued pass can never resurrect a cast, and
    -- (where the descriptor asks for it) a one-bar-per-frame anchor prewarm.
    --------------------------------------------------------------------

    local passQueued = false
    local passGeneration = 0
    local passPendingGeneration
    local prewarmQueued = false
    local prewarmGeneration = 0
    local prewarmPendingGeneration
    local prewarmIndex

    local FlushPrewarm

    local function SchedulePrewarmStep()
        if prewarmQueued then return true end
        local scheduleOnce = _G.MSUF_ScheduleOnce
        if type(scheduleOnce) == "function" then
            prewarmQueued = true
            scheduleOnce(SCHEDULE_PREWARM, FlushPrewarm)
            return true
        end
        local timer = _G.C_Timer
        if timer and timer.After then
            prewarmQueued = true
            timer.After(0, FlushPrewarm)
            return true
        end
        -- The prewarm is optional; without a real frame boundary, leave the
        -- authoritative PrepareForCast validation in charge instead of moving
        -- all hidden-bar layout work into one synchronous burst.
        return false
    end

    FlushPrewarm = function()
        prewarmQueued = false
        local generation = prewarmPendingGeneration
        if generation == nil or generation ~= prewarmGeneration then
            prewarmPendingGeneration = nil
            prewarmIndex = nil
            return
        end

        local castbars = _G[POOL_GLOBAL]
        local index = prewarmIndex or 1
        local frame = castbars and castbars[index]
        if frame and not UnitUnavailable(frame.unit) and frame.UpdateAnchor then
            -- At most one provider/size/layout validation per rendered frame.
            -- A later real cast still calls PrepareForCast, so provider changes
            -- or a cast racing this queue cannot expose stale geometry.
            frame:UpdateAnchor(false)
        end

        index = index + 1
        if castbars and index <= #castbars then
            prewarmIndex = index
            if SchedulePrewarmStep() then return end
        end
        prewarmPendingGeneration = nil
        prewarmIndex = nil
    end

    local function QueuePrewarm()
        prewarmGeneration = prewarmGeneration + 1
        prewarmPendingGeneration = prewarmGeneration
        prewarmIndex = 1
        if not SchedulePrewarmStep() then
            prewarmPendingGeneration = nil
            prewarmIndex = nil
        end
    end

    local function FlushPass()
        passQueued = false
        if passPendingGeneration ~= passGeneration then return end
        passPendingGeneration = nil
        if not Enabled() then return end

        local castbars = _G[POOL_GLOBAL]
        if not castbars then return end
        for index = 1, #castbars do
            RefreshFromUnit(castbars[index], true)
        end
    end

    local function QueuePass()
        passPendingGeneration = passGeneration
        if passQueued then return end
        passQueued = true

        local scheduleOnce = _G.MSUF_ScheduleOnce
        local timer = _G.C_Timer
        if type(scheduleOnce) == "function" then
            scheduleOnce(SCHEDULE_PASS, FlushPass)
        elseif timer and timer.After then
            timer.After(0, FlushPass)
        else
            FlushPass()
        end
    end

    local function CancelLifecycle()
        passGeneration = passGeneration + 1
        passPendingGeneration = nil
        prewarmGeneration = prewarmGeneration + 1
        prewarmPendingGeneration = nil
        prewarmIndex = nil
    end

    -- event -> lifecycle row, for the events this client supports.
    local rows = {}
    local supportedRows = {}
    for index = 1, #desc.lifecycle do
        local row = desc.lifecycle[index]
        if row.supported ~= false then
            rows[row.event] = row
            supportedRows[#supportedRows + 1] = row
        end
    end

    -- Unit tokens the pool owns: the filter for UNIT_* lifecycle events. The
    -- shared bus refuses a UNIT_* subscription without a unit list, and
    -- RegisterUnitEvent is variadic on 12.x (SimpleFrameAPIDocumentation
    -- marks `units` StrideIndex = 1), so every token really is registered.
    local lifecycleUnits = {}
    for index = 1, MAX_FRAMES do
        lifecycleUnits[index] = UNIT_PREFIX .. index
    end

    local issecret = _G.issecretvalue
    local UNIT_PATTERN = "^" .. UNIT_PREFIX .. "(%d+)$"

    local function HandleLifecycle(event, eventUnit)
        local castbars = _G[POOL_GLOBAL]
        local created
        if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
            castbars, created = EnsureCastbars()
            if not castbars or created == true then return end
        elseif not castbars then
            return
        end

        local row = rows[event]
        if not row then return end
        local action = row.action

        if action == "terminal" and (not row.terminalWhen or row.terminalWhen()) then
            -- A queued pass must never resurrect a cast after the terminal
            -- event. The stable callback stays harmless in the scheduler and
            -- rejects this older generation when it runs.
            CancelLifecycle()
            for index = 1, #castbars do
                StopCastbar(castbars[index])
            end
            return
        end

        if action == "unit" then
            -- A per-unit payload refreshes only the owning bar, at once. A
            -- secret token must never reach string.match.
            if type(eventUnit) == "string" and not (issecret and issecret(eventUnit) == true) then
                local index = tonumber(eventUnit:match(UNIT_PATTERN))
                local frame = index and castbars[index]
                if frame and frame.unit == eventUnit then
                    RefreshFromUnit(frame, false)
                    return
                end
            end
            if row.unitFallback ~= "pass" then return end
        end

        -- These notifications commonly arrive as one same-frame burst. Collapse
        -- the burst into one next-frame pool pass, so every bar refreshes once
        -- instead of once per overlapping notification.
        QueuePass()
        if row.prewarm and SCHEDULE_PREWARM then
            QueuePrewarm()
        end
    end
    pool.HandleLifecycle = HandleLifecycle

    local lifecycleFrame

    local function UnregisterLifecycleBus()
        local unregister = _G.MSUF_EventBus_Unregister
        if type(unregister) ~= "function" then return end
        for index = 1, #supportedRows do
            local row = supportedRows[index]
            unregister(row.event, row.key)
        end
    end

    --- Private driver frame for the whole pool. It owns the lifecycle when no
    --- shared bus exists, and it is also the recovery path when the bus refuses
    --- a subscription: a half-wired pool would silently miss lifecycle updates
    --- instead of failing where it can be seen.
    local function RegisterLifecycleFrame()
        lifecycleFrame = lifecycleFrame or CreateFrame("Frame")
        lifecycleFrame:SetScript("OnEvent", function(_, event, ...)
            HandleLifecycle(event, ...)
        end)
        for index = 1, #supportedRows do
            lifecycleFrame:RegisterEvent(supportedRows[index].event)
        end
    end

    local function SyncLifecycle(enabled)
        enabled = enabled == true
        UnregisterLifecycleBus()
        if lifecycleFrame then lifecycleFrame:UnregisterAllEvents() end
        if not enabled then
            CancelLifecycle()
            return false
        end
        local register = _G.MSUF_EventBus_Register
        if type(register) == "function" then
            -- The bus answers false when it declines a subscription. Every call
            -- runs before the verdict is read, so one refusal cannot skip the
            -- others.
            local wired = true
            for index = 1, #supportedRows do
                local row = supportedRows[index]
                wired = register(row.event, row.key, HandleLifecycle, row.units and lifecycleUnits or nil,
                    row.once or nil) ~= false and wired
            end
            if wired then return true end
            UnregisterLifecycleBus()
        end
        RegisterLifecycleFrame()
        return true
    end

    --------------------------------------------------------------------
    -- Menu/profile entry points
    --------------------------------------------------------------------

    local function RefreshPreviewIfAllowed()
        local updatePreview = _G[PREVIEW_UPDATE]
        if not InCombat() and type(updatePreview) == "function" then
            updatePreview()
        end
    end

    local function ApplyPositionSetting(forceLayout, skipPreviewRefresh, geometryOnly)
        local castbars = _G[POOL_GLOBAL] or EnsureCastbars()
        if not castbars then
            return
        end

        for index = 1, #castbars do
            local frame = castbars[index]
            if frame then
                if geometryOnly and frame.UpdateAnchorBase then
                    frame:UpdateAnchorBase()
                else
                    frame:UpdateAnchor(forceLayout ~= false)
                end
            end
        end

        if not skipPreviewRefresh then RefreshPreviewIfAllowed() end
    end

    --- Keep backend flags, event subscriptions, live frame state, visuals and
    --- previews synchronized from this one path.
    local function SetEnabled(enabled)
        EnsureDB()

        enabled = enabled and true or false

        local general = _G.MSUF_DB and _G.MSUF_DB.general
        if general then
            local setBackend = _G.MSUF_SetCastbarBackend
            if type(setBackend) == "function" then
                setBackend(KIND, enabled and "MSUF" or "HIDE", general)
            else
                general[ENABLE_KEY] = enabled
            end
        end

        local castbars = enabled and (_G[POOL_GLOBAL] or EnsureCastbars()) or _G[POOL_GLOBAL]
        if not castbars then
            return
        end

        for index = 1, #castbars do
            local frame = castbars[index]
            if frame then
                SetEventsRegistered(frame, enabled)

                if enabled then
                    if frame.UpdateAnchorBase then frame:UpdateAnchorBase() else frame:UpdateAnchor(true) end
                    if UnitExists(frame.unit) and frame.Cast then
                        frame:Cast()
                    end
                else
                    StopCastbar(frame)
                end
            end
        end

        local refreshed
        if type(_G.MSUF_ApplyCastbarVisualsForUnit) == "function" then
            _G.MSUF_ApplyCastbarVisualsForUnit(KIND)
            refreshed = true
        elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
            _G.MSUF_UpdateCastbarVisuals(KIND)
            refreshed = true
        end

        if not refreshed then RefreshPreviewIfAllowed() end
    end

    --- Every castbar settings refresh lands here. On a client without the
    --- kind's units the pool is never built, and the profile keeps its castbar
    --- backend instead of being rewritten to HIDE, so a profile taken to a
    --- client with those units still shows the castbars.
    local function ApplyEnabled()
        local sync = _G[EXPORTS.syncLifecycle]
        if not HAS_UNITS then
            if sync then sync(false) end
            return
        end
        local enabled = Enabled()
        SetEnabled(enabled)
        if sync then sync(enabled) end
    end

    pool.ApplyPositionSetting = ApplyPositionSetting
    pool.ApplyEnabled = ApplyEnabled
    pool.SetEnabled = SetEnabled
    pool.SyncLifecycle = SyncLifecycle
    pool.RefreshFromUnit = RefreshFromUnit
    pool.Stop = StopCastbar

    -- Documented public globals, kept as compatibility aliases.
    ExportPublic(EXPORTS.positionSetting, ApplyPositionSetting)
    ExportPublic(EXPORTS.applyEnabled, ApplyEnabled)
    ExportPublic(EXPORTS.stop, StopCastbar)
    ExportPublic(EXPORTS.syncLifecycle, SyncLifecycle)
    SyncLifecycle(Enabled())
    return pool
end
