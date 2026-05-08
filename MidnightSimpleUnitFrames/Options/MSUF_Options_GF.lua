-- MSUF_Options_GF.lua — Group Frames Options Panel (Phase 6)
-- Accordion UX, Party/Raid scope tabs, ns.UI.* toolkit, preview management.
-- Midnight 12.0 secret-safe, zero combat overhead.
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF
local UI
local TR = ns.TR or function(v) return v end
local CreateFrame = CreateFrame
local ColorPickerFrame = ColorPickerFrame
local UIDropDownMenu_SetWidth = UIDropDownMenu_SetWidth
local type = type
local pairs = pairs
local ipairs = ipairs

local TEX_W8 = "Interface\\Buttons\\WHITE8x8"
local SECTION_W = 680
local SECTION_COLLAPSED_H = 28

if not StaticPopupDialogs["MSUF_GF_GROWTH_RELOAD"] then
    StaticPopupDialogs["MSUF_GF_GROWTH_RELOAD"] = {
        text = "Growth direction changed. A UI reload is required to apply.\n\nReload now?",
        button1 = "Reload",
        button2 = "Later",
        OnAccept = function() ReloadUI() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

------------------------------------------------------------------------
-- Color picker (same pattern as MSUF_Options_Colors.lua)
------------------------------------------------------------------------
local function OpenColorPicker(r, g, b, callback)
    if not ColorPickerFrame or type(callback) ~= "function" then return end
    local sR, sG, sB = tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = sR, g = sG, b = sB, opacity = 1, hasOpacity = false,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                callback(nr, ng, nb)
            end,
            cancelFunc = function(prev)
                if type(prev) == "table" then
                    callback(prev.r or sR, prev.g or sG, prev.b or sB)
                else callback(sR, sG, sB) end
            end,
            previousValues = { r = sR, g = sG, b = sB, opacity = 1 },
        })
    else
        local function onChange() local nr, ng, nb = ColorPickerFrame:GetColorRGB(); callback(nr, ng, nb) end
        ColorPickerFrame.func = onChange
        ColorPickerFrame.cancelFunc = function(prev)
            if type(prev) == "table" then callback(prev.r or sR, prev.g or sG, prev.b or sB)
            else callback(sR, sG, sB) end
        end
        ColorPickerFrame.previousValues = { r = sR, g = sG, b = sB }
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame:SetColorRGB(sR, sG, sB)
        ColorPickerFrame:Show()
    end
end

------------------------------------------------------------------------
-- Color swatch helper
------------------------------------------------------------------------
local function MakeColorSwatch(parent, anchor, anchorPt, ox, oy, label, getColors, onSet)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", anchor, anchorPt or "BOTTOMLEFT", ox, oy)
    lbl:SetText(TR(label))

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(32, 16)
    btn:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    btn._swatchTex = tex

    local function Refresh()
        local r, g, b = getColors()
        tex:SetColorTexture(r or 1, g or 1, b or 1)
    end
    btn:SetScript("OnShow", function() Refresh() end)
    btn:SetScript("OnClick", function()
        local r, g, b = getColors()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            onSet(nr, ng, nb)
            Refresh()
        end)
    end)
    btn.Refresh = Refresh
    Refresh()
    return lbl, btn
end

------------------------------------------------------------------------
-- Panel builder
------------------------------------------------------------------------
local _panel
local _built = false

function _G.MSUF_EnsureGFPanelBuilt()
    if _panel then return _panel end

    -- Resolve lazily (GF files load before Options, but after SlashMenu parse)
    GF = ns.GF
    UI = ns.UI
    TR = ns.TR or TR
    if not GF then return nil end

    -- One-shot migration: Cutaway Health was removed. Clear every saved
    -- cutaway* key across all GF kinds so old profiles do not keep stale
    -- settings around. Runs
    -- once per session on first GF panel build; idempotent on subsequent
    -- opens because the keys are already nil after the first pass.
    do
        local KINDS = { "party", "raid", "mythicraid" }
        local CUTAWAY_KEYS = {
            "cutawayEnabled", "cutawayFadeTime",
            "cutawayColorR", "cutawayColorG", "cutawayColorB", "cutawayColorA",
        }
        for i = 1, #KINDS do
            local conf = GF.GetConf and GF.GetConf(KINDS[i])
            if type(conf) == "table" then
                for j = 1, #CUTAWAY_KEYS do
                    conf[CUTAWAY_KEYS[j]] = nil
                end
            end
        end
    end

    _panel = CreateFrame("Frame", "MSUF_GFOptionsPanel", UIParent)
    _panel:SetSize(640, 800)
    _panel:Hide()

    local _activeKind = "party"
    local _allRefreshFns = {}

    local function K() return _activeKind end
    local function C() return GF.GetConf(K()) end
    local function V(key) return GF.Val(K(), key) end
    local function IsRaidLike(kind) return kind == "raid" or kind == "mythicraid" end
    local function ScopeLabel(kind)
        if kind == "mythicraid" then return "Mythic Raid" end
        return (kind == "raid") and "Raid" or "Party"
    end
    local function W(key, val, refreshFn)
        local conf = GF.GetConf(K())
        conf[key] = val
        if type(refreshFn) == "function" then refreshFn()
        else GF.RefreshVisuals() end
    end

    local function SyncGFEditPopup()
        local fn = _G.MSUF_EM2_SyncGFPopups
        if type(fn) == "function" then fn() end
    end

    local function RefreshAllWidgets()
        for i = 1, #_allRefreshFns do
            local fn = _allRefreshFns[i]
            if type(fn) == "function" then fn() end
        end
    end
    GF._RefreshOptionWidgets = RefreshAllWidgets

    -- ── EM2 live-sync ──
    -- Both the Group-Frame Options panel and Edit Mode 2 movers write to the
    -- same per-kind config keys (nameOffsetX/Y, hpOffsetX/Y, powerOffsetX/Y,
    -- statusOffsetX/Y, etc.) and signal layout changes via GF.MarkAllDirty.
    -- Hook MarkAllDirty so any external mutation (EM2 drag, slash command,
    -- profile reload) triggers a coalesced widget refresh — keeping sliders
    -- and dropdowns in sync with whatever the user just dragged in EM2.
    --
    -- Coalesced via OnUpdate: many MarkAllDirty calls per drag (one per axis,
    -- one per snap, etc.) collapse into a single RefreshAllWidgets per frame.
    -- Self-loops are harmless: the panel's own slider set-handlers also call
    -- MarkAllDirty, which schedules a sync, which re-reads the value we just
    -- wrote and SetValueClean's it back — a no-op on the slider state.
    do
        local _syncPending = false
        local _syncFrame
        local function ScheduleWidgetSync()
            if _syncPending then return end
            if not _panel or not _panel:IsShown() then return end
            _syncPending = true
            if not _syncFrame then _syncFrame = CreateFrame("Frame") end
            _syncFrame:SetScript("OnUpdate", function(self)
                self:SetScript("OnUpdate", nil)
                _syncPending = false
                RefreshAllWidgets()
            end)
        end
        if type(GF.MarkAllDirty) == "function" then
            local _origMAD = GF.MarkAllDirty
            GF.MarkAllDirty = function(...)
                _origMAD(...)
                ScheduleWidgetSync()
            end
        end
        -- Public hook: EM2 / external code can request a panel resync without
        -- having to call MarkAllDirty (e.g., after a checkbox toggle that
        -- doesn't dirty layout). Coalesced like the MarkAllDirty path.
        GF._RequestOptionsResync = ScheduleWidgetSync
    end

    -- Track widgets that need scope-refresh
    local function TrackRefresh(widget)
        if widget and widget.Refresh then
            _allRefreshFns[#_allRefreshFns + 1] = function() if widget:IsShown() then widget:Refresh() end end
        end
    end
    local function TrackCheckbox(cb)
        if cb and cb.SetChecked and cb.GetChecked then
            _allRefreshFns[#_allRefreshFns + 1] = function()
                if not cb:IsShown() then return end
                local spec = cb._msufSpec
                if spec and spec.get then cb:SetChecked(spec.get() and true or false) end
            end
        end
    end

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "MSUF_GFScrollFrame", _panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", _panel, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", _panel, "BOTTOMRIGHT", -28, 0)
    if scrollFrame.EnableMouseWheel then scrollFrame:EnableMouseWheel(true) end

    local scrollChild = CreateFrame("Frame", "MSUF_GFScrollChild", scrollFrame)
    scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    scrollChild:SetSize(SECTION_W + 32, 1)
    scrollFrame:SetScrollChild(scrollChild)

    if scrollFrame.SetScript then
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            local step = 40
            local cur = self.GetVerticalScroll and self:GetVerticalScroll() or 0
            local v = cur - ((tonumber(delta) or 0) * step)
            if v < 0 then v = 0 end
            local mx = self.GetVerticalScrollRange and self:GetVerticalScrollRange() or 0
            if v > mx then v = mx end
            if self.SetVerticalScroll then self:SetVerticalScroll(v) end
        end)
    end

    local RefreshScrollLayout

    ----------------------------------------------------------------
    -- Preview box (drag-to-position mock frame)
    ----------------------------------------------------------------
    local _previewBox
    local _sectionLookup = {} -- [sectionKey] = boxFrame

    ----------------------------------------------------------------
    -- Radio-section: only one section open at a time
    ----------------------------------------------------------------
    local sections = {}

    local function CollapseAllExcept(keepBox)
        for i = 1, #sections do
            local b = sections[i]
            if b and not b._msufIsDivider and b ~= keepBox and not b._msufCollapsed then
                b._msufCollapsed = true
                if b._msufApplyCollapseState then b._msufApplyCollapseState() end
            end
        end
    end

    --- Find which section is open and tell the mock preview to focus on it
    local function _UpdatePreviewFocus()
        local openKey = nil
        for key, box in pairs(_sectionLookup) do
            if box and box:IsShown() and not box._msufCollapsed then
                openKey = key
                break
            end
        end
        if GF.SetPreviewFocus then GF.SetPreviewFocus(openKey) end
    end

    local function OpenSectionByKey(sectionKey)
        if not sectionKey then return end
        local box = _sectionLookup[sectionKey]
        if not box then return end
        CollapseAllExcept(box)
        if box._msufCollapsed then
            box._msufCollapsed = false
            if box._msufApplyCollapseState then box._msufApplyCollapseState() end
        end
        _UpdatePreviewFocus()
    end

    ----------------------------------------------------------------
    -- Auto-height: measure bottommost descendant of a body frame
    ----------------------------------------------------------------
    local function _MeasureContentHeight(body)
        local top = body:GetTop()
        if not top then return nil end
        local minBot = top
        -- Recursive scan: find the bottommost visible element in the tree
        local function Scan(frame)
            local children = { frame:GetChildren() }
            for i = 1, #children do
                local c = children[i]
                if c:IsShown() then
                    local b = c:GetBottom()
                    if b and b < minBot then minBot = b end
                    Scan(c)
                end
            end
            local regions = { frame:GetRegions() }
            for i = 1, #regions do
                local r = regions[i]
                if r:IsShown() then
                    local b = r:GetBottom()
                    if b and b < minBot then minBot = b end
                end
            end
        end
        Scan(body)
        local h = top - minBot
        return h > 0 and h or nil
    end

    ----------------------------------------------------------------
    -- Collapsible section helper
    ----------------------------------------------------------------
    local function MakeCollapsibleSection(parent, expandedH, titleText, defaultOpen)
        local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        box:SetSize(SECTION_W, defaultOpen and expandedH or SECTION_COLLAPSED_H)
        box:SetBackdrop({
            bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        box:SetBackdropColor(0, 0, 0, 0.25)
        box:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)
        box._msufExpandedH = expandedH
        box._msufCollapsedH = SECTION_COLLAPSED_H
        box._msufCollapsed = not defaultOpen

        local hdr = CreateFrame("Button", nil, box)
        hdr:SetHeight(24)
        hdr:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
        hdr:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)

        local chevron = hdr:CreateTexture(nil, "OVERLAY")
        chevron:SetSize(12, 12)
        chevron:SetPoint("LEFT", hdr, "LEFT", 12, 0)
        chevron:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        if _G.MSUF_ApplyCollapseVisual then
            _G.MSUF_ApplyCollapseVisual(chevron, nil, defaultOpen)
        end

        local title = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("LEFT", chevron, "RIGHT", 6, 0)
        title:SetText(TR(titleText))

        local hint = hdr:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("RIGHT", hdr, "RIGHT", -12, 0)
        hint:SetText(defaultOpen and "" or TR("click to expand"))
        hint:SetTextColor(0.45, 0.52, 0.65)

        local divider = box:CreateTexture(nil, "ARTWORK")
        divider:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -28)
        divider:SetPoint("TOPRIGHT", box, "TOPRIGHT", -8, -28)
        divider:SetHeight(1)
        divider:SetColorTexture(1, 1, 1, 0.08)

        local body = CreateFrame("Frame", nil, box)
        body:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -30)
        body:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
        body:SetShown(defaultOpen)
        box._msufBody = body
        box._msufChevron = chevron
        box._msufHint = hint
        box._msufTitleFS = title
        box._msufBaseTitle = titleText

        local function ApplyState()
            local open = not box._msufCollapsed
            body:SetShown(open)
            box:SetHeight(open and box._msufExpandedH or box._msufCollapsedH)
            if _G.MSUF_ApplyCollapseVisual then
                _G.MSUF_ApplyCollapseVisual(chevron, hint, open)
            end
            if type(RefreshScrollLayout) == "function" then RefreshScrollLayout() end
        end

        hdr:SetScript("OnClick", function()
            if box._msufCollapsed then
                CollapseAllExcept(box)
                box._msufCollapsed = false
            else
                box._msufCollapsed = true
            end
            ApplyState()
            _UpdatePreviewFocus()
        end)
        do
            local hl = hdr:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.03)
        end

        -- Auto-height: measure content on every expand, update box height
        local function _DoRemeasure()
            C_Timer.After(0, function()
                if not body:IsShown() then return end
                local h = _MeasureContentHeight(body)
                if h and h > 10 then
                    local newH = h + 44 -- 30 header + 14 bottom pad
                    box._msufExpandedH = newH
                    if not box._msufCollapsed then
                        box:SetHeight(newH)
                        if type(RefreshScrollLayout) == "function" then RefreshScrollLayout() end
                    end
                end
            end)
        end
        body:HookScript("OnShow", function() _DoRemeasure() end)
        box._msufRemeasure = _DoRemeasure

        box._msufApplyCollapseState = ApplyState
        return box, body
    end

    ----------------------------------------------------------------
    -- Copy Settings: selective category copy (Party ↔ Raid)
    ----------------------------------------------------------------
    local function _GFDeepCopy(src)
        if not src then return src end
        if type(src) ~= "table" then return src end
        local dst = {}
        for k, v in pairs(src) do dst[k] = (type(v) == "table") and _GFDeepCopy(v) or v end
        return dst
    end

    local _COPY_EXCLUDE = {
        offsetX = true, offsetY = true, point = true,
        positionMode = true, _hlMigrated = true,
    }

    -- Category groups: key → list of config keys to copy
    local _COPY_CATEGORIES = {
        { key = "general",    label = "General (size, spacing, growth)",
          keys = { "enabled", "showPlayer", "showSolo", "width", "height", "spacing",
                   "growth", "groupFilter", "sortMode", "sortByRole", "roleOrder",
                   "separateMeleeRanged", "playerFirstInRole",
                   "unitsPerColumn", "maxColumns",
                   "reverseFill", "smoothFill", "hideInClientScene", "hideOfflineDelay",
                   "tooltipMode", "tooltipModifier",
                   "frameScaleMode", "frameScaleManual", "scaleAt10", "scaleAt20",
                   "scaleAt25", "scaleOver25" } },
        { key = "health",     label = "Health & Bars",
          keys = { "gfBarMode", "healthColorMode", "healthCustomR", "healthCustomG", "healthCustomB",
                   "gfDarkR", "gfDarkG", "gfDarkB", "gfUnifiedR", "gfUnifiedG", "gfUnifiedB",
                   "barTexture", "barBgTexture",
                   "powerHeight", "showPower", "showPowerText",
                   "powerTextLeft", "powerTextCenter", "powerTextRight", "powerTextDelimiter",
                   "powerFontSize", "powerOffsetX", "powerOffsetY",
                   "powerTextLayer", "powerSmoothFill",
                   "powerShowTank", "powerShowHealer", "powerShowDamager",
                   "healPredEnabled",
                   "dispelOverlayEnabled", "dispelOverlayStyle", "dispelOverlayOnHealth", "dispelOverlayAlpha" } },
        { key = "text",       label = "Text & Name",
          keys = { "showName", "nameFontSize", "nameAnchor", "nameOffsetX", "nameOffsetY",
                   "nameTextLayer",
                   "nameColorMode", "nameColorR", "nameColorG", "nameColorB",
                   "nameMaxChars", "nameNoEllipsis",
                   "showHPText", "hpFontSize", "textLeft", "textCenter", "textRight", "textDelimiter",
                   "hpTextReverse", "hpOffsetX", "hpOffsetY", "textLayer" } },
        { key = "font",       label = "Font Override",
          keys = { "fontOverride", "fontKey", "fontOutline", "useGlobalFontColor",
                   "fontR", "fontG", "fontB" } },
        { key = "border",     label = "Background & Opacity",
          keys = { "bgR", "bgG", "bgB", "bgA",
                   "hpBarAlpha", "hpBgAlpha", "hpTextIgnoreAlpha", "alphaPreserveHPColor" } },
        { key = "range",      label = "Range Fade",
          keys = { "rangeFadeEnabled", "rangeFadeAlpha", "rangeFadeLayerMode", "offlineAlpha", "alphaPreserveHPColor" } },
        { key = "indicators", label = "Indicators & Status Icons",
          keys = { "showGroupNumber", "groupNumberSize", "groupNumberAnchor",
                   "groupNumberX", "groupNumberY",
                   "iconStyle", "useMidnightIcons",
                   "statusText", "statusTextSize", "statusTextAnchor",
                   "statusOffsetX", "statusOffsetY", "statusTextLayer",
                   "statusGhostText", "statusGhostTextSize", "statusGhostTextAnchor",
                   "statusGhostOffsetX", "statusGhostOffsetY", "statusGhostTextLayer",
                   "statusAFKText", "statusAFKTextSize", "statusAFKTextAnchor",
                   "statusAFKOffsetX", "statusAFKOffsetY", "statusAFKTextLayer" },
          prefix = { "si_", "statusIcon", "indicator" } },
        { key = "auras",      label = "Auras (Buffs/Debuffs/Defensives)",
          tables = { "auras" } },
        { key = "highlight",  label = "Highlight & Aggro",
          prefix = { "hl", "dispel" } },
        { key = "dstripe",   label = "Debuff Stripe",
          prefix = { "debuffStripe" } },
        { key = "features",   label = "Corner/Spell/Private",
          tables = { "spellIndicators", "privateAuras" },
          keys = { "ciEnabled", "ciAlpha" },
          prefix = { "ci" } },
    }

    -- Default: all categories ON
    local _copyToggles = {}
    for _, cat in ipairs(_COPY_CATEGORIES) do _copyToggles[cat.key] = true end

    local function _GFDoCopySelective(srcKind, dstKind)
        local srcConf = GF.GetConf(srcKind)
        local dstConf = GF.GetConf(dstKind)
        if not srcConf or not dstConf then return end

        -- Build set of keys to copy based on active toggles
        local allowKeys = {}
        local allowPrefixes = {}
        local allowTables = {}
        for _, cat in ipairs(_COPY_CATEGORIES) do
            if _copyToggles[cat.key] then
                if cat.keys then
                    for _, k in ipairs(cat.keys) do allowKeys[k] = true end
                end
                if cat.prefix then
                    for _, p in ipairs(cat.prefix) do allowPrefixes[#allowPrefixes + 1] = p end
                end
                if cat.tables then
                    for _, t in ipairs(cat.tables) do allowTables[t] = true end
                end
            end
        end

        for k, v in pairs(srcConf) do
            if _COPY_EXCLUDE[k] then
                -- skip position keys
            elseif allowKeys[k] or allowTables[k] then
                dstConf[k] = (type(v) == "table") and _GFDeepCopy(v) or v
            else
                -- Check prefix match
                for _, p in ipairs(allowPrefixes) do
                    if k:sub(1, #p) == p then
                        dstConf[k] = (type(v) == "table") and _GFDeepCopy(v) or v
                        break
                    end
                end
            end
        end

        if GF.RebuildAll then GF.RebuildAll() end
        GF.RefreshVisuals()
        RefreshAllWidgets()
        if GF.RefreshPreviewBox then GF.RefreshPreviewBox() end
        if type(RefreshScrollLayout) == "function" then RefreshScrollLayout() end
    end

    -- Copy popup panel (replaces StaticPopup)
    local _copyPopup
    local function ShowCopyPopup(anchorFrame)
        if _copyPopup and _copyPopup:IsShown() then _copyPopup:Hide(); return end
        if not _copyPopup then
            local pop = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            pop:SetSize(350, 30 + #_COPY_CATEGORIES * 22 + 36)
            pop:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 } })
            pop:SetBackdropColor(0.06, 0.10, 0.20, 0.97)
            pop:SetBackdropBorderColor(0.30, 0.45, 0.70, 0.9)
            pop:SetFrameStrata("DIALOG")
            pop:SetFrameLevel(100)
            pop:EnableMouse(true)

            local title = pop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            title:SetPoint("TOP", pop, "TOP", 0, -8)
            pop._titleFS = title

            local y = -26
            pop._checks = {}
            for i, cat in ipairs(_COPY_CATEGORIES) do
                local cb = CreateFrame("CheckButton", nil, pop, "UICheckButtonTemplate")
                cb:SetSize(20, 20)
                cb:SetPoint("TOPLEFT", pop, "TOPLEFT", 10, y)
                cb:SetChecked(_copyToggles[cat.key])
                cb:SetScript("OnClick", function(self)
                    _copyToggles[cat.key] = self:GetChecked() and true or false
                end)
                if _G.MSUF_StyleCheckmark then _G.MSUF_StyleCheckmark(cb) end
                local fs = cb.text or cb.Text
                if fs then fs:SetText(cat.label); fs:SetFontObject("GameFontHighlightSmall") end
                pop._checks[i] = cb
                y = y - 22
            end

            -- Select All / None
            local allBtn = CreateFrame("Button", nil, pop, "BackdropTemplate")
            allBtn:SetSize(50, 18)
            allBtn:SetPoint("BOTTOMLEFT", pop, "BOTTOMLEFT", 10, 8)
            allBtn:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
            allBtn:SetBackdropColor(0.10, 0.16, 0.28, 1)
            allBtn:SetBackdropBorderColor(0.25, 0.40, 0.65, 0.7)
            local allFs = allBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            allFs:SetPoint("CENTER"); allFs:SetText("All")
            allBtn:SetScript("OnClick", function()
                for j, cat in ipairs(_COPY_CATEGORIES) do
                    _copyToggles[cat.key] = true; pop._checks[j]:SetChecked(true)
                end
            end)

            local noneBtn = CreateFrame("Button", nil, pop, "BackdropTemplate")
            noneBtn:SetSize(50, 18)
            noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 4, 0)
            noneBtn:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
            noneBtn:SetBackdropColor(0.10, 0.16, 0.28, 1)
            noneBtn:SetBackdropBorderColor(0.25, 0.40, 0.65, 0.7)
            local noneFs = noneBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            noneFs:SetPoint("CENTER"); noneFs:SetText("None")
            noneBtn:SetScript("OnClick", function()
                for j, cat in ipairs(_COPY_CATEGORIES) do
                    _copyToggles[cat.key] = false; pop._checks[j]:SetChecked(false)
                end
            end)

            pop._targetBtns = {}
            local function MakeTargetBtn(kind, x)
                local btn = CreateFrame("Button", nil, pop, "BackdropTemplate")
                btn:SetSize(76, 18)
                btn:SetPoint("BOTTOMLEFT", pop, "BOTTOMLEFT", x, 8)
                btn:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
                btn:SetBackdropColor(0.15, 0.30, 0.18, 1)
                btn:SetBackdropBorderColor(0.30, 0.60, 0.35, 0.9)
                local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetPoint("CENTER")
                fs:SetText("|cff44ee55" .. ((kind == "mythicraid") and "Mythic" or ScopeLabel(kind)) .. "|r")
                btn:SetFontString(fs)
                btn:SetScript("OnClick", function()
                    local src = _activeKind
                    _GFDoCopySelective(src, kind)
                    pop:Hide()
                    print("|cff00ff00MSUF:|r Copied selected settings from " .. ScopeLabel(src) .. " to " .. ScopeLabel(kind) .. ".")
                end)
                pop._targetBtns[kind] = btn
                return btn
            end

            MakeTargetBtn("party", 104)
            MakeTargetBtn("raid", 184)
            MakeTargetBtn("mythicraid", 264)

            local targetOrder = { "party", "raid", "mythicraid" }
            local function LayoutTargetBtns()
                local nextX = 104
                for _, kind in ipairs(targetOrder) do
                    local btn = pop._targetBtns[kind]
                    if btn and btn:IsShown() then
                        btn:ClearAllPoints()
                        btn:SetPoint("BOTTOMLEFT", pop, "BOTTOMLEFT", nextX, 8)
                        nextX = nextX + 80
                    end
                end
            end
            pop._layoutTargetBtns = LayoutTargetBtns

            _copyPopup = pop
        end

        local src = _activeKind
        _copyPopup._titleFS:SetText("Copy from " .. ScopeLabel(src))
        for i, cat in ipairs(_COPY_CATEGORIES) do
            _copyPopup._checks[i]:SetChecked(_copyToggles[cat.key])
        end
        for kind, btn in pairs(_copyPopup._targetBtns or {}) do
            btn:SetShown(kind ~= src)
        end
        if _copyPopup._layoutTargetBtns then _copyPopup._layoutTargetBtns() end
        _copyPopup:ClearAllPoints()
        _copyPopup:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", 0, -2)
        _copyPopup:Show()
    end

    ----------------------------------------------------------------
    -- Scope tabs (Party / Raid) + Copy button
    ----------------------------------------------------------------
    local scopeBar = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
    scopeBar:SetSize(SECTION_W, 32)
    scopeBar:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, -10)
    scopeBar:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    scopeBar:SetBackdropColor(0.04, 0.08, 0.18, 0.95)
    scopeBar:SetBackdropBorderColor(0.12, 0.25, 0.50, 0.6)

    local scopeLbl = scopeBar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    scopeLbl:SetPoint("LEFT", scopeBar, "LEFT", 10, 0)
    scopeLbl:SetText(TR("Editing:"))

    local scopeBtns = {}
    local function RefreshScopeBtns()
        for kind, btn in pairs(scopeBtns) do
            local active = (kind == _activeKind)
            local fs = btn:GetFontString()
            if active then
                btn:SetBackdropColor(0.15, 0.35, 0.65, 0.9)
                if fs then fs:SetTextColor(1, 0.82, 0) end
            else
                btn:SetBackdropColor(0.08, 0.12, 0.22, 0.7)
                if fs then fs:SetTextColor(0.6, 0.65, 0.7) end
            end
        end
    end

    -- Preview only when no real group exists for the active scope
    local function NeedsPreview(kind)
        local inRaid = (IsInRaid and IsInRaid()) or false
        if kind == "mythicraid" then
            return not (inRaid and GF.IsMythicRaidContext and GF.IsMythicRaidContext())
        end
        if kind == "raid" then
            return not (inRaid and not (GF.IsMythicRaidContext and GF.IsMythicRaidContext()))
        end
        return not (((IsInGroup and IsInGroup()) or false) and not inRaid)
    end

    local function SyncActiveScopeForEM2(kind)
        GF._optionsActiveKind = kind
        local fn = _G.MSUF_GF_EM2_SetActivePreviewKind
        if type(fn) == "function" then fn(kind) end
    end

    local function ShowPreviewIfNeeded(kind)
        if NeedsPreview(kind) then
            -- Hide SecureGroupHeaders to prevent doubling with preview frames
            if not InCombatLockdown() and GF.headers then
                if GF.headers.party then GF.headers.party:Hide() end
                if GF.headers.raid  then GF.headers.raid:Hide()  end
            end
            GF.ShowPreview(kind, (kind == "mythicraid" and 20) or (kind == "raid" and 30) or 5)
        elseif not InCombatLockdown() and GF.UpdateGroupVisibility then
            GF.UpdateGroupVisibility()
        end
    end

    local function HideAllPreviews(restoreHeaders)
        if restoreHeaders == nil then restoreHeaders = true end
        GF.HidePreview("party")
        GF.HidePreview("raid")
        GF.HidePreview("mythicraid")
        -- Restore headers
        if restoreHeaders and not InCombatLockdown() and GF.UpdateGroupVisibility then
            GF.UpdateGroupVisibility()
        end
    end

    local function RefreshAfterFullReset()
        RefreshAllWidgets()
        HideAllPreviews(false)
        SyncActiveScopeForEM2(_activeKind)
        ShowPreviewIfNeeded(_activeKind)
        if GF.PreviewScopeChanged then GF.PreviewScopeChanged() end
        if GF.RefreshPreviewBox then GF.RefreshPreviewBox() end
        if type(RefreshScrollLayout) == "function" then RefreshScrollLayout() end
    end

    if not StaticPopupDialogs["MSUF_GF_RESET_ALL_CONFIRM"] then
        StaticPopupDialogs["MSUF_GF_RESET_ALL_CONFIRM"] = {
            text = "Reset all Group Frame settings to defaults?\n\nThis resets Party, Raid, and Mythic Raid Group Frames for the active profile.",
            button1 = YES,
            button2 = NO,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    StaticPopupDialogs["MSUF_GF_RESET_ALL_CONFIRM"].OnAccept = function()
        if GF.ResetAllToDefaults and GF.ResetAllToDefaults() then
            RefreshAfterFullReset()
            print("|cffffd700MSUF:|r Group Frames reset to defaults.")
        end
    end

    local function SwitchScope(kind)
        _activeKind = kind
        RefreshScopeBtns()
        RefreshAllWidgets()
        HideAllPreviews(false)
        SyncActiveScopeForEM2(kind)
        ShowPreviewIfNeeded(kind)
        if GF.PreviewScopeChanged then GF.PreviewScopeChanged() end
    end

    do
        local prevBtn
        for _, info in ipairs({ { "party", "Party" }, { "raid", "Raid" }, { "mythicraid", "Mythic" } }) do
            local kind, label = info[1], info[2]
            local btn = CreateFrame("Button", nil, scopeBar, "BackdropTemplate")
            btn:SetSize((kind == "mythicraid") and 68 or 56, 20)
            btn:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
            btn:SetBackdropBorderColor(0.2, 0.35, 0.55, 0.5)
            local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("CENTER"); fs:SetText(TR(label))
            btn:SetFontString(fs)
            if not prevBtn then
                btn:SetPoint("LEFT", scopeLbl, "RIGHT", 8, 0)
            else
                btn:SetPoint("LEFT", prevBtn, "RIGHT", 2, 0)
            end
            btn:SetScript("OnClick", function() SwitchScope(kind) end)
            scopeBtns[kind] = btn
            prevBtn = btn
        end
    end

    do
        local scopeEventFrame = CreateFrame("Frame")
        local function RefreshMythicScopeState()
            RefreshScopeBtns()
            local panel = _G.MSUF_GFOptionsPanel
            if panel and panel.IsShown and panel:IsShown() then
                HideAllPreviews(false)
                SyncActiveScopeForEM2(_activeKind)
                ShowPreviewIfNeeded(_activeKind)
            end
        end
        scopeEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        scopeEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        scopeEventFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
        scopeEventFrame:SetScript("OnEvent", RefreshMythicScopeState)
        _allRefreshFns[#_allRefreshFns + 1] = RefreshMythicScopeState
    end
    -- Copy button (right side of scope bar, label changes with scope)
    local copyBtn = CreateFrame("Button", nil, scopeBar, "BackdropTemplate")
    copyBtn:SetSize(110, 20)
    copyBtn:SetPoint("RIGHT", scopeBar, "RIGHT", -8, 0)
    copyBtn:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    copyBtn:SetBackdropColor(0.12, 0.18, 0.30, 0.9)
    copyBtn:SetBackdropBorderColor(0.25, 0.40, 0.65, 0.7)
    local copyFS = copyBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    copyFS:SetPoint("CENTER")
    copyFS:SetTextColor(0.65, 0.78, 0.95)
    copyBtn:SetFontString(copyFS)
    copyBtn:SetScript("OnClick", function()
        ShowCopyPopup(copyBtn)
    end)
    copyBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.18, 0.28, 0.45, 1)
        self:SetBackdropBorderColor(0.35, 0.55, 0.80, 1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Copy Settings", 1, 1, 1)
        GameTooltip:AddLine("Select which categories to copy\nbetween Party, Raid, and Mythic Raid settings.", 0.7, 0.7, 0.8, true)
        GameTooltip:Show()
    end)
    copyBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.18, 0.30, 0.9)
        self:SetBackdropBorderColor(0.25, 0.40, 0.65, 0.7)
        GameTooltip:Hide()
    end)

    local function RefreshCopyBtn()
        copyFS:SetText("Copy To")
    end
    RefreshCopyBtn()

    local rightAnchor = copyBtn

    -- Patch RefreshScopeBtns to also refresh copy button
    local _origRefreshScope = RefreshScopeBtns
    RefreshScopeBtns = function()
        _origRefreshScope()
        RefreshCopyBtn()
    end
    RefreshScopeBtns()

    ----------------------------------------------------------------
    -- Category filtering (driven by sidebar, no in-panel tab bar)
    ----------------------------------------------------------------
    local _activeTab = "frame"

    -- Forward declarations for preview state (used by SwitchTab)
    local _previewCollapsed = false
    local RefreshPreviewToggle
    local _scopeHintFS

    local _TAB_DEFS = {
        { key = "frame",      keys = { "general", "layout", "sorting", "scaling", "border", "anchor", "tooltip" } },
        { key = "health",     keys = { "hcolor", "bars", "power", "text", "healpred", "dispel", "dstripe", "range" } },
        { key = "auras",      keys = { "blizzrenderer", "buffs", "debuffs", "ext", "textcolor", "priv", "masque", "autil" } },
        { key = "indicators", keys = { "indicators", "sicons", "si", "ci" } },
    }
    -- Reverse lookup: sectionKey → tabKey
    local _secToTab = {}
    for _, tab in ipairs(_TAB_DEFS) do
        for _, sk in ipairs(tab.keys) do _secToTab[sk] = tab.key end
    end

    -- (#4) Section memory: remember last open section per tab
    local _tabLastSection = {}

    -- (#3) Preview relevance per tab
    local _tabWantsPreview = { frame = true, health = true, auras = true, indicators = true }

    local function SwitchTab(tabKey)
        -- Save current open section before switching
        if _activeTab then
            for i = 1, #sections do
                local box = sections[i]
                if box and not box._msufIsDivider and not box._msufCollapsed then
                    local sk = box._msufSecKey
                    if sk and _secToTab[sk] == _activeTab then
                        _tabLastSection[_activeTab] = sk
                        break
                    end
                end
            end
        end

        _activeTab = tabKey

        -- Show/hide sections for this tab
        for i = 1, #sections do
            local box = sections[i]
            if box and not box._msufIsDivider then
                local sk = box._msufSecKey
                box:SetShown(sk and _secToTab[sk] == tabKey or false)
            elseif box and box._msufIsDivider then
                box:SetShown(false)
            end
        end

        -- (#1 + #4) Restore remembered section, or auto-open first
        local restored = false
        local lastSk = _tabLastSection[tabKey]
        if lastSk then
            local lastBox = _sectionLookup[lastSk]
            if lastBox and not lastBox._msufIsDivider then
                CollapseAllExcept(lastBox)
                lastBox._msufCollapsed = false
                if lastBox._msufApplyCollapseState then lastBox._msufApplyCollapseState() end
                restored = true
            end
        end
        if not restored then
            -- Auto-open first visible section
            for i = 1, #sections do
                local box = sections[i]
                if box and not box._msufIsDivider and box:IsShown() then
                    CollapseAllExcept(box)
                    box._msufCollapsed = false
                    if box._msufApplyCollapseState then box._msufApplyCollapseState() end
                    break
                end
            end
        end

        -- (#3) Auto-collapse preview on irrelevant pages
        if _tabWantsPreview[tabKey] == false and not _previewCollapsed then
            _previewCollapsed = true
            if type(RefreshPreviewToggle) == "function" then RefreshPreviewToggle() end
        elseif _tabWantsPreview[tabKey] and _previewCollapsed then
            _previewCollapsed = false
            if type(RefreshPreviewToggle) == "function" then RefreshPreviewToggle() end
        end

        -- (#5) Update scope context hint
        if _scopeHintFS then
            local TAB_LABELS = { frame = "layout", health = "health & text", auras = "buffs & debuffs", indicators = "indicators" }
            local scopeLabel = ScopeLabel(_activeKind)
            _scopeHintFS:SetText("|cff666680Editing " .. scopeLabel .. " " .. (TAB_LABELS[tabKey] or tabKey) .. "|r")
        end

        _UpdatePreviewFocus()
        if type(RefreshScrollLayout) == "function" then RefreshScrollLayout() end
    end

    ----------------------------------------------------------------
    -- (#5) Scope context hint (below scope bar)
    ----------------------------------------------------------------
    _scopeHintFS = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    _scopeHintFS:SetPoint("TOPLEFT", scopeBar, "BOTTOMLEFT", 4, -4)
    _scopeHintFS:SetText("|cff666680Editing " .. ScopeLabel(_activeKind) .. " layout|r")

    -- Patch SwitchScope to also update hint
    local _origSwitchScope = SwitchScope
    SwitchScope = function(kind)
        _origSwitchScope(kind)
        if _scopeHintFS then
            local TAB_LABELS = { frame = "layout", health = "health & text", auras = "buffs & debuffs", indicators = "indicators" }
            local scopeLabel = ScopeLabel(_activeKind)
            _scopeHintFS:SetText("|cff666680Editing " .. scopeLabel .. " " .. (TAB_LABELS[_activeTab] or _activeTab) .. "|r")
        end
    end

    ----------------------------------------------------------------
    -- MSUF Edit Mode button on scope bar
    ----------------------------------------------------------------
    local editBtn = CreateFrame("Button", nil, scopeBar, "BackdropTemplate")
    editBtn:SetSize(116, 20)
    editBtn:SetPoint("RIGHT", copyBtn, "LEFT", -6, 0)
    editBtn:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    editBtn:SetBackdropColor(0.12, 0.24, 0.26, 0.92)
    editBtn:SetBackdropBorderColor(0.24, 0.55, 0.58, 0.8)
    local editFS = editBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    editFS:SetPoint("CENTER")
    editFS:SetTextColor(0.75, 0.95, 0.95)
    editBtn:SetFontString(editFS)

    local function IsMSUFEditModeActive()
        if type(_G.MSUF_IsMSUFEditModeActive) == "function" then
            return _G.MSUF_IsMSUFEditModeActive() and true or false
        end
        local em2 = _G.MSUF_EM2
        if em2 and em2.State and type(em2.State.IsActive) == "function" then
            return em2.State.IsActive() and true or false
        end
        return _G.MSUF_UnitEditModeActive == true
    end

    local function RefreshEditModeButton()
        editFS:SetText(IsMSUFEditModeActive() and TR("Exit Edit Mode") or TR("MSUF Edit Mode"))
    end

    editBtn:SetScript("OnClick", function()
        if InCombatLockdown and InCombatLockdown() then
            if UIErrorsFrame and UIErrorsFrame.AddMessage then
                UIErrorsFrame:AddMessage("MSUF: Can't toggle Edit Mode in combat.", 1, 0.2, 0.2)
            end
            return
        end
        local active = IsMSUFEditModeActive()
        local key = "gf_" .. K()
        if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
            _G.MSUF_SetMSUFEditModeDirect(not active, key)
        elseif _G.MSUF_EM2 and _G.MSUF_EM2.State then
            if active then _G.MSUF_EM2.State.Exit("gf_options")
            else _G.MSUF_EM2.State.Enter(key) end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, RefreshEditModeButton)
        else RefreshEditModeButton() end
    end)
    editBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.17, 0.34, 0.36, 1)
        self:SetBackdropBorderColor(0.35, 0.75, 0.78, 1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(TR("MSUF Edit Mode"), 1, 1, 1)
        GameTooltip:AddLine("Toggle MSUF Edit Mode for Group Frames.", 0.7, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    editBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.24, 0.26, 0.92)
        self:SetBackdropBorderColor(0.24, 0.55, 0.58, 0.8)
        GameTooltip:Hide()
    end)
    editBtn:SetScript("OnShow", RefreshEditModeButton)
    RefreshEditModeButton()
    rightAnchor = editBtn

    local resetBtn = CreateFrame("Button", nil, scopeBar, "BackdropTemplate")
    resetBtn:SetSize(84, 20)
    resetBtn:SetPoint("RIGHT", rightAnchor, "LEFT", -6, 0)
    resetBtn:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    resetBtn:SetBackdropColor(0.34, 0.14, 0.14, 0.92)
    resetBtn:SetBackdropBorderColor(0.70, 0.28, 0.28, 0.8)
    local resetFS = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    resetFS:SetPoint("CENTER")
    resetFS:SetText(TR("Reset All"))
    resetFS:SetTextColor(1, 0.82, 0.82)
    resetBtn:SetScript("OnClick", function()
        StaticPopup_Show("MSUF_GF_RESET_ALL_CONFIRM")
    end)
    resetBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.42, 0.18, 0.18, 1)
        self:SetBackdropBorderColor(0.85, 0.35, 0.35, 1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(TR("Reset All"), 1, 1, 1)
        GameTooltip:AddLine("Resets Party, Raid, and Mythic Raid Group Frame settings to defaults for the active profile.", 0.8, 0.8, 0.85, true)
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.34, 0.14, 0.14, 0.92)
        self:SetBackdropBorderColor(0.70, 0.28, 0.28, 0.8)
        GameTooltip:Hide()
    end)

    ----------------------------------------------------------------
    -- Preview collapse toggle
    ----------------------------------------------------------------
    local _previewToggle = CreateFrame("Button", nil, scrollChild)
    _previewToggle:SetSize(SECTION_W, 18)
    local _pvChevron = _previewToggle:CreateTexture(nil, "OVERLAY")
    _pvChevron:SetSize(10, 10)
    _pvChevron:SetPoint("LEFT", _previewToggle, "LEFT", 4, 0)
    _pvChevron:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    local _pvLabel = _previewToggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    _pvLabel:SetPoint("LEFT", _pvChevron, "RIGHT", 4, 0)
    _pvLabel:SetTextColor(0.55, 0.65, 0.85)
    local _pvLine = _previewToggle:CreateTexture(nil, "ARTWORK")
    _pvLine:SetPoint("LEFT", _pvLabel, "RIGHT", 8, 0)
    _pvLine:SetPoint("RIGHT", _previewToggle, "RIGHT", -4, 0)
    _pvLine:SetHeight(1)
    _pvLine:SetColorTexture(0.35, 0.45, 0.65, 0.3)

    RefreshPreviewToggle = function()
        if _previewCollapsed then
            _pvLabel:SetText(TR("Show Preview"))
            _pvChevron:SetRotation(0)
            if _previewBox then _previewBox:Hide() end
        else
            _pvLabel:SetText(TR("Hide Preview"))
            _pvChevron:SetRotation(math.pi / 2)
            if _previewBox then _previewBox:Show() end
        end
        if type(RefreshScrollLayout) == "function" then RefreshScrollLayout() end
    end
    _previewToggle:SetScript("OnClick", function()
        _previewCollapsed = not _previewCollapsed
        RefreshPreviewToggle()
    end)
    RefreshPreviewToggle()

    ----------------------------------------------------------------
    -- Helper: UI.Check with scope awareness
    ----------------------------------------------------------------
    local function SCheck(spec)
        local origGet = spec.get
        local origSet = spec.set
        spec.get = function() return origGet(K()) end
        spec.set = function(v) origSet(K(), v) end
        local cb = UI.Check(spec)
        cb._msufSpec = spec
        function cb:Refresh()
            if spec.get then self:SetChecked(spec.get() and true or false) end
            if self._msufToggleUpdate then self._msufToggleUpdate() end
        end
        _allRefreshFns[#_allRefreshFns + 1] = function()
            if cb:IsShown() then cb:Refresh() end
        end
        return cb
    end

    local function SSlider(spec)
        local origGet = spec.get
        local origSet = spec.set
        spec.get = function() return origGet(K()) end
        spec.set = function(v) origSet(K(), v) end
        if spec.compact and spec.compactInput == nil then
            spec.compactInput = true
            spec.compactInputWidth = 42
            spec.compactInputGap = 6
        end
        local sl = UI.Slider(spec)
        if sl then
            function sl:Refresh()
                if spec.get then
                    local v = spec.get()
                    if type(v) == "number" and self.SetValueClean then self:SetValueClean(v) end
                end
            end
            _allRefreshFns[#_allRefreshFns + 1] = function()
                if sl:IsShown() then sl:Refresh() end
            end
        end
        return sl
    end

    local function SDropdown(spec)
        local origGet = spec.get
        local origSet = spec.set
        spec.get = function() return origGet(K()) end
        spec.set = function(v) origSet(K(), v) end
        local dd = UI.Dropdown(spec)
        if dd and dd.Refresh then
            _allRefreshFns[#_allRefreshFns + 1] = function() if dd:IsShown() then dd:Refresh() end end
        end
        return dd
    end

    local OPTION_DISABLED_ALPHA = 0.45
    local function SetGFOptionControlEnabled(widget, enabled)
        if not widget then return end
        enabled = enabled and true or false
        local alpha = enabled and 1 or OPTION_DISABLED_ALPHA

        if widget.SetEnabled then
            widget:SetEnabled(enabled)
        elseif enabled then
            if widget.EnableMouse then widget:EnableMouse(true) end
            if widget.Enable then widget:Enable() end
        else
            if widget.EnableMouse then widget:EnableMouse(false) end
            if widget.Disable then widget:Disable() end
        end

        local name = widget.GetName and widget:GetName()
        local dropButton = widget.Button or (name and _G[name .. "Button"])
        if dropButton then
            if enabled then
                if dropButton.EnableMouse then dropButton:EnableMouse(true) end
                if dropButton.Enable then dropButton:Enable() end
            else
                if dropButton.EnableMouse then dropButton:EnableMouse(false) end
                if dropButton.Disable then dropButton:Disable() end
            end
            if dropButton.SetAlpha then dropButton:SetAlpha(alpha) end
        end

        if widget._msufPeelButton then
            if widget._msufPeelButton.EnableMouse then widget._msufPeelButton:EnableMouse(enabled) end
            if enabled then
                if widget._msufPeelButton.Enable then widget._msufPeelButton:Enable() end
            else
                if widget._msufPeelButton.Disable then widget._msufPeelButton:Disable() end
            end
            if widget._msufPeelButton.SetAlpha then widget._msufPeelButton:SetAlpha(alpha) end
        end

        if widget.SetAlpha then widget:SetAlpha(alpha) end
        if widget.Text and widget.Text.SetAlpha then widget.Text:SetAlpha(alpha) end
        if widget.text and widget.text.SetAlpha then widget.text:SetAlpha(alpha) end
        if widget.editBox and widget.editBox.SetAlpha then widget.editBox:SetAlpha(alpha) end
        if widget.minusButton and widget.minusButton.SetAlpha then widget.minusButton:SetAlpha(alpha) end
        if widget.plusButton and widget.plusButton.SetAlpha then widget.plusButton:SetAlpha(alpha) end

        if widget._msufToggleUpdate then widget._msufToggleUpdate() end
        if widget.__msufToggleUpdate then widget.__msufToggleUpdate() end

        if name then
            for _, suffix in ipairs({ "Text", "Low", "High" }) do
                local region = _G[name .. suffix]
                if region and region.SetAlpha then region:SetAlpha(alpha) end
            end
        end
    end

    local function SetGFOptionRegionEnabled(region, enabled)
        if region and region.SetAlpha then region:SetAlpha(enabled and 1 or OPTION_DISABLED_ALPHA) end
    end

    local function SetGFOptionControlsEnabled(enabled, widgets, labels)
        for i = 1, #(widgets or {}) do
            SetGFOptionControlEnabled(widgets[i], enabled)
        end
        for i = 1, #(labels or {}) do
            SetGFOptionRegionEnabled(labels[i], enabled)
        end
    end

    ----------------------------------------------------------------
    -- All sections stacked below scopeBar
    ----------------------------------------------------------------
    local function AddSection(expandedH, title, defaultOpen, sectionKey)
        local box, body = MakeCollapsibleSection(scrollChild, expandedH, title, defaultOpen)
        sections[#sections + 1] = box
        box._msufSecKey = sectionKey or ("_auto_" .. #sections)
        if sectionKey then _sectionLookup[sectionKey] = box end
        return box, body
    end

    -- Category divider: non-collapsible label between section groups
    local function MakeCategoryDivider(titleText)
        local div = CreateFrame("Frame", nil, scrollChild)
        div:SetSize(SECTION_W, 22)
        local label = div:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", div, "LEFT", 4, 0)
        label:SetText(titleText)
        label:SetTextColor(0.55, 0.65, 0.85, 1)
        local line = div:CreateTexture(nil, "ARTWORK")
        line:SetPoint("LEFT", label, "RIGHT", 8, 0)
        line:SetPoint("RIGHT", div, "RIGHT", -4, 0)
        line:SetHeight(1)
        line:SetColorTexture(0.35, 0.45, 0.65, 0.5)
        div._msufIsDivider = true
        return div
    end

    ----------------------------------------------------------------
    -- Preview box: drag-to-position mock frame (top of panel)
    ----------------------------------------------------------------
    if GF.CreatePreviewBox then
        _previewBox = GF.CreatePreviewBox(scrollChild, K, function(sectionKey)
            OpenSectionByKey(sectionKey)
        end)
    end

    ----------------------------------------------------------------
    -- Section 1: General (default open)
    ----------------------------------------------------------------
    do
        local box, body = AddSection(320, "General", false, "general")

        local enableChk = SCheck({
            name = "MSUF_GF_EnableCheck", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -8,
            label = TR("Enable"),
            get = function(k) return GF.Val(k, "enabled") end,
            set = function(k, v) GF.GetConf(k).enabled = v; GF.RebuildAll() end,
        })

        local showPlayerChk = SCheck({
            name = "MSUF_GF_ShowPlayerCheck", parent = body,
            anchor = enableChk, x = 0, y = -4,
            label = TR("Show Player in Group"),
            get = function(k) return GF.Val(k, "showPlayer") end,
            set = function(k, v) GF.GetConf(k).showPlayer = v; GF.RebuildAll() end,
        })

        local showSoloChk = SCheck({
            name = "MSUF_GF_ShowSoloCheck", parent = body,
            anchor = showPlayerChk, x = 0, y = -4,
            label = TR("Show when Solo"),
            get = function(k) return GF.Val(k, "showSolo") end,
            set = function(k, v) GF.GetConf(k).showSolo = v; GF.RebuildAll() end,
        })

        -- Misc options
        local reverseFillChk = SCheck({
            name = "MSUF_GF_ReverseFillCheck", parent = body,
            anchor = showSoloChk, x = 0, y = -4,
            label = TR("Reverse Fill"),
            get = function(k) return GF.Val(k, "reverseFill") end,
            set = function(k, v) GF.GetConf(k).reverseFill = v; GF.RefreshVisuals() end,
        })

        local smoothChk = SCheck({
            name = "MSUF_GF_SmoothFillCheck", parent = body,
            anchor = reverseFillChk, x = 0, y = -4,
            label = TR("Smooth Health Fill"),
            get = function(k) return GF.Val(k, "smoothFill") ~= false end,
            set = function(k, v) GF.GetConf(k).smoothFill = v end,
        })

        local hideClientChk = SCheck({
            name = "MSUF_GF_HideInClientSceneCheck", parent = body,
            anchor = smoothChk, x = 0, y = -4,
            label = TR("Hide in Barber Shop / Dressing Room"),
            get = function(k) return GF.Val(k, "hideInClientScene") ~= false end,
            set = function(k, v) GF.GetConf(k).hideInClientScene = v end,
        })

        SSlider({
            name = "MSUF_GF_HideOfflineSlider", parent = body, compact = true,
            anchor = hideClientChk, x = 0, y = -14,
            min = 0, max = 120, step = 1, width = 270, default = 0,
            get = function(k) return GF.Val(k, "hideOfflineDelay") or 0 end,
            set = function(k, v) GF.GetConf(k).hideOfflineDelay = v; GF.RefreshVisuals() end,
            formatText = function(v) return v == 0 and TR("Hide Offline: Off") or string.format(TR("Hide Offline: %ds"), v) end,
        })
    end

    ----------------------------------------------------------------
    -- Section 1a: Layout (Raid Layout Situation + geometry)
    ----------------------------------------------------------------
    do
        local box, body = AddSection(690, "Layout", false, "layout")

        -- ── Raid Layout Situation (raid scope only) ──
        local _raidLayoutContainer = CreateFrame("Frame", nil, body)
        _raidLayoutContainer:SetSize(SECTION_W - 24, 110)
        _raidLayoutContainer:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)

        local _raidLayoutItems = {}
        for _, sit in ipairs(GF.RAID_LAYOUT_SITUATIONS or {}) do
            _raidLayoutItems[#_raidLayoutItems + 1] = { key = sit.key, label = TR(sit.label) }
        end

        local raidLayoutLbl = _raidLayoutContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        raidLayoutLbl:SetPoint("TOPLEFT", _raidLayoutContainer, "TOPLEFT", 12, -8)
        raidLayoutLbl:SetText(TR("Raid Layout Situation")); raidLayoutLbl:SetTextColor(1, 0.82, 0)

        local raidLayoutAutoChk = SCheck({
            name = "MSUF_GF_RaidLayoutAuto", parent = _raidLayoutContainer,
            anchor = raidLayoutLbl, anchorPoint = "TOPLEFT", x = 0, y = -14,
            label = TR("Auto-switch on zone change"),
            get = function(k)
                local conf = GF.GetConf(k)
                return conf and conf.raidLayoutMode == "auto"
            end,
            set = function(k, v)
                local conf = GF.GetConf(k)
                if conf then
                    conf.raidLayoutMode = v and "auto" or "manual"
                    if v and GF.AutoSwitchRaidLayout then
                        GF.AutoSwitchRaidLayout(k)
                    end
                end
            end,
        })

        local raidLayoutDd
        if #_raidLayoutItems > 0 then
            raidLayoutDd = SDropdown({
                name = "MSUF_GF_RaidLayoutDropdown", parent = _raidLayoutContainer,
                anchor = raidLayoutAutoChk, x = 0, y = -4, width = 220,
                items = _raidLayoutItems,
                get = function(k)
                    local conf = GF.GetConf(k)
                    return conf and conf._activeRaidLayout or "manual"
                end,
                set = function(k, v)
                    if GF.SwitchRaidLayout then GF.SwitchRaidLayout(v, k) end
                end,
            })
        end

        local raidLayoutHint = _raidLayoutContainer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        raidLayoutHint:SetPoint("TOPLEFT", raidLayoutDd or raidLayoutAutoChk, "BOTTOMLEFT", 4, -4)
        raidLayoutHint:SetText(TR("Width, Height, Spacing, Columns, Growth saved per situation.\nSwitch to edit each layout. Auto detects Mythic/Normal/World."))
        raidLayoutHint:SetTextColor(0.5, 0.5, 0.6)
        raidLayoutHint:SetWidth(350)
        raidLayoutHint:SetJustifyH("LEFT")

        local widthSl = SSlider({
            name = "MSUF_GF_WidthSlider", parent = body, compact = true,
            anchor = _raidLayoutContainer, anchorPoint = "BOTTOMLEFT", x = 12, y = -10,
            min = 40, max = 300, step = 1, width = 270, default = 120,
            get = function(k) return GF.Val(k, "width") end,
            set = function(k, v) GF.GetConf(k).width = v; GF.RebuildAll() end,
            formatText = function(v) return string.format("Width: %d", v) end,
        })

        local heightSl = SSlider({
            name = "MSUF_GF_HeightSlider", parent = body, compact = true,
            anchor = widthSl, x = 0, y = -32,
            min = 16, max = 120, step = 1, width = 270, default = 40,
            get = function(k) return GF.Val(k, "height") end,
            set = function(k, v) GF.GetConf(k).height = v; GF.RebuildAll() end,
            formatText = function(v) return string.format("Height: %d", v) end,
        })

        local spacingSl = SSlider({
            name = "MSUF_GF_SpacingSlider", parent = body, compact = true,
            anchor = heightSl, x = 0, y = -32,
            min = 0, max = 20, step = 1, width = 270, default = 1,
            get = function(k) return GF.Val(k, "spacing") end,
            set = function(k, v) GF.GetConf(k).spacing = v; GF.RebuildAll() end,
            formatText = function(v) return string.format("Spacing: %d", v) end,
        })

        -- Growth direction: 4 visual preview buttons (reload required)
        -- Shows mini-grid with numbered "1" on first unit + arrow showing direction.
        local growthLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        growthLabel:SetPoint("TOPLEFT", spacingSl, "BOTTOMLEFT", 0, -18)
        growthLabel:SetText(TR("Growth Direction"))
        growthLabel:SetTextColor(1, 0.82, 0)

        local GROW_W, GROW_H = 64, 64
        local GROW_GAP = 6
        local GROW_DIRS = {
            { key = "DOWN",  label = "Down",  dx = 0, dy = -1, arrow = "▼" },
            { key = "UP",    label = "Up",    dx = 0, dy = 1,  arrow = "▲" },
            { key = "RIGHT", label = "Right", dx = 1, dy = 0,  arrow = "►" },
            { key = "LEFT",  label = "Left",  dx = -1, dy = 0, arrow = "◄" },
        }
        local growthBtns = {}
        local growthContainer = CreateFrame("Frame", nil, body)
        growthContainer:SetSize(4 * GROW_W + 3 * GROW_GAP, GROW_H + 16)
        growthContainer:SetPoint("TOPLEFT", growthLabel, "BOTTOMLEFT", 0, -6)

        local function DrawMiniPreview(btn, dx, dy, arrow, isRaid)
            -- Clean up old elements
            if btn._miniRects then
                for _, r in ipairs(btn._miniRects) do r:Hide() end
            end
            btn._miniRects = btn._miniRects or {}
            if btn._miniNums then
                for _, fs in ipairs(btn._miniNums) do fs:Hide() end
            end
            btn._miniNums = btn._miniNums or {}

            local cols, rows
            if isRaid then
                if dy ~= 0 then rows = 5; cols = 4
                else rows = 4; cols = 5 end
            else
                if dy ~= 0 then rows = 5; cols = 1
                else rows = 1; cols = 5 end
            end

            local pad = 4
            local labelH = 14
            local innerW = GROW_W - pad * 2
            local innerH = GROW_H - pad - labelH
            local gap = 1

            local cellW = (innerW - (cols - 1) * gap) / cols
            local cellH = (innerH - (rows - 1) * gap) / rows
            if cellW < 2 then cellW = 2 end
            if cellH < 2 then cellH = 2 end

            local gridW = cols * cellW + (cols - 1) * gap
            local gridH = rows * cellH + (rows - 1) * gap
            local originX = pad + (innerW - gridW) / 2
            local originY = -(pad + (innerH - gridH) / 2)

            local count = cols * rows
            local ri = 0

            -- Build ordered position list matching growth direction
            local positions = {}
            if dy ~= 0 then
                local rowStart, rowEnd, rowStep = 0, rows - 1, 1
                if dy == 1 then rowStart, rowEnd, rowStep = rows - 1, 0, -1 end
                for col = 0, cols - 1 do
                    for row = rowStart, rowEnd, rowStep do
                        positions[#positions + 1] = { col = col, row = row }
                    end
                end
            else
                local colStart, colEnd, colStep = 0, cols - 1, 1
                if dx == -1 then colStart, colEnd, colStep = cols - 1, 0, -1 end
                for row = 0, rows - 1 do
                    for col = colStart, colEnd, colStep do
                        positions[#positions + 1] = { col = col, row = row }
                    end
                end
            end

            for idx = 1, #positions do
                ri = ri + 1
                local pos = positions[idx]
                local r = btn._miniRects[ri]
                if not r then
                    r = btn:CreateTexture(nil, "ARTWORK")
                    btn._miniRects[ri] = r
                end
                r:SetSize(cellW, cellH)
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", btn, "TOPLEFT",
                    originX + pos.col * (cellW + gap),
                    originY - pos.row * (cellH + gap))

                if idx == 1 then
                    -- First unit: bright green-blue highlight
                    r:SetColorTexture(0.2, 0.9, 0.6, 1.0)
                elseif idx <= 3 then
                    -- Next few: medium
                    r:SetColorTexture(0.35, 0.65, 0.90, 0.85)
                else
                    -- Rest: progressively faded
                    local alpha = 0.7 - (idx - 3) * (0.35 / count)
                    if alpha < 0.2 then alpha = 0.2 end
                    r:SetColorTexture(0.30, 0.50, 0.75, alpha)
                end
                r:Show()

                -- Number on first unit
                if idx == 1 then
                    local fs = btn._miniNums[1]
                    if not fs then
                        fs = btn:CreateFontString(nil, "OVERLAY")
                        fs:SetFont("Fonts\\FRIZQT__.TTF", 7, "OUTLINE")
                        btn._miniNums[1] = fs
                    end
                    fs:ClearAllPoints()
                    fs:SetPoint("CENTER", r, "CENTER", 0, 0)
                    fs:SetText("1")
                    fs:SetTextColor(0, 0, 0, 1)
                    fs:Show()
                end
            end
            for j = ri + 1, #btn._miniRects do btn._miniRects[j]:Hide() end

            -- Arrow indicator showing direction
            local arrowFs = btn._miniNums[2]
            if not arrowFs then
                arrowFs = btn:CreateFontString(nil, "OVERLAY")
                arrowFs:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
                btn._miniNums[2] = arrowFs
            end
            arrowFs:ClearAllPoints()
            arrowFs:SetText(arrow)
            arrowFs:SetTextColor(0.9, 0.75, 0.3, 0.9)
            -- Position arrow at the growth edge
            if dy == -1 then
                arrowFs:SetPoint("BOTTOM", btn, "BOTTOM", 0, labelH + 1)
            elseif dy == 1 then
                arrowFs:SetPoint("TOP", btn, "TOP", 0, -pad)
            elseif dx == 1 then
                arrowFs:SetPoint("RIGHT", btn, "RIGHT", -pad, labelH / 2)
            elseif dx == -1 then
                arrowFs:SetPoint("LEFT", btn, "LEFT", pad, labelH / 2)
            end
            arrowFs:Show()
            for j = 3, #btn._miniNums do btn._miniNums[j]:Hide() end
        end

        local function RefreshGrowthButtons()
            local cur = GF.Val(K(), "growth") or "DOWN"
            local isRaid = IsRaidLike(K())
            for _, info in ipairs(GROW_DIRS) do
                local btn = growthBtns[info.key]
                if btn then
                    DrawMiniPreview(btn, info.dx, info.dy, info.arrow, isRaid)
                    if info.key == cur then
                        btn:SetBackdropBorderColor(0.3, 0.7, 1.0, 1)
                        btn:SetBackdropColor(0.12, 0.18, 0.28, 1)
                    else
                        btn:SetBackdropBorderColor(0.25, 0.25, 0.30, 0.8)
                        btn:SetBackdropColor(0.08, 0.08, 0.10, 1)
                    end
                end
            end
        end

        for idx, info in ipairs(GROW_DIRS) do
            local btn = CreateFrame("Button", nil, growthContainer, "BackdropTemplate")
            btn:SetSize(GROW_W, GROW_H)
            btn:SetPoint("TOPLEFT", growthContainer, "TOPLEFT", (idx - 1) * (GROW_W + GROW_GAP), 0)
            btn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            btn:SetBackdropColor(0.08, 0.08, 0.10, 1)
            btn:SetBackdropBorderColor(0.25, 0.25, 0.30, 0.8)

            local lbl = btn:CreateFontString(nil, "OVERLAY")
            lbl:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
            lbl:SetPoint("BOTTOM", btn, "BOTTOM", 0, 3)
            lbl:SetText(TR(info.label))
            lbl:SetTextColor(0.8, 0.8, 0.8)

            btn:SetScript("OnEnter", function(self)
                self:SetBackdropColor(0.15, 0.20, 0.30, 1)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(TR("Grow") .. " " .. TR(info.label), 1, 1, 1)
                if info.dy == -1 then
                    GameTooltip:AddLine(TR("Unit 1 at top, new units added below"), 0.7, 0.7, 0.7)
                elseif info.dy == 1 then
                    GameTooltip:AddLine(TR("Unit 1 at bottom, new units added above"), 0.7, 0.7, 0.7)
                elseif info.dx == 1 then
                    GameTooltip:AddLine(TR("Unit 1 at left, new units added right"), 0.7, 0.7, 0.7)
                else
                    GameTooltip:AddLine(TR("Unit 1 at right, new units added left"), 0.7, 0.7, 0.7)
                end
                GameTooltip:AddLine(TR("Requires reload to apply"), 0.9, 0.7, 0.3)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
                RefreshGrowthButtons()
            end)
            btn:SetScript("OnClick", function()
                local cur = GF.Val(K(), "growth") or "DOWN"
                if info.key == cur then return end
                GF.GetConf(K()).growth = info.key
                RefreshGrowthButtons()
                GF.RebuildAll()
                if GF.RefreshPreviewLayout then GF.RefreshPreviewLayout(K()) end
            end)

            growthBtns[info.key] = btn
        end

        RefreshGrowthButtons()
        _allRefreshFns[#_allRefreshFns + 1] = RefreshGrowthButtons

        local upcSl = SSlider({
            name = "MSUF_GF_UnitsPerColumnSlider", parent = body, compact = true,
            anchor = growthContainer, x = 0, y = -14,
            min = 1, max = 40, step = 1, width = 270, default = 5,
            get = function(k) return GF.Val(k, "unitsPerColumn") end,
            set = function(k, v) GF.GetConf(k).unitsPerColumn = v; GF.RebuildAll() end,
            formatText = function(v) return string.format("Units per Column: %d", v) end,
        })

        local maxColSl = SSlider({
            name = "MSUF_GF_MaxColumnsSlider", parent = body, compact = true,
            anchor = upcSl, x = 0, y = -32,
            min = 1, max = 8, step = 1, width = 270, default = 8,
            get = function(k) return GF.Val(k, "maxColumns") end,
            set = function(k, v) GF.GetConf(k).maxColumns = v; GF.RebuildAll() end,
            formatText = function(v) return string.format("Max Columns: %d", v) end,
        })

        -- Group Filter (raid only): 8 compact toggles in a row
        local _gfRow = CreateFrame("Frame", nil, body)
        _gfRow:SetSize(500, 36)
        _gfRow:SetPoint("TOPLEFT", maxColSl, "BOTTOMLEFT", 0, -14)
        do
            local lbl = _gfRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("TOPLEFT", _gfRow, "TOPLEFT", 0, 0)
            lbl:SetText(TR("Show Groups:")); lbl:SetTextColor(1, 0.82, 0)
        end

        --- Migrate legacy string "1,2,3,4" → table {[1]=true,...,[8]=false}
        local function EnsureGroupFilterTable(conf)
            local gf = conf.groupFilter
            if type(gf) == "string" then
                local tbl = {}
                for i = 1, 8 do tbl[i] = false end
                for num in gf:gmatch("%d+") do
                    local n = tonumber(num)
                    if n and n >= 1 and n <= 8 then tbl[n] = true end
                end
                conf.groupFilter = tbl
                return tbl
            end
            if type(gf) ~= "table" then conf.groupFilter = nil end
            return conf.groupFilter
        end

        local W8 = "Interface\\Buttons\\WHITE8x8"
        local _gfChecks = {}
        for gi = 1, 8 do
            local btn = CreateFrame("Button", nil, _gfRow, "BackdropTemplate")
            btn:SetSize(30, 18)
            btn:SetPoint("TOPLEFT", _gfRow, "TOPLEFT", (gi - 1) * 34, -14)
            btn:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
            btn._checked = true
            local fs = btn:CreateFontString(nil, "OVERLAY")
            fs:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
            fs:SetPoint("CENTER"); fs:SetText(tostring(gi))
            btn._fs = fs
            local function UpdateVisual(b)
                if b._checked then
                    b:SetBackdropColor(0.15, 0.35, 0.55, 1)
                    b:SetBackdropBorderColor(0.3, 0.55, 0.8, 1)
                    b._fs:SetTextColor(1, 1, 1)
                else
                    b:SetBackdropColor(0.08, 0.08, 0.10, 1)
                    b:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)
                    b._fs:SetTextColor(0.35, 0.35, 0.40)
                end
            end
            local idx = gi
            btn:SetScript("OnClick", function(self)
                self._checked = not self._checked
                UpdateVisual(self)
                local k = K()
                local conf = GF.GetConf(k)
                EnsureGroupFilterTable(conf)
                if not conf.groupFilter then conf.groupFilter = {} end
                conf.groupFilter[idx] = self._checked
                GF.RebuildAll()
            end)
            btn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(0.5, 0.7, 1, 1)
            end)
            btn:SetScript("OnLeave", function(self) UpdateVisual(self) end)
            UpdateVisual(btn)
            _gfChecks[gi] = btn
        end
        -- Sync raid layout container: hide for party, re-anchor width slider
        local function SyncRaidLayout()
            local isRaid = IsRaidLike(K())
            _raidLayoutContainer:SetShown(isRaid)
            widthSl:ClearAllPoints()
            if isRaid then
                widthSl:SetPoint("TOPLEFT", _raidLayoutContainer, "BOTTOMLEFT", 12, -10)
            else
                widthSl:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -12)
            end
        end
        _allRefreshFns[#_allRefreshFns + 1] = SyncRaidLayout
        SyncRaidLayout()

        -- Sync group filter toggles on scope change
        local function SyncGroupFilter()
            local k = K()
            local isRaid = IsRaidLike(k)
            _gfRow:SetShown(isRaid)
            if isRaid then
                local conf = GF.GetConf(k)
                local gf = EnsureGroupFilterTable(conf)
                for gi = 1, 8 do
                    _gfChecks[gi]._checked = (not gf or gf[gi] ~= false)
                    local uv = _gfChecks[gi]:GetScript("OnLeave")
                    if uv then uv(_gfChecks[gi]) end
                end
            end
        end
        _allRefreshFns[#_allRefreshFns + 1] = SyncGroupFilter
        SyncGroupFilter()

    end

    ----------------------------------------------------------------
    -- Section 1a2: Sorting (Sort Mode + Role Sort)
    ----------------------------------------------------------------
    do
        local box, body = AddSection(380, "Sorting", false, "sorting")

        ----------------------------------------------------------------
        -- Sort Mode dropdown (raid only: INDEX / ROLE / GROUP / GROUP_ROLE / NAME)
        ----------------------------------------------------------------
        local _sortModeItems = {
            { key = "INDEX",      label = TR("Index (Default)") },
            { key = "ROLE",       label = TR("By Role") },
            { key = "GROUP",      label = TR("By Raid Group") },
            { key = "GROUP_ROLE", label = TR("Group + Role") },
            { key = "NAME",       label = TR("Alphabetical") },
        }
        local sortModeDd = SDropdown({
            name = "MSUF_GF_SortModeDropdown", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -8, width = 200,
            items = _sortModeItems,
            get = function(k)
                local conf = GF.GetConf(k)
                if conf.sortMode then return conf.sortMode end
                return conf.sortByRole and "ROLE" or "INDEX"
            end,
            set = function(k, v)
                local conf = GF.GetConf(k)
                conf.sortMode = v
                -- Backward compat: keep sortByRole in sync
                conf.sortByRole = (v == "ROLE")
                GF.RebuildAll()
            end,
        })
        local sortModeLbl = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sortModeLbl:SetPoint("LEFT", sortModeDd, "RIGHT", 8, 0)
        sortModeLbl:SetText(TR("Sort Mode"))
        sortModeLbl:SetTextColor(0.7, 0.7, 0.7)

        ----------------------------------------------------------------
        -- Role Sort: drag-to-reorder role priority (visible when ROLE mode)
        ----------------------------------------------------------------
        local _roleSortWrap = CreateFrame("Frame", nil, body)
        _roleSortWrap:SetPoint("TOPLEFT", sortModeDd, "BOTTOMLEFT", 0, -2)
        _roleSortWrap:SetSize(300, 24)
        do
            local ALL_ROLES = {
                { key = "TANK",    label = "Tank",   r = 0.30, g = 0.55, b = 0.85, mode = "both" },
                { key = "HEALER",  label = "Healer", r = 0.20, g = 0.72, b = 0.35, mode = "both" },
                { key = "DAMAGER", label = "DPS",    r = 0.82, g = 0.30, b = 0.30, mode = "merged" },
                { key = "MELEE",   label = "Melee",  r = 0.90, g = 0.55, b = 0.20, mode = "split" },
                { key = "RANGED",  label = "Ranged", r = 0.55, g = 0.40, b = 0.85, mode = "split" },
            }
            local ROLE_BY_KEY = {}
            for i, rd in ipairs(ALL_ROLES) do ROLE_BY_KEY[rd.key] = i end
            local ROW_H, ROW_GAP = 22, 4
            local ROW_W = 200
            local MAX_ROWS = 5
            local W8 = "Interface\\Buttons\\WHITE8x8"

            local _roleRows = {}
            local _activeCount = 3

            -- Enable checkbox (legacy — syncs with Sort Mode dropdown)
            local roleSortChk = SCheck({
                name = "MSUF_GF_SortByRoleCheck", parent = _roleSortWrap,
                anchor = _roleSortWrap, anchorPoint = "TOPLEFT", x = 0, y = -4,
                label = TR("Sort by Role"),
                get = function(k)
                    local conf = GF.GetConf(k)
                    local sm = conf.sortMode
                    if sm then return sm == "ROLE" end
                    return GF.Val(k, "sortByRole")
                end,
                set = function(k, v)
                    local conf = GF.GetConf(k)
                    conf.sortByRole = v
                    conf.sortMode = v and "ROLE" or "INDEX"
                    GF.RebuildAll()
                end,
            })

            local meleeChk = SCheck({
                name = "MSUF_GF_SeparateMeleeCheck", parent = _roleSortWrap,
                anchor = roleSortChk, x = 16, y = -2,
                label = TR("Separate Melee / Ranged"),
                get = function(k) return GF.Val(k, "separateMeleeRanged") end,
                set = function(k, v) GF.GetConf(k).separateMeleeRanged = v; GF.RebuildAll() end,
            })
            local playerFirstChk = SCheck({
                name = "MSUF_GF_PlayerFirstCheck", parent = _roleSortWrap,
                anchor = meleeChk, x = 0, y = -2,
                label = TR("Player first in role"),
                get = function(k) return GF.Val(k, "playerFirstInRole") end,
                set = function(k, v) GF.GetConf(k).playerFirstInRole = v; GF.RebuildAll() end,
            })

            local roleContainer = CreateFrame("Frame", nil, _roleSortWrap)
            roleContainer:SetSize(ROW_W, MAX_ROWS * (ROW_H + ROW_GAP))
            roleContainer:SetPoint("TOPLEFT", playerFirstChk, "BOTTOMLEFT", -16, -4)

            local function SlotY(s) return -((s - 1) * (ROW_H + ROW_GAP)) end

            local function SnapAll()
                for i = 1, MAX_ROWS do
                    local r = _roleRows[i]
                    if r.active then
                        r.frame:ClearAllPoints()
                        r.frame:SetPoint("TOPLEFT", roleContainer, "TOPLEFT", 0, SlotY(r.slotIndex))
                        r.frame._numText:SetText(tostring(r.slotIndex))
                        r.frame:Show()
                    else
                        r.frame:Hide()
                    end
                end
                roleContainer:SetHeight(_activeCount * (ROW_H + ROW_GAP))
            end

            local function SaveOrder()
                local sorted = {}
                for i = 1, MAX_ROWS do
                    if _roleRows[i].active then sorted[#sorted + 1] = _roleRows[i] end
                end
                table.sort(sorted, function(a, b) return a.slotIndex < b.slotIndex end)
                local parts = {}
                for _, r in ipairs(sorted) do parts[#parts + 1] = r.key end
                GF.GetConf(K()).roleOrder = table.concat(parts, ",")
                GF.RebuildAll()
            end

            for i = 1, MAX_ROWS do
                local rd = ALL_ROLES[i]
                local rf = CreateFrame("Frame", "MSUF_GF_RoleSortRow" .. i, roleContainer, "BackdropTemplate")
                rf:SetSize(ROW_W, ROW_H)
                rf:SetMovable(true); rf:EnableMouse(true); rf:RegisterForDrag("LeftButton")
                rf:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
                rf:SetBackdropColor(0.12, 0.12, 0.12, 0.85)
                rf:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
                local stripe = rf:CreateTexture(nil, "ARTWORK")
                stripe:SetSize(4, ROW_H - 2); stripe:SetPoint("LEFT", rf, "LEFT", 2, 0)
                stripe:SetColorTexture(rd.r, rd.g, rd.b, 1)
                local label = rf:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                label:SetPoint("LEFT", stripe, "RIGHT", 6, 0); label:SetText(rd.label)
                local num = rf:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                num:SetPoint("RIGHT", rf, "RIGHT", -8, 0); num:SetTextColor(0.5, 0.5, 0.5)
                rf._numText = num
                rf:SetScript("OnDragStart", function(self)
                    GameTooltip:Hide(); self:StartMoving(); self:SetFrameStrata("TOOLTIP")
                end)
                rf:SetScript("OnDragStop", function(self)
                    self:StopMovingOrSizing(); self:SetFrameStrata(roleContainer:GetFrameStrata())
                    local _, selfY = self:GetCenter()
                    local contTop = roleContainer:GetTop()
                    local bestSlot, bestDist = 1, math.huge
                    for s = 1, _activeCount do
                        local dist = math.abs(selfY - (contTop + SlotY(s) - ROW_H / 2))
                        if dist < bestDist then bestDist = dist; bestSlot = s end
                    end
                    local myRow
                    for idx = 1, MAX_ROWS do
                        if _roleRows[idx].active and _roleRows[idx].frame == self then myRow = _roleRows[idx]; break end
                    end
                    if myRow and myRow.slotIndex ~= bestSlot then
                        for idx = 1, MAX_ROWS do
                            if _roleRows[idx].active and _roleRows[idx].slotIndex == bestSlot then
                                _roleRows[idx].slotIndex = myRow.slotIndex; break
                            end
                        end
                        myRow.slotIndex = bestSlot
                    end
                    SnapAll(); SaveOrder()
                end)
                rf:Hide()
                _roleRows[i] = { frame = rf, key = rd.key, slotIndex = i, active = false, mode = rd.mode }
            end

            local function SetMode(split)
                _activeCount = split and 4 or 3
                for i = 1, MAX_ROWS do
                    local m = _roleRows[i].mode
                    _roleRows[i].active = (m == "both") or (split and m == "split") or (not split and m == "merged")
                end
            end

            local function InitFromDB()
                local conf = GF.GetConf(K())
                local split = conf.separateMeleeRanged == true
                SetMode(split)
                local str = conf.roleOrder or (split and "TANK,HEALER,MELEE,RANGED" or "TANK,HEALER,DAMAGER")
                local slot = 0
                local assigned = {}
                for tok in str:gmatch("[^,]+") do
                    local ri = ROLE_BY_KEY[tok]
                    if ri and _roleRows[ri].active and not assigned[ri] then
                        slot = slot + 1
                        _roleRows[ri].slotIndex = slot
                        assigned[ri] = true
                    end
                end
                for i = 1, MAX_ROWS do
                    if _roleRows[i].active and not assigned[i] then
                        slot = slot + 1
                        _roleRows[i].slotIndex = slot
                    end
                end
                SnapAll()
            end

            local function SetRowsEnabled(enabled)
                for i = 1, MAX_ROWS do
                    if _roleRows[i].active then
                        _roleRows[i].frame:SetAlpha(enabled and 1 or 0.4)
                        _roleRows[i].frame:EnableMouse(enabled)
                    end
                end
                meleeChk:SetAlpha(enabled and 1 or 0.4)
                meleeChk:EnableMouse(enabled)
                playerFirstChk:SetAlpha(enabled and 1 or 0.4)
                playerFirstChk:EnableMouse(enabled)
            end

            local function SyncRoleSort()
                local conf = GF.GetConf(K())
                local enabled = conf.sortByRole and true or false
                InitFromDB()
                roleContainer:SetShown(true)
                SetRowsEnabled(enabled)
                _roleSortWrap:SetHeight(_activeCount * (ROW_H + ROW_GAP) + 80)
            end
            _allRefreshFns[#_allRefreshFns + 1] = SyncRoleSort
            SyncRoleSort()
            roleSortChk:HookScript("OnClick", function()
                C_Timer.After(0, function() SyncRoleSort() end)
            end)
            meleeChk:HookScript("OnClick", function()
                C_Timer.After(0, function() SyncRoleSort() end)
            end)
        end
    end

    ----------------------------------------------------------------
    -- Section 1b: Anchoring
    ----------------------------------------------------------------
    do
        local box, body = AddSection(220, "Anchoring", false, "anchor")

        local GF_ANCHOR_CHOICES = {
            { key = "FREE",         label = TR("Free (UIParent)") },
            { key = "player",       label = TR("Player Frame") },
            { key = "target",       label = TR("Target Frame") },
            { key = "targettarget", label = TR("Target of Target") },
            { key = "focus",        label = TR("Focus Frame") },
        }

        local GF_ANCHOR_POINTS = {
            { key = "TOPLEFT",     label = "TOPLEFT" },
            { key = "TOP",         label = "TOP" },
            { key = "TOPRIGHT",    label = "TOPRIGHT" },
            { key = "LEFT",        label = "LEFT" },
            { key = "CENTER",      label = "CENTER" },
            { key = "RIGHT",       label = "RIGHT" },
            { key = "BOTTOMLEFT",  label = "BOTTOMLEFT" },
            { key = "BOTTOM",      label = "BOTTOM" },
            { key = "BOTTOMRIGHT", label = "BOTTOMRIGHT" },
        }

        local anchorToLbl = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        anchorToLbl:SetPoint("TOPLEFT", body, "TOPLEFT", 14, -8)
        anchorToLbl:SetText(TR("Anchor To"))

        local anchorToDd = SDropdown({
            name = "MSUF_GF_AnchorToDropdown", parent = body,
            anchor = anchorToLbl, anchorPoint = "BOTTOMLEFT", x = -16, y = -4, width = 200,
            items = GF_ANCHOR_CHOICES,
            get = function(k) return GF.GetConf(k).anchorToFrame or "FREE" end,
            set = function(k, v)
                GF.GetConf(k).anchorToFrame = (v == "FREE") and nil or v
                GF.RebuildAll()
            end,
        })

        local anchorPtLbl = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        anchorPtLbl:SetPoint("TOPLEFT", anchorToLbl, "TOPLEFT", 240, 0)
        anchorPtLbl:SetText(TR("Anchor Point"))

        SDropdown({
            name = "MSUF_GF_AnchorPointDropdown", parent = body,
            anchor = anchorPtLbl, anchorPoint = "BOTTOMLEFT", x = -16, y = -4, width = 160,
            items = GF_ANCHOR_POINTS,
            get = function(k) return GF.GetConf(k).anchorPoint or "CENTER" end,
            set = function(k, v)
                GF.GetConf(k).anchorPoint = v
                GF.RebuildAll()
            end,
        })

        -- Custom frame name input + Picker + Clear
        local customLbl = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        customLbl:SetPoint("TOPLEFT", anchorToDd, "BOTTOMLEFT", 16, -8)
        customLbl:SetText(TR("Custom Anchor Frame"))
        customLbl:SetTextColor(0.55, 0.65, 0.80)

        local customBox = CreateFrame("EditBox", "MSUF_GF_AnchorCustomBox", body, "InputBoxTemplate")
        customBox:SetSize(200, 22)
        customBox:SetPoint("TOPLEFT", customLbl, "BOTTOMLEFT", 4, -4)
        customBox:SetAutoFocus(false)
        customBox:SetMaxLetters(100)
        customBox:SetScript("OnEnterPressed", function(self)
            local conf = GF.GetConf(K())
            local val = self:GetText()
            if val == "" then
                conf.anchorToFrame = nil
            else
                conf.anchorToFrame = val
            end
            self:ClearFocus()
            GF.RebuildAll()
        end)
        customBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        local pickBtn = CreateFrame("Button", nil, body, "BackdropTemplate")
        pickBtn:SetSize(50, 22)
        pickBtn:SetPoint("LEFT", customBox, "RIGHT", 6, 0)
        pickBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        pickBtn:SetBackdropColor(0.15, 0.35, 0.55, 0.9)
        pickBtn:SetBackdropBorderColor(0.25, 0.45, 0.70, 0.8)
        local pickFS = pickBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pickFS:SetPoint("CENTER")
        pickFS:SetText(TR("Pick"))
        pickFS:SetTextColor(0.85, 0.92, 1.0)
        pickBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.25, 0.45, 0.70, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(TR("Click, then click on any frame on screen to anchor to it."))
            GameTooltip:Show()
        end)
        pickBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.15, 0.35, 0.55, 0.9)
            GameTooltip:Hide()
        end)
        pickBtn:SetScript("OnClick", function()
            local ov = type(_G.MSUF_EnsureAnchorPicker) == "function" and _G.MSUF_EnsureAnchorPicker() or nil
            if not ov then return end
            ov._onPick = function(frameName)
                local conf = GF.GetConf(K())
                conf.anchorToFrame = frameName
                customBox:SetText(frameName or "")
                GF.RebuildAll()
            end
            ov:Show()
        end)

        local clearBtn = CreateFrame("Button", nil, body, "BackdropTemplate")
        clearBtn:SetSize(50, 22)
        clearBtn:SetPoint("LEFT", pickBtn, "RIGHT", 4, 0)
        clearBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        clearBtn:SetBackdropColor(0.35, 0.15, 0.15, 0.9)
        clearBtn:SetBackdropBorderColor(0.55, 0.25, 0.25, 0.8)
        local clearFS = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        clearFS:SetPoint("CENTER")
        clearFS:SetText(TR("Clear"))
        clearFS:SetTextColor(1.0, 0.75, 0.75)
        clearBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.50, 0.20, 0.20, 1) end)
        clearBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.35, 0.15, 0.15, 0.9) end)
        clearBtn:SetScript("OnClick", function()
            local conf = GF.GetConf(K())
            conf.anchorToFrame = nil
            customBox:SetText("")
            GF.RebuildAll()
        end)

        _allRefreshFns[#_allRefreshFns + 1] = function()
            local conf = GF.GetConf(K())
            local atv = conf.anchorToFrame or ""
            local isStd = (atv == "" or atv == "FREE" or atv == "player" or atv == "target"
                or atv == "targettarget" or atv == "focus")
            customBox:SetText(isStd and "" or atv)
        end
    end

    ----------------------------------------------------------------
    -- Section 1c: Frame Scaling
    ----------------------------------------------------------------
    do
        local box, body = AddSection(380, "Frame Scaling", false, "scaling")

        local _scaleItems = {
            { key = "off",    label = TR("Off (100%)") },
            { key = "auto",   label = TR("Auto (by group size)") },
            { key = "manual", label = TR("Manual") },
        }
        local RefreshScalingState
        local scaleDd = SDropdown({
            name = "MSUF_GF_FrameScaleMode", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -8, width = 220,
            items = _scaleItems,
            get = function(k) return GF.Val(k, "frameScaleMode") or "off" end,
            set = function(k, v)
                GF.GetConf(k).frameScaleMode = v
                if RefreshScalingState then RefreshScalingState() end
                GF.RebuildAll()
            end,
        })
        local scaleDdLbl = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        scaleDdLbl:SetPoint("LEFT", scaleDd, "RIGHT", 8, 0)
        scaleDdLbl:SetText(TR("Scale Mode")); scaleDdLbl:SetTextColor(0.7, 0.7, 0.7)

        -- Manual slider (y=-22: slider has a 16px label-above region; the
        -- previous y=-6 made the label clip into the dropdown above)
        local scaleManualSl = SSlider({
            name = "MSUF_GF_FrameScaleManual", parent = body, compact = true,
            anchor = scaleDd, x = 0, y = -22,
            min = 50, max = 150, step = 5, width = 220, default = 100,
            get = function(k) return GF.Val(k, "frameScaleManual") or 100 end,
            set = function(k, v) GF.GetConf(k).frameScaleManual = v; GF.RebuildAll() end,
            formatText = function(v) return string.format("Manual Scale: %d%%", v) end,
        })

        -- Auto breakpoint sliders
        local autoLbl = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        autoLbl:SetPoint("TOPLEFT", scaleManualSl, "BOTTOMLEFT", 0, -10)
        autoLbl:SetText(TR("Auto Breakpoints")); autoLbl:SetTextColor(1, 0.82, 0)

        -- y=-22 (was -6): label-above space for the first breakpoint slider so
        -- "1-10 players" no longer overlaps the "Auto Breakpoints" header.
        local s10Sl = SSlider({
            name = "MSUF_GF_ScaleAt10", parent = body, compact = true,
            anchor = autoLbl, x = 0, y = -22,
            min = 50, max = 100, step = 5, width = 220, default = 100,
            get = function(k) return GF.Val(k, "scaleAt10") or 100 end,
            set = function(k, v) GF.GetConf(k).scaleAt10 = v; GF.RebuildAll() end,
            formatText = function(v) return string.format("1-10 players: %d%%", v) end,
        })
        local s20Sl = SSlider({
            name = "MSUF_GF_ScaleAt20", parent = body, compact = true,
            anchor = s10Sl, x = 0, y = -30,
            min = 50, max = 100, step = 5, width = 220, default = 85,
            get = function(k) return GF.Val(k, "scaleAt20") or 85 end,
            set = function(k, v) GF.GetConf(k).scaleAt20 = v; GF.RebuildAll() end,
            formatText = function(v) return string.format("11-20 players: %d%%", v) end,
        })
        local s25Sl = SSlider({
            name = "MSUF_GF_ScaleAt25", parent = body, compact = true,
            anchor = s20Sl, x = 0, y = -30,
            min = 50, max = 100, step = 5, width = 220, default = 80,
            get = function(k) return GF.Val(k, "scaleAt25") or 80 end,
            set = function(k, v) GF.GetConf(k).scaleAt25 = v; GF.RebuildAll() end,
            formatText = function(v) return string.format("21-25 players: %d%%", v) end,
        })
        local s26Sl = SSlider({
            name = "MSUF_GF_ScaleOver25", parent = body, compact = true,
            anchor = s25Sl, x = 0, y = -30,
            min = 50, max = 100, step = 5, width = 220, default = 70,
            get = function(k) return GF.Val(k, "scaleOver25") or 70 end,
            set = function(k, v) GF.GetConf(k).scaleOver25 = v; GF.RebuildAll() end,
            formatText = function(v) return string.format("26+ players: %d%%", v) end,
        })

        local scaleHint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        scaleHint:SetPoint("TOPLEFT", s26Sl, "BOTTOMLEFT", 4, -6)
        scaleHint:SetText(TR("Scales frame size, fonts, and icons proportionally.\nBuff/debuff positions stay relative to their anchors."))
        scaleHint:SetTextColor(0.5, 0.5, 0.6)
        scaleHint:SetWidth(320)
        scaleHint:SetJustifyH("LEFT")

        local function SetSliderEnabled(sl, enabled)
            if not sl then return end
            if sl.SetEnabled then
                sl:SetEnabled(enabled and true or false)
            elseif enabled then
                if sl.Enable then sl:Enable() end
                if sl.SetAlpha then sl:SetAlpha(1) end
            else
                if sl.Disable then sl:Disable() end
                if sl.SetAlpha then sl:SetAlpha(0.55) end
            end
            if sl.editBox and sl.editBox.SetAlpha then sl.editBox:SetAlpha(enabled and 1 or 0.55) end
            if sl.minusButton and sl.minusButton.SetAlpha then sl.minusButton:SetAlpha(enabled and 1 or 0.55) end
            if sl.plusButton and sl.plusButton.SetAlpha then sl.plusButton:SetAlpha(enabled and 1 or 0.55) end
        end

        RefreshScalingState = function()
            local mode = GF.Val(K(), "frameScaleMode") or "off"
            local manualOn = (mode == "manual")
            local autoOn = (mode == "auto")

            SetSliderEnabled(scaleManualSl, manualOn)
            SetSliderEnabled(s10Sl, autoOn)
            SetSliderEnabled(s20Sl, autoOn)
            SetSliderEnabled(s25Sl, autoOn)
            SetSliderEnabled(s26Sl, autoOn)

            if autoLbl then
                autoLbl:SetTextColor(autoOn and 1 or 0.35, autoOn and 0.82 or 0.35, autoOn and 0 or 0.35)
                autoLbl:SetAlpha(autoOn and 1 or 0.55)
            end
            if scaleHint then scaleHint:SetAlpha((manualOn or autoOn) and 1 or 0.55) end
        end
        RefreshScalingState()
        _allRefreshFns[#_allRefreshFns + 1] = function()
            if body:IsShown() and RefreshScalingState then RefreshScalingState() end
        end
    end

    ----------------------------------------------------------------
    -- Section 2: Health Colors (GF-independent bar mode)
    ----------------------------------------------------------------
    do
        local box, body = AddSection(120, "Health Colors", false, "hcolor")

        local modeLbl = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        modeLbl:SetPoint("TOPLEFT", body, "TOPLEFT", 14, -8)
        modeLbl:SetText(TR("Bar Color Mode"))

        local GF_BAR_MODES = {
            { key = "GLOBAL",   label = TR("Follow Global Style") },
            { key = "CLASS",    label = TR("Class Color") },
            { key = "dark",     label = TR("Dark Mode") },
            { key = "unified",  label = TR("Unified Color") },
            { key = "GRADIENT", label = TR("Health Gradient") },
            { key = "CUSTOM",   label = TR("Custom Color") },
        }

        local gfColorSwatch, gfColorHint
        local function RefreshColorControls()
            -- Dynamic title badge
            local conf = GF.GetConf(K())
            local m = conf.gfBarMode
            if box._msufTitleFS then
                if not m or m == "GLOBAL" then
                    box._msufTitleFS:SetText(TR("Health Colors") .. "  |cff888888(Global)|r")
                else
                    box._msufTitleFS:SetText(TR("Health Colors") .. "  |cff88aacc(Custom)|r")
                end
            end
            if not gfColorSwatch then return end
            if m == "dark" or m == "unified" or m == "CUSTOM" then
                gfColorSwatch:Show()
                local r, g, b
                if m == "dark" then
                    r = conf.gfDarkR or 0; g = conf.gfDarkG or 0; b = conf.gfDarkB or 0
                elseif m == "unified" then
                    r = conf.gfUnifiedR or 0.10; g = conf.gfUnifiedG or 0.60; b = conf.gfUnifiedB or 0.90
                else
                    r = conf.healthCustomR or 0.2; g = conf.healthCustomG or 0.8; b = conf.healthCustomB or 0.2
                end
                local tex = gfColorSwatch._tex
                if tex then tex:SetColorTexture(r, g, b) end
            else
                gfColorSwatch:Hide()
            end
            if gfColorHint then
                if not m or m == "GLOBAL" then
                    gfColorHint:SetText(TR("Health bar colors follow |cffffd200Global Style > Colors|r."))
                    gfColorHint:Show()
                else
                    gfColorHint:Hide()
                end
            end
        end

        local gfModeDd = SDropdown({
            name = "MSUF_GF_BarModeDropdown", parent = body,
            anchor = modeLbl, anchorPoint = "BOTTOMLEFT", x = -16, y = -4, width = 260,
            items = GF_BAR_MODES,
            get = function(k) return GF.GetConf(k).gfBarMode or "GLOBAL" end,
            set = function(k, v)
                local conf = GF.GetConf(k)
                conf.gfBarMode = (v == "GLOBAL") and nil or v
                if v == "CLASS" or v == "GRADIENT" then
                    conf.healthColorMode = v
                end
                GF.RefreshVisuals()
                RefreshColorControls()
            end,
        })

        gfColorSwatch = MakeColorSwatch(body,
            gfModeDd, "BOTTOMLEFT", 16, -12, TR("Bar Color"),
            function()
                local conf = GF.GetConf(K())
                local m = conf.gfBarMode
                if m == "dark" then
                    return conf.gfDarkR or 0, conf.gfDarkG or 0, conf.gfDarkB or 0
                elseif m == "unified" then
                    return conf.gfUnifiedR or 0.10, conf.gfUnifiedG or 0.60, conf.gfUnifiedB or 0.90
                else
                    return conf.healthCustomR or 0.2, conf.healthCustomG or 0.8, conf.healthCustomB or 0.2
                end
            end,
            function(r, g, b)
                local conf = GF.GetConf(K())
                local m = conf.gfBarMode
                if m == "dark" then
                    conf.gfDarkR = r; conf.gfDarkG = g; conf.gfDarkB = b
                elseif m == "unified" then
                    conf.gfUnifiedR = r; conf.gfUnifiedG = g; conf.gfUnifiedB = b
                else
                    conf.healthCustomR = r; conf.healthCustomG = g; conf.healthCustomB = b
                end
                GF.RefreshVisuals()
            end
        )

        gfColorHint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        gfColorHint:SetPoint("TOPLEFT", gfModeDd, "BOTTOMLEFT", 16, -8)
        gfColorHint:SetWidth(600)
        gfColorHint:SetJustifyH("LEFT")
        gfColorHint:SetTextColor(0.55, 0.60, 0.70)

        _allRefreshFns[#_allRefreshFns + 1] = RefreshColorControls
        RefreshColorControls()
    end

    ----------------------------------------------------------------
    -- Section 3: Power Bar
    ----------------------------------------------------------------
    do
        local box, body = AddSection(280, "Power Bar", false, "power")

        local phSl = SSlider({
            name = "MSUF_GF_PowerHeightSlider", parent = body, compact = true,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -10,
            min = 0, max = 30, step = 1, width = 270, default = 6,
            get = function(k) return GF.Val(k, "powerHeight") end,
            set = function(k, v) GF.GetConf(k).powerHeight = v; GF.RefreshGeometry() end,
            formatText = function(v) return v == 0 and "Power Bar: Hidden" or string.format("Power Bar Height: %d", v) end,
        })

        local powSmoothChk = SCheck({
            name = "MSUF_GF_PowerSmoothFillCheck", parent = body,
            anchor = phSl, x = 0, y = -14,
            label = TR("Smooth Fill"),
            get = function(k) return GF.Val(k, "powerSmoothFill") end,
            set = function(k, v) GF.GetConf(k).powerSmoothFill = v end,
        })

        -- Hint: power text settings in Edit Mode popup
        local ptHint = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ptHint:SetPoint("TOPLEFT", powSmoothChk, "BOTTOMLEFT", 0, -10)
        ptHint:SetText(TR("Power text modes, delimiter and font size\nare in the Edit Mode popup."))
        ptHint:SetTextColor(0.55, 0.75, 1.0)
        ptHint:SetJustifyH("LEFT")

        -- Power per-role visibility
        local roleSep = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        roleSep:SetPoint("TOPLEFT", ptHint, "BOTTOMLEFT", 0, -12)
        roleSep:SetText(TR("Show Power for Roles"))
        roleSep:SetTextColor(1, 0.82, 0)

        local tankChk = SCheck({
            name = "MSUF_GF_PowerShowTankCheck", parent = body,
            anchor = roleSep, anchorPoint = "BOTTOMLEFT", x = 0, y = -4,
            label = TR("Tank"),
            get = function(k) return GF.Val(k, "powerShowTank") ~= false end,
            set = function(k, v) GF.GetConf(k).powerShowTank = v; GF.RefreshVisuals() end,
        })

        local healerChk = SCheck({
            name = "MSUF_GF_PowerShowHealerCheck", parent = body,
            anchor = tankChk, x = 0, y = -4,
            label = TR("Healer"),
            get = function(k) return GF.Val(k, "powerShowHealer") ~= false end,
            set = function(k, v) GF.GetConf(k).powerShowHealer = v; GF.RefreshVisuals() end,
        })

        SCheck({
            name = "MSUF_GF_PowerShowDamagerCheck", parent = body,
            anchor = healerChk, x = 0, y = -4,
            label = TR("DPS"),
            get = function(k) return GF.Val(k, "powerShowDamager") end,
            set = function(k, v) GF.GetConf(k).powerShowDamager = v; GF.RefreshVisuals() end,
        })
    end

    ----------------------------------------------------------------
    -- Section 4: Text
    ----------------------------------------------------------------
    do
        local box, body = AddSection(800, "Text", false, "text")

        local COL_W = 310

        -- Redirect hint (full width)
        local hintFS = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hintFS:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -8)
        hintFS:SetText(TR("Font, outline and color are controlled globally in |cffffd200Global Style > Fonts|r."))
        hintFS:SetTextColor(0.55, 0.75, 1.0); hintFS:SetJustifyH("LEFT"); hintFS:SetWordWrap(true); hintFS:SetWidth(600)

        -- EM2 bridge hint (full width)
        local em2HintFS = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        em2HintFS:SetPoint("TOPLEFT", hintFS, "BOTTOMLEFT", 0, -3)
        em2HintFS:SetText(TR("Tip: positions can also be dragged in |cffffd200Edit Mode|r — changes sync live both ways."))
        em2HintFS:SetTextColor(0.50, 0.55, 0.65); em2HintFS:SetJustifyH("LEFT"); em2HintFS:SetWordWrap(true); em2HintFS:SetWidth(600)

        -- Two column anchors
        local colL = CreateFrame("Frame", nil, body); colL:SetSize(COL_W, 1)
        colL:SetPoint("TOPLEFT", em2HintFS, "BOTTOMLEFT", 0, -10)
        local colR = CreateFrame("Frame", nil, body); colR:SetSize(COL_W, 1)
        colR:SetPoint("TOPLEFT", colL, "TOPRIGHT", 20, 0)

        -- Subtle vertical divider between the two columns. Spans most of the
        -- content area; matches the section's accent palette for visual coherence.
        local vColDiv = body:CreateTexture(nil, "ARTWORK")
        vColDiv:SetWidth(1)
        vColDiv:SetColorTexture(0.20, 0.32, 0.45, 0.35)
        vColDiv:SetPoint("TOPLEFT",    colL, "TOPLEFT",    COL_W + 10, 4)
        vColDiv:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 12 + COL_W + 10, 12)

        -- Shared mode items (used by HP + Power dropdowns)
        local TEXT_MODES = function()
            return GF.HEALTH_TEXT_MODES or {
                { key = "NONE", label = TR("None") }, { key = "PERCENT", label = "%" },
                { key = "CURRENT", label = TR("Current") }, { key = "DEFICIT", label = TR("Deficit") },
                { key = "CURMAX", label = TR("Cur / Max") }, { key = "CURPERCENT", label = TR("Cur / %") },
            }
        end
        local DELIM_ITEMS = function()
            return GF.DELIMITER_OPTIONS or {
                { key = " / ", label = "/" }, { key = " - ", label = "-" }, { key = " ", label = TR("Space") },
            }
        end
        local refreshTextControlStates

        -- ════════════════════════════════════════════════
        -- LEFT COLUMN: Name + Status/Layer
        -- ════════════════════════════════════════════════

        -- ── Name ──
        local nameSep = colL:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameSep:SetPoint("TOPLEFT", colL, "TOPLEFT", 0, 0)
        nameSep:SetText(TR("Name")); nameSep:SetTextColor(1, 0.82, 0)

        local nameShowChk = SCheck({
            name = "MSUF_GF_NameShowCheck", parent = colL,
            anchor = nameSep, x = 0, y = -4,
            label = TR("Show Name"),
            get = function(k) return GF.Val(k, "showName") end,
            set = function(k, v)
                GF.GetConf(k).showName = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT); GF.RefreshVisuals()
                if refreshTextControlStates then refreshTextControlStates() end
            end,
        })

        local nameSizeSl = SSlider({
            name = "MSUF_GF_NameFontSizeSlider", parent = colL, compact = true,
            anchor = nameShowChk, x = 0, y = -26,
            min = 6, max = 48, step = 1, width = 180, default = 12,
            get = function(k) return GF.Val(k, "nameFontSize") end,
            set = function(k, v) GF.GetConf(k).nameFontSize = v; GF.RefreshFonts(); GF.RefreshVisuals() end,
            formatText = function(v) return string.format("Size: %d", v) end,
        })

        local nameAnchorDd = SDropdown({
            name = "MSUF_GF_NameAnchorDropdown", parent = colL,
            anchor = nameSizeSl, anchorPoint = "BOTTOMLEFT", x = -16, y = -8, width = 180,
            items = { { key = "LEFT", label = TR("Left") }, { key = "CENTER", label = TR("Center") }, { key = "RIGHT", label = TR("Right") } },
            get = function(k) return GF.Val(k, "nameAnchor") or "LEFT" end,
            set = function(k, v) GF.GetConf(k).nameAnchor = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT); GF.RefreshVisuals() end,
        })

        local nameXSl = SSlider({
            name = "MSUF_GF_NameOffsetXSlider", parent = colL, compact = true,
            anchor = nameAnchorDd, x = 16, y = -26,
            min = -100, max = 100, step = 1, width = 180, default = 0,
            get = function(k) return GF.Val(k, "nameOffsetX") end,
            set = function(k, v) GF.GetConf(k).nameOffsetX = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT) end,
            formatText = function(v) return string.format("X: %d", v) end,
        })
        local nameYSl = SSlider({
            name = "MSUF_GF_NameOffsetYSlider", parent = colL, compact = true,
            anchor = nameXSl, x = 0, y = -32,
            min = -100, max = 100, step = 1, width = 180, default = 0,
            get = function(k) return GF.Val(k, "nameOffsetY") end,
            set = function(k, v) GF.GetConf(k).nameOffsetY = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT) end,
            formatText = function(v) return string.format("Y: %d", v) end,
        })

        -- Subtle horizontal divider separating Name and Power Text sub-sections
        local lcSubDiv = colL:CreateTexture(nil, "ARTWORK")
        lcSubDiv:SetHeight(1)
        lcSubDiv:SetColorTexture(0.20, 0.32, 0.45, 0.30)
        lcSubDiv:SetPoint("TOPLEFT",  nameYSl, "BOTTOMLEFT", -8, -14)
        lcSubDiv:SetPoint("TOPRIGHT", nameYSl, "BOTTOMRIGHT", 100, -14)

        -- ── Power Text ── (left column, below Name)
        local powSep = colL:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        powSep:SetPoint("TOPLEFT", nameYSl, "BOTTOMLEFT", 0, -28)
        powSep:SetText(TR("Power Text")); powSep:SetTextColor(1, 0.82, 0)
        local powLeftLbl, powCenterLbl, powRightLbl, powDelimLbl

        local powShowChk = SCheck({
            name = "MSUF_GF_PowerShowCheck", parent = colL,
            anchor = powSep, x = 0, y = -4,
            label = TR("Show Power Text"),
            get = function(k) return (GF.IsPowerTextEnabled and GF.IsPowerTextEnabled(k)) or false end,
            set = function(k, v)
                if GF.SetPowerTextEnabled then GF.SetPowerTextEnabled(k, v) else local c = GF.GetConf(k); c.showPower = v; c.showPowerText = v end
                GF.MarkAllDirty(GF.DIRTY_LAYOUT); GF.RefreshVisuals()
                if GF._RequestOptionsResync then GF._RequestOptionsResync() end
                SyncGFEditPopup()
                if refreshTextControlStates then refreshTextControlStates() end
            end,
        })

        local powLeftDd = SDropdown({
            name = "MSUF_GF_PowerTextLeftDropdown", parent = colL,
            anchor = powShowChk, anchorPoint = "BOTTOMLEFT", x = -16, y = -32, width = 180,
            items = TEXT_MODES,
            get = function(k) return GF.Val(k, "powerTextLeft") or "NONE" end,
            set = function(k, v) GF.GetConf(k).powerTextLeft = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT); GF.RefreshVisuals(); SyncGFEditPopup() end,
        })
        powLeftLbl = colL:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        powLeftLbl:SetPoint("BOTTOMLEFT", powLeftDd, "TOPLEFT", 18, 1); powLeftLbl:SetText(TR("Left")); powLeftLbl:SetTextColor(0.6, 0.6, 0.6)

        local powCenterDd = SDropdown({
            name = "MSUF_GF_PowerTextCenterDropdown", parent = colL,
            anchor = powLeftDd, anchorPoint = "BOTTOMLEFT", x = 0, y = -22, width = 180,
            items = TEXT_MODES,
            get = function(k) return GF.Val(k, "powerTextCenter") or "NONE" end,
            set = function(k, v) GF.GetConf(k).powerTextCenter = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT); GF.RefreshVisuals(); SyncGFEditPopup() end,
        })
        powCenterLbl = colL:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        powCenterLbl:SetPoint("BOTTOMLEFT", powCenterDd, "TOPLEFT", 18, 1); powCenterLbl:SetText(TR("Center")); powCenterLbl:SetTextColor(0.6, 0.6, 0.6)

        local powRightDd = SDropdown({
            name = "MSUF_GF_PowerTextRightDropdown", parent = colL,
            anchor = powCenterDd, anchorPoint = "BOTTOMLEFT", x = 0, y = -22, width = 180,
            items = TEXT_MODES,
            get = function(k) return GF.Val(k, "powerTextRight") or "NONE" end,
            set = function(k, v) GF.GetConf(k).powerTextRight = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT); GF.RefreshVisuals(); SyncGFEditPopup() end,
        })
        powRightLbl = colL:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        powRightLbl:SetPoint("BOTTOMLEFT", powRightDd, "TOPLEFT", 18, 1); powRightLbl:SetText(TR("Right")); powRightLbl:SetTextColor(0.6, 0.6, 0.6)

        local powDelimDd = SDropdown({
            name = "MSUF_GF_PowerDelimDropdown", parent = colL,
            anchor = powRightDd, anchorPoint = "BOTTOMLEFT", x = 0, y = -22, width = 180,
            items = DELIM_ITEMS,
            get = function(k) return GF.Val(k, "powerTextDelimiter") or " / " end,
            set = function(k, v) GF.GetConf(k).powerTextDelimiter = v; GF.RefreshVisuals(); SyncGFEditPopup() end,
        })
        powDelimLbl = colL:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        powDelimLbl:SetPoint("BOTTOMLEFT", powDelimDd, "TOPLEFT", 18, 1); powDelimLbl:SetText(TR("Delimiter")); powDelimLbl:SetTextColor(0.6, 0.6, 0.6)

        local powSizeSl = SSlider({
            name = "MSUF_GF_PowerFontSizeSlider", parent = colL, compact = true,
            anchor = powDelimDd, x = 16, y = -26,
            min = 6, max = 48, step = 1, width = 180, default = 9,
            get = function(k) return GF.Val(k, "powerFontSize") end,
            set = function(k, v) GF.GetConf(k).powerFontSize = v; GF.RefreshFonts(); GF.RefreshVisuals(); SyncGFEditPopup() end,
            formatText = function(v) return string.format("Size: %d", v) end,
        })

        local powXSl = SSlider({
            name = "MSUF_GF_PowerOffsetXSlider", parent = colL, compact = true,
            anchor = powSizeSl, x = 0, y = -32,
            min = -100, max = 100, step = 1, width = 180, default = 0,
            get = function(k) return GF.Val(k, "powerOffsetX") end,
            set = function(k, v) GF.GetConf(k).powerOffsetX = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT); SyncGFEditPopup() end,
            formatText = function(v) return string.format("X: %d", v) end,
        })
        local powYSl = SSlider({
            name = "MSUF_GF_PowerOffsetYSlider", parent = colL, compact = true,
            anchor = powXSl, x = 0, y = -32,
            min = -100, max = 100, step = 1, width = 180, default = 0,
            get = function(k) return GF.Val(k, "powerOffsetY") end,
            set = function(k, v) GF.GetConf(k).powerOffsetY = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT); SyncGFEditPopup() end,
            formatText = function(v) return string.format("Y: %d", v) end,
        })

        -- ════════════════════════════════════════════════
        -- RIGHT COLUMN: HP Text + Status/Layer
        -- ════════════════════════════════════════════════

        -- ── HP Text ──
        local hpSep = colR:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hpSep:SetPoint("TOPLEFT", colR, "TOPLEFT", 0, 0)
        hpSep:SetText(TR("HP Text")); hpSep:SetTextColor(1, 0.82, 0)
        local hpLeftLbl, hpCenterLbl, hpRightLbl, hpDelimLbl

        local hpShowChk = SCheck({
            name = "MSUF_GF_HPTextShowCheck", parent = colR,
            anchor = hpSep, x = 0, y = -4,
            label = TR("Show HP Text"),
            get = function(k) return GF.Val(k, "showHPText") ~= false end,
            set = function(k, v)
                GF.GetConf(k).showHPText = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT); GF.RefreshVisuals()
                if refreshTextControlStates then refreshTextControlStates() end
            end,
        })

        local hpLeftDd = SDropdown({
            name = "MSUF_GF_TextLeftDropdown", parent = colR,
            anchor = hpShowChk, anchorPoint = "BOTTOMLEFT", x = -16, y = -32, width = 180,
            items = TEXT_MODES,
            get = function(k) return GF.Val(k, "textLeft") or "NONE" end,
            set = function(k, v) GF.GetConf(k).textLeft = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT); GF.RefreshVisuals() end,
        })
        hpLeftLbl = colR:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hpLeftLbl:SetPoint("BOTTOMLEFT", hpLeftDd, "TOPLEFT", 18, 1); hpLeftLbl:SetText(TR("Left")); hpLeftLbl:SetTextColor(0.6, 0.6, 0.6)

        local hpCenterDd = SDropdown({
            name = "MSUF_GF_TextCenterDropdown", parent = colR,
            anchor = hpLeftDd, anchorPoint = "BOTTOMLEFT", x = 0, y = -22, width = 180,
            items = TEXT_MODES,
            get = function(k) return GF.Val(k, "textCenter") or "NONE" end,
            set = function(k, v) GF.GetConf(k).textCenter = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT); GF.RefreshVisuals() end,
        })
        hpCenterLbl = colR:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hpCenterLbl:SetPoint("BOTTOMLEFT", hpCenterDd, "TOPLEFT", 18, 1); hpCenterLbl:SetText(TR("Center")); hpCenterLbl:SetTextColor(0.6, 0.6, 0.6)

        local hpRightDd = SDropdown({
            name = "MSUF_GF_TextRightDropdown", parent = colR,
            anchor = hpCenterDd, anchorPoint = "BOTTOMLEFT", x = 0, y = -22, width = 180,
            items = TEXT_MODES,
            get = function(k) return GF.Val(k, "textRight") or "NONE" end,
            set = function(k, v) GF.GetConf(k).textRight = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT); GF.RefreshVisuals() end,
        })
        hpRightLbl = colR:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hpRightLbl:SetPoint("BOTTOMLEFT", hpRightDd, "TOPLEFT", 18, 1); hpRightLbl:SetText(TR("Right")); hpRightLbl:SetTextColor(0.6, 0.6, 0.6)

        local hpDelimDd = SDropdown({
            name = "MSUF_GF_HPDelimDropdown", parent = colR,
            anchor = hpRightDd, anchorPoint = "BOTTOMLEFT", x = 0, y = -22, width = 180,
            items = DELIM_ITEMS,
            get = function(k) return GF.Val(k, "textDelimiter") or " / " end,
            set = function(k, v) GF.GetConf(k).textDelimiter = v; GF.RefreshVisuals() end,
        })
        hpDelimLbl = colR:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hpDelimLbl:SetPoint("BOTTOMLEFT", hpDelimDd, "TOPLEFT", 18, 1); hpDelimLbl:SetText(TR("Delimiter")); hpDelimLbl:SetTextColor(0.6, 0.6, 0.6)

        local hpReverseCB = SCheck({
            name = "MSUF_GF_HPReverseCheck", parent = colR,
            anchor = hpDelimDd, x = 16, y = -8,
            label = TR("Reverse Order"),
            get = function(k) return GF.Val(k, "hpTextReverse") end,
            set = function(k, v) GF.GetConf(k).hpTextReverse = v; GF.RefreshVisuals() end,
        })

        local hpSizeSl = SSlider({
            name = "MSUF_GF_HPFontSizeSlider", parent = colR, compact = true,
            anchor = hpReverseCB, x = 0, y = -26,
            min = 6, max = 48, step = 1, width = 180, default = 10,
            get = function(k) return GF.Val(k, "hpFontSize") end,
            set = function(k, v) GF.GetConf(k).hpFontSize = v; GF.RefreshFonts(); GF.RefreshVisuals() end,
            formatText = function(v) return string.format("Size: %d", v) end,
        })

        local hpXSl = SSlider({
            name = "MSUF_GF_HPOffsetXSlider", parent = colR, compact = true,
            anchor = hpSizeSl, x = 0, y = -32,
            min = -100, max = 100, step = 1, width = 180, default = 0,
            get = function(k) return GF.Val(k, "hpOffsetX") end,
            set = function(k, v) GF.GetConf(k).hpOffsetX = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT) end,
            formatText = function(v) return string.format("X: %d", v) end,
        })
        local hpYSl = SSlider({
            name = "MSUF_GF_HPOffsetYSlider", parent = colR, compact = true,
            anchor = hpXSl, x = 0, y = -32,
            min = -100, max = 100, step = 1, width = 180, default = 0,
            get = function(k) return GF.Val(k, "hpOffsetY") end,
            set = function(k, v) GF.GetConf(k).hpOffsetY = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT) end,
            formatText = function(v) return string.format("Y: %d", v) end,
        })

        -- Subtle horizontal divider separating HP Text and text-layer controls
        local rcSubDiv = colR:CreateTexture(nil, "ARTWORK")
        rcSubDiv:SetHeight(1)
        rcSubDiv:SetColorTexture(0.20, 0.32, 0.45, 0.30)
        rcSubDiv:SetPoint("TOPLEFT",  hpYSl, "BOTTOMLEFT", -8, -14)
        rcSubDiv:SetPoint("TOPRIGHT", hpYSl, "BOTTOMRIGHT", 100, -14)

        -- Text layers (right column, below HP)
        local tOffSep = colR:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tOffSep:SetPoint("TOPLEFT", hpYSl, "BOTTOMLEFT", 0, -28)
        tOffSep:SetText(TR("Text Layers")); tOffSep:SetTextColor(1, 0.82, 0)

        local nameLaySl = SSlider({
            name = "MSUF_GF_NameTextLayerSlider", parent = colR, compact = true,
            anchor = tOffSep, x = 0, y = -26,
            min = 1, max = 15, step = 1, width = 180, default = 5,
            get = function(k) return GF.Val(k, "nameTextLayer") end,
            set = function(k, v) GF.GetConf(k).nameTextLayer = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT) end,
            formatText = function(v) return string.format("Name Layer: %d", v) end,
        })
        local hpLaySl = SSlider({
            name = "MSUF_GF_TextLayerSlider", parent = colR, compact = true,
            anchor = nameLaySl, x = 0, y = -32,
            min = 1, max = 15, step = 1, width = 180, default = 5,
            get = function(k) return GF.Val(k, "textLayer") end,
            set = function(k, v) GF.GetConf(k).textLayer = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT) end,
            formatText = function(v) return string.format("HP Layer: %d", v) end,
        })
        local powerLaySl = SSlider({
            name = "MSUF_GF_PowerTextLayerSlider", parent = colR, compact = true,
            anchor = hpLaySl, x = 0, y = -32,
            min = 1, max = 15, step = 1, width = 180, default = 2,
            get = function(k) return GF.Val(k, "powerTextLayer") end,
            set = function(k, v) GF.GetConf(k).powerTextLayer = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT); SyncGFEditPopup() end,
            formatText = function(v) return string.format("Power Layer: %d", v) end,
        })

        refreshTextControlStates = function()
            local kind = K()
            local nameEnabled = GF.Val(kind, "showName") and true or false
            local powerEnabled = (GF.IsPowerTextEnabled and GF.IsPowerTextEnabled(kind)) or false
            local hpEnabled = GF.Val(kind, "showHPText") ~= false

            SetGFOptionControlsEnabled(nameEnabled, { nameSizeSl, nameAnchorDd, nameXSl, nameYSl, nameLaySl })
            SetGFOptionControlsEnabled(powerEnabled,
                { powLeftDd, powCenterDd, powRightDd, powDelimDd, powSizeSl, powXSl, powYSl, powerLaySl },
                { powLeftLbl, powCenterLbl, powRightLbl, powDelimLbl })
            SetGFOptionControlsEnabled(hpEnabled,
                { hpLeftDd, hpCenterDd, hpRightDd, hpDelimDd, hpReverseCB, hpSizeSl, hpXSl, hpYSl, hpLaySl },
                { hpLeftLbl, hpCenterLbl, hpRightLbl, hpDelimLbl })
        end
        _allRefreshFns[#_allRefreshFns + 1] = function()
            if refreshTextControlStates then refreshTextControlStates() end
        end
        if body.HookScript then body:HookScript("OnShow", function() if refreshTextControlStates then refreshTextControlStates() end end) end
        refreshTextControlStates()

    end

    ----------------------------------------------------------------
    -- Section 5: Bars
    ----------------------------------------------------------------
    do
        local box, body = AddSection(170, "Bars", false, "bars")

        -- Forward declare for set callbacks
        local RefreshBarsTitle

        local fgLbl = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fgLbl:SetPoint("TOPLEFT", body, "TOPLEFT", 14, -10)
        fgLbl:SetText(TR("Foreground Texture"))

        local fgDd = SDropdown({
            name = "MSUF_GF_BarTextureDropdown", parent = body,
            anchor = fgLbl, anchorPoint = "BOTTOMLEFT", x = -16, y = -4, width = 280, maxVisible = 12,
            iconWidth = 80, iconHeight = 12,
            items = function()
                return UI.StatusBarTextureItems(TR("(Follow Global Style)"))
            end,
            get = function(k) return GF.Val(k, "barTexture") or "" end,
            set = function(k, v)
                GF.GetConf(k).barTexture = (v ~= "" and v) or nil
                GF.RefreshTextures()
                if RefreshBarsTitle then RefreshBarsTitle() end
            end,
        })

        local bgLbl = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bgLbl:SetPoint("TOPLEFT", fgDd, "BOTTOMLEFT", 16, -10)
        bgLbl:SetText(TR("Background Texture"))

        SDropdown({
            name = "MSUF_GF_BarBackgroundTextureDropdown", parent = body,
            anchor = bgLbl, anchorPoint = "BOTTOMLEFT", x = -16, y = -4, width = 280, maxVisible = 12,
            iconWidth = 80, iconHeight = 12,
            items = function()
                return UI.StatusBarTextureItems(TR("(Follow Global Style)"))
            end,
            get = function(k) return GF.Val(k, "barBgTexture") or "" end,
            set = function(k, v)
                GF.GetConf(k).barBgTexture = (v ~= "" and v) or nil
                GF.RefreshTextures()
                if RefreshBarsTitle then RefreshBarsTitle() end
            end,
        })

        -- Dynamic title badge
        RefreshBarsTitle = function()
            if not box._msufTitleFS then return end
            local conf = GF.GetConf(K())
            local fg = conf.barTexture
            local bg = conf.barBgTexture
            local isGlobal = (not fg or fg == "") and (not bg or bg == "")
            if isGlobal then
                box._msufTitleFS:SetText(TR("Bars") .. "  |cff888888(Global)|r")
            else
                box._msufTitleFS:SetText(TR("Bars") .. "  |cff88aacc(Custom)|r")
            end
        end
        _allRefreshFns[#_allRefreshFns + 1] = RefreshBarsTitle
        RefreshBarsTitle()
    end

    ----------------------------------------------------------------
    -- Section 6: Transparency
    ----------------------------------------------------------------
    do
        local box, body = AddSection(310, "Transparency", false, "border")

        -- Hint: outline border is controlled in Bars menu
        local hint = body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", body, "TOPLEFT", 14, -8)
        hint:SetWidth(270); hint:SetJustifyH("LEFT")
        hint:SetText(TR("Outline border thickness is configured in\nGlobal Style > Bars > Outline & Highlight Border."))
        hint:SetTextColor(0.6, 0.75, 1.0)

        local bgLbl, bgSwatch = MakeColorSwatch(body, hint, "BOTTOMLEFT", 0, -12,
            "Background Color",
            function() return V("bgR"), V("bgG"), V("bgB") end,
            function(r, g, b)
                local c = C(); c.bgR = r; c.bgG = g; c.bgB = b
                GF.MarkAllDirty(GF.DIRTY_BORDER)
            end)
        _allRefreshFns[#_allRefreshFns + 1] = function()
            if bgSwatch and bgSwatch.Refresh and bgSwatch:IsShown() then bgSwatch:Refresh() end
        end

        SSlider({
            name = "MSUF_GF_BgAlphaSlider", parent = body, compact = true,
            anchor = bgLbl, x = 0, y = -20,
            min = 0, max = 1, step = 0.05, width = 270, default = 0.85,
            get = function(k) return GF.Val(k, "bgA") end,
            set = function(k, v) GF.GetConf(k).bgA = v; GF.MarkAllDirty(GF.DIRTY_BORDER) end,
            formatText = function(v) return string.format("Background Alpha: %.0f%%", v * 100) end,
        })

        -- Health Bar Foreground Opacity (how transparent the HP fill is)
        local hpFgSl = SSlider({
            name = "MSUF_GF_HpBarAlphaSlider", parent = body, compact = true,
            anchor = bgLbl, x = 0, y = -56,
            min = 0.3, max = 1, step = 0.05, width = 270, default = 1,
            get = function(k) return GF.Val(k, "hpBarAlpha") or 1 end,
            set = function(k, v) GF.GetConf(k).hpBarAlpha = v; GF.MarkAllDirty(GF.DIRTY_COLOR) end,
            formatText = function(v) return string.format("HP Bar Foreground: %.0f%%", v * 100) end,
        })

        SCheck({
            name = "MSUF_GF_PreserveHPColorCheck", parent = body,
            anchor = bgLbl, anchorPoint = "TOPLEFT", x = 320, y = -56,
            label = TR("Preserve HP color"),
            maxTextWidth = 220,
            tooltip = TR("On: HP stays transparent and missing health is dark like Unhalted. Off: normal background transparency is used."),
            get = function(k) return GF.Val(k, "alphaPreserveHPColor") == true end,
            set = function(k, v)
                GF.GetConf(k).alphaPreserveHPColor = v
                GF.MarkAllDirty(GF.DIRTY_COLOR)
                if GF.RefreshRangeFade then GF.RefreshRangeFade() else GF.RefreshVisuals() end
            end,
        })

        -- Text ignores foreground opacity (stays full alpha when bar is transparent)
        SCheck({
            name = "MSUF_GF_HpTextIgnoreAlpha", parent = body,
            anchor = bgLbl, anchorPoint = "TOPLEFT", x = 0, y = -86,
            label = TR("Text ignores HP opacity"),
            get = function(k) return GF.Val(k, "hpTextIgnoreAlpha") ~= false end,
            set = function(k, v) GF.GetConf(k).hpTextIgnoreAlpha = v; GF.MarkAllDirty(GF.DIRTY_COLOR) end,
        })

        -- Health Background Opacity (missing-HP area tint, affects behind-bar icon visibility)
        -- y=-138 (was -112): the previous offset put this slider's label-above
        -- region 12px INSIDE the "Text ignores HP opacity" checkbox row. The
        -- gap accounts for the 16px label band plus an 8px visual breath.
        SSlider({
            name = "MSUF_GF_HpBgAlphaSlider", parent = body, compact = true,
            anchor = bgLbl, x = 0, y = -138,
            min = 0, max = 1, step = 0.05, width = 270, default = 0.85,
            get = function(k) return GF.Val(k, "hpBgAlpha") or GF.Val(k, "bgA") or 0.85 end,
            set = function(k, v) GF.GetConf(k).hpBgAlpha = v; GF.MarkAllDirty(GF.DIRTY_BORDER) end,
            formatText = function(v) return string.format("HP Background: %.0f%%", v * 100) end,
        })

    end

    ----------------------------------------------------------------
    -- Section 7: Range Fade
    ----------------------------------------------------------------
    do
        local box, body = AddSection(210, "Range Fade", false, "range")

        local enChk = SCheck({
            name = "MSUF_GF_RangeFadeEnableCheck", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -6,
            label = TR("Enable Range Fade"),
            get = function(k) return GF.Val(k, "rangeFadeEnabled") end,
            set = function(k, v) GF.GetConf(k).rangeFadeEnabled = v; GF.RefreshVisuals() end,
        })

        local layerLbl = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        layerLbl:SetPoint("TOPLEFT", enChk, "BOTTOMLEFT", 0, -10)
        layerLbl:SetText(TR("Range fade affects"))
        layerLbl:SetTextColor(1, 0.82, 0)

        local layerDd = SDropdown({
            name = "MSUF_GF_RangeFadeLayerDropdown", parent = body,
            anchor = layerLbl, x = -16, y = -4, width = 180,
            items = {
                { key = "frame", label = TR("Frame") },
                { key = "health", label = TR("HP Bar") },
            },
            get = function(k)
                local v = GF.Val(k, "rangeFadeLayerMode")
                return (v == "health" or v == "hp" or v == "hpbar" or v == 2) and "health" or "frame"
            end,
            set = function(k, v)
                GF.GetConf(k).rangeFadeLayerMode = (v == "health") and "health" or "frame"
                if GF.RefreshRangeFade then GF.RefreshRangeFade() else GF.RefreshVisuals() end
            end,
        })

        local fadeSl = SSlider({
            name = "MSUF_GF_FadeAlphaSlider", parent = body, compact = true,
            anchor = layerDd, x = 16, y = -18,
            min = 0, max = 1, step = 0.05, width = 270, default = 0.4,
            get = function(k) return GF.Val(k, "rangeFadeAlpha") end,
            set = function(k, v)
                GF.GetConf(k).rangeFadeAlpha = v
                if GF.RefreshRangeFade then GF.RefreshRangeFade() else GF.RefreshVisuals() end
            end,
            formatText = function(v) return string.format("Out of Range Alpha: %.0f%%", v * 100) end,
        })

        SSlider({
            name = "MSUF_GF_OfflineAlphaSlider", parent = body, compact = true,
            anchor = fadeSl, x = 0, y = -32,
            min = 0, max = 1, step = 0.05, width = 270, default = 0.5,
            get = function(k) return GF.Val(k, "offlineAlpha") end,
            set = function(k, v)
                GF.GetConf(k).offlineAlpha = v
                if GF.RefreshRangeFade then GF.RefreshRangeFade() else GF.RefreshVisuals() end
            end,
            formatText = function(v) return string.format("Offline Alpha: %.0f%%", v * 100) end,
        })
    end

    ----------------------------------------------------------------
    -- Section 8: Indicators
    ----------------------------------------------------------------
    do
        local box, body = AddSection(580, "Indicators", false, "indicators")
        local refreshIndicatorControls

        local function IsMouseoverHighlightEnabled()
            local gen = _G.MSUF_DB and _G.MSUF_DB.general
            return not (gen and gen.highlightEnabled == false)
        end

        -- Redirect: aggro/dispel/target are controlled from the Bars menu
        local hlRedirect = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hlRedirect:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -8)
        hlRedirect:SetText(TR("Aggro / Dispel / Target Highlight"))
        hlRedirect:SetTextColor(1, 0.82, 0)

        local hlHint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hlHint:SetPoint("TOPLEFT", hlRedirect, "BOTTOMLEFT", 0, -6)
        hlHint:SetText(TR("Controlled from: |cffffd200Global Style > Bars|r > |cffffd200Outline & Highlight Border|r\nEnable/disable, colors, size, offset, priority — all in one place."))
        hlHint:SetTextColor(0.6, 0.65, 0.75)
        hlHint:SetWidth(400)
        hlHint:SetJustifyH("LEFT")

        -- Group Number sub-group
        local gnSep = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        gnSep:SetPoint("TOPLEFT", hlHint, "BOTTOMLEFT", 0, -16)
        gnSep:SetText(TR("Group Number"))
        gnSep:SetTextColor(1, 0.82, 0)

        local gnChk = SCheck({
            name = "MSUF_GF_ShowGroupNumberCheck", parent = body,
            anchor = gnSep, x = 0, y = -6,
            label = TR("Show Group Number"),
            get = function(k) return GF.Val(k, "showGroupNumber") end,
            set = function(k, v)
                GF.GetConf(k).showGroupNumber = v
                GF.RefreshVisuals()
                if refreshIndicatorControls then refreshIndicatorControls() end
            end,
        })

        local gnSizeSl = SSlider({
            name = "MSUF_GF_GroupNumberSizeSlider", parent = body, compact = true,
            anchor = gnChk, x = 0, y = -10,
            min = 6, max = 24, step = 1, width = 200, default = 10,
            get = function(k) return GF.Val(k, "groupNumberSize") end,
            set = function(k, v) GF.GetConf(k).groupNumberSize = v; GF.RefreshFonts() end,
            formatText = function(v) return string.format("Size: %d", v) end,
        })

        local gnAnchorDd = SDropdown({
            name = "MSUF_GF_GroupNumberAnchorDropdown", parent = body,
            anchor = gnSizeSl, anchorPoint = "BOTTOMLEFT", x = 0, y = -8, width = 160,
            items = {
                { key = "TOPLEFT",     label = "Top Left"     },
                { key = "TOPRIGHT",    label = "Top Right"    },
                { key = "BOTTOMLEFT",  label = "Bottom Left"  },
                { key = "BOTTOMRIGHT", label = "Bottom Right" },
                { key = "CENTER",      label = "Center"       },
            },
            get = function(k) return GF.Val(k, "groupNumberAnchor") end,
            set = function(k, v) GF.GetConf(k).groupNumberAnchor = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT) end,
        })

        local gnXSl = SSlider({
            name = "MSUF_GF_GroupNumberXSlider", parent = body, compact = true,
            anchor = gnAnchorDd, anchorPoint = "BOTTOMLEFT", x = 0, y = -8,
            min = -100, max = 100, step = 1, width = 200, default = -2,
            get = function(k) return GF.Val(k, "groupNumberX") end,
            set = function(k, v) GF.GetConf(k).groupNumberX = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT) end,
            formatText = function(v) return string.format("X Offset: %d", v) end,
        })

        local gnYSl = SSlider({
            name = "MSUF_GF_GroupNumberYSlider", parent = body, compact = true,
            anchor = gnXSl, x = 0, y = -28,
            min = -100, max = 100, step = 1, width = 200, default = 2,
            get = function(k) return GF.Val(k, "groupNumberY") end,
            set = function(k, v) GF.GetConf(k).groupNumberY = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT) end,
            formatText = function(v) return string.format("Y Offset: %d", v) end,
        })

        -- Hover Highlight sub-group
        local hoverSep = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hoverSep:SetPoint("TOPLEFT", gnYSl, "BOTTOMLEFT", 0, -16)
        hoverSep:SetText(TR("Hover Highlight"))
        hoverSep:SetTextColor(1, 0.82, 0)

        local hoverHint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hoverHint:SetPoint("TOPLEFT", hoverSep, "BOTTOMLEFT", 0, -4)
        hoverHint:SetText(TR("Enable + color: |cffffd200Global Style > Colors|r > Mouseover Highlight"))
        hoverHint:SetTextColor(0.5, 0.55, 0.65)

        local hoverSizeSl = SSlider({
            name = "MSUF_GF_HoverHighlightSizeSlider", parent = body, compact = true,
            anchor = hoverHint, anchorPoint = "BOTTOMLEFT", x = 0, y = -24,
            min = 1, max = 6, step = 1, width = 200, default = 1,
            get = function(k) return tonumber(GF.GetHighlightVal(k, "hlHoverSize")) or 1 end,
            set = function(k, v)
                GF.GetConf(k).hlHoverSize = v
                GF.GetConf(k).hlOverride = true
            end,
            formatText = function(v) return string.format("Border Thickness: %d", v) end,
        })

        -- Focus Highlight sub-group (anchored to hover SLIDER, not hint)
        local focusSep = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        focusSep:SetPoint("TOPLEFT", hoverSizeSl, "BOTTOMLEFT", 0, -16)
        focusSep:SetText(TR("Focus Highlight"))
        focusSep:SetTextColor(1, 0.82, 0)

        local focusChk = SCheck({
            name = "MSUF_GF_FocusHighlightEnableCheck", parent = body,
            anchor = focusSep, x = 0, y = -6,
            label = TR("Enable Focus Glow"),
            get = function(k) return GF.Val(k, "hlFocusEnabled") end,
            set = function(k, v)
                GF.GetConf(k).hlFocusEnabled = v
                GF.RefreshVisuals()
                if refreshIndicatorControls then refreshIndicatorControls() end
            end,
        })

        local focusHint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        focusHint:SetPoint("TOPLEFT", focusChk, "BOTTOMLEFT", 0, -4)
        focusHint:SetWidth(400)
        focusHint:SetJustifyH("LEFT")
        focusHint:SetText(TR("Shows a colored border around your Focus target. Priority: Dispel > Aggro > Target > Focus."))
        focusHint:SetTextColor(0.5, 0.55, 0.65)

        local focusSzSl = SSlider({
            name = "MSUF_GF_FocusHighlightSizeSlider", parent = body, compact = true,
            anchor = focusHint, anchorPoint = "BOTTOMLEFT", x = 0, y = -24,
            min = 1, max = 6, step = 1, width = 200, default = 2,
            get = function(k) return GF.Val(k, "hlFocusSize") end,
            set = function(k, v) GF.GetConf(k).hlFocusSize = v; GF.RefreshVisuals() end,
            formatText = function(v) return string.format("Border Thickness: %d", v) end,
        })

        local focusColorLabel, focusColorSwatch = MakeColorSwatch(body, focusSzSl, "BOTTOMLEFT", 0, -16,
            "Focus Glow Color",
            function()
                return V("hlFocusColorR") or 0.5, V("hlFocusColorG") or 0.5, V("hlFocusColorB") or 1.0
            end,
            function(r, g, b)
                local c = C()
                c.hlFocusColorR = r; c.hlFocusColorG = g; c.hlFocusColorB = b
                GF.RefreshVisuals()
            end)

        refreshIndicatorControls = function()
            local groupNumberEnabled = GF.Val(K(), "showGroupNumber") and true or false
            SetGFOptionControlsEnabled(groupNumberEnabled, {
                gnSizeSl, gnAnchorDd, gnXSl, gnYSl,
            })

            SetGFOptionControlEnabled(hoverSizeSl, IsMouseoverHighlightEnabled())

            local focusEnabled = GF.Val(K(), "hlFocusEnabled") and true or false
            SetGFOptionControlsEnabled(focusEnabled, {
                focusSzSl, focusColorSwatch,
            }, {
                focusHint, focusColorLabel,
            })
        end

        _G.MSUF_GF_RefreshIndicatorControlStates = refreshIndicatorControls
        if body.HookScript then body:HookScript("OnShow", refreshIndicatorControls) end
        _allRefreshFns[#_allRefreshFns + 1] = function()
            if body:IsShown() and refreshIndicatorControls then refreshIndicatorControls() end
        end
        refreshIndicatorControls()
    end

    ----------------------------------------------------------------
    -- Section 8b: Status Icons (Selector pattern: dropdown picks icon,
    -- one set of controls updates to show that icon's config)
    ----------------------------------------------------------------
    do
        local ICON_SPECS_UI = {
            { label = "Role Icon",   enKey = "roleIcon",      sizeKey = "roleIconSize",      anchorKey = "roleIconAnchor",    xKey = "roleIconX",    yKey = "roleIconY",    layerKey = "roleIconLayer",      defSize = 12 },
            { label = "Leader",      enKey = "leaderIcon",     sizeKey = "leaderIconSize",    anchorKey = "leaderIconAnchor",  xKey = "leaderIconX",  yKey = "leaderIconY",  layerKey = "leaderIconLayer",    defSize = 12 },
            { label = "Assist",      enKey = "assistIcon",     sizeKey = "assistIconSize",    anchorKey = "assistIconAnchor",  xKey = "assistIconX",  yKey = "assistIconY",  layerKey = "assistIconLayer",    defSize = 12 },
            { label = "Raid Marker", enKey = "raidMarker",     sizeKey = "raidMarkerSize",    anchorKey = "raidMarkerAnchor",  xKey = "raidMarkerX",  yKey = "raidMarkerY",  layerKey = "raidMarkerLayer",    defSize = 14 },
            { label = "Ready Check", enKey = "readyCheckIcon", sizeKey = "readyCheckSize",    anchorKey = "readyCheckAnchor",  xKey = "readyCheckX",  yKey = "readyCheckY",  layerKey = "readyCheckLayer",    defSize = 16 },
            { label = "Summon",      enKey = "summonIcon",     sizeKey = "summonIconSize",    anchorKey = "summonAnchor",      xKey = "summonX",      yKey = "summonY",      layerKey = "summonLayer",        defSize = 16 },
            { label = "Resurrect",   enKey = "resurrectIcon",  sizeKey = "resurrectIconSize", anchorKey = "resurrectAnchor",   xKey = "resurrectX",   yKey = "resurrectY",   layerKey = "resurrectLayer",     defSize = 16 },
            { label = "Phase",       enKey = "phaseIcon",      sizeKey = "phaseIconSize",     anchorKey = "phaseAnchor",       xKey = "phaseX",       yKey = "phaseY",       layerKey = "phaseLayer",         defSize = 14 },
            { label = "Dead Text",   enKey = "statusText",     sizeKey = "statusTextSize",    anchorKey = "statusTextAnchor",  xKey = "statusOffsetX", yKey = "statusOffsetY", layerKey = "statusTextLayer",    defSize = 14, isStatusText = true },
            { label = "Ghost Text",  enKey = "statusGhostText", sizeKey = "statusGhostTextSize", anchorKey = "statusGhostTextAnchor", xKey = "statusGhostOffsetX", yKey = "statusGhostOffsetY", layerKey = "statusGhostTextLayer", defSize = 14, isStatusText = true },
            { label = "AFK / DND Text", enKey = "statusAFKText", sizeKey = "statusAFKTextSize", anchorKey = "statusAFKTextAnchor", xKey = "statusAFKOffsetX", yKey = "statusAFKOffsetY", layerKey = "statusAFKTextLayer", defSize = 14, isStatusText = true },
        }
        local ANCHOR_ITEMS = {
            { key = "TOPLEFT",     label = "Top Left"     },
            { key = "TOPRIGHT",    label = "Top Right"    },
            { key = "BOTTOMLEFT",  label = "Bottom Left"  },
            { key = "BOTTOMRIGHT", label = "Bottom Right" },
            { key = "CENTER",      label = "Center"       },
            { key = "TOP",         label = "Top"          },
            { key = "BOTTOM",      label = "Bottom"       },
            { key = "LEFT",        label = "Left"         },
            { key = "RIGHT",       label = "Right"        },
        }

        local box, body = AddSection(440, "Status Icons", false, "sicons")

        -- Icon Style dropdown
        local styleDd = SDropdown({
            name = "MSUF_GF_SI_StyleDropdown", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = -4, y = -6, width = 240,
            items = GF.ICON_STYLE_ITEMS,
            get = function(k) return GF.Val(k, "iconStyle") or "BLIZZARD" end,
            set = function(k, v)
                GF.GetConf(k).iconStyle = v
                GF.RefreshVisuals()
            end,
        })

        local midnightChk = SCheck({
            name = "MSUF_GF_SI_MidnightCheck", parent = body,
            anchor = styleDd, x = 16, y = -6,
            label = TR("Use Midnight Style"),
            get = function(k) return GF.Val(k, "useMidnightIcons") end,
            set = function(k, v)
                GF.GetConf(k).useMidnightIcons = v
                GF.RefreshVisuals()
            end,
        })

        local _selectedIdx = 1

        -- Build selector dropdown items
        local selectorItems = {}
        for i = 1, #ICON_SPECS_UI do
            selectorItems[i] = { key = tostring(i), label = ICON_SPECS_UI[i].label }
        end

        local function SetStatusOptionEnabled(widget, enabled)
            if not widget then return end
            enabled = enabled and true or false
            if widget.SetEnabled then
                widget:SetEnabled(enabled)
            elseif enabled then
                if widget.EnableMouse then widget:EnableMouse(true) end
                if widget.Enable then widget:Enable() end
                if widget.SetAlpha then widget:SetAlpha(1) end
            else
                if widget.EnableMouse then widget:EnableMouse(false) end
                if widget.Disable then widget:Disable() end
                if widget.SetAlpha then widget:SetAlpha(0.45) end
            end
        end

        -- Forward-declare refresh
        local refreshIconControls

        -- Selector dropdown
        local selectorDd = SDropdown({
            name = "MSUF_GF_SI_SelectorDropdown", parent = body,
            anchor = midnightChk, x = -16, y = -8, width = 240,
            items = selectorItems,
            get = function() return tostring(_selectedIdx) end,
            set = function(k, v)
                _selectedIdx = tonumber(v) or 1
                if refreshIconControls then refreshIconControls() end
                GF.RefreshVisuals()
                local spec = ICON_SPECS_UI[_selectedIdx]
                if spec and GF._PreviewSelectStatusIcon then
                    GF._PreviewSelectStatusIcon(spec.enKey)
                end
            end,
        })

        local statusPreviewMode = "current"
        local statusPreviewModeBtns = {}
        local function RefreshStatusPreviewMode()
            local mode = (GF.GetStatusPreviewMode and GF.GetStatusPreviewMode()) or statusPreviewMode
            mode = (mode == "all") and "all" or "current"
            statusPreviewMode = mode
            for key, btn in pairs(statusPreviewModeBtns) do
                local active = (key == mode)
                if active then
                    btn:SetBackdropColor(0.12, 0.18, 0.30, 0.95)
                    btn:SetBackdropBorderColor(0.30, 0.55, 0.90, 1)
                    btn._fs:SetTextColor(0.85, 0.92, 1.00, 1)
                elseif btn._hover then
                    btn:SetBackdropColor(0.11, 0.13, 0.18, 0.95)
                    btn:SetBackdropBorderColor(0.25, 0.35, 0.50, 0.9)
                    btn._fs:SetTextColor(0.78, 0.82, 0.90, 1)
                else
                    btn:SetBackdropColor(0.04, 0.05, 0.08, 0.85)
                    btn:SetBackdropBorderColor(0.16, 0.20, 0.28, 0.75)
                    btn._fs:SetTextColor(0.55, 0.60, 0.70, 1)
                end
            end
        end
        local function SetStatusPreviewMode(mode)
            mode = (mode == "all") and "all" or "current"
            statusPreviewMode = mode
            if GF.SetStatusPreviewMode then GF.SetStatusPreviewMode(mode) end
            RefreshStatusPreviewMode()
        end

        local previewLbl = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        previewLbl:SetPoint("TOPLEFT", body, "TOPLEFT", 360, -76)
        previewLbl:SetText(TR("Status Preview"))

        local function MakeStatusPreviewModeButton(mode, label, width)
            local btn = CreateFrame("Button", nil, body, "BackdropTemplate")
            btn:SetSize(width or 84, 20)
            btn:SetBackdrop({
                bgFile = TEX_W8,
                edgeFile = TEX_W8,
                edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("CENTER")
            fs:SetText(TR(label))
            btn._fs = fs
            btn:SetScript("OnClick", function()
                SetStatusPreviewMode(mode)
            end)
            btn:SetScript("OnEnter", function(self)
                self._hover = true
                RefreshStatusPreviewMode()
                if not GameTooltip then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(TR("Status Preview"), 1, 1, 1)
                if mode == "all" then
                    GameTooltip:AddLine(TR("Shows every status indicator while this section is open."), 0.75, 0.80, 0.90, true)
                else
                    GameTooltip:AddLine(TR("Shows only the selected status indicator while this section is open."), 0.75, 0.80, 0.90, true)
                end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                self._hover = false
                RefreshStatusPreviewMode()
                if GameTooltip then GameTooltip:Hide() end
            end)
            statusPreviewModeBtns[mode] = btn
            return btn
        end

        local currentPreviewBtn = MakeStatusPreviewModeButton("current", "Current", 82)
        currentPreviewBtn:SetPoint("TOPLEFT", previewLbl, "BOTTOMLEFT", 0, -6)
        local allPreviewBtn = MakeStatusPreviewModeButton("all", "Show All", 88)
        allPreviewBtn:SetPoint("LEFT", currentPreviewBtn, "RIGHT", 2, 0)
        RefreshStatusPreviewMode()

        -- Enable checkbox
        local enChk = SCheck({
            name = "MSUF_GF_SI_EnableCheck", parent = body,
            anchor = selectorDd, x = 16, y = -8,
            label = TR("Enabled"),
            get = function(k) local s = ICON_SPECS_UI[_selectedIdx]; return s and GF.Val(k, s.enKey) end,
            set = function(k, v)
                local s = ICON_SPECS_UI[_selectedIdx]
                if s then
                    GF.GetConf(k)[s.enKey] = v
                    GF.RefreshVisuals()
                    if refreshIconControls then refreshIconControls() end
                end
            end,
        })

        -- Size slider
        local sizeSl = SSlider({
            name = "MSUF_GF_SI_SizeSlider", parent = body, compact = true,
            anchor = enChk, x = 0, y = -10,
            min = 6, max = 40, step = 1, width = 270, default = 12,
            get = function(k) local s = ICON_SPECS_UI[_selectedIdx]; return s and GF.Val(k, s.sizeKey) or 12 end,
            set = function(k, v)
                local s = ICON_SPECS_UI[_selectedIdx]
                if s then GF.GetConf(k)[s.sizeKey] = v; GF.RefreshVisuals() end
            end,
            formatText = function(v) return string.format("Size: %d", v) end,
        })

        -- Anchor dropdown
        local anchorDd = SDropdown({
            name = "MSUF_GF_SI_AnchorDropdown", parent = body,
            anchor = sizeSl, x = -16, y = -10, width = 200,
            items = ANCHOR_ITEMS,
            get = function(k) local s = ICON_SPECS_UI[_selectedIdx]; return s and GF.Val(k, s.anchorKey) or "CENTER" end,
            set = function(k, v)
                local s = ICON_SPECS_UI[_selectedIdx]
                if s then GF.GetConf(k)[s.anchorKey] = v; GF.RefreshVisuals() end
            end,
        })

        -- X Offset
        local xSl = SSlider({
            name = "MSUF_GF_SI_XSlider", parent = body, compact = true,
            anchor = anchorDd, x = 16, y = -10,
            min = -100, max = 100, step = 1, width = 270, default = 0,
            get = function(k) local s = ICON_SPECS_UI[_selectedIdx]; return s and GF.Val(k, s.xKey) or 0 end,
            set = function(k, v)
                local s = ICON_SPECS_UI[_selectedIdx]
                if s then GF.GetConf(k)[s.xKey] = v; GF.RefreshVisuals() end
            end,
            formatText = function(v) return string.format("X Offset: %d", v) end,
        })

        -- Y Offset
        local ySl = SSlider({
            name = "MSUF_GF_SI_YSlider", parent = body, compact = true,
            anchor = xSl, x = 0, y = -32,
            min = -100, max = 100, step = 1, width = 270, default = 0,
            get = function(k) local s = ICON_SPECS_UI[_selectedIdx]; return s and GF.Val(k, s.yKey) or 0 end,
            set = function(k, v)
                local s = ICON_SPECS_UI[_selectedIdx]
                if s then GF.GetConf(k)[s.yKey] = v; GF.RefreshVisuals() end
            end,
            formatText = function(v) return string.format("Y Offset: %d", v) end,
        })

        -- Layer (draw order, higher = on top)
        local layerSl = SSlider({
            name = "MSUF_GF_SI_LayerSlider", parent = body, compact = true,
            anchor = ySl, x = 0, y = -32,
            min = 1, max = 15, step = 1, width = 270, default = 1,
            get = function(k) local s = ICON_SPECS_UI[_selectedIdx]; return s and GF.Val(k, s.layerKey) or 1 end,
            set = function(k, v)
                local s = ICON_SPECS_UI[_selectedIdx]
                if s then GF.GetConf(k)[s.layerKey] = v; GF.RefreshVisuals() end
            end,
            formatText = function(v) return string.format("Layer: %d (higher = on top)", v) end,
        })

        local resetBtn = CreateFrame("Button", "MSUF_GF_SI_ResetButton", body, "UIPanelButtonTemplate")
        resetBtn:SetSize(62, 22)
        resetBtn:SetText(TR("Reset"))
        resetBtn:SetPoint("LEFT", layerSl, "RIGHT", 84, 0)
        resetBtn:SetScript("OnClick", function()
            local s = ICON_SPECS_UI[_selectedIdx]
            local kind = K()
            local conf = GF.GetConf(kind)
            if not (s and conf) then return end

            for _, key in ipairs({ s.sizeKey, s.anchorKey, s.xKey, s.yKey, s.layerKey }) do
                if key then
                    local def = GF.GetDefault and GF.GetDefault(kind, key)
                    conf[key] = def
                end
            end

            GF.RefreshVisuals()
            if refreshIconControls then refreshIconControls() end
            if GF._PreviewSelectStatusIcon then GF._PreviewSelectStatusIcon(s.enKey) end
        end)
        resetBtn:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(TR("Resets current indicator"), 1, 1, 1)
            GameTooltip:AddLine(TR("Resets X/Y, Anchor, Size and Layer back to defaults."), 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        resetBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

        local function SetStatusConfigEnabled(enabled)
            SetStatusOptionEnabled(sizeSl, enabled)
            SetStatusOptionEnabled(anchorDd, enabled)
            SetStatusOptionEnabled(xSl, enabled)
            SetStatusOptionEnabled(ySl, enabled)
            SetStatusOptionEnabled(layerSl, enabled)
            SetStatusOptionEnabled(resetBtn, enabled)
        end

        -- Refresh all controls when selector changes
        refreshIconControls = function()
            if enChk and enChk.Refresh then enChk:Refresh() end
            if sizeSl and sizeSl.Refresh then sizeSl:Refresh() end
            if anchorDd and anchorDd.Refresh then anchorDd:Refresh() end
            if xSl and xSl.Refresh then xSl:Refresh() end
            if ySl and ySl.Refresh then ySl:Refresh() end
            if layerSl and layerSl.Refresh then layerSl:Refresh() end
            local s = ICON_SPECS_UI[_selectedIdx]
            SetStatusConfigEnabled(s and GF.Val(K(), s.enKey) and true or false)
        end

        -- Also refresh on scope switch
        _allRefreshFns[#_allRefreshFns + 1] = function()
            if refreshIconControls then refreshIconControls() end
            if midnightChk and midnightChk.Refresh then midnightChk:Refresh() end
            if styleDd and styleDd.Refresh then styleDd:Refresh() end
            if RefreshStatusPreviewMode then RefreshStatusPreviewMode() end
        end
        refreshIconControls()
    end

    ----------------------------------------------------------------
    -- Sections 9-10: Buffs, Debuffs, Externals, Private Auras, Spell Indicators
    -- (delegated to MSUF_Options_GF_Auras.lua)
    ----------------------------------------------------------------
    if GF.BuildAuraOptionsSections then
        GF.BuildAuraOptionsSections(AddSection, SCheck, SSlider, SDropdown, K, TrackRefresh, MakeColorSwatch, OpenColorPicker, _allRefreshFns)
    end

    ----------------------------------------------------------------
    -- Section: Heal Prediction
    ----------------------------------------------------------------
    do
        local box, body = AddSection(120, "Heal Prediction", false, "healpred")

        local healPredChk = SCheck({
            name = "MSUF_GF_HealPredEnableCheck", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -6,
            label = TR("Heal Prediction Overlay"),
            get = function(k)
                return (GF.IsHealPredictionEnabled and GF.IsHealPredictionEnabled(k, GF.GetConf(k))) or false
            end,
            set = function(k, v)
                GF.GetConf(k).healPredEnabled = v
                if GF.frames then
                    for f in pairs(GF.frames) do
                        if GF.BuildFrameCache then GF.BuildFrameCache(f) end
                        if f.unit then GF.RegisterUnitEvents(f, f.unit) end
                    end
                end
                GF.RefreshVisuals()
                if _G.MSUF_GF_RefreshOverlays then _G.MSUF_GF_RefreshOverlays() end
            end,
        })

        local hpHint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hpHint:SetPoint("TOPLEFT", healPredChk, "BOTTOMLEFT", 0, -6)
        hpHint:SetWidth(600)
        hpHint:SetJustifyH("LEFT")
        hpHint:SetText(TR("Shows incoming heals as a lighter overlay on each member's health bar.\nAbsorb overlays and their colors/textures are shared with |cffffd200Global Style > Bars|r and |cffffd200Colors|r."))
        hpHint:SetTextColor(0.55, 0.60, 0.70)
    end

    ----------------------------------------------------------------
    -- Section: Dispel Overlay
    ----------------------------------------------------------------
    do
        local box, body = AddSection(330, "Dispel Overlay", false, "dispel")

        local doChk = SCheck({
            name = "MSUF_GF_DispelOverlayCheck", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -6,
            label = TR("Enable Dispel Overlay"),
            get = function(k) return GF.Val(k, "dispelOverlayEnabled") end,
            set = function(k, v)
                GF.GetConf(k).dispelOverlayEnabled = v
                GF.RefreshVisuals()
                local fn = _G.MSUF_GF_RefreshDispelOverlay
                if type(fn) == "function" then fn() end
            end,
        })

        local doHint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        doHint:SetPoint("TOPLEFT", doChk, "BOTTOMLEFT", 0, -4)
        doHint:SetWidth(550)
        doHint:SetJustifyH("LEFT")
        doHint:SetText(TR("Tints the health bar when a dispellable debuff is active. Works alongside the highlight border.\nColors are shared with |cffffd200Global Style > Colors|r > |cffffd200Dispel|r."))
        doHint:SetTextColor(0.55, 0.60, 0.70)

        local doStyleDd = SDropdown({
            name = "MSUF_GF_DispelOverlayStyleDropdown", parent = body,
            anchor = doHint, anchorPoint = "BOTTOMLEFT", x = -4, y = -10, width = 200,
            items = {
                { key = "FULL",   label = TR("Full Frame") },
                { key = "BOTTOM", label = TR("Bottom Edge") },
                { key = "TOP",    label = TR("Top Edge") },
                { key = "LEFT",   label = TR("Left Edge") },
                { key = "RIGHT",  label = TR("Right Edge") },
            },
            get = function(k) return GF.Val(k, "dispelOverlayStyle") end,
            set = function(k, v)
                GF.GetConf(k).dispelOverlayStyle = v
                GF.RefreshVisuals()
                local fn = _G.MSUF_GF_RefreshDispelOverlay
                if type(fn) == "function" then fn() end
            end,
        })

        local doOnHPChk = SCheck({
            name = "MSUF_GF_DispelOverlayOnHPCheck", parent = body,
            anchor = doStyleDd, x = 0, y = -8,
            label = TR("Show On Current Health Only"),
            get = function(k) return GF.Val(k, "dispelOverlayOnHealth") end,
            set = function(k, v)
                GF.GetConf(k).dispelOverlayOnHealth = v
                GF.RefreshVisuals()
                local fn = _G.MSUF_GF_RefreshDispelOverlay
                if type(fn) == "function" then fn() end
            end,
        })

        SSlider({
            name = "MSUF_GF_DispelOverlayAlphaSlider", parent = body, compact = true,
            anchor = doOnHPChk, x = 0, y = -12,
            min = 0.05, max = 1, step = 0.05, width = 270, default = 0.35,
            get = function(k) return GF.Val(k, "dispelOverlayAlpha") end,
            set = function(k, v)
                GF.GetConf(k).dispelOverlayAlpha = v
                local fn = _G.MSUF_GF_RefreshDispelOverlay
                if type(fn) == "function" then fn() end
            end,
            formatText = function(v) return string.format("Overlay Opacity: %.0f%%", v * 100) end,
        })
    end

    ----------------------------------------------------------------
    -- Section: Debuff Stripe
    ----------------------------------------------------------------
    do
        local box, body = AddSection(320, "Debuff Stripe", false, "dstripe")
        local refreshDebuffStripeControls

        local function IsNativeDebuffsActive()
            local conf = GF.GetConf(K())
            return GF.IsBlizzardAuraTypeEnabled
                and GF.IsBlizzardAuraTypeEnabled(conf, "debuffs") == true
        end

        local dsChk = SCheck({
            name = "MSUF_GF_DebuffStripeCheck", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -6,
            label = TR("Enable Debuff Stripe"),
            get = function(k) return GF.Val(k, "debuffStripeEnabled") end,
            set = function(k, v)
                GF.GetConf(k).debuffStripeEnabled = v
                GF.RefreshVisuals()
                local fn = _G.MSUF_GF_RefreshDebuffStripe
                if type(fn) == "function" then fn() end
                if refreshDebuffStripeControls then refreshDebuffStripeControls() end
            end,
        })

        local dsHint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        dsHint:SetPoint("TOPLEFT", dsChk, "BOTTOMLEFT", 0, -4)
        dsHint:SetWidth(550)
        dsHint:SetJustifyH("LEFT")
        dsHint:SetText(TR("Shows a thin colored stripe when a debuff matching your Debuffs filter/list is active — including non-dispellable ones when allowed there.\nWorks independently from the Dispel Overlay."))
        dsHint:SetTextColor(0.55, 0.60, 0.70)
        local dsHintText = dsHint:GetText()
        local dsNativeHintText = TR("Disabled while Group Frames > Buffs & Debuffs > Blizzard Renderer owns Debuffs. The stripe needs a custom debuff scan, so it is suppressed in Blizzard mode for performance.")

        local dsEdgeDd = SDropdown({
            name = "MSUF_GF_DebuffStripeEdgeDropdown", parent = body,
            anchor = dsHint, anchorPoint = "BOTTOMLEFT", x = -4, y = -10, width = 200,
            items = {
                { key = "BOTTOM", label = TR("Bottom Edge") },
                { key = "TOP",    label = TR("Top Edge") },
            },
            get = function(k) return GF.Val(k, "debuffStripeEdge") end,
            set = function(k, v)
                GF.GetConf(k).debuffStripeEdge = v
                GF.RefreshVisuals()
                local fn = _G.MSUF_GF_RefreshDebuffStripe
                if type(fn) == "function" then fn() end
            end,
        })

        -- y=-26 (was -8): compact-slider's value label sits ~16px ABOVE the
        -- slider track via OptionsSliderTemplate, so anything <17 makes the
        -- next slider's label clip into the previous control.
        local dsHeightSl = SSlider({
            name = "MSUF_GF_DebuffStripeHeightSlider", parent = body, compact = true,
            anchor = dsEdgeDd, x = 0, y = -26,
            min = 1, max = 8, step = 1, width = 270, default = 3,
            get = function(k) return GF.Val(k, "debuffStripeHeight") end,
            set = function(k, v)
                GF.GetConf(k).debuffStripeHeight = v
                local fn = _G.MSUF_GF_RefreshDebuffStripe
                if type(fn) == "function" then fn() end
            end,
            formatText = function(v) return string.format("Height: %dpx", v) end,
        })

        local dsAlphaSl = SSlider({
            name = "MSUF_GF_DebuffStripeAlphaSlider", parent = body, compact = true,
            anchor = dsHeightSl, x = 0, y = -26,
            min = 0.10, max = 1, step = 0.05, width = 270, default = 0.60,
            get = function(k) return GF.Val(k, "debuffStripeAlpha") end,
            set = function(k, v)
                GF.GetConf(k).debuffStripeAlpha = v
                local fn = _G.MSUF_GF_RefreshDebuffStripe
                if type(fn) == "function" then fn() end
            end,
            formatText = function(v) return string.format("Opacity: %.0f%%", v * 100) end,
        })

        refreshDebuffStripeControls = function()
            local nativeDebuffs = IsNativeDebuffsActive()
            local enabled = GF.Val(K(), "debuffStripeEnabled") == true and not nativeDebuffs
            dsHint:SetText(nativeDebuffs and dsNativeHintText or dsHintText)
            SetGFOptionControlsEnabled(not nativeDebuffs, { dsChk }, { dsHint })
            SetGFOptionControlsEnabled(enabled, { dsEdgeDd, dsHeightSl, dsAlphaSl })
        end
        _G.MSUF_GF_RefreshDebuffStripeControlStates = refreshDebuffStripeControls
        if body.HookScript then body:HookScript("OnShow", refreshDebuffStripeControls) end
        _allRefreshFns[#_allRefreshFns + 1] = function()
            if body:IsShown() and refreshDebuffStripeControls then refreshDebuffStripeControls() end
        end
        refreshDebuffStripeControls()
    end

    ----------------------------------------------------------------
    -- Section 12: Tooltip
    ----------------------------------------------------------------
    do
        local box, body = AddSection(140, "Tooltip", false, "tooltip")

        local _modifierDd -- forward ref for show/hide toggle

        local modeDd = SDropdown({
            name = "MSUF_GF_TooltipModeDropdown", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = -4, y = -6, width = 200,
            items = {
                { key = "ALWAYS",   label = "Always"        },
                { key = "OOC",      label = "Out of Combat" },
                { key = "MODIFIER", label = "Modifier Key"  },
                { key = "NEVER",    label = "Never"         },
            },
            get = function(k) return GF.Val(k, "tooltipMode") end,
            set = function(k, v)
                GF.GetConf(k).tooltipMode = v
                if _modifierDd then
                    if v == "MODIFIER" then _modifierDd:Show() else _modifierDd:Hide() end
                end
            end,
        })

        _modifierDd = SDropdown({
            name = "MSUF_GF_TooltipModifierDropdown", parent = body,
            anchor = modeDd, x = 0, y = -6, width = 160,
            items = {
                { key = "ALT",   label = "Alt"   },
                { key = "CTRL",  label = "Ctrl"  },
                { key = "SHIFT", label = "Shift" },
            },
            get = function(k) return GF.Val(k, "tooltipModifier") end,
            set = function(k, v) GF.GetConf(k).tooltipModifier = v end,
        })

        -- Sync modifier dropdown visibility on scope switch
        _allRefreshFns[#_allRefreshFns + 1] = function()
            if _modifierDd then
                local mode = GF.Val(K(), "tooltipMode")
                if mode == "MODIFIER" then _modifierDd:Show() else _modifierDd:Hide() end
            end
        end
    end

    ----------------------------------------------------------------
    -- Reorder sections into logical groups (tabs replace dividers)
    ----------------------------------------------------------------
    do
        -- Desired order within each tab
        local ORDER = {
            { key = "frame",      keys = { "general", "layout", "sorting", "scaling", "border", "anchor", "tooltip" } },
            { key = "health",     keys = { "hcolor", "bars", "power", "text", "healpred", "dispel", "dstripe", "range" } },
            { key = "auras",      keys = { "blizzrenderer", "buffs", "debuffs", "ext", "textcolor", "priv", "masque", "autil" } },
            { key = "indicators", keys = { "indicators", "sicons", "si", "ci" } },
        }

        local byKey = {}
        for i = 1, #sections do
            local k = sections[i]._msufSecKey
            if k then byKey[k] = sections[i] end
        end

        local ordered = {}
        local placed = {}
        for _, group in ipairs(ORDER) do
            for _, k in ipairs(group.keys) do
                if byKey[k] then
                    ordered[#ordered + 1] = byKey[k]
                    placed[byKey[k]] = true
                end
            end
        end
        -- Append any sections not in ORDER (safety net)
        for i = 1, #sections do
            if not placed[sections[i]] then
                ordered[#ordered + 1] = sections[i]
            end
        end
        for i = 1, math.max(#sections, #ordered) do
            sections[i] = ordered[i]
        end
    end
    local SECTION_GAP = 6

    RefreshScrollLayout = function()
        local y = -66  -- below scope bar + context hint

        -- Preview toggle
        _previewToggle:ClearAllPoints()
        _previewToggle:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, y)
        y = y - 18 - 2

        -- Preview box (collapsible)
        if _previewBox then
            if _previewCollapsed then
                _previewBox:Hide()
            else
                _previewBox:ClearAllPoints()
                _previewBox:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, y)
                _previewBox:SetWidth(SECTION_W)
                _previewBox:Show()
                if GF.ResizePreviewContainer then GF.ResizePreviewContainer() end
                y = y - (_previewBox:GetHeight() or 200) - SECTION_GAP
            end
        end

        -- Sections (only visible ones — tab-filtered)
        for i = 1, #sections do
            local box = sections[i]
            if box and box:IsShown() then
                box:ClearAllPoints()
                box:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, y)
                y = y - box:GetHeight() - SECTION_GAP
            end
        end
        scrollChild:SetHeight(math.abs(y) + 40)
    end

    -- Initialize: activate default tab + layout
    SwitchTab(_activeTab)
    _G.MSUF_GF_SwitchTab = SwitchTab
    _G.MSUF_GF_OpenSectionByKey = function(sectionKey)
        OpenSectionByKey(sectionKey)
        if type(RefreshScrollLayout) == "function" then RefreshScrollLayout() end
    end
    RefreshScrollLayout()

    ----------------------------------------------------------------
    -- Preview management
    ----------------------------------------------------------------
    _panel:SetScript("OnShow", function()
        SyncActiveScopeForEM2(_activeKind)
        ShowPreviewIfNeeded(_activeKind)
        RefreshAllWidgets()
        if GF.RefreshPreviewBox then GF.RefreshPreviewBox() end
        if GF.ResizePreviewContainer then GF.ResizePreviewContainer() end
        RefreshScrollLayout()
    end)
    _panel:SetScript("OnHide", function()
        HideAllPreviews()
    end)

    ----------------------------------------------------------------
    -- Search registration
    ----------------------------------------------------------------
    if _G.MSUF_Search_RegisterRoots then
        _G.MSUF_Search_RegisterRoots(
            { "groupframes", "gf_layout", "gf_bars", "gf_auras", "gf_indicators",
              "party", "raid", "group", "heal prediction", "buffs", "debuffs" },
            scrollChild, "Group Frames"
        )
    end

    return _panel
end
