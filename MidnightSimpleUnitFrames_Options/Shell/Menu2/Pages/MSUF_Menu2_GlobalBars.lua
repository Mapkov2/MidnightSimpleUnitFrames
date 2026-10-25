local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
-- Load-time dependency handoff; runtime callbacks retain their original local bindings.
local Parts = {}
M.GlobalBarsParts = Parts
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
            get = get or Get, set = not row.write and (row.set or Set) or nil, write = row.write,
        writeTargets = row.writeTargets,
            companionWrites = row.companionWrites,
            customSetReason = row.customSetReason or "Writes scoped bar ownership markers, companion fields or preview commands." }
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
    customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.",
            companionWrites = { "general.highlightPrioOrder" },
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
        Rows.Schema.SetSetting(Rows.Schema.Owned(shortcut, "bars", "contextColors"), Rows.Schema.FromMeta(registeredMeta))
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

-- Explicit load-time exports for the following responsibility modules.
Parts.ApplyBars = ApplyBars
Parts.ApplyGradientRuntime = ApplyGradientRuntime
Parts.ApplyRoundedRuntime = ApplyRoundedRuntime
Parts.AttachBarsColorShortcut = AttachBarsColorShortcut
Parts.BarBackgroundTextureForScope = BarBackgroundTextureForScope
Parts.BarScopeGet = BarScopeGet
Parts.BarScopeGetBars = BarScopeGetBars
Parts.BarScopeSet = BarScopeSet
Parts.BarScopeSetBars = BarScopeSetBars
Parts.BarTextureForScope = BarTextureForScope
Parts.Bars = Bars
Parts.BorderTestScope = BorderTestScope
Parts.C_Timer = C_Timer
Parts.CaptureBarsScopeFields = CaptureBarsScopeFields
Parts.ChunkedPowerGet = ChunkedPowerGet
Parts.ChunkedPowerSet = ChunkedPowerSet
Parts.CreateRoundedTexturePreview = CreateRoundedTexturePreview
Parts.CurrentBarsScope = CurrentBarsScope
Parts.CurrentGradientDirectionsForScope = CurrentGradientDirectionsForScope
Parts.CurrentPowerBarScopeUnit = CurrentPowerBarScopeUnit
Parts.DB = DB
Parts.DISPEL_COLOR_REFERENCES = DISPEL_COLOR_REFERENCES
Parts.DISPEL_SHOW_ON = DISPEL_SHOW_ON
Parts.DISPEL_TRIGGERS = DISPEL_TRIGGERS
Parts.EnsureUnitFrameAuraSensorsForScope = EnsureUnitFrameAuraSensorsForScope
Parts.FILE = FILE
Parts.FreezePowerGradientScope = FreezePowerGradientScope
Parts.G = G
Parts.GP = GP
Parts.GradientControlsActive = GradientControlsActive
Parts.GradientScopeGet = GradientScopeGet
Parts.GradientScopeSet = GradientScopeSet
Parts.GroupScope = GroupScope
Parts.HighlightControls = HighlightControls
Parts.IsAbsorbTextureTestEnabled = IsAbsorbTextureTestEnabled
Parts.IsGFScope = IsGFScope
Parts.Meta = Meta
Parts.NormalizeAggroMode = NormalizeAggroMode
Parts.NormalizeDispelTrigger = NormalizeDispelTrigger
Parts.NormalizeScopeKey = NormalizeScopeKey
Parts.OUTLINE_COLOR_STATE_FIELDS = OUTLINE_COLOR_STATE_FIELDS
Parts.PRIORITY_LABELS = PRIORITY_LABELS
Parts.PixelLayoutRegion = PixelLayoutRegion
Parts.PriorityColor = PriorityColor
Parts.PriorityOrder = PriorityOrder
Parts.PurgeScopeSupported = PurgeScopeSupported
Parts.ROUNDED_SECTION_HEIGHT = ROUNDED_SECTION_HEIGHT
Parts.ROUNDED_STRENGTH_APPLY_DELAY = ROUNDED_STRENGTH_APPLY_DELAY
Parts.ReadB = ReadB
Parts.ReadG = ReadG
Parts.ReadGBool = ReadGBool
Parts.RefreshBorderTestModes = RefreshBorderTestModes
Parts.RegisterControl = RegisterControl
Parts.RegisterDragRows = RegisterDragRows
Parts.RegisterRoundedSearch = RegisterRoundedSearch
Parts.RegisterSegment = RegisterSegment
Parts.RequestAggroBorderRuntime = RequestAggroBorderRuntime
Parts.RequestAllHighlightBorderRuntime = RequestAllHighlightBorderRuntime
Parts.RequestApply = RequestApply
Parts.RequestBossTargetBorderRuntime = RequestBossTargetBorderRuntime
Parts.RequestDispelPurgeBorderRuntime = RequestDispelPurgeBorderRuntime
Parts.RequestGroupAggroRoleRuntime = RequestGroupAggroRoleRuntime
Parts.RequestHighlightPriorityRuntime = RequestHighlightPriorityRuntime
Parts.RequestOutlineRuntime = RequestOutlineRuntime
Parts.RestoreBarsScopeFields = RestoreBarsScopeFields
Parts.Rows = Rows
Parts.SLANTED_DIRECTION_VALUES = SLANTED_DIRECTION_VALUES
Parts.SLANTED_PRESET_GROUPS = SLANTED_PRESET_GROUPS
Parts.SLANTED_PRESET_UNITS = SLANTED_PRESET_UNITS
Parts.SLANTED_SCOPED_DIRECTION_VALUES = SLANTED_SCOPED_DIRECTION_VALUES
Parts.ScopeDBKeys = ScopeDBKeys
Parts.ScopeHasOverride = ScopeHasOverride
Parts.ScopeSetOverride = ScopeSetOverride
Parts.ScopedControls = ScopedControls
Parts.SetAbsorbTextureTest = SetAbsorbTextureTest
Parts.SetBarBackgroundTextureForScope = SetBarBackgroundTextureForScope
Parts.SetBarTextureForScope = SetBarTextureForScope
Parts.SetControlEnabled = SetControlEnabled
Parts.SetControlsEnabled = SetControlsEnabled
Parts.SetOutlineColorForScope = SetOutlineColorForScope
Parts.SetRoundedBool = SetRoundedBool
Parts.ShapePreviewSurface = ShapePreviewSurface
Parts.SharedScope = SharedScope
Parts.ShowDispelBorderReloadRequiredPopup = ShowDispelBorderReloadRequiredPopup
Parts.SmoothPowerGet = SmoothPowerGet
Parts.SmoothPowerSet = SmoothPowerSet
Parts.T = T
Parts.TEMP_MAX_HEALTH_COLOR_STATE_FIELDS = TEMP_MAX_HEALTH_COLOR_STATE_FIELDS
Parts.TextureControlsActive = TextureControlsActive
Parts.TextureValues = TextureValues
Parts.ToggleGradientDirectionForScope = ToggleGradientDirectionForScope
Parts.UNITFRAME_DISPEL_AURA_WARNING = UNITFRAME_DISPEL_AURA_WARNING
Parts.UNITFRAME_DISPEL_AURA_WARNING_COLOR = UNITFRAME_DISPEL_AURA_WARNING_COLOR
Parts.UnitFrameAuraSensorMissingForScope = UnitFrameAuraSensorMissingForScope
Parts.VT = VT
Parts.W = W
Parts.floor = floor
Parts.max = max
Parts.min = min
