-- MSUF_EM2_Popups.lua — PopupFactory + all Popup types (consolidated)

-- MSUF_EM2_PopupFactory.lua

-- MSUF_EM2_PopupFactory.lua  v5 — MSUF Options Menu Match
-- ALL sections collapsible (chevron = collapse only).
-- Show/Hide toggles are inside card body, not in header.
-- Chevron: gold closed ▸, orange open ▾ (matches Options exactly).
local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local Factory = {}
EM2.PopupFactory = Factory

local floor = math.floor
local max, min = math.max, math.min
local W8 = "Interface/Buttons/WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF"
local CHEVRON = "Interface\\ChatFrame\\ChatFrameExpandArrow"
local function ApplyAllSettingsSafe()
    local fn = _G.MSUF_ApplyAllSettings
    if type(fn) == "function" then fn(); return true end
    return false
end

local C = {
    -- Match MSUF_THEME: bg=0.03/0.05/0.12, edge=0.10/0.20/0.45
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
    checkFill = { 0.90, 0.55, 0.15, 1.00 },
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
    if type(ns) == "table" and type(ns.Translate) == "function" then
        return ns.Translate(text)
    end
    local locale = (type(ns) == "table" and ns.L) or _G.MSUF_L
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

-- Panel
function Factory.Panel(name, width, visibleH, title)
    width = width or PW; visibleH = visibleH or 540

    local pf = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    pf:SetSize(width, visibleH)
    pf:SetPoint("CENTER", UIParent, "CENTER", 250, 0)
    pf:SetFrameStrata("DIALOG"); pf:SetFrameLevel(200)
    pf:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=1,right=1,top=1,bottom=1} })
    pf:SetBackdropColor(unpack(C.panelBg)); pf:SetBackdropBorderColor(unpack(C.panelEdge))
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

    local closeBtn = CreateFrame("Button", nil, pf)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("RIGHT", pf, "TOPRIGHT", -12, -TITLE_H / 2)
    local xFS = FS(closeBtn, 16, C.muted); xFS:SetPoint("CENTER", 0, 1); xFS:SetText("x")
    closeBtn:SetScript("OnClick", function() pf:Hide() end)
    closeBtn:SetScript("OnEnter", function() xFS:SetTextColor(1, 0.4, 0.4, 1) end)
    closeBtn:SetScript("OnLeave", function() xFS:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end)

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

-- Card: collapsible section (matches MakeCollapsibleSection in Options)
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

    -- Header (always visible)
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

    -- Divider
    local div = card:CreateTexture(nil, "ARTWORK"); div:SetHeight(1)
    div:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 6, -1)
    div:SetPoint("RIGHT", card, "RIGHT", -6, 0)
    div:SetColorTexture(unpack(C.divider))

    -- Body (collapsible)
    local body = CreateFrame("Frame", nil, card)
    body:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -BODY_TOP)
    body:SetPoint("RIGHT", card, "RIGHT", -CARD_PAD, 0)
    body:SetHeight(1)
    card._body = body

    -- Collapse state
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
        -- Recalc parent scroll
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

-- Stepper + EditBox helpers
local function MakeStep(parent, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(STEP_W, BOX_H)
    local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(unpack(C.stepBg))
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(unpack(C.stepHover))
    local fs = FS(b, 14, C.white); fs:SetPoint("CENTER", 0, 1); fs:SetText(text)
    return b
end

local function MakeBox(parent, w)
    local b = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    b:SetSize(w or BOX_W, BOX_H)
    b:SetFont(FONT, 12, ""); b:SetTextColor(unpack(C.white))
    b:SetJustifyH("CENTER"); b:SetAutoFocus(false); b:SetMaxLetters(7)
    b:SetBackdrop({bgFile=W8, edgeFile=W8, edgeSize=1})
    b:SetBackdropColor(unpack(C.inputBg)); b:SetBackdropBorderColor(unpack(C.inputEdge))
    b:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    return b
end

local function WireStepper(m, box, p, cb)
    m:SetScript("OnClick", function() local v=tonumber(box:GetText()) or 0; box:SetText(tostring(floor(v-GetStep()+0.5))); if cb then cb() end end)
    p:SetScript("OnClick", function() local v=tonumber(box:GetText()) or 0; box:SetText(tostring(floor(v+GetStep()+0.5))); if cb then cb() end end)
    box:SetScript("OnEnterPressed", function(s) s:ClearFocus(); if cb then cb() end end)
end

-- PairRow: "X:  [–][val][+]    Y:  [–][val][+]"
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

-- SingleRow: "Label:  [–][val][+]"
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

-- SizeAnchorRow: "Size: [–][val][+]   [ Anchor ▸ ]"
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

-- CheckRow
function Factory.CheckRow(pf, body, card, opts)
    local cbKey = opts.cbKey; local cb = opts.onChanged; local anchorTo = opts.anchorTo

    local row = CreateFrame("Frame", nil, body)
    row:SetHeight(20)
    if anchorTo then row:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, (opts.yOff or -ROW_GAP))
    else row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0) end
    row:SetPoint("RIGHT", body, "RIGHT", 0, 0)

    local chk = CreateFrame("CheckButton", nil, row)
    chk:SetSize(16, 16); chk:SetPoint("LEFT", 0, 0)
    local bg = chk:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
    bg:SetColorTexture(C.inputBg[1], C.inputBg[2], C.inputBg[3], C.inputBg[4])
    local brd = CreateFrame("Frame", nil, chk, "BackdropTemplate"); brd:SetAllPoints()
    brd:SetFrameLevel(max(0, chk:GetFrameLevel()-1))
    brd:SetBackdrop({edgeFile=W8, edgeSize=1}); brd:SetBackdropBorderColor(unpack(C.inputEdge))
    local ck = chk:CreateTexture(nil, "OVERLAY"); ck:SetSize(10, 10); ck:SetPoint("CENTER")
    ck:SetColorTexture(unpack(C.checkFill)); chk:SetCheckedTexture(ck)

    local lbl = FS(row, 12, C.white)
    lbl:SetPoint("LEFT", chk, "RIGHT", 8, 0); lbl:SetText(Tr(opts.label or ""))
    chk._label = lbl; chk.Text = lbl

    -- Dependent rows: grayed out when unchecked, enabled when checked
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
            s:UpdateDependents()
            cb(s:GetChecked())
        end)
    else
        chk:SetScript("OnClick", function(s) s:UpdateDependents() end)
    end
    if cbKey then pf[cbKey] = chk end
    card._rowCount = card._rowCount + 1; card._rows[card._rowCount] = row
    return row
end

-- FooterButtons
function Factory.FooterButtons(pf)
    local function MakeBtn(text, w)
        local b = CreateFrame("Button", nil, pf); b:SetSize(w or 80, 28)
        local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(unpack(C.btnBg))
        local brd = CreateFrame("Frame", nil, b, "BackdropTemplate"); brd:SetAllPoints()
        brd:SetFrameLevel(max(0, b:GetFrameLevel()-1))
        brd:SetBackdrop({edgeFile=W8, edgeSize=1}); brd:SetBackdropBorderColor(unpack(C.btnEdge))
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(unpack(C.btnHover))
        local fs = FS(b, 12, C.white); fs:SetPoint("CENTER"); fs:SetText(Tr(text))
        b._label = fs; return b
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

-- SelectRow: "Label:  [ Current Value ▾ ]"   (popup menu, not cycle-click)
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

    -- Popup menu frame (lazy-built, reused)
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

-- ── Copy Settings Dropdown ──────────────────────────────────────────────
-- Creates a "Copy From" dropdown button in a popup.
-- opts.sources = { {key="player", label="Player"}, ... }
-- opts.onCopy  = function(sourceKey) -- called when user picks a source
-- opts.anchorTo = widget to anchor below
function Factory.CopyDropdown(pf, body, card, opts)
    if not pf or not body or not opts then return end
    local FONT = STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF"

    local row = CreateFrame("Frame", nil, body)
    row:SetHeight(24)
    row:SetPoint("TOPLEFT", opts.anchorTo or body, "BOTTOMLEFT", 0, -6)
    row:SetPoint("TOPRIGHT", opts.anchorTo or body, "BOTTOMRIGHT", 0, -6)

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFont(FONT, 11, ""); label:SetShadowOffset(1, -1)
    label:SetTextColor(0.55, 0.62, 0.78, 0.85)
    label:SetPoint("LEFT", 4, 0)
    label:SetText(Tr("Copy To"))

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
    btnText:SetText(Tr("Select..."))

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
            C_Timer.After(1.5, function() btnText:SetText(Tr("Select...")) end)
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

    -- Close on global mouse click outside
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

-- MSUF_EM2_Popups.lua

-- MSUF_EM2_Popups.lua
-- Popup router. All popups are Midnight-native (EM2).
local addonName, ns = ...
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
end

function Popups.Open(key, anchorFrame)
    local cfg = EM2.Registry and EM2.Registry.Get(key)
    local pType = cfg and cfg.popupType

    if not pType then
        if key == "player" or key == "target" or key == "focus" or key == "focustarget" or key == "targettarget" or key == "pet" or key:match("^boss%d") then
            pType = "unit"
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
end

function Popups.IsAnyOpen()
    return (EM2.UnitPopup and EM2.UnitPopup.IsOpen())
        or (EM2.CastPopup and EM2.CastPopup.IsOpen())
        or (EM2.AuraPopup and EM2.AuraPopup.IsOpen())
        or (type(_G.MSUF_EM2_GFPopupIsOpen) == "function" and _G.MSUF_EM2_GFPopupIsOpen())
        or false
end

-- MSUF_EM2_Popup_Unit.lua

-- MSUF_EM2_Popup_Unit.lua — v5
local addonName, ns = ...
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
local function San(v,d) v=tonumber(v) or d or 0; if v~=v or v>2000 or v<-2000 then v=d or 0 end; return floor(v+0.5) end
local pf

local function Apply()
    if BlockConfigCombatLocked() then return end
    if not pf or not pf.unit then return end
    local key=CK(pf.unit); local conf=key and Conf(key); if not conf then return end
    if type(_G.MSUF_EM_UndoBeforeChange)=="function" then _G.MSUF_EM_UndoBeforeChange("unit", key) end
    conf.offsetX=San(pf.xBox and tonumber(pf.xBox:GetText()),0); conf.offsetY=San(pf.yBox and tonumber(pf.yBox:GetText()),0)
    local w=pf.wBox and tonumber(pf.wBox:GetText()); if w then conf.width=floor(max(40,min(800,w))+0.5) end
    local h=pf.hBox and tonumber(pf.hBox:GetText()); if h then conf.height=floor(max(8,min(200,h))+0.5) end
    if pf.nameShowCB then conf.showName=pf.nameShowCB:GetChecked() and true or false end
    conf.nameOffsetX=San(pf.nameXBox and tonumber(pf.nameXBox:GetText()),0); conf.nameOffsetY=San(pf.nameYBox and tonumber(pf.nameYBox:GetText()),0)
    if pf._msufNameAnchorVal then conf.nameTextAnchor=pf._msufNameAnchorVal end
    if pf.nameSizeBox then local sz=tonumber(pf.nameSizeBox:GetText()); if sz then conf.nameFontSize=floor(max(6,min(48,sz))+0.5) end end
    if pf.hpShowCB then conf.showHP=pf.hpShowCB:GetChecked() and true or false end
    conf.hpOffsetX=San(pf.hpXBox and tonumber(pf.hpXBox:GetText()),0); conf.hpOffsetY=San(pf.hpYBox and tonumber(pf.hpYBox:GetText()),0)
    if pf.hpSizeBox then local sz=tonumber(pf.hpSizeBox:GetText()); if sz then conf.hpFontSize=floor(max(6,min(48,sz))+0.5) end end
    if pf.powerShowCB then conf.showPower=pf.powerShowCB:GetChecked() and true or false end
    conf.powerOffsetX=San(pf.powerXBox and tonumber(pf.powerXBox:GetText()),0); conf.powerOffsetY=San(pf.powerYBox and tonumber(pf.powerYBox:GetText()),0)
    if pf.powerSizeBox then local sz=tonumber(pf.powerSizeBox:GetText()); if sz then conf.powerFontSize=floor(max(6,min(48,sz))+0.5) end end
    if pf.detachCB and (pf.unit=="player" or pf.unit=="target" or pf.unit=="focus") then
        conf.powerBarDetached=pf.detachCB:GetChecked() and true or false
        if conf.powerBarDetached then
            local dw=pf.dpbWBox and tonumber(pf.dpbWBox:GetText()); if dw then conf.detachedPowerBarWidth=floor(max(20,min(800,dw))+0.5) end
            local dh=pf.dpbHBox and tonumber(pf.dpbHBox:GetText()); if dh then conf.detachedPowerBarHeight=floor(max(2,min(80,dh))+0.5) end
            local dx=pf.dpbXBox and tonumber(pf.dpbXBox:GetText()); if dx then conf.detachedPowerBarOffsetX=floor(dx+0.5) end
            local dy=pf.dpbYBox and tonumber(pf.dpbYBox:GetText()); if dy then conf.detachedPowerBarOffsetY=floor(dy+0.5) end
            local dl=pf.dpbLevelBox and tonumber(pf.dpbLevelBox:GetText()); if dl then conf.detachedPowerBarFrameLevelOffset=floor(max(0,min(30,dl))+0.5) end
            if pf.syncCPCB and pf.unit=="player" then conf.detachedPowerBarSyncClassPower=pf.syncCPCB:GetChecked() and true or false end
            if pf.anchorCPCB and pf.unit=="player" then conf.detachedPowerBarAnchorToClassPower=pf.anchorCPCB:GetChecked() and true or false end
            if pf.textOnBarCB then conf.detachedPowerBarTextOnBar=pf.textOnBarCB:GetChecked() and true or false end
        end
    end
    if type(_G.MSUF_UpdateAllFonts)=="function" then _G.MSUF_UpdateAllFonts() end
    -- Direct SetSize: MarkDirty/UpdateSimpleUnitFrame only handles health/power/text,
    -- not frame dimensions. Apply width/height immediately.
    if pf.parent and conf.width and conf.height then
        pf.parent:SetSize(conf.width, conf.height)
    end
    local md=_G.MSUF_UFCore_MarkDirty; if type(md)=="function" and pf.parent then md(pf.parent, nil, true, "EM2:UnitPopup")
    elseif type(_G.MSUF_UpdateSimpleUnitFrame)=="function" and pf.parent then (_G.MSUF_UpdateSimpleUnitFrame)(pf.parent) end
    -- Full layout re-apply (power bar embed, text anchors, borders, etc.)
    if type(_G.MSUF_ApplyUnitFrameKey_Immediate)=="function" then _G.MSUF_ApplyUnitFrameKey_Immediate(key) end
    if type(_G.MSUF_ForceTextLayoutForUnitKey)=="function" then _G.MSUF_ForceTextLayoutForUnitKey(key) end
    -- Clear PBEmbedLayout stamp so width/height changes are re-applied
    if pf.parent then
        local cs=_G.MSUF_NS and _G.MSUF_NS.Cache; if cs and cs.ClearStamp then cs.ClearStamp(pf.parent, "PBEmbedLayout") end
    end
    if type(_G.MSUF_ApplyPowerBarEmbedLayout)=="function" and pf.parent then _G.MSUF_ApplyPowerBarEmbedLayout(pf.parent) end
    if pf._refreshVisibility then pf._refreshVisibility() end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    RefreshUFPreview("EM2_UNIT_POPUP_APPLY", key)
end

local function Sync()
    if not pf or not pf.unit then return end
    local key=CK(pf.unit); local conf=key and Conf(key); if not conf then return end
    local function S(b,v) if b and b.SetText then b:SetText(tostring(v or 0)) end end
    local function SC(c,v) if c and c.SetChecked then c:SetChecked(v and true or false) end end
    if pf._titleFS then pf._titleFS:SetText(Tr(LABELS[key] or key or "")) end
    S(pf.xBox,San(conf.offsetX,0)); S(pf.yBox,San(conf.offsetY,0))
    S(pf.wBox,conf.width or (pf.parent and pf.parent:GetWidth()) or 250)
    S(pf.hBox,conf.height or (pf.parent and pf.parent:GetHeight()) or 40)
    SC(pf.nameShowCB, conf.showName~=false)
    S(pf.nameXBox,conf.nameOffsetX or 0); S(pf.nameYBox,conf.nameOffsetY or 0)
    local db=DB(); local g=db and db.general or {}
    S(pf.nameSizeBox,conf.nameFontSize or g.nameFontSize or g.fontSize or 14)
    pf._msufNameAnchorVal=conf.nameTextAnchor or "LEFT"
    if pf.nameAnchorDrop then pf.nameAnchorDrop:SetValue(pf._msufNameAnchorVal) end
    SC(pf.hpShowCB, conf.showHP~=false)
    S(pf.hpXBox,conf.hpOffsetX or 0); S(pf.hpYBox,conf.hpOffsetY or 0)
    S(pf.hpSizeBox,conf.hpFontSize or g.hpFontSize or g.fontSize or 14)
    SC(pf.powerShowCB, (key ~= "focustarget" and conf.showPower ~= false) or conf.showPower == true)
    S(pf.powerXBox,conf.powerOffsetX or 0); S(pf.powerYBox,conf.powerOffsetY or 0)
    S(pf.powerSizeBox,conf.powerFontSize or g.powerFontSize or g.fontSize or 14)
    SC(pf.detachCB,conf.powerBarDetached); SC(pf.syncCPCB,conf.detachedPowerBarSyncClassPower)
    SC(pf.anchorCPCB,conf.detachedPowerBarAnchorToClassPower); SC(pf.textOnBarCB,conf.detachedPowerBarTextOnBar)
    S(pf.dpbWBox,conf.detachedPowerBarWidth or 150); S(pf.dpbHBox,conf.detachedPowerBarHeight or 6)
    S(pf.dpbXBox,conf.detachedPowerBarOffsetX or 0); S(pf.dpbYBox,conf.detachedPowerBarOffsetY or 0)
    S(pf.dpbLevelBox,conf.detachedPowerBarFrameLevelOffset or 6)
    pf.MSUF_prev = {}; for k,v in pairs(conf) do if type(v)~="table" then pf.MSUF_prev[k]=v end end; pf.MSUF_prev.key=key
    -- Refresh dependent gray-out state
    if pf.nameShowCB and pf.nameShowCB.UpdateDependents then pf.nameShowCB:UpdateDependents() end
    if pf.hpShowCB and pf.hpShowCB.UpdateDependents then pf.hpShowCB:UpdateDependents() end
    if pf.powerShowCB and pf.powerShowCB.UpdateDependents then pf.powerShowCB:UpdateDependents() end
    if pf._refreshVisibility then pf._refreshVisibility() end
end

local function Build()
    if pf then return pf end
    pf = F.Panel("MSUF_EM2_UnitPopup", 380, 540, "Player")
    local ANCH = { {"LEFT","Left"}, {"RIGHT","Right"}, {"CENTER","Center"} }
    local top = pf._contentTop

    -- Frame
    local fC, fB = F.Card(pf, top, "Position & Size", -2, true)
    local fXY = F.PairRow(pf, fB, fC, { label1="X:", label2="Y:", key1="xBox", key2="yBox", onChanged=Apply })
    local fWH = F.PairRow(pf, fB, fC, { label1="W:", label2="H:", key1="wBox", key2="hBox", anchorTo=fXY, onChanged=Apply })
    fC:RecalcHeight()

    -- Name
    local nC, nB = F.Card(pf, fC, "Name", -6, true)
    local nShow = F.CheckRow(pf, nB, nC, { label="Show Name", cbKey="nameShowCB", onChanged=function() Apply() end })
    local nXY = F.PairRow(pf, nB, nC, { label1="X:", label2="Y:", key1="nameXBox", key2="nameYBox", anchorTo=nShow, onChanged=Apply })
    local nSA = F.SizeAnchorRow(pf, nB, nC, { sizeKey="nameSizeBox", anchorKey="nameAnchorDrop", stateKey="_msufNameAnchorVal", options=ANCH, anchorTo=nXY, onChanged=Apply })
    nC:RecalcHeight()
    pf.nameShowCB:SetDependentRows(nXY, nSA)

    -- HP
    local hC, hB = F.Card(pf, nC, "HP", -6, true)
    local hShow = F.CheckRow(pf, hB, hC, { label="Show HP", cbKey="hpShowCB", onChanged=function() Apply() end })
    local hXY = F.PairRow(pf, hB, hC, { label1="X:", label2="Y:", key1="hpXBox", key2="hpYBox", anchorTo=hShow, onChanged=Apply })
    local hSA = F.SingleRow(pf, hB, hC, { label="Size:", boxKey="hpSizeBox", anchorTo=hXY, onChanged=Apply })
    hC:RecalcHeight()
    pf.hpShowCB:SetDependentRows(hXY, hSA)

    -- Power
    local pC, pB = F.Card(pf, hC, "Power", -6, true)
    local pShow = F.CheckRow(pf, pB, pC, { label="Show Power", cbKey="powerShowCB", onChanged=function() Apply() end })
    local pXY = F.PairRow(pf, pB, pC, { label1="X:", label2="Y:", key1="powerXBox", key2="powerYBox", anchorTo=pShow, onChanged=Apply })
    local pSA = F.SingleRow(pf, pB, pC, { label="Size:", boxKey="powerSizeBox", anchorTo=pXY, onChanged=Apply })
    pC:RecalcHeight()
    pf.powerShowCB:SetDependentRows(pXY, pSA)

    -- Detach
    local dC, dB = F.Card(pf, pC, "Detached Power Bar", -6, false)
    pf._dpbCard = dC
    local dToggle = F.CheckRow(pf, dB, dC, { label="Detach from frame", cbKey="detachCB", onChanged=function() Apply() end })
    local dSync = F.CheckRow(pf, dB, dC, { label="Sync width to Resource Bar", cbKey="syncCPCB", anchorTo=dToggle, onChanged=function() Apply() end })
    local dAnch = F.CheckRow(pf, dB, dC, { label="Anchor to Resource Bar", cbKey="anchorCPCB", anchorTo=dSync, onChanged=function() Apply() end })
    local dText = F.CheckRow(pf, dB, dC, { label="Power text on bar", cbKey="textOnBarCB", anchorTo=dAnch, onChanged=function() Apply() end })
    local dWH = F.PairRow(pf, dB, dC, { label1="W:", label2="H:", key1="dpbWBox", key2="dpbHBox", anchorTo=dText, onChanged=Apply })
    local dXY = F.PairRow(pf, dB, dC, { label1="X:", label2="Y:", key1="dpbXBox", key2="dpbYBox", anchorTo=dWH, onChanged=Apply })
    local dLevel = F.SingleRow(pf, dB, dC, { label="Level:", boxKey="dpbLevelBox", anchorTo=dXY, onChanged=Apply })
    dC:RecalcHeight()

    pf._allCards = { fC, nC, hC, pC, dC }

    -- Copy Settings dropdown
    local UNIT_SOURCES = {
        { key = "player", label = "Player" },
        { key = "target", label = "Target" },
        { key = "focus",  label = "Focus"  },
        { key = "focustarget", label = "Focus Target" },
        { key = "targettarget", label = "ToT" },
        { key = "pet",    label = "Pet"    },
        { key = "boss",   label = "Boss"   },
    }
    local SKIP_COPY = { offsetX=true, offsetY=true, anchorFrameName=true, anchorToUnitframe=true }
    local copyRow = F.CopyDropdown(pf, pf._scrollChild, nil, {
        anchorTo = dC,
        sources = UNIT_SOURCES,
        onCopy = function(targetKey)
            local db = _G.MSUF_DB; if not db then return end
            local srcKey = pf.unit; if not srcKey then return end
            local src = db[srcKey]; if not src then return end
            if _G.MSUF_EM_UndoBeforeChange then _G.MSUF_EM_UndoBeforeChange("unit", targetKey) end
            local dst = db[targetKey]; if not dst then db[targetKey] = {}; dst = db[targetKey] end
            -- Copy all keys FROM current unit TO selected target (except position)
            for k, v in pairs(src) do
                if not SKIP_COPY[k] then
                    if type(v) == "table" then
                        dst[k] = _G.MSUF_DeepCopy and _G.MSUF_DeepCopy(v) or v
                    else
                        dst[k] = v
                    end
                end
            end
            -- Apply + resync
            ApplyAllSettingsSafe()
            if _G.MSUF_UpdateAllFonts then _G.MSUF_UpdateAllFonts() end
            RefreshUFPreview("EM2_UNIT_POPUP_COPY", CK(pf.unit))
            C_Timer.After(0.1, function() Sync() end)
        end,
    })

    -- Visibility refresh
    pf._refreshVisibility = function()
        local u = pf.unit
        local canDetach = (u == "player" or u == "target" or u == "focus")
        local isPlayer = (u == "player")
        dC:SetShown(canDetach)
        -- Sync/Anchor to Resource Bar: only meaningful for player
        if pf.syncCPCB then pf.syncCPCB:SetShown(isPlayer) end
        if pf.anchorCPCB then pf.anchorCPCB:SetShown(isPlayer) end
        -- Recalc scroll
        C_Timer.After(0, function()
            local t = pf._scrollChild and pf._scrollChild:GetTop()
            local last = copyRow or (canDetach and dC or pC)
            local b = last and last.GetBottom and last:GetBottom()
            if t and b then pf:UpdateScrollHeight(t - b + 30) else pf:UpdateScrollHeight(640) end
        end)
    end

    pf._recalcScroll = pf._refreshVisibility

    local ok, cancel = F.FooterButtons(pf)
    ok:SetScript("OnClick", function() Apply(); pf:Hide() end)
    cancel:SetScript("OnClick", function()
        if pf.MSUF_prev and pf.MSUF_prev.key then
            local conf=Conf(pf.MSUF_prev.key)
            if conf then for k,v in pairs(pf.MSUF_prev) do if k~="key" then conf[k]=v end end
                ApplyAllSettingsSafe()
                if type(_G.MSUF_UpdateAllFonts)=="function" then _G.MSUF_UpdateAllFonts() end
                RefreshUFPreview("EM2_UNIT_POPUP_CANCEL", pf.MSUF_prev.key)
            end
        end; pf:Hide()
    end)
    pf:EnableKeyboard(true)
    pf:SetScript("OnKeyDown", function(s,k) if k=="ESCAPE" then s:SetPropagateKeyboardInput(false); cancel:Click() else s:SetPropagateKeyboardInput(true) end end)
    pf:UpdateScrollHeight(600)
    return pf
end

local UnitPopup = {}; EM2.UnitPopup = UnitPopup
function UnitPopup.Open(u, parent) if BlockConfigCombatLocked() then return false end; Build(); pf.unit=u; pf.parent=parent; Sync(); pf:Show(); return true end
function UnitPopup.Close() if pf then pf:Hide() end end
function UnitPopup.IsOpen() return pf and pf:IsShown() or false end
function UnitPopup.Sync() if pf and pf:IsShown() then Sync() end end

-- MSUF_EM2_Popup_Cast.lua

local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 or not EM2.PopupFactory then return end
local F = EM2.PopupFactory
local floor = math.floor
local max, min = math.max, math.min
local function G() local db=_G.MSUF_DB; return db and db.general or {} end
local function EG() local db=_G.MSUF_DB; if db then db.general=db.general or {} end; return db and db.general end
local function GP(u) local fn=_G.MSUF_GetCastbarPrefix; return type(fn)=="function" and fn(u) or nil end
local function GD(u) local fn=_G.MSUF_GetCastbarDefaultOffsets; if type(fn)=="function" then return fn(u) end; return 0,0 end
local function GST(u) local fn=_G.MSUF_GetCastbarShowTimeKey; return type(fn)=="function" and fn(u) or nil end
local function San(v,d) v=tonumber(v) or d or 0; if v~=v or v>2000 or v<-2000 then v=d or 0 end; return floor(v+0.5) end
local pf
local TF = { player="MSUF_SetPlayerCastbarTestMode", target="MSUF_SetTargetCastbarTestMode", focus="MSUF_SetFocusCastbarTestMode", boss="MSUF_SetBossCastbarTestMode" }
local function SetTest(u,on) for k,fn in pairs(TF) do local f=_G[fn]; if type(f)=="function" then f(k==u and on, true) end end end

local function WidthSourceUnitLabel(u)
    if u == "player" then return "MSUF Player Frame" end
    if u == "target" then return "MSUF Target Frame" end
    if u == "focus" then return "MSUF Focus Frame" end
    if u == "boss" then return "MSUF Boss Frame" end
    return "MSUF Unit Frame"
end
local function WidthSourceItems()
    local u = pf and pf.unit
    return {
        { key = "manual",    label = "Manual" },
        { key = "unitframe", label = WidthSourceUnitLabel(u) },
        { key = "essential", label = "Essential Cooldown Row" },
        { key = "utility",   label = "Utility Cooldown Bar" },
    }
end
local function NormalizeWidthSource(v)
    local fn = _G.MSUF_NormalizeCastbarWidthSource or _G.MSUF_NormalizePlayerCastbarWidthSource
    if type(fn) == "function" then return fn(v) end
    if v == "unitframe" or v == "essential" or v == "utility" then return v end
    return nil
end
local function WidthSourceDBKey(u)
    local fn = _G.MSUF_GetCastbarWidthSourceKey
    if type(fn) == "function" then
        local key = fn(u)
        if key then return key end
    end
    if u == "player" then return "castbarPlayerMatchWidth" end
    if u == "target" then return "castbarTargetMatchWidth" end
    if u == "focus" then return "castbarFocusMatchWidth" end
    if u == "boss" then return "bossCastbarMatchWidth" end
end
local function WidthSourceKey(g, u)
    local dbKey = WidthSourceDBKey(u)
    return NormalizeWidthSource(dbKey and g and g[dbKey]) or "manual"
end
local function SetBoxText(box, value)
    if box and box.SetText then box:SetText(tostring(value or 0)) end
end
local function ManualWidthValue(g, u)
    if u == "boss" then
        return tonumber(g and g.bossCastbarWidth) or 176
    end
    local pre = GP(u)
    if not pre then return tonumber(g and g.castbarGlobalWidth) or 271 end
    return tonumber(g and g[pre .. "BarWidth"]) or tonumber(g and g.castbarGlobalWidth) or 271
end
local function GetCastbarFrameForWidth(u)
    if u == "player" then return _G.MSUF_PlayerCastbarPreview or _G.MSUF_PlayerCastbar end
    if u == "target" then return _G.MSUF_TargetCastbarPreview or _G.MSUF_TargetCastbar end
    if u == "focus" then return _G.MSUF_FocusCastbarPreview or _G.MSUF_FocusCastbar end
    if u == "boss" then return _G.MSUF_BossCastbarPreview or _G["MSUF_BossCastbarPreview1"] end
end
local function GetUnitframeWidthFallback(u)
    local unitKey = (u == "boss") and "boss1" or u
    local frames = _G.MSUF_UnitFrames
    local unitFrame = (frames and frames[unitKey]) or _G["MSUF_" .. tostring(unitKey or "")]
    local hp = unitFrame and (unitFrame.hpBar or unitFrame.healthBar or unitFrame.health)
    if hp and hp.GetWidth then
        local w = hp:GetWidth()
        if w and w > 0 then return floor(w + 0.5) end
    end
    if unitFrame and unitFrame.GetWidth then
        local w = unitFrame:GetWidth()
        if w and w > 0 then return floor(w + 0.5) end
    end
end
local function GetEffectiveWidth(g, u)
    local fn = _G.MSUF_GetCastbarDesiredSize
    if type(fn) == "function" then
        local frame = GetCastbarFrameForWidth(u)
        local w = fn(u, g, frame, ManualWidthValue(g, u), 18)
        if w and w > 0 then return floor(w + 0.5) end
    end
    if WidthSourceKey(g, u) == "unitframe" then
        local w = GetUnitframeWidthFallback(u)
        if w and w > 0 then return w end
    end
    return floor(ManualWidthValue(g, u) + 0.5)
end
local function SetManualWidthControlsEnabled(enabled)
    if not pf then return end
    F.EnableStepper(pf.wBox, pf.wBoxMinus, pf.wBoxPlus, enabled)
    F.EnableLabel(pf.wBoxLabel, enabled)
    if not enabled and pf.wBox and pf.wBox.ClearFocus then pf.wBox:ClearFocus() end
end
local function RefreshWidthSourceControls(g, u, syncDropdown)
    if not pf then return end
    local dbKey = WidthSourceDBKey(u)
    if pf.widthSourceRow then pf.widthSourceRow:SetShown(dbKey ~= nil) end
    if not dbKey then
        SetManualWidthControlsEnabled(true)
    end

    local sourceKey = WidthSourceKey(g, u)
    if syncDropdown and pf.widthSourceDrop and pf.widthSourceDrop.SetValue then
        pf.widthSourceDrop:SetValue(sourceKey)
    end
    local manual = (sourceKey == "manual")
    SetManualWidthControlsEnabled(manual)
    if manual then
        SetBoxText(pf.wBox, floor(ManualWidthValue(g, u) + 0.5))
    else
        SetBoxText(pf.wBox, GetEffectiveWidth(g, u))
    end
    if pf._sizeCard and pf._sizeCard.RecalcHeight then pf._sizeCard:RecalcHeight() end
    if pf._recalcScroll then pf._recalcScroll() end
end
local function ReanchorCastbarUnit(u)
    local ra = (u=="player" and "MSUF_ReanchorPlayerCastBar")
        or (u=="target" and "MSUF_ReanchorTargetCastBar")
        or (u=="focus" and "MSUF_ReanchorFocusCastBar")
        or (u=="boss" and "MSUF_ReanchorBossCastBar")
    if type(_G[ra])=="function" then _G[ra]() end
end
local function ApplyWidthSource()
    if BlockConfigCombatLocked() then return end
    if not pf or not pf.unit then return end
    local g = EG(); if not g then return end
    local u = pf.unit
    local dbKey = WidthSourceDBKey(u); if not dbKey then return end
    local nextSource = NormalizeWidthSource(pf.widthSourceDrop and pf.widthSourceDrop.GetValue and pf.widthSourceDrop:GetValue())
    if g[dbKey] ~= nextSource and type(_G.MSUF_EM_UndoBeforeChange) == "function" then
        _G.MSUF_EM_UndoBeforeChange("castbar", u)
    end
    g[dbKey] = nextSource
    if type(_G.MSUF_UpdateCastbarWidthSourceSync) == "function" then _G.MSUF_UpdateCastbarWidthSourceSync(g, u) end
    ReanchorCastbarUnit(u)
    if type(_G.MSUF_UpdateCastbarVisuals) == "function" then _G.MSUF_UpdateCastbarVisuals() end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    RefreshWidthSourceControls(g, u, false)
    RefreshUFPreview("EM2_CASTBAR_WIDTH_SOURCE", u)
end

local function Apply()
    if BlockConfigCombatLocked() then return end
    if not pf or not pf.unit then return end; local g=EG(); if not g then return end; local u=pf.unit
    if type(_G.MSUF_EM_UndoBeforeChange)=="function" then _G.MSUF_EM_UndoBeforeChange("castbar", u) end
    if u=="boss" then
        local widthSource
        local widthSourceKey = WidthSourceDBKey(u)
        if widthSourceKey then
            local selected = pf.widthSourceDrop and pf.widthSourceDrop.GetValue and pf.widthSourceDrop:GetValue()
            widthSource = NormalizeWidthSource(selected or g[widthSourceKey])
            g[widthSourceKey] = widthSource
        end
        g.bossCastbarOffsetX=San(pf.xBox and tonumber(pf.xBox:GetText()),0); g.bossCastbarOffsetY=San(pf.yBox and tonumber(pf.yBox:GetText()),0)
        local w=pf.wBox and tonumber(pf.wBox:GetText()); if w and not widthSource then g.bossCastbarWidth=floor(max(50,min(600,w))+0.5) end
        local h=pf.hBox and tonumber(pf.hBox:GetText()); if h then g.bossCastbarHeight=floor(max(8,min(100,h))+0.5) end
        if pf.spellShowCB then g.showBossCastName=pf.spellShowCB:GetChecked() and true or false end
        if pf.iconShowCB then g.showBossCastIcon=pf.iconShowCB:GetChecked() and true or false end
        if pf.timeShowCB then g.showBossCastTime=pf.timeShowCB:GetChecked() and true or false end
        g.bossCastTextOffsetX=San(pf.spellXBox and tonumber(pf.spellXBox:GetText()),0); g.bossCastTextOffsetY=San(pf.spellYBox and tonumber(pf.spellYBox:GetText()),0)
        if pf.spellSizeBox then local sz=tonumber(pf.spellSizeBox:GetText()); if sz then g.bossCastSpellNameFontSize=floor(max(6,min(72,sz))+0.5) end end
        if pf.iconSizeBox then local sz=tonumber(pf.iconSizeBox:GetText()); if sz then g.bossCastIconSize=floor(max(6,min(128,sz))+0.5) end end
        if pf.timeSizeBox then local sz=tonumber(pf.timeSizeBox:GetText()); if sz then g.bossCastTimeFontSize=floor(max(6,min(72,sz))+0.5) end end
        if type(_G.MSUF_UpdateCastbarWidthSourceSync) == "function" then _G.MSUF_UpdateCastbarWidthSourceSync(g, u) end
        if not (_G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()))
            and type(_G.MSUF_UpdateBossCastbarPreview)=="function"
        then
            _G.MSUF_UpdateBossCastbarPreview()
        end
        RefreshWidthSourceControls(g, u, false)
    else
        local pre=GP(u); if not pre then return end; local dx,dy=GD(u)
        local widthSource
        local widthSourceKey = WidthSourceDBKey(u)
        if widthSourceKey then
            local selected = pf.widthSourceDrop and pf.widthSourceDrop.GetValue and pf.widthSourceDrop:GetValue()
            widthSource = NormalizeWidthSource(selected or g[widthSourceKey])
            g[widthSourceKey] = widthSource
        end
        g[pre.."OffsetX"]=San(pf.xBox and tonumber(pf.xBox:GetText()),dx); g[pre.."OffsetY"]=San(pf.yBox and tonumber(pf.yBox:GetText()),dy)
        local w=pf.wBox and tonumber(pf.wBox:GetText()); if w and not widthSource then g[pre.."BarWidth"]=floor(max(50,min(600,w))+0.5) end
        local h=pf.hBox and tonumber(pf.hBox:GetText()); if h then g[pre.."BarHeight"]=floor(max(8,min(100,h))+0.5) end
        if pf.spellShowCB then g[pre.."ShowSpellName"]=pf.spellShowCB:GetChecked() and true or false end
        if pf.iconShowCB then g[pre.."ShowIcon"]=pf.iconShowCB:GetChecked() and true or false end
        local stk=GST(u); if stk and pf.timeShowCB then g[stk]=pf.timeShowCB:GetChecked() and true or false end
        g[pre.."TextOffsetX"]=San(pf.spellXBox and tonumber(pf.spellXBox:GetText()),0); g[pre.."TextOffsetY"]=San(pf.spellYBox and tonumber(pf.spellYBox:GetText()),0)
        if pf.spellSizeBox then local sz=tonumber(pf.spellSizeBox:GetText()); if sz then g[pre.."SpellNameFontSize"]=floor(max(6,min(48,sz))+0.5) end end
        if pf.iconSizeBox then local sz=tonumber(pf.iconSizeBox:GetText()); if sz then g[pre.."IconSize"]=floor(max(6,min(128,sz))+0.5) end end
        if pf.timeSizeBox then local sz=tonumber(pf.timeSizeBox:GetText()); if sz then g[pre.."TimeFontSize"]=floor(max(6,min(48,sz))+0.5) end end
        if type(_G.MSUF_UpdateCastbarWidthSourceSync) == "function" then _G.MSUF_UpdateCastbarWidthSourceSync(g, u) end
        ReanchorCastbarUnit(u)
        RefreshWidthSourceControls(g, u, false)
    end
    if type(_G.MSUF_UpdateCastbarVisuals)=="function" then _G.MSUF_UpdateCastbarVisuals() end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    RefreshUFPreview("EM2_CASTBAR_POPUP_APPLY", u)
end

local BOSS_KEYS = {
    "bossCastbarOffsetX","bossCastbarOffsetY","bossCastbarWidth","bossCastbarHeight",
    "showBossCastName","showBossCastIcon","showBossCastTime",
    "bossCastTextOffsetX","bossCastTextOffsetY",
    "bossCastSpellNameFontSize","bossCastIconSize","bossCastTimeFontSize",
    "bossCastbarDetached",
}
local function SnapshotCast(u)
    local g=G(); if not g then return nil end; local snap={}
    if u=="boss" then
        for _,k in ipairs(BOSS_KEYS) do snap[k]=g[k] end
        local wk = WidthSourceDBKey(u); if wk then snap[wk]=g[wk] end
    else
        local pre=GP(u); if not pre then return nil end
        local stk=GST(u)
        local suffixes={"OffsetX","OffsetY","BarWidth","BarHeight","ShowSpellName","ShowIcon",
            "TextOffsetX","TextOffsetY","SpellNameFontSize","IconSize","TimeFontSize","Detached"}
        for _,s in ipairs(suffixes) do snap[pre..s]=g[pre..s] end
        if stk then snap[stk]=g[stk] end
        local wk = WidthSourceDBKey(u); if wk then snap[wk]=g[wk] end
    end
    return snap
end
local function RestoreCast(snap)
    if not snap then return end; local g=EG(); if not g then return end
    for k,v in pairs(snap) do g[k]=v end
end

local function Sync()
    if not pf or not pf.unit then return end; local g=G(); local u=pf.unit
    pf._castSnap = SnapshotCast(u)
    local function S(b,v) if b and b.SetText then b:SetText(tostring(v or 0)) end end
    local function SC(c,v) if c and c.SetChecked then c:SetChecked(v and true or false) end end
    local lbl=(u=="player" and "Player") or (u=="target" and "Target") or (u=="focus" and "Focus") or (u=="boss" and "Boss") or u
    if pf._titleFS then pf._titleFS:SetText(Tr(lbl) .. " " .. Tr("Castbar")) end
    if u=="boss" then
        S(pf.xBox,floor((g.bossCastbarOffsetX or 0)+0.5)); S(pf.yBox,floor((g.bossCastbarOffsetY or 0)+0.5))
        local widthValue = g.bossCastbarWidth or 176
        if NormalizeWidthSource(g[WidthSourceDBKey(u) or ""]) then
            widthValue = GetEffectiveWidth(g, u)
        end
        S(pf.wBox,floor((widthValue or 176)+0.5)); S(pf.hBox,floor((g.bossCastbarHeight or 12)+0.5))
        SC(pf.spellShowCB,g.showBossCastName~=false); SC(pf.iconShowCB,g.showBossCastIcon~=false); SC(pf.timeShowCB,g.showBossCastTime~=false)
        S(pf.spellXBox,g.bossCastTextOffsetX or 0); S(pf.spellYBox,g.bossCastTextOffsetY or 0)
        S(pf.spellSizeBox,g.bossCastSpellNameFontSize or g.fontSize or 14)
        S(pf.iconSizeBox,g.bossCastIconSize or g.bossCastbarHeight or 18)
        S(pf.timeSizeBox,g.bossCastTimeFontSize or g.fontSize or 14)
    else
        local pre=GP(u); if not pre then return end; local dx,dy=GD(u)
        S(pf.xBox,floor((g[pre.."OffsetX"] or dx)+0.5)); S(pf.yBox,floor((g[pre.."OffsetY"] or dy)+0.5))
        local widthValue = g[pre.."BarWidth"] or g.castbarGlobalWidth or 271
        if NormalizeWidthSource(g[WidthSourceDBKey(u) or ""]) then
            widthValue = GetEffectiveWidth(g, u)
        end
        S(pf.wBox,floor((widthValue or 271)+0.5)); S(pf.hBox,floor((g[pre.."BarHeight"] or g.castbarGlobalHeight or 18)+0.5))
        SC(pf.spellShowCB,g[pre.."ShowSpellName"]~=false); SC(pf.iconShowCB,g[pre.."ShowIcon"]~=false)
        local stk=GST(u); SC(pf.timeShowCB,stk and g[stk]~=false)
        S(pf.spellXBox,g[pre.."TextOffsetX"] or 0); S(pf.spellYBox,g[pre.."TextOffsetY"] or 0)
        S(pf.spellSizeBox,g[pre.."SpellNameFontSize"] or g.fontSize or 14)
        S(pf.iconSizeBox,g[pre.."IconSize"] or g[pre.."BarHeight"] or 18)
        S(pf.timeSizeBox,g[pre.."TimeFontSize"] or g.fontSize or 14)
    end
    -- Anchor to unitframe checkbox
    if pf.anchorToUnitCB then
        local detachedKey
        if u == "boss" then
            detachedKey = "bossCastbarDetached"
        else
            local pre2 = GP(u)
            if pre2 then detachedKey = pre2 .. "Detached" end
        end
        local isDetached = detachedKey and g[detachedKey] == true
        SC(pf.anchorToUnitCB, not isDetached)
    end
    RefreshWidthSourceControls(g, u, true)
    -- Refresh dependent gray-out state
    if pf.spellShowCB and pf.spellShowCB.UpdateDependents then pf.spellShowCB:UpdateDependents() end
    if pf.iconShowCB and pf.iconShowCB.UpdateDependents then pf.iconShowCB:UpdateDependents() end
    if pf.timeShowCB and pf.timeShowCB.UpdateDependents then pf.timeShowCB:UpdateDependents() end
end

local function Build()
    if pf then return pf end
    pf = F.Panel("MSUF_EM2_CastPopup", 380, 460, "Castbar")
    local top=pf._contentTop

    local fC,fB = F.Card(pf, top, "Position & Size", -2, true)
    pf._sizeCard = fC
    local fXY = F.PairRow(pf, fB, fC, { label1="X:", label2="Y:", key1="xBox", key2="yBox", onChanged=Apply })
    local fWH = F.PairRow(pf, fB, fC, { label1="W:", label2="H:", key1="wBox", key2="hBox", anchorTo=fXY, onChanged=Apply })
    pf.widthSourceRow = F.SelectRow(pf, fB, fC, {
        label = "Width source:",
        selectKey = "widthSourceDrop",
        stateKey = "widthSource",
        anchorTo = fWH,
        width = 178,
        menuWidth = 210,
        items = WidthSourceItems,
        onChanged = ApplyWidthSource,
    })
    fC:RecalcHeight()

    local sC,sB = F.Card(pf, fC, "Spell Name", -6, true)
    local sSh = F.CheckRow(pf, sB, sC, { label="Show", cbKey="spellShowCB", onChanged=function() Apply() end })
    local sXY = F.PairRow(pf, sB, sC, { label1="X:", label2="Y:", key1="spellXBox", key2="spellYBox", anchorTo=sSh, onChanged=Apply })
    local sSz = F.SingleRow(pf, sB, sC, { label="Size:", boxKey="spellSizeBox", anchorTo=sXY, onChanged=Apply })
    sC:RecalcHeight()
    pf.spellShowCB:SetDependentRows(sXY, sSz)

    local iC,iB = F.Card(pf, sC, "Icon", -6, true)
    local iSh = F.CheckRow(pf, iB, iC, { label="Show", cbKey="iconShowCB", onChanged=function() Apply() end })
    local iSz = F.SingleRow(pf, iB, iC, { label="Size:", boxKey="iconSizeBox", anchorTo=iSh, onChanged=Apply })
    iC:RecalcHeight()
    pf.iconShowCB:SetDependentRows(iSz)

    local tC,tB = F.Card(pf, iC, "Duration", -6, true)
    local tSh = F.CheckRow(pf, tB, tC, { label="Show", cbKey="timeShowCB", onChanged=function() Apply() end })
    local tSz = F.SingleRow(pf, tB, tC, { label="Size:", boxKey="timeSizeBox", anchorTo=tSh, onChanged=Apply })
    tC:RecalcHeight()
    pf.timeShowCB:SetDependentRows(tSz)

    -- Castbar anchor toggle
    local aC,aB = F.Card(pf, tC, "Anchor", -6, true)
    local aAnch = F.CheckRow(pf, aB, aC, { label="Anchor to unitframe", cbKey="anchorToUnitCB", onChanged=function()
        if not pf or not pf.unit then return end
        local anchored = pf.anchorToUnitCB and pf.anchorToUnitCB:GetChecked() and true or false
        local fn = _G.MSUF_EM_SetCastbarAnchoredToUnit
        if type(fn) == "function" then
            fn(pf.unit, anchored)
        end
        Apply()
    end })
    aC:RecalcHeight()

    pf._recalcScroll = function()
        C_Timer.After(0, function()
            local t=pf._scrollChild and pf._scrollChild:GetTop(); local b=pf._lastCard and pf._lastCard.GetBottom and pf._lastCard:GetBottom()
            if t and b then pf:UpdateScrollHeight(t-b+30) else pf:UpdateScrollHeight(540) end
        end)
    end

    -- Copy castbar settings (all except X/Y position)
    local CAST_SOURCES = {
        { key = "player", label = "Player" },
        { key = "target", label = "Target" },
        { key = "focus",  label = "Focus"  },
        { key = "boss",   label = "Boss"   },
    }
    -- Keys to copy (semantic) → per-unit reader/writer
    local function ReadCastbarSettings(u)
        local g = G(); if not g then return nil end
        local r = {}
        if u == "boss" then
            r.w = g.bossCastbarWidth; r.h = g.bossCastbarHeight
            local wk = WidthSourceDBKey(u); r.widthSource = wk and g[wk]
            r.showSpell = g.showBossCastName; r.showIcon = g.showBossCastIcon; r.showTime = g.showBossCastTime
            r.textX = g.bossCastTextOffsetX; r.textY = g.bossCastTextOffsetY
            r.spellSize = g.bossCastSpellNameFontSize; r.iconSize = g.bossCastIconSize; r.timeSize = g.bossCastTimeFontSize
        else
            local pre = GP(u); if not pre then return nil end
            r.w = g[pre.."BarWidth"]; r.h = g[pre.."BarHeight"]
            local wk = WidthSourceDBKey(u); r.widthSource = wk and g[wk]
            r.showSpell = g[pre.."ShowSpellName"]; r.showIcon = g[pre.."ShowIcon"]
            local stk = GST(u); r.showTime = stk and g[stk]
            r.textX = g[pre.."TextOffsetX"]; r.textY = g[pre.."TextOffsetY"]
            r.spellSize = g[pre.."SpellNameFontSize"]; r.iconSize = g[pre.."IconSize"]; r.timeSize = g[pre.."TimeFontSize"]
        end
        return r
    end
    local function WriteCastbarSettings(u, r)
        local g = EG(); if not g or not r then return end
        if u == "boss" then
            g.bossCastbarWidth = r.w; g.bossCastbarHeight = r.h
            local wk = WidthSourceDBKey(u); if wk then g[wk] = NormalizeWidthSource(r.widthSource) end
            g.showBossCastName = r.showSpell; g.showBossCastIcon = r.showIcon; g.showBossCastTime = r.showTime
            g.bossCastTextOffsetX = r.textX; g.bossCastTextOffsetY = r.textY
            g.bossCastSpellNameFontSize = r.spellSize; g.bossCastIconSize = r.iconSize; g.bossCastTimeFontSize = r.timeSize
        else
            local pre = GP(u); if not pre then return end
            g[pre.."BarWidth"] = r.w; g[pre.."BarHeight"] = r.h
            local wk = WidthSourceDBKey(u); if wk then g[wk] = NormalizeWidthSource(r.widthSource) end
            g[pre.."ShowSpellName"] = r.showSpell; g[pre.."ShowIcon"] = r.showIcon
            local stk = GST(u); if stk then g[stk] = r.showTime end
            g[pre.."TextOffsetX"] = r.textX; g[pre.."TextOffsetY"] = r.textY
            g[pre.."SpellNameFontSize"] = r.spellSize; g[pre.."IconSize"] = r.iconSize; g[pre.."TimeFontSize"] = r.timeSize
        end
    end

    local copyRow = F.CopyDropdown(pf, pf._scrollChild, nil, {
        anchorTo = aC,
        sources = CAST_SOURCES,
        onCopy = function(targetKey)
            local r = ReadCastbarSettings(pf.unit)
            if not r or not targetKey then return end
            if _G.MSUF_EM_UndoBeforeChange then _G.MSUF_EM_UndoBeforeChange("castbar", targetKey) end
            WriteCastbarSettings(targetKey, r)
            if _G.MSUF_UpdateCastbarVisuals then _G.MSUF_UpdateCastbarVisuals() end
            ApplyAllSettingsSafe()
            RefreshUFPreview("EM2_CASTBAR_POPUP_COPY", targetKey)
            C_Timer.After(0.1, function() Sync() end)
        end,
    })
    pf._lastCard = copyRow or aC

    local ok,cancel = F.FooterButtons(pf)
    ok:SetScript("OnClick", function() Apply(); pf:Hide() end)
    cancel:SetScript("OnClick", function()
        RestoreCast(pf._castSnap)
        if type(_G.MSUF_UpdateCastbarVisuals)=="function" then _G.MSUF_UpdateCastbarVisuals() end
        ApplyAllSettingsSafe()
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        RefreshUFPreview("EM2_CASTBAR_POPUP_CANCEL", pf and pf.unit)
        pf:Hide()
    end)
    pf:EnableKeyboard(true)
    pf:SetScript("OnKeyDown", function(s,k) if k=="ESCAPE" then s:SetPropagateKeyboardInput(false); cancel:Click() else s:SetPropagateKeyboardInput(true) end end)
    pf:UpdateScrollHeight(500)
    return pf
end

local CastPopup = {}; EM2.CastPopup = CastPopup
function CastPopup.Open(u, parent) if BlockConfigCombatLocked() then return false end; Build(); pf.unit=u; pf.parent=parent; Sync(); pf:Show(); SetTest(u, true)
    pf:SetScript("OnHide", function()
        if pf.unit and not _G.MSUF_UnitPreviewActive then SetTest(pf.unit, false) end
    end); return true end
function CastPopup.Close() if pf then
    if pf.unit and not _G.MSUF_UnitPreviewActive then SetTest(pf.unit, false) end
    pf:Hide() end end
function CastPopup.IsOpen() return pf and pf:IsShown() or false end
function CastPopup.Sync() if pf and pf:IsShown() then Sync() end end

-- MSUF_EM2_Popup_Aura.lua

local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 or not EM2.PopupFactory then return end
local F = EM2.PopupFactory
local floor = math.floor
local max, min = math.max, math.min
local function A2() local db=_G.MSUF_DB; return db and db.auras2 end
local function Sh() local a=A2(); return a and a.shared or {} end
local function Lay(k) local a=A2(); if not a then return {} end; a.perUnit=a.perUnit or {}; a.perUnit[k]=a.perUnit[k] or {}; a.perUnit[k].layout=a.perUnit[k].layout or {}; return a.perUnit[k].layout end
local function San(v,d) v=tonumber(v) or d or 0; if v~=v or v>2000 or v<-2000 then v=d or 0 end; return floor(v+0.5) end
local function IsBoss(u) return type(u)=="string" and u:match("^boss%d+$") end
local pf

local function SetPopupObjectEnabled(obj, enabled)
    if not obj then return end
    enabled=enabled and true or false
    if obj.EnableMouse then obj:EnableMouse(enabled) end
    if obj.SetEnabled then
        obj:SetEnabled(enabled)
    elseif obj.Enable and obj.Disable then
        if enabled then obj:Enable() else obj:Disable() end
    end
    if obj.SetAlpha then obj:SetAlpha(enabled and 1 or 0.35) end
end
local function SetPopupKeyEnabled(key, enabled)
    if not (pf and key) then return end
    SetPopupObjectEnabled(pf[key], enabled)
    SetPopupObjectEnabled(pf[key.."Minus"], enabled)
    SetPopupObjectEnabled(pf[key.."Plus"], enabled)
    SetPopupObjectEnabled(pf[key.."Label"], enabled)
end
local function SetPopupRowEnabled(row, enabled)
    SetPopupObjectEnabled(row, enabled)
    if not (row and row.GetChildren) then return end
    local kids={row:GetChildren()}
    for i=1,#kids do SetPopupObjectEnabled(kids[i], enabled) end
end
local function ApplyNativePopupState()
    if not (pf and pf.unit) then return end
    local rows=pf._auraCustomTextRows
    if rows then for i=1,#rows do SetPopupRowEnabled(rows[i], true) end end
    SetPopupKeyEnabled("stSzBox", true)
    SetPopupKeyEnabled("stXBox", true)
    SetPopupKeyEnabled("stYBox", true)
    SetPopupKeyEnabled("cdSzBox", true)
    SetPopupKeyEnabled("cdXBox", true)
    SetPopupKeyEnabled("cdYBox", true)
    if pf._auraNativeHint then
        pf._auraNativeHint:Hide()
    end
end

local function Apply()
    if BlockConfigCombatLocked() then return end
    if not pf or not pf.unit then return end; local a2=A2(); if not a2 then return end
    a2.shared=a2.shared or {}; a2.perUnit=a2.perUnit or {}; local uk=pf.unit
    if type(_G.MSUF_EM_UndoBeforeChange)=="function" then _G.MSUF_EM_UndoBeforeChange("aura", uk) end
    local boss=IsBoss(uk)
    if boss and pf.bossTogetherCB then a2.shared.bossEditTogether=pf.bossTogetherCB:GetChecked() and true or false end
    local keys=(boss and a2.shared.bossEditTogether~=false) and {"boss1","boss2","boss3","boss4","boss5"} or {uk}
    local function R(b,fb) return San(b and tonumber(b:GetText()),fb) end
    local sp=max(0,min(30,R(pf.spacingBox,2)))
    local stSz=max(6,min(40,R(pf.stSzBox,14))); local stX=R(pf.stXBox,0); local stY=R(pf.stYBox,0)
    local cdSz=max(6,min(40,R(pf.cdSzBox,14))); local cdX=R(pf.cdXBox,0); local cdY=R(pf.cdYBox,0)
    local bX=R(pf.bXBox,0); local bY=R(pf.bYBox,0); local bSz=max(10,min(80,R(pf.bSzBox,26)))
    local dX=R(pf.dXBox,0); local dY=R(pf.dYBox,0); local dSz=max(10,min(80,R(pf.dSzBox,26)))
    local prX=R(pf.prXBox,0); local prY=R(pf.prYBox,0); local prSz=max(10,min(80,R(pf.prSzBox,26)))
    if pf.prPreviewCB then a2.shared.highlightPrivateAuras=pf.prPreviewCB:GetChecked() and true or false end
    for _,k in ipairs(keys) do
        a2.perUnit[k]=a2.perUnit[k] or {}; local uc=a2.perUnit[k]; uc.layout=uc.layout or {}; uc.overrideLayout=true; local l=uc.layout
        l.spacing=sp; l.stackTextSize=stSz; l.stackTextOffsetX=stX; l.stackTextOffsetY=stY
        l.cooldownTextSize=cdSz; l.cooldownTextOffsetX=cdX; l.cooldownTextOffsetY=cdY
        l.buffGroupOffsetX=bX; l.buffGroupOffsetY=bY; l.buffGroupIconSize=bSz
        l.debuffGroupOffsetX=dX; l.debuffGroupOffsetY=dY; l.debuffGroupIconSize=dSz
        l.privateOffsetX=prX; l.privateOffsetY=prY; l.privateSize=prSz; l.width=nil; l.height=nil
    end
    if type(_G.MSUF_Auras2_RefreshUnit)=="function" then for _,k in ipairs(keys) do _G.MSUF_Auras2_RefreshUnit(k) end
    elseif type(_G.MSUF_Auras2_RefreshAll)=="function" then _G.MSUF_Auras2_RefreshAll() end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
end

local SHARED_SNAP_KEYS = {"bossEditTogether","highlightPrivateAuras"}
local LAYOUT_KEYS = {
    "spacing","stackTextSize","stackTextOffsetX","stackTextOffsetY",
    "cooldownTextSize","cooldownTextOffsetX","cooldownTextOffsetY",
    "buffGroupOffsetX","buffGroupOffsetY","buffGroupIconSize",
    "debuffGroupOffsetX","debuffGroupOffsetY","debuffGroupIconSize",
    "privateOffsetX","privateOffsetY","privateSize",
}
local function SnapshotAura(uk)
    local a2=A2(); if not a2 then return nil end; local snap={shared={},units={}}
    local sh=a2.shared or {}
    for _,k in ipairs(SHARED_SNAP_KEYS) do snap.shared[k]=sh[k] end
    local boss=IsBoss(uk)
    local keys=(boss and sh.bossEditTogether~=false) and {"boss1","boss2","boss3","boss4","boss5"} or {uk}
    for _,k in ipairs(keys) do
        snap.units[k]={}
        local pu=a2.perUnit and a2.perUnit[k]; local l=pu and pu.layout or {}
        for _,lk in ipairs(LAYOUT_KEYS) do snap.units[k][lk]=l[lk] end
        snap.units[k]._overrideLayout=pu and pu.overrideLayout
    end
    return snap
end
local function RestoreAura(snap)
    if not snap then return end; local a2=A2(); if not a2 then return end
    a2.shared=a2.shared or {}
    for k,v in pairs(snap.shared) do a2.shared[k]=v end
    a2.perUnit=a2.perUnit or {}
    for uk,vals in pairs(snap.units) do
        a2.perUnit[uk]=a2.perUnit[uk] or {}; local pu=a2.perUnit[uk]
        pu.overrideLayout=vals._overrideLayout; pu.layout=pu.layout or {}
        for _,lk in ipairs(LAYOUT_KEYS) do pu.layout[lk]=vals[lk] end
    end
end

local function Sync()
    if not pf or not pf.unit then return end; local sh=Sh(); local uk=pf.unit; local ek=uk
    pf._auraSnap = SnapshotAura(uk)
    if IsBoss(uk) and sh.bossEditTogether~=false then ek="boss1" end; local l=Lay(ek)
    local function V(lk,sk,d) return (l[lk]~=nil and l[lk]) or (sh[sk]~=nil and sh[sk]) or d end
    local function S(b,v) if b and b.SetText then b:SetText(tostring(v or 0)) end end
    local function SC(c,v) if c and c.SetChecked then c:SetChecked(v and true or false) end end
    local lbl=uk; if IsBoss(uk) then lbl="Boss "..(uk:match("%d+") or "1") end
    if pf._titleFS then pf._titleFS:SetText(Tr(lbl) .. " " .. Tr("Auras")) end
    S(pf.spacingBox,V("spacing","spacing",2))
    S(pf.stSzBox,V("stackTextSize","stackTextSize",14)); S(pf.stXBox,V("stackTextOffsetX","stackTextOffsetX",0)); S(pf.stYBox,V("stackTextOffsetY","stackTextOffsetY",0))
    S(pf.cdSzBox,V("cooldownTextSize","cooldownTextSize",14)); S(pf.cdXBox,V("cooldownTextOffsetX","cooldownTextOffsetX",0)); S(pf.cdYBox,V("cooldownTextOffsetY","cooldownTextOffsetY",0))
    S(pf.bXBox,V("buffGroupOffsetX","buffGroupOffsetX",0)); S(pf.bYBox,V("buffGroupOffsetY","buffGroupOffsetY",0)); S(pf.bSzBox,V("buffGroupIconSize","buffGroupIconSize",26))
    S(pf.dXBox,V("debuffGroupOffsetX","debuffGroupOffsetX",0)); S(pf.dYBox,V("debuffGroupOffsetY","debuffGroupOffsetY",0)); S(pf.dSzBox,V("debuffGroupIconSize","debuffGroupIconSize",26))
    S(pf.prXBox,V("privateOffsetX","privateOffsetX",0)); S(pf.prYBox,V("privateOffsetY","privateOffsetY",0)); S(pf.prSzBox,V("privateSize","privateSize",26))
    SC(pf.prPreviewCB,sh.highlightPrivateAuras); SC(pf.bossTogetherCB,sh.bossEditTogether~=false)
    if pf._bossRow then pf._bossRow:SetShown(IsBoss(uk)) end
    ApplyNativePopupState()
end

local function Build()
    if pf then return pf end
    pf = F.Panel("MSUF_EM2_AuraPopup", 380, 520, "Auras")
    local top=pf._contentTop

    local fC,fB = F.Card(pf, top, "Layout", -2, true)
    local fSp = F.SingleRow(pf, fB, fC, { label="Spacing:", boxKey="spacingBox", onChanged=Apply })
    local fBoss = F.CheckRow(pf, fB, fC, { label="Boss 1-5 edit together", cbKey="bossTogetherCB", anchorTo=fSp, onChanged=function() Apply() end })
    pf._bossRow = fBoss; fC:RecalcHeight()

    local tC,tB = F.Card(pf, fC, "Text Overlays", -6, true)
    local tStSz = F.SingleRow(pf, tB, tC, { label="Stack size:", boxKey="stSzBox", onChanged=Apply })
    local tStXY = F.PairRow(pf, tB, tC, { label1="St X:", label2="St Y:", key1="stXBox", key2="stYBox", anchorTo=tStSz, onChanged=Apply })
    local tCdSz = F.SingleRow(pf, tB, tC, { label="CD size:", boxKey="cdSzBox", anchorTo=tStXY, yOff=-8, onChanged=Apply })
    local tCdXY = F.PairRow(pf, tB, tC, { label1="CD X:", label2="CD Y:", key1="cdXBox", key2="cdYBox", anchorTo=tCdSz, onChanged=Apply })
    pf._auraCustomTextRows = { tStSz, tStXY, tCdSz, tCdXY }
    local tHintRow = CreateFrame("Frame", nil, tB)
    tHintRow:SetHeight(26)
    tHintRow:SetPoint("TOPLEFT", tCdXY, "BOTTOMLEFT", 0, -4)
    tHintRow:SetPoint("RIGHT", tB, "RIGHT", 0, 0)
    local tHint = tHintRow:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    tHint:SetPoint("LEFT", tHintRow, "LEFT", 0, 0)
    tHint:SetPoint("RIGHT", tHintRow, "RIGHT", -4, 0)
    tHint:SetJustifyH("LEFT")
    tHint:SetText(Tr("Blizzard renders cooldown/stack text for native Buffs and Debuffs. These text overlay fields only affect custom icons."))
    tHint:Hide()
    pf._auraNativeHint = tHint
    tC._rowCount = tC._rowCount + 1
    tC._rows[tC._rowCount] = tHintRow
    tC:RecalcHeight()

    local bC,bB = F.Card(pf, tC, "Buffs", -6, true)
    local bXY = F.PairRow(pf, bB, bC, { label1="X:", label2="Y:", key1="bXBox", key2="bYBox", onChanged=Apply })
    local bSz = F.SingleRow(pf, bB, bC, { label="Icon size:", boxKey="bSzBox", anchorTo=bXY, onChanged=Apply })
    bC:RecalcHeight()

    local dC,dB = F.Card(pf, bC, "Debuffs", -6, true)
    local dXY = F.PairRow(pf, dB, dC, { label1="X:", label2="Y:", key1="dXBox", key2="dYBox", onChanged=Apply })
    local dSz = F.SingleRow(pf, dB, dC, { label="Icon size:", boxKey="dSzBox", anchorTo=dXY, onChanged=Apply })
    dC:RecalcHeight()

    local prC,prB = F.Card(pf, dC, "Private Auras", -6, true)
    local prPv = F.CheckRow(pf, prB, prC, { label="Preview (highlight)", cbKey="prPreviewCB", onChanged=function() Apply() end })
    local prXY = F.PairRow(pf, prB, prC, { label1="X:", label2="Y:", key1="prXBox", key2="prYBox", anchorTo=prPv, onChanged=Apply })
    local prSz = F.SingleRow(pf, prB, prC, { label="Icon size:", boxKey="prSzBox", anchorTo=prXY, onChanged=Apply })
    prC:RecalcHeight()

    pf._recalcScroll = function()
        C_Timer.After(0, function()
            local t=pf._scrollChild and pf._scrollChild:GetTop(); local b=prC and prC.GetBottom and prC:GetBottom()
            if t and b then pf:UpdateScrollHeight(t-b+20) else pf:UpdateScrollHeight(700) end
        end)
    end

    local ok,cancel = F.FooterButtons(pf)
    ok:SetScript("OnClick", function() Apply(); pf:Hide() end)
    cancel:SetScript("OnClick", function()
        RestoreAura(pf._auraSnap)
        if type(_G.MSUF_Auras2_RefreshAll)=="function" then _G.MSUF_Auras2_RefreshAll() end
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        pf:Hide()
    end)
    pf:EnableKeyboard(true)
    pf:SetScript("OnKeyDown", function(s,k) if k=="ESCAPE" then s:SetPropagateKeyboardInput(false); cancel:Click() else s:SetPropagateKeyboardInput(true) end end)
    pf:UpdateScrollHeight(700)
    return pf
end

local AuraPopup = {}; EM2.AuraPopup = AuraPopup
function AuraPopup.Open(u, parent) if BlockConfigCombatLocked() then return false end; Build(); pf.unit=u; pf.parent=parent; Sync(); pf:Show(); return true end
function AuraPopup.Close() if pf then pf:Hide() end end
function AuraPopup.IsOpen() return pf and pf:IsShown() or false end
function AuraPopup.Sync() if pf and pf:IsShown() then Sync() end end
