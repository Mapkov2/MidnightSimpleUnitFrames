-- ============================================================================
-- MSUF_EM2_PopupFactory.lua  v5 — MSUF Options Menu Match
-- ALL sections collapsible (chevron = collapse only).
-- Show/Hide toggles are inside card body, not in header.
-- Chevron: gold closed ▸, orange open ▾ (matches Options exactly).
-- ============================================================================
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

-- =========================================================================
-- Panel
-- =========================================================================
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
    pf:SetScript("OnDragStart", function(s) if not InCombatLockdown() then s:StartMoving() end end)
    pf:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)

    local titleFS = FS(pf, 15, C.title)
    titleFS:SetPoint("LEFT", pf, "TOPLEFT", PAD, -TITLE_H / 2)
    titleFS:SetText(title or "Edit"); pf._titleFS = titleFS

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
    end)
    pf._scrollFrame = sf

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(width); sc:SetHeight(1); sf:SetScrollChild(sc)
    pf._scrollChild = sc

    local anchor = sc:CreateFontString(nil, "OVERLAY")
    anchor:SetFont(FONT, 1, ""); anchor:SetText("")
    anchor:SetPoint("TOPLEFT", sc, "TOPLEFT", PAD, -6)
    pf._contentTop = anchor

    function pf:UpdateScrollHeight(h) sc:SetHeight(max(1, h + 20)) end
    pf.__msufEditPopupRoot = true; pf:Hide()
    return pf
end

-- =========================================================================
-- Card: collapsible section (matches MakeCollapsibleSection in Options)
-- =========================================================================
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
    title:SetText(text or "")

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
            hint:SetText("click to expand")
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

-- =========================================================================
-- Stepper + EditBox helpers
-- =========================================================================
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

-- =========================================================================
-- PairRow: "X:  [–][val][+]    Y:  [–][val][+]"
-- =========================================================================
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

    local l1 = FS(row, 11, C.muted); l1:SetPoint("LEFT", 0, 0); l1:SetText(l1t)
    local m1 = MakeStep(row, "-"); m1:SetPoint("LEFT", l1, "RIGHT", 4, 0)
    local b1 = MakeBox(row); b1:SetPoint("LEFT", m1, "RIGHT", 1)
    local p1 = MakeStep(row, "+"); p1:SetPoint("LEFT", b1, "RIGHT", 1)
    WireStepper(m1, b1, p1, cb)

    local l2 = FS(row, 11, C.muted); l2:SetPoint("LEFT", p1, "RIGHT", 10, 0); l2:SetText(l2t)
    local m2 = MakeStep(row, "-"); m2:SetPoint("LEFT", l2, "RIGHT", 4, 0)
    local b2 = MakeBox(row); b2:SetPoint("LEFT", m2, "RIGHT", 1)
    local p2 = MakeStep(row, "+"); p2:SetPoint("LEFT", b2, "RIGHT", 1)
    WireStepper(m2, b2, p2, cb)

    if k1 then pf[k1]=b1; pf[k1.."Minus"]=m1; pf[k1.."Plus"]=p1; pf[k1.."Label"]=l1 end
    if k2 then pf[k2]=b2; pf[k2.."Minus"]=m2; pf[k2.."Plus"]=p2; pf[k2.."Label"]=l2 end

    card._rowCount = card._rowCount + 1; card._rows[card._rowCount] = row
    return row
end

-- =========================================================================
-- SingleRow: "Label:  [–][val][+]"
-- =========================================================================
function Factory.SingleRow(pf, body, card, opts)
    local boxKey = opts.boxKey; local cb = opts.onChanged; local anchorTo = opts.anchorTo

    local row = CreateFrame("Frame", nil, body)
    row:SetHeight(ROW_H)
    if anchorTo then row:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, (opts.yOff or -ROW_GAP))
    else row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0) end
    row:SetPoint("RIGHT", body, "RIGHT", 0, 0)

    local label = FS(row, 11, C.muted)
    label:SetPoint("LEFT", 0, 0); label:SetText(opts.label or "Value:")

    local m = MakeStep(row, "-"); m:SetPoint("LEFT", label, "RIGHT", 6, 0)
    local box = MakeBox(row); box:SetPoint("LEFT", m, "RIGHT", 1)
    local p = MakeStep(row, "+"); p:SetPoint("LEFT", box, "RIGHT", 1)
    WireStepper(m, box, p, cb)

    if boxKey then pf[boxKey]=box; pf[boxKey.."Minus"]=m; pf[boxKey.."Plus"]=p; pf[boxKey.."Label"]=label end
    card._rowCount = card._rowCount + 1; card._rows[card._rowCount] = row
    return row
end

-- =========================================================================
-- SizeAnchorRow: "Size: [–][val][+]   [ Anchor ▸ ]"
-- =========================================================================
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

    local sl = FS(row, 11, C.muted); sl:SetPoint("LEFT", 0, 0); sl:SetText("Size:")
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
        for _,o in ipairs(options) do if o[1]==k then dFS:SetText(o[2]); return end end; dFS:SetText(tostring(k)) end
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

-- =========================================================================
-- CheckRow
-- =========================================================================
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
    lbl:SetPoint("LEFT", chk, "RIGHT", 8, 0); lbl:SetText(opts.label or "")
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

-- =========================================================================
-- FooterButtons
-- =========================================================================
function Factory.FooterButtons(pf)
    local function MakeBtn(text, w)
        local b = CreateFrame("Button", nil, pf); b:SetSize(w or 80, 28)
        local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(unpack(C.btnBg))
        local brd = CreateFrame("Frame", nil, b, "BackdropTemplate"); brd:SetAllPoints()
        brd:SetFrameLevel(max(0, b:GetFrameLevel()-1))
        brd:SetBackdrop({edgeFile=W8, edgeSize=1}); brd:SetBackdropBorderColor(unpack(C.btnEdge))
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(unpack(C.btnHover))
        local fs = FS(b, 12, C.white); fs:SetPoint("CENTER"); fs:SetText(text)
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
    label:SetText("Copy To")

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
    btnText:SetText("Select...")

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
        itemFS:SetText(src.label or src.key)

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
            btnText:SetText(src.label or src.key)
            if opts.onCopy then opts.onCopy(src.key) end
            C_Timer.After(1.5, function() btnText:SetText("Select...") end)
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
