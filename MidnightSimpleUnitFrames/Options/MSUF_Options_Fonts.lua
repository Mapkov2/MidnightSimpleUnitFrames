-- ---------------------------------------------------------------------------
-- MSUF_Options_Fonts.lua  (Phase 7: Per-unit scope system — Bars/Portraits pattern)
--
-- Font settings: global font, text sizes, text style, name colors, name display.
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
    local function EnsureCastbars()
        if type(_G.MSUF_EnsureAddonLoaded) == "function" then pcall(_G.MSUF_EnsureAddonLoaded, "MidnightSimpleUnitFrames_Castbars")
        elseif _G.C_AddOns and type(_G.C_AddOns.LoadAddOn) == "function" then pcall(_G.C_AddOns.LoadAddOn, "MidnightSimpleUnitFrames_Castbars") end
    end

    local TEX_W8 = "Interface\\Buttons\\WHITE8x8"
    local CONTENT_W = 650
    local ALL_UNITS = { "player", "target", "targettarget", "focus", "pet", "boss" }

    local FONT_OVERRIDE_KEYS = {
        "boldText", "noOutline", "textBackdrop",
        "nameClassColor", "npcNameRed", "colorPowerTextByType",
        "shortenNameMaxChars", "shortenNameClipSide", "shortenNameFrontMaskPx", "shortenNameShowDots",
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
    local function IsOverride(uk) return U(uk).fontOverride == true end

    local function EnableOverride(uk)
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
            if rootKey then
                v = U(uk)[rootKey]
            else
                v = U(uk)[key]
            end
            if v ~= nil then return v end
        end
        if rootKey then
            local rv = MSUF_DB[rootKey]
            return (rv ~= nil) and rv or def
        end
        local v = G()[key]
        return (v ~= nil) and v or def
    end

    local function ScopeSet(key, val, rootKey)
        local uk = GetUnitKey()
        if uk then
            if not IsOverride(uk) then EnableOverride(uk) end
            if rootKey then
                U(uk)[rootKey] = val
            else
                U(uk)[key] = val
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
                local hasOvr = (not isGF) and (bk ~= "shared") and IsOverride(bk)
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
                U(uk).fontOverride = true
            else
                EnableOverride(uk)
            end
        else
            U(uk).fontOverride = false
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
    local function GFConf()
        local gf = ns and ns.GF; return gf and gf.GetConf(GFKind())
    end
    local function GFVal(key)
        local gf = ns and ns.GF; return gf and gf.Val(GFKind(), key)
    end
    GFApplyFont = function()
        local gf = ns and ns.GF
        if gf and type(gf.RefreshFonts) == "function" then gf.RefreshFonts() end
    end
    GFApplyLayout = function()
        local gf = ns and ns.GF
        if gf and type(gf.MarkAllDirty) == "function" then gf.MarkAllDirty((gf.DIRTY_LAYOUT or 32) + (gf.DIRTY_FONT or 4)) end
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
        fontChoices = {}
        for _, info in ipairs(_G.MSUF_FONT_LIST or _G.FONT_LIST or {}) do
            fontChoices[#fontChoices + 1] = { key = info.key, label = info.name, path = info.path }
        end
        local LSM = (ns and ns.LSM) or _G.MSUF_LSM
        if LSM then
            if LSM.Register then
                for _, d in ipairs(fontChoices) do
                    if d.key and d.key ~= "" and d.path and d.path ~= "" then
                        if LSM.Fetch then
                            local ok, v = pcall(LSM.Fetch, LSM, "font", d.key, true)
                            if not (ok and v) then pcall(LSM.Register, LSM, "font", d.key, d.path) end
                        end
                    end
                end
            end
            local used = {}; for _, e in ipairs(fontChoices) do used[e.key] = true end
            local names = LSM:List("font"); table.sort(names)
            for _, name in ipairs(names) do
                if not used[name] then fontChoices[#fontChoices + 1] = { key = name, label = name }; used[name] = true end
            end
        end
    end
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
        get = function() return G().fontKey or "FRIZQT" end,
        set = function(v)
            G().fontKey = v; UpdateFonts()
            if C_Timer and C_Timer.After then C_Timer.After(0, UpdateFonts) end
        end,
    })

    -- GF font dropdown (same position, shown only for GF scopes)
    local gfFontDrop = UI.Dropdown({
        name = "MSUF_GF_FontDrop", parent = fontBody,
        anchor = fontBody, anchorPoint = "TOPLEFT", x = 14, y = -8, width = 300,
        items = function()
            local items = { { key = "", label = "(Global Default)" } }
            local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
            if LSM then
                local list = LSM:List("font")
                for i = 1, #list do items[#items + 1] = { key = list[i], label = list[i] } end
            end
            return items
        end,
        get = function() return GFVal("fontKey") or "" end,
        set = function(v) local c = GFConf(); if c then c.fontKey = v end; GFApplyFont() end,
    })
    gfFontDrop:Hide()
    _gfRefreshFns[#_gfRefreshFns + 1] = function() if gfFontDrop and gfFontDrop.Refresh then gfFontDrop:Refresh() end end

    -- Widget visibility tracking
    local _ufOnlyWidgets = { fontDrop }
    local _gfOnlyWidgets = { gfFontDrop }

    -- =====================================================================
    -- SECTION 2: Text Sizes (default open) — scope-aware
    -- =====================================================================
    local sizeBox, sizeBody = MakeCollapsibleBox(content, fontBox, CONTENT_W, 300, TR("Text Sizes"), true)

    local UpdateSizeOverrideInfo
    local sizeHint, nameSizeSlider, hpSizeSlider, powerSizeSlider, castbarSizeSlider
    local RefreshSizeScopeUI

    local function GetScopedCastbarFontSizeKey(scopeKey)
        if scopeKey == "player" or scopeKey == "target" or scopeKey == "focus" then
            local fn = _G.MSUF_GetCastbarPrefix
            local prefix = type(fn) == "function" and fn(scopeKey) or nil
            if prefix then return prefix .. "SpellNameFontSize" end
        elseif scopeKey == "boss" then
            return "bossCastSpellNameFontSize"
        end
        return nil
    end

    local function SizeScopeSupports(dbKey, scopeKey)
        scopeKey = scopeKey or GetScopeKey()
        if scopeKey == "gf_party" or scopeKey == "gf_raid" then return false end
        if dbKey == "castbarSpellNameFontSize" then
            if scopeKey == "shared" then return true end
            return GetScopedCastbarFontSizeKey(scopeKey) ~= nil
        end
        return true
    end

    local function GetScopedFontSizeValue(dbKey, default)
        EnsureDB()
        local g = G()
        local scopeKey = GetScopeKey()
        if scopeKey == "shared" then
            return tonumber(g[dbKey]) or default or 14
        end
        if dbKey == "castbarSpellNameFontSize" then
            local castKey = GetScopedCastbarFontSizeKey(scopeKey)
            if castKey then
                local v = g[castKey]
                if v ~= nil then return tonumber(v) or default or 14 end
            end
            return tonumber(g[dbKey]) or default or 14
        end
        local u = MSUF_DB and MSUF_DB[scopeKey]
        local v = u and u[dbKey]
        if v ~= nil then return tonumber(v) or default or 14 end
        return tonumber(g[dbKey]) or default or 14
    end

    local function SetScopedFontSizeValue(dbKey, value)
        EnsureDB()
        local v = floor((tonumber(value) or 0) + 0.5)
        local scopeKey = GetScopeKey()
        if scopeKey == "shared" then
            G()[dbKey] = v
            return true
        end
        if dbKey == "castbarSpellNameFontSize" then
            local castKey = GetScopedCastbarFontSizeKey(scopeKey)
            if not castKey then return false end
            G()[castKey] = v
            return true
        end
        U(scopeKey)[dbKey] = v
        return true
    end

    local function SetSizeSliderEnabled(sl, enabled)
        if not sl then return end
        if sl.EnableMouse then sl:EnableMouse(enabled) end
        if sl.editBox then
            if enabled then
                if sl.editBox.EnableMouse then sl.editBox:EnableMouse(true) end
                if sl.editBox.Enable then sl.editBox:Enable() end
            else
                if sl.editBox.EnableMouse then sl.editBox:EnableMouse(false) end
                if sl.editBox.Disable then sl.editBox:Disable() end
            end
        end
        if sl.minusButton then
            if enabled and sl.minusButton.Enable then sl.minusButton:Enable()
            elseif (not enabled) and sl.minusButton.Disable then sl.minusButton:Disable() end
        end
        if sl.plusButton then
            if enabled and sl.plusButton.Enable then sl.plusButton:Enable()
            elseif (not enabled) and sl.plusButton.Disable then sl.plusButton:Disable() end
        end
        if sl.SetAlpha then sl:SetAlpha(enabled and 1 or 0.4) end
    end

    RefreshSizeScopeUI = function()
        if not sizeBox then return end
        local scopeKey = GetScopeKey()
        local gfScope = IsGFScope and IsGFScope() or false
        sizeBox:SetShown(not gfScope)
        if gfScope then return end

        if sizeHint and sizeHint.SetText then
            if scopeKey == "shared" then
                sizeHint:SetText("Shared defaults. Unitframes inherit these sizes unless that scope stores its own override.")
            else
                local label = SCOPE_LABELS[scopeKey] or scopeKey or "Unit"
                if SizeScopeSupports("castbarSpellNameFontSize", scopeKey) then
                    sizeHint:SetText("Editing " .. label .. " size overrides. Unchanged values still fall back to Shared.")
                else
                    sizeHint:SetText("Editing " .. label .. " text size overrides. Castbar size stays on Shared for this scope.")
                end
            end
        end

        if nameSizeSlider and nameSizeSlider.Refresh then nameSizeSlider:Refresh() end
        if hpSizeSlider and hpSizeSlider.Refresh then hpSizeSlider:Refresh() end
        if powerSizeSlider and powerSizeSlider.Refresh then powerSizeSlider:Refresh() end
        if castbarSizeSlider and castbarSizeSlider.Refresh then castbarSizeSlider:Refresh() end
        SetSizeSliderEnabled(castbarSizeSlider, SizeScopeSupports("castbarSpellNameFontSize", scopeKey))
    end

    do
    sizeHint = sizeBody:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    sizeHint:SetJustifyH("LEFT"); sizeHint:SetWidth(CONTENT_W - 40)
    sizeHint:SetText("Shared defaults. Unitframes inherit these sizes unless that scope stores its own override.")
    sizeHint:SetPoint("TOPLEFT", sizeBody, "TOPLEFT", 16, -6)

    local function MakeSizeSlider(name, label, dbKey, anchor, ox, oy, min, max, default)
        local sl = UI.Slider({
            name = name, parent = sizeBody,
            anchor = anchor, anchorPoint = "TOPLEFT", x = ox, y = oy,
            width = 110, min = min or 8, max = max or 32, step = 1, default = default or 14,
            get = function() return GetScopedFontSizeValue(dbKey, default or 14) end,
            set = function(v)
                if not SetScopedFontSizeValue(dbKey, v) then
                    if RefreshSizeScopeUI then RefreshSizeScopeUI() end
                    return
                end
                UpdateFonts()
                if dbKey == "castbarSpellNameFontSize" then
                    EnsureCastbars()
                    if type(_G.MSUF_UpdateCastbarVisuals) == "function" then _G.MSUF_UpdateCastbarVisuals() end
                end
            end,
            formatText = function() return label end,
        })
        local n = sl:GetName()
        if n then
            local low = _G[n .. "Low"]; if low then low:Hide() end
            local high = _G[n .. "High"]; if high then high:Hide() end
            local text = _G[n .. "Text"]
            if text then text:ClearAllPoints(); text:SetPoint("BOTTOM", sl, "TOP", 0, 6); text:SetJustifyH("CENTER") end
        end
        if sl.editBox then sl.editBox:SetSize(44, 18) end
        if sl.minusButton then sl.minusButton:SetSize(18, 18) end
        if sl.plusButton then sl.plusButton:SetSize(18, 18) end
        return sl
    end

    local colGap = 30
    local firstRowY = -28
    local secondRowY = -118
    nameSizeSlider    = MakeSizeSlider("MSUF_NameFontSizeSlider",    "Name",    "nameFontSize",              sizeHint, 0,             firstRowY,  8, 32, 14)
    hpSizeSlider      = MakeSizeSlider("MSUF_HealthFontSizeSlider",  "HP",      "hpFontSize",                sizeHint, 110 + colGap,  firstRowY,  8, 32, 14)
    powerSizeSlider   = MakeSizeSlider("MSUF_PowerFontSizeSlider",   "Power",   "powerFontSize",             nameSizeSlider, 0,        secondRowY, 8, 32, 14)
    castbarSizeSlider = MakeSizeSlider("MSUF_CastbarSpellNameFontSizeSlider", "Castbar", "castbarSpellNameFontSize", powerSizeSlider, 110 + colGap, 0, 0, 30, 0)
    castbarSizeSlider:ClearAllPoints()
    castbarSizeSlider:SetPoint("TOPLEFT", powerSizeSlider, "TOPRIGHT", colGap, 0)

    local function MakeOverrideInfo(parent)
        local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        fs:SetWidth(120); fs:SetJustifyH("CENTER"); fs:SetText("")
        fs:EnableMouse(true)
        fs:SetScript("OnEnter", function(self)
            if self._fullList and self._fullList ~= "" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(TR("Overrides"), 1, 0.9, 0.4)
                GameTooltip:AddLine(self._fullList, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        fs:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return fs
    end

    local nameOvr  = MakeOverrideInfo(sizeBody)
    local hpOvr    = MakeOverrideInfo(sizeBody)
    local powerOvr = MakeOverrideInfo(sizeBody)
    nameOvr:SetPoint("TOP", nameSizeSlider.editBox, "BOTTOM", 0, -2)
    hpOvr:SetPoint("TOP", hpSizeSlider.editBox, "BOTTOM", 0, -2)
    powerOvr:SetPoint("TOP", powerSizeSlider.editBox, "BOTTOM", 0, -2)

    UpdateSizeOverrideInfo = function()
        EnsureDB()
        local keys = { "player", "target", "targettarget", "focus", "pet", "boss" }
        local pretty = { player = "Player", target = "Target", targettarget = "ToT", focus = "Focus", pet = "Pet", boss = "Boss" }
        local function List(field)
            local out = {}
            for _, k in ipairs(keys) do
                local c = MSUF_DB[k]
                if c and c[field] ~= nil then out[#out + 1] = pretty[k] or k end
            end
            return out
        end
        local function Fmt(list)
            if #list == 0 then return "Overrides: -", nil end
            if #list == 1 then return "Overrides: " .. list[1], list[1] end
            return "Overrides: " .. list[1] .. " +" .. (#list - 1), table.concat(list, ", ")
        end
        local s, f
        s, f = Fmt(List("nameFontSize"));  nameOvr:SetText(s);  nameOvr._fullList = f or ""
        s, f = Fmt(List("hpFontSize"));    hpOvr:SetText(s);    hpOvr._fullList = f or ""
        s, f = Fmt(List("powerFontSize")); powerOvr:SetText(s); powerOvr._fullList = f or ""
    end

    if not StaticPopupDialogs["MSUF_RESET_FONT_OVERRIDES"] then
        StaticPopupDialogs["MSUF_RESET_FONT_OVERRIDES"] = {
            text = "Reset all font size overrides?\n\nThis clears per-unit overrides for Name/Health/Power AND per-castbar overrides for Cast Name/Time so everything inherits the global defaults.",
            button1 = YES, button2 = NO, whileDead = true, hideOnEscape = true, preferredIndex = 3,
            OnAccept = function()
                EnsureDB()
                for _, k in ipairs({ "player", "target", "targettarget", "focus", "pet", "boss" }) do
                    local c = MSUF_DB[k]
                    if c then c.nameFontSize = nil; c.hpFontSize = nil; c.powerFontSize = nil end
                end
                local gg = G()
                for _, u in ipairs({ "player", "target", "focus" }) do
                    local pfx = type(_G.MSUF_GetCastbarPrefix) == "function" and _G.MSUF_GetCastbarPrefix(u) or nil
                    if pfx then gg[pfx .. "SpellNameFontSize"] = nil; gg[pfx .. "TimeFontSize"] = nil end
                end
                gg.bossCastSpellNameFontSize = nil; gg.bossCastTimeFontSize = nil
                UpdateFonts(); EnsureCastbars()
                if type(_G.MSUF_UpdateCastbarVisuals) == "function" then _G.MSUF_UpdateCastbarVisuals() end
                if RefreshSizeScopeUI then RefreshSizeScopeUI() end
                UpdateSizeOverrideInfo()
            end,
        }
    end

    local resetSizeBtn = UI.Button({
        name = "MSUF_ResetFontOverridesBtn", parent = sizeBody,
        text = TR("Reset overrides"), width = 280, height = 20,
        onClick = function() StaticPopup_Show("MSUF_RESET_FONT_OVERRIDES") end,
    })
    resetSizeBtn:ClearAllPoints(); resetSizeBtn:SetPoint("TOPLEFT", powerSizeSlider, "BOTTOMLEFT", 0, -40)
    panel.nameFontSizeSlider = nameSizeSlider
    panel.hpFontSizeSlider = hpSizeSlider
    panel.powerFontSizeSlider = powerSizeSlider
    panel.castbarSpellNameFontSizeSlider = castbarSizeSlider
    end -- do block for sizeBody locals

    -- =====================================================================
    -- SECTION 3: Text Style (scope-aware, default collapsed)
    -- =====================================================================
    local styleBox, styleBody = MakeCollapsibleBox(content, sizeBox, CONTENT_W, 148, TR("Text Style"), false)

    local boldCheck = UI.Check({
        name = "MSUF_BoldTextCheck", parent = styleBody,
        anchor = styleBody, anchorPoint = "TOPLEFT", x = 16, y = -8, maxTextWidth = 400,
        label = TR("Use bold text (THICKOUTLINE)"),
        get = function() return ScopeGet("boldText", false) and true or false end,
        set = function(v)
            ScopeSet("boldText", v)
            InvalidateTextSpecs()
            LiveSyncFontVisuals({ layout = "FONT_STYLE" })
        end,
    })

    local noOutlineCheck = UI.Check({
        name = "MSUF_NoOutlineCheck", parent = styleBody,
        anchor = boldCheck, x = 0, y = -10, maxTextWidth = 400,
        label = TR("Disable black outline around text"),
        get = function() return ScopeGet("noOutline", false) and true or false end,
        set = function(v)
            ScopeSet("noOutline", v)
            InvalidateTextSpecs()
            LiveSyncFontVisuals({ layout = "FONT_STYLE" })
        end,
    })

    local textBackdropCheck = UI.Check({
        name = "MSUF_TextBackdropCheck", parent = styleBody,
        anchor = noOutlineCheck, x = 0, y = -10, maxTextWidth = 400,
        label = TR("Add text shadow (backdrop)"),
        get = function() return ScopeGet("textBackdrop", true) and true or false end,
        set = function(v)
            ScopeSet("textBackdrop", v)
            InvalidateTextSpecs()
            LiveSyncFontVisuals({ layout = "FONT_STYLE" })
        end,
    })
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = boldCheck
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = noOutlineCheck
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
        set = function(v) local c = GFConf(); if c then c.fontOutline = (v == "") and nil or v end; GFApplyFont() end,
    })
    gfOutlineDrop:Hide()
    local gfGlobalColorChk = UI.Check({
        name = "MSUF_GF_Style_GlobalColor", parent = styleBody,
        anchor = gfOutlineDrop, x = 16, y = -10, maxTextWidth = 400,
        label = TR("Use Global Font Color (Colors menu)"),
        get = function() return GFVal("useGlobalFontColor") ~= false end,
        set = function(v) local c = GFConf(); if c then c.useGlobalFontColor = v end; GFApplyFont() end,
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
    -- SECTION 4: Name Colors (scope-aware, default collapsed)
    -- =====================================================================
    local colorsBox, colorsBody = MakeCollapsibleBox(content, styleBox, CONTENT_W, 220, TR("Name & Power Colors"), false)

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
        set = function(v) local c = GFConf(); if c then c.nameColorMode = v end; GFApplyFont() end,
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
            local c = GFConf(); if not c then return end
            c.nameColorR = nr; c.nameColorG = ng; c.nameColorB = nb; GFApplyFont(); GFRefreshSwatch()
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
    -- SECTION 5: Name Shortening (scope-aware, default collapsed)
    -- =====================================================================
    local nameBox, nameBody = MakeCollapsibleBox(content, colorsBox, CONTENT_W, 280, TR("Name Shortening"), false)

    local shortenMaxSlider, shortenMaskSlider, shortenClipDrop

    local function SyncShortenEnabled()
        local on = ScopeGet("shortenNames", false, "shortenNames") and true or false
        if shortenMaxSlider then shortenMaxSlider:SetAlpha(on and 1 or 0.45) end
        if shortenMaskSlider then shortenMaskSlider:SetAlpha(on and 1 or 0.45) end
        if shortenClipDrop then shortenClipDrop:SetEnabled(on) end
    end

    local shortenCheck = UI.Check({
        name = "MSUF_ShortenNamesCheck", parent = nameBody,
        anchor = nameBody, anchorPoint = "TOPLEFT", x = 16, y = -8, maxTextWidth = 400,
        label = TR("Shorten unit names (except Player)"),
        get = function() return ScopeGet("shortenNames", false, "shortenNames") and true or false end,
        set = function(v)
            ScopeSet("shortenNames", v, "shortenNames")
            SyncShortenEnabled()
            InvalidateTextSpecs()
            LiveSyncFontVisuals({ layout = "SHORTEN_NAMES" })
        end,
    })

    local shortenClipLabel = UI.Label({ parent = nameBody, text = TR("Truncation style"), font = "GameFontNormal", anchor = shortenCheck, x = 16, y = -10 })

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
            InvalidateTextSpecs()
            if ScopeGet("shortenNames", false, "shortenNames") then
                LiveSyncFontVisuals({ layout = "SHORTEN_CLIP" })
            end
        end,
    })

    shortenMaxSlider = UI.Slider({
        name = "MSUF_ShortenNameMaxCharsSlider", parent = nameBody, compact = true,
        anchor = shortenClipDrop, x = 16, y = -12, width = 200,
        label = TR("Max name length"), min = 6, max = 30, step = 1, default = 6,
        lowText = "6", highText = "30",
        get = function() return ScopeGet("shortenNameMaxChars", 6) end,
        set = function(v)
            ScopeSet("shortenNameMaxChars", floor(v + 0.5))
            InvalidateTextSpecs()
            if ScopeGet("shortenNames", false, "shortenNames") then
                LiveSyncFontVisuals({ layout = "SHORTEN_CHARS" })
            end
        end,
    })

    shortenMaskSlider = UI.Slider({
        name = "MSUF_ShortenNameFrontMaskSlider", parent = nameBody, compact = true,
        anchor = shortenMaxSlider, x = 0, y = -20, width = 200,
        label = TR("Reserved space"), min = 0, max = 40, step = 1, default = 8,
        lowText = "0", highText = "40",
        get = function() return ScopeGet("shortenNameFrontMaskPx", 8) end,
        set = function(v)
            ScopeSet("shortenNameFrontMaskPx", floor(v + 0.5))
            InvalidateTextSpecs()
            if ScopeGet("shortenNames", false, "shortenNames") then
                LiveSyncFontVisuals({ layout = "SHORTEN_MASK" })
            end
        end,
    })

    local infoBtn = CreateFrame("Button", "MSUF_ShortenNameInfoButton", nameBody)
    infoBtn:SetSize(16, 16)
    infoBtn:SetNormalTexture("Interface\\FriendsFrame\\InformationIcon")
    infoBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    infoBtn:SetPoint("TOPLEFT", shortenMaskSlider, "BOTTOMLEFT", 0, -6)
    infoBtn:SetScript("OnClick", function(self)
        if GameTooltip:IsOwned(self) and GameTooltip:IsShown() then GameTooltip:Hide(); return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(TR("Name Shortening"))
        local side = ScopeGet("shortenNameClipSide", "LEFT")
        if side == "RIGHT" then
            GameTooltip:AddLine("Keep start: shows the first letters (clips the end).", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Keep end: shows the last letters (clips the beginning).", 1, 1, 1, true)
            GameTooltip:AddLine("Reserved space protects the clipped edge (avoids overlaps).", 0.95, 0.95, 0.95, true)
        end
        GameTooltip:Show()
    end)

    SyncShortenEnabled()

    -- GF: nameMaxChars + nameNoEllipsis (shown only for GF scopes in this section)
    local gfMaxCharsLbl = nameBody:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gfMaxCharsLbl:SetPoint("TOPLEFT", nameBody, "TOPLEFT", 16, -8)
    gfMaxCharsLbl:SetText(TR("Group Frame Name Truncation"))
    gfMaxCharsLbl:Hide()
    local gfMaxCharsSlider = UI.Slider({
        name = "MSUF_GF_Shorten_MaxChars", parent = nameBody, compact = true,
        anchor = gfMaxCharsLbl, x = 0, y = -8, width = 270,
        label = TR("Name Max Chars"), min = 0, max = 30, step = 1, default = 0,
        lowText = "0", highText = "30",
        get = function() return GFVal("nameMaxChars") or 0 end,
        set = function(v) local c = GFConf(); if c then c.nameMaxChars = floor(v + 0.5) end; GFApplyLayout() end,
        formatText = function(v) return v == 0 and "Max Chars: Unlimited" or string.format("Max Chars: %d", v) end,
    })
    gfMaxCharsSlider:Hide()
    local gfNoEllipsis = UI.Check({
        name = "MSUF_GF_Shorten_NoEllipsis", parent = nameBody,
        anchor = gfMaxCharsSlider, x = 0, y = -6, maxTextWidth = 400,
        label = TR("No Ellipsis (truncate without ..)"),
        get = function() return GFVal("nameNoEllipsis") and true or false end,
        set = function(v) local c = GFConf(); if c then c.nameNoEllipsis = v end; GFApplyLayout() end,
    })
    gfNoEllipsis:Hide()
    _gfOnlyWidgets[#_gfOnlyWidgets + 1] = gfMaxCharsLbl
    _gfOnlyWidgets[#_gfOnlyWidgets + 1] = gfMaxCharsSlider
    _gfOnlyWidgets[#_gfOnlyWidgets + 1] = gfNoEllipsis
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = shortenCheck
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = shortenClipLabel
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = shortenClipDrop
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = shortenMaxSlider
    _ufOnlyWidgets[#_ufOnlyWidgets + 1] = shortenMaskSlider
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

        -- Text Sizes: scope-aware for UF, hidden for GF
        if RefreshSizeScopeUI then
            RefreshSizeScopeUI()
        else
            sizeBox:SetShown(not gfScope)
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

        -- Dim sections when any non-Shared scope without override
        local scopeDim = (not isShared and not isOvr)
        local dimAlpha = scopeDim and 0.40 or 1.0
        styleBox:SetAlpha(dimAlpha)
        colorsBox:SetAlpha(dimAlpha)

        -- Name Shortening: hide for Player scope, dim for non-override
        local isPlayer = (GetScopeKey() == "player")
        if isPlayer then
            nameBox:SetAlpha(0)
            nameBox:SetHeight(1)
            nameBox._msufHiddenForPlayer = true
        else
            if nameBox._msufHiddenForPlayer then
                nameBox._msufHiddenForPlayer = nil
                nameBox:SetHeight(280)
            end
            nameBox:SetAlpha(dimAlpha)
        end

        -- Refresh all widgets for current scope
        if not gfScope then
            if boldCheck and boldCheck.Refresh then boldCheck:Refresh() end
            if noOutlineCheck and noOutlineCheck.Refresh then noOutlineCheck:Refresh() end
            if textBackdropCheck and textBackdropCheck.Refresh then textBackdropCheck:Refresh() end
            if nameClassColorCheck and nameClassColorCheck.Refresh then nameClassColorCheck:Refresh() end
            if npcNameRedCheck and npcNameRedCheck.Refresh then npcNameRedCheck:Refresh() end
            if powerColorCheck and powerColorCheck.Refresh then powerColorCheck:Refresh() end
            if shortenCheck and shortenCheck.Refresh then shortenCheck:Refresh() end
            if shortenClipDrop and shortenClipDrop.Refresh then shortenClipDrop:Refresh() end
            if shortenMaxSlider and shortenMaxSlider.Refresh then shortenMaxSlider:Refresh() end
            if shortenMaskSlider and shortenMaskSlider.Refresh then shortenMaskSlider:Refresh() end
            SyncShortenEnabled()
            UpdateSizeOverrideInfo()
        else
            GFSyncAll()
        end

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
    panel.shortenNameFrontMaskSlider = shortenMaskSlider
end
