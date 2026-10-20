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
    arenaTrinket = { preview = true },
    layout = { preview = true },
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
    if spec.roundStep then meta.step, meta.roundStep = spec.range[3], true end
    return meta
end
-- Unit rows read and write through the UnitPage adapters, as the old section
-- binders did; `after` runs once the setter returns.
local function UnitAccessors(spec)
    local unit, key, owner = spec.unit, spec.key, M.UnitPage
    local function Get()
        if spec.kind == "toggle" then return owner.ReadBool(unit, key, spec.defaultSource()) end
        if spec.kind == "slider" then return owner.ReadNumber(unit, key, spec.defaultSource()) end
        return owner.GetConf(unit)[key] or spec.defaultSource()
    end
    local function Set(value)
        Schema.SetUnit(spec.applyDomain, unit, key, value, spec.reason, spec.kind)
        if spec.after then spec.after(value) end
    end
    return Get, Set
end
local function Accessors(spec)
    if spec.get then return spec.get, assert(spec.set, "schema custom setter missing") end
    if spec.unit then return UnitAccessors(spec) end
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
        M.BindNumberWidget(ctx, widget, get, set, spec.numberFallback or spec.defaultSource(), meta)
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
        elseif spec.view == "at" then widget = W.ToggleAt(parent, label, layout.x, layout.y, width)
        else widget = W.Toggle(parent, label) end
    elseif spec.kind == "dropdown" then widget = W.Dropdown(parent, label, spec.values, width)
    elseif spec.kind == "segment" then widget = W.Segment(parent, label, spec.values, width)
    elseif spec.kind == "textinput" then widget = W.TextInput(parent, label, width, spec.translatedLabel)
    else error("schema custom widget must be supplied to Bind") end
    if spec.beforeBind then spec.beforeBind(widget) end
    Schema.Bind(ctx, widget, spec)
    -- Toggles created at a position are already placed.
    if layout.x and not (spec.kind == "toggle" and (spec.view == "switch" or spec.view == "at")) then
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

-- Replacing rows hold kind, key, UI default, native constructor arguments and
-- optional placement arguments.
local ROW_CREATORS = {
    switch = "SwitchAt", toggle = "ToggleAt",
    slider = "Slider", dropdown = "Dropdown",
    textinput = "TextInput", color = "Color",
    sectionSwitch = "SectionSwitch", segment = "Segment", flowToggle = "Toggle",
    text = "Text", topButton = "TopButton", roleButton = "RoleButton",
}
local ROW_KINDS = { switch = "toggle", toggle = "toggle",
    slider = "slider", dropdown = "dropdown", textinput = "textinput", color = "color",
    sectionSwitch = "toggle", flowToggle = "toggle", segment = "segment" }
local ROW_CHROME = { text = "text", font = "font", card = "card",
    scopebar = "segment", topButton = "button", roleButton = "button" }
local function PlaceRow(widget, parent, row)
    local p = row[5]
    if not p then return end
    W.MoveWidget(widget, parent, p[1], p[2], p[3], p[4])
end
local function RowFlags(widget, flags)
    if not flags then return end
    for key, value in pairs(flags) do widget[key] = value end
end
-- Composite rows call the native owner once; a scope bar must never receive
-- a second segment binding. Cards declare existing and later-attached shortcuts.
local function CreateCompositeRow(ctx, parent, row)
    local kind, args = row[1], row[4]
    if kind == "font" then return M.Theme.Font(parent, unpack(args)) end
    if kind == "scopebar" then return W.ScopeOverrideBar(ctx, parent, args[1]) end
    if kind == "card" then
        return W.ControlCard(parent, args[1], args[2], args[3], args[4], args[5], args[6], args[7])
    end
    error("unsupported replacing row")
end
local function DeclareRow(ctx, widget, row, kind)
    local scope = row.scope or (ctx and ctx.key) or "shared"
    if row[1] == "scopebar" then
        Schema.Owned(widget, scope, row.domain or "menuState")
        local spec = widget._msuf2ControlSchema
        spec.get = function() return widget:GetValue() end
        spec.set = function(value) return widget:SetValue(value) end
        spec.values = widget.values
        return
    end
    local meta = row.meta
    local id = meta and meta.controlId or row[2]
    Schema.Custom(widget, { id = id, kind = kind,
        labelKey = row[1] == "font" and row[4][2] or row[4][1], meta = meta,
        scope = scope, applyDomain = row.domain or "presentation", owner = widget,
        action = kind == "button" and Schema.ButtonAction(widget) or nil })
    if kind == "card" then Schema.ContextColors(widget, id .. ".colors", scope) end
end
-- The UnitSections typed policy, shared without changing its native binders.
function Schema.UnitBinding(ctx, widget, row, kind)
    if row.bind then
        row.bind(widget)
        if widget._msuf2ControlSchema then return widget end
        return Schema.Custom(widget, { id = row[2], kind = kind, labelKey = row[4][1],
            scope = row.scope or "shared", applyDomain = "menuState", owner = widget })
    end
    local meta = assert(row.meta, "unit row metadata missing")
    local spec = { id = meta.controlId, kind = kind, key = row[2], labelKey = row[4][1],
        meta = meta, scope = row.scope or ctx.key, applyDomain = row.domain or "unit",
        settingPath = meta.settingKey, get = row.get, set = row.set, unit = row.unit,
        reason = row.reason, commitOnBlur = row.commitOnBlur,
        defaultSource = function() return row[3] end, roundStep = row.roundStep }
    if kind == "slider" then spec.range = { row[4][2], row[4][3], row[4][4] } end
    return Schema.Bind(ctx, widget, spec)
end
function Schema.UnitOptions()
    return { bind = Schema.UnitBinding }
end
function Schema.Build(ctx, parent, rows, opts, refs)
    opts, refs = opts or {}, refs or {}
    for _, row in ipairs(rows) do
        local widget, args, rowParent = nil, row[4], row.parent or parent
        if row[1] == "button" then widget = M.Theme.Button(rowParent, unpack(args))
        elseif ROW_CREATORS[row[1]] then widget = W[ROW_CREATORS[row[1]]](rowParent, unpack(args))
        else widget = CreateCompositeRow(ctx, rowParent, row) end
        refs[row[2]] = widget
        if row.anchor then widget:SetPoint(unpack(row.anchor)) end
        if row.center then M.Theme.CenterButtonLabel(widget) end
        RowFlags(widget, row.flagsBefore)
        if opts.beforeBind then opts.beforeBind(widget, row) end
        if row.beforeBind then row.beforeBind(widget, row) end
        if ROW_KINDS[row[1]] then opts.bind(ctx, widget, row, ROW_KINDS[row[1]]) end
        RowFlags(widget, row.flagsAfter)
        if row.tip and M.AddTooltip then M.AddTooltip(widget, unpack(row.tip)) end
        if row.action then widget:SetScript("OnClick", row.action) end
        if row.register then assert(opts.register, "schema row registry missing")(ctx, widget, row) end
        if ROW_CHROME[row[1]] then DeclareRow(ctx, widget, row, ROW_CHROME[row[1]]) end
        PlaceRow(widget, rowParent, row)
    end
    return refs
end

-- Shared column arithmetic keeps each page's existing inset, ratio and caps.
function Schema.Columns(parent, width, inset, gap, ratio, leftLow, leftHigh, rightLow, rightHigh)
    width = parent._msuf2Width or width or 720
    local inner = math.max(320, width - inset * 2)
    local left = math.floor((inner - gap) * ratio)
    if leftLow then left = math.max(leftLow, math.min(leftHigh, left)) end
    local right = inner - left - gap
    if rightLow then right = math.max(rightLow, math.min(rightHigh, right)) end
    return inset, left, inset + left + gap, right, inner, width
end

-- Named color options retain the exact existing shortcut/reference owner.
function Schema.Colors(parent, references, opts)
    local create = references and W.AttachContextColorReferences or W.AttachContextColorShortcut
    if not create then return end
    if references then return create(parent, references, opts) end
    return create(parent, opts)
end

-- Group scope resolves at input time. The existing group and central bindings
-- retain sole ownership of history, combat refusal, rounding and apply requests.
function Schema.GroupBinding(ctx, widget, row, kind)
    local gp = M.GroupPage
    local key, default, domain = row[2], row[3], row.domain or "visual"
    local meta = gp.ControlMeta(ctx, row.path or "field." .. tostring(key), row.classification)
    local spec = { id = meta.controlId, kind = kind, key = key, labelKey = row[4][1],
        scope = "group", applyDomain = domain, meta = meta }
    local bind = kind == "toggle" and gp.BindScopeToggle or kind == "slider" and gp.BindScopeSlider
        or kind == "dropdown" and gp.BindScopeDropdown
    assert(bind, "unsupported group scope kind: " .. tostring(kind))(ctx, widget, key, default, domain, meta)
    local command = widget._msuf2CommandAction
    spec.get, spec.set = command and command.get, command and command.set
    Schema.Custom(widget, spec)
end

-- Record rows retain the selected scope and nested-record owners at input time.
-- A missing record differs from a missing toggle field; false subtypes disable it.
local function CommandAccessors(owner, row, kind, widget, ctx)
    if row.set then return assert(row.get, "command row getter missing"), row.set, row[3] end
    local command = row.lifecycle and row.lifecycle(widget, ctx, row) or owner.commands[row[2]]
    local fallback = command.default
    if fallback == nil then fallback = row[3] end
    return command.get, command.set, fallback, command.afterBind
end
local function RecordAccessors(owner, row, kind, widget, ctx)
    if row.lifecycle then return CommandAccessors(owner, row, kind, widget, ctx) end
    if row.set then return assert(row.get, "record row getter missing"), row.set, row[3] end
    local config, scope, key, default = row.source or owner.config, owner.scope, row[2], row[3]
    local function Get()
        local record = config(scope(), false)
        if kind == "color" then
            local fields = row.channels
            return (record and record[fields[1]]) or default[1],
                (record and record[fields[2]]) or default[2], (record and record[fields[3]]) or default[3]
        end
        local value = record and record[key]
        if row.subtype then return type(value) == "table" and value.type or "none" end
        if kind == "toggle" then
            if not record then return false end
            if value == nil then return default and true or false end
            if owner.strictToggles then return value == true end
            return value and true or false
        end
        if kind == "slider" then return tonumber(value) or default end
        return value or default
    end
    local function Set(value, green, blue)
        if row.accept and not row.accept(value) then return end
        local record = config(scope(), true)
        if kind == "color" then
            if record then record[row.channels[1]], record[row.channels[2]], record[row.channels[3]] = value, green, blue end
        elseif row.subtype then
            if not record then return end
            if value == "none" then record[key] = false
            else
                record[key] = type(record[key]) == "table" and record[key] or {}
                record[key].type = value
                if row.defaults then row.defaults(record[key]) end
            end
        elseif not record and row.requireRecord then return
        elseif record then
            if row.convert then
                local converted = row.convert(value)
                record[key] = converted
                if row.afterWrite then row.afterWrite(record, converted) end
            elseif kind == "toggle" then
                if row.uncheckedNil then record[key] = value and true or nil
                elseif owner.strictToggles then record[key] = value == true
                else record[key] = value and true or false end
            elseif kind == "slider" then
                local number = tonumber(value) or default
                record[key] = owner.rawNumber and number or math.floor(number + 0.5)
            else record[key] = value or default end
        end
        owner.changed(scope())
        local afterSet = row.afterSet or (kind == "toggle" and owner.afterToggle)
        if afterSet then afterSet() end
    end
    return row.get or Get, Set, row[3]
end
local function GroupBindingOptions(owner, accessors)
    return { bind = function(ctx, widget, row, kind)
        if row.bind then
            row.bind(ctx, widget, row)
            Schema.Owned(widget, "group", row.domain or "visual")
            return
        end
        local get, set, fallback, afterBind = accessors(owner, row, kind, widget, ctx)
        local path = row.path or owner.path .. tostring(row[2])
        if row.identitySuffix then path = path .. "." .. row.identitySuffix end
        local meta = kind == "slider" and owner.stepMeta(ctx, path, row[4][4]) or owner.meta(ctx, path, row.classification)
        local spec = { id = meta.controlId, kind = kind, key = row[2], labelKey = row[4][1],
            scope = "group", applyDomain = row.domain or "visual", meta = meta, get = get, set = set,
            commitOnBlur = row.commitOnBlur }
        if kind == "slider" then
            spec.range, spec.defaultSource = { row[4][2], row[4][3], row[4][4] }, function() return fallback end
        end
        Schema.Bind(ctx, widget, spec)
        if afterBind then afterBind() end
        local command = widget._msuf2CommandAction
        spec.get, spec.set = command and command.get, command and command.set
    end }
end

function Schema.GroupRecordOptions(owner)
    return GroupBindingOptions(owner, RecordAccessors)
end

-- Selected-field rows use the existing scope readers and writes. The selected
-- provider and callable default are resolved anew for every read and input.
local function SelectedAccessors(owner, row, kind)
    local selected, scope, default = owner.selected, owner.scope, owner.default
    local field, valueDefault, domain = row[2], row[3], row.domain or "visual"
    local low, high = row[4][2], row[4][3]
    local reader = kind == "toggle" and owner.bool or owner.number
    local fallback
    if kind == "slider" then fallback = default(selected(), valueDefault) end
    local function Get()
        local spec = selected()
        if kind == "dropdown" then
            local key = spec and spec[field]
            return key and owner.value(scope(), key, default(spec, valueDefault)) or default(spec, valueDefault)
        end
        local value = reader(scope(), spec[field], default(spec, valueDefault))
        if row.clamp then
            if value < low then value = low elseif value > high then value = high end
        end
        return value
    end
    local function Set(value)
        local spec = selected()
        if kind == "dropdown" then
            local key = spec and spec[field]
            if not key then return end
            owner.write(scope(), key, value or default(spec, valueDefault), domain)
        else
            if kind == "toggle" then value = value and true or false
            else value = math.floor((tonumber(value) or default(spec, valueDefault)) + 0.5) end
            if row.clamp then
                if value < low then value = low elseif value > high then value = high end
            end
            owner.write(scope(), spec[field], value, domain)
        end
        if row.afterSet then row.afterSet() end
    end
    return row.get or Get, Set, fallback
end
function Schema.GroupSelectedOptions(owner)
    return GroupBindingOptions(owner, SelectedAccessors)
end

-- Typed policies supply business operations; central Bind retains input/history/combat ownership.
function Schema.GroupCommands(commands, meta, stepMeta)
    return GroupBindingOptions({ commands = commands, path = "", meta = meta, stepMeta = stepMeta }, CommandAccessors)
end
local function ScopeMeta(ctx, path, step)
    local meta = M.GroupPage.ControlMeta(ctx, path, type(step) == "string" and step or nil)
    if type(step) == "number" then meta.step, meta.roundStep = step, true end
    return meta
end
local function ScopeAccessors(owner, row, kind)
    local gp, key, default = M.GroupPage, row[2], row[3]
    local function Target()
        if row.target then return row.target() end
        return key, default
    end
    local function Get()
        local field, fallback = Target()
        local value = (kind == "slider" and gp.Num or gp.Val)(gp.CurrentScope(), field, fallback)
        if row.scale then return math.floor(value * row.scale + 0.5) end
        return value
    end
    local function Set(value)
        local field = Target()
        if row.select then M.SetMenuStateValue(row.select[1], row.select[2]) end
        if row.scale then value = (tonumber(value) or row.fallback) / row.scale
        else
            local fallback = row.writeDefault
            if fallback == nil then fallback = default end
            value = value or fallback
        end
        gp.Set(gp.CurrentScope(), field, value, row.domain or "visual")
        if row.afterSet then row.afterSet() end
    end
    return Get, Set, row.fallback or default
end
local SCOPE_OPTIONS = GroupBindingOptions({ path = "field.", meta = ScopeMeta, stepMeta = ScopeMeta }, ScopeAccessors)
function Schema.GroupOptions()
    return { bind = function(ctx, widget, row, kind)
        if row.binding == "scopeValue" then SCOPE_OPTIONS.bind(ctx, widget, row, kind)
        else Schema.GroupBinding(ctx, widget, row, kind) end
    end }
end
function Schema.GroupNestedBinding(ctx, widget, row)
    M.GroupPage.BindNestedSlider(ctx, widget, row.source, row[2], row[3], row.domain or "visual", row.path)
end
