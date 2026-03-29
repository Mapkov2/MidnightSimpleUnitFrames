-- MSUF_Options_GF.lua — Group Frames Options Panel (Phase 6)
-- Accordion UX, Party/Raid scope tabs, ns.UI.* toolkit, preview management.
-- Midnight 12.0 secret-safe, zero combat overhead.
local _, ns = ...
ns = ns or (_G and _G.MSUF_NS) or {}
if _G then _G.MSUF_NS = ns end

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

    _panel = CreateFrame("Frame", "MSUF_GFOptionsPanel", UIParent)
    _panel:SetSize(640, 800)
    _panel:Hide()

    local _activeKind = "party"
    local _allRefreshFns = {}

    local function K() return _activeKind end
    local function C() return GF.GetConf(K()) end
    local function V(key) return GF.Val(K(), key) end
    local function W(key, val, refreshFn)
        local conf = GF.GetConf(K())
        conf[key] = val
        if type(refreshFn) == "function" then refreshFn()
        else GF.RefreshVisuals() end
    end

    local function RefreshAllWidgets()
        for i = 1, #_allRefreshFns do
            local fn = _allRefreshFns[i]
            if type(fn) == "function" then fn() end
        end
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
            box._msufCollapsed = not box._msufCollapsed
            ApplyState()
        end)
        do
            local hl = hdr:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.03)
        end

        box._msufApplyCollapseState = ApplyState
        return box, body
    end

    ----------------------------------------------------------------
    -- Scope tabs (Party / Raid)
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
        if kind == "raid" then
            return not (IsInRaid and IsInRaid())
        end
        -- party: preview only when solo (no real party members)
        return not (IsInGroup and IsInGroup())
    end

    local function ShowPreviewIfNeeded(kind)
        if NeedsPreview(kind) then
            -- Hide SecureGroupHeaders to prevent doubling with preview frames
            if not InCombatLockdown() and GF.headers then
                if GF.headers.party then GF.headers.party:Hide() end
                if GF.headers.raid  then GF.headers.raid:Hide()  end
            end
            GF.ShowPreview(kind, kind == "raid" and 10 or 4)
        end
    end

    local function HideAllPreviews()
        GF.HidePreview("party")
        GF.HidePreview("raid")
        -- Restore headers
        if not InCombatLockdown() and GF.UpdateGroupVisibility then
            GF.UpdateGroupVisibility()
        end
    end

    local function SwitchScope(kind)
        _activeKind = kind
        RefreshScopeBtns()
        RefreshAllWidgets()
        HideAllPreviews()
        ShowPreviewIfNeeded(kind)
    end

    do
        local prevBtn
        for _, info in ipairs({ { "party", "Party" }, { "raid", "Raid" } }) do
            local kind, label = info[1], info[2]
            local btn = CreateFrame("Button", nil, scopeBar, "BackdropTemplate")
            btn:SetSize(56, 20)
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
    RefreshScopeBtns()

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
        _allRefreshFns[#_allRefreshFns + 1] = function()
            if cb:IsShown() and spec.get then cb:SetChecked(spec.get() and true or false) end
        end
        return cb
    end

    local function SSlider(spec)
        local origGet = spec.get
        local origSet = spec.set
        spec.get = function() return origGet(K()) end
        spec.set = function(v) origSet(K(), v) end
        local sl = UI.Slider(spec)
        if sl then
            _allRefreshFns[#_allRefreshFns + 1] = function()
                if sl:IsShown() and spec.get then
                    local v = spec.get()
                    if type(v) == "number" and sl.SetValueClean then
                        sl:SetValueClean(v)
                    end
                end
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

    ----------------------------------------------------------------
    -- All sections stacked below scopeBar
    ----------------------------------------------------------------
    local sections = {}
    local function AddSection(expandedH, title, defaultOpen)
        local box, body = MakeCollapsibleSection(scrollChild, expandedH, title, defaultOpen)
        sections[#sections + 1] = box
        return box, body
    end

    ----------------------------------------------------------------
    -- Section 1: General (default open)
    ----------------------------------------------------------------
    do
        local box, body = AddSection(600, "General", true)

        local enableChk = SCheck({
            name = "MSUF_GF_EnableCheck", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -6,
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

        local widthSl = SSlider({
            name = "MSUF_GF_WidthSlider", parent = body, compact = true,
            anchor = showSoloChk, x = 0, y = -18,
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
            local isRaid = (K() == "raid")
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
                StaticPopup_Show("MSUF_GF_GROWTH_RELOAD")
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

        local reverseFillChk = SCheck({
            name = "MSUF_GF_ReverseFillCheck", parent = body,
            anchor = maxColSl, x = 0, y = -14,
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

        SCheck({
            name = "MSUF_GF_HideInClientSceneCheck", parent = body,
            anchor = smoothChk, x = 0, y = -4,
            label = TR("Hide in Barber Shop / Dressing Room"),
            get = function(k) return GF.Val(k, "hideInClientScene") ~= false end,
            set = function(k, v) GF.GetConf(k).hideInClientScene = v end,
        })
    end

    ----------------------------------------------------------------
    -- Section 2: Health Colors (info only — controlled by global Colors menu)
    ----------------------------------------------------------------
    do
        local box, body = AddSection(60, "Health Colors", false)

        local hint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("TOPLEFT", body, "TOPLEFT", 14, -8)
        hint:SetWidth(640)
        hint:SetJustifyH("LEFT")
        hint:SetText(TR("Health bar colors follow the global |cffffd200Colors|r menu (Dark Mode, Class Colors, Unified)."))
        hint:SetTextColor(0.55, 0.60, 0.70)
    end

    ----------------------------------------------------------------
    -- Section 3: Power Bar
    ----------------------------------------------------------------
    do
        local box, body = AddSection(280, "Power Bar", false)

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
    -- Section 4: Text (Status Offsets)
    ----------------------------------------------------------------
    do
        local box, body = AddSection(200, "Text", false)

        -- Redirect hint
        local hintFS = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hintFS:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -6)
        hintFS:SetText(TR("Name, HP text, power text and font sizes\nare in the Edit Mode popup.\nFont, outline, name color and max chars\nare in the Fonts menu."))
        hintFS:SetTextColor(0.55, 0.75, 1.0)
        hintFS:SetJustifyH("LEFT")
        hintFS:SetWordWrap(true)
        hintFS:SetWidth(600)

        -- Status Text Offsets
        local tOffSep = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tOffSep:SetPoint("TOPLEFT", hintFS, "BOTTOMLEFT", 0, -12)
        tOffSep:SetText(TR("Status Text Offsets"))
        tOffSep:SetTextColor(1, 0.82, 0)

        local statXSl = SSlider({
            name = "MSUF_GF_StatusOffsetXSlider", parent = body, compact = true,
            anchor = tOffSep, x = 0, y = -8,
            min = -100, max = 100, step = 1, width = 270, default = 0,
            get = function(k) return GF.Val(k, "statusOffsetX") end,
            set = function(k, v) GF.GetConf(k).statusOffsetX = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT) end,
            formatText = function(v) return string.format("Status Text X: %d", v) end,
        })
        SSlider({
            name = "MSUF_GF_StatusOffsetYSlider", parent = body, compact = true,
            anchor = statXSl, x = 0, y = -32,
            min = -100, max = 100, step = 1, width = 270, default = 0,
            get = function(k) return GF.Val(k, "statusOffsetY") end,
            set = function(k, v) GF.GetConf(k).statusOffsetY = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT) end,
            formatText = function(v) return string.format("Status Text Y: %d", v) end,
        })

    end

    ----------------------------------------------------------------
    -- Section 5: Bars
    ----------------------------------------------------------------
    do
        local box, body = AddSection(170, "Bars", false)

        local fgLbl = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fgLbl:SetPoint("TOPLEFT", body, "TOPLEFT", 14, -10)
        fgLbl:SetText(TR("Foreground Texture"))

        local fgDd = SDropdown({
            name = "MSUF_GF_BarTextureDropdown", parent = body,
            anchor = fgLbl, anchorPoint = "BOTTOMLEFT", x = -16, y = -4, width = 240,
            items = function()
                local items = { { key = "", label = "(Global Default)" } }
                local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
                if LSM then
                    local list = LSM:List("statusbar")
                    for i = 1, #list do items[#items + 1] = { key = list[i], label = list[i] } end
                end
                return items
            end,
            get = function(k) return GF.Val(k, "barTexture") or "" end,
            set = function(k, v) GF.GetConf(k).barTexture = v; GF.RefreshTextures() end,
        })

        local bgLbl = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bgLbl:SetPoint("TOPLEFT", fgDd, "BOTTOMLEFT", 16, -10)
        bgLbl:SetText(TR("Background Texture"))

        SDropdown({
            name = "MSUF_GF_BarBackgroundTextureDropdown", parent = body,
            anchor = bgLbl, anchorPoint = "BOTTOMLEFT", x = -16, y = -4, width = 240,
            items = function()
                local items = { { key = "", label = "(Global Default)" } }
                local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
                if LSM then
                    local list = LSM:List("statusbar")
                    for i = 1, #list do items[#items + 1] = { key = list[i], label = list[i] } end
                end
                return items
            end,
            get = function(k) return GF.Val(k, "barBgTexture") or "" end,
            set = function(k, v) GF.GetConf(k).barBgTexture = v; GF.RefreshTextures() end,
        })
    end

    ----------------------------------------------------------------
    -- Section 6: Border & Background
    ----------------------------------------------------------------
    do
        local box, body = AddSection(280, "Border & Background", false)

        local enChk = SCheck({
            name = "MSUF_GF_BorderEnableCheck", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -6,
            label = TR("Enable Border"),
            get = function(k) return GF.Val(k, "borderEnabled") end,
            set = function(k, v) GF.GetConf(k).borderEnabled = v; GF.MarkAllDirty(GF.DIRTY_BORDER) end,
        })

        local sizeSl = SSlider({
            name = "MSUF_GF_BorderSizeSlider", parent = body, compact = true,
            anchor = enChk, x = 0, y = -14,
            min = 1, max = 4, step = 1, width = 270, default = 1,
            get = function(k) return GF.Val(k, "borderSize") end,
            set = function(k, v) GF.GetConf(k).borderSize = v; GF.MarkAllDirty(GF.DIRTY_BORDER) end,
            formatText = function(v) return string.format("Border Size: %d", v) end,
        })

        local borderLbl = MakeColorSwatch(body, sizeSl, "BOTTOMLEFT", 0, -16,
            "Border Color",
            function() return V("borderR"), V("borderG"), V("borderB") end,
            function(r, g, b)
                local c = C(); c.borderR = r; c.borderG = g; c.borderB = b
                GF.MarkAllDirty(GF.DIRTY_BORDER)
            end)

        local bgLbl, bgSwatch = MakeColorSwatch(body, borderLbl, "BOTTOMLEFT", 0, -16,
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
    end

    ----------------------------------------------------------------
    -- Section 7: Range Fade
    ----------------------------------------------------------------
    do
        local box, body = AddSection(160, "Range Fade", false)

        local enChk = SCheck({
            name = "MSUF_GF_RangeFadeEnableCheck", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -6,
            label = TR("Enable Range Fade"),
            get = function(k) return GF.Val(k, "rangeFadeEnabled") end,
            set = function(k, v) GF.GetConf(k).rangeFadeEnabled = v; GF.RefreshVisuals() end,
        })

        local fadeSl = SSlider({
            name = "MSUF_GF_FadeAlphaSlider", parent = body, compact = true,
            anchor = enChk, x = 0, y = -14,
            min = 0, max = 1, step = 0.05, width = 270, default = 0.4,
            get = function(k) return GF.Val(k, "rangeFadeAlpha") end,
            set = function(k, v) GF.GetConf(k).rangeFadeAlpha = v end,
            formatText = function(v) return string.format("Out of Range Alpha: %.0f%%", v * 100) end,
        })

        SSlider({
            name = "MSUF_GF_OfflineAlphaSlider", parent = body, compact = true,
            anchor = fadeSl, x = 0, y = -32,
            min = 0, max = 1, step = 0.05, width = 270, default = 0.5,
            get = function(k) return GF.Val(k, "offlineAlpha") end,
            set = function(k, v) GF.GetConf(k).offlineAlpha = v end,
            formatText = function(v) return string.format("Offline Alpha: %.0f%%", v * 100) end,
        })
    end

    ----------------------------------------------------------------
    -- Section 8: Indicators
    ----------------------------------------------------------------
    do
        local box, body = AddSection(400, "Indicators", false)

        -- Redirect: aggro/dispel/target are controlled from the Bars menu
        local hlRedirect = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hlRedirect:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -8)
        hlRedirect:SetText(TR("Aggro / Dispel / Target Highlight"))
        hlRedirect:SetTextColor(1, 0.82, 0)

        local hlHint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hlHint:SetPoint("TOPLEFT", hlRedirect, "BOTTOMLEFT", 0, -6)
        hlHint:SetText(TR("Controlled from: |cffffd200Bars|r > |cffffd200Outline & Highlight Border|r\nEnable/disable, colors, size, offset, priority — all in one place."))
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
            set = function(k, v) GF.GetConf(k).showGroupNumber = v; GF.RefreshVisuals() end,
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
            anchor = gnSizeSl, x = -16, y = -10, width = 160,
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
            anchor = gnAnchorDd, x = 16, y = -10,
            min = -100, max = 100, step = 1, width = 200, default = -2,
            get = function(k) return GF.Val(k, "groupNumberX") end,
            set = function(k, v) GF.GetConf(k).groupNumberX = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT) end,
            formatText = function(v) return string.format("X Offset: %d", v) end,
        })

        local gnYSl = SSlider({
            name = "MSUF_GF_GroupNumberYSlider", parent = body, compact = true,
            anchor = gnXSl, x = 0, y = -32,
            min = -100, max = 100, step = 1, width = 200, default = 2,
            get = function(k) return GF.Val(k, "groupNumberY") end,
            set = function(k, v) GF.GetConf(k).groupNumberY = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT) end,
            formatText = function(v) return string.format("Y Offset: %d", v) end,
        })

        -- Hover Highlight sub-group (enable + color from global Colors menu)
        local hoverSep = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hoverSep:SetPoint("TOPLEFT", gnYSl, "BOTTOMLEFT", 0, -16)
        hoverSep:SetText(TR("Hover Highlight"))
        hoverSep:SetTextColor(1, 0.82, 0)

        local hoverHint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hoverHint:SetPoint("TOPLEFT", hoverSep, "BOTTOMLEFT", 0, -4)
        hoverHint:SetText(TR("Enable + color: Colors menu > Mouseover Highlight | Size/offset also in Bars menu"))
        hoverHint:SetTextColor(0.5, 0.55, 0.65)

        SSlider({
            name = "MSUF_GF_HoverHighlightSizeSlider", parent = body, compact = true,
            anchor = hoverHint, x = 0, y = -8,
            min = 1, max = 6, step = 1, width = 200, default = 1,
            get = function(k) return tonumber(GF.GetHighlightVal(k, "hlHoverSize")) or 1 end,
            set = function(k, v)
                GF.GetConf(k).hlHoverSize = v
                GF.GetConf(k).hlOverride = true
            end,
            formatText = function(v) return string.format("Border Thickness: %d", v) end,
        })
    end

    ----------------------------------------------------------------
    -- Section 8b: Status Icons (Selector pattern: dropdown picks icon,
    -- one set of controls updates to show that icon's config)
    ----------------------------------------------------------------
    do
        local ICON_SPECS_UI = {
            { label = "Role Icon",   enKey = "roleIcon",      sizeKey = "roleIconSize",      anchorKey = "roleIconAnchor",    xKey = "roleIconX",    yKey = "roleIconY",    defSize = 12 },
            { label = "Leader",      enKey = "leaderIcon",     sizeKey = "leaderIconSize",    anchorKey = "leaderIconAnchor",  xKey = "leaderIconX",  yKey = "leaderIconY",  defSize = 12 },
            { label = "Assist",      enKey = "assistIcon",     sizeKey = "assistIconSize",    anchorKey = "assistIconAnchor",  xKey = "assistIconX",  yKey = "assistIconY",  defSize = 12 },
            { label = "Raid Marker", enKey = "raidMarker",     sizeKey = "raidMarkerSize",    anchorKey = "raidMarkerAnchor",  xKey = "raidMarkerX",  yKey = "raidMarkerY",  defSize = 14 },
            { label = "Ready Check", enKey = "readyCheckIcon", sizeKey = "readyCheckSize",    anchorKey = "readyCheckAnchor",  xKey = "readyCheckX",  yKey = "readyCheckY",  defSize = 16 },
            { label = "Summon",      enKey = "summonIcon",     sizeKey = "summonIconSize",    anchorKey = "summonAnchor",      xKey = "summonX",      yKey = "summonY",      defSize = 16 },
            { label = "Resurrect",   enKey = "resurrectIcon",  sizeKey = "resurrectIconSize", anchorKey = "resurrectAnchor",   xKey = "resurrectX",   yKey = "resurrectY",   defSize = 16 },
            { label = "Phase",       enKey = "phaseIcon",      sizeKey = "phaseIconSize",     anchorKey = "phaseAnchor",       xKey = "phaseX",       yKey = "phaseY",       defSize = 14 },
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

        local box, body = AddSection(390, "Status Icons", false)

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
            end,
        })

        -- Enable checkbox
        local enChk = SCheck({
            name = "MSUF_GF_SI_EnableCheck", parent = body,
            anchor = selectorDd, x = 16, y = -8,
            label = TR("Enabled"),
            get = function(k) local s = ICON_SPECS_UI[_selectedIdx]; return s and GF.Val(k, s.enKey) end,
            set = function(k, v)
                local s = ICON_SPECS_UI[_selectedIdx]
                if s then GF.GetConf(k)[s.enKey] = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT) end
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
                if s then GF.GetConf(k)[s.sizeKey] = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT) end
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
                if s then GF.GetConf(k)[s.anchorKey] = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT) end
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
                if s then GF.GetConf(k)[s.xKey] = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT) end
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
                if s then GF.GetConf(k)[s.yKey] = v; GF.MarkAllDirty(GF.DIRTY_LAYOUT) end
            end,
            formatText = function(v) return string.format("Y Offset: %d", v) end,
        })

        -- Refresh all controls when selector changes
        refreshIconControls = function()
            if enChk and enChk.Refresh then enChk:Refresh() end
            if sizeSl and sizeSl.Refresh then sizeSl:Refresh() end
            if anchorDd and anchorDd.Refresh then anchorDd:Refresh() end
            if xSl and xSl.Refresh then xSl:Refresh() end
            if ySl and ySl.Refresh then ySl:Refresh() end
        end

        -- Also refresh on scope switch
        _allRefreshFns[#_allRefreshFns + 1] = function()
            if refreshIconControls then refreshIconControls() end
            if midnightChk and midnightChk.Refresh then midnightChk:Refresh() end
            if styleDd and styleDd.Refresh then styleDd:Refresh() end
        end
    end

    ----------------------------------------------------------------
    -- Sections 9-10: Buffs, Debuffs, Externals, Private Auras, Spell Indicators
    -- (delegated to MSUF_Options_GF_Auras.lua)
    ----------------------------------------------------------------
    if GF.BuildAuraOptionsSections then
        GF.BuildAuraOptionsSections(AddSection, SCheck, SSlider, SDropdown, K, TrackRefresh, MakeColorSwatch, OpenColorPicker, _allRefreshFns)
    end

    ----------------------------------------------------------------
    -- Section 11: Health Overlays
    ----------------------------------------------------------------
    do
        local box, body = AddSection(120, "Health Overlays", false)

        local healPredChk = SCheck({
            name = "MSUF_GF_HealPredEnableCheck", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -6,
            label = TR("Heal Prediction Overlay"),
            get = function(k) return GF.Val(k, "healPredEnabled") end,
            set = function(k, v)
                GF.GetConf(k).healPredEnabled = v
                for f in pairs(GF.frames) do
                    if f.unit then GF.RegisterUnitEvents(f, f.unit) end
                end
                GF.RefreshVisuals()
            end,
        })

        local hint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("TOPLEFT", healPredChk, "BOTTOMLEFT", 0, -10)
        hint:SetWidth(600)
        hint:SetJustifyH("LEFT")
        hint:SetText(TR("Absorb overlays: controlled from |cffffd200Bars|r menu > Absorb Display (shared with unit frames).\nOverlay colors: |cffffd200Colors|r menu.  Overlay textures: |cffffd200Bars|r menu."))
        hint:SetTextColor(0.55, 0.60, 0.70)
    end

    ----------------------------------------------------------------
    -- Section 12: Tooltip
    ----------------------------------------------------------------
    do
        local box, body = AddSection(140, "Tooltip", false)

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
    -- Layout: stack sections vertically
    ----------------------------------------------------------------
    local SECTION_GAP = 6

    RefreshScrollLayout = function()
        local y = -52  -- below scope bar
        for i = 1, #sections do
            local box = sections[i]
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, y)
            y = y - box:GetHeight() - SECTION_GAP
        end
        scrollChild:SetHeight(math.abs(y) + 40)
    end
    RefreshScrollLayout()

    ----------------------------------------------------------------
    -- Preview management
    ----------------------------------------------------------------
    _panel:SetScript("OnShow", function()
        ShowPreviewIfNeeded(_activeKind)
        RefreshAllWidgets()
    end)
    _panel:SetScript("OnHide", function()
        HideAllPreviews()
    end)

    ----------------------------------------------------------------
    -- Search registration
    ----------------------------------------------------------------
    if _G.MSUF_Search_RegisterRoots then
        _G.MSUF_Search_RegisterRoots({ "groupframes" }, scrollChild, "Group Frames")
    end

    return _panel
end
