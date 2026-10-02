local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
--- Shell/Menu2/MSUF_Menu2_Widgets_Buttons.lua
--- Top-bar and role buttons (W.TopButton, W.RoleButton) and the badges a
--- collapsible section header shows (W.SetCollapsibleBadges, the Custom badge).
---
--- Split from MSUF_Menu2_Widgets.lua; loads after the page builder.

local _, MSUF = ...
local M = MSUF.MSUF2
local T = M.Theme
local W = M.Widgets
local Shared = W._Shared
local floor = math.floor
local max = math.max
local min = math.min
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
local TOP_DANGER_BUTTON_STYLE = TopButtonStyle({ 0.070, 0.026, 0.034, 0.94 }, { 0.340, 0.090, 0.110, 0.82 }, { 1.00, 0.82, 0.82, 1 }, { 0.090, 0.035, 0.045, 0.96 }, { 0.420, 0.120, 0.140, 0.90 })
local TOP_SUCCESS_BUTTON_STYLE = TopButtonStyle({ 0.018, 0.145, 0.090, 0.94 }, { 0.055, 0.440, 0.270, 0.82 }, { 0.780, 1.000, 0.875, 1 }, { 0.026, 0.185, 0.115, 0.96 }, { 0.075, 0.560, 0.345, 0.90 })
local TOP_ROLE_STYLES = { primary = TOP_ACTION_BUTTON_STYLE, destructive = TOP_DANGER_BUTTON_STYLE, danger = TOP_DANGER_BUTTON_STYLE, reset = TOP_DANGER_BUTTON_STYLE, delete = TOP_DANGER_BUTTON_STYLE, success = TOP_SUCCESS_BUTTON_STYLE, confirm = TOP_SUCCESS_BUTTON_STYLE }
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
local function ApplyTopActionButtonVisual(btn, hover)
    local bg = btn._msuf2TopActive and btn._msuf2TopActiveBg or (hover and btn._msuf2TopHoverBg or btn._msuf2TopBg)
    local br = btn._msuf2TopActive and btn._msuf2TopActiveBorder or (hover and btn._msuf2TopHoverBorder or btn._msuf2TopBorder)
    local tx = btn._msuf2TopActive and btn._msuf2TopActiveText or btn._msuf2TopText
    local mul = hover and 1.03 or 1
    if btn._msuf2Fill then
        local fill = { min(bg[1] * mul, 1), min(bg[2] * mul, 1), min(bg[3] * mul, 1), bg[4] or 1 }
        if T.SetFillGradient then T.SetFillGradient(btn._msuf2Fill, fill, 0.07, -0.26) else btn._msuf2Fill:SetVertexColor(fill[1], fill[2], fill[3], fill[4]) end
    end
    if btn._msuf2Edge then btn._msuf2Edge:SetVertexColor(min(br[1] * mul, 1), min(br[2] * mul, 1), min(br[3] * mul, 1), br[4] or 1) end
    if btn._msuf2Label then btn._msuf2Label:SetTextColor(tx[1], tx[2], tx[3], tx[4] or 1) end
    if btn._msuf2TopStripe then btn._msuf2TopStripe:SetShown(btn._msuf2TopActive and true or false) end
end
local TOP_BUTTON_HOOKS = { OnEnter = function(self) ApplyTopActionButtonVisual(self, true) end, OnLeave = function(self) ApplyTopActionButtonVisual(self) end, OnEnable = function(self) ApplyTopActionButtonVisual(self) end, OnDisable = function(self) ApplyTopActionButtonVisual(self) end }
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
local function StyleTopActionButton(btn)
    return StyleTopButton(btn, TOP_ACTION_BUTTON_STYLE)
end
local function StyleTopDangerButton(btn)
    return StyleTopButton(btn, TOP_DANGER_BUTTON_STYLE)
end
local function StyleTopSuccessButton(btn)
    return StyleTopButton(btn, TOP_SUCCESS_BUTTON_STYLE)
end
M.AssignNamedValues(W, "StyleTopActionButton StyleTopDangerButton StyleTopSuccessButton",
    StyleTopActionButton, StyleTopDangerButton, StyleTopSuccessButton)
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
            badge = PixelLayoutRegion(CreateFrame("Frame", nil, header))
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
            if badge._msuf2Fill then
                local c = style.bg
                if T.SetFillGradient then
                    T.SetFillGradient(badge._msuf2Fill, c, 0.12, -0.18)
                else
                    badge._msuf2Fill:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
                end
            end
            if badge._msuf2Edge then
                local c = style.border
                badge._msuf2Edge:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
            end
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
        badge = PixelLayoutRegion(CreateFrame("Frame", nil, header))
        badge:SetFrameLevel((header.GetFrameLevel and header:GetFrameLevel() or 1) + 2)
        badge:SetSize(CollapsibleBadgeWidth(Tr("Custom")), 20)
        local fill, edge = T.CreateSuperellipseLayers(badge, "_msuf2HeaderBadge", 1, "ARTWORK", "OVERLAY")
        if fill then
            if T.SetFillGradient then T.SetFillGradient(fill, style.bg, 0.12, -0.18)
            else fill:SetVertexColor(style.bg[1], style.bg[2], style.bg[3], style.bg[4] or 1) end
        end
        if edge then edge:SetVertexColor(style.border[1], style.border[2], style.border[3], style.border[4] or 1) end
        badge.text = T.Font(badge, "GameFontDisableSmall", "Custom", T.colors.text)
        badge.text:SetPoint("CENTER", badge, "CENTER", 0, 0)
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
