-- InstallColorPicker: isolated ownership, bound once during addon initialization.
local _, MSUF = ...
local M = MSUF.MSUF2
M.InstallColorPicker = function(dependencies)
local floor = math.floor
local max = math.max
local min = math.min
local M = dependencies.M
local NextRow = dependencies.NextRow
local RegisterSearchObject = dependencies.RegisterSearchObject
local SetSearchText = dependencies.SetSearchText
local T = dependencies.T
local Tr = dependencies.Tr
local W = dependencies.W
local function ColorSetRGB(self, r, g, b)
    self._msuf2R = tonumber(r) or 1
    self._msuf2G = tonumber(g) or 1
    self._msuf2B = tonumber(b) or 1
    if self._msuf2Swatch.SetColorTexture then
        self._msuf2Swatch:SetColorTexture(self._msuf2R, self._msuf2G, self._msuf2B, 1)
    else
        self._msuf2Swatch:SetVertexColor(self._msuf2R, self._msuf2G, self._msuf2B, 1)
    end
    local mirrors = self._msuf2ColorMirrors
    for i = 1, #(mirrors or {}) do mirrors[i](self._msuf2R, self._msuf2G, self._msuf2B) end
end
local function ColorGetRGB(self) return self._msuf2R or 1, self._msuf2G or 1, self._msuf2B or 1 end
local function ColorSetOnColorChanged(self, fn) self._msuf2OnColorChanged = fn end
local colorPickerPlus
local function ClampColor(value)
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end
local function ColorByte(value) return floor(ClampColor(value) * 255 + 0.5) end
local function ColorHex(r, g, b)
    return string.format("#%02X%02X%02X", ColorByte(r), ColorByte(g), ColorByte(b))
end
local function HexColor(value)
    local hex = tostring(value or ""):match("^%s*#?(%x%x%x%x%x%x)%s*$")
    if not hex then return nil end
    return (tonumber(hex:sub(1, 2), 16) or 255) / 255,
           (tonumber(hex:sub(3, 4), 16) or 255) / 255,
           (tonumber(hex:sub(5, 6), 16) or 255) / 255
end
local function ColorPickerPlusStore()
    local db = type(M.EnsureDB) == "function" and M.EnsureDB() or _G.MSUF_DB
    if type(db) ~= "table" then return nil end
    db.menu2ColorPicker = type(db.menu2ColorPicker) == "table" and db.menu2ColorPicker or {}
    local store = db.menu2ColorPicker
    store.saved = type(store.saved) == "table" and store.saved or {}
    return store
end
local function AddRecentColor(hex)
    local store = ColorPickerPlusStore()
    if not store or not hex then return end
    store.recent = type(store.recent) == "table" and store.recent or {}
    for i = #store.recent, 1, -1 do
        if store.recent[i] == hex then table.remove(store.recent, i) end
    end
    table.insert(store.recent, 1, hex)
    while #store.recent > 9 do table.remove(store.recent) end
end
local function PickerPlusApply(r, g, b)
    local picker = _G.ColorPickerFrame
    if not picker then return end
    picker:SetColorRGB(ClampColor(r), ClampColor(g), ClampColor(b))
    if picker._msuf2ColorOwner then
        local nr, ng, nb = picker:GetColorRGB()
        picker._msuf2ColorOwner:SetRGB(nr, ng, nb)
        if picker._msuf2ColorOwner._msuf2OnColorChanged then
            picker._msuf2ColorOwner._msuf2OnColorChanged(nr, ng, nb)
        end
    end
    if colorPickerPlus and colorPickerPlus.Refresh then colorPickerPlus:Refresh() end
end
local function PickerPlusInput(parent, width, numeric)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(width, 22)
    edit:SetAutoFocus(false)
    edit:SetJustifyH("CENTER")
    edit:SetMaxLetters(numeric and 3 or 7)
    if edit.SetNumeric then edit:SetNumeric(numeric and true or false) end
    if T and T.SkinEditBox then T.SkinEditBox(edit) end
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); if colorPickerPlus then colorPickerPlus:Refresh() end end)
    edit:SetScript("OnEnterPressed", function(self)
        if type(self._msuf2Commit) == "function" then self:_msuf2Commit() end
        self:ClearFocus()
    end)
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and type(self._msuf2LiveCommit) == "function" then self:_msuf2LiveCommit() end
    end)
    return edit
end
local function PickerPlusSwatch(parent, size, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local edge = btn:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0.32, 0.42, 0.58, 0.9)
    local fill = btn:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(1, 1, 1, 1)
    btn._msuf2Fill = fill
    btn:SetScript("OnClick", onClick)
    return btn
end
local function EnsureColorPickerPlus()
    if colorPickerPlus or not _G.ColorPickerFrame then return colorPickerPlus end
    local picker = _G.ColorPickerFrame
    local panel = (T and T.Panel and T.Panel(picker, nil, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft))
        or CreateFrame("Frame", nil, picker, "BackdropTemplate")
    colorPickerPlus = panel
    panel:SetSize(344, 482)
    panel:SetPoint("TOPLEFT", picker, "TOPRIGHT", 8, 0)
    if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
    panel:SetFrameStrata(picker:GetFrameStrata())
    panel:SetFrameLevel((picker:GetFrameLevel() or 1) + 20)
    if T and T.ApplySurface then T.ApplySurface(panel, "popup") end

    local title = T.Font(panel, "GameFontNormalLarge", Tr("Precision color editor"), T.colors.text, "heading")
    title:SetPoint("TOPLEFT", 16, -14)
    local target = T.Font(panel, "GameFontHighlightSmall", "", T.colors.muted, "supporting")
    target:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    target:SetWidth(310)
    target:SetJustifyH("LEFT")
    panel._msuf2Target = target

    local original = panel:CreateTexture(nil, "ARTWORK")
    original:SetPoint("TOPLEFT", 16, -62)
    original:SetSize(151, 34)
    local current = panel:CreateTexture(nil, "ARTWORK")
    current:SetPoint("TOPRIGHT", -16, -62)
    current:SetSize(151, 34)
    panel._msuf2Original, panel._msuf2Current = original, current
    local oldLabel = T.Font(panel, "GameFontDisableSmall", Tr("Original"), T.colors.dim)
    oldLabel:SetPoint("BOTTOMLEFT", original, "TOPLEFT", 0, 2)
    local newLabel = T.Font(panel, "GameFontDisableSmall", Tr("Current"), T.colors.dim)
    newLabel:SetPoint("BOTTOMRIGHT", current, "TOPRIGHT", 0, 2)

    local rgbLabel = T.Font(panel, "GameFontNormalSmall", "RGB", T.colors.muted)
    rgbLabel:SetPoint("TOPLEFT", 16, -108)
    local fields = {}
    for i, label in ipairs({ "R", "G", "B" }) do
        local field = PickerPlusInput(panel, 58, true)
        field:SetPoint("TOPLEFT", 52 + (i - 1) * 66, -104)
        local fs = T.Font(panel, "GameFontDisableSmall", label, T.colors.dim)
        fs:SetPoint("RIGHT", field, "LEFT", -3, 0)
        fields[i] = field
        field._msuf2Commit = function()
            local pickerFrame = _G.ColorPickerFrame
            if not pickerFrame then return end
            local r, g, b = pickerFrame:GetColorRGB()
            local values = { ColorByte(r), ColorByte(g), ColorByte(b) }
            values[i] = min(255, max(0, tonumber(field:GetText()) or values[i]))
            PickerPlusApply(values[1] / 255, values[2] / 255, values[3] / 255)
        end
        field._msuf2LiveCommit = function()
            if tonumber(field:GetText()) then field:_msuf2Commit() end
        end
    end
    panel._msuf2RGB = fields
    local hexLabel = T.Font(panel, "GameFontNormalSmall", "HEX", T.colors.muted)
    hexLabel:SetPoint("TOPLEFT", 16, -140)
    local hex = PickerPlusInput(panel, 118, false)
    hex:SetPoint("TOPLEFT", 52, -136)
    hex._msuf2Commit = function(self)
        local r, g, b = HexColor(self:GetText())
        if r then PickerPlusApply(r, g, b) elseif colorPickerPlus then colorPickerPlus:Refresh() end
    end
    hex._msuf2LiveCommit = function(self)
        local r, g, b = HexColor(self:GetText())
        if r then PickerPlusApply(r, g, b) end
    end
    panel._msuf2Hex = hex
    local copy = T.Button(panel, Tr("Copy"), 68, 22)
    copy:SetPoint("LEFT", hex, "RIGHT", 8, 0)
    copy:SetScript("OnClick", function()
        hex:SetFocus()
        hex:HighlightText()
    end)
    local save = T.Button(panel, Tr("Save"), 68, 22)
    save:SetPoint("LEFT", copy, "RIGHT", 6, 0)
    save:SetScript("OnClick", function()
        local store = ColorPickerPlusStore()
        local pickerFrame = _G.ColorPickerFrame
        if not (store and pickerFrame) then return end
        local r, g, b = pickerFrame:GetColorRGB()
        local value = ColorHex(r, g, b)
        for i = 1, #store.saved do if store.saved[i] == value then return end end
        if #store.saved < 27 then store.saved[#store.saved + 1] = value end
        panel:RefreshPalettes()
    end)

    local recentTitle = T.Font(panel, "GameFontNormalSmall", Tr("Recent"), T.colors.text)
    recentTitle:SetPoint("TOPLEFT", 16, -176)
    local savedTitle = T.Font(panel, "GameFontNormalSmall", Tr("Saved colors"), T.colors.text)
    savedTitle:SetPoint("TOPLEFT", 16, -230)
    local savedHint = T.Font(panel, "GameFontDisableSmall", Tr("Right-click a saved color to remove it."), T.colors.dim)
    savedHint:SetPoint("TOPRIGHT", -16, -230)
    panel._msuf2RecentButtons, panel._msuf2SavedButtons = {}, {}
    for i = 1, 9 do
        local btn = PickerPlusSwatch(panel, 24, function(self)
            local r, g, b = HexColor(self._msuf2Hex)
            if r then PickerPlusApply(r, g, b) end
        end)
        btn:SetPoint("TOPLEFT", 16 + (i - 1) * 34, -194)
        panel._msuf2RecentButtons[i] = btn
    end
    for i = 1, 27 do
        local col, row = (i - 1) % 9, floor((i - 1) / 9)
        local btn = PickerPlusSwatch(panel, 24, function(self, button)
            local store = ColorPickerPlusStore()
            if button == "RightButton" and store then
                table.remove(store.saved, self._msuf2Index)
                panel:RefreshPalettes()
                return
            end
            local r, g, b = HexColor(self._msuf2Hex)
            if r then PickerPlusApply(r, g, b) end
        end)
        btn._msuf2Index = i
        btn:SetPoint("TOPLEFT", 16 + col * 34, -250 - row * 31)
        panel._msuf2SavedButtons[i] = btn
    end

    local classTitle = T.Font(panel, "GameFontNormalSmall", Tr("Class colors"), T.colors.text)
    classTitle:SetPoint("TOPLEFT", 16, -354)
    panel._msuf2ClassButtons = {}
    local tokens = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }
    for i = 1, #tokens do
        local col, row = (i - 1) % 7, floor((i - 1) / 7)
        local token = tokens[i]
        local btn = PickerPlusSwatch(panel, 28, function(self)
            local c = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[self._msuf2Token]
            if c then PickerPlusApply(c.r, c.g, c.b) end
        end)
        btn._msuf2Token = token
        btn:SetPoint("TOPLEFT", 16 + col * 44, -374 - row * 34)
        if M.AddTooltip then M.AddTooltip(btn, token:gsub("DEATHKNIGHT", "Death Knight"):gsub("DEMONHUNTER", "Demon Hunter"), Tr("Apply this class color.")) end
        panel._msuf2ClassButtons[i] = btn
    end
    local note = T.Font(panel, "GameFontDisableSmall", Tr("Opacity remains beside the setting when that element supports it."), T.colors.dim)
    note:SetPoint("BOTTOMLEFT", 16, 14)
    note:SetWidth(312)

    function panel:RefreshPalettes()
        local store = ColorPickerPlusStore() or {}
        local function RefreshButtons(buttons, values)
            values = type(values) == "table" and values or {}
            for i = 1, #buttons do
                local btn, value = buttons[i], values[i]
                btn._msuf2Hex = value
                btn:SetShown(value ~= nil)
                if value then
                    local r, g, b = HexColor(value)
                    btn._msuf2Fill:SetColorTexture(r or 1, g or 1, b or 1, 1)
                end
            end
        end
        RefreshButtons(self._msuf2RecentButtons, store.recent)
        RefreshButtons(self._msuf2SavedButtons, store.saved)
        for i = 1, #self._msuf2ClassButtons do
            local btn = self._msuf2ClassButtons[i]
            local c = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[btn._msuf2Token]
            btn._msuf2Fill:SetColorTexture(c and c.r or 1, c and c.g or 1, c and c.b or 1, 1)
        end
    end
    function panel:Refresh()
        local pickerFrame = _G.ColorPickerFrame
        local owner = pickerFrame and pickerFrame._msuf2ColorOwner
        if not (pickerFrame and owner) then return end
        local r, g, b = pickerFrame:GetColorRGB()
        self._msuf2Current:SetColorTexture(r, g, b, 1)
        self._msuf2Original:SetColorTexture(owner._msuf2PrevR or r, owner._msuf2PrevG or g, owner._msuf2PrevB or b, 1)
        self._msuf2Target:SetText(Tr(owner._msuf2ColorLabel or owner._msuf2SearchText or "Selected color"))
        if not self._msuf2Hex:HasFocus() then self._msuf2Hex:SetText(ColorHex(r, g, b)) end
        local bytes = { ColorByte(r), ColorByte(g), ColorByte(b) }
        for i = 1, 3 do if not self._msuf2RGB[i]:HasFocus() then self._msuf2RGB[i]:SetText(bytes[i]) end end
        self:RefreshPalettes()
    end
    function panel:LayoutBesidePicker()
        local pickerFrame = _G.ColorPickerFrame
        if not pickerFrame then return end
        local uiW = _G.UIParent and _G.UIParent.GetWidth and _G.UIParent:GetWidth()
        local pickerRight = pickerFrame.GetRight and pickerFrame:GetRight()
        self:ClearAllPoints()
        if uiW and pickerRight and pickerRight + 352 > uiW then
            self:SetPoint("TOPRIGHT", pickerFrame, "TOPLEFT", -8, 0)
        else
            self:SetPoint("TOPLEFT", pickerFrame, "TOPRIGHT", 8, 0)
        end
    end
    panel:Hide()
    return panel
end
local function ColorApply(btn, r, g, b)
    btn:SetRGB(r, g, b)
    if btn._msuf2OnColorChanged then btn._msuf2OnColorChanged(r, g, b) end
    if colorPickerPlus and colorPickerPlus:IsShown() then colorPickerPlus:Refresh() end
end
local function ColorPickerCommit()
    local picker, btn = ColorPickerFrame, ColorPickerFrame and ColorPickerFrame._msuf2ColorOwner
    if not (picker and btn) then return end
    local r, g, b = picker:GetColorRGB()
    ColorApply(btn, r, g, b)
end
local function ColorPickerCancel(prev)
    local btn = ColorPickerFrame and ColorPickerFrame._msuf2ColorOwner
    if not btn then return end
    local r, g, b = btn._msuf2PrevR or 1, btn._msuf2PrevG or 1, btn._msuf2PrevB or 1
    if type(prev) == "table" then r, g, b = prev.r or r, prev.g or g, prev.b or b end
    if ColorPickerFrame then ColorPickerFrame._msuf2ColorCancelled = true end
    ColorApply(btn, r, g, b)
end
local colorPickerHideHooked = false
local function EnsureColorPickerHideHook()
    if colorPickerHideHooked or not (ColorPickerFrame and ColorPickerFrame.HookScript) then return end
    colorPickerHideHooked = true
    ColorPickerFrame:HookScript("OnHide", function(self)
        local btn = self and self._msuf2ColorOwner
        if btn and not self._msuf2ColorCancelled then
            local r, g, b = btn:GetRGB()
            AddRecentColor(ColorHex(r, g, b))
        end
        self._msuf2ColorCancelled = nil
        if colorPickerPlus then colorPickerPlus:Hide() end
        if btn and type(btn._msuf2CommitColorInteraction) == "function" then
            btn:_msuf2CommitColorInteraction()
        end
    end)
end
function W.CloseMenuOwnedColorPicker()
    if colorPickerPlus and colorPickerPlus.Hide then colorPickerPlus:Hide() end
    local picker = _G.ColorPickerFrame
    if not (picker and picker._msuf2ColorOwner) then return false end
    if picker.Hide then picker:Hide() end
    picker._msuf2ColorOwner = nil
    return true
end
local function ColorButtonOnClick(self)
    if W and type(W.OpenColorContextPicker) == "function" then
        W.OpenColorContextPicker(
            self._msuf2ColorContextTitle or self._msuf2ColorLabel,
            self._msuf2ColorContextOwners or { self },
            self._msuf2ColorContextNote,
            self
        )
        return
    end
    if not ColorPickerFrame then return end
    local r, g, b = self:GetRGB()
    local picker = ColorPickerFrame
    EnsureColorPickerHideHook()
    if picker._msuf2ColorOwner and picker._msuf2ColorOwner ~= self and type(picker._msuf2ColorOwner._msuf2CommitColorInteraction) == "function" then
        picker._msuf2ColorOwner:_msuf2CommitColorInteraction()
    end
    picker._msuf2ColorOwner = self
    picker._msuf2ColorCancelled = nil
    if type(self._msuf2BeginColorInteraction) == "function" then self:_msuf2BeginColorInteraction() end
    self._msuf2PrevR, self._msuf2PrevG, self._msuf2PrevB = r, g, b
    if picker.SetupColorPickerAndShow then
        picker:SetupColorPickerAndShow({
            r = r, g = g, b = b, opacity = 1, hasOpacity = false,
            swatchFunc = ColorPickerCommit,
            cancelFunc = ColorPickerCancel,
            previousValues = { r = r, g = g, b = b, opacity = 1 },
        })
    else
        picker.func, picker.cancelFunc = ColorPickerCommit, ColorPickerCancel
        picker:SetColorRGB(r, g, b)
        picker:Show()
    end
    local plus = EnsureColorPickerPlus()
    if plus then plus:LayoutBesidePicker(); plus:Show(); plus:Refresh() end
end

--- Color buttons use Blizzard's shared ColorPickerFrame but keep previous RGB
--- values on the button so cancel can restore the UI state.
function W.Color(section, label)
    local x, y = NextRow(section, 32)
    local title = T.Font(section, "GameFontHighlightSmall", Tr(label or ""), T.colors.text, "control")
    SetSearchText(title, label)
    title:SetPoint("TOPLEFT", x, y)
    title:SetWidth(230)
    local btn = CreateFrame("Button", nil, section)
    btn._msuf2Title = title
    btn._msuf2ColorLabel = label
    btn._msuf2ControlKind = "color"
    RegisterSearchObject(btn, label, "color", { anchor = title })
    btn:SetPoint("TOPLEFT", x + 250, y + 2)
    btn:SetSize(44, 20)
    btn._msuf2Swatch, btn._msuf2Edge = T.CreateSuperellipseLayers(btn, "_msuf2Color", 1, "ARTWORK", "ARTWORK")
    btn._msuf2Edge:SetVertexColor(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.75)
    btn.SetRGB = ColorSetRGB
    btn.GetRGB = ColorGetRGB
    btn.SetOnColorChanged = ColorSetOnColorChanged
    btn:SetRGB(1, 1, 1)
    btn:SetScript("OnClick", ColorButtonOnClick)
    return btn
end


return HexColor
end
