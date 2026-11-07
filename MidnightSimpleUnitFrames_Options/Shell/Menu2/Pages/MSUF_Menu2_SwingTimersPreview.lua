-- Embedded samples use the gameplay painter without native timers or DB writes.
local _, MSUF = ...
if not (MSUF.Client and MSUF.Client.IsForever) then return end
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Shell/Menu2/Pages/MSUF_Menu2_SwingTimersPreview.lua")
local M, Swing = MSUF.MSUF2, MSUF.SwingTimer
local W, H, T = M.Widgets, M.PreviewHelpers, M.Theme
local Preview = {}
M.SwingTimerPreview = Preview
local HANDS = { "main", "off", "ranged" }
local SECTION_HEIGHT, BODY_TOP, INSET, MIN_CANVAS_HEIGHT = 180, 66, 14, 148
local FOCUS = { flash = true }
local OPEN_SECTION = { flash = false, scroll = false }
local LAYERS = {
    { key = "bar", label = "Bar", setting = "texture", section = "appearance" },
    { key = "background", label = "Background texture", setting = "backgroundTexture", section = "appearance" },
    { key = "border", label = "Border thickness", setting = "borderSize", section = "appearance" },
    { key = "title", label = "Show bar title", setting = "title", section = "text" },
    { key = "time", label = "Remaining time", setting = "time", section = "text" },
    { key = "lane", label = "Off Hand", setting = "offhandLane", section = "behavior" },
    { key = "guides", label = "Guides", color = { 0.42, 0.72, 1.00 } },
}
local RANGE = { label = "Out of range", setting = "reachOpacity", section = "reach" }
local BORDERS = { "TOP", "BOTTOM", "LEFT", "RIGHT" }

local function FocusSetting(ui, layer)
    local hand = ui.selected
    local key = "swingTimers." .. hand .. "." .. layer.setting
    local focused = M.OpenExactSettingControl and M.OpenExactSettingControl(key, layer.label, "swingtimers")
    W.FocusCollapsibleSection(ui.handSections[hand][layer.section], focused and OPEN_SECTION or FOCUS)
end

local function RefreshGuide(ui)
    local target = ui.hoverTarget
    local visible = ui.layerVisibility.guides and target and target:IsVisible()
    local key = visible and target.layer.key or nil
    if ui._msuf2SelectedPreviewLayerKey ~= key then
        ui._msuf2SelectedPreviewLayerKey = key
        for _, chip in ipairs(ui.layerButtons) do chip:Refresh() end
    end
    local guide = ui.guide
    if visible then
        local anchor = target.guideAnchor or target
        guide:ClearAllPoints()
        guide:SetPoint("TOPLEFT", anchor, "TOPLEFT", -1, 1)
        guide:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 1, -1)
    end
    guide:SetShown(visible == true)
end

local function SetHover(ui, source, target)
    ui.hoverSource, ui.hoverTarget = source, target
    RefreshGuide(ui)
end

local function BindHover(widget, ui, targetForWidget)
    widget:HookScript("OnEnter", function(self) SetHover(ui, self, targetForWidget(self)) end)
    local function Leave(self)
        if ui.hoverSource == self then SetHover(ui) end
    end
    widget:HookScript("OnLeave", Leave)
    widget:HookScript("OnHide", Leave)
end

local function HoverLayerTarget(ui, key)
    local targets = ui.samples[ui.selected].hitTargets
    if key == "border" then return targets.borders[1] end
    return targets[key]
end

local function ToggleLayer(chip, ui)
    local key = chip.key
    if ui.available[key] then
        ui.layerVisibility[key] = not ui.layerVisibility[key]
        ui.Paint()
    else
        FocusSetting(ui, chip.layer)
    end
end

local function BuildLayers(ui, rail)
    local opts = H.LayerChipButtonOpts(M.Tr, T.colors, H.PreviewChromePalette(T), {
        IsAvailable = function(owner, key) return owner.available[key] == true end,
        IsOn = function(owner, key) return owner.layerVisibility[key] end,
        OnClick = ToggleLayer,
    })
    for i, layer in ipairs(LAYERS) do
        ui.layerVisibility[layer.key] = true
        local chip = H.CreateLayerButton(rail, ui, layer, i, nil, opts)
        chip.layer = layer
        if layer.setting then
            chip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            chip:SetScript("OnClick", function(self, button)
                if button == "RightButton" then FocusSetting(ui, layer) else ToggleLayer(self, ui) end
            end)
            if M.AddTooltip then
                M.AddTooltip(chip, layer.label, "Right-click an element to open its section below.", { hook = true })
            end
            BindHover(chip, ui, function() return HoverLayerTarget(ui, layer.key) end)
        end
        ui.layerButtons[i] = chip
        if layer.key == "lane" then ui.laneChip = chip end
    end
end

local function SelfTarget(button) return button end

local function HitTarget(parent, ui, layer, level)
    local button = PixelLayoutRegion(CreateFrame("Button", nil, parent))
    button:SetFrameLevel(level)
    button:EnableMouse(true)
    button:SetScript("OnClick", function() FocusSetting(ui, layer) end)
    button.layer = layer
    if M.AddTooltip then M.AddTooltip(button, layer.label, "Open settings") end
    BindHover(button, ui, SelfTarget)
    return button
end

local function BuildTargets(frame, ui, hand)
    local level = frame.Bar:GetFrameLevel()
    frame.Text:SetFrameLevel(level + 5)
    local targets = {
        bar = HitTarget(frame, ui, LAYERS[1], level + 2),
        background = HitTarget(frame, ui, LAYERS[2], level + 1),
        title = HitTarget(frame.Text, ui, LAYERS[4], level + 6),
        time = HitTarget(frame.Text, ui, LAYERS[5], level + 7),
        borders = {},
    }
    targets.background:SetAllPoints(frame.Bar.Background)
    targets.title:SetPoint("LEFT", frame.Title, "LEFT")
    targets.time:SetPoint("LEFT", frame.Time, "LEFT")
    for i, edge in ipairs(BORDERS) do
        local button = HitTarget(frame, ui, LAYERS[3], level)
        button:SetPoint(edge, frame, edge)
        button.guideAnchor = frame.PreviewBorder
        targets.borders[i] = button
    end
    if hand == "main" then targets.lane = HitTarget(frame, ui, LAYERS[6], level + 4) end
    return targets
end

local function ShowTextTarget(button, text, width, height, visible)
    button:SetSize(math.max(1, width), height + 4)
    button:SetShown(visible and text:IsShown())
end

local function PaintLayers(ui, frame)
    local layers, available, cfg = ui.layerVisibility, ui.available, frame.config
    local targets, bar = frame.hitTargets, frame.Bar
    local lane = ui.selected == "main" and ui.samples.off.Lane
    local visible = frame:GetAlpha() > 0
    local hasBar = cfg.display == "bar"
    available.bar, available.background = hasBar, hasBar
    available.border = hasBar and cfg.borderSize > 0
    available.title, available.time = frame.Title:IsShown(), frame.Time:IsShown()
    available.lane = lane and lane:IsShown() or false

    bar:SetShown(available.bar and layers.bar)
    bar.Background:SetShown(available.background and layers.background)
    frame.PreviewBorder:SetShown(available.border and layers.border)
    frame.Title:SetShown(available.title and layers.title)
    frame.Time:SetShown(available.time and layers.time)
    if lane then lane:SetShown(available.lane and layers.lane) end

    local fill = bar:GetStatusBarTexture()
    if fill then targets.bar:SetAllPoints(fill) end
    targets.bar:SetShown(visible and fill ~= nil and bar:IsShown())
    targets.background:SetShown(visible and cfg.backgroundOpacity > 0 and bar.Background:IsShown())
    local edge = math.max(frame.inset, 4)
    for i, button in ipairs(targets.borders) do
        if i <= 2 then button:SetSize(cfg.width, edge) else button:SetSize(edge, cfg.height) end
        button:SetShown(visible and frame.PreviewBorder:IsShown())
    end
    if targets.lane then
        if lane then targets.lane:SetAllPoints(lane) end
        targets.lane:SetShown(visible and lane and lane:IsShown() or false)
    end
    ShowTextTarget(targets.title, frame.Title, math.min(frame.Title:GetStringWidth(), frame.Title:GetWidth()), cfg.fontSize, visible)
    ShowTextTarget(targets.time, frame.Time, frame.Time:GetStringWidth(), cfg.fontSize, visible)
    for _, chip in ipairs(ui.layerButtons) do chip:Refresh() end
end

local function FitSample(ui, frame)
    local cfg = frame.config
    local left, right, bottom, top = -cfg.width / 2, cfg.width / 2, -cfg.height / 2, cfg.height / 2
    if frame.Title:IsShown() then
        bottom, top = math.min(bottom, -cfg.fontSize), math.max(top, cfg.fontSize)
    end
    if frame.Time:IsShown() then
        local align = cfg.textAlign
        if align == "AUTO" then align = cfg.display == "text" and "CENTER" or "RIGHT" end
        local textWidth = frame.Time:GetStringWidth()
        local padding = cfg.display == "bar" and (align == "LEFT" and 5 or align == "RIGHT" and -5 or 0) or 0
        local anchor = align == "LEFT" and left or align == "RIGHT" and right - textWidth or -textWidth / 2
        local textLeft = cfg.textX + padding + anchor
        left, right = math.min(left, textLeft), math.max(right, textLeft + textWidth)
        bottom, top = math.min(bottom, cfg.textY - cfg.fontSize), math.max(top, cfg.textY + cfg.fontSize)
    end
    local scale = math.min(cfg.scale / 100, (ui.canvasWidth - 16) / (right - left), (ui.canvasHeight - 8) / (top - bottom))
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", ui.canvas, "CENTER", -(left + right) / 2, -(bottom + top) / 2)
end

local function Layout(ui)
    local width = ui.section:GetWidth() or 0
    if width < 100 then width = ui.width end
    if ui.layoutWidth == width and ui.layoutHand == ui.selected then return end
    if ui.layoutHand ~= ui.selected then SetHover(ui) end
    ui.layoutWidth, ui.layoutHand = width, ui.selected
    ui.laneChip:SetShown(ui.selected == "main")

    local bodyWidth = width - INSET * 2
    local railHeight = H.FlowLayerChips(ui.rail, ui.layerButtons, { width = bodyWidth, padY = 23 }) - 15
    ui.rail:SetHeight(railHeight)
    local reserved = BODY_TOP + railHeight + 12
    local height = math.max(SECTION_HEIGHT, reserved + MIN_CANVAS_HEIGHT)
    ui.canvasWidth, ui.canvasHeight = bodyWidth, height - reserved
    if height == ui.layoutHeight then return end
    ui.layoutHeight = height
    ui.section._msuf2FixedPreviewActiveHeight = height
    ui.section:SetHeight(height)
end

local function Paint(ui)
    if not ui.section:IsVisible() then return end
    Layout(ui)
    local outside = ui.rangePreview[ui.selected]
    Swing.PaintMenuPreview(ui.samples, outside and ui.selected)
    local frame = ui.samples[ui.selected]
    PaintLayers(ui, frame)
    for _, hand in ipairs(HANDS) do ui.samples[hand]:SetShown(hand == ui.selected) end
    FitSample(ui, frame)
    RefreshGuide(ui)
    local status = outside and M.AlphaLabel("Out of range", frame.config.reachOpacity / 100) or M.Tr("Out of range")
    ui.rangeButton:SetText(status, true)
    local label = ui.rangeButton._msuf2Label
    if label then ui.rangeButton:SetWidth(math.max(154, label:GetStringWidth() + 22)) end
    ui.rangeButton:MSUF2RefreshPreviewPill(outside == true)
end

local function BuildRangeButton(ui, toolbar)
    local range = T.Button(toolbar, "Out of range", 154, 20, { history = false })
    H.StylePreviewPillButton(range, T, { fontField = "_msuf2Label" })
    range:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    range:SetScript("OnClick", function(_, button)
        if button == "RightButton" then FocusSetting(ui, RANGE)
        else ui.SetRangePreview(ui.selected, not ui.rangePreview[ui.selected]) end
    end)
    if M.AddTooltip then M.AddTooltip(range, "Out of range", "Right-click an element to open its section below.", { hook = true }) end
    range:SetPoint("RIGHT", toolbar, "RIGHT", -12, 0)
    ui.rangeButton = range
end

local function CreateGuide(canvas)
    local guide = PixelLayoutRegion(CreateFrame("Frame", nil, canvas, "BackdropTemplate"))
    guide:SetFrameLevel(canvas:GetFrameLevel() + 30)
    guide:EnableMouse(false)
    PixelLayoutRegion(guide, "SetBackdrop", {
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
    })
    guide:SetBackdropColor(0.30, 0.58, 0.95, 0.14)
    guide:SetBackdropBorderColor(0.42, 0.72, 1.00, 0.95)
    guide:Hide()
    return guide
end

function Preview.Build(ctx, builder)
    local ui
    local section, toolbar = W.FixedPreviewSection(ctx, builder, {
        title = "Preview", height = SECTION_HEIGHT,
        onActivate = function() if ui then ui.Paint() end end,
    })
    local canvas = PixelLayoutRegion(CreateFrame("Frame", nil, section, "BackdropTemplate"))
    local rail = PixelLayoutRegion(CreateFrame("Frame", nil, section, "BackdropTemplate"))
    rail:SetPoint("BOTTOMLEFT", section, "BOTTOMLEFT", INSET, 8)
    rail:SetPoint("BOTTOMRIGHT", section, "BOTTOMRIGHT", -INSET, 8)
    canvas:SetPoint("TOPLEFT", section, "TOPLEFT", INSET, -BODY_TOP)
    canvas:SetPoint("BOTTOMRIGHT", rail, "TOPRIGHT", 0, 4)
    H.ApplyPreviewChrome(rail, "sidebar", T)
    local title = PixelLayoutRegion(rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    title:SetPoint("TOPLEFT", rail, "TOPLEFT", 10, -5)
    title:SetText(M.Tr("Preview Layers"))
    canvas:SetClipsChildren(true)
    H.ApplyPreviewChrome(canvas, "canvas", T)
    ui = {
        section = section, canvas = canvas, rail = rail, railTitle = title, guide = CreateGuide(canvas),
        width = builder.width or ctx.width or 700, selected = "main", samples = {},
        handSections = { main = {}, off = {}, ranged = {} },
        layerButtons = {}, layerVisibility = {}, available = { guides = true }, rangePreview = {},
        layoutHeight = SECTION_HEIGHT,
    }
    function ui.Paint() Paint(ui) end
    function ui.SetRangePreview(hand, value)
        ui.rangePreview[hand] = value == true
        ui.Paint()
    end
    for _, hand in ipairs(HANDS) do
        local sample = Swing.CreateMenuPreview(canvas, hand)
        sample.hitTargets = BuildTargets(sample, ui, hand)
        ui.samples[hand] = sample
    end
    BuildLayers(ui, rail)
    BuildRangeButton(ui, toolbar)
    Layout(ui)
    section:HookScript("OnShow", ui.Paint)
    section:HookScript("OnHide", function() SetHover(ui) end)
    section:HookScript("OnSizeChanged", function(_, width)
        if width <= 0 or width == ui.layoutWidth or not section:IsVisible() then return end
        Layout(ui)
        local sample = ui.samples[ui.selected]
        if sample.config then FitSample(ui, sample) end
        RefreshGuide(ui)
    end)
    M.TrackRefresh(ctx, ui.Paint)
    ctx._msuf2SwingTimerPreview = ui
    return ui
end
