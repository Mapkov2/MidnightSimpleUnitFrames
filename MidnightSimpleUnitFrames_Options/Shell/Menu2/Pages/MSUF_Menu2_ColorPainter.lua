local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local C_Timer = M.MenuTimer or _G.C_Timer

-- The Color Painter deliberately owns no renderer. It embeds the same unit and
-- group preview objects used by their normal pages, then adds menu-only click
-- targets for colors. Keeping one renderer per frame type prevents the Colors
-- page from drifting away from live frame geometry, textures, auras or bars.
local W = M.Widgets
local T = M.Theme
local P = M.ColorPainter or {}
M.ColorPainter = P
local AP = M.AdvancedPage or {}
local ControlMeta, RegisterControl = M.Pick(AP, [[ControlMeta RegisterControl]])
local floor, max, min = math.floor, math.max, math.min
local Tr = M.TranslateText or M.Tr or function(text) return text end

local function Label(parent, text, x, y, width, color, template)
    local fs = T.Font(parent, template or "GameFontHighlightSmall", Tr(text), color or T.colors.text)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if width then fs:SetWidth(width); fs:SetJustifyH("LEFT") end
    return fs
end

local function RequestPreview(box, reason)
    if not (box and box.IsShown and box:IsShown()) then return end
    if type(box.RequestRefresh) == "function" then box:RequestRefresh(reason or "MSUF2_COLOR_PAINTER")
    elseif type(box.Refresh) == "function" then box:Refresh(reason or "MSUF2_COLOR_PAINTER") end
end

local function HidePreviewEditorChrome(box, surface, sidebar, zoomBar, animationButton)
    if box then
        box._msuf2ColorPainterHideSelectionChrome = true
        if M.PreviewSelectionBar and M.PreviewSelectionBar.SetShown then
            M.PreviewSelectionBar.SetShown(box, false)
        end
    end
    if sidebar then sidebar:Hide() end
    if box and box._msuf2LayersButton then box._msuf2LayersButton:Hide() end
    -- Color previews use the normal UF/GF renderer, so keep its existing zoom
    -- controls available here as well. Only editing chrome (layers, handles,
    -- animation and help hints) is suppressed on this color-only surface.
    if zoomBar then zoomBar:Show() end
    if animationButton then animationButton:Hide() end
    if box and box._msuf2PreviewControlsHint then box._msuf2PreviewControlsHint:Hide() end
    if surface then
        surface:ClearAllPoints()
        surface:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -30)
        surface:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)
    end
end

-- Keep every preview-only mouse surface well below Menu2 popup level 120.
-- Element specificity only needs a few local levels; using the raw 0..90
-- priority here previously placed invisible hit targets over the color picker.
local COLOR_SHIELD_LEVEL = 40
local COLOR_TARGET_LEVEL = 50
-- The zoom bar starts 8 px below the canvas top, is 24 px high, and its
-- background selector hangs another 4 + 20 px below it. Keep the shield below
-- that complete 56 px cluster after the canvas' 30 px Color Painter inset.
local COLOR_SHIELD_TOP_INSET = 90

local function ForwardMenuScrollWheel(frame)
    if not (frame and frame.EnableMouseWheel and frame.SetScript) then return end
    frame:EnableMouseWheel(true)
    if frame.SetPropagateMouseWheel then frame:SetPropagateMouseWheel(false) end
    frame:SetScript("OnMouseWheel", function(_, delta)
        if type(M.ForwardMenuScrollWheel) == "function" then M.ForwardMenuScrollWheel(delta) end
    end)
end

local function InstallColorOnlyShield(parent)
    local shield = CreateFrame("Button", nil, parent)
    -- Leave the top strip of every preview panel uncovered: that is where the
    -- zoom clusters live, and the shield must never eat their clicks. All
    -- other interactive preview surfaces up there are explicitly disabled.
    shield:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -COLOR_SHIELD_TOP_INSET)
    shield:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    shield:EnableMouse(true)
    shield:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp")
    local popupLevel = tonumber(M.MENU_POPUP_FRAME_LEVEL) or 120
    shield:SetFrameLevel(min((parent:GetFrameLevel() or 0) + COLOR_SHIELD_LEVEL, popupLevel - 20))
    ForwardMenuScrollWheel(shield)
    shield:SetScript("OnClick", function() end)
    return shield
end

local function HideGroupPreviewIcons(box)
    if not box then return end
    box._selectedHandle = nil
    if box.EnableKeyboard then box:EnableKeyboard(false) end
    for _, surface in ipairs({ box._stage, box._mock or box.mock, box._dragFrame }) do
        if surface then
            if surface.EnableMouse then surface:EnableMouse(false) end
            if surface.EnableMouseWheel then surface:EnableMouseWheel(false) end
        end
    end
    for _, handle in pairs(box._handles or {}) do
        if handle then
            handle:Hide()
            if handle.EnableMouse then handle:EnableMouse(false) end
        end
    end
end

local function DisableUnitPreviewEditing(box)
    if not box then return end
    box._selectedHandle = nil
    if box.EnableKeyboard then box:EnableKeyboard(false) end
    if box.canvas then
        if box.canvas.EnableMouse then box.canvas:EnableMouse(false) end
        if box.canvas.EnableMouseWheel then box.canvas:EnableMouseWheel(false) end
    end
    if box.dragFrame then
        box.dragFrame:Hide()
        if box.dragFrame.EnableMouse then box.dragFrame:EnableMouse(false) end
    end
    if box.mock and box.mock.cast and box.mock.cast.EnableMouse then box.mock.cast:EnableMouse(false) end
    for i = 1, #(box.handles or {}) do
        local handle = box.handles[i]
        if handle then
            if handle.EnableMouse then handle:EnableMouse(false) end
            if handle.EnableKeyboard then handle:EnableKeyboard(false) end
        end
    end
end

local function MakeUnitPreview(parent, ctx, width, unitKey, displayName)
    local create = MSUF.MSUF_Menu2_CreateUnitPreviewBox or _G.MSUF_Menu2_CreateUnitPreviewBox
    if type(create) ~= "function" then return nil end
    unitKey = unitKey or "player"
    displayName = displayName or unitKey
    local panel = CreateFrame("Frame", nil, parent)
    panel._msufLastApplyKey = unitKey
    panel._msufGetCurrentKey = function() return unitKey end
    panel._msufIsFramesTab = function() return true end
    panel._msufOpenUnitSection = function() end
    panel._msufAPI = {
        ApplySettingsForKey = function()
            local service = M.ApplyService
            if service and type(service.RequestUnit) == "function" then service.RequestUnit(unitKey, "visual", "MSUF2_COLOR_PAINTER") end
        end,
    }
    local box = create(parent, panel, width, 132)
    if not box then return nil end
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    box._msufPanel = panel
    box._msuf2ColorPainterUnitKey = unitKey
    box._msuf2ColorPainterUnitLabel = displayName
    box._msuf2PinnedPreviewPageKey = ctx and ctx.key
    box._msuf2PinnedPreviewWrapper = ctx and ctx.wrapper
    box._msuf2UnitPageHostShown = function()
        return (not M.activeKey or not ctx or not ctx.key or M.activeKey == ctx.key)
            and parent:IsShown()
    end
    if type(box.ApplyCompactPreviewPresentation) == "function" then box:ApplyCompactPreviewPresentation(true) end
    box:SetHeight(132)
    if box.title then box.title:Hide() end
    if box.hint then box.hint:Hide() end
    box._msuf2ColorPainterTitle = Label(box, displayName, 12, -8, width - 24, T.colors.title or T.colors.text, "GameFontNormal")
    if type(box.layerVisibility) == "table" then
        box.layerVisibility.guides = false
        box.layerVisibility.bounds = false
    end
    HidePreviewEditorChrome(box, box.canvas, box.sidebar, box.zoomBar, box.animateCombatButton)
    DisableUnitPreviewEditing(box)
    return box
end

local function MakeGroupPreview(parent, ctx, width)
    local groupPreview = M.GroupPreview
    local create = groupPreview and groupPreview.CreateNative
    if type(create) ~= "function" then return nil end
    local previewCtx = { width = width + 28, key = ctx and ctx.key, wrapper = ctx and ctx.wrapper }
    local box = create(parent, previewCtx, groupPreview.OpenSection)
    if not box then return nil end
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    box._msufGFNativePreviewPageKey = ctx and ctx.key
    box._msufGFNativePreviewWrapper = ctx and ctx.wrapper
    box._msufGFPreviewHostShown = function()
        return (not M.activeKey or not ctx or not ctx.key or M.activeKey == ctx.key)
            and parent:IsShown()
    end
    if type(box.ApplyCompactPreviewPresentation) == "function" then box:ApplyCompactPreviewPresentation(true) end
    box:SetHeight(132)
    if box._title then box._title:Hide() end
    if box._hint then box._hint:Hide() end
    box._msuf2ColorPainterTitle = Label(box, "Group", 12, -8, width - 24, T.colors.title or T.colors.text, "GameFontNormal")
    if type(box.layerVisibility) == "table" then
        box.layerVisibility.guides = false
        box.layerVisibility.bounds = false
    end
    HidePreviewEditorChrome(box, box._stage, box._layers, box._zoomBar, box._previewAnimationButton)
    local baseRefresh = box.Refresh
    if type(baseRefresh) == "function" then
        box.Refresh = function(self, ...)
            local result = baseRefresh(self, ...)
            HideGroupPreviewIcons(self)
            return result
        end
    end
    HideGroupPreviewIcons(box)
    return box
end

local UNIT_FOCUS = {
    unit = { body = true, nameText = true, hpText = true, powerText = true, portrait = true, power = true, texLayer = true },
    cast = { castbar = true },
    auras = { auras = true },
    resources = { power = true, classPower = true },
}
local COLOR_FIT_CATEGORIES = { cast = true, auras = true }
local function SwitchColorPreviewCamera(box, category)
    if not box or box._msuf2ColorPainterCameraCategory == category then return end
    local states = box._msuf2ColorPainterCameraStates
    if type(states) ~= "table" then
        states = {}
        box._msuf2ColorPainterCameraStates = states
    end
    local previous = box._msuf2ColorPainterCameraCategory
    if previous then
        states[previous] = {
            initialized = true,
            manualZoom = tonumber(box._manualZoom),
            panX = tonumber(box._zoomPanX) or 0,
            panY = tonumber(box._zoomPanY) or 0,
            defaultLockPending = box._msuf2ZoomLockDefaultPending == true,
        }
    end
    local nextState = states[category]
    if nextState and nextState.initialized then
        box._manualZoom = nextState.manualZoom
        box._zoomPanX, box._zoomPanY = nextState.panX or 0, nextState.panY or 0
        box._msuf2ZoomLockDefaultPending = nextState.defaultLockPending and true or nil
    elseif COLOR_FIT_CATEGORIES[category] then
        -- Castbars and aura lanes can sit outside the unit-frame rectangle.
        -- Start those color-only views in Fit so the renderer centers and
        -- scales their complete footprint inside the clipped 132px host.
        box._manualZoom = nil
        box._zoomPanX, box._zoomPanY = 0, 0
        box._msuf2ZoomLockDefaultPending = nil
    end
    box._msuf2ColorPainterCameraCategory = category
end
local CATEGORY_SECTION = {
    unit = "colors_appearance",
    group = "colors_group_frames",
    cast = "colors_castbar",
    auras = "colors_auras",
    resources = "colors_power",
}
-- Sections whose colors depend on a selector (text-color modes, Power type,
-- Class Resource type): preview clicks NAVIGATE to the section instead of
-- opening the paint picker, because the picker cannot show which token or
-- mode the painted color would actually edit. An armed palette brush still
-- paints the section's primary color directly.
local NAVIGATE_ONLY_SECTIONS = {
    colors_font = "Opens the shared Text Colors settings below - color modes for name, HP and power text.",
    colors_power = "Opens the Resources colors below - pick the power type there, then set its color.",
    colors_class_power = "Opens the Resources colors below - pick the Class Resource there, then set its colors.",
}

local function FocusUnitPreview(box, category)
    if not (box and type(box.layerVisibility) == "table") then return end
    SwitchColorPreviewCamera(box, category)
    -- A color sample must remain inspectable even when the corresponding live
    -- feature is disabled or has no configured lanes. These flags are read by
    -- the menu-only renderer and never reach runtime frames or SavedVariables.
    box._msuf2ColorPainterForceCastbar = category == "cast" or nil
    box._msuf2ColorPainterForceAuras = category == "auras" or nil
    local wanted = UNIT_FOCUS[category] or UNIT_FOCUS.unit
    for key in pairs(box.layerVisibility) do
        box.layerVisibility[key] = wanted[key] == true
    end
    box.layerVisibility.guides = false
    box.layerVisibility.bounds = false
    for i = 1, #(box.layerButtons or {}) do
        local button = box.layerButtons[i]
        if button and type(button.refresh) == "function" then button:refresh() end
    end
    RequestPreview(box, "MSUF2_COLOR_PAINTER_FOCUS")
end

local function ResolveCategoryAnchors(unitBoxes, groupBox, categoryKey)
    local function Target(anchor, sectionId, label, priority, ownerLabel)
        if not anchor then return nil end
        return { anchor = anchor, sectionId = sectionId, label = label, priority = priority or 0, ownerLabel = ownerLabel }
    end
    local function FillAnchor(bar)
        if bar and bar.GetStatusBarTexture then return bar:GetStatusBarTexture() or bar end
        return bar
    end
    local result = {}
    local function Add(anchor, sectionId, label, priority, ownerLabel)
        local value = Target(anchor, sectionId, label, priority, ownerLabel)
        if value then result[#result + 1] = value end
    end
    if categoryKey == "group" then
        local groupMock = groupBox and (groupBox._mock or groupBox.mock)
        Add(groupMock, "colors_group_frames", "Group Frame Colors", 0, "Health bar color")
        Add(groupMock and groupMock._power, "colors_power", "Power Bar Colors", 20, "Color")
        Add(groupMock and FillAnchor(groupMock._healPred), "colors_bar_colors", "Positive Heal Prediction", 40, "Positive Heal Prediction")
        Add(groupMock and FillAnchor(groupMock._absorb), "colors_bar_colors", "Absorb Overlay", 50, "Absorb Bar Color")
        Add(groupMock and FillAnchor(groupMock._healAbsorb), "colors_bar_colors", "Heal-Absorb (Negative)", 60, "Heal-Absorb / Negative Heal")
        Add(groupMock and groupMock._nameFS, "colors_font", "Name Text Color", 80, "Global font color")
        Add(groupMock and groupMock._hpLeftFS, "colors_font", "Health Text Color", 90, "Global font color")
        Add(groupMock and groupMock._hpCenterFS, "colors_font", "Health Text Color", 90, "Global font color")
        Add(groupMock and groupMock._hpRightFS, "colors_font", "Health Text Color", 90, "Global font color")
        Add(groupMock and groupMock._powerLeftFS, "colors_font", "Power Text Color", 90, "Global font color")
        Add(groupMock and groupMock._powerCenterFS, "colors_font", "Power Text Color", 90, "Global font color")
        Add(groupMock and groupMock._powerRightFS, "colors_font", "Power Text Color", 90, "Global font color")
        return result
    end
    for i = 1, #(unitBoxes or {}) do
        local unitBox = unitBoxes[i]
        local mock = unitBox and unitBox.mock
        if mock then
            local unitLabel = unitBox._msuf2ColorPainterUnitLabel
            local function LabelFor(label)
                return unitLabel and (unitLabel .. ": " .. label) or label
            end
            if categoryKey == "unit" then
                Add(mock.hpBG or mock, "colors_appearance", LabelFor("Unitframe Global Coloring"), 0, "Unified bar color")
                Add(mock.powerBG or mock.power, "colors_power", LabelFor("Power Bar Colors"), 20, "Color")
                Add(mock.detachedPower, "colors_power", LabelFor("Detached Power Bar Colors"), 25, "Color")
                Add(mock.portrait, "colors_portrait", LabelFor("Portrait Colors"), 30, "Border custom color")
                Add(mock.healPred, "colors_bar_colors", LabelFor("Positive Heal Prediction"), 40, "Positive Heal Prediction")
                Add(mock.absorb, "colors_bar_colors", LabelFor("Absorb Overlay"), 50, "Absorb Bar Color")
                Add(mock.healAbsorb, "colors_bar_colors", LabelFor("Heal-Absorb (Negative)"), 60, "Heal-Absorb / Negative Heal")
                Add(mock.nameText, "colors_font", LabelFor("Name Text Color"), 80, "Global font color")
                Add(mock.raidGroupNameText, "colors_font", LabelFor("Name Text Color"), 80, "Global font color")
                Add(mock.totInlineText, "colors_font", LabelFor("Name Text Color"), 80, "Global font color")
                Add(mock.hpTextLeft, "colors_font", LabelFor("Health Text Color"), 90, "Global font color")
                Add(mock.hpTextCenter, "colors_font", LabelFor("Health Text Color"), 90, "Global font color")
                Add(mock.hpText, "colors_font", LabelFor("Health Text Color"), 90, "Global font color")
                Add(mock.hpTextPct, "colors_font", LabelFor("Health Text Color"), 90, "Global font color")
                Add(mock.powerTextLeft, "colors_font", LabelFor("Power Text Color"), 90, "Global font color")
                Add(mock.powerTextCenter, "colors_font", LabelFor("Power Text Color"), 90, "Global font color")
                Add(mock.powerText, "colors_font", LabelFor("Power Text Color"), 90, "Global font color")
                Add(mock.powerTextPct, "colors_font", LabelFor("Power Text Color"), 90, "Global font color")
            elseif categoryKey == "cast" then
                Add(mock.cast, "colors_castbar", LabelFor("Castbar Colors"), 30, "Interruptible cast color")
            elseif categoryKey == "auras" then
                Add(unitBox.handleAuraBuffs, "colors_auras", LabelFor("Aura Colors"), 30, "Magic color")
                Add(unitBox.handleAuraDebuffs, "colors_auras", LabelFor("Aura Colors"), 30, "Magic color")
            elseif categoryKey == "resources" then
                Add(mock.powerBG or mock.power, "colors_power", LabelFor("Power Bar Colors"), 20, "Color")
                Add(mock.detachedPower, "colors_power", LabelFor("Detached Power Bar Colors"), 25, "Color")
                Add(mock.classPower, "colors_class_power", LabelFor("Class Power Colors"), 30, "Color")
            end
        end
    end
    return result
end

-- Click targets are rebuilt on every category show and WoW can never destroy
-- frames, so released targets cycle through this pool instead of leaking a
-- fresh Button plus highlight texture per rebuild.
local clickTargetPool = {}
local function ReleaseClickTargets(targets)
    for i = 1, #targets do
        local target = targets[i]
        target:Hide()
        clickTargetPool[#clickTargetPool + 1] = target
    end
end
local function AddClickTarget(host, anchor, onClick, onRightClick, label, priority, panDelegate, tooltipText, levelAnchor)
    if not (host and anchor and type(onClick) == "function") then return nil end
    local button = table.remove(clickTargetPool)
    if button then
        button:SetParent(host)
        button:ClearAllPoints()
        button:SetAllPoints(anchor)
        button:Show()
    else
        button = CreateFrame("Button", nil, host)
        button:SetAllPoints(anchor)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    if button.SetFrameLevel and host.GetFrameLevel then
        local localPriority = floor((tonumber(priority) or 0) / 10)
        local targetBase
        if levelAnchor and levelAnchor.GetFrameLevel then
            -- Anchor to the shield: pinning reparents the host and lifts the
            -- whole subtree, so absolute caps would strand rebuilt targets
            -- BELOW the shield (first click works, every later one is eaten).
            targetBase = (levelAnchor:GetFrameLevel() or 0) + 11
        else
            local popupLevel = tonumber(M.MENU_POPUP_FRAME_LEVEL) or 120
            targetBase = min((host:GetFrameLevel() or 0) + COLOR_TARGET_LEVEL, popupLevel - 19)
        end
        button:SetFrameLevel(targetBase + localPriority)
    end
    if not button._msuf2ClickTargetWired then
        button._msuf2ClickTargetWired = true
        local hover = button:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(0.18, 0.66, 1, 0.18)
    end
    button:EnableMouseWheel(true)
    if button.SetPropagateMouseWheel then button:SetPropagateMouseWheel(false) end
    button:SetScript("OnMouseWheel", function(_, delta)
        -- Paint hit targets cover the native preview canvas. Delegate first so
        -- Ctrl+wheel retains preview zoom; the canvas routes a plain tick to the
        -- page scroller itself. A non-preview target falls back centrally.
        if type(panDelegate) == "function" and panDelegate("OnMouseWheel", delta) then return end
        if type(M.ForwardMenuScrollWheel) == "function" then M.ForwardMenuScrollWheel(delta) end
    end)
    if M.AddTooltip then
        M.AddTooltip(button, label,
            tooltipText or Tr("Click to edit these colors. Right-click opens the matching section below."),
            { owner = "ANCHOR_CURSOR" })
    end
    -- Ctrl+drag (and middle-drag) over a click target must pan the preview
    -- canvas underneath instead of opening the paint picker.
    if type(panDelegate) == "function" then
        button:SetScript("OnMouseDown", function(_, mouseButton)
            if (mouseButton == "LeftButton" and IsControlKeyDown and IsControlKeyDown())
                or mouseButton == "MiddleButton" then
                panDelegate("OnMouseDown", mouseButton)
            end
        end)
        button:SetScript("OnMouseUp", function(_, mouseButton)
            panDelegate("OnMouseUp", mouseButton)
        end)
    end
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "LeftButton" and IsControlKeyDown and IsControlKeyDown() then return end
        if mouseButton == "RightButton" and type(onRightClick) == "function" then
            onRightClick(self)
            return
        end
        onClick(self)
    end)
    return button
end

function P.Build(ctx, builder, categories)
    if not (ctx and builder and type(categories) == "table" and #categories > 0) then return nil end
    local valid = {}
    local selectorValues = {}
    for i = 1, #categories do
        local category = categories[i]
        valid[category.key] = true
        selectorValues[i] = { value = category.key, text = category.shortTitle or category.title }
    end
    local function Current() return valid[M.colorsPainterCategory] and M.colorsPainterCategory or categories[1].key end
    local ShowCategory

    -- Category choice is page navigation, not preview chrome.  Keep it outside
    -- the collapsible preview so the active settings remain reachable even
    -- when the preview is closed or temporarily pinned.
    local pageW = tonumber(builder.width) or tonumber(ctx.width) or 720
    local selectorOpts = {
        values = selectorValues,
        width = pageW,
        label = "Editing:",
        labelWidth = 64,
        centerY = -27,
        getValue = Current,
        setValue = function(value)
            if ShowCategory then ShowCategory(value) end
        end,
    }
    local selectorMetrics = W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(selectorValues, selectorOpts)
    local selectorH = max(54, math.abs((selectorMetrics and selectorMetrics.bottomY) or -39) + 14)
    local selector = (T.Panel and T.Panel(builder.parent, nil, T.colors.glassStatus or T.colors.header, T.colors.borderSoft))
        or CreateFrame("Frame", nil, builder.parent)
    if T.ApplySurface then T.ApplySurface(selector, "status") end
    selector:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", builder.x, builder.y)
    selector:SetSize(pageW, selectorH)
    selector._msuf2Width = pageW
    builder.y = builder.y - selectorH - 8
    if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(builder.y) + 28) end
    if W.RegisterGuidedRegion then W.RegisterGuidedRegion(ctx, selector, "Color editing category", "colors_scope") end
    local categoryBar = W.ScopeOverrideBar and W.ScopeOverrideBar(ctx, selector, selectorOpts)
    RegisterControl(categoryBar,
        ControlMeta("opt_colors", "advanced", "preview.scope.selector", "ephemeral"),
        "Editing", "segment", selectorValues)
    if categoryBar and categoryBar.buttons and M.AddTooltip then
        for i = 1, #categories do
            local category = categories[i]
            M.AddTooltip(categoryBar.buttons[i], Tr(category.title or category.shortTitle or ""),
                Tr(category.subtitle or ""), { hook = true })
        end
    end
    if W.AttachStickyPageHeader then
        W.AttachStickyPageHeader(selector, {
            pageKey = ctx and ctx.key,
            wrapper = ctx and ctx.wrapper,
            gap = 4,
            builder = builder,
            ctx = ctx,
            flowGap = 8,
        })
    end

    local section, _, fixedPreview = W.FixedPreviewSection(ctx, builder, {
        title = "Color Preview",
        height = 180,
    })
    -- Palette and usage guidance belong to the settings flow. Keeping them out
    -- of the fixed shell leaves that slot exclusively to the compact preview.
    local paletteSection = builder:Section("Quick Palette", 82)
    local width = section._msuf2Width or ctx.width or 720
    local innerW = width - 32

    local previewW = innerW
    local host = CreateFrame("Frame", nil, section)
    host:SetPoint("TOPLEFT", section, "TOPLEFT", 16, -38)
    host:SetSize(previewW, 132)
    -- Native preview elements can extend beyond their canvas while zoomed or
    -- panned. The paint buttons mirror those element bounds at a high frame
    -- level, so without a hard owner boundary an invisible target can reach
    -- into the navigation rail and intercept its hover/clicks.
    if host.SetClipsChildren then host:SetClipsChildren(true) end
    local shield = InstallColorOnlyShield(host)

    -- Zoom chrome is noise for a color task: keep the controls functional but
    -- fade them in only while the pointer is over the preview.
    local zoomBars = {}
    -- Keep the zoom clusters strictly above the shield and the paint click
    -- targets. Levels are taken relative to the shield itself (no host math,
    -- no popup caps) and re-asserted on every tab switch, because preview
    -- internals may re-level their chrome during refreshes.
    local function RaiseZoomBar(bar)
        if bar and bar.SetFrameLevel and shield and shield.GetFrameLevel then
            local level = (shield:GetFrameLevel() or 0) + 30
            bar:SetFrameLevel(level)
            -- The preview background selector hangs below the zoom bar. The
            -- bar is re-leveled after construction on this paint surface, so
            -- explicitly carry its child above the mouse-catching shield too.
            local backgroundButton = bar._msuf2PreviewBackgroundButton
            if backgroundButton and backgroundButton.SetFrameLevel then
                backgroundButton:SetFrameLevel(level + 1)
            end
        end
    end
    local function RaiseZoomBars()
        for i = 1, #zoomBars do RaiseZoomBar(zoomBars[i]) end
    end
    local function CollectZoomBar(bar)
        if not bar then return end
        zoomBars[#zoomBars + 1] = bar
        RaiseZoomBar(bar)
        local backgroundButton = bar._msuf2PreviewBackgroundButton
        if backgroundButton and backgroundButton.HookScript and not backgroundButton._msuf2ColorPainterRevealHooked then
            backgroundButton._msuf2ColorPainterRevealHooked = true
            backgroundButton:HookScript("OnEnter", function()
                if bar.SetAlpha then bar:SetAlpha(1) end
            end)
        end
    end
    local function SetZoomChromeShown(shown)
        for i = 1, #zoomBars do
            local bar = zoomBars[i]
            if bar.SetAlpha then bar:SetAlpha(shown and 1 or 0) end
        end
    end
    if shield and shield.HookScript then
        shield:HookScript("OnEnter", function() SetZoomChromeShown(true) end)
        shield:HookScript("OnLeave", function()
            if C_Timer and C_Timer.After then
                C_Timer.After(0.30, function()
                    if not (host.IsMouseOver and host:IsMouseOver()) then SetZoomChromeShown(false) end
                end)
            end
        end)
    end

    local unitGap = 8
    local unitPreviewW = max(1, floor((previewW - unitGap) * 0.5))
    -- The Player/Target boxes are the default tab's content, but their host is
    -- a fixed 132px frame, so creating them one deferred refresh later (see
    -- EnsureUnitBoxes below) never moves layout. Only when no deferred refresh
    -- can follow do they build synchronously.
    local unitBoxes = {}
    local unitBoxesBuilt = false
    local EnsureUnitBoxes
    -- The group tab shows one full-width native preview. Like the castbar
    -- panel it is built lazily on first activation of its tab; the default
    -- unit tab must not pay for the native group frame preview.
    local groupBox
    local groupPreviewAvailable = type((M.GroupPreview or {}).CreateNative) == "function"
    local unitPreviewAvailable = type(MSUF.MSUF_Menu2_CreateUnitPreviewBox or _G.MSUF_Menu2_CreateUnitPreviewBox) == "function"
    if not unitPreviewAvailable and not groupPreviewAvailable then Label(host, "Preview renderer is unavailable.", 12, -12, previewW - 24, T.colors.muted) end
    SetZoomChromeShown(false)

    -- The color preview keeps zoom/pan but intentionally no layout editing,
    -- so the "?" help must describe this surface instead of the full editor.
    local PAINTER_HELP_LINES = {
        "Click a colored element to edit exactly its colors.",
        "Right-click an element to open its section below.",
        "Ctrl + mouse wheel zooms. Ctrl + drag pans. Fit recenters.",
        "Right-click any color swatch below to reset it to default.",
        "Layout editing lives on the Player/Target and Party/Raid pages.",
    }
    local function RewirePreviewHelp(helpButton)
        local helpers = M.PreviewHelpers
        if not (helpButton and helpers and type(helpers.ShowPreviewControlsHelp) == "function") then return end
        helpButton:SetScript("OnClick", function(self)
            local lines = {}
            for i = 1, #PAINTER_HELP_LINES do lines[i] = Tr(PAINTER_HELP_LINES[i]) end
            helpers.ShowPreviewControlsHelp(self, { M = M, T = T, W = W, Tr = Tr, lines = lines })
        end)
    end
    -- The castbar tab shows one full-width panel instead of two half panels;
    -- built lazily on first activation of the tab.
    local castBox
    local function EnsureCastBox()
        if castBox == nil then
            castBox = MakeUnitPreview(host, ctx, previewW, "target", "Target") or false
            if castBox then
                castBox:ClearAllPoints()
                castBox:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                CollectZoomBar(castBox.zoomBar)
                if castBox.zoomBar and castBox.zoomBar.SetAlpha then castBox.zoomBar:SetAlpha(0) end
                RewirePreviewHelp(castBox.zoomHelpButton)
                castBox:Hide()
            end
        end
        return castBox or nil
    end

    local function EnsureGroupBox()
        if groupBox == nil then
            groupBox = MakeGroupPreview(host, ctx, previewW) or false
            if groupBox then
                CollectZoomBar(groupBox._zoomBar)
                if groupBox._zoomBar and groupBox._zoomBar.SetAlpha then groupBox._zoomBar:SetAlpha(0) end
                RewirePreviewHelp(groupBox._zoomHelpButton)
                groupBox:Hide()
            end
        end
        return groupBox or nil
    end

    local function WireUnitBox(box)
        CollectZoomBar(box.zoomBar)
        if box.zoomBar and box.zoomBar.SetAlpha then box.zoomBar:SetAlpha(0) end
        RewirePreviewHelp(box.zoomHelpButton)
    end
    -- Each preview box costs a comparable slice of the entry frame, so the
    -- Target box builds one short tick after Player instead of in the same
    -- frame. The late box re-runs the category pass to pick up its
    -- shown-state, click targets, and first render; a hidden page skips that
    -- sync and the next visible refresh covers it. targetBoxPending stays the
    -- resume marker: if combat quiescence cancels the tracked timer, the next
    -- EnsureUnitBoxes call finishes the pair synchronously.
    local targetBoxPending = false
    local function AddTargetBox()
        targetBoxPending = false
        local targetBox = MakeUnitPreview(host, ctx, unitPreviewW, "target", "Target")
        if not targetBox then return end
        targetBox:ClearAllPoints()
        targetBox:SetPoint("TOPLEFT", host, "TOPLEFT", unitPreviewW + unitGap, 0)
        unitBoxes[#unitBoxes + 1] = targetBox
        WireUnitBox(targetBox)
        if not (ctx and ctx.wrapper and ctx.wrapper.IsShown and not ctx.wrapper:IsShown()) then
            ShowCategory(Current())
            RequestPreview(targetBox, "MSUF2_COLOR_PAINTER_TARGET_BOX")
        end
    end
    EnsureUnitBoxes = function()
        if unitBoxesBuilt then
            if targetBoxPending then AddTargetBox() end
            return
        end
        -- During the synchronous page-build frame a deferred visible refresh is
        -- already queued, so creation moves to that later frame. Hidden search
        -- index builds never pass the visible-refresh guards and skip the
        -- Player/Target boxes entirely. Without a timer (test harnesses,
        -- degraded clients) creation stays synchronous.
        if ctx and ctx._msuf2Building and C_Timer and C_Timer.After then return end
        unitBoxesBuilt = true
        local playerBox = MakeUnitPreview(host, ctx, unitPreviewW, "player", "Player")
        if playerBox then
            playerBox:ClearAllPoints()
            playerBox:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            unitBoxes[#unitBoxes + 1] = playerBox
            WireUnitBox(playerBox)
        end
        if C_Timer and C_Timer.After then
            targetBoxPending = true
            C_Timer.After(0.02, function()
                if targetBoxPending then AddTargetBox() end
            end)
        else
            AddTargetBox()
        end
    end

    -- Zoom and pan gestures pass through the shield to the hovered preview's
    -- own canvas handlers. Direct canvas mouse input stays disabled on this
    -- color-only surface, but the canvas scripts remain installed and expect
    -- (surface, ...) arguments, so delegation is safe.
    local function HoveredPreviewSurface()
        local function SurfaceOf(box)
            if box and box.IsShown and box:IsShown() and box.IsMouseOver and box:IsMouseOver() then
                return box.canvas or box._stage
            end
        end
        for i = 1, #unitBoxes do
            local surface = SurfaceOf(unitBoxes[i])
            if surface then return surface end
        end
        return SurfaceOf(castBox or nil) or SurfaceOf(groupBox)
    end
    local function DelegateSurfaceScript(scriptName, ...)
        local surface = HoveredPreviewSurface()
        local handler = surface and surface.GetScript and surface:GetScript(scriptName)
        if type(handler) == "function" then
            handler(surface, ...)
            return true
        end
        return false
    end
    if shield then
        shield:SetScript("OnMouseWheel", function(_, delta)
            -- The canvas wheel handler zooms on Ctrl and forwards plain wheel
            -- input to the menu scroll on its own.
            if DelegateSurfaceScript("OnMouseWheel", delta) then return end
            if type(M.ForwardMenuScrollWheel) == "function" then M.ForwardMenuScrollWheel(delta) end
        end)
        shield:SetScript("OnMouseDown", function(_, mouseButton)
            if (mouseButton == "LeftButton" and IsControlKeyDown and IsControlKeyDown())
                or mouseButton == "MiddleButton" then
                DelegateSurfaceScript("OnMouseDown", mouseButton)
            end
        end)
        shield:SetScript("OnMouseUp", function(_, mouseButton)
            DelegateSurfaceScript("OnMouseUp", mouseButton)
        end)
    end

    local function RefreshPreviews(reason)
        for i = 1, #unitBoxes do RequestPreview(unitBoxes[i], reason) end
        if groupBox then RequestPreview(groupBox, reason) end
        if castBox then RequestPreview(castBox, reason) end
    end

    -- Hint line: makes the clickable preview discoverable and doubles as the
    -- status line for the palette brush.
    local HINT_BASE = "Click an element in the preview to edit its colors. Right-click a color swatch to reset it to default."
    local hintLine = Label(paletteSection, HINT_BASE, 16, -36, innerW, T.colors.muted)
    local hintResetSerial = 0
    local function SetHintStatus(text, holdSeconds)
        hintResetSerial = hintResetSerial + 1
        local serial = hintResetSerial
        hintLine:SetText(text and Tr(text) or Tr(HINT_BASE))
        if text and holdSeconds and C_Timer and C_Timer.After then
            C_Timer.After(holdSeconds, function()
                if serial == hintResetSerial then hintLine:SetText(Tr(HINT_BASE)) end
            end)
        end
    end

    -- Palette row: saved + recent colors from the shared picker store. A click
    -- arms the swatch as a brush; the next preview click paints with it.
    local function PaletteStore()
        local db = type(M.EnsureDB) == "function" and M.EnsureDB() or _G.MSUF_DB
        local store = type(db) == "table" and db.menu2ColorPicker or nil
        return type(store) == "table" and store or nil
    end
    local function PaletteHexToRGB(value)
        local hex = tostring(value or ""):match("^%s*#?(%x%x%x%x%x%x)%s*$")
        if not hex then return nil end
        return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
    end
    local PALETTE_SLOTS = 14
    local paletteSlots = {}
    local paletteEmptyHint
    local function RefreshPaletteBrushVisuals()
        for i = 1, #paletteSlots do
            local slot = paletteSlots[i]
            if slot._msuf2Edge then
                if slot._msuf2Hex and slot._msuf2Hex == M.colorsBrushHex then
                    slot._msuf2Edge:SetVertexColor(1.00, 0.82, 0.20, 1)
                else
                    slot._msuf2Edge:SetVertexColor(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.9)
                end
            end
        end
    end
    local function SetBrush(hex)
        M.colorsBrushHex = hex
        RefreshPaletteBrushVisuals()
        if hex then
            SetHintStatus("Brush armed: click a preview element to paint it. Right-click the swatch to disarm.")
        else
            SetHintStatus(nil)
        end
    end
    local paletteLabel = Label(paletteSection, "My colors", 16, -62, 96, T.colors.dim, "GameFontNormalSmall")
    paletteLabel:SetJustifyH("LEFT")
    local paletteX = 96
    for i = 1, PALETTE_SLOTS do
        local slot = CreateFrame("Button", nil, paletteSection)
        slot:SetSize(26, 16)
        slot:SetPoint("TOPLEFT", paletteSection, "TOPLEFT", paletteX + 16 + (i - 1) * 32, -60)
        slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        slot._msuf2Fill, slot._msuf2Edge = T.CreateSuperellipseLayers(slot, "_msuf2PaletteSwatch", 1, "ARTWORK", "OVERLAY")
        local hover = slot:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.10)
        slot:SetScript("OnClick", function(self, mouseButton)
            if not self._msuf2Hex then return end
            if mouseButton == "RightButton" or M.colorsBrushHex == self._msuf2Hex then
                SetBrush(nil)
            else
                SetBrush(self._msuf2Hex)
            end
        end)
        if M.AddTooltip then
            M.AddTooltip(slot, "Palette color", Tr("Click to arm this color as a brush, then click a preview element to paint it."), { hook = true })
        end
        RegisterControl(slot,
            ControlMeta("opt_colors", "advanced", "preview.palette.slot." .. tostring(i), "ephemeral"),
            "Palette color", "button")
        slot:Hide()
        paletteSlots[i] = slot
    end
    local function RefreshPaletteSlots()
        local store = PaletteStore()
        local shown, seen = 0, {}
        local function AddSwatches(list)
            if type(list) ~= "table" then return end
            for i = 1, #list do
                if shown >= PALETTE_SLOTS then return end
                local hex = list[i]
                local r, g, b = PaletteHexToRGB(hex)
                if r and not seen[hex] then
                    seen[hex] = true
                    shown = shown + 1
                    local slot = paletteSlots[shown]
                    slot._msuf2Hex = hex
                    if slot._msuf2Fill.SetColorTexture then slot._msuf2Fill:SetColorTexture(r, g, b, 1)
                    else slot._msuf2Fill:SetVertexColor(r, g, b, 1) end
                    slot:Show()
                end
            end
        end
        AddSwatches(store and store.saved)
        AddSwatches(store and store.recent)
        for i = shown + 1, PALETTE_SLOTS do
            paletteSlots[i]._msuf2Hex = nil
            paletteSlots[i]:Hide()
        end
        if M.colorsBrushHex and not seen[M.colorsBrushHex] then M.colorsBrushHex = nil end
        if not paletteEmptyHint then
            paletteEmptyHint = Label(paletteSection, "Save or pick colors in the color picker to reuse them here.",
                paletteX + 16, -62, innerW - paletteX - 16, T.colors.dim, "GameFontNormalSmall")
        end
        paletteEmptyHint:SetShown(shown == 0)
        RefreshPaletteBrushVisuals()
    end
    RefreshPaletteSlots()
    M.TrackRefresh(ctx, RefreshPaletteSlots)

    -- Click-to-paint: resolve the section that owns the clicked element and
    -- open the shared context picker on its real bound color controls.
    local function EnsureSectionForPaint(sectionId)
        if not sectionId then return nil end
        local pageKey = (ctx and ctx.key) or M.activeKey or "opt_colors"
        local cache = M.cache and M.cache[pageKey]
        if not cache then return nil end
        local sections = cache.sections
        local target = sections and sections[sectionId]
        if not target and type(M.ColorsEnsureCategoryBuilt) == "function" then
            M.ColorsEnsureCategoryBuilt(sectionId)
            sections = cache.sections
            target = sections and sections[sectionId]
        end
        return target
    end
    local function SectionPaintOwners(sectionId)
        local target = EnsureSectionForPaint(sectionId)
        local entry = target and target._msuf2CollapsibleEntry
        if not entry then return nil end
        local root = entry
        while root.ancestorEntry do root = root.ancestorEntry end
        local owners = root._msuf2ColorContextOwners
        if type(owners) == "table" and #owners > 0 then return owners end
        return nil
    end
    local function FindOwnerByLabel(owners, label)
        if not (owners and label) then return nil end
        for i = 1, #owners do
            if owners[i]._msuf2ColorLabel == label then return owners[i] end
        end
    end
    local function ApplyBrushToOwner(owner, ownerLabel)
        local r, g, b = PaletteHexToRGB(M.colorsBrushHex)
        if not (r and owner) then return false end
        if owner.SetRGB then owner:SetRGB(r, g, b) end
        if type(owner._msuf2OnColorChanged) == "function" then owner._msuf2OnColorChanged(r, g, b) end
        SetHintStatus(Tr("Painted:") .. " " .. Tr(tostring(ownerLabel or owner._msuf2ColorLabel or "color")), 2.5)
        return true
    end
    local function OpenPaintTarget(spec, category)
        local sectionId = spec.sectionId or CATEGORY_SECTION[category.key]
        local owners = SectionPaintOwners(sectionId)
        if not owners then return false end
        local initialOwner = FindOwnerByLabel(owners, spec.ownerLabel) or owners[1]
        if M.colorsBrushHex then
            if ApplyBrushToOwner(initialOwner, spec.label) then return true end
        end
        if type(W.OpenColorContextPicker) ~= "function" then return false end
        W.OpenColorContextPicker(
            spec.label or category.title,
            owners,
            category.pickerNote,
            initialOwner,
            nil,
            nil,
            function() RefreshPreviews("MSUF2_COLOR_PAINTER_LIVE") end)
        return true
    end
    -- The external Editing navigator filters preview AND section list.  Keep a
    -- concise description in the preview card so its current content remains
    -- clear without duplicating the selector.
    local tabDescription = Label(section, "", 144, -14, innerW - 144, T.colors.muted)

    local clickTargets = {}
    local function FocusColorSection(sectionId)
        sectionId = sectionId or CATEGORY_SECTION[Current()]
        local target = EnsureSectionForPaint(sectionId)
        if target and type(W.FocusCollapsibleSection) == "function" then
            return W.FocusCollapsibleSection(target, { persist = true, flash = true })
        end
        return false
    end
    local function RebuildClickTargets(category, castPanel)
        ReleaseClickTargets(clickTargets)
        clickTargets = {}
        local anchors = ResolveCategoryAnchors(castPanel and { castPanel } or unitBoxes, groupBox, category.key)
        for i = 1, #anchors do
            local spec = anchors[i]
            local navigateTooltip = NAVIGATE_ONLY_SECTIONS[spec.sectionId or ""]
            local target = AddClickTarget(host, spec.anchor, function()
                if navigateTooltip and not M.colorsBrushHex then
                    FocusColorSection(spec.sectionId)
                    return
                end
                if not OpenPaintTarget(spec, category) then
                    FocusColorSection(spec.sectionId or CATEGORY_SECTION[category.key])
                end
            end, function()
                FocusColorSection(spec.sectionId or CATEGORY_SECTION[category.key])
            end, spec.label or category.title, spec.priority, DelegateSurfaceScript,
            navigateTooltip and Tr(navigateTooltip) or nil,
            shield)
            if target then clickTargets[#clickTargets + 1] = target end
        end
    end
    -- Resources tab: menu-only preview strip that follows the Power type /
    -- Resource type dropdowns. The live unit frames can only render the
    -- player's own class resources, so they cannot preview foreign selections.
    local resourcesStrip
    local function EnsureResourcesStrip(category)
        if resourcesStrip ~= nil then return resourcesStrip or nil end
        local preview = category and category.preview
        if type(preview) ~= "table" then
            resourcesStrip = false
            return nil
        end
        local strip = CreateFrame("Frame", nil, host)
        strip:SetPoint("TOPLEFT", host, "TOPLEFT", 24, 0)
        strip:SetPoint("TOPRIGHT", host, "TOPRIGHT", -24, 0)
        strip:SetHeight(132)
        if strip.SetFrameLevel and host.GetFrameLevel then
            local base = (shield and shield.GetFrameLevel and shield:GetFrameLevel())
                or ((host:GetFrameLevel() or 0) + COLOR_SHIELD_LEVEL)
            strip:SetFrameLevel(base + 11)
        end
        local barW = 340
        local function StripButton(y, height, label, sectionId, ownerLabel)
            local button = CreateFrame("Button", nil, strip)
            button:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, y)
            button:SetSize(barW + 24, height)
            button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            local hover = button:CreateTexture(nil, "HIGHLIGHT")
            hover:SetAllPoints()
            hover:SetColorTexture(0.18, 0.66, 1, 0.12)
            if M.AddTooltip then
                M.AddTooltip(button, label,
                    Tr("Click to edit these colors. Right-click opens the matching section below."),
                    { owner = "ANCHOR_CURSOR" })
            end
            ForwardMenuScrollWheel(button)
            button:SetScript("OnClick", function(_, mouseButton)
                if mouseButton == "RightButton" then
                    FocusColorSection(sectionId)
                    return
                end
                if not OpenPaintTarget({ sectionId = sectionId, label = label, ownerLabel = ownerLabel }, category) then
                    FocusColorSection(sectionId)
                end
            end)
            return button
        end

        local powerRow = StripButton(-2, 50, "Power Bar Colors", "colors_power", "Color")
        local powerLabel = Label(powerRow, "", 12, -4, barW, T.colors.text)
        local powerBg = powerRow:CreateTexture(nil, "BORDER")
        powerBg:SetPoint("TOPLEFT", powerRow, "TOPLEFT", 12, -24)
        powerBg:SetSize(barW, 18)
        local powerFill = powerRow:CreateTexture(nil, "ARTWORK")
        powerFill:SetPoint("TOPLEFT", powerBg, "TOPLEFT", 1, -1)
        powerFill:SetSize(floor(barW * 0.62), 16)

        local resourceRow = StripButton(-66, 56, "Class Power Colors", "colors_class_power", "Color")
        local resourceLabel = Label(resourceRow, "", 12, -4, barW, T.colors.text)
        local slots = {}
        for i = 1, 11 do
            local pill = resourceRow:CreateTexture(nil, "ARTWORK")
            pill:SetSize(26, 13)
            pill:SetPoint("TOPLEFT", resourceRow, "TOPLEFT", 12 + (i - 1) * 31, -28)
            pill:Hide()
            slots[i] = pill
        end
        local resourceBarBg = resourceRow:CreateTexture(nil, "BORDER")
        resourceBarBg:SetPoint("TOPLEFT", resourceRow, "TOPLEFT", 12, -26)
        resourceBarBg:SetSize(barW, 18)
        local resourceBarFill = resourceRow:CreateTexture(nil, "ARTWORK")
        resourceBarFill:SetPoint("TOPLEFT", resourceBarBg, "TOPLEFT", 1, -1)
        resourceBarFill:SetSize(floor(barW * 0.62), 16)

        function strip.Update()
            local pr, pg, pb = preview.power()
            local br, bgc, bb = preview.powerBg()
            powerFill:SetColorTexture(pr, pg, pb, 1)
            powerBg:SetColorTexture(br, bgc, bb, 0.9)
            powerLabel:SetText(Tr("Power") .. " - " .. Tr(preview.powerLabel() or ""))
            resourceLabel:SetText(Tr("Class Resource") .. " - " .. Tr(preview.resourceLabel() or ""))
            local count = tonumber(preview.slotCount()) or 0
            local slotsShown = count > 0
            if slotsShown then
                local shown = min(count, 10)
                for i = 1, shown do
                    local sr, sg, sb = preview.slot(i)
                    slots[i]:SetColorTexture(sr, sg, sb, 1)
                    slots[i]:Show()
                end
                local nextIndex = shown + 1
                if preview.fullEnabled() and nextIndex <= 11 then
                    local fr, fg, fb = preview.full()
                    slots[nextIndex]:SetColorTexture(fr, fg, fb, 1)
                    slots[nextIndex]:Show()
                    nextIndex = nextIndex + 1
                end
                for i = nextIndex, 11 do slots[i]:Hide() end
            else
                for i = 1, 11 do slots[i]:Hide() end
            end
            resourceBarBg:SetShown(not slotsShown)
            resourceBarFill:SetShown(not slotsShown)
            if not slotsShown then
                local rr, rg, rb = preview.resource()
                local rbr, rbg, rbb = preview.resourceBg()
                resourceBarFill:SetColorTexture(rr, rg, rb, 1)
                resourceBarBg:SetColorTexture(rbr, rbg, rbb, 0.9)
            end
        end
        strip:Hide()
        resourcesStrip = strip
        return strip
    end
    M.TrackRefresh(ctx, function()
        if resourcesStrip and resourcesStrip ~= false and resourcesStrip:IsShown() and resourcesStrip.Update then
            resourcesStrip.Update()
        end
    end)
    ShowCategory = function(key)
        if not valid[key] then key = categories[1].key end
        if M.SetMenuStateValue then M.SetMenuStateValue("colorsPainterCategory", key) else M.colorsPainterCategory = key end
        local category
        for i = 1, #categories do
            if categories[i].key == key then
                category = categories[i]
                break
            end
        end
        EnsureUnitBoxes()
        local castPanel = key == "cast" and EnsureCastBox() or nil
        local strip = key == "resources" and EnsureResourcesStrip(category) or nil
        if key == "group" then EnsureGroupBox() end
        for i = 1, #unitBoxes do unitBoxes[i]:SetShown(key ~= "group" and not castPanel and not strip) end
        if castBox then castBox:SetShown(castPanel and true or false) end
        if resourcesStrip and resourcesStrip ~= false then resourcesStrip:SetShown(strip and true or false) end
        if groupBox then groupBox:SetShown(key == "group") end
        if key ~= "group" and not strip then
            local boxes = castPanel and { castPanel } or unitBoxes
            for i = 1, #boxes do
                local unitBox = boxes[i]
                HidePreviewEditorChrome(unitBox, unitBox.canvas, unitBox.sidebar, unitBox.zoomBar, unitBox.animateCombatButton)
                DisableUnitPreviewEditing(unitBox)
                FocusUnitPreview(unitBox, key)
            end
        end
        if groupBox and key == "group" then
            HidePreviewEditorChrome(groupBox, groupBox._stage, groupBox._layers, groupBox._zoomBar, groupBox._previewAnimationButton)
            RequestPreview(groupBox, "MSUF2_COLOR_PAINTER_GROUP")
            HideGroupPreviewIcons(groupBox)
        end
        if categoryBar and categoryBar.Refresh then categoryBar:Refresh() end
        if category then
            tabDescription:SetText(Tr(category.subtitle or ""))
            if strip then
                ReleaseClickTargets(clickTargets)
                clickTargets = {}
                strip.Update()
            else
                RebuildClickTargets(category, castPanel)
            end
        end
        RaiseZoomBars()
        -- One taxonomy: the same tab drives which section category the page
        -- shows below the preview.
        if type(M.ColorsOnPainterCategory) == "function" then M.ColorsOnPainterCategory(key) end
    end
    M.ColorsSetPainterCategory = ShowCategory
    local function EnsurePreviewAttachment()
        if not W.AttachPinnedPreview then return end
        local pageKey = ctx and ctx.key
        local wrapper = ctx and ctx.wrapper
        local record = host._msuf2PinnedPreviewRecord
        if not record or record.pageKey ~= pageKey or record.pageWrapper ~= wrapper then
            W.AttachPinnedPreview(section, host, {
                stateKey = "colorPreview",
                pageKey = pageKey,
                wrapper = wrapper,
            })
        end
    end
    local initialRefreshSerial = 0
    local function RefreshVisiblePreview(reason, skipRender)
        if ctx and ctx.key and M.activeKey and M.activeKey ~= ctx.key then return end
        if ctx and ctx.wrapper and ctx.wrapper.IsShown and not ctx.wrapper:IsShown() then return end
        if section.IsShown and not section:IsShown() then return end
        -- Page changes release pinned previews and explicitly Hide() their box,
        -- while Menu2 keeps the Colors page itself cached. Reassert both the
        -- host's local shown state and its pin record before touching children.
        -- Showing only Player/Target here cannot make them visible below a
        -- released (hidden) host.
        if host.Show then host:Show() end
        EnsureUnitBoxes()
        EnsurePreviewAttachment()
        ShowCategory(Current())
        if not skipRender then RefreshPreviews(reason or "MSUF2_COLOR_PAINTER_VISIBLE") end
        return true
    end
    local function QueueVisiblePreviewRefresh(reason)
        initialRefreshSerial = initialRefreshSerial + 1
        local serial = initialRefreshSerial
        local rendered = RefreshVisiblePreview(reason) == true
        local timer = C_Timer
        if timer and timer.After then
            timer.After(0, function()
                if serial ~= initialRefreshSerial then return end
                -- The next-frame pass reasserts host/attachment/category state;
                -- the expensive preview render repeats here only when the
                -- immediate pass was blocked by the visibility guards. The
                -- 0.05s settle pass below stays a full render.
                if RefreshVisiblePreview(reason, rendered) == true then rendered = true end
            end)
            timer.After(0.05, function()
                if serial == initialRefreshSerial then RefreshVisiblePreview(reason) end
            end)
        end
    end
    if section.HookScript then
        section:HookScript("OnShow", function() QueueVisiblePreviewRefresh("MSUF2_COLOR_PAINTER_SHOW") end)
        section:HookScript("OnHide", function()
            initialRefreshSerial = initialRefreshSerial + 1
            for i = 1, #unitBoxes do unitBoxes[i]:Hide() end
            if groupBox then groupBox:Hide() end
            if castBox then castBox:Hide() end
        end)
    end
    if ctx and ctx.wrapper and ctx.wrapper.HookScript then
        ctx.wrapper:HookScript("OnShow", function()
            QueueVisiblePreviewRefresh("MSUF2_COLOR_PAINTER_PAGE_SHOW")
        end)
    end
    ShowCategory(Current())
    if not section:IsShown() then
        for i = 1, #unitBoxes do unitBoxes[i]:Hide() end
        if groupBox then groupBox:Hide() end
        if castBox then castBox:Hide() end
    end
    M.TrackRefresh(ctx, function()
        if not section:IsShown() then return end
        QueueVisiblePreviewRefresh("MSUF2_COLOR_PAINTER_REFRESH")
    end)
    EnsurePreviewAttachment()
    QueueVisiblePreviewRefresh("MSUF2_COLOR_PAINTER_INITIAL")
    -- Fixed below the color category selector. Internal shield/click-target
    -- levels remain page-native while all settings scroll below the shell.
    if fixedPreview then
        fixedPreview.onActivate = function() QueueVisiblePreviewRefresh("MSUF2_COLOR_PAINTER_FIXED_SHOW") end
    end
    return section
end
