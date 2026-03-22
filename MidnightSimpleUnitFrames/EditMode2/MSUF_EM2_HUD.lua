-- ============================================================================
-- MSUF_EM2_HUD.lua — Edit Mode HUD (two-row, polished)
-- ============================================================================
local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local HUD = {}; EM2.HUD = HUD

local FONT    = STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF"
local W8      = "Interface/Buttons/WHITE8X8"
local floor, max, min = math.floor, math.max, math.min

local hudFrame, row2Frame
local previewBtn, auraBtn, snapToggle, cdmBtn, anchorBtn
local undoBtn, redoBtn, exitBtn
local alphaFS, stepFS

local R1_H    = 36
local R2_H    = 26
local BTN_H   = 28
local BTN_H2  = 22
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

    -- Exit
    exitBtn = MakeBtn(hudFrame, "Exit", 48, BTN_H, 12, function()
        if EM2.State then EM2.State.Exit("hud_exit") end
    end)
    exitBtn:SetPoint("RIGHT", hudFrame, "RIGHT", -12, 0)
    exitBtn._label:SetTextColor(TH.exitR, TH.exitG, TH.exitB, 1)
    exitBtn._dot:Hide()
    SetTip(exitBtn, "Lock positions and exit Edit Mode.")

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

    undoBtn = MakeBtn(c2, "Undo", 42, BTN_H2, 10, function()
        if type(_G.MSUF_EM_UndoUndo) == "function" then _G.MSUF_EM_UndoUndo() end
    end)
    undoBtn._label:SetTextColor(TH.mutedR, TH.mutedG, TH.mutedB, 0.85)
    undoBtn._dot:Hide()
    SetTip(undoBtn, "Undo last position change.")
    r2[#r2+1] = undoBtn

    redoBtn = MakeBtn(c2, "Redo", 42, BTN_H2, 10, function()
        if type(_G.MSUF_EM_UndoRedo) == "function" then _G.MSUF_EM_UndoRedo() end
    end)
    redoBtn._label:SetTextColor(TH.mutedR, TH.mutedG, TH.mutedB, 0.85)
    redoBtn._dot:Hide()
    SetTip(redoBtn, "Redo last undone change.")
    r2[#r2+1] = redoBtn

    do local s = MakeSep(c2, BTN_H2); s._isSep = true; r2[#r2+1] = s end

    do
        local f = CreateFrame("Frame", nil, c2)
        f:SetSize(66, BTN_H2); f:EnableMouseWheel(true)
        stepFS = MakeFS(f, 10, TH.mutedR, TH.mutedG, TH.mutedB, 0.80)
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
        f:SetSize(58, BTN_H2); f:EnableMouseWheel(true)
        alphaFS = MakeFS(f, 10, TH.mutedR, TH.mutedG, TH.mutedB, 0.80)
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
end

function HUD.Show() EnsureHUD(); HUD.RefreshControls(); hudFrame:Show(); if row2Frame then row2Frame:Show() end end
function HUD.Hide() if row2Frame then row2Frame:Hide() end; if hudFrame then hudFrame:Hide() end end
function HUD.IsShown() return hudFrame and hudFrame:IsShown() or false end
