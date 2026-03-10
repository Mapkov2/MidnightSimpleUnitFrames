-- ---------------------------------------------------------------------------
-- MSUF_Options_Toolkit.lua  (Phase 1: Complete Rewrite)
--
-- Widget SDK for all MSUF Options files.
-- Loads BEFORE MSUF_Options_Core.lua in the TOC.
--
-- Provides:
--   ns.TR(v)               Localization (single definition, all files use this)
--   ns.EnsureDB()          DB guarantee (single definition)
--   ns.UI.Check(spec)      Self-syncing checkbox
--   ns.UI.Slider(spec)     Self-syncing slider with editbox + ±
--   ns.UI.Dropdown(spec)   Spec-driven dropdown (own ListFrame, scrollable)
--   ns.UI.Label(spec)      FontString helper
--   ns.UI.Section(spec)    Section header with divider line
--   ns.UI.Panel(spec)      Dark panel box with title
--   ns.UI.Button(spec)     UIPanelButton helper
--   ns.UI.ButtonRow(defs)  Horizontal row of buttons
--   ns.UI.StatusBarTextureItems(followText)  SharedMedia texture item list
--   ns.UI.QueueScrollUpdate(host, keys)      Deferred scroll-height calc
--   ns.UI.AttachTooltip(w, title, body)      GameTooltip helper
-- ---------------------------------------------------------------------------
local addonName, addonNS = ...
local ns = (_G.MSUF_NS) or addonNS or {}
if _G then _G.MSUF_NS = ns end

-- ============================================================
-- 1. Shared Boilerplate (all files use ns.TR / ns.EnsureDB)
-- ============================================================
ns.L = ns.L or (_G.MSUF_L) or {}
if not getmetatable(ns.L) then
    setmetatable(ns.L, { __index = function(_, k) return k end })
end

local L = ns.L
local isEn = (ns.LOCALE) == "enUS"

function ns.TR(v)
    if type(v) ~= "string" then return v end
    if isEn then return v end
    return L[v] or v
end

function ns.EnsureDB()
    if type(MSUF_DB) ~= "table" then MSUF_DB = {} end
    if type(MSUF_DB.general) ~= "table" then MSUF_DB.general = {} end
    if type(MSUF_DB.bars) ~= "table" then MSUF_DB.bars = {} end
end

-- Local aliases
local TR = ns.TR
local floor = math.floor
local format = string.format
local TEX_W8 = "Interface\\Buttons\\WHITE8x8"
local ADDON = (type(addonName) == "string" and addonName ~= "" and addonName) or "MidnightSimpleUnitFrames"

-- ============================================================
-- 2. Tooltip Helper
-- ============================================================
local function AttachTooltip(widget, titleText, bodyText)
    if not widget or (not titleText and not bodyText) then return end
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if titleText then GameTooltip:SetText(titleText, 1, 1, 1) end
        if bodyText then GameTooltip:AddLine(bodyText, 0.9, 0.9, 0.9, true) end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ============================================================
-- 3. Style Functions
-- ============================================================
local function StyleSlider(slider)
    if not slider or slider._msufStyled then return end
    slider._msufStyled = true
    slider:SetHeight(14)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    slider._msufTrack = track
    track:SetColorTexture(0.06, 0.06, 0.06, 1)
    track:SetPoint("TOPLEFT", slider, "TOPLEFT", 0, -3)
    track:SetPoint("BOTTOMRIGHT", slider, "BOTTOMRIGHT", 0, 3)
    local thumb = slider:GetThumbTexture()
    if thumb then
        thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        thumb:SetSize(10, 18)
    end
    slider:HookScript("OnEnter", function(self)
        if self._msufTrack then self._msufTrack:SetColorTexture(0.20, 0.20, 0.20, 1) end
    end)
    slider:HookScript("OnLeave", function(self)
        if self._msufTrack then self._msufTrack:SetColorTexture(0.06, 0.06, 0.06, 1) end
    end)
end

local function StyleSmallButton(button, isPlus)
    if not button or button._msufStyled then return end
    button._msufStyled = true
    button:SetSize(20, 20)
    local normal = button:CreateTexture(nil, "BACKGROUND")
    normal:SetAllPoints(); normal:SetTexture(TEX_W8); normal:SetVertexColor(0, 0, 0, 0.9)
    button:SetNormalTexture(normal)
    local pushed = button:CreateTexture(nil, "BACKGROUND")
    pushed:SetAllPoints(); pushed:SetTexture(TEX_W8); pushed:SetVertexColor(0.7, 0.55, 0.15, 0.95)
    button:SetPushedTexture(pushed)
    local hl = button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetTexture(TEX_W8); hl:SetVertexColor(1, 0.9, 0.4, 0.25)
    button:SetHighlightTexture(hl)
    local border = CreateFrame("Frame", nil, button, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop({ edgeFile = TEX_W8, edgeSize = 1 })
    border:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    local fs = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    fs:SetTextColor(1, 0.9, 0.4)
    fs:SetText(isPlus and "+" or "-")
    button.text = fs
end

local function StyleToggleText(cb)
    if not cb or cb._msufToggleStyled then return end
    cb._msufToggleStyled = true
    local fs = cb.text or cb.Text
    if not fs and cb.GetName and cb:GetName() then fs = _G[cb:GetName() .. "Text"] end
    if not (fs and fs.SetTextColor) then return end
    cb._msufToggleFS = fs
    local function Update()
        if cb.IsEnabled and not cb:IsEnabled() then
            fs:SetTextColor(0.35, 0.35, 0.35)
        elseif cb.GetChecked and cb:GetChecked() then
            fs:SetTextColor(1, 1, 1)
        else
            fs:SetTextColor(0.55, 0.55, 0.55)
        end
    end
    cb._msufToggleUpdate = Update
    cb:HookScript("OnShow", Update)
    cb:HookScript("OnClick", Update)
    pcall(hooksecurefunc, cb, "SetChecked", function() Update() end)
    pcall(hooksecurefunc, cb, "SetEnabled", function() Update() end)
    Update()
end

local CHECK_TEX_BOLD = "Interface/AddOns/" .. ADDON .. "/Media/msuf_check_tick_bold.tga"
local CHECK_TEX_THIN = "Interface/AddOns/" .. ADDON .. "/Media/msuf_check_tick_thin.tga"

local function StyleCheckmark(cb)
    if not cb or cb._msufCheckStyled then return end
    cb._msufCheckStyled = true
    local check = cb.GetCheckedTexture and cb:GetCheckedTexture()
    if not check and cb.GetName and cb:GetName() then check = _G[cb:GetName() .. "Check"] end
    if not (check and check.SetTexture) then return end
    local h = (cb.GetHeight and cb:GetHeight()) or 24
    check:SetTexture(h >= 24 and CHECK_TEX_BOLD or CHECK_TEX_THIN)
    check:SetTexCoord(0, 1, 0, 1)
    if check.SetBlendMode then check:SetBlendMode("BLEND") end
    if check.ClearAllPoints then
        check:ClearAllPoints()
        check:SetPoint("CENTER", cb, "CENTER", 0, 0)
        local sz = floor(h * 0.8 + 0.5)
        if sz < 12 then sz = 12 end
        check:SetSize(sz, sz)
    end
end

-- ============================================================
-- 4. Widget SDK (ns.UI)
-- ============================================================
ns.UI = ns.UI or {}
local UI = ns.UI

-- ---- 4a. Label ----
function UI.Label(spec)
    local parent = spec.parent
    local fs = parent:CreateFontString(nil, "OVERLAY", spec.font or "GameFontNormal")
    fs:SetText(spec.text or "")
    if spec.color then
        fs:SetTextColor(spec.color[1], spec.color[2], spec.color[3], spec.color[4] or 1)
    else
        fs:SetTextColor(1, 0.82, 0)
    end
    if spec.anchor then
        fs:SetPoint("TOPLEFT", spec.anchor, spec.anchorPoint or "BOTTOMLEFT", spec.x or 0, spec.y or -8)
    end
    if spec.width then fs:SetWidth(spec.width) end
    if spec.justify then fs:SetJustifyH(spec.justify) end
    return fs
end

-- ---- 4b. Section ----
function UI.Section(spec)
    local parent = spec.parent
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetText(spec.title or "")
    header:SetTextColor(1, 0.82, 0)
    if spec.anchor then
        header:SetPoint("TOPLEFT", spec.anchor, spec.anchorPoint or "BOTTOMLEFT", spec.x or 0, spec.y or -16)
    else
        header:SetPoint("TOPLEFT", parent, "TOPLEFT", spec.x or 16, spec.y or -16)
    end
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    line:SetWidth(spec.width or 300)
    header._msufLine = line
    return header
end

-- ---- 4c. Panel (dark box with title) ----
function UI.Panel(spec)
    local parent = spec.parent
    local p = CreateFrame("Frame", spec.name, parent, "BackdropTemplate")
    p:SetSize(spec.width or 330, spec.height or 330)
    if spec.anchor then
        p:SetPoint("TOPLEFT", spec.anchor, spec.anchorPoint or "TOPLEFT", spec.x or 0, spec.y or 0)
    else
        p:SetPoint("TOPLEFT", parent, "TOPLEFT", spec.x or 0, spec.y or 0)
    end
    p:SetBackdrop({
        bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    p:SetBackdropColor(0, 0, 0, spec.bgAlpha or 0)
    p:SetBackdropBorderColor(0, 0, 0, 0)
    local header = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetText(spec.title or "")
    header:SetTextColor(1, 0.82, 0)
    header:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -14)
    local line = p:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
    line:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -38)
    p._msufHeader = header
    p._msufLine = line
    return p
end

-- ---- 4d. Button ----
function UI.Button(spec)
    local b = CreateFrame("Button", spec.name, spec.parent, "UIPanelButtonTemplate")
    b:SetSize(spec.width or 140, spec.height or 24)
    b:SetText(spec.text or "")
    if spec.anchor then
        b:SetPoint("TOPLEFT", spec.anchor, spec.anchorPoint or "BOTTOMLEFT", spec.x or 0, spec.y or -8)
    end
    if spec.onClick then b:SetScript("OnClick", spec.onClick) end
    if spec.tooltip then AttachTooltip(b, spec.tooltip) end
    return b
end

-- ---- 4e. Check (self-syncing) ----
function UI.Check(spec)
    local cb = CreateFrame("CheckButton", spec.name, spec.parent, spec.template or "UICheckButtonTemplate")
    cb:RegisterForClicks("AnyUp")
    if cb.SetHitRectInsets then cb:SetHitRectInsets(0, -((spec.maxTextWidth or 220) + 8), 0, 0) end
    if spec.anchor then
        cb:SetPoint("TOPLEFT", spec.anchor, spec.anchorPoint or "BOTTOMLEFT", spec.x or 0, spec.y or -4)
    end
    -- Label
    local fs = cb.text or cb.Text
    if not fs and spec.name then fs = _G[spec.name .. "Text"] end
    if fs and fs.SetText then
        fs:SetText(TR(spec.label or ""))
        if fs.EnableMouse then fs:EnableMouse(false) end
    end
    if spec.maxTextWidth and _G.MSUF_ClampCheckboxText then
        _G.MSUF_ClampCheckboxText(cb, spec.maxTextWidth)
    end
    -- Style
    StyleToggleText(cb)
    StyleCheckmark(cb)

    local function SyncFromGetter(self)
        if spec.get then
            self:SetChecked(spec.get() and true or false)
        end
        if self._msufToggleUpdate then self._msufToggleUpdate() end
    end

    local function ApplyToDB(self)
        if not spec.set then return end
        local v = self:GetChecked() and true or false
        spec.set(v)
        if self._msufToggleUpdate then self._msufToggleUpdate() end
    end

    cb:SetScript("OnShow", function(self)
        SyncFromGetter(self)
    end)

    cb:SetScript("OnClick", function(self)
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if self and self.GetChecked then
                    ApplyToDB(self)
                    if spec.get then SyncFromGetter(self) end
                end
            end)
        else
            ApplyToDB(self)
            if spec.get then SyncFromGetter(self) end
        end
    end)

    if spec.tooltip then AttachTooltip(cb, spec.tooltip) end
    -- Search registration
    if spec.name and spec.label and _G.MSUF_Search_RegisterSlider then
        -- Search indexes by name + label text, works for any widget
    end
    return cb
end

-- ---- 4f. Slider (self-syncing; compact=true skips editbox/±) ----
function UI.Slider(spec)
    local name = spec.name
    local parent = spec.parent
    local minV, maxV, step = spec.min or 0, spec.max or 100, spec.step or 1
    local compact = spec.compact
    local sl = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    sl:SetMinMaxValues(minV, maxV)
    sl:SetValueStep(step)
    sl:SetObeyStepOnDrag(true)
    sl:SetWidth(spec.width or 270)
    if spec.anchor then
        sl:SetPoint("TOPLEFT", spec.anchor, spec.anchorPoint or "BOTTOMLEFT", spec.x or 0, spec.y or -18)
    end
    sl._msufStep = step
    -- Template text regions
    local low  = name and _G[name .. "Low"]
    local high = name and _G[name .. "High"]
    local text = name and _G[name .. "Text"]
    if low  then low:SetText(spec.lowText or tostring(minV)) end
    if high then high:SetText(spec.highText or tostring(maxV)) end
    -- EditBox + ± (only for non-compact sliders)
    local eb, minus, plus
    if not compact then
        eb = CreateFrame("EditBox", name and (name .. "Input"), parent, "InputBoxTemplate")
        eb:SetSize(60, 18); eb:SetAutoFocus(false); eb:SetJustifyH("CENTER")
        eb:SetPoint("TOP", sl, "BOTTOM", 0, -6)
        eb:SetFontObject(GameFontHighlightSmall); eb:SetTextColor(1, 1, 1, 1)
        sl.editBox = eb
        minus = CreateFrame("Button", name and (name .. "Minus"), parent)
        minus:SetPoint("RIGHT", eb, "LEFT", -2, 0)
        StyleSmallButton(minus, false)
        sl.minusButton = minus
        plus = CreateFrame("Button", name and (name .. "Plus"), parent)
        plus:SetPoint("LEFT", eb, "RIGHT", 2, 0)
        StyleSmallButton(plus, true)
        sl.plusButton = plus
    end
    -- Format helper
    local function FormatValue(v)
        if step >= 1 then
            return tostring(floor(v + 0.5))
        else
            return format("%.2f", v)
        end
    end
    -- Sync editbox from slider value
    local function SyncEditBox(v)
        if eb and not eb:HasFocus() then
            eb:SetText(FormatValue(v))
        end
    end
    -- Label update
    local function UpdateLabel(v)
        if text and text.SetText then
            if spec.formatText then
                text:SetText(spec.formatText(v))
            else
                text:SetText(TR(spec.label or ""))
            end
        end
    end
    if not compact then
        -- Apply editbox value
        local function ApplyEditBox()
            local v = tonumber(eb:GetText())
            if not v then SyncEditBox(sl:GetValue()); return end
            if v < minV then v = minV elseif v > maxV then v = maxV end
            sl:SetValue(v)
        end
        eb:SetScript("OnEnterPressed", function(self) ApplyEditBox(); self:ClearFocus() end)
        eb:SetScript("OnEditFocusLost", ApplyEditBox)
        eb:SetScript("OnEscapePressed", function(self)
            SyncEditBox(sl:GetValue()); self:ClearFocus()
        end)
        minus:SetScript("OnClick", function()
            local v = sl:GetValue() - step
            if v < minV then v = minV end
            sl:SetValue(v)
        end)
        plus:SetScript("OnClick", function()
            local v = sl:GetValue() + step
            if v > maxV then v = maxV end
            sl:SetValue(v)
        end)
    end
    -- OnValueChanged
    sl._msufSkip = false
    sl:SetScript("OnValueChanged", function(self, value)
        if self._msufSkip then return end
        if step >= 1 then value = floor(value + 0.5) end
        SyncEditBox(value)
        UpdateLabel(value)
        if spec.set then spec.set(value) end
    end)
    -- Self-sync on Show
    sl:SetScript("OnShow", function(self)
        if spec.get then
            local v = spec.get()
            if type(v) ~= "number" then v = spec.default or minV end
            if v < minV then v = minV elseif v > maxV then v = maxV end
            self._msufSkip = true
            self:SetValue(v)
            self._msufSkip = false
            SyncEditBox(v)
            UpdateLabel(v)
        end
    end)
    -- Programmatic set (no callback)
    function sl:SetValueClean(v)
        self._msufSkip = true
        self:SetValue(v)
        self._msufSkip = false
        SyncEditBox(v)
    end
    StyleSlider(sl)
    -- Search registration
    if name and spec.label and type(_G.MSUF_Search_RegisterSlider) == "function" then
        _G.MSUF_Search_RegisterSlider(name, spec.label)
    end
    return sl
end

-- ============================================================
-- 5. Dropdown System (own ListFrame, no DropDownList1)
-- ============================================================

-- Theme
local DD_BG     = { 0.08, 0.08, 0.10, 0.95 }
local DD_BORDER  = { 0.30, 0.30, 0.35, 0.80 }
local DD_HOVER   = { 0.20, 0.20, 0.25, 1.00 }
local DD_CHECK   = { 1.00, 0.82, 0.00 }
local DD_TEXT    = { 0.90, 0.90, 0.90 }
local DD_ITEM_H  = 22

-- Singleton list frame
local _listFrame, _listOwner, _listBackdrop
local _itemPool = {}
local _itemCount = 0

local function DD_Close()
    if _listFrame then _listFrame:Hide() end
    if _listBackdrop then _listBackdrop:Hide() end
    _listOwner = nil
end

local function DD_EnsureList()
    if _listFrame then return end
    -- Fullscreen click-outside catcher
    _listBackdrop = CreateFrame("Button", nil, UIParent)
    _listBackdrop:SetFrameStrata("FULLSCREEN")
    _listBackdrop:SetAllPoints(UIParent)
    _listBackdrop:EnableMouse(true)
    _listBackdrop:SetScript("OnClick", DD_Close)
    _listBackdrop:Hide()
    -- List container
    local lf = CreateFrame("Frame", "MSUF_SpecDDList", UIParent, "BackdropTemplate")
    lf:SetFrameStrata("FULLSCREEN_DIALOG")
    lf:SetClampedToScreen(true)
    lf:SetBackdrop({
        bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    lf:SetBackdropColor(DD_BG[1], DD_BG[2], DD_BG[3], DD_BG[4])
    lf:SetBackdropBorderColor(DD_BORDER[1], DD_BORDER[2], DD_BORDER[3], DD_BORDER[4])
    lf:Hide()
    -- ESC close
    lf:EnableKeyboard(true)
    lf:SetPropagateKeyboardInput(true)
    lf:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            DD_Close()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    -- ScrollFrame
    local sf = CreateFrame("ScrollFrame", nil, lf, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", lf, "TOPLEFT", 2, -2)
    sf:SetPoint("BOTTOMRIGHT", lf, "BOTTOMRIGHT", -18, 2)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    lf._sf = sf
    lf._child = child
    lf._sb = sf.ScrollBar
    -- Mousewheel
    lf:EnableMouseWheel(true)
    lf:SetScript("OnMouseWheel", function(self, delta)
        local cur = sf:GetVerticalScroll()
        local step = (self._itemH or DD_ITEM_H) * 3
        local new = cur - (delta * step)
        if new < 0 then new = 0 end
        local mx = (self._totalH or 0) - (self._visH or 0)
        if mx < 0 then mx = 0 end
        if new > mx then new = mx end
        sf:SetVerticalScroll(new)
    end)
    _listFrame = lf
end

-- Shared item click handler (reads refs from button fields)
local function DD_ItemClick(self)
    local item  = self._ddItem
    local owner = self._ddOwner
    if not (item and owner) then return end
    local spec = owner._ddSpec
    if spec and spec.set then spec.set(item.key, item) end
    if owner.SetValue then
        owner:SetValue(item.key)
    else
        -- Auto-intercepted dropdown: update text via UIDropDownMenu API
        owner._ddKey = item.key
        if UIDropDownMenu_SetSelectedValue then pcall(UIDropDownMenu_SetSelectedValue, owner, item.key) end
        if UIDropDownMenu_SetText then pcall(UIDropDownMenu_SetText, owner, item.label or tostring(item.key or "")) end
    end
    DD_Close()
end

local function DD_GetItem(index)
    if _itemPool[index] then return _itemPool[index] end
    DD_EnsureList()
    local btn = CreateFrame("Button", nil, _listFrame._child)
    btn:SetHeight(DD_ITEM_H)
    -- Highlight (ADD blend so text stays bright, not darkened)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(DD_HOVER[1], DD_HOVER[2], DD_HOVER[3], 0.35)
    hl:SetBlendMode("ADD")
    -- Selected indicator: subtle gold left bar (hidden by default)
    local sel = btn:CreateTexture(nil, "OVERLAY")
    sel:SetColorTexture(DD_CHECK[1], DD_CHECK[2], DD_CHECK[3], 0.9)
    sel:SetSize(2, DD_ITEM_H - 4)
    sel:SetPoint("LEFT", btn, "LEFT", 2, 0)
    sel:Hide()
    btn._sel = sel
    -- Icon (optional, for texture swatches)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("LEFT", btn, "LEFT", 10, 0)
    icon:SetSize(80, 12)
    icon:Hide()
    btn._icon = icon
    -- Label
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", btn, "LEFT", 10, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    label:SetJustifyH("LEFT")
    label:SetTextColor(DD_TEXT[1], DD_TEXT[2], DD_TEXT[3])
    btn._label = label
    -- Click
    btn:SetScript("OnClick", DD_ItemClick)
    -- Mousewheel passthrough
    btn:EnableMouseWheel(true)
    btn:SetScript("OnMouseWheel", function(_, delta)
        if _listFrame then
            local handler = _listFrame:GetScript("OnMouseWheel")
            if handler then handler(_listFrame, delta) end
        end
    end)
    _itemPool[index] = btn
    _itemCount = index
    return btn
end

local function DD_Populate(owner)
    DD_EnsureList()
    local lf = _listFrame
    local spec = owner._ddSpec
    if not spec then return end
    local items = spec.items
    if type(items) == "function" then items = items() end
    if type(items) ~= "table" then return end
    local curKey = spec.get and spec.get() or nil
    local itemH  = spec.itemHeight or DD_ITEM_H
    local maxVis = spec.maxVisible or 12
    -- List width matches the peel button (visual trigger), not UIDropDownMenu chrome
    local peelW = owner._msufPeelButton and owner._msufPeelButton.GetWidth and owner._msufPeelButton:GetWidth()
    local w = (peelW and peelW > 40 and peelW) or spec.width or 200
    local iconW  = spec.iconWidth or 80
    local iconH  = spec.iconHeight or 12
    local count  = #items
    -- Size
    local visCount = count > maxVis and maxVis or count
    local visH = visCount * itemH + 4
    local totalH = count * itemH
    local needScroll = count > maxVis
    lf:SetSize(w + (needScroll and 22 or 4), visH)
    lf._itemH = itemH; lf._totalH = totalH; lf._visH = visH
    -- Scroll child
    local child = lf._child
    child:SetWidth(w)
    child:SetHeight(totalH)
    -- Scrollbar visibility + scrollframe extent
    local sf = lf._sf
    sf:ClearAllPoints()
    sf:SetPoint("TOPLEFT", lf, "TOPLEFT", 2, -2)
    sf:SetPoint("BOTTOMRIGHT", lf, "BOTTOMRIGHT", needScroll and -18 or -2, 2)
    if lf._sb then lf._sb:SetShown(needScroll) end
    -- Populate
    for i = 1, count do
        local item = items[i]
        local btn = DD_GetItem(i)
        btn:SetParent(child)
        btn:SetHeight(itemH)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * itemH)
        btn:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        btn._sel:SetShown(item.key == curKey)
        -- Icon
        if item.icon then
            btn._icon:ClearAllPoints()
            btn._icon:SetPoint("LEFT", btn, "LEFT", 10, 0)
            btn._icon:SetTexture(item.icon)
            btn._icon:SetTexCoord(0, 0.85, 0, 1)
            btn._icon:SetSize(iconW, iconH)
            btn._icon:Show()
            btn._label:ClearAllPoints()
            btn._label:SetPoint("LEFT", btn._icon, "RIGHT", 4, 0)
            btn._label:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
        else
            btn._icon:Hide()
            btn._label:ClearAllPoints()
            btn._label:SetPoint("LEFT", btn, "LEFT", 10, 0)
            btn._label:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
        end
        btn._label:SetText(item.label or item.key or "")
        -- Per-item font preview (e.g. font dropdown shows each font in its own typeface)
        if item.fontObject then
            btn._label:SetFontObject(item.fontObject)
        elseif btn._fontOverridden then
            btn._label:SetFontObject(GameFontHighlight)
        end
        btn._fontOverridden = (item.fontObject ~= nil)
        btn._ddItem = item
        btn._ddOwner = owner
        btn:Show()
    end
    -- Hide excess
    for i = count + 1, _itemCount do
        local b = _itemPool[i]
        if b then b:Hide() end
    end
    if sf.SetVerticalScroll then sf:SetVerticalScroll(0) end
end

local function DD_Toggle(owner)
    DD_EnsureList()
    if _listOwner == owner and _listFrame:IsShown() then DD_Close(); return end
    if _listFrame:IsShown() then DD_Close() end
    _listOwner = owner
    DD_Populate(owner)
    _listFrame:ClearAllPoints()
    -- Anchor to the peel button (visible superellipse) if available, else the frame
    local anchorTo = owner._msufPeelButton or owner
    _listFrame:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -2)
    _listBackdrop:Show()
    _listFrame:Show()
end

-- ---- 4g. Dropdown (spec-driven, own ListFrame, superellipse trigger) ----
function UI.Dropdown(spec)
    local parent = spec.parent
    local w = spec.width or 200
    -- Create trigger via MSUF_CreateStyledDropdown (superellipse Peel styling)
    -- Falls back to plain UIDropDownMenuTemplate if style system not loaded yet
    local CreateSD = _G.MSUF_CreateStyledDropdown
    local dd
    if CreateSD then
        dd = CreateSD(spec.name, parent)
    else
        dd = CreateFrame("Frame", spec.name, parent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_SetWidth(dd, w)
    if spec.anchor then
        dd:ClearAllPoints()
        -- UIDropDownMenuTemplate has ~16px built-in left padding; compensate automatically
        dd:SetPoint("TOPLEFT", spec.anchor, spec.anchorPoint or "BOTTOMLEFT", spec.x or 0, spec.y or -4)
    end
    -- Neuter Blizzard init (prevent ToggleDropDownMenu from firing)
    UIDropDownMenu_Initialize(dd, function() end)
    -- Hijack click: peel button (superellipse) or native button → open our list
    local function OnSpecClick()
        DD_Toggle(dd)
    end
    local peelBtn = dd._msufPeelButton
    if peelBtn then peelBtn:SetScript("OnClick", OnSpecClick) end
    local dname = dd.GetName and dd:GetName()
    local nativeBtn = dd.Button or (dname and _G[dname .. "Button"])
    if nativeBtn then nativeBtn:SetScript("OnClick", OnSpecClick) end
    -- Spec
    dd._ddSpec = spec
    dd._ddKey = nil
    -- API: SetValue — updates both UIDropDownMenu text AND peel text
    function dd:SetValue(key)
        self._ddKey = key
        local label = tostring(key or "")
        local items = self._ddSpec.items
        if type(items) == "function" then items = items() end
        if type(items) == "table" then
            for i = 1, #items do
                if items[i].key == key then
                    label = items[i].label or label
                    break
                end
            end
        end
        -- UIDropDownMenu_SetText syncs through to peel text via Style hooks
        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(self, key) end
        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(self, label) end
    end
    function dd:GetValue() return self._ddKey end
    function dd:Refresh()
        local key = self._ddSpec.get and self._ddSpec.get() or nil
        self:SetValue(key)
        if _listOwner == self and _listFrame and _listFrame:IsShown() then
            DD_Populate(self)
        end
    end
    function dd:SetEnabled(enabled)
        if enabled then
            self:SetAlpha(1)
            if UIDropDownMenu_EnableDropDown then UIDropDownMenu_EnableDropDown(self) end
        else
            DD_Close()
            self:SetAlpha(0.45)
            if UIDropDownMenu_DisableDropDown then UIDropDownMenu_DisableDropDown(self) end
        end
    end
    -- Self-sync on Show
    dd:HookScript("OnShow", function(self) self:Refresh() end)
    -- Initial sync
    dd:Refresh()
    if spec.tooltip then AttachTooltip(dd, spec.tooltip) end
    return dd
end

-- ============================================================
-- 6. SharedMedia Texture Items Builder
-- ============================================================
function UI.StatusBarTextureItems(followText)
    local LSM = (ns and ns.LSM) or _G.MSUF_LSM
    local list
    if LSM and type(LSM.List) == "function" then
        list = LSM:List("statusbar")
    end
    if type(list) ~= "table" or #list == 0 then
        list = { "Blizzard", "Flat", "RaidHP", "RaidPower", "Skills", "Outline" }
    end
    table.sort(list, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
    local result = {}
    if followText then
        result[1] = { key = "", label = TR(followText) }
    end
    for i = 1, #list do
        local name = list[i]
        local icon
        if type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then
            icon = _G.MSUF_ResolveStatusbarTextureKey(name)
        elseif LSM and type(LSM.Fetch) == "function" then
            local ok, tex = pcall(LSM.Fetch, LSM, "statusbar", name, true)
            if ok then icon = tex end
        end
        result[#result + 1] = { key = name, label = name, icon = icon }
    end
    return result
end

-- ============================================================
-- 7. Scroll Height Helper
-- ============================================================
local _scrollPending = {}
local math_ceil = math.ceil

function UI.QueueScrollUpdate(host, scrollKey, childKey, contentKey)
    if not host then return end
    local id = scrollKey or "_scroll"
    if _scrollPending[host] and _scrollPending[host][id] then return end
    _scrollPending[host] = _scrollPending[host] or {}
    _scrollPending[host][id] = true
    local function run()
        _scrollPending[host][id] = nil
        local scroll = host[scrollKey or "_scroll"]
        local child  = host[childKey or "_child"]
        if not (scroll and child) then return end
        local top = child.GetTop and child:GetTop()
        if not top then return end
        local lowest = top
        local content = host[contentKey or "_content"]
        if content and content.GetChildren then
            local regions = { content:GetChildren() }
            for i = 1, #regions do
                local r = regions[i]
                if r and r.IsShown and r:IsShown() and r.GetBottom then
                    local b = r:GetBottom()
                    if b and b < lowest then lowest = b end
                end
            end
        end
        local h = math_ceil((top - lowest) + 32)
        if h < 500 then h = 500 end
        child:SetHeight(h)
        local w = scroll:GetWidth()
        if w and w > 1 then child:SetWidth(w) end
        if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
        if _G.UIPanelScrollFrame_Update then _G.UIPanelScrollFrame_Update(scroll) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end

-- ============================================================
-- 8. Button Row Builder
-- ============================================================
function UI.ButtonRow(parent, anchor, gap, defs)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(1, 1)
    local buttons = {}
    local last
    gap = tonumber(gap) or 8
    for i = 1, #defs do
        local d = defs[i]
        local id = d.id or ("b" .. i)
        local btn = UI.Button({ parent = parent, name = d.name, text = d.text, onClick = d.onClick, width = d.w, height = d.h })
        buttons[id] = btn
        if not last then
            btn:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(tonumber(d.y) or 10))
        else
            btn:SetPoint("LEFT", last, "RIGHT", gap, 0)
        end
        last = btn
    end
    if last and defs[1] then
        local first = buttons[defs[1].id or "b1"]
        if first then
            row:SetPoint("TOPLEFT", first, "TOPLEFT", 0, 0)
            row:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", 0, 0)
        end
    end
    return row, buttons
end

-- ============================================================
-- 9. Backward-Compat Stubs (for Auras/Colors/EditMode)
-- ============================================================

-- These stay functional for non-migrated consumers:
local function MSUF_InitSimpleDropdown(dropdown, options, getCurrentKey, setCurrentKey, onSelect, width)
    if not dropdown then return end
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        local cur = getCurrentKey and getCurrentKey() or nil
        for _, opt in ipairs(options or {}) do
            info.text = opt.menuText or opt.label
            info.value = opt.key
            info.checked = (opt.key == cur)
            info.func = function(btn)
                if setCurrentKey then setCurrentKey(btn.value) end
                UIDropDownMenu_SetSelectedValue(dropdown, btn.value)
                UIDropDownMenu_SetText(dropdown, opt.label)
                if type(onSelect) == "function" then onSelect(btn.value, opt)
                elseif type(onSelect) == "string" and type(_G.MSUF_Options_Apply) == "function" then _G.MSUF_Options_Apply(onSelect, btn.value, opt) end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    if width then UIDropDownMenu_SetWidth(dropdown, width) end
    local cur = getCurrentKey and getCurrentKey() or nil
    local label = (options and options[1] and options[1].label) or ""
    for _, opt in ipairs(options or {}) do
        if opt.key == cur then label = opt.label; break end
    end
    UIDropDownMenu_SetSelectedValue(dropdown, cur)
    UIDropDownMenu_SetText(dropdown, label)
end

local function MSUF_SyncSimpleDropdown(dropdown, options, getCurrentKey)
    if not dropdown or not options or not getCurrentKey then return end
    local cur = getCurrentKey()
    if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(dropdown, cur) end
    for _, opt in ipairs(options) do
        if opt.key == cur then
            if UIDropDownMenu_SetText then UIDropDownMenu_SetText(dropdown, opt.label) end
            break
        end
    end
end

-- No-op stubs (consumers still call these but they do nothing with new dropdown system)
local function MSUF_MakeDropdownScrollable() end
local function MSUF_ExpandDropdownClickArea() end

-- ============================================================
-- 10. Exports
-- ============================================================
UI.AttachTooltip         = AttachTooltip
UI.StyleSlider           = StyleSlider
UI.StyleSmallButton      = StyleSmallButton
UI.StyleToggleText       = StyleToggleText
UI.StyleCheckmark        = StyleCheckmark
UI.CloseDropdown         = DD_Close

-- ns.* exports (split modules use ns.*)
ns.MSUF_AttachTooltip           = AttachTooltip
ns.MSUF_UI_Text                 = function(p, t, tmpl) local fs = p:CreateFontString(nil, "ARTWORK", tmpl or "GameFontNormal"); fs:SetText(t or ""); return fs end
ns.MSUF_UI_Btn                  = function(p, n, l, fn, w, h) return UI.Button({ parent = p, name = n, text = l, onClick = fn, width = w, height = h }) end
ns.MSUF_BuildButtonRowList      = UI.ButtonRow
ns.MSUF_MakeDropdownScrollable  = MSUF_MakeDropdownScrollable
ns.MSUF_ExpandDropdownClickArea = MSUF_ExpandDropdownClickArea
ns.MSUF_InitSimpleDropdown      = MSUF_InitSimpleDropdown
ns.MSUF_SyncSimpleDropdown      = MSUF_SyncSimpleDropdown
ns.MSUF_GetLSM                  = function() return (ns and ns.LSM) or _G.MSUF_LSM end

-- _G exports (backward compat)
_G.MSUF_InitSimpleDropdown      = _G.MSUF_InitSimpleDropdown   or MSUF_InitSimpleDropdown
_G.MSUF_SyncSimpleDropdown      = _G.MSUF_SyncSimpleDropdown   or MSUF_SyncSimpleDropdown
_G.MSUF_MakeDropdownScrollable  = _G.MSUF_MakeDropdownScrollable or MSUF_MakeDropdownScrollable
_G.MSUF_ExpandDropdownClickArea = _G.MSUF_ExpandDropdownClickArea or MSUF_ExpandDropdownClickArea
_G.MSUF_CloseSpecDropdown       = DD_Close

-- Style exports (Core and other files use these)
ns.MSUF_StyleSlider             = StyleSlider
ns.MSUF_StyleSmallButton        = StyleSmallButton
ns.MSUF_StyleToggleText         = StyleToggleText
ns.MSUF_StyleCheckmark          = StyleCheckmark
_G.MSUF_StyleToggleText         = _G.MSUF_StyleToggleText or StyleToggleText
_G.MSUF_StyleCheckmark          = _G.MSUF_StyleCheckmark or StyleCheckmark

-- =====================================================================
-- Auto-Intercept: Styled Dropdowns → Toolkit List
--
-- Any frame created by MSUF_CreateStyledDropdown (has ._msufPeelButton)
-- that uses UIDropDownMenu_Initialize will automatically open the
-- Toolkit's styled list instead of Blizzard's DropDownList1.
--
-- Zero changes needed in Player, Colors, Auras, Gameplay.
-- =====================================================================
do
    -- Capture buffer for UIDropDownMenu_AddButton interception
    local _captureActive = false
    local _captureItems = {}
    local _captureOwner = nil

    -- Hook UIDropDownMenu_AddButton to capture items when we're intercepting
    local _origAddButton = UIDropDownMenu_AddButton
    if _origAddButton then
        UIDropDownMenu_AddButton = function(info, level, ...)
            if _captureActive and info then
                -- Skip title/separator items
                if not info.isTitle and not info.disabled then
                    _captureItems[#_captureItems + 1] = {
                        key    = info.value,
                        label  = info.text or tostring(info.value or ""),
                        icon   = info.icon,
                        func   = info.func,
                        arg1   = info.arg1,
                        arg2   = info.arg2,
                        checked = info.checked,
                    }
                end
                return  -- don't add to Blizzard's list
            end
            return _origAddButton(info, level, ...)
        end
    end

    -- Hook ToggleDropDownMenu to intercept styled dropdowns
    local _origToggle = ToggleDropDownMenu
    if _origToggle then
        ToggleDropDownMenu = function(level, value, dropDown, anchorName, xOff, yOff, menuList, button, autoHide)
            -- Only intercept level-1 opens on styled MSUF dropdowns
            local dd = dropDown
            if dd and dd._msufPeelButton and (level == 1 or level == nil) and dd.initialize then
                -- Capture items from the init function
                _captureActive = true
                _captureItems = {}
                _captureOwner = dd
                pcall(dd.initialize, dd, 1)
                _captureActive = false

                if #_captureItems > 0 then
                    -- Build spec for Toolkit list
                    local curKey = nil
                    for _, it in ipairs(_captureItems) do
                        local ck = it.checked
                        if type(ck) == "function" then
                            if ck() then curKey = it.key; break end
                        elseif ck then
                            curKey = it.key; break
                        end
                    end

                    -- Store a temporary spec
                    dd._ddSpec = {
                        items = _captureItems,
                        get = function() return curKey end,
                        set = function(v, item)
                            -- Find and call the original func
                            if item and item.func then
                                -- Create a fake button with .value
                                local fakeBtn = { value = v }
                                pcall(item.func, fakeBtn, item.arg1, item.arg2)
                            end
                        end,
                        width = dd._msufPeelButton and dd._msufPeelButton:GetWidth() or 200,
                    }
                    DD_Toggle(dd)
                    return
                end
            end
            -- Fallback to Blizzard's default
            return _origToggle(level, value, dropDown, anchorName, xOff, yOff, menuList, button, autoHide)
        end
    end
end

-- Also export UI.BindExistingDropdown for explicit use (e.g. refactored Bars)
function UI.BindExistingDropdown(dd, spec)
    if not dd or not spec then return dd end
    UIDropDownMenu_Initialize(dd, function() end)
    local function OnSpecClick() DD_Toggle(dd) end
    local peelBtn = dd._msufPeelButton
    if peelBtn then peelBtn:SetScript("OnClick", OnSpecClick) end
    local dname = dd.GetName and dd:GetName()
    local nativeBtn = dd.Button or (dname and _G[dname .. "Button"])
    if nativeBtn then nativeBtn:SetScript("OnClick", OnSpecClick) end
    dd._ddSpec = spec; dd._ddKey = nil
    function dd:SetValue(key)
        self._ddKey = key; local label = tostring(key or "")
        local items = self._ddSpec.items
        if type(items) == "function" then items = items() end
        if type(items) == "table" then for _, it in ipairs(items) do if it.key == key then label = it.label or label; break end end end
        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(self, key) end
        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(self, label) end
    end
    function dd:GetValue() return self._ddKey end
    function dd:Refresh()
        local key = self._ddSpec.get and self._ddSpec.get() or nil; self:SetValue(key)
        if _listOwner == self and _listFrame and _listFrame:IsShown() then DD_Populate(self) end
    end
    dd:HookScript("OnShow", function(self) self:Refresh() end)
    dd:Refresh()
    return dd
end
