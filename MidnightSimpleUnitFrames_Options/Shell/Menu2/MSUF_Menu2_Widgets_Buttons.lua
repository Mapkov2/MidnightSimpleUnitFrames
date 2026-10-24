--- Shell/Menu2/MSUF_Menu2_Widgets_Buttons.lua
--- Top-bar and role buttons (W.TopButton, W.RoleButton) and the badges a
--- collapsible section header shows (W.SetCollapsibleBadges, the Custom badge).
---
--- Split from MSUF_Menu2_Widgets.lua; loads after the page builder.

local _, MSUF = ...
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Shell/Menu2/MSUF_Menu2_Widgets_Buttons.lua")
local M = MSUF.MSUF2
local T = M.Theme
local W = M.Widgets
local Shared = W._Shared
local floor, max, min = math.floor, math.max, math.min
local Tr = M.TranslateText
local ThemeColor = Shared.ThemeColor
local WithAlpha = Shared.WithAlpha

local function TopButtonStyle(bg, border, textColor, hoverBg, hoverBorder)
    return {
        bg = bg, border = border, textColor = textColor,
        hoverBg = hoverBg, hoverBorder = hoverBorder,
        activeBg = bg, activeBorder = border, activeTextColor = textColor,
    }
end
local TOP_ACTION_BUTTON_STYLE = TopButtonStyle(
    { 0.006, 0.016, 0.032, 0.82 },
    { 0.043, 0.096, 0.150, 0.46 },
    { 0.82, 0.90, 1.00, 0.96 },
    { 0.014, 0.038, 0.072, 0.86 },
    { 0.060, 0.250, 0.390, 0.42 })
local TOP_DANGER_BUTTON_STYLE = TopButtonStyle({ 0.070, 0.026, 0.034, 0.94 }, { 0.340, 0.090, 0.110, 0.82 }, { 1.00, 0.82, 0.82, 1 },
    { 0.090, 0.035, 0.045, 0.96 }, { 0.420, 0.120, 0.140, 0.90 })
local TOP_SUCCESS_BUTTON_STYLE = TopButtonStyle({ 0.018, 0.145, 0.090, 0.94 }, { 0.055, 0.440, 0.270, 0.82 }, { 0.780, 1.000, 0.875, 1 },
    { 0.026, 0.185, 0.115, 0.96 }, { 0.075, 0.560, 0.345, 0.90 })
local TOP_ROLE_STYLES = { primary = TOP_ACTION_BUTTON_STYLE, destructive = TOP_DANGER_BUTTON_STYLE, danger = TOP_DANGER_BUTTON_STYLE,
    reset = TOP_DANGER_BUTTON_STYLE, delete = TOP_DANGER_BUTTON_STYLE, success = TOP_SUCCESS_BUTTON_STYLE, confirm = TOP_SUCCESS_BUTTON_STYLE }
-- Options may load before PLAYER_LOGIN, while the saved Menu2 accent is applied
-- at PLAYER_LOGIN. Do not retain the Midnight copies created during file load:
-- resolve the live token tables whenever a top button is constructed. Mutating
-- this shared style also keeps custom styles' missing-field fallbacks current.
local function RefreshTopActionButtonStyle()
    local style = TOP_ACTION_BUTTON_STYLE
    style.bg = WithAlpha(ThemeColor("coreShadow", { 0.006, 0.016, 0.032, 1.00 }), 0.82)
    style.border = WithAlpha(ThemeColor("coreRim", { 0.043, 0.096, 0.150, 1.00 }), 0.46)
    style.textColor = WithAlpha(ThemeColor("pillText", { 0.82, 0.90, 1.00, 1.00 }), 0.96)
    style.hoverBg = WithAlpha(ThemeColor("coreSurface", { 0.014, 0.038, 0.072, 1.00 }), 0.86)
    style.hoverBorder = WithAlpha(ThemeColor("coreBlue", { 0.060, 0.250, 0.390, 1.00 }), 0.42)
    style.activeBg = style.bg
    style.activeBorder = style.border
    style.activeTextColor = style.textColor
    return style
end
local ApplyTopActionButtonVisual
local function RepaintTopButton(btn, _, hover) ApplyTopActionButtonVisual(btn, hover) end
ApplyTopActionButtonVisual = function(btn, hover)
    if MSUF.MenuSkin and MSUF.MenuSkin.Button(btn, btn._msuf2TopActive, hover, RepaintTopButton) then return end
    local surfaceActive = btn._msuf2TopActive and not btn._msuf2SelectionMotion
    local bg = surfaceActive and btn._msuf2TopActiveBg or (hover and btn._msuf2TopHoverBg or btn._msuf2TopBg)
    local br = surfaceActive and btn._msuf2TopActiveBorder or (hover and btn._msuf2TopHoverBorder or btn._msuf2TopBorder)
    local tx = btn._msuf2TopActive and btn._msuf2TopActiveText or btn._msuf2TopText
    local mul = hover and 1.03 or 1
    if btn._msuf2Fill then
        local fill = { min(bg[1] * mul, 1), min(bg[2] * mul, 1), min(bg[3] * mul, 1), bg[4] or 1 }
        if T.SetFillGradient then T.SetFillGradient(btn._msuf2Fill, fill, 0.07, -0.26) else btn._msuf2Fill:SetVertexColor(fill[1],
            fill[2], fill[3], fill[4]) end
    end
    if btn._msuf2Edge then btn._msuf2Edge:SetVertexColor(min(br[1] * mul, 1), min(br[2] * mul, 1), min(br[3] * mul, 1), br[4] or 1) end
    if btn._msuf2Label then btn._msuf2Label:SetTextColor(tx[1], tx[2], tx[3], tx[4] or 1) end
    if btn._msuf2TopStripe then btn._msuf2TopStripe:SetShown(btn._msuf2TopActive and not btn._msuf2SelectionMotion) end
end
local TOP_BUTTON_HOOKS = { OnEnter = function(self) ApplyTopActionButtonVisual(self, true) end, OnLeave = function(self) ApplyTopActionButtonVisual(self) end,
    OnEnable = function(self) ApplyTopActionButtonVisual(self) end, OnDisable = function(self) ApplyTopActionButtonVisual(self) end }
local function StyleTopButton(btn, style)
    local defaults = RefreshTopActionButtonStyle()
    local s = style or defaults
    btn._msuf2TopActive = false
    btn._msuf2TopBg = s.bg or defaults.bg
    btn._msuf2TopBorder = s.border or defaults.border
    btn._msuf2TopText = s.textColor or defaults.textColor
    btn._msuf2TopHoverBg = s.hoverBg or s.bg or defaults.hoverBg or defaults.bg
    btn._msuf2TopHoverBorder = s.hoverBorder or s.border or defaults.hoverBorder or defaults.border
    btn._msuf2TopActiveBg = s.activeBg or s.bg or defaults.activeBg or defaults.bg
    btn._msuf2TopActiveBorder = s.activeBorder or s.border or defaults.activeBorder or defaults.border
    btn._msuf2TopActiveText = s.activeTextColor or s.textColor or defaults.activeTextColor or defaults.textColor
    if btn._msuf2Label then
        T.CenterButtonLabel(btn)
        if btn._msuf2Label.SetShadowColor then btn._msuf2Label:SetShadowColor(0, 0, 0, 0.55) end
        if btn._msuf2Label.SetShadowOffset then btn._msuf2Label:SetShadowOffset(1, -1) end
    end
    if s.stripe == true and not btn._msuf2TopStripe then
        local stripe = PixelLayoutRegion(btn:CreateTexture(nil, "ARTWORK", nil, 6))
        local c = s.stripeColor or ThemeColor("coreBlue", { 0.060, 0.250, 0.390, 1.00 })
        stripe:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        stripe:SetWidth(s.stripeWidth or 3)
        stripe:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -5)
        stripe:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 2, 5)
        stripe:Hide()
        btn._msuf2TopStripe = stripe
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
    for script, handler in pairs(TOP_BUTTON_HOOKS) do btn:SetScript(script, handler) end
    ApplyTopActionButtonVisual(btn)
    return btn
end
M.Assign(W, {
    StyleTopActionButton = function(btn) return StyleTopButton(btn, TOP_ACTION_BUTTON_STYLE) end,
    StyleTopDangerButton = function(btn) return StyleTopButton(btn, TOP_DANGER_BUTTON_STYLE) end,
    StyleTopSuccessButton = function(btn) return StyleTopButton(btn, TOP_SUCCESS_BUTTON_STYLE) end,
})
function W.RoleButton(parent, label, role, width, height)
    local btn = (T.RoleButton and T.RoleButton(parent, label, role, width, height)) or T.Button(parent, label, width, height)
    role = tostring(role or "normal")
    return StyleTopButton(btn, TOP_ROLE_STYLES[role] or TOP_ACTION_BUTTON_STYLE)
end
function W.TopButton(parent, label, width, height, style, active)
    local btn = StyleTopButton(T.Button(parent, label, width, height), style)
    if active ~= nil and btn.SetActive then btn:SetActive(active) end
    return btn
end
function W.GlobalStyleHeader(ctx, builder, title, subtitle, height)
    return nil, nil
end
local COLLAPSIBLE_BADGE_STYLES = {
    ok = {
        bg = { 0.018, 0.230, 0.145, 0.94 },
        border = { 0.050, 0.690, 0.430, 0.88 },
        text = { 0.640, 1.000, 0.820, 1 },
    },
    info = {
        bg = WithAlpha(ThemeColor("coreSurface", { 0.014, 0.038, 0.072, 1.00 }), 0.92),
        border = WithAlpha(ThemeColor("coreRim", { 0.043, 0.096, 0.150, 1.00 }), 0.78),
        text = { 0.760, 0.840, 1.000, 1 },
    },
    accent = {
        bg = WithAlpha(ThemeColor("coreRaised", { 0.026, 0.070, 0.110, 1.00 }), 0.94),
        border = WithAlpha(ThemeColor("coreBlue", { 0.060, 0.250, 0.390, 1.00 }), 0.72),
        text = { 0.680, 0.920, 1.000, 1 },
    },
    muted = {
        bg = WithAlpha(ThemeColor("coreShadow", { 0.006, 0.016, 0.032, 1.00 }), 0.90),
        border = WithAlpha(ThemeColor("coreRim", { 0.043, 0.096, 0.150, 1.00 }), 0.72),
        text = { 0.680, 0.730, 0.860, 1 },
    },
}
-- Measures the translated text the badge shows.
local function CollapsibleBadgeWidth(text)
    text = tostring(text or "")
    return max(48, min(176, floor(22 + (#text * 6.2) + 0.5)))
end
-- The badge styles copy token colors at file load, before the menu accent
-- override runs; re-sync the accent border from the live token and pull the
-- remaining copies through the accent re-hue on first use.
local badgeStylesRehued
local function RefreshBadgeAccentBorder()
    local live = ThemeColor("coreBlue", nil)
    local accentBorder = COLLAPSIBLE_BADGE_STYLES.accent and COLLAPSIBLE_BADGE_STYLES.accent.border
    if live and accentBorder then
        accentBorder[1], accentBorder[2], accentBorder[3] = live[1], live[2], live[3]
    end
    if not badgeStylesRehued and T.MenuAccentRehueLiteral then
        badgeStylesRehued = true
        for _, style in pairs(COLLAPSIBLE_BADGE_STYLES) do
            T.MenuAccentRehueLiteral(style.bg)
            T.MenuAccentRehueLiteral(style.text)
            if style.border ~= accentBorder then T.MenuAccentRehueLiteral(style.border) end
        end
    end
end
-- Frame, rounded layers and centered text of one header badge.
local function NewHeaderBadge(header, width, text)
    local badge = PixelLayoutRegion(CreateFrame("Frame", nil, header))
    badge:SetFrameLevel((header.GetFrameLevel and header:GetFrameLevel() or 1) + 2)
    badge:SetSize(width, 20)
    local fill, edge = T.CreateSuperellipseLayers(badge, "_msuf2HeaderBadge", 1, "ARTWORK", "OVERLAY")
    badge.text = T.Font(badge, "GameFontDisableSmall", text, T.colors.text)
    badge.text:SetPoint("CENTER", badge, "CENTER", 0, 0)
    return badge, fill, edge
end
local function PaintBadgeLayers(fill, edge, style)
    if fill then
        local c = style.bg
        if T.SetFillGradient then T.SetFillGradient(fill, c, 0.12, -0.18)
        else fill:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
    end
    if edge then
        local c = style.border
        edge:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    end
end
function W.SetCollapsibleBadges(section, specs)
    RefreshBadgeAccentBorder()
    local entry = section and section._msuf2CollapsibleEntry
    local header = entry and entry.header
    if not header then return end
    entry._msuf2Badges = entry._msuf2Badges or {}
    specs = specs or {}
    local showAllWhenClosed = section._msuf2CollapsibleBadgesShowWhenClosed == true
        or entry._msuf2CollapsibleBadgesShowWhenClosed == true
        or section._msuf2CollapsibleBadgesOnlyWhenOpen == false
        or entry._msuf2CollapsibleBadgesOnlyWhenOpen == false
    local badgesOpen = entry.open == true and entry._msuf2Closing ~= true
    local changed = false
    for i = 1, #specs do
        local spec = specs[i] or {}
        local badge = entry._msuf2Badges[i]
        if not badge then
            local fill, edge
            badge, fill, edge = NewHeaderBadge(header, 54, "")
            badge._msuf2Fill = fill
            badge._msuf2Edge = edge
            badge.text:SetJustifyH("CENTER")
            entry._msuf2Badges[i] = badge
        end
        local text = Tr(spec.text or "")
        local style = COLLAPSIBLE_BADGE_STYLES[spec.kind or spec.style or "info"] or COLLAPSIBLE_BADGE_STYLES.info
        local width = tonumber(spec.width) or CollapsibleBadgeWidth(text)
        local height = tonumber(spec.height) or 20
        -- Page refreshers call this on every refresh; an unchanged badge
        -- writes nothing and the header keeps its layout.
        if badge._msuf2BadgeText ~= text or badge._msuf2BadgeStyle ~= style
            or badge._msuf2BadgeW ~= width or badge._msuf2BadgeH ~= height
        then
            badge._msuf2BadgeText, badge._msuf2BadgeStyle = text, style
            badge._msuf2BadgeW, badge._msuf2BadgeH = width, height
            changed = true
            badge:SetSize(width, height)
            if badge.text then
                T.SetTranslatedText(badge.text, text)
                local c = style.text
                badge.text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
                if badge.text.SetWidth then badge.text:SetWidth(max(20, width - 10)) end
                if badge.text.SetMaxLines then badge.text:SetMaxLines(1) end
                if badge.text.SetWordWrap then badge.text:SetWordWrap(false) end
            end
            PaintBadgeLayers(badge._msuf2Fill, badge._msuf2Edge, style)
        end
        local shown = text ~= ""
        if shown then
            local allowCollapsed = showAllWhenClosed
                or spec.showWhenClosed == true
                or spec.showCollapsed == true
                or spec.important == true
                or spec.alwaysShow == true
            if not badgesOpen and not allowCollapsed then shown = false end
            if spec.onlyWhenOpen == true and not badgesOpen then shown = false end
        end
        shown = shown and true or false
        if badge._msuf2BadgeWantedShown ~= shown then
            badge._msuf2BadgeWantedShown = shown
            badge:SetShown(shown)
            changed = true
        end
    end
    for i = #specs + 1, #entry._msuf2Badges do
        local badge = entry._msuf2Badges[i]
        if badge and badge._msuf2BadgeWantedShown ~= false then
            badge._msuf2BadgeWantedShown = false
            badge:SetShown(false)
            changed = true
        end
    end
    -- Only a changed badge set re-anchors the header (badges, hint, title).
    if changed and entry._msuf2RefreshLayout then entry._msuf2RefreshLayout() end
end
--- "Custom" text marker for a section whose settings differ from what Reset
--- section restores. It has its own slot because summary headers hide the
--- page badge row. The owner decides at build/refresh time; a state change
--- relayouts the header once, an unchanged state costs one comparison.
function W.SetCollapsibleCustomBadge(section, shown)
    local entry = section and section._msuf2CollapsibleEntry
    local header = entry and entry.header
    if not header then return end
    shown = shown and true or false
    local badge = entry._msuf2CustomBadge
    if not badge then
        if not shown then return end
        RefreshBadgeAccentBorder()
        local style = COLLAPSIBLE_BADGE_STYLES.accent
        local fill, edge
        badge, fill, edge = NewHeaderBadge(header, CollapsibleBadgeWidth(Tr("Custom")), "Custom")
        PaintBadgeLayers(fill, edge, style)
        badge.text:SetTextColor(style.text[1], style.text[2], style.text[3], style.text[4] or 1)
        if badge.text.SetWordWrap then badge.text:SetWordWrap(false) end
        -- Hover explains the marker; a click still opens or closes the section.
        badge:EnableMouse(true)
        badge:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" and header.Click then header:Click() end
        end)
        if M.AddTooltip then
            M.AddTooltip(badge, "Custom", "Some settings in this section differ from their defaults. Reset section restores them.", { hook = true })
        end
        badge:Hide()
        entry._msuf2CustomBadge = badge
    end
    if entry._msuf2CustomBadgeWanted == shown then return end
    entry._msuf2CustomBadgeWanted = shown
    if entry._msuf2RefreshLayout then entry._msuf2RefreshLayout() else badge:SetShown(shown) end
end

-- Selection/hover move only skin surfaces; rail folding moves complete rows.
-- A critically damped spring preserves position and velocity when retargeted.
-- Drivers have no OnUpdate script once settled.
do
    local exp, abs = math.exp, math.abs
    local SPRING_RATE, CLICK_DURATION, HOVER_DURATION = 80, 0.14, 0.12
    local TAB_RATE, TAB_DURATION = 65, 0.16
    local carry = T.TrackMenuAnimationGroup({ channels = {}, Stop = function(self) self.key = nil end })
    function W.BeginSelectionMotion(owner, value)
        carry.key = nil
        local selections = owner._msuf2SelectionMotions
        local selection = owner._msuf2SelectionMotion or (selections and #selections == 1 and selections[1])
        local driver = selection and selection.driver
        if not driver or not selection.seeded or not selection.selected or selection.selected._msuf2Value == value then return end
        if T.ReducedMotionEnabled() then return end
        carry.key, carry.value, carry.time = selection.key, value, GetTime()
        for i = 1, 4 do
            local source = driver.channels[i]
            local target = carry.channels[i] or {}
            carry.channels[i] = target
            target.value, target.velocity = source.value, source.velocity
        end
    end
    local function RestoreSelection(selection, button, driver)
        if not carry.key or carry.key ~= selection.key or carry.value ~= button._msuf2Value then return false end
        local recent = GetTime() - carry.time <= 0.25
        carry.key = nil
        if not recent or T.ReducedMotionEnabled() then return false end
        for i = 1, 4 do
            local target, source = driver.channels[i], carry.channels[i]
            target.value, target.velocity = source.value, source.velocity
        end
        selection.seeded = true
        return true
    end
    local FOREGROUND_KEYS = { "_msuf2Label", "_msuf2NavIcon", "_msuf2NavArrow", "_msuf2NavOffBadge", "_msuf2NavTitleText" }
    local SURFACE_KEYS = { "_msuf2NavItem", "_msuf2NavPillVisualWidth", "_msuf2SegmentChoice", "_msuf2SolidPill",
        "_msuf2Danger", "_msuf2Primary", "_msuf2Success", "_msuf2TopBg", "_msuf2TopBorder", "_msuf2TopText",
        "_msuf2TopHoverBg", "_msuf2TopHoverBorder", "_msuf2TopActiveBg", "_msuf2TopActiveBorder", "_msuf2TopActiveText" }
    function W.RaiseSelectionText(button)
        local host = button._msuf2MotionForeground
        if not host then
            host = PixelLayoutRegion(CreateFrame("Frame", nil, button), true)
            host:SetAllPoints(button)
            host:EnableMouse(false)
            host:SetFrameLevel(button:GetFrameLevel() + 4)
            host._msuf2ControlPartOf = button
            button._msuf2MotionForeground = host
        end
        for i = 1, #FOREGROUND_KEYS do
            local region = button[FOREGROUND_KEYS[i]]
            if region and region:GetParent() ~= host then region:SetParent(host) end
        end
    end
    local function PaintSurface(driver, button, active)
        local surface = driver.art
        for i = 1, #SURFACE_KEYS do
            local key = SURFACE_KEYS[i]
            surface[key] = button[key]
        end
        surface._msuf2Active, surface._msuf2TopActive = active, active
        surface:SetAlpha(button:GetAlpha())
        if button._msuf2TopBg then ApplyTopActionButtonVisual(surface)
        else surface:RefreshVisual() end
        surface._msuf2Label:Hide()
    end
    local function PaintMotion(driver)
        -- A stale control driver rests under paint its owner already applied.
        if driver.stale then return end
        if driver.paint then driver.paint(driver) return end
        local c, art = driver.channels, driver.art
        if driver.button then
            art:SetAlpha(max(0, min(1, c[1].value)) * 0.15)
        else
            art:ClearAllPoints()
            art:SetPoint("TOPLEFT", driver, "TOPLEFT", c[1].value, c[2].value)
            art:SetSize(max(1, c[3].value), max(1, c[4].value))
        end
    end
    local function SettleMotion(driver, clear)
        driver:SetScript("OnUpdate", nil)
        for i = 1, #driver.channels do
            local c = driver.channels[i]
            if clear then c.target = 0 end
            c.value, c.velocity = c.target, 0
        end
        driver.age = 0
        PaintMotion(driver)
    end
    local function StopMotion(driver) SettleMotion(driver, driver.button ~= nil) end
    local function StepMotion(driver, elapsed)
        local selection = driver.selection
        if selection and (not selection.selected or not selection.selected._msuf2MotionSelected
            or not selection.selected:IsVisible()) then
            driver:Stop()
            driver.art:Hide()
            selection.seeded = false
            return
        end
        if not driver:IsVisible() or T.ReducedMotionEnabled() then
            driver:Stop()
            return
        end
        driver.age = driver.age + elapsed
        local rate = driver.rate
        local decay, settled = exp(-rate * elapsed), true
        for i = 1, #driver.channels do
            local c = driver.channels[i]
            local offset = c.value - c.target
            local b = c.velocity + rate * offset
            c.value = c.target + (offset + b * elapsed) * decay
            c.velocity = (c.velocity - rate * b * elapsed) * decay
            if abs(c.value - c.target) > 0.01 or abs(c.velocity) > 0.1 then settled = false end
        end
        PaintMotion(driver)
        if settled or driver.age + 0.000001 >= driver.duration then
            -- Hover settles at its destination; explicit Stop clears feedback.
            SettleMotion(driver)
        end
    end
    function W.CreateLayoutMotion(parent, paint)
        local driver = PixelLayoutRegion(CreateFrame("Frame", nil, parent), true)
        driver:SetAllPoints(parent)
        driver:EnableMouse(false)
        driver.channels, driver.paint = {}, paint
        driver.age, driver.duration, driver.Stop = 0, CLICK_DURATION, StopMotion
        driver.rate = SPRING_RATE
        driver:HookScript("OnHide", StopMotion)
        T.TrackMenuAnimationGroup(driver)
        return driver
    end
    local function NewMotion(parent, count, button)
        local driver = W.CreateLayoutMotion(parent)
        driver:SetFrameLevel(button:GetFrameLevel() + 1)
        driver.art = T.Button(driver, "", button:GetWidth(), button:GetHeight(), { history = false, noSearch = true })
        driver.art._msuf2MotionSurface = true
        driver.art._msuf2ControlPartOf = parent
        driver.art:EnableMouse(false)
        driver.art._msuf2Label:Hide()
        for i = 1, count do driver.channels[i] = { value = 0, velocity = 0, target = 0 } end
        return driver
    end
    local function StartMotion(driver, snap)
        driver.age = 0
        if snap or T.ReducedMotionEnabled() or not driver:IsVisible() then
            SettleMotion(driver)
        else
            driver:SetScript("OnUpdate", StepMotion)
        end
    end
    W.PlayLayoutMotion = StartMotion
    -- Small control transitions use the same interruptible spring. Capture the
    -- current skin paint, let its owner choose the destination, then interpolate
    -- only the existing regions. Initial/hidden/reduced-motion paint stays exact.
    local function SetChannel(driver, index, value, seed)
        local channel = driver.channels[index]
        if not channel then
            channel = { value = value, velocity = 0, target = value }
            driver.channels[index] = channel
        end
        if seed then channel.value, channel.velocity = value, 0 end
        if channel.target ~= value then driver.dirty = true end
        channel.target = value
    end
    local function ColorChannels(driver, index, r, g, b, a, seed)
        if not seed then
            local channels = driver.channels
            local cr, cg, cb, ca = channels[index], channels[index + 1], channels[index + 2], channels[index + 3]
            if cr and cg and cb and ca and cr.target == r and cg.target == g and cb.target == b and ca.target == a then
                cr.target, cg.target, cb.target, ca.target = r, g, b, a
                return
            end
        end
        SetChannel(driver, index, r, seed)
        SetChannel(driver, index + 1, g, seed)
        SetChannel(driver, index + 2, b, seed)
        SetChannel(driver, index + 3, a, seed)
    end
    local function ColorValue(channel) return max(0, min(1, channel.value)) end
    local function PaintColor(region, channels, index, texture)
        local r, g, b, a = ColorValue(channels[index]), ColorValue(channels[index + 1]),
            ColorValue(channels[index + 2]), ColorValue(channels[index + 3])
        if texture then
            region._msuf2MotionR, region._msuf2MotionG, region._msuf2MotionB, region._msuf2MotionA = r, g, b, a
            region:SetColorTexture(r, g, b, a)
        else region:SetVertexColor(r, g, b, a) end
    end
    local function PaintSwitch(driver)
        local button, channels = driver.owner, driver.channels
        local knob, pad = button._msuf2SwitchKnob, button._msuf2SwitchKnobPad or 2
        knob:ClearAllPoints()
        if not driver:GetScript("OnUpdate") and channels[1].value == 1 then
            knob:SetPoint("RIGHT", button, "RIGHT", -pad, 0)
        else
            local travel = max(0, button:GetWidth() - knob:GetWidth() - pad * 2)
            knob:SetPoint("LEFT", button, "LEFT", pad + travel * ColorValue(channels[1]), 0)
        end
        PaintColor(button._msuf2SwitchFill, channels, 2)
        PaintColor(button._msuf2SwitchEdge, channels, 6)
        PaintColor(knob, channels, 10)
    end
    local function MotionAllowed(owner)
        return owner:IsVisible() and not T.ReducedMotionEnabled()
    end
    -- Channel 1 is the knob position; 2, 6 and 10 follow the painted fill, edge and knob colors.
    local function SyncSwitchChannels(driver, button, on, seed)
        SetChannel(driver, 1, on and 1 or 0, seed)
        local r, g, b, a = button._msuf2SwitchFill:GetVertexColor()
        ColorChannels(driver, 2, r, g, b, a, seed)
        r, g, b, a = button._msuf2SwitchEdge:GetVertexColor()
        ColorChannels(driver, 6, r, g, b, a, seed)
        r, g, b, a = button._msuf2SwitchKnob:GetVertexColor()
        ColorChannels(driver, 10, r, g, b, a, seed)
    end
    function W.BeginSwitchMotion(button, checked)
        local before, driver = button._msuf2SwitchPaintedChecked, button._msuf2SwitchMotion
        local unchanged = before == (checked and true or false)
        local playing = unchanged and driver and driver:GetScript("OnUpdate")
        if (unchanged and not playing) or (before == nil and not driver) then return end
        if not MotionAllowed(button) or not button:IsEnabled() then
            if driver and (playing or driver:GetScript("OnUpdate")) then driver:Stop() end
            return
        end
        if before == nil then return end
        if not driver then
            driver = W.CreateLayoutMotion(button, PaintSwitch)
            driver.owner, driver.duration = button, 0.12
            button._msuf2SwitchMotion = driver
        end
        if not (playing or driver:GetScript("OnUpdate")) then
            SyncSwitchChannels(driver, button, before, true)
            driver.dirty, driver.stale = nil, nil
        end
        return driver
    end
    function W.FinishControlMotion(driver)
        if not driver then return end
        if driver.dirty then
            driver.dirty = nil
            PaintMotion(driver)
            StartMotion(driver)
        elseif driver:GetScript("OnUpdate") then
            PaintMotion(driver)
        end
    end
    function W.FinishSwitchMotion(driver, checked, snap)
        if not driver then return end
        if snap and not driver:GetScript("OnUpdate") then
            -- Settled repaint: the owner painted the regions. Begin reseeds the
            -- channels from them before any motion, so the sync waits until then.
            driver.stale, driver.dirty = true, nil
            return
        end
        SyncSwitchChannels(driver, driver.owner, checked, snap)
        if snap then driver.dirty = nil else W.FinishControlMotion(driver) end
    end
    local function PaintDisclosure(driver)
        driver.region:SetRotation(ColorValue(driver.channels[1]) * math.pi * 0.5)
    end
    function W.AnimateDisclosure(chevron, open, immediate)
        local target = open and 1 or 0
        local previous, driver = chevron._msuf2DisclosureTarget, chevron._msuf2DisclosureMotion
        -- Every section relayout lands here: an unchanged, idle chevron costs nothing.
        if previous == target and not (driver and driver:GetScript("OnUpdate")) then return end
        local snap = immediate or previous == nil or not MotionAllowed(chevron)
        chevron._msuf2DisclosureTarget = target
        if previous == target and not snap then return end
        if not driver and snap then chevron:SetRotation(target * math.pi * 0.5) return end
        if not driver then
            driver = W.CreateLayoutMotion(chevron:GetParent(), PaintDisclosure)
            driver.region = chevron
            SetChannel(driver, 1, previous, true)
            chevron._msuf2DisclosureMotion = driver
        end
        SetChannel(driver, 1, target)
        StartMotion(driver, snap)
    end
    local function PaintLayer(driver)
        PaintColor(driver.owner.bg, driver.channels, 1, true)
        PaintColor(driver.owner.bar, driver.channels, 5, true)
    end
    local function SeedLayerColor(driver, region, index)
        ColorChannels(driver, index, region._msuf2MotionR, region._msuf2MotionG, region._msuf2MotionB, region._msuf2MotionA, true)
    end
    function W.BeginLayerMotion(button, state, available)
        local before, driver = button._msuf2LayerPaintedState, button._msuf2LayerMotion
        button._msuf2LayerPaintedState = state
        button._msuf2LayerPaintingMotion = nil
        if not MotionAllowed(button) or not available then
            if driver and driver:GetScript("OnUpdate") then driver:Stop() end
            return
        end
        if before == nil or (before == state and not (driver and driver:GetScript("OnUpdate"))) then return end
        if not driver then
            driver = W.CreateLayoutMotion(button, PaintLayer)
            driver.owner, driver.duration, driver.rate = button, 0.10, 100
            button._msuf2LayerMotion = driver
        end
        if not driver:GetScript("OnUpdate") then
            SeedLayerColor(driver, button.bg, 1)
            SeedLayerColor(driver, button.bar, 5)
            driver.dirty, driver.stale = nil, nil
        end
        button._msuf2LayerPaintingMotion = driver
        return driver
    end
    function W.SetLayerColor(button, region, r, g, b, a)
        local driver = button._msuf2LayerPaintingMotion
        if driver then
            ColorChannels(driver, region == button.bg and 1 or 5, r, g, b, a)
        else
            local cached = button._msuf2LayerMotion
            if cached then cached.stale, cached.dirty = true, nil end
            region._msuf2MotionR, region._msuf2MotionG, region._msuf2MotionB, region._msuf2MotionA = r, g, b, a
            region:SetColorTexture(r, g, b, a)
        end
    end
    local function ButtonFeedback(button, target)
        if not button:IsVisible() or not button:IsEnabled() or T.ReducedMotionEnabled() then
            if button._msuf2ButtonMotion then button._msuf2ButtonMotion:Stop() end
            return
        end
        local driver = button._msuf2ButtonMotion
        if not driver then
            if target == 0 then return end
            driver = NewMotion(button, 1, button)
            driver.button = button
            driver.art:SetAllPoints(button)
            driver.art:SetAlpha(0)
            button._msuf2ButtonMotion = driver
        end
        PaintSurface(driver, button, true)
        driver.art:SetAlpha(max(0, min(1, driver.channels[1].value)) * 0.15)
        if driver.channels[1].target == target then return end
        driver.channels[1].target = target
        driver.duration = button._msuf2MotionPressed and CLICK_DURATION or HOVER_DURATION
        StartMotion(driver)
    end
    local function ButtonEnter(button)
        button._msuf2MotionHover = true
        ButtonFeedback(button, 0.55)
    end
    local function ButtonLeave(button)
        button._msuf2MotionHover, button._msuf2MotionPressed = nil, nil
        ButtonFeedback(button, 0)
    end
    local function ButtonDown(button)
        button._msuf2MotionPressed = true
        ButtonFeedback(button, 1)
    end
    local function ButtonUp(button)
        button._msuf2MotionPressed = nil
        ButtonFeedback(button, button._msuf2MotionHover and 0.55 or 0)
    end
    local function ButtonReset(button)
        button._msuf2MotionHover, button._msuf2MotionPressed, button._msuf2Hover = nil, nil, nil
        if button._msuf2ButtonMotion then button._msuf2ButtonMotion:Stop() end
        if button._msuf2TopBg then ApplyTopActionButtonVisual(button)
        elseif button.RefreshVisual then button:RefreshVisual() end
    end
    function W.AttachButtonMotion(button)
        if button._msuf2HasButtonMotion then return end
        button._msuf2HasButtonMotion = true
        W.RaiseSelectionText(button)
        button:HookScript("OnEnter", ButtonEnter)
        button:HookScript("OnLeave", ButtonLeave)
        button:HookScript("OnMouseDown", ButtonDown)
        button:HookScript("OnMouseUp", ButtonUp)
        button:HookScript("OnHide", ButtonReset)
        button:HookScript("OnDisable", ButtonReset)
    end
    local function RefreshSelection(selection, snap)
        local button = selection.selected
        if not button or not button._msuf2MotionSelected or not button:IsVisible() or not selection.owner:IsVisible() then
            if selection.driver then
                selection.driver:Stop()
                selection.driver.art:Hide()
            end
            selection.seeded = false
            return
        end
        local left, top = button:GetLeft(), button:GetTop()
        local parentLeft, parentTop = selection.owner:GetLeft(), selection.owner:GetTop()
        if not left or not top or not parentLeft or not parentTop then return end
        local ratio = button:GetEffectiveScale() / selection.owner:GetEffectiveScale()
        local x, y = left * ratio - parentLeft, top * ratio - parentTop
        local width, height = button:GetWidth() * ratio, button:GetHeight() * ratio
        local driver = selection.driver
        if not driver then
            driver = NewMotion(selection.owner, 4, button)
            driver.selection, driver.vertical = selection, selection.vertical
            if not selection.vertical then driver.rate, driver.duration = TAB_RATE, TAB_DURATION end
            selection.driver = driver
        end
        local c = driver.channels
        local restored = RestoreSelection(selection, button, driver)
        local changed = c[1].target ~= x or c[2].target ~= y or c[3].target ~= width or c[4].target ~= height
        c[1].target, c[2].target, c[3].target, c[4].target = x, y, width, height
        PaintSurface(driver, button, true)
        driver.art:Show()
        if changed or snap or restored or not selection.seeded then
            StartMotion(driver, not restored and (snap or not selection.seeded))
        end
        selection.seeded = true
    end
    local function SelectionSetActive(button, active)
        button:_msuf2MotionSetActive(active)
        button._msuf2MotionSelected = active and true or false
        local selection = button._msuf2SelectionMotion
        if active then
            selection.selected = button
            RefreshSelection(selection)
        elseif selection.selected == button and selection.driver then
            -- SetActive is called in a loop. Keep the in-flight position until
            -- that loop supplies the next selected button, or clear next frame.
            selection.driver:SetScript("OnUpdate", StepMotion)
        end
    end
    -- Revealing an owner or button never starts a slide. A fill that was seeded
    -- while the owner was still being built (SetActive runs during construction,
    -- before the final layout) snaps to the laid-out geometry; only a fill that
    -- is already moving (a carried page switch) keeps going.
    local function RevealSelection(selection)
        local driver = selection.driver
        RefreshSelection(selection, not (driver and driver:GetScript("OnUpdate")))
    end
    local function SelectionShown(owner)
        local selections = owner._msuf2SelectionMotions
        for i = 1, #selections do RevealSelection(selections[i]) end
    end
    local function SelectionResized(owner)
        if not owner._msuf2NavFolding then W.RefreshSelectionMotion(owner, true) end
    end
    function W.ShiftSelectionMotion(button, dy)
        local selection = button._msuf2SelectionMotion
        local driver = selection and selection.selected == button and selection.driver
        if not driver then return end
        if not selection.seeded then RefreshSelection(selection, true) return end
        local c = driver.channels[2]
        c.value, c.target = c.value + dy, c.target + dy
        PaintMotion(driver)
    end
    function W.UpdateSelectionAlpha(button)
        local selection = button._msuf2SelectionMotion
        if selection and selection.selected == button and selection.driver then selection.driver.art:SetAlpha(button:GetAlpha()) end
    end
    local function SelectionButtonShown(button)
        if button._msuf2SelectionMotion.owner._msuf2NavFoldPreparing then return end
        if button._msuf2MotionSelected then RevealSelection(button._msuf2SelectionMotion) end
    end
    local function SelectionButtonHidden(button)
        local selection = button._msuf2SelectionMotion
        if selection.owner._msuf2NavFoldPreparing then return end
        if selection.selected == button then
            if selection.driver then
                selection.driver:Stop()
                selection.driver.art:Hide()
            end
            selection.seeded = false
        end
    end
    function W.RefreshSelectionMotion(owner, snap)
        local selections = owner._msuf2SelectionMotions
        if not selections then return end
        for i = 1, #selections do RefreshSelection(selections[i], snap) end
    end
    function W.AttachSelectionMotion(owner, buttons, vertical, key)
        local values = { key or "" }
        for i = 1, #buttons do values[#values + 1] = tostring(buttons[i]._msuf2Value) end
        local selection = { owner = owner, vertical = vertical, key = table.concat(values, "\031") }
        local selections = owner._msuf2SelectionMotions
        if not selections then
            selections = {}
            owner._msuf2SelectionMotions = selections
            owner:HookScript("OnShow", SelectionShown)
            owner:HookScript("OnSizeChanged", SelectionResized)
        end
        selections[#selections + 1] = selection
        for _, button in pairs(buttons) do
            if not button._msuf2MotionSetActive then
                button._msuf2MotionSetActive, button.SetActive = button.SetActive, SelectionSetActive
                button._msuf2SelectionMotion = selection
                button._msuf2MotionSelected = button._msuf2Active or button._msuf2TopActive or false
                if button._msuf2MotionSelected then selection.selected = button end
                W.AttachButtonMotion(button)
                button:HookScript("OnShow", SelectionButtonShown)
                button:HookScript("OnHide", SelectionButtonHidden)
            end
        end
        RefreshSelection(selection, true)
        return selection
    end
end
