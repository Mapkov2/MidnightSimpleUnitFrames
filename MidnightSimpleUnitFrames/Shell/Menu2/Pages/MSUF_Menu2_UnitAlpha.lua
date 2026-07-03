local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local W = M.Widgets or {}
local UP = M.UnitPage or {}
local max = math.max
local AlphaLabel = M.AlphaLabel

-- Unified, simple transparency: separate health/resource opacity cards with
-- foreground and background sliders, plus one toggle that keeps frame texts +
-- portrait fully opaque while bars dim. Range fade multiplies HP at runtime.
local function BuildAlpha(ctx, builder, unit)
    local ReadBool = UP.ReadBool
    local SetBool = UP.SetBool
    local ReadNumber = UP.ReadNumber
    local SetNumber = UP.SetNumber
    if not (ReadBool and SetBool and ReadNumber and SetNumber) then return end
    local sec = builder:CollapsibleSection("transparency", "Transparency", nil, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local gap = 16
    local leftX = 20
    local innerW = max(320, sectionW - 40)
    local cardW = math.floor((innerW - (gap * 2)) / 3)
    local cardH = 168
    local healthX = leftX
    local resourceX = healthX + cardW + gap
    local optionsX = resourceX + cardW + gap
    local optionsW = innerW - (cardW * 2) - (gap * 2)
    local _, cardY = W.NextRow(sec, cardH)
    local healthCard = W.ControlCard(sec, "Opacity Health", "Fade the health bar foreground and background.", healthX, cardY, cardW, cardH)
    local resourceCard = W.ControlCard(sec, "Opacity Resource Bar", "Fade the resource bar foreground and background.", resourceX, cardY, cardW, cardH)
    local optionsCard = W.ControlCard(sec, "Options", "Keep text and portrait readable while bars fade.", optionsX, cardY, optionsW, cardH)
    local function AddAlphaSlider(parent, width, spec)
        local slider = W.Slider(parent, "", 0, 1, 0.05, width)
        M.BindNumberWidget(ctx, slider,
            function() return ReadNumber(unit, spec.key, spec.default) end,
            function(v) SetNumber(unit, spec.key, v, spec.reason, spec.flags) end,
            spec.default)
        M.BindSliderLiveLabel(ctx, slider, function() return ReadNumber(unit, spec.key, spec.default) end,
            function(value) return AlphaLabel(spec.label, value) end, true)
        W.MoveWidget(slider, parent, 16, spec.y, width - 58, "LEFT")
    end
    AddAlphaSlider(healthCard, cardW, { label = "Foreground", key = "hpBarAlpha", default = 1, reason = "MSUF2_ALPHA_HP", flags = { alpha = true, preview = true }, y = -62 })
    AddAlphaSlider(healthCard, cardW, { label = "Background", key = "hpBgAlpha", default = 0.85, reason = "MSUF2_ALPHA_BG", flags = { preview = true }, y = -100 })
    AddAlphaSlider(resourceCard, cardW, { label = "Foreground", key = "powerBarAlpha", default = 1, reason = "MSUF2_ALPHA_POWER", flags = { power = true, preview = true }, y = -62 })
    AddAlphaSlider(resourceCard, cardW, { label = "Background", key = "powerBarBgAlpha", default = 0.85, reason = "MSUF2_ALPHA_POWER_BG", flags = { power = true, preview = true }, y = -100 })
    local exclude = W.ToggleAt(optionsCard, "Keep text + portrait visible", 16, -62, optionsW - 32)
    M.BindBoolWidget(ctx, exclude,
        function() return ReadBool(unit, "alphaExcludeTextPortrait", false) end,
        function(v)
            SetBool(unit, "alphaExcludeTextPortrait", v, "MSUF2_ALPHA_EXCLUDE", { alpha = true, preview = true })
        end)
    local hint = W.Text(optionsCard, "", 16, -94, optionsW - 32, nil)
    if hint and hint.SetWordWrap then hint:SetWordWrap(true) end
    if hint and hint.SetText then hint:SetText(M.Tr("On: bars and background fade while text and portrait stay visible. Off: text and portrait fade with them.")) end
    if builder.FinishSection then builder:FinishSection(sec, 48) end
end
if type(UP.RegisterSection) == "function" then
    UP.RegisterSection({
        id = "transparency",
        title = "Transparency",
        autoHeight = true,
        placement = "after_load_conditions",
        order = 20,
        build = BuildAlpha,
    })
end
