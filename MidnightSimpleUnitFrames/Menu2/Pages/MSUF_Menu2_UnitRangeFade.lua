local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets or {}
local UP = M.UnitPage or {}

local floor = math.floor
local max = math.max

local RANGE_FADE_UNITS = {
    target = true,
    targettarget = true,
    focus = true,
    focustarget = true,
    pet = true,
    boss = true,
}

local function PercentValue(value)
    return tostring(floor((tonumber(value) or 0) * 100 + 0.5)) .. "%"
end

local function BuildRangeFade(ctx, builder, unit)
    local ReadBool = UP.ReadBool
    local SetBool = UP.SetBool
    local ReadNumber = UP.ReadNumber
    local SetNumber = UP.SetNumber
    local SetString = UP.SetString
    local SetControlEnabled = UP.SetControlEnabled
    local GetConf = UP.GetConf
    if not (ReadBool and SetBool and ReadNumber and SetNumber and SetString and SetControlEnabled and GetConf) then return end

    local sec = builder:CollapsibleSection("range_fade", "Range Fade", 214, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local gap = 16
    local leftX = 20
    local innerW = max(320, sectionW - 40)
    local leftW = floor((innerW - gap) * 0.48)
    local rightX = leftX + leftW + gap
    local rightW = innerW - leftW - gap

    local mainCard = W.ControlCard(sec, "Range", "Unitframe range fade.", leftX, -38, leftW, 150)
    local alphaCard = W.ControlCard(sec, "Out of range", "Opacity multiplier and affected layer.", rightX, -38, rightW, 150)

    local enabled = W.ToggleAt(mainCard, "Enable Range Fade", 16, -54, leftW - 32)
    M.BindToggle(ctx, enabled,
        function() return ReadBool(unit, "rangeFadeEnabled", true) end,
        function(v) SetBool(unit, "rangeFadeEnabled", v, "MSUF2_RANGE_FADE", { preview = true }) end)

    local slider = W.Slider(alphaCard, "", 0, 1, 0.05, rightW - 58)
    if slider.SetValueFormatter then slider:SetValueFormatter(PercentValue) end
    M.BindSlider(ctx, slider,
        function() return ReadNumber(unit, "rangeFadeAlpha", 0.4) end,
        function(v) SetNumber(unit, "rangeFadeAlpha", v, "MSUF2_RANGE_FADE_ALPHA", { preview = true }) end)
    W.MoveWidget(slider, alphaCard, 16, -54, rightW - 58, "LEFT")

    local mode = W.Segment(alphaCard, "Affects", {
        { value = "frame", text = "Whole" },
        { value = "health", text = "HP" },
    }, rightW - 32)
    M.BindSegment(ctx, mode,
        function() return GetConf(unit).rangeFadeLayerMode == "health" and "health" or "frame" end,
        function(v) SetString(unit, "rangeFadeLayerMode", v == "health" and "health" or "frame", "MSUF2_RANGE_FADE_LAYER", { preview = true }) end)
    W.MoveWidget(mode, alphaCard, 16, -104, rightW - 32, "LEFT")

    local function RefreshRangeControls()
        local on = ReadBool(unit, "rangeFadeEnabled", true)
        SetControlEnabled(slider, on)
        SetControlEnabled(mode, on)
    end
    M.AddRefresher(ctx, RefreshRangeControls)
    RefreshRangeControls()
end

if type(UP.RegisterSection) == "function" then
    UP.RegisterSection({
        id = "range_fade",
        placement = "after_load_conditions",
        order = 10,
        units = RANGE_FADE_UNITS,
        build = BuildRangeFade,
    })
end
