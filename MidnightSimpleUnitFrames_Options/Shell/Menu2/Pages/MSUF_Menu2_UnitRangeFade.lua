local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local W = M.Widgets or {}
local UP = M.UnitPage or {}
local VT = M.ValueTextList
local floor = math.floor
local max = math.max
local PercentValue = M.PercentValue
local SettingMeta = UP.SettingMeta
local RANGE_FADE_UNITS = M.KeySetFromWords "target targettarget focus focustarget pet boss"
local function BuildRangeFade(ctx, builder, unit)
    local ReadBool = UP.ReadBool
    local SetBool = UP.SetBool
    local ReadNumber = UP.ReadNumber
    local SetNumber = UP.SetNumber
    local SetString = UP.SetString
    local SetControlEnabled = UP.SetControlEnabled
    local GetConf = UP.GetConf
    if not (ReadBool and SetBool and ReadNumber and SetNumber and SetString and SetControlEnabled and GetConf) then return end
    local sec = builder:CollapsibleSection("range_fade", "Range Fade", 230, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local gap = 16
    local leftX = 20
    local innerW = max(320, sectionW - 40)
    local leftW = floor((innerW - gap) * 0.48)
    local rightX = leftX + leftW + gap
    local rightW = innerW - leftW - gap
    local mainCard = W.ControlCard(sec, "Behavior", nil, leftX, -38, leftW, 166)
    local alphaCard = W.ControlCard(sec, "Out of range", nil, rightX, -38, rightW, 166)
    local RefreshRangeControls = M.RefreshProxy()
    local enabled = W.ToggleAt(mainCard, "Enable Range Fade", 16, -54, leftW - 32)
    M.BindBoolWidget(ctx, enabled,
        function() return ReadBool(unit, "rangeFadeEnabled", true) end,
        function(v)
            SetBool(unit, "rangeFadeEnabled", v, "MSUF2_RANGE_FADE", { preview = true })
            RefreshRangeControls()
        end,
        SettingMeta(ctx, "range_fade.enabled", unit, "rangeFadeEnabled"))
    local slider = W.Slider(alphaCard, "", 0, 1, 0.05, rightW - 58)
    if slider.SetValueFormatter then slider:SetValueFormatter(PercentValue) end
    M.BindNumberWidget(ctx, slider,
        function() return ReadNumber(unit, "rangeFadeAlpha", 0.4) end,
        function(v) SetNumber(unit, "rangeFadeAlpha", v, "MSUF2_RANGE_FADE_ALPHA", { preview = true }) end,
        0.4,
        SettingMeta(ctx, "range_fade.alpha", unit, "rangeFadeAlpha"))
    if M.BindSliderDragPreview and M.SetRangeFadePreviewState then
        M.BindSliderDragPreview(slider, function(active, value)
            local layerMode = GetConf(unit).rangeFadeLayerMode == "health" and "health" or "frame"
            M.SetRangeFadePreviewState("unit", active, value, layerMode)
        end)
    end
    W.MoveWidget(slider, alphaCard, 16, -54, rightW - 58, "LEFT")
    local mode = W.Segment(alphaCard, "Affects", VT("frame", "Whole", "health", "HP"), rightW - 32)
    M.BindSegment(ctx, mode,
        function() return GetConf(unit).rangeFadeLayerMode == "health" and "health" or "frame" end,
        function(v) SetString(unit, "rangeFadeLayerMode", v == "health" and "health" or "frame", "MSUF2_RANGE_FADE_LAYER", { preview = true }) end,
        SettingMeta(ctx, "range_fade.layer_mode", unit, "rangeFadeLayerMode"))
    W.MoveWidget(mode, alphaCard, 16, -104, rightW - 32, "LEFT")
    RefreshRangeControls = RefreshRangeControls(function()
        local on = ReadBool(unit, "rangeFadeEnabled", true)
        SetControlEnabled(slider, on)
        SetControlEnabled(mode, on)
    end)
    M.TrackRefresh(ctx, RefreshRangeControls)
end
if type(UP.RegisterSection) == "function" then
    UP.RegisterSection({
        id = "range_fade",
        title = "Range Fade",
        height = 230,
        placement = "after_load_conditions",
        order = 10,
        units = RANGE_FADE_UNITS,
        build = BuildRangeFade,
    })
end
