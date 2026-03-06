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

-- SharedMedia statusbar texture dropdown init (1:1 with Options_Core)
local MSUF_InitStatusbarTextureDropdown = _G.MSUF_InitStatusbarTextureDropdown
local MSUF_SyncStatusbarTextureDropdown = _G.MSUF_SyncStatusbarTextureDropdown

-- Dropdown scroll helpers (exported from Options_Core)
-- Makes large SharedMedia dropdown lists scrollable (mousewheel + scrollbar).
local MSUF_MakeDropdownScrollable = (ns and ns.MSUF_MakeDropdownScrollable) or _G.MSUF_MakeDropdownScrollable

-- Expand dropdown click area so the whole dropdown is clickable (not only the arrow).
-- Exported by Options_Core.
local MSUF_ExpandDropdownClickArea = (ns and ns.MSUF_ExpandDropdownClickArea) or _G.MSUF_ExpandDropdownClickArea

-- Stepper modifier support (match Options_Player behavior):
-- default = baseStep, Shift = x5, Ctrl = x10, Alt = grid step (Edit Mode)
-- (Alt > Ctrl > Shift priority)
local function MSUF_GetCurrentGridStep()
    local MIN, MAX = 8, 64
    local step
    local slider = _G and _G["MSUF_EditModeGridSlider"]
    if slider and slider.GetValue then
        step = slider:GetValue()
    elseif MSUF_DB and MSUF_DB.general and type(MSUF_DB.general.editModeGridStep) == "number" then
        step = MSUF_DB.general.editModeGridStep
    else
        step = 20
    end
    step = tonumber(step) or 20
    if step < MIN then step = MIN end
    if step > MAX then step = MAX end
    return step
end

local function MSUF_GetModifierStep(baseStep)
    baseStep = tonumber(baseStep) or 1
    if IsAltKeyDown and IsAltKeyDown() then
        return MSUF_GetCurrentGridStep()
    end
    local mult = 1
    if IsControlKeyDown and IsControlKeyDown() then
        mult = 10
    elseif IsShiftKeyDown and IsShiftKeyDown() then
        mult = 5
    end
    return baseStep * mult
end



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

local function MakeCheck(name, label, parent, maxWidth)
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    local fs = _G[name .. "Text"]
    if fs then
        fs:SetText(TR(label or ""))
        -- i18n safety: clamp text width so long translations don't overflow column
        if maxWidth and fs.SetWidth then
            fs:SetWidth(maxWidth)
            if fs.SetWordWrap then fs:SetWordWrap(false) end
            if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
        end
    end
    cb.text = fs
    StyleToggleText(cb)
    StyleCheckmark(cb)
    return cb
end


-- ============================================================================
-- Labeled slider helper (copied from Options_Core style, trimmed for reuse)
-- ============================================================================
local function MSUF_SetLabeledSliderValue(slider, value)
    if not slider then return end
    slider.MSUF_SkipCallback = true
    slider:SetValue(value)
    slider.MSUF_SkipCallback = nil
    if slider.editBox and slider.editBox.SetText and (not slider.editBox:HasFocus()) then
        local cur = slider:GetValue()
        local step = slider.step or 1
        local formatted
        if step >= 1 then
            cur = math.floor((tonumber(cur) or 0) + 0.5)
            formatted = tostring(cur)
        else
            formatted = string.format("%.2f", tonumber(cur) or 0)
        end
        slider.editBox:SetText(formatted)
    end
end

local function CreateLabeledSlider(name, label, parent, minVal, maxVal, step)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider.minVal = minVal
    slider.maxVal = maxVal
    slider.step   = step

    local low  = _G[name .. "Low"]
    local high = _G[name .. "High"]
    local text = _G[name .. "Text"]
    if low  then low:SetText(tostring(minVal)) end
    if high then high:SetText(tostring(maxVal)) end
    if text then text:SetText(TR(label or "")) end

    -- Edit box + +/- buttons (matches MSUF stepper look used elsewhere)
    local eb = CreateFrame("EditBox", name .. "Input", parent, "InputBoxTemplate")
    eb:SetSize(60, 18)
    eb:SetAutoFocus(false)
    eb:SetPoint("TOP", slider, "BOTTOM", 0, -6)
    eb:SetJustifyH("CENTER")
    eb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local v = tonumber(self:GetText())
        if not v then
            MSUF_SetLabeledSliderValue(slider, slider:GetValue())
            return
        end
        if v < minVal then v = minVal elseif v > maxVal then v = maxVal end
        v = math_floor((v / step) + 0.5) * step
        MSUF_SetLabeledSliderValue(slider, v)
        if slider.onValueChanged then slider.onValueChanged(slider, v) end
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    slider.editBox = eb

    local minus = CreateFrame("Button", name .. "Minus", parent, "UIPanelButtonTemplate")
    minus:SetSize(18, 18)
    minus:SetPoint("RIGHT", eb, "LEFT", -4, 0)
    minus:SetText("-")

    local plus = CreateFrame("Button", name .. "Plus", parent, "UIPanelButtonTemplate")
    plus:SetSize(18, 18)
    plus:SetPoint("LEFT", eb, "RIGHT", 4, 0)
    plus:SetText("+")

    slider.minusButton = minus
    slider.plusButton  = plus

    local function Step(delta)
        local v = tonumber(slider:GetValue()) or 0
        v = v + delta
        if v < minVal then v = minVal elseif v > maxVal then v = maxVal end
        v = math_floor((v / step) + 0.5) * step
        MSUF_SetLabeledSliderValue(slider, v)
        if slider.onValueChanged then slider.onValueChanged(slider, v) end
    end
    minus:SetScript("OnClick", function()
        Step(-MSUF_GetModifierStep(step))
    end)
    plus:SetScript("OnClick", function()
        Step(MSUF_GetModifierStep(step))
    end)

    slider:HookScript("OnValueChanged", function(self, value)
        if self.MSUF_SkipCallback then return end
        MSUF_SetLabeledSliderValue(self, value)
        if self.onValueChanged then self.onValueChanged(self, value) end
    end)

    return slider
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

-- Compact slider factory: label + slider + editbox + [-][+] + suffix in one row.
-- Returns { slider=, editBox=, label=, minus=, plus= } table.
-- labelW: fixed label width for column alignment (nil = auto)
local function MakeCompactSlider(name, labelText, parent, minVal, maxVal, step, dbKey, anchorTo, anchorPt, oX, oY, sliderW, labelW)
    sliderW = sliderW or 120
    step = step or 1
    local row = {}

    -- Label (fixed width for column alignment)
    local lbl = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    lbl:SetPoint(anchorPt or "TOPLEFT", anchorTo or parent, anchorPt == "TOPLEFT" and "BOTTOMLEFT" or "BOTTOMLEFT", oX or 0, oY or -10)
    lbl:SetText(TR(labelText))
    lbl:SetTextColor(0.85, 0.85, 0.85)
    if labelW then
        lbl:SetWidth(labelW)
        lbl:SetJustifyH("LEFT")
    end
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

    -- Sync slider → editbox → DB
    local _isAlphaKey = (dbKey == "classPowerBgAlpha"
                      or dbKey == "classPowerFilledAlpha"
                      or dbKey == "classPowerEmptyAlpha")
    local function WriteDB(val)
        if type(MSUF_DB) == "table" then
            MSUF_DB.bars = MSUF_DB.bars or {}
            if _isAlphaKey then
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

    -- [-] [+] stepper buttons (MSUF dark style, matches Options_Player X/Y)
    local StyleBtn = _G.MSUF_StyleSmallButton
    local minus = CreateFrame("Button", name .. "Minus", parent)
    minus:SetPoint("LEFT", eb, "RIGHT", 3, 0)
    if StyleBtn then StyleBtn(minus, false) else minus:SetSize(20, 20) end
    row.minus = minus

    local plus = CreateFrame("Button", name .. "Plus", parent)
    plus:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    if StyleBtn then StyleBtn(plus, true) else plus:SetSize(20, 20) end
    row.plus = plus

    local function StepValue(sign)
        local v = tonumber(eb:GetText()) or (s:GetValue() or minVal)
        local delta = MSUF_GetModifierStep(step)
        v = v + sign * delta
        if step >= 1 then v = math_floor(v + 0.5) end
        if v < minVal then v = minVal elseif v > maxVal then v = maxVal end
        eb:SetText(tostring(v))
        s:SetValue(v)
    end
    minus:SetScript("OnClick", function() StepValue(-1) end)
    plus:SetScript("OnClick",  function() StepValue(1) end)

    -- Set method: update both slider + editbox without triggering OnValueChanged
    function row:Set(val)
        if step >= 1 then val = math_floor(val + 0.5) end
        eb:SetText(tostring(val))
        s:SetValue(val)
    end

    function row:SetEnabled(on)
        if on then
            s:Enable(); eb:EnableMouse(true); eb:SetAlpha(1)
            lbl:SetTextColor(0.85, 0.85, 0.85)
            minus:EnableMouse(true);  minus:SetAlpha(1)
            plus:EnableMouse(true);   plus:SetAlpha(1)
        else
            s:Disable(); eb:EnableMouse(false); eb:ClearFocus(); eb:SetAlpha(0.45)
            lbl:SetTextColor(0.35, 0.35, 0.35)
            minus:EnableMouse(false); minus:SetAlpha(0.35)
            plus:EnableMouse(false);  plus:SetAlpha(0.35)
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
local cpRuneTimeCheck  -- DK: show rune time text
local cpPredictionCheck -- "Show resource prediction (Warlock / Balance Druid)"
local cpAnchorCooldownCheck -- "Anchor to Essential Cooldown"
local cpFillReverseCheck    -- "Fill right-to-left"
local cpEleMaelCheck        -- "Show Maelstrom bar (Elemental)"
local cpEbonMightCheck      -- "Show Ebon Might timer (Aug)"
local cpFilledAlphaRow      -- slider row: Filled pip alpha
local cpEmptyAlphaRow       -- slider row: Empty pip alpha
local cpFontSizeRow         -- slider row: Font size
local cpTextOffsetXRow      -- slider row: Text X offset
local cpTextOffsetYRow      -- slider row: Text Y offset
local cpGapRow              -- slider row: Gap between pips
local cpHideOOCCheck        -- "Hide out of combat"
local cpHideFullCheck       -- "Hide when full"
local cpHideEmptyCheck      -- "Hide when empty"
local amShowCheck      -- "Show alternative mana bar"
local amHeightRow      -- slider row: Height
local amOffsetRow      -- slider row: Y offset
local dpbWidthModeDrop -- dropdown: DPB Match width to CDM

-- ============================================================================
-- Build (called once; idempotent)
-- ============================================================================
local _built = false

-- Build the Class Power options panel anchored under a given left/right panel pair.
-- If no names are provided, defaults to the Bars tab panel pair.
local function BuildClassPowerOptions(leftName, rightName)
    if _built then return end

    leftName  = leftName  or "MSUF_BarsMenuPanelLeft"
    rightName = rightName or "MSUF_BarsMenuPanelRight"

    local rightPanel = _G[rightName]
    local leftPanel  = _G[leftName]
    if not (rightPanel and leftPanel) then return end

    _built = true

    -- ── Third panel (full width, below both columns) ──
    cpPanel = CreateFrame("Frame", "MSUF_ClassPowerOptionsPanel", leftPanel:GetParent(), "BackdropTemplate")
    local totalW = leftPanel:GetWidth() + rightPanel:GetWidth()
    cpPanel:SetSize(totalW, 788)
    cpPanel:SetPoint("TOPLEFT", leftPanel, "BOTTOMLEFT", 0, -10)
    cpPanel:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    cpPanel:SetBackdropColor(0, 0, 0, 0.20)
    cpPanel:SetBackdropBorderColor(1, 1, 1, 0.15)

    local colW = math_floor(totalW / 2)
    local PAD_X, PAD_Y = 16, -12
    local LINE_W = colW - 24

    -- =====================================================================
    -- LEFT COLUMN: Class Power — Position & Behavior
    -- =====================================================================
    local cpHeader = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    cpHeader:SetPoint("TOPLEFT", cpPanel, "TOPLEFT", PAD_X, PAD_Y)
    cpHeader:SetText(TR("Class Power"))
    if cpHeader.SetTextColor then cpHeader:SetTextColor(1, 1, 1) end
    cpPanel._cpHeader = cpHeader

    local cpSub = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cpSub:SetPoint("TOPLEFT", cpHeader, "BOTTOMLEFT", 0, -2)
    cpSub:SetText(TR("Combo Points, Holy Power, Soul Shards, Chi, Essence, Runes"))
    cpSub:SetTextColor(0.55, 0.55, 0.55)
    cpSub:SetWidth(colW - 32)
    cpSub:SetJustifyH("LEFT")

    local DIVIDER_Y = -54
    local cpLine = cpPanel:CreateTexture(nil, "ARTWORK")
    cpLine:SetColorTexture(1, 1, 1, 0.20)
    cpLine:SetHeight(1)
    cpLine:SetPoint("TOPLEFT", cpPanel, "TOPLEFT", 0, DIVIDER_Y)
    cpLine:SetWidth(LINE_W)

    -- [x] Show class power
    cpShowCheck = MakeCheck("MSUF_ClassPowerShowCheck", "Show class power", cpPanel, L_CHECK_TW)
    cpShowCheck:SetPoint("TOPLEFT", cpLine, "BOTTOMLEFT", PAD_X, -10)

    -- Column alignment: fixed label width per column
    local L_LABEL_W = 62   -- left column: Height, Width, X offset, Y offset
    local R_LABEL_W = 70   -- right column: BG opacity, Separator, Outline, Height, Y offset

    -- Max text width for checkboxes (colW minus checkbox ~26px minus padding)
    -- Prevents long i18n strings from overflowing into the adjacent column.
    local L_CHECK_TW = colW - 42
    local R_CHECK_TW = colW - 42

    -- Height
    cpHeightRow = MakeCompactSlider("MSUF_CPHeight", "Height", cpPanel, 2, 30, 1, "classPowerHeight",
        cpShowCheck, "TOPLEFT", 0, -10, nil, L_LABEL_W)

    -- Match width dropdown
    local cpWidthModeLabel = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cpWidthModeLabel:SetPoint("TOPLEFT", cpHeightRow.label, "BOTTOMLEFT", 0, -10)
    cpWidthModeLabel:SetText(TR("Match width"))
    cpWidthModeLabel:SetTextColor(0.85, 0.85, 0.85)
    cpWidthModeLabel:SetWidth(L_LABEL_W)
    cpWidthModeLabel:SetJustifyH("LEFT")
    cpPanel._cpWidthModeLabel = cpWidthModeLabel

    cpWidthModeDrop = CreateFrame("Frame", "MSUF_CPWidthModeDrop", cpPanel, "UIDropDownMenuTemplate")
    cpWidthModeDrop:SetPoint("LEFT", cpWidthModeLabel, "RIGHT", 4, -2)
    UIDropDownMenu_SetWidth(cpWidthModeDrop, 155)
    if MSUF_ExpandDropdownClickArea then MSUF_ExpandDropdownClickArea(cpWidthModeDrop) end

    local WIDTH_MODE_OPTIONS = {
        { key = "player",       label = TR("Player frame") },
        { key = "cooldown",     label = TR("Essential Cooldowns") },
        { key = "utility",      label = TR("Utility Cooldowns") },
        { key = "tracked_buffs",label = TR("Tracked Buffs") },
        { key = "custom",       label = TR("Custom") },
    }

    -- Width (custom only)
    cpWidthRow = MakeCompactSlider("MSUF_CPWidth", "Width", cpPanel, 30, 800, 1, "classPowerWidth",
        cpWidthModeLabel, "TOPLEFT", 0, -12, nil, L_LABEL_W)

    -- X / Y offset
    cpXOffsetRow = MakeCompactSlider("MSUF_CPXOffset", "X offset", cpPanel, -1000, 1000, 1, "classPowerOffsetX",
        cpWidthRow.label, "TOPLEFT", 0, -10, nil, L_LABEL_W)

    cpYOffsetRow = MakeCompactSlider("MSUF_CPYOffset", "Y offset", cpPanel, -1000, 1000, 1, "classPowerOffsetY",
        cpXOffsetRow.label, "TOPLEFT", 0, -10, nil, L_LABEL_W)

    -- Wire width mode dropdown
    local function OnWidthModeChanged(mode)
        if type(MSUF_DB) == "table" then
            MSUF_DB.bars = MSUF_DB.bars or {}
            MSUF_DB.bars.classPowerWidthMode = mode
        end
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
            function(v) end,
            function(val) OnWidthModeChanged(val) end,
            155
        )
    end

    -- Checkboxes: behavior toggles
    cpAnchorCooldownCheck = MakeCheck("MSUF_ClassPowerAnchorCooldownCheck", TR("Anchor to Essential Cooldown"), cpPanel, L_CHECK_TW)
    cpAnchorCooldownCheck:SetPoint("TOPLEFT", cpYOffsetRow.label, "BOTTOMLEFT", 0, -12)

    cpChargedCheck = MakeCheck("MSUF_ShowChargedCPCheck", TR("Show empowered combo points"), cpPanel, L_CHECK_TW)
    cpChargedCheck:SetPoint("TOPLEFT", cpAnchorCooldownCheck, "BOTTOMLEFT", 0, -4)

    cpTextCheck = MakeCheck("MSUF_ClassPowerTextCheck", TR("Show resource text"), cpPanel, L_CHECK_TW)
    cpTextCheck:SetPoint("TOPLEFT", cpChargedCheck, "BOTTOMLEFT", 0, -4)

    cpRuneTimeCheck = MakeCheck("MSUF_RuneTimeTextCheck", TR("Show rune time (per rune)"), cpPanel, L_CHECK_TW)
    cpRuneTimeCheck:SetPoint("TOPLEFT", cpTextCheck, "BOTTOMLEFT", 0, -4)

    cpFillReverseCheck = MakeCheck("MSUF_ClassPowerReverseCheck", TR("Fill right-to-left"), cpPanel, L_CHECK_TW)
    cpFillReverseCheck:SetPoint("TOPLEFT", cpRuneTimeCheck, "BOTTOMLEFT", 0, -4)

    cpEleMaelCheck = MakeCheck("MSUF_ClassPowerEleMaelCheck", TR("Show Maelstrom bar (Elemental)"), cpPanel, L_CHECK_TW)
    cpEleMaelCheck:SetPoint("TOPLEFT", cpFillReverseCheck, "BOTTOMLEFT", 0, -4)

    cpEbonMightCheck = MakeCheck("MSUF_ClassPowerEbonMightCheck", TR("Show Ebon Might timer (Aug)"), cpPanel, L_CHECK_TW)
    cpEbonMightCheck:SetPoint("TOPLEFT", cpEleMaelCheck, "BOTTOMLEFT", 0, -4)

    cpPredictionCheck = MakeCheck("MSUF_ClassPowerPredictionCheck", TR("Show resource prediction"), cpPanel, L_CHECK_TW)
    cpPredictionCheck:SetPoint("TOPLEFT", cpEbonMightCheck, "BOTTOMLEFT", 0, -4)

    -- =====================================================================
    -- LEFT COLUMN BOTTOM: Detached Power Bar — Texture Overrides
    -- =====================================================================
    local dpbDivider = cpPanel:CreateTexture(nil, "ARTWORK")
    dpbDivider:SetColorTexture(1, 1, 1, 0.12)
    dpbDivider:SetHeight(1)
    dpbDivider:SetPoint("TOPLEFT", cpPredictionCheck, "BOTTOMLEFT", -PAD_X, -10)
    dpbDivider:SetWidth(LINE_W)

    local dpbHeader = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    dpbHeader:SetPoint("TOPLEFT", dpbDivider, "BOTTOMLEFT", PAD_X, -8)
    dpbHeader:SetText(TR("Detached Power Bar"))
    if dpbHeader.SetTextColor then dpbHeader:SetTextColor(1, 1, 1) end
    cpPanel._dpbHeader = dpbHeader

    local dpbSub = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    dpbSub:SetPoint("TOPLEFT", dpbHeader, "BOTTOMLEFT", 0, -2)
    dpbSub:SetText(TR("Only applies when power bar is detached"))
    dpbSub:SetTextColor(0.55, 0.55, 0.55)
    dpbSub:SetWidth(colW - 32)
    dpbSub:SetJustifyH("LEFT")
    cpPanel._dpbSub = dpbSub

    -- Width mode dropdown
    local dpbWidthModeLabel = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    dpbWidthModeLabel:SetPoint("TOPLEFT", dpbSub, "BOTTOMLEFT", 0, -8)
    dpbWidthModeLabel:SetText(TR("Match width"))
    dpbWidthModeLabel:SetTextColor(0.85, 0.85, 0.85)
    dpbWidthModeLabel:SetWidth(L_LABEL_W)
    dpbWidthModeLabel:SetJustifyH("LEFT")
    cpPanel._dpbWidthModeLabel = dpbWidthModeLabel

    dpbWidthModeDrop = CreateFrame("Frame", "MSUF_DPBWidthModeDrop", cpPanel, "UIDropDownMenuTemplate")
    dpbWidthModeDrop:SetPoint("LEFT", dpbWidthModeLabel, "RIGHT", 4, -2)
    UIDropDownMenu_SetWidth(dpbWidthModeDrop, 155)
    if MSUF_ExpandDropdownClickArea then MSUF_ExpandDropdownClickArea(dpbWidthModeDrop) end

    local DPB_WIDTH_MODE_OPTIONS = {
        { key = "manual",       label = TR("Manual") },
        { key = "cooldown",     label = TR("Essential Cooldowns") },
        { key = "utility",      label = TR("Utility Cooldowns") },
        { key = "tracked_buffs",label = TR("Tracked Buffs") },
    }

    local function OnDPBWidthModeChanged(mode)
        if type(MSUF_DB) == "table" then
            MSUF_DB.bars = MSUF_DB.bars or {}
            MSUF_DB.bars.detachedPowerBarWidthMode = (mode ~= "manual") and mode or nil
        end
        if type(_G.MSUF_ApplyPowerBarEmbedLayout_All) == "function" then
            _G.MSUF_ApplyPowerBarEmbedLayout_All()
        end
    end

    local InitDPBDrop = _G.MSUF_InitSimpleDropdown
    if InitDPBDrop then
        InitDPBDrop(dpbWidthModeDrop, DPB_WIDTH_MODE_OPTIONS,
            function()
                return (MSUF_DB and MSUF_DB.bars and MSUF_DB.bars.detachedPowerBarWidthMode) or "manual"
            end,
            function(v) end,
            function(val) OnDPBWidthModeChanged(val) end,
            155
        )
    end

    local DPB_TEX_DROP_W = 170

    -- FG texture
    local dpbFgLabel = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    dpbFgLabel:SetPoint("TOPLEFT", dpbWidthModeLabel, "BOTTOMLEFT", 0, -14)
    dpbFgLabel:SetText(TR("Foreground texture"))
    dpbFgLabel:SetTextColor(0.85, 0.85, 0.85)
    cpPanel._dpbFgLabel = dpbFgLabel

    local dpbFgDrop = CreateFrame("Frame", "MSUF_DPBFgTextureDropdown", cpPanel, "UIDropDownMenuTemplate")
    dpbFgDrop:SetPoint("TOPLEFT", dpbFgLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(dpbFgDrop, DPB_TEX_DROP_W)
    dpbFgDrop._msufTweakBarTexturePreview = true
    if MSUF_ExpandDropdownClickArea then MSUF_ExpandDropdownClickArea(dpbFgDrop) end
    if MSUF_MakeDropdownScrollable then MSUF_MakeDropdownScrollable(dpbFgDrop, 12) end

    -- BG texture
    local dpbBgLabel = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    dpbBgLabel:SetPoint("TOPLEFT", dpbFgLabel, "BOTTOMLEFT", 0, -34)
    dpbBgLabel:SetText(TR("Background texture"))
    dpbBgLabel:SetTextColor(0.85, 0.85, 0.85)
    cpPanel._dpbBgLabel = dpbBgLabel

    local dpbBgDrop = CreateFrame("Frame", "MSUF_DPBBgTextureDropdown", cpPanel, "UIDropDownMenuTemplate")
    dpbBgDrop:SetPoint("TOPLEFT", dpbBgLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(dpbBgDrop, DPB_TEX_DROP_W)
    dpbBgDrop._msufTweakBarTexturePreview = true
    if MSUF_ExpandDropdownClickArea then MSUF_ExpandDropdownClickArea(dpbBgDrop) end
    if MSUF_MakeDropdownScrollable then MSUF_MakeDropdownScrollable(dpbBgDrop, 12) end

    
    -- Power bar outline (Detached Power Bar) — moved here from Options_Core (Bars).
    -- IMPORTANT: Must look like the other compact X/Y sliders (inline label + slider + editbox + [-][+]).
    local function CreateCompactIntRow(name, labelText, parent, minVal, maxVal, step, anchorTo, anchorPt, oX, oY, sliderW, labelW)
        sliderW = sliderW or 150
        step = step or 1
        local row = {}

        local lbl = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        lbl:SetPoint(anchorPt or "TOPLEFT", anchorTo or parent, anchorPt == "TOPLEFT" and "BOTTOMLEFT" or "BOTTOMLEFT", oX or 0, oY or -10)
        lbl:SetText(TR(labelText))
        lbl:SetTextColor(0.85, 0.85, 0.85)
        if labelW then
            lbl:SetWidth(labelW)
            lbl:SetJustifyH("LEFT")
        end
        row.label = lbl

        local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
        s:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
        s:SetSize(sliderW, 14)
        s:SetMinMaxValues(minVal, maxVal)
        s:SetValueStep(step)
        s:SetObeyStepOnDrag(true)
        local track = s:CreateTexture(nil, "BACKGROUND")
        track:SetColorTexture(0.06, 0.06, 0.06, 1)
        track:SetPoint("TOPLEFT", s, "TOPLEFT", 0, -3)
        track:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 0, 3)
        s._track = track
        s:HookScript("OnEnter", function(self) if self._track then self._track:SetColorTexture(0.20, 0.20, 0.20, 1) end end)
        s:HookScript("OnLeave", function(self) if self._track then self._track:SetColorTexture(0.06, 0.06, 0.06, 1) end end)
        local thumb = s:GetThumbTexture()
        if thumb then thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal"); thumb:SetSize(10, 18) end
        local lo = _G[name .. "Low"];  if lo  then lo:SetText("") end
        local hi = _G[name .. "High"]; if hi  then hi:SetText("") end
        local tx = _G[name .. "Text"]; if tx  then tx:SetText("") end
        row.slider = s

        local eb = CreateFrame("EditBox", name .. "EB", parent, "InputBoxTemplate")
        eb:SetSize(44, 18)
        eb:SetAutoFocus(false)
        eb:SetPoint("LEFT", s, "RIGHT", 6, 0)
        eb:SetJustifyH("CENTER")
        eb:SetFontObject(GameFontHighlightSmall)
        eb:SetTextColor(1, 1, 1, 1)
        row.editBox = eb

        local StyleBtn = _G.MSUF_StyleSmallButton
        local minus = CreateFrame("Button", name .. "Minus", parent)
        minus:SetPoint("LEFT", eb, "RIGHT", 3, 0)
        if StyleBtn then StyleBtn(minus, false) else minus:SetSize(20, 20) end
        row.minus = minus

        local plus = CreateFrame("Button", name .. "Plus", parent)
        plus:SetPoint("LEFT", minus, "RIGHT", 2, 0)
        if StyleBtn then StyleBtn(plus, true) else plus:SetSize(20, 20) end
        row.plus = plus

        local function Clamp(v)
            v = tonumber(v)
            if type(v) ~= "number" then return nil end
            v = math_floor(v + 0.5)
            if v < minVal then v = minVal elseif v > maxVal then v = maxVal end
            return v
        end

        function row:Set(val)
            val = Clamp(val) or minVal
            eb:SetText(tostring(val))
            s:SetValue(val)
        end

        function row:SetEnabled(on)
            local a = on and 1.0 or 0.35
            s:SetAlpha(a)
            eb:SetAlpha(a)
            minus:SetAlpha(a)
            plus:SetAlpha(a)
            if on then
                s:Enable(); eb:EnableMouse(true)
                minus:EnableMouse(true); plus:EnableMouse(true)
                lbl:SetTextColor(0.85, 0.85, 0.85)
            else
                s:Disable(); eb:EnableMouse(false); eb:ClearFocus()
                minus:EnableMouse(false); plus:EnableMouse(false)
                lbl:SetTextColor(0.35, 0.35, 0.35)
            end
        end

        row.onValueChanged = nil

        s:SetScript("OnValueChanged", function(_, val)
            val = Clamp(val) or minVal
            eb:SetText(tostring(val))
            if row.onValueChanged then row.onValueChanged(val) end
        end)

        local function ApplyEB()
            local v = Clamp(eb:GetText())
            if not v then
                eb:SetText(tostring(Clamp(s:GetValue()) or minVal))
                return
            end
            eb:SetText(tostring(v))
            s:SetValue(v)
        end
        eb:SetScript("OnEnterPressed", function(self) ApplyEB(); self:ClearFocus() end)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        eb:SetScript("OnEditFocusLost", function() ApplyEB() end)

        local function StepValue(sign)
            local cur = Clamp(eb:GetText()) or Clamp(s:GetValue()) or minVal
            local delta = MSUF_GetModifierStep(step)
            cur = cur + sign * delta
            if cur < minVal then cur = minVal elseif cur > maxVal then cur = maxVal end
            eb:SetText(tostring(cur))
            s:SetValue(cur)
        end
        minus:SetScript("OnClick", function() StepValue(-1) end)
        plus:SetScript("OnClick",  function() StepValue(1) end)

        return row
    end

    local dpbOutlineRow = CreateCompactIntRow(
        "MSUF_DPBOutlineThicknessSlider",
        "Power bar outline",
        cpPanel,
        0, 6, 1,
        dpbBgDrop, "TOPLEFT", 16, -26,
        150, 110
    )

    do
        local bars = (MSUF_DB and MSUF_DB.bars) or {}
        local t = tonumber(bars.detachedPowerBarOutline)
        if type(t) ~= "number" then
            -- Default: same as main outline (or 1).
            t = tonumber(bars.barOutlineThickness) or 1
        end
        if type(t) ~= "number" then t = 1 end
        t = math_floor(t + 0.5)
        if t < 0 then t = 0 elseif t > 6 then t = 6 end
        dpbOutlineRow:Set(t)
    end

    dpbOutlineRow.onValueChanged = function(value)
        if type(MSUF_DB) ~= "table" then return end
        MSUF_DB.bars = MSUF_DB.bars or {}
        MSUF_DB.bars.detachedPowerBarOutline = value
        if type(_G.MSUF_ApplyBarOutlineThickness_All) == "function" then
            _G.MSUF_ApplyBarOutlineThickness_All()
        end
    end

    -- Grey out when no power bar is detached (any unit).
    local function MSUF_RefreshDPBOutlineSliderState()
        local anyDetached = false
        if type(MSUF_DB) == "table" then
            for _, key in ipairs({ "player", "target", "focus" }) do
                local conf = MSUF_DB[key]
                if conf and conf.powerBarDetached == true then
                    anyDetached = true
                    break
                end
            end
        end
        if dpbOutlineRow and dpbOutlineRow.SetEnabled then
            dpbOutlineRow:SetEnabled(anyDetached)
        end
    end
    _G.MSUF_RefreshDPBOutlineSliderState = MSUF_RefreshDPBOutlineSliderState
    if dpbOutlineRow and dpbOutlineRow.slider and dpbOutlineRow.slider.HookScript then
        dpbOutlineRow.slider:HookScript("OnShow", MSUF_RefreshDPBOutlineSliderState)
    end
    _G.MSUF_DPBOutlineSlider = dpbOutlineRow

-- =====================================================================
    -- RIGHT COLUMN TOP: Style — Visual Appearance
    -- =====================================================================
    local styleHeader = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    styleHeader:SetPoint("TOPLEFT", cpPanel, "TOPLEFT", colW + PAD_X, PAD_Y)
    styleHeader:SetText(TR("Style"))
    if styleHeader.SetTextColor then styleHeader:SetTextColor(1, 1, 1) end
    cpPanel._styleHeader = styleHeader

    local styleSub = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    styleSub:SetPoint("TOPLEFT", styleHeader, "BOTTOMLEFT", 0, -2)
    styleSub:SetText(TR("Colors, textures & visual tweaks"))
    styleSub:SetTextColor(0.55, 0.55, 0.55)
    styleSub:SetWidth(colW - 32)
    styleSub:SetJustifyH("LEFT")

    local styleLine = cpPanel:CreateTexture(nil, "ARTWORK")
    styleLine:SetColorTexture(1, 1, 1, 0.20)
    styleLine:SetHeight(1)
    styleLine:SetPoint("TOPLEFT", cpPanel, "TOPLEFT", colW, DIVIDER_Y)
    styleLine:SetWidth(LINE_W)

    -- [x] Color by resource type
    cpColorCheck = MakeCheck("MSUF_ClassPowerColorCheck", "Color by resource type", cpPanel, R_CHECK_TW)
    cpColorCheck:SetPoint("TOPLEFT", styleLine, "BOTTOMLEFT", PAD_X, -10)

    -- BG opacity / Separator / Outline
    cpFontSizeRow = MakeCompactSlider("MSUF_CPFontSize", "Font size", cpPanel, 6, 32, 1, "classPowerFontSize",
        cpColorCheck, "TOPLEFT", 0, -10, nil, R_LABEL_W)

    cpTextOffsetXRow = MakeCompactSlider("MSUF_CPTextOffsetX", "Text X", cpPanel, -200, 200, 1, "classPowerTextOffsetX",
        cpFontSizeRow.label, "TOPLEFT", 0, -10, nil, R_LABEL_W)

    cpTextOffsetYRow = MakeCompactSlider("MSUF_CPTextOffsetY", "Text Y", cpPanel, -200, 200, 1, "classPowerTextOffsetY",
        cpTextOffsetXRow.label, "TOPLEFT", 0, -10, nil, R_LABEL_W)

    cpBgAlphaRow = MakeCompactSlider("MSUF_CPBgAlpha", "BG opacity", cpPanel, 0, 100, 1, "classPowerBgAlpha",
        cpTextOffsetYRow.label, "TOPLEFT", 0, -10, nil, R_LABEL_W)

    cpTickRow = MakeCompactSlider("MSUF_CPTick", "Separator", cpPanel, 0, 4, 1, "classPowerTickWidth",
        cpBgAlphaRow.label, "TOPLEFT", 0, -10, nil, R_LABEL_W)

    cpOutlineRow = MakeCompactSlider("MSUF_CPOutline", "Outline", cpPanel, 0, 4, 1, "classPowerOutline",
        cpTickRow.label, "TOPLEFT", 0, -10, nil, R_LABEL_W)

    -- Filled / Empty alpha
    cpFilledAlphaRow = MakeCompactSlider("MSUF_CPFilledAlpha", "Filled %", cpPanel, 0, 100, 5, "classPowerFilledAlpha",
        cpOutlineRow.label, "TOPLEFT", 0, -10, nil, R_LABEL_W)

    cpEmptyAlphaRow = MakeCompactSlider("MSUF_CPEmptyAlpha", "Empty %", cpPanel, 0, 100, 5, "classPowerEmptyAlpha",
        cpFilledAlphaRow.label, "TOPLEFT", 0, -10, nil, R_LABEL_W)

    -- Gap between pips
    cpGapRow = MakeCompactSlider("MSUF_CPGap", "Pip gap", cpPanel, 0, 8, 1, "classPowerGap",
        cpEmptyAlphaRow.label, "TOPLEFT", 0, -10, nil, R_LABEL_W)

    -- ── Auto-hide subsection ──
    local ahLine = cpPanel:CreateTexture(nil, "ARTWORK")
    ahLine:SetColorTexture(1, 1, 1, 0.12)
    ahLine:SetHeight(1)
    ahLine:SetPoint("TOPLEFT", cpGapRow.label, "BOTTOMLEFT", -PAD_X, -10)
    ahLine:SetWidth(LINE_W)

    local ahHeader = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ahHeader:SetPoint("TOPLEFT", ahLine, "BOTTOMLEFT", PAD_X, -6)
    ahHeader:SetText(TR("Auto-Hide"))
    ahHeader:SetTextColor(0.85, 0.85, 0.85)
    cpPanel._ahHeader = ahHeader

    cpHideOOCCheck = MakeCheck("MSUF_ClassPowerHideOOC", TR("Hide out of combat"), cpPanel, R_CHECK_TW)
    cpHideOOCCheck:SetPoint("TOPLEFT", ahHeader, "BOTTOMLEFT", 0, -6)

    cpHideFullCheck = MakeCheck("MSUF_ClassPowerHideFull", TR("Hide when full"), cpPanel, R_CHECK_TW)
    cpHideFullCheck:SetPoint("TOPLEFT", cpHideOOCCheck, "BOTTOMLEFT", 0, -4)

    cpHideEmptyCheck = MakeCheck("MSUF_ClassPowerHideEmpty", TR("Hide when empty"), cpPanel, R_CHECK_TW)
    cpHideEmptyCheck:SetPoint("TOPLEFT", cpHideFullCheck, "BOTTOMLEFT", 0, -4)

    -- Texture dropdowns
    local TEX_DROP_W = 180
    local InitTexDrop = _G.MSUF_InitStatusbarTextureDropdown
    local KillPreview = _G.MSUF_KillMenuPreviewBar

    -- Foreground texture
    local cpFgTexLabel = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cpFgTexLabel:SetPoint("TOPLEFT", cpHideEmptyCheck, "BOTTOMLEFT", 0, -12)
    cpFgTexLabel:SetText(TR("Foreground texture"))
    cpFgTexLabel:SetTextColor(0.85, 0.85, 0.85)
    cpPanel._cpFgTexLabel = cpFgTexLabel

    local cpFgTexDrop = CreateFrame("Frame", "MSUF_CPFgTextureDropdown", cpPanel, "UIDropDownMenuTemplate")
    cpFgTexDrop:SetPoint("TOPLEFT", cpFgTexLabel, "BOTTOMLEFT", -16, -2)
    if MSUF_ExpandDropdownClickArea then MSUF_ExpandDropdownClickArea(cpFgTexDrop) end

    -- Make the LSM list scrollable like Options_Core (prevents huge lists from going offscreen)
    if MSUF_MakeDropdownScrollable then MSUF_MakeDropdownScrollable(cpFgTexDrop, 12) end
    -- Use the same small preview swatch layout as Options_Core so it doesn't cover the scrollbar area.
    cpFgTexDrop._msufTweakBarTexturePreview = true

    local cpFgTexPreview = CreateFrame("StatusBar", "MSUF_CPFgTexturePreview", cpPanel)
    cpFgTexPreview:SetSize(TEX_DROP_W, 10)
    cpFgTexPreview:SetPoint("TOPLEFT", cpFgTexDrop, "BOTTOMLEFT", 20, -2)
    cpFgTexPreview:SetMinMaxValues(0, 1)
    cpFgTexPreview:SetValue(1)
    cpFgTexPreview:Hide()
    if KillPreview then KillPreview(cpFgTexPreview) end
    cpPanel._cpFgTexPreview = cpFgTexPreview

    local function CPFgTexPreview_Update(texName)
        local resolve = _G.MSUF_ResolveStatusbarTextureKey
        if resolve and type(resolve) == "function" then
            local p = resolve(texName)
            if p then cpFgTexPreview:SetStatusBarTexture(p); return end
        end
        local getBar = _G.MSUF_GetBarTexture
        cpFgTexPreview:SetStatusBarTexture((getBar and getBar()) or "Interface\\TargetingFrame\\UI-StatusBar")
    end

    if InitTexDrop then
        InitTexDrop(cpFgTexDrop, {
            width = TEX_DROP_W,
            followText  = TR("Use global bar texture"),
            followValue = "",
            isFollow    = function(cur)  return (cur == nil or cur == "") end,
            setFollow   = function()
                if MSUF_DB then
                    MSUF_DB.bars = MSUF_DB.bars or {}
                    MSUF_DB.bars.classPowerTexture = ""
                end
                CPFgTexPreview_Update(nil)
                if type(_G.MSUF_ClassPower_RefreshTextures) == "function" then _G.MSUF_ClassPower_RefreshTextures() end
            end,
            get = function()
                return MSUF_DB and MSUF_DB.bars and MSUF_DB.bars.classPowerTexture or ""
            end,
            set = function(value)
                if MSUF_DB then
                    MSUF_DB.bars = MSUF_DB.bars or {}
                    MSUF_DB.bars.classPowerTexture = value
                end
                CPFgTexPreview_Update(value)
                if type(_G.MSUF_ClassPower_RefreshTextures) == "function" then _G.MSUF_ClassPower_RefreshTextures() end
            end,
        })
    end
    CPFgTexPreview_Update(MSUF_DB and MSUF_DB.bars and MSUF_DB.bars.classPowerTexture)

    -- Background texture
    local cpBgTexLabel = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cpBgTexLabel:SetPoint("TOPLEFT", cpFgTexLabel, "BOTTOMLEFT", 0, -34)
    cpBgTexLabel:SetText(TR("Background texture"))
    cpBgTexLabel:SetTextColor(0.85, 0.85, 0.85)
    cpPanel._cpBgTexLabel = cpBgTexLabel

    local cpBgTexDrop = CreateFrame("Frame", "MSUF_CPBgTextureDropdown", cpPanel, "UIDropDownMenuTemplate")
    cpBgTexDrop:SetPoint("TOPLEFT", cpBgTexLabel, "BOTTOMLEFT", -16, -2)
    if MSUF_ExpandDropdownClickArea then MSUF_ExpandDropdownClickArea(cpBgTexDrop) end

    if MSUF_MakeDropdownScrollable then MSUF_MakeDropdownScrollable(cpBgTexDrop, 12) end
    cpBgTexDrop._msufTweakBarTexturePreview = true

    local cpBgTexPreview = CreateFrame("StatusBar", "MSUF_CPBgTexturePreview", cpPanel)
    cpBgTexPreview:SetSize(TEX_DROP_W, 10)
    cpBgTexPreview:SetPoint("TOPLEFT", cpBgTexDrop, "BOTTOMLEFT", 20, -2)
    cpBgTexPreview:SetMinMaxValues(0, 1)
    cpBgTexPreview:SetValue(1)
    cpBgTexPreview:Hide()
    if KillPreview then KillPreview(cpBgTexPreview) end
    cpPanel._cpBgTexPreview = cpBgTexPreview

    local function CPBgTexPreview_Update(texName)
        local resolve = _G.MSUF_ResolveStatusbarTextureKey
        if resolve and type(resolve) == "function" then
            local p = resolve(texName)
            if p then cpBgTexPreview:SetStatusBarTexture(p); return end
        end
        local fgKey = MSUF_DB and MSUF_DB.bars and MSUF_DB.bars.classPowerTexture
        local fgResolve = resolve and type(resolve) == "function" and resolve(fgKey)
        local getBar = _G.MSUF_GetBarTexture
        cpBgTexPreview:SetStatusBarTexture(fgResolve or (getBar and getBar()) or "Interface\\TargetingFrame\\UI-StatusBar")
    end

    if InitTexDrop then
        InitTexDrop(cpBgTexDrop, {
            width = TEX_DROP_W,
            followText  = TR("Use foreground texture"),
            followValue = "",
            isFollow    = function(cur)  return (cur == nil or cur == "") end,
            setFollow   = function()
                if MSUF_DB then
                    MSUF_DB.bars = MSUF_DB.bars or {}
                    MSUF_DB.bars.classPowerBgTexture = ""
                end
                CPBgTexPreview_Update(nil)
                if type(_G.MSUF_ClassPower_RefreshTextures) == "function" then _G.MSUF_ClassPower_RefreshTextures() end
            end,
            get = function()
                return MSUF_DB and MSUF_DB.bars and MSUF_DB.bars.classPowerBgTexture or ""
            end,
            set = function(value)
                if MSUF_DB then
                    MSUF_DB.bars = MSUF_DB.bars or {}
                    MSUF_DB.bars.classPowerBgTexture = value
                end
                CPBgTexPreview_Update(value)
                if type(_G.MSUF_ClassPower_RefreshTextures) == "function" then _G.MSUF_ClassPower_RefreshTextures() end
            end,
        })
    end
    CPBgTexPreview_Update(MSUF_DB and MSUF_DB.bars and MSUF_DB.bars.classPowerBgTexture)

    -- ── Detached Power Bar texture dropdown init ──
    -- (Frames created earlier in left column; init here after helper vars are available.)
    if MSUF_MakeDropdownScrollable then
        MSUF_MakeDropdownScrollable(dpbFgDrop, 12)
        MSUF_MakeDropdownScrollable(dpbBgDrop, 12)
    end
    dpbFgDrop._msufTweakBarTexturePreview = true
    dpbBgDrop._msufTweakBarTexturePreview = true

    local DPB_Refresh = function()
        if type(_G.MSUF_DetachedPowerBar_RefreshTextures) == "function" then
            _G.MSUF_DetachedPowerBar_RefreshTextures()
        end
    end

    if InitTexDrop then
        InitTexDrop(dpbFgDrop, {
            width = TEX_DROP_W,
            followText  = TR("Use global bar texture"),
            followValue = "",
            isFollow    = function(cur) return (cur == nil or cur == "") end,
            setFollow   = function()
                if MSUF_DB then
                    MSUF_DB.bars = MSUF_DB.bars or {}
                    MSUF_DB.bars.detachedPowerBarTexture = ""
                end
                DPB_Refresh()
            end,
            get = function()
                return MSUF_DB and MSUF_DB.bars and MSUF_DB.bars.detachedPowerBarTexture or ""
            end,
            set = function(value)
                if MSUF_DB then
                    MSUF_DB.bars = MSUF_DB.bars or {}
                    MSUF_DB.bars.detachedPowerBarTexture = value
                end
                DPB_Refresh()
            end,
        })
        InitTexDrop(dpbBgDrop, {
            width = TEX_DROP_W,
            followText  = TR("Use foreground texture"),
            followValue = "",
            isFollow    = function(cur) return (cur == nil or cur == "") end,
            setFollow   = function()
                if MSUF_DB then
                    MSUF_DB.bars = MSUF_DB.bars or {}
                    MSUF_DB.bars.detachedPowerBarBgTexture = ""
                end
                DPB_Refresh()
            end,
            get = function()
                return MSUF_DB and MSUF_DB.bars and MSUF_DB.bars.detachedPowerBarBgTexture or ""
            end,
            set = function(value)
                if MSUF_DB then
                    MSUF_DB.bars = MSUF_DB.bars or {}
                    MSUF_DB.bars.detachedPowerBarBgTexture = value
                end
                DPB_Refresh()
            end,
        })
    end

    -- =====================================================================
    -- RIGHT COLUMN BOTTOM: Alternative Mana Bar
    -- =====================================================================
    -- Thin divider between Style and Alt Mana sections
    local amDivider = cpPanel:CreateTexture(nil, "ARTWORK")
    amDivider:SetColorTexture(1, 1, 1, 0.12)
    amDivider:SetHeight(1)
    amDivider:SetPoint("TOPLEFT", cpBgTexLabel, "BOTTOMLEFT", -PAD_X, -38)
    amDivider:SetWidth(LINE_W)

    local amHeader = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    amHeader:SetPoint("TOPLEFT", amDivider, "BOTTOMLEFT", PAD_X, -8)
    amHeader:SetText(TR("Alternative Mana Bar"))
    if amHeader.SetTextColor then amHeader:SetTextColor(1, 1, 1) end
    cpPanel._amHeader = amHeader

    local amSub = cpPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    amSub:SetPoint("TOPLEFT", amHeader, "BOTTOMLEFT", 0, -2)
    amSub:SetText(TR("Shadow, Ret, Ele, Enh, Balance, Feral, WW"))
    amSub:SetTextColor(0.55, 0.55, 0.55)
    amSub:SetWidth(colW - 32)
    amSub:SetJustifyH("LEFT")

    -- [x] Show mana bar
    amShowCheck = MakeCheck("MSUF_AltManaShowCheck", "Show mana bar (dual resource)", cpPanel, R_CHECK_TW)
    amShowCheck:SetPoint("TOPLEFT", amSub, "BOTTOMLEFT", 0, -6)

    -- Height / Y offset
    amHeightRow = MakeCompactSlider("MSUF_AMHeight", "Height", cpPanel, 2, 30, 1, "altManaHeight",
        amShowCheck, "TOPLEFT", 0, -10, nil, R_LABEL_W)

    amOffsetRow = MakeCompactSlider("MSUF_AMOffset", "Y offset", cpPanel, -50, 50, 1, "altManaOffsetY",
        amHeightRow.label, "TOPLEFT", 0, -10, nil, R_LABEL_W)

    -- =================================================================
    -- Bottom quick actions
    --   - Edit Mode: toggle MSUF Edit Mode
    --   - Class color: open Colors page and jump to the Class Power color dropdown
    -- =================================================================
    local function _ToggleMSUFEditMode()
        local st = _G and _G.MSUF_EditState
        local isActive = (type(st) == "table" and st.active) and true or false
        if type(_G and _G.MSUF_SetMSUFEditModeDirect) == "function" then
            _G.MSUF_SetMSUFEditModeDirect(not isActive)
        elseif type(_G and _G.MSUF_SetEditMode) == "function" then
            _G.MSUF_SetEditMode(not isActive)
        end
    end

    local function _OpenClassPowerClassColorDropdown()
        if type(_G and _G.MSUF_OpenPage) == "function" then
            _G.MSUF_OpenPage("colors")
        end

        local function JumpAndOpen()
            local dd = _G and _G["MSUF_Colors_ClassPowerTypeDropdown"]
            if not dd then return end

            -- Scroll to dropdown (same math as Bars anchor helper, but for Colors)
            local scroll = _G and _G["MSUF_ColorsScrollFrame"]
            local child  = _G and _G["MSUF_ColorsScrollChild"]
            if scroll and child and scroll.SetVerticalScroll and child.GetTop and dd.GetTop then
                local top  = child:GetTop()
                local aTop = dd:GetTop()
                if top and aTop then
                    local off = (top - aTop) - 12
                    if off < 0 then off = 0 end
                    scroll:SetVerticalScroll(off)
                    if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
                    if _G.UIPanelScrollFrame_Update then _G.UIPanelScrollFrame_Update(scroll) end
                end
            end

            -- Open dropdown menu
            if _G.ToggleDropDownMenu then
                pcall(_G.ToggleDropDownMenu, 1, nil, dd, dd, 0, 0)
            end
        end

        if _G and _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, JumpAndOpen)
        else
            JumpAndOpen()
        end
    end

    -- ── Divider above quick-action buttons ──
    local btnDivider = cpPanel:CreateTexture(nil, "ARTWORK")
    btnDivider:SetColorTexture(1, 1, 1, 0.12)
    btnDivider:SetHeight(1)
    btnDivider:SetPoint("TOPLEFT", dpbOutlineRow.label, "BOTTOMLEFT", -PAD_X, -14)
    btnDivider:SetWidth(totalW - 2)

    local btnW, btnH = 140, 22
    local BTN_PAD = 24  -- horizontal text padding inside button

    local editBtn = CreateFrame("Button", "MSUF_ClassPower_EditModeButton", cpPanel, "UIPanelButtonTemplate")
    editBtn:SetHeight(btnH)
    editBtn:SetText(TR("Edit Mode"))
    -- Auto-width: measure text then clamp to minimum
    do
        local fs = editBtn:GetFontString()
        local tw = (fs and fs.GetStringWidth and fs:GetStringWidth()) or 0
        local w = tw + BTN_PAD
        if w < btnW then w = btnW end
        editBtn:SetWidth(w)
    end
    editBtn:SetPoint("TOPLEFT", btnDivider, "BOTTOMLEFT", PAD_X, -10)
    editBtn:SetScript("OnClick", _ToggleMSUFEditMode)

	-- Match Options_Player action button styling (and prevent SlashMenu mirror skin from breaking click/hover).
	editBtn._msufNoSlashSkin = true
	if _G and _G.MSUF_SkinMidnightActionButton then
		_G.MSUF_SkinMidnightActionButton(editBtn)
	else
		editBtn.__msufMidnightActionSkinned = true
	end

    local colorBtn = CreateFrame("Button", "MSUF_ClassPower_ClassColorButton", cpPanel, "UIPanelButtonTemplate")
    colorBtn:SetHeight(btnH)
    colorBtn:SetText(TR("Class color"))
    do
        local fs = colorBtn:GetFontString()
        local tw = (fs and fs.GetStringWidth and fs:GetStringWidth()) or 0
        local w = tw + BTN_PAD
        if w < btnW then w = btnW end
        colorBtn:SetWidth(w)
    end
    colorBtn:SetPoint("LEFT", editBtn, "RIGHT", 12, 0)
    colorBtn:SetScript("OnClick", _OpenClassPowerClassColorDropdown)

	colorBtn._msufNoSlashSkin = true
	if _G and _G.MSUF_SkinMidnightActionButton then
		_G.MSUF_SkinMidnightActionButton(colorBtn)
	else
		colorBtn.__msufMidnightActionSkinned = true
	end

    -- Dynamically size panel to actual content (buttons are last element).
    -- This avoids clipping regardless of font size or scale.
    do
        local BTN_BOTTOM_PAD = 14
        if editBtn and editBtn.GetHeight and cpPanel and cpPanel.SetHeight then
            local function RecalcPanelHeight()
                if not (editBtn.GetBottom and cpPanel.GetTop) then return end
                local pTop = cpPanel:GetTop()
                local bBot = editBtn:GetBottom()
                if pTop and bBot then
                    local needed = math.ceil(pTop - bBot) + BTN_BOTTOM_PAD
                    if needed < 700 then needed = 700 end
                    cpPanel:SetHeight(needed)
                end
            end
            editBtn:HookScript("OnShow", RecalcPanelHeight)
            C_Timer.After(0.05, RecalcPanelHeight)
        end
    end

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
        BindBool(cpRuneTimeCheck, "bars.runeShowTimeText",          CPRefresh, SyncClassPowerToggles)
        BindBool(cpAnchorCooldownCheck, "bars.classPowerAnchorToCooldown", CPRefresh, SyncClassPowerToggles)
        BindBool(cpFillReverseCheck,   "bars.classPowerFillReverse",      CPRefresh, SyncClassPowerToggles)
        BindBool(cpEleMaelCheck,       "bars.showEleMaelstrom",           CPRefresh, SyncClassPowerToggles)
        BindBool(cpEbonMightCheck,     "bars.showEbonMight",              CPRefresh, SyncClassPowerToggles)
        BindBool(cpPredictionCheck,    "bars.classPowerShowPrediction",   CPRefresh, SyncClassPowerToggles)
        BindBool(cpHideOOCCheck,       "bars.classPowerHideOOC",          CPRefresh, SyncClassPowerToggles)
        BindBool(cpHideFullCheck,      "bars.classPowerHideWhenFull",     CPRefresh, SyncClassPowerToggles)
        BindBool(cpHideEmptyCheck,     "bars.classPowerHideWhenEmpty",    CPRefresh, SyncClassPowerToggles)
        BindBool(amShowCheck,  "bars.showAltMana",            CPRefresh, SyncClassPowerToggles)
    end

    -- Ensure checkbox visuals always reflect DB immediately.
    -- Some templates/skins don't auto-toggle reliably, and our binder is
    -- intentionally minimal; we explicitly load the checked state from DB
    -- whenever the panel is shown (and once right after building).
    local function LoadChecksFromDB()
        if type(MSUF_DB) ~= "table" then return end
        local b = MSUF_DB.bars or {}
        local function _bool(key, defaultTrue)
            local v = b[key]
            if v == nil then return defaultTrue and true or false end
            return v and true or false
        end

        if cpShowCheck and cpShowCheck.SetChecked then cpShowCheck:SetChecked(_bool("showClassPower", true)) end
        if cpColorCheck and cpColorCheck.SetChecked then cpColorCheck:SetChecked(_bool("classPowerColorByType", true)) end
        if cpChargedCheck and cpChargedCheck.SetChecked then cpChargedCheck:SetChecked(_bool("showChargedComboPoints", false)) end
        if cpTextCheck and cpTextCheck.SetChecked then cpTextCheck:SetChecked(_bool("classPowerShowText", false)) end
        if cpAnchorCooldownCheck and cpAnchorCooldownCheck.SetChecked then cpAnchorCooldownCheck:SetChecked(_bool("classPowerAnchorToCooldown", false)) end
        if cpFillReverseCheck and cpFillReverseCheck.SetChecked then cpFillReverseCheck:SetChecked(_bool("classPowerFillReverse", false)) end
        if cpEleMaelCheck and cpEleMaelCheck.SetChecked then cpEleMaelCheck:SetChecked(_bool("showEleMaelstrom", false)) end
        if cpEbonMightCheck and cpEbonMightCheck.SetChecked then cpEbonMightCheck:SetChecked(_bool("showEbonMight", false)) end
        if cpHideOOCCheck and cpHideOOCCheck.SetChecked then cpHideOOCCheck:SetChecked(_bool("classPowerHideOOC", false)) end
        if cpHideFullCheck and cpHideFullCheck.SetChecked then cpHideFullCheck:SetChecked(_bool("classPowerHideWhenFull", false)) end
        if cpHideEmptyCheck and cpHideEmptyCheck.SetChecked then cpHideEmptyCheck:SetChecked(_bool("classPowerHideWhenEmpty", false)) end
        if amShowCheck and amShowCheck.SetChecked then amShowCheck:SetChecked(_bool("showAltMana", true)) end

        if SyncClassPowerToggles then SyncClassPowerToggles() end
    end

    LoadChecksFromDB()
    if cpPanel and cpPanel.HookScript then
        cpPanel:HookScript("OnShow", LoadChecksFromDB)
    end

    -- IMPORTANT: Some checkbox skins / template scripts can replace the
    -- checkbox's OnClick after our binder runs (or swallow the binder's
    -- SetScript). This makes enabled/disabled greying appear only after
    -- leaving/re-entering the tab (OnShow sync).
    --
    -- To guarantee *immediate* visual enable-state updates, we HookScript
    -- (non-destructive) and sync on the next tick so GetChecked() is final.
    local function HookImmediateSync(cb)
        if not cb or not cb.HookScript or cb.__msufImmediateSyncHooked then return end
        cb.__msufImmediateSyncHooked = true
        cb:HookScript("OnClick", function()
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function() if SyncClassPowerToggles then SyncClassPowerToggles() end end)
            else
                if SyncClassPowerToggles then SyncClassPowerToggles() end
            end
        end)
    end
    HookImmediateSync(cpShowCheck)
    HookImmediateSync(amShowCheck)

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

-- Search helper (additive): register the Class Resources root panel (built lazily).
if _G and _G.MSUF_Search_RegisterRoots then
    _G.MSUF_Search_RegisterRoots({ "classpower" }, { "MSUF_ClassPowerOptionsPanel" }, "Class Resources")
end

-- ============================================================================
-- Sync (called when Bars tab opens or state changes)
-- ============================================================================
local function SyncClassPowerToggles()
    if not _built then return end
    if not MSUF_DB then return end
    local b = MSUF_DB.bars or {}

    -- Enable/disable helpers (defined once at top for use throughout)
    local cpOn = (b.showClassPower ~= false)
    local amOn = (b.showAltMana ~= false)

    local function SetEnabled(ctrl, on)
        if not ctrl then return end
        -- IMPORTANT UX: For checkboxes, we want the ON/OFF state to remain
        -- visually readable even when the parent section is disabled by a
        -- master toggle (e.g. 'Show class power'). Using :Disable() on a
        -- UICheckButtonTemplate greys out the checkmark and makes an enabled
        -- option look "off". Instead we keep it enabled but block mouse.
        local isCheck = (ctrl.GetObjectType and ctrl:GetObjectType() == "CheckButton")
        if on then
            if ctrl.Enable then ctrl:Enable() end
            if ctrl.EnableMouse then ctrl:EnableMouse(true) end
            if ctrl.SetAlpha then ctrl:SetAlpha(1) end
        else
            if isCheck then
                -- Keep the check state visible (checked stays clearly visible).
                if ctrl.Enable then ctrl:Enable() end
                if ctrl.EnableMouse then ctrl:EnableMouse(false) end
                if ctrl.SetAlpha then
                    ctrl:SetAlpha((ctrl.GetChecked and ctrl:GetChecked()) and 0.85 or 0.55)
                end
            else
                if ctrl.Disable then ctrl:Disable() end
                if ctrl.EnableMouse then ctrl:EnableMouse(false) end
                if ctrl.ClearFocus then ctrl:ClearFocus() end
                if ctrl.SetAlpha then ctrl:SetAlpha(0.45) end
            end
        end
    end

    -- ClassPower toggles
    if cpShowCheck then
        cpShowCheck:SetChecked(cpOn)
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
                { key = "player",       label = TR("Player frame") },
                { key = "cooldown",     label = TR("Essential Cooldowns") },
                { key = "utility",      label = TR("Utility Cooldowns") },
                { key = "tracked_buffs",label = TR("Tracked Buffs") },
                { key = "custom",       label = TR("Custom") },
            }
            SyncDrop(cpWidthModeDrop, WIDTH_MODE_OPTIONS, function() return widthMode end)
        end
    end
    -- Width slider only active in custom mode + cpOn
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
    if cpRuneTimeCheck then
        cpRuneTimeCheck:SetChecked(b.runeShowTimeText == true)
        if cpRuneTimeCheck.__msufToggleUpdate then cpRuneTimeCheck.__msufToggleUpdate() end
    end
    if cpAnchorCooldownCheck then
        cpAnchorCooldownCheck:SetChecked(b.classPowerAnchorToCooldown == true)
        if cpAnchorCooldownCheck.__msufToggleUpdate then cpAnchorCooldownCheck.__msufToggleUpdate() end
    end
    -- Filled / Empty alpha
    if cpFilledAlphaRow then
        local a = tonumber(b.classPowerFilledAlpha) or 1.0
        cpFilledAlphaRow:Set(math_floor(a * 100 + 0.5))
    end
    if cpEmptyAlphaRow then
        local a = tonumber(b.classPowerEmptyAlpha) or 0.3
        cpEmptyAlphaRow:Set(math_floor(a * 100 + 0.5))
    end
    -- Gap
    if cpGapRow then
        cpGapRow:Set(tonumber(b.classPowerGap) or 0)
    end
    -- Font size
    if cpFontSizeRow then
        cpFontSizeRow:Set(tonumber(b.classPowerFontSize) or 16)
    end
    -- Text offset
    if cpTextOffsetXRow then
        cpTextOffsetXRow:Set(tonumber(b.classPowerTextOffsetX) or 0)
    end
    if cpTextOffsetYRow then
        cpTextOffsetYRow:Set(tonumber(b.classPowerTextOffsetY) or 0)
    end
    -- Fill reverse
    if cpFillReverseCheck then
        cpFillReverseCheck:SetChecked(b.classPowerFillReverse == true)
        if cpFillReverseCheck.__msufToggleUpdate then cpFillReverseCheck.__msufToggleUpdate() end
    end
    -- Spec-specific toggles
    if cpEleMaelCheck then
        cpEleMaelCheck:SetChecked(b.showEleMaelstrom == true)
        if cpEleMaelCheck.__msufToggleUpdate then cpEleMaelCheck.__msufToggleUpdate() end
    end
    if cpEbonMightCheck then
        cpEbonMightCheck:SetChecked(b.showEbonMight ~= false)
        if cpEbonMightCheck.__msufToggleUpdate then cpEbonMightCheck.__msufToggleUpdate() end
    end
    if cpPredictionCheck then
        cpPredictionCheck:SetChecked(b.classPowerShowPrediction ~= false)
        if cpPredictionCheck.__msufToggleUpdate then cpPredictionCheck.__msufToggleUpdate() end
    end
    -- Auto-hide
    if cpHideOOCCheck then
        cpHideOOCCheck:SetChecked(b.classPowerHideOOC == true)
        if cpHideOOCCheck.__msufToggleUpdate then cpHideOOCCheck.__msufToggleUpdate() end
    end
    if cpHideFullCheck then
        cpHideFullCheck:SetChecked(b.classPowerHideWhenFull == true)
        if cpHideFullCheck.__msufToggleUpdate then cpHideFullCheck.__msufToggleUpdate() end
    end
    if cpHideEmptyCheck then
        cpHideEmptyCheck:SetChecked(b.classPowerHideWhenEmpty == true)
        if cpHideEmptyCheck.__msufToggleUpdate then cpHideEmptyCheck.__msufToggleUpdate() end
    end
    -- Texture dropdowns: re-sync selected text from DB
    local SyncTexDrop = _G.MSUF_SyncStatusbarTextureDropdown
    if SyncTexDrop then
        local fgD = _G["MSUF_CPFgTextureDropdown"]
        local bgD = _G["MSUF_CPBgTextureDropdown"]
        if fgD then SyncTexDrop(fgD) end
        if bgD then SyncTexDrop(bgD) end
        local dpbFgD = _G["MSUF_DPBFgTextureDropdown"]
        local dpbBgD = _G["MSUF_DPBBgTextureDropdown"]
        if dpbFgD then SyncTexDrop(dpbFgD) end
        if dpbBgD then SyncTexDrop(dpbBgD) end
    end

    -- AltMana
    if amShowCheck then
        amShowCheck:SetChecked(amOn)
        if amShowCheck.__msufToggleUpdate then amShowCheck.__msufToggleUpdate() end
    end
    if amHeightRow then
        amHeightRow:Set(tonumber(b.altManaHeight) or 4)
    end
    if amOffsetRow then
        amOffsetRow:Set(tonumber(b.altManaOffsetY) or -2)
    end

    -- Dim sub-controls when master toggle is off
    SetEnabled(cpColorCheck, cpOn)
    SetEnabled(cpChargedCheck, cpOn)
    SetEnabled(cpTextCheck, cpOn)
    SetEnabled(cpRuneTimeCheck, cpOn and (b.classPowerShowText == true))
    SetEnabled(cpAnchorCooldownCheck, cpOn)
    SetEnabled(cpFillReverseCheck, cpOn)
    SetEnabled(cpEleMaelCheck, cpOn)
    SetEnabled(cpEbonMightCheck, cpOn)
    SetEnabled(cpPredictionCheck, cpOn)
    SetEnabled(cpHideOOCCheck, cpOn)
    SetEnabled(cpHideFullCheck, cpOn)
    SetEnabled(cpHideEmptyCheck, cpOn)
    if cpHeightRow      then cpHeightRow:SetEnabled(cpOn)      end
    if cpXOffsetRow     then cpXOffsetRow:SetEnabled(cpOn)     end
    if cpYOffsetRow     then cpYOffsetRow:SetEnabled(cpOn)     end
    if cpBgAlphaRow     then cpBgAlphaRow:SetEnabled(cpOn)     end
    if cpTickRow        then cpTickRow:SetEnabled(cpOn)        end
    if cpOutlineRow     then cpOutlineRow:SetEnabled(cpOn)     end
    if cpFilledAlphaRow then cpFilledAlphaRow:SetEnabled(cpOn) end
    if cpEmptyAlphaRow  then cpEmptyAlphaRow:SetEnabled(cpOn)  end
    if cpGapRow         then cpGapRow:SetEnabled(cpOn)         end
    if cpFontSizeRow    then cpFontSizeRow:SetEnabled(cpOn)    end
    if cpTextOffsetXRow then cpTextOffsetXRow:SetEnabled(cpOn) end
    if cpTextOffsetYRow then cpTextOffsetYRow:SetEnabled(cpOn) end
    if cpPanel and cpPanel._ahHeader then
        cpPanel._ahHeader:SetTextColor(cpOn and 0.85 or 0.35, cpOn and 0.85 or 0.35, cpOn and 0.85 or 0.35)
    end

    -- Texture dropdowns dim
    local fgDrop = _G["MSUF_CPFgTextureDropdown"]
    local bgDrop = _G["MSUF_CPBgTextureDropdown"]
    local SetDropEnabled = _G.MSUF_SetDropDownEnabled
    if SetDropEnabled then
        local fgLabel = cpPanel and cpPanel._cpFgTexLabel
        local bgLabel = cpPanel and cpPanel._cpBgTexLabel
        if fgDrop then SetDropEnabled(fgDrop, fgLabel, cpOn) end
        if bgDrop then SetDropEnabled(bgDrop, bgLabel, cpOn) end
    end

    if amHeightRow then amHeightRow:SetEnabled(amOn) end
    if amOffsetRow then amOffsetRow:SetEnabled(amOn) end

    -- Detached Power Bar section: dim when no unit has powerBarDetached
    local dpbOn = false
    for _, k in ipairs({"player", "target", "focus"}) do
        local c = MSUF_DB[k]
        if c and c.powerBarDetached == true then dpbOn = true; break end
    end
    -- Sync DPB width mode dropdown
    if dpbWidthModeDrop then
        local SyncDrop = _G.MSUF_SyncSimpleDropdown
        if SyncDrop then
            local DPB_WIDTH_MODE_OPTIONS = {
                { key = "manual",       label = TR("Manual") },
                { key = "cooldown",     label = TR("Essential Cooldowns") },
                { key = "utility",      label = TR("Utility Cooldowns") },
                { key = "tracked_buffs",label = TR("Tracked Buffs") },
            }
            SyncDrop(dpbWidthModeDrop, DPB_WIDTH_MODE_OPTIONS, function()
                return (b.detachedPowerBarWidthMode) or "manual"
            end)
        end
    end
    local dpbAlpha = dpbOn and 1 or 0.35
    local dpbCol   = dpbOn and 0.85 or 0.35
    if cpPanel then
        if cpPanel._dpbHeader then cpPanel._dpbHeader:SetAlpha(dpbAlpha) end
        if cpPanel._dpbSub   then cpPanel._dpbSub:SetAlpha(dpbAlpha)   end
        if cpPanel._dpbWidthModeLabel then cpPanel._dpbWidthModeLabel:SetTextColor(dpbCol, dpbCol, dpbCol) end
        if cpPanel._dpbFgLabel then cpPanel._dpbFgLabel:SetTextColor(dpbCol, dpbCol, dpbCol) end
        if cpPanel._dpbBgLabel then cpPanel._dpbBgLabel:SetTextColor(dpbCol, dpbCol, dpbCol) end
    end
    if SetDropEnabled then
        local dpbWDrop  = _G["MSUF_DPBWidthModeDrop"]
        local dpbFgDrop = _G["MSUF_DPBFgTextureDropdown"]
        local dpbBgDrop = _G["MSUF_DPBBgTextureDropdown"]
        if dpbWDrop  then SetDropEnabled(dpbWDrop,  cpPanel and cpPanel._dpbWidthModeLabel, dpbOn) end
        if dpbFgDrop then SetDropEnabled(dpbFgDrop, cpPanel and cpPanel._dpbFgLabel, dpbOn) end
        if dpbBgDrop then SetDropEnabled(dpbBgDrop, cpPanel and cpPanel._dpbBgLabel, dpbOn) end
    end
end

-- ============================================================================
-- Hook: Bars tab OnShow + SyncBarsTabToggles wrapping
-- ============================================================================
local _hooked = false

local function HookClassPowerTab()
    if _hooked then return end

    local host = _G["MSUF_ClassPowerMenuHost"]
    if not host then return end

    _hooked = true

    -- Build on first show of the dedicated Class Resources tab
    if host.HookScript then
        host:HookScript("OnShow", function()
            BuildClassPowerOptions("MSUF_ClassPowerMenuPanelLeft", "MSUF_ClassPowerMenuPanelRight")
            SyncClassPowerToggles()
        end)
    end

    -- If the tab is already visible right now, build + sync immediately
    if host.IsVisible and host:IsVisible() then
        BuildClassPowerOptions("MSUF_ClassPowerMenuPanelLeft", "MSUF_ClassPowerMenuPanelRight")
        SyncClassPowerToggles()
    end
end

-- ============================================================================
-- Entry: hook into CreateOptionsPanel (global) so we attach AFTER the UI is built.
-- CreateOptionsPanel() is called from the slash menu on first /msuf.
-- ============================================================================
do
    -- 1) Already built? (e.g. file loaded after options panel)
    if _G["MSUF_ClassPowerMenuHost"] then
        HookClassPowerTab()
    end

    -- 2) Not built yet: wrap CreateOptionsPanel to hook after it runs.
    if not _hooked and type(_G.CreateOptionsPanel) == "function" then
        hooksecurefunc(_G, "CreateOptionsPanel", function()
            -- CreateOptionsPanel just finished; MSUF_ClassPowerMenuHost now exists.
            HookClassPowerTab()
        end)
    end
end

-- Public helper for callers (SlashMenu mirror) to force-build if needed.
_G.MSUF_EnsureClassPowerMenuBuilt = function()
    HookClassPowerTab()
    BuildClassPowerOptions("MSUF_ClassPowerMenuPanelLeft", "MSUF_ClassPowerMenuPanelRight")
    SyncClassPowerToggles()
end

-- ============================================================================
-- Public: allow MSUF_ClassPower.lua to trigger options sync
-- ============================================================================
_G.MSUF_ClassPower_SyncOptions = SyncClassPowerToggles