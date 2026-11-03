-- Group preview view owner.
local _, MSUF = ...
local M = MSUF.MSUF2
local RequireFields = M.PreviewContracts.RequireFields
local T = M.Theme
local Specs = M.GroupPreviewSpecs
local PreviewHelpers = M.PreviewHelpers
local GFZoomPan = M.GroupPreviewZoomPan
local Fallbacks = M.Fallbacks
local WHITE8X8 = Specs.WHITE8X8
local Tr = M.Tr
local floor = math.floor
local Chrome = RequireFields("GroupView.Chrome", M.GroupPreviewChrome,
    "ApplyGroupChrome ApplyGroupCompactPresentation CreatePreviewAnimationButton CreatePreviewRoleButton "
    .. "RegisterGroupPreviewControl ShowExpandedHeader TrText UpdateHint")
local ApplyGroupChrome = Chrome.ApplyGroupChrome
local ApplyGroupCompactPresentation = Chrome.ApplyGroupCompactPresentation
local CreatePreviewAnimationButton = Chrome.CreatePreviewAnimationButton
local CreatePreviewRoleButton = Chrome.CreatePreviewRoleButton
local RegisterGroupPreviewControl = Chrome.RegisterGroupPreviewControl
local ShowExpandedHeader = Chrome.ShowExpandedHeader
local TrText = Chrome.TrText
local UpdateHint = Chrome.UpdateHint
local Model = RequireFields("GroupView.Model", M.GroupPreviewModel, "CurrentScope PreviewScopeLabel")
local CurrentScope = Model.CurrentScope
local PreviewScopeLabel = Model.PreviewScopeLabel

local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Menu2/GroupPreview_View")
local View = {}
function View.Frame(parent, ctx, Deps)
    local width = (ctx.width or 720) - 28
    local layerW = 104
    local box = PixelLayoutRegion(CreateFrame("Frame", nil, parent, T.Template()))
    local previewControls = {}
    local runtimePageContext = { key = ctx and ctx.key }
    local function RegisterPreviewControl(widget, semanticPath, label, kind, classification, extra)
        if not widget then return widget end
        if widget._msuf2GroupPreviewControlOwner ~= box then
            widget._msuf2GroupPreviewControlOwner = box
            previewControls[#previewControls + 1] = widget
        end
        widget._msuf2GroupPreviewSemanticPath = semanticPath
        widget._msuf2GroupPreviewLabel = label
        widget._msuf2GroupPreviewKind = kind
        widget._msuf2GroupPreviewClassification = classification
        widget._msuf2GroupPreviewExtra = extra
        return RegisterGroupPreviewControl(widget, semanticPath, label, kind, classification, extra)
    end
    box._msuf2RegisterGroupPreviewControl = RegisterPreviewControl
    function box:RegisterRuntimeControlsForPage(pageKey)
        local page = M.GroupPage
        if not (page and page.RegisterControl) then return false end
        runtimePageContext.key = pageKey
        for i = 1, #previewControls do
            local widget = previewControls[i]
            page.RegisterControl(widget, runtimePageContext,
                "preview." .. tostring(widget._msuf2GroupPreviewSemanticPath),
                widget._msuf2GroupPreviewLabel,
                widget._msuf2GroupPreviewKind,
                widget._msuf2GroupPreviewClassification,
                widget._msuf2GroupPreviewExtra)
        end
        return true
    end
    local chrome = ApplyGroupChrome(box, "outer", T.colors.panel or T.colors.panel2, T.colors.borderSoft or T.colors.border)
        or { title = T.colors.title or T.colors.text, layerHeader = T.colors.muted }
    box:SetSize(width, 358)
    box._msufStaticH = 358
    box.ApplyPinnedPreviewPresentation = function(self, pinned)
        if pinned then
            if PreviewHelpers.SwitchCompactZoomMode then PreviewHelpers.SwitchCompactZoomMode(self, false, 1.50) end
            ShowExpandedHeader(self)
            if self._msuf2LayersButton then self._msuf2LayersButton:Hide() end
        end
        local shade, line = PreviewHelpers.EnsurePinnedHeader(self)
        if M.PreviewSelectionBar then M.PreviewSelectionBar.SetShown(self, true) end
        if self.ApplyDockedPreviewLayout then self:ApplyDockedPreviewLayout(12) end
        if self._footer then self._footer:SetShown(not pinned) end
        PreviewHelpers.PaintPinnedHeader(shade, line, T.colors or {}, pinned)
        UpdateHint(self)
        if not pinned and self._msuf2CompactPreview then ApplyGroupCompactPresentation(self, true) end
    end
    box.ApplyCompactPreviewPresentation = ApplyGroupCompactPresentation
    if parent and parent.GetFrameLevel and box.SetFrameLevel then box:SetFrameLevel((parent:GetFrameLevel() or 0) + 2) end
    local title = T.Font(box, "GameFontNormal", "", chrome.title or T.colors.title or T.colors.text)
    title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -8)
    T.SetTranslatedText(title, string.format(TrText("%s - %s"), TrText("Group Frame Preview"), PreviewScopeLabel(CurrentScope())))
    box._title = title
    local hint = T.Font(box, "GameFontDisableSmall", "", T.colors.muted)
    hint:SetPoint("LEFT", title, "RIGHT", 12, 0)
    box._hint = hint
    return {
        ctx = ctx, R = Deps, width = width, layerW = layerW, box = box, chrome = chrome,
        RegisterPreviewControl = RegisterPreviewControl,
    }
end
function View.Stage(state)
    local Deps, box, RegisterPreviewControl = state.R, state.box, state.RegisterPreviewControl
    -- The stage is re-anchored against the selection bar by
    -- ApplyDockedPreviewLayout once the layer rail exists.
    local stage = PixelLayoutRegion(CreateFrame("Frame", nil, box, T.Template()))
    stage:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -30)
    stage:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)
    stage._msuf2PreviewCanvasUnderlay = box
    ApplyGroupChrome(stage, "canvas", { 0.020, 0.039, 0.071, 0.92 }, T.colors.borderSoft)
    if stage.SetClipsChildren then stage:SetClipsChildren(true) end
    stage:EnableMouse(true)
    stage:EnableMouseWheel(true)
    if stage.SetPropagateMouseWheel then stage:SetPropagateMouseWheel(false) end
    box._stage = stage
    PreviewHelpers.BuildZoomBar(box, stage, {
        template = T.Template(),
        texture = WHITE8X8,
        T = T,
        themeReadout = true,
        fieldPrefix = "_",
        wheelField = "_zoomWheel",
        CreateZoomButton = GFZoomPan.CreateButton,
        Tr = Tr,
        StepZoom = GFZoomPan.Step or Fallbacks.Noop,
        SetZoom = GFZoomPan.SetZoom or Fallbacks.Noop,
        StartPan = Deps.Interaction.StartPan,
        StopPan = Deps.Interaction.StopPan,
        fitReason = "GROUP_PREVIEW_ZOOM_FIT",
        oneReason = "GROUP_PREVIEW_ZOOM_1TO1",
        lockButton = true,
        defaultLocked = true,
        lockReason = "GROUP_PREVIEW_ZOOM_LOCK",
        unlockReason = "GROUP_PREVIEW_ZOOM_UNLOCK",
    })
    box._msuf2ZoomCommand = box._msuf2ZoomCommand
        or (PreviewHelpers.BuildZoomCommand and PreviewHelpers.BuildZoomCommand(box, GFZoomPan, "GROUP_PREVIEW_SEARCH_ZOOM"))
    RegisterPreviewControl(box._zoomBar, "zoom.surface", "Group Preview Zoom", "slider", "ephemeral", {
        help = "Sets the Group preview zoom percentage; Fit and 1:1 remain available as exact actions.",
        command = box._msuf2ZoomCommand,
    })
    local zoomControls = {
        { "_zoomOutButton", "zoom.out", "Zoom out" },
        { "_zoomFitButton", "zoom.fit", "Fit preview" },
        { "_zoomOneButton", "zoom.one_to_one", "Pixel preview" },
        { "_zoomInButton", "zoom.in", "Zoom in" },
        { "_zoomHelpButton", "zoom.help", "Preview controls help" },
        { "zoomLockButton", "zoom.lock", "Lock preview zoom" },
    }
    for i = 1, #zoomControls do
        local info = zoomControls[i]
        RegisterPreviewControl(box[info[1]], info[2], info[3], "button", "ephemeral")
    end
    if PreviewHelpers.EnsurePreviewControlsHint then
        local controlsHint = PreviewHelpers.EnsurePreviewControlsHint(box, stage, { M = M, T = T, Tr = Tr })
        RegisterPreviewControl(controlsHint and controlsHint._close, "hint.dismiss", "Dismiss preview tip", "button", "ephemeral")
    end
    Deps.Interaction.ZoomWheel = box._zoomWheel or Deps.Interaction.ZoomWheel
    CreatePreviewAnimationButton(box, RegisterPreviewControl)
    CreatePreviewRoleButton(box, RegisterPreviewControl)
    local bounds = PixelLayoutRegion(CreateFrame("Frame", nil, stage, T.Template()))
    PixelLayoutRegion(bounds, "SetBackdrop", { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    bounds:SetBackdropColor(0, 0, 0, 0)
    -- Bounds mark a measurement, not a problem; cyan matches the Unit preview.
    bounds:SetBackdropBorderColor(0.25, 0.75, 0.88, 0.92)
    box._bounds = bounds
    state.stage, state.bounds = stage, bounds
end
function View.Mock(state)
    local Deps, box, stage, bounds, RegisterPreviewControl = state.R, state.box, state.stage, state.bounds, state.RegisterPreviewControl
    local mock = PixelLayoutRegion(CreateFrame("Frame", nil, stage, T.Template()), true)
    PixelLayoutRegion(mock, "SetBackdrop", { bgFile = WHITE8X8 })
    mock:SetBackdropColor(0, 0, 0, 0)
    mock:SetBackdropBorderColor(0, 0, 0, 0)
    mock:EnableMouse(true)
    mock:EnableMouseWheel(true)
    if mock.SetPropagateMouseWheel then mock:SetPropagateMouseWheel(false) end
    mock:SetScript("OnMouseWheel", Deps.Interaction.ZoomWheel)
    mock:SetScript("OnMouseDown", function(_, button) Deps.Interaction.StartPan(stage, box, button, true) end)
    mock:SetScript("OnMouseUp", function()
        if stage._msufGFPreviewPanning then Deps.Interaction.StopPan(stage) end
    end)
    -- Stands in for the live frame's MSUFSpec.scope: the shared preview border
    -- helper puts group mocks in the group foreground band (Layers.BorderOffset).
    mock._msufPreviewGroupScope = true
    box._mock = mock
    box.mock, mock.bounds = mock, bounds
    function box:PanExact(dx, dy)
        if M.IsConfigCombatLocked and M.IsConfigCombatLocked() then return false, "combat-locked" end
        if self._msufGFNativePreviewDisposed then return false, "preview-disposed" end
        if not (self.IsShown and self:IsShown() and (not self.IsVisible or self:IsVisible())) then return false, "preview-not-visible" end
        if (self._stage and self._stage._msufGFPreviewPanning) or (self._dragFrame and self._dragFrame._handle) then return false, "preview-busy" end
        if not GFZoomPan.NudgePan then return false, "pan-api-unavailable" end
        return GFZoomPan.NudgePan(self, dx, dy)
    end
    box._msuf2PanCommand = box._msuf2PanCommand or (PreviewHelpers.BuildPanCommand and PreviewHelpers.BuildPanCommand(
        box, GFZoomPan,
        function(dx, dy)
            if not (M.GroupPreview and M.GroupPreview.Pan) then return false end
            return M.GroupPreview.Pan(dx, dy)
        end,
        { previewSurface = "group" }
    ))
    RegisterPreviewControl(mock, "canvas", "Group preview canvas", "canvas", "ephemeral", {
        help = "Pans this exact Group preview canvas by an explicit X/Y delta.",
        command = box._msuf2PanCommand,
    })
    -- The complete cell is an engine frame: an isolated scene hangs on the mock and Render.RenderCell aliases its regions
    -- (_health, _power, _nameFS, ...) onto the mock for the handles. The scene root is the kit host of this preview:
    -- Activate/Deactivate follow the box's visibility. It is built by the first paint (Render.RenderCell), not here:
    -- a preview that is never shown, or a host without the engine, never builds a scene.
    state.mock = mock
end
--- The selection bar reads and writes the same stored offsets the handles drag.

M.GroupPreviewView = View
