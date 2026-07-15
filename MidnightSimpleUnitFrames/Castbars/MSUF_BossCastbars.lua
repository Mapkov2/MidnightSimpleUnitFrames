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

local function SetPointIfChanged(frame, point, relativeTo, relativePoint, offsetX, offsetY)
    if not frame then
        return false
    end

    offsetX = math.floor((tonumber(offsetX) or 0) + 0.5)
    offsetY = math.floor((tonumber(offsetY) or 0) + 0.5)

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
    if type(_G.MSUF_GetCastbarDesiredSize) == "function" then
        desiredWidth, desiredHeight = _G.MSUF_GetCastbarDesiredSize(unit, general, frame, 240, 12)
    else
        desiredWidth = tonumber(general.bossCastbarWidth)
        desiredHeight = tonumber(general.bossCastbarHeight)
    end

    local changed = false
    changed = SetHeightIfChanged(frame, desiredHeight or frame:GetHeight() or 18) or changed

    local offsetX = tonumber(general.bossCastbarOffsetX) or 0
    local offsetY = tonumber(general.bossCastbarOffsetY) or 0

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
        changed = SetWidthIfChanged(frame, desiredWidth or frame:GetWidth() or 240) or changed
    else
        local unitFrame = _G["MSUF_" .. unit]
        if unitFrame and unitFrame.GetWidth then
            changed = SetPointIfChanged(frame, "BOTTOMLEFT", unitFrame, "TOPLEFT", offsetX, offsetY + 2) or changed
            changed = SetWidthIfChanged(frame, desiredWidth or unitFrame:GetWidth() or 240) or changed
        else
            changed = SetPointIfChanged(
                frame,
                "TOPRIGHT",
                UIParent,
                "TOPRIGHT",
                -420 + offsetX,
                (-220 + offsetY) - ((bossIndex - 1) * 34)
            ) or changed
            changed = SetWidthIfChanged(frame, desiredWidth or frame:GetWidth() or 240) or changed
        end
    end

    return changed
end

local function UpdateBossCastbarAnchor(frame, forceLayout)
    local changed = UpdateBossCastbarAnchorBase(frame)
    if changed or forceLayout then ApplyBossCastbarLayout(frame) end
    return changed
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

local function InvalidateBossCastState(unit)
    local getEngine = _G.MSUF_GetCastbarEngine
    local engine = type(getEngine) == "function" and getEngine() or nil
    if engine and type(engine.Invalidate) == "function" then
        engine:Invalidate(unit)
    end
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

    if refreshLayout then frame:UpdateAnchor(true) end
    InvalidateBossCastState(frame.unit)
    if frame.Cast then frame:Cast() end
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
        frame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        frame:RegisterEvent("UNIT_TARGETABLE_CHANGED")
        frame:RegisterEvent("ENCOUNTER_START")
        frame:RegisterEvent("ENCOUNTER_END")
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
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
local function EnsureBossCastbar(index)
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
    frame.UpdateAnchor = UpdateBossCastbarAnchor
    frame.UpdateAnchorBase = UpdateBossCastbarAnchorBase

    if not frame._msufBossHooked then
        frame._msufBossHooked = true
        frame:HookScript("OnEvent", function(eventFrame, event, eventUnit)
            -- The generic driver owns active-only UNIT_HEALTH. Keep its hot
            -- path out of the boss lifecycle branch chain below.
            if event == "UNIT_HEALTH" then return end

            if event == "ENCOUNTER_END" then
                StopBossCastbar(eventFrame)
                return
            end

            if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT"
                or event == "ENCOUNTER_START"
                or event == "PLAYER_ENTERING_WORLD"
            then
                if BossCastbarsEnabled() then
                    RefreshBossCastbarFromUnit(eventFrame, true)
                end
            elseif event == "UNIT_TARGETABLE_CHANGED"
                and eventUnit == eventFrame.unit
            then
                if BossCastbarsEnabled() then
                    RefreshBossCastbarFromUnit(eventFrame, false)
                end
            elseif event == "UNIT_FLAGS"
                and eventFrame:IsShown()
                and BossUnitUnavailable(eventFrame.unit)
            then
                StopBossCastbar(eventFrame)
            end
        end)
    end

    SetBossEventsRegistered(frame, BossCastbarsEnabled())
    frame:UpdateAnchor(true)
    frame:Hide()

    return frame
end

local function EnsureBossCastbars()
    if _G.MSUF_BossCastbars then
        return _G.MSUF_BossCastbars
    end

    if not BossCastbarsEnabled() then
        return nil
    end

    local bossCastbars = {}
    ExportPublic("MSUF_BossCastbars", bossCastbars)

    for index = 1, MAX_BOSS_FRAMES do
        local frame = EnsureBossCastbar(index)
        bossCastbars[index] = frame

        if frame and UnitExists(frame.unit) and frame.Cast then
            frame:Cast()
        end
    end

    return bossCastbars
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

local function OnLogin()
    if not BossCastbarsEnabled() then return end
    EnsureBossCastbars()

    ApplyBossCastbarPositionSetting(true)
end

ExportPublic("MSUF_ApplyBossCastbarPositionSetting", ApplyBossCastbarPositionSetting)
ExportPublic("MSUF_ApplyBossCastbarsEnabled", ApplyBossCastbarsEnabled)
ExportPublic("MSUF_BossCastbar_Stop", StopBossCastbar)

local bossLifecycleFrame
local function SyncBossLifecycle(enabled)
    enabled = enabled == true
    if type(_G.MSUF_EventBus_Unregister) == "function" then
        _G.MSUF_EventBus_Unregister("PLAYER_LOGIN", "MSUF_BOSS_CASTBARS")
        _G.MSUF_EventBus_Unregister("PLAYER_ENTERING_WORLD", "MSUF_BOSS_CASTBARS_WORLD")
    end
    if bossLifecycleFrame then bossLifecycleFrame:UnregisterAllEvents() end
    if not enabled then return false end
    if type(_G.MSUF_EventBus_Register) == "function" then
        _G.MSUF_EventBus_Register("PLAYER_LOGIN", "MSUF_BOSS_CASTBARS", OnLogin, nil, true)
        _G.MSUF_EventBus_Register("PLAYER_ENTERING_WORLD", "MSUF_BOSS_CASTBARS_WORLD", OnLogin)
    else
        bossLifecycleFrame = bossLifecycleFrame or CreateFrame("Frame")
        bossLifecycleFrame:SetScript("OnEvent", OnLogin)
        bossLifecycleFrame:RegisterEvent("PLAYER_LOGIN")
        bossLifecycleFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    return true
end
ExportPublic("MSUF_BossCastbars_SyncLifecycle", SyncBossLifecycle)
SyncBossLifecycle(BossCastbarsEnabled())
