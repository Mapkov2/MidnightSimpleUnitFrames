-- Cold preview drag/resize bridge to the live castbars' DB keys and anchor helpers.
local _, MSUF = ...
local Castbars = MSUF.Require("MSUF", "Castbars/MSUF_CastbarPreviewEdit.lua").Castbars
local Config = Castbars.Config
local Anchors = Castbars.Anchors
local Core = Castbars.Core
local PreviewEdit = Castbars.PreviewEdit
local Previews = Castbars.Previews
local PublicAPI = Castbars.PublicAPI
local Utils = Castbars.Utils
local Publish = PublicAPI.Publish

local UNIT_CONFIG = MSUF.Castbars.UNIT_CASTBAR
local CASTBAR_PREVIEW_DRAG_APPLY_INTERVAL = 0.05

local GeneralDB = Utils.EnsureCastbarGeneralDB

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

--- Kernel Util and the Edit Mode shell (EM2, the nudge target, the castbar
--- popup, the undo history) load before this file. MSUF_EM_UndoBeforeChange
--- stays late-bound: the external Edit Mode provider hooks it at run time.
local FILE = "Castbars/MSUF_CastbarPreviewEdit.lua"
local Require = MSUF.Require
local Round = Require("MSUF_RoundOffset", FILE)
local UndoBeginChange = Require("MSUF_EM_UndoBeginChange", FILE)
local UndoCommitChange = Require("MSUF_EM_UndoCommitChange", FILE)
local OpenCastbarPositionPopup = Require("MSUF_OpenCastbarPositionPopup", FILE)
local SyncCastbarPositionPopup = Require("MSUF_SyncCastbarPositionPopup", FILE)
local EM2 = MSUF.Optional("MSUF_EM2")
local SetPreviewNudgeTarget = Require("MSUF_EM2_SetPreviewNudgeTarget", FILE)

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

--- Castbars/MSUF_Castbars_Core.lua loads before this file in every TOC and
--- owns the apply and sync (reanchor, visuals, edit info, popup); the per-step
--- fallback that stood here never ran. Late-bound: the menu preview wraps it.
local function ApplyUnitAndSync(unit)
    Core.ApplyCastbarUnitAndSync(unit)
end

local function PositionPreviewOnly(unit)
    local position = Previews.PositionCastbarPreviewUnit
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

local function PulsePreview(unit)
    if not MSUF_UnitEditModeActive then
        return
    end

    local config = UNIT_CONFIG[unit]
    local setTestMode = config and Previews[config.test:sub(6)]
    if type(setTestMode) ~= "function" then
        return
    end

    setTestMode(true, true)

    local timers = PreviewEdit.CastbarPreviewPulseTimers
    if not timers then
        timers = {}
        PreviewEdit.CastbarPreviewPulseTimers = timers
    end

    if type(timers[unit]) == "table" then
        timers[unit].cancelled = true
    end

    local token = {}
    timers[unit] = token

    C_Timer.After(8, function()
        if token.cancelled or timers[unit] ~= token or not MSUF_UnitEditModeActive or InCombat() then
            return
        end

        local general = GeneralDB()
        local testModeKey = (unit == "player" and "playerCastbarTestMode")
            or (unit == "target" and "targetCastbarTestMode")
            or (unit == "focus" and "focusCastbarTestMode")
            or (unit == "arena" and "arenaCastbarTestMode")
            or "bossCastbarTestMode"

        if general[testModeKey] then
            return
        end

        local popup = EM2 and EM2.CastPopup
        if popup and popup.IsOpen and popup:IsOpen() then
            return
        end

        timers[unit] = nil
        setTestMode(false, true)
    end)
end

local function RegisterPreviewNudgeTarget(frame, unit, config)
    SetPreviewNudgeTarget({
        frame = frame,
        IsActive = function()
            return MSUF_UnitEditModeActive and frame.IsShown and frame:IsShown()
        end,
        Nudge = function(_, deltaX, deltaY)
            if not MSUF_UnitEditModeActive or InCombat() then
                return
            end

            local general = GeneralDB()
            Require("MSUF_EM_UndoBeforeChange", FILE)("castbar", unit, true)

            general[config.x] = Round(OffsetX(general, config) + (deltaX or 0))
            general[config.y] = Round(OffsetY(general, config) + (deltaY or 0))

            Config.Invalidate()
            ApplyUnitAndSync(unit)
        end,
    })
end

local function UsesWidthSource(general, unit)
    local widthSourceKey = Anchors.GetCastbarWidthSourceKey and Anchors.GetCastbarWidthSourceKey(unit)
    local normalize = Anchors.NormalizeCastbarWidthSource or Anchors.NormalizePlayerCastbarWidthSource
    local widthSource = widthSourceKey and general[widthSourceKey]

    if type(normalize) == "function" then
        return normalize(widthSource) ~= nil
    end

    return widthSource == "unitframe" or widthSource == "essential" or widthSource == "utility"
end

--- One preview press's drag follow (a new closure per press, as before):
--- move or size the bar's settings with the cursor, snapped in Edit Mode.
local function PreviewDragUpdate(unit, config)
    return function(dragFrame, elapsed)
        if not dragFrame.isDragging then
            MSUF.EditModeKinds.Detach(dragFrame)
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

            dragFrame._msufCastbarHistoryDrag = UndoBeginChange("castbar", unit, "Move") == true
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
            local snap = EM2 and EM2.Snap

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

            local toBar = dragFrame._msufDragToBarScale or 1
            liveGeneral[config.x] = Round((dragFrame.dragStartOffsetX or 0) + snappedDeltaX * toBar)
            liveGeneral[config.y] = Round((dragFrame.dragStartOffsetY or 0) + snappedDeltaY * toBar)
        end

        Config.Invalidate()
        if dragFrame.dragMode == "MOVE" and PositionPreviewOnly(unit) then
            dragFrame._msufPreviewApplyAcc = CASTBAR_PREVIEW_DRAG_APPLY_INTERVAL
            dragFrame._msufPopupSyncAcc = (tonumber(dragFrame._msufPopupSyncAcc) or 0) + (tonumber(elapsed) or 0)
            if dragFrame._msufPopupSyncAcc >= CASTBAR_PREVIEW_DRAG_APPLY_INTERVAL then
                dragFrame._msufPopupSyncAcc = 0
                SyncCastbarPositionPopup(unit)
            end
        else
            ThrottledApplyUnitAndSync(dragFrame, unit, elapsed)
        end
    end
end

--- The preview's OnMouseDown: the Edit Mode nudge target, the right-click
--- position popup and the start of a move or size drag.
local function PreviewMouseDown(unit, config)
    return function(self, button)
        if MSUF_UnitEditModeActive then
            RegisterPreviewNudgeTarget(self, unit, config)
        end

        if button == "RightButton" then
            if MSUF_UnitEditModeActive
                and not MSUF_EditModeSizing
                and not InCombat()
            then
                OpenCastbarPositionPopup(unit, self)
            end
            return
        end

        if button ~= "LeftButton" or not MSUF_UnitEditModeActive or InCombat() then
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
            --- The offsets are SetPoint offsets in this bar's own (MSUF Frame
            --- Scale) units; the cursor delta is in UIParent units.
            self._msufDragToBarScale = frameScale > 0 and uiScale / frameScale or 1
            local left = self:GetLeft() or 0
            local right = self:GetRight() or 0
            local top = self:GetTop() or 0
            local bottom = self:GetBottom() or 0

            self._snapStartCX = (left + right) * 0.5 * frameScale / uiScale
            self._snapStartCY = (top + bottom) * 0.5 * frameScale / uiScale
            self._snapHW = (right - left) * 0.5 * frameScale / uiScale
            self._snapHH = (top - bottom) * 0.5 * frameScale / uiScale
        end

        MSUF.EditModeKinds.Attach("castbar", self, PreviewDragUpdate(unit, config))
    end
end

--- The preview's OnMouseUp: end the drag, apply it and commit its undo step;
--- a click without a drag opens the position popup.
local function PreviewMouseUp(unit)
    return function(self, button)
        if button ~= "LeftButton" then
            return
        end

        local moved = self.dragMoved
        if self.isDragging then
            self.isDragging = false
            MSUF.EditModeKinds.Detach(self)
            self._msufPreviewApplyAcc = nil
            self._msufPopupSyncAcc = nil

            local snap = EM2 and EM2.Snap
            if snap and snap.HideGuides then
                snap.HideGuides()
            end
        end

        PulsePreview(unit)
        if moved then
            Config.Invalidate()
            ApplyUnitAndSync(unit)
        end
        if self._msufCastbarHistoryDrag then
            self._msufCastbarHistoryDrag = nil
            UndoCommitChange()
        end

        if not moved
            and MSUF_UnitEditModeActive
            and not InCombat()
        then
            OpenCastbarPositionPopup(unit, self)
        end
    end
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

    frame:SetScript("OnMouseDown", PreviewMouseDown(unit, config))
    frame:SetScript("OnMouseUp", PreviewMouseUp(unit))
end

PreviewEdit.SetupCastbarPreviewEditHandlers = SetupCastbarPreviewEditHandlers
