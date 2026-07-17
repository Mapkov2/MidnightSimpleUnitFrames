local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

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
    if sidebar then sidebar:Hide() end
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

local function ForwardMenuScrollWheel(frame)
    if not (frame and frame.EnableMouseWheel and frame.SetScript) then return end
    frame:EnableMouseWheel(true)
    if frame.SetPropagateMouseWheel then frame:SetPropagateMouseWheel(false) end
    frame:SetScript("OnMouseWheel", function(_, delta)
        local scroll = M.scrollFrame
        local handler = scroll and scroll.GetScript and scroll:GetScript("OnMouseWheel")
        if type(handler) == "function" then handler(scroll, delta) end
    end)
end

local function InstallColorOnlyShield(parent)
    local shield = CreateFrame("Button", nil, parent)
    shield:SetAllPoints(parent)
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
    local box = create(parent, panel, width, 292)
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
    unit = { body = true, nameText = true, hpText = true, powerText = true, portrait = true, power = true },
    cast = { castbar = true },
    auras = { auras = true },
    resources = { power = true, classPower = true },
}
local CATEGORY_SECTION = {
    unit = "colors_appearance",
    group = "colors_group_frames",
    cast = "colors_castbar",
    auras = "colors_auras",
    resources = "colors_power",
}

local function FocusUnitPreview(box, category)
    if not (box and type(box.layerVisibility) == "table") then return end
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
    local function Target(anchor, sectionId, label, priority)
        if not anchor then return nil end
        return { anchor = anchor, sectionId = sectionId, label = label, priority = priority or 0 }
    end
    local function FillAnchor(bar)
        if bar and bar.GetStatusBarTexture then return bar:GetStatusBarTexture() or bar end
        return bar
    end
    local result = {}
    local function Add(anchor, sectionId, label, priority)
        local value = Target(anchor, sectionId, label, priority)
        if value then result[#result + 1] = value end
    end
    if categoryKey == "group" then
        local groupMock = groupBox and (groupBox._mock or groupBox.mock)
        Add(groupMock, "colors_group_frames", "Group Frame Colors", 0)
        Add(groupMock and groupMock._power, "colors_power", "Power Bar Colors", 20)
        Add(groupMock and FillAnchor(groupMock._healPred), "colors_bar_colors", "Positive Heal Prediction", 40)
        Add(groupMock and FillAnchor(groupMock._absorb), "colors_bar_colors", "Absorb Overlay", 50)
        Add(groupMock and FillAnchor(groupMock._healAbsorb), "colors_bar_colors", "Heal-Absorb (Negative)", 60)
        Add(groupMock and groupMock._nameFS, "colors_font", "Name Text Color", 80)
        Add(groupMock and groupMock._hpLeftFS, "colors_font", "Health Text Color", 90)
        Add(groupMock and groupMock._hpCenterFS, "colors_font", "Health Text Color", 90)
        Add(groupMock and groupMock._hpRightFS, "colors_font", "Health Text Color", 90)
        Add(groupMock and groupMock._powerLeftFS, "colors_font", "Power Text Color", 90)
        Add(groupMock and groupMock._powerCenterFS, "colors_font", "Power Text Color", 90)
        Add(groupMock and groupMock._powerRightFS, "colors_font", "Power Text Color", 90)
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
                Add(mock.hpBG or mock, "colors_appearance", LabelFor("Unitframe Global Coloring"), 0)
                Add(mock.powerBG or mock.power, "colors_power", LabelFor("Power Bar Colors"), 20)
                Add(mock.detachedPower, "colors_power", LabelFor("Detached Power Bar Colors"), 25)
                Add(mock.portrait, "colors_portrait", LabelFor("Portrait Colors"), 30)
                Add(mock.healPred, "colors_bar_colors", LabelFor("Positive Heal Prediction"), 40)
                Add(mock.absorb, "colors_bar_colors", LabelFor("Absorb Overlay"), 50)
                Add(mock.healAbsorb, "colors_bar_colors", LabelFor("Heal-Absorb (Negative)"), 60)
                Add(mock.nameText, "colors_font", LabelFor("Name Text Color"), 80)
                Add(mock.raidGroupNameText, "colors_font", LabelFor("Name Text Color"), 80)
                Add(mock.totInlineText, "colors_font", LabelFor("Name Text Color"), 80)
                Add(mock.hpTextLeft, "colors_font", LabelFor("Health Text Color"), 90)
                Add(mock.hpTextCenter, "colors_font", LabelFor("Health Text Color"), 90)
                Add(mock.hpText, "colors_font", LabelFor("Health Text Color"), 90)
                Add(mock.hpTextPct, "colors_font", LabelFor("Health Text Color"), 90)
                Add(mock.powerTextLeft, "colors_font", LabelFor("Power Text Color"), 90)
                Add(mock.powerTextCenter, "colors_font", LabelFor("Power Text Color"), 90)
                Add(mock.powerText, "colors_font", LabelFor("Power Text Color"), 90)
                Add(mock.powerTextPct, "colors_font", LabelFor("Power Text Color"), 90)
            elseif categoryKey == "cast" then
                Add(mock.cast, "colors_castbar", LabelFor("Castbar Colors"), 30)
            elseif categoryKey == "auras" then
                Add(unitBox.handleAuraBuffs, "colors_auras", LabelFor("Aura Colors"), 30)
                Add(unitBox.handleAuraDebuffs, "colors_auras", LabelFor("Aura Colors"), 30)
            elseif categoryKey == "resources" then
                Add(mock.powerBG or mock.power, "colors_power", LabelFor("Power Bar Colors"), 20)
                Add(mock.detachedPower, "colors_power", LabelFor("Detached Power Bar Colors"), 25)
                Add(mock.classPower, "colors_class_power", LabelFor("Class Power Colors"), 30)
            end
        end
    end
    return result
end

local function AddClickTarget(host, anchor, onClick, label, priority)
    if not (host and anchor and type(onClick) == "function") then return nil end
    local button = CreateFrame("Button", nil, host)
    button:SetAllPoints(anchor)
    button:RegisterForClicks("LeftButtonUp")
    if button.SetFrameLevel and host.GetFrameLevel then
        local localPriority = floor((tonumber(priority) or 0) / 10)
        local popupLevel = tonumber(M.MENU_POPUP_FRAME_LEVEL) or 120
        local targetBase = min((host:GetFrameLevel() or 0) + COLOR_TARGET_LEVEL, popupLevel - 19)
        button:SetFrameLevel(targetBase + localPriority)
    end
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(0.18, 0.66, 1, 0.18)
    if M.AddTooltip then M.AddTooltip(button, label, Tr("Open the matching color section below."), { owner = "ANCHOR_CURSOR" }) end
    ForwardMenuScrollWheel(button)
    button:SetScript("OnClick", onClick)
    return button
end

function P.Build(ctx, builder, categories)
    if not (ctx and builder and type(categories) == "table" and #categories > 0) then return nil end
    local section = builder:CollapsibleSection("colors_preview", "Color Preview", 410, false)
    local width = section._msuf2Width or ctx.width or 720
    local innerW = width - 32

    local tabsY, gap = -10, 6
    local tabW = floor((innerW - gap * (#categories - 1)) / #categories)
    local tabButtons = {}
    local previewW = innerW
    local host = CreateFrame("Frame", nil, section)
    host:SetPoint("TOPLEFT", section, "TOPLEFT", 16, -46)
    host:SetSize(previewW, 350)
    InstallColorOnlyShield(host)

    local unitGap = 8
    local unitPreviewW = max(1, floor((previewW - unitGap) * 0.5))
    local playerBox = MakeUnitPreview(host, ctx, unitPreviewW, "player", "Player")
    local targetBox = MakeUnitPreview(host, ctx, unitPreviewW, "target", "Target")
    local unitBoxes = {}
    if playerBox then
        playerBox:ClearAllPoints()
        playerBox:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        unitBoxes[#unitBoxes + 1] = playerBox
    end
    if targetBox then
        targetBox:ClearAllPoints()
        targetBox:SetPoint("TOPLEFT", host, "TOPLEFT", unitPreviewW + unitGap, 0)
        unitBoxes[#unitBoxes + 1] = targetBox
    end
    local groupBox = MakeGroupPreview(host, ctx, previewW)
    if groupBox then groupBox:Hide() end
    if #unitBoxes == 0 and not groupBox then Label(host, "Preview renderer is unavailable.", 12, -12, previewW - 24, T.colors.muted) end

    local function RefreshPreviews(reason)
        for i = 1, #unitBoxes do RequestPreview(unitBoxes[i], reason) end
        RequestPreview(groupBox, reason)
    end
    for i = 1, #categories do
        local category = categories[i]
        local tab = T.Button(section, category.shortTitle or category.title, tabW, 26)
        tab:SetPoint("TOPLEFT", section, "TOPLEFT", 16 + (i - 1) * (tabW + gap), tabsY)
        RegisterControl(tab,
            ControlMeta("opt_colors", "advanced", "preview.scope.option." .. tostring(category.key), "ephemeral"),
            category.shortTitle or category.title, "button")
        tabButtons[category.key] = tab
    end

    local clickTargets = {}
    local valid = {}
    for i = 1, #categories do valid[categories[i].key] = true end
    local function Current() return valid[M.colorsPainterCategory] and M.colorsPainterCategory or categories[1].key end
    local function FocusColorSection(sectionId)
        sectionId = sectionId or CATEGORY_SECTION[Current()]
        local pageKey = (ctx and ctx.key) or M.activeKey or "opt_colors"
        local cache = M.cache and M.cache[pageKey]
        local section = cache and cache.sections and cache.sections[sectionId]
        if section and type(W.FocusCollapsibleSection) == "function" then
            return W.FocusCollapsibleSection(section, { persist = true, flash = true })
        end
        return false
    end
    local function RebuildClickTargets(category)
        for i = 1, #clickTargets do clickTargets[i]:Hide() end
        clickTargets = {}
        local anchors = ResolveCategoryAnchors(unitBoxes, groupBox, category.key)
        for i = 1, #anchors do
            local spec = anchors[i]
            local target = AddClickTarget(host, spec.anchor, function()
                FocusColorSection(spec.sectionId or CATEGORY_SECTION[category.key])
            end, spec.label or category.title, spec.priority)
            if target then clickTargets[#clickTargets + 1] = target end
        end
    end
    local function ShowCategory(key)
        if not valid[key] then key = categories[1].key end
        if M.SetMenuStateValue then M.SetMenuStateValue("colorsPainterCategory", key) else M.colorsPainterCategory = key end
        for i = 1, #unitBoxes do unitBoxes[i]:SetShown(key ~= "group") end
        if groupBox then groupBox:SetShown(key == "group") end
        if key ~= "group" then
            for i = 1, #unitBoxes do
                local unitBox = unitBoxes[i]
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
        for id, button in pairs(tabButtons) do if button.SetActive then button:SetActive(id == key) end end
        for i = 1, #categories do if categories[i].key == key then RebuildClickTargets(categories[i]); break end end
    end
    for key, button in pairs(tabButtons) do
        button:SetScript("OnClick", function()
            ShowCategory(key)
        end)
    end
    local function EnsurePreviewAttachment()
        if not W.AttachPinnedPreview then return end
        local pageKey = ctx and ctx.key
        local wrapper = ctx and ctx.wrapper
        local record = host._msuf2PinnedPreviewRecord
        if not record or record.pageKey ~= pageKey or record.pageWrapper ~= wrapper then
            W.AttachPinnedPreview(section, host, {
                stateKey = "colorPreview",
                left = 14,
                right = 14,
                top = -8,
                buttonWidth = 78,
                buttonHeight = 20,
                centerButton = true,
                quietButton = true,
                pinnedHeight = 350,
                pageKey = pageKey,
                wrapper = wrapper,
                restoreParent = section,
                restorePoint = { "TOPLEFT", section, "TOPLEFT", 16, -46 },
                restoreWidth = previewW,
                restoreHeight = 350,
            })
        end
        if host._msuf2PinButton and host._msuf2PinButton.SetFrameLevel then
            local popupLevel = tonumber(M.MENU_POPUP_FRAME_LEVEL) or 120
            host._msuf2PinButton:SetFrameLevel(min((host:GetFrameLevel() or 1) + COLOR_TARGET_LEVEL + 12, popupLevel - 5))
        end
        if host._msuf2PinButton and not host._msuf2ColorPainterPinRegistered then
            host._msuf2ColorPainterPinRegistered = true
            RegisterControl(host._msuf2PinButton,
                ControlMeta("opt_colors", "advanced", "preview.pin.toggle", "ephemeral"),
                "Pin Color Preview", "toggle")
        end
    end
    local initialRefreshSerial = 0
    local function RefreshVisiblePreview(reason)
        if ctx and ctx.key and M.activeKey and M.activeKey ~= ctx.key then return end
        if ctx and ctx.wrapper and ctx.wrapper.IsShown and not ctx.wrapper:IsShown() then return end
        if section.IsShown and not section:IsShown() then return end
        -- Page changes release pinned previews and explicitly Hide() their box,
        -- while Menu2 keeps the Colors page itself cached. Reassert both the
        -- host's local shown state and its pin record before touching children.
        -- Showing only Player/Target here cannot make them visible below a
        -- released (hidden) host.
        if host.Show then host:Show() end
        EnsurePreviewAttachment()
        ShowCategory(Current())
        RefreshPreviews(reason or "MSUF2_COLOR_PAINTER_VISIBLE")
    end
    local function QueueVisiblePreviewRefresh(reason)
        initialRefreshSerial = initialRefreshSerial + 1
        local serial = initialRefreshSerial
        RefreshVisiblePreview(reason)
        local timer = _G.C_Timer
        if timer and timer.After then
            timer.After(0, function()
                if serial == initialRefreshSerial then RefreshVisiblePreview(reason) end
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
    end
    M.TrackRefresh(ctx, function()
        if not section:IsShown() then return end
        QueueVisiblePreviewRefresh("MSUF2_COLOR_PAINTER_REFRESH")
    end)
    EnsurePreviewAttachment()
    QueueVisiblePreviewRefresh("MSUF2_COLOR_PAINTER_INITIAL")
    return section
end
