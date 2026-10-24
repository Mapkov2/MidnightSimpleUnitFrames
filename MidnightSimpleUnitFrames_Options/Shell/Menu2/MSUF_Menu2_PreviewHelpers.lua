local _, MSUF = ...
local M = MSUF.MSUF2
local H = M.PreviewHelpers or {}
M.PreviewHelpers = H
M.ClassPowerPreview = M.ClassPowerPreview or {}

-- Preview onboarding state and per-profile interaction cadence.
-- Keep these readers independent of visual construction and the scene modules.
local PREVIEW_MOVE_HINT_TARGET = 3
function H.PreviewMoveHintState()
    return M.GetPersistentMenuStateTable("previewMoveHintState")
end
function H.PreviewMoveHintRemaining()
    local state = H.PreviewMoveHintState()
    local done = tonumber(state and state.count) or 0
    local remaining = PREVIEW_MOVE_HINT_TARGET - done
    if remaining < 0 then return 0 end
    return remaining
end
function H.NotePreviewCanvasMoved(button)
    if button ~= "LeftButton" and button ~= "RightButton" and button ~= "MiddleButton" then
        return H.PreviewMoveHintRemaining()
    end
    local state = H.PreviewMoveHintState()
    if type(state) ~= "table" then return 0 end
    local done = tonumber(state.count) or 0
    if done >= PREVIEW_MOVE_HINT_TARGET then return 0 end
    state.count = done + 1
    M.SavePersistentMenuState()
    return H.PreviewMoveHintRemaining()
end

local function PreviewDragCueEnabled()
    local db = MSUF_DB
    local general = db and db.general
    return type(general) ~= "table" or general.previewDragHintAnimationEnabled ~= false
end
local function PreviewDragCueIsNewProfile()
    local db = MSUF_DB
    local general = db and db.general
    return type(general) == "table" and general._msufPreviewDragHintExperienced == false
end
-- A SavedVariables string without a namespace export: the active profile's name.
local function ActiveProfileName()
    return tostring(MSUF_ActiveProfile or "")
end
local function PreparePreviewMoveCueOwner(owner)
    if not owner then return end
    local profile = ActiveProfileName()
    if owner._msuf2PreviewDragCueProfile ~= profile then
        owner._msuf2PreviewDragCueProfile = profile
        owner._msuf2PreviewDragCueShownForOpen = nil
        owner._msuf2PreviewHandleTooltipShownForOpen = nil
    end
    if owner._msuf2PreviewDragCueLifecycleHooked or not owner.HookScript then return end
    owner._msuf2PreviewDragCueLifecycleHooked = true
    owner:HookScript("OnShow", function(self)
        self._msuf2PreviewDragCueShownForOpen = nil
        self._msuf2PreviewHandleTooltipShownForOpen = nil
        self._msuf2PreviewDragCueProfile = ActiveProfileName()
    end)
end
function H.NotePreviewElementMoved()
    local db = MSUF_DB
    local general = db and db.general
    if type(general) == "table" then general._msufPreviewDragHintExperienced = true end
    H._previewDragCueSessionShown = true
end
function H.ShouldShowPreviewHandleTooltip(owner)
    PreparePreviewMoveCueOwner(owner)
    if PreviewDragCueIsNewProfile() then
        if owner and owner._msuf2PreviewHandleTooltipShownForOpen == true then return false end
        if owner then owner._msuf2PreviewHandleTooltipShownForOpen = true end
    elseif H._previewHandleTooltipSessionShown == true then
        return false
    end
    H._previewHandleTooltipSessionShown = true
    return true
end

H._HintState = {
    DragCueEnabled = PreviewDragCueEnabled, IsNewProfile = PreviewDragCueIsNewProfile,
    PrepareOwner = PreparePreviewMoveCueOwner,
}
