--- Shell/Menu2/MSUF_Menu2_PreviewSelectionBar.lua
--- Cold-path selection chrome shared by the Unit and Group frame previews.
---
--- Owns the two surfaces that answer "what is selected and where is it":
--- the selection bar (element name, exact X/Y inputs, reset, jump to settings)
--- and the element picker (a list of every placed handle, plus Tab cycling).
--- Both used to be carried by a single hint FontString that doubled as the
--- tutorial line, and dense frames had no way to reach an overlapped handle.
---
--- Each preview owns its handles, offsets and section routing, so the surface
--- registers those as dependencies on its own box instead of this file reaching
--- into either preview.
local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local SB = M.PreviewSelectionBar or {}
M.PreviewSelectionBar = SB
local F = M.Fallbacks or {}
local TEX_W8 = "Interface\\Buttons\\WHITE8X8"
local floor = math.floor

local function Deps(box)
    return (box and box._msuf2SelectionDeps) or nil
end
local function Call(box, name, ...)
    local deps = Deps(box)
    local fn = deps and deps[name]
    if type(fn) ~= "function" then return nil end
    return fn(...)
end
local function Tr(box, value)
    local deps = Deps(box)
    local fn = deps and deps.Tr
    if type(fn) == "function" then return fn(value) end
    return value
end
local function Theme(box)
    local deps = Deps(box)
    local fn = deps and deps.Theme
    if type(fn) == "function" then return fn() end
    return M.Theme
end
local function Round(box, value)
    local deps = Deps(box)
    local fn = deps and deps.Round
    if type(fn) == "function" then return fn(value) end
    return floor((tonumber(value) or 0) + 0.5)
end
local function ConfigLocked()
    return type(M.IsConfigCombatLocked) == "function" and M.IsConfigCombatLocked() == true
end
local function SelectionAttentionEnabled(box)
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    if type(general) == "table" and general.previewDragHintAnimationEnabled == false then return false end
    local T = Theme(box)
    return not (T and T.ReducedMotionEnabled and T.ReducedMotionEnabled())
end
local function ApplyBackdrop(box, frame, bg, border)
    local deps = Deps(box)
    local fn = deps and deps.ApplyBackdrop
    if type(fn) == "function" then return fn(frame, bg, border) end
    if not (frame and frame.SetBackdrop) then return end
    frame:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end
local function Chrome(box, frame, role)
    local helpers = M.PreviewHelpers or {}
    if helpers.ApplyPreviewChrome then
        helpers.ApplyPreviewChrome(frame, role, Theme(box), function(f, bg, border)
            ApplyBackdrop(box, f, bg, border)
        end)
        return
    end
    ApplyBackdrop(box, frame, { 0.020, 0.039, 0.071, 0.56 }, { 0.086, 0.149, 0.227, 0.32 })
end

--- A handle counts as reachable when the renderer actually placed it; hidden or
--- locked elements must never become a selectable row or a Tab stop.
local function IsPlaced(box, handle)
    if not handle then return false end
    local deps = Deps(box)
    local fn = deps and deps.IsPlaced
    if type(fn) == "function" then return fn(handle) == true end
    if handle._msufPlaced == false then return false end
    if handle.IsShown and not handle:IsShown() then return false end
    return true
end
local function SelectedHandle(box)
    local handle = box and box._selectedHandle
    if not IsPlaced(box, handle) then return nil end
    return handle
end
local function HandleLabel(box, handle)
    if not handle then return Tr(box, "No element selected") end
    local deps = Deps(box)
    local fn = deps and deps.HandleLabel
    if type(fn) == "function" then
        local label = fn(handle)
        if label and label ~= "" then return Tr(box, label) end
    end
    return Tr(box, handle._label or handle._key or "?")
end
local function PlacedHandles(box, out)
    out = out or {}
    for index = #out, 1, -1 do out[index] = nil end
    local deps = Deps(box)
    local list = deps and type(deps.HandleList) == "function" and deps.HandleList(box) or nil
    for index = 1, #(list or {}) do
        local handle = list[index]
        if IsPlaced(box, handle) then out[#out + 1] = handle end
    end
    return out
end
local function ReadOffsets(box, handle)
    local x, y = Call(box, "ReadOffsets", box, handle)
    return tonumber(x) or 0, tonumber(y) or 0
end

--- Resolve the center of a rendered preview handle in one shared coordinate
--- space. Preview surfaces can use this for elements whose controls expose an
--- absolute visual position; anchor-local controls (such as Group Name) read
--- their stored offsets instead. For rendered coordinates the mock center is 0,0;
--- render scaling is divided back out so the readout remains stable at Fit,
--- 1:1, any manual zoom, and unit-specific runtime visual scales. This is
--- deliberately derived from rendered geometry instead
--- of SavedVariables: imported legacy and direct-layout profiles can store the
--- same visual placement in very different anchor/offset key families.
function SB.ReadRenderedCoordinates(handle, reference, renderScale)
    if not (handle and reference and handle.GetCenter and reference.GetCenter) then return nil end
    local hx, hy = handle:GetCenter()
    local rx, ry = reference:GetCenter()
    if hx == nil or hy == nil or rx == nil or ry == nil then return nil end
    renderScale = tonumber(renderScale) or 1
    if renderScale <= 0 then renderScale = 1 end
    return (hx - rx) / renderScale, (hy - ry) / renderScale
end

local function HandleByKey(box, handleKey)
    local deps = Deps(box)
    local list = deps and type(deps.HandleList) == "function" and deps.HandleList(box) or nil
    for index = 1, #(list or {}) do
        local handle = list[index]
        if handle and tostring(handle._key or "") == tostring(handleKey or "") then return handle end
    end
end

--- Builds the command behind an exact X/Y field whose visible selection bar is
--- shared by many preview handles. The command pins reads and writes to the
--- declared handle so Assistant routing never depends on whichever element the
--- user happened to select last.
function SB.BuildExactOffsetCommand(box, handleKey, axis, metadata)
    axis = axis == "y" and "y" or "x"
    metadata = type(metadata) == "table" and metadata or {}
    local command = {
        kind = "textinput",
        historyMode = "single",
        interaction = "preview.handle.offset",
        previewSurface = metadata.previewSurface,
        previewHandleKey = handleKey,
        previewUnitKey = metadata.previewUnitKey,
        previewScope = metadata.previewScope,
    }
    command.get = function()
        local handle = HandleByKey(box, handleKey)
        if not handle then return nil end
        local x, y = ReadOffsets(box, handle)
        return axis == "x" and x or y
    end
    command.set = function(value)
        local handle = HandleByKey(box, handleKey)
        value = tonumber(value)
        if not handle or value == nil or ConfigLocked() then return false end
        local x, y = ReadOffsets(box, handle)
        if axis == "x" then x = Round(box, value) else y = Round(box, value) end
        Call(box, "SelectHandle", box, handle)
        local ok = Call(box, "WriteOffsets", box, handle, x, y, "PREVIEW_ASSISTANT_EXACT_OFFSET")
        Call(box, "UpdateHint", box, handle)
        SB.Refresh(box)
        return ok ~= false
    end
    return command
end

--- Exact search highlighting should show the same handle that owns the shared
--- X/Y input. This hook is consumed only by the cold Search/Assistant route.
function SB.BindExactOffsetSearchTarget(widget, box, handleKey)
    if not widget then return widget end
    widget._msuf2PrepareExactSearchTarget = function()
        local handle = HandleByKey(box, handleKey)
        if not handle then return false end
        Call(box, "SelectHandle", box, handle)
        Call(box, "UpdateHint", box, handle)
        SB.Refresh(box)
        return true
    end
    return widget
end

--------------------------------------------------------------------------
-- Selection bar
--------------------------------------------------------------------------

function SB.Refresh(box)
    local bar = box and box._msuf2SelectionBar
    if not bar then return end
    local handle = SelectedHandle(box)
    local editing = bar.editX._msuf2Focused == true or bar.editY._msuf2Focused == true
    bar.label:SetText(HandleLabel(box, handle))
    if handle then
        local c = handle._color or { 0.70, 0.80, 1.00 }
        bar.swatch:SetColorTexture(c[1], c[2], c[3], 1)
        bar.label:SetTextColor(0.90, 0.94, 1.00, 1)
        if not editing then
            local x, y = ReadOffsets(box, handle)
            bar.editX:SetText(tostring(Round(box, x)))
            bar.editY:SetText(tostring(Round(box, y)))
        end
    else
        bar.swatch:SetColorTexture(0.30, 0.36, 0.46, 0.55)
        bar.label:SetTextColor(0.55, 0.62, 0.74, 0.90)
        if not editing then
            bar.editX:SetText("")
            bar.editY:SetText("")
        end
    end
    bar:MSUF2SetEnabled(handle ~= nil and not ConfigLocked())
    bar:MSUF2SetSelected(handle ~= nil)
    if handle and handle ~= bar._msuf2AttentionHandle then bar:MSUF2PulseAxes() end
    bar._msuf2AttentionHandle = handle
    if box._msuf2ElementPicker then box._msuf2ElementPicker:MSUF2Refresh() end
end

local function CommitAxis(box, axis, raw)
    local handle = SelectedHandle(box)
    local value = tonumber(raw)
    if not handle or ConfigLocked() or value == nil then
        SB.Refresh(box)
        return false
    end
    local x, y = ReadOffsets(box, handle)
    if axis == "x" then x = Round(box, value) else y = Round(box, value) end
    Call(box, "WriteOffsets", box, handle, x, y, "PREVIEW_EXACT_OFFSET")
    Call(box, "UpdateHint", box, handle)
    SB.Refresh(box)
    return true
end

local function StepAxis(box, axis, delta)
    local handle = SelectedHandle(box)
    if not handle or ConfigLocked() then return false end
    local ok = Call(box, "NudgeDelta", box, axis == "x" and delta or 0, axis == "y" and delta or 0)
    Call(box, "UpdateHint", box, box._selectedHandle)
    SB.Refresh(box)
    return ok == true
end

local function BuildAxis(box, bar, axis, caption, anchor, gap)
    local T = Theme(box)
    local colors = (T and T.colors) or {}
    local controls = CreateFrame("Frame", nil, bar)
    controls:SetSize(98, 18)
    controls:SetPoint("LEFT", anchor, "RIGHT", gap, 0)

    local attention = controls:CreateTexture(nil, "BACKGROUND")
    attention:SetAllPoints(controls)
    attention:SetColorTexture(0.18, 0.70, 1.00, 0.32)
    attention:SetAlpha(0)
    attention:Hide()

    local function StepButton(delta, glyph)
        local btn = CreateFrame("Button", nil, controls, "BackdropTemplate")
        btn:SetSize(18, 18)
        btn:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
        btn:SetBackdropColor(0.030, 0.070, 0.115, 0.94)
        btn:SetBackdropBorderColor(0.086, 0.149, 0.227, 0.85)
        btn.fs = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        btn.fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btn.fs:SetText(glyph)
        btn:SetScript("OnClick", function() StepAxis(box, axis, delta) end)
        return btn
    end

    local minus = StepButton(-1, "-")
    minus:SetPoint("LEFT", controls, "LEFT", 0, 0)
    local titleHolder = CreateFrame("Frame", nil, controls)
    titleHolder:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    titleHolder:SetSize(8, 18)
    local title = titleHolder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    title:SetAllPoints(titleHolder)
    title:SetJustifyH("CENTER")
    title:SetText(caption)
    if T and T.StyleFontString then T.StyleFontString(title, colors.muted or { 0.62, 0.70, 0.82, 1 }, 0) end
    local edit = CreateFrame("EditBox", nil, controls, "InputBoxTemplate")
    edit:SetPoint("LEFT", titleHolder, "RIGHT", 3, 0)
    edit:SetSize(44, 18)
    edit:SetAutoFocus(false)
    edit:SetJustifyH("RIGHT")
    edit:SetMaxLetters(6)
    if T and T.SkinEditBox then T.SkinEditBox(edit) end
    edit:SetScript("OnEditFocusGained", function(self) self._msuf2Focused = true end)
    edit:SetScript("OnEscapePressed", function(self)
        self._msuf2Focused = nil
        self:ClearFocus()
        SB.Refresh(box)
    end)
    edit:SetScript("OnEnterPressed", function(self)
        self._msuf2Focused = nil
        CommitAxis(box, axis, self:GetText())
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        self._msuf2Focused = nil
        CommitAxis(box, axis, self:GetText())
    end)
    local plus = StepButton(1, "+")
    plus:SetPoint("LEFT", edit, "RIGHT", 3, 0)
    controls.minusButton, controls.plusButton = minus, plus
    controls.titleHolder, controls.title, controls.edit, controls.attention = titleHolder, title, edit, attention

    function controls:MSUF2SetSelected(selected)
        selected = selected == true
        self:SetSize(selected and 110 or 98, selected and 22 or 18)
        self.minusButton:SetSize(selected and 22 or 18, selected and 22 or 18)
        self.plusButton:SetSize(selected and 22 or 18, selected and 22 or 18)
        self.titleHolder:SetSize(selected and 10 or 8, selected and 22 or 18)
        self.edit:SetSize(selected and 46 or 44, selected and 22 or 18)
        if selected then
            self.title:SetTextColor(0.66, 0.90, 1.00, 1)
        else
            local muted = colors.muted or { 0.62, 0.70, 0.82, 1 }
            self.title:SetTextColor(muted[1], muted[2], muted[3], muted[4] or 1)
        end
    end

    if attention.CreateAnimationGroup then
        local group = attention:CreateAnimationGroup()
        if T and T.TrackMenuAnimationGroup then T.TrackMenuAnimationGroup(group) end
        local fadeIn = group:CreateAnimation("Alpha")
        fadeIn:SetOrder(1)
        fadeIn:SetFromAlpha(0)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.16)
        if fadeIn.SetSmoothing then fadeIn:SetSmoothing("OUT") end
        local fadeOut = group:CreateAnimation("Alpha")
        fadeOut:SetOrder(2)
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0)
        fadeOut:SetDuration(0.44)
        if fadeOut.SetSmoothing then fadeOut:SetSmoothing("IN_OUT") end
        group:SetScript("OnFinished", function()
            attention:SetAlpha(0)
            attention:Hide()
            titleHolder:SetAlpha(1)
        end)
        controls._msuf2AttentionAnim = group
    end
    if titleHolder.CreateAnimationGroup then
        local group = titleHolder:CreateAnimationGroup()
        if T and T.TrackMenuAnimationGroup then T.TrackMenuAnimationGroup(group) end
        local dim = group:CreateAnimation("Alpha")
        dim:SetOrder(1)
        dim:SetFromAlpha(1)
        dim:SetToAlpha(0.28)
        dim:SetDuration(0.16)
        if dim.SetSmoothing then dim:SetSmoothing("IN") end
        local brighten = group:CreateAnimation("Alpha")
        brighten:SetOrder(2)
        brighten:SetFromAlpha(0.28)
        brighten:SetToAlpha(1)
        brighten:SetDuration(0.44)
        if brighten.SetSmoothing then brighten:SetSmoothing("OUT") end
        group:SetScript("OnFinished", function() titleHolder:SetAlpha(1) end)
        controls._msuf2TitleAttentionAnim = group
    end

    function controls:MSUF2Pulse()
        local group = self._msuf2AttentionAnim
        if group and group.Stop then group:Stop() end
        local titleGroup = self._msuf2TitleAttentionAnim
        if titleGroup and titleGroup.Stop then titleGroup:Stop() end
        self.titleHolder:SetAlpha(1)
        if group and group.Play then
            self.attention:SetAlpha(0)
            self.attention:Show()
            group:Play()
        else
            self.attention:SetAlpha(0)
            self.attention:Hide()
        end
        if titleGroup and titleGroup.Play then titleGroup:Play() end
    end
    return edit, controls
end

function SB.Create(box, deps)
    if not box then return nil end
    box._msuf2SelectionDeps = deps or box._msuf2SelectionDeps or {}
    if box._msuf2SelectionBar then return box._msuf2SelectionBar end
    local T = Theme(box)
    local colors = (T and T.colors) or {}
    local bar = CreateFrame("Frame", nil, box, "BackdropTemplate")
    bar:SetHeight(24)
    Chrome(box, bar, "sidebar")
    local swatch = bar:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(8, 8)
    swatch:SetPoint("LEFT", bar, "LEFT", 10, 0)
    bar.swatch = swatch
    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", swatch, "RIGHT", 7, 0)
    label:SetJustifyH("LEFT")
    label:SetWidth(132)
    if label.SetMaxLines then label:SetMaxLines(1) end
    if T and T.StyleFontString then T.StyleFontString(label, colors.text or { 1, 1, 1, 1 }, 0) end
    bar.label = label
    local editX, stepX = BuildAxis(box, bar, "x", "X", label, 6)
    local editY, stepY = BuildAxis(box, bar, "y", "Y", stepX, 12)
    bar.editX, bar.editY = editX, editY
    bar.axisX, bar.axisY = stepX, stepY

    local openBtn = (T and T.Button and T.Button(bar, Tr(box, "Open settings"), 110, 18))
        or CreateFrame("Button", nil, bar, "BackdropTemplate")
    if T and T.CenterButtonLabel then T.CenterButtonLabel(openBtn) end
    openBtn:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
    openBtn:SetScript("OnClick", function()
        local handle = SelectedHandle(box)
        if handle then Call(box, "OpenSettings", box, handle, "selectionbar") end
    end)
    local resetBtn = (T and T.Button and T.Button(bar, Tr(box, "Reset"), 60, 18))
        or CreateFrame("Button", nil, bar, "BackdropTemplate")
    if T and T.CenterButtonLabel then T.CenterButtonLabel(resetBtn) end
    resetBtn:SetPoint("RIGHT", openBtn, "LEFT", -6, 0)
    resetBtn:SetScript("OnClick", function()
        local handle = SelectedHandle(box)
        if not handle or ConfigLocked() then return end
        local reset = Call(box, "ResetOffsets", box, handle, "PREVIEW_RESET_OFFSET")
        if reset == nil then
            local dx, dy = Call(box, "DefaultOffsets", box, handle)
            if dx == nil then return end
            Call(box, "WriteOffsets", box, handle, dx, dy or 0, "PREVIEW_RESET_OFFSET")
        end
        Call(box, "UpdateHint", box, handle)
        SB.Refresh(box)
    end)
    bar.openButton, bar.resetButton = openBtn, resetBtn

    if M.AddTooltip then
        M.AddTooltip(openBtn, "Open settings", "Jumps to the options section that owns the selected preview element.", { hook = true })
        M.AddTooltip(resetBtn, "Reset offset", "Puts the selected element back to its default X/Y offset.", { hook = true })
        M.AddTooltip(editX, "Exact X offset", "Edits the selected child element's local X offset. Positive values move right. Arrow keys and dragging update the same offset.", { hook = true })
        M.AddTooltip(editY, "Exact Y offset", "Edits the selected child element's local Y offset. Positive values move up. Arrow keys and dragging update the same offset.", { hook = true })
    end

    function bar:MSUF2SetEnabled(enabled)
        enabled = enabled == true
        local widgets = { self.editX, self.editY, self.openButton, self.resetButton }
        for index = 1, #widgets do
            local widget = widgets[index]
            if widget.SetEnabled then widget:SetEnabled(enabled) end
            if widget.SetAlpha then widget:SetAlpha(enabled and 1 or 0.45) end
        end
        for _, controls in ipairs({ stepX, stepY }) do
            controls:SetAlpha(enabled and 1 or 0.45)
            controls.minusButton:SetEnabled(enabled)
            controls.plusButton:SetEnabled(enabled)
        end
    end

    function bar:MSUF2SetSelected(selected)
        self.axisX:MSUF2SetSelected(selected)
        self.axisY:MSUF2SetSelected(selected)
    end

    function bar:MSUF2PulseAxes()
        if not SelectionAttentionEnabled(box) then return end
        self.axisX:MSUF2Pulse()
        self.axisY:MSUF2Pulse()
    end

    box._msuf2SelectionBar = bar
    SB.Refresh(box)
    return bar
end

--------------------------------------------------------------------------
-- Element picker
--------------------------------------------------------------------------

local function SelectHandle(box, handle)
    local ok = Call(box, "SelectHandle", box, handle)
    if ok == false then return false end
    Call(box, "UpdateHint", box, handle)
    SB.Refresh(box)
    return true
end

--- Tab moves to the next placed handle, Shift+Tab to the previous one. Dense
--- frames stack handles on top of each other, where clicking can only ever
--- reach the topmost one.
function SB.CycleHandle(box, backwards)
    if not box then return false end
    local placed = PlacedHandles(box, box._msuf2PlacedHandleScratch)
    box._msuf2PlacedHandleScratch = placed
    local count = #placed
    if count == 0 then return false end
    local current = box._selectedHandle
    local index = 0
    for position = 1, count do
        if placed[position] == current then
            index = position
            break
        end
    end
    local nextIndex
    if backwards then
        nextIndex = (index <= 1) and count or (index - 1)
    else
        nextIndex = (index >= count) and 1 or (index + 1)
    end
    return SelectHandle(box, placed[nextIndex])
end

local function EnsurePickerPopup(box, picker)
    local popup = box._msuf2ElementPickerPopup
    if popup then return popup end
    if type(M.CreateMenuPopupPanel) == "function" then
        popup = M.CreateMenuPopupPanel(UIParent, { name = nil, glass = "popup" })
    else
        popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        ApplyBackdrop(box, popup, { 0.014, 0.024, 0.050, 0.985 }, { 0.10, 0.22, 0.44, 0.80 })
    end
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:EnableMouse(true)
    popup:Hide()
    popup._rows = {}
    popup._anchor = picker
    box._msuf2ElementPickerPopup = popup
    return popup
end

local function PickerRow(box, popup, index)
    local row = popup._rows[index]
    if row then return row end
    local T = Theme(box)
    row = CreateFrame("Button", nil, popup)
    row:SetSize(190, 18)
    row:SetPoint("TOPLEFT", popup, "TOPLEFT", 6, -(6 + (index - 1) * 18))
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0, 0, 0, 0)
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(7, 7)
    row.dot:SetPoint("LEFT", row, "LEFT", 7, 0)
    row.fs = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.fs:SetPoint("LEFT", row.dot, "RIGHT", 7, 0)
    row.fs:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.fs:SetJustifyH("LEFT")
    if T and T.StyleFontString then T.StyleFontString(row.fs, { 0.82, 0.88, 1.00, 1 }, 0) end
    row:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.10, 0.28, 0.42, 0.55) end)
    row:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(0.08, 0.22, 0.34, self._msuf2Selected and 0.62 or 0)
    end)
    popup._rows[index] = row
    return row
end

local function RefreshPickerPopup(box, popup)
    local placed = PlacedHandles(box, popup._placed)
    popup._placed = placed
    local count = #placed
    for index = 1, count do
        local handle = placed[index]
        local row = PickerRow(box, popup, index)
        local c = handle._color or { 0.70, 0.80, 1.00 }
        row.dot:SetColorTexture(c[1], c[2], c[3], 1)
        row.fs:SetText(HandleLabel(box, handle))
        row._msuf2Selected = handle == box._selectedHandle
        row.bg:SetColorTexture(0.08, 0.22, 0.34, row._msuf2Selected and 0.62 or 0)
        row:SetScript("OnClick", function()
            popup:Hide()
            SelectHandle(box, handle)
        end)
        row:Show()
    end
    for index = count + 1, #popup._rows do popup._rows[index]:Hide() end
    popup:SetSize(202, math.max(24, 12 + count * 18))
    return count
end

function SB.CreatePicker(box, parent)
    if not (box and parent) then return nil end
    if box._msuf2ElementPicker then return box._msuf2ElementPicker end
    local T = Theme(box)
    local picker = CreateFrame("Button", nil, parent, "BackdropTemplate")
    picker:SetSize(158, 20)
    picker:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    if picker.SetFrameLevel and parent.GetFrameLevel then
        picker:SetFrameLevel((parent:GetFrameLevel() or 0) + 82)
    end
    picker.dot = picker:CreateTexture(nil, "ARTWORK")
    picker.dot:SetSize(7, 7)
    picker.dot:SetPoint("LEFT", picker, "LEFT", 7, 0)
    picker.fs = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    picker.fs:SetPoint("LEFT", picker.dot, "RIGHT", 7, 0)
    picker.fs:SetPoint("RIGHT", picker, "RIGHT", -16, 0)
    picker.fs:SetJustifyH("LEFT")
    picker.caret = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    picker.caret:SetPoint("RIGHT", picker, "RIGHT", -6, 0)
    picker.caret:SetText("v")
    local helpers = M.PreviewHelpers or {}
    if helpers.StylePreviewPillButton then helpers.StylePreviewPillButton(picker, T, { fontField = "fs" }) end

    function picker:MSUF2Refresh()
        local handle = SelectedHandle(box)
        local c = handle and (handle._color or { 0.70, 0.80, 1.00 }) or { 0.30, 0.36, 0.46 }
        self.dot:SetColorTexture(c[1], c[2], c[3], handle and 1 or 0.55)
        self.fs:SetText(HandleLabel(box, handle))
    end

    picker:SetScript("OnClick", function(self)
        local popup = EnsurePickerPopup(box, self)
        if popup:IsShown() then
            popup:Hide()
            return
        end
        if RefreshPickerPopup(box, popup) == 0 then return end
        if type(M.ApplyPopupFramePriority) == "function" then M.ApplyPopupFramePriority(popup) end
        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -3)
        popup:Show()
    end)
    picker:SetScript("OnHide", function()
        local popup = box._msuf2ElementPickerPopup
        if popup and popup.Hide then popup:Hide() end
    end)
    if M.AddTooltip then
        M.AddTooltip(picker, "Preview element", "Lists every element the preview placed, including those hidden behind another handle. Tab and Shift+Tab step through the same list.", { hook = true })
    end
    picker:MSUF2Refresh()
    box._msuf2ElementPicker = picker
    return picker
end

--- Compact previews are a reference strip, not an editing surface; the
--- selection chrome only belongs to the full canvas and the floating window.
function SB.SetShown(box, shown)
    -- Color Painter embeds the normal UF/GF preview renderers, but it is not
    -- an editing surface. Renderer refreshes may request their usual chrome;
    -- honor the per-preview owner flag so those refreshes cannot resurrect it.
    shown = shown == true and not (box and box._msuf2ColorPainterHideSelectionChrome == true)
    local bar = box and box._msuf2SelectionBar
    if bar then bar:SetShown(shown) end
    local picker = box and box._msuf2ElementPicker
    if picker then picker:SetShown(shown) end
    if not shown then
        local popup = box and box._msuf2ElementPickerPopup
        if popup and popup.Hide then popup:Hide() end
    end
end

SB.PlacedHandles = PlacedHandles
SB.SelectHandle = SelectHandle
return SB
