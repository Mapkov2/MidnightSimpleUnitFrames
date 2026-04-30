-- MSUF_Options_Bars.lua  (Phase 4: A2-style scope bar + collapsible boxes)
-- Bar appearance: absorb display, textures, gradients, outlines,
-- highlight borders (aggro/dispel/purge), priority reorder,
-- power bar settings, HP/Power text modes, separators, spacers,
-- bar animation, per-unit scope system.
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
    local function Apply() if _G.ApplyAllSettings then _G.ApplyAllSettings() end end
    local function LayoutKey(k, reason, urgent)
        if _G.MSUF_Options_RequestLayoutForKey then _G.MSUF_Options_RequestLayoutForKey(k, reason, urgent) end
    end
    local function ForceTextLayout(k) if _G.MSUF_ForceTextLayoutForUnitKey then _G.MSUF_ForceTextLayoutForUnitKey(k) end end
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
    local _Scope_GetGFKey  -- returns "gf_party"/"gf_raid" DB key if in GF scope, else nil

    -- Scope-aware get/set helpers
    local function ScopeGet(generalKey, defaultVal)
        EnsureDB()
        -- GF scope override (party/raid) — check FIRST (unitKey also returns "party"/"raid")
        local gfKey = _Scope_GetGFKey and _Scope_GetGFKey()
        if gfKey then
            local gf = MSUF_DB[gfKey]
            if gf and gf.hlOverride and gf[generalKey] ~= nil then return gf[generalKey] end
        else
            -- Per-unit override (unified hlOverride flag)
            local uk = _Scope_GetUnitKey and _Scope_GetUnitKey()
            if uk then
                local u = MSUF_DB[uk]
                if u and u.hlOverride and u[generalKey] ~= nil then return u[generalKey] end
            end
        end
        local v = G()[generalKey]
        return v ~= nil and v or defaultVal
    end

    local function ScopeSet(generalKey, val, applyFn)
        EnsureDB()
        -- GF scope override (party/raid) — check FIRST (unitKey also returns "party"/"raid")
        local gfKey = _Scope_GetGFKey and _Scope_GetGFKey()
        if gfKey then
            MSUF_DB[gfKey] = MSUF_DB[gfKey] or {}
            local gf = MSUF_DB[gfKey]
            if not gf.hlOverride then
                gf.hlOverride = true
                if type(HlSeedFromGeneral) == "function" then HlSeedFromGeneral(gf) end
            end
            gf[generalKey] = val
        else
            -- Per-unit override (unified hlOverride flag)
            local uk = _Scope_GetUnitKey and _Scope_GetUnitKey()
            if uk then
                local u = type(_Scope_GetUnitDB) == "function" and _Scope_GetUnitDB(uk)
                if u then
                    if not u.hlOverride then
                        u.hlOverride = true
                        if type(HlSeedFromGeneral) == "function" then HlSeedFromGeneral(u) end
                    end
                    u[generalKey] = val
                end
            else
                G()[generalKey] = val
            end
        end
        if type(applyFn) == "function" then pcall(applyFn, val) end
        if type(_Scope_SyncUI) == "function" then _Scope_SyncUI() end
    end

    local function ScopeGetBars(barsKey, defaultVal)
        EnsureDB()
        local gfKey = _Scope_GetGFKey and _Scope_GetGFKey()
        if gfKey then
            local gf = MSUF_DB[gfKey]
            if gf and gf.hlOverride and gf[barsKey] ~= nil then return gf[barsKey] end
        else
            local uk = _Scope_GetUnitKey and _Scope_GetUnitKey()
            if uk then
                local u = MSUF_DB[uk]
                if u and u.hlOverride and u[barsKey] ~= nil then return u[barsKey] end
            end
        end
        local b = B()
        local v = b and b[barsKey]
        return v ~= nil and v or defaultVal
    end

    local function ScopeSetBars(barsKey, val, applyFn)
        EnsureDB()
        local gfKey = _Scope_GetGFKey and _Scope_GetGFKey()
        if gfKey then
            MSUF_DB[gfKey] = MSUF_DB[gfKey] or {}
            local gf = MSUF_DB[gfKey]
            if not gf.hlOverride then
                gf.hlOverride = true
                if type(HlSeedFromGeneral) == "function" then HlSeedFromGeneral(gf) end
            end
            gf[barsKey] = val
        else
            local uk = _Scope_GetUnitKey and _Scope_GetUnitKey()
            if uk then
                local u = type(_Scope_GetUnitDB) == "function" and _Scope_GetUnitDB(uk)
                if u then
                    if not u.hlOverride then
                        u.hlOverride = true
                        if type(HlSeedFromGeneral) == "function" then HlSeedFromGeneral(u) end
                    end
                    u[barsKey] = val
                end
            else
                B()[barsKey] = val
            end
        end
        if type(applyFn) == "function" then pcall(applyFn, val) end
        if type(_Scope_SyncUI) == "function" then _Scope_SyncUI() end
    end

    -- Box helpers (A2 style)
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

    -- SCOPE BAR (A2-style button strip)
    local SCOPE_KEYS = { "shared", "player", "target", "targettarget", "focus", "pet", "boss", "party", "raid" }
    local SCOPE_LABELS = {
        shared = "Shared", player = "Player", target = "Target",
        targettarget = "ToT", focus = "Focus", pet = "Pet", boss = "Boss",
        party = "Party", raid = "Raid",
    }
    local GF_SCOPE_KEYS = { party = "gf_party", raid = "gf_raid" }
    local function IsGFScope(key) return GF_SCOPE_KEYS[key] ~= nil end
    local function GetGFDBKey(key) return GF_SCOPE_KEYS[key] end

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
        EnsureDB()
        local gfKey = GF_SCOPE_KEYS[key]
        if gfKey then
            local gf = MSUF_DB[gfKey]
            return (gf and gf.hlOverride == true)
        end
        local u = MSUF_DB[key]
        return (u and u.hlOverride == true)
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
        -- Switch GF preview to match scope (party vs raid)
        if _barsGFPreviewOn and _BarsShowGFPreview then
            if key == "party" or key == "raid" then _BarsShowGFPreview(key)
            else _BarsShowGFPreview("party") end
        end
    end

    do
        local prevBtn
        for _, k in ipairs(SCOPE_KEYS) do
            local bk = k
            local btn = CreateFrame("Button", nil, scopeBar, "BackdropTemplate")
            btn:SetSize(bk == "shared" and 56 or 48, 18)
            if not prevBtn then
                btn:SetPoint("LEFT", scopeEditLbl, "RIGHT", 8, 0)
            elseif bk == "party" then
                -- Visual separator before GF scope buttons
                btn:SetPoint("LEFT", prevBtn, "RIGHT", 10, 0)
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
                    elseif IsGFScope(bk) then
                        local tip = GetScopeUnitHasOverride(bk) and TR("Override active: Group Frames use their own highlight settings.") or TR("Uses Shared highlight settings.")
                        GameTooltip:AddLine(tip, 0.72, 0.78, 0.88, true)
                        GameTooltip:AddLine(TR("Only Outline & Highlight Border applies to Group Frames."), 0.55, 0.60, 0.72, true)
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

    -- Scope helper functions
    _MSUF_HPText_NormalizeScopeKey = function(v) if v == nil or v == "" or v == "shared" then return "shared" end; return v end
    _MSUF_HPText_GetScopeKey = function() return _MSUF_HPText_NormalizeScopeKey(G().hpPowerTextSelectedKey) end
    _MSUF_HPText_GetUnitKey = function()
        local k = _MSUF_HPText_GetScopeKey(); if k == "shared" then return nil end; return k
    end
    _MSUF_HPText_GetUnitDB = function(unitKey) EnsureDB(); MSUF_DB[unitKey] = MSUF_DB[unitKey] or {}; return MSUF_DB[unitKey] end
    _MSUF_HPText_EnableOverride = function(unitKey)
        local u = _MSUF_HPText_GetUnitDB(unitKey); if not u then return end
        u.hlOverride = true
        local g = G()
        if u.hpTextMode == nil then u.hpTextMode = g.hpTextMode end
        if u.hpTextReverse == nil then u.hpTextReverse = g.hpTextReverse end
        if u.powerTextMode == nil then u.powerTextMode = g.powerTextMode end
        if u.hpTextSeparator == nil then u.hpTextSeparator = g.hpTextSeparator end
        if u.powerTextSeparator == nil then u.powerTextSeparator = g.powerTextSeparator end
        if u.absorbTextMode == nil then u.absorbTextMode = g.absorbTextMode end
        if u.absorbAnchorMode == nil then u.absorbAnchorMode = g.absorbAnchorMode end
        if u.absorbBarOpacity == nil then u.absorbBarOpacity = g.absorbBarOpacity end
        if u.healAbsorbBarOpacity == nil then u.healAbsorbBarOpacity = g.healAbsorbBarOpacity end
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
    _Scope_GetGFKey = function()
        local sk = _MSUF_HPText_GetScopeKey and _MSUF_HPText_GetScopeKey() or "shared"
        return GF_SCOPE_KEYS[sk]   -- "gf_party" / "gf_raid" / nil
    end

    local HlSeedFromGeneral  -- forward decl (defined in highlight section below)
    local _BumpBorderSerial  -- forward decl (defined in highlight section below; captured as upvalue by closures above)

    -- Override checkbox handler
    hpPowerOverrideCheck:SetScript("OnClick", function(self)
        local scopeKey = _MSUF_HPText_GetScopeKey()
        if scopeKey == "shared" then self:SetChecked(false); return end

        -- GF scope: toggle hlOverride in gf_party/gf_raid
        if IsGFScope(scopeKey) then
            local gfKey = GetGFDBKey(scopeKey)
            EnsureDB(); MSUF_DB[gfKey] = MSUF_DB[gfKey] or {}
            local gf = MSUF_DB[gfKey]
            if self:GetChecked() then
                gf.hlOverride = true
                HlSeedFromGeneral(gf)
            else
                gf.hlOverride = false
            end
            local GF = _G.MSUF_NS and _G.MSUF_NS.GF
            if GF and GF.InvalidateConfCache then GF.InvalidateConfCache() end
            if GF and GF.RefreshVisuals then GF.RefreshVisuals()
            elseif GF and GF.MarkAllDirty then GF.MarkAllDirty(GF.DIRTY_BORDER) end
            if _MSUF_SyncHpPowerTextScopeUI then _MSUF_SyncHpPowerTextScopeUI() end
            return
        end

        -- Unit scope: toggle hlOverride
        local uk = _MSUF_HPText_GetUnitKey(); if not uk then self:SetChecked(false); return end
        local u = _MSUF_HPText_GetUnitDB(uk); if not u then self:SetChecked(false); return end
        if self:GetChecked() then
            _MSUF_HPText_EnableOverride(uk)
            u.hlOverride = true
            HlSeedFromGeneral(u)
        else
            u.hlOverride = false
        end
        _BumpBorderSerial()
        Apply(); ForceTextLayout(uk)
        -- Re-stamp absorb anchor on UF frames only — GF frames have their own
        -- anchor pipeline (_msufGFAbsorbAnchorStamp namespace + _GF_ApplyAbsorbAnchor)
        -- and would be corrupted by main-UF logic touching `f.hpBar` / wrong stamps.
        if _G.MSUF_UnitFrames then
            if _G.MSUF_InvalidateAbsorbCache then _G.MSUF_InvalidateAbsorbCache() end
            local applyAnchor = _G.MSUF_ApplyAbsorbAnchorMode
            local updateUF    = _G.UpdateSimpleUnitFrame
            for _, f in pairs(_G.MSUF_UnitFrames) do
                if f and f.unit and not f._msufIsGroupFrame then
                    f._msufAbsorbAnchorModeStamp = nil
                    f._msufAbsorbFollowActive    = nil
                    if applyAnchor then applyAnchor(f) end
                    if updateUF    then updateUF(f)    end
                end
            end
        end
        -- Group Frames refresh through their own pipeline so per-GF overrides
        -- and the GF-side anchor diff-gate stay consistent.
        local GF = _G.MSUF_NS and _G.MSUF_NS.GF
        if GF and GF.RefreshVisuals then GF.RefreshVisuals() end
        if _MSUF_SyncHpPowerTextScopeUI then _MSUF_SyncHpPowerTextScopeUI() end
    end)

    -- Reset overrides handler
    scopeResetBtn:SetScript("OnClick", function()
        EnsureDB(); local any = false
        for _, uk in ipairs(ALL_UNITS) do
            local u = MSUF_DB[uk]
            if u then
                if u.hlOverride then u.hlOverride = false; any = true end
            end
        end
        for _, gfKey in pairs(GF_SCOPE_KEYS) do
            local gf = MSUF_DB[gfKey]
            if gf and gf.hlOverride then gf.hlOverride = false; any = true end
        end
        if any then
            _BumpBorderSerial()
            Apply(); for _, uk in ipairs(ALL_UNITS) do ForceTextLayout(uk) end; RefreshFrames()
            local GF = _G.MSUF_NS and _G.MSUF_NS.GF
            if GF and GF.RefreshVisuals then GF.RefreshVisuals() end
        end
        if _MSUF_SyncHpPowerTextScopeUI then _MSUF_SyncHpPowerTextScopeUI() end
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

    -- Scope hint for GF inheritance
    local barsGFHint = barGroup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    barsGFHint:SetPoint("TOPLEFT", scopeBar, "BOTTOMLEFT", 4, -6)
    barsGFHint:SetWidth(600)
    barsGFHint:SetJustifyH("LEFT")
    barsGFHint:SetText("Group Frames inherit these textures by default. Override per Party/Raid in Group Frames > Bars & Text.")
    barsGFHint:SetTextColor(0.50, 0.60, 0.75)

    -- BOX 1: Textures & Gradient (default open)
    local box1, box1Body = MakeCollapsibleBox(barGroup, barsGFHint, 200, "Textures & Gradient", true)

    -- Left col: Bar textures
    local texColLabel = MakeSectionLabel(box1Body, box1Body, "Bar textures (SharedMedia)", -6)
    texColLabel:SetPoint("TOPLEFT", box1Body, "TOPLEFT", 14, -6)

    local function ApplyBarTex()
        if _G.MSUF_UpdateAllBarTextures_Immediate then _G.MSUF_UpdateAllBarTextures_Immediate()
        elseif _G.MSUF_UpdateAllBarTextures then _G.MSUF_UpdateAllBarTextures()
        else Apply() end
        -- Refresh GF textures + gradient overlays
        local GF = _G.MSUF_NS and _G.MSUF_NS.GF
        if GF and GF.MarkAllDirty then GF.MarkAllDirty(GF.DIRTY_TEXTURE or 0x02) end
    end
    _G.MSUF_TryApplyBarTextureLive = ApplyBarTex

    local barTextureDrop = UI.Dropdown({
        name = "MSUF_BarTextureDropdown", parent = box1Body,
        anchor = texColLabel, x = -14, y = -4, width = 280, maxVisible = 12,
        iconWidth = 80, iconHeight = 12,
        items = function() return UI.StatusBarTextureItems(nil) end,
        get = function() return ScopeGet("barTexture", "Blizzard") end,
        set = function(v) ScopeSet("barTexture", v, ApplyBarTex) end,
    })

    local barBgTexLabel = box1Body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    barBgTexLabel:SetPoint("TOPLEFT", barTextureDrop, "BOTTOMLEFT", 14, -6)
    barBgTexLabel:SetText(TR("Background texture")); barBgTexLabel:SetTextColor(0.75, 0.75, 0.75)

    local barBgTextureDrop = UI.Dropdown({
        name = "MSUF_BarBackgroundTextureDropdown", parent = box1Body,
        anchor = barBgTexLabel, x = -14, y = -4, width = 280, maxVisible = 12,
        iconWidth = 80, iconHeight = 12,
        items = function() return UI.StatusBarTextureItems(TR("Use foreground texture")) end,
        get = function() return ScopeGet("barBackgroundTexture", "") end,
        set = function(v) ScopeSet("barBackgroundTexture", v, ApplyBarTex) end,
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

    -- BOX 2: Absorb Display (default open)
    local box2, box2Body = MakeCollapsibleBox(barGroup, box1, 280, "Absorb Display", true)

    local function ApplyAbsorb(mode)
        if _G.MSUF_InvalidateAbsorbCache then _G.MSUF_InvalidateAbsorbCache() end
        if _G.MSUF_UpdateAbsorbTextMode then _G.MSUF_UpdateAbsorbTextMode(mode) end
        if _G.MSUF_UFCore_NotifyConfigChanged then
            _G.MSUF_UFCore_NotifyConfigChanged(nil, true, true, "AbsorbDisplay")
        else
            RefreshFrames()
        end
        -- Refresh GF: synchronous full refresh (applies per-GF resolve + preview data)
        local GF = _G.MSUF_NS and _G.MSUF_NS.GF
        if GF and GF.RefreshVisuals then GF.RefreshVisuals()
        elseif _G.MSUF_GF_RefreshOverlays then _G.MSUF_GF_RefreshOverlays() end
    end
    local function ApplyAbsorbAnchor()
        if _G.MSUF_InvalidateAbsorbCache then _G.MSUF_InvalidateAbsorbCache() end
        if _G.MSUF_UnitFrames and type(_G.MSUF_ApplyAbsorbAnchorMode) == "function" then
            for _, f in pairs(_G.MSUF_UnitFrames) do
                if f and f.unit and not f._msufIsGroupFrame then
                    f._msufAbsorbAnchorModeStamp = nil; f._msufAbsorbFollowActive = nil
                    _G.MSUF_ApplyAbsorbAnchorMode(f)
                    if _G.UpdateSimpleUnitFrame then _G.UpdateSimpleUnitFrame(f) end
                end
            end
        end
        -- Refresh GF: synchronous full refresh (per-GF anchor + overlay colors + preview)
        local GF = _G.MSUF_NS and _G.MSUF_NS.GF
        if GF and GF.RefreshVisuals then GF.RefreshVisuals()
        elseif _G.MSUF_GF_RefreshOverlays then _G.MSUF_GF_RefreshOverlays() end
    end
    local function ApplyAbsorbTex()
        if _G.MSUF_UpdateAbsorbBarTextures then _G.MSUF_UpdateAbsorbBarTextures()
        elseif _G.MSUF_UpdateAllUnitFrames then _G.MSUF_UpdateAllUnitFrames()
        else RefreshFrames() end
        if _G.MSUF_AbsorbTextureTestMode then RefreshFrames() end
        local GF = _G.MSUF_NS and _G.MSUF_NS.GF
        if GF and GF.RefreshVisuals then GF.RefreshVisuals()
        elseif GF and GF.MarkAllDirty then GF.MarkAllDirty(GF.DIRTY_TEXTURE or 0x02) end
    end
    local function ApplyAbsorbOpacity()
        if _G.MSUF_InvalidateAbsorbCache then _G.MSUF_InvalidateAbsorbCache() end
        if _G.MSUF_UnitFrames then
            for _, f in pairs(_G.MSUF_UnitFrames) do
                if f and not f._msufIsGroupFrame then f._msufAbsorbDirty = true; f._msufHealAbsorbDirty = true end
            end
        end
        RefreshFrames()
        -- Refresh GF: synchronous full refresh (per-GF opacity + preview data)
        local GF = _G.MSUF_NS and _G.MSUF_NS.GF
        if GF and GF.RefreshVisuals then GF.RefreshVisuals()
        elseif _G.MSUF_GF_RefreshOverlays then _G.MSUF_GF_RefreshOverlays() end
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

    local absorbTexTestCB = CreateFrame("CheckButton", "MSUF_AbsorbTextureTestModeCheck", box2Body, "UICheckButtonTemplate")
    absorbTexTestCB:SetPoint("TOPLEFT", absorbAnchorDrop, "BOTTOMLEFT", 14, -8)
    absorbTexTestCB.text = _G["MSUF_AbsorbTextureTestModeCheckText"]
    if absorbTexTestCB.text then absorbTexTestCB.text:SetText(TR("Test absorb textures")); absorbTexTestCB.text:SetTextColor(0.75, 0.75, 0.75) end
    UI.StyleCheckmark(absorbTexTestCB)
    absorbTexTestCB:SetChecked(_G.MSUF_AbsorbTextureTestMode and true or false)
    absorbTexTestCB:SetScript("OnClick", function(self)
        _G.MSUF_AbsorbTextureTestMode = self:GetChecked() and true or false
        RefreshFrames()
        if _G.MSUF_GF_RefreshOverlays then _G.MSUF_GF_RefreshOverlays() end
    end)
    absorbTexTestCB:SetScript("OnHide", function(self)
        if barGroup:IsShown() then return end
        if _G.MSUF_AbsorbTextureTestMode then
            _G.MSUF_AbsorbTextureTestMode = false; self:SetChecked(false)
            RefreshFrames()
            if _G.MSUF_GF_RefreshOverlays then _G.MSUF_GF_RefreshOverlays() end
        end
    end)

    local selfHealPredCB = CreateFrame("CheckButton", "MSUF_SelfHealPredictionCheck", box2Body, "UICheckButtonTemplate")
    selfHealPredCB:SetPoint("LEFT", absorbTexTestCB, "RIGHT", 140, 0)
    selfHealPredCB.text = _G["MSUF_SelfHealPredictionCheckText"]
    if selfHealPredCB.text then selfHealPredCB.text:SetText(TR("Heal prediction")); selfHealPredCB.text:SetTextColor(0.75, 0.75, 0.75) end
    UI.StyleCheckmark(selfHealPredCB)
    do EnsureDB(); selfHealPredCB:SetChecked(ScopeGet("showSelfHealPrediction", false) and true or false) end
    selfHealPredCB:SetScript("OnClick", function(self) ScopeSet("showSelfHealPrediction", self:GetChecked() and true or false, RefreshFrames) end)

    -- Right col: absorb textures (aligned with left col)
    local absorbTextureLabel = box2Body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    absorbTextureLabel:SetPoint("TOPLEFT", box2Body, "TOPLEFT", 340, -6)
    absorbTextureLabel:SetText(TR("Absorb bar texture (SharedMedia)")); absorbTextureLabel:SetTextColor(0.75, 0.75, 0.75)

    local absorbBarTextureDrop = UI.Dropdown({
        name = "MSUF_AbsorbBarTextureDropdown", parent = box2Body,
        anchor = absorbTextureLabel, x = -14, y = -4, width = 280, maxVisible = 12,
        iconWidth = 80, iconHeight = 12,
        items = function() return UI.StatusBarTextureItems(TR("Use foreground texture")) end,
        get = function() return ScopeGet("absorbBarTexture", "") end,
        set = function(v) ScopeSet("absorbBarTexture", v, function() ApplyAbsorbTex(); Apply() end) end,
    })

    local healAbsorbLabel = box2Body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    healAbsorbLabel:SetPoint("TOPLEFT", absorbBarTextureDrop, "BOTTOMLEFT", 14, -8)
    healAbsorbLabel:SetText(TR("Heal-absorb texture")); healAbsorbLabel:SetTextColor(0.75, 0.75, 0.75)

    local healAbsorbTextureDrop = UI.Dropdown({
        name = "MSUF_HealAbsorbBarTextureDropdown", parent = box2Body,
        anchor = healAbsorbLabel, x = -14, y = -4, width = 280, maxVisible = 12,
        iconWidth = 80, iconHeight = 12,
        items = function() return UI.StatusBarTextureItems(TR("Use foreground texture")) end,
        get = function() return ScopeGet("healAbsorbBarTexture", "") end,
        set = function(v) ScopeSet("healAbsorbBarTexture", v, function() ApplyAbsorbTex(); Apply() end) end,
    })

    local absorbOpacitySlider = CreateLabeledSlider("MSUF_AbsorbBarOpacitySlider", "Absorb bar opacity", box2Body, 0, 1, 0.05, 16, -200)
    absorbOpacitySlider:ClearAllPoints(); absorbOpacitySlider:SetPoint("TOPLEFT", absorbTexTestCB, "BOTTOMLEFT", 0, -6)
    if absorbOpacitySlider.SetWidth then absorbOpacitySlider:SetWidth(280) end
    absorbOpacitySlider.onValueChanged = function(_, v) ScopeSet("absorbBarOpacity", v, ApplyAbsorbOpacity) end

    local healAbsorbOpacitySlider = CreateLabeledSlider("MSUF_HealAbsorbBarOpacitySlider", "Heal-absorb bar opacity", box2Body, 0, 1, 0.05, 16, -200)
    healAbsorbOpacitySlider:ClearAllPoints(); healAbsorbOpacitySlider:SetPoint("TOPLEFT", absorbOpacitySlider, "TOPLEFT", 326, 0)
    if healAbsorbOpacitySlider.SetWidth then healAbsorbOpacitySlider:SetWidth(280) end
    healAbsorbOpacitySlider.onValueChanged = function(_, v) ScopeSet("healAbsorbBarOpacity", v, ApplyAbsorbOpacity) end

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
        MSUF_SetLabeledSliderEnabled(absorbOpacitySlider, barEnabled)
        MSUF_SetLabeledSliderEnabled(healAbsorbOpacitySlider, barEnabled)
        if not barEnabled and _G.MSUF_AbsorbTextureTestMode then
            _G.MSUF_AbsorbTextureTestMode = false; absorbTexTestCB:SetChecked(false); RefreshFrames()
        end
    end
    MSUF_RefreshAbsorbBarUIEnabled()

    -- BOX 3: Outline & Highlight Border (default open)
    -- Assign (not re-declare) so closures defined earlier capture the upvalue
    -- from the forward-decl above.
    _BumpBorderSerial = function()
        if _G.MSUF_UFCore_RefreshSettingsCache then _G.MSUF_UFCore_RefreshSettingsCache("BAR_OPTION") end
    end

    --- Scope-aware DB target for highlight writes.
    --- GF scope → gf_party/gf_raid, unit scope → MSUF_DB[unit], else → general.
    local function HlDB()
        local scopeKey = _MSUF_HPText_GetScopeKey and _MSUF_HPText_GetScopeKey() or "shared"
        local gfKey = GF_SCOPE_KEYS[scopeKey]
        if gfKey then
            EnsureDB(); MSUF_DB[gfKey] = MSUF_DB[gfKey] or {}
            return MSUF_DB[gfKey]
        end
        if scopeKey ~= "shared" then
            EnsureDB(); MSUF_DB[scopeKey] = MSUF_DB[scopeKey] or {}
            return MSUF_DB[scopeKey]
        end
        return G()
    end
    local function HlGet(key, def)
        local scopeKey = _MSUF_HPText_GetScopeKey and _MSUF_HPText_GetScopeKey() or "shared"
        local gfKey = GF_SCOPE_KEYS[scopeKey]
        if gfKey then
            EnsureDB()
            local gf = MSUF_DB[gfKey]
            if gf and gf.hlOverride and gf[key] ~= nil then return gf[key] end
        elseif scopeKey ~= "shared" then
            EnsureDB()
            local u = MSUF_DB[scopeKey]
            if u and u.hlOverride and u[key] ~= nil then return u[key] end
        end
        local gen = G()
        if gen[key] ~= nil then return gen[key] end
        return def
    end
    local function HlApply()
        local scopeKey = _MSUF_HPText_GetScopeKey and _MSUF_HPText_GetScopeKey() or "shared"
        _BumpBorderSerial()
        local GF = _G.MSUF_NS and _G.MSUF_NS.GF
        if GF and GF.InvalidateConfCache then GF.InvalidateConfCache() end
        if IsGFScope(scopeKey) then
            if GF and GF.RefreshVisuals then GF.RefreshVisuals()
            elseif GF and GF.MarkAllDirty then GF.MarkAllDirty(GF.DIRTY_BORDER or 0x10) end
        else
            if _G.MSUF_ApplyBarOutlineThickness_All then _G.MSUF_ApplyBarOutlineThickness_All() else Apply() end
            if GF and GF.MarkAllDirty then GF.MarkAllDirty(GF.DIRTY_BORDER or 0x10) end
        end
    end
    local function HlApplyGF()
        local GF = _G.MSUF_NS and _G.MSUF_NS.GF
        if not GF then return end
        if GF.InvalidateConfCache then GF.InvalidateConfCache() end
        if GF.RefreshVisuals then GF.RefreshVisuals()
        elseif GF.MarkAllDirty then GF.MarkAllDirty(GF.DIRTY_BORDER or 0x10) end
    end
    local function IsCurrentScopeGF()
        local scopeKey = _MSUF_HPText_GetScopeKey and _MSUF_HPText_GetScopeKey() or "shared"
        return IsGFScope(scopeKey)
    end
    local function IsCurrentScopeNonShared()
        local scopeKey = _MSUF_HPText_GetScopeKey and _MSUF_HPText_GetScopeKey() or "shared"
        return scopeKey ~= "shared"
    end
    local function IsCurrentScopeOverrideActive()
        local scopeKey = _MSUF_HPText_GetScopeKey and _MSUF_HPText_GetScopeKey() or "shared"
        if scopeKey == "shared" then return false end
        local gfKey = GF_SCOPE_KEYS[scopeKey]
        if gfKey then
            local gf = MSUF_DB and MSUF_DB[gfKey]
            return gf and gf.hlOverride == true
        end
        local u = MSUF_DB and MSUF_DB[scopeKey]
        return u and u.hlOverride == true
    end
    --- Seed hl* values from general into scope DB when first enabling override.
    HlSeedFromGeneral = function(db)
        local gen = G()
        local seeds = {
            -- Box 1: Textures & Gradient
            "barTexture", "barBackgroundTexture",
            "gradientEnabled", "powerGradientEnabled", "gradientStrength",
            "gradientDirection",
            -- Box 2: Absorb Display
            "absorbTextMode", "absorbAnchorMode",
            "absorbBarOpacity", "healAbsorbBarOpacity",
            "absorbBarTexture", "healAbsorbBarTexture",
            "showSelfHealPrediction",
            -- Box 3: Highlight borders
            "hlAggroEnabled", "hlAggroSize", "hlAggroOffset", "hlAggroLayer", "hlAggroMode",
            "hlAggroColorR", "hlAggroColorG", "hlAggroColorB",
            "hlDispelEnabled", "hlDispelColorR", "hlDispelColorG", "hlDispelColorB",
            "hlDispelGlowEnabled", "hlDispelGlowStyle", "hlDispelGlowLines",
            "hlDispelGlowFrequency", "hlDispelGlowThickness",
            "hlPurgeEnabled", "hlPurgeColorR", "hlPurgeColorG", "hlPurgeColorB",
            "hlTargetEnabled", "hlTargetSize", "hlTargetOffset", "hlTargetLayer",
            "hlTargetColorR", "hlTargetColorG", "hlTargetColorB",
            "hlHoverSize", "hlHoverOffset",
            "hlPrioEnabled", "hlPrioOrder",
            -- Box 5/6: HP / Power Text
            "hpTextMode", "powerTextMode", "hpTextReverse",
            "hpTextSeparator", "powerTextSeparator",
            "hpTextSpacerEnabled", "hpTextSpacerX",
            "powerTextSpacerEnabled", "powerTextSpacerX",
            "hpTextAnchor", "powerTextAnchor",
            -- Box 7: Animation
            "smoothPowerBar", "realtimePowerText",
        }
        for _, key in ipairs(seeds) do
            if db[key] == nil then
                local v = gen[key]
                if v ~= nil then
                    if type(v) == "table" then
                        db[key] = {}; for i, e in ipairs(v) do db[key][i] = e end
                    else
                        db[key] = v
                    end
                end
            end
        end
        -- Legacy fallbacks for first-time migration
        if db.hlAggroSize == nil then db.hlAggroSize = gen.highlightBorderThickness or 2 end
        if db.barOutlineThickness == nil then db.barOutlineThickness = B().barOutlineThickness end
        if db.hlAggroEnabled == nil then db.hlAggroEnabled = (gen.aggroOutlineMode == 1) end
        if db.hlDispelEnabled == nil then db.hlDispelEnabled = (gen.dispelOutlineMode == 1) end
        if db.hlPurgeEnabled == nil then db.hlPurgeEnabled = (gen.purgeOutlineMode == 1) end
    end

    local box3a, box3aBody = MakeCollapsibleBox(barGroup, box2, 80, "Frame Outline", false)

    -- Left col: thickness sliders
    local barOutlineThicknessSlider = CreateLabeledSlider("MSUF_BarOutlineThicknessSlider", "Outline thickness", box3aBody, 0, 6, 1, 16, -350)
    barOutlineThicknessSlider:ClearAllPoints(); barOutlineThicknessSlider:SetPoint("TOPLEFT", box3aBody, "TOPLEFT", 14, -10)
    barOutlineThicknessSlider:SetWidth(280)
    do local n = barOutlineThicknessSlider:GetName(); local t = _G[n .. "Text"]; if t then t:SetText(""); t:Hide() end end
    barOutlineThicknessSlider.onValueChanged = function(_, v)
        v = floor(v + 0.5); if v < 0 then v = 0 elseif v > 6 then v = 6 end
        ScopeSetBars("barOutlineThickness", v); _BumpBorderSerial()
        if _G.MSUF_ApplyBarOutlineThickness_All then _G.MSUF_ApplyBarOutlineThickness_All() else Apply() end
        -- Also refresh GF (unified: outline thickness controls GF frame border too)
        local GF = _G.MSUF_NS and _G.MSUF_NS.GF
        if GF then
            if GF.InvalidateConfCache then GF.InvalidateConfCache() end
            if GF.RefreshVisuals then GF.RefreshVisuals() end
        end
    end


    local box3b, box3bBody = MakeCollapsibleBox(barGroup, box3a, 560, "Highlight Borders", true)

    local highlightBorderThicknessSlider = CreateLabeledSlider("MSUF_HighlightBorderThicknessSlider", "Highlight border thickness", box3bBody, 1, 30, 1, 16, -420)
    highlightBorderThicknessSlider:ClearAllPoints(); highlightBorderThicknessSlider:SetPoint("TOPLEFT", box3bBody, "TOPLEFT", 14, -10)
    highlightBorderThicknessSlider:SetWidth(280)
    highlightBorderThicknessSlider.onValueChanged = function(_, v)
        v = floor(v + 0.5); if v < 1 then v = 1 elseif v > 30 then v = 30 end
        EnsureDB()
        MSUF_DB.general.highlightBorderThickness = v
        MSUF_DB.general.hlAggroSize = v
        local scopeDB = HlDB(); if scopeDB then scopeDB.hlAggroSize = v end
        if MSUF_DB.gf_party then MSUF_DB.gf_party.hlAggroSize = v end
        if MSUF_DB.gf_raid then MSUF_DB.gf_raid.hlAggroSize = v end
        -- UF refresh
        _BumpBorderSerial()
        if _G.MSUF_ApplyBarOutlineThickness_All then _G.MSUF_ApplyBarOutlineThickness_All() end
        -- GF refresh: invalidate cache + re-render every visible highlight border
        local GF = _G.MSUF_NS and _G.MSUF_NS.GF
        local rfb = _G.MSUF_GF_RefreshBorder
        if GF and rfb and GF.frames then
            if GF.InvalidateConfCache then GF.InvalidateConfCache() end
            for gf in pairs(GF.frames) do
                local hb = gf._msufGFHighlightBorder
                if hb then
                    hb._msufHLEdgeSz = nil
                    hb._msufHLEdge = nil
                    hb._msufHLOfs = nil
                    rfb(gf, gf.unit)
                end
            end
        end
    end

    -- Right col: highlight borders + priority
    -- Prio defaults (declared early so dispel color mode dropdown closure can see them)
    local _PRIO_3 = { "dispel", "aggro", "purge", "bossTarget" }
    local _PRIO_6 = { "magic", "curse", "disease", "poison", "bleed", "aggro", "purge", "bossTarget" }

    local function MakeOutlineRow(name, dbKey, hlKey, labelOn, labelOff, anchor, oX, oY, w, applyFn)
        local dd = UI.Dropdown({
            name = name, parent = box3bBody,
            anchor = anchor, anchorPoint = "TOPLEFT", x = oX, y = oY, width = w or 170,
            items = { { key = 0, label = TR(labelOff) }, { key = 1, label = TR(labelOn) } },
            get = function()
                if IsCurrentScopeNonShared() and hlKey then
                    return (HlGet(hlKey, false) and 1 or 0)
                end
                return G()[dbKey] or 0
            end,
            set = function(v)
                if IsCurrentScopeNonShared() then
                    if hlKey then HlDB()[hlKey] = (v == 1) end
                    HlApply()
                else
                    G()[dbKey] = v
                    if hlKey then G()[hlKey] = (v == 1) end
                    if type(applyFn) == "function" then applyFn() end
                end
            end,
        })
        local cb = CreateFrame("CheckButton", name:gsub("Dropdown$", "") .. "TestCheck", box3bBody, "ChatConfigCheckButtonTemplate")
        cb:SetPoint("LEFT", dd, "RIGHT", 6, 0)
        cb.Text:SetText(TR("Test"))
        cb:HookScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.tooltipText or "", 1, 1, 1, 1, true); GameTooltip:Show() end)
        cb:HookScript("OnLeave", function() GameTooltip:Hide() end)
        return dd, cb
    end

    local function AggroApply()
        _BumpBorderSerial()
        if _G.MSUF_AggroOutline_ApplyEventRegistration then _G.MSUF_AggroOutline_ApplyEventRegistration() end
        local fn, frames = _G.MSUF_RefreshRareBarVisuals, _G.MSUF_UnitFrames
        if type(fn) == "function" and frames then
            if frames.target then fn(frames.target) end; if frames.focus then fn(frames.focus) end
            for i = 1, 5 do local b = frames["boss" .. i]; if b then fn(b) end end
        end
        HlApplyGF()
    end
    local function DispelPurgeApply()
        _BumpBorderSerial()
        if _G.MSUF_DispelOutline_ApplyEventRegistration then _G.MSUF_DispelOutline_ApplyEventRegistration() end
        if _G.MSUF_RefreshDispelOutlineStates then _G.MSUF_RefreshDispelOutlineStates(true) end
        local fn, frames = _G.MSUF_RefreshRareBarVisuals, _G.MSUF_UnitFrames
        if type(fn) == "function" and frames then
            for _, k in ipairs({ "player", "target", "focus", "targettarget" }) do if frames[k] then fn(frames[k]) end end
        end
        HlApplyGF()
    end

    local aggroOutlineDrop, aggroTestCheck = MakeOutlineRow("MSUF_AggroOutlineDropdown", "aggroOutlineMode", "hlAggroEnabled", "Aggro border on", "Aggro border off", highlightBorderThicknessSlider, 0, -70, 170, AggroApply)
    aggroTestCheck.tooltipText = TR("Aggro border: Target, Focus, Boss, Party, Raid frames")
    aggroTestCheck:SetScript("OnClick", function(self)
        local scope = _MSUF_HPText_GetScopeKey and _MSUF_HPText_GetScopeKey() or "shared"
        if _G.MSUF_SetAggroBorderTestMode then _G.MSUF_SetAggroBorderTestMode(self:GetChecked() and true or false, scope) end
    end)

    local dispelOutlineDrop, dispelTestCheck = MakeOutlineRow("MSUF_DispelOutlineDropdown", "dispelOutlineMode", "hlDispelEnabled", "Dispel border on", "Dispel border off", aggroOutlineDrop, 0, -28, 170, DispelPurgeApply)
    dispelTestCheck.tooltipText = TR("Dispel border: Player, Target, Focus, Target of Target, Party, Raid")
    dispelTestCheck:SetScript("OnClick", function(self)
        local scope = _MSUF_HPText_GetScopeKey and _MSUF_HPText_GetScopeKey() or "shared"
        if _G.MSUF_SetDispelBorderTestMode then _G.MSUF_SetDispelBorderTestMode(self:GetChecked() and true or false, scope) end
    end)

    -- Per-type test dropdown (visible next to Test checkbox)
    _G.MSUF_DispelBorderTestType = _G.MSUF_DispelBorderTestType or "Magic"
    local dispelTestTypeDrop = UI.Dropdown({
        name = "MSUF_DispelTestTypeDropdown", parent = box3bBody,
        anchor = dispelTestCheck, anchorPoint = "RIGHT", x = 30, y = 10, width = 90,
        items = {
            { key = "Magic",   label = TR("Magic") },
            { key = "Curse",   label = TR("Curse") },
            { key = "Disease", label = TR("Disease") },
            { key = "Poison",  label = TR("Poison") },
            { key = "Bleed",   label = TR("Bleed") },
        },
        get = function() return _G.MSUF_DispelBorderTestType or "Magic" end,
        set = function(v)
            _G.MSUF_DispelBorderTestType = v
            if _G.MSUF_DispelBorderTestMode then
                local scope = _MSUF_HPText_GetScopeKey and _MSUF_HPText_GetScopeKey() or "shared"
                if _G.MSUF_SetDispelBorderTestMode then _G.MSUF_SetDispelBorderTestMode(true, scope) end
            end
        end,
    })
    UI.AttachTooltip(_G["MSUF_DispelTestTypeDropdown"], TR("Preview type"),
        TR("Which dispel type to preview when Test is checked.\nVisible difference only with 'Per debuff type' color mode (set in Colors > Dispel)."))

    -- Helper: apply glow change + re-trigger test mode if active
    local function GlowApply()
        HlApply(); HlApplyGF()
        if _G.MSUF_DispelBorderTestMode and _G.MSUF_SetDispelBorderTestMode then
            local scope = _MSUF_HPText_GetScopeKey and _MSUF_HPText_GetScopeKey() or "shared"
            _G.MSUF_SetDispelBorderTestMode(true, scope)
        end
    end

    -- Dispel glow toggle
    local dispelGlowCheck = CreateFrame("CheckButton", "MSUF_DispelGlowCheck", box3bBody, "ChatConfigCheckButtonTemplate")
    dispelGlowCheck:SetPoint("TOPLEFT", dispelOutlineDrop, "BOTTOMLEFT", 14, -28)
    dispelGlowCheck.Text:SetText(TR("Dispel glow effect"))
    dispelGlowCheck:SetChecked(HlGet("hlDispelGlowEnabled", false) and true or false)
    UI.AttachTooltip(dispelGlowCheck, TR("Dispel glow"),
        TR("Adds an animated glow overlay to the dispel border highlight.\nUses LibCustomGlow. Color follows the dispel border color."))

    -- Glow settings container (shown only when glow enabled)
    local glowContainer = CreateFrame("Frame", nil, box3bBody)
    glowContainer:SetSize(250, 1)
    glowContainer:SetPoint("TOPLEFT", dispelGlowCheck, "BOTTOMLEFT", -14, -4)

    -- Glow style dropdown
    local dispelGlowStyleDrop = UI.Dropdown({
        name = "MSUF_DispelGlowStyleDropdown", parent = glowContainer,
        anchor = glowContainer, anchorPoint = "TOPLEFT", x = 0, y = 0, width = 170,
        items = {
            { key = "PIXEL",    label = "Pixel" },
            { key = "AUTOCAST", label = "AutoCast" },
            { key = "PROC",     label = "Proc" },
        },
        get = function() return HlGet("hlDispelGlowStyle", "PIXEL") end,
        set = function(v)
            HlDB().hlDispelGlowStyle = v
            G().hlDispelGlowStyle = v
            GlowApply()
        end,
    })
    UI.AttachTooltip(_G["MSUF_DispelGlowStyleDropdown"], TR("Glow style"),
        TR("Pixel: animated dots around the border.\nAutoCast: spinning sparkle particles.\nProc: spell activation overlay."))

    -- Glow lines slider
    local dispelGlowLinesSlider = CreateLabeledSlider("MSUF_DispelGlowLinesSlider", "Glow lines / particles", glowContainer, 2, 16, 1, 16, -350)
    dispelGlowLinesSlider:ClearAllPoints(); dispelGlowLinesSlider:SetPoint("TOPLEFT", dispelGlowStyleDrop, "BOTTOMLEFT", 0, -8)
    if dispelGlowLinesSlider.SetWidth then dispelGlowLinesSlider:SetWidth(170) end
    dispelGlowLinesSlider.onValueChanged = function(_, v)
        HlDB().hlDispelGlowLines = v
        G().hlDispelGlowLines = v
        GlowApply()
    end

    -- Glow frequency slider
    local dispelGlowFreqSlider = CreateLabeledSlider("MSUF_DispelGlowFreqSlider", "Glow speed", glowContainer, 0.05, 1.0, 0.05, 16, -350)
    dispelGlowFreqSlider:ClearAllPoints(); dispelGlowFreqSlider:SetPoint("TOPLEFT", dispelGlowLinesSlider, "TOPLEFT", 0, -60)
    if dispelGlowFreqSlider.SetWidth then dispelGlowFreqSlider:SetWidth(170) end
    dispelGlowFreqSlider.onValueChanged = function(_, v)
        HlDB().hlDispelGlowFrequency = v
        G().hlDispelGlowFrequency = v
        GlowApply()
    end

    -- Glow thickness slider (Pixel only)
    local dispelGlowThickSlider = CreateLabeledSlider("MSUF_DispelGlowThickSlider", "Glow thickness (Pixel)", glowContainer, 1, 5, 1, 16, -350)
    dispelGlowThickSlider:ClearAllPoints(); dispelGlowThickSlider:SetPoint("TOPLEFT", dispelGlowFreqSlider, "TOPLEFT", 0, -60)
    if dispelGlowThickSlider.SetWidth then dispelGlowThickSlider:SetWidth(170) end
    dispelGlowThickSlider.onValueChanged = function(_, v)
        HlDB().hlDispelGlowThickness = v
        G().hlDispelGlowThickness = v
        GlowApply()
    end

    -- Toggle glow container + re-anchor purge
    local function RefreshGlowVisibility()
        local on = dispelGlowCheck:GetChecked() and true or false
        glowContainer:SetShown(on)
    end
    RefreshGlowVisibility()

    dispelGlowCheck:SetScript("OnClick", function(self)
        local v = self:GetChecked() and true or false
        HlDB().hlDispelGlowEnabled = v
        G().hlDispelGlowEnabled = v
        RefreshGlowVisibility()
        GlowApply()
        MSUF_BarsMenu_QueueScrollUpdate()
    end)

    -- Purge/Boss anchor dynamically: below glow container or checkbox
    local purgeAnchor = CreateFrame("Frame", nil, box3bBody)
    purgeAnchor:SetSize(1, 1)
    local function RepositionPurgeAnchor()
        purgeAnchor:ClearAllPoints()
        if glowContainer:IsShown() then
            purgeAnchor:SetPoint("TOPLEFT", dispelGlowThickSlider, "TOPLEFT", 0, 0)
        else
            purgeAnchor:SetPoint("TOPLEFT", dispelGlowCheck, "BOTTOMLEFT", -14, 6)
        end
    end
    RepositionPurgeAnchor()
    glowContainer:HookScript("OnShow", RepositionPurgeAnchor)
    glowContainer:HookScript("OnHide", RepositionPurgeAnchor)

    local purgeOutlineDrop, purgeTestCheck = MakeOutlineRow("MSUF_PurgeOutlineDropdown", "purgeOutlineMode", "hlPurgeEnabled", "Purge border on", "Purge border off", purgeAnchor, 0, -60, 170, DispelPurgeApply)
    purgeTestCheck.tooltipText = TR("Purge border: Target, Focus, Target of Target, Boss")
    purgeTestCheck:SetScript("OnClick", function(self) if _G.MSUF_SetPurgeBorderTestMode then _G.MSUF_SetPurgeBorderTestMode(self:GetChecked() and true or false) end end)

    local function BossTargetApply()
        _BumpBorderSerial()
        local fn, frames = _G.MSUF_RefreshRareBarVisuals, _G.MSUF_UnitFrames
        if type(fn) == "function" and frames then
            for i = 1, 5 do local b = frames["boss" .. i]; if b then fn(b) end end
        end
    end
    local bossTargetOutlineDrop, bossTargetTestCheck = MakeOutlineRow("MSUF_BossTargetOutlineDropdown", "bossTargetOutlineMode", nil, "Boss target border on", "Boss target border off", purgeOutlineDrop, 0, -28, 170, BossTargetApply)
    bossTargetTestCheck.tooltipText = TR("Boss target border: highlights the boss frame you are targeting")
    bossTargetTestCheck:SetScript("OnClick", function(self) if _G.MSUF_SetBossTargetBorderTestMode then _G.MSUF_SetBossTargetBorderTestMode(self:GetChecked() and true or false) end end)

    -- Clear test modes on panel hide so preview borders don't linger
    aggroTestCheck:SetScript("OnHide", function(self)
        if _G.MSUF_AggroBorderTestMode and type(_G.MSUF_SetAggroBorderTestMode) == "function" then
            _G.MSUF_SetAggroBorderTestMode(false); self:SetChecked(false)
        end
    end)
    dispelTestCheck:SetScript("OnHide", function(self)
        if _G.MSUF_DispelBorderTestMode and type(_G.MSUF_SetDispelBorderTestMode) == "function" then
            _G.MSUF_SetDispelBorderTestMode(false); self:SetChecked(false)
        end
    end)
    purgeTestCheck:SetScript("OnHide", function(self)
        if _G.MSUF_PurgeBorderTestMode and type(_G.MSUF_SetPurgeBorderTestMode) == "function" then
            _G.MSUF_SetPurgeBorderTestMode(false); self:SetChecked(false)
        end
    end)
    bossTargetTestCheck:SetScript("OnHide", function(self)
        if _G.MSUF_BossTargetBorderTestMode and type(_G.MSUF_SetBossTargetBorderTestMode) == "function" then
            _G.MSUF_SetBossTargetBorderTestMode(false); self:SetChecked(false)
        end
    end)


    local box3c, box3cBody = MakeCollapsibleBox(barGroup, box3b, 280, "Highlight Priority", false)

    -- Priority drag-and-drop (dynamic: 3 rows for SINGLE, 6 for TYPE)
    local _PRIO_LABELS = {
        dispel = "Dispel", aggro = "Aggro", purge = "Purge", bossTarget = "Boss Target",
        magic = "Magic", curse = "Curse", disease = "Disease", poison = "Poison", bleed = "Bleed",
    }
    local _PRIO_COLORS = {
        dispel  = { 0.25, 0.75, 1.00 },
        aggro   = { 1.00, 0.50, 0.00 },
        purge   = { 1.00, 0.85, 0.00 },
        bossTarget = { 1.00, 0.82, 0.00 },
        magic   = { 0.20, 0.60, 1.00 },
        curse   = { 0.60, 0.00, 1.00 },
        disease = { 0.60, 0.40, 0.00 },
        poison  = { 0.00, 0.60, 0.00 },
        bleed   = { 0.80, 0.10, 0.10 },
    }
    local _PRIO_ROW_H, _PRIO_ROW_GAP = 22, 4
    local _PRIO_MAX = 8
    local _prioRows = {}
    local _prioCount = 3

    local prioCheck = CreateFrame("CheckButton", "MSUF_HighlightPrioCheck", box3cBody, "ChatConfigCheckButtonTemplate")
    prioCheck:SetPoint("TOPLEFT", box3cBody, "TOPLEFT", 14, -8)
    prioCheck.Text:SetText(TR("Custom highlight priority"))
    UI.AttachTooltip(prioCheck, TR("Custom highlight priority"), TR("Drag to reorder which highlight border takes priority when multiple are active."))

    local prioContainer = CreateFrame("Frame", "MSUF_HighlightPrioContainer", box3cBody)
    prioContainer:SetSize(200, _PRIO_MAX * (_PRIO_ROW_H + _PRIO_ROW_GAP))
    prioContainer:SetPoint("TOPLEFT", prioCheck, "BOTTOMLEFT", -2, -4)

    local function _Prio_IsTypeMode()
        return HlGet("hlDispelColorMode", "SINGLE") == "TYPE"
    end
    local function _Prio_GetDefaults()
        return _Prio_IsTypeMode() and _PRIO_6 or _PRIO_3
    end
    local function _Prio_GetOrder()
        local defs = _Prio_GetDefaults()
        local n = #defs
        local o = HlGet("hlPrioOrder", nil)
        if type(o) == "table" and #o == n then return o, n end
        -- Migrate: append bossTarget if missing from old orders
        if type(o) == "table" and (#o == n - 1) then
            o[n] = "bossTarget"; return o, n
        end
        -- Fallback: try legacy
        if not _Prio_IsTypeMode() then
            local g = MSUF_DB and MSUF_DB.general
            local og = g and g.highlightPrioOrder
            if type(og) == "table" and #og == 3 then og[4] = "bossTarget"; return og, 4 end
        end
        local out = {}; for i = 1, n do out[i] = defs[i] end
        return out, n
    end
    local function _Prio_SlotY(s) return -((s - 1) * (_PRIO_ROW_H + _PRIO_ROW_GAP)) end
    local function _Prio_SnapAll()
        for i = 1, _prioCount do
            local r = _prioRows[i]
            r.frame:ClearAllPoints()
            r.frame:SetPoint("TOPLEFT", prioContainer, "TOPLEFT", 0, _Prio_SlotY(r.slotIndex))
            r.frame:Show()
        end
        for i = _prioCount + 1, _PRIO_MAX do
            if _prioRows[i] then _prioRows[i].frame:Hide() end
        end
        prioContainer:SetHeight(_prioCount * (_PRIO_ROW_H + _PRIO_ROW_GAP))
    end
    local function _Prio_SaveOrder()
        EnsureDB()
        local order = {}
        local sorted = {}; for i = 1, _prioCount do sorted[i] = _prioRows[i] end
        table.sort(sorted, function(a, b) return a.slotIndex < b.slotIndex end)
        for i = 1, _prioCount do order[i] = sorted[i].key end
        local db = HlDB()
        db.hlPrioOrder = order
        if not IsCurrentScopeNonShared() and _prioCount == 3 then db.highlightPrioOrder = order end
        HlApply()
    end
    local function _Prio_SetEnabled(enabled)
        for i = 1, _prioCount do
            _prioRows[i].frame:SetAlpha(enabled and 1 or 0.4)
            _prioRows[i].frame:EnableMouse(enabled)
        end
    end

    -- Create max rows upfront
    for i = 1, _PRIO_MAX do
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
            for s = 1, _prioCount do
                local dist = math.abs(selfY - (contTop + _Prio_SlotY(s) - _PRIO_ROW_H / 2))
                if dist < bestDist then bestDist = dist; bestSlot = s end
            end
            local myRow; for idx = 1, _prioCount do if _prioRows[idx].frame == self then myRow = _prioRows[idx]; break end end
            if myRow and myRow.slotIndex ~= bestSlot then
                for idx = 1, _prioCount do if _prioRows[idx].slotIndex == bestSlot then _prioRows[idx].slotIndex = myRow.slotIndex; break end end
                myRow.slotIndex = bestSlot
            end
            for idx = 1, _prioCount do _prioRows[idx].frame._numText:SetText(tostring(_prioRows[idx].slotIndex)) end
            _Prio_SnapAll(); _Prio_SaveOrder()
        end)
        rf:Hide()
        _prioRows[i] = { frame = rf, key = "", slotIndex = i }
    end

    local function _Prio_InitRows()
        local order, n = _Prio_GetOrder()
        _prioCount = n
        for i = 1, n do
            local key = order[i]
            local col = _PRIO_COLORS[key] or { 1, 1, 1 }
            -- Override colors from DB if available
            local gen = G()
            if key == "aggro" then
                col = { gen.hlAggroColorR or gen.aggroBorderColorR or col[1], gen.hlAggroColorG or gen.aggroBorderColorG or col[2], gen.hlAggroColorB or gen.aggroBorderColorB or col[3] }
            elseif key == "purge" then
                col = { gen.hlPurgeColorR or gen.purgeBorderColorR or col[1], gen.hlPurgeColorG or gen.purgeBorderColorG or col[2], gen.hlPurgeColorB or gen.purgeBorderColorB or col[3] }
            elseif key == "dispel" then
                col = { gen.hlDispelColorR or gen.dispelBorderColorR or col[1], gen.hlDispelColorG or gen.dispelBorderColorG or col[2], gen.hlDispelColorB or gen.dispelBorderColorB or col[3] }
            end
            _prioRows[i].key = key; _prioRows[i].slotIndex = i
            _prioRows[i].frame._stripe:SetColorTexture(col[1], col[2], col[3], 1)
            _prioRows[i].frame._label:SetText(TR(_PRIO_LABELS[key] or key))
            _prioRows[i].frame._numText:SetText(tostring(i))
        end
        _Prio_SnapAll()
    end
    _Prio_InitRows()
    _G.MSUF_PrioRows_Reinit = function() _Prio_InitRows(); _Prio_SetEnabled(HlGet("hlPrioEnabled", false) and true or false) end

    prioCheck:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        local db = HlDB()
        db.hlPrioEnabled = on
        if not IsCurrentScopeNonShared() then db.highlightPrioEnabled = on and 1 or 0 end
        _Prio_SetEnabled(on); _Prio_SaveOrder()
    end)
    do local on = HlGet("hlPrioEnabled", false); prioCheck:SetChecked(on); _Prio_SetEnabled(on) end

    -- BOX 5: HP / Power Text (default open)
    local box5, box5Body = MakeCollapsibleBox(barGroup, box3c, 240, "HP / Power Text", true)

    local hpModeOptions = {
        { key = "PERCENT",        label = "Percent"                  },
        { key = "CURRENT",        label = "Current"                  },
        { key = "MAX",            label = "Max"                      },
        { key = "DEFICIT",        label = "Deficit"                  },
        { key = "CURMAX",         label = "Current / Max"            },
        { key = "CURPERCENT",     label = "Current / Percent"        },
        { key = "CURMAXPERCENT",  label = "Current / Max / Percent"  },
        { key = "MAXPERCENT",     label = "Max / Percent"            },
        { key = "PERCENTCUR",     label = "Percent / Current"        },
        { key = "PERCENTMAX",     label = "Percent / Max"            },
        { key = "PERCENTCURMAX",  label = "Percent / Current / Max"  },
        { key = "NONE",           label = "None"                     },
    }
    local function NormHpMode(m)
        if type(_G.MSUF_NormalizeHpTextMode) == "function" then return _G.MSUF_NormalizeHpTextMode(m) end
        if m == nil then return "CURPERCENT" end
        if m == "FULL_ONLY" then return "CURRENT" end
        if m == "PERCENT_ONLY" then return "PERCENT" end
        if m == "FULL_PLUS_PERCENT" then return "CURPERCENT" end
        if m == "PERCENT_PLUS_FULL" then return "PERCENTCUR" end
        return m
    end
    local hpModeDrop = UI.Dropdown({
        name = "MSUF_HPTextModeDropdown", parent = box5Body,
        anchor = box5Body, anchorPoint = "TOPLEFT", x = 0, y = -6, width = 280,
        items = hpModeOptions,
        get = function() return NormHpMode(ScopeGet("hpTextMode", "FULL_PLUS_PERCENT")) end,
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

    -- Reverse order toggle
    local hpReverseCheck = CreateFrame("CheckButton", "MSUF_HPTextReverseCheck", box5Body, "UICheckButtonTemplate")
    hpReverseCheck:SetPoint("TOPLEFT", hpModeDrop, "BOTTOMLEFT", 14, -6)
    hpReverseCheck.text = _G["MSUF_HPTextReverseCheckText"]
    if hpReverseCheck.text then hpReverseCheck.text:SetText(TR("Reverse Order")); hpReverseCheck.text:SetTextColor(0.75, 0.75, 0.75) end
    UI.StyleCheckmark(hpReverseCheck)
    do
        local v = ScopeGet("hpTextReverse", false)
        hpReverseCheck:SetChecked(v and true or false)
    end
    hpReverseCheck:SetScript("OnClick", function(self)
        local val = self:GetChecked() and true or false
        ScopeSet("hpTextReverse", val, function()
            -- Invalidate text spec cache on all frames so EnsureSpec picks up new reverse
            if _G.MSUF_UnitFrames then
                for _, f in pairs(_G.MSUF_UnitFrames) do
                    if f then
                        f._msufTextSpec = nil
                        f._msufLastH = nil
                        f._msufLastPctS = nil
                        f._msufLastMaxS = nil
                    end
                end
            end
            local uk = _MSUF_HPText_GetUnitKey()
            if uk then ForceTextLayout(uk) else for _, k in ipairs(ALL_UNITS) do ForceTextLayout(k) end end
            RefreshFrames()
        end)
    end)

    -- Separators
    local textSepOptions = {
        { key = "", label = " " }, { key = "-", label = "-" }, { key = "/", label = "/" },
        { key = "\\", label = "\\" }, { key = "|", label = "|" }, { key = "<", label = "<" },
        { key = ">", label = ">" }, { key = "~", label = "~" },
        { key = "\194\183", label = "\194\183" }, { key = "\226\128\162", label = "\226\128\162" },
        { key = ":", label = ":" }, { key = "\194\187", label = "\194\187" }, { key = "\194\171", label = "\194\171" },
    }

    local hpSepLabel = box5Body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hpSepLabel:SetPoint("TOPLEFT", hpReverseCheck, "BOTTOMLEFT", 0, -10); hpSepLabel:SetText(TR("HP separator"))

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
                if u and u.hlOverride then
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

    -- BOX 6: Text Spacers (collapsible, default closed)
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
    local function _TextModeAllowsSpacer(m)
        local nm = m
        if type(_G.MSUF_NormalizeHpTextMode) == "function" then nm = _G.MSUF_NormalizeHpTextMode(m) end
        return (nm == "CURPERCENT" or nm == "PERCENTCUR"
            or nm == "CURMAXPERCENT" or nm == "MAXPERCENT"
            or nm == "PERCENTMAX" or nm == "PERCENTCURMAX"
            or nm == "PERCENTMAXCUR"
            or nm == "FULL_PLUS_PERCENT" or nm == "PERCENT_PLUS_FULL")
    end
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
        return (u0 and u0.hlOverride and u0[spec.modeKey]) or (g0 and g0[spec.modeKey]) or "FULL_PLUS_PERCENT"
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
        local unitOverride = not isShared and (u and u.hlOverride == true)
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
                local canEdit = isS or (db and db.hlOverride)
                if not canEdit or not _TextModeAllowsSpacer(_GetEffSpacerMode(uk2, spec, g2)) then _SyncSpacerControls(); return end
                (isS and g2 or db)[spec.enabledKey] = self:GetChecked() and true or false
                _SyncSpacerControls(); _RequestTextLayoutForScope(uk2, isS, "SPACER_TOGGLE")
            end)
        end
        if spec.slider then
            spec.slider.onValueChanged = function(self, value)
                EnsureDB(); local uk2, db, isS = _HPSpacer_GetDB(); local g2 = G()
                local canEdit = isS or (db and db.hlOverride)
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

    -- GF hint (shown when Party/Raid scope, replaces Box 5/6)
    local gfTextHint = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    gfTextHint:SetPoint("TOPLEFT", box3c, "BOTTOMLEFT", 14, -12)
    gfTextHint:SetWidth(600); gfTextHint:SetJustifyH("LEFT")
    gfTextHint:SetText(TR("HP / Power Text and Text Spacers for Group Frames are configured in\nGroup Frames > Health & Text."))
    gfTextHint:SetTextColor(0.6, 0.75, 1.0)
    gfTextHint:Hide()

    -- BOX 7: Bar Animation + Text Accuracy (collapsible, default closed)
    local box7, box7Body = MakeCollapsibleBox(barGroup, box6, 110, "Bar Animation + Text Accuracy", false)

    local smoothBarCheck = CreateFrame("CheckButton", "MSUF_SmoothPowerBarCheck", box7Body, "UICheckButtonTemplate")
    smoothBarCheck:SetPoint("TOPLEFT", box7Body, "TOPLEFT", 14, -6)
    smoothBarCheck.text = _G["MSUF_SmoothPowerBarCheckText"]; if smoothBarCheck.text then smoothBarCheck.text:SetText(TR("Smooth power bar")) end
    UI.StyleToggleText(smoothBarCheck); UI.StyleCheckmark(smoothBarCheck)
    do EnsureDB(); local v = B().smoothPowerBar; if v == nil then v = true end; smoothBarCheck:SetChecked(v) end
    smoothBarCheck:SetScript("OnClick", function(self) B().smoothPowerBar = self:GetChecked() and true or false
        if _G.MSUF_UFCore_RefreshSettingsCache then _G.MSUF_UFCore_RefreshSettingsCache("SMOOTH_POWER") end end)

    local smoothHint = box7Body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    smoothHint:SetPoint("TOPLEFT", smoothBarCheck, "BOTTOMLEFT", 0, -1)
    smoothHint:SetText(TR("C-side interpolation for fluid bar movement")); smoothHint:SetTextColor(0.45, 0.45, 0.45)

    local rtTextCheck = CreateFrame("CheckButton", "MSUF_RealtimePowerTextCheck", box7Body, "UICheckButtonTemplate")
    rtTextCheck:SetPoint("TOPLEFT", smoothHint, "BOTTOMLEFT", 0, -6)
    rtTextCheck.text = _G["MSUF_RealtimePowerTextCheckText"]; if rtTextCheck.text then rtTextCheck.text:SetText(TR("Real-time power text")) end
    UI.StyleToggleText(rtTextCheck); UI.StyleCheckmark(rtTextCheck)
    do EnsureDB(); local v = B().realtimePowerText; if v == nil then v = true end; rtTextCheck:SetChecked(v) end
    rtTextCheck:SetScript("OnClick", function(self) B().realtimePowerText = self:GetChecked() and true or false
        if _G.MSUF_UFCore_RefreshSettingsCache then _G.MSUF_UFCore_RefreshSettingsCache("REALTIME_TEXT") end end)

    -- Collect label/control refs into table to stay under 60-upvalue limit
    local _C = {
        texColLabel = texColLabel, barBgTexLabel = barBgTexLabel, gradColLabel = gradColLabel,
        absorbModeLabel = absorbModeLabel, absorbTextureLabel = absorbTextureLabel, healAbsorbLabel = healAbsorbLabel,
        hlSectionLabel = hlSectionLabel,
        barTextureDrop = barTextureDrop, barBgTextureDrop = barBgTextureDrop,
        absorbDisplayDrop = absorbDisplayDrop, absorbAnchorDrop = absorbAnchorDrop,
        absorbOpacitySlider = absorbOpacitySlider, healAbsorbOpacitySlider = healAbsorbOpacitySlider,
        selfHealPredCB = selfHealPredCB,
        aggroOutlineDrop = aggroOutlineDrop, dispelOutlineDrop = dispelOutlineDrop,
        dispelGlowStyleDrop = dispelGlowStyleDrop,
        dispelGlowCheck = dispelGlowCheck,
        dispelGlowLinesSlider = dispelGlowLinesSlider, dispelGlowFreqSlider = dispelGlowFreqSlider,
        dispelGlowThickSlider = dispelGlowThickSlider,
        purgeOutlineDrop = purgeOutlineDrop,
        highlightBorderThicknessSlider = highlightBorderThicknessSlider,
        gradientStrengthSlider = gradientStrengthSlider,
        hpModeDrop = hpModeDrop, powerModeDrop = powerModeDrop,
        hpSepDrop = hpSepDrop, powerSepDrop = powerSepDrop,
        hpReverseCheck = hpReverseCheck,
        hpPowerOverrideCheck = hpPowerOverrideCheck,
        scopeOverrideInfo = scopeOverrideInfo, scopeResetBtn = scopeResetBtn,
        box1 = box1, box2 = box2, box3a = box3a, box3b = box3b, box3c = box3c,
        box5 = box5, box6 = box6, box7 = box7, gfTextHint = gfTextHint,
    }

    -- Scope UI Sync (_MSUF_SyncHpPowerTextScopeUI)
    _MSUF_SyncHpPowerTextScopeUI = function()
        EnsureDB(); local uk = _MSUF_HPText_GetUnitKey()
        local scopeKey = _MSUF_HPText_GetScopeKey()
        local isGF = IsGFScope(scopeKey)

        -- Scope buttons
        RefreshScopeButtons()

        -- Override checkbox
        if _C.hpPowerOverrideCheck then
            if scopeKey ~= "shared" then
                _C.hpPowerOverrideCheck:Show(); _C.hpPowerOverrideCheck:Enable(); _C.hpPowerOverrideCheck:SetAlpha(1)
                if isGF then
                    local gfKey = GetGFDBKey(scopeKey)
                    local gf = MSUF_DB[gfKey]
                    _C.hpPowerOverrideCheck:SetChecked(gf and gf.hlOverride == true)
                else
                    local u = uk and _MSUF_HPText_GetUnitDB(uk)
                    _C.hpPowerOverrideCheck:SetChecked(u and u.hlOverride == true)
                end
            else _C.hpPowerOverrideCheck:Hide() end
        end

        -- Reset button + override summary
        if _C.scopeResetBtn then
            if scopeKey ~= "shared" then
                _C.scopeResetBtn:Hide()
                _C.scopeOverrideInfo:Hide()
            else
                local active = {}
                for _, uK in ipairs(ALL_UNITS) do
                    local u = MSUF_DB[uK]
                    if u and u.hlOverride then active[#active + 1] = _NiceUnitKey(uK) end
                end
                for scopeName, gfKey in pairs(GF_SCOPE_KEYS) do
                    local gf = MSUF_DB[gfKey]
                    if gf and gf.hlOverride then active[#active + 1] = SCOPE_LABELS[scopeName] or scopeName end
                end
                if #active > 0 then
                    _C.scopeOverrideInfo:SetText("|cffffffffOverrides:|r " .. table.concat(active, ", "))
                    _C.scopeOverrideInfo:SetFontObject(GameFontHighlightSmall)
                    _C.scopeOverrideInfo:Show()
                    _C.scopeResetBtn:Show(); _C.scopeResetBtn:Enable(); _C.scopeResetBtn:SetAlpha(1)
                else
                    _C.scopeOverrideInfo:SetText("|cff9aa0a6No unit overrides active.|r")
                    _C.scopeOverrideInfo:SetFontObject(GameFontDisableSmall)
                    _C.scopeOverrideInfo:Show()
                    _C.scopeResetBtn:Show(); _C.scopeResetBtn:Disable(); _C.scopeResetBtn:SetAlpha(0.45)
                end
            end
        end

        -- Box 5/6: HP / Power Text — hide for GF scopes, show hint instead
        if _C.box5 then _C.box5:SetShown(not isGF) end
        if _C.box6 then _C.box6:SetShown(not isGF) end
        if _C.gfTextHint then _C.gfTextHint:SetShown(isGF) end
        -- Re-anchor box7 when box5/6 are hidden
        if _C.box7 then
            _C.box7:ClearAllPoints()
            if isGF then
                _C.box7:SetPoint("TOPLEFT", _C.gfTextHint or _C.box3c, "BOTTOMLEFT", 0, -12)
            else
                _C.box7:SetPoint("TOPLEFT", _C.box6, "BOTTOMLEFT", 0, -4)
            end
        end

        -- Refresh scope-aware text dropdowns (non-GF only)
        if not isGF then
            if _C.hpModeDrop and _C.hpModeDrop.Refresh then _C.hpModeDrop:Refresh() end
            if _C.hpReverseCheck then _C.hpReverseCheck:SetChecked(ScopeGet("hpTextReverse", false) and true or false) end
            if _C.powerModeDrop and _C.powerModeDrop.Refresh then _C.powerModeDrop:Refresh() end
            if _C.hpSepDrop and _C.hpSepDrop.Refresh then _C.hpSepDrop:Refresh() end
            if _C.powerSepDrop and _C.powerSepDrop.Refresh then _C.powerSepDrop:Refresh() end
            if _C.selfHealPredCB then _C.selfHealPredCB:SetChecked(ScopeGet("showSelfHealPrediction", false) and true or false) end
            _SyncSpacerControls()
        end

        -- Absorb controls: scope-aware, refresh for ALL scopes
        if _C.absorbDisplayDrop and _C.absorbDisplayDrop.Refresh then _C.absorbDisplayDrop:Refresh() end
        if _C.absorbAnchorDrop and _C.absorbAnchorDrop.Refresh then _C.absorbAnchorDrop:Refresh() end
        if _C.absorbOpacitySlider then local v = tonumber(ScopeGet("absorbBarOpacity", 1)); if v < 0 then v = 0 elseif v > 1 then v = 1 end; MSUF_SetLabeledSliderValue(_C.absorbOpacitySlider, v) end
        if _C.healAbsorbOpacitySlider then local v = tonumber(ScopeGet("healAbsorbBarOpacity", 1)); if v < 0 then v = 0 elseif v > 1 then v = 1 end; MSUF_SetLabeledSliderValue(_C.healAbsorbOpacitySlider, v) end
        if absorbTexTestCB then absorbTexTestCB:SetChecked(_G.MSUF_AbsorbTextureTestMode and true or false) end
        if MSUF_RefreshAbsorbBarUIEnabled then MSUF_RefreshAbsorbBarUIEnabled() end

        -- Highlight slider sync (scope-aware)
        if _C.barOutlineThicknessSlider then
            local t = floor((tonumber(ScopeGetBars("barOutlineThickness", tonumber(B().barOutlineThickness) or 1)) or 1) + 0.5)
            if t < 0 then t = 0 elseif t > 6 then t = 6 end
            MSUF_SetLabeledSliderValue(_C.barOutlineThicknessSlider, t)
        end

        if _C.highlightBorderThicknessSlider then
            local v = tonumber(HlGet("hlAggroSize", nil)) or tonumber(G().highlightBorderThickness) or 2
            v = floor(v + 0.5); if v < 1 then v = 1 elseif v > 30 then v = 30 end
            MSUF_SetLabeledSliderValue(_C.highlightBorderThicknessSlider, v)
        end

        -- Glow controls sync
        if _C.dispelGlowCheck then _C.dispelGlowCheck:SetChecked(HlGet("hlDispelGlowEnabled", false) and true or false) end
        if _C.dispelGlowStyleDrop and _C.dispelGlowStyleDrop.Refresh then _C.dispelGlowStyleDrop:Refresh() end
        if _C.dispelGlowLinesSlider then MSUF_SetLabeledSliderValue(_C.dispelGlowLinesSlider, tonumber(HlGet("hlDispelGlowLines", 8)) or 8) end
        if _C.dispelGlowFreqSlider then MSUF_SetLabeledSliderValue(_C.dispelGlowFreqSlider, tonumber(HlGet("hlDispelGlowFrequency", 0.25)) or 0.25) end
        if _C.dispelGlowThickSlider then MSUF_SetLabeledSliderValue(_C.dispelGlowThickSlider, tonumber(HlGet("hlDispelGlowThickness", 2)) or 2) end

        -- Scope dimming
        local isNonShared = (uk ~= nil) or isGF
        local hlOverrideOn = IsCurrentScopeOverrideActive()
        local hlControlsActive = (not isNonShared) or hlOverrideOn  -- highlight controls active when shared OR override on
        local function DimDrop(n, lbl) MSUF_SetDropDownEnabled(_G[n], lbl, not isNonShared) end
        local function DimCheck(n)
            local cb = _G[n]; if not cb then return end
            MSUF_SetCheckboxEnabled(cb, not isNonShared)
            if cb.EnableMouse then pcall(cb.EnableMouse, cb, not isNonShared) end
        end
        local function DimSlider(n) MSUF_SetLabeledSliderEnabled(_G[n], not isNonShared) end
        local function DimFrame(n) local f = _G[n]; if not f then return end
            f:SetAlpha(isNonShared and 0.35 or 1)
            if not isNonShared then if f.Enable then pcall(f.Enable, f) end else if f.Disable then pcall(f.Disable, f) end end
            if f.EnableMouse then pcall(f.EnableMouse, f, not isNonShared) end end
        local function DimLabel(fs) if not fs then return end
            if fs.SetTextColor then fs:SetTextColor(isNonShared and 0.35 or 1, isNonShared and 0.35 or 1, isNonShared and 0.35 or 1)
            elseif fs.SetAlpha then fs:SetAlpha(isNonShared and 0.35 or 1) end end
        -- Highlight-specific dim helpers
        local function HlDimDrop(n, lbl) MSUF_SetDropDownEnabled(_G[n], lbl, hlControlsActive) end
        local function HlDimCheck(n)
            local cb = _G[n]; if not cb then return end
            MSUF_SetCheckboxEnabled(cb, hlControlsActive)
            if cb.EnableMouse then pcall(cb.EnableMouse, cb, hlControlsActive) end
        end
        local function HlDimSlider(n) MSUF_SetLabeledSliderEnabled(_G[n], hlControlsActive) end
        local function HlDimFrame(n) local f = _G[n]; if not f then return end
            f:SetAlpha(hlControlsActive and 1 or 0.35)
            if hlControlsActive then if f.Enable then pcall(f.Enable, f) end else if f.Disable then pcall(f.Disable, f) end end
            if f.EnableMouse then pcall(f.EnableMouse, f, hlControlsActive) end end

        -- Box 1 dims (textures + gradient) — scope-aware
        HlDimDrop("MSUF_BarTextureDropdown"); HlDimDrop("MSUF_BarBackgroundTextureDropdown")
        if _C.texColLabel then DimLabel(_C.texColLabel) end; if _C.barBgTexLabel then DimLabel(_C.barBgTexLabel) end
        HlDimCheck("MSUF_GradientEnableCheck"); HlDimCheck("MSUF_PowerGradientEnableCheck")
        HlDimSlider("MSUF_GradientStrengthSlider"); HlDimFrame("MSUF_GradientDirectionPad")
        if _C.gradColLabel then DimLabel(_C.gradColLabel) end

        -- Box 2 dims (absorb display) — scope-aware
        HlDimDrop("MSUF_AbsorbDisplayDrop"); HlDimDrop("MSUF_AbsorbAnchorDrop")
        HlDimDrop("MSUF_AbsorbBarTextureDropdown"); HlDimDrop("MSUF_HealAbsorbBarTextureDropdown")
        HlDimCheck("MSUF_AbsorbTextureTestModeCheck"); HlDimCheck("MSUF_SelfHealPredictionCheck")
        HlDimSlider("MSUF_AbsorbBarOpacitySlider"); HlDimSlider("MSUF_HealAbsorbBarOpacitySlider")
        if _C.absorbTextureLabel then DimLabel(_C.absorbTextureLabel) end
        if _C.healAbsorbLabel then DimLabel(_C.healAbsorbLabel) end
        if _C.absorbModeLabel then DimLabel(_C.absorbModeLabel) end

        -- Box 3: all controls follow hlControlsActive
        HlDimSlider("MSUF_BarOutlineThicknessSlider")
        HlDimSlider("MSUF_HighlightBorderThicknessSlider")
        HlDimDrop("MSUF_AggroOutlineDropdown"); HlDimCheck("MSUF_AggroOutlineTestCheck")
        HlDimDrop("MSUF_DispelOutlineDropdown"); HlDimCheck("MSUF_DispelOutlineTestCheck")
        HlDimDrop("MSUF_DispelColorModeDropdown")
        HlDimCheck("MSUF_DispelGlowCheck")
        HlDimDrop("MSUF_DispelGlowStyleDropdown")
        HlDimSlider("MSUF_DispelGlowLinesSlider")
        HlDimSlider("MSUF_DispelGlowFreqSlider")
        HlDimSlider("MSUF_DispelGlowThickSlider")
        HlDimDrop("MSUF_PurgeOutlineDropdown"); HlDimCheck("MSUF_PurgeOutlineTestCheck")
        HlDimCheck("MSUF_HighlightPrioCheck"); HlDimFrame("MSUF_HighlightPrioContainer")
        if _C.hlSectionLabel then
            if hlControlsActive then _C.hlSectionLabel:SetTextColor(1, 1, 1) else _C.hlSectionLabel:SetTextColor(0.35, 0.35, 0.35) end
        end
        -- Refresh dropdowns when scope changes
        -- Box 1
        if _C.barTextureDrop and _C.barTextureDrop.Refresh then _C.barTextureDrop:Refresh() end
        if _C.barBgTextureDrop and _C.barBgTextureDrop.Refresh then _C.barBgTextureDrop:Refresh() end
        -- Box 2
        if _C.selfHealPredCB then _C.selfHealPredCB:SetChecked(ScopeGet("showSelfHealPrediction", false) and true or false) end
        -- Box 3
        if _C.aggroOutlineDrop and _C.aggroOutlineDrop.Refresh then _C.aggroOutlineDrop:Refresh() end
        if _C.dispelOutlineDrop and _C.dispelOutlineDrop.Refresh then _C.dispelOutlineDrop:Refresh() end
        if _C.dispelGlowStyleDrop and _C.dispelGlowStyleDrop.Refresh then _C.dispelGlowStyleDrop:Refresh() end
        if _C.purgeOutlineDrop and _C.purgeOutlineDrop.Refresh then _C.purgeOutlineDrop:Refresh() end
        if _G.MSUF_PrioRows_Reinit then _G.MSUF_PrioRows_Reinit() end

        -- Box titles dim
        local function TitleDim(box)
            if not box or not box._msufTitle then return end
            if hlControlsActive then box._msufTitle:SetTextColor(1, 1, 1) else DimLabel(box._msufTitle) end
        end
        TitleDim(_C.box1); TitleDim(_C.box2); TitleDim(_C.box3a); TitleDim(_C.box3b); TitleDim(_C.box3c)

        -- Re-trigger active test modes with current scope (prevents scope bleed)
        if _G.MSUF_DispelBorderTestMode and _G.MSUF_SetDispelBorderTestMode then
            _G.MSUF_SetDispelBorderTestMode(true, scopeKey)
        end
        if _G.MSUF_AggroBorderTestMode and _G.MSUF_SetAggroBorderTestMode then
            _G.MSUF_SetAggroBorderTestMode(true, scopeKey)
        end
    end

    _Scope_SyncUI = _MSUF_SyncHpPowerTextScopeUI
    _MSUF_SyncHpPowerTextScopeUI()

    -- MSUF_BarsApplyGradient (live gradient apply)
    local MSUF_BarsApplyGradient
    MSUF_BarsApplyGradient = function()
        EnsureDB(); local g = G()
        if (g.enableGradient ~= false) or (g.enablePowerGradient ~= false) then
            if not (tonumber(g.gradientStrength) and tonumber(g.gradientStrength) > 0) then g.gradientStrength = 0.45 end
        end
        if gradientDirPad and gradientDirPad.SyncFromDB then gradientDirPad:SyncFromDB() end
        if InCombatLockdown and InCombatLockdown() then Apply()
        elseif _G.MSUF_ApplyAllSettings_Immediate then _G.MSUF_ApplyAllSettings_Immediate()
        else Apply() end
        local function Repaint()
            local frames = _G.MSUF_UnitFrames; if type(frames) ~= "table" then RefreshFrames(); return end
            for _, f in pairs(frames) do if f and f.unit and f.hpBar then
                f._msufHeavyVisualNextAt = 0
                if _G.UpdateSimpleUnitFrame then _G.UpdateSimpleUnitFrame(f) end
                if _G.MSUF_UFCore_UpdatePowerBarFast then _G.MSUF_UFCore_UpdatePowerBarFast(f) end
            end end
        end
        Repaint()
        if C_Timer then C_Timer.After(0.08, Repaint) end
        -- Refresh GF gradient overlays
        local GF = _G.MSUF_NS and _G.MSUF_NS.GF
        if GF and GF.MarkAllDirty then GF.MarkAllDirty(GF.DIRTY_TEXTURE or 0x02) end
    end

    -- SyncAll (called on OnShow)
    local function SyncAll()
        EnsureDB(); local g = G(); local b = B()
        -- Ensure hlAggroSize exists in general (migrate from legacy key)
        if g.hlAggroSize == nil and g.highlightBorderThickness ~= nil then g.hlAggroSize = g.highlightBorderThickness end
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
        if barOutlineThicknessSlider then local t = floor((tonumber(ScopeGetBars("barOutlineThickness", tonumber(b.barOutlineThickness) or 1)) or 1) + 0.5); if t < 0 then t = 0 elseif t > 6 then t = 6 end; MSUF_SetLabeledSliderValue(barOutlineThicknessSlider, t) end
        if highlightBorderThicknessSlider then local t = tonumber(HlGet("hlAggroSize", nil)) or tonumber(G().highlightBorderThickness) or 2; t = floor(t + 0.5); if t < 1 then t = 1 elseif t > 30 then t = 30 end; MSUF_SetLabeledSliderValue(highlightBorderThicknessSlider, t) end
        if _G.MSUF_PrioRows_Reinit then _G.MSUF_PrioRows_Reinit() end
        local function SC(cb, v) if cb then cb:SetChecked(v and true or false); if cb.__msufToggleUpdate then cb.__msufToggleUpdate() end end end
        SC(absorbTexTestCB, _G.MSUF_AbsorbTextureTestMode)
        SC(_C.selfHealPredCB, ScopeGet("showSelfHealPrediction", false))
        local smoothCB = _G["MSUF_SmoothPowerBarCheck"]; if smoothCB then local v = b.smoothPowerBar; if v == nil then v = true end; smoothCB:SetChecked(v) end
        local rtCB = _G["MSUF_RealtimePowerTextCheck"]; if rtCB then local v = b.realtimePowerText; if v == nil then v = true end; rtCB:SetChecked(v) end
        _MSUF_SyncHpPowerTextScopeUI()
        MSUF_BarsMenu_QueueScrollUpdate()
    end
    SyncAll()
    if barGroup.HookScript then barGroup:HookScript("OnShow", SyncAll) end

    -- GF party/raid preview: show when Bars menu opens so highlight borders are visible on group frames
    local _barsGFPreviewOn = false
    local _barsGFPreviewKind = nil
    local function _BarsShowGFPreview(kind)
        local GF = _G.MSUF_NS and _G.MSUF_NS.GF
        if not GF or not GF.ShowPreview then return end
        -- Don't override if GF Options already has a preview active
        if GF._previewActive and (GF._previewActive.party or GF._previewActive.raid) and not _barsGFPreviewOn then return end
        -- Only need preview when solo (real frames exist otherwise)
        if kind == "raid" then
            if IsInRaid and IsInRaid() then return end
        else
            kind = "party"
            if IsInGroup and IsInGroup() then return end
        end
        -- Hide previous if switching kind
        if _barsGFPreviewKind and _barsGFPreviewKind ~= kind and GF.HidePreview then
            GF.HidePreview(_barsGFPreviewKind)
        end
        if not InCombatLockdown() and GF.headers then
            if GF.headers.party then GF.headers.party:Hide() end
            if GF.headers.raid  then GF.headers.raid:Hide()  end
        end
        GF.ShowPreview(kind, kind == "raid" and 30 or 4)
        _barsGFPreviewKind = kind
        _barsGFPreviewOn = true
    end
    barGroup:HookScript("OnShow", function()
        local scopeKey = _MSUF_HPText_GetScopeKey and _MSUF_HPText_GetScopeKey() or "shared"
        if scopeKey == "party" or scopeKey == "raid" then
            _BarsShowGFPreview(scopeKey)
        else
            _BarsShowGFPreview("party")
        end
    end)
    barGroup:HookScript("OnHide", function()
        if not _barsGFPreviewOn then return end
        _barsGFPreviewOn = false
        local GF = _G.MSUF_NS and _G.MSUF_NS.GF
        if not GF then return end
        if _barsGFPreviewKind and GF.HidePreview then GF.HidePreview(_barsGFPreviewKind) end
        _barsGFPreviewKind = nil
        if not InCombatLockdown() and GF.UpdateGroupVisibility then GF.UpdateGroupVisibility() end
    end)

    -- DB bindings
    if _G.MSUF_Options_BindDBBoolCheck then
        _G.MSUF_Options_BindDBBoolCheck(gradientCheck, "general.enableGradient", MSUF_BarsApplyGradient, SyncAll)
        _G.MSUF_Options_BindDBBoolCheck(powerGradientCheck, "general.enablePowerGradient", MSUF_BarsApplyGradient, SyncAll)
        local function Bind(cb, path, apply) if cb then _G.MSUF_Options_BindDBBoolCheck(cb, path, apply or Apply, SyncAll) end end
    end
    if gradientStrengthSlider then
        gradientStrengthSlider.onValueChanged = function(_, v) ScopeSet("gradientStrength", v, MSUF_BarsApplyGradient) end
    end

    -- Panel stores (Core compat)
    panel.gradientCheck = gradientCheck; panel.powerGradientCheck = powerGradientCheck
    panel.gradientDirPad = gradientDirPad or _G["MSUF_GradientDirectionPad"]
    panel.hpModeDrop = hpModeDrop; panel.barTextureDrop = barTextureDrop
    panel.barOutlineThicknessSlider = barOutlineThicknessSlider
    panel.highlightBorderThicknessSlider = highlightBorderThicknessSlider
    panel.aggroOutlineDrop = aggroOutlineDrop; panel.aggroTestCheck = aggroTestCheck
    panel.dispelOutlineDrop = dispelOutlineDrop; panel.dispelTestCheck = dispelTestCheck
    panel.dispelTestTypeDrop = dispelTestTypeDrop
    panel.purgeOutlineDrop = purgeOutlineDrop; panel.purgeTestCheck = purgeTestCheck
    panel.bossTargetOutlineDrop = bossTargetOutlineDrop; panel.bossTargetTestCheck = bossTargetTestCheck
    panel.prioCheck = prioCheck
    if type(MSUF_BarsApplyGradient) == "function" then _G.MSUF_BarsApplyGradient = MSUF_BarsApplyGradient end

    -- GF preview: show party/raid preview while Bars menu is visible (same logic as GF Options)
    if barGroupHost and barGroupHost.HookScript then
        barGroupHost:HookScript("OnShow", function()
            local GF = _G.MSUF_NS and _G.MSUF_NS.GF
            if not GF or not GF.ShowPreview then return end
            local inGroup = IsInGroup and IsInGroup()
            local inRaid  = IsInRaid  and IsInRaid()
            if inRaid then
                -- In raid: show raid preview
                GF.ShowPreview("raid", 30)
            elseif inGroup then
                -- In party: real frames visible, no preview needed
            else
                -- Solo: show party preview
                if not InCombatLockdown() and GF.headers then
                    if GF.headers.party then GF.headers.party:Hide() end
                    if GF.headers.raid  then GF.headers.raid:Hide()  end
                end
                GF.ShowPreview("party", 4)
            end
        end)
        barGroupHost:HookScript("OnHide", function()
            local GF = _G.MSUF_NS and _G.MSUF_NS.GF
            if not GF or not GF.HidePreview then return end
            GF.HidePreview("party")
            GF.HidePreview("raid")
            if not InCombatLockdown() and GF.UpdateGroupVisibility then
                GF.UpdateGroupVisibility()
            end
        end)
    end
end
