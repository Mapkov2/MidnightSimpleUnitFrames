-- ============================================================================
-- MSUF_Options_ClassPower.lua  (Phase 6: Rewrite using ns.UI.*)
--
-- Class Power + Alt Mana + Detached Power Bar options panel.
-- Self-syncing via ns.UI.* spec-driven widgets. Zero feature regression.
-- ============================================================================
if _G.__MSUF_Options_ClassPower_Loaded then return end
_G.__MSUF_Options_ClassPower_Loaded = true

local ns = (_G and _G.MSUF_NS) or {}
local TR = ns.TR or function(v) return v end
local UI = ns.UI or {}
local floor = math.floor
local CreateFrame = CreateFrame

local function ApplyReadableFont(fs, kind)
    if not fs then return end
    if kind == "header" then
        fs:SetFontObject(GameFontNormalLarge)
    elseif kind == "section" then
        fs:SetFontObject(GameFontNormal)
    elseif kind == "sub" then
        fs:SetFontObject(GameFontHighlight)
    else
        fs:SetFontObject(GameFontNormal)
    end
end

local function EnhanceCheck(cb)
    if not cb then return cb end
    if cb.Text then
        cb.Text:SetFontObject(GameFontNormal)
        if cb.Text.SetSpacing then cb.Text:SetSpacing(1) end
    end
    return cb
end

local function EnhanceDropdown(dd, width)
    if not dd then return dd end
    if width and dd.SetWidth then dd:SetWidth(width) end
    if dd.Text then dd.Text:SetFontObject(GameFontNormal) end
    return dd
end

-- ============================================================================
-- Modifier-step support (Shift=x5, Ctrl=x10, Alt=grid)
-- ============================================================================
local function GetGridStep()
    local step = (MSUF_DB and MSUF_DB.general and MSUF_DB.general.editModeGridStep) or 20
    step = tonumber(step) or 20
    if step < 8 then step = 8 elseif step > 64 then step = 64 end
    return step
end

local function GetModStep(base)
    base = tonumber(base) or 1
    if IsAltKeyDown and IsAltKeyDown() then return GetGridStep() end
    if IsControlKeyDown and IsControlKeyDown() then return base * 10 end
    if IsShiftKeyDown and IsShiftKeyDown() then return base * 5 end
    return base
end

-- ============================================================================
-- Compact inline slider factory (label left, slider, editbox, ±)
-- Specific to ClassPower — uses bars.* DB, modifier-step, SetEnabled
-- ============================================================================
local function B() if type(MSUF_DB) == "table" then MSUF_DB.bars = MSUF_DB.bars or {}; return MSUF_DB.bars end; return {} end
local function CPRefresh() if type(_G.MSUF_ClassPower_Refresh) == "function" then _G.MSUF_ClassPower_Refresh() end end

local function MakeRow(name, labelText, parent, minV, maxV, step, dbKey, anchor, anchorPt, oX, oY, sliderW, labelW, opts)
    sliderW = sliderW or 188; labelW = labelW or 88; step = step or 1
    opts = opts or {}
    local toDB = (type(opts.toDB) == "function") and opts.toDB or nil
    local fromDB = (type(opts.fromDB) == "function") and opts.fromDB or nil
    local row = {}
    local lbl = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lbl:SetPoint(anchorPt or "TOPLEFT", anchor, "BOTTOMLEFT", oX or 0, oY or -10)
    lbl:SetText(TR(labelText)); lbl:SetTextColor(0.88, 0.88, 0.88); lbl:SetWidth(labelW); lbl:SetJustifyH("LEFT"); ApplyReadableFont(lbl)
    row.label = lbl

    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetPoint("LEFT", lbl, "RIGHT", 12, 0); s:SetSize(sliderW, 18)
    s:SetMinMaxValues(minV, maxV); s:SetValueStep(step); s:SetObeyStepOnDrag(true)
    if UI.StyleSlider then UI.StyleSlider(s) end
    local lo = _G[name .. "Low"]; if lo then lo:SetText("") end
    local hi = _G[name .. "High"]; if hi then hi:SetText("") end
    local tx = _G[name .. "Text"]; if tx then tx:SetText("") end
    row.slider = s

    local eb = CreateFrame("EditBox", name .. "EB", parent, "InputBoxTemplate")
    eb:SetSize(52, 22); eb:SetAutoFocus(false); eb:SetJustifyH("CENTER")
    eb:SetPoint("LEFT", s, "RIGHT", 6, 0)
    eb:SetFontObject(GameFontNormal); eb:SetTextColor(1, 1, 1, 1)
    row.editBox = eb

    local minus = CreateFrame("Button", name .. "Minus", parent)
    minus:SetPoint("LEFT", eb, "RIGHT", 4, 0)
    if UI.StyleSmallButton then UI.StyleSmallButton(minus, false) end
    minus:SetSize(24, 22)

    local plus = CreateFrame("Button", name .. "Plus", parent)
    plus:SetPoint("LEFT", minus, "RIGHT", 3, 0)
    if UI.StyleSmallButton then UI.StyleSmallButton(plus, true) end
    plus:SetSize(24, 22)

    local function Clamp(v) v = tonumber(v); if not v then return nil end; v = floor(v + 0.5); if v < minV then v = minV elseif v > maxV then v = maxV end; return v end

    function row:Set(val) val = Clamp(val) or minV; eb:SetText(tostring(val)); s:SetValue(val) end
    function row:SetFromDB(val)
        if fromDB then
            val = fromDB(val)
        end
        row:Set(val)
    end
    function row:SetEnabled(on)
        local a = on and 1.0 or 0.35
        s:SetAlpha(a); eb:SetAlpha(a); minus:SetAlpha(a); plus:SetAlpha(a)
        if on then s:Enable(); eb:EnableMouse(true); minus:EnableMouse(true); plus:EnableMouse(true); lbl:SetTextColor(0.88, 0.88, 0.88)
        else s:Disable(); eb:EnableMouse(false); eb:ClearFocus(); minus:EnableMouse(false); plus:EnableMouse(false); lbl:SetTextColor(0.35, 0.35, 0.35) end
    end

    s:SetScript("OnValueChanged", function(_, val)
        val = Clamp(val) or minV; eb:SetText(tostring(val))
        if dbKey then
            B()[dbKey] = toDB and toDB(val) or val
            CPRefresh()
        end
    end)

    local function ApplyEB() local v = Clamp(eb:GetText()); if not v then eb:SetText(tostring(Clamp(s:GetValue()) or minV)); return end; eb:SetText(tostring(v)); s:SetValue(v) end
    eb:SetScript("OnEnterPressed", function(self) ApplyEB(); self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", ApplyEB)

    local function StepV(sign) local cur = Clamp(eb:GetText()) or Clamp(s:GetValue()) or minV; cur = cur + sign * GetModStep(step); if cur < minV then cur = minV elseif cur > maxV then cur = maxV end; eb:SetText(tostring(cur)); s:SetValue(cur) end
    minus:SetScript("OnClick", function() StepV(-1) end)
    plus:SetScript("OnClick", function() StepV(1) end)

    -- Self-sync from DB on show
    if dbKey then
        s:HookScript("OnShow", function()
            local v = tonumber(B()[dbKey])
            if v ~= nil then row:SetFromDB(v) end
        end)
    end

    return row
end

-- ============================================================================
-- Texture dropdown with "follow" option
-- ============================================================================
local function MakeTexDrop(name, parent, anchor, oY, dbKey, followText, refreshFn)
    local texLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    texLabel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, oY or -14)
    texLabel:SetText(TR(followText and followText:gsub("^Use ", "") or "Texture"))
    texLabel:SetTextColor(0.88, 0.88, 0.88)
    ApplyReadableFont(texLabel)

    local dd = UI.Dropdown({
        name = name, parent = parent,
        anchor = texLabel, x = -16, y = -3, width = 220, maxVisible = 12,
        iconWidth = 80, iconHeight = 12,
        items = function() return UI.StatusBarTextureItems(followText) end,
        get = function() return B()[dbKey] or "" end,
        set = function(v)
            B()[dbKey] = v
            if type(refreshFn) == "function" then refreshFn() end
        end,
    })

    EnhanceDropdown(dd, 220)
    return texLabel, dd
end

-- ============================================================================
-- Build (called once on first show)
-- ============================================================================
local _built = false

local function BuildClassPowerOptions(leftName, rightName)
    if _built then return end
    leftName  = leftName  or "MSUF_ClassPowerMenuPanelLeft"
    rightName = rightName or "MSUF_ClassPowerMenuPanelRight"
    local leftPanel  = _G[leftName]
    local rightPanel = _G[rightName]
    if not (rightPanel and leftPanel) then return end
    _built = true

    local TEX_W8 = "Interface\\Buttons\\WHITE8x8"
    local EXTRA_RIGHT_W = 220 -- widened right border so value boxes +/- controls do not clip at panel edge
    local totalW = leftPanel:GetWidth() + rightPanel:GetWidth() + EXTRA_RIGHT_W
    local colW = floor(totalW / 2)
    local PAD_X, PAD_Y = 20, -14
    local LINE_W = colW - 28
    local L_LABEL_W, R_LABEL_W = 88, 96
    local L_CHECK_TW, R_CHECK_TW = colW - 54, colW - 54
    local DD_W = 220

    -- Panel
    local cpPanel = CreateFrame("Frame", "MSUF_ClassPowerOptionsPanel", leftPanel:GetParent(), "BackdropTemplate")
    cpPanel:SetSize(totalW, 788)
    cpPanel:SetPoint("TOPLEFT", leftPanel, "BOTTOMLEFT", 0, -10)
    cpPanel:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
    cpPanel:SetBackdropColor(0, 0, 0, 0.20); cpPanel:SetBackdropBorderColor(1, 1, 1, 0.15)

    -- =====================================================================
    -- LEFT COLUMN: Class Power — Position & Behavior
    -- =====================================================================
    local cpHeader = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    cpHeader:SetPoint("TOPLEFT", cpPanel, "TOPLEFT", PAD_X, PAD_Y); cpHeader:SetText(TR("Class Power")); cpHeader:SetTextColor(1, 1, 1); ApplyReadableFont(cpHeader, "header")
    local cpSub = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cpSub:SetPoint("TOPLEFT", cpHeader, "BOTTOMLEFT", 0, -2); cpSub:SetText(TR("Combo Points, Holy Power, Soul Shards, Chi, Essence, Runes"))
    cpSub:SetTextColor(0.60, 0.60, 0.60); cpSub:SetWidth(colW - 36); cpSub:SetJustifyH("LEFT"); ApplyReadableFont(cpSub, "sub")
    local cpLine = cpPanel:CreateTexture(nil, "ARTWORK"); cpLine:SetColorTexture(1, 1, 1, 0.20); cpLine:SetHeight(1)
    cpLine:SetPoint("TOPLEFT", cpPanel, "TOPLEFT", 0, -54); cpLine:SetWidth(LINE_W)

    local cpShowCheck = EnhanceCheck(UI.Check({
        name = "MSUF_ClassPowerShowCheck", parent = cpPanel,
        anchor = cpLine, x = PAD_X, y = -10, maxTextWidth = L_CHECK_TW,
        label = TR("Show class power"),
        get = function() return B().showClassPower ~= false end,
        set = function(v) B().showClassPower = v; CPRefresh() end,
    }))

    local cpHeightRow = MakeRow("MSUF_CPHeight", "Height", cpPanel, 2, 30, 1, "classPowerHeight", cpShowCheck, "TOPLEFT", 0, -10, nil, L_LABEL_W)

    -- Width mode dropdown
    local cpWidthModeLabel = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cpWidthModeLabel:SetPoint("TOPLEFT", cpHeightRow.label, "BOTTOMLEFT", 0, -10)
    cpWidthModeLabel:SetText(TR("Match width")); cpWidthModeLabel:SetTextColor(0.88, 0.88, 0.88); cpWidthModeLabel:SetWidth(L_LABEL_W); cpWidthModeLabel:SetJustifyH("LEFT"); ApplyReadableFont(cpWidthModeLabel)

    local cpWidthModeDrop = UI.Dropdown({
        name = "MSUF_CPWidthModeDrop", parent = cpPanel,
        anchor = cpWidthModeLabel, anchorPoint = "TOPLEFT", x = L_LABEL_W + 16, y = 2, width = DD_W,
        items = {
            { key = "player",        label = TR("Player frame") },
            { key = "cooldown",      label = TR("Essential Cooldowns") },
            { key = "utility",       label = TR("Utility Cooldowns") },
            { key = "tracked_buffs", label = TR("Tracked Buffs") },
            { key = "custom",        label = TR("Custom") },
        },
        get = function() return B().classPowerWidthMode or "player" end,
        set = function(v) B().classPowerWidthMode = v; CPRefresh() end,
    })
    EnhanceDropdown(cpWidthModeDrop, DD_W)

    local cpWidthRow = MakeRow("MSUF_CPWidth", "Width", cpPanel, 30, 800, 1, "classPowerWidth", cpWidthModeLabel, "TOPLEFT", 0, -12, nil, L_LABEL_W)
    local cpXOffsetRow = MakeRow("MSUF_CPXOffset", "X offset", cpPanel, -1000, 1000, 1, "classPowerOffsetX", cpWidthRow.label, "TOPLEFT", 0, -10, nil, L_LABEL_W)
    local cpYOffsetRow = MakeRow("MSUF_CPYOffset", "Y offset", cpPanel, -1000, 1000, 1, "classPowerOffsetY", cpXOffsetRow.label, "TOPLEFT", 0, -10, nil, L_LABEL_W)

    -- Behavior checkboxes
    local function CPC(name, label, anchor, dbKey, defaultVal)
        return UI.Check({
            name = name, parent = cpPanel,
            anchor = anchor, x = 0, y = -4, maxTextWidth = L_CHECK_TW,
            label = TR(label),
            get = function() local v = B()[dbKey]; if v == nil then return defaultVal or false end; return v and true or false end,
            set = function(v) B()[dbKey] = v; CPRefresh() end,
        })
    end

    local cpAnchorCDCheck = EnhanceCheck(CPC("MSUF_ClassPowerAnchorCooldownCheck", "Anchor to Essential Cooldown", cpYOffsetRow.label, "classPowerAnchorToCooldown"))
    cpAnchorCDCheck:ClearAllPoints(); cpAnchorCDCheck:SetPoint("TOPLEFT", cpYOffsetRow.label, "BOTTOMLEFT", 0, -12)
    local cpChargedCheck = EnhanceCheck(CPC("MSUF_ShowChargedCPCheck", "Show empowered combo points", cpAnchorCDCheck, "showChargedComboPoints"))
    local cpTextCheck = EnhanceCheck(CPC("MSUF_ClassPowerTextCheck", "Show resource text", cpChargedCheck, "classPowerShowText"))
    local cpRuneTimeCheck = EnhanceCheck(CPC("MSUF_RuneTimeTextCheck", "Show rune time (per rune)", cpTextCheck, "runeShowTimeText"))
    local cpFillReverseCheck = EnhanceCheck(CPC("MSUF_ClassPowerReverseCheck", "Fill right-to-left", cpRuneTimeCheck, "classPowerFillReverse"))
    local cpEleMaelCheck = EnhanceCheck(CPC("MSUF_ClassPowerEleMaelCheck", "Show Maelstrom bar (Elemental)", cpFillReverseCheck, "showEleMaelstrom"))
    local cpEbonMightCheck = EnhanceCheck(CPC("MSUF_ClassPowerEbonMightCheck", "Show Ebon Might timer (Aug)", cpEleMaelCheck, "showEbonMight", true))
    local cpPredictionCheck = EnhanceCheck(CPC("MSUF_ClassPowerPredictionCheck", "Show resource prediction", cpEbonMightCheck, "classPowerShowPrediction", true))

    -- =====================================================================
    -- LEFT BOTTOM: Detached Power Bar
    -- =====================================================================
    local dpbDiv = cpPanel:CreateTexture(nil, "ARTWORK"); dpbDiv:SetColorTexture(1, 1, 1, 0.12); dpbDiv:SetHeight(1)
    dpbDiv:SetPoint("TOPLEFT", cpPredictionCheck, "BOTTOMLEFT", -PAD_X, -10); dpbDiv:SetWidth(LINE_W)
    local dpbHeader = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    dpbHeader:SetPoint("TOPLEFT", dpbDiv, "BOTTOMLEFT", PAD_X, -8); dpbHeader:SetText(TR("Detached Power Bar")); dpbHeader:SetTextColor(1, 1, 1); ApplyReadableFont(dpbHeader, "section")
    cpPanel._dpbHeader = dpbHeader
    local dpbSub = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    dpbSub:SetPoint("TOPLEFT", dpbHeader, "BOTTOMLEFT", 0, -2); dpbSub:SetText(TR("Only applies when power bar is detached"))
    dpbSub:SetTextColor(0.60, 0.60, 0.60); dpbSub:SetWidth(colW - 36); dpbSub:SetJustifyH("LEFT"); ApplyReadableFont(dpbSub, "sub")
    cpPanel._dpbSub = dpbSub

    local dpbWidthModeLabel = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    dpbWidthModeLabel:SetPoint("TOPLEFT", dpbSub, "BOTTOMLEFT", 0, -8)
    dpbWidthModeLabel:SetText(TR("Match width")); dpbWidthModeLabel:SetTextColor(0.88, 0.88, 0.88); dpbWidthModeLabel:SetWidth(L_LABEL_W); dpbWidthModeLabel:SetJustifyH("LEFT"); ApplyReadableFont(dpbWidthModeLabel)
    cpPanel._dpbWidthModeLabel = dpbWidthModeLabel

    local dpbWidthModeDrop = UI.Dropdown({
        name = "MSUF_DPBWidthModeDrop", parent = cpPanel,
        anchor = dpbWidthModeLabel, anchorPoint = "TOPLEFT", x = L_LABEL_W + 16, y = 2, width = DD_W,
        items = {
            { key = "manual",        label = TR("Manual") },
            { key = "cooldown",      label = TR("Essential Cooldowns") },
            { key = "utility",       label = TR("Utility Cooldowns") },
            { key = "tracked_buffs", label = TR("Tracked Buffs") },
        },
        get = function() return B().detachedPowerBarWidthMode or "manual" end,
        set = function(v) B().detachedPowerBarWidthMode = v ~= "manual" and v or nil; if type(_G.MSUF_ApplyPowerBarEmbedLayout_All) == "function" then _G.MSUF_ApplyPowerBarEmbedLayout_All() end end,
    })
    EnhanceDropdown(dpbWidthModeDrop, DD_W)

    local DPB_Refresh = function() if type(_G.MSUF_DetachedPowerBar_RefreshTextures) == "function" then _G.MSUF_DetachedPowerBar_RefreshTextures() end end
    local dpbFgLabel, dpbFgDrop = MakeTexDrop("MSUF_DPBFgTextureDropdown", cpPanel, dpbWidthModeLabel, -14, "detachedPowerBarTexture", TR("Use global bar texture"), DPB_Refresh)
    cpPanel._dpbFgLabel = dpbFgLabel
    local dpbBgLabel, dpbBgDrop = MakeTexDrop("MSUF_DPBBgTextureDropdown", cpPanel, dpbFgLabel, -34, "detachedPowerBarBgTexture", TR("Use foreground texture"), DPB_Refresh)
    cpPanel._dpbBgLabel = dpbBgLabel

    local dpbOutlineRow = MakeRow("MSUF_DPBOutlineThicknessSlider", "Power bar outline", cpPanel, 0, 6, 1, nil, dpbBgLabel, "TOPLEFT", 0, -26, 150, 110)
    dpbOutlineRow.slider:HookScript("OnValueChanged", function(_, val)
        val = floor((tonumber(val) or 1) + 0.5); if val < 0 then val = 0 elseif val > 6 then val = 6 end
        B().detachedPowerBarOutline = val
        if type(_G.MSUF_ApplyBarOutlineThickness_All) == "function" then _G.MSUF_ApplyBarOutlineThickness_All() end
    end)
    -- Init value
    do local t = tonumber(B().detachedPowerBarOutline) or tonumber(B().barOutlineThickness) or 1; dpbOutlineRow:Set(t) end

    _G.MSUF_DPBOutlineSlider = dpbOutlineRow
    _G.MSUF_RefreshDPBOutlineSliderState = function()
        local any = false
        if type(MSUF_DB) == "table" then
            for _, k in ipairs({ "player", "target", "focus" }) do
                if MSUF_DB[k] and MSUF_DB[k].powerBarDetached then any = true; break end
            end
        end
        dpbOutlineRow:SetEnabled(any)
    end

    -- =====================================================================
    -- RIGHT COLUMN: Style
    -- =====================================================================
    local styleHeader = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    styleHeader:SetPoint("TOPLEFT", cpPanel, "TOPLEFT", colW + PAD_X, PAD_Y); styleHeader:SetText(TR("Style")); styleHeader:SetTextColor(1, 1, 1); ApplyReadableFont(styleHeader, "header")
    local styleSub = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    styleSub:SetPoint("TOPLEFT", styleHeader, "BOTTOMLEFT", 0, -2); styleSub:SetText(TR("Colors, textures & visual tweaks"))
    styleSub:SetTextColor(0.60, 0.60, 0.60); styleSub:SetWidth(colW - 36); styleSub:SetJustifyH("LEFT"); ApplyReadableFont(styleSub, "sub")
    local styleLine = cpPanel:CreateTexture(nil, "ARTWORK"); styleLine:SetColorTexture(1, 1, 1, 0.20); styleLine:SetHeight(1)
    styleLine:SetPoint("TOPLEFT", cpPanel, "TOPLEFT", colW, -54); styleLine:SetWidth(LINE_W)

    local cpColorCheck = EnhanceCheck(UI.Check({
        name = "MSUF_ClassPowerColorCheck", parent = cpPanel,
        anchor = styleLine, x = PAD_X, y = -10, maxTextWidth = R_CHECK_TW,
        label = TR("Color by resource type"),
        get = function() return B().classPowerColorByType ~= false end,
        set = function(v) B().classPowerColorByType = v; CPRefresh() end,
    }))

    local percentAlphaOpts = {
        toDB = function(v)
            local n = tonumber(v) or 0
            if n < 0 then n = 0 elseif n > 100 then n = 100 end
            return n / 100
        end,
        fromDB = function(v)
            local n = tonumber(v)
            if n == nil then n = 0 end
            if n <= 1 then
                n = n * 100
            end
            return floor(n + 0.5)
        end,
    }

    -- Style sliders (right column)
    local cpFontSizeRow    = MakeRow("MSUF_CPFontSize",    "Font size", cpPanel, 6, 32, 1, "classPowerFontSize",    cpColorCheck,          "TOPLEFT", 0, -10, nil, R_LABEL_W)
    local cpTextOffsetXRow = MakeRow("MSUF_CPTextOffsetX", "Text X",    cpPanel, -200, 200, 1, "classPowerTextOffsetX", cpFontSizeRow.label,  "TOPLEFT", 0, -10, nil, R_LABEL_W)
    local cpTextOffsetYRow = MakeRow("MSUF_CPTextOffsetY", "Text Y",    cpPanel, -200, 200, 1, "classPowerTextOffsetY", cpTextOffsetXRow.label,"TOPLEFT", 0, -10, nil, R_LABEL_W)
    local cpBgAlphaRow     = MakeRow("MSUF_CPBgAlpha",     "BG opacity",cpPanel, 0, 100, 1, "classPowerBgAlpha",     cpTextOffsetYRow.label,"TOPLEFT", 0, -10, nil, R_LABEL_W, percentAlphaOpts)
    local cpTickRow        = MakeRow("MSUF_CPTick",        "Separator", cpPanel, 0, 4, 1, "classPowerTickWidth",    cpBgAlphaRow.label,    "TOPLEFT", 0, -10, nil, R_LABEL_W)
    local cpOutlineRow     = MakeRow("MSUF_CPOutline",     "Outline",   cpPanel, 0, 4, 1, "classPowerOutline",      cpTickRow.label,       "TOPLEFT", 0, -10, nil, R_LABEL_W)
    local cpFilledAlphaRow = MakeRow("MSUF_CPFilledAlpha", "Filled %",  cpPanel, 0, 100, 5, "classPowerFilledAlpha", cpOutlineRow.label,    "TOPLEFT", 0, -10, nil, R_LABEL_W, percentAlphaOpts)
    local cpEmptyAlphaRow  = MakeRow("MSUF_CPEmptyAlpha",  "Empty %",   cpPanel, 0, 100, 5, "classPowerEmptyAlpha",  cpFilledAlphaRow.label,"TOPLEFT", 0, -10, nil, R_LABEL_W, percentAlphaOpts)
    local cpGapRow         = MakeRow("MSUF_CPGap",         "Pip gap",   cpPanel, 0, 8, 1, "classPowerGap",          cpEmptyAlphaRow.label, "TOPLEFT", 0, -10, nil, R_LABEL_W)

    -- Auto-Hide subsection
    local ahLine = cpPanel:CreateTexture(nil, "ARTWORK"); ahLine:SetColorTexture(1, 1, 1, 0.12); ahLine:SetHeight(1)
    ahLine:SetPoint("TOPLEFT", cpGapRow.label, "BOTTOMLEFT", -PAD_X, -10); ahLine:SetWidth(LINE_W)
    local ahHeader = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ahHeader:SetPoint("TOPLEFT", ahLine, "BOTTOMLEFT", PAD_X, -6); ahHeader:SetText(TR("Auto-Hide")); ahHeader:SetTextColor(0.88, 0.88, 0.88); ApplyReadableFont(ahHeader, "section")
    cpPanel._ahHeader = ahHeader

    local function RPC(name, label, anchor, dbKey, defaultVal)
        return UI.Check({
            name = name, parent = cpPanel,
            anchor = anchor, x = 0, y = -6, maxTextWidth = R_CHECK_TW,
            label = TR(label),
            get = function() local v = B()[dbKey]; if v == nil then return defaultVal or false end; return v and true or false end,
            set = function(v) B()[dbKey] = v; CPRefresh() end,
        })
    end

    local cpHideOOCCheck   = EnhanceCheck(RPC("MSUF_ClassPowerHideOOC",   "Hide out of combat", ahHeader, "classPowerHideOOC"))
    local cpHideFullCheck  = EnhanceCheck(RPC("MSUF_ClassPowerHideFull",  "Hide when full",     cpHideOOCCheck, "classPowerHideWhenFull"))
    local cpHideEmptyCheck = EnhanceCheck(RPC("MSUF_ClassPowerHideEmpty", "Hide when empty",    cpHideFullCheck, "classPowerHideWhenEmpty"))

    -- Texture dropdowns (right column)
    local CPTexRefresh = function() if type(_G.MSUF_ClassPower_RefreshTextures) == "function" then _G.MSUF_ClassPower_RefreshTextures() end end
    local cpFgTexLabel, _ = MakeTexDrop("MSUF_CPFgTextureDropdown", cpPanel, cpHideEmptyCheck, -12, "classPowerTexture", TR("Use global bar texture"), CPTexRefresh)
    cpPanel._cpFgTexLabel = cpFgTexLabel
    local cpBgTexLabel, _ = MakeTexDrop("MSUF_CPBgTextureDropdown", cpPanel, cpFgTexLabel, -34, "classPowerBgTexture", TR("Use foreground texture"), CPTexRefresh)
    cpPanel._cpBgTexLabel = cpBgTexLabel

    -- =====================================================================
    -- RIGHT BOTTOM: Alternative Mana Bar
    -- =====================================================================
    local amDiv = cpPanel:CreateTexture(nil, "ARTWORK"); amDiv:SetColorTexture(1, 1, 1, 0.12); amDiv:SetHeight(1)
    amDiv:SetPoint("TOPLEFT", cpBgTexLabel, "BOTTOMLEFT", -PAD_X, -38); amDiv:SetWidth(LINE_W)
    local amHeader = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    amHeader:SetPoint("TOPLEFT", amDiv, "BOTTOMLEFT", PAD_X, -8); amHeader:SetText(TR("Alternative Mana Bar")); amHeader:SetTextColor(1, 1, 1); ApplyReadableFont(amHeader, "header")
    local amSub = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    amSub:SetPoint("TOPLEFT", amHeader, "BOTTOMLEFT", 0, -2); amSub:SetText(TR("Shadow, Ret, Ele, Enh, Balance, Feral, WW"))
    amSub:SetTextColor(0.60, 0.60, 0.60); amSub:SetWidth(colW - 36); amSub:SetJustifyH("LEFT"); ApplyReadableFont(amSub, "sub")

    local amShowCheck = EnhanceCheck(UI.Check({
        name = "MSUF_AltManaShowCheck", parent = cpPanel,
        anchor = amSub, x = 0, y = -6, maxTextWidth = R_CHECK_TW,
        label = TR("Show mana bar (dual resource)"),
        get = function() return B().showAltMana ~= false end,
        set = function(v) B().showAltMana = v; CPRefresh() end,
    }))

    local amHeightRow = MakeRow("MSUF_AMHeight", "Height",   cpPanel, 2, 30, 1, "altManaHeight", amShowCheck, "TOPLEFT", 0, -10, nil, R_LABEL_W)
    local amOffsetRow = MakeRow("MSUF_AMOffset", "Y offset", cpPanel, -50, 50, 1, "altManaOffsetY", amHeightRow.label, "TOPLEFT", 0, -10, nil, R_LABEL_W)

    -- =====================================================================
    -- Quick action buttons
    -- =====================================================================
    local btnDiv = cpPanel:CreateTexture(nil, "ARTWORK"); btnDiv:SetColorTexture(1, 1, 1, 0.12); btnDiv:SetHeight(1)
    btnDiv:SetPoint("TOPLEFT", dpbOutlineRow.label, "BOTTOMLEFT", -PAD_X, -14); btnDiv:SetWidth(totalW - 2)

    local Skin = _G.MSUF_SkinMidnightActionButton
    local editBtn = CreateFrame("Button", "MSUF_ClassPower_EditModeButton", cpPanel, "UIPanelButtonTemplate")
    editBtn:SetSize(156, 24); editBtn:SetText(TR("Edit Mode")); editBtn:SetPoint("TOPLEFT", btnDiv, "BOTTOMLEFT", PAD_X, -10)
    editBtn._msufNoSlashSkin = true
    if Skin then Skin(editBtn) else editBtn.__msufMidnightActionSkinned = true end
    editBtn:SetScript("OnClick", function()
        local st = _G.MSUF_EditState
        local isActive = type(st) == "table" and st.active
        local fn = _G.MSUF_SetMSUFEditModeDirect or _G.MSUF_SetEditMode
        if type(fn) == "function" then fn(not isActive) end
    end)

    local colorBtn = CreateFrame("Button", "MSUF_ClassPower_ClassColorButton", cpPanel, "UIPanelButtonTemplate")
    colorBtn:SetSize(156, 24); colorBtn:SetText(TR("Class color")); colorBtn:SetPoint("LEFT", editBtn, "RIGHT", 12, 0)
    colorBtn._msufNoSlashSkin = true
    if Skin then Skin(colorBtn) else colorBtn.__msufMidnightActionSkinned = true end
    colorBtn:SetScript("OnClick", function()
        if type(_G.MSUF_OpenPage) == "function" then _G.MSUF_OpenPage("colors") end
        if C_Timer and C_Timer.After then C_Timer.After(0, function()
            local dd = _G["MSUF_Colors_ClassPowerTypeDropdown"]
            if not dd then return end
            local scroll = _G["MSUF_ColorsScrollFrame"]; local child = _G["MSUF_ColorsScrollChild"]
            if scroll and child and scroll.SetVerticalScroll and child.GetTop and dd.GetTop then
                local off = ((child:GetTop() or 0) - (dd:GetTop() or 0)) - 12; if off < 0 then off = 0 end
                scroll:SetVerticalScroll(off)
            end
            if _G.ToggleDropDownMenu then pcall(_G.ToggleDropDownMenu, 1, nil, dd, dd, 0, 0) end
        end) end
    end)

    -- =====================================================================
    -- Sync all widget values from DB (initial + every OnShow)
    -- =====================================================================
    local function SyncAll()
        if type(MSUF_DB) ~= "table" then return end
        local b = MSUF_DB.bars or {}
        local cpOn = (b.showClassPower ~= false)
        local amOn = (b.showAltMana ~= false)

        -- Sliders
        cpHeightRow:Set(tonumber(b.classPowerHeight) or 4)
        local w = tonumber(b.classPowerWidth); if not w or w < 30 then w = ((MSUF_DB.player and tonumber(MSUF_DB.player.width)) or 275) - 4 end
        cpWidthRow:Set(w)
        cpXOffsetRow:Set(tonumber(b.classPowerOffsetX) or 0)
        cpYOffsetRow:Set(tonumber(b.classPowerOffsetY) or 0)
        cpFontSizeRow:Set(tonumber(b.classPowerFontSize) or 16)
        cpTextOffsetXRow:Set(tonumber(b.classPowerTextOffsetX) or 0)
        cpTextOffsetYRow:Set(tonumber(b.classPowerTextOffsetY) or 0)
        cpBgAlphaRow:SetFromDB(b.classPowerBgAlpha)
        cpTickRow:Set(tonumber(b.classPowerTickWidth) or 1)
        cpOutlineRow:Set(tonumber(b.classPowerOutline) or 1)
        cpFilledAlphaRow:SetFromDB(b.classPowerFilledAlpha)
        cpEmptyAlphaRow:SetFromDB(b.classPowerEmptyAlpha)
        cpGapRow:Set(tonumber(b.classPowerGap) or 0)
        amHeightRow:Set(tonumber(b.altManaHeight) or 4)
        amOffsetRow:Set(tonumber(b.altManaOffsetY) or -2)

        -- Width slider only in custom mode
        local wm = b.classPowerWidthMode or "player"
        cpWidthRow:SetEnabled(cpOn and wm == "custom")

        -- Enable/disable sub-controls based on master toggles
        cpHeightRow:SetEnabled(cpOn); cpXOffsetRow:SetEnabled(cpOn); cpYOffsetRow:SetEnabled(cpOn)
        cpBgAlphaRow:SetEnabled(cpOn); cpTickRow:SetEnabled(cpOn); cpOutlineRow:SetEnabled(cpOn)
        cpFilledAlphaRow:SetEnabled(cpOn); cpEmptyAlphaRow:SetEnabled(cpOn); cpGapRow:SetEnabled(cpOn)
        cpFontSizeRow:SetEnabled(cpOn); cpTextOffsetXRow:SetEnabled(cpOn); cpTextOffsetYRow:SetEnabled(cpOn)
        amHeightRow:SetEnabled(amOn); amOffsetRow:SetEnabled(amOn)

        -- DPB outline
        local dpbT = tonumber(b.detachedPowerBarOutline) or tonumber(b.barOutlineThickness) or 1
        dpbOutlineRow:Set(dpbT)
        if _G.MSUF_RefreshDPBOutlineSliderState then _G.MSUF_RefreshDPBOutlineSliderState() end

        -- Auto-hide header dim
        if cpPanel._ahHeader then
            cpPanel._ahHeader:SetTextColor(cpOn and 0.88 or 0.35, cpOn and 0.88 or 0.35, cpOn and 0.88 or 0.35)
        end
    end

    -- Initial sync (panel is already visible during Build)
    SyncAll()
    -- Force dropdowns to refresh (they self-sync on OnShow but panel is already visible)
    if cpWidthModeDrop and cpWidthModeDrop.Refresh then cpWidthModeDrop:Refresh() end
    if dpbWidthModeDrop and dpbWidthModeDrop.Refresh then dpbWidthModeDrop:Refresh() end
    -- Force checkboxes to re-read DB (OnShow won't fire since parent is already visible)
    for _, cb in ipairs({ cpShowCheck, cpColorCheck, cpAnchorCDCheck, cpChargedCheck, cpTextCheck,
        cpRuneTimeCheck, cpFillReverseCheck, cpEleMaelCheck, cpEbonMightCheck, cpPredictionCheck,
        cpHideOOCCheck, cpHideFullCheck, cpHideEmptyCheck, amShowCheck }) do
        local handler = cb and cb:GetScript("OnShow")
        if handler then handler(cb) end
    end
    -- Re-sync every time panel becomes visible
    cpPanel:HookScript("OnShow", function()
        SyncAll()
        if cpWidthModeDrop and cpWidthModeDrop.Refresh then cpWidthModeDrop:Refresh() end
        if dpbWidthModeDrop and dpbWidthModeDrop.Refresh then dpbWidthModeDrop:Refresh() end
    end)

    -- Dynamic panel height
    do
        local function Recalc()
            if not (editBtn.GetBottom and cpPanel.GetTop) then return end
            local h = math.ceil((cpPanel:GetTop() or 0) - (editBtn:GetBottom() or 0)) + 14
            if h < 740 then h = 740 end
            cpPanel:SetHeight(h)
        end
        editBtn:HookScript("OnShow", Recalc)
        if C_Timer then C_Timer.After(0.05, Recalc) end
    end

    -- =====================================================================
    -- Scope dimming (mirror Bars right-header dim state)
    -- =====================================================================
    local rh = _G.MSUF_BarsMenuRightHeader
    if rh and rh.SetTextColor then
        hooksecurefunc(rh, "SetTextColor", function(_, r)
            if cpPanel then
                local dim = type(r) == "number" and r < 0.5
                cpPanel:SetAlpha(dim and 0.35 or 1); cpPanel:EnableMouse(not dim)
            end
        end)
    end

    -- Scroll height fix
    do
        local origQ = _G.MSUF_BarsMenu_QueueScrollUpdate
        if type(origQ) == "function" then
            _G.MSUF_BarsMenu_QueueScrollUpdate = function(...)
                origQ(...)
                if cpPanel and cpPanel.GetBottom and cpPanel:IsShown() then
                    C_Timer.After(0.02, function()
                        local scroll = _G["MSUF_BarsMenuScrollFrame"]; local child = _G["MSUF_BarsMenuScrollChild"]
                        if not (scroll and child and child.GetTop) then return end
                        local h = math.ceil(((child:GetTop() or 0) - (cpPanel:GetBottom() or 0)) + 32)
                        if h < 500 then h = 500 end
                        if h > (child:GetHeight() or 0) then child:SetHeight(h)
                            if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
                        end
                    end)
                end
            end
        end
    end

    if type(_G.MSUF_BarsMenu_QueueScrollUpdate) == "function" then _G.MSUF_BarsMenu_QueueScrollUpdate() end
end

-- Search registration
if _G.MSUF_Search_RegisterRoots then
    _G.MSUF_Search_RegisterRoots({ "classpower" }, { "MSUF_ClassPowerOptionsPanel" }, "Class Resources")
end

-- ============================================================================
-- Hook into tab system
-- ============================================================================
local _hooked = false
local function HookTab()
    if _hooked then return end
    local host = _G["MSUF_ClassPowerMenuHost"]
    if not host then return end
    _hooked = true
    host:HookScript("OnShow", function()
        BuildClassPowerOptions("MSUF_ClassPowerMenuPanelLeft", "MSUF_ClassPowerMenuPanelRight")
    end)
    if host:IsVisible() then
        BuildClassPowerOptions("MSUF_ClassPowerMenuPanelLeft", "MSUF_ClassPowerMenuPanelRight")
    end
end

if _G["MSUF_ClassPowerMenuHost"] then HookTab() end
if not _hooked and type(_G.CreateOptionsPanel) == "function" then
    hooksecurefunc(_G, "CreateOptionsPanel", HookTab)
end

_G.MSUF_EnsureClassPowerMenuBuilt = function()
    HookTab()
    BuildClassPowerOptions("MSUF_ClassPowerMenuPanelLeft", "MSUF_ClassPowerMenuPanelRight")
end
