local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
addonName = (type(MSUF.AddonName) == "string" and MSUF.AddonName ~= "" and MSUF.AddonName)
    or "MidnightSimpleUnitFrames"
local FILE = "Shell/Menu2/Pages/MSUF_Menu2_GlobalBars.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
-- Core functions this page calls by their global names: required here at
-- load; the sections that call them resolve them once when they build, never per update.
M.RequireGlobals(FILE, {
    "MSUF_RefreshTempMaxHealth",
    "MSUF_UFPreview_RequestRefresh",
    "MSUF_ApplyRoundedUnitframes",
})

-- Menu2 global Bars page.
-- Binds shared/scoped texture, gradient, outline, absorb, and highlight controls. Page code
-- updates DB through GlobalPage helpers and lets runtime refreshers repaint live frames.
local W = M.Widgets
local T = M.Theme
local GP = M.GlobalPage or {}
local VT = M.ValueTextList
local C_Timer = M.MenuTimer or C_Timer
local floor = math.floor
local max = math.max
local min = math.min
local unpack = unpack or table.unpack
local UNITFRAME_DISPEL_AURA_WARNING = "Dispel Border, Overlay, and Symbol need each UnitFrame's Aura sensor. Enable Buffs or Debuffs on the affected " ..
    "UnitFrame, or turn on its Dispel feature to enable the sensor automatically. Both icon caps may stay at 0."
local UNITFRAME_DISPEL_AURA_WARNING_COLOR = { 0.90, 0.84, 0.76, 1 }
local UNITFRAME_DISPEL_AURA_UNITS = { "player", "target", "focus", "boss", "arena" }
local ROUNDED_STRENGTH_APPLY_DELAY = 0.12
local ROUNDED_SECTION_HEIGHT = 310
local SLANTED_PRESET_UNITS = { "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena" }
local SLANTED_PRESET_GROUPS = { "gf_party", "gf_raid", "gf_mythicraid" }
local SLANTED_DIRECTION_VALUES = VT(
    "RIGHT_DOWN", "Right edge: lower corner", "RIGHT_UP", "Right edge: upper corner",
    "LEFT_DOWN", "Left edge: lower corner", "LEFT_UP", "Left edge: upper corner",
    "BOTH_DOWN", "Both edges: lower corners", "BOTH_UP", "Both edges: upper corners")
local SLANTED_SCOPED_DIRECTION_VALUES = VT("DEFAULT", "Use shared style")
for i = 1, #SLANTED_DIRECTION_VALUES do
    SLANTED_SCOPED_DIRECTION_VALUES[#SLANTED_SCOPED_DIRECTION_VALUES + 1] = SLANTED_DIRECTION_VALUES[i]
end
local ROUNDED_PREVIEW_CARD_HEIGHT = 92
local GRADIENT_DIR_KEYS, PRIORITY_LABELS = GP.GRADIENT_DIR_KEYS or {}, GP.PRIORITY_LABELS or {}
local DISPEL_TRIGGERS = VT("BY_ME", "Dispellable by me", "BY_RAID", "Dispellable by group",
    "DISPEL_TYPE", "Any dispel type")
local DISPEL_SHOW_ON = VT("FRIENDLY", "Friendly", "ENEMY", "Enemy", "BOTH", "Both")
local DISPEL_COLOR_REFERENCES = {
    "aura.dispel.magic", "aura.dispel.curse", "aura.dispel.disease",
    "aura.dispel.poison", "aura.dispel.bleed",
}
local DB, G, Bars, ReadG, ReadGBool, ReadB, NormalizeScopeKey = GP.DB, GP.G, GP.Bars, GP.ReadG, GP.ReadGBool, GP.ReadB, GP.NormalizeScopeKey
local ScopeDBKeys, ScopeHasOverride, ScopeSetOverride, CurrentBarsScope = GP.ScopeDBKeys, GP.ScopeHasOverride, GP.ScopeSetOverride, GP.CurrentBarsScope
local IsGFScope, BarScopeGet, BarScopeSet, BarScopeGetBars = GP.IsGFScope, GP.BarScopeGet, GP.BarScopeSet, GP.BarScopeGetBars
local BarScopeSetBars, GradientScopeGet, GradientScopeSet = GP.BarScopeSetBars, GP.GradientScopeGet, GP.GradientScopeSet
local GradientScopeHasExplicit, TextureValues, CurrentPowerBarScopeUnit = GP.GradientScopeHasExplicit, GP.TextureValues, GP.CurrentPowerBarScopeUnit
local SmoothPowerGet, SmoothPowerSet, ChunkedPowerGet, ChunkedPowerSet = GP.SmoothPowerGet, GP.SmoothPowerSet, GP.ChunkedPowerGet, GP.ChunkedPowerSet
local PriorityOrder, PriorityColor, RefreshBorderTestModes = GP.PriorityOrder, GP.PriorityColor, GP.RefreshBorderTestModes
local SetAbsorbTextureTest, SetControlEnabled, SetControlsEnabled = GP.SetAbsorbTextureTest, GP.SetControlEnabled, GP.SetControlsEnabled
local ApplyBars, ControlMeta, RegisterControl = GP.ApplyBars, GP.ControlMeta, GP.RegisterControl
local IsAbsorbTextureTestEnabled = GP.IsAbsorbTextureTestEnabled
local BAR_SETTING_BY_PATH = {
    ["highlight.boss_target.mode"] = "general.bossTargetOutlineMode",
    ["rounded.roundedFramesEnabled"] = "bars.roundedFramesEnabled",
    ["rounded.roundedUnitFrames"] = "bars.roundedUnitFrames",
    ["rounded.roundedGroupFrames"] = "bars.roundedGroupFrames",
    ["rounded.roundedPowerBars"] = "bars.roundedPowerBars",
    ["rounded.roundedCastbars"] = "bars.roundedCastbars",
    ["rounded.roundedClassResources"] = "bars.roundedClassResources",
    ["rounded.roundedMouseover"] = "bars.roundedMouseover",
    ["rounded.roundedCornerStrength"] = "bars.roundedCornerStrength",
    ["slanted.enabled"] = "bars.slantedBarsEnabled",
    ["slanted.units"] = "bars.slantedUnitFrames",
    ["slanted.groups"] = "bars.slantedGroupFrames",
    ["slanted.power"] = "bars.slantedPowerBars",
    ["slanted.mouseover"] = "bars.slantedMouseover",
    ["slanted.castbars"] = "bars.slantedCastbars",
    ["slanted.class_resources"] = "bars.slantedClassResources",
    ["slanted.direction"] = "bars.slantedBarDirection",
    ["power.realtime_text"] = "bars.realtimePowerText",
    ["textures.power_foreground"] = "bars.powerBarTexture",
    ["textures.power_background"] = "bars.powerBarBgTexture",
}
local BAR_ACTION_BY_PATH = {
    ["scope.overrides.reset"] = "reset_all_scoped_global_bars_overrides",
}
local BAR_DYNAMIC_SETTING_SUFFIX_BY_PATH = {
    ["scope.override.enabled"] = "override",
    ["textures.foreground"] = "barTexture",
    ["textures.background"] = "barBackgroundTexture",
    ["gloss.health.enabled"] = "healthGlossEnabled",
    ["gloss.health.strength"] = "healthGlossStrength",
    ["gloss.power.enabled"] = "powerGlossEnabled",
    ["gloss.power.strength"] = "powerGlossStrength",
    ["gradient.enableGradient"] = "enableGradient",
    ["gradient.enablePowerGradient"] = "enablePowerGradient",
    ["gradient.health.strength"] = "gradientStrength",
    ["gradient.power.strength"] = "powerGradientStrength",
    ["temp_max_health.enabled"] = "tempMaxHealthEnabled",
    ["temp_max_health.texture"] = "tempMaxHealthTexture",
    ["temp_max_health.color"] = "tempMaxHealthColorR",
    ["temp_max_health.opacity"] = "tempMaxHealthOpacity",
    ["temp_max_health.background_opacity"] = "tempMaxHealthBackgroundOpacity",
    ["absorb.display_mode"] = "absorbTextMode",
    ["absorb.absorbAnchorMode"] = "absorbAnchorMode",
    ["absorb.absorbBarOpacity"] = "absorbBarOpacity",
    ["absorb.absorbBarTexture"] = "absorbBarTexture",
    ["absorb.healAbsorbBarOpacity"] = "healAbsorbBarOpacity",
    ["absorb.healAbsorbBarTexture"] = "healAbsorbBarTexture",
    ["absorb.healPredAnchorMode"] = "healPredAnchorMode",
    ["absorb.heal_prediction.enabled"] = "healPredEnabled",
    ["absorb.heal_prediction.all_healers"] = "healPredAllHealers",
    ["absorb.healPredEnabled"] = "healPredEnabled",
    ["absorb.positive.enabled"] = "enableAbsorbBar",
    ["absorb.positive.anchor"] = "absorbAnchorMode",
    ["absorb.positive.height"] = "absorbBarHeight",
    ["absorb.positive.offset_y"] = "absorbBarOffsetY",
    ["absorb.positive.texture"] = "absorbBarTexture",
    ["absorb.positive.opacity"] = "absorbBarOpacity",
    ["absorb.positive.over_absorb"] = "overAbsorbOverlay",
    ["absorb.positive.full_health_stripe"] = "fullHealthAbsorbStripe",
    ["absorb.negative.enabled"] = "healAbsorbEnabled",
    ["absorb.negative.anchor"] = "healAbsorbAnchorMode",
    ["absorb.negative.height"] = "healAbsorbBarHeight",
    ["absorb.negative.offset_y"] = "healAbsorbBarOffsetY",
    ["absorb.negative.texture"] = "healAbsorbBarTexture",
    ["absorb.negative.opacity"] = "healAbsorbBarOpacity",
    ["absorb.heal_prediction.anchor"] = "healPredAnchorMode",
    ["absorb.heal_prediction.height"] = "healPredictionBarHeight",
    ["absorb.heal_prediction.offset_y"] = "healPredictionBarOffsetY",
    ["absorb.heal_prediction.texture"] = "healPredictionBarTexture",
    ["absorb.heal_prediction.opacity"] = "healPredictionBarOpacity",
    ["absorb.over_absorb_overlay"] = "overAbsorbOverlay",
    ["absorb.full_health_stripe"] = "fullHealthAbsorbStripe",
    ["outline.thickness"] = "barOutlineThickness",
    ["outline.layer"] = "barOutlineLayer",
    ["outline.texture"] = "barOutlineTexture",
    ["outline.color"] = "barOutlineColor",
    ["highlight.border_thickness"] = "highlightBorderThickness",
    ["highlight.border_mode.aggroOutlineMode"] = "aggroOutlineMode",
    ["highlight.aggro.roles"] = "aggroMode",
    ["highlight.border_mode.dispelOutlineMode"] = "dispelOutlineMode",
    ["highlight.dispel.trigger"] = "dispelBorderTrigger",
    ["highlight.dispel.show_on"] = "dispelBorderShowOn",
    ["highlight.border_mode.purgeOutlineMode"] = "purgeOutlineMode",
    ["highlight.priority.enabled"] = "hlPrioEnabled",
}
-- Most scope routes share their general key and suffix. Keep only the
-- multi-key and bars-table routes explicit, so both metadata views agree.
local Rows = { Schema = M.ControlSchema, keys = (function()
    local keys = {
        ["slanted.direction"] = { "bars.slantedBarDirection", "player.slantedBarDirection", "target.slantedBarDirection",
            "targettarget.slantedBarDirection", "focus.slantedBarDirection", "focustarget.slantedBarDirection",
            "pet.slantedBarDirection", "pettarget.slantedBarDirection", "boss.slantedBarDirection", "arena.slantedBarDirection",
            "gf_party.slantedBarDirection", "gf_raid.slantedBarDirection", "gf_mythicraid.slantedBarDirection" },
        ["temp_max_health.color"] = {
            "general.tempMaxHealthColor", "general.tempMaxHealthColorR", "general.tempMaxHealthColorG", "general.tempMaxHealthColorB",
        },
        ["absorb.heal_prediction.enabled"] = { "general.healPredEnabled", "general.showSelfHealPrediction" },
        ["absorb.healPredEnabled"] = { "general.healPredEnabled", "general.showSelfHealPrediction" },
        ["absorb.positive.enabled"] = { "general.enableAbsorbBar", "general.absorbTextMode" },
        ["outline.thickness"] = { "bars.barOutlineThickness" },
        ["outline.layer"] = { "bars.barOutlineLayer" },
        ["outline.texture"] = { "bars.barOutlineTexture" },
        ["power.smooth_fill"] = { "bars.smoothPowerBar" },
        ["power.chunked_fill"] = { "bars.chunkedPowerBar" },
    }
    for path, suffix in pairs(BAR_DYNAMIC_SETTING_SUFFIX_BY_PATH) do
        if path ~= "scope.override.enabled" and not keys[path] then
            keys[path] = { "general." .. suffix }
        end
    end
    return keys
end)() }
local BAR_DYNAMIC_SETTING_PATTERNS_BY_PATH = {
    ["absorb.positive.enabled"] = {
        "^barScope%.[%w_]+%.enableAbsorbBar$",
        "^barScope%.[%w_]+%.absorbTextMode$",
    },
    ["temp_max_health.color"] = {
        "^barScope%.[%w_]+%.tempMaxHealthColor$",
        "^barScope%.[%w_]+%.tempMaxHealthColor[RGB]$",
    },
}
local function IsDynamicBarPath(path)
    path = tostring(path or "")
    return path == "scope.override.enabled"
        or path == "power.smooth_fill"
        or path == "power.chunked_fill"
        or path:find("^textures%.") ~= nil
        or path:find("^gradient%.") ~= nil
        or path:find("^gloss%.") ~= nil
        or path:find("^temp_max_health%.") ~= nil
        or path:find("^absorb%.") ~= nil
        or path:find("^outline%.") ~= nil
        or (path:find("^highlight%.") ~= nil and path ~= "highlight.boss_target.mode")
end
local function Meta(path, classification, exact)
    local resolved = {}
    if type(exact) == "table" then
        for key, value in pairs(exact) do resolved[key] = value end
    end
    resolved.settingKey = resolved.settingKey or BAR_SETTING_BY_PATH[path]
    resolved.actionKey = resolved.actionKey or BAR_ACTION_BY_PATH[path]
    -- Release links open these scope-dependent controls in the shared scope (the
    -- route selects it, the hook confirms it); there they edit exactly this key.
    local linkKey = path == "absorb.heal_prediction.all_healers" and "general.healPredAllHealers"
        or path == "outline.texture" and "bars.barOutlineTexture" or nil
    if linkKey then
        resolved.searchPrepareKind, resolved.searchPrepareValue, resolved.searchPrepareSettingKey = "barsScope", "shared", linkKey
        resolved.prepareExactSearchTarget = function(_, target)
            return target.prepareValue == "shared" and CurrentBarsScope() == "shared"
        end
    end
    if path == "slanted.direction" then
        resolved.searchSettingKeys = Rows.keys[path]
    end
    local kind = classification or "setting"
    if (kind == "setting" or kind == "action") and not resolved.settingKey and not resolved.actionKey
        and IsDynamicBarPath(path)
    then
        resolved.searchSettingKeys = resolved.searchSettingKeys or Rows.keys[path]
        resolved.searchSettingKeyPatterns = resolved.searchSettingKeyPatterns
            or BAR_DYNAMIC_SETTING_PATTERNS_BY_PATH[path]
        local suffix = BAR_DYNAMIC_SETTING_SUFFIX_BY_PATH[path]
        if suffix and not resolved.searchSettingKeyPatterns then
            resolved.searchSettingKeyPatterns = { "^barScope%.[%w_]+%." .. suffix .. "$" }
        end
    end
    if kind == "setting" then
        local suffix = BAR_DYNAMIC_SETTING_SUFFIX_BY_PATH[path]
        local fields, shared, groups = suffix and { suffix }, "general"
        if path == "scope.override.enabled" then fields, shared, groups = { "hlOverride" }, nil, { "hlOverride", "barTextureOverride" }
        elseif path == "gradient.enableGradient" then fields = { "enableGradient", "gradientStrength" }
        elseif path == "gradient.enablePowerGradient" then fields = { "enablePowerGradient", "powerGradientStrength" }
        elseif path == "gradient.health.strength" then
            fields = { "gradientStrength", "powerGradientStrength", "powerGradientDirUp", "powerGradientDirDown",
                "powerGradientDirLeft", "powerGradientDirRight" }
        elseif path == "outline.color" then fields = { "barOutlineColorMode", "barOutlineColorR", "barOutlineColorG", "barOutlineColorB", "barOutlineColorA" }
        elseif path == "textures.background" then
            resolved.setting = Rows.Schema.Family({ "general.barBackgroundTexture", "gf_party.barBackgroundTexture", "gf_raid.barBackgroundTexture",
                "gf_mythicraid.barBackgroundTexture", "gf_party.barBgTexture", "gf_raid.barBgTexture", "gf_mythicraid.barBgTexture",
                "gf_party.barTextureOverride", "gf_raid.barTextureOverride", "gf_mythicraid.barTextureOverride",
                "gf_party.hlOverride", "gf_raid.hlOverride", "gf_mythicraid.hlOverride" })
        elseif path == "textures.foreground" then groups = { "barTexture", "barTextureOverride" }
        elseif path == "power.smooth_fill" or path == "power.chunked_fill" then
            resolved.setting = Rows.Schema.ScopedFields({ "powerSmoothFill", "powerChunkedFill" }, nil)
            resolved.setting.keys[#resolved.setting.keys + 1] = "bars.smoothPowerBar"
            resolved.setting.keys[#resolved.setting.keys + 1] = "bars.chunkedPowerBar"
        elseif path:match("^outline%.") and Rows.keys[path] then fields, shared = { Rows.keys[path][1]:match("%.(.+)$") }, "bars"
        elseif path == "highlight.boss_target.mode" then fields = { "bossTargetOutlineMode", "bossTargetHighlightEnabled" }
        elseif path == "highlight.priority.enabled" then fields = { "hlPrioEnabled", "highlightPrioEnabled" }
        elseif Rows.keys[path] then
            fields = {}
            for _, key in ipairs(Rows.keys[path]) do fields[#fields + 1] = key:match("%.(.+)$") end
        end
        if fields and not resolved.setting then resolved.setting = Rows.Schema.ScopedFields(fields, shared, "hlOverride", groups) end
    end
    return ControlMeta("opt_bars", "global", path, classification, resolved)
end
-- Page field policies translate into the shared typed binders; input, history,
-- refusal and refresh remain with those native bindings. A `direct` page passes
-- its plain reader, setter and apply functions instead of wrappers: they are
-- called as read(key, fallback, row.legacyKey), write(key, value, row.reason,
-- true) and changed(row.reason, row.gradientKind), so a slider drag step makes
-- no wrapper hop. A constant default is used as is, without a default call.
function Rows.Options(read, write, changed, raw, direct)
    return { bind = function(ctx, widget, row, kind)
        local fallback = row[3]
        local defaultIsFunction = type(fallback) == "function"
        local readArg = row
        if direct then readArg = row.legacyKey end
        local function Default()
            return defaultIsFunction and fallback() or fallback
        end
        local function Get()
            local fallback = Default()
            local value = read(row[2], fallback, readArg)
            if row.readValue then return row.readValue(value, fallback) end
            if kind == "toggle" then return row.defaultOn and fallback and value ~= false or value == true end
            if kind == "slider" or row.numeric then return tonumber(value) or fallback end
            return value
        end
        -- Scalar row policy is fixed when the control is built; profile and
        -- scope values still resolve through the live reader on every refresh.
        local get, key = row.get, row[2]
        if not get and not defaultIsFunction then
            if row.readValue then
                local convert = row.readValue
                get = function() return convert(read(key, fallback, readArg), fallback) end
            elseif kind == "toggle" then
                if row.defaultOn and fallback then get = function() return read(key, fallback, readArg) ~= false end
                else get = function() return read(key, fallback, readArg) == true end end
            elseif kind == "slider" or row.numeric then
                get = function() return tonumber(read(key, fallback, readArg)) or fallback end
            else get = function() return read(key, fallback, readArg) end end
        elseif not get and not row.readValue and kind == "dropdown" and not row.numeric then
            -- Texture defaults read the current general profile on every call.
            get = function() return read(key, fallback() or fallback, readArg) end
        end
        local function Set(value)
            local default = fallback
            if defaultIsFunction then default = fallback() or fallback end
            if row.writeValue then value = row.writeValue(value, default)
            elseif kind == "toggle" then value = value and true or false
            elseif kind == "slider" or row.numeric then value = tonumber(value) or default
            else value = value or (row.writeDefault ~= nil and row.writeDefault or default) end
            if row.skipEqual and raw(row[2]) == value then return end
            if row.beforeWrite then row.beforeWrite(value) end
            if direct then write(row[2], value, row.reason, true) else write(row[2], value, row) end
            if row.afterWrite then row.afterWrite(value) end
            if changed then
                if direct then changed(row.reason, row.gradientKind) else changed(row, value) end
            end
        end
        local meta = row.meta or Meta(row.path or row[2], row.classification, row.exact)
        local spec = { id = meta.controlId, kind = kind, key = row[2], labelKey = row[4][1],
            scope = "bars", applyDomain = row.domain or "bars", meta = meta,
            get = get or Get, set = row.set or Set }
        if kind == "slider" then
            spec.range, spec.defaultSource = { row[4][2], row[4][3], row[4][4] }, Default
        end
        Rows.Schema.Bind(ctx, widget, spec)
    end }
end
Rows.Commands = Rows.Options()
-- A string `tip` on a row is the standard tooltip: the row label as title, with the
-- options named by `tipOpts` ("label" by default, or "plain" / "power").
Rows.tipOpts = {
    label = { hook = true, labelHit = true },
    plain = { hook = true },
    power = { hook = true, labelHit = true, labelHitWhenDisabled = true },
}
function Rows.Build(ctx, parent, rows, opts, refs)
    for _, row in ipairs(rows) do
        if type(row.tip) == "string" then row.tip = { row[4][1], row.tip, Rows.tipOpts[row.tipOpts or "label"] } end
    end
    return Rows.Schema.Build(ctx, parent, rows, opts, refs)
end
local function RegisterSegment(segment, path, values)
    RegisterControl(segment, Meta(path, "ephemeral"), nil, "segment", values)
    if segment and type(segment.buttons) == "table" then
        for i = 1, #segment.buttons do
            local item = values and values[i] or {}
            RegisterControl(segment.buttons[i], Meta(path .. ".option." .. tostring(item.value), "ephemeral"),
                item.text or item.label or item.value or "", "button")
        end
    end
    return Rows.Schema.Owned(segment, "bars", "sectionNavigation")
end
local HIGHLIGHT_ORDER_KEYS = { "dispel", "aggro", "purge", "bossTarget" }
local HIGHLIGHT_ORDER_ALLOWED = { dispel = true, aggro = true, purge = true, bossTarget = true }
local HIGHLIGHT_ORDER_VALUES = {}
local function BuildHighlightOrderValues(prefix, used)
    if #prefix == #HIGHLIGHT_ORDER_KEYS then
        local value = table.concat(prefix, ",")
        HIGHLIGHT_ORDER_VALUES[#HIGHLIGHT_ORDER_VALUES + 1] = { value = value, text = value }
        return
    end
    for i = 1, #HIGHLIGHT_ORDER_KEYS do
        local key = HIGHLIGHT_ORDER_KEYS[i]
        if not used[key] then
            used[key], prefix[#prefix + 1] = true, key
            BuildHighlightOrderValues(prefix, used)
            prefix[#prefix], used[key] = nil, nil
        end
    end
end
BuildHighlightOrderValues({}, {})
local function ParseHighlightOrder(value)
    if type(value) ~= "string" then return nil end
    local order, used = {}, {}
    for token in value:gmatch("[^,]+") do
        token = token:match("^%s*(.-)%s*$")
        if token:lower() == "bosstarget" or token:lower() == "boss target" then token = "bossTarget"
        else token = token:lower() end
        if not HIGHLIGHT_ORDER_ALLOWED[token] or used[token] then return nil end
        used[token], order[#order + 1] = true, token
    end
    if #order ~= #HIGHLIGHT_ORDER_KEYS then return nil end
    return order
end
local HIGHLIGHT_ORDER_COMMAND = {
    kind = "dragrow",
    source = "global/highlight/priority/order",
    valueKind = "enum",
    values = HIGHLIGHT_ORDER_VALUES,
    get = function() return table.concat(PriorityOrder(), ",") end,
    set = function(value)
        local order = ParseHighlightOrder(value)
        if not order then return false end
        BarScopeSet("hlPrioOrder", order, "MSUF2_HIGHLIGHT_PRIORITY_ORDER")
        if CurrentBarsScope() == "shared" then
            G().hlPrioOrder = order
            G().highlightPrioOrder = order
        end
        return true
    end,
    canExecute = function() return true end,
}
local function RegisterDragRows(container, path)
    local rows = container and container.rows or {}
    local owner = rows[1] and rows[1].frame
    if owner then
        RegisterControl(owner, Meta(path .. ".order", "setting", {
            searchSettingKeyPatterns = { "^barScope%.[%w_]+%.hlPrioOrder$" },
            command = HIGHLIGHT_ORDER_COMMAND,
        }), "Highlight priority order", "dragrow")
        local spec = Rows.Schema.Owned(owner, "bars", "bars")._msuf2ControlSchema
        spec.get, spec.set = HIGHLIGHT_ORDER_COMMAND.get, HIGHLIGHT_ORDER_COMMAND.set
        spec.dragStart, spec.dragStop = owner:GetScript("OnDragStart"), owner:GetScript("OnDragStop")
        -- The remaining visible rows are handles for the same atomic four-item
        -- order. They must resolve to one catalog owner, not four competing
        -- setting routes.
        if M.MarkRuntimeControlComponent then
            for i = 2, #rows do M.MarkRuntimeControlComponent(rows[i].frame, owner) end
        end
    end
    return container
end
--- A client without focus, boss or arena units has no page and no frame for
--- those sensors, so they can never report enabled. Counting them left the
--- shared scope permanently "missing a sensor" and made the auto-enable write
--- aura config for units that do not exist on this client. Client support is
--- fixed for the session, so resolve the list once.
local supportedUnitFrameAuraUnits
local function SupportedUnitFrameAuraUnits()
    if supportedUnitFrameAuraUnits then return supportedUnitFrameAuraUnits end
    if type(M.SupportsUnitPage) ~= "function" then
        supportedUnitFrameAuraUnits = UNITFRAME_DISPEL_AURA_UNITS
        return supportedUnitFrameAuraUnits
    end
    local supported = {}
    for i = 1, #UNITFRAME_DISPEL_AURA_UNITS do
        local unit = UNITFRAME_DISPEL_AURA_UNITS[i]
        if M.SupportsUnitPage("uf_" .. unit) then supported[#supported + 1] = unit end
    end
    supportedUnitFrameAuraUnits = supported
    return supported
end
local function UnitFrameAuraScopeUnits()
    local scope = CurrentBarsScope()
    local units = SupportedUnitFrameAuraUnits()
    if scope == "shared" then return #units > 0 and units or nil end
    for i = 1, #units do
        if units[i] == scope then return { scope } end
    end
    return nil
end
local function UnitFrameAuraSensorMissingForScope()
    local a3 = MSUF and MSUF.MSUF_Auras3
    local model = a3 and a3.MenuModel
    if not (model and type(model.UnitEnabled) == "function") then return false end
    local units = UnitFrameAuraScopeUnits()
    if not units then return false end
    for i = 1, #units do
        if model.UnitEnabled(units[i]) ~= true then return true end
    end
    return false
end
local function EnsureUnitFrameAuraSensorsForScope()
    local a3 = MSUF and MSUF.MSUF_Auras3
    local model = a3 and a3.MenuModel
    if not (model and type(model.UnitEnabled) == "function" and type(model.SetUnitEnabled) == "function") then return false end
    local units, changed = UnitFrameAuraScopeUnits(), false
    if not units then return false end
    for i = 1, #units do
        if model.UnitEnabled(units[i]) ~= true then
            model.SetUnitEnabled(units[i], true)
            changed = true
        end
    end
    if changed and type(M.ShowStatusFeedback) == "function" then
        M.ShowStatusFeedback("Aura sensor enabled for Dispel. Buff and Debuff icon caps may stay at 0.", "info", 3.0)
    end
    return changed
end
-- Scope rules are shared by all page sections. Keeping them outside the page builder
-- prevents every widget callback from being routed through one giant closure.
local function SharedScope() return CurrentBarsScope() == "shared" end
local ReloadAfterCombatCheck = function()
    if InCombatLockdown and InCombatLockdown() then
        if print then print(M.Tr("|cffff5555MSUF|r: Can't reload UI in combat. Leave combat, then type /reload.")) end
    elseif type(ReloadUI) == "function" then
        ReloadUI()
    end
end

local function GroupScope()
    local scope = CurrentBarsScope()
    return type(IsGFScope) == "function" and IsGFScope(scope)
        or scope == "gf_party" or scope == "gf_raid"
end
local function PurgeScopeSupported()
    local scope = CurrentBarsScope()
    return scope == "shared" or scope == "target" or scope == "focus"
end
local function ScopedControls() return SharedScope() or ScopeHasOverride(CurrentBarsScope(), "hlOverride") end
local function HighlightControls() return CurrentBarsScope() ~= nil end
local function BorderTestScope()
    local scope = CurrentBarsScope()
    return scope == "gf_party" and "party" or scope == "gf_raid" and "raid" or scope
end

-- ApplyService owns batching, combat deferral and compatibility fallbacks.
-- The old page duplicated all of that logic in seven near-identical request functions.
Rows.applyService = MSUF.Require("MSUF_Menu2_ApplyService", FILE)
local function RequestApply(method, reason, scope)
    return Rows.applyService[method](reason, scope)
end
local function RequestOutlineRuntime() return RequestApply("RequestBarOutline", "MSUF2_BAR_OUTLINE", CurrentBarsScope()) end
local function RequestAggroBorderRuntime() return RequestApply("RequestAggroBorder", "MSUF2_AGGRO_BORDER_RUNTIME", CurrentBarsScope()) end
local function RequestGroupAggroRoleRuntime() return RequestApply("RequestGroupAggroRole", "MSUF2_GROUP_AGGRO_ROLE_RUNTIME", CurrentBarsScope()) end
local function RequestBossTargetBorderRuntime() return RequestApply("RequestBossTargetBorder", "MSUF2_BOSS_TARGET_BORDER_RUNTIME", "boss") end
local function RequestHighlightPriorityRuntime(reason)
    return RequestApply("RequestHighlightPriority", reason or "MSUF2_HIGHLIGHT_PRIORITY_RUNTIME", CurrentBarsScope())
end
local function RequestAllHighlightBorderRuntime()
    return RequestApply("RequestHighlightBorders", "MSUF2_ALL_HIGHLIGHT_BORDER_RUNTIME", CurrentBarsScope())
end
-- Border test modes. The owner assigns each runtime flag directly, so every mode reads its flag
-- by the bare global name inside its own closures: `flag()` answers a boolean and `stop(keep)`
-- turns a running test off unless `keep` (its border mode is still on). The setter is an
-- optional provider that resolves once, the first time a running test needs it.
Rows.testModes = {
    aggro = { setter = "MSUF_SetAggroBorderTestMode",
        flag = function() return MSUF_AggroBorderTestMode and true or false end,
        stop = function(keep) if not keep and MSUF_AggroBorderTestMode then Rows.StopRunning("aggro") end end },
    dispel = { setter = "MSUF_SetDispelBorderTestMode",
        flag = function() return MSUF_DispelBorderTestMode and true or false end,
        stop = function(keep) if not keep and MSUF_DispelBorderTestMode then Rows.StopRunning("dispel") end end },
    purge = { setter = "MSUF_SetPurgeBorderTestMode",
        flag = function() return MSUF_PurgeBorderTestMode and true or false end,
        stop = function(keep) if not keep and MSUF_PurgeBorderTestMode then Rows.StopRunning("purge") end end },
    bossTarget = { setter = "MSUF_SetBossTargetBorderTestMode",
        flag = function() return MSUF_BossTargetBorderTestMode and true or false end,
        stop = function(keep) if not keep and MSUF_BossTargetBorderTestMode then Rows.StopRunning("bossTarget") end end },
}
function Rows.TestSetter(kind)
    local mode = Rows.testModes[kind]
    local setter = mode.resolved
    if setter == nil then
        setter = MSUF.Optional(mode.setter) or false
        mode.resolved = setter
    end
    return setter
end
function Rows.StopRunning(kind)
    local setter = Rows.TestSetter(kind)
    if type(setter) == "function" then setter(false) end
end
function Rows.RetargetTest(kind)
    local setter = Rows.TestSetter(kind)
    if type(setter) == "function" then setter(true, BorderTestScope()) end
end
local function RequestDispelPurgeBorderRuntime()
    local result = RequestApply("RequestDispelPurgeBorder", "MSUF2_DISPEL_PURGE_BORDER_RUNTIME", CurrentBarsScope())
    if MSUF_DispelBorderTestMode then Rows.RetargetTest("dispel") end
    if MSUF_PurgeBorderTestMode then Rows.RetargetTest("purge") end
    return result
end
local function ApplyRoundedRuntime()
    return RequestApply("RequestRoundedBars", "MSUF2_ROUNDED", CurrentBarsScope())
end

-- One Reload button, and Escape does not answer: menu-owned prompts
-- (M.ShowPrompt), which also take the menu's popup priority.
local function ShowDispelBorderReloadRequiredPopup()
    M.ShowPrompt("MSUF2_DISPEL_BORDER_RELOAD_REQUIRED", {
        text = M.Tr("Dispel border") .. "\n\n" .. M.Tr("Requires a UI reload."),
        accept = RELOAD or M.Tr("Reload"), single = true, hideOnEscape = false,
        onAccept = ReloadAfterCombatCheck,
    })
end

local function ShowRoundedReloadRequiredPopup()
    M.ShowPrompt("MSUF2_ROUNDED_RELOAD_REQUIRED", {
        text = M.Tr("Rounded frame texture was changed.\n\nA UI reload is required because this " ..
            "style rebuilds frame masks and protected frame visuals.\n\nReload now?"),
        accept = RELOAD or M.Tr("Reload"), single = true, hideOnEscape = false,
        onAccept = ReloadAfterCombatCheck,
    })
end
local function SetRoundedBool(key, value, requireReload)
    value = value and true or false
    local bars = Bars()
    local switchStyle = key == "roundedFramesEnabled" and value and bars.slantedBarsEnabled ~= false
    if bars[key] == value and not switchStyle then return end
    bars[key] = value
    if switchStyle then bars.slantedBarsEnabled = false end
    ApplyRoundedRuntime()
    if switchStyle and M.RequestRefresh then M.RequestRefresh(nil, "rounded-style-selected") end
    if requireReload then ShowRoundedReloadRequiredPopup() end
end
local function RegisterRoundedSearch(control, label, extraKeywords, help, kind, meta)
    if not (control and type(M.RegisterSearchWidget) == "function") then return end
    local keywords = {
        "rounded texture", "rounded frame texture", "rounded frames", "round corners", "rounded corners",
        "bars rounded", "enable rounded frames", "disable rounded frames", "abgerundete frames", "runde kanten",
    }
    if type(extraKeywords) == "string" then
        for keyword in extraKeywords:gmatch("[^|]+") do keywords[#keywords + 1] = keyword end
    elseif type(extraKeywords) == "table" then
        for i = 1, #extraKeywords do keywords[#keywords + 1] = extraKeywords[i] end
    end
    local payload = {
        label = label, kind = kind or control._msuf2ControlKind or "toggle",
        anchor = control._msuf2Title or control._msuf2Label or control,
        values = { "On", "Off", "Enable", "Disable", "Einschalten", "Ausschalten" },
        keywords = keywords,
        help = help or "Controls the rounded frame texture style for unit frames, group frames, " ..
            "power bars, class resources, castbars, and mouseover highlights.",
    }
    if type(meta) == "table" then for key, value in pairs(meta) do payload[key] = value end end
    M.RegisterSearchWidget(control, payload)
end

local function ShapePreviewSurface(card, width, height)
    local host = PixelLayoutRegion(CreateFrame("Frame", nil, card))
    host:SetPoint("TOPLEFT", card, "TOPLEFT", 20, -40)
    host:SetSize(width, height)
    local surface = M.PreviewHelpers.NewRuntimeUnitSurface(host, CurrentBarsScope, { hp = .78, power = .66, hpPct = .78, powerPct = .66 })
    card._msuf2RoundedPreviewSample = surface
    return surface
end
local function CreateRoundedTexturePreview(parent, x, y, width)
    width = max(320, floor((tonumber(width) or 560) + .5))
    local card = W.ControlCard(parent, "Preview", nil, x, y, width, ROUNDED_PREVIEW_CARD_HEIGHT)
    if not card then return end
    local surface = ShapePreviewSurface(card, min(440, max(280, width - 44)), 46)
    function card:RefreshRoundedPreview() surface:Refresh() end
    card:RefreshRoundedPreview()
    return card
end

local NormalizeDispelTrigger = MSUF.Require("MSUF_NormalizeDispelBorderTrigger", FILE)
local function NormalizeAggroMode(value)
    value = tostring(value or "ALL"):upper()
    if value == "TANK_ONLY" then return "TANK" end
    if value == "HEALER_ONLY" then return "HEALER" end
    return (value == "NON_TANK" or value == "HEALER" or value == "TANK") and value or "ALL"
end

local function GradientControlsActive() return ScopedControls() end
local function TextureControlsActive() return SharedScope() or GroupScope() and ScopedControls() end
local POWER_GRADIENT_DIR_KEYS = {
    LEFT = "powerGradientDirLeft",
    RIGHT = "powerGradientDirRight",
    UP = "powerGradientDirUp",
    DOWN = "powerGradientDirDown",
}
local function GradientDirectionKeys(kind)
    return kind == "power" and POWER_GRADIENT_DIR_KEYS or GRADIENT_DIR_KEYS
end
local function CurrentGradientDirectionsForScope(kind)
    local keys = GradientDirectionKeys(kind)
    if kind == "power" then
        local hasPower, hasLegacy = false, false
        for direction, key in pairs(POWER_GRADIENT_DIR_KEYS) do
            hasPower = hasPower or GradientScopeHasExplicit(key)
            hasLegacy = hasLegacy or GradientScopeHasExplicit(GRADIENT_DIR_KEYS[direction])
        end
        if not hasPower and hasLegacy then keys = GRADIENT_DIR_KEYS end
    end
    local directions, any = {}, false
    for direction, key in pairs(keys) do
        directions[direction] = GradientScopeGet(key, false) == true
        any = any or directions[direction]
    end
    if not any then
        local directionKey = kind == "power" and "powerGradientDirection" or "gradientDirection"
        local legacyKey = kind == "power" and "gradientDirection" or nil
        local legacy = GradientScopeGet(directionKey, "RIGHT", legacyKey)
        directions[keys[legacy] and legacy or "RIGHT"] = true
    end
    return directions
end
local function FreezePowerGradientScope()
    local current = CurrentGradientDirectionsForScope("power")
    for direction, key in pairs(POWER_GRADIENT_DIR_KEYS) do
        if not GradientScopeHasExplicit(key) then GradientScopeSet(key, current[direction] == true) end
    end
    if not GradientScopeHasExplicit("powerGradientStrength") then
        GradientScopeSet("powerGradientStrength", GradientScopeGet("powerGradientStrength", 0.45, "gradientStrength"))
    end
end
local function ToggleGradientDirectionForScope(kind, direction)
    direction = GRADIENT_DIR_KEYS[direction] and direction or "RIGHT"
    if kind == "health" then FreezePowerGradientScope() end
    local keys = GradientDirectionKeys(kind)
    local directions = CurrentGradientDirectionsForScope(kind)
    directions[direction] = not directions[direction]
    local any = false
    for candidate in pairs(GRADIENT_DIR_KEYS) do any = any or directions[candidate] == true end
    if not any then directions[direction] = true end
    for candidate, key in pairs(keys) do GradientScopeSet(key, directions[candidate] == true) end
    GradientScopeSet(kind == "power" and "powerGradientDirection" or "gradientDirection", direction)
end
local function ApplyGradientRuntime(reason, kind)
    local enabledKey = kind == "power" and "enablePowerGradient" or "enableGradient"
    local strengthKey = kind == "power" and "powerGradientStrength" or "gradientStrength"
    local legacyStrengthKey = kind == "power" and "gradientStrength" or nil
    if GradientScopeGet(enabledKey, false) == true then
        local strength = tonumber(GradientScopeGet(strengthKey, 0.45, legacyStrengthKey))
        if not (strength and strength > 0) then GradientScopeSet(strengthKey, 0.45) end
    end
    return RequestApply("RequestBarGradients", reason or "MSUF2_GRADIENT", CurrentBarsScope())
end

-- Bars keeps its normal accordion controls focused on geometry and behavior.
-- Color targets are built only when the quiet three-dot shortcut is clicked,
-- so no hidden swatch widgets or gameplay/runtime hooks are needed.
local function AttachBarsColorShortcut(section, title, note, label, getRGB, setRGB, historySource, captureState, restoreState, catalogMeta)
    if not (section and W.AttachContextColorShortcut) then return nil end
    local targets = {
        {
            label = label,
            getRGB = getRGB,
            setRGB = setRGB,
            captureState = captureState,
            restoreState = restoreState,
            historyLabel = tostring(label or "Bar") .. " color",
        },
    }
    local shortcut = W.AttachContextColorShortcut(section, {
        title = title,
        note = note,
        getTargets = function() return targets end,
        historySource = historySource or "menu:bars-colors",
        maxTargets = 1,
    })
    if shortcut and catalogMeta then
        local registeredMeta = {}
        for key, value in pairs(catalogMeta) do registeredMeta[key] = value end
        registeredMeta.command = {
            kind = "color",
            source = registeredMeta.controlPath or registeredMeta.identityKey,
            get = getRGB,
            set = setRGB,
            searchSettingKeys = registeredMeta.searchSettingKeys,
            searchSettingKeyPatterns = registeredMeta.searchSettingKeyPatterns,
            blockCombat = function()
                return type(M.BlockCombatAction) == "function" and M.BlockCombatAction() or false
            end,
        }
        RegisterControl(shortcut, registeredMeta, title or label or "Bar color", "color")
        Rows.Schema.Owned(shortcut, "bars", "contextColors")._msuf2ControlSchema.setting = Rows.Schema.FromMeta(registeredMeta)
    end
    return shortcut
end

local function CaptureBarsScopeFields(fields)
    local scope = CurrentBarsScope()
    local keys = scope ~= "shared" and ScopeDBKeys(scope) or nil
    local state = { scope = scope, fields = fields }
    if not keys then
        state.shared = {}
        local general = G()
        for i = 1, #fields do
            local field = fields[i]
            state.shared[field] = general[field]
        end
        return state
    end

    state.entries = {}
    local db = DB()
    for i = 1, #keys do
        local key, entry = keys[i], db[keys[i]]
        local saved = { key = key, existed = type(entry) == "table", values = {} }
        for j = 1, #fields do
            local field = fields[j]
            if saved.existed then saved.values[field] = entry[field] end
        end
        state.entries[i] = saved
    end
    return state
end

local function RestoreBarsScopeFields(state)
    if type(state) ~= "table" or type(state.fields) ~= "table" then return end
    if state.shared then
        local general = G()
        for i = 1, #state.fields do
            local field = state.fields[i]
            general[field] = state.shared[field]
        end
        return
    end

    local db = DB()
    for i = 1, #(state.entries or {}) do
        local saved = state.entries[i]
        local entry = db[saved.key]
        if saved.existed then
            if type(entry) ~= "table" then
                entry = {}
                db[saved.key] = entry
            end
            for j = 1, #state.fields do
                local field = state.fields[j]
                entry[field] = saved.values[field]
            end
        elseif type(entry) == "table" then
            for j = 1, #state.fields do entry[state.fields[j]] = nil end
            if next(entry) == nil then db[saved.key] = nil end
        end
    end
end

local TEMP_MAX_HEALTH_COLOR_STATE_FIELDS = {
    "hlOverride", "tempMaxHealthColorR", "tempMaxHealthColorG", "tempMaxHealthColorB",
}
local OUTLINE_COLOR_STATE_FIELDS = {
    "hlOverride", "barOutlineColorMode", "barOutlineColorR", "barOutlineColorG", "barOutlineColorB", "barOutlineColorA",
}

local function SetOutlineRGB(entry, r, g, b)
    if entry.barOutlineColorR == r and entry.barOutlineColorG == g and entry.barOutlineColorB == b
        and entry.barOutlineColorA == 1 and entry.barOutlineColorMode == nil then return false end
    entry.barOutlineColorMode = nil
    entry.barOutlineColorR, entry.barOutlineColorG, entry.barOutlineColorB, entry.barOutlineColorA = r, g, b, 1
    return true
end
local function SetOutlineColorForScope(r, g, b)
    r, g, b = tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0
    local scope, keys = CurrentBarsScope(), ScopeDBKeys(CurrentBarsScope())
    if scope == "shared" or not keys then return SetOutlineRGB(G(), r, g, b) end
    local db, changed = DB(), false
    for i = 1, #keys do
        db[keys[i]] = db[keys[i]] or {}
        changed = SetOutlineRGB(db[keys[i]], r, g, b) or db[keys[i]].hlOverride ~= true or changed
    end
    ScopeSetOverride(scope, "hlOverride", true)
    return changed
end
local function GeneralBarBackgroundTextureKey()
    local general = G()
    return general.barBackgroundTexture == nil and (general.barBgTexture or "") or general.barBackgroundTexture
end
local function BarTextureForScope()
    -- Unit scopes use the shared texture; a group scope shows what its frames draw.
    return GroupScope() and GP.GroupTextureRead(CurrentBarsScope(), "barTexture") or ReadG("barTexture", "Blizzard")
end
local function SetBarTextureForScope(value)
    value = value or "Blizzard"
    if not SharedScope() and not GroupScope() or BarTextureForScope() == value then return false end
    BarScopeSet("barTexture", value, "MSUF2_BAR_TEXTURE")
    return true
end
local function BarBackgroundTextureForScope()
    local scope = CurrentBarsScope()
    if scope ~= "shared" and not GroupScope() then return GeneralBarBackgroundTextureKey() end
    if scope ~= "shared" then
        -- Show what the group frames draw (GF.ResolveBarBgTexture's ownership rule).
        local db, keys = DB(), ScopeDBKeys(scope)
        for i = 1, #(keys or {}) do
            local entry = db[keys[i]]
            if GP.GroupEntryOwnsTextures(entry) then
                if entry.barBackgroundTexture ~= nil then return entry.barBackgroundTexture end
                if entry.barBgTexture ~= nil then return entry.barBgTexture end
            end
        end
    end
    return GeneralBarBackgroundTextureKey()
end
local function SetBarBackgroundTextureForScope(value)
    value = value or ""
    local scope, keys = CurrentBarsScope(), ScopeDBKeys(CurrentBarsScope())
    if scope ~= "shared" and not GroupScope() then return false end
    if scope == "shared" or not keys then
        local general = G()
        if general.barBackgroundTexture == value then return false end
        general.barBackgroundTexture = value
        return true
    end
    -- Taking ownership alone changes what the frames draw (an explicit false wins).
    local db, changed = DB(), not GP.GroupTexturesOwned(scope)
    GP.SetGroupTextureOwner(scope, true)
    ScopeSetOverride(scope, "hlOverride", true)
    for i = 1, #keys do
        db[keys[i]] = db[keys[i]] or {}
        changed = db[keys[i]].barBackgroundTexture ~= value or db[keys[i]].barBgTexture ~= value or changed
        db[keys[i]].barBackgroundTexture, db[keys[i]].barBgTexture = value, value
    end
    return changed
end
local function BuildScopeSection(ctx, b)
    local function HasScopedSlantedDirection(scope)
        -- Selector values are already canonical; keep its badge refresh allocation-free.
        local conf = DB()[scope]
        local value = conf and conf.slantedBarDirection
        return value == "RIGHT_DOWN" or value == "RIGHT_UP" or value == "LEFT_DOWN"
            or value == "LEFT_UP" or value == "BOTH_DOWN" or value == "BOTH_UP"
    end
    local scopeValues = GP.SCOPE_VALUES
    local function RefreshBarsPage(reason)
        M.RequestRefresh(ctx, reason)
    end
    local scopeUI = GP.BuildScopeOverrideSection(ctx, b, {
        values = scopeValues,
        meta = Meta,
        getValue = function() return CurrentBarsScope() end,
        setValue = function(v)
            G().hpPowerTextSelectedKey = NormalizeScopeKey(v)
            RefreshBorderTestModes()
            RefreshBarsPage("bars-scope-change")
        end,
        hasOverride = function(value)
            return value ~= "shared" and (ScopeHasOverride(value, "hlOverride") or HasScopedSlantedDirection(value))
        end,
        getOverride = function()
            local key = CurrentBarsScope()
            return ScopeHasOverride(key, "hlOverride")
        end,
        setOverride = function(v)
            local key = CurrentBarsScope()
            if key ~= "shared" then
                ScopeSetOverride(key, "hlOverride", v)
                -- Group textures follow this switch again, also after a Copy To flag.
                GP.SetGroupTextureOwner(key, nil)
                -- Texture refresh alone leaves the unit outline's painted state stale.
                M.RequestGeneralDomains("MSUF2_BARS_OVERRIDE", {
                    preview = true, applyAll = false, bars = true,
                    barOutline = not IsGFScope(key), barsScope = key,
                })
            end
            RefreshBarsPage("bars-scope-override")
        end,
        reset = function()
            local resetDirections = false
            for i = 1, #scopeValues do
                local key = scopeValues[i].value
                if key ~= "shared" then
                    ScopeSetOverride(key, "hlOverride", false)
                    GP.SetGroupTextureOwner(key, nil)
                    local keys, db = ScopeDBKeys(key), DB()
                    for j = 1, #(keys or {}) do
                        local entry = db[keys[j]]
                        if entry and entry.slantedBarDirection ~= nil then
                            entry.slantedBarDirection = nil
                            resetDirections = true
                        end
                    end
                end
            end
            M.RequestGeneralDomains("MSUF2_BARS_RESET_OVERRIDES", {
                preview = true, applyAll = false, bars = true, barOutline = true, roundedBars = resetDirections, barsScope = "shared",
            })
            RefreshBarsPage("bars-reset-overrides")
        end,
        hint = "Textures are shared except Party/Raid group-frame overrides. Gradients can be customized per unit or group scope.",
        updateHint = function(hint, current, active, shared)
            if shared then
                hint:SetText("Textures are shared except Party/Raid group-frame overrides. Gradients can be customized per unit or group scope.")
            elseif HasScopedSlantedDirection(current) then
                hint:SetText("This scope uses its own slanted cut direction. Other bar settings follow the custom-settings switch.")
            elseif IsGFScope(current) and ScopeHasOverride(current, "hlOverride") then
                hint:SetText("This group scope can use custom textures and gradients. Raid also applies to Mythic Raid.")
            elseif ScopeHasOverride(current, "hlOverride") then
                hint:SetText("This scope can use custom gradients and bar settings. Textures still follow Shared.")
            else
                hint:SetText("This scope follows Shared bar settings. Turn on custom settings here when this scope needs different gradients or bar settings.")
            end
        end,
    })
    if scopeUI then
        local scope = Rows.Schema.ScopeOwner(scopeUI.segment, "bars", "menuState")._msuf2ControlSchema
        Rows.Schema.Owned(scopeUI.override, "bars", "bars")
        Rows.Schema.Owned(scopeUI.reset, "bars", "bars")
        Rows.Schema.Custom(scopeUI.section, { id = scope.id .. ".owner", kind = "scope", scope = "bars",
            applyDomain = "menuState", owner = scopeUI.section, selector = scopeUI.segment })
    end
    if M.AddTooltip and scopeUI then
        M.AddTooltip(scopeUI.override, "Use custom settings for this scope",
            "Gives this unit or group its own gradient, absorb, outline and highlight " ..
                "settings instead of following Shared. Turning it off keeps your custom values.",
            { hook = true, labelHit = true })
        M.AddTooltip(scopeUI.reset, "Reset",
            "Resets all scoped slanted directions to Shared and turns off custom bar settings for every unit and group. Other custom values stay saved.",
                { hook = true })
    end
end

function GP.BuildGradientDirectionPads(textures, padX, hpY, powerY, SyncGradientControls)
    local padW, padH = 104, 78
    local padButtonW, padButtonH = 22, 18
    local directionButtons = { health = {}, power = {} }
    local pads = {}
    local function BuildDirectionPad(kind, y)
        local pad = T.Panel(textures, nil, T.colors.panel2 or { 0.014, 0.038, 0.072, 0.55 }, T.colors.borderSoft)
        pad:SetPoint("TOPLEFT", textures, "TOPLEFT", padX, y)
        pad:SetSize(padW, padH)
        local center = PixelLayoutRegion(pad:CreateTexture(nil, "ARTWORK"))
        center:SetPoint("CENTER", pad, "CENTER", 0, 0)
        center:SetSize(10, 10)
        local centerColor = T.colors.coreRim or { 0.043, 0.096, 0.150 }
        center:SetColorTexture(centerColor[1], centerColor[2], centerColor[3], 0.95)
        local function PadButton(text, value, x, buttonY)
            local btn = T.Button(pad, text, padButtonW, padButtonH, { history = true })
            btn:SetPoint("TOPLEFT", pad, "TOPLEFT", x, buttonY)
            T.CenterButtonLabel(btn)
            btn:SetScript("OnClick", function()
                ToggleGradientDirectionForScope(kind, value or "RIGHT")
                ApplyGradientRuntime(kind == "power" and "MSUF2_POWER_GRADIENT_DIRECTION" or "MSUF2_HP_GRADIENT_DIRECTION", kind)
                SyncGradientControls()
            end)
            -- The arrow glyphs are no searchable names. The pad is found once, by its
            -- name on the first arrow; the other arrows keep their glyph.
            local meta = Meta("gradient." .. kind .. ".direction." .. tostring(value), "action")
            local label = value == "UP" and "Gradient direction" or text
            RegisterControl(btn, meta, label, "button")
            Rows.Schema.Custom(btn, { id = meta.controlId, meta = meta,
                kind = "button", labelKey = label, scope = "bars", applyDomain = "bars", owner = btn,
                setting = Rows.Schema.ScopedFields(M.WordList [[
                    gradientDirUp gradientDirDown gradientDirLeft gradientDirRight gradientDirection gradientStrength
                    powerGradientDirUp powerGradientDirDown powerGradientDirLeft powerGradientDirRight powerGradientDirection powerGradientStrength
                ]], "general", "hlOverride"), action = Rows.Schema.ButtonAction(btn) })
            if M.AddTooltip then
                M.AddTooltip(btn, nil,
                    "Adds or removes a fade direction; the shade darkens toward this arrow. Directions can be combined, and one always stays on.",
                    { hook = true })
            end
            directionButtons[kind][value] = btn
        end
        local centerX = (padW - padButtonW) * 0.5
        local centerY = (padH - padButtonH) * 0.5
        local sideOffset = 23
        PadButton("^", "UP", centerX, -(centerY - sideOffset))
        PadButton("<", "LEFT", centerX - sideOffset, -centerY)
        PadButton(">", "RIGHT", centerX + sideOffset, -centerY)
        PadButton("v", "DOWN", centerX, -(centerY + sideOffset))
        Rows.Schema.Custom(pad, { id = Meta("gradient." .. kind .. ".direction", "ephemeral").controlId,
            kind = "directionpad", scope = "bars", applyDomain = "bars", owner = pad, controls = directionButtons[kind] })
        pads[kind] = pad
    end
    BuildDirectionPad("health", hpY - 2)
    BuildDirectionPad("power", powerY - 2)
    return directionButtons, pads
end

function GP.BuildBarTextureControls(ctx, textures, leftW, leftX, topY)
    local options = Rows.Options(function(key, fallback) return Bars()[key] or fallback end,
        function(key, value) Bars()[key] = value end, function(row) ApplyBars(row.reason) end,
        function(key) return Bars()[key] end)
    -- Shared power-bar art for every unit power bar (detached or not). Stored in
    -- the shared bars table like powerBarHeight, and resolved in the UF compiler
    -- as: this value -> Class Resources detached art -> per-unit powerBarTexture.
    local refs = Rows.Schema.Build(ctx, textures, {
        { "dropdown", "foreground", "", { "Bar textures (SharedMedia)", function() return TextureValues(nil) end, leftW },
            { leftX, topY, leftW, "LEFT" }, path = "textures.foreground", get = BarTextureForScope,
            set = function(v) if SetBarTextureForScope(v) then ApplyBars("MSUF2_BAR_TEXTURE") end end },
        { "dropdown", "background", "", { "Background texture", function() return TextureValues("Use foreground texture") end, leftW },
            { leftX, topY - 54, leftW, "LEFT" }, path = "textures.background", get = BarBackgroundTextureForScope,
            set = function(v) if SetBarBackgroundTextureForScope(v) then ApplyBars("MSUF2_BAR_BG_TEXTURE") end end },
        { "dropdown", "powerBarTexture", "", { "Power bar texture", function() return TextureValues("Use bar texture") end, leftW },
            { leftX, topY - 108, leftW, "LEFT" }, path = "textures.power_foreground", skipEqual = true, reason = "MSUF2_POWER_BAR_TEXTURE",
            tip = { "Power Bar Texture",
                "Art for every unit's power bar. Leave on Use bar texture to keep the shared bar art. Each unit page can override this, and the Class " ..
                    "Resources detached power texture still wins for a detached Player bar.",
                { hook = true, owner = "ANCHOR_RIGHT" } } },
        { "dropdown", "powerBarBgTexture", "", { "Power background texture", function() return TextureValues("Use bar background texture") end, leftW },
            { leftX, topY - 162, leftW, "LEFT" }, path = "textures.power_background", skipEqual = true, reason = "MSUF2_POWER_BAR_BG_TEXTURE",
            tip = { "Power Background Texture", "Background art behind every unit's power bar. Overridable per unit on the unit page.", { hook = true,
                owner = "ANCHOR_RIGHT" } } },
    }, options)
    return refs.foreground, refs.background
end

function GP.BuildBarGlossControls(ctx, section, leftX, rightX, width, compact)
    local topY = compact and -546 or -304
    local Sync = M.RefreshProxy()
    local options = Rows.Options(function(key, fallback, row)
        local value = BarScopeGet(key, row.percent and 0.5 or fallback)
        return row.percent and floor(max(0, min(1, tonumber(value) or 0.5)) * 100 + 0.5) or value
    end, function(key, value, row)
        if row.percent then value = max(0, min(100, value)) / 100 end
        BarScopeSet(key, value, row.reason, true)
    end, function(row)
        RequestApply("RequestBarGradients", row.reason, CurrentBarsScope())
        Sync()
    end)
    local refs = Rows.Build(ctx, section, {
        { "toggle", "healthGlossEnabled", false, { "Health gloss", leftX, topY, width },
            path = "gloss.health.enabled", reason = "MSUF2_HEALTH_GLOSS",
            tip = "Adds a white reflection over the filled bar, including dark bars." },
        { "slider", "healthGlossStrength", 50, { "Health gloss strength", 0, 100, 5, width },
            { leftX, topY - 38, width, "LEFT" }, path = "gloss.health.strength", percent = true, reason = "MSUF2_HEALTH_GLOSS_STRENGTH",
            tip = "Sets the reflection strength from 0 to 100." },
        { "toggle", "powerGlossEnabled", false, { "Power gloss", rightX, compact and topY - 96 or topY, width },
            path = "gloss.power.enabled", reason = "MSUF2_POWER_GLOSS",
            tip = "Adds a white reflection over the filled bar, including dark bars." },
        { "slider", "powerGlossStrength", 50, { "Power gloss strength", 0, 100, 5, width },
            { rightX, (compact and topY - 96 or topY) - 38, width, "LEFT" }, path = "gloss.power.strength",
            percent = true, reason = "MSUF2_POWER_GLOSS_STRENGTH",
            tip = "Sets the reflection strength from 0 to 100." },
    }, options)
    local toggles = { refs.healthGlossEnabled, refs.powerGlossEnabled }
    if W.SetControlsDisabledReason and W.TurnOnReason then
        local scopeReason = W.TurnOnReason("Use custom settings for this scope", ScopedControls)
        W.SetControlsDisabledReason(toggles, scopeReason)
        local healthReason = W.TurnOnReason("Health gloss", function() return BarScopeGet("healthGlossEnabled", false) == true end)
        local powerReason = W.TurnOnReason("Power gloss", function() return BarScopeGet("powerGlossEnabled", false) == true end)
        W.SetControlDisabledReason(refs.healthGlossStrength, function(control) return scopeReason(control) or healthReason(control) end)
        W.SetControlDisabledReason(refs.powerGlossStrength, function(control) return scopeReason(control) or powerReason(control) end)
    end
    M.TrackRefresh(ctx, Sync(function()
        local active = GradientControlsActive()
        SetControlsEnabled(toggles, active)
        SetControlEnabled(refs.healthGlossStrength, active and BarScopeGet("healthGlossEnabled", false) == true)
        SetControlEnabled(refs.powerGlossStrength, active and BarScopeGet("powerGlossEnabled", false) == true)
    end))
end

local function BuildTextureSection(ctx, b)
    local compactTextures = (ctx.width or 720) < 560
    local textures = Rows.Schema.Section(b:CollapsibleSection("bars_textures", "Textures & Gradient", compactTextures and 766 or 448, true), "bars")
    local leftX, topY = 14, -42
    local rightX = compactTextures and leftX or math.max(340, math.floor((ctx.width or 720) * 0.50))
    local leftW = compactTextures and math.max(220, (ctx.width or 720) - 42) or math.min(300, math.max(220, rightX - 48))
    -- Compact stacks the gradient block under the texture column, which now
    -- carries two extra power dropdowns.
    local gradientY = compactTextures and (topY - 234) or topY
    local barTexture, bgTexture = GP.BuildBarTextureControls(ctx, textures, leftW, leftX, topY)
    GP.BuildBarGlossControls(ctx, textures, leftX, rightX, leftW, compactTextures)
    Rows.Schema.Build(ctx, textures, {
        { "font", "gradientLabel", nil, { "GameFontHighlightSmall", "Gradient", T.colors.muted }, scope = "bars",
            anchor = { "TOPLEFT", textures, "TOPLEFT", rightX, gradientY } },
    })
    local SyncGradientControls = M.RefreshProxy()
    local gradientOptions = Rows.Options(function(key, fallback) return GradientScopeGet(key, fallback) end,
        function(key, value) GradientScopeSet(key, value) end,
        function(row)
            ApplyGradientRuntime(row.reason, row.gradientKind)
            SyncGradientControls()
        end)
    local hpY = gradientY - 28
    local powerY = gradientY - 138
    local padX = compactTextures and math.min(rightX + 210, (ctx.width or 720) - 104) or math.min(rightX + 238, (ctx.width or 720) - 104)
    local compactStrengthW = math.max(150, padX - rightX - 14)
    local gradients = Rows.Build(ctx, textures, {
        { "toggle", "enableGradient", false, { "Health gradient", rightX, hpY, compactTextures and 150 or 180 },
            path = "gradient.enableGradient", reason = "MSUF2_HP_GRADIENT", gradientKind = "health",
            tip = "Adds a shade over the filled part of health bars that darkens toward the arrows you pick. The strength slider sets how dark it gets." },
        { "toggle", "enablePowerGradient", false, { "Power gradient", rightX, powerY, compactTextures and 170 or 190 },
            path = "gradient.enablePowerGradient", reason = "MSUF2_POWER_GRADIENT", gradientKind = "power",
            tip = "Adds the same fading shade to power bars, with its own direction arrows and strength." },
    }, gradientOptions)
    local hpGradient, powerGradient = gradients.enableGradient, gradients.enablePowerGradient
    Rows.Schema.Colors(textures, { "gradient.health", "gradient.power" }, {
        title = "Bar Gradient Colors",
        note = "Health and Power gradient colors for the selected Bars scope.",
        historySource = "menu:bars-gradient-colors",
        offsetY = -8,
    })
    local strengthOptions = Rows.Options(GradientScopeGet, GradientScopeSet, ApplyGradientRuntime, nil, true)
    local strengths = Rows.Build(ctx, textures, {
        { "slider", "gradientStrength", 0.45, { "Health strength", 0, 1, 0.05, 220 },
            { rightX, hpY - 36, compactTextures and compactStrengthW or 220, "LEFT" }, path = "gradient.health.strength",
            reason = "MSUF2_HP_GRADIENT_STRENGTH", gradientKind = "health", beforeWrite = FreezePowerGradientScope,
            tip = "How dark the health bar shade gets at its strongest edge. 0 shows no shade, 1 uses the full shade color." },
        { "slider", "powerGradientStrength", 0.45, { "Power strength", 0, 1, 0.05, 220 },
            { rightX, powerY - 36, compactTextures and compactStrengthW or 220, "LEFT" }, path = "gradient.power.strength",
            reason = "MSUF2_POWER_GRADIENT_STRENGTH", gradientKind = "power", legacyKey = "gradientStrength",
            tip = "How dark the power bar shade gets at its strongest edge. 0 shows no shade, 1 uses the full shade color." },
    }, strengthOptions)
    local hpStrength, powerStrength = strengths.gradientStrength, strengths.powerGradientStrength
    local directionButtons, pads = GP.BuildGradientDirectionPads(textures, padX, hpY, powerY, SyncGradientControls)
    local textureControls = { barTexture, bgTexture }
    local gradientControls = { hpGradient, powerGradient }
    -- Hover reasons: a unit or group scope without its own settings locks this
    -- card, and each strength slider and arrow pad waits for its gradient.
    if W.SetControlsDisabledReason and W.TurnOnReason then
        local scopeReason = W.TurnOnReason("Use custom settings for this scope", ScopedControls)
        W.SetControlsDisabledReason(textureControls, function(control)
            if TextureControlsActive() then return nil end
            if GroupScope() then return scopeReason(control) end
            return M.Tr("Textures are shared except Party/Raid group-frame overrides. Gradients can be customized per unit or group scope.")
        end)
        W.SetControlsDisabledReason(gradientControls, scopeReason)
        local hpReason = W.TurnOnReason("Health gradient", function() return GradientScopeGet("enableGradient", false) == true end)
        local powerReason = W.TurnOnReason("Power gradient", function() return GradientScopeGet("enablePowerGradient", false) == true end)
        local function HealthReason(control) return scopeReason(control) or hpReason(control) end
        local function PowerReason(control) return scopeReason(control) or powerReason(control) end
        W.SetControlDisabledReason(hpStrength, HealthReason)
        W.SetControlDisabledReason(powerStrength, PowerReason)
        W.SetControlsDisabledReason(directionButtons.health, HealthReason)
        W.SetControlsDisabledReason(directionButtons.power, PowerReason)
    end
    M.TrackRefresh(ctx, SyncGradientControls(function()
        local hpDirections = CurrentGradientDirectionsForScope("health")
        local powerDirections = CurrentGradientDirectionsForScope("power")
        local textureControlsActive = TextureControlsActive()
        local gradientControlsActive = GradientControlsActive()
        local hpActive = gradientControlsActive and GradientScopeGet("enableGradient", false) == true
        local powerActive = gradientControlsActive and GradientScopeGet("enablePowerGradient", false) == true
        SetControlsEnabled(textureControls, textureControlsActive)
        SetControlsEnabled(gradientControls, gradientControlsActive)
        SetControlEnabled(hpStrength, hpActive)
        SetControlEnabled(powerStrength, powerActive)
        pads.health:SetAlpha(hpActive and 1 or 0.45)
        pads.power:SetAlpha(powerActive and 1 or 0.45)
        for value, btn in pairs(directionButtons.health) do
            btn:SetActive(hpDirections[value] == true)
            SetControlEnabled(btn, hpActive)
        end
        for value, btn in pairs(directionButtons.power) do
            btn:SetActive(powerDirections[value] == true)
            SetControlEnabled(btn, powerActive)
        end
    end))
end

local function BuildTempMaxHealthSection(ctx, b)
    local sectionW = ctx.width or 720
    local compact = sectionW < 700
    local section = Rows.Schema.Section(b:CollapsibleSection("bars_temp_max_health", "Maximum Health Loss", compact and 414 or 274, true), "bars")
    sectionW = section._msuf2Width or sectionW
    local leftX = compact and 20 or 30
    local rightX = compact and 20 or max(390, min(540, floor(sectionW * 0.52)))
    local leftW = compact and max(240, sectionW - 40) or max(280, rightX - leftX - 54)
    local rightW = compact and leftW or max(280, sectionW - rightX - 32)
    local SyncControls = M.RefreshProxy()

    local RefreshTempMaxHealth = MSUF.Require("MSUF_RefreshTempMaxHealth", FILE)
    local RequestPreviewRefresh = MSUF.Require("MSUF_UFPreview_RequestRefresh", FILE)
    local function Refresh(reason)
        local scope = CurrentBarsScope()
        RefreshTempMaxHealth(scope, reason or "MSUF2_TEMP_MAX_HEALTH")
        RequestPreviewRefresh(reason or "MSUF2_TEMP_MAX_HEALTH")
        if type(M.RefreshGFNativePreviews) == "function" then
            M.RefreshGFNativePreviews(reason or "MSUF2_TEMP_MAX_HEALTH")
        end
        SyncControls()
    end

    local bindings = Rows.Options(function(key, fallback, row)
        if row.booleanFallback then return BarScopeGet(key, ReadGBool(key, fallback)) end
        return BarScopeGet(key, ReadG(key, fallback))
    end, function(key, value, row) BarScopeSet(key, value, row.reason, true) end,
        function(row) Refresh(row.reason) end)
    local controls = Rows.Schema.Build(ctx, section, {
        { "text", "tempHealthHint", nil, { "Shows the part of maximum health that is temporarily unavailable.",
            20, -36, sectionW - 40, T.colors.muted }, scope = "bars" },
        { "toggle", "tempMaxHealthEnabled", false, { "Show maximum-health loss", leftX, -78, leftW },
            path = "temp_max_health.enabled", booleanFallback = true, reason = "MSUF2_TEMP_MAX_HEALTH_ENABLED" },
        { "dropdown", "tempMaxHealthTexture", "Solid", { "Texture", function() return TextureValues("Use foreground texture") end, leftW },
            { leftX, -132, leftW, "LEFT" }, path = "temp_max_health.texture", writeDefault = "", reason = "MSUF2_TEMP_MAX_HEALTH_TEXTURE" },
    }, bindings)

    AttachBarsColorShortcut(section,
        "Maximum Health Loss Color",
        "Loss color for the selected Bars scope.",
        "Loss color",
        function()
            return tonumber(BarScopeGet("tempMaxHealthColorR", ReadG("tempMaxHealthColorR", 0.70))) or 0.70,
                tonumber(BarScopeGet("tempMaxHealthColorG", ReadG("tempMaxHealthColorG", 0.10))) or 0.10,
                tonumber(BarScopeGet("tempMaxHealthColorB", ReadG("tempMaxHealthColorB", 0.10))) or 0.10
        end,
        function(r, g, b)
            BarScopeSet("tempMaxHealthColorR", tonumber(r) or 0.70, "MSUF2_TEMP_MAX_HEALTH_COLOR", true)
            BarScopeSet("tempMaxHealthColorG", tonumber(g) or 0.10, "MSUF2_TEMP_MAX_HEALTH_COLOR", true)
            BarScopeSet("tempMaxHealthColorB", tonumber(b) or 0.10, "MSUF2_TEMP_MAX_HEALTH_COLOR", true)
            Refresh("MSUF2_TEMP_MAX_HEALTH_COLOR")
        end,
        "menu:bars-temp-max-health-color",
        function() return CaptureBarsScopeFields(TEMP_MAX_HEALTH_COLOR_STATE_FIELDS) end,
        function(state)
            RestoreBarsScopeFields(state)
            Refresh("MSUF2_TEMP_MAX_HEALTH_COLOR_CANCEL")
        end,
        Meta("temp_max_health.color"))

    Rows.Schema.Build(ctx, section, {
        { "slider", "tempMaxHealthOpacity", 1, { "Overlay opacity", 0.05, 1, 0.05, rightW },
            { rightX, compact and -204 or -78, rightW, "LEFT" }, path = "temp_max_health.opacity", reason = "MSUF2_TEMP_MAX_HEALTH_OPACITY" },
        { "slider", "tempMaxHealthBackgroundOpacity", 0.65, { "Background opacity", 0, 1, 0.05, rightW },
            { rightX, compact and -268 or -142, rightW, "LEFT" }, path = "temp_max_health.background_opacity", reason = "MSUF2_TEMP_MAX_HEALTH_BACKGROUND" },
        { "toggle", "preview", false, { "Preview effect", rightX, compact and -340 or -214, rightW },
            path = "temp_max_health.preview", classification = "ephemeral", get = function() return IsAbsorbTextureTestEnabled("tempMaxHealth") == true end,
            set = function(value) SetAbsorbTextureTest(value and true or false, "tempMaxHealth") end },
    }, bindings, controls)
    local options = { controls.tempMaxHealthTexture, controls.tempMaxHealthOpacity, controls.tempMaxHealthBackgroundOpacity }
    M.TrackRefresh(ctx, SyncControls(function()
        local scopedActive = ScopedControls()
        local on = BarScopeGet("tempMaxHealthEnabled", ReadGBool("tempMaxHealthEnabled", false)) == true
        SetControlEnabled(controls.tempMaxHealthEnabled, scopedActive)
        SetControlsEnabled(options, scopedActive and on)
        SetControlEnabled(controls.preview, true)
    end))
end

function GP.AbsorbControlMeta(parent, path, classification, frames, selectTab)
    local meta = Meta(path, classification)
    local prepare = meta.prepareExactSearchTarget
    local tab = parent == frames.negative and "negative" or parent == frames.heal and "heal" or "positive"
    meta.searchPrepareKind, meta.searchPrepareValue = "barsAbsorbTab", tab
    meta.legacyBarsSettingKey = meta.searchPrepareSettingKey
    meta.searchPrepareSettingKey = nil
    meta.prepareExactSearchTarget = function(widget, target)
        if prepare then
            local scoped = {}
            for key, value in pairs(target) do scoped[key] = value end
            scoped.prepareKind, scoped.prepareValue = "barsScope", "shared"
            if not prepare(widget, scoped) then return false end
        end
        selectTab(tab)
        return true
    end
    return meta
end
function GP.BuildAbsorbTabs(ctx, b)
    local section = Rows.Schema.Section(b:CollapsibleSection("bars_absorb", "Absorb Display", 414, true), "bars")
    local sectionW = section._msuf2Width or ctx.width or 720
    local leftX = 30
    local rightX = max(430, min(560, floor(sectionW * 0.52)))
    local leftW = max(300, min(380, rightX - leftX - 58))
    local rightW = max(300, min(420, sectionW - rightX - 42))
    local tabFrames = {}
    local tabValues = VT(
        "positive", "Absorb (positive)",
        "negative", "Absorb (negative)",
        "heal", "Heal Prediction")
    M.globalBarsAbsorbTabSelection = M.globalBarsAbsorbTabSelection or {}
    local function CurrentTab()
        local key = M.globalBarsAbsorbTabSelection[CurrentBarsScope()] or "positive"
        if key ~= "positive" and key ~= "negative" and key ~= "heal" then key = "positive" end
        return key
    end
    local positive, negative, heal = M.UnitSectionsShared.MakeTabFrames(
        section, -64, sectionW, tabFrames, "positive", "negative", "heal")
    for name, frame in pairs(tabFrames) do
        Rows.Schema.ContextColors(frame, Meta("absorb." .. name .. ".colors", "ephemeral").controlId, "bars")
    end
    Rows.Schema.Colors(positive, { "bar.absorb" }, {
        title = "Absorb Color",
        historySource = "menu:bars-absorb-color",
    })
    Rows.Schema.Colors(negative, { "bar.heal_absorb" }, {
        title = "Heal Absorb Color",
        historySource = "menu:bars-heal-absorb-color",
    })
    Rows.Schema.Colors(heal, { "bar.heal_prediction" }, {
        title = "Heal Prediction Color",
        historySource = "menu:bars-heal-prediction-color",
    })
    local tabs, _, _, SelectAbsorbTab = W.SegmentTabs(ctx, section, {
        label = "", values = tabValues, width = min(660, sectionW - 48),
        frames = tabFrames, defaultTab = "positive", get = CurrentTab,
        set = function(value) M.globalBarsAbsorbTabSelection[CurrentBarsScope()] = value or "positive" end,
        x = 20, y = -12,
    })
    if tabs._msuf2Title then tabs._msuf2Title:Hide() end
    RegisterControl(tabs, Meta("absorb.workspace_tab", "ephemeral"), "Absorb area", "segment")
    Rows.Schema.Owned(tabs, "bars", "sectionNavigation")

    return section, leftX, rightX, leftW, rightW, tabFrames, SelectAbsorbTab, positive, negative, heal
end

function GP.BuildAbsorbControls(ctx, positive, negative, heal, leftX, rightX, leftW, rightW,
    options, TextureDefault, anchorValues, negativeAnchorValues, healAnchorValues, SyncControls)
    local refs = {}
    Rows.Build(ctx, positive, {
        { "toggle", "enableAbsorbBar", true, { "Show positive absorbs", leftX, -10, leftW },
            path = "absorb.positive.enabled", reason = "MSUF2_ABSORB_ENABLED", afterWrite = function(value)
            BarScopeSet("absorbTextMode", value and 2 or 1, "MSUF2_ABSORB_ENABLED", true)
        end,
            tip = "Draws absorb shields on the unit, such as Power Word: Shield, as an overlay on the health bar." },
        { "dropdown", "absorbAnchorMode", 2, { "Anchor", anchorValues, leftW }, { leftX, -64, leftW, "LEFT" },
            path = "absorb.positive.anchor", reason = "MSUF2_ABSORB_ANCHOR", numeric = true },
        { "slider", "absorbBarHeight", 0, { "Bar height (0 = full)", 0, 100, 1, leftW }, { leftX, -118, leftW, "LEFT" },
            path = "absorb.positive.height", reason = "MSUF2_ABSORB_HEIGHT" },
        { "slider", "absorbBarOffsetY", 0, { "Vertical offset", -100, 100, 1, leftW }, { leftX, -182, leftW, "LEFT" },
            path = "absorb.positive.offset_y", reason = "MSUF2_ABSORB_OFFSET" },
        { "dropdown", "absorbBarTexture", TextureDefault("absorbBarTexture"), { "Texture", function() return TextureValues("Use foreground texture") end,
            rightW }, { rightX, -10, rightW, "LEFT" },
            path = "absorb.positive.texture", reason = "MSUF2_ABSORB_TEXTURE" },
        { "slider", "absorbBarOpacity", 0.75, { "Opacity", 0, 1, 0.05, rightW }, { rightX, -64, rightW, "LEFT" },
            path = "absorb.positive.opacity", reason = "MSUF2_ABSORB_OPACITY" },
        { "toggle", "positiveTest", false, { "Test prediction bars", rightX, -128, rightW }, path = "absorb.positive.preview.test",
            classification = "ephemeral",
            get = function() return IsAbsorbTextureTestEnabled("absorb") == true end,
            set = function(value) SetAbsorbTextureTest(value and true or false, "absorb") end,
            tip = "Shows sample bars on the frames of the selected scope, even while this bar " ..
                "is turned off, so you can check its look. Cannot be turned on in combat." },
        { "toggle", "overAbsorbOverlay", false, { "Over-absorb overlay", rightX, -182, rightW },
            path = "absorb.positive.over_absorb", reason = "MSUF2_OVER_ABSORB_OVERLAY",
            tip = "Adds a shield glow at the end of the health bar when absorbs plus incoming heals cover all of the missing health." },
        { "toggle", "fullHealthAbsorbStripe", false, { "Full-health absorb stripe", rightX, -236, rightW },
            path = "absorb.positive.full_health_stripe", reason = "MSUF2_FULL_HEALTH_ABSORB_STRIPE",
            tip = "Shows a shield glow at the end of the health bar while the unit is at full health and still has an absorb shield." },
    }, options, refs)
    Rows.Build(ctx, negative, {
        { "toggle", "healAbsorbEnabled", true, { "Show negative heal absorbs", leftX, -10, leftW },
            path = "absorb.negative.enabled", reason = "MSUF2_HEAL_ABSORB_ENABLED",
            tip = "Shows heal absorbs, effects that soak up incoming healing before health can rise, as a bar over current health." },
        { "dropdown", "healAbsorbAnchorMode", 3, { "Anchor", negativeAnchorValues, leftW }, { leftX, -64, leftW, "LEFT" },
            path = "absorb.negative.anchor", reason = "MSUF2_HEAL_ABSORB_ANCHOR", numeric = true },
        { "slider", "healAbsorbBarHeight", 0, { "Bar height (0 = full)", 0, 100, 1, leftW }, { leftX, -118, leftW, "LEFT" },
            path = "absorb.negative.height", reason = "MSUF2_HEAL_ABSORB_HEIGHT" },
        { "slider", "healAbsorbBarOffsetY", 0, { "Vertical offset", -100, 100, 1, leftW }, { leftX, -182, leftW, "LEFT" },
            path = "absorb.negative.offset_y", reason = "MSUF2_HEAL_ABSORB_OFFSET" },
        { "dropdown", "healAbsorbBarTexture", TextureDefault("healAbsorbBarTexture"), { "Texture",
            function() return TextureValues("Use foreground texture") end, rightW }, { rightX, -10, rightW, "LEFT" },
            path = "absorb.negative.texture", reason = "MSUF2_HEAL_ABSORB_TEXTURE" },
        { "slider", "healAbsorbBarOpacity", 1, { "Opacity", 0, 1, 0.05, rightW }, { rightX, -64, rightW, "LEFT" },
            path = "absorb.negative.opacity", reason = "MSUF2_HEAL_ABSORB_OPACITY" },
        { "toggle", "negativeTest", false, { "Test prediction bars", rightX, -128, rightW }, path = "absorb.negative.preview.test",
            classification = "ephemeral",
            get = function() return IsAbsorbTextureTestEnabled("healAbsorb") == true end,
            set = function(value) SetAbsorbTextureTest(value and true or false, "healAbsorb") end,
            tip = "Shows sample bars on the frames of the selected scope, even while this bar " ..
                "is turned off, so you can check its look. Cannot be turned on in combat." },
    }, options, refs)
    Rows.Build(ctx, heal, {
        { "toggle", "healPredEnabled", ReadGBool("showSelfHealPrediction", false), { "Show heal prediction", leftX, -10, leftW },
            path = "absorb.heal_prediction.enabled", reason = "MSUF2_HEAL_PRED_ENABLED", afterWrite = function(value)
            if SharedScope() then
                G().showSelfHealPrediction = value
            end
        end,
            tip = "Shows incoming heals as a bar on the health bar before they land. Only your own heals count unless Include healing from others is on." },
        { "dropdown", "healPredAnchorMode", 3, { "Anchor", healAnchorValues, leftW }, { leftX, -64, leftW, "LEFT" },
            path = "absorb.heal_prediction.anchor", reason = "MSUF2_HEALPRED_ANCHOR", numeric = true },
        { "slider", "healPredictionBarHeight", 0, { "Bar height (0 = full)", 0, 100, 1, leftW }, { leftX, -118, leftW, "LEFT" },
            path = "absorb.heal_prediction.height", reason = "MSUF2_HEALPRED_HEIGHT" },
        { "slider", "healPredictionBarOffsetY", 0, { "Vertical offset", -100, 100, 1, leftW }, { leftX, -182, leftW, "LEFT" },
            path = "absorb.heal_prediction.offset_y", reason = "MSUF2_HEALPRED_OFFSET" },
        { "dropdown", "healPredictionBarTexture", "", { "Texture", function() return TextureValues("Use foreground texture") end, rightW }, { rightX, -10,
            rightW, "LEFT" },
            path = "absorb.heal_prediction.texture", reason = "MSUF2_HEALPRED_TEXTURE" },
        { "slider", "healPredictionBarOpacity", 0.45, { "Opacity", 0, 1, 0.05, rightW }, { rightX, -64, rightW, "LEFT" },
            path = "absorb.heal_prediction.opacity", reason = "MSUF2_HEALPRED_OPACITY" },
        { "toggle", "healTest", false, { "Test prediction bars", rightX, -128, rightW }, path = "absorb.heal_prediction.preview.test",
            classification = "ephemeral",
            get = function() return IsAbsorbTextureTestEnabled("heal") == true end,
            set = function(value) SetAbsorbTextureTest(value and true or false, "heal") end,
            tip = "Shows sample bars on the frames of the selected scope, even while this bar " ..
                "is turned off, so you can check its look. Cannot be turned on in combat." },
        { "toggle", "healPredAllHealers", false, { "Include healing from others", rightX, -182, rightW },
            path = "absorb.heal_prediction.all_healers", reason = "MSUF2_HEALPRED_ALL_HEALERS",
            tip = "Counts incoming heals from every healer, not only your own. Useful on group frames when several healers are active." },
    }, options, refs)

    local positiveOptions = { refs.absorbAnchorMode, refs.absorbBarHeight, refs.absorbBarOffsetY, refs.absorbBarTexture, refs.absorbBarOpacity,
        refs.overAbsorbOverlay, refs.fullHealthAbsorbStripe }
    local negativeOptions = { refs.healAbsorbAnchorMode, refs.healAbsorbBarHeight, refs.healAbsorbBarOffsetY, refs.healAbsorbBarTexture,
        refs.healAbsorbBarOpacity }
    local healOptions = { refs.healPredAnchorMode, refs.healPredictionBarHeight, refs.healPredictionBarOffsetY, refs.healPredictionBarTexture,
        refs.healPredictionBarOpacity, refs.healPredAllHealers }
    if W.SetControlsDisabledReason and W.TurnOnReason then
        local scopeReason = W.TurnOnReason("Use custom settings for this scope", ScopedControls)
        local function Chain(label, isOn)
            local own = W.TurnOnReason(label, isOn)
            return function(control) return scopeReason(control) or own(control) end
        end
        W.SetControlsDisabledReason({ refs.enableAbsorbBar, refs.healAbsorbEnabled, refs.healPredEnabled }, scopeReason)
        W.SetControlsDisabledReason(positiveOptions, Chain("Show positive absorbs", function() return BarScopeGet("enableAbsorbBar", true) ~= false end))
        W.SetControlsDisabledReason(negativeOptions, Chain("Show negative heal absorbs", function() return BarScopeGet("healAbsorbEnabled", true) ~= false end))
        W.SetControlsDisabledReason(healOptions, Chain("Show heal prediction", function()
            return BarScopeGet("healPredEnabled", ReadGBool("showSelfHealPrediction", false)) == true
        end))
    end
    M.TrackRefresh(ctx, SyncControls(function()
        local scopedActive = ScopedControls()
        SetControlEnabled(refs.enableAbsorbBar, scopedActive)
        SetControlEnabled(refs.healAbsorbEnabled, scopedActive)
        SetControlEnabled(refs.healPredEnabled, scopedActive)
        SetControlsEnabled(positiveOptions, scopedActive and BarScopeGet("enableAbsorbBar", true) ~= false)
        SetControlsEnabled(negativeOptions, scopedActive and BarScopeGet("healAbsorbEnabled", true) ~= false)
        SetControlsEnabled(healOptions, scopedActive and BarScopeGet("healPredEnabled", ReadGBool("showSelfHealPrediction", false)) == true)
        SetControlEnabled(refs.positiveTest, true)
        SetControlEnabled(refs.negativeTest, true)
        SetControlEnabled(refs.healTest, true)
        if refs.absorbAnchorMode.RefreshPreview then refs.absorbAnchorMode:RefreshPreview() end
        if refs.healAbsorbAnchorMode.RefreshPreview then refs.healAbsorbAnchorMode:RefreshPreview() end
        if refs.healPredAnchorMode.RefreshPreview then refs.healPredAnchorMode:RefreshPreview() end
    end))
end

function GP.BuildAbsorbBindings(ctx, tabFrames, SelectAbsorbTab, Apply)
    local options = Rows.Options(BarScopeGet, BarScopeSet, Apply, nil, true)
    options.beforeBind = function(widget, row)
        row.meta = GP.AbsorbControlMeta(widget:GetParent(), row.path, row.classification, tabFrames, SelectAbsorbTab)
    end
    return options
end

local function BuildAbsorbSection(ctx, b)
    local section, leftX, rightX, leftW, rightW, tabFrames, SelectAbsorbTab, positive, negative, heal = GP.BuildAbsorbTabs(ctx, b)

    local SyncControls = M.RefreshProxy()
    local function Apply(reason)
        ApplyBars(reason)
        SyncControls()
    end
    local function TextureDefault(key)
        return function() return ReadG(key, "") end
    end
    local options = GP.BuildAbsorbBindings(ctx, tabFrames, SelectAbsorbTab, Apply)
    local resolve = MSUF.Optional("MSUF_ResolveStatusbarTextureKey")
    local function ResolveBarPreviewTexture(key, fallback)
        key = type(key) == "string" and key ~= "" and key or fallback
        if type(resolve) == "function" then
            local texture = resolve(key)
            if type(texture) == "string" and texture ~= "" then return texture end
        end
        return "Interface\\Buttons\\WHITE8X8"
    end
    local function AnchorPreview(category)
        return function(item)
            local foregroundKey = BarTextureForScope()
            local backgroundKey = BarBackgroundTextureForScope()
            local mode = tonumber(item and item.value) or 3
            local textureKey, opacity, color, showAbsorbEdgeGlow
            if category == "negative" then
                textureKey = BarScopeGet("healAbsorbBarTexture", ReadG("healAbsorbBarTexture", ""))
                opacity = tonumber(BarScopeGet("healAbsorbBarOpacity", ReadG("healAbsorbBarOpacity", 1))) or 1
                color = {
                    tonumber(ReadG("healAbsorbBarColorR", 0.70)) or 0.70,
                    tonumber(ReadG("healAbsorbBarColorG", 0)) or 0,
                    tonumber(ReadG("healAbsorbBarColorB", 0)) or 0,
                    max(0, min(1, opacity)),
                }
            elseif category == "heal" then
                textureKey = BarScopeGet("healPredictionBarTexture", ReadG("healPredictionBarTexture", ""))
                opacity = tonumber(BarScopeGet("healPredictionBarOpacity", ReadG("healPredictionColorA", 0.45))) or 0.45
                color = {
                    tonumber(ReadG("healPredictionColorR", 0)) or 0,
                    tonumber(ReadG("healPredictionColorG", 1)) or 1,
                    tonumber(ReadG("healPredictionColorB", 0)) or 0,
                    max(0, min(1, opacity)),
                }
            else
                textureKey = BarScopeGet("absorbBarTexture", ReadG("absorbBarTexture", ""))
                opacity = tonumber(BarScopeGet("absorbBarOpacity", ReadG("absorbBarOpacity", 0.75))) or 0.75
                color = {
                    tonumber(ReadG("absorbBarColorR", 1)) or 1,
                    tonumber(ReadG("absorbBarColorG", 1)) or 1,
                    tonumber(ReadG("absorbBarColorB", 1)) or 1,
                    max(0, min(1, opacity)),
                }
                showAbsorbEdgeGlow = BarScopeGet("fullHealthAbsorbStripe", ReadGBool("fullHealthAbsorbStripe", false)) == true
            end
            return {
                mode = mode,
                category = category,
                dualDirection = true,
                followInsideHealth = category == "negative",
                showAbsorbEdgeGlow = showAbsorbEdgeGlow,
                healthFraction = mode == 4 and 0.84 or 0.68,
                overlayFraction = category == "negative" and 0.16 or 0.22,
                healthTexture = ResolveBarPreviewTexture(foregroundKey, "Blizzard"),
                backgroundTexture = ResolveBarPreviewTexture(backgroundKey, foregroundKey),
                overlayTexture = ResolveBarPreviewTexture(textureKey, foregroundKey),
                healthColor = { 0.12, 0.62, 0.25, 1 },
                backgroundColor = { 0.025, 0.075, 0.045, 0.92 },
                overlayColor = color,
            }
        end
    end
    -- Negative absorbs have no overflow anchor (choice 4).
    local function AnchorValues(preview, skipOverflow)
        local values = {}
        for _, choice in ipairs({
            { 1, "Anchor to left side" }, { 2, "Anchor to right side" }, { 3, "Follow HP bar" },
            { 4, "Follow HP bar (overflow)" }, { 5, "Reverse from max" },
        }) do
            if not (skipOverflow and choice[1] == 4) then
                values[#values + 1] = { value = choice[1], text = choice[2], previewKind = "barOverlay", barPreview = preview }
            end
        end
        return values
    end
    local anchorValues = AnchorValues(AnchorPreview("positive"))
    local negativeAnchorValues = AnchorValues(AnchorPreview("negative"), true)
    local healAnchorValues = AnchorValues(AnchorPreview("heal"))

    GP.BuildAbsorbControls(ctx, positive, negative, heal, leftX, rightX, leftW, rightW,
        options, TextureDefault, anchorValues, negativeAnchorValues, healAnchorValues, SyncControls)
end

local function BuildOutlineSection(ctx, b)
    local outline = Rows.Schema.Section(b:CollapsibleSection("bars_outline", "Frame Outline", 226, false), "bars")
    local options = Rows.Options(BarScopeGetBars, BarScopeSetBars, RequestOutlineRuntime, nil, true)
    local BorderStyles = MSUF.BorderStyles or MSUF.Require("MSUF_BorderStyles", FILE)
    local function OutlineTextureValues()
        return BorderStyles.FrameList("None (solid color)")
    end
    local controls = Rows.Build(ctx, outline, {
        { "slider", "barOutlineThickness", 1, { "Bar outline thickness", 0, 8, 1, 300 },
            path = "outline.thickness", reason = "MSUF2_BAR_OUTLINE", exact = { step = 1, roundStep = true },
            tip = "Width in pixels of the normal frame outline; 0 hides it. Aggro, dispel and other highlight borders use their own thickness.",
            tipOpts = "plain" },
        { "slider", "barOutlineLayer", 0, { "Frame outline layer (0-30)", 0, 30, 1, 300 },
            path = "outline.layer", reason = "MSUF2_BAR_OUTLINE_LAYER", exact = { step = 1, roundStep = true },
            tip = "Draw order on the shared 0-30 layer scale. Raise it to draw the outline above text, icons or auras on a lower layer.", tipOpts = "plain" },
        { "dropdown", "texture", "", { "Outline style", OutlineTextureValues, 300 }, path = "outline.texture",
            get = function() return BorderStyles.NormalizeFrame(BarScopeGetBars("barOutlineTexture", "")) end,
        set = function(value)
            BarScopeSetBars("barOutlineTexture", value or "", "MSUF2_BAR_OUTLINE_TEXTURE", true)
            RequestOutlineRuntime()
        end },
    }, options)
    local outlineSlider, outlineLayer, outlineTexture = controls.barOutlineThickness, controls.barOutlineLayer, controls.texture
    AttachBarsColorShortcut(outline,
        "Frame Outline Color",
        "Outline color for the selected Bars scope.",
        "Outline color",
        function()
            return tonumber(BarScopeGet("barOutlineColorR", ReadG("barOutlineColorR", 0))) or 0,
                tonumber(BarScopeGet("barOutlineColorG", ReadG("barOutlineColorG", 0))) or 0,
                tonumber(BarScopeGet("barOutlineColorB", ReadG("barOutlineColorB", 0))) or 0
        end,
        function(r, g, b)
            if SetOutlineColorForScope(r, g, b) then
                RequestOutlineRuntime()
            end
        end,
        "menu:bars-outline-color",
        function() return CaptureBarsScopeFields(OUTLINE_COLOR_STATE_FIELDS) end,
        function(state)
            RestoreBarsScopeFields(state)
            RequestOutlineRuntime()
        end,
        Meta("outline.color"))
    local turnOn = W.TurnOnReason
    local scopeReason = turnOn and turnOn("Use custom settings for this scope", ScopedControls)
    -- Rounded and slanted frames draw the selected style along their shape.
    M.BindGateGroup(ctx, nil, {
        { controls = { outlineSlider, outlineLayer, outlineTexture }, on = ScopedControls, reason = scopeReason },
    })
end

local function BuildRoundedSection(ctx, b)
    local rounded = Rows.Schema.Section(b:CollapsibleSection("bars_rounded", "Rounded Texture", ROUNDED_SECTION_HEIGHT, true), "bars")
    local roundLeftX = 30
    local roundRightX = 330
    local roundW = 250
    RegisterRoundedSearch(rounded, "Rounded Texture",
        "rounded section|rounded menu|rounded options|where rounded frames|wo rounded frames",
        "Open this section to enable or disable rounded frame textures and its per-surface toggles.", "section")
    local SyncRoundedControls = M.RefreshProxy()
    local options = Rows.Options(ReadB,
        function(key, value, row) SetRoundedBool(key, value, row.reload) end, SyncRoundedControls)
    options.register = function(_, control, row)
        RegisterRoundedSearch(control, row[4][1], row.search[1], row.search[2], nil, Meta(row.path))
    end
    local roundedControls = Rows.Schema.Build(ctx, rounded, {
        { "switch", "roundedFramesEnabled", false, { "Rounded frame texture", roundLeftX, -52, roundW },
            path = "rounded.roundedFramesEnabled", defaultOn = true, reload = true, register = true,
            search = { "master toggle|all rounded frames|rounded frames master|rounded frames on|rounded frames off|rounded frames einschalten|rounded " ..
                "frames ausschalten|alle abgerundeten frames",
                "Master switch for the rounded frame texture style." } },
        { "toggle", "roundedUnitFrames", true, { "Unit frames", roundLeftX, -90, roundW },
            path = "rounded.roundedUnitFrames", defaultOn = true, register = true,
            search = { "rounded unit frames|rounded unitframes|unit frame corners|unitframe corners|abgerundete unitframes|unitframes " ..
                "abgerundet|player target focus boss rounded",
                "Enable or disable rounded textures on unit frames." } },
        { "toggle", "roundedGroupFrames", true, { "Group frames", roundLeftX, -128, roundW },
            path = "rounded.roundedGroupFrames", defaultOn = true, register = true,
            search = { "rounded group frames|rounded party frames|rounded raid frames|group frame corners|abgerundete gruppenframes|party raid abgerundet",
                "Enable or disable rounded textures on group frames." } },
        { "toggle", "roundedClassResources", false, { "Class resources", roundLeftX, -166, roundW },
            path = "rounded.roundedClassResources", defaultOn = true, register = true,
            search = { "rounded class resources|rounded combo points|rounded soul shards|class resource bar corners|klassenressourcen abgerundet|combo " ..
                "punkte abrunden|seelensplitter abrunden",
                "Round rectangular class resource bars. Circle, Diamond, and Hex shapes are unchanged." } },
        { "toggle", "roundedPowerBars", true, { "Power bars", roundRightX, -52, roundW },
            path = "rounded.roundedPowerBars", defaultOn = true, register = true,
            search = { "rounded power bars|rounded powerbar|power bar corners|powerbar corners|powerbars abgerundet|powerbar abrunden",
                "Enable or disable rounded textures on power bars." } },
        { "toggle", "roundedMouseover", true, { "Mouseover highlights", roundRightX, -90, roundW },
            path = "rounded.roundedMouseover", defaultOn = true, register = true,
            search = { "rounded mouseover|rounded hover|rounded hover border|mouseover " ..
                "rounded|mouseover highlight rounded|mouseover abgerundet|hover abgerundet",
                "Enable or disable rounded mouseover highlight edges." } },
        { "toggle", "roundedCastbars", false, { "Castbars", roundRightX, -128, roundW },
            path = "rounded.roundedCastbars", defaultOn = true, register = true,
            search = { "rounded castbars|castbar corners|cast bars rounded|castbars abgerundet|zauberbalken abgerundet",
                "Round MSUF castbar surfaces and outlines. Blizzard castbars, spell icons, and the GCD bar are not changed." } },
    }, options)
    local roundedPreview
    local roundingSlider
    local roundingApplyPending, roundingApplyTimer, roundingReleaseScheduled
    local function CancelRoundingApplyTimer()
        if roundingApplyTimer and type(roundingApplyTimer.Cancel) == "function" then roundingApplyTimer:Cancel() end
        roundingApplyTimer = nil
    end
    local function FlushRoundingRuntime()
        if not roundingApplyPending then
            roundingReleaseScheduled = nil
            CancelRoundingApplyTimer()
            return
        end
        if M.IsConfigCombatLocked and M.IsConfigCombatLocked(true) then
            roundingReleaseScheduled = nil
            CancelRoundingApplyTimer()
            return false
        end
        roundingApplyPending = nil
        roundingReleaseScheduled = nil
        CancelRoundingApplyTimer()
        ApplyRoundedRuntime()
        return true
    end
    local function ScheduleRoundingRelease()
        if not roundingApplyPending or roundingReleaseScheduled then return end
        roundingReleaseScheduled = true
        CancelRoundingApplyTimer()
        if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0, FlushRoundingRuntime)
        else FlushRoundingRuntime() end
    end
    local function QueueRoundingRuntime()
        roundingApplyPending = true
        if roundedPreview and roundedPreview.RefreshRoundedPreview then roundedPreview:RefreshRoundedPreview() end
        if roundingSlider._msuf2SliderActive == true then
            roundingReleaseScheduled = nil
            CancelRoundingApplyTimer()
            return
        end
        if roundingReleaseScheduled then return end
        CancelRoundingApplyTimer()
        if C_Timer and type(C_Timer.NewTimer) == "function" then
            roundingApplyTimer = C_Timer.NewTimer(ROUNDED_STRENGTH_APPLY_DELAY, FlushRoundingRuntime)
        else
            FlushRoundingRuntime()
        end
    end
    roundingSlider = Rows.Schema.Build(ctx, rounded, {
        { "slider", "rounding", 3, { "Corner rounding", 1, 5, 1, 300 },
            { roundRightX, -166, 300, "LEFT" }, path = "rounded.roundedCornerStrength", exact = { step = 1, roundStep = true },
            get = function() return tonumber(Bars().roundedCornerStrength) or 3 end,
        set = function(value)
            value = floor((tonumber(value) or 3) + 0.5)
            if value < 1 then value = 1 elseif value > 5 then value = 5 end
            local bars = Bars()
            if bars.roundedCornerStrength == value then return end
            bars.roundedCornerStrength = value
            QueueRoundingRuntime()
        end },
    }, Rows.Commands).rounding
    roundingSlider:HookScript("OnMouseUp", ScheduleRoundingRelease)
    roundingSlider:HookScript("OnHide", FlushRoundingRuntime)
    roundingSlider:HookScript("OnShow", FlushRoundingRuntime)
    RegisterRoundedSearch(roundingSlider, "Corner rounding",
        "corner rounding|rounding strength|rounded strength|corner radius|rounding radius|abrundungsstaerke|eckenradius|staerke der abrundung",
        "Controls how subtle or strong the rounded corners appear. Masks, outlines, highlights, mouseover edges, power bars, enabled class resources, " ..
            "and enabled castbars use the same value.",
        "slider", Meta("rounded.roundedCornerStrength", "setting", { step = 1, min = 1, max = 5 }))
    roundedPreview = CreateRoundedTexturePreview(rounded, roundLeftX, -214, max(320, (rounded._msuf2Width or ctx.width or 720) - 60))
    RegisterRoundedSearch(roundedPreview, "Rounded Texture Preview",
        "rounded preview|rounded example|rounded image|rounded frame preview|preview rounded frames|rounded frames aussehen|vorschau abgerundete frames",
        "Shows a small preview of the rounded frame texture style.", "preview")
    Rows.Schema.Custom(roundedPreview, { id = Meta("rounded.preview", "ephemeral").controlId, kind = "preview",
        labelKey = "Rounded Texture Preview", meta = roundedPreview._msuf2SearchMeta,
        scope = "bars", applyDomain = "preview", owner = roundedPreview, refresh = roundedPreview.RefreshRoundedPreview })
    local roundedDependentControls = { roundedControls.roundedUnitFrames, roundedControls.roundedGroupFrames, roundedControls.roundedClassResources,
        roundedControls.roundedPowerBars,
        roundedControls.roundedMouseover, roundedControls.roundedCastbars, roundingSlider }
    SyncRoundedControls(M.BindGateGroup(ctx, nil, {
        { controls = roundedDependentControls, on = function() return ReadB("roundedFramesEnabled", false) == true end,
            reason = W.TurnOnReason and W.TurnOnReason("Rounded frame texture") },
    }, {
        also = function() if roundedPreview and roundedPreview.RefreshRoundedPreview then roundedPreview:RefreshRoundedPreview() end end,
    }))
end

local function SlantedStylesSelected(keys)
    local db = DB()
    local function InScope(scope)
        for _, key in ipairs(scope) do
            if db[key] and db[key].frameBarShape == "SLANTED" then return true end
        end
        return false
    end
    if keys then return InScope(keys) end
    return InScope(SLANTED_PRESET_UNITS) or InScope(SLANTED_PRESET_GROUPS)
end

local function SlantedSwitchOn()
    local saved = Bars().slantedBarsEnabled
    if saved ~= nil then return saved == true end
    return SlantedStylesSelected()
end

local function CreateSlantedBarPreview(section, width)
    local card = W.ControlCard(section, "Slanted bar preview", nil, 30, -300, width - 60, 92)
    if not card then return end
    local surface = ShapePreviewSurface(card, min(440, max(240, width - 110)), 43)
    function card:RefreshSlantedPreview() surface:Refresh() end
    card:RefreshSlantedPreview()
    return card
end

local function SlantedDirectionForScope()
    local keys = ScopeDBKeys(CurrentBarsScope())
    local value = keys and DB()[keys[1]] and DB()[keys[1]].slantedBarDirection
        or (not keys and Bars().slantedBarDirection)
    for i = 1, #SLANTED_DIRECTION_VALUES do
        if SLANTED_DIRECTION_VALUES[i].value == value then return value end
    end
    return keys and "DEFAULT" or "RIGHT_DOWN"
end
local function SetSlantedDirectionForScope(value)
    local keys = ScopeDBKeys(CurrentBarsScope())
    local allowed = keys and value == "DEFAULT"
    for i = 1, #SLANTED_DIRECTION_VALUES do
        if SLANTED_DIRECTION_VALUES[i].value == value then
            allowed = true
            break
        end
    end
    if not allowed then return false end
    if value == "DEFAULT" then value = nil end
    if not keys then
        if Bars().slantedBarDirection == value then return false end
        Bars().slantedBarDirection = value
        return true
    end
    local db, changed = DB(), false
    for i = 1, #keys do
        local entry = db[keys[i]]
        if not entry and value ~= nil then
            entry = {}
            db[keys[i]] = entry
        end
        if entry and entry.slantedBarDirection ~= value then
            entry.slantedBarDirection, changed = value, true
        end
    end
    return changed
end
local function BuildSlantedSection(ctx, b)
    local section = Rows.Schema.Section(b:CollapsibleSection("bars_slanted", "Slanted Bars", 480, true), "bars")
    local width = (section and section._msuf2Width) or b.width or 720
    local SyncSlantedControls = M.RefreshProxy()
    local function Search(control, label, kind, keywords, help)
        if type(M.RegisterSearchWidget) == "function" then
            M.RegisterSearchWidget(control, { label = label, kind = kind, keywords = keywords, help = help })
        end
    end
    local function ApplySlantedToScope(keys)
        local db, changed = DB(), false
        for _, key in ipairs(keys) do
            db[key] = db[key] or {}
            if db[key].frameBarShape ~= "SLANTED" then db[key].frameBarShape, changed = "SLANTED", true end
        end
        return changed
    end
    local function ApplySlantedToAll()
        local units = ApplySlantedToScope(SLANTED_PRESET_UNITS)
        return ApplySlantedToScope(SLANTED_PRESET_GROUPS) or units
    end
    local ApplyRoundedUnitframes = MSUF.Require("MSUF_ApplyRoundedUnitframes", FILE)
    local function RefreshSlanted(reason)
        ApplyRoundedUnitframes()
        SyncSlantedControls()
        if M.RequestRefresh then M.RequestRefresh(ctx, reason) end
    end
    Rows.Schema.Build(ctx, section, {
        { "text", "slantedHint", nil, { "Choose where slanted edges appear. Turning this off keeps your frame choices.",
            30, -40, width - 60, T.colors.muted }, scope = "bars" },
    })
    local preview = CreateSlantedBarPreview(section, width)
    if preview and type(M.RegisterSearchWidget) == "function" then
        M.RegisterSearchWidget(preview, {
            label = "Slanted bar preview", kind = "preview",
            keywords = { "slanted", "angled", "preview", "vorschau", "schraege" },
            help = "Shows the selected cut on a Health and Power bar sample.",
        })
        Rows.Schema.Custom(preview, { id = Meta("slanted.preview", "ephemeral").controlId, kind = "preview",
            labelKey = "Slanted bar preview", meta = preview._msuf2SearchMeta,
            scope = "bars", applyDomain = "preview", owner = preview, refresh = preview.RefreshSlantedPreview })
    end
    local enabled = Rows.Schema.Build(ctx, section, {
        -- Turning it on restyles every unit and group frame: whole-profile undo.
        { "switch", "enabled", false, { "Enable slanted bars", 30, -78, min(340, width - 60) },
            path = "slanted.enabled", exact = { historyScope = false }, get = SlantedSwitchOn,
            set = function(value)
            value = value == true
            local bars = Bars()
            local switchStyle = value and bars.roundedFramesEnabled == true
            if bars.slantedBarsEnabled == value and not switchStyle then return end
            bars.slantedBarsEnabled = value
            if switchStyle then bars.roundedFramesEnabled = false end
            if value and not SlantedStylesSelected() then ApplySlantedToAll() end
            RefreshSlanted("slanted-bar-enabled")
        end },
    }, Rows.Commands).enabled
    Search(enabled, "Enable slanted bars", "toggle",
        { "slanted", "enable", "disable", "on", "off", "schraege", "einschalten", "ausschalten" },
        "Choose where slanted edges appear. Turning this off keeps your frame choices.")
    local options = Rows.Options(ReadB, function(key, value) Bars()[key] = value end,
        function(row, value)
            if value and row.presetKeys and not SlantedStylesSelected(row.presetKeys) then ApplySlantedToScope(row.presetKeys) end
            RefreshSlanted("slanted-" .. row.id)
        end, function(key) return Bars()[key] end)
    options.register = function(_, control, row)
        Search(control, row[4][1], "toggle", { "slanted", "angled", row.id, "schraege", "ein", "aus" })
    end
    local controls = Rows.Schema.Build(ctx, section, {
        { "toggle", "slantedUnitFrames", true, { "Unit frames", 30, -116, 250 },
            path = "slanted.units", id = "units", defaultOn = true, skipEqual = true, register = true, presetKeys = SLANTED_PRESET_UNITS },
        { "toggle", "slantedGroupFrames", true, { "Group frames", 30, -154, 250 },
            path = "slanted.groups", id = "groups", defaultOn = true, skipEqual = true, register = true, presetKeys = SLANTED_PRESET_GROUPS },
        { "toggle", "slantedClassResources", false, { "Class resources", 30, -192, 250 },
            path = "slanted.class_resources", id = "class_resources", defaultOn = true, skipEqual = true, register = true },
        { "toggle", "slantedPowerBars", true, { "Power bars", 330, -78, 250 },
            path = "slanted.power", id = "power", defaultOn = true, skipEqual = true, register = true },
        { "toggle", "slantedMouseover", true, { "Mouseover highlights", 330, -116, 250 },
            path = "slanted.mouseover", id = "mouseover", defaultOn = true, skipEqual = true, register = true },
        { "toggle", "slantedCastbars", false, { "Castbars", 330, -154, 250 },
            path = "slanted.castbars", id = "castbars", defaultOn = true, skipEqual = true, register = true },
        { "dropdown", "direction", nil, { "Cut direction", function()
            return CurrentBarsScope() == "shared" and SLANTED_DIRECTION_VALUES or SLANTED_SCOPED_DIRECTION_VALUES
        end, min(340, width - 60) }, { 30, -248, min(340, width - 60), "LEFT" },
            path = "slanted.direction", get = SlantedDirectionForScope,
            set = function(value)
            if not SetSlantedDirectionForScope(value) then return end
            if preview and preview.RefreshSlantedPreview then preview:RefreshSlantedPreview() end
            ApplyRoundedRuntime()
            if M.RequestRefresh then M.RequestRefresh(ctx, "slanted-bar-direction") end
        end },
    }, options)
    local dependent = { controls.slantedUnitFrames, controls.slantedGroupFrames, controls.slantedClassResources,
        controls.slantedPowerBars, controls.slantedMouseover, controls.slantedCastbars }
    local direction = controls.direction
    Search(direction, "Cut direction", "dropdown", { "slanted", "diagonal", "left", "right", "both", "schraege", "richtung" },
        "Choose the cut direction for the selected scope. Use shared style follows the shared direction.")
    local preset = W.Button(section, "Apply slanted bars to all frames", 280)
    W.MoveWidget(preset, section, 30, -420)
    preset:SetScript("OnClick", function()
        local function Write()
            local bars = Bars()
            local changed = ApplySlantedToAll()
            if bars.slantedBarsEnabled ~= true then bars.slantedBarsEnabled, changed = true, true end
            if bars.slantedUnitFrames ~= true then bars.slantedUnitFrames, changed = true, true end
            if bars.slantedGroupFrames ~= true then bars.slantedGroupFrames, changed = true, true end
            if not changed then return false end
            RefreshSlanted("slanted-bar-preset")
            return true
        end
        if type(M.RunWithHistory) == "function" then
            M.RunWithHistory("Apply slanted bars to all frames", "bars:slanted-preset", Write)
        else
            Write()
        end
    end)
    RegisterControl(preset, Meta("slanted.apply_preset", "action"), "Apply slanted bars to all frames", "button")
    local presetDeclaration = Rows.Schema.Owned(preset, "bars", "bars")._msuf2ControlSchema
    presetDeclaration.setting = Rows.Schema.Record({ "bars.slantedBarsEnabled", "bars.slantedUnitFrames", "bars.slantedGroupFrames",
        "{unit}.frameBarShape", "gf_{scope}.frameBarShape" })
    Search(preset, "Apply slanted bars to all frames", "button",
        { "slanted bars", "slanted preset", "angled health bar", "schraege leiste", "schraege balken" },
        "Cuts the Health and Power bar edges. Choose frames in Basics or apply this shape everywhere.")
    dependent[#dependent + 1] = direction
    SyncSlantedControls(M.BindGateGroup(ctx, nil, {
        { controls = dependent, on = SlantedSwitchOn, reason = W.TurnOnReason and W.TurnOnReason("Enable slanted bars") },
    }, {
        also = function() if preview and preview.RefreshSlantedPreview then preview:RefreshSlantedPreview() end end,
    }))
end

-- Upgrade-tour playground for the 5.x highlight card. The rounded rework is the
-- one 6.0 change that has to be felt rather than read, so the tour hosts the
-- real controls; reading, writing, applying and the master gate all stay here.
local ROUNDED_TOUR_STRENGTHS = {}
for i = 1, 5 do ROUNDED_TOUR_STRENGTHS[i] = { value = i, text = tostring(i) } end

local function RoundedTourGet(key, defaultOn)
    return function()
        local value = ReadB(key, defaultOn)
        if defaultOn then return value ~= false end
        return value == true
    end
end

local function RoundedTourSet(key, requireReload)
    return function(value) SetRoundedBool(key, value, requireReload) end
end

local function SetRoundedTourStrength(value)
    value = floor((tonumber(value) or 3) + 0.5)
    if value < 1 then value = 1 elseif value > 5 then value = 5 end
    local bars = Bars()
    if bars.roundedCornerStrength == value then return end
    bars.roundedCornerStrength = value
    -- A segment commits once per click, so the page slider's drag debounce
    -- (ROUNDED_STRENGTH_APPLY_DELAY) has nothing to smooth out here.
    ApplyRoundedRuntime()
end

if type(M.RegisterUpgradeTourControls) == "function" then
    M.RegisterUpgradeTourControls("rounded_frames", {
        -- Grid height only; the tour adds its own "try it here" label above.
        -- Two columns: 48 (toggle + segment row) + 36 + 36, each plus the 6px
        -- row gap W.SettingsRows uses.
        columns = 2,
        height = 126,
        rows = function()
            return {
                { id = "master", kind = "toggle", label = "Rounded frame texture",
                    get = RoundedTourGet("roundedFramesEnabled", false),
                    set = RoundedTourSet("roundedFramesEnabled", true) },
                { id = "strength", kind = "segment", label = "Corner rounding",
                    values = ROUNDED_TOUR_STRENGTHS,
                    get = function() return floor(tonumber(Bars().roundedCornerStrength) or 3) end,
                    set = SetRoundedTourStrength },
                { id = "units", kind = "toggle", label = "Unit frames",
                    get = RoundedTourGet("roundedUnitFrames", true), set = RoundedTourSet("roundedUnitFrames") },
                { id = "groups", kind = "toggle", label = "Group frames",
                    get = RoundedTourGet("roundedGroupFrames", true), set = RoundedTourSet("roundedGroupFrames") },
                { id = "power", kind = "toggle", label = "Power bars",
                    get = RoundedTourGet("roundedPowerBars", true), set = RoundedTourSet("roundedPowerBars") },
                { id = "mouseover", kind = "toggle", label = "Mouseover highlights",
                    get = RoundedTourGet("roundedMouseover", true), set = RoundedTourSet("roundedMouseover") },
            }
        end,
        after = function(ctx, result)
            local controls = result and result.controls
            if type(controls) ~= "table" then return end
            local refresh = M.BindGateGroup(ctx, nil, {
                {
                    controls = { controls.strength, controls.units, controls.groups,
                        controls.power, controls.mouseover },
                    on = function() return ReadB("roundedFramesEnabled", false) == true end,
                },
            })
            if type(refresh) == "function" then refresh() end
        end,
    })
end

function GP.BuildHighlightModes(ctx, modesFrame, hlLeftX, hlLeftW)
    local borderModes = VT(0, "Off", 1, "On")
    local function BorderModeSet(key, fallback, reason, kind, apply, onEnabled, onChanged)
        return function(v)
            local value = tonumber(v) or fallback
            local previous = tonumber(BarScopeGet(key, fallback)) or fallback
            BarScopeSet(key, value, reason, true)
            if value == 1 and onEnabled then onEnabled() end
            Rows.testModes[kind].stop(value == 1)
            apply()
            if value ~= previous and onChanged then onChanged() end
        end
    end
    local function DispelShowOn(value)
        return (value == "FRIENDLY" or value == "ENEMY") and value or "BOTH"
    end
    local options = Rows.Options(BarScopeGet,
        function(key, value, row) BarScopeSet(key, value, row.reason, true) end,
        function(row) row.apply() end)
    local aggroModeValues = VT("ALL", "All roles", "NON_TANK", "Non-tanks", "HEALER", "Healers only", "TANK", "Tanks only")
    local controls = Rows.Build(ctx, modesFrame, {
        { "slider", "highlightBorderThickness", 2, { "Highlight border thickness", 1, 30, 1, hlLeftW },
            { hlLeftX, -70, hlLeftW, "LEFT" }, path = "highlight.border_thickness", exact = { step = 1, roundStep = true },
            get = function() return tonumber(BarScopeGet("highlightBorderThickness", BarScopeGet("hlAggroSize", 2))) or 2 end,
            set = function(v)
            local n = floor((tonumber(v) or 2) + 0.5)
            BarScopeSet("highlightBorderThickness", n, "MSUF2_HIGHLIGHT_BORDER", true)
            BarScopeSet("hlAggroSize", n, "MSUF2_HIGHLIGHT_BORDER", true)
            RequestAllHighlightBorderRuntime()
        end },
        { "dropdown", "aggroOutlineMode", 1, { "Aggro border", borderModes, hlLeftW }, { hlLeftX, -136, hlLeftW, "LEFT" },
            path = "highlight.border_mode.aggroOutlineMode", numeric = true, set = BorderModeSet("aggroOutlineMode", 1,
                "MSUF2_AGGRO_BORDER", "aggro", RequestAggroBorderRuntime),
            tip = "Shows the aggro color on the border when the unit has threat: your frame while " ..
                "you hold aggro, enemies attacking you, and group members with high threat.", tipOpts = "plain" },
        { "dropdown", "aggroMode", "ALL", { "Group threat visuals show for", aggroModeValues, hlLeftW }, { hlLeftX, -190, hlLeftW, "LEFT" },
            path = "highlight.aggro.roles", readValue = NormalizeAggroMode, writeValue = NormalizeAggroMode,
            reason = "MSUF2_AGGRO_MODE", apply = RequestGroupAggroRoleRuntime },
        { "dropdown", "dispelOutlineMode", 1, { "Dispel border", borderModes, hlLeftW }, { hlLeftX, -244, hlLeftW, "LEFT" },
            path = "highlight.border_mode.dispelOutlineMode", numeric = true, set = BorderModeSet("dispelOutlineMode", 1,
                "MSUF2_DISPEL_BORDER", "dispel", RequestDispelPurgeBorderRuntime,
                EnsureUnitFrameAuraSensorsForScope, ShowDispelBorderReloadRequiredPopup),
            tip = "Colors the border by debuff type while the unit has a debuff that Dispel border detects. Changing it asks for a UI reload.",
            tipOpts = "plain" },
        { "dropdown", "dispelBorderTrigger", "DISPEL_TYPE", { "Dispel border detects", DISPEL_TRIGGERS, hlLeftW },
            { hlLeftX, -298, hlLeftW, "LEFT" }, path = "highlight.dispel.trigger", readValue = NormalizeDispelTrigger,
            set = function(v)
            local value = NormalizeDispelTrigger(v)
            local previous = NormalizeDispelTrigger(BarScopeGet("dispelBorderTrigger", "DISPEL_TYPE"))
            BarScopeSet("dispelBorderTrigger", value, "MSUF2_DISPEL_TRIGGER", true)
            RequestDispelPurgeBorderRuntime()
            if value ~= previous then ShowDispelBorderReloadRequiredPopup() end
        end },
        { "dropdown", "dispelBorderShowOn", "BOTH", { "Show on", DISPEL_SHOW_ON, hlLeftW }, { hlLeftX, -352, hlLeftW, "LEFT" },
            path = "highlight.dispel.show_on", readValue = DispelShowOn, writeValue = DispelShowOn,
            reason = "MSUF2_DISPEL_BORDER", apply = RequestDispelPurgeBorderRuntime },
        { "dropdown", "purgeOutlineMode", 0, { "Purge border", borderModes, hlLeftW }, { hlLeftX, -406, hlLeftW, "LEFT" },
            path = "highlight.border_mode.purgeOutlineMode", numeric = true, set = BorderModeSet("purgeOutlineMode", 0,
                "MSUF2_PURGE_BORDER", "purge", RequestDispelPurgeBorderRuntime),
            tip = "Colors the border while the unit has a buff you can purge or spellsteal. Only Target and Focus frames support it.", tipOpts = "plain" },
    }, options)
    local bossSupported = not M.SupportsUnitPage or M.SupportsUnitPage("uf_boss")
    local bossTarget = bossSupported and Rows.Build(ctx, modesFrame, {
        { "dropdown", "boss", 1, { "Boss target border", borderModes, hlLeftW }, { hlLeftX, -460, hlLeftW, "LEFT" },
            path = "highlight.boss_target.mode", get = function()
            local fallback = ReadGBool("bossTargetHighlightEnabled", true) and 1 or 0
            return tonumber(ReadG("bossTargetOutlineMode", fallback)) or fallback
        end,
        set = function(v)
            local value = tonumber(v) or 1
            local general = G()
            general.bossTargetOutlineMode = value
            general.bossTargetHighlightEnabled = value == 1
            Rows.testModes.bossTarget.stop(value == 1)
            RequestBossTargetBorderRuntime()
        end,
            tip = "Highlights the Boss frame of the boss you are targeting. It is shared by all boss frames, so it changes only on the Shared scope.",
            tipOpts = "plain" },
    }, Rows.Commands).boss
    local bossSharedHint = bossSupported and Rows.Schema.Build(ctx, modesFrame, {
        { "text", "bossHint", nil, { "Boss target border is a shared boss-frame setting.", hlLeftX, -540, hlLeftW, T.colors.dim }, scope = "bars" },
    }).bossHint
    if bossSharedHint and bossSharedHint.SetWordWrap then bossSharedHint:SetWordWrap(true) end
    local unitAuraDispelHint = Rows.Schema.Build(ctx, modesFrame, {
        { "text", "auraHint", nil, { UNITFRAME_DISPEL_AURA_WARNING, hlLeftX, -570, hlLeftW, UNITFRAME_DISPEL_AURA_WARNING_COLOR }, scope = "bars" },
    }).auraHint
    if unitAuraDispelHint.SetWordWrap then unitAuraDispelHint:SetWordWrap(true) end
    return controls.highlightBorderThickness, controls.aggroOutlineMode, controls.aggroMode, controls.dispelOutlineMode,
        controls.dispelBorderTrigger, controls.dispelBorderShowOn, controls.purgeOutlineMode, bossSupported,
        bossTarget, bossSharedHint, unitAuraDispelHint
end

function GP.BuildHighlightPriority(ctx, priorityCard, priorityCardW, HighlightPriorityEnabled)
    local RefreshPriorityRows
    local prio = Rows.Build(ctx, priorityCard, {
        { "switch", "priority", false, { "Custom highlight priority", 16, -54, priorityCardW - 32 },
            path = "highlight.priority.enabled", get = HighlightPriorityEnabled,
            set = function(v)
            local on = v and true or false
            BarScopeSet("hlPrioEnabled", on, "MSUF2_HIGHLIGHT_PRIORITY", true)
            if CurrentBarsScope() == "shared" then
                G().hlPrioEnabled = on and 1 or 0
                G().highlightPrioEnabled = on and 1 or 0
            end
            RequestHighlightPriorityRuntime()
            if RefreshPriorityRows then RefreshPriorityRows() end
        end,
            tip = "When several highlight borders show at once, the highest one in the list wins. Turn this on to reorder the list by dragging.",
            tipOpts = "plain" },
    }, Rows.Commands).priority
    local rowMax = 4
    local prioContainer, prioRows, prioCount
    local function SavePriorityRows()
        local function WritePriorityRows()
            local sorted = {}
            for i = 1, prioCount do sorted[i] = prioRows[i] end
            table.sort(sorted, function(a, b) return a.slotIndex < b.slotIndex end)
            local order = {}
            for i = 1, prioCount do order[i] = sorted[i].key end
            BarScopeSet("hlPrioOrder", order, "MSUF2_HIGHLIGHT_PRIORITY_ORDER", true)
            if CurrentBarsScope() == "shared" then
                G().hlPrioOrder = order
                G().highlightPrioOrder = order
            end
            RequestHighlightPriorityRuntime()
        end
        M.RunWithHistory("Highlight Priority Order", "global:highlightPriorityOrder", WritePriorityRows)
    end
    local function SetPriorityRowsEnabled(enabled)
        prioContainer:SetRowsEnabled(enabled)
    end
    prioContainer = RegisterDragRows(M.UnitSectionsShared.MakeDragSortRows(priorityCard, nil, {
        x = 16, y = -82, width = min(220, priorityCardW - 32), rowHeight = 22, gap = 4, maxRows = rowMax,
        bg = { 0.12, 0.12, 0.12, 0.85 },
        border = { 0.30, 0.30, 0.30, 0.60 },
        disabledAlpha = 0.4,
        dragAllowed = function() return HighlightControls() and HighlightPriorityEnabled() end,
        onReorder = SavePriorityRows,
    }), "highlight.priority.order")
    prioRows = prioContainer.rows
    RefreshPriorityRows = function()
        SetControlEnabled(prio, HighlightControls())
        local order = PriorityOrder()
        prioCount = math.min(#order, rowMax)
        for i = 1, prioCount do
            local key = order[i]
            local r, g, bcol = PriorityColor(key)
            local row = prioRows[i]
            row.key = key
            row.slotIndex = i
            row.frame._stripe:SetColorTexture(r, g, bcol, 1)
            row.frame._label:SetText(PRIORITY_LABELS[key] or key)
            row.frame._numText:SetText(tostring(i))
        end
        prioContainer:SetActiveCount(prioCount)
        SetPriorityRowsEnabled(HighlightControls() and HighlightPriorityEnabled())
    end
    if ctx.entry then ctx.entry.refreshHighlightPriorityColors = RefreshPriorityRows end
    M.TrackRefresh(ctx, RefreshPriorityRows)
end

local function BuildHighlightSection(ctx, b)
    local highlights = Rows.Schema.Section(b:CollapsibleSection("bars_highlight", "Highlight Borders", 764, true), "bars")
    local hlW = highlights._msuf2Width or ctx.width or 720
    local hlGap = 28
    local hlLeftX = 30
    local hlInnerW = max(320, hlW - 60)
    local hlLeftW = max(220, min(380, floor((hlInnerW - hlGap) * 0.46)))
    local hlPreviewX = hlLeftX
    local hlPreviewW = max(280, min(440, hlInnerW - 28))
    local highlightTabFrames = {}
    local modesFrame, previewFrame, priorityFrame =
        M.UnitSectionsShared.MakeTabFrames(highlights, -88, hlW, highlightTabFrames, "modes", "preview", "priority")
    RegisterSegment(W.SegmentTabs(ctx, highlights, {
        stateKey = "barsHighlightTab", label = "Highlight area",
        values = VT("modes", "Modes", "preview", "Preview", "priority", "Priority"),
        width = min(520, hlInnerW), frames = highlightTabFrames, defaultTab = "modes",
        x = hlLeftX, y = -44,
    }), "highlight.workspace_tab", VT("modes", "Modes", "preview", "Preview", "priority", "Priority"))
    local priorityCardW = min(360, max(260, hlLeftW + 28))
    local cards = Rows.Schema.Build(ctx, modesFrame, {
        { "card", "modesCard", nil, { "Border Modes", nil, hlLeftX - 14, -38, hlLeftW + 28, 596 }, scope = "bars" },
        { "card", "priorityCard", nil, { "Priority Order", nil, hlLeftX - 14, -38, priorityCardW, 296 }, scope = "bars",
            parent = priorityFrame },
        { "card", "previewCard", nil, { "Preview", nil, hlPreviewX - 14, -38, hlPreviewW + 28, 248 }, scope = "bars",
            parent = previewFrame },
    })
    local modesCard, priorityCard = cards.modesCard, cards.priorityCard
    local function HighlightPriorityEnabled()
        local value = BarScopeGet("hlPrioEnabled", nil)
        if value == nil then value = BarScopeGet("highlightPrioEnabled", false) end
        return value == true or value == 1 or value == "1"
    end
    local highlight, aggro, aggroMode, dispelBorder, dispelTrigger, dispelShowOn, purge, bossSupported,
        bossTarget, bossSharedHint, unitAuraDispelHint = GP.BuildHighlightModes(ctx, modesFrame, hlLeftX, hlLeftW)
    local function ScopeBorderModeOn(key, defaultValue) return tonumber(BarScopeGet(key, defaultValue)) == 1 end
    local function BossTargetBorderOn()
        local fallback = ReadGBool("bossTargetHighlightEnabled", true) and 1 or 0
        return (tonumber(ReadG("bossTargetOutlineMode", fallback)) or fallback) == 1
    end
    Rows.Schema.Colors(modesCard, function()
        local references = {}
        for i = 1, #DISPEL_COLOR_REFERENCES do
            references[i] = DISPEL_COLOR_REFERENCES[i]
        end
        references[#references + 1] = "bar.aggro_border"
        if PurgeScopeSupported() then
            references[#references + 1] = "bar.purge_border"
        end
        if SharedScope() then references[#references + 1] = "highlight.boss_target" end
        return references
    end, {
        title = "Highlight Border Colors",
        note = "Shared Dispel type colors plus the other colors available to this card's border modes.",
        scopeTag = "Shared",
        historySource = "menu:bars-highlight-colors",
        maxTargets = 8,
    })
    local function BindBorderTestToggle(label, y, kind, enabledFn, noScope, path)
        local flag, fn = Rows.testModes[kind].flag, Rows.TestSetter(kind)
        local control = Rows.Schema.Build(ctx, previewFrame, {
            { "toggle", "test", false, { label, hlPreviewX, y, hlPreviewW }, path = path, classification = "ephemeral",
                get = flag,
            set = function(v)
                if v and not enabledFn() then
                    if M.RequestRefresh then M.RequestRefresh(ctx, "bars-border-test-disabled") elseif M.Refresh then M.Refresh(ctx) end
                    return
                end
                if type(fn) == "function" then
                    if noScope then fn(v and true or false)
                    else fn(v and true or false, BorderTestScope()) end
                end
            end },
        }, Rows.Commands).test
        control:HookScript("OnHide", function(self)
            if flag() and type(fn) == "function" then
                fn(false)
                self:SetChecked(false)
            end
        end)
        return control
    end
    local aggroTest = BindBorderTestToggle("Test aggro border", -72, "aggro",
        function() return ScopeBorderModeOn("aggroOutlineMode", 1) end, nil, "highlight.preview.aggro")
    local dispelTest = BindBorderTestToggle("Test dispel border", -104, "dispel",
        function() return ScopeBorderModeOn("dispelOutlineMode", 1) end, nil, "highlight.preview.dispel")
    local purgeTest = BindBorderTestToggle("Test purge border", -214, "purge",
        function() return ScopeBorderModeOn("purgeOutlineMode", 0) end, nil, "highlight.preview.purge")
    local bossTargetTest = bossSupported and BindBorderTestToggle("Test boss target border", -246, "bossTarget",
        BossTargetBorderOn, true, "highlight.preview.boss_target")
    local scopedBorderControls = { highlight, aggro, dispelBorder, purge }
    local dispelBorderControls = { dispelTrigger, dispelShowOn, dispelTest }
    if W.SetControlsDisabledReason and W.TurnOnReason then
        W.SetControlsDisabledReason(dispelBorderControls, W.TurnOnReason("Dispel border", function() return ScopeBorderModeOn("dispelOutlineMode", 1) end))
        W.SetControlDisabledReason(aggroTest, W.TurnOnReason("Aggro border", function() return ScopeBorderModeOn("aggroOutlineMode", 1) end))
        local purgeReason = W.TurnOnReason("Purge border", function() return ScopeBorderModeOn("purgeOutlineMode", 0) end)
        W.SetControlDisabledReason(purgeTest, function(control) return PurgeScopeSupported() and purgeReason(control) or nil end)
        if bossTarget then
            local bossOnReason = W.TurnOnReason("Boss target border", BossTargetBorderOn)
            local function BossReason(control)
                if not SharedScope() then return M.Tr("Boss target border is a shared boss-frame setting.") end
                return control == bossTargetTest and bossOnReason(control) or nil
            end
            W.SetControlDisabledReason(bossTarget, BossReason)
            W.SetControlDisabledReason(bossTargetTest, BossReason)
        end
    end
    M.TrackRefresh(ctx, function()
        local scopedActive = HighlightControls()
        local sharedActive = SharedScope()
        local aggroOn = ScopeBorderModeOn("aggroOutlineMode", 1)
        local dispelOn = ScopeBorderModeOn("dispelOutlineMode", 1)
        local purgeOn = ScopeBorderModeOn("purgeOutlineMode", 0)
        local purgeSupported = PurgeScopeSupported()
        local bossTargetOn = BossTargetBorderOn()
        Rows.testModes.aggro.stop(aggroOn)
        Rows.testModes.dispel.stop(dispelOn)
        Rows.testModes.purge.stop(purgeOn and purgeSupported)
        Rows.testModes.bossTarget.stop(sharedActive and bossTargetOn)
        SetControlsEnabled(scopedBorderControls, scopedActive)
        SetControlEnabled(dispelBorder, scopedActive)
        SetControlEnabled(purge, scopedActive and purgeSupported)
        SetControlEnabled(bossTarget, sharedActive)
        SetControlEnabled(aggroMode, scopedActive and (sharedActive or GroupScope()))
        SetControlEnabled(aggroTest, scopedActive and aggroOn)
        SetControlsEnabled(dispelBorderControls, scopedActive and dispelOn)
        SetControlEnabled(purgeTest, scopedActive and purgeSupported and purgeOn)
        SetControlEnabled(bossTargetTest, sharedActive and bossTargetOn)
        if unitAuraDispelHint and unitAuraDispelHint.SetShown then
            unitAuraDispelHint:SetShown((not GroupScope()) and dispelOn and UnitFrameAuraSensorMissingForScope())
        end
        local hintColor = sharedActive and T.colors.dim or T.colors.muted
        if bossSharedHint then bossSharedHint:SetTextColor(hintColor[1], hintColor[2], hintColor[3], sharedActive and 0.75 or 1) end
    end)
    GP.BuildHighlightPriority(ctx, priorityCard, priorityCardW, HighlightPriorityEnabled)
end

local function BuildPowerSection(ctx, b)
    local power = Rows.Schema.Section(b:CollapsibleSection("bars_power", "Bar Animation + Text Accuracy", 184, false), "bars")
    local function FillSetter(setValue, reason)
        return function(value)
            setValue(value, reason)
            if M.RequestRefresh then M.RequestRefresh(ctx, "bars-power-fill-mode") end
        end
    end
    local controls = Rows.Build(ctx, power, {
        { "flowToggle", "smooth", false, { "Smooth power bar" }, path = "power.smooth_fill", get = SmoothPowerGet,
            set = FillSetter(SmoothPowerSet, "MSUF2_BARS_SMOOTH_POWER"),
            tip = "Power bars glide to new values instead of jumping; turns off Chunked power loss. " ..
                "Set per unit: pick a unit scope with a power bar, such as Player or Target.", tipOpts = "power" },
        { "flowToggle", "chunked", false, { "Chunked power loss" }, path = "power.chunked_fill", get = ChunkedPowerGet,
            set = FillSetter(ChunkedPowerSet, "MSUF2_BARS_CHUNKED_POWER"),
            tip = "Spent power drops at once while the spent part briefly stays highlighted, " ..
                "then fades; turns off Smooth power bar. Set per unit, like Smooth power bar.", tipOpts = "power" },
        { "flowToggle", "realtime", true, { "Realtime power text" }, path = "power.realtime_text",
            get = function() return ReadB("realtimePowerText", true) ~= false end,
            set = function(v)
            v = v and true or false
            local bars = Bars()
            if bars.realtimePowerText == v then return end
            bars.realtimePowerText = v
            -- Recompile Player and rebind both Power and PowerText events.
            -- A generic Bars layout refresh leaves this event option dead.
            M.RequestUnitDomains("player", "MSUF2_BARS_REALTIME_POWER", {
                preview = true, power = true, text = true,
            })
        end,
            tip = "Updates the Player power text on every power tick instead of the regular " ..
                "update rate. Only the Player frame uses it; set it on the Shared scope.", tipOpts = "power" },
    }, Rows.Commands)
    local smoothPower, chunkedPower, realtimePower = controls.smooth, controls.chunked, controls.realtime
    M.BindGateGroup(ctx, nil, {
        { controls = { smoothPower, chunkedPower }, on = function() return CurrentPowerBarScopeUnit() ~= nil end },
        { controls = realtimePower, on = SharedScope },
    })
end

-- Every collapsible on this page goes through the shared lazy-section
-- registry in page order. Open sections get their shell (declared height)
-- in the click frame and their content one deferred refresh later; closed
-- sections build on first expand; hidden search-index builds stay synchronous
-- inside BuildSectionLazy. Heights of open sections must mirror the compact
-- thresholds their builders use internally.
function Rows.PrepareSection(_, section) Rows.Schema.Section(section, "bars") end
local GLOBAL_BARS_LAZY_SECTION_SPECS = {
    {
        sectionId = "bars_textures", prepareShell = Rows.PrepareSection,
        title = "Textures & Gradient",
        defaultOpen = true,
        height = function(lazyCtx) return (((lazyCtx and lazyCtx.width) or 720) < 560) and 766 or 448 end,
        build = BuildTextureSection,
    },
    {
        sectionId = "bars_temp_max_health", prepareShell = Rows.PrepareSection,
        title = "Maximum Health Loss",
        defaultOpen = true,
        height = function(lazyCtx) return (((lazyCtx and lazyCtx.width) or 720) < 700) and 414 or 274 end,
        build = BuildTempMaxHealthSection,
    },
    { sectionId = "bars_absorb", prepareShell = Rows.PrepareSection,
        title = "Absorb Display", height = 414, defaultOpen = true, build = BuildAbsorbSection },
    { sectionId = "bars_outline", prepareShell = Rows.PrepareSection,
        title = "Frame Outline", height = 226, build = BuildOutlineSection },
    { sectionId = "bars_rounded", prepareShell = Rows.PrepareSection,
        title = "Rounded Texture", height = ROUNDED_SECTION_HEIGHT, defaultOpen = true, build = BuildRoundedSection },
    { sectionId = "bars_slanted", prepareShell = Rows.PrepareSection,
        title = "Slanted Bars", height = 480, defaultOpen = true, build = BuildSlantedSection },
    { sectionId = "bars_highlight", prepareShell = Rows.PrepareSection,
        title = "Highlight Borders", height = 764, defaultOpen = true, build = BuildHighlightSection },
    { sectionId = "bars_power", prepareShell = Rows.PrepareSection,
        title = "Bar Animation + Text Accuracy", height = 184, build = BuildPowerSection },
}
local function BuildGlobalBarsSectionLazy(ctx, b, spec)
    local buildLazy = M.UnitPage and M.UnitPage.BuildSectionLazy
    if type(buildLazy) == "function" then return buildLazy(ctx, b, nil, spec) end
    return spec.build(ctx, b)
end

local function BuildBars(ctx)
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Bars", "Textures, gradients, outlines and highlight borders.", 72)
    BuildScopeSection(ctx, b)
    for i = 1, #GLOBAL_BARS_LAZY_SECTION_SPECS do
        BuildGlobalBarsSectionLazy(ctx, b, GLOBAL_BARS_LAZY_SECTION_SPECS[i])
    end
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("opt_bars", { title = "MSUF Bars", build = BuildBars, version = 19 })
