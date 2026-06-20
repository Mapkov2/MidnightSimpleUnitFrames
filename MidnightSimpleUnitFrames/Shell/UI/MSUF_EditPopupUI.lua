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
local BOX_H    = 22
local STEP_W   = 20

local Tr = U.Tr

local function FS(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size or 12, "")
    fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 0.9)
    local c = color or C.white
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    return fs
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

function Menu2Style.Button(parent, text, width, height, onClick)
    if SharedUI and SharedUI.Button then
        return KeepMenu2Skin(SharedUI.Button(parent, text, width or 66, height or 24, {
            onClick = onClick,
            align = "CENTER",
            skipHistory = true,
        }))
    end
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 66, height or 24)
    b:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1 })
    b:SetBackdropColor(C.btnBg[1], C.btnBg[2], C.btnBg[3], 0.88)
    b:SetBackdropBorderColor(C.btnEdge[1], C.btnEdge[2], C.btnEdge[3], 0.82)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(C.btnHover[1], C.btnHover[2], C.btnHover[3], 0.18)
    local fs = FS(b, 11, C.white)
    fs:SetPoint("CENTER")
    fs:SetText(Tr(text or ""))
    b._label = fs
    if onClick then b:SetScript("OnClick", onClick) end
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
function Quick.FS(parent, size, color) return FS(parent, size, color) end
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
        b = Menu2Style.Button(parent, Tr(text), w or 66, h or 30, onClick)
        if Menu2Style.SetButtonText then Menu2Style.SetButtonText(b, text) end
    else
        b = CreateFrame("Button", nil, parent, "BackdropTemplate")
        b:SetSize(w or 66, h or 30)
        b:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
        b:SetBackdropColor(c.btnBg[1], c.btnBg[2], c.btnBg[3], c.btnBg[4])
        b:SetBackdropBorderColor(c.btnEdge[1], c.btnEdge[2], c.btnEdge[3], c.btnEdge[4])
        b._label = FS(b, 11, c.white)
        b._label:SetPoint("CENTER")
    end
    if not Menu2Style.SetButtonText and b._label then b._label:SetText(Tr(text)) end
    if onClick then b:SetScript("OnClick", onClick) end
    return FinishQuickButton(b, opts)
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
    b:SetSize(width or 52, 22)
    b:SetAutoFocus(false)
    b:SetNumeric(false)
    b:SetJustifyH("CENTER")
    b:SetMaxLetters(7)
    b:SetFont(FONT, 12, "")
    b:SetTextColor(c.white[1], c.white[2], c.white[3], c.white[4] or 1)
    if b.SetBackdrop then
        b:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
        b:SetBackdropColor(c.inputBg[1], c.inputBg[2], c.inputBg[3], c.inputBg[4] or 0.90)
        b:SetBackdropBorderColor(c.inputEdge[1], c.inputEdge[2], c.inputEdge[3], c.inputEdge[4] or 0.70)
    end
    if Menu2Style.EditBox then Menu2Style.EditBox(b) end
    if opts and opts.peelSkin then Quick.KeepEditSkin(b) end
    return b
end

function Quick.WireStepper(minus, box, plus, cb)
    local function commit(delta)
        box:SetText(tostring(Quick.San(box:GetText(), 0) + ((delta or 0) * GetStep())))
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
    row:SetSize(400, 24)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", (opts and opts.x) or 20, y)

    local l1 = FS(row, 11, c.white)
    l1:SetPoint("LEFT", row, "LEFT", 0, 0)
    l1:SetText(Tr(label1))
    local m1 = Quick.Step(row, "-", opts); m1:SetPoint("LEFT", l1, "RIGHT", 6, 0)
    local b1 = Quick.Box(row, opts and opts.boxWidth or 52, opts); b1:SetPoint("LEFT", m1, "RIGHT", 1)
    local p1 = Quick.Step(row, "+", opts); p1:SetPoint("LEFT", b1, "RIGHT", 1)
    Quick.WireStepper(m1, b1, p1, cb1)
    owner[key1] = b1

    local l2 = FS(row, 11, c.white)
    l2:SetPoint("LEFT", p1, "RIGHT", 18, 0)
    l2:SetText(Tr(label2))
    local m2 = Quick.Step(row, "-", opts); m2:SetPoint("LEFT", l2, "RIGHT", 6, 0)
    local b2 = Quick.Box(row, opts and opts.boxWidth or 52, opts); b2:SetPoint("LEFT", m2, "RIGHT", 1)
    local p2 = Quick.Step(row, "+", opts); p2:SetPoint("LEFT", b2, "RIGHT", 1)
    Quick.WireStepper(m2, b2, p2, cb2)
    owner[key2] = b2

    return row
end

function Quick.SingleValue(owner, parent, y, label, key, cb, opts)
    local c = Quick.RefreshPalette()
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize((opts and opts.rowWidth) or 360, 24)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", (opts and opts.x) or 20, y)

    local l = FS(row, 11, c.white)
    l:SetPoint("LEFT", row, "LEFT", 0, 0)
    l:SetText(Tr(label))
    local m = Quick.Step(row, "-", opts); m:SetPoint("LEFT", l, "RIGHT", 6, 0)
    local b = Quick.Box(row, opts and opts.boxWidth or 52, opts); b:SetPoint("LEFT", m, "RIGHT", 1)
    local p = Quick.Step(row, "+", opts); p:SetPoint("LEFT", b, "RIGHT", 1)
    Quick.WireStepper(m, b, p, cb)
    owner[key] = b
    return row
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
    pf:SetFrameStrata("DIALOG")
    pf:SetFrameLevel(opts.frameLevel or 220)
    pf:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    pf:SetBackdropColor(c.panelBg[1], c.panelBg[2], c.panelBg[3], 0.96)
    pf:SetBackdropBorderColor(c.panelEdge[1], c.panelEdge[2], c.panelEdge[3], 0.95)
    if Menu2Style.Shell then Menu2Style.Shell(pf) end
    pf:EnableMouse(true)
    pf:SetMovable(true)
    pf:SetClampedToScreen(true)
    pf:RegisterForDrag("LeftButton")
    local blocker = opts.blocker or Quick.BlockConfigCombatLocked
    pf:SetScript("OnDragStart", function(s) if not blocker() then s:StartMoving() end end)
    pf:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)

    pf._titleFS = FS(pf, 15, c.white)
    pf._titleFS:SetPoint("TOPLEFT", pf, "TOPLEFT", 20, -18)
    if opts.title then pf._titleFS:SetText(Tr(opts.title)) end

    local close = (Menu2Style.CloseButton and Menu2Style.CloseButton(pf, function() pf:Hide() end))
        or Quick.Button(pf, "x", 24, 24, function() pf:Hide() end, opts)
    FinishQuickButton(close, opts)
    close:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -10, -10)

    if opts.subtitle then
        pf._subtitleFS = FS(pf, 12, c.muted)
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
    local b = Quick.Button(parent, text, w, h or 30, onClick, opts)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    return b
end

function Quick.MenuButtonAt(parent, text, x, y, w, h, entries, onSelect, opts)
    -- Compact dropdown used by quick EditMode popups. The host supplies declarative
    -- entries and the copy/apply callback; this helper owns only popup chrome and
    -- hover-close behaviour so individual popups do not rebuild small menus by hand.
    opts = opts or {}
    local btn = Quick.ButtonAt(parent, text, x, y, w, h or 30, nil, opts.buttonOpts)
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

    local itemH = opts.itemHeight or 22
    local function BuildRows()
        if menu._built then return end
        menu._built = true
        local rows = type(entries) == "function" and entries() or entries or {}
        menu:SetSize(w, #rows * itemH + 6)
        for i = 1, #rows do
            local row = rows[i]
            local item = CreateFrame("Button", nil, menu)
            item:SetSize(w - 4, itemH)
            item:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -(3 + (i - 1) * itemH))
            local bg = item:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(row.highlight and c.btnHover[1] or 0, row.highlight and c.btnHover[2] or 0, row.highlight and c.btnHover[3] or 0, row.highlight and 0.08 or 0)
            local fs = FS(item, 10, row.highlight and c.title or c.white)
            fs:SetPoint("LEFT", 8, 0)
            fs:SetText(Tr(row.label))
            item:SetScript("OnEnter", function() bg:SetColorTexture(c.btnHover[1], c.btnHover[2], c.btnHover[3], 0.22) end)
            item:SetScript("OnLeave", function() bg:SetColorTexture(row.highlight and c.btnHover[1] or 0, row.highlight and c.btnHover[2] or 0, row.highlight and c.btnHover[3] or 0, row.highlight and 0.08 or 0) end)
            item:SetScript("OnClick", function()
                menu:Hide()
                if onSelect then onSelect(row, btn, menu) end
                if opts.flashSelection ~= false and Menu2Style.SetButtonText then
                    Menu2Style.SetButtonText(btn, row.label)
                    C_Timer.After(opts.flashSeconds or 1.2, function() Menu2Style.SetButtonText(btn, text) end)
                end
            end)
        end
    end
    btn:SetScript("OnClick", function()
        if menu:IsShown() then menu:Hide(); return end
        BuildRows()
        menu:ClearAllPoints()
        menu:SetPoint(opts.point or "TOP", btn, opts.relativePoint or "BOTTOM", opts.offsetX or 0, opts.offsetY or -3)
        menu:Show()
    end)
    menu:SetOnUpdateMode("RunWhenVisible")
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
    local b = Quick.ToggleButton(parent, text, w, h or 30, onClick, opts)
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

local function ResolveQuickSpecValue(value)
    return type(value) == "function" and value() or value
end

function Quick.BuildBoundsPopup(name, shellOpts, spec)
    -- Castbar and aura shortcut popups share one fixed bounds-editor layout. The caller
    -- still owns DB writes, focus routing, and refresh callbacks; this helper only centralizes
    -- the chrome so future popup additions do not copy/paste shell rows and footer wiring.
    spec = spec or {}
    local pf = Quick.CreateShell(name, shellOpts)
    local defaultOpts = ResolveQuickSpecValue(spec.buttonOpts)
    for i = 1, #(spec.rows or {}) do
        local row = spec.rows[i]
        Quick.ValuePairAt(pf, pf, row.x or 0, row.y, row.label1, row.key1, row.cb1, row.label2, row.key2, row.cb2, ResolveQuickSpecValue(row.opts) or defaultOpts)
    end
    local toggle = spec.toggle
    if toggle then
        pf[toggle.key] = Quick.ToggleAt(pf, toggle.text, toggle.x, toggle.y, toggle.w, toggle.h, toggle.onClick, ResolveQuickSpecValue(toggle.opts) or defaultOpts)
    end
    for i = 1, #(spec.buttons or {}) do
        local button = spec.buttons[i]
        local control = Quick.ButtonAt(pf, button.text, button.x, button.y, button.w, button.h, button.onClick, ResolveQuickSpecValue(button.opts) or defaultOpts)
        if spec.wireButton then control = spec.wireButton(control, button, pf) or control end
        if button.key then pf[button.key] = control end
    end
    if Quick.AddFooterControls and spec.footer then Quick.AddFooterControls(pf, spec.footer) end
    if spec.scaleGrip ~= false and EM2.AttachPopupScaleGrip then EM2.AttachPopupScaleGrip(pf) end
    return pf
end

--- Shared bottom footer: Undo / Redo + Reset position. Keeps every quick popup
--- on the same Menu2 visual system and behavior. The host popup supplies:
---   opts.onResetPosition  -> called when "Reset position" is clicked
---   opts.resetLabel       -> button label (default "Reset position")
---   opts.y                -> TOPLEFT y of the footer row (negative, from top)
--- Exposes pf._refreshUndoRedo() to re-evaluate Undo/Redo enabled state, and
--- calls it after the row is built and whenever the popup is shown.
function Quick.AddFooterControls(pf, opts)
    if not pf then return end
    opts = opts or {}
    local btnOpts = opts.buttonOpts or { hoverWash = true, hoverKey = "_msufEM2FooterHoverWash" }
    local y = opts.y or -206

    local function SetEnabled(btn, enabled)
        if not btn then return end
        btn:EnableMouse(enabled and true or false)
        btn:SetAlpha(enabled and 1 or 0.4)
    end

    local undoBtn = Quick.Button(pf, "Undo", 90, 26, function()
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

    local redoBtn = Quick.Button(pf, "Redo", 90, 26, function()
        if EM2.Undo then EM2.Undo.DoRedo() end
        if pf._refreshUndoRedo then pf._refreshUndoRedo() end
    end, btnOpts)
    redoBtn:SetPoint("TOPLEFT", undoBtn, "TOPRIGHT", 8, 0)

    if opts.onResetPosition then
        local resetBtn = Quick.Button(pf, opts.resetLabel or "Reset position", 188, 26, function()
            opts.onResetPosition(pf)
            if pf._refreshUndoRedo then pf._refreshUndoRedo() end
        end, btnOpts)
        resetBtn:SetPoint("TOPLEFT", redoBtn, "TOPRIGHT", 8, 0)
        pf._resetPosBtn = resetBtn
    end

    pf._undoBtn, pf._redoBtn = undoBtn, redoBtn
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
