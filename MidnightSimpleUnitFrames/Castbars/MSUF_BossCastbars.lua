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
    local height = frame:GetHeight() or 18
    if height < 12 then
        height = 12
    end

    local showIcon = (general.showBossCastIcon == nil)
        and (general.castbarShowIcon ~= false)
        or (general.showBossCastIcon ~= false)

    local iconOffsetX = tonumber(general.bossCastIconOffsetX) or tonumber(general.castbarIconOffsetX) or 0
    local iconOffsetY = tonumber(general.bossCastIconOffsetY) or tonumber(general.castbarIconOffsetY) or 0
    local iconSize = tonumber(general.bossCastIconSize) or tonumber(general.castbarIconSize) or height

    if iconSize < 6 then
        iconSize = 6
    elseif iconSize > 128 then
        iconSize = 128
    end

    if frame.icon then
        local iconParent = ((iconOffsetX ~= 0 or iconOffsetY ~= 0) and frame.statusBar) or frame

        if frame.icon.SetParent and frame.icon:GetParent() ~= iconParent then
            frame.icon:SetParent(iconParent)
        end

        frame.icon:ClearAllPoints()
        frame.icon:SetPoint("LEFT", frame, "LEFT", iconOffsetX, iconOffsetY)
        frame.icon:SetSize(iconSize, iconSize)
        frame.icon:SetShown(showIcon)
    end

    frame.statusBar:ClearAllPoints()
    if showIcon and frame.icon and iconOffsetX == 0 and iconOffsetY == 0 then
        frame.statusBar:SetPoint("LEFT", frame, "LEFT", iconSize + 1, 0)
    else
        frame.statusBar:SetPoint("LEFT", frame, "LEFT", 0, 0)
    end

    frame.statusBar:SetPoint("TOP", frame, "TOP", 0, -1)
    frame.statusBar:SetPoint("BOTTOM", frame, "BOTTOM", 0, 1)
    frame.statusBar:SetPoint("RIGHT", frame, "RIGHT", -1, 0)

    if frame.backgroundBar then
        frame.backgroundBar:ClearAllPoints()
        frame.backgroundBar:SetAllPoints(frame.statusBar)
    end

    if type(_G.MSUF_ApplyBossCastbarTextsLayout) == "function" then
        local nameFontSize = tonumber(general.bossCastSpellNameFontSize)
            or tonumber(general.castbarSpellNameFontSize)
            or tonumber(general.fontSize)
            or 14
        local timeFontSize = tonumber(general.bossCastTimeFontSize) or nameFontSize

        _G.MSUF_ApplyBossCastbarTextsLayout(frame, {
            baselineTimeX = -2,
            baselineTimeY = 0,
            textOffsetX = tonumber(general.bossCastTextOffsetX) or 0,
            textOffsetY = tonumber(general.bossCastTextOffsetY) or 0,
            timeOffsetX = tonumber(general.bossCastTimeOffsetX) or -2,
            timeOffsetY = tonumber(general.bossCastTimeOffsetY) or 0,
            showName = general.showBossCastName ~= false,
            showTime = general.showBossCastTime ~= false,
            nameFontSize = nameFontSize,
            timeFontSize = timeFontSize,
        })
    end

    if type(_G.MSUF_ApplyCastbarOutline) == "function" then
        _G.MSUF_ApplyCastbarOutline(frame, true)
    end

    if type(_G.MSUF_ApplyCastbarDetailLayout) == "function" then
        _G.MSUF_ApplyCastbarDetailLayout(frame, "boss")
    end
end

--- Anchor/size pass for one boss castbar. This can be called from settings,
--- login, encounter events, and preview sync, so it only mutates when values
--- actually changed.
local function UpdateBossCastbarAnchor(frame, forceLayout)
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

    if changed or forceLayout then
        ApplyBossCastbarLayout(frame)
    end

    return changed
end

local function StopBossCastbar(frame)
    if not frame then
        return
    end

    if type(_G.MSUF_CB_ResetStateOnStop) == "function" then
        _G.MSUF_CB_ResetStateOnStop(frame, "STOPPED")
    elseif frame.Hide then
        frame:Hide()
    end
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

        frame:RegisterUnitEvent("UNIT_HEALTH", frame.unit)
        frame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        frame:RegisterEvent("ENCOUNTER_START")
        frame:RegisterEvent("ENCOUNTER_END")
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame._msufDriverEventsRegistered = true
        frame._msufBossEventsRegistered = true
        return
    end

    frame:UnregisterAllEvents()
    frame._msufDriverEventsRegistered = nil
    frame._msufBossEventsRegistered = nil
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

    if not frame._msufBossHooked then
        frame._msufBossHooked = true
        frame:HookScript("OnEvent", function(eventFrame, event)
            if event == "ENCOUNTER_END" then
                StopBossCastbar(eventFrame)
                return
            end

            if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT"
                or event == "ENCOUNTER_START"
                or event == "PLAYER_ENTERING_WORLD"
            then
                if BossCastbarsEnabled() then
                    eventFrame:UpdateAnchor(true)
                    if eventFrame.Cast then
                        eventFrame:Cast()
                    end
                end
            elseif event == "UNIT_HEALTH"
                and eventFrame:IsShown()
                and (not UnitExists(eventFrame.unit) or (UnitIsDeadOrGhost and UnitIsDeadOrGhost(eventFrame.unit)))
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

local function ApplyBossCastbarTimeSetting()
    EnsureDB()

    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local showTime = (not general) or general.showBossCastTime ~= false
    local bossCastbars = _G.MSUF_BossCastbars

    if bossCastbars then
        for index = 1, #bossCastbars do
            local frame = bossCastbars[index]
            if frame and frame.timeText then
                frame.timeText:Show()
                frame.timeText:SetAlpha(showTime and 1 or 0)

                if not showTime and frame.timeText.SetText then
                    frame.timeText:SetText("")
                end
            end
        end
    end

    RefreshBossPreviewIfAllowed()
end

local function ApplyBossCastbarPositionSetting(forceLayout)
    local bossCastbars = _G.MSUF_BossCastbars or EnsureBossCastbars()
    if not bossCastbars then
        return
    end

    for index = 1, #bossCastbars do
        local frame = bossCastbars[index]
        if frame then
            frame:UpdateAnchor(forceLayout ~= false)
        end
    end

    RefreshBossPreviewIfAllowed()
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
                frame:UpdateAnchor(true)
                if UnitExists(frame.unit) and frame.Cast then
                    frame:Cast()
                end
            else
                StopBossCastbar(frame)
            end
        end
    end

    if type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals()
    end

    RefreshBossPreviewIfAllowed()
end

local function ApplyBossCastbarsEnabled()
    SetBossCastbarsEnabled(BossCastbarsEnabled())
end

local function OnLogin()
    EnsureBossCastbars()

    ApplyBossCastbarPositionSetting(true)
end

ExportPublic("MSUF_ApplyBossCastbarTimeSetting", ApplyBossCastbarTimeSetting)
ExportPublic("MSUF_ApplyBossCastbarPositionSetting", ApplyBossCastbarPositionSetting)
ExportPublic("MSUF_SetBossCastbarsEnabled", SetBossCastbarsEnabled)
ExportPublic("MSUF_ApplyBossCastbarsEnabled", ApplyBossCastbarsEnabled)
ExportPublic("MSUF_BossCastbar_Stop", StopBossCastbar)

if type(_G.MSUF_EventBus_Register) == "function" then
    _G.MSUF_EventBus_Register("PLAYER_LOGIN", "MSUF_BOSS_CASTBARS", OnLogin, nil, true)
    _G.MSUF_EventBus_Register("PLAYER_ENTERING_WORLD", "MSUF_BOSS_CASTBARS_WORLD", OnLogin)
else
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", OnLogin)
end
