local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- AdvancedPage helper module.
-- Provides shared DB helpers, binding adapters, and layout primitives for advanced option
-- pages. Keep page-specific controls in their domain files and common glue here.
local W = M.Widgets
local WL = M.WordList
local C_Timer = M.MenuTimer or _G.C_Timer
local function NormalizeControlPath(value)
    local path = tostring(value or "")
    path = path:gsub("([%l%d])([%u])", "%1_%2"):lower()
    path = path:gsub("[^%w]+", "."):gsub("^%.*", ""):gsub("%.*$", ""):gsub("%.+", ".")
    return path
end
local function ControlMeta(pageKey, domain, semanticPath, classification, exact)
    local identity = table.concat({
        NormalizeControlPath(pageKey),
        NormalizeControlPath(domain),
        NormalizeControlPath(semanticPath),
    }, ".")
    local meta = {
        controlId = "menu2." .. identity,
        identityKey = identity,
        controlPath = identity:gsub("%.", "/"),
        classification = classification or "setting",
    }
    if type(exact) == "table" then
        for key, value in pairs(exact) do meta[key] = value end
    end
    return meta
end
local function RegisterControl(widget, meta, label, kind, values)
    if not (widget and type(meta) == "table" and type(M.RegisterSearchWidget) == "function") then return widget end
    local payload = {}
    for key, value in pairs(meta) do payload[key] = value end
    payload.label = label or payload.label
    payload.kind = kind or payload.kind
    payload.values = values or payload.values
    M.RegisterSearchWidget(widget, payload)
    return widget
end
local function CallGlobal(name, ...)
    local apply = M.ApplyService
    if apply and type(apply.CallGlobal) == "function" then return apply.CallGlobal(name, ...) end
    local fn = _G[name]
    if type(fn) == "function" then fn(...); return true end
    return false
end
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
local function SetValue(tbl, key, value, apply)
    if not tbl or tbl[key] == value then return end
    local function Write()
        if tbl[key] == value then return false end
        tbl[key] = value
        if type(apply) == "function" then apply() end
        return true
    end
    return M.RunWithHistory(tostring(key), "advanced:" .. tostring(key), Write)
end
local function DeepCopyTable(src)
    if type(src) ~= "table" then return src end
    if type(CopyTable) == "function" then return CopyTable(src) end
    return M.DeepCopy(src)
end
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
local function BindTableToggle(ctx, section, label, getTable, key, default, apply, metadata)
    return BindToggleControl(ctx, W.Toggle(section, label),
        function() return BoolValue(getTable(), key, default) end,
        function(v) SetValue(getTable(), key, v, apply) end,
        metadata)
end
local function BindTableSwitchAt(ctx, section, label, x, y, labelWidth, getTable, key, default, apply, metadata)
    return BindToggleControl(ctx, W.SwitchAt(section, label, x, y, labelWidth),
        function() return BoolValue(getTable(), key, default) end,
        function(v) SetValue(getTable(), key, v, apply) end,
        metadata)
end
local function BindTableSlider(ctx, section, label, minVal, maxVal, step, width, getTable, key, default, apply, metadata)
    return BindSliderControl(ctx, W.Slider(section, label, minVal, maxVal, step, width or 300),
        function() return NumValue(getTable(), key, default) end,
        function(v) SetValue(getTable(), key, v, apply) end,
        default, step, metadata)
end
local function BindTableDropdown(ctx, section, label, values, width, getTable, key, default, apply, metadata)
    return BindDropdownControl(ctx, W.Dropdown(section, label, values, width or 220),
        function()
            local tbl = getTable()
            if tbl and tbl[key] ~= nil then return tbl[key] end
            return default
        end,
        function(v) SetValue(getTable(), key, v or default, apply) end,
        metadata)
end
local function BindValueDropdown(ctx, section, label, values, width, getValue, setValue, metadata)
    return BindDropdownControl(ctx, W.Dropdown(section, label, values, width or 220), getValue, setValue, metadata)
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
    return W.LabelAt(parent, text, x, y, width, template, color)
end
local function DividerAt(parent, y, leftPad, rightPad)
    return W.DividerAt(parent, y, leftPad, rightPad)
end
local function BindValueToggle(ctx, section, label, getValue, setValue, metadata)
    return BindToggleControl(ctx, W.Toggle(section, label), getValue, setValue, metadata)
end
local function BindValueSwitchAt(ctx, section, label, x, y, labelWidth, getValue, setValue, metadata)
    return BindToggleControl(ctx, W.SwitchAt(section, label, x, y, labelWidth), getValue, setValue, metadata)
end
local function BindValueSlider(ctx, section, label, minVal, maxVal, step, width, getValue, setValue, metadata)
    return BindSliderControl(ctx, W.Slider(section, label, minVal, maxVal, step, width or 160), getValue, setValue, minVal, step, metadata)
end
local function ToggleAt(ctx, section, label, x, y, getTable, key, default, apply, metadata)
    return MoveWidget(BindTableToggle(ctx, section, label, getTable, key, default, apply, metadata), section, x, y)
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
local function DropdownAt(ctx, section, label, x, y, values, width, getTable, key, default, apply, metadata)
    return MoveWidget(BindTableDropdown(ctx, section, label, values, width, getTable, key, default, apply, metadata), section, x, y)
end
local function ValueDropdownAt(ctx, section, label, x, y, values, width, getValue, setValue, metadata)
    return MoveWidget(BindValueDropdown(ctx, section, label, values, width, getValue, setValue, metadata), section, x, y)
end
local function AddTableControlSpecs(ctx, list, section, getTable, specs, defaultApply)
    M.BuildControlSpecs(specs, {
        toggle = function(s) return ToggleAt(ctx, section, s[2], s[3], s[4], getTable, s[5], s[6], s[7] or defaultApply, s.meta) end,
        switch = function(s) return SwitchAt(ctx, section, s[2], s[3], s[4], s[5], getTable, s[6], s[7], s[8] or defaultApply, s.meta) end,
        slider = function(s) return SliderAt(ctx, section, s[2], s[3], s[4], s[5], s[6], s[7], s[8], getTable, s[9], s[10], s[11] or defaultApply, s.meta) end,
        dropdown = function(s) return DropdownAt(ctx, section, s[2], s[3], s[4], s[5], s[6], getTable, s[7], s[8], s[9] or defaultApply, s.meta) end,
    }, nil, list)
    return list
end
local function BuildTableControlSpecs(ctx, parent, getTable, defaultApply, specs, customKinds)
    return M.BuildControlSpecs(specs, { ["*"] = function(s)
        local kind = s[2]
        if kind == "toggle" then return BindTableToggle(ctx, parent, s[3], getTable, s[4], s[5], s[6] or defaultApply, s.meta), s[1] end
        if kind == "slider" then return BindTableSlider(ctx, parent, s[3], s[4], s[5], s[6], s[7], getTable, s[8], s[9], s[10] or defaultApply, s.meta), s[1] end
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
    CallGlobal = CallGlobal, DB = DB, G = G, Bars = Bars, Gameplay = Gameplay,
    ControlMeta = ControlMeta, RegisterControl = RegisterControl,
    BoolValue = BoolValue, NumValue = NumValue, SetValue = SetValue, DeepCopyTable = DeepCopyTable,
    BindTableToggle = BindTableToggle, BindTableSwitchAt = BindTableSwitchAt, BindTableSlider = BindTableSlider, BindTableDropdown = BindTableDropdown,
    BindValueDropdown = BindValueDropdown, ApplyAuras = ApplyAuras, MoveWidget = MoveWidget, LabelAt = LabelAt, DividerAt = DividerAt,
    BindValueToggle = BindValueToggle, BindValueSwitchAt = BindValueSwitchAt, BindValueSlider = BindValueSlider,
    ToggleAt = ToggleAt, SwitchAt = SwitchAt, ValueToggleAt = ValueToggleAt, ValueSwitchAt = ValueSwitchAt,
    SliderAt = SliderAt, ValueSliderAt = ValueSliderAt, DropdownAt = DropdownAt, ValueDropdownAt = ValueDropdownAt,
    AddTableControlSpecs = AddTableControlSpecs, BuildTableControlSpecs = BuildTableControlSpecs,
    SetControlEnabled = SetControlEnabled,
})
