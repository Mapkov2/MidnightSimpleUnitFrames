local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local T = M.Theme
local W = M.Widgets or {}
M.Widgets = W

local floor = math.floor
local max = math.max
local min = math.min
local sliderSerial = 0
local MSUF_SetIconTexture = _G.MSUF_SetIconTexture

local function Tr(text)
    if type(text) ~= "string" then return text end
    local fn = M.Tr or ns.TR
    if type(fn) == "function" then
        local translated = fn(text)
        if translated ~= nil then return translated end
    end
    local locale = ns.L or _G.MSUF_L
    if type(locale) == "table" and locale[text] ~= nil then return locale[text] end
    return text
end

local function SetSearchText(object, text)
    if object and text ~= nil then object._msuf2SearchText = text end
    return object
end

local function SetSearchTitle(object, text)
    if object and text ~= nil then object._msuf2SearchTitle = text end
    return object
end

local function PlaceBackdropFrameBehindControls(frame, parent)
    if not (frame and frame.SetFrameLevel) then return end
    local parentLevel = 0
    if parent and parent.GetFrameLevel then
        parentLevel = tonumber(parent:GetFrameLevel()) or 0
    end
    frame:SetFrameLevel(max(0, parentLevel))
end

local function RegisterSearchObject(object, label, kind, opts)
    SetSearchText(object, label)
    if object and type(M.RegisterSearchWidget) == "function" then
        opts = opts or {}
        opts.label = opts.label or label
        opts.kind = opts.kind or kind
        M.RegisterSearchWidget(object, opts)
    end
    return object
end

local function IsMSUFEditModeActive()
    local st = rawget(_G, "MSUF_EditState")
    if type(st) == "table" and st.active ~= nil then
        return st.active == true
    end

    local em2 = rawget(_G, "MSUF_EM2")
    local state = em2 and em2.State
    if state and type(state.IsActive) == "function" then
        return state.IsActive() and true or false
    end

    local fn = rawget(_G, "MSUF_IsMSUFEditModeActive")
        or rawget(_G, "MSUF_IsInEditMode")
        or rawget(_G, "MSUF_IsEditModeActive")
    if type(fn) == "function" then
        local ok, active = pcall(fn)
        if ok then return active and true or false end
    end

    return rawget(_G, "MSUF_UnitEditModeActive") == true
        or rawget(_G, "MSUF_EDITMODE_ACTIVE") == true
end

local function IsEditModeCombatLocked()
    return (_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
end

local function ToggleMSUFEditMode()
    local active = IsMSUFEditModeActive()
    if (not active) and IsEditModeCombatLocked() then
        if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then _G.MSUF_ShowConfigCombatLockMessage() end
        return
    end
    local fn = rawget(_G, "MSUF_SetMSUFEditModeDirect") or rawget(_G, "MSUF_SetEditMode")
    if type(fn) == "function" then
        pcall(fn, not active)
    end
    if M.frame and M.frame.RefreshStatus then M.frame:RefreshStatus() end
    if M.Refresh then M.Refresh() end
end

local function HideSliderTemplateParts(slider)
    if not slider then return end
    local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
    local regions = { slider:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        local isTexture = false
        if region and region.IsObjectType then isTexture = region:IsObjectType("Texture") and true or false end
        if (not isTexture) and region and region.GetObjectType then isTexture = (region:GetObjectType() == "Texture") end
        if isTexture
            and region ~= thumb
            and region ~= slider._msufTrack
            and region ~= slider._msufTrackTop
            and region ~= slider._msufTrackBottom
            and region ~= slider._msufFill
            and region ~= slider._msufFillGlow
            and region ~= slider._msufPeelTrack
            and region ~= slider._msufPeelTrackFill
        then
            if region.SetAlpha then region:SetAlpha(0) end
            if region.Hide then region:Hide() end
        end
    end

    local name = slider.GetName and slider:GetName()
    for _, suffix in ipairs({ "Left", "Middle", "Right", "Text", "Low", "High" }) do
        local region = (name and _G[name .. suffix]) or slider[suffix]
        if region then
            if region.SetText then region:SetText("") end
            if region.SetAlpha then region:SetAlpha(0) end
            if region.Hide then region:Hide() end
        end
    end
end

function W.PageBuilder(ctx)
    if type(M.EnsurePersistentMenuState) == "function" then M.EnsurePersistentMenuState() end
    local b = {
        ctx = ctx,
        parent = ctx.wrapper,
        x = 12,
        y = -12,
        width = ctx.width or 720,
        collapsibles = {},
    }

    function b:RelayoutCollapsibles()
        if not self._collapsibleStartY then return end
        local y = self._collapsibleStartY
        for i = 1, #self.collapsibles do
            local entry = self.collapsibles[i]
            local open = entry.open and true or false
            entry.outer:ClearAllPoints()
            entry.outer:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, y)
            entry.outer:SetHeight(entry.headerHeight + (open and entry.contentHeight or 0))
            entry.body:SetShown(open)
            T.ApplyCollapseVisual(entry.arrow, entry.hint, open)
            if entry._msuf2RefreshState then pcall(entry._msuf2RefreshState, entry) end
            y = y - entry.outer:GetHeight() - 8
        end
        self.y = y
        if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(y) + 42) end
    end

    function b:Section(title, height)
        local section = T.Panel(self.parent, nil, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft)
        SetSearchTitle(section, title)
        RegisterSearchObject(section, title, "section")
        section:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, self.y)
        section:SetSize(self.width, height or 120)
        section._msuf2CursorY = -38
        section._msuf2ContentX = 14
        section._msuf2Width = self.width

        local fs = T.Font(section, "GameFontNormal", Tr(title or ""), T.colors.text)
        SetSearchText(fs, title)
        fs:SetPoint("TOPLEFT", 14, -12)
        section.title = fs

        self.y = self.y - (height or 120) - 12
        if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(self.y) + 28) end
        return section
    end

    function b:CollapsibleSection(id, title, height, defaultOpen)
        if type(M.GetPersistentMenuStateTable) == "function" then
            M.accordionState = M.GetPersistentMenuStateTable("accordionState")
        else
            M.accordionState = M.accordionState or {}
        end
        local stateKey = tostring(ctx.key or "page") .. ":" .. tostring(id or title or "section")
        local saved = M.accordionState[stateKey]
        local open = (saved == nil) and (defaultOpen and true or false) or (saved and true or false)
        local headerH = 28

        if not self._collapsibleStartY then self._collapsibleStartY = self.y end

        local outer = T.Panel(self.parent, nil, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft)
        SetSearchTitle(outer, title)
        RegisterSearchObject(outer, title, "section")
        outer:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, self.y)
        outer:SetSize(self.width, headerH + (open and (height or 120) or 0))

        local header = CreateFrame("Button", nil, outer)
        SetSearchTitle(header, title)
        header:SetPoint("TOPLEFT", outer, "TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", outer, "TOPRIGHT", 0, 0)
        header:SetHeight(headerH)
        local headerBg = header:CreateTexture(nil, "BACKGROUND")
        headerBg:SetAllPoints()
        headerBg:SetColorTexture(0.060, 0.070, 0.130, 0.48)
        local headerHover = header:CreateTexture(nil, "HIGHLIGHT")
        headerHover:SetAllPoints()
        headerHover:SetColorTexture(1, 1, 1, 0.03)

        local arrow = header:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(10, 10)
        arrow:SetPoint("LEFT", header, "LEFT", 12, 0)
        arrow:SetTexture(T.media.collapseArrow)

        local label = T.Font(header, "GameFontNormal", Tr(title or ""), T.colors.text)
        SetSearchText(label, title)
        label:SetJustifyH("LEFT")

        local hint = T.Font(header, "GameFontDisableSmall", "", T.colors.dim)
        hint:SetJustifyH("RIGHT")

        local contentW = math.min(self.width, M.formContentMaxWidth or 980)
        local body = CreateFrame("Frame", nil, outer)
        SetSearchTitle(body, title)
        body:SetPoint("TOPLEFT", outer, "TOPLEFT", 0, -headerH)
        body:SetSize(contentW, height or 120)
        body._msuf2CursorY = -38
        body._msuf2ContentX = 14
        body._msuf2Width = contentW

        local entry = {
            outer = outer,
            header = header,
            headerBg = headerBg,
            headerHover = headerHover,
            body = body,
            arrow = arrow,
            label = label,
            hint = hint,
            open = open,
            headerHeight = headerH,
            contentHeight = height or 120,
            stateKey = stateKey,
        }
        local function RefreshHeaderLayout()
            local headerW = (header.GetWidth and header:GetWidth()) or self.width or 240
            local reserve = math.max(120, math.min(136, math.floor(headerW * 0.38 + 0.5)))
            if not entry._msuf2ManualHintLayout then
                local badges = entry._msuf2Badges
                if badges and #badges > 0 then
                    local right = -12
                    local hasVisibleBadge = false
                    for i = #badges, 1, -1 do
                        local badge = badges[i]
                        if badge and badge.IsShown and badge:IsShown() then
                            hasVisibleBadge = true
                            local bw = (badge.GetWidth and badge:GetWidth()) or 0
                            badge:ClearAllPoints()
                            badge:SetPoint("RIGHT", header, "RIGHT", right, 0)
                            right = right - bw - 6
                        end
                    end

                    if hasVisibleBadge then
                        if hint.Hide then hint:Hide() end

                        label:ClearAllPoints()
                        label:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
                        label:SetPoint("RIGHT", header, "RIGHT", right - 8, 0)
                        label:SetJustifyH("LEFT")
                        return
                    end
                end

                if hint.Show then hint:Show() end
                hint:ClearAllPoints()
                hint:SetPoint("TOPRIGHT", header, "TOPRIGHT", -12, -1)
                hint:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -12, 1)
                hint:SetPoint("LEFT", header, "RIGHT", -(12 + reserve), 0)
                hint:SetJustifyH("RIGHT")

                label:ClearAllPoints()
                label:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
                label:SetPoint("RIGHT", hint, "LEFT", -8, 0)
                label:SetJustifyH("LEFT")
            end
        end
        entry._msuf2RefreshLayout = RefreshHeaderLayout
        outer._msuf2CollapsibleEntry = entry
        body._msuf2CollapsibleEntry = entry
        self.collapsibles[#self.collapsibles + 1] = entry
        header:SetScript("OnClick", function()
            entry.open = not entry.open
            M.accordionState[stateKey] = entry.open
            self:RelayoutCollapsibles()
        end)
        header:HookScript("OnSizeChanged", RefreshHeaderLayout)

        self.y = self.y - outer:GetHeight() - 8
        RefreshHeaderLayout()
        self:RelayoutCollapsibles()
        return body
    end

    function b:Header(title, subtitle, height)
        local section = T.Panel(self.parent, nil, T.colors.panel2, T.colors.border)
        SetSearchTitle(section, title)
        RegisterSearchObject(section, title, "section")
        section:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, self.y)
        section:SetSize(self.width, height or 78)
        local fs = T.Font(section, "GameFontNormalLarge", Tr(title or ""), T.colors.text)
        SetSearchText(fs, title)
        fs:SetPoint("TOPLEFT", 14, -12)
        section.title = fs
        if subtitle and subtitle ~= "" then
            local sub = T.Font(section, "GameFontDisableSmall", Tr(subtitle), T.colors.muted)
            SetSearchText(sub, subtitle)
            sub:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -6)
            sub:SetWidth(self.width - 28)
            sub:SetJustifyH("LEFT")
        end
        self.y = self.y - (height or 78) - 12
        if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(self.y) + 28) end
        return section
    end

    function b:GlobalStyleHeader(title, subtitle, height)
        return W.GlobalStyleHeader(ctx, self, title, subtitle, height)
    end

    function b:Spacer(height)
        self.y = self.y - (height or 10)
        if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(self.y) + 28) end
    end

    return b
end

local TOP_ACTION_BUTTON_STYLE = {
    bg = { 0.018, 0.028, 0.058, 0.95 },
    border = { 0.082, 0.125, 0.245, 0.66 },
    textColor = { 0.82, 0.90, 1.00, 1 },
    hoverBg = { 0.026, 0.040, 0.078, 0.97 },
    hoverBorder = { 0.125, 0.220, 0.430, 0.80 },
    activeBg = { 0.018, 0.028, 0.058, 0.95 },
    activeBorder = { 0.082, 0.125, 0.245, 0.66 },
    activeTextColor = { 0.82, 0.90, 1.00, 1 },
}

local TOP_DANGER_BUTTON_STYLE = {
    bg = { 0.070, 0.026, 0.034, 0.94 },
    border = { 0.340, 0.090, 0.110, 0.82 },
    textColor = { 1.00, 0.82, 0.82, 1 },
    hoverBg = { 0.090, 0.035, 0.045, 0.96 },
    hoverBorder = { 0.420, 0.120, 0.140, 0.90 },
    activeBg = { 0.070, 0.026, 0.034, 0.94 },
    activeBorder = { 0.340, 0.090, 0.110, 0.82 },
    activeTextColor = { 1.00, 0.82, 0.82, 1 },
}

local TOP_SUCCESS_BUTTON_STYLE = {
    bg = { 0.018, 0.145, 0.090, 0.94 },
    border = { 0.055, 0.440, 0.270, 0.82 },
    textColor = { 0.780, 1.000, 0.875, 1 },
    hoverBg = { 0.026, 0.185, 0.115, 0.96 },
    hoverBorder = { 0.075, 0.560, 0.345, 0.90 },
    activeBg = { 0.018, 0.145, 0.090, 0.94 },
    activeBorder = { 0.055, 0.440, 0.270, 0.82 },
    activeTextColor = { 0.780, 1.000, 0.875, 1 },
}

local function ApplyTopActionButtonVisual(btn, hover)
    local bg = btn._msuf2TopActive and btn._msuf2TopActiveBg or (hover and btn._msuf2TopHoverBg or btn._msuf2TopBg)
    local br = btn._msuf2TopActive and btn._msuf2TopActiveBorder or (hover and btn._msuf2TopHoverBorder or btn._msuf2TopBorder)
    local tx = btn._msuf2TopActive and btn._msuf2TopActiveText or btn._msuf2TopText
    local mul = hover and 1.06 or 1
    if btn._msuf2Fill then btn._msuf2Fill:SetVertexColor(min(bg[1] * mul, 1), min(bg[2] * mul, 1), min(bg[3] * mul, 1), bg[4] or 1) end
    if btn._msuf2Edge then btn._msuf2Edge:SetVertexColor(min(br[1] * mul, 1), min(br[2] * mul, 1), min(br[3] * mul, 1), br[4] or 1) end
    if btn._msuf2Label then btn._msuf2Label:SetTextColor(tx[1], tx[2], tx[3], tx[4] or 1) end
end

local function StyleTopButton(btn, style)
    local s = style or TOP_ACTION_BUTTON_STYLE
    btn._msuf2TopActive = false
    btn._msuf2TopBg = s.bg
    btn._msuf2TopBorder = s.border
    btn._msuf2TopText = s.textColor
    btn._msuf2TopHoverBg = s.hoverBg
    btn._msuf2TopHoverBorder = s.hoverBorder
    btn._msuf2TopActiveBg = s.activeBg
    btn._msuf2TopActiveBorder = s.activeBorder
    btn._msuf2TopActiveText = s.activeTextColor
    if btn._msuf2Label then
        btn._msuf2Label:ClearAllPoints()
        btn._msuf2Label:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btn._msuf2Label:SetJustifyH("CENTER")
        if btn._msuf2Label.SetShadowColor then btn._msuf2Label:SetShadowColor(0, 0, 0, 0.55) end
        if btn._msuf2Label.SetShadowOffset then btn._msuf2Label:SetShadowOffset(1, -1) end
    end
    btn.SetActive = function(self, active)
        self._msuf2TopActive = active and true or false
        ApplyTopActionButtonVisual(self)
    end
    btn.SetEnabled = function(self, enabled)
        if enabled then
            if self.Enable then self:Enable() end
        else
            if self.Disable then self:Disable() end
        end
        ApplyTopActionButtonVisual(self)
    end
    btn:SetScript("OnEnter", function(self) ApplyTopActionButtonVisual(self, true) end)
    btn:SetScript("OnLeave", function(self) ApplyTopActionButtonVisual(self) end)
    btn:SetScript("OnEnable", function(self) ApplyTopActionButtonVisual(self) end)
    btn:SetScript("OnDisable", function(self) ApplyTopActionButtonVisual(self) end)
    ApplyTopActionButtonVisual(btn)
    return btn
end

local function StyleTopActionButton(btn)
    return StyleTopButton(btn, TOP_ACTION_BUTTON_STYLE)
end
W.StyleTopActionButton = StyleTopActionButton

local function StyleTopDangerButton(btn)
    return StyleTopButton(btn, TOP_DANGER_BUTTON_STYLE)
end
W.StyleTopDangerButton = StyleTopDangerButton

local function StyleTopSuccessButton(btn)
    return StyleTopButton(btn, TOP_SUCCESS_BUTTON_STYLE)
end
W.StyleTopSuccessButton = StyleTopSuccessButton

function W.CreatePageResetButton(ctx, parent, anchor, opts)
    opts = opts or {}
    local key = ctx and ctx.key
    if not (M.PageHasReset and M.PageHasReset(key)) then return nil end
    local label = opts.text or "Reset All"
    local btn = StyleTopDangerButton(T.Button(parent, label, opts.width or 88, opts.height or 24))
    btn._msuf2SkipHistoryCheckpoint = true
    if anchor then
        btn:SetPoint("RIGHT", anchor, "LEFT", -(opts.gap or 8), opts.offsetY or 0)
    else
        btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", opts.x or -14, opts.y or -14)
    end
    btn:SetScript("OnClick", function()
        if M.ShowPageResetConfirm then M.ShowPageResetConfirm(key) end
    end)
    RegisterSearchObject(btn, label, "button")
    return btn
end

function W.GlobalStyleHeader(ctx, builder, title, subtitle, height)
    if not (builder and builder.Header) then return nil end
    local head = builder:Header(title, subtitle, height or 72)
    local edit = StyleTopActionButton(T.Button(head, "MSUF Edit Mode", 128, 24))
    RegisterSearchObject(edit, "MSUF Edit Mode", "button")
    edit:SetPoint("TOPRIGHT", head, "TOPRIGHT", -14, -14)
    edit:SetScript("OnClick", ToggleMSUFEditMode)
    W.CreatePageResetButton(ctx, head, edit, { width = 88 })

    local function RefreshEditButton()
        local active = IsMSUFEditModeActive()
        local locked = IsEditModeCombatLocked() and true or false
        if edit.SetText then edit:SetText(active and Tr("Exit Edit Mode") or Tr("MSUF Edit Mode")) end
        if edit.SetActive then edit:SetActive(false) end
        if edit.SetEnabled then edit:SetEnabled(active or not locked) end
    end

    if ctx and M.AddRefresher then M.AddRefresher(ctx, RefreshEditButton) end
    RefreshEditButton()
    return head, edit
end

function W.SetCollapsibleToggleText(section, openText, closedText)
    local entry = section and section._msuf2CollapsibleEntry
    if not (entry and entry.label and entry.label.SetText) then return nil end

    local function Refresh()
        entry.label:SetText(Tr(entry.open and (openText or "") or (closedText or openText or "")))
    end

    if entry.header and entry.header.HookScript and not entry._msuf2DynamicTitleHooked then
        entry._msuf2DynamicTitleHooked = true
        entry.header:HookScript("OnClick", Refresh)
    end
    Refresh()
    return Refresh
end

local COLLAPSIBLE_BADGE_STYLES = {
    ok = {
        bg = { 0.018, 0.230, 0.145, 0.94 },
        border = { 0.050, 0.690, 0.430, 0.88 },
        text = { 0.640, 1.000, 0.820, 1 },
    },
    info = {
        bg = { 0.060, 0.090, 0.210, 0.92 },
        border = { 0.160, 0.260, 0.560, 0.78 },
        text = { 0.760, 0.840, 1.000, 1 },
    },
    accent = {
        bg = { 0.018, 0.170, 0.280, 0.94 },
        border = { 0.100, 0.530, 0.780, 0.86 },
        text = { 0.680, 0.920, 1.000, 1 },
    },
    muted = {
        bg = { 0.045, 0.055, 0.090, 0.90 },
        border = { 0.110, 0.140, 0.230, 0.72 },
        text = { 0.680, 0.730, 0.860, 1 },
    },
}

local function CollapsibleBadgeWidth(text)
    text = tostring(Tr(text or ""))
    return max(48, min(176, floor(22 + (#text * 6.2) + 0.5)))
end

function W.SetCollapsibleBadges(section, specs)
    local entry = section and section._msuf2CollapsibleEntry
    local header = entry and entry.header
    if not header then return end

    entry._msuf2Badges = entry._msuf2Badges or {}
    specs = specs or {}
    local onlyWhenOpen = section._msuf2CollapsibleBadgesOnlyWhenOpen == true
        or entry._msuf2CollapsibleBadgesOnlyWhenOpen == true

    for i = 1, #specs do
        local spec = specs[i] or {}
        local badge = entry._msuf2Badges[i]
        if not badge then
            badge = CreateFrame("Frame", nil, header)
            badge:SetSize(54, 20)
            badge:SetFrameLevel((header.GetFrameLevel and header:GetFrameLevel() or 1) + 2)
            local fill, edge = T.CreateSuperellipseLayers(badge, "_msuf2HeaderBadge", 1, "ARTWORK", "OVERLAY")
            badge._msuf2Fill = fill
            badge._msuf2Edge = edge
            badge.text = T.Font(badge, "GameFontDisableSmall", "", T.colors.text)
            badge.text:SetPoint("CENTER", badge, "CENTER", 0, 0)
            badge.text:SetJustifyH("CENTER")
            entry._msuf2Badges[i] = badge
        end

        local text = Tr(spec.text or "")
        local style = COLLAPSIBLE_BADGE_STYLES[spec.kind or spec.style or "info"] or COLLAPSIBLE_BADGE_STYLES.info
        badge:SetSize(tonumber(spec.width) or CollapsibleBadgeWidth(text), tonumber(spec.height) or 20)
        if badge.text then
            badge.text:SetText(text)
            local c = style.text
            badge.text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        end
        if badge._msuf2Fill then
            local c = style.bg
            badge._msuf2Fill:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
        end
        if badge._msuf2Edge then
            local c = style.border
            badge._msuf2Edge:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
        end
        local shown = text ~= ""
        if shown and (onlyWhenOpen or spec.onlyWhenOpen == true) then
            shown = entry.open == true
        end
        badge:SetShown(shown)
    end

    for i = #specs + 1, #entry._msuf2Badges do
        local badge = entry._msuf2Badges[i]
        if badge then badge:SetShown(false) end
    end

    if entry._msuf2RefreshLayout then entry._msuf2RefreshLayout() end
end

local function NextRow(section, height)
    local y = section._msuf2CursorY or -38
    section._msuf2CursorY = y - (height or 28)
    return section._msuf2ContentX or 14, y
end

local function CreateToggle(section, label, x, y, labelWidth)
    local btn = CreateFrame("CheckButton", nil, section, "UICheckButtonTemplate")
    btn._msuf2ControlKind = "toggle"
    btn:SetPoint("TOPLEFT", x, y)
    btn:SetSize(24, 24)

    btn._msuf2Label = T.Font(section, "GameFontHighlightSmall", Tr(label or ""), T.colors.text)
    SetSearchText(btn._msuf2Label, label)
    btn._msuf2Label:SetPoint("LEFT", btn, "RIGHT", 6, 0)
    btn._msuf2Label:SetJustifyH("LEFT")
    if not labelWidth and section and section._msuf2Width then
        labelWidth = max(40, (section._msuf2Width or 0) - (x or 0) - 44)
    end
    if labelWidth then btn._msuf2Label:SetWidth(labelWidth) end
    btn.text = btn._msuf2Label
    if T.StyleCheckmark then T.StyleCheckmark(btn) end
    btn:HookScript("OnShow", function(self)
        if T.StyleCheckmark then T.StyleCheckmark(self) end
    end)

    local labelHit = CreateFrame("Button", nil, section)
    labelHit:SetFrameLevel(btn:GetFrameLevel() + 2)
    labelHit:SetPoint("TOPLEFT", btn._msuf2Label, "TOPLEFT", -2, 2)
    labelHit:SetPoint("BOTTOMRIGHT", btn._msuf2Label, "BOTTOMRIGHT", 2, -2)
    labelHit:SetScript("OnClick", function()
        if btn.IsEnabled and not btn:IsEnabled() then return end
        if btn.Click then btn:Click() end
    end)
    labelHit:SetScript("OnEnter", function()
        if btn.LockHighlight then btn:LockHighlight() end
    end)
    labelHit:SetScript("OnLeave", function()
        if btn.UnlockHighlight then btn:UnlockHighlight() end
    end)
    btn._msuf2LabelHit = labelHit
    btn:SetChecked(false)
    RegisterSearchObject(btn, label, "toggle", { anchor = btn._msuf2Label })
    return btn
end

function W.Text(parent, text, x, y, width, color)
    local fs = T.Font(parent, "GameFontHighlightSmall", Tr(text or ""), color or T.colors.muted)
    SetSearchText(fs, text)
    RegisterSearchObject(fs, text, "text")
    fs:SetPoint("TOPLEFT", x or 0, y or 0)
    fs:SetWidth(width or 300)
    fs:SetJustifyH("LEFT")
    return fs
end

function W.ControlCard(parent, title, subtitle, x, y, width, height)
    if not parent then return nil end
    width = width or 360
    height = height or 120

    local card = T.Panel(parent, nil, { 0.018, 0.026, 0.052, 0.86 }, T.colors.cardBorder or T.colors.borderSoft)
    SetSearchTitle(card, title)
    RegisterSearchObject(card, title, "section")
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
    card:SetSize(width, height)
    PlaceBackdropFrameBehindControls(card, parent)
    card._msuf2Width = width
    card._msuf2ContentX = 16
    card._msuf2CursorY = -52
    if card.EnableMouse then card:EnableMouse(false) end

    local heading = T.Font(card, "GameFontNormal", Tr(title or ""), T.colors.text)
    SetSearchText(heading, title)
    heading:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -16)
    heading:SetWidth(max(24, width - 32))
    heading:SetJustifyH("LEFT")
    card.title = heading

    if subtitle and subtitle ~= "" then
        local sub = T.Font(card, "GameFontDisableSmall", Tr(subtitle), T.colors.muted)
        SetSearchText(sub, subtitle)
        sub:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -40)
        sub:SetWidth(max(24, width - 32))
        sub:SetJustifyH("LEFT")
        if sub.SetWordWrap then sub:SetWordWrap(true) end
        card.subtitle = sub
    end

    return card
end

function W.ControlCardBackdrop(parent, x, y, width, height, bg, border)
    if not parent then return nil end
    width = max(24, floor((tonumber(width) or 360) + 0.5))
    height = max(24, floor((tonumber(height) or 120) + 0.5))
    x = floor((tonumber(x) or 0) + 0.5)
    y = floor((tonumber(y) or 0) + 0.5)

    local card = T.Panel(parent, nil, bg or { 0.018, 0.026, 0.052, 0.86 }, border or T.colors.cardBorder or T.colors.borderSoft)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    card:SetSize(width, height)
    PlaceBackdropFrameBehindControls(card, parent)
    card._msuf2Width = width
    card._msuf2DecorativeBackdrop = true
    if card.EnableMouse then card:EnableMouse(false) end
    if card.SetHitRectInsets then card:SetHitRectInsets(0, 0, 0, 0) end
    return card
end

function W.Toggle(section, label)
    local x, y = NextRow(section, 30)
    return CreateToggle(section, label, x, y)
end

function W.ToggleAt(section, label, x, y, labelWidth)
    return CreateToggle(section, label, x or 14, y or -38, labelWidth)
end

function W.SwitchAt(section, label, x, y, labelWidth, labelSide)
    local switchW, switchH = 35, 18
    local knobSize = 14
    local knobPad = 2

    local btn = CreateFrame("CheckButton", nil, section)
    btn._msuf2ControlKind = "toggle"
    btn:SetPoint("TOPLEFT", x or 14, y or -38)
    btn:SetSize(switchW, switchH)

    local edge = btn:CreateTexture(nil, "BACKGROUND", nil, 0)
    edge:SetTexture((T.media and T.media.switchTrack) or (T.media and T.media.superellipse) or "Interface\\Buttons\\WHITE8X8")
    edge:SetAllPoints(btn)
    edge:SetTexCoord(0, 1, 0, 1)
    if edge.SetSnapToPixelGrid then edge:SetSnapToPixelGrid(false) end
    if edge.SetTexelSnappingBias then edge:SetTexelSnappingBias(0) end

    local fill = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    fill:SetTexture((T.media and T.media.switchTrack) or (T.media and T.media.superellipse) or "Interface\\Buttons\\WHITE8X8")
    fill:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    fill:SetTexCoord(0, 1, 0, 1)
    if fill.SetSnapToPixelGrid then fill:SetSnapToPixelGrid(false) end
    if fill.SetTexelSnappingBias then fill:SetTexelSnappingBias(0) end
    btn._msuf2SwitchFill = fill
    btn._msuf2SwitchEdge = edge

    local knob = btn:CreateTexture(nil, "OVERLAY")
    knob:SetTexture((T.media and T.media.switchKnob) or (T.media and T.media.sliderThumb) or (T.media and T.media.superellipse) or "Interface\\Buttons\\WHITE8X8")
    knob:SetTexCoord(0, 1, 0, 1)
    knob:SetSize(knobSize, knobSize)
    if knob.SetSnapToPixelGrid then knob:SetSnapToPixelGrid(false) end
    if knob.SetTexelSnappingBias then knob:SetTexelSnappingBias(0) end
    btn._msuf2SwitchKnob = knob

    local side = labelSide or "RIGHT"
    local labelFS = T.Font(section, "GameFontHighlightSmall", Tr(label or ""), T.colors.text)
    SetSearchText(labelFS, label)
    labelFS:SetJustifyH(side == "LEFT" and "RIGHT" or "LEFT")
    if not labelWidth and section and section._msuf2Width then
        labelWidth = max(40, (section._msuf2Width or 0) - (x or 0) - switchW - 30)
    end
    if labelWidth then labelFS:SetWidth(max(20, labelWidth - (side == "RIGHT" and 22 or 0))) end
    if side == "LEFT" then
        labelFS:SetPoint("RIGHT", btn, "LEFT", -8, 0)
    else
        labelFS:SetPoint("LEFT", btn, "RIGHT", 8, 0)
    end
    if side == "HIDDEN" then labelFS:Hide() end
    btn._msuf2Label = labelFS
    btn.text = labelFS

    local function Refresh(self, hover)
        local checked = self.GetChecked and self:GetChecked()
        local enabled = not self.IsEnabled or self:IsEnabled()
        local bg = checked and { 0.020, 0.090, 0.135, 0.96 } or { 0.014, 0.022, 0.048, 0.96 }
        local br = checked and { 0.160, 0.560, 0.760, 0.86 } or { 0.095, 0.145, 0.255, 0.82 }
        local kb = checked and { 0.380, 0.760, 0.900, 1.00 } or { 0.680, 0.760, 0.940, 1.00 }
        local mul = (hover and enabled) and 1.08 or 1
        local alpha = enabled and 1 or 0.45
        if self._msuf2SwitchFill then self._msuf2SwitchFill:SetVertexColor(min(bg[1] * mul, 1), min(bg[2] * mul, 1), min(bg[3] * mul, 1), (bg[4] or 1) * alpha) end
        if self._msuf2SwitchEdge then self._msuf2SwitchEdge:SetVertexColor(min(br[1] * mul, 1), min(br[2] * mul, 1), min(br[3] * mul, 1), (br[4] or 1) * alpha) end
        if knob then
            knob:ClearAllPoints()
            knob:SetTexture((T.media and T.media.switchKnob) or (T.media and T.media.sliderThumb) or (T.media and T.media.superellipse) or "Interface\\Buttons\\WHITE8X8")
            knob:SetTexCoord(0, 1, 0, 1)
            knob:SetPoint(checked and "RIGHT" or "LEFT", self, checked and "RIGHT" or "LEFT", checked and -knobPad or knobPad, 0)
            knob:SetVertexColor(kb[1], kb[2], kb[3], (kb[4] or 1) * alpha)
            if knob.SetAlpha then knob:SetAlpha(alpha) end
        end
    end
    btn._msuf2RefreshSwitchVisual = Refresh

    local rawSetChecked = btn.SetChecked
    btn.SetChecked = function(self, value)
        rawSetChecked(self, value and true or false)
        Refresh(self)
    end
    btn:HookScript("OnEnter", function(self) Refresh(self, true) end)
    btn:HookScript("OnLeave", function(self) Refresh(self) end)
    btn:HookScript("OnClick", function(self) Refresh(self) end)
    btn:HookScript("OnEnable", function(self) Refresh(self) end)
    btn:HookScript("OnDisable", function(self) Refresh(self) end)

    if side ~= "HIDDEN" then
        local labelHit = CreateFrame("Button", nil, section)
        labelHit:SetFrameLevel(btn:GetFrameLevel() + 2)
        labelHit:SetPoint("TOPLEFT", labelFS, "TOPLEFT", -2, 2)
        labelHit:SetPoint("BOTTOMRIGHT", labelFS, "BOTTOMRIGHT", 2, -2)
        labelHit:SetScript("OnClick", function()
            if btn.IsEnabled and not btn:IsEnabled() then return end
            if btn.Click then btn:Click() end
        end)
        labelHit:SetScript("OnEnter", function()
            Refresh(btn, true)
            if btn.LockHighlight then btn:LockHighlight() end
        end)
        labelHit:SetScript("OnLeave", function()
            Refresh(btn)
            if btn.UnlockHighlight then btn:UnlockHighlight() end
        end)
        btn._msuf2LabelHit = labelHit
    end

    btn:SetChecked(false)
    RegisterSearchObject(btn, label, "toggle", { anchor = side ~= "HIDDEN" and labelFS or btn })
    return btn
end

local function ScopeButtonWidth(item)
    if item and item.width then return item.width end
    local value = item and item.value
    local text = tostring(Tr((item and (item.text or item.label)) or value or ""))
    if value == "shared" then return 72 end
    if value == "targettarget" then return 58 end
    if value == "focustarget" then return 92 end
    if text == "Boss 1" or text == "Boss 2" or text == "Boss 3" or text == "Boss 4" or text == "Boss 5" then return 74 end
    return math.max(54, math.min(96, 28 + (#text * 7)))
end

local function MeasureScopeOverrideLayout(values, opts)
    opts = opts or {}
    values = values or opts.values or {}
    local centerY = opts.centerY or -28
    local labelX = opts.labelX or 14
    local labelW = opts.labelWidth or 64
    local gap = opts.gap or 8
    local buttonH = opts.buttonHeight or 24
    local rowStep = opts.rowStep or (buttonH + 6)
    local sectionW = opts.width or (opts.ctx and opts.ctx.width) or 720
    local maxRight = opts.maxRight or (sectionW - 14)
    local startX = opts.startX or (labelX + labelW + 8)
    local x, y = startX, centerY
    local rows = 1

    for i = 1, #values do
        local width = ScopeButtonWidth(values[i])
        if x > startX and x + width > maxRight then
            x = startX
            y = y - rowStep
            rows = rows + 1
        end
        x = x + width + gap
    end

    return {
        rows = rows,
        bottomY = y - math.floor(buttonH * 0.5 + 0.5),
        centerY = centerY,
        lastRowCenterY = y,
        rowStep = rowStep,
        buttonHeight = buttonH,
        sectionWidth = sectionW,
        maxRight = maxRight,
        startX = startX,
    }
end

function W.MeasureScopeOverrideBar(values, opts)
    if type(values) == "table" and values.values and opts == nil then
        opts = values
        values = opts.values
    end
    return MeasureScopeOverrideLayout(values, opts)
end

function W.ScopeOverrideBar(ctx, section, opts)
    opts = opts or {}
    local values = opts.values or {}
    local centerY = opts.centerY or -28
    local labelX = opts.labelX or 14
    local labelW = opts.labelWidth or 64
    local gap = opts.gap or 8
    local buttonH = opts.buttonHeight or 24
    local sectionW = opts.width or section._msuf2Width or (ctx and ctx.width) or (section.GetWidth and section:GetWidth()) or 720
    local maxRight = opts.maxRight or (sectionW - 14)
    local startX = opts.startX or (labelX + labelW + 8)
    local rowStep = opts.rowStep or (buttonH + 6)
    local metrics = MeasureScopeOverrideLayout(values, {
        centerY = centerY,
        labelX = labelX,
        labelWidth = labelW,
        gap = gap,
        buttonHeight = buttonH,
        rowStep = rowStep,
        width = sectionW,
        maxRight = maxRight,
        startX = startX,
    })

    local label = T.Font(section, opts.labelFont or "GameFontHighlightSmall", Tr(opts.label or "Editing:"), opts.labelColor or T.colors.text)
    SetSearchText(label, opts.label or "Editing:")
    RegisterSearchObject(label, opts.label or "Editing:", "text")
    label:SetPoint("LEFT", section, "TOPLEFT", labelX, centerY)
    label:SetWidth(labelW)
    label:SetJustifyH("LEFT")

    local bar = CreateFrame("Frame", nil, section)
    SetSearchTitle(bar, opts.label or "Editing:")
    RegisterSearchObject(bar, opts.label or "Editing:", "segment", { values = values })
    bar:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
    bar:SetSize(sectionW, math.abs(metrics.bottomY) + 6)
    bar.buttons = {}
    bar.values = values
    bar.label = label
    bar._msuf2Rows = metrics.rows
    bar._msuf2BottomY = metrics.bottomY
    bar._msuf2LastRowCenterY = metrics.lastRowCenterY

    local x, y = startX, centerY
    for i = 1, #values do
        local item = values[i]
        local width = ScopeButtonWidth(item)
        if x > startX and x + width > maxRight then
            x = startX
            y = y - rowStep
        end
        local btn = T.Button(section, Tr(item.text or item.label or item.value or ""), width, buttonH)
        RegisterSearchObject(btn, item.text or item.label or item.value or "", "button")
        btn:SetPoint("LEFT", section, "TOPLEFT", x, y)
        btn._msuf2Value = item.value
        btn._msuf2BaseWidth = width
        if btn._msuf2Label then
            btn._msuf2Label:ClearAllPoints()
            btn._msuf2Label:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn._msuf2Label:SetJustifyH("CENTER")
        end
        btn:SetScript("OnClick", function()
            if type(opts.setValue) == "function" then opts.setValue(item.value) end
            if type(opts.onChange) == "function" then opts.onChange(item.value) end
            if bar.Refresh then bar:Refresh() end
        end)
        bar.buttons[i] = btn
        x = x + width + gap
    end

    function bar:GetValue()
        if type(opts.getValue) == "function" then return opts.getValue() end
        return opts.value
    end
    function bar:GetLayoutMetrics()
        return metrics
    end
    function bar:Refresh()
        local value = self:GetValue()
        for i = 1, #self.buttons do
            local btn = self.buttons[i]
            local active = btn._msuf2Value == value
            local override = false
            if type(opts.hasOverride) == "function" then override = opts.hasOverride(btn._msuf2Value) and true or false end
            btn._msuf2Override = (not active) and override or false
            btn:SetActive(active)
        end
    end

    if ctx and M.AddRefresher then M.AddRefresher(ctx, function() bar:Refresh() end) end
    bar:Refresh()
    return bar
end

function W.SetControlShown(control, shown)
    if not control then return end
    shown = shown and true or false
    if control.SetShown then control:SetShown(shown) elseif shown then control:Show() else control:Hide() end
    if control._msuf2Title then control._msuf2Title:SetShown(shown) end
    if control._msuf2Label then control._msuf2Label:SetShown(shown) end
    if control._msuf2LabelHit then control._msuf2LabelHit:SetShown(shown) end
    if control.editBox then control.editBox:SetShown(shown) end
    if control._msuf2StepButtons then
        for i = 1, #control._msuf2StepButtons do
            control._msuf2StepButtons[i]:SetShown(shown)
        end
    end
    if shown and control._msuf2SetLayoutWidth then
        control:_msuf2SetLayoutWidth(control._msuf2RowWidth or control._msuf2RequestedWidth)
    end
end

local function SetEnabledState(frame, enabled)
    if not frame then return end
    if frame.Enable and frame.Disable then
        if enabled then frame:Enable() else frame:Disable() end
    elseif frame.SetEnabled then
        frame:SetEnabled(enabled)
    end
    if frame.EnableMouse then frame:EnableMouse(enabled) end
end

local function SetTextEnabledColor(fontString, enabled)
    if not (fontString and fontString.SetTextColor) then return end
    local c = enabled and T.colors.text or T.colors.dim
    fontString:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

local function HasDisableGate(control)
    local gates = control and control._msuf2DisableGates
    if type(gates) ~= "table" then return false end
    for _, disabled in pairs(gates) do
        if disabled then return true end
    end
    return false
end

local function ApplyControlEnabled(control)
    if not control then return end
    local enabled = (control._msuf2DesiredEnabled ~= false) and not HasDisableGate(control)
    if control._msuf2AppliedEnabled == enabled then
        SetEnabledState(control, enabled)
        if control.SetAlpha then control:SetAlpha(enabled and 1 or 0.45) end
        SetTextEnabledColor(control._msuf2Title, enabled)
        SetTextEnabledColor(control._msuf2Label, enabled)
        if control._msuf2RefreshSwitchVisual then control:_msuf2RefreshSwitchVisual() end
        if control._msuf2LabelHit and control._msuf2LabelHit.EnableMouse then
            control._msuf2LabelHit:EnableMouse(enabled)
        end
        local edit = control.editBox or control.__MSUF_valueBox
        if edit then
            SetEnabledState(edit, enabled)
            if edit.SetAlpha then edit:SetAlpha(enabled and 1 or 0.45) end
        end
        if control._msuf2StepButtons then
            for i = 1, #control._msuf2StepButtons do
                local btn = control._msuf2StepButtons[i]
                SetEnabledState(btn, enabled)
                if btn.SetAlpha then btn:SetAlpha(enabled and 1 or 0.45) end
            end
        end
        if control.buttons then
            for i = 1, #control.buttons do
                local btn = control.buttons[i]
                SetEnabledState(btn, enabled)
                if btn.SetAlpha then btn:SetAlpha(enabled and 1 or 0.45) end
            end
        end
        if control._msuf2UpdateFill then control:_msuf2UpdateFill() end
        return
    end
    control._msuf2AppliedEnabled = enabled

    SetEnabledState(control, enabled)
    if control._msuf2ControlKind == "slider" then
        HideSliderTemplateParts(control)
        if T.StyleSlider then T.StyleSlider(control) end
        if control._msuf2UpdateFill then control:_msuf2UpdateFill() end
    end
    if control.SetAlpha then control:SetAlpha(enabled and 1 or 0.45) end
    SetTextEnabledColor(control._msuf2Title, enabled)
    SetTextEnabledColor(control._msuf2Label, enabled)
    if control._msuf2RefreshSwitchVisual then control:_msuf2RefreshSwitchVisual() end

    if control._msuf2LabelHit and control._msuf2LabelHit.EnableMouse then
        control._msuf2LabelHit:EnableMouse(enabled)
    end
    if control._msuf2Chevron and control._msuf2Chevron.SetVertexColor then
        local c = enabled and T.colors.muted or T.colors.dim
        control._msuf2Chevron:SetVertexColor(c[1], c[2], c[3], enabled and 0.95 or 0.55)
    end

    local edit = control.editBox or control.__MSUF_valueBox
    if edit then
        SetEnabledState(edit, enabled)
        if edit.SetAlpha then edit:SetAlpha(enabled and 1 or 0.45) end
    end
    if control._msuf2StepButtons then
        for i = 1, #control._msuf2StepButtons do
            local btn = control._msuf2StepButtons[i]
            SetEnabledState(btn, enabled)
            if btn.SetAlpha then btn:SetAlpha(enabled and 1 or 0.45) end
        end
    end
    if control.buttons then
        for i = 1, #control.buttons do
            local btn = control.buttons[i]
            SetEnabledState(btn, enabled)
            if btn.SetAlpha then btn:SetAlpha(enabled and 1 or 0.45) end
        end
    end
end

-- Shared by all Menu2 pages so disabled dependent options do not drift visually.
function W.SetControlEnabled(control, enabled)
    if not control then return end
    control._msuf2DesiredEnabled = enabled and true or false
    ApplyControlEnabled(control)
end

function W.SetControlGateEnabled(control, gateKey, enabled)
    if not control then return end
    gateKey = tostring(gateKey or "default")
    control._msuf2DisableGates = control._msuf2DisableGates or {}
    control._msuf2DisableGates[gateKey] = not (enabled and true or false)
    if control._msuf2DesiredEnabled == nil then
        local current = true
        if control.IsEnabled then current = control:IsEnabled() and true or false end
        control._msuf2DesiredEnabled = current
    end
    ApplyControlEnabled(control)
end

function W.SetControlsEnabled(controls, enabled)
    for i = 1, #(controls or {}) do
        W.SetControlEnabled(controls[i], enabled)
    end
end

function W.SetControlsGateEnabled(controls, gateKey, enabled)
    for i = 1, #(controls or {}) do
        W.SetControlGateEnabled(controls[i], gateKey, enabled)
    end
end

local function ClampPlacedControlWidth(widget, parent, x)
    if not (widget and parent and parent._msuf2Width) then return end
    local kind = widget._msuf2ControlKind
    if kind ~= "slider" and kind ~= "dropdown" and kind ~= "textinput" then return end

    local available = floor((parent._msuf2Width or 0) - (x or 0) - 18)
    if available <= 0 then return end

    if kind == "slider" and widget._msuf2SetLayoutWidth then
        local requested = widget._msuf2RequestedWidth or widget._msuf2RowWidth or 280
        local minWidth = widget._msuf2MinRowWidth or 48
        widget:_msuf2SetLayoutWidth(max(minWidth, min(requested, available)))
        return
    end

    local currentW = widget.GetWidth and widget:GetWidth()
    if currentW and currentW > available then
        widget:SetWidth(max(72, available))
        if widget._msuf2Title and widget._msuf2Title.SetWidth then
            widget._msuf2Title:SetWidth(max(72, available))
        end
    end
end

function W.MoveWidget(widget, parent, x, y, width, titleJustify)
    if not (widget and widget.ClearAllPoints) then return widget end
    parent = parent or widget:GetParent()
    x = x or 0
    y = y or 0

    local kind = widget._msuf2ControlKind
    width = tonumber(width)
    if width then
        if kind == "slider" and widget._msuf2SetLayoutWidth then
            widget._msuf2RequestedWidth = width
            widget:_msuf2SetLayoutWidth(width)
        elseif kind == "dropdown" or kind == "textinput" or kind == "segment" then
            widget:SetSize(width, widget:GetHeight() or 22)
            if widget._msuf2Title and widget._msuf2Title.SetWidth then widget._msuf2Title:SetWidth(width) end
        end
    end
    if titleJustify and widget._msuf2Title and widget._msuf2Title.SetJustifyH then
        widget._msuf2TitleJustify = titleJustify
        widget._msuf2Title:SetJustifyH(titleJustify)
    end

    ClampPlacedControlWidth(widget, parent, x)
    if widget._msuf2Title then
        widget._msuf2Title:ClearAllPoints()
        widget._msuf2Title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end

    widget:ClearAllPoints()
    if kind == "slider" or kind == "dropdown" or kind == "textinput" or kind == "segment" then
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 22)
    elseif kind == "color" then
        if widget._msuf2Title then widget._msuf2Title:SetWidth(100) end
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 108, y + 2)
    else
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end
    return widget
end

function W.LabelAt(parent, text, x, y, width, template, color)
    local fs = T.Font(parent, template or "GameFontNormalSmall", Tr(text or ""), color or T.colors.text)
    SetSearchText(fs, text)
    RegisterSearchObject(fs, text, "text")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
    fs:SetWidth(width or 180)
    fs:SetJustifyH("LEFT")
    return fs
end

function W.DividerAt(parent, y, leftPad, rightPad)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", leftPad or 12, y or 0)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(rightPad or 12), y or 0)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.06)
    return line
end

function W.Button(section, label, width)
    local x, y = NextRow(section, 30)
    local btn = T.Button(section, Tr(label or ""), width or 160, 24)
    btn._msuf2ControlKind = "button"
    RegisterSearchObject(btn, label, "button")
    btn:SetPoint("TOPLEFT", x, y)
    return btn
end

local function InstallPinnedPreviewUpdater(scroll)
    if not scroll or scroll._msuf2PinnedPreviewUpdater then return end
    scroll._msuf2PinnedPreviewUpdater = true
    scroll:HookScript("OnUpdate", function(self, elapsed)
        self._msuf2PinnedPreviewElapsed = (self._msuf2PinnedPreviewElapsed or 0) + (elapsed or 0)
        if self._msuf2PinnedPreviewElapsed < 0.04 then return end
        self._msuf2PinnedPreviewElapsed = 0
        local offset = (self.GetVerticalScroll and self:GetVerticalScroll()) or 0
        local h = (self.GetHeight and self:GetHeight()) or 0
        if offset == self._msuf2PinnedPreviewLastOffset and h == self._msuf2PinnedPreviewLastHeight then return end
        self._msuf2PinnedPreviewLastOffset = offset
        self._msuf2PinnedPreviewLastHeight = h
        if M.RefreshPinnedPreviews then M.RefreshPinnedPreviews(self) end
    end)
    scroll:HookScript("OnShow", function(self)
        if M.RefreshPinnedPreviews then M.RefreshPinnedPreviews(self) end
    end)
    scroll:HookScript("OnSizeChanged", function(self)
        if M.RefreshPinnedPreviews then M.RefreshPinnedPreviews(self) end
    end)
end

function M.RefreshPinnedPreviews(scroll)
    local list = M._pinnedPreviews
    if not list then return end
    for i = 1, #list do
        local r = list[i]
        if r and r.update and (not scroll or r.scroll == scroll) then r.update() end
    end
end

function W.AttachPinnedPreview(body, box, opts)
    if not (body and box) then return nil end
    opts = opts or {}
    local scroll = M.scrollFrame
    if not scroll then return nil end

    if type(M.GetPersistentMenuStateTable) == "function" then
        M.previewPinState = M.GetPersistentMenuStateTable("previewPinState")
    else
        M.previewPinState = M.previewPinState or {}
    end
    local stateKey = tostring(opts.stateKey or box._msuf2PinStateKey or "preview")
    local originalParent = box:GetParent()
    local point, relTo, relPoint, xOfs, yOfs = box:GetPoint(1)
    local scrollParent = scroll:GetParent()
    local originalFrameLevel = (box.GetFrameLevel and box:GetFrameLevel()) or 1
    local pinned = false
    local record

    local pinBtn = T.Button(box, Tr("Pinned"), opts.buttonWidth or 86, 22)
    pinBtn:SetPoint("TOPRIGHT", box, "TOPRIGHT", -10, -6)
    pinBtn._msuf2SearchText = "Pin Preview"
    pinBtn._msuf2ControlKind = "button"
    RegisterSearchObject(pinBtn, "Pin Preview", "button")

    local hint = opts.hint or box.hint or box._hint
    if hint and hint.SetPoint then
        hint:ClearAllPoints()
        hint:SetPoint("LEFT", opts.title or box.title or box._title, "RIGHT", 12, 0)
        hint:SetPoint("RIGHT", pinBtn, "LEFT", -10, 0)
        hint:SetJustifyH("LEFT")
    end

    local placeholder = body.CreateFontString and body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") or nil
    if placeholder then
        placeholder:SetPoint("CENTER", body, "CENTER", 0, 0)
        placeholder:SetText(Tr("\226\134\145 Preview pinned at top"))
        placeholder:SetTextColor(0.38, 0.44, 0.58, 0.55)
        placeholder:Hide()
    end

    local function PinEnabled()
        return M.previewPinState[stateKey] ~= false
    end

    local function RefreshButton()
        local enabled = PinEnabled()
        pinBtn:SetText(enabled and "Pinned" or "Pin Preview")
        if pinBtn.SetActive then pinBtn:SetActive(enabled) end
    end

    local function Restore()
        if not pinned then return end
        pinned = false
        box._msuf2PinnedFloating = nil
        if placeholder then placeholder:Hide() end
        if scroll._msuf2PinnedPreviewActiveRecord == record then
            scroll._msuf2PinnedPreviewActiveRecord = nil
        end
        box:SetParent(originalParent)
        box:ClearAllPoints()
        box:SetPoint(point or "TOPLEFT", relTo or body, relPoint or "TOPLEFT", xOfs or 0, yOfs or 0)
        if box.SetFrameLevel then box:SetFrameLevel(originalFrameLevel) end
    end

    local function BodyVisible()
        -- IsVisible checks the full ancestor chain; IsShown only checks the frame itself
        return (not body.IsVisible or body:IsVisible())
            and (not scroll.IsShown or scroll:IsShown())
    end

    local function ShouldPin()
        if not PinEnabled() or not BodyVisible() then return false end
        local offset = (scroll.GetVerticalScroll and scroll:GetVerticalScroll()) or 0
        local activateAt = opts.activateAfter or 64
        if offset <= (pinned and math.floor(activateAt * 0.45) or activateAt) then return false end
        local scrollTop = scroll.GetTop and scroll:GetTop()
        local bodyTop = body.GetTop and body:GetTop()
        if not (scrollTop and bodyTop) then return false end
        if bodyTop <= (scrollTop + (opts.threshold or 6)) then return false end
        return true
    end

    local function ApplyPinnedState()
        if ShouldPin() then
            local active = scroll._msuf2PinnedPreviewActiveRecord
            if active and active ~= record and active.restore then active.restore() end
            if not pinned then
                pinned = true
                box._msuf2PinnedFloating = true
                scroll._msuf2PinnedPreviewActiveRecord = record
                -- Float as a pure overlay — scroll frame is never moved
                local level = ((scrollParent and scrollParent.GetFrameLevel and scrollParent:GetFrameLevel()) or 1)
                    + (opts.frameLevelOffset or 80)
                box:SetParent(scrollParent or scroll)
                box:ClearAllPoints()
                box:SetPoint("TOPLEFT", scroll, "TOPLEFT", opts.left or 14, opts.top or -8)
                box:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -(opts.right or 14), opts.top or -8)
                if box.SetFrameLevel then box:SetFrameLevel(level) end
                if placeholder then placeholder:Show() end
            end
        else
            Restore()
        end
        RefreshButton()
    end

    pinBtn:SetScript("OnClick", function()
        M.previewPinState[stateKey] = not PinEnabled()
        if not PinEnabled() then
            pinned = true  -- force Restore() to run fully even if state drifted
            Restore()
        end
        ApplyPinnedState()
    end)
    pinBtn:SetScript("OnEnter", function(self)
        self._msuf2Hover = true
        if self.RefreshVisual then self:RefreshVisual() end
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(Tr("Pin Preview"), 1, 1, 1)
            GameTooltip:AddLine(Tr("Keeps this preview visible while you edit lower options."), 0.82, 0.82, 0.82, true)
            GameTooltip:Show()
        end
    end)
    pinBtn:SetScript("OnLeave", function(self)
        self._msuf2Hover = nil
        if self.RefreshVisual then self:RefreshVisual() end
        if GameTooltip then GameTooltip:Hide() end
    end)

    record = { scroll = scroll, update = ApplyPinnedState, restore = Restore, box = box, stateKey = stateKey }
    M._pinnedPreviews = M._pinnedPreviews or {}
    for i = #M._pinnedPreviews, 1, -1 do
        local r = M._pinnedPreviews[i]
        if r and r.box == box then  -- same box = this exact page was rebuilt, replace its record
            if r.restore then r.restore() end
            table.remove(M._pinnedPreviews, i)
        end
    end
    M._pinnedPreviews[#M._pinnedPreviews + 1] = record
    InstallPinnedPreviewUpdater(scroll)

    if body.HookScript then
        body:HookScript("OnShow", ApplyPinnedState)
        body:HookScript("OnHide", Restore)
    end
    if box.HookScript then
        box:HookScript("OnHide", Restore)
        box:HookScript("OnSizeChanged", ApplyPinnedState)
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, ApplyPinnedState) end
    RefreshButton()
    return record
end

function W.Slider(section, label, minVal, maxVal, step, width)
    local x, y = NextRow(section, 48)
    local valueGap = 8
    local buttonGap = 2
    local stepButtonW = 18
    local editW = 52
    local minTrackW = 96
    local compactMinTrackW = 48
    local sliderH = 22
    local valueClusterW = valueGap + stepButtonW + buttonGap + editW + buttonGap + stepButtonW
    local compactValueClusterW = valueGap + editW
    width = width or 280
    if section and section._msuf2Width then
        local available = section._msuf2Width - x - 14
        if available > 0 and width > available then width = max(72, available) end
    end
    local title = T.Font(section, "GameFontHighlightSmall", Tr(label or ""), T.colors.text)
    SetSearchText(title, label)
    title:SetPoint("TOPLEFT", x, y)
    title:SetWidth(width)
    title:SetJustifyH("LEFT")

    sliderSerial = sliderSerial + 1
    local slider = CreateFrame("Slider", "MSUF2NativeSlider" .. sliderSerial, section)
    slider._msuf2Title = title
    slider._msuf2ControlKind = "slider"
    RegisterSearchObject(slider, label, "slider", { anchor = title })
    slider:SetPoint("TOPLEFT", x, y - 22)
    slider:SetSize(max(compactMinTrackW, width - valueClusterW), sliderH)
    if slider.EnableMouse then slider:EnableMouse(true) end
    slider:SetMinMaxValues(minVal or 0, maxVal or 1)
    slider:SetValueStep(step or 1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    if slider.SetStepsPerPage then slider:SetStepsPerPage(1) end
    slider._msuf2Step = step or 1
    slider._msuf2RequestedWidth = width
    slider._msuf2MinRowWidth = compactMinTrackW
    HideSliderTemplateParts(slider)
    if T.StyleSlider then T.StyleSlider(slider) end

    local function StepButton(text)
        local btn = T.Button(section, text, 18, 20)
        SetSearchText(btn, text)
        btn._msuf2Label:ClearAllPoints()
        btn._msuf2Label:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btn._msuf2Label:SetJustifyH("CENTER")
        return btn
    end

    local minus = StepButton("-")

    local edit = CreateFrame("EditBox", nil, section, "InputBoxTemplate")
    edit:SetSize(52, 20)
    edit:SetAutoFocus(false)
    edit:SetJustifyH("CENTER")
    edit:SetNumeric(false)
    T.SkinEditBox(edit)
    slider.editBox = edit

    local plus = StepButton("+")
    slider.minusButton = minus
    slider.plusButton = plus
    slider._msuf2StepButtons = { minus, plus }

    local function UpdateFill()
        local fill = slider._msufFill
        if not fill then return end
        local minV, maxV = slider:GetMinMaxValues()
        local span = maxV - minV
        local pct = span > 0 and ((slider:GetValue() - minV) / span) or 0
        if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
        fill:SetWidth(max(1, max(1, slider:GetWidth() - 2) * pct))
    end
    slider._msuf2UpdateFill = UpdateFill

    function slider:_msuf2SetLayoutWidth(totalWidth)
        totalWidth = tonumber(totalWidth) or width or 280
        self._msuf2RowWidth = totalWidth
        local tiny = totalWidth < (compactMinTrackW + compactValueClusterW)
        local compact = tiny or totalWidth < (minTrackW + valueClusterW)
        local clusterW = tiny and 0 or (compact and compactValueClusterW or valueClusterW)
        local trackMin = compact and compactMinTrackW or minTrackW
        local trackW = max(trackMin, floor(totalWidth - clusterW + 0.5))
        if title then
            title:SetWidth(max(trackW, floor(totalWidth + 0.5)))
            if title.SetJustifyH then title:SetJustifyH(self._msuf2TitleJustify or "LEFT") end
        end
        self:SetSize(trackW, sliderH)
        minus:ClearAllPoints()
        if compact then
            minus:Hide()
        else
            minus:Show()
            minus:SetPoint("LEFT", self, "RIGHT", valueGap, 0)
        end
        edit:ClearAllPoints()
        if tiny then
            edit:Hide()
        else
            edit:Show()
            edit:SetPoint("LEFT", compact and self or minus, "RIGHT", compact and valueGap or buttonGap, 0)
        end
        plus:ClearAllPoints()
        if compact then
            plus:Hide()
        else
            plus:Show()
            plus:SetPoint("LEFT", edit, "RIGHT", buttonGap, 0)
        end
        UpdateFill()
    end
    slider:_msuf2SetLayoutWidth(width)

    local function FormatValue(value)
        if type(slider._msuf2ValueFormatter) == "function" then
            local ok, text = pcall(slider._msuf2ValueFormatter, value, slider)
            if ok and text ~= nil then return tostring(text) end
        end
        local st = step or 1
        if st < 1 then
            return string.format("%.2f", value)
        end
        return tostring(floor(value + 0.5))
    end
    slider._msuf2FormatValue = FormatValue
    function slider:SetValueFormatter(fn)
        self._msuf2ValueFormatter = (type(fn) == "function") and fn or nil
        if not self._msuf2Editing then edit:SetText(FormatValue(self:GetValue())) end
    end

    slider:HookScript("OnValueChanged", function(self, value)
        UpdateFill()
        if not self._msuf2Editing then
            edit:SetText(FormatValue(value))
        end
    end)
    slider:HookScript("OnShow", function(self)
        HideSliderTemplateParts(self)
        if T.StyleSlider then T.StyleSlider(self) end
        if self._msuf2SetLayoutWidth then
            self:_msuf2SetLayoutWidth(self._msuf2RowWidth or width)
        else
            UpdateFill()
        end
    end)
    edit:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v ~= nil then slider:SetValue(v) end
        self:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:SetText(FormatValue(slider:GetValue()))
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusGained", function() slider._msuf2Editing = true end)
    edit:SetScript("OnEditFocusLost", function(self)
        slider._msuf2Editing = nil
        self:SetText(FormatValue(slider:GetValue()))
    end)

    local function ClampToSlider(value)
        local minV, maxV = slider:GetMinMaxValues()
        if value < minV then value = minV elseif value > maxV then value = maxV end
        local st = tonumber(slider._msuf2Step) or 1
        if st > 0 then value = floor((value / st) + 0.5) * st end
        if value < minV then value = minV elseif value > maxV then value = maxV end
        return value
    end

    local function StepMultiplier()
        if IsControlKeyDown and IsControlKeyDown() then return 10 end
        if IsShiftKeyDown and IsShiftKeyDown() then return 5 end
        return 1
    end

    local function StepBy(direction)
        if slider.IsEnabled and not slider:IsEnabled() then return end
        local amount = (tonumber(slider._msuf2Step) or 1) * StepMultiplier() * direction
        slider:SetValue(ClampToSlider((tonumber(slider:GetValue()) or 0) + amount))
    end

    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(_, delta)
        if not delta or delta == 0 then return end
        StepBy(delta > 0 and 1 or -1)
    end)

    minus:SetScript("OnClick", function() StepBy(-1) end)
    plus:SetScript("OnClick", function() StepBy(1) end)

    return slider
end

function W.Segment(section, label, values, width)
    local x, y = NextRow(section, 48)
    local title = T.Font(section, "GameFontHighlightSmall", label or "", T.colors.text)
    SetSearchText(title, label)
    title:SetPoint("TOPLEFT", x, y)

    local holder = CreateFrame("Frame", nil, section)
    RegisterSearchObject(holder, label, "segment", { anchor = title, values = values })
    holder:SetPoint("TOPLEFT", x, y - 22)
    holder:SetSize(width or 360, 22)
    holder._msuf2ControlKind = "segment"
    holder._msuf2Title = title
    holder.buttons = {}
    holder.values = values or {}

    local count = #holder.values
    local gap = 6
    local bw = count > 0 and math.floor(((width or 360) - gap * (count - 1)) / count) or 80
    for i = 1, count do
        local item = holder.values[i]
        local btn = T.Button(holder, item.text or tostring(item.value), bw, 22)
        RegisterSearchObject(btn, item.text or item.label or item.value or "", "button")
        btn:SetPoint("LEFT", holder, "LEFT", (i - 1) * (bw + gap), 0)
        btn._msuf2Value = item.value
        holder.buttons[i] = btn
    end

    function holder:SetValue(value)
        self.value = value
        for i = 1, #self.buttons do
            local btn = self.buttons[i]
            btn:SetActive(btn._msuf2Value == value)
        end
    end
    function holder:GetValue()
        return self.value
    end
    return holder
end

function W.StatCard(parent, label, value, x, y, width)
    local card = T.Panel(parent, nil, T.colors.panel2, T.colors.borderSoft)
    SetSearchTitle(card, label)
    RegisterSearchObject(card, label, "text", { values = { value } })
    card:SetPoint("TOPLEFT", x or 0, y or 0)
    card:SetSize(width or 170, 56)
    local l = T.Font(card, "GameFontDisableSmall", Tr(label or ""), T.colors.muted)
    SetSearchText(l, label)
    l:SetPoint("TOPLEFT", 12, -10)
    local v = T.Font(card, "GameFontNormal", Tr(value or ""), T.colors.text)
    SetSearchText(v, value)
    v:SetPoint("TOPLEFT", 12, -30)
    card.valueText = v
    return card
end

function W.Divider(parent, x, y, width)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", x or 0, y or 0)
    line:SetSize(width or 400, 1)
    line:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.70)
    return line
end

function W.TextInput(section, label, width)
    local x, y = NextRow(section, 50)
    width = width or 260
    local title = T.Font(section, "GameFontHighlightSmall", Tr(label or ""), T.colors.text)
    SetSearchText(title, label)
    title:SetPoint("TOPLEFT", x, y)

    local edit = CreateFrame("EditBox", nil, section, "InputBoxTemplate")
    edit._msuf2Title = title
    edit._msuf2ControlKind = "textinput"
    RegisterSearchObject(edit, label, "textinput", { anchor = title })
    edit:SetPoint("TOPLEFT", x, y - 22)
    edit:SetSize(width, 22)
    edit:SetAutoFocus(false)
    edit:SetJustifyH("LEFT")
    edit:SetMaxLetters(200000)
    T.SkinEditBox(edit)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    function edit:SetOnValueCommitted(fn)
        self._msuf2OnCommit = fn
    end
    edit:SetScript("OnEnterPressed", function(self)
        if self._msuf2OnCommit then self._msuf2OnCommit(self:GetText() or "") end
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        if self._msuf2CommitOnBlur and self._msuf2OnCommit then
            self._msuf2OnCommit(self:GetText() or "")
        end
    end)
    return edit
end

function W.Color(section, label)
    local x, y = NextRow(section, 34)
    local title = T.Font(section, "GameFontHighlightSmall", Tr(label or ""), T.colors.text)
    SetSearchText(title, label)
    title:SetPoint("TOPLEFT", x, y)
    title:SetWidth(230)

    local btn = CreateFrame("Button", nil, section)
    btn._msuf2Title = title
    btn._msuf2ControlKind = "color"
    RegisterSearchObject(btn, label, "color", { anchor = title })
    btn:SetPoint("TOPLEFT", x + 250, y + 2)
    btn:SetSize(44, 18)
    btn._msuf2Swatch, btn._msuf2Edge = T.CreateSuperellipseLayers(btn, "_msuf2Color", 1, "ARTWORK", "ARTWORK")
    btn._msuf2Edge:SetVertexColor(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.75)

    function btn:SetRGB(r, g, b)
        self._msuf2R = tonumber(r) or 1
        self._msuf2G = tonumber(g) or 1
        self._msuf2B = tonumber(b) or 1
        self._msuf2Swatch:SetVertexColor(self._msuf2R, self._msuf2G, self._msuf2B, 1)
    end
    function btn:GetRGB()
        return self._msuf2R or 1, self._msuf2G or 1, self._msuf2B or 1
    end
    function btn:SetOnColorChanged(fn)
        self._msuf2OnColorChanged = fn
    end
    btn:SetRGB(1, 1, 1)
    btn:SetScript("OnClick", function(self)
        if not ColorPickerFrame then return end
        local r, g, b = self:GetRGB()
        local function Commit()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            self:SetRGB(nr, ng, nb)
            if self._msuf2OnColorChanged then self._msuf2OnColorChanged(nr, ng, nb) end
        end
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = r, g = g, b = b, opacity = 1, hasOpacity = false,
                swatchFunc = Commit,
                cancelFunc = function(prev)
                    if type(prev) == "table" then
                        local pr, pg, pb = prev.r or r, prev.g or g, prev.b or b
                        self:SetRGB(pr, pg, pb)
                        if self._msuf2OnColorChanged then self._msuf2OnColorChanged(pr, pg, pb) end
                    end
                end,
                previousValues = { r = r, g = g, b = b, opacity = 1 },
            })
        else
            ColorPickerFrame.func = Commit
            ColorPickerFrame.cancelFunc = function()
                self:SetRGB(r, g, b)
                if self._msuf2OnColorChanged then self._msuf2OnColorChanged(r, g, b) end
            end
            ColorPickerFrame:SetColorRGB(r, g, b)
            ColorPickerFrame:Show()
        end
    end)
    return btn
end
