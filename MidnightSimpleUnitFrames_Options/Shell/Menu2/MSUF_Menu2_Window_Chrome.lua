-- Window: Chrome responsibility.
local addonName, MSUF = ...
local M = MSUF.MSUF2
local Parts = M.WindowParts
local L = Parts.L
local ApplyMenuFramePriority = Parts.ApplyMenuFramePriority
local ApplyMenuFrameScale = Parts.ApplyMenuFrameScale
local ApplyScrollMetrics = Parts.ApplyScrollMetrics
local ApplyWindowResizeBounds = Parts.ApplyWindowResizeBounds
local BuildNav = Parts.BuildNav
local C_Timer = Parts.C_Timer
local EffectiveMenuScale = Parts.EffectiveMenuScale
local EnsureEditModeUIHook = Parts.EnsureEditModeUIHook
local EnsurePersistentMenuState = Parts.EnsurePersistentMenuState
local ExportPublic = Parts.ExportPublic
local FEEDBACK_COLOR_KEYS = Parts.FEEDBACK_COLOR_KEYS
local FILE = Parts.FILE
local GetAddonVersion = Parts.GetAddonVersion
local IsEditModeActive = Parts.IsEditModeActive
local IsEditModeCombatLocked = Parts.IsEditModeCombatLocked
local MENU_SCALE_MAX_PERCENT = Parts.MENU_SCALE_MAX_PERCENT
local MENU_SCALE_MIN_PERCENT = Parts.MENU_SCALE_MIN_PERCENT
local MENU_SCALE_REFERENCE = Parts.MENU_SCALE_REFERENCE
local MENU_SCALE_STEP_PERCENT = Parts.MENU_SCALE_STEP_PERCENT
local MaximizeSlashMenuWindow = Parts.MaximizeSlashMenuWindow
local MenuRuntime = Parts.MenuRuntime
local MenuScalePercent = Parts.MenuScalePercent
local MenuScaleValue = Parts.MenuScaleValue
local MinimizeSlashMenuWindow = Parts.MinimizeSlashMenuWindow
local NAV_W = Parts.NAV_W
local PixelLayoutRegion = Parts.PixelLayoutRegion
local QueueVisiblePageLayoutSettle = Parts.QueueVisiblePageLayoutSettle
local ReadSavedWindowSize = Parts.ReadSavedWindowSize
local RefreshDashboardEditModeButton = Parts.RefreshDashboardEditModeButton
local RefreshSearchResultsPage = Parts.RefreshSearchResultsPage
local RefreshWindowMetrics = Parts.RefreshWindowMetrics
local RequestBossPagePreviewForKey = Parts.RequestBossPagePreviewForKey
local RequestGroupPagePreviewForKey = Parts.RequestGroupPagePreviewForKey
local ResetBossPagePreviewCache = Parts.ResetBossPagePreviewCache
local ResetStatusIndicatorTestModeOnMenuExit = Parts.ResetStatusIndicatorTestModeOnMenuExit
local ResetWindowState = Parts.ResetWindowState
local SavePersistentMenuState = Parts.SavePersistentMenuState
local SetCachedText = Parts.SetCachedText
local SetWindowMetrics = Parts.SetWindowMetrics
local SyncBossPagePreviewForKey = Parts.SyncBossPagePreviewForKey
local T = Parts.T
local W = Parts.W
local WINDOW_FOOTER_H = Parts.WINDOW_FOOTER_H
local WINDOW_H = Parts.WINDOW_H
local WINDOW_W = Parts.WINDOW_W
local WindowDragStartAllowed = Parts.WindowDragStartAllowed
local floor = Parts.floor
local max = Parts.max
local min = Parts.min

local function BuildWindowShell()
    EnsurePersistentMenuState()
    SetWindowMetrics(ReadSavedWindowSize())
    local WINDOW_W, WINDOW_H = Parts.WindowSize()
    local f = T.Panel(UIParent, "MSUF2_Window", T.colors.glassShell or T.colors.bg, T.colors.border)
    T.ApplySurface(f, "shell")
    ExportPublic("MSUF_StandaloneOptionsWindow", f)
    f:SetSize(WINDOW_W, WINDOW_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    ApplyMenuFramePriority(f)
    f:EnableMouse(true)
    f:SetMovable(true)
    if f.SetResizable then f:SetResizable(true) end
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    ApplyWindowResizeBounds(f)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if WindowDragStartAllowed(self) then self:_msuf2BeginWindowDrag() end
    end)
    f:SetScript("OnDragStop", function(self) self:_msuf2FinishWindowDrag(true) end)
    f:SetScript("OnSizeChanged", function(self)
        if self._msuf2LiveResizing then
            self._msuf2ResizeMetricsDirty = true
            return
        end
        if self._msuf2WindowLayoutAnim then
            -- Raw animation geometry changes every render frame. Responsive
            -- metrics and preview layout commit once in the onFinished rebuild;
            -- recalculating them here makes the preview visibly chase the shell.
            return
        end
        RefreshWindowMetrics(self)
        ApplyScrollMetrics()
    end)
    f:Hide()
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "MSUF2_Window") end
    local title = T.Font(f, "GameFontDisableSmall", "MSUF", T.colors.accent)
    title:SetPoint("TOPLEFT", 12, -6)
    title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -112, -6)
    title:SetJustifyH("LEFT")
    title:SetAlpha(0.82)
    f.title = title
    local subtitle = T.Font(f, "GameFontDisableSmall", "", T.colors.muted)
    subtitle:SetPoint("TOPRIGHT", f, "TOPRIGHT", -112, -16)
    subtitle:SetJustifyH("RIGHT")
    subtitle:Hide()
    f.subtitle = subtitle
    local windowControls = M.CreateWindowControlGroup(f, 3)
    -- The authored texture extends three pixels beyond the clickable group on
    -- the horizontal axis. Offset the anchor by 11 so the visible right edge,
    -- like the visible top edge, observes the rail's 8px outer spacing.
    windowControls:SetPoint("TOPRIGHT", f, "TOPRIGHT", -11, -7)
    f.windowControls = windowControls
    local function AddControl(anchor, anchorPoint, kind, tooltipTitle, tooltipText, segment, onClick, path, label, meta)
        local btn = M.CreateWindowControlButton(windowControls, kind, tooltipTitle, tooltipText, segment)
        btn:SetPoint("TOPRIGHT", anchor, anchorPoint, 0, 0)
        btn:SetScript("OnClick", onClick)
        meta.historyMode = "none"
        M.RegisterMenuChromeControl(btn, path, label, "action", meta)
        return btn
    end
    local close = AddControl(windowControls, "TOPRIGHT", "close", "Close", "Close the MSUF menu window.", 3,
        function() M.HideSlashMenuAndMinibar(f) end, "window.close", "Close MSUF menu", {
            actionKey = "menu_window_close",
            help = "Closes the MSUF menu window, including its minimized bar.",
        })
    if M.minimizedBar and M.minimizedBar.closeButton and M.MarkRuntimeControlComponent then
        M.MarkRuntimeControlComponent(M.minimizedBar.closeButton, close)
    end
    f.closeButton = close
    local maximize = AddControl(close, "TOPLEFT", "maximize", "Maximize", "Maximize or restore the MSUF menu window.", 2,
        function() MaximizeSlashMenuWindow(f) end, "window.maximize", "Maximize MSUF menu", {
            actionKey = "menu_window_maximize",
            help = "Maximizes the MSUF menu window; the same title-bar button restores it when maximized.",
            command = {
                kind = "button",
                historyMode = "none",
                set = function()
                    if f._msuf2WindowState == "maximized" then return false end
                    return MaximizeSlashMenuWindow(f)
                end,
            },
        })
    f.maximizeButton = maximize
    f.minimizeButton = AddControl(maximize, "TOPLEFT", "minimize", "Minimize", "Collapse the MSUF menu to a small taskbar-style bar.", 1,
        function() MinimizeSlashMenuWindow(f) end, "window.minimize", "Minimize MSUF menu", {
            actionKey = "menu_window_minimize",
            help = "Minimizes the MSUF menu to its compact draggable bar.",
        })
    return { frame = f }
end

local function CreateMenuScaleControl(f)
    local control = T.Panel(f, nil, T.colors.glassStatus or T.colors.header, T.colors.borderSoft)
    T.ApplySurface(control, "status")
    control:SetSize(190, 22)
    control:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 4)
    control:SetFrameLevel(f:GetFrameLevel() + 20)
    control:EnableMouse(true)

    local label = T.Font(control, "GameFontDisableSmall", "", T.colors.muted)
    label:SetPoint("LEFT", control, "LEFT", 8, 0)
    label:SetWidth(76)
    label:SetJustifyH("LEFT")

    local slider = PixelLayoutRegion(CreateFrame("Slider", nil, control))
    slider:SetPoint("LEFT", label, "RIGHT", 6, 0)
    slider:SetPoint("RIGHT", control, "RIGHT", -8, 0)
    slider:SetHeight(20)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(MENU_SCALE_MIN_PERCENT, MENU_SCALE_MAX_PERCENT)
    slider:SetValueStep(MENU_SCALE_STEP_PERCENT)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    if slider.SetStepsPerPage then slider:SetStepsPerPage(0) end
    if slider.EnableMouseWheel then slider:EnableMouseWheel(true) end
    if slider.SetPropagateMouseWheel then slider:SetPropagateMouseWheel(false) end
    slider._msuf2CursorDrag = true
    T.StyleSlider(slider)
    return control, label, slider
end

local function InstallMenuScaleControl(f)
    if not (f and T) then return end
    local control, label, slider = CreateMenuScaleControl(f)

    local function Percent(value)
        local pct = tonumber(value) or 100
        if pct < MENU_SCALE_MIN_PERCENT then pct = MENU_SCALE_MIN_PERCENT
        elseif pct > MENU_SCALE_MAX_PERCENT then pct = MENU_SCALE_MAX_PERCENT end
        return floor((pct / MENU_SCALE_STEP_PERCENT) + 0.5) * MENU_SCALE_STEP_PERCENT
    end
    local function UpdateVisual(value)
        local pct = Percent(value or slider:GetValue())
        -- One translated format; the raw setter keeps every percentage out of
        -- the locale-key tracking (Theme FontSetText).
        T.SetTranslatedText(label, M.Format("Menu %d%%", pct))
        local fill = slider._msufFill
        if fill then
            local span = MENU_SCALE_MAX_PERCENT - MENU_SCALE_MIN_PERCENT
            local fraction = span > 0 and ((pct - MENU_SCALE_MIN_PERCENT) / span) or 0
            fill:SetWidth(max(1, max(1, slider:GetWidth() - 2) * fraction))
        end
        if slider._msuf2UpdateThumb then slider:_msuf2UpdateThumb() end
    end
    slider._msuf2UpdateFill = function(self) UpdateVisual(self:GetValue()) end

    local function Refresh()
        local g = M.GetGeneralDB and M.GetGeneralDB()
        local pct = Percent(MenuScalePercent(type(g) == "table" and g.slashMenuScale or MENU_SCALE_REFERENCE))
        slider._msuf2Refreshing = true
        slider:SetValue(pct)
        slider._msuf2Refreshing = nil
        UpdateVisual(pct)
    end
    local function Commit(value)
        local g = M.GetGeneralDB and M.GetGeneralDB()
        if type(g) ~= "table" then return false end
        local pct = Percent(value or slider:GetValue())
        g.slashMenuScale = MenuScaleValue(pct)
        if ApplyMenuFrameScale then
            ApplyMenuFrameScale(f)
        elseif f.SetScale then
            f:SetScale(EffectiveMenuScale(g.slashMenuScale))
            ApplyWindowResizeBounds(f)
        end
        Refresh()
        return true
    end
    local function SetValueFromCursor()
        if not (GetCursorPosition and slider.GetLeft and slider.GetWidth) then return end
        local left, width = slider:GetLeft(), slider:GetWidth()
        if not left or not width or width <= 0 then return end
        local cursorX = GetCursorPosition()
        local effectiveScale = slider.GetEffectiveScale and slider:GetEffectiveScale() or 1
        if not effectiveScale or effectiveScale == 0 then effectiveScale = 1 end
        local fraction = ((cursorX / effectiveScale) - left) / width
        if fraction < 0 then fraction = 0 elseif fraction > 1 then fraction = 1 end
        local target = Percent(MENU_SCALE_MIN_PERCENT + ((MENU_SCALE_MAX_PERCENT - MENU_SCALE_MIN_PERCENT) * fraction))
        if target ~= tonumber(slider:GetValue()) then slider:SetValue(target) end
    end
    -- Same cursor-follow contract as W.Slider: the press keeps driving the
    -- value until the button is released, not just on the down-click.
    local function FollowScaleCursor(self)
        if not self._msuf2MenuScaleDragging then
            self:SetScript("OnUpdate", nil)
            return
        end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            self._msuf2MenuScaleDragging = nil
            self:SetScript("OnUpdate", nil)
            Commit(self:GetValue())
            return
        end
        SetValueFromCursor()
    end

    slider:HookScript("OnValueChanged", function(self, value)
        if not self._msuf2Refreshing then UpdateVisual(value) end
    end)
    slider:SetScript("OnMouseDown", function(self, button)
        if button and button ~= "LeftButton" then return end
        self._msuf2MenuScaleDragging = true
        SetValueFromCursor()
        self:SetScript("OnUpdate", FollowScaleCursor)
    end)
    slider:SetScript("OnMouseUp", function(self, button)
        if button and button ~= "LeftButton" then return end
        self._msuf2MenuScaleDragging = nil
        self:SetScript("OnUpdate", nil)
        Commit(self:GetValue())
    end)
    slider:SetScript("OnMouseWheel", function(self, delta)
        if not delta or delta == 0 then return end
        local step = MENU_SCALE_STEP_PERCENT
        self:SetValue(Percent((tonumber(self:GetValue()) or 100) + (delta > 0 and step or -step)))
        Commit(self:GetValue())
    end)
    slider:HookScript("OnHide", function(self)
        self._msuf2MenuScaleDragging = nil
        self:SetScript("OnUpdate", nil)
    end)

    local tooltip = "Scales only the MSUF menu. Drag the bar or use the mouse wheel; changes apply immediately."
    M.AddTooltip(control, "MSUF Menu Scale", tooltip, { hook = true, owner = "ANCHOR_TOP" })
    M.AddTooltip(slider, "MSUF Menu Scale", tooltip, { hook = true, owner = "ANCHOR_TOP" })
    M.RegisterMenuChromeControl(slider, "window.menu-scale", "MSUF Menu Scale", "setting", {
        kind = "slider",
        settingKey = "general.slashMenuScale",
        historyMode = "none",
        help = "Reads and applies the MSUF configuration-menu scale percentage directly.",
        command = {
            kind = "slider", min = MENU_SCALE_MIN_PERCENT, max = MENU_SCALE_MAX_PERCENT,
            step = MENU_SCALE_STEP_PERCENT, percentIsValue = true, historyMode = "none",
            get = function()
                local g = M.GetGeneralDB and M.GetGeneralDB()
                return Percent(MenuScalePercent(type(g) == "table" and g.slashMenuScale or MENU_SCALE_REFERENCE))
            end,
            set = function(value)
                slider:SetValue(Percent(value))
                return Commit(slider:GetValue())
            end,
            refresh = Refresh,
        },
    })
    control.slider, control.label, control.Refresh = slider, label, Refresh
    f.menuScaleControl, f.menuScaleSlider = control, slider
    f.RefreshMenuScaleControl = Refresh
    Refresh()
end

-- Same links as the dashboard support card, parked in the free bottom-left
-- corner of the footer band: faint until hovered so the chrome stays quiet.
-- The marks keep their colors at rest -- at 14px the brand color is the only
-- thing that tells them apart, so desaturating them on top of the low alpha
-- left five identical gray blobs. Anchored to the nav rail so the row lines up
-- with the nav buttons above it, and centered in the 30px band so it shares a
-- baseline with the menu-scale control on the right.
local SUPPORT_STRIP_NAV_INSET = 8 -- mirrors NAV_ITEM_X in MSUF_Menu2_NavRail
local function InstallSupportLinkStrip(f)
    if not (f and type(CreateFrame) == "function") then return end
    if f.supportLinkStrip then return end
    local iconDir = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\"
    local links = {
        { texture = "Discord.png", title = "Discord", tooltip = "Copy Discord Link", url = "https://discord.gg/2Gf9b2Wprz" },
        { texture = "Patreon.png", title = "Patreon", tooltip = "Click to copy the Patreon support link.",
            url = "https://www.patreon.com/cw/MidnightSimpleUnitframes" },
        { texture = "PayPal.png", title = "PayPal", tooltip = "Click to copy the PayPal support link.",
            url = "https://www.paypal.com/ncp/payment/H3N2P87S53KBQ" },
        { texture = "Ko-Fi.png", title = "Ko-fi", tooltip = "Click to copy the Ko-fi link.", url = "https://ko-fi.com/midnightsimpleunitframes#linkModal" },
        { texture = "GitHub.png", title = "GitHub", tooltip = "Click to copy the GitHub repository link.",
            url = "https://github.com/Mapkov2/MidnightSimpleUnitFrames" },
    }
    local size, gap, idleAlpha = 14, 7, 0.45
    local strip = PixelLayoutRegion(CreateFrame("Frame", nil, f))
    strip:SetSize((#links * size) + ((#links - 1) * gap), size)
    local rail = f.nav
    if rail then
        strip:SetPoint("TOPLEFT", rail, "BOTTOMLEFT", SUPPORT_STRIP_NAV_INSET, -floor((WINDOW_FOOTER_H - size) * 0.5))
    else
        strip:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16 + SUPPORT_STRIP_NAV_INSET, floor((WINDOW_FOOTER_H - size) * 0.5))
    end
    strip:SetFrameLevel(f:GetFrameLevel() + 20)
    local previous
    for i = 1, #links do
        local data = links[i]
        local btn = PixelLayoutRegion(CreateFrame("Button", nil, strip))
        btn:SetSize(size, size)
        if previous then
            btn:SetPoint("LEFT", previous, "RIGHT", gap, 0)
        else
            btn:SetPoint("LEFT", strip, "LEFT", 0, 0)
        end
        local icon = PixelLayoutRegion(btn:CreateTexture(nil, "ARTWORK"))
        icon:SetAllPoints()
        icon:SetTexture(iconDir .. data.texture)
        icon:SetAlpha(idleAlpha)
        btn:SetScript("OnEnter", function() icon:SetAlpha(1) end)
        btn:SetScript("OnLeave", function() icon:SetAlpha(idleAlpha) end)
        btn:SetScript("OnClick", function()
            MSUF.Require("MSUF_ShowCopyLink", "Shell/Menu2/MSUF_Menu2_Window.lua")(data.title, data.url)
        end)
        M.AddTooltip(btn, data.title, data.tooltip, { hook = true, owner = "ANCHOR_TOP" })
        previous = btn
    end
    f.supportLinkStrip = strip
end

-- Drag, snap and resize share transient proxy state but no page/chrome state.
local function HistoryNavButton(status, rotation, hitLeft, hitRight, onClick)
    local btn = PixelLayoutRegion(CreateFrame("Button", nil, status))
    btn:SetSize(22, 22)
    if btn.SetHitRectInsets then btn:SetHitRectInsets(hitLeft, hitRight, -5, -11) end
    local fill, edge = T.CreateSuperellipseLayers(btn, "_msuf2HistNav", 1, "BACKGROUND", "BORDER")
    local icon = PixelLayoutRegion(btn:CreateTexture(nil, "ARTWORK"))
    icon:SetTexture(T.media.dropdownChevron)
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", 0, 0)
    if icon.SetRotation then icon:SetRotation(rotation) end
    btn._msuf2HistNavIcon = icon
    local CLEAR = { 0, 0, 0 }
    local function Paint(self, hover, down)
        local c = T.colors
        local disabled = self.IsEnabled and not self:IsEnabled()
        -- fill color/alpha, edge color/alpha, icon color/alpha for the resting state.
        local fillC, fillA, edgeC, edgeA, iconC, iconA = CLEAR, 0, CLEAR, 0, c.muted, 0.96
        if self._msuf2TourCue then
            fillC, fillA, edgeC, edgeA, iconC, iconA = c.pillActive, 0.90, c.pillEdgeActive, 0.92, c.pillTextActive, 1
        elseif disabled then
            iconC, iconA = c.disabled, 0.55
        elseif down then
            fillC, fillA, edgeC, edgeA, iconC, iconA = c.pillActive, 0.90, c.pillEdgeActive, 0.85, c.pillTextActive, 1
        elseif hover then
            fillC, fillA, edgeC, edgeA, iconC, iconA = c.pillHover, 0.92, c.pillEdgeHover, 0.80, c.text, 1
        end
        if fill then fill:SetVertexColor(fillC[1], fillC[2], fillC[3], fillA) end
        if edge then edge:SetVertexColor(edgeC[1], edgeC[2], edgeC[3], edgeA) end
        icon:SetVertexColor(iconC[1], iconC[2], iconC[3], iconA)
    end
    btn:SetScript("OnEnter", function(self)
        self._msuf2Hover = true
        Paint(self, true, self._msuf2Down)
    end)
    btn:SetScript("OnLeave", function(self)
        self._msuf2Hover = nil
        self._msuf2Down = nil
        Paint(self, false, false)
    end)
    btn:SetScript("OnMouseDown", function(self)
        self._msuf2Down = true
        Paint(self, self._msuf2Hover, true)
    end)
    btn:SetScript("OnMouseUp", function(self)
        self._msuf2Down = nil
        Paint(self, self._msuf2Hover, false)
    end)
    btn:SetScript("OnEnable", function(self) Paint(self, self._msuf2Hover, self._msuf2Down) end)
    btn:SetScript("OnDisable", function(self) Paint(self, false, false) end)
    btn:SetScript("OnClick", onClick)
    -- The first upgrade-tour stop deliberately makes this impossible to
    -- miss. A native animation group flashes the complete button quickly;
    -- there is no Lua OnUpdate, and MenuRuntime quiescence tracks/stops it
    -- with every other menu animation.
    local tourBlink
    if btn.CreateAnimationGroup then
        tourBlink = btn:CreateAnimationGroup()
        if T.TrackMenuAnimationGroup then T.TrackMenuAnimationGroup(tourBlink) end
        if tourBlink.SetLooping then tourBlink:SetLooping("BOUNCE") end
        local fade = tourBlink:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0.08)
        fade:SetDuration(0.16)
        btn._msuf2TourBlink = tourBlink
    end
    btn._msuf2SetTourCue = function(enabled)
        btn._msuf2TourCue = enabled == true or nil
        Paint(btn, btn._msuf2Hover, btn._msuf2Down)
        if btn._msuf2TourCue then
            if tourBlink and (not tourBlink.IsPlaying or not tourBlink:IsPlaying()) then tourBlink:Play() end
        else
            if tourBlink and tourBlink.Stop then tourBlink:Stop() end
            btn:SetAlpha(1)
        end
    end
    -- Disabled arrows keep their tooltip so the affordance stays learnable.
    if btn.SetMotionScriptsWhileDisabled then btn:SetMotionScriptsWhileDisabled(true) end
    Paint(btn, false, false)
    return btn
end
local function BuildWindowChrome(state)
    local f = state.frame
    local content = PixelLayoutRegion(CreateFrame("Frame", nil, f))
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -40)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, WINDOW_FOOTER_H)
    f.content = content
    local nav = T.Panel(content, nil, T.colors.glassRail or T.colors.panelNav or T.colors.panel, T.colors.borderSoft)
    T.ApplySurface(nav, "rail")
    nav:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    nav:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
    nav:SetWidth(NAV_W)
    f.nav = nav
    f._msufNavRail = nav
    f._msufNavStack = nav
    M.nav = nav
    BuildNav(nav)
    InstallSupportLinkStrip(f)
    local host = T.Panel(content, nil, T.colors.glassHost or T.colors.panel, T.colors.borderSoft)
    T.ApplySurface(host, "host")
    host:SetPoint("TOPLEFT", nav, "TOPRIGHT", 4, 0)
    host:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    f.host = host
    f._msufMirrorHost = host
    if T.ApplyMenuAtmosphere then T.ApplyMenuAtmosphere(f, host, nav) end
    local status = T.Panel(host, nil, T.colors.glassStatus or T.colors.header, T.colors.borderSoft)
    T.ApplySurface(status, "status")
    status:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    status:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    status:SetHeight(60)
    local function StatusDivider(edge, inset, alpha)
        local line = PixelLayoutRegion(status:CreateTexture(nil, "ARTWORK", nil, 6))
        line:SetHeight(1)
        line:SetPoint(edge .. "LEFT", status, edge .. "LEFT", inset, 0)
        line:SetPoint(edge .. "RIGHT", status, edge .. "RIGHT", -inset, 0)
        line:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], alpha)
    end
    StatusDivider("TOP", 0, 0.25)
    StatusDivider("BOTTOM", 16, 0.16)
    local function StatusText(point, relativeTo, relativePoint, x, y, justify, alpha)
        local fs = T.Font(status, "GameFontDisableSmall", "", T.colors.muted)
        fs:SetPoint(point, relativeTo, relativePoint, x, y)
        fs:SetJustifyH(justify or "LEFT")
        if alpha then fs:SetAlpha(alpha) end
        return fs
    end
    -- Browser-style Back/Forward page navigation. The history stacks live next
    -- to SelectPage; these two ghost buttons are their only visible surface.
    -- Cold path by construction: state changes on page navigation only, no
    -- OnUpdate, no events. All colors come from theme tokens so every menu
    -- accent (midnight, class, presets, custom, +tint) restyles them for free.
    -- The 22px art is a much smaller target than the empty strip around it, so
    -- the hit rect grows well past the glyph: down to just above the bottom
    -- divider, up to the text row, and outward to the side. The 2px gap between
    -- the pair is split 1/1 so neither arrow ever steals the other's clicks.
    -- Bottom-left of the strip, in line with the toolbar button row on the
    -- right; the Profile/Edit/Combat text row above keeps its full width.
    local histBack = HistoryNavButton(status, -math.pi * 0.5, -12, -1, function() M.GoBackPage() end)
    histBack:SetPoint("BOTTOMLEFT", status, "BOTTOMLEFT", 18, 13)
    local histForward = HistoryNavButton(status, math.pi * 0.5, -1, -14, function() M.GoForwardPage() end)
    histForward:SetPoint("LEFT", histBack, "RIGHT", 2, 0)
    M.pageHistoryBackButton = histBack
    M.pageHistoryForwardButton = histForward
    local function HistoryTargetTitle(field)
        local history = M.GetPageHistoryState() or nil
        local spec = history and history[field] and M.pages and M.pages[history[field]]
        return spec and spec.title and M.Tr(spec.title) or ""
    end
    M.AddTooltip(histBack, function() return M.Tr("Previous page") end,
        function() return HistoryTargetTitle("previousPage") end, { hook = true })
    M.AddTooltip(histForward, function() return M.Tr("Next page") end,
        function() return HistoryTargetTitle("nextPage") end, { hook = true })
    M.RegisterMenuChromeControl(histBack, "toolbar.page-back", "Previous Page", "action", {
        actionKey = "dashboard_page_back",
        historyMode = "none", help = "Opens the previous page from the menu page history.",
    })
    M.RegisterMenuChromeControl(histForward, "toolbar.page-forward", "Next Page", "action", {
        actionKey = "dashboard_page_forward",
        historyMode = "none", help = "Opens the next page from the menu page history.",
    })
    M.RefreshPageHistoryNav()
    local sbProfile = StatusText("LEFT", status, "LEFT", 24, 15)
    local sbEdit = StatusText("LEFT", sbProfile, "RIGHT", 16, 0)
    local sbCombat = StatusText("LEFT", sbProfile, "RIGHT", 16, 0)
    local sbVersion = StatusText("RIGHT", status, "RIGHT", -16, 15, "RIGHT", 0.50)
    local sbFeedback = StatusText("RIGHT", sbVersion, "LEFT", -16, 15, "RIGHT", 0)
    sbFeedback:SetPoint("LEFT", sbCombat, "RIGHT", 16, 15)
    status.profileText = sbProfile
    status.editText = sbEdit
    status.combatText = sbCombat
    status.versionText = sbVersion
    status.feedbackText = sbFeedback
    status.text = sbProfile
    f.status = status
end

local function InstallWindowFeedback(f)
    -- The fade-out runs on a MenuTimer task; when the menu quiesces (or the
    -- task is refused in combat) the message is cleared at once instead.
    local function ClearStatusFeedback()
        local feedback = f and f.status and f.status.feedbackText
        if not feedback then return end
        f.status._msuf2FeedbackSerial = (f.status._msuf2FeedbackSerial or 0) + 1
        feedback:SetAlpha(0)
        feedback:SetText("")
    end
    MenuRuntime:SetQuiesceSettler("status-feedback", ClearStatusFeedback)
    --- translated = true marks text the caller translated already (a formatted
    --- message); it is shown as it is.
    function M.ShowStatusFeedback(text, kind, seconds, translated)
        if not (f and f.status and f.status.feedbackText and text and text ~= "") then return end
        local feedback = f.status.feedbackText
        local colorKey = FEEDBACK_COLOR_KEYS[kind]
        local color = colorKey and T.colors[colorKey] or T.colors.muted
        f.status._msuf2FeedbackSerial = (f.status._msuf2FeedbackSerial or 0) + 1
        local serial = f.status._msuf2FeedbackSerial
        T.SetTranslatedText(feedback, translated == true and tostring(text) or M.Tr(tostring(text)))
        if feedback.SetTextColor then feedback:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
        feedback:SetAlpha(1)
        if T.PlayMotion then T.PlayMotion(feedback, "controlFocusIn", { fromAlpha = 0.25, toAlpha = 1, duration = 0.10 }) end
        local delay = tonumber(seconds) or 1.4
        local fade = C_Timer.After(delay, function()
            if not (f and f.status and f.status.feedbackText) then return end
            if f.status._msuf2FeedbackSerial ~= serial then return end
            if T.PlayMotion then
                T.PlayMotion(feedback, "controlFocusOut", {
                    fromAlpha = feedback.GetAlpha and feedback:GetAlpha() or 1,
                    toAlpha = 0,
                    duration = 0.16,
                    onFinished = function()
                        if f.status and f.status._msuf2FeedbackSerial == serial then feedback:SetText("") end
                    end,
                })
            else
                feedback:SetAlpha(0)
                feedback:SetText("")
            end
        end)
        if not fade then ClearStatusFeedback() end
    end
    M.ShowInlineFeedback = M.ShowStatusFeedback
end

local function BuildWindowToolbar(state)
    local f, status = state.frame, state.frame.status
    local function RunToolbarSeeNewFeatures()
        if type(M.OpenSeeNewFeatures) == "function" then return M.OpenSeeNewFeatures() end
        if type(M.SelectPage) == "function" then return M.SelectPage("changelog") end
        return false
    end
    local function RunToolbarEditMode()
        if type(M.ToggleDashboardEditMode) == "function" then return M.ToggleDashboardEditMode() end
        if IsEditModeCombatLocked and IsEditModeCombatLocked() then
            M.BlockCombatAction()
            RefreshDashboardEditModeButton()
            return
        end
        local active = IsEditModeActive and IsEditModeActive()
        MSUF.Require("MSUF_SetMSUFEditModeDirect", FILE)(not active)
        RefreshDashboardEditModeButton()
        if f.RefreshStatus then f:RefreshStatus() end
    end
    local toolbarEdit = T.Button(status, "Edit Mode: Off", 152, 24)
    toolbarEdit:SetPoint("BOTTOMRIGHT", status, "BOTTOMRIGHT", -24, 12)
    T.CenterButtonLabel(toolbarEdit)
    toolbarEdit:SetScript("OnClick", RunToolbarEditMode)
    M.RegisterMenuChromeControl(toolbarEdit, "toolbar.edit-mode", "Edit Mode", "action", {
        actionKey = "menu.action.editMode.toggle",
        historyMode = "none", help = "Toggles MSUF Edit Mode.",
    })
    M.dashboardToolbarEditModeButton = toolbarEdit
    local toolbarFeatures = T.Button(status, "See New Features", 132, 24)
    toolbarFeatures:SetPoint("RIGHT", toolbarEdit, "LEFT", -12, 0)
    T.CenterButtonLabel(toolbarFeatures)
    toolbarFeatures:SetScript("OnClick", RunToolbarSeeNewFeatures)
    M.RegisterMenuChromeControl(toolbarFeatures, "toolbar.see-new-features", "See New Features", "ephemeral", {
        historyMode = "none", help = "Opens the full changelog with direct links to highlighted features.",
    })
    -- Blizzard calls out unseen options with NewFeatureLabelTemplate
    -- (Blizzard_SharedXML/NewFeatureLabel.xml) and anchors it left of the game
    -- menu's Options label. The template owns the localized NEW_CAPS text, the
    -- collections-newglow atlas and the pulse, so reusing it - including
    -- Blizzard's scale and offsets - makes the toolbar badge identical to the
    -- one players already know instead of an MSUF lookalike.
    local FEATURES_BADGE_ROOM = 38
    local function RefreshSeeNewFeaturesBadge()
        local unseen = type(M.HasUnseenChangelog) == "function" and M.HasUnseenChangelog() == true
        local badge = toolbarFeatures._msuf2NewBadge
        if unseen and not badge and type(NewFeatureLabelMixin) == "table" then
            badge = PixelLayoutRegion(CreateFrame("Frame", nil, toolbarFeatures, "NewFeatureLabelTemplate"))
            badge:SetScale(0.8)
            badge:SetFrameLevel(toolbarFeatures:GetFrameLevel() + 5)
            toolbarFeatures._msuf2NewBadge = badge
        end
        local label = toolbarFeatures._msuf2Label
        local shown = (unseen and badge and label) and true or false
        -- The badge needs room left of the label, which localized labels have
        -- already eaten at the authored 132: measure first, then reserve.
        local measured = label and label.GetStringWidth and label:GetStringWidth() or 0
        local width = max(132, (type(measured) == "number" and measured > 0) and (measured + 24) or 0)
        toolbarFeatures:SetWidth(shown and (width + FEATURES_BADGE_ROOM) or width)
        if label then
            label:ClearAllPoints()
            label:SetPoint("CENTER", toolbarFeatures, "CENTER", shown and (FEATURES_BADGE_ROOM * 0.5) or 0, 0)
        end
        if badge then
            badge:SetShown(shown)
            if shown then
                badge:ClearAllPoints()
                badge:SetPoint("BOTTOMRIGHT", label, "LEFT", 16, -10)
            end
        end
    end
    M.RefreshSeeNewFeaturesBadge = RefreshSeeNewFeaturesBadge
    RefreshSeeNewFeaturesBadge()
    local toolbarReset = T.Button(status, "Reset page", 88, 24)
    toolbarReset:SetPoint("RIGHT", toolbarFeatures, "LEFT", -12, 0)
    T.CenterButtonLabel(toolbarReset)
    M.AddTooltip(toolbarReset, "Reset page", function()
        local key = M.activeKey
        local route = key and M.GetMenuBreadcrumb(key) or ""
        if route == "" then return nil end
        return M.Format("Resets all settings on %s to their defaults. Asks for confirmation first.", route)
    end, { hook = true })
    toolbarReset:SetScript("OnClick", function()
        local key = M.activeKey
        if key and M.ShowPageResetConfirm and M.PageHasReset and M.PageHasReset(key) then
            M.ShowPageResetConfirm(key)
        end
    end)
    M.RegisterMenuChromeControl(toolbarReset, "toolbar.reset-page", "Reset current page", "action", {
        actionKey = "menu_reset_current_page_prompt",
        confirmRequired = true, historyMode = "none",
        command = { kind = "button", historyMode = "none", confirmRequired = true, set = function()
            local key = M.activeKey
            return key and M.PageHasReset and M.PageHasReset(key) and M.ResetPageToDefaults
                and M.ResetPageToDefaults(key) or false
        end },
    })
    local function RefreshToolbarPageReset()
        local key = M.activeKey
        local shown = key and M.PageHasReset and M.PageHasReset(key)
        toolbarReset:SetShown(shown and true or false)
        if toolbarReset.SetEnabled then toolbarReset:SetEnabled(shown and true or false) end
    end
    M.RefreshToolbarPageReset = RefreshToolbarPageReset
    RefreshToolbarPageReset()
    status.seeNewFeaturesButton = toolbarFeatures
    status.resetPageButton = toolbarReset
    status.editModeButton = toolbarEdit
    InstallWindowFeedback(f)
end

local function InstallWindowStatusRuntime(state)
    local f, status = state.frame, state.frame.status
    local sbProfile, sbEdit = status.profileText, status.editText
    local sbCombat, sbVersion = status.combatText, status.versionText
    local RefreshToolbarPageReset = M.RefreshToolbarPageReset
    local RefreshSeeNewFeaturesBadge = M.RefreshSeeNewFeaturesBadge
    function f:RefreshStatus()
        local profile = tostring(MSUF_ActiveProfile or "Default")
        local profileText = M.Format("Profile: %s", profile)
        SetCachedText(status, "_msuf2ProfileText", sbProfile, profileText)
        -- The Edit Mode button already owns its current state. Reserve status
        -- emphasis for a condition that actually limits the user's next action.
        SetCachedText(status, "_msuf2EditText", sbEdit, "")
        local combatText = InCombatLockdown() and ("|cffef4444" .. L.inCombat .. "|r") or ""
        SetCachedText(status, "_msuf2CombatText", sbCombat, combatText)
        local version = GetAddonVersion()
        local versionText = type(version) == "string" and version ~= ""
            and (version:match("^%d") and ("v" .. version) or version) or ""
        SetCachedText(status, "_msuf2VersionText", sbVersion, versionText)
        RefreshDashboardEditModeButton()
        RefreshToolbarPageReset()
        if RefreshSeeNewFeaturesBadge then RefreshSeeNewFeaturesBadge() end
    end
    local STATUS_EVENTS = {
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE",
        "PLAYER_ENTERING_WORLD", "PLAYER_DIFFICULTY_CHANGED",
        "PLAYER_SPECIALIZATION_CHANGED", "UPDATE_BINDINGS",
    }
    local function SetStatusEventsRegistered(registered)
        if (status._msuf2EventsRegistered == true) == (registered == true) then return end
        status._msuf2EventsRegistered = registered and true or nil
        local method = registered and status.RegisterEvent or status.UnregisterEvent
        for i = 1, #STATUS_EVENTS do method(status, STATUS_EVENTS[i]) end
    end
    status:SetScript("OnEvent", function(_, event)
        if not (f and f:IsShown()) then
            SetStatusEventsRegistered(false)
            return
        end
        if event == "PLAYER_REGEN_DISABLED" then
            -- The event marks the combat edge before the lockdown starts, so
            -- the teardown below (history commit, runtime quiesce) refuses too.
            M.BlockCombatAction(event)
            M.HideSlashMenuAndMinibar(f)
            return
        elseif event == "PLAYER_REGEN_ENABLED" and M.activeKey == "search" then
            RefreshSearchResultsPage()
        end
        f:RefreshStatus()
        M.RequestOrRefresh(nil, event or "menu-status-event")
        RequestBossPagePreviewForKey(M.activeKey)
        RequestGroupPagePreviewForKey(M.activeKey)
    end)
    state.SetStatusEventsRegistered = SetStatusEventsRegistered
end

local function InstallWindowLifecycle(state)
    local f = state.frame
    local SetStatusEventsRegistered = state.SetStatusEventsRegistered
    f:SetScript("OnShow", function(self)
        if M.BlockCombatAction and M.BlockCombatAction() then
            self:Hide()
            return
        end
        -- A monotonic, runtime-only token lets expensive-setting warnings show
        -- once per real Menu2 visit without persisting acknowledgement state.
        M._msuf2MenuSessionSerial = (tonumber(M._msuf2MenuSessionSerial) or 0) + 1
        if type(MenuRuntime.Resume) == "function" then MenuRuntime:Resume("menu-show") end
        self._msuf2Closing = nil
        if self.SetAlpha then self:SetAlpha(1) end
        ApplyMenuFramePriority(self)
        M.RefreshWindowControls(self)
        self._msuf2Minimized = nil
        if M.minimizedBar and M.minimizedBar.Hide then M.minimizedBar:Hide() end
        M.StartHistorySession("menu")
        SetStatusEventsRegistered(true)
        EnsureEditModeUIHook()
        if self.RefreshStatus then self:RefreshStatus() end
        if M.scrollFrame and M.scrollFrame._msuf2RefreshScrollBar then M.scrollFrame:_msuf2RefreshScrollBar() end
        local activeEntry = M.activeKey and M.cache and M.cache[M.activeKey]
        M.SetActivePageHeader(activeEntry)
        if activeEntry then QueueVisiblePageLayoutSettle(M.activeKey, activeEntry) end
        M.RefreshGuidedTourChrome("WINDOW_SHOW")
        M.ResumePinnedPreviews("WINDOW_SHOW")
        M.ResumeClassPowerPreview("WINDOW_SHOW", M.activeKey)
        M.ResumeGFNativePreviews("WINDOW_SHOW", M.activeKey)
        -- Reopening the window is a page-show for the docked previews too: the
        -- window frame is visible here, so their ownership gates pass again.
        M.RunStickyHeaderActivation()
        if activeEntry and M.ShouldExpandFixedPreview() then
            M.RestoreFixedPreview(M.activeKey, activeEntry, {
                reason = "WINDOW_SHOW_DEFAULT_EXPANDED",
            })
        end
        RequestBossPagePreviewForKey(M.activeKey)
        RequestGroupPagePreviewForKey(M.activeKey)
        M.UpdateMenuCombatListener()
    end)
    f:SetScript("OnHide", function()
        M.ClearPendingFixedPreviewExpansion()
        M.SetActivePageHeader(nil)
        M.HideLayerOverview()
        if M.StopWindowLayoutAnimation then M.StopWindowLayoutAnimation(f) end
        if f._msuf2CancelWindowInteractions then
            f:_msuf2CancelWindowInteractions()
        end
        if f._msuf2Closing then ResetWindowState(f, true) end
        SetStatusEventsRegistered(false)
        -- The dropdown and its focus veil are UIParent-owned modal surfaces.
        -- They must be torn down synchronously when their menu owner disappears;
        -- an animated close can otherwise outlive the hidden window and veil the
        -- cached page when it is shown again.
        if W then W.CloseDropdown({ immediate = true }) end
        M.HideNavSearchPalette()
        M.HideMenuPreviewPopups()
        M.HideMenuCopyLinkPopup()
        if W and type(W.CloseMenuOwnedColorPicker) == "function" then W.CloseMenuOwnedColorPicker() end
        M.ResetFocusVeil(nil, { force = true })
        M.EndHistorySession("menu")
        ResetStatusIndicatorTestModeOnMenuExit()
        SavePersistentMenuState()
        ResetBossPagePreviewCache()
        M.SuspendPinnedPreviews("WINDOW_HIDE")
        M.ReleaseGFNativePreviews("WINDOW_HIDE", nil)
        -- Force: ResetBossPagePreviewCache just cleared lastCastbarPagePreviewUnit,
        -- so the castbar-page fake cast would dedupe against nil and never be
        -- stopped when the window closes straight from the castbar page.
        SyncBossPagePreviewForKey(nil, true)
        RequestGroupPagePreviewForKey(nil)
        M.UpdateMenuCombatListener()
        if type(MenuRuntime.Quiesce) == "function" then
            local reason = M.IsConfigCombatLocked and M.IsConfigCombatLocked() and "combat" or "menu-hide"
            MenuRuntime:Quiesce(reason)
        end
        f._msuf2Closing = nil
    end)
end


-- Explicit load-time exports for the following responsibility modules.
Parts.BuildWindowChrome = BuildWindowChrome
Parts.BuildWindowShell = BuildWindowShell
Parts.BuildWindowToolbar = BuildWindowToolbar
Parts.InstallMenuScaleControl = InstallMenuScaleControl
Parts.InstallWindowLifecycle = InstallWindowLifecycle
Parts.InstallWindowStatusRuntime = InstallWindowStatusRuntime
