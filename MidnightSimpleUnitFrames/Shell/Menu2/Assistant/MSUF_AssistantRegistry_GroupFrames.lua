-- Assistant GroupFrames registry: declares group layout, bars, status, and copy controls.
-- It writes saved config and delegates secure/header refresh to GroupFrame runtime helpers.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry or { settings = {}, settingsByKey = {}, actions = {}, actionsByKey = {}, todos = {} }
A.Registry = Registry
A.Workflow = A.Workflow or {}

local C = A.RegistryCore
if type(C) ~= "table" then return end

-- GroupFrames registry domain.
-- Registers party/raid/mythicraid controls against the group DB. Group header rebuilds and
-- secure combat deferral remain in the group runtime, not in these assistant setters.
local Registry = C.Registry
local UNIT_LABELS = C.UNIT_LABELS
local AddAliasesForUnit = C.AddAliasesForUnit
local EnsureDB = C.EnsureDB
local GeneralDB = C.GeneralDB
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
        exactAliases = opts.exactAliases,
        booleanAliases = opts.booleanAliases,
        valueAliases = opts.valueAliases,
        intentGuard = opts.intentGuard,
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
        description = opts.description,
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
        description = opts.description,
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
        exactAliases = opts.exactAliases,
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

local function ClearGroupNameShorteningLegacyFlags(conf)
    if type(conf) ~= "table" then return end
    conf.nameShortenOverride = nil
    conf._msufGFNameTruncationOverride = nil
end

local function SetGroupFontOverrideValue(scope, key, value)
    local conf = GroupDB(scope)
    conf.fontOverride = true
    conf[key] = value
    ClearGroupNameShorteningLegacyFlags(conf)
end

local function SharedNameShorteningEnabled()
    local db = EnsureDB and EnsureDB() or _G.MSUF_DB
    return db and db.shortenNames == true
end

local function SharedNameShorteningMax()
    local g = GeneralDB and GeneralDB() or (_G.MSUF_DB and _G.MSUF_DB.general)
    return tonumber(g and g.shortenNameMaxChars) or 6
end

local function SharedNameShorteningSide()
    local g = GeneralDB and GeneralDB() or (_G.MSUF_DB and _G.MSUF_DB.general)
    local side = g and g.shortenNameClipSide
    return side == "RIGHT" and "RIGHT" or "LEFT"
end

local function SharedNameShorteningNoEllipsis()
    local g = GeneralDB and GeneralDB() or (_G.MSUF_DB and _G.MSUF_DB.general)
    return not (g and g.shortenNameShowDots ~= false)
end

local function GroupNameShorteningEnabled(scope)
    local conf = GroupDB(scope)
    if conf.fontOverride == true then
        local value = conf.nameShortenEnabled
        if value == nil then return (tonumber(conf.nameMaxChars) or 0) > 0 end
        return value == true
    end
    return SharedNameShorteningEnabled()
end

local function GroupNameShorteningMax(scope)
    local conf = GroupDB(scope)
    if conf.fontOverride == true then
        local value = tonumber(conf.nameMaxChars)
        if value ~= nil then return value end
        return conf.nameShortenEnabled == true and 6 or 0
    end
    return SharedNameShorteningMax()
end

local function GroupNameShorteningSide(scope)
    local conf = GroupDB(scope)
    if conf.fontOverride == true then
        return conf.nameClipSide == "LEFT" and "LEFT" or "RIGHT"
    end
    return SharedNameShorteningSide()
end

local function GroupNameShorteningNoEllipsis(scope)
    local conf = GroupDB(scope)
    if conf.fontOverride == true then return conf.nameNoEllipsis == true end
    return SharedNameShorteningNoEllipsis()
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

local function GroupBarModeExactAliases(scope)
    local out = {}
    local function add(value)
        if value and value ~= "" then out[#out + 1] = value end
    end
    local function addModePhrases(term)
        add(term .. " class color")
        add(term .. " class colors")
        add(term .. " class colored")
        add(term .. " colored by class")
        add(term .. " use class color")
        add(term .. " use class colors")
        add(term .. " bar color mode")
        add(term .. " health bar color mode")
        add(term .. " group bar style")
        add(term .. " global color")
        add(term .. " global colors")
        add(term .. " use global color")
        add(term .. " use global colors")
        add(term .. " default color")
        add(term .. " default colors")
        add(term .. " use default colors")
    end
    local function addModeForScopePhrases(term)
        add("class color mode for " .. term)
        add("class colors for " .. term)
        add("class colored bars for " .. term)
        add("global colors for " .. term)
        add("default colors for " .. term)
    end
    local scopeTerms = {
        party = { "party", "party frame", "party frames", "partyframe", "partyframes" },
        raid = { "raid", "raid frame", "raid frames", "raidframe", "raidframes" },
        mythicraid = { "mythic raid", "mythic raid frame", "mythic raid frames", "mythicraid", "mythicraidframe", "mythicraidframes" },
    }
    for _, term in ipairs(scopeTerms[scope] or {}) do
        addModePhrases(term)
        addModeForScopePhrases(term)
    end
    for _, term in ipairs({ "group frame", "group frames", "groupframes", "all group frames" }) do
        addModePhrases(term)
        addModeForScopePhrases(term)
    end
    return out
end

local function GroupGrowthExactAliases(scope)
    local out = {}
    local function add(value)
        if value and value ~= "" then out[#out + 1] = value end
    end
    local function addDirectionPhrases(term)
        for _, phrase in ipairs({
            "grow right", "grows right", "to grow right", "frames grow right", "frames to grow right",
            "grow right then down", "grow right and down", "right then down growth", "right first growth",
            "grow left", "grows left", "to grow left", "frames grow left", "frames to grow left",
            "grow left then down", "grow left and down", "left then down growth", "left first growth",
            "grow down", "grows down", "to grow down", "frames grow down", "frames to grow down",
            "grow down then right", "grow down and right", "down then right growth", "down first growth",
            "grow up", "grows up", "to grow up", "frames grow up", "frames to grow up",
            "grow up then right", "grow up and right", "up then right growth", "up first growth",
            "growth right", "growth left", "growth down", "growth up",
            "growth direction right", "growth direction left", "growth direction down", "growth direction up",
        }) do
            add(term .. " " .. phrase)
        end
    end
    local scopeTerms = {
        party = { "party", "party frame", "party frames", "partyframe", "partyframes", "party group", "party groups" },
        raid = { "raid", "raid frame", "raid frames", "raidframe", "raidframes", "raid group", "raid groups" },
        mythicraid = { "mythic raid", "mythic raid frame", "mythic raid frames", "mythicraid", "mythicraidframe", "mythicraidframes", "mythic raid group", "mythic raid groups" },
    }
    for _, term in ipairs(scopeTerms[scope] or {}) do addDirectionPhrases(term) end
    for _, term in ipairs({ "group frame", "group frames", "groupframes", "all group frames" }) do addDirectionPhrases(term) end
    return out
end

local GROUP_REVERSE_FILL_BOOLEAN_ALIASES = {
    ["right to left"] = true,
    ["fill right to left"] = true,
    ["fill backwards"] = true,
    ["fill backward"] = true,
    ["fills backwards"] = true,
    ["fills backward"] = true,
    ["reverse fill"] = true,
    ["reverse direction"] = true,
    ["fill reverse"] = true,
    ["fill reversed"] = true,
    ["other way"] = true,
    ["left to right"] = false,
    ["fill left to right"] = false,
    ["fill left"] = false,
    ["normal direction"] = false,
    ["normal fill"] = false,
    ["fill normal"] = false,
    ["forward fill"] = false,
    ["fill forward"] = false,
    ["same direction"] = false,
}

local function GroupReverseFillExactAliases(scope)
    local out = {}
    local function add(value)
        if value and value ~= "" then out[#out + 1] = value end
    end
    local scopeTerms = {
        party = { "party", "party frame", "party frames", "partyframe", "partyframes" },
        raid = { "raid", "raid frame", "raid frames", "raidframe", "raidframes" },
        mythicraid = { "mythic raid", "mythic raid frame", "mythic raid frames", "mythicraid", "mythicraidframe", "mythicraidframes" },
    }
    local phrases = {
        "reverse fill",
        "reverse health fill",
        "fill backwards",
        "fill backward",
        "fill right to left",
        "right to left fill",
        "fill normal direction",
        "fill normal",
        "normal direction",
        "normal fill",
        "fill left to right",
        "left to right fill",
    }
    for _, term in ipairs(scopeTerms[scope] or {}) do
        for _, phrase in ipairs(phrases) do add(term .. " " .. phrase) end
    end
    for _, term in ipairs({ "group frame", "group frames", "groupframes", "all group frames" }) do
        for _, phrase in ipairs(phrases) do add(term .. " " .. phrase) end
    end
    return out
end

local function GroupReverseFillBooleanAliases(scope)
    local out = {}
    for key, value in pairs(GROUP_REVERSE_FILL_BOOLEAN_ALIASES) do out[key] = value end
    local scopeTerms = {
        party = { "party", "party frame", "party frames", "partyframe", "partyframes" },
        raid = { "raid", "raid frame", "raid frames", "raidframe", "raidframes" },
        mythicraid = { "mythic raid", "mythic raid frame", "mythic raid frames", "mythicraid", "mythicraidframe", "mythicraidframes" },
    }
    for _, term in ipairs(scopeTerms[scope] or {}) do
        out["turn off " .. term .. " reverse fill"] = false
        out["disable " .. term .. " reverse fill"] = false
        out[term .. " reverse fill off"] = false
        out["turn on " .. term .. " reverse fill"] = true
        out["enable " .. term .. " reverse fill"] = true
        out[term .. " reverse fill on"] = true
    end
    return out
end

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
    { value = "roleIcon", label = "Role Icon", enabled = "roleIcon", iconStyle = "roleIconStyle", size = "roleIconSize", anchor = "roleIconAnchor", x = "roleIconX", y = "roleIconY", layer = "roleIconLayer", defaultSize = 12, defaultAnchor = "TOPLEFT", defaultLayer = 1, terms = { "role icon", "role icons", "role indicator", "role indicators", "role symbol", "role symbols" } },
    { value = "leaderIcon", label = "Leader Icon", enabled = "leaderIcon", iconStyle = "leaderIconStyle", size = "leaderIconSize", anchor = "leaderIconAnchor", x = "leaderIconX", y = "leaderIconY", layer = "leaderIconLayer", defaultSize = 12, defaultAnchor = "TOPRIGHT", defaultLayer = 2, terms = { "leader icon", "leader icons", "leader indicator", "leader indicators", "leader symbol", "leader symbols" } },
    { value = "assistIcon", label = "Assist Icon", enabled = "assistIcon", iconStyle = "assistIconStyle", size = "assistIconSize", anchor = "assistIconAnchor", x = "assistIconX", y = "assistIconY", layer = "assistIconLayer", defaultSize = 12, defaultAnchor = "TOPRIGHT", defaultLayer = 2, terms = { "assist icon", "assist icons", "assistant icon", "assistant icons", "assist indicator", "assist indicators", "assistant indicator", "assistant indicators", "assist symbol", "assist symbols", "assistant symbol", "assistant symbols" } },
    { value = "raidMarker", label = "Raid Marker", enabled = "raidMarker", size = "raidMarkerSize", anchor = "raidMarkerAnchor", x = "raidMarkerX", y = "raidMarkerY", layer = "raidMarkerLayer", defaultSize = 14, defaultAnchor = "CENTER", defaultLayer = 3, terms = { "raid marker", "raid marker icon", "raid marker indicator", "raid marker symbol", "target marker", "target marker icon", "target marker indicator", "target marker symbol" } },
    { value = "readyCheckIcon", label = "Ready Check Icon", enabled = "readyCheckIcon", size = "readyCheckSize", anchor = "readyCheckAnchor", x = "readyCheckX", y = "readyCheckY", layer = "readyCheckLayer", defaultSize = 16, defaultAnchor = "CENTER", defaultLayer = 4, terms = { "ready check", "ready check icon", "ready check indicator", "ready check symbol", "ready icon", "ready indicator", "ready symbol" } },
    { value = "summonIcon", label = "Summon Icon", enabled = "summonIcon", size = "summonIconSize", anchor = "summonAnchor", x = "summonX", y = "summonY", layer = "summonLayer", defaultSize = 16, defaultAnchor = "CENTER", defaultLayer = 4, terms = { "summon icon", "summon indicator", "summon symbol" } },
    { value = "resurrectIcon", label = "Resurrect Icon", enabled = "resurrectIcon", size = "resurrectIconSize", anchor = "resurrectAnchor", x = "resurrectX", y = "resurrectY", layer = "resurrectLayer", defaultSize = 16, defaultAnchor = "CENTER", defaultLayer = 4, terms = { "resurrect icon", "resurrect indicator", "resurrect symbol", "resurrection icon", "resurrection indicator", "resurrection symbol", "rez icon", "rez indicator", "rez symbol", "incoming resurrection", "incoming resurrection icon", "incoming resurrection indicator", "incoming resurrection symbol" } },
    { value = "pvpIcon", label = "PvP Flag Icon (War Mode/PvP)", enabled = "pvpIcon", size = "pvpIconSize", anchor = "pvpIconAnchor", x = "pvpIconX", y = "pvpIconY", layer = "pvpIconLayer", defaultSize = 14, defaultAnchor = "TOPLEFT", defaultLayer = 3, description = "Only active in War Mode, Arena/Battleground, or while the player is PvP flagged; PvE instances keep it cold.", terms = { "pvp flag", "pvp icon", "pvp flag icon", "pvp indicator", "pvp flag indicator", "pvp status", "war mode indicator", "flagged indicator" } },
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

A.GroupFramesRegistry = A.GroupFramesRegistry or {}
A.GroupFramesRegistry.Settings = {
    Registry = Registry,
    UNIT_LABELS = UNIT_LABELS,
    AddAliasesForUnit = AddAliasesForUnit,
    GroupDB = GroupDB,
    ClampNumber = ClampNumber,
    ApplyGroup = ApplyGroup,
    RegisterGroupBoolean = RegisterGroupBoolean,
    RegisterGroupNumber = RegisterGroupNumber,
    RegisterGroupEnum = RegisterGroupEnum,
    RegisterGroupString = RegisterGroupString,
    RegisterGroupColor = RegisterGroupColor,
    RegisterGroupTexture = RegisterGroupTexture,
    RegisterGroupTextMode = RegisterGroupTextMode,
    RegisterGroupDelimiter = RegisterGroupDelimiter,
    GroupReverseFillExactAliases = GroupReverseFillExactAliases,
    GroupReverseFillBooleanAliases = GroupReverseFillBooleanAliases,
    GroupNameShorteningMax = GroupNameShorteningMax,
    GroupNameShorteningEnabled = GroupNameShorteningEnabled,
    GroupNameShorteningSide = GroupNameShorteningSide,
    GroupNameShorteningNoEllipsis = GroupNameShorteningNoEllipsis,
    SetGroupFontOverrideValue = SetGroupFontOverrideValue,
    GroupGrowthExactAliases = GroupGrowthExactAliases,
    NormalizeGroupRoleOrder = NormalizeGroupRoleOrder,
    StandardGroupAnchorTarget = StandardGroupAnchorTarget,
    TrimString = TrimString,
    GroupBarModeExactAliases = GroupBarModeExactAliases,
    GroupColorSame = GroupColorSame,
    GetGroupHealthBarColor = GetGroupHealthBarColor,
    SetGroupHealthBarColor = SetGroupHealthBarColor,
    NormalizeGroupDispelTrigger = NormalizeGroupDispelTrigger,
    AddGroupStatusIconAliases = AddGroupStatusIconAliases,
    GROUP_BAR_MODE_VALUES = GROUP_BAR_MODE_VALUES,
    GROUP_HEALTH_MODE_VALUES = GROUP_HEALTH_MODE_VALUES,
    GROUP_ANCHOR_VALUES = GROUP_ANCHOR_VALUES,
    GROUP_ANCHOR_ALIASES = GROUP_ANCHOR_ALIASES,
    GROUP_DISPEL_TRIGGER_VALUES = GROUP_DISPEL_TRIGGER_VALUES,
    GROUP_DISPEL_STYLE_VALUES = GROUP_DISPEL_STYLE_VALUES,
    GROUP_STRIPE_EDGE_VALUES = GROUP_STRIPE_EDGE_VALUES,
    GROUP_RANGE_LAYER_VALUES = GROUP_RANGE_LAYER_VALUES,
    GROUP_STATUS_ICON_STYLE_VALUES = GROUP_STATUS_ICON_STYLE_VALUES,
    GROUP_STATUS_ICON_STYLE_ALIASES = GROUP_STATUS_ICON_STYLE_ALIASES,
    GROUP_STATUS_ICON_PACK_VALUES = GROUP_STATUS_ICON_PACK_VALUES,
    GROUP_STATUS_ICON_PACK_ALIASES = GROUP_STATUS_ICON_PACK_ALIASES,
    GROUP_STATUS_ANCHOR_VALUES = GROUP_STATUS_ANCHOR_VALUES,
    GROUP_STATUS_ANCHOR_ALIASES = GROUP_STATUS_ANCHOR_ALIASES,
    GROUP_STATUS_ICON_SPECS = GROUP_STATUS_ICON_SPECS,
}
A.GroupFramesRegistry = A.GroupFramesRegistry or {}
A.GroupFramesRegistry.Actions = {
    Registry = Registry,
    M = M,
    MSUF = MSUF,
    UNIT_LABELS = UNIT_LABELS,
    ResolveGroupStatusIcon = ResolveGroupStatusIcon,
    ResetGroupStatusIcon = ResetGroupStatusIcon,
    GROUP_STATUS_ICON_SPECS = GROUP_STATUS_ICON_SPECS,
}

end
A.GroupFramesRegistry = A.GroupFramesRegistry or {}
A.GroupFramesRegistry.SpellIndicators = {
    Registry = Registry,
    MSUF = MSUF,
    UNIT_LABELS = UNIT_LABELS,
    AddAliasesForUnit = AddAliasesForUnit,
    GroupDB = GroupDB,
    ClampNumber = ClampNumber,
    ApplyGroup = ApplyGroup,
}
