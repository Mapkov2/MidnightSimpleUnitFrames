local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry or { settings = {}, settingsByKey = {}, actions = {}, actionsByKey = {}, todos = {} }
A.Registry = Registry
A.Workflow = A.Workflow or {}

local C = A.RegistryCore
if type(C) ~= "table" then return end

-- GroupFrames registry domain. Shared helpers live in MSUF_AssistantRegistry_Core.lua.
local Registry = C.Registry
local UNIT_LABELS = C.UNIT_LABELS
local AddAliasesForUnit = C.AddAliasesForUnit
local GroupDB = C.GroupDB
local ClampNumber = C.ClampNumber
local ApplyGroup = C.ApplyGroup

do
local function RegisterGroupBoolean(scope, attr, dbKey, label, defaultValue, mode, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "gf_" .. scope .. "." .. dbKey,
        label = UNIT_LABELS[scope] .. " " .. label,
        category = UNIT_LABELS[scope] .. " / Group Frames",
        unit = scope,
        frameType = "group",
        attribute = attr,
        type = "boolean",
        aliases = aliases,
        get = function()
            if opts.get then return opts.get(scope) end
            local value = GroupDB(scope)[dbKey]
            if value == nil then return defaultValue and true or false end
            return value and true or false
        end,
        set = function(value)
            if opts.set then opts.set(scope, value); return end
            GroupDB(scope)[dbKey] = value and true or false
        end,
        apply = function() ApplyGroup(scope, opts.mode or mode or "visual") end,
        combatSafe = false,
    })
end

local function RegisterGroupNumber(scope, attr, dbKey, label, defaultValue, minValue, maxValue, step, mode, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "gf_" .. scope .. "." .. dbKey,
        label = UNIT_LABELS[scope] .. " " .. label,
        category = UNIT_LABELS[scope] .. " / Group Frames",
        unit = scope,
        frameType = "group",
        attribute = attr,
        type = "number",
        aliases = aliases,
        min = minValue,
        max = maxValue,
        step = step or 1,
        percent = opts.percent == true,
        get = function()
            if opts.get then return opts.get(scope) end
            local value = tonumber(GroupDB(scope)[dbKey])
            if value == nil then return defaultValue end
            return value
        end,
        set = function(value)
            if opts.set then opts.set(scope, value); return end
            GroupDB(scope)[dbKey] = ClampNumber(value, minValue, maxValue, step or 1)
        end,
        apply = function() ApplyGroup(scope, opts.mode or mode or "visual") end,
        combatSafe = false,
    })
end

local function RegisterGroupEnum(scope, attr, dbKey, label, defaultValue, values, valueAliases, mode, aliases, opts)
    opts = opts or {}
    local allowed = {}
    for i = 1, #(values or {}) do allowed[values[i]] = true end
    Registry:RegisterSetting({
        key = "gf_" .. scope .. "." .. dbKey,
        label = UNIT_LABELS[scope] .. " " .. label,
        category = UNIT_LABELS[scope] .. " / Group Frames",
        unit = scope,
        frameType = "group",
        attribute = attr,
        type = "enum",
        aliases = aliases,
        values = values,
        valueAliases = valueAliases,
        get = function()
            if opts.get then return opts.get(scope) end
            local value = GroupDB(scope)[dbKey]
            if allowed[value] then return value end
            return defaultValue
        end,
        set = function(value)
            if opts.set then opts.set(scope, value); return end
            if not allowed[value] then value = defaultValue end
            GroupDB(scope)[dbKey] = value
        end,
        apply = function() ApplyGroup(scope, opts.mode or mode or "visual") end,
        combatSafe = false,
    })
end

local function RegisterGroupString(scope, attr, dbKey, label, defaultValue, mode, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "gf_" .. scope .. "." .. dbKey,
        label = UNIT_LABELS[scope] .. " " .. label,
        category = UNIT_LABELS[scope] .. " / Group Frames",
        unit = scope,
        frameType = "group",
        attribute = attr,
        type = "string",
        aliases = aliases,
        valuePrefixes = opts.valuePrefixes or aliases,
        mediaType = opts.mediaType,
        get = function()
            if opts.get then return opts.get(scope) end
            local value = GroupDB(scope)[dbKey]
            if type(value) ~= "string" or value == "" then return defaultValue or "" end
            return value
        end,
        set = function(value)
            if opts.set then opts.set(scope, value); return end
            GroupDB(scope)[dbKey] = tostring(value or "")
        end,
        apply = function() ApplyGroup(scope, opts.mode or mode or "visual") end,
        combatSafe = false,
        description = opts.description,
    })
end

local function GroupClamp01(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback or 0 end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function GroupAlphaKeysForMode(mode)
    if mode == "background" then return "alphaBGInCombat", "alphaBGOutOfCombat" end
    if mode == "health" then return "alphaHPInCombat", "alphaHPOutOfCombat" end
    if mode == "foreground" then return "alphaFGInCombat", "alphaFGOutOfCombat" end
    return "alphaInCombat", "alphaOutOfCombat"
end

local function GroupOpacityMode(scope)
    local conf = GroupDB(scope)
    if conf.alphaExcludeTextPortrait == true then
        local mode = conf.alphaLayerMode
        if mode == 1 or mode == "background" then return "background" end
        if mode == 2 or mode == "health" or mode == "hp" or mode == "hpbar" then return "health" end
        return "foreground"
    end
    return "frame"
end

local function GroupCurrentAlphaKeys(scope)
    return GroupAlphaKeysForMode(GroupOpacityMode(scope))
end

local function GroupReadAlpha(scope, inCombat)
    local conf = GroupDB(scope)
    local inKey, outKey = GroupCurrentAlphaKeys(scope)
    local key = inCombat and inKey or outKey
    local value = tonumber(conf[key])
    if value ~= nil then return value end
    if conf.alphaExcludeTextPortrait == true then return 1 end
    return tonumber(conf[inCombat and "alphaInCombat" or "alphaOutOfCombat"]) or 1
end

local function GroupWriteAlpha(scope, inCombat, value)
    local conf = GroupDB(scope)
    local inKey, outKey = GroupCurrentAlphaKeys(scope)
    value = GroupClamp01(value, 1)
    if inCombat then
        conf[inKey] = value
        if conf.alphaSync == true then conf[outKey] = value end
    else
        conf[outKey] = value
    end
end

local function GroupAlphaModeValue(mode)
    if mode == "background" then return 1 end
    if mode == "health" then return 2 end
    return 0
end

local function GroupSetOpacityMode(scope, mode)
    local conf = GroupDB(scope)
    local inValue = GroupReadAlpha(scope, true)
    local outValue = GroupReadAlpha(scope, false)
    if mode == "frame" then
        conf.alphaExcludeTextPortrait = false
        return
    end
    mode = (mode == "background" or mode == "health" or mode == "foreground") and mode or "foreground"
    conf.alphaExcludeTextPortrait = true
    conf.alphaLayerMode = GroupAlphaModeValue(mode)
    local syncedOut = conf.alphaSync == true and inValue or outValue
    local fgIn, fgOut = GroupAlphaKeysForMode("foreground")
    local hpIn, hpOut = GroupAlphaKeysForMode("health")
    local bgIn, bgOut = GroupAlphaKeysForMode("background")
    conf[fgIn], conf[fgOut] = mode == "foreground" and inValue or 1, mode == "foreground" and syncedOut or 1
    conf[hpIn], conf[hpOut] = mode == "health" and inValue or 1, mode == "health" and syncedOut or 1
    conf[bgIn], conf[bgOut] = mode == "background" and inValue or 1, mode == "background" and syncedOut or 1
end

local function NormalizeGroupRoleOrder(value)
    local labels = { tank = "TANK", tanks = "TANK", healer = "HEALER", healers = "HEALER", heal = "HEALER", dps = "DAMAGER", damage = "DAMAGER", damager = "DAMAGER", damagers = "DAMAGER", dd = "DAMAGER" }
    local seen, out = {}, {}
    for token in tostring(value or ""):gmatch("[^,%s/|>%+%-]+") do
        local upper = tostring(token or ""):upper()
        local mapped = labels[tostring(token or ""):lower()] or upper
        if mapped == "MELEE" or mapped == "RANGED" then mapped = "DAMAGER" end
        if (mapped == "TANK" or mapped == "HEALER" or mapped == "DAMAGER") and not seen[mapped] then
            seen[mapped] = true
            out[#out + 1] = mapped
        end
    end
    if not seen.TANK then out[#out + 1] = "TANK" end
    if not seen.HEALER then out[#out + 1] = "HEALER" end
    if not seen.DAMAGER then out[#out + 1] = "DAMAGER" end
    return table.concat(out, ",")
end

local function TrimString(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function StandardGroupAnchorTarget(value)
    return value == nil or value == "" or value == "FREE" or value == "player" or value == "target"
        or value == "targettarget" or value == "focustarget" or value == "focus"
end

local function GroupColorSame(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    local ar, ag, ab = tonumber(a.r or a[1]) or 0, tonumber(a.g or a[2]) or 0, tonumber(a.b or a[3]) or 0
    local br, bg, bb = tonumber(b.r or b[1]) or 0, tonumber(b.g or b[2]) or 0, tonumber(b.b or b[3]) or 0
    return math.abs(ar - br) < 0.0005 and math.abs(ag - bg) < 0.0005 and math.abs(ab - bb) < 0.0005
end

local function RegisterGroupColor(scope, attr, keyPrefix, label, dr, dg, db, aliases)
    local settingKey = keyPrefix:match("Color$") and keyPrefix or (keyPrefix .. "Color")
    Registry:RegisterSetting({
        key = "gf_" .. scope .. "." .. settingKey,
        label = UNIT_LABELS[scope] .. " " .. label,
        category = UNIT_LABELS[scope] .. " / Group Frames",
        unit = scope,
        frameType = "group",
        attribute = attr,
        type = "color",
        aliases = aliases,
        get = function()
            local conf = GroupDB(scope)
            return { r = tonumber(conf[keyPrefix .. "R"]) or dr, g = tonumber(conf[keyPrefix .. "G"]) or dg, b = tonumber(conf[keyPrefix .. "B"]) or db }
        end,
        set = function(value)
            local conf = GroupDB(scope)
            conf[keyPrefix .. "R"] = GroupClamp01(type(value) == "table" and (value.r or value[1]) or dr, dr)
            conf[keyPrefix .. "G"] = GroupClamp01(type(value) == "table" and (value.g or value[2]) or dg, dg)
            conf[keyPrefix .. "B"] = GroupClamp01(type(value) == "table" and (value.b or value[3]) or db, db)
        end,
        sameValue = GroupColorSame,
        apply = function() ApplyGroup(scope, "visual") end,
        combatSafe = false,
    })
end

local function GetGroupHealthBarColor(scope)
    local conf = GroupDB(scope)
    local mode = conf.gfBarMode
    local prefix, dr, dg, db
    if mode == "dark" then
        prefix, dr, dg, db = "gfDark", 0, 0, 0
    elseif mode == "unified" then
        prefix, dr, dg, db = "gfUnified", 0.10, 0.60, 0.90
    else
        prefix, dr, dg, db = "healthCustom", 0.20, 0.80, 0.20
    end
    return {
        r = tonumber(conf[prefix .. "R"]) or dr,
        g = tonumber(conf[prefix .. "G"]) or dg,
        b = tonumber(conf[prefix .. "B"]) or db,
    }
end

local function SetGroupHealthBarColor(scope, value)
    local conf = GroupDB(scope)
    local mode = conf.gfBarMode
    local prefix, dr, dg, db
    if mode == "dark" then
        prefix, dr, dg, db = "gfDark", 0, 0, 0
    elseif mode == "unified" then
        prefix, dr, dg, db = "gfUnified", 0.10, 0.60, 0.90
    else
        conf.gfBarMode = "CUSTOM"
        conf.healthColorMode = "CUSTOM"
        prefix, dr, dg, db = "healthCustom", 0.20, 0.80, 0.20
    end
    conf[prefix .. "R"] = GroupClamp01(type(value) == "table" and (value.r or value[1]) or dr, dr)
    conf[prefix .. "G"] = GroupClamp01(type(value) == "table" and (value.g or value[2]) or dg, dg)
    conf[prefix .. "B"] = GroupClamp01(type(value) == "table" and (value.b or value[3]) or db, db)
end

local GROUP_BAR_MODE_VALUES = { "GLOBAL", "CLASS", "dark", "unified", "GRADIENT", "CUSTOM" }
local GROUP_HEALTH_MODE_VALUES = { "CLASS", "GRADIENT", "CUSTOM" }
local GROUP_TEXT_MODE_VALUES = {
    "NONE", "PERCENT", "CURRENT", "MAX", "DEFICIT", "CURMAX", "CURPERCENT",
    "CURMAXPERCENT", "MAXPERCENT", "PERCENTCUR", "PERCENTMAX", "PERCENTCURMAX",
}
local GROUP_ANCHOR_VALUES = { "LEFT", "CENTER", "RIGHT" }
local GROUP_CORNER_ANCHOR_VALUES = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local GROUP_DISPEL_TRIGGER_VALUES = { "BORDER", "BY_ME", "DISPEL_TYPE", "ANY_DEBUFF" }
local GROUP_DISPEL_STYLE_VALUES = { "FULL", "BOTTOM", "TOP", "LEFT", "RIGHT" }
local GROUP_STRIPE_EDGE_VALUES = { "BOTTOM", "TOP" }
local GROUP_RANGE_LAYER_VALUES = { "frame", "health" }
local GROUP_DELIMITER_VALUES = { " ", "  ", " / ", " - ", " : ", " | " }
local GROUP_STATUS_ICON_STYLE_VALUES = { "BLIZZARD", "CLASSIC", "MIDNIGHT" }
local GROUP_STATUS_ICON_PACK_VALUES = { "DEFAULT", "BLIZZARD", "CLASSIC", "MIDNIGHT" }
local GROUP_STATUS_ANCHOR_VALUES = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT" }

local GROUP_TEXT_MODE_ALIASES = {
    none = "NONE",
    off = "NONE",
    hide = "NONE",
    hidden = "NONE",
    percent = "PERCENT",
    percentage = "PERCENT",
    pct = "PERCENT",
    current = "CURRENT",
    cur = "CURRENT",
    value = "CURRENT",
    max = "MAX",
    maximum = "MAX",
    deficit = "DEFICIT",
    missing = "DEFICIT",
    curmax = "CURMAX",
    currentmax = "CURMAX",
    ["current max"] = "CURMAX",
    curpercent = "CURPERCENT",
    currentpercent = "CURPERCENT",
    ["current percent"] = "CURPERCENT",
    curmaxpercent = "CURMAXPERCENT",
    ["current max percent"] = "CURMAXPERCENT",
    maxpercent = "MAXPERCENT",
    ["max percent"] = "MAXPERCENT",
    percentcur = "PERCENTCUR",
    ["percent current"] = "PERCENTCUR",
    percentmax = "PERCENTMAX",
    ["percent max"] = "PERCENTMAX",
    percentcurmax = "PERCENTCURMAX",
    ["percent current max"] = "PERCENTCURMAX",
}

local GROUP_DELIMITER_ALIASES = {
    space = " ",
    single = " ",
    doublespace = "  ",
    ["double space"] = "  ",
    slash = " / ",
    forwardslash = " / ",
    ["forward slash"] = " / ",
    hyphen = " - ",
    dash = " - ",
    minus = " - ",
    colon = " : ",
    pipe = " | ",
    verticalbar = " | ",
    ["vertical bar"] = " | ",
}

local GROUP_ANCHOR_ALIASES = {
    left = "LEFT",
    center = "CENTER",
    centre = "CENTER",
    middle = "CENTER",
    right = "RIGHT",
}

local GROUP_CORNER_ANCHOR_ALIASES = {
    topleft = "TOPLEFT",
    ["top left"] = "TOPLEFT",
    top = "TOPLEFT",
    topright = "TOPRIGHT",
    ["top right"] = "TOPRIGHT",
    bottomleft = "BOTTOMLEFT",
    ["bottom left"] = "BOTTOMLEFT",
    bottom = "BOTTOMRIGHT",
    bottomright = "BOTTOMRIGHT",
    ["bottom right"] = "BOTTOMRIGHT",
}

local GROUP_STATUS_ANCHOR_ALIASES = {
    topleft = "TOPLEFT",
    ["top left"] = "TOPLEFT",
    topright = "TOPRIGHT",
    ["top right"] = "TOPRIGHT",
    bottomleft = "BOTTOMLEFT",
    ["bottom left"] = "BOTTOMLEFT",
    bottomright = "BOTTOMRIGHT",
    ["bottom right"] = "BOTTOMRIGHT",
    center = "CENTER",
    centre = "CENTER",
    middle = "CENTER",
    top = "TOP",
    bottom = "BOTTOM",
    left = "LEFT",
    right = "RIGHT",
}

local GROUP_STATUS_ICON_STYLE_ALIASES = {
    blizzard = "BLIZZARD",
    default = "BLIZZARD",
    classic = "CLASSIC",
    old = "CLASSIC",
    midnight = "MIDNIGHT",
    msuf = "MIDNIGHT",
}

local GROUP_STATUS_ICON_PACK_ALIASES = {
    inherit = "DEFAULT",
    global = "DEFAULT",
    default = "DEFAULT",
    ["follow global"] = "DEFAULT",
    blizzard = "BLIZZARD",
    classic = "CLASSIC",
    old = "CLASSIC",
    midnight = "MIDNIGHT",
    msuf = "MIDNIGHT",
}

local GROUP_STATUS_ICON_SPECS = {
    { value = "roleIcon", label = "Role Icon", enabled = "roleIcon", iconStyle = "roleIconStyle", size = "roleIconSize", anchor = "roleIconAnchor", x = "roleIconX", y = "roleIconY", layer = "roleIconLayer", defaultSize = 12, defaultAnchor = "TOPLEFT", defaultLayer = 1, terms = { "role icon", "role indicator", "role symbol" } },
    { value = "leaderIcon", label = "Leader Icon", enabled = "leaderIcon", iconStyle = "leaderIconStyle", size = "leaderIconSize", anchor = "leaderIconAnchor", x = "leaderIconX", y = "leaderIconY", layer = "leaderIconLayer", defaultSize = 12, defaultAnchor = "TOPRIGHT", defaultLayer = 2, terms = { "leader icon", "leader indicator", "leader symbol" } },
    { value = "assistIcon", label = "Assist Icon", enabled = "assistIcon", iconStyle = "assistIconStyle", size = "assistIconSize", anchor = "assistIconAnchor", x = "assistIconX", y = "assistIconY", layer = "assistIconLayer", defaultSize = 12, defaultAnchor = "TOPRIGHT", defaultLayer = 2, terms = { "assist icon", "assistant icon", "assist indicator", "assistant indicator", "assist symbol", "assistant symbol" } },
    { value = "raidMarker", label = "Raid Marker", enabled = "raidMarker", size = "raidMarkerSize", anchor = "raidMarkerAnchor", x = "raidMarkerX", y = "raidMarkerY", layer = "raidMarkerLayer", defaultSize = 14, defaultAnchor = "CENTER", defaultLayer = 3, terms = { "raid marker", "raid marker icon", "raid marker indicator", "raid marker symbol", "target marker", "target marker icon", "target marker indicator", "target marker symbol" } },
    { value = "readyCheckIcon", label = "Ready Check Icon", enabled = "readyCheckIcon", size = "readyCheckSize", anchor = "readyCheckAnchor", x = "readyCheckX", y = "readyCheckY", layer = "readyCheckLayer", defaultSize = 16, defaultAnchor = "CENTER", defaultLayer = 4, terms = { "ready check", "ready check icon", "ready check indicator", "ready check symbol", "ready icon", "ready indicator", "ready symbol" } },
    { value = "summonIcon", label = "Summon Icon", enabled = "summonIcon", size = "summonIconSize", anchor = "summonAnchor", x = "summonX", y = "summonY", layer = "summonLayer", defaultSize = 16, defaultAnchor = "CENTER", defaultLayer = 4, terms = { "summon icon", "summon indicator", "summon symbol" } },
    { value = "resurrectIcon", label = "Resurrect Icon", enabled = "resurrectIcon", size = "resurrectIconSize", anchor = "resurrectAnchor", x = "resurrectX", y = "resurrectY", layer = "resurrectLayer", defaultSize = 16, defaultAnchor = "CENTER", defaultLayer = 4, terms = { "resurrect icon", "resurrect indicator", "resurrect symbol", "resurrection icon", "resurrection indicator", "resurrection symbol", "rez icon", "rez indicator", "rez symbol", "incoming resurrection", "incoming resurrection icon", "incoming resurrection indicator", "incoming resurrection symbol" } },
    { value = "phaseIcon", label = "Phase Icon", enabled = "phaseIcon", size = "phaseIconSize", anchor = "phaseAnchor", x = "phaseX", y = "phaseY", layer = "phaseLayer", defaultSize = 14, defaultAnchor = "TOPLEFT", defaultLayer = 3, terms = { "phase icon", "phasing icon", "phase indicator", "phasing indicator", "phase symbol", "phasing symbol" } },
    { value = "statusText", label = "Dead Text", enabled = "statusText", size = "statusTextSize", anchor = "statusTextAnchor", x = "statusOffsetX", y = "statusOffsetY", layer = "statusTextLayer", defaultSize = 14, defaultAnchor = "CENTER", defaultLayer = 7, terms = { "dead text", "dead status text", "status text" } },
    { value = "statusGhostText", label = "Ghost Text", enabled = "statusGhostText", size = "statusGhostTextSize", anchor = "statusGhostTextAnchor", x = "statusGhostOffsetX", y = "statusGhostOffsetY", layer = "statusGhostTextLayer", defaultSize = 14, defaultAnchor = "CENTER", defaultLayer = 7, terms = { "ghost text", "ghost status text" } },
    { value = "statusAFKText", label = "AFK DND Text", enabled = "statusAFKText", size = "statusAFKTextSize", anchor = "statusAFKTextAnchor", x = "statusAFKOffsetX", y = "statusAFKOffsetY", layer = "statusAFKTextLayer", defaultSize = 14, defaultAnchor = "CENTER", defaultLayer = 7, terms = { "afk text", "dnd text", "afk dnd text", "away text" } },
}

local function NormalizeGroupTextureName(value)
    value = TrimString(value)
    local lower = value:lower()
    if lower == "" or lower == "global" or lower == "follow global" or lower == "global style" then return "" end
    if lower == "default" or lower == "inherit" or lower == "inherited" then return "" end
    return value
end

local function NormalizeGroupDispelTrigger(value)
    if value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then return "DISPEL_TYPE" end
    if value == "ANY_DEBUFF" or value == "DEBUFF" or value == "ANY" or value == "ALL_DEBUFFS" then return "ANY_DEBUFF" end
    if value == "BY_ME" or value == "PLAYER" or value == "DISPELLABLE_BY_ME" then return "BY_ME" end
    return "BORDER"
end

local function RegisterGroupTexture(scope, attr, dbKey, label, aliases)
    RegisterGroupString(scope, attr, dbKey, label, "", "visual", aliases, {
        set = function(scopeKey, value) GroupDB(scopeKey)[dbKey] = NormalizeGroupTextureName(value) end,
        description = "Sets the group-frame texture name, or clears it to follow the global style.",
    })
end

local function RegisterGroupTextMode(scope, attr, dbKey, label, defaultValue, aliases)
    RegisterGroupEnum(scope, attr, dbKey, label, defaultValue or "NONE", GROUP_TEXT_MODE_VALUES, GROUP_TEXT_MODE_ALIASES, "visual", aliases)
end

local function RegisterGroupDelimiter(scope, attr, dbKey, label, aliases)
    RegisterGroupEnum(scope, attr, dbKey, label, " / ", GROUP_DELIMITER_VALUES, GROUP_DELIMITER_ALIASES, "visual", aliases)
end

local function AddGroupStatusIconAliases(out, scope, spec, suffix)
    for i = 1, #(spec.terms or {}) do
        local term = spec.terms[i]
        local alias = suffix and (term .. " " .. suffix) or term
        out[#out + 1] = alias
        AddAliasesForUnit(out, scope, alias)
        if suffix then
            local prefixAlias = suffix .. " " .. term
            out[#out + 1] = prefixAlias
            AddAliasesForUnit(out, scope, prefixAlias)
        end
    end
end

local GROUP_STATUS_ICON_LOOKUP = {}
for i = 1, #GROUP_STATUS_ICON_SPECS do
    local spec = GROUP_STATUS_ICON_SPECS[i]
    GROUP_STATUS_ICON_LOOKUP[spec.value:lower()] = spec
    GROUP_STATUS_ICON_LOOKUP[tostring(spec.label or ""):lower():gsub("[^%w]+", "")] = spec
    for j = 1, #(spec.terms or {}) do
        GROUP_STATUS_ICON_LOOKUP[spec.terms[j]:lower():gsub("[^%w]+", "")] = spec
    end
end

local function ResolveGroupStatusIcon(value)
    local key = tostring(value or ""):lower():gsub("[^%w]+", "")
    return GROUP_STATUS_ICON_LOOKUP[key]
end

local function ResetGroupStatusIcon(scope, spec)
    if not spec then return false end
    local conf = GroupDB(scope)
    for _, key in ipairs({ spec.size, spec.anchor, spec.x, spec.y, spec.layer, spec.iconStyle }) do
        if key then conf[key] = nil end
    end
    ApplyGroup(scope, "visual")
    return true
end

for _, scope in ipairs({ "party", "raid", "mythicraid" }) do
    local aliases = {}
    AddAliasesForUnit(aliases, scope, "frames", "frames")
    AddAliasesForUnit(aliases, scope, "group frames", "gruppenframes")
    RegisterGroupBoolean(scope, "enabled", "enabled", "Frames Enabled", false, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "range fade", "range fade")
    AddAliasesForUnit(aliases, scope, "range fading", "reichweite fade")
    RegisterGroupBoolean(scope, "rangeFade", "rangeFadeEnabled", "Range Fade", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "show player", "spieler anzeigen")
    AddAliasesForUnit(aliases, scope, "player in group", "spieler in gruppe")
    AddAliasesForUnit(aliases, scope, "player in group frames")
    AddAliasesForUnit(aliases, scope, "show player in group")
    AddAliasesForUnit(aliases, scope, "show player in group frames")
    AddAliasesForUnit(aliases, scope, "show player when solo")
    AddAliasesForUnit(aliases, scope, "show player in group when solo")
    RegisterGroupBoolean(scope, "showPlayer", "showPlayer", "Show Player", true, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "show solo", "solo anzeigen")
    AddAliasesForUnit(aliases, scope, "solo mode", "solo modus")
    AddAliasesForUnit(aliases, scope, "show while solo")
    AddAliasesForUnit(aliases, scope, "show group while solo")
    AddAliasesForUnit(aliases, scope, "show group frames while solo")
    RegisterGroupBoolean(scope, "showSolo", "showSolo", "Show While Solo", false, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "click casting", "klick zauber")
    AddAliasesForUnit(aliases, scope, "clique", "clique")
    RegisterGroupBoolean(scope, "clickCast", "clickCastEnabled", "Click Casting", true, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "blizzard fallback", "blizzard fallback")
    AddAliasesForUnit(aliases, scope, "fallback mode", "fallback modus")
    AddAliasesForUnit(aliases, scope, "disabled group frame behavior")
    RegisterGroupEnum(scope, "blizzardFallbackMode", "blizzardFallbackMode", "Blizzard Fallback Mode", "AUTO", { "AUTO", "SHOW", "NONE" }, {
        auto = "AUTO",
        automatic = "AUTO",
        default = "AUTO",
        blizzarddefault = "AUTO",
        ["blizzard default"] = "AUTO",
        show = "SHOW",
        force = "SHOW",
        forceblizzard = "SHOW",
        ["force blizzard"] = "SHOW",
        forceblizzardframes = "SHOW",
        hide = "NONE",
        none = "NONE",
        off = "NONE",
        hideall = "NONE",
        ["hide all"] = "NONE",
    }, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hide during client scene", "client szene ausblenden")
    AddAliasesForUnit(aliases, scope, "hide in client scene")
    RegisterGroupBoolean(scope, "hideInClientScene", "hideInClientScene", "Hide During Client Scene", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hide offline members", "offline spieler ausblenden")
    AddAliasesForUnit(aliases, scope, "offline members")
    RegisterGroupBoolean(scope, "hideOfflineEnabled", "hideOfflineEnabled", "Hide Offline Members", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hide offline in combat", "offline im kampf ausblenden")
    AddAliasesForUnit(aliases, scope, "combat offline hide")
    RegisterGroupBoolean(scope, "hideOfflineInCombat", "hideOfflineInCombat", "Hide Offline In Combat", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hide offline delay", "offline ausblenden verzoegerung")
    AddAliasesForUnit(aliases, scope, "hide offline after")
    AddAliasesForUnit(aliases, scope, "offline delay")
    RegisterGroupNumber(scope, "hideOfflineDelay", "hideOfflineDelay", "Hide Offline Delay", 0, 0, 120, 1, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "smooth fill", "weiche fuellung")
    AddAliasesForUnit(aliases, scope, "smooth health", "weiche leben")
    RegisterGroupBoolean(scope, "smoothFill", "smoothFill", "Smooth Health Fill", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "reverse fill", "fuellung umkehren")
    AddAliasesForUnit(aliases, scope, "reverse health fill", "leben umkehren")
    RegisterGroupBoolean(scope, "reverseFill", "reverseFill", "Reverse Health Fill", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "name", "name")
    AddAliasesForUnit(aliases, scope, "names", "namen")
    RegisterGroupBoolean(scope, "name", "showName", "Names", true, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp text", "leben text")
    AddAliasesForUnit(aliases, scope, "health text", "gesundheit text")
    RegisterGroupBoolean(scope, "hpText", "showHPText", "HP Text", true, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power text", "power text")
    AddAliasesForUnit(aliases, scope, "mana text", "mana text")
    Registry:RegisterSetting({
        key = "gf_" .. scope .. ".showPowerText",
        label = UNIT_LABELS[scope] .. " Power Text",
        category = UNIT_LABELS[scope] .. " / Group Frames",
        unit = scope,
        frameType = "group",
        attribute = "powerText",
        type = "boolean",
        aliases = aliases,
        get = function()
            local db = GroupDB(scope)
            return db.showPowerText == true or db.showPower == true
        end,
        set = function(value)
            local enabled = value and true or false
            local db = GroupDB(scope)
            db.showPowerText = enabled
            db.showPower = enabled
        end,
        apply = function() ApplyGroup(scope, "font") end,
        combatSafe = false,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power bar", "power balken")
    AddAliasesForUnit(aliases, scope, "mana bar", "mana balken")
    RegisterGroupBoolean(scope, "powerBar", "powerBarEnabled", "Power Bar", true, "rebuild", aliases)

    local widthDefault = scope == "party" and 120 or 80
    local heightDefault = scope == "party" and 40 or 32
    local powerHeightDefault = scope == "party" and 6 or 4
    local hpFontDefault = scope == "party" and 10 or 9
    local nameFontDefault = scope == "party" and 12 or 10
    local textCenterDefault = scope == "party" and "PERCENT" or "NONE"
    local maxColumnsDefault = scope == "party" and 1 or 8

    aliases = {}
    AddAliasesForUnit(aliases, scope, "width", "breite")
    AddAliasesForUnit(aliases, scope, "frame width", "frame breite")
    RegisterGroupNumber(scope, "width", "width", "Width", widthDefault, 40, 300, 1, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "height", "hoehe")
    AddAliasesForUnit(aliases, scope, "frame height", "frame hoehe")
    RegisterGroupNumber(scope, "height", "height", "Height", heightDefault, 16, 120, 1, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "spacing", "abstand")
    AddAliasesForUnit(aliases, scope, "frame spacing", "frame abstand")
    RegisterGroupNumber(scope, "spacing", "spacing", "Spacing", 1, 0, 20, 1, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "units per column", "einheiten pro spalte")
    AddAliasesForUnit(aliases, scope, "members per column", "spieler pro spalte")
    RegisterGroupNumber(scope, "unitsPerColumn", "unitsPerColumn", "Units Per Column", 5, 1, 40, 1, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "max columns", "max spalten")
    AddAliasesForUnit(aliases, scope, "columns", "spalten")
    RegisterGroupNumber(scope, "maxColumns", "maxColumns", "Max Columns", maxColumnsDefault, 1, 8, 1, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "preserve raid groups", "raid gruppen beibehalten")
    AddAliasesForUnit(aliases, scope, "keep raid groups")
    RegisterGroupBoolean(scope, "preserveRaidGroups", "preserveRaidGroups", "Preserve Raid Groups", false, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power height", "power hoehe")
    AddAliasesForUnit(aliases, scope, "power bar height", "power balken hoehe")
    RegisterGroupNumber(scope, "powerHeight", "powerHeight", "Power Bar Height", powerHeightDefault, 0, 30, 1, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "name font size", "name schriftgroesse")
    AddAliasesForUnit(aliases, scope, "name size", "name groesse")
    RegisterGroupNumber(scope, "nameFontSize", "nameFontSize", "Name Font Size", nameFontDefault, 6, 24, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp font size", "leben schriftgroesse")
    AddAliasesForUnit(aliases, scope, "health font size", "gesundheit schriftgroesse")
    RegisterGroupNumber(scope, "hpFontSize", "hpFontSize", "HP Font Size", hpFontDefault, 6, 24, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power font size", "power schriftgroesse")
    AddAliasesForUnit(aliases, scope, "mana font size", "mana schriftgroesse")
    RegisterGroupNumber(scope, "powerFontSize", "powerFontSize", "Power Font Size", 9, 6, 24, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "name max chars", "name max zeichen")
    AddAliasesForUnit(aliases, scope, "name length", "name laenge")
    RegisterGroupNumber(scope, "nameMaxChars", "nameMaxChars", "Name Max Characters", 0, 0, 30, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "shorten group names")
    AddAliasesForUnit(aliases, scope, "shorten names")
    AddAliasesForUnit(aliases, scope, "name shortening")
    RegisterGroupBoolean(scope, "nameShortening", "nameShortenEnabled", "Name Shortening", false, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "name truncation style")
    AddAliasesForUnit(aliases, scope, "truncation style")
    AddAliasesForUnit(aliases, scope, "name clip side")
    RegisterGroupEnum(scope, "nameClipSide", "nameClipSide", "Name Truncation Style", "RIGHT", { "LEFT", "RIGHT" }, {
        left = "LEFT",
        endletters = "LEFT",
        ["keep end"] = "LEFT",
        right = "RIGHT",
        startletters = "RIGHT",
        ["keep start"] = "RIGHT",
    }, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "no ellipsis")
    AddAliasesForUnit(aliases, scope, "name no ellipsis")
    AddAliasesForUnit(aliases, scope, "truncate without dots")
    RegisterGroupBoolean(scope, "nameNoEllipsis", "nameNoEllipsis", "Name No Ellipsis", false, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "range fade alpha", "reichweite fade alpha")
    AddAliasesForUnit(aliases, scope, "out of range alpha", "ausser reichweite alpha")
    RegisterGroupNumber(scope, "rangeFadeAlpha", "rangeFadeAlpha", "Range Fade Alpha", 0.4, 0, 1, 0.05, "visual", aliases, { percent = true })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "growth", "wachstum")
    AddAliasesForUnit(aliases, scope, "growth direction", "wachstumsrichtung")
    AddAliasesForUnit(aliases, scope, "grow")
    AddAliasesForUnit(aliases, scope, "to grow")
    AddAliasesForUnit(aliases, scope, "grow direction")
    AddAliasesForUnit(aliases, scope, "frames grow")
    AddAliasesForUnit(aliases, scope, "frames to grow")
    RegisterGroupEnum(scope, "growth", "growth", "Growth Direction", "DOWN", { "DOWN", "UP", "RIGHT", "LEFT" }, {
        down = "DOWN",
        runter = "DOWN",
        unten = "DOWN",
        up = "UP",
        hoch = "UP",
        oben = "UP",
        right = "RIGHT",
        rechts = "RIGHT",
        left = "LEFT",
        links = "LEFT",
    }, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "health text center", "leben text mitte")
    AddAliasesForUnit(aliases, scope, "hp text center", "hp text mitte")
    AddAliasesForUnit(aliases, scope, "center text", "text mitte")
    AddAliasesForUnit(aliases, scope, "center hp text", "hp text mitte")
    RegisterGroupEnum(scope, "healthTextCenter", "textCenter", "Center HP Text", textCenterDefault, { "NONE", "PERCENT", "CURRENT", "MAX", "DEFICIT", "CURMAX", "CURPERCENT", "CURMAXPERCENT", "MAXPERCENT", "PERCENTCUR", "PERCENTMAX", "PERCENTCURMAX" }, {
        none = "NONE",
        off = "NONE",
        aus = "NONE",
        percent = "PERCENT",
        percentage = "PERCENT",
        prozent = "PERCENT",
        current = "CURRENT",
        aktuell = "CURRENT",
        max = "MAX",
        deficit = "DEFICIT",
        missing = "DEFICIT",
        curmax = "CURMAX",
        currentmax = "CURMAX",
        currentpercent = "CURPERCENT",
        currentpercentage = "CURPERCENT",
    }, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "sort mode", "sortierung")
    AddAliasesForUnit(aliases, scope, "sort order", "sortiermodus")
    RegisterGroupEnum(scope, "sortMode", "sortMode", "Sort Mode", "INDEX", { "INDEX", "ROLE", "GROUP", "GROUP_ROLE", "NAME" }, {
        index = "INDEX",
        default = "INDEX",
        simple = "INDEX",
        off = "INDEX",
        disable = "INDEX",
        disabled = "INDEX",
        role = "ROLE",
        roles = "ROLE",
        byrole = "ROLE",
        ["by role"] = "ROLE",
        group = "GROUP",
        raidgroup = "GROUP",
        ["raid group"] = "GROUP",
        group_role = "GROUP_ROLE",
        grouprole = "GROUP_ROLE",
        ["group role"] = "GROUP_ROLE",
        ["group and role"] = "GROUP_ROLE",
        ["group plus role"] = "GROUP_ROLE",
        name = "NAME",
        alphabetical = "NAME",
        alpha = "NAME",
    }, "rebuild", aliases, {
        get = function(scopeKey)
            local conf = GroupDB(scopeKey)
            local mode = conf.sortMode
            if mode == "INDEX" or mode == "ROLE" or mode == "GROUP" or mode == "GROUP_ROLE" or mode == "NAME" then return mode end
            return conf.sortByRole and "ROLE" or "INDEX"
        end,
        set = function(scopeKey, value)
            local conf = GroupDB(scopeKey)
            if value ~= "ROLE" and value ~= "GROUP" and value ~= "GROUP_ROLE" and value ~= "NAME" then value = "INDEX" end
            conf.sortMode = value
            conf.sortByRole = value == "ROLE"
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "sort by role")
    AddAliasesForUnit(aliases, scope, "role sorting")
    AddAliasesForUnit(aliases, scope, "sort roles")
    RegisterGroupBoolean(scope, "sortByRole", "sortByRole", "Sort By Role", false, "rebuild", aliases, {
        get = function(scopeKey)
            local conf = GroupDB(scopeKey)
            if conf.sortMode then return conf.sortMode == "ROLE" end
            return conf.sortByRole and true or false
        end,
        set = function(scopeKey, value)
            local conf = GroupDB(scopeKey)
            conf.sortByRole = value and true or false
            conf.sortMode = value and "ROLE" or "INDEX"
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "player first in role")
    AddAliasesForUnit(aliases, scope, "player first")
    RegisterGroupBoolean(scope, "playerFirstInRole", "playerFirstInRole", "Player First In Role", false, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "role priority order")
    AddAliasesForUnit(aliases, scope, "role order")
    AddAliasesForUnit(aliases, scope, "role sorting order")
    RegisterGroupEnum(scope, "roleOrder", "roleOrder", "Role Priority Order", "TANK,HEALER,DAMAGER", {
        "TANK,HEALER,DAMAGER", "TANK,DAMAGER,HEALER", "HEALER,TANK,DAMAGER",
        "HEALER,DAMAGER,TANK", "DAMAGER,TANK,HEALER", "DAMAGER,HEALER,TANK",
    }, {
        ["tank healer dps"] = "TANK,HEALER,DAMAGER",
        ["tank heal dps"] = "TANK,HEALER,DAMAGER",
        ["tank dps healer"] = "TANK,DAMAGER,HEALER",
        ["tank dps heal"] = "TANK,DAMAGER,HEALER",
        ["healer tank dps"] = "HEALER,TANK,DAMAGER",
        ["heal tank dps"] = "HEALER,TANK,DAMAGER",
        ["healer dps tank"] = "HEALER,DAMAGER,TANK",
        ["heal dps tank"] = "HEALER,DAMAGER,TANK",
        ["dps tank healer"] = "DAMAGER,TANK,HEALER",
        ["dps tank heal"] = "DAMAGER,TANK,HEALER",
        ["dps healer tank"] = "DAMAGER,HEALER,TANK",
        ["dps heal tank"] = "DAMAGER,HEALER,TANK",
    }, "rebuild", aliases, {
        get = function(scopeKey) return NormalizeGroupRoleOrder(GroupDB(scopeKey).roleOrder) end,
        set = function(scopeKey, value) GroupDB(scopeKey).roleOrder = NormalizeGroupRoleOrder(value) end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "scale mode", "skalierungsmodus")
    AddAliasesForUnit(aliases, scope, "group scale mode")
    RegisterGroupEnum(scope, "frameScaleMode", "frameScaleMode", "Frame Scaling Mode", "off", { "off", "manual", "auto" }, {
        off = "off",
        none = "off",
        disable = "off",
        disabled = "off",
        ["false"] = "off",
        manual = "manual",
        on = "manual",
        enable = "manual",
        enabled = "manual",
        custom = "manual",
        auto = "auto",
        automatic = "auto",
        breakpoint = "auto",
        breakpoints = "auto",
    }, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "frame scaling")
    AddAliasesForUnit(aliases, scope, "group frame scaling")
    AddAliasesForUnit(aliases, scope, "scaling")
    RegisterGroupBoolean(scope, "frameScaleEnabled", "frameScaleEnabled", "Frame Scaling", false, "rebuild", aliases, {
        get = function(scopeKey)
            local mode = GroupDB(scopeKey).frameScaleMode
            return mode == "manual" or mode == "auto"
        end,
        set = function(scopeKey, value)
            local conf = GroupDB(scopeKey)
            if value then
                if conf.frameScaleMode ~= "manual" and conf.frameScaleMode ~= "auto" then conf.frameScaleMode = "manual" end
            else
                conf.frameScaleMode = "off"
            end
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "manual scale", "manuelle skalierung")
    AddAliasesForUnit(aliases, scope, "scale")
    AddAliasesForUnit(aliases, scope, "frame scale")
    AddAliasesForUnit(aliases, scope, "scale percent")
    AddAliasesForUnit(aliases, scope, "frame scale percent")
    RegisterGroupNumber(scope, "frameScaleManual", "frameScaleManual", "Manual Frame Scale", 100, 50, 150, 5, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "scale at 10")
    AddAliasesForUnit(aliases, scope, "1-10 player scale")
    AddAliasesForUnit(aliases, scope, "small group scale")
    RegisterGroupNumber(scope, "scaleAt10", "scaleAt10", "Scale 1-10 Players", 100, 50, 100, 5, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "scale at 20")
    AddAliasesForUnit(aliases, scope, "11-20 player scale")
    RegisterGroupNumber(scope, "scaleAt20", "scaleAt20", "Scale 11-20 Players", 85, 50, 100, 5, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "scale at 25")
    AddAliasesForUnit(aliases, scope, "21-25 player scale")
    RegisterGroupNumber(scope, "scaleAt25", "scaleAt25", "Scale 21-25 Players", 80, 50, 100, 5, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "scale over 25")
    AddAliasesForUnit(aliases, scope, "26 plus player scale")
    AddAliasesForUnit(aliases, scope, "large raid scale")
    RegisterGroupNumber(scope, "scaleOver25", "scaleOver25", "Scale 26+ Players", 70, 50, 100, 5, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "opacity affects")
    AddAliasesForUnit(aliases, scope, "transparency affects")
    AddAliasesForUnit(aliases, scope, "alpha target")
    RegisterGroupEnum(scope, "opacityMode", "opacityMode", "Opacity Affects", "frame", { "frame", "foreground", "health", "background" }, {
        frame = "frame",
        whole = "frame",
        ["whole frame"] = "frame",
        foreground = "foreground",
        bars = "foreground",
        bar = "foreground",
        hp = "health",
        health = "health",
        healthbar = "health",
        ["health bar"] = "health",
        background = "background",
        backdrop = "background",
        track = "background",
    }, "visual", aliases, {
        get = function(scopeKey) return GroupOpacityMode(scopeKey) end,
        set = function(scopeKey, value) GroupSetOpacityMode(scopeKey, value) end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "in combat opacity")
    AddAliasesForUnit(aliases, scope, "combat opacity")
    AddAliasesForUnit(aliases, scope, "in combat alpha")
    RegisterGroupNumber(scope, "alphaInCombat", "alphaCurrentInCombat", "In Combat Opacity", 1, 0, 1, 0.05, "visual", aliases, {
        percent = true,
        get = function(scopeKey) return GroupReadAlpha(scopeKey, true) end,
        set = function(scopeKey, value) GroupWriteAlpha(scopeKey, true, value) end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "out of combat opacity")
    AddAliasesForUnit(aliases, scope, "outside combat opacity")
    AddAliasesForUnit(aliases, scope, "out of combat alpha")
    RegisterGroupNumber(scope, "alphaOutOfCombat", "alphaCurrentOutOfCombat", "Out Of Combat Opacity", 1, 0, 1, 0.05, "visual", aliases, {
        percent = true,
        get = function(scopeKey) return GroupReadAlpha(scopeKey, false) end,
        set = function(scopeKey, value) GroupWriteAlpha(scopeKey, false, value) end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "sync opacity")
    AddAliasesForUnit(aliases, scope, "sync alpha")
    AddAliasesForUnit(aliases, scope, "sync both opacity")
    RegisterGroupBoolean(scope, "alphaSync", "alphaSync", "Sync Combat Opacity", false, "visual", aliases, {
        set = function(scopeKey, value)
            local conf = GroupDB(scopeKey)
            conf.alphaSync = value and true or false
            if conf.alphaSync then GroupWriteAlpha(scopeKey, false, GroupReadAlpha(scopeKey, true)) end
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "backdrop opacity")
    AddAliasesForUnit(aliases, scope, "background opacity")
    AddAliasesForUnit(aliases, scope, "backdrop base opacity")
    RegisterGroupNumber(scope, "bgAlpha", "bgA", "Backdrop Base Opacity", 0.85, 0, 1, 0.05, "visual", aliases, { percent = true })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp fill opacity")
    AddAliasesForUnit(aliases, scope, "health fill opacity")
    AddAliasesForUnit(aliases, scope, "health bar opacity")
    RegisterGroupNumber(scope, "hpBarAlpha", "hpBarAlpha", "HP Fill Opacity", 1, 0.3, 1, 0.05, "visual", aliases, { percent = true })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp track opacity")
    AddAliasesForUnit(aliases, scope, "health track opacity")
    AddAliasesForUnit(aliases, scope, "health background opacity")
    RegisterGroupNumber(scope, "hpBgAlpha", "hpBgAlpha", "HP Track Opacity", 0.85, 0, 1, 0.05, "visual", aliases, { percent = true })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "preserve hp color")
    AddAliasesForUnit(aliases, scope, "preserve health color")
    RegisterGroupBoolean(scope, "alphaPreserveHPColor", "alphaPreserveHPColor", "Preserve HP Color", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "text ignores hp opacity")
    AddAliasesForUnit(aliases, scope, "text ignores health opacity")
    AddAliasesForUnit(aliases, scope, "ignore hp opacity for text")
    RegisterGroupBoolean(scope, "hpTextIgnoreAlpha", "hpTextIgnoreAlpha", "Text Ignores HP Opacity", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group backdrop color")
    AddAliasesForUnit(aliases, scope, "group background color")
    AddAliasesForUnit(aliases, scope, "frame background color")
    AddAliasesForUnit(aliases, scope, "background color")
    AddAliasesForUnit(aliases, scope, "backdrop color")
    RegisterGroupColor(scope, "groupBackdropColor", "bg", "Backdrop Color", 0.10, 0.10, 0.10, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "anchor to")
    AddAliasesForUnit(aliases, scope, "anchor target")
    AddAliasesForUnit(aliases, scope, "anchor frame")
    RegisterGroupEnum(scope, "anchorToFrame", "anchorToFrame", "Anchor To", "FREE", { "FREE", "player", "target", "targettarget", "focustarget", "focus" }, {
        free = "FREE",
        none = "FREE",
        clear = "FREE",
        ui = "FREE",
        uiparent = "FREE",
        player = "player",
        target = "target",
        targettarget = "targettarget",
        ["target of target"] = "targettarget",
        tot = "targettarget",
        focustarget = "focustarget",
        ["focus target"] = "focustarget",
        focus = "focus",
    }, "rebuild", aliases, {
        get = function(scopeKey)
            local value = GroupDB(scopeKey).anchorToFrame
            return StandardGroupAnchorTarget(value) and (value and value ~= "" and value or "FREE") or "FREE"
        end,
        set = function(scopeKey, value)
            GroupDB(scopeKey).anchorToFrame = (value == "FREE") and nil or value
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "custom anchor frame")
    AddAliasesForUnit(aliases, scope, "custom anchor")
    AddAliasesForUnit(aliases, scope, "custom anchor name")
    RegisterGroupString(scope, "customAnchorFrame", "customAnchorFrame", "Custom Anchor Frame", "", "rebuild", aliases, {
        get = function(scopeKey)
            local value = GroupDB(scopeKey).anchorToFrame
            return StandardGroupAnchorTarget(value) and "" or tostring(value or "")
        end,
        set = function(scopeKey, value)
            value = TrimString(value)
            local lower = value:lower()
            GroupDB(scopeKey).anchorToFrame = (value == "" or lower == "free" or lower == "clear" or lower == "none") and nil or value
        end,
        description = "Sets a custom frame name for the group-frame anchor target.",
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "anchor point")
    AddAliasesForUnit(aliases, scope, "anchor position")
    RegisterGroupEnum(scope, "anchorPoint", "anchorPoint", "Anchor Point", "CENTER", { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }, {
        topleft = "TOPLEFT",
        ["top left"] = "TOPLEFT",
        top = "TOP",
        topright = "TOPRIGHT",
        ["top right"] = "TOPRIGHT",
        left = "LEFT",
        center = "CENTER",
        centre = "CENTER",
        middle = "CENTER",
        right = "RIGHT",
        bottomleft = "BOTTOMLEFT",
        ["bottom left"] = "BOTTOMLEFT",
        bottom = "BOTTOM",
        bottomright = "BOTTOMRIGHT",
        ["bottom right"] = "BOTTOMRIGHT",
    }, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "bar color mode")
    AddAliasesForUnit(aliases, scope, "health bar color mode")
    AddAliasesForUnit(aliases, scope, "group bar style")
    RegisterGroupEnum(scope, "groupBarMode", "gfBarMode", "Bar Color Mode", "GLOBAL", GROUP_BAR_MODE_VALUES, {
        global = "GLOBAL",
        inherit = "GLOBAL",
        default = "GLOBAL",
        ["global style"] = "GLOBAL",
        class = "CLASS",
        classcolor = "CLASS",
        ["class color"] = "CLASS",
        dark = "dark",
        darkmode = "dark",
        ["dark mode"] = "dark",
        unified = "unified",
        unifiedcolor = "unified",
        ["unified color"] = "unified",
        gradient = "GRADIENT",
        healthgradient = "GRADIENT",
        ["health gradient"] = "GRADIENT",
        custom = "CUSTOM",
        manual = "CUSTOM",
    }, "visual", aliases, {
        get = function(scopeKey) return GroupDB(scopeKey).gfBarMode or "GLOBAL" end,
        set = function(scopeKey, value)
            local conf = GroupDB(scopeKey)
            conf.gfBarMode = value == "GLOBAL" and nil or value
            if value == "CLASS" or value == "GRADIENT" then conf.healthColorMode = value end
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "foreground texture")
    AddAliasesForUnit(aliases, scope, "bar texture")
    AddAliasesForUnit(aliases, scope, "health bar texture")
    RegisterGroupTexture(scope, "barTexture", "barTexture", "Foreground Texture", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "background texture")
    AddAliasesForUnit(aliases, scope, "bar background texture")
    AddAliasesForUnit(aliases, scope, "health background texture")
    RegisterGroupTexture(scope, "barBackgroundTexture", "barBgTexture", "Background Texture", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "health color mode")
    AddAliasesForUnit(aliases, scope, "health mode")
    RegisterGroupEnum(scope, "healthColorMode", "healthColorMode", "Health Color Mode", "CLASS", GROUP_HEALTH_MODE_VALUES, {
        class = "CLASS",
        classcolor = "CLASS",
        ["class color"] = "CLASS",
        gradient = "GRADIENT",
        healthgradient = "GRADIENT",
        ["health gradient"] = "GRADIENT",
        custom = "CUSTOM",
        manual = "CUSTOM",
    }, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "health bar color")
    AddAliasesForUnit(aliases, scope, "health color")
    AddAliasesForUnit(aliases, scope, "bar color")
    Registry:RegisterSetting({
        key = "gf_" .. scope .. ".healthBarColor",
        label = UNIT_LABELS[scope] .. " Health Bar Color",
        category = UNIT_LABELS[scope] .. " / Group Frames",
        unit = scope,
        frameType = "group",
        attribute = "healthBarColor",
        type = "color",
        aliases = aliases,
        get = function() return GetGroupHealthBarColor(scope) end,
        set = function(value) SetGroupHealthBarColor(scope, value) end,
        sameValue = GroupColorSame,
        apply = function() ApplyGroup(scope, "visual") end,
        combatSafe = false,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "custom health color")
    AddAliasesForUnit(aliases, scope, "health custom color")
    AddAliasesForUnit(aliases, scope, "health bar custom color")
    RegisterGroupColor(scope, "healthCustomColor", "healthCustom", "Custom Health Color", 0.20, 0.80, 0.20, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dark health color")
    AddAliasesForUnit(aliases, scope, "dark bar color")
    AddAliasesForUnit(aliases, scope, "dark mode health color")
    RegisterGroupColor(scope, "darkBarColor", "gfDark", "Dark Bar Color", 0, 0, 0, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "unified health color")
    AddAliasesForUnit(aliases, scope, "unified bar color")
    AddAliasesForUnit(aliases, scope, "unified color")
    RegisterGroupColor(scope, "unifiedBarColor", "gfUnified", "Unified Bar Color", 0.10, 0.60, 0.90, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power smooth fill")
    AddAliasesForUnit(aliases, scope, "smooth power fill")
    RegisterGroupBoolean(scope, "powerSmoothFill", "powerSmoothFill", "Power Smooth Fill", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "show tank power")
    AddAliasesForUnit(aliases, scope, "tank power bar")
    AddAliasesForUnit(aliases, scope, "power for tanks")
    RegisterGroupBoolean(scope, "powerShowTank", "powerShowTank", "Show Tank Power", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "show healer power")
    AddAliasesForUnit(aliases, scope, "healer power bar")
    AddAliasesForUnit(aliases, scope, "power for healers")
    RegisterGroupBoolean(scope, "powerShowHealer", "powerShowHealer", "Show Healer Power", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "show dps power")
    AddAliasesForUnit(aliases, scope, "dps power bar")
    AddAliasesForUnit(aliases, scope, "power for dps")
    RegisterGroupBoolean(scope, "powerShowDamager", "powerShowDamager", "Show DPS Power", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hide name on dead offline")
    AddAliasesForUnit(aliases, scope, "hide name when dead")
    AddAliasesForUnit(aliases, scope, "hide name when offline")
    RegisterGroupBoolean(scope, "hideNameOnDeadOffline", "hideNameOnDeadOffline", "Hide Name On Dead Or Offline", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "name anchor")
    AddAliasesForUnit(aliases, scope, "name text anchor")
    RegisterGroupEnum(scope, "nameAnchor", "nameAnchor", "Name Anchor", "LEFT", GROUP_ANCHOR_VALUES, GROUP_ANCHOR_ALIASES, "geometry", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "name x")
    AddAliasesForUnit(aliases, scope, "name x offset")
    AddAliasesForUnit(aliases, scope, "name text x offset")
    RegisterGroupNumber(scope, "nameOffsetX", "nameOffsetX", "Name X Offset", 0, -100, 100, 1, "geometry", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "name y")
    AddAliasesForUnit(aliases, scope, "name y offset")
    AddAliasesForUnit(aliases, scope, "name text y offset")
    RegisterGroupNumber(scope, "nameOffsetY", "nameOffsetY", "Name Y Offset", 0, -100, 100, 1, "geometry", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "name layer")
    AddAliasesForUnit(aliases, scope, "name text layer")
    RegisterGroupNumber(scope, "nameTextLayer", "nameTextLayer", "Name Text Layer", 5, 1, 15, 1, "geometry", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp left text")
    AddAliasesForUnit(aliases, scope, "health left text")
    AddAliasesForUnit(aliases, scope, "left hp text")
    RegisterGroupTextMode(scope, "healthTextLeft", "textLeft", "Left HP Text", "NONE", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp right text")
    AddAliasesForUnit(aliases, scope, "health right text")
    AddAliasesForUnit(aliases, scope, "right hp text")
    RegisterGroupTextMode(scope, "healthTextRight", "textRight", "Right HP Text", "NONE", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp text delimiter")
    AddAliasesForUnit(aliases, scope, "health text delimiter")
    AddAliasesForUnit(aliases, scope, "health delimiter")
    RegisterGroupDelimiter(scope, "healthTextDelimiter", "textDelimiter", "HP Text Delimiter", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "reverse hp text")
    AddAliasesForUnit(aliases, scope, "reverse health text")
    AddAliasesForUnit(aliases, scope, "hp text reverse order")
    RegisterGroupBoolean(scope, "healthTextReverse", "hpTextReverse", "Reverse HP Text", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp text x")
    AddAliasesForUnit(aliases, scope, "hp text x offset")
    AddAliasesForUnit(aliases, scope, "health text x offset")
    RegisterGroupNumber(scope, "healthTextOffsetX", "hpOffsetX", "HP Text X Offset", 0, -100, 100, 1, "geometry", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp text y")
    AddAliasesForUnit(aliases, scope, "hp text y offset")
    AddAliasesForUnit(aliases, scope, "health text y offset")
    RegisterGroupNumber(scope, "healthTextOffsetY", "hpOffsetY", "HP Text Y Offset", 0, -100, 100, 1, "geometry", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp text layer")
    AddAliasesForUnit(aliases, scope, "health text layer")
    RegisterGroupNumber(scope, "healthTextLayer", "textLayer", "HP Text Layer", 5, 1, 15, 1, "geometry", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power left text")
    AddAliasesForUnit(aliases, scope, "left power text")
    RegisterGroupTextMode(scope, "powerTextLeft", "powerTextLeft", "Left Power Text", "NONE", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power center text")
    AddAliasesForUnit(aliases, scope, "power middle text")
    AddAliasesForUnit(aliases, scope, "center power text")
    RegisterGroupTextMode(scope, "powerTextCenter", "powerTextCenter", "Center Power Text", "PERCENT", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power right text")
    AddAliasesForUnit(aliases, scope, "right power text")
    RegisterGroupTextMode(scope, "powerTextRight", "powerTextRight", "Right Power Text", "NONE", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power text delimiter")
    AddAliasesForUnit(aliases, scope, "power delimiter")
    RegisterGroupDelimiter(scope, "powerTextDelimiter", "powerTextDelimiter", "Power Text Delimiter", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power text x")
    AddAliasesForUnit(aliases, scope, "power text x offset")
    RegisterGroupNumber(scope, "powerTextOffsetX", "powerOffsetX", "Power Text X Offset", 0, -100, 100, 1, "geometry", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power text y")
    AddAliasesForUnit(aliases, scope, "power text y offset")
    RegisterGroupNumber(scope, "powerTextOffsetY", "powerOffsetY", "Power Text Y Offset", 0, -100, 100, 1, "geometry", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power text layer")
    RegisterGroupNumber(scope, "powerTextLayer", "powerTextLayer", "Power Text Layer", 2, 1, 15, 1, "geometry", aliases)

    for _, slotInfo in ipairs({
        { label = "HP Left Text", prefix = "hpTextLeft", words = { "hp left slot", "health left slot", "left hp slot" } },
        { label = "HP Center Text", prefix = "hpTextCenter", words = { "hp center slot", "health center slot", "center hp slot" } },
        { label = "HP Right Text", prefix = "hpTextRight", words = { "hp right slot", "health right slot", "right hp slot" } },
        { label = "Power Left Text", prefix = "powerTextLeft", words = { "power left slot", "left power slot" } },
        { label = "Power Center Text", prefix = "powerTextCenter", words = { "power center slot", "center power slot" } },
        { label = "Power Right Text", prefix = "powerTextRight", words = { "power right slot", "right power slot" } },
    }) do
        aliases = {}
        for i = 1, #slotInfo.words do
            AddAliasesForUnit(aliases, scope, slotInfo.words[i] .. " x")
            AddAliasesForUnit(aliases, scope, slotInfo.words[i] .. " x offset")
        end
        RegisterGroupNumber(scope, slotInfo.prefix .. "OffsetX", slotInfo.prefix .. "OffsetX", slotInfo.label .. " Slot X Offset", 0, -100, 100, 1, "geometry", aliases)

        aliases = {}
        for i = 1, #slotInfo.words do
            AddAliasesForUnit(aliases, scope, slotInfo.words[i] .. " y")
            AddAliasesForUnit(aliases, scope, slotInfo.words[i] .. " y offset")
        end
        RegisterGroupNumber(scope, slotInfo.prefix .. "OffsetY", slotInfo.prefix .. "OffsetY", slotInfo.label .. " Slot Y Offset", 0, -100, 100, 1, "geometry", aliases)
    end

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dispel overlay")
    AddAliasesForUnit(aliases, scope, "debuff overlay")
    RegisterGroupBoolean(scope, "dispelOverlay", "dispelOverlayEnabled", "Dispel Overlay", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dispel overlay detects")
    AddAliasesForUnit(aliases, scope, "dispel overlay trigger")
    AddAliasesForUnit(aliases, scope, "debuff overlay trigger")
    RegisterGroupEnum(scope, "dispelOverlayTrigger", "dispelOverlayTrigger", "Dispel Overlay Detects", "BORDER", GROUP_DISPEL_TRIGGER_VALUES, {
        border = "BORDER",
        inherit = "BORDER",
        same = "BORDER",
        ["dispel border"] = "BORDER",
        byme = "BY_ME",
        ["by me"] = "BY_ME",
        dispellable = "BY_ME",
        ["dispellable by me"] = "BY_ME",
        type = "DISPEL_TYPE",
        dispeltype = "DISPEL_TYPE",
        ["dispel type"] = "DISPEL_TYPE",
        any = "ANY_DEBUFF",
        debuff = "ANY_DEBUFF",
        ["any debuff"] = "ANY_DEBUFF",
        ["all debuffs"] = "ANY_DEBUFF",
    }, "visual", aliases, {
        get = function(scopeKey) return NormalizeGroupDispelTrigger(GroupDB(scopeKey).dispelOverlayTrigger) end,
        set = function(scopeKey, value) GroupDB(scopeKey).dispelOverlayTrigger = NormalizeGroupDispelTrigger(value) end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dispel overlay style")
    AddAliasesForUnit(aliases, scope, "debuff overlay style")
    RegisterGroupEnum(scope, "dispelOverlayStyle", "dispelOverlayStyle", "Dispel Overlay Style", "FULL", GROUP_DISPEL_STYLE_VALUES, {
        full = "FULL",
        ["full frame"] = "FULL",
        bottom = "BOTTOM",
        top = "TOP",
        left = "LEFT",
        right = "RIGHT",
    }, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dispel overlay current health")
    AddAliasesForUnit(aliases, scope, "dispel overlay current health only")
    AddAliasesForUnit(aliases, scope, "dispel overlay on current health only")
    AddAliasesForUnit(aliases, scope, "dispel overlay on health")
    AddAliasesForUnit(aliases, scope, "debuff overlay on health")
    AddAliasesForUnit(aliases, scope, "debuff overlay current health only")
    RegisterGroupBoolean(scope, "dispelOverlayOnHealth", "dispelOverlayOnHealth", "Dispel Overlay On Current Health", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dispel overlay opacity")
    AddAliasesForUnit(aliases, scope, "dispel overlay alpha")
    AddAliasesForUnit(aliases, scope, "debuff overlay opacity")
    RegisterGroupNumber(scope, "dispelOverlayAlpha", "dispelOverlayAlpha", "Dispel Overlay Opacity", 0.35, 0.05, 1, 0.05, "visual", aliases, { percent = true })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "debuff stripe")
    AddAliasesForUnit(aliases, scope, "debuff stripe enabled")
    RegisterGroupBoolean(scope, "debuffStripe", "debuffStripeEnabled", "Debuff Stripe", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "debuff stripe edge")
    AddAliasesForUnit(aliases, scope, "debuff stripe position")
    RegisterGroupEnum(scope, "debuffStripeEdge", "debuffStripeEdge", "Debuff Stripe Edge", "BOTTOM", GROUP_STRIPE_EDGE_VALUES, {
        bottom = "BOTTOM",
        lower = "BOTTOM",
        top = "TOP",
        upper = "TOP",
    }, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "debuff stripe height")
    AddAliasesForUnit(aliases, scope, "debuff stripe size")
    RegisterGroupNumber(scope, "debuffStripeHeight", "debuffStripeHeight", "Debuff Stripe Height", 3, 1, 8, 1, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "debuff stripe opacity")
    AddAliasesForUnit(aliases, scope, "debuff stripe alpha")
    RegisterGroupNumber(scope, "debuffStripeAlpha", "debuffStripeAlpha", "Debuff Stripe Opacity", 0.60, 0.10, 1, 0.05, "visual", aliases, { percent = true })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "range fade affects")
    AddAliasesForUnit(aliases, scope, "range fade layer")
    AddAliasesForUnit(aliases, scope, "range fade mode")
    RegisterGroupEnum(scope, "rangeFadeLayerMode", "rangeFadeLayerMode", "Range Fade Affects", "frame", GROUP_RANGE_LAYER_VALUES, {
        frame = "frame",
        whole = "frame",
        ["whole frame"] = "frame",
        health = "health",
        hp = "health",
        ["hp only"] = "health",
        ["health only"] = "health",
    }, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "offline alpha")
    AddAliasesForUnit(aliases, scope, "offline opacity")
    AddAliasesForUnit(aliases, scope, "offline member opacity")
    RegisterGroupNumber(scope, "offlineAlpha", "offlineAlpha", "Offline Opacity", 0.5, 0, 1, 0.05, "visual", aliases, { percent = true })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group number")
    AddAliasesForUnit(aliases, scope, "group index")
    AddAliasesForUnit(aliases, scope, "group number label")
    RegisterGroupBoolean(scope, "groupNumber", "showGroupNumber", "Group Number", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group number size")
    AddAliasesForUnit(aliases, scope, "group index size")
    RegisterGroupNumber(scope, "groupNumberSize", "groupNumberSize", "Group Number Size", 10, 6, 24, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group number anchor")
    AddAliasesForUnit(aliases, scope, "group index anchor")
    RegisterGroupEnum(scope, "groupNumberAnchor", "groupNumberAnchor", "Group Number Anchor", "BOTTOMRIGHT", { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }, {
        topleft = "TOPLEFT",
        ["top left"] = "TOPLEFT",
        top = "TOPLEFT",
        topright = "TOPRIGHT",
        ["top right"] = "TOPRIGHT",
        bottomleft = "BOTTOMLEFT",
        ["bottom left"] = "BOTTOMLEFT",
        bottom = "BOTTOMRIGHT",
        bottomright = "BOTTOMRIGHT",
        ["bottom right"] = "BOTTOMRIGHT",
    }, "geometry", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group number x")
    AddAliasesForUnit(aliases, scope, "group number x offset")
    AddAliasesForUnit(aliases, scope, "group index x offset")
    RegisterGroupNumber(scope, "groupNumberX", "groupNumberX", "Group Number X Offset", -2, -100, 100, 1, "geometry", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group number y")
    AddAliasesForUnit(aliases, scope, "group number y offset")
    AddAliasesForUnit(aliases, scope, "group index y offset")
    RegisterGroupNumber(scope, "groupNumberY", "groupNumberY", "Group Number Y Offset", 2, -100, 100, 1, "geometry", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hover highlight thickness")
    AddAliasesForUnit(aliases, scope, "mouseover highlight thickness")
    AddAliasesForUnit(aliases, scope, "hover border thickness")
    RegisterGroupNumber(scope, "hoverHighlightSize", "hlHoverSize", "Hover Highlight Thickness", 1, 1, 6, 1, "visual", aliases, {
        set = function(scopeKey, value)
            local conf = GroupDB(scopeKey)
            conf.hlHoverSize = ClampNumber(value, 1, 6, 1)
            conf.hlOverride = true
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "focus highlight")
    AddAliasesForUnit(aliases, scope, "focus border")
    AddAliasesForUnit(aliases, scope, "focus glow")
    RegisterGroupBoolean(scope, "focusHighlight", "hlFocusEnabled", "Focus Highlight", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "focus highlight thickness")
    AddAliasesForUnit(aliases, scope, "focus border thickness")
    AddAliasesForUnit(aliases, scope, "focus glow thickness")
    RegisterGroupNumber(scope, "focusHighlightSize", "hlFocusSize", "Focus Highlight Thickness", 2, 1, 6, 1, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "focus highlight color")
    AddAliasesForUnit(aliases, scope, "focus border color")
    AddAliasesForUnit(aliases, scope, "focus glow color")
    RegisterGroupColor(scope, "focusHighlightColor", "hlFocusColor", "Focus Highlight Color", 0.50, 0.50, 1.00, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group border")
    AddAliasesForUnit(aliases, scope, "full group border")
    AddAliasesForUnit(aliases, scope, "group frame border")
    RegisterGroupBoolean(scope, "groupBorder", "groupBorderEnabled", "Group Border", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group border thickness")
    AddAliasesForUnit(aliases, scope, "group frame border thickness")
    RegisterGroupNumber(scope, "groupBorderSize", "groupBorderSize", "Group Border Thickness", 1, 1, 12, 1, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group border padding")
    AddAliasesForUnit(aliases, scope, "group frame border padding")
    RegisterGroupNumber(scope, "groupBorderPadding", "groupBorderPadding", "Group Border Padding", 2, 0, 40, 1, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group border color")
    AddAliasesForUnit(aliases, scope, "group frame border color")
    RegisterGroupColor(scope, "groupBorderColor", "groupBorder", "Group Border Color", 0.38, 0.68, 1.00, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "status icon style")
    AddAliasesForUnit(aliases, scope, "status icons style")
    AddAliasesForUnit(aliases, scope, "group icon style")
    RegisterGroupEnum(scope, "statusIconStyle", "iconStyle", "Status Icon Style", "BLIZZARD", GROUP_STATUS_ICON_STYLE_VALUES, GROUP_STATUS_ICON_STYLE_ALIASES, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "midnight status icons")
    AddAliasesForUnit(aliases, scope, "midnight icon style")
    AddAliasesForUnit(aliases, scope, "use midnight icons")
    RegisterGroupBoolean(scope, "useMidnightIcons", "useMidnightIcons", "Use Midnight Status Icons", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "role icon tanks")
    AddAliasesForUnit(aliases, scope, "show role icon for tanks")
    AddAliasesForUnit(aliases, scope, "tank role icon")
    RegisterGroupBoolean(scope, "roleIconShowTank", "roleIconShowTank", "Role Icon For Tanks", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "role icon healers")
    AddAliasesForUnit(aliases, scope, "show role icon for healers")
    AddAliasesForUnit(aliases, scope, "healer role icon")
    RegisterGroupBoolean(scope, "roleIconShowHealer", "roleIconShowHealer", "Role Icon For Healers", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "role icon dps")
    AddAliasesForUnit(aliases, scope, "show role icon for dps")
    AddAliasesForUnit(aliases, scope, "dps role icon")
    RegisterGroupBoolean(scope, "roleIconShowDPS", "roleIconShowDPS", "Role Icon For DPS", true, "visual", aliases)

    for _, spec in ipairs(GROUP_STATUS_ICON_SPECS) do
        aliases = {}
        AddGroupStatusIconAliases(aliases, scope, spec)
        AddGroupStatusIconAliases(aliases, scope, spec, "enabled")
        RegisterGroupBoolean(scope, "statusIcon" .. spec.value .. "Enabled", spec.enabled, spec.label, true, "visual", aliases)

        aliases = {}
        AddGroupStatusIconAliases(aliases, scope, spec, "size")
        RegisterGroupNumber(scope, "statusIcon" .. spec.value .. "Size", spec.size, spec.label .. " Size", spec.defaultSize, 6, 40, 1, "visual", aliases)

        aliases = {}
        AddGroupStatusIconAliases(aliases, scope, spec, "anchor")
        AddGroupStatusIconAliases(aliases, scope, spec, "position")
        RegisterGroupEnum(scope, "statusIcon" .. spec.value .. "Anchor", spec.anchor, spec.label .. " Anchor", spec.defaultAnchor, GROUP_STATUS_ANCHOR_VALUES, GROUP_STATUS_ANCHOR_ALIASES, "geometry", aliases)

        aliases = {}
        AddGroupStatusIconAliases(aliases, scope, spec, "x")
        AddGroupStatusIconAliases(aliases, scope, spec, "x offset")
        RegisterGroupNumber(scope, "statusIcon" .. spec.value .. "X", spec.x, spec.label .. " X Offset", 0, -500, 500, 1, "geometry", aliases)

        aliases = {}
        AddGroupStatusIconAliases(aliases, scope, spec, "y")
        AddGroupStatusIconAliases(aliases, scope, spec, "y offset")
        RegisterGroupNumber(scope, "statusIcon" .. spec.value .. "Y", spec.y, spec.label .. " Y Offset", 0, -500, 500, 1, "geometry", aliases)

        aliases = {}
        AddGroupStatusIconAliases(aliases, scope, spec, "layer")
        AddGroupStatusIconAliases(aliases, scope, spec, "draw layer")
        RegisterGroupNumber(scope, "statusIcon" .. spec.value .. "Layer", spec.layer, spec.label .. " Layer", spec.defaultLayer, 0, 30, 1, "visual", aliases)

        if spec.iconStyle then
            aliases = {}
            AddGroupStatusIconAliases(aliases, scope, spec, "icon pack")
            AddGroupStatusIconAliases(aliases, scope, spec, "style")
            RegisterGroupEnum(scope, "statusIcon" .. spec.value .. "Style", spec.iconStyle, spec.label .. " Icon Pack", "DEFAULT", GROUP_STATUS_ICON_PACK_VALUES, GROUP_STATUS_ICON_PACK_ALIASES, "visual", aliases)
        end
    end

end

Registry:RegisterAction({
    key = "reset_group_status_icon",
    label = "Reset Group Status Icon",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local scope = args and args.scope
        if scope ~= "raid" and scope ~= "mythicraid" then scope = "party" end
        local spec = ResolveGroupStatusIcon(args and args.icon)
        if not spec then return false, "I need a group status icon name to reset." end
        ResetGroupStatusIcon(scope, spec)
        return true, "Done. Reset " .. tostring(UNIT_LABELS[scope]) .. " " .. tostring(spec.label) .. " placement and icon pack."
    end,
})

Registry:RegisterAction({
    key = "reset_group_status_icons",
    label = "Reset Group Status Icons",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local scope = args and args.scope
        if scope ~= "raid" and scope ~= "mythicraid" then scope = "party" end
        for i = 1, #GROUP_STATUS_ICON_SPECS do ResetGroupStatusIcon(scope, GROUP_STATUS_ICON_SPECS[i]) end
        return true, "Done. Reset " .. tostring(UNIT_LABELS[scope]) .. " status icon placement and icon packs."
    end,
})

Registry:RegisterAction({
    key = "preview_group_status_icon",
    label = "Preview Group Status Icon",
    type = "preview",
    combatSafe = true,
    aliases = { "preview group status icon", "preview group status indicator", "show all group status icons", "show all group status indicators" },
    run = function(args)
        local mode = args and args.mode == "all" and "all" or "current"
        local spec = ResolveGroupStatusIcon(args and (args.icon or args.text))
        local gf = MSUF and MSUF.GF
        if gf and type(gf.SetPreviewFocus) == "function" then gf.SetPreviewFocus("sicons") end
        if gf and type(gf.SetStatusPreviewMode) == "function" then gf.SetStatusPreviewMode(mode) end
        if mode == "current" and spec and gf and type(gf._PreviewSelectStatusIcon) == "function" then gf._PreviewSelectStatusIcon(spec.value) end
        if mode == "all" then return true, "Done. Showing all group status icons in the preview." end
        return true, "Done. Previewing " .. tostring(spec and spec.label or "the current group status icon") .. "."
    end,
})

local GROUP_COPY_SCOPE_LABELS = {
    { key = "general", label = "Basics" },
    { key = "health", label = "Health & Bars" },
    { key = "text", label = "Text & Name" },
    { key = "font", label = "Font Override" },
    { key = "border", label = "Background & Opacity" },
    { key = "range", label = "Range Fade" },
    { key = "indicators", label = "Indicators & Status Icons" },
    { key = "auras", label = "Auras" },
    { key = "highlight", label = "Highlight & Aggro" },
    { key = "dstripe", label = "Debuff Stripe" },
    { key = "features", label = "Corner/Spell" },
}

local function GroupCopyScopeSummary(scopes)
    if type(scopes) ~= "table" then return "" end
    local selected, total = {}, 0
    for i = 1, #GROUP_COPY_SCOPE_LABELS do
        local row = GROUP_COPY_SCOPE_LABELS[i]
        total = total + 1
        if scopes[row.key] == true then selected[#selected + 1] = row.label end
    end
    if #selected == 0 then return " No copy categories were selected." end
    if #selected == total then return " Categories: all group-frame copy categories." end
    return " Categories: " .. table.concat(selected, ", ") .. "."
end

Registry:RegisterAction({
    key = "copy_group",
    label = "Copy Group Frame Settings",
    type = "copy",
    combatSafe = false,
    captureSnapshot = true,
    aliases = { "copy party to raid", "copy group frame settings", "copy group settings", "copy raid settings" },
    run = function(args)
        local GP = M and M.GroupPage
        if not (GP and type(GP.CopyGroupSettings) == "function") then
            return false, "Group frame copy is not available yet."
        end
        local src = args and args.source
        if src ~= "raid" and src ~= "mythicraid" then src = "party" end
        local targets = args and args.targets
        if type(targets) ~= "table" or #targets == 0 then
            local target = args and args.target
            targets = target and { target } or {}
        end
        if #targets == 0 then return false, "Copy needs at least one group-frame destination." end
        local scopes = args and args.scopes
        if type(scopes) ~= "table" and type(GP.NewGFCopyScopes) == "function" then scopes = GP.NewGFCopyScopes() end
        local count = 0
        local copiedLabels = {}
        for i = 1, #targets do
            local dst = targets[i]
            if dst ~= "raid" and dst ~= "mythicraid" then dst = "party" end
            if dst ~= src and GP.CopyGroupSettings(src, dst, scopes) then
                count = count + 1
                copiedLabels[#copiedLabels + 1] = tostring(UNIT_LABELS[dst] or dst)
            end
        end
        if count == 0 then return false, "No group-frame destination was copied." end
        return true, "Done. I copied " .. tostring(UNIT_LABELS[src] or src) .. " group-frame settings to " .. table.concat(copiedLabels, ", ") .. "." .. GroupCopyScopeSummary(scopes)
    end,
})
end

do
local SCOPES = { "party", "raid", "mythicraid" }
local SPEC_VALUES = {
    "auto", "multi",
    "PreservationEvoker", "AugmentationEvoker", "RestorationDruid", "DisciplinePriest", "HolyPriest",
    "ShadowPriest", "MistweaverMonk", "RestorationShaman", "HolyPaladin", "ProtectionPaladin", "RetributionPaladin",
}
local SPEC_ALIASES = {
    auto = "auto", automatic = "auto", autodetect = "auto", ["auto detect"] = "auto", current = "auto", player = "auto",
    multi = "multi", multispec = "multi", ["multi spec"] = "multi",
    preservation = "PreservationEvoker", preservationevoker = "PreservationEvoker", ["preservation evoker"] = "PreservationEvoker", prevoker = "PreservationEvoker",
    augmentation = "AugmentationEvoker", augmentationevoker = "AugmentationEvoker", ["augmentation evoker"] = "AugmentationEvoker", aug = "AugmentationEvoker", auggie = "AugmentationEvoker",
    restorationdruid = "RestorationDruid", ["restoration druid"] = "RestorationDruid", restodruid = "RestorationDruid", ["resto druid"] = "RestorationDruid", rdruid = "RestorationDruid",
    discipline = "DisciplinePriest", disciplinepriest = "DisciplinePriest", ["discipline priest"] = "DisciplinePriest", disc = "DisciplinePriest", discpriest = "DisciplinePriest", ["disc priest"] = "DisciplinePriest",
    holypriest = "HolyPriest", ["holy priest"] = "HolyPriest", shadowpriest = "ShadowPriest", ["shadow priest"] = "ShadowPriest",
    mistweaver = "MistweaverMonk", mistweavermonk = "MistweaverMonk", ["mistweaver monk"] = "MistweaverMonk", mwmonk = "MistweaverMonk", ["mw monk"] = "MistweaverMonk",
    restorationshaman = "RestorationShaman", ["restoration shaman"] = "RestorationShaman", restoshaman = "RestorationShaman", ["resto shaman"] = "RestorationShaman", rshaman = "RestorationShaman",
    holy = "HolyPaladin", holypaladin = "HolyPaladin", ["holy paladin"] = "HolyPaladin", hpal = "HolyPaladin", hpaladin = "HolyPaladin",
    protectionpaladin = "ProtectionPaladin", ["protection paladin"] = "ProtectionPaladin", protpaladin = "ProtectionPaladin", ["prot paladin"] = "ProtectionPaladin",
    retributionpaladin = "RetributionPaladin", ["retribution paladin"] = "RetributionPaladin", retpaladin = "RetributionPaladin", ["ret paladin"] = "RetributionPaladin",
}
local PLACED_VALUES = { "none", "icon", "square", "bar", "number" }
local FRAME_VALUES = { "none", "healthtint", "border", "glow", "pulse", "namecolor" }
local GROWTH_VALUES = { "RIGHTDOWN", "LEFTDOWN", "RIGHTUP", "LEFTUP" }
local ANCHOR_VALUES = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT" }
local CI_CATEGORY_VALUES = { "none", "dispel", "aggro", "custom" }
local CI_MODE_VALUES = { "present", "missing" }
local CI_FILTER_VALUES = { "HELPFUL|PLAYER", "HELPFUL", "HARMFUL|PLAYER", "HARMFUL" }
local PLACED_ALIASES = { none = "none", off = "none", disabled = "none", hide = "none", icon = "icon", icons = "icon", square = "square", dot = "square", bar = "bar", number = "number", text = "number" }
local FRAME_ALIASES = { none = "none", off = "none", disabled = "none", hide = "none", healthtint = "healthtint", ["health tint"] = "healthtint", tint = "healthtint", border = "border", outline = "border", glow = "glow", pulse = "pulse", namecolor = "namecolor", ["name color"] = "namecolor", name = "namecolor" }
local GROWTH_ALIASES = { rightdown = "RIGHTDOWN", ["right down"] = "RIGHTDOWN", ["right then down"] = "RIGHTDOWN", leftdown = "LEFTDOWN", ["left down"] = "LEFTDOWN", ["left then down"] = "LEFTDOWN", rightup = "RIGHTUP", ["right up"] = "RIGHTUP", ["right then up"] = "RIGHTUP", leftup = "LEFTUP", ["left up"] = "LEFTUP", ["left then up"] = "LEFTUP" }
local ANCHOR_ALIASES = { topleft = "TOPLEFT", ["top left"] = "TOPLEFT", topright = "TOPRIGHT", ["top right"] = "TOPRIGHT", bottomleft = "BOTTOMLEFT", ["bottom left"] = "BOTTOMLEFT", bottomright = "BOTTOMRIGHT", ["bottom right"] = "BOTTOMRIGHT", center = "CENTER", centre = "CENTER", middle = "CENTER", top = "TOP", bottom = "BOTTOM", left = "LEFT", right = "RIGHT" }
local CI_CATEGORY_ALIASES = { none = "none", off = "none", empty = "none", disabled = "none", dispel = "dispel", dispellable = "dispel", ["dispellable debuff"] = "dispel", aggro = "aggro", threat = "aggro", ["aggro threat"] = "aggro", custom = "custom", ["custom spell"] = "custom", spell = "custom" }
local CI_MODE_ALIASES = { present = "present", shown = "present", active = "present", ["when present"] = "present", missing = "missing", absent = "missing", ["when missing"] = "missing" }
local CI_FILTER_ALIASES = { helpfulplayer = "HELPFUL|PLAYER", ["helpful player"] = "HELPFUL|PLAYER", ["buff by me"] = "HELPFUL|PLAYER", ["my buff"] = "HELPFUL|PLAYER", ["own buff"] = "HELPFUL|PLAYER", helpful = "HELPFUL", buff = "HELPFUL", ["any buff"] = "HELPFUL", harmfulplayer = "HARMFUL|PLAYER", ["harmful player"] = "HARMFUL|PLAYER", ["debuff by me"] = "HARMFUL|PLAYER", ["my debuff"] = "HARMFUL|PLAYER", ["own debuff"] = "HARMFUL|PLAYER", harmful = "HARMFUL", debuff = "HARMFUL", ["any debuff"] = "HARMFUL" }
local CI_SLOTS = {
    { key = "TL", label = "Top Left", default = "dispel", terms = { "top left corner", "top left dot", "top left corner indicator", "tl corner" } },
    { key = "TR", label = "Top Right", default = "aggro", terms = { "top right corner", "top right dot", "top right corner indicator", "tr corner" } },
    { key = "BL", label = "Bottom Left", default = "none", terms = { "bottom left corner", "bottom left dot", "bottom left corner indicator", "bl corner" } },
    { key = "BR", label = "Bottom Right", default = "none", terms = { "bottom right corner", "bottom right dot", "bottom right corner indicator", "br corner" } },
    { key = "C", label = "Center", default = "none", terms = { "center corner", "middle corner", "center dot", "middle dot", "center indicator" } },
}

local function LookupKey(value)
    return tostring(value or ""):lower():gsub("[^%w]+", "")
end

local function Scope(scope)
    return (scope == "raid" or scope == "mythicraid") and scope or "party"
end

local function Clamp01(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback or 0 end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function ColorSame(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    local ar, ag, ab = tonumber(a.r or a[1]) or 0, tonumber(a.g or a[2]) or 0, tonumber(a.b or a[3]) or 0
    local br, bg, bb = tonumber(b.r or b[1]) or 0, tonumber(b.g or b[2]) or 0, tonumber(b.b or b[3]) or 0
    return math.abs(ar - br) < 0.0005 and math.abs(ag - bg) < 0.0005 and math.abs(ab - bb) < 0.0005
end

local function SpellRuntime()
    local gf = MSUF and MSUF.GF
    return (gf and gf.SpellIndicators) or _G.MSUF_GF_SpellIndicators
end

local function SpellDB(scope)
    local conf = GroupDB(scope)
    if type(conf.spellIndicators) ~= "table" then conf.spellIndicators = { enabled = false, spec = "auto", specs = {}, layer = 9 } end
    local si = conf.spellIndicators
    if si.spec == nil or si.spec == "" then si.spec = "auto" end
    if type(si.specs) ~= "table" then si.specs = {} end
    if si.layer == nil then si.layer = 9 end
    return si
end

local function SpecDisplay(specKey)
    if specKey == "auto" then return "Auto-Detect" end
    if specKey == "multi" then return "Multi-Spec" end
    local info = SpellRuntime() and SpellRuntime().SpecInfo and SpellRuntime().SpecInfo[specKey]
    return (info and info.display) or tostring(specKey or "")
end

local function ResolveSpec(value)
    local compact = LookupKey(value)
    if compact == "" then return nil end
    for alias, specKey in pairs(SPEC_ALIASES) do
        local aliasKey = LookupKey(alias)
        if compact == aliasKey or (#aliasKey >= 5 and compact:find(aliasKey, 1, true)) then return specKey end
    end
    for i = 1, #SPEC_VALUES do
        local specKey = SPEC_VALUES[i]
        if compact == LookupKey(specKey) or compact == LookupKey(SpecDisplay(specKey)) then return specKey end
    end
    local specs = SpellRuntime() and SpellRuntime().SpecInfo
    if type(specs) == "table" then
        for specKey, info in pairs(specs) do
            local displayKey = LookupKey(info and info.display)
            if compact == LookupKey(specKey) or compact == displayKey or (#displayKey >= 5 and compact:find(displayKey, 1, true)) then return specKey end
        end
    end
    return nil
end

local function FindAuraInSpec(specKey, text)
    text = tostring(text or "")
    local compact = LookupKey(text)
    local runtime = SpellRuntime()
    local list = runtime and runtime.TrackableAuras and runtime.TrackableAuras[specKey]
    local bestName, bestDisplay, bestScore
    if type(list) == "table" then
        for i = 1, #list do
            local info = list[i]
            local name = info and info.name
            if name then
                local display = info.display or name
                local nameKey = LookupKey(name)
                local displayKey = LookupKey(display)
                local score
                if compact == nameKey or compact == displayKey then score = math.max(#nameKey, #displayKey)
                elseif #nameKey >= 4 and compact:find(nameKey, 1, true) then score = #nameKey
                elseif #displayKey >= 4 and compact:find(displayKey, 1, true) then score = #displayKey end
                if score and (not bestScore or score > bestScore) then bestName, bestDisplay, bestScore = name, display, score end
            end
        end
    end
    local ids = runtime and runtime.SpellIDs and runtime.SpellIDs[specKey]
    local numberText = text:match("%d+")
    if type(ids) == "table" and numberText then
        for auraName, spellID in pairs(ids) do
            if tostring(spellID) == numberText then return auraName, auraName end
        end
    end
    return bestName, bestDisplay
end

local function ResolveAura(specKey, text)
    specKey = ResolveSpec(specKey) or specKey
    if specKey then
        local aura, display = FindAuraInSpec(specKey, text)
        return aura, specKey, display
    end
    local trackable = SpellRuntime() and SpellRuntime().TrackableAuras
    local bestAura, bestSpec, bestDisplay, bestScore
    if type(trackable) == "table" then
        for key in pairs(trackable) do
            local aura, display = FindAuraInSpec(key, text)
            if aura then
                local score = #LookupKey(display or aura)
                if not bestScore or score > bestScore then
                    bestAura, bestSpec, bestDisplay, bestScore = aura, key, display, score
                elseif score == bestScore and aura ~= bestAura then
                    bestAura, bestSpec, bestDisplay = nil, nil, nil
                end
            end
        end
    end
    return bestAura, bestSpec, bestDisplay
end

A.ResolveGroupSpellSpec = ResolveSpec
A.ResolveGroupSpellAura = ResolveAura
A.GroupSpellSpecDisplay = SpecDisplay

local function EnsureSpec(scope, specKey)
    local si = SpellDB(scope)
    if not specKey or specKey == "auto" or specKey == "multi" then return si end
    local runtime = SpellRuntime()
    if runtime and type(runtime.EnsureSpecConfig) == "function" then runtime.EnsureSpecConfig(si, specKey) else si.specs[specKey] = si.specs[specKey] or {} end
    return si
end

local function SpellEntry(scope, specKey, auraName, create)
    if not (specKey and auraName and auraName ~= "") then return nil end
    local si = EnsureSpec(scope, specKey)
    si.specs[specKey] = si.specs[specKey] or {}
    if create and type(si.specs[specKey][auraName]) ~= "table" then si.specs[specKey][auraName] = { enabled = true, onlyOwn = true } end
    return si.specs[specKey][auraName], si.specs[specKey]
end

local function Placed(entry, create)
    if not entry then return nil end
    if create and type(entry.placed) ~= "table" then entry.placed = { type = "icon", anchor = "TOPLEFT", x = 0, y = 0, size = 18, showCooldownSwipe = true } end
    return type(entry.placed) == "table" and entry.placed or nil
end

local function FrameEffect(entry, create)
    if not entry then return nil end
    if create and type(entry.frame) ~= "table" then entry.frame = { type = "none" } end
    return type(entry.frame) == "table" and entry.frame or nil
end

local function ApplySpell(scope)
    local runtime = SpellRuntime()
    if runtime and type(runtime.InvalidateRuntimeCaches) == "function" then runtime.InvalidateRuntimeCaches() end
    ApplyGroup(scope, "visual")
end

local function CopyTable(src)
    if type(src) ~= "table" then return src end
    local out = {}
    for k, v in pairs(src) do out[k] = CopyTable(v) end
    return out
end

local function CustomConfig(scope, slotKey, create)
    local conf = GroupDB(scope)
    local key = "ciCustom" .. tostring(slotKey or "")
    if create and type(conf[key]) ~= "table" then conf[key] = { spells = "", mode = "present", filter = "HELPFUL|PLAYER", r = 0.40, g = 1.00, b = 0.40 } end
    return type(conf[key]) == "table" and conf[key] or nil
end

local function ActivateCustom(scope, slotKey)
    GroupDB(scope)["ciSlot" .. tostring(slotKey or "")] = "custom"
end

local SLOT_LOOKUP = {}
for i = 1, #CI_SLOTS do
    local slot = CI_SLOTS[i]
    SLOT_LOOKUP[LookupKey(slot.key)] = slot
    SLOT_LOOKUP[LookupKey(slot.label)] = slot
    for j = 1, #(slot.terms or {}) do SLOT_LOOKUP[LookupKey(slot.terms[j])] = slot end
end

local function ResolveSlot(value)
    local compact = LookupKey(value)
    if SLOT_LOOKUP[compact] then return SLOT_LOOKUP[compact] end
    for key, slot in pairs(SLOT_LOOKUP) do if #key >= 3 and compact:find(key, 1, true) then return slot end end
    return nil
end

A.ResolveGroupCornerSlot = ResolveSlot

local function AddSlotAliases(out, scope, slot, suffix)
    for i = 1, #(slot.terms or {}) do
        local term = slot.terms[i]
        AddAliasesForUnit(out, scope, suffix and (term .. " " .. suffix) or term)
        if suffix then AddAliasesForUnit(out, scope, suffix .. " " .. term) end
    end
end

local function RegisterGroupNested(scope, suffix, attr, label, typeName, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "gf_" .. scope .. "." .. suffix,
        label = UNIT_LABELS[scope] .. " " .. label,
        category = UNIT_LABELS[scope] .. " / Group Frames",
        unit = scope,
        frameType = "group",
        attribute = attr,
        type = typeName,
        aliases = aliases,
        values = opts.values,
        valueAliases = opts.valueAliases,
        valuePrefixes = opts.valuePrefixes or aliases,
        min = opts.min,
        max = opts.max,
        step = opts.step,
        percent = opts.percent == true,
        description = opts.description,
        get = opts.get,
        set = opts.set,
        sameValue = opts.sameValue,
        apply = function() (opts.apply or ApplyGroup)(scope, opts.mode or "visual") end,
        combatSafe = false,
    })
end

for _, scope in ipairs(SCOPES) do
    local aliases = {}
    AddAliasesForUnit(aliases, scope, "spell indicators")
    AddAliasesForUnit(aliases, scope, "spell indicator")
    AddAliasesForUnit(aliases, scope, "tracked spells")
    RegisterGroupNested(scope, "spellIndicators.enabled", "spellIndicators", "Spell Indicators", "boolean", aliases, {
        get = function() return SpellDB(scope).enabled == true end,
        set = function(value)
            local si = SpellDB(scope)
            si.enabled = value and true or false
            local specKey = ResolveSpec(si.spec)
            if specKey and specKey ~= "auto" and specKey ~= "multi" then EnsureSpec(scope, specKey) end
        end,
        apply = ApplySpell,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "spell indicator layer")
    AddAliasesForUnit(aliases, scope, "spell indicators layer")
    AddAliasesForUnit(aliases, scope, "tracked spell layer")
    RegisterGroupNested(scope, "spellIndicators.layer", "spellIndicatorLayer", "Spell Indicator Layer", "number", aliases, {
        min = 1, max = 15, step = 1,
        get = function() return tonumber(SpellDB(scope).layer) or 9 end,
        set = function(value) SpellDB(scope).layer = ClampNumber(value, 1, 15, 1) end,
        apply = ApplySpell,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "spell indicator spec")
    AddAliasesForUnit(aliases, scope, "spell indicators spec")
    AddAliasesForUnit(aliases, scope, "tracked spell spec")
    RegisterGroupNested(scope, "spellIndicators.spec", "spellIndicatorSpec", "Spell Indicator Spec", "enum", aliases, {
        values = SPEC_VALUES, valueAliases = SPEC_ALIASES,
        get = function() return ResolveSpec(SpellDB(scope).spec) or "auto" end,
        set = function(value)
            local specKey = ResolveSpec(value) or "auto"
            SpellDB(scope).spec = specKey
            if specKey ~= "auto" and specKey ~= "multi" then EnsureSpec(scope, specKey) end
        end,
        apply = ApplySpell,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "corner indicators")
    AddAliasesForUnit(aliases, scope, "corner indicator")
    AddAliasesForUnit(aliases, scope, "corner dots")
    RegisterGroupNested(scope, "ciEnabled", "cornerIndicators", "Corner Indicators", "boolean", aliases, {
        get = function()
            local value = GroupDB(scope).ciEnabled
            if value == nil then return true end
            return value and true or false
        end,
        set = function(value) GroupDB(scope).ciEnabled = value and true or false end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "corner indicator size")
    AddAliasesForUnit(aliases, scope, "corner dot size")
    RegisterGroupNested(scope, "ciSize", "cornerIndicatorSize", "Corner Indicator Size", "number", aliases, {
        min = 4, max = 24, step = 1,
        get = function() return tonumber(GroupDB(scope).ciSize) or 8 end,
        set = function(value) GroupDB(scope).ciSize = ClampNumber(value, 4, 24, 1) end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "corner indicator alpha")
    AddAliasesForUnit(aliases, scope, "corner indicator opacity")
    AddAliasesForUnit(aliases, scope, "corner dot opacity")
    RegisterGroupNested(scope, "ciAlpha", "cornerIndicatorAlpha", "Corner Indicator Opacity", "number", aliases, {
        min = 0.1, max = 1, step = 0.05, percent = true,
        get = function() return tonumber(GroupDB(scope).ciAlpha) or 1 end,
        set = function(value) GroupDB(scope).ciAlpha = ClampNumber(value, 0.1, 1, 0.05) end,
    })

    for _, slot in ipairs(CI_SLOTS) do
        local slotKey, slotLabel, slotDefault = slot.key, slot.label, slot.default
        aliases = {}
        AddSlotAliases(aliases, scope, slot)
        AddSlotAliases(aliases, scope, slot, "indicator")
        AddSlotAliases(aliases, scope, slot, "category")
        RegisterGroupNested(scope, "ciSlot" .. slotKey, "cornerIndicator" .. slotKey, slotLabel .. " Corner Indicator", "enum", aliases, {
            values = CI_CATEGORY_VALUES, valueAliases = CI_CATEGORY_ALIASES,
            get = function() return GroupDB(scope)["ciSlot" .. slotKey] or slotDefault end,
            set = function(value) GroupDB(scope)["ciSlot" .. slotKey] = value or "none" end,
        })

        aliases = {}
        AddSlotAliases(aliases, scope, slot, "custom spells")
        AddSlotAliases(aliases, scope, slot, "custom spell ids")
        AddSlotAliases(aliases, scope, slot, "spell ids")
        RegisterGroupNested(scope, "ciCustom" .. slotKey .. ".spells", "cornerIndicator" .. slotKey .. "CustomSpells", slotLabel .. " Corner Custom Spells", "string", aliases, {
            get = function()
                local cfg = CustomConfig(scope, slotKey, false)
                return cfg and cfg.spells or ""
            end,
            set = function(value)
                local cfg = CustomConfig(scope, slotKey, true)
                cfg.spells = tostring(value or "")
                ActivateCustom(scope, slotKey)
            end,
            description = "Comma-separated spell IDs for this corner custom spell slot.",
        })

        aliases = {}
        AddSlotAliases(aliases, scope, slot, "custom mode")
        AddSlotAliases(aliases, scope, slot, "custom when")
        RegisterGroupNested(scope, "ciCustom" .. slotKey .. ".mode", "cornerIndicator" .. slotKey .. "CustomMode", slotLabel .. " Corner Custom Mode", "enum", aliases, {
            values = CI_MODE_VALUES, valueAliases = CI_MODE_ALIASES,
            get = function()
                local cfg = CustomConfig(scope, slotKey, false)
                return cfg and cfg.mode or "present"
            end,
            set = function(value)
                local cfg = CustomConfig(scope, slotKey, true)
                cfg.mode = value == "missing" and "missing" or "present"
                ActivateCustom(scope, slotKey)
            end,
        })

        aliases = {}
        AddSlotAliases(aliases, scope, slot, "custom filter")
        AddSlotAliases(aliases, scope, slot, "custom aura filter")
        RegisterGroupNested(scope, "ciCustom" .. slotKey .. ".filter", "cornerIndicator" .. slotKey .. "CustomFilter", slotLabel .. " Corner Custom Filter", "enum", aliases, {
            values = CI_FILTER_VALUES, valueAliases = CI_FILTER_ALIASES,
            get = function()
                local cfg = CustomConfig(scope, slotKey, false)
                return cfg and cfg.filter or "HELPFUL|PLAYER"
            end,
            set = function(value)
                local cfg = CustomConfig(scope, slotKey, true)
                local ok = { ["HELPFUL|PLAYER"] = true, HELPFUL = true, ["HARMFUL|PLAYER"] = true, HARMFUL = true }
                cfg.filter = ok[value] and value or "HELPFUL|PLAYER"
                ActivateCustom(scope, slotKey)
            end,
        })

        aliases = {}
        AddSlotAliases(aliases, scope, slot, "custom color")
        AddSlotAliases(aliases, scope, slot, "spell color")
        RegisterGroupNested(scope, "ciCustom" .. slotKey .. ".color", "cornerIndicator" .. slotKey .. "CustomColor", slotLabel .. " Corner Custom Color", "color", aliases, {
            sameValue = ColorSame,
            get = function()
                local cfg = CustomConfig(scope, slotKey, false)
                return { r = (cfg and tonumber(cfg.r)) or 0.40, g = (cfg and tonumber(cfg.g)) or 1.00, b = (cfg and tonumber(cfg.b)) or 0.40 }
            end,
            set = function(value)
                local cfg = CustomConfig(scope, slotKey, true)
                cfg.r = Clamp01(type(value) == "table" and (value.r or value[1]) or 0.40, 0.40)
                cfg.g = Clamp01(type(value) == "table" and (value.g or value[2]) or 1.00, 1.00)
                cfg.b = Clamp01(type(value) == "table" and (value.b or value[3]) or 0.40, 0.40)
                ActivateCustom(scope, slotKey)
            end,
        })
    end
end

Registry:RegisterAction({
    key = "clear_group_custom_anchor",
    label = "Clear Group Custom Anchor",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    aliases = { "clear group custom anchor", "clear group custom anchor frame", "reset group custom anchor", "remove group custom anchor" },
    run = function(args)
        local scope = Scope(args and args.scope)
        GroupDB(scope).anchorToFrame = nil
        ApplyGroup(scope, "rebuild")
        return true, "Done. Cleared " .. tostring(UNIT_LABELS[scope] or scope) .. " custom anchor."
    end,
})

local function ActionTarget(args)
    local scope = Scope(args and args.scope)
    local specKey = ResolveSpec(args and args.spec)
    local auraName, resolvedSpec, display = ResolveAura(specKey, tostring(args and (args.aura or args.text) or ""))
    return scope, specKey or resolvedSpec, auraName, display or auraName
end

local function SetSpellField(scope, specKey, auraName, field, value)
    local entry = SpellEntry(scope, specKey, auraName, true)
    if not entry then return false end
    if field == "enabled" then entry.enabled = value and true or false
    elseif field == "onlyOwn" then entry.onlyOwn = value and true or false
    elseif field == "placedType" then
        if value == "none" then entry.placed = false else Placed(entry, true).type = value or "icon" end
    elseif field == "placedAnchor" then Placed(entry, true).anchor = value or "TOPLEFT"
    elseif field == "placedSize" then Placed(entry, true).size = ClampNumber(value, 6, 48, 1)
    elseif field == "placedX" then Placed(entry, true).x = ClampNumber(value, -100, 100, 1)
    elseif field == "placedY" then Placed(entry, true).y = ClampNumber(value, -100, 100, 1)
    elseif field == "placedBarWidth" then Placed(entry, true).barWidth = ClampNumber(value, 8, 120, 1)
    elseif field == "placedGrowth" then Placed(entry, true).growth = value or "RIGHTDOWN"
    elseif field == "placedMissing" then Placed(entry, true).missing = value and true or false
    elseif field == "placedCooldownSwipe" then Placed(entry, true).showCooldownSwipe = value and true or false
    elseif field == "placedCooldown" then Placed(entry, true).showCooldown = value and true or false
    elseif field == "placedCooldownSize" then Placed(entry, true).cooldownSize = ClampNumber(value, 6, 24, 1)
    elseif field == "frameType" then
        if value == "none" then entry.frame = false else
            local frame = FrameEffect(entry, true)
            frame.type = value or "border"
            frame.priority = frame.priority or 5
            frame.color = frame.color or { 1, 1, 1, 0.8 }
        end
    elseif field == "framePriority" then FrameEffect(entry, true).priority = ClampNumber(value, 1, 10, 1)
    elseif field == "frameAlpha" then
        local frame = FrameEffect(entry, true)
        local alpha = Clamp01(value, 0.8)
        frame.alpha = alpha
        if type(frame.color) == "table" then frame.color[4] = alpha end
    elseif field == "frameThickness" then FrameEffect(entry, true).thickness = ClampNumber(value, 1, 8, 1)
    elseif field == "frameColor" then
        local frame = FrameEffect(entry, true)
        local alpha = (type(frame.color) == "table" and frame.color[4]) or frame.alpha or 0.8
        frame.color = { Clamp01(type(value) == "table" and (value.r or value[1]) or 1, 1), Clamp01(type(value) == "table" and (value.g or value[2]) or 1, 1), Clamp01(type(value) == "table" and (value.b or value[3]) or 1, 1), alpha }
    else return false end
    ApplySpell(scope)
    return true
end

Registry:RegisterAction({
    key = "set_group_spell_indicator_aura",
    label = "Set Group Spell Indicator Aura",
    type = "configure",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local scope, specKey, auraName, display = ActionTarget(args)
        if not specKey then return false, "I need a supported spell-indicator spec, such as Holy Paladin or Restoration Druid." end
        if not auraName then return false, "I need a supported spell indicator aura for " .. SpecDisplay(specKey) .. "." end
        if not SetSpellField(scope, specKey, auraName, args and args.field, args and args.value) then return false, "That spell indicator field is not available." end
        return true, "Done. " .. tostring(UNIT_LABELS[scope]) .. " " .. SpecDisplay(specKey) .. " " .. tostring(display or auraName) .. " spell indicator updated."
    end,
})

Registry:RegisterAction({
    key = "reset_group_spell_indicator_aura",
    label = "Reset Group Spell Indicator Aura",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local scope, specKey, auraName, display = ActionTarget(args)
        if not specKey then return false, "I need a supported spell-indicator spec to reset." end
        if not auraName then return false, "I need a supported spell indicator aura for " .. SpecDisplay(specKey) .. "." end
        local _, specCfg = SpellEntry(scope, specKey, auraName, true)
        local defaults = SpellRuntime() and SpellRuntime().SpecDefaults and SpellRuntime().SpecDefaults[specKey]
        specCfg[auraName] = type(defaults) == "table" and type(defaults[auraName]) == "table" and CopyTable(defaults[auraName]) or nil
        ApplySpell(scope)
        return true, "Done. Reset " .. tostring(UNIT_LABELS[scope]) .. " " .. SpecDisplay(specKey) .. " " .. tostring(display or auraName) .. " spell indicator."
    end,
})

Registry:RegisterAction({
    key = "set_group_spell_indicator_multi_spec",
    label = "Set Group Spell Indicator Multi-Spec Entry",
    type = "configure",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local scope, specKey = Scope(args and args.scope), ResolveSpec(args and args.spec)
        if not specKey or specKey == "auto" or specKey == "multi" then return false, "I need a concrete spell-indicator spec to track in Multi-Spec mode." end
        local si = SpellDB(scope)
        si.spec = "multi"
        si.multiSpecs = type(si.multiSpecs) == "table" and si.multiSpecs or {}
        si.multiSpecs[specKey] = args and args.value and true or nil
        EnsureSpec(scope, specKey)
        ApplySpell(scope)
        return true, "Done. " .. tostring(UNIT_LABELS[scope]) .. " Multi-Spec tracking for " .. SpecDisplay(specKey) .. " " .. ((args and args.value) and "enabled." or "disabled.")
    end,
})

Registry:RegisterAction({
    key = "move_group_spell_indicator_order",
    label = "Move Group Spell Indicator Order",
    type = "configure",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local scope, specKey, auraName, display = ActionTarget(args)
        if not specKey then return false, "I need a supported spell-indicator spec to reorder." end
        if not auraName then return false, "I need a supported spell indicator aura for " .. SpecDisplay(specKey) .. "." end
        EnsureSpec(scope, specKey)
        local trackable = SpellRuntime() and SpellRuntime().TrackableAuras and SpellRuntime().TrackableAuras[specKey]
        if type(trackable) ~= "table" or #trackable == 0 then return false, "That spell-indicator spec has no ordered spell list." end
        local si = SpellDB(scope)
        si.sortOrder = type(si.sortOrder) == "table" and si.sortOrder or {}
        local order = si.sortOrder[specKey]
        if type(order) ~= "table" or #order == 0 then
            order = {}
            for i = 1, #trackable do order[#order + 1] = trackable[i].name end
            si.sortOrder[specKey] = order
        end
        local from
        for i = 1, #order do if order[i] == auraName then from = i; break end end
        if not from then return false, "That aura is not in the current spell indicator order." end
        local target = tonumber(args and args.position) or from
        if target < 1 then target = 1 end
        if target > #order then target = #order end
        table.remove(order, from)
        if target > from then target = target - 1 end
        table.insert(order, target, auraName)
        ApplySpell(scope)
        return true, "Done. Moved " .. tostring(display or auraName) .. " to spell indicator slot " .. tostring(target) .. "."
    end,
})

Registry:RegisterAction({
    key = "reset_group_corner_indicator_slot",
    label = "Reset Group Corner Indicator Slot",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local scope, slot = Scope(args and args.scope), ResolveSlot(args and args.slot)
        if not slot then return false, "I need a corner slot, such as top left or bottom right." end
        local conf = GroupDB(scope)
        conf["ciSlot" .. slot.key] = slot.default or "none"
        conf["ciCustom" .. slot.key] = nil
        ApplyGroup(scope, "visual")
        return true, "Done. Reset " .. tostring(UNIT_LABELS[scope]) .. " " .. tostring(slot.label) .. " corner indicator."
    end,
})

Registry:RegisterAction({
    key = "reset_group_corner_indicators",
    label = "Reset Group Corner Indicators",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local scope = Scope(args and args.scope)
        local conf = GroupDB(scope)
        conf.ciEnabled, conf.ciSize, conf.ciAlpha = true, 8, 1
        for i = 1, #CI_SLOTS do
            local slot = CI_SLOTS[i]
            conf["ciSlot" .. slot.key] = slot.default or "none"
            conf["ciCustom" .. slot.key] = nil
        end
        ApplyGroup(scope, "visual")
        return true, "Done. Reset " .. tostring(UNIT_LABELS[scope]) .. " corner indicators."
    end,
})
end
