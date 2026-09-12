local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Advanced Colors page: Power and Class Resource colors.
-- Owns the power-type and class-power override readers and writers, the
-- combo-slot palettes, the Power / Class Power color sections and the painter's
-- Resources preview strip data. Split from MSUF_Menu2_AdvancedColors.lua: it
-- loads after that page (and its Group sibling), picks the page helpers from
-- M.ColorsPage and publishes its readers there for the context-color registry.
local W = M.Widgets
local AP = M.AdvancedPage or {}
local floor = math.floor
local min = math.min
local G, Bars, ValueToggleAt, ValueSwitchAt, ValueDropdownAt = AP.G, AP.Bars, AP.ValueToggleAt, AP.ValueSwitchAt, AP.ValueDropdownAt
local WL, ColorRows, KeyLabelMap, ValueTextPairs = M.WordList, M.ColorRows, M.KeyLabelMap, M.ValueTextPairs
local CP = M.ColorsPage or {}
M.ColorsPage = CP
local CurrentApplyService, RequestGeneral, ApplyColors, ApiRGB = CP.CurrentApplyService, CP.RequestGeneral, CP.ApplyColors, CP.ApiRGB
local TableRGB, ColorValueAt, Meta = CP.TableRGB, CP.ColorValueAt, CP.Meta
local COLOR_DATA, COLOR_PAINTER_CATEGORIES, COLOR_POWER_TOKENS, COLOR_CP_TOKENS = CP.COLOR_DATA, CP.COLOR_PAINTER_CATEGORIES, CP.COLOR_POWER_TOKENS, CP.COLOR_CP_TOKENS
local function ApplyClassPowerColors()
    -- The painter's Resources strip paints straight from these DB values and
    -- has no writer of its own, so both apply paths poke it. Kept inline: this
    -- file rides the 200 active-local ceiling.
    local painter = M.ColorPainter
    if painter and type(painter.RefreshResourcesStrip) == "function" then painter.RefreshResourcesStrip() end
    local apply = CurrentApplyService()
    if apply and type(apply.RequestClassPower) == "function" then
        return apply.RequestClassPower("MSUF2_CLASSPOWER_COLORS", { colors = true, playerHP = true }, { preview = true, applyAll = false, colors = true, colorScope = "player" })
    end
    RequestGeneral("MSUF2_CLASSPOWER_COLORS", { preview = true, applyAll = false, colors = true, colorScope = "player" })
    _G.MSUF_ClassPower_InvalidateColors()
end
local COLOR_CP_SLOT_TOKENS = WL [[COMBO_POINTS_1 COMBO_POINTS_2 COMBO_POINTS_3 COMBO_POINTS_4 COMBO_POINTS_5 COMBO_POINTS_6 COMBO_POINTS_7]]
local COLOR_CP_SLOT_DEFAULTS = {}
for _, row in ipairs(ColorRows [[COMBO_POINTS_1|1|0.00|0.95|1.00;COMBO_POINTS_2|2|0.00|0.95|1.00;COMBO_POINTS_3|3|1.00|1.00|0.00;COMBO_POINTS_4|4|1.00|1.00|0.00;COMBO_POINTS_5|5|1.00|1.00|0.00;COMBO_POINTS_6|6|1.00|0.05|0.05;COMBO_POINTS_7|7|1.00|0.05|0.05]]) do
    COLOR_CP_SLOT_DEFAULTS[row.key] = { row.dr, row.dg, row.db }
end
local COLOR_CP_SLOT_MODES = ValueTextPairs "default=Resource color|ramp=Color ramp|custom=Custom slots"
local COLOR_CP_SLOT_COUNTS = KeyLabelMap [[COMBO_POINTS=7|HOLY_POWER=5|SOUL_SHARDS=5|CHI=6|ARCANE_CHARGES=4|RUNES=6|ESSENCE=6|SOUL_FRAGMENTS_VENG=6|MAELSTROM=10|WHIRLWIND=4|TIP_OF_THE_SPEAR=3|ICICLES=5]]
for token, count in pairs(COLOR_CP_SLOT_COUNTS) do COLOR_CP_SLOT_COUNTS[token] = tonumber(count) or 1 end
COLOR_DATA.CP_SLOT_TOKENS = COLOR_CP_SLOT_TOKENS
COLOR_DATA.CP_SLOT_MODES = COLOR_CP_SLOT_MODES
local function PowerDefaultRGB(token)
    local col = _G.PowerBarColor and token and _G.PowerBarColor[token]
    if type(col) == "table" then
        local r = tonumber(col.r or col[1])
        local g = tonumber(col.g or col[2])
        local b = tonumber(col.b or col[3])
        if r and g and b then return r, g, b end
    end
    return 0.8, 0.8, 0.8
end
local function EnsurePowerOverrides()
    local g = G()
    if type(g.powerColorOverrides) ~= "table" then g.powerColorOverrides = {} end
    return g.powerColorOverrides
end
local function GetPowerOverrideRGB(token)
    local overrides = G().powerColorOverrides
    local r, g, b = PowerDefaultRGB(token)
    if type(overrides) == "table" then return TableRGB(overrides, token, r, g, b) end
    return r, g, b
end
local function SetPowerOverrideRGB(token, r, g, b)
    EnsurePowerOverrides()[token] = { r, g, b }
    ApplyColors()
end
local function ResetPowerOverride(token)
    local overrides = EnsurePowerOverrides()
    overrides[token] = nil
    ApplyColors()
end
local CLASS_POWER_STATIC_DEFAULTS = {}
for _, row in ipairs(ColorRows [[CHARGED|Charged|0.60|0.20|0.80;SOUL_FRAGMENTS|Soul Fragments|0.00|0.80|0.00;SOUL_FRAGMENTS_META|Soul Fragments Meta|0.60|0.20|0.93;MAELSTROM_ABOVE_5|Maelstrom Above 5|1.00|0.50|0.00;ECLIPSE_SOLAR|Eclipse Solar|0.82|0.56|0.25;ECLIPSE_LUNAR|Eclipse Lunar|0.41|0.49|0.82;ECLIPSE_CA|Eclipse CA|0.30|1.00|0.43;STAGGER_GREEN|Stagger Green|0.52|1.00|0.52;STAGGER_YELLOW|Stagger Yellow|1.00|0.98|0.72;STAGGER_RED|Stagger Red|1.00|0.42|0.42;SOUL_FRAGMENTS_VENG|Soul Fragments Veng|0.34|0.06|0.46;WHIRLWIND|Whirlwind|0.20|0.80|0.20;TIP_OF_THE_SPEAR|Tip of the Spear|0.60|0.80|0.20;ICICLES|Icicles|0.50|0.80|1.00;EBON_MIGHT|Ebon Might|0.40|0.80|0.60]]) do
    CLASS_POWER_STATIC_DEFAULTS[row.key] = { row.dr, row.dg, row.db }
end
local CLASS_POWER_POWER_DEFAULTS = KeyLabelMap [[MAELSTROM=MAELSTROM|MAELSTROM_POWER=MAELSTROM|ASTRAL_POWER=LUNAR_POWER|AP_PREDICTION=LUNAR_POWER|INSANITY=INSANITY]]
local function ClassPowerDefaultRGB(token)
    local slot = COLOR_CP_SLOT_DEFAULTS[token]
    if slot then return slot[1], slot[2], slot[3] end
    local static = CLASS_POWER_STATIC_DEFAULTS[token]
    if static then return static[1], static[2], static[3] end
    if token == "RESOURCE_TEXT" then return ApiRGB("GetGlobalFontColor", 1, 1, 1) end
    local powerToken = CLASS_POWER_POWER_DEFAULTS[token]
    if powerToken then return GetPowerOverrideRGB(powerToken) end
    return GetPowerOverrideRGB(token)
end
local function EnsureClassPowerOverrides()
    local g = G()
    if type(g.classPowerColorOverrides) ~= "table" then g.classPowerColorOverrides = {} end
    if type(g.classPowerBgColorOverrides) ~= "table" then g.classPowerBgColorOverrides = {} end
    return g
end
local function GetClassPowerRGB(token)
    local dr, dg, db = ClassPowerDefaultRGB(token)
    local g = G()
    return TableRGB(g.classPowerColorOverrides, token, dr, dg, db)
end
local function SetClassPowerRGB(token, r, g, b)
    EnsureClassPowerOverrides().classPowerColorOverrides[token] = { r, g, b }
    ApplyClassPowerColors()
end
local function GetClassPowerBgRGB(token)
    return TableRGB(G().classPowerBgColorOverrides, token, 0, 0, 0)
end
local function SetClassPowerBgRGB(token, r, g, b)
    EnsureClassPowerOverrides().classPowerBgColorOverrides[token] = { r, g, b }
    ApplyClassPowerColors()
end
local function ResetClassPowerRGB(token, bg)
    local g = EnsureClassPowerOverrides()
    if bg then g.classPowerBgColorOverrides[token] = nil else g.classPowerColorOverrides[token] = nil end
    ApplyClassPowerColors()
end
local function ClassPowerSlotToken(resourceToken, slot)
    if resourceToken == "COMBO_POINTS" and slot <= #COLOR_CP_SLOT_TOKENS then
        return COLOR_CP_SLOT_TOKENS[slot]
    end
    return tostring(resourceToken or "COMBO_POINTS") .. "_" .. tostring(slot)
end
local function ClassPowerSlotCount(resourceToken)
    return COLOR_CP_SLOT_COUNTS[resourceToken] or 0
end
local function GetClassPowerSlotMode(resourceToken)
    local bars = Bars()
    local modes = bars.classPowerSlotColorModes
    local mode = type(modes) == "table" and modes[resourceToken] or nil
    if mode == nil and resourceToken == "COMBO_POINTS" then mode = bars.classPowerComboPointColorMode end
    if mode ~= "ramp" and mode ~= "custom" then return "default" end
    return mode
end
local function SetClassPowerSlotMode(resourceToken, mode)
    local bars = Bars()
    if type(bars.classPowerSlotColorModes) ~= "table" then bars.classPowerSlotColorModes = {} end
    mode = (mode == "ramp" or mode == "custom") and mode or "default"
    bars.classPowerSlotColorModes[resourceToken] = mode ~= "default" and mode or nil
    if resourceToken == "COMBO_POINTS" then bars.classPowerComboPointColorMode = mode end
    ApplyClassPowerColors()
end
local function GetClassPowerSlotRGB(resourceToken, slot)
    local token = ClassPowerSlotToken(resourceToken, slot)
    local overrides = G().classPowerColorOverrides
    if type(overrides) == "table" and type(overrides[token]) == "table" then
        return TableRGB(overrides, token, 1, 1, 1)
    end
    if resourceToken ~= "COMBO_POINTS" and GetClassPowerSlotMode(resourceToken) ~= "ramp" then
        return GetClassPowerRGB(resourceToken)
    end
    local rampSlot = slot > 7 and 7 or slot
    local fallback = COLOR_CP_SLOT_DEFAULTS[COLOR_CP_SLOT_TOKENS[rampSlot]]
    if fallback then return fallback[1], fallback[2], fallback[3] end
    return GetClassPowerRGB(resourceToken)
end
local function ClassPowerFullColorToken(resourceToken)
    return tostring(resourceToken or "COMBO_POINTS") .. "_FULL"
end
local function ClassPowerFullColorEnabled(resourceToken)
    local enabled = Bars().classPowerFullColorEnabled
    return type(enabled) == "table" and enabled[resourceToken] == true
end
local function SetClassPowerFullColorEnabled(resourceToken, enabled)
    local bars = Bars()
    if type(bars.classPowerFullColorEnabled) ~= "table" then bars.classPowerFullColorEnabled = {} end
    bars.classPowerFullColorEnabled[resourceToken] = enabled == true and true or nil
    ApplyClassPowerColors()
end
local function GetClassPowerFullRGB(resourceToken)
    local token = ClassPowerFullColorToken(resourceToken)
    local overrides = G().classPowerColorOverrides
    if type(overrides) == "table" and type(overrides[token]) == "table" then
        return TableRGB(overrides, token, 1, 1, 1)
    end
    return GetClassPowerRGB(resourceToken)
end
local function BuildPowerAndClassPowerColors(ctx, b, CH)
    local power = b:CollapsibleSection("colors_power", "Power Bar Colors", 150, false)
    ValueToggleAt(ctx, power, "Power bar color by class", 12, -94,
        function() return M.PowerBarColorByClass.Get() end,
        function(v) M.PowerBarColorByClass.Set(v) end,
        Meta("power.color_by_class"))
    M.colorsPowerToken = M.colorsPowerToken or "MANA"
    local powerColor
    ValueDropdownAt(ctx, power, "Power type", 12, -10, COLOR_DATA.POWER_TOKENS, 260,
        function() return M.colorsPowerToken or "MANA" end,
        function(v)
            M.SetMenuStateValue("colorsPowerToken", v or "MANA")
            if powerColor then powerColor:SetRGB(GetPowerOverrideRGB(M.colorsPowerToken)) end
            -- The painter's resources preview strip mirrors this selection.
            if M.RequestRefresh then M.RequestRefresh(ctx, "power-color-token") end
        end,
        Meta("power.editor.resource_selector", "ephemeral"))
    powerColor = ColorValueAt(ctx, power, "Color", 360, -10,
        function() return GetPowerOverrideRGB(M.colorsPowerToken or "MANA") end,
        function(r, g, c) SetPowerOverrideRGB(M.colorsPowerToken or "MANA", r, g, c) end,
        nil, nil, Meta("power.editor.color"))
    CH.ButtonAt(power, "Reset", 360, -54, 90, function()
        ResetPowerOverride(M.colorsPowerToken or "MANA")
        if powerColor then powerColor:SetRGB(GetPowerOverrideRGB(M.colorsPowerToken or "MANA")) end
    end, "power.editor.reset")
    local classPower = b:CollapsibleSection("colors_class_power", "Class Power Colors", 430, false)
    M.colorsCPToken = M.colorsCPToken or "COMBO_POINTS"
    local cpColor, cpBg, slotMode, slotReset, fullToggle, fullColor, fullReset
    local slotControls = {}
    local visibleSlotCount, slotControlsAvailable
    local function RequestClassPowerEditorRefresh(reason)
        if M.RequestRefresh then
            M.RequestRefresh(ctx, reason or "class-power-resource-editor")
        elseif M.Refresh then
            M.Refresh(ctx)
        end
    end
    local function RefreshSlotControls()
        local resourceToken = M.colorsCPToken or "COMBO_POINTS"
        local count = min(#slotControls, ClassPowerSlotCount(resourceToken))
        local hasSlots = count > 0
        if slotControlsAvailable ~= hasSlots then
            -- New controls start shown. Avoid reapplying that default on the
            -- common slot-based resources; SetControlShown also refreshes the
            -- control layout and is intentionally reserved for real deltas.
            if slotControlsAvailable ~= nil or not hasSlots then
                W.SetControlShown(slotMode, hasSlots)
                W.SetControlShown(slotReset, hasSlots)
                W.SetControlShown(fullToggle, hasSlots)
                W.SetControlShown(fullColor, hasSlots)
                W.SetControlShown(fullReset, hasSlots)
            end
            slotControlsAvailable = hasSlots
        end
        if visibleSlotCount == nil then
            for i = count + 1, #slotControls do W.SetControlShown(slotControls[i], false) end
        elseif count < visibleSlotCount then
            for i = count + 1, visibleSlotCount do W.SetControlShown(slotControls[i], false) end
        elseif count > visibleSlotCount then
            for i = visibleSlotCount + 1, count do W.SetControlShown(slotControls[i], true) end
        end
        visibleSlotCount = count
    end
    ValueDropdownAt(ctx, classPower, "Resource type", 12, -10, COLOR_DATA.CP_TOKENS, 310,
        function() return M.colorsCPToken or "COMBO_POINTS" end,
        function(v)
            M.SetMenuStateValue("colorsCPToken", v or "COMBO_POINTS")
            RequestClassPowerEditorRefresh("class-power-resource-selection")
        end,
        Meta("class_power.editor.resource_selector", "ephemeral"))
    cpColor = ColorValueAt(ctx, classPower, "Color", 360, -10,
        function() return GetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS") end,
        function(r, g, c) SetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS", r, g, c) end,
        nil, nil, Meta("class_power.editor.foreground_color"))
    cpBg = ColorValueAt(ctx, classPower, "Background", 360, -46,
        function() return GetClassPowerBgRGB(M.colorsCPToken or "COMBO_POINTS") end,
        function(r, g, c) SetClassPowerBgRGB(M.colorsCPToken or "COMBO_POINTS", r, g, c) end,
        nil, nil, Meta("class_power.editor.background_color"))
    CH.ButtonAt(classPower, "Reset color", 360, -86, 110, function()
        ResetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS", false)
        if cpColor then cpColor:SetRGB(GetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS")) end
    end, "class_power.editor.reset_foreground")
    CH.ButtonAt(classPower, "Reset bg", 480, -86, 110, function()
        ResetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS", true)
        if cpBg then cpBg:SetRGB(GetClassPowerBgRGB(M.colorsCPToken or "COMBO_POINTS")) end
    end, "class_power.editor.reset_background")
    slotMode = ValueDropdownAt(ctx, classPower, "Resource slot mode", 12, -92, COLOR_DATA.CP_SLOT_MODES, 230,
        function()
            return GetClassPowerSlotMode(M.colorsCPToken or "COMBO_POINTS")
        end,
        function(v)
            SetClassPowerSlotMode(M.colorsCPToken or "COMBO_POINTS", v)
        end,
        Meta("class_power.resource_slots.mode"))
    fullToggle = ValueSwitchAt(ctx, classPower, "Full resource color", 360, -116, 150,
        function() return ClassPowerFullColorEnabled(M.colorsCPToken or "COMBO_POINTS") end,
        function(value)
            SetClassPowerFullColorEnabled(M.colorsCPToken or "COMBO_POINTS", value)
        end,
        Meta("class_power.full_resource.enabled"))
    fullColor = ColorValueAt(ctx, classPower, "Full", 540, -116,
        function() return GetClassPowerFullRGB(M.colorsCPToken or "COMBO_POINTS") end,
        function(r, g, b)
            local resourceToken = M.colorsCPToken or "COMBO_POINTS"
            local enabled = ClassPowerFullColorEnabled(resourceToken)
            if not enabled then SetClassPowerFullColorEnabled(resourceToken, true) end
            SetClassPowerRGB(ClassPowerFullColorToken(resourceToken), r, g, b)
            if not enabled then RequestClassPowerEditorRefresh("class-power-full-color") end
        end, 36, 44, Meta("class_power.full_resource.color"))
    for i = 1, 10 do
        local slot = i
        slotControls[i] = ColorValueAt(ctx, classPower, tostring(i), 12 + ((i - 1) % 4) * 160, -154 - floor((i - 1) / 4) * 38,
            function() return GetClassPowerSlotRGB(M.colorsCPToken or "COMBO_POINTS", slot) end,
            function(r, g, c)
                local resourceToken = M.colorsCPToken or "COMBO_POINTS"
                local custom = GetClassPowerSlotMode(resourceToken) == "custom"
                if not custom then SetClassPowerSlotMode(resourceToken, "custom") end
                SetClassPowerRGB(ClassPowerSlotToken(resourceToken, slot), r, g, c)
                if not custom then RequestClassPowerEditorRefresh("class-power-slot-color") end
            end, 24, 44, Meta("class_power.resource_slots.slot." .. tostring(i)))
    end
    slotReset = CH.ButtonAt(classPower, "Reset slots", 12, -284, 120, function()
        local resourceToken = M.colorsCPToken or "COMBO_POINTS"
        local g = EnsureClassPowerOverrides()
        for i = 1, ClassPowerSlotCount(resourceToken) do
            g.classPowerColorOverrides[ClassPowerSlotToken(resourceToken, i)] = nil
        end
        ApplyClassPowerColors()
        RequestClassPowerEditorRefresh("class-power-slots-reset")
    end, "class_power.resource_slots.reset")
    fullReset = CH.ButtonAt(classPower, "Reset full", 142, -284, 110, function()
        local resourceToken = M.colorsCPToken or "COMBO_POINTS"
        EnsureClassPowerOverrides().classPowerColorOverrides[ClassPowerFullColorToken(resourceToken)] = nil
        SetClassPowerFullColorEnabled(resourceToken, false)
        RequestClassPowerEditorRefresh("class-power-full-color-reset")
    end, "class_power.full_resource.reset")
    M.TrackRefresh(ctx, RefreshSlotControls)
end
local function TokenText(list, value)
    for i = 1, #(list or {}) do
        local item = list[i]
        if item.value == value then return item.text or tostring(value) end
    end
    return tostring(value or "")
end
-- The Resources tab renders a menu-only preview strip instead of the live unit
-- frames: it must follow the Power type / Resource type dropdown selection,
-- which the player's real frames cannot show for foreign classes.
local COLOR_RESOURCES_CATEGORY
for i = 1, #COLOR_PAINTER_CATEGORIES do
    if COLOR_PAINTER_CATEGORIES[i].key == "resources" then COLOR_RESOURCES_CATEGORY = COLOR_PAINTER_CATEGORIES[i] end
end
COLOR_RESOURCES_CATEGORY.preview = {
    powerLabel = function() return TokenText(COLOR_POWER_TOKENS, M.colorsPowerToken or "MANA") end,
    power = function() return GetPowerOverrideRGB(M.colorsPowerToken or "MANA") end,
    powerBg = function() return ApiRGB("GetPowerBarBackgroundColor", 0, 0, 0) end,
    resourceLabel = function() return TokenText(COLOR_CP_TOKENS, M.colorsCPToken or "COMBO_POINTS") end,
    resource = function() return GetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS") end,
    resourceBg = function() return GetClassPowerBgRGB(M.colorsCPToken or "COMBO_POINTS") end,
    slotCount = function() return ClassPowerSlotCount(M.colorsCPToken or "COMBO_POINTS") end,
    slot = function(i) return GetClassPowerSlotRGB(M.colorsCPToken or "COMBO_POINTS", i) end,
    fullEnabled = function() return ClassPowerFullColorEnabled(M.colorsCPToken or "COMBO_POINTS") end,
    full = function() return GetClassPowerFullRGB(M.colorsCPToken or "COMBO_POINTS") end,
}
-- Published for the context-color registry sibling, the Fonts swatches and
-- the page's lazy category builders.
CP.GetPowerOverrideRGB = GetPowerOverrideRGB
CP.SetPowerOverrideRGB = SetPowerOverrideRGB
CP.GetClassPowerRGB = GetClassPowerRGB
CP.SetClassPowerRGB = SetClassPowerRGB
CP.GetClassPowerBgRGB = GetClassPowerBgRGB
CP.SetClassPowerBgRGB = SetClassPowerBgRGB
CP.ClassPowerSlotToken = ClassPowerSlotToken
CP.ClassPowerSlotCount = ClassPowerSlotCount
CP.GetClassPowerSlotMode = GetClassPowerSlotMode
CP.SetClassPowerSlotMode = SetClassPowerSlotMode
CP.GetClassPowerSlotRGB = GetClassPowerSlotRGB
CP.ClassPowerFullColorToken = ClassPowerFullColorToken
CP.ClassPowerFullColorEnabled = ClassPowerFullColorEnabled
CP.SetClassPowerFullColorEnabled = SetClassPowerFullColorEnabled
CP.GetClassPowerFullRGB = GetClassPowerFullRGB
CP.BuildPowerAndClassPowerColors = BuildPowerAndClassPowerColors
