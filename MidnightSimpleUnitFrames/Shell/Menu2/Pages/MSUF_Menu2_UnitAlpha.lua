local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local W = M.Widgets or {}
local UP = M.UnitPage or {}
local max = math.max
local SettingMeta = UP.SettingMeta

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
    local cardH = 180
    local healthX = leftX
    local resourceX = healthX + cardW + gap
    local optionsX = resourceX + cardW + gap
    local optionsW = innerW - (cardW * 2) - (gap * 2)
    local _, cardY = W.NextRow(sec, cardH)
    local healthCard = W.ControlCard(sec, "Health Bar", nil, healthX, cardY, cardW, cardH)
    local resourceCard = W.ControlCard(sec, "Resource Bar", nil, resourceX, cardY, cardW, cardH)
    local optionsCard = W.ControlCard(sec, "Options", nil, optionsX, cardY, optionsW, cardH)
    local function AddAlphaSlider(parent, width, spec)
        local slider = W.Slider(parent, spec.label, 0, 1, 0.05, width)
        M.UsePercentInput(slider)
        M.BindNumberWidget(ctx, slider,
            function() return ReadNumber(unit, spec.key, spec.default) end,
            function(v) SetNumber(unit, spec.key, v, spec.reason, spec.flags) end,
            spec.default,
            SettingMeta(ctx, "transparency." .. tostring(spec.key), unit, spec.key))
        W.MoveWidget(slider, parent, 16, spec.y, width - 58, "LEFT")
    end
    AddAlphaSlider(healthCard, cardW, { label = "Foreground", key = "hpBarAlpha", default = 1, reason = "MSUF2_ALPHA_HP", flags = { alpha = true, preview = true }, y = -54 })
    AddAlphaSlider(healthCard, cardW, { label = "Background", key = "hpBgAlpha", default = 0.85, reason = "MSUF2_ALPHA_BG", flags = { preview = true }, y = -112 })
    AddAlphaSlider(resourceCard, cardW, { label = "Foreground", key = "powerBarAlpha", default = 1, reason = "MSUF2_ALPHA_POWER", flags = { power = true, preview = true }, y = -54 })
    AddAlphaSlider(resourceCard, cardW, { label = "Background", key = "powerBarBgAlpha", default = 0.85, reason = "MSUF2_ALPHA_POWER_BG", flags = { power = true, preview = true }, y = -112 })
    local exclude = W.ToggleAt(optionsCard, "Keep text + portrait visible", 16, -62, optionsW - 32)
    M.BindBoolWidget(ctx, exclude,
        function() return ReadBool(unit, "alphaExcludeTextPortrait", false) end,
        function(v)
            SetBool(unit, "alphaExcludeTextPortrait", v, "MSUF2_ALPHA_EXCLUDE", { alpha = true, preview = true })
        end,
        SettingMeta(ctx, "transparency.alpha_exclude_text_portrait", unit, "alphaExcludeTextPortrait"))
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
