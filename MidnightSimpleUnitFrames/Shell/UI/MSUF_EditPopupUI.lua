--- Shell/UI/MSUF_EditPopupUI.lua - shared Edit Mode popup UI helpers.
--- Defines popup styling, quick popup controls, and the scrollable popup factory.
local function InstallEditPopupUI(addonName, MSUF)
    local EM2 = _G.MSUF_EM2
    if not EM2 then return nil end
    if type(EM2.PopupFactory) == "table" and type(EM2.QuickPopup) == "table" then return EM2.PopupFactory end
local Factory = {}
EM2.PopupFactory = Factory

local floor = math.floor
local max, min = math.max, math.min
local W8 = "Interface/Buttons/WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF"
local CHEVRON = "Interface\\ChatFrame\\ChatFrameExpandArrow"
local ADDON = (type(addonName) == "string" and addonName ~= "" and addonName) or "MidnightSimpleUnitFrames"
local ADDON_PATH = "Interface\\AddOns\\" .. ADDON .. "\\"
local CHECK_BOX_FILL_TEX = ADDON_PATH .. "Media\\msuf_checkbox_fill.tga"
local CHECK_BOX_EDGE_TEX = ADDON_PATH .. "Media\\msuf_checkbox_edge.tga"
local CHECK_TICK_TEX = ADDON_PATH .. "Media\\msuf_check_tick_medium.tga"
local U = EM2.Util or {}
local ApplyAllSettingsSafe = U.ApplyAllSettingsSafe

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

local PW       = 380
local PAD      = 14
local CARD_PAD = 8
local BOX_W    = 52
local BOX_H    = 22
local STEP_W   = 20
local ROW_H    = 24
local ROW_GAP  = 4
local CARD_GAP = 6
local TITLE_H  = 38
local FOOTER_H = 46
local HDR_H    = 24
local BODY_TOP = 28

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
_G.MSUF_EM2_Menu2Style = Menu2Style

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
    if C_Timer and C_Timer.After then C_Timer.After(0, Quick.RefreshPopupFocus) else Quick.RefreshPopupFocus() end
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
        if key == "ESCAPE" then
            if s.SetPropagateKeyboardInput then s:SetPropagateKeyboardInput(false) end
            s:Hide()
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

--- Panel
function Factory.Panel(name, width, visibleH, title)
    RefreshPalette()
    width = width or PW; visibleH = visibleH or 540

    local pf = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    pf:SetSize(width, visibleH)
    pf:SetPoint("CENTER", UIParent, "CENTER", 250, 0)
    pf:SetFrameStrata("DIALOG"); pf:SetFrameLevel(200)
    pf:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=1,right=1,top=1,bottom=1} })
    pf:SetBackdropColor(unpack(C.panelBg)); pf:SetBackdropBorderColor(unpack(C.panelEdge))
    Menu2Style.Shell(pf)
    pf:EnableMouse(true); pf:SetMovable(true); pf:SetClampedToScreen(true)
    pf:RegisterForDrag("LeftButton")
    pf:SetScript("OnDragStart", function(s)
        if BlockConfigCombatLocked() then return end
        s:StartMoving()
    end)
    pf:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)

    local titleFS = FS(pf, 15, C.title)
    titleFS:SetPoint("LEFT", pf, "TOPLEFT", PAD, -TITLE_H / 2)
    titleFS:SetText(Tr(title or "Edit")); pf._titleFS = titleFS

    local closeBtn = Menu2Style.CloseButton(pf, function() pf:Hide() end)
    closeBtn:SetPoint("RIGHT", pf, "TOPRIGHT", -12, -TITLE_H / 2)

    local function MakeDiv(yRef, yOff)
        local d = pf:CreateTexture(nil, "ARTWORK"); d:SetHeight(1)
        d:SetPoint("LEFT", pf, "LEFT", 0, 0); d:SetPoint("RIGHT", pf, "RIGHT", 0, 0)
        d:SetPoint("TOP", yRef, "TOP", 0, yOff); d:SetColorTexture(unpack(C.divider))
    end
    MakeDiv(pf, -TITLE_H); MakeDiv(pf, -(visibleH - FOOTER_H))

    local sf = CreateFrame("ScrollFrame", nil, pf)
    sf:SetPoint("TOPLEFT", pf, "TOPLEFT", 0, -(TITLE_H + 1))
    sf:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", 0, FOOTER_H + 1)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local mx = max(0, (self:GetScrollChild():GetHeight() or 0) - self:GetHeight())
        self:SetVerticalScroll(max(0, min(mx, cur - delta * 32)))
        if pf.UpdateScrollIndicator then pf:UpdateScrollIndicator() end
    end)
    pf._scrollFrame = sf

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(width); sc:SetHeight(1); sf:SetScrollChild(sc)
    pf._scrollChild = sc

    local scrollIndicator = CreateFrame("Frame", nil, pf, "BackdropTemplate")
    scrollIndicator:SetSize(26, 50)
    scrollIndicator:SetPoint("RIGHT", sf, "RIGHT", -15, 0)
    scrollIndicator:SetFrameLevel(pf:GetFrameLevel() + 4)
    scrollIndicator:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=1,right=1,top=1,bottom=1} })
    scrollIndicator:SetBackdropColor(0.01, 0.015, 0.04, 0.88)
    scrollIndicator:SetBackdropBorderColor(C.panelEdge[1], C.panelEdge[2], C.panelEdge[3], 0.95)
    scrollIndicator:Hide()
    pf._scrollIndicator = scrollIndicator

    local function MakeScrollButton(parent, rotation, y)
        local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
        b:SetSize(22, 22)
        b:SetPoint("TOP", parent, "TOP", 0, y)
        b:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=1,right=1,top=1,bottom=1} })
        b:SetBackdropColor(0.055, 0.075, 0.14, 0.98)
        b:SetBackdropBorderColor(C.title[1], C.title[2], C.title[3], 0.85)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(C.orange[1], C.orange[2], C.orange[3], 0.18)
        local icon = b:CreateTexture(nil, "OVERLAY")
        icon:SetSize(13, 13)
        icon:SetPoint("CENTER", 0, 0)
        icon:SetTexture(CHEVRON)
        icon:SetRotation(rotation)
        icon:SetVertexColor(C.orange[1], C.orange[2], C.orange[3], 1)
        b._icon = icon
        return b
    end

    local upBtn = MakeScrollButton(scrollIndicator, math.pi * 0.5, -2)
    local downBtn = MakeScrollButton(scrollIndicator, -math.pi * 0.5, -26)
    scrollIndicator.upBtn = upBtn
    scrollIndicator.downBtn = downBtn

    local function SetScrollButtonEnabled(btn, enabled)
        if not btn then return end
        btn:SetAlpha(enabled and 1 or 0.65)
        if enabled then
            btn:SetBackdropColor(0.055, 0.075, 0.14, 0.98)
            btn:SetBackdropBorderColor(C.title[1], C.title[2], C.title[3], 0.85)
        else
            btn:SetBackdropColor(C.btnBg[1], C.btnBg[2], C.btnBg[3], 0.74)
            btn:SetBackdropBorderColor(C.btnEdge[1], C.btnEdge[2], C.btnEdge[3], 0.55)
        end
        if btn._icon then
            if enabled then btn._icon:SetVertexColor(C.orange[1], C.orange[2], C.orange[3], 1)
            else btn._icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3], 0.75) end
        end
    end

    function pf:UpdateScrollIndicator()
        local mx = max(0, (sf:GetScrollChild():GetHeight() or 0) - (sf:GetHeight() or 0))
        if mx <= 1 then
            scrollIndicator:Hide()
            return
        end
        local cur = max(0, min(mx, sf:GetVerticalScroll() or 0))
        scrollIndicator:Show()
        SetScrollButtonEnabled(upBtn, cur > 1)
        SetScrollButtonEnabled(downBtn, cur < mx - 1)
    end

    local function StepScroll(direction)
        local mx = max(0, (sf:GetScrollChild():GetHeight() or 0) - (sf:GetHeight() or 0))
        local cur = sf:GetVerticalScroll() or 0
        sf:SetVerticalScroll(max(0, min(mx, cur + direction * 64)))
        pf:UpdateScrollIndicator()
    end
    upBtn:SetScript("OnClick", function() StepScroll(-1) end)
    downBtn:SetScript("OnClick", function() StepScroll(1) end)
    sf:SetScript("OnVerticalScroll", function()
        if pf.UpdateScrollIndicator then pf:UpdateScrollIndicator() end
    end)
    pf:SetScript("OnShow", function(self)
        if self.UpdateScrollIndicator then self:UpdateScrollIndicator() end
        if Menu2Style.FadeIn then Menu2Style.FadeIn(self, 0.12, 0.86, 1) end
    end)
    pf:HookScript("OnHide", Quick.DeferPopupFocusRefresh)

    local anchor = sc:CreateFontString(nil, "OVERLAY")
    anchor:SetFont(FONT, 1, ""); anchor:SetText("")
    anchor:SetPoint("TOPLEFT", sc, "TOPLEFT", PAD, -6)
    pf._contentTop = anchor

    function pf:UpdateScrollHeight(h)
        sc:SetHeight(max(1, h + 20))
        if self.UpdateScrollIndicator then self:UpdateScrollIndicator() end
        if C_Timer then
            C_Timer.After(0, function()
                if pf.UpdateScrollIndicator then pf:UpdateScrollIndicator() end
            end)
        end
    end
    pf.__msufEditPopupRoot = true; pf:Hide()
    return pf
end

--- Card: collapsible section (matches MakeCollapsibleSection in Options)
function Factory.Card(pf, anchorTo, text, yOff, defaultOpen)
    local sc = pf._scrollChild or pf
    yOff = yOff or -CARD_GAP
    if defaultOpen == nil then defaultOpen = true end

    local card = CreateFrame("Frame", nil, sc, "BackdropTemplate")
    card:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yOff)
    card:SetPoint("RIGHT", sc, "RIGHT", -PAD, 0)
    card:SetHeight(50)
    card:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=1,right=1,top=1,bottom=1} })
    card:SetBackdropColor(unpack(C.cardBg)); card:SetBackdropBorderColor(unpack(C.cardEdge))

    --- Header (always visible)
    local hdr = CreateFrame("Button", nil, card)
    hdr:SetHeight(HDR_H)
    hdr:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    hdr:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
    local hl = hdr:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.03)

    local chevron = hdr:CreateTexture(nil, "OVERLAY")
    chevron:SetSize(12, 12); chevron:SetPoint("LEFT", hdr, "LEFT", 10, 0)
    chevron:SetTexture(CHEVRON)

    local title = FS(hdr, 12, C.title)
    title:SetPoint("LEFT", chevron, "RIGHT", 6, 0)
    title:SetText(Tr(text or ""))

    local hint = FS(hdr, 10, C.muted)
    hint:SetPoint("RIGHT", hdr, "RIGHT", -10, 0)

    --- Divider
    local div = card:CreateTexture(nil, "ARTWORK"); div:SetHeight(1)
    div:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 6, -1)
    div:SetPoint("RIGHT", card, "RIGHT", -6, 0)
    div:SetColorTexture(unpack(C.divider))

    --- Body (collapsible)
    local body = CreateFrame("Frame", nil, card)
    body:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -BODY_TOP)
    body:SetPoint("RIGHT", card, "RIGHT", -CARD_PAD, 0)
    body:SetHeight(1)
    card._body = body

    --- Collapse state
    card._open = defaultOpen
    card._rows = {}; card._rowCount = 0

    local function ApplyState()
        local open = card._open
        body:SetShown(open)
        div:SetShown(open)
        if open then
            chevron:SetRotation(math.pi * 0.5)
            chevron:SetVertexColor(C.orange[1], C.orange[2], C.orange[3])
            hint:SetText("")
        else
            chevron:SetRotation(0)
            chevron:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
            hint:SetText(Tr("click to expand"))
        end
        card:RecalcHeight()
        --- Recalc parent scroll
        if pf._recalcScroll then pf._recalcScroll() end
    end
    card._applyState = ApplyState

    hdr:SetScript("OnClick", function()
        card._open = not card._open
        ApplyState()
    end)

    function card:RecalcHeight()
        if not card._open then
            card:SetHeight(HDR_H + 4); return
        end
        local h = BODY_TOP + 4
        for i = 1, self._rowCount do
            local r = self._rows[i]
            if r and r.IsShown and r:IsShown() then
                h = h + (r:GetHeight() or ROW_H) + ROW_GAP
            end
        end
        card:SetHeight(max(HDR_H + 8, h))
        body:SetHeight(max(1, h - BODY_TOP))
    end

    ApplyState()
    return card, body
end

--- Stepper + EditBox helpers
local function MakeStep(parent, text)
    return Menu2Style.Step(parent, text, STEP_W, BOX_H)
end

local function MakeBox(parent, w)
    local b = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    b:SetSize(w or BOX_W, BOX_H)
    b:SetFont(FONT, 12, ""); b:SetTextColor(unpack(C.white))
    b:SetJustifyH("CENTER"); b:SetAutoFocus(false); b:SetMaxLetters(7)
    b:SetBackdrop({bgFile=W8, edgeFile=W8, edgeSize=1})
    b:SetBackdropColor(unpack(C.inputBg)); b:SetBackdropBorderColor(unpack(C.inputEdge))
    b:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    Menu2Style.EditBox(b)
    return b
end

local function WireStepper(m, box, p, cb)
    m:SetScript("OnClick", function() local v=tonumber(box:GetText()) or 0; box:SetText(tostring(floor(v-GetStep()+0.5))); if cb then cb() end end)
    p:SetScript("OnClick", function() local v=tonumber(box:GetText()) or 0; box:SetText(tostring(floor(v+GetStep()+0.5))); if cb then cb() end end)
    box:SetScript("OnEnterPressed", function(s) s:ClearFocus(); if cb then cb() end end)
end

local function NewFactoryRow(body, opts, height, defaultYOff)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, body)
    row:SetHeight(height or ROW_H)
    if opts.anchorTo then
        row:SetPoint("TOPLEFT", opts.anchorTo, "BOTTOMLEFT", 0, opts.yOff or defaultYOff or -ROW_GAP)
    else
        row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    end
    row:SetPoint("RIGHT", body, "RIGHT", 0, 0)
    return row
end

--- PairRow: "X: [-][val][+] Y: [-][val][+]"
function Factory.PairRow(pf, body, card, opts)
    local l1t, l2t = opts.label1 or "X:", opts.label2 or "Y:"
    local k1, k2 = opts.key1, opts.key2
    local cb = opts.onChanged

    local row = NewFactoryRow(body, opts, ROW_H)

    local l1 = FS(row, 11, C.muted); l1:SetPoint("LEFT", 0, 0); l1:SetText(Tr(l1t))
    local m1 = MakeStep(row, "-"); m1:SetPoint("LEFT", l1, "RIGHT", 4, 0)
    local b1 = MakeBox(row); b1:SetPoint("LEFT", m1, "RIGHT", 1)
    local p1 = MakeStep(row, "+"); p1:SetPoint("LEFT", b1, "RIGHT", 1)
    WireStepper(m1, b1, p1, cb)

    local l2 = FS(row, 11, C.muted); l2:SetPoint("LEFT", p1, "RIGHT", 10, 0); l2:SetText(Tr(l2t))
    local m2 = MakeStep(row, "-"); m2:SetPoint("LEFT", l2, "RIGHT", 4, 0)
    local b2 = MakeBox(row); b2:SetPoint("LEFT", m2, "RIGHT", 1)
    local p2 = MakeStep(row, "+"); p2:SetPoint("LEFT", b2, "RIGHT", 1)
    WireStepper(m2, b2, p2, cb)

    if k1 then pf[k1]=b1; pf[k1.."Minus"]=m1; pf[k1.."Plus"]=p1; pf[k1.."Label"]=l1 end
    if k2 then pf[k2]=b2; pf[k2.."Minus"]=m2; pf[k2.."Plus"]=p2; pf[k2.."Label"]=l2 end

    card._rowCount = card._rowCount + 1; card._rows[card._rowCount] = row
    return row
end

--- SingleRow: "Label: [-][val][+]"
function Factory.SingleRow(pf, body, card, opts)
    local boxKey = opts.boxKey; local cb = opts.onChanged

    local row = NewFactoryRow(body, opts, ROW_H)

    local label = FS(row, 11, C.muted)
    label:SetPoint("LEFT", 0, 0); label:SetText(Tr(opts.label or "Value:"))

    local m = MakeStep(row, "-"); m:SetPoint("LEFT", label, "RIGHT", 6, 0)
    local box = MakeBox(row); box:SetPoint("LEFT", m, "RIGHT", 1)
    local p = MakeStep(row, "+"); p:SetPoint("LEFT", box, "RIGHT", 1)
    WireStepper(m, box, p, cb)

    if boxKey then pf[boxKey]=box; pf[boxKey.."Minus"]=m; pf[boxKey.."Plus"]=p; pf[boxKey.."Label"]=label end
    card._rowCount = card._rowCount + 1; card._rows[card._rowCount] = row
    return row
end

--- SizeAnchorRow: "Size: [-][val][+] [ Anchor â–¸ ]"
function Factory.SizeAnchorRow(pf, body, card, opts)
    local sizeKey = opts.sizeKey; local anchorKey = opts.anchorKey
    local stateKey = opts.stateKey; local cb = opts.onChanged
    local options = opts.options or { {"LEFT","Left"}, {"RIGHT","Right"}, {"CENTER","Center"} }
    local row = NewFactoryRow(body, opts, ROW_H)

    local sl = FS(row, 11, C.muted); sl:SetPoint("LEFT", 0, 0); sl:SetText(Tr("Size:"))
    local sm = MakeStep(row, "-"); sm:SetPoint("LEFT", sl, "RIGHT", 4, 0)
    local sb = MakeBox(row, 44); sb:SetPoint("LEFT", sm, "RIGHT", 1)
    local sp = MakeStep(row, "+"); sp:SetPoint("LEFT", sb, "RIGHT", 1)
    WireStepper(sm, sb, sp, cb)

    local drop = CreateFrame("Frame", nil, row, "BackdropTemplate")
    drop:SetSize(68, BOX_H); drop:SetPoint("LEFT", sp, "RIGHT", 12, 0)
    drop:SetBackdrop({bgFile=W8, edgeFile=W8, edgeSize=1})
    drop:SetBackdropColor(unpack(C.inputBg)); drop:SetBackdropBorderColor(unpack(C.inputEdge))
    drop:EnableMouse(true)
    local dFS = FS(drop, 11, C.white); dFS:SetPoint("CENTER")
    drop.value = options[1] and options[1][1]
    function drop:SetValue(k) drop.value=k; if stateKey then pf[stateKey]=k end
        for _,o in ipairs(options) do if o[1]==k then dFS:SetText(Tr(o[2])); return end end; dFS:SetText(tostring(k)) end
    function drop:GetValue() return drop.value end
    drop:SetScript("OnMouseDown", function()
        local idx=1; for i,o in ipairs(options) do if o[1]==drop.value then idx=i; break end end
        idx=(idx%#options)+1; drop:SetValue(options[idx][1]); if cb then cb() end
    end)

    if sizeKey then pf[sizeKey]=sb; pf[sizeKey.."Minus"]=sm; pf[sizeKey.."Plus"]=sp end
    if anchorKey then pf[anchorKey]=drop end
    card._rowCount = card._rowCount + 1; card._rows[card._rowCount] = row
    return row
end

--- CheckRow
function Factory.CheckRow(pf, body, card, opts)
    local cbKey = opts.cbKey; local cb = opts.onChanged

    local row = NewFactoryRow(body, opts, 24)

    local chk = CreateFrame("CheckButton", nil, row)
    chk:SetSize(22, 22); chk:SetPoint("LEFT", 0, 0)

    local edge = chk:CreateTexture(nil, "BACKGROUND", nil, -3)
    edge:SetTexture(CHECK_BOX_EDGE_TEX); edge:SetTexCoord(0, 1, 0, 1)
    edge:SetSize(22, 22); edge:SetPoint("CENTER")
    if edge.SetSnapToPixelGrid then edge:SetSnapToPixelGrid(false) end
    if edge.SetTexelSnappingBias then edge:SetTexelSnappingBias(0) end
    chk._msufCheckEdge = edge

    local bg = chk:CreateTexture(nil, "BACKGROUND", nil, -2)
    bg:SetTexture(CHECK_BOX_FILL_TEX); bg:SetTexCoord(0, 1, 0, 1)
    bg:SetSize(20, 20); bg:SetPoint("CENTER")
    if bg.SetSnapToPixelGrid then bg:SetSnapToPixelGrid(false) end
    if bg.SetTexelSnappingBias then bg:SetTexelSnappingBias(0) end
    chk._msufCheckFill = bg

    local ck = chk:CreateTexture(nil, "OVERLAY")
    ck:SetTexture(CHECK_TICK_TEX); ck:SetTexCoord(0, 1, 0, 1)
    ck:SetSize(15, 15); ck:SetPoint("CENTER")
    ck:SetVertexColor(1, 1, 1, 0.96)
    chk:SetCheckedTexture(ck)

    function chk:RefreshCheckVisual()
        local on = self:GetChecked() and true or false
        if self._msufCheckFill then
            local c = on and C.checkFill or C.inputBg
            self._msufCheckFill:SetVertexColor(c[1], c[2], c[3], on and 0.96 or (c[4] or 1))
        end
        if self._msufCheckEdge then
            local c = on and C.checkEdge or C.inputEdge
            self._msufCheckEdge:SetVertexColor(c[1], c[2], c[3], on and 0.86 or 0.46)
        end
    end
    local rawSetChecked = chk.SetChecked
    chk.SetChecked = function(self, value)
        rawSetChecked(self, value and true or false)
        self:RefreshCheckVisual()
    end
    chk:RefreshCheckVisual()

    local lbl = FS(row, 12, C.white)
    lbl:SetPoint("LEFT", chk, "RIGHT", 10, 0); lbl:SetText(Tr(opts.label or ""))
    chk._label = lbl; chk.Text = lbl

    --- Dependent rows: grayed out when unchecked, enabled when checked
    chk._deps = {}
    function chk:SetDependentRows(...)
        for i = 1, select("#", ...) do
            local dep = select(i, ...)
            if dep then chk._deps[#chk._deps + 1] = dep end
        end
        chk:UpdateDependents()
    end
    function chk:UpdateDependents()
        local on = self:GetChecked() and true or false
        local a = on and 1 or 0.28
        for _, dep in ipairs(self._deps) do
            if dep.SetAlpha then dep:SetAlpha(a) end
            if dep.EnableMouse then dep:EnableMouse(on) end
        end
    end

    if cb then
        chk:SetScript("OnClick", function(s)
            s:RefreshCheckVisual()
            s:UpdateDependents()
            cb(s:GetChecked())
        end)
    else
        chk:SetScript("OnClick", function(s)
            s:RefreshCheckVisual()
            s:UpdateDependents()
        end)
    end
    if cbKey then pf[cbKey] = chk end
    card._rowCount = card._rowCount + 1; card._rows[card._rowCount] = row
    return row
end

--- FooterButtons
function Factory.FooterButtons(pf)
    local function MakeBtn(text, w)
        return Menu2Style.Button(pf, text, w or 80, 28)
    end
    local ok = MakeBtn("OK", 80); local cancel = MakeBtn("Cancel", 80)
    ok:SetPoint("BOTTOMLEFT", pf, "BOTTOM", -84, 10)
    cancel:SetPoint("BOTTOMRIGHT", pf, "BOTTOM", 84, 10)
    pf.okBtn = ok; pf.cancelBtn = cancel
    return ok, cancel
end

function Factory.EnableStepper(box, m, p, on)
    local a = on and 1 or 0.25
    if box then box:EnableMouse(on); box:SetAlpha(a) end
    if m then m:EnableMouse(on); m:SetAlpha(a) end
    if p then p:EnableMouse(on); p:SetAlpha(a) end
end
function Factory.EnableLabel(l, on) if l then l:SetAlpha(on and 1 or 0.25) end end

function Factory.ActionRow(pf, body, opts)
    if not pf or not body then return end
    opts = opts or {}
    local row = CreateFrame("Frame", nil, body)
    row:SetHeight(opts.height or 26)
    row:SetPoint("TOPLEFT", opts.anchorTo or body, "BOTTOMLEFT", 0, opts.yOff or -6)
    row:SetPoint("TOPRIGHT", opts.anchorTo or body, "BOTTOMRIGHT", 0, opts.yOff or -6)

    local buttons = {}
    local prev
    local gap = opts.gap or 8
    for i, spec in ipairs(opts.buttons or {}) do
        local b = Menu2Style.Button(row, spec.label or "", spec.width or 120, opts.buttonHeight or 22, spec.onClick)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", gap, 0)
        else b:SetPoint("LEFT", row, "LEFT", 4, 0) end
        buttons[i] = b
        prev = b
    end
    row.buttons = buttons
    return row, buttons
end

--- SelectRow: "Label: [ Current Value â–¾ ]" (popup menu, not cycle-click)
function Factory.SelectRow(pf, body, card, opts)
    local selectKey = opts.selectKey
    local stateKey  = opts.stateKey
    local items     = opts.items or {}
    local cb        = opts.onChanged
    local row = NewFactoryRow(body, opts, ROW_H)

    local label = FS(row, 11, C.muted)
    label:SetPoint("LEFT", 0, 0); label:SetText(Tr(opts.label or "Select:"))

    local btnW = opts.width or 140
    local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
    btn:SetSize(btnW, BOX_H)
    btn:SetPoint("LEFT", label, "RIGHT", 6, 0)
    btn:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1 })
    btn:SetBackdropColor(unpack(C.inputBg)); btn:SetBackdropBorderColor(unpack(C.inputEdge))
    local hl = btn:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints()
    hl:SetColorTexture(C.stepHover[1], C.stepHover[2], C.stepHover[3], C.stepHover[4])
    local btnFS = FS(btn, 10, C.white); btnFS:SetPoint("CENTER")

    --- Popup menu frame (lazy-built, reused)
    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("TOOLTIP"); menu:SetFrameLevel(960)
    menu:SetClampedToScreen(true); menu:EnableMouse(true); menu:Hide()
    local menuBg = menu:CreateTexture(nil, "BACKGROUND"); menuBg:SetAllPoints()
    menuBg:SetColorTexture(C.panelBg[1], C.panelBg[2], C.panelBg[3], 0.97)
    local menuBrd = CreateFrame("Frame", nil, menu, "BackdropTemplate"); menuBrd:SetAllPoints()
    menuBrd:SetFrameLevel(max(0, menu:GetFrameLevel() - 1))
    menuBrd:SetBackdrop({ edgeFile=W8, edgeSize=1 }); menuBrd:SetBackdropBorderColor(unpack(C.panelEdge))

    local function ResolveItems()
        if type(items) == "function" then return items() end
        return items
    end

    local _builtBtns
    local function BuildMenu()
        if _builtBtns then
            for _, old in ipairs(_builtBtns) do old:Hide() end
        end
        local list = ResolveItems()
        _builtBtns = {}
        local itemH = 20
        local menuW = (opts.menuWidth or btnW) + 20
        menu:SetSize(menuW, #list * itemH + 6)
        for i, src in ipairs(list) do
            local it = CreateFrame("Button", nil, menu)
            it:SetSize(menuW - 4, itemH)
            it:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -(3 + (i - 1) * itemH))
            local iBg = it:CreateTexture(nil, "BACKGROUND"); iBg:SetAllPoints()
            iBg:SetColorTexture(0, 0, 0, 0)
            local iFS = FS(it, 10, C.white); iFS:SetPoint("LEFT", 8, 0)
            iFS:SetText(Tr(src.label or src.key))
            it:SetScript("OnEnter", function() iBg:SetColorTexture(0.10, 0.20, 0.45, 0.25) end)
            it:SetScript("OnLeave", function() iBg:SetColorTexture(0, 0, 0, 0) end)
            it:SetScript("OnClick", function()
                menu:Hide()
                if stateKey then pf[stateKey] = src.key end
                btnFS:SetText(Tr(src.label or src.key))
                if cb then cb() end
            end)
            _builtBtns[i] = it
        end
    end

    function btn:SetValue(key)
        if stateKey then pf[stateKey] = key end
        local list = ResolveItems()
        for _, src in ipairs(list) do
            if src.key == key then btnFS:SetText(Tr(src.label or src.key)); return end
        end
        btnFS:SetText(tostring(key or ""))
    end
    function btn:GetValue() return stateKey and pf[stateKey] end

    btn:SetScript("OnClick", function()
        if menu:IsShown() then menu:Hide(); return end
        BuildMenu()
        menu:ClearAllPoints()
        menu:SetPoint("TOP", btn, "BOTTOM", 0, -2)
        menu:Show()
    end)

    menu:SetScript("OnUpdate", function(self)
        if not self:IsShown() then return end
        if btn:IsMouseOver() or self:IsMouseOver() then
            self._closeTimer = nil
        else
            if not self._closeTimer then self._closeTimer = GetTime() + 0.4
            elseif GetTime() >= self._closeTimer then self:Hide() end
        end
    end)

    if selectKey then pf[selectKey] = btn end
    card._rowCount = card._rowCount + 1; card._rows[card._rowCount] = row
    return row
end

--- â”€â”€ Copy Settings Dropdown â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
--- Creates a "Copy To" dropdown button in a popup.
--- opts.sources = { {key="player", label="Player"}, ... }
--- opts.onCopy = function(targetKey) --- called when user picks a target
--- opts.anchorTo = widget to anchor below
function Factory.CopyDropdown(pf, body, card, opts)
    if not pf or not body or not opts then return end
    local FONT = STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF"
    local placeholder = opts.placeholder or "Select..."

    local row = CreateFrame("Frame", nil, body)
    row:SetHeight(24)
    row:SetPoint("TOPLEFT", opts.anchorTo or body, "BOTTOMLEFT", 0, -6)
    row:SetPoint("TOPRIGHT", opts.anchorTo or body, "BOTTOMRIGHT", 0, -6)

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFont(FONT, 11, ""); label:SetShadowOffset(1, -1)
    label:SetTextColor(0.55, 0.62, 0.78, 0.85)
    label:SetPoint("LEFT", 4, 0)
    label:SetText(Tr(opts.label or "Copy To"))

    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(140, 20)
    btn:SetPoint("RIGHT", -4, 0)

    local btnBg = btn:CreateTexture(nil, "BACKGROUND")
    btnBg:SetAllPoints(); btnBg:SetColorTexture(0.09, 0.10, 0.15, 0.90)

    local btnBrd = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    btnBrd:SetAllPoints(); btnBrd:SetFrameLevel(btn:GetFrameLevel() - 1)
    btnBrd:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    btnBrd:SetBackdropBorderColor(0.10, 0.20, 0.42, 0.65)

    local btnText = btn:CreateFontString(nil, "OVERLAY")
    btnText:SetFont(FONT, 10, ""); btnText:SetShadowOffset(1, -1)
    btnText:SetPoint("CENTER"); btnText:SetTextColor(0.75, 0.88, 1.00, 1)
    btnText:SetText(Tr(placeholder))

    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("TOOLTIP"); menu:SetFrameLevel(950)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:Hide()

    local menuBg = menu:CreateTexture(nil, "BACKGROUND")
    menuBg:SetAllPoints(); menuBg:SetColorTexture(0.03, 0.05, 0.12, 0.96)

    local menuBrd = CreateFrame("Frame", nil, menu, "BackdropTemplate")
    menuBrd:SetAllPoints(); menuBrd:SetFrameLevel(menu:GetFrameLevel() - 1)
    menuBrd:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    menuBrd:SetBackdropBorderColor(0.10, 0.20, 0.45, 0.90)

    local sources = opts.sources or {}
    local itemH = 22
    local menuW = 150
    menu:SetSize(menuW, #sources * itemH + 6)

    for i, src in ipairs(sources) do
        local item = CreateFrame("Button", nil, menu)
        item:SetSize(menuW - 4, itemH)
        item:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -(3 + (i - 1) * itemH))

        local itemBg = item:CreateTexture(nil, "BACKGROUND")
        itemBg:SetAllPoints(); itemBg:SetColorTexture(0, 0, 0, 0)

        local itemFS = item:CreateFontString(nil, "OVERLAY")
        itemFS:SetFont(FONT, 10, ""); itemFS:SetShadowOffset(1, -1)
        itemFS:SetPoint("LEFT", 8, 0)
        itemFS:SetTextColor(0.86, 0.92, 1.00, 0.90)
        itemFS:SetText(Tr(src.label or src.key))

        item:SetScript("OnEnter", function()
            itemBg:SetColorTexture(0.10, 0.20, 0.45, 0.25)
            itemFS:SetTextColor(0.86, 0.92, 1.00, 1)
        end)
        item:SetScript("OnLeave", function()
            itemBg:SetColorTexture(0, 0, 0, 0)
            itemFS:SetTextColor(0.86, 0.92, 1.00, 0.90)
        end)
        item:SetScript("OnClick", function()
            menu:Hide()
            btnText:SetText(Tr(src.label or src.key))
            if opts.onCopy then opts.onCopy(src.key) end
            C_Timer.After(1.5, function() btnText:SetText(Tr(placeholder)) end)
        end)
    end

    btn:SetScript("OnClick", function()
        if menu:IsShown() then
            menu:Hide()
        else
            menu:ClearAllPoints()
            menu:SetPoint("TOP", btn, "BOTTOM", 0, -2)
            menu:Show()
        end
    end)

    --- Close on global mouse click outside
    menu:SetScript("OnShow", function(self)
        self._closeTimer = nil
    end)
    menu:SetScript("OnUpdate", function(self)
        if not self:IsShown() then return end
        if btn:IsMouseOver() or self:IsMouseOver() then
            self._closeTimer = nil
        else
            if not self._closeTimer then
                self._closeTimer = GetTime() + 0.4
            elseif GetTime() >= self._closeTimer then
                self:Hide()
            end
        end
    end)

    return row
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

_G.MSUF_InstallEditPopupUI = InstallEditPopupUI
