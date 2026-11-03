--- Group preview handle, drag, and nudge helpers.
---
--- Native owns the preview host. This module owns interactive handles and the
--- save/write behavior behind drag and keyboard nudges.
local _, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local FILE = "Menu2/GroupPreview_Handles"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local Handles = M.GroupPreviewHandles or {}
M.GroupPreviewHandles = Handles
local RequireFields = M.PreviewContracts.RequireFields
local max = math.max

local HandleStorage = RequireFields("GroupHandles.HandleStorage", M.GroupPreviewHandleStorage,
    "BindSelection BindRefresh BindPositionWriters BindNudge "
    .. "BindExactNudge ManagerCombatLocked RequestBoxRefresh SelectSpellAura")
local HandleDrag = RequireFields("GroupHandles.HandleDrag", M.GroupPreviewHandleDrag, "BindTextDrag BindDrag BindDragStart ResolveTextDragPixelDelta")
local HandleView = RequireFields("GroupHandles.HandleView", M.GroupPreviewHandleView,
    "BindHandleFactory CreateLayerHandles BindSpellDrop CreateTextHandles BuildBundle InteractionLevel")
local InteractionLevel = HandleView.InteractionLevel
local ManagerCombatLocked = HandleStorage.ManagerCombatLocked
Handles._ResolveTextDragPixelDelta = HandleDrag.ResolveTextDragPixelDelta
function Handles.Install(box, deps)
    if not box then return nil end
    local Config = RequireFields("GroupHandles.Config", deps.Config,
        "Round ResolveAnchor PointOffset HandleOffset CurrentStatusSpec CurrentSpellConfig StatusLabel "
        .. "OffsetToConfig")
    local Selection = RequireFields("GroupHandles.Selection", deps.Selection,
        "HandleText HandleOffsets RefreshHandleSelection Helpers OpenGFSection")
    local Interaction = RequireFields("GroupHandles.Interaction", deps.Interaction,
        "StartPan StopPan ZoomWheel")
    local ns = MSUF
    -- The old monolith closed over the native preview mock. After splitting the
    -- file, bind it explicitly so preview handles never fall back to UIParent.
    local mock = box._mock or box
    local dragParent = box._stage or box
    local st = {
        box = box, M = M, MSUF = ns, mock = mock, dragParent = dragParent,
        H = Selection.Helpers, T = M.Theme, PreviewHelpers = M.PreviewHelpers,
        RegisterPreviewControl = deps.RegisterPreviewControl,
        OpenSection = Selection.OpenGFSection,
        WHITE8X8 = deps.Specs.WHITE8X8,
        AuraDurationBarColor = ns.MSUF_Auras3.GetDurationBarColor,
    }
    st.TR, st.UpdateHint = M.Tr, M.GroupPreviewChrome.UpdateHint
    st.Round = Config.Round
    st.ResolveAnchor = Config.ResolveAnchor
    st.PointOffset = Config.PointOffset
    st.HandleOffset = Config.HandleOffset
    st.CurrentStatusSpec = Config.CurrentStatusSpec
    st.CurrentSpellConfig = Config.CurrentSpellConfig
    st.StatusLabel = Config.StatusLabel
    st.OffsetToConfig = Config.OffsetToConfig
    st.HandleText = Selection.HandleText
    st.HandleOffsets = Selection.HandleOffsets
    st.RefreshHandleSelection = Selection.RefreshHandleSelection
    st.StartPan = Interaction.StartPan
    st.StopPan = Interaction.StopPan
    st.ZoomWheel = Interaction.ZoomWheel
    box._handles = {}
    box._handleList = {}
    local dragFrame = PixelLayoutRegion(CreateFrame("Frame", nil, dragParent), true)
    box._dragFrame = dragFrame
    dragFrame:SetAllPoints(dragParent)
    dragFrame:EnableMouse(true)
    dragFrame:EnableMouseWheel(true)
    if dragFrame.SetPropagateMouseWheel then dragFrame:SetPropagateMouseWheel(false) end
    dragFrame:SetScript("OnMouseWheel", st.ZoomWheel)
    if dragFrame.SetFrameLevel then
        dragFrame:SetFrameLevel(InteractionLevel(ns, mock, 2))
    end
    dragFrame:Hide()
    HandleStorage.BindSelection(st)
    HandleStorage.BindRefresh(st)
    HandleDrag.BindTextDrag(st)
    HandleStorage.BindPositionWriters(st)
    HandleStorage.BindNudge(st)
    HandleStorage.BindExactNudge(st)
    HandleDrag.BindDrag(st)
    HandleDrag.BindDragStart(st)
    HandleView.BindHandleFactory(st)
    HandleView.CreateLayerHandles(st)
    HandleView.BindSpellDrop(st)
    HandleView.CreateTextHandles(st)
    return HandleView.BuildBundle(st)
end
local function VisibleGroupPreview()
    local found
    local previews = M._gfNativePreviews
    for i = 1, #(previews or {}) do
        local box = previews[i]
        local visible = box
            and not box._msufGFNativePreviewDisposed
            and box.IsShown and box:IsShown()
            and (not box.IsVisible or box:IsVisible())
        if visible then
            if found and found ~= box then return nil, "ambiguous-preview" end
            found = box
        end
    end
    if not found then return nil, "preview-not-visible" end
    return found
end
-- UpdateSpellDropTarget runs every frame while a spell tile is dragged: these entry points stay a single
-- VisibleGroupPreview call plus the method call, with no shared dispatch helper in between.
M.GroupPreview = M.GroupPreview or {}
function M.GroupPreview.UpdateSpellDropTarget(active, spellLabel)
    local box, reason = VisibleGroupPreview()
    if not box then return false, reason end
    if type(box.SetSpellDropTarget) ~= "function" then return false, "spell-drop-api-unavailable" end
    return box:SetSpellDropTarget(active == true, spellLabel)
end
function M.GroupPreview.DropSpellIndicatorAtCursor(specKey, auraName)
    local box, reason = VisibleGroupPreview()
    if not box then return false, reason end
    if type(box.DropSpellIndicatorAtCursor) ~= "function" then return false, "spell-drop-api-unavailable" end
    return box:DropSpellIndicatorAtCursor(specKey, auraName)
end
function M.GroupPreview.NudgeHandle(handleKey, dx, dy)
    local box, reason = VisibleGroupPreview()
    if not box then return false, reason end
    if type(box.NudgeHandleExact) ~= "function" then return false, "nudge-api-unavailable" end
    return box:NudgeHandleExact(handleKey, dx, dy)
end
function M.GroupPreview.Pan(dx, dy)
    local box, reason = VisibleGroupPreview()
    if not box then return false, reason end
    if type(box.PanExact) ~= "function" then return false, "pan-api-unavailable" end
    return box:PanExact(dx, dy)
end
ExportPublic("MSUF_GroupPreview_NudgeHandle", function(handleKey, dx, dy)
    return M.GroupPreview.NudgeHandle(handleKey, dx, dy)
end)
ExportPublic("MSUF_GroupPreview_Pan", function(dx, dy)
    return M.GroupPreview.Pan(dx, dy)
end)
