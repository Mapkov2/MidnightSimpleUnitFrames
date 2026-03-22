-- ---------------------------------------------------------------------------
-- MSUF_Options_Bars.lua  (Phase 4: A2-style scope bar + collapsible boxes)
--
-- Bar appearance: absorb display, textures, gradients, outlines,
-- highlight borders (aggro/dispel/purge), priority reorder,
-- power bar settings, HP/Power text modes, separators, spacers,
-- bar animation, per-unit scope system.
-- ---------------------------------------------------------------------------
local addonName, ns = ...
local TR = ns.TR
local UI = ns.UI
local EnsureDB = ns.EnsureDB
local floor = math.floor
local CreateFrame = CreateFrame

function ns.MSUF_Options_Bars_Build(panel, barGroup, barGroupHost, ctx)
    if not panel or not barGroup then return end
    if barGroup._msufBuilt then return end
    barGroup._msufBuilt = true

    local function G() EnsureDB(); return MSUF_DB.general end
    local function B() EnsureDB(); MSUF_DB.bars = MSUF_DB.bars or {}; return MSUF_DB.bars end
    local function Apply() if type(_G.ApplyAllSettings) == "function" then _G.ApplyAllSettings() end end
    local function LayoutKey(k, reason, urgent)
        if type(_G.MSUF_Options_RequestLayoutForKey) == "function" then _G.MSUF_Options_RequestLayoutForKey(k, reason, urgent) end
    end
    local function ForceTextLayout(k) if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then _G.MSUF_ForceTextLayoutForUnitKey(k) end end
    local function RefreshFrames()
        if ns.MSUF_RefreshAllFrames then ns.MSUF_RefreshAllFrames(); return end
        if _G.MSUF_UnitFrames and _G.UpdateSimpleUnitFrame then
            for _, f in pairs(_G.MSUF_UnitFrames) do if f and f.unit then _G.UpdateSimpleUnitFrame(f) end end
        end
    end

    local TEX_W8 = "Interface\\Buttons\\WHITE8x8"
    local BAR_DD_W = 260
    local ALL_UNITS = { "player", "target", "focus", "targettarget", "pet", "boss" }

    local CreateLabeledCheckButton = ctx and ctx.CreateLabeledCheckButton
    local CreateLabeledSlider = (ctx and ctx.CreateLabeledSlider) or (ns and ns.MSUF_CreateLabeledSlider) or _G.CreateLabeledSlider
    local MSUF_SetLabeledSliderValue = (ctx and ctx.MSUF_SetLabeledSliderValue) or _G.MSUF_SetLabeledSliderValue
    local MSUF_SetLabeledSliderEnabled = (ctx and ctx.MSUF_SetLabeledSliderEnabled) or _G.MSUF_SetLabeledSliderEnabled
    local MSUF_SetCheckboxEnabled = _G.MSUF_SetCheckboxEnabled or function() end
    local MSUF_SetDropDownEnabled = _G.MSUF_SetDropDownEnabled or function() end
    local MSUF_CreateGradientDirectionPad = (ctx and ctx.MSUF_CreateGradientDirectionPad) or _G.MSUF_CreateGradientDirectionPad
    local MSUF_KillMenuPreviewBar = _G.MSUF_KillMenuPreviewBar or function() end
    local MSUF_BarsMenu_QueueScrollUpdate = (ctx and ctx.MSUF_BarsMenu_QueueScrollUpdate) or function() end
    local MSUF_UpdatePowerBarHeightFromEdit = (ctx and ctx.MSUF_UpdatePowerBarHeightFromEdit) or _G.MSUF_UpdatePowerBarHeightFromEdit or function() end
    local MSUF_UpdatePowerBarBorderSizeFromEdit = (ctx and ctx.MSUF_UpdatePowerBarBorderSizeFromEdit) or _G.MSUF_UpdatePowerBarBorderSizeFromEdit or function() end
    if type(CreateLabeledCheckButton) ~= "function" then return end

    local _Scope_GetUnitKey, _Scope_GetUnitDB, _Scope_EnableOverride, _Scope_SyncUI

    -- =====================================================================
    -- Scope-aware get/set helpers
    -- =====================================================================
    local function ScopeGet(generalKey, defaultVal)
        EnsureDB()
        local uk = _Scope_GetUnitKey and _Scope_GetUnitKey()
        if uk then
            local u = MSUF_DB[uk]
            if u and u.hpPowerTextOverride == true and u[generalKey] ~= nil then return u[generalKey] end
        end
        local v = G()[generalKey]
        return v ~= nil and v or defaultVal
    end

    local function ScopeSet(generalKey, val, applyFn)
        EnsureDB()
        local uk = _Scope_GetUnitKey and _Scope_GetUnitKey()
        if uk then
            local u = type(_Scope_GetUnitDB) == "function" and _Scope_GetUnitDB(uk)
            if u then
                if u.hpPowerTextOverride ~= true and type(_Scope_EnableOverride) == "function" then _Scope_EnableOverride(uk) end
                u[generalKey] = val
            end
        else
            G()[generalKey] = val
        end
        if type(applyFn) == "function" then pcall(applyFn, val) end
        if type(_Scope_SyncUI) == "function" then _Scope_SyncUI() end
    end

    -- =====================================================================
    -- Box helpers (A2 style)
    -- =====================================================================
    local BOX_W = 650
    local function MakeBox(parent, h)
        local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        f:SetSize(BOX_W, h)
        f:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        f:SetBackdropColor(0, 0, 0, 0.35)
        f:SetBackdropBorderColor(1, 1, 1, 0.08)
        return f
    end

    local function MakeCollapsibleBox(parent, anchorTo, h, titleText, defaultOpen)
        local box = MakeBox(parent, defaultOpen and h or 28)
        box:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -6)
        box._msufExpandedH = h
        box._msufCollapsed = not defaultOpen
        local hdr = CreateFrame("Button", nil, box)
        hdr:SetHeight(24); hdr:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0); hdr:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
        local chevron = hdr:CreateTexture(nil, "OVERLAY")
        chevron:SetSize(12, 12); chevron:SetPoint("LEFT", hdr, "LEFT", 12, 0)
        chevron:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        MSUF_ApplyCollapseVisual(chevron, nil, defaultOpen)
        local title = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("LEFT", chevron, "RIGHT", 6, 0); title:SetText(TR(titleText))
        local hint = hdr:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("RIGHT", hdr, "RIGHT", -12, 0)
        hint:SetText(defaultOpen and "" or TR("click to expand")); hint:SetTextColor(0.45, 0.52, 0.65)
        local bodyHost = CreateFrame("Frame", nil, box)
        bodyHost:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -28); bodyHost:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
        bodyHost:SetShown(defaultOpen)
        if bodyHost.SetFrameLevel and box.GetFrameLevel then
            bodyHost:SetFrameLevel((box:GetFrameLevel() or 0) + 5)
        end
        box._msufBody = bodyHost
        box._msufTitle = title
        do
            local hl = hdr:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.03)
        end
        hdr:SetScript("OnClick", function()
            box._msufCollapsed = not box._msufCollapsed
            bodyHost:SetShown(not box._msufCollapsed)
            if box._msufCollapsed then
                box:SetHeight(28); MSUF_ApplyCollapseVisual(chevron, hint, false)
            else
                box:SetHeight(box._msufExpandedH); MSUF_ApplyCollapseVisual(chevron, hint, true)
            end
            MSUF_BarsMenu_QueueScrollUpdate()
        end)
        return box, bodyHost
    end

    local function MakeSectionLabel(parent, anchor, text, oY)
        local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, oY or 0)
        fs:SetText(TR(text)); fs:SetTextColor(0.7, 0.75, 0.82, 0.6)
        return fs
    end

    -- Forward-declare scope functions
    local _MSUF_HPText_GetScopeKey, _MSUF_HPText_GetUnitKey, _MSUF_HPText_GetUnitDB
    local _MSUF_HPText_NormalizeScopeKey, _MSUF_HPText_EnableOverride
    local _MSUF_SyncHpPowerTextScopeUI
    local hpPowerOverrideCheck

    -- =====================================================================
    -- SCOPE BAR (A2-style button strip)
    -- =====================================================================
    local SCOPE_KEYS = { "shared", "player", "target", "targettarget", "focus", "pet", "boss" }
    local SCOPE_LABELS = {
        shared = "Shared", player = "Player", target = "Target",
        targettarget = "ToT", focus = "Focus", pet = "Pet", boss = "Boss",
    }

    local scopeBar = CreateFrame("Frame", nil, barGroup, "BackdropTemplate")
    scopeBar:SetHeight(72); scopeBar:SetWidth(BOX_W)
    scopeBar:SetPoint("TOPLEFT", barGroup, "TOPLEFT", 0, -120)
    scopeBar:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    scopeBar:SetBackdropColor(0.04, 0.08, 0.18, 0.95)
    scopeBar:SetBackdropBorderColor(0.12, 0.25, 0.50, 0.6)

    local scopeEditLbl = scopeBar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    scopeEditLbl:SetPoint("TOPLEFT", scopeBar, "TOPLEFT", 10, -10); scopeEditLbl:SetText(TR("Editing:"))

    local scopeBtns = {}
    local function GetScopeUnitHasOverride(key)
        if key == "shared" then return false end
        EnsureDB(); local u = MSUF_DB[key]
        return (type(u) == "table" and u.hpPowerTextOverride == true)
    end

    local function RefreshScopeButtons()
        local activeKey = G().hpPowerTextSelectedKey or "shared"
        for k, btn in pairs(scopeBtns) do
            if btn and btn._msufApplyState then btn:_msufApplyState(k == activeKey) end
        end
    end

    local function ApplyScopeKey(key)
        EnsureDB()
        G().hpPowerTextSelectedKey = key
        if key ~= "shared" then G().hpSpacerSelectedUnitKey = key end
        RefreshScopeButtons()
        if type(_MSUF_SyncHpPowerTextScopeUI) == "function" then _MSUF_SyncHpPowerTextScopeUI() end
    end

    do
        local prevBtn
        for _, k in ipairs(SCOPE_KEYS) do
            local bk = k
            local btn = CreateFrame("Button", nil, scopeBar, "BackdropTemplate")
            btn:SetSize(bk == "shared" and 56 or 48, 18)
            if not prevBtn then
                btn:SetPoint("LEFT", scopeEditLbl, "RIGHT", 8, 0)
            else
                btn:SetPoint("LEFT", prevBtn, "RIGHT", 2, 0)
            end
            local bg = btn:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.08, 0.12, 0.22, 0.80)
            btn._msufBg = bg
            local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
            border:SetAllPoints(); border:SetBackdrop({ edgeFile = TEX_W8, edgeSize = 1 })
            border:SetBackdropBorderColor(0.15, 0.30, 0.60, 0.50)
            btn._msufBorder = border
            local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("CENTER", 0, 0); fs:SetText(SCOPE_LABELS[bk] or bk)
            btn._msufLabel = fs

            btn._msufApplyState = function(self, active)
                local hasOvr = GetScopeUnitHasOverride(bk)
                if active then
                    bg:SetColorTexture(0.12, 0.24, 0.50, 0.95)
                    if hasOvr then border:SetBackdropBorderColor(0.96, 0.80, 0.34, 0.98)
                    else border:SetBackdropBorderColor(0.30, 0.55, 1.00, 0.80) end
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

            btn:SetScript("OnClick", function() ApplyScopeKey(bk) end)
            btn:SetScript("OnEnter", function(self)
                if self._msufBg then self._msufBg:SetColorTexture(0.10, 0.18, 0.36, 0.90) end
                if GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(SCOPE_LABELS[bk] or bk, 1, 1, 1)
                    if bk == "shared" then
                        GameTooltip:AddLine(TR("Shared baseline used by units without overrides."), 0.72, 0.78, 0.88, true)
                    else
                        local tip = GetScopeUnitHasOverride(bk) and TR("Override active: this unit uses its own HP/Power text settings.") or TR("Uses Shared settings.")
                        GameTooltip:AddLine(tip, 0.72, 0.78, 0.88, true)
                    end
                    GameTooltip:Show()
                end
            end)
            btn:SetScript("OnLeave", function(self)
                if GameTooltip then GameTooltip:Hide() end
                local isActive = (G().hpPowerTextSelectedKey or "shared") == bk
                if self._msufApplyState then self:_msufApplyState(isActive) end
            end)
            btn:_msufApplyState(k == "shared")
            scopeBtns[bk] = btn
            prevBtn = btn
        end
    end

    -- Override checkbox (row 2 of scope bar)
    hpPowerOverrideCheck = CreateFrame("CheckButton", "MSUF_HPTextOverrideCheck", scopeBar, "UICheckButtonTemplate")
    hpPowerOverrideCheck:SetPoint("TOPLEFT", scopeBar, "TOPLEFT", 10, -36)
    hpPowerOverrideCheck.text = _G["MSUF_HPTextOverrideCheckText"]
    if hpPowerOverrideCheck.text then hpPowerOverrideCheck.text:SetText(TR("Override shared settings")) end
    UI.StyleToggleText(hpPowerOverrideCheck); UI.StyleCheckmark(hpPowerOverrideCheck)
    UI.AttachTooltip(hpPowerOverrideCheck, "Per-unit override", "When unchecked, this unit inherits Shared settings.")

    -- Override summary (shown when Shared selected)
    local scopeOverrideInfo = scopeBar:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    scopeOverrideInfo:SetPoint("BOTTOMLEFT", scopeBar, "BOTTOMLEFT", 10, 8)
    scopeOverrideInfo:SetJustifyH("LEFT"); scopeOverrideInfo:SetWordWrap(false)

    -- Reset overrides button
    local scopeResetBtn = CreateFrame("Button", "MSUF_HPTextResetOverridesBtn", scopeBar, "UIPanelButtonTemplate")
    scopeResetBtn:SetSize(72, 18); scopeResetBtn:SetPoint("TOPRIGHT", scopeBar, "TOPRIGHT", -8, -36)
    scopeResetBtn:SetText(TR("Reset")); scopeResetBtn:SetNormalFontObject("GameFontNormalSmall")

    -- =====================================================================
    -- Scope helper functions
    -- =====================================================================
    _MSUF_HPText_NormalizeScopeKey = function(v) if v == nil or v == "" or v == "shared" then return "shared" end; return v end
    _MSUF_HPText_GetScopeKey = function() return _MSUF_HPText_NormalizeScopeKey(G().hpPowerTextSelectedKey) end
    _MSUF_HPText_GetUnitKey = function()
        local k = _MSUF_HPText_GetScopeKey(); if k == "shared" then return nil end; return k
    end
    _MSUF_HPText_GetUnitDB = function(unitKey) EnsureDB(); MSUF_DB[unitKey] = MSUF_DB[unitKey] or {}; return MSUF_DB[unitKey] end
    _MSUF_HPText_EnableOverride = function(unitKey)
        local u = _MSUF_HPText_GetUnitDB(unitKey); if not u then return end
        u.hpPowerTextOverride = true
        local g = G()
        if u.hpTextMode == nil then u.hpTextMode = g.hpTextMode end
        if u.powerTextMode == nil then u.powerTextMode = g.powerTextMode end
        if u.hpTextSeparator == nil then u.hpTextSeparator = g.hpTextSeparator end
        if u.powerTextSeparator == nil then u.powerTextSeparator = g.powerTextSeparator end
        if u.absorbTextMode == nil then u.absorbTextMode = g.absorbTextMode end
        if u.absorbAnchorMode == nil then u.absorbAnchorMode = g.absorbAnchorMode end
        if u.hpTextSpacerEnabled == nil then u.hpTextSpacerEnabled = g.hpTextSpacerEnabled end
        if u.hpTextSpacerX == nil then u.hpTextSpacerX = g.hpTextSpacerX end
        if u.powerTextSpacerEnabled == nil then u.powerTextSpacerEnabled = g.powerTextSpacerEnabled end
        if u.powerTextSpacerX == nil then u.powerTextSpacerX = g.powerTextSpacerX end
        if u.hpTextAnchor == nil then u.hpTextAnchor = g.hpTextAnchor end
        if u.powerTextAnchor == nil then u.powerTextAnchor = g.powerTextAnchor end
    end

    _Scope_GetUnitKey = _MSUF_HPText_GetUnitKey
    _Scope_GetUnitDB = _MSUF_HPText_GetUnitDB
    _Scope_EnableOverride = _MSUF_HPText_EnableOverride

    -- Override checkbox handler
    hpPowerOverrideCheck:SetScript("OnClick", function(self)
        local uk = _MSUF_HPText_GetUnitKey(); if not uk then self:SetChecked(false); return end
        local u = _MSUF_HPText_GetUnitDB(uk); if not u then self:SetChecked(false); return end
        if self:GetChecked() then _MSUF_HPText_EnableOverride(uk) else u.hpPowerTextOverride = false end
        Apply(); ForceTextLayout(uk)
        if _G.MSUF_UnitFrames then
            if type(_G.MSUF_InvalidateAbsorbCache) == "function" then _G.MSUF_InvalidateAbsorbCache() end
            for _, f in pairs(_G.MSUF_UnitFrames) do
                if f and f.unit then
                    f._msufAbsorbAnchorModeStamp = nil; f._msufAbsorbFollowActive = nil
                    if type(_G.MSUF_ApplyAbsorbAnchorMode) == "function" then _G.MSUF_ApplyAbsorbAnchorMode(f) end
                    if _G.UpdateSimpleUnitFrame then _G.UpdateSimpleUnitFrame(f) end
                end
            end
        end
        _MSUF_SyncHpPowerTextScopeUI()
    end)

    -- Reset overrides handler
    scopeResetBtn:SetScript("OnClick", function()
        EnsureDB(); local any = false
        for _, uk in ipairs(ALL_UNITS) do local u = MSUF_DB[uk]; if u and u.hpPowerTextOverride then u.hpPowerTextOverride = false; any = true end end
        if any then Apply(); for _, uk in ipairs(ALL_UNITS) do ForceTextLayout(uk) end; RefreshFrames() end
        _MSUF_SyncHpPowerTextScopeUI()
    end)
    scopeResetBtn:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_NONE"); GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPLEFT", self, "TOPRIGHT", 12, 0)
        GameTooltip:SetText(TR("Reset overrides"), 1, 1, 1)
        GameTooltip:AddLine(TR("Turns off per-unit overrides for all units and reverts to Shared."), 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    scopeResetBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    -- =====================================================================
    -- BOX 1: Textures & Gradient (default open)
    -- =====================================================================
    local box1, box1Body = MakeCollapsibleBox(barGroup, scopeBar, 200, "Textures & Gradient", true)

    -- Left col: Bar textures
    local texColLabel = MakeSectionLabel(box1Body, box1Body, "Bar textures (SharedMedia)", -6)
    texColLabel:SetPoint("TOPLEFT", box1Body, "TOPLEFT", 14, -6)

    local function ApplyBarTex()
        if type(_G.MSUF_UpdateAllBarTextures_Immediate) == "function" then _G.MSUF_UpdateAllBarTextures_Immediate()
        elseif type(_G.MSUF_UpdateAllBarTextures) == "function" then _G.MSUF_UpdateAllBarTextures()
        else Apply() end
    end
    _G.MSUF_TryApplyBarTextureLive = ApplyBarTex

    local barTextureDrop = UI.Dropdown({
        name = "MSUF_BarTextureDropdown", parent = box1Body,
        anchor = texColLabel, x = -14, y = -4, width = 280, maxVisible = 12,
        iconWidth = 80, iconHeight = 12,
        items = function() return UI.StatusBarTextureItems(nil) end,
        get = function() return G().barTexture or "Blizzard" end,
        set = function(v) G().barTexture = v; ApplyBarTex() end,
    })

    local barBgTexLabel = box1Body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    barBgTexLabel:SetPoint("TOPLEFT", barTextureDrop, "BOTTOMLEFT", 14, -6)
    barBgTexLabel:SetText(TR("Background texture")); barBgTexLabel:SetTextColor(0.75, 0.75, 0.75)

    local barBgTextureDrop = UI.Dropdown({
        name = "MSUF_BarBackgroundTextureDropdown", parent = box1Body,
        anchor = barBgTexLabel, x = -14, y = -4, width = 280, maxVisible = 12,
        iconWidth = 80, iconHeight = 12,
        items = function() return UI.StatusBarTextureItems(TR("Use foreground texture")) end,
        get = function() return G().barBackgroundTexture or "" end,
        set = function(v) G().barBackgroundTexture = v; ApplyBarTex() end,
    })

    -- Right col: Gradient
    local gradColLabel = box1Body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    gradColLabel:SetPoint("TOPLEFT", box1Body, "TOPLEFT", 340, -6)
    gradColLabel:SetText(TR("Gradient")); gradColLabel:SetTextColor(0.7, 0.75, 0.82, 0.6)

    local gradientCheck = CreateLabeledCheckButton("MSUF_GradientEnableCheck", "HP bar gradient", box1Body, 16, -260)
    gradientCheck:ClearAllPoints(); gradientCheck:SetPoint("TOPLEFT", gradColLabel, "BOTTOMLEFT", 0, -8)

    local powerGradientCheck = CreateLabeledCheckButton("MSUF_PowerGradientEnableCheck", "Power bar gradient", box1Body, 16, -282)
    powerGradientCheck:ClearAllPoints(); powerGradientCheck:SetPoint("TOPLEFT", gradientCheck, "BOTTOMLEFT", 0, -8)

    local gradientStrengthSlider = CreateLabeledSlider("MSUF_GradientStrengthSlider", "Gradient strength", box1Body, 0, 1, 0.05, 16, -304)
    gradientStrengthSlider:ClearAllPoints(); gradientStrengthSlider:SetPoint("TOPLEFT", powerGradientCheck, "BOTTOMLEFT", 0, -18)
    if gradientStrengthSlider.SetWidth then gradientStrengthSlider:SetWidth(200) end

    local gradientDirPad = MSUF_CreateGradientDirectionPad and MSUF_CreateGradientDirectionPad(box1Body) or nil
    if gradientDirPad then
        if gradientDirPad.SetParent then gradientDirPad:SetParent(box1Body) end
        gradientDirPad:ClearAllPoints(); gradientDirPad:SetPoint("TOPLEFT", gradientCheck, "TOPLEFT", 218, -3); gradientDirPad:Show()
    end

    -- SharedMedia compat exports
    _G.MSUF_InitStatusbarTextureDropdown = _G.MSUF_InitStatusbarTextureDropdown or function() end
    _G.MSUF_SyncStatusbarTextureDropdown = _G.MSUF_SyncStatusbarTextureDropdown or function() end
    if not _G.MSUF_ResolveStatusbarTextureKey then
        _G.MSUF_ResolveStatusbarTextureKey = function(key)
            if type(key) ~= "string" or key == "" then return nil end
            local LSM = (ns and ns.LSM) or _G.MSUF_LSM
            if LSM and type(LSM.Fetch) == "function" then
                local ok, tex = pcall(LSM.Fetch, LSM, "statusbar", key, true)
                if ok and type(tex) == "string" and tex ~= "" then return tex end
            end
            return nil
        end
    end

    -- =====================================================================
    -- BOX 2: Absorb Display (default open)
    -- =====================================================================
    local box2, box2Body = MakeCollapsibleBox(barGroup, box1, 210, "Absorb Display", true)

    local function ApplyAbsorb(mode)
        if type(_G.MSUF_UpdateAbsorbTextMode) == "function" then _G.MSUF_UpdateAbsorbTextMode(mode) end
        RefreshFrames()
    end
    local function ApplyAbsorbAnchor()
        if type(_G.MSUF_InvalidateAbsorbCache) == "function" then _G.MSUF_InvalidateAbsorbCache() end
        if _G.MSUF_UnitFrames and type(_G.MSUF_ApplyAbsorbAnchorMode) == "function" then
            for _, f in pairs(_G.MSUF_UnitFrames) do
                if f and f.unit then
                    f._msufAbsorbAnchorModeStamp = nil; f._msufAbsorbFollowActive = nil
                    _G.MSUF_ApplyAbsorbAnchorMode(f)
                    if _G.UpdateSimpleUnitFrame then _G.UpdateSimpleUnitFrame(f) end
                end
            end
        end
    end
    local function ApplyAbsorbTex()
        if type(_G.MSUF_UpdateAbsorbBarTextures) == "function" then _G.MSUF_UpdateAbsorbBarTextures()
        elseif type(_G.MSUF_UpdateAllUnitFrames) == "function" then _G.MSUF_UpdateAllUnitFrames()
        else RefreshFrames() end
        if _G.MSUF_AbsorbTextureTestMode then RefreshFrames() end
    end

    -- Left col: mode + anchor + test
    local absorbModeLabel = box2Body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    absorbModeLabel:SetPoint("TOPLEFT", box2Body, "TOPLEFT", 14, -6)
    absorbModeLabel:SetText(TR("Display mode")); absorbModeLabel:SetTextColor(0.75, 0.75, 0.75)

    local absorbDisplayDrop = UI.Dropdown({
        name = "MSUF_AbsorbDisplayDrop", parent = box2Body,
        anchor = absorbModeLabel, x = -14, y = -4, width = 280,
        items = {
            { key = 1, label = "Absorb off" }, { key = 2, label = "Absorb bar" },
            { key = 3, label = "Absorb bar + text" }, { key = 4, label = "Absorb text only" },
        },
        get = function()
            local m = ScopeGet("absorbTextMode", nil)
            if m then return tonumber(m) end
            local g = G()
            local barOn = (g.enableAbsorbBar ~= false); local textOn = (g.showTotalAbsorbAmount == true)
            if not barOn and not textOn then return 1 end; if barOn and not textOn then return 2 end
            if barOn and textOn then return 3 end; return 4
        end,
        set = function(v) ScopeSet("absorbTextMode", v, ApplyAbsorb) end,
    })

    local absorbAnchorLabel = box2Body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    absorbAnchorLabel:SetPoint("TOPLEFT", absorbDisplayDrop, "BOTTOMLEFT", 14, -8)
    absorbAnchorLabel:SetText(TR("Absorb bar anchoring")); absorbAnchorLabel:SetTextColor(0.75, 0.75, 0.75)

    local absorbAnchorDrop = UI.Dropdown({
        name = "MSUF_AbsorbAnchorDrop", parent = box2Body,
        anchor = absorbAnchorLabel, x = -14, y = -4, width = 280,
        items = {
            { key = 1, label = "Anchor to left side" }, { key = 2, label = "Anchor to right side" },
            { key = 3, label = "Follow HP bar" }, { key = 4, label = "Follow HP bar (overflow)" },
            { key = 5, label = "Reverse from max" },
        },
        get = function() return tonumber(ScopeGet("absorbAnchorMode", 2)) or 2 end,
        set = function(v) ScopeSet("absorbAnchorMode", v, ApplyAbsorbAnchor) end,
    })

    local absorbTexTestCB = CreateLabeledCheckButton("MSUF_AbsorbTextureTestModeCheck", "Test absorb textures", box2Body, 16, -1)
    absorbTexTestCB:ClearAllPoints(); absorbTexTestCB:SetPoint("TOPLEFT", absorbAnchorDrop, "BOTTOMLEFT", 14, -8)
    absorbTexTestCB:SetScript("OnShow", function(self) self:SetChecked(_G.MSUF_AbsorbTextureTestMode and true or false) end)
    absorbTexTestCB:SetScript("OnClick", function(self)
        _G.MSUF_AbsorbTextureTestMode = self:GetChecked() and true or false; RefreshFrames()
    end)
    absorbTexTestCB:SetScript("OnHide", function(self)
        if barGroup:IsShown() then return end
        if _G.MSUF_AbsorbTextureTestMode then _G.MSUF_AbsorbTextureTestMode = false; self:SetChecked(false); RefreshFrames() end
    end)

    local selfHealPredCB = CreateLabeledCheckButton("MSUF_SelfHealPredictionCheck", "Heal prediction", box2Body, 16, -1)
    selfHealPredCB:ClearAllPoints(); selfHealPredCB:SetPoint("LEFT", absorbTexTestCB, "RIGHT", 140, 0)
    selfHealPredCB:SetScript("OnShow", function(self) EnsureDB(); self:SetChecked(G().showSelfHealPrediction and true or false) end)
    selfHealPredCB:SetScript("OnClick", function(self) G().showSelfHealPrediction = self:GetChecked() and true or false; RefreshFrames() end)

    -- Right col: absorb textures (aligned with left col)
    local absorbTextureLabel = box2Body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    absorbTextureLabel:SetPoint("TOPLEFT", box2Body, "TOPLEFT", 340, -6)
    absorbTextureLabel:SetText(TR("Absorb bar texture (SharedMedia)")); absorbTextureLabel:SetTextColor(0.75, 0.75, 0.75)

    local absorbBarTextureDrop = UI.Dropdown({
        name = "MSUF_AbsorbBarTextureDropdown", parent = box2Body,
        anchor = absorbTextureLabel, x = -14, y = -4, width = 280, maxVisible = 12,
        iconWidth = 80, iconHeight = 12,
        items = function() return UI.StatusBarTextureItems(TR("Use foreground texture")) end,
        get = function() return G().absorbBarTexture or "" end,
        set = function(v) G().absorbBarTexture = v; ApplyAbsorbTex(); Apply() end,
    })

    local healAbsorbLabel = box2Body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    healAbsorbLabel:SetPoint("TOPLEFT", absorbBarTextureDrop, "BOTTOMLEFT", 14, -8)
    healAbsorbLabel:SetText(TR("Heal-absorb texture")); healAbsorbLabel:SetTextColor(0.75, 0.75, 0.75)

    local healAbsorbTextureDrop = UI.Dropdown({
        name = "MSUF_HealAbsorbBarTextureDropdown", parent = box2Body,
        anchor = healAbsorbLabel, x = -14, y = -4, width = 280, maxVisible = 12,
        iconWidth = 80, iconHeight = 12,
        items = function() return UI.StatusBarTextureItems(TR("Use foreground texture")) end,
        get = function() return G().healAbsorbBarTexture or "" end,
        set = function(v) G().healAbsorbBarTexture = v; ApplyAbsorbTex(); Apply() end,
    })

    -- Absorb bar UI enable/disable based on display mode
    local MSUF_RefreshAbsorbBarUIEnabled
    MSUF_RefreshAbsorbBarUIEnabled = function()
        local mode = tonumber(ScopeGet("absorbTextMode", 2)) or 2
        local barEnabled = (mode == 2 or mode == 3)
        MSUF_SetDropDownEnabled(absorbAnchorDrop, absorbAnchorLabel, barEnabled)
        if absorbTextureLabel.SetTextColor then absorbTextureLabel:SetTextColor(barEnabled and 1 or 0.35, barEnabled and 1 or 0.35, barEnabled and 1 or 0.35) end
        if healAbsorbLabel and healAbsorbLabel.SetTextColor then healAbsorbLabel:SetTextColor(barEnabled and 0.75 or 0.35, barEnabled and 0.75 or 0.35, barEnabled and 0.75 or 0.35) end
        MSUF_SetDropDownEnabled(absorbBarTextureDrop, nil, barEnabled)
        MSUF_SetDropDownEnabled(healAbsorbTextureDrop, nil, barEnabled)
        MSUF_SetCheckboxEnabled(absorbTexTestCB, barEnabled)
        if not barEnabled and _G.MSUF_AbsorbTextureTestMode then
            _G.MSUF_AbsorbTextureTestMode = false; absorbTexTestCB:SetChecked(false); RefreshFrames()
        end
    end
    MSUF_RefreshAbsorbBarUIEnabled()

    -- =====================================================================
    -- BOX 3: Outline & Highlight Border (default open)
    -- =====================================================================
    local function _BumpBorderSerial()
        if type(_G.MSUF_UFCore_RefreshSettingsCache) == "function" then _G.MSUF_UFCore_RefreshSettingsCache("BAR_OPTION") end
    end

    local box3, box3Body = MakeCollapsibleBox(barGroup, box2, 350, "Outline & Highlight Border", true)

    -- Left col: thickness sliders
    local barOutlineThicknessSlider = CreateLabeledSlider("MSUF_BarOutlineThicknessSlider", "Outline thickness", box3Body, 0, 6, 1, 16, -350)
    barOutlineThicknessSlider:ClearAllPoints(); barOutlineThicknessSlider:SetPoint("TOPLEFT", box3Body, "TOPLEFT", 14, -10)
    barOutlineThicknessSlider:SetWidth(280)
    do local n = barOutlineThicknessSlider:GetName(); local t = _G[n .. "Text"]; if t then t:SetText(""); t:Hide() end end
    barOutlineThicknessSlider.onValueChanged = function(_, v)
        B().barOutlineThickness = v; _BumpBorderSerial()
        if type(_G.MSUF_ApplyBarOutlineThickness_All) == "function" then _G.MSUF_ApplyBarOutlineThickness_All() else Apply() end
    end

    local highlightBorderThicknessSlider = CreateLabeledSlider("MSUF_HighlightBorderThicknessSlider", "Highlight border thickness", box3Body, 1, 6, 1, 16, -420)
    highlightBorderThicknessSlider:ClearAllPoints(); highlightBorderThicknessSlider:SetPoint("TOPLEFT", barOutlineThicknessSlider, "BOTTOMLEFT", 0, -60)
    highlightBorderThicknessSlider:SetWidth(280)
    highlightBorderThicknessSlider.onValueChanged = function(_, v)
        G().highlightBorderThickness = v; _BumpBorderSerial()
        if type(_G.MSUF_ApplyBarOutlineThickness_All) == "function" then _G.MSUF_ApplyBarOutlineThickness_All() else Apply() end
    end

    -- Right col: highlight borders + priority
    local function MakeOutlineRow(name, dbKey, labelOn, labelOff, anchor, oX, oY, w, applyFn)
        local dd = UI.Dropdown({
            name = name, parent = box3Body,
            anchor = anchor, anchorPoint = "TOPLEFT", x = oX, y = oY, width = w or 170,
            items = { { key = 0, label = TR(labelOff) }, { key = 1, label = TR(labelOn) } },
            get = function() return G()[dbKey] or 0 end,
            set = function(v) G()[dbKey] = v; if type(applyFn) == "function" then applyFn() end end,
        })
        local cb = CreateFrame("CheckButton", name:gsub("Dropdown$", "") .. "TestCheck", box3Body, "ChatConfigCheckButtonTemplate")
        cb:SetPoint("LEFT", dd, "RIGHT", 6, 0)
        cb.Text:SetText(TR("Test"))
        cb:HookScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.tooltipText or "", 1, 1, 1, 1, true); GameTooltip:Show() end)
        cb:HookScript("OnLeave", function() GameTooltip:Hide() end)
        return dd, cb
    end

    local function AggroApply()
        _BumpBorderSerial()
        if type(_G.MSUF_AggroOutline_ApplyEventRegistration) == "function" then _G.MSUF_AggroOutline_ApplyEventRegistration() end
        local fn, frames = _G.MSUF_RefreshRareBarVisuals, _G.MSUF_UnitFrames
        if type(fn) == "function" and frames then
            if frames.target then fn(frames.target) end; if frames.focus then fn(frames.focus) end
            for i = 1, 5 do local b = frames["boss" .. i]; if b then fn(b) end end
        end
    end
    local function DispelPurgeApply()
        _BumpBorderSerial()
        if type(_G.MSUF_DispelOutline_ApplyEventRegistration) == "function" then _G.MSUF_DispelOutline_ApplyEventRegistration() end
        if type(_G.MSUF_RefreshDispelOutlineStates) == "function" then _G.MSUF_RefreshDispelOutlineStates(true); return end
        local fn, frames = _G.MSUF_RefreshRareBarVisuals, _G.MSUF_UnitFrames
        if type(fn) == "function" and frames then
            for _, k in ipairs({ "player", "target", "focus", "targettarget" }) do if frames[k] then fn(frames[k]) end end
        end
    end

    local hlSectionLabel = box3Body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hlSectionLabel:SetPoint("TOPLEFT", box3Body, "TOPLEFT", 340, -2)
    hlSectionLabel:SetText(TR("Highlight borders"))

    local aggroOutlineDrop, aggroTestCheck = MakeOutlineRow("MSUF_AggroOutlineDropdown", "aggroOutlineMode", "Aggro border on", "Aggro border off", hlSectionLabel, -14, -14, 170, AggroApply)
    aggroTestCheck.tooltipText = TR("Aggro border: Target, Focus, Boss frames")
    aggroTestCheck:SetScript("OnClick", function(self) if type(_G.MSUF_SetAggroBorderTestMode) == "function" then _G.MSUF_SetAggroBorderTestMode(self:GetChecked() and true or false) end end)

    local dispelOutlineDrop, dispelTestCheck = MakeOutlineRow("MSUF_DispelOutlineDropdown", "dispelOutlineMode", "Dispel border on", "Dispel border off", aggroOutlineDrop, 0, -28, 170, DispelPurgeApply)
    dispelTestCheck.tooltipText = TR("Dispel border: Player, Target, Focus, Target of Target")
    dispelTestCheck:SetScript("OnClick", function(self) if type(_G.MSUF_SetDispelBorderTestMode) == "function" then _G.MSUF_SetDispelBorderTestMode(self:GetChecked() and true or false) end end)

    local purgeOutlineDrop, purgeTestCheck = MakeOutlineRow("MSUF_PurgeOutlineDropdown", "purgeOutlineMode", "Purge border on", "Purge border off", dispelOutlineDrop, 0, -28, 170, DispelPurgeApply)
    purgeTestCheck.tooltipText = TR("Purge border: Target, Focus, Target of Target")
    purgeTestCheck:SetScript("OnClick", function(self) if type(_G.MSUF_SetPurgeBorderTestMode) == "function" then _G.MSUF_SetPurgeBorderTestMode(self:GetChecked() and true or false) end end)

    -- Priority drag-and-drop
    local _PRIO_DEFAULTS = { "dispel", "aggro", "purge" }
    local _PRIO_LABELS = { dispel = "Dispel", aggro = "Aggro", purge = "Purge" }
    local _PRIO_ROW_H, _PRIO_ROW_GAP = 22, 4
    local _prioRows = {}

    local prioCheck = CreateFrame("CheckButton", "MSUF_HighlightPrioCheck", box3Body, "ChatConfigCheckButtonTemplate")
    prioCheck:SetPoint("TOPLEFT", purgeOutlineDrop, "BOTTOMLEFT", 14, -16)
    prioCheck.Text:SetText(TR("Custom highlight priority"))
    UI.AttachTooltip(prioCheck, TR("Custom highlight priority"), TR("Drag to reorder which highlight border takes priority when multiple are active."))

    local prioContainer = CreateFrame("Frame", "MSUF_HighlightPrioContainer", box3Body)
    prioContainer:SetSize(200, 78); prioContainer:SetPoint("TOPLEFT", prioCheck, "BOTTOMLEFT", -2, -4)

    local function _Prio_GetOrder()
        local g = MSUF_DB and MSUF_DB.general; local o = g and g.highlightPrioOrder
        if type(o) == "table" and #o == 3 then return { o[1], o[2], o[3] } end
        return { _PRIO_DEFAULTS[1], _PRIO_DEFAULTS[2], _PRIO_DEFAULTS[3] }
    end
    local function _Prio_SlotY(s) return -((s - 1) * (_PRIO_ROW_H + _PRIO_ROW_GAP)) end
    local function _Prio_SnapAll()
        for i = 1, 3 do local r = _prioRows[i]; r.frame:ClearAllPoints(); r.frame:SetPoint("TOPLEFT", prioContainer, "TOPLEFT", 0, _Prio_SlotY(r.slotIndex)) end
    end
    local function _Prio_SaveOrder()
        EnsureDB(); G().highlightPrioOrder = {}
        local sorted = {}; for i = 1, 3 do sorted[i] = _prioRows[i] end
        table.sort(sorted, function(a, b) return a.slotIndex < b.slotIndex end)
        for i = 1, 3 do G().highlightPrioOrder[i] = sorted[i].key end
        _BumpBorderSerial()
        if type(_G.MSUF_ApplyBarOutlineThickness_All) == "function" then _G.MSUF_ApplyBarOutlineThickness_All() end
    end
    local function _Prio_SetEnabled(enabled)
        for i = 1, 3 do _prioRows[i].frame:SetAlpha(enabled and 1 or 0.4); _prioRows[i].frame:EnableMouse(enabled) end
    end

    for i = 1, 3 do
        local rf = CreateFrame("Frame", "MSUF_PrioRow" .. i, prioContainer, "BackdropTemplate")
        rf:SetSize(190, _PRIO_ROW_H); rf:SetMovable(true); rf:EnableMouse(true); rf:RegisterForDrag("LeftButton")
        rf:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
        rf:SetBackdropColor(0.12, 0.12, 0.12, 0.85); rf:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
        local stripe = rf:CreateTexture(nil, "ARTWORK"); stripe:SetSize(4, _PRIO_ROW_H - 2); stripe:SetPoint("LEFT", rf, "LEFT", 2, 0); rf._stripe = stripe
        local label = rf:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); label:SetPoint("LEFT", stripe, "RIGHT", 6, 0); rf._label = label
        local num = rf:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall"); num:SetPoint("RIGHT", rf, "RIGHT", -8, 0); num:SetTextColor(0.5, 0.5, 0.5); rf._numText = num
        rf:SetScript("OnDragStart", function(self) GameTooltip:Hide(); self:StartMoving(); self:SetFrameStrata("TOOLTIP") end)
        rf:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing(); self:SetFrameStrata(prioContainer:GetFrameStrata())
            local _, selfY = self:GetCenter(); local contTop = prioContainer:GetTop()
            local bestSlot, bestDist = 1, math.huge
            for s = 1, 3 do local dist = math.abs(selfY - (contTop + _Prio_SlotY(s) - _PRIO_ROW_H / 2)); if dist < bestDist then bestDist = dist; bestSlot = s end end
            local myRow; for idx = 1, 3 do if _prioRows[idx].frame == self then myRow = _prioRows[idx]; break end end
            if myRow and myRow.slotIndex ~= bestSlot then
                for idx = 1, 3 do if _prioRows[idx].slotIndex == bestSlot then _prioRows[idx].slotIndex = myRow.slotIndex; break end end
                myRow.slotIndex = bestSlot
            end
            for idx = 1, 3 do _prioRows[idx].frame._numText:SetText(tostring(_prioRows[idx].slotIndex)) end
            _Prio_SnapAll(); _Prio_SaveOrder()
        end)
        _prioRows[i] = { frame = rf, key = "", slotIndex = i }
    end

    local function _Prio_InitRows()
        local order = _Prio_GetOrder(); local g = G()
        local dbColors = {
            dispel = { g.dispelBorderColorR or 0.25, g.dispelBorderColorG or 0.75, g.dispelBorderColorB or 1 },
            aggro = { g.aggroBorderColorR or 1, g.aggroBorderColorG or 0.5, g.aggroBorderColorB or 0 },
            purge = { g.purgeBorderColorR or 1, g.purgeBorderColorG or 0.85, g.purgeBorderColorB or 0 },
        }
        for i = 1, 3 do
            local key = order[i]; local col = dbColors[key] or { 1, 1, 1 }
            _prioRows[i].key = key; _prioRows[i].slotIndex = i
            _prioRows[i].frame._stripe:SetColorTexture(col[1], col[2], col[3], 1)
            _prioRows[i].frame._label:SetText(TR(_PRIO_LABELS[key] or key))
            _prioRows[i].frame._numText:SetText(tostring(i))
        end; _Prio_SnapAll()
    end
    _Prio_InitRows()
    _G.MSUF_PrioRows_Reinit = function() _Prio_InitRows(); _Prio_SetEnabled(G().highlightPrioEnabled == 1) end

    prioCheck:SetScript("OnClick", function(self)
        G().highlightPrioEnabled = self:GetChecked() and 1 or 0; _Prio_SetEnabled(self:GetChecked()); _Prio_SaveOrder()
    end)
    do local g = G(); prioCheck:SetChecked(g.highlightPrioEnabled == 1); _Prio_SetEnabled(g.highlightPrioEnabled == 1) end

    -- =====================================================================
    -- BOX 4: Power Bar Settings (default open)
    -- =====================================================================
    local box4, box4Body = MakeCollapsibleBox(barGroup, box3, 230, "Power Bar Settings", true)

    local targetPowerBarCheck = CreateLabeledCheckButton("MSUF_TargetPowerBarCheck", "Target", box4Body, 260, -260)
    targetPowerBarCheck:ClearAllPoints(); targetPowerBarCheck:SetPoint("TOPLEFT", box4Body, "TOPLEFT", 14, -8)
    local bossPowerBarCheck = CreateLabeledCheckButton("MSUF_BossPowerBarCheck", "Boss", box4Body, 260, -290)
    bossPowerBarCheck:ClearAllPoints(); bossPowerBarCheck:SetPoint("LEFT", targetPowerBarCheck, "RIGHT", 80, 0)
    local playerPowerBarCheck = CreateLabeledCheckButton("MSUF_PlayerPowerBarCheck", "Player", box4Body, 260, -320)
    playerPowerBarCheck:ClearAllPoints(); playerPowerBarCheck:SetPoint("LEFT", bossPowerBarCheck, "RIGHT", 80, 0)
    local focusPowerBarCheck = CreateLabeledCheckButton("MSUF_FocusPowerBarCheck", "Focus", box4Body, 260, -350)
    focusPowerBarCheck:ClearAllPoints(); focusPowerBarCheck:SetPoint("LEFT", playerPowerBarCheck, "RIGHT", 80, 0)

    local pbSep = box4Body:CreateTexture(nil, "ARTWORK"); pbSep:SetColorTexture(1, 1, 1, 0.06); pbSep:SetHeight(1)
    pbSep:SetPoint("TOPLEFT", box4Body, "TOPLEFT", 14, -38); pbSep:SetWidth(BOX_W - 28)

    local powerBarHeightEdit = CreateLabeledSlider("MSUF_PowerBarHeightEdit", "Power bar height", box4Body, 1, 20, 1, 16, -60)
    powerBarHeightEdit:ClearAllPoints(); powerBarHeightEdit:SetPoint("TOPLEFT", pbSep, "BOTTOMLEFT", 0, -14)
    powerBarHeightEdit:SetWidth(260)
    powerBarHeightEdit.onValueChanged = function(_, v)
        v = floor(v + 0.5); if v < 1 then v = 1 elseif v > 20 then v = 20 end
        B().powerBarHeight = v
        if type(_G.MSUF_ApplyPowerBarEmbedLayout_All) == "function" then _G.MSUF_ApplyPowerBarEmbedLayout_All() end
        Apply()
    end

    local powerBarBorderSizeEdit = CreateLabeledSlider("MSUF_PowerBarBorderSizeEdit", "Border thickness", box4Body, 0, 6, 1, 16, -60)
    powerBarBorderSizeEdit:ClearAllPoints(); powerBarBorderSizeEdit:SetPoint("TOPLEFT", pbSep, "BOTTOMLEFT", 340, -14)
    powerBarBorderSizeEdit:SetWidth(260)
    powerBarBorderSizeEdit.onValueChanged = function(_, v)
        v = floor(v + 0.5); if v < 0 then v = 0 elseif v > 6 then v = 6 end
        B().powerBarBorderThickness = v
        if type(_G.MSUF_ApplyPowerBarBorder_All) == "function" then _G.MSUF_ApplyPowerBarBorder_All() else Apply() end
    end

    local powerBarEmbedCheck = CreateLabeledCheckButton("MSUF_PowerBarEmbedCheck", "Embed into health bar", box4Body, 260, -380)
    powerBarEmbedCheck:ClearAllPoints(); powerBarEmbedCheck:SetPoint("TOPLEFT", powerBarHeightEdit, "BOTTOMLEFT", 0, -20)

    local powerBarBorderCheck = CreateLabeledCheckButton("MSUF_PowerBarBorderCheck", "Power bar border", box4Body, 260, -410)
    powerBarBorderCheck:ClearAllPoints(); powerBarBorderCheck:SetPoint("TOPLEFT", powerBarBorderSizeEdit, "BOTTOMLEFT", 0, -20)

    -- Labels kept as refs for scope dimming (hidden, no text needed)
    local powerBarHeightLabel = box4Body:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    powerBarHeightLabel:SetPoint("TOPLEFT", box4Body, "TOPLEFT", 0, 0); powerBarHeightLabel:SetText(""); powerBarHeightLabel:Hide()
    local powerBarBorderSizeLabel = box4Body:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    powerBarBorderSizeLabel:SetPoint("TOPLEFT", box4Body, "TOPLEFT", 0, 0); powerBarBorderSizeLabel:SetText(""); powerBarBorderSizeLabel:Hide()

    -- =====================================================================
    -- BOX 5: HP / Power Text (default open)
    -- =====================================================================
    local box5, box5Body = MakeCollapsibleBox(barGroup, box4, 200, "HP / Power Text", true)

    local hpModeOptions = {
        { key = "FULL_ONLY", label = "Full value only" }, { key = "FULL_PLUS_PERCENT", label = "Full value + %" },
        { key = "PERCENT_PLUS_FULL", label = "% + Full value" }, { key = "PERCENT_ONLY", label = "Only %" },
    }
    local hpModeDrop = UI.Dropdown({
        name = "MSUF_HPTextModeDropdown", parent = box5Body,
        anchor = box5Body, anchorPoint = "TOPLEFT", x = 0, y = -6, width = 280,
        items = hpModeOptions,
        get = function() return ScopeGet("hpTextMode", "FULL_PLUS_PERCENT") end,
        set = function(v)
            ScopeSet("hpTextMode", v, function()
                Apply(); local uk = _MSUF_HPText_GetUnitKey()
                if uk then ForceTextLayout(uk) else for _, k in ipairs(ALL_UNITS) do ForceTextLayout(k) end end
            end)
        end,
    })

    local function NormPowerMode(m)
        if type(_G.MSUF_NormalizePowerTextMode) == "function" then return _G.MSUF_NormalizePowerTextMode(m) end
        if m == nil then return "CURPERCENT" end
        if m == "FULL_SLASH_MAX" then return "CURMAX" end; if m == "FULL_ONLY" then return "CURRENT" end
        if m == "PERCENT_ONLY" then return "PERCENT" end; if m == "FULL_PLUS_PERCENT" or m == "PERCENT_PLUS_FULL" then return "CURPERCENT" end
        return m
    end

    local powerModeOptions = {
        { key = "CURRENT", label = "Current" }, { key = "MAX", label = "Max" },
        { key = "CURMAX", label = "Cur/Max" }, { key = "PERCENT", label = "Percent" },
        { key = "CURPERCENT", label = "Cur + Percent" }, { key = "CURMAXPERCENT", label = "Cur/Max + Percent" },
    }
    local powerModeDrop = UI.Dropdown({
        name = "MSUF_PowerTextModeDropdown", parent = box5Body,
        anchor = box5Body, anchorPoint = "TOPLEFT", x = 326, y = -6, width = 280,
        items = powerModeOptions,
        get = function() return NormPowerMode(ScopeGet("powerTextMode", "CURPERCENT")) end,
        set = function(v)
            ScopeSet("powerTextMode", v, function()
                Apply(); local uk = _MSUF_HPText_GetUnitKey()
                if uk then ForceTextLayout(uk) else for _, k in ipairs(ALL_UNITS) do ForceTextLayout(k) end end
            end)
        end,
    })

    -- Separators
    local textSepOptions = {
        { key = "", label = " " }, { key = "-", label = "-" }, { key = "/", label = "/" },
        { key = "\\", label = "\\" }, { key = "|", label = "|" }, { key = "<", label = "<" },
        { key = ">", label = ">" }, { key = "~", label = "~" },
        { key = "\194\183", label = "\194\183" }, { key = "\226\128\162", label = "\226\128\162" },
        { key = ":", label = ":" }, { key = "\194\187", label = "\194\187" }, { key = "\194\171", label = "\194\171" },
    }

    local hpSepLabel = box5Body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hpSepLabel:SetPoint("TOPLEFT", hpModeDrop, "BOTTOMLEFT", 14, -10); hpSepLabel:SetText(TR("HP separator"))

    local hpSepDrop = UI.Dropdown({
        name = "MSUF_HPTextSeparatorDropdown", parent = box5Body,
        anchor = hpSepLabel, x = -14, y = -6, width = 120,
        items = textSepOptions,
        get = function() return ScopeGet("hpTextSeparator", "") end,
        set = function(v)
            ScopeSet("hpTextSeparator", v, function()
                local uk = _MSUF_HPText_GetUnitKey()
                if uk then ForceTextLayout(uk) else for _, k in ipairs(ALL_UNITS) do ForceTextLayout(k) end end
            end)
        end,
    })

    local powerSepLabel = box5Body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    powerSepLabel:SetPoint("TOPLEFT", powerModeDrop, "BOTTOMLEFT", 14, -10); powerSepLabel:SetText(TR("Power separator"))

    local powerSepDrop = UI.Dropdown({
        name = "MSUF_PowerTextSeparatorDropdown", parent = box5Body,
        anchor = powerSepLabel, x = -14, y = -6, width = 120,
        items = textSepOptions,
        get = function()
            EnsureDB(); local g = G(); local uk = _MSUF_HPText_GetUnitKey()
            if uk then
                local u = _MSUF_HPText_GetUnitDB(uk)
                if u and u.hpPowerTextOverride then
                    if u.powerTextSeparator ~= nil then return u.powerTextSeparator end
                    if u.hpTextSeparator ~= nil then return u.hpTextSeparator end
                end
            end
            return g.powerTextSeparator ~= nil and g.powerTextSeparator or (g.hpTextSeparator or "")
        end,
        set = function(v)
            ScopeSet("powerTextSeparator", v, function()
                local uk = _MSUF_HPText_GetUnitKey()
                if uk then ForceTextLayout(uk) else for _, k in ipairs(ALL_UNITS) do ForceTextLayout(k) end end
            end)
        end,
    })

    -- =====================================================================
    -- BOX 6: Text Spacers (collapsible, default closed)
    -- =====================================================================
    local box6, box6Body = MakeCollapsibleBox(barGroup, box5, 290, "Text Spacers", false)

    local hpSpacerSelectedLabel = box6Body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hpSpacerSelectedLabel:SetPoint("TOPLEFT", box6Body, "TOPLEFT", 14, -4)
    hpSpacerSelectedLabel:SetTextColor(1, 0.82, 0)

    local hpSpacerInfoButton = CreateFrame("Button", "MSUF_HPSpacerInfoButton", box6Body)
    hpSpacerInfoButton:SetSize(14, 14); hpSpacerInfoButton:SetPoint("LEFT", hpSpacerSelectedLabel, "RIGHT", 4, 0)
    hpSpacerInfoButton:CreateTexture(nil, "ARTWORK"):SetAllPoints(); hpSpacerInfoButton:GetRegions():SetTexture("Interface\\FriendsFrame\\InformationIcon")
    UI.AttachTooltip(hpSpacerInfoButton, "Text Spacers", "Use the scope buttons above to choose which unit these settings apply to.")

    local hpSpacerCheck = CreateFrame("CheckButton", "MSUF_HPTextSpacerCheck", box6Body, "UICheckButtonTemplate")
    hpSpacerCheck:SetPoint("TOPLEFT", hpSpacerSelectedLabel, "BOTTOMLEFT", 0, -4)
    hpSpacerCheck.text = _G["MSUF_HPTextSpacerCheckText"]; if hpSpacerCheck.text then hpSpacerCheck.text:SetText(TR("HP Spacer on/off")) end
    UI.StyleToggleText(hpSpacerCheck); UI.StyleCheckmark(hpSpacerCheck)

    local hpSpacerSlider = CreateLabeledSlider("MSUF_HPTextSpacerSlider", "HP Spacer (X)", box6Body, 0, 1000, 1, 16, -200)
    hpSpacerSlider:ClearAllPoints(); hpSpacerSlider:SetPoint("TOPLEFT", hpSpacerCheck, "BOTTOMLEFT", 0, -30); hpSpacerSlider:SetWidth(260)

    local powerSpacerHeader = box6Body:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    powerSpacerHeader:SetPoint("TOPLEFT", hpSpacerSlider, "BOTTOMLEFT", 0, -18)

    local powerSpacerCheck = CreateFrame("CheckButton", "MSUF_PowerTextSpacerCheck", box6Body, "UICheckButtonTemplate")
    powerSpacerCheck:SetPoint("TOPLEFT", powerSpacerHeader, "BOTTOMLEFT", 0, -4)
    powerSpacerCheck.text = _G["MSUF_PowerTextSpacerCheckText"]; if powerSpacerCheck.text then powerSpacerCheck.text:SetText(TR("Power Spacer on/off")) end
    UI.StyleToggleText(powerSpacerCheck); UI.StyleCheckmark(powerSpacerCheck)

    local powerSpacerSlider = CreateLabeledSlider("MSUF_PowerTextSpacerSlider", "Power Spacer (X)", box6Body, 0, 1000, 1, 16, -200)
    powerSpacerSlider:ClearAllPoints(); powerSpacerSlider:SetPoint("TOPLEFT", powerSpacerCheck, "BOTTOMLEFT", 0, -18); powerSpacerSlider:SetWidth(260)

    -- Spacer system (scope-aware, dynamic ranges)
    local function _TextModeAllowsSpacer(m) return (m == "FULL_PLUS_PERCENT" or m == "PERCENT_PLUS_FULL" or m == "CURPERCENT" or m == "CURMAXPERCENT") end
    local function _NiceUnitKey(k)
        local map = { player = "Player", target = "Target", focus = "Focus", targettarget = "ToT", pet = "Pet", boss = "Boss" }
        return map[k] or tostring(k or "Player")
    end

    local SPACER_SPECS = {
        { id = "hp", check = hpSpacerCheck, slider = hpSpacerSlider, modeKey = "hpTextMode", enabledKey = "hpTextSpacerEnabled", xKey = "hpTextSpacerX", maxFuncName = "MSUF_GetHPSpacerMaxForUnitKey", maxDefault = 1000, maxCap = 2000, dimText = true },
        { id = "power", check = powerSpacerCheck, slider = powerSpacerSlider, modeKey = "powerTextMode", enabledKey = "powerTextSpacerEnabled", xKey = "powerTextSpacerX", maxFuncName = "MSUF_GetPowerSpacerMaxForUnitKey", maxDefault = 1000, maxCap = 1000 },
    }

    local function _HPSpacer_GetSelection()
        EnsureDB(); local scope = _MSUF_HPText_GetScopeKey()
        scope = _MSUF_HPText_NormalizeScopeKey(scope)
        if scope == "shared" then return nil, true end
        local k = scope; if type(_G.MSUF_NormalizeTextLayoutUnitKey) == "function" then k = _G.MSUF_NormalizeTextLayoutUnitKey(k, "player") end
        if not k or k == "shared" then k = "player" end
        G().hpSpacerSelectedUnitKey = k; return k, false
    end
    local function _HPSpacer_GetDB()
        local uk, isShared = _HPSpacer_GetSelection(); EnsureDB()
        if isShared then return nil, G(), true end
        MSUF_DB[uk] = MSUF_DB[uk] or {}; return uk, MSUF_DB[uk], false
    end
    local function _GetEffSpacerMode(uk, spec, g0)
        if not uk then return (g0 and g0[spec.modeKey]) or "FULL_PLUS_PERCENT" end
        local u0 = MSUF_DB[uk]
        return (u0 and u0.hpPowerTextOverride and u0[spec.modeKey]) or (g0 and g0[spec.modeKey]) or "FULL_PLUS_PERCENT"
    end
    local function _GetSpacerMax(spec, uk)
        local mv = spec.maxDefault or 1000
        local fn = spec.maxFuncName and _G[spec.maxFuncName]
        if type(fn) == "function" then local ok, out = pcall(fn, uk); if ok and type(out) == "number" and out > 0 then mv = out end end
        mv = floor(mv + 0.5); if mv < 0 then mv = 0 end; if spec.maxCap and mv > spec.maxCap then mv = spec.maxCap end; return mv
    end

    local function _SyncSpacerControls()
        EnsureDB(); local g0 = G()
        do local p = MSUF_DB.player
            if p then
                if g0.hpTextSpacerEnabled == nil and p.hpTextSpacerEnabled ~= nil then g0.hpTextSpacerEnabled = p.hpTextSpacerEnabled end
                if g0.hpTextSpacerX == nil and p.hpTextSpacerX ~= nil then g0.hpTextSpacerX = p.hpTextSpacerX end
                if g0.powerTextSpacerEnabled == nil and p.powerTextSpacerEnabled ~= nil then g0.powerTextSpacerEnabled = p.powerTextSpacerEnabled end
                if g0.powerTextSpacerX == nil and p.powerTextSpacerX ~= nil then g0.powerTextSpacerX = p.powerTextSpacerX end
            end
        end
        local uk, u, isShared = _HPSpacer_GetDB()
        local unitOverride = not isShared and (u and u.hpPowerTextOverride == true)
        hpSpacerSelectedLabel:SetText("Selected: " .. (isShared and "Shared" or _NiceUnitKey(uk)))

        for _, spec in ipairs(SPACER_SPECS) do
            local cb, sl = spec.check, spec.slider
            local canEdit = isShared or unitOverride
            local src = (isShared and g0) or (unitOverride and u or g0)
            local enabled = src and src[spec.enabledKey] == true
            local mode = _GetEffSpacerMode(uk, spec, g0)
            local modeAllows = _TextModeAllowsSpacer(mode)
            if cb then cb:SetChecked(enabled); cb:SetEnabled(canEdit and modeAllows); cb:SetAlpha((canEdit and modeAllows) and 1 or 0.45) end
            if spec.dimText and cb and cb.text and cb.text.SetTextColor then
                local c = (modeAllows and (canEdit and 1 or 0.75)) or 0.5; cb.text:SetTextColor(c, c, c)
            end
            local maxKey = isShared and "player" or uk
            local maxV = _GetSpacerMax(spec, maxKey)
            if sl and sl.SetMinMaxValues then
                sl:SetMinMaxValues(0, maxV); sl.minVal = 0; sl.maxVal = maxV
                local n = sl:GetName(); if n then local h = _G[n .. "High"]; if h then h:SetText(tostring(maxV)) end end
                local v = tonumber(src and src[spec.xKey]) or 0; if v < 0 then v = 0 end; if v > maxV then v = maxV end
                if canEdit then (isShared and g0 or u)[spec.xKey] = v end
                MSUF_SetLabeledSliderValue(sl, v)
                local slEnabled = canEdit and modeAllows and enabled
                MSUF_SetLabeledSliderEnabled(sl, slEnabled)
                if not slEnabled and sl.SetAlpha then sl:SetAlpha(0.45) end
            end
        end
    end

    local function _RequestTextLayoutForScope(uk, isShared, reason)
        if isShared then for _, k in ipairs(ALL_UNITS) do LayoutKey(k, reason); ForceTextLayout(k) end; return end
        LayoutKey(uk, reason); ForceTextLayout(uk)
    end
    for _, spec in ipairs(SPACER_SPECS) do
        if spec.check then
            spec.check:SetScript("OnClick", function(self)
                EnsureDB(); local uk2, db, isS = _HPSpacer_GetDB(); local g2 = G()
                local canEdit = isS or (db and db.hpPowerTextOverride)
                if not canEdit or not _TextModeAllowsSpacer(_GetEffSpacerMode(uk2, spec, g2)) then _SyncSpacerControls(); return end
                (isS and g2 or db)[spec.enabledKey] = self:GetChecked() and true or false
                _SyncSpacerControls(); _RequestTextLayoutForScope(uk2, isS, "SPACER_TOGGLE")
            end)
        end
        if spec.slider then
            spec.slider.onValueChanged = function(self, value)
                EnsureDB(); local uk2, db, isS = _HPSpacer_GetDB(); local g2 = G()
                local canEdit = isS or (db and db.hpPowerTextOverride)
                if not canEdit or not _TextModeAllowsSpacer(_GetEffSpacerMode(uk2, spec, g2)) then _SyncSpacerControls(); return end
                local maxV = _GetSpacerMax(spec, isS and "player" or uk2)
                local v = tonumber(value) or 0; if v < 0 then v = 0 end; if v > maxV then v = maxV end
                (isS and g2 or db)[spec.xKey] = v
                if v ~= value then MSUF_SetLabeledSliderValue(self, v) end
                _RequestTextLayoutForScope(uk2, isS, "SPACER_X")
            end
        end
    end
    _SyncSpacerControls()
    _G.MSUF_Options_RefreshHPSpacerControls = _SyncSpacerControls

    -- =====================================================================
    -- BOX 7: Bar Animation + Text Accuracy (collapsible, default closed)
    -- =====================================================================
    local box7, box7Body = MakeCollapsibleBox(barGroup, box6, 110, "Bar Animation + Text Accuracy", false)

    local smoothBarCheck = CreateFrame("CheckButton", "MSUF_SmoothPowerBarCheck", box7Body, "UICheckButtonTemplate")
    smoothBarCheck:SetPoint("TOPLEFT", box7Body, "TOPLEFT", 14, -6)
    smoothBarCheck.text = _G["MSUF_SmoothPowerBarCheckText"]; if smoothBarCheck.text then smoothBarCheck.text:SetText(TR("Smooth power bar")) end
    UI.StyleToggleText(smoothBarCheck); UI.StyleCheckmark(smoothBarCheck)
    do EnsureDB(); local v = B().smoothPowerBar; if v == nil then v = true end; smoothBarCheck:SetChecked(v) end
    smoothBarCheck:SetScript("OnClick", function(self) B().smoothPowerBar = self:GetChecked() and true or false
        if type(_G.MSUF_UFCore_RefreshSettingsCache) == "function" then _G.MSUF_UFCore_RefreshSettingsCache("SMOOTH_POWER") end end)

    local smoothHint = box7Body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    smoothHint:SetPoint("TOPLEFT", smoothBarCheck, "BOTTOMLEFT", 0, -1)
    smoothHint:SetText(TR("C-side interpolation for fluid bar movement")); smoothHint:SetTextColor(0.45, 0.45, 0.45)

    local rtTextCheck = CreateFrame("CheckButton", "MSUF_RealtimePowerTextCheck", box7Body, "UICheckButtonTemplate")
    rtTextCheck:SetPoint("TOPLEFT", smoothHint, "BOTTOMLEFT", 0, -6)
    rtTextCheck.text = _G["MSUF_RealtimePowerTextCheckText"]; if rtTextCheck.text then rtTextCheck.text:SetText(TR("Real-time power text")) end
    UI.StyleToggleText(rtTextCheck); UI.StyleCheckmark(rtTextCheck)
    do EnsureDB(); local v = B().realtimePowerText; if v == nil then v = true end; rtTextCheck:SetChecked(v) end
    rtTextCheck:SetScript("OnClick", function(self) B().realtimePowerText = self:GetChecked() and true or false
        if type(_G.MSUF_UFCore_RefreshSettingsCache) == "function" then _G.MSUF_UFCore_RefreshSettingsCache("REALTIME_TEXT") end end)

    -- =====================================================================
    -- Scope UI Sync (_MSUF_SyncHpPowerTextScopeUI)
    -- =====================================================================
    _MSUF_SyncHpPowerTextScopeUI = function()
        EnsureDB(); local uk = _MSUF_HPText_GetUnitKey()

        -- Scope buttons
        RefreshScopeButtons()

        -- Override checkbox
        if hpPowerOverrideCheck then
            if uk then
                local u = _MSUF_HPText_GetUnitDB(uk)
                hpPowerOverrideCheck:Show(); hpPowerOverrideCheck:Enable(); hpPowerOverrideCheck:SetAlpha(1)
                hpPowerOverrideCheck:SetChecked(u and u.hpPowerTextOverride == true)
            else hpPowerOverrideCheck:Hide() end
        end

        -- Reset button + override summary
        if scopeResetBtn then
            if uk then
                scopeResetBtn:Hide()
                scopeOverrideInfo:Hide()
            else
                local active = {}
                for _, uK in ipairs(ALL_UNITS) do
                    local u = MSUF_DB[uK]; if u and u.hpPowerTextOverride then active[#active + 1] = _NiceUnitKey(uK) end
                end
                if #active > 0 then
                    scopeOverrideInfo:SetText("|cffffffffOverrides:|r " .. table.concat(active, ", "))
                    scopeOverrideInfo:SetFontObject(GameFontHighlightSmall)
                    scopeOverrideInfo:Show()
                    scopeResetBtn:Show(); scopeResetBtn:Enable(); scopeResetBtn:SetAlpha(1)
                else
                    scopeOverrideInfo:SetText("|cff9aa0a6No unit overrides active.|r")
                    scopeOverrideInfo:SetFontObject(GameFontDisableSmall)
                    scopeOverrideInfo:Show()
                    scopeResetBtn:Show(); scopeResetBtn:Disable(); scopeResetBtn:SetAlpha(0.45)
                end
            end
        end

        -- Refresh all scope-aware dropdowns
        if hpModeDrop and hpModeDrop.Refresh then hpModeDrop:Refresh() end
        if powerModeDrop and powerModeDrop.Refresh then powerModeDrop:Refresh() end
        if hpSepDrop and hpSepDrop.Refresh then hpSepDrop:Refresh() end
        if powerSepDrop and powerSepDrop.Refresh then powerSepDrop:Refresh() end
        if absorbDisplayDrop and absorbDisplayDrop.Refresh then absorbDisplayDrop:Refresh() end
        if absorbAnchorDrop and absorbAnchorDrop.Refresh then absorbAnchorDrop:Refresh() end
        if MSUF_RefreshAbsorbBarUIEnabled then MSUF_RefreshAbsorbBarUIEnabled() end
        _SyncSpacerControls()

        -- Scope dimming (global-only controls dim when per-unit scope active)
        local isUnit = (uk ~= nil); local ena = not isUnit; local dimAlpha = isUnit and 0.35 or 1
        local function DimDrop(n, lbl) MSUF_SetDropDownEnabled(_G[n], lbl, ena) end
        local function DimCheck(n) MSUF_SetCheckboxEnabled(_G[n], ena) end
        local function DimSlider(n) MSUF_SetLabeledSliderEnabled(_G[n], ena) end
        local function DimFrame(n) local f = _G[n]; if not f then return end; if f.SetAlpha then f:SetAlpha(dimAlpha) end
            if ena then if f.Enable then pcall(f.Enable, f) end else if f.Disable then pcall(f.Disable, f) end end
            if f.EnableMouse then pcall(f.EnableMouse, f, ena) end end
        local function DimLabel(fs) if not fs then return end
            if fs.SetTextColor then if ena then fs:SetTextColor(1, 1, 1) else fs:SetTextColor(0.35, 0.35, 0.35) end
            elseif fs.SetAlpha then fs:SetAlpha(dimAlpha) end end

        -- Box 1 dims (textures + gradient)
        DimDrop("MSUF_BarTextureDropdown"); DimDrop("MSUF_BarBackgroundTextureDropdown")
        DimLabel(texColLabel); DimLabel(barBgTexLabel)
        DimCheck("MSUF_GradientEnableCheck"); DimCheck("MSUF_PowerGradientEnableCheck")
        DimSlider("MSUF_GradientStrengthSlider"); DimFrame("MSUF_GradientDirectionPad")
        DimLabel(gradColLabel)

        -- Box 2 dims (absorb textures)
        DimDrop("MSUF_AbsorbBarTextureDropdown"); DimDrop("MSUF_HealAbsorbBarTextureDropdown")
        DimCheck("MSUF_AbsorbTextureTestModeCheck"); DimCheck("MSUF_SelfHealPredictionCheck")
        DimLabel(absorbTextureLabel); DimLabel(healAbsorbLabel)

        -- Box 3 dims (outline + highlight)
        DimSlider("MSUF_BarOutlineThicknessSlider"); DimSlider("MSUF_HighlightBorderThicknessSlider")
        DimDrop("MSUF_AggroOutlineDropdown"); DimCheck("MSUF_AggroOutlineTestCheck")
        DimDrop("MSUF_DispelOutlineDropdown"); DimCheck("MSUF_DispelOutlineTestCheck")
        DimDrop("MSUF_PurgeOutlineDropdown"); DimCheck("MSUF_PurgeOutlineTestCheck")
        DimCheck("MSUF_HighlightPrioCheck"); DimFrame("MSUF_HighlightPrioContainer")
        DimLabel(hlSectionLabel)

        -- Box 4 dims (power bar)
        DimCheck("MSUF_TargetPowerBarCheck"); DimCheck("MSUF_BossPowerBarCheck")
        DimCheck("MSUF_PlayerPowerBarCheck"); DimCheck("MSUF_FocusPowerBarCheck")
        DimSlider("MSUF_PowerBarHeightEdit"); DimCheck("MSUF_PowerBarEmbedCheck")
        DimCheck("MSUF_PowerBarBorderCheck"); DimSlider("MSUF_PowerBarBorderSizeEdit")
        DimLabel(powerBarHeightLabel); DimLabel(powerBarBorderSizeLabel)

        -- Box titles dim
        if box1._msufTitle then DimLabel(box1._msufTitle) end
        if box3._msufTitle then DimLabel(box3._msufTitle) end
        if box4._msufTitle then DimLabel(box4._msufTitle) end
    end

    _Scope_SyncUI = _MSUF_SyncHpPowerTextScopeUI
    _MSUF_SyncHpPowerTextScopeUI()

    -- =====================================================================
    -- MSUF_BarsApplyGradient (live gradient apply)
    -- =====================================================================
    local MSUF_BarsApplyGradient
    MSUF_BarsApplyGradient = function()
        EnsureDB(); local g = G()
        if (g.enableGradient ~= false) or (g.enablePowerGradient ~= false) then
            if not (tonumber(g.gradientStrength) and tonumber(g.gradientStrength) > 0) then g.gradientStrength = 0.45 end
        end
        if gradientDirPad and gradientDirPad.SyncFromDB then gradientDirPad:SyncFromDB() end
        if InCombatLockdown and InCombatLockdown() then Apply()
        elseif type(_G.MSUF_ApplyAllSettings_Immediate) == "function" then _G.MSUF_ApplyAllSettings_Immediate()
        else Apply() end
        local function Repaint()
            local frames = _G.MSUF_UnitFrames; if type(frames) ~= "table" then RefreshFrames(); return end
            for _, f in pairs(frames) do if f and f.unit and f.hpBar then
                f._msufHeavyVisualNextAt = 0
                if _G.UpdateSimpleUnitFrame then _G.UpdateSimpleUnitFrame(f) end
                if type(_G.MSUF_UFCore_UpdatePowerBarFast) == "function" then _G.MSUF_UFCore_UpdatePowerBarFast(f) end
            end end
        end
        Repaint()
        if C_Timer then C_Timer.After(0.08, Repaint) end
    end

    -- =====================================================================
    -- SyncAll (called on OnShow)
    -- =====================================================================
    local function SyncAll()
        EnsureDB(); local g = G(); local b = B()
        local hpGrad = (g.enableGradient ~= false); local powGrad = (g.enablePowerGradient ~= false)
        if gradientCheck then gradientCheck:SetChecked(hpGrad) end
        if powerGradientCheck then powerGradientCheck:SetChecked(powGrad) end
        if gradientDirPad then
            if gradientDirPad.SyncFromDB then gradientDirPad:SyncFromDB() end
            if gradientDirPad.SetEnabledVisual then gradientDirPad:SetEnabledVisual(hpGrad or powGrad) end
        end
        if gradientStrengthSlider then
            local v = tonumber(g.gradientStrength) or 0.45; if v < 0 then v = 0 elseif v > 1 then v = 1 end
            MSUF_SetLabeledSliderValue(gradientStrengthSlider, v)
            MSUF_SetLabeledSliderEnabled(gradientStrengthSlider, hpGrad or powGrad)
        end
        if barOutlineThicknessSlider then local t = floor((tonumber(b.barOutlineThickness) or 1) + 0.5); if t < 0 then t = 0 elseif t > 6 then t = 6 end; MSUF_SetLabeledSliderValue(barOutlineThicknessSlider, t) end
        if highlightBorderThicknessSlider then local t = floor((tonumber(g.highlightBorderThickness) or 2) + 0.5); if t < 1 then t = 1 elseif t > 6 then t = 6 end; MSUF_SetLabeledSliderValue(highlightBorderThicknessSlider, t) end
        if _G.MSUF_PrioRows_Reinit then _G.MSUF_PrioRows_Reinit() end
        local function SC(cb, v) if cb then cb:SetChecked(v and true or false); if cb.__msufToggleUpdate then cb.__msufToggleUpdate() end end end
        SC(targetPowerBarCheck, b.showTargetPowerBar); SC(bossPowerBarCheck, b.showBossPowerBar)
        SC(playerPowerBarCheck, b.showPlayerPowerBar); SC(focusPowerBarCheck, b.showFocusPowerBar)
        SC(powerBarEmbedCheck, b.embedPowerBarIntoHealth); SC(powerBarBorderCheck, b.powerBarBorderEnabled)
        local anyPB = not (b.showTargetPowerBar == false and b.showBossPowerBar == false and b.showPlayerPowerBar == false and b.showFocusPowerBar == false)
        local borderOn = b.powerBarBorderEnabled == true
        local function SetCtrl(c, on)
            if not c then return end
            if on then if c.Enable then c:Enable() end; if c.SetAlpha then c:SetAlpha(1) end
            else if c.Disable then c:Disable() end; if c.SetAlpha then c:SetAlpha(0.55) end end
        end
        if powerBarHeightLabel then powerBarHeightLabel:SetTextColor(anyPB and 1 or 0.35, anyPB and 1 or 0.35, anyPB and 1 or 0.35) end
        do
            local h = floor((tonumber(b.powerBarHeight) or 6) + 0.5); if h < 1 then h = 1 elseif h > 20 then h = 20 end
            MSUF_SetLabeledSliderValue(powerBarHeightEdit, h)
            MSUF_SetLabeledSliderEnabled(powerBarHeightEdit, anyPB)
        end
        SetCtrl(powerBarEmbedCheck, anyPB); SetCtrl(powerBarBorderCheck, anyPB)
        if powerBarBorderSizeLabel then powerBarBorderSizeLabel:SetTextColor((anyPB and borderOn) and 1 or 0.35, (anyPB and borderOn) and 1 or 0.35, (anyPB and borderOn) and 1 or 0.35) end
        do
            local t = floor((tonumber(b.powerBarBorderThickness) or 1) + 0.5); if t < 0 then t = 0 elseif t > 6 then t = 6 end
            MSUF_SetLabeledSliderValue(powerBarBorderSizeEdit, t)
            MSUF_SetLabeledSliderEnabled(powerBarBorderSizeEdit, anyPB and borderOn)
        end
        local smoothCB = _G["MSUF_SmoothPowerBarCheck"]; if smoothCB then local v = b.smoothPowerBar; if v == nil then v = true end; smoothCB:SetChecked(v) end
        local rtCB = _G["MSUF_RealtimePowerTextCheck"]; if rtCB then local v = b.realtimePowerText; if v == nil then v = true end; rtCB:SetChecked(v) end
        _MSUF_SyncHpPowerTextScopeUI()
        MSUF_BarsMenu_QueueScrollUpdate()
    end
    SyncAll()
    if barGroup.HookScript then barGroup:HookScript("OnShow", SyncAll) end

    -- =====================================================================
    -- DB bindings
    -- =====================================================================
    if _G.MSUF_Options_BindDBBoolCheck then
        _G.MSUF_Options_BindDBBoolCheck(gradientCheck, "general.enableGradient", MSUF_BarsApplyGradient, SyncAll)
        _G.MSUF_Options_BindDBBoolCheck(powerGradientCheck, "general.enablePowerGradient", MSUF_BarsApplyGradient, SyncAll)
        local function Bind(cb, path, apply) if cb then _G.MSUF_Options_BindDBBoolCheck(cb, path, apply or Apply, SyncAll) end end
        Bind(targetPowerBarCheck, "bars.showTargetPowerBar")
        Bind(bossPowerBarCheck, "bars.showBossPowerBar")
        Bind(playerPowerBarCheck, "bars.showPlayerPowerBar")
        Bind(focusPowerBarCheck, "bars.showFocusPowerBar")
        Bind(powerBarEmbedCheck, "bars.embedPowerBarIntoHealth", function()
            if type(_G.MSUF_ApplyPowerBarEmbedLayout_All) == "function" then _G.MSUF_ApplyPowerBarEmbedLayout_All() end; Apply()
        end)
        Bind(powerBarBorderCheck, "bars.powerBarBorderEnabled", function()
            if type(_G.MSUF_ApplyPowerBarBorder_All) == "function" then _G.MSUF_ApplyPowerBarBorder_All() else Apply() end
        end)
    end
    if gradientStrengthSlider then
        gradientStrengthSlider.onValueChanged = function(_, v) G().gradientStrength = v; MSUF_BarsApplyGradient() end
    end

    -- =====================================================================
    -- Panel stores (Core compat)
    -- =====================================================================
    panel.gradientCheck = gradientCheck; panel.powerGradientCheck = powerGradientCheck
    panel.gradientDirPad = gradientDirPad or _G["MSUF_GradientDirectionPad"]
    panel.targetPowerBarCheck = targetPowerBarCheck; panel.bossPowerBarCheck = bossPowerBarCheck
    panel.playerPowerBarCheck = playerPowerBarCheck; panel.focusPowerBarCheck = focusPowerBarCheck
    panel.powerBarHeightEdit = powerBarHeightEdit; panel.powerBarEmbedCheck = powerBarEmbedCheck
    panel.powerBarBorderCheck = powerBarBorderCheck; panel.powerBarBorderSizeEdit = powerBarBorderSizeEdit
    panel.hpModeDrop = hpModeDrop; panel.barTextureDrop = barTextureDrop
    panel.barOutlineThicknessSlider = barOutlineThicknessSlider
    panel.highlightBorderThicknessSlider = highlightBorderThicknessSlider
    panel.aggroOutlineDrop = aggroOutlineDrop; panel.aggroTestCheck = aggroTestCheck
    panel.dispelOutlineDrop = dispelOutlineDrop; panel.dispelTestCheck = dispelTestCheck
    panel.purgeOutlineDrop = purgeOutlineDrop; panel.purgeTestCheck = purgeTestCheck
    panel.prioCheck = prioCheck
    if type(MSUF_BarsApplyGradient) == "function" then _G.MSUF_BarsApplyGradient = MSUF_BarsApplyGradient end
end
