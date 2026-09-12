local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Advanced Colors page: Group Frame colors.
-- Owns the shared Party / Raid / Mythic Raid color readers and writers and
-- the Group Frame color sections. Split from MSUF_Menu2_AdvancedColors.lua:
-- it loads right after that page, picks the page helpers from M.ColorsPage and
-- publishes its readers there for the context-color registry sibling.
local W = M.Widgets
local AP = M.AdvancedPage or {}
local floor = math.floor
local max = math.max
local min = math.min
local DB, G, MoveWidget, ValueToggleAt, ValueSwitchAt, ValueDropdownAt = AP.DB, AP.G, AP.MoveWidget, AP.ValueToggleAt, AP.ValueSwitchAt, AP.ValueDropdownAt
local ValueTextPairs = M.ValueTextPairs
local CP = M.ColorsPage or {}
M.ColorsPage = CP
local CurrentApplyService, ColorValueAt, Meta = CP.CurrentApplyService, CP.ColorValueAt, CP.Meta
local GROUP_COLOR_DB_KEYS = { "gf_party", "gf_raid", "gf_mythicraid" }
local GROUP_COLOR_KINDS = { "party", "raid", "mythicraid" }
local GROUP_BAR_MODES = (M.GroupSpecs and M.GroupSpecs.GF_BAR_MODES)
    or ValueTextPairs "GLOBAL=Follow Global Style|CLASS=Class Color|dark=Dark Mode|unified=Unified Color|GRADIENT=Health Gradient|CUSTOM=Custom Color"
local GROUP_HEALTH_MODES = (M.GroupSpecs and M.GroupSpecs.HEALTH_MODES)
    or ValueTextPairs "CLASS=Class|GRADIENT=Gradient|CUSTOM=Custom"
local function GroupDBConf(dbKey)
    local db = DB()
    db[dbKey] = db[dbKey] or {}
    return db[dbKey]
end
local function GroupRead(key, defaultValue)
    local db = DB()
    for i = 1, #GROUP_COLOR_DB_KEYS do
        local conf = db[GROUP_COLOR_DB_KEYS[i]]
        if conf and conf[key] ~= nil then return conf[key] end
    end
    return defaultValue
end
local function GroupNum(key, defaultValue)
    return tonumber(GroupRead(key, defaultValue)) or defaultValue or 0
end
local function GroupBool(key, defaultValue)
    local value = GroupRead(key, defaultValue and true or false)
    return value and true or false
end
local function RequestGroupColorApply(reason, mode)
    local apply = CurrentApplyService()
    if apply and type(apply.RequestGroup) == "function" then
        return apply.RequestGroup("group", mode or "visual", reason or "MSUF2_GROUP_COLORS")
    end
    local GP = M.GroupPage
    if GP and type(GP.QueueGF) == "function" then
        for i = 1, #GROUP_COLOR_KINDS do GP.QueueGF(GROUP_COLOR_KINDS[i], mode or "visual") end
        return true
    end
    return false
end
local function SetGroupValue(key, value, reason, mode)
    local changed = false
    for i = 1, #GROUP_COLOR_DB_KEYS do
        local conf = GroupDBConf(GROUP_COLOR_DB_KEYS[i])
        if conf[key] ~= value then
            conf[key] = value
            changed = true
        end
    end
    if changed then RequestGroupColorApply(reason, mode or "visual") end
    return changed
end
local function SetGroupRGB(prefix, r, g, b, reason, mode)
    local changed = false
    for i = 1, #GROUP_COLOR_DB_KEYS do
        local conf = GroupDBConf(GROUP_COLOR_DB_KEYS[i])
        if conf[prefix .. "R"] ~= r or conf[prefix .. "G"] ~= g or conf[prefix .. "B"] ~= b then
            conf[prefix .. "R"], conf[prefix .. "G"], conf[prefix .. "B"] = r, g, b
            changed = true
        end
    end
    if changed then RequestGroupColorApply(reason, mode or "visual") end
end
local function SetGroupRGBA(prefix, alphaKey, r, g, b, a, reason, mode)
    local changed = false
    for i = 1, #GROUP_COLOR_DB_KEYS do
        local conf = GroupDBConf(GROUP_COLOR_DB_KEYS[i])
        if conf[prefix .. "R"] ~= r or conf[prefix .. "G"] ~= g or conf[prefix .. "B"] ~= b
            or (a ~= nil and conf[alphaKey] ~= a)
        then
            conf[prefix .. "R"], conf[prefix .. "G"], conf[prefix .. "B"] = r, g, b
            if a ~= nil then conf[alphaKey] = a end
            changed = true
        end
    end
    if changed then RequestGroupColorApply(reason, mode or "visual") end
end
local function GroupRGB(prefix, dr, dg, db)
    return GroupNum(prefix .. "R", dr), GroupNum(prefix .. "G", dg), GroupNum(prefix .. "B", db)
end
local function GroupColorAt(ctx, section, label, x, y, prefix, dr, dg, db, labelWidth, swatchWidth)
    return ColorValueAt(ctx, section, label, x, y,
        function() return GroupRGB(prefix, dr, dg, db) end,
        function(r, g, b) SetGroupRGB(prefix, r, g, b, "MSUF2_GROUP_COLORS", "visual") end,
        labelWidth, swatchWidth, Meta("group_frame.color." .. tostring(prefix)), { dr, dg, db })
end
local function Clamp01(value, fallback)
    value = tonumber(value)
    if value == nil then value = fallback or 0 end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end
local function PercentLabel(label, value)
    return tostring(label or "") .. ": " .. tostring(floor(Clamp01(value, 0) * 100 + 0.5)) .. "%"
end
local function GroupAlphaSlider(ctx, parent, label, x, y, width, key, defaultValue)
    local slider = W.Slider(parent, "", 0, 1, 0.05, width or 260)
    M.BindNumberWidget(ctx, slider,
        function() return GroupNum(key, defaultValue) end,
        function(value) SetGroupValue(key, Clamp01(value, defaultValue), "MSUF2_GROUP_COLORS", "visual") end,
        defaultValue,
        Meta("group_frame.alpha." .. tostring(key)))
    MoveWidget(slider, parent, x, y)
    if M.BindSliderLiveLabel then
        M.BindSliderLiveLabel(ctx, slider, function() return GroupNum(key, defaultValue) end,
            function(value) return PercentLabel(label, value) end, true)
    end
    return slider
end
local function CurrentGlobalBarColor()
    local getCache = _G.MSUF_UFCore_GetSettingsCache
    local cache = (type(getCache) == "function") and getCache() or nil
    local modeKey = cache and cache.barMode
    if modeKey == "unified" then
        return cache.unifiedBarR or 0.10, cache.unifiedBarG or 0.60, cache.unifiedBarB or 0.90
    elseif modeKey == "dark" then
        return cache.darkBarR or 0, cache.darkBarG or 0, cache.darkBarB or 0
    end
    local g = G()
    return g.unifiedBarR or 0.10, g.unifiedBarG or 0.60, g.unifiedBarB or 0.90
end
local function GroupBarMode()
    local mode = GroupRead("gfBarMode", "GLOBAL")
    if mode == nil or mode == "" then return "GLOBAL" end
    return mode
end
local function GroupHealthBarRGB()
    local mode = GroupBarMode()
    if mode == "GLOBAL" then return CurrentGlobalBarColor() end
    if mode == "dark" then return GroupRGB("gfDark", 0, 0, 0) end
    if mode == "unified" then return GroupRGB("gfUnified", 0.10, 0.60, 0.90) end
    if mode == "CUSTOM" then return GroupRGB("healthCustom", 0.20, 0.80, 0.20) end
    return 0.20, 0.80, 0.20
end
local function SetGroupHealthBarRGB(r, g, b)
    local mode = GroupBarMode()
    if mode == "dark" then
        SetGroupRGB("gfDark", r, g, b, "MSUF2_GROUP_HEALTH_COLOR", "visual")
    elseif mode == "unified" then
        SetGroupRGB("gfUnified", r, g, b, "MSUF2_GROUP_HEALTH_COLOR", "visual")
    elseif mode == "CUSTOM" then
        SetGroupRGB("healthCustom", r, g, b, "MSUF2_GROUP_HEALTH_COLOR", "visual")
    end
end
local function BuildGroupFrameColors(ctx, b)
    local pageW = b.width or ctx.width or 720
    local cardW = max(320, pageW - 32)
    local health = b:CollapsibleSection("colors_group_frames", "Health Bars", 112, true)
    local background = b:CollapsibleSection("colors_group_frames_background", "Bar Background", 112, false)
    local state = b:CollapsibleSection("colors_group_frames_state", "State Tints", 242, false)
    local highlights = b:CollapsibleSection("colors_group_frames_highlights", "Group Highlights", 220, false)

    ValueDropdownAt(ctx, health, "Bar Color Mode", 12, -10, GROUP_BAR_MODES, min(360, cardW - 32),
        GroupBarMode,
        function(value)
            value = value or "GLOBAL"
            local selectedValue1
            if not (value == "GLOBAL") then selectedValue1 = value end
            SetGroupValue("gfBarMode", selectedValue1, "MSUF2_GROUP_HEALTH_MODE", "visual")
            if value == "CLASS" or value == "GRADIENT" then
                SetGroupValue("healthColorMode", value, "MSUF2_GROUP_HEALTH_MODE", "visual")
            end
            if M.RequestRefresh then M.RequestRefresh(ctx, "group-colors-mode") end
        end,
        Meta("group_frame.health.mode"))
    local healthColor = ColorValueAt(ctx, health, "Health bar color", 12, -64, GroupHealthBarRGB, SetGroupHealthBarRGB,
        nil, nil, Meta("group_frame.health.color"))

    GroupColorAt(ctx, background, "Background Color", 12, -10, "bg", 0.10, 0.10, 0.10)
    ValueDropdownAt(ctx, background, "Health color fallback", 12, -56, GROUP_HEALTH_MODES, min(360, cardW - 32),
        function() return GroupRead("healthColorMode", "CLASS") or "CLASS" end,
        function(value) SetGroupValue("healthColorMode", value or "CLASS", "MSUF2_GROUP_HEALTH_FALLBACK", "visual") end,
        Meta("group_frame.health.fallback_mode"))

    local RefreshStateTintControls = M.RefreshProxy()
    ValueSwitchAt(ctx, state, "Dead / Offline Background", 12, -10, min(320, cardW - 32),
        function() return GroupBool("deadBgEnabled", false) end,
        function(value)
            SetGroupValue("deadBgEnabled", value and true or false, "MSUF2_GROUP_DEAD_BG", "visual")
            RefreshStateTintControls()
        end,
        Meta("group_frame.state.dead_offline.enabled"))
    local deadColor = GroupColorAt(ctx, state, "Background color", 12, -48, "deadBg", 0.60, 0.05, 0.05)
    local deadAlpha = GroupAlphaSlider(ctx, state, "Dead/offline opacity", 12, -86, max(220, cardW - 58), "deadBgA", 0.90)
    local offline = ValueToggleAt(ctx, state, "Also tint offline members", 12, -132,
        function() return GroupBool("deadBgOffline", true) end,
        function(value) SetGroupValue("deadBgOffline", value and true or false, "MSUF2_GROUP_DEAD_BG_OFFLINE", "visual") end,
        Meta("group_frame.state.dead_offline.include_offline"))
    GroupColorAt(ctx, state, "Debuff stripe color", 12, -166, "debuffStripeColor", 0.80, 0.20, 0.20)
    GroupAlphaSlider(ctx, state, "Debuff stripe opacity", 12, -202, max(220, cardW - 58), "debuffStripeAlpha", 0.60)

    GroupColorAt(ctx, highlights, "Target Highlight Color", 12, -10, "target", 1, 1, 1)
    GroupColorAt(ctx, highlights, "Focus Highlight Color", 12, -48, "hlFocusColor", 0.50, 0.50, 1.00)
    GroupColorAt(ctx, highlights, "Group Border Color", 12, -86, "groupBorder", 0.38, 0.68, 1.00)
    GroupAlphaSlider(ctx, highlights, "Group border opacity", 12, -128, max(220, cardW - 58), "groupBorderA", 0.95)
    GroupColorAt(ctx, highlights, "Corner aggro color", 12, -174, "ciAggroColor", 1.00, 0.55, 0.00)
    RefreshStateTintControls = RefreshStateTintControls(M.BindGateGroup(ctx, nil, {
        { controls = healthColor, on = function()
            local current = GroupBarMode()
            return current == "dark" or current == "unified" or current == "CUSTOM"
        end },
        { controls = { deadColor, deadAlpha, offline }, on = function() return GroupBool("deadBgEnabled", false) end },
    }))
end
-- Published for the context-color registry sibling and the page's lazy
-- category builders.
CP.GROUP_COLOR_DB_KEYS = GROUP_COLOR_DB_KEYS
CP.GroupNum = GroupNum
CP.GroupRGB = GroupRGB
CP.SetGroupRGB = SetGroupRGB
CP.SetGroupRGBA = SetGroupRGBA
CP.GroupHealthBarRGB = GroupHealthBarRGB
CP.SetGroupHealthBarRGB = SetGroupHealthBarRGB
CP.BuildGroupFrameColors = BuildGroupFrameColors
