-- Unit-preview mouse, keyboard and drag gestures plus their native handles.
-- Selection, profile writes and history remain in the selection owner.
local _, MSUF = ...
local FILE = "Menu2/UnitPreview_Input"
local M2 = MSUF.MSUF2
local RequireFields = M2.PreviewContracts.RequireFields
local Selection = RequireFields("UnitInput.Selection", MSUF.UFPreviewSelection,
    "SelectHandle RefreshVisuals ReadOffsets WriteOffsets NudgeSelected StatusRefresh GearOptions")
local SelectPreviewHandle, RefreshHandleSelectionVisuals = Selection.SelectHandle, Selection.RefreshVisuals
local ReadHandleOffsets, WriteHandleOffsets = Selection.ReadOffsets, Selection.WriteOffsets
local NudgeSelectedHandle, STATUS_REFRESH, GearOptions = Selection.NudgeSelected, Selection.StatusRefresh, Selection.GearOptions
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local Preview, PreviewCore = MSUF.UFPreview, MSUF.UFPreviewCore
local PreviewHelpers, ViewHandles = M2.PreviewHelpers, MSUF.UFPreviewViewHandles
local ViewChrome, PreviewZoomPan = MSUF.UFPreviewViewChrome, MSUF.UFPreviewZoomPan
local TR, RoundOffset, MenuTheme = ViewChrome.TR, PreviewCore.RoundOffset, PreviewCore.MenuTheme
local BeginMenuHistory, CommitMenuHistory = ViewHandles.BeginMenuHistory, ViewHandles.CommitMenuHistory
local OpenPreviewHandleSettings = ViewHandles.OpenPreviewHandleSettings
local RequestPreviewLayoutRefresh = ViewChrome.RequestPreviewLayoutRefresh
local function PreviewArrowKeyDown(self, keyName)
    -- Tab steps through the placed handles. Overlapping elements in dense
    -- corners cannot all be reached by clicking, so keyboard traversal is the
    -- only way to select what sits underneath.
    if keyName == "TAB" then
        local box = (self and self.handles and self) or Preview.active
        if M2.IsConfigCombatLocked() or PreviewHelpers.IsTextInputFocused() then
            PreviewHelpers.ReleaseKeyboardCapture(box)
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
            return
        end
        if box and M2.PreviewSelectionBar
            and M2.PreviewSelectionBar.CycleHandle(box, IsShiftKeyDown and IsShiftKeyDown()) then
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
            return
        end
    end
    if PreviewHelpers.ArrowKeyDown then
        return PreviewHelpers.ArrowKeyDown(self, keyName, {
            active = function() return Preview.active end,
            selectedField = "_selectedHandle",
            nudge = NudgeSelectedHandle,
        })
    end
end
local StartPreviewPan, StopPreviewPan = PreviewZoomPan.Start, PreviewZoomPan.Stop
-- Handle scripts read the owning preview from the handle, so every handle
-- shares one function per script instead of building a closure set per handle.
local function HandleOnEnter(self)
    local preview = self._preview
    self._hovering = true
    RefreshHandleSelectionVisuals(preview)
    local showTooltip = GameTooltip and (not PreviewHelpers.ShouldShowPreviewHandleTooltip
        or PreviewHelpers.ShouldShowPreviewHandleTooltip(preview))
    if showTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        -- `_label` can be rebound per unit on the shared box (custom
        -- container 4 is Defensive Buffs on player, Dots on target
        -- elsewhere), so the tooltip reads it at hover time.
        GameTooltip:SetText(TR(self._label or self._key), 1, 1, 1)
        GameTooltip:AddLine(TR("Drag to move. Arrow keys nudge."), 0.82, 0.82, 0.82, true)
        GameTooltip:AddLine(TR("Right-click opens quick actions."), 0.50, 0.78, 0.92, true)
        GameTooltip:Show()
    end
end
local function HandleOnLeave(self)
    self._hovering = nil
    RefreshHandleSelectionVisuals(self._preview)
    if GameTooltip then GameTooltip:Hide() end
end
local function HandleOnClick(self, button)
    if self._suppressNextClick then
        self._suppressNextClick = nil
        return
    end
    if button == "RightButton" then
        SelectPreviewHandle(self, true)
        if PreviewHelpers.ShowPreviewHandleContext then
            PreviewHelpers.ShowPreviewHandleContext(self, {
                M = M2,
                T = MenuTheme and MenuTheme(),
                Tr = TR,
                title = self._label or self._key,
                openSettings = OpenPreviewHandleSettings,
            })
        end
        return
    end
    SelectPreviewHandle(self)
end
local function DragFrameMouseUp(df, upButton)
    local activeHandle = df and df._handle
    local stop = activeHandle and activeHandle.GetScript and activeHandle:GetScript("OnMouseUp")
    if stop then stop(activeHandle, upButton) end
end
-- Per-drag state a handle carries between press and release.
local HANDLE_DRAG_STATE = { "_dragging", "_lastDragX", "_lastDragY", "_dragPoint", "_dragRelTo", "_dragRelPoint",
    "_dragOffsetX", "_dragOffsetY", "_didDragMove" }
local function StartHandleDrag(self, button)
    local preview = self._preview
    if button and button ~= "LeftButton" then return end
    if self._dragging == true or preview.dragFrame._handle == self or (preview.canvas and preview.canvas._msufPreviewPanning) then return true end
    self._didDragMove = nil
    if button == "LeftButton" and IsControlKeyDown and IsControlKeyDown() and StartPreviewPan and StartPreviewPan(preview.canvas, preview, button) then
        self._suppressNextClick = true
        return
    end
    SelectPreviewHandle(self, true)
    if PreviewHelpers.ShowPreviewMoveCue then PreviewHelpers.ShowPreviewMoveCue(preview, self) end
    local x, y = ReadHandleOffsets(self)
    self._startX = x
    self._startY = y
    self._lastDragX = nil
    self._lastDragY = nil
    self._dragging = true
    preview._dragFrozenScale = tonumber(preview._mockScale) or tonumber(preview._mockAutoScale) or 1
    preview._dragFrozenBaseOffsetX = tonumber(preview._mockBaseOffsetX) or 0
    preview._dragFrozenBaseOffsetY = tonumber(preview._mockBaseOffsetY) or 0
    self._msuf2PreviewHistoryTx = BeginMenuHistory(self, "Move")
    local cx, cy = GetCursorPosition()
    self._cursorX, self._cursorY = cx, cy
    self._dragPoint, self._dragRelTo, self._dragRelPoint, self._dragOffsetX, self._dragOffsetY = self:GetPoint(1)
    preview.dragFrame._handle = self
    if preview.dragFrame.SetAllPoints then preview.dragFrame:SetAllPoints(preview.canvas) end
    preview.dragFrame:SetScript("OnUpdate", preview._onDragUpdate)
    preview.dragFrame:SetScript("OnMouseUp", DragFrameMouseUp)
    preview.dragFrame:Show()
    RefreshHandleSelectionVisuals(preview)
end
local function StopHandleDrag(self, button, allowOpenSettings)
    local preview = self._preview
    if StopPreviewPan and preview.canvas and preview.canvas._msufPreviewPanning then StopPreviewPan(preview.canvas) end
    if button and button ~= "LeftButton" then return end
    local wasDragging = self._dragging == true or preview.dragFrame._handle == self
    if not wasDragging then return end
    local didMove = self._didDragMove == true
    if didMove and PreviewHelpers.NotePreviewElementMoved then PreviewHelpers.NotePreviewElementMoved() end
    local openSettingsOnRelease = allowOpenSettings == true
        and button == "LeftButton"
        and not didMove
    if preview.dragFrame._handle == self then
        preview.dragFrame:SetScript("OnUpdate", nil)
        preview.dragFrame:SetScript("OnMouseUp", nil)
        preview.dragFrame._handle = nil
        preview.dragFrame:Hide()
    end
    local fields = self._fields or {}
    if fields.commitOffsets then fields.commitOffsets(self, "UNIT_PREVIEW_DRAG_END") end
    if self._msuf2PreviewHistoryTx then
        self._msuf2PreviewHistoryTx = nil
        CommitMenuHistory()
    end
    local hadFrozenScale = preview._dragFrozenScale ~= nil
    preview._dragFrozenScale = nil
    preview._dragFrozenBaseOffsetX = nil
    preview._dragFrozenBaseOffsetY = nil
    if fields.clearDragOffsets then fields.clearDragOffsets(self) end
    for i = 1, #HANDLE_DRAG_STATE do self[HANDLE_DRAG_STATE[i]] = nil end
    RefreshHandleSelectionVisuals(preview)
    if hadFrozenScale and not preview._manualZoom then RequestPreviewLayoutRefresh(preview, "UNIT_PREVIEW_DRAG_END") end
    if openSettingsOnRelease then OpenPreviewHandleSettings(self, "click") end
end
local function HandleOnMouseUp(self, button) StopHandleDrag(self, button, true) end
local function HandleOnDragStop(self, button) StopHandleDrag(self, button, false) end
local function HandleOnHide(self) StopHandleDrag(self, nil, false) end
local HANDLE_SCRIPTS = {
    OnEnter = HandleOnEnter, OnLeave = HandleOnLeave, OnClick = HandleOnClick,
    OnMouseDown = StartHandleDrag, OnMouseUp = HandleOnMouseUp, OnDragStart = StartHandleDrag,
    OnDragStop = HandleOnDragStop, OnHide = HandleOnHide, OnKeyDown = PreviewArrowKeyDown,
}
--- The handle frame: hit area, hover/selection textures and the selection border.
local function CreateHandleFrame(preview, key, fields, label, color)
    local h = PixelLayoutRegion(CreateFrame("Button", nil, preview.canvas), true)
    local statusRefresh = fields and fields.statusRefresh
    if statusRefresh and STATUS_REFRESH[statusRefresh] == nil then
        STATUS_REFRESH[statusRefresh] = MSUF.Optional(statusRefresh) or false
    end
    -- Composite elements need a deterministic mouse-hit hierarchy. The broad
    -- container handle stays on the base interaction plane while its smaller
    -- icon/text/time handles sit above it; creation/show order must not decide
    -- which element receives the click.
    local interactionPriority = tonumber(fields and fields.interactionPriority) or 0
    h:SetFrameLevel((PreviewCore.InteractionFrameLevel and PreviewCore.InteractionFrameLevel(preview.canvas, interactionPriority))
        or ((preview.canvas:GetFrameLevel() or 0) + 30 + interactionPriority))
    h:SetSize(20, 20)
    h:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonUp")
    if h.RegisterForDrag then h:RegisterForDrag("LeftButton") end
    h:EnableMouse(true)
    if PreviewHelpers.BindPreviewWheel then PreviewHelpers.BindPreviewWheel(h, preview) end
    h:EnableKeyboard(true)
    if h.SetPropagateKeyboardInput then h:SetPropagateKeyboardInput(true) end
    h.tex = PixelLayoutRegion(h:CreateTexture(nil, "OVERLAY"))
    h.tex:SetAllPoints()
    h.tex:SetColorTexture(color[1], color[2], color[3], 0)
    h.edge = PixelLayoutRegion(h:CreateTexture(nil, "BORDER"))
    h.edge:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
    h.edge:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    h.edge:SetColorTexture(color[1], color[2], color[3], 0)
    h._label = label
    h._fields = fields
    h._key = key
    h._previewLayerKey = ViewHandles.UnitPreviewLayerForHandle(key, fields)
    h._preview = preview
    h._color = color
    h._selBorder = PixelLayoutRegion(CreateFrame("Frame", nil, h))
    h._selBorder:SetPoint("TOPLEFT", h, "TOPLEFT", -1, 1)
    h._selBorder:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 1, -1)
    for side, spec in pairs(ViewHandles.HANDLE_BORDER_SPECS) do
        local line = PixelLayoutRegion(h._selBorder:CreateTexture(nil, "OVERLAY"))
        line:SetColorTexture(0.30, 0.58, 0.95, 0.70)
        line:SetPoint(spec[1])
        line:SetPoint(spec[2])
        line[spec[3]](line, 1)
        h._selBorder[side] = line
    end
    h._selBorder:Hide()
    return h
end
local function MakeHandle(preview, key, fields, label, color)
    local h = CreateHandleFrame(preview, key, fields, label, color)
    for script, handler in pairs(HANDLE_SCRIPTS) do h:SetScript(script, handler) end
    h._msuf2CommandAction = {
        kind = "button",
        historyMode = "none",
        interaction = "preview.handle.select",
        previewSurface = "unit",
        previewHandleKey = key,
        previewUnitKey = preview.key or tostring(M2.PageKeyForWidget(preview) or M2.activeKey or ""):match("^uf_(.+)$"),
        set = function()
            if h._msufPlaced == false then return false end
            if h.IsShown and not h:IsShown() then return false end
            SelectPreviewHandle(h, true)
            return preview._selectedHandle == h
        end,
    }
    if PreviewHelpers.EnsurePreviewHandleGear then
        local gear = PreviewHelpers.EnsurePreviewHandleGear(h, GearOptions(false))
        if gear and not gear._msuf2UnitPreviewOpenCommand then
            gear._msuf2UnitPreviewOpenCommand = {
                kind = "button",
                historyMode = "none",
                set = function() return OpenPreviewHandleSettings(h, "search") end,
            }
        end
    end
    h:Hide()
    preview.handles[#preview.handles + 1] = h
    return h
end
--- While a handle is dragged this runs every frame on the drag frame; it only writes when the rounded position changed.
local function HandleDragUpdate(df)
    local h = df._handle
    if not h then return end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        local stop = h.GetScript and h:GetScript("OnMouseUp")
        if stop then stop(h, "LeftButton") end
        return
    end
    local box = h._preview
    local cx, cy = GetCursorPosition()
    local scale = box._mockEffectiveScale or box._mockScale or 1
    local uiScale = (box.canvas and box.canvas.GetEffectiveScale and box.canvas:GetEffectiveScale())
        or (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale())
        or 1
    if uiScale <= 0 then uiScale = 1 end
    local dx = (((cx or 0) - (h._cursorX or 0)) / uiScale) / scale
    local dy = (((cy or 0) - (h._cursorY or 0)) / uiScale) / scale
    dx, dy = Preview.ActiveHandleDelta(h, dx, dy)
    local nextX = RoundOffset((h._startX or 0) + dx)
    local nextY = RoundOffset((h._startY or 0) + dy)
    if nextX ~= h._startX or nextY ~= h._startY then h._didDragMove = true end
    if h._lastDragX == nextX and h._lastDragY == nextY then return end
    h._lastDragX = nextX
    h._lastDragY = nextY
    WriteHandleOffsets(h, nextX, nextY, "UNIT_PREVIEW_DRAG")
end
--- Gives the keyboard back: the shared capture release when it exists, else the plain propagate flag.
local function ReleasePreviewKeyboard(box)
    if PreviewHelpers.ReleaseKeyboardCapture then
        PreviewHelpers.ReleaseKeyboardCapture(box)
    elseif box.SetPropagateKeyboardInput then
        box:SetPropagateKeyboardInput(true)
    end
end
MSUF.UFPreviewInput = {
    MakeHandle = MakeHandle, ArrowKeyDown = PreviewArrowKeyDown,
    DragUpdate = HandleDragUpdate, ReleaseKeyboard = ReleasePreviewKeyboard,
}
