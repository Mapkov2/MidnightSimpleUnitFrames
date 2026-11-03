--- Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View.lua
--- Cold-path unitframe preview view.
---
--- Builds the preview host and composes its owners. Selection/write policies,
--- input gestures and rendering each live in their dedicated module.
local _, MSUF = ...
local FILE = "Menu2/UnitPreview_View"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local ExportPublic = MSUF.ExportPublic
local floor = math.floor
local TEX_W8 = "Interface\\Buttons\\WHITE8X8"
local Preview = MSUF.UFPreview or {}
MSUF.UFPreview = Preview
ExportPublic("MSUF_UFPreview", Preview)
local PreviewCore = MSUF.UFPreviewCore or {}
local PreviewCastbar = MSUF.UFPreviewCastbar or {}
local PreviewAuras = MSUF.UFPreviewAuras or {}
local PreviewRuntime = MSUF.UFPreviewRuntime or {}
local PreviewZoomPan = MSUF.UFPreviewZoomPan or {}
local M2 = MSUF.MSUF2
local PreviewHelpers = M2.PreviewHelpers or {}
local ViewHandles = MSUF.UFPreviewViewHandles or {}
local ViewChrome = MSUF.UFPreviewViewChrome or {}
local TR = ViewChrome.TR
local RequireFields = M2.PreviewContracts.RequireFields
local Selection = RequireFields("UnitView.Selection", MSUF.UFPreviewSelection, "SelectHandle RefreshVisuals NudgeSelectedDelta")
local Input = RequireFields("UnitView.Input", MSUF.UFPreviewInput, "MakeHandle ArrowKeyDown DragUpdate ReleaseKeyboard")
local SelectPreviewHandle, RefreshHandleSelectionVisuals = Selection.SelectHandle, Selection.RefreshVisuals
local NudgeSelectedHandleDelta = Selection.NudgeSelectedDelta
local MakeHandle, PreviewArrowKeyDown = Input.MakeHandle, Input.ArrowKeyDown
local HandleDragUpdate, ReleasePreviewKeyboard = Input.DragUpdate, Input.ReleaseKeyboard
local PreviewModel = Preview.Model or {}
local Fallbacks = M2.Fallbacks or {}
local CastbarOffsetFields = PreviewCastbar.OffsetFields
local RuntimeVisualScaleForPreviewKey = PreviewRuntime.VisualScaleForPreviewKey or Fallbacks.One
local UpdateHandleHint = ViewChrome.UpdateHandleHint
local RequestPreviewLayoutRefresh = ViewChrome.RequestPreviewLayoutRefresh
local OpenPreviewHandleSettings = ViewHandles.OpenPreviewHandleSettings
local MenuTheme, RoundOffset = PreviewCore.MenuTheme, PreviewCore.RoundOffset
local StartPreviewPan, StopPreviewPan
-- Boss units exist only where the client model says so: every Mainline client
-- and Mists among the Classic ones. Render draws the boss target marker only
-- when its handle exists, so a client without boss units never shows one.
local HAS_BOSS_UNITS = MSUF.Client.SupportsUnit("boss1")

local ApplyPreviewBackdrop = PreviewCore.ApplyBackdrop
local STATUS_PREVIEW = (MSUF.UFPreviewSpecs and MSUF.UFPreviewSpecs.StatusPreview) or {}
local PREVIEW_LAYERS = (MSUF.UFPreviewSpecs and MSUF.UFPreviewSpecs.PreviewLayers) or {}
local ZOOM_MIN = tonumber(PreviewZoomPan.MIN) or 0.35
if PreviewZoomPan.Configure then PreviewZoomPan.Configure({ Preview = Preview, T = M2.Theme, TR = TR, TEX_W8 = TEX_W8,
    UpdateHandleHint = UpdateHandleHint }) end
local function ZoomOrOne(v) return tonumber(v) or 1 end
local ClampPreviewZoom = PreviewZoomPan.Clamp or ZoomOrOne
local UpdatePreviewZoomControls = PreviewZoomPan.UpdateControls or Fallbacks.Noop
local SetPreviewZoom = PreviewZoomPan.SetZoom or Fallbacks.Noop
local StepPreviewZoom = PreviewZoomPan.Step or Fallbacks.Noop
StartPreviewPan = PreviewZoomPan.Start or StartPreviewPan
StopPreviewPan = PreviewZoomPan.Stop or StopPreviewPan
-- BuildPreview runs a sequence of stages on one box: frame, chrome, layer rail, selection bar, the mock
-- frame (health, class power, overlays, castbar), drag handles and scripts. The stages create their
-- widgets in the order the single builder did, so the layout is unchanged. They share a small state
-- table (`s`) and live on one table so the main chunk keeps its local budget.
local BoxBuild = {}
function BoxBuild.Frame(parent, panel, width, height)
    local sideW = 104
    local T = MenuTheme()
    local colors = (T and T.colors) or {}
    local box = PixelLayoutRegion(CreateFrame("Frame", nil, parent, "BackdropTemplate"))
    box:SetSize(width or 632, height or 228)
    local chrome = PreviewHelpers.ApplyPreviewChrome and PreviewHelpers.ApplyPreviewChrome(box, "outer", T, ApplyPreviewBackdrop)
    if not chrome then
        ApplyPreviewBackdrop(box, colors.panel or { 0.035, 0.067, 0.114, 0.54 }, colors.borderSoft or { 0.086, 0.149, 0.227, 0.46 })
        chrome = { title = colors.title or colors.text, layerHeader = colors.muted }
    end
    box._msufStaticH = height or 228
    box._msufPanel = panel
    box.ApplyPinnedPreviewPresentation = function(self, pinned, opts)
        if pinned then
            if PreviewHelpers.SwitchCompactZoomMode then PreviewHelpers.SwitchCompactZoomMode(self, false, 1.50) end
            -- The pinned header reuses title/hint; compact mode may have
            -- hidden them and must never leave the floating header empty.
            if self.title then self.title:Show() end
            if self.hint then self.hint:Show() end
            ViewChrome.SetUnitCanvasToolsShown(self, true, self.animateCombatButton)
            ViewChrome.LayoutUnitHeaderControls(self, false)
            if self._msuf2LayersButton then self._msuf2LayersButton:Hide() end
        end
        ViewChrome.ApplyUnitPinnedPresentation(self, pinned, opts, sideW)
        if not pinned and self._msuf2CompactPreview then
            ViewChrome.ApplyUnitCompactPresentation(self, true, sideW)
        end
    end
    box.ApplyCompactPreviewPresentation = function(self, compact)
        ViewChrome.ApplyUnitCompactPresentation(self, compact, sideW)
    end
    function box:RequestRefresh(reason)
        local preview = MSUF.UFPreview or Preview
        if type(preview) == "table" then
            if self:IsShown() then preview.active = self end
            if preview.RequestRefreshForBox then
                preview.RequestRefreshForBox(self, reason)
                return
            end
            if preview.Refresh and self:IsShown() and (not self.IsVisible or self:IsVisible()) then
                preview.Refresh(self, reason)
            end
        end
    end
    local title = PixelLayoutRegion(box:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
    title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -8)
    title:SetText(TR("Unit Frame Preview"))
    if T and T.StyleFontString then T.StyleFontString(title, chrome.title or colors.title or colors.text or { 1, 1, 1, 1 }, 1) end
    box.title = title
    local hint = PixelLayoutRegion(box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"))
    hint:SetPoint("LEFT", title, "RIGHT", 12, 0)
    hint:SetText(ViewChrome.DefaultPreviewHint())
    if T and T.StyleFontString then T.StyleFontString(hint, colors.muted or { 0.55, 0.60, 0.70, 0.90 }, 0) end
    box.hint = hint
    -- The canvas is anchored against the selection bar rather than the box, so
    -- whatever the chip rail does not need stays with the preview surface.
    local canvas = PixelLayoutRegion(CreateFrame("Frame", nil, box, "BackdropTemplate"))
    canvas:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -30)
    canvas:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)
    canvas._msuf2PreviewCanvasUnderlay = box
    if PreviewHelpers.ApplyPreviewChrome then
        PreviewHelpers.ApplyPreviewChrome(canvas, "canvas", T, ApplyPreviewBackdrop)
    else
        ApplyPreviewBackdrop(canvas, { 0.020, 0.039, 0.071, 0.92 }, colors.borderSoft or { 0.086, 0.149, 0.227, 0.38 })
    end
    if canvas.SetClipsChildren then canvas:SetClipsChildren(true) end
    canvas:EnableMouse(true)
    canvas:EnableMouseWheel(true)
    if canvas.SetPropagateMouseWheel then canvas:SetPropagateMouseWheel(false) end
    box.canvas = canvas
    return box, { sideW = sideW, T = T, colors = colors, chrome = chrome, canvas = canvas }
end
function BoxBuild.Chrome(box, s)
    local T, colors, chrome, canvas = s.T, s.colors, s.chrome, s.canvas
    PreviewHelpers.BuildZoomBar(box, canvas, {
        texture = TEX_W8,
        T = T,
        themeReadout = true,
        CreateZoomButton = PreviewZoomPan.CreateButton,
        Tr = TR,
        StepZoom = StepPreviewZoom,
        SetZoom = SetPreviewZoom,
        StartPan = StartPreviewPan,
        StopPan = StopPreviewPan,
        fitReason = "UNIT_PREVIEW_ZOOM_FIT",
        oneReason = "UNIT_PREVIEW_ZOOM_1TO1",
        lockButton = true,
        defaultLocked = true,
        lockReason = "UNIT_PREVIEW_ZOOM_LOCK",
        unlockReason = "UNIT_PREVIEW_ZOOM_UNLOCK",
    })
    -- Full Unit previews are 1:1 editors on first use. The page is constructed
    -- in Compact mode before the fresh-session auto-expand runs; seed the Full
    -- slot here so that technical restore cannot lock its first Fit scale
    -- (often about 50%) as though it were a prior user zoom. The shared box is
    -- built only once, so later manual/Fit choices remain untouched.
    if box._msuf2CompactZoomMode == nil and box._manualZoom == nil then
        box._manualZoom = 1.00
        box._msuf2ZoomLockDefaultPending = nil
    end
    if PreviewHelpers.EnsurePreviewControlsHint then
        PreviewHelpers.EnsurePreviewControlsHint(box, canvas, { M = M2, T = T, Tr = TR })
    end
    ViewChrome.CreatePreviewAnimationButton(box)
    -- Layer chips flow along the bottom instead of holding a fixed column: the
    -- canvas keeps the full box width, and the rail only claims the rows it
    -- actually fills. `box.sidebar` stays the field name because the compact
    -- popover and the colour page already address the layer surface by it.
    local sidebar = PixelLayoutRegion(CreateFrame("Frame", nil, box, "BackdropTemplate"))
    sidebar:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, 12)
    sidebar:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)
    sidebar:SetHeight(30)
    if PreviewHelpers.ApplyPreviewChrome then
        PreviewHelpers.ApplyPreviewChrome(sidebar, "sidebar", T, ApplyPreviewBackdrop)
    else
        ApplyPreviewBackdrop(sidebar, colors.coreShadow or colors.panel or { 0.020, 0.039, 0.071, 0.56 }, colors.borderSoft or { 0.086, 0.149, 0.227, 0.32 })
    end
    box.sidebar = sidebar
    local sHdr = PixelLayoutRegion(sidebar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"))
    sHdr:SetPoint("LEFT", sidebar, "LEFT", 10, 0)
    sHdr:SetText(TR("Preview Layers"))
    local layerHeaderColor = chrome.layerHeader or colors.muted or { 0.62, 0.70, 0.82, 0.82 }
    sHdr:SetTextColor(layerHeaderColor[1], layerHeaderColor[2], layerHeaderColor[3], layerHeaderColor[4] or 0.82)
    if T and T.StyleFontString then T.StyleFontString(sHdr, layerHeaderColor, 0) end
    box._msuf2LayerRailHeader = sHdr
    box.layerVisibility = {}
    box.layerButtons = {}
    s.sidebar = sidebar
end
function BoxBuild.LayerRail(box, s)
    local colors, chrome, sidebar, sideW = s.colors, s.chrome, s.sidebar, s.sideW
    local function UnitLayerAvailable(owner, key)
        return not (owner and owner.layerAvailable and owner.layerAvailable[key] == false)
    end
    local disabledLayerText = colors.dim or { 0.36, 0.46, 0.60, 0.82 }
    local function UnitLayerOn(owner, key) return UnitLayerAvailable(owner, key) and owner.layerVisibility[key] ~= false end
    --- Everything a layer change does once its flag has flipped. The chip click and the sample-effect hint share it,
    --- so hiding the sample layers from the hint is exactly a click on each of their chips.
    local function ApplyUnitLayerChange(owner, key)
        if key == "guides" then ViewChrome.SetPreviewGuidesEnabled(owner.layerVisibility[key] ~= false) end
        -- Hiding a layer changes the footprint, so auto-fit has to recenter.
        -- A zoom the user dialled in by hand is a deliberate viewport and
        -- must survive the toggle; _manualZoom is exactly that marker.
        if key ~= "guides" and owner._manualZoom == nil then
            owner._zoomPanX, owner._zoomPanY = 0, 0
        end
        for j = 1, #owner.layerButtons do owner.layerButtons[j]:refresh() end
        PreviewHelpers.RefreshSampleEffectHint(owner)
        -- Visibility is local preview state and does not need a full render.
        -- Apply it immediately; the queued refresh only recomputes footprint
        -- and fit geometry for layers such as Auras, Cast and Class Power.
        if PreviewCore.ApplyLayerVisibility then PreviewCore.ApplyLayerVisibility(owner) end
        RequestPreviewLayoutRefresh(owner, "UNIT_PREVIEW_LAYER")
        RefreshHandleSelectionVisuals(owner)
    end
    local function HideSampleLayers(owner)
        local state, changed = owner._msuf2SampleLayers, nil
        for i = 1, #owner.layerButtons do
            local key = owner.layerButtons[i].key
            if PreviewHelpers.IsSampleEffectLayer(key) and UnitLayerOn(owner, key) then
                owner.layerVisibility[key], changed = false, key
                if state then state.auto[key] = nil end
            end
        end
        if changed then ApplyUnitLayerChange(owner, changed) end
    end
    local unitLayerButtonOpts = PreviewHelpers.LayerChipButtonOpts(TR, colors, chrome, {
        IsAvailable = UnitLayerAvailable,
        IsOn = UnitLayerOn,
        OnClick = function(self, owner)
            if owner.layerAvailable and owner.layerAvailable[self.key] == false then
                if GameTooltip then GameTooltip:Hide() end
                Preview.OpenUnavailableLayerSettings(owner, self.key)
                return
            end
            owner.layerVisibility[self.key] = owner.layerVisibility[self.key] == false
            -- A chip click is the user's own choice: the settings section no longer owns this layer's state.
            local sampleState = owner._msuf2SampleLayers
            if sampleState then sampleState.auto[self.key] = nil end
            ApplyUnitLayerChange(owner, self.key)
        end,
        OnEnter = function(self, owner, available, on, tr)
            if not available then
                self.bg:SetColorTexture(0.014, 0.038, 0.072, 0.62)
                self.fs:SetTextColor(disabledLayerText[1], disabledLayerText[2], disabledLayerText[3], 0.78)
                owner.hint:SetText(TR("This layer is off in settings. Click to open its options."))
                return
            end
            local label = tr(self.fs and self.fs:GetText() or self.key)
            if owner.hint then owner.hint:SetText(label .. " - " .. TR(on and "click to hide this preview layer" or "click to show this preview layer")) end
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(label, 1, 1, 1)
                if self.tooltip then GameTooltip:AddLine(tr(self.tooltip), 0.82, 0.82, 0.82, true) end
                PreviewHelpers.AddSampleEffectTooltipLine(self.key, tr)
                GameTooltip:AddLine(TR(on and "Click to hide this preview layer." or "Click to show this preview layer."), 0.55, 0.68, 0.86, true)
                if self.key == "guides" then GameTooltip:AddLine(tr(on
                    and "Turn off to inspect the frame without mover outlines. The selected element can still be nudged with arrow keys."
                    or "Guides are hidden. Turn this back on to see drag handles and selected borders."), 0.55, 0.68, 0.86, true) end
                GameTooltip:Show()
            end
        end,
        OnLeave = function(_, owner) UpdateHandleHint(owner, owner._selectedHandle) end,
    })
    for i = 1, #PREVIEW_LAYERS do
        local def = PREVIEW_LAYERS[i]
        -- Bounds are an optional measurement overlay, not part of the frame's
        -- configured visual. Keep the real frame outline visible and start the
        -- separate cyan measurement guide hidden.
        if def.key == "guides" then
            box.layerVisibility[def.key] = ViewChrome.PreviewGuidesEnabled()
        elseif def.key == "bounds" or PreviewHelpers.IsSampleEffectLayer(def.key) then
            -- Sample-effect layers (dispel overlay/symbol) stay off until a chip click or their open settings
            -- section asks for them; Bounds is the cyan measurement guide.
            box.layerVisibility[def.key] = false
        else
            box.layerVisibility[def.key] = true
        end
        local btn = PreviewHelpers.CreateLayerButton(sidebar, box, def, i, sideW, unitLayerButtonOpts)
        if M2.AddTooltip then
            M2.AddTooltip(btn, "Layer disabled", "Click to open the setting that enables this layer.", {
                hook = true,
                enabled = function(self) return UnitLayerAvailable(box, self.key) == false end,
            })
        end
        box.layerButtons[#box.layerButtons + 1] = btn
    end
    PreviewHelpers.SetupSampleEffectHint(box, s.canvas, {
        Tr = TR, T = s.T, buttons = "layerButtons", IsOn = UnitLayerOn, Hide = HideSampleLayers,
    })
    -- While the rail hangs under the "Layers" button it is a dropdown, not
    -- the docked strip, so it owns its own width. Callers that re-flow it
    -- from the preview box -- the render pass does, on every layer-
    -- availability change such as entering combat view -- would otherwise
    -- push the chips out past the panel painted behind them.
    box.LayoutLayerRail = function(self, railWidth)
        return PreviewHelpers.LayoutLayerRail(self, self.sidebar, self.layerButtons, railWidth)
    end
end
function BoxBuild.Selection(box, s)
    local canvas = s.canvas
    if M2.PreviewSelectionBar then
        M2.PreviewSelectionBar.Create(box, {
            Tr = TR,
            Theme = MenuTheme,
            ApplyBackdrop = ApplyPreviewBackdrop,
            Round = RoundOffset,
            HandleList = function(owner) return owner.handles end,
            HandleLabel = function(handle) return handle._label or handle._key end,
            ReadOffsets = Preview.ReadSelectionCoordinates,
            WriteOffsets = Preview.WriteSelectionCoordinates,
            ResetOffsets = Preview.ResetSelectionOffsets,
            NudgeDelta = NudgeSelectedHandleDelta,
            DefaultOffsets = Preview.DefaultSelectionOffsets,
            OpenSettings = function(_, handle, source) return OpenPreviewHandleSettings(handle, source) end,
            SelectHandle = function(_, handle) return SelectPreviewHandle(handle, true) end,
            UpdateHint = UpdateHandleHint,
        })
        M2.PreviewSelectionBar.CreatePicker(box, canvas)
    end
    -- One layout path for the docked (inline expanded) and floating states: the
    -- rail sits on the bottom edge, the selection bar rides above it, and the
    -- canvas takes whatever is left instead of a fixed-width column.
    box.ApplyDockedPreviewLayout = function(self, bottomInset)
        return PreviewHelpers.ApplyDockedPreviewLayout(self, self.sidebar, self.canvas, bottomInset, false)
    end
end
function BoxBuild.Stage(box, s)
    local T, canvas = s.T, s.canvas
    -- A plain root owns no synthetic Center texture. Only the real health
    -- background media below may cover the unit-frame rectangle; outlines are
    -- drawn by the dedicated four-edge overlay in PreviewCore.
    local mock = PixelLayoutRegion(CreateFrame("Frame", nil, canvas), true)
    if mock.SetBackdropColor then mock:SetBackdropColor(0, 0, 0, 0) end
    box.mock = mock
    mock.bounds = PixelLayoutRegion(CreateFrame("Frame", nil, mock))
    mock.bounds:SetFrameLevel((mock:GetFrameLevel() or 0) + 28)
    mock.bounds:SetAllPoints(mock)
    mock.sizeTag = PixelLayoutRegion(mock.bounds:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"))
    mock.sizeTag:SetPoint("BOTTOM", mock.bounds, "TOP", 0, 2)
    mock.sizeTag:SetTextColor(0.62, 0.84, 0.94, 0.95)
    if T and T.StyleFontString then T.StyleFontString(mock.sizeTag, { 0.62, 0.84, 0.94, 0.95 }, 0) end
    s.mock = mock
end
--- The class power and castbar slots are plain holders: the engine's scenes paint inside them (root:ClassPower,
--- root:Castbar). A slot keeps the layer switch, the colour-painter target, the hit area and the guides.
function BoxBuild.MockClassPower(box, s)
    s.mock.classPower = PixelLayoutRegion(CreateFrame("Frame", nil, s.canvas))
end
function BoxBuild.MockCast(box, s)
    local T, canvas, mock = s.T, s.canvas, s.mock
    mock.cast = PixelLayoutRegion(CreateFrame("Frame", nil, canvas))
    mock.cast:EnableMouse(false)
    mock.cast:SetScript("OnMouseUp", function(self, button)
        if canvas._msufPreviewPanning then
            StopPreviewPan(canvas)
            return
        end
        if button and button ~= "LeftButton" then return end
        -- Whole-bar movement is owned by handleCastbar on the interaction
        -- layer. This plain Frame keeps a one-click fallback route to the same
        -- settings when that handle is not the active mouse target.
        OpenPreviewHandleSettings(box.handleCastbar, "click")
    end)
    mock.cast:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(TR("Castbar"), 1, 1, 1)
            GameTooltip:AddLine(TR("Preview follows the current castbar visibility, whole-bar layer, icon, text, and global color settings."),
                0.82, 0.82, 0.82, true)
            GameTooltip:AddLine(TR("Ctrl + left-drag pans the preview canvas."), 0.55, 0.68, 0.86, true)
            GameTooltip:Show()
        end
    end)
    mock.cast:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    mock.cast.sizeTag = PixelLayoutRegion(mock.cast:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"))
    mock.cast.sizeTag:SetPoint("BOTTOM", mock.cast, "TOP", 0, 2)
    mock.cast.sizeTag:SetTextColor(0.20, 0.90, 0.85, 0.95)
    if T and T.StyleFontString then T.StyleFontString(mock.cast.sizeTag, { 0.20, 0.90, 0.85, 0.95 }, 0) end
    mock.icons = {}
end
-- Handle recipes. A frame's place in the preview tree is its creation order, so
-- the rows below and the calls in BoxBuild.Handles keep the order the handles
-- were always built in. Colours are shared, read-only tables.
local COLOR_HP, COLOR_POWER, COLOR_TEXLAYER = { 0.25, 0.90, 0.42 }, { 0.95, 0.72, 0.18 }, { 0.80, 0.55, 0.25 }
local COLOR_CLASS_POWER, COLOR_CAST, COLOR_CAST_TARGET = { 0.30, 0.78, 0.55 }, { 0.20, 0.90, 0.85 }, { 0.95, 0.78, 0.22 }
-- box field, handle key, offset key prefix, label, colour, default X, default Y
local TEXT_HANDLES = {
    { "handleHP", "hp", "hp", "HP text", COLOR_HP, -4, -4 },
    { "handleHPLeft", "hpLeft", "hpTextLeft", "HP left text", COLOR_HP, 0, 0 },
    { "handleHPCenter", "hpCenter", "hpTextCenter", "HP center text", COLOR_HP, 0, 0 },
    { "handleHPRight", "hpRight", "hpTextRight", "HP right text", COLOR_HP, 0, 0 },
    { "handlePower", "power", "power", "Power text", COLOR_POWER, -4, 4 },
    { "handlePowerLeft", "powerLeft", "powerTextLeft", "Power left text", COLOR_POWER, 0, 0 },
    { "handlePowerCenter", "powerCenter", "powerTextCenter", "Power center text", COLOR_POWER, 0, 0 },
    { "handlePowerRight", "powerRight", "powerTextRight", "Power right text", COLOR_POWER, 0, 0 },
}
-- handle key (also the offset key prefix), label
local TEXTURE_LAYER_HANDLES = {
    { "texLayer", "Texture layer 1" }, { "texLayer2", "Texture layer 2" }, { "texLayer3", "Texture layer 3" },
}
-- box field, handle key (also the offset key prefix), label
local CLASS_POWER_HANDLES = {
    { "handleClassPower", "classPower", "Class power" },
    { "handleClassPowerText", "classPowerText", "Class power text" },
}
-- box field, handle key, castbar offset key part, label, colour, default X, default Y, extra fields
local CASTBAR_SUB_HANDLES = {
    { "handleCastbarIcon", "castbarIcon", "Icon", "Castbar icon", COLOR_CAST, 0, 0, { iconFallback = true } },
    { "handleCastbarText", "castbarText", "Text", "Castbar text", COLOR_CAST, 0, 0 },
    { "handleCastbarTarget", "castbarTarget", "TargetName", "Cast target text", COLOR_CAST_TARGET, 0, 1 },
    { "handleCastbarTime", "castbarTime", "Time", "Castbar time", COLOR_CAST, -2, 0, {
        bossBaseX = -2, defaultXFromG = "castbarPlayerTimeOffsetX", defaultYFromG = "castbarPlayerTimeOffsetY",
    } },
}
local function TextHandleFields(prefix, defaultX, defaultY, resolveOffsetDelta)
    return { x = prefix .. "OffsetX", y = prefix .. "OffsetY", defaultX = defaultX, defaultY = defaultY, text = true,
        resolveOffsetDelta = resolveOffsetDelta, section = "text" }
end
local function CastbarSubHandleFields(part, defaultX, defaultY, extra)
    local fields = {
        suffixX = part .. "OffsetX", suffixY = part .. "OffsetY",
        bossX = "bossCast" .. part .. "OffsetX", bossY = "bossCast" .. part .. "OffsetY",
        defaultX = defaultX, defaultY = defaultY,
        readOffsets = ViewHandles.ReadCastbarSubOffsets, writeOffsets = ViewHandles.WriteCastbarSubOffsets,
        section = "castbar", interactionPriority = 1,
    }
    for name, value in pairs(extra or {}) do fields[name] = value end
    return fields
end
function BoxBuild.Handles(box, s)
    local canvas = s.canvas
    box.handles = {}
    box.dragFrame = PixelLayoutRegion(CreateFrame("Frame", nil, canvas), true)
    box.dragFrame:EnableMouse(true)
    if PreviewHelpers.BindPreviewWheel then PreviewHelpers.BindPreviewWheel(box.dragFrame, box) end
    if box.dragFrame.SetFrameLevel then
        box.dragFrame:SetFrameLevel((PreviewCore.InteractionFrameLevel and PreviewCore.InteractionFrameLevel(canvas, 2))
            or ((canvas:GetFrameLevel() or 0) + 32))
    end
    box.dragFrame:Hide()
    box._onDragUpdate = HandleDragUpdate
    box.handleName = MakeHandle(box, "name", TextHandleFields("name", 4, -4, ViewHandles.NameHandleOffsetDelta),
        "Name text", { 0.30, 0.66, 1.0 })
    box.handleRaidGroupName = MakeHandle(box, "raidgroupname", { x = "raidGroupNameOffsetX", y = "raidGroupNameOffsetY", defaultX = 3, defaultY = 0,
        statusRefresh = "MSUF_RefreshRaidGroupNameFrames", section = "status" }, "Raid group", { 0.45, 0.70, 1.0 })
    for i = 1, #TEXT_HANDLES do
        local spec = TEXT_HANDLES[i]
        box[spec[1]] = MakeHandle(box, spec[2], TextHandleFields(spec[3], spec[6], spec[7]), spec[4], spec[5])
    end
    box.handlePortrait = MakeHandle(box, "portrait", { x = "portraitOffsetX", y = "portraitOffsetY", defaultX = 0, defaultY = 0, portrait = true,
        section = "portrait" }, "Portrait", { 0.90, 0.42, 1.0 })
    box.handleDetachedPower = MakeHandle(box, "detachedPower", { x = "detachedPowerBarOffsetX", y = "detachedPowerBarOffsetY", defaultX = 0, defaultY = -4,
        detachedPower = true, section = "power", playerSection = "classPower" }, "Detached power bar", COLOR_POWER)
    box.texLayerHandles = {}
    for i = 1, #TEXTURE_LAYER_HANDLES do
        local key, label = TEXTURE_LAYER_HANDLES[i][1], TEXTURE_LAYER_HANDLES[i][2]
        box.texLayerHandles[i] = MakeHandle(box, key, { x = key .. "OffsetX", y = key .. "OffsetY", defaultX = 0, defaultY = 0, texLayer = true,
            section = "texture_layer" }, label, COLOR_TEXLAYER)
    end
    for i = 1, #CLASS_POWER_HANDLES do
        local spec = CLASS_POWER_HANDLES[i]
        box[spec[1]] = MakeHandle(box, spec[2], { barsX = spec[2] .. "OffsetX", barsY = spec[2] .. "OffsetY", defaultX = 0, defaultY = 0,
            classPower = true, readOffsets = ViewHandles.ReadBarsHandleOffsets, writeOffsets = ViewHandles.WriteBarsHandleOffsets,
            section = "classPower" }, spec[3], COLOR_CLASS_POWER)
    end
    box.handleCastbar = MakeHandle(box, "castbar", { castbar = true, global = true, section = "castbar" }, "Castbar", COLOR_CAST)
    for i = 1, #CASTBAR_SUB_HANDLES do
        local spec = CASTBAR_SUB_HANDLES[i]
        box[spec[1]] = MakeHandle(box, spec[2], CastbarSubHandleFields(spec[3], spec[6], spec[7], spec[8]), spec[4], spec[5])
    end
    if PreviewAuras.CreateHandles then PreviewAuras.CreateHandles(box, MakeHandle) end
    box.statusHandles = { raidgroupname = box.handleRaidGroupName }
    if HAS_BOSS_UNITS then
        box.handleBossTarget = MakeHandle(box, "bossTarget", {
            x = "bossTargetIndicatorOffsetX", y = "bossTargetIndicatorOffsetY",
            defaultX = -28, defaultY = 0, section = "boss_target",
        }, "Boss target highlight", { 1, .82, 0 })
    end
    -- Arena's PvP trinket: Pages/MSUF_Menu2_UnitArenaTrinket.lua builds it with
    -- this MakeHandle, so it selects, drags and nudges like every element here.
    if M2.ArenaTrinketPreview then M2.ArenaTrinketPreview.CreateHandle(box, MakeHandle) end
    for i = 1, #STATUS_PREVIEW do
        local spec = STATUS_PREVIEW[i]
        box.statusHandles[spec.id] = MakeHandle(box, spec.id, { x = spec.x, y = spec.y, defaultX = spec.defaultX or 0, defaultY = spec.defaultY or 0,
            statusRefresh = spec.refresh, section = "status" }, spec.label, spec.color)
    end
end
function BoxBuild.Scripts(box)
    box:EnableKeyboard(true)
    if box.SetPropagateKeyboardInput then box:SetPropagateKeyboardInput(true) end
    box:SetScript("OnKeyDown", PreviewArrowKeyDown)
    function box:ReleasePreviewInteraction()
        self._selectedHandle = nil
        Preview.SetArrowBindings(self, false)
        RefreshHandleSelectionVisuals(self)
        if self.dragFrame then
            self.dragFrame:SetScript("OnUpdate", nil)
            self.dragFrame:SetScript("OnMouseUp", nil)
            self.dragFrame._handle = nil
            self.dragFrame:Hide()
        end
        if self._msufPreviewNudgeTarget
            and MSUF.Optional("MSUF_EM2_ActivePreviewNudgeTarget") == self._msufPreviewNudgeTarget then
            MSUF.Require("MSUF_EM2_SetPreviewNudgeTarget", FILE)(nil)
        end
        ReleasePreviewKeyboard(self)
    end
    box:SetScript("OnShow", function(self)
        self._msuf2PreviewShowSerial = (tonumber(self._msuf2PreviewShowSerial) or 0) + 1
        Preview.active = self
        if ViewChrome.PreviewAnimationActive(self) then ViewChrome.StartPreviewAnimationDriver(self) end
        ViewChrome.RefreshPreviewAnimationButton(self)
        self:RequestRefresh("SHOW")
    end)
    box:SetScript("OnHide", function(self)
        ViewChrome.StopPreviewAnimationDriver(self)
        if ViewChrome.PreviewAnimationActive(self) then Preview.RestoreStaticEditModeAuraPreview(self) end
        ViewChrome.ReleaseUnitPreviewLiveState(self)
        if self._unitSceneRoot then self._unitSceneRoot:Deactivate() end
        if self._castSceneRoot then self._castSceneRoot:Deactivate() end
        if self._cpSceneRoot then self._cpSceneRoot:Deactivate() end
        self._refreshSerial = (tonumber(self._refreshSerial) or 0) + 1
        self._refreshQueued = nil
        self._refreshReason = nil
        if self.UnregisterEvent then
            self:UnregisterEvent("PLAYER_REGEN_DISABLED")
        end
        self:ReleasePreviewInteraction()
        if Preview.active == self then Preview.active = nil end
        if Preview.UninstallRefreshHooks then Preview.UninstallRefreshHooks() end
    end)
    box:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            ViewChrome.KillPreviewAnimationForCombat(self)
            self._refreshReason = nil
            self._refreshQueued = nil
            self._selectedHandle = nil
            Preview.SetArrowBindings(self, false)
            ReleasePreviewKeyboard(self)
            RefreshHandleSelectionVisuals(self)
        end
    end)
    box:HookScript("OnSizeChanged", function(self, changedWidth, changedHeight)
        if not self:IsShown() then return end
        changedWidth = floor((tonumber(changedWidth) or self:GetWidth() or 0) + 0.5)
        changedHeight = floor((tonumber(changedHeight) or self:GetHeight() or 0) + 0.5)
        if self._msufUFPreviewRefreshWidth == changedWidth and self._msufUFPreviewRefreshHeight == changedHeight then return end
        self._msufUFPreviewRefreshWidth = changedWidth
        self._msufUFPreviewRefreshHeight = changedHeight
        -- The chip rail wraps on width, and the canvas hangs off its top edge,
        -- so a resize has to reflow the rail before the render measures the
        -- canvas.
        if self._msuf2CompactPreview ~= true and self.ApplyDockedPreviewLayout then
            self:ApplyDockedPreviewLayout(12)
        end
        self:RequestRefresh("UNIT_PREVIEW_SIZE")
    end)
    box.OnPreviewCanvasMoved = function(_, button)
        if PreviewHelpers.NotePreviewCanvasMoved then PreviewHelpers.NotePreviewCanvasMoved(button) end
    end
    box:ApplyDockedPreviewLayout(12)
    Preview.RegisterRuntimeControlsForPage(box, M2.activeKey)
end
local function BuildPreview(parent, panel, width, height)
    local box, s = BoxBuild.Frame(parent, panel, width, height)
    BoxBuild.Chrome(box, s)
    BoxBuild.LayerRail(box, s)
    BoxBuild.Selection(box, s)
    BoxBuild.Stage(box, s)
    BoxBuild.MockClassPower(box, s)
    BoxBuild.MockCast(box, s)
    BoxBuild.Handles(box, s)
    BoxBuild.Scripts(box)
    return box
end
local PreviewInCombat = PreviewCore.InCombat
do
    local deps = Preview.RefreshDeps or {}
    Preview.RefreshDeps = deps
    -- Model helpers the render reads under the names the model exports.
    M2.PickFallbackTable(PreviewModel, nil, "UNIT_LABELS UNIT_DATA CurrentPanelKey UnitDB NormalizeHpMode NormalizePowerMode "
        .. "TextScopeGet TextScopeHasSlots TextScopeSlotGet ToTInlineSeparator PortraitStyleGet "
        .. "SetTex ReadPowerBarEnabled ReadPowerBarHeight CanDetachPowerBarKey UnitPreviewText "
        .. "NormalizeStatusPreviewId LiveUnitData", deps)
    M2.Assign(deps, {
        PreviewInCombat = PreviewInCombat, TR = TR,
        RuntimeSpecForPreviewKey = PreviewRuntime.SpecForPreviewKey or Fallbacks.Nil,
        RuntimeAppliedPortraitSizeForPreviewKey = PreviewRuntime.AppliedPortraitSizeForPreviewKey or Fallbacks.Nil,
        DetachedCastbarOffsetForPreviewKey = PreviewRuntime.DetachedCastbarOffsetForPreviewKey,
        RuntimeVisualScaleForPreviewKey = RuntimeVisualScaleForPreviewKey,
        RuntimeCastbarVisualScaleForPreviewKey = PreviewRuntime.CastbarVisualScaleForPreviewKey or RuntimeVisualScaleForPreviewKey,
        ClampPreviewZoom = ClampPreviewZoom,
        ResolveDefaultPreviewZoomLock = PreviewZoomPan.ResolveDefaultLock or Fallbacks.Noop,
        UpdatePreviewZoomControls = UpdatePreviewZoomControls, ZOOM_MIN = ZOOM_MIN,
        max = math.max, min = math.min, abs = math.abs, floor = floor, format = string.format,
        TEX_W8 = TEX_W8, FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", STATUS_PREVIEW = STATUS_PREVIEW,
        SyncLiveStateDriver = ViewChrome.SyncUnitPreviewLiveState,
        CastbarEnabled = PreviewCastbar.Enabled, CastbarShowIcon = PreviewCastbar.ShowIcon,
        CastbarShowText = PreviewCastbar.ShowText, ReadCastbarSize = PreviewCastbar.ReadSize,
        ReadCastbarNum = PreviewCastbar.ReadNumber, CastbarOffsetFields = CastbarOffsetFields,
        CastbarDetached = PreviewCastbar.Detached,
        ClampPreviewLayer = PreviewCore.ClampLayer, PlaceHandle = PreviewCore.PlaceHandle,
        PlaceHandleAroundRegions = PreviewModel.UnitPreviewText.PlaceHandleAroundRegions,
        UnitPreviewTextMovesTogether = ViewHandles.UnitPreviewTextMovesTogether,
        ApplyPreviewTextFocus = ViewChrome.ApplyPreviewTextFocus, ApplyPreviewRounded = PreviewCore.ApplyRounded,
        ApplyPreviewFrameBorder = PreviewCore.ApplyFrameBorder,
        PreviewRoundedOutlineThickness = PreviewCore.RoundedOutlineThickness,
        ApplyPreviewBoundsGuide = PreviewCore.ApplyBoundsGuide, SetShownSafe = PreviewCore.SetShownSafe,
        ApplyPreviewLayerVisibility = PreviewCore.ApplyLayerVisibility,
        ApplyPreviewTransparency = Preview.ApplyPreviewTransparency,
        RefreshHandleSelectionVisuals = RefreshHandleSelectionVisuals, Auras = PreviewAuras,
    })
end
if MSUF.UFPreviewRender and MSUF.UFPreviewRender.Install then MSUF.UFPreviewRender.Install(Preview, Preview.RefreshDeps) end
Preview._BuildPreview = BuildPreview
Preview._PreviewInCombat = PreviewInCombat
