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

-- Unitframes registry domain. Shared helpers live in MSUF_AssistantRegistry_Core.lua.
local Registry = C.Registry
local UNIT_LABELS = C.UNIT_LABELS
local AddAliasesForUnit = C.AddAliasesForUnit
local MSUF = MSUF
local UnitDB = C.UnitDB
local GeneralDB = C.GeneralDB
local BarsDB = C.BarsDB
local ApplyUnit = C.ApplyUnit
local CallGlobal = C.CallGlobal
local ClampNumber = C.ClampNumber
local RegisterUnitBoolean = C.RegisterUnitBoolean
local RegisterUnitNumber = C.RegisterUnitNumber
local UnitDefaultPower = C.UnitDefaultPower

local UNIT_KEYS = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }
local RANGE_FADE_UNITS = { target = true, targettarget = true, focus = true, focustarget = true, pet = true, boss = true }
for i = 1, #UNIT_KEYS do
    local unit = UNIT_KEYS[i]
    local aliases

    aliases = {}
    AddAliasesForUnit(aliases, unit, "frame", "frame")
    RegisterUnitBoolean(unit, "enabled", "enabled", "Frame Enabled", true, aliases, { category = "Frame", reason = "MSUF_ASSISTANT_FRAME_ENABLED" })

    aliases = {}
    AddAliasesForUnit(aliases, unit, "name", "name")
    AddAliasesForUnit(aliases, unit, "name text", "namen")
    RegisterUnitBoolean(unit, "name", "showName", "Name", true, aliases, { category = "Text", reason = "MSUF_ASSISTANT_NAME", text = true })

    aliases = {}
    AddAliasesForUnit(aliases, unit, "hp text", "hp text")
    AddAliasesForUnit(aliases, unit, "health text", "leben text")
    RegisterUnitBoolean(unit, "hpText", "showHP", "HP Text", true, aliases, { category = "Text", reason = "MSUF_ASSISTANT_HP_TEXT", text = true })

    aliases = {}
    AddAliasesForUnit(aliases, unit, "power text", "power text")
    AddAliasesForUnit(aliases, unit, "mana text", "mana text")
    RegisterUnitBoolean(unit, "powerText", "showPower", "Power Text", UnitDefaultPower(unit), aliases, { category = "Text", reason = "MSUF_ASSISTANT_POWER_TEXT", text = true })

    aliases = {}
    AddAliasesForUnit(aliases, unit, "width", "breite")
    AddAliasesForUnit(aliases, unit, "frame width", "frame breite")
    RegisterUnitNumber(unit, "width", "width", "Width", unit == "boss" and 180 or (unit == "focus" and 180 or 275), 40, 900, aliases, { category = "Frame", reason = "MSUF_ASSISTANT_WIDTH" })

    aliases = {}
    AddAliasesForUnit(aliases, unit, "height", "hoehe")
    AddAliasesForUnit(aliases, unit, "frame height", "frame hoehe")
    RegisterUnitNumber(unit, "height", "height", "Height", unit == "boss" and 30 or (unit == "focus" and 30 or 40), 10, 180, aliases, { category = "Frame", reason = "MSUF_ASSISTANT_HEIGHT" })

    aliases = {}
    AddAliasesForUnit(aliases, unit, "x position", "x position")
    AddAliasesForUnit(aliases, unit, "x offset", "x versatz")
    RegisterUnitNumber(unit, "offsetX", "offsetX", "X Position", 0, -4096, 4096, aliases, { category = "Frame", reason = "MSUF_ASSISTANT_X" })

    aliases = {}
    AddAliasesForUnit(aliases, unit, "y position", "y position")
    AddAliasesForUnit(aliases, unit, "y offset", "y versatz")
    RegisterUnitNumber(unit, "offsetY", "offsetY", "Y Position", 0, -4096, 4096, aliases, { category = "Frame", reason = "MSUF_ASSISTANT_Y" })

    aliases = {}
    AddAliasesForUnit(aliases, unit, "raid marker", "raid marker")
    AddAliasesForUnit(aliases, unit, "raid marker icon", "schlachtzug marker")
    AddAliasesForUnit(aliases, unit, "raid indicator", "raid symbol")
    RegisterUnitBoolean(unit, "raidMarker", "showRaidMarker", "Raid Marker", true, aliases, { category = "Status", reason = "MSUF_ASSISTANT_RAID_MARKER", text = true, refresh = "MSUF_RefreshRaidMarkerFrames" })

    if RANGE_FADE_UNITS[unit] then
        aliases = {}
        AddAliasesForUnit(aliases, unit, "range fade", "range fade")
        AddAliasesForUnit(aliases, unit, "range fading", "reichweite fade")
        RegisterUnitBoolean(unit, "rangeFade", "rangeFadeEnabled", "Range Fade", true, aliases, { category = "Range", reason = "MSUF_ASSISTANT_RANGE_FADE", alpha = true })
    end
end

local POWER_UNITS = { player = true, target = true, focus = true, targettarget = true, focustarget = true, pet = true, boss = true }

local function UnitDefaultPowerBar(unit)
    return not (unit == "targettarget" or unit == "focustarget")
end

local TEXT_ANCHOR_VALUES = { "LEFT", "CENTER", "RIGHT" }
local HP_MODE_VALUES = { "PERCENT", "CURRENT", "MAX", "DEFICIT", "CURMAX", "CURPERCENT", "CURMAXPERCENT", "MAXPERCENT", "PERCENTCUR", "PERCENTMAX", "PERCENTCURMAX", "NONE" }
local POWER_MODE_VALUES = { "CURRENT", "MAX", "CURMAX", "PERCENT", "CURPERCENT", "CURMAXPERCENT", "NONE" }
local SEPARATOR_VALUES = { "", "-", "/", "\\", "|", "<", ">", "~", ":" }
local PORTRAIT_MODE_VALUES = { "OFF", "LEFT", "RIGHT" }
local PORTRAIT_RENDER_VALUES = { "2D", "CLASS" }
local PORTRAIT_SHAPE_VALUES = { "SQUARE", "CIRCLE", "ROUNDED", "DIAMOND" }
local PORTRAIT_BORDER_VALUES = { "NONE", "SOLID", "CLASS_COLOR", "REACTION", "CUSTOM" }
local RANGE_LAYER_VALUES = { "frame", "health" }
local STATUS_ANCHOR_VALUES = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT", "NAMERIGHT", "NAMELEFT" }
local STATUS_CORNER_ANCHOR_VALUES = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local RAID_GROUP_STYLE_VALUES = { "PAREN", "BRACKET", "NONE" }
local STATUS_ICON_PACK_FALLBACK_VALUES = { "BLIZZARD", "CLASSIC", "MIDNIGHT", "GLOSSY_ORBS", "DARK_EMBOSS", "GLASS_PANELS", "NEON_OUTLINE", "RING_SYMBOLS", "DOTS", "SHAPES", "DIAMONDS", "SQUARES" }
local COMBAT_SYMBOL_VALUES = { "DEFAULT", "weapon_axes_crossed", "weapon_bows_crossed", "weapon_crossbows_crossed", "weapon_daggers_crossed", "weapon_fishing_poles_crossed", "weapon_fist_crossed", "weapon_guns_crossed", "weapon_maces_crossed", "weapon_polearms_crossed", "weapon_shuriken", "weapon_staves_crossed", "weapon_swords_crossed", "weapon_thrown_crossed", "weapon_wands_crossed", "weapon_warglaives_crossed" }
local RESTED_SYMBOL_VALUES = { "DEFAULT", "rested_moonzzz", "rested_moonzzzz", "rested_sleep_zzzz", "rested_zzz_compact", "rested_zzz_diag", "rested_zzz_stack" }
local RESS_SYMBOL_VALUES = { "DEFAULT", "resurrection_ankh", "resurrection_cross", "resurrection_soul", "resurrection_wings" }
local ANCHOR_TARGET_VALUES = { "GLOBAL", "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "player", "target", "targettarget", "focustarget", "focus", "pet" }
local ANCHOR_POINT_VALUES = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local BOSS_LAYOUT_VALUES = { "VERTICAL_DOWN", "VERTICAL_UP", "HORIZONTAL_RIGHT", "HORIZONTAL_LEFT" }
local TOT_INLINE_COLOR_VALUES = { "AUTO", "TOT_NAME", "TARGET_NAME", "NPC", "DEFAULT" }
local TOT_INLINE_SEPARATOR_CUSTOM = "__CUSTOM__"

local HP_MODE_ALIASES = {
    percent = "PERCENT",
    ["percent only"] = "PERCENT",
    current = "CURRENT",
    value = "CURRENT",
    max = "MAX",
    maximum = "MAX",
    deficit = "DEFICIT",
    missing = "DEFICIT",
    ["current max"] = "CURMAX",
    ["current / max"] = "CURMAX",
    ["current and max"] = "CURMAX",
    ["current percent"] = "CURPERCENT",
    ["current / percent"] = "CURPERCENT",
    ["current and percent"] = "CURPERCENT",
    ["current max percent"] = "CURMAXPERCENT",
    ["current / max / percent"] = "CURMAXPERCENT",
    ["max percent"] = "MAXPERCENT",
    ["max / percent"] = "MAXPERCENT",
    ["percent current"] = "PERCENTCUR",
    ["percent / current"] = "PERCENTCUR",
    ["percent max"] = "PERCENTMAX",
    ["percent / max"] = "PERCENTMAX",
    ["percent current max"] = "PERCENTCURMAX",
    ["percent / current / max"] = "PERCENTCURMAX",
    none = "NONE",
    off = "NONE",
    hidden = "NONE",
}

local POWER_MODE_ALIASES = {
    current = "CURRENT",
    value = "CURRENT",
    max = "MAX",
    maximum = "MAX",
    ["current max"] = "CURMAX",
    ["current / max"] = "CURMAX",
    ["current and max"] = "CURMAX",
    percent = "PERCENT",
    ["percent only"] = "PERCENT",
    ["current percent"] = "CURPERCENT",
    ["current / percent"] = "CURPERCENT",
    ["current and percent"] = "CURPERCENT",
    ["current max percent"] = "CURMAXPERCENT",
    ["current / max / percent"] = "CURMAXPERCENT",
    none = "NONE",
    off = "NONE",
    hidden = "NONE",
}

local SEPARATOR_ALIASES = {
    space = "",
    blank = "",
    none = "",
    empty = "",
    dash = "-",
    hyphen = "-",
    minus = "-",
    slash = "/",
    ["forward slash"] = "/",
    backslash = "\\",
    pipe = "|",
    bar = "|",
    less = "<",
    ["less than"] = "<",
    greater = ">",
    ["greater than"] = ">",
    tilde = "~",
    colon = ":",
}

local STATUS_ANCHOR_ALIASES = {
    topleft = "TOPLEFT",
    ["top left"] = "TOPLEFT",
    upperleft = "TOPLEFT",
    ["upper left"] = "TOPLEFT",
    topright = "TOPRIGHT",
    ["top right"] = "TOPRIGHT",
    upperright = "TOPRIGHT",
    ["upper right"] = "TOPRIGHT",
    bottomleft = "BOTTOMLEFT",
    ["bottom left"] = "BOTTOMLEFT",
    lowerleft = "BOTTOMLEFT",
    ["lower left"] = "BOTTOMLEFT",
    bottomright = "BOTTOMRIGHT",
    ["bottom right"] = "BOTTOMRIGHT",
    lowerright = "BOTTOMRIGHT",
    ["lower right"] = "BOTTOMRIGHT",
    center = "CENTER",
    middle = "CENTER",
    top = "TOP",
    bottom = "BOTTOM",
    left = "LEFT",
    right = "RIGHT",
    nameright = "NAMERIGHT",
    ["name right"] = "NAMERIGHT",
    ["right to name"] = "NAMERIGHT",
    ["right to player name"] = "NAMERIGHT",
    nameleft = "NAMELEFT",
    ["name left"] = "NAMELEFT",
    ["left to name"] = "NAMELEFT",
    ["left to player name"] = "NAMELEFT",
}

local RAID_GROUP_STYLE_ALIASES = {
    paren = "PAREN",
    parentheses = "PAREN",
    brackets = "BRACKET",
    bracket = "BRACKET",
    none = "NONE",
    plain = "NONE",
}

local BOSS_LAYOUT_ALIASES = {
    ["vertical down"] = "VERTICAL_DOWN",
    down = "VERTICAL_DOWN",
    default = "VERTICAL_DOWN",
    ["top to bottom"] = "VERTICAL_DOWN",
    ["vertical up"] = "VERTICAL_UP",
    up = "VERTICAL_UP",
    ["bottom to top"] = "VERTICAL_UP",
    ["horizontal right"] = "HORIZONTAL_RIGHT",
    right = "HORIZONTAL_RIGHT",
    ["left to right"] = "HORIZONTAL_RIGHT",
    ["horizontal left"] = "HORIZONTAL_LEFT",
    left = "HORIZONTAL_LEFT",
    ["right to left"] = "HORIZONTAL_LEFT",
}

local TOT_INLINE_COLOR_ALIASES = {
    auto = "AUTO",
    automatic = "AUTO",
    ["tot name"] = "TOT_NAME",
    ["target of target name"] = "TOT_NAME",
    ["target name"] = "TARGET_NAME",
    npc = "NPC",
    ["npc type"] = "NPC",
    type = "NPC",
    default = "DEFAULT",
    font = "DEFAULT",
    ["font color"] = "DEFAULT",
}

local STATUS_SYMBOL_ALIASES = {
    default = "DEFAULT",
    axes = "weapon_axes_crossed",
    ["weapon axes"] = "weapon_axes_crossed",
    ["weapon axes crossed"] = "weapon_axes_crossed",
    bows = "weapon_bows_crossed",
    ["weapon bows"] = "weapon_bows_crossed",
    ["weapon bows crossed"] = "weapon_bows_crossed",
    crossbows = "weapon_crossbows_crossed",
    ["weapon crossbows"] = "weapon_crossbows_crossed",
    daggers = "weapon_daggers_crossed",
    ["weapon daggers"] = "weapon_daggers_crossed",
    fishing = "weapon_fishing_poles_crossed",
    ["fishing poles"] = "weapon_fishing_poles_crossed",
    fist = "weapon_fist_crossed",
    ["fist weapons"] = "weapon_fist_crossed",
    guns = "weapon_guns_crossed",
    maces = "weapon_maces_crossed",
    polearms = "weapon_polearms_crossed",
    shuriken = "weapon_shuriken",
    staves = "weapon_staves_crossed",
    swords = "weapon_swords_crossed",
    thrown = "weapon_thrown_crossed",
    wands = "weapon_wands_crossed",
    warglaives = "weapon_warglaives_crossed",
    moon = "rested_moonzzz",
    ["moon 3 z"] = "rested_moonzzz",
    ["moon 4 z"] = "rested_moonzzzz",
    sleep = "rested_sleep_zzzz",
    ["sleep zzzz"] = "rested_sleep_zzzz",
    compact = "rested_zzz_compact",
    ["compact zzz"] = "rested_zzz_compact",
    diagonal = "rested_zzz_diag",
    ["diagonal zzz"] = "rested_zzz_diag",
    stacked = "rested_zzz_stack",
    ["stacked zzz"] = "rested_zzz_stack",
    ankh = "resurrection_ankh",
    cross = "resurrection_cross",
    soul = "resurrection_soul",
    wings = "resurrection_wings",
    ["angelic wings"] = "resurrection_wings",
}

local function MakeAliases(unit, ...)
    local out = {}
    for i = 1, select("#", ...) do
        local noun = select(i, ...)
        if type(noun) == "string" and noun ~= "" then
            AddAliasesForUnit(out, unit, noun)
        end
    end
    return out
end

local function AddVerbUnitNounAliases(out, unit, verbs, noun)
    local unitAliases = (A.UnitAliases and A.UnitAliases[unit]) or { unit }
    for v = 1, #(verbs or {}) do
        local verb = verbs[v]
        for i = 1, #unitAliases do
            local unitText = unitAliases[i]
            out[#out + 1] = tostring(verb) .. " " .. tostring(unitText) .. " " .. tostring(noun)
        end
    end
end

local function ExpandStatusAliases(aliases)
    local out = {}
    local seen = {}
    local function add(value)
        value = tostring(value or "")
        if value == "" or seen[value] then return end
        seen[value] = true
        out[#out + 1] = value
    end
    for i = 1, #(aliases or {}) do
        local alias = tostring(aliases[i] or "")
        add(alias)
        if alias:find("raid marker", 1, true) then
            add(alias:gsub(" marker", " indicator"))
            add(alias:gsub(" marker", " icon"))
            add(alias:gsub(" marker", " symbol"))
        end
        if alias:find(" icon", 1, true) then
            add(alias:gsub(" icon", " indicator"))
            add(alias:gsub(" icon", " symbol"))
        end
        if alias:find(" indicator", 1, true) then
            add(alias:gsub(" indicator", " icon"))
            add(alias:gsub(" indicator", " symbol"))
        end
        if alias:find(" symbol", 1, true) then
            add(alias:gsub(" symbol", " icon"))
            add(alias:gsub(" symbol", " indicator"))
        end
    end
    return out
end

local function AllowedMap(values)
    local allowed = {}
    for i = 1, #(values or {}) do allowed[values[i]] = true end
    return allowed
end

local function UnitApply(unit, opts, defaultReason)
    opts = opts or {}
    ApplyUnit(unit, opts.reason or defaultReason or "MSUF_ASSISTANT_UNIT", opts.applyOpts or {
        preview = true,
        text = opts.text,
        power = opts.power,
        alpha = opts.alpha,
        castbar = opts.castbar,
    })
    if opts.refresh then CallGlobal(opts.refresh) end
    if opts.fonts then
        CallGlobal("MSUF_UpdateAllFonts_Immediate")
        CallGlobal("MSUF_UpdateAllFonts")
    end
end

local function RegisterUnitBooleanSetting(unit, attr, dbKey, label, defaultValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = unit .. "." .. (opts.keySuffix or dbKey),
        label = UNIT_LABELS[unit] .. " " .. label,
        category = UNIT_LABELS[unit] .. " / " .. (opts.category or "Frame"),
        unit = unit,
        frameType = opts.frameType or "unitframe",
        attribute = attr,
        type = "boolean",
        aliases = aliases,
        get = function()
            if opts.get then return opts.get(unit) end
            local value = UnitDB(unit)[dbKey]
            if value == nil then return defaultValue and true or false end
            return value and true or false
        end,
        set = function(value)
            if opts.set then
                opts.set(unit, value and true or false)
                return
            end
            UnitDB(unit)[dbKey] = value and true or false
        end,
        apply = function()
            if opts.apply then
                opts.apply(unit)
            else
                UnitApply(unit, opts, "MSUF_ASSISTANT_" .. tostring(dbKey))
            end
        end,
        combatSafe = opts.combatSafe == true,
        applyWhenUnchanged = opts.applyWhenUnchanged == true,
        description = opts.description,
    })
end

local function RegisterUnitNumberSetting(unit, attr, dbKey, label, defaultValue, minValue, maxValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = unit .. "." .. (opts.keySuffix or dbKey),
        label = UNIT_LABELS[unit] .. " " .. label,
        category = UNIT_LABELS[unit] .. " / " .. (opts.category or "Frame"),
        unit = unit,
        frameType = opts.frameType or "unitframe",
        attribute = attr,
        type = "number",
        aliases = aliases,
        min = minValue,
        max = maxValue,
        step = opts.step or 1,
        percent = opts.percent == true,
        get = function()
            if opts.get then return opts.get(unit) end
            local value = tonumber(UnitDB(unit)[dbKey])
            if value == nil and opts.fallbackGeneral then value = tonumber(GeneralDB()[dbKey]) end
            if value == nil then return defaultValue end
            return value
        end,
        set = function(value)
            value = ClampNumber(value, minValue, maxValue, opts.step or 1)
            if opts.set then
                opts.set(unit, value)
                return
            end
            UnitDB(unit)[dbKey] = value
        end,
        apply = function() UnitApply(unit, opts, "MSUF_ASSISTANT_" .. tostring(dbKey)) end,
        combatSafe = opts.combatSafe == true,
        description = opts.description,
    })
end

local function RegisterUnitEnum(unit, attr, dbKey, label, defaultValue, values, aliases, opts)
    opts = opts or {}
    local allowed = AllowedMap(values)
    Registry:RegisterSetting({
        key = unit .. "." .. (opts.keySuffix or dbKey),
        label = UNIT_LABELS[unit] .. " " .. label,
        category = UNIT_LABELS[unit] .. " / " .. (opts.category or "Frame"),
        unit = unit,
        frameType = opts.frameType or "unitframe",
        attribute = attr,
        type = "enum",
        aliases = aliases,
        values = values,
        valueAliases = opts.valueAliases,
        get = function()
            if opts.get then return opts.get(unit) end
            local value = UnitDB(unit)[dbKey]
            if allowed[value] then return value end
            if opts.fallbackGeneral then
                value = GeneralDB()[dbKey]
                if allowed[value] then return value end
            end
            return defaultValue
        end,
        set = function(value)
            if not allowed[value] then value = defaultValue end
            if opts.set then
                opts.set(unit, value)
                return
            end
            UnitDB(unit)[dbKey] = value
        end,
        apply = function() UnitApply(unit, opts, "MSUF_ASSISTANT_" .. tostring(dbKey)) end,
        combatSafe = opts.combatSafe == true,
        description = opts.description,
    })
end

local function RegisterUnitString(unit, attr, dbKey, label, defaultValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = unit .. "." .. (opts.keySuffix or dbKey),
        label = UNIT_LABELS[unit] .. " " .. label,
        category = UNIT_LABELS[unit] .. " / " .. (opts.category or "Frame"),
        unit = unit,
        frameType = opts.frameType or "unitframe",
        attribute = attr,
        type = "string",
        aliases = aliases,
        valuePrefixes = opts.valuePrefixes or aliases,
        mediaType = opts.mediaType,
        normalizesValue = opts.normalizeValue ~= nil,
        get = function()
            local value = UnitDB(unit)[dbKey]
            if type(value) ~= "string" or value == "" then value = defaultValue or "" end
            if opts.normalizeValue then value = opts.normalizeValue(value) end
            return value
        end,
        set = function(value)
            if opts.normalizeValue then value = opts.normalizeValue(value) end
            if opts.set then
                opts.set(unit, value)
                return
            end
            UnitDB(unit)[dbKey] = tostring(value or "")
        end,
        apply = function()
            if opts.apply then
                opts.apply(unit)
            else
                UnitApply(unit, opts, "MSUF_ASSISTANT_" .. tostring(dbKey))
            end
        end,
        combatSafe = opts.combatSafe == true,
        description = opts.description,
    })
end

local function RegisterGeneralNestedBoolean(rootKey, dbKey, attr, label, defaultValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "general." .. rootKey .. "." .. dbKey,
        label = label,
        category = opts.category or "Global",
        unit = opts.unit or "global",
        frameType = opts.frameType or "unitframe",
        attribute = attr,
        type = "boolean",
        aliases = aliases,
        get = function()
            local root = GeneralDB()[rootKey]
            if type(root) == "table" then
                local value = root[dbKey]
                if value ~= nil then return value and true or false end
            end
            return defaultValue and true or false
        end,
        set = function(value)
            local g = GeneralDB()
            g[rootKey] = type(g[rootKey]) == "table" and g[rootKey] or {}
            g[rootKey][dbKey] = value and true or false
        end,
        apply = function()
            if opts.apply then opts.apply(opts.reason or ("MSUF_ASSISTANT_" .. dbKey)) end
        end,
        combatSafe = opts.combatSafe == true,
        description = opts.description,
    })
end

local function ApplyStatus(unit, reason, statusRuntime, level)
    if statusRuntime then
        CallGlobal("MSUF_RefreshStatusIndicators")
        CallGlobal("MSUF_RequestStatusIconsRefreshForCurrent")
    end
    if level then
        CallGlobal("MSUF_UpdateAllFonts_Immediate")
        CallGlobal("MSUF_UpdateAllFonts")
        if unit == "boss" and _G.MSUF_BossTestMode and type(_G.MSUF_ApplyBossUnitframePreviewState) == "function" then
            _G.MSUF_ApplyBossUnitframePreviewState(true, reason or "MSUF_ASSISTANT_STATUS")
        end
    end
    ApplyUnit(unit, reason or "MSUF_ASSISTANT_STATUS", { preview = true, text = true })
end

local function ApplyStatusRefresh(unit, refresh, statusRuntime, level)
    if refresh then CallGlobal(refresh) end
    ApplyStatus(unit, "MSUF_ASSISTANT_STATUS", statusRuntime, level)
end

local function ApplyLoadCondition(unit)
    local conf = UnitDB(unit)
    local active = false
    local keys = {
        "loadCondHideMounted", "loadCondHideOutOfCombat", "loadCondHideSolo", "loadCondHideInVehicle", "loadCondHideInGroup",
        "loadCondHideInInstance", "loadCondHideResting", "loadCondHideInCombat", "loadCondHideStealthed",
    }
    for i = 1, #keys do
        if conf[keys[i]] == true then active = true; break end
    end
    conf.loadCondActive = active or nil
    ApplyUnit(unit, "MSUF_ASSISTANT_LOAD_CONDITION", { preview = true })
end

local function ApplyToTInline(reason)
    ApplyUnit("target", reason or "MSUF_ASSISTANT_TOT_INLINE", { text = true, preview = true })
    ApplyUnit("targettarget", reason or "MSUF_ASSISTANT_TOT_INLINE", { text = true, preview = true })
    local UF = MSUF and MSUF.UF
    if UF and type(UF.ForceUpdate) == "function" then UF.ForceUpdate("targettarget") end
    CallGlobal("MSUF_UpdateTargetToTInlineNow")
    CallGlobal("MSUF_UFPreview_RequestRefresh", reason or "MSUF_ASSISTANT_TOT_INLINE")
end

local function CleanToTInlineCustomSeparator(value)
    if M and type(M.CleanToTInlineCustomSeparator) == "function" then return M.CleanToTInlineCustomSeparator(value, 5) end
    value = tostring(value or ""):gsub("[%c]", " ")
    return value:sub(1, 5)
end

local function NormalizeToTInlineSeparatorValue(value)
    if value == TOT_INLINE_SEPARATOR_CUSTOM then return value end
    if value == nil or value == "" then return " " end
    return tostring(value)
end

local function NormalizeToTInlineColor(value)
    value = tostring(value or "AUTO")
    for i = 1, #TOT_INLINE_COLOR_VALUES do
        if TOT_INLINE_COLOR_VALUES[i] == value then return value end
    end
    return "AUTO"
end

local function NormalizeBossLayoutMode(value)
    if value == "VERTICAL_DOWN" or value == "VERTICAL_UP" or value == "HORIZONTAL_RIGHT" or value == "HORIZONTAL_LEFT" then return value end
    return "VERTICAL_DOWN"
end

local function TextValue(unit, dbKey, defaultValue)
    local conf = UnitDB(unit)
    local seed = _G.MSUF_Bars_SeedTextFromGeneral
    if type(seed) == "function" then seed(conf) end
    local value = conf[dbKey]
    if value ~= nil then return value end
    value = GeneralDB()[dbKey]
    if value ~= nil then return value end
    return defaultValue
end

local function TextNumber(unit, dbKey, generalKey, defaultValue)
    local value = tonumber(UnitDB(unit)[dbKey])
    if value == nil then value = tonumber(GeneralDB()[generalKey or dbKey]) end
    if value == nil then value = tonumber(GeneralDB().fontSize) end
    if value == nil then value = defaultValue end
    return value
end

local function NormalizePortraitMode(unit)
    local value = UnitDB(unit).portraitMode or "OFF"
    if value ~= "LEFT" and value ~= "RIGHT" then return "OFF" end
    return value
end

local function NormalizePortraitClassStyle(value)
    value = tostring(value or "")
    local normalized = value:upper():gsub("%s+", "_"):gsub("%-", "_")
    if normalized == "RONDO_COLOR" or normalized == "RONDO_WOW" or normalized == "BLIZZARD" then return normalized end
    if M and type(M.NormalizePortraitClassStyle) == "function" then return M.NormalizePortraitClassStyle(value) end
    local fn = _G.MSUF_NormalizePortraitClassStyleValue
    if type(fn) == "function" then return fn(value) end
    return "BLIZZARD"
end

local function InitDetachedPowerBar(unit)
    local conf = UnitDB(unit)
    conf.detachedPowerBarOffsetX = tonumber(conf.detachedPowerBarOffsetX) or 0
    conf.detachedPowerBarOffsetY = tonumber(conf.detachedPowerBarOffsetY) or -4
    conf.detachedPowerBarWidth = tonumber(conf.detachedPowerBarWidth) or tonumber(conf.width) or (unit == "focus" and 180 or 275)
    conf.detachedPowerBarHeight = tonumber(conf.detachedPowerBarHeight) or 6
    conf.detachedPowerBarFrameLevelOffset = tonumber(conf.detachedPowerBarFrameLevelOffset) or 6
    if unit == "player" and conf.detachedPowerBarSyncClassPower == nil then conf.detachedPowerBarSyncClassPower = true end
end

local function RegisterUnitTextNumber(unit, attr, dbKey, label, defaultValue, aliases, opts)
    opts = opts or {}
    opts.category = opts.category or "Text"
    opts.text = true
    opts.fonts = opts.fonts == true
    opts.get = opts.get or function(unitKey) return TextNumber(unitKey, dbKey, opts.generalKey, defaultValue) end
    RegisterUnitNumberSetting(unit, attr, dbKey, label, defaultValue, opts.min or -300, opts.max or 300, aliases, opts)
end

local function AnchorValueTerms(value)
    if value == "GLOBAL" then return { "global", "global anchor", "default" } end
    if value == "EssentialCooldownViewer" then return { "essential cooldown viewer", "essential cooldown manager", "essential cooldownmanager", "essential cooldowns", "cooldown manager", "cooldownmanager", "cooldowns manager", "cdm", "ecv" } end
    if value == "UtilityCooldownViewer" then return { "utility cooldown viewer", "utility cooldown manager", "utility cooldownmanager", "utility cooldowns", "ucv" } end
    if value == "BuffIconCooldownViewer" then return { "tracked buffs viewer", "tracked buff viewer", "buff icon cooldown viewer", "tracked buffs", "tracked buffs manager" } end
    if value == "targettarget" then return { "targettarget", "target of target", "tot" } end
    if value == "focustarget" then return { "focustarget", "focus target" } end
    return { value }
end

local function BuildAnchorValueAliases(unit)
    local aliases = {
        global = "GLOBAL",
        default = "GLOBAL",
        ["global anchor"] = "GLOBAL",
        ["essential cooldown viewer"] = "EssentialCooldownViewer",
        ["essential cooldown manager"] = "EssentialCooldownViewer",
        ["essential cooldownmanager"] = "EssentialCooldownViewer",
        ["essential cooldowns"] = "EssentialCooldownViewer",
        ["cooldown manager"] = "EssentialCooldownViewer",
        cooldownmanager = "EssentialCooldownViewer",
        ["cooldowns manager"] = "EssentialCooldownViewer",
        cdm = "EssentialCooldownViewer",
        ecv = "EssentialCooldownViewer",
        ["utility cooldown viewer"] = "UtilityCooldownViewer",
        ["utility cooldown manager"] = "UtilityCooldownViewer",
        ["utility cooldownmanager"] = "UtilityCooldownViewer",
        ["utility cooldowns"] = "UtilityCooldownViewer",
        ucv = "UtilityCooldownViewer",
        ["tracked buffs viewer"] = "BuffIconCooldownViewer",
        ["tracked buff viewer"] = "BuffIconCooldownViewer",
        ["buff icon cooldown viewer"] = "BuffIconCooldownViewer",
        ["tracked buffs"] = "BuffIconCooldownViewer",
        ["tracked buffs manager"] = "BuffIconCooldownViewer",
        player = "player",
        target = "target",
        targettarget = "targettarget",
        ["target of target"] = "targettarget",
        tot = "targettarget",
        focustarget = "focustarget",
        ["focus target"] = "focustarget",
        focus = "focus",
        pet = "pet",
    }
    for i = 1, #ANCHOR_TARGET_VALUES do
        local value = ANCHOR_TARGET_VALUES[i]
        local terms = AnchorValueTerms(value)
        for j = 1, #terms do
            local term = terms[j]
            aliases["anchor to " .. term] = value
            aliases[tostring(unit) .. " anchor to " .. term] = value
            aliases[tostring(unit) .. " anchor target " .. term] = value
        end
    end
    return aliases
end

local STATUS_CONTROL_SPECS = {
    {
        value = "leader", label = "Leader / Assist", show = "showLeaderIcon", defaultShow = true, size = "leaderIconSize", defaultSize = 14,
        anchor = "leaderIconAnchor", defaultAnchor = "TOPLEFT", x = "leaderIconOffsetX", defaultX = 0, y = "leaderIconOffsetY", defaultY = 3,
        layer = "leaderIconLayer", defaultLayer = 7, refresh = "MSUF_RefreshLeaderIconFrames", iconStyle = "leaderIconStyle",
        defaultIconStyle = "BLIZZARD", units = { player = true, target = true }, aliases = { "leader icon", "leader indicator", "assist icon", "assist indicator", "leader assist icon", "leader assist indicator" },
    },
    {
        value = "raidmarker", label = "Raid Marker", show = "showRaidMarker", defaultShow = true, size = "raidMarkerSize", defaultSize = 18,
        anchor = "raidMarkerAnchor", defaultAnchor = "TOPLEFT", x = "raidMarkerOffsetX", defaultX = 16, y = "raidMarkerOffsetY", defaultY = 3,
        layer = "raidMarkerLayer", defaultLayer = 7, refresh = "MSUF_RefreshRaidMarkerFrames", aliases = { "raid marker", "raid marker icon", "raid marker indicator", "raid indicator", "raid icon", "raid symbol", "target marker", "target marker icon", "target marker indicator" },
    },
    {
        value = "level", label = "Level Indicator", show = "showLevelIndicator", defaultShow = true, size = "levelIndicatorSize", defaultSize = 14,
        anchor = "levelIndicatorAnchor", defaultAnchor = "NAMERIGHT", x = "levelIndicatorOffsetX", defaultX = 0, y = "levelIndicatorOffsetY", defaultY = 0,
        layer = "levelIndicatorLayer", defaultLayer = 7, refresh = "MSUF_RefreshLevelIndicatorFrames", level = true, nameAnchors = true,
        aliases = { "level", "level indicator", "level text" },
    },
    {
        value = "raidgroupname", label = "Raid Group Name", show = "showRaidGroupInName", defaultShow = false, size = "nameFontSize", defaultSize = 14,
        anchor = "raidGroupNameAnchor", defaultAnchor = "NAMERIGHT", x = "raidGroupNameOffsetX", defaultX = 3, y = "raidGroupNameOffsetY", defaultY = 0,
        layer = "nameTextLayer", defaultLayer = 5, refresh = "MSUF_RefreshRaidGroupNameFrames", inlineName = true, nameAnchors = true,
        units = { player = true, target = true, targettarget = true, focustarget = true, focus = true },
        aliases = { "raid group name", "raid group", "group number in name", "subgroup name", "raid group indicator", "group number indicator", "subgroup indicator" },
    },
    {
        value = "eliteicon", label = "Elite / Rare Icon", show = "showEliteIcon", defaultShow = true, size = "eliteIconSize", defaultSize = 20,
        anchor = "eliteIconAnchor", defaultAnchor = "TOPRIGHT", x = "eliteIconOffsetX", defaultX = 2, y = "eliteIconOffsetY", defaultY = 2,
        layer = "eliteIconLayer", defaultLayer = 7, refresh = "MSUF_RefreshEliteIconFrames",
        units = { target = true, focus = true, targettarget = true, focustarget = true, boss = true },
        aliases = { "elite icon", "rare icon", "elite rare icon" },
    },
    {
        value = "statusText", label = "Dead Text", show = "statusTextEnabled", defaultShow = true, size = "statusTextSize", defaultSize = 16,
        anchor = "statusTextAnchor", defaultAnchor = "CENTER", x = "statusTextOffsetX", defaultX = 0, y = "statusTextOffsetY", defaultY = 0,
        layer = "statusTextLayer", defaultLayer = 7, refresh = "MSUF_RequestStatusTextRefresh", statusRuntime = true,
        aliases = { "dead text", "status text", "ghost text", "offline text", "dead indicator", "ghost indicator", "offline indicator" },
    },
    {
        value = "statusCombat", label = "Combat Indicator", show = "showCombatStateIndicator", defaultShow = true, size = "combatStateIndicatorSize", defaultSize = 18,
        anchor = "combatStateIndicatorAnchor", defaultAnchor = "TOPLEFT", x = "combatStateIndicatorOffsetX", defaultX = 0, y = "combatStateIndicatorOffsetY", defaultY = 0,
        layer = "combatStateIndicatorLayer", defaultLayer = 7, refresh = "MSUF_RequestStatusCombatIndicatorRefresh", symbol = "combatStateIndicatorSymbol",
        symbolValues = COMBAT_SYMBOL_VALUES, statusRuntime = true, units = { player = true, target = true },
        aliases = { "combat indicator", "combat state indicator", "combat status indicator", "combat icon", "combat state icon", "combat symbol", "combat state symbol" },
    },
    {
        value = "statusResting", label = "Rested Indicator", show = "showRestingIndicator", defaultShow = false, size = "restedStateIndicatorSize", defaultSize = 18,
        anchor = "restedStateIndicatorAnchor", defaultAnchor = "TOPLEFT", x = "restedStateIndicatorOffsetX", defaultX = 0, y = "restedStateIndicatorOffsetY", defaultY = 0,
        layer = "restedStateIndicatorLayer", defaultLayer = 7, refresh = "MSUF_RequestStatusRestingIndicatorRefresh", symbol = "restedStateIndicatorSymbol",
        symbolValues = RESTED_SYMBOL_VALUES, statusRuntime = true, units = { player = true },
        aliases = { "rested indicator", "resting indicator", "rested icon", "resting icon", "rested symbol", "resting symbol" },
    },
    {
        value = "statusIncomingRes", label = "Incoming Rez Indicator", show = "showIncomingResIndicator", defaultShow = true, size = "incomingResIndicatorSize", defaultSize = 18,
        anchor = "incomingResIndicatorAnchor", defaultAnchor = "TOPRIGHT", x = "incomingResIndicatorOffsetX", defaultX = 0, y = "incomingResIndicatorOffsetY", defaultY = 0,
        layer = "incomingResIndicatorLayer", defaultLayer = 7, refresh = "MSUF_RequestStatusIncomingResIndicatorRefresh", symbol = "incomingResIndicatorSymbol",
        symbolValues = RESS_SYMBOL_VALUES, statusRuntime = true, units = { player = true, target = true },
        aliases = { "incoming rez indicator", "incoming resurrection indicator", "incoming rez icon", "incoming resurrection icon", "incoming rez symbol", "incoming resurrection symbol", "rez indicator", "rez icon", "rez symbol", "resurrection indicator", "resurrection icon", "resurrection symbol" },
    },
    {
        value = "statusPvp", label = "PvP Flag Indicator (War Mode/PvP)", show = "showPvpIndicator", defaultShow = true, size = "pvpIndicatorSize", defaultSize = 18,
        anchor = "pvpIndicatorAnchor", defaultAnchor = "TOPRIGHT", x = "pvpIndicatorOffsetX", defaultX = 0, y = "pvpIndicatorOffsetY", defaultY = 0,
        layer = "pvpIndicatorLayer", defaultLayer = 7, refresh = "MSUF_RequestStatusPvpIndicatorRefresh", statusRuntime = true,
        units = { player = true, target = true, focus = true, targettarget = true, focustarget = true },
        description = "Only active in War Mode, Arena/Battleground, or while the player is PvP flagged; PvE instances keep it cold.",
        aliases = { "pvp flag", "pvp flag indicator", "pvp indicator", "pvp icon", "pvp flag icon", "pvp status", "pvp status indicator", "pvp status icon", "war mode indicator", "flagged indicator" },
    },
}
for i = 1, #STATUS_CONTROL_SPECS do
    STATUS_CONTROL_SPECS[i].aliases = ExpandStatusAliases(STATUS_CONTROL_SPECS[i].aliases)
end

local function NormalizeStatusPhrase(text)
    text = tostring(text or ""):lower()
    text = text:gsub("target%s+of%s+target", "targettarget")
    text = text:gsub("focus%s+target", "focustarget")
    text = text:gsub("[\"'`]", "")
    text = text:gsub("[^%w]+", " ")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "))
end

local function StatusPhraseContains(text, phrase)
    phrase = NormalizeStatusPhrase(phrase)
    if phrase == "" then return false end
    return (" " .. text .. " "):find(" " .. phrase .. " ", 1, true) ~= nil
end

local function StatusSpecAllowed(unit, spec)
    return spec and (not spec.units or spec.units[unit] == true)
end

local function ResolveUnitStatusSpec(unit, text)
    text = NormalizeStatusPhrase(text)
    for i = 1, #STATUS_CONTROL_SPECS do
        local spec = STATUS_CONTROL_SPECS[i]
        if StatusSpecAllowed(unit, spec) then
            if StatusPhraseContains(text, spec.label) or StatusPhraseContains(text, spec.value) then return spec end
            for j = 1, #(spec.aliases or {}) do
                if StatusPhraseContains(text, spec.aliases[j]) then return spec end
            end
        end
    end
    return nil
end

A.ResolveUnitStatusSpec = ResolveUnitStatusSpec

local LOAD_CONDITION_SPECS = {
    { key = "loadCondHideMounted", label = "Hide Mounted", aliases = { "hide mounted", "mounted load condition" } },
    { key = "loadCondHideOutOfCombat", label = "Hide Out Of Combat", aliases = { "hide out of combat", "out of combat load condition" } },
    { key = "loadCondHideSolo", label = "Hide Solo", aliases = { "hide solo", "solo load condition" } },
    { key = "loadCondHideInVehicle", label = "Hide In Vehicle", aliases = { "hide in vehicle", "vehicle load condition" } },
    { key = "loadCondHideInGroup", label = "Hide In Group", aliases = { "hide in group", "group load condition" } },
    { key = "loadCondHideInInstance", label = "Hide In Instance", aliases = { "hide in instance", "instance load condition" } },
    { key = "loadCondHideResting", label = "Hide Resting", aliases = { "hide resting", "resting load condition" } },
    { key = "loadCondHideInCombat", label = "Hide In Combat", aliases = { "hide in combat", "combat load condition" } },
    { key = "loadCondHideStealthed", label = "Hide Stealthed", aliases = { "hide stealthed", "stealth load condition" } },
}

for i = 1, #UNIT_KEYS do
    local unit = UNIT_KEYS[i]

    RegisterUnitBooleanSetting(unit, "reverseFillBars", "reverseFillBars", "Reverse Fill Direction", false, MakeAliases(unit, "reverse fill direction", "reverse health fill", "reverse bar fill"), {
        category = "Frame",
        reason = "MSUF_ASSISTANT_REVERSE_FILL",
    })
    RegisterUnitBooleanSetting(unit, "smoothFill", "smoothFill", "Smooth Health Fill", true, MakeAliases(unit, "smooth fill", "smooth health fill", "smooth frame fill"), {
        category = "Frame",
        reason = "MSUF_ASSISTANT_SMOOTH_FILL",
    })

    local anchorTargetAliases = MakeAliases(unit, "anchor to", "anchor target", "anchor frame")
    for av = 1, #ANCHOR_TARGET_VALUES do
        local anchorValue = ANCHOR_TARGET_VALUES[av]
        if anchorValue ~= unit then
            AddAliasesForUnit(anchorTargetAliases, unit, "anchor to " .. anchorValue)
        end
    end
    AddAliasesForUnit(anchorTargetAliases, unit, "anchor to target of target")
    AddAliasesForUnit(anchorTargetAliases, unit, "anchor to focus target")
    AddAliasesForUnit(anchorTargetAliases, unit, "anchor to global")
    RegisterUnitEnum(unit, "anchorToUnitframe", "anchorToUnitframe", "Anchor To", "GLOBAL", ANCHOR_TARGET_VALUES, anchorTargetAliases, {
        category = "Anchoring",
        valueAliases = BuildAnchorValueAliases(unit),
        get = function(unitKey)
            local conf = UnitDB(unitKey)
            local custom = type(conf.anchorFrameName) == "string" and conf.anchorFrameName or ""
            if custom ~= "" then return "GLOBAL" end
            local value = conf.anchorToUnitframe
            local allowed = AllowedMap(ANCHOR_TARGET_VALUES)
            if allowed[value] and value ~= unitKey then return value end
            return "GLOBAL"
        end,
        set = function(unitKey, value)
            local conf = UnitDB(unitKey)
            if value == unitKey then value = "GLOBAL" end
            conf.anchorToUnitframe = value or "GLOBAL"
            conf.anchorFrameName = nil
        end,
    })
    RegisterUnitEnum(unit, "anchorPoint", "point", "Anchor Point", "CENTER", ANCHOR_POINT_VALUES, MakeAliases(unit, "anchor point", "frame anchor point", "anchor position"), {
        category = "Anchoring",
        valueAliases = STATUS_ANCHOR_ALIASES,
        set = function(unitKey, value)
            local conf = UnitDB(unitKey)
            conf.point = value or "CENTER"
            conf.relativePoint = value or "CENTER"
        end,
    })
    RegisterUnitString(unit, "anchorFrameName", "anchorFrameName", "Custom Anchor Frame", "", MakeAliases(unit, "custom anchor frame", "anchor frame name", "custom anchor"), {
        category = "Anchoring",
        description = "Frame name used by the custom anchor text box. The UI picker remains an interactive helper.",
        set = function(unitKey, value)
            UnitDB(unitKey).anchorFrameName = tostring(value or "")
            UnitDB(unitKey).anchorToUnitframe = "GLOBAL"
        end,
    })

    RegisterUnitEnum(unit, "portraitMode", "portraitMode", "Portrait Position", "OFF", PORTRAIT_MODE_VALUES, MakeAliases(unit, "portrait", "portrait position", "portrait side"), {
        category = "Portrait",
        valueAliases = {
            off = "OFF",
            hide = "OFF",
            hidden = "OFF",
            disabled = "OFF",
            disable = "OFF",
            aus = "OFF",
            on = "LEFT",
            enable = "LEFT",
            enabled = "LEFT",
            show = "LEFT",
            visible = "LEFT",
            an = "LEFT",
            left = "LEFT",
            right = "RIGHT",
        },
        get = NormalizePortraitMode,
        set = function(unitKey, value) UnitDB(unitKey).portraitMode = value end,
    })
    RegisterUnitEnum(unit, "portraitRender", "portraitRender", "Portrait Render", "2D", PORTRAIT_RENDER_VALUES, MakeAliases(unit, "portrait render", "portrait type", "class portrait"), {
        category = "Portrait",
        valueAliases = {
            ["2d"] = "2D",
            ["2d portrait"] = "2D",
            portrait = "2D",
            class = "CLASS",
            ["class portrait"] = "CLASS",
        },
    })
    RegisterUnitEnum(unit, "portraitShape", "portraitShape", "Portrait Shape", "SQUARE", PORTRAIT_SHAPE_VALUES, MakeAliases(unit, "portrait shape"), {
        category = "Portrait",
        valueAliases = {
            square = "SQUARE",
            circle = "CIRCLE",
            round = "CIRCLE",
            rounded = "ROUNDED",
            diamond = "DIAMOND",
        },
    })
    RegisterUnitNumberSetting(unit, "portraitSizeOverride", "portraitSizeOverride", "Portrait Size Override", 0, 0, 128, MakeAliases(unit, "portrait size", "portrait size override"), { category = "Portrait" })
    RegisterUnitNumberSetting(unit, "portraitOffsetX", "portraitOffsetX", "Portrait X Offset", 0, -120, 120, MakeAliases(unit, "portrait x", "portrait x offset"), { category = "Portrait" })
    RegisterUnitNumberSetting(unit, "portraitOffsetY", "portraitOffsetY", "Portrait Y Offset", 0, -120, 120, MakeAliases(unit, "portrait y", "portrait y offset"), { category = "Portrait" })
    RegisterUnitString(unit, "portraitClassStyle", "portraitClassStyle", "Class Portrait Style", "BLIZZARD", MakeAliases(unit, "portrait class style", "class portrait style"), {
        category = "Portrait",
        normalizeValue = NormalizePortraitClassStyle,
        description = "PortraitMedia class portrait pack key; values are provided dynamically by the UI.",
    })
    RegisterUnitEnum(unit, "portraitBorderStyle", "portraitBorderStyle", "Portrait Border", "NONE", PORTRAIT_BORDER_VALUES, MakeAliases(unit, "portrait border", "portrait border style"), {
        category = "Portrait",
        valueAliases = {
            none = "NONE",
            off = "NONE",
            hide = "NONE",
            hidden = "NONE",
            disable = "NONE",
            disabled = "NONE",
            aus = "NONE",
            on = "SOLID",
            enable = "SOLID",
            enabled = "SOLID",
            show = "SOLID",
            visible = "SOLID",
            an = "SOLID",
            solid = "SOLID",
            class = "CLASS_COLOR",
            ["class color"] = "CLASS_COLOR",
            reaction = "REACTION",
            ["reaction color"] = "REACTION",
            custom = "CUSTOM",
            ["custom color"] = "CUSTOM",
        },
    })
    RegisterUnitNumberSetting(unit, "portraitBorderThickness", "portraitBorderThickness", "Portrait Border Thickness", 2, 1, 12, MakeAliases(unit, "portrait border thickness", "portrait border size", "portrait border thicker", "portrait border thinner"), { category = "Portrait" })
    RegisterUnitBooleanSetting(unit, "portraitFillBorder", "portraitFillBorder", "Portrait Fill Border Gap", false, MakeAliases(unit, "portrait fill border", "fill portrait border gap"), { category = "Portrait" })
    RegisterUnitBooleanSetting(unit, "portraitBgEnabled", "portraitBgEnabled", "Portrait Background", false, MakeAliases(unit, "portrait background", "portrait bg"), { category = "Portrait" })

    if POWER_UNITS[unit] then
        RegisterUnitBooleanSetting(unit, "powerBar", "showPowerBar", "Power Bar", UnitDefaultPowerBar(unit), MakeAliases(unit, "power bar", "show power bar"), { category = "Power Bar", power = true })
        RegisterUnitBooleanSetting(unit, "powerBarBorder", "powerBarBorderEnabled", "Power Bar Border", false, MakeAliases(unit, "power bar border", "power border"), {
            category = "Power Bar",
            power = true,
            get = function(unitKey)
                local conf = UnitDB(unitKey)
                if conf.powerBarBorderEnabled ~= nil then return conf.powerBarBorderEnabled == true end
                return BarsDB().powerBarBorderEnabled == true
            end,
        })
        RegisterUnitNumberSetting(unit, "powerBarHeight", "powerBarHeight", "Power Bar Height", 3, 1, 20, MakeAliases(unit, "power bar height", "power height"), {
            category = "Power Bar",
            power = true,
            get = function(unitKey) return tonumber(UnitDB(unitKey).powerBarHeight) or tonumber(BarsDB().powerBarHeight) or 3 end,
        })
        RegisterUnitNumberSetting(unit, "powerBarBorderThickness", "powerBarBorderThickness", "Power Bar Border Thickness", 1, 0, 6, MakeAliases(unit, "power bar border thickness", "power border size"), {
            category = "Power Bar",
            power = true,
            get = function(unitKey) return tonumber(UnitDB(unitKey).powerBarBorderThickness) or tonumber(BarsDB().powerBarBorderThickness or BarsDB().powerBarBorderSize) or 1 end,
        })
        RegisterUnitBooleanSetting(unit, "embedPowerBarIntoHealth", "embedPowerBarIntoHealth", "Embed Power Bar Into Health", false, MakeAliases(unit, "embed power bar", "embed power into health", "power bar embedded"), {
            category = "Power Bar",
            power = true,
            get = function(unitKey)
                local conf = UnitDB(unitKey)
                if conf.embedPowerBarIntoHealth ~= nil then return conf.embedPowerBarIntoHealth == true end
                return BarsDB().embedPowerBarIntoHealth == true
            end,
        })
        RegisterUnitBooleanSetting(unit, "powerSmoothFill", "powerSmoothFill", "Power Bar Smooth Fill", unit == "player", MakeAliases(unit, "power smooth fill", "smooth power bar"), { category = "Power Bar", power = true })
        local detachedPowerAliases = MakeAliases(unit, "detached power bar", "detach power bar", "power bar detached")
        AddVerbUnitNounAliases(detachedPowerAliases, unit, { "detach", "undock", "attach", "dock" }, "power bar")
        AddVerbUnitNounAliases(detachedPowerAliases, unit, { "abkoppeln", "ankoppeln" }, "power balken")
        RegisterUnitBooleanSetting(unit, "powerBarDetached", "powerBarDetached", "Detach Power Bar From Frame", false, detachedPowerAliases, {
            category = "Power Bar",
            power = true,
            set = function(unitKey, value)
                UnitDB(unitKey).powerBarDetached = value and true or false
                if value then InitDetachedPowerBar(unitKey) end
            end,
        })
        RegisterUnitBooleanSetting(unit, "detachedPowerBarTextOnBar", "detachedPowerBarTextOnBar", "Text On Detached Power Bar", false, MakeAliases(unit, "text on detached power bar", "detached power text on bar"), { category = "Power Bar", power = true, text = true })
        if unit == "player" then
            RegisterUnitBooleanSetting(unit, "detachedPowerBarSyncClassPower", "detachedPowerBarSyncClassPower", "Detached Power Bar Syncs To Class Resource Width", true, MakeAliases(unit, "detached power sync class resource", "sync power bar to class resource"), {
                category = "Power Bar",
                power = true,
                get = function(unitKey) return UnitDB(unitKey).detachedPowerBarSyncClassPower ~= false end,
            })
            RegisterUnitBooleanSetting(unit, "detachedPowerBarAnchorToClassPower", "detachedPowerBarAnchorToClassPower", "Detached Power Bar Anchors To Class Resource", false, MakeAliases(unit, "anchor detached power to class resource", "detached power anchor class resource"), { category = "Power Bar", power = true })
        end
        RegisterUnitNumberSetting(unit, "detachedPowerBarOffsetX", "detachedPowerBarOffsetX", "Detached Power Bar X Offset", 0, -1000, 1000, MakeAliases(unit, "detached power x", "detached power bar x offset"), { category = "Power Bar", power = true })
        RegisterUnitNumberSetting(unit, "detachedPowerBarOffsetY", "detachedPowerBarOffsetY", "Detached Power Bar Y Offset", -4, -1000, 1000, MakeAliases(unit, "detached power y", "detached power bar y offset"), { category = "Power Bar", power = true })
        RegisterUnitNumberSetting(unit, "detachedPowerBarWidth", "detachedPowerBarWidth", "Detached Power Bar Width", unit == "focus" and 180 or 275, 20, 800, MakeAliases(unit, "detached power width", "detached power bar width"), {
            category = "Power Bar",
            power = true,
            get = function(unitKey) return tonumber(UnitDB(unitKey).detachedPowerBarWidth) or tonumber(UnitDB(unitKey).width) or (unitKey == "focus" and 180 or 275) end,
        })
        RegisterUnitNumberSetting(unit, "detachedPowerBarHeight", "detachedPowerBarHeight", "Detached Power Bar Height", 6, 2, 80, MakeAliases(unit, "detached power height", "detached power bar height"), { category = "Power Bar", power = true })
        RegisterUnitNumberSetting(unit, "detachedPowerBarFrameLevelOffset", "detachedPowerBarFrameLevelOffset", "Detached Power Bar Layer", 6, 0, 20, MakeAliases(unit, "detached power layer", "detached power bar frame level"), { category = "Power Bar", power = true })
    end

    RegisterUnitEnum(unit, "nameTextAnchor", "nameTextAnchor", "Name Text Anchor", "LEFT", TEXT_ANCHOR_VALUES, MakeAliases(unit, "name anchor", "name text anchor"), {
        category = "Text",
        text = true,
        valueAliases = { left = "LEFT", center = "CENTER", middle = "CENTER", right = "RIGHT" },
        get = function(unitKey) return TextValue(unitKey, "nameTextAnchor", "LEFT") end,
    })
    RegisterUnitTextNumber(unit, "nameOffsetX", "nameOffsetX", "Name X Offset", 4, MakeAliases(unit, "name x", "name x offset"), { min = -300, max = 300 })
    RegisterUnitTextNumber(unit, "nameOffsetY", "nameOffsetY", "Name Y Offset", -4, MakeAliases(unit, "name y", "name y offset"), { min = -300, max = 300 })
    RegisterUnitTextNumber(unit, "nameFontSize", "nameFontSize", "Name Font Size", 14, MakeAliases(unit, "name size", "name font size"), { min = 6, max = 48, fonts = true, generalKey = "nameFontSize" })

    RegisterUnitEnum(unit, "hpTextLeft", "textLeft", "HP Left Slot", "NONE", HP_MODE_VALUES, MakeAliases(unit, "hp left slot", "health left slot", "left hp text"), { category = "Text", text = true, valueAliases = HP_MODE_ALIASES, get = function(unitKey) return TextValue(unitKey, "textLeft", TextValue(unitKey, "hpTextMode", "NONE")) end })
    RegisterUnitEnum(unit, "hpTextCenter", "textCenter", "HP Center Slot", "NONE", HP_MODE_VALUES, MakeAliases(unit, "hp center slot", "health center slot", "center hp text"), { category = "Text", text = true, valueAliases = HP_MODE_ALIASES, get = function(unitKey) return TextValue(unitKey, "textCenter", TextValue(unitKey, "hpTextMode", "NONE")) end })
    RegisterUnitEnum(unit, "hpTextRight", "textRight", "HP Right Slot", "CURPERCENT", HP_MODE_VALUES, MakeAliases(unit, "hp right slot", "health right slot", "right hp text"), { category = "Text", text = true, valueAliases = HP_MODE_ALIASES, get = function(unitKey) return TextValue(unitKey, "textRight", TextValue(unitKey, "hpTextMode", "CURPERCENT")) end })
    RegisterUnitEnum(unit, "hpTextSeparator", "hpTextSeparator", "HP Text Delimiter", "", SEPARATOR_VALUES, MakeAliases(unit, "hp text delimiter", "hp text separator", "health text delimiter"), { category = "Text", text = true, valueAliases = SEPARATOR_ALIASES, get = function(unitKey) return TextValue(unitKey, "hpTextSeparator", "") end })
    RegisterUnitBooleanSetting(unit, "hpTextReverse", "hpTextReverse", "Reverse HP Text Order", false, MakeAliases(unit, "reverse hp text", "hp text reverse order"), { category = "Text", text = true })
    RegisterUnitTextNumber(unit, "hpOffsetX", "hpOffsetX", "HP Text X Offset", -4, MakeAliases(unit, "hp text x", "health text x offset"), { min = -300, max = 300 })
    RegisterUnitTextNumber(unit, "hpOffsetY", "hpOffsetY", "HP Text Y Offset", -4, MakeAliases(unit, "hp text y", "health text y offset"), { min = -300, max = 300 })
    RegisterUnitTextNumber(unit, "hpFontSize", "hpFontSize", "HP Font Size", 14, MakeAliases(unit, "hp text size", "hp font size", "health text size"), { min = 6, max = 48, fonts = true, generalKey = "hpFontSize" })

    RegisterUnitEnum(unit, "powerTextLeft", "powerTextLeft", "Power Left Slot", "NONE", POWER_MODE_VALUES, MakeAliases(unit, "power left slot", "mana left slot", "left power text"), { category = "Text", text = true, valueAliases = POWER_MODE_ALIASES, get = function(unitKey) return TextValue(unitKey, "powerTextLeft", TextValue(unitKey, "powerTextMode", "NONE")) end })
    RegisterUnitEnum(unit, "powerTextCenter", "powerTextCenter", "Power Center Slot", "NONE", POWER_MODE_VALUES, MakeAliases(unit, "power center slot", "mana center slot", "center power text"), { category = "Text", text = true, valueAliases = POWER_MODE_ALIASES, get = function(unitKey) return TextValue(unitKey, "powerTextCenter", TextValue(unitKey, "powerTextMode", "NONE")) end })
    RegisterUnitEnum(unit, "powerTextRight", "powerTextRight", "Power Right Slot", "CURPERCENT", POWER_MODE_VALUES, MakeAliases(unit, "power right slot", "mana right slot", "right power text"), { category = "Text", text = true, valueAliases = POWER_MODE_ALIASES, get = function(unitKey) return TextValue(unitKey, "powerTextRight", TextValue(unitKey, "powerTextMode", "CURPERCENT")) end })
    RegisterUnitEnum(unit, "powerTextSeparator", "powerTextSeparator", "Power Text Delimiter", "", SEPARATOR_VALUES, MakeAliases(unit, "power text delimiter", "power text separator", "mana text delimiter"), { category = "Text", text = true, valueAliases = SEPARATOR_ALIASES, get = function(unitKey) return TextValue(unitKey, "powerTextSeparator", TextValue(unitKey, "hpTextSeparator", "")) end })
    RegisterUnitTextNumber(unit, "powerOffsetX", "powerOffsetX", "Power Text X Offset", -4, MakeAliases(unit, "power text x", "mana text x offset"), { min = -300, max = 300 })
    RegisterUnitTextNumber(unit, "powerOffsetY", "powerOffsetY", "Power Text Y Offset", 4, MakeAliases(unit, "power text y", "mana text y offset"), { min = -300, max = 300 })
    RegisterUnitTextNumber(unit, "powerFontSize", "powerFontSize", "Power Font Size", 14, MakeAliases(unit, "power text size", "power font size", "mana text size"), { min = 6, max = 48, fonts = true, generalKey = "powerFontSize" })

    local hpSlots = {
        { suffix = "Left", label = "HP Left Slot", keyPrefix = "hpTextLeft", alias = "hp left slot" },
        { suffix = "Center", label = "HP Center Slot", keyPrefix = "hpTextCenter", alias = "hp center slot" },
        { suffix = "Right", label = "HP Right Slot", keyPrefix = "hpTextRight", alias = "hp right slot" },
    }
    for s = 1, #hpSlots do
        local slot = hpSlots[s]
        RegisterUnitTextNumber(unit, slot.keyPrefix .. "OffsetX", slot.keyPrefix .. "OffsetX", slot.label .. " X Offset", 0, MakeAliases(unit, slot.alias .. " x", slot.alias .. " x offset"), { min = -300, max = 300 })
        RegisterUnitTextNumber(unit, slot.keyPrefix .. "OffsetY", slot.keyPrefix .. "OffsetY", slot.label .. " Y Offset", 0, MakeAliases(unit, slot.alias .. " y", slot.alias .. " y offset"), { min = -300, max = 300 })
    end
    local powerSlots = {
        { label = "Power Left Slot", keyPrefix = "powerTextLeft", alias = "power left slot" },
        { label = "Power Center Slot", keyPrefix = "powerTextCenter", alias = "power center slot" },
        { label = "Power Right Slot", keyPrefix = "powerTextRight", alias = "power right slot" },
    }
    for s = 1, #powerSlots do
        local slot = powerSlots[s]
        RegisterUnitTextNumber(unit, slot.keyPrefix .. "OffsetX", slot.keyPrefix .. "OffsetX", slot.label .. " X Offset", 0, MakeAliases(unit, slot.alias .. " x", slot.alias .. " x offset"), { min = -300, max = 300 })
        RegisterUnitTextNumber(unit, slot.keyPrefix .. "OffsetY", slot.keyPrefix .. "OffsetY", slot.label .. " Y Offset", 0, MakeAliases(unit, slot.alias .. " y", slot.alias .. " y offset"), { min = -300, max = 300 })
    end

    RegisterUnitTextNumber(unit, "nameTextLayer", "nameTextLayer", "Name Text Layer", 5, MakeAliases(unit, "name text layer", "name layer"), { min = 0, max = 30, fonts = true })
    RegisterUnitTextNumber(unit, "hpTextLayer", "hpTextLayer", "HP Text Layer", 5, MakeAliases(unit, "hp text layer", "health text layer"), { min = 0, max = 30, fonts = true })
    RegisterUnitTextNumber(unit, "powerTextLayer", "powerTextLayer", "Power Text Layer", 2, MakeAliases(unit, "power text layer", "mana text layer"), { min = 0, max = 30, fonts = true })

    -- Unified transparency: HP bar fill opacity, background opacity, and a toggle to
    -- keep text + portrait opaque while the bars dim.
    RegisterUnitNumberSetting(unit, "hpBarAlpha", "hpBarAlpha", "HP Bar Opacity", 1, 0, 1, MakeAliases(unit, "hp bar opacity", "health bar opacity", "hp opacity", "hp alpha", "bar opacity"), {
        category = "Transparency",
        alpha = true,
        step = 0.05,
        percent = true,
    })
    RegisterUnitNumberSetting(unit, "hpBgAlpha", "hpBgAlpha", "Background Opacity", 0.85, 0, 1, MakeAliases(unit, "background opacity", "backdrop opacity", "background alpha", "bg opacity", "hp track opacity", "health track opacity", "track opacity", "bar background opacity"), {
        category = "Transparency",
        step = 0.05,
        percent = true,
    })
    RegisterUnitBooleanSetting(unit, "alphaExcludeTextPortrait", "alphaExcludeTextPortrait", "Keep Text & Portrait Visible", false, MakeAliases(unit, "keep text visible", "keep text portrait visible", "keep text and portrait visible", "exclude text from opacity", "keep portrait visible", "exclude portrait from opacity"), { category = "Transparency", alpha = true })

    if RANGE_FADE_UNITS[unit] then
        RegisterUnitNumberSetting(unit, "rangeFadeAlpha", "rangeFadeAlpha", "Range Fade Opacity", 0.4, 0, 1, MakeAliases(unit, "range fade opacity", "range fade alpha"), { category = "Range", alpha = true, step = 0.05, percent = true })
        RegisterUnitEnum(unit, "rangeFadeLayerMode", "rangeFadeLayerMode", "Range Fade Affects", "frame", RANGE_LAYER_VALUES, MakeAliases(unit, "range fade affects", "range fade layer", "range fade mode"), {
            category = "Range",
            alpha = true,
            valueAliases = {
                frame = "frame",
                whole = "frame",
                ["whole frame"] = "frame",
                hp = "health",
                health = "health",
                ["hp only"] = "health",
                ["health only"] = "health",
            },
        })
    end

    if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then
        RegisterUnitBooleanSetting(unit, "showInterrupt", "showInterrupt", "Show Castbar Interrupt", true, MakeAliases(unit, "show interrupt", "castbar interrupt", "castbar show interrupt"), {
            category = "Castbar",
            frameType = "castbar",
            castbar = true,
        })
    end

    for s = 1, #STATUS_CONTROL_SPECS do
        local spec = STATUS_CONTROL_SPECS[s]
        if not spec.units or spec.units[unit] == true then
            local aliases = {}
            for a = 1, #(spec.aliases or {}) do
                local alias = spec.aliases[a]
                aliases[#aliases + 1] = alias
                AddAliasesForUnit(aliases, unit, alias)
            end
            RegisterUnitBooleanSetting(unit, spec.show, spec.show, spec.label, spec.defaultShow, aliases, {
                category = "Status Icons",
                frameType = "unitframe",
                reason = "MSUF_ASSISTANT_STATUS_" .. spec.value,
                refresh = spec.refresh,
                text = true,
                applyOpts = { preview = true, text = true },
                description = spec.description or ("Status icon visibility for " .. spec.label .. "."),
            })

            if spec.iconStyle then
                aliases = {}
                for a = 1, #(spec.aliases or {}) do
                    local base = tostring(spec.aliases[a] or "")
                    local alias
                    if base:match(" icon pack$") then
                        alias = base
                    elseif base:match(" icon$") then
                        alias = base .. " pack"
                    else
                        alias = base .. " icon pack"
                    end
                    aliases[#aliases + 1] = alias
                    AddAliasesForUnit(aliases, unit, alias)
                end
                RegisterUnitString(unit, spec.iconStyle, spec.iconStyle, spec.label .. " Icon Pack", spec.defaultIconStyle or "BLIZZARD", aliases, {
                    category = "Status Icons",
                    description = "Status icon pack key. The dropdown values can be provided dynamically by the UI; fallback values include " .. table.concat(STATUS_ICON_PACK_FALLBACK_VALUES, ", ") .. ".",
                    applyOpts = { preview = true, text = true },
                    refresh = spec.refresh,
                })
            end

            if spec.symbol then
                aliases = {}
                for a = 1, #(spec.aliases or {}) do
                    local base = spec.aliases[a]
                    local alias = tostring(base):find("symbol", 1, true) and base or (tostring(base) .. " symbol")
                    aliases[#aliases + 1] = alias
                    AddAliasesForUnit(aliases, unit, alias)
                end
                RegisterUnitEnum(unit, spec.symbol, spec.symbol, spec.label .. " Symbol", "DEFAULT", spec.symbolValues or { "DEFAULT" }, aliases, {
                    category = "Status Icons",
                    valueAliases = STATUS_SYMBOL_ALIASES,
                    refresh = spec.refresh,
                    applyOpts = { preview = true, text = true },
                })
            end

            aliases = {}
            for a = 1, #(spec.aliases or {}) do
                local alias = spec.aliases[a] .. " size"
                aliases[#aliases + 1] = alias
                AddAliasesForUnit(aliases, unit, alias)
            end
            RegisterUnitNumberSetting(unit, spec.value .. "Size", spec.size, spec.label .. " Size", spec.defaultSize, 8, 64, aliases, {
                category = "Status Icons",
                keySuffix = spec.size,
                refresh = spec.refresh,
                get = function(unitKey) return tonumber(UnitDB(unitKey)[spec.size]) or tonumber(GeneralDB()[spec.size]) or spec.defaultSize end,
                applyOpts = { preview = true, text = true },
            })

            aliases = {}
            for a = 1, #(spec.aliases or {}) do
                local alias = spec.aliases[a] .. " anchor"
                aliases[#aliases + 1] = alias
                AddAliasesForUnit(aliases, unit, alias)
            end
            RegisterUnitEnum(unit, spec.value .. "Anchor", spec.anchor, spec.label .. " Anchor", spec.defaultAnchor, spec.nameAnchors and STATUS_ANCHOR_VALUES or STATUS_CORNER_ANCHOR_VALUES, aliases, {
                category = "Status Icons",
                keySuffix = spec.anchor,
                valueAliases = STATUS_ANCHOR_ALIASES,
                refresh = spec.refresh,
                get = function(unitKey)
                    local value = UnitDB(unitKey)[spec.anchor] or GeneralDB()[spec.anchor]
                    local allowed = AllowedMap(spec.nameAnchors and STATUS_ANCHOR_VALUES or STATUS_CORNER_ANCHOR_VALUES)
                    return allowed[value] and value or spec.defaultAnchor
                end,
                applyOpts = { preview = true, text = true },
            })

            aliases = {}
            for a = 1, #(spec.aliases or {}) do
                local alias = spec.aliases[a] .. " x offset"
                aliases[#aliases + 1] = alias
                AddAliasesForUnit(aliases, unit, alias)
            end
            RegisterUnitNumberSetting(unit, spec.value .. "OffsetX", spec.x, spec.label .. " X Offset", spec.defaultX, -1000, 1000, aliases, {
                category = "Status Icons",
                keySuffix = spec.x,
                refresh = spec.refresh,
                applyOpts = { preview = true, text = true },
            })

            aliases = {}
            for a = 1, #(spec.aliases or {}) do
                local alias = spec.aliases[a] .. " y offset"
                aliases[#aliases + 1] = alias
                AddAliasesForUnit(aliases, unit, alias)
            end
            RegisterUnitNumberSetting(unit, spec.value .. "OffsetY", spec.y, spec.label .. " Y Offset", spec.defaultY, -1000, 1000, aliases, {
                category = "Status Icons",
                keySuffix = spec.y,
                refresh = spec.refresh,
                applyOpts = { preview = true, text = true },
            })

            aliases = {}
            for a = 1, #(spec.aliases or {}) do
                local alias = spec.aliases[a] .. " layer"
                aliases[#aliases + 1] = alias
                AddAliasesForUnit(aliases, unit, alias)
            end
            RegisterUnitNumberSetting(unit, spec.value .. "Layer", spec.layer, spec.label .. " Layer", spec.defaultLayer, 1, 10, aliases, {
                category = "Status Icons",
                keySuffix = spec.layer,
                refresh = spec.refresh,
                applyOpts = { preview = true, text = true },
            })

            if spec.value == "raidgroupname" then
                aliases = MakeAliases(unit, "raid group style", "raid group name style", "group number style")
                RegisterUnitEnum(unit, "raidGroupNameStyle", "raidGroupNameStyle", "Raid Group Name Style", "PAREN", RAID_GROUP_STYLE_VALUES, aliases, {
                    category = "Status Icons",
                    valueAliases = RAID_GROUP_STYLE_ALIASES,
                    refresh = spec.refresh,
                    applyOpts = { preview = true, text = true },
                })
            end
        end
    end

    RegisterUnitBooleanSetting(unit, "stateIconsTestMode", "stateIconsTestMode", "Status Icon Test Mode", false, MakeAliases(unit,
        "status icon test mode",
        "status icons test mode",
        "test status icons",
        "test status icon",
        "status icon preview mode",
        "status icons preview mode",
        "status preview mode",
        "status indicator test mode",
        "test status indicators"
    ), {
        category = "Status Icons",
        get = function(unitKey)
            local value = UnitDB(unitKey).stateIconsTestMode
            if value == nil then value = GeneralDB().stateIconsTestMode end
            return value == true
        end,
        refresh = "MSUF_RequestStatusIconsRefreshForCurrent",
        applyOpts = { preview = true, text = true },
        applyWhenUnchanged = true,
    })

    for l = 1, #LOAD_CONDITION_SPECS do
        local spec = LOAD_CONDITION_SPECS[l]
        local aliases = {}
        for a = 1, #(spec.aliases or {}) do AddAliasesForUnit(aliases, unit, spec.aliases[a]) end
        RegisterUnitBooleanSetting(unit, spec.key, spec.key, spec.label, false, aliases, {
            category = "Load Conditions",
            frameType = "unitframe",
            apply = function() ApplyLoadCondition(unit) end,
            set = function(unitKey, value)
                UnitDB(unitKey)[spec.key] = value and true or false
            end,
            applyOpts = { preview = true },
        })
    end
end

RegisterGeneralNestedBoolean("statusIndicators", "showDead", "statusTextDead", "Dead Text Shows Dead Units", true, { "dead text dead units", "status text dead units", "show dead text for dead" }, {
    category = "Status Icons",
    apply = function() CallGlobal("MSUF_RequestStatusTextRefresh"); ApplyUnit("player", "MSUF_ASSISTANT_STATUS_TEXT_STATE", { preview = true, text = true }) end,
})
RegisterGeneralNestedBoolean("statusIndicators", "showGhost", "statusTextGhost", "Dead Text Shows Ghost Units", true, { "dead text ghost units", "status text ghost units", "show ghost text" }, {
    category = "Status Icons",
    apply = function() CallGlobal("MSUF_RequestStatusTextRefresh"); ApplyUnit("player", "MSUF_ASSISTANT_STATUS_TEXT_STATE", { preview = true, text = true }) end,
})
RegisterGeneralNestedBoolean("statusIndicators", "showAFK", "statusTextAFK", "Dead Text Shows AFK Units", false, { "dead text afk", "status text afk", "show afk text", "afk text", "afk indicator", "afk status indicator" }, {
    category = "Status Icons",
    apply = function() CallGlobal("MSUF_RequestStatusTextRefresh"); ApplyUnit("player", "MSUF_ASSISTANT_STATUS_TEXT_STATE", { preview = true, text = true }) end,
})
RegisterGeneralNestedBoolean("statusIndicators", "showDND", "statusTextDND", "Dead Text Shows DND Units", false, { "dead text dnd", "status text dnd", "show dnd text", "dnd text", "dnd indicator", "dnd status indicator" }, {
    category = "Status Icons",
    apply = function() CallGlobal("MSUF_RequestStatusTextRefresh"); ApplyUnit("player", "MSUF_ASSISTANT_STATUS_TEXT_STATE", { preview = true, text = true }) end,
})

Registry:RegisterSetting({
    key = "general.statusIconsUseMidnightStyle",
    label = "Status Icons Use Midnight Style",
    category = "Status Icons",
    unit = "global",
    frameType = "unitframe",
    attribute = "statusIconsUseMidnightStyle",
    type = "boolean",
    aliases = { "status icons midnight style", "use midnight status icons", "midnight status icon style" },
    get = function() return GeneralDB().statusIconsUseMidnightStyle == true end,
    set = function(value) GeneralDB().statusIconsUseMidnightStyle = value and true or false end,
    apply = function()
        CallGlobal("MSUF_SetStatusIconStyleUseMidnight", GeneralDB().statusIconsUseMidnightStyle == true)
        CallGlobal("MSUF_RequestStatusIconsRefreshForCurrent")
    end,
    combatSafe = false,
})

Registry:RegisterSetting({
    key = "targettarget.showToTInTargetName",
    label = "Target Target Inline Text",
    category = "Target / Inline Text",
    unit = "target",
    frameType = "unitframe",
    attribute = "totInline",
    type = "boolean",
    aliases = { "target inline text", "target of target inline text", "show target of target text inline", "tot inline text" },
    get = function() return UnitDB("targettarget").showToTInTargetName == true end,
    set = function(value) UnitDB("targettarget").showToTInTargetName = value and true or false end,
    apply = function() ApplyToTInline("MSUF_ASSISTANT_TOT_INLINE") end,
    combatSafe = false,
})
Registry:RegisterSetting({
    key = "targettarget.totInlineColorMode",
    label = "Target Target Inline Color",
    category = "Target / Inline Text",
    unit = "target",
    frameType = "unitframe",
    attribute = "totInlineColor",
    type = "enum",
    aliases = { "target inline color", "target of target inline color", "tot inline color" },
    values = TOT_INLINE_COLOR_VALUES,
    valueAliases = TOT_INLINE_COLOR_ALIASES,
    get = function() return NormalizeToTInlineColor(UnitDB("targettarget").totInlineColorMode) end,
    set = function(value) UnitDB("targettarget").totInlineColorMode = NormalizeToTInlineColor(value) end,
    apply = function() ApplyToTInline("MSUF_ASSISTANT_TOT_INLINE_COLOR") end,
    combatSafe = false,
})
Registry:RegisterSetting({
    key = "targettarget.totInlineSeparator",
    label = "Target Target Inline Separator",
    category = "Target / Inline Text",
    unit = "target",
    frameType = "unitframe",
    attribute = "totInlineSeparator",
    type = "enum",
    aliases = { "target inline separator", "target of target inline separator", "tot inline separator", "target inline delimiter" },
    values = { "", "-", "/", "\\", "|", "<", ">", "~", ":", TOT_INLINE_SEPARATOR_CUSTOM },
    valueAliases = SEPARATOR_ALIASES,
    get = function()
        local value = UnitDB("targettarget").totInlineSeparator
        if value == nil or value == "" then return "|" end
        return value
    end,
    set = function(value)
        if value == TOT_INLINE_SEPARATOR_CUSTOM then
            UnitDB("targettarget").totInlineSeparator = TOT_INLINE_SEPARATOR_CUSTOM
            UnitDB("targettarget").totInlineCustomSeparator = CleanToTInlineCustomSeparator(UnitDB("targettarget").totInlineCustomSeparator)
        else
            UnitDB("targettarget").totInlineSeparator = NormalizeToTInlineSeparatorValue(value)
        end
    end,
    apply = function() ApplyToTInline("MSUF_ASSISTANT_TOT_INLINE_SEPARATOR") end,
    combatSafe = false,
})
Registry:RegisterSetting({
    key = "targettarget.totInlineCustomSeparator",
    label = "Target Target Inline Custom Separator",
    category = "Target / Inline Text",
    unit = "target",
    frameType = "unitframe",
    attribute = "totInlineCustomSeparator",
    type = "string",
    aliases = { "target inline custom separator", "target of target inline custom separator", "tot inline custom separator" },
    valuePrefixes = { "target inline custom separator", "target of target inline custom separator", "tot inline custom separator" },
    get = function() return CleanToTInlineCustomSeparator(UnitDB("targettarget").totInlineCustomSeparator) end,
    set = function(value)
        UnitDB("targettarget").totInlineCustomSeparator = CleanToTInlineCustomSeparator(value)
        UnitDB("targettarget").totInlineSeparator = TOT_INLINE_SEPARATOR_CUSTOM
    end,
    apply = function() ApplyToTInline("MSUF_ASSISTANT_TOT_INLINE_CUSTOM_SEPARATOR") end,
    combatSafe = false,
})

RegisterUnitNumberSetting("boss", "spacing", "spacing", "Boss Spacing", -36, -400, 0, MakeAliases("boss", "spacing", "frame spacing"), {
    category = "Boss Layout",
    applyOpts = { preview = true },
})
RegisterUnitEnum("boss", "bossLayoutMode", "bossLayoutMode", "Boss Frame Layout", "VERTICAL_DOWN", BOSS_LAYOUT_VALUES, MakeAliases("boss", "frame layout", "layout"), {
    category = "Boss Layout",
    valueAliases = BOSS_LAYOUT_ALIASES,
    get = function()
        return NormalizeBossLayoutMode(UnitDB("boss").bossLayoutMode)
    end,
    set = function(_, value)
        local conf = UnitDB("boss")
        conf.bossLayoutMode = NormalizeBossLayoutMode(value)
        conf.invertBossOrder = nil
    end,
    applyOpts = { preview = true },
})


local POSITION_FIELDS = { "offsetX", "offsetY", "point", "relativePoint", "anchorFrameName", "anchorToUnitframe" }

local function ResetUnitPositionFromDefaults(unit, defaults)
    local src = type(defaults) == "table" and defaults[unit] or nil
    if type(src) ~= "table" then return false end
    local dst = UnitDB(unit)
    for i = 1, #POSITION_FIELDS do
        local key = POSITION_FIELDS[i]
        dst[key] = src[key]
    end
    return true
end

Registry:RegisterAction({
    key = "reset_unit_status_indicator",
    label = "Reset Unit Status Indicator",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    aliases = { "reset selected status indicator", "reset status indicator", "reset status icon", "reset unit status icon" },
    run = function(args)
        local unit = args and args.unit
        local spec = ResolveUnitStatusSpec(unit, args and (args.status or args.text))
        if type(unit) ~= "string" or not spec then
            return false, "I do not know which status indicator to reset."
        end

        local conf = UnitDB(unit)
        if spec.inlineName then
            conf[spec.x] = nil
            conf[spec.y] = nil
            conf[spec.anchor] = nil
            conf.raidGroupNameStyle = nil
        else
            conf[spec.x] = nil
            conf[spec.y] = nil
            conf[spec.anchor] = nil
            conf[spec.size] = nil
            conf[spec.layer] = nil
            if spec.symbol then conf[spec.symbol] = nil end
            if spec.iconStyle then conf[spec.iconStyle] = nil end
        end
        ApplyStatusRefresh(unit, spec.refresh, spec.statusRuntime, spec.level)
        return true, "Done. Reset " .. tostring(UNIT_LABELS[unit] or unit) .. " " .. tostring(spec.label or "status indicator") .. "."
    end,
})

Registry:RegisterAction({
    key = "preview_unit_status_indicator",
    label = "Preview Unit Status Indicator",
    type = "preview",
    combatSafe = true,
    aliases = { "preview current status indicator", "show all status indicators", "preview status icon", "show all status icons" },
    run = function(args)
        local mode = args and args.mode == "all" and "all" or "current"
        local unit = args and args.unit
        local spec = ResolveUnitStatusSpec(unit, args and (args.status or args.text))
        CallGlobal("MSUF_UFPreview_SetStatusPreviewMode", mode)
        if mode == "current" and spec then CallGlobal("MSUF_UFPreview_SelectStatusIcon", spec.value) end
        if mode == "all" then return true, "Done. Showing all status indicators in the preview." end
        return true, "Done. Previewing " .. tostring(spec and spec.label or "the current status indicator") .. "."
    end,
})

Registry:RegisterAction({
    key = "clear_unit_custom_anchor",
    label = "Clear Unit Custom Anchor",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    aliases = { "clear custom anchor", "clear custom anchor frame", "reset custom anchor", "remove custom anchor" },
    run = function(args)
        local unit = args and args.unit
        if type(unit) ~= "string" then return false, "I do not know which custom anchor to clear." end
        local conf = UnitDB(unit)
        local allowed = AllowedMap(ANCHOR_TARGET_VALUES)
        conf.anchorFrameName = nil
        if type(conf.anchorToUnitframe) == "string" and conf.anchorToUnitframe ~= "" and not allowed[conf.anchorToUnitframe] then
            conf.anchorToUnitframe = "GLOBAL"
        end
        ApplyUnit(unit, "MSUF_ASSISTANT_CLEAR_CUSTOM_ANCHOR", { preview = true })
        return true, "Done. Cleared " .. tostring(UNIT_LABELS[unit] or unit) .. " custom anchor."
    end,
})

local UNIT_COPY_SCOPE_LABELS = {
    { key = "basics", label = "Frame Basics" },
    { key = "text", label = "Text" },
    { key = "portrait", label = "Portrait" },
    { key = "power", label = "Power Bar" },
    { key = "castbar", label = "Castbar" },
    { key = "status", label = "Status Icons" },
    { key = "load", label = "Load Conditions" },
    { key = "transparency", label = "Transparency" },
    { key = "layout", label = "Size & Anchoring" },
}

local function UnitCopyScopeSummary(scopes)
    if type(scopes) ~= "table" then return "" end
    local selected, total = {}, 0
    for i = 1, #UNIT_COPY_SCOPE_LABELS do
        local row = UNIT_COPY_SCOPE_LABELS[i]
        total = total + 1
        if scopes[row.key] == true then selected[#selected + 1] = row.label end
    end
    if #selected == 0 then return " No copy categories were selected." end
    if #selected == total then return " Categories: all unit copy categories." end
    return " Categories: " .. table.concat(selected, ", ") .. "."
end

Registry:RegisterAction({
    key = "copy_unit",
    label = "Copy Unit Settings",
    type = "copy",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local src = args and args.source
        local targets = args and args.targets
        if type(src) ~= "string" or type(targets) ~= "table" or #targets == 0 then
            return false, "Copy needs a source and at least one destination."
        end
        local UP = M and M.UnitPage
        if not (UP and type(UP.CopyUnitSettings) == "function") then
            return false, "Unit copy is not available yet."
        end
        local targetLabels = {}
        for i = 1, #targets do
            UP.CopyUnitSettings(src, targets[i], args.scopes)
            targetLabels[#targetLabels + 1] = tostring(UNIT_LABELS[targets[i]] or targets[i])
        end
        local targetText = table.concat(targetLabels, ", ")
        if targetText == "" then targetText = "the selected destination" end
        return true, "Done. I copied " .. tostring(UNIT_LABELS[src] or src) .. " settings to " .. targetText .. "." .. UnitCopyScopeSummary(args and args.scopes)
    end,
})

Registry:RegisterAction({
    key = "reset_unit_position",
    label = "Reset Unit Position",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local unit = args and args.unit
        if type(unit) ~= "string" then return false, "I do not know which frame position to reset." end
        local create = (type(MSUF) == "table" and MSUF.MSUF_CreateFactoryDefaultProfile) or _G.MSUF_CreateFactoryDefaultProfile
        if type(create) ~= "function" then return false, "Factory defaults are not available yet." end
        local defaults = create()
        if not ResetUnitPositionFromDefaults(unit, defaults) then return false, "No default position is known for " .. tostring(UNIT_LABELS[unit] or unit) .. "." end
        ApplyUnit(unit, "MSUF_ASSISTANT_RESET_POSITION", { preview = true })
        return true, "Done. Reset " .. tostring(UNIT_LABELS[unit] or unit) .. " frame position."
    end,
})

Registry:RegisterAction({
    key = "reset_all_unit_positions",
    label = "Reset All Unit Positions",
    type = "reset",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    run = function()
        local create = (type(MSUF) == "table" and MSUF.MSUF_CreateFactoryDefaultProfile) or _G.MSUF_CreateFactoryDefaultProfile
        if type(create) ~= "function" then return false, "Factory defaults are not available yet." end
        local defaults = create()
        local count = 0
        for i = 1, #UNIT_KEYS do
            local unit = UNIT_KEYS[i]
            if ResetUnitPositionFromDefaults(unit, defaults) then
                ApplyUnit(unit, "MSUF_ASSISTANT_RESET_ALL_POSITIONS", { preview = true })
                count = count + 1
            end
        end
        if count == 0 then return false, "No default frame positions are available." end
        CallGlobal("MSUF_ForceReanchorAllUnitFrames_Once")
        return true, "Done. Reset " .. tostring(count) .. " unit-frame positions."
    end,
})

Registry:RegisterAction({
    key = "reset_unit_page",
    label = "Reset Unit Settings",
    type = "reset",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    run = function(args)
        local unit = args and args.unit
        local page = unit and ("uf_" .. unit)
        if unit == "targettarget" then page = "uf_targettarget" end
        if unit == "focustarget" then page = "uf_focustarget" end
        if type(page) ~= "string" or not (M and type(M.ResetPageToDefaults) == "function") then
            return false, "Unit reset is not available right now."
        end
        if M.ResetPageToDefaults(page) then
            return true, "Done. Reset " .. tostring(UNIT_LABELS[unit] or unit) .. " settings."
        end
        return false, "Reset failed."
    end,
})
