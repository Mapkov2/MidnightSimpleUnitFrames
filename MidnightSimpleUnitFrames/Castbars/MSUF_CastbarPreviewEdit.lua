-- Castbar preview edit bridge.
-- Maps preview drag/resize handles back to the same DB keys and reanchor helpers used by live
-- castbars. This is an edit-mode cold path and should not observe live cast events.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local UNIT_CONFIG = {
    player = {
        w = "castbarPlayerBarWidth",
        h = "castbarPlayerBarHeight",
        x = "castbarPlayerOffsetX",
        y = "castbarPlayerOffsetY",
        dx = 0,
        dy = 5,
        reanchor = "MSUF_ReanchorPlayerCastBar",
        test = "MSUF_SetPlayerCastbarTestMode",
    },
    target = {
        w = "castbarTargetBarWidth",
        h = "castbarTargetBarHeight",
        x = "castbarTargetOffsetX",
        y = "castbarTargetOffsetY",
        dx = 65,
        dy = -15,
        reanchor = "MSUF_ReanchorTargetCastBar",
        test = "MSUF_SetTargetCastbarTestMode",
    },
    focus = {
        w = "castbarFocusBarWidth",
        h = "castbarFocusBarHeight",
        x = "castbarFocusOffsetX",
        y = "castbarFocusOffsetY",
        fallbackX = "castbarTargetOffsetX",
        fallbackY = "castbarTargetOffsetY",
        dx = 65,
        dy = -15,
        reanchor = "MSUF_ReanchorFocusCastBar",
        test = "MSUF_SetFocusCastbarTestMode",
    },
    boss = {
        w = "bossCastbarWidth",
        h = "bossCastbarHeight",
        x = "bossCastbarOffsetX",
        y = "bossCastbarOffsetY",
        dx = 0,
        dy = 0,
        reanchor = "MSUF_ReanchorBossCastBar",
        test = "MSUF_SetBossCastbarTestMode",
    },
}
local CASTBAR_PREVIEW_DRAG_APPLY_INTERVAL = 0.05

local function GeneralDB()
    if type(EnsureDB) == "function" then
        EnsureDB()
    end

    MSUF_DB = MSUF_DB or {}
    MSUF_DB.general = MSUF_DB.general or {}
    return MSUF_DB.general
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function Round(value)
    value = tonumber(value) or 0
    return value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5)
end

local function OffsetX(general, config)
    return tonumber(general[config.x])
        or (config.fallbackX and tonumber(general[config.fallbackX]))
        or config.dx
        or 0
end

local function OffsetY(general, config)
    return tonumber(general[config.y])
        or (config.fallbackY and tonumber(general[config.fallbackY]))
        or config.dy
        or 0
end

local function ApplyUnitAndSync(unit)
    if type(_G.MSUF_ApplyCastbarUnitAndSync) == "function" then
        _G.MSUF_ApplyCastbarUnitAndSync(unit)
        return
    end

    local config = UNIT_CONFIG[unit]
    local reanchor = config and config.reanchor and _G[config.reanchor]

    if type(reanchor) == "function" then
        reanchor()
    end

    local refreshed = false
    if type(_G.MSUF_ApplyCastbarVisualsForUnit) == "function" then
        _G.MSUF_ApplyCastbarVisualsForUnit(unit)
        refreshed = true
    elseif type(MSUF_UpdateCastbarVisuals) == "function" then
        MSUF_UpdateCastbarVisuals(unit)
        refreshed = true
    end

    if not refreshed and unit == "boss" and not InCombat() and type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
        _G.MSUF_UpdateBossCastbarPreview()
    end

    if type(_G.MSUF_PositionCastbarPreviewUnit) == "function" then
        _G.MSUF_PositionCastbarPreviewUnit(unit)
    end

    if type(MSUF_UpdateCastbarEditInfo) == "function" then
        MSUF_UpdateCastbarEditInfo(unit)
    end

    if type(MSUF_SyncCastbarPositionPopup) == "function" then
        MSUF_SyncCastbarPositionPopup(unit)
    end
end

local function PositionPreviewOnly(unit)
    local position = _G.MSUF_PositionCastbarPreviewUnit
    if type(position) == "function" then
        return position(unit) and true or false
    end
    return false
end

local function ThrottledApplyUnitAndSync(frame, unit, elapsed)
    frame._msufPreviewApplyAcc = (tonumber(frame._msufPreviewApplyAcc) or 0) + (tonumber(elapsed) or 0)
    if frame._msufPreviewApplyAcc < CASTBAR_PREVIEW_DRAG_APPLY_INTERVAL then return false end
    frame._msufPreviewApplyAcc = 0
    ApplyUnitAndSync(unit)
    return true
end

local function ClampBossOffsets(general, config)
    if type(MSUF_ClampToSlider) ~= "function" then
        return
    end

    local xSlider = _G.MSUF_CastbarBossXOffsetSlider
    local ySlider = _G.MSUF_CastbarBossYOffsetSlider

    if xSlider then
        general[config.x] = MSUF_ClampToSlider(xSlider, tonumber(general[config.x]) or 0)
    end

    if ySlider then
        general[config.y] = MSUF_ClampToSlider(ySlider, tonumber(general[config.y]) or 0)
    end
end

local function PulsePreview(unit)
    if not _G.MSUF_UnitEditModeActive then
        return
    end

    local config = UNIT_CONFIG[unit]
    local setTestMode = config and _G[config.test]
    if type(setTestMode) ~= "function" then
        return
    end

    setTestMode(true, true)

    local timers = _G.MSUF_CastbarPreviewPulseTimers
    if not timers then
        timers = ExportPublic("MSUF_CastbarPreviewPulseTimers", {})
    end

    if type(timers[unit]) == "table" then
        timers[unit].cancelled = true
    end

    local token = {}
    timers[unit] = token

    C_Timer.After(8, function()
        if token.cancelled or timers[unit] ~= token or not _G.MSUF_UnitEditModeActive or InCombat() then
            return
        end

        local general = GeneralDB()
        local testModeKey = (unit == "player" and "playerCastbarTestMode")
            or (unit == "target" and "targetCastbarTestMode")
            or (unit == "focus" and "focusCastbarTestMode")
            or "bossCastbarTestMode"

        if general[testModeKey] then
            return
        end

        local popup = _G.MSUF_EM2 and _G.MSUF_EM2.CastPopup
        if popup and popup.IsOpen and popup:IsOpen() then
            return
        end

        timers[unit] = nil
        setTestMode(false, true)
    end)
end

local function RegisterPreviewNudgeTarget(frame, unit, config)
    local setNudgeTarget = _G.MSUF_EM2_SetPreviewNudgeTarget
    if type(setNudgeTarget) ~= "function" then
        return
    end

    setNudgeTarget({
        frame = frame,
        IsActive = function()
            return _G.MSUF_UnitEditModeActive and frame.IsShown and frame:IsShown()
        end,
        Nudge = function(_, deltaX, deltaY)
            if not _G.MSUF_UnitEditModeActive or InCombat() then
                return
            end

            local general = GeneralDB()
            if type(_G.MSUF_EM_UndoBeforeChange) == "function" then
                _G.MSUF_EM_UndoBeforeChange("castbar", unit, true)
            end

            general[config.x] = Round(OffsetX(general, config) + (deltaX or 0))
            general[config.y] = Round(OffsetY(general, config) + (deltaY or 0))

            if unit == "boss" then
                ClampBossOffsets(general, config)
            end

            ApplyUnitAndSync(unit)
        end,
    })
end

local function UsesWidthSource(general, unit)
    local widthSourceKey = _G.MSUF_GetCastbarWidthSourceKey and _G.MSUF_GetCastbarWidthSourceKey(unit)
    local normalize = _G.MSUF_NormalizeCastbarWidthSource or _G.MSUF_NormalizePlayerCastbarWidthSource
    local widthSource = widthSourceKey and general[widthSourceKey]

    if type(normalize) == "function" then
        return normalize(widthSource) ~= nil
    end

    return widthSource == "unitframe" or widthSource == "essential" or widthSource == "utility"
end

local function SetupCastbarPreviewEditHandlers(frame, unit)
    if not frame or frame.MSUF_PreviewEditHandlersSetup then
        return
    end

    local config = UNIT_CONFIG[unit] or UNIT_CONFIG.player

    frame.MSUF_PreviewEditHandlersSetup = true
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)

    frame:SetScript("OnMouseDown", function(self, button)
        if _G.MSUF_UnitEditModeActive then
            RegisterPreviewNudgeTarget(self, unit, config)
        end

        if button == "RightButton" then
            if _G.MSUF_UnitEditModeActive
                and not MSUF_EditModeSizing
                and not InCombat()
                and type(MSUF_OpenCastbarPositionPopup) == "function"
            then
                MSUF_OpenCastbarPositionPopup(unit, self)
            end
            return
        end

        if button ~= "LeftButton" or not _G.MSUF_UnitEditModeActive or InCombat() then
            return
        end

        local general = GeneralDB()
        if not general.castbarPlayerPreviewEnabled then
            return
        end

        self.isDragging = true
        self.dragMoved = false
        self._msufUndoFired = false
        self._msufPreviewApplyAcc = CASTBAR_PREVIEW_DRAG_APPLY_INTERVAL

        local uiScale = UIParent:GetEffectiveScale() or 1
        local cursorX, cursorY = GetCursorPosition()
        self.dragStartCursorX = cursorX / uiScale
        self.dragStartCursorY = cursorY / uiScale

        if MSUF_EditModeSizing then
            self.dragMode = "SIZE"
            self.dragStartWidth = tonumber(general[config.w])
                or tonumber(general.castbarGlobalWidth)
                or self:GetWidth()
                or 250
            self.dragStartHeight = tonumber(general[config.h])
                or tonumber(general.castbarGlobalHeight)
                or self:GetHeight()
                or 18
        else
            self.dragMode = "MOVE"
            self.dragStartOffsetX = OffsetX(general, config)
            self.dragStartOffsetY = OffsetY(general, config)

            local frameScale = self:GetEffectiveScale() or 1
            local left = self:GetLeft() or 0
            local right = self:GetRight() or 0
            local top = self:GetTop() or 0
            local bottom = self:GetBottom() or 0

            self._snapStartCX = (left + right) * 0.5 * frameScale / uiScale
            self._snapStartCY = (top + bottom) * 0.5 * frameScale / uiScale
            self._snapHW = (right - left) * 0.5 * frameScale / uiScale
            self._snapHH = (top - bottom) * 0.5 * frameScale / uiScale
        end

        self:SetScript("OnUpdate", function(dragFrame, elapsed)
            if not dragFrame.isDragging then
                dragFrame:SetScript("OnUpdate", nil)
                return
            end

            local scale = UIParent:GetEffectiveScale() or 1
            local currentCursorX, currentCursorY = GetCursorPosition()
            local deltaX = currentCursorX / scale - (dragFrame.dragStartCursorX or currentCursorX / scale)
            local deltaY = currentCursorY / scale - (dragFrame.dragStartCursorY or currentCursorY / scale)

            if not dragFrame.dragMoved and math.abs(deltaX) + math.abs(deltaY) < 6 then
                return
            end

            if not dragFrame.dragMoved then
                dragFrame.dragMoved = true

                if type(_G.MSUF_EM_UndoBeginChange) == "function" then
                    dragFrame._msufCastbarHistoryDrag = _G.MSUF_EM_UndoBeginChange("castbar", unit, "Move") == true
                elseif type(_G.MSUF_EM_UndoBeforeChange) == "function" then
                    _G.MSUF_EM_UndoBeforeChange("castbar", unit, false)
                end
            end

            local liveGeneral = GeneralDB()
            if dragFrame.dragMode == "SIZE" then
                if not UsesWidthSource(liveGeneral, unit) then
                    liveGeneral[config.w] = Round(math.max(50, (dragFrame.dragStartWidth or 250) + deltaX))
                end

                liveGeneral[config.h] = Round(math.max(8, (dragFrame.dragStartHeight or 18) + deltaY))
            else
                local snappedDeltaX = deltaX
                local snappedDeltaY = deltaY
                local snap = _G.MSUF_EM2 and _G.MSUF_EM2.Snap

                if snap and snap.IsEnabled and snap.IsEnabled() and snap.Apply then
                    local snappedX, snappedY = snap.Apply(
                        (dragFrame._snapStartCX or 0) + deltaX,
                        (dragFrame._snapStartCY or 0) + deltaY,
                        dragFrame._snapHW or 0,
                        dragFrame._snapHH or 0,
                        "castbar_" .. unit
                    )

                    snappedDeltaX = snappedX - (dragFrame._snapStartCX or 0)
                    snappedDeltaY = snappedY - (dragFrame._snapStartCY or 0)
                end

                liveGeneral[config.x] = Round((dragFrame.dragStartOffsetX or 0) + snappedDeltaX)
                liveGeneral[config.y] = Round((dragFrame.dragStartOffsetY or 0) + snappedDeltaY)

                if unit == "boss" then
                    ClampBossOffsets(liveGeneral, config)
                end
            end

            if dragFrame.dragMode == "MOVE" and PositionPreviewOnly(unit) then
                dragFrame._msufPreviewApplyAcc = CASTBAR_PREVIEW_DRAG_APPLY_INTERVAL
                if type(MSUF_SyncCastbarPositionPopup) == "function" then
                    dragFrame._msufPopupSyncAcc = (tonumber(dragFrame._msufPopupSyncAcc) or 0) + (tonumber(elapsed) or 0)
                    if dragFrame._msufPopupSyncAcc >= CASTBAR_PREVIEW_DRAG_APPLY_INTERVAL then
                        dragFrame._msufPopupSyncAcc = 0
                        MSUF_SyncCastbarPositionPopup(unit)
                    end
                end
            else
                ThrottledApplyUnitAndSync(dragFrame, unit, elapsed)
            end
        end)
    end)

    frame:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then
            return
        end

        local moved = self.dragMoved
        if self.isDragging then
            self.isDragging = false
            self:SetScript("OnUpdate", nil)
            self._msufPreviewApplyAcc = nil
            self._msufPopupSyncAcc = nil

            local snap = _G.MSUF_EM2 and _G.MSUF_EM2.Snap
            if snap and snap.HideGuides then
                snap.HideGuides()
            end
        end

        PulsePreview(unit)
        if moved then
            ApplyUnitAndSync(unit)
        end
        if self._msufCastbarHistoryDrag and type(_G.MSUF_EM_UndoCommitChange) == "function" then
            self._msufCastbarHistoryDrag = nil
            _G.MSUF_EM_UndoCommitChange()
        end

        if not moved
            and _G.MSUF_UnitEditModeActive
            and not InCombat()
            and type(MSUF_OpenCastbarPositionPopup) == "function"
        then
            MSUF_OpenCastbarPositionPopup(unit, self)
        end
    end)
end

ExportPublic("MSUF_SetupCastbarPreviewEditHandlers", SetupCastbarPreviewEditHandlers)
