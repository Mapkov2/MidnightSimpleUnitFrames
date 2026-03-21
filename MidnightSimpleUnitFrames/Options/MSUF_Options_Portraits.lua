-- Options/MSUF_Options_Portraits.lua
-- Dedicated portrait styling panel (Accordion UX).
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
-- Collapsible section factory (same pattern as ClassPower/Auras)
-- ────────────────────────────────────────────────────────────
local function MakeCollapsibleSection(parent, anchorTo, w, expandedH, titleText, defaultOpen)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(w, expandedH)
    box:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -6)
    box:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
    box:SetBackdropColor(0, 0, 0, 0.18)
    box:SetBackdropBorderColor(1, 1, 1, 0.10)
    box._msufExpandedH = expandedH
    box._msufCollapsed = false
    box._msufDefaultOpen = defaultOpen

    local hdr = CreateFrame("Button", nil, box)
    hdr:SetHeight(24)
    hdr:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    hdr:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)

    local chevron = hdr:CreateTexture(nil, "OVERLAY")
    chevron:SetSize(12, 12)
    chevron:SetPoint("LEFT", hdr, "LEFT", 12, 0)
    chevron:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    chevron:SetVertexColor(0.55, 0.65, 0.82)
    chevron:SetRotation(math.pi * 0.5)

    local titleFS = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleFS:SetPoint("LEFT", chevron, "RIGHT", 6, 0)
    titleFS:SetText(titleText)

    local hint = hdr:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("RIGHT", hdr, "RIGHT", -12, 0)
    hint:SetText("")
    hint:SetTextColor(0.45, 0.52, 0.65)

    local body = CreateFrame("Frame", nil, box)
    body:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -28)
    body:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
    body:Show()
    box._msufBody = body

    local function ApplyState()
        local open = not box._msufCollapsed
        body:SetShown(open)
        box:SetHeight(open and box._msufExpandedH or 28)
        chevron:SetRotation(open and (math.pi * 0.5) or 0)
        hint:SetText(open and "" or TR("click to expand"))
        if type(box._msufOnToggle) == "function" then box._msufOnToggle() end
    end

    hdr:SetScript("OnClick", function()
        box._msufCollapsed = not box._msufCollapsed
        ApplyState()
    end)
    hdr:SetScript("OnEnter", function() end)
    do
        local hl = hdr:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.03)
    end

    box._msufApplyState = ApplyState
    return box, body
end

-- ────────────────────────────────────────────────────────────
-- Data
-- ────────────────────────────────────────────────────────────
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

    local SyncScopeUI
    local PAD_X = 16
    local SEC_W = 740

    -- ─── Title ───
    local titleFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFS:SetPoint("TOPLEFT", PAD_X, -16); titleFS:SetText("Portrait Settings")

    -- ─── Scope Bar (Auras 2.0 pattern: button row + override + reset) ───
    local scopeBar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    scopeBar:SetHeight(62)
    scopeBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -40)
    scopeBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -40)
    scopeBar:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
    scopeBar:SetBackdropColor(0.04, 0.08, 0.18, 0.95)
    scopeBar:SetBackdropBorderColor(0.12, 0.25, 0.50, 0.6)

    local editLbl = scopeBar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    editLbl:SetPoint("TOPLEFT", scopeBar, "TOPLEFT", 10, -10)
    editLbl:SetText(TR("Editing:"))

    local SCOPE_KEYS = { "shared", "player", "target", "targettarget", "focus", "pet", "boss" }
    local labelForKey = {
        shared = "Shared", player = "Player", target = "Target",
        targettarget = "ToT", focus = "Focus", pet = "Pet", boss = "Boss",
    }

    local scopeBtns = {}
    local function RefreshScopeButtons()
        for k, btn in pairs(scopeBtns) do
            if btn and btn._msufApplyState then
                btn:_msufApplyState(GetScopeKey() == k)
            end
        end
    end

    do
        local prevBtn
        for i, k in ipairs(SCOPE_KEYS) do
            local bk = k
            local btn = CreateFrame("Button", nil, scopeBar, "BackdropTemplate")
            btn:SetSize(i == 1 and 56 or 48, 18)
            if not prevBtn then
                btn:SetPoint("LEFT", editLbl, "RIGHT", 8, 0)
            else
                btn:SetPoint("LEFT", prevBtn, "RIGHT", 2, 0)
            end
            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(); bg:SetColorTexture(0.08, 0.12, 0.22, 0.80)
            btn._msufBg = bg
            local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
            border:SetAllPoints()
            border:SetBackdrop({ edgeFile = TEX_W8, edgeSize = 1 })
            border:SetBackdropBorderColor(0.15, 0.30, 0.60, 0.50)
            btn._msufBorder = border
            local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("CENTER", 0, 0); fs:SetText(labelForKey[bk] or bk)
            btn._msufLabel = fs

            btn._msufApplyState = function(self, active)
                local hasOvr = (bk ~= "shared") and IsOverride(bk)
                if active then
                    bg:SetColorTexture(0.12, 0.24, 0.50, 0.95)
                    border:SetBackdropBorderColor(hasOvr and 0.96 or 0.30, hasOvr and 0.80 or 0.55, hasOvr and 0.34 or 1.00, hasOvr and 0.98 or 0.80)
                    fs:SetTextColor(0.90, 0.95, 1.00)
                else
                    bg:SetColorTexture(0.08, 0.12, 0.22, 0.80)
                    if hasOvr then
                        border:SetBackdropBorderColor(0.86, 0.72, 0.28, 0.80)
                        fs:SetTextColor(0.88, 0.90, 0.96)
                    else
                        border:SetBackdropBorderColor(0.15, 0.30, 0.60, 0.50)
                        fs:SetTextColor(0.50, 0.58, 0.72)
                    end
                end
            end
            btn:SetScript("OnClick", function()
                G()._portraitScopeKey = bk
                RefreshScopeButtons()
                SyncScopeUI()
            end)
            btn:SetScript("OnEnter", function(self)
                self._msufBg:SetColorTexture(0.10, 0.18, 0.36, 0.90)
                if GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(labelForKey[bk] or bk, 1, 1, 1)
                    if bk == "shared" then
                        GameTooltip:AddLine("Shared baseline used by units without overrides.", 0.72, 0.78, 0.88, true)
                    else
                        local hasOvr = IsOverride(bk)
                        GameTooltip:AddLine(hasOvr and "Override active." or "Uses Shared settings.", hasOvr and 0.95 or 0.72, hasOvr and 0.82 or 0.78, hasOvr and 0.30 or 0.88, true)
                    end
                    GameTooltip:Show()
                end
            end)
            btn:SetScript("OnLeave", function(self)
                if GameTooltip then GameTooltip:Hide() end
                self:_msufApplyState(GetScopeKey() == bk)
            end)
            btn:_msufApplyState(k == "shared")
            scopeBtns[bk] = btn
            prevBtn = btn
        end
    end

    -- Override checkbox (row 2, left)
    local overrideCheck = CreateFrame("CheckButton", "MSUF_PortraitOverrideCheck", scopeBar, "UICheckButtonTemplate")
    overrideCheck:SetPoint("TOPLEFT", scopeBar, "TOPLEFT", 6, -30)
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

    -- Reset button (row 2, right)
    local resetBtn = CreateFrame("Button", "MSUF_PortraitResetBtn", scopeBar, "UIPanelButtonTemplate")
    resetBtn:SetSize(72, 18)
    resetBtn:SetPoint("TOPRIGHT", scopeBar, "TOPRIGHT", -8, -32)
    resetBtn:SetText(TR("Reset")); resetBtn:SetNormalFontObject("GameFontNormalSmall")
    resetBtn:SetScript("OnClick", function()
        EnsureDB()
        for _, k in ipairs(ALL_UNITS) do
            local u = MSUF_DB[k]; if u then u.portraitDecoOverride = false end
        end
        Apply(); LiveApply(); SyncScopeUI()
    end)

    -- Override summary line (bottom of scopeBar)
    local overrideInfo = scopeBar:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    overrideInfo:SetPoint("BOTTOMLEFT", scopeBar, "BOTTOMLEFT", 10, 6)
    overrideInfo:SetPoint("BOTTOMRIGHT", scopeBar, "BOTTOMRIGHT", -10, 6)
    overrideInfo:SetJustifyH("LEFT"); overrideInfo:SetWordWrap(false)

    -- ─── Content (scrollable area anchor) ───
    local content = CreateFrame("Frame", nil, panel)
    content:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -108)
    content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

    local headerAnchor = CreateFrame("Frame", nil, content)
    headerAnchor:SetSize(SEC_W, 1)
    headerAnchor:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_X, 0)

    -- =================================================================
    -- Section 1: Portrait Type (default open)
    -- =================================================================
    local COL_R = 200
    local DD_W_WIDE = 260
    local SL_W = 220

    local secType, typeBody = MakeCollapsibleSection(content, headerAnchor, SEC_W, 110, TR("Portrait Type"), true)

    MakeLabel(typeBody, "Type", PAD_X, -12)
    local renderDrop
    if UI.Dropdown then
        renderDrop = UI.Dropdown({
            name = "MSUF_PortraitRenderDD", parent = typeBody,
            anchor = typeBody, anchorPoint = "TOPLEFT", x = COL_R, y = -6, width = DD_W_WIDE,
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

    -- Class style sub-row (only visible when render == CLASS)
    local classLabel = MakeLabel(typeBody, "Class style", PAD_X, -46)
    local classDrop
    local PM = ns.PortraitMedia
    local function ClassItems()
        local t = {}
        local opts = (PM and PM.GetPackOptions and PM.GetPackOptions()) or {{ value = "BLIZZARD", text = "Blizzard Class Icon" }}
        for _, o in ipairs(opts) do t[#t + 1] = { key = o.value, label = o.text } end
        return t
    end
    if UI.Dropdown then
        classDrop = UI.Dropdown({
            name = "MSUF_PortraitClassStyleDD2", parent = typeBody,
            anchor = typeBody, anchorPoint = "TOPLEFT", x = COL_R, y = -40, width = DD_W_WIDE,
            items = ClassItems,
            get = function() return ScopeGet("portraitClassStyle", "BLIZZARD") end,
            set = function(v) ScopeSet("portraitClassStyle", v); LiveApply(); SyncScopeUI() end,
        })
    end

    -- =================================================================
    -- Section 2: Shape & Size (default open)
    -- =================================================================
    local TWO_COL_X = 430
    local HALF_SL_W = 220
    local secShape, shapeBody = MakeCollapsibleSection(content, secType, SEC_W, 214, TR("Shape & Size"), true)

    local shapeDrop
    if UI.Dropdown then
        shapeDrop = UI.Dropdown({
            name = "MSUF_PortraitShapeDD", parent = shapeBody,
            anchor = shapeBody, anchorPoint = "TOPLEFT", x = PAD_X, y = -6, width = 240,
            items = SHAPE_ITEMS,
            get = function() return ScopeGet("portraitShape", "SQUARE") end,
            set = function(v) ScopeSet("portraitShape", v); LiveApply() end,
        })
    end

    local sizeCheck = MakeCheck(shapeBody, "MSUF_PortraitSizeCheck", "Custom size", TWO_COL_X, -12,
        "Override auto size (frame height minus 4px)")
    local sizeSlider = MakeSliderWithEdit(shapeBody, "MSUF_PortraitSizeSlider", "Size (px)", TWO_COL_X, -56, 16, 80, 1, HALF_SL_W)

    local function NudgeCheckText(cb, dx, dy)
        local fs = cb and (cb.text or cb.Text or (_G[cb:GetName() .. "Text"]))
        if fs then
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", cb, "RIGHT", dx or 2, dy or 1)
        end
    end
    NudgeCheckText(sizeCheck, 4, 1)

    sizeCheck:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        if not on then ScopeSet("portraitSizeOverride", 0)
        else ScopeSet("portraitSizeOverride", floor(sizeSlider:GetValue() + 0.5))
        end
        sizeSlider:SetAllEnabled(on)
        if self._msufToggleUpdate then self._msufToggleUpdate() end
        LiveApply()
    end)
    sizeSlider:SetScript("OnValueChanged", function(self, val)
        val = floor(val + 0.5)
        if self.editBox then self.editBox:SetText(tostring(val)) end
        if sizeCheck:GetChecked() then ScopeSet("portraitSizeOverride", val); LiveApply() end
    end)

    local oxSlider = MakeSliderWithEdit(shapeBody, "MSUF_PortraitOXSlider", "Offset X", PAD_X, -116, -500, 500, 1, HALF_SL_W)
    local oySlider = MakeSliderWithEdit(shapeBody, "MSUF_PortraitOYSlider", "Offset Y", TWO_COL_X, -116, -500, 500, 1, HALF_SL_W)

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

    local fillCheck = MakeCheck(shapeBody, "MSUF_PortraitFillBorderCheck",
        "Stretch portrait into border", PAD_X, -168,
        "Portrait fills the full border area instead of sitting inside it. Best with Circle/Diamond borders.")
    NudgeCheckText(fillCheck, 4, 1)

    fillCheck:SetScript("OnClick", function(self)
        ScopeSet("portraitFillBorder", self:GetChecked() and true or false)
        if self._msufToggleUpdate then self._msufToggleUpdate() end
        LiveApply()
    end)

    -- =================================================================
    -- Section 3: Border (collapsed)
    -- =================================================================
    local secBorder, borderBody = MakeCollapsibleSection(content, secShape, SEC_W, 136, TR("Border"), false)

    MakeLabel(borderBody, "Style", PAD_X, -14)
    local borderDrop
    if UI.Dropdown then
        borderDrop = UI.Dropdown({
            name = "MSUF_PortraitBorderDD", parent = borderBody,
            anchor = borderBody, anchorPoint = "TOPLEFT", x = COL_R, y = -8, width = DD_W_WIDE,
            items = BORDER_ITEMS,
            get = function() return ScopeGet("portraitBorderStyle", "NONE") end,
            set = function(v) ScopeSet("portraitBorderStyle", v); LiveApply(); SyncScopeUI() end,
        })
    end

    MakeLabel(borderBody, "Thickness", PAD_X, -62)
    local thickSlider = MakeSliderWithEdit(borderBody, "MSUF_PortraitThickSlider", "", COL_R, -58, 1, 6, 1, HALF_SL_W)
    thickSlider:SetScript("OnValueChanged", function(self, val)
        val = floor(val + 0.5)
        if self.editBox then self.editBox:SetText(tostring(val)) end
        ScopeSet("portraitBorderThickness", val); LiveApply()
    end)

    local borderColorHint = MakeLabel(borderBody, "Color: Colors panel", 500, -62)
    borderColorHint:SetTextColor(0.5, 0.5, 0.5)

    -- =================================================================
    -- Section 4: Background (collapsed)
    -- =================================================================
    local secBg, bgBody = MakeCollapsibleSection(content, secBorder, SEC_W, 112, TR("Background"), false)

    local bgCheck = MakeCheck(bgBody, "MSUF_PortraitBgCheck", "Show background", PAD_X, -12)
    local bgOpacityLabel = MakeLabel(bgBody, "Opacity", PAD_X, -48)
    local bgOpSlider = MakeSliderWithEdit(bgBody, "MSUF_PortraitBgOpSlider", "", COL_R, -44, 0, 100, 5, SL_W)
    local bgColorHint = MakeLabel(bgBody, "Color: Colors panel", 500, -48)
    bgColorHint:SetTextColor(0.5, 0.5, 0.5)

    local function SyncBackgroundControls(bgEna)
        bgOpSlider:Show()
        bgOpSlider:SetAllEnabled(bgEna)

        if bgOpacityLabel and bgOpacityLabel.SetAlpha then
            bgOpacityLabel:SetAlpha(bgEna and 1 or 0.45)
        end
        if bgColorHint and bgColorHint.SetAlpha then
            bgColorHint:SetAlpha(bgEna and 1 or 0.45)
        end
        if bgOpSlider.editBox and bgOpSlider.editBox.SetTextColor then
            if bgEna then
                bgOpSlider.editBox:SetTextColor(1, 1, 1, 1)
            else
                bgOpSlider.editBox:SetTextColor(0.65, 0.65, 0.65, 1)
            end
        end
    end

    bgCheck:SetScript("OnClick", function(self)
        local bgEna = self:GetChecked() and true or false
        ScopeSet("portraitBgEnabled", bgEna)
        if self._msufToggleUpdate then self._msufToggleUpdate() end
        SyncBackgroundControls(bgEna)
        LiveApply(); SyncScopeUI()
    end)

    bgOpSlider:SetScript("OnValueChanged", function(self, val)
        val = floor(val + 0.5)
        if self.editBox then self.editBox:SetText(val .. "%") end
        ScopeSet("portraitBgColorA", val / 100); LiveApply()
    end)

    -- =================================================================
    -- Post-build: collapse non-default sections, wire toggle callback
    -- =================================================================
    local allSections = { secType, secShape, secBorder, secBg }

    local function RecalcHeight()
        local h = 8
        for i = 1, #allSections do
            h = h + (allSections[i]:GetHeight() or 28) + 6
        end
        if h < 200 then h = 200 end
        content:SetHeight(h)
    end

    for i = 1, #allSections do
        allSections[i]._msufOnToggle = RecalcHeight
    end

    -- =================================================================
    -- Scope UI Sync
    -- =================================================================
    SyncScopeUI = function()
        EnsureDB()
        local uk = GetUnitKey()
        local isUnit = (uk ~= nil)

        -- Scope buttons
        RefreshScopeButtons()

        -- Override checkbox + reset
        if isUnit then
            overrideCheck:Show(); overrideCheck:Enable(); overrideCheck:SetAlpha(1)
            overrideCheck:SetChecked(IsOverride(uk))
        else
            overrideCheck:Hide()
        end

        -- Override summary
        local active = {}
        for _, k in ipairs(ALL_UNITS) do
            if U(k).portraitDecoOverride then active[#active + 1] = (labelForKey[k] or k) end
        end
        if #active == 0 then
            overrideInfo:SetText("|cff9aa0a6No unit overrides active.|r")
            overrideInfo:SetFontObject(GameFontDisableSmall)
            resetBtn:Disable(); resetBtn:SetAlpha(0.45)
        else
            local txt = "|cffffffffOverrides:|r " .. table.concat(active, ", ")
            overrideInfo:SetText(txt)
            overrideInfo:SetFontObject(GameFontHighlightSmall)
            resetBtn:Enable(); resetBtn:SetAlpha(1)
        end
        overrideInfo:SetShown(not isUnit)

        if renderDrop and renderDrop.Refresh then renderDrop:Refresh() end
        if classDrop and classDrop.Refresh then classDrop:Refresh() end
        if shapeDrop and shapeDrop.Refresh then shapeDrop:Refresh() end
        if borderDrop and borderDrop.Refresh then borderDrop:Refresh() end

        -- Render type → show/hide class style row + adjust section height
        local render
        if isUnit then
            render = U(uk).portraitRender or "2D"
        else
            render = G()._portraitSharedRender or "2D"
        end
        local isClass = (render == "CLASS")
        classLabel:SetShown(isClass)
        if classDrop then classDrop:SetShown(isClass) end
        secType._msufExpandedH = isClass and 110 or 68
        if not secType._msufCollapsed then secType:SetHeight(secType._msufExpandedH) end

        -- Rondo packs have built-in borders → hide Border section
        local isRondo = false
        if isClass then
            local style = ScopeGet("portraitClassStyle", "BLIZZARD")
            isRondo = (style == "RONDO_COLOR" or style == "RONDO_WOW")
        end
        secBorder:SetShown(not isRondo)

        -- Rondo has built-in shape → dim shape dropdown
        if shapeDrop then
            if shapeDrop.SetEnabled then
                shapeDrop:SetEnabled(not isRondo)
            else
                shapeDrop:SetAlpha(isRondo and 0.35 or 1)
            end
        end

        -- Fill Border toggle: only for 2D/3D
        fillCheck:SetShown(render ~= "CLASS")

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
        bgOpSlider:SetValue((ScopeGet("portraitBgColorA", 0.85) or 0.85) * 100)
        SyncBackgroundControls(bgEna)

        RecalcHeight()
    end

    -- Collapse non-default sections AFTER all widgets are built
    for i = 1, #allSections do
        local sec = allSections[i]
        if not sec._msufDefaultOpen then
            sec._msufCollapsed = true
            sec._msufApplyState()
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
