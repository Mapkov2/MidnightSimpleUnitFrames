-- Cold control declarations; existing bindings remain the only history/combat owners.
local _, MSUF = ...
local M = MSUF.MSUF2
local W = M.Widgets
local Schema = {}
M.ControlSchema = Schema

-- UI compatibility owns the old page fallbacks, not profile normalization.
-- Reading a declaration never seeds a saved key or repairs a partial import.
local UI_DEFAULTS = {
    gameplay = {
        combatTimerAnchor = "none", combatFontSize = 24, lockCombatTimer = false, combatTimerClickThrough = false,
        combatOffsetX = 0, combatOffsetY = -200, lockCombatState = false, combatStateFontSize = 24,
        combatStateDuration = 1.5, combatStateOffsetX = 0, combatStateOffsetY = 80,
        playerTotemsIconSize = 24, playerTotemsOffsetX = 0, playerTotemsOffsetY = -6,
        playerTotemsAnchorFrom = "TOPLEFT", playerTotemsAnchorTo = "BOTTOMLEFT", crosshairThickness = 3, crosshairSize = 40,
        enableCombatTimer = false, enableCombatStateText = false, enablePlayerTotems = false,
        enableCombatCrosshair = false, enableCombatCrosshairMeleeRangeColor = false,
        meleeSpellPerClass = false, meleeSpellPerSpec = false, combatStateEnterText = "+Combat", combatStateLeaveText = "-Combat",
    },
    unit = {
        hpBarAlpha = 1, hpBgAlpha = 0.85, powerBarAlpha = 1, powerBarBgAlpha = 0.85,
        alphaExcludeTextPortrait = false, alphaExcludePredictionBars = false, oocFadeEnabled = false, oocFadeAlpha = 0.5,
        rangeFadeEnabled = true, rangeFadeAlpha = 0.4, rangeFadeUpdateRate = 0, rangeFadeLayerMode = "frame",
    },
    bars = {
        showIgnorePain = false, showArcaneWindow = false, arcaneWindowTextFrom = 0, arcaneWindowWarnLastGCD = false,
        manaRegenPause = false, manaGainPulse = false, manaUpcomingCost = false, resourceExtraOffsetX = 0,
    },
}
local EXTRA_DEFAULTS = MSUF.CPBuilders.ExtraAuraDefaults
Schema.MarkDefaults = { target = "PLAYER", resource = "ALL", mode = "PERCENT", value = 50,
    width = 2, color = { 1, 1, 1 }, mark = true }
function Schema.Default(scope, key)
    local store = UI_DEFAULTS[scope] or UI_DEFAULTS.unit
    local value = store[key]
    if value == nil and scope == "bars" then value = EXTRA_DEFAULTS[key] end
    assert(value ~= nil, "legacy UI default missing: " .. scope .. "." .. key)
    return value
end

-- These flags preserve the current ApplyService interface. No reason-text inference
-- or pending core-domain implementation is introduced by the pilot.
local UNIT_DOMAINS = {
    alpha = { alpha = true, preview = true },
    background = { preview = true },
    powerAlpha = { power = true, preview = true },
    oocAlpha = { alpha = true },
    range = { preview = true },
}
function Schema.SetUnit(domain, unit, key, value, reason, kind)
    local flags = assert(UNIT_DOMAINS[domain], "unknown pilot unit apply domain")
    local owner = M.UnitPage
    if kind == "toggle" then return owner.SetBool(unit, key, value, reason, flags) end
    if kind == "slider" then return owner.SetNumber(unit, key, value, reason, flags) end
    return owner.SetString(unit, key, value, reason, flags)
end

local function Metadata(spec)
    local meta = {}
    for key, value in pairs(spec.meta or {}) do meta[key] = value end
    meta.controlId = spec.id
    if spec.settingPath then meta.settingKey = spec.settingPath end
    if spec.help then meta.help = spec.help end
    if spec.keywords then meta.keywords = spec.keywords end
    return meta
end
local function Accessors(spec)
    if spec.get then return spec.get, assert(spec.set, "schema custom setter missing") end
    local source = assert(spec.source, "schema setting source missing")
    local key = assert(spec.key, "schema setting key missing")
    local function Get()
        local value = source()[key]
        if value == nil then return spec.defaultSource() end
        if spec.kind == "slider" then return tonumber(value) or spec.defaultSource() end
        if spec.kind == "toggle" then return value and true or false end
        return value
    end
    local function Set(value)
        if spec.kind == "dropdown" and not value then value = spec.defaultSource() end
        return M.AdvancedPage.SetValue(source(), key, value, spec.apply)
    end
    return Get, Set
end
function Schema.Bind(ctx, widget, spec)
    assert(type(spec.id) == "string" and spec.id ~= "", "schema stable control ID missing")
    assert(spec.scope and spec.applyDomain, "schema scope/apply domain missing")
    local get, set = Accessors(spec)
    local meta = Metadata(spec)
    widget._msuf2ControlSchema = spec
    if spec.workspace == "classpower" then
        local fallback = spec.defaultSource and spec.defaultSource()
        M.ClassPowerWorkspace.Bind(spec.kind, ctx, widget, get, set, fallback, meta)
    elseif spec.kind == "slider" then
        assert(spec.range and spec.defaultSource, "schema slider range/default source missing")
        M.BindNumberWidget(ctx, widget, get, set, spec.defaultSource(), meta)
    elseif spec.kind == "toggle" then
        M.BindBoolWidget(ctx, widget, get, set, meta)
    elseif spec.kind == "dropdown" then
        M.BindDropdownWidget(ctx, widget, get, set, meta)
    elseif spec.kind == "segment" then
        M.BindSegment(ctx, widget, get, set, meta)
    elseif spec.kind == "textinput" then
        if spec.textAdapter then M.BindTextInputWidget(ctx, widget, get, set, spec.commitOnBlur, meta)
        else M.BindTextInput(ctx, widget, get, set, spec.commitOnBlur, meta) end
    elseif spec.kind == "color" then
        M.BindColor(ctx, widget, get, set, meta)
    else
        error("unsupported schema control kind: " .. tostring(spec.kind))
    end
    if spec.register then M.RegisterControlMetadata(widget, meta, spec.labelKey, spec.kind) end
    if spec.gate then
        M.TrackRefresh(ctx, function() W.SetControlEnabled(widget, spec.gate()) end)
    end
    return widget
end
-- Custom composite widgets keep their existing binding owner (scope/copy/color
-- shortcuts). Their declaration documents the seam without binding them twice.
function Schema.Custom(widget, spec)
    assert(spec.id and spec.kind and spec.scope and spec.applyDomain, "custom schema row is incomplete")
    widget._msuf2ControlSchema = spec
    return widget
end
-- Native Click dispatches the current owned button's scripts and separate hooks.
function Schema.ButtonAction(widget)
    return function(_, ...) return widget:Click(...) end
end
-- Composite chrome retains the exact registered owner, including navigation and
-- button scripts. Callers name the actual widget; no catalog scan manufactures rows.
function Schema.Owned(widget, scope, domain)
    local record = assert(widget._msuf2RuntimeControlRecord, "schema composite owner missing")
    local command = widget._msuf2CommandAction or record.command
    return Schema.Custom(widget, {
        id = record.controlId, kind = record.kind, labelKey = record.label,
        settingPath = record.settingKey, scope = scope, applyDomain = domain,
        meta = widget._msuf2SearchMeta, actionKey = record.actionKey,
        get = command and command.get and function(...)
            return (widget._msuf2CommandAction or record.command).get(...)
        end,
        set = command and command.set and function(...)
            return (widget._msuf2CommandAction or record.command).set(...)
        end,
        values = widget.GetValues and function() return widget:GetValues() end,
        action = widget.GetScript and widget:GetScript("OnClick") and Schema.ButtonAction(widget), owner = widget,
    })
end
function Schema.Section(section, scope)
    local header = assert(section._msuf2CollapsibleEntry).header
    Schema.Owned(header, scope, "sectionNavigation")
    local id = header._msuf2RuntimeControlRecord.controlId .. ".colors"
    Schema.ContextColors(section, id, scope)
    Schema.ContextColors(header, id, scope)
    return section
end
-- Opt in at the pilot's existing card/section owner. The shortcut keeps its
-- installed click wrapper, current options and relevance callback; it stays
-- noSearch and never gains a second command or input/history binding.
function Schema.ContextColors(card, id, scope)
    local function Declare(widget)
        Schema.Custom(widget, {
            id = id, kind = "button", labelKey = widget._msuf2Label:GetText(),
            scope = scope, applyDomain = "contextColors", owner = widget,
            get = function() return widget._msuf2ContextColorOptions end,
            action = Schema.ButtonAction(widget), gate = widget._msuf2RefreshContextColorVisibility,
        })
    end
    card._msuf2DeclareContextColorShortcut = Declare
    if card._msuf2ContextColorShortcut then Declare(card._msuf2ContextColorShortcut) end
    return card
end
function Schema.Render(ctx, parent, spec, layout)
    if spec.wanted and not spec.wanted() then return nil end
    layout = layout or spec.layout or {}
    local width = layout.width or 280
    local label = spec.labelKey
    local widget
    if spec.kind == "slider" then
        local range = spec.range
        widget = W.Slider(parent, label, range[1], range[2], range[3], width)
        if spec.percent then M.UsePercentInput(widget) end
    elseif spec.kind == "toggle" then
        if spec.view == "header" then widget = W.SectionSwitch(parent, label)
        elseif spec.view == "switch" then widget = W.SwitchAt(parent, label, layout.x, layout.y, width)
        else widget = W.Toggle(parent, label) end
    elseif spec.kind == "dropdown" then widget = W.Dropdown(parent, label, spec.values, width)
    elseif spec.kind == "segment" then widget = W.Segment(parent, label, spec.values, width)
    elseif spec.kind == "textinput" then widget = W.TextInput(parent, label, width, spec.translatedLabel)
    else error("schema custom widget must be supplied to Bind") end
    if spec.beforeBind then spec.beforeBind(widget) end
    Schema.Bind(ctx, widget, spec)
    if layout.x and spec.view ~= "switch" then
        W.MoveWidget(widget, parent, layout.x, layout.y, layout.moveWidth, layout.align)
    end
    return widget
end
function Schema.Flow(ctx, parent, rows, layout)
    local controls = {}
    for i, spec in ipairs(rows) do
        local column = (i - 1) % layout.columns
        local row = math.floor((i - 1) / layout.columns)
        controls[spec.key or spec.id] = Schema.Render(ctx, parent, spec, {
            width = layout.width, x = layout.x + column * (layout.width + layout.gap),
            y = layout.y - row * layout.rowHeight,
            moveWidth = layout.moveWidth or (spec.kind == "toggle" and layout.width - 36 or layout.width),
            align = layout.align,
        })
    end
    return controls
end
