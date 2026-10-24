local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Advanced Colors page: Group Frame colors.
-- Owns the shared Party / Raid / Mythic Raid color readers and writers and
-- the Group Frame color sections. Split from MSUF_Menu2_AdvancedColors.lua:
-- it loads right after that page, picks the page helpers from M.ColorsPage and
-- publishes its readers there for the context-color registry sibling.
local Schema = M.ControlSchema
local AP = M.AdvancedPage or {}
local floor = math.floor
local max = math.max
local min = math.min
local DB, G, MoveWidget = AP.DB, AP.G, AP.MoveWidget
local ValueTextPairs = M.ValueTextPairs
local CP = M.ColorsPage or {}
M.ColorsPage = CP
local CurrentApplyService, Meta, Opt = CP.CurrentApplyService, CP.Meta, CP.Opt
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
local function HealerManaTextRGB() return GroupRGB("healerManaText", 1, 1, 1) end
local function SetHealerManaTextRGB(r, g, b)
    SetGroupRGB("healerManaText", r, g, b, "MSUF2_GROUP_HEALER_MANA_TEXT", "rebuild")
end
local function ApplyHealerManaText()
    return RequestGroupColorApply("MSUF2_GROUP_HEALER_MANA_TEXT", "rebuild")
end
local function Clamp01(value, fallback)
    value = tonumber(value)
    if value == nil then value = fallback or 0 end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end
local function PercentLabel(label, value)
    return M.Format("%s: %s", M.Tr(tostring(label or "")), tostring(floor(Clamp01(value, 0) * 100 + 0.5)) .. "%")
end
-- Each Party / Raid / Mythic Raid scope stores its own copy of a key: the control names the Party
-- copy and keeps the other scopes reachable through search. One write fans out over three profile
-- roots, so these rows keep whole-profile undo (historyScope = false). The Health bar color row
-- stores under a prefix that follows the bar mode; its patterns come from the Colors Meta tables.
local function GroupExact(key, kind, row)
    local exact = { historyScope = false }
    if kind == "color" and row.get then return exact end
    local suffixes = kind == "color" and { "R", "G", "B" } or { "" }
    local keys = {}
    for i = 1, #GROUP_COLOR_DB_KEYS do
        for j = 1, #suffixes do keys[#keys + 1] = GROUP_COLOR_DB_KEYS[i] .. "." .. key .. suffixes[j] end
    end
    exact.settingKey, exact.searchSettingKeys = keys[1], keys
    return exact
end
-- Rows keep the first-present/all-three group policy. The shared typed binders
-- still own input, history, combat refusal and metadata; color completion stays
-- with the canonical Colors owner instead of duplicating its reset/layout path.
local GroupRows = { bind = function(ctx, control, row, kind)
    local key, default = row[2], row[3]
    local function get()
        if row.get then return row.get() end
        if kind == "color" then return GroupRGB(key, default[1], default[2], default[3]) end
        if kind == "slider" then return GroupNum(key, default) end
        if kind == "toggle" then return GroupBool(key, default) end
        return GroupRead(key, default) or default
    end
    local function set(value, g, b)
        if row.set then return row.set(value, g, b) end
        if kind == "color" then return SetGroupRGB(key, value, g, b, row.reason or "MSUF2_GROUP_COLORS", row.mode or "visual") end
        if kind == "slider" then value = Clamp01(value, default)
        elseif kind == "toggle" then value = value and true or false
        else value = value or default end
        SetGroupValue(key, value, row.reason or "MSUF2_GROUP_COLORS", "visual")
        if row.after then row.after() end
    end
    local meta = row.meta or Meta(row.path or "group_frame.color." .. key, nil, GroupExact(key, kind, row))
    local spec = { id = meta.controlId, kind = kind, key = key, labelKey = row.label or row[4][1],
        scope = "colors", applyDomain = "groupColors", meta = meta, settingPath = meta.settingKey, get = get, set = set }
    if kind == "slider" then
        -- The live label names the slider on screen; search needs it as the label.
        meta.label = row.label
        spec.range, spec.defaultSource = { 0, 1, 0.05 }, function() return default end
    end
    Schema.Bind(ctx, control, spec)
    local p, parent = row.position, control:GetParent()
    if kind == "color" then CP.FinishColorRow(ctx, control, parent, p[1], p[2], p[3], p[4], default)
    elseif p then MoveWidget(control, parent, p[1], p[2]) end
    if kind == "slider" and M.BindSliderLiveLabel then
        M.BindSliderLiveLabel(ctx, control, get, function(value) return PercentLabel(row.label, value) end, true)
    end
end }
local function CurrentGlobalBarColor()
    local getCache = Opt.MSUF_UFCore_GetSettingsCache
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
-- Bar mode -> stored colour prefix and default RGB of the modes that own a colour.
local HEALTH_BAR_COLOR_KEYS = {
    dark = { "gfDark", 0, 0, 0 }, unified = { "gfUnified", 0.10, 0.60, 0.90 }, CUSTOM = { "healthCustom", 0.20, 0.80, 0.20 },
}
local function GroupHealthBarRGB()
    local mode = GroupBarMode()
    if mode == "GLOBAL" then return CurrentGlobalBarColor() end
    local key = HEALTH_BAR_COLOR_KEYS[mode]
    if key then return GroupRGB(key[1], key[2], key[3], key[4]) end
    return 0.20, 0.80, 0.20
end
local function SetGroupHealthBarRGB(r, g, b)
    local key = HEALTH_BAR_COLOR_KEYS[GroupBarMode()]
    if key then SetGroupRGB(key[1], r, g, b, "MSUF2_GROUP_HEALTH_COLOR", "visual") end
end
local function BuildGroupFrameColors(ctx, b)
    local pageW = b.width or ctx.width or 720
    local cardW = max(320, pageW - 32)
    local health = Schema.Section(b:CollapsibleSection("colors_group_frames", "Health Bars", 112, true), "colors")
    local background = Schema.Section(b:CollapsibleSection("colors_group_frames_background", "Bar Background", 112, false), "colors")
    local state = Schema.Section(b:CollapsibleSection("colors_group_frames_state", "State Tints", 242, false), "colors")
    local highlights = Schema.Section(b:CollapsibleSection("colors_group_frames_highlights", "Group Highlights", 220, false), "colors")
    local healerMana = Schema.Section(b:CollapsibleSection("colors_group_frames_healer_mana", "Healer mana bars", 80, false), "colors")
    Schema.Build(ctx, healerMana, {
        { "color", "healerManaText", { 1, 1, 1 }, { "Text color" }, position = { 12, -10 },
            reason = "MSUF2_GROUP_HEALER_MANA_TEXT", mode = "rebuild",
            meta = Meta("group_frame.healer_mana.text_color", nil, { settingKey = "gf_party.healerManaTextR", searchSettingKeys = {
                "gf_party.healerManaTextR", "gf_party.healerManaTextG", "gf_party.healerManaTextB",
                "gf_raid.healerManaTextR", "gf_raid.healerManaTextG", "gf_raid.healerManaTextB",
                "gf_mythicraid.healerManaTextR", "gf_mythicraid.healerManaTextG", "gf_mythicraid.healerManaTextB",
            } }) },
    }, GroupRows)
    local controls = Schema.Build(ctx, health, {
        { "dropdown", "gfBarMode", "GLOBAL", { "Bar Color Mode", GROUP_BAR_MODES, min(360, cardW - 32) },
            position = { 12, -10 }, path = "group_frame.health.mode", get = GroupBarMode, set = function(value)
                value = value or "GLOBAL"
                SetGroupValue("gfBarMode", value ~= "GLOBAL" and value or nil, "MSUF2_GROUP_HEALTH_MODE", "visual")
                if value == "CLASS" or value == "GRADIENT" then
                    SetGroupValue("healthColorMode", value, "MSUF2_GROUP_HEALTH_MODE", "visual")
                end
                if M.RequestRefresh then M.RequestRefresh(ctx, "group-colors-mode") end
            end },
        { "color", "health", nil, { "Health bar color" }, position = { 12, -64 }, path = "group_frame.health.color",
            get = GroupHealthBarRGB, set = SetGroupHealthBarRGB },
    }, GroupRows)
    Schema.Build(ctx, background, {
        { "color", "bg", { 0.10, 0.10, 0.10 }, { "Background Color" }, position = { 12, -10 } },
        { "dropdown", "healthColorMode", "CLASS", { "Health color fallback", GROUP_HEALTH_MODES, min(360, cardW - 32) },
            position = { 12, -56 }, path = "group_frame.health.fallback_mode", reason = "MSUF2_GROUP_HEALTH_FALLBACK" },
    }, GroupRows)
    local RefreshStateTintControls = M.RefreshProxy()
    Schema.Build(ctx, state, {
        { "switch", "deadBgEnabled", false, { "Dead / Offline Background", 12, -10, min(320, cardW - 32) },
            path = "group_frame.state.dead_offline.enabled", reason = "MSUF2_GROUP_DEAD_BG", after = RefreshStateTintControls },
        { "color", "deadBg", { 0.60, 0.05, 0.05 }, { "Background color" }, position = { 12, -48 } },
        { "slider", "deadBgA", 0.90, { "", 0, 1, 0.05, max(220, cardW - 58) }, position = { 12, -86 },
            label = "Dead/offline opacity", path = "group_frame.alpha.deadBgA" },
        { "flowToggle", "deadBgOffline", true, { "Also tint offline members" }, position = { 12, -132 },
            path = "group_frame.state.dead_offline.include_offline", reason = "MSUF2_GROUP_DEAD_BG_OFFLINE" },
        { "color", "debuffStripeColor", { 0.80, 0.20, 0.20 }, { "Debuff stripe color" }, position = { 12, -166 } },
        { "slider", "debuffStripeAlpha", 0.60, { "", 0, 1, 0.05, max(220, cardW - 58) }, position = { 12, -202 },
            label = "Debuff stripe opacity", path = "group_frame.alpha.debuffStripeAlpha" },
    }, GroupRows, controls)
    Schema.Build(ctx, highlights, {
        { "color", "target", { 1, 1, 1 }, { "Target Highlight Color" }, position = { 12, -10 } },
        { "color", "hlFocusColor", { 0.50, 0.50, 1.00 }, { "Focus Highlight Color" }, position = { 12, -48 } },
        { "color", "groupBorder", { 0.38, 0.68, 1.00 }, { "Group Border Color" }, position = { 12, -86 } },
        { "slider", "groupBorderA", 0.95, { "", 0, 1, 0.05, max(220, cardW - 58) }, position = { 12, -128 },
            label = "Group border opacity", path = "group_frame.alpha.groupBorderA" },
        { "color", "ciAggroColor", { 1.00, 0.55, 0.00 }, { "Corner aggro color" }, position = { 12, -174 } },
    }, GroupRows)
    RefreshStateTintControls = RefreshStateTintControls(M.BindGateGroup(ctx, nil, {
        { controls = controls.health, on = function()
            local current = GroupBarMode()
            return current == "dark" or current == "unified" or current == "CUSTOM"
        end },
        { controls = { controls.deadBg, controls.deadBgA, controls.deadBgOffline }, on = function() return GroupBool("deadBgEnabled", false) end },
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
CP.HealerManaTextRGB = HealerManaTextRGB
CP.SetHealerManaTextRGB = SetHealerManaTextRGB
CP.ApplyHealerManaText = ApplyHealerManaText
CP.BuildGroupFrameColors = BuildGroupFrameColors
