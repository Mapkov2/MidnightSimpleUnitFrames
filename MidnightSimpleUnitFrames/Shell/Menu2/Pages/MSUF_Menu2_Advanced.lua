local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- AdvancedPage helper module.
-- Provides shared DB helpers, binding adapters, and layout primitives for advanced option
-- pages. Keep page-specific controls in their domain files and common glue here.
local W = M.Widgets
local WL = M.WordList
local AURA_LAYOUT_OVERRIDE_KEYS = WL "iconSize spacing cooldownTextSize stackTextSize reminderGrowth"
local AURA_CAPS_OVERRIDE_KEYS = WL "maxBuffs maxDebuffs maxIcons perRow layoutMode growth buffGrowth debuffGrowth rowWrap buffRowWrap debuffRowWrap buffDebuffAnchor splitSpacing stackCountAnchor sortOrder"
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
local function IsEmptyAuraFilterTable(filters)
    if type(filters) ~= "table" then return true end
    for key, value in pairs(filters) do
        if key == "buffs" or key == "debuffs" then
            if type(value) == "table" then
                for _ in pairs(value) do return false end
            elseif value ~= nil then
                return false
            end
        elseif value ~= nil then
            return false
        end
    end
    return true
end
local BindToggleControl, BindDropdownControl = M.BindBoolWidget, M.BindDropdownWidget
local function BindSliderControl(ctx, slider, getValue, setValue, fallback, step)
    return M.BindNumberWidget(ctx, slider, getValue, setValue, fallback, { step = step, roundStep = true })
end
local function BindTableToggle(ctx, section, label, getTable, key, default, apply)
    return BindToggleControl(ctx, W.Toggle(section, label),
        function() return BoolValue(getTable(), key, default) end,
        function(v) SetValue(getTable(), key, v, apply) end)
end
local function BindTableSwitchAt(ctx, section, label, x, y, labelWidth, getTable, key, default, apply)
    return BindToggleControl(ctx, W.SwitchAt(section, label, x, y, labelWidth),
        function() return BoolValue(getTable(), key, default) end,
        function(v) SetValue(getTable(), key, v, apply) end)
end
local function BindTableSlider(ctx, section, label, minVal, maxVal, step, width, getTable, key, default, apply)
    return BindSliderControl(ctx, W.Slider(section, label, minVal, maxVal, step, width or 300),
        function() return NumValue(getTable(), key, default) end,
        function(v) SetValue(getTable(), key, v, apply) end,
        default, step)
end
local function BindTableDropdown(ctx, section, label, values, width, getTable, key, default, apply)
    return BindDropdownControl(ctx, W.Dropdown(section, label, values, width or 220),
        function()
            local tbl = getTable()
            if tbl and tbl[key] ~= nil then return tbl[key] end
            return default
        end,
        function(v) SetValue(getTable(), key, v or default, apply) end)
end
local function BindValueDropdown(ctx, section, label, values, width, getValue, setValue)
    return BindDropdownControl(ctx, W.Dropdown(section, label, values, width or 220), getValue, setValue)
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
        if api and type(api.RequestApply) == "function" then
            api.RequestApply()
        end
    end
    if type(_G.MSUF_ScheduleDelayOnce) == "function" then
        _G.MSUF_ScheduleDelayOnce("MSUF2_AURAS_APPLY", A3_APPLY_DELAY, Run)
    else
        C_Timer.After(A3_APPLY_DELAY, Run)
    end
end
local function AurasDB()
    local db = DB()
    db.auras3 = db.auras3 or {}
    local a2 = db.auras3
    a2.shared = a2.shared or {}
    a2.perUnit = a2.perUnit or {}
    return a2, a2.shared
end
local function AurasUnit(key)
    local a2 = AurasDB()
    a2.perUnit[key] = a2.perUnit[key] or {}
    local u = a2.perUnit[key]
    u.layout = u.layout or {}
    u.layoutShared = u.layoutShared or {}
    u.filters = u.filters or {}
    u.filters.buffs = u.filters.buffs or {}
    u.filters.debuffs = u.filters.debuffs or {}
    return u
end
local function AuraScope()
    return M.auraScope or "shared"
end
local function AuraShared()
    local _, shared = AurasDB()
    return shared
end
local function AuraLayout()
    local scope = AuraScope()
    if scope == "shared" then return AuraShared() end
    local u = AurasUnit(scope)
    if u.overrideLayout == true then return u.layout end
    return AuraShared()
end
local function AuraCaps()
    local scope = AuraScope()
    if scope == "shared" then return AuraShared() end
    local u = AurasUnit(scope)
    if u.overrideSharedLayout == true then return u.layoutShared end
    return AuraShared()
end
local function AuraFilters()
    local scope = AuraScope()
    local shared = AuraShared()
    shared.filters = shared.filters or {}
    shared.filters.buffs = shared.filters.buffs or {}
    shared.filters.debuffs = shared.filters.debuffs or {}
    if scope == "shared" then return shared.filters end
    local u = AurasUnit(scope)
    if u.overrideFilters == true then return u.filters end
    return shared.filters
end
local function AuraBuffFilters()
    local f = AuraFilters()
    f.buffs = f.buffs or {}
    return f.buffs
end
local function AuraDebuffFilters()
    local f = AuraFilters()
    f.debuffs = f.debuffs or {}
    return f.debuffs
end
local function ForceAuraLayoutOverride()
    local scope = AuraScope()
    if scope == "shared" then return end
    local shared = AuraShared()
    local u = AurasUnit(scope)
    u.overrideLayout = true
    if type(u.layout) ~= "table" then u.layout = {} end
    local layout = u.layout
    for _, key in ipairs(AURA_LAYOUT_OVERRIDE_KEYS) do
        if layout[key] == nil then layout[key] = shared[key] end
    end
end
local function ForceAuraCapsOverride()
    local scope = AuraScope()
    if scope == "shared" then return end
    local shared = AuraShared()
    local u = AurasUnit(scope)
    u.overrideSharedLayout = true
    if type(u.layoutShared) ~= "table" then u.layoutShared = {} end
    local layout = u.layoutShared
    for _, key in ipairs(AURA_CAPS_OVERRIDE_KEYS) do
        if layout[key] == nil then layout[key] = shared[key] end
    end
end
local function ForceAuraFilterOverride()
    local scope = AuraScope()
    if scope == "shared" then return end
    local shared = AuraShared()
    local u = AurasUnit(scope)
    local hadOverride = (u.overrideFilters == true)
    u.overrideFilters = true
    if type(u.filters) ~= "table" or u.filters == shared.filters or (not hadOverride and IsEmptyAuraFilterTable(u.filters)) then u.filters = DeepCopyTable(shared.filters or {}) end
    u.filters.buffs = u.filters.buffs or {}
    u.filters.debuffs = u.filters.debuffs or {}
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
local function BindValueToggle(ctx, section, label, getValue, setValue)
    return BindToggleControl(ctx, W.Toggle(section, label), getValue, setValue)
end
local function BindValueSwitchAt(ctx, section, label, x, y, labelWidth, getValue, setValue)
    return BindToggleControl(ctx, W.SwitchAt(section, label, x, y, labelWidth), getValue, setValue)
end
local function BindValueSlider(ctx, section, label, minVal, maxVal, step, width, getValue, setValue)
    return BindSliderControl(ctx, W.Slider(section, label, minVal, maxVal, step, width or 160), getValue, setValue, minVal, step)
end
local function ToggleAt(ctx, section, label, x, y, getTable, key, default, apply)
    return MoveWidget(BindTableToggle(ctx, section, label, getTable, key, default, apply), section, x, y)
end
local function SwitchAt(ctx, section, label, x, y, labelWidth, getTable, key, default, apply)
    return BindTableSwitchAt(ctx, section, label, x, y, labelWidth, getTable, key, default, apply)
end
local function ValueToggleAt(ctx, section, label, x, y, getValue, setValue)
    return MoveWidget(BindValueToggle(ctx, section, label, getValue, setValue), section, x, y)
end
local function ValueSwitchAt(ctx, section, label, x, y, labelWidth, getValue, setValue)
    return BindValueSwitchAt(ctx, section, label, x, y, labelWidth, getValue, setValue)
end
local function SliderAt(ctx, section, label, x, y, minVal, maxVal, step, width, getTable, key, default, apply)
    return MoveWidget(BindTableSlider(ctx, section, label, minVal, maxVal, step, width, getTable, key, default, apply), section, x, y)
end
local function ValueSliderAt(ctx, section, label, x, y, minVal, maxVal, step, width, getValue, setValue)
    return MoveWidget(BindValueSlider(ctx, section, label, minVal, maxVal, step, width, getValue, setValue), section, x, y)
end
local function DropdownAt(ctx, section, label, x, y, values, width, getTable, key, default, apply)
    return MoveWidget(BindTableDropdown(ctx, section, label, values, width, getTable, key, default, apply), section, x, y)
end
local function ValueDropdownAt(ctx, section, label, x, y, values, width, getValue, setValue)
    return MoveWidget(BindValueDropdown(ctx, section, label, values, width, getValue, setValue), section, x, y)
end
local function AddTableControlSpecs(ctx, list, section, getTable, specs, defaultApply)
    M.BuildControlSpecs(specs, {
        toggle = function(s) return ToggleAt(ctx, section, s[2], s[3], s[4], getTable, s[5], s[6], s[7] or defaultApply) end,
        switch = function(s) return SwitchAt(ctx, section, s[2], s[3], s[4], s[5], getTable, s[6], s[7], s[8] or defaultApply) end,
        slider = function(s) return SliderAt(ctx, section, s[2], s[3], s[4], s[5], s[6], s[7], s[8], getTable, s[9], s[10], s[11] or defaultApply) end,
        dropdown = function(s) return DropdownAt(ctx, section, s[2], s[3], s[4], s[5], s[6], getTable, s[7], s[8], s[9] or defaultApply) end,
    }, nil, list)
    return list
end
local function BuildTableControlSpecs(ctx, parent, getTable, defaultApply, specs, customKinds)
    return M.BuildControlSpecs(specs, { ["*"] = function(s)
        local kind = s[2]
        if kind == "toggle" then return BindTableToggle(ctx, parent, s[3], getTable, s[4], s[5], s[6] or defaultApply), s[1] end
        if kind == "slider" then return BindTableSlider(ctx, parent, s[3], s[4], s[5], s[6], s[7], getTable, s[8], s[9], s[10] or defaultApply), s[1] end
        if kind == "dropdown" then return BindTableDropdown(ctx, parent, s[3], s[4], s[5], getTable, s[6], s[7], s[8] or defaultApply), s[1] end
        local custom = customKinds and customKinds[kind]
        if custom then return custom(ctx, parent, getTable, defaultApply, s), s[1] end
    end })
end
local SetControlEnabled = W.SetControlEnabled
local function RefreshAurasPage(ctx)
    if M.RequestRefresh then M.RequestRefresh(ctx, "advanced-auras-ui") elseif M.Refresh then M.Refresh(ctx) end
end
local AURA_QUICK_PRESETS = {
    clean = {
        label = "Clean",
        maxBuffs = 6, maxDebuffs = 12, perRow = 10, splitSpacing = 4, iconSize = 24, spacing = 2, sortOrder = 0,
        layoutMode = "SEPARATE", buffGrowth = "RIGHT", debuffGrowth = "RIGHT", buffRowWrap = "DOWN", debuffRowWrap = "DOWN",
        hidePermanent = true, buffIncludeBoss = false, debuffIncludeBoss = true, includeStealable = true,
        includeDispellable = true, onlyMineBuffs = false, onlyMineDebuffs = false,
        highlightOwnBuffs = true, highlightOwnDebuffs = true, showCooldownSwipe = true, showCooldownText = true, showStackCount = true, useBlizzardTimerText = true,
    },
    focused = {
        label = "Focused",
        maxBuffs = 10, maxDebuffs = 16, perRow = 10, splitSpacing = 6, iconSize = 26, spacing = 2, sortOrder = 3,
        layoutMode = "SEPARATE", buffGrowth = "RIGHT", debuffGrowth = "RIGHT", buffRowWrap = "DOWN", debuffRowWrap = "DOWN",
        hidePermanent = false, buffIncludeBoss = true, debuffIncludeBoss = true, includeStealable = true,
        includeDispellable = true, onlyMineBuffs = true, onlyMineDebuffs = true,
        highlightOwnBuffs = true, highlightOwnDebuffs = true, showCooldownSwipe = true, showCooldownText = true, showStackCount = true, useBlizzardTimerText = true,
    },
    performance = {
        label = "Fast",
        maxBuffs = 4, maxDebuffs = 8, perRow = 8, splitSpacing = 2, iconSize = 22, spacing = 1, sortOrder = 0,
        layoutMode = "SEPARATE", buffGrowth = "RIGHT", debuffGrowth = "RIGHT", buffRowWrap = "DOWN", debuffRowWrap = "DOWN",
        hidePermanent = true, buffIncludeBoss = false, debuffIncludeBoss = true, includeStealable = false,
        includeDispellable = false, onlyMineBuffs = false, onlyMineDebuffs = false,
        highlightOwnBuffs = false, highlightOwnDebuffs = false, showCooldownSwipe = false, showCooldownText = true, showStackCount = false, useBlizzardTimerText = true,
    },
}
function M.ApplyAuraQuickPreset(scope, name, opts)
    local p = AURA_QUICK_PRESETS[name]
    if not p then return false end
    scope = scope or AuraScope()
    local previousScope = M.auraScope
    M.auraScope = scope
    local sharedScope = AuraScope() == "shared"
    if not sharedScope then
        ForceAuraFilterOverride()
        ForceAuraCapsOverride()
        ForceAuraLayoutOverride()
    end
    local caps = AuraCaps()
    local layout = AuraLayout()
    local filters = AuraFilters()
    local buffs = AuraBuffFilters()
    local debuffs = AuraDebuffFilters()
    caps.maxBuffs, caps.maxDebuffs, caps.perRow = p.maxBuffs, p.maxDebuffs, p.perRow
    caps.splitSpacing, caps.sortOrder = p.splitSpacing, p.sortOrder
    caps.layoutMode = p.layoutMode or caps.layoutMode or "SEPARATE"
    caps.buffGrowth, caps.debuffGrowth = p.buffGrowth, p.debuffGrowth
    caps.buffRowWrap, caps.debuffRowWrap = p.buffRowWrap, p.debuffRowWrap
    layout.iconSize, layout.spacing = p.iconSize, p.spacing
    filters.hidePermanent = p.hidePermanent
    buffs.includeBoss, debuffs.includeBoss = p.buffIncludeBoss, p.debuffIncludeBoss
    buffs.includeStealable, debuffs.includeDispellable = p.includeStealable, p.includeDispellable
    buffs.onlyMine, debuffs.onlyMine = p.onlyMineBuffs, p.onlyMineDebuffs
    if sharedScope then
        local shared = AuraShared()
        shared.highlightOwnBuffs = p.highlightOwnBuffs
        shared.highlightOwnDebuffs = p.highlightOwnDebuffs
        shared.showCooldownSwipe = p.showCooldownSwipe
        shared.showCooldownText = p.showCooldownText
        shared.showStackCount = p.showStackCount
        shared.useBlizzardTimerText = p.useBlizzardTimerText
    end
    M.auraScope = previousScope
    ApplyAuras()
    if opts and opts.refresh == true then RefreshAurasPage(opts.ctx) end
    return true, p.label
end
local AdvancedPage = M.AdvancedPage or {}
M.AdvancedPage = AdvancedPage
M.Assign(AdvancedPage, {
    CallGlobal = CallGlobal, DB = DB, G = G, Bars = Bars, Gameplay = Gameplay,
    BoolValue = BoolValue, NumValue = NumValue, SetValue = SetValue, DeepCopyTable = DeepCopyTable,
    BindTableToggle = BindTableToggle, BindTableSwitchAt = BindTableSwitchAt, BindTableSlider = BindTableSlider, BindTableDropdown = BindTableDropdown,
    BindValueDropdown = BindValueDropdown, ApplyAuras = ApplyAuras, MoveWidget = MoveWidget, LabelAt = LabelAt, DividerAt = DividerAt,
    BindValueToggle = BindValueToggle, BindValueSwitchAt = BindValueSwitchAt, BindValueSlider = BindValueSlider,
    ToggleAt = ToggleAt, SwitchAt = SwitchAt, ValueToggleAt = ValueToggleAt, ValueSwitchAt = ValueSwitchAt,
    SliderAt = SliderAt, ValueSliderAt = ValueSliderAt, DropdownAt = DropdownAt, ValueDropdownAt = ValueDropdownAt,
    AddTableControlSpecs = AddTableControlSpecs, BuildTableControlSpecs = BuildTableControlSpecs,
    SetControlEnabled = SetControlEnabled,
})
