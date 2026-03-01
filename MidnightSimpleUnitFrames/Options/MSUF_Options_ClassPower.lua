-- ============================================================================
-- MSUF_Options_ClassPower.lua — Options for Class Power + Alt Mana Bar
--
-- Architecture:
--   - Self-contained: creates widgets lazily on first Bars-tab show.
--   - Third panel below left/right Bars panels (zero surgery on existing anchors).
--   - Same visual language: header + divider line + checkboxes + edit boxes.
--   - Hooks MSUF_SyncBarsTabToggles for state synchronization.
--   - Uses MSUF_Options_BindDBBoolCheck for DB ↔ checkbox binding.
-- ============================================================================

if _G.__MSUF_Options_ClassPower_Loaded then return end
_G.__MSUF_Options_ClassPower_Loaded = true

local type, tonumber = type, tonumber
local math_floor = math.floor
local CreateFrame = CreateFrame

-- ============================================================================
-- Localization (mirrors MSUF_Options_Core pattern)
-- ============================================================================
local ns = (_G and _G.MSUF_NS) or {}
local L = ns.L or {}
if not getmetatable(L) then
    setmetatable(L, { __index = function(_, k) return k end })
end
local function TR(v) return (type(v) == "string" and L[v]) or v end

-- ============================================================================
-- Toggle text styling (same behavior as MSUF_StyleToggleText; replicated
-- to avoid depending on CreateOptionsPanel scope locals)
-- ============================================================================
local function StyleToggleText(cb)
    if not cb or cb.__msufToggleTextStyled then return end
    cb.__msufToggleTextStyled = true
    local fs = cb.text or cb.Text
    if (not fs) and cb.GetName and cb:GetName() and _G then
        fs = _G[cb:GetName() .. "Text"]
    end
    if not (fs and fs.SetTextColor) then return end
    cb.__msufToggleFS = fs
    local function Update()
        if cb.IsEnabled and (not cb:IsEnabled()) then
            fs:SetTextColor(0.35, 0.35, 0.35)
        elseif cb.GetChecked and cb:GetChecked() then
            fs:SetTextColor(1, 1, 1)
        else
            fs:SetTextColor(0.55, 0.55, 0.55)
        end
    end
    cb.__msufToggleUpdate = Update
    cb:HookScript("OnShow", Update)
    cb:HookScript("OnClick", Update)
    pcall(hooksecurefunc, cb, "SetChecked", function() Update() end)
    pcall(hooksecurefunc, cb, "SetEnabled", function() Update() end)
    Update()
end

local function StyleCheckmark(cb)
    if not cb or cb.__msufCheckmarkStyled then return end
    cb.__msufCheckmarkStyled = true
    local check = cb.GetCheckedTexture and cb:GetCheckedTexture()
    if (not check) and cb.GetName and cb:GetName() and _G then
        check = _G[cb:GetName() .. "Check"]
    end
    if not (check and check.SetTexture) then return end
    local addonDir = "MidnightSimpleUnitFrames"
    local h = (cb.GetHeight and cb:GetHeight()) or 24
    local tex = (h >= 24)
        and ("Interface/AddOns/" .. addonDir .. "/Media/msuf_check_tick_bold.tga")
        or  ("Interface/AddOns/" .. addonDir .. "/Media/msuf_check_tick_thin.tga")
    check:SetTexture(tex)
    check:SetTexCoord(0, 1, 0, 1)
    if check.SetBlendMode then check:SetBlendMode("BLEND") end
    if check.ClearAllPoints then
        check:ClearAllPoints()
        check:SetPoint("CENTER", cb, "CENTER", 0, 0)
    end
    if check.SetSize then
        local s = math_floor((h * 0.72) + 0.5)
        if s < 12 then s = 12 end
        check:SetSize(s, s)
    end
end

local function MakeCheck(name, label, parent)
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    local fs = _G[name .. "Text"]
    if fs then fs:SetText(TR(label or "")) end
    cb.text = fs
    StyleToggleText(cb)
    StyleCheckmark(cb)
    return cb
end

-- ============================================================================
-- Number edit box helper (matches existing power bar height edit pattern)
-- ============================================================================
local function MakeNumEdit(name, parent, width)
    local edit = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    edit:SetSize(width or 40, 20)
    edit:SetAutoFocus(false)
    edit:SetTextInsets(4, 4, 2, 2)
    return edit
end

-- Compact slider factory: label + slider + editbox in one row.
-- Returns { slider=, editBox=, label= } table.
local function MakeCompactSlider(name, labelText, parent, minVal, maxVal, step, dbKey, anchorTo, anchorPt, oX, oY, sliderW)
    sliderW = sliderW or 120
    step = step or 1
    local row = {}

    -- Label
    local lbl = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    lbl:SetPoint(anchorPt or "TOPLEFT", anchorTo or parent, anchorPt == "TOPLEFT" and "BOTTOMLEFT" or "BOTTOMLEFT", oX or 0, oY or -10)
    lbl:SetText(TR(labelText))
    lbl:SetTextColor(0.85, 0.85, 0.85)
    row.label = lbl

    -- Slider
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
    s:SetSize(sliderW, 14)
    s:SetMinMaxValues(minVal, maxVal)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    -- Style track
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0.06, 0.06, 0.06, 1)
    track:SetPoint("TOPLEFT", s, "TOPLEFT", 0, -3)
    track:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 0, 3)
    s._track = track
    s:HookScript("OnEnter", function(self) if self._track then self._track:SetColorTexture(0.20, 0.20, 0.20, 1) end end)
    s:HookScript("OnLeave", function(self) if self._track then self._track:SetColorTexture(0.06, 0.06, 0.06, 1) end end)
    local thumb = s:GetThumbTexture()
    if thumb then thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal"); thumb:SetSize(10, 18) end
    -- Hide default low/high/text
    local lo = _G[name .. "Low"];  if lo  then lo:SetText("")  end
    local hi = _G[name .. "High"]; if hi  then hi:SetText("")  end
    local tx = _G[name .. "Text"]; if tx  then tx:SetText("")  end
    row.slider = s

    -- Compact editbox (right of slider)
    local eb = CreateFrame("EditBox", name .. "EB", parent, "InputBoxTemplate")
    eb:SetSize(44, 18)
    eb:SetAutoFocus(false)
    eb:SetPoint("LEFT", s, "RIGHT", 6, 0)
    eb:SetJustifyH("CENTER")
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetTextColor(1, 1, 1, 1)
    row.editBox = eb

    -- px label
    local px = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    px:SetPoint("LEFT", eb, "RIGHT", 3, 0)
    px:SetText((dbKey == "classPowerBgAlpha") and "%" or "px")
    px:SetTextColor(0.45, 0.45, 0.45)
    row.suffix = px

    -- Sync slider → editbox → DB
    local function WriteDB(val)
        if type(MSUF_DB) == "table" then
            MSUF_DB.bars = MSUF_DB.bars or {}
            if dbKey == "classPowerBgAlpha" then
                MSUF_DB.bars[dbKey] = val / 100
            else
                MSUF_DB.bars[dbKey] = val
            end
        end
        if type(_G.MSUF_ClassPower_Refresh) == "function" then
            _G.MSUF_ClassPower_Refresh()
        end
    end

    s:SetScript("OnValueChanged", function(self, val)
        if step >= 1 then val = math_floor(val + 0.5) end
        eb:SetText(tostring(val))
        WriteDB(val)
    end)

    local function ApplyEB()
        local v = tonumber(eb:GetText())
        if type(v) ~= "number" then v = s:GetValue() or minVal end
        if step >= 1 then v = math_floor(v + 0.5) end
        if v < minVal then v = minVal elseif v > maxVal then v = maxVal end
        eb:SetText(tostring(v))
        s:SetValue(v)
    end
    eb:SetScript("OnEnterPressed", function(self) ApplyEB(); self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", function(self) ApplyEB() end)

    -- Set method: update both slider + editbox without triggering OnValueChanged
    function row:Set(val)
        if step >= 1 then val = math_floor(val + 0.5) end
        eb:SetText(tostring(val))
        s:SetValue(val)
    end

    function row:SetEnabled(on)
        if on then
            s:Enable(); eb:EnableMouse(true); eb:SetAlpha(1); lbl:SetTextColor(0.85, 0.85, 0.85)
        else
            s:Disable(); eb:EnableMouse(false); eb:ClearFocus(); eb:SetAlpha(0.45); lbl:SetTextColor(0.35, 0.35, 0.35)
        end
    end

    return row
end

local function ClampAndCommit(edit, dbKey, min, max, default)
    if not edit or not edit.GetText then return end
    local v = tonumber(edit:GetText())
    if type(v) ~= "number" then v = default end
    v = math_floor(v + 0.5)
    if v < min then v = min elseif v > max then v = max end
    edit:SetText(tostring(v))
    if type(MSUF_DB) == "table" then
        MSUF_DB.bars = MSUF_DB.bars or {}
        MSUF_DB.bars[dbKey] = v
    end
    if type(_G.MSUF_ClassPower_Refresh) == "function" then
        _G.MSUF_ClassPower_Refresh()
    end
end

-- ============================================================================
-- Widget references (file-scope; created once, reused on re-show)
-- ============================================================================
local cpPanel          -- third panel frame (BackdropTemplate)
local cpShowCheck      -- "Show class power"
local cpHeightRow      -- slider row: Height
local cpWidthModeDrop  -- dropdown: Match width to
local cpWidthRow       -- slider row: Width (only active in "custom" mode)
local cpXOffsetRow     -- slider row: X offset
local cpYOffsetRow     -- slider row: Y offset
local cpColorCheck     -- "Color by resource type"
local cpBgAlphaRow     -- slider row: Background opacity
local cpTickRow        -- slider row: Separator width
local cpOutlineRow     -- slider row: Outline thickness
local cpChargedCheck   -- "Show empowered combo points"
local cpTextCheck      -- "Show resource text"
local cpAnchorCooldownCheck -- "Anchor to Essential Cooldown"
local amShowCheck      -- "Show alternative mana bar"
local amHeightRow      -- slider row: Height
local amOffsetRow      -- slider row: Y offset

-- ============================================================================
-- Build (called once; idempotent)
-- ============================================================================
local _built = false

local function BuildClassPowerOptions()
    if _built then return end

    local rightPanel = _G["MSUF_BarsMenuPanelRight"]
    local leftPanel  = _G["MSUF_BarsMenuPanelLeft"]
    if not (rightPanel and leftPanel) then return end

    _built = true

    -- ── Third panel (full width, below both columns) ──
    cpPanel = CreateFrame("Frame", "MSUF_ClassPowerOptionsPanel", leftPanel:GetParent(), "BackdropTemplate")
    local totalW = leftPanel:GetWidth() + rightPanel:GetWidth()
    cpPanel:SetSize(totalW, 435)
    cpPanel:SetPoint("TOPLEFT", leftPanel, "BOTTOMLEFT", 0, -10)
    cpPanel:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    cpPanel:SetBackdropColor(0, 0, 0, 0.20)
    cpPanel:SetBackdropBorderColor(1, 1, 1, 0.15)

    -- ── Left column: Class Power ──
    local colW = math_floor(totalW / 2)
    local PAD_X, PAD_Y = 16, -12
    local LINE_W = colW - 24  -- consistent line width for both columns

    -- Header
    local cpHeader = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    cpHeader:SetPoint("TOPLEFT", cpPanel, "TOPLEFT", PAD_X, PAD_Y)
    cpHeader:SetText(TR("Class Power"))
    -- GameFontNormalLarge is yellow by default; force consistent white section headers.
    if cpHeader.SetTextColor then cpHeader:SetTextColor(1, 1, 1) end
    cpPanel._cpHeader = cpHeader

    -- Subtitle
    local cpSub = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cpSub:SetPoint("TOPLEFT", cpHeader, "BOTTOMLEFT", 0, -2)
    cpSub:SetText(TR("Combo Points, Holy Power, Soul Shards, Chi, Essence, Runes"))
    cpSub:SetTextColor(0.55, 0.55, 0.55)
    cpSub:SetWidth(colW - 32)
    cpSub:SetJustifyH("LEFT")

    -- Divider (fixed Y from panel top so both columns align)
    local DIVIDER_Y = -54  -- consistent for both columns
    local cpLine = cpPanel:CreateTexture(nil, "ARTWORK")
    cpLine:SetColorTexture(1, 1, 1, 0.20)
    cpLine:SetHeight(1)
    cpLine:SetPoint("TOPLEFT", cpPanel, "TOPLEFT", 0, DIVIDER_Y)
    cpLine:SetWidth(LINE_W)

    -- Show class power check
    cpShowCheck = MakeCheck("MSUF_ClassPowerShowCheck", "Show class power", cpPanel)
    cpShowCheck:SetPoint("TOPLEFT", cpLine, "BOTTOMLEFT", PAD_X, -10)

    -- Slider rows: Height, Width mode dropdown, Width (custom), X, Y
    cpHeightRow = MakeCompactSlider("MSUF_CPHeight", "Height", cpPanel, 2, 30, 1, "classPowerHeight",
        cpShowCheck, "TOPLEFT", 0, -10)

    -- Width mode dropdown: Player frame / Essential Cooldown / Custom
    local cpWidthModeLabel = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cpWidthModeLabel:SetPoint("TOPLEFT", cpHeightRow.label, "BOTTOMLEFT", 0, -10)
    cpWidthModeLabel:SetText(TR("Match width"))
    cpWidthModeLabel:SetTextColor(0.85, 0.85, 0.85)
    cpPanel._cpWidthModeLabel = cpWidthModeLabel

    cpWidthModeDrop = CreateFrame("Frame", "MSUF_CPWidthModeDrop", cpPanel, "UIDropDownMenuTemplate")
    cpWidthModeDrop:SetPoint("LEFT", cpWidthModeLabel, "RIGHT", -6, -2)
    UIDropDownMenu_SetWidth(cpWidthModeDrop, 130)

    local WIDTH_MODE_OPTIONS = {
        { key = "player",   label = TR("Player frame") },
        { key = "cooldown", label = TR("Essential Cooldown") },
        { key = "custom",   label = TR("Custom") },
    }

    -- Width slider (only enabled in "custom" mode)
    cpWidthRow = MakeCompactSlider("MSUF_CPWidth", "Width", cpPanel, 30, 800, 1, "classPowerWidth",
        cpWidthModeLabel, "TOPLEFT", 0, -12)

    cpXOffsetRow = MakeCompactSlider("MSUF_CPXOffset", "X offset", cpPanel, -1000, 1000, 1, "classPowerOffsetX",
        cpWidthRow.label, "TOPLEFT", 0, -10)

    cpYOffsetRow = MakeCompactSlider("MSUF_CPYOffset", "Y offset", cpPanel, -1000, 1000, 1, "classPowerOffsetY",
        cpXOffsetRow.label, "TOPLEFT", 0, -10)

    -- Wire dropdown after slider rows are created (needs cpWidthRow reference)
    local function OnWidthModeChanged(mode)
        if type(MSUF_DB) == "table" then
            MSUF_DB.bars = MSUF_DB.bars or {}
            MSUF_DB.bars.classPowerWidthMode = mode
        end
        -- Dim width slider unless "custom"
        if cpWidthRow then cpWidthRow:SetEnabled(mode == "custom") end
        if type(_G.MSUF_ClassPower_Refresh) == "function" then
            _G.MSUF_ClassPower_Refresh()
        end
    end

    local InitDrop = _G.MSUF_InitSimpleDropdown
    if InitDrop then
        InitDrop(cpWidthModeDrop, WIDTH_MODE_OPTIONS,
            function()
                return (MSUF_DB and MSUF_DB.bars and MSUF_DB.bars.classPowerWidthMode) or "player"
            end,
            function(v) end,  -- WriteDB handled in OnWidthModeChanged
            function(val) OnWidthModeChanged(val) end,
            130
        )
    end

    -- Color by type check
    cpColorCheck = MakeCheck("MSUF_ClassPowerColorCheck", "Color by resource type", cpPanel)
    cpColorCheck:SetPoint("TOPLEFT", cpYOffsetRow.label, "BOTTOMLEFT", 0, -10)

    -- Background opacity slider (displayed 0-100, stored 0.0-1.0)
    cpBgAlphaRow = MakeCompactSlider("MSUF_CPBgAlpha", "BG opacity", cpPanel, 0, 100, 1, "classPowerBgAlpha",
        cpColorCheck, "TOPLEFT", 0, -10)

    -- Separator width slider
    cpTickRow = MakeCompactSlider("MSUF_CPTick", "Separator", cpPanel, 0, 4, 1, "classPowerTickWidth",
        cpBgAlphaRow.label, "TOPLEFT", 0, -10)

    -- Outline thickness slider (0 = no outline)
    cpOutlineRow = MakeCompactSlider("MSUF_CPOutline", "Outline", cpPanel, 0, 4, 1, "classPowerOutline",
        cpTickRow.label, "TOPLEFT", 0, -10)

    -- Show empowered / charged combo points
    cpChargedCheck = MakeCheck("MSUF_ShowChargedCPCheck", TR("Show empowered combo points"), cpPanel)
    cpChargedCheck:SetPoint("TOPLEFT", cpOutlineRow.label, "BOTTOMLEFT", 0, -10)

    -- Show resource text overlay (e.g. "4/7" on the bar)
    cpTextCheck = MakeCheck("MSUF_ClassPowerTextCheck", TR("Show resource text"), cpPanel)
    cpTextCheck:SetPoint("TOPLEFT", cpChargedCheck, "BOTTOMLEFT", 0, -4)

    -- Anchor to Essential Cooldown Manager (MRB anchorToCooldownManager pattern)
    cpAnchorCooldownCheck = MakeCheck("MSUF_ClassPowerAnchorCooldownCheck", TR("Anchor to Essential Cooldown"), cpPanel)
    cpAnchorCooldownCheck:SetPoint("TOPLEFT", cpTextCheck, "BOTTOMLEFT", 0, -4)

    -- ── Right column: Alt Mana ──
    local amHeader = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    amHeader:SetPoint("TOPLEFT", cpPanel, "TOPLEFT", colW + PAD_X, PAD_Y)
    amHeader:SetText(TR("Alternative Mana Bar"))
    -- GameFontNormalLarge is yellow by default; force consistent white section headers.
    if amHeader.SetTextColor then amHeader:SetTextColor(1, 1, 1) end
    cpPanel._amHeader = amHeader

    -- Subtitle
    local amSub = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    amSub:SetPoint("TOPLEFT", amHeader, "BOTTOMLEFT", 0, -2)
    amSub:SetText(TR("Mana for Shadow, Ret, Ele, Enh, Balance, Feral, WW"))
    amSub:SetTextColor(0.55, 0.55, 0.55)
    amSub:SetWidth(colW - 32)
    amSub:SetJustifyH("LEFT")

    -- Divider (same fixed Y as left column)
    local amLine = cpPanel:CreateTexture(nil, "ARTWORK")
    amLine:SetColorTexture(1, 1, 1, 0.20)
    amLine:SetHeight(1)
    amLine:SetPoint("TOPLEFT", cpPanel, "TOPLEFT", colW, DIVIDER_Y)
    amLine:SetWidth(LINE_W)

    -- Show alt mana check
    amShowCheck = MakeCheck("MSUF_AltManaShowCheck", "Show mana bar (dual resource)", cpPanel)
    amShowCheck:SetPoint("TOPLEFT", amLine, "BOTTOMLEFT", PAD_X, -10)

    -- Height slider
    amHeightRow = MakeCompactSlider("MSUF_AMHeight", "Height", cpPanel, 2, 30, 1, "altManaHeight",
        amShowCheck, "TOPLEFT", 0, -10)

    -- Y Offset slider
    amOffsetRow = MakeCompactSlider("MSUF_AMOffset", "Y offset", cpPanel, -50, 50, 1, "altManaOffsetY",
        amHeightRow.label, "TOPLEFT", 0, -10)

    -- ── Bind checkboxes to DB ──
    local BindBool = _G.MSUF_Options_BindDBBoolCheck
    local function CPRefresh()
        if type(_G.MSUF_ClassPower_Refresh) == "function" then
            _G.MSUF_ClassPower_Refresh()
        end
    end

    if BindBool then
        BindBool(cpShowCheck,  "bars.showClassPower",        CPRefresh, SyncClassPowerToggles)
        BindBool(cpColorCheck, "bars.classPowerColorByType",  CPRefresh, SyncClassPowerToggles)
        BindBool(cpChargedCheck, "bars.showChargedComboPoints", CPRefresh, SyncClassPowerToggles)
        BindBool(cpTextCheck,  "bars.classPowerShowText",     CPRefresh, SyncClassPowerToggles)
        BindBool(cpAnchorCooldownCheck, "bars.classPowerAnchorToCooldown", CPRefresh, SyncClassPowerToggles)
        BindBool(amShowCheck,  "bars.showAltMana",            CPRefresh, SyncClassPowerToggles)
    end

    -- (Slider rows are self-binding — no HookEdit needed)

    -- ── Scope dimming: dim our panel when per-unit scope is active ──
    -- The scope handler in Options_Core dims _G.MSUF_BarsMenuRightHeader via
    -- SetTextColor when a per-unit override is selected. We mirror this: if the
    -- right header goes dim (r < 0.5), our panel dims too. Zero changes to Core.
    local rightHeader = _G.MSUF_BarsMenuRightHeader
    if rightHeader and rightHeader.SetTextColor then
        hooksecurefunc(rightHeader, "SetTextColor", function(self, r)
            if cpPanel then
                local isDimmed = (type(r) == "number" and r < 0.5)
                cpPanel:SetAlpha(isDimmed and 0.35 or 1)
                cpPanel:EnableMouse(not isDimmed)
            end
        end)
    end

    -- ── Fix scroll height: our panel extends below PanelLeft/Right ──
    -- The bars scroll updater uses PanelRight/PanelLeft:GetBottom() as the
    -- bottom anchor. We need it to use our panel instead.
    -- Strategy: hook MSUF_BarsMenu_QueueScrollUpdate to patch the anchor.
    do
        local origQueueFn = _G.MSUF_BarsMenu_QueueScrollUpdate
        if type(origQueueFn) == "function" then
            _G.MSUF_BarsMenu_QueueScrollUpdate = function(...)
                -- Run original first (sets up the queue)
                origQueueFn(...)
                -- Then patch: after 0.01s (after original's C_Timer.After(0)),
                -- re-run with our panel as anchor if it has a lower bottom.
                if cpPanel and cpPanel.GetBottom and cpPanel:IsShown() then
                    C_Timer.After(0.02, function()
                        local scroll = _G["MSUF_BarsMenuScrollFrame"]
                        local child  = _G["MSUF_BarsMenuScrollChild"]
                        if not (scroll and child and child.GetTop) then return end
                        local top = child:GetTop()
                        local bottom = cpPanel:GetBottom()
                        if not (top and bottom) then return end
                        local h = math.ceil((top - bottom) + 32)
                        if h < 500 then h = 500 end
                        local curH = child:GetHeight() or 0
                        if h > curH then
                            child:SetHeight(h)
                            if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
                        end
                    end)
                end
            end
        end
    end

    -- ── Request scroll update so the bars tab accounts for new height ──
    if type(_G.MSUF_BarsMenu_QueueScrollUpdate) == "function" then
        _G.MSUF_BarsMenu_QueueScrollUpdate()
    end
end

-- ============================================================================
-- Sync (called when Bars tab opens or state changes)
-- ============================================================================
local function SyncClassPowerToggles()
    if not _built then return end
    if not MSUF_DB then return end
    local b = MSUF_DB.bars or {}

    -- ClassPower
    if cpShowCheck then
        cpShowCheck:SetChecked(b.showClassPower ~= false)
        if cpShowCheck.__msufToggleUpdate then cpShowCheck.__msufToggleUpdate() end
    end
    if cpColorCheck then
        cpColorCheck:SetChecked(b.classPowerColorByType ~= false)
        if cpColorCheck.__msufToggleUpdate then cpColorCheck.__msufToggleUpdate() end
    end
    if cpHeightRow then
        cpHeightRow:Set(tonumber(b.classPowerHeight) or 4)
    end
    if cpWidthRow then
        -- Default: read from player frame DB width
        local w = tonumber(b.classPowerWidth)
        if not w or w < 30 then
            w = ((MSUF_DB.player and tonumber(MSUF_DB.player.width)) or 275) - 4
        end
        cpWidthRow:Set(w)
    end
    -- Sync width mode dropdown
    local widthMode = b.classPowerWidthMode or "player"
    if cpWidthModeDrop then
        local SyncDrop = _G.MSUF_SyncSimpleDropdown
        if SyncDrop then
            local WIDTH_MODE_OPTIONS = {
                { key = "player",   label = TR("Player frame") },
                { key = "cooldown", label = TR("Essential Cooldown") },
                { key = "custom",   label = TR("Custom") },
            }
            SyncDrop(cpWidthModeDrop, WIDTH_MODE_OPTIONS, function() return widthMode end)
        end
    end
    -- Width slider only active in custom mode
    if cpWidthRow then cpWidthRow:SetEnabled(cpOn and widthMode == "custom") end
    if cpXOffsetRow then
        cpXOffsetRow:Set(tonumber(b.classPowerOffsetX) or 0)
    end
    if cpYOffsetRow then
        cpYOffsetRow:Set(tonumber(b.classPowerOffsetY) or 0)
    end
    if cpBgAlphaRow then
        local a = tonumber(b.classPowerBgAlpha) or 0.3
        cpBgAlphaRow:Set(math_floor(a * 100 + 0.5))
    end
    if cpTickRow then
        cpTickRow:Set(tonumber(b.classPowerTickWidth) or 1)
    end
    if cpOutlineRow then
        cpOutlineRow:Set(tonumber(b.classPowerOutline) or 1)
    end
    if cpChargedCheck then
        cpChargedCheck:SetChecked(b.showChargedComboPoints ~= false)
        if cpChargedCheck.__msufToggleUpdate then cpChargedCheck.__msufToggleUpdate() end
    end
    if cpTextCheck then
        cpTextCheck:SetChecked(b.classPowerShowText == true)
        if cpTextCheck.__msufToggleUpdate then cpTextCheck.__msufToggleUpdate() end
    end
    if cpAnchorCooldownCheck then
        cpAnchorCooldownCheck:SetChecked(b.classPowerAnchorToCooldown == true)
        if cpAnchorCooldownCheck.__msufToggleUpdate then cpAnchorCooldownCheck.__msufToggleUpdate() end
    end

    -- AltMana
    if amShowCheck then
        amShowCheck:SetChecked(b.showAltMana ~= false)
        if amShowCheck.__msufToggleUpdate then amShowCheck.__msufToggleUpdate() end
    end
    if amHeightRow then
        amHeightRow:Set(tonumber(b.altManaHeight) or 4)
    end
    if amOffsetRow then
        amOffsetRow:Set(tonumber(b.altManaOffsetY) or -2)
    end

    -- Enable/disable sub-controls based on master toggle
    local cpOn = (b.showClassPower ~= false)
    local amOn = (b.showAltMana ~= false)

    local function SetEnabled(ctrl, on)
        if not ctrl then return end
        if on then
            if ctrl.Enable then ctrl:Enable() end
            if ctrl.EnableMouse then ctrl:EnableMouse(true) end
            if ctrl.SetAlpha then ctrl:SetAlpha(1) end
        else
            if ctrl.Disable then ctrl:Disable() end
            if ctrl.EnableMouse then ctrl:EnableMouse(false) end
            if ctrl.ClearFocus then ctrl:ClearFocus() end
            if ctrl.SetAlpha then ctrl:SetAlpha(0.45) end
        end
    end
    local function SetLabelEnabled(fs, on)
        if not fs then return end
        if on then fs:SetTextColor(0.85, 0.85, 0.85) else fs:SetTextColor(0.35, 0.35, 0.35) end
    end

    SetEnabled(cpColorCheck, cpOn)
    SetEnabled(cpChargedCheck, cpOn)
    SetEnabled(cpTextCheck, cpOn)
    if cpHeightRow   then cpHeightRow:SetEnabled(cpOn)   end
    -- cpWidthRow enabled/disabled by widthMode sync above
    if cpXOffsetRow  then cpXOffsetRow:SetEnabled(cpOn)  end
    if cpYOffsetRow  then cpYOffsetRow:SetEnabled(cpOn)  end
    if cpBgAlphaRow  then cpBgAlphaRow:SetEnabled(cpOn)  end
    if cpTickRow     then cpTickRow:SetEnabled(cpOn)     end
    if cpOutlineRow  then cpOutlineRow:SetEnabled(cpOn)  end

    if amHeightRow then amHeightRow:SetEnabled(amOn) end
    if amOffsetRow then amOffsetRow:SetEnabled(amOn) end
end

-- ============================================================================
-- Hook: Bars tab OnShow + SyncBarsTabToggles wrapping
-- ============================================================================
local _hooked = false

local function HookBarsTabs()
    if _hooked then return end

    local barGroupHost = _G["MSUF_BarsMenuHost"]
    if not barGroupHost then return end

    _hooked = true

    -- Build on first show of the Bars tab
    barGroupHost:HookScript("OnShow", function()
        BuildClassPowerOptions()
        SyncClassPowerToggles()
    end)

    -- Also hook the inner content frame for sync-on-show (same as Core does)
    local barGroup = _G["MSUF_BarsMenuContent"]
    if barGroup and barGroup.HookScript then
        barGroup:HookScript("OnShow", function()
            -- Delayed so original MSUF_SyncBarsTabToggles runs first
            C_Timer.After(0, SyncClassPowerToggles)
        end)
    end

    -- If bars tab is already visible right now, build + sync immediately
    if barGroupHost.IsVisible and barGroupHost:IsVisible() then
        BuildClassPowerOptions()
        SyncClassPowerToggles()
    end
end

-- ============================================================================
-- Entry: hook into CreateOptionsPanel (global) so we attach AFTER the UI is built.
-- CreateOptionsPanel() is called from the slash menu on first /msuf.
-- ============================================================================
do
    -- 1) Already built? (e.g. file loaded after options panel)
    if _G["MSUF_BarsMenuHost"] then
        HookBarsTabs()
    end

    -- 2) Not built yet: wrap CreateOptionsPanel to hook after it runs.
    if not _hooked and type(_G.CreateOptionsPanel) == "function" then
        hooksecurefunc(_G, "CreateOptionsPanel", function()
            -- CreateOptionsPanel just finished; MSUF_BarsMenuHost now exists.
            HookBarsTabs()
        end)
    end
end

-- ============================================================================
-- Public: allow MSUF_ClassPower.lua to trigger options sync
-- ============================================================================
_G.MSUF_ClassPower_SyncOptions = SyncClassPowerToggles
