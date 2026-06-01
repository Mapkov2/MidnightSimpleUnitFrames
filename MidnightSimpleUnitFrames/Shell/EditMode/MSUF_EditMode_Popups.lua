--- MSUF_EM2_Popups.lua - PopupFactory + all Popup types (consolidated)

--- MSUF_EM2_PopupFactory.lua

--- MSUF_EM2_PopupFactory.lua v5 - MSUF Options Menu Match
--- ALL sections collapsible (chevron = collapse only).
--- Show/Hide toggles are inside card body, not in header.
--- Chevron: gold closed ▸, orange open ▾ (matches Options exactly).
local addonName, MSUF = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

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
local function ApplyAllSettingsSafe()
    local UF = MSUF and MSUF.UF
    if UF and UF.Apply then UF.Apply(nil); return true end
    return false
end

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

local function Tr(text)
    if type(text) ~= "string" then return text end
    if type(MSUF) == "table" and type(MSUF.Translate) == "function" then
        return MSUF.Translate(text)
    end
    local locale = (type(MSUF) == "table" and MSUF.L) or _G.MSUF_L
    if type(locale) == "table" then
        local translated = rawget(locale, text)
        if translated ~= nil then return translated end
    end
    return text
end

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
    pf:HookScript("OnHide", function()
        local function RefreshPopupFocus()
            local anyOpen = EM2.Popups and EM2.Popups.IsAnyOpen and EM2.Popups.IsAnyOpen()
            if not anyOpen then
                if EM2.State and EM2.State.SetPopupOpen then EM2.State.SetPopupOpen(false) end
                if EM2.Focus and EM2.Focus.ClearPopupFocus then EM2.Focus.ClearPopupFocus() end
            elseif EM2.Focus and EM2.Focus.RefreshPopupFocus then
                EM2.Focus.RefreshPopupFocus()
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, RefreshPopupFocus) else RefreshPopupFocus() end
    end)

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

--- PairRow: "X: [-][val][+] Y: [-][val][+]"
function Factory.PairRow(pf, body, card, opts)
    local l1t, l2t = opts.label1 or "X:", opts.label2 or "Y:"
    local k1, k2 = opts.key1, opts.key2
    local cb = opts.onChanged
    local anchorTo = opts.anchorTo

    local row = CreateFrame("Frame", nil, body)
    row:SetHeight(ROW_H)
    if anchorTo then row:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -ROW_GAP)
    else row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0) end
    row:SetPoint("RIGHT", body, "RIGHT", 0, 0)

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
    local boxKey = opts.boxKey; local cb = opts.onChanged; local anchorTo = opts.anchorTo

    local row = CreateFrame("Frame", nil, body)
    row:SetHeight(ROW_H)
    if anchorTo then row:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, (opts.yOff or -ROW_GAP))
    else row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0) end
    row:SetPoint("RIGHT", body, "RIGHT", 0, 0)

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

--- SizeAnchorRow: "Size: [-][val][+] [ Anchor ▸ ]"
function Factory.SizeAnchorRow(pf, body, card, opts)
    local sizeKey = opts.sizeKey; local anchorKey = opts.anchorKey
    local stateKey = opts.stateKey; local cb = opts.onChanged
    local options = opts.options or { {"LEFT","Left"}, {"RIGHT","Right"}, {"CENTER","Center"} }
    local anchorTo = opts.anchorTo

    local row = CreateFrame("Frame", nil, body)
    row:SetHeight(ROW_H)
    if anchorTo then row:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -ROW_GAP)
    else row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0) end
    row:SetPoint("RIGHT", body, "RIGHT", 0, 0)

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
    local cbKey = opts.cbKey; local cb = opts.onChanged; local anchorTo = opts.anchorTo

    local row = CreateFrame("Frame", nil, body)
    row:SetHeight(24)
    if anchorTo then row:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, (opts.yOff or -ROW_GAP))
    else row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0) end
    row:SetPoint("RIGHT", body, "RIGHT", 0, 0)

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

--- SelectRow: "Label: [ Current Value ▾ ]" (popup menu, not cycle-click)
function Factory.SelectRow(pf, body, card, opts)
    local selectKey = opts.selectKey
    local stateKey  = opts.stateKey
    local items     = opts.items or {}
    local cb        = opts.onChanged
    local anchorTo  = opts.anchorTo

    local row = CreateFrame("Frame", nil, body)
    row:SetHeight(ROW_H)
    if anchorTo then row:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, (opts.yOff or -ROW_GAP))
    else row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0) end
    row:SetPoint("RIGHT", body, "RIGHT", 0, 0)

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

--- ── Copy Settings Dropdown ──────────────────────────────────────────────
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

--- MSUF_EM2_Popups.lua

--- MSUF_EM2_Popups.lua
--- Popup router. All popups are Midnight-native (EM2).
local addonName, MSUF = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local Popups = {}
EM2.Popups = Popups

function Popups.CloseAll()
    if EM2.UnitPopup then EM2.UnitPopup.Close() end
    if EM2.CastPopup then EM2.CastPopup.Close() end
    if EM2.AuraPopup then EM2.AuraPopup.Close() end
    if _G.MSUF_EM2_HideGFPopup then
        _G.MSUF_EM2_HideGFPopup("party")
        _G.MSUF_EM2_HideGFPopup("raid")
        _G.MSUF_EM2_HideGFPopup("mythicraid")
    end
    if EM2.State then EM2.State.SetPopupOpen(false) end
    if EM2.Focus and EM2.Focus.ClearPopupFocus then EM2.Focus.ClearPopupFocus() end
end

function Popups.Open(key, anchorFrame)
    if type(key) ~= "string" or key == "" then return end
    local cfg = EM2.Registry and EM2.Registry.Get(key)
    local pType = cfg and cfg.popupType

    if not pType then
        if key == "player" or key == "target" or key == "focus" or key == "focustarget" or key == "targettarget" or key == "pet" or key:match("^boss%d") then
            pType = "unit"
        elseif key:sub(1, 8) == "castbar_" then
            pType = "castbar"
        elseif key:sub(1, 5) == "aura_" then
            pType = "aura"
        elseif key == "gf_party" or key == "gf_raid" or key == "gf_mythicraid" then
            pType = key
        end
    end

    Popups.CloseAll()

    if pType == "unit" then
        _G.MSUF_EM2_ActiveAuraGroup = nil
        _G.MSUF_EM2_ActiveAuraUnit  = nil
        local unit = key
        if key:match("^boss%d") then unit = "boss" end
        local frame = cfg and cfg.getFrame and cfg.getFrame()
        if EM2.UnitPopup then
            EM2.UnitPopup.Open(unit, frame or anchorFrame)
            if EM2.State then EM2.State.SetPopupOpen(true) end
        end
    elseif pType == "castbar" then
        _G.MSUF_EM2_ActiveAuraGroup = nil
        _G.MSUF_EM2_ActiveAuraUnit  = nil
        local unit = key
        if key:sub(1, 8) == "castbar_" then unit = key:sub(9) end
        if type(unit) == "string" and unit:match("^boss%d+$") then unit = "boss" end
        local frame = cfg and cfg.getFrame and cfg.getFrame()
        if EM2.CastPopup then EM2.CastPopup.Open(unit, frame or anchorFrame) end
    elseif pType == "aura" then
        local unit = key
        if key:sub(1, 5) == "aura_" then unit = key:sub(6) end
        local frame = cfg and cfg.getFrame and cfg.getFrame()
        if EM2.AuraPopup then EM2.AuraPopup.Open(unit, frame or anchorFrame) end
    elseif pType == "gf_party" or pType == "gf_raid" or pType == "gf_mythicraid" then
        _G.MSUF_EM2_ActiveAuraGroup = nil
        _G.MSUF_EM2_ActiveAuraUnit  = nil
        local mode = (pType == "gf_raid") and "raid" or ((pType == "gf_mythicraid") and "mythicraid" or "party")
        if _G.MSUF_EM2_ShowGFPopup then
            _G.MSUF_EM2_ShowGFPopup(mode)
            if EM2.State then EM2.State.SetPopupOpen(true) end
        end
    end
    if Popups.IsAnyOpen and Popups.IsAnyOpen() then
        if EM2.State then EM2.State.SetPopupOpen(true) end
        if EM2.Focus and EM2.Focus.SetPopupFocus then EM2.Focus.SetPopupFocus(key, anchorFrame) end
    end
end

function Popups.IsAnyOpen()
    return (EM2.UnitPopup and EM2.UnitPopup.IsOpen())
        or (EM2.CastPopup and EM2.CastPopup.IsOpen())
        or (EM2.AuraPopup and EM2.AuraPopup.IsOpen())
        or (type(_G.MSUF_EM2_GFPopupIsOpen) == "function" and _G.MSUF_EM2_GFPopupIsOpen())
        or false
end

--- MSUF_EM2_Popup_Unit.lua

--- MSUF_EM2_Popup_Unit.lua - v5
local addonName, MSUF = ...
local EM2 = _G.MSUF_EM2
if not EM2 or not EM2.PopupFactory then return end
local F = EM2.PopupFactory
local floor = math.floor
local max, min = math.max, math.min
local function DB() return _G.MSUF_DB end
local function Conf(k) local db=DB(); return db and db[k] end
local function CK(u) if not u then return nil end; if u=="targettarget" or u=="tot" then return "targettarget" end
    if u=="focustarget" or u=="focus_target" or u=="focustargettarget" then return "focustarget" end
    if _G.MSUF_GetBossIndexFromToken and _G.MSUF_GetBossIndexFromToken(u) then return "boss" end; return u end
local LABELS = { player="Player", target="Target", focus="Focus", focustarget="Focus Target", targettarget="ToT", pet="Pet", boss="Boss" }
local UNIT_PAGE_KEYS = { player="uf_player", target="uf_target", focus="uf_focus", focustarget="uf_focustarget", targettarget="uf_targettarget", pet="uf_pet", boss="uf_boss" }
local UNIT_COPY_TARGETS = {
    { key="player", label="Player" },
    { key="target", label="Target" },
    { key="focus", label="Focus" },
    { key="focustarget", label="Focus Target" },
    { key="targettarget", label="ToT" },
    { key="pet", label="Pet" },
    { key="boss", label="Boss" },
}
local function San(v,d) v=tonumber(v) or d or 0; if v~=v or v>2000 or v<-2000 then v=d or 0 end; return floor(v+0.5) end
local function CanDetachPower(key) return key=="player" or key=="target" or key=="focus" end
local pf
local Sync

local function UnitSectionForComponent(component)
    if component == "name" or component == "hp" or component == "power" or component == "text" then return "text" end
    if component == "auras" then return "auras3" end
    if component == "castbar" or component == "cast" then return "castbar" end
    if component == "powerbar" or component == "power_bar" or component == "detached" then return "power_bar" end
    if component == "anchor" or component == "anchoring" then return "anchoring" end
    if component == "portrait" then return "portrait" end
    if component == "alpha" or component == "transparency" then return "transparency" end
    if component == "status" or component == "status_icons" then return "status_icons" end
    return "frame_basics"
end

local function Apply()
    if BlockConfigCombatLocked() then return end
    if not pf or not pf.unit then return end
    local key=CK(pf.unit); local conf=key and Conf(key); if not conf then return end
    if type(_G.MSUF_EM_UndoBeforeChange)=="function" then _G.MSUF_EM_UndoBeforeChange("unit", key) end
    conf.offsetX=San(pf.xBox and tonumber(pf.xBox:GetText()),0); conf.offsetY=San(pf.yBox and tonumber(pf.yBox:GetText()),0)
    local w=pf.wBox and tonumber(pf.wBox:GetText()); if w then conf.width=floor(max(40,min(800,w))+0.5) end
    local h=pf.hBox and tonumber(pf.hBox:GetText()); if h then conf.height=floor(max(8,min(200,h))+0.5) end
    if conf.powerBarDetached and CanDetachPower(key) then
        local dx=pf.dpbXBox and tonumber(pf.dpbXBox:GetText()); if dx then conf.detachedPowerBarOffsetX=San(dx,0) end
        local dy=pf.dpbYBox and tonumber(pf.dpbYBox:GetText()); if dy then conf.detachedPowerBarOffsetY=San(dy,-4) end
        local dw=pf.dpbWBox and tonumber(pf.dpbWBox:GetText()); if dw then conf.detachedPowerBarWidth=floor(max(20,min(800,dw))+0.5) end
        local dh=pf.dpbHBox and tonumber(pf.dpbHBox:GetText()); if dh then conf.detachedPowerBarHeight=floor(max(2,min(80,dh))+0.5) end
        local dl=pf.dpbLevelBox and tonumber(pf.dpbLevelBox:GetText()); if dl then conf.detachedPowerBarFrameLevelOffset=floor(max(0,min(20,dl))+0.5) end
        if pf.dpbTextBtn then conf.detachedPowerBarTextOnBar = pf.dpbTextBtn._checked and true or false end
        if key == "player" then
            if pf.dpbSyncBtn then conf.detachedPowerBarSyncClassPower = pf.dpbSyncBtn._checked and true or false end
            if pf.dpbAnchorBtn then conf.detachedPowerBarAnchorToClassPower = pf.dpbAnchorBtn._checked and true or false end
        end
    end
    if type(_G.MSUF_UpdateAllFonts)=="function" then _G.MSUF_UpdateAllFonts() end
    --- Direct SetSize: MarkDirty/UpdateSimpleUnitFrame only handles health/power/text,
    --- not frame dimensions. Apply width/height immediately.
    if pf.parent and conf.width and conf.height then
        pf.parent:SetSize(conf.width, conf.height)
    end
    if pf.parent and pf.parent.ForceUpdate then pf.parent:ForceUpdate("EM2_UNIT_POPUP") end
    --- Full layout re-apply (power bar embed, text anchors, borders, etc.)
    if type(_G.MSUF_ApplyUnitFrameKey_Immediate)=="function" then _G.MSUF_ApplyUnitFrameKey_Immediate(key) end
    if type(_G.MSUF_ForceTextLayoutForUnitKey)=="function" then _G.MSUF_ForceTextLayoutForUnitKey(key) end
    --- Clear PBEmbedLayout stamp so width/height changes are re-applied
    if pf.parent then
        local cs=_G.MSUF_NS and _G.MSUF_NS.Cache; if cs and cs.ClearStamp then cs.ClearStamp(pf.parent, "PBEmbedLayout") end
    end
    if type(_G.MSUF_ApplyPowerBarEmbedLayout)=="function" and pf.parent then _G.MSUF_ApplyPowerBarEmbedLayout(pf.parent) end
    if pf._refreshVisibility then pf._refreshVisibility() end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    RefreshUFPreview("EM2_UNIT_POPUP_APPLY", key)
    if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(key, true) end
    if pf and pf:IsShown() then Sync() end
end

function Sync()
    if not pf or not pf.unit then return end
    local key=CK(pf.unit); local conf=key and Conf(key); if not conf then return end
    local function S(b,v)
        if not (b and b.SetText) then return end
        if b.HasFocus and b:HasFocus() then return end
        b:SetText(tostring(v or 0))
    end
    if pf._titleFS then pf._titleFS:SetText(Tr((LABELS[key] or key or "") .. " - Frame")) end
    S(pf.xBox,San(conf.offsetX,0)); S(pf.yBox,San(conf.offsetY,0))
    S(pf.wBox,conf.width or (pf.parent and pf.parent:GetWidth()) or 250)
    S(pf.hBox,conf.height or (pf.parent and pf.parent:GetHeight()) or 40)
    if pf.detachBtn and pf.detachBtn.SetCheckedVisual then
        local canDetach = CanDetachPower(key)
        local detachedOn = canDetach and conf.powerBarDetached == true
        pf.detachBtn:SetShown(canDetach)
        pf.detachBtn:SetCheckedVisual(detachedOn)
        if pf.dpbPanel then
            pf.dpbPanel:SetShown(detachedOn)
            pf:SetHeight(detachedOn and (key == "player" and 526 or 488) or (canDetach and 292 or 244))
            if detachedOn then pf.dpbPanel:SetHeight(key == "player" and 220 or 184) end
        end
        if detachedOn then
            local function S(b,v)
                if not (b and b.SetText) then return end
                if b.HasFocus and b:HasFocus() then return end
                b:SetText(tostring(v or 0))
            end
            S(pf.dpbXBox, San(conf.detachedPowerBarOffsetX, 0))
            S(pf.dpbYBox, San(conf.detachedPowerBarOffsetY, -4))
            S(pf.dpbWBox, conf.detachedPowerBarWidth or conf.width or 250)
            S(pf.dpbHBox, conf.detachedPowerBarHeight or 6)
            S(pf.dpbLevelBox, conf.detachedPowerBarFrameLevelOffset or 6)
            if pf.dpbTextBtn and pf.dpbTextBtn.SetCheckedVisual then
                pf.dpbTextBtn:SetCheckedVisual(conf.detachedPowerBarTextOnBar == true)
            end
            local isPlayer = key == "player"
            if pf.dpbSyncBtn then
                pf.dpbSyncBtn:SetShown(isPlayer)
                if pf.dpbSyncBtn.SetCheckedVisual then pf.dpbSyncBtn:SetCheckedVisual(isPlayer and conf.detachedPowerBarSyncClassPower ~= false) end
            end
            if pf.dpbAnchorBtn then
                pf.dpbAnchorBtn:SetShown(isPlayer)
                if pf.dpbAnchorBtn.SetCheckedVisual then pf.dpbAnchorBtn:SetCheckedVisual(isPlayer and conf.detachedPowerBarAnchorToClassPower == true) end
            end
            local firstY = isPlayer and -92 or -62
            if pf.dpbXYRow then
                pf.dpbXYRow:ClearAllPoints()
                pf.dpbXYRow:SetPoint("TOPLEFT", pf.dpbPanel, "TOPLEFT", 16, firstY)
            end
            if pf.dpbWHRow then
                pf.dpbWHRow:ClearAllPoints()
                pf.dpbWHRow:SetPoint("TOPLEFT", pf.dpbPanel, "TOPLEFT", 16, firstY - 34)
            end
            if pf.dpbLayerRow then
                pf.dpbLayerRow:ClearAllPoints()
                pf.dpbLayerRow:SetPoint("TOPLEFT", pf.dpbPanel, "TOPLEFT", 16, firstY - 68)
            end
        end
    end
end

local function SetHUDStatus(text, kind)
    if type(_G.MSUF_EM2_SetHUDStatus) == "function" then
        _G.MSUF_EM2_SetHUDStatus(Tr(text), kind)
    end
end

local function ApplyMenu2UnitSelection(component, slot)
    if not pf or not pf.unit then return nil end
    local key = CK(pf.unit)
    if not key then return nil end
    local pageKey = UNIT_PAGE_KEYS[key] or "uf_player"
    local sectionId = UnitSectionForComponent(component)

    if EM2.Focus and EM2.Focus.SetSelection then
        EM2.Focus.SetSelection(key, component, slot, { source = "unit-popup", menu = false })
    end

    _G.MSUF_EM2_MenuFocusRequest = {
        key = key,
        component = component,
        slot = slot,
        pageKey = pageKey,
        sectionId = sectionId,
        source = "unit-popup",
        explicit = true,
        changedAt = GetTime and GetTime() or 0,
    }

    local M = _G.MSUF2 or (MSUF and MSUF.MSUF2)
    if M then
        M.editModeSelection = {
            key = key,
            component = component,
            slot = slot,
            pageKey = pageKey,
            sectionId = sectionId,
        }
    end
    if M and (component == "name" or component == "hp" or component == "power") then
        M.unitTextTabSelection = M.unitTextTabSelection or {}
        M.unitTextTabSelection[key] = component
        if slot then
            M.unitTextSlotSelection = M.unitTextSlotSelection or {}
            M.unitTextSlotSelection[key] = M.unitTextSlotSelection[key] or {}
            M.unitTextSlotSelection[key][component] = slot
        end
    end

    return key
end

local function OpenMenu2Page(pageKey, component, slot)
    if not pf or not pf.unit then return end
    Apply()
    local key = ApplyMenu2UnitSelection(component, slot)
    pageKey = pageKey or UNIT_PAGE_KEYS[key or CK(pf.unit)] or "uf_player"
    local M = _G.MSUF2 or (MSUF and MSUF.MSUF2)
    if M and pageKey and type(M.InvalidatePage) == "function" then M.InvalidatePage(pageKey) end
    pf:Hide()
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

local function OpenMenu2Settings()
    OpenMenu2Page(nil, "frame")
end

local function ApplyDetachPower(checked)
    if BlockConfigCombatLocked() then return end
    if not pf or not pf.unit then return end
    local key = CK(pf.unit)
    if not CanDetachPower(key) then return end
    local conf = key and Conf(key)
    if not conf then return end
    if type(_G.MSUF_EM_UndoBeforeChange)=="function" then _G.MSUF_EM_UndoBeforeChange("unit", key) end
    conf.powerBarDetached = checked and true or false
    if conf.powerBarDetached then
        conf.detachedPowerBarOffsetX = tonumber(conf.detachedPowerBarOffsetX) or 0
        conf.detachedPowerBarOffsetY = tonumber(conf.detachedPowerBarOffsetY) or -4
        conf.detachedPowerBarWidth = tonumber(conf.detachedPowerBarWidth) or tonumber(conf.width) or 250
        conf.detachedPowerBarHeight = tonumber(conf.detachedPowerBarHeight) or 6
        conf.detachedPowerBarFrameLevelOffset = tonumber(conf.detachedPowerBarFrameLevelOffset) or 6
        if key == "player" and conf.detachedPowerBarSyncClassPower == nil then conf.detachedPowerBarSyncClassPower = true end
    end
    if type(_G.MSUF_ApplyUnitFrameKey_Immediate)=="function" then _G.MSUF_ApplyUnitFrameKey_Immediate(key) end
    if type(_G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey)=="function" then
        _G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey(key, true)
    elseif type(_G.MSUF_ApplyPowerBarEmbedLayout_All)=="function" then
        _G.MSUF_ApplyPowerBarEmbedLayout_All()
    elseif type(_G.MSUF_ApplyPowerBarEmbedLayout)=="function" and pf.parent then
        _G.MSUF_ApplyPowerBarEmbedLayout(pf.parent)
    end
    if pf.parent and pf.parent.ForceUpdate then pf.parent:ForceUpdate("EM2_UNIT_POPUP_DETACH") end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    RefreshUFPreview("EM2_UNIT_POPUP_DETACH", key)
    SetHUDStatus(checked and "Detached powerbar" or "Embedded powerbar", "ok")
    Sync()
end

local function CopyBoundsTo(targetKey)
    if BlockConfigCombatLocked() then return end
    if not pf or not pf.unit or not targetKey then return end
    local db = DB()
    if not db then return end
    Apply()
    local srcKey = CK(pf.unit)
    local src = srcKey and db[srcKey]
    if not src or targetKey == srcKey then return end
    if type(_G.MSUF_EM_UndoBeforeChange)=="function" then _G.MSUF_EM_UndoBeforeChange("unit", targetKey) end
    local dst = db[targetKey]
    if not dst then db[targetKey] = {}; dst = db[targetKey] end
    dst.offsetX = San(src.offsetX, 0)
    dst.offsetY = San(src.offsetY, 0)
    if src.width ~= nil then dst.width = floor(max(40, min(800, tonumber(src.width) or 250)) + 0.5) end
    if src.height ~= nil then dst.height = floor(max(8, min(200, tonumber(src.height) or 40)) + 0.5) end
    if type(_G.MSUF_ApplyUnitFrameKey_Immediate)=="function" then _G.MSUF_ApplyUnitFrameKey_Immediate(targetKey) end
    if not ApplyAllSettingsSafe() and type(_G.MSUF_UpdateAllFrames)=="function" then _G.MSUF_UpdateAllFrames() end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    RefreshUFPreview("EM2_UNIT_POPUP_COPY_BOUNDS", targetKey)
    if EM2.Focus and EM2.Focus.Pulse then EM2.Focus.Pulse(targetKey, "frame", nil, { source = "unit-copy", duration = 0.32 }) end
    SetHUDStatus("Copied frame bounds", "ok")
    Sync()
end

local function Build()
    if pf then return pf end
    RefreshPalette()
    pf = CreateFrame("Frame", "MSUF_EM2_UnitPopup", UIParent, "BackdropTemplate")
    pf:SetSize(440, 292)
    pf:SetPoint("CENTER", UIParent, "CENTER", 250, 0)
    pf:SetFrameStrata("DIALOG")
    pf:SetFrameLevel(220)
    pf:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=1,right=1,top=1,bottom=1} })
    pf:SetBackdropColor(C.panelBg[1], C.panelBg[2], C.panelBg[3], 0.96)
    pf:SetBackdropBorderColor(C.panelEdge[1], C.panelEdge[2], C.panelEdge[3], 0.95)
    Menu2Style.Shell(pf)
    pf:EnableMouse(true)
    pf:SetMovable(true)
    pf:SetClampedToScreen(true)
    pf:RegisterForDrag("LeftButton")
    pf:SetScript("OnDragStart", function(s) if not BlockConfigCombatLocked() then s:StartMoving() end end)
    pf:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)

    local title = FS(pf, 15, C.white)
    title:SetPoint("TOPLEFT", pf, "TOPLEFT", 20, -18)
    title:SetText("Frame")
    pf._titleFS = title

    local closeBtn = Menu2Style.CloseButton(pf, function() pf:Hide() end)
    closeBtn:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -10, -10)

    local subtitle = FS(pf, 12, C.muted)
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText(Tr("Frame bounds"))

    local function MakeButtonIn(parent, text, x, y, w, onClick)
        local b = Menu2Style.Button(parent, text, w or 66, 30, onClick)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        return b
    end

    local function MakeTinyButton(text, x, y, w, onClick)
        return MakeButtonIn(pf, text, x, y, w, onClick)
    end

    local function WirePopupFocus(btn, component, slot)
        if not (btn and btn.HookScript) then return btn end
        btn:HookScript("OnEnter", function()
            local key = pf and pf.unit and CK(pf.unit)
            if key and EM2.Focus and EM2.Focus.SetHover then
                EM2.Focus.SetHover(key, component, slot, { source = "unit-popup" })
            end
        end)
        btn:HookScript("OnLeave", function()
            if EM2.Focus and EM2.Focus.ClearHover then EM2.Focus.ClearHover("unit-popup") end
        end)
        return btn
    end

    local function MakeToggleButtonIn(parent, text, x, y, w, onClick)
        local b = MakeButtonIn(parent, text, x, y, w, nil)
        function b:SetCheckedVisual(checked)
            self._checked = checked and true or false
            if self.SetActive then
                self:SetActive(self._checked)
                return
            end
            if self._checked then
                self:SetBackdropColor(0.08, 0.16, 0.28, 0.96)
                self:SetBackdropBorderColor(C.title[1], C.title[2], C.title[3], 0.95)
                if self._label then self._label:SetTextColor(C.title[1], C.title[2], C.title[3], 1) end
            else
                self:SetBackdropColor(C.btnBg[1], C.btnBg[2], C.btnBg[3], 0.88)
                self:SetBackdropBorderColor(C.btnEdge[1], C.btnEdge[2], C.btnEdge[3], 0.82)
                if self._label then self._label:SetTextColor(C.white[1], C.white[2], C.white[3], C.white[4] or 1) end
            end
        end
        b:SetScript("OnClick", function(s)
            s:SetCheckedVisual(not s._checked)
            if onClick then onClick(s._checked) end
            if pf and pf:IsShown() then Sync() end
        end)
        b:SetCheckedVisual(false)
        return b
    end

    local function MakeToggleButton(text, x, y, w, onClick)
        return MakeToggleButtonIn(pf, text, x, y, w, onClick)
    end

    local function MakeCopyButton(x, y, w)
        local b = MakeTinyButton("Copy to", x, y, w, nil)
        local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        menu:SetFrameStrata("TOOLTIP")
        menu:SetFrameLevel(960)
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        menu:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1 })
        menu:SetBackdropColor(C.panelBg[1], C.panelBg[2], C.panelBg[3], 0.98)
        menu:SetBackdropBorderColor(C.panelEdge[1], C.panelEdge[2], C.panelEdge[3], 0.95)
        Menu2Style.Shell(menu)
        menu:Hide()

        local itemH = 22
        menu:SetSize(w, #UNIT_COPY_TARGETS * itemH + 6)
        for i, src in ipairs(UNIT_COPY_TARGETS) do
            local item = CreateFrame("Button", nil, menu)
            item:SetSize(w - 4, itemH)
            item:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -(3 + (i - 1) * itemH))
            local bg = item:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0, 0, 0, 0)
            local fs = FS(item, 10, C.white)
            fs:SetPoint("LEFT", 8, 0)
            fs:SetText(Tr(src.label))
            item:SetScript("OnEnter", function()
                bg:SetColorTexture(C.btnHover[1], C.btnHover[2], C.btnHover[3], 0.22)
            end)
            item:SetScript("OnLeave", function() bg:SetColorTexture(0, 0, 0, 0) end)
            item:SetScript("OnClick", function()
                menu:Hide()
                CopyBoundsTo(src.key)
                if b then
                    Menu2Style.SetButtonText(b, src.label)
                    C_Timer.After(1.2, function() Menu2Style.SetButtonText(b, "Copy to") end)
                end
            end)
        end
        b:SetScript("OnClick", function()
            if menu:IsShown() then menu:Hide(); return end
            menu:ClearAllPoints()
            menu:SetPoint("TOP", b, "BOTTOM", 0, -3)
            menu:Show()
        end)
        menu:SetScript("OnUpdate", function(self)
            if not self:IsShown() then return end
            if b:IsMouseOver() or self:IsMouseOver() then
                self._closeTimer = nil
            else
                if not self._closeTimer then self._closeTimer = GetTime() + 0.35
                elseif GetTime() >= self._closeTimer then self:Hide() end
            end
        end)
        pf:HookScript("OnHide", function() menu:Hide() end)
        return b
    end

    local function MakeValuePairIn(parent, x, y, label1, key1, label2, key2)
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(400, 24)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y)

        local l1 = FS(row, 11, C.white)
        l1:SetPoint("LEFT", row, "LEFT", 0, 0)
        l1:SetText(label1)
        local m1 = MakeStep(row, "-")
        m1:SetPoint("LEFT", l1, "RIGHT", 6, 0)
        local b1 = MakeBox(row, 52)
        b1:SetPoint("LEFT", m1, "RIGHT", 1)
        local p1 = MakeStep(row, "+")
        p1:SetPoint("LEFT", b1, "RIGHT", 1)
        WireStepper(m1, b1, p1, Apply)
        b1:SetScript("OnEditFocusLost", Apply)
        pf[key1] = b1

        local l2 = FS(row, 11, C.white)
        l2:SetPoint("LEFT", p1, "RIGHT", 18, 0)
        l2:SetText(label2)
        local m2 = MakeStep(row, "-")
        m2:SetPoint("LEFT", l2, "RIGHT", 6, 0)
        local b2 = MakeBox(row, 52)
        b2:SetPoint("LEFT", m2, "RIGHT", 1)
        local p2 = MakeStep(row, "+")
        p2:SetPoint("LEFT", b2, "RIGHT", 1)
        WireStepper(m2, b2, p2, Apply)
        b2:SetScript("OnEditFocusLost", Apply)
        pf[key2] = b2
        return row
    end

    local function MakeValuePair(y, label1, key1, label2, key2)
        return MakeValuePairIn(pf, 20, y, label1, key1, label2, key2)
    end

    local function MakeSingleValueIn(parent, x, y, label, key)
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(360, 24)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y)
        local l = FS(row, 11, C.white)
        l:SetPoint("LEFT", row, "LEFT", 0, 0)
        l:SetText(label)
        local m = MakeStep(row, "-")
        m:SetPoint("LEFT", l, "RIGHT", 6, 0)
        local b = MakeBox(row, 52)
        b:SetPoint("LEFT", m, "RIGHT", 1)
        local p = MakeStep(row, "+")
        p:SetPoint("LEFT", b, "RIGHT", 1)
        WireStepper(m, b, p, Apply)
        b:SetScript("OnEditFocusLost", Apply)
        pf[key] = b
        return row
    end

    MakeValuePair(-72, "X", "xBox", "Y", "yBox")
    MakeValuePair(-102, "Width", "wBox", "Height", "hBox")

    WirePopupFocus(MakeTinyButton("Name", 20, -140, 58, function() OpenMenu2Page(nil, "name") end), "name")
    WirePopupFocus(MakeTinyButton("HP", 90, -140, 58, function() OpenMenu2Page(nil, "hp") end), "hp")
    WirePopupFocus(MakeTinyButton("Power", 160, -140, 72, function() OpenMenu2Page(nil, "power") end), "power")
    WirePopupFocus(MakeTinyButton("Auras", 244, -140, 68, function() OpenMenu2Page(nil, "auras") end), "auras")
    WirePopupFocus(MakeTinyButton("Cast", 324, -140, 58, function() OpenMenu2Page(nil, "castbar") end), "castbar")

    MakeTinyButton("Open settings", 20, -190, 190, OpenMenu2Settings)
    MakeCopyButton(224, -190, 190)
    pf.detachBtn = MakeToggleButton("Detach powerbar", 20, -238, 394, ApplyDetachPower)

    pf.dpbPanel = CreateFrame("Frame", nil, pf, "BackdropTemplate")
    pf.dpbPanel:SetPoint("TOPLEFT", pf, "TOPLEFT", 20, -282)
    pf.dpbPanel:SetSize(394, 220)
    pf.dpbPanel:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=1,right=1,top=1,bottom=1} })
    pf.dpbPanel:SetBackdropColor(C.cardBg[1], C.cardBg[2], C.cardBg[3], 0.58)
    pf.dpbPanel:SetBackdropBorderColor(C.cardEdge[1], C.cardEdge[2], C.cardEdge[3], 0.72)
    Menu2Style.Card(pf.dpbPanel)
    local dpbTitle = FS(pf.dpbPanel, 12, C.white)
    dpbTitle:SetPoint("TOPLEFT", pf.dpbPanel, "TOPLEFT", 16, -12)
    dpbTitle:SetText(Tr("Detached power bar"))
    local dpbHint = FS(pf.dpbPanel, 10, C.muted)
    dpbHint:SetPoint("LEFT", dpbTitle, "RIGHT", 10, 0)
    dpbHint:SetText(Tr("position, size, and layer"))
    pf.dpbTextBtn = MakeToggleButtonIn(pf.dpbPanel, "Text on bar", 16, -36, 112, Apply)
    pf.dpbSyncBtn = MakeToggleButtonIn(pf.dpbPanel, "Sync class", 140, -36, 112, Apply)
    pf.dpbAnchorBtn = MakeToggleButtonIn(pf.dpbPanel, "Anchor class", 264, -36, 114, Apply)
    pf.dpbXYRow = MakeValuePairIn(pf.dpbPanel, 16, -92, "X", "dpbXBox", "Y", "dpbYBox")
    pf.dpbWHRow = MakeValuePairIn(pf.dpbPanel, 16, -126, "Width", "dpbWBox", "Height", "dpbHBox")
    pf.dpbLayerRow = MakeSingleValueIn(pf.dpbPanel, 16, -160, "Layer", "dpbLevelBox")
    pf.dpbPanel:Hide()

    if EM2.AttachPopupScaleGrip then EM2.AttachPopupScaleGrip(pf) end

    pf:EnableKeyboard(true)
    pf:SetScript("OnKeyDown", function(s,k) if k=="ESCAPE" then s:SetPropagateKeyboardInput(false); s:Hide() else s:SetPropagateKeyboardInput(true) end end)
    pf:HookScript("OnHide", function(s)
        if s.SetPropagateKeyboardInput then s:SetPropagateKeyboardInput(true) end
        if EM2.Focus and EM2.Focus.ClearHover then EM2.Focus.ClearHover("unit-popup") end
        local function RefreshPopupFocus()
            local anyOpen = EM2.Popups and EM2.Popups.IsAnyOpen and EM2.Popups.IsAnyOpen()
            if not anyOpen then
                if EM2.State and EM2.State.SetPopupOpen then EM2.State.SetPopupOpen(false) end
                if EM2.Focus and EM2.Focus.ClearPopupFocus then EM2.Focus.ClearPopupFocus() end
            elseif EM2.Focus and EM2.Focus.RefreshPopupFocus then
                EM2.Focus.RefreshPopupFocus()
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, RefreshPopupFocus) else RefreshPopupFocus() end
    end)
    pf:Hide()
    return pf
end

local UnitPopup = {}; EM2.UnitPopup = UnitPopup
function UnitPopup.Open(u, parent) if BlockConfigCombatLocked() then return false end; Build(); pf.unit=u; pf.parent=parent; Sync(); pf:Show(); if Menu2Style.FadeIn then Menu2Style.FadeIn(pf, 0.12, 0.86, 1) end; return true end
function UnitPopup.Close() if pf then pf:Hide() end end
function UnitPopup.IsOpen() return pf and pf:IsShown() or false end
function UnitPopup.Sync() if pf and pf:IsShown() then Sync() end end
