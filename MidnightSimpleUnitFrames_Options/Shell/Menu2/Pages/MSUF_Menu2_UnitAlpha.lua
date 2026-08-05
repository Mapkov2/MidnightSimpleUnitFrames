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
    local GetConf = UP.GetConf
    local GetGeneral = UP.GetGeneral
    local GetBars = UP.GetBars
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
    -- State tab row: the base cards edit the general, always-on opacities,
    -- the second tab holds the whole-frame out-of-combat fade. Menu-session
    -- state only, never persisted.
    local _, barY = W.NextRow(sec, 34)
    local _, cardY = W.NextRow(sec, cardH)
    local healthCard = W.ControlCard(sec, "Health Bar", nil, healthX, cardY, cardW, cardH)
    local resourceCard = W.ControlCard(sec, "Resource Bar", nil, resourceX, cardY, cardW, cardH)
    local optionsCard = W.ControlCard(sec, "Options", nil, optionsX, cardY, optionsW, cardH)
    local oocCard = W.ControlCard(sec, "Out of Combat", nil, healthX, cardY, innerW, cardH)
    if W.AttachContextColorReferences and GetGeneral then
        local function EffectiveHealthMode()
            local conf = GetConf and GetConf(unit) or {}
            local mode = type(conf.healthColorMode) == "string" and conf.healthColorMode:lower() or nil
            if mode == "global" or (mode ~= "class" and mode ~= "gradient" and mode ~= "unified" and mode ~= "dark") then
                local general = GetGeneral()
                mode = type(general.barMode) == "string" and general.barMode:lower() or nil
                if mode ~= "class" and mode ~= "gradient" and mode ~= "unified" and mode ~= "dark" then
                    mode = general.useClassColors == true and "class" or "dark"
                end
                if mode == "gradient" and general.enableHealthGradient == false then mode = "class" end
            end
            return mode
        end
        W.AttachContextColorReferences(healthCard, function()
            local mode = EffectiveHealthMode()
            local refs = {}
            if mode == "gradient" then
                refs = { "health.gradient.low", "health.gradient.mid", "health.gradient.high" }
            elseif mode == "unified" then
                refs = { "health.unified" }
            elseif mode == "class" then
                refs = { unit == "pet" and "unit.pet" or "health.current" }
            end
            local general = GetGeneral()
            if general.barBgMatchHPColor ~= true and general.barBgClassColor ~= true then
                refs[#refs + 1] = "bar.background_tint"
            end
            return refs
        end, {
            title = "Health Bar Colors",
            note = "Colors follow this frame's effective Health Color Scheme.",
            historySource = "menu:unit-alpha-health-colors",
            context = function() return { unit = unit, healthMode = EffectiveHealthMode() } end,
        })
        W.AttachContextColorReferences(resourceCard, function()
            local refs = { "power.current" }
            local general = GetGeneral()
            local bars = GetBars and GetBars() or {}
            if not (general.powerBarBgMatchBarColor == true or bars.powerBarBgMatchBarColor == true) then
                refs[#refs + 1] = "bar.power_background"
            end
            return refs
        end, {
            title = "Resource Bar Colors",
            note = "A matched resource background is derived from Health instead.",
            historySource = "menu:unit-alpha-resource-colors",
            context = function() return { unit = unit } end,
        })
    end
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

    -- Out of Combat tab: whole-frame fade while out of combat. The slider is
    -- greyed while the toggle is off; runtime min-composes with range fade.
    local oocToggle = W.ToggleAt(oocCard, "Fade frame out of combat", 16, -54, cardW + 40)
    local oocSlider = W.Slider(oocCard, "Out of Combat Opacity", 0, 1, 0.05, cardW)
    M.UsePercentInput(oocSlider)
    local function UpdateOocEnabledState()
        if UP.SetControlEnabled then
            UP.SetControlEnabled(oocSlider, ReadBool(unit, "oocFadeEnabled", false))
        end
    end
    M.BindBoolWidget(ctx, oocToggle,
        function() return ReadBool(unit, "oocFadeEnabled", false) end,
        function(v)
            SetBool(unit, "oocFadeEnabled", v, "MSUF2_ALPHA_OOC_FADE", { alpha = true })
            UpdateOocEnabledState()
        end,
        SettingMeta(ctx, "transparency.ooc_fade_enabled", unit, "oocFadeEnabled"))
    M.BindNumberWidget(ctx, oocSlider,
        function() return ReadNumber(unit, "oocFadeAlpha", 0.5) end,
        function(v) SetNumber(unit, "oocFadeAlpha", v, "MSUF2_ALPHA_OOC_ALPHA", { alpha = true }) end,
        0.5,
        SettingMeta(ctx, "transparency.ooc_fade_alpha", unit, "oocFadeAlpha"))
    W.MoveWidget(oocSlider, oocCard, 16, -112, cardW - 58, "LEFT")
    UpdateOocEnabledState()

    -- Tab switch: show either the base opacity cards or the OOC fade card.
    local alphaTab = "combat"
    local combatCards = { healthCard, resourceCard, optionsCard }
    local function ApplyAlphaTab()
        local ooc = alphaTab == "ooc"
        for i = 1, #combatCards do
            W.SetControlShown(combatCards[i], not ooc)
        end
        W.SetControlShown(oocCard, ooc)
    end
    local stateBar = W.ScopeOverrideBar(ctx, sec, {
        values = {
            { value = "combat", text = "General" },
            { value = "ooc", text = "Out of Combat" },
        },
        width = sectionW,
        label = "Editing:",
        labelX = leftX,
        labelWidth = 64,
        centerY = barY - 16,
        getValue = function() return alphaTab end,
        setValue = function(value)
            alphaTab = value == "ooc" and "ooc" or "combat"
            ApplyAlphaTab()
        end,
    })
    if UP.RegisterControl then
        UP.RegisterControl(stateBar, ctx, "transparency.state_selector", "Editing", "segment", "ephemeral")
    end
    ApplyAlphaTab()
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
