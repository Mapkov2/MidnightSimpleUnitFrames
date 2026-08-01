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
    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    title:SetPoint("LEFT", anchor, "RIGHT", gap, 0)
    title:SetText(caption)
    if T and T.StyleFontString then T.StyleFontString(title, colors.muted or { 0.62, 0.70, 0.82, 1 }, 0) end
    local edit = CreateFrame("EditBox", nil, bar, "InputBoxTemplate")
    edit:SetPoint("LEFT", title, "RIGHT", 5, 0)
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
    local stepper = CreateFrame("Frame", nil, bar)
    stepper:SetSize(15, 18)
    stepper:SetPoint("LEFT", edit, "RIGHT", 3, 0)
    for _, spec in ipairs({ { "TOP", 1, "+" }, { "BOTTOM", -1, "-" } }) do
        local btn = CreateFrame("Button", nil, stepper, "BackdropTemplate")
        btn:SetSize(15, 9)
        btn:SetPoint(spec[1], stepper, spec[1], 0, 0)
        btn:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
        btn:SetBackdropColor(0.030, 0.070, 0.115, 0.94)
        btn:SetBackdropBorderColor(0.086, 0.149, 0.227, 0.85)
        btn.fs = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        btn.fs:SetPoint("CENTER", btn, "CENTER", 0, spec[2] > 0 and -1 or 1)
        btn.fs:SetText(spec[3])
        btn:SetScript("OnClick", function() StepAxis(box, axis, spec[2]) end)
    end
    return edit, stepper
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
        local dx, dy = Call(box, "DefaultOffsets", box, handle)
        if dx == nil then return end
        Call(box, "WriteOffsets", box, handle, dx, dy or 0, "PREVIEW_RESET_OFFSET")
        Call(box, "UpdateHint", box, handle)
        SB.Refresh(box)
    end)
    bar.openButton, bar.resetButton = openBtn, resetBtn

    if M.AddTooltip then
        M.AddTooltip(openBtn, "Open settings", "Jumps to the options section that owns the selected preview element.", { hook = true })
        M.AddTooltip(resetBtn, "Reset offset", "Puts the selected element back to its default X/Y offset.", { hook = true })
        M.AddTooltip(editX, "Exact offset", "Type an exact offset and press Enter. Arrow keys and dragging write the same setting.", { hook = true })
        M.AddTooltip(editY, "Exact offset", "Type an exact offset and press Enter. Arrow keys and dragging write the same setting.", { hook = true })
    end

    function bar:MSUF2SetEnabled(enabled)
        enabled = enabled == true
        local widgets = { self.editX, self.editY, self.openButton, self.resetButton }
        for index = 1, #widgets do
            local widget = widgets[index]
            if widget.SetEnabled then widget:SetEnabled(enabled) end
            if widget.SetAlpha then widget:SetAlpha(enabled and 1 or 0.45) end
        end
        stepX:SetAlpha(enabled and 1 or 0.45)
        stepY:SetAlpha(enabled and 1 or 0.45)
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
