-- ============================================================================
-- MSUF_EM2_HUD.lua — Edit Mode HUD (two-row, polished)
-- ============================================================================
local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local HUD = {}; EM2.HUD = HUD

local L     = (ns and ns.L) or _G.MSUF_L or setmetatable({}, { __index = function(_, k) return k end })
local FONT  = STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF"
local W8    = "Interface/Buttons/WHITE8X8"
local floor, max, min = math.floor, math.max, math.min

local hudFrame, row2Frame
local previewBtn, auraBtn, snapToggle, cdmBtn, anchorBtn
local undoBtn, redoBtn, cancelAllBtn, exitBtn
local alphaFS, stepFS
local helpBtn, tutorialPanel, tourState
local bgWidget, gridWidget

local R1_H    = 42
local R2_H    = 34
local BTN_H   = 32
local BTN_H2  = 26
local BTN_GAP = 5
local SEP_W   = 16

local TH = {
    r1Bg   = { 0.045, 0.05, 0.07, 0.95 },
    r2Bg   = { 0.035, 0.04, 0.06, 0.90 },
    edge   = { 0.20, 0.22, 0.28, 0.45 },
    titleR=0.50, titleG=0.53, titleB=0.60,
    textR=0.72, textG=0.74, textB=0.80,
    mutedR=0.52, mutedG=0.54, mutedB=0.60,
    onR=0.38, onG=0.65, onB=1.00,
    offR=0.40, offG=0.42, offB=0.50,
    exitR=0.90, exitG=0.32, exitB=0.32,
}

local function MakeFS(p, sz, r, g, b, a)
    local fs = p:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, sz or 12, ""); fs:SetShadowOffset(1, -1)
    fs:SetTextColor(r or 1, g or 1, b or 1, a or 1); return fs
end

local function SetActive(btn, on)
    if not btn or not btn._label then return end
    if on then
        btn._label:SetTextColor(TH.onR, TH.onG, TH.onB, 1)
        if btn._dot then btn._dot:Show() end
    else
        btn._label:SetTextColor(TH.offR, TH.offG, TH.offB, 0.85)
        if btn._dot then btn._dot:Hide() end
    end
end

local function SetTip(widget, text)
    if not widget or not text then return end
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -6)
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function MakeBtn(parent, text, w, h, fontSize, onClick)
    local btn = CreateFrame("Button", nil, parent)
    w = w or (#text * 8 + 18); h = h or BTN_H
    btn:SetSize(w, h)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.05)
    local label = MakeFS(btn, fontSize or 12, TH.textR, TH.textG, TH.textB, 0.92)
    label:SetPoint("CENTER"); label:SetText(text)
    btn._label = label
    local dot = btn:CreateTexture(nil, "OVERLAY")
    dot:SetSize(w - 8, 2); dot:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2)
    dot:SetColorTexture(TH.onR, TH.onG, TH.onB, 0.90); dot:Hide()
    btn._dot = dot
    if onClick then btn:SetScript("OnClick", onClick) end
    return btn
end

local function MakeSep(parent, h)
    local s = parent:CreateTexture(nil, "OVERLAY")
    s:SetSize(1, (h or BTN_H) - 8); s:SetColorTexture(0.35, 0.38, 0.45, 0.28)
    return s
end

local function LayoutCenter(anchor, items, gap, sepW)
    local totalW = 0
    for i, b in ipairs(items) do
        totalW = totalW + (b._isSep and sepW or b:GetWidth())
        if i < #items then totalW = totalW + gap end
    end
    local x = -totalW / 2
    for _, b in ipairs(items) do
        local w = b._isSep and sepW or b:GetWidth()
        b:SetPoint("LEFT", anchor, "CENTER", b._isSep and (x + w/2) or x, 0)
        x = x + w + gap
    end
end

-- =========================================================================
-- Localization: EN defaults (translators override via ns.AddLocale)
-- =========================================================================
do
    local raw = L
    if raw["EM_HELP_DRAG"] == "EM_HELP_DRAG" then
        raw["EM_HELP_DRAG"]    = "Left-click and drag any mover overlay to reposition a frame. Hold |cff60a5ffShift|r while dragging to ignore snap and move freely."
        raw["EM_HELP_NUDGE"]   = "Use arrow keys to nudge the selected frame by 1 pixel. |cff60a5ffShift|r = 5 px, |cff60a5ffCtrl|r = 10 px, |cff60a5ffAlt|r = grid step."
        raw["EM_HELP_POPUP"]   = "Left-click any mover to open its settings popup — fine-tune X/Y position, size, text anchors, and per-unit overrides."
        raw["EM_HELP_SNAP"]    = "Toggle |cff60a5ffSnap|r in the HUD toolbar. Scroll over |cff60a5ffGrid ##px|r to change step size. Frames snap to edges of other frames while dragging."
        raw["EM_HELP_OPACITY"] = "Scroll over |cff60a5ffBG ##%|r to darken the game world. Makes it easier to see frame positions and alignment."
        raw["EM_HELP_PREVIEW"] = "|cff60a5ffPreview|r fills empty unitframes with placeholder data (health, power, names). |cff60a5ffAuras|r shows aura icons and lets you reposition aura groups."
        raw["EM_HELP_UNDO"]    = "|cff60a5ffUndo|r / |cff60a5ffRedo|r track every position change. |cff60a5ffCancel All|r reverts everything to the state before Edit Mode was opened."
        raw["EM_HELP_CDM"]     = "|cff60a5ffCDM|r anchors all unitframes to the Essential Cooldown Manager. |cff60a5ffAnchor|r lets you pick any visible frame as a global anchor point."
        raw["EM_HELP_COPYTO"]  = "Inside a popup, use |cff60a5ffCopy Settings|r to copy the current frame's size, text, and layout to another unit — without copying position."
        raw["EM_HELP_EXIT"]    = "|cff60a5ffExit|r saves all changes and locks positions. You can also press |cff60a5ffEsc|r to leave Edit Mode."
        raw["EM_HELP_TITLE"]   = "Edit Mode — Quick Reference"
        raw["EM_TOUR_START"]   = "Start Guided Tour"
        raw["EM_TOUR_NEXT"]    = "Next"
        raw["EM_TOUR_BACK"]    = "Back"
        raw["EM_TOUR_SKIP"]    = "Skip"
        raw["EM_TOUR_DONE"]    = "Done"
        raw["EM_TOUR_STEP"]    = "Step %d of %d"
        raw["EM_HELP_BTN"]     = "? Help"
        raw["EM_HELP_BTN_TIP"] = "Quick reference and guided tour\nfor Edit Mode controls."
        raw["Drag & Move"]          = "Drag & Move"
        raw["Arrow Key Nudge"]      = "Arrow Key Nudge"
        raw["Click Popup"]          = "Click Popup"
        raw["Grid & Snap"]          = "Grid & Snap"
        raw["Background Opacity"]   = "Background Opacity"
        raw["Preview & Auras"]      = "Preview & Auras"
        raw["Undo / Cancel All"]    = "Undo / Cancel All"
        raw["CDM & Anchor"]         = "CDM & Anchor"
        raw["Copy Settings"]        = "Copy Settings"
        raw["Exit Edit Mode"]       = "Exit Edit Mode"
    end
end

-- =========================================================================
-- Tutorial / Help Reference Panel (lazy init)
-- =========================================================================
local HELP_SECTIONS = {
    { title = "Drag & Move",        body = "EM_HELP_DRAG" },
    { title = "Click Popup",        body = "EM_HELP_POPUP" },
    { title = "Arrow Key Nudge",    body = "EM_HELP_NUDGE" },
    { title = "Grid & Snap",        body = "EM_HELP_SNAP" },
    { title = "Background Opacity", body = "EM_HELP_OPACITY" },
    { title = "Preview & Auras",    body = "EM_HELP_PREVIEW" },
    { title = "CDM & Anchor",       body = "EM_HELP_CDM" },
    { title = "Copy Settings",      body = "EM_HELP_COPYTO" },
    { title = "Undo / Cancel All",  body = "EM_HELP_UNDO" },
    { title = "Exit Edit Mode",     body = "EM_HELP_EXIT" },
}

local PANEL_W     = 340
local PANEL_PAD   = 16
local SEC_GAP     = 6
local TITLE_SZ    = 12
local BODY_SZ     = 11
local BODY_W      = PANEL_W - PANEL_PAD * 2
local HEADER_H    = 36
local CLOSE_SZ    = 20

local function EnsureTutorialPanel()
    if tutorialPanel then return tutorialPanel end

    local p = CreateFrame("Frame", "MSUF_EM2_TutorialPanel", UIParent, "BackdropTemplate")
    p:SetFrameStrata("TOOLTIP"); p:SetFrameLevel(950)
    p:SetWidth(PANEL_W)
    p:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    p:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    p:SetBackdropColor(0.03, 0.05, 0.12, 0.97)
    p:SetBackdropBorderColor(0.10, 0.20, 0.45, 0.90)
    p:EnableMouse(true); p:Hide()

    p:EnableKeyboard(true)
    p:SetScript("OnKeyDown", function(self, k)
        if k == "ESCAPE" then
            self:SetPropagateKeyboardInput(false); self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    local hdr = MakeFS(p, 13, 0.75, 0.88, 1.00, 1)
    hdr:SetPoint("TOPLEFT", p, "TOPLEFT", PANEL_PAD, -12)
    hdr:SetText(L["EM_HELP_TITLE"])

    local closeBtn = CreateFrame("Button", nil, p)
    closeBtn:SetSize(CLOSE_SZ, CLOSE_SZ)
    closeBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, -8)
    local closeFS = MakeFS(closeBtn, 14, 0.55, 0.62, 0.78, 0.70)
    closeFS:SetPoint("CENTER"); closeFS:SetText("x")
    closeBtn:SetScript("OnEnter", function() closeFS:SetTextColor(1, 1, 1, 1) end)
    closeBtn:SetScript("OnLeave", function() closeFS:SetTextColor(0.55, 0.62, 0.78, 0.70) end)
    closeBtn:SetScript("OnClick", function() p:Hide() end)

    local y = -(HEADER_H)

    for i, sec in ipairs(HELP_SECTIONS) do
        if i > 1 then
            local div = p:CreateTexture(nil, "ARTWORK")
            div:SetSize(BODY_W, 1)
            div:SetPoint("TOPLEFT", p, "TOPLEFT", PANEL_PAD, y - SEC_GAP * 0.5)
            div:SetColorTexture(0.10, 0.20, 0.45, 0.25)
            y = y - SEC_GAP
        end

        local tFS = MakeFS(p, TITLE_SZ, 1.00, 0.82, 0.00, 1.00)
        tFS:SetPoint("TOPLEFT", p, "TOPLEFT", PANEL_PAD, y)
        tFS:SetText(L[sec.title])

        y = y - (TITLE_SZ + 4)

        local bFS = MakeFS(p, BODY_SZ, 0.78, 0.82, 0.90, 0.90)
        bFS:SetPoint("TOPLEFT", p, "TOPLEFT", PANEL_PAD, y)
        bFS:SetWidth(BODY_W); bFS:SetWordWrap(true); bFS:SetJustifyH("LEFT")
        bFS:SetText(L[sec.body])

        local bH = bFS:GetStringHeight() or 14
        y = y - bH - SEC_GAP
    end

    y = y - 4
    local tourBtn = CreateFrame("Button", nil, p, "BackdropTemplate")
    tourBtn:SetSize(BODY_W, 28)
    tourBtn:SetPoint("TOPLEFT", p, "TOPLEFT", PANEL_PAD, y)
    tourBtn:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1,
                          insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    tourBtn:SetBackdropColor(TH.onR * 0.25, TH.onG * 0.25, TH.onB * 0.25, 0.90)
    tourBtn:SetBackdropBorderColor(TH.onR, TH.onG, TH.onB, 0.50)
    local tbHL = tourBtn:CreateTexture(nil, "HIGHLIGHT")
    tbHL:SetAllPoints(); tbHL:SetColorTexture(TH.onR, TH.onG, TH.onB, 0.10)
    local tbFS = MakeFS(tourBtn, 12, TH.onR, TH.onG, TH.onB, 1)
    tbFS:SetPoint("CENTER"); tbFS:SetText(L["EM_TOUR_START"])
    tourBtn:SetScript("OnClick", function()
        p:Hide()
        HUD.StartTour()
    end)

    y = y - 28 - 4
    p:SetHeight(-y + PANEL_PAD * 0.5)

    tutorialPanel = p
    return p
end

-- =========================================================================
-- Phase 2: Guided Tour — spotlight mask + step cards
-- =========================================================================
local MASK_ALPHA = 0.65
local CARD_W     = 300
local CARD_PAD   = 14
local SPOT_PAD   = 6

local function GetTourSteps()
    return {
        {
            title  = L["Drag & Move"],
            body   = L["EM_HELP_DRAG"],
            anchor = "CENTER",
        },
        {
            target = function() return previewBtn end,
            title  = L["Preview & Auras"],
            body   = L["EM_HELP_PREVIEW"],
            anchor = "BOTTOM",
        },
        {
            title  = L["Click Popup"],
            body   = L["EM_HELP_POPUP"],
            anchor = "CENTER",
        },
        {
            title  = L["Arrow Key Nudge"],
            body   = L["EM_HELP_NUDGE"],
            anchor = "CENTER",
        },
        {
            target = function() return snapToggle end,
            title  = L["Grid & Snap"],
            body   = L["EM_HELP_SNAP"],
            anchor = "BOTTOM",
        },
        {
            target = function() return bgWidget end,
            title  = L["Background Opacity"],
            body   = L["EM_HELP_OPACITY"],
            anchor = "BOTTOM",
        },
        {
            target = function() return cdmBtn end,
            title  = L["CDM & Anchor"],
            body   = L["EM_HELP_CDM"],
            anchor = "BOTTOM",
        },
        {
            title  = L["Copy Settings"],
            body   = L["EM_HELP_COPYTO"],
            anchor = "CENTER",
        },
        {
            target = function() return undoBtn end,
            title  = L["Undo / Cancel All"],
            body   = L["EM_HELP_UNDO"],
            anchor = "BOTTOM",
        },
        {
            target = function() return exitBtn end,
            title  = L["Exit Edit Mode"],
            body   = L["EM_HELP_EXIT"],
            anchor = "BOTTOM",
        },
    }
end

local function EnsureTourFrames()
    if tourState then return tourState end

    local ts = {}
    tourState = ts
    ts.step = 0

    ts.masks = {}
    for i = 1, 4 do
        local m = CreateFrame("Frame", nil, UIParent)
        m:SetFrameStrata("TOOLTIP"); m:SetFrameLevel(940)
        local tex = m:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints(); tex:SetColorTexture(0, 0, 0, MASK_ALPHA)
        m:EnableMouse(true); m:Hide()
        ts.masks[i] = m
    end

    ts.ring = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    ts.ring:SetFrameStrata("TOOLTIP"); ts.ring:SetFrameLevel(941)
    ts.ring:SetBackdrop({ edgeFile = W8, edgeSize = 2 })
    ts.ring:SetBackdropBorderColor(1.00, 0.82, 0.00, 0.85)
    ts.ring:Hide()

    ts.card = CreateFrame("Frame", "MSUF_EM2_TourCard", UIParent, "BackdropTemplate")
    ts.card:SetFrameStrata("TOOLTIP"); ts.card:SetFrameLevel(945)
    ts.card:SetWidth(CARD_W)
    ts.card:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1,
                          insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    ts.card:SetBackdropColor(0.03, 0.05, 0.12, 0.97)
    ts.card:SetBackdropBorderColor(1.00, 0.82, 0.00, 0.70)
    ts.card:EnableMouse(true); ts.card:Hide()

    ts.card:EnableKeyboard(true)
    ts.card:SetScript("OnKeyDown", function(self, k)
        if k == "ESCAPE" then
            self:SetPropagateKeyboardInput(false); HUD.StopTour()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    ts.stepFS = MakeFS(ts.card, 10, TH.mutedR, TH.mutedG, TH.mutedB, 0.70)
    ts.stepFS:SetPoint("TOPRIGHT", ts.card, "TOPRIGHT", -CARD_PAD, -10)

    ts.titleFS = MakeFS(ts.card, 13, 1.00, 0.82, 0.00, 1.00)
    ts.titleFS:SetPoint("TOPLEFT", ts.card, "TOPLEFT", CARD_PAD, -10)

    ts.bodyFS = MakeFS(ts.card, 11, 0.78, 0.82, 0.90, 0.90)
    ts.bodyFS:SetPoint("TOPLEFT", ts.card, "TOPLEFT", CARD_PAD, -28)
    ts.bodyFS:SetWidth(CARD_W - CARD_PAD * 2)
    ts.bodyFS:SetWordWrap(true); ts.bodyFS:SetJustifyH("LEFT")

    local NAV_H = 26
    local NAV_W = 68

    local function NavBtn(text)
        local b = CreateFrame("Button", nil, ts.card, "BackdropTemplate")
        b:SetSize(NAV_W, NAV_H)
        b:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1,
                        insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        b:SetBackdropColor(0.09, 0.10, 0.14, 0.90)
        b:SetBackdropBorderColor(0.10, 0.20, 0.42, 0.65)
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
        b._fs = MakeFS(b, 11, TH.textR, TH.textG, TH.textB, 1)
        b._fs:SetPoint("CENTER"); b._fs:SetText(text)
        return b
    end

    ts.skipBtn = NavBtn(L["EM_TOUR_SKIP"])
    ts.skipBtn:SetScript("OnClick", function() HUD.StopTour() end)

    ts.backBtn = NavBtn(L["EM_TOUR_BACK"])
    ts.backBtn:SetScript("OnClick", function() HUD.TourStep(ts.step - 1) end)

    ts.nextBtn = NavBtn(L["EM_TOUR_NEXT"])
    ts.nextBtn:SetScript("OnClick", function()
        local steps = GetTourSteps()
        if ts.step >= #steps then
            HUD.StopTour()
        else
            HUD.TourStep(ts.step + 1)
        end
    end)

    return ts
end

local function PositionMask(ts, tgt)
    local uiW, uiH = UIParent:GetWidth(), UIParent:GetHeight()
    local m1, m2, m3, m4 = ts.masks[1], ts.masks[2], ts.masks[3], ts.masks[4]

    if not tgt then
        m1:ClearAllPoints(); m1:SetAllPoints(UIParent); m1:Show()
        m2:Hide(); m3:Hide(); m4:Hide()
        ts.ring:Hide()
        return
    end

    local sl = tgt:GetLeft() or 0
    local sr = tgt:GetRight() or 0
    local st = tgt:GetTop() or 0
    local sb = tgt:GetBottom() or 0
    local ratio = tgt:GetEffectiveScale() / UIParent:GetEffectiveScale()
    sl = sl * ratio - SPOT_PAD
    sr = sr * ratio + SPOT_PAD
    st = st * ratio + SPOT_PAD
    sb = sb * ratio - SPOT_PAD

    m1:ClearAllPoints()
    m1:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    m1:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", uiW, -(uiH - st))
    m1:Show()

    m2:ClearAllPoints()
    m2:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -(uiH - sb))
    m2:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
    m2:Show()

    m3:ClearAllPoints()
    m3:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -(uiH - st))
    m3:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", sl, -(uiH - sb))
    m3:Show()

    m4:ClearAllPoints()
    m4:SetPoint("TOPLEFT", UIParent, "TOPLEFT", sr, -(uiH - st))
    m4:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", uiW, -(uiH - sb))
    m4:Show()

    ts.ring:ClearAllPoints()
    ts.ring:SetPoint("TOPLEFT", UIParent, "TOPLEFT", sl, -(uiH - st))
    ts.ring:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", sr, -(uiH - sb))
    ts.ring:Show()
end

local function PositionCard(ts, tgt, anchorHint)
    local card = ts.card
    card:ClearAllPoints()

    if not tgt or anchorHint == "CENTER" then
        card:SetPoint("CENTER", UIParent, "CENTER", 0, -20)
        return
    end

    local ratio = tgt:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local uiH = UIParent:GetHeight()
    local t = (tgt:GetTop() or 0) * ratio
    local b = (tgt:GetBottom() or 0) * ratio
    local cx = ((tgt:GetLeft() or 0) + (tgt:GetRight() or 0)) * 0.5 * ratio

    if (uiH - t) < uiH * 0.3 then
        card:SetPoint("TOP", UIParent, "TOPLEFT", cx, -(uiH - b) - 14)
    else
        card:SetPoint("BOTTOM", UIParent, "TOPLEFT", cx, (uiH - t) + 14)
    end
end

function HUD.TourStep(idx)
    local ts = EnsureTourFrames()
    local steps = GetTourSteps()
    if idx < 1 then idx = 1 end
    if idx > #steps then idx = #steps end
    ts.step = idx

    local s = steps[idx]
    local tgt = s.target and s.target() or nil

    PositionMask(ts, tgt)
    PositionCard(ts, tgt, s.anchor)

    ts.titleFS:SetText(s.title)
    ts.bodyFS:SetText(s.body)
    ts.stepFS:SetText(L["EM_TOUR_STEP"]:format(idx, #steps))

    local bH = ts.bodyFS:GetStringHeight() or 14
    ts.card:SetHeight(28 + bH + 12 + 26 + 12)

    ts.skipBtn:ClearAllPoints()
    ts.skipBtn:SetPoint("BOTTOMLEFT", ts.card, "BOTTOMLEFT", CARD_PAD, 10)

    ts.backBtn:ClearAllPoints()
    ts.nextBtn:ClearAllPoints()
    ts.nextBtn:SetPoint("BOTTOMRIGHT", ts.card, "BOTTOMRIGHT", -CARD_PAD, 10)
    ts.backBtn:SetPoint("RIGHT", ts.nextBtn, "LEFT", -6, 0)

    if idx <= 1 then ts.backBtn:Hide() else ts.backBtn:Show() end

    local isLast = idx >= #steps
    ts.nextBtn._fs:SetText(isLast and L["EM_TOUR_DONE"] or L["EM_TOUR_NEXT"])
    if isLast then
        ts.nextBtn._fs:SetTextColor(TH.onR, TH.onG, TH.onB, 1)
    else
        ts.nextBtn._fs:SetTextColor(TH.textR, TH.textG, TH.textB, 1)
    end

    ts.card:Show()
end

function HUD.StartTour()
    local ts = EnsureTourFrames()
    for i = 1, 4 do ts.masks[i]:Show() end
    HUD.TourStep(1)
end

function HUD.StopTour()
    if not tourState then return end
    for i = 1, 4 do tourState.masks[i]:Hide() end
    tourState.ring:Hide()
    tourState.card:Hide()
    tourState.step = 0
end

-- =========================================================================
local function EnsureHUD()
    if hudFrame then return end

    -- ── ROW 1 ──
    hudFrame = CreateFrame("Frame", "MSUF_EM2_HUD", UIParent, "BackdropTemplate")
    hudFrame:SetFrameStrata("FULLSCREEN"); hudFrame:SetFrameLevel(100)
    hudFrame:SetHeight(R1_H)
    hudFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    hudFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    hudFrame:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=0,right=0,top=0,bottom=0} })
    hudFrame:SetBackdropColor(unpack(TH.r1Bg))
    hudFrame:SetBackdropBorderColor(unpack(TH.edge))
    hudFrame:EnableMouse(true); hudFrame:Hide()

    local title = MakeFS(hudFrame, 11, TH.titleR, TH.titleG, TH.titleB, 0.50)
    title:SetPoint("LEFT", hudFrame, "LEFT", 14, 0)
    title:SetText("EDIT MODE")

    -- ── Prominent HELP button ──
    helpBtn = CreateFrame("Button", nil, hudFrame, "BackdropTemplate")
    helpBtn:SetSize(72, 26)
    helpBtn:SetPoint("LEFT", title, "RIGHT", 10, 0)
    helpBtn:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1,
                          insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    helpBtn:SetBackdropColor(TH.onR * 0.20, TH.onG * 0.20, TH.onB * 0.20, 0.85)
    helpBtn:SetBackdropBorderColor(TH.onR, TH.onG, TH.onB, 0.60)
    do
        local glow = helpBtn:CreateTexture(nil, "BACKGROUND", nil, -1)
        glow:SetPoint("TOPLEFT", -3, 3); glow:SetPoint("BOTTOMRIGHT", 3, -3)
        glow:SetColorTexture(TH.onR, TH.onG, TH.onB, 0.08)
        helpBtn._glow = glow

        local hl = helpBtn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(TH.onR, TH.onG, TH.onB, 0.12)

        local lbl = MakeFS(helpBtn, 12, TH.onR, TH.onG, TH.onB, 1)
        lbl:SetPoint("CENTER", 0, 0); lbl:SetText(L["EM_HELP_BTN"])
        helpBtn._label = lbl

        local pulse = helpBtn:CreateAnimationGroup()
        local fadeOut = pulse:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0.45)
        fadeOut:SetDuration(0.8); fadeOut:SetOrder(1); fadeOut:SetSmoothing("IN_OUT")
        local fadeIn = pulse:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0.45); fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.8); fadeIn:SetOrder(2); fadeIn:SetSmoothing("IN_OUT")
        pulse:SetLooping("REPEAT")
        helpBtn._pulse = pulse
    end
    helpBtn:SetScript("OnClick", function()
        local panel = EnsureTutorialPanel()
        if panel:IsShown() then panel:Hide() else panel:Show() end
    end)
    helpBtn:SetScript("OnEnter", function(self)
        if self._pulse then self._pulse:Stop() end
        self:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -6)
        GameTooltip:SetText(L["EM_HELP_BTN_TIP"], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    helpBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Right-side: Cancel All | Exit
    exitBtn = MakeBtn(hudFrame, "Exit", 48, BTN_H, 12, function()
        if EM2.State then EM2.State.Exit("hud_exit") end
    end)
    exitBtn:SetPoint("RIGHT", hudFrame, "RIGHT", -12, 0)
    exitBtn._label:SetTextColor(TH.exitR, TH.exitG, TH.exitB, 1)
    exitBtn._dot:Hide()
    SetTip(exitBtn, "Lock positions and exit Edit Mode.")

    local rSep = MakeSep(hudFrame, BTN_H)
    rSep:SetPoint("RIGHT", exitBtn, "LEFT", -BTN_GAP, 0)

    cancelAllBtn = MakeBtn(hudFrame, "Cancel All", 78, BTN_H, 12, function()
        if not EM2.State or not EM2.State.CancelAll then return end
        local cf = _G["MSUF_EM2_CancelConfirm"]
        if cf then cf:Show(); return end
        cf = CreateFrame("Frame", "MSUF_EM2_CancelConfirm", UIParent, "BackdropTemplate")
        cf:SetSize(280, 100)
        cf:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
        cf:SetFrameStrata("TOOLTIP"); cf:SetFrameLevel(999)
        cf:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=1,right=1,top=1,bottom=1} })
        cf:SetBackdropColor(0.03, 0.05, 0.12, 0.97)
        cf:SetBackdropBorderColor(0.90, 0.70, 0.30, 0.80)
        cf:EnableMouse(true)
        local msg = MakeFS(cf, 13, TH.textR, TH.textG, TH.textB, 1)
        msg:SetPoint("TOP", cf, "TOP", 0, -18)
        msg:SetText("Discard all changes and exit?")
        local function ConfBtn(text, xOff, onClick)
            local b = CreateFrame("Button", nil, cf)
            b:SetSize(90, 28)
            b:SetPoint("BOTTOM", cf, "BOTTOM", xOff, 14)
            local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.09, 0.10, 0.14, 0.90)
            local brd = CreateFrame("Frame", nil, b, "BackdropTemplate"); brd:SetAllPoints()
            brd:SetFrameLevel(max(0, b:GetFrameLevel()-1))
            brd:SetBackdrop({edgeFile=W8, edgeSize=1}); brd:SetBackdropBorderColor(0.10, 0.20, 0.42, 0.65)
            local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.06)
            local fs = MakeFS(b, 12, TH.textR, TH.textG, TH.textB, 1); fs:SetPoint("CENTER"); fs:SetText(text)
            b:SetScript("OnClick", onClick); return b
        end
        ConfBtn("Yes, discard", -54, function() cf:Hide(); EM2.State.CancelAll() end)
        ConfBtn("No, keep", 54, function() cf:Hide() end)
        cf:EnableKeyboard(true)
        cf:SetScript("OnKeyDown", function(s, k)
            if k == "ESCAPE" then s:SetPropagateKeyboardInput(false); cf:Hide()
            else s:SetPropagateKeyboardInput(true) end
        end)
        cf:Show()
    end)
    cancelAllBtn:SetPoint("RIGHT", rSep, "LEFT", -BTN_GAP, 0)
    cancelAllBtn._label:SetTextColor(0.90, 0.70, 0.30, 0.90)
    cancelAllBtn._dot:Hide()
    SetTip(cancelAllBtn, "Discard ALL changes made in Edit Mode\nand restore settings to the state\nbefore Edit Mode was opened.")

    -- Center toggles
    local c1 = CreateFrame("Frame", nil, hudFrame)
    c1:SetSize(1, BTN_H); c1:SetPoint("CENTER", hudFrame, "CENTER", 0, 0)
    local r1 = {}

    previewBtn = MakeBtn(c1, "Preview", 64, BTN_H, 12, function()
        _G.MSUF_UnitPreviewActive = not (_G.MSUF_UnitPreviewActive and true or false)
        if type(_G.MSUF_SyncAllUnitPreviews) == "function" then _G.MSUF_SyncAllUnitPreviews() end
        SetActive(previewBtn, _G.MSUF_UnitPreviewActive)
    end)
    SetTip(previewBtn, "Show placeholder data on unitframes\nwithout real units (target, focus, etc.)")
    r1[#r1+1] = previewBtn

    auraBtn = MakeBtn(c1, "Auras", 52, BTN_H, 12, function()
        local db = _G.MSUF_DB; if not db then return end
        local a2 = db.auras2; if not a2 then return end
        local sh = a2.shared; if not sh then return end
        sh.showInEditMode = not (sh.showInEditMode and true or false)
        SetActive(auraBtn, sh.showInEditMode)
        if sh.showInEditMode then
            if type(_G.MSUF_A2_ShowAllEditMovers) == "function" then _G.MSUF_A2_ShowAllEditMovers() end
        else
            if type(_G.MSUF_A2_HideAllEditMovers) == "function" then _G.MSUF_A2_HideAllEditMovers() end
        end
        if type(_G.MSUF_Auras2_RefreshAll) == "function" then _G.MSUF_Auras2_RefreshAll() end
    end)
    SetTip(auraBtn, "Toggle aura preview icons\nand aura mover boxes.")
    r1[#r1+1] = auraBtn

    snapToggle = MakeBtn(c1, "Snap", 48, BTN_H, 12, function()
        if EM2.Snap then
            local on = not EM2.Snap.IsEnabled()
            EM2.Snap.SetEnabled(on); SetActive(snapToggle, on)
        end
    end)
    SetTip(snapToggle, "Snap frames to edges of\nother frames while dragging.")
    r1[#r1+1] = snapToggle

    do local s = MakeSep(c1, BTN_H); s._isSep = true; r1[#r1+1] = s end

    cdmBtn = MakeBtn(c1, "CDM", 46, BTN_H, 12, function()
        local db = _G.MSUF_DB; if not db then return end
        db.general = db.general or {}
        db.general.anchorToCooldown = not (db.general.anchorToCooldown and true or false)
        SetActive(cdmBtn, db.general.anchorToCooldown)
        if type(ApplyAllSettings) == "function" then ApplyAllSettings() end
        C_Timer.After(0.1, function()
            if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
            if type(_G.MSUF_EM2_ReforcePreviewFrames) == "function" then _G.MSUF_EM2_ReforcePreviewFrames() end
        end)
    end)
    SetTip(cdmBtn, "Anchor all unitframes to the\nEssential Cooldown Manager.")
    r1[#r1+1] = cdmBtn

    anchorBtn = MakeBtn(c1, "Anchor", 58, BTN_H, 12, function()
        local ov = type(_G.MSUF_EnsureAnchorPicker) == "function" and _G.MSUF_EnsureAnchorPicker()
        if not ov then return end
        ov._onPick = function(frameName)
            local db = _G.MSUF_DB; if not db then return end
            db.general = db.general or {}
            db.general.anchorName = frameName
            db.general.anchorToCooldown = false
            SetActive(cdmBtn, false)
            if type(ApplyAllSettings) == "function" then ApplyAllSettings() end
            C_Timer.After(0.1, function()
                if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
            end)
        end
        ov:Show()
    end)
    SetTip(anchorBtn, "Pick any frame as global anchor\nfor all unitframes.\nOverrides CDM anchor.")
    r1[#r1+1] = anchorBtn

    LayoutCenter(c1, r1, BTN_GAP, SEP_W)

    -- ── ROW 2 ──
    row2Frame = CreateFrame("Frame", "MSUF_EM2_HUD_Row2", hudFrame, "BackdropTemplate")
    row2Frame:SetHeight(R2_H)
    row2Frame:SetPoint("TOPLEFT", hudFrame, "BOTTOMLEFT", 0, 0)
    row2Frame:SetPoint("TOPRIGHT", hudFrame, "BOTTOMRIGHT", 0, 0)
    row2Frame:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=0,right=0,top=0,bottom=0} })
    row2Frame:SetBackdropColor(unpack(TH.r2Bg))
    row2Frame:SetBackdropBorderColor(unpack(TH.edge))
    row2Frame:EnableMouse(true)

    local c2 = CreateFrame("Frame", nil, row2Frame)
    c2:SetSize(1, BTN_H2); c2:SetPoint("CENTER", row2Frame, "CENTER", 0, 0)
    local r2 = {}

    undoBtn = MakeBtn(c2, "Undo", 52, BTN_H2, 11, function()
        if type(_G.MSUF_EM_UndoUndo) == "function" then _G.MSUF_EM_UndoUndo() end
        HUD.RefreshControls()
    end)
    undoBtn._label:SetTextColor(TH.mutedR, TH.mutedG, TH.mutedB, 0.85)
    undoBtn._dot:Hide()
    SetTip(undoBtn, "Undo last position change.")
    r2[#r2+1] = undoBtn

    redoBtn = MakeBtn(c2, "Redo", 52, BTN_H2, 11, function()
        if type(_G.MSUF_EM_UndoRedo) == "function" then _G.MSUF_EM_UndoRedo() end
        HUD.RefreshControls()
    end)
    redoBtn._label:SetTextColor(TH.mutedR, TH.mutedG, TH.mutedB, 0.85)
    redoBtn._dot:Hide()
    SetTip(redoBtn, "Redo last undone change.")
    r2[#r2+1] = redoBtn

    do local s = MakeSep(c2, BTN_H2); s._isSep = true; r2[#r2+1] = s end

    do
        local f = CreateFrame("Frame", nil, c2)
        f:SetSize(80, BTN_H2); f:EnableMouseWheel(true)
        gridWidget = f
        stepFS = MakeFS(f, 11, TH.mutedR, TH.mutedG, TH.mutedB, 0.80)
        stepFS:SetPoint("CENTER")
        local hl = f:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.04)
        f:SetScript("OnMouseWheel", function(_, d)
            if not EM2.Grid then return end
            EM2.Grid.SetGridStep(max(4, min(80, EM2.Grid.GetGridStep() + d * 4)))
            HUD.RefreshControls()
        end)
        SetTip(f, "Grid step size.\nScroll to adjust.")
        r2[#r2+1] = f
    end

    do
        local f = CreateFrame("Frame", nil, c2)
        f:SetSize(74, BTN_H2); f:EnableMouseWheel(true)
        bgWidget = f
        alphaFS = MakeFS(f, 11, TH.mutedR, TH.mutedG, TH.mutedB, 0.80)
        alphaFS:SetPoint("CENTER")
        local hl = f:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.04)
        f:SetScript("OnMouseWheel", function(_, d)
            if not EM2.Grid then return end
            EM2.Grid.SetBgAlpha(max(0, min(1, EM2.Grid.GetBgAlpha() + d * 0.05)))
            HUD.RefreshControls()
        end)
        SetTip(f, "Background overlay opacity.\nScroll to adjust.")
        r2[#r2+1] = f
    end

    LayoutCenter(c2, r2, BTN_GAP, SEP_W)
end

-- =========================================================================
function HUD.RefreshUnitSelector() end

function HUD.RefreshControls()
    if alphaFS and EM2.Grid then alphaFS:SetText("BG " .. floor(EM2.Grid.GetBgAlpha() * 100 + 0.5) .. "%") end
    if stepFS and EM2.Grid then stepFS:SetText("Grid " .. floor(EM2.Grid.GetGridStep()) .. "px") end
    if snapToggle and EM2.Snap then SetActive(snapToggle, EM2.Snap.IsEnabled()) end
    if previewBtn then SetActive(previewBtn, _G.MSUF_UnitPreviewActive and true or false) end
    if cdmBtn then
        local db = _G.MSUF_DB
        SetActive(cdmBtn, db and db.general and db.general.anchorToCooldown and true or false)
    end
    if auraBtn then
        local db = _G.MSUF_DB; local a2 = db and db.auras2; local sh = a2 and a2.shared
        SetActive(auraBtn, sh and sh.showInEditMode and true or false)
    end
    local canUndo = EM2.Undo and EM2.Undo.CanUndo() or false
    local canRedo = EM2.Undo and EM2.Undo.CanRedo() or false
    if undoBtn and undoBtn._label then
        if canUndo then undoBtn._label:SetTextColor(TH.textR, TH.textG, TH.textB, 1)
        else undoBtn._label:SetTextColor(TH.mutedR, TH.mutedG, TH.mutedB, 0.35) end
    end
    if redoBtn and redoBtn._label then
        if canRedo then redoBtn._label:SetTextColor(TH.textR, TH.textG, TH.textB, 1)
        else redoBtn._label:SetTextColor(TH.mutedR, TH.mutedG, TH.mutedB, 0.35) end
    end
end

function HUD.Show()
    EnsureHUD(); HUD.RefreshControls()
    hudFrame:Show(); if row2Frame then row2Frame:Show() end
    if helpBtn and helpBtn._pulse then helpBtn._pulse:Play() end
end

function HUD.Hide()
    HUD.StopTour()
    if tutorialPanel then tutorialPanel:Hide() end
    local cf = _G["MSUF_EM2_CancelConfirm"]; if cf then cf:Hide() end
    if helpBtn and helpBtn._pulse then helpBtn._pulse:Stop() end
    if row2Frame then row2Frame:Hide() end; if hudFrame then hudFrame:Hide() end
end

function HUD.IsShown() return hudFrame and hudFrame:IsShown() or false end
