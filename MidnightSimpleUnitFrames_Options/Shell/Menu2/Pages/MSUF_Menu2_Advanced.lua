local addonName, MSUF = ...
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
        set = function(value)
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

local C_Timer = M.MenuTimer or _G.C_Timer

local ControlMeta = M.ControlMeta
local RegisterControl = M.RegisterControlMetadata

local function DB()
    return M.EnsureDB()
end
local function G()
    local db = DB()
    db.general = db.general or {}
    return db.general
end
local function Bars()
    local db = DB()
    db.bars = db.bars or {}
    return db.bars
end
local function Gameplay()
    local db = DB()
    db.gameplay = db.gameplay or {}
    return db.gameplay
end
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
local BindToggleControl, BindDropdownControl = M.BindBoolWidget, M.BindDropdownWidget
local function BindSliderControl(ctx, slider, getValue, setValue, fallback, step, metadata)
    local opts = {}
    if type(metadata) == "table" then
        for key, value in pairs(metadata) do opts[key] = value end
    end
    opts.step = step
    opts.roundStep = true
    return M.BindNumberWidget(ctx, slider, getValue, setValue, fallback, opts)
end
local function BoundRow(ctx, parent, kind, key, default, args, get, set, metadata)
    return Row(ctx, parent, { kind, key, default, args, bind = function(widget)
        if kind == "slider" then
            BindSliderControl(ctx, widget, get, set, default, args[4], metadata)
        elseif kind == "dropdown" then BindDropdownControl(ctx, widget, get, set, metadata)
        else BindToggleControl(ctx, widget, get, set, metadata) end
    end })
end
local function BindTableToggle(ctx, section, label, getTable, key, default, apply, metadata)
    return BoundRow(ctx, section, "flowToggle", key, default, { label },
        function() return BoolValue(getTable(), key, default) end,
        function(v) SetValue(getTable(), key, v, apply) end, metadata)
end
local function BindTableSwitchAt(ctx, section, label, x, y, labelWidth, getTable, key, default, apply, metadata)
    return BoundRow(ctx, section, "switch", key, default, { label, x, y, labelWidth },
        function() return BoolValue(getTable(), key, default) end,
        function(v) SetValue(getTable(), key, v, apply) end, metadata)
end
local function BindTableSlider(ctx, section, label, minVal, maxVal, step, width, getTable, key, default, apply, metadata)
    return BoundRow(ctx, section, "slider", key, default, { label, minVal, maxVal, step, width or 300 },
        function() return NumValue(getTable(), key, default) end,
        function(v) SetValue(getTable(), key, v, apply) end, metadata)
end
local function BindTableDropdown(ctx, section, label, values, width, getTable, key, default, apply, metadata)
    return BoundRow(ctx, section, "dropdown", key, default, { label, values, width or 220 },
        function()
            local tbl = getTable()
            if tbl and tbl[key] ~= nil then return tbl[key] end
            return default
        end,
        function(v) SetValue(getTable(), key, v or default, apply) end, metadata)
end
local function BindValueDropdown(ctx, section, label, values, width, getValue, setValue, metadata)
    return BoundRow(ctx, section, "dropdown", metadata and metadata.controlId or label, nil,
        { label, values, width or 220 }, getValue, setValue, metadata)
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
        local apply = M.ApplyService or _G.MSUF_Menu2_ApplyService
        if apply and type(apply.RequestAuras) == "function" then
            apply.RequestAuras("shared", "MSUF2_AURAS_APPLY")
        elseif api and type(api.RequestApply) == "function" then
            api.RequestApply()
        end
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
    return BoundRow(ctx, section, "flowToggle", metadata and metadata.controlId or label, nil, { label }, getValue, setValue, metadata)
end
local function BindValueSwitchAt(ctx, section, label, x, y, labelWidth, getValue, setValue, metadata)
    return BoundRow(ctx, section, "switch", metadata and metadata.controlId or label, nil, { label, x, y, labelWidth }, getValue, setValue, metadata)
end
local function BindValueSlider(ctx, section, label, minVal, maxVal, step, width, getValue, setValue, metadata)
    return BoundRow(ctx, section, "slider", metadata and metadata.controlId or label, minVal,
        { label, minVal, maxVal, step, width or 160 }, getValue, setValue, metadata)
end
local function SwitchAt(ctx, section, label, x, y, labelWidth, getTable, key, default, apply, metadata)
    return BindTableSwitchAt(ctx, section, label, x, y, labelWidth, getTable, key, default, apply, metadata)
end
local function ValueToggleAt(ctx, section, label, x, y, getValue, setValue, metadata)
    return MoveWidget(BindValueToggle(ctx, section, label, getValue, setValue, metadata), section, x, y)
end
local function ValueSwitchAt(ctx, section, label, x, y, labelWidth, getValue, setValue, metadata)
    return BindValueSwitchAt(ctx, section, label, x, y, labelWidth, getValue, setValue, metadata)
end
local function SliderAt(ctx, section, label, x, y, minVal, maxVal, step, width, getTable, key, default, apply, metadata)
    return MoveWidget(BindTableSlider(ctx, section, label, minVal, maxVal, step, width, getTable, key, default, apply, metadata), section, x, y)
end
local function ValueSliderAt(ctx, section, label, x, y, minVal, maxVal, step, width, getValue, setValue, metadata)
    return MoveWidget(BindValueSlider(ctx, section, label, minVal, maxVal, step, width, getValue, setValue, metadata), section, x, y)
end
local function ValueDropdownAt(ctx, section, label, x, y, values, width, getValue, setValue, metadata)
    return MoveWidget(BindValueDropdown(ctx, section, label, values, width, getValue, setValue, metadata), section, x, y)
end
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
    SwitchAt = SwitchAt, ValueToggleAt = ValueToggleAt, ValueSwitchAt = ValueSwitchAt,
    SliderAt = SliderAt, ValueSliderAt = ValueSliderAt, ValueDropdownAt = ValueDropdownAt,
    BuildTableControlSpecs = BuildTableControlSpecs,
    SetControlEnabled = SetControlEnabled,
})
