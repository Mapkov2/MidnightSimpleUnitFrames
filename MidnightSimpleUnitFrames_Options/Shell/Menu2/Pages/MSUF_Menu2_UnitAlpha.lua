local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local W = M.Widgets or {}
local UP = M.UnitPage or {}
local max = math.max
local SettingMeta = UP.SettingMeta
local Schema = M.ControlSchema
local ALPHA_ROWS = {
    { key = "hpBarAlpha", path = "transparency.hpBarAlpha", kind = "slider", labelKey = "Foreground",
        card = "health", y = -54,
        domain = "alpha", reason = "MSUF2_ALPHA_HP" },
    { key = "hpBgAlpha", path = "transparency.hpBgAlpha", kind = "slider", labelKey = "Background",
        card = "health", y = -112,
        domain = "background", reason = "MSUF2_ALPHA_BG" },
    { key = "powerBarAlpha", path = "transparency.powerBarAlpha", kind = "slider", labelKey = "Foreground",
        card = "resource", y = -54,
        domain = "powerAlpha", reason = "MSUF2_ALPHA_POWER" },
    { key = "powerBarBgAlpha", path = "transparency.powerBarBgAlpha", kind = "slider", labelKey = "Background",
        card = "resource", y = -112,
        domain = "powerAlpha", reason = "MSUF2_ALPHA_POWER_BG" },
    { key = "alphaExcludeTextPortrait", path = "transparency.alpha_exclude_text_portrait", kind = "toggle", labelKey = "Keep text + portrait visible",
        card = "options", y = -62,
        domain = "alpha", reason = "MSUF2_ALPHA_EXCLUDE" },
    { key = "alphaExcludePredictionBars", path = "transparency.alpha_exclude_prediction_bars", kind = "toggle", labelKey = "Keep Absorbs + Prediction Visible",
        card = "options", y = -112,
        domain = "alpha", reason = "MSUF2_ALPHA_EXCLUDE_PREDICTION" },
    { key = "oocFadeEnabled", path = "transparency.ooc_fade_enabled", kind = "toggle", labelKey = "Fade frame out of combat",
        card = "ooc", y = -54,
        domain = "oocAlpha", reason = "MSUF2_ALPHA_OOC_FADE" },
    { key = "oocFadeAlpha", path = "transparency.ooc_fade_alpha", kind = "slider", labelKey = "Out of Combat Opacity",
        card = "ooc", y = -112,
        domain = "oocAlpha", reason = "MSUF2_ALPHA_OOC_ALPHA" },
}

-- Unified, simple transparency: separate health/resource opacity cards with
-- foreground and background sliders, plus one toggle that keeps frame texts +
-- portrait fully opaque while bars dim. Range fade multiplies HP at runtime.
local function AlphaMeta(ctx, path, unit, key, state)
    local meta = SettingMeta(ctx, path, unit, key)
    local tab = (key == "oocFadeEnabled" or key == "oocFadeAlpha") and "ooc" or "combat"
    meta.searchPrepareKind, meta.searchPrepareValue = "unitAlphaTab", tab
    meta.prepareExactSearchTarget = function(_, target)
        if target.prepareKind ~= "unitAlphaTab" or target.prepareValue ~= tab then return false end
        state.value = tab
        state.apply()
        return true
    end
    return meta
end
local function AlphaColorCard(ctx, section, unit, key, ...)
    local id = "menu2." .. ctx.key .. ".section.transparency.colors." .. key
    return Schema.ContextColors(W.ControlCard(section, ...), id, unit)
end
local function BuildAlpha(ctx, builder, unit)
    local tabState = { value = "combat" }
    local ReadBool = UP.ReadBool
    local ReadNumber = UP.ReadNumber
    local GetConf = UP.GetConf
    local GetGeneral = UP.GetGeneral
    local GetBars = UP.GetBars
    if not (ReadBool and ReadNumber) then return end
    local sec = Schema.Section(builder:CollapsibleSection("transparency", "Transparency", nil, false), unit)
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
    local healthCard = AlphaColorCard(ctx, sec, unit, "health", "Health Bar", nil, healthX, cardY, cardW, cardH)
    local resourceCard = AlphaColorCard(ctx, sec, unit, "resource", "Resource Bar", nil, resourceX, cardY, cardW, cardH)
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
        local function HealthColorRefs()
            local mode = EffectiveHealthMode()
            local refs = {}
            if mode == "gradient" then
                refs = { "health.gradient.low", "health.gradient.mid", "health.gradient.high" }
            elseif mode == "unified" then
                refs = { "health.unified" }
            elseif mode == "class" then
                refs = { unit == "pet" and "unit.pet" or "health.current" }
            end
            refs[#refs + 1] = "health.background.current"
            return refs
        end
        local function HealthColorContext()
            return { unit = unit, healthMode = EffectiveHealthMode() }
        end
        local function HealthColorShortcutRelevant()
            local resolver = M.ResolveContextColorReferences
            if type(resolver) ~= "function" then return false end
            local targets = resolver(HealthColorRefs(), HealthColorContext())
            local count = type(targets) == "table" and #targets or 0
            return count > 0 and count <= 6
        end
        W.AttachContextColorReferences(healthCard, HealthColorRefs, {
            title = "Health Bar Colors",
            note = "Colors follow this frame's effective Health Color Scheme.",
            historySource = "menu:unit-alpha-health-colors",
            maxTargets = 6,
            context = HealthColorContext,
            isRelevant = HealthColorShortcutRelevant,
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
    local cards = { health = healthCard, resource = resourceCard, options = optionsCard, ooc = oocCard }
    local widths = { health = cardW, resource = cardW, options = optionsW, ooc = cardW }
    local controls = {}
    for _, row in ipairs(ALPHA_ROWS) do
        local meta = AlphaMeta(ctx, row.path, unit, row.key, tabState)
        local function Default() return Schema.Default(unit, row.key) end
        local read = row.kind == "slider" and ReadNumber or ReadBool
        local width = widths[row.card]
        controls[row.key] = Schema.Render(ctx, cards[row.card], {
            id = meta.controlId, kind = row.kind, labelKey = row.labelKey, key = row.key,
            settingPath = unit .. "." .. row.key, scope = unit, applyDomain = row.domain,
            range = row.kind == "slider" and { 0, 1, 0.05 } or nil, percent = row.kind == "slider",
            defaultSource = Default, meta = meta,
            get = function() return read(unit, row.key, Default()) end,
            set = function(value)
                Schema.SetUnit(row.domain, unit, row.key, value, row.reason, row.kind)
                if row.key == "oocFadeEnabled" then
                    UP.SetControlEnabled(controls.oocFadeAlpha, ReadBool(unit, row.key, Default()))
                end
            end,
        }, { width = width, x = 16, y = row.y,
            moveWidth = row.kind == "slider" and width - 58 or (row.key == "oocFadeEnabled" and width + 40 or width - 32),
            align = "LEFT" })
    end
    UP.SetControlEnabled(controls.oocFadeAlpha, ReadBool(unit, "oocFadeEnabled", Schema.Default(unit, "oocFadeEnabled")))

    -- Tab switch: show either the base opacity cards or the OOC fade card.
    local combatCards = { healthCard, resourceCard, optionsCard }
    tabState.apply = function()
        local ooc = tabState.value == "ooc"
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
        getValue = function() return tabState.value end,
        setValue = function(value)
            tabState.value = value == "ooc" and "ooc" or "combat"
            tabState.apply()
        end,
    })
    if UP.RegisterControl then
        UP.RegisterControl(stateBar, ctx, "transparency.state_selector", "Editing", "segment", "ephemeral")
    end
    Schema.Custom(stateBar,{
        id="menu2."..ctx.key..".unit.transparency.state_selector",kind="segment",labelKey="Editing",
        scope=unit,applyDomain="navigation",values=stateBar.values,get=function() return stateBar:GetValue() end,
        set=function(value) return stateBar:SetValue(value) end,
    })
    tabState.apply()
    if builder.FinishSection then builder:FinishSection(sec, 48) end
end
if type(UP.RegisterSection) == "function" then
    UP.RegisterSection({
        id = "transparency",
        title = "Transparency",
        autoHeight = true,
        placement = "after_load_conditions",
        order = 20,
        prepareShell = function(_, section, unit) Schema.Section(section, unit) end,
        build = BuildAlpha,
    })
end
