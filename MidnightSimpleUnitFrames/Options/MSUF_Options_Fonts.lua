-- ---------------------------------------------------------------------------
-- MSUF_Options_Fonts.lua  (Phase 7: Per-unit scope system — Bars/Portraits pattern)
--
-- Font settings: global font, text style, name colors, name display.
-- Scope bar: Shared + per-unit overrides (fontOverride flag).
-- ---------------------------------------------------------------------------
local addonName, ns = ...
local TR = ns.TR
local UI = ns.UI
local EnsureDB = ns.EnsureDB
local floor = math.floor
local CreateFrame = CreateFrame

function ns.MSUF_Options_Fonts_Build(panel, fontGroup)
    if not panel or not fontGroup then return end
    if fontGroup._msufBuilt then return end
    fontGroup._msufBuilt = true

    if _G.MSUF_Search_RegisterRoots then
        _G.MSUF_Search_RegisterRoots({ "fonts" }, { "MSUF_FontsScrollChild" }, "Fonts")
    end

    local function G() EnsureDB(); return MSUF_DB.general end
    local function U(k) EnsureDB(); MSUF_DB[k] = MSUF_DB[k] or {}; return MSUF_DB[k] end

    local RequestLayoutAll
    local function UpdateFonts()
        local fn = _G.MSUF_UpdateAllFonts_Immediate or _G.MSUF_UpdateAllFonts or _G.UpdateAllFonts or (ns and ns.MSUF_UpdateAllFonts)
        if type(fn) == "function" then fn() end
    end
    local function LiveSyncFontVisuals(opts)
        opts = opts or {}
        UpdateFonts()
        if opts.layout then RequestLayoutAll(opts.layout) end
        local refreshIdentity = opts.refreshIdentity
        if refreshIdentity == nil then refreshIdentity = true end
        if refreshIdentity and type(_G.MSUF_RefreshAllIdentityColors) == "function" then
            _G.MSUF_RefreshAllIdentityColors()
        end
        local refreshPower = opts.refreshPower
        if refreshPower == nil then refreshPower = true end
        if refreshPower and type(_G.MSUF_RefreshAllPowerTextColors) == "function" then
            _G.MSUF_RefreshAllPowerTextColors()
        end
        local refreshFrames = opts.refreshFrames
        if refreshFrames == nil then refreshFrames = true end
        if refreshFrames then
            if ns and type(ns.MSUF_RefreshAllFrames) == "function" then
                ns.MSUF_RefreshAllFrames()
            elseif type(_G.MSUF_RefreshAllFrames) == "function" then
                _G.MSUF_RefreshAllFrames()
            end
        end
        -- Live-apply to Group Frames (shared settings propagate)
        local gf = ns and ns.GF
        if gf then
            if type(gf.RefreshFonts) == "function" then gf.RefreshFonts() end
            if type(gf.MarkAllDirty) == "function" then gf.MarkAllDirty((gf.DIRTY_FONT or 4) + (gf.DIRTY_LAYOUT or 32)) end
        end
    end
    RequestLayoutAll = function(reason)
        local fn = ns.MSUF_Options_RequestLayoutAll or _G.MSUF_Options_RequestLayoutAll
        if type(fn) == "function" then fn(reason); return end
        if type(_G.ApplyAllSettings) == "function" then pcall(_G.ApplyAllSettings) end
    end
    local TEX_W8 = "Interface\\Buttons\\WHITE8x8"
    local CONTENT_W = 650
    local ALL_UNITS = { "player", "target", "targettarget", "focus", "pet", "boss" }
    local GF_SCOPE_DB_KEYS = {
        gf_party = { "gf_party" },
        gf_raid = { "gf_raid", "gf_mythicraid" },
    }
    local function ClearUFFontKeyOverrides()
        EnsureDB()
        for _, k in ipairs(ALL_UNITS) do
            local u = MSUF_DB[k]
            if type(u) == "table" then
                u.fontKey = nil
            end
        end
    end

    local FONT_OVERRIDE_KEYS = {
        "boldText", "noOutline", "textBackdrop",
        "nameClassColor", "npcNameRed", "colorPowerTextByType",
        "shortenNameMaxChars", "shortenNameClipSide", "shortenNameShowDots",
    }

    -- =====================================================================
    -- Scope system (Bars / Portraits pattern)
    -- =====================================================================
    local function GetScopeKey() return G()._fontScopeKey or "shared" end
    local function GetUnitKey()
        local k = GetScopeKey()
        if k == "shared" then return nil end
        return k
    end
    local function IsOverride(uk)
        local keys = GF_SCOPE_DB_KEYS[uk]
        if keys then
            EnsureDB()
            for i = 1, #keys do
                local u = MSUF_DB[keys[i]]
                if u and u.fontOverride == true then return true end
            end
            return false
        end
        return U(uk).fontOverride == true
    end

    local function ForEachScopeDB(uk, fn)
        local keys = GF_SCOPE_DB_KEYS[uk]
        if not keys then return false end
        for i = 1, #keys do
            fn(U(keys[i]), keys[i])
        end
        return true
    end

    local function EnableOverride(uk)
        if ForEachScopeDB(uk, function(u) u.fontOverride = true end) then return end
        local u = U(uk); local g = G()
        u.fontOverride = true
        for _, k in ipairs(FONT_OVERRIDE_KEYS) do
            if u[k] == nil then u[k] = g[k] end
        end
        if u.shortenNames == nil then
            u.shortenNames = MSUF_DB.shortenNames
        end
    end

    local function ScopeGet(key, def, rootKey)
        local uk = GetUnitKey()
        if uk and IsOverride(uk) then
            local v
            local keys = GF_SCOPE_DB_KEYS[uk]
            if keys then
                for i = 1, #keys do
                    local u = U(keys[i])
                    v = rootKey and u[rootKey] or u[key]
                    if v ~= nil then return v end
                end
            else
                if rootKey then
                    v = U(uk)[rootKey]
                else
                    v = U(uk)[key]
                end
            end
            if v ~= nil then return v end
        end
        if rootKey then
            local rv = MSUF_DB[rootKey]
            if rv ~= nil then return rv end
            return def
        end
        local v = G()[key]
        if v ~= nil then return v end
        return def
    end

    local function ScopeSet(key, val, rootKey)
        local uk = GetUnitKey()
        if uk then
            local keys = GF_SCOPE_DB_KEYS[uk]
            if keys then
                ForEachScopeDB(uk, function(u)
                    if not u.fontOverride then u.fontOverride = true end
                    if rootKey then
                        u[rootKey] = val
                    else
                        u[key] = val
                    end
                end)
            else
                if not IsOverride(uk) then EnableOverride(uk) end
                if rootKey then
                    U(uk)[rootKey] = val
                else
                    U(uk)[key] = val
                end
            end
        else
            if rootKey then
                MSUF_DB[rootKey] = val
            else
                G()[key] = val
            end
        end
    end

    local SyncScopeUI

    local function InvalidateTextSpecs()
        local frames = _G.MSUF_UnitFrames
        if type(frames) ~= "table" then return end
        for _, f in pairs(frames) do
            if f then
                f._msufTextSpec = nil
                f._msufPwrTextConf = nil
                f._msufPTColorType = nil
                f._msufPTColorByPower = nil
                f._msufClampStamp = nil
                f._msufNameClipAnchorStamp = nil
                f._msufNameClipTextStamp = nil
                f._msufFontOverrideStamp = nil
            end
        end
    end

    -- =====================================================================
    -- Box helpers (A2/Bars pattern)
    -- =====================================================================
    local function MakeBox(parent, w, h)
        local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(w, h)
        f:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        f:SetBackdropColor(0, 0, 0, 0.35)
        f:SetBackdropBorderColor(1, 1, 1, 0.08)
        return f
    end

    local _allCollapsibles = {}
    local MSUF_Fonts_UpdateContentHeight

    local function MakeCollapsibleBox(parent, anchorTo, w, expandedH, titleText, defaultOpen)
        local box = MakeBox(parent, w, defaultOpen and expandedH or 28)
        box:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -6)
        box._msufExpandedH = expandedH
        box._msufCollapsed = not defaultOpen
        local hdr = CreateFrame("Button", nil, box)
        hdr:SetHeight(24)
        hdr:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
        hdr:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
        local chevron = hdr:CreateTexture(nil, "OVERLAY")
        chevron:SetSize(12, 12)
        chevron:SetPoint("LEFT", hdr, "LEFT", 12, 0)
        chevron:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        MSUF_ApplyCollapseVisual(chevron, nil, defaultOpen)
        local title = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("LEFT", chevron, "RIGHT", 6, 0)
        title:SetText(titleText)
        box._msufTitle = title
        local hint = hdr:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("RIGHT", hdr, "RIGHT", -12, 0)
        hint:SetText(defaultOpen and "" or "click to expand")
        hint:SetTextColor(0.45, 0.52, 0.65)
        local bodyHost = CreateFrame("Frame", nil, box)
        bodyHost:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -28)
        bodyHost:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
        bodyHost:SetShown(defaultOpen)
        if bodyHost.SetFrameLevel and box.GetFrameLevel then
            bodyHost:SetFrameLevel((box:GetFrameLevel() or 0) + 5)
        end
        box._msufBody = bodyHost
        hdr:SetScript("OnClick", function()
            box._msufCollapsed = not box._msufCollapsed
            bodyHost:SetShown(not box._msufCollapsed)
            if box._msufCollapsed then
                box:SetHeight(28)
                MSUF_ApplyCollapseVisual(chevron, hint, false)
            else
                box:SetHeight(box._msufExpandedH)
                MSUF_ApplyCollapseVisual(chevron, hint, true)
            end
            if MSUF_Fonts_UpdateContentHeight then pcall(MSUF_Fonts_UpdateContentHeight) end
        end)
        do
            local hl = hdr:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.03)
        end
        _allCollapsibles[#_allCollapsibles + 1] = box
        return box, bodyHost
    end

    -- =====================================================================
    -- SCOPE BAR (A2-style button strip — above scroll area)
    -- =====================================================================
    local SCOPE_KEYS = { "shared", "player", "target", "targettarget", "focus", "pet", "boss", "gf_party", "gf_raid" }
    local SCOPE_LABELS = {
        shared = "Shared", player = "Player", target = "Target",
        targettarget = "ToT", focus = "Focus", pet = "Pet", boss = "Boss",
        gf_party = "Party", gf_raid = "Raid",
    }

    local scopeBar = CreateFrame("Frame", nil, fontGroup, BackdropTemplateMixin and "BackdropTemplate" or nil)
    scopeBar:SetHeight(72); scopeBar:SetWidth(CONTENT_W)
    scopeBar:SetPoint("TOPLEFT", fontGroup, "TOPLEFT", 0, -110)
    scopeBar:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    scopeBar:SetBackdropColor(0.04, 0.08, 0.18, 0.95)
    scopeBar:SetBackdropBorderColor(0.12, 0.25, 0.50, 0.6)

    local scopeEditLbl = scopeBar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    scopeEditLbl:SetPoint("TOPLEFT", scopeBar, "TOPLEFT", 10, -10)
    scopeEditLbl:SetText(TR("Editing:"))

    local scopeBtns = {}
    local function RefreshScopeButtons()
        local activeKey = GetScopeKey()
        for k, btn in pairs(scopeBtns) do
            if btn and btn._msufApplyState then btn:_msufApplyState(k == activeKey) end
        end
    end

    local _isGFScope -- forward decl
    local IsGFScope, GFApplyFont, GFApplyLayout -- forward decls for closures
    do
        local prevBtn
        for i, k in ipairs(SCOPE_KEYS) do
            local bk = k
            local isGF = (bk == "gf_party" or bk == "gf_raid")

            -- Separator dot before Party
            if bk == "gf_party" and prevBtn then
                local sep = scopeBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                sep:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
                sep:SetText("|cff3a5a90·|r")
                local sepAnchor = CreateFrame("Frame", nil, scopeBar)
                sepAnchor:SetSize(10, 18); sepAnchor:SetPoint("LEFT", sep, "RIGHT", 0, 0)
                prevBtn = sepAnchor
            end

            local btn = CreateFrame("Button", nil, scopeBar, BackdropTemplateMixin and "BackdropTemplate" or nil)
            btn:SetSize(i == 1 and 56 or 44, 18)
            if not prevBtn then
                btn:SetPoint("LEFT", scopeEditLbl, "RIGHT", 8, 0)
            else
                btn:SetPoint("LEFT", prevBtn, "RIGHT", 2, 0)
            end
            local bg = btn:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.08, 0.12, 0.22, 0.80)
            btn._msufBg = bg
            local border = CreateFrame("Frame", nil, btn, BackdropTemplateMixin and "BackdropTemplate" or nil)
            border:SetAllPoints(); border:SetBackdrop({ edgeFile = TEX_W8, edgeSize = 1 })
            border:SetBackdropBorderColor(0.15, 0.30, 0.60, 0.50)
            btn._msufBorder = border
            local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("CENTER", 0, 0); fs:SetText(SCOPE_LABELS[bk] or bk)
            btn._msufLabel = fs

            btn._msufApplyState = function(self, active)
                local hasOvr = (bk ~= "shared") and IsOverride(bk)
                if active then
                    bg:SetColorTexture(isGF and 0.10 or 0.12, isGF and 0.20 or 0.24, isGF and 0.40 or 0.50, 0.95)
                    if hasOvr then border:SetBackdropBorderColor(0.96, 0.80, 0.34, 0.98)
                    else border:SetBackdropBorderColor(isGF and 0.25 or 0.30, isGF and 0.50 or 0.55, isGF and 0.90 or 1.00, 0.80) end
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
                G()._fontScopeKey = bk
                RefreshScopeButtons()
                if SyncScopeUI then SyncScopeUI() end
            end)
            btn:SetScript("OnEnter", function(self)
                if self._msufBg then self._msufBg:SetColorTexture(0.10, 0.18, 0.36, 0.90) end
                if GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(SCOPE_LABELS[bk] or bk, 1, 1, 1)
                    if bk == "shared" then
                        GameTooltip:AddLine(TR("Shared baseline used by units without overrides."), 0.72, 0.78, 0.88, true)
                    elseif isGF then
                        GameTooltip:AddLine(TR("Group Frame font settings (separate from unit frame overrides)."), 0.72, 0.78, 0.88, true)
                        if bk == "gf_raid" then GameTooltip:AddLine(TR("Raid scope also applies to Mythic Raid."), 0.55, 0.70, 0.95, true) end
                    else
                        local hasOvr = IsOverride(bk)
                        GameTooltip:AddLine(hasOvr and TR("Override active: this unit uses its own font settings.") or TR("Uses Shared settings."), 0.72, 0.78, 0.88, true)
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

    -- Override checkbox (row 2)
    local overrideCheck = CreateFrame("CheckButton", "MSUF_FontOverrideCheck", scopeBar, "UICheckButtonTemplate")
    overrideCheck:SetPoint("TOPLEFT", scopeBar, "TOPLEFT", 10, -36)
    do
        local ocFS = overrideCheck.text or overrideCheck.Text or _G["MSUF_FontOverrideCheckText"]
        if ocFS then ocFS:SetText(TR("Override shared settings")); ocFS:SetFontObject("GameFontNormalSmall") end
    end
    UI.StyleToggleText(overrideCheck); UI.StyleCheckmark(overrideCheck)
    UI.AttachTooltip(overrideCheck, "Per-unit override", "When unchecked, this unit inherits Shared font settings.")

    overrideCheck:SetScript("OnClick", function(self)
        local uk = GetUnitKey()
        if not uk then self:SetChecked(false); return end
        local gfScope = IsGFScope()
        if self:GetChecked() then
            if gfScope then
                -- GF: just set flag (GF config already has its own values)
                ForEachScopeDB(uk, function(u) u.fontOverride = true end)
            else
                EnableOverride(uk)
            end
        else
            if gfScope then
                ForEachScopeDB(uk, function(u) u.fontOverride = false end)
            else
                U(uk).fontOverride = false
            end
        end
        InvalidateTextSpecs()
        LiveSyncFontVisuals({ layout = "FONT_OVERRIDE" })
        if gfScope then GFApplyFont(); GFApplyLayout() end
        if SyncScopeUI then SyncScopeUI() end
    end)

    -- Override summary
    local scopeOverrideInfo = scopeBar:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    scopeOverrideInfo:SetPoint("BOTTOMLEFT", scopeBar, "BOTTOMLEFT", 10, 8)
    scopeOverrideInfo:SetJustifyH("LEFT"); scopeOverrideInfo:SetWordWrap(false)

    -- Reset button
    local scopeResetBtn = CreateFrame("Button", "MSUF_FontResetOverridesBtn", scopeBar, "UIPanelButtonTemplate")
    scopeResetBtn:SetSize(72, 18); scopeResetBtn:SetPoint("TOPRIGHT", scopeBar, "TOPRIGHT", -8, -36)
    scopeResetBtn:SetText(TR("Reset")); scopeResetBtn:SetNormalFontObject("GameFontNormalSmall")
    scopeResetBtn:SetScript("OnClick", function()
        EnsureDB()
        for _, k in ipairs(ALL_UNITS) do
            local u = MSUF_DB[k]
            if u then u.fontOverride = false end
        end
        -- Reset GF overrides too
        if MSUF_DB.gf_party then MSUF_DB.gf_party.fontOverride = false end
        if MSUF_DB.gf_raid  then MSUF_DB.gf_raid.fontOverride  = false end
        if MSUF_DB.gf_mythicraid then MSUF_DB.gf_mythicraid.fontOverride = false end
        InvalidateTextSpecs()
        LiveSyncFontVisuals({ layout = "FONT_OVERRIDE_RESET" })
        local gf = ns and ns.GF
        if gf and type(gf.RefreshFonts) == "function" then gf.RefreshFonts() end
        if SyncScopeUI then SyncScopeUI() end
    end)

    -- =====================================================================
    -- GF scope helpers (Party / Raid)
    -- =====================================================================
    IsGFScope = function()
        local k = GetScopeKey()
        return k == "gf_party" or k == "gf_raid"
    end
    _isGFScope = IsGFScope
    local function GFKind()
        return (GetScopeKey() == "gf_raid") and "raid" or "party"
    end
    local function ForEachGFKind(fn)
        if type(fn) ~= "function" then return end
        if GetScopeKey() == "gf_raid" then
            fn("raid")
            fn("mythicraid")
        else
            fn("party")
        end
    end
    local function GFVal(key)
        local gf = ns and ns.GF; return gf and gf.Val(GFKind(), key)
    end
    local function GFSet(key, val)
        local gf = ns and ns.GF
        if not (gf and gf.GetConf) then return end
        ForEachGFKind(function(kind)
            local c = gf.GetConf(kind)
            if c then c[key] = val end
        end)
    end
    local function GFSetMany(values)
        local gf = ns and ns.GF
        if not (gf and gf.GetConf and type(values) == "table") then return end
        ForEachGFKind(function(kind)
            local c = gf.GetConf(kind)
            if c then
                for k, v in pairs(values) do c[k] = v end
            end
        end)
    end
    GFApplyFont = function()
        local gf = ns and ns.GF
        if gf and type(gf.RefreshFonts) == "function" then gf.RefreshFonts() end
    end
    GFApplyLayout = function()
        local gf = ns and ns.GF
        if not gf then return end
        local bits = (gf.DIRTY_LAYOUT or 32) + (gf.DIRTY_FONT or 4)
        if type(gf.MarkAllDirty) == "function" then gf.MarkAllDirty(bits) end
        -- Keep option feedback immediate: MarkAllDirty is budgeted/coalesced, so
        -- previews/visible frames may update next frame. RefreshFonts is also
        -- coalesced internally, but direct RefreshPreviewBox makes the menu feel
        -- live without forcing a full GF UpdateAll/aura scan.
        if type(gf.RefreshPreviewBox) == "function" then gf.RefreshPreviewBox() end
    end
    local function GFColorPicker(r, g, b, callback)
        if not ColorPickerFrame or type(callback) ~= "function" then return end
        local sR, sG, sB = tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = sR, g = sG, b = sB, opacity = 1, hasOpacity = false,
                swatchFunc = function() local nr, ng, nb = ColorPickerFrame:GetColorRGB(); callback(nr, ng, nb) end,
                cancelFunc = function(prev) if type(prev) == "table" then callback(prev.r or sR, prev.g or sG, prev.b or sB) else callback(sR, sG, sB) end end,
                previousValues = { r = sR, g = sG, b = sB, opacity = 1 },
            })
        else
            ColorPickerFrame.func = function() local nr, ng, nb = ColorPickerFrame:GetColorRGB(); callback(nr, ng, nb) end
            ColorPickerFrame.cancelFunc = function(prev) if type(prev) == "table" then callback(prev.r or sR, prev.g or sG, prev.b or sB) else callback(sR, sG, sB) end end
            ColorPickerFrame.previousValues = { r = sR, g = sG, b = sB }; ColorPickerFrame.hasOpacity = false
            ColorPickerFrame:SetColorRGB(sR, sG, sB); ColorPickerFrame:Show()
        end
    end
    -- Tracks all GF widget refresh functions
    local _gfRefreshFns = {}
    local function GFSyncAll()
        for i = 1, #_gfRefreshFns do
            local fn = _gfRefreshFns[i]
            if type(fn) == "function" then fn() end
        end
    end

    local MSUF_SetCheckboxEnabled = _G.MSUF_SetCheckboxEnabled or function(cb, enabled)
        if not cb then return end
        if enabled then
            if cb.Enable then cb:Enable() end
        else
            if cb.Disable then cb:Disable() end
        end
        if cb.SetAlpha then cb:SetAlpha(enabled and 1 or 0.4) end
    end

    local function SetWidgetEnabled(widget, enabled)
        if not widget then return end
        enabled = enabled and true or false
        if widget._ddSpec and widget.SetEnabled then
            pcall(widget.SetEnabled, widget, enabled)
        elseif widget.GetChecked and widget.SetChecked then
            MSUF_SetCheckboxEnabled(widget, enabled)
        elseif widget.SetEnabled then
            pcall(widget.SetEnabled, widget, enabled)
        elseif enabled then
            if widget.Enable then pcall(widget.Enable, widget) end
        else
            if widget.Disable then pcall(widget.Disable, widget) end
        end
        local objectType = widget.GetObjectType and widget:GetObjectType() or nil
        if objectType ~= "FontString" and widget.EnableMouse then pcall(widget.EnableMouse, widget, enabled) end
        if widget.SetAlpha then widget:SetAlpha(enabled and 1 or 0.4) end

        if widget.editBox then
            if widget.editBox.EnableMouse then widget.editBox:EnableMouse(enabled) end
            if enabled then
                if widget.editBox.Enable then widget.editBox:Enable() end
            else
                if widget.editBox.Disable then widget.editBox:Disable() end
            end
            if widget.editBox.SetAlpha then widget.editBox:SetAlpha(enabled and 1 or 0.4) end
        end
        if widget.minusButton then
            if enabled then
                if widget.minusButton.Enable then widget.minusButton:Enable() end
            else
                if widget.minusButton.Disable then widget.minusButton:Disable() end
            end
            if widget.minusButton.SetAlpha then widget.minusButton:SetAlpha(enabled and 1 or 0.4) end
        end
        if widget.plusButton then
            if enabled then
                if widget.plusButton.Enable then widget.plusButton:Enable() end
            else
                if widget.plusButton.Disable then widget.plusButton:Disable() end
            end
            if widget.plusButton.SetAlpha then widget.plusButton:SetAlpha(enabled and 1 or 0.4) end
        end

        local label = widget.Text or widget.text
        if not label and widget.GetName then
            local n = widget:GetName()
            label = n and _G[n .. "Text"] or nil
        end
        if label and label.SetTextColor then
            local c = enabled and 1 or 0.35
            label:SetTextColor(c, c, c)
        end
    end

    local function SetWidgetListEnabled(list, enabled)
        if type(list) ~= "table" then return end
        for i = 1, #list do
            SetWidgetEnabled(list[i], enabled)
        end
    end

    local function SetBoxTitleEnabled(box, enabled)
        if box and box._msufTitle then SetWidgetEnabled(box._msufTitle, enabled) end
    end

    -- =====================================================================
    -- Scroll frame (below scope bar)
    -- =====================================================================
    local fontsScroll = CreateFrame("ScrollFrame", "MSUF_FontsMenuScrollFrame", fontGroup, "UIPanelScrollFrameTemplate")
    fontsScroll:SetPoint("TOPLEFT", fontGroup, "TOPLEFT", 0, -186)
    fontsScroll:SetPoint("BOTTOMRIGHT", fontGroup, "BOTTOMRIGHT", -36, 16)

    local fontsScrollChild = CreateFrame("Frame", "MSUF_FontsScrollChild", fontsScroll)
    fontsScrollChild:SetSize(CONTENT_W, 1200)
    fontsScroll:SetScrollChild(fontsScrollChild)

    local content = fontsScrollChild

    -- =====================================================================
    -- SECTION 1: Global Font (default open) — NOT scope-affected
    -- =====================================================================
    local anchorTop = CreateFrame("Frame", nil, content)
    anchorTop:SetSize(CONTENT_W, 1)
    anchorTop:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)

    local fontBox, fontBody = MakeCollapsibleBox(content, anchorTop, CONTENT_W, 76, TR("Global Font"), true)

    local fontChoices = {}
    local function RebuildFontChoices()
        local normalizeFontKey = _G.MSUF_NormalizeFontKey or (ns and ns.MSUF_NormalizeFontKey) or function(key) return key end
        for i = #fontChoices, 1, -1 do fontChoices[i] = nil end
        for _, info in ipairs(_G.MSUF_FONT_LIST or _G.FONT_LIST or {}) do
            fontChoices[#fontChoices + 1] = { key = normalizeFontKey(info.key), label = info.name, path = info.path }
        end
        local LSM = (ns and ns.LSM) or _G.MSUF_LSM
        if LSM then
            if LSM.Register then
                local rawFonts = type(LSM.HashTable) == "function" and LSM:HashTable("font") or nil
                for _, d in ipairs(fontChoices) do
                    if d.key and d.key ~= "" and d.path and d.path ~= "" then
                        local v = rawFonts and rawFonts[d.key]
                        if not v then
                            pcall(LSM.Register, LSM, "font", d.key, d.path)
                        end
                    end
                end
            end
            local used = {}; for _, e in ipairs(fontChoices) do used[normalizeFontKey(e.key)] = true end
            local names = LSM:List("font"); table.sort(names)
            for _, name in ipairs(names) do
                local normalizedName = normalizeFontKey(name)
                if not used[normalizedName] then fontChoices[#fontChoices + 1] = { key = name, label = name }; used[normalizedName] = true end
            end
        end
    end
    _G.MSUF_RebuildFontChoices = RebuildFontChoices
    RebuildFontChoices()

    local fontDrop = UI.Dropdown({
        name = "MSUF_FontDropdown", parent = fontBody,
        anchor = fontBody, anchorPoint = "TOPLEFT", x = 14, y = -8, width = 300, maxVisible = 12,
        itemHeight = 22,
        items = function()
            if #fontChoices == 0 then RebuildFontChoices() end
            local getFP = _G.MSUF_GetFontPreviewObject
            local out = {}
            for i = 1, #fontChoices do
                local c = fontChoices[i]
                out[i] = {
                    key = c.key,
                    label = c.label,
                    fontObject = type(getFP) == "function" and getFP(c.key) or nil,
                }
            end
            return out
        end,
        get = function()
            local normalizeFontKey = _G.MSUF_NormalizeFontKey or (ns and ns.MSUF_NormalizeFontKey) or function(key) return key end
            return normalizeFontKey(G().fontKey or "FRIZQT")
        end,
        set = function(v)
            local normalizeFontKey = _G.MSUF_NormalizeFontKey or (ns and ns.MSUF_NormalizeFontKey) or function(key) return key end
            G().fontKey = normalizeFontKey(v)
            ClearUFFontKeyOverrides()
            if type(_G.MSUF_NormalizeStoredFontKeys) == "function" then
                _G.MSUF_NormalizeStoredFontKeys()
            end
            InvalidateTextSpecs()
            LiveSyncFontVisuals({ layout = "FONT_GLOBAL" })
            if C_Timer and C_Timer.After then C_Timer.After(0, function()
                InvalidateTextSpecs()
                LiveSyncFontVisuals({ layout = "FONT_GLOBAL_DEFERRED" })
            end) end
        end,
    })

    -- GF font dropdown (same position, shown only for GF scopes)
    local gfFontDrop = UI.Dropdown({
        name = "MSUF_GF_FontDrop", parent = fontBody,
        anchor = fontBody, anchorPoint = "TOPLEFT", x = 14, y = -8, width = 300,
        items = function()
            local normalizeFontKey = _G.MSUF_NormalizeFontKey or (ns and ns.MSUF_NormalizeFontKey) or function(key) return key end
            local items = { { key = "", label = "(Global Default)" } }
            local used = { [""] = true }
            for _, info in ipairs(_G.MSUF_FONT_LIST or _G.FONT_LIST or {}) do
                local key = normalizeFontKey(info.key)
                if not used[key] then
                    items[#items + 1] = { key = key, label = info.name or key }
                    used[key] = true
                end
            end
            local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
            if LSM then
                local list = LSM:List("font")
                for i = 1, #list do
                    local key = normalizeFontKey(list[i])
                    if not used[key] then
                        items[#items + 1] = { key = list[i], label = list[i] }
                        used[key] = true
                    end
                end
            end
            return items
        end,
        get = function()
            local normalizeFontKey = _G.MSUF_NormalizeFontKey or (ns and ns.MSUF_NormalizeFontKey) or function(key) return key end
            return normalizeFontKey(GFVal("fontKey") or "")
        end,
        set = function(v)
            local normalizeFontKey = _G.MSUF_NormalizeFontKey or (ns and ns.MSUF_NormalizeFontKey) or function(key) return key end
            GFSet("fontKey", normalizeFontKey(v))
            GFApplyFont()
        end,
    })
    gfFontDrop:Hide()
    _gfRefreshFns[#_gfRefreshFns + 1] = function() if gfFontDrop and gfFontDrop.Refresh then gfFontDrop:Refresh() end end

    -- Widget visibility tracking
    local _ufOnlyWidgets = {}
    local _gfOnlyWidgets = { gfFontDrop }

    -- =====================================================================
    -- SECTION 2: Text Style (scope-aware, default open)
    -- =====================================================================
    local styleBox, styleBody = MakeCollapsibleBox(content, fontBox, CONTENT_W, 148, TR("Text Style"), true)

    local ufOutlineLbl = styleBody:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ufOutlineLbl:SetPoint("TOPLEFT", styleBody, "TOPLEFT", 16, -8)
    ufOutlineLbl:SetText(TR("Font Outline"))

    local boldCheck = UI.Dropdown({
        name = "MSUF_BoldTextCheck", parent = styleBody,
        anchor = ufOutlineLbl, x = -16, y = -2, width = 240,
        items = {
            { key = "OUTLINE",      label = "Outline"       },
            { key = "THICKOUTLINE", label = "Thick Outline" },
            { key = "NONE",         label = "None"          },
        },
        get = function()
            if ScopeGet("noOutline", false) then return "NONE" end
            if ScopeGet("boldText", false) then return "THICKOUTLINE" end
            return "OUTLINE"
        end,
        set = function(v)
            ScopeSet("boldText", v == "THICKOUTLINE")
            ScopeSet("noOutline", v == "NONE")
            InvalidateTextSpecs()
            LiveSyncFontVisuals({ layout = "FONT_STYLE" })
        end,
    })

    local ufShadowLbl = styleBody:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ufShadowLbl:SetPoint("TOPLEFT", boldCheck, "BOTTOMLEFT", 16, -10)
    ufShadowLbl:SetText(TR("Add text shadow (backdrop)"))

    local textBackdropCheck = UI.Dropdown({
        name = "MSUF_TextBackdropCheck", parent = styleBody,
        anchor = ufShadowLbl, x = -16, y = -2, width = 240,
        items = {
            { key = "ON",  label = "On"  },
            { key = "OFF", label = "Off" },
        },
        get = function()
            return ScopeGet("textBackdrop", true) and "ON" or "OFF"
        end,
        set = function(v)
            ScopeSet("textBackdrop", v == "ON")
            InvalidateTextSpecs()
            LiveSyncFontVisuals({ layout = "FONT_STYLE" })
        end,
    })

    local noOutlineCheck = nil
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = ufOutlineLbl
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = boldCheck
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = ufShadowLbl
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = textBackdropCheck

    -- GF: Font Outline dropdown + Use Global Font Color
    local gfOutlineLbl = styleBody:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gfOutlineLbl:SetPoint("TOPLEFT", styleBody, "TOPLEFT", 16, -8); gfOutlineLbl:SetText(TR("Font Outline")); gfOutlineLbl:Hide()
    local gfOutlineDrop = UI.Dropdown({
        name = "MSUF_GF_Style_OutlineDrop", parent = styleBody,
        anchor = gfOutlineLbl, x = -16, y = -2, width = 200,
        items = {
            { key = "",              label = "(Global Default)" },
            { key = "NONE",          label = "None"             },
            { key = "OUTLINE",       label = "Outline"          },
            { key = "THICKOUTLINE",  label = "Thick Outline"    },
        },
        get = function() return GFVal("fontOutline") or "" end,
        set = function(v) GFSet("fontOutline", (v == "") and nil or v); GFApplyFont() end,
    })
    gfOutlineDrop:Hide()
    local gfGlobalColorChk = UI.Check({
        name = "MSUF_GF_Style_GlobalColor", parent = styleBody,
        anchor = gfOutlineDrop, x = 16, y = -10, maxTextWidth = 400,
        label = TR("Use Global Font Color (Colors menu)"),
        get = function() return GFVal("useGlobalFontColor") ~= false end,
        set = function(v) GFSet("useGlobalFontColor", v); GFApplyFont() end,
    })
    gfGlobalColorChk:Hide()
    _gfOnlyWidgets[#_gfOnlyWidgets + 1] = gfOutlineLbl
    _gfOnlyWidgets[#_gfOnlyWidgets + 1] = gfOutlineDrop
    _gfOnlyWidgets[#_gfOnlyWidgets + 1] = gfGlobalColorChk
    _gfRefreshFns[#_gfRefreshFns + 1] = function()
        if gfOutlineDrop and gfOutlineDrop.Refresh then gfOutlineDrop:Refresh() end
        if gfGlobalColorChk and gfGlobalColorChk.Refresh then gfGlobalColorChk:Refresh() end
    end

    -- =====================================================================
    -- SECTION 4: Name Colors (scope-aware, default open)
    -- =====================================================================
    local colorsBox, colorsBody = MakeCollapsibleBox(content, styleBox, CONTENT_W, 220, TR("Name & Power Colors"), true)

    -- ── UF: Name Color ──
    local ufNameColorLbl = UI.Label({ parent = colorsBody, text = TR("Player Name Color"),
        font = "GameFontNormal", anchor = colorsBody, anchorPoint = "TOPLEFT", x = 16, y = -8 })

    local nameClassColorDrop = UI.Dropdown({
        name = "MSUF_NameClassColorDrop", parent = colorsBody,
        anchor = ufNameColorLbl, x = -16, y = -2, width = 220,
        items = {
            { key = "DEFAULT", label = "Default (Font Color)" },
            { key = "CLASS",   label = "Class Color"          },
        },
        get = function()
            return ScopeGet("nameClassColor", false) and "CLASS" or "DEFAULT"
        end,
        set = function(v)
            ScopeSet("nameClassColor", v == "CLASS")
            InvalidateTextSpecs()
            LiveSyncFontVisuals({ refreshPower = false, layout = "NAME_COLORS" })
        end,
    })

    -- ── UF: NPC Name Color ──
    local ufNpcColorLbl = UI.Label({ parent = colorsBody, text = TR("NPC / Boss Name Color"),
        font = "GameFontNormal", anchor = nameClassColorDrop, x = 16, y = -10 })

    local npcNameRedDrop = UI.Dropdown({
        name = "MSUF_NPCNameRedDrop", parent = colorsBody,
        anchor = ufNpcColorLbl, x = -16, y = -2, width = 220,
        items = {
            { key = "DEFAULT", label = "Default (Font Color)" },
            { key = "NPC",     label = "NPC / Reaction Color"  },
        },
        get = function()
            return ScopeGet("npcNameRed", false) and "NPC" or "DEFAULT"
        end,
        set = function(v)
            ScopeSet("npcNameRed", v == "NPC")
            InvalidateTextSpecs()
            LiveSyncFontVisuals({ refreshPower = false, layout = "NAME_COLORS" })
        end,
    })

    -- ── UF: Power Text Color ──
    local ufPowerColorLbl = UI.Label({ parent = colorsBody, text = TR("Power Text Color"),
        font = "GameFontNormal", anchor = npcNameRedDrop, x = 16, y = -10 })

    local powerColorDrop = UI.Dropdown({
        name = "MSUF_PowerTextColorDrop", parent = colorsBody,
        anchor = ufPowerColorLbl, x = -16, y = -2, width = 220,
        items = {
            { key = "DEFAULT",  label = "Default (Font Color)"  },
            { key = "RESOURCE", label = "By Power Type (Mana, Rage, ...)" },
        },
        get = function()
            return ScopeGet("colorPowerTextByType", false) and "RESOURCE" or "DEFAULT"
        end,
        set = function(v)
            ScopeSet("colorPowerTextByType", v == "RESOURCE")
            InvalidateTextSpecs()
            LiveSyncFontVisuals({ refreshIdentity = false, layout = "POWER_TEXT_COLOR" })
        end,
    })

    -- Track UF color widgets
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = ufNameColorLbl
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = nameClassColorDrop
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = ufNpcColorLbl
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = npcNameRedDrop
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = ufPowerColorLbl
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = powerColorDrop

    -- backward compat refs (panel stores used by Options_Core)
    local nameClassColorCheck = nameClassColorDrop
    local npcNameRedCheck     = npcNameRedDrop
    local powerColorCheck     = powerColorDrop

    -- ── GF: Name Color Mode + Custom Swatch ──
    local gfNameColorLbl = colorsBody:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gfNameColorLbl:SetPoint("TOPLEFT", colorsBody, "TOPLEFT", 16, -8); gfNameColorLbl:SetText(TR("Name Color")); gfNameColorLbl:Hide()
    local gfNameColorDrop = UI.Dropdown({
        name = "MSUF_GF_Colors_NameColorDrop", parent = colorsBody,
        anchor = gfNameColorLbl, x = -16, y = -2, width = 200,
        items = {
            { key = "DEFAULT", label = "Default (Font Color)" },
            { key = "CLASS",   label = "Class Color"          },
            { key = "CUSTOM",  label = "Custom"               },
        },
        get = function() return GFVal("nameColorMode") or "DEFAULT" end,
        set = function(v) GFSet("nameColorMode", v); GFApplyFont() end,
    })
    gfNameColorDrop:Hide()
    local gfSwatchLbl = colorsBody:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    gfSwatchLbl:SetPoint("LEFT", gfNameColorDrop, "RIGHT", 16, 0); gfSwatchLbl:SetText(TR("Custom")); gfSwatchLbl:Hide()
    local gfSwatchBtn = CreateFrame("Button", nil, colorsBody)
    gfSwatchBtn:SetSize(32, 16); gfSwatchBtn:SetPoint("LEFT", gfSwatchLbl, "RIGHT", 6, 0); gfSwatchBtn:Hide()
    local gfSwatchTex = gfSwatchBtn:CreateTexture(nil, "ARTWORK"); gfSwatchTex:SetAllPoints()
    local function GFRefreshSwatch()
        gfSwatchTex:SetColorTexture(GFVal("nameColorR") or 1, GFVal("nameColorG") or 1, GFVal("nameColorB") or 1)
    end
    gfSwatchBtn:SetScript("OnShow", GFRefreshSwatch)
    gfSwatchBtn:SetScript("OnClick", function()
        GFColorPicker(GFVal("nameColorR") or 1, GFVal("nameColorG") or 1, GFVal("nameColorB") or 1, function(nr, ng, nb)
            GFSetMany({ nameColorR = nr, nameColorG = ng, nameColorB = nb }); GFApplyFont(); GFRefreshSwatch()
        end)
    end)
    GFRefreshSwatch()
    _gfOnlyWidgets[#_gfOnlyWidgets + 1] = gfNameColorLbl
    _gfOnlyWidgets[#_gfOnlyWidgets + 1] = gfNameColorDrop
    _gfOnlyWidgets[#_gfOnlyWidgets + 1] = gfSwatchLbl
    _gfOnlyWidgets[#_gfOnlyWidgets + 1] = gfSwatchBtn
    _gfRefreshFns[#_gfRefreshFns + 1] = function()
        if gfNameColorDrop and gfNameColorDrop.Refresh then gfNameColorDrop:Refresh() end
        GFRefreshSwatch()
    end

    -- =====================================================================
    -- SECTION 5: Name Shortening (scope-aware, default open)
    -- =====================================================================
    local nameBox, nameBody = MakeCollapsibleBox(content, colorsBox, CONTENT_W, 220, TR("Name Shortening"), true)

    local shortenCheck, shortenMaxSlider, shortenNoEllipsis, shortenClipDrop, shortenClipLabel, infoBtn

    local function SyncShortenEnabled()
        local on = ScopeGet("shortenNames", false, "shortenNames") and true or false
        local scopeKey = GetScopeKey()
        local canEdit = (scopeKey == "shared") or ((not GF_SCOPE_DB_KEYS[scopeKey]) and IsOverride(scopeKey))
        local detailActive = canEdit and on
        SetWidgetEnabled(shortenCheck, canEdit)
        SetWidgetEnabled(shortenClipLabel, detailActive)
        SetWidgetEnabled(shortenClipDrop, detailActive)
        SetWidgetEnabled(shortenMaxSlider, detailActive)
        SetWidgetEnabled(shortenNoEllipsis, canEdit)
        SetWidgetEnabled(infoBtn, canEdit)
    end
    local function ApplyShortenLive(layoutReason)
        EnsureDB()
        local keys
        local scopeKey = GetScopeKey()
        if scopeKey == "shared" then
            keys = ALL_UNITS
        elseif not GF_SCOPE_DB_KEYS[scopeKey] then
            keys = { scopeKey }
        else
            return
        end

        if _G.MSUF_InCombat then
            local applyQueued = _G.MSUF_ApplySettingsForKey_Immediate or _G.ApplySettingsForKey
            if type(applyQueued) == "function" then
                for _, key in ipairs(keys) do pcall(applyQueued, key) end
            elseif RequestLayoutAll then
                RequestLayoutAll(layoutReason)
            end
            return
        end

        local clamp = _G.MSUF_ClampNameWidth
        local frames = _G.MSUF_UnitFrames
        local function ApplyFrame(frame, conf)
            if not frame then return end
            frame._msufClampStamp = nil
            frame._msufNameClipAnchorStamp = nil
            frame._msufNameClipTextStamp = nil
            frame._msufTextSpec = nil
            if type(clamp) == "function" then clamp(frame, conf) end
            if type(_G.MSUF_QueueUnitframeUpdate) == "function" then
                _G.MSUF_QueueUnitframeUpdate(frame, true)
            end
        end
        for _, key in ipairs(keys) do
            local conf = MSUF_DB and MSUF_DB[key]
            if key == "boss" then
                for i = 1, 5 do
                    local frame = (frames and frames["boss" .. i]) or _G["MSUF_boss" .. i]
                    ApplyFrame(frame, conf)
                end
            else
                local frame = (frames and frames[key]) or _G["MSUF_" .. key]
                ApplyFrame(frame, conf)
            end
        end
    end
    local function ApplyShortenChange(layoutReason, onlyWhenEnabled)
        SyncShortenEnabled()
        if SyncScopeUI then SyncScopeUI() end
        InvalidateTextSpecs()
        if (not onlyWhenEnabled) or ScopeGet("shortenNames", false, "shortenNames") then
            LiveSyncFontVisuals({ layout = layoutReason })
            ApplyShortenLive(layoutReason)
        end
    end

    shortenCheck = UI.Check({
        name = "MSUF_ShortenNamesCheck", parent = nameBody,
        anchor = nameBody, anchorPoint = "TOPLEFT", x = 16, y = -8, maxTextWidth = 400,
        label = TR("Shorten unit names (except Player)"),
        get = function() return ScopeGet("shortenNames", false, "shortenNames") and true or false end,
        set = function(v)
            ScopeSet("shortenNames", v, "shortenNames")
            ApplyShortenChange("SHORTEN_NAMES", false)
        end,
    })
    function shortenCheck:Refresh()
        self:SetChecked(ScopeGet("shortenNames", false, "shortenNames") and true or false)
        if self._msufToggleUpdate then self._msufToggleUpdate() end
    end

    shortenClipLabel = UI.Label({ parent = nameBody, text = TR("Truncation style"), font = "GameFontNormal", anchor = shortenCheck, x = 16, y = -10 })

    shortenClipDrop = UI.Dropdown({
        name = "MSUF_ShortenNameClipSideDrop", parent = nameBody,
        anchor = shortenClipLabel, x = -16, y = -2, width = 240,
        items = {
            { key = "LEFT",  label = "Keep end (show last letters)" },
            { key = "RIGHT", label = "Keep start (show first letters)" },
        },
        get = function() return ScopeGet("shortenNameClipSide", "LEFT") end,
        set = function(v)
            ScopeSet("shortenNameClipSide", v)
            ApplyShortenChange("SHORTEN_CLIP", true)
        end,
    })

    shortenMaxSlider = UI.Slider({
        name = "MSUF_ShortenNameMaxCharsSlider", parent = nameBody, compact = true, compactInput = true,
        anchor = shortenClipDrop, x = 16, y = -12, width = 254,
        label = TR("Max name length"), min = 6, max = 30, step = 1, default = 6,
        lowText = "6", highText = "30",
        get = function() return ScopeGet("shortenNameMaxChars", 6) end,
        set = function(v)
            ScopeSet("shortenNameMaxChars", floor(v + 0.5))
            ApplyShortenChange("SHORTEN_CHARS", true)
        end,
    })

    shortenNoEllipsis = UI.Check({
        name = "MSUF_ShortenNameNoEllipsis", parent = nameBody,
        anchor = shortenMaxSlider, x = 0, y = -22, maxTextWidth = 400,
        label = TR("No Ellipsis (truncate without ..)"),
        get = function() return not ScopeGet("shortenNameShowDots", true) end,
        set = function(v)
            ScopeSet("shortenNameShowDots", not v)
            ApplyShortenChange("SHORTEN_ELLIPSIS", false)
        end,
    })
    function shortenNoEllipsis:Refresh()
        self:SetChecked(not ScopeGet("shortenNameShowDots", true))
        if self._msufToggleUpdate then self._msufToggleUpdate() end
    end

    infoBtn = CreateFrame("Button", "MSUF_ShortenNameInfoButton", nameBody)
    infoBtn:SetSize(16, 16)
    infoBtn:SetNormalTexture("Interface\\FriendsFrame\\InformationIcon")
    infoBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    infoBtn:SetPoint("TOPLEFT", shortenNoEllipsis, "BOTTOMLEFT", 0, -6)
    infoBtn:SetScript("OnClick", function(self)
        if GameTooltip:IsOwned(self) and GameTooltip:IsShown() then GameTooltip:Hide(); return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(TR("Name Shortening"))
        local side = ScopeGet("shortenNameClipSide", "LEFT")
        if side == "RIGHT" then
            GameTooltip:AddLine("Keep start: shows the first letters (clips the end).", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Keep end: shows the last letters (clips the beginning).", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)

    SyncShortenEnabled()

    -- GF: nameMaxChars + nameNoEllipsis (shown only for GF scopes in this section)
    local gfMaxCharsLbl = nameBody:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gfMaxCharsLbl:SetPoint("TOPLEFT", nameBody, "TOPLEFT", 16, -10)
    gfMaxCharsLbl:SetText(TR("Group Frame Name Truncation"))
    gfMaxCharsLbl:Hide()
    local gfMaxCharsSlider = UI.Slider({
        name = "MSUF_GF_Shorten_MaxChars", parent = nameBody, compact = true, compactInput = true,
        -- Leave enough vertical space for the OptionsSliderTemplate value text.
        -- Before this, the external section label and the slider's dynamic
        -- "Max Chars: X" label overlapped/clipped in the Fonts menu.
        anchor = gfMaxCharsLbl, x = 0, y = -28, width = 354,
        label = TR("Name Max Chars"), min = 0, max = 30, step = 1, default = 0,
        lowText = "0", highText = "30",
        get = function() return GFVal("nameMaxChars") or 0 end,
        set = function(v) GFSet("nameMaxChars", floor(v + 0.5)); GFApplyLayout() end,
        formatText = function(v) return v == 0 and "Max Chars: Unlimited" or string.format("Max Chars: %d", v) end,
    })
    gfMaxCharsSlider:Hide()
    local gfNoEllipsis = UI.Check({
        name = "MSUF_GF_Shorten_NoEllipsis", parent = nameBody,
        anchor = gfMaxCharsSlider, x = 0, y = -22, maxTextWidth = 400,
        label = TR("No Ellipsis (truncate without ..)"),
        get = function() return GFVal("nameNoEllipsis") and true or false end,
        set = function(v) GFSet("nameNoEllipsis", v); GFApplyLayout() end,
    })
    gfNoEllipsis:Hide()
    _gfOnlyWidgets[#_gfOnlyWidgets + 1] = gfMaxCharsLbl
    _gfOnlyWidgets[#_gfOnlyWidgets + 1] = gfMaxCharsSlider
    _gfOnlyWidgets[#_gfOnlyWidgets + 1] = gfNoEllipsis
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = shortenCheck
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = shortenClipLabel
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = shortenClipDrop
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = shortenMaxSlider
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = shortenNoEllipsis
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = infoBtn
    _gfRefreshFns[#_gfRefreshFns + 1] = function()
        if gfMaxCharsSlider and gfMaxCharsSlider.Refresh then gfMaxCharsSlider:Refresh() end
        if gfNoEllipsis and gfNoEllipsis.Refresh then gfNoEllipsis:Refresh() end
    end

    -- =====================================================================
    -- Dynamic content height
    -- =====================================================================
    local _lastBox = nameBox
    MSUF_Fonts_UpdateContentHeight = function()
        if not (content and _lastBox and content.GetTop and _lastBox.GetBottom) then return end
        local top = content:GetTop()
        local bottom = _lastBox:GetBottom()
        if not top or not bottom then return end
        local h = (top - bottom) + 24
        if h < 10 then h = 10 end
        if content.__msufFonts_lastAutoH ~= h then
            content.__msufFonts_lastAutoH = h
            content:SetHeight(h)
        end
    end

    -- =====================================================================
    -- SyncScopeUI — refresh all widgets to current scope
    -- =====================================================================
    SyncScopeUI = function()
        EnsureDB()
        RefreshScopeButtons()

        local uk = GetUnitKey()
        local isShared = (uk == nil)
        local gfScope = IsGFScope()
        local isOvr = (uk ~= nil) and IsOverride(uk)

        -- Override checkbox: any non-Shared scope (UF + GF)
        overrideCheck:SetShown(not isShared)
        overrideCheck:SetChecked(isOvr)

        -- Toggle UF-only vs GF-only widgets
        for _, w in ipairs(_ufOnlyWidgets) do
            if w and w.SetShown then w:SetShown(not gfScope)
            elseif w and w.Show then if gfScope then w:Hide() else w:Show() end end
        end
        for _, w in ipairs(_gfOnlyWidgets) do
            if w and w.SetShown then w:SetShown(gfScope)
            elseif w and w.Show then if gfScope then w:Show() else w:Hide() end end
        end
        if fontDrop then
            if fontDrop.SetShown then
                fontDrop:SetShown(not gfScope)
            elseif fontDrop.Show then
                if gfScope then fontDrop:Hide() else fontDrop:Show() end
            end
        end

        -- Override summary + reset: visible only on Shared
        if isShared then
            local parts = {}
            for _, k in ipairs(ALL_UNITS) do
                if IsOverride(k) then parts[#parts + 1] = SCOPE_LABELS[k] or k end
            end
            -- Include GF overrides in summary
            if IsOverride("gf_party") then parts[#parts + 1] = "Party" end
            if IsOverride("gf_raid")  then parts[#parts + 1] = "Raid" end
            if #parts > 0 then
                scopeOverrideInfo:SetText("|cffffffffOverrides:|r " .. table.concat(parts, ", "))
                scopeOverrideInfo:SetFontObject(GameFontHighlightSmall)
                scopeOverrideInfo:Show()
                scopeResetBtn:Show(); scopeResetBtn:Enable(); scopeResetBtn:SetAlpha(1)
            else
                scopeOverrideInfo:SetText("|cff9aa0a6No overrides active.|r")
                scopeOverrideInfo:SetFontObject(GameFontDisableSmall)
                scopeOverrideInfo:Show()
                scopeResetBtn:Show(); scopeResetBtn:Disable(); scopeResetBtn:SetAlpha(0.45)
            end
        else
            scopeOverrideInfo:Hide()
            scopeResetBtn:Hide()
        end

        -- Font/style/color/shortening use fontOverride. Text sizes are configured
        -- in Edit Mode for UF and in the Group Frames menus for GF.
        local fontControlsActive = isShared or isOvr
        local function ApplyFontScopeEnabled()
            SetWidgetListEnabled(_ufOnlyWidgets, (not gfScope) and fontControlsActive)
            SetWidgetListEnabled(_gfOnlyWidgets, gfScope and fontControlsActive)
            if fontDrop then SetWidgetEnabled(fontDrop, not gfScope) end
            SetBoxTitleEnabled(fontBox, (not gfScope) or fontControlsActive)
            SetBoxTitleEnabled(styleBox, fontControlsActive)
            SetBoxTitleEnabled(colorsBox, fontControlsActive)
            if not gfScope and SyncShortenEnabled then SyncShortenEnabled() end
        end
        ApplyFontScopeEnabled()

        -- Name Shortening: hide for Player scope, disable for non-override
        local isPlayer = (GetScopeKey() == "player")
        if isPlayer then
            nameBox:SetAlpha(0)
            nameBox:SetHeight(1)
            nameBox._msufHiddenForPlayer = true
        else
            if nameBox._msufHiddenForPlayer then
                nameBox._msufHiddenForPlayer = nil
                nameBox:SetHeight(nameBox._msufCollapsed and 28 or (nameBox._msufExpandedH or 220))
            end
            nameBox:SetAlpha(1)
            SetBoxTitleEnabled(nameBox, fontControlsActive)
        end

        -- Refresh all widgets for current scope
        if not gfScope then
            if fontDrop and fontDrop.Refresh then fontDrop:Refresh() end
            if boldCheck and boldCheck.Refresh then boldCheck:Refresh() end
            if noOutlineCheck and noOutlineCheck.Refresh then noOutlineCheck:Refresh() end
            if textBackdropCheck and textBackdropCheck.Refresh then textBackdropCheck:Refresh() end
            if nameClassColorCheck and nameClassColorCheck.Refresh then nameClassColorCheck:Refresh() end
            if npcNameRedCheck and npcNameRedCheck.Refresh then npcNameRedCheck:Refresh() end
            if powerColorCheck and powerColorCheck.Refresh then powerColorCheck:Refresh() end
            if shortenCheck and shortenCheck.Refresh then shortenCheck:Refresh() end
            if shortenClipDrop and shortenClipDrop.Refresh then shortenClipDrop:Refresh() end
            if shortenMaxSlider and shortenMaxSlider.Refresh then shortenMaxSlider:Refresh() end
            if shortenNoEllipsis and shortenNoEllipsis.Refresh then shortenNoEllipsis:Refresh() end
            SyncShortenEnabled()
        else
            GFSyncAll()
        end
        ApplyFontScopeEnabled()

        if MSUF_Fonts_UpdateContentHeight then pcall(MSUF_Fonts_UpdateContentHeight) end
    end

    -- =====================================================================
    -- SyncAll (OnShow refresh)
    -- =====================================================================
    local function SyncAll()
        if SyncScopeUI then SyncScopeUI() end
    end
    SyncAll()
    if fontGroup.HookScript then
        fontGroup:HookScript("OnShow", SyncAll)
        fontGroup:HookScript("OnSizeChanged", function()
            if MSUF_Fonts_UpdateContentHeight then
                C_Timer.After(0, MSUF_Fonts_UpdateContentHeight)
            end
        end)
    end

    -- =====================================================================
    -- Color list export (backward compat)
    -- =====================================================================
    local colorList = {
        { key="white",r=1,g=1,b=1,label="White" }, { key="black",r=0,g=0,b=0,label="Black" },
        { key="red",r=1,g=0,b=0,label="Red" }, { key="green",r=0,g=1,b=0,label="Green" },
        { key="blue",r=0,g=0,b=1,label="Blue" }, { key="yellow",r=1,g=1,b=0,label="Yellow" },
        { key="cyan",r=0,g=1,b=1,label="Cyan" }, { key="magenta",r=1,g=0,b=1,label="Magenta" },
        { key="orange",r=1,g=0.5,b=0,label="Orange" }, { key="purple",r=0.6,g=0,b=0.8,label="Purple" },
        { key="pink",r=1,g=0.6,b=0.8,label="Pink" }, { key="turquoise",r=0,g=0.9,b=0.8,label="Turquoise" },
        { key="grey",r=0.5,g=0.5,b=0.5,label="Grey" }, { key="brown",r=0.6,g=0.3,b=0.1,label="Brown" },
        { key="gold",r=1,g=0.85,b=0.1,label="Gold" },
    }
    panel.__MSUF_COLOR_LIST = colorList
    _G.MSUF_COLOR_LIST = colorList

    -- =====================================================================
    -- Panel stores (Core compat)
    -- =====================================================================
    panel.__MSUF_FontChoices = fontChoices
    panel.__MSUF_RebuildFontChoices = RebuildFontChoices
    panel.fontDrop = fontDrop
    panel.boldCheck = boldCheck
    panel.noOutlineCheck = noOutlineCheck
    panel.textBackdropCheck = textBackdropCheck
    panel.nameClassColorCheck = nameClassColorCheck
    panel.npcNameRedCheck = npcNameRedCheck
    panel.powerTextColorByTypeCheck = powerColorCheck
    panel.shortenNamesCheck = shortenCheck
    panel.shortenNameClipSideDrop = shortenClipDrop
    panel.shortenNameMaxCharsSlider = shortenMaxSlider
    panel.shortenNameNoEllipsisCheck = shortenNoEllipsis
end
