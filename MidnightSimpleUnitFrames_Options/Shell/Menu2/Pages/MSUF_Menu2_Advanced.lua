local addonName, MSUF = ...
local FILE = "Shell/Menu2/Pages/MSUF_Menu2_Advanced.lua"
local M = MSUF.MSUF2

-- AdvancedPage helper module.
-- Provides shared DB helpers, binding adapters, and layout primitives for advanced option
-- pages. Keep page-specific controls in their domain files and common glue here.
local W = M.Widgets
local Schema = M.ControlSchema
local ROW_OPTIONS = Schema.UnitOptions()
local function NativeInput(widget)
    -- Draft and transport editors install their native handlers after styling.
    -- Their declaration dispatches the current owner, including later handlers.
    Schema.Custom(widget, { id = "advanced.nativeInput", kind = widget._msuf2ControlKind or "textinput",
        scope = "profiles", applyDomain = "menuState", owner = widget,
        get = function()
            local command = widget._msuf2CommandAction
            if command and command.get then return command.get() end
            if widget._msuf2ControlKind == "dropdown" then return widget:GetValue() end
            if widget._msuf2ControlKind == "toggle" then return widget:GetChecked() end
            return widget:GetText()
        end,
        customSetReason = "Changes editor selection or input state rather than a fixed profile field.", set = function(value)
            local command = widget._msuf2CommandAction
            if command and command.set then return command.set(value) end
            if widget._msuf2OnValueChanged then return widget._msuf2OnValueChanged(value) end
            if widget._msuf2ControlKind == "toggle" then
                if (widget:GetChecked() and true or false) ~= (value and true or false) then
                    return widget:Click()
                end
                return
            end
            widget:SetText(value)
        end,
    })
end
local function Row(ctx, parent, row)
    local widget = Schema.Build(ctx, parent, { row }, ROW_OPTIONS)[row[2]]
    if widget._msuf2ControlSchema then
        widget._msuf2ControlSchema.id = row.meta and row.meta.controlId or row[2]
    end
    if row.bind and row.bind ~= NativeInput and widget._msuf2RuntimeControlRecord then
        Schema.Owned(widget, row.scope or widget._msuf2RuntimeControlRecord.pageKey or (ctx and ctx.key) or "shared",
            row.domain or "menuState")
    elseif row[1] == "button" then
        Schema.Custom(widget, { id = row[2], kind = "button", labelKey = row[4][1],
            scope = row.scope or (ctx and ctx.key) or "shared", applyDomain = row.domain or "menuState",
            owner = widget, action = Schema.ButtonAction(widget) })
    end
    return widget
end

local C_Timer = M.MenuTimer or C_Timer

local ControlMeta = M.ControlMeta
local RegisterControl = M.RegisterControlMetadata

local function DB()
    return M.EnsureDB()
end
local function DBSection(key)
    return function()
        local db = DB()
        db[key] = db[key] or {}
        return db[key]
    end
end
local G, Bars, Gameplay = DBSection("general"), DBSection("bars"), DBSection("gameplay")
local function BoolValue(tbl, key, default)
    local value = tbl and tbl[key]
    if value == nil then return default and true or false end
    return value and true or false
end
local function NumValue(tbl, key, default)
    return tonumber(tbl and tbl[key]) or default or 0
end
local function SetValue(...)
    return MSUF.History.SetAdvancedValue(...)
end
local DeepCopyTable = M.DeepCopy
-- Every bound row declares through Schema.Bind: the row metadata names the stable ID and the setting key,
-- the get/set pair keeps the page's own writer and apply route.
local function BoundRow(ctx, parent, kind, key, default, args, metadata, get, set, writePolicy)
    if type(set) == "table" then writePolicy, set = set.write, nil end
    local id = type(metadata) == "table" and metadata.controlId
    assert(id, "advanced bound row needs a stable control ID: " .. tostring(key))
    return Row(ctx, parent, { kind, key, default, args, bind = function(widget)
        local spec = { id = id, kind = (kind == "slider" or kind == "dropdown") and kind or "toggle",
            labelKey = args[1], settingPath = metadata.settingKey, scope = ctx and ctx.key or "shared",
            applyDomain = "advanced", meta = metadata, get = get, set = set, write = writePolicy,
            customSetReason = set and "Runs the supplied business command or selection-dependent writer.",
            defaultSource = function() return default end }
        if kind == "slider" then spec.range, spec.roundStep = { args[2], args[3], args[4] }, true end
        Schema.Bind(ctx, widget, spec)
    end })
end
-- Getter/setter pair over one DB sub-table key, shared by the toggle and switch rows.
local function TableBool(getTable, key, default, apply)
    local write = { call = SetValue, source = getTable, args = { apply } } --[[schema setter: Advanced.TableBool]]
    return function() return BoolValue(getTable(), key, default) end, nil, write
end
local function BindTableToggle(ctx, section, label, getTable, key, default, apply, metadata)
    return BoundRow(ctx, section, "flowToggle", key, default, { label }, metadata,
        TableBool(getTable, key, default, apply))
end
local function BindTableSwitchAt(ctx, section, label, x, y, labelWidth, getTable, key, default, apply, metadata)
    return BoundRow(ctx, section, "switch", key, default, { label, x, y, labelWidth }, metadata,
        TableBool(getTable, key, default, apply))
end
local function BindTableSlider(ctx, section, label, minVal, maxVal, step, width, getTable, key, default, apply, metadata)
    local write = { call = SetValue, source = getTable, args = { apply } } --[[schema setter: Advanced.TableNumber]]
    return BoundRow(ctx, section, "slider", key, default, { label, minVal, maxVal, step, width or 300 }, metadata,
        function() return NumValue(getTable(), key, default) end, nil, write)
end
local function BindTableDropdown(ctx, section, label, values, width, getTable, key, default, apply, metadata)
    local write = { call = SetValue, source = getTable, fallback = default, args = { apply } } --[[schema setter: Advanced.TableChoice]]
    return BoundRow(ctx, section, "dropdown", key, default, { label, values, width or 220 }, metadata,
        function()
            local tbl = getTable()
            if tbl and tbl[key] ~= nil then return tbl[key] end
            return default
        end,
        nil, write)
end
local function BindValueDropdown(ctx, section, label, values, width, getValue, setValue, metadata)
    return BoundRow(ctx, section, "dropdown", metadata and metadata.controlId or label, nil,
        { label, values, width or 220 }, metadata, getValue, setValue)
end
local A3_APPLY_QUEUED = false
local A3_APPLY_DELAY = 0.04
local function ApplyAuras()
    if A3_APPLY_QUEUED then return end
    A3_APPLY_QUEUED = true
    local function Run()
        A3_APPLY_QUEUED = false
        local api = MSUF and MSUF.MSUF_Auras3
        if api and api.DB and type(api.DB.InvalidateCache) == "function" then api.DB.InvalidateCache() end
        if api and api.Colors and type(api.Colors.InvalidateCache) == "function" then api.Colors.InvalidateCache() end
        local apply = M.ApplyService or MSUF.Require("MSUF_Menu2_ApplyService", FILE)
        apply.RequestAuras("shared", "MSUF2_AURAS_APPLY")
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(A3_APPLY_DELAY, Run)
    else
        Run()
    end
end
local function MoveWidget(widget, parent, x, y)
    return W.MoveWidget(widget, parent, x, y)
end
local function LabelAt(parent, text, x, y, width, template, color)
    local widget = W.LabelAt(parent, text, x, y, width, template, color)
    local entry = parent._msuf2CollapsibleEntry
    local record = entry and entry.header._msuf2RuntimeControlRecord
    local owner = parent._msuf2ControlSchema
    return Schema.Custom(widget, { id = (record and record.controlId or owner and owner.id or "advanced.label")
        .. "." .. tostring(x) .. "." .. tostring(y), kind = "text", labelKey = text,
        scope = "shared", applyDomain = "presentation", owner = widget })
end
local function BindValueToggle(ctx, section, label, getValue, setValue, metadata)
    return BoundRow(ctx, section, "flowToggle", metadata and metadata.controlId or label, nil, { label }, metadata, getValue, setValue)
end
local function BindValueSwitchAt(ctx, section, label, x, y, labelWidth, getValue, setValue, metadata)
    return BoundRow(ctx, section, "switch", metadata and metadata.controlId or label, nil, { label, x, y, labelWidth }, metadata, getValue, setValue)
end
local function BindValueSlider(ctx, section, label, minVal, maxVal, step, width, getValue, setValue, metadata)
    return BoundRow(ctx, section, "slider", metadata and metadata.controlId or label, minVal,
        { label, minVal, maxVal, step, width or 160 }, metadata, getValue, setValue)
end
-- The *At variants take (ctx, section, label, x, y, ...) and place the row the bind function builds.
local function At(bind)
    return function(ctx, section, label, x, y, ...)
        return MoveWidget(bind(ctx, section, label, ...), section, x, y)
    end
end
local ValueToggleAt, SliderAt = At(BindValueToggle), At(BindTableSlider)
local ValueSliderAt, ValueDropdownAt = At(BindValueSlider), At(BindValueDropdown)
local function BuildTableControlSpecs(ctx, parent, getTable, defaultApply, specs, customKinds)
    return M.BuildControlSpecs(specs, { ["*"] = function(s)
        local kind = s[2]
        if kind == "toggle" then return BindTableToggle(ctx, parent, s[3], getTable, s[4], s[5], s[6] or defaultApply, s.meta), s[1] end
        if kind == "slider" then
            return BindTableSlider(ctx, parent, s[3], s[4], s[5], s[6], s[7], getTable, s[8], s[9], s[10] or defaultApply, s.meta), s[1]
        end
        if kind == "dropdown" then return BindTableDropdown(ctx, parent, s[3], s[4], s[5], getTable, s[6], s[7], s[8] or defaultApply, s.meta), s[1] end
        local custom = customKinds and customKinds[kind]
        if custom then return custom(ctx, parent, getTable, defaultApply, s), s[1] end
    end })
end
local SetControlEnabled = W.SetControlEnabled
function M.ApplyAuraQuickPreset()
    -- These presets were defined against the Auras2 table layout. Silently
    -- writing those aliases after Auras3 migration produces a success message
    -- without changing the live lanes, so keep the entry point but reject it
    -- until native Auras3 preset definitions exist.
    return false, "Aura quick presets are disabled because the legacy preset schema is not compatible with Auras3."
end
local AdvancedPage = M.AdvancedPage or {}
M.AdvancedPage = AdvancedPage
M.Assign(AdvancedPage, {
    DB = DB, G = G, Bars = Bars, Gameplay = Gameplay, Row = Row, NativeInput = NativeInput,
    ControlMeta = ControlMeta, RegisterControl = RegisterControl,
    BoolValue = BoolValue, NumValue = NumValue, SetValue = SetValue, DeepCopyTable = DeepCopyTable,
    BindTableToggle = BindTableToggle, BindTableSwitchAt = BindTableSwitchAt, BindTableSlider = BindTableSlider, BindTableDropdown = BindTableDropdown,
    BindValueDropdown = BindValueDropdown, ApplyAuras = ApplyAuras, MoveWidget = MoveWidget, LabelAt = LabelAt,
    BindValueToggle = BindValueToggle, BindValueSwitchAt = BindValueSwitchAt, BindValueSlider = BindValueSlider,
    SwitchAt = BindTableSwitchAt, ValueToggleAt = ValueToggleAt, ValueSwitchAt = BindValueSwitchAt,
    SliderAt = SliderAt, ValueSliderAt = ValueSliderAt, ValueDropdownAt = ValueDropdownAt,
    BuildTableControlSpecs = BuildTableControlSpecs,
    SetControlEnabled = SetControlEnabled,
})
