-- MSUF_GF_EM2_Popup.lua — Edit Mode popup for GroupFrames  v2
-- Full text settings (Name, HP Text 3-slot, Power) in Edit Mode.
-- Midnight 12.0 secret-safe, zero combat overhead.
local _, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 or not EM2.PopupFactory then return end
local F = EM2.PopupFactory
local floor = math.floor
local max, min = math.max, math.min
local type = type

local GF
local function GetGF() if not GF then GF = ns.GF end; return GF end

local function San(v, d)
    v = tonumber(v) or d or 0
    if v ~= v or v > 2000 or v < -2000 then v = d or 0 end
    return floor(v + 0.5)
end

local _popups = {} -- [mode] = popup

------------------------------------------------------------------------
-- Shared dropdown items (built once, reused across party/raid popups)
------------------------------------------------------------------------
local _textModeItems
local function GetTextModeItems()
    if _textModeItems then return _textModeItems end
    local gf = GetGF()
    local modes = gf and gf.HEALTH_TEXT_MODES
    if not modes then return {} end
    _textModeItems = {}
    for i = 1, #modes do
        _textModeItems[i] = { key = modes[i].key, label = modes[i].label }
    end
    return _textModeItems
end

local _delimItems
local function GetDelimItems()
    if _delimItems then return _delimItems end
    local gf = GetGF()
    local opts = gf and gf.DELIMITER_OPTIONS
    if not opts then return {} end
    _delimItems = {}
    for i = 1, #opts do
        _delimItems[i] = { key = opts[i].key, label = opts[i].label }
    end
    return _delimItems
end

local ANCH = { { "LEFT", "Left" }, { "RIGHT", "Right" }, { "CENTER", "Center" } }

------------------------------------------------------------------------
-- Build popup for a mode ("party" or "raid")
------------------------------------------------------------------------
local function BuildGFPopup(mode)
    local gf = GetGF(); if not gf then return nil end
    local isRaid = (mode == "raid")
    local popup  = F.Panel("MSUF_EM2_GFPopup_" .. mode, 380, isRaid and 640 or 600,
                           isRaid and "Raid Frames" or "Party Frames")

    local function Conf() return gf.GetConf(mode) end
    local function V(key) return gf.Val(mode, key) end

    -- ── Apply: read all widgets → write to conf → rebuild ──
    local function Apply()
        if InCombatLockdown and InCombatLockdown() then return end
        local conf = Conf(); if not conf then return end
        if type(_G.MSUF_EM_UndoBeforeChange) == "function" then
            _G.MSUF_EM_UndoBeforeChange("gf", mode)
        end

        -- Position & Size
        conf.offsetX = San(popup.xBox and tonumber(popup.xBox:GetText()), conf.offsetX or 0)
        conf.offsetY = San(popup.yBox and tonumber(popup.yBox:GetText()), conf.offsetY or 0)
        local w = popup.wBox and tonumber(popup.wBox:GetText())
        if w then conf.width = floor(max(40, min(400, w)) + 0.5) end
        local h = popup.hBox and tonumber(popup.hBox:GetText())
        if h then conf.height = floor(max(16, min(200, h)) + 0.5) end

        -- Layout
        local sp = popup.spacingBox and tonumber(popup.spacingBox:GetText())
        if sp then conf.spacing = floor(max(0, min(40, sp)) + 0.5) end
        local pbh = popup.pbhBox and tonumber(popup.pbhBox:GetText())
        if pbh then conf.powerHeight = floor(max(0, min(30, pbh)) + 0.5) end
        if isRaid then
            local upc = popup.upcBox and tonumber(popup.upcBox:GetText())
            if upc then conf.unitsPerColumn = floor(max(1, min(40, upc)) + 0.5) end
            local mc = popup.mcBox and tonumber(popup.mcBox:GetText())
            if mc then conf.maxColumns = floor(max(1, min(8, mc)) + 0.5) end
        end

        -- Name
        if popup.nameShowCB then conf.showName = popup.nameShowCB:GetChecked() and true or false end
        conf.nameOffsetX = San(popup.nameXBox and tonumber(popup.nameXBox:GetText()), 0)
        conf.nameOffsetY = San(popup.nameYBox and tonumber(popup.nameYBox:GetText()), 0)
        if popup.nameSizeBox then
            local sz = tonumber(popup.nameSizeBox:GetText())
            if sz then conf.nameFontSize = floor(max(6, min(24, sz)) + 0.5) end
        end
        if popup._nameAnchorVal then conf.nameAnchor = popup._nameAnchorVal end

        -- HP Text (3-slot)
        if popup._hpLeftVal   then conf.textLeft      = popup._hpLeftVal end
        if popup._hpCenterVal then conf.textCenter     = popup._hpCenterVal end
        if popup._hpRightVal  then conf.textRight      = popup._hpRightVal end
        if popup._hpDelimVal  then conf.textDelimiter  = popup._hpDelimVal end
        if popup.hpReverseCB  then conf.hpTextReverse  = popup.hpReverseCB:GetChecked() and true or false end
        if popup.hpSizeBox then
            local sz = tonumber(popup.hpSizeBox:GetText())
            if sz then conf.hpFontSize = floor(max(6, min(24, sz)) + 0.5) end
        end
        conf.hpOffsetX = San(popup.hpXBox and tonumber(popup.hpXBox:GetText()), 0)
        conf.hpOffsetY = San(popup.hpYBox and tonumber(popup.hpYBox:GetText()), 0)

        -- Power
        if popup.powerShowCB then conf.showPower = popup.powerShowCB:GetChecked() and true or false end
        if popup._powLeftVal   then conf.powerTextLeft      = popup._powLeftVal end
        if popup._powCenterVal then conf.powerTextCenter    = popup._powCenterVal end
        if popup._powRightVal  then conf.powerTextRight     = popup._powRightVal end
        if popup._powDelimVal  then conf.powerTextDelimiter = popup._powDelimVal end
        if popup.powerSizeBox then
            local sz = tonumber(popup.powerSizeBox:GetText())
            if sz then conf.powerFontSize = floor(max(6, min(24, sz)) + 0.5) end
        end
        conf.powerOffsetX = San(popup.powXBox and tonumber(popup.powXBox:GetText()), 0)
        conf.powerOffsetY = San(popup.powYBox and tonumber(popup.powYBox:GetText()), 0)

        -- Rebuild
        gf.RebuildAll()
        C_Timer.After(0.1, function()
            if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        end)
    end

    -- ── Sync: read conf → write to all widgets ──
    local function Sync()
        local conf = Conf(); if not conf then return end
        local function S(b, v) if b and b.SetText then b:SetText(tostring(v or 0)) end end
        local function SC(c, v) if c and c.SetChecked then c:SetChecked(v and true or false) end end

        -- Position & Size
        S(popup.xBox, San(conf.offsetX, 0))
        S(popup.yBox, San(conf.offsetY, 0))
        S(popup.wBox, conf.width  or (isRaid and 80 or 120))
        S(popup.hBox, conf.height or (isRaid and 32 or 40))

        -- Layout
        S(popup.spacingBox, conf.spacing or 1)
        S(popup.pbhBox, conf.powerHeight or (isRaid and 4 or 6))
        if isRaid then
            S(popup.upcBox, conf.unitsPerColumn or 5)
            S(popup.mcBox,  conf.maxColumns or 8)
        end

        -- Name
        SC(popup.nameShowCB, V("showName") ~= false)
        S(popup.nameXBox, conf.nameOffsetX or 0)
        S(popup.nameYBox, conf.nameOffsetY or 0)
        S(popup.nameSizeBox, conf.nameFontSize or (isRaid and 10 or 12))
        popup._nameAnchorVal = conf.nameAnchor or "LEFT"
        if popup.nameAnchorDrop then popup.nameAnchorDrop:SetValue(popup._nameAnchorVal) end

        -- HP Text (3-slot)
        popup._hpLeftVal   = V("textLeft")      or "NONE"
        popup._hpCenterVal = V("textCenter")     or "NONE"
        popup._hpRightVal  = V("textRight")      or "NONE"
        popup._hpDelimVal  = V("textDelimiter")  or " / "
        if popup.hpLeftSel   then popup.hpLeftSel:SetValue(popup._hpLeftVal) end
        if popup.hpCenterSel then popup.hpCenterSel:SetValue(popup._hpCenterVal) end
        if popup.hpRightSel  then popup.hpRightSel:SetValue(popup._hpRightVal) end
        if popup.hpDelimSel  then popup.hpDelimSel:SetValue(popup._hpDelimVal) end
        SC(popup.hpReverseCB, V("hpTextReverse"))
        S(popup.hpSizeBox, conf.hpFontSize or (isRaid and 9 or 10))
        S(popup.hpXBox, conf.hpOffsetX or 0)
        S(popup.hpYBox, conf.hpOffsetY or 0)

        -- Power
        SC(popup.powerShowCB, V("showPower"))
        popup._powLeftVal   = V("powerTextLeft")      or "NONE"
        popup._powCenterVal = V("powerTextCenter")    or "NONE"
        popup._powRightVal  = V("powerTextRight")     or "NONE"
        popup._powDelimVal  = V("powerTextDelimiter") or " / "
        if popup.powLeftSel   then popup.powLeftSel:SetValue(popup._powLeftVal) end
        if popup.powCenterSel then popup.powCenterSel:SetValue(popup._powCenterVal) end
        if popup.powRightSel  then popup.powRightSel:SetValue(popup._powRightVal) end
        if popup.powDelimSel  then popup.powDelimSel:SetValue(popup._powDelimVal) end
        S(popup.powerSizeBox, conf.powerFontSize or 9)
        S(popup.powXBox, conf.powerOffsetX or 0)
        S(popup.powYBox, conf.powerOffsetY or 0)

        -- Dependent rows gray-out
        if popup.nameShowCB  and popup.nameShowCB.UpdateDependents  then popup.nameShowCB:UpdateDependents() end
        if popup.powerShowCB and popup.powerShowCB.UpdateDependents then popup.powerShowCB:UpdateDependents() end
    end

    popup.Sync  = Sync
    popup.Apply = Apply

    -- ════════════════════════════════════════════════════════════════════
    -- Build UI
    -- ════════════════════════════════════════════════════════════════════
    local top = popup._contentTop

    -- ── Card 1: Position & Size ──
    local fC, fB = F.Card(popup, top, "Position & Size", -2, true)
    local fXY = F.PairRow(popup, fB, fC, { label1="X:", label2="Y:", key1="xBox", key2="yBox", onChanged=Apply })
    F.PairRow(popup, fB, fC, { label1="W:", label2="H:", key1="wBox", key2="hBox",
        anchorTo=fXY, onChanged=Apply })
    fC:RecalcHeight()

    -- ── Card 2: Layout ──
    local lC, lB = F.Card(popup, fC, "Layout", -6, true)
    local lSP = F.PairRow(popup, lB, lC, { label1="Spacing:", label2="PBar H:",
        key1="spacingBox", key2="pbhBox", onChanged=Apply })
    if isRaid then
        F.PairRow(popup, lB, lC, { label1="Units/Col:", label2="Max Cols:",
            key1="upcBox", key2="mcBox", anchorTo=lSP, onChanged=Apply })
    end
    lC:RecalcHeight()

    -- ── Card 3: Name ──
    local nC, nB = F.Card(popup, lC, "Name", -6, true)
    local nShow = F.CheckRow(popup, nB, nC, { label="Show Name", cbKey="nameShowCB",
        onChanged=function() Apply() end })
    local nXY = F.PairRow(popup, nB, nC, { label1="X:", label2="Y:",
        key1="nameXBox", key2="nameYBox", anchorTo=nShow, onChanged=Apply })
    local nSA = F.SizeAnchorRow(popup, nB, nC, { sizeKey="nameSizeBox",
        anchorKey="nameAnchorDrop", stateKey="_nameAnchorVal",
        options=ANCH, anchorTo=nXY, onChanged=Apply })
    nC:RecalcHeight()
    popup.nameShowCB:SetDependentRows(nXY, nSA)

    -- ── Card 4: HP Text (3-slot) ──
    local hC, hB = F.Card(popup, nC, "HP Text", -6, false)
    local hLeft = F.SelectRow(popup, hB, hC, { label="Left:",
        selectKey="hpLeftSel", stateKey="_hpLeftVal",
        items=GetTextModeItems, width=140, menuWidth=160, onChanged=Apply })
    local hCenter = F.SelectRow(popup, hB, hC, { label="Center:",
        selectKey="hpCenterSel", stateKey="_hpCenterVal",
        items=GetTextModeItems, width=140, menuWidth=160, anchorTo=hLeft, onChanged=Apply })
    local hRight = F.SelectRow(popup, hB, hC, { label="Right:",
        selectKey="hpRightSel", stateKey="_hpRightVal",
        items=GetTextModeItems, width=140, menuWidth=160, anchorTo=hCenter, onChanged=Apply })
    local hDelim = F.SelectRow(popup, hB, hC, { label="Delimiter:",
        selectKey="hpDelimSel", stateKey="_hpDelimVal",
        items=GetDelimItems, width=100, menuWidth=120, anchorTo=hRight, onChanged=Apply })
    local hRev = F.CheckRow(popup, hB, hC, { label="Reverse Order", cbKey="hpReverseCB",
        anchorTo=hDelim, onChanged=function() Apply() end })
    local hSize = F.SingleRow(popup, hB, hC, { label="Font Size:", boxKey="hpSizeBox",
        anchorTo=hRev, onChanged=Apply })
    F.PairRow(popup, hB, hC, { label1="X:", label2="Y:",
        key1="hpXBox", key2="hpYBox", anchorTo=hSize, onChanged=Apply })
    hC:RecalcHeight()

    -- ── Card 5: Power ──
    local pC, pB = F.Card(popup, hC, "Power", -6, false)
    local pShow = F.CheckRow(popup, pB, pC, { label="Show Power", cbKey="powerShowCB",
        onChanged=function() Apply() end })
    local pLeft = F.SelectRow(popup, pB, pC, { label="Left:",
        selectKey="powLeftSel", stateKey="_powLeftVal",
        items=GetTextModeItems, width=140, menuWidth=160, anchorTo=pShow, onChanged=Apply })
    local pCenter = F.SelectRow(popup, pB, pC, { label="Center:",
        selectKey="powCenterSel", stateKey="_powCenterVal",
        items=GetTextModeItems, width=140, menuWidth=160, anchorTo=pLeft, onChanged=Apply })
    local pRight = F.SelectRow(popup, pB, pC, { label="Right:",
        selectKey="powRightSel", stateKey="_powRightVal",
        items=GetTextModeItems, width=140, menuWidth=160, anchorTo=pCenter, onChanged=Apply })
    local pDelim = F.SelectRow(popup, pB, pC, { label="Delimiter:",
        selectKey="powDelimSel", stateKey="_powDelimVal",
        items=GetDelimItems, width=100, menuWidth=120, anchorTo=pRight, onChanged=Apply })
    local pSize = F.SingleRow(popup, pB, pC, { label="Font Size:", boxKey="powerSizeBox",
        anchorTo=pDelim, onChanged=Apply })
    local pXY = F.PairRow(popup, pB, pC, { label1="X:", label2="Y:",
        key1="powXBox", key2="powYBox", anchorTo=pSize, onChanged=Apply })
    pC:RecalcHeight()
    popup.powerShowCB:SetDependentRows(pLeft, pCenter, pRight, pDelim, pSize, pXY)

    -- ── Scroll recalc ──
    popup._allCards = { fC, lC, nC, hC, pC }
    popup._recalcScroll = function()
        C_Timer.After(0, function()
            local t = popup._scrollChild and popup._scrollChild:GetTop()
            local last = pC
            local b = last and last.GetBottom and last:GetBottom()
            if t and b then popup:UpdateScrollHeight(t - b + 30)
            else popup:UpdateScrollHeight(800) end
        end)
    end

    popup:Hide()
    return popup
end

------------------------------------------------------------------------
-- Show / Hide / IsOpen (global exports for Popups.lua routing)
------------------------------------------------------------------------
local function ShowGFPopup(mode)
    if not _popups[mode] then _popups[mode] = BuildGFPopup(mode) end
    local popup = _popups[mode]; if not popup then return end
    popup.Sync(); popup:Show()
end

local function HideGFPopup(mode)
    if _popups[mode] then _popups[mode]:Hide() end
end

_G.MSUF_EM2_ShowGFPopup = ShowGFPopup
_G.MSUF_EM2_HideGFPopup = HideGFPopup
_G.MSUF_EM2_GFPopupIsOpen = function()
    return (_popups.party and _popups.party:IsShown())
        or (_popups.raid and _popups.raid:IsShown()) or false
end
