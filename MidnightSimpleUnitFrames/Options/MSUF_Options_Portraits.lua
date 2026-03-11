-- Options/MSUF_Options_Portraits.lua
-- Dedicated portrait styling panel.
-- Scope system matches MSUF_Options_Bars.lua: Shared + per-unit dropdown + override checkbox.
-- All render types (2D / 3D / CLASS) are configurable here.
-- Frame Basics retains ONLY the anchor/position dropdown (LEFT/RIGHT/OFF).
--
-- DB contract (scope-aware):
--   Shared:   MSUF_DB.general.portraitShape / portraitBorderStyle / …
--   Per-unit:  MSUF_DB[unitKey].portraitDecoOverride = true  +  per-unit keys
--   Runtime resolution: if override → per-unit, else → general

local addonName, ns = ...
ns = ns or {}

local type, tonumber, pairs, ipairs, floor = type, tonumber, pairs, ipairs, math.floor
local CreateFrame = CreateFrame
local EnsureDB = ns.EnsureDB or function() if type(_G.EnsureDB) == "function" then _G.EnsureDB() end end
local UI = ns.UI or {}
local TR = ns.TR or function(v) return v end

local ALL_UNITS = { "player", "target", "focus", "targettarget", "pet", "boss" }
local TEX_W8 = "Interface\\Buttons\\WHITE8x8"

-- ────────────────────────────────────────────────────────────
-- Widget helpers
-- ────────────────────────────────────────────────────────────
local StyleToggleText = (UI and UI.StyleToggleText) or function() end
local StyleCheckmark  = (UI and UI.StyleCheckmark) or function() end
local AttachTooltip   = (UI and UI.AttachTooltip) or function() end

local function MakeGroupBox(parent, titleText, x, y, w, h)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(w, h); f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    f:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    f:SetBackdropColor(0.08, 0.08, 0.10, 0.85); f:SetBackdropBorderColor(0.25, 0.25, 0.28, 0.9)
    if titleText then
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6); t:SetText(titleText); f._msufTitleText = t
    end
    return f
end

local function MakeCheck(parent, name, label, x, y, tip)
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local fs = cb.text or cb.Text or (name and _G[name .. "Text"])
    if fs then fs:SetText(label); fs:SetFontObject("GameFontNormalSmall") end
    StyleToggleText(cb); StyleCheckmark(cb)
    if tip then AttachTooltip(cb, label, tip) end
    return cb
end

local function MakeLabel(parent, text, x, y, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); fs:SetText(text); return fs
end

-- Slider with edit box + minus/plus (matches CreateLabeledSlider pattern from Options_Core)
local function MakeSliderWithEdit(parent, name, label, x, y, minV, maxV, step, width)
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    s:SetWidth(width or 160); s:SetHeight(16)
    s:SetMinMaxValues(minV, maxV); s:SetValueStep(step); s:SetObeyStepOnDrag(true)
    s.minVal, s.maxVal, s.step = minV, maxV, step
    local low = name and _G[name .. "Low"]; if low then low:SetText(tostring(minV)) end
    local high = name and _G[name .. "High"]; if high then high:SetText(tostring(maxV)) end
    local txt = name and _G[name .. "Text"]; if txt then txt:SetText(label or "") end
    -- Edit box
    local eb = CreateFrame("EditBox", name and (name .. "Input") or nil, parent, "InputBoxTemplate")
    eb:SetSize(48, 18); eb:SetAutoFocus(false); eb:SetJustifyH("CENTER")
    eb:SetPoint("TOP", s, "BOTTOM", 0, -4)
    if GameFontHighlightSmall then eb:SetFontObject(GameFontHighlightSmall) end
    if eb.SetTextColor then eb:SetTextColor(1, 1, 1, 1) end
    s.editBox = eb
    local function SyncEB(val) if step >= 1 then val = floor(val + 0.5) end; eb:SetText(tostring(val)) end
    s:HookScript("OnValueChanged", function(self, val) SyncEB(val) end)
    local function ApplyEB()
        local val = tonumber(eb:GetText()); if not val then SyncEB(s:GetValue()); return end
        val = math.max(minV, math.min(maxV, val)); s:SetValue(val)
    end
    eb:SetScript("OnEnterPressed", function(self) ApplyEB(); self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", function() ApplyEB() end)
    eb:SetScript("OnEscapePressed", function(self) SyncEB(s:GetValue()); self:ClearFocus() end)
    -- +/- buttons
    local mi = CreateFrame("Button", nil, parent); mi:SetSize(18, 18)
    mi:SetPoint("RIGHT", eb, "LEFT", -1, 0)
    local mfs = mi:CreateFontString(nil, "OVERLAY", "GameFontNormal"); mfs:SetText("\226\128\147"); mfs:SetAllPoints(); mi:SetFontString(mfs)
    mi:SetScript("OnClick", function() s:SetValue(math.max(minV, s:GetValue() - step)) end)
    local pl = CreateFrame("Button", nil, parent); pl:SetSize(18, 18)
    pl:SetPoint("LEFT", eb, "RIGHT", 1, 0)
    local pfs = pl:CreateFontString(nil, "OVERLAY", "GameFontNormal"); pfs:SetText("+"); pfs:SetAllPoints(); pl:SetFontString(pfs)
    pl:SetScript("OnClick", function() s:SetValue(math.min(maxV, s:GetValue() + step)) end)
    s._minus, s._plus = mi, pl
    function s:SetAllEnabled(ena)
        if ena then self:Enable(); self:SetAlpha(1) else self:Disable(); self:SetAlpha(0.4) end
        eb:SetEnabled(ena); mi:SetEnabled(ena); pl:SetEnabled(ena)
    end
    return s
end

-- ────────────────────────────────────────────────────────────
-- Data
-- ────────────────────────────────────────────────────────────
local SCOPE_ITEMS = {
    { key = "shared", label = "Shared" },
    { key = "player", label = "Player" }, { key = "target", label = "Target" },
    { key = "focus",  label = "Focus" },  { key = "targettarget", label = "ToT" },
    { key = "boss",   label = "Boss" },   { key = "pet", label = "Pet" },
}
local SHAPE_ITEMS = {
    { key = "SQUARE", label = "Square" }, { key = "CIRCLE", label = "Circle" },
}
local BORDER_ITEMS = {
    { key = "NONE", label = "None" }, { key = "SOLID", label = "Solid (White)" },
    { key = "CLASS_COLOR", label = "Class Color" }, { key = "REACTION", label = "Reaction Color" },
    { key = "CUSTOM", label = "Custom Color" },
}
local RENDER_ITEMS = {
    { key = "2D", label = "2D Portrait" }, { key = "3D", label = "3D Portrait" },
    { key = "CLASS", label = "Class Icon" },
}

-- Keys inherited from general → per-unit when enabling override
local DECO_KEYS = {
    "portraitShape", "portraitSizeOverride", "portraitOffsetX", "portraitOffsetY",
    "portraitBorderStyle", "portraitBorderThickness",
    "portraitBorderColorR", "portraitBorderColorG", "portraitBorderColorB", "portraitBorderColorA",
    "portraitBgEnabled", "portraitBgColorR", "portraitBgColorG", "portraitBgColorB", "portraitBgColorA",
    "portraitClassStyle", "portraitFillBorder",
}

-- ════════════════════════════════════════════════════════════
-- BUILD
-- ════════════════════════════════════════════════════════════
function ns.MSUF_RegisterPortraitsOptions_Full(parentCategory)
    local panel = (_G and _G.MSUF_PortraitsPanel) or CreateFrame("Frame", "MSUF_PortraitsPanel", UIParent)
    _G.MSUF_PortraitsPanel = panel; panel:SetSize(780, 620)
    if panel.__MSUF_PortraitsBuilt then return panel end

    -- Settings registration
    if not (_G and _G.MSUF_SLASHMENU_ONLY) and parentCategory then
        if Settings and Settings.RegisterCanvasLayoutSubcategory and not panel.__MSUF_SettingsRegistered then
            panel.name = "Portraits"
            local sub = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
            Settings.RegisterAddOnCategory(sub); ns.MSUF_PortraitsCategory = sub
            panel.__MSUF_SettingsRegistered = true
        end
    end

    -- ─── State ───
    local function G() EnsureDB(); MSUF_DB.general = MSUF_DB.general or {}; return MSUF_DB.general end
    local function U(k) EnsureDB(); MSUF_DB[k] = MSUF_DB[k] or {}; return MSUF_DB[k] end

    local function GetScopeKey() return G()._portraitScopeKey or "shared" end
    local function GetUnitKey()
        local k = GetScopeKey()
        if k == "shared" then return nil end
        return k
    end
    local function IsOverride(uk) return U(uk).portraitDecoOverride == true end

    local function EnableOverride(uk)
        local u = U(uk); local g = G()
        u.portraitDecoOverride = true
        for _, k in ipairs(DECO_KEYS) do
            if u[k] == nil then u[k] = g[k] end
        end
    end

    local function ScopeGet(key, def)
        local uk = GetUnitKey()
        if uk and IsOverride(uk) then
            local v = U(uk)[key]
            if v ~= nil then return v end
        end
        local v = G()[key]
        return (v ~= nil) and v or def
    end

    local function ScopeSet(key, val)
        local uk = GetUnitKey()
        if uk then
            if not IsOverride(uk) then EnableOverride(uk) end
            U(uk)[key] = val
        else
            G()[key] = val
            -- Propagate to all non-override per-unit configs so runtime
            -- reads the correct value directly (no R() fallback needed).
            for _, k in ipairs(ALL_UNITS) do
                local u = U(k)
                if not u.portraitDecoOverride then u[key] = val end
            end
        end
    end

    local function LiveApply()
        local uk = GetUnitKey()
        local sync = _G.MSUF_PortraitDecoration_SyncUnit
        local sync3d = _G.MSUF_3DPortraits_SyncUnit
        if uk then
            if type(sync) == "function" then pcall(sync, uk) end
            if type(sync3d) == "function" then pcall(sync3d, uk) end
        else
            for _, k in ipairs(ALL_UNITS) do
                if type(sync) == "function" then pcall(sync, k) end
                if type(sync3d) == "function" then pcall(sync3d, k) end
            end
        end
    end
    local function Apply()
        if type(_G.ApplyAllSettings) == "function" then _G.ApplyAllSettings() end
    end

    -- Forward ref
    local SyncScopeUI

    -- ─── Title ───
    local titleFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFS:SetPoint("TOPLEFT", 16, -16); titleFS:SetText("Portrait Settings")

    -- ─── Scope Header ───
    local scopeLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    scopeLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -44); scopeLabel:SetText(TR("Configure for"))

    local scopeDrop
    if UI.Dropdown then
        scopeDrop = UI.Dropdown({
            name = "MSUF_PortraitScopeDD", parent = panel,
            anchor = scopeLabel, anchorPoint = "TOPLEFT", x = 90, y = 4, width = 160,
            items = SCOPE_ITEMS,
            get = function() return GetScopeKey() end,
            set = function(v) G()._portraitScopeKey = v; SyncScopeUI() end,
        })
    end

    -- Override checkbox
    local overrideCheck = CreateFrame("CheckButton", "MSUF_PortraitOverrideCheck", panel, "UICheckButtonTemplate")
    if scopeDrop then
        overrideCheck:SetPoint("LEFT", scopeDrop, "RIGHT", -10, 0)
    else
        overrideCheck:SetPoint("TOPLEFT", scopeLabel, "TOPRIGHT", 200, 2)
    end
    local ocFS = overrideCheck.text or overrideCheck.Text or _G["MSUF_PortraitOverrideCheckText"]
    if ocFS then ocFS:SetText(TR("Override shared")); ocFS:SetFontObject("GameFontNormalSmall") end
    StyleToggleText(overrideCheck); StyleCheckmark(overrideCheck)
    AttachTooltip(overrideCheck, "Per-unit override", "When unchecked, this unit inherits Shared settings.")

    overrideCheck:SetScript("OnClick", function(self)
        local uk = GetUnitKey()
        if not uk then self:SetChecked(false); return end
        if self:GetChecked() then EnableOverride(uk) else U(uk).portraitDecoOverride = false end
        Apply(); LiveApply(); SyncScopeUI()
    end)

    -- Reset button
    local resetBtn = CreateFrame("Button", "MSUF_PortraitResetBtn", panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(140, 22); resetBtn:SetPoint("TOPLEFT", overrideCheck, "TOPLEFT", 0, 2)
    resetBtn:SetText(TR("Reset all overrides")); resetBtn:SetNormalFontObject("GameFontNormalSmall"); resetBtn:Hide()
    resetBtn:SetScript("OnClick", function()
        EnsureDB()
        for _, k in ipairs(ALL_UNITS) do
            local u = MSUF_DB[k]; if u then u.portraitDecoOverride = false end
        end
        Apply(); LiveApply(); SyncScopeUI()
    end)

    -- ─── Content ───
    local content = CreateFrame("Frame", nil, panel)
    content:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -76)
    content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

    -- ═══ Render Type ═══
    local renderBox = MakeGroupBox(content, "Portrait Type", 16, -4, 350, 55)
    MakeLabel(renderBox, "Type", 12, -26)
    local renderDrop
    if UI.Dropdown then
        renderDrop = UI.Dropdown({
            name = "MSUF_PortraitRenderDD", parent = renderBox,
            anchor = renderBox, anchorPoint = "TOPLEFT", x = 48, y = -18, width = 170,
            items = RENDER_ITEMS,
            get = function()
                local uk = GetUnitKey()
                if uk then return U(uk).portraitRender or "2D" end
                return G()._portraitSharedRender or "2D"
            end,
            set = function(v)
                local uk = GetUnitKey()
                if uk then
                    if not IsOverride(uk) then EnableOverride(uk) end
                    U(uk).portraitRender = v
                    if type(_G.MSUF_3DPortraits_SyncUnit) == "function" then
                        pcall(_G.MSUF_3DPortraits_SyncUnit, uk)
                    end
                else
                    G()._portraitSharedRender = v
                    for _, k in ipairs(ALL_UNITS) do
                        local u = U(k)
                        if not u.portraitDecoOverride then u.portraitRender = v end
                    end
                    for _, k in ipairs(ALL_UNITS) do
                        if type(_G.MSUF_3DPortraits_SyncUnit) == "function" then
                            pcall(_G.MSUF_3DPortraits_SyncUnit, k)
                        end
                    end
                end
                Apply(); SyncScopeUI()
            end,
        })
    end

    -- ═══ Class Style (only CLASS render) ═══
    local classBox = MakeGroupBox(content, "Class Portrait Style", 16, -67, 350, 55)
    local PM = ns.PortraitMedia
    local function ClassItems()
        local t = {}
        local opts = (PM and PM.GetPackOptions and PM.GetPackOptions()) or {{ value = "BLIZZARD", text = "Blizzard Class Icon" }}
        for _, o in ipairs(opts) do t[#t + 1] = { key = o.value, label = o.text } end
        return t
    end
    local classDrop
    if UI.Dropdown then
        classDrop = UI.Dropdown({
            name = "MSUF_PortraitClassStyleDD2", parent = classBox,
            anchor = classBox, anchorPoint = "TOPLEFT", x = -6, y = -20, width = 220,
            items = ClassItems,
            get = function() return ScopeGet("portraitClassStyle", "BLIZZARD") end,
            set = function(v)
                ScopeSet("portraitClassStyle", v)
                LiveApply()
                SyncScopeUI()
            end,
        })
    end

    -- ═══ Shape & Size ═══
    local shapeBox = MakeGroupBox(content, "Shape & Size", 16, -130, 350, 185)
    MakeLabel(shapeBox, "Shape", 12, -28)
    local shapeDrop
    if UI.Dropdown then
        shapeDrop = UI.Dropdown({
            name = "MSUF_PortraitShapeDD", parent = shapeBox,
            anchor = shapeBox, anchorPoint = "TOPLEFT", x = 48, y = -20, width = 105,
            items = SHAPE_ITEMS,
            get = function() return ScopeGet("portraitShape", "SQUARE") end,
            set = function(v) ScopeSet("portraitShape", v); LiveApply() end,
        })
    end

    local sizeCheck = MakeCheck(shapeBox, "MSUF_PortraitSizeCheck", "Custom size", 8, -56,
        "Override auto size (frame height minus 4px)")
    local sizeSlider = MakeSliderWithEdit(shapeBox, "MSUF_PortraitSizeSlider", "Size (px)", 140, -50, 16, 80, 1, 160)

    sizeCheck:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        if not on then ScopeSet("portraitSizeOverride", 0)
        else ScopeSet("portraitSizeOverride", floor(sizeSlider:GetValue() + 0.5))
        end
        sizeSlider:SetAllEnabled(on)
        -- Force toggle text color update
        if self._msufToggleUpdate then self._msufToggleUpdate() end
        LiveApply()
    end)
    sizeSlider:SetScript("OnValueChanged", function(self, val)
        val = floor(val + 0.5)
        if self.editBox then self.editBox:SetText(tostring(val)) end
        if sizeCheck:GetChecked() then ScopeSet("portraitSizeOverride", val); LiveApply() end
    end)

    local oxSlider = MakeSliderWithEdit(shapeBox, "MSUF_PortraitOXSlider", "Offset X", 12, -105, -500, 500, 1, 130)
    local oySlider = MakeSliderWithEdit(shapeBox, "MSUF_PortraitOYSlider", "Offset Y", 186, -105, -500, 500, 1, 130)

    oxSlider:SetScript("OnValueChanged", function(self, val)
        val = floor(val + 0.5)
        if self.editBox then self.editBox:SetText(tostring(val)) end
        ScopeSet("portraitOffsetX", val); LiveApply()
    end)
    oySlider:SetScript("OnValueChanged", function(self, val)
        val = floor(val + 0.5)
        if self.editBox then self.editBox:SetText(tostring(val)) end
        ScopeSet("portraitOffsetY", val); LiveApply()
    end)

    -- Fill Border toggle (2D/3D only — stretches portrait to fill border bounds)
    local fillCheck = MakeCheck(shapeBox, "MSUF_PortraitFillBorderCheck",
        "Stretch portrait into border", 8, -148,
        "Portrait fills the full border area instead of sitting inside it. Best with Circle/Diamond borders.")
    fillCheck:SetScript("OnClick", function(self)
        ScopeSet("portraitFillBorder", self:GetChecked() and true or false)
        if self._msufToggleUpdate then self._msufToggleUpdate() end
        LiveApply()
    end)

    -- ═══ Border ═══
    local borderBox = MakeGroupBox(content, "Border", 16, -295, 350, 120)
    MakeLabel(borderBox, "Style", 12, -28)
    local borderDrop
    if UI.Dropdown then
        borderDrop = UI.Dropdown({
            name = "MSUF_PortraitBorderDD", parent = borderBox,
            anchor = borderBox, anchorPoint = "TOPLEFT", x = 42, y = -20, width = 180,
            items = BORDER_ITEMS,
            get = function() return ScopeGet("portraitBorderStyle", "NONE") end,
            set = function(v) ScopeSet("portraitBorderStyle", v); LiveApply(); SyncScopeUI() end,
        })
    end

    local thickSlider = MakeSliderWithEdit(borderBox, "MSUF_PortraitThickSlider", "Thickness", 12, -68, 1, 6, 1, 160)
    thickSlider:SetScript("OnValueChanged", function(self, val)
        val = floor(val + 0.5)
        if self.editBox then self.editBox:SetText(tostring(val)) end
        ScopeSet("portraitBorderThickness", val); LiveApply()
    end)

    local borderColorHint = MakeLabel(borderBox, "Color: Colors panel", 210, -58)
    borderColorHint:SetTextColor(0.5, 0.5, 0.5)

    -- ═══ Background ═══
    local bgBox = MakeGroupBox(content, "Background", 16, -425, 350, 130)
    local bgCheck = MakeCheck(bgBox, "MSUF_PortraitBgCheck", "Show background", 8, -28)
    bgCheck:SetScript("OnClick", function(self)
        ScopeSet("portraitBgEnabled", self:GetChecked() and true or false)
        if self._msufToggleUpdate then self._msufToggleUpdate() end
        LiveApply(); SyncScopeUI()
    end)

    local bgColorHint = MakeLabel(bgBox, "Color: Colors panel", 12, -62)
    bgColorHint:SetTextColor(0.5, 0.5, 0.5)

    local bgOpSlider = MakeSliderWithEdit(bgBox, "MSUF_PortraitBgOpSlider", "Opacity", 140, -56, 0, 100, 5, 160)
    bgOpSlider:SetScript("OnValueChanged", function(self, val)
        val = floor(val + 0.5)
        if self.editBox then self.editBox:SetText(val .. "%") end
        ScopeSet("portraitBgColorA", val / 100); LiveApply()
    end)

    -- ═══════════════════════════════════════════════
    -- Scope UI Sync
    -- ═══════════════════════════════════════════════
    SyncScopeUI = function()
        EnsureDB()
        local uk = GetUnitKey()
        local isUnit = (uk ~= nil)

        -- Override checkbox / reset button
        if isUnit then
            overrideCheck:Show(); overrideCheck:Enable(); overrideCheck:SetAlpha(1)
            overrideCheck:SetChecked(IsOverride(uk))
            resetBtn:Hide()
        else
            overrideCheck:Hide()
            local any = false
            for _, k in ipairs(ALL_UNITS) do
                if U(k).portraitDecoOverride then any = true; break end
            end
            resetBtn:SetShown(any)
        end

        -- Refresh dropdowns
        if scopeDrop and scopeDrop.Refresh then scopeDrop:Refresh() end
        if renderDrop and renderDrop.Refresh then renderDrop:Refresh() end
        if classDrop and classDrop.Refresh then classDrop:Refresh() end
        if shapeDrop and shapeDrop.Refresh then shapeDrop:Refresh() end
        if borderDrop and borderDrop.Refresh then borderDrop:Refresh() end

        -- Render type → show/hide class style box
        local render
        if isUnit then
            render = U(uk).portraitRender or "2D"
        else
            render = G()._portraitSharedRender or "2D"
        end
        classBox:SetShown(render == "CLASS")

        -- Rondo packs have built-in borders → hide Border section
        local isRondo = false
        if render == "CLASS" then
            local style = ScopeGet("portraitClassStyle", "BLIZZARD")
            isRondo = (style == "RONDO_COLOR" or style == "RONDO_WOW")
        end
        borderBox:SetShown(not isRondo)

        -- Rondo has built-in shape → dim shape dropdown
        if shapeDrop then
            if shapeDrop.SetEnabled then
                shapeDrop:SetEnabled(not isRondo)
            else
                shapeDrop:SetAlpha(isRondo and 0.35 or 1)
            end
        end

        -- Dynamic Y layout (shapeBox is 185px tall)
        local yBase = (render == "CLASS") and -130 or -67
        shapeBox:ClearAllPoints(); shapeBox:SetPoint("TOPLEFT", content, "TOPLEFT", 16, yBase)
        local borderY = yBase - 195
        borderBox:ClearAllPoints(); borderBox:SetPoint("TOPLEFT", content, "TOPLEFT", 16, borderY)
        -- If border hidden (Rondo), pull background up
        local bgY = isRondo and (yBase - 195) or (borderY - 130)
        bgBox:ClearAllPoints(); bgBox:SetPoint("TOPLEFT", content, "TOPLEFT", 16, bgY)

        -- Fill Border toggle: only for 2D/3D (not CLASS — Rondo/Blizzard icons don't stretch)
        local showFill = (render ~= "CLASS")
        fillCheck:SetShown(showFill)
        if showFill then
            fillCheck:SetChecked(ScopeGet("portraitFillBorder", false) and true or false)
        end

        -- Size
        local sizeOvr = tonumber(ScopeGet("portraitSizeOverride", 0)) or 0
        local hasSz = (sizeOvr > 0)
        sizeCheck:SetChecked(hasSz); sizeSlider:SetAllEnabled(hasSz)
        sizeSlider:SetValue(hasSz and sizeOvr or 36)

        -- Offsets
        oxSlider:SetValue(tonumber(ScopeGet("portraitOffsetX", 0)) or 0)
        oySlider:SetValue(tonumber(ScopeGet("portraitOffsetY", 0)) or 0)

        -- Border
        local bStyle = ScopeGet("portraitBorderStyle", "NONE")
        borderColorHint:SetShown(bStyle == "CUSTOM")
        thickSlider:SetAllEnabled(bStyle ~= "NONE")
        thickSlider:SetValue(tonumber(ScopeGet("portraitBorderThickness", 2)) or 2)

        -- Background
        local bgEna = ScopeGet("portraitBgEnabled", false) and true or false
        bgCheck:SetChecked(bgEna)
        bgColorHint:SetShown(bgEna)
        bgOpSlider:SetShown(bgEna)
        if bgEna then
            bgOpSlider:SetValue((ScopeGet("portraitBgColorA", 0.85) or 0.85) * 100)
        end
    end

    panel:SetScript("OnShow", function() SyncScopeUI() end)
    SyncScopeUI()

    panel.__MSUF_PortraitsBuilt = true
    return panel
end

-- ────────────────────────────────────────────────────────────
-- Lightweight lazy wrapper
-- ────────────────────────────────────────────────────────────
function ns.MSUF_RegisterPortraitsOptions(parentCategory)
    if _G and _G.MSUF_SLASHMENU_ONLY then return end
    if not Settings or not Settings.RegisterCanvasLayoutSubcategory or not parentCategory then
        return ns.MSUF_RegisterPortraitsOptions_Full(parentCategory)
    end
    local panel = (_G and _G.MSUF_PortraitsPanel) or CreateFrame("Frame", "MSUF_PortraitsPanel", UIParent)
    _G.MSUF_PortraitsPanel = panel; panel.name = "Portraits"
    if not panel.__MSUF_ForceHidden then panel.__MSUF_ForceHidden = true; panel:Hide() end
    if not panel.__MSUF_SettingsRegistered then
        local sub = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
        Settings.RegisterAddOnCategory(sub); ns.MSUF_PortraitsCategory = sub
        panel.__MSUF_SettingsRegistered = true
    end
    if panel.__MSUF_PortraitsBuilt then return panel end
    if not panel.__MSUF_LazyBuildHooked then
        panel.__MSUF_LazyBuildHooked = true
        panel:HookScript("OnShow", function()
            if panel.__MSUF_PortraitsBuilt or panel.__MSUF_PortraitsBuilding then return end
            panel.__MSUF_PortraitsBuilding = true
            ns.MSUF_RegisterPortraitsOptions_Full(parentCategory)
            panel.__MSUF_PortraitsBuilding = nil
        end)
    end
    return panel
end
