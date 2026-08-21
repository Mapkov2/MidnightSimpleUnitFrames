--- Shell/UI/MSUF_EditPopupUI.lua - shared Edit Mode popup UI helpers.
--- Defines popup styling and the quick popup controls used by Edit Mode.
local function InstallEditPopupUI(addonName, MSUF)
    local EM2 = _G.MSUF_EM2
    if not EM2 then return nil end
    if type(EM2.PopupFactory) == "table" and type(EM2.QuickPopup) == "table" then return EM2.PopupFactory end
    local ExportPublic = type(MSUF) == "table" and MSUF.ExportPublic or nil
    local function PublishCompat(name, value)
        if type(ExportPublic) == "function" then
            return ExportPublic(name, value)
        end
        _G[name] = value
        return value
    end
local Factory = {}
EM2.PopupFactory = Factory

local floor = math.floor
local W8 = "Interface/Buttons/WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF"
local MEDIA = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\"
local U = EM2.Util or {}

local C = {
    --- Match MSUF_THEME: bg=0.03/0.05/0.12, edge=0.10/0.20/0.45
    panelBg   = { 0.03, 0.05, 0.12, 0.95 },
    panelEdge = { 0.10, 0.20, 0.45, 0.90 },
    cardBg    = { 0.02, 0.03, 0.08, 0.40 },
    cardEdge  = { 0.10, 0.18, 0.38, 0.60 },
    divider   = { 0.10, 0.20, 0.45, 0.25 },
    gold      = { 1.00, 0.82, 0.00, 1.00 },
    orange    = { 0.90, 0.55, 0.15, 1.00 },
    title     = { 0.75, 0.88, 1.00, 1.00 },
    white     = { 0.86, 0.92, 1.00, 0.95 },
    muted     = { 0.55, 0.62, 0.78, 0.70 },
    inputBg   = { 0.02, 0.03, 0.08, 0.90 },
    inputEdge = { 0.10, 0.18, 0.38, 0.70 },
    stepBg    = { 0.09, 0.10, 0.15, 0.85 },
    stepHover = { 0.20, 0.40, 0.80, 0.15 },
    btnBg     = { 0.09, 0.10, 0.14, 0.90 },
    btnEdge   = { 0.10, 0.20, 0.42, 0.65 },
    btnHover  = { 0.20, 0.40, 0.80, 0.12 },
    checkFill = { 0.055, 0.145, 0.350, 1.00 },
    checkEdge = { 0.255, 0.455, 0.835, 0.90 },
}

local BOX_W    = 52
local BOX_H    = 24
local STEP_W   = 20

local Tr = U.Tr

local function FontSize(role)
    local ui = (type(MSUF) == "table" and MSUF.UI) or _G.MSUF_UI
    if ui and type(role) == "number" and ui.NormalizeFontSize then return ui.NormalizeFontSize(role) end
    return ui and ui.FontSize and ui.FontSize(role) or 13
end
local function Space(role, fallback)
    local ui = (type(MSUF) == "table" and MSUF.UI) or _G.MSUF_UI
    return ui and ui.Space and ui.Space(role, fallback) or fallback
end

local function FS(parent, role, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local ui = (type(MSUF) == "table" and MSUF.UI) or _G.MSUF_UI
    if ui and ui.ApplyFontRole then
        ui.ApplyFontRole(fs, role or "body", FONT, "")
    else
        fs:SetFont(FONT, FontSize(role or "body"), "")
    end
    fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 0.35)
    local c = color or C.white
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    return fs
end

local function SetReadableSize(fontObject, size)
    if not (fontObject and fontObject.SetFont) then return fontObject end
    local path, _, flags = fontObject.GetFont and fontObject:GetFont()
    fontObject:SetFont(path or FONT, tonumber(size) or 13, flags or "")
    return fontObject
end

local function SetButtonReadableSize(button, size)
    return SetReadableSize(button and (button._msuf2Label or button._label), size)
end

local SharedUI = (type(MSUF) == "table" and MSUF.UI) or _G.MSUF_UI
local Menu2Style = _G.MSUF_EM2_Menu2Style
if type(Menu2Style) ~= "table" or Menu2Style == SharedUI then Menu2Style = {} end
PublishCompat("MSUF_EM2_Menu2Style", Menu2Style)

function Menu2Style.Color(key, fallback)
    return SharedUI and SharedUI.Color and SharedUI.Color(key, fallback) or fallback
end

local function RefreshPalette()
    C.panelBg = Menu2Style.Color("popup", C.panelBg)
    C.panelEdge = Menu2Style.Color("borderSoft", C.panelEdge)
    C.cardBg = Menu2Style.Color("card", C.cardBg)
    C.cardEdge = Menu2Style.Color("borderSoft", C.cardEdge)
    C.divider = Menu2Style.Color("borderSoft", C.divider)
    C.gold = Menu2Style.Color("accent2", C.gold)
    C.orange = Menu2Style.Color("accent2", C.orange)
    C.title = Menu2Style.Color("accent", C.title)
    C.white = Menu2Style.Color("text", C.white)
    C.muted = Menu2Style.Color("muted", C.muted)
    C.inputBg = Menu2Style.Color("card", C.inputBg)
    C.inputEdge = Menu2Style.Color("borderSoft", C.inputEdge)
    C.stepBg = Menu2Style.Color("pillBase", C.stepBg)
    C.btnBg = Menu2Style.Color("pillBase", C.btnBg)
    C.btnEdge = Menu2Style.Color("pillEdge", C.btnEdge)
    C.checkFill = Menu2Style.Color("checkActive", C.checkFill)
    C.checkEdge = Menu2Style.Color("checkActiveEdge", C.checkEdge)
end

function Menu2Style.SetButtonText(btn, text)
    if SharedUI and SharedUI.SetButtonText then return SharedUI.SetButtonText(btn, text) end
    local label = btn and (btn._msuf2Label or btn._label)
    if label and label.SetText then label:SetText(Tr(text or "")) end
end

function Menu2Style.Shell(frame)
    if SharedUI and SharedUI.ApplyMaterial then return SharedUI.ApplyMaterial(frame, "popup") end
    return frame
end

function Menu2Style.Card(frame)
    if SharedUI and SharedUI.ApplyMaterial then return SharedUI.ApplyMaterial(frame, "card") end
    return frame
end

local function KeepMenu2Skin(widget)
    if widget then
        widget._msufNoSlashSkin = true
    end
    return widget
end

function Menu2Style.Button(parent, text, width, height, onClick, opts)
    opts = opts or {}
    if SharedUI and SharedUI.Button then
        return KeepMenu2Skin(SharedUI.Button(parent, text, width or 66, height or 24, {
            onClick = onClick,
            align = "CENTER",
            skipHistory = true,
            variant = opts.variant,
            active = opts.active,
        }))
    end
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 68, height or 24)
    b:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1 })
    b:SetBackdropColor(C.btnBg[1], C.btnBg[2], C.btnBg[3], 0.88)
    b:SetBackdropBorderColor(C.btnEdge[1], C.btnEdge[2], C.btnEdge[3], 0.82)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(C.btnHover[1], C.btnHover[2], C.btnHover[3], 0.18)
    local fs = FS(b, "caption", C.white)
    fs:SetPoint("CENTER")
    fs:SetText(Tr(text or ""))
    b._label = fs
    if onClick then b:SetScript("OnClick", onClick) end
    if opts.variant == "primary" then
        b:SetBackdropColor(0.16, 0.56, 0.72, 0.97)
        b:SetBackdropBorderColor(C.title[1], C.title[2], C.title[3], 0.95)
    end
    return KeepMenu2Skin(b)
end

function Menu2Style.Step(parent, text, width, height)
    if SharedUI and SharedUI.StepperButton then return KeepMenu2Skin(SharedUI.StepperButton(parent, text, width or STEP_W, height or BOX_H)) end
    return Menu2Style.Button(parent, text, width or STEP_W, height or BOX_H)
end

function Menu2Style.EditBox(editBox)
    local box = (SharedUI and SharedUI.EditBox and SharedUI.EditBox(editBox)) or editBox
    if box then box.__msufPeelEditSkinned = true end
    return box
end

function Menu2Style.CloseButton(parent, onClick)
    if SharedUI and SharedUI.CloseButton then return KeepMenu2Skin(SharedUI.CloseButton(parent, onClick)) end
    return Menu2Style.Button(parent, "x", 24, 24, onClick)
end

function Menu2Style.FadeIn(frame, duration, fromAlpha, toAlpha)
    if SharedUI and SharedUI.FadeIn then return SharedUI.FadeIn(frame, duration, fromAlpha, toAlpha) end
end

local function GetStep()
    local s = 1
    if IsShiftKeyDown and IsShiftKeyDown() then s = 5
    elseif IsControlKeyDown and IsControlKeyDown() then s = 10
    elseif IsAltKeyDown and IsAltKeyDown() then s = (EM2.Grid and EM2.Grid.GetGridStep()) or 20 end
    return s
end

local function RefreshUFPreview(reason)
    local fn = _G.MSUF_UFPreview_RequestRefresh
    if type(fn) == "function" then fn(reason or "EM2_POPUP") end
end

local function BlockConfigCombatLocked()
    if type(_G.MSUF_BlockConfigCombatLocked) == "function" then
        return _G.MSUF_BlockConfigCombatLocked() and true or false
    end
    if InCombatLockdown and InCombatLockdown() then
        if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then
            _G.MSUF_ShowConfigCombatLockMessage()
        end
        return true
    end
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then
            _G.MSUF_ShowConfigCombatLockMessage()
        end
        return true
    end
    return false
end

--- QuickPopup helpers keep the lightweight cast/aura/unit shortcut popups on
--- the same Menu2 visual system without each popup carrying its own shell,
--- stepper, editbox, and focus-cleanup copy.
local Quick = Menu2Style.QuickPopup
if type(Quick) ~= "table" then Quick = {} end
Menu2Style.QuickPopup = Quick
EM2.QuickPopup = Quick

local QC = {
    panelBg = { 0.03, 0.05, 0.12, 0.95 },
    panelEdge = { 0.10, 0.20, 0.45, 0.90 },
    cardBg = { 0.02, 0.03, 0.08, 0.64 },
    cardEdge = { 0.10, 0.18, 0.38, 0.72 },
    title = { 0.60, 0.80, 1.00, 1.00 },
    white = { 0.86, 0.92, 1.00, 0.95 },
    muted = { 0.55, 0.62, 0.78, 0.70 },
    inputBg = { 0.02, 0.03, 0.08, 0.90 },
    inputEdge = { 0.10, 0.18, 0.38, 0.70 },
    btnBg = { 0.09, 0.10, 0.14, 0.90 },
    btnEdge = { 0.10, 0.20, 0.42, 0.65 },
    btnHover = { 0.20, 0.40, 0.80, 0.12 },
}

function Quick.RefreshPalette()
    QC.panelBg = Menu2Style.Color("popup", QC.panelBg)
    QC.panelEdge = Menu2Style.Color("borderSoft", QC.panelEdge)
    QC.cardBg = Menu2Style.Color("card", QC.cardBg)
    QC.cardEdge = Menu2Style.Color("borderSoft", QC.cardEdge)
    QC.title = Menu2Style.Color("accent", QC.title)
    QC.white = Menu2Style.Color("text", QC.white)
    QC.muted = Menu2Style.Color("muted", QC.muted)
    QC.inputBg = Menu2Style.Color("card", QC.inputBg)
    QC.inputEdge = Menu2Style.Color("borderSoft", QC.inputEdge)
    QC.btnBg = Menu2Style.Color("pillBase", QC.btnBg)
    QC.btnEdge = Menu2Style.Color("pillEdge", QC.btnEdge)
    return QC
end

function Quick.Tr(text) return Tr(text) end
function Quick.FS(parent, role, color) return FS(parent, role, color) end
function Quick.GetStep() return GetStep() end

function Quick.San(value, fallback)
    value = tonumber(value) or fallback or 0
    if value ~= value or value > 2000 or value < -2000 then value = fallback or 0 end
    return floor(value + 0.5)
end

function Quick.BlockConfigCombatLocked()
    if type(_G.MSUF_BlockConfigCombatLocked) == "function" then
        return _G.MSUF_BlockConfigCombatLocked()
    end
    if _G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()) then
        if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then _G.MSUF_ShowConfigCombatLockMessage() end
        return true
    end
    return false
end

function Quick.KillOverlayPiece(piece)
    if not piece then return end
    if type(piece) == "table" then
        Quick.KillOverlayPiece(piece.L)
        Quick.KillOverlayPiece(piece.M)
        Quick.KillOverlayPiece(piece.R)
        Quick.KillOverlayPiece(piece.Left)
        Quick.KillOverlayPiece(piece.Middle)
        Quick.KillOverlayPiece(piece.Right)
    end
    if piece.Hide then piece:Hide() end
    if piece.SetAlpha then piece:SetAlpha(0) end
    if piece.SetColorTexture then piece:SetColorTexture(0, 0, 0, 0) end
end

function Quick.KeepButtonSkin(btn)
    if not btn then return btn end
    btn._msufNoSlashSkin = true
    btn.__msufPeelButtonSkinned = true
    Quick.KillOverlayPiece(btn._msufBtnBG)
    Quick.KillOverlayPiece(btn._msufBtnHover)
    Quick.KillOverlayPiece(btn._msufBtnDown)
    Quick.KillOverlayPiece(btn._msufBtnDisabled)
    Quick.KillOverlayPiece(btn._msufPeelFill)
    Quick.KillOverlayPiece(btn._msufPeelBorder)
    return btn
end

function Quick.KeepEditSkin(editBox)
    if not editBox then return editBox end
    editBox.__msufPeelEditSkinned = true
    Quick.KillOverlayPiece(editBox._msufMidnightBackdrop)
    return editBox
end

function Quick.AttachHoverWash(btn, opts)
    if not (btn and btn.CreateTexture) then return btn end
    opts = opts or {}
    local key = opts.key or "_msufEM2QuickHoverWash"
    if btn[key] then return btn end
    local c = Quick.RefreshPalette()
    local hl = btn:CreateTexture(nil, "HIGHLIGHT", nil, 2)
    hl:SetAllPoints()
    hl:SetColorTexture(c.btnHover[1], c.btnHover[2], c.btnHover[3], opts.alpha or 0.10)
    if hl.SetBlendMode then hl:SetBlendMode("ADD") end
    btn[key] = hl
    return btn
end

local function FinishQuickButton(btn, opts)
    opts = opts or {}
    if btn and btn.SetPropagateMouseClicks then btn:SetPropagateMouseClicks(false) end
    if opts.peelSkin then Quick.KeepButtonSkin(btn) end
    if opts.hoverWash then
        Quick.AttachHoverWash(btn, { key = opts.hoverKey, alpha = opts.hoverAlpha })
    end
    return btn
end

function Quick.Button(parent, text, w, h, onClick, opts)
    local c = Quick.RefreshPalette()
    local b
    if Menu2Style.Button then
        b = Menu2Style.Button(parent, Tr(text), w or 68, h or 32, onClick, opts)
        if Menu2Style.SetButtonText then Menu2Style.SetButtonText(b, text) end
    else
        b = CreateFrame("Button", nil, parent, "BackdropTemplate")
        b:SetSize(w or 68, h or 32)
        b:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
        b:SetBackdropColor(c.btnBg[1], c.btnBg[2], c.btnBg[3], c.btnBg[4])
        b:SetBackdropBorderColor(c.btnEdge[1], c.btnEdge[2], c.btnEdge[3], c.btnEdge[4])
        b._label = FS(b, "caption", c.white)
        b._label:SetPoint("CENTER")
    end
    if not Menu2Style.SetButtonText and b._label then b._label:SetText(Tr(text)) end
    SetButtonReadableSize(b, (opts and opts.fontSize) or ((text == "+" or text == "-") and 15 or 13))
    if onClick then b:SetScript("OnClick", onClick) end
    if opts and opts.active ~= nil and b.SetActive then b:SetActive(opts.active) end
    return FinishQuickButton(b, opts)
end

function Quick.AttachIcon(btn, texturePath, size)
    if not (btn and btn.CreateTexture and texturePath) then return nil end
    local label = btn._msuf2Label or btn._label
    if label and label.Hide then label:Hide() end
    local icon = btn:CreateTexture(nil, "ARTWORK", nil, 5)
    icon:SetTexture(texturePath)
    icon:SetSize(size or 17, size or 17)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn._quickIcon = icon
    return icon
end

function Quick.ToggleButton(parent, text, w, h, onClick, opts)
    opts = opts or {}
    local b = Quick.Button(parent, text, w, h, nil, opts)
    function b:SetCheckedVisual(checked)
        local c = opts.palette or Quick.RefreshPalette()
        self._checked = checked and true or false
        if opts.plain then
            if self.SetActive then self:SetActive(false) end
            return
        end
        if self.SetActive then
            self:SetActive(self._checked)
            return
        end
        if self._checked then
            self:SetBackdropColor(0.08, 0.16, 0.28, 0.96)
            self:SetBackdropBorderColor(c.title[1], c.title[2], c.title[3], 0.95)
            if self._label then self._label:SetTextColor(c.title[1], c.title[2], c.title[3], 1) end
        else
            self:SetBackdropColor(c.btnBg[1], c.btnBg[2], c.btnBg[3], 0.88)
            self:SetBackdropBorderColor(c.btnEdge[1], c.btnEdge[2], c.btnEdge[3], 0.82)
            if self._label then self._label:SetTextColor(c.white[1], c.white[2], c.white[3], c.white[4] or 1) end
        end
    end
    b:SetScript("OnClick", function(s)
        s:SetCheckedVisual(not s._checked)
        if onClick then onClick(s._checked) end
        if opts.sync then opts.sync() end
    end)
    b:SetCheckedVisual(false)
    return b
end

function Quick.Step(parent, text, opts)
    local b = (Menu2Style.Step and Menu2Style.Step(parent, text, 20, 22)) or Quick.Button(parent, text, 20, 22, nil, opts)
    return FinishQuickButton(b, opts)
end

function Quick.Box(parent, width, opts)
    local c = Quick.RefreshPalette()
    local b = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    b:SetSize(width or 52, (opts and opts.boxHeight) or 24)
    b:SetAutoFocus(false)
    b:SetNumeric(false)
    b:SetJustifyH("CENTER")
    b:SetMaxLetters(7)
    local ui = (type(MSUF) == "table" and MSUF.UI) or _G.MSUF_UI
    if ui and ui.ApplyFontRole then
        ui.ApplyFontRole(b, "body", FONT, "")
    else
        b:SetFont(FONT, FontSize("body"), "")
    end
    SetReadableSize(b, (opts and opts.valueFontSize) or 15)
    b:SetTextColor(c.white[1], c.white[2], c.white[3], c.white[4] or 1)
    if b.SetBackdrop then
        b:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
        b:SetBackdropColor(c.inputBg[1], c.inputBg[2], c.inputBg[3], c.inputBg[4] or 0.90)
        b:SetBackdropBorderColor(c.inputEdge[1], c.inputEdge[2], c.inputEdge[3], c.inputEdge[4] or 0.70)
    end
    if b.SetPropagateMouseClicks then b:SetPropagateMouseClicks(false) end
    if Menu2Style.EditBox then Menu2Style.EditBox(b) end
    if opts and opts.peelSkin then Quick.KeepEditSkin(b) end
    return b
end

function Quick.WireStepper(minus, box, plus, cb)
    local function commit(delta)
        --- A control with a fixed native step (box._msufStep, e.g. Blizzard
        --- Edit Mode sliders) must move by MULTIPLES of that step, or the
        --- setter rounds the value back onto the same raw and the click does
        --- nothing. Shift/Ctrl accelerate in native steps (×5/×10), exactly
        --- like the free-step boxes.
        local step = tonumber(box._msufStep)
        if step then
            if IsShiftKeyDown and IsShiftKeyDown() then step = step * 5
            elseif IsControlKeyDown and IsControlKeyDown() then step = step * 10 end
        else
            step = GetStep()
        end
        box:SetText(tostring(Quick.San(box:GetText(), 0) + ((delta or 0) * step)))
        if cb then cb() end
    end
    minus:SetScript("OnClick", function() commit(-1) end)
    plus:SetScript("OnClick", function() commit(1) end)
    box:SetScript("OnEnterPressed", function(s) s:ClearFocus(); if cb then cb() end end)
    box:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    box:SetScript("OnEditFocusLost", function() if cb then cb() end end)
end

function Quick.ValuePair(owner, parent, y, label1, key1, cb1, label2, key2, cb2, opts)
    local c = Quick.RefreshPalette()
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize((opts and opts.rowWidth) or 488, 32)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", (opts and opts.x) or 20, y)

    local l1 = SetReadableSize(FS(row, "caption", c.white), 13)
    l1:SetPoint("LEFT", row, "LEFT", 0, 0)
    l1:SetText(Tr(label1))
    if key1 then owner[key1 .. "Label"] = l1 end
    local m1 = Quick.Button(row, "-", 32, 32, nil, opts); m1:SetPoint("LEFT", l1, "RIGHT", Space("sm", 8), 0)
    local boxOpts = {}
    for key, value in pairs(opts or {}) do boxOpts[key] = value end
    boxOpts.boxHeight = 32
    local b1 = Quick.Box(row, opts and opts.boxWidth or 64, boxOpts); b1:SetPoint("LEFT", m1, "RIGHT", 4)
    local p1 = Quick.Button(row, "+", 32, 32, nil, opts); p1:SetPoint("LEFT", b1, "RIGHT", 4)
    Quick.WireStepper(m1, b1, p1, cb1)
    owner[key1] = b1

    local l2 = SetReadableSize(FS(row, "caption", c.white), 13)
    l2:SetPoint("LEFT", p1, "RIGHT", 20, 0)
    l2:SetText(Tr(label2))
    if key2 then owner[key2 .. "Label"] = l2 end
    local m2 = Quick.Button(row, "-", 32, 32, nil, opts); m2:SetPoint("LEFT", l2, "RIGHT", Space("sm", 8), 0)
    local b2 = Quick.Box(row, opts and opts.boxWidth or 64, boxOpts); b2:SetPoint("LEFT", m2, "RIGHT", 4)
    local p2 = Quick.Button(row, "+", 32, 32, nil, opts); p2:SetPoint("LEFT", b2, "RIGHT", 4)
    Quick.WireStepper(m2, b2, p2, cb2)
    owner[key2] = b2

    return row
end

function Quick.SingleValue(owner, parent, y, label, key, cb, opts)
    local c = Quick.RefreshPalette()
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize((opts and opts.rowWidth) or 488, 32)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", (opts and opts.x) or 20, y)

    local l = SetReadableSize(FS(row, "caption", c.white), 13)
    l:SetPoint("LEFT", row, "LEFT", 0, 0)
    l:SetText(Tr(label))
    local m = Quick.Button(row, "-", 32, 32, nil, opts); m:SetPoint("LEFT", l, "RIGHT", Space("sm", 8), 0)
    local boxOpts = {}
    for option, value in pairs(opts or {}) do boxOpts[option] = value end
    boxOpts.boxHeight = 32
    local b = Quick.Box(row, opts and opts.boxWidth or 64, boxOpts); b:SetPoint("LEFT", m, "RIGHT", 4)
    local p = Quick.Button(row, "+", 32, 32, nil, opts); p:SetPoint("LEFT", b, "RIGHT", 4)
    Quick.WireStepper(m, b, p, cb)
    owner[key] = b
    return row
end

--- Compact, self-contained geometry card used by the Edit Mode quick popups.
--- Rows are declarative: { label = "X", key = "xBox", onChanged = Apply }.
function Quick.ValueCard(owner, parent, x, y, width, title, rows, opts)
    opts = opts or {}
    local c = Quick.RefreshPalette()
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetSize(width, opts.height or 132)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    card:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    card:SetBackdropColor(c.cardBg[1], c.cardBg[2], c.cardBg[3], c.cardBg[4] or 0.64)
    card:SetBackdropBorderColor(c.cardEdge[1], c.cardEdge[2], c.cardEdge[3], c.cardEdge[4] or 0.72)
    if Menu2Style.Card then Menu2Style.Card(card) end

    local heading = SetReadableSize(FS(card, "body", c.white), 15)
    heading:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
    heading:SetText(Tr(title or ""))
    card._titleFS = heading

    for i = 1, #(rows or {}) do
        local spec = rows[i]
        local row = CreateFrame("Frame", nil, card)
        row:SetSize(width - 24, opts.controlHeight or 32)
        row:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -(38 + (i - 1) * 42))

        local label = SetReadableSize(FS(row, "caption", c.white), 13)
        label:SetPoint("LEFT", row, "LEFT", 0, 0)
        label:SetText(Tr(spec.label or ""))
        if spec.key then owner[spec.key .. "Label"] = label end

        local plus = Quick.Button(row, "+", opts.stepWidth or 32, opts.controlHeight or 32, nil, opts)
        plus:SetPoint("RIGHT", row, "RIGHT", -(spec.controlsRightInset or opts.controlsRightInset or 0), 0)
        local boxOpts = {}
        for key, value in pairs(opts) do boxOpts[key] = value end
        boxOpts.boxHeight = opts.controlHeight or 32
        local box = Quick.Box(row, spec.boxWidth or opts.boxWidth or 64, boxOpts)
        box:SetPoint("RIGHT", plus, "LEFT", -(opts.controlGap or 4), 0)
        local minus = Quick.Button(row, "-", opts.stepWidth or 32, opts.controlHeight or 32, nil, opts)
        minus:SetPoint("RIGHT", box, "LEFT", -(opts.controlGap or 4), 0)
        Quick.WireStepper(minus, box, plus, spec.onChanged)
        owner[spec.key] = box
    end

    return card
end

function Quick.AddLiveStatus(pf, text)
    if not (pf and pf._titleFS) then return nil end
    local c = Quick.RefreshPalette()
    local status = CreateFrame("Frame", nil, pf, "BackdropTemplate")
    status:SetSize(150, 22)
    status:SetPoint("LEFT", pf._titleFS, "RIGHT", 14, 0)
    status:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    status:SetBackdropColor(c.cardBg[1], c.cardBg[2], c.cardBg[3], 0.72)
    status:SetBackdropBorderColor(c.cardEdge[1], c.cardEdge[2], c.cardEdge[3], 0.58)
    if Menu2Style.Card then Menu2Style.Card(status) end
    local dot = status:CreateTexture(nil, "ARTWORK")
    dot:SetTexture(MEDIA .. "msuf_switch_knob.tga")
    dot:SetVertexColor(0.30, 1.00, 0.62, 1.00)
    dot:SetSize(8, 8)
    dot:SetPoint("LEFT", status, "LEFT", 9, 0)
    local label = SetReadableSize(FS(status, "caption", { 0.72, 0.90, 0.82, 0.95 }), 13)
    label:SetPoint("LEFT", dot, "RIGHT", 6, 0)
    label:SetText(Tr(text or "Changes apply live"))
    status._label, status._dot = label, dot
    pf._liveStatus = status
    return status
end

function Quick.ClearFocusedBoxes(...)
    for i = 1, select("#", ...) do
        local box = select(i, ...)
        if box and box.HasFocus and box:HasFocus() then box:ClearFocus() end
    end
end

function Quick.SetBoxText(box, value)
    if not (box and box.SetText) then return end
    if box.HasFocus and box:HasFocus() then return end
    box:SetText(tostring(value or 0))
end

function Quick.OpenPage(pageKey, owner)
    local M = _G.MSUF2 or (MSUF and MSUF.MSUF2)
    if pageKey and M and type(M.InvalidatePage) == "function" then M.InvalidatePage(pageKey) end
    if owner then owner:Hide() end
    if type(_G.MSUF_OpenStandaloneOptionsWindow) == "function" then
        _G.MSUF_OpenStandaloneOptionsWindow(pageKey)
    elseif type(_G.MSUF_OpenPage) == "function" then
        _G.MSUF_OpenPage(pageKey)
    elseif M and type(M.Open) == "function" then
        M.Open(pageKey)
    elseif M and type(M.SelectPage) == "function" then
        M.SelectPage(pageKey)
    end
end

function Quick.RefreshPopupFocus()
    local anyOpen = EM2.Popups and EM2.Popups.IsAnyOpen and EM2.Popups.IsAnyOpen()
    if not anyOpen then
        if EM2.State and EM2.State.SetPopupOpen then EM2.State.SetPopupOpen(false) end
        if EM2.Focus and EM2.Focus.ClearPopupFocus then EM2.Focus.ClearPopupFocus() end
    elseif EM2.Focus and EM2.Focus.RefreshPopupFocus then
        EM2.Focus.RefreshPopupFocus()
    end
end

function Quick.DeferPopupFocusRefresh()
    C_Timer.After(0, Quick.RefreshPopupFocus)
end

function Quick.CreateShell(name, opts)
    opts = opts or {}
    local c = Quick.RefreshPalette()
    local pf = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    pf:SetSize(opts.width or 440, opts.height or 244)
    pf:SetPoint("CENTER", UIParent, "CENTER", opts.x or 250, opts.y or 0)
    pf:SetFrameStrata(opts.strata or "FULLSCREEN_DIALOG")
    pf:SetFrameLevel(opts.frameLevel or 900)
    pf:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    pf:SetBackdropColor(c.panelBg[1], c.panelBg[2], c.panelBg[3], 0.96)
    pf:SetBackdropBorderColor(c.panelEdge[1], c.panelEdge[2], c.panelEdge[3], 0.95)
    if Menu2Style.Shell then Menu2Style.Shell(pf) end
    pf:EnableMouse(true)
    if pf.SetPropagateMouseClicks then pf:SetPropagateMouseClicks(false) end
    pf:SetScript("OnMouseDown", function() end)
    pf:SetScript("OnMouseUp", function() end)
    pf:SetMovable(true)
    pf:SetClampedToScreen(true)
    pf:RegisterForDrag("LeftButton")
    local blocker = opts.blocker or Quick.BlockConfigCombatLocked
    pf:SetScript("OnDragStart", function(s) if not blocker() then s:StartMoving() end end)
    pf:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)

    pf._titleFS = SetReadableSize(FS(pf, "section", c.white), 18)
    pf._titleFS:SetPoint("TOPLEFT", pf, "TOPLEFT", 20, -20)
    if opts.title then pf._titleFS:SetText(Tr(opts.title)) end
    if opts.liveStatus then Quick.AddLiveStatus(pf, opts.liveStatus == true and "Changes apply live" or opts.liveStatus) end

    local menu = _G.MSUF2 or (type(MSUF) == "table" and MSUF.MSUF2)
    local close = menu and menu.CreateWindowControlButton and menu.CreateWindowControlButton(pf, "close")
    if close then
        close:SetScript("OnClick", function() pf:Hide() end)
        KeepMenu2Skin(close)
    else
        close = (Menu2Style.CloseButton and Menu2Style.CloseButton(pf, function() pf:Hide() end))
            or Quick.Button(pf, "x", 24, 24, function() pf:Hide() end, opts)
    end
    FinishQuickButton(close, opts)
    close:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -12, -12)

    if opts.subtitle then
        pf._subtitleFS = SetReadableSize(FS(pf, "body", c.muted), 13)
        pf._subtitleFS:SetPoint("TOPLEFT", pf._titleFS, "BOTTOMLEFT", 0, -8)
        pf._subtitleFS:SetText(Tr(opts.subtitle))
    end

    pf:EnableKeyboard(true)
    pf:SetScript("OnKeyDown", function(s, key)
        local ctrl = IsControlKeyDown and IsControlKeyDown()
        if key == "ESCAPE" then
            if s.SetPropagateKeyboardInput then s:SetPropagateKeyboardInput(false) end
            s:Hide()
        elseif ctrl and key == "Z" then
            if s.SetPropagateKeyboardInput then s:SetPropagateKeyboardInput(false) end
            if EM2.Undo then EM2.Undo.DoUndo() end
            if s._refreshUndoRedo then s._refreshUndoRedo() end
        elseif ctrl and (key == "Y" or key == "R") then
            if s.SetPropagateKeyboardInput then s:SetPropagateKeyboardInput(false) end
            if EM2.Undo then EM2.Undo.DoRedo() end
            if s._refreshUndoRedo then s._refreshUndoRedo() end
        elseif s.SetPropagateKeyboardInput then
            s:SetPropagateKeyboardInput(true)
        end
    end)
    pf:HookScript("OnHide", function(s)
        if s.SetPropagateKeyboardInput then s:SetPropagateKeyboardInput(true) end
        if opts.hoverSource and EM2.Focus and EM2.Focus.ClearHover then EM2.Focus.ClearHover(opts.hoverSource) end
        if opts.onHide then opts.onHide(s) end
        Quick.DeferPopupFocusRefresh()
    end)
    pf:Hide()
    return pf
end

--- Small placement adapters for quick popups. They deliberately do not hide the
--- underlying Quick.Button/ValuePair behavior; they only remove repeated
--- SetPoint boilerplate from popup files.
function Quick.ButtonAt(parent, text, x, y, w, h, onClick, opts)
    local b = Quick.Button(parent, text, w, h or 32, onClick, opts)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    return b
end

function Quick.MenuButtonAt(parent, text, x, y, w, h, entries, onSelect, opts)
    -- Compact dropdown used by quick EditMode popups. The host supplies declarative
    -- entries and the copy/apply callback; this helper owns only popup chrome and
    -- hover-close behaviour so individual popups do not rebuild small menus by hand.
    opts = opts or {}
    local btn = Quick.ButtonAt(parent, text, x, y, w, h or 32, nil, opts.buttonOpts)
    local c = opts.palette or Quick.RefreshPalette()
    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetFrameStrata(opts.strata or "TOOLTIP")
    menu:SetFrameLevel(opts.frameLevel or 960)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
    menu:SetBackdropColor(c.panelBg[1], c.panelBg[2], c.panelBg[3], 0.98)
    menu:SetBackdropBorderColor(c.panelEdge[1], c.panelEdge[2], c.panelEdge[3], 0.95)
    if Menu2Style.Shell then Menu2Style.Shell(menu) end
    menu:Hide()

    local itemH = opts.itemHeight or 24
    local function PaintRow(item, hovered)
        local row = item and item._row or {}
        local bg = item and item._bg
        if bg then
            local highlighted = row.highlight and true or false
            local color = (hovered or highlighted) and c.btnHover or nil
            bg:SetColorTexture(color and color[1] or 0, color and color[2] or 0, color and color[3] or 0,
                hovered and 0.22 or (highlighted and 0.08 or 0))
        end
        local fs = item and item._label
        if fs then
            local color = row.highlight and c.title or c.white
            fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
            fs:SetText(Tr(row.label))
        end
    end

    local function AcquireRow(index)
        menu._items = menu._items or {}
        local item = menu._items[index]
        if item then return item end
        item = CreateFrame("Button", nil, menu)
        item:SetSize(w - 4, itemH)
        item:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -(3 + (index - 1) * itemH))
        item._bg = item:CreateTexture(nil, "BACKGROUND")
        item._bg:SetAllPoints()
        item._label = FS(item, "caption", c.white)
        item._label:SetPoint("LEFT", 8, 0)
        item:SetScript("OnEnter", function(self) PaintRow(self, true) end)
        item:SetScript("OnLeave", function(self) PaintRow(self, false) end)
        item:SetScript("OnClick", function(self)
            local row = self._row
            if not row then return end
            menu:Hide()
            if onSelect then onSelect(row, btn, menu) end
            if opts.flashSelection ~= false and Menu2Style.SetButtonText then
                Menu2Style.SetButtonText(btn, row.label)
                C_Timer.After(opts.flashSeconds or 1.2, function() Menu2Style.SetButtonText(btn, text) end)
            end
        end)
        menu._items[index] = item
        return item
    end

    local function BuildRows()
        -- Singleton popups can change source between openings, so resolve
        -- function-backed entries every time while reusing the row frames.
        local rows = type(entries) == "function" and entries() or entries or {}
        menu:SetSize(w, #rows * itemH + 8)
        for i = 1, #rows do
            local item = AcquireRow(i)
            item._row = rows[i]
            PaintRow(item, false)
            item:Show()
        end
        for i = #rows + 1, #(menu._items or {}) do
            local item = menu._items[i]
            item._row = nil
            item:Hide()
        end
    end
    btn:SetScript("OnClick", function()
        if menu:IsShown() then menu:Hide(); return end
        BuildRows()
        menu._closeTimer = nil
        menu:ClearAllPoints()
        menu:SetPoint(opts.point or "TOP", btn, opts.relativePoint or "BOTTOM", opts.offsetX or 0, opts.offsetY or -3)
        menu:Show()
    end)
    menu:SetScript("OnUpdate", function(self)
        if not self:IsShown() then return end
        if btn:IsMouseOver() or self:IsMouseOver() then
            self._closeTimer = nil
        else
            if not self._closeTimer then self._closeTimer = GetTime() + (opts.closeDelay or 0.35)
            elseif GetTime() >= self._closeTimer then self:Hide() end
        end
    end)
    if parent and parent.HookScript then parent:HookScript("OnHide", function() menu:Hide() end) end
    btn._menu = menu
    return btn, menu
end

function Quick.ToggleAt(parent, text, x, y, w, h, onClick, opts)
    local b = Quick.ToggleButton(parent, text, w, h or 32, onClick, opts)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    return b
end

function Quick.ValuePairAt(owner, parent, x, y, label1, key1, cb1, label2, key2, cb2, opts)
    opts = opts or {}
    opts.x = x or opts.x or 0
    return Quick.ValuePair(owner, parent, y, label1, key1, cb1, label2, key2, cb2, opts)
end

function Quick.SingleValueAt(owner, parent, x, y, label, key, cb, opts)
    opts = opts or {}
    opts.x = x or opts.x or 0
    return Quick.SingleValue(owner, parent, y, label, key, cb, opts)
end

--- Shared bottom footer: compact history, reset, and a clear Done action. Keeps every quick popup
--- on the same Menu2 visual system and behavior. The host popup supplies:
---   opts.onResetPosition  -> called when "Reset position" is clicked
---   opts.resetLabel       -> button label (default "Reset position")
---   opts.onDone           -> optional callback before the popup closes
---   opts.y                -> TOPLEFT y of the footer row (negative, from top)
--- Exposes pf._refreshUndoRedo() to re-evaluate Undo/Redo enabled state, and
--- calls it after the row is built and whenever the popup is shown.
function Quick.AddFooterControls(pf, opts)
    if not pf then return end
    opts = opts or {}
    local btnOpts = opts.buttonOpts or { hoverWash = true, hoverKey = "_msufEM2FooterHoverWash" }
    local y = opts.y or -206

    local divider = pf:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.18, 0.34, 0.56, 0.34)
    divider:SetHeight(1)
    divider:SetWidth(math.max(1, (pf:GetWidth() or 440) - 40))
    if opts.anchor == "BOTTOM" then
        divider:SetPoint("BOTTOM", pf, "BOTTOM", 0, (opts.bottomGap or 12) + 40)
    else
        divider:SetPoint("TOP", pf, "TOP", 0, y + 12)
    end
    pf._footerDivider = divider

    local function SetEnabled(btn, enabled)
        if not btn then return end
        btn:EnableMouse(enabled and true or false)
        btn:SetAlpha(enabled and 1 or 0.4)
    end

    local undoBtn = Quick.Button(pf, "", 38, 30, function()
        if EM2.Undo then EM2.Undo.DoUndo() end
        if pf._refreshUndoRedo then pf._refreshUndoRedo() end
    end, btnOpts)
    if opts.anchor == "BOTTOM" then
        --- Anchor to the bottom so popups with a dynamic height keep the footer
        --- pinned above the bottom edge. Leaves the bottom-right scale grip clear.
        undoBtn:SetPoint("BOTTOMLEFT", pf, "BOTTOMLEFT", 20, opts.bottomGap or 12)
    else
        undoBtn:SetPoint("TOPLEFT", pf, "TOPLEFT", 20, y)
    end

    local redoBtn = Quick.Button(pf, "", 38, 30, function()
        if EM2.Undo then EM2.Undo.DoRedo() end
        if pf._refreshUndoRedo then pf._refreshUndoRedo() end
    end, btnOpts)
    redoBtn:SetPoint("TOPLEFT", undoBtn, "TOPRIGHT", 8, 0)
    Quick.AttachIcon(undoBtn, MEDIA .. "msuf_history_undo_red.png", 17)
    Quick.AttachIcon(redoBtn, MEDIA .. "msuf_history_redo_green.png", 17)

    if opts.onResetPosition then
        local resetBtn = Quick.Button(pf, opts.resetLabel or "Reset position", 142, 30, function()
            opts.onResetPosition(pf)
            if pf._refreshUndoRedo then pf._refreshUndoRedo() end
        end, btnOpts)
        resetBtn:SetPoint("BOTTOM", pf, "BOTTOM", 0, opts.bottomGap or 12)
        if opts.anchor ~= "BOTTOM" then
            resetBtn:ClearAllPoints()
            resetBtn:SetPoint("TOP", pf, "TOP", 0, y)
        end
        pf._resetPosBtn = resetBtn
    end

    local doneBtn = Quick.Button(pf, opts.doneLabel or "Done", 118, 30, function()
        if opts.onDone then opts.onDone(pf) end
        if pf:IsShown() then pf:Hide() end
    end, { variant = "primary", hoverWash = true, hoverKey = "_msufEM2DoneHoverWash" })
    if opts.anchor == "BOTTOM" then
        doneBtn:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -20, opts.bottomGap or 12)
    else
        doneBtn:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -20, y)
    end

    pf._undoBtn, pf._redoBtn, pf._doneBtn = undoBtn, redoBtn, doneBtn

    local function AddTooltip(button, label)
        if not (button and button.HookScript) then return end
        button:HookScript("OnEnter", function(self)
            if not _G.GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(Tr(label), 0.86, 0.92, 1.00)
            GameTooltip:Show()
        end)
        button:HookScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
    end
    AddTooltip(undoBtn, "Undo")
    AddTooltip(redoBtn, "Redo")
    function pf._refreshUndoRedo()
        SetEnabled(undoBtn, EM2.Undo and EM2.Undo.CanUndo())
        SetEnabled(redoBtn, EM2.Undo and EM2.Undo.CanRedo())
    end
    pf._refreshUndoRedo()
    pf:HookScript("OnShow", function() if pf._refreshUndoRedo then pf._refreshUndoRedo() end end)
    return undoBtn, redoBtn
end

    Factory.Colors = C
    Factory.RefreshPalette = RefreshPalette
    Factory.FontString = FS
    Factory.WhiteTexture = W8
    Factory.Tr = Tr
    Factory.BlockConfigCombatLocked = BlockConfigCombatLocked
    Factory.RefreshUFPreview = RefreshUFPreview
    return Factory
end

do
    local ns = _G.MSUF_NS or _G.MSUF
    local export = type(ns) == "table" and ns.ExportPublic or nil
    if type(export) == "function" then
        export("MSUF_InstallEditPopupUI", InstallEditPopupUI)
    else
        _G["MSUF_InstallEditPopupUI"] = InstallEditPopupUI
    end
end
